extends Node
## GameManager — autoload singleton for global game state.
## 双得分制 (#385): 纯数据持有 + 终局判定 + 查询 API。
## 拆砖分/穿墙分/出界分统一经 add_score(winner, amount, kind) 进入；
## 任一方总分先到 WIN_SCORE(21) → match_over 终局（AC3）。
## 移除局/比赛分层（games_won/get_winner/game_won 信号，21 分制无「局」概念）。
##
## Design: docs/DESIGN/293-game-manager-global-state.md + docs/DESIGN/385-dual-scoring-system.md §2.2
## Parent Issue: #293, #385

# ── Configuration (via GameConstants #295 / Dual Scoring #385) ──
const CONSTS = preload("res://gdscripts/constants.gd")
const WIN_SCORE: int = CONSTS.WIN_SCORE

# ── Signals ──
signal score_changed(player_score: int, ai_score: int)
signal match_over(winner: String)     # "player" | "ai" — 21 分终局（复用既有信号名，FSM/结算屏零新接线）

# ── Game Mode (#543) ──
## 本地双人对战模式状态（DESIGN 543 §3.2）。默认 SINGLE（与 StartMenu _mode_index 同值对齐）。
enum GameMode { SINGLE = 0, LOCAL_2P = 1 }

## 顶侧挡板 player_index（2P 下 P2 映射 "ai" 侧，PRD §3.3 对手语义复用）
const MODE_P2_TOP_INDEX: int = 1

var game_mode: GameMode = GameMode.SINGLE   # reset_match() 不触碰 — 重开保留上次选择

# ── Wave Cycle (#386) ──
enum WaveState { IDLE, RUNNING, SETTLED }

signal wave_started(wave_index: int)   # 新一波开始（#390 转场「第 N 道墙」/ #393 HUD，AC3）
signal wave_settled(wave_index: int)   # 墙清空结算挂点（#388 升级 UI 触发时机）
signal brick_scored(side: String)      # 拆砖分（kind == "brick"，#392 霓虹 HUD 按类信号）
signal pierce_scored(side: String)     # 穿墙分（kind == "pierce"，#392 霓虹 HUD 按类信号）
# game_won 信号已删除（21 分制无「局」概念；HUD/FSM/结算屏均不消费）

# ── State ──
var player_score: int = 0
var ai_score: int = 0
var player_brick_count: int = 0
var ai_brick_count: int = 0
var player_pierce_count: int = 0
var ai_pierce_count: int = 0
var _is_run_over: bool = false        # 终局守卫（防终局后事件泄漏）

var wave_index: int = 0                # 当前波次号：IDLE 期 0，首次 begin_wave() 后从 1 递增（AC3）
var wave_state: WaveState = WaveState.IDLE

# ── API ──

func add_score(winner: String, amount: int = 1, kind: String = "boundary") -> void:
	# kind: "boundary" | "brick" | "pierce"
	if _is_run_over:
		return                       # 终局后直接 return（失败路径 2）
	if amount <= 0:
		return
	match winner:
		"player":
			player_score += amount
			_bump_count("player", kind)
		"ai":
			ai_score += amount
			_bump_count("ai", kind)
		_:
			return                   # 非法 winner：无状态变更、无信号（保持 TC5 语义）
	_emit_class_signals(winner, kind)       # #392: 按类信号（brick_scored / pierce_scored）
	score_changed.emit(player_score, ai_score)
	_check_run_end()


func get_brick_count(side: String) -> int:    # AC5
	return player_brick_count if side == "player" else ai_brick_count


func get_pierce_count(side: String) -> int:   # AC5
	return player_pierce_count if side == "player" else ai_pierce_count


func get_wave_index() -> int:    # #391 AC2：失败屏波次数查询（wave_index 终局后保留供 run 统计）
	return wave_index


func is_run_over() -> bool:
	return _is_run_over


# ── Wave Cycle API (#386) ──

func begin_wave() -> void:
	wave_index += 1
	wave_state = WaveState.RUNNING
	wave_started.emit(wave_index)


func settle_wave() -> void:
	if wave_state == WaveState.IDLE:
		return
	wave_state = WaveState.SETTLED
	wave_settled.emit(wave_index)


func end_wave_cycle() -> void:
	wave_state = WaveState.IDLE   # AC5 停止；wave_index 保留供 run 统计（GAME_OVER 屏「波次数」归 #391）


func is_wave_cycle_active() -> bool:
	return wave_state != WaveState.IDLE


func reset_match() -> void:
	player_score = 0
	ai_score = 0
	player_brick_count = 0
	ai_brick_count = 0
	player_pierce_count = 0
	ai_pierce_count = 0
	_is_run_over = false
	wave_index = 0          # 波次重置（边界 1：首波从 1 起）
	wave_state = WaveState.IDLE


# ── Internal ──

## #543 模式 API：越界 clamp 回 SINGLE（防御性，A4）。
func set_game_mode(mode: int) -> void:
	if mode < GameMode.SINGLE or mode > GameMode.LOCAL_2P:
		game_mode = GameMode.SINGLE
	else:
		game_mode = mode


func get_game_mode() -> int:
	return game_mode


## #543 模式落盘：按 game_mode 配置 paddles 组 + InputMap 重建（DESIGN §3.2/§3.3）。
## 身份契约: 节点名 "AIPaddle" → 顶侧 P2（player_index 1），"PlayerPaddle" → P1（0），
## 其余节点按自身 player_index。组空/节点失效 → push_warning + 跳过（headless 容错）。
func apply_mode_to_paddles() -> void:
	if not is_inside_tree():
		return
	var paddles := get_tree().get_nodes_in_group("paddles")
	if paddles.is_empty():
		push_warning("GameManager: paddles group empty — mode config skipped (#543)")
		return
	for p in paddles:
		if not ("mode" in p and "player_index" in p):
			continue
		var idx: int = MODE_P2_TOP_INDEX if p.name == "AIPaddle" else 0
		if p.name != "AIPaddle" and p.name != "PlayerPaddle":
			idx = int(p.get("player_index"))
		if game_mode == GameMode.LOCAL_2P:
			p.mode = 0                     # 双板均 PLAYER
			p.player_index = idx
		else:
			if idx == MODE_P2_TOP_INDEX:
				p.mode = 1                 # 顶侧回写 AI（场景默认值，幂等）
			else:
				p.mode = 0
				p.player_index = 0
	load("res://gdscripts/paddle.gd").rebind_for_mode(int(game_mode))


func _emit_class_signals(winner: String, kind: String) -> void:   # #392 纯增量：boundary 不触发
	match kind:
		"brick":
			brick_scored.emit(winner)
		"pierce":
			pierce_scored.emit(winner)
		_:
			pass


func _bump_count(side: String, kind: String) -> void:
	match kind:
		"brick":
			if side == "player":
				player_brick_count += 1
			else:
				ai_brick_count += 1
		"pierce":
			if side == "player":
				player_pierce_count += 1
			else:
				ai_pierce_count += 1
		_:
			pass                     # "boundary" 不计数（出界分不是 run 统计项）


func _check_run_end() -> void:       # AC3：先到 21 者赢；单次事件只给一方加分，不存在同帧双方到 21
	if player_score >= WIN_SCORE:
		_is_run_over = true
		match_over.emit("player")
	elif ai_score >= WIN_SCORE:
		_is_run_over = true
		match_over.emit("ai")

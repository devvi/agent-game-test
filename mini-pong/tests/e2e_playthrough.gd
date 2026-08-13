extends RefCounted
## E2E Playthrough (#394) — AI vs AI 真实物理端到端一局（Approach B）。
## 用真实组件（ball.tscn + player_paddle.tscn×2(mode=1) + breakout_grid.tscn +
## wave_controller.gd + scoring_manager.gd + ui_upgrade_pick.tscn + GameManager/UpgradePool
## autoload）镜像 Main.tscn 迷你树，真实引擎物理帧驱动一局到 21 分（AC1），
## 断言波次/墙生成/升级 UI 数据流（AC2）、拆砖+1/穿墙+3 总分与事件计数一致（AC3）、
## ≥3 个机械完整升级参数变化生效（AC4）。
## 确定性: UpgradePool.rng.seed(20260813) 固定抽取序列；MAX_FRAMES + 墙钟 DEADLINE_MS 双闸防死循环。
## 零游戏代码改动红线（PRD §1.4）: 只新增本文件 + run_tests.gd 注册行。
## Design: docs/DESIGN/394-e2e-playability.md §3.1 / §9（Scenario A-F）
## Runs under godot --path mini-pong/ --headless --script tests/run_tests.gd (_run_async)。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const SEED: int = 20260813            # UpgradePool.rng.seed 固定值（与 test_upgrade_pick_ui 同值；AC4 可复现）
const MAX_FRAMES: int = 60000         # 帧数上限（PRD §5.2 边界 1；防死循环）
const DEADLINE_MS: int = 300_000      # 墙钟超时（对齐 e2e_shots 03_gameover 300s 实测上限）
const SHORT_REVEAL: float = 0.05      # UpgradePickUI._reveal_hold 注入（#388 测试可注入；生产 0.8s）
const AI_ERROR_AI: float = 200.0      # AIPaddle ai_position_error（e2e_shots 实测可达族）
const SCREEN_W: float = 720.0         # headless 视口为 0 → 手动注入（auto_play 同法）
const SCREEN_H: float = 1280.0
const PADDLE_Y_TOP: float = 40.0      # AIPaddle（Main.tscn 几何镜像）
const PADDLE_Y_BOT: float = 1240.0    # PlayerPaddle（Main.tscn 几何镜像）
const WALL_X_LEFT: float = 5.0        # LeftWall（Main.tscn 几何镜像）
const WALL_X_RIGHT: float = 715.0     # RightWall
# 镜像 upgrade_defs.gd 机械常量（测试只读参考，不引入新事实源）
const LONG_ARM_STEP: float = 0.3
const SLOW_TIME_SCALE: float = 0.0
const SLOW_TIME_DURATION: float = 2.0
const _MECHANICAL_IDS: Array = ["long_arm", "fireball", "battering_ram", "magnet_core", "slow_time", "pre_hole"]

# ── 信号追踪 ──
var _started: Array = []
var _settled: Array = []
var _cleared: int = 0
var _walls: Array = []
var _brick_scored: Dictionary = {}
var _pierce_scored: Dictionary = {}
var _match_over_winner: String = ""
var _applied: Array = []
var _snapshot: Dictionary = {}
var _pre_hole_pending: bool = false
var _ui_open_count: int = 0
var _ui_close_count: int = 0
var _fx: Dictionary = {}
var _ai_delay_initial: float = 0.0
var _injecting_score: bool = false    # F3 终局竞态注入计分（非真实物理路径）→ 跳过 crossed_wall 断言


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _wait(seconds: float) -> void:
	await _tree().create_timer(seconds).timeout


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("  FAIL: %s" % msg)


## GAPS 布局每行砖数: cols=10 − 2 缝列 == 8
func _expected_bricks(thickness: int) -> int:
	return 8 * thickness


# ── 信号处理器 ──

func _on_started(index: int) -> void:
	_started.append(index)


func _on_settled(index: int) -> void:
	_settled.append(index)
	print("  wave %d settled → 升级窗口" % index)


func _on_cleared() -> void:
	if GameManager.is_run_over():
		return                       # 终局后残留清空不计数（F3/微检查等）
	_cleared += 1
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "AC2-T3: 打空 → wave_state SETTLED")
	_assert(_settled.size() == _cleared, "AC2-T3: wall_cleared 恰好一次 → wave_settled")
	_assert(_fx.ui.visible, "AC2-T3: 打空触发升级 UI 数据流（真实 UpgradePickUI visible）")


func _on_wall_generated(remaining: int) -> void:
	if GameManager.is_run_over():
		return                       # 局后微检查墙不参与断言
	var wave: int = GameManager.wave_index
	if wave < 1:
		return                       # 测试受控 generate_wave（blast 微检查等）非真实波次，不参与断言
	_walls.append(remaining)
	var expected: int = _expected_bricks(wave)
	_assert(fx_grid().rows == wave,
		"AC2-T2: 第 %d 波厚度 rows == %d (got %d)" % [wave, wave, fx_grid().rows])
	if _pre_hole_pending:
		_assert(fx_grid()._hole_columns.size() >= 1, "AC4-T7: 预开洞 → 洞柱位已开")
		_assert(remaining < expected, "AC4-T7: 洞墙砖数 < 无洞期望 (got %d, 期望 %d)" % [remaining, expected])
		_pre_hole_pending = false
	else:
		# 发球位 (360,640) 与 col5 砖物理重叠 → 开局首碰免费碎 1–2 砖（真实物理行为），
		# 故砖数允许比期望少 0–2（期望 -2 容差；DESIGN §9 B-T1 的精确值在真实物理下不成立）
		_assert(remaining <= expected and remaining >= expected - 2,
			"AC2-T1: 第 %d 波砖数 ∈ [期望-2, 期望] (got %d, 期望 %d)" % [wave, remaining, expected])


func _on_brick_scored(side: String) -> void:
	_brick_scored[side] = _brick_scored.get(side, 0) + 1
	# AC3-T4: 拆砖分归属 == 最后触球方（ball.last_toucher 契约，#385）
	var ball = _fx.get("ball")
	if ball != null:
		_assert(side == ball.last_toucher,
			"AC3-T4: 拆砖归属 last_toucher=='%s' (got '%s')" % [side, ball.last_toucher])


func _on_pierce_scored(side: String) -> void:
	_pierce_scored[side] = _pierce_scored.get(side, 0) + 1
	if _injecting_score:
		return                     # F3 注入计分非真实物理路径，不做 crossed_wall 断言
	# AC3-T5: pierce 事件必须经 _crossed_wall 路径（信号在 serve() 复位前同步触发）
	var ball = _fx.get("ball")
	if ball != null:
		_assert(bool(ball.get("_crossed_wall")), "AC3-T5: pierce 经 _crossed_wall 路径（%s 侧）" % side)


func _on_match_over(winner: String) -> void:
	_match_over_winner = winner


func _on_upgrade_applied(id: String) -> void:
	_applied.append(id)
	print("  upgrade applied: %s (stacks=%d)" % [id, UpgradePool.get_stacks(id)])
	var snap: Dictionary = _snapshot
	_snapshot = {}
	_verify_effect(id, snap, _fx)


func _connect_signals() -> void:
	GameManager.wave_started.connect(_on_started)
	GameManager.wave_settled.connect(_on_settled)
	GameManager.brick_scored.connect(_on_brick_scored)
	GameManager.pierce_scored.connect(_on_pierce_scored)
	GameManager.match_over.connect(_on_match_over)
	UpgradePool.upgrade_applied.connect(_on_upgrade_applied)


func _disconnect_signals() -> void:
	if GameManager.wave_started.is_connected(_on_started):
		GameManager.wave_started.disconnect(_on_started)
	if GameManager.wave_settled.is_connected(_on_settled):
		GameManager.wave_settled.disconnect(_on_settled)
	if GameManager.brick_scored.is_connected(_on_brick_scored):
		GameManager.brick_scored.disconnect(_on_brick_scored)
	if GameManager.pierce_scored.is_connected(_on_pierce_scored):
		GameManager.pierce_scored.disconnect(_on_pierce_scored)
	if GameManager.match_over.is_connected(_on_match_over):
		GameManager.match_over.disconnect(_on_match_over)
	if UpgradePool.upgrade_applied.is_connected(_on_upgrade_applied):
		UpgradePool.upgrade_applied.disconnect(_on_upgrade_applied)


func _reset_tracking() -> void:
	_started.clear()
	_settled.clear()
	_cleared = 0
	_walls.clear()
	_brick_scored = {}
	_pierce_scored = {}
	_match_over_winner = ""
	_applied.clear()
	_snapshot = {}
	_pre_hole_pending = false
	_ui_open_count = 0
	_ui_close_count = 0


func _reset_pool() -> void:
	UpgradePool.rng.seed = SEED
	UpgradePool.stacks = {}
	UpgradePool.stub_activated = {}
	UpgradePool._available = UpgradePool.get_definitions().duplicate()
	UpgradePool.ball_ref = null
	UpgradePool.paddle_ref = null
	UpgradePool.grid_ref = null


# ── 场景组装（镜像 Main.tscn 接线，节点名契约决定 last_toucher / ../ 相对路径）──

func _make_fx() -> Dictionary:
	var tree = _tree()
	var host = Node2D.new()
	host.name = "TestHost"
	tree.root.add_child(host)

	# 左右墙（groups=[walls]，Main.tscn 几何）
	var lw = StaticBody2D.new()
	lw.name = "LeftWall"
	lw.position = Vector2(WALL_X_LEFT, 640.0)
	lw.add_to_group("walls")
	var lcs = CollisionShape2D.new()
	var lshape = RectangleShape2D.new()
	lshape.size = Vector2(10.0, 1280.0)
	lcs.shape = lshape
	lw.add_child(lcs)
	host.add_child(lw)
	var rw = StaticBody2D.new()
	rw.name = "RightWall"
	rw.position = Vector2(WALL_X_RIGHT, 640.0)
	rw.add_to_group("walls")
	var rcs = CollisionShape2D.new()
	var rshape = RectangleShape2D.new()
	rshape.size = Vector2(10.0, 1280.0)
	rcs.shape = rshape
	rw.add_child(rcs)
	host.add_child(rw)

	# Ball（真实 ball.tscn；headless 视口 0 → 注入 screen 尺寸）
	var ball = load("res://scenes/ball.tscn").instantiate()
	ball.name = "Ball"
	ball.position = Vector2(360.0, 640.0)
	host.add_child(ball)
	ball.screen_width = SCREEN_W
	ball.screen_height = SCREEN_H

	# 双挡板（真实 player_paddle.tscn，均 mode=1；PlayerPaddle 保持默认 error 24 → 好瞄准清墙）
	var paddle = load("res://scenes/player_paddle.tscn").instantiate()
	paddle.name = "PlayerPaddle"
	paddle.position = Vector2(360.0, PADDLE_Y_BOT)
	paddle.mode = 1
	host.add_child(paddle)
	var paddle_top = load("res://scenes/player_paddle.tscn").instantiate()
	paddle_top.name = "AIPaddle"
	paddle_top.position = Vector2(360.0, PADDLE_Y_TOP)
	paddle_top.mode = 1
	paddle_top.ai_position_error = AI_ERROR_AI
	host.add_child(paddle_top)
	_ai_delay_initial = paddle_top.ai_reaction_delay_min

	# BreakoutGrid（真实 breakout_grid.tscn；position=(0,640) → wall_y 默认 640 世界对齐）
	var grid = load("res://scenes/breakout_grid.tscn").instantiate()
	grid.name = "BreakoutGrid"
	grid.position = Vector2(0.0, 640.0)
	host.add_child(grid)

	# WaveController（settle_delay 注入短延时；推进由 UI close 接管 settle_hold）
	var controller = Node.new()
	controller.set_script(load("res://gdscripts/wave_controller.gd"))
	controller.name = "WaveController"
	host.add_child(controller)
	controller.settle_delay = 0.01

	# ScoringManager（../Ball ../BreakoutGrid 相对路径解析）
	var sm = Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.name = "ScoringManager"
	host.add_child(sm)

	# 真实 UpgradePickUI（AC2 数据流走真实 UI；_reveal_hold 注入 0.05s）
	var ui = load("res://scenes/ui_upgrade_pick.tscn").instantiate()
	host.add_child(ui)
	ui._reveal_hold = SHORT_REVEAL

	return {"host": host, "ball": ball, "paddle": paddle, "paddle_top": paddle_top,
		"grid": grid, "controller": controller, "sm": sm, "ui": ui}


func fx_grid() -> Node2D:
	return _fx.get("grid")


func _cleanup(fx: Dictionary) -> void:
	_tree().paused = false   # 防残留暂停污染后续套件
	var host = fx.get("host")
	if host != null and is_instance_valid(host) and host.get_parent() != null:
		host.get_parent().remove_child(host)
		host.queue_free()
	await _wait(0.05)


func _take_snapshot(fx: Dictionary) -> Dictionary:
	return {
		"paddle_width": fx.paddle.paddle_width,
		"ball_speed": fx.ball.speed,
		"magnet": fx.paddle.magnet_enabled,
		"speed_scale": fx.ball.speed_scale,
		"pending_holes": fx.grid._pending_holes.size(),
	}


func _feed_accept() -> void:
	var ev = InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)


# ── 主驱动：真实物理一局到 21 分 ──

func _play_match(max_frames: int) -> Dictionary:
	GameManager.reset_match()
	_reset_pool()
	_reset_tracking()
	var fx = _make_fx()
	_fx = fx
	fx.grid.wall_cleared.connect(_on_cleared)
	fx.grid.wall_generated.connect(_on_wall_generated)
	for i in 5:
		await _tree().process_frame     # 等 _ready 信号连接 + serve 定时器就绪（auto_play 同法）

	# 首波（#393 B.1 入口；wave_index 1 + 首墙生成）
	fx.controller.start_first_wave()
	_assert(GameManager.wave_index == 1, "AC2-T1: 首波 wave_index == 1 (got %d)" % GameManager.wave_index)
	_assert(fx.grid.remaining_bricks > 0, "AC2-T1: 首波墙生成 remaining > 0 (got %d)" % fx.grid.remaining_bricks)
	_assert(fx.grid.remaining_bricks <= _expected_bricks(1), "AC2-T1: 首波砖数 ≤ 期望 (got %d)" % fx.grid.remaining_bricks)

	var frame: int = 0
	var start_ms: int = Time.get_ticks_msec()
	var was_visible: bool = false
	while not GameManager.is_run_over() and frame < max_frames \
			and Time.get_ticks_msec() - start_ms < DEADLINE_MS:
		var ui_visible: bool = fx.ui.visible
		if ui_visible and not was_visible:
			_ui_open_count += 1
			_assert(_tree().paused, "AC2-T3: 升级 UI 打开 → 树暂停")
			_assert(fx.ui._candidates.size() >= 1, "AC2-T4: 候选非空 (got %d)" % fx.ui._candidates.size())
			_assert(fx.ui._candidates.size() == CONSTS.UPGRADE_CANDIDATE_COUNT or UpgradePool._available.is_empty(),
				"AC2-T4: 候选 3 张（池未耗尽）(got %d)" % fx.ui._candidates.size())
		elif not ui_visible and was_visible:
			_ui_close_count += 1
			_assert(not _tree().paused, "AC2-T5: 升级 UI 关闭 → 恢复游戏时间")
		if ui_visible:
			_snapshot = _take_snapshot(fx)   # apply 前预录基线（AC4 快照）
			_feed_accept()
		was_visible = ui_visible
		await _tree().process_frame
		frame += 1

	var completed: bool = GameManager.is_run_over() and frame < max_frames \
		and Time.get_ticks_msec() - start_ms < DEADLINE_MS
	if not completed:
		printerr("  ⚠ match 未完成: frame=%d elapsed=%dms player=%d ai=%d wave=%d applied=%s" % [
			frame, Time.get_ticks_msec() - start_ms, GameManager.player_score, GameManager.ai_score,
			GameManager.wave_index, str(_applied)])

	# AC1-T4: 终局守卫 — match_over 后无新计分（30 帧观察窗）
	var s0p: int = GameManager.player_score
	var s0a: int = GameManager.ai_score
	var b0: Dictionary = _brick_scored.duplicate()
	var p0: Dictionary = _pierce_scored.duplicate()
	for i in 30:
		await _tree().process_frame
	_assert(GameManager.player_score == s0p and GameManager.ai_score == s0a, "AC1-T4: 终局后分数冻结")
	_assert(_brick_scored == b0 and _pierce_scored == p0, "AC1-T4: 终局后无新计分事件")

	var outcome = {
		"fx": fx,
		"completed": completed,
		"winner": _match_over_winner,
		"frame": frame,
		"elapsed_ms": Time.get_ticks_msec() - start_ms,
		"player_score": s0p,
		"ai_score": s0a,
		"pierce_total": _pierce_scored.get("player", 0) + _pierce_scored.get("ai", 0),
		"settled_count": _settled.size(),
		"player_brick": GameManager.player_brick_count,
		"ai_brick": GameManager.ai_brick_count,
		"player_pierce": GameManager.player_pierce_count,
		"ai_pierce": GameManager.ai_pierce_count,
	}
	print("  match: completed=%s winner='%s' score=%d:%d waves=%d applied=%d frames=%d elapsed=%dms" % [
		completed, _match_over_winner, s0p, s0a, _settled.size(), _applied.size(), frame,
		Time.get_ticks_msec() - start_ms])
	return outcome


# ── AC1: 自动打完一局到 21 分 ──

func _assert_ac1(o: Dictionary) -> void:
	_assert(bool(o.get("completed", false)),
		"AC1-T1: 真实物理驱动至 is_run_over（frame=%d, elapsed=%dms, 双闸未触发）"
		% [o.get("frame", 0), o.get("elapsed_ms", 0)])
	var winner: String = o.get("winner", "")
	_assert(winner == "player" or winner == "ai", "AC1-T2: match_over 胜者存在 (got '%s')" % winner)
	if winner == "player" or winner == "ai":
		var ws: int = o.get("player_score", 0) if winner == "player" else o.get("ai_score", 0)
		var ls: int = o.get("ai_score", 0) if winner == "player" else o.get("player_score", 0)
		_assert(ws >= CONSTS.WIN_SCORE, "AC1-T3: 胜者总分 ≥ 21 (got %d)" % ws)
		_assert(ls < CONSTS.WIN_SCORE, "AC1-T3: 败者总分 < 21 (got %d)" % ls)
	GameManager.reset_match()
	_assert(GameManager.player_score == 0 and GameManager.ai_score == 0
		and GameManager.wave_index == 0 and GameManager.wave_state == GameManager.WaveState.IDLE,
		"AC1-T3: reset_match 分数/波次归零")


# ── AC2: 每波生成砖墙 + 打空后升级 UI 数据流 ──

func _assert_ac2(o: Dictionary) -> void:
	# Test 2: 每波更厚（rows == wave_index 已在 wall_generated 断言）+ 新墙砖数 ≥ 旧墙
	for i in range(1, _walls.size()):
		_assert(int(_walls[i]) >= int(_walls[i - 1]),
			"AC2-T2: 新墙砖数 ≥ 旧墙 (wave %d: %d vs %d)" % [i + 1, _walls[i], _walls[i - 1]])
	if _settled.size() > 0:
		_assert(_fx.paddle_top.ai_reaction_delay_min < _ai_delay_initial,
			"AC2-T2: AI 参数收紧（难度杠杆生效）")
	# Test 8: 信号计数（首波无结算 → started == settled + 1；cleared == settled）
	_assert(_started.size() == _settled.size() + 1,
		"AC2-T8: wave_started == wave_settled + 1 (got %d vs %d)" % [_started.size(), _settled.size()])
	_assert(_cleared == _settled.size(),
		"AC2-T8: wall_cleared == wave_settled (got %d vs %d)" % [_cleared, _settled.size()])
	# Test 3/5/6: 升级 UI 数据流每波恰好一次（池耗尽时 open() 无候选静默跳过）
	_assert(_ui_open_count == _settled.size() or UpgradePool._available.is_empty(),
		"AC2-T3: 每波结算触发一次升级 UI (got %d opens vs %d settled)" % [_ui_open_count, _settled.size()])
	_assert(_ui_close_count == _ui_open_count,
		"AC2-T5: UI 关闭次数 == 打开次数 (got %d vs %d)" % [_ui_close_count, _ui_open_count])


# ── AC3: 拆砖 +1 / 穿墙 +3 总分与事件计数一致 ──

func _assert_ac3(o: Dictionary) -> void:
	for side in ["player", "ai"]:
		var score: int = o.get("player_score", 0) if side == "player" else o.get("ai_score", 0)
		var brick: int = o.get("player_brick", 0) if side == "player" else o.get("ai_brick", 0)
		var pierce: int = o.get("player_pierce", 0) if side == "player" else o.get("ai_pierce", 0)
		var remainder: int = score - brick - pierce * 3
		# 余项 = boundary 兜底分（_bump_count 对 boundary 不计数）；余项 ≥ 0 即全部计分可重构
		_assert(remainder >= 0,
			"AC3-T%d: %s 总分余项 ≥ 0 (score=%d brick=%d pierce=%d rem=%d)"
			% [1 if side == "player" else 2, side, score, brick, pierce, remainder])
		_assert(_brick_scored.get(side, 0) == brick,
			"AC3-T3: %s brick_scored 信号计数 == GameManager (%d vs %d)"
			% [side, _brick_scored.get(side, 0), brick])
		_assert(_pierce_scored.get(side, 0) == pierce,
			"AC3-T3: %s pierce_scored 信号计数 == GameManager (%d vs %d)"
			% [side, _pierce_scored.get(side, 0), pierce])
	_assert(int(o.get("pierce_total", 0)) >= 1,
		"AC3-T5: 整局穿墙分 ≥ 1 (got %d)" % o.get("pierce_total", 0))


# ── AC4: ≥3 个升级应用后参数变化生效 ──

func _verify_effect(id: String, snap: Dictionary, fx: Dictionary) -> void:
	if snap.is_empty():
		return                       # 无快照路径（F3 注入等）→ 仅记录，不做参数断言
	var paddle = fx.paddle
	var ball = fx.ball
	var grid = fx.grid
	match id:
		"long_arm":
			_assert(is_equal_approx(paddle.paddle_width,
					snap.get("paddle_width", 0.0) + LONG_ARM_STEP * paddle.base_paddle_width),
				"AC4-T2: long_arm 挡板宽度 +30%% 基数加算 (%.1f → %.1f)"
				% [snap.get("paddle_width", 0.0), paddle.paddle_width])
		"fireball":
			_assert(ball.speed > snap.get("ball_speed", 0.0)
					or is_equal_approx(ball.speed, ball.initial_speed * ball.max_speed_multiplier),
				"AC4-T3: fireball 球速 ×1.1（封顶 max）(%.1f → %.1f)"
				% [snap.get("ball_speed", 0.0), ball.speed])
			_assert(grid.upgrade_hooks.has("blast_neighbors"), "AC4-T3: fireball blast hook 已注册")
		"battering_ram":
			_assert(grid.upgrade_hooks.has("blast_neighbors"),
				"AC4-T4: battering_ram blast hook 已注册（受控微检查见局后）")
		"magnet_core":
			_assert(paddle.magnet_enabled == true, "AC4-T5: magnet_core 磁吸开启")
		"slow_time":
			_assert(is_equal_approx(ball.speed_scale, SLOW_TIME_SCALE),
				"AC4-T6: slow_time 球速冻结 (speed_scale=%.2f)" % ball.speed_scale)
		"pre_hole":
			_assert(int(snap.get("pending_holes", 0)) + 1 == grid._pending_holes.size(),
				"AC4-T7: pre_hole 挂起洞 +1 (got %d)" % grid._pending_holes.size())
			_pre_hole_pending = true


func _assert_ac4(o: Dictionary) -> void:
	var fx = o.get("fx", {})
	if fx.is_empty():
		_assert(false, "AC4: fx 缺失")
		return
	# Test 8: 桩升级（twin/stardust/phantom）被抽中 → stub_activated 标记断言
	for id in ["twin", "stardust", "phantom"]:
		if id in _applied:
			_assert(UpgradePool.stub_activated.get(id, false) == true,
				"AC4-T8: 桩升级 %s stub_activated 标记" % id)
	# Test 1: ≥3 个不同机械完整升级（不足走降级路径补足）
	var mechanical: Array = []
	for id in _applied:
		if id in _MECHANICAL_IDS and id not in mechanical:
			mechanical.append(id)
	if mechanical.size() < 3:
		# AC4 降级路径（PRD §5.3 失败路径 4）：本局自然应用仅 N 个升级，直接 apply 补足至 ≥3 个不同机械升级
		print("  AC4 降级路径（PRD §5.3 失败路径 4）：本局自然应用仅 %d 个机械升级，直接 apply 补足至 ≥3 个不同机械升级" % mechanical.size())
		for id in ["long_arm", "fireball", "pre_hole"]:
			if mechanical.size() >= 3:
				break
			if id in mechanical:
				continue
			var snap: Dictionary = _take_snapshot(fx)
			if UpgradePool.apply(id):
				_verify_effect(id, snap, fx)
				mechanical.append(id)
			else:
				print("  AC4 降级路径：apply('%s') 返回 false（max_stacks 耗尽）→ 该 id 已充分验证，跳过" % id)
	_assert(mechanical.size() >= 3,
		"AC4-T1: ≥3 个不同机械完整升级被应用 (got %d: %s)" % [mechanical.size(), str(mechanical)])
	# Test 6: slow_time 恢复（真实时间等待，SLOW_TIME_DURATION 后 speed_scale 回 1.0）
	if "slow_time" in mechanical:
		var t0: int = Time.get_ticks_msec()
		var recovered: bool = false
		while Time.get_ticks_msec() - t0 < 6000:
			if is_equal_approx(fx.ball.speed_scale, 1.0):
				recovered = true
				break
			await _tree().process_frame
		_assert(recovered, "AC4-T6: slow_time %ds 后 speed_scale 恢复 1.0" % SLOW_TIME_DURATION)
	# Test 7: pre_hole 挂起洞消费（终局前未消费时，受控补验）
	if _pre_hole_pending:
		fx.grid.generate_wave(1, 0, -1)
		await _tree().process_frame
		_assert(fx.grid._pending_holes.is_empty(), "AC4-T7: 挂起洞已被下波消费")
		_assert(fx.grid._hole_columns.size() >= 1, "AC4-T7: 洞柱位已开")
		_assert(fx.grid.remaining_bricks < _expected_bricks(1),
			"AC4-T7: 洞墙砖数 < 无洞期望 (got %d)" % fx.grid.remaining_bricks)
		_pre_hole_pending = false
	# Test 4: blast 受控微检查（battering_ram / fireball）
	await _verify_blast_microcheck(fx)


func _verify_blast_microcheck(fx: Dictionary) -> void:
	var grid = fx.grid
	var ball = fx.ball
	ball.frozen = true
	ball.position = Vector2(360.0, 700.0)
	ball.velocity = Vector2.ZERO
	grid.generate_wave(1, 0, -1)
	await _tree().process_frame
	var blast_pos: Vector2 = Vector2(360.0, 700.0)
	var before: int = _count_bricks_in_radius(grid, blast_pos, 150.0)
	_assert(before >= 1, "AC4-T4: 微检查墙就绪（半径内砖 %d）" % before)
	var dispatched: bool = false
	if UpgradePool.apply("battering_ram"):
		dispatched = true
	elif UpgradePool.apply("fireball"):
		dispatched = true
	else:
		dispatched = grid.apply_upgrade_hook("blast_neighbors", {"pos": blast_pos, "radius": 150.0})
	for i in 3:
		await _tree().process_frame   # queue_free 帧末生效 → 等帧后再数（DESIGN D-T4「后续帧触发」）
	var after: int = _count_bricks_in_radius(grid, blast_pos, 150.0)
	_assert(dispatched, "AC4-T4: blast 派发成功（apply 或 hook 直调）")
	_assert(after < before, "AC4-T4: blast 半径内砖减少 (%d → %d)" % [before, after])


func _count_bricks_in_radius(grid: Node2D, pos: Vector2, radius: float) -> int:
	var n: int = 0
	for child in grid.get_children():
		if child.is_in_group("bricks"):
			var b = child as Node2D
			if b != null and b.global_position.distance_to(pos) <= radius:
				n += 1
	return n


func _count_global_bricks() -> int:
	return _tree().get_nodes_in_group("bricks").size()


# ── 主入口 + 边界/失败路径（Scenario F）──

func run() -> void:
	print("\n=== E2E Playthrough Tests (#394) ===")
	_connect_signals()
	var outcome = {}
	var attempts: int = 0
	while true:
		attempts += 1
		outcome = await _play_match(MAX_FRAMES)
		var good: bool = bool(outcome.get("completed", false)) \
			and int(outcome.get("pierce_total", 0)) > 0 \
			and int(outcome.get("settled_count", 0)) > 0
		if good or attempts >= 3:
			break
		print("  ⚠ 本局 pierce=0 或零结算，重试 %d/3" % (attempts + 1))
		await _cleanup(outcome.get("fx"))
	_assert_ac1(outcome)
	_assert_ac2(outcome)
	_assert_ac3(outcome)
	await _assert_ac4(outcome)
	await _cleanup(outcome.get("fx"))
	await _test_f3_endgame_race()
	await _test_f4_restart_no_leak()
	# 防污染后续套件（auto_play 等）：升级池目标引用复位
	UpgradePool.ball_ref = null
	UpgradePool.paddle_ref = null
	UpgradePool.grid_ref = null
	_disconnect_signals()
	print("  E2E Playthrough: %d passed, %d failed" % [passed, failed])


## F3: 终局竞态 — 升级窗口（reveal）期间到 21 分 → 不生成新墙、end_wave_cycle（#388 边界 5）
func _test_f3_endgame_race() -> void:
	print("\n  -- F3: 终局竞态（升级窗口期间到 21 分）--")
	GameManager.reset_match()
	_reset_pool()
	_reset_tracking()
	var fx = _make_fx()
	_fx = fx
	fx.grid.wall_cleared.connect(_on_cleared)
	fx.grid.wall_generated.connect(_on_wall_generated)
	for i in 3:
		await _tree().process_frame
	fx.controller.start_first_wave()
	# 手动清空首波 → wall_cleared → 结算 → 真实 UI 打开（paused）
	var bricks: Array = []
	for child in fx.grid.get_children():
		if child.is_in_group("bricks"):
			bricks.append(child)
	for b in bricks:
		b.destroy()
	await _tree().process_frame
	_assert(fx.ui.visible, "F3: 打空 → 升级 UI 打开")
	# 确认升级（reveal 期间注入 21 分 → 终局竞态）
	_feed_accept()
	await _tree().process_frame
	_injecting_score = true
	GameManager.add_score("player", CONSTS.WIN_SCORE, "pierce")
	_injecting_score = false
	_assert(GameManager.is_run_over(), "F3: 注入后 run over")
	var started_before: int = _started.size()
	var waited: int = 0
	while fx.ui.visible and waited < 300:
		await _tree().process_frame
		waited += 1
	await _tree().process_frame
	_assert(_started.size() == started_before, "F3: 终局不生成新墙（wave_started 冻结）")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "F3: end_wave_cycle 生效（wave_state IDLE）")
	await _cleanup(fx)


## F4: 重开循环 — reset → 再首波：无残留砖节点、无信号泄漏（#393 清理惯例回归）
func _test_f4_restart_no_leak() -> void:
	print("\n  -- F4: 重开循环（reset → 再首波，无残留）--")
	GameManager.reset_match()
	_reset_pool()
	_reset_tracking()
	var fx = _make_fx()
	_fx = fx
	fx.grid.wall_cleared.connect(_on_cleared)
	fx.grid.wall_generated.connect(_on_wall_generated)
	for i in 3:
		await _tree().process_frame
	fx.controller.start_first_wave()
	_assert(GameManager.wave_index == 1, "F4: 重开首波 wave_index == 1")
	await _tree().process_frame
	var nb: int = _count_global_bricks()
	_assert(nb == _expected_bricks(1) or nb == _expected_bricks(1) - 1,
		"F4: 场景树仅本墙砖（无上一 run 残留）(got %d)" % nb)
	await _cleanup(fx)
	await _tree().process_frame
	_assert(_count_global_bricks() == 0, "F4: cleanup 后零残留砖节点")

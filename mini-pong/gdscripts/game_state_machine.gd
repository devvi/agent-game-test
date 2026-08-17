extends Node
## GameStateMachine — scene-level FSM for mini-pong runtime orchestration.
## 6-state machine: MENU → SERVING → PLAYING ⇌ PAUSED → SCORED → GAME_OVER → MENU.
## Pause added per #296: Escape toggles PLAYING ↔ PAUSED.
## Centralizes input routing, paddle freeze, UI visibility, and serve timing.
## Uses @onready node references, enum State + match dispatch, await timers.
##
## Design: docs/DESIGN/294-game-state-machine.md §2.1
## Parent Issue: #294

enum State {
	MENU,
	SERVING,
	PLAYING,
	PAUSED,
	SCORED,
	GAME_OVER
}

# ── Internal State ──
var current_state: State = State.MENU
var previous_state: State = State.MENU
var _transition_lock: bool = false
var _scored_timer_active: bool = false

# ── @onready Node References (set via Main.tscn node_path exports) ──
@onready var start_menu: CanvasLayer = $"../StartMenu"
@onready var game_hud: CanvasLayer = $"../GameHUD"
@onready var game_over_screen: CanvasLayer = $"../GameOverScreen"
@onready var ball: Area2D = $"../Ball"
@onready var player_paddle: Area2D = $"../PlayerPaddle"
@onready var ai_paddle: Area2D = $"../AIPaddle"
@onready var scoring_manager: Node = $"../ScoringManager"
@onready var pause_overlay: CanvasLayer = $"../PauseOverlay"


# ── Lifecycle ──

func _ready() -> void:
	# Validate all node references (log warnings for nulls, no crash)
	_validate_references()

	# Connect to ScoringManager.scored signal
	if scoring_manager and scoring_manager.has_signal("scored"):
		scoring_manager.scored.connect(_on_scored)

	# Connect to GameManager.match_over (global autoload signal)
	if is_instance_valid(GameManager):
		if GameManager.has_signal("match_over"):
			GameManager.match_over.connect(_on_match_over)

	# Initialize in MENU state
	enter_state(State.MENU)

	# #508 失败路径缓解（PRD §5.3-1）: 组空 → push_warning, 不崩溃
	var tree = get_tree() if is_inside_tree() else null
	if tree != null and tree.get_nodes_in_group("game_world").is_empty():
		push_warning("FSM: group 'game_world' is empty — title world hiding disabled (#508)")


func _input(event: InputEvent) -> void:
	# Pause toggle: Escape toggles PLAYING ↔ PAUSED
	if event.is_action_pressed("ui_cancel"):
		match current_state:
			State.PLAYING:
				transition_to(State.PAUSED)
			State.PAUSED:
				transition_to(State.PLAYING)
		return  # consume event, don't fall through to ui_accept

	if not event.is_action_pressed("ui_accept"):
		return

	match current_state:
		State.MENU:
			if not _transition_lock:
				_transition_lock = true
				transition_to(State.SERVING)
		State.GAME_OVER:
			if not _transition_lock:
				_transition_lock = true
				transition_to(State.MENU)
		_:
			pass


# ── State Management ──

func transition_to(next: State) -> void:
	if next == current_state:
		return
	exit_state(current_state)
	previous_state = current_state
	current_state = next
	enter_state(next)


func enter_state(state: State) -> void:
	match state:
		State.MENU:
			_set_ui("start_menu")
			_freeze_paddles(true)
			# #508 补漏: 初始 MENU (previous==MENU, 刚启动) 冻结球 — 否则 ball._ready() 的
			# serve() 使球在 title 界面后台空转/出界循环。GAME_OVER→MENU 重开路径
			# (previous==GAME_OVER) 不冻结 — #391 AC4 要求退出 GAME_OVER 后球可动。
			if previous_state == State.MENU:
				_freeze_ball(true)
			_transition_lock = false
			_set_world_visible(false)   # #508: MENU 隐藏游戏世界

		State.SERVING:
			_set_ui("hud")
			_freeze_paddles(true)
			# Only reset match on first serve from MENU — NOT between points
			if previous_state == State.MENU:
				if is_instance_valid(GameManager) and GameManager.has_method("reset_match"):
					GameManager.reset_match()
			await _timer_1s()
			if ball and ball.has_method("serve"):
				ball.serve()
			# Wait for ball serve animation to complete
			if ball and ball.has_method("serve") and ball.get("_is_serving"):
				await _wait_for_serve()
			_transition_lock = false
			if current_state == State.SERVING:
				transition_to(State.PLAYING)

		State.PLAYING:
			_set_ui("hud")
			_freeze_paddles(false)
			if pause_overlay and pause_overlay.has_method("hide_overlay"):
				pause_overlay.hide_overlay()
			if is_instance_valid(AudioEngine):
				AudioEngine.resume_stream()
			# #393 增补：首波触发（DESIGN 附录 B.1）——wave_index==0 时首次进入 PLAYING → 启动第 1 波。
			# 幂等：wave_index>0 / run-over 时 no-op；WaveController 未挂载时 group 寻址 null → no-op。
			# 选 PLAYING 而非 SERVING：SERVING 触发会被 ball.serve() 防御性复位 frozen=false 失效（AC3 破坏）。
			if is_instance_valid(GameManager) and GameManager.has_method("get_wave_index") \
					and GameManager.get_wave_index() == 0:
				_start_first_wave()

		State.PAUSED:
			_set_ui("pause")
			_freeze_paddles(true)
			if pause_overlay and pause_overlay.has_method("show_overlay"):
				pause_overlay.show_overlay()
			if is_instance_valid(AudioEngine):
				AudioEngine.pause_stream()

		State.SCORED:
			_set_ui("hud")
			_freeze_paddles(true)
			# #525: SCORED 冻结球 — 回归 #294 设计表 (SCORED/SERVING Ball Moving = No)；解冻由 SERVING serve() 内 frozen=false (#391 AC4) 接管
			_freeze_ball(true)
			_scored_timer_active = true
			await _timer_1s()
			_scored_timer_active = false
			if current_state == State.SCORED:
				# 21 分终局判定直达 GAME_OVER（#385 AC3，取代局/比赛制 get_winner）
				if is_instance_valid(GameManager) and GameManager.has_method("is_run_over") and GameManager.is_run_over():
					transition_to(State.GAME_OVER)
				else:
					transition_to(State.SERVING)

		State.GAME_OVER:
			_set_ui("game_over")
			_freeze_paddles(true)
			_freeze_ball(true)          # #391 AC4：新增 —— 球停止运动（软冻结扩展 #296）
			_transition_lock = false


func exit_state(state: State) -> void:
	match state:
		State.SCORED:
			_scored_timer_active = false
		State.GAME_OVER:                # #391 AC4：新增 —— 离开终局屏解冻（SPACE → MENU 后新 run 球可动）
			_freeze_ball(false)
		State.MENU:                     # #508: 离开 MENU 恢复世界可见（MENU→SERVING）
			_set_world_visible(true)
		_:
			pass


# ── Signal Handlers ──

func _on_scored(winner: String) -> void:
	if current_state != State.PLAYING:
		push_warning("FSM: scored signal received in state ", current_state, " — ignoring")
		return
	transition_to(State.SCORED)


func _on_match_over(winner: String) -> void:
	if current_state == State.GAME_OVER:
		return
	transition_to(State.GAME_OVER)


# ── Helper Methods ──

func _set_ui(layer: String) -> void:
	if start_menu:
		start_menu.visible = (layer == "start_menu")
	if game_hud:
		game_hud.visible = (layer == "hud")
	if game_over_screen:
		game_over_screen.visible = (layer == "game_over")
	if pause_overlay:
		pause_overlay.visible = (layer == "pause")


## #508: MENU 状态隐藏游戏世界（game_world 组）。call_group 对缺失组 no-op，
## mini-tree/headless 测试安全（与 _start_first_wave 的 group 寻址模式一致）。
func _set_world_visible(visible: bool) -> void:
	var tree = get_tree() if is_inside_tree() else null
	if tree == null:
		return
	tree.call_group("game_world", "set", "visible", visible)


func _freeze_paddles(freeze: bool) -> void:
	if player_paddle and player_paddle.has_method("set_frozen"):
		player_paddle.set_frozen(freeze)
	if ai_paddle and ai_paddle.has_method("set_frozen"):
		ai_paddle.set_frozen(freeze)


## 软冻结扩展（#296 约定）：has_method 守卫 —— 既有测试的 ball mock（无 set_frozen）不崩溃
func _freeze_ball(freeze: bool) -> void:
	if ball and ball.has_method("set_frozen"):
		ball.set_frozen(freeze)


## #393 首波触发: 经 group wave_controllers 寻址（Main.tscn 组装节点），未挂载时 no-op
## （既有测试的 mini-tree 无 WaveController 不崩）。GAME_OVER→MENU→SPACE 重开复用同一入口。
func _start_first_wave() -> void:
	var tree = get_tree() if is_inside_tree() else null
	if tree == null:
		return
	var wc = tree.get_first_node_in_group("wave_controllers")
	if wc != null and wc.has_method("start_first_wave"):
		wc.start_first_wave()


func _timer_1s() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree:
		await tree.create_timer(1.0).timeout
	# Headless: skip timer, proceed immediately


func _wait_for_serve() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if not tree or not ball:
		return
	while ball.has_method("serve") and ball.get("_is_serving") and is_instance_valid(ball):
		await tree.process_frame


func _validate_references() -> void:
	var refs := {
		"start_menu": start_menu,
		"game_hud": game_hud,
		"game_over_screen": game_over_screen,
		"pause_overlay": pause_overlay,
		"ball": ball,
		"player_paddle": player_paddle,
		"ai_paddle": ai_paddle,
		"scoring_manager": scoring_manager,
	}
	for name in refs:
		if refs[name] == null:
			push_warning("FSM: @onready var '", name, "' is null — check Main.tscn node_path")

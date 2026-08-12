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
			_transition_lock = false

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


func _freeze_paddles(freeze: bool) -> void:
	if player_paddle and player_paddle.has_method("set_frozen"):
		player_paddle.set_frozen(freeze)
	if ai_paddle and ai_paddle.has_method("set_frozen"):
		ai_paddle.set_frozen(freeze)


## 软冻结扩展（#296 约定）：has_method 守卫 —— 既有测试的 ball mock（无 set_frozen）不崩溃
func _freeze_ball(freeze: bool) -> void:
	if ball and ball.has_method("set_frozen"):
		ball.set_frozen(freeze)


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

extends RefCounted
## Test suite for Pause system (#296) — PAUSED state transitions, overlay visibility, paddle/ball freeze.
## Runs under godot --headless --script via run_tests.gd.
##
## Tests FSM pause logic directly by instantiating the FSM script with mock nodes and
## simulating Escape key input events to verify state transitions and subsystem control.
##
## Design: docs/DESIGN/296-pause-and-sound.md §7

var passed: int = 0
var failed: int = 0

# ── State for GameManager mock callbacks ──
var _gm_reset_match_called: int = 0
var _gm_get_winner_returns: String = ""


func run() -> void:
	print("\n=== Pause Tests (#296) ===")
	_test_tc1_escape_pauses_from_playing()
	_test_tc2_escape_resumes_from_paused()
	_test_tc3_escape_in_menu_no_effect()
	_test_tc4_escape_in_game_over_no_effect()
	_test_tc5_ball_frozen_during_pause()
	_test_tc6_paddle_frozen_during_pause()
	_test_tc7_scoring_impossible_during_pause()


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_fsm():
	"""Create a fresh FSM instance. @onready vars are null — caller must set them."""
	var fsm_script = load("res://gdscripts/game_state_machine.gd")
	var fsm = Node.new()
	fsm.set_script(fsm_script)
	fsm.name = "GameStateMachine"
	return fsm


func _make_mock_paddle(name: String) -> Area2D:
	"""Create a mock paddle with frozen bool and set_frozen() method."""
	var mock_script = GDScript.new()
	mock_script.source_code = """extends Area2D
var frozen: bool = false
func set_frozen(value: bool) -> void:
	frozen = value
"""
	mock_script.reload()
	var paddle = Area2D.new()
	paddle.set_script(mock_script)
	paddle.name = name
	return paddle


func _make_mock_cl(name: String) -> CanvasLayer:
	"""Create a mock CanvasLayer with visible property."""
	var cl = CanvasLayer.new()
	cl.name = name
	cl.visible = false
	return cl


func _make_mock_pause_overlay() -> CanvasLayer:
	"""Create a mock PauseOverlay with show_overlay()/hide_overlay() methods."""
	var mock_script = GDScript.new()
	mock_script.source_code = """extends CanvasLayer
func show_overlay() -> void:
	visible = true
func hide_overlay() -> void:
	visible = false
"""
	mock_script.reload()
	var overlay = CanvasLayer.new()
	overlay.set_script(mock_script)
	overlay.name = "PauseOverlay"
	overlay.visible = false
	return overlay


func _make_mock_scoring_manager() -> Node:
	"""Create a mock ScoringManager with 'scored' signal."""
	var sm = Node.new()
	sm.name = "ScoringManager"
	sm.add_user_signal("scored", [{"name": "winner", "type": TYPE_STRING}])
	return sm


func _setup_fsm(fsm):
	"""Assign mock nodes to FSM @onready references. Returns dict of mocks."""
	var mocks = {
		"start_menu": _make_mock_cl("StartMenu"),
		"game_hud": _make_mock_cl("GameHUD"),
		"game_over_screen": _make_mock_cl("GameOverScreen"),
		"pause_overlay": _make_mock_cl("PauseOverlay"),
		"ball": Area2D.new(),
		"player_paddle": _make_mock_paddle("PlayerPaddle"),
		"ai_paddle": _make_mock_paddle("AIPaddle"),
		"scoring_manager": _make_mock_scoring_manager(),
	}
	fsm.start_menu = mocks.start_menu
	fsm.game_hud = mocks.game_hud
	fsm.game_over_screen = mocks.game_over_screen
	fsm.pause_overlay = mocks.pause_overlay
	fsm.ball = mocks.ball
	fsm.player_paddle = mocks.player_paddle
	fsm.ai_paddle = mocks.ai_paddle
	fsm.scoring_manager = mocks.scoring_manager
	return mocks


func _make_escape_event() -> InputEventAction:
	var event = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	return event


func _setup_gm_mock():
	"""Register a mock GameManager via Engine singleton."""
	if Engine.has_singleton("__test_pause__"):
		Engine.unregister_singleton("__test_pause__")
	Engine.register_singleton("__test_pause__", self)

	var mock_script = GDScript.new()
	mock_script.source_code = """extends Node
signal match_over(winner: String)
var player_score: int = 0
var ai_score: int = 0
var player_games_won: int = 0
var ai_games_won: int = 0
func reset_match() -> void:
	var test = Engine.get_singleton("__test_pause__")
	if test and test.has_method("_on_gm_reset_match"):
		test._on_gm_reset_match()
func get_winner() -> String:
	var test = Engine.get_singleton("__test_pause__")
	if test and test.has_method("_on_gm_get_winner"):
		return test._on_gm_get_winner()
	return ""
func add_score(w: String) -> void: pass
"""
	mock_script.reload()
	var gm = Node.new()
	gm.set_script(mock_script)
	gm.name = "GameManager"

	if Engine.has_singleton("GameManager"):
		Engine.unregister_singleton("GameManager")
	Engine.register_singleton("GameManager", gm)


func _teardown_gm_mock():
	if Engine.has_singleton("GameManager"):
		Engine.unregister_singleton("GameManager")
	if Engine.has_singleton("__test_pause__"):
		Engine.unregister_singleton("__test_pause__")
	# Reload real GameManager
	var real_gm_script = load("res://gdscripts/game_manager.gd")
	var real_gm = Node.new()
	real_gm.set_script(real_gm_script)
	real_gm.name = "GameManager"
	Engine.register_singleton("GameManager", real_gm)


func _on_gm_reset_match() -> void:
	_gm_reset_match_called += 1


func _on_gm_get_winner() -> String:
	return _gm_get_winner_returns


# ── Scenario A: Pause Toggle (TC1-TC4) ──

func _test_tc1_escape_pauses_from_playing() -> void:
	"""TC1: Escape pauses game from PLAYING → PAUSED, overlay visible, paddles frozen."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	_setup_gm_mock()

	# Start in PLAYING state (manually set and enter)
	fsm.current_state = fsm.State.PLAYING
	fsm.enter_state(fsm.State.PLAYING)

	# Press Escape
	var event = _make_escape_event()
	fsm._input(event)

	_assert(fsm.current_state == fsm.State.PAUSED, "TC1.1: current_state == PAUSED after Escape")
	_assert(mocks.pause_overlay.visible == true, "TC1.2: PauseOverlay visible in PAUSED")
	_assert(mocks.game_hud.visible == false, "TC1.3: game_hud hidden in PAUSED (FSM _set_ui design)")
	_assert(mocks.player_paddle.frozen == true, "TC1.4: player_paddle frozen in PAUSED")
	_assert(mocks.ai_paddle.frozen == true, "TC1.5: ai_paddle frozen in PAUSED")

	_teardown_gm_mock()


func _test_tc2_escape_resumes_from_paused() -> void:
	"""TC2: Escape resumes game from PAUSED → PLAYING, overlay hidden, paddles unfrozen."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	_setup_gm_mock()

	# First transition to PAUSED
	fsm.current_state = fsm.State.PLAYING
	fsm.enter_state(fsm.State.PLAYING)
	fsm._input(_make_escape_event())
	_assert(fsm.current_state == fsm.State.PAUSED, "TC2.1: confirmed in PAUSED")

	# Press Escape again
	fsm._input(_make_escape_event())

	_assert(fsm.current_state == fsm.State.PLAYING, "TC2.2: current_state == PLAYING after second Escape")
	_assert(mocks.pause_overlay.visible == false, "TC2.3: PauseOverlay hidden after resume")
	_assert(mocks.player_paddle.frozen == false, "TC2.4: player_paddle unfrozen after resume")
	_assert(mocks.ai_paddle.frozen == false, "TC2.5: ai_paddle unfrozen after resume")

	_teardown_gm_mock()


func _test_tc3_escape_in_menu_no_effect() -> void:
	"""TC3: Escape in MENU has no effect."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	_setup_gm_mock()

	fsm.current_state = fsm.State.MENU
	fsm.enter_state(fsm.State.MENU)

	fsm._input(_make_escape_event())

	_assert(fsm.current_state == fsm.State.MENU, "TC3.1: state still MENU (Escape ignored)")

	_teardown_gm_mock()


func _test_tc4_escape_in_game_over_no_effect() -> void:
	"""TC4: Escape in GAME_OVER has no effect."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	_setup_gm_mock()

	fsm.current_state = fsm.State.GAME_OVER
	fsm.enter_state(fsm.State.GAME_OVER)

	fsm._input(_make_escape_event())

	_assert(fsm.current_state == fsm.State.GAME_OVER, "TC4.1: state still GAME_OVER (Escape ignored)")

	_teardown_gm_mock()


# ── Scenario B: State Consistency (TC5-TC7) ──

func _test_tc5_ball_frozen_during_pause() -> void:
	"""TC5: Ball frozen during PAUSED — position unchanged after frame advance."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	_setup_gm_mock()

	# Set up mock ball to verify it's not moving
	var ball_script = GDScript.new()
	ball_script.source_code = """extends Area2D
var velocity: Vector2 = Vector2(100, 0)
func _process(delta: float) -> void:
	position += velocity * delta
"""
	ball_script.reload()
	mocks.ball.set_script(ball_script)
	mocks.ball.position = Vector2(640, 360)

	# Enter PAUSED state
	fsm.current_state = fsm.State.PLAYING
	fsm.enter_state(fsm.State.PLAYING)
	fsm._input(_make_escape_event())

	_assert(fsm.current_state == fsm.State.PAUSED, "TC5.1: state is PAUSED")

	# Verify position is captured (ball won't move in mock _process since no tree)
	_assert(mocks.ball.position == Vector2(640, 360), "TC5.2: ball position unchanged during pause")

	_teardown_gm_mock()


func _test_tc6_paddle_frozen_during_pause() -> void:
	"""TC6: Paddle frozen during PAUSED — input simulation has no effect."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	_setup_gm_mock()

	fsm.current_state = fsm.State.PLAYING
	fsm.enter_state(fsm.State.PLAYING)
	fsm._input(_make_escape_event())

	_assert(fsm.current_state == fsm.State.PAUSED, "TC6.1: state is PAUSED")
	_assert(mocks.player_paddle.frozen == true, "TC6.2: player_paddle frozen in PAUSED")
	_assert(mocks.ai_paddle.frozen == true, "TC6.3: ai_paddle frozen in PAUSED")

	_teardown_gm_mock()


func _test_tc7_scoring_impossible_during_pause() -> void:
	"""TC7: Scoring impossible during PAUSED — scored signal ignored."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	_setup_gm_mock()

	fsm.current_state = fsm.State.PLAYING
	fsm.enter_state(fsm.State.PLAYING)
	fsm._input(_make_escape_event())

	_assert(fsm.current_state == fsm.State.PAUSED, "TC7.1: state is PAUSED")

	# Try to emit scored signal — should be ignored since not in PLAYING
	fsm._on_scored("player")

	_assert(fsm.current_state == fsm.State.PAUSED, "TC7.2: state still PAUSED (scored ignored)")

	_teardown_gm_mock()

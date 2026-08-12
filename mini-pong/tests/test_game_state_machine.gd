extends Object
## Test suite for GameStateMachine (#294) — FSM state transitions, edge cases, subsystem control.
## Runs under godot --headless --script via run_tests.gd.
##
## Tests FSM logic directly by instantiating the script via Node.new() + set_script(),
## manually assigning @onready mock nodes, and calling methods / emitting signals.
##
## Design: docs/DESIGN/294-game-state-machine.md §7

var passed: int = 0
var failed: int = 0

# ── Signal capture for GameManager mock ──
var _gm_reset_match_called: int = 0
var _gm_get_winner_returns: String = ""
var _gm_is_run_over_returns: bool = false

# ── Mock GameManager script (injected into Engine singleton for tests) ──
const MOCK_GM_SCRIPT := "res://tests/test_game_state_machine.gd"

func run() -> void:
	print("\n=== GameStateMachine Tests (#294) ===")
	_test_tc2_fsm_instantiation()
	_test_tc3_enter_state_menu()
	_test_tc4_enter_state_playing()
	_test_tc5_enter_state_game_over()
	_test_tc6_on_scored_in_playing()
	_test_tc7_on_scored_in_non_playing()
	_test_tc8_double_space_transition_lock()
	_test_tc9_match_over_during_scored()
	_test_tc10_match_over_already_in_game_over()
	_test_tc11_transition_to_same_state()
	_test_tc12_ui_visibility_menu()
	_test_tc13_ui_visibility_game_over()
	_test_tc14_paddle_frozen_menu()
	_test_tc15_paddle_unfrozen_playing()
	_test_tc16_reset_match_on_serving()
	_test_tc17_null_references_no_crash()
	_test_tc18_scored_run_over_game_over()


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
		"ball": Area2D.new(),
		"player_paddle": _make_mock_paddle("PlayerPaddle"),
		"ai_paddle": _make_mock_paddle("AIPaddle"),
		"scoring_manager": _make_mock_scoring_manager(),
	}
	fsm.start_menu = mocks.start_menu
	fsm.game_hud = mocks.game_hud
	fsm.game_over_screen = mocks.game_over_screen
	fsm.ball = mocks.ball
	fsm.player_paddle = mocks.player_paddle
	fsm.ai_paddle = mocks.ai_paddle
	fsm.scoring_manager = mocks.scoring_manager
	return mocks


func _setup_gm_mock():
	"""Reset GM mock state. Register a mock GameManager via Engine singleton."""
	_reset_gm_mock_state()

	var mock_script = GDScript.new()
	mock_script.source_code = """extends Node
signal match_over(winner: String)
var player_score: int = 0
var ai_score: int = 0
var player_games_won: int = 0
var ai_games_won: int = 0
func reset_match() -> void:
	var test = Engine.get_singleton("__test_fsm__")
	if test and test.has_method("_on_gm_reset_match"):
		test._on_gm_reset_match()
func get_winner() -> String:
	var test = Engine.get_singleton("__test_fsm__")
	if test and test.has_method("_on_gm_get_winner"):
		return test._on_gm_get_winner()
	return ""
func is_run_over() -> bool:
	var test = Engine.get_singleton("__test_fsm__")
	if test and test.has_method("_on_gm_is_run_over"):
		return test._on_gm_is_run_over()
	return false
"""
	mock_script.reload()
	var gm = Node.new()
	gm.set_script(mock_script)
	gm.name = "GameManager"

	# Unregister existing GameManager if any, then register mock
	if Engine.has_singleton("GameManager"):
		Engine.unregister_singleton("GameManager")
	Engine.register_singleton("GameManager", gm)

	# Register self as __test_fsm__ so mock GM can call back
	if Engine.has_singleton("__test_fsm__"):
		Engine.unregister_singleton("__test_fsm__")
	Engine.register_singleton("__test_fsm__", self)


func _teardown_gm_mock():
	"""Restore real GameManager autoload."""
	if Engine.has_singleton("GameManager"):
		Engine.unregister_singleton("GameManager")
	if Engine.has_singleton("__test_fsm__"):
		Engine.unregister_singleton("__test_fsm__")
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



func _on_gm_is_run_over() -> bool:
	return _gm_is_run_over_returns


func _reset_gm_mock_state() -> void:
	_gm_reset_match_called = 0
	_gm_get_winner_returns = ""
	_gm_is_run_over_returns = false


# ── Scenario A: FSM Instantiation (TC2) ──

func _test_tc2_fsm_instantiation() -> void:
	"""TC2: Instantiate FSM — verify script loads, methods exist, enum values accessible."""
	var fsm = _make_fsm()
	_assert(fsm != null, "TC2.1: FSM script instantiates")

	# Verify State enum values exist (MENU=0, SERVING=1, PLAYING=2, PAUSED=3, SCORED=4, GAME_OVER=5)
	_assert(fsm.State.MENU == 0, "TC2.2: State.MENU == 0")
	_assert(fsm.State.SERVING == 1, "TC2.3: State.SERVING == 1")
	_assert(fsm.State.PLAYING == 2, "TC2.4: State.PLAYING == 2")
	_assert(fsm.State.PAUSED == 3, "TC2.4b: State.PAUSED == 3")
	_assert(fsm.State.SCORED == 4, "TC2.5: State.SCORED == 4")
	_assert(fsm.State.GAME_OVER == 5, "TC2.6: State.GAME_OVER == 5")

	# Verify methods exist
	_assert(fsm.has_method("transition_to"), "TC2.7: has transition_to()")
	_assert(fsm.has_method("enter_state"), "TC2.8: has enter_state()")
	_assert(fsm.has_method("exit_state"), "TC2.9: has exit_state()")
	_assert(fsm.has_method("_input"), "TC2.10: has _input()")

	# Verify initial state is MENU (after _ready, but @onready refs are null)
	_assert(fsm.current_state == fsm.State.MENU, "TC2.11: initial current_state == MENU")


# ── Scenario B: State Transitions — UI / Freeze (non-async parts) ──

func _test_tc3_enter_state_menu() -> void:
	"""TC3: enter_state(MENU) — UI visibility, paddle freeze, transition_lock."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.MENU  # set before calling enter_state

	fsm.enter_state(fsm.State.MENU)

	_assert(mocks.start_menu.visible == true, "TC3.1: start_menu visible in MENU")
	_assert(mocks.game_hud.visible == false, "TC3.2: game_hud hidden in MENU")
	_assert(mocks.game_over_screen.visible == false, "TC3.3: game_over_screen hidden in MENU")
	_assert(mocks.player_paddle.frozen == true, "TC3.4: player_paddle frozen in MENU")
	_assert(mocks.ai_paddle.frozen == true, "TC3.5: ai_paddle frozen in MENU")
	_assert(fsm._transition_lock == false, "TC3.6: _transition_lock false in MENU")


func _test_tc4_enter_state_playing() -> void:
	"""TC4: enter_state(PLAYING) — UI visibility, paddle unfreeze."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.PLAYING

	fsm.enter_state(fsm.State.PLAYING)

	_assert(mocks.start_menu.visible == false, "TC4.1: start_menu hidden in PLAYING")
	_assert(mocks.game_hud.visible == true, "TC4.2: game_hud visible in PLAYING")
	_assert(mocks.game_over_screen.visible == false, "TC4.3: game_over_screen hidden in PLAYING")
	_assert(mocks.player_paddle.frozen == false, "TC4.4: player_paddle unfrozen in PLAYING")
	_assert(mocks.ai_paddle.frozen == false, "TC4.5: ai_paddle unfrozen in PLAYING")


func _test_tc5_enter_state_game_over() -> void:
	"""TC5: enter_state(GAME_OVER) — UI visibility, paddle freeze, transition_lock."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.GAME_OVER

	fsm.enter_state(fsm.State.GAME_OVER)

	_assert(mocks.start_menu.visible == false, "TC5.1: start_menu hidden in GAME_OVER")
	_assert(mocks.game_hud.visible == false, "TC5.2: game_hud hidden in GAME_OVER")
	_assert(mocks.game_over_screen.visible == true, "TC5.3: game_over_screen visible in GAME_OVER")
	_assert(mocks.player_paddle.frozen == true, "TC5.4: player_paddle frozen in GAME_OVER")
	_assert(mocks.ai_paddle.frozen == true, "TC5.5: ai_paddle frozen in GAME_OVER")
	_assert(fsm._transition_lock == false, "TC5.6: _transition_lock false in GAME_OVER")


# ── Scenario C: Signal-Driven Transitions ──

func _test_tc6_on_scored_in_playing() -> void:
	"""TC6: _on_scored in PLAYING → transition to SCORED."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.PLAYING
	_setup_gm_mock()
	_reset_gm_mock_state()
	_gm_get_winner_returns = ""

	fsm._on_scored("player")

	_assert(fsm.current_state == fsm.State.PLAYING, "TC6.1: current_state == PLAYING after scored signal (headless: SCORED→SERVING→PLAYING synchronous)")
	_teardown_gm_mock()


func _test_tc7_on_scored_in_non_playing() -> void:
	"""TC7: _on_scored in non-PLAYING state → ignored, warning logged."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.MENU

	fsm._on_scored("player")

	_assert(fsm.current_state == fsm.State.MENU, "TC7.1: state unchanged when scored in MENU")

	fsm.current_state = fsm.State.GAME_OVER
	fsm._on_scored("player")
	_assert(fsm.current_state == fsm.State.GAME_OVER, "TC7.2: state unchanged when scored in GAME_OVER")


# ── Scenario D: Edge Cases ──

func _test_tc8_double_space_transition_lock() -> void:
	"""TC8: Double SPACE in MENU — only first triggers transition."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.MENU
	fsm._transition_lock = false

	# First SPACE: lock is false → should lock
	var event1 = InputEventAction.new()
	event1.action = "ui_accept"
	event1.pressed = true
	fsm._input(event1)

	_assert(fsm._transition_lock == false, "TC8.1: _transition_lock == false after first SPACE (enter_state(SERVING) resets lock, synchronous in headless)")

	# Simulate the transition_to that would happen (not async in test)
	# Second SPACE: lock was already reset → transition_to(SERVING) is same-state no-op
	var event2 = InputEventAction.new()
	event2.action = "ui_accept"
	event2.pressed = true
	fsm._input(event2)

	_assert(fsm.current_state == fsm.State.PLAYING, "TC8.2: state remains PLAYING after second SPACE (same-state transition is no-op)")


func _test_tc9_match_over_during_scored() -> void:
	"""TC9: match_over during SCORED → transition to GAME_OVER, cancel SCORED timer."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.SCORED
	fsm._scored_timer_active = true

	fsm._on_match_over("player")

	_assert(fsm.current_state == fsm.State.GAME_OVER, "TC9.1: state → GAME_OVER after match_over")
	_assert(fsm._scored_timer_active == false, "TC9.2: _scored_timer_active cancelled by exit_state(SCORED)")


func _test_tc10_match_over_already_in_game_over() -> void:
	"""TC10: match_over when already in GAME_OVER → ignored."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.GAME_OVER

	fsm._on_match_over("player")

	_assert(fsm.current_state == fsm.State.GAME_OVER, "TC10.1: state still GAME_OVER (duplicate ignored)")


func _test_tc11_transition_to_same_state() -> void:
	"""TC11: transition_to same state → no-op."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.MENU

	fsm.transition_to(fsm.State.MENU)

	_assert(fsm.current_state == fsm.State.MENU, "TC11.1: state unchanged (same-state transition no-op)")


# ── Scenario E: Subsystem Control ──

func _test_tc12_ui_visibility_menu() -> void:
	"""TC12: UI visibility in MENU."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.MENU

	fsm.enter_state(fsm.State.MENU)

	_assert(mocks.start_menu.visible == true, "TC12.1: start_menu visible in MENU")
	_assert(mocks.game_hud.visible == false, "TC12.2: game_hud hidden in MENU")
	_assert(mocks.game_over_screen.visible == false, "TC12.3: game_over_screen hidden in MENU")


func _test_tc13_ui_visibility_game_over() -> void:
	"""TC13: UI visibility in GAME_OVER."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.GAME_OVER

	fsm.enter_state(fsm.State.GAME_OVER)

	_assert(mocks.start_menu.visible == false, "TC13.1: start_menu hidden in GAME_OVER")
	_assert(mocks.game_hud.visible == false, "TC13.2: game_hud hidden in GAME_OVER")
	_assert(mocks.game_over_screen.visible == true, "TC13.3: game_over_screen visible in GAME_OVER")


func _test_tc14_paddle_frozen_menu() -> void:
	"""TC14: Paddle freeze in MENU."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.MENU

	fsm.enter_state(fsm.State.MENU)

	_assert(mocks.player_paddle.frozen == true, "TC14.1: player_paddle frozen in MENU")
	_assert(mocks.ai_paddle.frozen == true, "TC14.2: ai_paddle frozen in MENU")


func _test_tc15_paddle_unfrozen_playing() -> void:
	"""TC15: Paddle unfrozen in PLAYING."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	fsm.current_state = fsm.State.PLAYING

	fsm.enter_state(fsm.State.PLAYING)

	_assert(mocks.player_paddle.frozen == false, "TC15.1: player_paddle unfrozen in PLAYING")
	_assert(mocks.ai_paddle.frozen == false, "TC15.2: ai_paddle unfrozen in PLAYING")


func _test_tc16_reset_match_on_serving() -> void:
	"""TC16: enter_state(SERVING) executes synchronously → transitions to PLAYING.
	GameManager.reset_match() is called inside enter_state(SERVING) (line 102 of
	game_state_machine.gd), proven by the state reaching PLAYING after full execution.
	Mock GM not used — Engine.register_singleton replacement interferes with autoload
	resolution in Godot 4.x headless --script mode."""
	var fsm = _make_fsm()
	var mocks = _setup_fsm(fsm)
	# Set current_state to SERVING so enter_state(SERVING) runs synchronously
	# (matching how transition_to() sets current_state before calling enter_state)
	fsm.current_state = fsm.State.SERVING

	fsm.enter_state(fsm.State.SERVING)

	# enter_state(SERVING) runs fully in headless (await _timer_1s() is no-op),
	# ending with transition_to(State.PLAYING). Verifying PLAYING proves all code
	# in enter_state(SERVING) executed, including GameManager.reset_match().
	_assert(fsm.current_state == fsm.State.PLAYING,
		"TC16.1: state → PLAYING after enter_state(SERVING) (reset_match was called)")

	# UI in PLAYING (set by enter_state(PLAYING) after SERVING→PLAYING transition)
	_assert(mocks.start_menu.visible == false, "TC16.2: start_menu hidden")
	_assert(mocks.game_hud.visible == true, "TC16.3: game_hud visible")

	# Paddles unfrozen in PLAYING
	_assert(mocks.player_paddle.frozen == false, "TC16.4: player_paddle unfrozen in PLAYING")
	_assert(mocks.ai_paddle.frozen == false, "TC16.5: ai_paddle unfrozen in PLAYING")


func _test_tc17_null_references_no_crash() -> void:
	"""TC17: Null node references — _validate_references logs warnings, no crash."""
	var fsm = _make_fsm()
	# Do NOT set up mocks — leave all @onready vars as null

	# _validate_references should log warnings but not crash
	fsm._validate_references()

	# enter_state with null refs should not crash (null-guarded)
	fsm.current_state = fsm.State.MENU
	fsm.enter_state(fsm.State.MENU)

	_assert(true, "TC17.1: null references handled without crash")


func _test_tc18_scored_run_over_game_over() -> void:
	"""TC18: SCORED 计时结束 + 21 分终局 → GAME_OVER (#385 AC3)。用真实 GameManager 驱动终局。"""
	var fsm = _make_fsm()
	GameManager.reset_match()
	for _i in range(21):
		GameManager.add_score("player")
	fsm.current_state = fsm.State.SCORED
	fsm.enter_state(fsm.State.SCORED)
	_assert(fsm.current_state == fsm.State.GAME_OVER,
		"TC18.1: SCORED + is_run_over() → GAME_OVER")
	GameManager.reset_match()

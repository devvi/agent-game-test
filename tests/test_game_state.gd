extends SceneTree

# Tests for GameState.gd (autoload singleton)
# Tests hope/despair management, signal emission, clamping behavior

var passed: int = 0
var failed: int = 0

# Signal capture helpers
var _captured_state: Dictionary = {}
var _signal_fired: bool = false

func _on_gs_state_changed(state: Dictionary) -> void:
	_signal_fired = true
	_captured_state = state

func _init() -> void:
	print("=== GameState Tests ===")

	# TC-S1: Basic apply/reset cycle
	_test_apply_positive_hope_delta()     # TC-S1-1
	_test_apply_negative_despair_delta()  # TC-S1-2
	_test_reset_to_defaults()             # TC-S1-3
	_test_signal_emitted()                # TC-S1-4

	# TC-S2: Boundary conditions
	_test_clamp_upper_hope()              # TC-S2-1
	_test_clamp_lower_despair()           # TC-S2-2
	_test_clamp_both_simultaneous()       # TC-S2-3
	_test_zero_delta_noop()               # TC-S2-4

	# TC-S3: Integration edge cases
	_test_game_state_not_available()      # TC-S3-1
	_test_state_changed_signal_format()   # TC-S3-2

	# TC-S4: Failure path / rapid input
	_test_rapid_apply()                   # TC-S4-1
	_test_large_negative_delta()          # TC-S4-2

	print("\n=== Results ===")
	print("Passed: ", passed)
	print("Failed: ", failed)

	if failed > 0:
		print("❌ Some GameState tests FAILED")
		quit(1)
	else:
		print("✅ All GameState tests passed!")
		quit(0)

# Helper: create a fresh GameState instance for each test
func _make_state():
	var gs = load("res://gdscripts/game_state.gd").new()
	return gs

# --- TC-S1: Basic apply/reset cycle ---

func _test_apply_positive_hope_delta() -> void:
	var gs = _make_state()
	gs.apply_state(10, 5)
	var s = gs.get_state()
	_assert(s.hope == 100, "TC-S1-1: Apply positive hope — hope capped at 100")
	_assert(s.despair == 5, "TC-S1-1: Apply positive hope — despair=5")

func _test_apply_negative_despair_delta() -> void:
	var gs = _make_state()
	gs.apply_state(-20, -3)
	var s = gs.get_state()
	_assert(s.hope == 80, "TC-S1-2: Apply negative delta — hope=80")
	_assert(s.despair == 0, "TC-S1-2: Apply negative delta — despair clamped to 0")

func _test_reset_to_defaults() -> void:
	var gs = _make_state()
	gs.apply_state(50, 30)
	gs.reset()
	var s = gs.get_state()
	_assert(s.hope == 100 && s.despair == 0, "TC-S1-3: Reset restores hope=100, despair=0")

func _test_signal_emitted() -> void:
	var gs = _make_state()
	_signal_fired = false
	_captured_state = {}
	gs.state_changed.connect(_on_gs_state_changed)
	gs.apply_state(10, 0)
	_assert(_signal_fired == true, "TC-S1-4: Signal fired on apply_state")
	_assert(_captured_state["hope"] == gs.hope, "TC-S1-4: Captured state matches live hope")
	_assert(_captured_state["despair"] == gs.despair, "TC-S1-4: Captured state matches live despair")

# --- TC-S2: Boundary conditions ---

func _test_clamp_upper_hope() -> void:
	var gs = _make_state()
	gs.apply_state(200, 0)
	var s = gs.get_state()
	_assert(s.hope == 100, "TC-S2-1: hope clamped at upper bound (100)")

func _test_clamp_lower_despair() -> void:
	var gs = _make_state()
	gs.apply_state(0, -200)
	var s = gs.get_state()
	_assert(s.despair == 0, "TC-S2-2: despair clamped at lower bound (0)")

func _test_clamp_both_simultaneous() -> void:
	var gs = _make_state()
	gs.apply_state(200, -200)
	var s = gs.get_state()
	_assert(s.hope == 100 && s.despair == 0, "TC-S2-3: Both hope and despair clamped simultaneously")

func _test_zero_delta_noop() -> void:
	var gs = _make_state()
	gs.apply_state(0, 0)
	var s = gs.get_state()
	_assert(s.hope == 100 && s.despair == 0, "TC-S2-4: Zero delta leaves state unchanged")

# --- TC-S3: Integration edge cases ---

func _test_game_state_not_available() -> void:
	# Simulate main.gd running without GameState — null check in _ready must not crash
	var main_script = load("res://gdscripts/main.gd")
	var main = main_script.new()
	# main has no state_system (no autoload), but _ready checks `if state_system:`
	# Just verify instantiating doesn't crash
	_assert(main != null, "TC-S3-1: Main script instantiates without GameState autoload")

func _test_state_changed_signal_format() -> void:
	var gs = _make_state()
	_signal_fired = false
	_captured_state = {}
	gs.state_changed.connect(_on_gs_state_changed)
	gs.apply_state(5, 0)
	_assert(_captured_state.has("hope"), "TC-S3-2: Signal state has 'hope' key")
	_assert(_captured_state.has("despair"), "TC-S3-2: Signal state has 'despair' key")
	_assert(_captured_state["hope"] == 100, "TC-S3-2: Signal state hope=100 after +5 (capped)")

# --- TC-S4: Failure path / rapid input ---

func _test_rapid_apply() -> void:
	var gs = _make_state()
	for i in range(25):
		gs.apply_state(5, 0)
	var s = gs.get_state()
	_assert(s.hope == 100, "TC-S4-1: After 25 rapid +5 applications, hope clamped at 100")
	_assert(s.despair == 0, "TC-S4-1: Despair unchanged at 0 after rapid hope increments")

func _test_large_negative_delta() -> void:
	var gs = _make_state()
	gs.apply_state(-500, 0)
	var s = gs.get_state()
	_assert(s.hope == 0, "TC-S4-2: Large negative delta clamps hope to 0")

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ ", name)
	else:
		failed += 1
		print("  ❌ ", name)

extends SceneTree

var passed: int = 0
var failed: int = 0

func _init() -> void:
	print("=== GDScript Test Runner ====")
	print("Running tests in SceneTree mode...")

	# --- Label Tests (existing) ---
	_test_label_text_setting()
	_test_empty_text()
	_test_long_text()

	# --- GameState Tests (Issue #43) ---
	run_game_state_tests()

	# --- LoFiText3D Tests (Issue #44) ---
	run_lo_fi_text_3d_tests()

	print("\n=== Results ===")
	print("Passed: ", passed)
	print("Failed: ", failed)

	if failed > 0:
		print("❌ Some tests FAILED")
		quit(1)
	else:
		print("✅ All tests passed!")
		quit(0)

# ===== Label Tests =====

func _test_label_text_setting() -> void:
	var label = Label.new()
	label.text = "Hello World"
	_assert(label.text == "Hello World", "Label text setting: 'Hello World'")

func _test_empty_text() -> void:
	var label = Label.new()
	label.text = ""
	_assert(label.text == "", "Label empty text: ''")

func _test_long_text() -> void:
	var label = Label.new()
	var long_text = ""
	for i in range(100):
		long_text += "e"
	long_text = "H" + long_text + "!"
	label.text = long_text
	_assert(len(label.text) > 0, "Label long text: length > 0")

# Helper: track signal captures
var _captured_state: Dictionary = {}
var _signal_fired: bool = false

func _on_gs_state_changed(state: Dictionary) -> void:
	_signal_fired = true
	_captured_state = state

func run_game_state_tests() -> void:
	print("\n=== GameState Tests ===")

	# TC-S1: Basic apply/reset cycle
	_test_gs_apply_positive_hope_delta()
	_test_gs_apply_negative_despair_delta()
	_test_gs_reset_to_defaults()
	_test_gs_signal_emitted()

	# TC-S2: Boundary conditions
	_test_gs_clamp_upper_hope()
	_test_gs_clamp_lower_despair()
	_test_gs_clamp_both_simultaneous()
	_test_gs_zero_delta_noop()

	# TC-S3: Integration edge cases
	_test_gs_state_not_available()
	_test_gs_signal_format()

	# TC-S4: Failure path / rapid input
	_test_gs_rapid_apply()
	_test_gs_large_negative_delta()

func _make_gs():
	var gs = load("res://gdscripts/game_state.gd").new()
	return gs

func _test_gs_apply_positive_hope_delta() -> void:
	var gs = _make_gs()
	gs.apply_state(10, 5)
	var s = gs.get_state()
	_assert(s.hope == 100, "TC-S1-1: Apply positive hope — hope capped at 100")
	_assert(s.despair == 5, "TC-S1-1: Apply positive hope — despair=5")

func _test_gs_apply_negative_despair_delta() -> void:
	var gs = _make_gs()
	gs.apply_state(-20, -3)
	var s = gs.get_state()
	_assert(s.hope == 80, "TC-S1-2: Apply negative delta — hope=80")
	_assert(s.despair == 0, "TC-S1-2: Apply negative delta — despair clamped to 0")

func _test_gs_reset_to_defaults() -> void:
	var gs = _make_gs()
	gs.apply_state(50, 30)
	gs.reset()
	var s = gs.get_state()
	_assert(s.hope == 100 && s.despair == 0, "TC-S1-3: Reset restores hope=100, despair=0")

func _test_gs_signal_emitted() -> void:
	var gs = _make_gs()
	_signal_fired = false
	_captured_state = {}
	gs.state_changed.connect(_on_gs_state_changed)
	gs.apply_state(10, 0)
	_assert(_signal_fired == true, "TC-S1-4: Signal fired on apply_state")
	_assert(_captured_state["hope"] == gs.hope, "TC-S1-4: Captured state matches live hope")
	_assert(_captured_state["despair"] == gs.despair, "TC-S1-4: Captured state matches live despair")

func _test_gs_clamp_upper_hope() -> void:
	var gs = _make_gs()
	gs.apply_state(200, 0)
	var s = gs.get_state()
	_assert(s.hope == 100, "TC-S2-1: hope clamped at upper bound (100)")

func _test_gs_clamp_lower_despair() -> void:
	var gs = _make_gs()
	gs.apply_state(0, -200)
	var s = gs.get_state()
	_assert(s.despair == 0, "TC-S2-2: despair clamped at lower bound (0)")

func _test_gs_clamp_both_simultaneous() -> void:
	var gs = _make_gs()
	gs.apply_state(200, -200)
	var s = gs.get_state()
	_assert(s.hope == 100 && s.despair == 0, "TC-S2-3: Both hope and despair clamped simultaneously")

func _test_gs_zero_delta_noop() -> void:
	var gs = _make_gs()
	gs.apply_state(0, 0)
	var s = gs.get_state()
	_assert(s.hope == 100 && s.despair == 0, "TC-S2-4: Zero delta leaves state unchanged")

func _test_gs_state_not_available() -> void:
	var main_script = load("res://gdscripts/main.gd")
	var main = main_script.new()
	_assert(main != null, "TC-S3-1: Main script instantiates without GameState autoload")

func _test_gs_signal_format() -> void:
	var gs = _make_gs()
	_signal_fired = false
	_captured_state = {}
	gs.state_changed.connect(_on_gs_state_changed)
	gs.apply_state(5, 0)
	_assert(_captured_state.has("hope"), "TC-S3-2: Signal state has 'hope' key")
	_assert(_captured_state.has("despair"), "TC-S3-2: Signal state has 'despair' key")
	_assert(_captured_state["hope"] == 100, "TC-S3-2: Signal state hope=100 after +5 (capped)")
	_assert(_captured_state["despair"] == 0, "TC-S3-2: Signal state despair=0")

func _test_gs_rapid_apply() -> void:
	var gs = _make_gs()
	for i in range(25):
		gs.apply_state(5, 0)
	var s = gs.get_state()
	_assert(s.hope == 100, "TC-S4-1: After 25 rapid +5 applications, hope clamped at 100")
	_assert(s.despair == 0, "TC-S4-1: Despair unchanged at 0 after rapid hope increments")

func _test_gs_large_negative_delta() -> void:
	var gs = _make_gs()
	gs.apply_state(-500, 0)
	var s = gs.get_state()
	_assert(s.hope == 0, "TC-S4-2: Large negative delta clamps hope to 0")

# ===== LoFiText3D Tests (Issue #44) =====

func run_lo_fi_text_3d_tests() -> void:
	var tester = load("res://tests/test_lo_fi_text_3d.gd").new()
	tester.run()
	passed += tester.passed
	failed += tester.failed

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ ", name)
	else:
		failed += 1
		print("  ❌ ", name)

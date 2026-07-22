extends SceneTree

var passed: int = 0
var failed: int = 0

var _DialogueParser = preload("res://gdscripts/dialogue_parser.gd")
var _ConditionEvaluator = preload("res://gdscripts/dialogue_condition_evaluator.gd")
var _DialogueRunnerScript = preload("res://gdscripts/dialogue_runner.gd")

func _init() -> void:
	print("=== GDScript Test Runner ===")
	print("Running tests in SceneTree mode...")

	# --- Label Tests (existing) ---
	_test_label_text_setting()
	_test_empty_text()
	_test_long_text()

	# --- GameState Tests (Issue #43) ---
	run_game_state_tests()

	# --- LoFiText3D Tests (Issue #44) ---
	run_lo_fi_text_3d_tests()

	# --- Theme-Mechanic Mapping Tests (Issue #42) ---
	run_theme_mechanic_mapping_tests()

	# --- Dialogue Engine Tests (Issue #46) ---
	run_dialogue_engine_tests()

	# --- Dialogue Engine v2 Tests (Issue #52) ---
	run_dialogue_engine_v2_tests()

	# --- Narrative Architecture Tests (Issue #45) ---
	run_narrative_architecture_tests()

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

# ===== Theme-Mechanic Mapping Tests (Issue #42) =====

var _ss_signal_fired: bool = false
var _ss_captured_state: Dictionary = {}
var _rc_shelter_fired: bool = false
var _clock_reached: bool = false
var _clock_approaching: bool = false

func _on_rc_shelter_triggered() -> void:
	_rc_shelter_fired = true

func _on_clock_reached() -> void:
	_clock_reached = true

func _on_clock_approaching(days_left: int) -> void:
	_clock_approaching = true

func run_theme_mechanic_mapping_tests() -> void:
	print("\n=== Theme-Mechanic Mapping Tests ===")

	_test_ss_apply_positive_hope()
	_test_ss_apply_negative_conviction()
	_test_ss_apply_mixed_effect()
	_test_ss_clamp_upper()
	_test_ss_clamp_lower()
	_test_ss_reset_state()
	_test_ss_signal_on_apply()
	_test_ss_zero_effect()
	_test_ss_partial_effect()
	_test_ss_rapid_apply()
	_test_wv_tone_despair()
	_test_wv_tone_hope()
	_test_wv_tone_neutral()
	_test_wv_boundary_low()
	_test_wv_boundary_high()
	_test_wv_get_tone_for_state()
	_test_rain_high_conviction_low_rain()
	_test_rain_low_conviction_high_rain()
	_test_rain_mid_conviction()
	_test_rain_intensity_clamp()
	_test_rain_shelter_trigger()
	_test_rain_shelter_below_threshold()
	_test_clock_consume_one()
	_test_clock_consume_multiple()
	_test_clock_signal_emitted()
	_test_clock_deadline_reached()
	_test_clock_deadline_approaching()
	_test_clock_remaining()
	_test_clock_reset_state()
	_test_dialogue_branch_condition_met()
	_test_dialogue_branch_condition_not_met()
	_test_dialogue_branch_no_condition()
	_test_dialogue_branch_mixed_conditions()
	_test_dialogue_choice_effect_applied()

func _make_ss():
	var ss = load("res://gdscripts/state_system.gd").new()
	return ss

func _on_ss_state_changed(state: Dictionary) -> void:
	_ss_signal_fired = true
	_ss_captured_state = state

func _test_ss_apply_positive_hope() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope": 2.0})
	var s = ss.get_state()
	_assert(abs(s.hope - 7.0) < 0.001, "SS-1: applying +2 hope from 5 -> 7")

func _test_ss_apply_negative_conviction() -> void:
	var ss = _make_ss()
	ss.apply_choice({"conviction": -3.0})
	var s = ss.get_state()
	_assert(abs(s.conviction - 2.0) < 0.001, "SS-2: applying -3 conviction from 5 -> 2")

func _test_ss_apply_mixed_effect() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope": 1.0, "conviction": -0.5})
	var s = ss.get_state()
	_assert(abs(s.hope - 6.0) < 0.001, "SS-3: mixed effect hope -> 6")
	_assert(abs(s.conviction - 4.5) < 0.001, "SS-3: mixed effect conviction -> 4.5")
	_assert(abs(s.will - 5.0) < 0.001, "SS-3: mixed effect will unchanged")

func _test_ss_clamp_upper() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope": 20.0})
	var s = ss.get_state()
	_assert(abs(s.hope - 10.0) < 0.001, "SS-4: clamp upper hope at 10")

func _test_ss_clamp_lower() -> void:
	var ss = _make_ss()
	ss.apply_choice({"will": -20.0})
	var s = ss.get_state()
	_assert(abs(s.will - 0.0) < 0.001, "SS-5: clamp lower will at 0")

func _test_ss_reset_state() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope": 3.0, "conviction": 2.0, "will": 1.0})
	ss.reset()
	var s = ss.get_state()
	_assert(abs(s.hope - 5.0) < 0.001, "SS-6: reset restores hope=5")
	_assert(abs(s.conviction - 5.0) < 0.001, "SS-6: reset restores conviction=5")
	_assert(abs(s.will - 5.0) < 0.001, "SS-6: reset restores will=5")

func _test_ss_signal_on_apply() -> void:
	var ss = _make_ss()
	_ss_signal_fired = false
	_ss_captured_state = {}
	ss.state_changed.connect(_on_ss_state_changed)
	ss.apply_choice({"hope": 1.0})
	_assert(_ss_signal_fired, "SS-7: signal emitted on apply_choice")
	_assert(_ss_captured_state.has("hope"), "SS-7: signal state has 'hope' key")
	_assert(_ss_captured_state.has("conviction"), "SS-7: signal state has 'conviction' key")
	_assert(_ss_captured_state.has("will"), "SS-7: signal state has 'will' key")

func _test_ss_zero_effect() -> void:
	var ss = _make_ss()
	ss.apply_choice({})
	var s = ss.get_state()
	_assert(abs(s.hope - 5.0) < 0.001, "SS-8: empty effect hope unchanged")
	_assert(abs(s.conviction - 5.0) < 0.001, "SS-8: empty effect conviction unchanged")

func _test_ss_partial_effect() -> void:
	var ss = _make_ss()
	ss.apply_choice({"conviction": 2.0})
	var s = ss.get_state()
	_assert(abs(s.hope - 5.0) < 0.001, "SS-9: partial effect hope=5 (unchanged)")
	_assert(abs(s.conviction - 7.0) < 0.001, "SS-9: partial effect conviction=7")

func _test_ss_rapid_apply() -> void:
	var ss = _make_ss()
	for i in range(25):
		ss.apply_choice({"hope": 0.5})
	var s = ss.get_state()
	_assert(abs(s.hope - 10.0) < 0.001, "SS-10: 25 rapid +0.5 hope clamped at 10")

func _test_wv_tone_despair() -> void:
	var wv = load("res://gdscripts/worldview_controller.gd").new()
	var tone = wv._calculate_tone(2.0, 5.0)
	_assert(tone == "despair", "WV-1: hope=2 -> despair")

func _test_wv_tone_hope() -> void:
	var wv = load("res://gdscripts/worldview_controller.gd").new()
	var tone = wv._calculate_tone(8.0, 5.0)
	_assert(tone == "hope", "WV-2: hope=8 -> hope")

func _test_wv_tone_neutral() -> void:
	var wv = load("res://gdscripts/worldview_controller.gd").new()
	var tone = wv._calculate_tone(5.0, 5.0)
	_assert(tone == "neutral", "WV-3: hope=5 -> neutral")

func _test_wv_boundary_low() -> void:
	var wv = load("res://gdscripts/worldview_controller.gd").new()
	var tone = wv._calculate_tone(3.0, 5.0)
	_assert(tone == "despair", "WV-4: hope=3 (boundary) -> despair")

func _test_wv_boundary_high() -> void:
	var wv = load("res://gdscripts/worldview_controller.gd").new()
	var tone = wv._calculate_tone(7.0, 5.0)
	_assert(tone == "hope", "WV-5: hope=7 (boundary) -> hope")

func _test_wv_get_tone_for_state() -> void:
	var wv = load("res://gdscripts/worldview_controller.gd").new()
	var tone = wv.get_tone_for_state({"hope": 1.0})
	_assert(tone == "despair", "WV-6: get_tone_for_state hope=1 -> despair")
	tone = wv.get_tone_for_state({"hope": 9.0})
	_assert(tone == "hope", "WV-6: get_tone_for_state hope=9 -> hope")
	tone = wv.get_tone_for_state({"conviction": 5.0})
	_assert(tone == "neutral", "WV-6: get_tone_for_state defaults hope=5 -> neutral")

func _test_rain_high_conviction_low_rain() -> void:
	var rc = load("res://gdscripts/rain_controller.gd").new()
	rc._on_state_changed({"conviction": 9.0})
	_assert(abs(rc.rain_intensity - 0.1) < 0.001, "RC-1: conviction=9 -> intensity=0.1")

func _test_rain_low_conviction_high_rain() -> void:
	var rc = load("res://gdscripts/rain_controller.gd").new()
	rc._on_state_changed({"conviction": 1.0})
	_assert(abs(rc.rain_intensity - 0.9) < 0.001, "RC-2: conviction=1 -> intensity=0.9")

func _test_rain_mid_conviction() -> void:
	var rc = load("res://gdscripts/rain_controller.gd").new()
	rc._on_state_changed({"conviction": 5.0})
	_assert(abs(rc.rain_intensity - 0.5) < 0.001, "RC-3: conviction=5 -> intensity=0.5")

func _test_rain_intensity_clamp() -> void:
	var rc = load("res://gdscripts/rain_controller.gd").new()
	rc._on_state_changed({"conviction": -5.0})
	_assert(abs(rc.rain_intensity - 1.0) < 0.001, "RC-4: conviction=-5 clamped -> intensity=1.0")
	rc._on_state_changed({"conviction": 20.0})
	_assert(abs(rc.rain_intensity - 0.0) < 0.001, "RC-4: conviction=20 clamped -> intensity=0.0")

func _test_rain_shelter_trigger() -> void:
	var rc = load("res://gdscripts/rain_controller.gd").new()
	_rc_shelter_fired = false
	rc.forced_shelter_triggered.connect(_on_rc_shelter_triggered)
	rc.rain_intensity = 0.8
	rc._check_rain()
	_assert(_rc_shelter_fired, "RC-5: intensity=0.8 >= 0.7 -> shelter triggered")

func _test_rain_shelter_below_threshold() -> void:
	var rc = load("res://gdscripts/rain_controller.gd").new()
	var shelter_fired = false
	rc.forced_shelter_triggered.connect(func(): shelter_fired = true)
	rc.rain_intensity = 0.5
	rc._check_rain()
	_assert(not shelter_fired, "RC-6: intensity=0.5 < 0.7 -> no shelter")

func _test_clock_consume_one() -> void:
	var c = load("res://gdscripts/clock_manager.gd").new()
	c.consume_days()
	_assert(c.current_day == 1, "CLK-1: consume_days() day=1")

func _test_clock_consume_multiple() -> void:
	var c = load("res://gdscripts/clock_manager.gd").new()
	c.consume_days(5)
	_assert(c.current_day == 5, "CLK-2: consume_days(5) day=5")

func _test_clock_signal_emitted() -> void:
	var c = load("res://gdscripts/clock_manager.gd").new()
	_ss_signal_fired = false
	c.day_passed.connect(func(day: int, remaining: int): _ss_signal_fired = true)
	c.consume_days(3)
	_assert(_ss_signal_fired, "CLK-3: day_passed signal emitted on consume_days(3)")

func _test_clock_deadline_reached() -> void:
	var c = load("res://gdscripts/clock_manager.gd").new()
	_clock_reached = false
	c.deadline_reached.connect(_on_clock_reached)
	c.consume_days(90)
	_assert(_clock_reached, "CLK-4: deadline_reached fired at day 90")

func _test_clock_deadline_approaching() -> void:
	var c = load("res://gdscripts/clock_manager.gd").new()
	_clock_approaching = false
	c.deadline_approaching.connect(_on_clock_approaching)
	c.consume_days(76)
	_assert(_clock_approaching, "CLK-5: deadline_approaching at 14 days left")

func _test_clock_remaining() -> void:
	var c = load("res://gdscripts/clock_manager.gd").new()
	c.consume_days(30)
	_assert(c.get_remaining() == 60, "CLK-6: get_remaining=60 after 30 days")

func _test_clock_reset_state() -> void:
	var c = load("res://gdscripts/clock_manager.gd").new()
	c.consume_days(30)
	c.reset()
	_assert(c.current_day == 0, "CLK-7: reset day=0")
	_assert(c.get_remaining() == 90, "CLK-7: reset remaining=90")

func _test_dialogue_branch_condition_met() -> void:
	var state = {"hope": 8.0}
	var high_hope = func(s: Dictionary) -> bool:
		return s.get("hope", 0.0) >= 7.0
	var branches = [
		{"id": "a", "condition": high_hope},
		{"id": "b"}
	]
	var node = {"branches": branches}
	var visible = []
	for branch in node.get("branches", []):
		if branch.has("condition") and branch.condition != null:
			if branch.condition.call(state):
				visible.append(branch)
		else:
			visible.append(branch)
	_assert(visible.size() == 2, "DE-1: both branches visible when condition met")

func _test_dialogue_branch_condition_not_met() -> void:
	var state = {"hope": 2.0}
	var high_hope = func(s: Dictionary) -> bool:
		return s.get("hope", 0.0) >= 7.0
	var branches = [
		{"id": "a", "condition": high_hope},
		{"id": "b"}
	]
	var node = {"branches": branches}
	var visible = []
	for branch in node.get("branches", []):
		if branch.has("condition") and branch.condition != null:
			if branch.condition.call(state):
				visible.append(branch)
		else:
			visible.append(branch)
	_assert(visible.size() == 1, "DE-2: only unconditional branch when condition fails")
	_assert(visible[0].id == "b", "DE-2: visible branch is 'b'")

func _test_dialogue_branch_no_condition() -> void:
	var branches = [
		{"id": "a"},
		{"id": "b"}
	]
	var node = {"branches": branches}
	var visible = []
	for branch in node.get("branches", []):
		if branch.has("condition") and branch.condition != null:
			if branch.condition.call({}):
				visible.append(branch)
		else:
			visible.append(branch)
	_assert(visible.size() == 2, "DE-3: all branches visible when no conditions")

func _test_dialogue_branch_mixed_conditions() -> void:
	var state = {"hope": 5.0}
	var high_hope = func(s: Dictionary) -> bool:
		return s.get("hope", 0.0) >= 7.0
	var low_hope = func(s: Dictionary) -> bool:
		return s.get("hope", 0.0) <= 3.0
	var branches = [
		{"id": "high", "condition": high_hope},
		{"id": "low", "condition": low_hope},
		{"id": "default"}
	]
	var node = {"branches": branches}
	var visible = []
	for branch in node.get("branches", []):
		if branch.has("condition") and branch.condition != null:
			if branch.condition.call(state):
				visible.append(branch)
		else:
			visible.append(branch)
	_assert(visible.size() == 1, "DE-4: only default visible when hope=5.0")
	_assert(visible[0].id == "default", "DE-4: visible branch is 'default'")

func _test_dialogue_choice_effect_applied() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope": 2.0, "conviction": 1.0})
	var s = ss.get_state()
	_assert(abs(s.hope - 7.0) < 0.001, "DE-5: choice effect hope=7.0")
	_assert(abs(s.conviction - 6.0) < 0.001, "DE-5: choice effect conviction=6.0")

# ===== Dialogue Engine Tests (Issue #46) =====

func run_dialogue_engine_tests() -> void:
	var tester = load("res://tests/test_dialogue_engine.gd").new()
	tester.run()
	passed += tester.passed
	failed += tester.failed

# ===== Dialogue Engine v2 Tests (Issue #52) =====

func run_dialogue_engine_v2_tests() -> void:
	var tester = load("res://tests/test_dialogue_engine_v2.gd").new()
	tester.run()
	passed += tester.passed
	failed += tester.failed

# ===== Narrative Architecture Tests (Issue #45) =====

func run_narrative_architecture_tests() -> void:
	var tester = load("res://tests/test_narrative_architecture.gd").new()
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

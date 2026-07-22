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

	# --- Bridge/Underpass Tests (Issue #58) ---
	run_bridge_underpass_tests()

	# --- Sound System Tests (Issue #48) ---
	run_sound_system_tests()

	# --- GameState System Tests (Issue #47) ---
	run_gamestate_system_47_tests()

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

func run_bridge_underpass_tests() -> void:
	var tester = load("res://tests/test_bridge_underpass.gd").new()
	tester.run()
	passed += tester.passed
	failed += tester.failed


func run_sound_system_tests() -> void:
	var unit = load("res://tests/unit/test_audio_manager.gd").new()
	unit.run()
	passed += unit.passed
	failed += unit.failed

	var state_mod = load("res://tests/integration/test_audio_state_modulation.gd").new()
	state_mod.run()
	passed += state_mod.passed
	failed += state_mod.failed

	var transition = load("res://tests/integration/test_audio_scene_transition.gd").new()
	transition.run()
	passed += transition.passed
	failed += transition.failed

	var footstep = load("res://tests/integration/test_audio_footstep_dialogue.gd").new()
	footstep.run()
	passed += footstep.passed
	failed += footstep.failed


# ===== GameState System Tests (Issue #47) =====

func run_gamestate_system_47_tests() -> void:
	print("\n=== GameState System Tests (Issue #47) ===\n")

	# TC1-TC7: Slider & State ID
	_test_47_tc1_initial_state()
	_test_47_tc2_clamp_range()
	_test_47_tc3_state_id_values()
	_test_47_tc4_boundary_despair()
	_test_47_tc5_boundary_low()
	_test_47_tc6_boundary_neutral()
	_test_47_tc7_boundary_buoyant()

	# TC8-TC12: Signal Emission
	_test_47_tc8_state_changed_fires()
	_test_47_tc9_state_changed_payload()
	_test_47_tc10_state_id_changed_on_transition()
	_test_47_tc11_state_id_changed_not_on_intra()
	_test_47_tc12_state_changed_on_load()

	# TC13-TC16: Flags
	_test_47_tc13_set_flag()
	_test_47_tc14_has_flag_unset()
	_test_47_tc15_get_flags()
	_test_47_tc16_flags_save_load()

	# TC17-TC19: Choice History
	_test_47_tc17_record_choice()
	_test_47_tc18_choice_history_cap()
	_test_47_tc19_choice_history_roundtrip()

	# TC20-TC23: Save/Load
	_test_47_tc20_save_valid()
	_test_47_tc21_load_restores()
	_test_47_tc22_load_missing()
	_test_47_tc23_load_corrupt()

	# TC24-TC26: Derived Values
	_test_47_tc24_hope_derived()
	_test_47_tc25_hope_zero()
	_test_47_tc26_hope_ten()

	# TC27-TC29: GameManager Delegation
	_test_47_tc27_gm_get_slider()
	_test_47_tc28_gm_apply_slider_delta()
	_test_47_tc29_gm_flag_delegation()

	# TC30-TC31: Legacy Deprecation
	_test_47_tc30_legacy_get_state()
	_test_47_tc31_legacy_apply_state()

	print("  GameState System Tests (#47): %d passed, %d failed" % [_47_passed, _47_failed])
	passed += _47_passed
	failed += _47_failed


# === Test state ===
var _47_passed: int = 0
var _47_failed: int = 0

# Signal capture helpers
var _47_signal_fired: bool = false
var _47_captured_state: Dictionary = {}
var _47_state_id_changed_fired: bool = false
var _47_captured_state_id: int = 0

func _47_make_ss():
	var ss = load("res://gdscripts/state_system.gd").new()
	ss.state_changed.connect(_47_on_state_changed)
	ss.state_id_changed.connect(_47_on_state_id_changed)
	return ss

func _47_on_state_changed(state: Dictionary) -> void:
	_47_signal_fired = true
	_47_captured_state = state

func _47_on_state_id_changed(state_id: int) -> void:
	_47_state_id_changed_fired = true
	_47_captured_state_id = state_id

func _47_reset_signals() -> void:
	_47_signal_fired = false
	_47_captured_state = {}
	_47_state_id_changed_fired = false
	_47_captured_state_id = 0

func _47_assert(condition: bool, name: String) -> void:
	if condition:
		_47_passed += 1
		print("  ✅ ", name)
	else:
		_47_failed += 1
		print("  ❌ ", name)


# --- TC1-TC7: Slider & State ID ---

func _test_47_tc1_initial_state() -> void:
	var ss = _47_make_ss()
	_47_assert(abs(ss.hope_despair - 0.0) < 0.001, "TC1: hope_despair initializes to 0.0")
	_47_assert(ss.get_state_id() == 3, "TC1: state_id == 3 (Neutral)")

func _test_47_tc2_clamp_range() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = 0.0
	ss.apply_choice({"hope_despair": 20.0})
	_47_assert(abs(ss.hope_despair - 10.0) < 0.001, "TC2: +20 delta clamped to 10.0")
	ss.apply_choice({"hope_despair": -25.0})
	_47_assert(abs(ss.hope_despair - (-10.0)) < 0.001, "TC2: -25 delta clamped to -10.0")

func _test_47_tc3_state_id_values() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = -10.0
	_47_assert(ss.get_state_id() == 1, "TC3: hope_despair=-10 -> state_id=1 (Despair)")
	ss.hope_despair = -6.0
	_47_assert(ss.get_state_id() == 1, "TC3: hope_despair=-6 -> state_id=1 (Despair)")
	ss.hope_despair = 0.0
	_47_assert(ss.get_state_id() == 3, "TC3: hope_despair=0 -> state_id=3 (Neutral)")
	ss.hope_despair = 6.0
	_47_assert(ss.get_state_id() == 4, "TC3: hope_despair=6 -> state_id=4 (Buoyant)")
	ss.hope_despair = 10.0
	_47_assert(ss.get_state_id() == 5, "TC3: hope_despair=10 -> state_id=5 (Hope)")

func _test_47_tc4_boundary_despair() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = -6.0
	_47_assert(ss.get_state_id() == 1, "TC4: hope_despair=-6.0 -> state_id=1 (Despair, inclusive)")

func _test_47_tc5_boundary_low() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = -2.0
	_47_assert(ss.get_state_id() == 2, "TC5: hope_despair=-2.0 -> state_id=2 (Low, inclusive)")

func _test_47_tc6_boundary_neutral() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = 2.0
	_47_assert(ss.get_state_id() == 3, "TC6: hope_despair=2.0 -> state_id=3 (Neutral, inclusive)")

func _test_47_tc7_boundary_buoyant() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = 6.0
	_47_assert(ss.get_state_id() == 4, "TC7: hope_despair=6.0 -> state_id=4 (Buoyant, inclusive)")


# --- TC8-TC12: Signal Emission ---

func _test_47_tc8_state_changed_fires() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	_47_reset_signals()
	ss.state_changed.connect(_47_on_state_changed)
	ss.apply_choice({"hope_despair": 1.0})
	_47_assert(_47_signal_fired, "TC8: state_changed fires on apply_choice()")

func _test_47_tc9_state_changed_payload() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	_47_reset_signals()
	ss.state_changed.connect(_47_on_state_changed)
	ss.set_flag("test_flag", true)
	ss.apply_choice({"hope_despair": 2.0, "conviction": 1.0})
	_47_assert(_47_captured_state.has("hope_despair"), "TC9: payload has hope_despair")
	_47_assert(_47_captured_state.has("hope"), "TC9: payload has hope")
	_47_assert(_47_captured_state.has("despair"), "TC9: payload has despair")
	_47_assert(_47_captured_state.has("conviction"), "TC9: payload has conviction")
	_47_assert(_47_captured_state.has("will"), "TC9: payload has will")
	_47_assert(_47_captured_state.has("state_id"), "TC9: payload has state_id")
	_47_assert(_47_captured_state.has("flags"), "TC9: payload has flags")
	_47_assert(_47_captured_state.has("choice_count"), "TC9: payload has choice_count")

func _test_47_tc10_state_id_changed_on_transition() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	_47_reset_signals()
	ss.state_id_changed.connect(_47_on_state_id_changed)
	# Move from Neutral (3) to Buoyant (4)
	ss.apply_choice({"hope_despair": 3.0})
	_47_assert(_47_state_id_changed_fired, "TC10: state_id_changed fires on state transition")
	_47_assert(_47_captured_state_id == 4, "TC10: new state_id=4 (Buoyant)")

func _test_47_tc11_state_id_changed_not_on_intra() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	_47_reset_signals()
	ss.state_id_changed.connect(_47_on_state_id_changed)
	# Move within Neutral (3): 0.0 -> 1.0, still state 3
	ss.apply_choice({"hope_despair": 1.0})
	_47_assert(not _47_state_id_changed_fired, "TC11: state_id_changed does NOT fire on intra-state change")
	# But state_changed should still fire
	_47_assert(_47_signal_fired, "TC11: state_changed still fires on intra-state change")

func _test_47_tc12_state_changed_on_load() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = 5.0
	var save_path: String = "user://test_47_tc12.json"
	ss.save_state_to_file(save_path)
	ss.hope_despair = -5.0  # Modify after save
	_47_reset_signals()
	var result: bool = ss.load_state_from_file(save_path)
	_47_assert(result, "TC12: load returns true")
	_47_assert(_47_signal_fired, "TC12: state_changed fires after load_state_from_file")


# --- TC13-TC16: Flags ---

func _test_47_tc13_set_flag() -> void:
	var ss = _47_make_ss()
	ss.set_flag("test_flag", true)
	_47_assert(ss.has_flag("test_flag"), "TC13: set_flag creates and stores a flag")

func _test_47_tc14_has_flag_unset() -> void:
	var ss = _47_make_ss()
	_47_assert(not ss.has_flag("nonexistent"), "TC14: has_flag returns false for unset flags")

func _test_47_tc15_get_flags() -> void:
	var ss = _47_make_ss()
	ss.set_flag("a", true)
	ss.set_flag("b", false)
	ss.set_flag("c", true)
	var flags: Dictionary = ss.get_flags()
	_47_assert(flags.size() == 3, "TC15: get_flags returns 3 entries")
	_47_assert(flags.get("a", false), "TC15: flag 'a' = true")
	_47_assert(not flags.get("b", true), "TC15: flag 'b' = false")
	_47_assert(flags.get("c", false), "TC15: flag 'c' = true")

func _test_47_tc16_flags_save_load() -> void:
	var ss1 = _47_make_ss()
	ss1.set_flag("met_stranger", true)
	ss1.set_flag("bought_coffee", false)
	var save_path: String = "user://test_47_tc16.json"
	_47_assert(ss1.save_state_to_file(save_path), "TC16: save returns true")

	var ss2 = _47_make_ss()
	var result: bool = ss2.load_state_from_file(save_path)
	_47_assert(result, "TC16: load returns true")
	_47_assert(ss2.has_flag("met_stranger"), "TC16: flag 'met_stranger' restored")
	_47_assert(not ss2.has_flag("bought_coffee"), "TC16: flag 'bought_coffee' restored as false")


# --- TC17-TC19: Choice History ---

func _test_47_tc17_record_choice() -> void:
	var ss = _47_make_ss()
	ss.record_choice("n_01", 0, "I'll wait.")
	ss.record_choice("n_02", 1, "Let's go.")
	ss.record_choice("n_01", 2, "No thanks.")
	_47_assert(ss.get_choice_count() == 3, "TC17: choice count = 3")
	var history: Array[Dictionary] = ss.get_choice_history()
	_47_assert(history.size() == 3, "TC17: history has 3 entries")
	_47_assert(history[0]["node_id"] == "n_01", "TC17: first entry node_id = n_01")
	_47_assert(history[0]["choice_text"] == "I'll wait.", "TC17: first entry choice_text correct")
	_47_assert(history[0].has("timestamp"), "TC17: first entry has timestamp")

func _test_47_tc18_choice_history_cap() -> void:
	var ss = _47_make_ss()
	for i in range(210):
		ss.record_choice("n_%d" % i, 0, "Choice %d" % i)
	_47_assert(ss.get_choice_count() == 200, "TC18: choice count capped at 200")
	var history: Array[Dictionary] = ss.get_choice_history()
	_47_assert(history.size() == 200, "TC18: history has 200 entries")
	_47_assert(history[0]["node_id"] == "n_10", "TC18: oldest entry dropped (starts at n_10)")
	_47_assert(history[199]["node_id"] == "n_209", "TC18: newest entry is n_209")

func _test_47_tc19_choice_history_roundtrip() -> void:
	var ss1 = _47_make_ss()
	ss1.record_choice("n_01", 0, "Hello")
	ss1.record_choice("n_02", 1, "World")
	ss1.record_choice("n_03", 0, "Test")
	var save_path: String = "user://test_47_tc19.json"
	_47_assert(ss1.save_state_to_file(save_path), "TC19: save returns true")

	var ss2 = _47_make_ss()
	var result: bool = ss2.load_state_from_file(save_path)
	_47_assert(result, "TC19: load returns true")
	_47_assert(ss2.get_choice_count() == 3, "TC19: choice count restored = 3")
	var h2: Array[Dictionary] = ss2.get_choice_history()
	_47_assert(h2[0]["node_id"] == "n_01", "TC19: first entry node_id = n_01")
	_47_assert(h2[1]["choice_text"] == "World", "TC19: second entry text = 'World'")


# --- TC20-TC23: Save/Load ---

func _test_47_tc20_save_valid() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = 3.0
	ss.conviction = 7.0
	ss.will = 2.0
	ss.set_flag("test", true)
	ss.record_choice("n_01", 0, "Test choice")
	var save_path: String = "user://test_47_tc20.json"
	var result: bool = ss.save_state_to_file(save_path)
	_47_assert(result, "TC20: save returns true")

func _test_47_tc21_load_restores() -> void:
	var ss1 = _47_make_ss()
	ss1.hope_despair = 3.0
	ss1.conviction = 7.0
	ss1.will = 2.0
	ss1.set_flag("test_flag", true)
	ss1.record_choice("n_01", 0, "Test choice")
	var save_path: String = "user://test_47_tc21.json"
	_47_assert(ss1.save_state_to_file(save_path), "TC21: save returns true")

	var ss2 = _47_make_ss()
	var result: bool = ss2.load_state_from_file(save_path)
	_47_assert(result, "TC21: load returns true")
	_47_assert(abs(ss2.hope_despair - 3.0) < 0.001, "TC21: hope_despair restored = 3.0")
	_47_assert(abs(ss2.conviction - 7.0) < 0.001, "TC21: conviction restored = 7.0")
	_47_assert(abs(ss2.will - 2.0) < 0.001, "TC21: will restored = 2.0")
	_47_assert(ss2.has_flag("test_flag"), "TC21: flag restored")
	_47_assert(ss2.get_choice_count() == 1, "TC21: choice count restored = 1")

func _test_47_tc22_load_missing() -> void:
	var ss = _47_make_ss()
	var result: bool = ss.load_state_from_file("user://nonexistent_file.json")
	_47_assert(not result, "TC22: load from missing file returns false")

func _test_47_tc23_load_corrupt() -> void:
	var ss = _47_make_ss()
	# Write corrupt JSON
	var file: FileAccess = FileAccess.open("user://test_47_tc23_corrupt.json", FileAccess.WRITE)
	file.store_string("{invalid json!!!")
	file.close()

	var result: bool = ss.load_state_from_file("user://test_47_tc23_corrupt.json")
	_47_assert(not result, "TC23: load from corrupt JSON returns false")


# --- TC24-TC26: Derived Values ---

func _test_47_tc24_hope_derived() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = 0.0
	_47_assert(abs(ss.hope - 5.0) < 0.001, "TC24: hope_despair=0 -> hope=5.0")

func _test_47_tc25_hope_zero() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = -10.0
	_47_assert(abs(ss.hope - 0.0) < 0.001, "TC25: hope_despair=-10 -> hope=0.0")

func _test_47_tc26_hope_ten() -> void:
	var ss = _47_make_ss()
	ss.hope_despair = 10.0
	_47_assert(abs(ss.hope - 10.0) < 0.001, "TC26: hope_despair=10 -> hope=10.0")


# --- TC27-TC29: GameManager Delegation ---

func _test_47_tc27_gm_get_slider() -> void:
	# We can't fully test this in --script mode (no autoloads),
	# but we can test GameManager's delegation by wiring manually.
	var ss = load("res://gdscripts/state_system.gd").new()
	ss.hope_despair = 3.0
	var gm = load("res://gdscripts/game_manager.gd").new()
	gm._state_system = ss  # Wire manually for test
	var val: float = gm.get_slider("hope_despair")
	_47_assert(abs(val - 3.0) < 0.001, "TC27: GameManager.get_slider returns hope_despair=3.0")

func _test_47_tc28_gm_apply_slider_delta() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	var gm = load("res://gdscripts/game_manager.gd").new()
	gm._state_system = ss
	gm.apply_slider_delta("hope_despair", 2.0)
	_47_assert(abs(ss.hope_despair - 2.0) < 0.001, "TC28: apply_slider_delta increases hope_despair by 2.0")

func _test_47_tc29_gm_flag_delegation() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	var gm = load("res://gdscripts/game_manager.gd").new()
	gm._state_system = ss
	gm.set_flag("test_flag", true)
	_47_assert(gm.has_flag("test_flag"), "TC29: GameManager.has_flag returns true via StateSystem")
	_47_assert(ss.has_flag("test_flag"), "TC29: StateSystem flag also set")
	# Test get_flags
	var flags: Dictionary = gm.get_flags()
	_47_assert(flags.get("test_flag", false), "TC29: GameManager.get_flags includes test_flag=true")


# --- TC30-TC31: Legacy Deprecation ---

func _test_47_tc30_legacy_get_state() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	ss.hope_despair = 5.0
	ss.conviction = 7.0
	ss.will = 3.0
	var gs = load("res://gdscripts/game_state.gd").new()
	# Wire GameState's internal _state_system
	gs._state_system = ss
	var state: Dictionary = gs.get_state()
	_47_assert(state.has("hope"), "TC30: legacy get_state returns 'hope'")
	_47_assert(state.has("despair"), "TC30: legacy get_state returns 'despair'")
	_47_assert(state["hope"] == clampi(int(ss.hope * 10.0), 0, 100), "TC30: hope matches scaled StateSystem value")

func _test_47_tc31_legacy_apply_state() -> void:
	var ss = load("res://gdscripts/state_system.gd").new()
	var gs = load("res://gdscripts/game_state.gd").new()
	gs._state_system = ss
	var hope_before: float = ss.hope
	gs.apply_state(10, 0)  # +10 hope in 0-100 scale
	# 10 * 0.2 = 2.0 hope_despair delta
	_47_assert(abs(ss.hope_despair - 2.0) < 0.001, "TC31: apply_state(+10,0) -> hope_despair +2.0")


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ ", name)
	else:
		failed += 1
		print("  ❌ ", name)

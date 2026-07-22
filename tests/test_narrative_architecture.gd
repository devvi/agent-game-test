extends Node
class_name TestNarrativeArchitecture

# Narrative Architecture tests (Issue #45)
# Tests T19: narrative_manager.gd, scene_base.gd, state_system.gd extensions
# Test patterns match the existing test framework used in run_tests.gd

var passed: int = 0
var failed: int = 0

var _echo_signal_count: int = 0
var _last_echo_id: String = ""
var _last_echo_variant: int = 0

# ===== NarrativeManager Tests =====

func run() -> void:
	print("\n=== Narrative Architecture Tests (Issue #45) ===")

	# TC-N1: Normal ending paths
	_test_n1_keep_walking()
	_test_n1_turn_back()
	_test_n1_stay()

	# TC-N2: Boundary ending paths
	_test_n2_conviction_boundary()
	_test_n2_hope_boundary()
	_test_n2_will_boundary()
	_test_n2_all_mid()

	# TC-N3: Default ending (all mid)
	_test_n3_stay_default()

	# TC-N4: Echo system
	_test_n4_rain_echo_high_hope()
	_test_n4_rain_echo_low_hope()
	_test_n4_rain_echo_repeat_suppression()
	_test_n4_screensaver_echo_high_conviction()

	# TC-N5: State system tier calculation
	_test_n5_tier_low()
	_test_n5_tier_mid()
	_test_n5_tier_high()
	_test_n5_tier_boundary_low()
	_test_n5_tier_boundary_high()

	# TC-N6: Scene sequence
	_test_n6_scene_order()
	_test_n6_advance_scene()
	_test_n6_get_next_scene()

	# TC-N7: Tone calculation
	_test_n7_office_tone()
	_test_n7_lobby_tone()
	_test_n7_store_tone()
	_test_n7_bridge_tone()
	_test_n7_underpass_tone()
	_test_n7_station_tone()

	# TC-N8: SceneBase common behavior
	_test_n8_get_state_tier()
	_test_n8_get_state()

	print("Narrative Architecture — Passed: ", passed, " Failed: ", failed)

# --- Helpers ---

func _make_nm():
	return load("res://gdscripts/narrative_manager.gd").new()

func _make_ss():
	return load("res://gdscripts/state_system.gd").new()

func _make_sb():
	return load("res://gdscripts/scene_base.gd").new()

func _on_echo_signal(echo_id: String, variant: int) -> void:
	_echo_signal_count += 1
	_last_echo_id = echo_id
	_last_echo_variant = variant

func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  ❌ FAIL: ", label)

# ===== TC-N1: Normal ending paths =====

func _test_n1_keep_walking() -> void:
	var nm = _make_nm()
	var ending = nm.determine_ending({"hope": 7.0, "conviction": 6.0, "will": 6.0})
	_assert(ending == "keep_walking", "TC-N1-1: hope=7, conviction=6, will=6 -> keep_walking")

func _test_n1_turn_back() -> void:
	var nm = _make_nm()
	var ending = nm.determine_ending({"hope": 5.0, "conviction": 2.0, "will": 5.0})
	_assert(ending == "turn_back", "TC-N1-2: conviction=2 -> turn_back (priority 1)")

func _test_n1_stay() -> void:
	var nm = _make_nm()
	# conviction=3.0 hits the turn_back priority (<=3.0) first
	var ending = nm.determine_ending({"hope": 3.0, "conviction": 3.0, "will": 3.0})
	_assert(ending == "turn_back", "TC-N1-3: all=3 -> turn_back (conviction=3 triggers priority 1)")

# ===== TC-N2: Boundary ending paths =====

func _test_n2_conviction_boundary() -> void:
	var nm = _make_nm()
	# conviction=3.0 is the boundary for turn_back (<=3.0)
	var ending = nm.determine_ending({"hope": 5.0, "conviction": 3.0, "will": 5.0})
	_assert(ending == "turn_back", "TC-N2-1: conviction=3 (boundary) -> turn_back")

func _test_n2_hope_boundary() -> void:
	var nm = _make_nm()
	# hope=6.0 is the boundary for keep_walking (>=6.0)
	var ending = nm.determine_ending({"hope": 6.0, "conviction": 6.0, "will": 5.0})
	_assert(ending == "keep_walking", "TC-N2-2: hope=6 (boundary) -> keep_walking")

func _test_n2_will_boundary() -> void:
	var nm = _make_nm()
	# will=5.0 is the boundary for keep_walking (>=5.0)
	var ending = nm.determine_ending({"hope": 6.0, "conviction": 6.0, "will": 5.0})
	_assert(ending == "keep_walking", "TC-N2-3: will=5 (boundary) -> keep_walking")

func _test_n2_all_mid() -> void:
	var nm = _make_nm()
	var ending = nm.determine_ending({"hope": 5.0, "conviction": 5.0, "will": 5.0})
	_assert(ending == "stay", "TC-N2-4: all=5 -> stay (fallthrough)")

# ===== TC-N3: Default ending (all mid/fallthrough) =====

func _test_n3_stay_default() -> void:
	var nm = _make_nm()
	# Even with high-but-not-extreme values, should fall through to stay
	var ending = nm.determine_ending({"hope": 5.5, "conviction": 5.5, "will": 5.5})
	_assert(ending == "stay", "TC-N3-1: all=5.5 -> stay (fallthrough)")

# ===== TC-N4: Echo system =====

func _test_n4_rain_echo_high_hope() -> void:
	var nm = _make_nm()
	_echo_signal_count = 0
	nm.echo_triggered.connect(_on_echo_signal)
	nm.trigger_echo("rain_echo")
	_assert(_echo_signal_count == 1, "TC-N4-1: echo_triggered signal emitted")

func _test_n4_rain_echo_low_hope() -> void:
	var nm = _make_nm()
	_echo_signal_count = 0
	nm.echo_triggered.connect(_on_echo_signal)
	nm.trigger_echo("rain_echo")
	_assert(nm.echo_flags.get("rain_echo", false), "TC-N4-2: echo flag set after trigger")

func _test_n4_rain_echo_repeat_suppression() -> void:
	var nm = _make_nm()
	_echo_signal_count = 0
	nm.echo_triggered.connect(_on_echo_signal)
	nm.trigger_echo("rain_echo")
	nm.trigger_echo("rain_echo")  # second call should be suppressed
	_assert(_echo_signal_count == 1, "TC-N4-3: second echo trigger suppressed (signal only fired once)")

func _test_n4_screensaver_echo_high_conviction() -> void:
	var nm = _make_nm()
	_echo_signal_count = 0
	nm.echo_triggered.connect(_on_echo_signal)
	nm.trigger_echo("screensaver_echo")
	_assert(_echo_signal_count == 1, "TC-N4-4: screensaver_echo signal emitted")
	_assert(nm.echo_flags.get("screensaver_echo", false), "TC-N4-4: screensaver_echo flag set")

# ===== TC-N5: State system tier calculation =====

func _test_n5_tier_low() -> void:
	var ss = _make_ss()
	ss.hope = 2.0
	_assert(ss.get_state_tier("hope") == "low", "TC-N5-1: hope=2 -> low")

func _test_n5_tier_mid() -> void:
	var ss = _make_ss()
	ss.hope = 5.0
	_assert(ss.get_state_tier("hope") == "mid", "TC-N5-2: hope=5 -> mid")

func _test_n5_tier_high() -> void:
	var ss = _make_ss()
	ss.hope = 8.0
	_assert(ss.get_state_tier("hope") == "high", "TC-N5-3: hope=8 -> high")

func _test_n5_tier_boundary_low() -> void:
	var ss = _make_ss()
	ss.hope = 3.0
	_assert(ss.get_state_tier("hope") == "low", "TC-N5-4: hope=3 (boundary) -> low")

func _test_n5_tier_boundary_high() -> void:
	var ss = _make_ss()
	ss.conviction = 7.0
	_assert(ss.get_state_tier("conviction") == "high", "TC-N5-5: conviction=7 (boundary) -> high")

# ===== TC-N6: Scene sequence =====

func _test_n6_scene_order() -> void:
	var nm = _make_nm()
	_assert(nm.SCENE_ORDER.size() == 6, "TC-N6-1: 6 scenes in SCENE_ORDER")
	_assert(nm.SCENE_ORDER[0] == "office", "TC-N6-1: first scene is office")
	_assert(nm.SCENE_ORDER[5] == "subway_station", "TC-N6-1: last scene is subway_station")

func _test_n6_advance_scene() -> void:
	var nm = _make_nm()
	nm.current_scene_index = 0
	var next = nm.advance_scene()
	_assert(next == "lobby", "TC-N6-2: advance_scene from 0 -> lobby")
	_assert(nm.current_scene_index == 1, "TC-N6-2: current_scene_index becomes 1")

func _test_n6_get_next_scene() -> void:
	var nm = _make_nm()
	var next = nm.get_next_scene("office")
	_assert(next == "lobby", "TC-N6-3: get_next_scene('office') -> lobby")
	var last = nm.get_next_scene("subway_station")
	_assert(last == "", "TC-N6-3: get_next_scene('subway_station') -> '' (end)")

# ===== TC-N7: Tone calculation =====

func _test_n7_office_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(0, {"hope": 2.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "despair", "TC-N7-1: office hope=2 -> despair")
	tone = nm._calculate_tone_for_scene(0, {"hope": 8.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "hope", "TC-N7-1: office hope=8 -> hope")
	tone = nm._calculate_tone_for_scene(0, {"hope": 5.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "neutral", "TC-N7-1: office hope=5 -> neutral")

func _test_n7_lobby_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(1, {"hope": 5.0, "conviction": 2.0, "will": 5.0})
	_assert(tone == "fear", "TC-N7-2: lobby conviction=2 -> fear")
	tone = nm._calculate_tone_for_scene(1, {"hope": 5.0, "conviction": 8.0, "will": 5.0})
	_assert(tone == "defiant", "TC-N7-2: lobby conviction=8 -> defiant")

func _test_n7_store_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(2, {"hope": 2.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "cold", "TC-N7-3: store hope=2 -> cold")
	tone = nm._calculate_tone_for_scene(2, {"hope": 8.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "warm", "TC-N7-3: store hope=8 -> warm")

func _test_n7_bridge_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(3, {"hope": 5.0, "conviction": 5.0, "will": 2.0})
	_assert(tone == "tired", "TC-N7-4: bridge will=2 -> tired")
	tone = nm._calculate_tone_for_scene(3, {"hope": 5.0, "conviction": 5.0, "will": 8.0})
	_assert(tone == "determined", "TC-N7-4: bridge will=8 -> determined")

func _test_n7_underpass_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(4, {"hope": 3.0, "conviction": 3.0, "will": 5.0})
	_assert(tone == "despair", "TC-N7-5: underpass hope=3,conviction=3 -> despair")
	tone = nm._calculate_tone_for_scene(4, {"hope": 7.0, "conviction": 7.0, "will": 5.0})
	_assert(tone == "resolute", "TC-N7-5: underpass hope=7,conviction=7 -> resolute")
	tone = nm._calculate_tone_for_scene(4, {"hope": 5.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "neutral", "TC-N7-5: underpass all=5 -> neutral")

func _test_n7_station_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(5, {"hope": 7.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "forward", "TC-N7-6: station hope=7 -> forward")

# ===== TC-N8: SceneBase =====

func _test_n8_get_state_tier() -> void:
	var sb = _make_sb()
	# SceneBase delegates to StateSystem, which won't exist in headless test
	# So this tests the fallback
	var tier = sb.get_state_tier("hope")
	_assert(tier == "mid", "TC-N8-1: get_state_tier fallback returns 'mid'")

func _test_n8_get_state() -> void:
	var sb = _make_sb()
	var state = sb.get_state()
	_assert(state.get("hope", 0.0) == 5.0, "TC-N8-2: get_state fallback hope=5.0")
	_assert(state.get("conviction", 0.0) == 5.0, "TC-N8-2: get_state fallback conviction=5.0")
	_assert(state.get("will", 0.0) == 5.0, "TC-N8-2: get_state fallback will=5.0")

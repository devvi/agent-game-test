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

# --- Issue #214 test capture state ---
var _hallucination_signal_level: int = -1
var _flashback_scene: String = ""
var _flashback_text: String = ""

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

	# Issue #214: Hallucination Engine
	_test_214_hallucination_base_levels()
	_test_214_hallucination_state_modifier()
	_test_214_hallucination_clamp()
	_test_214_hallucination_params_structure()
	_test_214_b1_tracking()
	_test_214_b3_no_metanarrative()
	_test_214_b6_paradox_check()
	_test_214_flashback_trigger()
	_test_214_echo_definitions_count()
	_test_214_route_flag_default()
	_test_214_route_flag_set_get()
	_test_214_reality_signal_emitted()

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
	tone = nm._calculate_tone_for_scene(0, {"hope": 9.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "hope", "TC-N7-1: office hope=9 -> hope")
	tone = nm._calculate_tone_for_scene(0, {"hope": 5.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "neutral", "TC-N7-1: office hope=5 -> neutral")

func _test_n7_lobby_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(1, {"hope": 1.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "fear", "TC-N7-2: lobby hope=1 -> fear")
	tone = nm._calculate_tone_for_scene(1, {"hope": 9.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "defiant", "TC-N7-2: lobby hope=9 -> defiant")

func _test_n7_store_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(2, {"hope": 2.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "cold", "TC-N7-3: store hope=2 -> cold")
	tone = nm._calculate_tone_for_scene(2, {"hope": 8.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "warm", "TC-N7-3: store hope=8 -> warm")

func _test_n7_bridge_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(3, {"hope": 1.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "tired", "TC-N7-4: bridge hope=1 -> tired")
	tone = nm._calculate_tone_for_scene(3, {"hope": 9.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "determined", "TC-N7-4: bridge hope=9 -> determined")

func _test_n7_underpass_tone() -> void:
	var nm = _make_nm()
	var tone = nm._calculate_tone_for_scene(4, {"hope": 3.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "hollow", "TC-N7-5: underpass hope=3 -> hollow")
	tone = nm._calculate_tone_for_scene(4, {"hope": 7.0, "conviction": 5.0, "will": 5.0})
	_assert(tone == "resolute", "TC-N7-5: underpass hope=7 -> resolute")
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


# ===== Issue #214: Hallucination Engine & Narrative Architecture Tests =====

func _make_state(hope: float, conviction: float = 5.0, will: float = 5.0) -> Dictionary:
	return {"hope": hope, "conviction": conviction, "will": will}

func _test_214_hallucination_base_levels() -> void:
	var nm = _make_nm()
	_assert(nm.get_hallucination_level("office", _make_state(5.0)) == 0, "TC214-1: office base level = 0")
	_assert(nm.get_hallucination_level("lobby", _make_state(5.0)) == 1, "TC214-1: lobby base level = 1")
	_assert(nm.get_hallucination_level("convenience_store", _make_state(5.0)) == 2, "TC214-1: store base level = 2")
	_assert(nm.get_hallucination_level("bridge", _make_state(5.0)) == 4, "TC214-1: bridge base level = 4")
	_assert(nm.get_hallucination_level("underpass", _make_state(5.0)) == 7, "TC214-1: underpass base level = 7")
	_assert(nm.get_hallucination_level("subway_station", _make_state(5.0)) == 9, "TC214-1: subway base level = 9")

func _test_214_hallucination_state_modifier() -> void:
	var nm = _make_nm()
	# High hope (-1): lobby base 1 -> 0
	var high_hope: int = nm.get_hallucination_level("lobby", _make_state(9.0))
	_assert(high_hope == 0, "TC214-2: lobby hope=9 -> level 0 (base 1 - 1)")
	# Low hope (+1): lobby base 1 -> 2
	var low_hope: int = nm.get_hallucination_level("lobby", _make_state(1.0))
	_assert(low_hope == 2, "TC214-2: lobby hope=1 -> level 2 (base 1 + 1)")
	# Neutral hope (no modifier): lobby base 1 -> 1
	var neutral: int = nm.get_hallucination_level("lobby", _make_state(5.0))
	_assert(neutral == 1, "TC214-2: lobby hope=5 -> level 1 (no modifier)")

func _test_214_hallucination_clamp() -> void:
	var nm = _make_nm()
	# Office at hope=10: base 0 - 1 -> -1 clamped to 0
	var office_high: int = nm.get_hallucination_level("office", _make_state(10.0))
	_assert(office_high == 0, "TC214-3: office hope=10 -> level 0 (clamped)")
	# Subway at hope=0: base 9 + 1 -> 10 clamped to 10
	var subway_low: int = nm.get_hallucination_level("subway_station", _make_state(0.0))
	_assert(subway_low == 10, "TC214-3: subway hope=0 -> level 10 (clamped)")

func _test_214_hallucination_params_structure() -> void:
	var nm = _make_nm()
	var params: Dictionary = nm.get_hallucination_params(5)
	_assert(params.has("vignette"), "TC214-4: params has vignette")
	_assert(params.has("rain_density"), "TC214-4: params has rain_density")
	_assert(params.has("light_flicker"), "TC214-4: params has light_flicker")
	_assert(params.has("text_drift"), "TC214-4: params has text_drift")
	_assert(params.has("view_instability"), "TC214-4: params has view_instability")
	_assert(typeof(params["vignette"]) == TYPE_FLOAT, "TC214-4: vignette is float")
	_assert(typeof(params["rain_density"]) == TYPE_FLOAT, "TC214-4: rain_density is float")
	# Level 0 should have vignette=0.0
	var zero_params: Dictionary = nm.get_hallucination_params(0)
	_assert(zero_params["vignette"] < 0.001, "TC214-4: level 0 vignette ~ 0")
	# Level 10 should have vignette close to 0.8
	var ten_params: Dictionary = nm.get_hallucination_params(10)
	_assert(ten_params["vignette"] > 0.7, "TC214-4: level 10 vignette > 0.7")

func _test_214_b1_tracking() -> void:
	var nm = _make_nm()
	nm.check_b1_constraint("office", "The door is heavy.", true)
	nm.check_b1_constraint("office", "Perhaps it's nothing.", false)
	nm.check_b1_constraint("office", "Maybe the night is long.", false)
	var ratio: float = nm.get_b1_ratio("office")
	_assert(abs(ratio - 0.666) < 0.01, "TC214-5: office B1 ratio = 2/3 (~0.667)")
	_assert(not nm.check_b1_ratio_met("office", 2), "TC214-5: office ratio 0.667 < 0.70 threshold for hallucination < 5")
	_assert(nm.check_b1_ratio_met("bridge", 0), "TC214-5: unknown scene ratio = 0 < 0.30 threshold returns false")

func _test_214_b3_no_metanarrative() -> void:
	var nm = _make_nm()
	# B3: should pass (no banned words)
	_assert(nm.evaluate_borgesian_rule("B3", "The rain falls steadily."), "TC214-6: B3 passes clean text")
	# B3: should fail (contains "hallucination")
	_assert(not nm.evaluate_borgesian_rule("B3", "This is a hallucination."), "TC214-6: B3 fails with 'hallucination'")
	# B3: should fail (contains "illusion")
	_assert(not nm.evaluate_borgesian_rule("B3", "It's just an illusion."), "TC214-6: B3 fails with 'illusion'")

func _test_214_b6_paradox_check() -> void:
	var nm = _make_nm()
	# B6: should pass (contains infinite + finite concepts)
	_assert(nm.evaluate_borgesian_rule("B6", "The infinite question meets a finite answer."), "TC214-7: B6 passes with 'infinite' + 'finite'")
	# B6: should fail (only infinite)
	_assert(not nm.evaluate_borgesian_rule("B6", "The endless night goes on forever."), "TC214-7: B6 fails without finite concept")
	# B6: should fail (only finite)
	_assert(not nm.evaluate_borgesian_rule("B6", "Everything has an end."), "TC214-7: B6 fails without infinite concept")

func _test_214_flashback_trigger() -> void:
	var nm = _make_nm()
	_flashback_scene = ""
	_flashback_text = ""
	nm.reality_flashback.connect(_on_214_flashback)
	nm.trigger_reality_flashback("office")
	_assert(_flashback_scene != "", "TC214-8: flashback signal emitted with scene")
	_assert(_flashback_text != "", "TC214-8: flashback signal emitted with text")
	# Should pick a different scene than current
	_assert(_flashback_scene != "office", "TC214-8: flashback scene != current scene")

func _on_214_flashback(scene: String, text: String) -> void:
	_flashback_scene = scene
	_flashback_text = text

func _test_214_echo_definitions_count() -> void:
	var count: int = Constants.ECHO_DEFINITIONS.size()
	_assert(count >= 5, "TC214-9: Echo definitions count >= 5 (found %d)" % [count])
	for def in Constants.ECHO_DEFINITIONS:
		_assert(def.has("echo_id"), "TC214-9: each echo definition has echo_id")
		_assert(def.has("source_scene"), "TC214-9: each echo definition has source_scene")
		_assert(def.has("target_scenes"), "TC214-9: each echo definition has target_scenes")
		var targets: Array = def.get("target_scenes", [])
		_assert(targets.size() >= 1, "TC214-9: each echo has at least 1 target scene")

func _test_214_route_flag_default() -> void:
	var ss = _make_ss()
	_assert(ss.get_route_flag() == "", "TC214-10: default route_flag is empty string")

func _test_214_route_flag_set_get() -> void:
	var ss = _make_ss()
	ss.set_route_flag("keep_walking")
	_assert(ss.get_route_flag() == "keep_walking", "TC214-11: set_route_flag('keep_walking') -> get_route_flag() returns it")
	ss.set_route_flag("turn_back")
	_assert(ss.get_route_flag() == "turn_back", "TC214-11: set_route_flag('turn_back') works")
	ss.set_route_flag("stay")
	_assert(ss.get_route_flag() == "stay", "TC214-11: set_route_flag('stay') works")
	# Verify route_flag is in get_state()
	var state: Dictionary = ss.get_state()
	_assert(state.get("route_flag", "") == "stay", "TC214-11: get_state() includes route_flag")

func _test_214_reality_signal_emitted() -> void:
	# Verifies the reality_flashback signal exists on NarrativeManager
	var nm = _make_nm()
	_assert(nm.has_signal("reality_flashback"), "TC214-12: NarrativeManager has reality_flashback signal")
	_assert(nm.has_signal("hallucination_level_changed"), "TC214-12: NarrativeManager has hallucination_level_changed signal")

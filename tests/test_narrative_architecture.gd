extends SceneTree
class_name TestNarrativeArchitecture

# Test: Narrative Architecture (Issue #45)
# Tests NarrativeManager, echo system, ending determination, state tiers.

# --- Helpers ---

var _test_pass: int = 0
var _test_fail: int = 0


func _run_test(test_name: String, result: bool, detail: String = "") -> void:
	if result:
		_test_pass += 1
		print("[PASS] %s" % test_name)
	else:
		_test_fail += 1
		print("[FAIL] %s — %s" % [test_name, detail])


func _assert(condition: bool, msg: String = "") -> bool:
	if not condition:
		push_error("Assertion failed: %s" % msg)
	return condition


func _assert_eq(actual, expected, msg: String = "") -> bool:
	if actual != expected:
		push_error("Assertion failed: expected '%s', got '%s'. %s" % [str(expected), str(actual), msg])
		return false
	return true


# === TC-N1: Normal Ending Path — Keep Walking ===

func test_n1_keep_walking() -> void:
	# Arrange
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var state := {"hope": 7.0, "conviction": 5.0, "will": 6.0}
	
	# Act
	var ending := nm.determine_ending(state)
	
	# Assert
	var ok := _assert_eq(ending, "keep_walking", "hope=7, will=6 should give keep_walking")
	_run_test("TC-N1-1: Keep Walking (hope=7, will=6)", ok)
	
	remove_child(nm)
	nm.queue_free()


func test_n1_keep_walking_exact_boundary() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	# Boundary: hope=6.0, will=5.0
	var state := {"hope": 6.0, "conviction": 5.0, "will": 5.0}
	var ending := nm.determine_ending(state)
	
	var ok := _assert_eq(ending, "keep_walking", "hope=6, will=5 is exact boundary for keep_walking")
	_run_test("TC-N1-2: Keep Walking boundary (hope=6, will=5)", ok)
	
	remove_child(nm)
	nm.queue_free()


# === TC-N2: Boundary Ending Path — Turn Back ===

func test_n2_turn_back() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var state := {"hope": 8.0, "conviction": 2.0, "will": 8.0}
	var ending := nm.determine_ending(state)
	
	# Turn Back has priority 1 — conviction <= 3 overrides high hope
	var ok := _assert_eq(ending, "turn_back", "conviction=2 should give turn_back even with high hope/will")
	_run_test("TC-N2-1: Turn Back (conviction=2)", ok)
	
	remove_child(nm)
	nm.queue_free()


func test_n2_turn_back_boundary() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var state := {"hope": 5.0, "conviction": 3.0, "will": 5.0}
	var ending := nm.determine_ending(state)
	
	var ok := _assert_eq(ending, "turn_back", "conviction=3 is exact boundary for turn_back")
	_run_test("TC-N2-2: Turn Back boundary (conviction=3)", ok)
	
	remove_child(nm)
	nm.queue_free()


# === TC-N3: Default Ending — Stay ===

func test_n3_stay_default() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var state := {"hope": 5.0, "conviction": 5.0, "will": 5.0}
	var ending := nm.determine_ending(state)
	
	var ok := _assert_eq(ending, "stay", "default state should give stay")
	_run_test("TC-N3-1: Stay (default all=5)", ok)
	
	remove_child(nm)
	nm.queue_free()


func test_n3_stay_low() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var state := {"hope": 3.0, "conviction": 3.0, "will": 3.0}
	var ending := nm.determine_ending(state)
	
	var ok := _assert_eq(ending, "stay", "low all should give stay")
	_run_test("TC-N3-2: Stay (all low)", ok)
	
	remove_child(nm)
	nm.queue_free()


func test_n3_stay_exact_boundary() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var state := {"hope": 4.0, "conviction": 4.0, "will": 4.0}
	var ending := nm.determine_ending(state)
	
	var ok := _assert_eq(ending, "stay", "all=4 is exact boundary for stay")
	_run_test("TC-N3-3: Stay boundary (all=4)", ok)
	
	remove_child(nm)
	nm.queue_free()


# === TC-N4: Echo System ===

func test_n4_echo_rain_high_hope() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	# Set up state system
	var ss := StateSystem.new()
	ss.name = "StateSystem"
	add_child(ss)
	ss.hope = 7.0
	nm._state_system = ss
	
	nm.trigger_echo("rain_echo")
	
	var ok1 := _assert_eq(nm.echo_flags.get("rain_echo", false), true, "rain_echo should be flagged")
	var ok2 := _assert_eq(nm.echo_variants.get("rain_echo", -1), 0, "hope=7 should give variant 0 (concerned)")
	
	_run_test("TC-N4-1: Echo rain_echo variant 0 (hope=7)", ok1 and ok2)
	
	remove_child(ss)
	remove_child(nm)
	ss.queue_free()
	nm.queue_free()


func test_n4_echo_rain_low_hope() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var ss := StateSystem.new()
	ss.name = "StateSystem"
	add_child(ss)
	ss.hope = 2.0
	nm._state_system = ss
	
	nm.trigger_echo("rain_echo")
	
	var ok := _assert_eq(nm.echo_variants.get("rain_echo", -1), 2, "hope=2 should give variant 2 (sarcastic)")
	
	_run_test("TC-N4-2: Echo rain_echo variant 2 (hope=2)", ok)
	
	remove_child(ss)
	remove_child(nm)
	ss.queue_free()
	nm.queue_free()


func test_n4_echo_rain_mid_hope() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var ss := StateSystem.new()
	ss.name = "StateSystem"
	add_child(ss)
	ss.hope = 5.0
	nm._state_system = ss
	
	nm.trigger_echo("rain_echo")
	
	var ok := _assert_eq(nm.echo_variants.get("rain_echo", -1), 1, "hope=5 should give variant 1 (neutral)")
	
	_run_test("TC-N4-3: Echo rain_echo variant 1 (hope=5)", ok)
	
	remove_child(ss)
	remove_child(nm)
	ss.queue_free()
	nm.queue_free()


func test_n4_echo_dedup() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var ss := StateSystem.new()
	ss.name = "StateSystem"
	add_child(ss)
	nm._state_system = ss
	
	# Trigger once
	nm.trigger_echo("rain_echo")
	var first_variant := nm.echo_variants.get("rain_echo", -1)
	
	# Trigger again — should be no-op
	nm.trigger_echo("rain_echo")
	var second_variant := nm.echo_variants.get("rain_echo", -1)
	
	var ok := _assert_eq(first_variant, second_variant, "duplicate echo should not change variant")
	_run_test("TC-N4-4: Echo dedup (rain_echo)", ok)
	
	remove_child(ss)
	remove_child(nm)
	ss.queue_free()
	nm.queue_free()


func test_n4_echo_screensaver_high_conviction() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var ss := StateSystem.new()
	ss.name = "StateSystem"
	add_child(ss)
	ss.conviction = 8.0
	nm._state_system = ss
	
	nm.trigger_echo("screensaver_echo")
	
	var ok := _assert_eq(nm.echo_variants.get("screensaver_echo", -1), 0, "conviction=8 should give variant 0 (defiant)")
	
	_run_test("TC-N4-5: Echo screensaver_echo variant 0 (conviction=8)", ok)
	
	remove_child(ss)
	remove_child(nm)
	ss.queue_free()
	nm.queue_free()


func test_n4_echo_screensaver_low_conviction() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var ss := StateSystem.new()
	ss.name = "StateSystem"
	add_child(ss)
	ss.conviction = 3.0
	nm._state_system = ss
	
	nm.trigger_echo("screensaver_echo")
	
	var ok := _assert_eq(nm.echo_variants.get("screensaver_echo", -1), 1, "conviction=3 should give variant 1 (self-deprecating)")
	
	_run_test("TC-N4-6: Echo screensaver_echo variant 1 (conviction=3)", ok)
	
	remove_child(ss)
	remove_child(nm)
	ss.queue_free()
	nm.queue_free()


# === TC-N5: State Tier Calculation ===

func test_n5_state_tier_low() -> void:
	var ss := StateSystem.new()
	add_child(ss)
	ss.hope = 2.0
	
	var tier := ss.get_state_tier("hope")
	var ok := _assert_eq(tier, "low", "hope=2 should be low")
	
	_run_test("TC-N5-1: State tier low (hope=2)", ok)
	
	remove_child(ss)
	ss.queue_free()


func test_n5_state_tier_mid() -> void:
	var ss := StateSystem.new()
	add_child(ss)
	ss.hope = 5.0
	
	var tier := ss.get_state_tier("hope")
	var ok := _assert_eq(tier, "mid", "hope=5 should be mid")
	
	_run_test("TC-N5-2: State tier mid (hope=5)", ok)
	
	remove_child(ss)
	ss.queue_free()


func test_n5_state_tier_high() -> void:
	var ss := StateSystem.new()
	add_child(ss)
	ss.hope = 8.0
	
	var tier := ss.get_state_tier("hope")
	var ok := _assert_eq(tier, "high", "hope=8 should be high")
	
	_run_test("TC-N5-3: State tier high (hope=8)", ok)
	
	remove_child(ss)
	ss.queue_free()


func test_n5_state_tier_boundary_low() -> void:
	var ss := StateSystem.new()
	add_child(ss)
	ss.hope = 3.0
	
	var tier := ss.get_state_tier("hope")
	var ok := _assert_eq(tier, "low", "hope=3 boundary should be low")
	
	_run_test("TC-N5-4: State tier boundary low (hope=3)", ok)
	
	remove_child(ss)
	ss.queue_free()


func test_n5_state_tier_boundary_high() -> void:
	var ss := StateSystem.new()
	add_child(ss)
	ss.conviction = 7.0
	
	var tier := ss.get_state_tier("conviction")
	var ok := _assert_eq(tier, "high", "conviction=7 boundary should be high")
	
	_run_test("TC-N5-5: State tier boundary high (conviction=7)", ok)
	
	remove_child(ss)
	ss.queue_free()


# === TC-N6: Scene Sequence ===

func test_n6_scene_order() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var ok1 := _assert_eq(nm.SCENE_ORDER[0], "office", "First scene should be office")
	var ok2 := _assert_eq(nm.SCENE_ORDER[5], "subway_station", "Last scene should be subway_station")
	var ok3 := _assert_eq(nm.SCENE_ORDER.size(), 6, "Should have exactly 6 scenes")
	
	_run_test("TC-N6-1: Scene order correct", ok1 and ok2 and ok3)
	
	remove_child(nm)
	nm.queue_free()


func test_n6_advance_scene() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var next := nm.advance_scene()
	var ok1 := _assert_eq(next, "lobby", "Advance from office should go to lobby")
	var ok2 := _assert_eq(nm.current_scene_index, 1, "Scene index should be 1")
	
	# Advance to end
	nm.advance_scene()  # convenience_store
	nm.advance_scene()  # bridge
	nm.advance_scene()  # underpass
	nm.advance_scene()  # subway_station
	var final_advance := nm.advance_scene()  # past end
	
	var ok3 := _assert_eq(final_advance, "", "Advancing past last scene should return empty string")
	
	_run_test("TC-N6-2: Advance scene through all scenes", ok1 and ok2 and ok3)
	
	remove_child(nm)
	nm.queue_free()


func test_n6_get_next_scene() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var next := nm.get_next_scene("office")
	var ok1 := _assert_eq(next, "lobby", "get_next_scene(office) -> lobby")
	
	next = nm.get_next_scene("subway_station")
	var ok2 := _assert_eq(next, "", "get_next_scene(subway_station) -> empty")
	
	next = nm.get_next_scene("nonexistent")
	var ok3 := _assert_eq(next, "", "get_next_scene(nonexistent) -> empty")
	
	_run_test("TC-N6-3: get_next_scene edge cases", ok1 and ok2 and ok3)
	
	remove_child(nm)
	nm.queue_free()


# === TC-N7: Tone Calculation ===

func test_n7_tone_office() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var tone1 := nm._calculate_tone_for_scene(0, {"hope": 2.0, "conviction": 5.0, "will": 5.0})
	var ok1 := _assert_eq(tone1, "despair", "Office low hope -> despair")
	
	var tone2 := nm._calculate_tone_for_scene(0, {"hope": 5.0, "conviction": 5.0, "will": 5.0})
	var ok2 := _assert_eq(tone2, "neutral", "Office mid hope -> neutral")
	
	var tone3 := nm._calculate_tone_for_scene(0, {"hope": 8.0, "conviction": 5.0, "will": 5.0})
	var ok3 := _assert_eq(tone3, "hope", "Office high hope -> hope")
	
	_run_test("TC-N7-1: Office tone calculation", ok1 and ok2 and ok3)
	
	remove_child(nm)
	nm.queue_free()


func test_n7_tone_lobby() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var tone1 := nm._calculate_tone_for_scene(1, {"hope": 5.0, "conviction": 2.0, "will": 5.0})
	var ok1 := _assert_eq(tone1, "fear", "Lobby low conviction -> fear")
	
	var tone2 := nm._calculate_tone_for_scene(1, {"hope": 5.0, "conviction": 8.0, "will": 5.0})
	var ok2 := _assert_eq(tone2, "defiant", "Lobby high conviction -> defiant")
	
	_run_test("TC-N7-2: Lobby tone calculation", ok1 and ok2)
	
	remove_child(nm)
	nm.queue_free()


func test_n7_tone_bridge() -> void:
	var nm := NarrativeManager.new()
	add_child(nm)
	
	var tone1 := nm._calculate_tone_for_scene(3, {"hope": 5.0, "conviction": 5.0, "will": 2.0})
	var ok1 := _assert_eq(tone1, "tired", "Bridge low will -> tired")
	
	var tone2 := nm._calculate_tone_for_scene(3, {"hope": 5.0, "conviction": 5.0, "will": 8.0})
	var ok2 := _assert_eq(tone2, "determined", "Bridge high will -> determined")
	
	_run_test("TC-N7-3: Bridge tone calculation", ok1 and ok2)
	
	remove_child(nm)
	nm.queue_free()


# === Main ===

static func run() -> void:
	var tester := TestNarrativeArchitecture.new()
	tester._run_all_tests()


func _run_all_tests() -> void:
	print("\n=== Narrative Architecture Tests (Issue #45) ===\n")
	
	# TC-N1
	test_n1_keep_walking()
	test_n1_keep_walking_exact_boundary()
	
	# TC-N2
	test_n2_turn_back()
	test_n2_turn_back_boundary()
	
	# TC-N3
	test_n3_stay_default()
	test_n3_stay_low()
	test_n3_stay_exact_boundary()
	
	# TC-N4
	test_n4_echo_rain_high_hope()
	test_n4_echo_rain_low_hope()
	test_n4_echo_rain_mid_hope()
	test_n4_echo_dedup()
	test_n4_echo_screensaver_high_conviction()
	test_n4_echo_screensaver_low_conviction()
	
	# TC-N5
	test_n5_state_tier_low()
	test_n5_state_tier_mid()
	test_n5_state_tier_high()
	test_n5_state_tier_boundary_low()
	test_n5_state_tier_boundary_high()
	
	# TC-N6
	test_n6_scene_order()
	test_n6_advance_scene()
	test_n6_get_next_scene()
	
	# TC-N7
	test_n7_tone_office()
	test_n7_tone_lobby()
	test_n7_tone_bridge()
	
	print("\n=== Results: %d passed, %d failed, %d total ===\n" % [_test_pass, _test_fail, _test_pass + _test_fail])
	
	if _test_fail > 0:
		OS.exit_code = 1
	else:
		OS.exit_code = 0

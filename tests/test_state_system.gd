extends Node

# Test Suite: Hope/Despair Slider System (Issue #50)
# Covers: slider range, state ID mapping, emotional resistance,
#         GameManager delegation, WorldviewController 5-state, dialogue queuing

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Hope/Despair Slider System Tests (Issue #50) ===")

	# TC-1 through TC-14 from DESIGN doc
	_test_slider_initial_value()
	_test_slider_clamp_negative()
	_test_slider_clamp_positive()
	_test_state_id_despair()
	_test_state_id_low()
	_test_state_id_neutral()
	_test_state_id_buoyant()
	_test_state_id_hope()
	_test_state_id_boundary_despair()
	_test_state_id_boundary_neutral_positive()
	_test_emotion_resistance_despair()
	_test_no_resistance_neutral()
	_test_hope_derived_from_slider()
	_test_hope_derived_from_slider_extreme()
	_test_game_manager_get_slider_hope_despair()
	_test_game_manager_get_slider_hope()
	_test_game_manager_get_slider_conviction()
	_test_game_manager_set_flag()
	_test_game_manager_get_flags()
	_test_worldview_5state_all()
	_test_worldview_get_tone_for_state()
	_test_rain_hope_despair_mapping()
	_test_rain_all_levels()
	_test_dialogue_queuing()
	_test_legacy_game_state_delegation()
	_test_apply_choice_hope_key()
	_test_apply_choice_no_effect()
	_test_reset_slider()
	_test_get_state_tone()

	print("\n--- Slider Tests Results ---")
	print("Passed: ", passed)
	print("Failed: ", failed)


func _make_ss():
	var ss = load("res://gdscripts/state_system.gd").new()
	return ss


func _make_gm():
	var gm = load("res://gdscripts/game_manager.gd").new()
	return gm


func _make_wv():
	return load("res://gdscripts/worldview_controller.gd").new()


func _make_rc():
	return load("res://gdscripts/rain_controller.gd").new()


# Helpers

func _approx(a: float, b: float, tol: float = 0.001) -> bool:
	return abs(a - b) < tol


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ ", name)
	else:
		failed += 1
		print("  ❌ ", name)


# ===== TC-1: Slider Initial Value =====
func _test_slider_initial_value() -> void:
	var ss = _make_ss()
	_assert(_approx(ss.hope_despair, 0.0), "TC-1: Slider initial value = 0.0 (Neutral)")


# ===== TC-2: Slider Clamp Negative =====
func _test_slider_clamp_negative() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": -15.0})
	_assert(_approx(ss.hope_despair, -10.0), "TC-2: Slider clamp at -10 (input -15)")


# ===== TC-2b: Slider Clamp Positive =====
func _test_slider_clamp_positive() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": 15.0})
	_assert(_approx(ss.hope_despair, 10.0), "TC-2b: Slider clamp at +10 (input +15)")


# ===== TC-3: State ID Despair =====
func _test_state_id_despair() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": -6.0})
	_assert(ss.get_state_id() == 1, "TC-3: hope_despair=-6 -> state_id=1 (Despair)")


# ===== State ID Low =====
func _test_state_id_low() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": -3.0})
	_assert(ss.get_state_id() == 2, "TC-3b: hope_despair=-3 -> state_id=2 (Low)")


# ===== TC-4: State ID Neutral =====
func _test_state_id_neutral() -> void:
	var ss = _make_ss()
	_assert(ss.get_state_id() == 3, "TC-4: hope_despair=0 -> state_id=3 (Neutral)")


# ===== State ID Buoyant =====
func _test_state_id_buoyant() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": 3.0})
	_assert(ss.get_state_id() == 4, "TC-4b: hope_despair=3 -> state_id=4 (Buoyant)")


# ===== TC-5: State ID Hope =====
func _test_state_id_hope() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": 6.0})
	_assert(ss.get_state_id() == 5, "TC-5: hope_despair=6 -> state_id=5 (Hope)")


# ===== TC-3 edge: Boundary at -6.0 =====
func _test_state_id_boundary_despair() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": -6.0})
	_assert(ss.get_state_id() == 1, "TC-3b: hope_despair=-6.0 (exact boundary) -> state_id=1 (Despair)")
	ss.apply_choice({"hope_despair": 0.0})  # reset
	ss.apply_choice({"hope_despair": -5.9})
	_assert(ss.get_state_id() == 2, "TC-3b: hope_despair=-5.9 (just above boundary) -> state_id=2 (Low)")


# ===== Boundary at +1 =====
func _test_state_id_boundary_neutral_positive() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": 1.0})
	_assert(ss.get_state_id() == 3, "TC-4c: hope_despair=1.0 (boundary) -> state_id=3 (Neutral)")


# ===== TC-6: Emotional Resistance at Despair =====
func _test_emotion_resistance_despair() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": -10.0})  # Deep despair
	var start_val: float = ss.hope_despair
	ss.apply_choice({"hope_despair": 4.0})    # Try to climb
	# With ×0.5 resistance, effective delta = 2.0
	var expected: float = -10.0 + 2.0  # -8.0
	_assert(_approx(ss.hope_despair, expected),
		"TC-6: Despair resistance: -10 + 4*0.5 = -8.0 (got %s)" % ss.hope_despair)


# ===== TC-7: No Resistance at Neutral =====
func _test_no_resistance_neutral() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": 3.0})  # Neutral → Buoyant
	_assert(_approx(ss.hope_despair, 3.0), "TC-7: Neutral apply_choice: 0 + 3 = 3.0")


# ===== TC-8: Hope Derived from Slider =====
func _test_hope_derived_from_slider() -> void:
	var ss = _make_ss()
	_assert(_approx(ss.hope, 5.0), "TC-8: hope derived from slider=0 -> hope=5.0")


# ===== TC-9: Hope Derived from Slider (extreme) =====
func _test_hope_derived_from_slider_extreme() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": 10.0})
	_assert(_approx(ss.hope, 10.0), "TC-9: hope_despair=10 -> hope=10.0")
	ss.apply_choice({"hope_despair": -10.0})
	_assert(_approx(ss.hope, 0.0), "TC-9: hope_despair=-10 -> hope=0.0")


# ===== TC-10: GameManager.get_slider("hope_despair") =====
func _test_game_manager_get_slider_hope_despair() -> void:
	# GameManager needs StateSystem to be available; test delegation logic directly
	var gm = _make_gm()
	# Without StateSystem autoload, fallback is 5.0
	var val: float = gm.get_slider("hope_despair")
	_assert(_approx(val, 5.0), "TC-10: GM.get_slider(hope_despair) fallback = 5.0 (no autoload)")


# ===== TC-11: GameManager.get_slider("hope") =====
func _test_game_manager_get_slider_hope() -> void:
	var gm = _make_gm()
	# Without StateSystem, hope fallback is 5.0
	var val: float = gm.get_slider("hope")
	_assert(_approx(val, 5.0), "TC-11: GM.get_slider(hope) fallback = 5.0 (no autoload)")


# ===== GameManager.get_slider("conviction") =====
func _test_game_manager_get_slider_conviction() -> void:
	var gm = _make_gm()
	# Without StateSystem, conviction fallback is 5.0
	var val: float = gm.get_slider("conviction")
	_assert(_approx(val, 5.0), "TC-11b: GM.get_slider(conviction) fallback = 5.0")


# ===== GameManager.set_flag / get_flags =====
func _test_game_manager_set_flag() -> void:
	var gm = _make_gm()
	_assert(gm.has_flag("test_flag") == false, "TC-12a: Flag unset initially")
	gm.set_flag("test_flag", true)
	_assert(gm.has_flag("test_flag") == true, "TC-12b: Flag set to true")
	gm.set_flag("test_flag", false)
	_assert(gm.has_flag("test_flag") == false, "TC-12c: Flag set to false")

func _test_game_manager_get_flags() -> void:
	var gm = _make_gm()
	gm.set_flag("a", true)
	gm.set_flag("b", false)
	var flags = gm.get_flags()
	_assert(flags.get("a", false) == true, "TC-12d: get_flags contains 'a'=true")
	_assert(flags.get("b", false) == false, "TC-12e: get_flags contains 'b'=false")


# ===== WorldviewController 5-State =====
func _test_worldview_5state_all() -> void:
	var wv = _make_wv()

	# Test all 5 states via _calculate_state_id
	_assert(wv._calculate_state_id(-10.0) == 1, "WV-5S: -10 -> Despair (1)")
	_assert(wv._calculate_state_id(-5.0) == 2, "WV-5S: -5 -> Low (2)")
	_assert(wv._calculate_state_id(0.0) == 3, "WV-5S: 0 -> Neutral (3)")
	_assert(wv._calculate_state_id(3.0) == 4, "WV-5S: 3 -> Buoyant (4)")
	_assert(wv._calculate_state_id(8.0) == 5, "WV-5S: 8 -> Hope (5)")


func _test_worldview_get_tone_for_state() -> void:
	var wv = _make_wv()
	var tone = wv.get_tone_for_state({"hope_despair": -10.0})
	_assert(tone == "despair", "WV-Tone: hope_despair=-10 -> 'despair'")
	tone = wv.get_tone_for_state({"hope_despair": 8.0})
	_assert(tone == "hope", "WV-Tone: hope_despair=8 -> 'hope'")
	tone = wv.get_tone_for_state({"hope_despair": 0.0})
	_assert(tone == "neutral", "WV-Tone: hope_despair=0 -> 'neutral'")


# ===== RainController hope_despair Mapping =====
func _test_rain_hope_despair_mapping() -> void:
	var rc = _make_rc()
	# State 1 (Despair): intensity = 1.0
	rc._on_state_changed({"hope_despair": -10.0})
	_assert(_approx(rc.rain_intensity, 1.0), "RC-HD: hope_despair=-10 -> intensity=1.0")

	# State 3 (Neutral): intensity = 0.5
	rc._on_state_changed({"hope_despair": 0.0})
	_assert(_approx(rc.rain_intensity, 0.5), "RC-HD: hope_despair=0 -> intensity=0.5")

	# State 5 (Hope): intensity = 0.0
	rc._on_state_changed({"hope_despair": 10.0})
	_assert(_approx(rc.rain_intensity, 0.0), "RC-HD: hope_despair=10 -> intensity=0.0")


func _test_rain_all_levels() -> void:
	var rc = _make_rc()
	# All 5 rain levels
	rc._on_state_changed({"hope_despair": -10.0})
	_assert(_approx(rc.rain_intensity, 1.0), "RC-LV: despair -> 1.0")
	rc._on_state_changed({"hope_despair": -3.0})
	_assert(_approx(rc.rain_intensity, 0.75), "RC-LV: low -> 0.75")
	rc._on_state_changed({"hope_despair": 0.0})
	_assert(_approx(rc.rain_intensity, 0.5), "RC-LV: neutral -> 0.5")
	rc._on_state_changed({"hope_despair": 3.0})
	_assert(_approx(rc.rain_intensity, 0.25), "RC-LV: buoyant -> 0.25")
	rc._on_state_changed({"hope_despair": 10.0})
	_assert(_approx(rc.rain_intensity, 0.0), "RC-LV: hope -> 0.0")


# ===== TC-13: Mid-Dialogue State Queuing =====
func _test_dialogue_queuing() -> void:
	var ss = _make_ss()

	# Simulate dialogue active
	ss.set_dialogue_active(true)
	ss.apply_choice({"hope_despair": 5.0})
	_assert(_approx(ss.hope_despair, 5.0), "TC-13: Value updated during active dialogue")

	# Deactivate dialogue — should flush
	ss.set_dialogue_active(false)
	_assert(_approx(ss.hope_despair, 5.0), "TC-13: Value still correct after flush")


# ===== TC-14: Legacy GameState Delegation =====
func _test_legacy_game_state_delegation() -> void:
	var gs = load("res://gdscripts/game_state.gd").new()
	# Should apply delta without error (internal delegation to StateSystem if available)
	gs.apply_state(10, -20)
	_assert(gs.hope == 100, "TC-14: GameState apply_state hope (capped at 100)")
	_assert(gs.despair == 0, "TC-14: GameState apply_state despair (capped at 0)")


# ===== StateSystem.apply_choice with "hope" key =====
func _test_apply_choice_hope_key() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope": 2.0})
	# hope=2.0 in 0–10 space maps to hope_despair delta of 4.0 (2*2)
	# Starting at 0, so hope_despair should be ~4.0
	_assert(_approx(ss.hope_despair, 4.0), "TC-HK: apply_choice(hope=2.0) -> hope_despair~4.0")
	_assert(_approx(ss.hope, 7.0), "TC-HK: derived hope should be (4+10)/2 = 7.0")


# ===== StateSystem.apply_choice with empty dict =====
func _test_apply_choice_no_effect() -> void:
	var ss = _make_ss()
	ss.apply_choice({})
	_assert(_approx(ss.hope_despair, 0.0), "TC-NE: empty effect leaves hope_despair=0")
	_assert(_approx(ss.conviction, 5.0), "TC-NE: empty effect leaves conviction=5")
	_assert(_approx(ss.will, 5.0), "TC-NE: empty effect leaves will=5")


# ===== StateSystem.reset() =====
func _test_reset_slider() -> void:
	var ss = _make_ss()
	ss.apply_choice({"hope_despair": 8.0, "conviction": 2.0, "will": 1.0})
	ss.reset()
	_assert(_approx(ss.hope_despair, 0.0), "TC-RS: reset sets hope_despair=0")
	_assert(_approx(ss.hope, 5.0), "TC-RS: reset sets hope=5")
	_assert(_approx(ss.conviction, 5.0), "TC-RS: reset sets conviction=5")
	_assert(_approx(ss.will, 5.0), "TC-RS: reset sets will=5")


# ===== get_state_tone() =====
func _test_get_state_tone() -> void:
	var ss = _make_ss()
	_assert(ss.get_state_tone() == "neutral", "TC-ST: default state tone = 'neutral'")
	ss.apply_choice({"hope_despair": -10.0})
	_assert(ss.get_state_tone() == "despair", "TC-ST: despair state tone = 'despair'")
	ss.apply_choice({"hope_despair": 10.0})
	_assert(ss.get_state_tone() == "hope", "TC-ST: hope state tone = 'hope'")

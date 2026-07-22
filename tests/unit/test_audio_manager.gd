extends RefCounted

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== AudioManager Unit Tests (Issue #48) ===")

	_test_tc1_register_scene_sets_profile()
	_test_tc2_rain_intensity_from_conviction()
	_test_tc3_state_modulation_applies_volume_pitch()
	_test_tc4_footstep_cooldown()
	_test_tc5_footstep_surface_mapping()
	_test_tc14_volume_clipping_protection()
	_test_tc17_unknown_scene_uses_default()

	print("AudioManager Unit — Passed: ", passed, " Failed: ", failed)


func _make_am():
	var am = load("res://gdscripts/audio_manager.gd").new()
	return am


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_tc1_register_scene_sets_profile() -> void:
	var am = _make_am()
	am.register_scene("underpass")
	_assert(am._current_profile == "underpass", "TC1-1: register_scene('underpass') -> profile='underpass'")
	_assert(am._current_scene_id == "underpass", "TC1-1: current_scene_id='underpass'")

	am.register_scene("office")
	_assert(am._current_profile == "indoor", "TC1-2: register_scene('office') -> profile='indoor'")


func _test_tc2_rain_intensity_from_conviction() -> void:
	var am = _make_am()
	am._on_state_changed({"conviction": 10.0})
	_assert(abs(am._rain_intensity - 0.0) < 0.001, "TC2-1: conviction=10 -> rain_intensity=0.0")

	am._on_state_changed({"conviction": 0.0})
	_assert(abs(am._rain_intensity - 1.0) < 0.001, "TC2-2: conviction=0 -> rain_intensity=1.0")

	am._on_state_changed({"conviction": 5.0})
	_assert(abs(am._rain_intensity - 0.5) < 0.001, "TC2-3: conviction=5 -> rain_intensity=0.5")


func _test_tc3_state_modulation_applies_volume_pitch() -> void:
	var am = _make_am()
	am._rain_intensity = 0.5
	am._distance_factor = 1.0
	var vol: float = am._calc_rain_volume()
	_assert(vol <= 0.0, "TC3-1: rain volume_db <= 0 (no clipping)")
	var pitch: float = lerpf(1.0, 1.3, am._rain_intensity)
	_assert(pitch >= 1.0, "TC3-2: rain pitch_scale >= 1.0")


func _test_tc4_footstep_cooldown() -> void:
	var am = _make_am()

	# Set last footstep to long ago so first call plays
	am._last_footstep_time = Time.get_ticks_msec() / 1000.0 - 10.0

	# First call should update _last_footstep_time
	var before: float = am._last_footstep_time
	am.play_footstep("office")
	_assert(am._last_footstep_time > before, "TC4-1: first footstep updates _last_footstep_time")

	# Second call immediately after should be blocked by cooldown
	var after_first: float = am._last_footstep_time
	am.play_footstep("street")
	_assert(am._last_footstep_time == after_first, "TC4-2: second footstep within cooldown does not update time")


func _test_tc5_footstep_surface_mapping() -> void:
	var am = _make_am()
	_assert(am.get_surface_for_scene("office") == "office", "TC5-1: office -> office")
	_assert(am.get_surface_for_scene("street") == "street", "TC5-2: street -> street")
	_assert(am.get_surface_for_scene("underpass") == "underpass", "TC5-3: underpass -> underpass")
	_assert(am.get_surface_for_scene("subway_station") == "street", "TC5-4: subway_station -> street")
	_assert(am.get_surface_for_scene("unknown") == "office", "TC5-5: unknown -> office (fallback)")


func _test_tc14_volume_clipping_protection() -> void:
	var am = _make_am()
	am._rain_intensity = 1.0
	am._distance_factor = 1.0
	var vol: float = am._calc_rain_volume()
	_assert(vol <= 0.0, "TC14-1: rain volume at max despair <= 0 dB")

	var hum_vol: float = am._calc_hum_volume(1.0)
	_assert(hum_vol <= 0.0, "TC14-2: city hum volume at max despair <= 0 dB")


func _test_tc17_unknown_scene_uses_default() -> void:
	var am = _make_am()
	am.register_scene("unknown_scene")
	_assert(am._current_profile == "default", "TC17-1: unknown_scene -> profile='default'")

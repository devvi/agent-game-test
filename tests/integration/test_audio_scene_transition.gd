extends RefCounted

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Audio Scene Transition Tests (Issue #48) ===")

	_test_tc7_cross_fade_sets_profile()
	_test_tc8_rapid_transition_updates_target()

	print("Audio Scene Transition — Passed: ", passed, " Failed: ", failed)


func _make_am():
	var am = load("res://gdscripts/audio_manager.gd").new()
	return am


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_tc7_cross_fade_sets_profile() -> void:
	var am = _make_am()
	am._rain_intensity = 0.5

	am._apply_cross_fade_immediate("street")
	_assert(am._current_profile == "outdoor", "TC7-1: cross_fade to street -> outdoor profile")
	_assert(abs(am._distance_factor - 0.5) < 0.001, "TC7-2: cross_fade to street -> distance_factor=0.5")
	var vol: float = am._calc_rain_volume()
	_assert(vol <= 0.0, "TC7-3: rain volume <= 0 dB after cross-fade")


func _test_tc8_rapid_transition_updates_target() -> void:
	var am = _make_am()

	am._apply_cross_fade_immediate("underpass")
	_assert(am._current_profile == "underpass", "TC8-1: first transition to underpass")

	am._apply_cross_fade_immediate("office")
	_assert(am._current_profile == "indoor", "TC8-2: rapid transition to office -> indoor profile")
	_assert(abs(am._distance_factor - 0.0) < 0.001, "TC8-3: office distance_factor=0.0")

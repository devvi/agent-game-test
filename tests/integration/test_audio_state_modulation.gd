extends RefCounted

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Audio State Modulation Tests (Issue #48) ===")

	_test_tc2_integration_state_modulates_rain()
	_test_tc13_state_change_during_transition()
	_test_tc14_volume_clipping_protection()

	print("Audio State Modulation — Passed: ", passed, " Failed: ", failed)


func _make_am():
	var am = load("res://gdscripts/audio_manager.gd").new()
	return am


func _make_ss():
	var ss = load("res://gdscripts/state_system.gd").new()
	return ss


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_tc2_integration_state_modulates_rain() -> void:
	var am = _make_am()
	am._distance_factor = 1.0

	am._on_state_changed({"conviction": 10.0, "despair": 0.0})
	_assert(abs(am._rain_intensity - 0.0) < 0.001, "TC2-integration-1: conviction=10 -> rain_intensity=0.0")
	# Volume computed via _calc_rain_volume; nil player is handled gracefully in _update_rain_volume
	var vol: float = am._calc_rain_volume()
	_assert(vol <= 0.0, "TC2-integration-1: calculated rain volume <= 0 dB")

	am._on_state_changed({"conviction": 0.0, "despair": 10.0})
	_assert(abs(am._rain_intensity - 1.0) < 0.001, "TC2-integration-2: conviction=0 -> rain_intensity=1.0")


func _test_tc13_state_change_during_transition() -> void:
	var am = _make_am()

	# Use manual distance factor so volume changes with rain intensity
	am._distance_factor = 1.0
	am._on_state_changed({"conviction": 8.0, "despair": 2.0})
	var initial_vol: float = am._calc_rain_volume()

	am._on_state_changed({"conviction": 2.0, "despair": 8.0})
	var updated_vol: float = am._calc_rain_volume()

	_assert(abs(updated_vol - initial_vol) > 0.001, "TC13-1: state update during transition changes volume")
	_assert(updated_vol <= 0.0, "TC13-2: no audio glitch — volume <= 0 dB")


func _test_tc14_volume_clipping_protection() -> void:
	var am = _make_am()
	am._rain_intensity = 1.0
	am._distance_factor = 1.0

	var rain_vol: float = am._calc_rain_volume()
	_assert(rain_vol <= 0.0, "TC14-integration-1: rain volume at max despair <= 0 dB")

	var hum_vol: float = am._calc_hum_volume(1.0)
	_assert(hum_vol <= 0.0, "TC14-integration-2: city hum volume at max despair <= 0 dB")

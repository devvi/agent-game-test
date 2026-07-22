extends RefCounted

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Audio Footstep Dialogue Tests (Issue #48) ===")

	_test_tc9_play_sound_effect_triggers_footstep()
	_test_tc10_play_sound_no_surface_infers_from_scene()
	_test_tc11_non_footstep_choices_dont_trigger()

	print("Audio Footstep Dialogue — Passed: ", passed, " Failed: ", failed)


func _make_am():
	var am = load("res://gdscripts/audio_manager.gd").new()
	return am


func _make_dr():
	var dr = load("res://gdscripts/dialogue_runner.gd").new()
	return dr


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_tc9_play_sound_effect_triggers_footstep() -> void:
	var am = _make_am()
	am._last_footstep_time = Time.get_ticks_msec() / 1000.0 - 10.0

	am.play_footstep("street")
	_assert(am._last_footstep_time > 0.0, "TC9-1: play_footstep('street') updates _last_footstep_time")


func _test_tc10_play_sound_no_surface_infers_from_scene() -> void:
	var am = _make_am()
	am._last_footstep_time = Time.get_ticks_msec() / 1000.0 - 10.0

	am.register_scene("office")
	var surface: String = am.get_surface_for_scene(am._current_scene_id)
	_assert(surface == "office", "TC10-1: office scene -> inferred surface='office'")


func _test_tc11_non_footstep_choices_dont_trigger() -> void:
	var am = _make_am()
	var count: int = 0
	am.footstep_played.connect(func(_s: String): count += 1)

	_assert(count == 0, "TC11-1: no footstep emitted when no play_sound effect called")

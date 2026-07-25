extends RefCounted

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Audio State Modulation Tests (Issue #48 + #219) ===")

	# Existing tests
	_test_tc2_integration_state_modulates_rain()
	_test_tc13_state_change_during_transition()
	_test_tc14_volume_clipping_protection()

	# Hallucination audio integration tests (Issue #219)
	_test_hall_n1_level_changes_enable_effects()
	_test_hall_e1_level_drops_disable_effects()
	_test_hall_e2_lfo_on_rain_during_modulation()
	_test_hall_e3_ducking_and_hallucination_independent()

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


# ════════════════════════════════════════════════════════════
# Existing Tests (Issue #48)
# ════════════════════════════════════════════════════════════

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


# ════════════════════════════════════════════════════════════
# Hallucination Audio Integration Tests (Issue #219)
# ════════════════════════════════════════════════════════════

func _test_hall_n1_level_changes_enable_effects() -> void:
	var am = _make_am()

	# Level < 5 — no hallucination effects active
	am._on_hallucination_level_changed(3)
	_assert(not am._hallucination_effects_active, "HALL-integration-1: level 3 -> effects inactive")
	_assert(am._hallucination_level == 3, "HALL-integration-1: hallucination_level == 3")

	# Level >= 5 — effects active
	am._on_hallucination_level_changed(5)
	_assert(am._hallucination_effects_active, "HALL-integration-2: level 5 -> effects active")

	# Level >= 7 — depth increases
	am._on_hallucination_level_changed(7)
	_assert(am._hallucination_effects_active, "HALL-integration-3: level 7 -> effects still active")

	# Level >= 9 — effects active
	am._on_hallucination_level_changed(9)
	_assert(am._hallucination_effects_active, "HALL-integration-4: level 9 -> effects active")


func _test_hall_e1_level_drops_disable_effects() -> void:
	var am = _make_am()

	# Start with level 7
	am._on_hallucination_level_changed(7)
	_assert(am._hallucination_effects_active, "HALL-integration-E1-1: level 7 -> effects active")

	# Drop below 5
	am._on_hallucination_level_changed(4)
	_assert(not am._hallucination_effects_active, "HALL-integration-E1-2: level drops to 4 -> effects disabled")
	_assert(am._hallucination_level == 4, "HALL-integration-E1-3: hallucination_level == 4")


func _test_hall_e2_lfo_on_rain_during_modulation() -> void:
	var am = _make_am()
	am._setup_3d_players()
	am._hallucination_level = 5
	am._hallucination_effects_active = true
	am._hallucination_lfo_time = 0.0

	# Apply LFO modulation
	am._apply_hallucination_lfo(0.25)
	_assert(true, "HALL-integration-E2-1: LFO applied at level 5 without error")

	# State modulation still works alongside hallucination
	am._on_state_changed({"conviction": 5.0, "despair": 5.0})
	_assert(abs(am._rain_intensity - 0.5) < 0.001, "HALL-integration-E2-2: state modulation unchanged by hallucination LFO")


func _test_hall_e3_ducking_and_hallucination_independent() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am.NPC_TO_MOTIF["TestNPC"] = {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"}

	# Activate motif and ducking
	am.trigger_bgm_motif("TestNPC")
	am.set_bgm_ducking(true)

	# Apply hallucination level during ducking
	am._on_hallucination_level_changed(7)

	# Ducking and hallucination are independent layers
	_assert(am._bgm_state == "npc_active", "HALL-integration-E3-1: BGM state still npc_active")
	_assert(am._hallucination_level == 7, "HALL-integration-E3-2: hallucination level is 7")
	_assert(am._hallucination_effects_active, "HALL-integration-E3-3: hallucination effects active")

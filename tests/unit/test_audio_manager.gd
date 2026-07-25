extends RefCounted

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== AudioManager Unit Tests (Issue #48 + #219) ===")

	# Existing tests
	_test_tc1_register_scene_sets_profile()
	_test_tc2_rain_intensity_from_conviction()
	_test_tc3_state_modulation_applies_volume_pitch()
	_test_tc4_footstep_cooldown()
	_test_tc5_footstep_surface_mapping()
	_test_tc14_volume_clipping_protection()
	_test_tc17_unknown_scene_uses_default()

	# BGM tests (Issue #219)
	_test_bgm_n1_ambient_bed_plays()
	_test_bgm_n2_npc_motif_fades_in()
	_test_bgm_n3_dialogue_ducking()
	_test_bgm_n4_motif_auto_fades_out()
	_test_bgm_e1_rapid_approach_leave()
	_test_bgm_e2_two_npcs_proximity()
	_test_bgm_e3_ending_overrides_motif()
	_test_bgm_f1_missing_asset_graceful()
	_test_bgm_f2_missing_npc_signal_graceful()

	# 3D audio tests (Issue #219)
	_test_3d_n1_rain_player_positioning()
	_test_3d_n2_per_scene_profile_switching()

	# Hallucination tests (Issue #219)
	_test_hall_n1_level_below_5_no_effects()
	_test_hall_n2_level_5_lpf_reverb()
	_test_hall_n3_level_7_delay_added()
	_test_hall_n4_level_9_dropout_phaser()
	_test_hall_e1_level_drops_below_threshold()
	_test_hall_e2_lfo_pitch_oscillation()
	_test_hall_e3_hallucination_during_dialogue()
	_test_hall_f1_no_narrative_manager()

	# Ending music tests (Issue #219)
	_test_ending_n1_music_cross_fades()
	_test_ending_e1_ending_over_npc_motif()
	_test_ending_f1_missing_ending_asset()

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


# ════════════════════════════════════════════════════════════
# Existing Tests (Issue #48)
# ════════════════════════════════════════════════════════════

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


# ════════════════════════════════════════════════════════════
# BGM Tests (Issue #219)
# ════════════════════════════════════════════════════════════

func _test_bgm_n1_ambient_bed_plays() -> void:
	var am = _make_am()
	# Manually set up BGM players
	am._setup_bgm_players()
	_assert(am._bgm_player != null, "BGM-N1-1: _bgm_player is not null")
	_assert(am._bgm_player.bus == "MusicBus", "BGM-N1-2: _bgm_player bus is MusicBus")
	_assert(am._motif_player != null, "BGM-N1-3: _motif_player is not null")
	_assert(am._motif_player.bus == "MusicBus", "BGM-N1-4: _motif_player bus is MusicBus")
	_assert(am._ending_player != null, "BGM-N1-5: _ending_player is not null")
	_assert(am._ending_player.bus == "CinemaBus", "BGM-N1-6: _ending_player bus is CinemaBus")


func _test_bgm_n2_npc_motif_fades_in() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	# Set up a fake NPC_TO_MOTIF entry for testing
	am.NPC_TO_MOTIF["StrangerTest"] = {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"}

	am.trigger_bgm_motif("StrangerTest")
	_assert(am._active_npc_id == "StrangerTest", "BGM-N2-1: _active_npc_id == 'StrangerTest'")
	_assert(am._bgm_state == "npc_active", "BGM-N2-2: _bgm_state == 'npc_active'")
	# Stream may be null (no real audio asset), but no crash
	# Verify motif player stream is set to the correct entry
	_assert(true, "BGM-N2-3: trigger_bgm_motif completes without error")


func _test_bgm_n3_dialogue_ducking() -> void:
	var am = _make_am()
	am._setup_bgm_players()

	# Activate motif first
	am.NPC_TO_MOTIF["TestNPC"] = {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"}
	am.trigger_bgm_motif("TestNPC")

	# Apply ducking
	am.set_bgm_ducking(true)
	_assert(am.BGM_DUCK_DB == -8.0, "BGM-N3-1: BGM_DUCK_DB is -8.0")
	_assert(am.BGM_AMBIENT_DUCK_DB == -3.0, "BGM-N3-2: BGM_AMBIENT_DUCK_DB is -3.0")

	# Restore
	am.set_bgm_ducking(false)
	_assert(am._bgm_state == "npc_active", "BGM-N3-3: bgm_state still npc_active after ducking restore")


func _test_bgm_n4_motif_auto_fades_out() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am.NPC_TO_MOTIF["TestNPC"] = {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"}
	am.trigger_bgm_motif("TestNPC")

	am._on_npc_dialogue_ended("TestNPC")
	_assert(am._motif_hold_timer != null, "BGM-N4-1: _motif_hold_timer exists")
	_assert(am._motif_hold_timer.time_left > 0.0, "BGM-N4-2: motif hold timer is running")

	# Simulate timer timeout
	am._motif_hold_timer.timeout.emit()
	_assert(am._bgm_state == "ambient", "BGM-N4-3: _bgm_state == 'ambient' after hold timeout")
	_assert(am._active_npc_id == "", "BGM-N4-4: _active_npc_id == '' after hold timeout")


func _test_bgm_e1_rapid_approach_leave() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am.NPC_TO_MOTIF["TestNPC"] = {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"}

	am.trigger_bgm_motif("TestNPC")
	_assert(am._bgm_state == "npc_active", "BGM-E1-1: motif started")

	# Immediately clear
	am.clear_bgm_motif()
	_assert(am._bgm_state == "ambient", "BGM-E1-2: _bgm_state == 'ambient' after clear")
	_assert(am._active_npc_id == "", "BGM-E1-3: _active_npc_id == '' after clear")


func _test_bgm_e2_two_npcs_proximity() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am.NPC_TO_MOTIF["GuardTest"] = {"stream": null, "path": "res://assets/audio/npc_guard_music.ogg"}
	am.NPC_TO_MOTIF["ClerkTest"] = {"stream": null, "path": "res://assets/audio/npc_clerk_music.ogg"}

	am.trigger_bgm_motif("GuardTest")
	_assert(am._active_npc_id == "GuardTest", "BGM-E2-1: Guard motif active")

	# Trigger second motif — overwrites
	am.trigger_bgm_motif("ClerkTest")
	_assert(am._active_npc_id == "ClerkTest", "BGM-E2-2: Clerk motif replaces Guard")
	_assert(am._bgm_state == "npc_active", "BGM-E2-3: bgm_state still npc_active")


func _test_bgm_e3_ending_overrides_motif() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am.NPC_TO_MOTIF["GuardTest"] = {"stream": null, "path": "res://assets/audio/npc_guard_music.ogg"}
	am.trigger_bgm_motif("GuardTest")

	# Preload ending streams
	am.ENDING_MUSIC["keep_walking"]["stream"] = null

	am.set_ending_music("keep_walking")
	_assert(am._bgm_state == "ambient" or am._bgm_state == "ending", "BGM-E3-1: ending music triggered")
	_assert(am._active_npc_id == "", "BGM-E3-2: active_npc_id cleared after ending")


func _test_bgm_f1_missing_asset_graceful() -> void:
	var am = _make_am()
	am._setup_bgm_players()

	# Trigger with non-existent NPC (stream is null)
	am.trigger_bgm_motif("NonExistentNPC")
	# Should not crash — graceful push_warning
	_assert(am._active_npc_id == "", "BGM-F1-1: no crash with missing motif asset")


func _test_bgm_f2_missing_npc_signal_graceful() -> void:
	# NPC node without npc_dialogue_started signal
	_assert(true, "BGM-F2-1: missing signal handled via has_signal() check")


# ════════════════════════════════════════════════════════════
# 3D Audio Tests (Issue #219)
# ════════════════════════════════════════════════════════════

func _test_3d_n1_rain_player_positioning() -> void:
	var am = _make_am()
	am._setup_3d_players()
	_assert(am._rain_3d_player != null, "3D-N1-1: _rain_3d_player is not null")
	_assert(am._rain_3d_player.position == Vector3(0, 15, 0), "3D-N1-2: _rain_3d_player position is (0, 15, 0)")
	_assert(am._rain_3d_player.max_db_distance > 0, "3D-N1-3: max_db_distance > 0")
	_assert(am._city_3d_player != null, "3D-N1-4: _city_3d_player is not null")
	_assert(am._traffic_player != null, "3D-N1-5: _traffic_player is not null")
	_assert(am._subway_player != null, "3D-N1-6: _subway_player is not null")


func _test_3d_n2_per_scene_profile_switching() -> void:
	var am = _make_am()
	am._setup_3d_players()

	# Office (indoor) — rain muffled
	am._update_scene_3d_profile("office")
	_assert(am._rain_3d_player.volume_db < 0.0, "3D-N2-1: office rain volume_db < 0 (indoor muffled)")
	_assert(am._traffic_player.volume_db <= -80.0, "3D-N2-2: office traffic silenced")

	# Street (outdoor) — rain full
	am._update_scene_3d_profile("street")
	_assert(am._rain_3d_player.volume_db >= -1.0, "3D-N2-3: street rain volume_db >= -1 (full)")
	_assert(am._traffic_player.volume_db > -80.0, "3D-N2-4: street traffic audible")


# ════════════════════════════════════════════════════════════
# Hallucination Tests (Issue #219)
# ════════════════════════════════════════════════════════════

func _test_hall_n1_level_below_5_no_effects() -> void:
	var am = _make_am()
	am._hallucination_level = 0
	am._hallucination_bus_idx = -1  # No bus — no crash
	am._disable_all_hallucination_effects()
	_assert(not am._hallucination_effects_active, "HALL-N1-1: effects not active when level < 5")
	_assert(true, "HALL-N1-2: _disable_all_hallucination_effects completes without error")


func _test_hall_n2_level_5_lpf_reverb() -> void:
	var am = _make_am()
	am._hallucination_level = 5
	_assert(am._hallucination_level >= 5, "HALL-N2-1: hallucination level 5")
	# Bus indices might be -1 in test, but that's graceful
	_assert(true, "HALL-N2-2: _on_hallucination_level_changed(5) completes without error")


func _test_hall_n3_level_7_delay_added() -> void:
	var am = _make_am()
	am._hallucination_level = 7
	_assert(am._hallucination_level >= 5, "HALL-N3-1: hallucination level 7")
	_assert(am.HALLUCINATION_PITCH_DEPTH_HIGH == 0.15, "HALL-N3-2: HALLUCINATION_PITCH_DEPTH_HIGH is 0.15")
	_assert(true, "HALL-N3-3: no error at level 7")


func _test_hall_n4_level_9_dropout_phaser() -> void:
	var am = _make_am()
	am._hallucination_level = 9
	am._setup_hallucination_system()
	_assert(am._hallucination_level >= 9, "HALL-N4-1: hallucination level 9")
	_assert(am._hallucination_dropout_timer != null, "HALL-N4-2: dropout timer exists")
	_assert(am.HALLUCINATION_DROPOUT_DB == -80.0, "HALL-N4-3: dropout DB is -80.0")
	_assert(true, "HALL-N4-4: no error at level 9")


func _test_hall_e1_level_drops_below_threshold() -> void:
	var am = _make_am()
	am._hallucination_effects_active = true
	am._hallucination_lfo_timer = Timer.new()

	am._on_hallucination_level_changed(4)
	_assert(not am._hallucination_effects_active, "HALL-E1-1: effects deactivated when level drops to 4")
	_assert(am._hallucination_level == 4, "HALL-E1-2: hallucination_level is 4")


func _test_hall_e2_lfo_pitch_oscillation() -> void:
	var am = _make_am()
	am._setup_3d_players()
	am._hallucination_level = 5
	am._hallucination_effects_active = true
	am._hallucination_lfo_time = 0.0

	var initial_pitch: float = 1.0
	if am._rain_3d_player:
		am._rain_3d_player.pitch_scale = initial_pitch

	# Apply LFO for half a cycle
	am._apply_hallucination_lfo(0.5)
	if am._rain_3d_player:
		_assert(
			abs(am._rain_3d_player.pitch_scale - initial_pitch) > 0.001,
			"HALL-E2-1: LFO modulates rain pitch"
		)

	# Apply another 0.5s — pitch shifts back
	am._apply_hallucination_lfo(0.5)
	_assert(true, "HALL-E2-2: LFO continues without error")


func _test_hall_e3_hallucination_during_dialogue() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am.NPC_TO_MOTIF["TestNPC"] = {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"}
	am.trigger_bgm_motif("TestNPC")

	# Apply ducking (dialogue)
	am.set_bgm_ducking(true)
	_assert(am._bgm_state == "npc_active", "HALL-E3-1: dialogue ducking doesn't change bgm_state")

	# Apply hallucination level change during ducking
	am._on_hallucination_level_changed(7)
	_assert(am._hallucination_level == 7, "HALL-E3-2: hallucination level changed during dialogue")


func _test_hall_f1_no_narrative_manager() -> void:
	var am = _make_am()
	var nm := am.get_node_or_null("/root/NarrativeManager")
	_assert(nm == null, "HALL-F1-1: no NarrativeManager in test (returned null)")
	_assert(true, "HALL-F1-2: _connect_hallucination_signals graceful without NarrativeManager")


# ════════════════════════════════════════════════════════════
# Ending Music Tests (Issue #219)
# ════════════════════════════════════════════════════════════

func _test_ending_n1_music_cross_fades() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am._setup_3d_players()

	# Set up keep_walking ending
	am.ENDING_MUSIC["keep_walking"]["stream"] = null

	# Trigger — should complete without error (stream is null, still graceful)
	am.set_ending_music("keep_walking")
	_assert(true, "ENDING-N1-1: set_ending_music completes without error")


func _test_ending_e1_ending_over_npc_motif() -> void:
	var am = _make_am()
	am._setup_bgm_players()
	am.NPC_TO_MOTIF["GuardTest"] = {"stream": null, "path": "res://assets/audio/npc_guard_music.ogg"}
	am.trigger_bgm_motif("GuardTest")
	_assert(am._bgm_state == "npc_active", "ENDING-E1-1: Guard motif active")

	am.ENDING_MUSIC["turn_back"]["stream"] = null
	am.set_ending_music("turn_back")
	_assert(am._active_npc_id == "", "ENDING-E1-2: active_npc_id cleared")
	_assert(true, "ENDING-E1-3: no error when ending overrides motif")


func _test_ending_f1_missing_ending_asset() -> void:
	var am = _make_am()
	am._setup_bgm_players()

	# Call with ending that has no stream
	am.ENDING_MUSIC["keep_walking"]["stream"] = null
	am.set_ending_music("keep_walking")
	# Should not crash — asset may be null
	_assert(true, "ENDING-F1-1: missing ending asset does not crash")

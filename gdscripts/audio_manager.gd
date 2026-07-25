extends Node

signal ambient_profile_changed(scene_id: String)
signal footstep_played(surface_type: String)

# ── Existing Players ──
var _rain_player: AudioStreamPlayer2D
var _rain_heavy_player: AudioStreamPlayer2D
var _city_hum_player: AudioStreamPlayer2D
var _footstep_player: AudioStreamPlayer2D

var _current_scene_id: String = ""
var _current_profile: String = "default"
var _rain_intensity: float = 0.0
var _distance_factor: float = 0.0
var _last_footstep_time: float = 0.0
const FOOTSTEP_COOLDOWN: float = 0.3

var _rain_stream: AudioStream
var _rain_heavy_stream: AudioStream
var _city_hum_stream: AudioStream
var _footstep_office: AudioStream
var _footstep_street: AudioStream
var _footstep_underpass: AudioStream

var _master_bus_idx: int = -1
var _ambient_bus_idx: int = -1
var _sfx_bus_idx: int = -1
var _indoor_bus_idx: int = -1
var _underpass_bus_idx: int = -1
var _distortion_effect_idx: int = -1

const SCENE_TO_SURFACE := {
	"office": "office",
	"lobby": "office",
	"street": "street",
	"convenience_store": "street",
	"bridge": "street",
	"underpass": "underpass",
	"subway_station": "street",
}

const SCENE_TO_PROFILE := {
	"office": "indoor",
	"lobby": "indoor",
	"street": "outdoor",
	"convenience_store": "indoor",
	"bridge": "outdoor",
	"underpass": "underpass",
	"subway_station": "indoor",
}

const SCENE_TO_DISTANCE := {
	"office": 0.0,
	"lobby": 0.2,
	"street": 0.5,
	"convenience_store": 0.3,
	"bridge": 0.7,
	"underpass": 0.8,
	"subway_station": 1.0,
}

# ════════════════════════════════════════════════════════════
# BGM System (Issue #219)
# ════════════════════════════════════════════════════════════

# ── BGM Constants ──
const BGM_DUCK_DB: float = -8.0
const BGM_AMBIENT_DUCK_DB: float = -3.0
const BGM_CROSSFADE_TIME: float = 2.0
const MOTIF_HOLD_TIME: float = 5.0
const MOTIF_FADE_OUT_TIME: float = 2.0

# ── 3D Audio Constants ──
const RAIN_3D_POSITION: Vector3 = Vector3(0, 15, 0)
const CITY_3D_POSITION: Vector3 = Vector3(-50, 5, 0)
const SUBWAY_3D_POSITION: Vector3 = Vector3(0, -8, 0)

# ── Hallucination Audio Constants ──
const HALLUCINATION_LFO_RATE: float = 0.5
const HALLUCINATION_PITCH_DEPTH: float = 0.1
const HALLUCINATION_PITCH_DEPTH_HIGH: float = 0.15
const HALLUCINATION_DROPOUT_DB: float = -80.0
const HALLUCINATION_DROPOUT_MS: int = 100
const HALLUCINATION_DROPOUT_INTERVAL_MIN: float = 3.0
const HALLUCINATION_DROPOUT_INTERVAL_MAX: float = 5.0

# ── BGM State ──
var _bgm_player: AudioStreamPlayer
var _motif_player: AudioStreamPlayer
var _ending_player: AudioStreamPlayer
var _bgm_state: String = "ambient"
var _active_npc_id: String = ""
var _motif_hold_timer: Timer

# ── 3D Spatial Players ──
var _rain_3d_player: AudioStreamPlayer3D
var _rain_heavy_3d_player: AudioStreamPlayer3D
var _city_3d_player: AudioStreamPlayer3D
var _traffic_player: AudioStreamPlayer3D
var _subway_player: AudioStreamPlayer3D
var _subway_close_player: AudioStreamPlayer3D

# ── Hallucination Audio State ──
var _hallucination_level: int = 0
var _hallucination_lfo_timer: Timer
var _hallucination_lfo_time: float = 0.0
var _hallucination_dropout_timer: Timer
var _hallucination_effects_active: bool = false

# ── Bus Indices (new) ──
var _music_bus_idx: int = -1
var _hallucination_bus_idx: int = -1
var _cinema_bus_idx: int = -1

# ── Bus Effect Indices (new) ──
var _hallucination_lpf_idx: int = -1
var _hallucination_reverb_idx: int = -1
var _hallucination_delay_idx: int = -1
var _hallucination_phaser_idx: int = -1

# Per-scene BGM configuration
const SCENE_BGM_CONFIG: Dictionary = {
	"office":           {"bed_volume": -6, "enabled": true},
	"lobby":            {"bed_volume": -4, "enabled": true},
	"street":           {"bed_volume": -3, "enabled": true},
	"convenience_store": {"bed_volume": -5, "enabled": true},
	"bridge":           {"bed_volume": -3, "enabled": true},
	"underpass":        {"bed_volume": -8, "enabled": true},
	"subway_station":   {"bed_volume": -6, "enabled": true},
}

# NPC motif mapping
const NPC_TO_MOTIF: Dictionary = {
	"Stranger": {"stream": null, "path": "res://assets/audio/npc_stranger_music.ogg"},
	"Guard":    {"stream": null, "path": "res://assets/audio/npc_guard_music.ogg"},
	"Clerk":    {"stream": null, "path": "res://assets/audio/npc_clerk_music.ogg"},
	"Homeless": {"stream": null, "path": "res://assets/audio/npc_homeless_music.ogg"},
}

# Ending music mapping
const ENDING_MUSIC: Dictionary = {
	"keep_walking": {"stream": null, "path": "res://assets/audio/ending_keep_walking.ogg"},
	"turn_back":    {"stream": null, "path": "res://assets/audio/ending_turn_back.ogg"},
	"stay":         {"stream": null, "path": "res://assets/audio/ending_stay.ogg"},
}

# NPC proximity distance threshold for motif trigger
const NPC_PROXIMITY_TRIGGER_DIST: float = 4.0

# ════════════════════════════════════════════════════════════


func _ready() -> void:
	_load_audio_streams()
	_setup_audio_players()
	_find_bus_indices()
	_configure_distortion_effect()
	_start_ambient_loops()
	_connect_state_system()

	# New: BGM, 3D, hallucination system
	_setup_bgm_players()
	_setup_3d_players()
	_setup_hallucination_system()
	_load_bgm_streams()
	_load_3d_audio_streams()
	_connect_npc_signals()
	_connect_hallucination_signals()


func _process(delta: float) -> void:
	_sync_3d_listener()
	if _hallucination_effects_active and _hallucination_level >= 5:
		_apply_hallucination_lfo(delta)


# ════════════════════════════════════════════════════════════
# BGM System Setup
# ════════════════════════════════════════════════════════════

func _setup_bgm_players() -> void:
	# Ambient BGM bed
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = "MusicBus"
	_bgm_player.volume_db = -80.0
	add_child(_bgm_player)

	# NPC encounter motif
	_motif_player = AudioStreamPlayer.new()
	_motif_player.name = "MotifPlayer"
	_motif_player.bus = "MusicBus"
	_motif_player.volume_db = -80.0
	add_child(_motif_player)

	# Ending music
	_ending_player = AudioStreamPlayer.new()
	_ending_player.name = "EndingPlayer"
	_ending_player.bus = "CinemaBus"
	_ending_player.volume_db = -80.0
	add_child(_ending_player)

	# Motif hold timer
	_motif_hold_timer = Timer.new()
	_motif_hold_timer.name = "MotifHoldTimer"
	_motif_hold_timer.one_shot = true
	_motif_hold_timer.timeout.connect(_on_motif_hold_timeout)
	add_child(_motif_hold_timer)


func _load_bgm_streams() -> void:
	# Ambient BGM stream
	var bgm_stream: AudioStream = _try_load("res://assets/audio/ambient_music.ogg")
	if bgm_stream:
		_bgm_player.stream = bgm_stream
		_bgm_player.play()

	# Preload NPC motif streams
	for npc_id: String in NPC_TO_MOTIF:
		var entry: Dictionary = NPC_TO_MOTIF[npc_id]
		var stream: AudioStream = _try_load(entry.path)
		entry.stream = stream

	# Preload ending music streams
	for ending_id: String in ENDING_MUSIC:
		var entry: Dictionary = ENDING_MUSIC[ending_id]
		var stream: AudioStream = _try_load(entry.path)
		entry.stream = stream


func _load_3d_audio_streams() -> void:
	var traffic: AudioStream = _try_load("res://assets/audio/traffic_rumble.ogg")
	if traffic and _traffic_player:
		_traffic_player.stream = traffic
		_traffic_player.play()

	var subway: AudioStream = _try_load("res://assets/audio/subway_rumble.ogg")
	if subway and _subway_player:
		_subway_player.stream = subway
		_subway_player.play()

	var subway_close: AudioStream = _try_load("res://assets/audio/subway_rumble_close.ogg")
	if subway_close and _subway_close_player:
		_subway_close_player.stream = subway_close
		_subway_close_player.play()


# ════════════════════════════════════════════════════════════
# 3D Spatial Audio
# ════════════════════════════════════════════════════════════

func _setup_3d_players() -> void:
	_rain_3d_player = AudioStreamPlayer3D.new()
	_rain_3d_player.name = "Rain3DPlayer"
	_rain_3d_player.bus = "AmbientBus"
	_rain_3d_player.position = RAIN_3D_POSITION
	_rain_3d_player.max_db_distance = 100.0
	_rain_3d_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE
	add_child(_rain_3d_player)

	_rain_heavy_3d_player = AudioStreamPlayer3D.new()
	_rain_heavy_3d_player.name = "RainHeavy3DPlayer"
	_rain_heavy_3d_player.bus = "AmbientBus"
	_rain_heavy_3d_player.position = RAIN_3D_POSITION
	_rain_heavy_3d_player.max_db_distance = 100.0
	_rain_heavy_3d_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE
	_rain_heavy_3d_player.volume_db = -80.0
	add_child(_rain_heavy_3d_player)

	_city_3d_player = AudioStreamPlayer3D.new()
	_city_3d_player.name = "CityHum3DPlayer"
	_city_3d_player.bus = "AmbientBus"
	_city_3d_player.position = CITY_3D_POSITION
	_city_3d_player.max_db_distance = 200.0
	_city_3d_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE
	add_child(_city_3d_player)

	_traffic_player = AudioStreamPlayer3D.new()
	_traffic_player.name = "TrafficPlayer"
	_traffic_player.bus = "AmbientBus"
	_traffic_player.position = Vector3(-60, 2, 0)
	_traffic_player.max_db_distance = 150.0
	_traffic_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE
	add_child(_traffic_player)

	_subway_player = AudioStreamPlayer3D.new()
	_subway_player.name = "SubwayPlayer"
	_subway_player.bus = "AmbientBus"
	_subway_player.position = SUBWAY_3D_POSITION
	_subway_player.max_db_distance = 80.0
	_subway_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE
	add_child(_subway_player)

	_subway_close_player = AudioStreamPlayer3D.new()
	_subway_close_player.name = "SubwayClosePlayer"
	_subway_close_player.bus = "AmbientBus"
	_subway_close_player.position = Vector3(0, -5, 5)
	_subway_close_player.max_db_distance = 30.0
	_subway_close_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE
	_subway_close_player.volume_db = -80.0
	add_child(_subway_close_player)

	# Clone streams from 2D players to 3D players
	if _rain_stream and _rain_3d_player:
		_rain_3d_player.stream = _rain_stream
		_rain_3d_player.play()
	if _rain_heavy_stream and _rain_heavy_3d_player:
		_rain_heavy_3d_player.stream = _rain_heavy_stream
		_rain_heavy_3d_player.play()
	if _city_hum_stream and _city_3d_player:
		_city_3d_player.stream = _city_hum_stream
		_city_3d_player.play()


func _sync_3d_listener() -> void:
	# Find the player controller and sync listener position
	var player := get_node_or_null("/root/GameManager/PlayerController")
	if player == null:
		# Try current scene
		var tree := get_tree()
		if tree:
			var scene_root := tree.current_scene
			if scene_root:
				player = scene_root.get_node_or_null("PlayerController")
	if player == null:
		return

	var cam_pos: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	# 3D players are children of AudioManager — set their positions
	# relative to the player via global position offsets
	# We don't need to set a listener; Godot's 3D audio uses the
	# active camera as the listener automatically.


# ════════════════════════════════════════════════════════════
# BGM Public API
# ════════════════════════════════════════════════════════════

func set_ending_music(ending_id: String) -> void:
	var entry: Dictionary = ENDING_MUSIC.get(ending_id, {})
	if entry.is_empty() or entry.stream == null:
		push_warning("AudioManager: Ending music asset not found for '%s'" % ending_id)
		return

	# Cancel active motif
	_clear_motif_immediate()

	# Fade out ambient BGM
	var tween: Tween = create_tween()
	if tween == null:
		return
	tween.set_parallel(true)

	# Fade in ending music
	_ending_player.stream = entry.stream
	_ending_player.volume_db = -80.0
	_ending_player.play()
	tween.tween_property(_ending_player, "volume_db", 0.0, BGM_CROSSFADE_TIME)

	# Fade out ambient bed
	if _bgm_player:
		tween.tween_property(_bgm_player, "volume_db", -80.0, BGM_CROSSFADE_TIME)

	# Fade out motif
	if _motif_player:
		tween.tween_property(_motif_player, "volume_db", -80.0, BGM_CROSSFADE_TIME)

	# Fade out rain ambience
	if _rain_player:
		tween.tween_property(_rain_player, "volume_db", -80.0, BGM_CROSSFADE_TIME)

	_bgm_state = "ending"


func set_bgm_ducking(ducking: bool) -> void:
	var tween: Tween = create_tween()
	if tween == null:
		return
	tween.set_parallel(true)

	if ducking:
		var target_bgm: float = BGM_DUCK_DB   # -8 dB for BGM
		var target_ambient: float = BGM_AMBIENT_DUCK_DB  # -3 dB for ambient
		if _motif_player:
			tween.tween_property(_motif_player, "volume_db", target_bgm, 0.5)
		if _bgm_player:
			tween.tween_property(_bgm_player, "volume_db", target_ambient, 0.5)
	else:
		if _motif_player:
			tween.tween_property(_motif_player, "volume_db", 0.0, 0.5)
		if _bgm_player:
			tween.tween_property(_bgm_player, "volume_db", 0.0, 0.5)


func trigger_bgm_motif(npc_id: String) -> void:
	var entry: Dictionary = NPC_TO_MOTIF.get(npc_id, {})
	if entry.is_empty() or entry.stream == null:
		push_warning("AudioManager: Motif stream not found for NPC '%s'" % npc_id)
		return

	# Kill any in-progress fade tween on motif player
	var existing_tween: Tween = _motif_player.get_tree().create_tween()
	if existing_tween:
		existing_tween.kill()

	# Set motif stream
	_motif_player.stream = entry.stream
	_motif_player.volume_db = -80.0
	_motif_player.play()

	# Fade in
	var tween: Tween = create_tween()
	if tween:
		tween.tween_property(_motif_player, "volume_db", 0.0, BGM_CROSSFADE_TIME)

	_active_npc_id = npc_id
	_bgm_state = "npc_active"


func clear_bgm_motif() -> void:
	if _bgm_state != "npc_active":
		return

	# Kill in-progress fade tweens
	var existing_tween: Tween = _motif_player.get_tree().create_tween()
	if existing_tween:
		existing_tween.kill()

	# Fade out
	var tween: Tween = create_tween()
	if tween:
		tween.tween_property(_motif_player, "volume_db", -80.0, MOTIF_FADE_OUT_TIME)

	_active_npc_id = ""
	_bgm_state = "ambient"


func _clear_motif_immediate() -> void:
	var existing_tween: Tween = _motif_player.get_tree().create_tween()
	if existing_tween:
		existing_tween.kill()
	_motif_player.volume_db = -80.0
	_motif_hold_timer.stop()
	_active_npc_id = ""


# ════════════════════════════════════════════════════════════
# Signal Connections (NPC → BGM)
# ════════════════════════════════════════════════════════════

func _connect_npc_signals() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for npc in tree.get_nodes_in_group("npcs"):
		if npc.has_signal("npc_dialogue_started"):
			npc.dialogue_started.connect(_on_npc_dialogue_started)
		if npc.has_signal("dialogue_completed"):
			npc.dialogue_completed.connect(_on_npc_dialogue_ended)


func _connect_hallucination_signals() -> void:
	var nm := get_node_or_null("/root/NarrativeManager")
	if nm and nm.has_signal("hallucination_level_changed"):
		nm.hallucination_level_changed.connect(_on_hallucination_level_changed)


func _on_npc_dialogue_started(npc_id: String) -> void:
	trigger_bgm_motif(npc_id)


func _on_npc_dialogue_ended(npc_id: String) -> void:
	if _active_npc_id != npc_id:
		return

	# Restore volume from ducking
	set_bgm_ducking(false)

	# Start hold timer before motif fade-out
	if _motif_hold_timer:
		_motif_hold_timer.start(MOTIF_HOLD_TIME)


func _on_motif_hold_timeout() -> void:
	clear_bgm_motif()


# ════════════════════════════════════════════════════════════
# Hallucination Audio System
# ════════════════════════════════════════════════════════════

func _setup_hallucination_system() -> void:
	_hallucination_lfo_timer = Timer.new()
	_hallucination_lfo_timer.name = "HallucinationLFOTimer"
	_hallucination_lfo_timer.wait_time = 1.0 / HALLUCINATION_LFO_RATE
	_hallucination_lfo_timer.one_shot = false
	_hallucination_lfo_timer.timeout.connect(_on_hallucination_lfo_tick)
	add_child(_hallucination_lfo_timer)

	_hallucination_dropout_timer = Timer.new()
	_hallucination_dropout_timer.name = "HallucinationDropoutTimer"
	_hallucination_dropout_timer.one_shot = false
	_hallucination_dropout_timer.timeout.connect(_on_hallucination_dropout_tick)
	add_child(_hallucination_dropout_timer)


func _on_hallucination_level_changed(level: int) -> void:
	_hallucination_level = level

	if level < 5:
		# Disable effects with 1s smooth transition
		_hallucination_effects_active = false
		_hallucination_lfo_timer.stop()
		_hallucination_dropout_timer.stop()
		_disable_all_hallucination_effects()
	else:
		_hallucination_effects_active = true
		_update_hallucination_effects()

		if level >= 5:
			if not _hallucination_lfo_timer.is_stopped() == false:
				_hallucination_lfo_timer.start()

		if level >= 9:
			_hallucination_dropout_timer.start(
				randf_range(HALLUCINATION_DROPOUT_INTERVAL_MIN, HALLUCINATION_DROPOUT_INTERVAL_MAX)
			)


func _update_hallucination_effects() -> void:
	var level: int = _hallucination_level

	# Level 5+: enable LowPass + Reverb
	if level >= 5:
		_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_lpf_idx, true)
		_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_reverb_idx, true)

		# Adjust LPF cutoff proportional to level
		var cutoff: float = lerpf(3000.0, 500.0, clampf((level - 5.0) / 5.0, 0.0, 1.0))
		if _hallucination_bus_idx >= 0 and _hallucination_lpf_idx >= 0:
			var lpf := AudioServer.get_bus_effect(_hallucination_bus_idx, _hallucination_lpf_idx) as AudioEffectLowPassFilter
			if lpf:
				lpf.cutoff_hz = cutoff

	# Level 7+: enable Delay
	if level >= 7:
		_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_delay_idx, true)

	# Level 9+: enable Phaser
	if level >= 9:
		_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_phaser_idx, true)


func _disable_all_hallucination_effects() -> void:
	_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_lpf_idx, false)
	_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_reverb_idx, false)
	_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_delay_idx, false)
	_set_bus_effect_enabled(_hallucination_bus_idx, _hallucination_phaser_idx, false)


func _on_hallucination_lfo_tick() -> void:
	# LFO tick sets time for _process-based modulation
	pass


func _apply_hallucination_lfo(delta: float) -> void:
	_hallucination_lfo_time += delta
	var depth: float = HALLUCINATION_PITCH_DEPTH if _hallucination_level < 7 else HALLUCINATION_PITCH_DEPTH_HIGH
	var lfo: float = sin(_hallucination_lfo_time * HALLUCINATION_LFO_RATE * TAU) * depth

	# Apply to 3D rain player
	if _rain_3d_player:
		_rain_3d_player.pitch_scale = 1.0 + lfo
	if _city_3d_player:
		_city_3d_player.pitch_scale = 1.0 + lfo * 0.7


func _on_hallucination_dropout_tick() -> void:
	# Temporarily mute players for HALLUCINATION_DROPOUT_MS
	var players: Array = [_rain_3d_player, _city_3d_player, _traffic_player, _subway_player]
	for p in players:
		if p:
			p.volume_db = HALLUCINATION_DROPOUT_DB

	# Restore after dropout duration
	await get_tree().create_timer(HALLUCINATION_DROPOUT_MS / 1000.0).timeout
	for p in players:
		if p:
			p.volume_db = 0.0

	# Schedule next dropout
	if _hallucination_level >= 9:
		_hallucination_dropout_timer.start(
			randf_range(HALLUCINATION_DROPOUT_INTERVAL_MIN, HALLUCINATION_DROPOUT_INTERVAL_MAX)
		)


# ════════════════════════════════════════════════════════════
# Scene BGM Bed Management
# ════════════════════════════════════════════════════════════

func _update_bgm_bed(scene_id: String) -> void:
	var config: Dictionary = SCENE_BGM_CONFIG.get(scene_id, {})
	if config.is_empty() or not config.get("enabled", false):
		return

	var bed_volume: float = config.get("bed_volume", -6.0)
	if _bgm_player:
		var tween: Tween = create_tween()
		if tween:
			tween.tween_property(_bgm_player, "volume_db", bed_volume, 0.5)


# ════════════════════════════════════════════════════════════
# Existing Audio Stream Loading & Setup
# ════════════════════════════════════════════════════════════

func _load_audio_streams() -> void:
	_rain_stream = _try_load("res://assets/audio/rain_loop.wav")
	_rain_heavy_stream = _try_load("res://assets/audio/rain_heavy.wav")
	_city_hum_stream = _try_load("res://assets/audio/city_hum.wav")
	_footstep_office = _try_load("res://assets/audio/footstep_office.wav")
	_footstep_street = _try_load("res://assets/audio/footstep_street.wav")
	_footstep_underpass = _try_load("res://assets/audio/footstep_underpass.wav")


func _try_load(path: String) -> AudioStream:
	var res := load(path)
	if res == null:
		push_warning("AudioManager: Could not load audio: ", path)
		return null
	if res is AudioStream:
		return res
	push_warning("AudioManager: Resource is not AudioStream: ", path)
	return null


func _setup_audio_players() -> void:
	_rain_player = AudioStreamPlayer2D.new()
	_rain_player.name = "RainPlayer"
	_rain_player.bus = "AmbientBus"
	add_child(_rain_player)

	_rain_heavy_player = AudioStreamPlayer2D.new()
	_rain_heavy_player.name = "RainHeavyPlayer"
	_rain_heavy_player.bus = "AmbientBus"
	_rain_heavy_player.volume_db = -80.0
	add_child(_rain_heavy_player)

	_city_hum_player = AudioStreamPlayer2D.new()
	_city_hum_player.name = "CityHumPlayer"
	_city_hum_player.bus = "AmbientBus"
	add_child(_city_hum_player)

	_footstep_player = AudioStreamPlayer2D.new()
	_footstep_player.name = "FootstepPlayer"
	_footstep_player.bus = "SFXBus"
	add_child(_footstep_player)


func _find_bus_indices() -> void:
	var count := AudioServer.get_bus_count()
	for i in count:
		var name := AudioServer.get_bus_name(i)
		match name:
			"Master": _master_bus_idx = i
			"AmbientBus": _ambient_bus_idx = i
			"SFXBus": _sfx_bus_idx = i
			"IndoorBus": _indoor_bus_idx = i
			"UnderpassBus": _underpass_bus_idx = i
			"MusicBus": _music_bus_idx = i
			"HallucinationFXBus": _hallucination_bus_idx = i
			"CinemaBus": _cinema_bus_idx = i

	if _master_bus_idx >= 0:
		var fx_count := AudioServer.get_bus_effect_count(_master_bus_idx)
		for j in fx_count:
			var fx := AudioServer.get_bus_effect(_master_bus_idx, j)
			if fx != null and fx is AudioEffectDistortion:
				_distortion_effect_idx = j
				break

	# Find hallucination bus effect indices
	if _hallucination_bus_idx >= 0:
		var fx_count := AudioServer.get_bus_effect_count(_hallucination_bus_idx)
		for j in fx_count:
			var fx := AudioServer.get_bus_effect(_hallucination_bus_idx, j)
			if fx == null:
				continue
			if fx is AudioEffectLowPassFilter:
				_hallucination_lpf_idx = j
			elif fx is AudioEffectReverb:
				_hallucination_reverb_idx = j
			elif fx is AudioEffectDelay:
				_hallucination_delay_idx = j
			elif fx is AudioEffectPhaser:
				_hallucination_phaser_idx = j


func _configure_distortion_effect() -> void:
	if _master_bus_idx >= 0 and _distortion_effect_idx >= 0:
		AudioServer.set_bus_effect_enabled(_master_bus_idx, _distortion_effect_idx, false)


func _start_ambient_loops() -> void:
	if _rain_player and _rain_stream:
		_rain_player.stream = _rain_stream
		_rain_player.play()
	if _rain_heavy_player and _rain_heavy_stream:
		_rain_heavy_player.stream = _rain_heavy_stream
		_rain_heavy_player.play()
	if _city_hum_player and _city_hum_stream:
		_city_hum_player.stream = _city_hum_stream
		_city_hum_player.play()


func _connect_state_system() -> void:
	var ss := get_node_or_null("/root/StateSystem")
	if ss and ss.has_signal("state_changed"):
		ss.state_changed.connect(_on_state_changed)


func register_scene(scene_id: String) -> void:
	_current_scene_id = scene_id
	var profile: String = SCENE_TO_PROFILE.get(scene_id, "default")
	var distance: float = SCENE_TO_DISTANCE.get(scene_id, 0.0)
	_distance_factor = distance
	set_bus_profile(profile)
	_update_scene_3d_profile(scene_id)
	if profile == "default":
		push_warning("AudioManager: No ambient profile for scene '%s'" % scene_id)


func _update_scene_3d_profile(scene_id: String) -> void:
	match scene_id:
		"office":
			# Indoor — rain muffled, no traffic/subway
			_rain_3d_player.volume_db = -12.0
			_traffic_player.volume_db = -80.0
			_subway_player.volume_db = -80.0
			_subway_close_player.volume_db = -80.0
		"lobby":
			_rain_3d_player.volume_db = -8.0
			_traffic_player.volume_db = -20.0
			_subway_player.volume_db = -80.0
			_subway_close_player.volume_db = -80.0
		"street":
			# Outdoor — full rain, traffic audible
			_rain_3d_player.volume_db = 0.0
			_traffic_player.volume_db = -6.0
			_subway_player.volume_db = -15.0
			_subway_close_player.volume_db = -80.0
		"convenience_store":
			_rain_3d_player.volume_db = -10.0
			_traffic_player.volume_db = -15.0
			_subway_player.volume_db = -80.0
			_subway_close_player.volume_db = -80.0
		"bridge":
			# Outdoor — full rain, traffic from distance
			_rain_3d_player.volume_db = 0.0
			_traffic_player.volume_db = -3.0
			_subway_player.volume_db = -12.0
			_subway_close_player.volume_db = -80.0
		"underpass":
			# Underpass — rain muffled, subway close
			_rain_3d_player.volume_db = -15.0
			_traffic_player.volume_db = -80.0
			_subway_player.volume_db = -6.0
			_subway_close_player.volume_db = -3.0
		"subway_station":
			_rain_3d_player.volume_db = -12.0
			_traffic_player.volume_db = -80.0
			_subway_player.volume_db = -3.0
			_subway_close_player.volume_db = -80.0
		_:
			_rain_3d_player.volume_db = 0.0
			_traffic_player.volume_db = -10.0
			_subway_player.volume_db = -15.0
			_subway_close_player.volume_db = -80.0


func set_bus_profile(profile: String) -> void:
	_current_profile = profile

	_bypass_all_effects()

	match profile:
		"indoor":
			_set_bus_effect_enabled(_indoor_bus_idx, 0, true)
		"underpass":
			_set_bus_effect_enabled(_underpass_bus_idx, 0, true)
			_set_bus_effect_enabled(_underpass_bus_idx, 1, true)

	ambient_profile_changed.emit(profile)


func _bypass_all_effects() -> void:
	_set_bus_effect_enabled(_indoor_bus_idx, 0, false)
	_set_bus_effect_enabled(_underpass_bus_idx, 0, false)
	_set_bus_effect_enabled(_underpass_bus_idx, 1, false)


func _set_bus_effect_enabled(bus_idx: int, effect_idx: int, enabled: bool) -> void:
	if bus_idx < 0:
		return
	var count := AudioServer.get_bus_count()
	if bus_idx >= count:
		return
	if effect_idx < 0 or effect_idx >= AudioServer.get_bus_effect_count(bus_idx):
		return
	AudioServer.set_bus_effect_enabled(bus_idx, effect_idx, enabled)


func play_footstep(surface_type: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_footstep_time < FOOTSTEP_COOLDOWN:
		return
	_last_footstep_time = now

	var stream: AudioStream
	match surface_type:
		"office": stream = _footstep_office
		"street": stream = _footstep_street
		"underpass": stream = _footstep_underpass
		_: stream = _footstep_office

	if _footstep_player and stream:
		_footstep_player.stream = stream
		_footstep_player.play()

	footstep_played.emit(surface_type)


func get_surface_for_scene(scene_id: String) -> String:
	return SCENE_TO_SURFACE.get(scene_id, "office")


func _get_profile_for_scene(scene_id: String) -> String:
	return SCENE_TO_PROFILE.get(scene_id, "default")


func cross_fade_ambient(target_scene_id: String, duration: float = 0.4) -> void:
	var tween: Tween = create_tween()
	if tween == null:
		_apply_cross_fade_immediate(target_scene_id)
		return

	tween.set_parallel(true)
	if _rain_player:
		tween.tween_property(_rain_player, "volume_db", -80.0, duration * 0.5)
	if _rain_heavy_player:
		tween.tween_property(_rain_heavy_player, "volume_db", -80.0, duration * 0.5)
	if _city_hum_player:
		tween.tween_property(_city_hum_player, "volume_db", -80.0, duration * 0.5)

	await tween.finished

	var profile := _get_profile_for_scene(target_scene_id)
	_distance_factor = SCENE_TO_DISTANCE.get(target_scene_id, 0.0)
	set_bus_profile(profile)

	var rain_vol: float = _calc_rain_volume()
	var hum_vol: float = _calc_hum_volume()

	var tween_in: Tween = create_tween()
	if tween_in == null:
		_rain_player.volume_db = rain_vol
		_city_hum_player.volume_db = hum_vol
		return

	tween_in.set_parallel(true)
	if _rain_player:
		tween_in.tween_property(_rain_player, "volume_db", rain_vol, duration * 0.5)
	if _city_hum_player:
		tween_in.tween_property(_city_hum_player, "volume_db", hum_vol, duration * 0.5)


func _apply_cross_fade_immediate(target_scene_id: String) -> void:
	var profile := _get_profile_for_scene(target_scene_id)
	_distance_factor = SCENE_TO_DISTANCE.get(target_scene_id, 0.0)
	set_bus_profile(profile)
	if _rain_player:
		_rain_player.volume_db = _calc_rain_volume()
	if _rain_heavy_player:
		_rain_heavy_player.volume_db = -80.0
	if _city_hum_player:
		_city_hum_player.volume_db = _calc_hum_volume()


func _on_state_changed(state: Dictionary) -> void:
	var conviction: float = state.get("conviction", 5.0)
	_rain_intensity = clampf((10.0 - conviction) / 10.0, 0.0, 1.0)

	var despair: float = state.get("despair", 0.0)
	var despair_norm: float
	if despair > 10.0:
		despair_norm = clampf(despair / 100.0, 0.0, 1.0)
	else:
		despair_norm = clampf(despair / 10.0, 0.0, 1.0)

	_update_rain_volume(despair_norm)
	_update_rain_pitch()
	_update_hum_volume(despair_norm)
	_update_distortion(despair_norm)


func _update_rain_volume(despair_norm: float) -> void:
	if not _rain_player:
		return
	var vol := _calc_rain_volume()
	_rain_player.volume_db = vol
	var heavy_vol := _calc_rain_heavy_volume(despair_norm)
	_rain_heavy_player.volume_db = heavy_vol


func _calc_rain_volume() -> float:
	var vol := lerpf(-24.0, -6.0, _rain_intensity * _distance_factor)
	return minf(vol, 0.0)


func _calc_rain_heavy_volume(despair_norm: float) -> float:
	if despair_norm < 0.5:
		return -80.0
	var vol := lerpf(-30.0, -12.0, despair_norm * _distance_factor)
	return minf(vol, 0.0)


func _update_rain_pitch() -> void:
	if not _rain_player:
		return
	var pitch := lerpf(1.0, 1.3, _rain_intensity)
	_rain_player.pitch_scale = pitch


func _update_hum_volume(despair_norm: float) -> void:
	if not _city_hum_player:
		return
	var vol := _calc_hum_volume(despair_norm)
	_city_hum_player.volume_db = vol


func _calc_hum_volume(despair_norm: float = 0.0) -> float:
	var vol := lerpf(-20.0, -8.0, despair_norm * _distance_factor)
	return minf(vol, 0.0)


func _update_distortion(despair_norm: float) -> void:
	if _master_bus_idx < 0 or _distortion_effect_idx < 0:
		return
	var enabled := despair_norm > 0.5
	AudioServer.set_bus_effect_enabled(_master_bus_idx, _distortion_effect_idx, enabled)


func get_state() -> Dictionary:
	return {
		"current_scene_id": _current_scene_id,
		"current_profile": _current_profile,
		"rain_intensity": _rain_intensity,
		"distance_factor": _distance_factor,
		"bgm_state": _bgm_state,
		"active_npc_id": _active_npc_id,
		"hallucination_level": _hallucination_level,
		"hallucination_effects_active": _hallucination_effects_active,
	}

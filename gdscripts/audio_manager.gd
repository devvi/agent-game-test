extends Node

signal ambient_profile_changed(scene_id: String)
signal footstep_played(surface_type: String)

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


func _ready() -> void:
	_load_audio_streams()
	_setup_audio_players()
	_find_bus_indices()
	_configure_distortion_effect()
	_start_ambient_loops()
	_connect_state_system()


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

	if _master_bus_idx >= 0:
		var fx_count := AudioServer.get_bus_effect_count(_master_bus_idx)
		for j in fx_count:
			var fx := AudioServer.get_bus_effect(_master_bus_idx, j)
			if fx != null and fx is AudioEffectDistortion:
				_distortion_effect_idx = j
				break


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
	if profile == "default":
		push_warning("AudioManager: No ambient profile for scene '%s'" % scene_id)


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
	}

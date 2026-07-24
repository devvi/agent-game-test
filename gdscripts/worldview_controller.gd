extends Node

# WorldviewController — Maps hope/despair to environment tone
# Listens to state_changed and emits world_text_changed with tone prefix.
# Expanded from 3-tone to 5-state for Issue #50.
# Also emits world_state_changed(state_id: int) for downstream consumers.

signal world_text_changed(prefix: String)
signal world_state_changed(state_id: int)

func _ready() -> void:
	var state_system = get_node_or_null("/root/StateSystem")
	if state_system:
		state_system.state_changed.connect(_on_state_changed)

func _on_state_changed(state: Dictionary) -> void:
	var tone = _calculate_tone(state.get("hope", 5.0), state.get("conviction", 5.0))
	world_text_changed.emit(tone)
	# Emit discrete state ID from hope_despair if available, else derive from hope
	var state_id: int = state.get("state_id", 0)
	if state_id == 0:
		var hope_val: float = state.get("hope", 5.0)
		state_id = _hope_to_state_id(hope_val)
	world_state_changed.emit(state_id)

## Convert hope (0–10) to discrete state ID (1–5) matching StateSystem.get_state_id()
static func _hope_to_state_id(hope: float) -> int:
	if hope <= 2.0:
		return 1
	elif hope <= 4.0:
		return 2
	elif hope <= 6.0:
		return 3
	elif hope <= 8.0:
		return 4
	else:
		return 5

## Calculate 5-state tone from hope value.
## Returns: "despair", "low", "neutral", "buoyant", or "hope".
func _calculate_tone(hope: float, conviction: float) -> String:
	var state_id: int = _hope_to_state_id(hope)
	match state_id:
		1:
			return "despair"
		2:
			return "low"
		3:
			return "neutral"
		4:
			return "buoyant"
		5:
			return "hope"
		_:
			return "neutral"

func get_tone_for_state(state: Dictionary) -> String:
	return _calculate_tone(state.get("hope", 5.0), state.get("conviction", 5.0))


# ===== Hallucination Visual Mapping (Issue #214) =====

## Get hallucination-to-visual parameter mapping.
## Returns {vignette, rain_density, light_flicker, text_drift, view_instability}
func get_hallucination_params(level: int) -> Dictionary:
	var params: Dictionary = {
		"vignette": 0.0,
		"rain_density": 0.0,
		"light_flicker": 0.0,
		"text_drift": 0.0,
		"view_instability": 0.0
	}

	if level <= 0:
		pass  # All defaults — no hallucination
	elif level <= 2:
		params["vignette"] = 0.1 + level * 0.05
		params["rain_density"] = 0.1
	elif level <= 4:
		params["vignette"] = 0.2 + (level - 2) * 0.1
		params["rain_density"] = 0.2 + (level - 2) * 0.1
		params["light_flicker"] = (level - 2) * 0.15
	elif level <= 6:
		params["vignette"] = 0.4 + (level - 4) * 0.1
		params["rain_density"] = 0.4 + (level - 4) * 0.1
		params["light_flicker"] = 0.3 + (level - 4) * 0.1
		params["text_drift"] = (level - 4) * 0.1
	elif level <= 8:
		params["vignette"] = 0.6 + (level - 6) * 0.1
		params["rain_density"] = 0.6 + (level - 6) * 0.1
		params["light_flicker"] = 0.5 + (level - 6) * 0.1
		params["text_drift"] = 0.2 + (level - 6) * 0.15
		params["view_instability"] = 0.1 + (level - 6) * 0.1
	else:  # level 9-10
		params["vignette"] = 0.8
		params["rain_density"] = 0.9
		params["light_flicker"] = 0.8
		params["text_drift"] = 0.5
		params["view_instability"] = 0.4

	return params


## Apply hallucination effects to visual environment.
## Modifies: vignette intensity, rain density, light flicker, text drift.
## In a full scene, this would control Camera3D, RainController, and light nodes.
## For headless test mode, this emits a signal that downstream systems can listen to.
signal hallucination_effects_applied(level: int, params: Dictionary)

func apply_hallucination_effects(level: int) -> void:
	var params: Dictionary = get_hallucination_params(level)
	# Emit signal for downstream consumers (CameraController, RainController, etc.)
	hallucination_effects_applied.emit(level, params)


## Get the full tone + hallucination mapping for debugging and test verification.
func get_hallucination_tone_map() -> Dictionary:
	return {
		"level_0": {"vignette": 0.0, "rain_density": 0.0, "light_flicker": 0.0, "text_drift": 0.0, "view_instability": 0.0},
		"level_1": {"vignette": 0.15, "rain_density": 0.1, "light_flicker": 0.0, "text_drift": 0.0, "view_instability": 0.0},
		"level_2": {"vignette": 0.2, "rain_density": 0.1, "light_flicker": 0.0, "text_drift": 0.0, "view_instability": 0.0},
		"level_3": {"vignette": 0.3, "rain_density": 0.3, "light_flicker": 0.15, "text_drift": 0.0, "view_instability": 0.0},
		"level_4": {"vignette": 0.4, "rain_density": 0.4, "light_flicker": 0.3, "text_drift": 0.0, "view_instability": 0.0},
		"level_5": {"vignette": 0.5, "rain_density": 0.5, "light_flicker": 0.4, "text_drift": 0.1, "view_instability": 0.0},
		"level_6": {"vignette": 0.6, "rain_density": 0.6, "light_flicker": 0.5, "text_drift": 0.2, "view_instability": 0.1},
		"level_7": {"vignette": 0.7, "rain_density": 0.7, "light_flicker": 0.6, "text_drift": 0.35, "view_instability": 0.2},
		"level_8": {"vignette": 0.8, "rain_density": 0.8, "light_flicker": 0.7, "text_drift": 0.5, "view_instability": 0.3},
		"level_9": {"vignette": 0.8, "rain_density": 0.9, "light_flicker": 0.8, "text_drift": 0.5, "view_instability": 0.4},
		"level_10": {"vignette": 0.8, "rain_density": 0.9, "light_flicker": 0.8, "text_drift": 0.5, "view_instability": 0.4}
	}

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

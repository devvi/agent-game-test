extends Node

# WorldviewController — Maps hope/conviction to environment tone
# Listens to state_changed and emits world_text_changed with tone prefix

signal world_text_changed(prefix: String)

func _ready() -> void:
	var state_system = get_node_or_null("/root/StateSystem")
	if state_system:
		state_system.state_changed.connect(_on_state_changed)

func _on_state_changed(state: Dictionary) -> void:
	var tone = _calculate_tone(state.get("hope", 5.0), state.get("conviction", 5.0))
	world_text_changed.emit(tone)

func _calculate_tone(hope: float, conviction: float) -> String:
	if hope <= 3.0:
		return "despair"
	elif hope >= 7.0:
		return "hope"
	else:
		return "neutral"

func get_tone_for_state(state: Dictionary) -> String:
	return _calculate_tone(state.get("hope", 5.0), state.get("conviction", 5.0))

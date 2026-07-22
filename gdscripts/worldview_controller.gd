extends Node

# WorldviewController — Maps hope/despair to environment tone (5-state)
# Listens to state_changed and emits world_text_changed with 5-state tone prefix
#
# State mapping:
#   1 (Despair)  → "despair"  — Monochrome, dark
#   2 (Low)      → "low"      — Gray-blue
#   3 (Neutral)  → "neutral"  — Default amber
#   4 (Buoyant)  → "buoyant"  — Warm gold
#   5 (Hope)     → "hope"     — Bright glow

signal world_text_changed(prefix: String)
signal world_state_changed(state_id: int)

const STATE_TONES: Array[String] = ["despair", "low", "neutral", "buoyant", "hope"]

func _ready() -> void:
	var state_system = get_node_or_null("/root/StateSystem")
	if state_system:
		state_system.state_changed.connect(_on_state_changed)

func _on_state_changed(state: Dictionary) -> void:
	var state_id = _calculate_state_id(state.get("hope_despair", 0.0))
	var tone = STATE_TONES[state_id - 1]
	world_text_changed.emit(tone)
	world_state_changed.emit(state_id)

## Calculate 5-state ID from hope_despair slider value.
## Returns int 1–5.
func _calculate_state_id(hope_despair: float) -> int:
	var boundaries: Array[float] = [-10.0, -6.0, -2.0, 1.0, 5.0, 10.0]
	for i in range(boundaries.size() - 1):
		if hope_despair >= boundaries[i] and hope_despair <= boundaries[i + 1]:
			return i + 1
	if hope_despair < -10.0:
		return 1
	return 5

## Get tone prefix string for a state dictionary (backward-compatible).
## Now uses hope_despair from state dict, falls back to hope.
func get_tone_for_state(state: Dictionary) -> String:
	var hd: float = state.get("hope_despair", -1.0)
	if hd < -9.0:
		# No hope_despair key; fall back to hope value
		var hope_val: float = state.get("hope", 5.0)
		hd = (hope_val * 2.0) - 10.0
	var state_id = _calculate_state_id(hd)
	return STATE_TONES[state_id - 1]

## Get state ID from a state dictionary (convenience for other modules).
func get_state_id_from_state(state: Dictionary) -> int:
	var hd: float = state.get("hope_despair", -1.0)
	if hd < -9.0:
		var hope_val: float = state.get("hope", 5.0)
		hd = (hope_val * 2.0) - 10.0
	return _calculate_state_id(hd)

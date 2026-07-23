class_name RainText
extends "res://gdscripts/text_component_base.gd"

## RainText — Uses the 'hope' axis for state determination.
## Overrides _apply_variant to apply a despair-state emissive multiplier.
## At state ID 1 (Despair), emissive strength is doubled for a harsh, washed-out look.

func _calculate_state_id(state: Dictionary) -> int:
	var hope_val: float = state.get("hope", 5.0)
	return _hope_to_state_id(hope_val)


func _apply_variant(idx: int) -> void:
	super._apply_variant(idx)
	if idx == 0 and _current_state_id == 1:
		emissive_strength = clampf(emissive_strength * 2.0, 0.0, 5.0)

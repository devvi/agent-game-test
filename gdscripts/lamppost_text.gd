class_name LamppostText
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var will_val: float = state.get("will", 5.0)
    if will_val <= 3.0: return "low"
    elif will_val >= 7.0: return "high"
    else: return "mid"

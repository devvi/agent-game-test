class_name NeonSign
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var conviction_val: float = state.get("conviction", 5.0)
    if conviction_val <= 3.0: return "low"
    elif conviction_val >= 7.0: return "high"
    else: return "mid"

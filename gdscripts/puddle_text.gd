class_name PuddleText
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var hope_val: float = state.get("hope", 5.0)
    if hope_val <= 3.0: return "low"
    elif hope_val >= 7.0: return "high"
    else: return "mid"

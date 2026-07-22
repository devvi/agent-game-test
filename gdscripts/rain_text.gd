class_name RainText
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var hope_val: float = state.get("hope", 5.0)
    if hope_val <= 3.0: return "low"
    elif hope_val >= 7.0: return "high"
    else: return "mid"

func _apply_variant(idx: int) -> void:
    super._apply_variant(idx)
    if idx == 0 and _current_tone == "despair":
        emissive_strength = clampf(emissive_strength * 2.0, 0.0, 5.0)

class_name TextComponentBase
extends "res://gdscripts/lo_fi_text_3d.gd"

@export var variant_data: Array[Resource] = []

var _state_system: Node
var _narrative_manager: Node
var _current_tier: String = "mid"
var _current_tone: String = "neutral"

func _ready() -> void:
    super._ready()
    _state_system = get_node_or_null("/root/StateSystem")
    _narrative_manager = get_node_or_null("/root/NarrativeManager")

    if _state_system and _state_system.has_signal("state_changed"):
        _state_system.state_changed.connect(_on_state_changed)

    if _narrative_manager and _narrative_manager.has_signal("scene_text_changed"):
        _narrative_manager.scene_text_changed.connect(_on_tone_changed)

    if _state_system and _state_system.has_method("get_state"):
        _on_state_changed(_state_system.get_state())

func set_state_tier(tier: String) -> void:
    _current_tier = tier
    _apply_variant(_variant_index_for_tier(tier))

func set_tone(tone: String) -> void:
    _current_tone = tone
    _apply_tone_overrides(tone)

func set_text_variant(idx: int) -> void:
    idx = clampi(idx, 0, variant_data.size() - 1)
    _apply_variant(idx)

func _on_state_changed(state: Dictionary) -> void:
    var tier: String = _calculate_tier(state)
    set_state_tier(tier)

func _on_tone_changed(scene_id: String, tone: String) -> void:
    set_tone(tone)

func _variant_index_for_tier(tier: String) -> int:
    match tier:
        "low":  return 0
        "high": return 2
        _:      return 1

func _calculate_tier(state: Dictionary) -> String:
    var hope_val: float = state.get("hope", 5.0)
    if hope_val <= 3.0: return "low"
    elif hope_val >= 7.0: return "high"
    else: return "mid"

func _apply_variant(idx: int) -> void:
    if variant_data.is_empty() or idx >= variant_data.size():
        return
    var data: TextVariantData = variant_data[idx]
    if not data:
        return

    text = data.fragment_text if data.fragment_text != "" else data.text
    emissive_color = data.emissive_color
    emissive_strength = data.emissive_strength
    pixel_factor = data.pixel_factor
    color_bits = data.color_bits
    scanline_intensity = data.scanline_intensity

func _apply_tone_overrides(tone: String) -> void:
    var idx: int = _variant_index_for_tier(_current_tier)
    if variant_data.is_empty() or idx >= variant_data.size():
        return
    var data: TextVariantData = variant_data[idx]
    if not data:
        return
    emissive_color = data.emissive_color
    emissive_strength = data.emissive_strength

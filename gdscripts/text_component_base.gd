class_name TextComponentBase
extends "res://gdscripts/lo_fi_text_3d.gd"

# TextComponentBase — 5-state variant selection for environmental text (Issue #154)
# Expanded from 3-tier to 5-state selection.
# Maps state IDs 1-5 to variant indices 0-4.
# Supports fallback for arrays with fewer than 5 entries.
# Fade-transitions between variants when tone changes.

@export var variant_data: Array[Resource] = []

## Duration (seconds) for the text content fade transition between variants.
@export var transition_duration: float = 0.3

var _state_system: Node
var _narrative_manager: Node
var _current_tier: String = "mid"
var _current_tone: String = "neutral"
var _current_state_id: int = 3
var _active_tween: Tween = null


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


## Set state tier (maintained for backward compatibility — internally maps to state_id).
func set_state_tier(tier: String) -> void:
	_current_tier = tier
	_apply_variant(_variant_index_for_tier(tier))


## Set tone and apply corresponding variant (text + visual properties).
func set_tone(tone: String) -> void:
	_current_tone = tone
	if not _state_system or not _state_system.has_method("get_state"):
		_apply_variant_for_tone_name(tone)
		return
	var state: Dictionary = _state_system.get_state()
	var state_id: int = _hope_to_state_id(state.get("hope", 5.0))
	_on_state_changed(state)


## Set text variant by index (0-4).
## Falls back to nearest available index if array is smaller than 5.
func set_text_variant(idx: int) -> void:
	idx = clampi(idx, 0, max(0, variant_data.size() - 1))
	_apply_variant(idx)


## Convert hope value (0-10) to discrete state ID (1-5).
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


## Respond to state_changed signal from StateSystem.
## Selects the appropriate 5-state variant based on state_id.
func _on_state_changed(state: Dictionary) -> void:
	var state_id: int = _calculate_state_id(state)
	_current_state_id = state_id
	_apply_variant_for_state(state_id)


## Respond to scene_text_changed signal from NarrativeManager.
## Updates both text content and visual properties for the tone.
func _on_tone_changed(scene_id: String, tone: String) -> void:
	_current_tone = tone
	if _state_system and _state_system.has_method("get_state"):
		var state: Dictionary = _state_system.get_state()
		var state_id: int = _hope_to_state_id(state.get("hope", 5.0))
		_current_state_id = state_id
		_apply_variant_for_state(state_id)


## Calculate discrete state ID (1-5) from the state dictionary.
## Subclasses can override to use a different axis (e.g. will for LamppostText).
func _calculate_state_id(state: Dictionary) -> int:
	var hope_val: float = state.get("hope", 5.0)
	return _hope_to_state_id(hope_val)


## Map state ID (1-5) to variant array index (0-4).
## Falls back to nearest available index if variant_data has fewer entries.
func _variant_index_for_state_id(state_id: int) -> int:
	var idx: int = clampi(state_id - 1, 0, 4)
	var max_idx: int = max(0, variant_data.size() - 1)
	return clampi(idx, 0, max_idx)


## Legacy tier-to-index mapping (maintained for backward compatibility).
func _variant_index_for_tier(tier: String) -> int:
	match tier:
		"low":  return 0
		"high": return 2
		_:      return 1


## Legacy tier calculation (maintained for backward compatibility).
## Preferred: use _calculate_state_id() for 5-state.
func _calculate_tier(state: Dictionary) -> String:
	var hope_val: float = state.get("hope", 5.0)
	if hope_val <= 3.0: return "low"
	elif hope_val >= 7.0: return "high"
	else: return "mid"


## Apply the variant for the given state ID with fade transition.
## This is the main entry point for 5-state variant selection.
func _apply_variant_for_state(state_id: int) -> void:
	var idx: int = _variant_index_for_state_id(state_id)
	_current_state_id = state_id

	if variant_data.is_empty():
		return
	if idx >= variant_data.size():
		idx = variant_data.size() - 1

	var data: TextVariantData = variant_data[idx]
	if not data:
		return

	# Start fade transition
	_start_transition(data)


## Apply a variant by index without transition (direct assignment).
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


## Apply variant based on tone name (used when StateSystem is unavailable).
func _apply_variant_for_tone_name(tone: String) -> void:
	var idx: int = 2  # Default to neutral (index 2)
	match tone:
		"despair":
			idx = 0
		"low":
			idx = 1
		"neutral":
			idx = 2
		"buoyant":
			idx = 3
		"hope":
			idx = 4
	if variant_data.size() > 1:
		idx = clampi(idx, 0, variant_data.size() - 1)
	_apply_variant(idx)


## Apply tone overrides to visual properties (backward compatibility wrapper).
func _apply_tone_overrides(tone: String) -> void:
	var state_id: int = 3
	match tone:
		"despair", "fear", "cold", "tired", "backward":
			state_id = 1
		"low", "uneasy", "distant", "heavy", "hollow", "hesitant":
			state_id = 2
		"neutral", "waiting":
			state_id = 3
		"buoyant", "curious", "warm", "hopeful", "resolute", "forward":
			state_id = 4
		"hope", "defiant", "glowing", "determined", "transcendent":
			state_id = 5
	_apply_variant_for_state(state_id)


## Start a tween-based fade transition between old text and new text.
## Cancels any active tween before starting a new one.
func _start_transition(data: TextVariantData) -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_parallel(false)

	# Fade out
	_active_tween.tween_property(self, "modulate:a", 0.0, transition_duration * 0.4)

	# Swap text and visual properties mid-transition
	_active_tween.tween_callback(_apply_variant_data.bind(data))

	# Fade in
	_active_tween.tween_property(self, "modulate:a", 1.0, transition_duration * 0.6)


## Apply TextVariantData fields directly (called during tween mid-point).
func _apply_variant_data(data: TextVariantData) -> void:
	text = data.fragment_text if data.fragment_text != "" else data.text
	emissive_color = data.emissive_color
	emissive_strength = data.emissive_strength
	pixel_factor = data.pixel_factor
	color_bits = data.color_bits
	scanline_intensity = data.scanline_intensity

extends Node3D
class_name DialogueDisplay3D

# Preload for class_name scripts to ensure parse-time resolution
const _LoFiText3D = preload("res://gdscripts/lo_fi_text_3d.gd")

# --- Exported Parameters ---

@export var max_choices: int = 4
@export var choice_spacing: float = 0.25
@export var emissive_focus: float = 3.0
@export var emissive_dim: float = 0.0
@export var reveal_delay: float = 0.5
@export var fade_duration: float = 0.3

# --- Node References ---

@onready var speaker_label: Node = $SpeakerLabel
@onready var dialogue_text: Node = $DialogueText
@onready var choice_container: Node3D = $ChoiceContainer
@onready var continue_prompt: Node = $ContinuePrompt

# --- Internal State ---

var _choice_labels: Array = []
var _focused_index: int = 0
var _is_active: bool = false
var _current_choices: Array = []
var _tween: Tween = null


func _ready() -> void:
	_setup_choice_pool()
	hide_dialogue()
	# Apply responsive layout from UIConfig if available
	var ui_config := get_node_or_null("/root/UIConfig")
	if ui_config != null:
		if ui_config.has_method("recalculate"):
			ui_config.recalculate()


func _setup_choice_pool() -> void:
	_choice_labels.clear()
	for child in choice_container.get_children():
		if child is Label3D:
			_choice_labels.append(child)
	# Ensure we have exactly max_choices slots
	while _choice_labels.size() < max_choices:
		# In case scene doesn't have enough, create programmatically (shouldn't happen with proper scene)
		var label = _LoFiText3D.new()
		label.name = "Choice" + str(_choice_labels.size())
		label.position = Vector3(0, -0.3 - (_choice_labels.size() * choice_spacing), 0)
		label.pixel_factor = 0.3
		label.color_bits = 8
		label.emissive_color = Color(0, 0, 0, 0)
		label.emissive_strength = 0.0
		label.billboard = true
		choice_container.add_child(label)
		_choice_labels.append(label)


func show_dialogue() -> void:
	visible = true
	_is_active = true
	_focused_index = 0
	_current_choices.clear()
	# Show speaker and dialogue areas (choices shown later via on_choices_available)
	speaker_label.visible = true
	dialogue_text.visible = true
	continue_prompt.visible = false


func hide_dialogue() -> void:
	visible = false
	_is_active = false


func on_node_changed(node_id: String, speaker: String, text: String) -> void:
	if not is_inside_tree():
		return
	
	# Update speaker label
	if speaker_label.has_method("set_text") or "text" in speaker_label:
		speaker_label.text = speaker
	
	# Hemingway-truncate dialogue text
	var enforcer := preload("res://gdscripts/hemingway_enforcer.gd")
	var result := enforcer.truncate(text, "dialogue")

	if dialogue_text.has_method("set_text") or "text" in dialogue_text:
		dialogue_text.text = result["truncated_text"]

	if result["was_truncated"]:
		dialogue_text.set_meta("hemingway_truncated", true)
		dialogue_text.set_meta("hemingway_original", result["original_text"])

	# Apply responsive font scaling from UIConfig
	var ui_config := get_node_or_null("/root/UIConfig")
	if ui_config != null:
		var scale_factor: float = ui_config.get("auto_font_scale") if "auto_font_scale" in ui_config else 1.0
		# Apply font scale to LoFiText3D nodes (pixel_size property)
		if "pixel_size" in speaker_label:
			speaker_label.pixel_size = 0.02 * scale_factor
		if "pixel_size" in dialogue_text:
			dialogue_text.pixel_size = 0.02 * scale_factor

	# Hide choices and continue prompt until on_choices_available fires
	for label in _choice_labels:
		label.visible = false
	continue_prompt.visible = false


func on_choices_available(choices: Array) -> void:
	_current_choices = choices
	_focused_index = 0
	
	# Hide all choice labels first
	for label in _choice_labels:
		label.visible = false
	
	# If no choices, show continue prompt
	if choices.is_empty():
		continue_prompt.visible = true
		return
	
	# Wait for reveal_delay, then show choices
	var timer := get_tree().create_timer(reveal_delay, false)
	await timer.timeout
	
	# Guard against getting destroyed during delay
	if not is_inside_tree() or not _is_active:
		return
	
	show_choices_immediate(choices)


func show_choices_immediate(choices: Array) -> void:
	_current_choices = choices
	var count: int = mini(choices.size(), max_choices)

	# Apply responsive choice_spacing from UIConfig
	var spacing: float = choice_spacing
	var ui_config := get_node_or_null("/root/UIConfig")
	if ui_config != null:
		spacing = ui_config.get("choice_spacing") if "choice_spacing" in ui_config else choice_spacing

	for i in range(_choice_labels.size()):
		var label = _choice_labels[i]
		if i < count:
			label.visible = true
			label.emissive_strength = emissive_dim
			label.emissive_color = Color(0, 0, 0, 0)
			var choice_text: String = choices[i].get("text", "")
			label.text = "(%s) %s" % [_prefix_letter(i), choice_text]
			# Choice labels positioned ABOVE dialogue text => negative Y offset
			label.position.y = -(i + 1) * spacing - 0.1
		else:
			label.visible = false
	
	# Highlight first choice
	if count > 0:
		highlight_choice(0)


func on_dialogue_ended() -> void:
	_is_active = false
	
	# Cancel any existing tween
	if _tween != null and _tween.is_valid():
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(speaker_label, "emissive_strength", 0.0, fade_duration)
	_tween.tween_property(dialogue_text, "emissive_strength", 0.0, fade_duration)
	for label in _choice_labels:
		_tween.tween_property(label, "emissive_strength", 0.0, fade_duration)
	if continue_prompt != null:
		_tween.tween_property(continue_prompt, "emissive_strength", 0.0, fade_duration)
	
	# After tween, hide the entire dialogue
	await _tween.finished
	if is_inside_tree():
		hide_dialogue()


func navigate_up() -> void:
	if not _is_active or _current_choices.is_empty():
		return
	var count: int = mini(_current_choices.size(), max_choices)
	_focused_index = (_focused_index - 1 + count) % count
	highlight_choice(_focused_index)


func navigate_down() -> void:
	if not _is_active or _current_choices.is_empty():
		return
	var count: int = mini(_current_choices.size(), max_choices)
	_focused_index = (_focused_index + 1) % count
	highlight_choice(_focused_index)


func get_focused_choice_index() -> int:
	return _focused_index


func highlight_choice(index: int) -> void:
	var count: int = mini(_current_choices.size(), max_choices)
	
	for i in range(_choice_labels.size()):
		var label = _choice_labels[i]
		if i >= count:
			label.visible = false
			continue
		
		label.visible = true
		var choice_text: String = _current_choices[i].get("text", "")
		
		if i == index:
			label.emissive_strength = emissive_focus
			label.emissive_color = Color(1.0, 0.69, 0.0)  # #FFB000 amber
			label.text = "→ (%s) %s" % [_prefix_letter(i), choice_text]
		else:
			label.emissive_strength = emissive_dim
			label.emissive_color = Color(0, 0, 0, 0)
			label.text = "(%s) %s" % [_prefix_letter(i), choice_text]


static func _prefix_letter(index: int) -> String:
	match index:
		0:
			return "A"
		1:
			return "B"
		2:
			return "C"
		3:
			return "D"
		_:
			return String.chr(65 + index)

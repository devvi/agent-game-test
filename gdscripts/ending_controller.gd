extends Node
class_name EndingController

# EndingController — CanvasLayer overlay for ending sequences.
# Lives as a child of UnderpassRoot.
# Each ending is 4 dialogue nodes shown as full-screen text overlays.
#
# Ending mapping:
#   "ending_keep_walking" → res://dialogues/ending_keep_walking.json
#   "ending_turn_back"    → res://dialogues/ending_turn_back.json
#   "ending_stay"         → res://dialogues/ending_stay.json

signal ending_completed(ending_id: String)

const ENDING_FILES: Dictionary = {
	"ending_keep_walking": "res://dialogues/ending_keep_walking.json",
	"ending_turn_back": "res://dialogues/ending_turn_back.json",
	"ending_stay": "res://dialogues/ending_stay.json"
}

var _dialogue_runner: Node
var _fade_anim: AnimationPlayer
var _overlay: CanvasLayer
var _current_ending: String = ""
var _bg: ColorRect
var _label: Label


func _ready() -> void:
	_setup_overlay()
	_overlay.hide()


func _setup_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "EndingOverlay"
	_overlay.layer = 64  # Above dialogue (128 is fade curtain)
	add_child(_overlay)

	# Full-screen ColorRect for fades
	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.color = Color.BLACK
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.modulate = Color(0, 0, 0, 0)  # Start transparent
	_overlay.add_child(_bg)

	# Text label for ending monologue
	_label = Label.new()
	_label.name = "TextLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_font_size_override("font_size", 28)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.size_flags_horizontal = Control.SIZE_EXPAND
	_label.size_flags_vertical = Control.SIZE_EXPAND
	_label.modulate = Color(1, 1, 1, 0)  # Start invisible
	_overlay.add_child(_label)

	# AnimationPlayer for fades
	var anim := AnimationPlayer.new()
	anim.name = "FadeAnimation"
	_overlay.add_child(anim)

	# fade_in: background goes transparent, text appears
	var fade_in := Animation.new()
	fade_in.length = 2.0
	var bg_in := fade_in.add_track(Animation.TYPE_VALUE)
	fade_in.track_set_path(bg_in, "Background:modulate")
	fade_in.track_insert_key(bg_in, 0.0, Color(0, 0, 0, 1))
	fade_in.track_insert_key(bg_in, 1.0, Color(0, 0, 0, 0))
	var txt_in := fade_in.add_track(Animation.TYPE_VALUE)
	fade_in.track_set_path(txt_in, "TextLabel:modulate")
	fade_in.track_insert_key(txt_in, 0.0, Color(1, 1, 1, 0))
	fade_in.track_insert_key(txt_in, 1.0, Color(1, 1, 1, 1))
	anim.add_animation("fade_in", fade_in)

	# fade_out: text fades, background returns
	var fade_out := Animation.new()
	fade_out.length = 1.5
	var bg_out := fade_out.add_track(Animation.TYPE_VALUE)
	fade_out.track_set_path(bg_out, "Background:modulate")
	fade_out.track_insert_key(bg_out, 0.0, Color(0, 0, 0, 0))
	fade_out.track_insert_key(bg_out, 1.5, Color(0, 0, 0, 1))
	var txt_out := fade_out.add_track(Animation.TYPE_VALUE)
	fade_out.track_set_path(txt_out, "TextLabel:modulate")
	fade_out.track_insert_key(txt_out, 0.0, Color(1, 1, 1, 1))
	fade_out.track_insert_key(txt_out, 1.5, Color(1, 1, 1, 0))
	anim.add_animation("fade_out", fade_out)

	_fade_anim = anim


# Start an ending sequence.
# ending_id: one of "ending_keep_walking", "ending_turn_back", "ending_stay"
func start_ending(ending_id: String) -> void:
	if not ENDING_FILES.has(ending_id):
		push_error("EndingController: Unknown ending: ", ending_id)
		ending_completed.emit("unknown")
		return

	_current_ending = ending_id

	# Find dialogue runner (sibling under scene root's CanvasLayer)
	_dialogue_runner = get_node("../CanvasLayer/DialoguePanel")
	if not _dialogue_runner:
		push_error("EndingController: DialoguePanel not found")
		ending_completed.emit(ending_id)
		return

	# Show overlay and fade in
	_overlay.show()
	_fade_anim.play("fade_in")
	await _fade_anim.animation_finished

	# Connect dialogue signals
	if _dialogue_runner.has_signal("node_changed"):
		_dialogue_runner.node_changed.connect(_on_node_changed)
	if _dialogue_runner.has_signal("dialogue_ended"):
		_dialogue_runner.dialogue_ended.connect(_on_ending_dialogue_ended)

	# Start the ending dialogue
	var file_path: String = ENDING_FILES[ending_id]
	_dialogue_runner.start(file_path, ending_id)


func _on_node_changed(node_id: String, speaker: String, text: String) -> void:
	if _label:
		_label.text = text


func _on_ending_dialogue_ended() -> void:
	# Disconnect signals
	if _dialogue_runner and _dialogue_runner.is_connected("node_changed", _on_node_changed):
		_dialogue_runner.node_changed.disconnect(_on_node_changed)
	if _dialogue_runner and _dialogue_runner.is_connected("dialogue_ended", _on_ending_dialogue_ended):
		_dialogue_runner.dialogue_ended.disconnect(_on_ending_dialogue_ended)

	# Final fade to color
	if _current_ending == "ending_keep_walking":
		_fade_to_color(Color.WHITE)
	else:
		_fade_to_color(Color.BLACK)

	await _fade_anim.animation_finished if _fade_anim else create_tween().tween_callback(func(): pass)
	ending_completed.emit(_current_ending)


func _fade_to_color(target: Color) -> void:
	# Set background to target color, then fade from transparent to opaque
	_bg.color = target
	_bg.modulate = Color(0, 0, 0, 0)  # Start invisible (transparent over whatever)

	var tween := create_tween()
	tween.tween_property(_bg, "modulate", Color(1, 1, 1, 1), 2.0)
	await tween.finished

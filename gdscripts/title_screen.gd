extends CanvasLayer
class_name TitleScreen

# TitleScreen — CanvasLayer controller for the game's title screen
# Displays game title, subtitle, and pulsing "Press Space to Start" prompt.
# Pressing Space/Enter emits start_requested signal for scene transition.
# See: docs/DESIGN/147-title-screen-start-prompt.md

# --- Signals ---
signal start_requested(fade_duration: float)

# --- Exports ---
@export var title_string: String = "Urban Night Walker"
@export var subtitle_string: String = "都市夜行者"
@export var prompt_string: String = "Press Space to Start"
@export var fade_duration: float = 0.5

# --- Color Constants (Hopper Palette) ---
const TITLE_COLOR := Color("#FFB000")       # Warm amber
const SUBTITLE_COLOR := Color("#B8B8B8")    # Muted silver
const PROMPT_COLOR := Color("#888888")      # Dim grey
const BG_COLOR_TOP := Color("#050510")      # Very dark blue-black
const BG_COLOR_BOTTOM := Color("#1a1a2e")   # Dark night blue

# --- Font Resource ---
const PIXEL_FONT := preload("res://assets/fonts/pixel_font.tres")

# --- Node References ---
@onready var _background: ColorRect = $Background
@onready var _title_label: Label = $TitleLabel
@onready var _subtitle_label: Label = $SubtitleLabel
@onready var _prompt_label: Label = $StartPrompt

# --- Lifecycle ---
func _ready() -> void:
	_configure_labels()
	_configure_background()
	_start_pulse_tween()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("dialogue_select"):
		emit_signal("start_requested", fade_duration)
		set_process_input(false)  # Prevent double-fire during fade
		get_viewport().set_input_as_handled()

# --- Configuration ---
func _configure_labels() -> void:
	_title_label.text = title_string
	_title_label.add_theme_color_override("font_color", TITLE_COLOR)
	_title_label.add_theme_font_override("font", PIXEL_FONT)
	_title_label.add_theme_font_size_override("font_size", 48)

	_subtitle_label.text = subtitle_string
	_subtitle_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	_subtitle_label.add_theme_font_override("font", PIXEL_FONT)
	_subtitle_label.add_theme_font_size_override("font_size", 32)

	_prompt_label.text = prompt_string
	_prompt_label.add_theme_color_override("font_color", PROMPT_COLOR)
	_prompt_label.add_theme_font_override("font", PIXEL_FONT)
	_prompt_label.add_theme_font_size_override("font_size", 18)

	# Apply UIConfig font scaling if available
	var ui_config := get_node_or_null("/root/UIConfig")
	if ui_config != null and ui_config.has_method("recalculate"):
		ui_config.recalculate()

func _configure_background() -> void:
	var gradient := GradientTexture2D.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([BG_COLOR_TOP, BG_COLOR_BOTTOM])
	gradient.gradient = g
	gradient.fill = GradientTexture2D.FILL_LINEAR
	gradient.fill_from = Vector2(0.5, 0.0)
	gradient.fill_to = Vector2(0.5, 1.0)
	_background.texture = gradient

# --- Pulsing Animation ---
func _start_pulse_tween() -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(_prompt_label, "modulate:a", 0.4, 1.0)
	tween.tween_property(_prompt_label, "modulate:a", 1.0, 1.0)

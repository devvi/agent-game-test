@tool
extends CanvasLayer

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var prompt_label: Label = $VBoxContainer/PromptLabel
@onready var version_label: Label = $VBoxContainer/VersionLabel
@onready var bg_rect: ColorRect = $BackgroundRect
@onready var rain_timer: Timer = $RainTimer

var _alpha: float = 0.0
var _prompt_visible: bool = true

func _ready() -> void:
	# Initial state: hidden, then fade in
	bg_rect.color.a = 1.0
	title_label.modulate.a = 0.0
	_modulate_all(0.0)
	
	# Start fade in
	var tween = create_tween()
	tween.tween_method(_set_alpha, 0.0, 1.0, 1.5)
	tween.tween_callback(_start_prompt_blink)
	
	# Set version
	version_label.text = "v0.2.0 — Literary Micro CRPG"

func _set_alpha(a: float) -> void:
	title_label.modulate.a = a
	prompt_label.modulate.a = a
	version_label.modulate.a = a

func _modulate_all(a: float) -> void:
	title_label.modulate.a = a
	prompt_label.modulate.a = a
	version_label.modulate.a = a

func _start_prompt_blink() -> void:
	var blink_tween = create_tween().set_loops()
	blink_tween.tween_property(prompt_label, "modulate:a", 0.3, 0.8)
	blink_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.8)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		set_process_input(false)
		var tween = create_tween()
		tween.tween_method(_set_alpha, 1.0, 0.0, 1.0)
		tween.tween_callback(_start_game)

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

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
	modulate = Color(1, 1, 1, 0)
	_prompt_visible = true
	
	# Start fade in
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 1.5)
	tween.tween_callback(_start_prompt_blink)
	
	# Start rain timer for pulsing effect
	rain_timer.timeout.connect(_on_rain_timer)
	rain_timer.start(0.1)
	
	# Set version
	version_label.text = "v0.1.0 — Literary Micro CRPG"

func _start_prompt_blink() -> void:
	var blink_tween = create_tween().set_loops()
	blink_tween.tween_property(prompt_label, "modulate", Color(1, 1, 1, 0.3), 0.8)
	blink_tween.tween_property(prompt_label, "modulate", Color(1, 1, 1, 1), 0.8)

func _on_rain_timer() -> void:
	# Subtle rain effect on background
	if bg_rect.material and bg_rect.material is ShaderMaterial:
		var offset = bg_rect.material.get_shader_parameter("rain_offset") or Vector2(0, 0)
		offset.y += 0.01
		if offset.y > 1.0:
			offset.y = 0.0
		bg_rect.material.set_shader_parameter("rain_offset", offset)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		# Start fade out and transition to main game
		var tween = create_tween()
		tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 1.0)
		tween.tween_callback(_start_game)
		set_process_input(false)

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

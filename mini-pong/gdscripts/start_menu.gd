extends CanvasLayer
## StartMenu — neon title screen with pulsing glow and SPACE-to-start prompt.
## Parent Issue: #292

# ── Exported ──
@export var title_pulse_min: float = 0.6       # Minimum alpha during pulse
@export var title_pulse_max: float = 1.0       # Maximum alpha during pulse
@export var title_pulse_duration: float = 1.5  # Seconds for one full pulse cycle
@export var prompt_blink_period: float = 0.8   # Seconds for one full blink cycle

# ── Node References ──
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var prompt_label: Label = $CenterContainer/VBoxContainer/PromptLabel

# ── State ──
var _title_tween: Tween = null
var _prompt_tween: Tween = null
var _transitioning: bool = false


# ── Lifecycle ──
func _ready() -> void:
	# Guard: run only if nodes exist
	if not title_label or not prompt_label:
		return

	# Start glow/pulse animations (headless-safe)
	if is_inside_tree() and get_tree():
		_start_title_pulse()
		_start_prompt_blink()

	visible = true


func _input(event: InputEvent) -> void:
	if not visible or _transitioning:
		return
	if event.is_action_pressed("ui_accept"):  # SPACE key
		_on_start_pressed()


# ── Public ──
func show_menu() -> void:
	"""Called by state machine (#294) to re-show the start screen."""
	visible = true
	_transitioning = false
	if is_inside_tree() and get_tree():
		_start_title_pulse()
		_start_prompt_blink()


func hide_menu() -> void:
	"""Cleanup animations and hide."""
	_kill_tweens()
	visible = false


# ── Animation ──
func _start_title_pulse() -> void:
	_kill_tween(_title_tween)
	_title_tween = create_tween()
	_title_tween.set_loops()  # infinite
	_title_tween.tween_property(title_label, "modulate:a", title_pulse_min, title_pulse_duration * 0.5)
	_title_tween.tween_property(title_label, "modulate:a", title_pulse_max, title_pulse_duration * 0.5)


func _start_prompt_blink() -> void:
	_kill_tween(_prompt_tween)
	_prompt_tween = create_tween()
	_prompt_tween.set_loops()
	_prompt_tween.tween_property(prompt_label, "modulate:a", 0.0, prompt_blink_period * 0.5)
	_prompt_tween.tween_property(prompt_label, "modulate:a", 1.0, prompt_blink_period * 0.5)


# ── Internal ──
func _on_start_pressed() -> void:
	_transitioning = true
	_kill_tweens()
	visible = false

	# Show HUD layer
	var hud := _get_sibling("GameHUD")
	if hud:
		hud.visible = true

	# Trigger game start via GameManager
	GameManager.reset_match()


func _get_sibling(node_name: String) -> CanvasLayer:
	"""Find a sibling CanvasLayer by name. Returns null if not found."""
	var parent := get_parent()
	if not parent:
		return null
	return parent.get_node_or_null(node_name)


func _kill_tween(tween: Tween) -> void:
	if tween and is_instance_valid(tween):
		tween.kill()


func _kill_tweens() -> void:
	_kill_tween(_title_tween)
	_kill_tween(_prompt_tween)
	_title_tween = null
	_prompt_tween = null

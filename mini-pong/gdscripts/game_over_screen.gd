extends CanvasLayer
## GameOverScreen — winner announcement with pulse glow and SPACE-to-restart prompt.
## Parent Issue: #292

# ── Constants ──
const COLOR_PLAYER: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const COLOR_AI: Color     = Color(1.0, 0.2, 0.33, 1.0)      # #ff3355
const TEXT_PLAYER_WIN: String = "YOU WIN!"
const TEXT_AI_WIN: String     = "AI WINS!"

# ── Exported ──
@export var winner_pulse_duration: float = 1.0   # Seconds for one pulse cycle
@export var prompt_blink_period: float = 0.8      # Seconds for one blink cycle

# ── Node References ──
@onready var winner_label: Label = $CenterContainer/VBoxContainer/WinnerLabel
@onready var restart_label: Label = $CenterContainer/VBoxContainer/RestartPromptLabel

# ── State ──
var _winner_tween: Tween = null
var _prompt_tween: Tween = null
var _transitioning: bool = false


# ── Lifecycle ──
func _ready() -> void:
	# Guard: skip if nodes missing
	if not winner_label or not restart_label:
		return

	# Connect to GameManager.match_over signal
	if is_instance_valid(GameManager):
		if GameManager.has_signal("match_over"):
			GameManager.match_over.connect(_on_match_over)

	visible = false


func _input(event: InputEvent) -> void:
	if not visible or _transitioning:
		return
	if event.is_action_pressed("ui_accept"):  # SPACE key
		_on_restart_pressed()


# ── Signal Handlers ──
func _on_match_over(winner: String) -> void:
	"""Called when GameManager.match_over fires. Shows winner text and animations."""
	if not winner_label or not restart_label:
		return

	# Set winner text and color
	match winner:
		"player":
			winner_label.text = TEXT_PLAYER_WIN
			winner_label.modulate = COLOR_PLAYER
		"ai":
			winner_label.text = TEXT_AI_WIN
			winner_label.modulate = COLOR_AI
		_:
			return

	# Hide HUD
	var hud := _get_sibling("GameHUD")
	if hud:
		hud.visible = false

	# Show this screen
	visible = true
	_transitioning = false

	# Start animations (headless-safe)
	if is_inside_tree() and get_tree():
		_start_winner_pulse()
		_start_prompt_blink()


# ── Animation ──
func _start_winner_pulse() -> void:
	_kill_tween(_winner_tween)
	_winner_tween = create_tween()
	_winner_tween.set_loops()
	_winner_tween.tween_property(winner_label, "modulate:a", 0.4, winner_pulse_duration * 0.5)
	_winner_tween.tween_property(winner_label, "modulate:a", 1.0, winner_pulse_duration * 0.5)


func _start_prompt_blink() -> void:
	_kill_tween(_prompt_tween)
	_prompt_tween = create_tween()
	_prompt_tween.set_loops()
	_prompt_tween.tween_property(restart_label, "modulate:a", 0.0, prompt_blink_period * 0.5)
	_prompt_tween.tween_property(restart_label, "modulate:a", 1.0, prompt_blink_period * 0.5)


# ── Internal ──
func _on_restart_pressed() -> void:
	_transitioning = true
	_kill_tweens()
	visible = false

	# Return to start menu
	var menu := _get_sibling("StartMenu")
	if menu and menu.has_method("show_menu"):
		menu.show_menu()

	# Reset match state
	GameManager.reset_match()


func _get_sibling(node_name: String) -> CanvasLayer:
	var parent := get_parent()
	if not parent:
		return null
	return parent.get_node_or_null(node_name)


func _kill_tween(tween: Tween) -> void:
	if tween and is_instance_valid(tween):
		tween.kill()


func _kill_tweens() -> void:
	_kill_tween(_winner_tween)
	_kill_tween(_prompt_tween)
	_winner_tween = null
	_prompt_tween = null

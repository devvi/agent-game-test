extends CanvasLayer
## GameHUD — top-center score display driven by GameManager.score_changed signal.
## Parent Issue: #292

# ── Node References ──
@onready var player_label: Label = $MarginContainer/HBoxContainer/PlayerScoreLabel
@onready var ai_label: Label = $MarginContainer/HBoxContainer/AIScoreLabel


# ── Lifecycle ──
func _ready() -> void:
	# Guard: skip if nodes missing
	if not player_label or not ai_label:
		return

	# Connect to GameManager signal
	if is_instance_valid(GameManager):
		# Check signal exists before connecting
		if GameManager.has_signal("score_changed"):
			GameManager.score_changed.connect(_on_score_changed)

	# Set initial values from GameManager state
	_on_score_changed(GameManager.player_score, GameManager.ai_score)

	visible = false  # Hidden until StartMenu triggers show


# ── Signal Handlers ──
func _on_score_changed(player_score: int, ai_score: int) -> void:
	"""Update label text when GameManager.score_changed fires."""
	if player_label:
		player_label.text = "Player: " + str(player_score)
	if ai_label:
		ai_label.text = "AI: " + str(ai_score)

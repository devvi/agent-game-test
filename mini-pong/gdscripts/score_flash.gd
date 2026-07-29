extends Node

## Score flash controller for mini-pong neon visual system.
## Manages a ColorRect overlay that flashes on score (0.2s fade out).

@onready var flash_rect: ColorRect = $ScoreFlashRect

var _flash_tween: Tween = null
var _is_flashing: bool = false


func _ready() -> void:
	if not flash_rect:
		push_warning("score_flash.gd: ColorRect not found, flash disabled")
		return
	flash_rect.modulate.a = 0.0
	flash_rect.hide()

	# Connect to scoring signal (to be wired by future scoring system issue)
	# var score_system = get_node("../ScoreSystem")
	# score_system.score_changed.connect(_on_score_changed)


## Trigger a flash. Caller passes the scoring side's color.
func flash(color: Color) -> void:
	if not flash_rect:
		return

	# New flash overrides old flash (prevents overlapping)
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	flash_rect.color = color
	flash_rect.modulate.a = 1.0
	flash_rect.show()

	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_rect, "modulate:a", 0.0, 0.2)
	_flash_tween.tween_callback(func(): flash_rect.hide())


## Signal callback (to be connected by future scoring issue)
func _on_score_changed(scoring_side: String) -> void:
	match scoring_side:
		"player":
			flash(Color(0.29, 0.56, 0.85, 0.3))  # #4a90d9 semi-transparent
		"ai":
			flash(Color(1.0, 0.2, 0.33, 0.3))    # #ff3355 semi-transparent

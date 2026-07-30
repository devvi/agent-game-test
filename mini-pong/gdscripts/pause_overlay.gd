extends CanvasLayer
## PauseOverlay — semi-transparent mask + "暂停" label, shown during PAUSED state.
## Follows the CanvasLayer + ColorRect + Label pattern from StartMenu/GameOverScreen (#292).
##
## Design: docs/DESIGN/296-pause-and-sound.md §2.1
## Parent Issue: #296

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label


func _ready() -> void:
	hide()


func show_overlay() -> void:
	visible = true


func hide_overlay() -> void:
	visible = false

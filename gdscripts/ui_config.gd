extends Node

# UIConfig — Singleton (autoload) for responsive layout parameters
# Both 2D and 3D UI components query this for consistent scaling.
# See: docs/DESIGN/53-ui-system.md

const BASE_RESOLUTION := Vector2(1920, 1080)
const MIN_FONT_SCALE := 0.5
const MAX_FONT_SCALE := 2.0
const BASE_CHOICE_SPACING := 0.25
const MIN_CHOICE_SPACING := 0.12
const MAX_CHOICE_SPACING := 0.5

var auto_font_scale: float = 1.0
var choice_spacing: float = 0.25
var status_bar_height: float = 4.0
var last_viewport_size: Vector2 = Vector2(1920, 1080)


func _ready() -> void:
	if is_instance_valid(get_viewport()):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	recalculate()


func recalculate() -> void:
	var viewport := get_viewport()
	if not is_instance_valid(viewport):
		return
	var size := viewport.get_visible_rect().size
	if size == Vector2.ZERO:
		return
	last_viewport_size = size
	var ratio := size.y / BASE_RESOLUTION.y
	auto_font_scale = clampf(ratio, MIN_FONT_SCALE, MAX_FONT_SCALE)
	choice_spacing = clampf(BASE_CHOICE_SPACING * auto_font_scale, MIN_CHOICE_SPACING, MAX_CHOICE_SPACING)
	status_bar_height = 4.0 * auto_font_scale


func _on_viewport_size_changed() -> void:
	recalculate()

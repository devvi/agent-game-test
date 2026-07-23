extends CanvasLayer
class_name StatusBar

# StatusBar — CanvasLayer controller for the hope/despair status bar
# A thin Hopper-style bar at the screen bottom showing hope/despair state.
# See: docs/DESIGN/53-ui-system.md

# --- Exports ---
@export var bar_width_ratio: float = 0.6
@export var bar_height_px: float = 4.0
@export var tween_duration: float = 0.3
@export var margin_bottom: float = 8.0  # pixels from screen bottom edge

# --- Color Constants ---
const HOPE_COLOR := Color("FFB000")       # Amber
const DESPAIR_COLOR := Color("2A2A4A")     # Dark blue
const BG_COLOR := Color("1a1a2e", 0.6)     # Semi-transparent dark
const INDICATOR_COLOR := Color("FFD700")   # Bright gold for indicator dot
const NEUTRAL_COLOR := Color("808080")     # Grey centre point

# --- Node References (@onready) ---
@onready var _bg: ColorRect = $Background
@onready var _bar_fill: ColorRect = $FillBar
@onready var _indicator: ColorRect = $Indicator
@onready var _hope_label: Label = $HopeLabel
@onready var _despair_label: Label = $DespairLabel
@onready var _tween: Tween

# --- Internal State ---
var _current_ratio: float = 0.5  # 0.0 = max despair, 1.0 = max hope
var _bar_max_width: float = 0.0


# --- Lifecycle ---
func _ready() -> void:
	_tween = Tween.new()
	add_child(_tween)
	_update_layout()
	_update_bar_immediate(0.5)  # Start neutral


func _on_state_changed(state: Dictionary) -> void:
	# Expects state.hope_despair: float in range -10..+10
	var hope_despair: float = state.get("hope_despair", 0.0)
	# Map -10..+10 → 0.0..1.0
	var ratio: float = (hope_despair + 10.0) / 20.0
	ratio = clampf(ratio, 0.0, 1.0)
	_update_bar(ratio)


func _update_bar(target_ratio: float) -> void:
	# Kill any active tween for compaction (rapid state changes)
	if _tween.is_running():
		_tween.kill()

	# Recalculate bar width in case viewport changed
	_update_layout()

	# Interpolate fill bar width
	var target_width: float = target_ratio * _bar_max_width
	var indicator_target_x: float = target_width - _indicator.size.x / 2.0

	_tween.tween_property(_bar_fill, "size:x", target_width, tween_duration) \
		 .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(_indicator, "position:x",
		indicator_target_x, tween_duration) \
		 .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	# Update fill bar to gradient colour based on ratio
	var fill_color: Color = DESPAIR_COLOR.lerp(HOPE_COLOR, target_ratio)
	_bar_fill.color = fill_color

	_current_ratio = target_ratio


func _update_bar_immediate(ratio: float) -> void:
	# Set bar state instantly without animation (used in _ready)
	if _tween.is_running():
		_tween.kill()

	_update_layout()

	var target_width: float = ratio * _bar_max_width
	_bar_fill.size.x = target_width
	_indicator.position.x = target_width - _indicator.size.x / 2.0
	_bar_fill.color = DESPAIR_COLOR.lerp(HOPE_COLOR, ratio)
	_current_ratio = ratio


func _update_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var bar_width := viewport_size.x * bar_width_ratio
	_bar_max_width = bar_width

	# UIConfig scaling (if available)
	var ui_config := get_node_or_null("/root/UIConfig")
	var scale_factor: float = 1.0
	if ui_config != null:
		scale_factor = ui_config.get("auto_font_scale", 1.0)

	var bar_height := bar_height_px * scale_factor
	var bar_x := (viewport_size.x - bar_width) / 2.0
	var bar_y := viewport_size.y - bar_height - margin_bottom

	_bg.position = Vector2(bar_x, bar_y)
	_bg.size = Vector2(bar_width, bar_height)

	_bar_fill.position = Vector2(bar_x, bar_y)
	_bar_fill.size = Vector2(_current_ratio * bar_width, bar_height)

	_indicator.size = Vector2(bar_height * 1.5, bar_height * 1.5)
	_indicator.position = Vector2(
		bar_x + (_current_ratio * bar_width) - _indicator.size.x / 2.0,
		bar_y - (_indicator.size.y - bar_height) / 2.0
	)

	_hope_label.position = Vector2(bar_x, bar_y - _hope_label.size.y - 2)
	_despair_label.position = Vector2(
		bar_x + bar_width - _despair_label.size.x,
		bar_y - _despair_label.size.y - 2
	)

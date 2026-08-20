extends CanvasLayer
## BloodVignette — 血色低血 vignette（#582, PRD §4.4 方案 A；AC4: 视觉 alpha 0→0.35）。
## 契约: #575 玩家实体未来 emit low_health → controller.set_low_health() 接入，
## 发射端归 #575，本脚本只建消费端。

const C = preload("res://gdscripts/constants.gd")

@export var alpha_max: float = C.BLOOD_VIGNETTE_ALPHA_MAX
@export var fade_seconds: float = C.BLOOD_VIGNETTE_FADE_SECONDS

var _enabled: bool = false
var _tween: Tween = null

@onready var _rect: ColorRect = $BloodRect


func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0 if enabled else 0.0, fade_seconds)


func set_low_health(enabled: bool) -> void:
	set_enabled(enabled)


func debug_trigger_low_health() -> void:
	set_low_health(true)


func debug_clear_low_health() -> void:
	set_low_health(false)


func get_visual_alpha() -> float:
	return _rect.modulate.a * alpha_max

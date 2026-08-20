extends Node
class_name FlashEffect
## FlashEffect — 白闪双通道（#579，AC2/AC5）。
## 归属: docs/DESIGN/579-combat-feedback-system.md §2.5
## 职责:
##   - 实体白闪通道: flash_entity(entity, alpha, ms) —— 同步冲高 modulate（Color(5,5,5)）
##     → 保持 duration_ms → 渐回 WHITE（高倍乘算 = 深色火柴人 #2b2b2b 也冲白）
##   - 全屏淡闪通道: flash_screen(alpha, ms) —— CanvasLayer(layer=0) → ColorRect 全屏
##     Color(1,1,1,alpha) 淡入 → duration_ms 后淡出；层序低于 UI/氛围层，不遮 HUD
## 红线:
##   - 全屏淡白闪仅 A- 级（架势崩解）路径可达（矩阵唯一调用点，AC5/AC6 页游感红线）
##   - 失效实体防护: flash_entity 首行 is_instance_valid 检查（边界 7）
## 全部 # DRAFT 候补值（FEEDBACK_ENTITY_FLASH_FACTOR / FEEDBACK_FLASH），定稿归 #584/用户。

const C = preload("res://gdscripts/constants.gd")

var _entity_tween: Tween = null
var _screen_tween: Tween = null
var _canvas_layer: CanvasLayer = null
var _color_rect: ColorRect = null


func _ready() -> void:
	_build_screen_layer()


func _build_screen_layer() -> void:
	## 代码创建全屏淡闪通道（CanvasLayer layer=0 → ColorRect 全屏 + 鼠标穿透）。
	## _ready 未跑（flash_screen 直接调用）时惰性构建。
	if _canvas_layer == null:
		var cl: CanvasLayer = CanvasLayer.new()
		cl.name = "CanvasLayer"
		cl.layer = 0
		add_child(cl)
		_canvas_layer = cl
	if _color_rect == null:
		var rect: ColorRect = ColorRect.new()
		rect.name = "ColorRect"
		rect.color = Color(1, 1, 1, 0)
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas_layer.add_child(rect)
		_color_rect = rect


func flash_entity(entity, alpha: float, duration_ms: int) -> void:
	## 实体白闪: 同步冲高 modulate → 保持 duration_ms → 0.2s 渐回 WHITE。
	## 失效实体直接跳过（边界 7，无报错）；不动动画层，只动 modulate 外层。
	## 首参不类型化: 已 free 的实体在类型化 Node 参数边界即报错（GDScript 调用前校验），
	##   无法进入函数体做 is_instance_valid 防护——边界 7 要求 is_instance_valid 首行拦截。
	if not is_instance_valid(entity):
		return
	var factor: float = float(C.FEEDBACK_ENTITY_FLASH_FACTOR)
	entity.modulate = Color(factor, factor, factor)
	_entity_tween = create_tween()
	_entity_tween.tween_interval(duration_ms / 1000.0)
	_entity_tween.tween_property(entity, "modulate", Color.WHITE, 0.2)


func flash_screen(alpha: float, duration_ms: int) -> void:
	## 全屏淡闪（仅 A- 级路径可达）: 同步置 alpha → 保持 duration_ms → 0.25s 淡出归零。
	_build_screen_layer()
	_color_rect.color.a = alpha
	_screen_tween = create_tween()
	_screen_tween.tween_interval(duration_ms / 1000.0)
	_screen_tween.tween_property(_color_rect, "color:a", 0.0, 0.25)

extends Node
class_name ExecutionFade
## ExecutionFade — 敌人淡出组件（#580 处决系统）。
## 归属: docs/DESIGN/580-execution-system.md §2.2
## 职责: 处决后目标 modulate alpha 1→0 淡出 → fade_completed → queue_free（如墨迹消散）。
## 墙钟驱动: _process(delta) 只做转发，进度全部由 Time.get_ticks_msec() 差值计算——
##   时间缩放不影响墙钟，处决慢动作 0.05x 期间淡出照常完成，不卡顿（PRD §5.2-6）。

signal fade_completed(entity: Node)

var _target: Node = null          # 淡出目标（CanvasItem，modulate 可写）
var _start_ms: int = -1           # 起始墙钟（Time.get_ticks_msec()，首次 _tick 惰性记录）
var _bound: bool = false

const C = preload("res://gdscripts/constants.gd")
const DebugCanvasScript = preload("res://gdscripts/debug_canvas.gd")


func _read(param_name: String, default_value: Variant) -> Variant:
	## 参数读值: DebugCanvas 热更新优先，release 回落 constants（#584 约定）。
	return DebugCanvasScript.get_value(param_name, default_value)


func bind(entity) -> void:
	## 幂等重绑: 新目标重置计时（_start_ms = -1，下一 _tick 惰性记录）。
	## 目标必须可写 modulate（Node2D/Control），否则 push_warning + 不绑定。
	_target = entity
	_start_ms = -1
	if entity == null or not is_instance_valid(entity):
		_bound = false
		return
	if not ("modulate" in entity):
		push_warning("ExecutionFade: target has no modulate")
		_bound = false
		return
	_bound = true


func _process(_delta: float) -> void:
	## 墙钟驱动入口（时间缩放不影响墙钟，慢动作不卡淡出）。
	_tick(Time.get_ticks_msec())


func _tick(now_ms: int) -> void:
	## 核心推进（测试直接注入 now_ms，headless 确定性——对齐 TimeScaleStack.tick 模式）。
	if not _bound:
		return
	if not is_instance_valid(_target):     # 目标已释放（竞态）→ 解绑静默退出
		_bound = false
		return
	if _start_ms < 0:
		_start_ms = now_ms
		_target.modulate.a = 1.0
	var elapsed: float = float(now_ms - _start_ms) / 1000.0
	var ratio: float = elapsed / float(_read("EXECUTE_FADE_SECONDS", C.EXECUTE_FADE_SECONDS))
	if ratio >= 1.0:
		_target.modulate.a = 0.0
		var done = _target
		_bound = false
		emit_signal("fade_completed", done)
		done.queue_free()                  # 如墨迹消散（issue body 画面路径）
		return
	_target.modulate.a = clampf(1.0 - ratio, 0.0, 1.0)

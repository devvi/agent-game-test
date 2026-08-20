extends RefCounted
class_name TimeScaleStack
## TimeScaleStack — 时间缩放栈（#579 打击反馈，AC4 核心）。
## 归属: docs/DESIGN/579-combat-feedback-system.md §2.3
## 职责: Engine.time_scale 唯一写入口 —— push(scale, duration_ms) / pop() / tick(now_ms) 墙钟兜底。
## 语义:
##   - D1 min 语义: 有效 time_scale = 栈内最小 scale（最慢层主导）——hit-stop 0.05 期间
##     慢动作 0.3 push 不稀释顿帧；hit-stop pop 后 0.3 继续，逐层恢复 1.0。
##   - 墙钟兜底（AC4 机械保证）: 每层记录 deadline_ms = push 时墙钟 + duration_ms；
##     tick(now_ms) 到期强制移除（墙钟不受 time_scale 影响），漏 pop 也不会卡死。
##   - hit-stop 用 0.05 而非 0（0 冻结引擎处理 → 墙钟兜底失效红线，PRD §8.4-3）。
##   - 边界 1: 栈深超限（FEEDBACK_TIME_MAX_STACK=3）→ push_warning + 丢弃新层保旧恢复。
## 全部 # DRAFT 候补值，定稿归 #584/用户。

const C = preload("res://gdscripts/constants.gd")

var _layers: Array[Dictionary] = []
var _max_stack: int = int(C.FEEDBACK_TIME_MAX_STACK)


func push(scale: float, duration_ms: int) -> void:
	## 入栈: 栈深已满 → push_warning + 丢弃（保旧恢复）；否则记录墙钟 deadline + 立即生效。
	if _layers.size() >= _max_stack:
		push_warning("TimeScaleStack: max stack depth %d reached, push dropped (scale=%s)" % [_max_stack, str(scale)])
		return
	_layers.append({
		"scale": scale,
		"deadline_ms": Time.get_ticks_msec() + duration_ms,
	})
	_apply()


func pop() -> void:
	## 出栈: 空栈 no-op；移除最早到期层（hit-stop 先 pop、慢动作层保留——D1 说明「hit-stop pop 后 0.3」，
	##   非 LIFO 栈顶）→ 重新生效。
	if _layers.is_empty():
		return
	var earliest: int = 0
	for i in range(1, _layers.size()):
		if int(_layers[i]["deadline_ms"]) < int(_layers[earliest]["deadline_ms"]):
			earliest = i
	_layers.remove_at(earliest)
	_apply()


func tick(now_ms: int) -> void:
	## 墙钟兜底（AC4）: 从栈底起移除 deadline 已过的层（到期强制 pop）；有变化 → 重新生效。
	var changed: bool = false
	var i: int = 0
	while i < _layers.size():
		if int(_layers[i]["deadline_ms"]) <= now_ms:
			_layers.remove_at(i)
			changed = true
		else:
			i += 1
	if changed:
		_apply()


func _apply() -> void:
	## D1 min 语义: Engine.time_scale = 栈内最小 scale；空栈 → 1.0。
	if _layers.is_empty():
		Engine.time_scale = 1.0
		return
	var min_scale: float = 1.0
	var first: bool = true
	for layer in _layers:
		var s: float = float(layer["scale"])
		if first or s < min_scale:
			min_scale = s
			first = false
	Engine.time_scale = min_scale

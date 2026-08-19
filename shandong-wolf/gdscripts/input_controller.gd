extends Node
## InputController — shandong-wolf 输入意图层（#573）。
## 注册: project.godot [autoload] InputController="*res://gdscripts/input_controller.gd"（Game 之后）
## 职责: 读 Input Map（game_*）→ 边沿检测 → 意图事件信号；时间戳缓冲队列（无吞噬）；
##       guard_pressed 仅含时间戳（弹反判定归 #6）；PARRY_WINDOW_FRAMES 只读不判定。
## 红线: 不接触战斗逻辑/动画/场景状态；消费方 #3/#6/#575/#4 独立监听。

signal attack_pressed
signal heavy_attack_pressed
signal guard_pressed(timestamp_ms: int)
signal guard_held
signal dash_pressed
signal jump_pressed
signal interact_pressed
signal revive_pressed

const C = preload("res://gdscripts/constants.gd")

const EDGE_ACTIONS: Array[StringName] = [
	&"game_light_attack", &"game_heavy_attack", &"game_guard",
	&"game_dash", &"game_jump", &"game_interact", &"game_revive",
]
const ALL_ACTIONS: Array[StringName] = [
	&"game_move_left", &"game_move_right", &"game_light_attack", &"game_heavy_attack",
	&"game_guard", &"game_dash", &"game_jump", &"game_interact", &"game_revive",
]

var _was_pressed: Dictionary = {}              # action:StringName -> bool
var _buffer: Array[Dictionary] = []            # [{action: StringName, timestamp_ms: int}] FIFO
var _dash_press_time_ms: int = -1
var _sprinting: bool = false


func _ready() -> void:
	_validate_input_map()


func _process(_delta: float) -> void:
	_clear_expired()
	_poll_edges()
	_update_dash_hold()


func get_move_axis() -> float:
	return Input.get_axis("game_move_left", "game_move_right")


func _safe_window_ms() -> float:
	return maxf(float(C.INPUT_BUFFER_WINDOW_MS), 1.0)


func _clear_expired() -> void:
	var now: int = Time.get_ticks_msec()
	_buffer = _buffer.filter(func(e: Dictionary) -> bool:
		return now - int(e["timestamp_ms"]) <= int(_safe_window_ms()))


func _push_buffer(action: StringName) -> void:
	if _buffer.size() >= int(C.INPUT_BUFFER_MAX):
		return  # 队列满: 拒新不丢旧
	_buffer.append({"action": action, "timestamp_ms": Time.get_ticks_msec()})


func _poll_edges() -> void:
	for action in EDGE_ACTIONS:
		var now_pressed: bool = Input.is_action_pressed(action)
		var was_pressed: bool = _was_pressed.get(action, false)
		if now_pressed and not was_pressed:
			_push_buffer(action)
			match action:
				&"game_guard":
					emit_signal("guard_pressed", Time.get_ticks_msec())  # 仅时间戳，弹反判定归 #6
				&"game_dash":
					_dash_press_time_ms = Time.get_ticks_msec()
				&"game_light_attack":
					emit_signal("attack_pressed")
				&"game_heavy_attack":
					emit_signal("heavy_attack_pressed")
				&"game_jump":
					emit_signal("jump_pressed")
				&"game_interact":
					emit_signal("interact_pressed")
				&"game_revive":
					emit_signal("revive_pressed")
		if now_pressed and action == &"game_guard":
			emit_signal("guard_held")  # 按住期间每帧，与 guard_pressed 语义独立
		if not now_pressed and was_pressed and action == &"game_dash":
			var held_ms: int = Time.get_ticks_msec() - _dash_press_time_ms
			if held_ms < int(C.DASH_HOLD_THRESHOLD_MS):
				emit_signal("dash_pressed")  # 轻按 = 垫步
			_sprinting = false
		_was_pressed[action] = now_pressed


func _update_dash_hold() -> void:
	if _was_pressed.get(&"game_dash", false):
		_sprinting = Input.is_action_pressed("game_dash") and (Time.get_ticks_msec() - _dash_press_time_ms) >= int(C.DASH_HOLD_THRESHOLD_MS)


func poll_buffer() -> Dictionary:
	_clear_expired()
	if _buffer.is_empty():
		return {}
	return _buffer.pop_front()


func peek_buffer() -> Dictionary:
	_clear_expired()
	if _buffer.is_empty():
		return {}
	return _buffer[0]


func buffer_size() -> int:
	_clear_expired()
	return _buffer.size()


func is_sprinting() -> bool:
	return _sprinting


func _validate_input_map() -> Array[StringName]:
	var missing: Array[StringName] = []
	for a in ALL_ACTIONS:
		if not InputMap.has_action(a):
			missing.append(a)
	if not missing.is_empty():
		push_error("InputController: missing Input Map actions: %s" % [missing])
	return missing

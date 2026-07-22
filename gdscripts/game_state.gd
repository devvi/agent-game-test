extends Node

# GameState — Global CRPG game state singleton (DEPRECATED)
# Manages hope and despair variables with signal-based change notifications
# NOTE: As of Issue #47, this delegates internally to StateSystem.
# Direct use emits a deprecation log warning.

signal state_changed(state: Dictionary)

var hope: int = 100       # 0-100, player's hope level
var despair: int = 0      # 0-100, player's despair level

var _deprecated_warned: bool = false
var _state_system: Node = null

func _ready() -> void:
	print("GameState initialized: hope=", hope, ", despair=", despair)

func _get_state_system() -> Node:
	if _state_system == null:
		_state_system = get_node_or_null("/root/StateSystem")
	return _state_system

func _log_deprecation() -> void:
	if not _deprecated_warned:
		push_warning("GameState is deprecated (Issue #47). Use /root/StateSystem instead.")
		_deprecated_warned = true

func apply_state(delta_hope: int, delta_despair: int) -> void:
	var ss = _get_state_system()
	if ss and ss.has_method("apply_choice"):
		_log_deprecation()
		# Convert 0-100 range to -10/+10 hope_despair delta
		# hope delta (0-100) -> hope_despair delta (-10 to +10): scale by 0.2
		var hd_delta: float = float(delta_hope) * 0.2
		var despair_delta: float = float(delta_despair) * 0.2
		ss.apply_choice({"hope_despair": hd_delta - despair_delta})
		# Update local state to reflect
		var ss_state: Dictionary = ss.get_state()
		hope = clampi(int(ss_state.get("hope", 5.0) * 10.0), 0, 100)
		despair = clampi(100 - hope, 0, 100)
	else:
		hope = clampi(hope + delta_hope, 0, 100)
		despair = clampi(despair + delta_despair, 0, 100)
	state_changed.emit(get_state())

func get_state() -> Dictionary:
	var ss = _get_state_system()
	if ss and ss.has_method("get_state"):
		var ss_state: Dictionary = ss.get_state()
		var hope_float: float = ss_state.get("hope", 5.0)
		hope = clampi(int(hope_float * 10.0), 0, 100)
		despair = clampi(100 - hope, 0, 100)
	return {"hope": hope, "despair": despair}

func reset() -> void:
	hope = 100
	despair = 0
	state_changed.emit(get_state())

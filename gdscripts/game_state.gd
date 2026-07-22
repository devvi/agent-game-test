extends Node

# GameState — Global CRPG game state singleton (DEPRECATED)
# Manages hope and despair variables with signal-based change notifications
#
# DEPRECATED: Use StateSystem.hope_despair (-10 to +10) instead of
# GameState's hope/despair (0–100) independent values.
# This file is kept for backward compatibility during migration.
# Internal calls delegate to StateSystem where possible.

signal state_changed(state: Dictionary)

var hope: int = 100       # 0–100, player's hope level (DEPRECATED)
var despair: int = 0      # 0–100, player's despair level (DEPRECATED)

func _ready() -> void:
	print("WARNING: GameState is deprecated. Use StateSystem.hope_despair (-10 to +10) instead.")
	print("GameState initialized: hope=", hope, ", despair=", despair)

func apply_state(delta_hope: int, delta_despair: int) -> void:
	# Delegate to StateSystem if available
	var ss = get_node_or_null("/root/StateSystem")
	if ss:
		# Convert GameState 0–100 scale to slider -10/+10 scale
		# delta_hope/10 is the approximate slider delta equivalent
		var slider_delta: float = (float(delta_hope) - float(delta_despair)) / 10.0
		ss.apply_hope_despair_delta(slider_delta)

	hope = clampi(hope + delta_hope, 0, 100)
	despair = clampi(despair + delta_despair, 0, 100)
	state_changed.emit(get_state())

func get_state() -> Dictionary:
	return {"hope": hope, "despair": despair}

func reset() -> void:
	hope = 100
	despair = 0
	state_changed.emit(get_state())

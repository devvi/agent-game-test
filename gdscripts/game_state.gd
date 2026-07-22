extends Node

# GameState — Global CRPG game state singleton
# Manages hope and despair variables with signal-based change notifications

signal state_changed(state: Dictionary)

var hope: int = 100       # 0–100, player's hope level
var despair: int = 0      # 0–100, player's despair level

func _ready() -> void:
    print("GameState initialized: hope=", hope, ", despair=", despair)

func apply_state(delta_hope: int, delta_despair: int) -> void:
    hope = clampi(hope + delta_hope, 0, 100)
    despair = clampi(despair + delta_despair, 0, 100)
    state_changed.emit(get_state())

func get_state() -> Dictionary:
    return {"hope": hope, "despair": despair}

func reset() -> void:
    hope = 100
    despair = 0
    state_changed.emit(get_state())

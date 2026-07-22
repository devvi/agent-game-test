extends Node

# GameManager — 全局游戏状态管理
# 由 Autoload 自动加载

var game_started: bool = false

func _ready() -> void:
	print("Agent Game Test — Godot 4.7")
	print("GameManager initialized.")

func start_game() -> void:
	game_started = true
	print("Game started!")

# ===== Dialogue API =====

## Get current value of a slider axis. Returns 5.0 (default) if axis unknown.
func get_slider(axis: String) -> float:
	return 5.0

## Check if a named flag is set.
func has_flag(flag_name: String) -> bool:
	return false

## Get all flags as a Dictionary.
func get_flags() -> Dictionary:
	return {}

## Apply a slider delta (clamped to [1, 10]).
func apply_slider_delta(axis: String, delta: float) -> void:
	pass

## Set a named flag.
func set_flag(flag_name: String, value: bool) -> void:
	pass

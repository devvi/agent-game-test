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

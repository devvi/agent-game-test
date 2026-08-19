extends Node
## Game — shandong-wolf 全局 autoload 锚点（#572）。
## 注册: project.godot [autoload] Game="*res://gdscripts/game.gd"
## 职责: 最小单例——版本号 + constants 预加载；后续系统（输入/战斗/音频）挂接于此。

const WolfConstants = preload("res://gdscripts/constants.gd")
const DebugCanvasScript = preload("res://gdscripts/debug_canvas.gd")

var game_version: String = WolfConstants.GAME_VERSION


func _ready() -> void:
	if DebugCanvasScript.is_available():
		add_child(DebugCanvasScript.new())

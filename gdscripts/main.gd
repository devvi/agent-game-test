extends Node

# Main — 主场景入口脚本

func _ready() -> void:
	$Label.text = "Hello World"
	print("Main scene ready.")

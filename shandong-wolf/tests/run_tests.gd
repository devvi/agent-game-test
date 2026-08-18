extends SceneTree
## Test runner for shandong-wolf headless tests.
## Usage: godot --path shandong-wolf/ --headless --script tests/run_tests.gd
##
## Skeleton 期无真实测试；首个 implement Issue 落地后在此挂载套件。

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	# 占位：骨架无测试。后续实现按 mini-pong 模式追加 _run("res://tests/test_x.gd", "X")
	print("shandong-wolf: skeleton — no tests yet")
	print("TESTS: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

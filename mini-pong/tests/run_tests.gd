extends SceneTree
## Test runner for mini-pong headless tests.
## Usage: godot --path mini-pong/ --headless --script tests/run_tests.gd

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	_run("res://tests/test_paddle.gd", "Paddle")
	_run("res://tests/test_neon.gd", "Neon Visual")
	_run("res://tests/test_ball.gd", "Ball Physics")
	print("\n=== TOTAL: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _run(path: String, name: String) -> void:
	print("=== %s Tests ===" % name)
	var script = load(path)
	if script == null:
		print("  SKIP: %s not found" % path)
		_fail += 1
		return
	var tester = script.new()
	tester.run()
	_pass += tester.passed
	_fail += tester.failed
	print("  %s: %d passed, %d failed" % [name, tester.passed, tester.failed])

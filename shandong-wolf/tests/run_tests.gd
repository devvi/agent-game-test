extends SceneTree
## Test runner for shandong-wolf headless tests.
## Usage: godot --path shandong-wolf/ --headless --script tests/run_tests.gd
##
## #572 起挂载真实套件（StateMachine / Constants）；新增套件按 mini-pong 模式追加 _run()。
## Uses call_deferred to defer test execution until autoload singletons are
## initialized, so scripts that reference autoload names can resolve identifiers.

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_run("res://tests/test_state_machine.gd", "StateMachine")
	_run("res://tests/test_constants.gd", "Constants")
	_run("res://tests/test_debug_canvas.gd", "DebugCanvas")
	print("TESTS: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _run(path: String, name: String) -> void:
	print("=== %s Tests ===" % name)
	var script = load(path)
	if script == null:
		print("  SKIP: %s not found" % path)
		_fail += 1
		return
	if not script.can_instantiate():
		print("  FAIL: %s does not compile (parse error)" % path)
		_fail += 1
		return
	var tester = script.new()
	tester.run()
	_pass += tester.passed
	_fail += tester.failed
	print("  %s: %d passed, %d failed" % [name, tester.passed, tester.failed])

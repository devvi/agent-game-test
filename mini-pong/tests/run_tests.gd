extends SceneTree
## Test runner for mini-pong headless tests.
## Usage: godot --path mini-pong/ --headless --script tests/run_tests.gd
##
## Uses call_deferred to defer test execution until autoload singletons are
## initialized, so scripts that reference autoload names (e.g. GameManager)
## can resolve those identifiers during compilation.

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	# Defer to next idle frame — by then autoloads are registered and
	# their names are available for GDScript identifier resolution.
	call_deferred("_run_tests")


func _run_tests() -> void:
	_run("res://tests/test_paddle.gd", "Paddle")
	_run("res://tests/test_neon.gd", "Neon Visual")
	_run("res://tests/test_ball.gd", "Ball Physics")
	_run("res://tests/test_scoring_manager.gd", "Scoring Manager")
	_run("res://tests/test_ai_paddle.gd", "AI Paddle")
	_run("res://tests/test_game_manager.gd", "GameManager")
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

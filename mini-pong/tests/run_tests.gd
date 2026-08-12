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
	call_deferred("_run_tests")


func _run_tests() -> void:
	_run("res://tests/test_paddle.gd", "Paddle")
	_run("res://tests/test_neon.gd", "Neon Visual")
	_run("res://tests/test_ball.gd", "Ball Physics")
	_run("res://tests/test_scoring_manager.gd", "Scoring Manager")
	_run("res://tests/test_ai_paddle.gd", "AI Paddle")
	_run("res://tests/test_game_manager.gd", "GameManager")
	_run("res://tests/test_ui_system.gd", "UI System")
	_run("res://tests/test_game_state_machine.gd", "Game State Machine")
	_run("res://tests/test_pause.gd", "Pause")
	_run("res://tests/test_audio_engine.gd", "AudioEngine")
	_run("res://tests/test_constants.gd", "Constants")
	_run("res://tests/test_main_scene.gd", "Main Scene Assembly")
	_run("res://tests/test_rain.gd", "Rain Curtain")
	_run("res://tests/test_integration_fsm.gd", "FSM Integration")
	await _run_async("res://tests/auto_play_test.gd", "Auto-Play")
	print("
=== TOTAL: %d passed, %d failed ===" % [_pass, _fail])
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


func _run_async(path: String, name: String) -> void:
	print("=== %s Tests ===" % name)
	var script = load(path)
	if script == null:
		print("  SKIP: %s not found" % path)
		_fail += 1
		return
	var tester = script.new()
	await tester.run()
	_pass += tester.passed
	_fail += tester.failed
	print("  %s: %d passed, %d failed" % [name, tester.passed, tester.failed])

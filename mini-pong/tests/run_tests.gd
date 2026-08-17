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
	await _run_async("res://tests/test_breakout_grid.gd", "Breakout Grid")
	_run("res://tests/test_scoring_manager.gd", "Scoring Manager")
	_run("res://tests/test_ai_paddle.gd", "AI Paddle")
	_run("res://tests/test_game_manager.gd", "GameManager")
	_run("res://tests/test_dual_scoring.gd", "Dual Scoring")
	_run("res://tests/test_ui_system.gd", "UI System")
	_run("res://tests/test_failure_screen.gd", "Failure Screen")
	_run("res://tests/test_game_state_machine.gd", "Game State Machine")
	_run("res://tests/test_pause.gd", "Pause")
	_run("res://tests/test_pause_overlay.gd", "Pause Overlay")
	_run("res://tests/test_audio_engine.gd", "AudioEngine")
	_run("res://tests/test_constants.gd", "Constants")
	_run("res://tests/test_visual_contrast.gd", "Visual Contrast")
	_run("res://tests/test_upgrade_pool.gd", "Upgrade Pool")
	_run("res://tests/test_main_scene.gd", "Main Scene Assembly")
	_run("res://tests/test_rain.gd", "Rain Curtain")
	await _run_async("res://tests/test_hud.gd", "Neon HUD")
	_run("res://tests/test_integration_fsm.gd", "FSM Integration")
	await _run_async("res://tests/test_ball_fsm_serve_race.gd", "Ball Serve Race")
	_run("res://tests/test_world_visibility.gd", "World Visibility")
	await _run_async("res://tests/test_wave_cycle.gd", "Wave Cycle")
	await _run_async("res://tests/test_upgrade_pick_ui.gd", "Upgrade Pick UI")
	await _run_async("res://tests/test_wave_transition.gd", "Wave Transition")
	await _run_async("res://tests/test_integration_393.gd", "Assembly Integration")
	await _run_async("res://tests/test_visual_enrichment.gd", "Visual Enrichment")
	_run("res://tests/test_local_2p.gd", "Local 2P")
	await _run_async("res://tests/e2e_playthrough.gd", "E2E Playthrough")
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

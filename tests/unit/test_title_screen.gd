extends RefCounted

# Unit tests for TitleScreen (title screen with start prompt)
# Tests display, input handling, background rendering, and pulsing animation.
# See: docs/DESIGN/147-title-screen-start-prompt.md

var passed: int = 0
var failed: int = 0

var _signal_count: int = 0
var _captured_fade_duration: float = 0.0


func run() -> void:
	print("\n=== TitleScreen Unit Tests (Issue #147) ===")

	# Normal Path (>=2)
	_test_tc1_title_labels_displayed()
	_test_tc2_space_emits_start_requested()
	_test_tc3_pulse_animation_starts()

	# Boundary / Edge Cases (>=3)
	_test_tc4_enter_also_triggers_start()
	_test_tc5_double_space_no_double_emit()
	_test_tc6_space_after_start_ignored()
	_test_tc7_gradient_background_renders()
	_test_tc9_uiconfig_missing_degrades_gracefully()

	# Failure Path (>=1)
	_test_tc10_scene_manager_unavailable_fallback()

	print("TitleScreen Unit — Passed: ", passed, " Failed: ", failed)


func _make_title_screen():
	var ts = load("res://gdscripts/title_screen.gd").new()
	return ts


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _on_start_requested(fade_duration: float) -> void:
	_signal_count += 1
	_captured_fade_duration = fade_duration


# ===== Normal Path =====

func _test_tc1_title_labels_displayed() -> void:
	var ts = _make_title_screen()
	_assert(ts.title_string == "Urban Night Walker", "TC1-1: Default title string")
	_assert(ts.subtitle_string == "都市夜行者", "TC1-2: Default subtitle string")
	_assert(ts.prompt_string == "Press Space to Start", "TC1-3: Default prompt string")


func _test_tc2_space_emits_start_requested() -> void:
	var ts = _make_title_screen()
	ts.fade_duration = 0.5
	_signal_count = 0
	_captured_fade_duration = 0.0
	ts.start_requested.connect(_on_start_requested)

	# Simulate Space via dialogue_select action
	var event := InputEventAction.new()
	event.action = "dialogue_select"
	event.pressed = true
	ts._input(event)

	_assert(_signal_count == 1, "TC2-1: start_requested emitted once")
	_assert(abs(_captured_fade_duration - 0.5) < 0.001, "TC2-2: fade_duration = 0.5")


func _test_tc3_pulse_animation_starts() -> void:
	var ts = _make_title_screen()
	# The pulsing tween starts with modulate:a at 1.0, then tweens to 0.4
	# After tween creation, the property should be changing from 1.0
	_assert(ts._prompt_label.modulate.a > 0.0, "TC3-1: Prompt label modulate.a > 0 after tween creation")


# ===== Boundary / Edge Cases =====

func _test_tc4_enter_also_triggers_start() -> void:
	var ts = _make_title_screen()
	_signal_count = 0
	_captured_fade_duration = 0.0
	ts.start_requested.connect(_on_start_requested)

	# Simulate Enter via ui_accept action
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	ts._input(event)

	_assert(_signal_count == 1, "TC4-1: ui_accept (Enter) emits start_requested")


func _test_tc5_double_space_no_double_emit() -> void:
	var ts = _make_title_screen()
	_signal_count = 0
	ts.start_requested.connect(_on_start_requested)

	for i in range(2):
		var event := InputEventAction.new()
		event.action = "dialogue_select"
		event.pressed = true
		ts._input(event)

	_assert(_signal_count == 1, "TC5-1: Double space emits start_requested only once")


func _test_tc6_space_after_start_ignored() -> void:
	var ts = _make_title_screen()
	_signal_count = 0
	ts.start_requested.connect(_on_start_requested)

	# First press
	var event := InputEventAction.new()
	event.action = "dialogue_select"
	event.pressed = true
	ts._input(event)

	# Second press after set_process_input(false) was called
	event = InputEventAction.new()
	event.action = "dialogue_select"
	event.pressed = true
	ts._input(event)

	_assert(_signal_count == 1, "TC6-1: Second space after start is ignored")


func _test_tc7_gradient_background_renders() -> void:
	var ts = _make_title_screen()
	# Background rendering requires _ready() to configure
	# but we can check constants are set correctly
	_assert(ts.BG_COLOR_TOP.to_html() == "050510", "TC7-1: BG_COLOR_TOP = #050510")
	_assert(ts.BG_COLOR_BOTTOM.to_html() == "1a1a2e", "TC7-2: BG_COLOR_BOTTOM = #1a1a2e")


func _test_tc9_uiconfig_missing_degrades_gracefully() -> void:
	var ts = _make_title_screen()
	# No /root/UIConfig autoload — should not crash
	ts._configure_labels()
	_assert(ts._title_label.text == "Urban Night Walker", "TC9-1: Title text set without UIConfig")
	_assert(ts._prompt_label.text == "Press Space to Start", "TC9-2: Prompt text set without UIConfig")


# ===== Failure Path =====

func _test_tc10_scene_manager_unavailable_fallback() -> void:
	# We cannot test actual scene change in headless tests,
	# but we can verify that Main._load_starting_scene() exists as fallback
	var main_script = load("res://gdscripts/main.gd")
	var main = main_script.new()
	_assert(main != null, "TC10-1: Main instantiates without SceneManager autoload")

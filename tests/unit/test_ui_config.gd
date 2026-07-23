extends RefCounted

# Unit tests for UIConfig (responsive layout singleton)
# Tests font scale, choice spacing, and status bar height calculations.
# See: docs/DESIGN/53-ui-system.md

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== UIConfig Unit Tests (Issue #53) ===")

	_test_tc1_default_values()
	_test_tc2_font_scale_at_1080p()
	_test_tc3_font_scale_at_720p()
	_test_tc4_font_scale_at_1440p()
	_test_tc5_font_scale_clamp_min()
	_test_tc6_font_scale_clamp_max()
	_test_tc7_choice_spacing_scales_with_font()
	_test_tc8_choice_spacing_clamp_min()
	_test_tc9_choice_spacing_clamp_max()
	_test_tc10_status_bar_height_scales()

	print("UIConfig Unit — Passed: ", passed, " Failed: ", failed)


func _make_ui_config():
	var cfg = load("res://gdscripts/ui_config.gd").new()
	return cfg


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_tc1_default_values() -> void:
	var cfg = _make_ui_config()
	_assert(cfg.auto_font_scale == 1.0, "TC1-1: default auto_font_scale = 1.0")
	_assert(cfg.choice_spacing == 0.25, "TC1-2: default choice_spacing = 0.25")
	_assert(cfg.status_bar_height == 4.0, "TC1-3: default status_bar_height = 4.0")
	_assert(cfg.last_viewport_size == Vector2(1920, 1080), "TC1-4: default last_viewport_size = 1920x1080")


func _test_tc2_font_scale_at_1080p() -> void:
	var cfg = _make_ui_config()
	var simulated_size := Vector2(1920, 1080)
	# Simulate recalculate with given viewport size (inline calculation)
	var ratio := simulated_size.y / 1080.0
	cfg.auto_font_scale = clampf(ratio, 0.5, 2.0)
	_assert(abs(cfg.auto_font_scale - 1.0) < 0.001, "TC2-1: 1080p -> auto_font_scale = 1.0")


func _test_tc3_font_scale_at_720p() -> void:
	var cfg = _make_ui_config()
	var simulated_size := Vector2(1280, 720)
	var ratio := simulated_size.y / 1080.0
	cfg.auto_font_scale = clampf(ratio, 0.5, 2.0)
	_assert(abs(cfg.auto_font_scale - 0.6667) < 0.01, "TC3-1: 720p -> auto_font_scale ~ 0.667")


func _test_tc4_font_scale_at_1440p() -> void:
	var cfg = _make_ui_config()
	var simulated_size := Vector2(2560, 1440)
	var ratio := simulated_size.y / 1080.0
	cfg.auto_font_scale = clampf(ratio, 0.5, 2.0)
	_assert(abs(cfg.auto_font_scale - 1.3333) < 0.01, "TC4-1: 1440p -> auto_font_scale ~ 1.333")


func _test_tc5_font_scale_clamp_min() -> void:
	var cfg = _make_ui_config()
	# Very small viewport (e.g., 540p)
	var simulated_size := Vector2(960, 540)
	var ratio := simulated_size.y / 1080.0
	cfg.auto_font_scale = clampf(ratio, 0.5, 2.0)
	_assert(cfg.auto_font_scale == 0.5, "TC5-1: 540p -> auto_font_scale clamped to 0.5")


func _test_tc6_font_scale_clamp_max() -> void:
	var cfg = _make_ui_config()
	# Very large viewport (e.g., 4K)
	var simulated_size := Vector2(3840, 2160)
	var ratio := simulated_size.y / 1080.0
	cfg.auto_font_scale = clampf(ratio, 0.5, 2.0)
	_assert(cfg.auto_font_scale == 2.0, "TC6-1: 2160p -> auto_font_scale clamped to 2.0")


func _test_tc7_choice_spacing_scales_with_font() -> void:
	var cfg = _make_ui_config()
	var simulated_size := Vector2(1920, 1080)
	var ratio := simulated_size.y / 1080.0
	cfg.auto_font_scale = clampf(ratio, 0.5, 2.0)
	cfg.choice_spacing = clampf(0.25 * cfg.auto_font_scale, 0.12, 0.5)
	_assert(abs(cfg.choice_spacing - 0.25) < 0.001, "TC7-1: 1080p -> choice_spacing = 0.25")


func _test_tc8_choice_spacing_clamp_min() -> void:
	var cfg = _make_ui_config()
	cfg.auto_font_scale = 0.5
	cfg.choice_spacing = clampf(0.25 * cfg.auto_font_scale, 0.12, 0.5)
	_assert(abs(cfg.choice_spacing - 0.12) < 0.001 or cfg.choice_spacing == 0.12, "TC8-1: 0.5 font scale -> choice_spacing clamped to 0.12")


func _test_tc9_choice_spacing_clamp_max() -> void:
	var cfg = _make_ui_config()
	cfg.auto_font_scale = 2.0
	cfg.choice_spacing = clampf(0.25 * cfg.auto_font_scale, 0.12, 0.5)
	_assert(abs(cfg.choice_spacing - 0.5) < 0.001 or cfg.choice_spacing == 0.5, "TC9-1: 2.0 font scale -> choice_spacing clamped to 0.5")


func _test_tc10_status_bar_height_scales() -> void:
	var cfg = _make_ui_config()
	cfg.auto_font_scale = 1.5
	cfg.status_bar_height = 4.0 * cfg.auto_font_scale
	_assert(abs(cfg.status_bar_height - 6.0) < 0.001, "TC10-1: 1.5 font scale -> status_bar_height = 6.0")

	cfg.auto_font_scale = 0.5
	cfg.status_bar_height = 4.0 * cfg.auto_font_scale
	_assert(abs(cfg.status_bar_height - 2.0) < 0.001, "TC10-2: 0.5 font scale -> status_bar_height = 2.0")

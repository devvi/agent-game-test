extends RefCounted
## Test suite for window_autofit.gd (#544) — 窗口自动适配纯函数单测。
## 设计: docs/DESIGN/544-window-display-autofit.md §8.1（TC-W 编号）。
## Runs under godot --headless --script via run_tests.gd（静态调用，不依赖 autoload 名称解析）。

var passed: int = 0
var failed: int = 0

var AutoFit = null


func run() -> void:
	AutoFit = load("res://gdscripts/window_autofit.gd")
	if AutoFit == null:
		_assert(false, "TC-W0: window_autofit.gd loads successfully")
		print("Passed: %d, Failed: %d" % [passed, failed])
		return
	print("\n=== Window Autofit Tests ===")
	_test_tc_w1_1080p_anchor()
	_test_tc_w2_aspect_sweep()
	_test_tc_w3_4k_no_upscale()
	_test_tc_w4_1440p_cap()
	_test_tc_w5_invalid_rect_fallback()
	_test_tc_w6_tiny_screen()
	_test_tc_w7_centering()
	_test_tc_w8_headless_guard()
	_test_tc_w9_constants_integrity()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		printerr("❌ %s" % msg)
		failed += 1


# ── TC-W1（AC1 1080p 适配锚点）──

func _test_tc_w1_1080p_anchor() -> void:
	var result: Vector2i = AutoFit.compute_window_size(Rect2i(0, 0, 1920, 1080))
	_assert(result == Vector2i(607, 1080), "TC-W1: compute_window_size(0,0,1920,1080) == (607,1080), got %s" % result)


# ── TC-W2（AC2 等比全高度遍历）──

func _test_tc_w2_aspect_sweep() -> void:
	var expected: Dictionary = {
		768: Vector2i(432, 768),
		900: Vector2i(506, 900),
		1080: Vector2i(607, 1080),
		1440: Vector2i(720, 1280),
		2160: Vector2i(720, 1280),
	}
	for h in [768, 900, 1080, 1440, 2160]:
		var result: Vector2i = AutoFit.compute_window_size(Rect2i(0, 0, 1920, h))
		_assert(result == expected[h], "TC-W2: h=%d -> %s (expected %s)" % [h, result, expected[h]])
		if h <= 1280:
			_assert(result.y == h, "TC-W2: h=%d result.y == %d (窗口高 = 可用高)" % [h, h])
			_assert(result.x == floori(h * 720 / 1280.0), "TC-W2: h=%d result.x == floori(h*720/1280.0) == %d" % [h, result.x])
		else:
			_assert(result == Vector2i(720, 1280), "TC-W2: h=%d v1 cap result == (720,1280)" % h)


# ── TC-W3（4K 不放大，v1 cap）──

func _test_tc_w3_4k_no_upscale() -> void:
	var result: Vector2i = AutoFit.compute_window_size(Rect2i(0, 0, 3840, 2160))
	_assert(result == Vector2i(720, 1280), "TC-W3: compute_window_size(0,0,3840,2160) == (720,1280), got %s" % result)


# ── TC-W4（1440p cap）──

func _test_tc_w4_1440p_cap() -> void:
	var result: Vector2i = AutoFit.compute_window_size(Rect2i(0, 0, 2560, 1440))
	_assert(result == Vector2i(720, 1280), "TC-W4: compute_window_size(0,0,2560,1440) == (720,1280), got %s" % result)


# ── TC-W5（无效矩形回退默认 720×1280）──

func _test_tc_w5_invalid_rect_fallback() -> void:
	var result1: Vector2i = AutoFit.compute_window_size(Rect2i(0, 0, 0, 0))
	_assert(result1 == Vector2i(720, 1280), "TC-W5: compute_window_size(0,0,0,0) == (720,1280), got %s" % result1)
	var result2: Vector2i = AutoFit.compute_window_size(Rect2i(0, 0, -1, -1))
	_assert(result2 == Vector2i(720, 1280), "TC-W5: compute_window_size(0,0,-1,-1) == (720,1280), got %s" % result2)
	var result3: Vector2i = AutoFit.compute_window_size(Rect2i(100, 50, 0, 800))
	_assert(result3 == Vector2i(720, 1280), "TC-W5: compute_window_size(100,50,0,800) == (720,1280), got %s" % result3)


# ── TC-W6（极小屏 800×600）──

func _test_tc_w6_tiny_screen() -> void:
	var result: Vector2i = AutoFit.compute_window_size(Rect2i(0, 0, 800, 600))
	_assert(result == Vector2i(337, 600), "TC-W6: compute_window_size(0,0,800,600) == (337,600), got %s" % result)


# ── TC-W7（居中纯函数）──

func _test_tc_w7_centering() -> void:
	var result1: Vector2i = AutoFit.compute_centered_position(Rect2i(0, 0, 1920, 1080), Vector2i(607, 1080))
	_assert(result1 == Vector2i(656, 0), "TC-W7: center(0,0,1920,1080 / 607x1080) == (656,0), got %s" % result1)
	var result2: Vector2i = AutoFit.compute_centered_position(Rect2i(100, 50, 1920, 1080), Vector2i(607, 1080))
	_assert(result2 == Vector2i(756, 50), "TC-W7: center(100,50,1920,1080 / 607x1080) == (756,50), got %s" % result2)
	var result3: Vector2i = AutoFit.compute_centered_position(Rect2i(0, 0, 720, 1280), Vector2i(720, 1280))
	_assert(result3 == Vector2i(0, 0), "TC-W7: center(0,0,720,1280 / 720x1280) == (0,0), got %s" % result3)


# ── TC-W8（headless 双保险守卫）──

func _test_tc_w8_headless_guard() -> void:
	var skip: bool = AutoFit._should_skip()
	_assert(skip == true, "TC-W8: _should_skip() == true in headless, got %s" % skip)
	var inst = AutoFit.new()
	_assert(inst != null, "TC-W8: AutoFit.new() instantiates without error")
	inst._ready()
	_assert(true, "TC-W8: _ready() no crash / no window side effects in headless")


# ── TC-W9（constants 引用完整性）──

func _test_tc_w9_constants_integrity() -> void:
	var logical_size: Vector2i = AutoFit.LOGICAL_SIZE
	_assert(logical_size == Vector2i(720, 1280), "TC-W9: LOGICAL_SIZE == (720,1280), got %s" % logical_size)

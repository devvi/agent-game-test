extends RefCounted
## Test suite for Visual Three-Color Layer (#464) — 可控物/目标物/环境颜色分离.
## Issue #464 验收条件:
##   AC1: PADDLE_NEON / BRICK_NEON / BG_COLOR 两两 RGB 欧氏距离 ≥ 60
##   AC2: PADDLE_NEON vs BG_COLOR WCAG 相对亮度对比度 ≥ 4:1 (Color.get_luminance())
##   AC3: BRICK_NEON vs PADDLE_NEON HSV 色相分离 ≥ 60° (Color.h 返回 0–1 归一化, 环形差)
##   AC4: brick.tscn ColorRect 显式设置 color = BRICK_NEON (不再继承默认)
##   AC5: 只新增常量, 既有语义色值不动 (test_constants TC6/TC8 覆盖, 本套件不重复)
## 渲染层有效性: neon_glow_material.tres glow_width 回落 0.25 (DESIGN §3.4, 基底色透出)
## 断言字面与场景/材质写入逐字节一致 (DESIGN §5.6):
##   player_paddle.tscn       → "color = Color(0, 0.898, 1, 1)"
##   brick.tscn               → "color = Color(1, 0.616, 0.271, 1)"
##   neon_glow_material.tres  → "shader_parameter/glow_width = 0.25"

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Visual Contrast Tests (#464) ===")
	_test_a_constants_exist_and_values()
	_test_b_rgb_distance()
	_test_c_wcag_contrast()
	_test_d_hsv_hue_separation()
	_test_e_tscn_tres_text_assertions()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _rgb_distance(a: Color, b: Color) -> float:
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


# ── Scenario A (P0): 常量存在与值 ──

func _test_a_constants_exist_and_values() -> void:
	var C = load("res://gdscripts/constants.gd")
	_assert(C != null, "A1-1: constants.gd loads")
	if C == null:
		return
	var const_map: Dictionary = C.get_script_constant_map()
	_assert(const_map.has("PADDLE_NEON"), "A1-2: PADDLE_NEON 常量存在")
	_assert(const_map.has("BRICK_NEON"), "A1-3: BRICK_NEON 常量存在")
	if const_map.has("PADDLE_NEON") and const_map.has("BRICK_NEON"):
		var paddle: Color = const_map["PADDLE_NEON"]
		var brick: Color = const_map["BRICK_NEON"]
		_assert(abs(paddle.r - 0.0) < 0.01 and abs(paddle.g - 0.898) < 0.01 and abs(paddle.b - 1.0) < 0.01,
			"A2: PADDLE_NEON == Color(0, 0.898, 1.0, 1.0) #00e5ff (got %s)" % paddle)
		_assert(abs(brick.r - 1.0) < 0.01 and abs(brick.g - 0.616) < 0.01 and abs(brick.b - 0.271) < 0.01,
			"A3: BRICK_NEON == Color(1.0, 0.616, 0.271, 1.0) #ff9d45 (got %s)" % brick)


# ── Scenario B: 三色互异 — RGB 欧氏距离 ≥ 60 (AC1) ──

func _test_b_rgb_distance() -> void:
	var C = load("res://gdscripts/constants.gd")
	if C == null:
		_assert(false, "B0: constants.gd loads")
		return
	var const_map: Dictionary = C.get_script_constant_map()
	if not (const_map.has("PADDLE_NEON") and const_map.has("BRICK_NEON") and const_map.has("BG_COLOR")):
		_assert(false, "B0: 三色常量缺失, 跳过 RGB 距离断言")
		return
	var paddle: Color = const_map["PADDLE_NEON"]
	var brick: Color = const_map["BRICK_NEON"]
	var bg: Color = const_map["BG_COLOR"]
	# Color 分量 0–1 归一化; AC 阈值 60 为 0–255 空间 (PRD 验算 324/323/290) → ×255
	var d_pb = _rgb_distance(paddle, brick) * 255.0
	var d_pbg = _rgb_distance(paddle, bg) * 255.0
	var d_bbg = _rgb_distance(brick, bg) * 255.0
	_assert(d_pb >= 60.0, "B1: PADDLE_NEON vs BRICK_NEON RGB 距离 >= 60 (got %.1f)" % d_pb)
	_assert(d_pbg >= 60.0, "B2: PADDLE_NEON vs BG_COLOR RGB 距离 >= 60 (got %.1f)" % d_pbg)
	_assert(d_bbg >= 60.0, "B3: BRICK_NEON vs BG_COLOR RGB 距离 >= 60 (got %.1f)" % d_bbg)


# ── Scenario C: WCAG 对比度 ≥ 4:1 (AC2) ──

func _test_c_wcag_contrast() -> void:
	var C = load("res://gdscripts/constants.gd")
	if C == null:
		_assert(false, "C0: constants.gd loads")
		return
	var const_map: Dictionary = C.get_script_constant_map()
	if not (const_map.has("PADDLE_NEON") and const_map.has("BG_COLOR")):
		_assert(false, "C0: 常量缺失, 跳过 WCAG 对比度断言")
		return
	var paddle: Color = const_map["PADDLE_NEON"]
	var bg: Color = const_map["BG_COLOR"]
	var l1 = paddle.get_luminance()
	var l2 = bg.get_luminance()
	var ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
	_assert(ratio >= 4.0, "C1: WCAG 对比度 PADDLE_NEON vs BG_COLOR >= 4:1 (got %.1f:1)" % ratio)


# ── Scenario D: HSV 色相分离 ≥ 60° (AC3) ──

func _test_d_hsv_hue_separation() -> void:
	var C = load("res://gdscripts/constants.gd")
	if C == null:
		_assert(false, "D0: constants.gd loads")
		return
	var const_map: Dictionary = C.get_script_constant_map()
	if not (const_map.has("BRICK_NEON") and const_map.has("PADDLE_NEON")):
		_assert(false, "D0: 常量缺失, 跳过色相分离断言")
		return
	var brick: Color = const_map["BRICK_NEON"]
	var paddle: Color = const_map["PADDLE_NEON"]
	# Color.h 返回 0–1 归一化色相 (0–360° 映射); 环形色相差取小
	var d = abs(brick.h - paddle.h)
	if d > 0.5:
		d = 1.0 - d
	var deg = d * 360.0
	_assert(deg >= 60.0, "D1: BRICK_NEON vs PADDLE_NEON HSV 色相分离 >= 60° (got %.1f°)" % deg)


# ── Scenario E: tscn / tres 文本断言 (AC4 + 渲染层有效性) ──

func _test_e_tscn_tres_text_assertions() -> void:
	var paddle_tscn = FileAccess.get_file_as_string("res://scenes/player_paddle.tscn")
	_assert(paddle_tscn != "", "E1-1: player_paddle.tscn 可读")
	_assert(paddle_tscn.contains("color = Color(0, 0.898, 1, 1)"),
		"E1-2: player_paddle.tscn ColorRect color = PADDLE_NEON 字面")
	var brick_tscn = FileAccess.get_file_as_string("res://scenes/brick.tscn")
	_assert(brick_tscn != "", "E2-1: brick.tscn 可读")
	_assert(brick_tscn.contains("color = Color(1, 0.616, 0.271, 1)"),
		"E2-2: brick.tscn ColorRect 显式 color = BRICK_NEON (AC4)")
	var mat = FileAccess.get_file_as_string("res://assets/neon_glow_material.tres")
	_assert(mat != "", "E3-1: neon_glow_material.tres 可读")
	_assert(mat.contains("shader_parameter/glow_width = 0.25"),
		"E3-2: glow_width 回落 0.25 (渲染层生效)")

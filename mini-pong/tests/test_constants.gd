extends RefCounted
## Test suite for constants.gd (#295) — Global constants extraction.
## Runs under godot --headless --script via run_tests.gd.
## 竖屏重写 (#383): TC6-2/3 SCREEN 720/1280；TC6-11/12 PADDLE 尺寸语义翻转
## （PADDLE_WIDTH=120 横向长度、PADDLE_HEIGHT=20 纵向厚度）。

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Constants Tests (#295) ===")
	_test_tc6_constants_values_match()
	_test_tc7_preload_works()
	_test_tc8_color_values()
	_test_dual_scoring_constants()
	_test_wave_cycle_constants()


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── TC6: GameConstants values match original dispersed constants ──

func _test_tc6_constants_values_match() -> void:
	var CONSTS = load("res://gdscripts/constants.gd")

	_assert(CONSTS != null, "TC6-1: constants.gd loads successfully")

	# Screen (竖屏 720x1280, #383)
	_assert(CONSTS.SCREEN_WIDTH == 720, "TC6-2: SCREEN_WIDTH == 720")
	_assert(CONSTS.SCREEN_HEIGHT == 1280, "TC6-3: SCREEN_HEIGHT == 1280")

	# Ball Physics
	_assert(abs(CONSTS.BALL_INITIAL_SPEED - 330.0) < 0.01, "TC6-4: BALL_INITIAL_SPEED == 330.0")
	_assert(abs(CONSTS.BALL_MAX_SPEED_MULTIPLIER - 1.9) < 0.01, "TC6-5: BALL_MAX_SPEED_MULTIPLIER == 1.9")
	_assert(abs(CONSTS.BALL_SPEED_INCREMENT - 1.07) < 0.01, "TC6-6: BALL_SPEED_INCREMENT == 1.07")
	_assert(abs(CONSTS.BALL_MAX_BOUNCE_ANGLE - 55.0) < 0.01, "TC6-7: BALL_MAX_BOUNCE_ANGLE == 55.0")
	_assert(abs(CONSTS.BALL_SERVE_ANGLE_RANGE - 30.0) < 0.01, "TC6-8: BALL_SERVE_ANGLE_RANGE == 30.0")
	_assert(abs(CONSTS.BALL_RADIUS - 10.0) < 0.01, "TC6-9: BALL_RADIUS == 10.0")

	# Paddle (竖屏语义: WIDTH=120 横向长度, HEIGHT=20 纵向厚度, #383)
	_assert(abs(CONSTS.PADDLE_SPEED - 430.0) < 0.01, "TC6-10: PADDLE_SPEED == 430.0")
	_assert(abs(CONSTS.PADDLE_WIDTH - 120.0) < 0.01, "TC6-11: PADDLE_WIDTH == 120.0")
	_assert(abs(CONSTS.PADDLE_HEIGHT - 20.0) < 0.01, "TC6-12: PADDLE_HEIGHT == 20.0")

	# AI
	_assert(abs(CONSTS.AI_REACTION_DELAY_MIN - 0.15) < 0.01, "TC6-13: AI_REACTION_DELAY_MIN == 0.15")
	_assert(abs(CONSTS.AI_REACTION_DELAY_MAX - 0.4) < 0.01, "TC6-14: AI_REACTION_DELAY_MAX == 0.4")
	_assert(abs(CONSTS.AI_POSITION_ERROR - 24.0) < 0.01, "TC6-15: AI_POSITION_ERROR == 24.0")
	_assert(abs(CONSTS.AI_SPEED_BOOST - 1.25) < 0.01, "TC6-16: AI_SPEED_BOOST == 1.25")
	_assert(abs(CONSTS.AI_SPEED_SLOW - 0.75) < 0.01, "TC6-17: AI_SPEED_SLOW == 0.75")

	# Scoring
	_assert(CONSTS.POINTS_TO_WIN_GAME == 5, "TC6-18: POINTS_TO_WIN_GAME == 5")
	_assert(CONSTS.GAMES_TO_WIN_MATCH == 2, "TC6-19: GAMES_TO_WIN_MATCH == 2")

	# Colors
	_assert(abs(CONSTS.PLAYER_NEON_BLUE.r - 0.29) < 0.01, "TC6-20: PLAYER_NEON_BLUE.r == 0.29")
	_assert(abs(CONSTS.PLAYER_NEON_BLUE.g - 0.56) < 0.01, "TC6-21: PLAYER_NEON_BLUE.g == 0.56")
	_assert(abs(CONSTS.PLAYER_NEON_BLUE.b - 0.85) < 0.01, "TC6-22: PLAYER_NEON_BLUE.b == 0.85")
	_assert(abs(CONSTS.AI_NEON_RED.r - 1.0) < 0.01, "TC6-23: AI_NEON_RED.r == 1.0")
	_assert(abs(CONSTS.AI_NEON_RED.g - 0.2) < 0.01, "TC6-24: AI_NEON_RED.g == 0.2")
	_assert(abs(CONSTS.AI_NEON_RED.b - 0.33) < 0.01, "TC6-25: AI_NEON_RED.b == 0.33")

	# Version (#358)
	_assert(CONSTS.GAME_VERSION == "v1.0.0", 'TC6-26: GAME_VERSION == "v1.0.0"')


# ── TC7: preload("constants.gd") works in headless mode ──

func _test_tc7_preload_works() -> void:
	# Verify the file exists and can be loaded
	var exists = ResourceLoader.exists("res://gdscripts/constants.gd")
	_assert(exists, "TC7-1: constants.gd file exists")

	# Verify preload pattern works (used by production scripts)
	var CONSTS = load("res://gdscripts/constants.gd")
	_assert(CONSTS != null, "TC7-2: load() returns a valid resource")
	_assert(CONSTS.SCREEN_WIDTH > 0, "TC7-3: constants accessible after load()")
	_assert(CONSTS.POINTS_TO_WIN_GAME > 0, "TC7-4: scoring constants accessible")


# ── TC8: Color values match DESIGN doc specifications ──

func _test_tc8_color_values() -> void:
	var CONSTS = load("res://gdscripts/constants.gd")
	_assert(CONSTS != null, "TC8-1: constants.gd loads for color tests")

	# Player blue: #4a90d9 → Color(0.29, 0.56, 0.85, 1.0)
	_assert(abs(CONSTS.PLAYER_NEON_BLUE.a - 1.0) < 0.01, "TC8-2: PLAYER_NEON_BLUE alpha == 1.0")

	# AI red: #ff3355 → Color(1.0, 0.2, 0.33, 1.0)
	_assert(abs(CONSTS.AI_NEON_RED.a - 1.0) < 0.01, "TC8-3: AI_NEON_RED alpha == 1.0")

	# BG color: #0a0a12 → Color(0.039, 0.039, 0.071, 1.0)
	_assert(abs(CONSTS.BG_COLOR.r - 0.039) < 0.01, "TC8-4: BG_COLOR.r == 0.039")
	_assert(abs(CONSTS.BG_COLOR.g - 0.039) < 0.01, "TC8-5: BG_COLOR.g == 0.039")
	_assert(abs(CONSTS.BG_COLOR.b - 0.071) < 0.01, "TC8-6: BG_COLOR.b == 0.071")


# ── TC9: Dual scoring constants (#385) match DESIGN spec ──

func _test_dual_scoring_constants() -> void:
	var CONSTS = load("res://gdscripts/constants.gd")
	_assert(CONSTS != null, "TC9-1: constants.gd loads for dual-scoring tests")

	# Dual scoring (#385): brick 1pt / pierce 3pt / 21-point match over
	_assert(CONSTS.BRICK_SCORE == 1, "TC9-2: BRICK_SCORE == 1")
	_assert(CONSTS.PIERCE_SCORE == 3, "TC9-3: PIERCE_SCORE == 3")
	_assert(CONSTS.WIN_SCORE == 21, "TC9-4: WIN_SCORE == 21")

# ── TC10: Wave Cycle constants (#386) match DESIGN §2.1 ──

func _test_wave_cycle_constants() -> void:
	var CONSTS = load("res://gdscripts/constants.gd")
	_assert(CONSTS != null, "TC10-0: constants.gd loads for wave-cycle tests")

	_assert(CONSTS.WAVE_START_THICKNESS == 1, "TC10-1: WAVE_START_THICKNESS == 1")
	_assert(CONSTS.WAVE_THICKNESS_STEP == 1, "TC10-2: WAVE_THICKNESS_STEP == 1")
	_assert(CONSTS.WAVE_MAX_INDEX == 99, "TC10-3: WAVE_MAX_INDEX == 99")
	_assert(abs(CONSTS.WAVE_SETTLE_DELAY - 1.0) < 0.001, "TC10-4: WAVE_SETTLE_DELAY == 1.0")
	_assert(abs(CONSTS.AI_DIFFICULTY_FACTOR - 0.9) < 0.001, "TC10-5: AI_DIFFICULTY_FACTOR == 0.9")
	_assert(abs(CONSTS.AI_REACTION_DELAY_MIN_FLOOR - 0.05) < 0.001, "TC10-6: AI_REACTION_DELAY_MIN_FLOOR == 0.05")
	_assert(abs(CONSTS.AI_REACTION_DELAY_MAX_FLOOR - 0.12) < 0.001, "TC10-7: AI_REACTION_DELAY_MAX_FLOOR == 0.12")
	_assert(abs(CONSTS.AI_POSITION_ERROR_FLOOR - 8.0) < 0.001, "TC10-8: AI_POSITION_ERROR_FLOOR == 8.0")

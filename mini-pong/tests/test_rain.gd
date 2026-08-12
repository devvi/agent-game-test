extends RefCounted
## Test suite for dynamic rain curtain (#389) — formula engine, clamp boundaries,
## smoothing (AC4), event pulse decay, contract API defaults, NaN guard, resource integrity.
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/389-dynamic-rain-curtain.md §5 (测试契约)

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")

func run() -> void:
	print("\n=== Rain Curtain Tests (#389) ===")
	_test_clamp_boundaries()
	_test_formula_monotonicity()
	_test_tension_boundary()
	_test_smoothing_no_jump()
	_test_smoothing_convergence()
	_test_event_pulse_decay()
	_test_contract_defaults()
	_test_contract_api()
	_test_nan_guard()
	_test_resource_integrity()


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_curtain():
	"""Fresh RainCurtain instance. @onready vars are null (not in tree) — pure logic only."""
	var script = load("res://gdscripts/rain_curtain.gd")
	var curtain = Node2D.new()
	curtain.set_script(script)
	curtain.name = "RainCurtain"
	return curtain


# ── clamp 边界 (AC2) ──

func _test_clamp_boundaries() -> void:
	var c = _make_curtain()
	# 输入 −1（base 0.3 + 负脉冲 −2 + 喘息 −0.15 远超下限）→ 0.1
	_assert(abs(c.compute_target_rain(330.0, 0, -2.0, true, 0, 0) - 0.1) < 0.0001,
		"TC-clamp-1: 输入 −1 → 0.1")
	# 输入 2（脉冲 +2.0）→ 1.0
	_assert(abs(c.compute_target_rain(330.0, 0, 2.0, false, 0, 0) - 1.0) < 0.0001,
		"TC-clamp-2: 输入 2 → 1.0")
	# RAIN_MIN/RAIN_MAX 为唯一边界源（钉死双边界）
	_assert(abs(CONSTS.RAIN_MIN - 0.1) < 0.0001, "TC-clamp-3: RAIN_MIN == 0.1")
	_assert(abs(CONSTS.RAIN_MAX - 1.0) < 0.0001, "TC-clamp-4: RAIN_MAX == 1.0")
	# 正常输入保序
	var r1: float = c.compute_target_rain(400.0, 0, 0.0, false, 0, 0)
	var r2: float = c.compute_target_rain(500.0, 0, 0.0, false, 0, 0)
	_assert(r1 <= r2, "TC-clamp-5: 正常输入保序")


# ── 公式单调性 (AC3) ──

func _test_formula_monotonicity() -> void:
	var c = _make_curtain()
	# 球速 330→627 雨量单调不减
	var prev: float = c.compute_target_rain(330.0, 0, 0.0, false, 0, 0)
	var monotonic: bool = true
	var speed: float = 330.0
	while speed <= 627.0:
		var r: float = c.compute_target_rain(speed, 0, 0.0, false, 0, 0)
		if r < prev - 0.0001:
			monotonic = false
		prev = r
		speed += 33.0
	_assert(monotonic, "TC-mono-1: 球速 330→627 雨量单调不减")
	# 发球瞬间 speed=330 → 球速因子 0（差=3 排除紧张因子）→ base
	_assert(abs(c.compute_target_rain(330.0, 0, 0.0, false, 0, 3) - CONSTS.RAIN_BASE) < 0.0001,
		"TC-mono-2: 发球瞬间 330 → base（球速因子 0）")
	# 上限 330×1.9≈627 → 因子 +0.3 → base+0.3
	_assert(abs(c.compute_target_rain(627.0, 0, 0.0, false, 0, 3) - (CONSTS.RAIN_BASE + CONSTS.RAIN_SPEED_FACTOR_MAX)) < 0.0001,
		"TC-mono-3: 上限 627 → base+0.3")


# ── 紧张因子等号边界 ──

func _test_tension_boundary() -> void:
	var c = _make_curtain()
	# 差=2（≤2 含等号）→ +0.2
	_assert(abs(c.compute_target_rain(330.0, 0, 0.0, false, 0, 2) - (CONSTS.RAIN_BASE + CONSTS.RAIN_TENSION_BONUS)) < 0.0001,
		"TC-tension-1: 比分差=2 → +0.2")
	# 差=3 → 0
	_assert(abs(c.compute_target_rain(330.0, 0, 0.0, false, 0, 3) - CONSTS.RAIN_BASE) < 0.0001,
		"TC-tension-2: 比分差=3 → +0")
	# 反向差=2 同样 +0.2
	_assert(abs(c.compute_target_rain(330.0, 0, 0.0, false, 5, 3) - (CONSTS.RAIN_BASE + CONSTS.RAIN_TENSION_BONUS)) < 0.0001,
		"TC-tension-3: 差=2 反向也 +0.2")


# ── 平滑无跳变 (AC4) ──

func _test_smoothing_no_jump() -> void:
	var c = _make_curtain()
	c.current_rain = CONSTS.RAIN_BASE
	c.set_intensity(1.0)  # 目标阶跃 0.3 → 1.0
	var step_range: float = 0.7
	var max_delta: float = 0.0
	for i in range(30):
		var before: float = c.current_rain
		c._process(1.0 / 60.0)
		var delta: float = abs(c.current_rain - before)
		if delta > max_delta:
			max_delta = delta
	_assert(max_delta <= 0.2 * step_range,
		"TC-smooth-1: 单帧变化 ≤ 20%% of range (max %.4f)" % max_delta)


func _test_smoothing_convergence() -> void:
	var c = _make_curtain()
	c.current_rain = CONSTS.RAIN_BASE
	c.set_intensity(1.0)
	for i in range(30):  # 30 × 1/60s = 0.5s
		c._process(1.0 / 60.0)
	var gap: float = abs(c.current_rain - 1.0)
	_assert(gap < 0.05 * 0.7,
		"TC-smooth-2: 0.5s 后收敛到目标 95%%+ (gap %.4f)" % gap)


# ── 事件脉冲回落 ──

func _test_event_pulse_decay() -> void:
	var c = _make_curtain()
	c.current_rain = CONSTS.RAIN_BASE
	c._player_score = 0
	c._ai_score = 3  # 差=3 → 紧张因子 0，基线 = 纯 base 0.3
	c.trigger_event_pulse(0.4)
	var samples: Array = []
	for i in range(150):  # 2.5s
		c._process(1.0 / 60.0)
		samples.append(c.current_rain)
	# 雨量上升（超过基线 0.05 以上）
	var peak: float = 0.0
	for s in samples:
		if s > peak:
			peak = s
	_assert(peak > CONSTS.RAIN_BASE + 0.05, "TC-pulse-1: 脉冲后雨量上升 (peak %.4f)" % peak)
	# ~1.5s 后回落回基线（3τ=1.5s 内单调递减，非瞬间消失）
	var last: float = samples[samples.size() - 1]
	_assert(abs(last - CONSTS.RAIN_BASE) < 0.05, "TC-pulse-2: 回落到基线 (last %.4f)" % last)
	# 峰值后单调递减
	var decreasing: bool = true
	var found_peak: bool = false
	var prev_val: float = -1.0
	for s in samples:
		if not found_peak and s >= peak - 0.0001:
			found_peak = true
			prev_val = s
			continue
		if found_peak:
			if s > prev_val + 0.0005:
				decreasing = false
			prev_val = s
	_assert(decreasing, "TC-pulse-3: 峰值后单调递减")
	# 脉冲状态衰减到近 0
	_assert(c._pulse_current < 0.02, "TC-pulse-4: _pulse_current 衰减到近 0")


# ── 契约默认值 ──

func _test_contract_defaults() -> void:
	var c = _make_curtain()
	# 未接线时波次/脉冲/喘息恒 0 → 雨量 = base+球速+紧张 ∈ [0.3, 0.8]
	# 最低 0.3：球速因子 0 + 紧张因子 0（差=3）
	_assert(abs(c.compute_target_rain(330.0, 0, 0.0, false, 0, 3) - CONSTS.RAIN_BASE) < 0.0001,
		"TC-default-1: 最低雨量 0.3")
	# 0.6：球速上限 + 紧张 0（差=3）
	_assert(abs(c.compute_target_rain(627.0, 0, 0.0, false, 0, 3) - (CONSTS.RAIN_BASE + CONSTS.RAIN_SPEED_FACTOR_MAX)) < 0.0001,
		"TC-default-2: 球速上限 0.6")
	# 最高 0.8：球速上限 + 紧张 +0.2（差=0 ≤ 2）
	_assert(abs(c.compute_target_rain(627.0, 0, 0.0, false, 0, 0) - (CONSTS.RAIN_BASE + CONSTS.RAIN_SPEED_FACTOR_MAX + CONSTS.RAIN_TENSION_BONUS)) < 0.0001,
		"TC-default-3: 最高雨量 0.8")
	# 等分情境（0-0）：紧张因子按公式生效（差≤2）→ base+0.2 = 0.5
	_assert(abs(c.compute_target_rain(330.0, 0, 0.0, false, 0, 0) - (CONSTS.RAIN_BASE + CONSTS.RAIN_TENSION_BONUS)) < 0.0001,
		"TC-default-4: 0-0 开局 → 紧张因子生效 0.5")
	_assert(c._wave_index == 0 and abs(c._pulse_current) < 0.0001 and not c._breathing,
		"TC-default-5: 契约默认值恒 0/false")


# ── 契约 API ──

func _test_contract_api() -> void:
	var c = _make_curtain()
	var base: float = c.compute_target_rain(330.0, 0, 0.0, false, 0, 0)
	# set_wave_factor: 每波 +0.1
	c.set_wave_factor(2)
	var after_wave: float = c.compute_target_rain(330.0, c._wave_index, 0.0, false, 0, 0)
	_assert(abs(after_wave - (base + 2.0 * CONSTS.RAIN_WAVE_STEP)) < 0.0001,
		"TC-api-1: set_wave_factor(2) → +0.2")
	# set_breathing: −0.15
	c.set_breathing(true)
	var after_breath: float = c.compute_target_rain(330.0, c._wave_index, 0.0, true, 0, 0)
	_assert(abs(after_breath - (after_wave - CONSTS.RAIN_BREATHING_DROP)) < 0.0001,
		"TC-api-2: set_breathing(true) → −0.15")
	# set_intensity: 调试口直设目标（不走公式）
	c.set_intensity(0.9)
	_assert(abs(c._compute_target() - 0.9) < 0.0001, "TC-api-3: set_intensity(0.9) 直设目标")
	# set_intensity(-1) → 回到公式模式
	c.set_intensity(-1.0)
	_assert(abs(c._compute_target() - after_breath) < 0.0001, "TC-api-4: set_intensity(-1) 回公式")


# ── NaN 防护 (#287 先例) ──

func _test_nan_guard() -> void:
	var c = _make_curtain()
	# ball.speed 为 NaN → 球速因子按 0 → 回退 base（差=3 排除紧张因子）
	var r: float = c.compute_target_rain(NAN, 0, 0.0, false, 0, 3)
	_assert(abs(r - CONSTS.RAIN_BASE) < 0.0001, "TC-nan-1: NaN 球速 → 因子 0, 回退 base")
	# 不污染平滑状态：目标回退 base → current 正常向 0.3 收敛，非 NaN
	c.current_rain = 0.5
	c._player_score = 0
	c._ai_score = 3
	c._ball_speed = NAN
	c._process(1.0 / 60.0)
	_assert(not is_nan(c.current_rain) and c.current_rain > 0.0 and c.current_rain < 0.5,
		"TC-nan-2: NaN 不污染平滑状态 (current %.4f)" % c.current_rain)


# ── 资源完整性 (test_neon.gd 风格) ──

func _test_resource_integrity() -> void:
	# rain_curtain.tscn 含 GPUParticles2D + ParticleProcessMaterial + 脚本
	var tscn: String = FileAccess.get_file_as_string("res://scenes/rain_curtain.tscn")
	_assert(tscn != "", "TC-res-1: rain_curtain.tscn 可读")
	_assert(tscn.contains("GPUParticles2D"), "TC-res-2: rain_curtain.tscn 含 GPUParticles2D")
	_assert(tscn.contains("ParticleProcessMaterial"), "TC-res-3: rain_curtain.tscn 含 ParticleProcessMaterial")
	_assert(tscn.contains("rain_curtain.gd"), "TC-res-4: rain_curtain.tscn 挂 rain_curtain.gd")
	# rain_drop.png 存在
	_assert(FileAccess.file_exists("res://assets/rain_drop.png"), "TC-res-5: rain_drop.png 存在")
	# Main.tscn 含 AtmosphereLayer + 雨幕实例
	var main: String = FileAccess.get_file_as_string("res://scenes/Main.tscn")
	_assert(main.contains("AtmosphereLayer"), "TC-res-6: Main.tscn 含 AtmosphereLayer")
	_assert(main.contains("rain_curtain.tscn"), "TC-res-7: Main.tscn 实例化 rain_curtain.tscn")
	# constants.gd RAIN_* 组
	var consts = load("res://gdscripts/constants.gd")
	_assert(consts != null, "TC-res-8: constants.gd 加载")
	_assert(abs(consts.RAIN_BASE - 0.3) < 0.0001, "TC-res-9: RAIN_BASE == 0.3")
	_assert(abs(consts.RAIN_SMOOTH_TAU - 0.15) < 0.0001, "TC-res-10: RAIN_SMOOTH_TAU == 0.15")
	_assert(abs(consts.RAIN_SPEED_FACTOR_MAX - 0.3) < 0.0001, "TC-res-11: RAIN_SPEED_FACTOR_MAX == 0.3")
	_assert(consts.RAIN_TENSION_THRESHOLD == 2, "TC-res-12: RAIN_TENSION_THRESHOLD == 2")
	_assert(abs(consts.RAIN_TENSION_BONUS - 0.2) < 0.0001, "TC-res-13: RAIN_TENSION_BONUS == 0.2")
	_assert(abs(consts.RAIN_WAVE_STEP - 0.1) < 0.0001, "TC-res-14: RAIN_WAVE_STEP == 0.1")
	_assert(abs(consts.RAIN_PULSE_PIERCE - 0.4) < 0.0001, "TC-res-15: RAIN_PULSE_PIERCE == 0.4")
	_assert(abs(consts.RAIN_BREATHING_DROP - 0.15) < 0.0001, "TC-res-16: RAIN_BREATHING_DROP == 0.15")
	# 场景可实例化 + GPUParticles2D 子节点
	var scene = load("res://scenes/rain_curtain.tscn")
	_assert(scene != null, "TC-res-17: rain_curtain.tscn 加载")
	if scene:
		var inst = scene.instantiate()
		_assert(inst != null, "TC-res-18: rain_curtain.tscn 实例化")
		if inst:
			_assert(inst.has_node("Particles"), "TC-res-19: 含 Particles 子节点")
			var p = inst.get_node_or_null("Particles")
			_assert(p is GPUParticles2D, "TC-res-20: Particles 是 GPUParticles2D")
			inst.queue_free()

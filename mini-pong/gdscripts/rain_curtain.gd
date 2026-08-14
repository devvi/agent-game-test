extends Node2D
## Dynamic rain curtain — L0 atmosphere layer (#389).
## Formula-driven GPUParticles2D modulation. NEVER writes `amount` (Godot
## restarts the particle system on amount change → visible jumps, AC4).
## Rain intensity is expressed via initial_velocity / scale / color alpha
## modulation + emitting toggle.
##
## Design: docs/DESIGN/389-dynamic-rain-curtain.md §3
## Formula (PLAN §3.2 确认版):
##   rain = clamp(base + 球速因子 + 波次因子 + 紧张因子 + 事件脉冲 − 喘息, 0.1, 1.0)

const CONSTS = preload("res://gdscripts/constants.gd")

# ── @export tunables (taste-draft window — human-review finalizes) ──
@export var base_intensity: float = CONSTS.RAIN_BASE
@export var smooth_tau: float = CONSTS.RAIN_SMOOTH_TAU

# ── Particle modulation base values (taste-draft candidates, linear default) ──
const BASE_VELOCITY_MIN: float = 800.0
const BASE_VELOCITY_MAX: float = 1200.0
const BASE_SCALE_MIN: float = 0.5
const BASE_SCALE_MAX: float = 1.2
const RAIN_TINT: Color = Color(0.72, 0.84, 1.0, 1.0)
# 事件脉冲指数衰减 τ（~1.5s = 3τ 衰减到近 0，单调递减）
const PULSE_DECAY_TAU: float = 0.5
const EMITTING_THRESHOLD: float = 0.05

# ── State ──
var current_rain: float = CONSTS.RAIN_BASE
var _target_override: float = -1.0   # set_intensity 调试口；< 0 = 公式模式
var _ball_speed: float = CONSTS.BALL_INITIAL_SPEED
var _player_score: int = 0
var _ai_score: int = 0
var _wave_index: int = 0
var _breathing: bool = false
var _pulse_current: float = 0.0

@onready var _particles: GPUParticles2D = $Particles
@onready var _material: ParticleProcessMaterial = _particles.process_material

# ── 契约 API（未来 Issue #384/#385/#386/#388 唯一写入口，禁止直接改 amount）──

func set_wave_factor(wave_index: int) -> void:
	_wave_index = max(wave_index, 0)


func trigger_event_pulse(amount: float) -> void:
	_pulse_current = max(amount, 0.0)


func set_breathing(active: bool) -> void:
	_breathing = active


func set_intensity(value: float) -> void:
	_target_override = value  # < 0 → 回到公式模式


# ── 公式引擎（纯逻辑，headless 可单测）──

func compute_target_rain(speed: float, wave_index: int, pulse: float, breathing: bool, player_score: int, ai_score: int) -> float:
	var speed_factor: float = 0.0
	# NaN 防护 (#287 先例): speed 为 NaN → 因子按 0，回退 base
	if not is_nan(speed) and speed > CONSTS.BALL_INITIAL_SPEED:
		var speed_max: float = CONSTS.BALL_INITIAL_SPEED * CONSTS.BALL_MAX_SPEED_MULTIPLIER
		var speed_range: float = speed_max - CONSTS.BALL_INITIAL_SPEED
		speed_factor = ((speed - CONSTS.BALL_INITIAL_SPEED) / speed_range) * CONSTS.RAIN_SPEED_FACTOR_MAX
		speed_factor = clamp(speed_factor, 0.0, CONSTS.RAIN_SPEED_FACTOR_MAX)
	var wave_factor: float = float(max(wave_index, 0)) * CONSTS.RAIN_WAVE_STEP
	var tension: float = 0.0
	if abs(player_score - ai_score) <= CONSTS.RAIN_TENSION_THRESHOLD:
		tension = CONSTS.RAIN_TENSION_BONUS
	var breathing_drop: float = CONSTS.RAIN_BREATHING_DROP if breathing else 0.0
	var score_band: int = score_band_for(player_score)
	var raw: float = base_intensity + speed_factor + wave_factor + tension \
		+ float(score_band) * CONSTS.RAIN_SCORE_BAND_STEP \
		+ pulse - breathing_drop
	return clamp(raw, CONSTS.RAIN_MIN, CONSTS.RAIN_MAX)


func score_band_for(score: int) -> int:
	# 0-9→0, 10-19→1, 20+→2；负分 → clampi 钳 0；常量单点定义边界
	return clampi(score / CONSTS.RAIN_SCORE_BAND_1,
		0, CONSTS.RAIN_SCORE_BAND_2 / CONSTS.RAIN_SCORE_BAND_1)


func smooth_step(current: float, target: float, delta: float) -> float:
	if delta <= 0.0:
		return current
	var factor: float = 1.0 - exp(-delta / smooth_tau)
	return current + (target - current) * factor


func _compute_target() -> float:
	if _target_override >= 0.0:
		return _target_override
	return compute_target_rain(_ball_speed, _wave_index, _pulse_current, _breathing, _player_score, _ai_score)


# ── 帧更新 ──

func _process(delta: float) -> void:
	_update_inputs(delta)
	var target: float = _compute_target()
	current_rain = smooth_step(current_rain, target, delta)
	_apply_to_particles()


func _update_inputs(delta: float) -> void:
	# 事件脉冲指数衰减回 0（~1.5s 单调递减）
	if delta > 0.0:
		_pulse_current = _pulse_current * exp(-delta / PULSE_DECAY_TAU)
		if _pulse_current < 0.001:
			_pulse_current = 0.0
	# 球速（只读公开属性，NaN 由 compute_target_rain 防护）
	var ball = get_node_or_null("/root/Game/Ball")
	if ball != null:
		var s = ball.get("speed")
		if s != null and typeof(s) == TYPE_FLOAT:
			_ball_speed = s
	# GameManager 比分（只读；lazy autoload → 经场景树解析）
	var gm = get_node_or_null("/root/GameManager")
	if gm != null:
		var ps = gm.get("player_score")
		var ais = gm.get("ai_score")
		if ps != null:
			_player_score = int(ps)
		if ais != null:
			_ai_score = int(ais)


func _apply_to_particles() -> void:
	if _material == null:
		return
	var r: float = current_rain
	var vel_mult: float = 0.6 + 0.8 * r
	var scale_mult: float = 0.5 + 0.7 * r
	_material.initial_velocity_min = BASE_VELOCITY_MIN * vel_mult
	_material.initial_velocity_max = BASE_VELOCITY_MAX * vel_mult
	_material.scale_min = BASE_SCALE_MIN * scale_mult
	_material.scale_max = BASE_SCALE_MAX * scale_mult
	var tint: Color = RAIN_TINT
	tint.a = 0.15 + 0.25 * r
	_material.color = tint
	if _particles != null:
		_particles.emitting = r > EMITTING_THRESHOLD

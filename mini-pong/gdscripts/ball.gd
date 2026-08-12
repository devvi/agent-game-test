extends Area2D
## Ball physics for mini-pong — manual _process movement, wall/paddle collision, scoring, serve.
## Self-contained Area2D: manages velocity, collision responses, and scoring signals.
## 竖屏 (#383): 垂直对打 — Y 出界得分（y<-R→player、y>H+R→ai）、左右墙反弹 X、
## 垂直发球 (sin θ, cos θ·dir)、paddle 反弹读 shape.size.x（长度 120）。

# ── Constants (via GameConstants, non-destructive migration #295) ──
const CONSTS = preload("res://gdscripts/constants.gd")

const INITIAL_SPEED: float = CONSTS.BALL_INITIAL_SPEED
const MAX_SPEED_MULTIPLIER: float = CONSTS.BALL_MAX_SPEED_MULTIPLIER
const SPEED_INCREMENT: float = CONSTS.BALL_SPEED_INCREMENT
const MAX_BOUNCE_ANGLE: float = CONSTS.BALL_MAX_BOUNCE_ANGLE
const SERVE_ANGLE_RANGE: float = CONSTS.BALL_SERVE_ANGLE_RANGE
const FALLBACK_SCREEN_WIDTH: float = float(CONSTS.SCREEN_WIDTH)
const FALLBACK_SCREEN_HEIGHT: float = float(CONSTS.SCREEN_HEIGHT)
const BOUNCE_COOLDOWN_FRAMES: int = 2
const SERVE_DELAY: float = 0.5
const BALL_RADIUS: float = CONSTS.BALL_RADIUS

# ── Exported Variables (tunable in editor) ──
@export var initial_speed: float = INITIAL_SPEED
@export var max_speed_multiplier: float = MAX_SPEED_MULTIPLIER
@export var speed_increment: float = SPEED_INCREMENT
@export var max_bounce_angle: float = MAX_BOUNCE_ANGLE
@export var serve_angle_range: float = SERVE_ANGLE_RANGE
@export var speed_scale: float = 1.0          # #387 缓时: 位移乘数（0.0 冻结，定时恢复）
var _slow_time_remaining: float = 0.0

# ── Signals ──
signal score(side: int)
# side: 0 = player scores (ball exited top past AI), 1 = ai scores (ball exited bottom past player)

# ── State ──
var velocity: Vector2 = Vector2.ZERO
var speed: float = INITIAL_SPEED
var screen_width: float = 0.0
var screen_height: float = 0.0
var _bounce_cooldown: int = 0
var _is_serving: bool = false
var _scored_this_frame: bool = false


func _ready() -> void:
	# Register with balls group — UpgradePool ctx resolution (#387 gap 决议)
	add_to_group("balls")
	# Read viewport dimensions
	var viewport = get_viewport()
	if viewport != null:
		var vs := viewport.get_visible_rect().size
		screen_width = vs.x if vs.x > 0.0 else FALLBACK_SCREEN_WIDTH
		screen_height = vs.y if vs.y > 0.0 else FALLBACK_SCREEN_HEIGHT
	else:
		screen_width = FALLBACK_SCREEN_WIDTH
		screen_height = FALLBACK_SCREEN_HEIGHT

	# Validate CollisionShape2D
	if has_node("CollisionShape2D"):
		var cs := $CollisionShape2D as CollisionShape2D
		if cs != null and cs.shape == null:
			push_error("ball.gd: CollisionShape2D has null shape")

	# Connect collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Connect ScoreZone Area2D area_entered signals (#295)
	# NOTE: ScoreZones are Area2D, ball is Area2D — use area_entered, NOT body_entered.
	# 竖屏 (#383): ScoreZoneTop(顶部)→player 得分(0)；ScoreZoneBottom(底部)→ai 得分(1)
	var parent = get_parent()
	if parent:
		var zone_top := parent.get_node_or_null("ScoreZoneTop")
		if zone_top and zone_top is Area2D:
			zone_top.area_entered.connect(func(a): _on_score_zone(0))
		var zone_bottom := parent.get_node_or_null("ScoreZoneBottom")
		if zone_bottom and zone_bottom is Area2D:
			zone_bottom.area_entered.connect(func(a): _on_score_zone(1))

	# Start first serve
	serve()


func serve() -> void:
	position = Vector2(screen_width / 2.0, screen_height / 2.0)
	speed = initial_speed
	velocity = Vector2.ZERO
	_bounce_cooldown = 0
	_is_serving = true

	# Headless mode: get_tree() returns null (no SceneTree context).
	# Skip the visual serve delay and set velocity immediately.
	var tree = get_tree() if is_inside_tree() else null
	if tree == null:
		var angle_rad := randf_range(-deg_to_rad(SERVE_ANGLE_RANGE), deg_to_rad(SERVE_ANGLE_RANGE))
		var direction: float = 1.0
		if randi() % 2 == 0:
			direction = -1.0
		velocity = Vector2(sin(angle_rad), cos(angle_rad) * direction) * speed
		_is_serving = false
		return

	await tree.create_timer(SERVE_DELAY).timeout

	var angle_rad := randf_range(-deg_to_rad(SERVE_ANGLE_RANGE), deg_to_rad(SERVE_ANGLE_RANGE))
	var direction: float = 1.0
	if randi() % 2 == 0:
		direction = -1.0
	velocity = Vector2(sin(angle_rad), cos(angle_rad) * direction) * speed
	_is_serving = false


func _process(delta: float) -> void:
	if _is_serving:
		return

	# Guard delta: skip abnormal frames (pause / frame spike)
	if delta <= 0.0 or delta > 0.1:
		return

	# Guard NaN velocity
	if is_nan(velocity.x) or is_nan(velocity.y):
		velocity = Vector2.DOWN * speed
		push_warning("ball.gd: NaN velocity detected, resetting")

	# Decrement bounce cooldown
	if _bounce_cooldown > 0:
		_bounce_cooldown -= 1

	# Reset dual-trigger flag at start of each frame (#295)
	_scored_this_frame = false

	# 缓时 (#387): 定时恢复倒计时（不依赖 SceneTreeTimer，headless 可测）
	if _slow_time_remaining > 0.0:
		_slow_time_remaining -= delta
		if _slow_time_remaining <= 0.0:
			speed_scale = 1.0

	# Move ball — re-normalize to prevent drift
	velocity = velocity.normalized() * speed
	position += velocity * delta * speed_scale

	# X boundary safety net (wall bounce fallback, 竖屏左右墙)
	if position.x < -BALL_RADIUS:
		position.x = -BALL_RADIUS
		velocity.x = abs(velocity.x)
	if position.x > screen_width + BALL_RADIUS:
		position.x = screen_width + BALL_RADIUS
		velocity.x = -abs(velocity.x)

	# Y boundary — scoring (fallback dual-trigger guard #295, 竖屏上下得分)
	if position.y < -BALL_RADIUS:
		if not _scored_this_frame:
			score.emit(0)  # Player scores (ball exited top past AI)
			serve()
	elif position.y > screen_height + BALL_RADIUS:
		if not _scored_this_frame:
			score.emit(1)  # AI scores (ball exited bottom past player)
			serve()


func _on_score_zone(side: int) -> void:
	# ScoreZone area_entered handler — primary scoring path (#295)
	if _scored_this_frame:
		return
	_scored_this_frame = true
	score.emit(side)
	serve()


func _on_body_entered(body: Node2D) -> void:
	if _bounce_cooldown > 0:
		return

	if body.is_in_group("walls"):
		velocity.x *= -1.0
		_bounce_cooldown = BOUNCE_COOLDOWN_FRAMES
		if is_instance_valid(AudioEngine):
			AudioEngine.play_wall_bounce()


func _on_area_entered(area: Area2D) -> void:
	if _bounce_cooldown > 0:
		return

	if not area.is_in_group("paddles"):
		return

	# Read paddle length from CollisionShape2D (竖屏: 长度沿 X = size.x), fall back to 120.0
	var paddle_length: float = 120.0
	if area.has_node("CollisionShape2D"):
		var cs := area.get_node("CollisionShape2D") as CollisionShape2D
		if cs != null and cs.shape != null:
			paddle_length = cs.shape.get("size").x

	# Calculate impact offset (沿 X)
	var paddle_center_x := area.global_position.x
	var impact_offset: float = (global_position.x - paddle_center_x) / (paddle_length / 2.0)
	impact_offset = clamp(impact_offset, -1.0, 1.0)

	# Calculate bounce angle
	var bounce_angle_rad: float = deg_to_rad(impact_offset * max_bounce_angle)

	# Determine vertical direction (reverse current direction, 主轴 Y)
	var direction: float = -sign(velocity.y)
	if direction == 0.0:
		direction = 1.0

	# Apply new velocity direction
	velocity = Vector2(sin(bounce_angle_rad), cos(bounce_angle_rad) * direction)
	velocity = velocity.normalized()

	# Speed escalation
	speed = min(speed * speed_increment, initial_speed * max_speed_multiplier)

	# Apply speed
	velocity *= speed

	# Bounce cooldown
	_bounce_cooldown = BOUNCE_COOLDOWN_FRAMES

	# Sound: paddle hit
	if is_instance_valid(AudioEngine):
		AudioEngine.play_paddle_hit()

	# Anti-stick: push ball away from paddle (沿主轴 Y 推离)
	var push_dist := BALL_RADIUS + 10.0 + 2.0  # ball radius + paddle half-thickness + margin
	position.y += sign(velocity.y) * push_dist


## #387 缓时升级入口: 设置速度倍率并启动倒计时；重复施放 = 重置倒计时（可堆叠语义）。
func set_speed_scale_timed(scale: float, duration: float) -> void:
	speed_scale = scale
	_slow_time_remaining = duration

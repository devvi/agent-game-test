extends Area2D
## Ball physics for mini-pong — manual _process movement, wall/paddle collision, scoring, serve.
## Self-contained Area2D: manages velocity, collision responses, and scoring signals.

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

# ── Signals ──
signal score(side: int)
# side: 0 = left scores (ball exited right), 1 = right scores (ball exited left)

# ── State ──
var velocity: Vector2 = Vector2.ZERO
var speed: float = INITIAL_SPEED
var screen_width: float = 0.0
var screen_height: float = 0.0
var _bounce_cooldown: int = 0
var _is_serving: bool = false
var _scored_this_frame: bool = false


func _ready() -> void:
	# Read viewport dimensions
	var viewport := get_viewport()
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

	# Connect ScoreZone Area2D body_entered signals (#295)
	var parent := get_parent()
	if parent:
		var zone_left := parent.get_node_or_null("ScoreZoneLeft")
		if zone_left and zone_left is Area2D:
			zone_left.body_entered.connect(func(_b): _on_score_zone(1))
		var zone_right := parent.get_node_or_null("ScoreZoneRight")
		if zone_right and zone_right is Area2D:
			zone_right.body_entered.connect(func(_b): _on_score_zone(0))

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
		velocity = Vector2(cos(angle_rad) * direction, sin(angle_rad)) * speed
		_is_serving = false
		return

	await tree.create_timer(SERVE_DELAY).timeout

	var angle_rad := randf_range(-deg_to_rad(SERVE_ANGLE_RANGE), deg_to_rad(SERVE_ANGLE_RANGE))
	var direction: float = 1.0
	if randi() % 2 == 0:
		direction = -1.0
	velocity = Vector2(cos(angle_rad) * direction, sin(angle_rad)) * speed
	_is_serving = false


func _process(delta: float) -> void:
	if _is_serving:
		return

	# Guard delta: skip abnormal frames (pause / frame spike)
	if delta <= 0.0 or delta > 0.1:
		return

	# Guard NaN velocity
	if is_nan(velocity.x) or is_nan(velocity.y):
		velocity = Vector2.RIGHT * speed
		push_warning("ball.gd: NaN velocity detected, resetting")

	# Decrement bounce cooldown
	if _bounce_cooldown > 0:
		_bounce_cooldown -= 1

	# Reset dual-trigger flag at start of each frame (#295)
	_scored_this_frame = false

	# Move ball — re-normalize to prevent drift
	velocity = velocity.normalized() * speed
	position += velocity * delta

	# Y boundary safety net (wall bounce fallback)
	if position.y < -BALL_RADIUS:
		position.y = -BALL_RADIUS
		velocity.y = abs(velocity.y)
	if position.y > screen_height + BALL_RADIUS:
		position.y = screen_height + BALL_RADIUS
		velocity.y = -abs(velocity.y)

	# X boundary — scoring (fallback dual-trigger guard #295)
	if position.x < -BALL_RADIUS:
		if not _scored_this_frame:
			score.emit(1)  # Right player scores (ball exited left)
			serve()
	elif position.x > screen_width + BALL_RADIUS:
		if not _scored_this_frame:
			score.emit(0)  # Left player scores (ball exited right)
			serve()


func _on_score_zone(side: int) -> void:
	# ScoreZone body_entered handler — primary scoring path (#295)
	if _scored_this_frame:
		return
	_scored_this_frame = true
	score.emit(side)
	serve()


func _on_body_entered(body: Node2D) -> void:
	if _bounce_cooldown > 0:
		return

	if body.is_in_group("walls"):
		velocity.y *= -1.0
		_bounce_cooldown = BOUNCE_COOLDOWN_FRAMES
		if is_instance_valid(AudioEngine):
			AudioEngine.play_wall_bounce()


func _on_area_entered(area: Area2D) -> void:
	if _bounce_cooldown > 0:
		return

	if not area.is_in_group("paddles"):
		return

	# Read paddle height from CollisionShape2D, fall back to 120.0
	var paddle_height: float = 120.0
	if area.has_node("CollisionShape2D"):
		var cs := area.get_node("CollisionShape2D") as CollisionShape2D
		if cs != null and cs.shape != null:
			paddle_height = cs.shape.get("size").y

	# Calculate impact offset
	var paddle_center_y := area.global_position.y
	var impact_offset: float = (global_position.y - paddle_center_y) / (paddle_height / 2.0)
	impact_offset = clamp(impact_offset, -1.0, 1.0)

	# Calculate bounce angle
	var bounce_angle_rad: float = deg_to_rad(impact_offset * max_bounce_angle)

	# Determine horizontal direction (reverse current direction)
	var direction: float = -sign(velocity.x)
	if direction == 0.0:
		direction = 1.0

	# Apply new velocity direction
	velocity = Vector2(cos(bounce_angle_rad) * direction, sin(bounce_angle_rad))
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

	# Anti-stick: push ball away from paddle
	var push_dist := BALL_RADIUS + 10.0 + 2.0  # ball radius + paddle half-width + margin
	position.x += sign(velocity.x) * push_dist

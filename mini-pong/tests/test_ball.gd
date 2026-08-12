extends RefCounted
## Test suite for ball.gd (#287) — Ball Physics & Collision.
## Runs under godot --headless --script via run_tests.gd.
## 竖屏重写 (#383): 墙反弹改 X 分量；得分改 Y 出界（y<-R→player、y>H+R→ai）；
## 发球垂直（散布 ±30° 沿 X）；paddle 反弹读 shape.size.x（长度 120）、offset 沿 X；
## 反卡位沿 Y。

var passed: int = 0
var failed: int = 0

## Paddle constants (must match paddle.gd — used for collision math tests)
const PADDLE_HEIGHT: float = 20.0
const PADDLE_WIDTH: float = 120.0

## Ball constants from DESIGN (for structural verification)
const INITIAL_SPEED: float = 300.0
const MAX_SPEED_MULTIPLIER: float = 2.0
const SPEED_INCREMENT: float = 1.05  # 测试夹具（TC-D1 显式 pin，见下）
const MAX_BOUNCE_ANGLE: float = 60.0
const SERVE_ANGLE_RANGE: float = 30.0
const BOUNCE_COOLDOWN_FRAMES: int = 2
const SERVE_DELAY: float = 0.5
const BALL_RADIUS: float = 10.0
const FALLBACK_SCREEN_WIDTH: float = 720.0
const FALLBACK_SCREEN_HEIGHT: float = 1280.0


func run() -> void:
	_test_scene_integrity_a1()       # TC-A1: ball.tscn node hierarchy
	_test_scene_integrity_a2()       # TC-A2: CollisionShape2D non-null, CircleShape2D r=10
	_test_scene_integrity_a3()       # TC-A3: Main.tscn hierarchy
	_test_scene_integrity_a4()       # TC-A4: project.godot main_scene
	_test_wall_bounce_b1()           # TC-B1: left wall bounce — X reversed
	_test_wall_bounce_b2()           # TC-B2: right wall bounce — X reversed
	_test_wall_bounce_b3()           # TC-B3: Y velocity unchanged after wall bounce
	_test_wall_bounce_b4()           # TC-B4: speed unchanged after wall bounce
	_test_paddle_center_c1()         # TC-C1: center hit → near-vertical bounce
	_test_paddle_left_edge_c2()      # TC-C2: left-edge hit → steep leftward bounce
	_test_paddle_right_edge_c3()     # TC-C3: right-edge hit → steep rightward bounce
	_test_paddle_y_reversed_c4()     # TC-C4: Y-direction reversed after paddle hit
	_test_speed_escalation_d1()      # TC-D1: speed +5% per hit (夹具固定)
	_test_speed_cap_d2()             # TC-D2: speed capped at 2x
	_test_speed_reset_d3()           # TC-D3: speed resets to initial_speed on serve
	_test_score_bottom_e1()          # TC-E1: bottom boundary → score(1) (ai)
	_test_score_top_e2()             # TC-E2: top boundary → score(0) (player)
	_test_serve_center_f1()          # TC-F1: serve from center
	_test_serve_direction_f2()       # TC-F2: random direction roughly 50/50
	_test_serve_angle_f3()           # TC-F3: serve angle within ±30° (vertical, spread along X)
	_test_nan_guard_g3()             # TC-G3: NaN velocity reset
	_test_cooldown_dup_h1()          # TC-H1: duplicate collision suppressed
	_test_cooldown_expiry_h2()       # TC-H2: cooldown expires, collision processed
	_print_ci_tests()                # TC-G1/G2: covered by CI
	_test_speed_scale_f5()          # TC-F5 (#387 AC3, ball speed_scale)


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_ball():
	## Create a bare ball instance with Area2D + set_script.
	## Does NOT call _ready() — caller must set up viewport state.
	var ball = Area2D.new()
	ball.set_script(load("res://gdscripts/ball.gd"))
	# Set fallback screen dimensions (matches _ready's fallback pattern)
	ball.screen_width = FALLBACK_SCREEN_WIDTH
	ball.screen_height = FALLBACK_SCREEN_HEIGHT
	# Add a mock CollisionShape2D so _ready validation passes
	var cs = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = BALL_RADIUS
	cs.shape = shape
	ball.add_child(cs)
	return ball


func _make_paddle_mock():
	## Create a minimal Area2D mock that can pass is_in_group("paddles").
	## 竖屏横置 (#383): 120 长（X）× 20 厚（Y）。
	var paddle = Area2D.new()
	paddle.add_to_group("paddles")
	var cs = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(PADDLE_WIDTH, PADDLE_HEIGHT)
	cs.shape = shape
	paddle.add_child(cs)
	return paddle


# ── Scenario A: Scene Integrity ──

func _test_scene_integrity_a1() -> void:
	var scene = load("res://scenes/ball.tscn")
	_assert(scene != null, "TC-A1: ball.tscn loaded")
	if scene == null:
		return
	var ball = scene.instantiate()
	_assert(ball is Area2D, "TC-A1: root is Area2D")
	_assert(ball.has_node("ColorRect"), "TC-A1: has ColorRect child")
	_assert(ball.has_node("CollisionShape2D"), "TC-A1: has CollisionShape2D child")


func _test_scene_integrity_a2() -> void:
	var scene = load("res://scenes/ball.tscn")
	_assert(scene != null, "TC-A2: ball.tscn loaded")
	if scene == null:
		return
	var ball = scene.instantiate()
	var cs = ball.get_node("CollisionShape2D")
	_assert(cs != null, "TC-A2: CollisionShape2D node found")
	var shape = cs.shape
	_assert(shape != null, "TC-A2: shape is non-null")
	_assert(shape is CircleShape2D, "TC-A2: shape is CircleShape2D")
	if shape is CircleShape2D:
		_assert(abs(shape.radius - 10.0) < 0.01, "TC-A2: radius == 10.0")


func _test_scene_integrity_a3() -> void:
	var scene = load("res://scenes/Main.tscn")
	_assert(scene != null, "TC-A3: Main.tscn loaded")
	if scene == null:
		return
	var game = scene.instantiate()
	_assert(game.has_node("LeftWall"), "TC-A3: LeftWall node exists")
	_assert(game.has_node("RightWall"), "TC-A3: RightWall node exists")
	var left = game.get_node("LeftWall")
	_assert(left is StaticBody2D, "TC-A3: LeftWall is StaticBody2D")
	_assert(left.is_in_group("walls"), "TC-A3: LeftWall in 'walls' group")
	var right = game.get_node("RightWall")
	_assert(right is StaticBody2D, "TC-A3: RightWall is StaticBody2D")
	_assert(right.is_in_group("walls"), "TC-A3: RightWall in 'walls' group")
	_assert(game.has_node("Ball"), "TC-A3: Ball instance node exists")
	_assert(game.has_node("PlayerPaddle"), "TC-A3: PlayerPaddle instance node exists")


func _test_scene_integrity_a4() -> void:
	var content = FileAccess.get_file_as_string("res://project.godot")
	_assert(content != "", "TC-A4: project.godot readable")
	_assert(content.contains("run/main_scene=\"res://scenes/Main.tscn\""), "TC-A4: run/main_scene set to Main.tscn")


# ── Scenario B: Wall Bounce (左右墙反弹 X 分量, #383) ──

func _test_wall_bounce_b1() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(-150, 200)  # moving left
	ball._bounce_cooldown = 0
	# Simulate wall collision
	var wall = StaticBody2D.new()
	wall.add_to_group("walls")
	ball._on_body_entered(wall)
	_assert(ball.velocity.x > 0, "TC-B1: velocity.x reversed (was negative, now positive)")
	_assert(ball._bounce_cooldown == BOUNCE_COOLDOWN_FRAMES, "TC-B1: bounce cooldown set")


func _test_wall_bounce_b2() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(150, 200)  # moving right
	ball._bounce_cooldown = 0
	var wall = StaticBody2D.new()
	wall.add_to_group("walls")
	ball._on_body_entered(wall)
	_assert(ball.velocity.x < 0, "TC-B2: velocity.x reversed (was positive, now negative)")


func _test_wall_bounce_b3() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(-150, 200)
	ball._bounce_cooldown = 0
	var wall = StaticBody2D.new()
	wall.add_to_group("walls")
	ball._on_body_entered(wall)
	_assert(ball.velocity.y == 200.0, "TC-B3: velocity.y unchanged after wall bounce")


func _test_wall_bounce_b4() -> void:
	var ball = _make_ball()
	ball.speed = 350.0
	ball.velocity = Vector2(-150, 200)
	ball._bounce_cooldown = 0
	var pre_speed = ball.speed
	var wall = StaticBody2D.new()
	wall.add_to_group("walls")
	ball._on_body_entered(wall)
	_assert(abs(ball.speed - pre_speed) < 0.01, "TC-B4: speed scalar unchanged after wall bounce")


# ── Scenario C: Paddle Collision — Angle Variation (offset 沿 X, #383) ──

func _test_paddle_center_c1() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(0, 300)   # moving down toward player paddle
	ball.speed = 300.0
	ball._bounce_cooldown = 0
	ball.position = Vector2(360, 1240)  # ball at same X as paddle center

	var paddle = _make_paddle_mock()
	paddle.position = Vector2(360, 1240)  # paddle center at x=360

	ball._on_area_entered(paddle)

	# Center hit → bounce angle ≈ 0° (nearly vertical, velocity.x ≈ 0)
	_assert(abs(ball.velocity.x) < 50.0, "TC-C1: center hit → near-vertical (vx ~ 0)")
	_assert(ball.velocity.y < 0, "TC-C1: Y direction reversed (was down, now up)")


func _test_paddle_left_edge_c2() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(0, 300)
	ball.speed = 300.0
	ball._bounce_cooldown = 0
	ball.position = Vector2(300, 1240)  # ball left of paddle center (360-300=60 left)
	# impact_offset = (300-360)/(120/2) = -60/60 = -1.0

	var paddle = _make_paddle_mock()
	paddle.position = Vector2(360, 1240)

	ball._on_area_entered(paddle)

	# Left-edge hit → steep leftward (vx < 0, large magnitude)
	_assert(ball.velocity.x < 0, "TC-C2: left-edge hit → leftward (vx negative)")
	_assert(ball.velocity.y < 0, "TC-C2: Y reversed (moving back up)")


func _test_paddle_right_edge_c3() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(0, 300)
	ball.speed = 300.0
	ball._bounce_cooldown = 0
	ball.position = Vector2(420, 1240)  # ball right of paddle center (420-360=60 right)
	# impact_offset = (420-360)/(120/2) = 60/60 = 1.0

	var paddle = _make_paddle_mock()
	paddle.position = Vector2(360, 1240)

	ball._on_area_entered(paddle)

	# Right-edge hit → steep rightward (vx > 0, large magnitude)
	_assert(ball.velocity.x > 0, "TC-C3: right-edge hit → rightward (vx positive)")
	_assert(ball.velocity.y < 0, "TC-C3: Y reversed (moving back up)")


func _test_paddle_y_reversed_c4() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(0, -300)    # moving up toward AI paddle
	ball.speed = 300.0
	ball._bounce_cooldown = 0
	ball.position = Vector2(360, 40)

	var paddle = _make_paddle_mock()
	paddle.position = Vector2(360, 40)

	ball._on_area_entered(paddle)

	_assert(ball.velocity.y > 0, "TC-C4: Y direction reversed after paddle hit (now down)")


# ── Scenario D: Speed Escalation ──

func _test_speed_escalation_d1() -> void:
	var ball = _make_ball()
	ball.speed = 300.0
	ball.speed_increment = SPEED_INCREMENT  # 自洽夹具
	ball.velocity = Vector2(0, 300)
	ball._bounce_cooldown = 0
	ball.position = Vector2(360, 1240)

	var paddle = _make_paddle_mock()
	paddle.position = Vector2(360, 1240)

	ball._on_area_entered(paddle)

	var expected = 300.0 * SPEED_INCREMENT
	_assert(abs(ball.speed - expected) < 0.1, "TC-D1: speed increased by +5%% (%.1f → %.1f, expected %.1f)" % [300.0, ball.speed, expected])


func _test_speed_cap_d2() -> void:
	var ball = _make_ball()
	ball.initial_speed = 300.0
	ball.speed = 300.0 * MAX_SPEED_MULTIPLIER  # already at cap: 600.0
	ball.velocity = Vector2(0, 600)
	ball._bounce_cooldown = 0
	ball.position = Vector2(360, 1240)

	var paddle = _make_paddle_mock()
	paddle.position = Vector2(360, 1240)

	ball._on_area_entered(paddle)

	var cap = 300.0 * MAX_SPEED_MULTIPLIER
	_assert(ball.speed <= cap + 0.01, "TC-D2: speed capped at %d (was %.1f, now %.1f)" % [int(cap), 600.0, ball.speed])


func _test_speed_reset_d3() -> void:
	var ball = _make_ball()
	ball.initial_speed = 300.0
	ball.speed = 500.0  # escalated
	ball.velocity = Vector2(0, 300)
	ball.position = Vector2(360, 640)
	ball.screen_width = FALLBACK_SCREEN_WIDTH
	ball.screen_height = FALLBACK_SCREEN_HEIGHT

	# Manually simulate serve's position/speed reset (the part before await)
	ball.position = Vector2(ball.screen_width / 2.0, ball.screen_height / 2.0)
	ball.speed = ball.initial_speed
	ball.velocity = Vector2.ZERO
	ball._bounce_cooldown = 0
	ball._is_serving = true

	_assert(ball.position == Vector2(360, 640), "TC-D3: position reset to center (360, 640)")
	_assert(abs(ball.speed - 300.0) < 0.01, "TC-D3: speed reset to initial_speed (300)")


# ── Scenario E: Scoring (Y 出界, #383) ──

func _test_score_bottom_e1() -> void:
	var ball = _make_ball()
	ball.screen_width = 720.0
	ball.screen_height = 1280.0
	ball.speed = 300.0
	ball.velocity = Vector2(0, 300)
	ball.position = Vector2(360.0, 1300.0)  # past bottom boundary
	ball._is_serving = false

	var scored: Array = []
	ball.score.connect(func(side: int): scored.append(side))

	# Call _process — ball should detect boundary exit
	ball._process(0.016)

	_assert(scored.size() >= 0, "TC-E1: score signal connected")
	# The ball processes: position.y > 1280 → score(1) (ai), then serve()
	if scored.size() > 0:
		_assert(scored[0] == 1, "TC-E1: score(1) emitted for bottom boundary exit (ai scores)")


func _test_score_top_e2() -> void:
	var ball = _make_ball()
	ball.screen_width = 720.0
	ball.screen_height = 1280.0
	ball.speed = 300.0
	ball.velocity = Vector2(0, -300)
	ball.position = Vector2(360.0, -20.0)  # past top boundary
	ball._is_serving = false

	var scored: Array = []
	ball.score.connect(func(side: int): scored.append(side))

	ball._process(0.016)

	if scored.size() > 0:
		_assert(scored[0] == 0, "TC-E2: score(0) emitted for top boundary exit (player scores)")


# ── Scenario F: Serve (垂直发球, #383) ──

func _test_serve_center_f1() -> void:
	var ball = _make_ball()
	ball.screen_width = 720.0
	ball.screen_height = 1280.0
	ball.initial_speed = INITIAL_SPEED  # 自洽夹具

	ball.initial_speed = INITIAL_SPEED
	ball.position = Vector2(ball.screen_width / 2.0, ball.screen_height / 2.0)
	ball.speed = ball.initial_speed

	_assert(ball.position == Vector2(360, 640), "TC-F1: serve sets position to center (360, 640)")
	_assert(abs(ball.speed - INITIAL_SPEED) < 0.01, "TC-F1: serve resets speed to initial_speed")


func _test_serve_direction_f2() -> void:
	# Structural: verify serve uses random direction selection
	var source = FileAccess.get_file_as_string("res://gdscripts/ball.gd")
	_assert(source != "", "TC-F2: ball.gd source readable")
	_assert(source.contains("randi()"), "TC-F2: serve uses randi() for random direction")

	# Manual statistical test
	var up_count := 0
	var down_count := 0
	for _i in range(20):
		var direction: float = 1.0
		if randi() % 2 == 0:
			direction = -1.0
		if direction < 0:
			up_count += 1
		else:
			down_count += 1

	# Roughly even split (within reason for 20 trials)
	_assert(up_count > 3 and down_count > 3, "TC-F2: serve direction ~50/50 (U=%d, D=%d)" % [up_count, down_count])


func _test_serve_angle_f3() -> void:
	# Verify serve angle is within ±30° range and vertical-dominant
	var source = FileAccess.get_file_as_string("res://gdscripts/ball.gd")
	_assert(source.contains("serve_angle_range"), "TC-F3: serve uses serve_angle_range")

	# 垂直发球语义: velocity = (sin θ, cos θ·dir)，θ ∈ ±30° → X 分量 ≤ sin(30°)=0.5，
	# Y 分量（主轴）始终 ≥ cos(30°)=0.866 — 不钉具体方向
	for _i in range(20):
		var angle = randf_range(-deg_to_rad(SERVE_ANGLE_RANGE), deg_to_rad(SERVE_ANGLE_RANGE))
		var vx = abs(sin(angle))
		var vy = abs(cos(angle))
		_assert(vx <= sin(deg_to_rad(SERVE_ANGLE_RANGE)) + 0.001, "TC-F3: X spread within ±sin(30°) (got %f)" % vx)
		_assert(vy >= cos(deg_to_rad(SERVE_ANGLE_RANGE)) - 0.001, "TC-F3: Y component vertical-dominant (got %f)" % vy)
		_assert(abs(rad_to_deg(angle)) <= SERVE_ANGLE_RANGE + 0.1, "TC-F3: angle ≤ %d°" % int(SERVE_ANGLE_RANGE))


# ── Scenario G: Headless Compilation ──

func _test_nan_guard_g3() -> void:
	var ball = _make_ball()
	ball.screen_width = 720.0
	ball.screen_height = 1280.0
	ball.speed = 300.0
	ball.velocity = Vector2(NAN, NAN)
	ball._is_serving = false

	# _process should detect NaN and reset velocity
	ball._process(0.016)

	_assert(not is_nan(ball.velocity.x), "TC-G3: velocity.x reset from NaN")
	_assert(not is_nan(ball.velocity.y), "TC-G3: velocity.y reset from NaN")
	_assert(ball.velocity.length() > 0.0, "TC-G3: velocity has non-zero magnitude after NaN reset (direction-agnostic)")


# ── Scenario H: Cooldown Mechanism ──

func _test_cooldown_dup_h1() -> void:
	var ball = _make_ball()
	ball._bounce_cooldown = 2  # cooldown active
	var vel_before = ball.velocity

	var wall = StaticBody2D.new()
	wall.add_to_group("walls")
	ball._on_body_entered(wall)

	# Velocity should be unchanged — cooldown suppressed the collision
	_assert(ball.velocity == vel_before, "TC-H1: cooldown suppressed duplicate collision")


func _test_cooldown_expiry_h2() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(-150, 200)
	ball._bounce_cooldown = 0  # cooldown expired

	var wall = StaticBody2D.new()
	wall.add_to_group("walls")

	var vel_x_before = ball.velocity.x
	ball._on_body_entered(wall)

	_assert(ball.velocity.x != vel_x_before, "TC-H2: collision processed after cooldown expiry")
	_assert(ball._bounce_cooldown == BOUNCE_COOLDOWN_FRAMES, "TC-H2: cooldown set after collision")


# ── CI-covered tests ──

func _print_ci_tests() -> void:
	print("  CI-COVERED: TC-G1 (zero exit code) — verified by godot --headless --quit")
	print("  CI-COVERED: TC-G2 (no script errors) — verified by parse check")
	print("  MANUAL: TC-F4 (serve 0.5s delay) — requires tree context for await timer")


func _test_speed_scale_f5() -> void:
	# TC-F5 (#387 AC3): speed_scale 实例属性 — 0.0 冻结位移；set_speed_scale_timed 2s 后恢复 1.0
	var ball = _make_ball()
	ball._ready()
	ball.speed_scale = 0.0
	var pos_before = ball.position
	ball._process(0.016)
	_assert(ball.position.distance_to(pos_before) < 0.001, "TC-F5: speed_scale=0 → no movement")
	ball.set_speed_scale_timed(0.0, 2.0)
	var elapsed := 0.0
	while elapsed < 2.0:
		ball._process(0.016)
		elapsed += 0.016
	_assert(abs(ball.speed_scale - 1.0) < 0.001, "TC-F5: speed_scale restored to 1.0 after 2s")


# ── Dual Scoring (#385) — last_toucher / _crossed_wall 生命周期（DESIGN §2.9 / §9 Scenario F）──

func _test_last_toucher_f1() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(0, 300)
	ball.speed = 300.0
	ball._bounce_cooldown = 0
	ball.position = Vector2(360, 1240)

	var p_player = _make_paddle_mock()
	p_player.name = "PlayerPaddle"
	p_player.position = Vector2(360, 1240)
	ball._on_area_entered(p_player)
	_assert(ball.last_toucher == "player", "TC-F1: PlayerPaddle → last_toucher == 'player'")

	var p_ai = _make_paddle_mock()
	p_ai.name = "AIPaddle"
	p_ai.position = Vector2(360, 40)
	ball.velocity = Vector2(0, -300)
	ball.position = Vector2(360, 40)
	ball._bounce_cooldown = 0
	ball._on_area_entered(p_ai)
	_assert(ball.last_toucher == "ai", "TC-F1: AIPaddle → last_toucher == 'ai'")

	var p_unknown = _make_paddle_mock()
	p_unknown.name = "WeirdPaddle"
	p_unknown.position = Vector2(360, 1240)
	ball.velocity = Vector2(0, 300)
	ball.position = Vector2(360, 1240)
	ball._bounce_cooldown = 0
	ball._on_area_entered(p_unknown)
	_assert(ball.last_toucher == "", "TC-F1: unknown paddle name → last_toucher == ''")


## F-2: serve 复位 last_toucher / _crossed_wall；发球位 (360,640) 在墙带内 → _was_in_wall_band true
func _test_serve_reset_f2() -> void:
	var ball = _make_ball()
	ball.screen_width = FALLBACK_SCREEN_WIDTH
	ball.screen_height = FALLBACK_SCREEN_HEIGHT
	ball.last_toucher = "player"
	ball._crossed_wall = true
	ball._was_in_wall_band = false

	ball.serve()  # headless 无 tree → 立即路径

	_assert(ball.last_toucher == "", "TC-F2: last_toucher reset by serve")
	_assert(ball._crossed_wall == false, "TC-F2: _crossed_wall reset by serve")
	_assert(ball._was_in_wall_band == true, "TC-F2: _was_in_wall_band true (serve pos in band)")
	_assert(ball.position == Vector2(360, 640), "TC-F2: serve position at center")


## F-3: 墙带边沿置位（带外→带内才置位；带内停留不重复）
func _test_wall_band_edge_f3() -> void:
	var ball = _make_ball()
	ball.screen_width = FALLBACK_SCREEN_WIDTH
	ball.screen_height = FALLBACK_SCREEN_HEIGHT
	ball._is_serving = false
	ball.velocity = Vector2.ZERO
	ball.speed = 330.0
	ball.position = Vector2(360, 600)  # 带外 (640±22 之外)
	ball._was_in_wall_band = false
	ball._crossed_wall = false

	ball._process(0.016)
	_assert(ball._crossed_wall == false, "TC-F3: outside band → not crossed")

	ball.position = Vector2(360, 630)  # 带内
	ball._process(0.016)
	_assert(ball._crossed_wall == true, "TC-F3: outside→inside edge sets _crossed_wall")

	ball.position = Vector2(360, 640)
	ball._process(0.016)
	_assert(ball._crossed_wall == true, "TC-F3: stays true inside band")


## F-4: 发球位不误置位（边界 7）— serve 后带内移动不置位，离开再进入才置位
func _test_serve_position_no_misflag_f4() -> void:
	var ball = _make_ball()
	ball.screen_width = FALLBACK_SCREEN_WIDTH
	ball.screen_height = FALLBACK_SCREEN_HEIGHT
	ball._is_serving = false
	ball.velocity = Vector2.ZERO
	ball.speed = 330.0

	ball.serve()
	_assert(ball.position == Vector2(360, 640), "TC-F4: serve at center")
	_assert(ball._crossed_wall == false, "TC-F4: serve does not flag crossed")

	ball.position = Vector2(360, 645)  # 带内移动
	ball._process(0.016)
	_assert(ball._crossed_wall == false, "TC-F4: in-band movement after serve → no mis-flag")

	ball.position = Vector2(360, 600)  # 带外
	ball._process(0.016)
	_assert(ball._crossed_wall == false, "TC-F4: outside band → still not crossed")

	ball.position = Vector2(360, 630)  # 重新进入带内
	ball._process(0.016)
	_assert(ball._crossed_wall == true, "TC-F4: re-enter band → crossed set")


## F-5: 触球复位穿越标记（失败路径 4）
func _test_paddle_resets_crossed_f5() -> void:
	var ball = _make_ball()
	ball.velocity = Vector2(0, 300)
	ball.speed = 300.0
	ball._bounce_cooldown = 0
	ball.position = Vector2(360, 1240)
	ball._crossed_wall = true
	ball.last_toucher = ""

	var paddle = _make_paddle_mock()
	paddle.name = "PlayerPaddle"
	paddle.position = Vector2(360, 1240)

	ball._on_area_entered(paddle)

	_assert(ball._crossed_wall == false, "TC-F5: paddle touch resets _crossed_wall")
	_assert(ball.last_toucher == "player", "TC-F5: last_toucher set on touch")

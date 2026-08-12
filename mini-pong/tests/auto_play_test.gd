extends RefCounted
## Auto-Play Test — 100-round AI-vs-AI simulation.
## Verifies: no crash, scores reach 5, best-of-3 logic, winner exists, restart works.
## Uses manual physics simulation + manual collision detection for CPU-speed execution
## (avoids SceneTree timer awaits that would take minutes per match).
##
## Run via run_tests.gd:
##   godot --path mini-pong/ --headless --script tests/run_tests.gd
##
## 竖屏重写 (#383): SCREEN_W=720/SCREEN_H=1280；左右墙反弹 X；上下得分区 Y；
## 挡板上下分列沿 X 移动；AI 追踪 X 轴。FSM/scoring 信号链不变。
##
## Design: docs/DESIGN/297-ai-auto-play-test.md — Approach C (minimal test scene).
## Parent Issue: #297

var passed: int = 0
var failed: int = 0

# ── Test parameters (竖屏 720x1280, #383) ──
const MATCH_COUNT: int = 100
const MAX_FRAMES_PER_MATCH: int = 100000
const SCREEN_W: float = 720.0
const SCREEN_H: float = 1280.0
const FIXED_DELTA: float = 1.0 / 60.0

# Increased AI error for test: ensures matches complete in reasonable frame counts.
const TEST_AI_POSITION_ERROR: float = 60.0

const _CONSTS = preload("res://gdscripts/constants.gd")
const POINTS_TO_WIN: int = _CONSTS.POINTS_TO_WIN_GAME
const GAMES_TO_WIN: int = _CONSTS.GAMES_TO_WIN_MATCH
const BALL_R: float = _CONSTS.BALL_RADIUS
const PADDLE_HW: float = _CONSTS.PADDLE_WIDTH / 2.0   # 60 (半长)
const PADDLE_HH: float = _CONSTS.PADDLE_HEIGHT / 2.0  # 10 (半厚)
const PADDLE_X_MIN: float = PADDLE_HW
const PADDLE_X_MAX: float = SCREEN_W - PADDLE_HW
const WALL_X_LEFT: float = 10.0
const WALL_X_RIGHT: float = SCREEN_W - 10.0
const PADDLE_Y_TOP: float = 50.0
const PADDLE_Y_BOT: float = SCREEN_H - 50.0

# ── Stats ──
var _timeouts: int = 0
var _crashes: int = 0
var _total_frames: int = 0


func run() -> void:
	print("\n=== Auto-Play Test: %d Matches (AI vs AI) ===" % MATCH_COUNT)
	print("  POINTS_TO_WIN_GAME=%d  GAMES_TO_WIN_MATCH=%d" % [POINTS_TO_WIN, GAMES_TO_WIN])
	print("  MAX_FRAMES_PER_MATCH=%d  FIXED_DELTA=%.4f" % [MAX_FRAMES_PER_MATCH, FIXED_DELTA])
	print("  TEST_AI_POSITION_ERROR=%.1f  SCREEN=%dx%d" % [TEST_AI_POSITION_ERROR, int(SCREEN_W), int(SCREEN_H)])

	var tree := Engine.get_main_loop() as SceneTree
	var gm: Node = tree.root.get_node("GameManager")

	# ── Build minimal test scene (竖屏: 左右墙 + 上下挡板) ──
	var ball: Area2D = _spawn_ball(tree)
	var left_wall: StaticBody2D = _spawn_wall(tree, "LeftWall", 5.0, SCREEN_H / 2.0)
	var right_wall: StaticBody2D = _spawn_wall(tree, "RightWall", SCREEN_W - 5.0, SCREEN_H / 2.0)
	var p_bottom: Area2D = _spawn_paddle(tree, "PlayerPaddle", Vector2(SCREEN_W / 2.0, PADDLE_Y_BOT))
	var p_top: Area2D = _spawn_paddle(tree, "AIPaddle", Vector2(SCREEN_W / 2.0, PADDLE_Y_TOP))
	var sm: Node = _spawn_scoring_manager(tree)

	# Fix headless viewport dimensions
	ball.screen_width = SCREEN_W
	ball.screen_height = SCREEN_H
	ball.position = Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0)
	p_bottom.min_x = PADDLE_X_MIN; p_bottom.max_x = PADDLE_X_MAX
	p_top.min_x = PADDLE_X_MIN; p_top.max_x = PADDLE_X_MAX

	# Increase AI position error for test: prevents infinite rallies
	p_bottom.ai_position_error = TEST_AI_POSITION_ERROR
	p_top.ai_position_error = TEST_AI_POSITION_ERROR

	# Wait for _ready callbacks (signal connections)
	for _i in range(5):
		await tree.process_frame

	# Re-assert after _ready may have modified
	ball.screen_width = SCREEN_W
	ball.screen_height = SCREEN_H

	var start_ms := Time.get_ticks_msec()

	for m in range(MATCH_COUNT):
		var ok: bool = _run_single_match(m, ball, left_wall, right_wall, p_bottom, p_top, sm, gm)
		if ok:
			passed += 1
		else:
			failed += 1

	var elapsed := Time.get_ticks_msec() - start_ms

	_print_summary(elapsed)

	# Cleanup test nodes
	for name in ["Ball", "PlayerPaddle", "AIPaddle", "LeftWall", "RightWall", "ScoringManager"]:
		var n := tree.root.get_node_or_null(name)
		if n != null:
			tree.root.remove_child(n)
			n.queue_free()


# ── Factories ──

func _spawn_ball(tree: SceneTree) -> Area2D:
	var ball: Area2D = load("res://scenes/ball.tscn").instantiate()
	ball.name = "Ball"
	tree.root.add_child(ball)
	return ball


func _spawn_wall(tree: SceneTree, wname: String, wx: float, wy: float) -> StaticBody2D:
	var w := StaticBody2D.new()
	w.name = wname
	w.position = Vector2(wx, wy)
	w.add_to_group("walls")
	var cs := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(10.0, SCREEN_H)  # 竖屏: 左右墙 10 厚 × 1280 长
	cs.shape = s
	w.add_child(cs)
	tree.root.add_child(w)
	return w


func _spawn_paddle(tree: SceneTree, pname: String, pos: Vector2) -> Area2D:
	var paddle: Area2D = load("res://scenes/player_paddle.tscn").instantiate()
	paddle.name = pname
	paddle.position = pos
	paddle.mode = 1  # Mode.AI
	tree.root.add_child(paddle)
	return paddle


func _spawn_scoring_manager(tree: SceneTree) -> Node:
	var sm := Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.name = "ScoringManager"
	tree.root.add_child(sm)
	return sm


# ── Match runner ──

func _run_single_match(midx: int, ball: Area2D, left_wall: StaticBody2D, right_wall: StaticBody2D, p_bottom: Area2D, p_top: Area2D, sm: Node, gm: Node) -> bool:
	_reset_match_state(ball, p_bottom, p_top, sm, gm)

	var game_letters: Array[String] = []
	var _on_game := func(w: String):
		game_letters.append(w)
	gm.game_won.connect(_on_game)

	_serve_fast(ball)

	var frame: int = 0
	var winner: String = ""

	while winner.is_empty() and frame < MAX_FRAMES_PER_MATCH:
		_simulate_frame(ball, left_wall, right_wall, p_bottom, p_top, FIXED_DELTA)
		frame += 1

		if is_nan(ball.velocity.x) or is_nan(ball.velocity.y):
			printerr("Match %03d: NaN velocity at frame %d — ABORT" % [midx + 1, frame])
			_crashes += 1
			_total_frames += frame
			gm.game_won.disconnect(_on_game)
			return false

		if gm.player_games_won >= GAMES_TO_WIN:
			winner = "player"
		elif gm.ai_games_won >= GAMES_TO_WIN:
			winner = "ai"

	gm.game_won.disconnect(_on_game)
	_total_frames += frame

	if frame >= MAX_FRAMES_PER_MATCH:
		_timeouts += 1
		print("Match %03d: TIMEOUT after %d frames (p=%d a=%d g=%d-%d) ❌" % [
			midx + 1, frame, gm.player_score, gm.ai_score, gm.player_games_won, gm.ai_games_won
		])
		return false

	var ok: bool = true
	var errors: Array[String] = []

	if winner not in ["player", "ai"]:
		errors.append("invalid winner '%s'" % winner)
		ok = false

	var wgames: int = gm.player_games_won if winner == "player" else gm.ai_games_won
	if wgames < GAMES_TO_WIN:
		errors.append("winner has only %d games (need >= %d)" % [wgames, GAMES_TO_WIN])
		ok = false

	var lgames: int = gm.ai_games_won if winner == "player" else gm.player_games_won
	if lgames >= GAMES_TO_WIN:
		errors.append("loser also has >= %d games" % GAMES_TO_WIN)
		ok = false

	if game_letters.size() < GAMES_TO_WIN:
		errors.append("only %d game_won signals (need >= %d)" % [game_letters.size(), GAMES_TO_WIN])
		ok = false

	var sm_games: int = sm.player_games + sm.ai_games
	var gm_games: int = gm.player_games_won + gm.ai_games_won
	if sm_games != gm_games:
		errors.append("SM games(%d) != GM games(%d)" % [sm_games, gm_games])
		ok = false

	# 竖屏: 挡板沿 X 移动，越界检查 X ∈ [0, SCREEN_W]
	if p_bottom.position.x < 0.0 or p_bottom.position.x > SCREEN_W:
		errors.append("bottom paddle OOB x=%.1f" % p_bottom.position.x)
		ok = false
	if p_top.position.x < 0.0 or p_top.position.x > SCREEN_W:
		errors.append("top paddle OOB x=%.1f" % p_top.position.x)
		ok = false

	var total_games: int = gm.player_games_won + gm.ai_games_won
	var gstr := _fmt_games(game_letters)
	var icon := "✅" if ok else "❌"
	print("Match %03d: %s wins — %d games %s [%d frames] %s" % [
		midx + 1, winner.capitalize(), total_games, gstr, frame, icon
	])

	for e in errors:
		print("         └─ %s" % e)

	return ok


# ── Physics simulation (竖屏语义, #383) ──

func _simulate_frame(ball: Area2D, left_wall: StaticBody2D, right_wall: StaticBody2D, p_bottom: Area2D, p_top: Area2D, delta: float) -> void:
	# ── Manual ball physics (avoids ball._process which calls serve()→await) ──
	if not ball._is_serving:
		# Normalize velocity to prevent drift
		if not is_nan(ball.velocity.x) and not is_nan(ball.velocity.y):
			var vlen: float = ball.velocity.length()
			if vlen > 0.0:
				ball.velocity = ball.velocity.normalized() * ball.speed
		else:
			ball.velocity = Vector2.DOWN * ball.speed

		# Decay bounce cooldown
		if ball._bounce_cooldown > 0:
			ball._bounce_cooldown -= 1

		# Predict next position
		var bx: float = ball.position.x
		var by: float = ball.position.y
		var nx: float = bx + ball.velocity.x * delta
		var ny: float = by + ball.velocity.y * delta

		# Collision detection (before applying position)
		if ball._bounce_cooldown <= 0:
			# Wall collision (左右墙)
			if nx - BALL_R <= WALL_X_LEFT:
				ball._on_body_entered(left_wall)
			elif nx + BALL_R >= WALL_X_RIGHT:
				ball._on_body_entered(right_wall)

			# Paddle collision (circle vs AABB) — 挡板上下分列、沿 X 移动
			for pdata in [[p_top, PADDLE_Y_TOP], [p_bottom, PADDLE_Y_BOT]]:
				var p: Area2D = pdata[0]
				var py: float = pdata[1]
				var px: float = p.position.x
				var cx: float = clamp(nx, px - PADDLE_HW, px + PADDLE_HW)
				var cy: float = clamp(ny, py - PADDLE_HH, py + PADDLE_HH)
				var dx: float = nx - cx
				var dy: float = ny - cy
				if dx * dx + dy * dy < BALL_R * BALL_R:
					ball._on_area_entered(p)

		# Apply position (collision handlers modified velocity)
		ball.position = Vector2(nx, ny)
		bx = ball.position.x
		by = ball.position.y

		# X boundary safety net (左右墙反弹 fallback)
		if bx < -BALL_R:
			ball.position.x = -BALL_R
			ball.velocity.x = abs(ball.velocity.x)
		elif bx > SCREEN_W + BALL_R:
			ball.position.x = SCREEN_W + BALL_R
			ball.velocity.x = -abs(ball.velocity.x)

		# Y boundary scoring (上下出界得分)
		if by < -BALL_R:
			if not ball._scored_this_frame:
				ball.score.emit(0)  # Player scores (ball exited top past AI)
				ball._scored_this_frame = true
			_serve_fast(ball)
		elif by > SCREEN_H + BALL_R:
			if not ball._scored_this_frame:
				ball.score.emit(1)  # AI scores (ball exited bottom past player)
				ball._scored_this_frame = true
			_serve_fast(ball)

	# ── Paddle AI ──
	p_bottom._process(delta)
	p_top._process(delta)


# ── State helpers ──

func _reset_match_state(ball: Area2D, p_bottom: Area2D, p_top: Area2D, sm: Node, gm: Node) -> void:
	gm.reset_match()
	sm.player_score = 0
	sm.ai_score = 0
	sm.player_games = 0
	sm.ai_games = 0
	sm._is_match_over = false

	ball.screen_width = SCREEN_W
	ball.screen_height = SCREEN_H
	ball.position = Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0)
	ball.speed = ball.initial_speed
	ball.velocity = Vector2.ZERO
	ball._bounce_cooldown = 0
	ball._is_serving = false

	p_bottom.position = Vector2(SCREEN_W / 2.0, PADDLE_Y_BOT)
	p_top.position = Vector2(SCREEN_W / 2.0, PADDLE_Y_TOP)
	p_bottom._ai_delay_timer = randf_range(p_bottom.ai_reaction_delay_min, p_bottom.ai_reaction_delay_max)
	p_top._ai_delay_timer = randf_range(p_top.ai_reaction_delay_min, p_top.ai_reaction_delay_max)


func _serve_fast(ball: Area2D) -> void:
	ball.position = Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0)
	ball.speed = ball.initial_speed
	ball.velocity = Vector2.ZERO
	ball._bounce_cooldown = 0
	ball._is_serving = true
	var angle: float = randf_range(-deg_to_rad(30.0), deg_to_rad(30.0))
	var direction: float = 1.0 if randi() % 2 == 0 else -1.0
	# 垂直发球: velocity = (sin θ, cos θ·dir)
	ball.velocity = Vector2(sin(angle), cos(angle) * direction) * ball.initial_speed
	ball._is_serving = false
	ball._scored_this_frame = false


func _fmt_games(letters: Array) -> String:
	var parts: Array[String] = []
	for i in range(letters.size()):
		var w: String = letters[i]
		parts.append("%s" % w[0].to_upper())
	return "(%s)" % " ".join(parts)


# ── Summary ──

func _print_summary(elapsed_ms: int) -> void:
	var total_match_count: int = max(passed + failed, 1)
	var avg: float = float(_total_frames) / float(total_match_count)
	print("\n═══════════════════════════════════════════")
	print("           AUTO-PLAY TEST SUMMARY")
	print("═══════════════════════════════════════════")
	print("  ✅ Passed:  %3d / %d" % [passed, MATCH_COUNT])
	print("  ❌ Failed:  %3d / %d" % [failed, MATCH_COUNT])
	print("  💥 Crashes: %3d" % _crashes)
	print("  ⏱  Timeouts: %3d" % _timeouts)
	print("  📊 Avg frames/match: %.0f" % avg)
	print("  ⏱  Elapsed: %d ms (%.1f s)" % [elapsed_ms, elapsed_ms / 1000.0])
	print("═══════════════════════════════════════════")
	var code := 1 if failed > 0 or _crashes > 0 or _timeouts > 0 else 0
	print("  Exit code: %d" % code)
	print("")

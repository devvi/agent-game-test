extends RefCounted
## Auto-Play Test — 100-round AI-vs-AI simulation.
## Verifies: no crash, scores reach 5, best-of-3 logic, winner exists, restart works.
## Uses a minimal self-contained scene (no FSM, no UI) for speed (~5s for 100 matches).
##
## Run via run_tests.gd:
##   godot --path mini-pong/ --headless --script tests/run_tests.gd
##
## Design: docs/DESIGN/297-ai-auto-play-test.md — Approach C (minimal test scene).
## Parent Issue: #297

var passed: int = 0
var failed: int = 0

# ── Test parameters ──
const MATCH_COUNT: int = 100
const MAX_FRAMES_PER_MATCH: int = 10000
const SCREEN_W: float = 1280.0
const SCREEN_H: float = 720.0

const _CONSTS = preload("res://gdscripts/constants.gd")
const POINTS_TO_WIN: int = _CONSTS.POINTS_TO_WIN_GAME
const GAMES_TO_WIN: int = _CONSTS.GAMES_TO_WIN_MATCH
const PADDLE_HALF_H: float = _CONSTS.PADDLE_HEIGHT / 2.0
const PADDLE_Y_MIN: float = PADDLE_HALF_H
const PADDLE_Y_MAX: float = SCREEN_H - PADDLE_HALF_H

# ── Stats ──
var _timeouts: int = 0
var _crashes: int = 0
var _total_frames: int = 0


func run() -> void:
	print("\n=== Auto-Play Test: %d Matches (AI vs AI) ===" % MATCH_COUNT)
	print("  POINTS_TO_WIN_GAME=%d  GAMES_TO_WIN_MATCH=%d" % [POINTS_TO_WIN, GAMES_TO_WIN])
	print("  MAX_FRAMES_PER_MATCH=%d" % MAX_FRAMES_PER_MATCH)

	var saved_ts := Engine.time_scale
	Engine.time_scale = 5.0
	print("  Engine.time_scale = %.1f" % Engine.time_scale)

	var tree := Engine.get_main_loop() as SceneTree
	var gm: Node = tree.root.get_node("GameManager")

	# ── Build minimal test scene (directly on root) ──
	var ball: Area2D = _spawn_ball(tree)
	var p_left: Area2D = _spawn_paddle(tree, "PlayerPaddle", Vector2(50.0, SCREEN_H / 2.0), 1)
	var p_right: Area2D = _spawn_paddle(tree, "AIPaddle", Vector2(SCREEN_W - 50.0, SCREEN_H / 2.0), 1)
	_spawn_walls(tree)
	var sm: Node = _spawn_scoring_manager(tree)

	# Wait for _ready callbacks to fire
	for _i in range(10):
		await tree.process_frame

	# Fix paddle bounds (headless viewport may return 0-size)
	_fix_paddle_bounds(p_left)
	_fix_paddle_bounds(p_right)

	var start_ms := Time.get_ticks_msec()

	for m in range(MATCH_COUNT):
		var ok: bool = await _run_single_match(tree, m, ball, p_left, p_right, sm, gm)
		if ok:
			passed += 1
		else:
			failed += 1

	var elapsed := Time.get_ticks_msec() - start_ms
	Engine.time_scale = saved_ts

	_print_summary(elapsed)

	# Cleanup test nodes
	for name in ["Ball", "PlayerPaddle", "AIPaddle", "TopWall", "BottomWall", "ScoringManager"]:
		var n := tree.root.get_node_or_null(name)
		if n != null:
			tree.root.remove_child(n)
			n.queue_free()


# ── Helpers ──

func _assert(condition: bool, name: String, midx: int, errors: Array[String]) -> bool:
	if condition:
		return true
	errors.append(name)
	return false


# ── Factories ──

func _spawn_ball(tree: SceneTree) -> Area2D:
	var ball: Area2D = load("res://scenes/ball.tscn").instantiate()
	ball.name = "Ball"
	tree.root.add_child(ball)
	return ball


func _spawn_paddle(tree: SceneTree, pname: String, pos: Vector2, ai_mode: int) -> Area2D:
	var paddle: Area2D = load("res://scenes/player_paddle.tscn").instantiate()
	paddle.name = pname
	paddle.position = pos
	paddle.mode = ai_mode
	tree.root.add_child(paddle)
	return paddle


func _spawn_walls(tree: SceneTree) -> void:
	_spawn_wall(tree, "TopWall", SCREEN_W / 2.0, 5.0)
	_spawn_wall(tree, "BottomWall", SCREEN_W / 2.0, SCREEN_H - 5.0)


func _spawn_wall(tree: SceneTree, wname: String, wx: float, wy: float) -> void:
	var w := StaticBody2D.new()
	w.name = wname
	w.position = Vector2(wx, wy)
	w.add_to_group("walls")
	w.collision_layer = 1
	w.collision_mask = 4
	var cs := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(SCREEN_W, 10.0)
	cs.shape = s
	w.add_child(cs)
	tree.root.add_child(w)


func _spawn_scoring_manager(tree: SceneTree) -> Node:
	var sm := Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.name = "ScoringManager"
	tree.root.add_child(sm)
	return sm


func _fix_paddle_bounds(p: Area2D) -> void:
	p.min_y = PADDLE_Y_MIN
	p.max_y = PADDLE_Y_MAX


# ── Match runner ──

func _run_single_match(tree: SceneTree, midx: int, ball: Area2D, p_left: Area2D, p_right: Area2D, sm: Node, gm: Node) -> bool:
	_reset_match(ball, p_left, p_right, sm, gm)

	var game_letters: Array[String] = []
	var _on_game := func(w: String):
		game_letters.append(w)
	gm.game_won.connect(_on_game)

	_serve_fast(ball)

	var frame := 0
	var winner := ""

	while winner.is_empty() and frame < MAX_FRAMES_PER_MATCH:
		await tree.process_frame
		frame += 1

		if is_nan(ball.velocity.x) or is_nan(ball.velocity.y):
			printerr("Match %03d: NaN velocity at frame %d — ABORT" % [midx + 1, frame])
			_crashes += 1
			_total_frames += frame
			gm.game_won.disconnect(_on_game)
			return false

		if is_nan(ball.position.x) or is_nan(ball.position.y):
			printerr("Match %03d: NaN position at frame %d — ABORT" % [midx + 1, frame])
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
		print("Match %03d: TIMEOUT after %d frames ❌" % [midx + 1, frame])
		return false

	var ok := true
	var errors: Array[String] = []

	ok = _assert(winner in ["player", "ai"], "invalid winner '%s'" % winner, midx, errors) and ok

	var wgames: int = gm.player_games_won if winner == "player" else gm.ai_games_won
	ok = _assert(wgames >= GAMES_TO_WIN, "winner has only %d games (need >= %d)" % [wgames, GAMES_TO_WIN], midx, errors) and ok

	var lgames: int = gm.ai_games_won if winner == "player" else gm.player_games_won
	ok = _assert(lgames < GAMES_TO_WIN, "loser also has >= %d games" % GAMES_TO_WIN, midx, errors) and ok

	ok = _assert(game_letters.size() >= GAMES_TO_WIN, "only %d game_won signals (need >= %d)" % [game_letters.size(), GAMES_TO_WIN], midx, errors) and ok

	var sm_games: int = sm.player_games + sm.ai_games
	var gm_games: int = gm.player_games_won + gm.ai_games_won
	ok = _assert(sm_games == gm_games, "SM games(%d) != GM games(%d)" % [sm_games, gm_games], midx, errors) and ok

	ok = _assert(p_left.position.y >= 0.0 and p_left.position.y <= SCREEN_H, "left paddle OOB y=%.1f" % p_left.position.y, midx, errors) and ok
	ok = _assert(p_right.position.y >= 0.0 and p_right.position.y <= SCREEN_H, "right paddle OOB y=%.1f" % p_right.position.y, midx, errors) and ok

	var total_games: int = gm.player_games_won + gm.ai_games_won
	var gstr := _fmt_games(game_letters)
	var icon := "✅" if ok else "❌"
	print("Match %03d: %s wins — %d games %s [%d frames] %s" % [
		midx + 1, winner.capitalize(), total_games, gstr, frame, icon
	])

	if not ok:
		for e in errors:
			print("         └─ %s" % e)

	return ok


func _reset_match(ball: Area2D, p_left: Area2D, p_right: Area2D, sm: Node, gm: Node) -> void:
	gm.reset_match()
	sm.player_score = 0
	sm.ai_score = 0
	sm.player_games = 0
	sm.ai_games = 0
	sm._is_match_over = false

	ball.position = Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0)
	ball.speed = ball.initial_speed
	ball.velocity = Vector2.ZERO
	ball._bounce_cooldown = 0
	ball._is_serving = false

	p_left.position.y = SCREEN_H / 2.0
	p_right.position.y = SCREEN_H / 2.0
	p_left.position.y = clamp(p_left.position.y, PADDLE_Y_MIN, PADDLE_Y_MAX)
	p_right.position.y = clamp(p_right.position.y, PADDLE_Y_MIN, PADDLE_Y_MAX)
	p_left._ai_delay_timer = randf_range(p_left.ai_reaction_delay_min, p_left.ai_reaction_delay_max)
	p_right._ai_delay_timer = randf_range(p_right.ai_reaction_delay_min, p_right.ai_reaction_delay_max)


func _serve_fast(ball: Area2D) -> void:
	ball.position = Vector2(SCREEN_W / 2.0, SCREEN_H / 2.0)
	ball.speed = ball.initial_speed
	ball._bounce_cooldown = 0
	ball._is_serving = false
	var angle: float = randf_range(-deg_to_rad(45.0), deg_to_rad(45.0))
	var direction: float = 1.0 if randi() % 2 == 0 else -1.0
	ball.velocity = Vector2(cos(angle) * direction, sin(angle)) * ball.initial_speed


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
	print("  📊 Avg frames/match: %.1f" % avg)
	print("  ⏱  Elapsed: %d ms (%.1f s)" % [elapsed_ms, elapsed_ms / 1000.0])
	print("═══════════════════════════════════════════")
	var code := 1 if failed > 0 or _crashes > 0 or _timeouts > 0 else 0
	print("  Exit code: %d" % code)
	print("")

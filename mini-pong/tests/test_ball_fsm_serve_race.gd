extends RefCounted
## Regression tests for Issue #525 — "游戏重置后无操作小球自行飞行" (double-serve race).
##
## 修复方案 A (DESIGN docs/DESIGN/525-ball-fly-after-reset.md §1.1/§3.1):
##   1. ball.gd 得分路径删除 3 处 serve() 调用（_process 上出界分支、_process 下出界分支、
##      _on_score_zone），只保留 score.emit(side) —— 发球编排收归 FSM 独占（#294）。
##   2. game_state_machine.gd State.SCORED enter_state 新增 _freeze_ball(true)
##      （在 _freeze_paddles(true) 之后）—— SCORED 期间球静止，回归 DESIGN #294 状态表
##      (SCORED/SERVING Ball Moving = No)；解冻由 SERVING 的 serve() 内 frozen=false (#391 AC4) 接管。
##
## 测试目标 (DESIGN §9 Scenario A/B/C):
##   AC1 (Scenario A): 出界 / ScoreZone 计分后球不自行飞行 —— SCORED/SERVING 期间
##       ball.position 恒定、frozen==true、score 仅 emit 1 次。
##   AC2 (Scenario B): 重发球时序不变 —— serve() 由 FSM 在 ~2.0s 回中、~2.5s 进 PLAYING 起飞；
##       首次发球 (MENU→SPACE→SERVING) 路径不受影响。
##   AC3 (Scenario C): 单次计分 —— ball.score 与 GameManager.score_changed 各恰好 1 次，
##       SCORED/SERVING 期间无重复出界事件（修复前竞态会重复出界 + 重复计分）。
##
## 运行方式: run_tests.gd (_run_async) 注册。测试必须 await 真实时间（FSM SCORED 1s +
## SERVING 1s + SERVE_DELAY 0.5s ≈ 2.5s 时序），不可跳过。
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0

# ── 竖屏几何 (720x1280, #383) 与球物理常量 (constants.gd) ──
const CONSTS = preload("res://gdscripts/constants.gd")
const SCREEN_WIDTH: float = 720.0
const SCREEN_HEIGHT: float = 1280.0
const BALL_RADIUS: float = 10.0
const CENTER: Vector2 = Vector2(360.0, 640.0)
const INITIAL_SPEED: float = 330.0

# ── 信号捕获（成员方法绑定，lambda 按值捕获不可用）──
var _score_sides: Array = []
var _score_changed_count: int = 0


func run() -> void:
	print("\n=== Ball Serve Race Tests (#525) ===")
	await _test_a1_bottom_exit()
	await _test_a2_top_exit()
	await _test_a3_score_zone()
	await _test_b1_timeline()
	await _test_b2_first_serve()
	await _test_c1_single_scoring()
	await _test_c2_no_duplicate_score()
	print("  Ball Serve Race: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── mini-tree helpers ────────────────────────────────────────────

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _wait(seconds: float) -> void:
	await _tree().create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	"""Poll every process_frame until cond() true or wall-clock timeout."""
	var tree: SceneTree = _tree()
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await tree.process_frame
	return true


func _build_mini_tree() -> Dictionary:
	"""Build Main.tscn-like mini-tree on the real SceneTree root.

	Node hierarchy (all siblings under root — FSM @onready "../X" refs resolve):
	  StartMenu/GameHUD/GameOverScreen/PauseOverlay : CanvasLayer (UI layers)
	  Ball                : real ball.gd (Area2D, 竖屏 physics, score/serve/set_frozen)
	  PlayerPaddle/AIPaddle : Area2D (FSM _freeze_paddles 用 has_method 守卫 → 跳过，可接受)
	  ScoringManager      : real scoring_manager.gd (消费 ball.score → add_score + scored.emit)
	  GameStateMachine    : real FSM, added last → _ready → enter_state(MENU)（冻结球）
	"""
	var root = _tree().root
	var added: Array = []
	var ui_names := ["StartMenu", "GameHUD", "GameOverScreen", "PauseOverlay"]
	for n in ui_names:
		var cl = CanvasLayer.new()
		cl.name = n
		root.add_child(cl)
		added.append(cl)
	var ball: Area2D = Area2D.new()
	ball.set_script(load("res://gdscripts/ball.gd"))
	ball.name = "Ball"
	root.add_child(ball)
	# headless viewport 非 720x1280 —— 显式固定竖屏几何（serve() 回中依赖它）
	ball.screen_width = SCREEN_WIDTH
	ball.screen_height = SCREEN_HEIGHT
	added.append(ball)
	for pname in ["PlayerPaddle", "AIPaddle"]:
		var paddle = Area2D.new()
		paddle.name = pname
		root.add_child(paddle)
		added.append(paddle)
	var sm = Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.name = "ScoringManager"
	root.add_child(sm)
	added.append(sm)
	var fsm_script = load("res://gdscripts/game_state_machine.gd")
	var fsm = Node.new()
	fsm.set_script(fsm_script)
	fsm.name = "GameStateMachine"
	root.add_child(fsm)
	added.append(fsm)
	return {"ball": ball, "fsm": fsm, "added": added}


func _teardown_mini_tree(ctx: Dictionary) -> void:
	"""Free every node this test added (by reference — no name collisions).
	挂起的 create_timer 协程随对象释放自动丢弃（Godot 4，safe）。"""
	for node in ctx["added"]:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()


func _reset_signal_capture() -> void:
	_score_sides = []
	_score_changed_count = 0


func _connect_capture(ball: Area2D) -> void:
	ball.score.connect(_on_ball_score)
	if GameManager.score_changed.is_connected(_on_score_changed):
		GameManager.score_changed.disconnect(_on_score_changed)
	GameManager.score_changed.connect(_on_score_changed)


func _disconnect_capture() -> void:
	if GameManager.score_changed.is_connected(_on_score_changed):
		GameManager.score_changed.disconnect(_on_score_changed)


func _on_ball_score(side: int) -> void:
	_score_sides.append(side)


func _on_score_changed(_player_score: int, _ai_score: int) -> void:
	_score_changed_count += 1


func _force_playing(fsm: Node, ball: Area2D) -> void:
	"""强制 FSM 进 PLAYING + 手动解冻球。

	MENU enter 冻结了球（#508），PLAYING enter 不解冻球 —— 测试需手动解冻。
	transition_to(PLAYING) 是同步的（enter_state(PLAYING) 无 await），直接可进。"""
	if fsm.current_state != fsm.State.PLAYING:
		fsm.transition_to(fsm.State.PLAYING)
	ball.set_frozen(false)
	ball.frozen = false
	ball._is_serving = false
	ball._scored_this_frame = false
	ball._crossed_wall = false
	ball._was_in_wall_band = false


# ── Scenario A: AC1 —— 出界后球不自行飞行 ───────────────────────

func _test_a1_bottom_exit() -> void:
	"""A-1 底部出界: 球下落至 y>1290 → score(1)；SCORED/SERVING 期间 frozen + position 恒定；
	最终 (~2.5s) FSM 回 PLAYING、球回中且起飞（serve 由 FSM 调用，时序不变 AC2）。"""
	var tree: SceneTree = _tree()
	var ctx: Dictionary = _build_mini_tree()
	var ball: Area2D = ctx["ball"]
	var fsm: Node = ctx["fsm"]
	await _wait(0.7)  # 等 ball._ready() 的首发球 serve 协程完成，避免中途覆盖测试状态
	GameManager.reset_match()
	_reset_signal_capture()
	_connect_capture(ball)
	_force_playing(fsm, ball)
	ball.position = Vector2(360.0, 330.0)
	ball.velocity = Vector2(0.0, INITIAL_SPEED)
	ball.speed = INITIAL_SPEED

	var exited: bool = await _wait_until(
		func(): return ball.position.y > SCREEN_HEIGHT + BALL_RADIUS, 6.0)
	_assert(exited, "A1-1: ball exited bottom boundary (y > 1290)")
	_assert(_score_sides.size() == 1, "A1-2: score emitted exactly once (%d emits)" % _score_sides.size())
	if _score_sides.size() == 1:
		_assert(_score_sides[0] == 1, "A1-3: score side == 1 (ai scores)")
	_assert(fsm.current_state == fsm.State.SCORED, "A1-4: FSM in SCORED after exit")
	_assert(ball.frozen == true, "A1-5: ball frozen in SCORED (no self-fly)")

	var pos_frozen: Vector2 = ball.position
	await _wait(0.5)
	_assert(ball.position == pos_frozen, "A1-6: position constant at t+0.5s (SCORED)")
	_assert(ball.frozen == true, "A1-7: ball still frozen at t+0.5s")
	await _wait(1.0)
	_assert(ball.position == pos_frozen, "A1-8: position constant at t+1.5s (SERVING)")
	_assert(ball.frozen == true, "A1-9: ball still frozen at t+1.5s")

	var recentered: bool = await _wait_until(
		func(): return ball._is_serving and ball.position.distance_to(CENTER) < 1.0, 4.0)
	_assert(recentered, "A1-10: FSM serve() recentered ball (~2.0s)")
	_assert(ball.frozen == false, "A1-11: ball unfrozen by serve() (#391 AC4)")
	_assert(ball._is_serving == true, "A1-12: ball in serving state at recenter")

	var playing: bool = await _wait_until(
		func(): return fsm.current_state == fsm.State.PLAYING, 4.0)
	_assert(playing, "A1-13: FSM back to PLAYING (~2.5s)")
	_assert(ball.velocity != Vector2.ZERO, "A1-14: ball in flight (velocity non-zero)")
	_assert(ball.frozen == false, "A1-15: ball not frozen in PLAYING")

	_disconnect_capture()
	_teardown_mini_tree(ctx)


func _test_a2_top_exit() -> void:
	"""A-2 顶部出界: 球向上 y<-10 → score(0)；同 A-1 断言（SCORED 期间 frozen、position 恒定）。"""
	var tree: SceneTree = _tree()
	var ctx: Dictionary = _build_mini_tree()
	var ball: Area2D = ctx["ball"]
	var fsm: Node = ctx["fsm"]
	await _wait(0.7)
	GameManager.reset_match()
	_reset_signal_capture()
	_connect_capture(ball)
	_force_playing(fsm, ball)
	ball.position = CENTER
	ball.velocity = Vector2(0.0, -INITIAL_SPEED)
	ball.speed = INITIAL_SPEED

	var exited: bool = await _wait_until(
		func(): return ball.position.y < -BALL_RADIUS, 6.0)
	_assert(exited, "A2-1: ball exited top boundary (y < -10)")
	_assert(_score_sides.size() == 1, "A2-2: score emitted exactly once (%d emits)" % _score_sides.size())
	if _score_sides.size() == 1:
		_assert(_score_sides[0] == 0, "A2-3: score side == 0 (player scores)")
	_assert(fsm.current_state == fsm.State.SCORED, "A2-4: FSM in SCORED after exit")
	_assert(ball.frozen == true, "A2-5: ball frozen in SCORED (no self-fly)")

	var pos_frozen: Vector2 = ball.position
	await _wait(0.5)
	_assert(ball.position == pos_frozen, "A2-6: position constant at t+0.5s (SCORED)")
	_assert(ball.frozen == true, "A2-7: ball still frozen at t+0.5s")
	await _wait(1.0)
	_assert(ball.position == pos_frozen, "A2-8: position constant at t+1.5s (SERVING)")
	_assert(ball.frozen == true, "A2-9: ball still frozen at t+1.5s")

	var recentered: bool = await _wait_until(
		func(): return ball._is_serving and ball.position.distance_to(CENTER) < 1.0, 4.0)
	_assert(recentered, "A2-10: FSM serve() recentered ball (~2.0s)")

	var playing: bool = await _wait_until(
		func(): return fsm.current_state == fsm.State.PLAYING, 4.0)
	_assert(playing, "A2-11: FSM back to PLAYING (~2.5s)")
	_assert(ball.velocity != Vector2.ZERO, "A2-12: ball in flight (velocity non-zero)")

	_disconnect_capture()
	_teardown_mini_tree(ctx)


func _test_a3_score_zone() -> void:
	"""A-3 ScoreZone 路径: 直接调 ball._on_score_zone(1)（area_entered 计分等价）
	→ 只 emit score、被 SCORED 冻结 —— 与 Y 边界计分路径行为一致（PRD 边界 4）。"""
	var tree: SceneTree = _tree()
	var ctx: Dictionary = _build_mini_tree()
	var ball: Area2D = ctx["ball"]
	var fsm: Node = ctx["fsm"]
	await _wait(0.7)
	GameManager.reset_match()
	_reset_signal_capture()
	_connect_capture(ball)
	_force_playing(fsm, ball)
	ball.position = Vector2(360.0, 700.0)
	ball.velocity = Vector2.ZERO
	ball._scored_this_frame = false
	ball._on_score_zone(1)

	_assert(_score_sides.size() == 1, "A3-1: score emitted exactly once via ScoreZone path (%d emits)" % _score_sides.size())
	if _score_sides.size() == 1:
		_assert(_score_sides[0] == 1, "A3-2: score side == 1 (ai scores)")
	_assert(fsm.current_state == fsm.State.SCORED, "A3-3: FSM in SCORED after ScoreZone score")
	_assert(ball.frozen == true, "A3-4: ball frozen in SCORED (no self-fly)")

	var pos_frozen: Vector2 = ball.position
	await _wait(0.5)
	_assert(ball.position == pos_frozen, "A3-5: position constant at t+0.5s (SCORED)")
	_assert(ball.frozen == true, "A3-6: ball still frozen at t+0.5s")
	await _wait(1.0)
	_assert(ball.position == pos_frozen, "A3-7: position constant at t+1.5s (SERVING)")
	_assert(ball.frozen == true, "A3-8: ball still frozen at t+1.5s")

	_disconnect_capture()
	_teardown_mini_tree(ctx)


# ── Scenario B: AC2 —— 重发球时序不变 ────────────────────────────

func _test_b1_timeline() -> void:
	"""B-1 时序: 出界后 ~2.0s serve() 回中（frozen==false、_is_serving==true）；
	~2.5s 进 PLAYING 且 velocity 非零。轮询等待，±0.5s 容差。"""
	var tree: SceneTree = _tree()
	var ctx: Dictionary = _build_mini_tree()
	var ball: Area2D = ctx["ball"]
	var fsm: Node = ctx["fsm"]
	await _wait(0.7)
	GameManager.reset_match()
	_reset_signal_capture()
	_connect_capture(ball)
	_force_playing(fsm, ball)
	ball.position = Vector2(360.0, 330.0)
	ball.velocity = Vector2(0.0, INITIAL_SPEED)
	ball.speed = INITIAL_SPEED

	var exited: bool = await _wait_until(
		func(): return ball.position.y > SCREEN_HEIGHT + BALL_RADIUS, 6.0)
	_assert(exited, "B1-1: ball exited bottom boundary")
	var score_ms := Time.get_ticks_msec()

	var recentered: bool = await _wait_until(
		func(): return ball._is_serving and ball.position.distance_to(CENTER) < 1.0, 4.0)
	_assert(recentered, "B1-2: ball recentered by FSM serve()")
	var recenter_dt := (Time.get_ticks_msec() - score_ms) / 1000.0
	_assert(absf(recenter_dt - 2.0) <= 0.5, "B1-3: recenter at ~2.0s after score (%.2fs)" % recenter_dt)
	_assert(ball.frozen == false, "B1-4: ball unfrozen at recenter")
	_assert(ball._is_serving == true, "B1-5: ball in serving state at recenter")

	var playing: bool = await _wait_until(
		func(): return fsm.current_state == fsm.State.PLAYING, 4.0)
	var play_dt := (Time.get_ticks_msec() - score_ms) / 1000.0
	_assert(playing, "B1-6: FSM reached PLAYING")
	_assert(play_dt >= 2.2 and play_dt <= 4.0, "B1-7: PLAYING at ~2.5s after score (%.2fs)" % play_dt)
	_assert(ball.velocity != Vector2.ZERO, "B1-8: ball in flight (velocity non-zero)")
	_assert(ball.frozen == false, "B1-9: ball not frozen in PLAYING")

	_disconnect_capture()
	_teardown_mini_tree(ctx)


func _test_b2_first_serve() -> void:
	"""B-2 首次发球: MENU→SPACE→SERVING 流程 —— serve() 由 FSM 调用（_ready 首发球路径
	不受修复影响），球正常进入对打。"""
	var tree: SceneTree = _tree()
	var ctx: Dictionary = _build_mini_tree()
	var ball: Area2D = ctx["ball"]
	var fsm: Node = ctx["fsm"]
	await _wait(0.7)
	GameManager.reset_match()
	_reset_signal_capture()
	_connect_capture(ball)

	_assert(fsm.current_state == fsm.State.MENU, "B2-1: FSM starts in MENU")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	fsm._input(ev)
	_assert(fsm.current_state == fsm.State.SERVING, "B2-2: SPACE in MENU → SERVING")

	var playing: bool = await _wait_until(
		func(): return fsm.current_state == fsm.State.PLAYING, 4.0)
	_assert(playing, "B2-3: first serve reaches PLAYING (FSM serves)")
	_assert(ball.frozen == false, "B2-4: ball unfrozen in PLAYING")
	_assert(ball._is_serving == false, "B2-5: serve animation completed")
	_assert(ball.velocity != Vector2.ZERO, "B2-6: ball in flight after first serve")

	_disconnect_capture()
	_teardown_mini_tree(ctx)


# ── Scenario C: AC3 —— 单次计分 ─────────────────────────────────

func _test_c1_single_scoring() -> void:
	"""C-1 事件计数: 出界后 ball.score 恰 1 次 + GameManager.score_changed 恰 1 次
	+ 总分 1 —— 修复前竞态会产生重复出界事件与重复计分。"""
	var tree: SceneTree = _tree()
	var ctx: Dictionary = _build_mini_tree()
	var ball: Area2D = ctx["ball"]
	var fsm: Node = ctx["fsm"]
	await _wait(0.7)
	GameManager.reset_match()
	_reset_signal_capture()
	_connect_capture(ball)
	_force_playing(fsm, ball)
	ball.position = Vector2(360.0, 330.0)
	ball.velocity = Vector2(0.0, INITIAL_SPEED)
	ball.speed = INITIAL_SPEED

	var exited: bool = await _wait_until(
		func(): return ball.position.y > SCREEN_HEIGHT + BALL_RADIUS, 6.0)
	_assert(exited, "C1-1: ball exited bottom boundary")
	_assert(_score_sides.size() == 1, "C1-2: ball.score emitted once (%d emits)" % _score_sides.size())
	_assert(_score_changed_count == 1, "C1-3: GameManager.score_changed fired once (%d)" % _score_changed_count)
	# 比分与事件计数一致：单次 add_score 事件（(360,330) 下坠必经墙带 y∈[618,662] → 穿墙分 3 分）
	_assert(GameManager.ai_score == GameManager.get_pierce_count("ai") * CONSTS.PIERCE_SCORE,
		"C1-4: ai tally matches single pierce event (score=%d)" % GameManager.ai_score)

	await _wait(1.5)  # 推进 SCORED + SERVING，确认无二次计分
	_assert(_score_sides.size() == 1, "C1-5: still exactly one score emit after SCORED/SERVING (%d)" % _score_sides.size())
	_assert(_score_changed_count == 1, "C1-6: still one score_changed after SCORED/SERVING (%d)" % _score_changed_count)

	_disconnect_capture()
	_teardown_mini_tree(ctx)


func _test_c2_no_duplicate_score() -> void:
	"""C-2 无重复出界: SCORED/SERVING 期间逐帧推进，无第二次 score.emit（计数仍为 1）。
	修复前球自行起飞后再次出界 → 计数 >1（伴随 'ignoring' 告警）。"""
	var tree: SceneTree = _tree()
	var ctx: Dictionary = _build_mini_tree()
	var ball: Area2D = ctx["ball"]
	var fsm: Node = ctx["fsm"]
	await _wait(0.7)
	GameManager.reset_match()
	_reset_signal_capture()
	_connect_capture(ball)
	_force_playing(fsm, ball)
	ball.position = Vector2(360.0, 330.0)
	ball.velocity = Vector2(0.0, INITIAL_SPEED)
	ball.speed = INITIAL_SPEED

	var exited: bool = await _wait_until(
		func(): return ball.position.y > SCREEN_HEIGHT + BALL_RADIUS, 6.0)
	_assert(exited, "C2-1: ball exited bottom boundary")
	_assert(_score_sides.size() == 1, "C2-2: score emitted once at exit (%d)" % _score_sides.size())

	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:  # 覆盖 SCORED 1s + SERVING 0.5s
		await tree.process_frame
		if _score_sides.size() > 1:
			break
	_assert(_score_sides.size() == 1, "C2-3: no second score.emit during SCORED/SERVING (count=%d)" % _score_sides.size())
	_assert(ball.frozen == true, "C2-4: ball still frozen through SCORED/SERVING")

	var playing: bool = await _wait_until(
		func(): return fsm.current_state == fsm.State.PLAYING, 4.0)
	_assert(playing, "C2-5: FSM recovered to PLAYING (serve path intact)")

	_disconnect_capture()
	_teardown_mini_tree(ctx)

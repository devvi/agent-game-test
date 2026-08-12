extends RefCounted
## Test suite for scoring_manager.gd (#291) — 双得分制薄事件路由 (#385)。
## 出界分 3/1 路由（穿墙/兜底）、brick_destroyed 消费、同帧去重、终局守卫。
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0

# ── Signal capture state ──
var _scored_winner: String = ""
var _scored_count: int = 0

func _on_scored(winner: String) -> void:
	_scored_winner = winner
	_scored_count += 1


func run() -> void:
	print("\n=== Scoring Manager Tests (#291/#385) ===")
	_test_tc1_player_scores()
	_test_tc2_ai_scores()
	_test_pierce_player_3pt()
	_test_pierce_ai_3pt()
	_test_boundary_no_cross_1pt()
	_test_brick_player()
	_test_brick_ai()
	_test_brick_empty_toucher()
	_test_brick_no_scored_signal()
	_test_same_frame_brick_only()
	_test_next_frame_both_count()
	_test_guard_resets_next_frame()
	_test_terminal_guard_ball_score()
	_test_terminal_guard_brick()
	_test_no_grid_tolerant()
	_test_grid_connected_consumes()
	_test_initial_state_zero()


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_mock_ball():
	var code = GDScript.new()
	code.source_code = """extends Area2D

signal score(side: int)

var last_toucher: String = ""
var _crossed_wall: bool = false

func serve() -> void:
	last_toucher = ""
	_crossed_wall = false
"""
	code.reload()
	var ball = Area2D.new()
	ball.name = "Ball"
	ball.set_script(code)
	return ball


func _make_mock_grid():
	var code = GDScript.new()
	code.source_code = """extends Node

signal brick_destroyed(brick: Node2D, pos: Vector2)
"""
	code.reload()
	var grid = Node.new()
	grid.name = "BreakoutGrid"
	grid.set_script(code)
	return grid


func _make_sm(ball = null, grid = null):
	var mb = ball if ball != null else _make_mock_ball()
	var sm = Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.ball = mb
	sm.breakout_grid = grid
	return sm

func _make_tree_sm(ball, grid):
	## 树构建：_ready 由引擎在入树时触发，@onready ../Ball ../BreakoutGrid 正确解析。
	## （手动调 _ready() 会重跑 @onready 赋值覆盖手动设置 —— Godot 4 行为，勿用）
	var tree = Engine.get_main_loop() as SceneTree
	ball.name = "Ball"
	tree.root.add_child(ball)
	if grid != null:
		tree.root.add_child(grid)
	var sm = Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.name = "ScoringManager"
	tree.root.add_child(sm)
	return sm


func _cleanup_tree(nodes: Array) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	for n in nodes:
		if n != null and is_instance_valid(n) and n.get_parent() != null:
			n.get_parent().remove_child(n)
			n.queue_free()


func _reset_gm() -> void:
	GameManager.reset_match()
	_scored_winner = ""
	_scored_count = 0


# ── TC1: 普通出界玩家得分（side 0 = 顶部出界 → player）──

func _test_tc1_player_scores() -> void:
	_reset_gm()
	var sm = _make_sm()
	sm.scored.connect(_on_scored)

	sm._on_ball_score(0)

	_assert(GameManager.player_score == 1, "TC1: player_score == 1 (boundary)")
	_assert(GameManager.ai_score == 0, "TC1: ai_score == 0")
	_assert(GameManager.get_pierce_count("player") == 0, "TC1: no pierce counted")
	_assert(_scored_winner == "player", "TC1: scored('player') emitted")
	_assert(_scored_count == 1, "TC1: scored emitted exactly once")


# ── TC2: 普通出界 AI 得分（side 1 = 底部出界 → ai）──

func _test_tc2_ai_scores() -> void:
	_reset_gm()
	var sm = _make_sm()
	sm.scored.connect(_on_scored)

	sm._on_ball_score(1)

	_assert(GameManager.ai_score == 1, "TC2: ai_score == 1 (boundary)")
	_assert(GameManager.player_score == 0, "TC2: player_score == 0")
	_assert(_scored_winner == "ai", "TC2: scored('ai') emitted")


# ── 穿墙 3 分路由（AC2）──

func _test_pierce_player_3pt() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_ball_score(0)

	_assert(GameManager.player_score == 3, "PZ-P: player_score == 3 (pierce)")
	_assert(GameManager.get_pierce_count("player") == 1, "PZ-P: player_pierce_count == 1")
	_assert(_scored_count == 1, "PZ-P: scored emitted (SCORED flow)")


func _test_pierce_ai_3pt() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_ball_score(1)

	_assert(GameManager.ai_score == 3, "PZ-A: ai_score == 3 (pierce)")
	_assert(GameManager.get_pierce_count("ai") == 1, "PZ-A: ai_pierce_count == 1")


func _test_boundary_no_cross_1pt() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball._crossed_wall = false
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_ball_score(0)

	_assert(GameManager.player_score == 1, "BD: player_score == 1 (boundary fallback)")
	_assert(GameManager.get_pierce_count("player") == 0, "BD: pierce_count == 0")


# ── 拆砖消费（AC1）──

func _test_brick_player() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 1, "BR-P: player_score == 1")
	_assert(GameManager.get_brick_count("player") == 1, "BR-P: player_brick_count == 1")
	_assert(_scored_count == 0, "BR-P: no scored emitted")


func _test_brick_ai() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = "ai"
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.ai_score == 1, "BR-A: ai_score == 1")
	_assert(GameManager.get_brick_count("ai") == 1, "BR-A: ai_brick_count == 1")
	_assert(GameManager.get_brick_count("player") == 0, "BR-A: player unchanged")


func _test_brick_empty_toucher() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = ""
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 0, "BR-E: player_score == 0")
	_assert(GameManager.ai_score == 0, "BR-E: ai_score == 0")
	_assert(GameManager.get_brick_count("player") == 0, "BR-E: brick_count == 0")
	_assert(_scored_count == 0, "BR-E: no scored emitted")


func _test_brick_no_scored_signal() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(_scored_count == 0, "BR-NS: brick destroy does NOT emit scored")


# ── 同帧去重（AC4）──

## 同帧拆砖 + 出界 → 只计拆砖
func _test_same_frame_brick_only() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._on_ball_score(0)

	_assert(GameManager.player_score == 1, "SF: only brick +1 (no +3)")
	_assert(GameManager.get_pierce_count("player") == 0, "SF: pierce suppressed")
	_assert(_scored_count == 0, "SF: no scored emitted")


## 不同帧各自计分
func _test_next_frame_both_count() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._process(0.016)  # 帧边界
	ball._crossed_wall = true
	sm._on_ball_score(0)

	_assert(GameManager.player_score == 4, "NF: brick +1 and pierce +3 both counted")
	_assert(GameManager.get_pierce_count("player") == 1, "NF: pierce_count == 1")


## 帧守卫复位: 守卫被消费后下一帧正常计分
func _test_guard_resets_next_frame() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._on_ball_score(0)
	_assert(GameManager.player_score == 1, "GR: same-frame only brick")

	sm._on_ball_score(0)
	_assert(GameManager.player_score == 4, "GR: next exit counted normally")
	_assert(_scored_count == 1, "GR: scored emitted once for second exit")


# ── 终局守卫（失败路径 2）──

func _test_terminal_guard_ball_score() -> void:
	_reset_gm()
	GameManager._is_run_over = true
	var ball = _make_mock_ball()
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_ball_score(0)

	_assert(GameManager.player_score == 0, "TG-B: no score after terminal")
	_assert(_scored_count == 0, "TG-B: no scored emitted")
	GameManager.reset_match()


func _test_terminal_guard_brick() -> void:
	_reset_gm()
	GameManager._is_run_over = true
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var sm = _make_sm(ball)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 0, "TG-R: no brick score after terminal")
	_assert(GameManager.get_brick_count("player") == 0, "TG-R: brick_count == 0")
	GameManager.reset_match()


# ── 容错连接（失败路径 1）──

## 无 BreakoutGrid → _ready 不崩、其余计分正常
func _test_no_grid_tolerant() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	var sm = _make_tree_sm(ball, null)
	sm.scored.connect(_on_scored)

	sm._on_ball_score(0)
	_assert(GameManager.player_score == 1, "NG: boundary scoring works without grid")
	_cleanup_tree([sm, ball])


## 有 brick_destroyed 信号 → 连接成功、事件被消费
func _test_grid_connected_consumes() -> void:
	_reset_gm()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var grid = _make_mock_grid()
	var sm = _make_tree_sm(ball, grid)
	sm.scored.connect(_on_scored)

	grid.brick_destroyed.emit(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 1, "GC: brick consumed via grid signal")
	_assert(GameManager.get_brick_count("player") == 1, "GC: player_brick_count == 1")
	_assert(_scored_count == 0, "GC: no scored emitted")
	_cleanup_tree([sm, ball, grid])


# ── 初始状态 ──

func _test_initial_state_zero() -> void:
	_reset_gm()
	var sm = _make_sm()
	_assert(sm._brick_destroyed_this_frame == false, "STATE: _brick_destroyed_this_frame initial false")
	_assert(GameManager.player_score == 0, "STATE: player_score initial 0")
	_assert(GameManager.ai_score == 0, "STATE: ai_score initial 0")

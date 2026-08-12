extends RefCounted
## Dual Scoring test suite (#385) — 双得分制。
## Covers DESIGN docs/DESIGN/385-dual-scoring-system.md §9 Scenarios A–E + H.
## (Scenario F: ball lifecycle → test_ball.gd; Scenario I: FSM → test_game_state_machine.gd)
##
## Uses the REAL GameManager autoload (reset between tests) + isolated ScoringManager
## instances with mock ball / mock BreakoutGrid (brick_destroyed 容错，未接线时验证失败路径)。
##
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0

# ── Signal capture state (member vars, not lambda closures) ──
var _captured_scores: Array = []       # [[player_score, ai_score], ...]
var _captured_match_overs: Array = []  # ["player", ...]
var _scored_count: int = 0


func _on_score_changed(p_score: int, a_score: int) -> void:
	_captured_scores.append([p_score, a_score])


func _on_match_over(winner: String) -> void:
	_captured_match_overs.append(winner)


func _on_scored(_winner: String) -> void:
	_scored_count += 1


func run() -> void:
	print("\n=== Dual Scoring Tests (#385) ===")
	# Connect to real GameManager autoload ONCE (dedup: disconnect at end)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.match_over.connect(_on_match_over)

	# Scenario A: 拆砖分归属 (AC1)
	_test_a1_player_brick()
	_test_a2_ai_brick()
	_test_a3_empty_toucher()
	_test_a4_brick_no_scored()
	_test_a5_multiple_bricks()
	# Scenario B: 穿墙 3 分 (AC2)
	_test_b1_pierce_top()
	_test_b2_pierce_bottom()
	_test_b3_no_cross_boundary()
	_test_b4_brick_plus_pierce()
	# Scenario C: 21 分终局 (AC3)
	_test_c1_exactly_21()
	_test_c2_frozen_after_end()
	_test_c3_20_not_end()
	_test_c4_ai_21()
	_test_c5_reset_after_end()
	# Scenario D: 同帧去重 (AC4)
	_test_d1_same_frame_dedup()
	_test_d2_diff_frame_both()
	_test_d3_guard_reset()
	# Scenario E: 查询 API (AC5)
	_test_e1_counts_consistent()
	_test_e2_initial_zero()
	_test_e3_over_screen_reads_stats()
	# Scenario H: 失败路径
	_test_h1_tolerant_connect_no_grid()
	_test_h2_connect_with_grid()
	_test_h3_events_ignored_after_end()

	GameManager.score_changed.disconnect(_on_score_changed)
	GameManager.match_over.disconnect(_on_match_over)
	print("  Dual Scoring: %d passed, %d failed" % [passed, failed])


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _reset_all() -> void:
	GameManager.reset_match()
	_captured_scores.clear()
	_captured_match_overs.clear()
	_scored_count = 0


func _make_mock_ball() -> Area2D:
	## Mock ball with score signal + #385 state fields (last_toucher / _crossed_wall).
	var code = GDScript.new()
	code.source_code = """extends Area2D

signal score(side: int)

var last_toucher: String = ""
var _crossed_wall: bool = false

func serve() -> void:
	pass
"""
	code.reload()
	var ball = Area2D.new()
	ball.name = "Ball"
	ball.set_script(code)
	return ball


func _make_mock_grid() -> Node2D:
	## Mock BreakoutGrid with #384 signal contract: brick_destroyed(brick, pos).
	var code = GDScript.new()
	code.source_code = """extends Node2D

signal brick_destroyed(brick: Node2D, pos: Vector2)
"""
	code.reload()
	var grid = Node2D.new()
	grid.name = "BreakoutGrid"
	grid.set_script(code)
	return grid


func _make_sm(ball) -> Node:
	## Isolated ScoringManager instance; ball injected manually (no scene tree in headless).
	var sm = Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.ball = ball
	return sm


func _make_tree_sm(ball, grid) -> Node:
	## Build a real mini-tree so _ready() runs with @onready resolving properly.
	## (Manual _ready() calls re-run @onready assignments and wipe manually-set
	## member vars — Godot 4 behavior; tree-based setup avoids that pitfall.)
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


# ── Scenario A: 拆砖分归属 (AC1) ──

## A-1: 玩家触球拆砖 → +1 分、player_brick_count +1、score_changed 恰好一次 [1,0]
func _test_a1_player_brick() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 1, "A-1: player_score == 1")
	_assert(GameManager.ai_score == 0, "A-1: ai_score == 0")
	_assert(GameManager.get_brick_count("player") == 1, "A-1: player_brick_count == 1")
	_assert(_captured_scores.size() == 1 and _captured_scores[0] == [1, 0],
		"A-1: score_changed exactly once with [1, 0]")
	_assert(_scored_count == 0, "A-1: brick does not emit scored (A-4 同断言)")


## A-2: AI 触球拆砖 → ai 侧 +1，player 侧不变
func _test_a2_ai_brick() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "ai"
	var sm = _make_sm(ball)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.ai_score == 1, "A-2: ai_score == 1")
	_assert(GameManager.ai_brick_count == 1, "A-2: ai_brick_count == 1")
	_assert(GameManager.player_score == 0, "A-2: player_score unchanged")
	_assert(GameManager.player_brick_count == 0, "A-2: player_brick_count unchanged")


## A-3: 空触球者（发球直撞砖）→ 不计分、无 score_changed（边界 2）
func _test_a3_empty_toucher() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = ""
	var sm = _make_sm(ball)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 0, "A-3: player_score == 0")
	_assert(GameManager.ai_score == 0, "A-3: ai_score == 0")
	_assert(GameManager.get_brick_count("player") == 0, "A-3: no brick count")
	_assert(_captured_scores.size() == 0, "A-3: no score_changed")


## A-4: 拆砖不触发 scored 信号（边界 8：比赛继续，不暂停）
func _test_a4_brick_no_scored() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(_scored_count == 0, "A-4: scored signal count == 0 after brick")
	_assert(GameManager.player_score == 1, "A-4: brick still scored +1")


## A-5: 连续 3 次拆砖（同一触球方）→ 分数 +3、计数 +3、score_changed 3 次
func _test_a5_multiple_bricks() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	var sm = _make_sm(ball)

	for i in range(3):
		sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 3, "A-5: player_score == 3 after 3 bricks")
	_assert(GameManager.get_brick_count("player") == 3, "A-5: brick count == 3")
	_assert(_captured_scores.size() == 3, "A-5: score_changed 3 times")


# ── Scenario B: 穿墙 3 分 (AC2) ──

## B-1: 穿越墙带后顶部出界 → player +3、pierce_count +1、scored 触发（走 SCORED 流）
func _test_b1_pierce_top() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_ball_score(0)

	_assert(GameManager.player_score == 3, "B-1: player_score == 3 (pierce)")
	_assert(GameManager.get_pierce_count("player") == 1, "B-1: player_pierce_count == 1")
	_assert(_scored_count == 1, "B-1: scored emitted (SCORED flow)")


## B-2: 穿越后底部出界 → ai +3
func _test_b2_pierce_bottom() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball._crossed_wall = true
	var sm = _make_sm(ball)

	sm._on_ball_score(1)

	_assert(GameManager.ai_score == 3, "B-2: ai_score == 3 (pierce)")
	_assert(GameManager.get_pierce_count("ai") == 1, "B-2: ai_pierce_count == 1")


## B-3: 未穿越出界兜底 1 分（边界 3：无墙时期游戏不坏）
func _test_b3_no_cross_boundary() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball._crossed_wall = false
	var sm = _make_sm(ball)

	sm._on_ball_score(0)

	_assert(GameManager.player_score == 1, "B-3: boundary 1 point")
	_assert(GameManager.get_pierce_count("player") == 0, "B-3: no pierce count")
	_assert(GameManager.get_brick_count("player") == 0, "B-3: kind=boundary, no brick count")


## B-4: 拆砖 +1 再穿墙 +3（不同帧）→ 总分 +4、两类计数各 1（打穿推进）
func _test_b4_brick_plus_pierce() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	ball._crossed_wall = true
	var sm = _make_sm(ball)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._process(0.016)  # 帧边界：守卫复位
	sm._on_ball_score(0)

	_assert(GameManager.player_score == 4, "B-4: brick +1 and pierce +3 → 4")
	_assert(GameManager.get_brick_count("player") == 1, "B-4: brick count 1")
	_assert(GameManager.get_pierce_count("player") == 1, "B-4: pierce count 1")


# ── Scenario C: 21 分终局 (AC3) ──

## C-1: 恰好 21 分 → match_over 恰好一次、winner 正确、is_run_over == true
func _test_c1_exactly_21() -> void:
	_reset_all()
	for i in range(20):
		GameManager.add_score("player")
	GameManager.add_score("player", 1, "brick")

	_assert(GameManager.player_score == 21, "C-1: player_score == 21")
	_assert(GameManager.is_run_over() == true, "C-1: is_run_over == true")
	_assert(_captured_match_overs.size() == 1, "C-1: match_over exactly once")
	_assert(_captured_match_overs[0] == "player", "C-1: match_over winner 'player'")


## C-2: 终局后分数冻结 —— add_score/_on_ball_score/_on_brick_destroyed 全部忽略（失败路径 2）
func _test_c2_frozen_after_end() -> void:
	_reset_all()
	for i in range(21):
		GameManager.add_score("player")
	_captured_match_overs.clear()
	_captured_scores.clear()

	var ball = _make_mock_ball()
	ball.last_toucher = "ai"
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._on_ball_score(1)
	GameManager.add_score("ai", 3, "pierce")

	_assert(GameManager.player_score == 21, "C-2: player_score frozen at 21")
	_assert(GameManager.ai_score == 0, "C-2: ai_score unchanged")
	_assert(_captured_scores.size() == 0, "C-2: no score_changed after end")
	_assert(_scored_count == 0, "C-2: no scored signal after end")
	_assert(_captured_match_overs.size() == 0, "C-2: no new match_over")


## C-3: 20 分不终局
func _test_c3_20_not_end() -> void:
	_reset_all()
	for i in range(20):
		GameManager.add_score("player")

	_assert(GameManager.is_run_over() == false, "C-3: 20 points → not run over")
	_assert(_captured_match_overs.size() == 0, "C-3: no match_over at 20")


## C-4: AI 先到 21 → match_over("ai") 恰好一次
func _test_c4_ai_21() -> void:
	_reset_all()
	for i in range(21):
		GameManager.add_score("ai")

	_assert(GameManager.is_run_over() == true, "C-4: run over")
	_assert(_captured_match_overs.size() == 1, "C-4: match_over exactly once")
	_assert(_captured_match_overs[0] == "ai", "C-4: winner 'ai'")


## C-5: 终局后 reset_match() → 全状态归零、可重新开局
func _test_c5_reset_after_end() -> void:
	_reset_all()
	for i in range(21):
		GameManager.add_score("player")
	GameManager.reset_match()

	_assert(GameManager.player_score == 0 and GameManager.ai_score == 0, "C-5: scores zeroed")
	_assert(GameManager.get_brick_count("player") == 0, "C-5: brick count zeroed")
	_assert(GameManager.get_pierce_count("ai") == 0, "C-5: pierce count zeroed")
	_assert(GameManager.is_run_over() == false, "C-5: run over reset")


# ── Scenario D: 同帧去重 (AC4) ──

## D-1: 同帧拆砖 + 出界 → 只计拆砖分（无 +3）（边界 1）
func _test_d1_same_frame_dedup() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	ball._crossed_wall = true
	var sm = _make_sm(ball)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._on_ball_score(0)

	_assert(GameManager.player_score == 1, "D-1: same frame → only brick +1")
	_assert(GameManager.get_brick_count("player") == 1, "D-1: brick count 1")
	_assert(GameManager.get_pierce_count("player") == 0, "D-1: no pierce counted")


## D-2: 不同帧各自计分 → +1 +3 都计入
func _test_d2_diff_frame_both() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	ball._crossed_wall = true
	var sm = _make_sm(ball)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._process(0.016)  # 下一帧帧首：守卫复位
	sm._on_ball_score(0)

	_assert(GameManager.player_score == 4, "D-2: different frames → +1 and +3 both")
	_assert(GameManager.get_brick_count("player") == 1, "D-2: brick count 1")
	_assert(GameManager.get_pierce_count("player") == 1, "D-2: pierce count 1")


## D-3: 帧守卫复位 —— 去重帧后下一帧出界正常计分
func _test_d3_guard_reset() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	ball._crossed_wall = true
	var sm = _make_sm(ball)

	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)
	sm._on_ball_score(0)
	_assert(GameManager.player_score == 1, "D-3a: same-frame dedup")

	sm._process(0.016)  # 下一帧帧首：守卫复位
	sm._on_ball_score(0)

	_assert(GameManager.player_score == 4, "D-3b: guard reset — next frame scores +3 normally")


# ── Scenario E: 查询 API (AC5) ──

## E-1: 混入拆砖/穿墙事件后计数与内部状态一致
func _test_e1_counts_consistent() -> void:
	_reset_all()
	GameManager.add_score("player", 1, "brick")
	GameManager.add_score("player", 1, "brick")
	GameManager.add_score("ai", 1, "brick")
	GameManager.add_score("player", 3, "pierce")

	_assert(GameManager.get_brick_count("player") == 2, "E-1: player bricks 2")
	_assert(GameManager.get_brick_count("ai") == 1, "E-1: ai bricks 1")
	_assert(GameManager.get_pierce_count("player") == 1, "E-1: player pierces 1")
	_assert(GameManager.get_pierce_count("ai") == 0, "E-1: ai pierces 0")


## E-2: fresh GameManager 四个查询全为 0
func _test_e2_initial_zero() -> void:
	_reset_all()
	_assert(GameManager.get_brick_count("player") == 0, "E-2: player bricks 0")
	_assert(GameManager.get_brick_count("ai") == 0, "E-2: ai bricks 0")
	_assert(GameManager.get_pierce_count("player") == 0, "E-2: player pierces 0")
	_assert(GameManager.get_pierce_count("ai") == 0, "E-2: ai pierces 0")


## E-3: 结算屏读取路径 —— GameOverScreen._on_match_over 能读到统计（数据路径断言，布局不测）
func _test_e3_over_screen_reads_stats() -> void:
	_reset_all()
	GameManager.add_score("player", 1, "brick")
	GameManager.add_score("player", 3, "pierce")
	GameManager.add_score("ai", 1, "brick")

	var gos = CanvasLayer.new()
	gos.set_script(load("res://gdscripts/game_over_screen.gd"))
	gos.winner_label = Label.new()
	gos.restart_label = Label.new()
	var cc = Control.new()
	cc.name = "CenterContainer"
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	var stats_label = Label.new()
	stats_label.name = "RunStatsLabel"
	vbox.add_child(stats_label)
	cc.add_child(vbox)
	gos.add_child(cc)

	gos._on_match_over("player")

	_assert(stats_label.text.contains("拆砖  P:1/A:1"), "E-3: stats label shows brick counts")
	_assert(stats_label.text.contains("穿墙  P:1/A:0"), "E-3: stats label shows pierce counts")


# ── Scenario H: 失败路径 ──

## H-1: 无 BreakoutGrid 节点时 _ready() 不崩、其余计分正常（失败路径 1）
func _test_h1_tolerant_connect_no_grid() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	var sm = _make_tree_sm(ball, null)

	sm._on_ball_score(0)
	_assert(GameManager.player_score == 1, "H-1: scoring works with no grid wired")

	_cleanup_tree([sm, ball])


## H-2: 存在带 brick_destroyed 信号的 mock grid → 连接成功、事件被消费
func _test_h2_connect_with_grid() -> void:
	_reset_all()
	var ball = _make_mock_ball()
	var grid = _make_mock_grid()
	var sm = _make_tree_sm(ball, grid)

	ball.last_toucher = "player"
	grid.brick_destroyed.emit(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 1, "H-2: brick event consumed after grid connect")
	_assert(GameManager.get_brick_count("player") == 1, "H-2: brick count 1")

	_cleanup_tree([sm, ball, grid])


## H-3: is_run_over() == true 时 _on_ball_score/_on_brick_destroyed 直接 return（失败路径 2）
func _test_h3_events_ignored_after_end() -> void:
	_reset_all()
	for i in range(21):
		GameManager.add_score("player")
	_captured_match_overs.clear()

	var ball = _make_mock_ball()
	ball.last_toucher = "player"
	ball._crossed_wall = true
	var sm = _make_sm(ball)
	sm.scored.connect(_on_scored)

	sm._on_ball_score(0)
	sm._on_brick_destroyed(Node2D.new(), Vector2.ZERO)

	_assert(GameManager.player_score == 21, "H-3: player frozen at 21")
	_assert(GameManager.ai_score == 0, "H-3: ai unchanged")
	_assert(_scored_count == 0, "H-3: no scored signal")
	_assert(_captured_match_overs.size() == 0, "H-3: no new match_over")

extends RefCounted
## Integration tests for GameStateMachine ↔ GameManager contract (#294 / #385).
## 双得分制 (#385): 21 分 run 语义 —— 分数跨发球持续累积、拆砖/穿墙计数、
## 21 分终局（is_run_over + match_over）、终局后分数冻结。
## 5 分/2 局制断言已移除（games_won/get_winner/game_won 已删除）。
##
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== FSM Integration Tests (#294/#385) ===")
	_test_int1_scores_persist_across_score_serve()
	_test_int2_point_scoring_increments_correctly()
	_test_int3_run_over_after_21()


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── INT-1: 分数跨发球持续累积（21 分制无局间清零）──
# Bug 防护: FSM 不得在每次 SERVING 时调用 GameManager.reset_match()，
# 否则 21 分 run 永远无法推进到终局。

func _test_int1_scores_persist_across_score_serve() -> void:
	GameManager.reset_match()

	# 模拟 AI 连得 5 分（21 分制下只是普通分数累积，不触发任何局级重置）
	for _i in range(5):
		GameManager.add_score("ai")

	_assert(GameManager.ai_score == 5,
		"INT1-1: ai_score == 5 after 5 scores (no game-level reset in 21-pt system)")
	_assert(GameManager.player_score == 0,
		"INT1-2: player_score unchanged")
	_assert(GameManager.is_run_over() == false,
		"INT1-3: not run over at 5 points")

	# 下一轮得分 —— 分数应继续累积
	GameManager.add_score("player")
	_assert(GameManager.player_score == 1,
		"INT1-4: player scoring starts accumulating")
	_assert(GameManager.ai_score == 5,
		"INT1-5: ai scores persist across serves")


# ── INT-2: add_score 链与计数 —— 出界/拆砖/穿墙混合 ──

func _test_int2_point_scoring_increments_correctly() -> void:
	GameManager.reset_match()

	GameManager.add_score("player")
	_assert(GameManager.player_score == 1, "INT2-1: player_score == 1")
	_assert(GameManager.ai_score == 0, "INT2-2: ai_score unchanged")

	GameManager.add_score("ai")
	_assert(GameManager.player_score == 1, "INT2-3: player_score unchanged")
	_assert(GameManager.ai_score == 1, "INT2-4: ai_score == 1")

	GameManager.add_score("player", 3, "pierce")
	GameManager.add_score("ai", 1, "brick")
	_assert(GameManager.player_score == 4, "INT2-5: player 1+3")
	_assert(GameManager.ai_score == 2, "INT2-6: ai 1+1")
	_assert(GameManager.get_pierce_count("player") == 1, "INT2-7: player pierce count 1")
	_assert(GameManager.get_brick_count("ai") == 1, "INT2-8: ai brick count 1")


# ── INT-3: 21 分终局 —— 先到 21 者赢，终局后冻结 ──

func _test_int3_run_over_after_21() -> void:
	GameManager.reset_match()

	# 玩家到 20 分 —— 未终局
	for _i in range(20):
		GameManager.add_score("player")
	_assert(GameManager.is_run_over() == false, "INT3-1: 20 points not run over")

	# 第 21 分 → 终局
	GameManager.add_score("player")
	_assert(GameManager.is_run_over() == true, "INT3-2: 21 points → run over")

	# 终局后 add_score 被守卫拦截（失败路径 2）
	GameManager.add_score("ai")
	_assert(GameManager.ai_score == 0, "INT3-3: scores frozen after run over")
	_assert(GameManager.player_score == 21, "INT3-4: winner score stays 21")

	# reset_match 后可重新开局
	GameManager.reset_match()
	_assert(GameManager.is_run_over() == false, "INT3-5: reset_match clears run over")
	_assert(GameManager.player_score == 0, "INT3-6: scores zeroed after reset")

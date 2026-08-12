extends RefCounted
## Test suite for GameManager autoload (#293) — 双得分制重写 (#385)。
## GameManager = 纯状态持有者: add_score(winner, amount, kind) / 21 分终局 / 查询 API。
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0

# ── Signal capture state ──
var _captured_scores: Array = []
var _captured_match_overs: Array = []

func _on_score_changed(p_score: int, a_score: int) -> void:
	_captured_scores.append([p_score, a_score])

func _on_match_over(winner: String) -> void:
	_captured_match_overs.append(winner)


func run() -> void:
	print("\n=== GameManager Tests (#293/#385) ===")
	_test_tc2_initial_state()
	_test_tc3_add_score_player()
	_test_tc4_add_score_ai()
	_test_tc5_add_score_invalid()
	_test_add_score_amount_kind()
	_test_brick_counting()
	_test_pierce_counting()
	_test_score_changed_signal()
	_test_win_score_21_ends_run()
	_test_ai_reaches_21()
	_test_20_points_no_end()
	_test_post_terminal_frozen()
	_test_reset_match_full_reset()
	_test_query_api()
	_test_amount_zero_ignored()


# ── Helpers ──

func _make_gm():
	var gm = Node.new()
	gm.set_script(load("res://gdscripts/game_manager.gd"))
	gm.name = "GameManager"
	return gm


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _clear_captures() -> void:
	_captured_scores.clear()
	_captured_match_overs.clear()


func _connect_signals(gm) -> void:
	gm.score_changed.connect(_on_score_changed)
	gm.match_over.connect(_on_match_over)


func _disconnect_signals(gm) -> void:
	if gm.score_changed.is_connected(_on_score_changed):
		gm.score_changed.disconnect(_on_score_changed)
	if gm.match_over.is_connected(_on_match_over):
		gm.match_over.disconnect(_on_match_over)


# ── Scenario: 初始状态 ──

## 双得分制初始状态: 分数/计数全零、未终局
func _test_tc2_initial_state() -> void:
	var gm = _make_gm()
	_assert(gm != null, "TC2: GameManager script instantiates")
	_assert(gm.player_score == 0, "TC2: player_score == 0")
	_assert(gm.ai_score == 0, "TC2: ai_score == 0")
	_assert(gm.player_brick_count == 0, "TC2: player_brick_count == 0")
	_assert(gm.ai_brick_count == 0, "TC2: ai_brick_count == 0")
	_assert(gm.player_pierce_count == 0, "TC2: player_pierce_count == 0")
	_assert(gm.ai_pierce_count == 0, "TC2: ai_pierce_count == 0")
	_assert(gm.is_run_over() == false, "TC2: is_run_over == false")


# ── Scenario: add_score() API ──

## 单参调用仍 +1（kind 默认 boundary，兼容既有调用点）
func _test_tc3_add_score_player() -> void:
	var gm = _make_gm()
	gm.add_score("player")
	_assert(gm.player_score == 1, "TC3: player_score == 1 after add_score(player)")
	_assert(gm.ai_score == 0, "TC3: ai_score == 0")
	_assert(gm.get_brick_count("player") == 0, "TC3: boundary does not bump brick count")


func _test_tc4_add_score_ai() -> void:
	var gm = _make_gm()
	gm.add_score("ai")
	_assert(gm.ai_score == 1, "TC4: ai_score == 1 after add_score(ai)")
	_assert(gm.player_score == 0, "TC4: player_score == 0")


## 非法 winner: 无状态变更、无信号（TC5 语义保留）
func _test_tc5_add_score_invalid() -> void:
	var gm = _make_gm()
	_clear_captures()
	_connect_signals(gm)

	gm.add_score("invalid")
	_assert(gm.player_score == 0, "TC5: player_score unchanged")
	_assert(gm.ai_score == 0, "TC5: ai_score unchanged")
	_assert(_captured_scores.size() == 0, "TC5: no score_changed")
	_assert(_captured_match_overs.size() == 0, "TC5: no match_over")

	_disconnect_signals(gm)


## amount/kind 参数: 穿墙 3 分进 pierce 计数、拆砖 1 分进 brick 计数
func _test_add_score_amount_kind() -> void:
	var gm = _make_gm()
	gm.add_score("player", 3, "pierce")
	_assert(gm.player_score == 3, "AK: player_score == 3 after pierce")
	_assert(gm.get_pierce_count("player") == 1, "AK: player_pierce_count == 1")
	_assert(gm.get_brick_count("player") == 0, "AK: brick_count unchanged")

	gm.add_score("ai", 1, "brick")
	_assert(gm.ai_score == 1, "AK: ai_score == 1 after brick")
	_assert(gm.get_brick_count("ai") == 1, "AK: ai_brick_count == 1")
	_assert(gm.get_pierce_count("ai") == 0, "AK: ai_pierce_count == 0")


## 拆砖计数累计
func _test_brick_counting() -> void:
	var gm = _make_gm()
	for i in range(3):
		gm.add_score("player", 1, "brick")
	_assert(gm.player_score == 3, "BK: player_score == 3")
	_assert(gm.player_brick_count == 3, "BK: player_brick_count == 3")
	_assert(gm.ai_brick_count == 0, "BK: ai_brick_count == 0")


## 穿墙计数累计
func _test_pierce_counting() -> void:
	var gm = _make_gm()
	gm.add_score("ai", 3, "pierce")
	gm.add_score("ai", 3, "pierce")
	_assert(gm.ai_score == 6, "PK: ai_score == 6")
	_assert(gm.ai_pierce_count == 2, "PK: ai_pierce_count == 2")


## score_changed 信号值与次数
func _test_score_changed_signal() -> void:
	var gm = _make_gm()
	_clear_captures()
	_connect_signals(gm)

	gm.add_score("player")
	gm.add_score("ai")
	gm.add_score("player", 1, "brick")

	_assert(_captured_scores.size() == 3, "SC: score_changed emitted 3 times")
	_assert(_captured_scores[0] == [1, 0], "SC: first [1,0]")
	_assert(_captured_scores[1] == [1, 1], "SC: second [1,1]")
	_assert(_captured_scores[2] == [2, 1], "SC: third [2,1]")

	_disconnect_signals(gm)


# ── Scenario: 21 分终局（AC3）──

## 恰好 21 分 → match_over 恰好一次
func _test_win_score_21_ends_run() -> void:
	var gm = _make_gm()
	_clear_captures()
	_connect_signals(gm)

	for i in range(20):
		gm.add_score("player")
	_assert(_captured_match_overs.size() == 0, "W21: no match_over at 20")

	gm.add_score("player", 1, "brick")
	_assert(_captured_match_overs.size() == 1, "W21: match_over emitted exactly once")
	_assert(_captured_match_overs[0] == "player", "W21: winner is 'player'")
	_assert(gm.is_run_over() == true, "W21: is_run_over == true")

	_disconnect_signals(gm)


## AI 先到 21
func _test_ai_reaches_21() -> void:
	var gm = _make_gm()
	_clear_captures()
	_connect_signals(gm)

	for i in range(21):
		gm.add_score("ai")
	_assert(_captured_match_overs.size() == 1, "AI21: match_over emitted exactly once")
	_assert(_captured_match_overs[0] == "ai", "AI21: winner is 'ai'")
	_assert(gm.is_run_over() == true, "AI21: is_run_over == true")

	_disconnect_signals(gm)


## 20 分不终局
func _test_20_points_no_end() -> void:
	var gm = _make_gm()
	_clear_captures()
	_connect_signals(gm)

	for i in range(20):
		gm.add_score("player")
	_assert(gm.is_run_over() == false, "20P: is_run_over == false")
	_assert(_captured_match_overs.size() == 0, "20P: no match_over")

	_disconnect_signals(gm)


## 终局后分数冻结（失败路径 2）
func _test_post_terminal_frozen() -> void:
	var gm = _make_gm()
	_clear_captures()
	_connect_signals(gm)

	for i in range(21):
		gm.add_score("player")
	_assert(gm.is_run_over() == true, "PT: run over")

	gm.add_score("player", 3, "pierce")
	_assert(gm.player_score == 21, "PT: player_score frozen")
	_assert(gm.get_pierce_count("player") == 0, "PT: pierce not counted")
	_assert(_captured_scores.size() == 21, "PT: no further score_changed")

	gm.add_score("ai", 1, "brick")
	_assert(gm.ai_score == 0, "PT: ai_score unchanged")

	_disconnect_signals(gm)


## reset_match 全量重置
func _test_reset_match_full_reset() -> void:
	var gm = _make_gm()
	gm.add_score("player", 3, "pierce")
	gm.add_score("ai", 1, "brick")
	for i in range(21):
		gm.add_score("player")
	_assert(gm.is_run_over() == true, "RM: run over before reset")

	gm.reset_match()
	_assert(gm.player_score == 0, "RM: player_score == 0")
	_assert(gm.ai_score == 0, "RM: ai_score == 0")
	_assert(gm.player_brick_count == 0, "RM: player_brick_count == 0")
	_assert(gm.ai_brick_count == 0, "RM: ai_brick_count == 0")
	_assert(gm.player_pierce_count == 0, "RM: player_pierce_count == 0")
	_assert(gm.ai_pierce_count == 0, "RM: ai_pierce_count == 0")
	_assert(gm.is_run_over() == false, "RM: is_run_over == false")

	gm.add_score("player")
	_assert(gm.player_score == 1, "RM: scoring works after reset")


# ── Scenario: 查询 API（AC5）──

func _test_query_api() -> void:
	var gm = _make_gm()
	gm.add_score("player", 1, "brick")
	gm.add_score("player", 3, "pierce")
	gm.add_score("ai", 1, "brick")

	_assert(gm.get_brick_count("player") == 1, "QA: player brick == 1")
	_assert(gm.get_brick_count("ai") == 1, "QA: ai brick == 1")
	_assert(gm.get_pierce_count("player") == 1, "QA: player pierce == 1")
	_assert(gm.get_pierce_count("ai") == 0, "QA: ai pierce == 0")


# ── Scenario: 边界 ──

## amount <= 0 直接忽略
func _test_amount_zero_ignored() -> void:
	var gm = _make_gm()
	_clear_captures()
	_connect_signals(gm)

	gm.add_score("player", 0, "brick")
	gm.add_score("player", -1, "pierce")
	_assert(gm.player_score == 0, "AZ: player_score unchanged")
	_assert(gm.get_brick_count("player") == 0, "AZ: brick unchanged")
	_assert(_captured_scores.size() == 0, "AZ: no signal")

	_disconnect_signals(gm)

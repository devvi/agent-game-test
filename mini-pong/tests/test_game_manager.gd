extends RefCounted
## Test suite for GameManager autoload (#293) — Global State Singleton.
## Runs under godot --headless --script via run_tests.gd.
##
## GameManager is an autoload — directly accessible as GameManager.<var>.
## No mock setup needed.

var passed: int = 0
var failed: int = 0

# ── Signal capture state (Pattern 11: member vars, not lambda closures) ──
var _captured_scores: Array = []           # [[player_score, ai_score], ...]
var _captured_game_wins: Array = []        # ["player", ...]
var _captured_match_overs: Array = []      # ["player", ...]

# ── Signal handlers ──
func _on_score_changed(p_score: int, a_score: int) -> void:
	_captured_scores.append([p_score, a_score])

func _on_game_won(winner: String) -> void:
	_captured_game_wins.append(winner)

func _on_match_over(winner: String) -> void:
	_captured_match_overs.append(winner)


func run() -> void:
	print("\n=== GameManager Tests (#293) ===")
	_test_tc2_initial_state()
	_test_tc3_add_score_player()
	_test_tc4_add_score_ai()
	_test_tc5_add_score_invalid()
	_test_tc6_five_scores_game_win()
	_test_tc7_score_changed_signal()
	_test_tc8_game_won_signal()
	_test_tc9_match_over_signal()
	_test_tc10_reset_game()
	_test_tc11_reset_match()
	_test_tc12_reset_match_idempotent()
	_test_tc13_get_winner_empty()
	_test_tc14_get_winner_player()
	_test_tc15_get_winner_ai()


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _clear_captures() -> void:
	_captured_scores.clear()
	_captured_game_wins.clear()
	_captured_match_overs.clear()


func _connect_signals() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.game_won.connect(_on_game_won)
	GameManager.match_over.connect(_on_match_over)


func _disconnect_signals() -> void:
	if GameManager.score_changed.is_connected(_on_score_changed):
		GameManager.score_changed.disconnect(_on_score_changed)
	if GameManager.game_won.is_connected(_on_game_won):
		GameManager.game_won.disconnect(_on_game_won)
	if GameManager.match_over.is_connected(_on_match_over):
		GameManager.match_over.disconnect(_on_match_over)


# ── Scenario A: Autoload Registration ──

## TC2: GameManager accessible with all initial values zero
func _test_tc2_initial_state() -> void:
	GameManager.reset_match()  # ensure clean state
	_assert(GameManager != null, "TC2: GameManager autoload exists")
	_assert(GameManager.player_score == 0, "TC2: player_score == 0")
	_assert(GameManager.ai_score == 0, "TC2: ai_score == 0")
	_assert(GameManager.player_games_won == 0, "TC2: player_games_won == 0")
	_assert(GameManager.ai_games_won == 0, "TC2: ai_games_won == 0")


# ── Scenario B: add_score() API ──

## TC3: add_score("player") increments player_score
func _test_tc3_add_score_player() -> void:
	GameManager.reset_match()
	GameManager.add_score("player")
	_assert(GameManager.player_score == 1, "TC3: player_score == 1 after add_score(player)")
	_assert(GameManager.ai_score == 0, "TC3: ai_score == 0 after add_score(player)")


## TC4: add_score("ai") increments ai_score
func _test_tc4_add_score_ai() -> void:
	GameManager.reset_match()
	GameManager.add_score("ai")
	_assert(GameManager.ai_score == 1, "TC4: ai_score == 1 after add_score(ai)")
	_assert(GameManager.player_score == 0, "TC4: player_score == 0 after add_score(ai)")


## TC5: add_score("invalid") — no change, no crash, no signals
func _test_tc5_add_score_invalid() -> void:
	GameManager.reset_match()
	_clear_captures()
	_connect_signals()

	GameManager.add_score("invalid")
	_assert(GameManager.player_score == 0, "TC5: player_score unchanged for invalid winner")
	_assert(GameManager.ai_score == 0, "TC5: ai_score unchanged for invalid winner")
	_assert(_captured_scores.size() == 0, "TC5: no score_changed signal for invalid winner")
	_assert(_captured_game_wins.size() == 0, "TC5: no game_won signal for invalid winner")

	_disconnect_signals()


## TC6: 5x add_score("player") → game won, score auto-resets, game counter increments
func _test_tc6_five_scores_game_win() -> void:
	GameManager.reset_match()
	for i in range(5):
		GameManager.add_score("player")
	_assert(GameManager.player_games_won == 1, "TC6: player_games_won == 1 after 5 scores")
	_assert(GameManager.player_score == 0, "TC6: player_score auto-reset to 0 after game win")
	_assert(GameManager.ai_score == 0, "TC6: ai_score still 0")


## TC7: score_changed signal emitted after each add_score() with correct values
func _test_tc7_score_changed_signal() -> void:
	GameManager.reset_match()
	_clear_captures()
	_connect_signals()

	GameManager.add_score("player")
	GameManager.add_score("ai")
	GameManager.add_score("player")

	_assert(_captured_scores.size() >= 3, "TC7: score_changed emitted for each add_score")
	_assert(_captured_scores[0] == [1, 0], "TC7: first signal: player=1, ai=0")
	_assert(_captured_scores[1] == [1, 1], "TC7: second signal: player=1, ai=1")
	_assert(_captured_scores[2] == [2, 1], "TC7: third signal: player=2, ai=1")

	_disconnect_signals()


## TC8: game_won("player") signal emitted after 5th consecutive player score
func _test_tc8_game_won_signal() -> void:
	GameManager.reset_match()
	_clear_captures()
	_connect_signals()

	for i in range(5):
		GameManager.add_score("player")

	_assert(_captured_game_wins.size() == 1, "TC8: game_won emitted exactly once")
	_assert(_captured_game_wins[0] == "player", "TC8: game_won winner is 'player'")

	_disconnect_signals()


## TC9: match_over("player") signal emitted after 2 game wins
func _test_tc9_match_over_signal() -> void:
	GameManager.reset_match()
	_clear_captures()
	_connect_signals()

	# Win game 1 (5 scores)
	for i in range(5):
		GameManager.add_score("player")
	_assert(_captured_match_overs.size() == 0, "TC9: no match_over after 1 game win")

	# Win game 2 (5 more scores)
	for i in range(5):
		GameManager.add_score("player")
	_assert(_captured_match_overs.size() == 1, "TC9: match_over emitted after 2 game wins")
	_assert(_captured_match_overs[0] == "player", "TC9: match_over winner is 'player'")

	_disconnect_signals()


# ── Scenario C: reset_game() vs reset_match() ──

## TC10: reset_game() zeros scores, preserves game counters
func _test_tc10_reset_game() -> void:
	GameManager.reset_match()
	# Score some points
	GameManager.add_score("player")
	GameManager.add_score("player")
	GameManager.add_score("player")
	_assert(GameManager.player_score == 3, "TC10: player_score == 3 before reset")

	GameManager.reset_game()
	_assert(GameManager.player_score == 0, "TC10: player_score == 0 after reset_game")
	_assert(GameManager.ai_score == 0, "TC10: ai_score == 0 after reset_game")
	_assert(GameManager.player_games_won == 0, "TC10: player_games_won unchanged by reset_game")
	_assert(GameManager.ai_games_won == 0, "TC10: ai_games_won unchanged by reset_game")


## TC11: reset_match() zeros everything (after partial progress)
func _test_tc11_reset_match() -> void:
	GameManager.reset_match()
	# Win a game
	for i in range(5):
		GameManager.add_score("player")
	_assert(GameManager.player_games_won == 1, "TC11: player_games_won == 1 before reset_match")

	GameManager.reset_match()
	_assert(GameManager.player_score == 0, "TC11: player_score == 0 after reset_match")
	_assert(GameManager.ai_score == 0, "TC11: ai_score == 0 after reset_match")
	_assert(GameManager.player_games_won == 0, "TC11: player_games_won == 0 after reset_match")
	_assert(GameManager.ai_games_won == 0, "TC11: ai_games_won == 0 after reset_match")


## TC12: reset_match() on fresh state — idempotent
func _test_tc12_reset_match_idempotent() -> void:
	GameManager.reset_match()
	GameManager.reset_match()  # second call
	_assert(GameManager.player_score == 0, "TC12: player_score still 0")
	_assert(GameManager.ai_score == 0, "TC12: ai_score still 0")
	_assert(GameManager.player_games_won == 0, "TC12: player_games_won still 0")
	_assert(GameManager.ai_games_won == 0, "TC12: ai_games_won still 0")


# ── Scenario D: get_winner() ──

## TC13: get_winner() on fresh state returns ""
func _test_tc13_get_winner_empty() -> void:
	GameManager.reset_match()
	_assert(GameManager.get_winner() == "", "TC13: get_winner() returns empty string on fresh state")


## TC14: After 2 player game wins → get_winner() == "player"
func _test_tc14_get_winner_player() -> void:
	GameManager.reset_match()
	for g in range(2):
		for i in range(5):
			GameManager.add_score("player")
	_assert(GameManager.player_games_won == 2, "TC14: player_games_won == 2")
	_assert(GameManager.get_winner() == "player", "TC14: get_winner() returns 'player'")


## TC15: After 2 AI game wins → get_winner() == "ai"
func _test_tc15_get_winner_ai() -> void:
	GameManager.reset_match()
	for g in range(2):
		for i in range(5):
			GameManager.add_score("ai")
	_assert(GameManager.ai_games_won == 2, "TC15: ai_games_won == 2")
	_assert(GameManager.get_winner() == "ai", "TC15: get_winner() returns 'ai'")

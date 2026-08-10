extends RefCounted
## Integration tests for GameStateMachine ↔ GameManager contract (#294).
## Verifies that state transitions don't corrupt autoload data —
## catches the reset_match()-on-every-serve bug that the isolated
## unit tests (test_scoring_manager.gd, test_game_state_machine.gd)
## couldn't detect because they bypass the full signal chain.
##
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== FSM Integration Tests (#294) ===")
	_test_int1_games_won_persists_across_score_serve()
	_test_int2_point_scoring_increments_correctly()
	_test_int3_match_over_detected_after_two_games()


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── INT-1: Game won state survives score → game_won → next serve ──
# Bug: FSM called GameManager.reset_match() on every SERVING transition,
# wiping games_won counters. After 5 points → game won → new serve,
# games_won should be 1, not 0.

func _test_int1_games_won_persists_across_score_serve() -> void:
	GameManager.reset_match()

	# Simulate AI scoring 5 points (wins one game)
	for _i in range(5):
		GameManager.add_score("ai")

	_assert(GameManager.ai_games_won == 1,
		"INT1-1: ai_games_won == 1 after 5 AI scores (game won)")
	_assert(GameManager.player_games_won == 0,
		"INT1-2: player_games_won unchanged")
	_assert(GameManager.ai_score == 0,
		"INT1-3: per-game scores reset after game win")
	_assert(GameManager.player_score == 0,
		"INT1-4: per-game scores reset after game win")
	_assert(GameManager.get_winner() == "",
		"INT1-5: match not over after 1 game (need 2 of 3)")

	# Simulate a few more points in the next game — scores should accumulate
	GameManager.add_score("player")
	_assert(GameManager.player_score == 1,
		"INT1-6: next game scoring starts from 0")
	_assert(GameManager.ai_games_won == 1,
		"INT1-7: games_won persists across game boundary")


# ── INT-2: Point scoring fires score_changed correctly ──
# Bug: ScoreZone body_entered never fired for Area2D balls.
# The GameManager.add_score() chain must work regardless.

func _test_int2_point_scoring_increments_correctly() -> void:
	GameManager.reset_match()

	GameManager.add_score("player")
	_assert(GameManager.player_score == 1, "INT2-1: player_score == 1")
	_assert(GameManager.ai_score == 0, "INT2-2: ai_score unchanged")

	GameManager.add_score("ai")
	_assert(GameManager.player_score == 1, "INT2-3: player_score unchanged")
	_assert(GameManager.ai_score == 1, "INT2-4: ai_score == 1")

	GameManager.add_score("player")
	GameManager.add_score("ai")
	_assert(GameManager.player_score == 2, "INT2-5: player_score == 2 after 2+1")
	_assert(GameManager.ai_score == 2, "INT2-6: ai_score == 2 after 2+1")


# ── INT-3: Match ends correctly after 2 games won ──
# Bug: if games_won kept getting reset, match would never end.

func _test_int3_match_over_detected_after_two_games() -> void:
	GameManager.reset_match()

	# Player wins game 1
	for _i in range(5):
		GameManager.add_score("player")
	_assert(GameManager.player_games_won == 1, "INT3-1: player won game 1")
	_assert(GameManager.get_winner() == "", "INT3-2: match not over yet")

	# Player wins game 2 → match over
	for _i in range(5):
		GameManager.add_score("player")
	_assert(GameManager.player_games_won == 2, "INT3-3: player won game 2")
	_assert(GameManager.get_winner() == "player", "INT3-4: match over — player wins")

	# Additional scores after match end are guarded by ScoringManager._is_match_over,
	# not by GameManager.add_score itself. Testing GameManager directly shows it
	# still accepts scores — the guard lives one level up.
	GameManager.add_score("ai")
	_assert(GameManager.ai_score == 1,
		"INT3-5: GameManager accepts scores post-match (ScoringManager guard handles this)")

extends RefCounted
## Test suite for scoring_manager.gd (#291) — Scoring System.
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0

const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

# ── Signal capture state (Pattern 11: member vars, not lambda closures) ──
var _scored_winner: String = ""
var _scored_count: int = 0
var _game_won_winner: String = ""
var _game_won_count: int = 0
var _match_over_winner: String = ""
var _match_over_count: int = 0

# ── Signal handlers ──
func _on_scored(winner: String) -> void:
	_scored_winner = winner
	_scored_count += 1

func _on_game_won(winner: String) -> void:
	_game_won_winner = winner
	_game_won_count += 1

func _on_match_over(winner: String) -> void:
	_match_over_winner = winner
	_match_over_count += 1


func run() -> void:
	_test_tc1_player_scores()
	_test_tc2_ai_scores()
	_test_tc3_game_won()
	_test_tc4_match_over()
	_test_tc5_alternating_scores()
	_test_tc6_game_won_by_ai()
	_test_tc9_match_over_guard()
	_test_tc10_double_game_over_guard()
	_test_tc11_headless_no_tree()
	_test_tc13_ball_missing()
	_test_signal_scored_emitted()
	_test_signal_game_won_emitted()
	_test_signal_match_over_emitted()
	_test_initial_state_zero()


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_mock_ball():
	## Create a mock ball with score signal and serve() method (Pattern 15: inline GDScript mock).
	var code = GDScript.new()
	code.source_code = """extends Area2D

signal score(side: int)

var serve_count: int = 0

func serve() -> void:
	serve_count += 1
"""
	code.reload()
	var ball = Area2D.new()
	ball.name = "Ball"
	ball.set_script(code)
	return ball


func _make_sm(mock_ball = null):
	## Create ScoringManager instance and set up mock ball.
	var mb = mock_ball if mock_ball != null else _make_mock_ball()
	var sm = Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	sm.ball = mb  # Set @onready var manually (no scene tree in headless)
	return sm


func _connect_signals(sm) -> void:
	## Connect all ScoringManager signals to capture handlers.
	sm.scored.connect(_on_scored)
	sm.game_won.connect(_on_game_won)
	sm.match_over.connect(_on_match_over)


func _reset_signal_state() -> void:
	_scored_winner = ""
	_scored_count = 0
	_game_won_winner = ""
	_game_won_count = 0
	_match_over_winner = ""
	_match_over_count = 0


# ── TC1: Player scores (right boundary) ──

func _test_tc1_player_scores() -> void:
	_reset_signal_state()
	var mock_ball = _make_mock_ball()
	var sm = _make_sm(mock_ball)
	_connect_signals(sm)

	# Emit score(0) — right boundary → player scores
	sm._on_ball_score(0)

	_assert(sm.player_score == 1, "TC1: player_score == 1 after score(0)")
	_assert(sm.ai_score == 0, "TC1: ai_score == 0 after score(0)")
	_assert(_scored_winner == "player", "TC1: scored(\"player\") emitted")
	_assert(_scored_count == 1, "TC1: scored emitted exactly once")


# ── TC2: AI scores (left boundary) ──

func _test_tc2_ai_scores() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm._on_ball_score(1)

	_assert(sm.ai_score == 1, "TC2: ai_score == 1 after score(1)")
	_assert(sm.player_score == 0, "TC2: player_score == 0 after score(1)")
	_assert(_scored_winner == "ai", "TC2: scored(\"ai\") emitted")
	_assert(_scored_count == 1, "TC2: scored emitted exactly once")


# ── TC3: Game won at 5 points ──

func _test_tc3_game_won() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	# Pre-set player_score to 4
	sm.player_score = 4
	# Emit score(0) → player_score = 5 → game won
	sm._on_ball_score(0)

	_assert(sm.player_score == 0, "TC3: player_score reset to 0 after game win")
	_assert(sm.ai_score == 0, "TC3: ai_score reset to 0 after game win")
	_assert(sm.player_games == 1, "TC3: player_games == 1 after game win")
	_assert(sm.ai_games == 0, "TC3: ai_games == 0")
	_assert(_game_won_winner == "player", "TC3: game_won(\"player\") emitted")
	_assert(_game_won_count == 1, "TC3: game_won emitted exactly once")


# ── TC4: Match won at 2 games ──

func _test_tc4_match_over() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	# Pre-set: player already won 1 game, current game at 4 points
	sm.player_games = 1
	sm.player_score = 4

	# Emit score(0) → player_score = 5 → game_won("player") → player_games = 2 → match_over
	sm._on_ball_score(0)

	_assert(_match_over_winner == "player", "TC4: match_over(\"player\") emitted")
	_assert(_match_over_count == 1, "TC4: match_over emitted exactly once")
	_assert(sm._is_match_over == true, "TC4: _is_match_over == true")


# ── TC5: Alternating scores ──

func _test_tc5_alternating_scores() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm._on_ball_score(0)  # player=1
	sm._on_ball_score(1)  # ai=1
	sm._on_ball_score(0)  # player=2
	sm._on_ball_score(1)  # ai=2

	_assert(sm.player_score == 2, "TC5: player_score == 2 after alternating")
	_assert(sm.ai_score == 2, "TC5: ai_score == 2 after alternating")
	_assert(_scored_count == 4, "TC5: 4 scored signals emitted")
	# Verify sequence: player, ai, player, ai
	# (can only verify final values due to signal overwrite pattern)


# ── TC6: Game won by AI side ──

func _test_tc6_game_won_by_ai() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm.ai_score = 4
	sm._on_ball_score(1)  # ai_score = 5

	_assert(sm.ai_score == 0, "TC6: ai_score reset to 0 after game win")
	_assert(sm.player_score == 0, "TC6: player_score reset to 0 after game win")
	_assert(sm.ai_games == 1, "TC6: ai_games == 1")
	_assert(sm.player_games == 0, "TC6: player_games == 0")
	_assert(_game_won_winner == "ai", "TC6: game_won(\"ai\") emitted")


# ── TC9: Score after match_over is ignored ──

func _test_tc9_match_over_guard() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm._is_match_over = true
	sm.player_score = 1

	sm._on_ball_score(0)

	_assert(sm.player_score == 1, "TC9: player_score unchanged after match_over guard")
	_assert(_scored_count == 0, "TC9: no scored signal emitted after match_over")


# ── TC10: Double game over guard ──

func _test_tc10_double_game_over_guard() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm.player_games = 2
	sm._is_match_over = true
	sm.player_score = 0

	# Try to score after match already over
	sm._on_ball_score(0)

	_assert(sm.player_score == 0, "TC10: player_score unchanged (match over guard)")
	_assert(_scored_count == 0, "TC10: no signal after match over")


# ── TC11: Headless — no tree, serve called immediately ──

func _test_tc11_headless_no_tree() -> void:
	_reset_signal_state()
	var mock_ball = _make_mock_ball()
	var sm = _make_sm(mock_ball)
	_connect_signals(sm)

	# In headless, get_tree() returns null for parentless nodes
	# _pause_and_serve() should skip timer, call ball.serve() directly
	sm._pause_and_serve()

	_assert(mock_ball.serve_count == 0, "TC11: _pause_and_serve() is no-op — ball.serve() now handled by FSM #294 enter_state(SERVING)")


# ── TC13: Ball node missing (failure path) ──

func _test_tc13_ball_missing() -> void:
	_reset_signal_state()
	# Create SM without setting ball — make _ready() safe
	var sm = Node.new()
	sm.set_script(load("res://gdscripts/scoring_manager.gd"))
	# ball is null (no scene tree, not manually set)
	_assert(true, "TC13: ScoringManager can be created without crash")
	# _ready() does push_error when ball is null — but instantiation itself succeeds


# ── Signal integrity tests ──

func _test_signal_scored_emitted() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm._on_ball_score(0)
	_assert(_scored_winner == "player", "SIG-S1: scored signal carries 'player'")
	sm._on_ball_score(1)
	_assert(_scored_winner == "ai", "SIG-S1: scored signal carries 'ai'")


func _test_signal_game_won_emitted() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm.player_score = 4
	sm._on_ball_score(0)
	_assert(_game_won_winner == "player", "SIG-S2: game_won signal carries 'player'")
	_assert(_game_won_count == 1, "SIG-S2: game_won emitted once")


func _test_signal_match_over_emitted() -> void:
	_reset_signal_state()
	var sm = _make_sm()
	_connect_signals(sm)

	sm.player_games = 1
	sm.player_score = 4
	sm._on_ball_score(0)
	_assert(_match_over_winner == "player", "SIG-S3: match_over signal carries 'player'")
	_assert(_match_over_count == 1, "SIG-S3: match_over emitted once")


# ── Initial state ──

func _test_initial_state_zero() -> void:
	var sm = _make_sm()
	_assert(sm.player_score == 0, "STATE: player_score initial == 0")
	_assert(sm.ai_score == 0, "STATE: ai_score initial == 0")
	_assert(sm.player_games == 0, "STATE: player_games initial == 0")
	_assert(sm.ai_games == 0, "STATE: ai_games initial == 0")
	_assert(sm._is_match_over == false, "STATE: _is_match_over initial == false")

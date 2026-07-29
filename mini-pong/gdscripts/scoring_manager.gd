extends Node
## ScoringManager — consumes ball.score(side) signals and tracks points/games/matches.
## Event-driven: no polling, no _process. Uses await for pause-then-serve flow.
##
## Signal chain:
##   Ball._process() → ball.score(side: int)
##     → ScoringManager._on_ball_score(side)
##       → scored(winner: String)     ← per-point UI updates
##       → game_won(winner: String)   ← per-game conclusion (5 points)
##       → match_over(winner: String) ← per-match conclusion (2 games)
##
## Design: docs/DESIGN/291-scoring-system.md §2.1
## Parent Issue: #291

# ── Configuration ──
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

# ── Signals ──
signal scored(winner: String)       # "player" | "ai" — emitted every point
signal game_won(winner: String)     # "player" | "ai" — emitted when a game concludes
signal match_over(winner: String)   # "player" | "ai" — emitted when the match concludes

# ── State (publicly readable) ──
var player_score: int = 0
var ai_score: int = 0
var player_games: int = 0
var ai_games: int = 0
var _is_match_over: bool = false

# ── Node References ──
@onready var ball: Area2D = $"../Ball"
@onready var score_flash: Node = get_node_or_null("../ScoreFlash")


func _ready() -> void:
	# Validate ball reference
	if ball == null:
		push_error("ScoringManager: Ball node not found — scoring disabled")
		return

	# Connect to ball's score signal
	ball.score.connect(_on_ball_score)

	# Wire score flash if present (best-effort — scoring works without it)
	if score_flash != null and score_flash.has_method("_on_score_changed"):
		scored.connect(score_flash._on_score_changed)


func _on_ball_score(side: int) -> void:
	# Guard: ignore scores after match concludes
	if _is_match_over:
		return

	# Determine winner (side: 0 = right boundary → player, 1 = left boundary → AI)
	var winner: String = "ai" if side == 1 else "player"

	# Increment score
	match winner:
		"player":
			player_score += 1
		"ai":
			ai_score += 1

	# Emit per-point signal
	scored.emit(winner)
	GameManager.add_score(winner)

	# Check game win threshold
	if player_score >= POINTS_TO_WIN_GAME:
		_win_game("player")
	elif ai_score >= POINTS_TO_WIN_GAME:
		_win_game("ai")


func _win_game(winner: String) -> void:
	# Emit game-level signal
	game_won.emit(winner)

	# Increment game counter
	match winner:
		"player":
			player_games += 1
		"ai":
			ai_games += 1

	# Reset per-game scores
	player_score = 0
	ai_score = 0

	# Check match win threshold
	if player_games >= GAMES_TO_WIN_MATCH:
		_is_match_over = true
		match_over.emit("player")
		return
	elif ai_games >= GAMES_TO_WIN_MATCH:
		_is_match_over = true
		match_over.emit("ai")
		return

	# Match not over — FSM (#294) handles serve timing


func _pause_and_serve() -> void:
	# FSM (#294) handles pause + serve timing.
	# ScoringManager now only emits signals; no longer controls ball serve.
	pass

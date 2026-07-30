extends Node
## GameManager — autoload singleton for global game state.
## Pure-data holder: scores, games won, reset APIs, and signals.
## Does NOT duplicate ScoringManager logic — provides global namespace.
##
## Design: docs/DESIGN/293-game-manager-global-state.md
## Parent Issue: #293

# ── Configuration (via GameConstants #295) ──
const CONSTS = preload("res://gdscripts/constants.gd")
const POINTS_TO_WIN_GAME: int = CONSTS.POINTS_TO_WIN_GAME
const GAMES_TO_WIN_MATCH: int = CONSTS.GAMES_TO_WIN_MATCH

# ── Signals ──
signal score_changed(player_score: int, ai_score: int)
signal game_won(winner: String)       # "player" | "ai"
signal match_over(winner: String)     # "player" | "ai"

# ── State ──
var player_score: int = 0
var ai_score: int = 0
var player_games_won: int = 0
var ai_games_won: int = 0

# ── API ──

func add_score(winner: String) -> void:
    match winner:
        "player":
            player_score += 1
        "ai":
            ai_score += 1
        _:
            return
    score_changed.emit(player_score, ai_score)
    _check_game_win()


func reset_game() -> void:
    player_score = 0
    ai_score = 0


func reset_match() -> void:
    player_score = 0
    ai_score = 0
    player_games_won = 0
    ai_games_won = 0


func get_winner() -> String:
    if player_games_won >= GAMES_TO_WIN_MATCH:
        return "player"
    if ai_games_won >= GAMES_TO_WIN_MATCH:
        return "ai"
    return ""


# ── Internal ──

func _check_game_win() -> void:
    if player_score >= POINTS_TO_WIN_GAME:
        _win_game("player")
    elif ai_score >= POINTS_TO_WIN_GAME:
        _win_game("ai")


func _win_game(winner: String) -> void:
    game_won.emit(winner)
    match winner:
        "player":
            player_games_won += 1
        "ai":
            ai_games_won += 1
    player_score = 0
    ai_score = 0
    if player_games_won >= GAMES_TO_WIN_MATCH or ai_games_won >= GAMES_TO_WIN_MATCH:
        match_over.emit(winner)

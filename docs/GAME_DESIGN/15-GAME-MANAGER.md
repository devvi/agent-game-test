# Game Manager — Global State Singleton

> Reference: ../DESIGN/293-game-manager-global-state.md
> Parent Issue: #293

## Overview

GameManager is an autoload singleton that provides a global namespace for game state
— player and AI scores, games won, and match tracking. It sits **above** the existing
`ScoringManager` (scene-bound Node) as a persistent, globally-accessible data layer.

The GameManager does NOT duplicate scoring logic. ScoringManager remains the
authoritative source for score events (ball boundary → points). GameManager
provides the global API (`reset_game()`, `reset_match()`, `get_winner()`) that
the scene-bound ScoringManager cannot offer.

## Relationship to ScoringManager

| Concern | ScoringManager (#291) | GameManager (#293) |
|---------|----------------------|-------------------|
| Lifecycle | Scene Node (dies with game.tscn) | Autoload singleton (survives scene changes) |
| Score increment logic | ✅ `_on_ball_score(side)` + threshold checks | ✅ `add_score(winner)` — simpler, no Ball dependency |
| Signals | `scored(winner)`, `game_won(winner)`, `match_over(winner)` | `score_changed(p, a)`, `game_won(winner)`, `match_over(winner)` |
| Reset API | ❌ No public reset methods | ✅ `reset_game()`, `reset_match()` |
| Winner query | ❌ Must inspect private vars | ✅ `get_winner() → String` |
| Global access | ❌ `get_node("../ScoringManager")` | ✅ `GameManager.player_score` |
| Headless compatible | ❌ `@onready var ball` fails in headless | ✅ No scene dependencies |

## Node Tree

```
GameManager (autoload, extends Node)
```

Registered as `GameManager` in `mini-pong/project.godot`:
```ini
[autoload]
GameManager="*res://gdscripts/game_manager.gd"
```

## Configuration

| Parameter | Value | Description |
|-----------|:-----:|-------------|
| Points to win a game | 5 | `POINTS_TO_WIN_GAME` |
| Games to win a match | 2 | `GAMES_TO_WIN_MATCH` |

## Signals

```gdscript
signal score_changed(player_score: int, ai_score: int)    # Emitted after every add_score()
signal game_won(winner: String)                            # "player" | "ai" — game concludes
signal match_over(winner: String)                          # "player" | "ai" — match concludes
```

## State Variables

| Variable | Type | Default | Description |
|----------|------|:-------:|-------------|
| `player_score` | int | 0 | Points in current game (0–5) |
| `ai_score` | int | 0 | Points in current game (0–5) |
| `player_games_won` | int | 0 | Games won by player (0–2) |
| `ai_games_won` | int | 0 | Games won by AI (0–2) |

## Public API

| Method | Signature | Behavior |
|--------|-----------|----------|
| `add_score` | `func add_score(winner: String) -> void` | Increments score; emits `score_changed`; checks game/match win |
| `reset_game` | `func reset_game() -> void` | Zeros per-game scores; preserves game counters |
| `reset_match` | `func reset_match() -> void` | Zeros all four state vars; full reset |
| `get_winner` | `func get_winner() -> String` | Returns `"player"` / `"ai"` / `""` |

## Signal Emission Order

Per `add_score()`:
1. `score_changed.emit(player_score, ai_score)` — first (UI updates before conclusion effects)
2. If threshold reached: `game_won.emit(winner)` — second
3. If 2 games won: `match_over.emit(winner)` — third

## Edge Cases

| # | Edge Case | Behavior |
|---|-----------|----------|
| 1 | `add_score()` with invalid winner | Silent no-op — no score change, no signal |
| 2 | `add_score()` after `match_over` | Score increments; `_check_game_win()` re-fires. Caller's responsibility to guard. |
| 3 | `reset_game()` mid-round | Scores zeroed; game counters preserved |
| 4 | `reset_match()` any time | Full reset; no validation |
| 5 | `get_winner()` when no winner | Returns `""` — consumers check `result != ""` |

## Test Coverage

| Area | Tests | Description |
|------|:-----:|-------------|
| Initial state | TC2 | All counters zero + script instantiates |
| add_score("player") | TC3 | player_score increments, ai_score unchanged |
| add_score("ai") | TC4 | ai_score increments, player_score unchanged |
| add_score("invalid") | TC5 | No change, no crash, no signals |
| Game win (5 pts) | TC6 | player_games_won += 1, scores auto-reset |
| score_changed signal | TC7 | Signal emitted with correct (p, a) after each add_score |
| game_won signal | TC8 | game_won("player") after 5th consecutive score |
| match_over signal | TC9 | match_over("player") after 2 game wins |
| reset_game() | TC10 | Scores zeroed, game counters preserved |
| reset_match() | TC11 | All four vars zeroed after partial progress |
| reset_match() idempotent | TC12 | Calling on fresh state — no side effects |
| get_winner() empty | TC13 | Returns "" on fresh state |
| get_winner() player | TC14 | Returns "player" after 2 player game wins |
| get_winner() ai | TC15 | Returns "ai" after 2 AI game wins |

**Test file:** `mini-pong/tests/test_game_manager.gd` (44 tests across 15 test cases, all passing)

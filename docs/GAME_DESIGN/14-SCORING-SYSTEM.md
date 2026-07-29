# Scoring System

> Reference: ../DESIGN/291-scoring-system.md
> Parent Issue: #291

## Overview

The Scoring System translates low-level boundary events (`ball.score(side)`) into
high-level scoring events — points, games, and matches. It is a self-contained
`ScoringManager` Node that sits in the game scene and operates entirely via signals
with no polling or `_process` dependency.

The system runs independently of any autoload or global state. It is designed to
work in both headless (test) and runtime (playable) modes with graceful degradation
when optional dependencies (like `ScoreFlash`) are absent.

## Node Tree

```
ScoringManager (Node, scoring_manager.gd)
```

The `ScoringManager` is a sibling of `Ball` and `PlayerPaddle` in `game.tscn`.
It references the ball via `$"../Ball"` and optionally connects to `ScoreFlash`
via `get_node_or_null("../ScoreFlash")`.

## Signal Chain

```
Ball._process() → ball.score(side: int)
    │
    ▼
ScoringManager._on_ball_score(side)
    │
    ├── scored(winner: String)         ← per-point (every boundary exit)
    ├── game_won(winner: String)       ← when a side reaches 5 points
    └── match_over(winner: String)     ← when a side wins 2 games
```

## Rules

| Parameter | Value | Description |
|-----------|:-----:|-------------|
| Points to win a game | 5 | `POINTS_TO_WIN_GAME` |
| Games to win a match | 2 | `GAMES_TO_WIN_MATCH` |
| Post-score pause | 1.0 s | `await get_tree().create_timer(1.0).timeout` |
| Score direction — player | side=0 | Ball exits right boundary |
| Score direction — AI | side=1 | Ball exits left boundary |

## Signals

```gdscript
signal scored(winner: String)       # "player" | "ai" — every point
signal game_won(winner: String)     # "player" | "ai" — game concludes (5 pts)
signal match_over(winner: String)   # "player" | "ai" — match concludes (2 games)
```

## State Variables

| Variable | Type | Default | Description |
|----------|------|:-------:|-------------|
| `player_score` | int | 0 | Points in current game (0–5) |
| `ai_score` | int | 0 | Points in current game (0–5) |
| `player_games` | int | 0 | Games won (0–2) |
| `ai_games` | int | 0 | Games won (0–2) |
| `_is_match_over` | bool | false | Guard: suppresses further scoring after match concludes |

## Key Behaviors

### Score Flow

1. `_on_ball_score(side)` determines winner from side enum (0=player, 1=AI)
2. Increments the appropriate score counter
3. Emits `scored(winner)` for UI/visual updates
4. If score reaches `POINTS_TO_WIN_GAME`: calls `_win_game(winner)`
5. Otherwise: calls `_pause_and_serve()` to resume play after 1s

### Game Win

1. Emits `game_won(winner)`
2. Increments game counter
3. Resets per-game scores to 0
4. If games reach `GAMES_TO_WIN_MATCH`: sets `_is_match_over = true`, emits `match_over(winner)`
5. Otherwise: calls `_pause_and_serve()`

### Post-Match Guard

The `_is_match_over` flag prevents any further `ball.score` signals from
corrupting state after the match concludes. All score events are silently
dropped.

### Headless Compatibility

`_pause_and_serve()` checks `get_tree()` for null before calling `create_timer()`.
In headless mode (parentless node), the timer is skipped and `ball.serve()` is
called immediately — no crash, no hang.

### Score Flash Integration

The scoring manager attempts to connect its `scored` signal to `ScoreFlash`'s
`_on_score_changed` method via `get_node_or_null`. If `ScoreFlash` is absent,
the scoring system operates normally — the connection is best-effort.

## Test Coverage

| Area | Tests | Description |
|------|:-----:|-------------|
| Player scoring | TC1 | side=0 → player_score += 1, scored("player") |
| AI scoring | TC2 | side=1 → ai_score += 1, scored("ai") |
| Game win (5 pts) | TC3, TC6 | 5 points → game_won, scores reset, games += 1 |
| Match win (2 games) | TC4 | 2 games → match_over, _is_match_over = true |
| Alternating scores | TC5 | Interleaved player/AI scoring integrity |
| Post-match guard | TC9, TC10 | Scores ignored after match_over |
| Headless safety | TC11 | No tree → serve called immediately |
| Missing ball | TC13 | Null ball → push_error, no crash |
| Signal integrity | SIG-S1–S3 | scored, game_won, match_over carry correct winner |
| Initial state | STATE | All counters zero, _is_match_over = false |

**Test file:** `mini-pong/tests/test_scoring_manager.gd` (42 tests, all passing)

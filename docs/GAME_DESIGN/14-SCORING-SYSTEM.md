# Scoring System

> Reference: ../DESIGN/291-scoring-system.md + ../DESIGN/385-dual-scoring-system.md
> Parent Issues: #291, #385

## Overview

The Scoring System translates low-level gameplay events into run-level score
state. Since #385 (dual scoring), it follows a **two-layer design**:

1. **ScoringManager (scene side, event routing)** — consumes `ball.score(side)`
   and `BreakoutGrid.brick_destroyed(brick, pos)` signals, decides ownership,
   amount, and kind, then forwards to the GameManager. No score state lives here.
2. **GameManager (global state holder)** — the single authority for totals,
   run-end detection, and the query API. The 21-point run replaced the old
   5-point-game / 2-game-match layering.

The system runs independently of any autoload and works in both headless
(test) and runtime (playable) modes with graceful degradation when optional
dependencies (BreakoutGrid, ScoreFlash) are absent.

## Node Tree

```
ScoringManager (Node, scoring_manager.gd)   — scene-side event router
GameManager    (autoload, game_manager.gd)  — run state holder + query API
```

The `ScoringManager` is a sibling of `Ball` and `PlayerPaddle` in `Main.tscn`.
It references the ball via `$"../Ball"`, connects to `ScoreFlash` via
`get_node_or_null("../ScoreFlash")`, and to the BreakoutGrid via
`get_node_or_null("../BreakoutGrid")` — the grid connection is **best-effort**
(#384/#393 not wired yet → brick scoring degrades gracefully with a warning).

## Signal Chain

```
Ball._process() → ball.score(side)                       (boundary exit)
    │
    ▼
ScoringManager._on_ball_score(side)
    │  ball._crossed_wall?  → add_score(winner, 3, "pierce")   (穿墙分 AC2)
    │  else                 → add_score(winner, 1, "boundary") (普通出界兜底)
    └── scored(winner)      ← only boundary/pierce points → FSM SCORED pause flow

BreakoutGrid.brick_destroyed(brick, pos)                   (#384, best-effort)
    │
    ▼
ScoringManager._on_brick_destroyed(brick, pos)
    └── ball.last_toucher 非空 → add_score(toucher, 1, "brick")  (拆砖分 AC1)

GameManager.add_score(winner, amount, kind)
    ├── score_changed(player_score, ai_score)   ← total updated
    └── match_over(winner)                      ← first to 21 (AC3)
```

**Same-frame dedup (AC4):** `_brick_destroyed_this_frame` is reset at the start
of every `_process` frame and set when a brick is destroyed. If a boundary exit
arrives in the same frame, only the brick point counts (the boundary event is
consumed and the guard reset, so later frames score normally).

## Rules

| Parameter | Value | Description |
|-----------|:-----:|-------------|
| Brick score | 1 | `GameConstants.BRICK_SCORE` — last toucher +1 (AC1) |
| Pierce score | 3 | `GameConstants.PIERCE_SCORE` — crossed wall band, exited uncaught (AC2) |
| Run end | 21 | `GameConstants.WIN_SCORE` — first side to 21 total wins (AC3) |
| Wall band half-height | 22.0 | `GameConstants.WALL_BAND_HALF_HEIGHT` = BRICK_SIZE.y/2 + BALL_RADIUS; edge-triggered crossing detect |
| Grid wall Y | 640.0 | `GameConstants.GRID_WALL_Y` — brick wall centerline (shared with #384/#414) |
| Post-score pause | 1.0 s | FSM SCORED state, boundary/pierce points only |
| Score direction — player | side=0 | Ball exits top boundary |
| Score direction — AI | side=1 | Ball exits bottom boundary |

> **Superseded (#385):** `POINTS_TO_WIN_GAME=5` / `GAMES_TO_WIN_MATCH=2` are
> retained as declarations but marked deprecated — the 21-point run has no
> game/match layering, and nothing references them.

## Signals

```gdscript
# GameManager (autoload)
signal score_changed(player_score: int, ai_score: int)  # every add_score
signal match_over(winner: String)                       # "player" | "ai" — 21 分终局

# ScoringManager (scene)
signal scored(winner: String)   # boundary/pierce points only → FSM SCORED pause flow
```

## State Variables

| Variable | Type | Default | Description |
|----------|------|:-------:|-------------|
| `player_score` / `ai_score` | int | 0 | Run totals (0–21) |
| `player_brick_count` / `ai_brick_count` | int | 0 | Brick points per side (AC5) |
| `player_pierce_count` / `ai_pierce_count` | int | 0 | Pierce points per side (AC5) |
| `_is_run_over` | bool | false | Guard: suppresses further scoring after run ends |

## Key Behaviors

### Score Flow (boundary)

1. `_on_ball_score(side)` — early-return if `GameManager.is_run_over()` (post-match guard)
2. Same-frame dedup check (AC4): brick destroyed this frame → consume, skip
3. Winner from side (0=player top, 1=AI bottom); pierce if `ball._crossed_wall`
4. `GameManager.add_score(winner, amount, kind)` → `score_changed` + run-end check
5. `scored.emit(winner)` → FSM SCORED → pause-and-serve (1s)

### Brick Score (AC1)

`_on_brick_destroyed(brick, pos)` → if `ball.last_toucher` is non-empty,
`add_score(toucher, 1, "brick")`. Brick points **do not** trigger the SCORED
pause — play continues. `last_toucher` is tracked on the ball by paddle node
name (`PlayerPaddle`/`AIPaddle`), set on body-exited, reset on serve/paddle hit.

### Run End (AC3)

`_check_run_end()` — first side to 21 wins; `match_over(winner)` emitted.
A single scoring event only ever awards one side, so same-frame double-21 is
impossible. `_is_run_over` then suppresses all further events.

### Query API (AC5)

`get_brick_count(side)` / `get_pierce_count(side)` — used by the game-over /
results screens to show the scoring breakdown; `reset_match()` restarts state.

### Headless Compatibility

`_pause_and_serve()` checks `get_tree()` for null before `create_timer()` —
in headless mode the timer is skipped and `ball.serve()` runs immediately.

### Graceful Degradation

- BreakoutGrid absent / signal unwired → warning once, brick scoring disabled
- ScoreFlash absent → `scored` connection skipped, scoring unaffected
- Ball node missing → `push_error`, scoring disabled

## Test Coverage

| Area | Tests | Description |
|------|:-----:|-------------|
| Brick scoring | test_dual_scoring A/B/C | last_toucher +1, no-toucher no-score, dedup |
| Pierce scoring | test_dual_scoring D/E/F | crossed-wall 3pt, touch-reset, edge-trigger |
| Run end | test_dual_scoring G/H | first-to-21 match_over, post-run guard |
| Query API | AC5 cases | get_brick_count / get_pierce_count |
| Boundary fallback | scoring tests | no-wall 1pt boundary scoring intact |
| FSM integration | test_integration_fsm | SCORED pause flow, GAME_OVER entry |
| Legacy | TC1–TC13 (adapted) | signal integrity, headless safety, missing ball |

**Test files:** `mini-pong/tests/test_dual_scoring.gd` (72 cases, A–H scenes) +
`test_scoring_manager.gd`, `test_game_manager.gd` (adapted to dual scoring).

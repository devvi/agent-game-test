# Design: 计分系统 — Scoring System

> **Parent Issue:** #291
> **Agent:** game-plan-agent
> **Date:** 2026-07-29
> **Approach:** A — ScoringManager Node + signal connection (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                    ← unchanged (no autoload needed)
├── scenes/
│   ├── ball.tscn                    ← unchanged
│   ├── player_paddle.tscn           ← unchanged
│   ├── world_environment.tscn       ← unchanged
│   └── game.tscn                    ← MODIFIED: add ScoringManager Node
├── gdscripts/
│   ├── ball.gd                      ← unchanged (score signal already emits)
│   ├── paddle.gd                    ← unchanged
│   ├── ball_trail.gd                ← unchanged
│   ├── score_flash.gd               ← unchanged (callback already defined)
│   ├── neon_glow.gdshader           ← unchanged
│   └── scoring_manager.gd           ← NEW: score/game/match logic + signals
└── tests/
    ├── run_tests.gd                 ← unchanged
    ├── test_ball.gd                 ← unchanged
    ├── test_paddle.gd               ← unchanged
    └── test_neon.gd                 ← unchanged
```

**Design philosophy:** ScoringManager is a self-contained Node that consumes the `ball.score(side)` signal from #287's physics layer. It translates low-level side-enumeration (0=left/player, 1=right/AI) into high-level scoring events (`scored`, `game_won`, `match_over`) with human-readable String winner identifiers. The scoring logic is entirely event-driven — no polling, no `_process` — and operates without autoload dependencies.

**Signal chain:**
```
Ball._process() → ball.score(side: int)
    │
    ▼
ScoringManager._on_ball_score(side)
    │
    ├── scored(winner: String)         ← UI update + score_flash trigger
    │
    ├── Check 5-point game win → game_won(winner: String)
    │   └── Check 2-game match win → match_over(winner: String)
    │
    └── await 1.0s pause → ball.serve()
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | Scene Node (not autoload) | Scoring is scene-level, not global — autoload reserved for #293 GameManager |
| Signal parameter type | `String` (`"player"` / `"ai"`) | Matches `score_flash.gd`'s existing `_on_score_changed(scoring_side: String)` callback |
| Ball reference | `@onready var ball = $"../Ball"` | Simple scene-tree relative path; ScoringManager is sibling of Ball |
| Pause mechanism | `await get_tree().create_timer(1.0).timeout` | Consistent with `ball.gd`'s `serve()` delay pattern; headless-safe via null check |
| Game/match thresholds | Hardcoded constants `POINTS_TO_WIN_GAME=5`, `GAMES_TO_WIN_MATCH=2` | Issue spec; can export later for balance tuning |
| Post-match guard | `_is_match_over: bool` flag | Prevents ball.score signals after match conclusion from corrupting state |
| Score flash connection | `scored.connect(score_flash._on_score_changed)` | score_flash callback already implemented (#289), only needs signal wiring |

---

## 2. New Components — Detailed Design

### 2.1 `scoring_manager.gd`

- **File:** `mini-pong/gdscripts/scoring_manager.gd`
- **Attached to:** `Node` root of `ScoringManager` node in `game.tscn`
- **Line estimate:** ~95 lines

#### Signals

```gdscript
signal scored(winner: String)       # "player" | "ai" — emitted every point
signal game_won(winner: String)     # "player" | "ai" — emitted when a game concludes (5 points)
signal match_over(winner: String)   # "player" | "ai" — emitted when the match concludes (2 games)
```

#### Constants

```gdscript
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2
```

#### State Variables

```gdscript
var player_score: int = 0          # Points in current game (0–5)
var ai_score: int = 0              # Points in current game (0–5)
var player_games: int = 0          # Games won (0–2)
var ai_games: int = 0              # Games won (0–2)
var _is_match_over: bool = false   # Guard: ignore further scores after match concludes
```

#### Node References

```gdscript
@onready var ball: Area2D = $"../Ball"
@onready var score_flash: Node = $"../ScoreFlash"
```

#### Key Methods

**`_ready()` — Connect signals:**
```
1. Assert ball != null (push_error if missing)
2. ball.score.connect(_on_ball_score)
3. If score_flash exists: scored.connect(score_flash._on_score_changed)
```

**`_on_ball_score(side: int) — Core scoring logic:**
```
1. If _is_match_over: return (ignore post-match scores)

2. Determine winner:
   a. side == 1 → winner = "ai"
   b. side == 0 → winner = "player"

3. Increment score:
   a. winner == "player" → player_score += 1
   b. winner == "ai"     → ai_score += 1

4. Emit scored(winner)

5. Check game win:
   a. If player_score >= POINTS_TO_WIN_GAME: call _win_game("player")
   b. Else if ai_score >= POINTS_TO_WIN_GAME: call _win_game("ai")
   c. Else: call _pause_and_serve()
```

**`_win_game(winner: String) — Game-level win logic:**
```
1. Emit game_won(winner)

2. Increment game counter:
   a. winner == "player" → player_games += 1
   b. winner == "ai"     → ai_games += 1

3. Reset per-game scores to 0: player_score = 0; ai_score = 0

4. Check match win:
   a. If player_games >= GAMES_TO_WIN_MATCH:
        _is_match_over = true
        emit match_over("player")
        return
   b. Else if ai_games >= GAMES_TO_WIN_MATCH:
        _is_match_over = true
        emit match_over("ai")
        return

5. If match not over: call _pause_and_serve()
```

**`_pause_and_serve() — 1-second pause then serve:**
```
1. var tree := get_tree()
2. If tree != null: await tree.create_timer(1.0).timeout
   (Headless: get_tree() returns null, skip timer — serve immediately)
3. ball.serve()
```

#### Full API Surface

| Element | Kind | Signature | Notes |
|---------|------|-----------|-------|
| `scored` | signal | `scored(winner: String)` | "player" or "ai" |
| `game_won` | signal | `game_won(winner: String)` | "player" or "ai" |
| `match_over` | signal | `match_over(winner: String)` | "player" or "ai" |
| `player_score` | var (int) | `= 0` | Current game score, publicly readable |
| `ai_score` | var (int) | `= 0` | Current game score, publicly readable |
| `player_games` | var (int) | `= 0` | Games won, publicly readable |
| `ai_games` | var (int) | `= 0` | Games won, publicly readable |
| `_on_ball_score` | func | `(side: int) -> void` | Signal handler, connected to ball.score |
| `_win_game` | func | `(winner: String) -> void` | Internal game-win handler |
| `_pause_and_serve` | func | `() -> void` | Internal pause + serve logic |

### 2.2 `game.tscn` Modification

- **File:** `mini-pong/scenes/game.tscn`
- **Change:** Add `ScoringManager` Node after existing nodes
- **Estimated delta:** +6 lines

#### Node Tree (after change)

```
Game (Node2D)
├── TopWall (StaticBody2D)
├── BottomWall (StaticBody2D)
├── Ball (Area2D, instance=ExtResource("1_ball"))
├── PlayerPaddle (Area2D, instance=ExtResource("2_player_paddle"))
└── ScoringManager (Node)                    ← NEW
```

#### TSCN Fragment

```ini
[ext_resource type="Script" path="res://gdscripts/scoring_manager.gd" id="3_scoring_manager"]

[node name="ScoringManager" type="Node" parent="."]
script = ExtResource("3_scoring_manager")
```

Note: The `ext_resource` ID must be the next available integer. In the current `game.tscn`, IDs 1 and 2 are already used (`1_ball`, `2_player_paddle`), so `3_scoring_manager` is correct.

---

## 3. Component Interaction After Changes

```
┌─────────────────┐     score(side: int)     ┌─────────────────────┐
│   ball.gd       │ ────────────────────────►│  scoring_manager.gd │
│   (unchanged)   │                           │  (NEW)              │
└─────────────────┘                           └──────┬──────────────┘
                                                     │
                              ┌──────────────────────┼──────────────────────┐
                              │                      │                      │
                              ▼                      ▼                      ▼
                     scored("player")       game_won("player")     match_over("player")
                     scored("ai")           game_won("ai")         match_over("ai")
                              │                      │                      │
                              ▼                      ▼                      ▼
                     ┌──────────────┐     ┌──────────────────┐    ┌──────────────────┐
                     │ score_flash  │     │  Future UI (#292) │    │ Future GameMgr   │
                     │ (existing)   │     │  HUD / End Screen │    │ autoload (#293)   │
                     └──────────────┘     └──────────────────┘    └──────────────────┘
```

**Flow:**

1. `ball._process()` detects X-boundary exit → emits `score(0)` or `score(1)` then calls `serve()` (internal reset)
2. `ScoringManager._on_ball_score(side)` fires → increments score → emits `scored(winner)`
3. `scored` signal triggers `score_flash._on_score_changed(scoring_side)` — existing #289 callback
4. If game threshold reached (5 points): `_win_game()` emits `game_won(winner)`, checks match threshold
5. If match threshold reached (2 games): emits `match_over(winner)`, sets `_is_match_over = true`
6. After score processing: waits 1 second, then calls `ball.serve()` to restart play

**Ball.serve() internal flow (existing #287):**
- Resets position to center, speed to `initial_speed`
- Sets `_is_serving = true` (freezes `_process`)
- After 0.5s delay: sets random velocity, `_is_serving = false`
- Total delay from score to ball moving: 1.0s (ScoringManager) + 0.5s (ball.serve) = ~1.5s

---

## 4. State Transition Diagram

```
                  ┌─────────┐
                  │  IDLE   │  (ball in play)
                  └────┬────┘
                       │ ball.score(side)
                       ▼
              ┌────────────────┐
              │ SCORE RECEIVED │
              │ scored(winner) │
              └───────┬────────┘
                      │
            ┌─────────┼─────────┐
            │         │         │
         [<5 pts]   [5 pts]  [match_over]
            │         │         │
            ▼         ▼         ▼
     ┌──────────┐ ┌──────────┐ ┌─────────────┐
     │ PAUSE 1s │ │GAME_WON  │ │ MATCH_OVER  │
     │ → serve  │ │scores→0  │ │ no-op       │
     │ → IDLE   │ │games +=1 │ │ (final)     │
     └──────────┘ └────┬─────┘ └─────────────┘
                       │
                ┌──────┼──────┐
                │             │
           [<2 games]    [2 games]
                │             │
                ▼             ▼
         ┌──────────┐  ┌─────────────┐
         │ PAUSE 1s │  │ MATCH_OVER  │
         │ → serve  │  │ (final)     │
         │ → IDLE   │  └─────────────┘
         └──────────┘
```

---

## 5. Test Case Descriptions

### Test Approach

Since this is a `depth/light` issue, test descriptions are embedded in the DESIGN doc rather than creating runnable test files. The implement agent may choose to create `mini-pong/tests/test_scoring.gd` following the existing test pattern (`extends RefCounted` + `run()` + `_assert()`), or may verify via headless compilation + manual signal inspection.

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|:-----------:|:----------:|:-------------:|
| Score tracking | TC1, TC2 | TC5 | TC9 |
| Game win (5 pts) | TC3 | TC6 | — |
| Match win (2 games) | TC4 | TC7 | TC10 |
| Pause + serve | TC8 | TC11 | — |
| Signal integrity | TC1–TC4 | TC12 | TC13 |

### Test Cases

#### TC1 — Player scores (right boundary)

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | Instantiate ScoringManager, connect to a mock ball with `score` signal |
| **Steps** | 1. Emit `ball.score.emit(0)` (right boundary → player) |
| **Expected** | `player_score == 1`, `ai_score == 0`. Signal `scored("player")` emitted. |

#### TC2 — AI scores (left boundary)

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | Same as TC1, fresh state |
| **Steps** | 1. Emit `ball.score.emit(1)` (left boundary → AI) |
| **Expected** | `ai_score == 1`, `player_score == 0`. Signal `scored("ai")` emitted. |

#### TC3 — Game won at 5 points

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | Fresh ScoringManager. Pre-set `player_score = 4` |
| **Steps** | 1. Emit `ball.score.emit(0)` → player_score = 5 |
| **Expected** | `game_won("player")` emitted. `player_score == 0`, `ai_score == 0` (reset). `player_games == 1`, `ai_games == 0`. |

#### TC4 — Match won at 2 games

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | Fresh ScoringManager. Pre-set `player_games = 1`, `player_score = 4` |
| **Steps** | 1. Emit `ball.score.emit(0)` → player_score = 5 → game_won → player_games = 2 |
| **Expected** | `match_over("player")` emitted. `_is_match_over == true`. |

#### TC5 — Alternating scores

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | Fresh ScoringManager |
| **Steps** | 1. Emit `ball.score.emit(0)` (player=1) 2. Emit `ball.score.emit(1)` (ai=1) 3. Emit `ball.score.emit(0)` (player=2) 4. Emit `ball.score.emit(1)` (ai=2) |
| **Expected** | `player_score == 2`, `ai_score == 2`. Four `scored` emissions: "player", "ai", "player", "ai". |

#### TC6 — Game won by AI side

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | Fresh ScoringManager. Pre-set `ai_score = 4` |
| **Steps** | 1. Emit `ball.score.emit(1)` → ai_score = 5 |
| **Expected** | `game_won("ai")` emitted. Scores reset to 0. `ai_games == 1`. |

#### TC7 — Player wins 2 games, AI wins none

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | Fresh ScoringManager. Pre-set `player_games = 1`, `player_score = 4` |
| **Steps** | 1. Emit `ball.score.emit(0)` → game_won("player") → player_games = 2 |
| **Expected** | `match_over("player")` emitted. `_is_match_over == true`. |

#### TC8 — Pause timer invoked after score

| Field | Detail |
|-------|--------|
| **Type** | Normal Path |
| **Setup** | ScoringManager instantiated in scene tree (has valid `get_tree()`) |
| **Steps** | 1. Emit `ball.score.emit(0)` → player_score = 1 → `_pause_and_serve()` called |
| **Expected** | `ball.serve()` is called. Verify that `ball.position` resets to center. (Timer behavior verified by functional test; exact 1.0s timing is an integration concern.) |

#### TC9 — Score after match_over is ignored

| Field | Detail |
|-------|--------|
| **Type** | Edge Case |
| **Setup** | ScoringManager with `_is_match_over = true`, `player_score = 1` |
| **Steps** | 1. Emit `ball.score.emit(0)` |
| **Expected** | `player_score` remains 1 (no increment). No `scored` signal emitted. |

#### TC10 — Double game_won edge case (unreachable, defensive)

| Field | Detail |
|-------|--------|
| **Type** | Edge Case |
| **Setup** | ScoringManager with `player_games = 2`, `_is_match_over = true` |
| **Steps** | 1. Emit 5 consecutive `ball.score.emit(0)` signals in rapid succession |
| **Expected** | First signal after match_over: guard suppresses. `player_score` unchanged. |

#### TC11 — Headless: no tree, serve called immediately

| Field | Detail |
|-------|--------|
| **Type** | Edge Case |
| **Setup** | ScoringManager with `get_tree()` returning null (simulated headless) |
| **Steps** | 1. Emit `ball.score.emit(0)` |
| **Expected** | `_pause_and_serve()` detects null tree, skips `await`, calls `ball.serve()` immediately. No crash, no hang. |

#### TC12 — score_flash.gd receives scored signal

| Field | Detail |
|-------|--------|
| **Type** | Integration |
| **Setup** | game.tscn instance with ScoringManager and ScoreFlash nodes |
| **Steps** | 1. Emit `ball.score.emit(0)` |
| **Expected** | `score_flash._on_score_changed("player")` fires → flash with Color(0.29, 0.56, 0.85, 0.3) appears. |

#### TC13 — Ball node missing (failure path)

| Field | Detail |
|-------|--------|
| **Type** | Failure Path |
| **Setup** | ScoringManager without a sibling "Ball" node |
| **Steps** | 1. Call `_ready()` |
| **Expected** | `push_error` emitted. `ball == null`. No crash — `connect()` is not called on null. |

---

## 6. Files Changed

| File | Type | Change | Est. Lines |
|------|:----:|--------|:----------:|
| `mini-pong/gdscripts/scoring_manager.gd` | New | Full scoring manager implementation | +95 |
| `mini-pong/scenes/game.tscn` | Modify | Add ScoringManager Node + ext_resource reference | +6 |

**Total:** 2 files, ~101 lines delta.

---

## 7. Verification Checklist

### Acceptance Criteria

- [ ] **AC1: 球出左边界 → AI 得分** — Ball exits left boundary → `ball.score(1)` → `ai_score += 1` → `scored("ai")` emitted
- [ ] **AC2: 球出右边界 → 玩家得分** — Ball exits right boundary → `ball.score(0)` → `player_score += 1` → `scored("player")` emitted
- [ ] **AC3: 5 分一局，先赢 2 局者胜** — Party reaches 5 points → `game_won(winner)` emitted + scores reset + games counter incremented. Party reaches 2 games → `match_over(winner)` emitted
- [ ] **AC4: 得分后暂停 1 秒再发球** — `_pause_and_serve()` waits 1s → `ball.serve()` called (ball adds 0.5s serve delay, total ~1.5s)
- [ ] **AC5: scored(winner) 和 match_over(winner) 信号** — `scored` fires immediately on each point, `match_over` fires on match conclusion; both use `"player"` | `"ai"` String params
- [ ] **AC6: --headless --quit 无脚本错误** — `godot --path mini-pong/ --headless --quit` exits code 0, no SCRIPT ERROR

### Additional Verification

- [ ] `score_flash._on_score_changed` fires on every score (neon visual feedback chain complete)
- [ ] Post-match `ball.score` signals are ignored (`_is_match_over` guard)
- [ ] Headless compatibility: no crash when `get_tree()` returns null in `_pause_and_serve()`
- [ ] `game.tscn` ext_resource IDs are sequential (3_scoring_manager follows 1_ball, 2_player_paddle)

---

## 8. Correction to PRD

**PRD claim:** `game_won(winner)` signal should be the game-win intermediate signal between `scored` and `match_over`.

**Correction:** This is already present in both the PRD's code examples and this DESIGN. No correction needed — the three-signal hierarchy (`scored` → `game_won` → `match_over`) is correctly specified.

**PRD claim:** `score_flash.gd` node is referenced as `$"../ScoreFlash"`.

**Actual state:** The current `game.tscn` does not yet include a `ScoreFlash` node. Per DESIGN §2.1, the `@onready var score_flash` reference should use optional access: `$"../ScoreFlash"` (returns null if not present, graceful degradation). The implement agent should note that `score_flash` wiring is best-effort — the scoring system functions correctly without it.

---

## 9. Design Decisions Record

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Post-match guard | `_is_match_over: bool` flag in `_on_ball_score()` | Simplest guard; no need for signal disconnection logic |
| Game thresholds | Hardcoded constants, not `@export` | Issue explicitly specifies 5/2; export can be added later for balance |
| Ball reference path | `$"../Ball"` (sibling) | ScoringManager added after Ball in TSCN order → `_ready()` runs after Ball is ready |
| Score reset timing | Reset in `_win_game()` (before match check) | Clean state for next game regardless of match outcome |
| No explicit edge-case for "both at 5" | Player check before AI check | Pong is sequential — only one side scores per boundary event |
| Async pause | `await` in `_pause_and_serve()` | Co-routine pattern matches `ball.gd`'s `serve()` — natural Godot async |

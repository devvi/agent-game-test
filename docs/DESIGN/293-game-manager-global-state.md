# Design: GameManager 全局状态 — Global State Singleton

> **Parent Issue:** #293
> **Agent:** game-plan-agent
> **Date:** 2026-07-29
> **Approach:** A — Independent autoload GameManager (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                         ← MODIFIED: add [autoload] section
├── gdscripts/
│   ├── game_manager.gd                   ← NEW: autoload singleton
│   ├── scoring_manager.gd                ← unchanged (bridge in #295)
│   ├── ball.gd, paddle.gd, ...           ← unchanged
├── scenes/
│   └── game.tscn                         ← unchanged
```

**Design philosophy:** GameManager is a pure-data autoload that sits **above** the existing ScoringManager. It does not duplicate scoring logic — it provides the global namespace, reset APIs, and a `get_winner()` query that the scene-bound ScoringManager cannot offer. ScoringManager remains unchanged; #295 will bridge `ScoringManager.scored → GameManager.add_score`.

**Relationship to ScoringManager:**

| Concern | ScoringManager (#291) | GameManager (#293) |
|---------|----------------------|-------------------|
| Lifecycle | Scene Node (dies with game.tscn) | Autoload singleton (survives scene changes) |
| Score increment logic | ✅ `_on_ball_score(side)` + threshold checks | ✅ `add_score(winner)` — simpler, no Ball dependency |
| Signals | `scored(winner)`, `game_won(winner)`, `match_over(winner)` | `score_changed(p, a)`, `game_won(winner)`, `match_over(winner)` |
| Reset API | ❌ No public reset methods | ✅ `reset_game()`, `reset_match()` |
| Winner query | ❌ Must inspect private vars | ✅ `get_winner() → String` |
| Global access | ❌ `get_node("../ScoringManager")` | ✅ `GameManager.player_score` |
| Headless compatible | ❌ `@onready var ball` fails in headless | ✅ No scene dependencies |

---

## 2. New Components — Detailed Design

### 2.1 `game_manager.gd`

- **File:** `mini-pong/gdscripts/game_manager.gd`
- **Type:** Autoload singleton (`extends Node`), registered as `GameManager` in `project.godot`
- **Line estimate:** ~65 lines

#### Configuration Constants

```gdscript
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2
```

Aligned with `scoring_manager.gd` L16–17. Both constants must stay in sync — future refactoring can extract to a shared `constants.gd`.

#### Signals

```gdscript
signal score_changed(player_score: int, ai_score: int)
signal game_won(winner: String)       # "player" | "ai"
signal match_over(winner: String)     # "player" | "ai"
```

`score_changed` is NEW (not in ScoringManager) — carries actual score values so consumers don't need to re-read state. `game_won` and `match_over` match ScoringManager's signal names for easy bridge wiring in #295.

#### State Variables

```gdscript
var player_score: int = 0
var ai_score: int = 0
var player_games_won: int = 0
var ai_games_won: int = 0
```

Publicly readable/writable (`var`, no setget). Semantic names (`*_games_won`) distinguish from ScoringManager's `player_games` / `ai_games`. Direct writes allowed for testing flexibility; production code should use `add_score()`.

#### Public API

| Method | Signature | Behavior |
|--------|-----------|----------|
| `add_score` | `func add_score(winner: String) -> void` | Increments `player_score` or `ai_score`; emits `score_changed`; calls `_check_game_win()` |
| `reset_game` | `func reset_game() -> void` | Sets `player_score = 0`, `ai_score = 0`; game counters untouched |
| `reset_match` | `func reset_match() -> void` | Sets all four state vars to 0; full reset |
| `get_winner` | `func get_winner() -> String` | Returns `"player"` / `"ai"` / `""` based on `*_games_won >= GAMES_TO_WIN_MATCH` |

#### Internal Methods

```gdscript
func _check_game_win() -> void:
    if player_score >= POINTS_TO_WIN_GAME:
        _win_game("player")
    elif ai_score >= POINTS_TO_WIN_GAME:
        _win_game("ai")

func _win_game(winner: String) -> void:
    game_won.emit(winner)
    match winner:
        "player": player_games_won += 1
        "ai":     ai_games_won += 1
    player_score = 0
    ai_score = 0
    if player_games_won >= GAMES_TO_WIN_MATCH or ai_games_won >= GAMES_TO_WIN_MATCH:
        match_over.emit(winner)
```

**Signal emission order per `add_score()`:**
1. `score_changed.emit(player_score, ai_score)` — first, so UI updates before game/match conclusion effects
2. `_check_game_win()` → if threshold reached: `game_won.emit(winner)` — second
3. If 2 games won: `match_over.emit(winner)` — third

#### Edge Cases Handled

| # | Edge Case | Behavior |
|---|-----------|----------|
| 1 | `add_score()` with invalid winner | `match` falls through silently — no score change, no signal. No `push_warning()` (avoids spam in headless CI). |
| 2 | `add_score()` after `match_over` | Score increments normally; `_check_game_win()` fires again → `game_won` + `match_over` re-emit. Caller's responsibility to guard. |
| 3 | `reset_game()` mid-round | Scores zeroed; game counters preserved. Valid for testing. |
| 4 | `reset_match()` any time | Full reset; no validation. Valid for "force restart" scenarios. |
| 5 | `get_winner()` when no winner | Returns `""` — consumers check `result != ""` |

---

## 3. Existing Component Modifications

| File | Change | Why |
|------|--------|-----|
| `mini-pong/project.godot` | Add `[autoload]` section | Register GameManager as global singleton |

### 3.1 `project.godot` — precise modification

**Before (end of file):**
```ini
rendering/environment/defaults/default_clear_color=Color(0.039, 0.039, 0.071, 1)
```

**After:**
```ini
rendering/environment/defaults/default_clear_color=Color(0.039, 0.039, 0.071, 1)

[autoload]

GameManager="*res://gdscripts/game_manager.gd"
```

Format: `Name="*res://path"`. `*` prefix = global singleton marker (Godot 4.x convention). Section header `[autoload]` on its own line, then one autoload entry per line.

### Affected Test Files

| File | Change |
|------|--------|
| None | No existing tests for `game_manager.gd` (it's a new file). Headless compile test (`godot --headless --quit`) is the primary CI validation. |

### Files NOT Modified

| File | Reason |
|------|--------|
| `mini-pong/gdscripts/scoring_manager.gd` | ScoringManager operates independently; bridge wiring deferred to #295 |
| `mini-pong/scenes/game.tscn` | ScoringManager Node stays; GameManager is autoload, not scene node |
| `mini-pong/gdscripts/ball.gd` | Unchanged — Ball still emits `score(side)` to ScoringManager |

---

## 4. Data Flow

### Flow 1: Normal score increment (post-#295 bridge)

```
Ball._process() → ball.score(side: int)
  → ScoringManager._on_ball_score(side)
    → [existing ScoringManager logic: scored/game_won/match_over]
    → GameManager.add_score(winner)           ← #295 bridge
      → player_score += 1
      → score_changed.emit(player_score, ai_score)
      → _check_game_win() → game_won.emit(winner) or match_over.emit(winner)
  → UI reads GameManager.player_score         ← #292 consumption
```

### Flow 2: Headless test (direct API usage)

```
# Test script directly manipulates GameManager:
GameManager.reset_match()
assert GameManager.player_score == 0
GameManager.add_score("player")
assert GameManager.player_score == 1
assert GameManager.get_winner() == ""
GameManager.add_score("player")  # x5 total → game won
GameManager.reset_game()
assert GameManager.player_score == 0
assert GameManager.player_games_won == 1
```

### Flow 3: Match reset (state machine)

```
StateMachine.on_game_over()
  → GameManager.get_winner()  → "player" or "ai"
  → on SPACE press:
      → GameManager.reset_match()
      → scene transition to playing state
```

---

## 5. Integration Points

| Integration | Component | How | When |
|-------------|-----------|-----|------|
| ScoringManager → GameManager | `scoring_manager.gd` | `scored.connect(GameManager._on_scored)` | #295 |
| UI HUD → GameManager | `hud.gd` (#292) | `GameManager.score_changed.connect(_update_display)` | #292 |
| StateMachine → GameManager | `state_machine.gd` (#294) | `GameManager.get_winner()`, `GameManager.reset_match()` | #294 |
| Tests → GameManager | `test_*.gd` | Direct variable access + API calls | Immediate (this PR) |

---

## 6. Test Case Descriptions

> Descriptions only — implement agent writes runnable tests.

### Scenario A: Autoload Registration

- **TC1:** `godot --path mini-pong/ --headless --quit` exits 0 — verifies autoload script parses and `[autoload]` config is valid
- **TC2:** Headless test script accesses `GameManager` — assert not null; assert `player_score == 0`, `ai_score == 0`, `player_games_won == 0`, `ai_games_won == 0`

### Scenario B: add_score() API

- **TC3:** `add_score("player")` → `player_score == 1`, `ai_score == 0`
- **TC4:** `add_score("ai")` → `ai_score == 1`
- **TC5:** `add_score("invalid")` → no change, no crash, no signal spam
- **TC6:** 5x `add_score("player")` → `player_games_won == 1`, `player_score == 0` (auto-reset after game win)
- **TC7:** `score_changed` signal emitted after each `add_score()` with correct (player_score, ai_score) values
- **TC8:** `game_won("player")` signal emitted after 5th consecutive player score
- **TC9:** `match_over("player")` signal emitted after 2 game wins

### Scenario C: reset_game() vs reset_match()

- **TC10:** After 3x `add_score("player")`, call `reset_game()` → `player_score == 0`, `ai_score == 0`, `player_games_won` unchanged
- **TC11:** After `game_won` + `match_over`, call `reset_match()` → all four vars == 0
- **TC12:** `reset_match()` on fresh state → all four vars == 0 (idempotent)

### Scenario D: get_winner()

- **TC13:** Fresh state → `get_winner() == ""`
- **TC14:** After 2 player game wins → `get_winner() == "player"`
- **TC15:** After 2 AI game wins → `get_winner() == "ai"`

---

## 7. Verification

```bash
# Compile verification
godot --path mini-pong/ --headless --quit
echo "Exit: $?"

# API smoke test (headless script)
cat > /tmp/test_gm.gd << 'SCRIPT'
extends Node
func _ready():
    assert(GameManager != null, "autoload not found")
    assert(GameManager.player_score == 0)
    GameManager.add_score("player")
    assert(GameManager.player_score == 1)
    GameManager.reset_match()
    assert(GameManager.player_score == 0)
    assert(GameManager.get_winner() == "")
    print("PASS: GameManager smoke test")
    get_tree().quit(0)
SCRIPT
godot --path mini-pong/ --headless --script /tmp/test_gm.gd
```

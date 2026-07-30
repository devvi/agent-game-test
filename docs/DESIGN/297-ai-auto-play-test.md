# Design: AI 自动对打测试 — AI Auto-Play Test (100 Rounds)

> **Parent Issue:** #297
> **Agent:** game-plan-agent
> **Date:** 2026-07-30
> **Approach:** C — Minimal Test Scene (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                         ← unchanged
├── gdscripts/
│   ├── ball.gd                           ← unchanged (consumer: score signal, serve(), _process)
│   ├── paddle.gd                         ← unchanged (consumer: Mode.AI, _ai_process(), _resolve_ball())
│   ├── scoring_manager.gd                ← unchanged (consumer: scored/game_won/match_over signals)
│   ├── game_manager.gd                   ← unchanged (consumer: reset_match(), get_winner(), match_over signal)
│   ├── constants.gd                      ← unchanged (consumer: POINTS_TO_WIN_GAME=5, GAMES_TO_WIN_MATCH=2)
│   └── game_state_machine.gd             ← unused by this test
├── scenes/
│   └── (none used — test builds its own scene)
└── tests/
    ├── run_tests.gd                      ← MODIFIED: +1 entry for auto_play_test
    └── auto_play_test.gd                 ← NEW: 100-round AI-vs-AI simulation (~350 lines)
```

**Design philosophy:** Build a minimal self-contained test scene that duplicates only the physics + scoring layer of mini-pong — no FSM, no UI, no CanvasLayer. This eliminates timer-based `await` delays entirely. The test manually assembles a `Node2D` containing two Wall `StaticBody2D` nodes, one `Ball` (loaded from `ball.tscn`), two AI-mode `Paddle` instances, and a `ScoringManager`, then drives 100 matches frame-by-frame using `await get_tree().process_frame`. Each match is a best-of-3-games, first-to-5-points contest between two AI paddles. The test is a pure consumer — **no existing files are modified**.

### Why Approach C (Minimal Test Scene)

| # | Reason | Detail |
|---|--------|--------|
| 1 | **Speed** | No FSM timer awaits — 100 matches complete in ~5s (Approach A/B would take 10–1000s) |
| 2 | **Zero code changes** | No modifications to `ball.gd`, `paddle.gd`, `scoring_manager.gd`, `game_manager.gd`, or `game_state_machine.gd` |
| 3 | **Targeted coverage** | Focuses on the integration layer at risk: AI+physics+scoring running for 100 consecutive matches |
| 4 | **Existing FSM coverage** | `game_state_machine.gd` already has 16 unit tests (#294); UI has dedicated tests (#292) |
| 5 | **Consistent pattern** | Follows the same `extends RefCounted` + mock assembly pattern as `test_ball.gd`, `test_scoring_manager.gd`, `test_ai_paddle.gd` |

### Key Architectural Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Test script type | `extends RefCounted` + `run()` method | Matches existing test suite pattern (`test_ai_paddle.gd`, `test_scoring_manager.gd`). Integrates with `run_tests.gd` via `_run()` wrapper. |
| 2 | Scene assembly | Manual `Node2D` + factory functions | No dependency on `Main.tscn` or `game.tscn`. Avoids FSM instantiation entirely. |
| 3 | Ball instantiation | `load("res://scenes/ball.tscn").instantiate()` | Reuses the real Ball scene (with `CollisionShape2D`), not a mock. Ball's `serve()`, `_process()`, and `score` signal all function normally. |
| 4 | Paddle instantiation | `Area2D` + `set_script(load("res://gdscripts/paddle.gd"))` | Uses the real paddle.gd script in `Mode.AI` (value 1). Matches pattern from `test_ai_paddle.gd`. |
| 5 | Wall construction | `StaticBody2D` + `CollisionShape2D` (RectangleShape2D) via `_make_wall()` | Duplicates TopWall/BottomWall geometry from Main.tscn. Added to `"walls"` group so ball.gd wall-bounce code triggers. |
| 6 | Scoring integration | Real `ScoringManager` script on a Node, with manually-set `ball` reference | ScoringManager's `_ready()` connects to `ball.score` signal and calls `GameManager.add_score()`. The full signal chain (ball.score → ScoringManager → GameManager.match_over) operates normally. |
| 7 | Frame loop | `await get_tree().process_frame` in a while loop | No timer awaits. Each frame: ball._process(delta) runs automatically; paddle._ai_process(delta) is called manually. |
| 8 | Match counting | `_match_count` outer loop (100) | Each iteration resets GameManager + ScoringManager + ball/paddle positions, then drives until `match_over` fires. |
| 9 | Safety limit | `MAX_FRAMES_PER_MATCH = 10000` (~167s @60fps) | Prevents infinite loop if ball gets stuck between paddles. |
| 10 | Error detection | No explicit `push_error` hook needed | Any SCRIPT ERROR in headless mode prints to stderr and propagates naturally. Test catches failures via assertion checks. |
| 11 | Integration with run_tests.gd | Add `_run("res://tests/auto_play_test.gd", "Auto-Play")` entry | Follows the exact existing pattern: `_run()` loads the script, calls `run()`, and aggregates `passed`/`failed`. |

---

## 2. New Component — Detailed Design

### 2.1 `auto_play_test.gd`

- **File:** `mini-pong/tests/auto_play_test.gd`
- **Type:** Test script (`extends RefCounted`)
- **Line estimate:** ~350 lines

#### Script Structure

```gdscript
extends RefCounted
## Auto-Play Test — 100-round AI-vs-AI simulation.
## Verifies: no crash, scores reach 5, best-of-3 logic, winner exists, restart works.
## Uses a minimal self-contained scene (no FSM, no UI) for speed (~5s for 100 matches).
##
## Run standalone:
##   godot --path mini-pong/ --headless --script tests/auto_play_test.gd
## Run via run_tests.gd:
##   (entry added to run_tests.gd _run_tests())

# ── Constants ──
const MATCH_COUNT: int = 100
const MAX_FRAMES_PER_MATCH: int = 10000
const SCREEN_WIDTH: float = 1280.0
const SCREEN_HEIGHT: float = 720.0
const PADDLE_SPEED: float = 400.0

# ── Internal ──
const _CONSTS = preload("res://gdscripts/constants.gd")
const POINTS_TO_WIN_GAME: int = _CONSTS.POINTS_TO_WIN_GAME    # 5
const GAMES_TO_WIN_MATCH: int = _CONSTS.GAMES_TO_WIN_MATCH    # 2

# ── Test state ──
var passed: int = 0
var failed: int = 0
var _crash_count: int = 0
var _timeout_count: int = 0
var _match_count: int = 0
var _total_frames: int = 0
var _match_details: Array = []   # Array[Dictionary] for detailed reporting


func run() -> void:
    print("\n=== Auto-Play Test: %d Matches (AI vs AI) ===" % MATCH_COUNT)
    # ... test body (see §3 Data Flow)
```

#### Factory Functions

```gdscript
## ── Scene Assembly (factory functions) ──

func _make_wall(y: float) -> StaticBody2D:
    """Create a full-width wall at given Y position (center)."""
    var wall := StaticBody2D.new()
    wall.name = "Wall"
    wall.add_to_group("walls")
    var cs := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(SCREEN_WIDTH, 5.0)
    cs.shape = rect
    wall.add_child(cs)
    wall.position = Vector2(SCREEN_WIDTH / 2.0, y)
    return wall


func _make_ball() -> Area2D:
    """Instantiate the real ball.tscn scene."""
    var ball_tscn := load("res://scenes/ball.tscn")
    var ball := ball_tscn.instantiate()
    ball.name = "Ball"
    ball.position = Vector2(SCREEN_WIDTH / 2.0, SCREEN_HEIGHT / 2.0)
    return ball


func _make_ai_paddle(x: float, y: float) -> Area2D:
    """Create a paddle in AI mode at given position."""
    var paddle := Area2D.new()
    paddle.set_script(load("res://gdscripts/paddle.gd"))
    paddle.name = "AIPaddle"
    paddle.mode = 1  # Mode.AI
    paddle.position = Vector2(x, y)
    # Add CollisionShape2D for ball collision
    var cs := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(_CONSTS.PADDLE_WIDTH, _CONSTS.PADDLE_HEIGHT)
    cs.shape = rect
    paddle.add_child(cs)
    return paddle


func _make_scoring_manager(ball: Area2D) -> Node:
    """Create ScoringManager and wire it to the ball."""
    var sm := Node.new()
    sm.set_script(load("res://gdscripts/scoring_manager.gd"))
    sm.name = "ScoringManager"
    # Manually set the ball reference (bypasses @onready)
    sm.ball = ball
    # Explicitly set screen dimensions for paddle boundary calculation
    # Note: ball.tscn _ready() connects ScoreZoneLeft/Right signals,
    # but in minimal scene those don't exist — ball falls back to X-boundary scoring
    return sm
```

#### Test Scene Assembly

```gdscript
func _build_test_scene() -> Node2D:
    """Assemble minimal test scene: walls + ball + 2 AI paddles + ScoringManager."""
    var root := Node2D.new()
    root.name = "AutoPlayTestScene"

    # Walls (top and bottom)
    root.add_child(_make_wall(5.0))        # top wall
    root.add_child(_make_wall(SCREEN_HEIGHT - 5.0))  # bottom wall

    # Ball
    var ball := _make_ball()
    root.add_child(ball)

    # AI Paddles (left = "player", right = "ai")
    var paddle_left := _make_ai_paddle(50.0, SCREEN_HEIGHT / 2.0)
    paddle_left.name = "PlayerPaddle"
    root.add_child(paddle_left)

    var paddle_right := _make_ai_paddle(SCREEN_WIDTH - 50.0, SCREEN_HEIGHT / 2.0)
    paddle_right.name = "AIPaddle"
    root.add_child(paddle_right)

    # ScoringManager (must be sibling of Ball for @onready resolution)
    var sm := _make_scoring_manager(ball)
    root.add_child(sm)

    # Wire paddle ball references (paddle._resolve_ball() looks for sibling "Ball")
    # By placing them as siblings of Ball, _resolve_ball() will find it automatically

    return root
```

#### Match Loop (Core Logic)

```gdscript
func _run_match(scene: Node2D, match_index: int) -> Dictionary:
    """Run a single best-of-3 match. Returns result dictionary."""
    var ball := scene.get_node("Ball") as Area2D
    var sm := scene.get_node("ScoringManager") as Node
    var paddle_left := scene.get_node("PlayerPaddle") as Area2D
    var paddle_right := scene.get_node("AIPaddle") as Area2D

    # Reset global state
    GameManager.reset_match()

    # Reset ScoringManager state (manually, since no FSM does this)
    sm.player_score = 0
    sm.ai_score = 0
    sm.player_games = 0
    sm.ai_games = 0
    sm._is_match_over = false

    # Reset paddle positions
    paddle_left.position = Vector2(50.0, SCREEN_HEIGHT / 2.0)
    paddle_right.position = Vector2(SCREEN_WIDTH - 50.0, SCREEN_HEIGHT / 2.0)

    # Reset paddle AI state
    paddle_left._ai_delay_timer = 0.0
    paddle_right._ai_delay_timer = 0.0

    # Connect match_over signal for synchronous detection
    var match_winner := ""
    var match_done := false

    func _on_match_over(winner: String) -> void:
        match_winner = winner
        match_done = true

    # Use CONNECT_ONE_SHOT to auto-disconnect after firing
    var conn_err := GameManager.match_over.connect(_on_match_over, CONNECT_ONE_SHOT)

    # Serve the ball
    ball.serve()

    # Frame loop: advance until match_over or timeout
    var frame_count := 0
    var tree := scene.get_tree()
    while not match_done and frame_count < MAX_FRAMES_PER_MATCH:
        await tree.process_frame
        frame_count += 1

        # Ball._process(delta) runs automatically (SceneTree drives it)
        # Paddles need manual _ai_process call (since no SceneTree _process on these nodes)
        # Actually, paddle._process() IS driven by SceneTree — verify this
        # If paddle._process() auto-runs, we don't need manual calls

    # Disconnect if not already (belt-and-suspenders)
    if GameManager.match_over.is_connected(_on_match_over):
        GameManager.match_over.disconnect(_on_match_over)

    return {
        "winner": match_winner,
        "frames": frame_count,
        "timeout": frame_count >= MAX_FRAMES_PER_MATCH,
        "player_score": sm.player_score,
        "ai_score": sm.ai_score,
        "player_games": sm.player_games,
        "ai_games": sm.ai_games,
    }
```

**Critical note on paddle `_process()` auto-execution:** When a `Node2D` with a script is added to the SceneTree via `add_child()`, its `_process(delta)` callback is called automatically each frame. Since paddles have `_process()` defined in `paddle.gd`, they will be driven by the SceneTree — no manual `paddle._ai_process(delta)` call is needed. **However**, verify this during implementation — if `_process()` doesn't fire (e.g., because the Node is an `Area2D`, not a `Node`), add explicit `paddle_left._process(get_process_delta_time())` calls in the frame loop.

#### Verification Logic

```gdscript
func _verify_match(result: Dictionary, match_index: int) -> bool:
    """Validate a single match result. Returns true if all checks pass."""
    var ok := true

    # VC1: No timeout
    if result["timeout"]:
        print("  Match %03d: TIMEOUT (%d frames, no winner)" % [match_index + 1, result["frames"]])
        _timeout_count += 1
        return false

    # VC2: Winner is valid
    if result["winner"] not in ["player", "ai"]:
        print("  Match %03d: INVALID WINNER '%s'" % [match_index + 1, result["winner"]])
        ok = false

    # VC3: At least one side won 2 games (best-of-3)
    var games := max(result["player_games"], result["ai_games"])
    if games < GAMES_TO_WIN_MATCH:
        print("  Match %03d: GAMES < %d (p_games=%d, a_games=%d)" % [
            match_index + 1, GAMES_TO_WIN_MATCH, result["player_games"], result["ai_games"]
        ])
        ok = false

    # VC4: Winner's games_won >= 2
    var winner_games := result["player_games"] if result["winner"] == "player" else result["ai_games"]
    if winner_games < GAMES_TO_WIN_MATCH:
        print("  Match %03d: winner '%s' has only %d games" % [
            match_index + 1, result["winner"], winner_games
        ])
        ok = false

    # VC5: GameManager.get_winner() is non-empty
    var gm_winner := GameManager.get_winner()
    if gm_winner == "":
        print("  Match %03d: GameManager.get_winner() is empty" % (match_index + 1))
        ok = false

    # VC6: GameManager reports correct winner
    if gm_winner != result["winner"]:
        print("  Match %03d: GM winner (%s) != signal winner (%s)" % [
            match_index + 1, gm_winner, result["winner"]
        ])
        ok = false

    if ok:
        _match_details.append(result)
        _total_frames += result["frames"]

    return ok
```

#### Output Format

```text
=== Auto-Play Test: 100 Matches (AI vs AI) ===

Match 001: AI wins — 2 games to 1 (scores: 5-3, 4-5, 5-2) [342 frames] ✅
Match 002: Player wins — 2 games to 0 (scores: 5-2, 5-1) [287 frames] ✅
...
Match 100: Player wins — 2 games to 1 (scores: 5-4, 3-5, 5-0) [401 frames] ✅

=== Results ===
✅ Passed: 100/100
❌ Failed: 0/100
   Crashes: 0
   Timeouts: 0
   Avg frames/match: 348.5
   Avg time/match (est): 5.8s @60fps

Total time: 4.2s (headless)
Exit code: 0
```

---

## 3. Data Flow

### 3.1 Complete Match Loop Data Flow

```
auto_play_test.gd::run()
  |
  ├── 1. _build_test_scene()
  │       → Creates Node2D root
  │       → Adds TopWall, BottomWall (StaticBody2D, "walls" group)
  │       → Instantiates ball.tscn → Ball (Area2D)
  │       → Creates PlayerPaddle (Area2D, mode=AI, x=50)
  │       → Creates AIPaddle (Area2D, mode=AI, x=1230)
  │       → Creates ScoringManager (Node, ball ref set)
  │       → Paddle._resolve_ball() finds Ball via sibling lookup
  │
  ├── 2. For each match (0..99):
  │     │
  │     ├── GameManager.reset_match()
  │     │     → player_score=0, ai_score=0, player_games_won=0, ai_games_won=0
  │     │
  │     ├── ScoringManager state reset (manual)
  │     │     → player_score=0, ai_score=0, player_games=0, ai_games=0, _is_match_over=false
  │     │
  │     ├── Paddle position reset + AI state reset
  │     │     → position = starting X/Y, _ai_delay_timer=0
  │     │
  │     ├── Connect GameManager.match_over → _on_match_over(winner)
  │     │
  │     ├── ball.serve()
  │     │     → Ball repositions to center, sets random velocity
  │     │
  │     ├── Frame loop (await process_frame each iteration):
  │     │     │
  │     │     ├── Ball._process(delta)    ← auto-driven by SceneTree
  │     │     │     → position += velocity * delta
  │     │     │     → Wall collision (body_entered → velocity.y *= -1)
  │     │     │     → Paddle collision (area_entered → bounce angle + speed escalation)
  │     │     │     → X boundary exit → score.emit(side)
  │     │     │
  │     │     ├── PlayerPaddle._process(delta)  ← auto-driven by SceneTree
  │     │     │     → mode==AI → _ai_process(delta)
  │     │     │       → Decrement _ai_delay_timer
  │     │     │       → On expiry: update _ai_target_y = ball.y + random error
  │     │     │       → Move toward target with speed adjustment
  │     │     │
  │     │     ├── AIPaddle._process(delta)  ← auto-driven by SceneTree
  │     │     │     → Same AI logic
  │     │     │
  │     │     └── ScoringManager._on_ball_score(side)  ← signal from ball.score
  │     │           → Increment player_score or ai_score
  │     │           → GameManager.add_score(winner)
  │     │           → scored.emit(winner)
  │     │           → If score >= 5: _win_game() → game_won.emit()
  │     │           → If games >= 2: _is_match_over=true → match_over.emit(winner)
  │     │
  │     ├── match_over fires → _on_match_over sets match_done=true
  │     │
  │     └── _verify_match(result) → validation checks
  │
  ├── 3. Print summary report
  │
  └── 4. Return passed/failed counts to run_tests.gd
```

### 3.2 Signal Chain (reused from existing code)

```
Ball._process()
  → X boundary exit detected
  → score.emit(side)                          # side: 0=right(player), 1=left(ai)
    → ScoringManager._on_ball_score(side)
      → GameManager.add_score(winner)          # increments player_score or ai_score
      → scored.emit(winner)                    # per-point signal (unused by test)
      → if score >= 5: _win_game(winner)
        → game_won.emit(winner)                # per-game signal (unused by test)
        → player_games++ or ai_games++
        → if games >= 2:
          → _is_match_over = true
          → match_over.emit(winner)            # ← test listens for this

GameManager.match_over.emit(winner)            # ← also emitted from _win_game()
  → auto_play_test.gd::_on_match_over(winner)  # ← test captures match end
```

### 3.3 GameManager Autoload Interaction

```
GameManager (autoload singleton)
  │
  ├── test calls GameManager.reset_match() before each match
  │     → zeroes all 4 counters (player_score, ai_score, player_games_won, ai_games_won)
  │
  ├── ScoringManager calls GameManager.add_score() on each point
  │     → increments score, emits score_changed, checks game/match win
  │
  ├── GameManager emits match_over(winner) when match concludes
  │     → test listens via CONNECT_ONE_SHOT per match
  │
  └── test calls GameManager.get_winner() for post-match verification
```

---

## 4. Constants and Parameters

| Constant | Value | Source | Purpose |
|----------|-------|--------|---------|
| `MATCH_COUNT` | 100 | PRD requirement | Number of matches to simulate |
| `MAX_FRAMES_PER_MATCH` | 10000 | Design (safety limit) | Max frames before timeout (~167s @60fps) |
| `SCREEN_WIDTH` | 1280.0 | constants.gd | Viewport width for wall/ball/paddle positioning |
| `SCREEN_HEIGHT` | 720.0 | constants.gd | Viewport height for wall/ball/paddle positioning |
| `POINTS_TO_WIN_GAME` | 5 | constants.gd (preload) | Points needed to win a single game |
| `GAMES_TO_WIN_MATCH` | 2 | constants.gd (preload) | Games needed to win a match (best-of-3) |
| `PADDLE_WIDTH` | 20.0 | constants.gd (via `_CONSTS`) | Paddle collision shape width |
| `PADDLE_HEIGHT` | 120.0 | constants.gd (via `_CONSTS`) | Paddle collision shape height |
| `AI_REACTION_DELAY_MIN` | 0.1 | paddle.gd (default) | Minimum AI reaction delay (seconds) |
| `AI_REACTION_DELAY_MAX` | 0.3 | paddle.gd (default) | Maximum AI reaction delay (seconds) |
| `AI_POSITION_ERROR` | 20.0 | paddle.gd (default) | AI targeting error range (±pixels) |
| `BALL_INITIAL_SPEED` | 300.0 | constants.gd | Ball initial speed (pixels/sec) |

---

## 5. Implementation Spec

### Phase 1: Factory Functions (~60 lines)

**Priority: P0 (blocking)**

1. Implement `_make_wall(y)` — creates a `StaticBody2D` with `CollisionShape2D` (RectangleShape2D, size `1280x5`), added to `"walls"` group
2. Implement `_make_ball()` — `load("res://scenes/ball.tscn").instantiate()`, set `name="Ball"`, position at center
3. Implement `_make_ai_paddle(x, y)` — creates `Area2D`, sets script to `paddle.gd`, sets `mode=1`, adds `CollisionShape2D` (RectangleShape2D, size `20x120`)
4. Implement `_make_scoring_manager(ball)` — creates `Node`, sets script to `scoring_manager.gd`, manually sets `sm.ball = ball`

### Phase 2: Scene Assembly (~30 lines)

**Priority: P0 (blocking)**

5. Implement `_build_test_scene()` — creates `Node2D`, adds 6 children in order: top wall, bottom wall, ball, left paddle, right paddle, ScoringManager. Names paddles `PlayerPaddle` and `AIPaddle`.

### Phase 3: Match Loop (~80 lines)

**Priority: P0 (blocking)**

6. Implement `_run_match(scene, match_index)`:
   - Reset `GameManager` via `reset_match()`
   - Reset `ScoringManager` state variables manually
   - Reset paddle positions and AI state
   - Connect `GameManager.match_over` with `CONNECT_ONE_SHOT`
   - Call `ball.serve()`
   - Frame loop: `while not match_done and frame_count < MAX_FRAMES_PER_MATCH: await tree.process_frame`
   - Return result dictionary: `{winner, frames, timeout, player_score, ai_score, player_games, ai_games}`

### Phase 4: Verification (~50 lines)

**Priority: P0 (blocking)**

7. Implement `_verify_match(result, match_index)`:
   - VC1: No timeout
   - VC2: Winner ∈ {"player", "ai"}
   - VC3: Max games ≥ GAMES_TO_WIN_MATCH (2)
   - VC4: Winner's games ≥ GAMES_TO_WIN_MATCH
   - VC5: `GameManager.get_winner()` non-empty
   - VC6: `GameManager.get_winner()` matches signal winner

### Phase 5: Main Loop & Reporting (~70 lines)

**Priority: P0 (blocking)**

8. Implement `run()`:
   - Print header
   - `_build_test_scene()` once (reuse across matches)
   - Loop `MATCH_COUNT` times: `_run_match()` → `_verify_match()`
   - Track pass/fail/crash/timeout counters
   - Print per-match result line (winner, games, scores)
   - Print summary table with exit code determination

### Phase 6: run_tests.gd Integration (~3 lines)

**Priority: P1**

9. Add to `run_tests.gd::_run_tests()`:
   ```gdscript
   _run("res://tests/auto_play_test.gd", "Auto-Play")
   ```
   Add it as the **last** test entry (longest-running test should be last).

### Phase 7: Edge Case Verification

**Priority: P2 (nice-to-have)**

10. Verify ball velocity normalization after each match (Ball normalizes each frame — drift should be zero)
11. Verify paddle positions remain within bounds after each match
12. Verify GameManager autoload state is fully reset between matches (no residual scores/games)

---

## 6. Test Case Descriptions

> These are the validation checks built into `auto_play_test.gd` itself. The test IS the verification.

### Scenario A: No-Crash Validation

- **TC-A1: 100 matches execute without SCRIPT ERROR** — Headless Godot runs `auto_play_test.gd` for 100 matches. Any `push_error`, exception, or crash causes test failure. This is the primary acceptance criterion.

### Scenario B: Scoring Correctness

- **TC-B1: Every match scores to 5** — `ScoringManager` increments scores correctly; at least one side reaches 5 points before a game concludes. Verified via `player_score >= 5 or ai_score >= 5` at `game_won` time.
- **TC-B2: Best-of-3 logic correct** — Each match resolves as best-of-3: first to win 2 games wins the match. Never 2-2; never 1-0. Verified via `max(player_games, ai_games) >= 2` and `winner_games >= 2`.
- **TC-B3: Winner is unambiguous** — `GameManager.get_winner()` returns either `"player"` or `"ai"`, never `""`, never both. Verified at match end.

### Scenario C: Restart Integrity

- **TC-C1: GameManager.reset_match() works between matches** — Before each match, `player_score == 0 && ai_score == 0 && player_games_won == 0 && ai_games_won == 0`. Verified by reading GameManager state after `reset_match()`.
- **TC-C2: ScoringManager state reset works** — Before each match, `sm.player_score == 0 && sm.ai_score == 0 && sm.player_games == 0 && sm.ai_games == 0 && sm._is_match_over == false`. Verified by reading ScoringManager state after manual reset.
- **TC-C3: No residual state pollution** — Match N+1's starting state is identical to Match 1's. No score carryover, no frozen paddle, no stuck ball.

### Scenario D: Timeout Safety

- **TC-D1: All matches complete within MAX_FRAMES** — No match exceeds `MAX_FRAMES_PER_MATCH` (10000). If any match times out, it's counted as `_timeout_count` and reported as a failure with the frame count.
- **TC-D2: Ball does not get stuck** — The AI opponents are aggressive enough that every match eventually ends. No infinite ping-pong between paddles without scoring.

### Scenario E: Signal Integrity

- **TC-E1: match_over signal fires exactly once per match** — Using `CONNECT_ONE_SHOT`, each match's signal handler fires exactly once. No duplicate match_over emissions.
- **TC-E2: match_over carries correct winner** — The `winner` parameter matches `GameManager.get_winner()`.

### Scenario F: Component Integrity (sanity checks)

- **TC-F1: Ball velocity non-NaN** — After 100 matches, ball velocity is never NaN (ball.gd has a NaN guard that resets to `Vector2.RIGHT * speed` — verify this guard never triggered, or if it did, it recovered).
- **TC-F2: Paddles remain in bounds** — After 100 matches, paddle Y positions are always within `[min_y, max_y]`. Paddle's `_ai_process()` clamps position — verify no edge case bypasses the clamp.

---

## 7. Edge Cases & Error Handling

| # | Edge Case | Mitigation |
|---|-----------|------------|
| 1 | **Ball stuck between paddles (infinite rally)** | `MAX_FRAMES_PER_MATCH = 10000` safety limit (~167s @60fps). Match counted as timeout → failure. |
| 2 | **ScoringManager._is_match_over guard fails** | The guard `if _is_match_over: return` prevents post-match scoring. Verify this guard works across 100 matches by checking no score changes after `match_over` fires. |
| 3 | **GameManager autoload state bleed** | `reset_match()` called at the start of every match. Additionally, ScoringManager state is manually zeroed. Verify pre-match state is all-zeros. |
| 4 | **Ball NaN velocity** | `ball.gd` already detects NaN and resets (`velocity = Vector2.RIGHT * speed`). Test logs any NaN detections as warnings but continues. |
| 5 | **Paddle._resolve_ball() returns null** | Paddles are placed as siblings of Ball under the same parent — `_resolve_ball()`'s primary path (`parent.has_node("Ball")`) will succeed. If it fails, `_ai_process()` no-ops (returns early when `_ball_node == null`). |
| 6 | **ball.tscn _ready() connects to ScoreZone** | In the minimal scene, no ScoreZoneLeft/Right exist. `ball.tscn:_ready()` uses `get_node_or_null("ScoreZoneLeft")` and `get_node_or_null("ScoreZoneRight")` — both return null, connections are skipped. Ball falls back to X-boundary scoring in `_process()`. |
| 7 | **ball.tscn _ready() calls serve() immediately** | Yes — but `serve()` in headless mode (no `get_tree()`) sets velocity immediately without delay. The test then calls `serve()` explicitly after match setup, which re-serves from the correct position. This double-serve is harmless. |
| 8 | **ScoringManager._ready() calls push_error if ball is null** | `sm.ball` is manually set before `add_child()`. The `_ready()` callback fires on `add_child()`, at which point `ball` is already set. No error. |
| 9 | **Paddle._ready() binds InputMap** | Only when `mode == Mode.PLAYER`. Our paddles are created with `mode = Mode.AI` (1) — InputMap binding is skipped. |
| 10 | **AudioEngine autoload references in paddle/ball** | `ball.gd:_on_body_entered()` calls `AudioEngine.play_wall_bounce()` guarded by `is_instance_valid(AudioEngine)`. In headless, AudioEngine._enabled is false, play methods no-op. These calls add negligible overhead and do not crash. |

---

## 8. Integration Points

| Integration | From | To | How | When |
|-------------|------|----|-----|------|
| Test runner entry | `run_tests.gd::_run_tests()` | `auto_play_test.gd::run()` | `_run("res://tests/auto_play_test.gd", "Auto-Play")` added as last entry | Each run_tests.gd invocation |
| Match reset | `auto_play_test.gd::_run_match()` | `GameManager.reset_match()` | Direct call on autoload singleton | Start of each match |
| Score tracking | `ScoringManager._on_ball_score()` | `GameManager.add_score()` | Existing signal chain (unchanged) | Every point scored |
| Match end detection | `auto_play_test.gd::_on_match_over()` | `GameManager.match_over` signal | `connect(_on_match_over, CONNECT_ONE_SHOT)` | End of each match |
| Winner verification | `auto_play_test.gd::_verify_match()` | `GameManager.get_winner()` | Direct call on autoload singleton | After each match |
| Ball serve | `auto_play_test.gd::_run_match()` | `ball.serve()` | Direct method call | Start of each match |
| Wall collision | `Ball._on_body_entered()` | `StaticBody2D` in `"walls"` group | Godot collision system (unchanged) | Every wall bounce |
| Paddle collision | `Ball._on_area_entered()` | Paddle `Area2D` in `"paddles"` group | Godot collision system (unchanged) | Every paddle hit |
| Paddle AI logic | `SceneTree._process()` | `paddle._process(delta)` → `_ai_process(delta)` | SceneTree auto-drives `_process()` | Every frame |

---

## 9. Correction to PRD

### PRD §1 "Headless 模式特殊性" — Timer Behavior

The PRD states that `create_timer(N)` in headless SceneTree "同样实时等待 N 秒". **Clarification:** In Godot 4.x, `SceneTree.create_timer(N)` in headless mode does wait real time unless `Engine.time_scale` is adjusted. This is correct — which is why Approach C avoids timers entirely. However, `await get_tree().process_frame` does NOT wait real time; it yields until the next simulated frame (driven by `_process` callbacks), which occurs at maximum CPU speed in headless mode.

### PRD §4 "Approach C" — Paddle `_process()` Auto-Execution

The PRD's Approach C pseudocode shows manual `paddle_left._ai_process(delta)` and `paddle_right._ai_process(delta)` calls in the frame loop. **Clarification:** When an `Area2D` with a script is added to the SceneTree via `add_child()`, its `_process(delta)` IS called automatically each frame. The manual calls are unnecessary. The DESIGN reflects this — manual calls are included only as a fallback if auto-execution is verified not to work during implementation.

### PRD §8 "给 Plan Agent 的移交要点" — ScoringManager reset

The PRD mentions that `scoring_manager`'s `_is_match_over` must be manually reset. **Confirmed:** `_is_match_over` is a `var` (not `@onready`), so setting `sm._is_match_over = false` after each match is correct and sufficient.

---

## 10. Verification

```bash
# 1. Standalone execution
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/auto_play_test.gd
echo "Exit: $?"

# 2. Via run_tests.gd (after adding entry)
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/run_tests.gd
echo "Exit: $?"

# 3. Quick smoke test (1 match instead of 100)
# Temporarily change MATCH_COUNT = 1, verify:

# 4. Verify no existing files modified
git diff --stat  # should show only: tests/auto_play_test.gd (new), tests/run_tests.gd (modified)

# 5. Check ball.tscn loads in headless
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --quit
echo "Exit: $?"  # should be 0
```

---

## 11. Files Changed Summary

| # | File | Type | Change | Est. Lines |
|---|------|------|--------|-----------|
| 1 | `mini-pong/tests/auto_play_test.gd` | **New** | Full test script with factory functions, match loop, verification, reporting | +350 |
| 2 | `mini-pong/tests/run_tests.gd` | Modify | Add `_run("res://tests/auto_play_test.gd", "Auto-Play")` entry (1 line) | +1 |
| **Total** | | | | **~351 net new** |

---

## 12. Implementation Order

| Phase | Priority | Components | Est. Lines | Depends On |
|:-----:|:--------:|-----------|:----------:|-----------|
| 1 | P0 | Factory functions (`_make_wall`, `_make_ball`, `_make_ai_paddle`, `_make_scoring_manager`) | ~60 | None |
| 2 | P0 | Scene assembly (`_build_test_scene`) | ~30 | Phase 1 |
| 3 | P0 | Match loop (`_run_match`) | ~80 | Phase 2 |
| 4 | P0 | Verification (`_verify_match`) | ~50 | Phase 3 |
| 5 | P0 | Main loop + reporting (`run`) | ~70 | Phase 4 |
| 6 | P1 | `run_tests.gd` integration | ~3 | Phase 5 |
| 7 | P2 | Manual smoke test (MATCH_COUNT=1) and full 100-match validation | — | Phase 6 |

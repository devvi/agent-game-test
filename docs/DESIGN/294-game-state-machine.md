# Design: 游戏状态管理 — Game State Machine

> **Parent Issue:** #294
> **Agent:** game-plan-agent
> **Date:** 2026-07-30
> **Approach:** A — Scene-level FSM Node with enum state dispatch (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                         ← unchanged (ui_accept is Godot built-in)
├── gdscripts/
│   ├── game_state_machine.gd             ← NEW: 5-state FSM node script (~160 lines)
│   ├── paddle.gd                         ← MODIFIED: +frozen bool, _process guard
│   ├── scoring_manager.gd                ← MODIFIED: remove _pause_and_serve() serve logic
│   ├── start_menu.gd                     ← MODIFIED: remove _input(), keep show/hide API
│   ├── game_over_screen.gd               ← MODIFIED: remove _input(), keep signal handlers
│   ├── ball.gd                           ← unchanged (API: serve() + _is_serving)
│   ├── game_hud.gd                       ← unchanged (visible toggle only)
│   ├── game_manager.gd                   ← unchanged
│   └── ball_trail.gd                     ← unchanged (indirect: stops when ball frozen)
├── scenes/
│   └── game.tscn                         ← MODIFIED: add GameStateMachine Node
```

**Design philosophy:** Add a single scene-level FSM node to `game.tscn` that centralizes all runtime state orchestration — currently scattered across `start_menu.gd`, `scoring_manager.gd`, and `game_over_screen.gd`. The FSM uses `@onready` node references (not runtime `get_node()`), signal-driven transitions, and `await`-based timers (same pattern already proven in `scoring_manager.gd`). The FSM is NOT an autoload — it lives in `game.tscn` alongside the nodes it orchestrates, consistent with the project's existing pattern (ScoringManager, ScoreFlash are also scene-level Node scripts).

### Key Architectural Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | FSM location | Scene-level Node in `game.tscn` | Single-scene game — no need for global autoload. Aligns with existing ScoringManager pattern. |
| 2 | State dispatch | `enum State` + `match` in `enter_state()` / `exit_state()` | Explicit, traceable, no magic strings. Godot 4.x native enum support with typed match. |
| 3 | Node references | `@onready var` set via `game.tscn` node_path exports | No runtime `get_node("../Foo")` — references resolved at scene load. Null-guarded with warning fallback. |
| 4 | Input routing | FSM's `_input()` consumes `ui_accept`, gate by current_state | Centralized — no per-script input handling. StartMenu/GameOverScreen `_input()` removed. |
| 5 | Physics freeze | Paddle: `frozen` bool checked in `_process()`. Ball: existing `_is_serving` | Minimal change — paddle gets +2 lines, ball unchanged. |
| 6 | Timers | `await get_tree().create_timer(1.0).timeout` | Same pattern proven in `scoring_manager.gd:107-113`. Headless-safe with `get_tree()` null guard. |
| 7 | Signal source for match_over | Connect to `GameManager.match_over` | Global autoload signal — survives potential future scene changes. `ScoringManager.match_over` also fires but FSM uses the autoload. |

### State Transition Diagram

```
     ┌──────────────────────────────────────────────────────┐
     │                                                      │
     ▼                                                      │
   MENU ──[SPACE]──► SERVING ──[1s timer]──► PLAYING       │
     ▲                                        │             │
     │                          [scored signal]│             │
     │                                        ▼             │
     │                         SCORED ──[1s timer]──┐       │
     │                           │                  │       │
     │              [match_over] │     [no winner]──┘       │
     │                           ▼                          │
     └──────────[SPACE]──── GAME_OVER                       │
```

**State responsibilities:**

| State | UI Visible | Input Active | Ball Moving | Paddle Moving |
|-------|-----------|-------------|-------------|---------------|
| `MENU` | StartMenu | SPACE only | No (`_is_serving`) | No (`frozen=true`) |
| `SERVING` | GameHUD | None | No (awaiting serve) | No (`frozen=true`) |
| `PLAYING` | GameHUD | WASD/Arrows | Yes | Yes (`frozen=false`) |
| `SCORED` | GameHUD | None | No (`_is_serving`) | No (`frozen=true`) |
| `GAME_OVER` | GameOverScreen | SPACE only | No (`_is_serving`) | No (`frozen=true`) |

---

## 2. New Components — Detailed Design

### 2.1 `game_state_machine.gd`

- **File:** `mini-pong/gdscripts/game_state_machine.gd`
- **Type:** Scene Node script (`extends Node`)
- **Line estimate:** ~160 lines

#### State Enum

```gdscript
enum State {
    MENU,
    SERVING,
    PLAYING,
    SCORED,
    GAME_OVER
}
```

#### Internal State Variables

```gdscript
var current_state: State = State.MENU
var _transition_lock: bool = false       # prevents double-SPACE in MENU/GAME_OVER
var _scored_timer_active: bool = false   # flag to cancel scored→serving timer on match_over
```

#### @onready Node References (set via game.tscn exports)

```gdscript
@onready var start_menu: CanvasLayer = $"../StartMenu"
@onready var game_hud: CanvasLayer = $"../GameHUD"
@onready var game_over_screen: CanvasLayer = $"../GameOverScreen"
@onready var ball: Area2D = $"../Ball"
@onready var player_paddle: Area2D = $"../PlayerPaddle"
@onready var ai_paddle: Area2D = $"../AIPaddle"
@onready var scoring_manager: Node = $"../ScoringManager"
```

**Note on paths:** All nodes are siblings under the `Game` Node2D root. `GameStateMachine` is added as a sibling Node — path `"../<Name>"` resolves correctly.

#### Lifecycle Methods

```gdscript
func _ready() -> void:
    # Null-guard all references; log warnings not crashes
    _validate_references()

    # Connect to ScoringManager signals for state transitions
    if scoring_manager:
        scoring_manager.scored.connect(_on_scored)
        # match_over: connect to GameManager (global autoload, more durable)
    if is_instance_valid(GameManager):
        GameManager.match_over.connect(_on_match_over)

    # Initial state: MENU
    enter_state(State.MENU)

func _input(event: InputEvent) -> void:
    if not event.is_action_pressed("ui_accept"):
        return
    match current_state:
        State.MENU:
            if not _transition_lock:
                _transition_lock = true
                transition_to(State.SERVING)
        State.GAME_OVER:
            if not _transition_lock:
                _transition_lock = true
                transition_to(State.MENU)
        _:
            pass  # ignore SPACE in all other states
```

#### State Management

```gdscript
func transition_to(next: State) -> void:
    if next == current_state:
        return
    exit_state(current_state)
    current_state = next
    enter_state(next)

func enter_state(state: State) -> void:
    match state:
        State.MENU:
            _set_ui("start_menu")
            _freeze_paddles(true)
            _transition_lock = false  # allow SPACE to start
        State.SERVING:
            _set_ui("hud")
            _freeze_paddles(true)
            GameManager.reset_match()
            await _timer_1s()
            if ball:
                ball.serve()
            # ball.serve() has internal 0.5s delay via await
            # Wait for ball serve to complete before transitioning
            if ball and ball._is_serving:
                await _wait_for_serve()
            _transition_lock = false
            if current_state == State.SERVING:
                transition_to(State.PLAYING)
        State.PLAYING:
            _set_ui("hud")
            _freeze_paddles(false)
        State.SCORED:
            _set_ui("hud")
            _freeze_paddles(true)
            _scored_timer_active = true
            await _timer_1s()
            _scored_timer_active = false
            if current_state == State.SCORED:
                if GameManager.get_winner() != "":
                    transition_to(State.GAME_OVER)
                else:
                    transition_to(State.SERVING)
        State.GAME_OVER:
            _set_ui("game_over")
            _freeze_paddles(true)
            _transition_lock = false  # allow SPACE to restart

func exit_state(state: State) -> void:
    match state:
        State.SCORED:
            _scored_timer_active = false  # cancel pending timer
        _:
            pass
```

#### Signal Handlers

```gdscript
func _on_scored(winner: String) -> void:
    # Guard: only transition from PLAYING
    if current_state != State.PLAYING:
        push_warning("FSM: scored signal received in state ", current_state, " — ignoring")
        return
    transition_to(State.SCORED)

func _on_match_over(winner: String) -> void:
    # Guard: only relevant in SCORED or PLAYING (immediate match end)
    if current_state == State.GAME_OVER:
        return  # already in game_over, ignore duplicate
    # If in SCORED with timer active, exit_state cancels the timer
    transition_to(State.GAME_OVER)
```

#### Helper Methods

```gdscript
func _set_ui(layer: String) -> void:
    if start_menu:
        start_menu.visible = (layer == "start_menu")
    if game_hud:
        game_hud.visible = (layer == "hud")
    if game_over_screen:
        game_over_screen.visible = (layer == "game_over")

func _freeze_paddles(freeze: bool) -> void:
    if player_paddle and player_paddle.has_method("set_frozen"):
        player_paddle.set_frozen(freeze)
    if ai_paddle and ai_paddle.has_method("set_frozen"):
        ai_paddle.set_frozen(freeze)

func _timer_1s() -> void:
    var tree := get_tree() if is_inside_tree() else null
    if tree:
        await tree.create_timer(1.0).timeout
    # Headless: skip timer, proceed immediately

func _wait_for_serve() -> void:
    # Wait until ball._is_serving becomes false (serve animation complete)
    var tree := get_tree() if is_inside_tree() else null
    if not tree or not ball:
        return
    while ball._is_serving and is_instance_valid(ball):
        await tree.process_frame

func _validate_references() -> void:
    var refs := {
        "start_menu": start_menu,
        "game_hud": game_hud,
        "game_over_screen": game_over_screen,
        "ball": ball,
        "player_paddle": player_paddle,
        "ai_paddle": ai_paddle,
        "scoring_manager": scoring_manager,
    }
    for name in refs:
        if refs[name] == null:
            push_warning("FSM: @onready var '", name, "' is null — check game.tscn node_path")
```

#### Edge Cases Handled

| # | Edge Case | Behavior |
|---|-----------|----------|
| 1 | Double SPACE in MENU/GAME_OVER | `_transition_lock` blocks repeat `transition_to()` until next state's `enter_state()` resets it |
| 2 | `scored` signal in non-PLAYING state | Guard: log warning, return — no state change |
| 3 | `match_over` during SCORED timer | `exit_state(SCORED)` sets `_scored_timer_active=false`; timer's `await` continuation checks `current_state == State.SCORED` before proceeding → skips |
| 4 | Ball `serve()` internal 0.5s delay | FSM waits via `_wait_for_serve()` polling `ball._is_serving` per frame before transitioning to PLAYING |
| 5 | Headless mode (`get_tree() == null`) | `_timer_1s()` and `_wait_for_serve()` skip gracefully; FSM transitions without delay |
| 6 | Null node reference (misconfigured game.tscn) | `_validate_references()` logs warnings; `_set_ui()` and `_freeze_paddles()` null-check before access |
| 7 | `match_over` from GameManager re-fires | Guard: if already in `GAME_OVER`, ignore signal |

#### Signal Chain

```
Ball._process() → ball.score(side)
  → ScoringManager._on_ball_score(side)
    → GameManager.add_score(winner)
    → scored.emit(winner)                    ← FSM._on_scored → transition_to(SCORED)
    → _win_game() → match_over.emit(winner)  ← FSM._on_match_over → transition_to(GAME_OVER)
```

---

## 3. Existing Component Modifications

| # | File | Nature of Change | Est. Δ Lines |
|---|------|-----------------|-------------|
| 1 | `mini-pong/scenes/game.tscn` | Add `GameStateMachine` Node with ext_resource script; add `@export` node_path assignments | +6 lines |
| 2 | `mini-pong/gdscripts/paddle.gd` | Add `frozen` bool + `set_frozen()` method + `_process` guard | +6 lines |
| 3 | `mini-pong/gdscripts/scoring_manager.gd` | In `_pause_and_serve()`: remove 1s await + `ball.serve()` call; keep method as no-op or remove entirely | −8 lines |
| 4 | `mini-pong/gdscripts/start_menu.gd` | Remove `_input()` method (lines 35-39); keep `show_menu()` / `hide_menu()` API | −5 lines |
| 5 | `mini-pong/gdscripts/game_over_screen.gd` | Remove `_input()` method (lines 39-43); keep `_on_match_over()` signal handler | −5 lines |

### 3.1 `game.tscn` — precise modification

**Add after ScoringManager node (line 41-42):**

```ini
[node name="GameStateMachine" type="Node" parent="."]
script = ExtResource("7_game_state_machine")
start_menu = NodePath("../StartMenu")
game_hud = NodePath("../GameHUD")
game_over_screen = NodePath("../GameOverScreen")
ball = NodePath("../Ball")
player_paddle = NodePath("../PlayerPaddle")
ai_paddle = NodePath("../AIPaddle")
scoring_manager = NodePath("../ScoringManager")
```

**Add ext_resource reference at top:**
```ini
[ext_resource type="Script" path="res://gdscripts/game_state_machine.gd" id="7_game_state_machine"]
```

### 3.2 `paddle.gd` — precise modification

**Add after line 25 (`var _ai_error_offset: float = 0.0`):**
```gdscript
# ── Freeze control (FSM) ──
var frozen: bool = false

func set_frozen(value: bool) -> void:
    frozen = value
```

**Modify `_process()` (line 77): add guard at top:**
```gdscript
func _process(delta: float) -> void:
    if frozen:
        return
    # ... existing code
```

### 3.3 `scoring_manager.gd` — precise modification

**Remove `_pause_and_serve()` body (lines 107-113), replace with no-op:**
```gdscript
func _pause_and_serve() -> void:
    # FSM (#294) handles pause + serve timing.
    # ScoringManager now only emits signals; no longer controls ball serve.
    pass
```

**Also remove the two `await _pause_and_serve()` calls (lines 75, 104):**
- Line 75: Change `await _pause_and_serve()` to `_pause_and_serve()` (remove await)
- Line 104: Change `await _pause_and_serve()` to `_pause_and_serve()` (remove await)

Or better: remove both calls entirely since the method is now a no-op.

### 3.4 `start_menu.gd` — precise modification

**Remove `_input()` method (lines 35-39):**
```gdscript
# REMOVED: _input() — FSM (#294) handles SPACE in MENU state
```

**Keep:** `_ready()`, `show_menu()`, `hide_menu()`, `_start_title_pulse()`, `_start_prompt_blink()`, `_on_start_pressed()` (deprecated but harmless), `_get_sibling()`, tween helpers.

**Note:** `_on_start_pressed()` at line 76 is no longer called from `_input()`, but may still be useful if `StartMenu` has a Button child in a future iteration. The method is harmless to leave in place.

### 3.5 `game_over_screen.gd` — precise modification

**Remove `_input()` method (lines 39-43):**
```gdscript
# REMOVED: _input() — FSM (#294) handles SPACE in GAME_OVER state
```

**Keep:** `_ready()`, `_on_match_over(winner)`, `_start_winner_pulse()`, `_start_prompt_blink()`, `_on_restart_pressed()` (deprecated but harmless), `_get_sibling()`, tween helpers.

**Note:** `_on_match_over()` at line 47 still handles winner text/color and hides HUD. This can be left as-is (FSM also sets UI visibility, creating redundancy that's harmless) or simplified in a follow-up.

### Files NOT Modified

| File | Reason |
|------|--------|
| `mini-pong/gdscripts/ball.gd` | `serve()` and `_is_serving` are API — called/read by FSM, no changes needed |
| `mini-pong/gdscripts/game_hud.gd` | `visible` toggle only — FSM writes to existing property |
| `mini-pong/gdscripts/ball_trail.gd` | Indirect: trail stops when ball `_is_serving=true`, no code change needed |
| `mini-pong/gdscripts/game_manager.gd` | Unchanged — `reset_match()`, `get_winner()`, `match_over` signal used as-is |
| `mini-pong/project.godot` | Unchanged — `ui_accept` is Godot 4.x built-in action (Space + Enter), no explicit binding needed |

---

## 4. Data Flow

### Flow 1: Game Start (MENU → SERVING → PLAYING)

```
SPACE press
  → FSM._input() → current_state == MENU
    → transition_to(SERVING)
      → enter_state(SERVING):
        _set_ui("hud")           → StartMenu.visible=false, GameHUD.visible=true
        _freeze_paddles(true)     → paddle.frozen = true
        GameManager.reset_match() → all scores zeroed
        await _timer_1s()         → 1 second countdown
        ball.serve()              → ball repositions to center, starts 0.5s serve animation
        await _wait_for_serve()   → poll ball._is_serving until false
        transition_to(PLAYING)
      → enter_state(PLAYING):
        _set_ui("hud")           → GameHUD remains visible
        _freeze_paddles(false)    → paddle.frozen = false (movement resumes)
```

### Flow 2: Point Scored (PLAYING → SCORED → SERVING or GAME_OVER)

```
Ball exits boundary → ball.score(side)
  → ScoringManager._on_ball_score(side)
    → GameManager.add_score(winner)    → score_changed → GameHUD updates
    → scored.emit(winner)
      → FSM._on_scored(winner)
        → transition_to(SCORED)
          → enter_state(SCORED):
            _freeze_paddles(true)       → paddles frozen
            await _timer_1s()           → 1 second freeze
            if GameManager.get_winner() != "":
              transition_to(GAME_OVER)  → winner determined
            else:
              transition_to(SERVING)    → next serve round
```

### Flow 3: Match Over (GAME_OVER → MENU)

```
GameManager.match_over.emit(winner)
  → FSM._on_match_over(winner)
    → transition_to(GAME_OVER)
      → enter_state(GAME_OVER):
        _set_ui("game_over")       → GameOverScreen.visible=true
        _freeze_paddles(true)
        _transition_lock = false   → allow SPACE

SPACE press
  → FSM._input() → current_state == GAME_OVER
    → transition_to(MENU)
      → enter_state(MENU):
        _set_ui("start_menu")      → StartMenu.visible=true
        _freeze_paddles(true)
        _transition_lock = false   → allow SPACE to start again
```

### Flow 4: Rapid match_over during SCORED timer

```
scored.emit → transition_to(SCORED) → await _timer_1s() [timer started]

  [timer running...]
  match_over.emit from GameManager
    → FSM._on_match_over()
      → transition_to(GAME_OVER)
        → exit_state(SCORED): _scored_timer_active = false
        → enter_state(GAME_OVER): UI switches, paddles frozen

  [timer expires, await continues]
    → checks: current_state == State.SCORED? → NO (now GAME_OVER)
    → skips → no spurious transition_to(SERVING)
```

---

## 5. Integration Points

| Integration | From | To | How | When |
|-------------|------|----|-----|------|
| Score signal | `ScoringManager.scored(winner)` | `FSM._on_scored()` | `scored.connect()` in FSM `_ready()` | Every point |
| Match over signal | `GameManager.match_over(winner)` | `FSM._on_match_over()` | `GameManager.match_over.connect()` in FSM `_ready()` | Match conclusion |
| Match reset | `FSM.enter_state(SERVING)` | `GameManager.reset_match()` | Direct call | Game start / new round |
| Winner query | `FSM.enter_state(SCORED)` | `GameManager.get_winner()` | Direct call | After scored freeze |
| Paddle freeze | `FSM._freeze_paddles()` | `paddle.set_frozen(bool)` | Method call via @onready ref | All state transitions |
| Ball serve | `FSM.enter_state(SERVING)` | `ball.serve()` | Direct call | Before playing starts |
| UI visibility | `FSM._set_ui(layer)` | `start_menu/game_hud/game_over_screen.visible` | Property write via @onready ref | All state transitions |
| SPACE input | `InputEvent(ui_accept)` | `FSM._input()` | Built-in `_input()` callback | MENU / GAME_OVER only |
| GameOver display | `GameManager.match_over` | `game_over_screen._on_match_over()` | Existing connection (unchanged) | Match conclusion |

---

## 6. Correction to PRD

The PRD (Section 1, "当前状态" table, row "比赛结束→菜单") describes `game_over_screen.gd` connecting to `ScoringManager.match_over`. **Correction:** The actual code at `game_over_screen.gd:32-34` connects to `GameManager.match_over` (the global autoload), not `ScoringManager.match_over`. The FSM follows the same pattern — connecting to `GameManager.match_over` for durability. This is a documentation discrepancy in the PRD only; the design is not affected.

The PRD (Section 3, "间接影响") lists `mini-pong/project.godot` as possibly needing `ui_accept` binding. **Correction:** `ui_accept` is a built-in Godot 4.x action with default bindings of `Space` and `Enter` keys. No explicit `InputMap` configuration is needed. The PRD's concern is noted but the existing Godot defaults suffice.

---

## 7. Test Case Descriptions

> Descriptions only — implement agent writes runnable tests.

### Scenario A: State Enum and Compilation

- **TC1:** Run `godot --path mini-pong/ --headless --quit` — exit code 0. Verifies FSM script parses, all `@onready` references resolve, `GameManager` autoload accessible.
- **TC2:** Instantiate FSM in headless test script — assert `current_state == State.MENU` after `_ready()`, verify 5 enum values exist.

### Scenario B: State Transitions (Normal Path)

- **TC3:** MENU → SERVING: Simulate SPACE press → assert `current_state == State.SERVING`, assert `_transition_lock == true`, then after timer + serve → assert `current_state == State.PLAYING`.
- **TC4:** PLAYING → SCORED: Emit `scoring_manager.scored.emit("player")` → assert `current_state == State.SCORED`.
- **TC5:** SCORED → SERVING (no winner): After entering SCORED, await timer, with `GameManager.get_winner() == ""` → assert `current_state == State.SERVING`.
- **TC6:** SCORED → GAME_OVER (winner exists): Set `GameManager.player_games_won = 2`, enter SCORED, await timer → assert `current_state == State.GAME_OVER`.
- **TC7:** GAME_OVER → MENU: Simulate SPACE press in GAME_OVER → assert `current_state == State.MENU`.

### Scenario C: Edge Cases

- **TC8:** Double SPACE in MENU: Two rapid SPACE events → only first triggers `transition_to(SERVING)`, second blocked by `_transition_lock`.
- **TC9:** `scored` signal in non-PLAYING state: Emit `scored` while in MENU → state unchanged, warning logged.
- **TC10:** `match_over` during SCORED timer: Enter SCORED, immediately emit `match_over` → state changes to GAME_OVER, SCORED timer continuation detects state changed and does NOT transition to SERVING.
- **TC11:** Null node reference: Instantiate FSM without setting `@onready` refs → `_validate_references()` logs warnings, `enter_state()` null-checks prevent crashes.

### Scenario D: Subsystem Control

- **TC12:** UI visibility in MENU: Assert `start_menu.visible == true`, `game_hud.visible == false`, `game_over_screen.visible == false`.
- **TC13:** UI visibility in PLAYING: Assert `start_menu.visible == false`, `game_hud.visible == true`, `game_over_screen.visible == false`.
- **TC14:** UI visibility in GAME_OVER: Assert `start_menu.visible == false`, `game_hud.visible == false`, `game_over_screen.visible == true`.
- **TC15:** Paddle freeze in MENU: Assert `player_paddle.frozen == true`.
- **TC16:** Paddle freeze in PLAYING: Assert `player_paddle.frozen == false`, `ai_paddle.frozen == false`.
- **TC17:** `GameManager.reset_match()` called on SERVING enter: Spy on GameManager → assert `reset_match()` was called once.

---

## 8. Verification

```bash
# 1. Compile verification
godot --path mini-pong/ --headless --quit
echo "Exit: $?"

# 2. FSM instantiation smoke test (headless)
cat > /tmp/test_fsm.gd << 'SCRIPT'
extends Node

func _ready():
    # Mock GameManager if needed for headless
    var fsm_script = load("res://gdscripts/game_state_machine.gd")
    var fsm = Node.new()
    fsm.set_script(fsm_script)
    # Verify script loaded
    assert(fsm != null, "FSM script failed to load")
    assert(fsm.has_method("transition_to"), "FSM missing transition_to()")
    assert(fsm.has_method("enter_state"), "FSM missing enter_state()")
    print("PASS: FSM script smoke test")
    get_tree().quit(0)
SCRIPT
godot --path mini-pong/ --headless --script /tmp/test_fsm.gd

# 3. Verify paddle.gd frozen guard compiles
grep -n "frozen" mini-pong/gdscripts/paddle.gd

# 4. Verify no remaining _input() in modified files
grep -n "_input" mini-pong/gdscripts/start_menu.gd mini-pong/gdscripts/game_over_screen.gd

# 5. Verify scoring_manager no longer calls ball.serve()
grep -n "ball.serve" mini-pong/gdscripts/scoring_manager.gd
```

---

## 9. Files Changed Summary

| # | File | Type | Change | Est. Lines |
|---|------|------|--------|-----------|
| 1 | `mini-pong/gdscripts/game_state_machine.gd` | **New** | Full FSM script | +160 |
| 2 | `mini-pong/scenes/game.tscn` | Modify | Add GameStateMachine Node + ext_resource | +8 |
| 3 | `mini-pong/gdscripts/paddle.gd` | Modify | Add `frozen` + `set_frozen()` + `_process` guard | +6 |
| 4 | `mini-pong/gdscripts/scoring_manager.gd` | Modify | Remove serve from `_pause_and_serve()`, remove await calls | −8 |
| 5 | `mini-pong/gdscripts/start_menu.gd` | Modify | Remove `_input()` | −5 |
| 6 | `mini-pong/gdscripts/game_over_screen.gd` | Modify | Remove `_input()` | −5 |
| **Total** | | | | **~156 net new** |

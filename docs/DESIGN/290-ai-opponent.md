# DESIGN: AI 对手 — AI Opponent

> **Parent Issue:** #290
> **Agent:** game-plan-agent
> **Date:** 2026-07-29
> **Approach:** A — 扩展 `paddle.gd` 添加 AI 模式 (PRD recommendation, confirmed)

---

## 1. Architecture Overview

**Core idea:** Extend the existing `paddle.gd` with an AI mode enum. When `mode == MODE_AI`, `_process()` bypasses player input and instead runs AI ball-tracking logic — target acquisition with randomized delay + position error, distance-based speed adjustment, and boundary clamping. The AI paddle reuses all existing infrastructure (boundary calc, `paddles` group registration, CollisionShape2D structure) from the player paddle.

```
┌─────────────────────────────────────────────────────────────┐
│                      game.tscn                               │
│  ┌──────────────────┐              ┌──────────────────────┐  │
│  │   PlayerPaddle   │              │     AIPaddle          │  │
│  │  (mode=PLAYER)   │              │  (mode=AI)            │  │
│  │  x = 50          │              │  x = 1230             │  │
│  │  input: WASD/↑↓  │              │  input: ball.y track  │  │
│  └──────────────────┘              └──────────────────────┘  │
│           │                                  │                │
│           └──────────┬───────────────────────┘                │
│                      ▼                                        │
│               ┌──────────┐                                   │
│               │   Ball   │  ← `paddles` group collision      │
│               │  x=640   │     (unchanged)                    │
│               └──────────┘                                   │
└─────────────────────────────────────────────────────────────┘
```

**AI processing flow (per frame):**

```
ball.global_position.y
    │
    ▼
┌──────────────────────────────────┐
│  _ai_delay_timer -= delta         │
│  if timer ≤ 0:                    │
│    timer = rand(100ms, 300ms)     │  ← reaction delay window
│    error  = rand(-20px, +20px)    │  ← position error
│    target = ball.y + error        │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│  dist = |position.y - target|     │
│  factor = dist ≥ 40 ? 1.2 : 0.8  │  ← speed adjust
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│  position.y += sign(target-y)     │
│              * SPEED * factor     │
│              * delta              │
│  position.y = clamp(y, min, max)  │  ← boundary safety
└──────────────────────────────────┘
```

**Key architectural decisions:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| AI logic location | Extend `paddle.gd` (Approach A) | Zero file duplication; reuse boundary calc, `paddles` group; minimal diff |
| Mode switching | `@export var mode: int` enum (0=PLAYER, 1=AI) | Godot-native pattern; editable per-instance in scene; clear separation |
| Ball reference | `get_parent().get_node("Ball")` with graceful null-safety | Matches `game.tscn` node hierarchy; no `@export` wiring needed per scene |
| Delay timing | `delta`-based accumulator | Frame-rate independent; works in headless CI |
| Speed threshold | 40px (2× error range) | Matches AC4 spec; `>=` on boost side, `<` on slow side |
| Headless safety | Null-guard `ball_node` + reuse `FALLBACK_VIEWPORT_Y` | CI compilation passes with zero exit code |

---

## 2. Modified Files

### 2.1 `mini-pong/gdscripts/paddle.gd`

**Nature of change:** Extend with AI mode — add `@export` enum + AI parameters, AI state variables, `_process()` mode dispatch, and `_ai_process()` method. Existing player input logic is preserved under `mode == MODE_PLAYER` guard.

**Current state (63 lines):**
- Constants: `SPEED`, `PADDLE_WIDTH`, `PADDLE_HEIGHT`, `FALLBACK_VIEWPORT_Y`
- State: `min_y`, `max_y`
- Methods: `_ready()` (InputMap binding + boundary calc + clamp), `_process()` (input → move → clamp)

**After change (~115 lines, +~52 lines):**

New additions:

```gdscript
# ── Mode enum ──
enum Mode { PLAYER = 0, AI = 1 }

@export var mode: Mode = Mode.PLAYER

# ── AI parameters (tunable in editor) ──
@export var ai_reaction_delay_min: float = 0.1   # 100ms
@export var ai_reaction_delay_max: float = 0.3   # 300ms
@export var ai_position_error: float = 20.0       # ±20px
@export var ai_speed_boost: float = 1.2           # +20% when trailing
@export var ai_speed_slow: float = 0.8            # -20% when ahead

# ── AI state ──
var _ball_node: Node2D = null
var _ai_delay_timer: float = 0.0
var _ai_target_y: float = 0.0
var _ai_error_offset: float = 0.0
```

**`_ready()` — ADD after boundary calc, before clamp:**

```gdscript
# Resolve ball reference (AI mode)
_ball_node = _resolve_ball()
if mode == Mode.AI and _ai_delay_timer <= 0.0:
    _ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)
```

**`_process(delta)` — WRAP existing logic in mode dispatch:**

```gdscript
func _process(delta: float) -> void:
    if mode == Mode.AI:
        _ai_process(delta)
        return
    # ... existing player input logic unchanged ...
```

**New method `_resolve_ball()`:**

```gdscript
func _resolve_ball() -> Node2D:
    # Primary path: sibling node named "Ball" in parent
    var parent := get_parent()
    if parent != null and parent.has_node("Ball"):
        return parent.get_node("Ball")
    # Fallback: scene-tree search (resilient to hierarchy changes)
    var tree := get_tree()
    if tree != null:
        var root := tree.root
        if root != null and root.has_node("Game/Ball"):
            return root.get_node("Game/Ball")
    return null
```

**New method `_ai_process(delta)`:**
```gdscript
func _ai_process(delta: float) -> void:
    if _ball_node == null:
        return

    # Decrement delay timer; on expiry, update target with new error
    _ai_delay_timer -= delta
    if _ai_delay_timer <= 0.0:
        _ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)
        _ai_error_offset = randf_range(-ai_position_error, ai_position_error)
        _ai_target_y = _ball_node.global_position.y + _ai_error_offset

    # Distance-based speed adjustment
    var dist := abs(position.y - _ai_target_y)
    var threshold := ai_position_error * 2.0  # 40px
    var factor := ai_speed_boost if dist >= threshold else ai_speed_slow

    # Move toward target and clamp
    var move := sign(_ai_target_y - position.y)
    position.y += move * SPEED * factor * delta
    position.y = clamp(position.y, min_y, max_y)
```

**`_ready()` change — InputMap binding guard:**

The existing `_ready()` registers InputMap actions with `has_action()` guards. When `mode == Mode.AI`, these bindings are unnecessary but harmless. To avoid unnecessary InputMap mutations in AI mode, wrap the InputMap block:

```gdscript
if mode == Mode.PLAYER:
    # ... existing InputMap binding code ...
```

**Line estimate:** +~52 lines net (add AI constants/enum/state/param ~20, add mode dispatch ~5, add `_resolve_ball()` ~10, add `_ai_process()` ~17 lines).

### 2.2 `mini-pong/scenes/game.tscn`

**Nature of change:** Add a second paddle instance for the AI opponent, positioned on the right side. Reuses `player_paddle.tscn` with `mode` override.

**Change:**
```diff
 [node name="PlayerPaddle" parent="." instance=ExtResource("2_player_paddle")]
 position = Vector2(50, 360)
+
+[node name="AIPaddle" parent="." instance=ExtResource("2_player_paddle")]
+position = Vector2(1230, 360)
```

The `mode` enum is set via the TSCN metadata section or via `_ready()` default. Since the default is `Mode.PLAYER`, the AI paddle instance needs `mode` override. In Godot 4.x TSCN format, this is done via:

```ini
[node name="AIPaddle" parent="." instance=ExtResource("2_player_paddle")]
position = Vector2(1230, 360)
mode = 1
```

**Position rationale:** `x = 1230` (1280 - 50, mirror of PlayerPaddle at x=50). This puts the AI paddle on the right edge matching the player paddle's left-edge offset.

---

## 3. New Files

None. All changes are modifications to existing files. No new scene file is created — the AI paddle reuses `player_paddle.tscn`.

---

## 4. API Contracts

### 4.1 Signal Connections

No new signals. Existing:
- `ball.gd` → `score(side: int)` signal already works with both paddles via `paddles` group
- `ball.gd` → `area_entered` already detects `paddles` group — AI paddle registers via `add_to_group("paddles")` in `_ready()`

### 4.2 Method Call Chains

```
game.tscn instantiation
  ├── _ball_node = _resolve_ball()      ← paddle.gd _ready()
  │     └── get_parent().get_node("Ball") → Node2D or null
  ├── _ai_delay_timer = rand(100ms,300ms) ← initial random delay
  └── add_to_group("paddles")           ← existing

per-frame:
  _process(delta) → mode == AI ?
    └── _ai_process(delta)
          ├── ball_node.global_position.y  ← read (no mutation)
          ├── randf_range(min, max)        ← delay + error
          ├── position.y += ...            ← write
          └── clamp(position.y, min, max)  ← existing
```

### 4.3 External Writable Properties

| Property | Type | Default | Writable | Purpose |
|----------|------|---------|:--------:|---------|
| `mode` | int (enum) | 0 (PLAYER) | ✅ | Switch between player/AI |
| `ai_reaction_delay_min` | float | 0.1 | ✅ | Min delay (seconds) |
| `ai_reaction_delay_max` | float | 0.3 | ✅ | Max delay (seconds) |
| `ai_position_error` | float | 20.0 | ✅ | ±error range (pixels) |
| `ai_speed_boost` | float | 1.2 | ✅ | Speed multiplier when trailing |
| `ai_speed_slow` | float | 0.8 | ✅ | Speed multiplier when ahead |

All writable for future difficulty-adjustment systems.

---

## 5. Data Flow

### Flow 1: AI Normal Tracking (happy path)

```
frame N, delta=0.016
  │
  ▼
_ai_process(0.016)
  ├── _ball_node.global_position.y = 400.0 (ball moving down)
  ├── _ai_delay_timer = 0.25 → 0.234 after delta
  │   └── timer > 0 → skip target update, use stale _ai_target_y=350.0
  ├── dist = |360.0 - 350.0| = 10.0
  ├── 10.0 < 40.0 (threshold) → factor = 0.8 (slow)
  ├── move = sign(350.0 - 360.0) = -1.0
  ├── position.y += -1.0 * 400 * 0.8 * 0.016 = -5.12
  └── clamp(position.y, 60, 660) → OK

frame N+15 (delay expires)
  │
  ▼
_ai_process(0.016)
  ├── _ai_delay_timer = 0.002 → -0.014 → timer ≤ 0
  ├── _ai_delay_timer = rand(0.1, 0.3) = 0.18 (new delay)
  ├── _ai_error_offset = rand(-20, 20) = -12.0
  ├── _ai_target_y = ball.y + error = 420.0 + (-12.0) = 408.0
  ├── dist = |365.0 - 408.0| = 43.0
  ├── 43.0 ≥ 40.0 → factor = 1.2 (boost)
  ├── move = sign(408.0 - 365.0) = +1.0
  ├── position.y += 1.0 * 400 * 1.2 * 0.016 = +7.68
  └── clamp → OK
```

### Flow 2: AI Headless / No Ball

```
_ai_process(0.016)
  ├── _ball_node == null (ball not found in scene tree)
  └── early return → no position change, no crash
```

### Flow 3: Extreme Target Y (ball at edge)

```
_ai_process(0.016)
  ├── _ai_target_y = -100.0 (ball at top + error)
  ├── dist = |60.0 - (-100.0)| = 160.0
  ├── 160.0 ≥ 40.0 → factor = 1.2
  ├── move = sign(-100.0 - 60.0) = -1.0
  ├── position.y += -1.0 * 400 * 1.2 * 0.016 = -7.68
  └── clamp(position.y, 60, 660) → 60.0 (clamped at min_y)
```

### Flow 4: Player Mode Backward Compatibility

```
_process(0.016)
  ├── mode = Mode.PLAYER (0)
  ├── → existing player input logic runs unchanged
  └── AI state variables ignored
```

---

## 6. Edge Cases & Error Handling

| # | Edge Case | Behavior | Verification |
|---|-----------|----------|-------------|
| 1 | **Ball node missing** (removed/renamed) | `_resolve_ball()` returns null → `_ai_process()` early-returns; paddle stays in place | Headless test with no Ball node in scene |
| 2 | **Ball position extreme** (Y = -9999 or 9999) | Target Y calculated but final position clamped to [min_y, max_y] | TC-C1/C2 boundary tests |
| 3 | **Delay timer initial state** | `_ready()` sets initial `_ai_delay_timer` to random positive value so first frame doesn't update target | TC-A1: verify timer > 0 after `_ready()` |
| 4 | **Very large delta** (frame spike > 0.1s) | Speed multiplier + delta means larger position jump; clamp still ensures in-bounds | TC-C3: set delta=0.5, verify position within bounds |
| 5 | **Distance exactly equals threshold** (40px) | `dist >= threshold` → boost (1.2). This means exactly-at-threshold triggers acceleration, which is correct — the paddle is far enough to need catching up | TC-B3: verify factor at exact threshold |
| 6 | **Mode invalid value** (e.g., 99) | Falls through to player branch (no AI logic runs); default behavior safe | Structural: verify `mode` enum guards in source |
| 7 | **Headless: get_viewport() returns null** | Existing `FALLBACK_VIEWPORT_Y = 720.0` handles boundary calc; AI logic only reads `_ball_node.global_position.y` which is valid in headless scene context | CI: `godot --headless --quit` exit 0 |
| 8 | **Re-instantiation duplicates** | Second AIPaddle re-runs `_ready()` → `_resolve_ball()` re-resolves (same node). No conflict — each paddle tracks its own `_ai_target_y` | TC-F1: two AI paddles coexist |

---

## 7. Integration Points

| Integration | Component | How |
|-------------|-----------|-----|
| Ball collision (#287) | `paddles` group | AI paddle calls `add_to_group("paddles")` in `_ready()` — zero code change in `ball.gd` |
| Scoring (#291) | `ball.score` signal | Ball emits `score(0)` when exiting right (player scores), `score(1)` when exiting left (AI scores) — unchanged |
| Game scene (#301) | `game.tscn` | AIPaddle instance added at x=1230; no new scene file needed |
| Visual system (#289) | ColorRect color | AI paddle inherits white ColorRect from `player_paddle.tscn` — visual differentiation deferred to #289 |
| Future difficulty | `@export` params | All AI parameters are writable — external system can adjust `ai_speed_boost` etc. at runtime |
| Headless CI | `run_tests.gd` | AI tests use RefCounted pattern (same as `test_paddle.gd`) — no tree context needed |

---

## 8. Test Case Descriptions

> **Testing pattern:** RefCounted + `run()` + `_assert()`, registered in `run_tests.gd`. Tests create bare `Area2D` + `set_script(load("paddle.gd"))` + configure `mode = Mode.AI` + mock `_ball_node`.

### Scenario A: AI State Initialization

- **TC-A1 — Mode enum default:** Create paddle without setting mode → verify `mode == Mode.PLAYER` (0). AI code path not entered.
- **TC-A2 — AI mode activation:** Set `mode = Mode.AI` on a paddle → verify after `_ready()`, `_ai_delay_timer > 0` (initial random delay is positive).
- **TC-A3 — Ball node resolution:** Create paddle as child of a mock parent with a `Ball` node → call `_resolve_ball()` → verify returns the Ball node reference (not null).

### Scenario B: AI Movement & Speed Adjustment

- **TC-B1 — Move toward target:** Set `mode = AI`, manually set `_ball_node` to a mock with `global_position.y = 400`, set `_ai_target_y = 400`, position at 360 → call `_ai_process(0.016)` → verify `position.y` increases (moves down toward 400).
- **TC-B2 — Speed boost when trailing:** Set `_ai_target_y = 500`, paddle at 360 → dist=140 ≥ 40 → factor=1.2. Verify per-frame movement = `SPEED * 1.2 * delta`.
- **TC-B3 — Speed slow when ahead:** Set `_ai_target_y = 380`, paddle at 360 → dist=20 < 40 → factor=0.8. Verify per-frame movement = `SPEED * 0.8 * delta`.
- **TC-B4 — Exact threshold boundary:** Set `_ai_target_y = 400`, paddle at 360 → dist=40 → factor=1.2 (boost at `>=` threshold). Verify boost applied.

### Scenario C: Reaction Delay

- **TC-C1 — Delay blocks target update:** Set `_ai_delay_timer = 0.2`, `_ai_target_y = 300`, ball at y=500 → call `_ai_process(0.016)` → verify `_ai_target_y` still = 300 (not updated to ball.y). Timer decremented to 0.184.
- **TC-C2 — Delay expires, target updates:** Set `_ai_delay_timer = 0.005`, ball at y=500 → call `_ai_process(0.016)` → verify `_ai_delay_timer` becomes a new random positive value AND `_ai_target_y` is updated (within ±20px of ball.y).
- **TC-C3 — Random delay in range:** Run 100 delay-update cycles → collect all `_ai_delay_timer` values after reset → verify all ∈ [0.1, 0.3].

### Scenario D: Position Error

- **TC-D1 — Error within ±20px:** Run 100 target updates with ball at y=360 → collect all `_ai_error_offset` values → verify all ∈ [-20, 20].
- **TC-D2 — Error applied to target:** Ball at y=360 → force `_ai_error_offset = -15` → verify `_ai_target_y = 345` (= 360 + (-15)).

### Scenario E: Boundary Clamping

- **TC-E1 — Top clamp:** Set `_ai_target_y = -500`, paddle at min_y=60 → call `_ai_process(0.016)` → verify `position.y == min_y` (clamped, not negative).
- **TC-E2 — Bottom clamp:** Set `_ai_target_y = 2000`, paddle at max_y=660 → call `_ai_process(0.016)` → verify `position.y == max_y`.
- **TC-E3 — Large delta doesn't escape bounds:** Set `_ai_target_y = -500`, paddle at 360, delta=0.5 → call `_ai_process(0.5)` → verify `position.y >= min_y` (clamp catches even large jumps).

### Scenario F: Graceful Degradation

- **TC-F1 — No ball, no crash:** Set `_ball_node = null`, call `_ai_process(0.016)` → verify no error, `position.y` unchanged.
- **TC-F2 — Headless compilation:** Run `godot --path mini-pong/ --headless --quit` → verify exit code 0, no script errors in output.

### Scenario G: Player Mode Backward Compatibility

- **TC-G1 — Player mode unchanged:** Create paddle with `mode = PLAYER` → verify `_process()` still reads Input actions (existing behavior preserved).
- **TC-G2 — InputMap binding still works:** Paddle in PLAYER mode → `_ready()` still creates `paddle_up`/`paddle_down` InputMap actions.

---

## 9. File Manifest

| File | Type | Action | Est. Lines Changed |
|------|------|--------|-------------------|
| `mini-pong/gdscripts/paddle.gd` | GDScript | **MODIFY** | +52 (63 → ~115) |
| `mini-pong/scenes/game.tscn` | Godot Scene | **MODIFY** | +3 lines (add AIPaddle instance) |

No new files. No files removed.

---

## 10. Verification Checklist

- [ ] **AC1:** AI paddle tracks ball Y position — `_ai_process` reads `_ball_node.global_position.y`
- [ ] **AC2:** 100–300ms random reaction delay — `_ai_delay_timer` uses `randf_range(0.1, 0.3)`, target only updates on expiry
- [ ] **AC3:** ±20px random position error — `_ai_error_offset = randf_range(-20, 20)` applied to target
- [ ] **AC4:** +20% speed when trailing (dist ≥ 40), -20% when ahead (dist < 40) — factor 1.2 vs 0.8
- [ ] **AC5:** Does not exceed screen boundaries — `clamp(position.y, min_y, max_y)` on every frame
- [ ] **AC6:** `--headless --quit` exits 0 with no script errors
- [ ] **Player mode preserved:** Existing `mode == PLAYER` path unchanged — InputMap binding + WASD input still work
- [ ] **`paddles` group registration:** AI paddle calls `add_to_group("paddles")` in `_ready()` — ball collision works
- [ ] **AI parameters are `@export`:** All 6 AI params tunable in editor without code changes
- [ ] **Graceful degradation:** Ball node missing → AI paddle stays still, no crash

---

## 11. Implementation Notes

1. **Enum pattern:** Use `enum Mode { PLAYER = 0, AI = 1 }` — Godot 4.x GDScript 2.0 supports enums at class level
2. **`_process` dispatch:** Check `mode` once per frame at the top of `_process()`, early return for AI path
3. **`_resolve_ball()` resilience:** Two-stage lookup (parent sibling first, scene-tree fallback) handles both `game.tscn` and test environments
4. **InputMap guard in AI mode:** Wrap the InputMap binding block in `if mode == Mode.PLAYER:` to avoid unnecessary InputMap mutations when instantiating AI paddles
5. **TSCN mode override:** Godot 4.x text format supports `mode = 1` property override on instance nodes — this sets the enum value without needing a new scene file
6. **Test mock pattern:** Tests create `Area2D.new()` + `set_script(load("paddle.gd"))` + set `mode` and `_ball_node` manually — same pattern as `test_paddle.gd` and `test_ball.gd`
7. **Position at x=1230:** Mirror of PlayerPaddle at x=50 in 1280-wide viewport. `1230 = 1280 - 50` — ensures symmetric gameplay

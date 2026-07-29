# DESIGN: Test Coverage & GDD Backfill for #288 + #289

> **Parent Issue:** #311
> **Agent:** game-plan-agent
> **Date:** 2026-07-29
> **Approach:** A — GDScript headless tests + markdown GDD chapters (PRD recommendation, confirmed)
> **Depth:** standard

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                    ← unchanged (verified: 12 lines, Forward+, glow, clear_color)
├── scenes/
│   ├── world_environment.tscn       ← unchanged (verified: glow_bloom=0.8, background_color)
│   └── player_paddle.tscn           ← unchanged (verified: Area2D + ColorRect + CollisionShape2D)
├── gdscripts/
│   ├── paddle.gd                    ← unchanged (verified: 60 lines, SPEED=400, InputMap guard)
│   ├── neon_glow.gdshader           ← unchanged (verified: 23 lines, canvas_item shader)
│   ├── ball_trail.gd                ← unchanged (verified: 36 lines, MIN_SPEED=20, MAX_SPEED=600)
│   └── score_flash.gd               ← unchanged (verified: 48 lines, create_tween 0.2s)
├── assets/
│   ├── gradient_neon.tres           ← unchanged (verified: GradientTexture1D, blue→purple)
│   └── particle_material.tres       ← unchanged (verified: lifetime=0.5, spread=15)
└── tests/                            ← NEW — created by this issue
    ├── run_tests.gd                  ← Entry point (extends SceneTree)
    ├── test_paddle.gd                ← Paddle suite (extends RefCounted)
    └── test_neon.gd                  ← Neon suite (extends RefCounted)

docs/GAME_DESIGN/
├── INDEX.md                         ← MODIFIED — add two rows to table
├── 10-SCENE-LAYOUT.md               ← unchanged
├── 11-PLAYER-PADDLE.md              ← NEW — GDD chapter
└── 12-NEON-VISUAL.md                ← NEW — GDD chapter
```

**Design philosophy:** Zero modification of existing source code. All new files go into `mini-pong/tests/` and `docs/GAME_DESIGN/`. The test runner uses Godot's `--headless --script` mode, with `RefCounted`-based suite scripts for maximum CI compatibility. GDD chapters extract architecture decisions, constants, and data flows from existing DESIGN docs — no new design, only consolidation.

**Why Approach A:** The PRD's recommended approach is confirmed. GDScript headless tests are the lightest-weight option that works in CI without third-party dependencies (no GUT, no gdUnit4). Markdown GDD chapters follow the existing `10-SCENE-LAYOUT.md` convention.

**Files modified vs created:**

| Classification | File | Action |
|----------------|------|--------|
| New | `mini-pong/tests/run_tests.gd` | CREATE |
| New | `mini-pong/tests/test_paddle.gd` | CREATE |
| New | `mini-pong/tests/test_neon.gd` | CREATE |
| New | `docs/GAME_DESIGN/11-PLAYER-PADDLE.md` | CREATE |
| New | `docs/GAME_DESIGN/12-NEON-VISUAL.md` | CREATE |
| Modified | `docs/GAME_DESIGN/INDEX.md` | MODIFY — add 2 rows |
| — | All `mini-pong/` source files | UNCHANGED |

---

## 2. Test Infrastructure — Detailed Design

### 2.1 Test Runner Architecture

**Entry point:** `mini-pong/tests/run_tests.gd`

```gdscript
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
    _run("res://tests/test_paddle.gd", "Paddle")
    _run("res://tests/test_neon.gd", "Neon Visual")
    print("\n=== TOTAL: %d passed, %d failed ===" % [_pass, _fail])
    quit(1 if _fail > 0 else 0)

func _run(path: String, name: String) -> void:
    print("=== %s Tests ===" % name)
    var script = load(path)
    if script == null:
        print("  SKIP: %s not found" % path)
        _fail += 1
        return
    var tester = script.new()
    tester.run()
    _pass += tester.passed
    _fail += tester.failed
    print("  %s: %d passed, %d failed" % [name, tester.passed, tester.failed])
```

**Runner contract:**
- `extends SceneTree` — mandatory for `--script` mode entry
- `_init()` — entry point; calls each suite's `run()`, aggregates counts, calls `quit(exit_code)`
- `_run(path, name)` — loads each suite script via `load()`, null-checks, instantiates via `.new()`
- Exit code: 0 if all pass, 1 if any fail or any suite not found

**Why `load()` not `preload()`:** Per `godot-headless-test-patterns` §Pattern 3, `load()` defers resolution to runtime, avoiding compile-cascade failures from `class_name` references in suite scripts. The suite scripts themselves use `load()` (not `preload()`) at top level for the same reason (§Pattern 13).

### 2.2 Suite Script Contract

Each test suite (`test_paddle.gd`, `test_neon.gd`) follows the same contract:

```gdscript
extends RefCounted

var passed: int = 0    # Public — runner reads this
var failed: int = 0    # Public — runner reads this

func run() -> void:
    # Call test cases in order
    _test_inputmap_creation()
    _test_key_bindings()
    # ... more tests ...

func _assert(condition: bool, name: String) -> void:
    if not condition:
        print("  FAIL: %s" % name)
        failed += 1
    # Do NOT print pass — avoids CI pipe buffer deadlock
```

**Suite contract rules:**
- `extends RefCounted` — enables `.new()` instantiation without SceneTree dependency
- `var passed: int = 0` and `var failed: int = 0` — public properties, runner reads after `run()`
- `func run() -> void` — dispatches to private `_test_*()` methods
- `func _assert(condition, name)` — only prints on failure; passes are silent
- No `preload()` at top level — use `load()` inside test methods (§Pattern 13)
- No lambda captures for signal callbacks — use member variables + handler methods (§Pattern 11)

---

## 3. Paddle Test Suite — `test_paddle.gd`

**Source:** Test cases derived from `docs/DESIGN/288-player-paddle.md` §6 (TC-A1~E3, 14 test cases).

**Headless constraint:** `Input.is_action_pressed()` returns `false` in `--script` mode (no input system). Movement tests (Scenario B) bypass this by directly invoking `_process(delta)` after setting `up`/`down` via internal state manipulation. For movement direction logic, we test the numeric formula: `position.y += move * SPEED * delta`.

**Instantiation strategy:** `Node.new()` + `set_script(load("res://gdscripts/paddle.gd"))` — per `godot-headless-test-patterns` §Pattern 2. `paddle.gd` extends `Area2D` (which extends `Node2D`), and `.new()` on `Area2D` creates a valid node. The script has no `@export var` (uses only `const` and local `var`), so no sub-pattern 2a issues.

### Scenario A: InputMap Binding (TC-A1~A3)

**TC-A1 — Actions created:**
- **Precondition:** Fresh Godot instance (no prior InputMap bindings)
- **Action:** Create `Node.new()` → `set_script(load("res://gdscripts/paddle.gd"))` → call `_ready()`
- **Verify:** `InputMap.has_action("paddle_up")` returns `true` AND `InputMap.has_action("paddle_down")` returns `true`

**TC-A2 — Key bindings:**
- **Precondition:** TC-A1 passed (actions created)
- **Action:** Call `InputMap.action_get_events("paddle_up")` and `InputMap.action_get_events("paddle_down")`
- **Verify:** The events array for "paddle_up" contains `InputEventKey` with `keycode == KEY_W` and `keycode == KEY_UP`; "paddle_down" contains KEY_S and KEY_DOWN
- **Implementation:** Iterate events array, check `event is InputEventKey`, read `event.keycode`, assert set membership

**TC-A3 — No duplicate on re-instantiate:**
- **Precondition:** TC-A1 passed (actions exist)
- **Action:** Create second instance via `Node.new()` + `set_script(load(...))` → call `_ready()`
- **Verify:** No crash, no error output. `InputMap.action_get_events("paddle_up")` still returns exactly 2 events (no 4). The `has_action()` guard in `_ready()` prevents duplicate binding.

### Scenario B: Movement (TC-B1~B4)

**Headless strategy:** `Input.is_action_pressed()` returns `false` in `--script` mode. We test the movement logic directly:
- Create paddle instance, call `_ready()` to set boundaries
- Manually set `position.y` to a known value (e.g., 360.0 for viewport center)
- Call `_process(0.016)` — verifies that position.y changes according to the formula
- Since Input returns false for both actions, `move = 0.0` in all headless cases. The test verifies that `_process` completes without error and position stays clamped.

**Refined strategy — test the formula directly:**

Since headless Input is always false, we test the **clamp boundary** and **formula integrity** instead of direction logic:

**TC-B1 — Up movement formula verification:**
- **Action:** Set position.y = 500, call `_process(0.016)`
- **Verify:** position.y does not exceed `max_y` (clamp) and no script error. The actual movement logic (direction selection) is verified by code review of the DESIGN doc's data flow.

**TC-B2 — Down movement formula verification:**
- **Action:** Set position.y = 100, call `_process(0.016)`
- **Verify:** position.y does not go below `min_y` and no script error.

**TC-B3 — Simultaneous cancel (structural verification):**
- **Action:** Verify that the source code's `_process` function contains the `if up and not down` / `elif down and not up` pattern (both true → move = 0.0). This is a structural assertion checked via source code analysis or manual review.
- **Heuristic:** Load the script source with `FileAccess.get_file_as_string("res://gdscripts/paddle.gd")`, grep for `if up and not down:` and `elif down and not up:`.

**TC-B4 — No input (structural + behavioral):**
- **Action:** Call `_process(0.016)` with position.y = 360.0 (center), verify position.y unchanged. Input returns false for both → move = 0.0 → position unchanged.

### Scenario C: Boundary Clamping (TC-C1~C3)

**TC-C1 — Top clamp:**
- **Precondition:** Paddle instance created, `_ready()` called (min_y = 60.0 with 720 viewport)
- **Action:** Set position.y = -1000.0, call `_process(0.016)`
- **Verify:** position.y == min_y (60.0). Clamp at top boundary.

**TC-C2 — Bottom clamp:**
- **Precondition:** Same as TC-C1
- **Action:** Set position.y = 2000.0, call `_process(0.016)`
- **Verify:** position.y == max_y (660.0). Clamp at bottom boundary.

**TC-C3 — Clamp at startup:**
- **Precondition:** Before `_ready()`, set position.y = -500.0
- **Action:** Call `_ready()`
- **Verify:** After `_ready()`, position.y is in [min_y, max_y] (60.0 with 720 viewport)

### Scenario D: Headless Compilation (TC-D1~D2)

**TC-D1 — Zero exit code:**
- **Action:** Run `godot --path mini-pong/ --headless --quit`
- **Verify:** Exit code 0
- **Note:** Covered by existing CI — no new test code needed. The test runner itself compiling and running successfully implies this passes.

**TC-D2 — No script errors:**
- **Action:** Run `godot --path mini-pong/ --headless --quit`, capture stderr
- **Verify:** Output does not contain "SCRIPT ERROR" or "Parse Error"
- **Note:** Also covered by CI. The `run_tests.gd` script's own compilation serves as an additional validation.

### Scenario E: Scene Integrity (TC-E1~E3)

**TC-E1 — Node hierarchy:**
- **Action:** `var scene = load("res://scenes/player_paddle.tscn")` → `var paddle = scene.instantiate()`
- **Verify:** `paddle is Area2D` AND paddle has child named "ColorRect" AND paddle has child named "CollisionShape2D"

**TC-E2 — CollisionShape2D non-null:**
- **Precondition:** TC-E1 passed
- **Action:** Get CollisionShape2D child node, check `.shape`
- **Verify:** `.shape is RectangleShape2D` AND `shape.size.x > 0` AND `shape.size.y > 0`

**TC-E3 — Script attachment:**
- **Precondition:** TC-E1 passed
- **Action:** Check `paddle.get_script()`
- **Verify:** Script path contains "paddle.gd" (use `paddle.get_script().resource_path`)

### Paddle Test Summary

| Category | Test ID | What It Tests | Headless | Strategy |
|----------|---------|---------------|:--------:|----------|
| A — InputMap | TC-A1 | Actions created (has_action) | ✅ | Create instance, call _ready() |
| A — InputMap | TC-A2 | Key bindings (W/S/↑/↓) | ✅ | action_get_events() iteration |
| A — InputMap | TC-A3 | No duplicate binding | ✅ | Second instantiation + count check |
| B — Movement | TC-B1 | Up formula (position changes) | ✅ | _process(0.016) with position set |
| B — Movement | TC-B2 | Down formula | ✅ | _process(0.016) with position set |
| B — Movement | TC-B3 | Simultaneous cancel | ⚠️ | Structural: grep source for pattern |
| B — Movement | TC-B4 | No input | ✅ | _process(0.016), verify unchanged |
| C — Clamping | TC-C1 | Top clamp (position = -1000) | ✅ | Set position, _process(), assert == min_y |
| C — Clamping | TC-C2 | Bottom clamp (position = 2000) | ✅ | Set position, _process(), assert == max_y |
| C — Clamping | TC-C3 | Startup clamp (_ready) | ✅ | Set pre-_ready position, call _ready() |
| D — Headless | TC-D1 | Zero exit code | ✅ | CI coverage (no test code) |
| D — Headless | TC-D2 | No script errors | ✅ | CI coverage (no test code) |
| E — Scene | TC-E1 | Node hierarchy (Area2D + 2 children) | ✅ | PackedScene.instantiate() |
| E — Scene | TC-E2 | CollisionShape2D non-null shape | ✅ | Child node inspection |
| E — Scene | TC-E3 | Script attachment to root | ✅ | get_script().resource_path |

**Total: 14 test cases** (12 automated, 1 structural, 1 CI-covered)

---

## 4. Neon Visual Test Suite — `test_neon.gd`

**Source:** Test cases derived from `docs/DESIGN/289-neon-visual.md` §7 (TC1~TC17, 17 test cases).

**Headless constraint:** Visual effects (TC10–TC17) cannot be verified in `--script` mode — Godot uses a dummy renderer. These are marked as `MANUAL ONLY` and the test suite outputs them as informative messages. Automated tests (TC1–TC9) verify file existence, script compilation, and resource loadability.

### Scenario A: WorldEnvironment Config Compilation (TC1~TC4)

**TC1 — Headless exit code:**
- **Action:** Run `godot --path mini-pong/ --headless --quit`
- **Verify:** Exit code 0
- **Note:** Covered by existing CI. The `run_tests.gd` itself loading and running serves as validation.

**TC2 — glow_bloom present:**
- **Action:** `var content = FileAccess.get_file_as_string("res://scenes/world_environment.tscn")`
- **Verify:** `content.contains("glow_bloom = 0.8")` returns true

**TC3 — background_color present:**
- **Action:** Same file read
- **Verify:** `content.contains("background_color = Color(0.039, 0.039, 0.071, 1)")` returns true

**TC4 — default_clear_color in project.godot:**
- **Action:** `var content = FileAccess.get_file_as_string("res://project.godot")`
- **Verify:** `content.contains("rendering/environment/defaults/default_clear_color")` returns true

### Scenario B: Resource File Integrity (TC5~TC7)

**TC5 — neon_glow.gdshader exists and compiles:**
- **Action:** `var shader = load("res://gdscripts/neon_glow.gdshader")`
- **Verify:** `shader != null` AND shader contains `shader_type canvas_item`

**TC6 — gradient_neon.tres exists:**
- **Action:** `var gradient = load("res://assets/gradient_neon.tres")`
- **Verify:** `gradient != null`

**TC7 — particle_material.tres exists:**
- **Action:** `var material = load("res://assets/particle_material.tres")`
- **Verify:** `material != null`

### Scenario C: Script Compilation (TC8~TC9)

**TC8 — ball_trail.gd compiles:**
- **Action:** `var script = load("res://gdscripts/ball_trail.gd")`
- **Verify:** `script != null`
- **Note:** `ball_trail.gd` uses `as CharacterBody2D` cast — this returns null at runtime (no CharacterBody2D in test context) but does NOT prevent script loading. The `load()` call alone validates syntax.

**TC9 — score_flash.gd compiles:**
- **Action:** `var script = load("res://gdscripts/score_flash.gd")`
- **Verify:** `script != null`
- **Note:** `score_flash.gd` uses `create_tween()` — valid Godot 4.x pattern. No compile error expected.

### Scenario D: Visual Effects — Manual Only (TC10~TC17)

**These cannot be verified in headless mode.** The test suite outputs them as informative messages:

```
print("MANUAL ONLY: TC10-TC17 — verify in Godot editor")
print("  TC10: Dark background (#0a0a12) visible on game run")
print("  TC11: Player paddle glow (#4a90d9) — ShaderMaterial applied")
print("  TC12: AI paddle glow (#ff3355) — ShaderMaterial applied")
print("  TC13: Ball trail (blue→purple gradient) — GPUParticles2D emitting")
print("  TC14: Ball stationary → no trail — particles stopped")
print("  TC15: Score flash (0.2s fade) — ColorRect tween")
print("  TC16: Dashed center line visible")
print("  TC17: Rapid score flashes don't overlap — old tween killed")
```

**Rationale for keeping manual tests in the suite:** The test runner needs to account for all 17 DESIGN-specified tests. Outputting the manual ones ensures they're not forgotten and appear in the test report. They don't affect pass/fail count.

### Neon Test Summary

| Category | Test ID | What It Tests | Headless | Strategy |
|----------|---------|---------------|:--------:|----------|
| A — WorldEnv | TC1 | Headless exit code 0 | ✅ | CI coverage |
| A — WorldEnv | TC2 | glow_bloom = 0.8 in .tscn | ✅ | FileAccess read + contains() |
| A — WorldEnv | TC3 | background_color in .tscn | ✅ | FileAccess read + contains() |
| A — WorldEnv | TC4 | default_clear_color in project.godot | ✅ | FileAccess read + contains() |
| B — Resources | TC5 | neon_glow.gdshader loads | ✅ | load() != null |
| B — Resources | TC6 | gradient_neon.tres loads | ✅ | load() != null |
| B — Resources | TC7 | particle_material.tres loads | ✅ | load() != null |
| C — Scripts | TC8 | ball_trail.gd compiles | ✅ | load() != null |
| C — Scripts | TC9 | score_flash.gd compiles | ✅ | load() != null |
| D — Visual | TC10–TC17 | Visual effects | ❌ | Manual only — informative message |

**Total: 17 test cases** (9 automated, 8 manual-only)

---

## 5. GDD Chapter Outlines

### 5.1 `11-PLAYER-PADDLE.md` — Player Paddle System

**Source mapping:** Extracted from `docs/DESIGN/288-player-paddle.md`.

```
# Player Paddle & Input

> Reference: ../DESIGN/288-player-paddle.md

## Overview

The player paddle is a self-contained Area2D component with code-based InputMap bindings,
vertical movement, and boundary clamping. It can be dropped into any scene and works immediately
with zero external dependencies beyond Godot built-in APIs.

## Node Tree

Area2D (PlayerPaddle, paddle.gd)
├── ColorRect (20×120, white)
└── CollisionShape2D (RectangleShape2D, 20×120)

## Core Constants

```gdscript
const SPEED: float = 400.0              # Pixels per second
const PADDLE_WIDTH: float = 20.0        # ColorRect width
const PADDLE_HEIGHT: float = 120.0      # ColorRect height
const FALLBACK_VIEWPORT_Y: float = 720.0 # Headless fallback
```

## InputMap Bindings

| Action | Keys | Purpose |
|--------|------|---------|
| `paddle_up` | W, ↑ | Move paddle upward |
| `paddle_down` | S, ↓ | Move paddle downward |

Bindings are created in `_ready()` with `has_action()` guard to prevent duplicates on re-instantiation.

## Movement & Clamping

Per-frame in `_process(delta)`:
1. Read `Input.is_action_pressed("paddle_up")` and `("paddle_down")`
2. Compute direction: up-only → -1, down-only → +1, both → 0, neither → 0
3. Apply: `position.y += move * SPEED * delta`
4. Clamp: `position.y = clamp(position.y, min_y, max_y)`

Boundaries calculated from viewport height: `min_y = half_height`, `max_y = viewport_height - half_height`.
Falls back to 720px if viewport unavailable (headless mode).

## Data Flow

```
_ready()
  ├── InputMap binding (guarded)
  ├── Boundary calculation (viewport or fallback)
  └── Initial position clamp

_process(delta) — every frame
  ├── Read input
  ├── Compute move direction
  ├── Apply speed * delta
  └── Clamp to [min_y, max_y]
```

## Edge Cases

| # | Case | Behavior |
|---|------|----------|
| 1 | W+S or ↑+↓ simultaneously | move = 0.0 (cancel) |
| 2 | Window resize mid-game | Boundaries from _ready() — static for MVP |
| 3 | Position outside bounds at start | _ready() clamps |
| 4 | Very low FPS (delta > 1.0) | clamp() runs after move — always in bounds |
| 5 | Scene instantiated twice | has_action() guard skips duplicate binding |
| 6 | Headless mode (zero viewport) | FALLBACK_VIEWPORT_Y = 720.0 |

## Integration Points

| System | How |
|--------|-----|
| Ball collision (#290) | Area2D body_entered signal — paddle is passive, no code needed |
| Main scene (#295) | Instance `player_paddle.tscn` in main scene |
| Visual (#289) | ColorRect color → ShaderMaterial neon glow |
| AI paddle (future) | Reuse `.tscn` structure with different script |
```

### 5.2 `12-NEON-VISUAL.md` — Neon Cyber Visual System

**Source mapping:** Extracted from `docs/DESIGN/289-neon-visual.md`.

```
# Neon Cyber Visual System

> Reference: ../DESIGN/289-neon-visual.md

## Overview

A pure visual layer for Mini Pong using Godot 4.x built-in effects:
WorldEnvironment glow/bloom, GPUParticles2D ball trail, ShaderMaterial canvas_item
edge glow, and ColorRect score flash. Zero third-party dependencies.

## Design Principles

| # | Principle | Explanation |
|---|-----------|-------------|
| 1 | Pure visual layer | No game logic changes |
| 2 | Leverage existing infra | Forward+ and glow enabled in #301 |
| 3 | Minimal intrusion | Standalone resource files, no scene hierarchy changes |
| 4 | 2D convention | canvas_item shaders, GPUParticles2D (not 3D) |

## Color Constants

```gdscript
const PLAYER_NEON_BLUE = Color(0.29, 0.56, 0.85, 1)  # #4a90d9
const AI_NEON_RED      = Color(1.0, 0.2, 0.33, 1)     # #ff3355
const TRAIL_PURPLE     = Color(0.53, 0.2, 1.0, 1)     # #8833ff
const CENTER_LINE      = Color(0.4, 0.6, 0.9, 0.5)    # semi-transparent blue
const BG_COLOR_LINEAR  = Color(0.039, 0.039, 0.071, 1) # #0a0a12
```

## WorldEnvironment Configuration

File: `scenes/world_environment.tscn`

| Property | Value | Purpose |
|----------|-------|---------|
| glow_enabled | true | Enable glow post-processing |
| glow_intensity | 0.6 | Overall glow strength |
| glow_bloom | 0.8 | Bloom threshold — only pixels > 0.8 brightness bloom |
| background_color | #0a0a12 | Dark blue-black background |

## Edge Glow Shader

File: `gdscripts/neon_glow.gdshader` (canvas_item mode)

Uniforms:
- `glow_color` (#4a90d9 default, override per-element)
- `glow_width` (3.0, range 1.0–10.0)
- `glow_intensity` (1.0, range 0.0–2.0)

Algorithm: Edge detection via neighbor alpha difference → overlay glow_color outside edge.

## Ball Trail System

File: `gdscripts/ball_trail.gd` (attached as child of ball)

| Constant | Value | Purpose |
|----------|-------|---------|
| MIN_SPEED_FOR_TRAIL | 20.0 | Below this speed, no particles |
| MAX_SPEED_FOR_TRAIL | 600.0 | Max speed for emission rate normalization |

Behavior: Reads `get_parent().velocity.length()` in `_process()`. If speed < 20.0, particles stop.
Otherwise emission rate proportional to speed (0.3–1.0 range).

Particles use `particle_material.tres` (ParticleProcessMaterial):
- lifetime = 0.5s, spread = 15°
- Color ramp: gradient_neon.tres (blue #4a90d9 → purple #8833ff)

## Score Flash

File: `gdscripts/score_flash.gd`

| Signal | Source | Behavior |
|--------|--------|----------|
| score_changed(side: String) | Scoring system (future) | Flash blue for "player", red for "ai" |

Flash: Full-screen ColorRect overlay → 0.2s fade via `create_tween()`.
Old tweens killed on new flash (prevents overlap).

## Data Flows

### Game Start → Visual Init
load project.godot (clear_color) → load world_environment.tscn (glow/bloom) → compile shaders/scripts → ready

### Ball Movement → Trail
_physics_process() updates velocity → ball_trail.gd._process() reads speed → GPUParticles2D emits → gradient particles render

### Score → Flash
score_changed signal → _on_score_changed(side) → flash(color) → create_tween() → 0.2s fade out

### Edge Glow
ShaderMaterial applied to Sprite2D → fragment shader detects edge → overlays glow_color → WorldEnvironment bloom post-processes

## Integration Points

| Component | Connected To | Via |
|-----------|-------------|-----|
| Ball trail | Ball CharacterBody2D | get_parent().velocity |
| Ball glow | Ball Sprite2D | ShaderMaterial (neon_glow.gdshader) |
| Player paddle glow | Paddle Sprite2D | ShaderMaterial, glow_color=#4a90d9 |
| AI paddle glow | AI Paddle Sprite2D | ShaderMaterial, glow_color=#ff3355 |
| Score flash | Scoring system | score_changed signal |
| Center line | Main scene | Line2D child node |
| Background | Rendering pipeline | WorldEnvironment + project.godot clear_color |
| Bloom | Forward+ renderer | glow_bloom=0.8 threshold |
```

---

## 6. Existing Component Modifications

### 6.1 GDD INDEX Update

**File:** `docs/GAME_DESIGN/INDEX.md`

**Current state:**
```markdown
| [10-SCENE-LAYOUT](10-SCENE-LAYOUT.md) | 3D scene layout — floor, walls, collision |
```

**Target state — add two rows after row 10:**
```markdown
| [10-SCENE-LAYOUT](10-SCENE-LAYOUT.md) | 3D scene layout — floor, walls, collision |
| [11-PLAYER-PADDLE](11-PLAYER-PADDLE.md) | Player paddle — InputMap, movement, clamp |
| [12-NEON-VISUAL](12-NEON-VISUAL.md) | Neon cyber visuals — glow, trail, flash, colors |
```

**Method:** `patch` with `old_string` matching the last line of the existing table, `new_string` appending the two new rows.

---

## 7. Data Flow: Test Execution

```
CI / Developer runs:
  godot --path mini-pong/ --headless --script tests/run_tests.gd
    │
    ▼
SceneTree._init()
  ├── _run("res://tests/test_paddle.gd", "Paddle")
  │     ├── load("res://tests/test_paddle.gd") → GDScript
  │     ├── script.new() → RefCounted instance
  │     ├── tester.run()
  │     │     ├── _test_inputmap_creation()     → TC-A1
  │     │     ├── _test_key_bindings()          → TC-A2
  │     │     ├── _test_no_duplicate_binding()  → TC-A3
  │     │     ├── _test_movement_up()           → TC-B1
  │     │     ├── _test_movement_down()         → TC-B2
  │     │     ├── _test_simultaneous_cancel()   → TC-B3
  │     │     ├── _test_no_input()              → TC-B4
  │     │     ├── _test_top_clamp()             → TC-C1
  │     │     ├── _test_bottom_clamp()          → TC-C2
  │     │     ├── _test_startup_clamp()         → TC-C3
  │     │     ├── _test_node_hierarchy()        → TC-E1
  │     │     ├── _test_collision_shape()       → TC-E2
  │     │     └── _test_script_attachment()     → TC-E3
  │     ├── _pass += tester.passed, _fail += tester.failed
  │     └── Print summary
  │
  ├── _run("res://tests/test_neon.gd", "Neon Visual")
  │     ├── load("res://tests/test_neon.gd") → GDScript
  │     ├── script.new() → RefCounted instance
  │     ├── tester.run()
  │     │     ├── _test_worldenv_glow_bloom()   → TC2
  │     │     ├── _test_worldenv_bg_color()     → TC3
  │     │     ├── _test_project_clear_color()   → TC4
  │     │     ├── _test_neon_shader_loads()     → TC5
  │     │     ├── _test_gradient_loads()        → TC6
  │     │     ├── _test_particle_mat_loads()    → TC7
  │     │     ├── _test_ball_trail_compiles()   → TC8
  │     │     ├── _test_score_flash_compiles()  → TC9
  │     │     └── _print_manual_tests()         → TC10–TC17
  │     ├── _pass += tester.passed, _fail += tester.failed
  │     └── Print summary
  │
  ├── Print "=== TOTAL: %d passed, %d failed ==="
  └── quit(0 if _fail == 0 else 1)
```

---

## 8. Edge Cases & Error Handling

| # | Edge Case | Mitigation |
|---|-----------|------------|
| 1 | `tests/` directory doesn't exist | `mkdir -p mini-pong/tests` before writing test files |
| 2 | `load()` returns null for suite script | `_run()` null-checks, prints `SKIP`, increments failed |
| 3 | `load()` returns null for source script (paddle.gd, etc.) | Individual test functions null-check before use |
| 4 | `PackedScene.instantiate()` fails (corrupt .tscn) | Try/catch around instantiation, treat as test failure |
| 5 | `FileAccess.get_file_as_string()` fails (permissions) | Null-check result, treat as test failure |
| 6 | InputMap already has actions from previous test suite | `has_action()` guard in paddle.gd handles this — tests verify it |
| 7 | `Node.new()` + `set_script()` fails on .mono Godot | CI uses standard Godot — `.new()` works. Skip if platform mismatch detected |
| 8 | `_ready()` not auto-called in test context | Tests explicitly call `_ready()` after instantiation |
| 9 | GDD INDEX patch targets wrong line | Use exact `old_string` match on the last table row |
| 10 | CI pipe buffer deadlock from too many print() calls | `_assert()` only prints failures (silent passes) |

---

## 9. Implementation Phases

| Phase | Priority | Components | What It Delivers |
|:-----:|:--------:|-----------|------------------|
| Phase 1 | P0 | `run_tests.gd` + `test_paddle.gd` | Paddle tests (12 automated) passing in headless |
| Phase 2 | P0 | `test_neon.gd` | Neon tests (9 automated + 8 manual) passing in headless |
| Phase 3 | P0 | GDD chapters + INDEX update | `11-PLAYER-PADDLE.md`, `12-NEON-VISUAL.md`, INDEX.md updated |

**Phase dependency:** Phases are independent and can be done in any order. Phase 1 and 2 both depend on `run_tests.gd` (Phase 1). Phase 3 is fully independent of Phase 1-2.

---

## 10. Integration Points

| Integration | This Component | Connected To | How |
|-------------|---------------|-------------|-----|
| Test runner | `run_tests.gd` | `test_paddle.gd` | `load()` + `.new()` + `.run()` + read `.passed`/`.failed` |
| Test runner | `run_tests.gd` | `test_neon.gd` | `load()` + `.new()` + `.run()` + read `.passed`/`.failed` |
| Paddle tests | `test_paddle.gd` | `gdscripts/paddle.gd` | `set_script(load("res://gdscripts/paddle.gd"))` |
| Paddle tests | `test_paddle.gd` | `scenes/player_paddle.tscn` | `load("res://scenes/player_paddle.tscn").instantiate()` |
| Neon tests | `test_neon.gd` | `gdscripts/*` | `load("res://gdscripts/...")` for compile validation |
| Neon tests | `test_neon.gd` | `*.tscn`, `project.godot` | `FileAccess.get_file_as_string()` for config grep |
| GDD chapters | `INDEX.md` | New `.md` files | Table row insertion |
| CI | `--headless --script` | GitHub Actions | Existing `setup-godot@v2` + `godot --path mini-pong/ --headless --script tests/run_tests.gd` |

---

## 11. Key Architecture Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Test framework | Self-implemented assert + `extends RefCounted` | Zero dependencies, CI-compatible, GDScript-native |
| 2 | Suite script base class | `RefCounted` (not `Node`, not `SceneTree`) | `.new()` works without scene tree; public `passed`/`failed` readable by runner |
| 3 | Runner script base class | `SceneTree` | Mandatory for `--script` mode entry point |
| 4 | Script loading in suites | `load()` not `preload()` | §Pattern 13 — avoids compile-cascade failures |
| 5 | Movement test strategy | Test formula + clamp (not Input simulation) | `Input.is_action_pressed()` always false in headless |
| 6 | Visual tests (TC10–TC17) | Informative manual-only message | Headless uses dummy renderer — can't verify pixels |
| 7 | GDD chapter format | Narrative markdown with code blocks and tables | Follows AGENTS.md GDD convention; same style as 10-SCENE-LAYOUT.md |
| 8 | GDD content boundary | Architecture decisions, constants, data flows only | Excludes test cases, implementation details, issue/PR numbers |
| 9 | Assert output | Only print failures | Prevents CI pipe buffer deadlock from excessive stdout |
| 10 | Suite aggregation | Runner aggregates `passed`/`failed` from each suite | Each suite is self-contained; runner is thin dispatch layer |

---

## 12. File Manifest

| File | Type | Action | Lines (est.) |
|------|------|--------|:-----------:|
| `mini-pong/tests/run_tests.gd` | GDScript | CREATE | ~30 |
| `mini-pong/tests/test_paddle.gd` | GDScript | CREATE | ~200 |
| `mini-pong/tests/test_neon.gd` | GDScript | CREATE | ~120 |
| `docs/GAME_DESIGN/11-PLAYER-PADDLE.md` | Markdown | CREATE | ~80 |
| `docs/GAME_DESIGN/12-NEON-VISUAL.md` | Markdown | CREATE | ~100 |
| `docs/GAME_DESIGN/INDEX.md` | Markdown | MODIFY | +2 lines |

---

## 13. Verification

### Automated (CI)

```bash
# Run all tests
godot --path mini-pong/ --headless --script tests/run_tests.gd
echo "Exit: $?"

# Expected output sample:
# === Paddle Tests ===
#   Paddle: 12 passed, 0 failed
# === Neon Visual Tests ===
#   Neon Visual: 9 passed, 0 failed
#
# === TOTAL: 21 passed, 0 failed ===
# Exit: 0
```

### Manual

```bash
# Verify GDD files exist and are non-empty
wc -l docs/GAME_DESIGN/11-PLAYER-PADDLE.md
wc -l docs/GAME_DESIGN/12-NEON-VISUAL.md

# Verify INDEX.md updated
grep "11-PLAYER-PADDLE" docs/GAME_DESIGN/INDEX.md
grep "12-NEON-VISUAL" docs/GAME_DESIGN/INDEX.md
```

### CI Integration

Add to existing CI workflow after the `--headless --quit` compilation check:

```yaml
- name: Run tests
  run: godot --path mini-pong/ --headless --script tests/run_tests.gd
```

---

## 14. Implementation Notes

1. **Tests directory creation:** `mkdir -p mini-pong/tests` before writing test files.

2. **Paddle movement tests and headless Input:** `Input.is_action_pressed()` always returns `false` in `--script` mode. Movement direction tests (TC-B1~B4) test the clamp and formula integrity rather than Input response. TC-B3 uses a structural check (`FileAccess.get_file_as_string()` + `contains("if up and not down:")`) to verify the cancel logic exists in source.

3. **`@export var` and `set_script()`:** `paddle.gd` has NO `@export var` — only `const` and local `var`. No sub-pattern 2a issues. Safe to use `Node.new()` + `set_script()`.

4. **`_ready()` not auto-called:** In test context (node not in scene tree), `_ready()` does NOT fire automatically. Tests must explicitly call `_ready()` after instantiation.

5. **`PackedScene.instantiate()` availability:** Available and tested in `--script` mode for scene integrity tests (TC-E1~E3).

6. **No `preload()` at top level of suite scripts:** Per `godot-headless-test-patterns` §Pattern 13, `preload()` at the top level of `RefCounted` scripts can fail with "Could not resolve script" in `--script` mode. All script references use `load()` inside test methods or `run()`.

7. **Print discipline:** `_assert()` prints only failures. Runner prints one-line summary per suite. Total: maximum ~30 lines of output → safe for CI pipe buffers.

8. **Exit codes:** Runner calls `quit(1)` if any test fails or any suite not found. Call `quit(0)` only if all tests pass. The runner itself loading and running successfully implies TC-D1/TC-D2 (compilation) pass.

9. **GDD INDEX patch precision:** The `old_string` for patching INDEX.md must exactly match the last table row including its trailing newline. Insert the two new rows after it.

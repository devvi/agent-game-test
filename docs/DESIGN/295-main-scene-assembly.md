# Design: [Integration] 主场景组装 — Main Scene Assembly

> **Parent Issue:** #295
> **Agent:** plan agent (game-plan-agent)
> **Date:** 2026-07-30
> **Approach:** A — Incremental Fix (PRD recommendation, confirmed)
> **Reference PRD:** docs/PRD/295-main-scene-assembly.md
> **Reference Design:** docs/DESIGN/287–294

---

## 1. Architecture Overview

**Core idea:** Incrementally add 4 missing nodes (WorldEnvironment, ScoreZoneLeft, ScoreZoneRight, ScoreFlash) to the existing `game.tscn`, rename to `Main.tscn`, extract duplicated constants into a single `constants.gd`, and update all hardcoded `game.tscn` path references. No new game logic — pure assembly/glue.

```
                             Main.tscn (was game.tscn)
┌────────────────────────────────────────────────────────────────────┐
│                                                                    │
│  WorldEnvironment ◄── NEW: instanced from world_environment.tscn   │
│  ├─ glow_intensity=0.6, glow_bloom=0.8, bg_color=(10,10,18)       │
│                                                                    │
│  ┌─ Walls (StaticBody2D, groups=["walls"]) ──────────────────────┐ │
│  │  TopWall: pos(640,5), rect 1280×10                           │ │
│  │  BottomWall: pos(640,715), rect 1280×10                      │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ┌─ Score Zones ◄── NEW ────────────────────────────────────────┐ │
│  │  ScoreZoneLeft: pos(0,360), rect 20×720  → body_entered(1)   │ │
│  │  ScoreZoneRight: pos(1280,360), rect 20×720 → body_entered(0)│ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  Ball (instance of ball.tscn)        → ball.gd: score signal       │
│  PlayerPaddle (instance, mode=PLAYER) → paddle.gd: Mode.PLAYER     │
│  AIPaddle (instance, mode=AI)         → paddle.gd: Mode.AI         │
│                                                                    │
│  ScoringManager (Node, scoring_manager.gd)                         │
│  ├── consumes ball.score signal                                    │
│  ├── emits scored → GameStateMachine, ScoreFlash                   │
│  └── calls GameManager.add_score()                                 │
│                                                                    │
│  ScoreFlash ◄── NEW: Node + child ColorRect, score_flash.gd        │
│  ├── ColorRect[ScoreFlashRect] 1280×720, modulate.a=0.0           │
│  └── connected: ScoringManager.scored → _on_score_changed()        │
│                                                                    │
│  GameStateMachine (Node, game_state_machine.gd)                     │
│  └── NodePath→ StartMenu,GameHUD,GameOverScreen,Ball,Paddles,SM   │
│                                                                    │
│  CanvasLayer UI (inline node trees)                                │
│  ├── StartMenu (layer=1)                                           │
│  ├── GameHUD (layer=0)                                             │
│  └── GameOverScreen (layer=1)                                      │
│                                                                    │
│  GameManager ◄── autoload singleton (not in scene tree)            │
└────────────────────────────────────────────────────────────────────┘

            ┌──────────────┐
            │ constants.gd │  ◄── NEW: extracted from ball/paddle/scoring/game_manager
            │ class_name   │
            │ GameConstants│
            └──────────────┘
```

### Key Architectural Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Rename strategy | Copy `game.tscn` → `Main.tscn`, then delete `game.tscn` | Safer than `git mv` — preserves ext_resource IDs; enables fallback if Main.tscn breaks |
| 2 | ScoreZone collision | Area2D `body_entered` signal connected to ball | Explicit, editor-visible, clean separation: ball moves, zone detects score |
| 3 | Dual-trigger prevention | `_scored_this_frame` bool flag in ball.gd | Prevents same-frame double-score from both `_process` X-boundary and ScoreZone Area2D |
| 4 | Constants file | `class_name GameConstants` in `gdscripts/constants.gd` | Single source of truth; scripts reference via `GameConstants.POINTS_TO_WIN_GAME` |
| 5 | WorldEnvironment | `instance` of `world_environment.tscn` via ext_resource | Reuses existing .tscn; no inline environment duplication |
| 6 | ScoreFlash | New Node with script `score_flash.gd` + child ColorRect | Reuses existing 48-line script; duck-typing connection already in scoring_manager.gd:46 |
| 7 | CanvasLayer UI | Keep inline node trees (not ext_resource instances) | Consistent with #292 design — UI nodes are scene-specific, not shared across scenes |
| 8 | Ext_resource ID ordering | Reorder `[ext_resource …]` lines: existing refs (1–7) then new (8–10) | Maintains backward compatibility; Godot TSCN parser tolerant of gaps |

---

## 2. New Files

### 2.1 `mini-pong/scenes/Main.tscn`

- **Type:** Godot Scene (gd_scene format=3)
- **Source:** Derivative of `game.tscn` (140 lines → ~165 lines)
- **New node type:** Node2D root ("Game")

**Added nodes (not in game.tscn):**

```
[node name="WorldEnvironment" parent="." instance=ExtResource("8_world_env")]
[node name="ScoreZoneLeft" type="Area2D" parent="."]
position = Vector2(0, 360)
  └── [node name="CollisionShape2D" type="CollisionShape2D"]
      shape: RectangleShape2D, size = (20, 720)

[node name="ScoreZoneRight" type="Area2D" parent="."]
position = Vector2(1280, 360)
  └── [node name="CollisionShape2D" type="CollisionShape2D"]
      shape: RectangleShape2D, size = (20, 720)

[node name="ScoreFlash" type="Node" parent="."]
script = ExtResource("10_score_flash")
  └── [node name="ScoreFlashRect" type="ColorRect"]
      layout: full rect (1280×720)
      color: Color(1,1,1,1), modulate.a=0.0
```

**New ext_resource entries (appended):**

```
[ext_resource type="PackedScene" path="res://scenes/world_environment.tscn" id="8_world_env"]
[ext_resource type="Script" path="res://gdscripts/score_flash.gd" id="10_score_flash"]
```

**ScoreZone signal connection** (in ball.gd `_ready()`, not in TSCN):
```gdscript
# ScoreZone body_entered → score emission
if has_node("../ScoreZoneLeft"):
    var zone = $"../ScoreZoneLeft"
    zone.body_entered.connect(func(body): _on_score_zone(body, 1))
if has_node("../ScoreZoneRight"):
    var zone = $"../ScoreZoneRight"
    zone.body_entered.connect(func(body): _on_score_zone(body, 0))
```

### 2.2 `mini-pong/gdscripts/constants.gd`

- **Type:** GDScript (class_name)
- **Line estimate:** ~55 lines

```gdscript
extends RefCounted
## Global constants for Mini Pong — single source of truth.
## Imported by ball.gd, paddle.gd, scoring_manager.gd, game_manager.gd.

class_name GameConstants

# ── Screen ──
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720

# ── Ball Physics ──
const BALL_INITIAL_SPEED: float = 300.0
const BALL_MAX_SPEED_MULTIPLIER: float = 2.0
const BALL_SPEED_INCREMENT: float = 1.05
const BALL_MAX_BOUNCE_ANGLE: float = 60.0
const BALL_SERVE_ANGLE_RANGE: float = 45.0
const BALL_RADIUS: float = 10.0

# ── Paddle ──
const PADDLE_SPEED: float = 400.0
const PADDLE_WIDTH: float = 20.0
const PADDLE_HEIGHT: float = 120.0

# ── AI ──
const AI_REACTION_DELAY_MIN: float = 0.1
const AI_REACTION_DELAY_MAX: float = 0.3
const AI_POSITION_ERROR: float = 20.0
const AI_SPEED_BOOST: float = 1.2
const AI_SPEED_SLOW: float = 0.8

# ── Scoring ──
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

# ── Colors ──
const PLAYER_NEON_BLUE: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const AI_NEON_RED: Color = Color(1.0, 0.2, 0.33, 1.0)            # #ff3355
const BG_COLOR: Color = Color(0.039, 0.039, 0.071, 1.0)          # #0a0a12
```

**Design Note — class_name vs preload:** The PRD §7 (§5 in PRD) identifies a headless-mode risk: `class_name GameConstants` may not be available if the script isn't in the parse order. Fallback: if headless tests fail with `GameConstants` undefined, switch to `const` script (no class_name) + `preload("res://gdscripts/constants.gd")` in each consumer. The DESIGN specifies `class_name` as the primary approach with the fallback documented for the implement agent.

---

## 3. Modified Files

### 3.1 Engine Layer

| File | Change | Est. Δ |
|------|--------|--------|
| `mini-pong/project.godot` | `run/main_scene` path: `game.tscn` → `Main.tscn` | ±1 line |

**Before:**
```
run/main_scene="res://scenes/game.tscn"
```
**After:**
```
run/main_scene="res://scenes/Main.tscn"
```

### 3.2 Scene Layer

| File | Change | Est. Δ |
|------|--------|--------|
| `mini-pong/scenes/game.tscn` | **DELETE** — replaced by `Main.tscn` | −140 lines |
| `mini-pong/scenes/Main.tscn` | **CREATE** — see §2.1 | +~165 lines |

### 3.3 Script Layer

| File | Change | Est. Δ |
|------|--------|--------|
| `mini-pong/gdscripts/ball.gd` | Add `GameConstants` import; replace local `const` with `GameConstants.*` refs (non-destructive: keep local const aliases); add ScoreZone `body_entered` connection in `_ready()`; add `_scored_this_frame` flag for dual-trigger prevention | +~25 |
| `mini-pong/gdscripts/paddle.gd` | Replace local `const SPEED`, `PADDLE_WIDTH`, `PADDLE_HEIGHT` with `GameConstants.*` refs (keep local const aliases) | ±4 |
| `mini-pong/gdscripts/scoring_manager.gd` | Replace `const POINTS_TO_WIN_GAME` and `GAMES_TO_WIN_MATCH` with `GameConstants.*` refs | ±2 |
| `mini-pong/gdscripts/game_manager.gd` | Replace `const POINTS_TO_WIN_GAME` and `GAMES_TO_WIN_MATCH` with `GameConstants.*` refs | ±2 |
| `mini-pong/gdscripts/game_state_machine.gd` | Update comments: `game.tscn` → `Main.tscn` (lines 23, 194) | ±2 |

#### 3.3.1 ball.gd — Detailed Changes

**ScoreZone collision detection (NEW):**

```gdscript
# ── Score Zone collision (added to _ready()) ──
var _scored_this_frame: bool = false

func _ready() -> void:
    # ... existing _ready() code ...

    # Connect ScoreZone Area2D body_entered signals
    var parent := get_parent()
    if parent:
        var zone_left := parent.get_node_or_null("ScoreZoneLeft")
        if zone_left and zone_left is Area2D:
            zone_left.body_entered.connect(func(_b): _on_score_zone(1))
        var zone_right := parent.get_node_or_null("ScoreZoneRight")
        if zone_right and zone_right is Area2D:
            zone_right.body_entered.connect(func(_b): _on_score_zone(0))

func _on_score_zone(side: int) -> void:
    if _scored_this_frame:
        return
    _scored_this_frame = true
    score.emit(side)
    serve()

func _process(delta: float) -> void:
    # ... existing guards ...

    _scored_this_frame = false  # Reset flag at start of each frame

    # X boundary — scoring (keep as fallback)
    if position.x < -BALL_RADIUS:
        if not _scored_this_frame:
            score.emit(1)
            serve()
    elif position.x > screen_width + BALL_RADIUS:
        if not _scored_this_frame:
            score.emit(0)
            serve()
```

**Constants migration (non-destructive — keep local const aliases):**
```gdscript
# After import at top:
const CONSTS = preload("res://gdscripts/constants.gd")

# Replace inline values with references:
const INITIAL_SPEED: float = CONSTS.BALL_INITIAL_SPEED
const MAX_SPEED_MULTIPLIER: float = CONSTS.BALL_MAX_SPEED_MULTIPLIER
# ... etc for all ball constants
```

#### 3.3.2 paddle.gd — Constants Migration

```gdscript
const CONSTS = preload("res://gdscripts/constants.gd")

const SPEED: float = CONSTS.PADDLE_SPEED
const PADDLE_WIDTH: float = CONSTS.PADDLE_WIDTH
const PADDLE_HEIGHT: float = CONSTS.PADDLE_HEIGHT
```

AI defaults kept as `@export var` (tunable in editor) with initial values from `CONSTS`:
```gdscript
@export var ai_reaction_delay_min: float = CONSTS.AI_REACTION_DELAY_MIN
@export var ai_reaction_delay_max: float = CONSTS.AI_REACTION_DELAY_MAX
@export var ai_position_error: float = CONSTS.AI_POSITION_ERROR
@export var ai_speed_boost: float = CONSTS.AI_SPEED_BOOST
@export var ai_speed_slow: float = CONSTS.AI_SPEED_SLOW
```

**Design Decision — preload over class_name:** Both `ball.gd` and `paddle.gd` use `preload()` rather than relying on `class_name GameConstants`. Rationale: Godot headless mode (`--headless --script`) loads scripts in dependency order, and `class_name` availability depends on parse order — `preload()` is deterministic. If tests pass with `class_name`, the implement agent may switch to it; if not, `preload()` is the safe default.

#### 3.3.3 scoring_manager.gd — Constants Migration

```gdscript
const CONSTS = preload("res://gdscripts/constants.gd")
const POINTS_TO_WIN_GAME: int = CONSTS.POINTS_TO_WIN_GAME
const GAMES_TO_WIN_MATCH: int = CONSTS.GAMES_TO_WIN_MATCH
```

No logic changes — the script already has `@onready var score_flash: Node = get_node_or_null("../ScoreFlash")` which will resolve once ScoreFlash exists in Main.tscn.

#### 3.3.4 game_manager.gd — Constants Migration

```gdscript
const CONSTS = preload("res://gdscripts/constants.gd")
const POINTS_TO_WIN_GAME: int = CONSTS.POINTS_TO_WIN_GAME
const GAMES_TO_WIN_MATCH: int = CONSTS.GAMES_TO_WIN_MATCH
```

### 3.4 Test Layer

| File | Change | Est. Δ |
|------|--------|--------|
| `mini-pong/tests/test_ball.gd` | `game.tscn` → `Main.tscn` (lines 28, 119, 120, 139) | ±4 |
| `mini-pong/tests/test_ui_system.gd` | `game.tscn` → `Main.tscn` (lines 419, 420, 422, 424, 427) | ±5 |

### 3.5 Deletion

| File | Action |
|------|--------|
| `mini-pong/scenes/game.tscn` | **DELETE** — replaced by `Main.tscn` |

---

## 4. API Contracts

### 4.1 Signal Connections (Post-Assembly)

```
Ball.score(side: int)
    │  ← emitted from: ScoreZone body_entered OR _process() X boundary (fallback)
    │
    ▼
ScoringManager._on_ball_score(side)
    │
    ├── scored(winner: String) ──► GameStateMachine._on_scored(winner)
    │                               PLAYING → SCORED
    │
    ├── scored(winner: String) ──► ScoreFlash._on_score_changed(winner)
    │                               ← ✅ NEW: ScoreFlash node now exists in scene
    │                               ← connected in scoring_manager.gd:46-47
    │
    └── GameManager.add_score(winner)
            │
            ├── score_changed(p: int, a: int) ──► GameHUD._on_score_changed()
            │
            ├── game_won(winner: String)
            │       ← ⚠️ No consumer — acceptable MVP behavior (per PRD §6)
            │
            └── match_over(winner: String)
                    ├── GameStateMachine._on_match_over()
                    └── GameOverScreen._on_match_over()
```

### 4.2 ScoreZone Signal Flow (NEW)

```
ScoreZoneLeft.body_entered(Ball)
    │   ← Ball enters left zone (x < 20)
    │   ← ball.gd _on_score_zone(1)
    ▼
ball.score.emit(1)  → right player scores

ScoreZoneRight.body_entered(Ball)
    │   ← Ball enters right zone (x > 1260)
    │   ← ball.gd _on_score_zone(0)
    ▼
ball.score.emit(0)  → left player scores
```

### 4.3 Method Call Chains

**Game Start:**
```
project.godot run/main_scene → Main.tscn loads
  → GameStateMachine._ready()
    → _validate_references()  (now 7 refs)
    → enter_state(MENU)
      → _set_ui("start_menu"), _freeze_paddles(true)
  → ScoringManager._ready()
    → ball.score.connect(_on_ball_score)         ← ✅ (Ball node exists)
    → scored.connect(score_flash._on_score_changed) ← ✅ (ScoreFlash now exists!)
  → StartMenu visible
```

**Scoring Flow (after assembly):**
```
ScoreZone.body_entered(Ball) or ball._process() X boundary
  → ball.score.emit(side)
  → ScoringManager._on_ball_score(side)
    → scored.emit(winner)
      → GameStateMachine._on_scored() → PLAYING → SCORED
      → ScoreFlash._on_score_changed() → flash(Color) ← ✅ NOW WORKS
    → GameManager.add_score(winner)
      → score_changed.emit(p,a) → GameHUD labels update
      → _check_game_win() → game_won or continue
```

### 4.4 New @onready Reference: ScoreFlash

In `scoring_manager.gd` (already exists):
```gdscript
@onready var score_flash: Node = get_node_or_null("../ScoreFlash")
```
This was a no-op when ScoreFlash didn't exist. After assembly, `get_node_or_null` returns the ScoreFlash node, and `has_method("_on_score_changed")` returns true → signal connects and flash works.

---

## 5. Test Plan

### 5.1 Test Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|:----------:|:----------:|:------------:|
| Main.tscn scene tree | TC1, TC2 | TC3, TC4 | TC5 |
| Constants extraction | TC6 | TC7 | TC8 |
| ScoreFlash rendering | TC9 | TC10 | TC11 |
| ScoreZone collision | TC12 | TC13 | TC14 |
| Path migration (tests) | TC15, TC16 | — | TC17 |
| Compilation/headless | TC18 | — | TC19 |
| End-to-end flow | TC20 | — | — |

### 5.2 Test Case Descriptions

Test descriptions below are **verbal/scenario-based** — they document what the implement agent should verify. Actual test code is authored during the implement phase.

#### Scene Tree Integrity

**TC1 — Main.tscn contains all 12 node types (Normal)**
- **Setup:** Load `res://scenes/Main.tscn` via `load()` or `ResourceLoader.load()`
- **Steps:** Instantiate scene, iterate children
- **Expected:** Nodes present by name: WorldEnvironment, TopWall, BottomWall, Ball, PlayerPaddle, AIPaddle, ScoringManager, GameStateMachine, ScoreZoneLeft, ScoreZoneRight, ScoreFlash, StartMenu, GameHUD, GameOverScreen

**TC2 — Main.tscn ext_resource references resolve (Normal)**
- **Setup:** Load Main.tscn packed scene
- **Steps:** Check `ext_resource` references: ball.tscn, player_paddle.tscn, scoring_manager.gd, start_menu.gd, game_hud.gd, game_over_screen.gd, game_state_machine.gd, world_environment.tscn, score_flash.gd
- **Expected:** All 9 ext_resource paths point to existing files. No "Missing resource" warnings in Godot output.

**TC3 — WorldEnvironment missing file (Edge)**
- **Setup:** Temporarily rename `world_environment.tscn` → `_world_environment.tscn`
- **Steps:** Load Main.tscn
- **Expected:** Scene loads with warning `Missing resource: res://scenes/world_environment.tscn`. No crash. Other nodes functional.

**TC4 — ScoreFlash ColorRect child missing (Edge)**
- **Setup:** Instantiate Main.tscn, remove ScoreFlash's ColorRect child via script before `_ready()`
- **Steps:** Trigger score → ScoringManager emits `scored`
- **Expected:** `score_flash.has_method("_on_score_changed")` → true. `flash_rect` is null → `push_warning`. Scoring still works.

**TC5 — Main.tscn load with missing Ball node (Failure)**
- **Setup:** Remove Ball node from Main.tscn
- **Steps:** Load scene → ScoringManager._ready()
- **Expected:** `push_error("ScoringManager: Ball node not found — scoring disabled")`. GameStateMachine._validate_references() logs warning for null `ball`.

#### Constants Extraction

**TC6 — GameConstants values match original dispersed constants (Normal)**
- **Setup:** Preload `constants.gd`
- **Steps:** Compare each constant value against the original in ball.gd, paddle.gd, scoring_manager.gd, game_manager.gd
- **Expected:** All values identical (300.0, 2.0, 1.05, 60.0, 45.0, 10.0, 400.0, 20.0, 120.0, 0.1, 0.3, 20.0, 1.2, 0.8, 5, 2). Color values match: `Color(0.29, 0.56, 0.85, 1.0)` etc.

**TC7 — Scripts using GameConstants compile and run (Normal)**
- **Setup:** Headless compile: `godot --path mini-pong/ --headless --quit`
- **Steps:** Also run `godot --path mini-pong/ --headless --script tests/check_compile.gd`
- **Expected:** Exit code 0. No parse errors related to `CONSTS` or `GameConstants`.

**TC8 — preload("constants.gd") works in headless mode (Edge/Failure path)**
- **Setup:** Run `godot --path mini-pong/ --headless --script tests/run_tests.gd`
- **Steps:** If tests fail with `GameConstants` undefined, switch to `preload()` approach
- **Expected:** All tests pass with `preload()`. If `class_name` works: tests pass either way.

#### ScoreFlash Functionality

**TC9 — ScoreFlash node receives scored signal (Normal)**
- **Setup:** Load Main.tscn, enter PLAYING state, simulate ball scoring
- **Steps:** Emit `ball.score.emit(0)` → trace signal chain
- **Expected:** ScoreFlash._on_score_changed("player") called. ColorRect flashes blue (#4a90d9 at 30% alpha), fades to 0 in 0.2s.

**TC10 — ScoreFlash double-trigger (Edge)**
- **Setup:** Rapidly emit two `scored` signals < 0.2s apart
- **Steps:** ScoreFlash.flash() called twice
- **Expected:** First tween killed by `_flash_tween.kill()`. Second flash starts fresh. No overlapping tweens. No errors.

**TC11 — ScoreFlash missing from scene (Failure)**
- **Setup:** Load scene without ScoreFlash node
- **Steps:** scoring_manager.gd:46 `get_node_or_null("../ScoreFlash")` → null
- **Expected:** `score_flash.has_method(...)` not called (short-circuit). Scoring works normally. No crash.

#### ScoreZone Collision

**TC12 — Ball entering ScoreZoneLeft triggers score(side=1) (Normal)**
- **Setup:** Main.tscn loaded, ball positioned at x=10 (inside left zone), PLAYING state
- **Steps:** Advance one physics frame
- **Expected:** `score.emit(1)` called. AI scores. ScoringManager processes normally.

**TC13 — Dual-trigger prevention (Edge)**
- **Setup:** Ball positioned at x=5 (will trigger both ScoreZone body_entered AND _process X boundary on same frame)
- **Steps:** Advance one frame
- **Expected:** `_scored_this_frame` flag prevents double emission. Exactly one `score.emit()` per frame.

**TC14 — ScoreZone collision shape dimensions correct (Normal)**
- **Setup:** Read ScoreZoneLeft CollisionShape2D
- **Steps:** Check shape.size
- **Expected:** `RectangleShape2D` with `size = Vector2(20, 720)`. Position `(0, 360)`.

#### Path Migration

**TC15 — test_ball.gd references Main.tscn (Normal)**
- **Setup:** Read `mini-pong/tests/test_ball.gd`
- **Steps:** Grep for `game.tscn`
- **Expected:** Zero matches. All references use `Main.tscn`.

**TC16 — test_ui_system.gd references Main.tscn (Normal)**
- **Setup:** Read `mini-pong/tests/test_ui_system.gd`
- **Steps:** Grep for `game.tscn`
- **Expected:** Zero matches. All references use `Main.tscn`.

**TC17 — No remaining game.tscn references in project (Normal)**
- **Setup:** `grep -r "game\.tscn" mini-pong/ --include="*.gd" --include="*.tscn" --include="*.godot"`
- **Steps:** Run grep
- **Expected:** Zero matches (excluding `docs/` and `game_state_machine.gd` comments which are updated).

#### Compilation & Headless

**TC18 — Headless compilation passes (Normal)**
- **Setup:** `cd mini-pong && godot --headless --quit`
- **Steps:** Run command
- **Expected:** Exit code 0. No `ERROR:` lines in output. No `SCRIPT ERROR:` lines.

**TC19 — Scene loads without script errors (Normal)**
- **Setup:** `godot --path mini-pong/ --headless --script tests/check_compile.gd`
- **Steps:** Run command
- **Expected:** All scripts compile. Exit code 0.

#### End-to-End

**TC20 — Full game flow (Normal)**
- **Setup:** Run `godot --path mini-pong/ mini-pong/scenes/Main.tscn` (editor mode)
- **Steps:** Menu → SPACE → SERVING → PLAYING → ball scores → ScoreFlash → HUD updates → game_won → match_over → GameOverScreen → SPACE → MENU
- **Expected:** Complete cycle without errors. WorldEnvironment glow visible. ScoreFlash flash visible. HUD score updates visible.

---

## 6. Files Changed — Master Summary

| # | File | Type | Change | Est. Lines |
|---|------|------|--------|:----------:|
| 1 | `mini-pong/scenes/Main.tscn` | New | Create from game.tscn + add 4 nodes | +165 |
| 2 | `mini-pong/gdscripts/constants.gd` | New | Extract all constants | +55 |
| 3 | `mini-pong/scenes/game.tscn` | Delete | Replaced by Main.tscn | −140 |
| 4 | `mini-pong/project.godot` | Modify | run/main_scene path update | ±1 |
| 5 | `mini-pong/gdscripts/ball.gd` | Modify | Constants + ScoreZone collision | +25 |
| 6 | `mini-pong/gdscripts/paddle.gd` | Modify | Constants migration | ±4 |
| 7 | `mini-pong/gdscripts/scoring_manager.gd` | Modify | Constants migration | ±2 |
| 8 | `mini-pong/gdscripts/game_manager.gd` | Modify | Constants migration | ±2 |
| 9 | `mini-pong/gdscripts/game_state_machine.gd` | Modify | Comment updates | ±2 |
| 10 | `mini-pong/tests/test_ball.gd` | Modify | Path: game.tscn → Main.tscn | ±4 |
| 11 | `mini-pong/tests/test_ui_system.gd` | Modify | Path: game.tscn → Main.tscn | ±5 |
| **Total** | | | | **~+265 / −140** |

---

## 7. Verification Checklist

### AC1: Main.tscn Scene Tree
- [ ] WorldEnvironment node present, references `world_environment.tscn`
- [ ] ScoreZoneLeft node present (Area2D, pos 0,360, collider 20×720)
- [ ] ScoreZoneRight node present (Area2D, pos 1280,360, collider 20×720)
- [ ] ScoreFlash node present (Node + ColorRect child "ScoreFlashRect" 1280×720)
- [ ] All 9 original node types unchanged from game.tscn
- [ ] `project.godot` → `run/main_scene="res://scenes/Main.tscn"`

### AC2: Signal Connections
- [ ] Ball.score → ScoringManager (unchanged)
- [ ] ScoringManager.scored → GameStateMachine._on_scored (unchanged)
- [ ] ScoringManager.scored → ScoreFlash._on_score_changed (now functional)
- [ ] GameManager.score_changed → GameHUD (unchanged)
- [ ] GameManager.match_over → GameStateMachine, GameOverScreen (unchanged)
- [ ] ScoreZone body_entered → ball._on_score_zone (new, verified)

### AC3: Global Constants
- [ ] `gdscripts/constants.gd` exists with `class_name GameConstants`
- [ ] All 20 constants defined (screen ×2, ball ×6, paddle ×3, AI ×5, scoring ×2, colors ×3)
- [ ] `scoring_manager.gd` references `CONSTS.POINTS_TO_WIN_GAME` (no local duplicate)
- [ ] `game_manager.gd` references `CONSTS.POINTS_TO_WIN_GAME` (no local duplicate)
- [ ] `ball.gd` references `CONSTS.BALL_INITIAL_SPEED` etc.
- [ ] `paddle.gd` references `CONSTS.PADDLE_SPEED` etc.

### AC4: Game Flow
- [ ] Start → Main.tscn loads → WorldEnvironment visible → StartMenu visible
- [ ] SPACE → SERVING → ball serves → PLAYING → paddles move
- [ ] Score → ScoreFlash flashes → HUD updates → SCORED state → re-serve
- [ ] 5 points → game_won → scores reset → next game
- [ ] 2 games → match_over → GameOverScreen → SPACE → MENU

### AC5: Compilation
- [ ] `godot --path mini-pong/ --headless --quit` → exit 0
- [ ] `godot --path mini-pong/ --headless --script tests/check_compile.gd` → exit 0
- [ ] `godot --path mini-pong/ --headless --script tests/run_tests.gd` → all pass

### AC6: File Cleanup
- [ ] `mini-pong/scenes/game.tscn` deleted
- [ ] Zero remaining references to `game.tscn` in .gd, .tscn, .godot files
- [ ] `docs/GAME_DESIGN/` annotation optionally updated (non-blocking)

---

## 8. Edge Cases & Failure Paths

### Edge Cases

| # | Scenario | Design Response |
|---|----------|----------------|
| EC1 | Main.tscn loads when `world_environment.tscn` missing | Godot warns, scene loads degraded. No crash. |
| EC2 | ScoreFlash ColorRect missing | `has_method` check in score_flash.gd:12 prevents crash. Scoring works. |
| EC3 | ScoreZone and _process X boundary both trigger same frame | `_scored_this_frame` flag in ball.gd prevents double-emit |
| EC4 | `class_name GameConstants` unavailable in headless mode | `preload("res://gdscripts/constants.gd")` used as fallback by all consumers |
| EC5 | Old `game.tscn` still referenced by a cached test runner | `grep` verification step (TC17) catches before PR merge |
| EC6 | Two paddles share `player_paddle.tscn` — AIPaddle mode=1 | Already verified working in current game.tscn. No change. |
| EC7 | CanvasLayer nodes are inline (not ext_resource instances) | Preserved from game.tscn. Consistent with #292 design. |

### Failure Paths

| # | Scenario | Mitigation |
|---|----------|-----------|
| FP1 | `project.godot` run/main_scene points to deleted `game.tscn` | Compilation check (AC5) catches. Error: "Can't run project: No main scene defined" |
| FP2 | GameStateMachine NodePath exports break after rename | Only comment updates in game_state_machine.gd — no NodePath changes. FSM refs use `"../Ball"` etc., unchanged. |
| FP3 | Test path references not fully updated | `grep -r "game\.tscn" mini-pong/ --include="*.gd"` catches. TC15-17 verify. |
| FP4 | constants.gd preload path wrong | `godot --headless --quit` catches at compile time. "Can't preload resource" error. |
| FP5 | ScoreZone collision shape overlaps with paddle/wall zones | Zone positioned at x=0 and x=1280 — outside playfield. Ball only reaches zone after passing paddle. |

---

## 9. Correction to PRD

**Correction 1 — constants.gd approach: `preload()` over `class_name`:** The PRD §4 recommends `class_name GameConstants` as the primary approach. The DESIGN adds a conservative fallback: use `preload("res://gdscripts/constants.gd")` in all consumers, because Godot headless mode (`--headless --script`) may not resolve `class_name` in dependency order. The implement agent should start with `preload()` and switch to `class_name` only if headless tests confirm it works.

**Correction 2 — PRD over-counts `game_state_machine.gd` changes:** The PRD §3 lists `game_state_machine.gd` as needing `game.tscn` → `Main.tscn` updates on lines 23, 194. Investigation confirms only comment strings need updating (lines 23 comment and 194 push_warning string). No functional code paths reference `game.tscn` — NodePath exports use relative `"../Ball"` paths, not scene filenames.

**Correction 3 — `ball_trail.gd` not affected:** The PRD §3 "Indirect Impact" does not list `ball_trail.gd`. Investigation confirms `ball_trail.gd` follows the ball node via `get_parent()` and has no hardcoded scene paths — no changes needed.

**Correction 4 — `test_game_state_machine.gd` may not reference `game.tscn`:** The PRD §3 speculates `test_game_state_machine.gd` "可能引用 game.tscn". Investigation via grep confirms zero `game.tscn` matches in `test_game_state_machine.gd`. No path update needed for this file.

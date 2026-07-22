# Design: #43 — Project Scaffold

> Parent Issue: #43
> Agent: plan-agent
> Date: 2026-07-22

---

## 1. Architecture Overview

### Core Idea

Build the foundational CRPG project scaffold on top of the existing Hello World project. Add a `GameState` singleton (autoload) managing `hope` and `despair` variables with signal-based change notifications, restructure the entry scene as a 3D hierarchy (Node3D → Label3D + placeholder slots for UI and dialogue), configure project-level input mappings for keyboard navigation, and add a macOS export preset. This scaffold is the foundation that all subsequent features (dialogue engine, UI overlay, text system, scene switching) depend on.

### Data Flow

```ascii
Godot Engine startup
    │
    ├─ project.godot loads config
    │   ├─ Renderer: forward_plus
    │   ├─ Input Map: arrow keys, Enter/Space, Esc
    │   └─ Autoloads: GameManager → GameState (order matters)
    │
    ├─ Autoload GameManager._ready() — prints banner
    │
    ├─ Autoload GameState._ready()
    │   └─ hope=100, despair=0
    │
    ├─ scenes/main.tscn (Node3D root)
    │   ├─ Label3D "Hello, Godot!" — keyboard-responsive text display
    │   ├─ CanvasLayer/UIOverlay — Control node placeholder for HUD system
    │   └─ CanvasLayer/DialogueLayer — Control node placeholder for dialogue UI
    │
    ├─ gdscripts/main.gd
    │   ├─ _ready() → connect to GameState.state_changed signal
    │   │              update Label3D text with initial state
    │   ├─ _input(event) → arrow keys / Enter / Esp → update Label3D
    │   └─ _on_state_changed(state) → update Label3D text
    │
    └─ Player sees 3D text responding to keyboard input
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| GameState as separate Autoload | New `gdscripts/game_state.gd` alongside existing GameManager | GameManager manages lifecycle/game-flow; GameState owns game-world state (hope/despair). Separation of concerns prevents a monolithic singleton. |
| Scene root type | Node3D (3D scene) | CRPG uses 3D environments — the entry scene must demonstrate 3D rendering and be extensible with 3D world nodes downstream. |
| Text display type | Label3D (3D node) | Shows 3D text that responds to input, demonstrating the 3D pipeline works. Can be replaced/enhanced by downstream text system. |
| Placeholder approach | CanvasLayer children (Control nodes) on main scene | CanvasLayer renders on top of 3D world — perfect for UI overlays. Placeholder nodes are empty Control containers that downstream features reparent into. |
| Input handling location | `main.gd._input()` | Simplest pattern for a single-scene demo. Downstream features will add their own input handling via the Input Map. |
| GameState default values | hope=100, despair=0 | 100/0 gives an unambiguous "fresh start" state. downstream systems can adjust at game start via apply_state(). |
| macOS export preset | Added to `export_presets.cfg` alongside Linux/X11 | Enables CI build for both platforms. macOS templates must be downloaded during CI setup. |

---

## 2. Node / Scene Tree Layer

### Scene Modifications: `scenes/main.tscn`

**Restructure from 2D (Node + Label) to 3D (Node3D root + Label3D + CanvasLayer placeholders).**

| Node | Type | Parent | Purpose |
|------|------|--------|---------|
| Main | Node3D (was Node) | — | New 3D root for the entry scene |
| WorldLabel | Label3D | Main | 3D text label displaying game-state-reactive text. Font size 64, horizontal alignment center, position (0, 0, -5) |
| UI | CanvasLayer | Main | Renders on top of 3D world. Contains placeholder Control nodes for downstream HUD/UI |
| UI/Overlay | Control | UI | **Placeholder** — empty container for future HUD system (state display, day counter) |
| Dialogue | CanvasLayer | Main | Renders on top of 3D world and UI. Contains placeholder for dialogue panel |
| Dialogue/Panel | Control | Dialogue | **Placeholder** — empty container for future dialogue engine UI |
| Camera3D | Camera3D | Main | Perspective camera, position (0, 2, 5), looking at origin |

**Signal Connections:**
- `Main` script (`main.gd`) connects to `GameState.state_changed` in `_ready()`

### Existing Scene Removals
- Remove old `Label` (2D Control node) — replaced by `WorldLabel` (Label3D)

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/game_state.gd`

**Extends:** `Node` (registered as Autoload in project.godot)

**Purpose:** Global game state singleton managing CRPG-specific state variables with signal-based change notifications.

```gdscript
extends Node

# --- Signals ---
signal state_changed(state: Dictionary)

# --- State Variables ---
var hope: int = 100       # 0–100, player's hope level (100 = fresh start)
var despair: int = 0      # 0–100, player's despair level (0 = fresh start)

# --- Public API ---
func _ready() -> void:
    print("GameState initialized: hope=", hope, ", despair=", despair)

func apply_state(delta_hope: int, delta_despair: int) -> void:
    hope = clampi(hope + delta_hope, 0, 100)
    despair = clampi(despair + delta_despair, 0, 100)
    state_changed.emit(get_state())

func get_state() -> Dictionary:
    return {"hope": hope, "despair": despair}

func reset() -> void:
    hope = 100
    despair = 0
    state_changed.emit(get_state())
```

**Key behaviors:**
- `apply_state()` clamps both values to [0, 100] and emits `state_changed`
- `reset()` restores defaults and emits `state_changed`
- `state_changed` signal carries a Dictionary with `hope` and `despair` keys

### Rewritten Script: `gdscripts/main.gd`

**Extends:** `Node3D` (was `Node` — reflects new 3D root)

```gdscript
extends Node3D

# Main — CRPG entry scene script
# Handles keyboard input and connects to GameState

@onready var world_label: Label3D = $WorldLabel
@onready var state_system: Node = get_node("/root/GameState")

func _ready() -> void:
    if state_system:
        state_system.state_changed.connect(_on_state_changed)
    world_label.text = "Hope: 100  Despair: 0"
    print("CRPG Main Scene ready.")

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_up"):
        if state_system:
            state_system.apply_state(5, 0)
    elif event.is_action_pressed("ui_down"):
        if state_system:
            state_system.apply_state(-5, 0)
    elif event.is_action_pressed("ui_right"):
        if state_system:
            state_system.apply_state(0, -5)
    elif event.is_action_pressed("ui_left"):
        if state_system:
            state_system.apply_state(0, 5)
    elif event.is_action_pressed("ui_accept"):
        if state_system:
            state_system.reset()
    elif event.is_action_pressed("ui_cancel"):
        print("Pause requested (placeholder)")

func _on_state_changed(state: Dictionary) -> void:
    world_label.text = "Hope: " + str(state.hope) + "  Despair: " + str(state.despair)
```

**Key behaviors:**
- `_ready()` connects to `GameState.state_changed` via `/root/GameState` path
- `_input()` handles arrow keys (ui_up/ui_down/ui_left/ui_right), Enter/Space (ui_accept), Escape (ui_cancel)
- Arrow keys modify hope/despair: Up=+hope, Down=-hope, Right=-despair, Left=+despair
- Accept (Enter/Space) resets state to defaults
- Cancel (Escape) prints a pause placeholder message
- `_on_state_changed()` updates the Label3D text to reflect current state

### Existing Script: `gdscripts/game_manager.gd`

**No changes needed.** GameManager remains functional as an Autoload. GameState is a separate Autoload loaded after GameManager.

---

## 4. Resource / Config Layer

### `project.godot` — Autoload Registration

Add GameState as a second autoload, registered AFTER GameManager:

```ini
[autoload]
GameManager="*res://gdscripts/game_manager.gd"
GameState="*res://gdscripts/game_state.gd"
```

Order matters: GameManager initializes first, then GameState. The `*` prefix marks it as a singleton (global scope).

### `project.godot` — Input Map Entries

The built-in Godot 4.7 input actions (`ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_accept`, `ui_cancel`) already exist by default in any Godot 4 project. The design uses these built-in actions — no new input map entries need to be defined. This keeps the input handling compatible with console controllers and touch input out of the box.

> **Decision rationale:** Using built-in `ui_*` actions avoids adding custom input mappings that downstream features would need to override. If custom CRPG-specific actions are needed later (e.g. `interact`, `inventory`, `map`), they can be added in the respective feature issues.

### `export_presets.cfg` — macOS Export Preset

Add a new preset `[preset.1]` for macOS:

```ini
[preset.1]

name="macOS"
platform="macOS"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="exports/agent-game-test-macos.zip"
patch_list=PackedStringArray()
patches=PackedStringArray()
script_encryption_key=""

[preset.1.options]

custom_template/debug=""
custom_template/release=""
binary_format/embed_pck=false
texture_format/bptc_force_packed=true
texture_format/s3tc_force_packed=true
texture_format/etc1_force_packed=true
texture_format/etc2_force_packed=true
codesign/enable=false
codesign/identity=""
codesign/password=""
codesign/timestamp=""
codesign/timestamp_service_url=""
application/export_icon=""
application/icon=""  # macOS app icon — leave empty for default
```

### Existing Config: `project.godot`

No changes needed to existing sections (`[application]`, `[rendering]`, `[display]`, `[editor_plugins]`).

---

## 5. Asset / Visual Layer

### No New Assets Required

The Label3D uses Godot's built-in font rendering (default Theme). No custom textures, materials, or sprites are needed for the scaffold.

**Future assets** (not in scope):
- UI theme `.tres` resources for HUD/dialogue panels
- Sprites and 3D models for the game world
- Custom fonts for Label3D

---

## 6. Input / UI Layer

### Input Actions Used

| Action | Key Binding | Effect |
|--------|-------------|--------|
| `ui_up` | Up Arrow / W | Increase hope by 5 |
| `ui_down` | Down Arrow / S | Decrease hope by 5 |
| `ui_right` | Right Arrow / D | Decrease despair by 5 |
| `ui_left` | Left Arrow / A | Increase despair by 5 |
| `ui_accept` | Enter / Space | Reset GameState to defaults |
| `ui_cancel` | Escape | Print pause placeholder message |

These are Godot's built-in actions — no `project.godot` changes needed for input mapping.

### UI Hierarchy

```
Main (Node3D)                ← 3D scene root
├─ WorldLabel (Label3D)      ← 3D text, state-reactive
├─ Camera3D                  ← Perspective camera
├─ UI (CanvasLayer)          ← HUD/UI overlay
│  └─ Overlay (Control)      ← Placeholder for HUD system
└─ Dialogue (CanvasLayer)    ← Dialogue overlay (renders above UI)
   └─ Panel (Control)        ← Placeholder for dialogue engine
```

---

## 7. Test Layer

### Test Structure

The existing `tests/run_tests.gd` must remain passing. The scaffold changes affect the main scene and autoloads but the existing Label unit tests are independent of Autoloads and the scene tree — they create their own `Label.new()` instances. No test code changes are needed.

**New test file:** `tests/test_game_state.gd` (to be created in Implement phase)

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| GameState.apply_state() | ✅ | ≥3 | ✅ |
| GameState.state_changed signal | ✅ | ≥2 | ✅ |
| Main script input handling | ✅ | ≥2 | ✅ |
| Main script GameState connection | ✅ | ≥1 | ✅ |

### Test Case Descriptions

**Normal Path (TC-S1): GameState basic apply/reset cycle**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S1-1 | Apply positive hope delta | Create GameState, call `apply_state(10, 5)` | hope=100→100 (capped), despair=0→5 | `_assert(state.hope == 100)` |
| TC-S1-2 | Apply negative despair delta | Create GameState, call `apply_state(-20, -3)` | hope=100→80, despair=0→0 (clamped) | `_assert(state.despair == 0)` |
| TC-S1-3 | Reset to defaults | Call `apply_state(50, 30)`, then `reset()` | hope=100, despair=0 | `_assert(state.hope == 100 && state.despair == 0)` |
| TC-S1-4 | state_changed signal emitted | Connect to signal, call `apply_state(10, 0)` | Signal fires exactly once with correct state | `_assert(signal_fired == true && state.hope == state_captured.hope)` |

**Edge Cases (TC-S2): GameState boundary conditions**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S2-1 | Clamp at upper bound (hope) | Call `apply_state(200, 0)` | hope=100 (clamped) | `_assert(state.hope == 100)` |
| TC-S2-2 | Clamp at lower bound (despair) | Call `apply_state(0, -200)` | despair=0 (clamped) | `_assert(state.despair == 0)` |
| TC-S2-3 | Simultaneous clamping | Call `apply_state(200, -200)` | hope=100, despair=0 (both clamped) | `_assert(state.hope == 100 && state.despair == 0)` |
| TC-S2-4 | Zero delta is a no-op | Call `apply_state(0, 0)` | hope=100, despair=0 (unchanged) | `_assert(state.hope == 100 && state.despair == 0)` |

**Edge Cases (TC-S3): Main script GameState integration**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S3-1 | GameState not available | Run main.gd without GameState autoload | Graceful null-check: `if state_system:` protects against missing singleton, no crash | `_assert(no crash)` |
| TC-S3-2 | state_changed updates Label3D text | Call `apply_state(5, 0)`, check text | world_label.text contains "Hope: 100  Despair: 0" after reset | `_assert(text matches pattern)` |

**Failure Path (TC-S4): Edge case input handling**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-S4-1 | Multiple rapid inputs | Call `apply_state(5,0)` 25 times rapidly | hope=100 (clamped at max), despair=0 | `_assert(state.hope == 100)` |
| TC-S4-2 | Large negative delta from fresh state | Call `apply_state(-500, 0)` | hope=0 (clamped at min) | `_assert(state.hope == 0)` |

---

## 8. Files Changed (per-layer summary)

### Node / Scene Tree Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/main.tscn` | Restructure from 2D (Node + Label) to 3D (Node3D + Label3D + CanvasLayer placeholders + Camera3D) | ±30 |

### GDScript / Logic Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/game_state.gd` | **New** — Autoload singleton with hope/despair + state_changed signal | +35 |
| `gdscripts/main.gd` | Rewrite: extends Node3D, add _input() handling, GameState integration | ±40 |

### Resource / Config Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `project.godot` | Add `GameState` autoload entry (1 line) | +1 |
| `export_presets.cfg` | Add macOS export preset | +25 |

### Total Estimate

~96 lines changed/added across 5 files.

---

## 9. Verification Checklist

- [ ] `godot --headless --script tests/run_tests.gd` — all 3 existing Label tests pass (0 failures)
- [ ] `godot --headless --check-only` — project opens without errors (validates GameState autoload, scene structure, input map)
- [ ] `scenes/main.tscn` loads with Node3D root, Label3D child, CanvasLayer placeholders, Camera3D
- [ ] GameState autoload loads with hope=100, despair=0 (verify via print statement)
- [ ] Keyboard input (arrow keys) updates Label3D text via state_changed signal
- [ ] Enter/Space resets GameState to defaults
- [ ] macOS export preset appears in export dialog (`godot --headless --export-list` check)
- [ ] No regression: existing GameManager autoload still prints its initialization message
- [ ] No regression: all pre-existing tests still pass on repeated runs (5 consecutive runs)

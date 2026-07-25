# Design: Interactive Area Visual Feedback System

> Parent Issue: #218
> Agent: game-plan-agent
> Date: 2026-07-25
> Approach: A — InteractiveArea Component + Decal/Shader Feedback System

---

## 1. Architecture Overview

### Core Idea

Create a reusable `InteractiveArea` component (extends Area3D) that provides configurable visual feedback — Decal glow, OmniLight3D pulse, billboarded Sprite3D indicator, and scale pulse — whenever the player's cursor hovers over or walks near an interactive object. The component drops into any scene as a child of an interactive trigger zone, wiring into the existing `mouse_entered`/`mouse_exited` (built into Area3D) and `body_entered`/`body_exited` (player proximity) signals.

```
InteractiveArea (Area3D — replaces or wraps inline Area3D triggers)
├── CollisionShape3D (BoxShape3D / CylinderShape3D — interaction zone)
├── HoverDecal (Decal — optional, projected glow on hover)
├── ProximityLight (OmniLight3D — optional, pulsing light on proximity)
└── IndicatorIcon (Sprite3D — optional, billboarded floating icon)
```

### Design Philosophy

1. **Composable layers** — Each visual effect (Decal, Light, Sprite, Scale) is independently optional. Scenes configure only what they need.
2. **Non-destructive** — Existing `input_event`, `body_entered`/`body_exited`, and `_nearby_interactables` integration continues to work. InteractiveArea is additive.
3. **Diegetic** — World-space glow on surfaces (Decal) and point lights (OmniLight3D) match the warm amber neon aesthetic (`#FFAA55`).
4. **Economical** — GDScript only, no C++ modules. Uses Godot 4.7 built-in nodes (Decal, OmniLight3D, Sprite3D, Tween).

### Visual Palette

| Effect | Color | Alpha / Intensity | Duration |
|--------|-------|-------------------|----------|
| Hover Decal Glow | `#FFAA55` warm amber | Alpha 0.3–0.6 | 0.2s fade-in, 0.3s fade-out |
| Proximity Pulse Light | `#FFAA55` | Energy 0.5–2.0 | 1.5s pulse cycle |
| Scale Pulse | — | 1.0 → 1.05 → 1.0 | 1.0s bounce cycle |
| NPC Indicator Arrow | `#AAFFDD` teal-white | Alpha 0.4–0.8 persistent | 2.0s slow pulse |
| Key Item Indicator | `#FF8833` deep amber | Alpha 0.5–0.9 persistent | 1.2s stronger pulse |

---

## 2. New Components — Detailed Design

### 2.1 InteractiveArea (`gdscripts/interactive_area.gd`)

- **File:** `gdscripts/interactive_area.gd`
- **Extends:** `Area3D`
- **Class name:** `InteractiveArea`

#### Signals

| Signal | Parameters | When Emitted |
|--------|-----------|--------------|
| `hovered()` | — | Mouse cursor enters the InteractiveArea |
| `unhovered()` | — | Mouse cursor leaves the InteractiveArea |
| `proximity_entered()` | — | Player body enters the InteractiveArea |
| `proximity_exited()` | — | Player body exits the InteractiveArea |
| `interactable_clicked()` | — | Left-click detected while `is_interactable == true` |

#### Exported Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `feedback_mode` | `int` (enum) | `BOTH` | HOVER_ONLY, PROXIMITY_ONLY, BOTH, INDICATOR_ONLY |
| `is_interactable` | `bool` | `true` | Gate for click processing |
| `parent_mesh` | `NodePath` | `""` | Optional parent MeshInstance3D for scale pulse |
| `decal_size` | `Vector2` | `(0.8, 0.8)` | Decal projection size |
| `light_energy` | `float` | `1.5` | OmniLight3D energy at full pulse |
| `indicator_texture` | `Texture2D` | `null` | Sprite3D texture for indicator |
| `indicator_size` | `float` | `0.3` | Sprite3D pixel size |
| `fade_in_duration` | `float` | `0.2` | Seconds for hover/proximity fade-in |
| `fade_out_duration` | `float` | `0.3` | Seconds for hover/proximity fade-out |
| `pulse_duration` | `float` | `1.5` | Seconds for one pulse cycle |
| `scale_pulse_intensity` | `float` | `0.05` | Scale delta (1.0 ± intensity) |
| `glow_color` | `Color` | `#FFAA55` | Amber glow color |
| `proximity_distance` | `float` | `2.0` | Range for proximity light |

#### Internal State

| Variable | Type | Purpose |
|----------|------|---------|
| `_hover_decal` | `Decal` or `null` | Created if feedback_mode supports hover |
| `_proximity_light` | `OmniLight3D` or `null` | Created if feedback_mode supports proximity |
| `_indicator_sprite` | `Sprite3D` or `null` | Created if indicator_texture is set |
| `_parent_node` | `Node3D` or `null` | Resolved from parent_mesh path for scale pulse |
| `_is_hovered` | `bool` | Current hover state |
| `_is_nearby` | `bool` | Current proximity state |

#### Key Methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `_ready()` | `void` | Build visual children, connect signals, start indicator pulse |
| `_build_hover_decal()` | `void` | Create Decal with additive-blend material, load glow texture |
| `_build_proximity_light()` | `void` | Create OmniLight3D with exported glow_color |
| `_build_indicator_sprite()` | `void` | Create billboarded Sprite3D at 2.0m above root |
| `_on_mouse_entered()` | `void` | Fade decal in, start scale pulse, emit `hovered()` |
| `_on_mouse_exited()` | `void` | Fade decal out, stop scale pulse, emit `unhovered()` |
| `_on_body_entered(body)` | `void` | Check player group, fade proximity light in, emit `proximity_entered()` |
| `_on_body_exited(body)` | `void` | Check player group, fade proximity light out, emit `proximity_exited()` |
| `_on_input_event(camera, event, pos, normal, shape_idx)` | `void` | Gate by `is_interactable`, emit `interactable_clicked()` on left-click |
| `_tween_hover_decal(target_alpha)` | `void` | Tween decal material alpha to target |
| `_tween_proximity_light(target_energy)` | `void` | Tween light energy to target |
| `_tween_scale_pulse(active)` | `void` | Start/stop looping scale tween on parent mesh |
| `_start_indicator_pulse()` | `void` | Looping alpha tween on indicator sprite |
| `_exit_tree()` | `void` | Disconnect all signals gracefully |

#### Connection Pattern

```gdscript
# In InteractiveArea._ready() — schematic:
mouse_entered.connect(_on_mouse_entered)       # Built into Area3D
mouse_exited.connect(_on_mouse_exited)          # Built into Area3D
body_entered.connect(_on_body_entered)          # Built into Area3D
body_exited.connect(_on_body_exited)            # Built into Area3D
input_event.connect(_on_input_event)            # Built into Area3D
```

The `mouse_entered`/`mouse_exited` signals fire automatically when the mouse cursor moves over the CollisionShape3D — no per-frame raycasting needed.

### 2.2 NPC Indicator Controller (`gdscripts/npc_indicator.gd`)

- **File:** `gdscripts/npc_indicator.gd`
- **Extends:** `Sprite3D`

Optional standalone script that adds a looping alpha pulse and gentle bob animation to an NPC's indicator icon. Can be attached directly in NPC.tscn as an alternative to building the indicator via InteractiveArea.

Signals: none (controlled via exported parameters).

### 2.3 Interactive Feedback Shader (`gdscripts/interactive_feedback.gdshader`)

- **File:** `gdscripts/interactive_feedback.gdshader`
- **Type:** `shader_type spatial; render_mode blend_add`

Optional fresnel-based edge-outline shader for MeshInstance3D interactables. Provides a geometry-bound glow that follows mesh edges, separate from the Decal-based floor glow. See PRD §4 for full shader code.

### 2.4 Asset Textures

| File | Size | Description |
|------|------|-------------|
| `assets/textures/glow_amber.webp` | 256×256 | Radial gradient, amber center → transparent edge, for Decal |
| `assets/textures/icon_interact.webp` | 64×64 | Teal chevron/arrow for NPC indicator |
| `assets/textures/icon_important.webp` | 64×64 | Deep amber diamond for key items |

---

## 3. Existing Component Modifications

### Modified Files

| File | Change | Why |
|------|--------|-----|
| `gdscripts/npc_node.gd` | Add optional `InteractiveArea` child in `_ready()`; wire `hovered`/`proximity_entered` to name label emission; set `is_interactable = false` when state != IDLE | NPCs get the same visual feedback as other interactables; feedback suppressed during dialogue |
| `gdscripts/player_controller.gd` | Add new `interactable_hovered` signal (optional enhancement); emit when mouse ray intersects top of `_nearby_interactables` stack | Bridges the gap between mouse hover (on InteractiveArea) and E-key proximity (on PlayerController's InteractionArea) |
| `gdscripts/scene_base.gd` | No changes needed | InteractiveArea integrates at scene level via TSCN modifications |

### Modified TSCN Files

All 8 scene TSCN files need the same pattern:
1. Wrap or replace the existing inline `Area3D` trigger with an `InteractiveArea` (or add `InteractiveArea` as a sibling/parent)
2. Configure exported feedback params per scene (decal_size, glow_color, indicator_texture)
3. Wire `interactable_clicked` → existing scene dialogue handler

| Scene | Trigger(s) to Modify | Suggested Feedback Mode |
|-------|---------------------|------------------------|
| `scenes/office/office.tscn` | `InteractionZones/OfficeDoorTrigger` | HOVER_ONLY + scale pulse |
| `scenes/store/convenience_store.tscn` | `InteractionZones/StoreExitTrigger` | HOVER_ONLY |
| `scenes/street/street.tscn` | `InteractionZones/StoreEntranceTrigger`, `ExitZoneToOffice`, `ExitZoneToStore` | HOVER_ONLY for triggers; the ExitZones use their own mechanism |
| `scenes/lobby/lobby.tscn` | `SecurityGuardTrigger`, `StrangerTrigger`, `ExitTrigger` | HOVER_ONLY for all three |
| `scenes/bridge/bridge.tscn` | `RailingTrigger`, `HomelessTrigger`, `BridgeExitTrigger` | HOVER_ONLY |
| `scenes/underpass/underpass.tscn` | `GraffitiTrigger`, `StrangerEchoTrigger`, `UnderpassExitTrigger` | HOVER_ONLY |
| `scenes/subway_station/subway_station.tscn` | `TicketGateTrigger`, `TurnBackTrigger`, `BenchTrigger` | HOVER_ONLY |

**Note:** For ExitZone-based exits (street.tscn's `ExitZoneToOffice`, `ExitZoneToStore`), the ExitZone itself is an Area3D subclass. The implement agent should decide whether to:
- (a) Add InteractiveArea as a sibling to ExitZone (simpler, no ExitZone modification)
- (b) Make ExitZone extend InteractiveArea (deeper, requires refactoring ExitZone)

**Recommendation:** Option (a) — add `InteractiveArea` as a child or sibling of the zone Area3D for hover visual feedback, keeping ExitZone's existing logic unchanged.

### Codebase Gap: What the PRD Assumes vs Codebase Reality

| PRD Assertion | Actual Codebase | Design Resolution |
|---------------|----------------|-------------------|
| `PlayerController` has `interactable_hovered` signal | Does NOT exist; has `interaction_requested`, `dialogue_mode_changed`, `navigation_hint_requested` | Add new signal as optional enhancement; not required for MVP |
| All scenes have `EKeyTrigger` children on Area3D triggers | Only `office.tscn` OfficeDoorTrigger has EKeyTrigger; lobby/bridge/underpass/subway triggers rely on `input_event` via `.gd` scripts | InteractiveArea handles both mouse click (via `input_event`) and hover — existing EKeyTrigger wiring continues to work unaffected |
| `proximity_distance` on InteractiveArea | NPCNode has its own `proximity_distance` export; InteractiveArea needs its own | InteractiveArea gets an independent `proximity_distance: float` export for the OmniLight3D range |
| Scene `Area3D` triggers have CollisionShape3D | All do — confirmed | InteractiveArea inherits Area3D, so existing CollisionShape3D children work |
| NPC indicator via InteractiveArea | NPC.tscn uses Script (NPCNode) as root node; IndicatorIcon would be added as additional child | Add InteractiveArea as child of NPC.tscn's root Node3D, not replacing InteractionTrigger |

---

## 4. Data Flow

### Flow 1: Hover Highlight

```
Player moves cursor over InteractiveArea CollisionShape3D
    │
    ├── Area3D built-in signal: mouse_entered
    │   └── InteractiveArea._on_mouse_entered()
    │       ├── _is_hovered = true
    │       ├── _tween_hover_decal(target_alpha=0.5)
    │       │   └── Tween: material.albedo_color.a → 0.5 (0.2s)
    │       ├── _tween_scale_pulse(active=true)
    │       │   └── Looping Tween: parent.scale 1.0→1.05→1.0 (1.0s sine)
    │       └── hovered.emit()
    │
Player moves cursor away
    ├── mouse_exited
    │   └── InteractiveArea._on_mouse_exited()
    │       ├── _is_hovered = false
    │       ├── _tween_hover_decal(target_alpha=0.0) → fade out (0.3s)
    │       ├── _tween_scale_pulse(active=false) → reset to 1.0
    │       └── unhovered.emit()
```

### Flow 2: Proximity Glow

```
Player body enters InteractiveArea CollisionShape3D
    │
    ├── body_entered(body)
    │   └── InteractiveArea._on_body_entered(body)
    │       └── if body.is_in_group("player"):
    │           ├── _is_nearby = true
    │           ├── _tween_proximity_light(target_energy=1.5)
    │           │   └── Tween: light_energy → 1.5 (0.2s)
    │           └── proximity_entered.emit()
    │
Player body exits InteractiveArea
    ├── body_exited(body)
    │   └── InteractiveArea._on_body_exited(body)
    │       ├── _is_nearby = false
    │       ├── _tween_proximity_light(target_energy=0.0) → fade out (0.3s)
    │       └── proximity_exited.emit()
```

### Flow 3: Click Gating

```
Left-click on InteractiveArea
    │
    ├── input_event(camera, event, position, normal, shape_idx)
    │   └── InteractiveArea._on_input_event(...)
    │       ├── event is InputEventMouseButton
    │       ├── event.button_index == MOUSE_BUTTON_LEFT
    │       ├── event.pressed == true
    │       ├── is_interactable == true? → interactable_clicked.emit()
    │       └── is_interactable == false? → return silently
    │
    └── Interactable Designer connects:
        interactive_area.interactable_clicked → _start_dialogue()
```

### Flow 4: NPC Interaction with Feedback

```
Player approaches NPC
    │
    ├── body_entered on NPC's InteractionTrigger
    │   ├── NPCNode: shows VisualName + InteractionPrompt labels
    │   ├── InteractiveArea (new child): proximity glow activates
    │
Player hovers cursor over NPC
    ├── mouse_entered on InteractiveArea
    │   └── Decal glow + scale pulse on NPC's VisualName parent (if wireframe mesh)
    │
Player clicks NPC
    ├── input_event on NPC's InteractionTrigger
    │   └── NPCNode._on_interaction() → set_state(TALKING)
    │       └── NPCNode sets is_interactable = false on InteractiveArea
    │           └── Click suppressed; visual feedback suppressed
    │
Dialogue ends → state returns to IDLE
    └── NPCNode sets is_interactable = true on InteractiveArea
```

---

## 5. Edge Cases & Error Handling

| Edge Case | Mitigation |
|-----------|-----------|
| Rapid mouse movement across multiple interactables | Each InteractiveArea manages its own independent Tween — no global state. Fade-in/out chain cleanly. |
| Player inside zone at scene load | `body_entered` fires during `_ready()` if player spawns inside zone. Mitigation: use `set_deferred("monitoring", true)` or check a scene-transition-in-progress flag. |
| Overlapping InteractiveAreas | Both show feedback simultaneously. This is correct behavior if both are interactive. Scene authors should spatially separate zones if undesirable. |
| NPC in TALKING state + hover | `is_interactable = false` suppresses click; feedback could still show decal/light. Consider suppressing visual feedback entirely when state != IDLE via `feedback_mode = INDICATOR_ONLY`. |
| Dialogue active during hover | `is_interactable` set false via PlayerController's `dialogue_mode_changed` signal connection. |
| Scale pulse on zero-scale or tiny objects | Clamp minimum scale delta to 0.01 to avoid invisible pulsing. |
| Decal on non-horizontal surface (wall) | Default decal projects downward. Export `decal_orientation: Vector3` for manual rotation on wall decals. |
| Glow texture not found | Check texture at `_ready()`: `if not tex: push_warning(...)` |
| Parent mesh removed at runtime | All scale pulse operations check `is_instance_valid(_parent_node)` |
| Missing CollisionShape3D | Add `_ready()` warning: no CollisionShape3D child → no signals fire |
| Multiple players (split-screen, future) | `body_entered` fires once per body. `player` group check ensures only the local player triggers. No mitigation needed for single-player. |
| Memory on scene unload | InteractiveArea and children freed with parent via Godot's scene tree — no orphan nodes. |

---

## 6. Per-Scene / Per-Component Configuration

### Scene: office.tscn

| Trigger | Feedback Mode | Decal Size | Glow Color | Notes |
|:-------:|:------------:|:----------:|:----------:|-------|
| OfficeDoorTrigger | HOVER_ONLY | (0.8, 0.8) | `#FFAA55` | Blend with door frame; existing EKeyTrigger unchanged |

### Scene: convenience_store.tscn

| Trigger | Feedback Mode | Decal Size | Notes |
|:-------:|:------------:|:----------:|-------|
| StoreExitTrigger | HOVER_ONLY | (0.6, 0.6) | Small exit zone near counter |

### Scene: street.tscn

| Trigger | Feedback Mode | Decal Size | Notes |
|:-------:|:------------:|:----------:|-------|
| StoreEntranceTrigger | HOVER_ONLY | (0.8, 0.8) | Entrance glow on store threshold |
| ExitZoneToOffice | HOVER_ONLY | (0.6, 0.6) | Sibling InteractiveArea alongside ExitZone |
| ExitZoneToStore | HOVER_ONLY | (0.6, 0.6) | Sibling InteractiveArea alongside ExitZone |

### Scene: lobby.tscn

| Trigger | Feedback Mode | Decal Size | Notes |
|:-------:|:------------:|:----------:|-------|
| SecurityGuardTrigger | HOVER_ONLY | (0.6, 0.6) | Near guard position |
| StrangerTrigger | HOVER_ONLY | (0.8, 0.8) | Slightly larger for critical character |
| ExitTrigger | HOVER_ONLY | (0.6, 0.6) | Exit zone highlight |

### Scene: bridge.tscn

| Trigger | Feedback Mode | Decal Size | Notes |
|:-------:|:------------:|:----------:|-------|
| RailingTrigger | HOVER_ONLY | (0.5, 0.5) | Smaller, railing-edge |
| HomelessTrigger | HOVER_ONLY | (0.8, 0.8) | Near homeless character |
| BridgeExitTrigger | HOVER_ONLY | (0.6, 0.6) | Exit zone |

### Scene: underpass.tscn

| Trigger | Feedback Mode | Decal Size | Notes |
|:-------:|:------------:|:----------:|-------|
| GraffitiTrigger | HOVER_ONLY | (0.6, 0.6) | Wall graffiti |
| StrangerEchoTrigger | HOVER_ONLY | (0.8, 0.8) | Critical dialogue point |
| UnderpassExitTrigger | HOVER_ONLY | (0.6, 0.6) | Exit zone |

### Scene: subway_station.tscn

| Trigger | Feedback Mode | Decal Size | Notes |
|:-------:|:------------:|:----------:|-------|
| TicketGateTrigger | HOVER_ONLY | (0.8, 0.8) | Ending path trigger |
| TurnBackTrigger | HOVER_ONLY | (0.8, 0.8) | Ending path trigger |
| BenchTrigger | HOVER_ONLY | (0.8, 0.8) | Ending path trigger |

---

## 7. Integration Points

| Integration | Component | How |
|-------------|-----------|-----|
| InteractiveArea → SceneBase | Scene trigger script | Scene's existing `input_event` handler is replaced by or forwarded from InteractiveArea's `interactable_clicked` signal |
| InteractiveArea → NPCNode | NPC trigger script | Either NPCNode's existing `InteractionTrigger` (Area3D) wraps InteractiveArea? Or InteractiveArea is a sibling. Decision: sibling — NPCNode's InteractionTrigger handles `body_entered` for labels, InteractiveArea handles `mouse_entered` for visual feedback |
| InteractiveArea → PlayerController | Player proximity | PlayerController's `_nearby_interactables` stack unaffected — InteractiveArea's Area3D already has `body_entered`/`body_exited` for visual feedback; player's `interaction_area` is a separate Area3D on the player body |
| InteractiveArea → LoFiText3D | Hover feedback on text | InteractiveArea's `hovered` signal can be connected to LoFiText3D's `emissive_strength` to increase text glow on hover |
| InteractiveArea → DialogueBalloon | State gating | Dialogue runner sets `is_interactable = false` via NPCNode during dialogue; can also be wired via PlayerController's `dialogue_mode_changed` |

---

## 8. File Manifest

### New Files

| File | Type | Lines (est.) |
|------|------|:-----------:|
| `gdscripts/interactive_area.gd` | GDScript | ~250 |
| `gdscripts/interactive_feedback.gdshader` | Shader | ~25 |
| `gdscripts/npc_indicator.gd` | GDScript | ~60 |
| `assets/textures/glow_amber.webp` | Image | N/A |
| `assets/textures/icon_interact.webp` | Image | N/A |
| `assets/textures/icon_important.webp` | Image | N/A |

### Modified Files

| File | Nature of Change |
|------|-----------------|
| `gdscripts/npc_node.gd` | Add InteractiveArea child, wire state-dependent gating |
| `gdscripts/player_controller.gd` | Optional: add `interactable_hovered` signal |
| `scenes/office/office.tscn` | Add InteractiveArea to OfficeDoorTrigger |
| `scenes/store/convenience_store.tscn` | Add InteractiveArea to StoreExitTrigger |
| `scenes/street/street.tscn` | Add InteractiveArea to StoreEntranceTrigger + ExitZones |
| `scenes/lobby/lobby.tscn` | Add InteractiveArea to Guard/Stranger/Exit triggers |
| `scenes/bridge/bridge.tscn` | Add InteractiveArea to Railing/Homeless/Exit triggers |
| `scenes/underpass/underpass.tscn` | Add InteractiveArea to Graffiti/StrangerEcho/Exit triggers |
| `scenes/subway_station/subway_station.tscn` | Add InteractiveArea to Gate/TurnBack/Bench triggers |

### Removed/Deprecated Files

None.

### Affected Test Files

| Test File | Nature of Change |
|-----------|-----------------|
| `tests/unit/test_npc_node.gd` | Add tests for InteractiveArea child creation and state gating |
| `tests/unit/test_player_controller.gd` | Add tests for optional `interactable_hovered` signal |
| New: `tests/unit/test_interactive_area.gd` | Add unit tests for InteractiveArea feedback, signals, and edge cases |

---

## 9. Test Case Descriptions

> Note: Test descriptions only — no runnable test code. The implement agent writes test scripts.

### Scenario A: InteractiveArea Construction and Defaults

- **Test A1**: `InteractiveArea` with `feedback_mode = BOTH` creates `_hover_decal`, `_proximity_light`, and connects `mouse_entered`/`mouse_exited`/`body_entered`/`body_exited`/`input_event` signals.
- **Test A2**: `InteractiveArea` with `feedback_mode = HOVER_ONLY` creates `_hover_decal` but no `_proximity_light`.
- **Test A3**: `InteractiveArea` with `feedback_mode = INDICATOR_ONLY` and a valid `indicator_texture` creates `_indicator_sprite` with correct pixel_size and position offset.
- **Test A4**: `InteractiveArea` with `feedback_mode = BOTH` and no `parent_mesh` set does NOT attempt scale pulse.
- **Test A5**: `InteractiveArea` with missing `CollisionShape3D` child prints a `push_warning` at `_ready()`.

### Scenario B: Hover Feedback

- **Test B1**: Simulate `mouse_entered` → `_is_hovered = true`, decal material alpha starts tween toward `glow_color.a`, `hovered` signal emitted.
- **Test B2**: Simulate `mouse_exited` after B1 → `_is_hovered = false`, decal alpha tweens to 0.0, `unhovered` signal emitted.
- **Test B3**: `mouse_entered` with `_parent_node` set → scale pulse tween starts looping.
- **Test B4**: `mouse_exited` with active scale pulse → scale pulse stops, parent node scale returns to `Vector3.ONE`.

### Scenario C: Proximity Feedback

- **Test C1**: `body_entered` with body in `player` group → `_is_nearby = true`, proximity light energy tweens to `light_energy`, `proximity_entered` emitted.
- **Test C2**: `body_entered` with body NOT in `player` group → no change.
- **Test C3**: `body_exited` with player group body → `_is_nearby = false`, light energy tweens to 0.0, `proximity_exited` emitted.
- **Test C4**: `body_entered` then `body_exited` rapidly → tween chain handles without visual flicker.

### Scenario D: Click Gating

- **Test D1**: `input_event` with left-click and `is_interactable = true` → `interactable_clicked` signal emitted.
- **Test D2**: `input_event` with left-click and `is_interactable = false` → signal NOT emitted, function returns silently.
- **Test D3**: `input_event` with non-left-click event (right-click, motion) → no signal emitted regardless of `is_interactable`.

### Scenario E: Indicator Pulse

- **Test E1**: `InteractiveArea` with `indicator_texture` set → indicator sprite alpha pulses between 0.4 and 0.8 at `pulse_duration` cycle.
- **Test E2**: Indicator pulse continues independently of hover/proximity state changes.

### Scenario F: NPCNode Integration

- **Test F1**: `NPCNode._ready()` creates an `InteractiveArea` child with `feedback_mode = BOTH` and appropriate NPC indicator texture.
- **Test F2**: When NPC transitions to `TALKING` state, `is_interactable` is set `false` on the InteractiveArea.
- **Test F3**: When NPC transitions back to `IDLE`, `is_interactable` is restored to `true`.

### Scenario G: Edge Cases

- **Test G1**: Rapid `mouse_entered`/`mouse_exited` across 3 zones in 0.5s → each zone's tween runs independently, no cross-zone interference.
- **Test G2**: Player spawns inside InteractiveArea zone at scene load → `body_entered` may fire during `_ready()`. Monitoring should be deferred by 0.5s (or `transition_in_progress` checked).
- **Test G3**: `glow_color` alpha set to 0.0 → decal effectively invisible. Feedback still fires, but no visual change.
- **Test G4**: Two overlapping InteractiveAreas → both show feedback simultaneously. No crash, no performance issue.

---

## 10. Implementation Phases

| Phase | Priority | Components | Est. |
|:-----:|:--------:|-----------|:----:|
| Phase 1 | P0 | InteractiveArea.gd script + npc_indicator.gd | 1 day |
| Phase 2 | P0 | Asset textures (glow_amber, icon_interact, icon_important) | 0.5 day |
| Phase 3 | P1 | NPCNode integration (add InteractiveArea child, state gating) | 0.5 day |
| Phase 4 | P1 | 8 scene TSCN modifications (office, store, street, lobby, bridge, underpass, subway) | 1 day |
| Phase 5 | P2 | PlayerController optional enhancement (interactable_hovered signal) | 0.5 day |
| Phase 6 | P2 | Edge-outline shader (interactive_feedback.gdshader) | 0.5 day |
| Phase 7 | P2 | Unit tests | 0.5 day |

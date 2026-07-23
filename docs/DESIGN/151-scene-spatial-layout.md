# Design: #151 — Scene Spatial Layout — Place all 3D text objects at correct coordinates

> Parent Issue: #151
> Agent: plan-agent
> Date: 2026-07-24

---

## 1. Architecture Overview

### Core Idea

Place four pre-built component scenes (`RainText`, `LamppostText`, `PuddleText`, `NeonSign`) as **new instance nodes** inside `scenes/street/street.tscn` at authored world coordinates along the player walking path. The existing inline `Label3D` nodes (NeonSign, Graffiti, StreetSign) are **preserved** — the component instances supplement rather than replace them, providing 5-state variant behavior from Issue #154 without breaking any `@onready` node path references in `street.gd`.

`WorldLabel` in `main.tscn` remains at `(0, 0, -5)` with `visible = false` — unchanged.

### Walking Path Layout

```
SpawnPoint (0, 0, -3)
    │
    ▼ walk forward (Z+)
StreetSign (2, 2, -3)    ← existing inline Label3D
    │
    ▼
LamppostText (3, 1.5, -3)  ← NEW component, beside Streetlamp pole
    │
    ▼
RainText (3, 2.5, 0)       ← NEW component, street center overhead
    │
    ▼ walk toward store
PuddleText (0, 0.1, 2)      ← NEW component, ground reflection at path midpoint
    │
    ▼
NeonSign (4.5, 2.5, 3)    ← NEW component (NeonSignInstance), same position as inline
    │
    ▼
StoreEntranceTrigger (4.5, 0.5, 1)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Component placement strategy | **Sibling** — add as new instances, keep inline Label3Ds | `street.gd` has `@onready var neon_sign: Node3D = $Environments/NeonSign` — replacing the inline would break this path. Sibling instances get unique names and don't affect existing node references |
| Component instance naming | Use distinct node names (e.g. `NeonSignInstance`, `RainTextInstance`) | Avoids name collision with existing `Environments/NeonSign` node while keeping the relationship clear |
| `street.gd` modifications | **None required** | Each component inherits from `TextComponentBase` and connects to `StateSystem` / `NarrativeManager` signals in its own `_ready()`. No scene-script plumbing needed |
| `WorldLabel` visibility | Keep `visible = false` | Debug HUD retained for future debugging; removal out of scope |
| Coordinate system | Godot units (meters), Y+ up, Z+ forward | Matches existing scene convention and player controller parameters |
| Billboard mode | All components use `billboard = true` (set in their `.tscn` files) | Ensures text is always readable regardless of player viewing angle |

### Correction to PRD

The PRD's requirement table labels `LamppostText` as will-axis and `RainText` as hope-axis. This is confirmed by the actual source (`lamppost_text.gd` uses `state.get("will", 5.0)`, `rain_text.gd` uses `state.get("hope", 5.0)`). No discrepancy.

However, the PRD's Implementation Notes section shows component instance syntax with node names that would shadow existing nodes (e.g. `RainText` instead of `RainTextInstance`). The DESIGN doc explicitly uses distinct node names to avoid name conflicts with existing inline nodes in the same parent (`Environments`).

---

## 2. Scene Tree Changes

### `scenes/street/street.tscn` — 4 New Component Instances

All four new nodes are added under `Environments/` (the same parent as existing inline NeonSign, Graffiti, and StreetSign).

```ascii
StreetRoot (Node3D)
  ├── SpawnPoint (Marker3D)            [ (0, 0, -3) ]
  ├── Environments (Node3D)
  │   ├── StreetSurface (StaticBody3D)
  │   ├── BuildingLeft (StaticBody3D)
  │   ├── BuildingRight (StaticBody3D)
  │   ├── StoreFront (StaticBody3D)
  │   ├── Streetlamp (StaticBody3D)
  │   ├── NeonSign (Label3D)           [INLINE — preserved, (4.5, 2.5, 3)]
  │   ├── Graffiti (Label3D)           [INLINE — preserved, (-4.5, 0.5, 3)]
  │   ├── StreetSign (Label3D)         [INLINE — preserved, (2, 2, -3)]
  │   ├── RainTextInstance (Label3D)   [NEW — instance of rain_text.tscn, (3, 2.5, 0)]
  │   ├── LamppostTextInstance (Label3D) [NEW — instance of lamppost_text.tscn, (3, 1.5, -3)]
  │   ├── PuddleTextInstance (Label3D) [NEW — instance of puddle_text.tscn, (0, 0.1, 2)]
  │   └── NeonSignInstance (Label3D)   [NEW — instance of neon_sign.tscn, (4.5, 2.5, 3)]
  ├── InteractionZones (Node3D)
  └── ...
```

#### Instance Syntax (TSCN format)

For each of the four new nodes, the corresponding `ext_resource` is already registered (only one `PackedScene` is needed per component type, but since no component `.tscn` is currently loaded in `street.tscn`, new `ext_resource` entries are required):

```gdscript
[ext_resource type="PackedScene" path="res://scenes/components/rain_text.tscn" id="6_rain_text"]
[ext_resource type="PackedScene" path="res://scenes/components/lamppost_text.tscn" id="7_lamppost_text"]
[ext_resource type="PackedScene" path="res://scenes/components/puddle_text.tscn" id="8_puddle_text"]
[ext_resource type="PackedScene" path="res://scenes/components/neon_sign.tscn" id="9_neon_sign"]
```

Node definitions:

```gdscript
[node name="RainTextInstance" parent="Environments" instance=ExtResource("6_rain_text")]
position = Vector3(3, 2.5, 0)

[node name="LamppostTextInstance" parent="Environments" instance=ExtResource("7_lamppost_text")]
position = Vector3(3, 1.5, -3)

[node name="PuddleTextInstance" parent="Environments" instance=ExtResource("8_puddle_text")]
position = Vector3(0, 0.1, 2)

[node name="NeonSignInstance" parent="Environments" instance=ExtResource("9_neon_sign")]
position = Vector3(4.5, 2.5, 3)
```

### `scenes/main.tscn` — No Changes

`WorldLabel` is already present at `(0, 0, -5)` with `visible = false`. No modifications required.

---

## 3. GDScript / Logic Layer

### No Script Changes Required

Each component scene already has its own script (`rain_text.gd`, `lamppost_text.gd`, `puddle_text.gd`, `neon_sign.gd`) that extends `TextComponentBase`. In `_ready()`, each component:

1. Calls `super._ready()` which sets up the lo-fi shader material
2. Connects to `/root/StateSystem` for `state_changed` signals
3. Connects to `/root/NarrativeManager` for `scene_text_changed` signals
4. Applies the initial variant based on current state

Because the components handle their own signal wiring and variant selection, **no changes to `street.gd` are needed**. The scene script's existing methods (`_set_graffiti_text`, `_set_neon_modulate`) continue to control the inline Label3D nodes independently.

#### Verification: `street.gd` Node Path Safety

| `@onready` in `street.gd` | Target | Conflict? |
|---|---|---|
| `$Environments/NeonSign` | Inline Label3D → NeonSign | No — new instance is `NeonSignInstance` |
| `$Environments/Graffiti` | Inline Label3D → Graffiti | No — no new node named Graffiti |
| `$Environments/StreetSign` | Inline Label3D → StreetSign | No — no new node named StreetSign |
| `$InteractionZones/StoreEntranceTrigger` | Area3D | No — no new nodes in InteractionZones |
| `$InteractionZones/TestNPC/InteractionTrigger/EKeyTrigger` | Area3D | No — no new nodes in TestNPC subtree |

No node path collisions.

---

## 4. Data Flow

```
Scene load (street.tscn)
    │
    ├── street.gd._ready()
    │     └── _configure_environmental_text()
    │           ├── graffiti.text = tone-variant text     [inline Label3D]
    │           └── neon_sign.modulate = tone color       [inline Label3D]
    │
    └── Component instances (4x)
          │
          ├── RainTextInstance._ready()
          │     ├── self._setup_material()                [lo-fi shader]
          │     └── _on_state_changed(state)              [variant 0-4]
          │
          ├── LamppostTextInstance._ready()
          │     ├── self._setup_material()
          │     └── _on_state_changed(state)              [will axis]
          │
          ├── PuddleTextInstance._ready()
          │     ├── self._setup_material()
          │     └── _on_state_changed(state)              [hope axis]
          │
          └── NeonSignInstance._ready()
                ├── self._setup_material()
                └── _on_state_changed(state)              [conviction axis]

Mid-scene state change:
    StateSystem emits state_changed({hope, will, conviction, ...})
        │
        ├── street.gd._on_narrative_tone_changed(scene_id, tone)
        │     └── Updates inline Label3D colors/text     [inline only]
        │
        └── Each component._on_state_changed(state)
              └── _calculate_state_id(state)
                    └── _apply_variant_for_state(state_id)
                          └── Fade transition (0.3s)
```

---

## 5. Test Case Descriptions

> **Note:** These are scenario descriptions for manual verification and future automated testing. No executable test files are produced at the plan phase.

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Component instance positions | ✅ 4 (one per component) | ✅ 2 (z-fighting, off-screen) | ✅ 1 (missing ext_resource) |
| Node path safety | ✅ 4 (existing @onready vars) | ✅ 1 (name collision) | — |
| 5-state variant behavior | ✅ 4 (one per component) | ✅ 2 (null variant data, axis divergence) | ✅ 1 (missing autoloads) |
| WorldLabel visibility | ✅ 1 | — | — |

### Test Cases

#### Position Correctness

**TC1-N: RainTextInstance at correct world position**
| Field | Value |
|-------|-------|
| **Type** | Normal Path |
| **Scenario** | RainText component instance appears in street scene |
| **Setup** | Load `scenes/street/street.tscn` in editor |
| **Steps** | 1. Select `Environments/RainTextInstance` node. 2. Read `position` in Inspector |
| **Expected** | `position = Vector3(3, 2.5, 0)` |
| **Verification** | Inspector shows `x=3.0, y=2.5, z=0.0`. Billboard mode is enabled. |

**TC2-N: LamppostTextInstance at correct world position**
| Field | Value |
|-------|-------|
| **Type** | Normal Path |
| **Scenario** | LamppostText component instance appears in street scene |
| **Setup** | Load `scenes/street/street.tscn` in editor |
| **Steps** | 1. Select `Environments/LamppostTextInstance` node. 2. Read `position` |
| **Expected** | `position = Vector3(3, 1.5, -3)` |
| **Verification** | Inspector shows `x=3.0, y=1.5, z=-3.0`. Node is child of `Environments`. |

**TC3-N: PuddleTextInstance at correct ground position**
| Field | Value |
|-------|-------|
| **Type** | Normal Path |
| **Scenario** | PuddleText at near-ground height |
| **Setup** | Load `scenes/street/street.tscn` in editor |
| **Steps** | 1. Select `Environments/PuddleTextInstance`. 2. Read `position` |
| **Expected** | `position = Vector3(0, 0.1, 2)` — Y=0.1 avoids z-fighting with ground plane at Y=-0.5 |
| **Verification** | Inspector shows `y=0.1`. Surface is at Y=-0.5 (CSGBox3D center offset), so text is ~0.6 above actual ground surface. |

**TC4-N: NeonSignInstance at correct storefront position**
| Field | Value |
|-------|-------|
| **Type** | Normal Path |
| **Scenario** | NeonSign component at storefront position matching inline NeonSign |
| **Setup** | Load `scenes/street/street.tscn` in editor |
| **Steps** | 1. Select `Environments/NeonSignInstance`. 2. Read `position` |
| **Expected** | `position = Vector3(4.5, 2.5, 3)` — same position as inline `Environments/NeonSign` |
| **Verification** | Inspector values match. Both nodes at identical position (layered visual effect). |

**TC5-E: WorldLabel remains at position with visible=false**
| Field | Value |
|-------|-------|
| **Type** | Edge Case |
| **Scenario** | WorldLabel in main.tscn is unchanged |
| **Setup** | Load `scenes/main.tscn` in editor |
| **Steps** | 1. Select `WorldLabel` node. 2. Read `position` and `visible` |
| **Expected** | `position = Vector3(0, 0, -5)`, `visible = false` |
| **Verification** | Position unchanged. Visible checkbox unchecked. |

#### Node Path Safety

**TC6-E: Existing street.gd @onready references resolve correctly**
| Field | Value |
|-------|-------|
| **Type** | Edge Case |
| **Scenario** | All five `@onready` node paths in `street.gd` still resolve after adding component instances |
| **Setup** | Open `scenes/street/street.tscn` in editor, inspect `StreetRoot` node |
| **Steps** | 1. Select `StreetRoot` (which has `street.gd` attached). 2. Check the Remote Inspector (or run scene and check debugger for null reference errors) |
| **Expected** | No `null reference` or `Invalid get index` errors. `Environments/NeonSign`, `Environments/Graffiti`, `Environments/StreetSign` all resolve to their inline Label3D nodes |
| **Verification** | Scene loads without script errors. All five `@onready` paths resolve to valid nodes. |

#### 5-State Variant Behavior

**TC7-N: RainTextInstance responds to state change (hope axis)**
| Field | Value |
|-------|-------|
| **Type** | Normal Path |
| **Scenario** | Component applies correct variant when StateSystem emits a state change |
| **Setup** | Run scene with StateSystem autoload. Set `hope = 1.0` (despair) |
| **Steps** | 1. Trigger `state_changed({hope: 1.0})`. 2. Observe `RainTextInstance` text and emissive |
| **Expected** | Variant index 0 applied. Text matches `rain_text_very_low.tres` content. Emissive doubled per `rain_text.gd._apply_variant()` special case for state 1 |
| **Verification** | `text` property updated. `emissive_strength` is `2x` the variant's base value. |

**TC8-N: LamppostTextInstance responds to state change (will axis)**
| Field | Value |
|-------|-------|
| **Type** | Normal Path |
| **Scenario** | Component uses will axis independently of hope |
| **Setup** | Run scene. Set `hope = 9.0, will = 1.0` |
| **Steps** | 1. Trigger `state_changed({hope: 9.0, will: 1.0})`. 2. Observe `LamppostTextInstance` |
| **Expected** | LamppostText shows variant 0 (despair) because will=1.0 ≤ 2.0, despite hope being high |
| **Verification** | Text content and emissive match low/despair variant. Demonstrates axis independence from hope. |

**TC9-E: Component with null variant data entry doesn't crash**
| Field | Value |
|-------|-------|
| **Type** | Edge Case |
| **Scenario** | If a variant_data slot is null or empty, component gracefully no-ops |
| **Setup** | (Manual editor check) Open each component `.tscn` file, verify `variant_data` array |
| **Steps** | 1. Select component node. 2. Check `variant_data` in Inspector |
| **Expected** | Each component has a populated `variant_data` array (5 entries). No null entries. `TextComponentBase._apply_variant_data()` checks `if not data: return` |
| **Verification** | All 5 variants present per component. No null entries. |

#### Failure Paths

**TC10-F: Missing ext_resource blocks scene load**
| Field | Value |
|-------|-------|
| **Type** | Failure Path |
| **Scenario** | If any component `.tscn` ext_resource ID is missing or wrong, Godot reports parse error |
| **Setup** | Open `scenes/street/street.tscn` in editor |
| **Steps** | 1. Verify all 4 `[ext_resource]` entries for components exist. 2. Verify IDs match the `[node instance=ExtResource(...)]` references |
| **Expected** | No parse errors. All 4 ext_resources: `6_rain_text`, `7_lamppost_text`, `8_puddle_text`, `9_neon_sign` are defined before any `[node]` block referencing them |
| **Verification** | Scene loads without errors. Four component instances appear under `Environments/`. |

**TC11-F: Component instances without autoloads degrade gracefully**
| Field | Value |
|-------|-------|
| **Type** | Failure Path |
| **Scenario** | If `StateSystem` or `NarrativeManager` autoloads are not available, components don't crash |
| **Setup** | Run scene without autoloads (or instantiate component in isolation) |
| **Steps** | 1. Create `RainText` standalone. 2. Call `_ready()` |
| **Expected** | `get_node_or_null("/root/StateSystem")` returns `null`. `get_node_or_null("/root/NarrativeManager")` returns `null`. No crash. Text shows with default lo-fi shader settings |
| **Verification** | Component displays with initial variant (index 2 / neutral). No `null reference` errors in output. |

---

## 6. Component Instance Coordinate Summary

| Component | Parent | Position | Instance Of | Axis | Notes |
|-----------|--------|----------|-------------|------|-------|
| `RainTextInstance` | `Environments` | `(3, 2.5, 0)` | `rain_text.tscn` | hope | Overhead rain text in street center; player walks toward it from SpawnPoint |
| `LamppostTextInstance` | `Environments` | `(3, 1.5, -3)` | `lamppost_text.tscn` | will | Beside Streetlamp pole at Y=1.5 (half pole height); visible on spawn |
| `PuddleTextInstance` | `Environments` | `(0, 0.1, 2)` | `puddle_text.tscn` | hope | Ground reflection at path midpoint; Y slightly above ground to avoid z-fighting |
| `NeonSignInstance` | `Environments` | `(4.5, 2.5, 3)` | `neon_sign.tscn` | conviction | Same position as inline NeonSign; layered visual effect. Billboard for readability |

---

## 7. Files Changed

| Type | File | Change | Est. Lines |
|------|------|--------|-----------|
| Scene | `scenes/street/street.tscn` | **Modify** — add 4 `[ext_resource]` entries + 4 `[node instance=...]` blocks + position overrides | +30 |
| Doc | `docs/DESIGN/151-scene-spatial-layout.md` | **New** — this document | +300 |

No other files are modified:
- `scenes/main.tscn` — WorldLabel already at correct position; no change
- `gdscripts/street.gd` — No node path collision with new instance names; no change
- `gdscripts/*.gd` (component scripts) — No logic changes; positions handled in scene file
- `scenes/components/*.tscn` — No changes; position is overridden at the instance level in street.tscn

---

## 8. Verification Checklist

- [ ] `RainTextInstance` in `street.tscn` has `position = (3, 2.5, 0)` — Inspector confirms
- [ ] `LamppostTextInstance` in `street.tscn` has `position = (3, 1.5, -3)` — Inspector confirms
- [ ] `PuddleTextInstance` in `street.tscn` has `position = (0, 0.1, 2)` — Inspector confirms
- [ ] `NeonSignInstance` in `street.tscn` has `position = (4.5, 2.5, 3)` — Inspector confirms
- [ ] `WorldLabel` in `main.tscn` still at `(0, 0, -5)`, `visible = false`
- [ ] All 4 components have `billboard = true` (set in their `.tscn` files)
- [ ] Existing inline `NeonSign` (Label3D) still present at `(4.5, 2.5, 3)` with `text = "YOU'RE STILL HERE"`
- [ ] Existing inline `Graffiti` (Label3D) still present at `(-4.5, 0.5, 3)`
- [ ] Existing inline `StreetSign` (Label3D) still present at `(2, 2, -3)`
- [ ] No `@onready` node path in `street.gd` is broken (all 5 paths resolve)
- [ ] Scene loads without parse errors or null references
- [ ] Each component's `variant_data` array has 5 populated entries
- [ ] Component instances appear in the correct parenting under `Environments/`

# Research: Text Component Library

> Parent Issue: #49
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project has a working Lo-Fi 3D text rendering system (`gdscripts/lo_fi_text_3d.gd`, `shaders/lo_fi_text.gdshader`) built on Godot 4.7's `Label3D` node. Each scene script currently duplicates environmental text configuration logic inline:

- **Office** (`office.gd`): `window_text`, `screensaver_text`, `desktop_text` — hand-configured with manual `match` blocks per tone
- **Lobby** (`lobby.gd`): `entrance_text`, `stranger_spotlight` — tone-based text switching inline
- **Store** (`store.gd`): `open_sign` — simple condition-based text
- **Street** (`street.gd`): `neon_sign`, `graffiti`, `street_sign` — per-element state mapping inline
- **Bridge** (`bridge.gd`): `traffic_text`, `homeless_text`, `rain_bridge_text` — tone + intrusive thought logic inline
- **Underpass** (`underpass.gd`): `graffiti_text`, `echo_text`, `underpass_light` — tone + echo trigger inline
- **Subway Station** (`subway_station.gd`): `ticket_gate_text`, `clock_text`, `broadcast_text`, `stranger_final_text` — tone + ending logic inline

This leads to:
- No reusable scene components for common text types (neon signs, rain text, puddles, street lamps)
- Each scene re-implements visual response to GameState changes (hope/despair/conviction)
- Text variants (shallow/middle/deep) exist only implicitly via tone mapping, not as a structured system
- No standardized way to define how a text component's appearance changes with player state

### Expected Behavior

A **Text Component Library** of reusable `Label3D`-based scene components (`rain_text`, `neon_sign`, `puddle_text`, `lamppost_text`) that:

1. Each component is a self-contained `.tscn` scene file with pre-configured `lo_fi_text_3d.gd` script
2. Each component has exported parameters for state-driven visual variation (color, intensity, text content variants)
3. Components expose a standardized API: `set_state_tier(tier: String)`, `set_tone(tone: String)`, `set_text_variant(variant: int)`
4. Components have **3 layered text variants** (shallow → middle → deep) that map to hope/despair ranges, per the issue's acceptance criteria
5. Components connect to `NarrativeManager.scene_text_changed` or `StateSystem.state_changed` for reactive updates
6. The library is referenced by scene scripts instead of duplicating text configuration

### User Scenarios

- **Scenario A (Scene Builder):** A developer drops `RainText.tscn` into a bridge scene and sets `conviction_response = "inverse"`. The rain text automatically becomes more fragmented as conviction drops, without writing any per-scene code.
- **Scenario B (State Integration):** A `NeonSign.tscn` placed above a store entrance listens to `NarrativeManager.scene_text_changed`. When the tone shifts to "cold", the neon color transitions from warm amber to dim red and the sign flickers faster.
- **Scenario C (Deep Layer):** A `PuddleText.tscn` on the street reflects not just the tone but subtle inner state — at high despair, the text itself becomes fragmented (missing letters, broken words), visually mirroring the player's mental state.
- **Frequency:** Every 3D scene (6 scenes) uses 3-6 text components each. The library will be instantiated 20-40 times across the game.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project evolved feature-by-feature: PRD #44 (Lo-Fi 3D Text Rendering) delivered the base `Label3D` + shader infrastructure. PRD #45 (Narrative Architecture) delivered `SceneBase`, `StateSystem`, `NarrativeManager`. Each scene script then wired these systems together ad-hoc during implementation. The "text component" as a reusable unit was never designed — each scene's text was treated as a one-off config.

### Why Change Now?

All six scenes are in the Plan/Implement phase (Issues #55, #58, #59). Before more environmental text code is written, a component library eliminates duplication and ensures consistency:

1. **Duplication cost**: Every scene script currently repeats the same `match tone:` → `$Label3D.text = ...` pattern. With 6 scenes × 4 text elements = 24 text nodes, this is ~240 lines of near-identical code.
2. **Deep layer requirement**: AC3 demands that components "subtly reflect inner state" — e.g., rain text fragments at despair. This requires structured text variant data, not match blocks.
3. **Future-proofing**: Adding a new scene should mean instantiating components, not re-implementing text logic.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static typing) |
| Renderer | `forward_plus` |
| Resolution | 1920×1080, Allow HiDPI |
| Theme | Edward Hopper urban night — warm/amber light on dark/cool backgrounds |
| Existing infrastructure | `lo_fi_text_3d.gd`, `lo_fi_text.gdshader`, `StateSystem`, `NarrativeManager`, `SceneBase` |
| Text base class | `Label3D` via `lo_fi_text_3d.gd` (extends `Label3D`) |
| State signals | `StateSystem.state_changed(state: Dictionary)`, `NarrativeManager.scene_text_changed(scene_id: String, tone: String)`, `NarrativeManager.echo_triggered(echo_id: String, variant: int)` |
| Platform | macOS / Linux |
| Performance budget | No physics/action; 3-8 text elements per scene |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `docs/PRD/49-text-component-library.md` | PRD | **New** — This document |
| `scenes/components/rain_text.tscn` (new) | Rain Text Component | **New** — Pre-configured Label3D for rain-related text |
| `scenes/components/neon_sign.tscn` (new) | Neon Sign Component | **New** — Pre-configured Label3D for neon signs |
| `scenes/components/puddle_text.tscn` (new) | Puddle Text Component | **New** — Pre-configured Label3D for puddle reflections |
| `scenes/components/lamppost_text.tscn` (new) | Lamppost Text Component | **New** — Pre-configured Label3D for lamppost glow text |
| `gdscripts/text_component_base.gd` (new) | Component Base | **New** — Base class extending `lo_fi_text_3d.gd` with state response API |
| `gdscripts/text_variant_data.gd` (new) | Variant Data | **New** — Data structure for 3-tier text variants (shallow/middle/deep) |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/office.gd` | Office scene | Should use RainText/NeonSign components instead of inline text config |
| `gdscripts/lobby.gd` | Lobby scene | Should use LamppostText component |
| `gdscripts/store.gd` | Store scene | Should use NeonSign component |
| `gdscripts/street.gd` | Street scene | Should use all 4 components |
| `gdscripts/bridge.gd` | Bridge scene | Should use RainText + LamppostText |
| `gdscripts/underpass.gd` | Underpass scene | Should use PuddleText + LamppostText |
| `gdscripts/subway_station.gd` | Subway Station scene | Should use components for clock/broadcast text |
| `gdscripts/scene_base.gd` | SceneBase | May add helper method for batch component binding |
| `tests/test_text_component_library.gd` (new) | Tests | **New** — Test suite for component library |
| `docs/DESIGN/49-text-component-library.md` | Design doc | Plan phase will produce design document |

### Data Flow Impact

```
Text Component Library Architecture

TextVariantData (Resource)
  │  ┌── shallow: {text, shader_params}
  │  ├── middle: {text, shader_params}
  │  └── deep:   {text, shader_params}
  │
  ▼
TextComponentBase (extends LoFiText3D)
  │  - set_state_tier(tier) → selects variant
  │  - set_tone(tone) → overrides color params
  │  - set_text_variant(idx) → manual variant select
  │
  ├── RainText
  │   rain_text.tscn: pre-configured for rain-scene text
  │   - Variants map to hope/conviction tiers
  │   - Deep layer: text fragments at despair
  │
  ├── NeonSign
  │   neon_sign.tscn: emissive + billboard pre-set
  │   - Variants map to conviction tiers
  │   - Deep layer: flicker rate increases at low conviction
  │
  ├── PuddleText
  │   puddle_text.tscn: ground-level, mirror effect
  │   - Variants map to hope tiers
  │   - Deep layer: text becomes inverted/unreadable at despair
  │
  └── LamppostText
      lamppost_text.tscn: overhead glow text
      - Variants map to will tiers
      - Deep layer: color temperature shifts with will

Signal Wiring:
  StateSystem.state_changed
    → TextComponentBase._on_state_changed
    → set_state_tier(calculate_tier(state))
    → select_text_variant(current_variant_index)

  NarrativeManager.scene_text_changed
    → TextComponentBase._on_tone_changed
    → apply_tone_overrides(tone)
    → override emissive_color, emissive_strength
```

### Documents to Update

- [x] **This output:** `docs/PRD/49-text-component-library.md`
- [ ] `docs/DESIGN/49-text-component-library.md` (Plan phase output)
- [ ] `docs/REFERENCE/component-library.md` (Plan phase reference)
- [ ] `gdscripts/office.gd` — Refactor to use components
- [ ] `gdscripts/street.gd` — Refactor to use components
- [ ] `gdscripts/bridge.gd` — Refactor to use components
- [ ] `gdscripts/underpass.gd` — Refactor to use components
- [ ] `gdscripts/subway_station.gd` — Refactor to use components

---

## 4. Solution Comparison

### Approach A: Component Base Class + Resource-Driven Variants

**Description:**

Create a `TextComponentBase.gd` extending `LoFiText3D` which provides:
- A `set_state_tier(tier: String)` method that maps "low"/"mid"/"high" tiers to text variants
- A `TextVariantData` custom `Resource` that holds 3 variant records: each with `text: String`, `emissive_color: Color`, `emissive_strength: float`, `pixel_factor: float`, `color_bits: int`, `scanline_intensity: float`
- Each component type (RainText, NeonSign, etc.) extends `TextComponentBase` with its own `TextVariantData` resource
- Components connect to `StateSystem.state_changed` and `NarrativeManager.scene_text_changed` in `_ready()`
- Deep layer (AC3): each variant record includes a `fragment_text: String` that replaces `text` at extreme state values

**Pros:**
- Clean data-driven design — text content and visual params live in `.tres` resource files, not code
- Resource separation: designers can edit text content without touching GDScript
- Standardized API across all 4 components
- Easy to add new components (just create a `.gd` + `.tscn` + `.tres`)
- Deep layer is a first-class field in the variant resource, not a hack
- Existing `NarrativeManager.echo_triggered` signal can integrate naturally

**Cons:**
- Requires new `.tres` resource files + editor setup in Godot
- TextComponentBase adds a layer of abstraction on top of LoFiText3D — slight learning curve
- Need to refactor existing scene scripts to use components (6 scenes affected)
- Resource files can't be hot-reloaded during gameplay

**Risk:** Low — Godot 4.7's Resource system is mature. `.tres` files are version-control-friendly.

**Effort:** 5 files (base class, variant resource, 4 components × .tscn, test) — ~300 lines total

---

### Approach B: Singleton Text Config Manager with Inline Components

**Description:**

Create a `TextComponentManager` autoload singleton that holds all text variant data as Dictionaries (keyed by component type × tier). Each scene's text nodes keep their inline `_configure_environmental_text()` method but call the manager to get the current text/params instead of hard-coding them.

**Pros:**
- No new scene files — text nodes remain as Label3D children of each scene
- No refactor of scene hierarchy — just change how `_configure_environmental_text()` fetches data
- Singleton is easy to access from any scene script
- Dictionaries are simpler than custom Resources for prototype phase

**Cons:**
- No visual components to drag-and-drop — each scene must manually discover and configure nodes
- No standardized API — each scene still has its own wiring
- Deep layer (AC3) requires per-scene conditional logic again
- No encapsulation — all text data lives in one monolithic singleton
- Doesn't truly provide a "component library" — just a data refactor
- Harder to unit test (singleton state)

**Risk:** Low-Medium — works for shallow/middle but doesn't satisfy the "library" intent.

**Effort:** 3 files (manager singleton, data file, test updates) — ~200 lines

---

### Approach C: Scene Tree Template Instances via @onready + Module Script

**Description:**

Create a single `TextComponentModule.gd` script that can be added to any scene root. It autodiscovers all Label3D nodes with a specific group (`text_component`) and applies state-driven text variant logic from a centralized data structure. Each Label3D node is tagged with metadata in the editor (e.g., `component_type = "neon_sign"` via `set_meta`).

**Pros:**
- No new `.tscn` files or base classes — uses existing node hierarchy
- Single script per scene for all text management
- Group-based discovery is Godot-idiomatic
- Easy to retrofit onto existing scenes

**Cons:**
- Requires all scenes to carry the module node
- Metadata-based component typing is fragile (mistyped metadata = silent failure)
- No visual component encapsulation — can't see a "neon sign" as a coherent unit in the editor
- Deep layer variation logic becomes complex conditional chains
- Doesn't produce reusable "components" in the Godot sense
- No editor preview — text content is determined at runtime

**Risk:** Medium — metadata-based discovery is fragile and not debuggable easily.

**Effort:** 2 files (module script, data dictionary) — ~150 lines

---

### Comparison Summary

| Dimension | A: Component Base + Resources | B: Singleton Manager | C: Module Script |
|-----------|-------------------------------|---------------------|------------------|
| Reusability | ★★★★★ | ★★☆☆☆ | ★★★☆☆ |
| Encapsulation | ★★★★★ | ★★☆☆☆ | ★★★☆☆ |
| Editor integration | ★★★★☆ | ★☆☆☆☆ | ★★☆☆☆ |
| Refactor effort | ★★☆☆☆ | ★★★★☆ | ★★★★☆ |
| Deep layer support | ★★★★★ | ★★★☆☆ | ★★★☆☆ |
| Testability | ★★★★★ | ★★☆☆☆ | ★★★☆☆ |
| Maintenance burden | ★★★★★ | ★★★☆☆ | ★★★☆☆ |
| Godot 4.7 idiomatic | ★★★★★ | ★★★☆☆ | ★★★☆☆ |

### Recommendation

→ **Approach A (Component Base Class + Resource-Driven Variants)** because:

1. **It produces actual reusable components** — `.tscn` files that can be dragged into any scene, with state-driven behavior baked in
2. **Deep layer (AC3)** is a native feature: each variant record has a `fragment_text` field that activates at extreme state values
3. **Resource-driven design** separates content from code — text changes don't require script edits
4. **Standardized API** (`set_state_tier`, `set_tone`, `set_text_variant`) means scene scripts are dramatically simpler
5. **Testability**: each component can be instantiated in isolation and tested with synthetic state values
6. **Future-proof**: adding a new component (e.g., `billboard_text.tscn`) means one new file, not changes across 6 scenes

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. Create `TextVariantData.tres` template resource defining: `{ text, emissive_color, emissive_strength, pixel_factor, color_bits, scanline_intensity, fragment_text }` for 3 tiers (shallow/middle/deep)
2. Create `TextComponentBase.gd` extending `LoFiText3D` with:
   - Exported `variant_data: Array[Resource]` (3 TextVariantData resources)
   - `set_state_tier(tier: String)` → selects variant by tier index (low=0, mid=1, high=2)
   - `set_tone(tone: String)` → optional color override per tone name
   - `set_text_variant(idx: int)` → manual variant selection
   - `_on_state_changed(state: Dictionary)` → calculate tier and apply
   - `_on_tone_changed(scene_id: String, tone: String)` → apply tone overrides
3. Create 4 component scenes:
   - `RainText.tscn` — configurable rain-related text, 3 variants mapped to hope/conviction
   - `NeonSign.tscn` — emissive billboard, conviction-mapped variants
   - `PuddleText.tscn` — ground-level text, hope-mapped variants
   - `LamppostText.tscn` — overhead glow text, will-mapped variants
4. Each component has shallow/middle/deep `.tres` variant files
5. Wire components to `StateSystem.state_changed` and `NarrativeManager.scene_text_changed`
6. Verify in `test_3d_text.tscn` or a new test scene

### Edge Cases

1. **No StateSystem available:** Components should fall back to neutral (mid tier) without crashing
2. **Rapid state changes:** Multiple `state_changed` signals in quick succession should not cause flicker — debounce or use last-value-wins
3. **Empty variant data:** If `variant_data` array has < 3 entries, pad with defaults (fallback to component's exported default params)
4. **Fragment text empty:** `fragment_text = ""` means no fragmentation effect at extreme tier — component degrades gracefully to just using `text`
5. **Multiple components listening to same signal:** All 4 components in a scene can share one connection to `StateSystem.state_changed` — no per-component signal overhead
6. **Tone override for non-neon components:** Tone overrides (from `NarrativeManager.scene_text_changed`) should only affect `emissive_color`/`emissive_strength` — text content is driven by tier, not tone

### Failure Paths

1. **Component not connected to state signals:** Falls back to initial `variant_data[1]` (mid tier) — text renders but doesn't react to state changes. Mitigation: warn in debug mode if no signal connection after 1 second.
2. **Resource path broken:** If `.tres` file is moved or deleted, component uses exported defaults (no crash). Mitigation: use `preload()` with fallback defaults.
3. **NarrativeManager missing:** `scene_text_changed` signal not available — component uses tier-based variants only (tone overrides disabled). Not a blocker.
4. **Fragment text too long:** Extreme fragmentation at deep tier should not make text unreadable — keep fragment text ≤ 80% of original text length.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #44 — Lo-Fi 3D Text Rendering (lo_fi_text_3d.gd, lo_fi_text.gdshader) | ✅ Complete | Low — existing and tested |
| Issue #43 — Project scaffold refinement | Backlog | Low — scene component directory creation only |
| Godot 4.7 Resource system (.tres files) | Stable | Low — mature API |
| StateSystem (state_system.gd) | ✅ Complete | Low — state_changed signal exists |
| NarrativeManager (narrative_manager.gd) | ✅ Complete | Low — scene_text_changed + echo_triggered signals exist |
| TextVariantData Resource | Needs creation | Low — ~20 lines of GDScript |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Scene refactoring (Issues #55, #58, #59) | Critical — scenes need to use components instead of inline text |
| Adding new text types (watermark text, clock text, broadcast text) | Medium — new component types can be added anytime |
| Inspector editor plugin for TextVariantData | Low — nice-to-have for designers |

### Preparation Needed

- [ ] Create `scenes/components/` directory
- [ ] Design TextVariantData Resource schema
- [ ] Define 3 text variant strings per component (shallow/middle/deep) — content to be written by narrative designer
- [ ] Verify `NarrativeManager.scene_text_changed` signal signal is correctly wired in existing scenes

---

## 7. Spike / Experiment (Optional — depth/deep only)

### Question to Answer

Can a custom `Resource` class in GDScript (extending `Resource`) hold all the visual parameter overrides needed to fully reconfigure a `LoFiText3D` component's appearance, including deep-layer fragmentation text?

### Method

1. Write a minimal `TextVariantData.gd` extending `Resource` with fields:
   ```gdscript
   class_name TextVariantData
   extends Resource
   
   @export var text: String = ""
   @export var emissive_color: Color = Color(0, 0, 0, 0)
   @export var emissive_strength: float = 0.0
   @export var pixel_factor: float = 0.5
   @export var color_bits: int = 8
   @export var scanline_intensity: float = 0.15
   @export var fragment_text: String = ""
   ```
2. Create a `.tres` file from the resource in the editor
3. Assign the `.tres` to a TextComponentBase instance in a test scene
4. Call `set_state_tier("low")` and verify all parameters update correctly
5. Verify that `fragment_text` replaces `text` at the extreme tier

### Result

Expected: GDScript custom Resources work fully in Godot 4.7 — `@export` fields are editable in the inspector, `.tres` files serialize correctly, and runtime parameter reassignment works. The `fragment_text` field integrates seamlessly because it's just another string that replaces `text` at runtime.

Risk: If `TextVariantData` resources have issues with `Array[Resource]` export (Godot 4.7's array export sometimes requires manual inspector setup), fall back to a Dictionary-based variant data approach stored directly in the component script.

### Impact on Approach

If the Resource approach works (expected), Approach A is validated for Plan phase. If resource arrays are buggy in Godot 4.7, use an exported `Variant` (Dictionary) instead of `Array[Resource]` — the component base class API stays the same, only the storage format changes.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The Godot 4.7 CRPG project currently has Lo-Fi 3D text rendering (Issue #44) fully implemented: `gdscripts/lo_fi_text_3d.gd` extends `Label3D` with pixel_factor, color_bits, scanline_intensity, emissive_color, and emissive_strength; `shaders/lo_fi_text.gdshader` applies screen-space pixelation and color quantization; `tests/test_lo_fi_text_3d.gd` validates all get/set/clamp behavior.

The narrative systems (Issue #45) provide: `StateSystem` (hope/conviction/will axes with `state_changed` signal), `NarrativeManager` (scene sequence, tone calculation, echo system with `scene_text_changed` and `echo_triggered` signals), and `SceneBase` (base class with `_configure_environmental_text()` hook).

Six scene scripts currently duplicate environmental text configuration inline using `match` blocks and `@onready` node references. The proposed approach (Approach A — Component Base + Resource Variants) introduces:

1. `gdscripts/text_component_base.gd` — extends `LoFiText3D` with `set_state_tier()`, `set_tone()`, `set_text_variant()` methods, wired to state signals
2. `gdscripts/text_variant_data.gd` — `Resource` class holding per-tier text + shader param overrides + fragment text for deep layer
3. 4 component `.tscn` files in `scenes/components/`: `rain_text.tscn`, `neon_sign.tscn`, `puddle_text.tscn`, `lamppost_text.tscn`

The main risk is Godot 4.7's `Array[Resource]` export behavior — if it requires manual inspector setup, switch to an exported Dictionary approach while keeping the same API. The spike/experiment section validates this in Plan phase.

The secondary risk is refactoring existing scene scripts — 6 scenes need text configuration moved from `_configure_environmental_text()` to component properties. This is mechanical work with low technical risk but requires verifying each component renders identically to the current inline version.

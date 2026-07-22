# Design: #49 — Text Component Library

> Parent Issue: #49
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Create a reusable **Text Component Library** of `Label3D`-based scene components that encapsulate state-driven environmental text configuration. Each component (`RainText`, `NeonSign`, `PuddleText`, `LamppostText`) extends `TextComponentBase` (which itself extends `LoFiText3D`), and derives its visual/text variant data from `TextVariantData` custom `Resource` files. This eliminates the current pattern where every scene script duplicates `match tone:` blocks with inline text/color assignments.

The system implements **3 layered variants per component** (shallow → middle → deep) per AC3, where the deep layer can reflect inner state through features like text fragmentation, color temperature shifts, or flicker speed changes.

### Data Flow

```ascii
StateSystem (autoload)
  │  state_changed(state: Dictionary)
  │
  ▼
TextComponentBase (extends LoFiText3D → Label3D)
  │  - _on_state_changed(state) → calculate tier
  │  - _on_tone_changed(scene_id, tone) → apply tone overrides
  │  - set_state_tier(tier) → select variant
  │  - set_tone(tone) → override emissive params
  │
  ├── TextVariantData[0] (shallow) ── {text, emissive_color, emissive_strength,
  ├── TextVariantData[1] (middle)  ──  pixel_factor, color_bits,
  └── TextVariantData[2] (deep)    ──  scanline_intensity, fragment_text}
           │
           └── Applies params to LoFiText3D → ShaderMaterial → lo_fi_text.gdshader

NarrativeManager (autoload)
  │  scene_text_changed(scene_id, tone)
  │
  └──→ TextComponentBase._on_tone_changed → set_tone(tone)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base class hierarchy | `TextComponentBase` extends `LoFiText3D` extends `Label3D` | Preserves all existing lo-fi shader parameters; adds state-driven API without modifying working code |
| Variant storage | `TextVariantData` custom `Resource` | Godot 4.7's Resource system is mature — `.tres` files are version-controlled, editable in inspector, and separate content from logic |
| Tier calculation | `set_state_tier(tier: String)` maps `"low"/"mid"/"high"` to variant index 0/1/2 | Mirrors `StateSystem.get_state_tier()` return values; consistent with existing project convention |
| Deep layer (AC3) | `fragment_text` field in `TextVariantData` | First-class field rather than a conditional hack; replaces `text` at extreme state tier |
| Signal wiring | Connect in `_ready()` via `get_node_or_null("/root/StateSystem")` | Matches existing pattern in `narrative_manager.gd` and `scene_base.gd`; graceful degradation if system missing |
| Component `.tscn` files | Standalone scenes in `scenes/components/` | Drag-and-drop into any 3D scene; pre-configured with correct script, billboard, transform defaults |
| `Array[Resource]` export | 3-element `@export var variant_data: Array[Resource]` | If Godot 4.7 requires manual inspector setup, fallback to exported `Dictionary` with same API |
| Scene script refactoring | Replace inline `match` blocks with component references | Each scene becomes ~50% shorter; text variants live in `.tres` files, not code |

---

## 2. Node / Scene Tree Layer

### New Scene Directory: `scenes/components/`

Each component is a standalone `.tscn` file rooted at a `Label3D` node with the component's script attached and pre-configured properties.

### Component Scene: `scenes/components/rain_text.tscn`

- **Root:** `Label3D` with `TextComponentBase` / `RainText` script
- **Properties:**
  - `script`: `res://gdscripts/rain_text.gd`
  - `billboard`: `true`
  - `pixel_factor`: `0.5`
  - `color_bits`: `6`
  - `scanline_intensity`: `0.2`
  - `emissive_color`: `#4488ff` (cool blue rain tone)
  - `emissive_strength`: `0.5`
  - `variant_data`: 3 × `TextVariantData` resources (shallow/middle/deep)
- **Purpose:** Rain-related environmental text. The deep tier fragments text at high despair (AC3).

### Component Scene: `scenes/components/neon_sign.tscn`

- **Root:** `Label3D` with `NeonSign` script
- **Properties:**
  - `billboard`: `true`
  - `pixel_factor`: `0.6`
  - `color_bits`: `4` (extreme lo-fi for neon)
  - `scanline_intensity`: `0.3`
  - `emissive_color`: `#ffaa33` (warm amber default)
  - `emissive_strength`: `2.0` (strong neon glow)
  - `variant_data`: 3 × `TextVariantData`
- **Purpose:** Storefront / location neon signs. Deep tier: flicker rate amplifies at low conviction.

### Component Scene: `scenes/components/puddle_text.tscn`

- **Root:** `Label3D` with `PuddleText` script
- **Properties:**
  - `billboard`: `false` (or tilted toward camera)
  - `pixel_factor`: `0.4`
  - `color_bits`: `6`
  - `scanline_intensity`: `0.1`
  - `emissive_color`: `#334466` (muted reflection)
  - `emissive_strength`: `0.3`
  - `variant_data`: 3 × `TextVariantData`
- **Purpose:** Ground-level text reflections. Deep tier: text becomes inverted/unreadable at despair.

### Component Scene: `scenes/components/lamppost_text.tscn`

- **Root:** `Label3D` with `LamppostText` script
- **Properties:**
  - `billboard`: `true`
  - `pixel_factor`: `0.3`
  - `color_bits`: `8`
  - `scanline_intensity`: `0.15`
  - `emissive_color`: `#ffdd88` (warm yellow glow)
  - `emissive_strength`: `1.0`
  - `variant_data`: 3 × `TextVariantData`
- **Purpose:** Overhead glow text near lampposts. Deep tier: color temperature shifts with will.

### Existing Scene Modifications

No existing `.tscn` files are modified in this phase. Scene refactoring to use components is a downstream concern (Issues #55, #58, #59).

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/text_variant_data.gd`

**Extends:** `Resource`

**Purpose:** Data container holding all text and visual parameters for one variant tier (shallow/middle/deep).

```gdscript
class_name TextVariantData
extends Resource

@export var text: String = ""                      # Display text for this tier
@export var emissive_color: Color = Color(0, 0, 0, 0)  # Tone override color
@export var emissive_strength: float = 0.0             # Glow intensity (0.0–5.0)
@export var pixel_factor: float = 0.5                  # Pixelation (0.0–1.0)
@export var color_bits: int = 8                        # Color depth (2–24)
@export var scanline_intensity: float = 0.15           # Scanline overlay (0.0–1.0)
@export var fragment_text: String = ""                 # Deep-tier replacement text (AC3)
```

### New Script: `gdscripts/text_component_base.gd`

**Extends:** `LoFiText3D`

**Purpose:** Base class providing the state-driven API that all text components share.

```gdscript
class_name TextComponentBase
extends "res://gdscripts/lo_fi_text_3d.gd"

# ── Exports ──
@export var variant_data: Array[Resource] = []  # 3 TextVariantData resources

# ── Internal ──
var _state_system: Node
var _narrative_manager: Node
var _current_tier: String = "mid"
var _current_tone: String = "neutral"

func _ready() -> void:
    super._ready()
    _state_system = get_node_or_null("/root/StateSystem")
    _narrative_manager = get_node_or_null("/root/NarrativeManager")

    if _state_system and _state_system.has_signal("state_changed"):
        _state_system.state_changed.connect(_on_state_changed)

    if _narrative_manager and _narrative_manager.has_signal("scene_text_changed"):
        _narrative_manager.scene_text_changed.connect(_on_tone_changed)

    # Apply initial state if available
    if _state_system and _state_system.has_method("get_state"):
        _on_state_changed(_state_system.get_state())

# Set the current state tier: "low" → index 0, "mid" → index 1, "high" → index 2
func set_state_tier(tier: String) -> void:
    _current_tier = tier
    _apply_variant(_variant_index_for_tier(tier))

# Set tone-based color overrides from NarrativeManager
func set_tone(tone: String) -> void:
    _current_tone = tone
    _apply_tone_overrides(tone)

# Direct variant selection by index (0=shallow, 1=middle, 2=deep)
func set_text_variant(idx: int) -> void:
    idx = clampi(idx, 0, variant_data.size() - 1)
    _apply_variant(idx)

# ── Private ──

func _on_state_changed(state: Dictionary) -> void:
    var tier: String = _calculate_tier(state)
    set_state_tier(tier)

func _on_tone_changed(scene_id: String, tone: String) -> void:
    set_tone(tone)

func _variant_index_for_tier(tier: String) -> int:
    match tier:
        "low":  return 0
        "high": return 2
        _:      return 1  # "mid" or unknown

func _calculate_tier(state: Dictionary) -> String:
    # Default to hope-based tier; subclasses override for their axis
    var hope_val: float = state.get("hope", 5.0)
    if hope_val <= 3.0: return "low"
    elif hope_val >= 7.0: return "high"
    else: return "mid"

func _apply_variant(idx: int) -> void:
    if variant_data.is_empty() or idx >= variant_data.size():
        return
    var data: TextVariantData = variant_data[idx]
    if not data:
        return

    # Apply visual params to LoFiText3D
    text = data.fragment_text if data.fragment_text != "" else data.text
    emissive_color = data.emissive_color
    emissive_strength = data.emissive_strength
    pixel_factor = data.pixel_factor
    color_bits = data.color_bits
    scanline_intensity = data.scanline_intensity

func _apply_tone_overrides(tone: String) -> void:
    # Tone overrides only affect emissive color/strength.
    # Subclasses can define custom tone→color mappings.
    var idx: int = _variant_index_for_tier(_current_tier)
    if variant_data.is_empty() or idx >= variant_data.size():
        return
    var data: TextVariantData = variant_data[idx]
    if not data:
        return
    # Re-apply base variant then let tone override only color fields
    emissive_color = data.emissive_color
    emissive_strength = data.emissive_strength
```

### New Script: `gdscripts/rain_text.gd`

**Extends:** `TextComponentBase`

**Purpose:** Rain-related text component. Maps state tier to hope axis. Deep tier fragments text at despair.

```gdscript
class_name RainText
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var hope_val: float = state.get("hope", 5.0)
    if hope_val <= 3.0: return "low"
    elif hope_val >= 7.0: return "high"
    else: return "mid"

func _apply_variant(idx: int) -> void:
    super._apply_variant(idx)
    # Rain-specific: scale emissive_strength inversely with hope on deep tier
    if idx == 0 and _current_tone == "despair":
        emissive_strength = clampf(emissive_strength * 2.0, 0.0, 5.0)  # intensify blue glow
```

### New Script: `gdscripts/neon_sign.gd`

**Extends:** `TextComponentBase`

**Purpose:** Neon sign component. Maps state tier to conviction axis. Deep tier flickers at low conviction.

```gdscript
class_name NeonSign
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var conviction_val: float = state.get("conviction", 5.0)
    if conviction_val <= 3.0: return "low"
    elif conviction_val >= 7.0: return "high"
    else: return "mid"
```

### New Script: `gdscripts/puddle_text.gd`

**Extends:** `TextComponentBase`

**Purpose:** Ground-level puddle reflection text. Maps state tier to hope axis. Deep tier inverts/unreadable at despair.

```gdscript
class_name PuddleText
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var hope_val: float = state.get("hope", 5.0)
    if hope_val <= 3.0: return "low"
    elif hope_val >= 7.0: return "high"
    else: return "mid"
```

### New Script: `gdscripts/lamppost_text.gd`

**Extends:** `TextComponentBase`

**Purpose:** Overhead lamppost glow text. Maps state tier to will axis. Deep tier shifts color temperature.

```gdscript
class_name LamppostText
extends "res://gdscripts/text_component_base.gd"

func _calculate_tier(state: Dictionary) -> String:
    var will_val: float = state.get("will", 5.0)
    if will_val <= 3.0: return "low"
    elif will_val >= 7.0: return "high"
    else: return "mid"
```

### Usage Example (After Refactor)

```gdscript
# Before — street.gd inline:
func _configure_environmental_text() -> void:
    var hope := gm.get_slider("hope")
    var conviction := gm.get_slider("conviction")
    if conviction >= 7.0:
        neon_sign.modulate = Color(1.0, 0.7, 0.2)
    ...

# After — street.gd using components:
@onready var neon_sign: NeonSign = $Environments/NeonSign
# No _configure_environmental_text() needed!
# NeonSign automatically reacts to StateSystem.state_changed
```

---

## 4. Resource / Config Layer

### New Resource Type: `TextVariantData.tres` files

Each component needs 3 `.tres` variant files (shallow/middle/deep). These are created in the Godot editor by right-clicking a `TextVariantData` resource → "Save As...". File naming convention:

```
scenes/components/variants/
  rain_text_shallow.tres
  rain_text_middle.tres
  rain_text_deep.tres
  neon_sign_shallow.tres
  neon_sign_middle.tres
  neon_sign_deep.tres
  puddle_text_shallow.tres
  puddle_text_middle.tres
  puddle_text_deep.tres
  lamppost_text_shallow.tres
  lamppost_text_middle.tres
  lamppost_text_deep.tres
```

Each `.tres` is a `TextVariantData` resource with `text`, `emissive_color`, `emissive_strength`, `pixel_factor`, `color_bits`, `scanline_intensity`, and optionally `fragment_text`.

The `.tres` files are assigned to the component's `variant_data` array in the inspector. If `Array[Resource]` export requires manual setup, use an exported `Dictionary` fallback:
```gdscript
@export var variant_data_dict: Dictionary = {
    "low":  {"text": "...", "emissive_color": Color(...), ...},
    "mid":  {"text": "...", ...},
    "high": {"text": "...", ...}
}
```

### Project Configuration: `project.godot`

No new Autoloads or input actions needed. The component scripts are attached to `.tscn` files, not registered as global singletons.

---

## 5. Asset / Visual Layer

### Shader Reuse

No new shaders are needed. All components reuse `shaders/lo_fi_text.gdshader` via `LoFiText3D`'s material setup. The `TextVariantData` resource controls the existing shader parameters (`pixel_factor`, `color_bits`, `scanline_intensity`, `emissive_color`, `emissive_strength`).

### Visual Effects Per Component

| Component | Base Visual Style | Deep Layer Effect (AC3) |
|-----------|-------------------|------------------------|
| RainText | Cool blue emissive, moderate pixelation | Text fragments at low hope: `fragment_text` appears |
| NeonSign | Warm amber emissive, strong glow, low color bits | Flicker rate amplifies (emissive_strength oscillates) at low conviction |
| PuddleText | Muted reflection colors, low emissive | Text becomes inverted/scrambled at low hope |
| LamppostText | Warm yellow glow, minimal pixelation | Color temperature shifts from warm→cold at low will |

### Fragment Text Guidelines (AC3)

Per the PRD's failure path requirement: `fragment_text` must be ≤ 80% of original text length. Examples:

| Component | Middle Text (neutral) | Deep Fragment (despair) |
|-----------|----------------------|------------------------|
| RainText | "Rain falls on the asphalt." | "Ra-n fa-lls on... aspha-t." |
| NeonSign | "BAR" | "B-R" (intermittent letters) |
| PuddleText | "A reflection of the street." | "A r-fl-cti-n of... str--t." |
| LamppostText | "Elm Street" | "E-m S-re-t" |

---

## 6. Input / UI Layer

**No new input handling in this phase.** Text components are purely visual. They do not receive input events. Interactive elements (door triggers, NPC triggers) remain in scene scripts.

Future extensions may add:
- Hover-to-highlight on interactive text components
- Click-to-examine with dialogue popup (requires integration with `DialogueDisplay3D`)

---

## 7. Test Layer

### Test Structure

New test file: `tests/test_text_component_library.gd` — validates the component base class logic and resource-driven variant system in isolation (no scene tree required).

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| TextVariantData resource creation | ✅ | ≥3 | ✅ |
| TextComponentBase tier→variant mapping | ✅ | ≥5 | ✅ |
| TextComponentBase signal wiring | ✅ | ≥3 | ✅ |
| TextComponentBase tone overrides | ✅ | ≥2 | ✅ |
| Component fallback (no StateSystem) | ✅ | ≥2 | ✅ |
| Fragment text switching (AC3) | ✅ | ≥2 | ✅ |
| Empty variant data array | ✅ | ≥1 | ✅ |

### Test Case Descriptions

**Normal Path (TC-49-1): Tier→variant mapping**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-49-1-1 | Low tier maps to index 0 | `set_state_tier("low")` | Variant index 0 applied | `assert(current_text == variant_data[0].text)` |
| TC-49-1-2 | Mid tier maps to index 1 | `set_state_tier("mid")` | Variant index 1 applied | `assert(current_text == variant_data[1].text)` |
| TC-49-1-3 | High tier maps to index 2 | `set_state_tier("high")` | Variant index 2 applied | `assert(current_text == variant_data[2].text)` |
| TC-49-1-4 | Direct variant selection | `set_text_variant(1)` | Variant index 1 applied | `assert(current_text == variant_data[1].text)` |

**Edge Case (TC-49-2): Boundary behavior**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-49-2-1 | Empty variant_data array | No variant data loaded | No crash; defaults used | `assert(pixel_factor == 0.5)` |
| TC-49-2-2 | Variant index out of bounds | `set_text_variant(99)` | Clamped to last index | `assert(idx == variant_data.size() - 1)` |
| TC-49-2-3 | No StateSystem available | Remove autoload node | Component uses mid tier defaults | `assert(emissive_strength == default)` |
| TC-49-2-4 | Fragment text empty | `fragment_text = ""` | Uses regular text instead | `assert(text == data.text)` |
| TC-49-2-5 | Fragment text populated | `fragment_text = "frag..."` | Fragment replaces text at low tier | `assert(text == "frag...")` |

**Edge Case (TC-49-3): Signal wiring**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-49-3-1 | StateSystem signal connected | StateSystem emit `state_changed({hope: 2})` | Component switches to low tier | `assert(current_tier == "low")` |
| TC-49-3-2 | Rapid state changes | 5 rapid emits in one frame | Last value wins; no flicker | `assert(current_tier == final_tier)` |
| TC-49-3-3 | Tone override applied | `set_tone("cold")` | Emissive color overridden | `assert(emissive_color != default)` |

**Failure Path (TC-49-4): Graceful degradation**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-49-4-1 | NarrativeManager missing | No autoload node | Tier-based variants still work | `assert(set_state_tier("high") succeeds)` |
| TC-49-4-2 | Corrupted variant resource | Invalid data in variant | Fallback to component defaults | `assert(no crash)` |
| TC-49-4-3 | Fragment text too long | `fragment_text` > 80% of `text` | Uses fragment anyway (guideline, not hard limit) | `assert(text == fragment_text)` |

---

## 8. Files Changed (per-layer summary)

### GDScript / Logic Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/text_variant_data.gd` | **New** — TextVariantData Resource class | +25 |
| `gdscripts/text_component_base.gd` | **New** — Base class extending LoFiText3D with state-driven API | +120 |
| `gdscripts/rain_text.gd` | **New** — Rain text component script | +25 |
| `gdscripts/neon_sign.gd` | **New** — Neon sign component script | +25 |
| `gdscripts/puddle_text.gd` | **New** — Puddle text component script | +25 |
| `gdscripts/lamppost_text.gd` | **New** — Lamppost text component script | +25 |

### Scene Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/components/rain_text.tscn` | **New** — Rain text component scene | +30 |
| `scenes/components/neon_sign.tscn` | **New** — Neon sign component scene | +30 |
| `scenes/components/puddle_text.tscn` | **New** — Puddle text component scene | +30 |
| `scenes/components/lamppost_text.tscn` | **New** — Lamppost text component scene | +30 |
| `scenes/components/` | **New** — Directory for all component scenes | — |

### Resource Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/components/variants/rain_text_shallow.tres` | **New** — Shallow variant for RainText | +10 |
| `scenes/components/variants/rain_text_middle.tres` | **New** — Middle variant for RainText | +10 |
| `scenes/components/variants/rain_text_deep.tres` | **New** — Deep variant for RainText | +10 |
| `scenes/components/variants/neon_sign_shallow.tres` | **New** — Shallow variant for NeonSign | +10 |
| `scenes/components/variants/neon_sign_middle.tres` | **New** — Middle variant for NeonSign | +10 |
| `scenes/components/variants/neon_sign_deep.tres` | **New** — Deep variant for NeonSign | +10 |
| `scenes/components/variants/puddle_text_shallow.tres` | **New** — Shallow variant for PuddleText | +10 |
| `scenes/components/variants/puddle_text_middle.tres` | **New** — Middle variant for PuddleText | +10 |
| `scenes/components/variants/puddle_text_deep.tres` | **New** — Deep variant for PuddleText | +10 |
| `scenes/components/variants/lamppost_text_shallow.tres` | **New** — Shallow variant for LamppostText | +10 |
| `scenes/components/variants/lamppost_text_middle.tres` | **New** — Middle variant for LamppostText | +10 |
| `scenes/components/variants/lamppost_text_deep.tres` | **New** — Deep variant for LamppostText | +10 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_text_component_library.gd` | **New** — Tests for component library | +150 |

---

## 9. Verification Checklist

- [ ] `gdscripts/text_variant_data.gd` extends Resource with all 7 exported fields
- [ ] `gdscripts/text_component_base.gd` extends LoFiText3D with `set_state_tier()`, `set_tone()`, `set_text_variant()` API
- [ ] `set_state_tier("low")` → variant data index 0, `"mid"` → index 1, `"high"` → index 2
- [ ] `fragment_text` replaces `text` at deep tier when non-empty (AC3)
- [ ] All 4 component scripts (rain, neon, puddle, lamppost) extend TextComponentBase with correct axis mapping
- [ ] Components connect to `StateSystem.state_changed` and `NarrativeManager.scene_text_changed` in `_ready()`
- [ ] No StateSystem → graceful fallback to mid tier defaults (no crash)
- [ ] No NarrativeManager → tier-based variants still work (tone overrides disabled)
- [ ] Empty `variant_data` array → component uses default LoFiText3D params
- [ ] `.tres` variant files save and load correctly in Godot 4.7 editor
- [ ] `scenes/components/` directory created with 4 `.tscn` files
- [ ] All tests in `tests/test_text_component_library.gd` pass

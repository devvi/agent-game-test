# DESIGN: GameState-World Feedback — Hope/Despair affects environment text

> Issue #154
> Phase: Implementation
> Date: 2026-07-23

---

## 1. Design Summary

**Purpose:** Connect the 5-state hope_despair slider to environmental text rendering. Every scene text object displays one of 5 authored variants depending on the player's emotional state. Text updates dynamically when the slider changes mid-scene with smooth fade transitions.

**Key Idea:** `TextComponentBase` is expanded from 3-tier (low/mid/high) to 5-state (state ID 1-5) variant selection. Scene scripts use `NarrativeManager.SCENE_TONES` via `SceneBase._get_tone_for_scene()` for tone lookup. Subclasses override `_calculate_state_id()` to use custom axes (will for LamppostText, conviction for NeonSign).

---

## 2. Architecture Changes

### 2.1 TextComponentBase (`gdscripts/text_component_base.gd`)

**Before (3-tier):**
- `_calculate_tier(state) → String` returning "low"/"mid"/"high"
- `_variant_index_for_tier(tier) → int` mapping low→0, mid→1, high→2
- `_on_state_changed()` → `set_state_tier(tier)` → `_apply_variant(idx)`

**After (5-state):**
- `_calculate_state_id(state) → int` returning 1-5 (can be overridden by subclasses)
- `_variant_index_for_state_id(state_id) → int` mapping 1→0, 2→1, 3→2, 4→3, 5→4
- Old methods retained for backward compatibility
- `_on_state_changed()` → `_apply_variant_for_state(state_id)`
- `_on_tone_changed()` handles both text and visual properties
- `_start_transition(data)` uses Tween for fade-out (0.12s) → swap → fade-in (0.18s)
- `transition_duration: float = 0.3` exported parameter

### 2.2 Subclass Axis Mapping

| Subclass | Axis | Mapping Function |
|----------|------|------------------|
| LamppostText | will | `_will_to_state_id()`: ≤2→1, ≤4→2, ≤6→3, ≤8→4, >8→5 |
| NeonSign | conviction | `_conviction_to_state_id()`: same mapping |
| PuddleText | hope | Inherits `_hope_to_state_id()` from base |
| RainText | hope | Inherits base + despair emissive multiplier at state 1 |

### 2.3 SceneBase (`gdscripts/scene_base.gd`)

New methods:
- `_get_tone_for_scene(scene_id) → String` — queries NarrativeManager's per-scene tone table
- `_get_tone_for_scene_state(scene_id, state_id) → String` — previews tone for specific state
- `_get_current_state_id() → int` — returns current state ID (1-5)
- `_connect_state_signals()` — connects to NarrativeManager.scene_text_changed
- `_on_narrative_tone_changed(scene_id, tone)` — handler for dynamic updates

### 2.4 Scene Script Refactoring

Each scene script:
1. Calls `_get_tone_for_scene(scene_id)` in `_configure_environmental_text()`
2. Overrides `_on_narrative_tone_changed()` for dynamic mid-scene updates
3. Provides 5-state variant text via `_set_*_text(tone)` or `_set_environment_text(tone)` methods

### 2.5 Variant Resources

8 new `.tres` files (very_low and very_high for 4 text component types):

| File | State | Purpose |
|------|-------|---------|
| `lamppost_text_very_low.tres` | 1 (Despair) | Dim, highly pixelated alley text |
| `lamppost_text_very_high.tres` | 5 (Hope) | Bright, clear "Elm Street — Home" |
| `puddle_text_very_low.tres` | 1 (Despair) | Dark, low-res "The street drowns" |
| `puddle_text_very_high.tres` | 5 (Hope) | Bright "Stars in the water" |
| `neon_sign_very_low.tres` | 1 (Despair) | Dim red "CLOSED" with heavy scanlines |
| `neon_sign_very_high.tres` | 5 (Hope) | Bright "WELCOME HOME" with high color depth |
| `rain_text_very_low.tres` | 1 (Despair) | Dark "The rain won't stop" |
| `rain_text_very_high.tres` | 5 (Hope) | Bright "The rain sounds like music" |

---

## 3. Data Flow

```
StateSystem.apply_choice({hope_despair: delta})
    │
    ├── state_changed(state) emitted
    │
    ├──► NarrativeManager._on_state_changed(state)
    │       └── scene_text_changed.emit(scene_id, tone_string)
    │               │
    │               ├──► TextComponentBase._on_tone_changed(scene_id, tone)
    │               │       ├── Calculate state_id from state system
    │               │       ├── _variant_index_for_state_id(state_id) → 0-4
    │               │       ├── _start_transition(data) → fade out → swap → fade in
    │               │
    │               └──► SceneBase._on_narrative_tone_changed(scene_id, tone)
    │                       └── _set_environment_text(tone) — updates scene-specific nodes
```

---

## 4. Fallback and Edge Cases

| Scenario | Behavior |
|----------|----------|
| variant_data has < 5 entries | Nearest index via `clampi(idx, 0, variant_data.size()-1)` |
| variant_data is empty | No-op (returns without crashing) |
| Null entry in variant_data | Null check: `if not data: return` |
| Rapid state changes | Active tween is killed, new tween starts |
| Scene unload during tween | Tween is child of text node, auto-freed with scene |
| No StateSystem autoload | `_hope_to_state_id(5.0)` → state 3 (neutral) |
| No NarrativeManager autoload | Falls back to WorldviewController tone lookup |

---

## 5. Files Changed

### Modified
- `gdscripts/text_component_base.gd` — 5-state expansion
- `gdscripts/lamppost_text.gd` — will axis mapping
- `gdscripts/neon_sign.gd` — conviction axis mapping
- `gdscripts/puddle_text.gd` — inherits hope axis (cleaned up)
- `gdscripts/rain_text.gd` — hope axis + despair multiplier
- `gdscripts/scene_base.gd` — tone lookup helpers + signal wiring
- `gdscripts/office.gd` — 5-state text + dynamic updates
- `gdscripts/street.gd` — 5-state graffiti/neon + dynamic updates
- `gdscripts/lobby.gd` — 5-state lobby text + dynamic updates
- `gdscripts/bridge.gd` — 5-state bridge text + dynamic updates
- `gdscripts/underpass.gd` — 5-state underpass text + dynamic updates
- `gdscripts/store.gd` — 5-state open sign + dynamic updates
- `gdscripts/subway_station.gd` — 5-state station text + dynamic updates
- `tests/run_tests.gd` — registered env text test suite

### Created
- `scenes/components/variants/lamppost_text_very_low.tres`
- `scenes/components/variants/lamppost_text_very_high.tres`
- `scenes/components/variants/puddle_text_very_low.tres`
- `scenes/components/variants/puddle_text_very_high.tres`
- `scenes/components/variants/neon_sign_very_low.tres`
- `scenes/components/variants/neon_sign_very_high.tres`
- `scenes/components/variants/rain_text_very_low.tres`
- `scenes/components/variants/rain_text_very_high.tres`
- `tests/unit/test_env_text_5_state.gd`
- `docs/DESIGN/154-gamestate-world-feedback-env-text.md`
- `docs/TASKS/154-gamestate-world-feedback-env-text.md`

---

## 6. Test Coverage (20 tests)

| ID | Test | Coverage |
|----|------|----------|
| ET-01 | variant_index_for_state_id | All 5 states + OOB clamping |
| ET-02 | hope_to_state_id | Boundaries: 0-10 mapped to 1-5 |
| ET-03 | calculate_state_id default | Hope axis with fallback |
| ET-04 | apply_variant_for_state | All 5 variants applied correctly |
| ET-05 | fallback small array | 3 variants, states 1-5 |
| ET-06 | fallback empty array | No crash on empty |
| ET-07 | null entry | No crash on null |
| ET-08 | LamppostText will axis | Will axis override |
| ET-09 | NeonSign conviction axis | Conviction axis override |
| ET-10 | PuddleText hope axis | Inherits base behavior |
| ET-11 | RainText despair multiplier | Emissive doubling at state 1 |
| ET-12 | Tone name to state ID | All tone names mapped |
| ET-13 | get_tone_for_scene | Fallback without autoloads |
| ET-14 | get_tone_for_scene_state | Fallback without NM |
| ET-15 | signal updates text | No crash on signal |
| ET-16 | signal wiring | Null autoloads handled |
| ET-17 | get_current_state_id | Fallback to 3 |
| ET-18 | get_tone_for_scene fallback | Neutral fallback |
| ET-19 | transition export default | 0.3s default |
| ET-20 | tween cancellation | Old tween killed on new |

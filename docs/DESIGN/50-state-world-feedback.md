# Design: #50 — State-World Feedback — Hope/Despair Slider System

> Parent Issue: #50
> Agent: plan-agent
> Date: 2026-07-22
> Depth: deep

---

## 1. Architecture Overview

### Core Idea

Unify the game's two overlapping state systems (GameState 0–100, StateSystem 0–10) under **StateSystem** by expanding its `hope` axis into a bipolar `hope_despair` slider (-10 to +10) with 5 discrete emotional states: Despair, Low, Neutral, Buoyant, Hope. Wire GameManager to delegate slider/flag queries to StateSystem. Expand WorldviewController from 3-tone to 5-state mapping. Add emotional pacing ("sticky" resistance at extremes) and disabled-choice rendering for slider-gated dialogue options.

This implements **Approach A** from the PRD: Unify Under StateSystem.

### Data Flow

```
Dialogue choice with effect
    │
    ├──► DialogueRunner._apply_effects()
    │       └──► GameManager.apply_slider_delta("hope_despair", delta)
    │               └──► StateSystem.apply_choice({"hope_despair": delta})
    │                       ├──► Clamp value to [-10, +10]
    │                       ├──► Apply emotional resistance (×0.5 near extremes)
    │                       ├──► Set internal hope = (hope_despair + 10) / 2
    │                       └──► Emit state_changed(get_state())
    │
    ├──► WorldviewController receives state_changed
    │       └──► _calculate_tone() → 5-state discrete ID (1–5)
    │       └──► world_text_changed.emit(state_id)  (replaces 3-tone prefix)
    │               └──► Scene scripts update environmental text variants
    │
    ├──► RainController receives state_changed
    │       └──► Map hope_despair → rain intensity (inverse)
    │       └──► More granular: 5 intensity levels instead of continuous
    │
    ├──► Next dialogue encounter
    │       └──► DialogueRunner._build_state_snapshot()
    │               └──► GameManager.get_slider("hope_despair") → real value
    │               └──► Condition evaluator gates choices against discrete ranges
    │
    └──► (Queued if mid-dialogue: flush on dialogue_ended)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Slider source | StateSystem (Approach A) | Single source of truth; existing signal wiring works; no synchronization risk |
| Slider range | -10 to +10 bipolar | Matches issue requirement; maps cleanly to 5 discrete states |
| 5-state mapping | Despair(-10–-6), Low(-5–-2), Neutral(-1–+1), Buoyant(+2–+5), Hope(+6–+10) | Symmetric around 0; even bucket sizes for natural distribution |
| StateSystem persistence | Already an autoload in project.godot | State persists across scene changes automatically |
| GameManager wiring | Delegate to StateSystem | GameManager already has the get_slider/apply_slider_delta API surface — just needs real implementation |
| Emotional resistance | ×0.5 multiplier at extremes (state 1 and 5) | Mild resistance provides best pacing (3-4 choices to escape Despair) |
| Mid-dialogue state changes | Queue; flush on dialogue_ended | Prevents jarring visual updates during active conversation |
| Dialogue gating style | Disabled (visible but grayed out) | Best balance of player agency and immersion |
| Legacy GameState | Deprecate; delegate internally to StateSystem | Avoid breaking existing references during transition |
| Rain intensity mapping | From conviction → hope_despair (inverse) | Larger emotional range; more dramatic visual feedback |

---

## 2. Engine / State Layer

### StateSystem Changes (`gdscripts/state_system.gd`)

**New property:**
- `hope_despair: float = 0.0` — bipolar slider (-10 to +10), authoritative source

**Modified:**
- `hope` remains 0–10 internally but is derived: `hope = (hope_despair + 10.0) / 2.0`
- `apply_choice(effect)` — accepts `"hope_despair"` key in effect dict; applies emotional resistance; clamps to [-10, +10]; updates hope/conviction/will accordingly
- `get_state()` — returns `{"hope_despair": ..., "hope": ..., "conviction": ..., "will": ...}`

**New methods:**
- `get_state_id() -> int` — returns 1–5 based on current `hope_despair`
- `apply_hope_despair_delta(delta: float) -> void` — applies delta with resistance, clamps, emits signal
- `_get_resistance_multiplier(delta: float) -> float` — returns ×1.0 for neutral states, ×0.5 for extreme states (same-direction delta), ×1.0 for opposite-direction delta

**Signal changes:**
- Existing `state_changed(state: Dictionary)` continues to fire — dictionary includes new `"hope_despair"` key
- (Optional) New `slider_state_changed(state_id: int)` for direct 5-state listeners

### GameManager Changes (`gdscripts/game_manager.gd`)

**Modified methods:**
- `get_slider(axis: String) -> float` — delegates to `/root/StateSystem`:
  - `"hope_despair"` → `StateSystem.hope_despair` (-10 to +10)
  - `"hope"` → `StateSystem.hope` (0 to 10, derived)
  - `"conviction"`, `"will"` → same as now (0 to 10)
  - Unknown axis → 0.0 with warning
- `apply_slider_delta(axis: String, delta: float)` — delegates to `StateSystem.apply_hope_despair_delta()` for `"hope_despair"` axis, existing behavior for others
- `has_flag()` / `get_flags()` / `set_flag()` — real flag storage (Dictionary), not stub

**New:**
- `_flags: Dictionary = {}` — internal flag storage
- `get_slider_list() -> Array` — returns all known axis names (for debug/dialogue tools)

### Emotional Resistance (in `StateSystem.apply_choice()`)

```
state_id = get_state_id()
if state_id == 1 (Despair) and delta > 0:
    delta *= 0.5   # Harder to escape despair
elif state_id == 5 (Hope) and delta < 0:
    delta *= 0.5   # Harder to fall from hope
else:
    delta *= 1.0   # Normal rate
```

Resistance multipliers are exported as editable variables for designer tuning.

---

## 3. Data Layer

### Hope/Despair State Mapping

| State ID | Name | Slider Range | Hope (0–10) | Tone / Color |
|----------|------|-------------|--------------|--------------|
| 1 | Despair | -10 to -6 | 0.0–2.0 | Monochrome, dark (#333) |
| 2 | Low | -5 to -2 | 2.5–4.0 | Gray-blue (#666) |
| 3 | Neutral | -1 to +1 | 4.5–5.5 | Default amber (#FFB347) |
| 4 | Buoyant | +2 to +5 | 6.0–7.5 | Warm gold (#FFD700) |
| 5 | Hope | +6 to +10 | 8.0–10.0 | Bright glow (#FFEA00) |

**Boundary rule:** Upper bound uses `<=` (e.g. `-6.0` → Despair, `-5.9` → Low). Documented in code.

### New Constants

```gdscript
# In state_system.gd or constants.gd
const HOPE_DESPAIR_MIN: float = -10.0
const HOPE_DESPAIR_MAX: float = 10.0
const HOPE_DESPAIR_NEUTRAL: float = 0.0
const STATE_DESPAIR: int = 1
const STATE_LOW: int = 2
const STATE_NEUTRAL: int = 3
const STATE_BUOYANT: int = 4
const STATE_HOPE: int = 5
const STATE_BOUNDARIES: Array[float] = [-10.0, -6.0, -2.0, 1.0, 5.0, 10.0]  # upper bounds per state
const RESISTANCE_EXTREME: float = 0.5
const RESISTANCE_NORMAL: float = 1.0
```

### Legacy GameState Deprecation

`game_state.gd` gets a deprecation warning on `_ready()`:
```
print("WARNING: GameState is deprecated. Use StateSystem.hope_despair instead.")
```

Internal delegation: `apply_state(delta_hope, delta_despair)` translates to `StateSystem.apply_hope_despair_delta()` using the mapping:
- `hope_despair_delta = (delta_hope - delta_despair) / 10.0` (compressed from 0–100 scale to -10/+10)

This ensures existing code referencing GameState continues to work during migration.

---

## 4. Dialogue / Narrative Layer

### Slider-Gated Choice Conditions (Existing, Unchanged)

Dialogue conditions use the existing DSL — no new operator types needed:

```json
{
  "type": "slider",
  "axis": "hope_despair",
  "op": "gte",
  "value": 6
}
```

Threshold values: -6 (Despair/Low boundary), -2 (Low/Neutral), +2 (Neutral/Buoyant), +6 (Buoyant/Hope), plus intermediate values for finer gating.

### Disabled Choice Rendering

The `choices_available` signal payload changes from `Array[Dictionary]` to include a `disabled` field:

```json
{
  "text": "I feel like things might change...",
  "next_node": "n_03",
  "disabled": true,          // NEW: rendered grayed out, not clickable
  "disabled_tooltip": "You don't feel hopeful enough to say this."
}
```

The dialogue display (`DialogueDisplay3D` / `DialoguePanel`) renders disabled choices:
- 50% alpha, grayed out
- Tooltip text shown on focus (not clickable)
- Not selectable via keyboard/click navigation

### Mid-Dialogue State Change Queueing

`StateSystem.apply_choice()` checks if dialogue is active (via `DialogueRunner.is_active` or a flag). If so, state changes are queued instead of emitted immediately:

```gdscript
var _pending_state: Dictionary = {}  # Buffered state change
var _dialogue_active: bool = false

func apply_choice(effect: Dictionary) -> void:
    # Apply internally but don't emit immediately if dialogue is active
    # Instead, buffer and flush on dialogue_ended
```

On `dialogue_ended` signal, the buffered state change is applied and emitted.

### NPC Attitude System (Data-Driven)

NPC dialogue JSON gains per-state fields:

| Field | Type | Description |
|-------|------|-------------|
| `state_greetings[1..5]` | String (per state) | Per-state greeting text (up to 5) |
| `state_information_tiers[1..5]` | String (per state) | Information the NPC shares at each state (longer = more hopeful) |
| `choice_gating[opts]` | Array of conditions | Existing condition DSL on choices, referencing `"hope_despair"` axis |

Example (in NPC dialogue JSON metadata):
```json
{
  "npc_metadata": {
    "state_greetings": {
      "1": "...",
      "2": "Yeah?",
      "3": "Evening.",
      "4": "Hey there.",
      "5": "Good to see you!"
    }
  }
}
```

---

## 5. Render / Visual Layer

### WorldviewController Changes (`gdscripts/worldview_controller.gd`)

**Modified:**
- `_calculate_tone(hope_despair: float) -> int` — returns state ID (1–5) instead of 3-tone string
- `world_text_changed.emit(prefix: String)` — prefix becomes `"despair"|"low"|"neutral"|"buoyant"|"hope"`
- `get_tone_for_state(state)` — updated for new state IDs

**New signal (optional):**
- `world_state_changed(state_id: int)` — direct 5-state notification for listeners that need discrete IDs

### RainController Changes (`gdscripts/rain_controller.gd`)

**Modified:**
- `_on_state_changed(state)` — maps `hope_despair` to rain intensity (inverse):
  - `hope_despair = -10` → rain intensity 1.0 (max)
  - `hope_despair = 0` → rain intensity 0.5
  - `hope_despair = +10` → rain intensity 0.0 (min)
- 5 discrete rain levels instead of continuous mapping:
  - State 1 (Despair): intensity 1.0 — downpour
  - State 2 (Low): intensity 0.75 — steady rain
  - State 3 (Neutral): intensity 0.5 — light rain
  - State 4 (Buoyant): intensity 0.25 — drizzle
  - State 5 (Hope): intensity 0.0 — let-up

### Environmental Text Variants (Scene Scripts)

Each scene script (`office.gd`, `street.gd`, `store.gd`) updates `_configure_environmental_text()` to work with 5-state mapping. Minimum 3 variants per scene object (Despair+Low, Neutral, Buoyant+H捆绑e), recommended 5.

The `get_variant(state_id: int, variants: Array) -> String` helper function clamps state_id to available variant count:

```gdscript
func get_variant(state_id: int, variants: Array) -> String:
    var idx: int = clampi(state_id - 1, 0, variants.size() - 1)
    return variants[idx]
```

---

## 6. Test Layer

### Test Structure

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_state_system.gd` | **New** — dedicated StateSystem tests | +200 |
| `tests/test_core.gd` or `run_tests.gd` | **Modify** — add slider system tests | +15 |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| hope_despair slider range | ✅ | Boundary values (-10, -6, -2, +2, +6, +10) | Invalid axis name |
| State ID mapping | ✅ | Exact boundaries (-6.0, -2.0, 0.0, +2.0, +6.0) | Out-of-range slider |
| Emotional resistance | ✅ | Despair→Neutral trajectory, Hope→Neutral trajectory | Zero delta, max delta |
| GameManager delegation | ✅ | get_slider for all known axes | StateSystem not found |
| WorldviewController 5-state | ✅ | All 5 states produce correct tone | Unknown state ID |
| Dialogue disabled choices | ✅ | Disabled rendering, focus behavior | No disabled choice handler |
| Legacy GameState delegation | ✅ | apply_state → slider delta | StateSystem not found |

### Key Test Scenarios

| # | Scenario | Input | Expected | Verification |
|---|----------|-------|----------|-------------|
| TC-1 | Slider initial value | New StateSystem() | `hope_despair = 0.0` | `assert_eq(ss.hope_despair, 0.0)` |
| TC-2 | Slider clamp at -10 | apply_choice({"hope_despair": -15}) | `hope_despair = -10` | `assert_eq(ss.hope_despair, -10.0)` |
| TC-3 | State ID: Despair | hope_despair = -6 | state_id = 1 | `assert_eq(ss.get_state_id(), 1)` |
| TC-4 | State ID: Neutral | hope_despair = 0 | state_id = 3 | `assert_eq(ss.get_state_id(), 3)` |
| TC-5 | State ID: Hope | hope_despair = +6 | state_id = 5 | `assert_eq(ss.get_state_id(), 5)` |
| TC-6 | Resistance at Despair | state=Despair, delta=+3 | actual_delta = +1.5 | `assert_approx(ss.hope_despair - start, 1.5)` |
| TC-7 | No resistance at Neutral | state=Neutral, delta=+3 | actual_delta = +3.0 | `assert_approx(ss.hope_despair - start, 3.0)` |
| TC-8 | Hope derived from slider | hope_despair = 0 | hope = 5.0 | `assert_eq(ss.hope, 5.0)` |
| TC-9 | Hope derived from slider (extreme) | hope_despair = +10 | hope = 10.0 | `assert_eq(ss.hope, 10.0)` |
| TC-10 | GameManager.get_slider("hope_despair") | After apply_delta(3) | Returns ≈3.0 | `assert_approx(gm.get_slider("hope_despair"), 3.0)` |
| TC-11 | GameManager.get_slider("hope") | hope_despair = 6 | Returns 8.0 | `assert_eq(gm.get_slider("hope"), 8.0)` |
| TC-12 | Disabled choice rendering | choice has disabled=true | Display shows grayed out | `assert_eq(choice_label.modulate.a < 1.0)` |
| TC-13 | Mid-dialogue state queuing | apply during active dialogue | Signal not emitted until dialogue_ended | Verify signal count |
| TC-14 | Legacy GameState delegation | GameState.apply_state(10, -20) | StateSystem slider moves +3 | `assert_approx(ss.hope_despair, 3.0)` |

---

## 7. Files Changed (per-layer summary)

### State / Engine Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/state_system.gd` | **Modify** — add hope_despair, get_state_id(), resistance, queuing | +60 |
| `gdscripts/game_manager.gd` | **Modify** — implement get_slider, apply_slider_delta, flags | +30 |
| `gdscripts/game_state.gd` | **Modify** — deprecation warning, delegation to StateSystem | +10 |

### Dialogue / Narrative Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/dialogue_display_3d.gd` | **Modify** — disabled choice rendering support | +25 |
| `dialogues/store_clerk.json` | **Modify** — add state_greetings, slider-gated choices | +30 |
| `dialogues/office_door.json` | **Modify** — add slider-gated branches | +15 |

### Render / Visual Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/worldview_controller.gd` | **Modify** — 5-state mapping, get_tone_for_state update | +15 |
| `gdscripts/rain_controller.gd` | **Modify** — hope_despair mapping, 5-level rain | +15 |
| `gdscripts/office.gd` | **Modify** — 5-state environmental text variants | +15 |
| `gdscripts/street.gd` | **Modify** — 5-state text variants | +15 |
| `gdscripts/store.gd` | **Modify** — 5-state text variants | +10 |

### Config / Constants Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/constants.gd` | **Modify** — add state mapping constants | +8 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_state_system.gd` | **New** — slider, state ID, resistance, delegation tests | +200 |
| `tests/run_tests.gd` | **Modify** — add slider tests to suite | +4 |

---

## 8. Verification Checklist

- [ ] TC-1 through TC-14: All slider test cases pass
- [ ] `godot --headless --script tests/run_tests.gd` — all tests pass, 0 failures
- [ ] No regression: existing dialogue engine tests still pass
- [ ] No regression: existing state system tests still pass
- [ ] hope_despair initializes to 0.0 (Neutral)
- [ ] get_state_id() returns correct ID for all boundary values
- [ ] Emotional resistance ×0.5 at extremes (Despair and Hope)
- [ ] GameManager.get_slider("hope_despair") returns real value (not stub 5.0)
- [ ] WorldviewController emits 5-state IDs (not 3-tone strings)
- [ ] RainController maps hope_despair to 5-level rain intensity
- [ ] Disabled choices render grayed out with tooltip in dialogue display
- [ ] Mid-dialogue state changes are queued and flushed on dialogue_ended
- [ ] Legacy GameState.apply_state() delegates to StateSystem correctly
- [ ] Office/street/store scene scripts update to 5-state text variants
- [ ] Store clerk dialogue has 3+ state-greeting variants
- [ ] At least one dialogue choice is slider-gated (visible only at certain state)
- [ ] `project.godot` autoload section unchanged (StateSystem already registered)

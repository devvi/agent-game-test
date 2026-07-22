# Design: #50 — State-World Feedback (Hope/Despair Slider System)

> Parent Issue: #50
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Wire the stub `GameManager` to `StateSystem` to create a unified **Hope/Despair slider** (-10 to +10, 5 discrete states) that drives NPC attitudes, environmental text variants, dialogue choice gating, and rain intensity. Expand the existing 3-tone worldview and narrative systems to 5-state granularity. The slider becomes a single authoritative source of truth replacing the dual `GameState` / `StateSystem.hope` confusion.

### Data Flow

```
Player makes dialogue choice
    │
    ├──► DialogueRunner records choice
    │       └──► _apply_effects() → calls GameManager.apply_slider_delta()
    │               └──► GameManager (wired) → StateSystem.apply_choice()
    │                       └──► state_changed signal emitted
    │
    ├──► WorldviewController receives state_changed
    │       └──► _calculate_tone() → 5-state discrete tier (was 3-tone)
    │       └──► world_text_changed.emit(tone)
    │       └──► world_state_changed.emit(state_id) [NEW]
    │
    ├──► NarrativeManager receives state_changed
    │       └──► _calculate_tone_for_scene() → 5-state tier per scene
    │       └──► scene_text_changed.emit(scene_id, tone)
    │
    ├──► RainController receives state_changed
    │       └──► Rain intensity mapped from hope (inverse) — was conviction
    │
    ├──► Echo variant calculation
    │       └──► _calculate_echo_variant() → 5 variant choices (was 3)
    │
    └──► Next dialogue encounter
            └──► DialogueRunner._build_state_snapshot()
                    └──► GameManager.get_slider("hope_despair") → real value
                    └──► Condition evaluator gates choices against discrete ranges
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where to add hope_despair slider | **StateSystem** — expand hope to bipolar | Single source of truth; existing signal wiring works; no synchronization risk between two systems |
| Slider API | `hope_despair: float` (-10 to +10) with `hope` derived via `(hope_despair + 10.0) / 2.0` | Backward compatible; existing `get_slider("hope")` returns mapped value; dialogue conditions use `hope_despair` for clarity |
| State enumeration | `get_state_id() → int` (1–5) with inclusive upper bounds | Simple enum; both WorldviewController and NarrativeManager derive from same function |
| Emotional resistance | **Mild resistance** — at Despair (state 1), positive deltas ×0.5; at Hope (state 5), negative deltas ×0.5 | Spike 2 result: best pacing balance (3-4 choices to escape Despair) |
| Mid-dialogue state changes | **Queue + flush** — defer visual updates until `dialogue_ended` | Spike 1 result: instant swaps acceptable for bg text, but mid-dialogue visual changes are jarring |
| Choice gating style | **Disabled gating** — choices visible but grayed with tooltip | Spike 3 result: best balance of player agency + narrative tension |
| NPC attitude system | **Data-driven within existing dialogue JSONs** using `hope_despair` conditions | No new autoload; dialogue engine already supports slider conditions; content authors use familiar format |
| Legacy GameState | **Deprecated** — delegate internally to StateSystem, emit log warning | Keep for backward compat; existing `get_node("/root/GameState")` references still work |

### Five Discrete States

| State ID | Name | Slider Range | Hope Mapping | Tone (Worldview) |
|----------|------|-------------|--------------|-------------------|
| 1 | **Despair** | -10.0 to -6.0 | hope 0.0–2.0 | Deepest despair — monochrome |
| 2 | **Low** | -5.0 to -2.0 | hope 2.5–4.0 | Negative but not hopeless |
| 3 | **Neutral** | -1.0 to +1.0 | hope 4.5–5.5 | Baseline — flat affect |
| 4 | **Buoyant** | +2.0 to +5.0 | hope 6.0–7.5 | Positive outlook, warm |
| 5 | **Hope** | +6.0 to +10.0 | hope 8.0–10.0 | Boundless hope, glowing |

Boundary rule: upper bound inclusive (`<=`), so state 1 = [-10.0, -6.0], state 2 = (-6.0, -2.0], etc.

---

## 2. New Files

None. All changes are modifications to existing files.

---

## 3. Modified Files

### 3.1 Engine Layer

#### `gdscripts/state_system.gd` — StateSystem (**Modified**)

**Nature of change:** Add `hope_despair` bipolar axis, `get_state_id()`, emotional resistance multipliers, `apply_choice()` enhancement.

| Method/Variable | Signature | Description |
|----------------|-----------|-------------|
| `hope_despair` | `var hope_despair: float = 0.0` | New bipolar axis: -10 to +10, initialized at 0.0 (Neutral) |
| `hope` | Kept as 0–10, now derived via `(hope_despair + 10.0) / 2.0` | Backward compatible read-only derivation |
| `apply_choice()` | `func apply_choice(effect: Dictionary) -> void` | **Modified** — apply delta to `hope_despair` via `hope_despair` key; apply emotional resistance multipliers at extremes; batch signals on rapid changes |
| `get_state_id()` | `func get_state_id() -> int` | **New** — return 1–5 based on `hope_despair` using the 5-state mapping table |
| `_get_resistance_multiplier()` | `func _get_resistance_multiplier(state_id: int, delta_sign: int) -> float` | **New** — return ×0.5 at Despair (positive delta) or Hope (negative delta), else ×1.0 |
| `conviction`, `will` | No change | Remain independent axes, 0–10 |

**Key constants:**
- `HOPE_DESPAIR_MIN: float = -10.0`
- `HOPE_DESPAIR_MAX: float = 10.0`
- `STATE_DESPAIR_RANGE: Vector2 = Vector2(-10.0, -6.0)`
- `STATE_LOW_RANGE: Vector2 = Vector2(-5.0, -2.0)`
- `STATE_NEUTRAL_RANGE: Vector2 = Vector2(-1.0, 1.0)`
- `STATE_BUOYANT_RANGE: Vector2 = Vector2(2.0, 5.0)`
- `STATE_HOPE_RANGE: Vector2 = Vector2(6.0, 10.0)`
- `RESISTANCE_MILD: float = 0.5`

**Signals:** No new signals — `state_changed(state: Dictionary)` already emitted and includes `hope_despair` key.

#### `gdscripts/game_manager.gd` — GameManager (**Modified**)

**Nature of change:** Wire stub methods to delegate to StateSystem. Add `hope_despair` axis support.

| Method | Signature | Change |
|--------|-----------|--------|
| `get_slider(axis)` | `func get_slider(axis: String) -> float` | **Modified** — delegate to `StateSystem.hope_despair` for `"hope_despair"`, `StateSystem.hope` for `"hope"`, etc.; return `5.0` fallback for unknown axes |
| `apply_slider_delta(axis, delta)` | `func apply_slider_delta(axis: String, delta: float) -> void` | **Modified** — call `StateSystem.apply_choice()` with `{"hope_despair": delta}` for `"hope_despair"` axis; existing axis routes work |
| `set_flag(flag_name, value)` | `func set_flag(flag_name: String, value: bool) -> void` | **Modified** — store in internal `_flags: Dictionary` |
| `get_flags()` | `func get_flags() -> Dictionary` | **Modified** — return `_flags` |
| `has_flag(flag_name)` | `func has_flag(flag_name: String) -> bool` | **Modified** — check `_flags` |

**Internal state additions:**
- `var _flags: Dictionary = {}` — flag storage
- `var _state_system: Node` — `@onready` reference to `/root/StateSystem`

### 3.2 World & Narrative Layer

#### `gdscripts/worldview_controller.gd` — Worldview Controller (**Modified**)

**Nature of change:** Expand from 3-tone to 5-state mapping. Add `world_state_changed` signal.

| Signal | Signature | Description |
|--------|-----------|-------------|
| `world_state_changed` | `signal world_state_changed(state_id: int)` | **New** — emits discrete state ID for downstream consumers |
| `world_text_changed` | `signal world_text_changed(prefix: String)` | Kept — fires with state name for backward compat |

**Internal changes:**
- `_calculate_tone(hope, conviction)` → expand to 5 states
- Mapping: `hope_despair` value → state name string (despair/low/neutral/buoyant/hope)
- `get_tone_for_state(state)` → updated to use 5-state

#### `gdscripts/narrative_manager.gd` — Narrative Manager (**Modified**)

**Nature of change:** Expand `_calculate_tone_for_scene()` from 3-state to 5-state per scene. Update echo variant calculation.

Per-scene 5-state tone table (6 scenes × 5 states = 30 entries):

| Scene | State 1 (Despair) | State 2 (Low) | State 3 (Neutral) | State 4 (Buoyant) | State 5 (Hope) |
|-------|-------------------|---------------|-------------------|-------------------|----------------|
| Office | "despair" | "low" | "neutral" | "buoyant" | "hope" |
| Lobby | "fear" | "uneasy" | "neutral" | "curious" | "defiant" |
| Convenience Store | "cold" | "distant" | "neutral" | "warm" | "glowing" |
| Bridge | "tired" | "heavy" | "neutral" | "hopeful" | "determined" |
| Underpass | "despair" (composite) | "hollow" | "neutral" | "resolute" | "transcendent" |
| Subway Station | "backward" | "hesitant" | "waiting" | "forward" | "forward" |

**Echo variant expansion:** Each echo handler in `_calculate_echo_variant()` expands from 2-3 variants to 5 variants.

### 3.3 Systems Layer

#### `gdscripts/rain_controller.gd` — Rain Controller (**Modified**)

**Nature of change:** Re-map rain intensity from conviction-inverse to hope-inverse. Expand to 5 levels.

| Method/Variable | Change |
|----------------|--------|
| `_on_state_changed(state)` | Rain intensity = `(10.0 - state.get("hope", 5.0)) / 10.0` (was conviction) |
| `get_intensity()` | Returns 0.0–1.0, matching 5 rain levels |
| 5 rain levels | State 1=1.0 (max), 2=0.75, 3=0.5, 4=0.25, 5=0.0 (clear) |

### 3.4 Dialogue Layer

#### `gdscripts/dialogue_runner.gd` — Dialogue Runner (**Modified**)

**Nature of change:** Add `"hope_despair"` to the axes list in `_build_state_snapshot()`. Add mid-dialogue state change queuing.

| Method | Change |
|--------|--------|
| `_build_state_snapshot()` | Add `"hope_despair"` to the `for axis in [...]` loop |
| `select_choice(choice_index)` | Queue state changes for deferred flush |
| `dialogue_ended` signal | New connection to flush queued visual state changes |

#### `gdscripts/dialogue_condition_evaluator.gd` — Condition Evaluator

**No changes needed.** Existing ops (`gte`/`lte`/`gt`/`lt`/`eq`) work with `hope_despair` axis values directly.

### 3.5 Legacy Layer

#### `gdscripts/game_state.gd` — GameState (**Deprecated**)

**Nature of change:** Add delegate methods that forward to StateSystem. Emit deprecation log warning.

| Method | Change |
|--------|--------|
| `apply_state(delta_hope, delta_despair)` | **Modified** — delegate to `StateSystem.apply_choice()`, convert ranges (0–100 → -10 to +10), log deprecation warning |
| `get_state()` | **Modified** — return `StateSystem.get_state()` mapped values |
| `hope`, `despair` (0–100) | Keep for backward compat; values derived from StateSystem |

---

## 4. API Contracts

### Signal Connections

```
StateSystem.state_changed(state)
    ├──► WorldviewController._on_state_changed(state)
    │       └── emits world_text_changed(tone)
    │       └── emits world_state_changed(state_id) [NEW]
    ├──► NarrativeManager._on_state_changed(state)
    │       └── emits scene_text_changed(scene_id, tone)
    ├──► RainController._on_state_changed(state)
    │       └── updates rain_intensity (hope-inverse)
    └──► (future) AudioManager, UI overlays, etc.
```

### Method Call Chains

```
DialogueRunner._apply_effects(effects)
    └── gm.apply_slider_delta("hope_despair", -2.0)
            └── StateSystem.apply_choice({"hope_despair": -2.0})
                    ├── applies resistance multiplier
                    ├── clamps to [-10.0, 10.0]
                    ├── derives hope = (hope_despair + 10.0) / 2.0
                    └── emits state_changed(state)

GameManager.get_slider("hope_despair")
    └── StateSystem.hope_despair (direct read)

GameManager.set_flag("met_stranger", true)
    └── _flags["met_stranger"] = true

DialogueRunner._build_state_snapshot()
    └── gm.get_slider("hope_despair") → real value
    └── gm.get_slider("hope") → derived value (backward compat)
    └── gm.get_flags() → real flags
```

### NPC Attitude Pattern (Dialogue JSON)

```json
{
  "id": "clerk_greet",
  "speaker": "Clerk",
  "text": "「今晚没什么人。」",
  "choices": [
    {
      "text": "「我需要一些……温暖的东西。」",
      "condition": {
        "type": "slider",
        "axis": "hope_despair",
        "op": "lte",
        "value": -2.0
      },
      "effects": [
        {"type": "slider_delta", "axis": "hope_despair", "delta": 1.0}
      ],
      "next_node": "clerk_warm_response"
    },
    {
      "text": "「随便看看。」",
      "effects": [],
      "next_node": "clerk_browse"
    },
    {
      "text": "「今晚感觉不错。」",
      "condition": {
        "type": "slider",
        "axis": "hope_despair",
        "op": "gte",
        "value": 2.0
      }
    }
  ]
}
```

---

## 5. Test Plan

### Test Coverage Requirements

| Area | Coverage | Notes |
|------|----------|-------|
| hope_despair range enforcement | 100% boundary tests | -10, 0, +10, clamped extremes |
| get_state_id() | 7 cases — all 5 states + 2 boundary values | -6.0, -2.0, 0.0, +1.0, +5.0, +10.0 |
| Emotional resistance | 4 cases — each extreme × each delta sign | Despair + positive, Despair + negative, Hope + positive, Hope + negative |
| GameManager wiring | 6 cases — get_slider (known/unknown axis), apply_slider_delta, set_flag, get_flags, has_flag | Verify delegation to StateSystem |
| WorldviewController | 5 cases — each state ID produces correct tone | State 1–5 |
| NarrativeManager tone | 6 scenes × 5 states = 30 combinations | Ensure per-scene tone tables are complete |
| RainController | 5 cases — each state ID produces correct intensity | Inverse hope mapping |
| Echo variants | 5 states × 6 echoes = 30 variant outputs | Ensure no stale 3-state checks remain |
| Dialogue condition evaluation | 4 cases — slider gte/lte/gt/lt on hope_despair axis | Existing ops work with new axis |
| Mid-dialogue state queuing | 2 cases — queue works, flush works | Deferred visual update |
| Legacy GameState delegation | 2 cases — apply_state delegates, get_state reflects | Deprecation path |
| Boundary slider = -6.0 | 1 case — exact boundary returns state 1 (Despair) | Inclusive upper bound rule |

### Test Cases

#### TC1–TC5: State ID Mapping (Normal Path)
- **TC1:** `hope_despair = 0.0` → `get_state_id()` returns 3 (Neutral)
- **TC2:** `hope_despair = -10.0` → `get_state_id()` returns 1 (Despair)
- **TC3:** `hope_despair = 10.0` → `get_state_id()` returns 5 (Hope)
- **TC4:** `hope_despair = -6.0` → `get_state_id()` returns 1 (Despair) — inclusive upper bound
- **TC5:** `hope_despair = -5.0` → `get_state_id()` returns 2 (Low)

#### TC6–TC9: Clamping & Resistance (Edge Cases)
- **TC6:** Apply +12.0 to `hope_despair` at 5.0 → clamped to 10.0
- **TC7:** Apply -15.0 to `hope_despair` at -3.0 → clamped to -10.0
- **TC8:** At state 1 (Despair), apply `+2.0` delta → effective +1.0 (×0.5 resistance)
- **TC9:** At state 5 (Hope), apply `-2.0` delta → effective -1.0 (×0.5 resistance)

#### TC10–TC14: GameManager Wiring
- **TC10:** `GameManager.get_slider("hope_despair")` returns `StateSystem.hope_despair`
- **TC11:** `GameManager.get_slider("unknown_axis")` returns `5.0` fallback
- **TC12:** `GameManager.apply_slider_delta("hope_despair", 1.0)` delegates to `StateSystem.apply_choice()`
- **TC13:** `GameManager.set_flag("test_flag", true)` → `has_flag("test_flag")` returns true
- **TC14:** `GameManager.get_flags()` returns dict with all set flags

#### TC15–TC19: WorldviewController 5-State
- **TC15:** State 1 (Despair) → `_calculate_tone()` returns `"despair"`
- **TC16:** State 3 (Neutral) → `_calculate_tone()` returns `"neutral"`
- **TC17:** State 5 (Hope) → `_calculate_tone()` returns `"hope"`
- **TC18:** `world_state_changed` signal emitted with correct `state_id: int`
- **TC19:** `world_text_changed` signal still emitted with state name string

#### TC20–TC23: NarrativeManager 5-State Tone
- **TC20:** Office scene, state 2 (Low) → `_calculate_tone_for_scene()` returns `"low"`
- **TC21:** Lobby scene, state 5 (Hope) → returns `"defiant"`
- **TC22:** Bridge scene, state 1 (Despair) → returns `"tired"`
- **TC23:** Subway station, state 4 (Buoyant) → returns `"forward"`

#### TC24–TC26: RainController Hope Mapping
- **TC24:** State 1 (Despair, hope≈0) → `get_intensity()` returns 1.0
- **TC25:** State 3 (Neutral, hope≈5) → `get_intensity()` returns 0.5
- **TC26:** State 5 (Hope, hope≈10) → `get_intensity()` returns 0.0

#### TC27–TC29: Dialogue Runner Integration
- **TC27:** `_build_state_snapshot()` includes `"hope_despair"` key in sliders dict
- **TC28:** Dialogue condition `{"axis": "hope_despair", "op": "gte", "value": 2}` evaluates correctly when hope_despair = 3.0
- **TC29:** Dialogue condition with `hope_despair` unknown axis → evaluates as false (default 0.0)

#### TC30–TC31: Mid-Dialogue State Queue
- **TC30:** State change during active dialogue → environmental text NOT updated until dialogue ends
- **TC31:** After `dialogue_ended` → queued state changes flush to WorldviewController and NarrativeManager

#### TC32: Legacy GameState Delegation
- **TC32:** `GameState.apply_state(10, -5)` delegates to `StateSystem.apply_choice()`, 0–100 range mapped to -10 to +10 range

---

## 6. Files Changed

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `gdscripts/state_system.gd` | Modify | Add `hope_despair`, `get_state_id()`, resistance multipliers, derived `hope` | +40 |
| `gdscripts/game_manager.gd` | Modify | Wire get_slider, apply_slider_delta, set_flag, get_flags to real StateSystem | +25 |
| `gdscripts/worldview_controller.gd` | Modify | Expand to 5-state mapping, add `world_state_changed` signal | +15 |
| `gdscripts/narrative_manager.gd` | Modify | Expand `_calculate_tone_for_scene()` to 5-state, update echo variants | +30 |
| `gdscripts/rain_controller.gd` | Modify | Re-map from conviction→hope, 5 intensity levels | +5 |
| `gdscripts/dialogue_runner.gd` | Modify | Add `"hope_despair"` to axis list, state queue plumbing | +15 |
| `gdscripts/game_state.gd` | Modify | Add delegate methods to StateSystem, deprecation warning | +10 |
| `docs/DESIGN/50-state-world-feedback.md` | **New** | This document | — |
| `docs/TASKS/50-state-world-feedback.md` | **New** | Task breakdown | — |
| **Total** | | | **+140** |

### Unchanged (audited, no changes needed)

| File | Reason |
|------|--------|
| `gdscripts/dialogue_condition_evaluator.gd` | Existing ops work with `hope_despair` axis natively |
| `gdscripts/dialogue_parser.gd` | No new data model changes |
| `gdscripts/scene_base.gd` | Scene scripts read from `WorldviewController` which is updated |
| `gdscripts/constants.gd` | No new constants needed (state IDs are in StateSystem) |
| `project.godot` | StateSystem is **already** an autoload |
| `dialogues/*.json` | Condition updates are **Story Content** phase (Issue #56) |

---

## 7. Verification Checklist

- [ ] AC1 (Slider): `StateSystem.hope_despair` initializes to 0.0, clamped to [-10.0, +10.0], 5 discrete states via `get_state_id()`
- [ ] AC1 (Slider): `GameManager.get_slider("hope_despair")` returns the real current value
- [ ] AC2 (Text): Each scene object has at least 3 text variants (via 5-state tone mapping)
- [ ] AC3 (Choices): At least one dialogue choice is gated by `hope_despair` axis (tested via condition evaluator)
- [ ] AC3 (Choices): At least one NPC has different greeting tone per slider state (5 variants via dialogue JSON conditions)
- [ ] Emotional resistance: Despair state applies ×0.5 to positive deltas; Hope state applies ×0.5 to negative deltas
- [ ] Rain intensity: Inversely proportional to hope, 5 levels matching 5 states
- [ ] Mid-dialogue state changes: Queued, flushed on `dialogue_ended`
- [ ] Legacy GameState: Delegates to StateSystem with range conversion, emits deprecation warning
- [ ] All existing `state_changed` signal connections continue to work
- [ ] No regression: existing dialogue files still load and evaluate conditions

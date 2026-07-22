# Test Cases: #50 — State-World Feedback (Hope/Despair Slider System)

> Parent Issue: #50
> Phase: Implement
> Date: 2026-07-23

## Overview

32 test cases covering the Hope/Despair Slider System implementation:
- **TC1–TC5**: State ID mapping (normal path)
- **TC6–TC9**: Clamping & resistance (edge cases)
- **TC10–TC14**: GameManager wiring
- **TC15–TC19**: WorldviewController 5-state
- **TC20–TC23**: NarrativeManager 5-state tone
- **TC24–TC26**: RainController hope mapping
- **TC27–TC29**: Dialogue Runner integration
- **TC30–TC31**: Mid-dialogue state queue
- **TC32**: Legacy GameState delegation

---

## TC1–TC5: State ID Mapping

### TC1: Neutral
- **Input:** `hope_despair = 0.0`
- **Expected:** `get_state_id()` returns `3` (Neutral)

### TC2: Despair
- **Input:** `hope_despair = -10.0`
- **Expected:** `get_state_id()` returns `1` (Despair)

### TC3: Hope
- **Input:** `hope_despair = 10.0`
- **Expected:** `get_state_id()` returns `5` (Hope)

### TC4: Inclusive Upper Bound (Despair)
- **Input:** `hope_despair = -6.0`
- **Expected:** `get_state_id()` returns `1` (Despair) — inclusive upper bound rule

### TC5: Low
- **Input:** `hope_despair = -5.0`
- **Expected:** `get_state_id()` returns `2` (Low)

---

## TC6–TC9: Clamping & Resistance

### TC6: Clamp Upper
- **Setup:** `hope_despair = 5.0`
- **Apply:** `+12.0` delta
- **Expected:** `hope_despair` clamped to `10.0`

### TC7: Clamp Lower
- **Setup:** `hope_despair = -3.0`
- **Apply:** `-15.0` delta
- **Expected:** `hope_despair` clamped to `-10.0`

### TC8: Resistance at Despair (positive)
- **Setup:** `hope_despair = -10.0` (state 1)
- **Apply:** `+2.0` delta
- **Expected:** Effective `+1.0` (×0.5 resistance multiplier)

### TC9: Resistance at Hope (negative)
- **Setup:** `hope_despair = 10.0` (state 5)
- **Apply:** `-2.0` delta
- **Expected:** Effective `-1.0` (×0.5 resistance multiplier)

---

## TC10–TC14: GameManager Wiring

### TC10: get_slider("hope_despair")
- **Input:** `GameManager.get_slider("hope_despair")`
- **Expected:** Returns `StateSystem.hope_despair` value

### TC11: get_slider("unknown_axis")
- **Input:** `GameManager.get_slider("unknown_axis")`
- **Expected:** Returns `5.0` fallback

### TC12: apply_slider_delta delegation
- **Input:** `GameManager.apply_slider_delta("hope_despair", 1.0)`
- **Expected:** Delegates to `StateSystem.apply_choice({"hope_despair": 1.0})`

### TC13: set_flag / has_flag
- **Input:** `set_flag("test", true)` → `has_flag("test")`
- **Expected:** Returns `true`

### TC14: get_flags
- **Input:** `get_flags()` after set_flag calls
- **Expected:** Returns dict with all set flags

---

## TC15–TC19: WorldviewController 5-State

### TC15: Despair tone
- **Input:** `_calculate_tone(hope=1.0, conviction=5.0)`
- **Expected:** Returns `"despair"`

### TC16: Neutral tone
- **Input:** `_calculate_tone(hope=5.0, conviction=5.0)`
- **Expected:** Returns `"neutral"`

### TC17: Hope tone
- **Input:** `_calculate_tone(hope=9.0, conviction=5.0)`
- **Expected:** Returns `"hope"`

### TC18: world_state_changed signal
- **Input:** State change triggers `_on_state_changed`
- **Expected:** `world_state_changed` emitted with correct `state_id: int`

### TC19: world_text_changed signal backward compat
- **Input:** State change triggers `_on_state_changed`
- **Expected:** `world_text_changed` still emitted with state name string

---

## TC20–TC23: NarrativeManager 5-State Tone

### TC20: Office scene, Low state
- **Input:** `_calculate_tone_for_scene(0, {"hope": 3.0})`
- **Expected:** Returns `"low"`

### TC21: Lobby scene, Hope state
- **Input:** `_calculate_tone_for_scene(1, {"hope": 9.0})`
- **Expected:** Returns `"defiant"`

### TC22: Bridge scene, Despair state
- **Input:** `_calculate_tone_for_scene(3, {"hope": 1.0})`
- **Expected:** Returns `"tired"`

### TC23: Subway station, Buoyant state
- **Input:** `_calculate_tone_for_scene(5, {"hope": 7.0})`
- **Expected:** Returns `"forward"`

---

## TC24–TC26: RainController Hope Mapping

### TC24: State 1 (Despair)
- **Input:** `_on_state_changed({"hope": 1.0})`
- **Expected:** `get_intensity()` returns ≈1.0 (max rain)

### TC25: State 3 (Neutral)
- **Input:** `_on_state_changed({"hope": 5.0})`
- **Expected:** `get_intensity()` returns ≈0.5

### TC26: State 5 (Hope)
- **Input:** `_on_state_changed({"hope": 10.0})`
- **Expected:** `get_intensity()` returns 0.0 (clear)

---

## TC27–TC29: Dialogue Runner Integration

### TC27: snapshot includes hope_despair
- **Input:** `_build_state_snapshot()`
- **Expected:** Sliders dict includes `"hope_despair"` key

### TC28: condition gte on hope_despair
- **Input:** Condition `{"axis": "hope_despair", "op": "gte", "value": 2}` with hope_despair=3.0
- **Expected:** Evaluates to `true`

### TC29: unknown axis default
- **Input:** Condition with unknown axis
- **Expected:** Evaluates to `false` (defaults to 0.0)

---

## TC30–TC31: Mid-Dialogue State Queue

### TC30: State change during dialogue
- **Setup:** Active dialogue in progress
- **Apply:** State change via choice effect
- **Expected:** Environmental text NOT updated until dialogue ends

### TC31: Flush on dialogue_ended
- **Setup:** Queued state changes from TC30
- **Trigger:** `dialogue_ended` signal
- **Expected:** Queued changes flush to WorldviewController and NarrativeManager

---

## TC32: Legacy GameState Delegation

### TC32: apply_state delegates to StateSystem
- **Input:** `GameState.apply_state(10, -5)`
- **Expected:** Delegates to `StateSystem.apply_choice()`, 0–100 range mapped to -10 to +10 range

# Tasks: #50 — State-World Feedback (Hope/Despair Slider System)

> Parent Issue: #50
> Priority: critical
> Estimated: 2-3 weeks
> Prerequisites: #45 (merged), #46/#52 (merged)
> Design Reference: `docs/DESIGN/50-state-world-feedback.md`

---

## Task Breakdown

### Phase 0 — StateSystem Core: hope_despair Slider (Day 1)

**Rationale:** The slider is the foundation everything else depends on. Must be implemented and tested first.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Add `hope_despair` bipolar axis to StateSystem: -10 to +10 property, derived `hope` from `(hope_despair + 10.0) / 2.0`, `get_state_id()` returning 1–5, `_get_resistance_multiplier()`, enhanced `apply_choice()` with resistance and clamping | `gdscripts/state_system.gd` | None | 1d |

#### T1 Validation
- [ ] `hope_despair` initializes to 0.0
- [ ] Clamped to [-10.0, +10.0] on every `apply_choice()`
- [ ] `get_state_id()` returns correct state for every range:
  - [-10.0, -6.0] → 1 (Despair)
  - (-6.0, -2.0] → 2 (Low)
  - (-1.0, +1.0] → 3 (Neutral)
  - (+2.0, +5.0] → 4 (Buoyant)
  - (+6.0, +10.0] → 5 (Hope)
- [ ] Boundary: -6.0 → state 1, -2.0 → state 2, +1.0 → state 3, +5.0 → state 4, +10.0 → state 5
- [ ] `hope = (hope_despair + 10.0) / 2.0` derivation works correctly
- [ ] Resistance: Despair applies ×0.5 to positive deltas; Hope applies ×0.5 to negative deltas
- [ ] Rapid state changes (same frame) → single `state_changed` emission
- [ ] `conviction` and `will` axes unchanged

---

### Phase 1 — GameManager Wiring (Day 1-2)

**Rationale:** GameManager stub must be wired to StateSystem before dialogue engine can query real slider values.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T2 | Wire GameManager: implement real `get_slider()`, `apply_slider_delta()`, `set_flag()`, `get_flags()`, `has_flag()` delegating to StateSystem. Add internal `_flags: Dictionary`. Support `"hope_despair"` axis in addition to existing axis names | `gdscripts/game_manager.gd` | T1 | 0.5d |
| T3 | Add `"hope_despair"` to `DialogueRunner._build_state_snapshot()` axis list. Add mid-dialogue state change queuing: queue state changes during active dialogue, flush on `dialogue_ended` signal | `gdscripts/dialogue_runner.gd` | T2 | 0.5d |
| T4 | Deprecate legacy `GameState`: add delegate methods that forward `apply_state()` and `get_state()` to StateSystem with range conversion (0–100 → -10 to +10). Add deprecation warning log on first delegation | `gdscripts/game_state.gd` | T1 | 0.25d |

#### T2 Validation
- [ ] `get_slider("hope_despair")` returns `StateSystem.hope_despair` value
- [ ] `get_slider("hope")` returns derived 0–10 value (backward compat)
- [ ] `get_slider("unknown_axis")` returns 5.0 fallback
- [ ] `apply_slider_delta("hope_despair", delta)` calls `StateSystem.apply_choice({"hope_despair": delta})`
- [ ] `set_flag("test", true)` → `has_flag("test")` returns true
- [ ] `get_flags()` returns all flags

#### T3 Validation
- [ ] `_build_state_snapshot()` includes `"hope_despair"` key
- [ ] Mid-dialogue state changes are queued, not immediately affecting visuals
- [ ] After `dialogue_ended`, queued changes flush to WorldviewController and NarrativeManager

#### T4 Validation
- [ ] `GameState.apply_state(10, -5)` delegates correctly to StateSystem (hope+5, despair mapped)
- [ ] Deprecation log warning prints once on first delegation

---

### Phase 2 — World & Narrative Expansion (Day 2-4)

**Rationale:** WorldviewController and NarrativeManager must expand from 3-state to 5-state. RainController needs re-mapping. These are parallelizable.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T5 | Expand WorldviewController: update `_calculate_tone()` from 3-tone to 5-state (despair/low/neutral/buoyant/hope). Add `world_state_changed(state_id: int)` signal. Ensure `world_text_changed` signal still works for backward compat | `gdscripts/worldview_controller.gd` | T1 | 0.5d |
| T6 | Expand NarrativeManager: update `_calculate_tone_for_scene()` to return 5-state tones per scene (30 entries: 6 scenes × 5 states). Update `_calculate_echo_variant()` to produce 5 variants per echo instead of 2-3 | `gdscripts/narrative_manager.gd` | T1 | 1d |
| T7 | Re-map RainController: change rain intensity from conviction-inverse to hope-inverse. Define 5 intensity levels matching the 5 states (Despair=1.0, Low=0.75, Neutral=0.5, Buoyant=0.25, Hope=0.0) | `gdscripts/rain_controller.gd` | T1 | 0.25d |

#### T5 Validation
- [ ] State 1 → `_calculate_tone()` returns "despair"
- [ ] State 2 → returns "low"
- [ ] State 3 → returns "neutral"
- [ ] State 4 → returns "buoyant"
- [ ] State 5 → returns "hope"
- [ ] `world_state_changed` emitted with correct int state_id
- [ ] `world_text_changed` still emitted with tone string

#### T6 Validation
- [ ] Each of the 6 scenes returns the correct 5-state tone (30 combinations verified)
- [ ] Echo handler for "rain_echo" returns 5 variants (0-4) instead of 3
- [ ] Echo handler for "screensaver_echo" returns 5 variants
- [ ] Echo handler for "clock_echo" returns 5 variants
- [ ] Echo handler for "door_echo" returns 5 variants
- [ ] Echo handler for "rain_variation_echo" returns 5 variants
- [ ] Echo handler for "stranger_echo" returns 5 variants

#### T7 Validation
- [ ] State 1 (hope≈0) → rain_intensity = 1.0
- [ ] State 3 (hope≈5) → rain_intensity = 0.5
- [ ] State 5 (hope≈10) → rain_intensity = 0.0
- [ ] `forced_shelter_triggered` threshold unchanged

---

### Phase 3 — Integration & Verification (Day 4-5)

**Rationale:** All modifications must work together in integration tests.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T8 | Write integration tests in `tests/run_tests.gd`: test the full chain — GameManager.get_slider → StateSystem.hope_despair → WorldviewController/NarrativeManager tone → dialogue condition evaluation with hope_despair axis. Cover all 5 states + 2 boundary values | `tests/run_tests.gd` | T2, T5, T6, T7 | 1d |
| T9 | Write test case descriptions covering all 32 test cases from DESIGN doc (TC1–TC32) in `docs/TESTS/50-state-world-feedback.md` | `docs/TESTS/50-state-world-feedback.md` | None | 0.5d |

#### T8 Validation
- [ ] Full chain test: apply slider delta → StateSystem emits state_changed → WorldviewController emits correct tone
- [ ] Dialogue condition with "hope_despair" axis evaluates correctly
- [ ] Emotional resistance test: positive delta at Despair → ×0.5 effective
- [ ] Legacy GameState delegation test: apply_state goes through StateSystem
- [ ] All existing test cases still pass

---

### Phase 4 — GDD Documentation Update (Day 5)

**Rationale:** The GAME_DESIGN docs need updating to reflect the new slider system and 5-state mapping.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T10 | Update `docs/GAME_DESIGN/01-OVERVIEW.md` — add hope_despair slider description to state system section | `docs/GAME_DESIGN/01-OVERVIEW.md` | T1 | 0.25d |
| T11 | Update `docs/GAME_DESIGN/05-DIALOGUE.md` — add `hope_despair` axis documentation, 5-state condition patterns, disabled gating pattern | `docs/GAME_DESIGN/05-DIALOGUE.md` | T1 | 0.25d |
| T12 | Update `docs/GAME_DESIGN/06-NARRATIVE.md` — update tone mapping tables from 3-state to 5-state | `docs/GAME_DESIGN/06-NARRATIVE.md` | T5, T6 | 0.25d |
| T13 | Update `docs/GAME_DESIGN/INDEX.md` — add any new section references | `docs/GAME_DESIGN/INDEX.md` | T10-T12 | 0.25d |

---

## Dependency Graph

```
T1 (StateSystem slider)
 │
 ├──► T2 (GameManager wiring)
 │     └──► T3 (DialogueRunner axis + queue)
 │
 ├──► T4 (GameState deprecation)
 │
 ├──► T5 (WorldviewController 5-state)
 │
 ├──► T6 (NarrativeManager 5-state)
 │
 └──► T7 (RainController re-map)
        │
        └──► T8 (Integration tests)
                │
                ├──► T9 (Test case descriptions)
                │
                └──► T10-T13 (GDD updates)
```

---

## Summary

| File | Type | Est. Lines |
|------|------|-----------|
| `gdscripts/state_system.gd` | Modify | +40 |
| `gdscripts/game_manager.gd` | Modify | +25 |
| `gdscripts/worldview_controller.gd` | Modify | +15 |
| `gdscripts/narrative_manager.gd` | Modify | +30 |
| `gdscripts/rain_controller.gd` | Modify | +5 |
| `gdscripts/dialogue_runner.gd` | Modify | +15 |
| `gdscripts/game_state.gd` | Modify | +10 |
| `tests/run_tests.gd` | Modify | +40 |
| `docs/TESTS/50-state-world-feedback.md` | **New** | +80 |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | Modify | +5 |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | Modify | +15 |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | Modify | +20 |
| `docs/GAME_DESIGN/INDEX.md` | Modify | +3 |
| **Total** | | **+303** |

### Implementation Order

| Phase | Tasks | Days | Key Deliverable |
|-------|-------|------|-----------------|
| P0 — Core Slider | T1 | Day 1 | StateSystem with hope_despair, get_state_id(), resistance |
| P1 — Wiring | T2, T3, T4 | Day 1-2 | GameManager wired with real data, dialogue runner uses it |
| P2 — Expansion | T5, T6, T7 | Day 2-4 | 5-state worldview, narrative tones, rain mapping |
| P3 — Integration | T8, T9 | Day 4-5 | All tests pass, test doc written |
| P4 — Doc Update | T10, T11, T12, T13 | Day 5 | GDD docs reflect 5-state system |

# TASKS: GameState-World Feedback — Hope/Despair affects environment text

> Issue: #154
> Phase: Implementation
> Target PR: `impl/154-gamestate-world-feedback-env-text`
> Priority: Critical (depth/deep)

---

## Task Breakdown

| ID | Task | File(s) | Dependencies | Est. Effort |
|----|------|---------|-------------|-------------|
| T1 | Expand TextComponentBase from 3-tier to 5-state variant selection | `gdscripts/text_component_base.gd` | None | 1d |
| T2 | Update LamppostText to use will-axis state mapping | `gdscripts/lamppost_text.gd` | T1 | 0.1d |
| T3 | Update NeonSign to use conviction-axis state mapping | `gdscripts/neon_sign.gd` | T1 | 0.1d |
| T4 | Update PuddleText (hope axis, cleanup) | `gdscripts/puddle_text.gd` | T1 | 0.1d |
| T5 | Update RainText (hope axis + despair emissive multiplier) | `gdscripts/rain_text.gd` | T1 | 0.1d |
| T6 | Add SceneBase helper methods for tone lookup and signal wiring | `gdscripts/scene_base.gd` | T1 | 0.3d |
| T7 | Create very_low and very_high variant .tres files (8 files) | `scenes/components/variants/*_very_low.tres`, `*_very_high.tres` | None | 0.5d |
| T8 | Refactor Office scene to use 5-state tone lookup | `gdscripts/office.gd` | T1, T6, T7 | 0.3d |
| T9 | Refactor Street scene (graffiti, neon) | `gdscripts/street.gd` | T1, T6 | 0.3d |
| T10 | Refactor Lobby scene (entrance, stranger spotlight) | `gdscripts/lobby.gd` | T1, T6 | 0.3d |
| T11 | Refactor Bridge scene (traffic, homeless, rain) | `gdscripts/bridge.gd` | T1, T6 | 0.3d |
| T12 | Refactor Underpass scene (graffiti, light) | `gdscripts/underpass.gd` | T1, T6 | 0.3d |
| T13 | Refactor Store scene (open sign) | `gdscripts/store.gd` | T1, T6 | 0.2d |
| T14 | Refactor Subway Station scene (ticket gate, clock, broadcast) | `gdscripts/subway_station.gd` | T1, T6 | 0.3d |
| T15 | Write comprehensive test file (20+ test cases) | `tests/unit/test_env_text_5_state.gd` | T1-T7 | 1d |
| T16 | Update test runner to include env text tests | `tests/run_tests.gd` | T15 | 0.1d |
| T17 | Create DESIGN doc | `docs/DESIGN/154-gamestate-world-feedback-env-text.md` | T1-T16 | 0.3d |
| T18 | Create TASKS doc | `docs/TASKS/154-gamestate-world-feedback-env-text.md` | T1-T16 | 0.2d |
| T19 | Create PR and pass stage gate | — | T1-T18 | 0.2d |

**Total:** ~6.0d effort, 19 tasks

---

## Implementation Order

1. **Phase 1 — Infrastructure:** T1 (TextComponentBase) → T2-T5 (subclasses) → T6 (SceneBase)
2. **Phase 2 — Content:** T7 (variant .tres files)
3. **Phase 3 — Scene Scripts:** T8-T14 (all 7 scenes)
4. **Phase 4 — Testing:** T15-T16 (tests + runner)
5. **Phase 5 — Documentation:** T17-T18 (documents)
6. **Phase 6 — Delivery:** T19 (PR + gate)

---

## Verification

- [ ] `godot --headless --script tests/run_tests.gd` — all 20+ env text tests pass, 0 failures
- [ ] All 8 new .tres files load without errors
- [ ] All 7 scene scripts compile without errors
- [ ] PR body starts with "Parent #154"
- [ ] Stage gate passes: `python3 ~/.hermes/scripts/stage-gate.py --pr <N>`

---

## Notes

- TextComponentBase retains backward compatibility (`_calculate_tier()`, `_variant_index_for_tier()`, `set_state_tier()`) for any code still using 3-tier API
- Subclass axis overrides follow the PRD recommendation: LamppostText → will, NeonSign → conviction, PuddleText/RainText → hope
- Dynamic updates use `scene_text_changed` signal from NarrativeManager
- Fade transitions use Tween with 0.3s default duration (configurable via `transition_duration`)

# Tasks: #59 — Mysterious Stranger NPC (三层真相对话树)

> Parent Issue: #59
> Priority: Critical (P0)
> Estimated: 2–3 weeks
> Prerequisites: #58 (underpass scene), #46/#52 (dialogue engine), #45 (narrative architecture)
> Design Reference: `docs/DESIGN/59-mysterious-stranger-npc.md`

---

## Phase Breakdown

### Phase 0 — Infrastructure: GameManager playthrough_count (P0)

**Rationale:** AC3 (deep layer) requires `playthrough_count ≥ 2`. This must be implemented before any dialogue work because the dialogue JSON conditions reference the flag. Minimal change — one new field + increment + accessor.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T0.1 | Add `playthrough_count: int = 0` field to `GameManager.gd` | `gdscripts/game_manager.gd` | None | 0.25d |
| T0.2 | Increment `playthrough_count` in `start_game()` method | `gdscripts/game_manager.gd` | T0.1 | 0.25d |
| T0.3 | Add `get_playthrough_count() → int` accessor | `gdscripts/game_manager.gd` | T0.1 | 0.25d |
| T0.4 | Ensure `playthrough_count` persists across `reset()` calls (not reset on new game) | `gdscripts/game_manager.gd` | T0.2 | 0.25d |
| T0.5 | Write unit tests for playthrough_count: increment, persistence, accessor | `tests/test_game_manager_playthrough.gd` | T0.1–T0.4 | 0.5d |

**Validation:** `start_game()` increments count. `get_playthrough_count()` returns correct value. `reset()` does not reset the counter.

### Phase 1 — Underpass Dialogue JSON: Full Three-Layer Tree (P0)

**Rationale:** Core deliverable. Rewrite `underpass_stranger_echo.json` from the current ~12 nodes/250 lines to ~24 nodes/~400 lines with all three layers. This is the largest change and must be done carefully to maintain existing behavior while adding new layers.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1.1 | Expand AC1 shallow paths: verify 3 base paths still work (acknowledge/deny/silent), add terminal nodes for each path | `dialogues/underpass_stranger_echo.json` | None | 0.5d |
| T1.2 | Add AC2 extreme-state variants: high hope (≥9), low hope (≤2) variants for each path | `dialogues/underpass_stranger_echo.json` | T1.1 | 0.5d |
| T1.3 | Add AC2 office/store cross-reference nodes: `echo_office_sigh`, `echo_office_determined`, `echo_coffee_ref` with conditions | `dialogues/underpass_stranger_echo.json` | T1.2 | 0.5d |
| T1.4 | Add AC3 meta-narrative layer: `echo_meta_entry`, `echo_meta_reveal`, `echo_meta_choice`, `echo_meta_end` nodes with `is_new_game_plus` condition | `dialogues/underpass_stranger_echo.json` | T1.3 | 1d |
| T1.5 | Hemingway constraint pass: verify every node has ≤25 chars/sentence, ≤3 sentences/node. Use ⌈⌋ brackets for AC3 meta-text | `dialogues/underpass_stranger_echo.json` | T1.4 | 0.5d |
| T1.6 | Verify existing conditional nodes (screensaver_echo variants, low conviction variants) still work alongside new nodes | `dialogues/underpass_stranger_echo.json` | T1.1–T1.5 | 0.5d |

**Validation:** All 3 base paths visible on fresh game. screensaver/conviction variants show on correct conditions. New extreme-state variants show only at extreme values. AC3 meta path visible only with `is_new_game_plus`. Hemingway constraints pass.

### Phase 2 — Supporting Dialogue Files (P1)

**Rationale:** Lobby stranger flags and subway ending mapping must be in place for the underpass dialogue to reference cross-scene conditions and for the ending dialogue to reflect meta choices.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T2.1 | Expand `lobby_stranger.json`: add `stranger_high_hope`, `stranger_low_conviction`, `stranger_dejavu_deep` nodes with flag-setting effects | `dialogues/lobby_stranger.json` | None | 0.5d |
| T2.2 | Verify new lobby flags don't break existing lobby dialogue flow (existing nodes unchanged) | `dialogues/lobby_stranger.json` | T2.1 | 0.25d |
| T2.3 | Expand `subway_ending.json`: add meta-aware Stranger nodes for each ending (`kw_stranger_meta`, `tb_stranger_meta`, `st_stranger_meta`) with `stranger_revealed` condition | `dialogues/subway_ending.json` | T1.4 (AC3 node references) | 0.5d |
| T2.4 | Verify existing subway ending nodes unchanged — meta variants are additional condition-gated nodes | `dialogues/subway_ending.json` | T2.3 | 0.25d |

**Validation:** Lobby Stranger sets new flags at correct state thresholds. Subway ending shows meta variants only when `stranger_revealed = true`. Existing nodes unchanged.

### Phase 3 — Scene Script Modifications (P0)

**Rationale:** `underpass.gd` must be updated to set `is_new_game_plus` flag before starting dialogue, and to pass extreme-state context for AC2 variants.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T3.1 | Modify `_on_stranger_echo_trigger_input()` to read `GameManager.playthrough_count` and set `is_new_game_plus` flag before `start_dialogue()` | `gdscripts/underpass.gd` | T0.3 (get_playthrough_count accessor) | 0.5d |
| T3.2 | Add `_get_stranger_context()` helper that returns extreme-state flags (hope≥9, hope≤2) for dialogue condition pre-population | `gdscripts/underpass.gd` | None | 0.25d |
| T3.3 | Add `playthrough_count` read path to `NarrativeManager` for dialogue condition evaluator access | `gdscripts/narrative_manager.gd` | T0.3 | 0.25d |
| T3.4 | Verify existing `_check_hidden_text()` and echo triggers still work after modifications | `gdscripts/underpass.gd` | T3.1–T3.3 | 0.25d |

**Validation:** `is_new_game_plus` set before dialogue on playthrough ≥ 2. Extreme-state flags set correctly. No regression on existing underpass behavior.

### Phase 4 — Documentation Update (P1)

**Rationale:** `docs/GAME_DESIGN/06-NARRATIVE.md` must reflect the expanded Stranger dialogue design.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T4.1 | Update Section 6 "Stranger NPC 设计" with 3-layer dialogue description, AC3 meta-narrative reveal, playthrough_count mechanic | `docs/GAME_DESIGN/06-NARRATIVE.md` | T1.4 (finalized node structure) | 0.5d |
| T4.2 | Add cross-scene flag reference table documenting all flags used by underpass dialogue | `docs/GAME_DESIGN/06-NARRATIVE.md` | T2.1, T2.3 | 0.25d |

**Validation:** Section 6 covers all 3 layers, mentions AC3 reveal, documents playthrough_count and cross-scene flags.

### Phase 5 — Tests & Verification (P0)

**Rationale:** All three dialogue layers, condition evaluation, playthrough counting, and ending mapping must be tested.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T5.1 | Write `tests/test_stranger_dialogue.gd`: unit tests for all condition combinations (TC1–TC14 from DESIGN doc) | `tests/test_stranger_dialogue.gd` | T1.6, T2.2, T2.4, T3.1 | 2d |
| T5.2 | Write `tests/test_stranger_scene.gd`: integration tests for full underpass dialogue flow, AC1/AC2/AC3 routing, ending effects mapping | `tests/test_stranger_scene.gd` | T1.6, T2.4, T3.4, T0.5 | 1.5d |
| T5.3 | Hemingway constraint validator test: programmatically check all nodes in underpass_stranger_echo.json | `tests/test_stranger_dialogue.gd` | T1.5 | 0.5d |
| T5.4 | End-to-end walkthrough: simulate full game with 2 playthroughs, verify AC1→AC2→AC3 progression | All modified files | T5.1–T5.3 | 1d |
| T5.5 | Regression verification: all pre-existing tests still pass | Test runner | T5.4 | 0.25d |

**Validation:** ≥18 test cases from DESIGN doc pass. All ACs verified. Pre-existing tests pass.

---

## Dependency Graph

```
Phase 0 ────────────────
├─ T0.1 (GameManager: add field) ───────────────────┐
├─ T0.2 (GameManager: increment on start) ───────────┤
├─ T0.3 (GameManager: accessor) ─────────────────────┤
├─ T0.4 (GameManager: reset persistence) ────────────┤
└─ T0.5 (tests: playthrough) ────────────────────────┘
                                                      │
Phase 1 ────────────────                               │
├─ T1.1 (underpass JSON: expand AC1) ──────┐          │
├─ T1.2 (underpass JSON: AC2 extreme) ─────┤          │
├─ T1.3 (underpass JSON: AC2 cross-ref) ───┤          │
├─ T1.4 (underpass JSON: AC3 meta) ────────┤          │
├─ T1.5 (underpass JSON: Hemingway) ───────┤          │
└─ T1.6 (underpass JSON: verify existing) ─┤          │
                                            │          │
Phase 2 ────────────────                     │          │
├─ T2.1 (lobby JSON: expand) ───────────────┤          │
├─ T2.2 (lobby: verify existing) ───────────┤          │
├─ T2.3 (subway JSON: meta endings) ────────┤          │
└─ T2.4 (subway: verify existing) ──────────┤          │
                                            │          │
Phase 3 ────────────────                     │          │
├─ T3.1 (underpass.gd: is_new_game_plus) ◄──┼──── T0.3 │
├─ T3.2 (underpass.gd: context helper) ─────┤          │
├─ T3.3 (narrative_mgr: playthrough path) ◄─┼──── T0.3 │
└─ T3.4 (underpass: verify existing) ───────┤          │
                                            │          │
Phase 4 ────────────────                     │          │
├─ T4.1 (06-NARRATIVE: 3-layer section) ◄───┤── T1.4   │
└─ T4.2 (06-NARRATIVE: flag table) ◄────────┼── T2.1   │
                                            │          │
Phase 5 ────────────────                     │          │
├─ T5.1 (tests: stranger dialogue) ◄────────┼── T1.6   │
├─ T5.2 (tests: stranger integration) ◄─────┼── T0.5   │
├─ T5.3 (tests: Hemingway validator) ◄──────┼── T1.5   │
├─ T5.4 (E2E walkthrough) ◄─────────────────┼── T5.1   │
└─ T5.5 (regression) ◄──────────────────────┴── T5.4   │
                                                        │
All done ────────────────────────────────────────────────┘
```

---

## Summary: Changed Files

| File | Type | Est. Lines |
|------|----------|-----------|
| `dialogues/underpass_stranger_echo.json` | Modified | +150 (250→400) |
| `dialogues/lobby_stranger.json` | Modified | +40 |
| `dialogues/subway_ending.json` | Modified | +30 |
| `gdscripts/underpass.gd` | Modified | +15 |
| `gdscripts/narrative_manager.gd` | Modified | +6 |
| `gdscripts/game_manager.gd` | Modified | +10 |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | Modified | +30 |
| `tests/test_stranger_dialogue.gd` | **New** | +150 |
| `tests/test_game_manager_playthrough.gd` | **New** | +60 |
| `tests/test_stranger_scene.gd` | **New** | +120 |

**Total:** 7 modified files + 3 new files ≈ +611 lines estimated.

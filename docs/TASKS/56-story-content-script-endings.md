# Tasks: #56 — Story Content（全场景剧本 + 三结局）

> Parent Issue: #56
> Priority: critical
> Estimated: 3-5 days
> Prerequisite: #45, #50, #51, #55, #13 (all merged)

---

## Task Breakdown

### Phase 1 — Dialogue Content: Thin Files First (Day 1)

**Rationale:** Expand the two thinnest/most important files first — bridge_homeless and subway_ending — to ensure implementation covers the critical path.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Expand `bridge_homeless.json` from 1 node → 7 nodes (homeless mirror conversation, screensaver_echo enrichment, conditional low-will and conviction branches) | `dialogues/bridge_homeless.json` | None | 1d |
| T2 | Expand `subway_ending.json` from 4 nodes → 17 nodes (Keep Walking 6-node arc, Turn Back 5-node arc, Stay 5-node arc) | `dialogues/subway_ending.json` | None | 1d |

#### T1 Details — bridge_homeless.json

**Current:** 1 node, 3 choices. **Target:** 5-7 nodes.

```jsonc
// Nodes to add:
// - homeless_talk: deep conversation branch (choice: "停下倾听")
// - homeless_story: homeless person's mirror story
// - homeless_farewell: resolution node
// - homeless_low_will: conditional (will≤3) — "坐下休息"
// - homeless_deep_question: conditional (conviction≥6) — "你为什么做游戏？"
```

**Validation:** Reads correctly with `dialogue_parser.gd`. All node `next_node` references resolve. Hemingway constraints satisfied. Screensaver echo trigger preserved.

#### T2 Details — subway_ending.json

**Current:** 4 nodes. **Target:** 15-17 nodes across 3 endings.

```
Keep Walking chain: kw_arrive → kw_edge → kw_lookback(optional) → kw_stranger → kw_train → kw_final
Turn Back chain:    tb_arrive → tb_gate → tb_decision → tb_street → tb_final
Stay chain:         st_arrive → st_bench → st_train_passes → st_stranger → st_final
```

**Validation:** Each chain has ≥5 nodes. Each node ≤3 sentences, each sentence ≤25 chars. set_flag for each ending unique (ending_keep_walking, ending_turn_back, ending_stay).

---

### Phase 2 — Dialogue Content: Enrich Existing Files (Day 2-3)

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T3 | Expand `office_door.json` from 3 → 5 nodes (add door_lookback, enrich door_leave with will-dependent variant) | `dialogues/office_door.json` | None | 0.5d |
| T4 | Expand `lobby_stranger.json` from 5 → 7 nodes (add hope-dependent variants to stranger_talk, add stranger_dejavu_dialogue conditional) | `dialogues/lobby_stranger.json` | None | 0.5d |
| T5 | Expand `lobby_guard.json` from 3 → 5 nodes (add guard_greet_variant, guard_deep_chat conditional, enrich guard_weather with will check) | `dialogues/lobby_guard.json` | None | 0.5d |
| T6 | Expand `store_clerk.json` from 10 → 14 nodes (add look_window_despair/hope conditionals, shelf_explore new interaction with will-dependent text) | `dialogues/store_clerk.json` | None | 0.5d |
| T7 | Expand `underpass_stranger_echo.json` from 4 → 7 nodes (add coffee_echo conditional, echo_tunnel_walk, echo_deny_followup, hope-dependent entry variant) | `dialogues/underpass_stranger_echo.json` | None | 0.5d |

#### T7 Notes — coffee_echo

Add conditional node that's only visible when `bought_coffee` flag = true:
```json
{
  "speaker": "Stranger",
  "text": "那杯咖啡还好吗？",
  "condition": { "type": "flag", "flag": "bought_coffee", "value": true }
}
```

---

### Phase 3 — Intertextuality Echoes (Day 3)

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T8 | Add 4 new echo IDs to `constants.gd`: ECHO_CLOCK, ECHO_DOOR, ECHO_RAIN_VARIATION, ECHO_STRANGER | `gdscripts/constants.gd` | None | 0.25d |
| T9 | Add echo handler entries in `narrative_manager.gd` `_calculate_echo_variant()` for the 4 new echoes (clock_echo with hope-driven variants, door_echo with conviction-driven variants, rain_variation_echo as cumulative environmental text, stranger_echo matching lobby→station) | `gdscripts/narrative_manager.gd` | None | 0.5d |
| T10 | Verify intertextuality coverage: 7 echoes total across all scenes (rain_echo, screensaver_echo, clock_echo, door_echo, rain_variation_echo, stranger_echo, coffee_echo) | All dialogue files | T1-T9 | 0.25d |

#### T8 Echo Constants

```gdscript
const ECHO_CLOCK: String = "clock_echo"
const ECHO_DOOR: String = "door_echo"
const ECHO_RAIN_VARIATION: String = "rain_variation_echo"
const ECHO_STRANGER: String = "stranger_echo"
```

#### T9 Echo Handler Example — clock_echo

```gdscript
"clock_echo":
    var hope_val: float = _state_system.hope if _state_system else 5.0
    if hope_val >= 7.0: return 0  # "The train is coming"
    elif hope_val <= 3.0: return 2  # "Too late"
    else: return 1  # "The clock ticks"
```

---

### Phase 4 — Environmental Text + Verification (Day 3-4)

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T11 | Verify and enrich environmental text across all 6 scenes (state-aware LoFiText3D content): office window/screensaver/desktop, lobby entrance/stranger/exit, store counter/shelves/window, bridge traffic/homeless/rain, underpass graffiti/tunnel/light, subway gate/clock/broadcast | Scene `.tscn` files + scene `.gd` scripts | None | 1d |
| T12 | Hemingway constraint audit: run all dialogue JSON files through `HemingwayEnforcer.truncate()` validation. Fix any sentences that exceed 25 chars or nodes with >3 sentences | All dialogue JSON files | T1-T7 | 0.5d |
| T13 | Dialogue JSON integrity check: verify all `next_node` references exist, all condition/effect types are valid, all JSON files parse correctly with `dialogue_parser.gd` | All dialogue JSON files | T1-T7, T12 | 0.25d |

---

### Phase 5 — Test Cases (Day 4)

**These are test case descriptions for manual/headless verification — NOT runnable `.gd` test files.**

| ID | Test Case | Steps | Expected Result | Type |
|----|-----------|-------|----------------|------|
| T14-TC01 | Office door dialogue coverage | Start game, interact with office door | All 5 nodes accessible without missing references | Integration |
| T14-TC02 | Stranger lobby dialogue | Reach lobby, interact with Stranger | 7 nodes, hope-dependent variants on stranger_talk, conviction≥6 branch available | Integration |
| T14-TC03 | Guard deep chat | Interact with guard, hope≥5 | guard_deep_chat node triggers with guard's story | Integration |
| T14-TC04 | Store clerk state variants | Reach store, check window text at hope≤3, 4-6, ≥7 | Different text per hope tier | State |
| T14-TC05 | Store clerk shelf interaction | Reach store, interact with shelves | Shelf text depends on will value | State |
| T14-TC06 | Homeless dialogue expansion | Reach bridge, interact with homeless | 7 nodes accessible, screensaver_echo triggers, conditional nodes visible at will≤3 and conviction≥6 | Integration |
| T14-TC07 | Underpass echo variants | Reach underpass, trigger echo with hope≥7, 5, ≤3 | Different Stranger text per hope tier | State |
| T14-TC08 | Underpass coffee echo | Reach underpass, bought_coffee flag=true | coffee_echo conditional node visible | Flag |
| T14-TC09 | Keep Walking ending (faith) | hope≥6, will≥5 at subway station | 6-node arc: kw_arrive → ... → kw_final, set_flag ending_keep_walking | Integration |
| T14-TC10 | Turn Back ending (give up) | conviction≤3 at subway station | 5-node arc: tb_arrive → ... → tb_final, set_flag ending_turn_back | Integration |
| T14-TC11 | Stay ending (acceptance) | Default/fallthrough state at subway station | 5-node arc: st_arrive → ... → st_final, set_flag ending_stay | Integration |
| T14-TC12 | Intertextuality count | Play full game, track echo triggers | ≥5 echoes triggered (rain_echo, screensaver_echo + at least 3 new) | Verification |
| T14-TC13 | Hemingway compliance | Scan all dialogue JSON texts | No sentence >25 chars, no node >3 sentences | Validation |
| T14-TC14 | JSON parse integrity | Load all 7 dialogue JSONs | All parse without errors, no dangling next_node references | Validation |
| T14-TC15 | State variant matrix | Visit each scene at hope≤3, 4-6, ≥7 | Environmental text changes per scene-state mapping | State |

---

### Phase 6 — Final Verification & Polish (Day 4-5)

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T14 | Run all 15 test cases | All dialogue files, scene scripts | T1-T13 | 1d |
| T15 | End-to-end walkthrough: office → subway station, verify 100% dialogue coverage with no gaps | All scene files, dialogue files | T14 | 0.5d |
| T16 | Text pass: review tone consistency, emotional arc quality, intertextuality resonance | All dialogue files | T15 | 0.5d |
| T17 | Final commit and close | All changed files | T16 | 0.25d |

---

## Milestones

| Milestone | Tasks | Done When |
|-----------|-------|-----------|
| M1 — Thin files filled | T1, T2 | bridge_homeless 7 nodes + subway_ending 17 nodes complete |
| M2 — All dialogue files enriched | T3-T7 | All 7 JSON files at target node counts |
| M3 — Intertextuality complete | T8-T10 | 7 echoes across game, all handlers in narrative_manager |
| M4 — Text verified | T11-T13 | Hemingway audit, environmental text enriched, JSON integrity checked |
| M5 — Release candidate | T14-T17 | All tests pass, end-to-end walkthrough green |

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Hemingway constraint makes emotional expression difficult | Medium | High | Write tests as short phrases, not sentences. Verify character counts before merging. |
| JSON node reference errors (typos in next_node) | Medium | Medium | Run dialogue_parser.gd validation before committing. |
| Echo handler missing in narrative_manager (no effect) | Low | Medium | Verify each echo triggers with 'echo_triggered' signal in test run. |
| State variant text feels disconnected from scene context | Medium | Medium | Review text per scene in isolation before full walkthrough (T15). |
| Endings not emotionally distinct enough | High | Low | Each ending has explicit emotional arc designed in DESIGN doc §7. Review against arc during T16. |
| Content overload — too many nodes for a single play session | Low | Low | Most nodes are conditional/state-dependent. A single playthrough sees ~40% of total content. |

---

## Files Changed (Summary)

### Modified Dialogue Files (7)
- `dialogues/office_door.json` — 3→5 nodes
- `dialogues/lobby_stranger.json` — 5→7 nodes
- `dialogues/lobby_guard.json` — 3→5 nodes
- `dialogues/store_clerk.json` — 10→14 nodes
- `dialogues/bridge_homeless.json` — 1→7 nodes
- `dialogues/underpass_stranger_echo.json` — 4→7 nodes
- `dialogues/subway_ending.json` — 4→17 nodes

### Modified Code Files (2)
- `gdscripts/constants.gd` — Add 4 new echo constants
- `gdscripts/narrative_manager.gd` — Add 4 new echo handlers in `_calculate_echo_variant()`

### Total: ~32 new dialogue nodes + ~8 lines of GDScript

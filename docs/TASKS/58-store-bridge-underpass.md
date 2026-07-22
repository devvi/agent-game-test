# Tasks: #58 — [Scene] Convenience Store → Bridge → Underpass

> Parent Issue: #58
> Priority: critical
> Estimated: 2-3 weeks

---

## Task Breakdown

### Phase 1 — Scene Geometry & Infrastructure（Week 1）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Add complete scene infrastructure to `bridge.tscn` — Camera3D, WorldEnvironment, DirectionalLight3D, OmniLight3D, SceneManager, FadeCurtain, DialoguePanel | `scenes/bridge/bridge.tscn` | None (skeleton exists) | 1d |
| T2 | Build bridge 3D geometry with CSG primitives — bridge deck, railings, canal surface, distant buildings, streetlamp | `scenes/bridge/bridge.tscn` | T1 | 1d |
| T3 | Add complete scene infrastructure to `underpass.tscn` — Camera3D, WorldEnvironment, DirectionalLight3D, flickering OmniLight3D, SceneManager, FadeCurtain, DialoguePanel | `scenes/underpass/underpass.tscn` | None (skeleton exists) | 1d |
| T4 | Build underpass 3D geometry with CSG primitives — tunnel walls, floor, ceiling, exit arch | `scenes/underpass/underpass.tscn` | T3 | 1d |
| T5 | Create placeholder materials: bridge_asphalt, canal_water, tunnel_wall, tunnel_floor, building_silhouette | `assets/materials/*.tres` | None | 0.5d |

### Phase 2 — Scripts & Scene Logic（Week 1-2）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T6 | Verify `bridge.gd` — confirm `_ready()` calls `scene_manager.fade_in()`, intrusive thought triggers `nm.trigger_echo("screensaver_echo")` | `gdscripts/bridge.gd` | T1 | 0.5d |
| T7 | Verify `underpass.gd` — confirm `_ready()` calls `scene_manager.fade_in()`, add AC3 hidden text check method (`_check_hidden_text()`) | `gdscripts/underpass.gd` | T3 | 0.5d |
| T8 | Modify `store.gd` — add `StoreExitTrigger` Area3D handler + dialogue start for store exit | `gdscripts/store.gd` | None | 0.5d |
| T9 | Add `StoreExitTrigger` Area3D to `convenience_store.tscn` near store entrance | `scenes/store/convenience_store.tscn` | T8 | 0.5d |
| T10 | Update `constants.gd` — add SCENE_BRIDGE, SCENE_UNDERPASS path constants, DESPAIR_HOPE_THRESHOLD, DESPAIR_CONVICTION_THRESHOLD | `gdscripts/constants.gd` | None | 0.5d |

### Phase 3 — Dialogue Content（Week 2）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T11 | Create `dialogues/store_exit.json` — exit → bridge transition dialogue (2 paths: walk immediately / stand in doorway) | `dialogues/store_exit.json` | T8 | 0.5d |
| T12 | Modify `dialogues/underpass_stranger_echo.json` — add condition-based 2nd-layer text variants per AC2 (6 extra nodes, flag + slider conditions) | `dialogues/underpass_stranger_echo.json` | T7 | 1d |
| T13 | Text pass: verify Stranger 2nd-layer dialogue is sharp/sad and matches the emotional climax tone | `dialogues/underpass_stranger_echo.json` | T12 | 0.5d |

### Phase 4 — Tests & Verification（Week 2-3）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T14 | Write `tests/test_bridge_underpass.gd` — all test cases from DESIGN doc (TC-B1 through TC-B9) | `tests/test_bridge_underpass.gd` | T6, T7, T10, T12 | 2d |
| T15 | Update `tests/run_tests.gd` — add `run_bridge_underpass_tests()` call | `tests/run_tests.gd` | T14 | 0.5d |
| T16 | End-to-end walkthrough: store → bridge → underpass — verify all 3 ACs | All scene files | T1-T13 | 1d |
| T17 | Echo system validation — verify screensaver_echo chain (office→bridge→underpass) and rain_echo chain (store→underpass) | `gdscripts/bridge.gd`, `gdscripts/underpass.gd`, `gdscripts/narrative_manager.gd` | T6, T7 | 0.5d |
| T18 | AC3 thresholds tuning — adjust DESPAIR_HOPE_THRESHOLD / DESPAIR_CONVICTION_THRESHOLD if playtest reveals imbalance | `gdscripts/constants.gd`, `gdscripts/underpass.gd` | T16 | 0.5d |
| T19 | Bridge geometry layout review — verify camera framing and railing/exit placement in Godot editor | `scenes/bridge/bridge.tscn` | T2 | 0.5d |
| T20 | Underpass geometry layout review — verify tunnel proportions and lighting in Godot editor | `scenes/underpass/underpass.tscn` | T4 | 0.5d |

---

## Milestones

| Milestone | Tasks | Done When |
|-----------|-------|-----------|
| M1 — Scene infrastructure complete | T1-T5 | Both scenes load in editor with geometry + lighting |
| M2 — Scene logic connected | T6-T10 | Store→bridge→underpass→subway transition chain works |
| M3 — All dialogues implemented | T11-T13 | store_exit.json created; Stranger 2nd layer complete |
| M4 — Release candidate | T14-T20 | All tests pass, ACs verified, geometry reviewed |

---

## Acceptance Criteria Mapping

| AC | Description | Covered By |
|----|-------------|-----------|
| AC1 (Shallow) | Player navigates store→bridge→underpass with 3 scene transitions | T16, T14 (TC-B7-1 through TC-B7-4) |
| AC2 (Middle) | Bridge text changes based on store choice; Stranger dialogue has 2 visible layers | T13, T12, T14 (TC-B1, TC-B6-1 through TC-B6-4) |
| AC3 (Deep) | Underpass hidden text (despair threshold) reveals Stranger as projection | T7, T18, T14 (TC-B5-1 through TC-B5-5) |

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| despair threshold imbalance (AC3 too easy/hard to trigger) | High | Medium | Prototype → adjust thresholds in T18; start with hope≤2 AND conviction≤2 |
| Dialogue JSON volume (underpass_stranger_echo grows from 73→150 lines) | Medium | Medium | Start with 1-2 variant branches; fill incrementally in T12 |
| CSG geometry misalignment with camera framing | Medium | Low | Review in editor during T19/T20; CSG is easy to reshape |
| Scene transition chain breaks (store exit not connecting to bridge) | High | Low | Verify in T16; SceneManager pattern is already proven in #55 |
| Echo system gap (intrusive thought and screensaver_echo diverging) | Medium | Low | Validate in T17; bridge.gd must call `nm.trigger_echo()` in both paths |

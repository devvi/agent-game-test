# Tasks: #45 — Narrative Architecture Implementation

> Parent Issue: #45
> Priority: critical
> Estimated: 3-4 weeks

---

## Task Breakdown

### Phase 1 — Core Systems（Week 1）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Implement `narrative_manager.gd` — scene sequence, ending determination, echo system | `gdscripts/narrative_manager.gd` | None | 2d |
| T2 | Implement `scene_base.gd` — base class for all scene scripts | `gdscripts/scene_base.gd` | None | 0.5d |
| T3 | Extend `state_system.gd` — add `get_state_tier()` | `gdscripts/state_system.gd` | None | 0.5d |
| T4 | Extend `game_manager.gd` — add scene tracking API | `gdscripts/game_manager.gd` | T1 | 0.5d |
| T5 | Add narrative constants to `constants.gd` | `gdscripts/constants.gd` | None | 0.5d |

### Phase 2 — Scenes & Scripts（Week 2）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T6 | Create/update `office.tscn` + `office.gd` | `scenes/office/office.tscn`, `gdscripts/office.gd` | T2 | 1d |
| T7 | Create `lobby.tscn` + `lobby.gd` | `scenes/lobby/lobby.tscn`, `gdscripts/lobby.gd` | T2 | 1d |
| T8 | Update `convenience_store.tscn` + `store.gd` | `scenes/store/convenience_store.tscn`, `gdscripts/store.gd` | T2 | 1d |
| T9 | Create `bridge.tscn` + `bridge.gd` | `scenes/bridge/bridge.tscn`, `gdscripts/bridge.gd` | T2 | 1d |
| T10 | Create `underpass.tscn` + `underpass.gd` | `scenes/underpass/underpass.tscn`, `gdscripts/underpass.gd` | T2 | 1d |
| T11 | Create `subway_station.tscn` + `subway_station.gd` | `scenes/subway_station/subway_station.tscn`, `gdscripts/subway_station.gd` | T2 | 1d |

### Phase 3 — Dialogue Content（Week 2-3）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T12 | Create `dialogues/office_door.json` | `dialogues/office_door.json` | T1 | 0.5d |
| T13 | Create `dialogues/lobby_stranger.json`（含条件分支 C02） | `dialogues/lobby_stranger.json` | T1 | 1d |
| T14 | Create `dialogues/lobby_guard.json` | `dialogues/lobby_guard.json` | T3 | 0.5d |
| T15 | Create `dialogues/store_clerk.json`（含条件分支 C05） | `dialogues/store_clerk.json` | T1 | 1d |
| T16 | Create `dialogues/bridge_homeless.json`（含回流民对话、回声2） | `dialogues/bridge_homeless.json` | T1, T5 | 1d |
| T17 | Create `dialogues/underpass_stranger_echo.json`（回声1核心 + 条件C11） | `dialogues/underpass_stranger_echo.json` | T1, T5 | 1d |
| T18 | Create `dialogues/subway_ending.json`（终局 3 分支） | `dialogues/subway_ending.json` | T1 | 1d |

### Phase 4 — Tests & Polish（Week 3-4）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T19 | Write `tests/test_narrative_architecture.gd` | `tests/test_narrative_architecture.gd` | T1 | 1d |
| T20 | End-to-end walkthrough: office → subway station | All scene files | T6-T18 | 2d |
| T21 | Text pass: review all state-aware text variants | All dialog JSONs | T12-T18 | 2d |
| T22 | Echo system validation: verify all 3 echoes trigger correctly | All | T1, T17, T16 | 1d |
| T23 | State threshold tuning: adjust ending conditions if needed | `gdscripts/narrative_manager.gd` | T20 | 1d |

---

## Milestones

| Milestone | Tasks | Done When |
|-----------|-------|-----------|
| M1 — Core narrative system | T1-T5 | Weekly checkpoint |
| M2 — All scenes playable | T6-T11 | Weekly checkpoint |
| M3 — All dialogues implemented | T12-T18 | Weekly checkpoint |
| M4 — Release candidate | T19-T23 | Issue can close |

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| State threshold imbalance (endings too easy/hard) | High | Medium | Prototype → adjust thresholds in T23 |
| Dialogue JSON volume (7 files, state variants) | Medium | Medium | Start with 1-2 scenes; fill variants incrementally |
| Echo system missing due to player skipping interactions | Low | Medium | Design ensures echoes are on the fixed path |

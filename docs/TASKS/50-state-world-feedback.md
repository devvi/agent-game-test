# Tasks: #50 — State-World Feedback — Hope/Despair Slider System

| 字段 | 值 |
|------|----|
| Issue | #50 |
| 优先级 | P0 |

## Overview

Implement Approach A from the PRD: Unify the game's dual state systems under StateSystem by adding a `hope_despair` bipolar slider (-10 to +10) with 5 discrete emotional states. Wire GameManager to delegate to StateSystem. Expand WorldviewController to 5-state mapping. Add emotional resistance and disabled-choice rendering.

See DESIGN doc: `docs/DESIGN/50-state-world-feedback.md`

## Phase 1: Core State Changes (P0)

| Step | File | Change | Prerequisite | Priority |
|------|------|--------|-------------|----------|
| 1.1 | `gdscripts/state_system.gd` | Add `hope_despair` property (-10 to +10), `get_state_id()`, `_get_resistance_multiplier()`, queuing logic | None | P0 |
| 1.2 | `gdscripts/game_manager.gd` | Implement `get_slider()` (all axes), `apply_slider_delta()`, `set_flag()`, `get_flags()` | 1.1 | P0 |
| 1.3 | `gdscripts/game_state.gd` | Add deprecation warning, delegate `apply_state()` to StateSystem | 1.1 | P0 |
| 1.4 | `gdscripts/constants.gd` | Add state mapping constants (HOPE_DESPAIR_MIN/MAX, STATE_*, RESISTANCE_*) | 1.1 | P0 |

## Phase 2: World/Visual Layer (P0)

| Step | File | Change | Prerequisite | Priority |
|------|------|--------|-------------|----------|
| 2.1 | `gdscripts/worldview_controller.gd` | Expand to 5-state mapping, update `_calculate_tone()`, `get_tone_for_state()` | 1.1 | P0 |
| 2.2 | `gdscripts/rain_controller.gd` | Map hope_despair to 5-level rain intensity | 1.1 | P0 |
| 2.3 | `gdscripts/office.gd` | Update `_configure_environmental_text()` to 5-state (or 3 with fallback) | 2.1 | P0 |
| 2.4 | `gdscripts/street.gd` | Update environmental text to 5-state | 2.1 | P0 |
| 2.5 | `gdscripts/store.gd` | Update environmental text to 5-state | 2.1 | P0 |

## Phase 3: Dialogue / NPC Layer (P1)

| Step | File | Change | Prerequisite | Priority |
|------|------|--------|-------------|----------|
| 3.1 | `gdscripts/dialogue_display_3d.gd` | Add disabled-choice rendering (grayed out, tooltip) | 1.1 | P1 |
| 3.2 | `dialogues/store_clerk.json` | Add per-state greetings (`npc_metadata.state_greetings`), slider-gated choices | 2.1, 3.1 | P1 |
| 3.3 | `dialogues/office_door.json` | Add slider-gated branches | 2.1, 3.1 | P1 |

## Phase 4: Tests (P0)

| Step | File | Change | Prerequisite | Priority |
|------|------|--------|-------------|----------|
| 4.1 | `tests/test_state_system.gd` | **New** — slider range, state ID, resistance, delegation tests | 1.1, 1.2 | P0 |
| 4.2 | `tests/run_tests.gd` | Add slider tests to suite | 4.1 | P0 |

## Dependency Graph

```
Phase 1 ─────────────────────────────
├─ 1.1 (state_system.gd) ─────┐
├─ 1.2 (game_manager.gd) ─────┤ ←── 1.1
├─ 1.3 (game_state.gd) ───────┤ ←── 1.1
└─ 1.4 (constants.gd) ────────┘ ←── 1.1
                              │
Phase 2 ─────────────────────────────
├─ 2.1 (worldview_controller.gd) ←── 1.1
├─ 2.2 (rain_controller.gd)    ←── 1.1
├─ 2.3 (office.gd)             ←── 2.1
├─ 2.4 (street.gd)             ←── 2.1
└─ 2.5 (store.gd)              ←── 2.1
                              │
Phase 3 ─────────────────────────────
├─ 3.1 (dialogue_display_3d.gd)  ←── 1.1
├─ 3.2 (store_clerk.json)        ←── 2.1, 3.1
└─ 3.3 (office_door.json)        ←── 2.1, 3.1
                              │
Phase 4 ─────────────────────────────
├─ 4.1 (test_state_system.gd)  ←── 1.1, 1.2
└─ 4.2 (run_tests.gd)          ←── 4.1
                              │
All done ────────────────────────────┘
```

## Summary: Changed Files

| File | Change Type | Est. Lines |
|------|-------------|-----------|
| `gdscripts/state_system.gd` | 修改 | +60 |
| `gdscripts/game_manager.gd` | 修改 | +30 |
| `gdscripts/game_state.gd` | 修改 | +10 |
| `gdscripts/constants.gd` | 修改 | +8 |
| `gdscripts/worldview_controller.gd` | 修改 | +15 |
| `gdscripts/rain_controller.gd` | 修改 | +15 |
| `gdscripts/office.gd` | 修改 | +15 |
| `gdscripts/street.gd` | 修改 | +15 |
| `gdscripts/store.gd` | 修改 | +10 |
| `gdscripts/dialogue_display_3d.gd` | 修改 | +25 |
| `dialogues/store_clerk.json` | 修改 | +30 |
| `dialogues/office_door.json` | 修改 | +15 |
| `tests/test_state_system.gd` | 新增 | +200 |
| `tests/run_tests.gd` | 修改 | +4 |

**Total estimated lines: +452**

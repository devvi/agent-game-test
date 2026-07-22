# Tasks: #56 — Story Content — Script for All Scenes + 3 Endings

| 字段 | 值 |
|------|----|
| Issue | #56 |
| 优先级 | P0 |

## Overview

Implement the complete game narrative content per [DESIGN doc](56-story-content-script-endings.md) and [PRD](../PRD/56-story-content-script-endings.md). Approach A (Top-Down Script-First): write the full annotated script as `docs/GAME_DESIGN/06-STORY.md`, create the Underpass 3D scene, build EndingController CanvasLayer overlay, expand/create 7 dialogue JSON files, integrate bartender trigger, and validate all 7 intertextual echoes.

## Phase 1: Underpass Scene + EndingController + Story Design Doc (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 1.1 | `docs/GAME_DESIGN/06-STORY.md` | **Create** — Full annotated script: Office, Street, Store, Underpass, 3 endings. Every node has shallow+middle layers; deep for endings/Stranger. Hemingway-constrained (≤25 chars/sentence, ≤3 sentences/paragraph). 7 intertextual echoes documented. | 无 | P0 |
| 1.2 | `scenes/underpass/underpass.tscn` | **Create** — Tunnel 3D environment with CSGBox3D walls/floor/ceiling, bench, dim fluorescent lighting, 4 LoFiText3D nodes (graffiti, subway sign, floor text, wall poster), Camera3D, Area3D trigger for final choice | 无 | P0 |
| 1.3 | `gdscripts/underpass.gd` | **Create** — Scene init script: configure environmental text variants from GameState (hope/conviction), connect final choice trigger to DialogueRunner | 无 | P0 |
| 1.4 | `gdscripts/ending_controller.gd` | **Create** — CanvasLayer overlay ending sequence: load ending dialogue JSON, display text with fade transitions, trigger credits/menu return. ~60 lines GDScript | 无 | P0 |
| 1.5 | `docs/GAME_DESIGN/INDEX.md` | **Modify** — Add 06-STORY entry | 1.1 | P0 |

## Phase 2: Dialogue JSON Expansion + Scene Integration (P1)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 2.1 | `dialogues/office_door.json` | **Modify** — Expand with final nodes per design doc (office_stay expanded, confirm scene transitions) | 1.1 | P1 |
| 2.2 | `dialogues/store_clerk.json` | **Modify** — Expand with after-clerk transition to underpass | 1.1 | P1 |
| 2.3 | `dialogues/bartender.json` | **Modify** — Verify 4 existing nodes; add integrate-notes if needed | 1.1 | P1 |
| 2.4 | `dialogues/underpass.json` | **Create** — Underpass arrival + 3-ending choice branch (4 nodes) | 1.1 | P1 |
| 2.5 | `dialogues/ending_keep_walking.json` | **Create** — Faith ending monologue (4 nodes) | 1.1 | P1 |
| 2.6 | `dialogues/ending_turn_back.json` | **Create** — Give-up ending monologue (4 nodes) | 1.1 | P1 |
| 2.7 | `dialogues/ending_stay.json` | **Create** — Acceptance ending monologue (4 nodes) | 1.1 | P1 |
| 2.8 | `gdscripts/store.gd` | **Modify** — Add after-clerk-dialogue scene transition → underpass.tscn | 2.2, 1.2 | P1 |
| 2.9 | `gdscripts/street.gd` | **Modify** — Add bartender NPC trigger zone connection (if bar area exists) | 2.3 | P1 |
| 2.10 | `gdscripts/store.gd` | **Modify** — After-clerk dialogue transition → underpass.tscn | 2.2, 1.2 | P1 |

## Phase 3: Validation + GDD Updates (P1-P2)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 3.1 | All dialogue JSONs | **Validate** — Run `dialogue_parser.gd` @tool mode on all JSON files; fix schema errors | 2.1-2.7 | P1 |
| 3.2 | All dialogue JSONs | **Audit** — Verify Hemingway constraints (≤25 chars/sentence, ≤3 sentences/paragraph) | 2.1-2.7 | P1 |
| 3.3 | All scenes | **Audit** — Intertextuality matrix checklist: confirm all 7 echoes present in authored content | 2.1-2.7, 1.2 | P1 |
| 3.4 | `docs/GAME_DESIGN/05-DIALOGUE.md` | **Modify** — Add intertextuality pattern documentation | 3.3 | P2 |
| 3.5 | All scenes | **Manual playtest** — Walk through full Office→Street→Store→Underpass→Ending flow; verify text-context accuracy | 3.1-3.3 | P2 |

## Dependency Graph

```
Phase 1 (P0) ──────────────────
├─ 1.1 Story Design Doc ──────┬────────────┐
├─ 1.2 Underpass .tscn ───────┤            │
├─ 1.3 underpass.gd ──────────┤            │
├─ 1.4 ending_controller.gd ──┤            │
└─ 1.5 INDEX.md ──────────────┘            │
                                            │
Phase 2 (P1) ────────────────              │
├─ 2.1 office_door.json  ←──── 1.1         │
├─ 2.2 store_clerk.json  ←──── 1.1         │
├─ 2.3 bartender.json    ←──── 1.1         │
├─ 2.4 underpass.json    ←──── 1.1         │
├─ 2.5 ending_keep_walking.json ← 1.1      │
├─ 2.6 ending_turn_back.json   ← 1.1       │
├─ 2.7 ending_stay.json        ← 1.1       │
├─ 2.8 store.gd         ←──── 2.2 + 1.2    │
├─ 2.9 street.gd        ←──── 2.3          │
└─ 2.10 store.gd (transition) ← 2.2 + 1.2  │
                                            │
Phase 3 (P1-P2) ──────────                  │
├─ 3.1 JSON schema validation ←─ 2.1-2.7   │
├─ 3.2 Hemingway audit        ←─ 2.1-2.7   │
├─ 3.3 Intertextuality audit  ←─ 2.1-2.7   │
├─ 3.4 05-DIALOGUE.md update  ←─ 3.3       │
└─ 3.5 Manual playtest        ←─ 3.1-3.3   │
                                            │
All done ───────────────────────────────────┘
```

## Summary: Changed Files

| 文件 | 变更类型 | 预估行数 |
|------|----------|----------|
| `docs/GAME_DESIGN/06-STORY.md` | 新增 | ~400 |
| `docs/GAME_DESIGN/INDEX.md` | 修改 | +1 |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | 修改 | +20 |
| `scenes/underpass/underpass.tscn` | 新增 | N/A (scene file) |
| `gdscripts/underpass.gd` | 新增 | ~40 |
| `gdscripts/ending_controller.gd` | 新增 | ~60 |
| `gdscripts/store.gd` | 修改 | +10 |
| `gdscripts/street.gd` | 修改 | +15 |
| `dialogues/office_door.json` | 修改 | +10 |
| `dialogues/store_clerk.json` | 修改 | +10 |
| `dialogues/bartender.json` | 修改 | +5 |
| `dialogues/underpass.json` | 新增 | ~20 |
| `dialogues/ending_keep_walking.json` | 新增 | ~20 |
| `dialogues/ending_turn_back.json` | 新增 | ~20 |
| `dialogues/ending_stay.json` | 新增 | ~20 |

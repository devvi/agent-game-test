# Tasks: #220 — 核心主题→机制映射研究 (Core Theme→Mechanism Mapping)

> Parent Issue: #220
> Agent: plan-agent
> Date: 2026-07-25
> Priority: critical
> Estimated Duration: 2–3 days (Implement Phase)
> Prerequisites: #213 (Rainy Night Prometheus scaffold ✅), #214 (narrative architecture ✅)
> Design Reference: `docs/DESIGN/220-theme-mechanism-mapping.md`

---

## Task Breakdown

### Phase 1: Mapping Document Output (P0)

**Rationale:** The DESIGN doc is the primary deliverable of the plan phase. The TASKS doc provides execution guidance for downstream work. Both must be created and merged before any content work begins.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 1.1 | Create DESIGN doc for #220 | Write `docs/DESIGN/220-theme-mechanism-mapping.md` with bidirectional affinity matrix (3×12×5), narrative mapping chains for 12 mechanisms, theme coverage maps, substitution test results, and elimination candidate rationale. Adopt Approach C (双向结合度矩阵 + 叙事段落). | `docs/DESIGN/220-theme-mechanism-mapping.md` | PRD #220 | 1.5 h |
| 1.2 | Create TASKS doc for #220 | Write `docs/TASKS/220-theme-mechanism-mapping.md` with task breakdown for playtest integration, GDD updates, content prioritization, and spike execution. | `docs/TASKS/220-theme-mechanism-mapping.md` | 1.1 | 1 h |
| 1.3 | Create plan branch and PR | Branch `plan/220-theme-mechanism-mapping` from `main`, commit both docs, push, create PR with title `docs: PLAN for #220 — 核心主题→机制映射研究` and body `Parent #220`. | — | 1.1, 1.2 | 0.25 h |

### Phase 2: GDD Integration (P1)

**Rationale:** The mapping analysis needs to be available as a living reference in the GDD, not siloed in a DESIGN doc. Update two GDD sections with mapping summaries.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 2.1 | Update GDD Overview with mapping summary | Add theme→mechanism mapping summary table to `docs/GAME_DESIGN/01-OVERVIEW.md`. Include: the 3 themes, their primary carriers (≥20/25), and the coverage pattern (distributed/concentrated/bimodal). Link to `docs/DESIGN/220-theme-mechanism-mapping.md` for full detail. | `docs/GAME_DESIGN/01-OVERVIEW.md` | 1.1 | 0.5 h |
| 2.2 | Update Narrative GDD with mapping chains | Add mapping chain references to `docs/GAME_DESIGN/06-NARRATIVE.md`. For each narrative mechanism (echo, hallucination, dialogue-as-check), link to the specific mapping chain in the DESIGN doc. | `docs/GAME_DESIGN/06-NARRATIVE.md` | 1.1 | 0.5 h |

### Phase 3: Playtest Preparation (P1)

**Rationale:** The playtest must verify that theme→mechanism mappings are actually perceptible to players. The mapping matrix provides structured test hypotheses.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 3.1 | Add mapping chain verification to playtest checklist | Extend `tests/playtest/README.md` with a "Theme Coverage" section. For each theme (T1–T3), list the top 3 mechanisms to verify and a sample verification question. Include the scoring matrix as a reference for expected perceptibility. | `tests/playtest/README.md` | 1.1 | 0.5 h |
| 3.2 | Create theme perceptibility survey template | Create a player survey template in `tests/playtest/` (e.g., `survey-theme-perception.md`) with 5-point Likert items: "I felt alone in the city" (T1), "I was unsure what was real" (T2), "I questioned my own perception" (T3). Map each question to the mechanisms expected to deliver that feeling. | `tests/playtest/survey-theme-perception.md` | 3.1 | 0.5 h |

### Phase 4: Spike Execution (P1–P2)

**Rationale:** Three spikes from PRD §7 need execution to validate the mapping matrix assumptions. Run in development environment; results may revise scores or design decisions.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 4.1 | Execute Spike 1: M07 removal impact | Temporarily disable M07 hallucination visual parameters (set all HALLUCINATION_PARAMS to baseline 0). Run a player walkthrough office→subway. Record T2/T3 perceptibility. If survival <30%, M07 stays P0; if >50%, consider M07 downgrade. | `gdscripts/worldview_controller.gd` (temp disable) | — | 1 h |
| 4.2 | Execute Spike 2: Hemingway constraint perceptibility | Prepare two versions of convenience store dialogue (A: with constraints, B: without). Run with 3+ testers. Record loneliness perception gap. If gap <0.5, revise M11 D2 scores. | `dialogues/json/convenience_store.json` (variant) | — | 1 h |
| 4.3 | Execute Spike 3: Elimination bounce-back risk | Build conflict matrix for all 5 eliminated mechanisms (quest journal, inventory, combat, randomized weather, minigame) vs. 6 core design principles. Check for ≤1 conflict point — if found, reconsider elimination. | — | — | 0.5 h |

### Phase 5: Content Priority Guidance (P2)

**Rationale:** The mapping matrix identifies which mechanisms are most thematically important. Content fill (dialogue JSON) should prioritize the highest-scoring mapping pairs.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 5.1 | Create content priority guide | From the ranking table (§4.3), derive text creation priorities: (1) M03 Worldview Filter → all 3 themes (66/75), (2) M02 Dialogue Checks → all 3 themes (64/75), (3) M07+Stranger → T2/T3. Share with content writers. | — | 1.1 | 0.25 h |
| 5.2 | Map dialogue nodes to mapping chains | For each of the 6 scene dialogues, annotate which mapping chain(s) each dialogue node serves. Ensure each dialogue node maps to at least one theme. | `dialogues/json/*.json` | 5.1 | 1 h |

### Phase 6: Deprecation or Retention Decision (P2–P3)

**Rationale:** M05 (3-Month Clock) scored lowest (36/75) and is near-zero on T3 (8/25). A decision is needed before playtest.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 6.1 | M05 deprecation assessment | Review M05's actual runtime usage. If clock_manager.gd is never referenced by state-dependent content (beyond the visible clock UI), mark as removed post-MVP. If it serves a narrative pacing function that the mapping matrix doesn't capture, document the blind spot. | `gdscripts/clock_manager.gd` | — | 0.5 h |
| 6.2 | File removal PR (if deprecation decided) | Create an implement PR to remove M05 (clock_manager.gd, references), with PRD/DESIGN/TASKS updates documenting the removal. The mapping matrix's low score is the justification. | `gdscripts/clock_manager.gd`, `gdscripts/*.gd` (cleaning references) | 6.1 | 0.25 h |

---

## Dependency Graph

```
Phase 1 (P0) ────────────────
├─ 1.1 DESIGN doc ────────────────────┐
├─ 1.2 TASKS doc ─────────────────────┤
└─ 1.3 branch + PR ───────────────────┘
                                       │
Phase 2 (P1) ───── 2.1, 2.2 ←── 1.1  │
                                       │
Phase 3 (P1) ───── 3.1, 3.2 ←── 1.1  │
                                       │
Phase 4 (P1-P2) ── 4.1–4.3 (parallel) │
                                       │
Phase 5 (P2) ───── 5.1, 5.2 ←── 1.1  │
                                       │
Phase 6 (P2-P3) ── 6.1, 6.2 ←── 1.1  │
                                       │
All done ──────────────────────────────┘
```

---

## Summary: Changed / New Files

| File | Change Type | Estimated Lines |
|:-----|:-----------:|:---------------:|
| `docs/DESIGN/220-theme-mechanism-mapping.md` | **NEW** | ~600 |
| `docs/TASKS/220-theme-mechanism-mapping.md` | **NEW** | ~180 |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | Modify | +30 |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | Modify | +20 |
| `tests/playtest/README.md` | Modify | +40 |
| `tests/playtest/survey-theme-perception.md` | **NEW** | ~30 |
| `dialogue_synthesis/priority-guide.md` | **NEW** | ~20 |

# MVP Playtest Protocol — Layered Verification

This directory contains the structured playtest infrastructure for the **MVP vertical slice** (都市夜行人 / Urban Night Walker). The playtest uses a 3-layer verification approach: **Shallow** (AC1 — 100% pass), **Middle** (AC2 — ≥60% pass), and **Deep** (AC3 — qualitative).

## Quick Start

```bash
# 1. Launch the game in GUI mode
godot scenes/main.tscn

# 2. For each playthrough, record observations in a report file
cp tests/playtest/report-template.yaml tests/playtest/report-agent-cua-1.yaml

# 3. Use the checklists to guide your testing
#    - tests/playtest/checklist-shallow.yaml  (47 items, must pass)
#    - tests/playtest/checklist-middle.yaml   (40 items, ≥60% pass)
#    - tests/playtest/checklist-deep.yaml     (10 Likert + 6 free-text)
```

## Directory Structure

```
tests/playtest/
├── README.md                          # This file — protocol instructions
├── checklist-shallow.yaml             # AC1 — 47 items, 100% must pass
├── checklist-middle.yaml              # AC2 — 40 items, ≥60% must pass
├── checklist-deep.yaml                # AC3 — 10 Likert + 6 free-text
├── report-template.yaml               # Template for each tester's report
├── report-agent-cua-1.yaml            # Example / actual report (tester 1)
├── report-agent-cua-2.yaml            # Example / actual report (tester 2)
├── report-agent-cua-3.yaml            # Example / actual report (tester 3)
└── synthesis.yaml                     # Merged results across testers
```

## Tester Scenarios

Three agent testers execute the playtest with distinct scenario instructions:

| Tester | Scenario | Goal |
|--------|----------|------|
| agent-cua-1 | **Neutral** | Default playthrough — observe baseline behavior without forcing state |
| agent-cua-2 | **High-hope** | Make choices that maximize hope/conviction/will. Verify Keep Walking ending |
| agent-cua-3 | **Low-hope** | Make choices that minimize hope/conviction/will. Verify Turn Back ending |

Each tester should:

1. **Play through all 6 scenes** in order: office → lobby → street → store → bridge → underpass → subway_station
2. **Interact with all triggers** in each scene (dialogue NPCs, exit doors, environmental interactables)
3. **Read all on-screen text** — environmental text, dialogue text, ending text
4. **Record observations** using the checklist YAML files and report template
5. **Note any crashes, missing text, broken transitions, or unexpected behavior**

## Verification Layers

### Shallow Layer (AC1) — 47 items, 100% Pass Required

| Section | Items | Focus |
|---------|-------|-------|
| Scene Loading | S-01 to S-08 (8) | All 6 scenes load with correct nodes |
| Dialogue System | S-09 to S-20 (12) | All 7 dialogues trigger and display correctly |
| Scene Transitions | S-21 to S-27 (7) | All 6 transitions work with fade effects |
| Environmental Text | S-28 to S-42 (15) | All text nodes render in correct positions |
| Sound System | S-43 to S-45 (3) | AudioManager loads without errors |
| Test Suite Baseline | S-46 to S-47 (2) | All existing unit tests pass headless |

Any shallow-layer failure is **blocking** — the playtest cannot proceed until it's fixed.

### Middle Layer (AC2) — 40 items, ≥60% Pass Required

| Section | Items | Pass Threshold |
|---------|-------|----------------|
| State-Dependent Branching | M-01 to M-08 (8) | ≥5 of 8 |
| Dialogue Conditions & Effects | M-09 to M-14 (6) | ≥4 of 6 |
| Echo System | M-15 to M-20 (6) | ≥4 of 6 |
| Ending Determination | M-21 to M-26 (6) | ≥4 of 6 |
| Scene Transition Integration | M-27 to M-30 (4) | ≥3 of 4 |
| Edge Cases | M-31 to M-35 (5) | ≥3 of 5 |
| Sound System Integration | M-36 to M-40 (5) | ≥3 of 5 |

Each failure must be documented with:
- **State used** when testing (axis/value pairs)
- **Observed vs. expected** behavior
- **Suggested fix** direction

Items may be **excluded** from scoring if the required state conditions were not reached during the playthrough (e.g., an ending-condition item when the tester didn't reach Subway Station). Excluded items are documented separately.

### Deep Layer (AC3) — Qualitative Evaluation

10 Likert-scale dimensions (1–5) and 6 free-text prompts. At least 2 testers must rate D-01 (Metaphor clarity) at ≥4/5 for AC3 to pass.

**Bonus criteria:**
- ≥2 testers rate D-04 (State-world feedback) at ≥4/5
- ≥1 tester identifies the Stranger as internal projection unprompted

## Bug Reporting

All bugs discovered during playtesting must be documented in the report's `failures` array with:
- `severity`: `blocking` (prevents further testing), `major` (significant feature broken), `minor` (cosmetic or edge case)
- `reproduction`: Exact steps to reproduce
- `observed`: What happened
- `expected`: What should happen

After the playtest round, all bugs are **filed as separate implement-phase issues** in the GitHub project. No code changes are part of this playtest issue itself.

## Synthesis Process

After all 3 testers complete their playthroughs:

1. Collect all 3 report files
2. Calculate AC1 pass rate (must be 100%)
3. Calculate AC2 pass rate per tester (must be ≥60%)
4. Aggregate AC3 ratings and free-text responses
5. Produce `synthesis.yaml` with merged results
6. File all discovered bugs as new GitHub issues with `bug` label
7. Assign implement-phase based on severity and layer

## CI Gate

The headless test suite (`godot --headless --script tests/run_tests.gd`) runs in CI on every push to `impl/*` branches. This verifies S-46 and S-47 (all existing tests pass, no warnings/errors). The GUI playtest is executed outside CI by agent testers.

## Edge Cases to Watch For

- Rapid trigger clicking (M-31)
- Re-entering dialogue while dialogue is active (M-32)
- All state axes at minimum (M-33)
- All state axes at maximum (M-34)
- Scene transition during active dialogue
- Missing autoload on first scene load
- Dialogue JSON parse failures (silent in production)
- Node path mismatches between script and scene tree

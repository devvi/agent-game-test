# Design: #57 — MVP Playtest & Layered Verification

> Parent Issue: #57
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Design a structured, repeatable playtest protocol combining a headless GDScript integration test suite (CI-gated) with an LLM-agent-driven GUI playtest (deep/interactive verification) to validate the MVP vertical slice end-to-end across Shallow (AC1 — 100% pass), Middle (AC2 — ≥60% pass), and Deep (AC3 — qualitative) acceptance layers.

### Data Flow

```ascii
┌─────────────────────────────────────────────────────────────────────┐
│                        MVP Playtest Pipeline                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────┐      ┌───────────────────────────┐        │
│  │  CI (GitHub Actions)  │      │  Agent Tester (GUI Mode)   │        │
│  │                      │      │                           │        │
│  │  godot --headless    │      │  computer_use drives      │        │
│  │  --script tests/     │      │  godot scenes/main.tscn   │        │
│  │  run_tests.gd        │      │                           │        │
│  │                      │      │  ┌──────────────────┐     │        │
│  │  ├─ Unit tests       │      │  │ Tester 1: neutral │     │        │
│  │  ├─ Integration      │      │  │ playthrough       │     │        │
│  │  │  (dialogue parse, │      │  └──────────────────┘     │        │
│  │  │   state eval,     │      │  ┌──────────────────┐     │        │
│  │  │   ending logic)   │      │  │ Tester 2: high   │     │        │
│  │  └──────────────────┘      │  │ hope/conviction  │     │        │
│  │                            │  └──────────────────┘     │        │
│  │  Gates: S-46, S-47        │  ┌──────────────────┐     │        │
│  │  (all existing tests      │  │ Tester 3: low    │     │        │
│  │   must pass)              │  │ hope/conviction  │     │        │
│  │                            │  └──────────────────┘     │        │
│  └──────────┬───────────────┘      │                      │        │
│             │                      │                      │        │
│              ──────► Merge ────────                      │        │
│                           │                               │        │
│                           ▼                               │        │
│              ┌──────────────────────┐                     │        │
│              │  Playtest Reports    │                     │        │
│              │  (YAML structured)   │                     │        │
│              │  tests/playtest/     │                     │        │
│              │  ├─ report-*.yaml    │                     │        │
│              │  └─ synthesis.yaml   │                     │        │
│              └──────────────────────┘                     │        │
│                           │                               │        │
│                           ▼                               │        │
│              ┌──────────────────────┐                     │        │
│              │  Bug Inventory       │                     │        │
│              │  → New Issues        │                     │        │
│              └──────────────────────┘                     │        │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Testing approach | **Hybrid (Approach C)** — headless integration suite + GUI agent playtest | Best coverage: logic verified by deterministic tests (CI), UX verified by agent playtest; industry standard |
| Headless test framework | Extend existing `tests/run_tests.gd` with new `*_integration.gd` tests | Reuses existing harness, Godot 4.7.1 `--headless --script` mode, zero new dependencies |
| GUI playtest driver | `computer_use` tool via Hermes agent | Exercises the real game binary, can evaluate deep/thematic quality, detects visual bugs |
| Test data format | YAML structured reports per tester | Machine-parseable for synthesis, human-readable for bug triage; aligns with existing YAML checklists |
| CI gate | Headless tests only (unit + integration) | GUI playtest requires display server; headless suite catches regressions fast in CI |
| Checklist format | YAML files with ID → description → verification method | Version-controlled, parseable by both humans and agents |
| Tester pool | 3 agent testers (LLM-based) with distinct scenario instructions | Covers neutral, high-hope, and low-hope paths for broad state coverage |

---

## 2. New Files

### `tests/playtest/` (new directory)

The playtest directory holds all structured data for the agent-based GUI playtest phase.

| File | Purpose | Format |
|------|---------|--------|
| `tests/playtest/checklist-shallow.yaml` | Shallow-layer acceptance checklist (AC1) — 47 items (S-01 through S-47) | YAML — ID, description, verification method, pass/fail |
| `tests/playtest/checklist-middle.yaml` | Middle-layer acceptance checklist (AC2) — 40 items (M-01 through M-40) | YAML — ID, description, priority, state conditions, pass/fail |
| `tests/playtest/checklist-deep.yaml` | Deep-layer evaluation rubric (AC3) — 10 Likert items + 6 free-text prompts | YAML — dimension ID, question, 1–5 scale, free-text field |
| `tests/playtest/report-template.yaml` | Structured report template for each tester to fill | YAML — tester_id, date, shallow/middle/deep sections, failure details |
| `tests/playtest/README.md` | Protocol instructions for agent testers | Markdown — setup, scenarios, recording format |

### `tests/playtest/checklist-shallow.yaml`

```yaml
# Shallow Layer Checklist (AC1 — 100% Must Pass)
# Each item must pass for every tester across any single playthrough.
#
# Sections:
#   scene_loading: S-01 to S-08  (8 items)
#   dialogue_system: S-09 to S-20  (12 items)
#   scene_transitions: S-21 to S-27  (7 items)
#   environmental_text: S-28 to S-42  (15 items)
#   sound_system: S-43 to S-45  (3 items)
#   test_suite_baseline: S-46 to S-47  (2 items)
```

### `tests/playtest/checklist-middle.yaml`

```yaml
# Middle Layer Checklist (AC2 — ≥60% Must Pass)
# Failing items must be documented with reproduction steps and suggested fixes.
#
# Sections:
#   state_dependent_branching: M-01 to M-08  (8 items)
#   dialogue_conditions_effects: M-09 to M-14  (6 items)
#   echo_system: M-15 to M-20  (6 items)
#   ending_determination: M-21 to M-26  (6 items)
#   scene_transition_integration: M-27 to M-30  (4 items)
#   edge_cases: M-31 to M-35  (5 items)
#   sound_system_integration: M-36 to M-40  (5 items)
```

### `tests/playtest/checklist-deep.yaml`

```yaml
# Deep Layer Evaluation Rubric (AC3 — Qualitative)
# Likert scale 1–5 per dimension, plus free-text responses.
# AC3-PASS: ≥2 testers rate D-01 at ≥4/5
```

### `tests/playtest/report-template.yaml`

Defines the structured report format from the PRD (Section 5 — Test Data Collection Format):

```yaml
tester_id: "agent-cua-{1..3}"
date: "2026-07-23"
playthrough_path: "office→lobby→street→store→bridge→underpass→subway_station"

shallow:
  total: 47
  passed: <int>
  failed: <int>
  failures:
    - id: "S-XX"
      description: "..."
      reproduction: "..."
      observed: "..."
      expected: "..."
      severity: "blocking|major|minor"

middle:
  total: 40
  passed: <int>
  failed: <int>
  excluded: []
  failures:
    - id: "M-XX"
      description: "..."
      state_used: {axis: value}
      observed: "..."
      expected: "..."
      suggestion: "..."
      severity: "blocking|major|minor"

deep:
  likert:
    D-01: <1..5>
    ...
  free_text:
    D-Q1: "..."
    ...
```

---

## 3. Modified Files

### Engine Layer

| File | Nature of Change | Est. Δ Lines |
|------|-----------------|-------------|
| `gdscripts/narrative_manager.gd` | **Inspect only** — validate scene sequence, ending determination, echo triggering in playtest | ±0 |
| `gdscripts/state_system.gd` | **Inspect only** — verify state transitions, clamping, resistance, signal emission | ±0 |
| `gdscripts/game_manager.gd` | **Inspect only** — verify slider delegation, flag storage, choice persistence | ±0 |
| `gdscripts/audio_manager.gd` | **Inspect only** — verify scene registration, ambient audio mapping | ±0 |
| `gdscripts/rain_controller.gd` | **Inspect only** — verify rain intensity conviction mapping | ±0 |

### Scene Layer

| File | Nature of Change | Est. Δ Lines |
|------|-----------------|-------------|
| `gdscripts/office.gd` | **Inspect only** — verify environmental text variants, door trigger | ±0 |
| `gdscripts/lobby.gd` | **Inspect only** — verify guard/stranger/exit triggers, tone switching | ±0 |
| `gdscripts/street.gd` | **Inspect only** — verify neon sign conviction modulation, graffiti hope visibility | ±0 |
| `gdscripts/store.gd` | **Inspect only** — verify OPEN sign foreshadowing condition | ±0 |
| `gdscripts/bridge.gd` | **Inspect only** — verify trigger/echo behavior | ±0 |
| `gdscripts/underpass.gd` | **Inspect only** — verify graffiti/echo/exit triggers, AC3 hidden text | ±0 |
| `gdscripts/subway_station.gd` | **Inspect only** — verify gate/turn_back/bench triggers, ending text | ±0 |

### Dialogue Layer

| File | Nature of Change | Est. Δ Lines |
|------|-----------------|-------------|
| `gdscripts/dialogue_runner.gd` | **Inspect only** — validate dialogue start, choice navigation, effects | ±0 |
| `gdscripts/dialogue_parser.gd` | **Inspect only** — validate JSON parsing | ±0 |
| `gdscripts/dialogue_condition_evaluator.gd` | **Inspect only** — validate condition evaluation | ±0 |
| `dialogues/*.json` (9 files) | **Inspect only** — validate all JSON is parseable, no dangling references | ±0 |

### Test Layer

| File | Nature of Change | Est. Δ Lines |
|------|-----------------|-------------|
| `tests/playtest/` (new directory) | **New directory** — agent playtest scripts and protocol | ~150 |
| `tests/playtest/checklist-shallow.yaml` | **New** — Shallow-layer acceptance checklist | ~120 |
| `tests/playtest/checklist-middle.yaml` | **New** — Middle-layer acceptance checklist | ~160 |
| `tests/playtest/checklist-deep.yaml` | **New** — Deep-layer evaluation rubric | ~60 |
| `tests/playtest/report-template.yaml` | **New** — Structured report template | ~50 |
| `tests/playtest/README.md` | **New** — Playtest protocol instructions | ~80 |

### Infrastructure

| File | Nature of Change | Est. Δ Lines |
|------|-----------------|-------------|
| `.github/workflows/opencode-review.yml` | **Inspect only** — may need playtest step added | ±0 |

---

## 4. API Contracts

### Test Signal Flow

```
Godot headless mode
    │
    │ godot --headless --script tests/run_tests.gd
    ▼
tests/run_tests.gd
    │
    ├──► tests/test_state_system.gd          (unit)
    ├──► tests/test_dialogue_parser.gd       (unit)
    ├──► tests/test_narrative_manager.gd     (unit)
    ├──► tests/test_scene_base.gd            (unit)
    ├──► tests/test_audio_manager.gd         (unit)
    ├──► tests/test_game_manager.gd          (unit)
    ├──► tests/test_rain_controller.gd       (unit)
    ├──► tests/test_hemingway_enforcer.gd    (unit)
    ├──► tests/test_condition_evaluator.gd   (unit)
    └──► [new] tests/test_integration.gd     (integration)
              │
              ├── Dialogue parsing integration
              │   └─ Parse all 9 JSON files → assert ok=true
              │
              ├── State transition integration
              │   └─ Set state → apply effects → assert state values
              │
              └── Ending determination integration
                  └─ Set state → call determine_ending() → assert result
```

### GUI Playtest Interaction Contract

```
Agent Tester (computer_use)
    │
    │ 1. Launch godot scenes/main.tscn
    │ 2. Click triggers (Office door, Lobby guard, etc.)
    │ 3. Read on-screen text (environmental text, dialogue)
    │ 4. Click dialogue choices
    │ 5. Observe scene transitions
    │ 6. Record observations in YAML report
    ▼
Playtest Report (tests/playtest/report-*.yaml)
    │
    ├── shallow: {total, passed, failed, failures[]}
    ├── middle: {total, passed, failed, excluded, failures[]}
    └── deep: {likert: {}, free_text: {}}
```

### State Evaluation Chain (for test assertions)

```
StateSystem.set_value(axis, value)
    │
    ▼
StateSystem._clamp(axis, value)        → clamped [0.0, 10.0]
    │
    ▼
StateSystem.state_changed.emit(axis, old, new)  → fires per axis
    │
    ├── NarrativeManager._on_state_changed(axis, old, new)
    │       │
    │       ▼
    │   NarrativeManager._calculate_tone(axis, value)
    │       │ returns "hope"/"neutral"/"despair" etc.
    │       │
    │       ▼
    │   NarrativeManager.scene_text_changed.emit(scene, tone)
    │
    └── AudioManager._on_state_changed(axis, old, new)
            │
            ▼
        AudioManager._update_ambient_for_state(axis, value)
```

---

## 5. Test Plan

### Test File Summary

| File | Type | Target |
|------|------|--------|
| Existing unit tests (9+ files) | Unit | Component-level validation per-module |
| `tests/playtest/checklist-shallow.yaml` | Structured checklist | AC1 — Scene loading, dialogue, transitions, text, sound |
| `tests/playtest/checklist-middle.yaml` | Structured checklist | AC2 — State branching, conditions, echoes, endings, edge cases |
| `tests/playtest/checklist-deep.yaml` | Likert rubric | AC3 — Qualitative thematic evaluation |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Scene Loading & Navigation | ✅ | S-01 through S-08 | ✅ |
| Dialogue System | ✅ | S-09 through S-20 | ≥2 (S-18, S-19) | ✅ |
| Scene Transitions | ✅ | S-21 through S-27 | ≥2 (S-22 desync) | ✅ |
| Environmental Text | ✅ | S-28 through S-42 | ≥3 (S-28→S-31, S-42) | ✅ |
| Sound System | ✅ | S-43 through S-45 | ≥1 (S-45) | ✅ |
| State-Dependent Branching | ✅ | M-01 through M-08 | ≥3 per test | ✅ |
| Dialogue Conditions & Effects | ✅ | M-09 through M-14 | ≥2 (M-12, M-13) | ✅ |
| Echo System | ✅ | M-15 through M-20 | ≥2 (M-17, M-20) | ✅ |
| Ending Determination | ✅ | M-21 through M-26 | ≥2 (M-22, M-25) | ✅ |
| Scene Transition Integration | ✅ | M-27 through M-30 | ≥1 (M-27) | ✅ |
| Edge Cases | ✅ | M-31 through M-35 | ✅ | ✅ |
| Sound System Integration | ✅ | M-36 through M-40 | ≥2 (M-36, M-39) | ✅ |

### Test Cases

#### Shallow Layer — 47 Items (TC-01 to TC-10 for key test scenarios)

**TC-01: Full Scene Load Walkthrough**
- **Type:** Normal path
- **Setup:** Launch `godot scenes/main.tscn` in GUI mode
- **Steps:**
  1. Observe console for launch errors
  2. Verify Office scene loads with WindowText, ScreensaverText, DesktopText, OfficeDoorTrigger nodes
  3. Click Office door → complete dialogue → verify Lobby loads with all expected nodes
  4. Click Lobby exit → verify Street loads with all expected nodes
  5. Click Store entrance → verify Store loads with all expected nodes
  6. Click Store exit → verify Bridge loads with all expected nodes
  7. Click Underpass entrance → verify Underpass loads with all expected nodes
  8. Click Subway entrance → verify Subway Station loads with all expected nodes
- **Assertions:** S-01 through S-08 pass. All 6 scenes load, all triggers/environment text nodes are visible.

**TC-02: All Dialogue Trigger Activation**
- **Type:** Normal path
- **Setup:** Scene loaded with any state
- **Steps:**
  1. Click each dialogue trigger in sequence: office_door, lobby_guard, lobby_stranger, store_clerk, bridge_homeless, underpass_stranger_echo, subway_ending
  2. For each: observe dialogue start, speaker name, dialogue text, choice buttons, dialogue end
- **Assertions:** S-09 through S-20 pass. All 7 dialogues start, display correctly, choices appear, dialogues end cleanly.

**TC-03: All Scene Transitions Verified**
- **Type:** Normal path
- **Setup:** Full playthrough
- **Steps:**
  1. Complete office_door dialogue → verify transition to Lobby with fade
  2. Click Lobby exit trigger → verify transition to Street
  3. Click Store entrance → verify transition to Store
  4. Click Store exit → verify transition to Bridge
  5. Click Underpass entrance → verify transition to Underpass
  6. Click Subway entrance → verify transition to Subway Station
- **Assertions:** S-21 through S-27 pass. Each transition plays fade effect and loads correct next scene.

**TC-04: All Environmental Text Rendered**
- **Type:** Normal path
- **Setup:** All scenes visited
- **Steps:**
  1. In each scene, visually verify all environment text nodes are present and readable
  2. Check Office: window, screensaver, desktop text
  3. Check Street: neon sign, graffiti
  4. Check Store: OPEN sign
  5. Check Bridge: traffic, homeless, rain text
  6. Check Underpass: graffiti, light text
  7. Check Subway: ticket gate, clock (11:47 PM), broadcast, stranger final text
- **Assertions:** S-28 through S-42 pass. All 15 environment text nodes are visible.

**TC-05: All 9 Dialogue JSON Files Parse**
- **Type:** Headless validation
- **Setup:** Run headless script that loads all 9 JSON files via DialogueParser
- **Steps:**
  1. For each JSON file: call `DialogueParser.load_dialogue(filepath)`
  2. Assert `result.ok == true`
  3. Assert `result.nodes.size() > 0`
- **Assertions:** S-20, S-46 pass. All JSON files parse without errors.

**TC-06: Existing Test Suite Baseline**
- **Type:** CI gate
- **Setup:** `godot --headless --script tests/run_tests.gd`
- **Steps:**
  1. Run headless test suite
  2. Check exit code is 0
  3. Check stderr is empty (no warnings or errors)
- **Assertions:** S-46, S-47 pass. No regression.

#### Middle Layer — Key Test Cases (TC-07 to TC-15)

**TC-07: State-Dependent Branching — Office Window Text**
- **Type:** State branching
- **Setup:** Office scene loaded
- **Steps:**
  1. Set hope slider to 2 → verify WindowText shows despair variant
  2. Set hope slider to 5 → verify WindowText shows neutral variant
  3. Set hope slider to 8 → verify WindowText shows hope variant
- **Assertions:** M-01 passes. Window text changes between despair/neutral/hope.

**TC-08: State-Dependent Branching — Neon Sign Color**
- **Type:** State branching
- **Setup:** Street scene loaded
- **Steps:**
  1. Set conviction slider to 2 → verify neon sign color (red shift)
  2. Set conviction slider to 5 → verify neon sign color (neutral)
  3. Set conviction slider to 8 → verify neon sign color (amber shift)
- **Assertions:** M-02 passes. Neon sign color shifts with conviction.

**TC-09: Dialogue Condition Gating**
- **Type:** Dialogue conditions
- **Setup:** Lobby scene with Stranger dialogue
- **Steps:**
  1. Set hope=2, conviction=2 → triggered dialogue shows only default choices (conditions fail)
  2. Set hope=7, conviction=7 → triggered dialogue shows gated choices (conditions pass)
- **Assertions:** M-09 passes. Conditions correctly gate choice visibility.

**TC-10: Dialogue Effects (slider_delta & set_flag)**
- **Type:** Dialogue effects
- **Setup:** Any scene with dialogue that applies effects
- **Steps:**
  1. Choose a dialogue option with `slider_delta: {axis: "hope", value: 1}`
  2. Assert `StateSystem.get_value("hope")` increased by 1
  3. Choose an option with `set_flag: {flag: "met_stranger", value: true}`
  4. Assert `GameManager.has_flag("met_stranger")` returns true
- **Assertions:** M-10, M-11 pass. Effects modify state correctly.

**TC-11: Anti-Loop Termination**
- **Type:** Edge case
- **Setup:** Any dialogue with MAX_NODE_VISITS=3
- **Steps:**
  1. Visit the same dialogue node 3 times
  2. On 4th visit, verify dialogue force-ends with `dialogue_ended` signal
- **Assertions:** M-12 passes. Anti-loop prevents infinite cycles.

**TC-12: Echo System — Screensaver Echo on Bridge**
- **Type:** Echo trigger
- **Setup:** StateSystem.conviction ≤ 2, Bridge scene
- **Steps:**
  1. Set conviction to 2
  2. Enter Bridge scene (or reload)
  3. Trigger homeless NPC dialogue
  4. Verify screensaver_echo fires (homeless says "你做游戏有什么用？")
- **Assertions:** M-15 passes. Echo triggers at correct state threshold.

**TC-13: Ending Determination — Keep Walking**
- **Type:** Ending logic
- **Setup:** StateSystem values set for Keep Walking
- **Steps:**
  1. Set hope ≥ 6 AND will ≥ 5
  2. Enter Subway Station
  3. Click gate trigger
  4. Verify Keep Walking ending dialogue starts
  5. Verify ending text matches "forward" variants
- **Assertions:** M-21, M-24, M-25 pass.

**TC-14: Ending Determination — Turn Back (Highest Priority)**
- **Type:** Ending logic
- **Setup:** conviction ≤ 3 (overrides other endings)
- **Steps:**
  1. Set conviction to 2 (hope and will can be any value)
  2. Enter Subway Station
  3. Click Turn Back trigger (or any trigger — ending should match Turn Back)
  4. Verify Turn Back ending dialogue starts
  5. Verify ending text matches "backward" variants
- **Assertions:** M-22, M-24 pass. Turn Back has highest priority.

**TC-15: State Carries Across Scene Transitions**
- **Type:** Integration
- **Setup:** Full playthrough
- **Steps:**
  1. In Office, make a dialogue choice that sets hope to 7
  2. Transition to Lobby
  3. Verify Lobby entrance text shows hope-based variant
  4. Verify `NarrativeManager.current_scene_index` = 1
- **Assertions:** M-27, M-29 pass. State and scene index carry across transitions.

**TC-16: Rapid Trigger Clicking**
- **Type:** Edge case
- **Setup:** Scene with dialogue trigger
- **Steps:**
  1. Click same trigger rapidly 10 times within 1 second
  2. Observe game does not crash
  3. Dialogue should not start multiple times (re-entrance guard)
- **Assertions:** M-31 passes. No crash on rapid input.

**TC-17: Zero-State & Max-State Extremes**
- **Type:** Edge case
- **Setup:** All state axes at minimum, then all at maximum
- **Steps:**
  1. Set hope=0, conviction=0, will=0
  2. Navigate all triggers — no crashes, text renders
  3. Set hope=10, conviction=10, will=10
  4. Navigate all triggers — no crashes, text renders
- **Assertions:** M-33, M-34 pass. Extremes don't break the game.

**TC-18: AC3 Hidden Text in Underpass**
- **Type:** State-dependent content
- **Setup:** hope ≤ 2 AND conviction ≤ 2
- **Steps:**
  1. Set hope=2, conviction=2
  2. Enter Underpass scene
  3. Verify "你的影子" hidden text appears
- **Assertions:** M-19 passes. AC3 hidden text renders at correct state threshold.

**TC-19: Hope_Despair Axis Integration**
- **Type:** Sound/state integration
- **Setup:** Any scene with state change
- **Steps:**
  1. Trigger state change dialogue that affects hope
  2. Verify `NarrativeManager._build_state_snapshot()` includes "hope_despair" axis
  3. Verify condition evaluator recognizes "hope_despair" axis
- **Assertions:** M-39, M-40 pass.

**TC-20: Dialogue History Persistence**
- **Type:** Integration
- **Setup:** Two-scene playthrough
- **Steps:**
  1. Make a choice in Office dialogue
  2. Transition to Lobby
  3. Verify `GameManager.choices_history` contains the Office choice
  4. Verify dialogue state restoration in Lobby
- **Assertions:** M-14, M-28 pass. Choice history persists across transitions.

---

## 6. Files Changed

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `tests/playtest/` | **New** directory | Playtest assessment infrastructure | ~600 |
| `tests/playtest/checklist-shallow.yaml` | **New** | Shallow-layer acceptance checklist (47 items) | ~120 |
| `tests/playtest/checklist-middle.yaml` | **New** | Middle-layer acceptance checklist (40 items) | ~160 |
| `tests/playtest/checklist-deep.yaml` | **New** | Deep-layer evaluation rubric (10 dims + 6 prompts) | ~60 |
| `tests/playtest/report-template.yaml` | **New** | Structured tester report template | ~50 |
| `tests/playtest/README.md` | **New** | Playtest protocol instructions for agent testers | ~80 |

### No Code Changes to Existing Files

This plan phase produces **design documentation and test infrastructure only**. No behavioral changes to existing `.gd` scripts are part of this issue. All existing modules are **inspected** during the playtest but not modified.

If bugs are discovered during playtest, they are filed as separate implement-phase issues.

---

## 7. Verification Checklist

- [ ] S-01 through S-08: All 6 scenes load with correct nodes (AC1 — 8 checks)
- [ ] S-09 through S-20: All 7 dialogue triggers activate and display correctly (AC1 — 12 checks)
- [ ] S-21 through S-27: All 6 scene transitions work with fade effects (AC1 — 7 checks)
- [ ] S-28 through S-42: All 15 environmental text nodes render correctly (AC1 — 15 checks)
- [ ] S-43 through S-45: AudioManager registers no errors (AC1 — 3 checks)
- [ ] S-46 through S-47: All existing unit tests pass headless (AC1 — 2 checks)
- [ ] M-01 through M-08: ≥5 of 8 state-dependent branching checks pass (AC2 — ≥60%)
- [ ] M-09 through M-14: ≥4 of 6 dialogue conditions & effects checks pass (AC2 — ≥60%)
- [ ] M-15 through M-20: ≥4 of 6 echo system checks pass (AC2 — ≥60%)
- [ ] M-21 through M-26: ≥4 of 6 ending determination checks pass (AC2 — ≥60%)
- [ ] M-27 through M-30: ≥3 of 4 scene transition integration checks pass (AC2 — ≥60%)
- [ ] M-31 through M-35: ≥3 of 5 edge case checks pass (AC2 — ≥60%)
- [ ] M-36 through M-40: ≥3 of 5 sound system integration checks pass (AC2 — ≥60%)
- [ ] D-01 through D-10: ≥2 testers rate D-01 at ≥4/5 (AC3 — qualitative pass)
- [ ] Tester reports collected → synthesis → bug inventory filed as separate issues
- [ ] No regression on existing features
- [ ] All pre-existing tests still pass

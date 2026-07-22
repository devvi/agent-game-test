# Research: MVP Playtest & Layered Verification (#57)

> Parent Issue: #57
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The MVP vertical slice (Issues 1–17) has been implemented incrementally through individual PRs for each feature: narrative architecture (Issue #45), dialogue engine (#46, #52), scene scaffolding (#55, #58), state system (#50), sound system (#48), text components (#49), and full story content (#56). Each feature was validated against its own acceptance criteria at the unit/component level.

What has NOT been done:

1. **End-to-end playtest** — No one has actually "played through" the full game from office → lobby → store → bridge → underpass → subway_station with all state permutations
2. **Cross-feature integration verification** — Individual features pass their own tests, but no testing validates whether they work correctly *together* (e.g., state choice in dialogue → scene transition → environmental text updating with new state)
3. **Layered acceptance criteria verification** — Each issue defined shallow/middle/deep acceptance criteria, but they were never verified as a unified whole across the vertical slice
4. **Thematic coherence check** — The game's core metaphor (都市夜行人 = urban night walker as introspection journey) has never been qualitatively evaluated
5. **Bug inventory** — No systematic bug-tracking sweep has been performed on the fully assembled game

### Expected Behavior

A structured, repeatable playtest protocol executed by **3 agent testers** (LLM-based QA agents) plus automated CI validation:

1. **Shallow layer (AC1):** All 100% pass — every scene loads, every trigger responds, every dialogue completes without crash, all environmental text renders
2. **Middle layer (AC2):** ≥60% pass — state-dependent branching works correctly, echo system fires at right moments, scene transitions preserve state, endings correctly determined
3. **Deep layer (AC3):** Qualitative evaluation by ≥2 testers — the metaphor of urban walking as introspection is felt; pacing supports emotional arc; narrative coherence holds across all 6 scenes

### User Scenarios

- **Scenario A (Full playthrough, neutral state):** A tester plays through all 6 scenes sequentially. All triggers are clickable, all dialogues are readable, scene transitions work. No crashes, no blank text.
- **Scenario B (High-hope playthrough):** A tester makes choices that maximize hope/conviction/will. Environmental text shifts to positive variants. Keep Walking ending triggers.
- **Scenario C (Despair playthrough):** A tester makes choices that minimize hope/conviction/will. Environmental text shifts to despair variants. Turn Back ending triggers.
- **Scenario D (State-boundary playthrough):** A tester deliberately triggers edge cases — transitioning between scenes mid-dialogue, rapidly clicking triggers, loading dialogues multiple times.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally — each issue had its own test suite and acceptance criteria at the component level. Integration testing across all 17+ issues was **explicitly deferred** to the MVP milestone. This is standard in incremental development: individual features are validated in isolation before the "whole is greater than the sum of its parts" check.

### Why Change Now?

All core features for the MVP vertical slice are implemented and merged:
- Scenes: office, lobby, street, convenience_store, bridge, underpass, subway_station (Issues #55, #58)
- Narrative: NarrativeManager, SceneBase, 5-state tones, echo system (Issue #45, #50)
- Dialogue: parser, runner, condition evaluator, 3D display, Hemingway enforcer (Issues #46, #52)
- Content: 9 dialogue JSON files, environmental text in all scenes (Issue #56)
- Systems: GameManager, StateSystem, AudioManager, RainController (Issues #47, #48, #49, #50)
- Tests: 80+ unit tests across the full stack

Without an integrated playtest, the team cannot confirm that the game is actually playable end-to-end. A broken integration (e.g., scene transition not updating state, dialogue condition not reading the right axis) would make the entire MVP non-functional despite all component tests passing.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| Test framework | GDScript `SceneTree` mode via `tests/run_tests.gd` |
| Headless testing | `godot --headless --script tests/run_tests.gd` — no GUI, pure logic |
| Interactive testing | Requires GUI — `godot scenes/main.tscn` — can only be driven via `computer_use` |
| Autoloads | GameManager, StateSystem, NarrativeManager, AudioManager — all must be present at runtime |
| State axes | hope (0–10), conviction (0–10), will (0–10), hope_despair (-10–+10) |
| Hemingway constraint | Max 3 sentences, max 25 chars per sentence enforced at runtime |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Inspection |
|------|--------|---------------------|
| `gdscripts/narrative_manager.gd` | NarrativeManager | Validate scene sequence, ending determination, echo triggering |
| `gdscripts/scene_base.gd` | SceneBase | Validate fade-in, dialogue state restoration |
| `gdscripts/office.gd` | OfficeScene | Verify environmental text variants, door trigger |
| `gdscripts/lobby.gd` | LobbyScene | Verify guard/stranger/exit triggers, tone switching |
| `gdscripts/street.gd` | StreetScene | Verify neon sign conviction modulation, graffiti hope visibility |
| `gdscripts/store.gd` | StoreScene | Verify OPEN sign Stranger foreshadowing condition |
| `gdscripts/bridge.gd` | BridgeScene | Verify railing/homeless/exit triggers, intrusive thought, echo trigger |
| `gdscripts/underpass.gd` | UnderpassScene | Verify graffiti/echo/exit triggers, AC3 hidden text, echo display |
| `gdscripts/subway_station.gd` | SubwayStationScene | Verify gate/turn_back/bench triggers, ending text, environment tone |
| `gdscripts/dialogue_runner.gd` | DialogueRunner | Validate dialogue start, choice navigation, effects, anti-loop |
| `gdscripts/state_system.gd` | StateSystem | Verify state transitions, clamping, resistance, signal emission |
| `gdscripts/game_manager.gd` | GameManager | Verify slider delegation, flag storage, choice persistence |
| `gdscripts/rain_controller.gd` | RainController | Verify rain intensity conviction mapping |
| `gdscripts/audio_manager.gd` | AudioManager | Verify scene registration, ambient audio, footstep triggers |
| `dialogues/*.json` (9 files) | Dialogue data | Validate all JSON is parseable, no dangling references |
| `tests/*.gd` | Test suite | Re-run all existing tests as baseline verification |

### Indirectly Affected Modules

| File | Why Affected |
|------|-------------|
| `scenes/*/*.tscn` (6 scene files) | Scene tree structure must match script references (node paths, trigger names) |
| `.github/workflows/opencode-review.yml` | CI workflow may need playtest step added |
| `docs/GAME_DESIGN/*.md` | Test findings may reveal gaps in design documentation |

### Documents to Create

| Document | Purpose |
|----------|---------|
| `docs/PRD/57-mvp-playtest-layered-verification.md` | This document |
| `tests/playtest/` (new directory) | Agent playtest scripts and protocol |
| `tests/playtest/checklist-shallow.yaml` | Shallow-layer acceptance checklist |
| `tests/playtest/checklist-middle.yaml` | Middle-layer acceptance checklist |
| `tests/playtest/checklist-deep.yaml` | Deep-layer evaluation rubric |

### Documents to Update

- [x] `docs/PRD/57-mvp-playtest-layered-verification.md` (this document)
- [ ] `docs/TESTS/` — add playtest protocol reference
- [ ] `README.md` — add playtest results badge (pass/fail summary)

---

## 4. Solution Comparison

### Approach A: Automated Headless Test Runner (CI-First)

**Description:** Expand the existing `tests/run_tests.gd` GDScript test runner with integration test functions that exercise the full vertical slice programmatically — instantiate scenes, simulate dialogue choices, verify state transitions, and assert on environmental text values — all in `--headless --script` mode.

**Pros:**
- Fully repeatable, no GUI needed
- Runs in CI (GitHub Actions) on every push
- Produces deterministic pass/fail results
- Can be extended incrementally
- Fast execution (~seconds)

**Cons:**
- Cannot test visual rendering, timing, or "feel"
- Headless mode cannot instantiate scenes with 3D nodes (scenes require a Viewport)
- Dialogue runner's signal-based architecture is hard to test outside a live scene tree
- Misses deep/thematic evaluation entirely

**Risk:** Medium — headless limitations mean only 30–50% of the vertical slice can be tested this way

**Effort:** 3–5 days

### Approach B: GUI-Based Agent Playtest (Primary)

**Description:** Use `computer_use` tool to drive Godot in GUI mode. An LLM agent "plays" through the game: clicking triggers, reading on-screen text, navigating dialogue choices, observing scene transitions, and recording observations. Each tester plays through multiple state paths. Results are recorded as structured bug reports and checklist pass/fail.

**Pros:**
- Exercises the real game — the exact same binary a human would play
- Can observe visual output, text rendering, timing
- Can evaluate deep/thematic quality
- Detects visual bugs (missing text, bad layouts, wrong colors)
- Most faithful to real player experience

**Cons:**
- Slow (~10–20 minutes per full playthrough)
- Non-deterministic (timing, rendering may vary)
- Requires `computer_use` environment with display server
- Cannot run in CI directly (needs a macOS/Linux desktop)
- LLM agent may hallucinate observations or miss subtle issues

**Risk:** Low — captures the majority of real issues; deep evaluation is inherently qualitative

**Effort:** 2–3 days setup + 1 day per tester round

### Approach C: Hybrid — Headless Integration Suite + GUI Agent Playtest

**Description:** Combine both approaches. Run headless integration tests for all logic that can be tested without a GUI (dialogue parsing, state transitions, ending determination, condition evaluation). Run GUI agent playtests for visual, interactive, and deep-layer verification. The headless suite gates CI; the GUI playtest produces the final sign-off report.

**Pros:**
- Best coverage — logic verified by deterministic tests, UX verified by agent playtest
- Headless suite catches regressions fast in CI
- Agent playtest focuses on what only a human (or agent simulating a human) can evaluate
- Minimizes wasted agent compute on easily-automated checks

**Cons:**
- Two test systems to maintain
- Headless test coverage has gaps (cannot test per-scene environmental text rendering in 3D)
- Callback-heavy GDScript architecture makes headless mocking complex

**Risk:** Low — this is the standard industry approach (unit + integration + manual QA)

**Effort:** 3–4 days (1–2 for headless expansion, 2 for playtest protocol + execution)

### Recommendation

→ **Approach C (Hybrid)** because:

1. **Headless automation covers 50%** of the shallow layer deterministically (dialogue parsing, condition evaluation, state transitions, ending logic, sound system deregistration) — this should run in CI and gate merges
2. **GUI agent playtest covers the rest** (scene loading, text rendering, dialogue interaction, scene transitions, echo system, endings) — this is where real bugs are found
3. **Deep evaluation is inherently agent-based** — no automated test can assess "does this feel like an introspection journey"
4. **The existing test harness** (`tests/run_tests.gd`) is already in place and runs headless; expanding it is low effort
5. **Separation of concerns**: if headless tests pass but the playtest fails, the bug is in integration/rendering — not in core logic

---

## 5. Boundary Conditions & Acceptance Criteria

### Complete Shallow Acceptance Checklist (AC1 — 100% Must Pass)

All items must pass for each of the 3 testers across any single playthrough.

#### Scene Loading & Navigation

| ID | Check | How to Verify |
|----|-------|---------------|
| S-01 | Game launches without errors | No console errors on start |
| S-02 | Office scene loads with all 4 environment text nodes visible | WindowText, ScreensaverText, DesktopText, OfficeDoorTrigger present |
| S-03 | Lobby scene loads with all 3 environment text nodes + 3 triggers | EntranceText, StrangerSpotlight visible; guard/stranger/exit triggers enabled |
| S-04 | Street scene loads with environment text + store entrance trigger | NeonSign, Graffiti, StreetSign, StoreEntranceTrigger present |
| S-05 | Convenience Store loads with OPEN sign, clerk trigger, exit trigger | OpenSign visible, triggers active |
| S-06 | Bridge loads with traffic/homeless/rain text + 3 triggers | TrafficText, HomelessText, RainBridgeText visible; triggers active |
| S-07 | Underpass loads with graffiti/echo/light + 3 triggers | GraffitiText, EchoText, UnderpassLight visible; triggers active |
| S-08 | Subway Station loads with all environment text + 3 trigger zones | TicketGateText, ClockText, BroadcastText, StrangerFinalText visible; triggers active |

#### Dialogue System

| ID | Check | How to Verify |
|----|-------|---------------|
| S-09 | Office door dialogue starts on trigger click | `office_door.json` loads, first node displays |
| S-10 | Lobby guard dialogue starts on trigger click | `lobby_guard.json` loads |
| S-11 | Lobby stranger dialogue starts on trigger click | `lobby_stranger.json` loads |
| S-12 | Store clerk dialogue starts on trigger click | `store_clerk.json` loads |
| S-13 | Bridge homeless dialogue starts on trigger click | `bridge_homeless.json` loads |
| S-14 | Underpass stranger echo dialogue starts on trigger click | `underpass_stranger_echo.json` loads |
| S-15 | Subway ending dialogue starts on gate/turn_back/bench trigger | `subway_ending.json` loads |
| S-16 | Dialogue displays speaker name and text | SpeakerLabel and DialogueText render |
| S-17 | Choices appear after text (reveal delay) | At least 1 choice button visible within 2s |
| S-18 | Clicking a choice advances dialogue or ends conversation | `choice_made` signal fires |
| S-19 | Dialogue properly ends (exit to empty state) | `dialogue_ended` signal fires, UI clears |
| S-20 | All 9 JSON dialogue files parse without errors | `DialogueParser.load_dialogue()` returns ok=true for each |

#### Scene Transitions

| ID | Check | How to Verify |
|----|-------|---------------|
| S-21 | Office → Lobby transition on door dialogue completion | Scene changes, fade plays |
| S-22 | Lobby → Street transition on exit trigger | Scene changes |
| S-23 | Street → Store transition on store entrance click | Scene changes |
| S-24 | Store → Bridge exit transition | Scene changes |
| S-25 | Bridge → Underpass exit transition | Scene changes |
| S-26 | Underpass → Subway Station exit transition | Scene changes |
| S-27 | Fade-in plays on each scene entry | Visual fade effect observed |

#### Environmental Text

| ID | Check | How to Verify |
|----|-------|---------------|
| S-28 | Office window text renders with correct state tone | At least one of hope/neutral/despair variants visible |
| S-29 | Office screensaver text renders ("你做游戏有什么用？") | Text is visible |
| S-30 | Office desktop text renders ("Deadline: Day X/90") | Day counter visible |
| S-31 | Street neon sign renders with conviction-dependent color | Modulate color set |
| S-32 | Street graffiti renders with hope-dependent text | Text variant visible |
| S-33 | Store OPEN sign renders | Text "OPEN" visible |
| S-34 | Bridge traffic text renders | Visible |
| S-35 | Bridge homeless text renders | Visible |
| S-36 | Bridge rain text renders | Visible |
| S-37 | Underpass graffiti text renders | Visible |
| S-38 | Underpass light text renders | Visible |
| S-39 | Subway ticket gate text renders | Visible |
| S-40 | Subway clock text renders ("11:47 PM") | Visible |
| S-41 | Subway broadcast text renders | Visible |
| S-42 | Subway stranger final text renders (ending-dependent) | Visible |

#### Sound System

| ID | Check | How to Verify |
|----|-------|---------------|
| S-43 | AudioManager autoload exists and does not crash | Console: no errors on GameManager init |
| S-44 | Each scene calls `register_scene()` without error | Console: no "method not found" errors |
| S-45 | `play_sound` effect type in `dialogue_runner.gd` does not crash | Console: no errors when walking choices selected |

#### Test Suite Baseline

| ID | Check | How to Verify |
|----|-------|---------------|
| S-46 | All existing unit tests pass | `godot --headless --script tests/run_tests.gd` exits 0 |
| S-47 | No test produces console warnings or errors | stderr is empty |

### Middle Acceptance Checklist (AC2 — ≥60% Must Pass)

Failing items must be documented with reproduction steps and suggested fixes.

#### State-Dependent Branching

| ID | Check | Priority | How to Verify |
|----|-------|----------|---------------|
| M-01 | Office window text changes between hope/neutral/despair based on hope slider | High | Set hope to 2, 5, 8 — text should change |
| M-02 | Street neon sign color changes with conviction slider | High | Set conviction to 2, 5, 8 — color should shift from red to amber |
| M-03 | Street graffiti text changes based on hope | High | Set hope to 2 vs 8 — text changes from "i was here" to "this too shall pass" |
| M-04 | Store OPEN sign shows Stranger foreshadowing when hope≥5 AND conviction≥4 | High | Verify text "⌈He was here tonight.⌋" appears |
| M-05 | Bridge traffic/homeless/rain text changes with will-based tone (tired/neutral/determined) | High | Set will to 2, 5, 8 — text changes |
| M-06 | Underpass graffiti text changes with combined hope+conviction tone | High | Set both low vs both high — text changes |
| M-07 | Subway station environment text matches ending tone (forward/backward/waiting) | High | Verified by checking ending result |
| M-08 | Lobby entrance text changes with conviction-based tone (fear/neutral/defiant) | High | Set conviction to 2, 5, 8 |

#### Dialogue Conditions & Effects

| ID | Check | Priority | How to Verify |
|----|-------|----------|---------------|
| M-09 | Dialogue choices with slider conditions correctly gate visibility | High | Test `condition_evaluator.gd` with known state |
| M-10 | `slider_delta` effect modifies state after choice made | High | Verify hope/conviction/will changes after choice |
| M-11 | `set_flag` effect sets flag accessible via `has_flag()` | High | Verify flag state before/after |
| M-12 | Dialogue node anti-loop (MAX_NODE_VISITS=3) terminates conversation | Medium | Visit same node 4 times — conversation should force-end |
| M-13 | Default choice fallback works when all gated choices hidden | Medium | Create state where all conditions fail; default choice should show |
| M-14 | Dialogue state persists across scene transitions via GameManager.choices_history | High | Make choice in office, transition to lobby — verify restoration |

#### Echo System

| ID | Check | Priority | How to Verify |
|----|-------|----------|---------------|
| M-15 | `screensaver_echo` triggers on bridge when conviction ≤ 2 (intrusive thought) | High | Set conviction=2, enter bridge — verify echo fires |
| M-16 | `rain_echo` triggers on underpass Stranger trigger | High | Click Stranger in underpass — verify echo triggered signal |
| M-17 | Echo repeat suppression works (same echo can't fire twice) | Medium | Trigger same echo twice — second call suppressed |
| M-18 | Underpass echo text displays screensaver echo when triggered | Medium | Echo text shows screensaver quote |
| M-19 | Underpass AC3 hidden text appears when hope≤2 AND conviction≤2 | High | Set both to 2 — verify "你的影子" text |
| M-20 | At least 3 of 6 defined echoes are observable in a single playthrough | Medium | Count unique echo trigger events |

#### Ending Determination

| ID | Check | Priority | How to Verify |
|----|-------|----------|---------------|
| M-21 | Keep Walking triggers when hope≥6 AND will≥5 | High | Set state accordingly, enter subway station |
| M-22 | Turn Back triggers when conviction≤3 (highest priority) | High | Set conviction=2, any hope/will |
| M-23 | Stay triggers as fallthrough when no other ending matches | High | Set all values mid-range (5.0 each) |
| M-24 | Ending text matches ending type (keep_walking/turn_back/stay) | High | Verify StrangerFinalText and BroadcastText |
| M-25 | Each ending trigger zone only opens dialogue for matching ending | Medium | Gate only triggers KW dialogue, bench only Stay dialogue |
| M-26 | Ending determination is consistent per play session | Medium | Scene reload gives same ending without state change |

#### Scene Transition Integration

| ID | Check | Priority | How to Verify |
|----|-------|----------|---------------|
| M-27 | State carries across scene transitions | High | Change hope in office, verify lobby entrance text reflects new state |
| M-28 | Dialogue history carries across scene transitions | Medium | `choices_history` restored in new scene |
| M-29 | NarrativeManager.current_scene_index increments correctly | High | Verify sequential: 0→1→2→3→4→5 |
| M-30 | AudioManager.register_scene called on each scene load | Medium | Verify no warning for missing scene profile |

#### Edge Cases

| ID | Check | Priority | How to Verify |
|----|-------|----------|---------------|
| M-31 | Rapid trigger clicking does not crash game | Medium | Click same trigger rapidly 10x — game continues |
| M-32 | Dialogue trigger during active dialogue (re-entrance) | Medium | Click stranger trigger while stranger dialogue active — no crash |
| M-33 | All state axes at minimum (hope=0, conviction=0, will=0) | Medium | Set all to 0 — no crashes, text renders |
| M-34 | All state axes at maximum (hope=10, conviction=10, will=10) | Medium | Set all to 10 — no crashes, text renders |
| M-35 | Rain intensity at extremes (conviction=0 → 1.0, conviction=10 → 0.0) | Low | Verify `rain_controller.gd` clamp |

#### Sound System Integration

| ID | Check | Priority | How to Verify |
|----|-------|----------|---------------|
| M-36 | Footstep `play_sound` effect type processes without error | Medium | Choose walking choice — verify console |
| M-37 | AudioManager.get_surface_for_scene returns valid surface | Low | Verify mapping: office→"office", bridge→"stone" etc. |
| M-38 | State change triggers NarrativeManager tone recalculation | High | Verify `scene_text_changed` signal fires on state change |
| M-39 | Dialogue state snapshot includes hope_despair axis | High | Verify `_build_state_snapshot()` includes "hope_despair" |
| M-40 | Condition evaluator recognizes "hope_despair" axis | High | Test `evaluate({axis:"hope_despair",op:"gte",value:2})` |

### Deep Acceptance Evaluation Rubric (AC3 — Qualitative)

Each tester completes a qualitative evaluation form (1–5 Likert scale + free-text). At least 2 testers must report feeling the metaphor/introspection for AC3 to pass.

| Dimension | Question | Scale |
|-----------|----------|-------|
| D-01 | **Metaphor clarity**: Does the game communicate that the walk is an introspection journey? | 1 (No) → 5 (Strongly) |
| D-02 | **Emotional arc**: Does the 6-scene journey have a discernible emotional progression? | 1 (Flat) → 5 (Clear arc) |
| D-03 | **Pacing**: Does each scene feel appropriately paced (not too fast, not too slow)? | 1 (Broken) → 5 (Natural) |
| D-04 | **State-world feedback**: Does changing the slider values change how the world feels to you? | 1 (No difference) → 5 (Profound) |
| D-05 | **Narrative coherence**: Do the 6 scenes feel connected as a single night's journey? | 1 (Disjointed) → 5 (Coherent) |
| D-06 | **Hemingway style**: Does the short, constrained text work for the atmosphere? | 1 (Too limiting) → 5 (Perfect fit) |
| D-07 | **Echo system perception**: Did you notice any repeated imagery or phrases across scenes? | 1 (Not at all) → 5 (Clearly intentional) |
| D-08 | **Ending emotional impact**: Did the ending(s) you saw feel earned by your choices? | 1 (Random) → 5 (Earned) |
| D-09 | **Atmosphere**: Does the lo-fi 3D visual + audio create the intended Hopper-esque mood? | 1 (Fails) → 5 (Succeeds) |
| D-10 | **Would replay**: Would you play through again to see different endings/text? | 1 (No) → 5 (Yes) |

**Qualitative prompts for free-text:**

1. "What is this game about? (in your own words)"
2. "Describe a moment that stood out to you."
3. "What did the Stranger represent to you?"
4. "Did the ending(s) feel consistent with the journey?"
5. "What one thing would you change to make the metaphor stronger?"
6. "Did you notice any recurring symbols or phrases? What were they?"

#### AC3 Pass Criteria

- AC3-PASS: ≥2 testers rate D-01 (Metaphor clarity) at ≥4/5
- AC3-BONUS: ≥2 testers rate D-04 (State-world feedback) at ≥4/5
- AC3-BONUS: ≥1 tester identifies the Stranger as internal projection unprompted
- AC3-FAIL: Only 0–1 tester rates D-01 at ≥4/5 → document structural therapy suggestions

### Test Data Collection Format

Each tester produces a structured report:

```yaml
tester_id: "agent-cua-1"         # Unique tester identifier
date: "2026-07-23"
playthrough_path: "office→lobby→street→store→bridge→underpass→subway_station"

shallow:
  total: 47
  passed: 44
  failed: 3
  failures:
    - id: "S-15"
      description: "Subway ending dialogue on gate trigger"
      reproduction: "Clicked gate trigger after keep_walking ending determined"
      observed: "DialogueRunner.start returned false"
      expected: "Dialogue starts with subway_ending.json"
      severity: "blocking"

middle:
  total: 40
  passed: 28
  failed: 12
  excluded: []   # Items that could not be tested (e.g., visual-only checks in headless)
  failures:
    - id: "M-05"
      description: "Bridge text change with will tone"
      state_used: {will: 2.0}
      observed: "TrafficText shows neutral variant"
      expected: "TrafficText shows 'tired' variant"
      suggestion: "Check _get_tone() in bridge.gd — may still use legacy axis mapping"
      severity: "major"

deep:
  likert:
    D-01: 4
    D-02: 3
    D-03: 3
    D-04: 5
    D-05: 4
    D-06: 4
    D-07: 3
    D-08: 4
    D-09: 3
    D-10: 4
  free_text:
    D-Q1: "A lonely night walk where the city reflects your inner state..."
    D-Q2: "The bridge homeless scene — felt like looking at a possible future self..."
    D-Q3: "A projection of doubt/guidance — not a real person"
    D-Q4: "Turn Back ending felt consistent with my low-conviction choices"
    D-Q5: "Make the rain more responsive — it's a great atmospheric tool"
    D-Q6: "The screensaver echo was subtle but noticeable"
```

### Normal Path

1. **Setup:** Clone repo, verify Godot 4.7.1 available, source GH_TOKEN
2. **Baseline:** Run `godot --headless --script tests/run_tests.gd` → must exit 0 (S-46, S-47)
3. **Headless shallow suite:** Run new integration tests for dialogue parsing, state evaluation, ending logic
4. **GUI playtest (Tester 1):** Full playthrough with neutral state → record shallow + middle + deep
5. **GUI playtest (Tester 2):** High-hope playthrough → verify different endings + state paths
6. **GUI playtest (Tester 3):** Low-hope/despair playthrough → verify edge cases + AC3 hidden text
7. **Synthesis:** Merge 3 reports, calculate AC1/AC2/AC3 pass rates, produce bug inventory
8. **Sign-off:** PRD → PLAN → IMPLEMENT for fixes

### Edge Cases

1. **Fresh game vs. continued game**: First playthrough vs starting from GameManager with pre-set state — all 6 scenes should be navigable
2. **All interaction zones at once**: If multiple triggers overlap, only the first clicked should activate
3. **Scene transition during dialogue**: If dialogue is active when exit trigger is clicked, behavior should be well-defined (queue or ignore)
4. **Missing autoloads**: If any autoload (GameManager, StateSystem, NarrativeManager, AudioManager) fails to register, scene scripts should degrade gracefully
5. **Zero-state playthrough**: All dialogue choices skipped, shortest possible path — ending determination still works
6. **Rapid state change**: Multiple `apply_choice()` calls in rapid succession — state should converge correctly
7. **Browser/headless mode**: The game is designed for GUI — headless tests are supplementary, not replacements

### Failure Paths

1. **Dialogue JSON parse error**: Silent failure in production — playtest must detect this by triggering every dialogue at least once
2. **Missing node path in scene tree**: Script references a node that doesn't exist → `@onready var` produces runtime error on scene load
3. **Condition axis mismatch**: Dialogue condition references "hope_despair" but evaluator expects "hope" → invisible choice gate
4. **Scene transition desync**: `NarrativeManager.advance_scene()` increments index but `SceneManager` fails to change scene → state out of sync
5. **Autoload not ready on first scene load**: Scene tries to access StateSystem in `_ready()` before autoloads are initialized

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #56 — Story content (full dialogue JSON + environmental text) | ✅ Closed | Low — content is merged |
| #48 — Sound system | ✅ Closed | Low — audio is merged |
| #50 — State-world feedback | ✅ Closed | Low — 5-state system is merged |
| All 6 scenes (office, lobby, street, store, bridge, underpass, subway_station) | ✅ Merged | Low |
| All 9 dialogue JSON files exist (office_door, lobby_guard, lobby_stranger, store_clerk, store_exit, bridge_homeless, underpass_stranger_echo, subway_ending, bartender) | ✅ Merged | Low |
| Godot 4.7.1 installed and accessible via CLI | ✅ Known | Low — confirmed in project config |
| `computer_use` tool available for GUI playtest | ✅ Available | Medium — requires macOS desktop |
| 3 agent testers available | ✅ Available | Low — can reuse same agent with different instructions |

### Blocks

| Future Work | Priority |
|-------------|----------|
| All implement-phase fixes for bugs discovered in playtest | High |
| Issue #59 — Mysterious Stranger NPC (depends on knowing current game state) | Medium |
| Issue #54 — NPC Framework + Convenience Clerk (may reuse playtest infrastructure) | Medium |

### Preparation Needed

- [ ] Create `tests/playtest/` directory with 3 checklist files (shallow/middle/deep)
- [ ] Write headless integration test scripts for dialogue parsing + condition evaluation + ending logic
- [ ] Prepare 3 tester instruction sets (neutral / high-hope / low-hope playthrough paths)
- [ ] Verify Godot project opens without errors in GUI mode
- [ ] Verify all autoloads register correctly on launch
- [ ] Run full test suite baseline and save results

---

## 7. Spike / Experiment

> *Per `depth/standard` label — limited to 1 spike focused on the highest-risk unknown.*

### Spike A: Headless Integration Test Coverage Assessment

**Question to answer:** What percentage of the shallow and middle layers can be tested in `--headless --script` mode without a GUI?

**Method:** Attempt to instantiate each scene's script in headless mode and call methods programmatically. Document which checks are feasible and which require GUI. This directly informs the split between CI (deterministic) and agent playtest (GUI) in the recommended approach.

**Expected result:**

| Scene | Headless-Testable | GUI-Only |
|-------|-------------------|----------|
| NarrativeManager.determine_ending | ✅ Full — pure function | — |
| DialogueParser.load_dialogue | ✅ Full — pure utility | — |
| DialogueConditionEvaluator.evaluate | ✅ Full — pure utility | — |
| StateSystem.apply_choice | ✅ Full — pure logic | — |
| WorldviewController._calculate_tone | ✅ Full — pure function | — |
| RainController._on_state_changed | ✅ Full — pure logic | — |
| ClockManager | ✅ Full — pure logic | — |
| OfficeScene._configure_environmental_text | ❌ Needs node tree | ✅ Full |
| BridgeScene._check_intrusive_thought | ❌ Needs NarrativeManager autoload | ✅ Full |
| LobbyScene._get_tone | ❌ Needs StateSystem autoload | ✅ Full |
| DialogueRunner.start (full cycle) | ⚠️ Partial — can test load + enter_node, but signals need scene tree | Signal emission verification |
| Scene transitions | ❌ SceneManager needs actual scene tree | ✅ Full |

**Impact:** Approximately 30–40% of shallow checks and 45–55% of middle checks can be headless-automated. The remaining 50% require GUI playtest. This confirms the Hybrid approach is the correct split.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

### Current State

The game has a complete MVP vertical slice: 6 scenes in fixed sequence (office → lobby → street → convenience_store → bridge → underpass → subway_station), a narrative architecture with 5-state per-scene tone tables, a dialogue engine with condition-based branching and state effects, a tri-axis state system (hope/conviction/will) with bipolar hope_despair axis, an echo system with 6 defined echoes, ending determination with 3 outcomes, and a sound system with ambient audio and footstep effects. 9 dialogue JSON files exist. 80+ unit tests run in `--headless --script` mode.

### What Has NOT Been Done

No end-to-end playtest has been conducted. The existing tests are all unit/component-level — they test individual functions and classes but never the integrated game loop. The acceptance criteria from each issue have never been verified together as a unified whole.

### Test Protocol Summary

**3 testers** (LLM agents using `computer_use`), each executing a prescribed playthrough:

1. **Tester 1 (neutral):** Default state, full 6-scene playthrough, document all observations
2. **Tester 2 (high-hope):** Make choices that maximize hope/conviction/will, reach Keep Walking ending
3. **Tester 3 (low-hope):** Make choices that minimize hope/conviction/will, reach Turn Back ending

Each tester produces a structured YAML report with:
- Shallow checklist (47 items) — all must pass
- Middle checklist (40 items) — ≥60% must pass; failures documented with suggestions
- Deep evaluation (10 Likert + 6 free-text) — ≥2 testers must rate metaphor ≥4/5

### Next Steps

1. Create `tests/playtest/` directory with 3 checklist YAML files
2. Write headless integration test extensions for dialogue parsing, condition evaluation, and ending logic (CI-gated)
3. Execute 3 agent playthroughs using `computer_use`
4. Synthesize reports into a bug inventory and sign-off document
5. Create implement-phase issues for each bug found (high-severity: separate issue; low-severity: batch)

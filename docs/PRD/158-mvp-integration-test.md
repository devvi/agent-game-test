# Research: MVP Integration Test — Full Walkthrough (#158)

> Parent Issue: #158
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project has been built incrementally through 17+ issues, each adding features validated at the unit or component level. The existing test suite consists of **28 test files** covering:

- **12 unit tests** in `tests/unit/` — PlayerController, NPCNode, NPC personality, dialogue runner extension, audio manager, UI config/status bar, input map validation, scene base player, game manager player, E-key trigger
- **5 integration tests** in `tests/integration/` — Player in scene, NPC in scene, audio state modulation, audio scene transition, audio footstep dialogue
- **11 standalone test files** in `tests/` — Dialogue engine (46 tests), dialogue engine v2, narrative architecture, bridge/underpass, game state, game manager playthrough, LoFi text 3D, Hemingway enforcer, text component library, stranger dialogue, stranger scene
- **1 master runner** — `tests/run_tests.gd` orchestrates all tests via `--headless --script` mode

**What is missing:**

1. **End-to-end walkthrough** — No single test validates the complete game flow from game start through all 6 scenes to ending determination
2. **Cross-system integration** — Individual systems pass their own tests but are never validated working together (e.g., dialogue choice → state change → environmental text update)
3. **Scene transition integrity** — State persistence, dialogue history restoration, and scene index advancement are not tested as a unified flow
4. **Full narrative path coverage** — The 6-scene narrative path (office → lobby → street → store → bridge → underpass → subway_station) has no integration test
5. **Ending determination chain** — State accumulated across multiple scenes → NarrativeManager.determine_ending() → correct ending dialogue triggered
6. **Echo system lifecycle** — Echoes triggered in one scene, carried to next, displayed correctly
7. **Audio lifecycle** — Scene registration → ambient profile switching → rain intensity modulation → cross-fade during transitions

### Expected Behavior

A structured, automated integration test suite that:

1. **Validates the full game walkthrough** — Office → Lobby → Street → Store → Bridge → Underpass → Subway Station, with scene transitions and state accumulation
2. **Tests state-dialogue-scene feedback loop** — Dialogue choice modifies state → state change updates environmental text → scene transition preserves state
3. **Verifies all 3 ending paths** — Keep Walking, Turn Back, Stay — each reached through appropriate state accumulation
4. **Covers edge cases** — Min/max state extremes, rapid scene transitions, missing autoloads, dialogue re-entrance
5. **Runs deterministically** — Existing `--headless --script` mode, no GUI dependency for logic-layer tests
6. **Provides clear pass/fail output** — Each test case produces a labeled assertion, total passed/failed reported, non-zero exit on failure

### User Scenarios

- **Scenario A (Full neutral playthrough):** Test walks through all 6 scenes sequentially, triggers all dialogue, verifies default state values. No crashes, no errors.
- **Scenario B (High-hope path):** State is configured with high hope/conviction/will. Environmental text shifts to positive variants. Keep Walking ending.
- **Scenario C (Despair path):** State is configured with low hope/conviction/will. Despair text variants. Turn Back ending.
- **Scenario D (Edge case path):** All state axes at extremes (0 and 10). Min/max state clamping. Rapid dialogue triggers.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project followed standard incremental development: each issue added a feature with its own test suite and acceptance criteria at the component level. The `tests/run_tests.gd` runner accumulated tests linearly, with each new issue appending its test block. Integration across features was deferred because features were being built — not yet assembled into a playable whole.

Now that all MVP scenes, systems, dialogue content, and mechanics are merged:
- All 6 scenes exist with complete scripts and scene trees
- Autoloads are stable (StateSystem, GameManager, NarrativeManager, AudioManager, GameState, UIConfig)
- 9 dialogue JSON files are present
- NPC framework is operational
- PlayerController is integrated into SceneBase

### Why Change Now?

Without an end-to-end integration test, the team cannot confirm that the "whole" works. A broken integration (e.g., scene transition not preserving dialogue state, ending determination reading wrong axis, audio cross-fade during transition crashing) would make the full game non-functional despite all 80+ individual tests passing.

### Previous Constraints

| Constraint | Detail |
|---|---|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| Test framework | GDScript `SceneTree` mode via `tests/run_tests.gd` |
| Headless testing | `godot --headless --script tests/run_tests.gd` — no GUI, pure logic |
| Autoloads | GameManager, StateSystem, NarrativeManager, AudioManager, GameState (deprecated), UIConfig |
| State axes | hope_despair (-10–+10), hope (0–10), conviction (0–10), will (0–10) |
| Dialogue condition evaluator | Supports: slider (gte/lte/eq/gt/lt), flag, choice_made, and/or/not compound |
| Hemingway constraint | Max 3 sentences, max 25 chars per sentence |
| Scene sequence | office(0) → lobby(1) → store(2) → bridge(3) → underpass(4) → subway_station(5) |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|---|---|---|
| `tests/run_tests.gd` | Test runner | Add integration test import and execution block |
| `tests/test_mvp_integration.gd` | **NEW** — MVP integration test suite | Full walkthrough test with 20+ test cases |
| `tests/test_mvp_integration_walkthrough.gd` | **NEW** — Walkthrough scenarios | Scene sequence, state paths, ending verification |
| `gdscripts/narrative_manager.gd` | NarrativeManager | No changes; tested for scene sequence, advance_scene(), determine_ending() |
| `gdscripts/scene_base.gd` | SceneBase | No changes; tested for player instantiation, dialogue state restoration |
| `gdscripts/state_system.gd` | StateSystem | No changes; tested for apply_choice(), get_state(), get_state_id(), clamp, resistance |
| `gdscripts/game_manager.gd` | GameManager | No changes; tested for slider delegation, flag storage, choice persistence |
| `gdscripts/dialogue_runner.gd` | DialogueRunner | No changes; tested for start/choice/end cycle, state provider |
| `gdscripts/npc_node.gd` | NPCNode | No changes; tested for state transitions, personality layers |
| `gdscripts/player_controller.gd` | PlayerController | No changes; tested for instantiation, movement, dialogue blocking |
| `gdscripts/audio_manager.gd` | AudioManager | No changes; tested for scene registration, bus profile switching, rain modulation |
| `gdscripts/rain_controller.gd` | RainController | No changes; tested for rain intensity → conviction mapping |
| `gdscripts/underpass.gd` | UnderpassScene | No changes; tested for echo system, AC3 hidden text |
| `gdscripts/subway_station.gd` | SubwayStationScene | No changes; tested for ending trigger zones |
| `dialogues/*.json` (9 files) | Dialogue data | No changes; parsed and validated via dialogue parser |

### Documents to Create

| Document | Purpose |
|---|---|
| `docs/PRD/158-mvp-integration-test.md` | This document |
| `tests/test_mvp_integration.gd` | Full walkthrough integration test suite |
| `tests/test_mvp_integration_walkthrough.gd` | Walkthrough scenario definitions (optional split) |

### Documents to Update

| Document | Change |
|---|---|
| `tests/run_tests.gd` | Add import and execution of the new integration test suite |

---

## 4. Solution Comparison

### Approach A: Dedicated GDScript Integration Test Suite (Recommended)

**Description:** Create a new `tests/test_mvp_integration.gd` file (and optionally `tests/test_mvp_integration_walkthrough.gd`) following the existing `RefCounted` pattern with `run()`, `_assert()`, `passed`/`failed` tracking. Add it to `tests/run_tests.gd` under a new integration block.

Test cases cover:
1. **Walkthrough sequence** — Mock/narrative-level flow through all 6 scenes: verify NarrativeManager.SCENE_ORDER, verify each scene_id maps to a valid path
2. **Ending determination** — 3 ending paths: Keep Walking (hope≥6, will≥5), Turn Back (conviction≤3), Stay (fallthrough)
3. **State system integration** — apply_choice → get_state → state_id change detection → resistance multiplier
4. **Dialogue manager integration** — GameManager.get_slider(), set_flag/has_flag delegation to StateSystem
5. **Audio state modulation** — StateSystem state → AudioManager rain_intensity + volume calculation
6. **Narrative scene advancement** — NarrativeManager.advance_scene() → current_scene_index increment → GameManager.current_scene_id update
7. **Echo system** — Echo trigger suppression, _calculate_echo_variant 5-state mapping
8. **NPC framework** — Personality layer evaluation, state transition cycle (IDLE→TALKING→COOLDOWN→IDLE)
9. **Player controller** — Interaction detection, dialogue blocking, WASD movement
10. **Scene transitions** — Fade curtain dynamic creation, transition_in_progress gating

**Pros:**
- Fully deterministic, runs in CI via `--headless --script`
- Reuses existing test patterns (RefCounted, passed/failed, _assert)
- Fast execution (~seconds)
- Covers all logic-layer integration points
- Easy to extend with new scenarios

**Cons:**
- Cannot test 3D rendering (text positions, colors, visibility in scene)
- Cannot test visual timing (fade animations, typewriter effects)
- Cannot test actual scene loading via `change_scene_to_file()` in headless mode
- Mock-heavy — must instantiate components without the full scene tree

**Risk:** Low — 70%+ of integration points are pure logic; the remaining 30% (visual rendering) is covered by GUI-based playtesting per Issue #57

**Effort:** 2–3 days

### Approach B: Extend Existing Unit Tests Only

**Description:** Instead of a dedicated integration suite, add cross-module assertions to existing `tests/unit/` test files. For example, add GameManager↔StateSystem delegation tests to `test_game_manager_player.gd`.

**Pros:**
- No new files
- Incremental — fits existing workflow

**Cons:**
- Scattered — no single cohesive walkthrough
- Harder to reason about cross-system interactions
- Misses the "whole game" perspective entirely
- Existing test files would grow unwieldy

**Risk:** High — would miss the walkthrough-level bugs this issue is about

**Effort:** 1–2 days (but lower coverage)

### Approach C: Python-Driven Integration Tests

**Description:** Write Python scripts that drive Godot headless via command-line, parse stdout/stderr, and verify integration behavior. Use the existing `tests/test_validator_parity.py` pattern.

**Pros:**
- Python is more flexible for complex assertions
- Can orchestrate multiple Godot invocations

**Cons:**
- Adds a second test framework (Python + GDScript)
- Brittle — depends on stdout parsing
- Cannot easily mock Godot-internal state from Python
- Duplicates existing GDScript test patterns

**Risk:** Medium — stdout parsing is fragile; silent failures possible

**Effort:** 3–4 days

### Recommendation

→ **Approach A (Dedicated GDScript Integration Test Suite)** because:

1. **Reuses proven patterns** — RefCounted + run() + _assert() is established across 28 existing test files
2. **Runs in CI** — `godot --headless --script tests/run_tests.gd` already gates merges
3. **Deterministic** — No timing/flaky dependence
4. **Comprehensive** — Covers all logic-layer integration points across all systems
5. **Extensible** — New scenarios (additional state paths, edge cases) are easy to add
6. **CI-friendly** — Non-zero exit on failure integrates with GitHub Actions

---

## 5. Boundary Conditions & Acceptance Criteria

### Acceptance Criteria

**AC1 (100% Must Pass):** All headless integration tests pass with exit code 0.
| ID | Criterion | How to Verify |
|----|-----------|---------------|
| AC1-1 | `godot --headless --script tests/run_tests.gd` exits 0 | Run the headless test runner |
| AC1-2 | New integration tests appear in output with "=== MVP Integration Test ===" header | Console output contains the header |
| AC1-3 | No test produces GDScript parse errors | stderr is empty |
| AC1-4 | All existing tests still pass (no regression) | Existing 80+ tests all report "✅" |

**AC2 (≥90% Must Pass):** Integration-specific test coverage.
| ID | Criterion | Threshold |
|----|-----------|-----------|
| AC2-1 | Scene sequence test validates all 6 scenes | 6/6 verified |
| AC2-2 | Ending determination test covers all 3 endings | 3/3 verified |
| AC2-3 | State system integration tests (apply + clamp + resistance + signal) | 5/5 sub-tests pass |
| AC2-4 | Dialogue-game manager delegation tests | 4/4 sub-tests pass |
| AC2-5 | Audio state modulation integration tests | 3/3 sub-tests pass |
| AC2-6 | Echo system tests (suppression, variant calculation) | 2/2 sub-tests pass |
| AC2-7 | NPC framework integration tests | 3/3 sub-tests pass |
| AC2-8 | Player controller integration tests | 4/4 sub-tests pass |
| AC2-9 | Scene transition logic tests | 2/2 sub-tests pass |

**AC3 (Quality bar):** Test structure quality.
| ID | Criterion | Threshold |
|----|-----------|-----------|
| AC3-1 | Each test case has a unique ID (TC-INT-XX) | All cases labeled |
| AC3-2 | Tests are organized by system (State, Dialogue, Audio, NPC, Player, Scene, Echo) | Section headers |
| AC3-3 | At least 20 total test cases across all sections | ≥20 cases |
| AC3-4 | At least 3 edge case tests (min/max state, rapid input, empty state) | ≥3 edge cases |
| AC3-5 | At least 2 failure path tests (missing autoload, invalid state) | ≥2 failure paths |

### Complete Test Case Specifications

#### Test Data Collection Format

Each test produces a formatted assertion line:
```
  ✅ TC-INT-NN: Description
  ❌ TC-INT-NN: Description (actual value vs expected)
```

Tests are organized under section headers:
```
  === MVP Integration Test ===
  --- State System Integration ---
  --- Dialogue-Game Manager Integration ---
  --- Audio State Modulation ---
  --- Narrative & Scene Sequence ---
  --- Echo System ---
  --- NPC Framework ---
  --- Player Controller ---
  --- Scene Transition Logic ---
  --- Edge Cases & Failure Paths ---
```

#### Section 1: State System Integration (TC-INT-01 to TC-INT-06)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-01 | Normal | Create StateSystem instance | apply_choice({"hope_despair": 3.0}) | hope_despair=3.0, hope=(3.0+10)/2=6.5, despair=3.5 |
| TC-INT-02 | Normal | Create StateSystem instance | apply_choice({"hope": 2.0, "conviction": -1.0, "will": 0.5}) | hope_despair=4.0, hope=7.0, conviction=4.0, will=5.5 |
| TC-INT-03 | Edge | Create StateSystem instance | apply_choice({"hope_despair": 100.0}) | hope_despair clamped to 10.0 |
| TC-INT-04 | Edge | Create StateSystem instance | apply_choice({"conviction": -100.0}) | conviction clamped to 0.0 |
| TC-INT-05 | Normal | Create StateSystem instance | apply_choice({"hope_despair": -10.0}), get_state_id() | state_id=1 (Despair) |
| TC-INT-06 | Normal | Create StateSystem instance with signal | Connect state_changed, apply_choice({"hope": 1.0}) | Signal fires with correct hope=6.0 |

#### Section 2: Dialogue-Game Manager Integration (TC-INT-07 to TC-INT-10)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-07 | Normal | Create GameManager; mock StateSystem with get_slider("hope") = 7.0 | get_slider("hope") | Returns 7.0 |
| TC-INT-08 | Normal | Create GameManager; no autoload StateSystem | get_slider("unknown_axis") | Returns 5.0 fallback |
| TC-INT-09 | Normal | Create GameManager with StateSystem mock | set_flag("test_flag", true), has_flag("test_flag") | Returns true |
| TC-INT-10 | Edge | Create GameManager with StateSystem mock | has_flag("nonexistent") | Returns false |

#### Section 3: Audio State Modulation (TC-INT-11 to TC-INT-13)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-11 | Normal | Create AudioManager, set distance_factor=1.0 | _on_state_changed({"conviction": 10.0, "despair": 0.0}) | rain_intensity ≈ 0.0 |
| TC-INT-12 | Normal | Create AudioManager, set distance_factor=1.0 | _on_state_changed({"conviction": 0.0, "despair": 10.0}) | rain_intensity ≈ 1.0 |
| TC-INT-13 | Edge | Create AudioManager, set distance_factor=1.0 | _on_state_changed({"conviction": 0.0, "despair": 10.0}), _calc_rain_volume() | Volume ≤ 0 dB (no clipping) |

#### Section 4: Narrative & Scene Sequence (TC-INT-14 to TC-INT-18)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-14 | Normal | Access NarrativeManager.SCENE_ORDER | Verify array | ["office", "lobby", "convenience_store", "bridge", "underpass", "subway_station"] |
| TC-INT-15 | Normal | Create NarrativeManager | advance_scene() from index 0 | Returns "lobby", current_scene_index=1 |
| TC-INT-16 | Normal | Create NarrativeManager, advance to index 5 | advance_scene() at last scene | Returns "" (no more scenes) |
| TC-INT-17 | Normal | Create NarrativeManager with state {"hope": 7.0, "conviction": 5.0, "will": 6.0} | determine_ending(state) | Returns "keep_walking" |
| TC-INT-18 | Normal | Create NarrativeManager with state {"hope": 4.0, "conviction": 2.0, "will": 3.0} | determine_ending(state) | Returns "turn_back" (conviction ≤ 3 takes priority) |

#### Section 5: Echo System (TC-INT-19 to TC-INT-20)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-19 | Normal | Create NarrativeManager with echo_flags empty | trigger_echo("screensaver_echo") twice | Second call suppressed; echo_flags["screensaver_echo"]=true |
| TC-INT-20 | Normal | Create NarrativeManager with hope=9.0 | _calculate_echo_variant("rain_echo") | Variant=0 (state 5 → inverse 0) |

#### Section 6: NPC Framework (TC-INT-21 to TC-INT-23)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-21 | Normal | Create NPCNode with basic exports | Verify all export values | dialogue_file, dialogue_id, speaker_name, proximity_distance all match set values |
| TC-INT-22 | Normal | Create NPCNode, set state to TALKING | set_state(1) | current_state = 1 |
| TC-INT-23 | Normal | Create NPCNode with 3 personality layers | verify layer structure | 3 layers, first has condition, last is "always" fallback |

#### Section 7: Player Controller Integration (TC-INT-24 to TC-INT-27)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-24 | Normal | Create PlayerController instance | Verify @onready node references | head, camera, interaction_area all non-null |
| TC-INT-25 | Normal | Create PlayerController with head/camera/area | Verify camera is current | camera.current = true |
| TC-INT-26 | Normal | Create PlayerController in dialog mode | _dialogue_active = true, set velocity | Velocity brakes toward zero in _physics_process equivalent |
| TC-INT-27 | Normal | Create PlayerController | _on_dialogue_ended() | _dialogue_active = false |

#### Section 8: Scene Transition Logic (TC-INT-28 to TC-INT-29)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-28 | Normal | Create SceneManager with mock scene tree | _setup_fade_curtain() | FadeCurtain node created with ColorRect, AnimationPlayer |
| TC-INT-29 | Edge | Create SceneManager, set transition_in_progress=true | trigger_scene_change("res://fake.tscn") | Returns early, no transition |

#### Section 9: Walkthrough Sequence (TC-INT-30 to TC-INT-35)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-30 | Normal | Create NarrativeManager and GameManager | Loop: advance_scene() for each, verify GameManager.current_scene_id | 6 scenes visited, current_scene_id matches each |
| TC-INT-31 | Normal | Create SceneBase with mock StateSystem (hope=2.0) | get_state_tier("hope") | Returns "low" |
| TC-INT-32 | Normal | Create SceneBase with mock StateSystem (hope=8.0) | get_state_tier("hope") | Returns "high" |
| TC-INT-33 | Edge | Create SceneBase with no StateSystem autoload | get_state_tier("hope") | Returns "mid" (fallback) |
| TC-INT-34 | Failure | Create SceneBase with no SpawnPoint marker | _get_player_spawn_position() | Returns Vector3.ZERO |
| TC-INT-35 | Normal | Create UnderpassScene with StateSystem (hope=1.5, conviction=1.5) | _check_hidden_text(), read echo_text.text | Text contains "影子" (AC3 hidden text revealed) |

#### Section 10: Full Ending Determination Spectrum (TC-INT-36 to TC-INT-38)

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-36 | Normal | NarrativeManager.determine_ending({"hope":6.0,"conviction":7.0,"will":5.0}) | Call determine_ending | "keep_walking" |
| TC-INT-37 | Normal | NarrativeManager.determine_ending({"hope":3.0,"conviction":2.0,"will":3.0}) | Call determine_ending | "turn_back" (conviction=2 ≤ 3) |
| TC-INT-38 | Normal | NarrativeManager.determine_ending({"hope":5.0,"conviction":5.0,"will":5.0}) | Call determine_ending | "stay" (fallthrough — no condition met) |

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|---|---|---|
| All 6 scene scripts (office.gd, lobby.gd, street.gd, store.gd, bridge.gd, underpass.gd, subway_station.gd) | ✅ Merged | Low |
| StateSystem (state_system.gd) — tri-axis + bipolar slider | ✅ Merged | Low |
| GameManager (game_manager.gd) — flag/slider/choice delegation | ✅ Merged | Low |
| NarrativeManager (narrative_manager.gd) — scene order, ending, echoes | ✅ Merged | Low |
| AudioManager (audio_manager.gd) — scene registration, rain modulation | ✅ Merged | Low |
| DialogueRunner (dialogue_runner.gd) — start/choice/end/anti-loop | ✅ Merged | Low |
| NPCNode (npc_node.gd) — state machine, personality layers | ✅ Merged | Low |
| PlayerController (player_controller.gd) — WASD, mouse, interaction | ✅ Merged | Low |
| SceneBase (scene_base.gd) — player instantiation, dialogue restore | ✅ Merged | Low |
| SceneManager (scene_manager.gd) — fade curtain, scene transitions | ✅ Merged | Low |
| All 9 dialogue JSON files | ✅ Merged | Low |
| Godot 4.7.1 headless mode | ✅ Working | Low |
| Existing test runner (tests/run_tests.gd) | ✅ Working | Low |

### Blocks

| Future Work | Priority |
|---|---|
| Implement-phase test file creation (`tests/test_mvp_integration.gd`) | High |
| Implement-phase update to `tests/run_tests.gd` | High |
| All bug fixes discovered during integration test failures | Medium |

---

## 7. Test Implementation Plan

### File Structure

```
tests/
├── run_tests.gd                     # ADD: load and run MVP integration tests
└── test_mvp_integration.gd          # NEW: 35+ test cases across 10 sections
```

### Execution Order in run_tests.gd

The new integration block should be appended after existing Integration Tests:

```gdscript
# --- MVP Integration Tests (Issue #158) ---
var _mvp_integration = load("res://tests/test_mvp_integration.gd")
if _mvp_integration != null:
    var _mvp = _mvp_integration.new()
    _mvp.run()
    passed += _mvp.passed
    failed += _mvp.failed
else:
    print("  ⚠️ MVP integration test not found (Issue #158)")
```

### Test File Skeleton

The `test_mvp_integration.gd` follows the established RefCounted pattern:

```gdscript
extends RefCounted

var passed: int = 0
var failed: int = 0

func run() -> void:
    print("\n=== MVP Integration Test (Issue #158) ===")
    
    print("  --- State System Integration ---")
    # TC-INT-01 to TC-INT-06
    
    print("  --- Dialogue-Game Manager Integration ---")
    # TC-INT-07 to TC-INT-10
    
    print("  --- Audio State Modulation ---")
    # TC-INT-11 to TC-INT-13
    
    print("  --- Narrative & Scene Sequence ---")
    # TC-INT-14 to TC-INT-18
    
    print("  --- Echo System ---")
    # TC-INT-19 to TC-INT-20
    
    print("  --- NPC Framework ---")
    # TC-INT-21 to TC-INT-23
    
    print("  --- Player Controller ---")
    # TC-INT-24 to TC-INT-27
    
    print("  --- Scene Transition Logic ---")
    # TC-INT-28 to TC-INT-29
    
    print("  --- Walkthrough & Edge Cases ---")
    # TC-INT-30 to TC-INT-35
    
    print("  --- Ending Determination ---")
    # TC-INT-36 to TC-INT-38
    
    print("\n  MVP Integration: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("    ✅ %s" % label)
    else:
        failed += 1
        print("    ❌ %s" % label)
```

### Normal Path

1. Create `tests/test_mvp_integration.gd` with all 38 test cases across 10 sections
2. Update `tests/run_tests.gd` to load and execute the new test
3. Run `godot --headless --script tests/run_tests.gd` to verify all tests pass
4. Confirm no regression in existing tests (80+ existing tests still pass)

### Edge Cases

1. **Min/max state extremes** — All axes at 0 and 10 — clamping/resistance must hold
2. **Empty state dictionary** — apply_choice({}) should be no-op
3. **Rapid state changes** — Multiple apply_choice calls in sequence — correct final state
4. **Missing autoload** — SceneBase.get_state_tier() fallback when StateSystem not available
5. **Transition gating** — scene_manager.transition_in_progress prevents double transitions

### Failure Paths

1. **StateSystem not available** — GameManager.get_slider() returns 5.0 fallback
2. **Invalid axis name** — GameManager.apply_slider_delta("nonexistent", 5.0) — warning but no crash
3. **Echo re-trigger suppression** — Calling trigger_echo twice — second call silently suppressed
4. **Scene at end of sequence** — NarrativeManager.advance_scene() at index 5 returns ""
5. **Missing SpawnPoint** — SceneBase._get_player_spawn_position() returns Vector3.ZERO

---

## 8. Verification Protocol

### Primary Verification

```bash
cd /Users/devvi/workspace/agent-game-test
godot --headless --script tests/run_tests.gd
```

Expected output contains:
```
=== MVP Integration Test (Issue #158) ===
  --- State System Integration ---
    ✅ TC-INT-01: ...
  ... (all 38 test cases) ...
  MVP Integration: 38 passed, 0 failed

=== Results ===
Passed: ...
Failed: 0
✅ All tests passed!
```

### Secondary Verification

After the test is merged, run the full suite to confirm no regression:

```bash
godot --headless --script tests/run_tests.gd
echo "Exit code: $?"
# Must be 0
```

### Failure Indicators

- Any `❌` in output indicates a specific test case failure
- Non-zero exit code from `godot --headless` runner
- GDScript parse errors on stderr
- Integration test header not printed (file not found or load error)

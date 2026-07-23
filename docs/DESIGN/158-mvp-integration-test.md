# Design: #158 — MVP Integration Test — Full Walkthrough

> Parent Issue: #158
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Create a dedicated GDScript integration test suite (`tests/test_mvp_integration.gd`) that validates the full MVP game walkthrough in headless mode. The test exercises every logic-layer integration point across all 7 major systems without requiring the 3D rendering pipeline or GUI interaction. It runs via the existing `godot --headless --script tests/run_tests.gd` CI gate.

### Systems Under Test

```
┌────────────────────────────────────────────────────────────────────┐
│                    MVP Integration Test (38 cases)                  │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │  State System     │   │  Dialogue-GM      │   │  Audio State   │  │
│  │  (TC-INT-01→06)   │◄─►│  (TC-INT-07→10)   │◄─►│  (TC-INT-11→13) │  │
│  └──────┬───────────┘   └────────┬─────────┘   └───────┬────────┘  │
│         │                        │                       │          │
│  ┌──────▼────────────────────────▼───────────────────────▼──────┐  │
│  │                    Walkthrough Orchestrator                    │  │
│  │             (TC-INT-30→35 — scene sequence loop)              │  │
│  └──────┬────────────────────────┬───────────────────────┬──────┘  │
│         │                        │                       │          │
│  ┌──────▼───────────┐   ┌───────▼──────────┐   ┌───────▼────────┐  │
│  │  Narrative &      │   │  Echo System     │   │  NPC Framework  │  │
│  │  Scene Sequence   │   │  (TC-INT-19→20)  │   │  (TC-INT-21→23) │  │
│  │  (TC-INT-14→18)   │   └──────────────────┘   └────────────────┘  │
│  └──────────────────┘                                                │
│                                                                     │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │  Player Control   │   │  Scene Transi-   │   │  Ending Det.   │  │
│  │  (TC-INT-24→27)   │   │  tion (TC-INT-   │   │  (TC-INT-36→38)│  │
│  └──────────────────┘   └──────────────────┘   └────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Edge Cases & Failure Paths (TC-INT-03-04, 33-35, embedded) │   │
│  └──────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

### Data Flow — Walkthrough Sequence

```gdscript
# Conceptual flow of a full playthrough (TC-INT-30)
var nm = NarrativeManager.new()
var gm = GameManager.new()

for scene_id in SCENE_ORDER:
    gm.current_scene_id = scene_id
    gm.mark_scene_visited(scene_id)
    _assert(gm.is_scene_visited(scene_id))

    # Dialogue choices accumulate state
    ss.apply_choice({"hope": 1.0, "conviction": 0.5})
    
    # Determine ending at end
    if scene_id == "subway_station":
        var ending = nm.determine_ending(ss.get_state())
        _assert(ending in ["keep_walking", "turn_back", "stay"])
```

### Test Pattern

All tests follow the established `RefCounted` pattern used by 28 existing test files:

```gdscript
extends RefCounted

var passed: int = 0
var failed: int = 0

func run() -> void:
    print("\n=== MVP Integration Test (Issue #158) ===")
    _test_state_system()
    _test_dialogue_gm()
    _test_audio_modulation()
    _test_narrative_scene()
    _test_echo_system()
    _test_npc_framework()
    _test_player_controller()
    _test_scene_transition()
    _test_walkthrough()
    _test_endings()
    print("\n  MVP Integration: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("    ✅ %s" % label)
    else:
        failed += 1
        print("    ❌ %s" % label)
```

---

## 2. System-by-System Test Specification

### 2.1 State System Integration (TC-INT-01 to TC-INT-06)

Tests the core state mechanics: bipolar slider, derived values, clamping, resistance, state ID transitions, and signal emission.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-01 | Normal | Create StateSystem instance | `apply_choice({"hope_despair": 3.0})` | hope_despair=3.0, hope=(3.0+10)/2=6.5, despair=3.5 |
| TC-INT-02 | Normal | Create StateSystem instance | `apply_choice({"hope": 2.0, "conviction": -1.0, "will": 0.5})` | hope_despair=4.0, hope=7.0, conviction=4.0, will=5.5 |
| TC-INT-03 | Edge | Create StateSystem instance | `apply_choice({"hope_despair": 100.0})` | hope_despair clamped to 10.0 |
| TC-INT-04 | Edge | Create StateSystem instance | `apply_choice({"conviction": -100.0})` | conviction clamped to 0.0 |
| TC-INT-05 | Normal | Create StateSystem instance | `apply_choice({"hope_despair": -10.0})`, `get_state_id()` | state_id=1 (Despair) |
| TC-INT-06 | Normal | Create StateSystem with signal watcher | Connect state_changed, `apply_choice({"hope": 1.0})` | Signal fires with hope=6.0 |

**Resistance edge cases (embedded):**
- State 1 (Despair) + positive delta → 0.5× multiplier
- State 5 (Hope) + negative delta → 0.5× multiplier
- Empty effect dict `apply_choice({})` → no-op

### 2.2 Dialogue-Game Manager Integration (TC-INT-07 to TC-INT-10)

Tests the delegation chain from GameManager to StateSystem for slider values, flags, and choice persistence.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-07 | Normal | GameManager with StateSystem mock having get_slider("hope")=7.0 | `get_slider("hope")` | Returns 7.0 |
| TC-INT-08 | Normal | GameManager with no StateSystem | `get_slider("unknown_axis")` | Returns 5.0 fallback |
| TC-INT-09 | Normal | GameManager with StateSystem mock | `set_flag("test_flag", true)`, `has_flag("test_flag")` | Returns true |
| TC-INT-10 | Edge | GameManager with StateSystem mock | `has_flag("nonexistent")` | Returns false |

### 2.3 Audio State Modulation (TC-INT-11 to TC-INT-13)

Tests AudioManager's integration with StateSystem: rain intensity, volume clamping, and distortion.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-11 | Normal | Create AudioManager, set distance_factor=1.0 | `_on_state_changed({"conviction": 10.0, "despair": 0.0})` | rain_intensity ≈ 0.0 |
| TC-INT-12 | Normal | Create AudioManager, set distance_factor=1.0 | `_on_state_changed({"conviction": 0.0, "despair": 10.0})` | rain_intensity ≈ 1.0 |
| TC-INT-13 | Edge | Create AudioManager, set distance_factor=1.0 | `_on_state_changed({"conviction": 0.0, "despair": 10.0})`, check `_calc_rain_volume()` | Volume ≤ 0 dB (no clipping) |

### 2.4 Narrative & Scene Sequence (TC-INT-14 to TC-INT-18)

Tests NarrativeManager's scene order, advancement, ending determination logic, and edge-of-sequence handling.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-14 | Normal | Access NarrativeManager.SCENE_ORDER | Verify array | 6 scenes in order: office, lobby, convenience_store, bridge, underpass, subway_station |
| TC-INT-15 | Normal | Create NarrativeManager | `advance_scene()` from index 0 | Returns "lobby", current_scene_index=1 |
| TC-INT-16 | Normal | Create NarrativeManager, advance to index 5 | `advance_scene()` at last scene | Returns "" (no more scenes) |
| TC-INT-17 | Normal | NarrativeManager with state {hope:7.0, conviction:5.0, will:6.0} | `determine_ending(state)` | Returns "keep_walking" |
| TC-INT-18 | Normal | NarrativeManager with state {hope:4.0, conviction:2.0, will:3.0} | `determine_ending(state)` | Returns "turn_back" (conviction ≤ 3 takes priority) |

### 2.5 Echo System (TC-INT-19 to TC-INT-20)

Tests echo trigger suppression (one-shot) and variant calculation based on state.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-19 | Normal | NarrativeManager with echo_flags empty | `trigger_echo("screensaver_echo")` twice | Second call suppressed; echo_flags["screensaver_echo"]=true |
| TC-INT-20 | Normal | NarrativeManager with hope=9.0, conviction=5.0 (state 5) | `_calculate_echo_variant("rain_echo")` | Variant=0 (state 5 → inverse 0) |

### 2.6 NPC Framework (TC-INT-21 to TC-INT-23)

Tests NPCNode state machine, personality layer evaluation, and export defaults.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-21 | Normal | Create NPCNode with basic exports | Verify all export values | dialogue_file, dialogue_id, speaker_name, proximity_distance all match set values |
| TC-INT-22 | Normal | Create NPCNode | `set_state(1)` (TALKING) | current_state = 1 (NPCState.TALKING) |
| TC-INT-23 | Normal | Create NPCNode with 3 personality layers | Verify layer structure | 3 layers, first has condition, last is "always" fallback |

### 2.7 Player Controller Integration (TC-INT-24 to TC-INT-27)

Tests PlayerController instantiation, node tree construction, camera ownership, and dialogue mode blocking.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-24 | Normal | Create PlayerController instance via `new()` | Check `_build_node_tree()` results | head, camera, interaction_area all non-null |
| TC-INT-25 | Normal | Create PlayerController | Verify camera is current after `_ready()` | camera.current = true |
| TC-INT-26 | Normal | Create PlayerController | Set `_dialogue_active = true`, set velocity to non-zero | In `_physics_process(delta)`, velocity brakes toward zero |
| TC-INT-27 | Normal | Create PlayerController | Call `_on_dialogue_ended()` | `_dialogue_active = false` |

### 2.8 Scene Transition Logic (TC-INT-28 to TC-INT-29)

Tests SceneManager's fade curtain creation and transition gating.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-28 | Normal | Create SceneManager | Verify `_create_fade_curtain()` | Returns CanvasLayer with ColorRect, AnimationPlayer |
| TC-INT-29 | Edge | Create SceneManager, set transition_in_progress=true | `trigger_scene_change("res://fake.tscn")` | Returns early, no transition |

### 2.9 Walkthrough Sequence (TC-INT-30 to TC-INT-35)

Tests the narrative-level playthrough: scene iteration, state tier evaluation, and missing-node fallbacks.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-30 | Normal | Create NarrativeManager and GameManager | Loop: advance_scene() for each, verify GameManager.current_scene_id | 6 scenes visited, current_scene_id matches each |
| TC-INT-31 | Normal | Create SceneBase (headless) with mock StateSystem (hope=2.0) | `get_state_tier("hope")` | Returns "low" |
| TC-INT-32 | Normal | Create SceneBase with mock StateSystem (hope=8.0) | `get_state_tier("hope")` | Returns "high" |
| TC-INT-33 | Edge | Create SceneBase with no StateSystem autoload | `get_state_tier("hope")` | Returns "mid" (fallback) |
| TC-INT-34 | Failure | Create SceneBase with no SpawnPoint marker | `_get_player_spawn_position()` | Returns Vector3.ZERO |
| TC-INT-35 | Normal | Create UnderpassScene logic with hope=1.5, conviction=1.5 | Simulate `_check_hidden_text()` | Hidden text reveals AC3 content |

### 2.10 Ending Determination Spectrum (TC-INT-36 to TC-INT-38)

Tests all 3 ending paths with representative state values.

| ID | Type | Setup | Steps | Expected |
|----|------|-------|-------|----------|
| TC-INT-36 | Normal | NarrativeManager.determine_ending({hope:6.0, conviction:7.0, will:5.0}) | Call determine_ending | "keep_walking" |
| TC-INT-37 | Normal | NarrativeManager.determine_ending({hope:3.0, conviction:2.0, will:3.0}) | Call determine_ending | "turn_back" (conviction=2 ≤ 3) |
| TC-INT-38 | Normal | NarrativeManager.determine_ending({hope:5.0, conviction:5.0, will:5.0}) | Call determine_ending | "stay" (fallthrough — no condition met) |

---

## 3. Implementation Plan

### File Changes

| File | Action | Description |
|------|--------|-------------|
| `tests/test_mvp_integration.gd` | **CREATE** | 38 test cases across 10 sections, RefCounted pattern |
| `tests/run_tests.gd` | **MODIFY** | Add MVP integration test block before final result print |

### Execution Order in run_tests.gd

Append after the existing integration tests block (around line 60), before the existing unit test blocks:

```gdscript
# --- MVP Integration Tests (Issue #158) ---
var _mvp_script = load("res://tests/test_mvp_integration.gd")
if _mvp_script != null:
    var _mvp = _mvp_script.new()
    _mvp.run()
    passed += _mvp.passed
    failed += _mvp.failed
else:
    print("  ⚠️ MVP integration test not found (res://tests/test_mvp_integration.gd)")
```

### Test File Structure

```
tests/test_mvp_integration.gd
├── extends RefCounted
├── var passed: int / var failed: int
├── func run() -> void
│   ├── print "=== MVP Integration Test ==="
│   ├── Section headers per system
│   └── Calls _test_*() methods
├── func _assert(condition, label) -> void
├── _test_state_system()        # TC-INT-01→06
├── _test_dialogue_gm()         # TC-INT-07→10
├── _test_audio_modulation()    # TC-INT-11→13
├── _test_narrative_scene()     # TC-INT-14→18
├── _test_echo_system()         # TC-INT-19→20
├── _test_npc_framework()       # TC-INT-21→23
├── _test_player_controller()   # TC-INT-24→27
├── _test_scene_transition()    # TC-INT-28→29
├── _test_walkthrough()         # TC-INT-30→35
└── _test_endings()             # TC-INT-36→38
```

### Key Implementation Details

**StateSystem instantiation for headless tests:**
```gdscript
func _test_state_system() -> void:
    var ss = load("res://gdscripts/state_system.gd").new()
    ss.apply_choice({"hope_despair": 3.0})
    _assert(abs(ss.hope_despair - 3.0) < 0.001, "TC-INT-01: apply_choice sets hope_despair")
    _assert(abs(ss.hope - 6.5) < 0.001, "TC-INT-01: hope derived correctly")
    _assert(abs(ss.despair - 3.5) < 0.001, "TC-INT-01: despair derived correctly")
```

**NarrativeManager without autoload (manual injection):**
```gdscript
func _test_narrative_scene() -> void:
    var nm = load("res://gdscripts/narrative_manager.gd").new()
    # No autoload means _state_system is null, but advance_scene() doesn't need it
    _assert(nm.SCENE_ORDER.size() == 6, "TC-INT-14: SCENE_ORDER has 6 scenes")
    _assert(nm.SCENE_ORDER[0] == "office", "TC-INT-14: first scene is office")
    
    var next = nm.advance_scene()
    _assert(next == "lobby", "TC-INT-15: advance_scene returns lobby")
    _assert(nm.current_scene_index == 1, "TC-INT-15: current_scene_index is 1")
```

**Edge case: transition gating:**
```gdscript
func _test_scene_transition() -> void:
    var sm = load("res://gdscripts/scene_manager.gd").new()
    sm.transition_in_progress = true
    sm.trigger_scene_change("res://fake.tscn")
    _assert(sm.transition_in_progress == true, "TC-INT-29: transition still in progress")
```

---

## 4. Acceptance Criteria

### AC1 — 100% Must Pass

| ID | Criterion | How to Verify |
|----|-----------|---------------|
| AC1-1 | `godot --headless --script tests/run_tests.gd` exits 0 | Run the headless test runner |
| AC1-2 | New integration tests appear with "=== MVP Integration Test ===" header | Console output contains the header |
| AC1-3 | No GDScript parse errors | stderr is empty |
| AC1-4 | All existing tests still pass (no regression) | Existing 80+ tests all report "✅" |

### AC2 — ≥90% Must Pass

| ID | Criterion | Threshold |
|----|-----------|-----------|
| AC2-1 | Scene sequence test validates all 6 scenes | 6/6 verified |
| AC2-2 | Ending determination covers all 3 endings | 3/3 verified |
| AC2-3 | State system integration tests (apply + clamp + resistance + signal) | 5/5 sub-tests pass |
| AC2-4 | Dialogue-game manager delegation tests | 4/4 sub-tests pass |
| AC2-5 | Audio state modulation integration tests | 3/3 sub-tests pass |
| AC2-6 | Echo system tests (suppression, variant calculation) | 2/2 sub-tests pass |
| AC2-7 | NPC framework integration tests | 3/3 sub-tests pass |
| AC2-8 | Player controller integration tests | 4/4 sub-tests pass |
| AC2-9 | Scene transition logic tests | 2/2 sub-tests pass |

### AC3 — Quality Bar

| ID | Criterion | Threshold |
|----|-----------|-----------|
| AC3-1 | Each test case has a unique ID (TC-INT-XX) | All 38 cases labeled |
| AC3-2 | Tests organized by system with section headers | 10 section headers |
| AC3-3 | At least 20 total test cases across all sections | 38 cases |
| AC3-4 | At least 3 edge case tests (min/max state, rapid input, empty state) | ≥3 edge cases |
| AC3-5 | At least 2 failure path tests (missing autoload, invalid state) | ≥2 failure paths |

---

## 5. Verification

### Primary Verification

```bash
cd /Users/devvi/workspace/agent-game-test
godot --headless --script tests/run_tests.gd
```

Expected output contains:
```
=== MVP Integration Test (Issue #158) ===
  --- State System Integration ---
    ✅ TC-INT-01: apply_choice sets hope_despair correctly
    ✅ TC-INT-02: apply_choice with legacy hope delta
    ...
  MVP Integration: 38 passed, 0 failed

=== Results ===
Passed: ...
Failed: 0
✅ All tests passed!
```

### Failure Indicators

- Any `❌` in output indicates a specific test case failure
- Non-zero exit code from `godot --headless` runner
- GDScript parse errors on stderr
- Integration test header not printed (file not found or load error)

---

## 6. Dependencies

| Dependency | Status |
|-----------|--------|
| StateSystem (state_system.gd) | ✅ Merged |
| GameManager (game_manager.gd) | ✅ Merged |
| NarrativeManager (narrative_manager.gd) | ✅ Merged |
| AudioManager (audio_manager.gd) | ✅ Merged |
| PlayerController (player_controller.gd) | ✅ Merged |
| NPCNode (npc_node.gd) | ✅ Merged |
| SceneBase (scene_base.gd) | ✅ Merged |
| SceneManager (scene_manager.gd) | ✅ Merged |
| Existing test runner (tests/run_tests.gd) | ✅ Working |
| Godot 4.7 headless mode | ✅ Working |

---

## 7. Open Questions & Risks

| Question | Impact | Resolution |
|----------|--------|------------|
| AudioManager depends on AudioServer — in headless mode, buses may not exist | Audio tests may fail in --headless | Add null guards for bus operations; bus-independent tests (rain_intensity calculation) still work |
| PlayerController._build_node_tree() needs to run before @onready vars are accessible | PlayerController player tests must call new() then manually trigger setup | Follow existing test patterns (_build_node_tree before variable access) |
| SceneManager._create_fade_curtain() uses Animation.new() which is RefCounted | May need special handling in headless mode | No issue — Animation is RefCounted, .new() works fine in headless |
| UnderpassScene depends on SceneBase and scene tree nodes | AC3 hidden text test must mock or extract logic | Extract _check_hidden_text() logic into a testable function or use null guards |

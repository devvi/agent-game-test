# Tasks: #158 — MVP Integration Test — Full Walkthrough

> Parent Issue: #158
> Priority: high
> Estimated: 2-3 hours
> Prerequisite: All MVP scenes, systems, dialogue content, and mechanics merged

---

## Task Breakdown

### Phase 1 — Create Test File + Update Runner (2-3 hours)

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Create `tests/test_mvp_integration.gd` — State System Integration (TC-INT-01→06) | `tests/test_mvp_integration.gd` | None | 15min |
| T2 | Add Dialogue-Game Manager Integration (TC-INT-07→10) | `tests/test_mvp_integration.gd` | T1 | 10min |
| T3 | Add Audio State Modulation tests (TC-INT-11→13) | `tests/test_mvp_integration.gd` | T1 | 10min |
| T4 | Add Narrative & Scene Sequence tests (TC-INT-14→18) | `tests/test_mvp_integration.gd` | None | 15min |
| T5 | Add Echo System tests (TC-INT-19→20) | `tests/test_mvp_integration.gd` | T4 | 10min |
| T6 | Add NPC Framework tests (TC-INT-21→23) | `tests/test_mvp_integration.gd` | None | 10min |
| T7 | Add Player Controller tests (TC-INT-24→27) | `tests/test_mvp_integration.gd` | None | 15min |
| T8 | Add Scene Transition Logic tests (TC-INT-28→29) | `tests/test_mvp_integration.gd` | None | 10min |
| T9 | Add Walkthrough Sequence tests (TC-INT-30→35) | `tests/test_mvp_integration.gd` | T1, T4 | 15min |
| T10 | Add Ending Determination tests (TC-INT-36→38) | `tests/test_mvp_integration.gd` | T4 | 10min |
| T11 | Update `tests/run_tests.gd` to load and run MVP integration tests | `tests/run_tests.gd` | T1-T10 | 5min |
| T12 | Run full test suite and fix any failures | — | T11 | 30min |

### Estimated Total: 2h 25min (plus 30min buffer = ~3h)

---

## Detailed Task Specifications

### T1: State System Integration (TC-INT-01→06)

**File:** `tests/test_mvp_integration.gd`

**Test method:** `_test_state_system()`

Create a fresh `StateSystem` via `load("res://gdscripts/state_system.gd").new()` for each test variant. Verify:

1. **TC-INT-01:** `apply_choice({"hope_despair": 3.0})` → hope_despair=3.0, hope=(3.0+10)/2=6.5, despair=3.5
2. **TC-INT-02:** `apply_choice({"hope": 2.0, "conviction": -1.0, "will": 0.5})` → hope_despair=4.0, hope=7.0, conviction=4.0, will=5.5
3. **TC-INT-03:** `apply_choice({"hope_despair": 100.0})` → hope_despair clamped to 10.0
4. **TC-INT-04:** `apply_choice({"conviction": -100.0})` → conviction clamped to 0.0
5. **TC-INT-05:** `apply_choice({"hope_despair": -10.0})` → state_id=1
6. **TC-INT-06:** Connect to `state_changed` signal, `apply_choice({"hope": 1.0})` → signal fires with hope=6.0

Use `abs(value - expected) < 0.001` for float comparisons.

### T2: Dialogue-Game Manager (TC-INT-07→10)

**Test method:** `_test_dialogue_gm()`

Create a `GameManager` and inject a `StateSystem` reference to test delegation:

1. **TC-INT-07:** Set `ss.hope = 7.0`, assign `gm._state_system = ss` → `gm.get_slider("hope")` returns 7.0
2. **TC-INT-08:** Create GM with no StateSystem → `gm.get_slider("unknown_axis")` returns 5.0
3. **TC-INT-09:** Set `ss.has_flag("test_flag")` = true via mock → `gm.has_flag("test_flag")` = true
4. **TC-INT-10:** `gm.has_flag("nonexistent")` → false

### T3: Audio State Modulation (TC-INT-11→13)

**Test method:** `_test_audio_modulation()`

Create AudioManager (headless — bus indices will be -1). Test the calculation logic:

1. **TC-INT-11:** `_on_state_changed({"conviction": 10.0, "despair": 0.0})` → rain_intensity ≈ 0.0
2. **TC-INT-12:** `_on_state_changed({"conviction": 0.0, "despair": 10.0})` → rain_intensity ≈ 1.0
3. **TC-INT-13:** Same state as TC-INT-12, check `_calc_rain_volume()` → ≤ 0 dB

**Note:** In headless mode, bus indices will be -1. The calculation logic (`_on_state_changed`, `_calc_rain_volume`) still works because they don't depend on AudioServer — only the bus operations do, and those are guarded by `if bus_idx < 0: return`.

### T4: Narrative & Scene Sequence (TC-INT-14→18)

**Test method:** `_test_narrative_scene()`

1. **TC-INT-14:** Verify `NarrativeManager.SCENE_ORDER` array — 6 scenes in correct order
2. **TC-INT-15:** Create NM, call `advance_scene()` → returns "lobby", index=1
3. **TC-INT-16:** Set NM to index 5, `advance_scene()` → returns ""
4. **TC-INT-17:** `determine_ending({hope:7.0, conviction:5.0, will:6.0})` → "keep_walking"
5. **TC-INT-18:** `determine_ending({hope:4.0, conviction:2.0, will:3.0})` → "turn_back"

### T5: Echo System (TC-INT-19→20)

**Test method:** `_test_echo_system()`

1. **TC-INT-19:** `trigger_echo("screensaver_echo")` twice → check `echo_flags["screensaver_echo"]=true` after. Note: second call suppressed by `echo_flags.get(id, false)` guard.
2. **TC-INT-20:** Set `_state_system` (or inject hope=9.0), call `_calculate_echo_variant("rain_echo")` → variant=0

**Note:** `_calculate_echo_variant` reads `_state_system.hope`. Either inject a mock StateSystem or set `_state_system = {hope: 9.0, conviction: 5.0}`.

### T6: NPC Framework (TC-INT-21→23)

**Test method:** `_test_npc_framework()`

1. **TC-INT-21:** Create NPCNode, set exports → verify values
2. **TC-INT-22:** `set_state(1)` → current_state = 1
3. **TC-INT-23:** Set personality_layers with 3 entries → verify layer count and structure

### T7: Player Controller (TC-INT-24→27)

**Test method:** `_test_player_controller()`

1. **TC-INT-24:** Create PlayerController → head, camera, interaction_area non-null after `_build_node_tree()` and `_ready()` (call these manually since no SceneTree)
2. **TC-INT-25:** camera.current = true after setup
3. **TC-INT-26:** Set `_dialogue_active = true`, velocity = Vector3(5,0,5) → in `_physics_process(delta)`, velocity reduces toward zero
4. **TC-INT-27:** Emit `dialogue_ended` → `_dialogue_active = false`

### T8: Scene Transition Logic (TC-INT-28→29)

**Test method:** `_test_scene_transition()`

1. **TC-INT-28:** Create SceneManager, call `_create_fade_curtain()` → check result has CanvasLayer, ColorRect, AnimationPlayer
2. **TC-INT-29:** Set `transition_in_progress = true`, call `trigger_scene_change()` → returns early

### T9: Walkthrough Sequence (TC-INT-30→35)

**Test method:** `_test_walkthrough()`

1. **TC-INT-30:** Create NM + GM, iterate all 6 scenes via advance_scene() → verify each GM.current_scene_id
2. **TC-INT-31:** Create SceneBase (headless, no tree) with StateSystem mock (hope=2.0) → get_state_tier("hope") = "low"
3. **TC-INT-32:** Same, hope=8.0 → "high"
4. **TC-INT-33:** SceneBase with no StateSystem → "mid"
5. **TC-INT-34:** SceneBase with no SpawnPoint → Vector3.ZERO
6. **TC-INT-35:** UnderpassScene with hope=1.5, conviction=1.5 → hidden text reveals AC3 content

### T10: Ending Determination (TC-INT-36→38)

**Test method:** `_test_endings()`

1. **TC-INT-36:** High hope → "keep_walking"
2. **TC-INT-37:** Low conviction → "turn_back"
3. **TC-INT-38:** Mid values → "stay" (fallthrough)

### T11: Update run_tests.gd

**File:** `tests/run_tests.gd`

Add block between existing Integration Tests block and the next block (around line 60-61):

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

### T12: Run Full Test Suite

```bash
cd /Users/devvi/workspace/agent-game-test
godot --headless --script tests/run_tests.gd
```

Expected:
- Exit code 0
- "=== MVP Integration Test ===" header in output
- All 38 TC-INT cases pass with "✅"
- No regression in existing tests
- No GDScript parse errors

---

## Verification Checklist

- [ ] All 38 test cases pass
- [ ] Exit code 0 from headless runner
- [ ] "=== MVP Integration Test ===" header printed
- [ ] No parse errors on stderr
- [ ] All existing tests still pass (no regression)
- [ ] TC-INT-03 (clamp max), TC-INT-04 (clamp min), TC-INT-10 (missing flag), TC-INT-29 (transition gating) exercise edge cases
- [ ] TC-INT-33 (missing autoload fallback), TC-INT-34 (missing SpawnPoint) exercise failure paths

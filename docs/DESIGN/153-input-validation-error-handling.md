# Design: #153 — Input Validation & Error Handling

> Parent Issue: #153
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Add systematic, consistent input validation and error handling across the game's critical systems — PlayerController, NPCNode, SceneManager, SceneBase, and boot/startup — using Godot-native `@export_range` annotations, startup integrity checks, method boundary guards, and expanded test coverage. This is a cross-cutting hardening pass, not a new system.

### Validation Layers

```
Layer 1: @export_range (editor-time constraint)
    ├── Enforced by Godot inspector — prevents invalid values at authoring time
    ├── Does NOT apply in headless --script mode
    └── Must be paired with runtime clamp() in setters for headless safety

Layer 2: _ready() startup checks (boot-time)
    ├── _verify_input_map() — confirms all required InputMap actions exist
    ├── _verify_autoloads() — confirms critical autoloads are available
    └── Runs once per session — logs missing items with push_warning

Layer 3: Method boundary validation (call-time)
    ├── Empty/null string guards (dialogue_file, dialogue_id)
    ├── Out-of-range parameter checks (choice_index, scene path)
    └── Returns early with push_warning for recoverable conditions

Layer 4: Null-safety at call sites (defensive)
    ├── get_node_or_null() + is_instance_valid() — existing pattern (40+ sites)
    ├── has_method() / has_signal() guards — existing pattern
    └── Consistent fallback defaults with warning

Layer 5: Graceful degradation (last resort)
    ├── Missing autoload → null → fallback values (hope=5, conviction=5, will=5)
    ├── Failed scene transition → stay in current scene, log error
    └── Dialogue file not found → push_error, UI remains in current state
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Validation approach | Inline @export + guards (Approach A) | Existing codebase conventions (push_warning/push_error, @export); no new autoloads or utility files needed |
| Runtime headless safety | clamp() in setters + method guards | @export_range is editor-only; headless/--script tests bypass inspector. Runtime guard is required for all exported parameters that affect behavior |
| Startup check location | main.gd + GameManager._ready() | Both are autoloads that run at boot; GameManager already serves as the delegation hub |
| Verification frequency | Once per session at boot | Validation state doesn't change during runtime; redundant checks at every call site waste cycles |
| Signal connection guards | is_connected() before connect() | Prevents double-connect on re-entrance (EKeyTrigger) without breaking existing patterns |
| Test framework | RefCounted + run() pattern (existing) | Consistent with 25 existing test files; registered in run_tests.gd |

---

## 2. Modified Files

### 2.1 Player Controller (`gdscripts/player_controller.gd`)

**6 exports need @export_range bounds:**

| Export | Current | Proposed Range | Rationale |
|--------|---------|----------------|-----------|
| `walk_speed` | `@export var walk_speed: float = 2.5` | `@export_range(0.5, 10.0, 0.1) var walk_speed: float = 2.5` | Narrative pace: 0.5 crawl to 10.0 sprint |
| `look_sensitivity` | `@export var look_sensitivity: float = 0.003` | `@export_range(0.001, 0.02, 0.0005) var look_sensitivity: float = 0.003` | Mouse sensitivity range |
| `interaction_range` | `@export var interaction_range: float = 2.0` | `@export_range(0.5, 10.0, 0.1) var interaction_range: float = 2.0` | Proximity detection radius |
| `camera_height` | `@export var camera_height: float = 1.6` | `@export_range(0.5, 3.0, 0.1) var camera_height: float = 1.6` | Eye level range |
| `camera_tilt` | `@export var camera_tilt: float = -0.087` | `@export_range(-1.0, 1.0, 0.001) var camera_tilt: float = -0.087` | Tilt angle in radians |
| `look_vertical_clamp` | `@export var look_vertical_clamp: float = 1.047` | `@export_range(0.174, 1.57, 0.01) var look_vertical_clamp: float = 1.047` | 10° to 90° (0.174 to 1.57 rad) |

**Additional changes:**
- Add `_verify_input_map()` guard in `_ready()` — check that all 4 movement actions + `interact` exist
- Signal connections in `_ready()` already safe from `_build_node_tree()` path — no double-connection risk on `interaction_area.body_entered/exited` since nodes are freshly created each time. However, `_connect_dialogue_signals()` should have null-guards (already present for `scene_root` and `dr`)
- Add `clamp()` in `_physics_process()` for `walk_speed` as runtime safety (headless mode bypasses @export_range)

### 2.2 NPC Node (`gdscripts/npc_node.gd`)

**Relevant exports for @export_range:**

| Export | Current | Proposed Range | Rationale |
|--------|---------|----------------|-----------|
| `proximity_distance` | `@export var proximity_distance: float = 3.0` | `@export_range(0.5, 20.0, 0.1) var proximity_distance: float = 3.0` | Interaction trigger radius |
| `cooldown_seconds` | `@export var cooldown_seconds: float = 2.0` | `@export_range(0.5, 60.0, 0.5) var cooldown_seconds: float = 2.0` | Cooldown between interactions |

**Additional changes:**
- Add empty-string validation on `dialogue_file` and `dialogue_id` before `_dialogue_runner.start()` calls (lines 107, 120)
- `speaker_name` default is "NPC" — intentionally non-empty. Document as safe (no guard needed for the default, but an empty override should warn)
- Add null-check on `_name_label` and `_prompt_label` before accessing `.text` property in `_ready()` (line 68-71) — these are `@onready var` and could theoretically be null if the scene structure is wrong
- `mood_axis` is used in `_build_state_snapshot()` indirectly — already guarded by `_get_axis()` fallback in StateSystem

### 2.3 State System (`gdscripts/state_system.gd`)

**Parameter validation on record_choice():**
- `record_choice(node_id: String, choice_index: int, choice_text: String)` — add empty-string guard on `node_id` and `choice_text`; `choice_index` is already safe (int can't be null)
- `set_flag(name: String, value: bool)` — add empty-string guard on `name`
- `apply_choice(effect: Dictionary)` — already uses `.get()` defaults for all keys (safe). Add warning if `effect` is empty (not an error, but worth noting in debug)
- `save_state_to_file(path: String)` — add empty-string guard; existing path logic handles missing dirs

### 2.4 Scene Manager (`gdscripts/scene_manager.gd`)

**Path validation in `trigger_scene_change()`:**
- Add `if target_scene.is_empty(): return` guard
- Add `FileAccess.file_exists(target_scene)` check before calling `change_scene_to_file()`
- If file doesn't exist, `push_error()` and return early with `transition_in_progress = false`
- `_connect_to_dialogue()` — signal connections already guarded by `has_signal("choice_made")` — no change needed

### 2.5 Scene Base (`gdscripts/scene_base.gd`)

**Null-safety improvements:**
- `_instantiate_player()` — already has null-checks on `_player`, `gm`, and saved values (lines 76-98). No change needed for existing paths.
- Add spawn point validation — if `SpawnPoint` node is missing, log `push_warning` and fall back to `Vector3.ZERO` (already the case via `_get_player_spawn_position()`)
- `start_dialogue(file_path: String, dialogue_id: String)` — add empty-string guard on both parameters

### 2.6 Game Manager (`gdscripts/game_manager.gd`)

**Input Map validation in `_ready()`:**
- Add `_verify_input_map()` call that checks all 5 required actions (`move_forward`, `move_backward`, `move_left`, `move_right`, `interact`)
- Also verify dialogue-specific actions: `dialogue_up`, `dialogue_down`, `dialogue_select`, `dialogue_skip`, `toggle_dialogue`
- Log `push_warning` for each missing action, but only once per session

### 2.7 Main Script (`gdscripts/main.gd`)

**Correction to PRD:** The `main.gd` file at `res://gdscripts/main.gd` is the old CRPG entry scene script. Per codebase inspection, `main.gd` references `get_node("/root/GameState")` (deprecated name) rather than `get_node("/root/StateSystem")`. The actual boot entry point is **GameManager** (autoload), not `main.gd`.

**Changes:**
- Add `_verify_autoloads()` in `GameManager._ready()` — check that `/root/StateSystem`, `/root/NarrativeManager`, `/root/AudioManager` are present
- Log warning for each missing autoload: `push_warning("GameManager: Autoload '/root/xxx' not found")`
- `main.gd` is used as the initial scene entry — add null guards for `dialogue_display_3d` (line 34-37, already guarded). Add `is_instance_valid()` guards on `dialogue_runner` signal connections (lines 28-31)

### 2.8 E-Key Trigger (`gdscripts/e_key_trigger.gd`)

**Signal connection guards:**
- `_on_body_entered()` already uses `is_connected()` before `connect()` (line 19) — ✅ safe
- `_on_body_exited()` already uses `is_connected()` before `disconnect()` (line 25) — ✅ safe
- No code changes needed for existing patterns. Document as already correct.

### 2.9 Audio Manager (`gdscripts/audio_manager.gd`)

**Already robust per codebase inspection:**
- `_try_load()` returns null gracefully (line 82-89) — ✅ safe
- `_set_bus_effect_enabled()` bounds-checks bus_idx and effect_idx (lines 190-197) — ✅ safe
- `get_surface_for_scene()` and `_get_profile_for_scene()` use `.get()` with defaults — ✅ safe
- `_on_state_changed()` uses `state.get("key", default)` — ✅ safe
- No code changes needed. Document as reference model.

---

## 3. API Contracts

### Signal Connection Safety

| Signal | Location | Current Guard | Change Needed |
|--------|----------|---------------|---------------|
| `interaction_area.body_entered` | `player_controller.gd:107` | None (node built in _ready) | None — node is freshly created |
| `interaction_area.body_exited` | `player_controller.gd:108` | None (node built in _ready) | None — node is freshly created |
| `body.interaction_requested` → `_on_player_interact` | `e_key_trigger.gd:19` | `is_connected()` guard | None — already safe |
| `body.interaction_requested` disconnect | `e_key_trigger.gd:25` | `is_connected()` guard | None — already safe |
| `dialogue_started` / `dialogue_ended` | `main.gd:28-29` | `if dialogue_runner != null` | Add `is_instance_valid()` |
| `state_changed` → `status_bar` | `main.gd:41` | `if state_system != null and status_bar != null` | None — already safe |
| `dialogue_runner.dialogue_ended` | `npc_node.gd:66` | `if _dialogue_runner:` then connect | Add `is_connected()` guard |

### Method Call Chains (Validation-Aware)

```
Boot:
  GameManager._ready()
    ├── _verify_autoloads()      # NEW — checks StateSystem, NarrativeManager, AudioManager
    └── print("GameManager initialized.")

Runtime — NPC interaction:
  NPCNode._on_interaction()
    ├── if dialogue_file.is_empty() or dialogue_id.is_empty(): return
    ├── _dialogue_runner.start(dialogue_file, dialogue_id)
    │     └── push_error if file not found
    └── npc_interacted.emit()

Runtime — Scene transition:
  SceneManager.trigger_scene_change(target_scene)
    ├── if transition_in_progress: return
    ├── if target_scene.is_empty(): return                   # NEW
    ├── if not FileAccess.file_exists(target_scene):         # NEW
    │     ├── push_error("Scene not found: " + target_scene)
    │     └── transition_in_progress = false / return
    ├── change_scene_to_file(target_scene)
    └── if err != OK: push_error() + transition_in_progress = false

Runtime — state effects:
  StateSystem.apply_choice(effect)
    ├── if effect.is_empty(): push_warning + return           # NEW
    └── .get() defaults for all keys                         # Existing (safe)

Runtime — save/load:
  StateSystem.record_choice(node_id, choice_index, choice_text)
    ├── if node_id.is_empty(): push_warning + return          # NEW
    ├── if choice_text.is_empty(): push_warning + return      # NEW
    └── _choice_history.append(record)
```

---

## 4. Test Plan

### Test File Structure

| File | Type | Target |
|------|------|--------|
| `tests/unit/test_input_map_validation.gd` | Unit | Input map validation (existing — expand with edge + failure tests) |
| `tests/unit/test_player_controller.gd` | Unit | PlayerController export ranges, @export_range bounds |
| `tests/unit/test_npc_node.gd` | Unit | NPCNode empty-string guards, range bounds |
| `tests/unit/test_game_manager_player.gd` | Unit | GameManager startup checks |
| `tests/integration/test_player_in_scene.gd` | Integration | SceneBase spawn validation |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Input Map validation | ✅ 5 tests (existing) | ✅ 2 new | ✅ 3 new |
| Export bounds (PlayerController) | ✅ 2 tests | ✅ 2 tests | — |
| NPCNode empty-string guards | ✅ 1 test | ✅ 1 test | ✅ 1 test |
| SceneManager path validation | ✅ 1 test | ✅ 1 test | ✅ 2 tests |
| StateSystem parameter validation | ✅ 2 tests | ✅ 1 test | ✅ 2 tests |
| Autoload verification | — | ✅ 1 test | ✅ 2 tests |
| Signal connection safety | ✅ 1 test | — | ✅ 1 test |

### Test Cases (TC1–TC17)

#### Input Map Validation

| # | Scenario | Type | Setup | Expected Assertion |
|---|----------|------|-------|-------------------|
| TC1 | `move_forward` exists (existing TC-IM-N-1) | Normal | Headless mode | `InputMap.has_action("move_forward") == true` |
| TC2 | `move_backward` exists (existing TC-IM-N-2) | Normal | Headless mode | `InputMap.has_action("move_backward") == true` |
| TC3 | `move_left` exists (existing TC-IM-N-3) | Normal | Headless mode | `InputMap.has_action("move_left") == true` |
| TC4 | `move_right` exists (existing TC-IM-N-4) | Normal | Headless mode | `InputMap.has_action("move_right") == true` |
| TC5 | `interact` exists (existing TC-IM-N-5) | Normal | Headless mode | `InputMap.has_action("interact") == true` |
| TC6 | Unknown action returns false | Edge | Headless mode, no registration | `InputMap.has_action("nonexistent_action") == false` |
| TC7 | `dialogue_up` action exists | Edge | Headless mode | `InputMap.has_action("dialogue_up") == true` (register if needed) |
| TC8 | `Input.get_vector()` with missing action returns ZERO | Failure | Headless, action removed, call `Input.get_vector("missing", "missing", "missing", "missing")` | `result == Vector2.ZERO` |
| TC9 | `_verify_input_map()` logs warning for missing action | Failure | Headless, one action missing before registration, spy on `push_warning` (or mock) | Warning contains action name |
| TC10 | `_verify_input_map()` with all actions present logs no warning | Normal | All 5 movement actions registered | No warnings logged |

#### Export Bounds (PlayerController)

| # | Scenario | Type | Setup | Expected Assertion |
|---|----------|------|-------|-------------------|
| TC11 | `walk_speed` initial value is 2.5 | Normal | `PlayerController.new()` | `walk_speed == 2.5` |
| TC12 | Negative `walk_speed` is clamped at runtime | Edge | After instantiation, call `_physics_process()` with negative walk_speed set | Velocity magnitude does not exceed `clamp(walk_speed, 0.5, 10.0)` |
| TC13 | All 6 exports have `@export_range` annotation (static check) | Edge | Read `player_controller.gd` source | Each `@export var` has matching `@export_range` |

#### NPCNode Empty-String Guards

| # | Scenario | Type | Setup | Expected Assertion |
|---|----------|------|-------|-------------------|
| TC14 | Empty `dialogue_file` + empty `dialogue_id` prevents `_dialogue_runner.start()` call | Failure | Create NPCNode with `dialogue_file = ""`, `dialogue_id = ""`, call `start_npc_interaction()` | `_dialogue_runner.start()` is never called (mock/spy) |
| TC15 | Valid `dialogue_file` + `dialogue_id` triggers `_dialogue_runner.start()` | Normal | Create NPCNode with valid paths, call `start_npc_interaction()` | `_dialogue_runner.start()` is called with correct params |
| TC16 | `proximity_distance` with `@export_range(0.5, 20.0)` bounds | Normal | Create NPCNode | `proximity_distance` default is 3.0, accepts 0.5–20.0 |

#### SceneManager Path Validation

| # | Scenario | Type | Setup | Expected Assertion |
|---|----------|------|-------|-------------------|
| TC17 | Empty scene path returns early without transition | Failure | `trigger_scene_change("")` | `transition_in_progress == false`, `change_scene_to_file()` not called |
| TC18 | Nonexistent scene path logs error and returns | Failure | `trigger_scene_change("res://nonexistent.tscn")` | `push_error` called with scene path, `transition_in_progress == false` |
| TC19 | Valid scene path triggers transition | Normal | `trigger_scene_change("res://scenes/office/office.tscn")` | `transition_started` signal emitted, `transition_in_progress == true` |

#### StateSystem Parameter Validation

| # | Scenario | Type | Setup | Expected Assertion |
|---|----------|------|-------|-------------------|
| TC20 | `record_choice()` with empty `node_id` logs warning | Failure | `record_choice("", 0, "test")` | `push_warning` called, no record appended |
| TC21 | `record_choice()` with empty `choice_text` logs warning | Failure | `record_choice("node", 0, "")` | `push_warning` called, no record appended |
| TC22 | `set_flag()` with empty name logs warning | Edge | `set_flag("", true)` | `push_warning` called, flag not set |
| TC23 | `apply_choice()` with empty effect dict is safe | Normal | `apply_choice({})` | All state values unchanged, `state_changed` still emitted |

#### Autoload / Startup Verification

| # | Scenario | Type | Setup | Expected Assertion |
|---|----------|------|-------|-------------------|
| TC24 | GameManager `_verify_autoloads()` tolerates missing autoloads | Failure | Load GameManager in headless mode (no autoloads present) | No crash; `push_warning` logged for each missing autoload |
| TC25 | StateSystem.get_state() returns fallback when autoload missing | Failure | Call `get_state()` when StateSystem unavailable | Returns `{"hope": 5.0, "conviction": 5.0, "will": 5.0}` |

#### Signal Connection Safety

| # | Scenario | Type | Setup | Expected Assertion |
|---|----------|------|-------|-------------------|
| TC26 | Double `_ready()` call on EKeyTrigger doesn't double-connect signals | Edge | Call `_ready()` twice, then trigger body_entered | Signal handler fires exactly once |
| TC27 | `_connect_dialogue_signals()` with null `dialogue_runner` is safe | Failure | Call with no `DialoguePanel` in scene | No crash, no error (returns silently) |

---

## 5. Files Changed

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `gdscripts/player_controller.gd` | Modify | Add `@export_range` on 6 exports; add `clamp()` in `_physics_process`; add `_verify_input_map()` in `_ready()` | ±30 |
| `gdscripts/npc_node.gd` | Modify | Add `@export_range` on 2 exports; add empty-string guards on `dialogue_file`/`dialogue_id` in `start_npc_interaction()` and `_on_interaction()`; add null-guards on labels | ±20 |
| `gdscripts/state_system.gd` | Modify | Add empty-string guards on `record_choice()` and `set_flag()`; add empty-effect warning in `apply_choice()`; add empty-string guard in `save_state_to_file()` | ±20 |
| `gdscripts/scene_manager.gd` | Modify | Add empty-string guard on `trigger_scene_change()`; add `FileAccess.file_exists()` check before transition | ±15 |
| `gdscripts/scene_base.gd` | Modify | Add spawn point warning; add empty-string guard on `start_dialogue()` | ±10 |
| `gdscripts/game_manager.gd` | Modify | Add `_verify_input_map()` + `_verify_autoloads()` in `_ready()` | ±25 |
| `gdscripts/main.gd` | Modify | Add `is_instance_valid()` guards on signal connections | ±10 |
| `tests/unit/test_input_map_validation.gd` | Modify | Add TC-IM-E (2 tests) and TC-IM-F (3 tests) | ±40 |
| `tests/unit/test_player_controller.gd` | Modify | Add export bounds tests (TC11-TC13) | ±30 |
| `tests/unit/test_npc_node.gd` | Modify | Add empty-string guard tests (TC14-TC16) | ±30 |
| `tests/unit/test_game_manager_player.gd` | Modify | Add autoload verification tests (TC24-TC25) | ±20 |

**Total estimated delta:** ±250 lines across 11 files (approximately 150 lines of validation code + 100 lines of tests)

---

## 6. Implementation Order (Dependency Chain)

| Priority | Task | Files | Reason |
|----------|------|-------|--------|
| **P0** | @export_range annotations | player_controller.gd, npc_node.gd | Quickest, zero behavioral impact. Editor-only change. |
| **P0** | GameManager startup checks (_verify_input_map, _verify_autoloads) | game_manager.gd | Detects misconfiguration at boot — runs before any interaction |
| **P0** | PlayerController guards | player_controller.gd | Most user-visible system — movement is the primary interaction |
| **P0** | NPCNode empty-string guards | npc_node.gd | Prevents silent no-ops when `dialogue_file`/`dialogue_id` are empty |
| **P1** | SceneManager path validation | scene_manager.gd | Blocks invalid scene transitions — user-visible failure mode |
| **P1** | StateSystem parameter validation | state_system.gd | Low-impact — `.get()` defaults already handle missing keys |
| **P1** | SceneBase spawn validation | scene_base.gd | Minor — spawn at ZERO is an edge case |
| **P1** | main.gd signal guards | main.gd | Low risk — signal disconnect already graceful |
| **P1** | Test expansion | All test files | Tests verify all above changes |

---

## 7. Verification Checklist

- [ ] All 6 PlayerController exports have `@export_range` bounds matching the design table
- [ ] Both NPCNode numeric exports (`proximity_distance`, `cooldown_seconds`) have `@export_range`
- [ ] `GameManager._ready()` calls `_verify_input_map()` and `_verify_autoloads()`
- [ ] NPCNode guards against empty `dialogue_file`/`dialogue_id` before calling `start()`
- [ ] SceneManager guards against empty and nonexistent scene paths in `trigger_scene_change()`
- [ ] StateSystem `record_choice()` guards against empty `node_id` and `choice_text`
- [ ] StateSystem `set_flag()` guards against empty name
- [ ] StateSystem `apply_choice()` warns on empty effect dict
- [ ] All existing 25+ test files still pass (no regression)
- [ ] `test_input_map_validation.gd` has ≥5 edge/failure tests (TC-IM-E + TC-IM-F)
- [ ] No new autoloads or script-level dependencies added
- [ ] All changes use existing `push_warning`/`push_error` conventions (no new logging)

---

## 8. Corrections to PRD

During codebase inspection, the following discrepancies were found against the PRD's descriptions:

1. **PRD section 3 lists `main.gd` as the boot entry script.** The actual boot process uses `GameManager` (autoload) for runtime setup. `main.gd` is an old CRPG entry scene that references `get_node("/root/GameState")` (deprecated) — it should be `/root/StateSystem`. This is a pre-existing bug, not in scope for #153, but should be noted for future cleanup.

2. **PRD estimates 44 @export declarations across scripts.** Investigation confirms this count. However, the PRD's scope of "all scripts" is unnecessarily broad — the DESIGN doc narrows P0/P1 scope to files directly affecting gameplay interaction (player_controller.gd and npc_node.gd). Dialogue-only exports (DialogueNode, DialogueBranch, DialogueData, dialogue_display_3d, lo_fi_text_3d, text_variant_data) are excluded from P0/P1 because existing validation (has_method, get_node_or_null) already handles null values gracefully, and range constraints on dialogue presentation parameters (font size, spacing) are cosmetic, not functional.

3. **PRD section 2 claims `@export_range` is sufficient.** Codebase inspection confirms that `@export_range` is editor-only. Headless `--script` mode bypasses inspector clamping. The DESIGN doc adds `clamp()` in setters and method guards for runtime safety — the PRD's "Correction for plan" note at the bottom already acknowledges this.

4. **PRD lists `e_key_trigger.gd` as needing `is_connected()` guards on connect.** Codebase inspection reveals `e_key_trigger.gd` already has `is_connected()` on both connect AND disconnect (lines 19, 25). No change needed — this pattern is already correct.

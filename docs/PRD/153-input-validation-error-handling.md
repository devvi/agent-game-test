# Research: Input Validation & Error Handling

> Parent Issue: #153
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The game compiles and runs without errors, and has a baseline of defensive programming already in place. However, there are **no systematic input validation or error-handling patterns** — the existing protections are ad-hoc, inconsistent across modules, and leave significant gaps:

**Existing patterns (strengths):**
- `get_node_or_null()` + null-guard used extensively throughout (40+ call sites)
- `has_method()` / `has_signal()` guards before connecting or calling
- `push_warning()` on 50+ non-fatal conditions (file load failure, unknown axis, missing profile, anti-loop detection)
- `push_error()` on 17 fatal conditions (dialogue load fail, missing nodes, choice OOB, scene transition fail)
- `clamp()` / `clampf()` in setter functions for state values
- `match` with `_:` default on all enum/constant branches
- `is_instance_valid()` checks on cached node references
- `_try_load()` pattern for audio assets with null-return

**Missing (gaps):**
1. **No @export range validation** — 44 exported variables across scripts lack `@export_range` or `@export var` bounds. A `walk_speed` of `-5.0`, `interaction_range` of `1000`, or `cooldown_seconds` of `0` are silently accepted.
2. **No Input Map validation** — `Input.get_vector()` / `Input.get_axis()` silently return `Vector2.ZERO` / `0.0` if the named actions are missing from the Input Map. The test file `test_input_map_validation.gd` exists but only has normal-path checks (5 passes), no edge/failure cases, and the test is NOT run in CI.
3. **No empty/null string validation on critical exports** — `dialogue_file: String = ""`, `dialogue_id: String = ""`, `speaker_name: String = "NPC"` accept empty values. NPCNode attempts `dialogue_runner.start("")` which logs `push_error("Dialogue load failed: path is empty")` — degrades gracefully but wastes a frame.
4. **No parameter range validation for dialogue effects** — `apply_choice()` doesn't validate `choice_index` for negative values (though path is guarded). `record_choice()` accepts empty strings.
5. **No collision layer/enum validation** — Collision layers (player, environment, trigger) are convention-based with no runtime enforcement. A misconfigured scene silently fails collision.
6. **No scene transition path validation** — `trigger_scene_change()` accepts arbitrary strings; `change_scene_to_file()` returns `OK`/error, but the error path only logs and resets — no retry, no fallback scene.
7. **No duplicate signal connection guards** — Some areas connect signals in `_ready()` without `is_connected()` check, risking double-connect on re-entrance.
8. **No formal error classification** — `push_error` for parse errors, `push_warning` for recoverable, `print` for debug — but no structured logging (no `logger_name`, no severity level).
9. **No startup validation** — No system checks at boot: Input Map integrity, autoload presence, required scenes, bus layout, collision layer setup.
10. **Graceful degradation is assumed but untested** — When StateSystem returns null, consumers fall back to neutral defaults (hope=5, conviction=5, will=5), but the fallback paths have no test coverage and may mask configuration errors.

### Expected Behavior

The game should have systematic, consistent input validation and error handling:

- **@export validation:** All exported parameters have range/type constraints appropriate to their domain (walk_speed ∈ [0.5, 10], interaction_range ∈ [0.5, 10], etc.)
- **Input Map validation:** Runtime check at startup that all required Input Map actions exist. Missing actions logged with clear error message.
- **Parameter validation:** Dialogue effects, state transitions, and API calls validate inputs at the boundary (non-null, non-empty, in-range).
- **Null safety:** Continued `get_node_or_null()` pattern, extended to all autoload-dependent code paths with consistent fallback behavior.
- **Graceful degradation:** When a system fails, it degrades without crashing — logged with appropriate severity.
- **Startup integrity checks:** On `_ready()`, critical systems (StateSystem, GameManager, AudioManager, InputMap) are verified. Missing autoloads or misconfigurations are logged early.
- **Test coverage:** Input Map validation, parameter bounds, and error path tests exist and are runnable in `--script` mode.

### User Scenarios

- **Scenario A (Developer):** Developer exports a scene with `walk_speed = -1.0`. The engine clamps or warns at load time, not silently accepting invalid values.
- **Scenario B (Developer):** Developer adds a new Input Map action but misspells it in `player_controller.gd`. A startup validation log catches the mismatch immediately.
- **Scenario C (Runtime):** An audio file fails to load. AudioManager logs a warning and continues without that sound — no crash, no silent failure.
- **Scenario D (Runtime):** StateSystem autoload entry is accidentally removed from `project.godot`. All downstream consumers receive null — each logs a warning once and uses safe defaults.
- **Frequency:** Every game launch (startup checks), every interaction (parameter validation), every frame (null-safety).

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally across 30+ issues, each adding features without a cross-cutting validation/error-handling pass:

1. **MVP velocity priority** — Earlier issues (scaffold, scenes, dialogue engine, narrative) focused on getting features working rather than hardening them. Error handling was added reactively where bugs appeared.
2. **Godot's lenient defaults** — Godot silently accepts untyped exports, missing Input Map actions return zero vectors, `get_node_or_null()` returns null without warning. The engine doesn't enforce validation.
3. **Multi-agent pipeline gap** — Each agent (research → plan → implement) focused on its specific feature. No issue was dedicated to cross-cutting robustness.
4. **Existing tests are coverage-incomplete** — `test_input_map_validation.gd` has only normal-path assertions (5 of TC-IM-N). Zero edge-case or failure-path tests.

### Why Change Now?

- **Issue #153 is explicitly tagged `core`** — input validation and error handling are foundational quality concerns.
- **The game has become complex enough** that silent failures (missing Input Map actions, invalid @export values, missing autoloads) are hard to debug without systematic validation.
- **Multiple downstream features depend on consistent error behavior** — NPC interaction, E-key triggers, player movement, scene transitions all rely on the same input and validation pathways.
- **Test coverage gap** — Without validation tests, the project has no regression protection against configuration drift (e.g., someone removes an Input Map action or changes an export range).

### Previous Constraints

- **Godot 4.7 GDScript** — All validation logic must be GDScript. No C# or GDExtension.
- **Existing conventions preserved** — `push_warning` for non-fatal, `push_error` for fatal. Don't replace the logging pattern, just make it systematic.
- **Headless test compatible** — Validation must work in `--script` mode (no scene tree required for unit tests).
- **No new autoloads for validation** — Keep validation as utility functions/static methods rather than adding new singletons.
- **Backward compatible** — Adding validation must NOT change runtime behavior for valid configurations. Only newly-invalid states produce warnings.

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/player_controller.gd` | Player Controller | Add `@export_range` bounds on all 6 exports; add `InputMap.has_action()` guard in `_ready()` |
| `gdscripts/npc_node.gd` | NPC Framework | Add `@export_range` on `proximity_distance`, `cooldown_seconds`; add empty-string validation on `dialogue_file`, `dialogue_id` before `dialogue_runner.start()` |
| `gdscripts/state_system.gd` | State System | Add `apply_choice()` parameter validation; add safe bounds on `record_choice()` params |
| `gdscripts/scene_manager.gd` | Scene Manager | Add path validation in `trigger_scene_change()`; add fallback scene on transition failure |
| `gdscripts/scene_base.gd` | Scene Base | Add null-safety for PlayerController instantiation; add spawn point validation |
| `gdscripts/game_manager.gd` | Game Manager | Add Input Map validation call in `_ready()`; add axis name validation in `get_slider()` |
| `gdscripts/main.gd` | Entry Script | Add boot-time integrity check for autoloads and Input Map |
| `gdscripts/audio_manager.gd` | Audio Manager | Add bus index validation in `_set_bus_effect_enabled()` (already has bounds checking) |
| `gdscripts/e_key_trigger.gd` | E-Key Trigger | Add `is_connected()` guards before signal connection (already done for disconnect) |
| `tests/unit/test_input_map_validation.gd` | Tests | Add TC-IM-E edge cases and TC-IM-F failure path tests |
| `project.godot` | Project Config | Add input action validation section (documentation only — no code change) |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/status_bar.gd` | Status Bar | Already safe via `state.get("hope_despair", 0.0)` — no change needed |
| `gdscripts/dialogue_runner.gd` | Dialogue Runner | Already has extensive error handling — doc the existing patterns |
| `gdscripts/hemingway_enforcer.gd` | Hemingway Enforcer | Already validates parameters at boundary — model for other modules |
| `gdscripts/ui_config.gd` | UI Config | Already safe via `is_instance_valid(viewport)` checks — model for other modules |
| All scene scripts (6) | Scene Scripts | Already use null-safe `get_node_or_null()` — consistent pattern |
| All test files (25) | Tests | May need additional validation tests per module |

### Data Flow Impact

**Current (ad-hoc validation):**
```
@export walk_speed: float = 2.5    # No bounds — accepts negative or extreme values
Input.get_vector("move_left", ...)  # No guard — silently returns Vector2.ZERO if actions missing
dialogue_runner.start("", "")       # No empty-string guard — push_error logged but wastes frame
```

**Proposed (systematic validation):**
```
@export_range(0.5, 10.0, 0.1) var walk_speed: float = 2.5
# Clamped at assignment point by Godot engine

func _ready() -> void:
    _verify_input_map()  # Runs once at startup, logs missing actions

if dialogue_file.is_empty() or dialogue_id.is_empty():
    push_warning("NPCNode: dialogue_file or dialogue_id is empty — skipping")
    return
dialogue_runner.start(dialogue_file, dialogue_id)
```

Validation layers:
```
Layer 1: @export_range (compile-time constraint, enforced by Godot inspector)
Layer 2: _ready() startup checks (autoload presence, Input Map integrity)
Layer 3: Method boundary validation (empty strings, out-of-range params)
Layer 4: Null-safety at call sites (get_node_or_null, is_instance_valid, has_method)
Layer 5: Fallback defaults with warning (unknown axis → push_warning + return 5.0)
```

### Documents to Update

- [ ] `docs/DESIGN/153-input-validation-error-handling.md` — Will be created in Plan phase
- [ ] `docs/GAME_DESIGN/02-WORKFLOW.md` — Document validation conventions for future issues
- [ ] `docs/GAME_DESIGN/03-GODOT-SETUP.md` — Add Input Map convention reference

---

## 4. Solution Comparison

### Approach A: Systematic @export + Startup + Unit Tests (Recommended)

**Description:** Add `@export_range` bounds to all exported variables across the codebase. Add `_verify_input_map()` startup check in `main.gd`. Add empty-string and out-of-range guards at API boundaries. Write comprehensive unit tests for validation paths.

**Pros:**
- **Additive, not breaking** — existing valid configurations work identically
- **Godot-native** — `@export_range` is enforced by the inspector
- **Low implementation effort** — mostly adding attributes and guard clauses
- **Testable** — each validation path is independently testable in `--script` mode
- **Catches misconfiguration early** — at boot or load time, not at first use
- **Consistent with existing patterns** — builds on `push_warning`/`push_error` conventions

**Cons:**
- Adds ~15 `@export_range` annotations across scripts
- Boot-time checks add ~1ms to startup (negligible)
- Does NOT solve dynamic runtime input validation (e.g., dialogue JSON malformation)
- Some validation is only enforceable in editor (inspector range), not at headless runtime

**Risk:** Low — purely additive constraints. No runtime behavior changes for valid configs.

**Effort:** Small (~2-3 hours: annotate exports, write startup checks, add guard clauses, write tests)

### Approach B: Centralized Validation Utility

**Description:** Create a `Validator.gd` static utility class with reusable validation functions for common patterns (non-empty string, in-range float, valid axis name, valid dialogue file). All call sites use the validator instead of inline checks.

**Pros:**
- **Centralized logic** — one place to update validation rules
- **Reusable** — shared across all modules
- **More structured output** — consistent error message format
- **Easier to test** — single test file for all validation utilities

**Cons:**
- **New file + new dependency** — increases code footprint
- **Over-engineered for this scope** — most validations are single-line guards that don't benefit from centralization
- **Inline guards are equally testable** — a utility class adds abstraction without adding value for this codebase's size
- **@export_range** is already the Godot-native way to constrain exports — wrapping it in a validator would be redundant
- **Higher effort** for no additional safety vs Approach A

**Risk:** Low — but adds code without proportional benefit.

**Effort:** Medium (~3-4 hours: create Validator.gd, refactor all call sites, write tests)

### Approach C: Assertion-Based with Debug Build Only

**Description:** Add `assert()` calls at key API boundaries, active only in debug builds. No persistent validation logic.

**Pros:**
- Minimal code change
- Catches development errors early
- Zero runtime overhead in release builds
- Godot-native — `assert()` is built-in

**Cons:**
- **Disabled in release builds** — release players get no validation
- **assert() crashes** — not graceful degradation, it's hard crash on first failure
- **No warning path** — cannot distinguish recoverable from fatal
- **Not testable** — assert() can't be caught or asserted in tests without custom handling
- **Existing pattern is push_warning/push_error, not assert** — inconsistent with codebase conventions

**Risk:** Medium — `assert()` terminates execution, which is inappropriate for recoverable conditions like missing Input Map actions.

**Effort:** Low (~1 hour: add 20-30 assert calls)

### Recommendation

→ **Approach A (Systematic @export + Startup + Unit Tests)** because:

1. **Additive and non-breaking** — existing configurations keep working. No refactoring needed.
2. **Consistent with existing patterns** — builds on `push_warning`/`push_error` and `@export` conventions already in the codebase.
3. **Appropriate granularity** — each validation is where it belongs (export bounds in the export declaration, startup checks in the entry script, method guards in the method body).
4. **Approach B (Validator utility)** is over-engineered — the codebase has 44 exports across 20 scripts; inline `@export_range` is the idiomatic Godot pattern and doesn't need wrapping.
5. **Approach C (assert)** is dangerous — hard crash on recoverable conditions is worse than the current silent-failure behavior.
6. **Low effort, high impact** — the ~2-3 hours covers all critical gaps (export bounds, Input Map, startup checks, empty-string guards, test coverage).

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Valid configuration at launch:** All required Input Map actions exist, all autoloads present, all @export values in valid range → game starts normally, no validation warnings.
2. **Valid configuration during gameplay:** NPCNode with non-empty `dialogue_file` and valid `dialogue_id` interacts correctly — dialogue loads, E-key triggers work.
3. **Valid state transitions:** `apply_choice()` with valid effect dictionary applies state changes correctly — no warnings.
4. **Valid scene transitions:** `trigger_scene_change()` with valid scene path loads the target scene — fade transition completes.
5. **Existing test suite passes:** All existing tests (25 test files) continue to pass after validation additions.

### Edge Cases

1. **@export at boundary values:** `walk_speed = 0.5` (min) and `10.0` (max) are accepted. `walk_speed = 0.49` (below min) is clamped to 0.5 by Godot. `walk_speed = 10.01` (above max) clamped to 10.0.
2. **Empty dialogue_file or dialogue_id:** NPCNode logs a `push_warning` in `_ready()`. Interaction via E-key or click silently no-ops. NPC can still display name label and prompt — degraded interaction mode.
3. **Missing Input Map action (single):** One action missing (e.g., `move_forward`). `_verify_input_map()` logs `push_warning`. `Input.get_vector()` returns `Vector2.ZERO` for forward/backward axis. Player can't walk forward — other directions still work.
4. **Missing Input Map action (all):** No movement actions registered. `_verify_input_map()` logs 4 warnings. Player can't move at all. Mouse look and E-key interaction still work.
5. **StateSystem autoload missing:** All `get_node_or_null("/root/StateSystem")` calls return null. Fallback values used (hope=5, conviction=5, will=5). `push_warning` logged once per call site per session.
6. **AudioManager bus index out of range:** `_set_bus_effect_enabled()` with invalid bus_idx returns silently (already handled by existing bounds check). No crash.
7. **Duplicate `_connect_dialogue_signals()` call:** If `_ready()` is called twice on PlayerController (re-entrance), `is_connected()` guard prevents double-connection. No duplicate events.
8. **Rapid scene transitions:** `transition_in_progress` flag prevents concurrent transitions. Second `trigger_scene_change()` call during active transition silently no-ops.
9. **Negative choice_index in select_choice:** Already guarded (`choice_index < 0` check on line 115). `push_error` logged, returns silently.
10. **State effect with missing keys:** `effect.get("key", default)` handles all missing keys. `apply_choice()` works with partial effect dictionaries.

### Failure Paths

1. **Input Map completely empty:** `_verify_input_map()` logs warnings for every required action. Player can't interact via keyboard. Mouse-click still works on Area3D triggers (degraded mode).
2. **Corrupt project.godot:** If `project.godot` input map section is malformed, Godot reports at startup. `InputMap.has_action()` works for whatever was loaded. Partial validation warnings.
3. **All autoloads removed:** Every `get_node_or_null()` returns null. Full degraded mode — state effects don't apply, dialogue conditions can't be evaluated, audio plays nothing. Each system logs its own warning.
4. **Dialogue file path doesn't exist:** `dialogue_runner.start()` returns false. `load_dialogue()` logs `push_error("Dialogue load failed")`. NPCNode receives `start() == false` (currently ignored — add check).
5. **Scene file doesn't exist for transition:** `change_scene_to_file("res://scenes/nonexistent.tscn")` returns `ERR_FILE_NOT_FOUND`. `push_error` logged. `transition_in_progress = false`. Player remains in current scene. Retry allowed.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Existing Input Map actions (project.godot) | ✅ Stable | Low — only adding validation, not changing actions |
| Existing @export declarations | ✅ Stable | Low — adding @export_range is backward-compatible |
| Existing test framework (run_tests.gd) | ✅ Stable | Low — adding new test methods |
| Existing main.gd entry point | ✅ Stable | Low — adding _verify_ methods |
| Existing push_warning/push_error conventions | ✅ Stable | Low — consistent pattern |

### Blocks

| Future Work | Priority |
|-------------|----------|
| CI pipeline that runs validation tests on push | P1 — without CI, validation is only developer-visible |
| Automated Input Map drift detection | P2 — periodic check that project.godot Input Map matches expected actions |
| Runtime error telemetry for gameplay testing | P3 — collect push_error/push_warning during playtest sessions |

### Preparation Needed

- [ ] **Audit all @export declarations** — Scan every `.gd` file for `@export var` and determine valid ranges per parameter
- [ ] **Define Input Map action canonical list** — Central reference of all required actions (for `_verify_input_map()`) in `main.gd` or a constants file
- [ ] **Confirm test runner supports new tests** — `run_tests.gd` handles list of test files; add `test_input_map_validation.gd` to the run list
- [ ] **Set up CI runner** — GitHub Action to run `godot --headless --script tests/run_tests.gd` on push (separate issue)

---

## 7. Spike / Experiment (Optional — depth/deep only)

*Not required — issue is depth/light.*

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The input validation and error handling system currently has **ad-hoc coverage across the entire project**. The relevant systems and their current state:

### Current State Summary

| System | Validation State | Key Files | Priority |
|--------|-----------------|-----------|----------|
| **Player Controller** | @exports lack range bounds. No Input Map guard. Signal connections lack `is_connected()` guard. | `player_controller.gd`, `project.godot` | P0 — movement is the most interactive system |
| **NPCNode** | @exports lack range bounds. `dialogue_file`/`dialogue_id` not validated for empty strings. | `npc_node.gd` | P0 — NPC interaction is entry point to narrative |
| **StateSystem** | `apply_choice()` uses `.get()` defaults but doesn't validate effect dict keys. `record_choice()` accepts empty strings. | `state_system.gd` | P1 — low failure impact |
| **SceneManager** | No path validation for `trigger_scene_change()`. Existing `push_error` on transition failure. No fallback. | `scene_manager.gd` | P1 — failure is user-visible |
| **SceneBase** | Null-safety via `get_node_or_null()`. No spawn point validation. | `scene_base.gd` | P1 — spawn at ZERO is edge case |
| **Boot/Startup** | No Input Map or autoload integrity check. Silent degradation on missing autoloads. | `main.gd` | P0 — catches misconfiguration early |
| **GameManager** | Axis name validation in `apply_slider_delta()` via match default. No Input Map validation. | `game_manager.gd` | P1 — match default handles unknown |
| **AudioManager** | Good validation — `_try_load()` with null-return, bus bounds check in `_set_bus_effect_enabled()`. | `audio_manager.gd` | P2 — already robust |
| **HemingwayEnforcer** | Excellent validation — null/Variant check, domain fallback with warning, CJK awareness. | `hemingway_enforcer.gd` | P2 — reference model |
| **UIConfig** | `is_instance_valid(viewport)` check. Size zero guard. | `ui_config.gd` | P2 — already robust |
| **Test Coverage** | 5 normal-path assertions only. Zero edge/failure tests. Not run in CI. | `test_input_map_validation.gd` | P0 — tests must be added |
| **EKeyTrigger** | Signal disconnect has `is_connected()` guard but connect does not. | `e_key_trigger.gd` | P1 — minor risk of double-connect |

### Codebase Conventions to Follow

- Use `@export_range(min, max, step)` for all numeric exports — Godot-native bounds enforcement
- Use `push_warning()` for recoverable conditions (missing action, empty string, null autoload)
- Use `push_error()` for programmer errors (missing node, corrupt data, impossible state)
- Use `is_connected()` before `connect()` on signal wiring in `_ready()` where re-entrance is possible
- Use `is_instance_valid()` before accessing cached node references after scene transitions
- Keep validation noise low — log at most once per condition per session (consider a `_warned_about: Dictionary = {}` pattern for noisy paths)

### Implementation Order (Dependency Chain)

1. **P0 — @export_range annotations** (all scripts): Quickest, no behavioral impact. Editor-only.
2. **P0 — main.gd startup checks** (`_verify_input_map()`, `_verify_autoloads()`): Detects misconfiguration early.
3. **P0 — PlayerController guards** (missing action check in `_ready()`): Most user-visible system.
4. **P0 — NPCNode empty-string guards** (`dialogue_file`, `dialogue_id`): Prevents silent no-ops.
5. **P1 — test_input_map_validation.gd expansion** (edge + failure tests): ~10 new test cases.
6. **P1 — SceneManager path validation**: Add `FileAccess.file_exists()` check before transition.
7. **P1 — EKeyTrigger is_connected() guard on connect**: Minor but consistent.
8. **P2 — StateSystem parameter validation**: Low-impact — existing `.get()` defaults already handle missing keys.

### Risks

- **@export_range only works in editor** — headless `--script` mode bypasses inspector clamping. Plan phase should note that runtime `clamp()` in setters is still needed for headless validation. **Correction for plan:** `@export_range` is editor-inspector only; runtime boundary enforcement still needs `clamp()` in the setter or the consuming method. This is already the pattern (StateSystem setters use `clamp()`). The PRD correctly frames @export_range as the first layer but the plan should ensure runtime guards exist.
- **No CI pipeline** — validation tests need a CI runner (GitHub Action) to be meaningful. The plan phase should add a `.github/workflows/` file or reference an existing one.
- **False positives from validation** — startup checks must not produce warnings for intentionally-missing configurations (e.g., headless tests that don't load project.godot). The `_verify_input_map()` and `_verify_autoloads()` methods should be idempotent and produce empty output in genuine headless scenarios.

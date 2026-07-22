# Tasks: #47 — GameState System

> Parent Issue: #47
> Priority: critical
> Estimated: 2–3 weeks
> Prerequisite: #43 (merged), #45 (merged), #46 (merged)
> Design Reference: `docs/DESIGN/47-gamestate-system.md`

---

## Task Breakdown

### Phase 1 — StateSystem Core (P0)

**Rationale:** The StateSystem extension is the foundation. Build and test the bipolar slider, flags, and choice history before wiring GameManager or save/load.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Add `hope_despair` bipolar slider (-10 to +10) with derived `hope`/`despair` read-only getters, clamping, and `get_state_id()` 5-state mapping | `gdscripts/state_system.gd` | None | 0.5d |
| T2 | Add `state_id_changed(state_id: int)` signal; modify `apply_choice()` to emit both signals; implement signal-optimised state ID comparison (only emit state_id_changed on transition) | `gdscripts/state_system.gd` | T1 | 0.5d |
| T3 | Implement `set_flag()`, `has_flag()`, `get_flags()` API with Dictionary storage | `gdscripts/state_system.gd` | None | 0.25d |
| T4 | Implement `record_choice()`, `get_choice_history()`, `get_choice_count()` with 200-entry cap | `gdscripts/state_system.gd` | None | 0.25d |

**Validation:** Unit tests TC1–TC19 pass in headless test runner.

#### T1 Details — Bipolar Slider

- Add `var hope_despair: float = 0.0` with setter clamping to `[-10.0, 10.0]`
- Make `var hope: float` a read-only getter: `return (hope_despair + 10.0) / 2.0`
- Make `var despair: float` a read-only getter: `return 10.0 - hope`
- Add `func get_state_id() -> int` with the 5-state mapping table
- Modify `apply_choice()` to dispatch `"hope_despair"` key to `hope_despair` and clamp
- Maintain existing `"hope"` key for backward compat (convert 0–10 delta to hope_despair delta)

**Validation:** TC1–TC7 pass.

#### T2 Details — Signal Enhancement

- Add `signal state_id_changed(state_id: int)`
- In `apply_choice()`, compute `var old_state_id = get_state_id()` before mutation
- After mutation, compute `var new_state_id = get_state_id()`
- Always emit `state_changed.emit(get_state())`
- Only emit `if old_state_id != new_state_id: state_id_changed.emit(new_state_id)`

**Validation:** TC8–TC12 pass.

#### T3 Details — Flags

- Add `var _flags: Dictionary = {}`
- `set_flag(name, value)`: `_flags[name] = value`
- `has_flag(name)`: `return _flags.get(name, false) == true`
- `get_flags()`: `return _flags.duplicate()`

**Validation:** TC13–TC16 pass.

#### T4 Details — Choice History

- Add `var _choice_history: Array[Dictionary] = []`
- `record_choice(node_id, choice_index, choice_text)`: Append record with `Time.get_ticks_msec()`. If `_choice_history.size() > 200`, `_choice_history.pop_front()`
- `get_choice_history()`: `return _choice_history.duplicate()`
- `get_choice_count()`: `return _choice_history.size()`

**Validation:** TC17–TC19 pass.

---

### Phase 2 — Save/Load & GameManager Wiring (P0)

**Rationale:** Save/load is a testing dependency for Phase 3. GameManager delegation must work before dialogue conditions evaluate correctly.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T5 | Implement `_to_save_dict()`, `_from_save_dict()`, `save_state_to_file(path)`, `load_state_from_file(path)` with version validation | `gdscripts/state_system.gd` | T1, T2, T3, T4 | 1.0d |
| T6 | Update `GameManager.set_flag()`, `has_flag()`, `get_flags()` to delegate to StateSystem; remove local `_flags` field | `gdscripts/game_manager.gd` | T3 | 0.25d |
| T7 | Test save/load round-trip: save state → modify → load → verify all values match | `gdscripts/state_system.gd` | T5 | 0.25d |

**Validation:** TC20–TC29 pass.

#### T5 Details — Serialization

- `_to_save_dict()` returns `{version: 1, hope_despair, conviction, will, flags, choice_history}`
- `_from_save_dict(data)`: validate `version`, set all fields, replace `_choice_history`
- `save_state_to_file(path)`: use `FileAccess.open()`, `store_string(JSON.stringify(save_dict))`, return `true`/`false`
- `load_state_from_file(path)`: use `FileAccess.open()`, parse JSON, validate version, call `_from_save_dict()`, emit `state_changed`
- Error paths: missing file → `false`, corrupt JSON → `false`, version mismatch → `false`

**Validation:** TC20–TC23 pass.

#### T6 Details — GameManager Refactor

- Remove `var _flags: Dictionary = {}`
- Change `set_flag()` to `_state_system.set_flag(flag_name, value)`
- Change `has_flag()` to `return _state_system.has_flag(flag_name)`
- Change `get_flags()` to `return _state_system.get_flags()`

**Validation:** TC27–TC29 pass.

---

### Phase 3 — Legacy Deprecation & Autoload Order (P0)

**Rationale:** Legacy GameState must continue working during migration. Autoload order prevents runtime lookup failures.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T8 | Add delegation methods to legacy GameState: `apply_state()` maps 0–100 to -10..+10, `get_state()` returns mapped values from StateSystem; add `push_warning` deprecation notice | `gdscripts/game_state.gd` | T1 | 0.25d |
| T9 | Reorder `[autoload]` in `project.godot` so StateSystem appears first | `project.godot` | T1 | 0.1d |
| T10 | Run full regression test suite — verify all existing tests still pass | `tests/` | T1–T9 | 0.5d |

**Validation:** TC30–TC31 pass; all pre-existing tests pass.

#### T8 Details — Legacy Deprecation

```gdscript
# In game_state.gd _ready():
push_warning("GameState is deprecated. Use /root/StateSystem instead.")

# Modified apply_state():
func apply_state(delta_hope: float, delta_despair: float) -> void:
    var ss = get_node("/root/StateSystem")
    var hope_delta = (delta_hope - delta_despair) / 10.0  # 0–100 → -10..+10
    ss.apply_choice({"hope_despair": hope_delta})

# Modified get_state():
func get_state() -> Dictionary:
    var ss = get_node("/root/StateSystem")
    return ss.get_state()
```

#### T9 Details — Autoload Order

Change `project.godot` `[autoload]` section to:

```
[autoload]
StateSystem="*res://gdscripts/state_system.gd"
GameManager="*res://gdscripts/game_manager.gd"
NarrativeManager="*res://gdscripts/narrative_manager.gd"
AudioManager="*res://gdscripts/audio_manager.gd"
GameState="*res://gdscripts/game_state.gd"
```

---

### Phase 4 — Tests (P0)

**Rationale:** All three ACs require test coverage. The test file updates are blocking.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T11 | Add unit tests for StateSystem slider (TC1–TC7) | `tests/test_game_state.gd` | T1 | 0.5d |
| T12 | Add unit tests for signal emission (TC8–TC12) | `tests/test_game_state.gd` | T2 | 0.5d |
| T13 | Add unit tests for flags (TC13–TC16) | `tests/test_game_state.gd` | T3 | 0.25d |
| T14 | Add unit tests for choice history (TC17–TC19) | `tests/test_game_state.gd` | T4 | 0.25d |
| T15 | Add unit tests for save/load (TC20–TC23) | `tests/test_game_state.gd` | T5 | 0.5d |
| T16 | Add unit tests for derived values (TC24–TC26) | `tests/test_game_state.gd` | T1 | 0.25d |
| T17 | Add integration tests for GameManager delegation (TC27–TC29) | `tests/test_game_state.gd` | T6 | 0.25d |
| T18 | Add integration tests for legacy deprecation (TC30–TC31) | `tests/test_game_state.gd` | T8 | 0.25d |
| T19 | Register new test methods in `tests/run_tests.gd` | `tests/run_tests.gd` | T11–T18 | 0.1d |

**Validation:** All 31 test cases pass in Godot headless test runner. Total test count increased by ~31.

---

## Dependency Graph

```
Phase 1 — StateSystem Core ────────────────────────────────────
├─ T1 (bipolar slider + derived values) ───┬─────────────────┐
├─ T2 (signals)                  ←── T1 ───┤                 │
├─ T3 (flags)                   ←──────────┼───┐             │
└─ T4 (choice history)          ←──────────┼───┼───┐         │
                                          │   │   │         │
Phase 2 — Save/Load & GM Wiring ──────────┤   │   │         │
├─ T5 (save/load)               ←── T1–T4 ───┘   │         │
├─ T6 (GameManager delegation)  ←── T3 ───────────┘         │
└─ T7 (round-trip test)         ←── T5 ─────────────────────┤
                                                             │
Phase 3 — Legacy & Autoload ─────────────────────────────────┤
├─ T8 (GameState deprecation)   ←── T1 ──────────────────────┤
├─ T9 (autoload order)          ←── T1 ──────────────────────┤
└─ T10 (regression)             ←── T1–T9 ───────────────────┤
                                                             │
Phase 4 — Tests ──────────────────────────────────────────────┤
├─ T11 (slider tests)           ←── T1                       │
├─ T12 (signal tests)           ←── T2                       │
├─ T13 (flag tests)             ←── T3                       │
├─ T14 (history tests)          ←── T4                       │
├─ T15 (save/load tests)        ←── T5                       │
├─ T16 (derived value tests)    ←── T1                       │
├─ T17 (GM delegation tests)    ←── T6                       │
├─ T18 (deprecation tests)      ←── T8                       │
└─ T19 (register in runner)     ←── T11–T18 ─────────────────┘
                                                             │
All Done ──────────────────────────────────────────────────────┘
```

---

## Summary: Changed Files

| File | Change Type | Est. Lines |
|------|-------------|-----------|
| `gdscripts/state_system.gd` | Modify — add bipolar slider, signals, flags, choice history, save/load | +120 lines |
| `gdscripts/game_manager.gd` | Modify — delegate flag methods to StateSystem | +5 / -10 lines |
| `gdscripts/game_state.gd` | Modify — add delegation methods, deprecation warning | +15 lines |
| `project.godot` | Modify — reorder autoload section | ±1 line |
| `tests/test_game_state.gd` | Modify — add ~31 new test cases | +400 lines |
| `tests/run_tests.gd` | Modify — register new test suite | +2 lines |

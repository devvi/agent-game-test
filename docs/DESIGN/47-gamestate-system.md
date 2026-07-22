# Design: #47 — GameState System

> Parent Issue: #47
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Consolidate all game state into a single authoritative **StateSystem autoload** (`/root/StateSystem`) by extending the existing `state_system.gd`. Add a bipolar **hope/despair slider** (-10 to +10) with 5 discrete state IDs, a **flags system** (10+ boolean flags), **choice history** tracking, and **save/load serialization**. Wire `GameManager` as a thin delegation facade. Deprecate the legacy `GameState` autoload in-place.

**Design principles:**
1. **Single source of truth** — Every state query routes through `StateSystem`. No synchronization risk between multiple state files.
2. **Incremental migration** — Legacy `GameState` stays as a compatibility shim during migration; no sudden breakage of existing code.
3. **Signal-driven downstream updates** — `state_changed` and `state_id_changed` signals propagate state mutations to all consumers (WorldviewController, NarrativeManager, RainController, AudioManager, SceneBase).
4. **Self-contained serialization** — State exports/imports as a single JSON dictionary. Save/load is a round-trip-safe operation for testing and checkpointing.

### Data Flow

```
Dialogue choice made
    │
    ├──► DialogueRunner.select_choice()
    │       └──► _apply_effects() → calls GameManager.apply_slider_delta()
    │               └──► GameManager (wired) → StateSystem.apply_choice()
    │                       ├── Updates hope_despair, conviction, will
    │                       ├── Clamps all values to valid ranges
    │                       ├── Calculates new state_id (1–5)
    │                       ├── Records choice to _choice_history
    │                       ├── Emits state_changed(state: Dictionary)
    │                       └── If state_id changed: emits state_id_changed(state_id: int)
    │
    ├──► WorldviewController receives state_changed
    │       └──→ world_text_changed.emit(tone)
    │       └──→ world_state_changed.emit(state_id)
    │
    ├──► NarrativeManager receives state_changed
    │       └──→ _calculate_tone_for_scene() → scene_text_changed.emit()
    │
    ├──► RainController receives state_changed
    │       └──→ Updates rain intensity from hope (inverse)
    │
    ├──► AudioManager receives state_changed
    │       └──→ Modulates rain volume/pitch, distortion effect
    │
    └──► Next dialogue encounter
            └──→ DialogueRunner._build_state_snapshot()
                    └──→ GameManager.get_slider("hope_despair") → REAL value
                    └──→ GameManager.get_flags() → REAL flags dict
                    └──→ Condition evaluator gates choices with real data

Save/Load flow:
    StateSystem.save_state_to_file(path)
        └──→ Serializes: hope_despair, conviction, will, flags, choice_history
        └──→ Writes JSON to user://path
    StateSystem.load_state_from_file(path)
        └──→ Reads JSON, validates version field
        └──→ Restores all state values
        └──→ Emits state_changed once after full restore
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where to add features | **Extend existing `state_system.gd`** (Approach A) | Single source of truth; minimal new code; existing signal wiring continues to work; backward compatible |
| Bipolar slider design | `hope_despair: float` (-10 to +10) with `hope` derived via `(hope_despair + 10.0) / 2.0` | Backward compatible with existing `hope` 0–10 API; dialogue engine receives the new axis |
| State enumeration | `get_state_id() → int` (1–5) with inclusive upper bounds per state | Matches Issue #50 5-state design; both WorldviewController and NarrativeManager derive from same function |
| Flag storage | Dictionary-based `_flags: Dictionary` with no pre-registration | Simplest API; creates keys on demand; supports 20+ flags with no schema changes |
| Choice history cap | Array capped at 200 entries (oldest dropped) | Prevents unbounded memory growth; 200 choices is generous for a single play session |
| Autoload order | `StateSystem` → `GameManager` → `NarrativeManager` → `AudioManager` | StateSystem must be ready before GameManager delegates to it; NarrativeManager queries state at `_ready()` |
| Save file path | `user://save_states/` with `.json` extension | Godot's `user://` is platform-agnostic; `.json` is human-readable for debugging |
| Serialization format | Versioned JSON (`"version": 1`) | Enables forward migration if schema evolves |
| Legacy GameState | Deprecated in-place — delegate internally, emit push_warning once per session | Existing `get_node("/root/GameState")` references continue to work; removal deferred to follow-up issue |
| Mid-dialogue state change deferral | NOT in this issue's scope — Issue #50's queuing pattern is a separate concern | This issue focuses on the state foundation; visual deferral belongs in Issue #50 |

---

## 2. StateSystem Class API Specification

### `gdscripts/state_system.gd` — Extend Existing

The existing `state_system.gd` (~45 lines, tri-axis hope/conviction/will 0–10) is extended to become the authoritative GameState autoload.

#### New Exports and Properties

```gdscript
extends Node
class_name StateSystem

# ── Signals ──

signal state_changed(state: Dictionary)
## Emitted on every apply_choice() / load_state_from_file() call.
## state dict contains: hope_despair, hope, despair, conviction, will, state_id, flags, choice_count

signal state_id_changed(state_id: int)
## Emitted ONLY when the discrete state ID changes (not on every slider tick).
## state_id: int (1–5)

# ── Bipolar Slider ──

var hope_despair: float = 0.0
## Primary slider axis. Range [-10.0, +10.0]. Initialized to 0.0 (Neutral, state ID 3).

var hope: float = 5.0 :
    get:
        return (hope_despair + 10.0) / 2.0
## Derived read-only value. Maps bipolar -10..+10 to unipolar 0..10.
## Backward compatible — existing consumers reading `hope` get correct values.

var despair: float = 5.0 :
    get:
        return 10.0 - hope
## Derived read-only value. Mirror of hope in 0–10 scale.
## Backward compatible for consumers that read `despair`.

# ── Tri-axis (Existing, Unchanged) ──

var conviction: float = 5.0      # 0–10, 5 = neutral
var will: float = 5.0            # 0–10, 5 = neutral

# ── Flags ──

var _flags: Dictionary = {}
## Internal flag storage. Keys: String flag names. Values: bool.
## No pre-registration required — set_flag() creates keys on demand.

# ── Choice History ──

var _choice_history: Array[Dictionary] = []
## Array of choice records. Max 200 entries.
## Each record: {node_id: String, choice_index: int, choice_text: String, timestamp: int}
```

#### New and Modified Methods

```gdscript
# ── Modified: apply_choice ──

## Apply a dictionary of effects to game state.
## Accepted keys: "hope_despair" (float, delta), "conviction" (float, delta), "will" (float, delta)
## Clamps all values to legal ranges after applying deltas.
## Computes new state_id and emits state_changed + (if changed) state_id_changed.
## Records the choice to choice_history if node_id and choice_index are provided.
func apply_choice(effect: Dictionary) -> void

# ── New: State ID ──

## Return the discrete state ID (1–5) for the current hope_despair value.
## 1=Despair [-10.0, -6.0], 2=Low (-6.0, -2.0], 3=Neutral (-2.0, +2.0],
## 4=Buoyant (+2.0, +6.0], 5=Hope (+6.0, +10.0]
## Upper bound inclusive (<=).
func get_state_id() -> int

# ── New: Flags API ──

## Set a boolean flag. Creates the flag key if it doesn't exist.
func set_flag(name: String, value: bool) -> void

## Check if a named flag is set (true). Returns false for unset flags.
func has_flag(name: String) -> bool

## Get all flags as a Dictionary copy.
func get_flags() -> Dictionary

# ── New: Choice History API ──

## Record a dialogue choice in history. Caps at 200 entries (oldest dropped).
func record_choice(node_id: String, choice_index: int, choice_text: String) -> void

## Get a copy of the full choice history array.
func get_choice_history() -> Array[Dictionary]

## Get the number of choices made this session.
func get_choice_count() -> int

# ── New: Save/Load ──

## Serialize all game state to a JSON file at the given path.
## Returns true on success, false on failure.
## Creates parent directories automatically.
func save_state_to_file(path: String) -> bool

## Deserialize game state from a JSON file.
## Validates version field (must match current version).
## Returns true on success, false on failure (file not found, corrupt JSON, version mismatch).
## Emits a single state_changed after full restore.
func load_state_from_file(path: String) -> bool

# ── Helper (Private) ──

## Convert current state to a serializable Dictionary.
func _to_save_dict() -> Dictionary

## Restore state from a Dictionary returned by _to_save_dict().
## Resets all internal state values and replaces choice_history.
func _from_save_dict(data: Dictionary) -> void

## Calculate state_id from hope_despair value using the 5-state mapping.
func _calculate_state_id(value: float) -> int

## Get axis value by string name (for GameManager delegation).
func _get_axis_value(axis: String) -> float
```

### State ID Mapping

| State ID | Name | Slider Range (hope_despair) | Derived hope (0–10) | Tone |
|----------|------|-----------------------------|---------------------|------|
| 1 | Despair | [-10.0, -6.0] | 0.0–2.0 | Deepest despair |
| 2 | Low | (-6.0, -2.0] | 2.0–4.0 | Negative but not hopeless |
| 3 | Neutral | (-2.0, +2.0] | 4.0–6.0 | Baseline — flat affect |
| 4 | Buoyant | (+2.0, +6.0] | 6.0–8.0 | Positive outlook, warm |
| 5 | Hope | (+6.0, +10.0] | 8.0–10.0 | Boundless hope |

**Boundary rule:** Upper bound inclusive (`<=`). Each state spans 4.0 units of the 20-unit range.

---

## 3. Flag System Design

### API Surface

| Method | Signature | Description |
|--------|-----------|-------------|
| `set_flag` | `func set_flag(name: String, value: bool) -> void` | Creates or updates a flag entry |
| `has_flag` | `func has_flag(name: String) -> bool` | Returns `true` only if flag is set to `true`; unset flags return `false` |
| `get_flags` | `func get_flags() -> Dictionary` | Returns a shallow copy of all flags |

### Design Decisions

- **No pre-registration required** — Dialogue authors can set any string flag name. Unset flags evaluate to `false` in conditions.
- **No reserved name filtering** — While `"version"` and `"state_id"` could collide with serialization keys, the save/load uses a separate save dict structure where flags are nested under a `"flags"` key, so no collision occurs.
- **Capacity** — Supports at least 20 simultaneous flags. Internal storage is a GDScript Dictionary with no theoretical limit beyond available memory.
- **Persistence** — Flags are included in save/load serialization under the `"flags"` key.
- **Lifetime** — Flags persist for the entire game session. They are reset only on `load_state_from_file()` or a new game start.

### Usage from Dialogue JSON

```json
{
  "condition": {
    "type": "flag",
    "flag": "met_stranger",
    "value": true
  }
}
```

`GameManager.has_flag("met_stranger")` → delegates to `StateSystem.has_flag("met_stranger")` → returns `true` if previously set.

---

## 4. Choice History Data Model

### Record Structure

```json
{
  "node_id": "n_01",
  "choice_index": 0,
  "choice_text": "I'll wait.",
  "timestamp": 123456
}
```

| Field | Type | Description |
|-------|------|-------------|
| `node_id` | String | The dialogue node ID where the choice was made |
| `choice_index` | int | The index of the selected choice (0-based) |
| `choice_text` | String | The full text of the selected choice |
| `timestamp` | int | Godot `Time.get_ticks_msec()` at the moment of recording |

### Storage

- Array stored in `_choice_history: Array[Dictionary]`
- Max 200 entries — oldest entries are dropped when the cap is reached
- Ordered chronologically (newest appended at the end)
- Reset on `load_state_from_file()` or new game
- `record_choice()` is called by `GameManager` after `StateSystem.apply_choice()` completes

### API

| Method | Signature | Description |
|--------|-----------|-------------|
| `record_choice` | `func record_choice(node_id: String, choice_index: int, choice_text: String) -> void` | Append a choice record; trim oldest if > 200 |
| `get_choice_history` | `func get_choice_history() -> Array[Dictionary]` | Return a deep copy of all records |
| `get_choice_count` | `func get_choice_count() -> int` | Return the current count of recorded choices |

---

## 5. Save/Load Serialization Format

### JSON Schema

```json
{
  "version": 1,
  "hope_despair": 0.0,
  "conviction": 5.0,
  "will": 5.0,
  "flags": {
    "met_stranger": true,
    "bought_coffee": false
  },
  "choice_history": [
    {
      "node_id": "n_01",
      "choice_index": 0,
      "choice_text": "I'll wait.",
      "timestamp": 123456
    }
  ]
}
```

| Field | Type | Range | Notes |
|-------|------|-------|-------|
| `version` | int | 1 | Schema version for forward migration |
| `hope_despair` | float | -10.0 to +10.0 | Bipolar slider value |
| `conviction` | float | 0.0 to 10.0 | Tri-axis value |
| `will` | float | 0.0 to 10.0 | Tri-axis value |
| `flags` | object | String→bool | Arbitrary flag key-value pairs |
| `choice_history` | array | 0–200 entries | Ordered choice records |

### API Contract

```gdscript
## Save current state to a JSON file.
## Returns true on success.
## Creates parent directories if they don't exist.
## On any file I/O error, returns false and prints push_warning.
func save_state_to_file(path: String) -> bool

## Load state from a JSON file.
## Returns true on success, false on failure.
## Failure scenarios:
##   - File doesn't exist → false + push_warning
##   - Corrupt JSON (parse error) → false + push_warning
##   - Version mismatch → false + push_warning
## On success, emits a single state_changed after full restore.
func load_state_from_file(path: String) -> bool
```

### File Path Convention

- Default save path: `user://save_states/gamestate_<timestamp>.json`
- Test path: `user://test_save.json` (overwritten on each save round)

---

## 6. GameManager Delegation Table

GameManager (`gdscripts/game_manager.gd`) is already partially wired. The following table shows the complete delegation contract:

| GameManager Method | Delegates To | Status |
|--------------------|-------------|--------|
| `get_slider(axis: String) → float` | `StateSystem._get_axis_value(axis)` | ✅ Already wired |
| `apply_slider_delta(axis: String, delta: float)` | `StateSystem.apply_choice({axis: delta})` | ✅ Already wired |
| `set_flag(name: String, value: bool)` | `StateSystem.set_flag(name, value)` | **Needs update** — currently stores in `_flags` locally; must sync with StateSystem |
| `has_flag(name: String) → bool` | `StateSystem.has_flag(name)` | **Needs update** — currently reads local `_flags` |
| `get_flags() → Dictionary` | `StateSystem.get_flags()` | **Needs update** — currently returns local `_flags` duplicate |
| `save_choices(choices: Array)` | `StateSystem._choice_history` | **Needs update** — currently stores locally |

**Change required in GameManager:** Replace local `_flags` and `choices_history` storage with delegation to StateSystem. Remove the local `_flags: Dictionary` field and the `choices_history: Array` field. All four flag methods and the choice persistence method should delegate exclusively to `/root/StateSystem`.

---

## 7. Autoload Initialization Order

### Current Autoload Registration (`project.godot`)

```
[autoload]
GameManager="*res://gdscripts/game_manager.gd"
GameState="*res://gdscripts/game_state.gd"
StateSystem="*res://gdscripts/state_system.gd"
NarrativeManager="*res://gdscripts/narrative_manager.gd"
AudioManager="*res://gdscripts/audio_manager.gd"
```

### Required Order for #47

| Priority | Autoload | Rationale |
|----------|----------|-----------|
| 1 | **StateSystem** `"*res://gdscripts/state_system.gd"` | Must be ready first — GameManager delegates to it at `_ready()` |
| 2 | **GameManager** `"*res://gdscripts/game_manager.gd"` | Needs `/root/StateSystem` to be available for reactive `_state_system` resolution |
| 3 | **NarrativeManager** `"*res://gdscripts/narrative_manager.gd"` | Queries state at initialization |
| 4 | **AudioManager** `"*res://gdscripts/audio_manager.gd"` | Listens to state_changed for audio modulation |
| 5 | **GameState** (legacy) `"*res://gdscripts/game_state.gd"` | Keep at lowest priority; only used for backward compat during migration |

**Action:** Reorder the `[autoload]` section so `StateSystem` appears first. `GameManager`'s delegation methods already use lazy `get_node_or_null("/root/StateSystem")` as a safety net, so if the order is missed, it degrades gracefully (returns 5.0 fallback).

---

## 8. Migration Plan (Legacy GameState)

### Phase 1 — This Issue (#47)

1. **Extend `state_system.gd`** — Add bipolar slider, flags, choice history, save/load. Register as autoload (already registered).
2. **Wire `GameManager`** — Replace local flag/choice storage with StateSystem delegation.
3. **Keep `GameState` autoload** — Add `push_warning` deprecation notice in `_ready()`. Delegate `apply_state()` and `get_state()` to StateSystem with range conversion (hope 0–100 → -10 to +10).
4. **Reorder autoloads** — `StateSystem` first.

### Phase 2 — After Issue #47 (Follow-up)

1. **Update all `get_node("/root/GameState")` references** in scene scripts to use `/root/StateSystem`.
2. **Update `tests/test_game_state.gd`** to test StateSystem API instead.
3. **Remove `GameState` from autoload** and delete `gdscripts/game_state.gd`.

### Backward Compatibility

| Existing Reference | Works in #47? | Notes |
|--------------------|---------------|-------|
| `get_node("/root/GameState").get_state()` | ✅ Yes | Delegates to StateSystem, returns mapped values |
| `get_node("/root/GameState").apply_state(20, -10)` | ✅ Yes | Converts 0–100 range to -10..+10 |
| `get_node("/root/StateSystem").hope` | ✅ Yes | Derived from hope_despair (still returns 0–10) |
| `get_node("/root/StateSystem").get_state()` | ✅ Yes | Returns tri-axis dict |
| `state_changed` signal connections | ✅ Yes | Signature unchanged |

---

## 9. Test Case Descriptions

> Note: These are test case *descriptions* only. No runnable GDScript test files are to be written during the Plan phase.

### TC1–TC7: Slider & State ID (AC1 Coverage)

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC1 | hope_despair initializes to 0.0 | Create new StateSystem | `hope_despair == 0.0`, state_id == 3 (Neutral) |
| TC2 | hope_despair clamped to range [-10, +10] | Apply +20 delta from 0.0 | `hope_despair == 10.0`; apply -25 delta → `hope_despair == -10.0` |
| TC3 | state_id returns correct value for each state | Set hope_despair to -10, -6, 0, +6, +10 | Returns 1, 1, 3, 5, 5 respectively |
| TC4 | state_id boundary: -6.0 → State 1 (Despair) | Set hope_despair = -6.0 | `get_state_id() == 1` (inclusive upper bound) |
| TC5 | state_id boundary: -2.0 → State 2 (Low) | Set hope_despair = -2.0 | `get_state_id() == 2` |
| TC6 | state_id boundary: +2.0 → State 3 (Neutral) | Set hope_despair = 2.0 | `get_state_id() == 3` |
| TC7 | state_id boundary: +6.0 → State 4 (Buoyant) | Set hope_despair = 6.0 | `get_state_id() == 4` |

### TC8–TC12: Signal Emission

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC8 | `state_changed` fires on every apply_choice() | Connect to signal, apply delta | Signal fires once per apply_choice call |
| TC9 | `state_changed` passes correct state dict | Connect to signal, inspect payload | Dict contains: hope_despair, hope, conviction, will, state_id, flags, choice_count |
| TC10 | `state_id_changed` fires on state transition | Move hope_despair from 0→3 | Fires with state_id=4 |
| TC11 | `state_id_changed` does NOT fire on intra-state change | Move hope_despair from 0→1 (still Neutral) | Does NOT fire |
| TC12 | `state_changed` fires once after load_state_from_file | Save state, modify, load | Single emission with restored state |

### TC13–TC16: Flags System (AC3 Coverage)

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC13 | set_flag creates and stores a flag | `set_flag("test_flag", true)` | `has_flag("test_flag") == true` |
| TC14 | has_flag returns false for unset flags | Query an unset flag | Returns `false` |
| TC15 | get_flags returns all flags | Set 3 flags, query | Returns dict with 3 entries |
| TC16 | Flags persist through save/load | Set flag, save, load new instance | Flag is restored |

### TC17–TC19: Choice History

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC17 | record_choice appends to history | Record 3 choices | `get_choice_count() == 3`, array has 3 entries |
| TC18 | Choice history caps at 200 entries | Record 210 choices | `get_choice_count() == 200`, oldest entries dropped |
| TC19 | Choice history round-trip via save/load | Record 3 choices, save, load | All 3 records match original |

### TC20–TC23: Save/Load (AC2 Coverage)

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC20 | Save state to valid path | Modify all sliders, set flags, record choices, save | Returns `true`, file exists |
| TC21 | Load state restores all values | Save, modify values, load | hope_despair, conviction, will, flags, choice_history all match saved state |
| TC22 | Load from missing file returns false | `load_state_from_file("nonexistent.json")` | Returns `false`, push_warning printed |
| TC23 | Load from corrupt JSON returns false | Write malformed JSON, try load | Returns `false`, state unchanged |

### TC24–TC26: Derived Values

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC24 | hope is derived from hope_despair | hope_despair = 0.0 | `hope == 5.0` |
| TC25 | hope = 0.0 when hope_despair = -10.0 | hope_despair = -10.0 | `hope == 0.0` |
| TC26 | hope = 10.0 when hope_despair = +10.0 | hope_despair = 10.0 | `hope == 10.0` |

### TC27–TC29: GameManager Delegation

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC27 | GameManager.get_slider retrieves hope_despair | Set StateSystem.hope_despair = 3.0 via StateSystem | `GameManager.get_slider("hope_despair") == 3.0` |
| TC28 | GameManager.apply_slider_delta delegates correctly | Call `apply_slider_delta("hope_despair", 2.0)` | StateSystem.hope_despair increased by 2.0 |
| TC29 | GameManager flag methods delegate to StateSystem | `set_flag()` on GameManager | Same flag readable via StateSystem.has_flag() |

### TC30–TC31: Deprecation / Migration

| ID | Description | Setup | Expected Result |
|----|-------------|-------|-----------------|
| TC30 | Legacy GameState.get_state() delegates | Call GameState.get_state() | Returns values matching StateSystem |
| TC31 | Legacy GameState.apply_state() converts ranges | `apply_state(20, 0)` (0–100 range) | StateSystem.hope_despair changes by appropriate amount |

---

## 10. Files Changed

### Modified Files

| File | Change | Est. Lines | Priority |
|------|--------|-----------|----------|
| `gdscripts/state_system.gd` | Add hope_despair slider, get_state_id(), flags API, choice history, save/load, state_id_changed signal, derived hope/despair | +120 lines | P0 |
| `gdscripts/game_manager.gd` | Replace local _flags and choices_history with StateSystem delegation | +5 / -10 lines | P0 |
| `project.godot` | Reorder [autoload] — StateSystem first | ±1 line | P0 |
| `gdscripts/game_state.gd` | Add delegate methods to StateSystem, range conversion, deprecation warning | +15 lines | P0 |

### New Files

None. All changes are modifications to existing files.

### Unchanged (audited, no changes needed)

| File | Reason |
|------|--------|
| `gdscripts/constants.gd` | Constants for state IDs can live within StateSystem |
| `gdscripts/dialogue_runner.gd` | Already queries GameManager; GameManager will return real data |
| `gdscripts/scene_base.gd` | Reads from WorldviewController, which listens to StateSystem signals |
| `gdscripts/worldview_controller.gd` | Already listens to `state_changed` signal — no code change needed for #47 |
| `gdscripts/narrative_manager.gd` | Already listens to `state_changed` signal — no change for state foundation |
| `gdscripts/rain_controller.gd` | Already listens to `state_changed` signal |
| `gdscripts/audio_manager.gd` | Already listens to `state_changed` signal |
| `dialogues/*.json` | Condition updates belong to Issue #56 (Story Content) |
| `tests/run_tests.gd` | Test runner update belongs to Implementation phase, not Plan |

---

## 11. Verification Checklist

- [ ] AC1: `StateSystem.hope_despair` initializes to `0.0` (Neutral, state ID 3)
- [ ] AC1: `StateSystem.hope_despair` clamped to `[-10.0, +10.0]` on every `apply_choice()`
- [ ] AC1: `state_changed(state: Dictionary)` fires on every `apply_choice()` call
- [ ] AC1: `state_id_changed(state_id: int)` fires ONLY when discrete state ID changes
- [ ] AC1: 5 discrete states map correctly with inclusive upper bounds
- [ ] AC2: `save_state_to_file()` serializes all state to JSON, returns `true`/`false`
- [ ] AC2: `load_state_from_file()` restores exact state, emits `state_changed` once
- [ ] AC2: Load from missing/corrupt file returns `false` without crashing
- [ ] AC3: `set_flag()` creates and updates boolean flags
- [ ] AC3: `has_flag()` returns `false` for unset flags
- [ ] AC3: `get_flags()` returns all flags as a Dictionary
- [ ] AC3: Supports at least 20 simultaneous flags
- [ ] GameManager `set_flag`, `has_flag`, `get_flags` delegate to StateSystem
- [ ] Legacy GameState delegates to StateSystem with range conversion
- [ ] Autoload order: StateSystem listed first in `project.godot`
- [ ] Choice history capped at 200 entries, oldest dropped
- [ ] All existing pre-existing tests still pass

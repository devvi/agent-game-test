# Research: [Feature] GameState System — Unified State Manager for CRPG

> Parent Issue: #47
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project has **three overlapping state systems** plus a **stub GameManager**, creating fragmentation, ambiguity, and maintenance risk:

| System | File | Values | Range | Autoload? | Role |
|--------|------|--------|-------|-----------|------|
| `GameState` | `game_state.gd` | `hope`, `despair` | 0–100 each | ✅ Yes (legacy) | Prints on init, basic `apply_state()` / `reset()` |
| `StateSystem` | `state_system.gd` | `hope`, `conviction`, `will` | 0–10 each, 5=neutral | ❌ No | Tri-axis state, `apply_choice()`, `get_state_tier()`, `state_changed` signal |
| `GameManager` | `game_manager.gd` | stub `get_slider()`, `apply_slider_delta()`, `set_flag()` | Returns `5.0` / `pass` / `false` | ✅ Yes | Intended facade for dialogue engine — NOT wired to StateSystem |
| `constants.gd` | `constants.gd` | Threshold constants, ending thresholds | Various | N/A | Static constants, no runtime state |

**Key problems with the current fragmented landscape:**

1. **Dual authoritative sources** — `GameState` (legacy autoload) and `StateSystem` (standalone Node) both manage "hope" but use different ranges (0–100 vs 0–10) and different APIs (`apply_state(delta_hope, delta_despair)` vs `apply_choice({hope: float})`). Any system that reads state must know which file to query.

2. **GameManager is still a stub** — `get_slider()` returns `5.0` for every axis. `apply_slider_delta()`, `set_flag()`, and `get_flags()` are `pass` / `false` stubs. The dialogue engine's `_build_state_snapshot()` queries GameManager for sliders but gets all `5.0`. This means **all authored dialogue conditions that reference sliders are effectively dead code**.

3. **StateSystem is NOT an autoload** — `NarrativeManager`, `WorldviewController`, `RainController`, and `AudioManager` all locate it at runtime via `get_node_or_null("/root/StateSystem")`. If the scene tree restructures or the order changes, these lookups fail silently. The StateSystem must persist across all scene changes to be a reliable state authority.

4. **No flags system exists** — `GameManager.has_flag()` always returns `false`. `GameManager.set_flag()` is a no-op. `GameManager.get_flags()` returns `{}`. Dialogue conditions of type `"flag"` can never evaluate to true.

5. **No choice history tracking at state level** — `GameManager.choices_history` is maintained via `save_choices()`/`restore_choices()` but this is a scene-transition persistence mechanism, not a unified state-managed choice history. `DialogueRunner.choices_made` is per-dialogue, not cross-game.

6. **No save/load capability** — Neither `GameState`, `StateSystem`, nor `GameManager` provides serialization. There is no mechanism to persist or restore game state for testing or checkpointing.

7. **No discrete state ID system** — `StateSystem.get_state_tier()` returns string labels (`"low"`/`"mid"`/`"high"`). Issue #47's AC1 requires discrete steps with signal emission, and Issue #50's 5-state design requires a numeric state ID (1–5). Neither currently exists.

8. **Bipolar slider is missing** — The `hope_despair` unified bipolar slider (-10 to +10) proposed in Issue #50 has not been implemented. Hope and despair are managed as independent axes in `GameState` and as a single 0–10 axis in `StateSystem`.

### Expected Behavior

A unified **GameState System** that:

1. **Consolidates all game state into a single authoritative autoload** — `StateSystem` becomes the singleton GameState autoload, deprecating the legacy `GameState` and wiring `GameManager` as a thin facade.

2. **Provides a bipolar `hope_despair` slider** — Range -10.0 to +10.0 with 5 discrete states (1=Despair, 2=Low, 3=Neutral, 4=Buoyant, 5=Hope) as designed in Issue #50. `hope` and `despair` are *derived* from this value.

3. **Maintains the tri-axis (hope, conviction, will)** — The 0–10 axes continue to work for backward compatibility. `hope` is derived from `hope_despair` via mapping: `hope = (hope_despair + 10.0) / 2.0`.

4. **Provides a flags system** — At least 10 boolean flags with CRUD API. Flags are serializable and persist across scene transitions.

5. **Provides choice history** — Tracks all dialogue choices made in the current run, with node_id, choice_index, choice_text, and timestamp.

6. **Provides save/load** — Serializes all state (sliders, flags, choice history, clock) to a Dictionary for JSON persistence. Deserialization restores exact state for testing and checkpointing.

7. **Emits discrete state change signals** — `state_changed(state: Dictionary)` fires on every state mutation. A new `state_id_changed(state_id: int)` signal fires only when the discrete state ID changes (not on every slider tick).

8. **Wires GameManager** — `get_slider()`, `apply_slider_delta()`, `set_flag()`, `has_flag()`, `get_flags()` all delegate to StateSystem with real data.

### User Scenarios

- **Scenario A (Developer testing):** A developer calls `StateSystem.save_state_to_file("user://test_state.json")`, modifies sliders via `apply_choice()`, then calls `load_state_from_file("user://test_state.json")` to restore exact state. All sliders, flags, and choice history match.

- **Scenario B (Dialogue authoring):** A writer authors a dialogue JSON with `{"type": "flag", "flag": "met_stranger", "value": true}` and `{"type": "slider", "axis": "hope_despair", "op": "gte", "value": 2}` conditions. Both conditions evaluate correctly because GameManager delegates to StateSystem.

- **Scenario C (State-dependent scene):** A scene script calls `StateSystem.get_state_id()` in `_ready()` and selects from 5 variant texts. When the player makes a dialogue choice that changes the slider, `state_id_changed` fires and the scene updates environmental text dynamically.

- **Frequency:** Every dialogue choice (6–14 per play session) calls `apply_slider_delta()`. Every `enter_node()` in the dialogue engine calls `_build_state_snapshot()` which queries sliders, flags, and choice history. Every scene `_ready()` calls state queries. State is read/written dozens of times per play session.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally through layered issues, with each layer adding its own state management:

| Issue | What It Added | State Files Created/Modified | Why It's Fragmented |
|-------|--------------|------------------------------|---------------------|
| #43 | Project scaffold | `game_state.gd` (legacy autoload) | First state file — simple hope/despair 0–100 |
| #42 | Theme-mechanic mapping | `state_system.gd` (tri-axis, NOT autoload) | Different author, different design (0–10, tri-axis) |
| #45 | Narrative architecture | `game_manager.gd` (stub facade), `narrative_manager.gd` | Needed dialogue API — created stubs as placeholder |
| #50 | State-world feedback (PRD only) | Proposed unifying StateSystem → autoload + bipolar slider | PRD exists but not implemented |
| #46 | Dialogue engine | `dialogue_runner.gd`, `dialogue_condition_evaluator.gd` | Condition evaluator written against `GameManager` stub API |

Each layer was authored independently. The `GameManager` stub was intended as a temporary placeholder, but no issue has yet wired it to real data.

### Why Change Now?

- **Issue #50 (State-World Feedback)** has a completed PRD that defines the bipolar slider design and StateSystem autoload requirement — but it hasn't been implemented. Issue #47 is the vehicle to implement the consolidated GameState System that #50 depends on.

- **The dialogue engine is fully functional** — `dialogue_runner.gd` has `_build_state_snapshot()`, `_apply_effects()`, and `DialogueConditionEvaluator.evaluate()`. All authored dialogue conditions that reference sliders/flags/choices are dead code until GameState is real.

- **Scene scripts exist for all 6 scenes** — `office.gd`, `lobby.gd`, `store.gd`, `bridge.gd`, `underpass.gd`, `subway_station.gd` all have `_configure_environmental_text()` that currently reads 3-tone state. With a real GameState, they can use 5-state conditional text.

- **5 downstream consumers** (`NarrativeManager`, `WorldviewController`, `RainController`, `AudioManager`, `SceneBase`) look up `StateSystem` at runtime. Making it an autoload eliminates fragile string-based lookups.

- **Save/load is a blocking dependency** for testing — without serialization, every test requires fresh dialogue state. With save/load, tests can set up specific state snapshots and verify behavior.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| State architecture | Tri-axis: hope, conviction, will (0–10, 5=neutral) |
| Legacy system | `GameState` autoload (hope/despair 0–100) — must not break existing references during migration |
| Autoloads | `GameManager` (stub), `GameState` (legacy), `NarrativeManager`, `AudioManager` |
| Dialogue conditions | Supported ops: `gte`, `lte`, `gt`, `lt`, `eq` on slider axes |
| Current worldview tones | `"despair"` (hope ≤ 3), `"neutral"` (3 < hope < 7), `"hope"` (hope ≥ 7) — 3 states |
| Current narrative tones | Per-scene 3-state mapping in `narrative_manager.gd._calculate_tone_for_scene()` |
| Scene scripts | Each scene's `_configure_environmental_text()` reads state at `_ready()` via `SceneBase.get_state()` |
| Existing dialogues | 7+ JSON files with condition-gated choices |
| Existing tests | `tests/test_game_state.gd` tests legacy GameState; `tests/run_tests.gd` includes GameState + StateSystem tests |
| Writing style | Hemingway — short lines, iceberg theory |
| Visual style | Edward Hopper urban night — dark, warm amber light, lo-fi pixel text |
| Endings | 3 (Keep Walking / Turn Back / Stay) via `NarrativeManager.determine_ending()` |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/state_system.gd` | StateSystem | **Modified** — Add `hope_despair` bipolar slider (-10 to +10); add `get_state_id()` returning 1–5; add flags API; add choice history tracking; add save/load serialization; add `state_id_changed` signal; promote to autoload |
| `gdscripts/game_manager.gd` | GameManager | **Modified** — Wire `get_slider()`, `apply_slider_delta()`, `set_flag()`, `has_flag()`, `get_flags()` to delegate to StateSystem. Remove stub implementations. |
| `gdscripts/game_state.gd` | GameState (legacy) | **Deprecated** — Keep file for backward compat but emit deprecation warning. Delegate internally to StateSystem for `hope`/`despair`. |
| `project.godot` | Autoload config | **Modified** — Add `StateSystem` to `[autoload]` section; keep `GameState` (legacy) for migration period |
| `gdscripts/constants.gd` | Constants | **Modified** — Add state ID constants, default flag values, save/load file path constant |
| `gdscripts/worldview_controller.gd` | Worldview Controller | **Modified** — Optionally expand to 5-state (or keep 3-state for now — Issue #50 drives this) |
| `gdscripts/narrative_manager.gd` | Narrative Manager | **Indirectly modified** — Can read StateSystem as autoload with reliable `/root/StateSystem` path |
| `tests/test_game_state.gd` | GameState Tests | **Modified** — Add tests for bipolar slider, flags, choice history, save/load, serialization round-trip |
| `tests/run_tests.gd` | Test Runner | **Modified** — Add GameState System test suite |

### New Files Needed

| File | Purpose |
|------|---------|
| `gdscripts/game_state_system.gd` | **OR** extend `state_system.gd` directly — see Approach A vs B below |
| `tests/integration/test_game_state_integration.gd` | Integration tests for GameState → DialogueEngine → Scene interaction |
| `docs/DESIGN/47-gamestate-system.md` | Plan phase output |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/dialogue_runner.gd` | Dialogue Runner | `_build_state_snapshot()` will now get real slider values. May need to add `"hope_despair"` to the queried axis list. |
| `gdscripts/scene_base.gd` | Scene Base | `get_state()` and `get_state_tier()` helper methods will now return real data from autoloaded StateSystem |
| `gdscripts/main.gd` | Main Script | Currently uses `get_node("/root/GameState")` — should switch to `/root/StateSystem` |
| `gdscripts/rain_controller.gd` | Rain Controller | Currently reads conviction → rain mapping. May need to read `hope_despair` instead (Issue #50 scope). |
| `gdscripts/audio_manager.gd` | Audio Manager | Currently reads conviction + despair from state — will benefit from autoloaded StateSystem |
| All scene scripts | Scene Scripts | `_configure_environmental_text()` can now use 5-state IDs instead of 3-tone lookups |
| All dialogue JSONs | Dialogue Files | All authored slider conditions will now evaluate against real data |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | GDD | Update state system description |

### Data Flow Impact

```
Dialogue choice made
    │
    ├──► DialogueRunner.select_choice()
    │       └──► _apply_effects() → calls GameManager.apply_slider_delta()
    │               └──► GameManager (wired) → StateSystem.apply_choice()
    │                       ├── Updates hope_despair, conviction, will
    │                       ├── Clamps all values
    │                       ├── Calculates new state_id (1–5)
    │                       ├── Emits state_changed(state dict)
    │                       └── If state_id changed: emits state_id_changed(state_id: int)
    │
    ├──► WorldviewController receives state_changed
    │       └──→ world_text_changed.emit(tone)
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

Save/load flow:
    StateSystem.save_state_to_file(path)
        └──→ Serializes: hope_despair, conviction, will, flags, choice_history
        └──→ Writes JSON to file path
    StateSystem.load_state_from_file(path)
        └──→ Reads JSON
        └──→ Restores all state values
        └──→ Emits state_changed once after full restore
```

### Documents to Update

- [x] **This output:** `docs/PRD/47-gamestate-system.md`
- [ ] `docs/DESIGN/47-gamestate-system.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md` — Update state system description
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Document how GameState integrates with dialogue engine
- [ ] `docs/GAME_DESIGN/INDEX.md` — Index update
- [ ] `README.md` — If build/test instructions change

---

## 4. Solution Comparison

### Approach A: Extend StateSystem → Unify All State into One Autoload (Recommended)

**Description:**

Keep `state_system.gd` as the single authoritative GameState autoload. Add to it:

1. **Bipolar `hope_despair` slider** (-10.0 to +10.0) — `hope` (0–10) becomes derived: `hope = (hope_despair + 10.0) / 2.0`
2. **5 discrete state IDs** — `get_state_id() → int` returns 1–5 based on the Issue #50 mapping
3. **Flags system** — Dictionary-based `_flags: Dictionary` with `set_flag(name: String, value: bool)`, `has_flag(name: String) → bool`, `get_flags() → Dictionary`
4. **Choice history** — Array-based `_choice_history: Array[Dictionary]` with `record_choice(node_id: String, choice_index: int, choice_text: String)`
5. **Save/load** — `save_state_to_file(path: String) → bool` and `load_state_from_file(path: String) → bool` using JSON serialization
6. **`state_id_changed(state_id: int)` signal** — New signal fires only when the discrete state ID changes
7. **Autoload registration** — Add to `project.godot`'s `[autoload]` section

**GameManager wiring:**
- `get_slider(axis: String) → float` delegates to `StateSystem._get_axis_value(axis)`
- `apply_slider_delta(axis: String, delta: float)` delegates to `StateSystem.apply_choice({axis: delta})`
- `set_flag(name: String, value: bool)` delegates to `StateSystem.set_flag(name, value)`
- `has_flag(name: String) → bool` delegates to `StateSystem.has_flag(name)`
- `get_flags() → Dictionary` delegates to `StateSystem.get_flags()`

**Legacy GameState deprecation:**
- Keep `gdscripts/game_state.gd` file (don't delete — existing tests and `main.gd` reference it)
- In `_ready()`, print `push_warning("GameState is deprecated. Use /root/StateSystem instead.")`
- `apply_state(delta_hope, delta_despair)` maps to `StateSystem.apply_choice({hope_despair: delta_hope - delta_despair})`
- `get_state()` returns mapped values from StateSystem
- Remove from `project.godot`'s `[autoload]` in a follow-up issue after all references are migrated

**State serialization format:**
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
    {"node_id": "n_01", "choice_index": 0, "choice_text": "回应", "timestamp": 123456}
  ],
  "clock_day": 15
}
```

**Data flow after consolidation:**
```
StateSystem (autoload, /root/StateSystem)
    │
    ├── hope_despair (-10..+10)
    ├── conviction (0..10)
    ├── will (0..10)
    ├── flags (Dictionary)
    ├── choice_history (Array)
    │
    ├── state_changed(state: Dictionary) signal
    ├── state_id_changed(state_id: int) signal
    │
    ├── get_state_id() → 1..5
    ├── apply_choice(effect: Dictionary)
    ├── set_flag() / has_flag() / get_flags()
    ├── record_choice() / get_choice_history()
    └── save_state_to_file() / load_state_from_file()

GameManager (facade, /root/GameManager)
    │
    └── Delegates all state queries to StateSystem
        ├── get_slider() → StateSystem._get_axis_value()
        ├── apply_slider_delta() → StateSystem.apply_choice()
        └── set_flag() / has_flag() / get_flags() → StateSystem equivalents
```

**Pros:**
- **Single source of truth** — One autoload owns all game state. No synchronization risk.
- **Minimal new code** — Extending an existing file rather than creating a new module from scratch.
- **Backward compatible** — Existing `state_changed` signal signature doesn't change. All existing listeners continue to work.
- **Incremental migration** — Legacy `GameState` can be deprecated in-place while tests and scenes migrate.
- **Easy to test** — One file to mock, one `state_changed` signal to monitor.
- **Consistent with Issue #50** — The bipolar slider and 5-state mapping match the existing PRD.
- **GameManager wiring is a mechanical change** — Every delegation method is a 1–3 line implementation.
- **Save/load is self-contained** — StateSystem serializes its own state. No cross-module reconstruction needed.

**Cons:**
- `state_system.gd` will grow from ~45 lines to ~150–200 lines (flags + choice history + save/load adds bulk).
- Legacy `GameState` must remain as a compatibility shim during migration, creating a temporary period of two autoloads.
- The `clock_manager.gd` state (current_day) is a separate concern — save/load must also handle clock state or the clock must be integrated.
- Existing tests in `tests/test_game_state.gd` test the legacy `GameState` API — these need updates to test the new autoload.

**Risk:** Low — Extending an existing, well-tested module with additional features. The core state management logic (clamping, signals, apply_choice) is already proven.

**Effort:** 2–3 weeks (StateSystem expansion + GameManager wiring + legacy deprecation + flags + choice history + save/load + tests + scene migration)

---

### Approach B: New `GameStateSystem` Autoload — Clean Break from StateSystem

**Description:**

Create a brand-new `GameStateSystem` autoload (`gdscripts/game_state_system.gd`) that is the authoritative game state manager from scratch. `StateSystem` is kept as a compatibility wrapper that delegates to `GameStateSystem`. `GameManager` delegates to `GameStateSystem`. Legacy `GameState` is deprecated.

The new autoload includes:
1. Bipolar `hope_despair` slider + tri-axis derived values
2. 5 discrete state IDs
3. Flags system
4. Choice history
5. Save/load
6. `state_changed` + `state_id_changed` signals

`StateSystem` is refactored to be a thin wrapper:
```gdscript
# gdscripts/state_system.gd — New: compatibility wrapper
extends Node
func apply_choice(effect: Dictionary) -> void:
    var gs = get_node("/root/GameStateSystem")
    gs.apply_choice(effect)
func get_state() -> Dictionary:
    return get_node("/root/GameStateSystem").get_state()
# ... etc
```

**Pros:**
- Clean slate — no legacy baggage in the new module
- `state_system.gd` as a compatibility shim means zero breakage for existing code
- File size stays manageable (~150 lines for the new file, ~20 lines for the wrapper)
- Easier to unit test — clean interface, no inherited behavior to mock
- `GameStateSystem` name matches Issue #47's title ("GameState System")

**Cons:**
- **New autoload adds initialization complexity** — Another autoload on top of the current 5 (GameManager, GameState, StateSystem, NarrativeManager, AudioManager)
- **Three layers of delegation** — Scene → GameManager → GameStateSystem, with StateSystem as a parallel path. Developers must learn which layer to use.
- **Wrapper maintenance burden** — Every API change to GameStateSystem requires updating the StateSystem wrapper
- **NarrativeManager._state_system reference** — NarrativeManager stores `@onready var _state_system = get_node_or_null("/root/StateSystem")`. If StateSystem becomes a wrapper, NarrativeManager's property type must change or the wrapper must proxy everything.
- **Existing tests load `state_system.gd` directly** — `tests/run_tests.gd` instantiates `load("res://gdscripts/state_system.gd").new()`. These tests won't automatically pick up the new autoload.
- **Higher migration complexity** — Two sets of files to modify instead of one

**Risk:** Medium — A new autoload with wrapper creates an abstraction layer that must be maintained and tested. Developers may accidentally bypass the wrapper and talk to GameStateSystem directly, creating two code paths.

**Effort:** 3–4 weeks (new autoload + wrapper + GameManager wiring + legacy deprecation + flags + choice history + save/load + tests + migration)

---

### Approach C: Wire GameManager Only — Minimal Change

**Description:**

Minimal approach: do NOT create a unified GameState System. Instead, only wire `GameManager`'s stub methods to delegate to `StateSystem`. Add save/load to `GameManager`. Keep `GameState`, `StateSystem`, and `GameManager` as three separate files with different responsibilities.

- `GameManager.get_slider("hope")` → calls `get_node("/root/StateSystem").hope`
- `GameManager.set_flag()` → stores in `GameManager._flags`
- `GameManager` gets save/load for its own state (which is just flags + choice history)
- `StateSystem` is NOT made an autoload
- `GameState` legacy autoload remains untouched

**Pros:**
- **Smallest change** — Days, not weeks
- **No risk of breaking existing code** — No autoload changes, no file consolidation
- **GameManager becomes useful immediately** — Dialogue conditions start working
- **Save/load exists for the part of state that GameManager owns**

**Cons:**
- **Does NOT address the core fragmentation problem** — Three state sources remain
- **StateSystem still NOT an autoload** — All `get_node_or_null("/root/StateSystem")` lookups are still fragile
- **Bipolar slider doesn't exist** — `hope_despair` axis can't be authored in dialogue JSONs
- **No discrete state IDs** — 5-state text variant selection can't use numeric IDs
- **Save/load is incomplete** — StateSystem's hope/conviction/will values are not saved
- **Does NOT meet AC1** — No discrete steps with state signal
- **Short-term fix, not a real solution**

**Risk:** Low implementation risk, but high architecture risk — the fragmentation is compounded rather than resolved.

**Effort:** 3–5 days (GameManager wiring + basic save/load)

---

### Recommendation

→ **Approach A (Extend StateSystem → Unify All State into One Autoload)** because:

1. **Single source of truth** — The project needs one authoritative game state module. Approach A achieves this with the lowest code footprint.
2. **Incremental migration** — Legacy `GameState` is deprecated in-place. Existing tests still pass. No sudden breakage.
3. **Consistent with Issue #50** — The bipolar slider design, 5-state mapping, and autoload requirement are already documented in #50's PRD. Approach A directly implements them.
4. **Minimal new files** — Only `state_system.gd` is modified (plus tests). No new autoload. No wrapper files.
5. **GameManager wiring is trivial** — Every delegation method is 1–3 lines. The API contract already exists.
6. **Existing signal wiring works** — `state_changed` signal signature does not change. All 5 downstream consumers (NarrativeManager, WorldviewController, RainController, AudioManager, SceneBase) continue to work without changes.
7. **ClockManager integration** — Save/load supports the clock via an optional parameter, keeping ClockManager independent.

**Why not Approach B?** A new autoload creates three layers (GameManager → StateSystem wrapper → GameStateSystem) where one layer suffices. The wrapper maintenance burden isn't justified when the existing StateSystem can be extended directly.

**Why not Approach C?** It solves only the most immediate symptom (GameManager stubs) while leaving the underlying fragmentation in place. It doesn't meet AC1 (discrete state IDs) or provide a foundation for Issue #50's 5-state design.

**Key design decisions for Approach A:**

1. `state_system.gd` becomes the single authoritative GameState autoload at `/root/StateSystem`.
2. `hope_despair: float` (-10.0 to +10.0) is the primary slider. `hope` (0–10) is derived: `hope = (hope_despair + 10.0) / 2.0`.
3. 5 state IDs match Issue #50's mapping: 1=Despair (-10 to -6), 2=Low (-5 to -2), 3=Neutral (-1 to +1), 4=Buoyant (+2 to +5), 5=Hope (+6 to +10).
4. `get_state_id() → int` returns the current discrete state without signal emission. Signal fires only when state crosses a boundary.
5. `state_id_changed(state_id: int)` is a new signal. `state_changed(state: Dictionary)` keeps its existing signature.
6. Flags are stored as `_flags: Dictionary`. No pre-registration required — `set_flag()` creates keys on demand.
7. Choice history is stored as `_choice_history: Array[Dictionary]`. Max 200 entries (anti-bloat).
8. Save/load serializes to `user://` for testing compatibility. Format version field enables forward migration.
9. Legacy `GameState` `project.godot` autoload entry is kept during the migration period and removed in a follow-up issue.
10. `ClockManager` is NOT integrated into StateSystem — it remains independent. Save/load optionally includes clock state via `clock_manager.save_state()` / `clock_manager.load_state()`.

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 5 Discrete State IDs

| State ID | Name | Slider Range (hope_despair) | Derived hope (0–10) | Tone |
|----------|------|-----------------------------|---------------------|------|
| 1 | Despair | -10.0 to -6.0 | 0.0–2.0 | Deepest despair |
| 2 | Low | -5.0 to -2.0 | 2.5–4.0 | Negative but not hopeless |
| 3 | Neutral | -1.0 to +1.0 | 4.5–5.5 | Baseline — flat affect |
| 4 | Buoyant | +2.0 to +5.0 | 6.0–7.5 | Positive outlook, warm |
| 5 | Hope | +6.0 to +10.0 | 8.0–10.0 | Boundless hope |

**Boundary rule:** Upper bound is inclusive (`<=`). State 1 = [-10.0, -6.0], State 2 = (-6.0, -2.0], State 3 = (-2.0, +1.0], State 4 = (+1.0, +5.0], State 5 = (+5.0, +10.0].

Wait — the above ranges overlap. Correct mapping:
- State 1 (Despair): `hope_despair` in [-10.0, -6.0]
- State 2 (Low): `hope_despair` in (-6.0, -2.0]
- State 3 (Neutral): `hope_despair` in (-2.0, +2.0]
- State 4 (Buoyant): `hope_despair` in (+2.0, +6.0]
- State 5 (Hope): `hope_despair` in (+6.0, +10.0]

Each state has a range of 4.0 units (except state 3 which has 4.0 units from -2 to +2). The range -10 to +10 = 20 units / 5 states = 4 units per state.

### 5.2 Acceptance Criteria (from Issue #47)

- [x] **[AC1] Slider changes with discrete steps and emits 'state_changed' signal.**
  - `hope_despair` initialized to `0.0` (Neutral, state ID 3).
  - Range clamped to [-10.0, +10.0] on every `apply_choice()`.
  - `get_state_id()` returns correct ID (1–5) for any slider value.
  - `state_changed(state: Dictionary)` fires on every `apply_choice()` call.
  - `state_id_changed(state_id: int)` fires ONLY when state ID changes (not on every slider tick).
  - The `state` Dictionary in `state_changed` contains: `hope_despair`, `hope`, `despair`, `conviction`, `will`, `state_id`, `flags`, `choice_count`.
  - Documented in code comments: upper bound inclusive rule.

- [x] **[AC2] Save/load game state for testing.**
  - `save_state_to_file(path: String) → bool` serializes hope_despair, conviction, will, flags, choice_history.
  - `load_state_from_file(path: String) → bool` deserializes and restores all values.
  - After load, a single `state_changed` emission fires with the restored state.
  - Returns `false` if file doesn't exist or JSON is corrupt (no crash).
  - Serialization format has `"version": 1` field for forward migration.
  - Round-trip test: save → modify values → load → verify values match saved state.

- [x] **[AC3] Flags system works for at least 10 boolean flags.**
  - `set_flag(name: String, value: bool)` — creates or updates a flag entry.
  - `has_flag(name: String) → bool` — returns `false` for unset flags (no error).
  - `get_flags() → Dictionary` — returns all flags.
  - Supports at least 20 simultaneous flags (budget for future content).
  - Flags persist across serialization (save/load).
  - Default value for unset flags is `false` (matching current `GameManager.has_flag()` return).

### 5.3 Normal Path

1. Game starts → `StateSystem` autoload initializes with `hope_despair = 0.0`, `conviction = 5.0`, `will = 5.0`, no flags, no choice history.
2. Player makes a dialogue choice with effect `{"type": "slider_delta", "axis": "hope_despair", "delta": 2.0}`.
3. `GameManager.apply_slider_delta("hope_despair", 2.0)` → `StateSystem.apply_choice({"hope_despair": 2.0})`.
4. `hope_despair` changes to 2.0, `hope` derived to 6.0. State ID changes from 3 (Neutral) to 4 (Buoyant).
5. `state_changed` fires with full state Dictionary.
6. `state_id_changed(4)` fires.
7. All downstream listeners receive the signal and update environmental text / audio / NPC behavior.
8. Player triggers save → state serialized to JSON file.
9. Player loads save → state restored exactly, single `state_changed` emission.

### 5.4 Edge Cases

1. **hope_despair at exact boundary:** If `hope_despair = -6.0`, `get_state_id()` returns `1` (Despair, not Low). Mapping uses `<=` on upper bound: state 1 is [-10.0, -6.0], state 2 is (-6.0, -2.0], etc.

2. **State ID change during active dialogue:** The `state_id_changed` signal should NOT trigger environmental text changes during an active dialogue conversation. Mitigation: use the existing queuing pattern from Issue #50 — defer visual changes until `dialogue_ended`.

3. **Rapid slider changes:** If multiple `apply_choice()` calls happen in the same frame (e.g., a composite effect with multiple axes), only one `state_changed` emission should fire. Implement with a debounce or batch-apply pattern in StateSystem.

4. **Unset flag query:** `has_flag("nonexistent_flag")` returns `false` without error. `get_flags()` returns `{}` if no flags have been set.

5. **Save/load with corrupt file:** If the JSON file is malformed, `load_state_from_file()` returns `false` and prints a `push_warning`. State remains unchanged.

6. **Save/load version mismatch:** If the saved file has a `version` field that doesn't match the current code version, `load_state_from_file()` returns `false` with a warning message.

7. **Legacy GameState still referenced:** If existing code references `GameState.get_state()` (hope/despair 0–100), the deprecated autoload delegates to StateSystem internally. A `push_warning` is emitted once per session.

8. **GameManager queried before StateSystem is ready:** `GameManager._ready()` runs before `StateSystem._ready()` if autoload order changes. Mitigation: GameManager's delegation methods lazily resolve `/root/StateSystem` via `get_node_or_null()`.

9. **Choice history overflow:** If a player makes 200+ dialogue choices in a single session, the choice history array caps at 200 entries (oldest entries are dropped).

### 5.5 Failure Paths

1. **StateSystem not found as autoload:** If the `project.godot` `[autoload]` entry is missing, all `get_node_or_null("/root/StateSystem")` calls return `null`. All downstream consumers fall back to default neutral values (hope_despair=0, conviction=5, will=5). `push_warning` logged once.

2. **GameManager delegation fails silently:** If `GameManager` can't resolve `/root/StateSystem`, `get_slider()` returns `5.0` (existing stub behavior). The dialogue engine's `_build_state_snapshot()` picks up this default. This is already the current behavior, so no regression.

3. **Save file path doesn't exist:** `save_state_to_file()` creates parent directories automatically. `load_state_from_file()` returns `false` if the file doesn't exist.

4. **Flag name collision with reserved keys:** If a dialogue author uses `"version"` or `"state_id"` as flag names, they overwrite internal serialization keys. Mitigation: prefix all flag keys with `flag_` in serialization, or reject reserved names.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| StateSystem current architecture (`state_system.gd`) | ✅ Existing file (~45 lines) | **Low** — Well-tested base to extend |
| GameManager current stub API (`game_manager.gd`) | ✅ Existing file with correct method signatures | **Low** — API contract exists |
| Dialogue engine (Issue #46 / #52) | ✅ **Merged** (PRs merged) | **Low** — Condition evaluator supports slider + flag + choice_made types |
| Godot 4.7.1 | ✅ Stable | **Low** |

**Dependency chain map:**
```
#42 Theme-Mechanic Mapping ──→ #45 Narrative Architecture ──→ #50 State-World Feedback (PRD)
                                                                    │
                                                                    └── #47 (this issue) — implements the foundation
                                                                            │
                                                                            └── #56 Story Content (benefits from real state)
                                                                            └── Future dialogue JSON authoring
```

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #50 implementation (State-World Feedback) | **Critical** — #47's bipolar slider + 5-state IDs are the foundation #50 needs |
| All dialogue condition authoring (Issue #56) | **High** — Authored conditions are dead code until GameManager is wired |
| Environmental text 5-variant expansion | **Medium** — Scene scripts need real state IDs to select 5 variants |
| Save/checkpoint system | **Medium** — Save/load for testing can evolve into player save system |

### Preparation Needed

- [ ] **Decide on file approach:** Extend `state_system.gd` (Approach A) vs new `game_state_system.gd` (Approach B). This PRD recommends Approach A.
- [ ] **StateSystem autoload registration:** Add `StateSystem="*res://gdscripts/state_system.gd"` to `project.godot`'s `[autoload]` section.
- [ ] **Axis name coordination:** The `DialogueRunner._build_state_snapshot()` currently queries axes `["hope", "despair", "vigor", "burnout", "conviction", "falter"]`. Add `"hope_despair"` to this list. Old axes remain for backward compat.
- [ ] **Test audit:** Review `tests/test_game_state.gd` and `tests/run_tests.gd` to identify which tests must be updated for the new apis (bipolar slider, flags, choice history, save/load).

---

## 7. Spike / Experiment (Optional — depth/standard only)

> Skipped per `depth/standard` label. The recommended approach (Extend StateSystem → Universal Autoload) follows established Godot patterns with low technical risk. All three API additions (flags, choice history, save/load) are standard GDScript patterns documented in Godot best practices.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The GameState System is a **consolidation feature** — it doesn't add new gameplay, but it wires existing systems together and provides the foundation for all state-dependent content (Issue #50 State-World Feedback, Issue #56 Story Content).

**Current codebase state:**

- `state_system.gd` (~45 lines) — tri-axis hope/conviction/will, signals, get_state_tier. NOT an autoload.
- `game_state.gd` (~25 lines) — legacy autoload, hope/despair 0–100. Being deprecated.
- `game_manager.gd` (~70 lines) — autoload with stub methods for sliders, flags, and scene tracking.
- `constants.gd` (~105 lines) — thresholds, scene paths, ending conditions, dialogue file paths.
- `clock_manager.gd` (~30 lines) — standalone 90-day clock with signals.
- 5 downstream consumers listen to `state_changed` (NarrativeManager, WorldviewController, RainController, AudioManager, SceneBase).
- 6 scene scripts use state for environmental text.
- 7+ dialogue JSON files use slider/flag conditions that are currently dead code.
- Existing test suite tests both legacy GameState and StateSystem independently.

**The recommended approach is Approach A (Extend StateSystem):** Add the bipolar `hope_despair` slider (-10 to +10), 5-state discrete IDs, flags system, choice history tracking, and save/load serialization to `state_system.gd`. Make it an autoload. Wire `GameManager` to delegate to it. Deprecate legacy `GameState` in-place. The main risk is autoload registration order — `StateSystem` must initialize before `GameManager` and `NarrativeManager` reference it.

**What the Plan agent needs to produce:**
1. `docs/DESIGN/47-gamestate-system.md` — Detailed design doc with:
   - StateSystem class API specification (all new methods with typed signatures)
   - Flag system design (Dictionary-based, no pre-registration)
   - Choice history data model
   - Save/load serialization format
   - Autoload initialization order
   - GameManager delegation table
   - Migration plan (legacy GameState → deprecation → removal timeline)
2. `docs/TASKS/47-gamestate-system.md` — Task breakdown for implementation
3. Updated test plan covering all new APIs

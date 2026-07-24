# Design: #215 — godot_dialogue_manager Dialogue Engine Integration

> Parent Issue: #215
> Agent: game-plan-agent
> Date: 2026-07-25
> PRD Reference: `docs/PRD/215-integrate-godot-dialogue-manager.md`
> Recommended Approach: **Approach A — Full Integration** (adopted)

---

## 1. Architecture Overview

### Core Idea

Replace the project's custom JSON-based dialogue engine (DialogueRunner, DialogueParser, DialogueConditionEvaluator, DialogueEngine) with **godot_dialogue_manager v3.10.5** — a mature, MIT-licensed addon providing a dedicated `.dialogue` authoring language, built-in condition/mutation systems, DialogueLabel for typewriter effects, and a Godot editor plugin.

### Data Flow

```
Current (custom) data flow (REMOVED):

    JSON dialogue file
        │
        ├──► DialogueParser.load_dialogue()
        │       └──► DialogueRunner.start()
        │               ├──► enter_node() → filter via ConditionEvaluator
        │               ├──► node_changed.emit() → scene renders text
        │               ├──► select_choice() → _apply_effects()
        │               └──► GameManager → StateSystem


Proposed (godot_dialogue_manager) data flow:

    .dialogue file  ───►  DMCompiler → DialogueResource (.tres)
        │        (using StateSystem)
        │
        └──► CustomDialogueBalloon (instantiated by scene)
                │
                ├──► DialogueManager.get_next_dialogue_line(resource, title, [StateSystem])
                │       ├── Evaluates conditions against StateSystem (autoload)
                │       ├── Runs mutations: set/do on StateSystem or GameManager
                │       └── Returns DialogueLine (character, text, responses[])
                │
                ├──► DialogueLabel.type_out() → typewriter effect
                ├──► Player selects response → resource.get_next_dialogue_line(response.next_id)
                └──► Recurses until line is null → dialogue_ended → balloon closes
```

### System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     godot_dialogue_manager                        │
│  ┌────────────────────┐  ┌─────────────────┐  ┌──────────────┐   │
│  │ DialogueManager    │  │ DMCompiler      │  │ DialogueLabel│   │
│  │ (autoload singleton)│  │ (.dialogue→.tres)│  │ (typewriter)  │   │
│  └──────┬─────────────┘  └─────────────────┘  └──────────────┘   │
└─────────┼────────────────────────────────────────────────────────┘
          │ get_next_dialogue_line()
          ▼
┌──────────────────────────────────────────────────────────────────┐
│                   Custom DialogueBalloon                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ DialogueLabel │  │ ResponsePanel│  │ AnimationPlayer     │   │
│  │ (typewriter)  │  │ (choice btns)│  │ (fade in/out)       │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
          │ reads/writes via `using`
          ▼
┌──────────────────────────────────────────────────────────────────┐
│               Game State Layer (unchanged)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ StateSystem  │  │ GameManager  │  │ AudioManager         │   │
│  │ (autoload)   │  │ (facade)     │  │ (sound effects)      │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Structures

### 2.1 godot_dialogue_manager Types (New Dependency)

| Type | Role | Consumed By |
|------|------|-------------|
| `DialogueResource` | Compiled `.dialogue` → `.tres` resource. Preloaded before conversation. | Balloon trigger code |
| `DialogueLine` | Runtime line: `character`, `text`, `responses[]` (each with `is_allowed`, `next_id`), `inline_mutations[]` | Balloon rendering |
| `DialogueResponse` | A single choice: `text`, `next_id`, `is_allowed`, `mutations[]` | Balloon response display |
| `DialogueLabel` | `RichTextLabel` subclass with typewriter effect, inline mutation support, `spoke` signal | Balloon text display |

### 2.2 Existing Game State (Unchanged)

```
StateSystem (autoload, /root/StateSystem):
  - hope_despair: float (-10.0 to +10.0)
  - conviction: float (0.0 to 10.0)
  - will: float (0.0 to 10.0)
  - route_flag: String
  - _flags: Dictionary (boolean flags)
  - Methods: apply_choice(), get_state(), set_flag(), has_flag(),
             record_choice(), get_state_id(), set_route_flag()
  - Signals: state_changed(state), state_id_changed(state_id)

GameManager (autoload, /root/GameManager):
  - get_slider(), apply_slider_delta(), set_flag(), has_flag(), get_flags()
  - Delegates slider operations to StateSystem
```

### 2.3 Condition → Expression Mapping

| Custom JSON Condition | godot_dialogue_manager Expression |
|-----------------------|-----------------------------------|
| `{"type":"slider","axis":"hope","op":"gte","value":5}` | `StateSystem.hope >= 5` |
| `{"type":"slider","axis":"despair","op":"lte","value":3}` | `StateSystem.hope <= 3` *(despair maps to 10-hope; use hope directly)* |
| `{"type":"slider","axis":"will","op":"gte","value":6}` | `StateSystem.will >= 6` |
| `{"type":"slider","axis":"conviction","op":"gte","value":3}` | `StateSystem.conviction >= 3` |
| `{"type":"flag","flag":"met_bartender","value":true}` | `StateSystem.has_flag("met_bartender")` |
| `{"type":"flag","flag":"declined_drink","op":"eq","value":true}` | `StateSystem.has_flag("declined_drink")` |
| `{"type":"choice_made","node_id":"n_01","choice_index":0}` | *(Not directly supported — use `set` flags in .dialogue instead)* |
| `{"type":"and","conditions":[...]}` | `condition1 and condition2` |
| `{"type":"or","conditions":[...]}` | `condition1 or condition2` |
| `{"type":"not","condition":...}` | `not (condition)` |

### 2.4 Effect → Mutation Mapping

| Custom Effect | godot_dialogue_manager Syntax |
|---------------|-------------------------------|
| `{"type":"slider_delta","axis":"hope","delta":1}` | `do StateSystem.apply_choice({"hope_despair": 2})` *(hope delta 1 → hope_despair delta 2)* |
| `{"type":"slider_delta","axis":"hope","delta":-0.5}` | `do StateSystem.apply_choice({"hope_despair": -1})` |
| `{"type":"slider_delta","axis":"will","delta":1}` | `do StateSystem.apply_choice({"will": 1})` |
| `{"type":"slider_delta","axis":"conviction","delta":0.5}` | `do StateSystem.apply_choice({"conviction": 0.5})` |
| `{"type":"set_flag","flag":"bought_coffee","value":true}` | `set StateSystem.route_flag = "bought_coffee"` or `do StateSystem.set_flag("bought_coffee", true)` |
| `{"type":"play_sound","surface":"office"}` | `do GameManager.play_footstep("office")` |
| `{"type":"trigger_event","event":"..."}` | `do GameManager.trigger_event("...")` *(requires implementation)* |
| `{"type":"advance_clock"}` | `do GameManager.advance_clock()` *(requires implementation)* |

---

## 3. Module / File Changes

### 3.1 New Files

| File | Purpose |
|------|---------|
| `addons/dialogue_manager/` (directory) | godot_dialogue_manager v3.10.5 plugin — install via download + extract |
| `scenes/dialogue/dialogue_balloon.tscn` | Custom DialogueBalloon scene with DialogueLabel for typewriter, response VBoxContainer, AnimationPlayer for fade in/out |
| `gdscripts/dialogue_balloon.gd` | Balloon script: text typeout orchestration, response navigation (up/down/select), input mapping, graceful close |
| `scenes/dialogue/response_panel.tscn` | Custom response panel for choice buttons (styled per lo-fi aesthetic) |
| `dialogues/bartender.dialogue` | Migrated from `dialogues/bartender.json` |
| `dialogues/store_clerk.dialogue` | Migrated from `dialogues/store_clerk.json` |
| `dialogues/store_exit.dialogue` | Migrated from `dialogues/store_exit.json` |
| `dialogues/office_door.dialogue` | Migrated from `dialogues/office_door.json` |
| `dialogues/lobby_guard.dialogue` | Migrated from `dialogues/lobby_guard.json` |
| `dialogues/lobby_stranger.dialogue` | Migrated from `dialogues/lobby_stranger.json` |
| `dialogues/lobby_exit.dialogue` | Migrated from `dialogues/lobby_exit.json` |
| `dialogues/bridge_homeless.dialogue` | Migrated from `dialogues/bridge_homeless.json` |
| `dialogues/bridge_exit.dialogue` | Migrated from `dialogues/bridge_exit.json` |
| `dialogues/underpass_stranger_echo.dialogue` | Migrated from `dialogues/underpass_stranger_echo.json` |
| `dialogues/underpass_exit.dialogue` | Migrated from `dialogues/underpass_exit.json` |
| `dialogues/subway_ending.dialogue` | Migrated from `dialogues/subway_ending.json` |
| `dialogues/npc_test.dialogue` | Migrated from `dialogues/npc_test.json` |
| `tests/test_dialogue_manager_integration.gd` | Tests for DM integration: conditional branching, mutation effects, headless API calls |

### 3.2 Modified Files

| File | Change | Description |
|------|--------|-------------|
| `project.godot` | Modified | Add `enabled=PackedStringArray("dialogue_manager")` in `[editor_plugins]` section |
| `gdscripts/scene_base.gd` | Modified | Dialogue trigger pattern changes from `DialogueRunner.start()` to `DialogueManager.show_dialogue_balloon_scene()` or direct balloon instantiation |
| `gdscripts/npc_node.gd` | Modified | NPC interaction signal wiring updated to use DM balloon |
| `gdscripts/game_manager.gd` | Possibly modified | Add `trigger_event()` and `advance_clock()` methods if referenced by dialogue mutations |
| `docs/PROJECT.md` | Modified | Update dialogue system description and module list |

### 3.3 Removed / Deprecated Files

| File | Status | Notes |
|------|--------|-------|
| `gdscripts/dialogue_runner.gd` (239 lines) | **Deprecated** | Replaced by `DialogueManager.get_next_dialogue_line()` — keep as fallback during migration, remove when all 13 files migrated |
| `gdscripts/dialogue_parser.gd` (74 lines) | **Removed** | godot_dialogue_manager has its own compiler |
| `gdscripts/dialogue_condition_evaluator.gd` (88 lines) | **Removed** | DM has built-in condition evaluation |
| `gdscripts/dialogue_engine.gd` (66 lines) | **Removed** | Replaced by DialogueBalloon scene |
| `scenes/dialogue/dialogue_panel.tscn` | **Removed** | Replaced by dialogue_balloon.tscn |
| `dialogues/*.json` (13 files) | **Deprecated** | Migrated to `.dialogue` — keep originals until all conversions verified, then remove |

### 3.4 Affected Test Files

| File | Change |
|------|--------|
| `tests/test_dialogue_engine.gd` | Rewrite — use `DialogueManager.get_next_dialogue_line()` instead of `DialogueRunner` |
| `tests/test_dialogue_engine_v2.gd` | Rewrite — adapt to DM API |
| `tests/test_stranger_dialogue.gd` | Rewrite — use DM test patterns |
| `tests/unit/test_dialogue_runner_extension.gd` | Rewrite — test DM condition eval instead |
| `tests/unit/test_exit_dialogues.gd` | Rewrite — test exit dialogue conditions via DM |
| `tests/integration/test_audio_footstep_dialogue.gd` | Modify — adapt effect wiring to DM mutation syntax |

---

## 4. Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Approach** | Approach A — Full Integration (adopting PRD recommendation) | Best long-term value: typewriter effect, editor integration, condition evaluation, translation support. <2 weeks vs 3-5 weeks for custom build (Approach B). |
| **Plugin installation** | `addons/dialogue_manager/` via zip download + extract | Standard Godot addon pattern. Plugin registers `DialogueManager` singleton automatically — no manual autoload entry. |
| **State wiring** | `using StateSystem` at top of each `.dialogue` file | Exposes all StateSystem properties and methods as shorthand in conditions/mutations. No bridge code needed. |
| **Dialogue UI** | Custom `DialogueBalloon.tscn` based on DM's example | Provides full control over styling while reusing DM's `DialogueLabel` for typewriter. Matches lo-fi aesthetic (amber text on dark BG, pixel font). |
| **Input handling** | Map existing `dialogue_up`/`dialogue_down`/`dialogue_select` InputMap actions to balloon navigation | Reuses existing input configuration. No breaking change for player controls. |
| **Dialogue file format** | `.dialogue` text format (one file per NPC/scene) | More readable than JSON for branching narrative. Supports labels, gotos, snippets, weighted random, inline conditions. |
| **Backward compat** | Keep original JSON files during migration | Allows side-by-side comparison and fallback. Remove only after all 13 files migrated and tested. |
| **Test strategy** | API-level tests (no balloon instantiation in headless) | `DialogueLabel` requires Control canvas — headless tests use `DialogueManager.get_next_dialogue_line()` directly with `extra_game_states=[StateSystem]`. |
| **Effect mapping** | `do StateSystem.apply_choice(...)` for slider deltas; `do GameManager.xxx()` for custom effects | Preserves existing StateSystem logic (emotional resistance, history tracking). Custom effects delegated to GameManager methods. |
| **Singleton balloon check** | `if _current_balloon: return` before opening new balloon | Prevents concurrent balloon instances. One dialogue at a time. |

### Condition `choice_made` Handling

The custom system supports a `choice_made` condition type checking if a specific choice was previously made. godot_dialogue_manager does not have a native equivalent. **Decision:** In the `.dialogue` migration, use `using StateSystem` combined with flag-based tracking. Each response that needs `choice_made` checking should set a flag via mutation, then check that flag in later nodes. This preserves the anti-loop and branching logic without custom code.

### Effect `choice_made` Recording Preservation

The custom `DialogueRunner.record_choice()` writes to `choices_made`. StateSystem's `record_choice()` method handles this via `do StateSystem.record_choice(...)` in `.dialogue` mutation lines. This maintains choice history for narrative tracking.

---

## 5. Edge Cases & Error Handling

### 5.1 Dialogue File Compilation Errors

If a `.dialogue` file has syntax errors, `DialogueManager.get_next_dialogue_line()` prints the error to the console. The balloon closes gracefully with `push_error`. No crash. During development, the Godot editor's `.dialogue` plugin highlights syntax errors inline.

### 5.2 Missing State Property in Condition

If a condition references `StateSystem.nonexistent_property`, DM prints a warning. The condition evaluates to `false` (response not shown). Balloon handles by showing remaining reachable responses.

### 5.3 StateSystem Not Available

If the `using StateSystem` autoload can't be found, DM prints `"runtime.unknown_autoload"` error. The balloon should handle by closing gracefully with a `push_error`.

### 5.4 Empty Response List

If a dialogue node has no reachable responses (all conditions fail), DM returns `responses = []`. The balloon shows a "..." default response and ends the conversation.

### 5.5 Inline Mutation During Typewriter

If a line has `[do something()]` mid-text, DM's `DialogueLabel` handles the mutation automatically — pauses typing, executes mutation, continues.

### 5.6 Concurrent Balloon Instances

Implement singleton check: `if _current_balloon: return` before opening. If a player triggers dialogue while another is open, the second call is ignored.

### 5.7 Headless Mode Compatibility

`DialogueLabel` rendering requires a Control canvas — balloon instantiation fails in `--headless` mode. Mitigation: all headless tests use `DialogueManager.get_next_dialogue_line()` API directly with `extra_game_states=[StateSystem]`, without instantiating balloons.

### 5.8 Missing Effect Handler

Custom effects like `trigger_event` and `advance_clock` currently print warnings. In DM, these must be mapped to `do GameManager.trigger_event(...)` or `do GameManager.advance_clock()`. If the GameManager method doesn't exist, the mutation silently does nothing. Mitigation: implement stub methods in GameManager that print warnings.

---

## 6. Test Case Descriptions

### Scenario A: godot_dialogue_manager Plugin Installed and Enabled

- **Test A1 — Plugin loaded:** `DialogueManager` singleton is accessible as `DialogueManager` globally after project load. `DialogueManager` is not null in `_ready()`.
- **Test A2 — Plugin compiled:** `godot --headless --quit` exits with code 0. No script errors.

### Scenario B: StateSystem Exposed to Dialogue System

- **Test B1 — State read from dialogue:** A `.dialogue` test file with `using StateSystem` reads `StateSystem.hope_despair` in a condition. Setting `hope_despair = 5.0` before calling `get_next_dialogue_line()` makes a response with `[if StateSystem.hope_despair >= 5]` visible (`is_allowed == true`).
- **Test B2 — State write from dialogue:** A `.dialogue` file calls `do StateSystem.set_flag("test_flag", true)`. After `get_next_dialogue_line()` returns, `StateSystem.has_flag("test_flag")` returns `true`.
- **Test B3 — Signal emission:** After a `do StateSystem.apply_choice(...)` mutation, `state_changed` signal fires.

### Scenario C: Conditional Branching

- **Test C1 — Condition passes:** `hope_despair = 6.0`, response with `[if StateSystem.hope_despair >= 5]` has `is_allowed == true`.
- **Test C2 — Condition fails:** `hope_despair = 3.0`, same response has `is_allowed == false`.
- **Test C3 — Flag condition:** Set flag `met_bartender = true`. Response with `[if StateSystem.has_flag("met_bartender")]` has `is_allowed == true`. Clear flag → `is_allowed == false`.
- **Test C4 — Compound AND condition:** Response with `[if StateSystem.hope >= 5 and StateSystem.conviction >= 5]`. Both conditions must pass for response to be allowed.

### Scenario D: DialogueBalloon UI

- **Test D1 — Balloon instantiates:** `DialogueBalloon.tscn` instantiates without errors in a running scene tree.
- **Test D2 — Typewriter effect:** Text types out character by character when `DialogueLabel.type_out()` is called. `seconds_per_step` configurable.
- **Test D3 — Response display:** After typewriter finishes, response options appear in VBoxContainer.
- **Test D4 — Input handling:** `dialogue_up` / `dialogue_down` / `dialogue_select` input actions trigger correct balloon navigation.
- **Test D5 — Balloon close:** When `get_next_dialogue_line()` returns `null`, balloon auto-closes.

### Scenario E: Dialogue Format Migration (JSON → .dialogue)

- **Test E1 — bartender.json:** All 4 nodes (npc_bartender_greet, npc_bartender_drink, npc_bartender_leave, npc_bartender_silent) present in `bartender.dialogue`. Condition on "Not tonight." choice preserved. `set_flag` effect on "declined_drink" choice preserved. `slider_delta` effect on "despair" preserved.
- **Test E2 — All 13 dialogues compile:** `DialogueManager.get_next_dialogue_line()` called for each `.dialogue` file's entry node — no compile errors.
- **Test E3 — Response count matches:** Each migrated `.dialogue` node returns the same number of responses (after condition filtering) as the original JSON node at equivalent state values.

### Scenario F: Edge Cases

- **Test F1 — Empty response list:** A dialogue node with all conditions failing returns `responses = []`. Balloon ends gracefully.
- **Test F2 — Concurrent balloon:** Second balloon call is ignored when one is already open.
- **Test F3 — Compilation error:** A deliberately malformed `.dialogue` file does not crash the engine. `get_next_dialogue_line()` returns null with `push_error`.
- **Test F4 — State default values:** Dialogue triggered before any state mutations uses default StateSystem values (hope_despair=0, conviction=5, will=5). Conditions evaluate correctly against defaults.

### Scenario G: Headless API Verification

- **Test G1 — Direct API usage:** `DialogueManager.get_next_dialogue_line(resource, title, [StateSystem])` works in `--headless --script` mode.
- **Test G2 — No errors:** All dialogue API calls pass with no script errors in `--headless` mode.

# Design: #155 — Minimal Ending: Complete One Playable Path

> Parent Issue: #155
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Complete the 6-scene narrative chain so a player can start in the office, walk through all scenes, reach the subway station ending, see ending-appropriate epilogue text, and be returned to the game start with full state reset — without getting stuck at any transition point.

### Gap Audit (Correction to PRD Finding)

The PRD correctly identifies 5 broken exit points (office, lobby, bridge, underpass, subway ending) and 1 working exit (store → bridge). Cross-referencing the actual source confirms:

| Scene | Exit Trigger | Current Behavior | Gap |
|-------|-------------|------------------|-----|
| Office | `_start_door_dialogue()` → `office_door.json` | `door_leave` choices set flags but have `next_node: null` — dialogue ends, no scene load | No `"scene"` key |
| Lobby | `_on_exit_trigger_input()` → `nm.advance_scene()` | Advances counter, no dialogue, no scene load | No dialogue call, no transition |
| Store | `store_exit.json` | Choice has `"scene": "res://scenes/bridge/bridge.tscn"` | ✅ WORKS |
| Bridge | `_on_exit_trigger_input()` → `nm.advance_scene()` | Advances counter, no dialogue, no scene load | No dialogue call, no transition |
| Underpass | `_on_exit_trigger_input()` → `nm.advance_scene()` | Advances counter, no dialogue, no scene load | No dialogue call, no transition |
| Subway | `subway_ending.json` | 3 ending paths set flags (`ending_keep_walking`, `ending_turn_back`, `ending_stay`), dialogue ends | No post-ending transition to credits |

**Additional correction to PRD:** The PRD states `subway_ending.json` terminal choices have `next_node: null`. This is correct — they terminate the dialogue without any `"scene"` key. No post-ending scene exists.

### Data Flow (Post-Fix)

```
Player clicks exit trigger (Area3D.input_event)
  ↓
Scene script calls dialogue_runner.start("res://dialogues/<exit>.json", "<id>")
  ↓
DialogueRunner renders first node, player sees choices
  ↓
Player selects a choice
  ↓
DialogueRunner emits choice_made(index, text)
  ↓
SceneManager._on_choice_made() reads current_node.choices[index]
  ↓
Detects "scene" key → calls trigger_scene_change(target_scene)
  ↓
fade_out → persist dialogue state → change_scene_to_file → fade_in
  ↓
New scene's _ready() → SceneBase.fade_in() → player instantiated
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Exit trigger mechanism | Dialogue-based (not direct API call) | Matches proven store_exit.json pattern; allows state-aware narrative text per exit |
| Post-ending destination | `res://scenes/end_credits.tscn` | New dedicated scene; avoids coupling subway_ending.json to a specific restart flow |
| Ending detection | Existing `NarrativeManager.determine_ending()` | Already implemented and returns correct `"keep_walking"`, `"turn_back"`, or `"stay"` |
| Post-credits behavior | `GameManager.reset()` + reload `main.tscn` | Resets all state (playthrough_count preserved); returns to office for replay |
| Main menu | Deferred (not part of this issue) | Post-credits reloads `main.tscn` which immediately loads `office.tscn` — matches current no-menu design |
| Exit dialogue JSONs | One per missing exit (lobby, bridge, underpass) | Follows store_exit.json pattern exactly; each carries 1-2 narrative nodes |

---

## 2. New Files

### `dialogues/lobby_exit.json`

Role: Exit dialogue for lobby → convenience_store transition.

| Node ID | Speaker | Text | Choices |
|---------|---------|------|---------|
| `lobby_exit_prompt` | Narrator | "The revolving door catches the light. Outside, the street is quiet. The convenience store sign glows down the block." | `"Walk toward the store."` → scene transition |
| `lobby_exit_stand` | Narrator | (Optional second node) "A car passes. The rain has stopped. The store is still open." | `"Go now."` → scene transition |

```json
{
  "entry_node_id": "lobby_exit_prompt",
  "nodes": {
    "lobby_exit_prompt": {
      "speaker": "Narrator",
      "text": "The revolving door catches the light.\nOutside, the street is quiet.\nThe convenience store sign glows down the block.",
      "choices": [
        {
          "text": "Walk toward the store.",
          "effects": [],
          "scene": "res://scenes/store/convenience_store.tscn"
        },
        {
          "text": "Stand in the doorway a moment.",
          "next_node": "lobby_exit_stand",
          "effects": []
        }
      ]
    },
    "lobby_exit_stand": {
      "speaker": "Narrator",
      "text": "A car passes. The rain has stopped.\nThe store is still open.",
      "choices": [
        {
          "text": "Go now.",
          "effects": [],
          "scene": "res://scenes/store/convenience_store.tscn"
        }
      ]
    }
  }
}
```

### `dialogues/bridge_exit.json`

Role: Exit dialogue for bridge → underpass transition.

| Node ID | Speaker | Text | Choices |
|---------|---------|------|---------|
| `bridge_exit_prompt` | Narrator | "The bridge ends at a tunnel entrance. Graffiti covers the concrete walls. A single light flickers inside." | `"Enter the underpass."` → scene transition |

### `dialogues/underpass_exit.json`

Role: Exit dialogue for underpass → subway_station transition.

| Node ID | Speaker | Text | Choices |
|---------|---------|------|---------|
| `underpass_exit_prompt` | Narrator | "The tunnel opens into a wider space. Stairs descend. A sign reads 'SUBWAY →'. The air is still." | `"Take the stairs down."` → scene transition |

### `scenes/end_credits.tscn`

New scene. Minimal 3D scene with:
- `Node3D` root (name: `EndCredits`)
- `Label3D` for ending title (e.g. "Keep Walking")
- `Label3D` for epilogue text (3 sentences max)
- `Label3D` for "The End"
- `Timer` for auto-return (10 seconds)
- `SceneManager` child for fade-in
- `SpawnPoint` Marker3D (unused but convention)

### `gdscripts/end_credits.gd`

```gdscript
extends Node3D
class_name EndCredits

# End-credits scene script.
# Reads ending flags set by subway_ending.json, displays
# appropriate title + epilogue, then returns to main.tscn.

@onready var scene_manager: Node = $SceneManager
@onready var title_label: Label3D = $TitleLabel
@onready var epilogue_label: Label3D = $EpilogueLabel
@onready var the_end_label: Label3D = $TheEndLabel

var _ending_id: String = ""


func _ready() -> void:
    _determine_ending()
    _set_epilogue()
    _fade_in()
    $ReturnTimer.start()
    title_label.visible = true
    epilogue_label.visible = true
    the_end_label.visible = true


func _determine_ending() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if not gm:
        _ending_id = "stay"
        return
    if gm.has_flag("ending_keep_walking"):
        _ending_id = "keep_walking"
    elif gm.has_flag("ending_turn_back"):
        _ending_id = "turn_back"
    elif gm.has_flag("ending_stay"):
        _ending_id = "stay"
    else:
        _ending_id = "stay"


func _set_epilogue() -> void:
    match _ending_id:
        "keep_walking":
            title_label.text = "Keep Walking"
            epilogue_label.text = "The train carries you forward.\nThe city fades behind the glass.\nYou don't look back."
        "turn_back":
            title_label.text = "Turn Back"
            epilogue_label.text = "The exit door clicks shut.\nThe streets are empty.\nYou walk home."
        "stay":
            title_label.text = "Stay"
            epilogue_label.text = "The platform hums.\nThe clock reads 11:48.\nYou're still here. That's okay."


func _fade_in() -> void:
    if scene_manager and scene_manager.has_method("fade_in"):
        scene_manager.fade_in()


func _on_return_timer_timeout() -> void:
    _return_to_start()


func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _return_to_start()


func _return_to_start() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm and gm.has_method("reset"):
        gm.reset()
    var ss: Node = get_node_or_null("/root/StateSystem")
    if ss and ss.has_method("reset"):
        ss.reset()
    get_tree().change_scene_to_file("res://scenes/main.tscn")
```

### `tests/unit/test_exit_dialogues.gd`

New test file — validates all exit dialogue JSON files parse correctly and contain a `"scene"` key on terminal choices.

---

## 3. Modified Files

### Dialogue JSON Files

| File | Nature of Change | Est. Lines |
|------|-----------------|-----------|
| `dialogues/office_door.json` | Add `"scene": "res://scenes/lobby/lobby.tscn"` to all 3 terminal choices in `door_leave` node | +3 lines |
| `dialogues/subway_ending.json` | Add `"scene": "res://scenes/end_credits.tscn"` to 3 terminal choices (`kw_final`, `tb_final`, `st_final`) | +3 lines |

### Scene Scripts

| File | Nature of Change | Est. Lines |
|------|-----------------|-----------|
| `gdscripts/lobby.gd` | Replace bare `nm.advance_scene()` with `dialogue_runner.start("res://dialogues/lobby_exit.json", "lobby_exit")` | ±4 lines |
| `gdscripts/bridge.gd` | Replace bare `nm.advance_scene()` with `dialogue_runner.start("res://dialogues/bridge_exit.json", "bridge_exit")` | ±4 lines |
| `gdscripts/underpass.gd` | Replace bare `nm.advance_scene()` with `dialogue_runner.start("res://dialogues/underpass_exit.json", "underpass_exit")` | ±4 lines |

### Test Files

| File | Nature of Change | Est. Lines |
|------|-----------------|-----------|
| `tests/run_tests.gd` | Add `test_exit_dialogues.gd` load and run | +7 lines |

### Correction to PRD: No changes needed to `main.gd`

The PRD lists `gdscripts/main.gd` as a directly affected module (adding main menu). Per the deferred-main-menu decision, `_load_starting_scene()` already loads `office.tscn` — after credits, `_return_to_start()` calls `change_scene_to_file("res://scenes/main.tscn")` which will execute `main.gd._ready()` → `_load_starting_scene()`, reloading the office. No main.gd changes are needed.

---

## 4. API Contracts

### Signal Connections

```
SceneScript exit trigger
  → dialogue_runner.start(file_path, dialogue_id)    [direct call]
  → dialogue_runner.choice_made(index, text)         [signal → SceneManager]
    → SceneManager._on_choice_made(index, text)       [reads current_node.choices[index]["scene"]]
      → SceneManager.trigger_scene_change(path)       [fade_out → change_scene → fade_in]
```

### Method Call Chain (Subway Ending Terminal)

```
Play clicks gate/bench/turn-back trigger
  → subway_station.gd → start_dialogue("subway_ending.json", "subway_ending_*")
    → DialogueRunner traverses ending nodes
      → Player selects terminal choice with "scene" key
        → SceneManager._on_choice_made()
          → trigger_scene_change("res://scenes/end_credits.tscn")
            → fade_out → persist state → change_scene_to_file
              → end_credits.gd._ready()
                → read flags → set epilogue → fade_in
                → timer starts → _return_to_start()
                  → GameManager.reset() + StateSystem.reset()
                  → change_scene_to_file("res://scenes/main.tscn")
```

### Exit Dialogue Format Contract

Every exit dialogue JSON choice that terminates the dialogue MUST include:
```json
{
  "text": "Walk forward.",
  "effects": [],
  "scene": "res://scenes/<target>/<target>.tscn"
}
```

The `"scene"` key is parsed by `SceneManager._on_choice_made()` at line 102 of `scene_manager.gd`:
```gdscript
if choice.has("scene") and choice["scene"] != null and str(choice["scene"]) != "":
    trigger_scene_change(choice["scene"])
```

Scene paths MUST match existing `.tscn` files. SceneManager validates via `FileAccess.file_exists()` at line 114.

---

## 5. Test Layer

### Test Case Descriptions

#### Exit Dialogue Unit Tests

New file: `tests/unit/test_exit_dialogues.gd`

Pattern: Load each exit JSON via `JSON.parse_string()`, validate structure and `"scene"` keys.

| # | Scenario | Setup | Expected Behavior | Verification |
|---|----------|-------|-------------------|-------------|
| **TC1** | Office door exit JSON has `"scene"` key | Load `dialogues/office_door.json` → `door_leave` node → terminal choices | All 3 choices in `door_leave` have `"scene"` key with value `"res://scenes/lobby/lobby.tscn"` | `assert(choice.has("scene"))` for each choice in `door_leave` |
| **TC2** | Lobby exit JSON parses correctly | Load `dialogues/lobby_exit.json` | `entry_node_id` is `"lobby_exit_prompt"`, nodes dict has 2 entries, terminal choice has `"scene"` key | `assert(json.entry_node_id == "lobby_exit_prompt")`, `assert(terminal_choice.has("scene"))` |
| **TC3** | Bridge exit JSON parses correctly | Load `dialogues/bridge_exit.json` | `entry_node_id` is `"bridge_exit_prompt"`, terminal choice has `"scene"` key → `underpass.tscn` | `assert(bridge_exit_path.ends_with("underpass.tscn"))` |
| **TC4** | Underpass exit JSON parses correctly | Load `dialogues/underpass_exit.json` | Terminal choice has `"scene"` key → `subway_station.tscn` | `assert(path.ends_with("subway_station.tscn"))` |
| **TC5** | Subway ending JSON has `"scene"` on terminal choices | Load `dialogues/subway_ending.json` → check `kw_final`, `tb_final`, `st_final` | All 3 terminal nodes have `"scene": "res://scenes/end_credits.tscn"` | `assert(kw_choice.has("scene"))`, `assert(tb_choice.has("scene"))`, `assert(st_choice.has("scene"))` |
| **TC6** | Exit dialogue scene paths are valid files | For each exit JSON, extract `"scene"` values | All scene paths point to existing `.tscn` files | `assert(FileAccess.file_exists(scene_path))` for each extracted path |
| **TC7** | Exit dialogue JSON doesn't have missing speaker | Every node has non-empty `speaker` field | All nodes in lobby_exit.json, bridge_exit.json, underpass_exit.json | `assert(node.speaker != "")` for all nodes |

#### Scene Script Unit Tests

New file: `tests/unit/test_exit_trigger_scripts.gd` (or integrated into existing test files)

| # | Scenario | Setup | Expected Behavior | Verification |
|---|----------|-------|-------------------|-------------|
| **TC8** | Lobby exit trigger calls dialogue instead of advance_scene | Inspect `lobby.gd._on_exit_trigger_input` source | Function calls `dialogue_runner.start(` with `lobby_exit.json` path | Check source via parse or string contains |
| **TC9** | Bridge exit trigger calls dialogue instead of advance_scene | Inspect `bridge.gd._on_exit_trigger_input` source | Function calls `dialogue_runner.start(` with `bridge_exit.json` path | Check source via parse or string contains |
| **TC10** | Underpass exit trigger calls dialogue instead of advance_scene | Inspect `underpass.gd._on_exit_trigger_input` source | Function calls `dialogue_runner.start(` with `underpass_exit.json` path | Check source via parse or string contains |

#### End Credits Scene Tests

New file: `tests/unit/test_end_credits.gd`

| # | Scenario | Setup | Expected Behavior | Verification |
|---|----------|-------|-------------------|-------------|
| **TC11** | EndCredits reads `ending_keep_walking` flag | Create EndCredits instance, inject GameManager with `ending_keep_walking=true` | `_ending_id == "keep_walking"`, title_label.text contains "Keep Walking" | `assert(_ending_id == "keep_walking")` |
| **TC12** | EndCredits reads `ending_turn_back` flag | Create EndCredits instance, inject GameManager with `ending_turn_back=true` | `_ending_id == "turn_back"` | `assert(_ending_id == "turn_back")` |
| **TC13** | EndCredits reads `ending_stay` flag | Create EndCredits instance, inject GameManager with `ending_stay=true` | `_ending_id == "stay"` | `assert(_ending_id == "stay")` |
| **TC14** | EndCredits defaults to `"stay"` if no flags set | Create EndCredits instance, inject GameManager with no ending flags | `_ending_id == "stay"` | `assert(_ending_id == "stay")` |
| **TC15** | EndCredits `_return_to_start` resets GameManager | Create EndCredits, mock GameManager.reset() | `_return_to_start()` calls `gm.reset()` | Assert `gm.reset()` was called |
| **TC16** | EndCredits `_return_to_start` resets StateSystem | Create EndCredits, mock StateSystem.reset() | `_return_to_start()` calls `ss.reset()` | Assert `ss.reset()` was called |
| **TC17** | EndCredits `_return_to_start` loads main.tscn | Create EndCredits, mock `get_tree().change_scene_to_file` | Called with `"res://scenes/main.tscn"` | Assert change_scene_to_file was called with correct path |

#### Full Playthrough Integration Tests

New file or section in `tests/test_mvp_integration.gd`:

| # | Scenario | Setup | Expected Behavior | Verification |
|---|----------|-------|-------------------|-------------|
| **TC18** | NarrativeManager advances correctly through all 6 scenes | Create NM, call `advance_scene()` 6 times | Sequence: office → lobby → convenience_store → bridge → underpass → subway_station → empty | After 6 advances, returns `""` |
| **TC19** | Any ending triggers credits scene path | Inject subway_ending.json terminal choice with `"scene"` key | `choice.has("scene") == true`, path points to `end_credits.tscn` | Parse JSON, verify terminal choices |
| **TC20** | Keep Walking ending leads to keep_walking flag | Simulate keep_walking dialogue path through subway_ending.json | Last choice in `kw_final` sets `ending_keep_walking=true` | Assert `effects[idx].flag == "ending_keep_walking"` |
| **TC21** | Turn Back ending leads to turn_back flag | Simulate turn_back dialogue path through subway_ending.json | Last choice in `tb_final` sets `ending_turn_back=true` | Assert effects |
| **TC22** | Stay ending leads to stay flag | Simulate stay dialogue path through subway_ending.json | Last choice in `st_final` sets `ending_stay=true` | Assert effects |
| **TC23** | SceneManager triggers scene change from exit dialogue choice | Create SceneManager, mock DialogueRunner with a choice containing `"scene"` key | `_on_choice_made(0, "")` calls `trigger_scene_change(target_scene)` | Assert `trigger_scene_change` was called with correct path |
| **TC24** | SceneManager ignores choice without `"scene"` key | Same setup, but choice has `next_node` instead | `_on_choice_made(0, "")` does NOT call `trigger_scene_change` | Assert `trigger_scene_change` was NOT called |
| **TC25** | State persists across full path (hope/conviction/will) | Instantiate StateSystem, apply various deltas, call get_state() | State values are cumulative across all operations | Assert each axis equals sum of deltas |

---

## 6. Files Changed (Master Summary)

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `dialogues/lobby_exit.json` | NEW | Exit dialogue for lobby → store | +40 lines |
| `dialogues/bridge_exit.json` | NEW | Exit dialogue for bridge → underpass | +25 lines |
| `dialogues/underpass_exit.json` | NEW | Exit dialogue for underpass → subway | +25 lines |
| `dialogues/office_door.json` | MODIFY | Add `"scene"` key to 3 door_leave terminal choices | +3 lines |
| `dialogues/subway_ending.json` | MODIFY | Add `"scene"` key to 3 terminal choices (kw_final, tb_final, st_final) | +3 lines |
| `scenes/end_credits.tscn` | NEW | Epilogue/credits scene | +20 lines (scene file) |
| `gdscripts/end_credits.gd` | NEW | Credits scene script | +100 lines |
| `gdscripts/lobby.gd` | MODIFY | Replace `nm.advance_scene()` with `dialogue_runner.start()` | ±4 lines |
| `gdscripts/bridge.gd` | MODIFY | Replace `nm.advance_scene()` with `dialogue_runner.start()` | ±4 lines |
| `gdscripts/underpass.gd` | MODIFY | Replace `nm.advance_scene()` with `dialogue_runner.start()` | ±4 lines |
| `tests/unit/test_exit_dialogues.gd` | NEW | Exit dialogue JSON validation tests | +120 lines |
| `tests/unit/test_end_credits.gd` | NEW | End credits scene unit tests | +120 lines |
| `tests/run_tests.gd` | MODIFY | Register new test files | +7 lines |

**Total estimated change: ~475 lines**

---

## 7. Verification Checklist

- [ ] **TC1-7:** All exit dialogue JSON files parse correctly and contain valid `"scene"` keys
- [ ] **TC8-10:** All scene exit triggers call `dialogue_runner.start()` instead of bare `nm.advance_scene()`
- [ ] **TC11-14:** EndCredits correctly reads all 3 ending flags and defaults to "stay"
- [ ] **TC15-16:** EndCredits `_return_to_start()` resets GameManager and StateSystem
- [ ] **TC17:** EndCredits loads `main.tscn` on return
- [ ] **TC18:** NarrativeManager full scene sequence advances correctly
- [ ] **TC19-22:** All 3 subway ending paths lead to credits scene via `"scene"` key
- [ ] **TC23-24:** SceneManager handles choices with/without `"scene"` key correctly
- [ ] **TC25:** State persists correctly across transitions
- [ ] Player can walk: office → lobby → store → bridge → underpass → subway (8 interactions)
- [ ] All 3 endings display appropriate epilogue text
- [ ] After credits, player returns to office with clean state
- [ ] Existing test suite still passes (`godot --headless --script tests/run_tests.gd`)
- [ ] `playthrough_count` persists across cycles (remains unchanged by credits reset)

# Design: #46 — Dialogue Engine Data Model + Conditional Branching

> Parent Issue: #46
> Agent: plan-agent
> Date: 2026-07-22

---

## 1. Architecture Overview

### Core Idea

Implement a JSON-driven dialogue engine with three components: a **DialogueParser** that loads and validates dialogue trees from JSON files, a **DialogueConditionEvaluator** that checks runtime conditions (slider values, flags, previous choices) against `GameState`, and a **DialogueRunner** that orchestrates conversation flow — entering nodes, filtering choices by condition, applying side effects, and advancing to the next node.

### Data Flow

```
dialogue JSON files (dialogues/npc_*.json) — authoring format
       │
       ▼ (load + validate)
DialogueParser.gd — validates schema, indexes nodes by ID
       │
       ▼ (returns parsed Dictionary tree)
DialogueRunner.gd — stateful runtime per conversation
       │
       ├──► calls DialogueConditionEvaluator.gd for each Choice
       │    ├── reads GameState (sliders, flags) via GameManager
       │    └── returns true/false per condition
       │
       ├──► filters choices → presents reachable set to UI
       │
       ├──► on select: applies side effects (slider deltas, flag toggles)
       │    └── writes back to GameManager
       │
       └──► advances to next DialogueNode
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data format | JSON per NPC file | Writer-ergonomic, diffable, mergeable; portable across editors. One file per NPC (`dialogues/bartender.json`) scales for version control. |
| Runtime representation | Parsed Dictionary (not Godot Resource) | Avoids Godot `.tres` resource ceremony at this project scale (~5 NPCs, ~14-21 interactions). Dictionaries are simple to validate, debug, and serialize. |
| Condition DSL | Declarative dict format (`{"type": "slider", "axis": "hope", "op": "gte", "value": 5}`) | No arbitrary expression evaluation. Compact, type-safe by validation, easy to test. Supports AND/OR/NOT composition. |
| Side effect application | Ordered array of effect dicts on each Choice | Each effect mutates GameState before the next is evaluated. Clamp sliders to [1, 10]. |
| Parsing strategy | Validate on load; fail fast with descriptive errors | Invalid JSON, missing nodes, duplicate IDs caught at `load_dialogue()` time, not mid-conversation. |
| Loading strategy | Lazy-load per NPC | Load dialogue JSON only when player triggers an NPC interaction. Reduces memory overhead at project startup. |
| Integration with GameManager | DialogueRunner reads `GameManager.get_slider()`, `GameManager.has_flag()`, calls `GameManager.set_slider()`, `GameManager.set_flag()` | Thin interface — no new Autoload needed. Dialogue engine is a client of GameManager, not a peer. |

---

## 2. Node / Scene Tree Layer

### New Scene: `scenes/dialogue/dialogue_panel.tscn`

- **Root:** `Panel` (Control node)
- **Children:**
  - `RichTextLabel` — NPC dialogue text
  - `VBoxContainer` → `Button[]` — player choice buttons (0–4, filtered by conditions)
  - `Label` — speaker name
- **Script:** `gdscripts/dialogue_runner.gd`
- **Process Mode:** `When Paused` (dialogue may pause game)

### New Scene: `scenes/dialogue/dialogue_debug_overlay.tscn` (dev only)

- **Root:** `Panel` (Control node)
- **Children:**
  - `Label` — current node ID
  - `Label` — reachable / total choice count
  - `Label` — GameState snapshot (hope, despair, vigor, burnout, conviction, falter)
- **Script:** `gdscripts/dialogue_debug.gd`
- **Visibility:** Toggled via `F12` in debug builds

### Existing Scene Modifications: `scenes/main.tscn`

- Add `CanvasLayer` child for `dialogue_panel` (rendered on top of game world)
- For dev builds: add `CanvasLayer` child for `dialogue_debug_overlay`

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/dialogue_parser.gd`

**Extends:** `RefCounted` (pure utility class, no scene attachment)

**Purpose:** Load a JSON dialogue file, validate against the expected schema, return a parsed Dictionary indexed by node ID, or return an error dictionary.

```gdscript
class_name DialogueParser extends RefCounted

## Parsed dialogue tree shape:
# {
#   "nodes": {
#     "node_id_01": { ... DialogueNode ... },
#     "node_id_02": { ... DialogueNode ... },
#   },
#   "entry_node_id": "node_id_01"
# }

## Validates and parses a JSON dialogue file at the given path.
## Returns { "ok": true, "data": tree } or { "ok": false, "error": "..." }
static func load_dialogue(file_path: String) -> Dictionary:
    var file := FileAccess.open(file_path, FileAccess.READ)
    if file == null:
        return { "ok": false, "error": "Failed to open file: " + file_path }
    var json_str := file.get_as_text()
    file.close()
    return parse_json_string(json_str)


## Parses a JSON string and validates the dialogue tree structure.
static func parse_json_string(json_str: String) -> Dictionary:
    var json := JSON.new()
    var parse_err := json.parse(json_str)
    if parse_err != OK:
        return { "ok": false, "error": "JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()] }
    var data := json.get_data()
    if typeof(data) != TYPE_DICTIONARY:
        return { "ok": false, "error": "Root must be a JSON object (dictionary)" }
    return _validate_and_index(data)


## Validates structure and builds node_id → node index.
## Checks for: duplicate IDs, missing entry_node, missing referents, required fields.
static func _validate_and_index(data: Dictionary) -> Dictionary:
    # Must have "nodes" dictionary
    if not data.has("nodes") or typeof(data["nodes"]) != TYPE_DICTIONARY:
        return { "ok": false, "error": "Missing or invalid 'nodes' dictionary" }
    var nodes: Dictionary = data["nodes"]
    if nodes.is_empty():
        return { "ok": false, "error": "Dialogue tree has zero nodes" }

    # Must have entry_node_id referencing an existing node
    if not data.has("entry_node_id"):
        return { "ok": false, "error": "Missing 'entry_node_id'" }
    var entry_id: String = str(data["entry_node_id"])
    if not nodes.has(entry_id):
        return { "ok": false, "error": "entry_node_id '%s' not found in nodes" % [entry_id] }

    # Validate each node
    for node_id: String in nodes.keys():
        var node: Variant = nodes[node_id]
        if typeof(node) != TYPE_DICTIONARY:
            return { "ok": false, "error": "Node '%s' must be a dictionary" % [node_id] }
        # Required: speaker, text
        if not node.has("speaker") or typeof(node["speaker"]) != TYPE_STRING:
            return { "ok": false, "error": "Node '%s' missing 'speaker' (string)" % [node_id] }
        if not node.has("text") or typeof(node["text"]) != TYPE_STRING:
            return { "ok": false, "error": "Node '%s' missing 'text' (string)" % [node_id] }
        # Choices (optional array)
        if node.has("choices") and typeof(node["choices"]) == TYPE_ARRAY:
            for i: int in range(len(node["choices"])):
                var choice: Variant = node["choices"][i]
                if typeof(choice) != TYPE_DICTIONARY:
                    return { "ok": false, "error": "Node '%s' choice %d is not a dictionary" % [node_id, i] }
                # next_node must exist in nodes (unless terminal)
                if choice.has("next_node") and not nodes.has(choice["next_node"]):
                    return { "ok": false, "error": "Node '%s' choice %d next_node '%s' not found in nodes" % [node_id, i, str(choice["next_node"])] }

    return { "ok": true, "data": { "nodes": nodes, "entry_node_id": entry_id } }
```

### New Script: `gdscripts/dialogue_condition_evaluator.gd`

**Extends:** `RefCounted` (pure utility, stateless)

**Purpose:** Evaluate a single Condition dict against the current GameState. Returns true if the condition passes, false otherwise. Stateless — call with condition + state dictionary on each evaluation.

```gdscript
class_name DialogueConditionEvaluator extends RefCounted

## Supported condition types:
## - slider:  {"type": "slider", "axis": "hope", "op": "gte", "value": 5}
## - flag:    {"type": "flag", "flag": "met_bartender", "value": true}
## - choice_made: {"type": "choice_made", "node_id": "n_01", "choice_index": 0}
## - and:     {"type": "and", "conditions": [Cond, Cond, ...]}
## - or:      {"type": "or", "conditions": [Cond, Cond, ...]}
## - not:     {"type": "not", "condition": Cond}
##
## state is a Dictionary: { "sliders": {...}, "flags": {...}, "choices_made": [...] }

static func evaluate(condition: Dictionary, state: Dictionary) -> bool:
    var ctype: String = condition.get("type", "")
    match ctype:
        "slider":
            return _eval_slider(condition, state.get("sliders", {}))
        "flag":
            return _eval_flag(condition, state.get("flags", {}))
        "choice_made":
            return _eval_choice_made(condition, state.get("choices_made", []))
        "and":
            return _eval_and(condition, state)
        "or":
            return _eval_or(condition, state)
        "not":
            return _eval_not(condition, state)
        _:
            push_warning("Unknown condition type: '%s'" % ctype)
            return false


static func _eval_slider(cond: Dictionary, sliders: Dictionary) -> bool:
    var axis: String = cond.get("axis", "")
    var op: String = cond.get("op", "eq")
    var value: float = float(cond.get("value", 0))
    var current: float = float(sliders.get(axis, 0.0))
    match op:
        "gte": return current >= value
        "lte": return current <= value
        "gt":  return current > value
        "lt":  return current < value
        "eq":  return current == value
        _:
            push_warning("Unknown slider operator: '%s'" % op)
            return false


static func _eval_flag(cond: Dictionary, flags: Dictionary) -> bool:
    var flag_name: String = cond.get("flag", "")
    var expected: bool = bool(cond.get("value", true))
    return flags.get(flag_name, false) == expected


static func _eval_choice_made(cond: Dictionary, choices_made: Array) -> bool:
    var node_id: String = cond.get("node_id", "")
    var choice_idx: int = int(cond.get("choice_index", -1))
    for entry in choices_made:
        if typeof(entry) == TYPE_DICTIONARY:
            if entry.get("node_id") == node_id and entry.get("choice_index") == choice_idx:
                return true
    return false


static func _eval_and(cond: Dictionary, state: Dictionary) -> bool:
    var conditions: Array = cond.get("conditions", [])
    for c in conditions:
        if typeof(c) == TYPE_DICTIONARY:
            if not evaluate(c, state):
                return false
    return true


static func _eval_or(cond: Dictionary, state: Dictionary) -> bool:
    var conditions: Array = cond.get("conditions", [])
    for c in conditions:
        if typeof(c) == TYPE_DICTIONARY:
            if evaluate(c, state):
                return true
    return false


static func _eval_not(cond: Dictionary, state: Dictionary) -> bool:
    var inner: Variant = cond.get("condition", {})
    if typeof(inner) == TYPE_DICTIONARY:
        return not evaluate(inner, state)
    return false
```

### New Script: `gdscripts/dialogue_runner.gd`

**Extends:** `Node` (attached to `dialogue_panel.tscn`)

**Purpose:** Stateful runtime that manages a single conversation. Tracks current node, visited nodes, choice history. Orchestrates enter → evaluate → present → select → advance loop.

```gdscript
extends Node

signal dialogue_started(dialogue_id: String)
signal dialogue_ended()
signal node_changed(node_id: String, speaker: String, text: String)
signal choices_available(choices: Array)     # Array[Dictionary] — filtered, reachable choices
signal choice_made(choice_index: int, choice_text: String)

## Maximum times a node can be visited before forced exit (anti-loop).
const MAX_NODE_VISITS: int = 3

var current_dialogue_id: String = ""
var current_node_id: String = ""
var current_node: Dictionary = {}
var dialogue_tree: Dictionary = {}   # result from DialogueParser
var visited_nodes: Dictionary = {}   # node_id → visit_count
var choices_made: Array = []         # [ {node_id, choice_index, choice_text}, ... ]

## Load a dialogue by its file path (lazy-load).
## Returns true on successful load, false on error.
func load_dialogue(file_path: String, dialogue_id: String = "") -> bool:
    var result := DialogueParser.load_dialogue(file_path)
    if not result.get("ok", false):
        push_error("Dialogue load failed: ", result.get("error", "unknown"))
        return false
    dialogue_tree = result["data"]
    current_dialogue_id = dialogue_id
    visited_nodes.clear()
    choices_made.clear()
    return true


## Enter a node by ID. Evaluates conditions, presents choices.
func enter_node(node_id: String) -> void:
    if not dialogue_tree.has("nodes"):
        push_error("No dialogue tree loaded")
        _end_conversation()
        return

    var nodes: Dictionary = dialogue_tree["nodes"]
    if not nodes.has(node_id):
        push_error("Node not found: ", node_id)
        _end_conversation()
        return

    # Apply on_enter effects (if any)
    var node: Dictionary = nodes[node_id]
    if node.has("on_enter"):
        _apply_effects(node["on_enter"])

    # Track visits (anti-loop)
    var visits: int = visited_nodes.get(node_id, 0) + 1
    visited_nodes[node_id] = visits
    if visits > MAX_NODE_VISITS:
        push_warning("Node '%s' visited %d times — force ending conversation" % [node_id, visits])
        _end_conversation()
        return

    current_node_id = node_id
    current_node = node

    # Build GameState snapshot for condition evaluation
    var state := _build_state_snapshot()

    # Filter choices by condition
    var raw_choices: Array = node.get("choices", [])
    var reachable: Array = []
    var default_choice: Dictionary = {}

    for c in raw_choices:
        if typeof(c) != TYPE_DICTIONARY:
            continue
        if c.get("default", false):
            default_choice = c
            continue
        if c.has("condition"):
            var cond: Dictionary = c["condition"]
            if typeof(cond) == TYPE_DICTIONARY:
                if DialogueConditionEvaluator.evaluate(cond, state):
                    reachable.append(c)
        else:
            reachable.append(c)

    # Fallback: if no choices reachable and a default exists, use default
    if reachable.is_empty() and not default_choice.is_empty():
        reachable = [default_choice]

    node_changed.emit(node_id, node.get("speaker", ""), node.get("text", ""))
    choices_available.emit(reachable)


## Called when player selects a choice.
func select_choice(choice_index: int) -> void:
    var choices: Array = current_node.get("choices", [])
    if choice_index < 0 or choice_index >= choices.size():
        push_error("Choice index out of range: %d" % choice_index)
        return

    var choice: Dictionary = choices[choice_index]
    var choice_text: String = choice.get("text", "")

    # Record choice
    choices_made.append({
        "node_id": current_node_id,
        "choice_index": choice_index,
        "choice_text": choice_text
    })

    # Apply side effects
    if choice.has("effects"):
        _apply_effects(choice["effects"])

    choice_made.emit(choice_index, choice_text)

    # Advance to next node or end
    if choice.has("next_node") and not choice["next_node"].is_empty():
        enter_node(choice["next_node"])
    else:
        _end_conversation()


## Start conversation from the entry node of a loaded dialogue.
func start(dialogue_file_path: String) -> bool:
    if not load_dialogue(dialogue_file_path):
        return false
    dialogue_started.emit(current_dialogue_id)
    enter_node(dialogue_tree["entry_node_id"])
    return true


## Build a snapshot of the current GameState for condition evaluation.
func _build_state_snapshot() -> Dictionary:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm == null or not gm.has_method("get_slider") or not gm.has_method("has_flag"):
        # If GameManager doesn't have the API yet, return empty state
        return { "sliders": {}, "flags": {}, "choices_made": choices_made }
    var sliders := {}
    for axis in ["hope", "despair", "vigor", "burnout", "conviction", "falter"]:
        sliders[axis] = gm.get_slider(axis)
    return {
        "sliders": sliders,
        "flags": gm.get_flags(),
        "choices_made": choices_made
    }


## Apply an array of Effect dicts in order.
func _apply_effects(effects: Array) -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm == null:
        push_warning("GameManager not found — effects not applied")
        return
    for effect in effects:
        if typeof(effect) != TYPE_DICTIONARY:
            continue
        var etype: String = effect.get("type", "")
        match etype:
            "slider_delta":
                if gm.has_method("apply_slider_delta"):
                    gm.apply_slider_delta(effect.get("axis", ""), float(effect.get("delta", 0)))
            "set_flag":
                if gm.has_method("set_flag"):
                    gm.set_flag(effect.get("flag", ""), bool(effect.get("value", true)))
            "trigger_event":
                push_warning("trigger_event not yet implemented: %s" % effect.get("event", ""))
            "advance_clock":
                push_warning("advance_clock not yet implemented")
            _:
                push_warning("Unknown effect type: '%s'" % etype)


func _end_conversation() -> void:
    current_node_id = ""
    current_node = {}
    dialogue_ended.emit()
```

### New Script: `gdscripts/dialogue_debug.gd`

**Extends:** `CanvasLayer` (attached to debug overlay scene)

**Purpose:** Displays current dialogue state for development debugging. Toggle with F12.

```gdscript
extends CanvasLayer

@onready var node_id_label: Label = $Panel/NodeIdLabel
@onready var choices_label: Label = $Panel/ChoicesLabel

var is_visible: bool = false

func _ready() -> void:
    hide()

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("toggle_debug") or (event is InputEventKey and event.keycode == KEY_F12 and not event.echo):
        is_visible = not is_visible
        visible = is_visible

func update_display(runner: Node) -> void:
    if not is_visible:
        return
    # Update labels from runner state
```

### Existing Script Modifications: `gdscripts/game_manager.gd`

**Extends:** Add the dialogue-engine-facing API methods that the condition evaluator and runner depend on.

```gdscript
# Existing content kept. New methods added:

## --- Dialogue API ---

## Get current value of a slider axis. Returns 0.0 if axis unknown.
func get_slider(axis: String) -> float:
    # Placeholder — return default value until GameState system (Issue #43) is implemented
    return 5.0

## Check if a named flag is set.
func has_flag(flag_name: String) -> bool:
    # Placeholder — return false until flag system is implemented
    return false

## Get all flags as a Dictionary.
func get_flags() -> Dictionary:
    return {}

## Apply a slider delta (clamped to [1, 10]).
func apply_slider_delta(axis: String, delta: float) -> void:
    # Placeholder — no-op until GameState is implemented
    pass

## Set a named flag.
func set_flag(flag_name: String, value: bool) -> void:
    # Placeholder — no-op until GameState is implemented
    pass
```

---

## 4. Resource / Config Layer

### JSON Schema — Dialogue File Format

Each NPC has one JSON file in `dialogues/`. The JSON structure mirrors the internal dict shape described in the PRD.

```json
{
  "entry_node_id": "npc_bartender_greet",
  "nodes": {
    "npc_bartender_greet": {
      "speaker": "Bartender",
      "text": "You again. Same as usual?",
      "choices": [
        {
          "text": "Yeah, the usual.",
          "next_node": "npc_bartender_drink",
          "condition": null,
          "effects": []
        },
        {
          "text": "Not tonight.",
          "next_node": "npc_bartender_leave",
          "condition": {
            "type": "slider",
            "axis": "despair",
            "op": "lte",
            "value": 5
          },
          "effects": [
            { "type": "set_flag", "flag": "declined_drink", "value": true }
          ]
        },
        {
          "text": "...",
          "next_node": "npc_bartender_silent",
          "condition": {
            "type": "slider",
            "axis": "despair",
            "op": "gte",
            "value": 7
          },
          "effects": [
            { "type": "slider_delta", "axis": "despair", "delta": 1 }
          ]
        }
      ],
      "on_enter": [],
      "tags": ["bartender", "night_1"]
    },
    "npc_bartender_drink": {
      "speaker": "Bartender",
      "text": "One glass of warm sake, coming up.",
      "choices": [
        {
          "text": "Thanks.",
          "next_node": null,
          "effects": [
            { "type": "slider_delta", "axis": "hope", "delta": 1 }
          ]
        }
      ],
      "tags": ["bartender"]
    }
  }
}
```

### Dialogue File Organization

```
dialogues/
  ├── bartender.json
  ├── coworker.json
  ├── childhood_friend.json
  ├── mentor.json
  └── stranger.json
```

### Project Configuration: `project.godot`

- No new Autoloads needed — `DialogueRunner` is attached to the dialogue panel scene, not a global singleton.
- `GameManager` remains the sole Autoload for game state (extended with dialogue API methods).

### Directory Structure

```
dialogues/               ← NEW — dialogue JSON files
gdscripts/
  ├── main.gd
  ├── game_manager.gd    ← MODIFY — add dialogue API methods
  ├── dialogue_parser.gd         ← NEW
  ├── dialogue_condition_evaluator.gd  ← NEW
  ├── dialogue_runner.gd          ← NEW
  ├── dialogue_debug.gd           ← NEW (dev only)
scenes/
  ├── main.tscn
  ├── dialogue/
  │   ├── dialogue_panel.tscn     ← NEW
  │   └── dialogue_debug_overlay.tscn  ← NEW (dev only)
tests/
  └── run_tests.gd               ← MODIFY — add dialogue tests
```

---

## 5. Asset / Visual Layer

### Dialogue Panel Theme

- Panel background: semi-transparent dark overlay (black, 60% opacity)
- Speaker name label: bold white
- NPC dialogue text: light gray on dark background, 22pt
- Player choice buttons:
  - Normal: dark panel with light text, rounded corners
  - Hover: highlight with accent color
  - Disabled: dimmed (if condition fails, hidden entirely)
- Typewriter text reveal: 30ms per character (skippable on click)

### Debug Overlay

- Small panel top-left corner
- Monospace font, small (12pt)
- Green text on dark semi-transparent background
- Shows: current node ID, visit count, reachable choices, slider values

---

## 6. Input / UI Layer

### Dialogue Flow

1. Player interacts with an NPC → calls `DialogueRunner.start("dialogues/npc_id.json")`
2. `dialogue_panel.tscn` appears as an overlay (CanvasLayer)
3. NPC text reveals with typewriter animation (30ms/char)
4. After text fully revealed (or player clicks to skip), choice buttons appear
5. Player clicks a choice button → `DialogueRunner.select_choice(index)`
6. Side effects applied, next node loaded, repeat
7. Terminal node (no `next_node`) or Escape → panel hides

### Input Mapping

| Action | Binding | Context |
|--------|---------|---------|
| Advance text / Skip typewriter | Left Mouse, Space, Enter | Dialogue panel visible |
| Select choice 1–4 | 1–4 keys, or click | Choices visible |
| Close dialogue | Escape | Dialogue panel visible (only when no active node) |

### Keyboard Shortcut Registration

Add to `project.godot` Input Map:
- `ui_dialogue_advance` — Space, Enter, Left Mouse
- `ui_dialogue_choice_1` through `ui_dialogue_choice_4` — 1–4
- `ui_dialogue_close` — Escape

---

## 7. Test Layer

### Test Structure

New test cases added to `tests/run_tests.gd`. Tests are pure GDScript — no scene tree required. They instantiate `DialogueParser`, `DialogueConditionEvaluator`, and `DialogueRunner` as `RefCounted`/`Node` objects in headless mode.

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| DialogueParser.parse_json_string() | ✅ | ≥3 | ✅ |
| DialogueConditionEvaluator.evaluate() | ✅ | ≥4 | ✅ |
| DialogueRunner.load_dialogue() | ✅ | ≥2 | ✅ |
| DialogueRunner.enter_node() choice filtering | ✅ | ≥3 | ✅ |
| DialogueRunner.select_choice() side effects | ✅ | ≥2 | ✅ |
| DialogueConditionEvaluator compound logic | ✅ | ≥3 | ✅ |

### Test Case Descriptions

**Normal Path (TC-D1): DialogueParser loads and validates a well-formed dialogue**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D1-1 | Parse valid minimal dialogue | Valid JSON with 1 node + 1 choice | Returns `{"ok": true}` with indexed data | `_assert(result.ok == true)` |
| TC-D1-2 | Parse multi-node dialogue | 3 nodes, 2 with choices, one entry node | All nodes indexed by ID, entry_node_id set | `_assert(result.data.entry_node_id == "n_01")` |
| TC-D1-3 | Terminal node with null next_node | Choice has `next_node: null` | No validation error | `_assert(result.ok == true)` |

**Edge Case (TC-D2): DialogueParser validation edge cases**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D2-1 | Duplicate node IDs (theoretically impossible in dict, but test JSON in array form) | Same ID twice in JSON | Error on non-dict root — caught by validator | `_assert(result.ok == false)` |
| TC-D2-2 | Missing entry_node_id | No `entry_node_id` field | Parser returns error | `_assert(result.ok == false)` |
| TC-D2-3 | entry_node_id refers to non-existent node | `entry_node_id: "ghost"` but no such node | Parser returns error | `_assert(result.ok == false)` |
| TC-D2-4 | Choice next_node refers to non-existent node | `next_node: "missing"` not in nodes | Parser returns error | `_assert(result.ok == false)` |

**Failure Path (TC-D3): DialogueParser malformed input handling**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D3-1 | Invalid JSON syntax | `{invalid json}` | Parse error with line number | `_assert(result.ok == false)` |
| TC-D3-2 | Empty dialogue JSON | Empty file/fixture JSON string | Error — missing nodes dict | `_assert(result.ok == false)` |
| TC-D3-3 | Node missing required speaker field | Node without `speaker` | Error — missing field | `_assert(result.ok == false)` |
| TC-D3-4 | Non-dict node value | Node value is a string instead of dict | Error — type mismatch | `_assert(result.ok == false)` |

**Normal Path (TC-D4): DialogueConditionEvaluator basic evaluation**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D4-1 | Slider gte — passes | `{type:"slider", axis:"hope", op:"gte", value:5}`, state: hope=7 | Returns true | `_assert(ok == true)` |
| TC-D4-2 | Slider gte — fails | `{type:"slider", axis:"hope", op:"gte", value:5}`, state: hope=3 | Returns false | `_assert(ok == false)` |
| TC-D4-3 | Slider boundary eq | `{type:"slider", axis:"despair", op:"eq", value:5}`, state: despair=5 | Returns true | `_assert(ok == true)` |
| TC-D4-4 | Flag check — flag set | `{type:"flag", flag:"met_bartender", value:true}`, state: flags={met_bartender:true} | Returns true | `_assert(ok == true)` |
| TC-D4-5 | Flag check — flag not set | `{type:"flag", flag:"met_bartender", value:true}`, state: flags={} | Returns false | `_assert(ok == false)` |

**Edge Case (TC-D5): Compound conditions**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D5-1 | AND — both true | `{type:"and", conditions:[{type:"flag", flag:"a", value:true}, {type:"flag", flag:"b", value:true}]}`, both flags set | Returns true | `_assert(ok == true)` |
| TC-D5-2 | AND — one false | Same condition, flag "b" not set | Returns false | `_assert(ok == false)` |
| TC-D5-3 | OR — one true | `{type:"or", conditions:[...]}`, one true one false | Returns true | `_assert(ok == true)` |
| TC-D5-4 | OR — all false | `{type:"or", conditions:[...]}`, all false | Returns false | `_assert(ok == false)` |
| TC-D5-5 | NOT — negates true | `{type:"not", condition:{type:"flag", flag:"a", value:true}}`, flag "a" set | Returns false | `_assert(ok == false)` |
| TC-D5-6 | NOT — negates false | Same condition, flag "a" not set | Returns true | `_assert(ok == true)` |
| TC-D5-7 | Nested AND/OR | `{type:"and", conditions:[{type:"or", conditions:[...]}, {type:"flag", ...}]}` | Correctly evaluates nested structure | `_assert(ok == true)` |

**Normal Path (TC-D6): DialogueRunner basic conversation flow**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D6-1 | Load dialogue then enter entry node | Call `start()` with valid JSON path | `dialogue_started` fires, `node_changed` fires with correct speaker/text | `_assert(node_changed_fired == true)` |
| TC-D6-2 | Filter choices — all reachable | Node has 2 choices, no conditions | Both choices in `choices_available` array | `_assert(choices.size() == 2)` |
| TC-D6-3 | Filter choices — some gated | 1 of 3 choices has unmet condition | Only 2 choices in reachable array | `_assert(choices.size() == 2)` |
| TC-D6-4 | Terminal choice ends conversation | Choice with null next_node | `dialogue_ended` signal fires | `_assert(ended_fired == true)` |

**Edge Case (TC-D7): DialogueRunner edge cases**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D7-1 | All choices gated, no default | None of 3 choices' conditions met, no default | Empty reachable array, conversation ends gracefully | `_assert(choices.is_empty())` and `dialogue_ended` fires |
| TC-D7-2 | All choices gated, default exists | Conditions fail but one choice has `default: true` | Default choice is presented | `_assert(choices.size() == 1)` and `choices[0].default == true` |
| TC-D7-3 | Circular dialogue loop | 2 nodes referencing each other, visited 4 times | Anti-loop triggers after 3 visits per node, conversation force-ends | `_assert(ended_fired == true)` |
| TC-D7-4 | Load non-existent file | `start("nonexistent.json")` | Returns false, no crash | `_assert(result == false)` |

**Failure Path (TC-D8): DialogueRunner error handling**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-D8-1 | Enter unknown node ID | `enter_node("ghost")` | Error logged, conversation ends | `_assert(ended_fired == true)` |
| TC-D8-2 | Select choice out of range | `select_choice(99)` on node with 2 choices | Error logged, no crash | `_assert(no crash)` |
| TC-D8-3 | Malformed condition — unknown type | Condition with `type: "invalid"` | Evaluator returns false, logs warning | `_assert(evaluator.evaluate(...) == false)` |

---

## 8. Files Changed (per-layer summary)

### Node / Scene Tree Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/dialogue/dialogue_panel.tscn` | **New** — dialogue UI overlay scene | +50 |
| `scenes/dialogue/dialogue_debug_overlay.tscn` | **New** — dev debug overlay scene | +30 |
| `scenes/main.tscn` | Add CanvasLayer children for dialogue panel + debug overlay | +10 |

### GDScript / Logic Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/dialogue_parser.gd` | **New** — JSON load + validate + index | +90 |
| `gdscripts/dialogue_condition_evaluator.gd` | **New** — condition DSL evaluator | +80 |
| `gdscripts/dialogue_runner.gd` | **New** — stateful conversation runtime | +160 |
| `gdscripts/dialogue_debug.gd` | **New** — dev debug overlay controller | +40 |
| `gdscripts/game_manager.gd` | **Modify** — add dialogue-facing API methods | +30 |

### Resource / Config Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `dialogues/bartender.json` | **New** — sample dialogue JSON fixture | +60 |
| `project.godot` | Modify — add dialogue-related Input Map actions | +5 |

### Scenes

| File | Change | Est. Lines |
|------|--------|-----------|
| `scenes/dialogue/dialogue_panel.tscn` | **New** | +50 |
| `scenes/dialogue/dialogue_debug_overlay.tscn` | **New** | +30 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/run_tests.gd` | **Modify** — add dialogue test cases (TC-D1 through TC-D8) | +200 |

---

## 9. Verification Checklist

- [ ] TC-D1-1 through TC-D1-3: DialogueParser loads valid JSON correctly
- [ ] TC-D2-1 through TC-D2-4: Parser validation catches schema violations
- [ ] TC-D3-1 through TC-D3-4: Parser handles malformed input gracefully
- [ ] TC-D4-1 through TC-D4-5: ConditionEvaluator correctly evaluates slider/flag conditions
- [ ] TC-D5-1 through TC-D5-7: Compound AND/OR/NOT conditions evaluate correctly (including nesting)
- [ ] TC-D6-1 through TC-D6-4: DialogueRunner basic flow works (start, filter, end)
- [ ] TC-D7-1 through TC-D7-4: DialogueRunner handles edge cases (all gated, anti-loop, missing file)
- [ ] TC-D8-1 through TC-D8-3: DialogueRunner error handling doesn't crash
- [ ] `godot --headless --script tests/run_tests.gd` — all tests pass, 0 failures
- [ ] `gdscripts/game_manager.gd` dialogue API methods compile without errors
- [ ] JSON schema documented in this DESIGN doc is consistent with DialogueParser implementation
- [ ] No regression: existing `main.gd` and `game_manager.gd` unchanged

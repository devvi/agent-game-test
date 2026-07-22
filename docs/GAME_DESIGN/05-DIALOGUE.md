# Dialogue Engine — Data Model + Conditional Branching

> Parent Issue: #46
> Added: 2026-07-22 (post-merge GDD update)

## 1. Architecture Overview

The dialogue engine consists of three components that form a pipeline:

```
dialogue JSON → DialogueParser (validate + index)
                    ↓ parsed dictionary
             DialogueRunner (stateful runtime)
                    ↓
        DialogueConditionEvaluator (stateless checks)
```

**Design decisions:**
- **JSON format** over Godot Resources — writer-ergonomic, diffable, mergeable
- **Parsed Dictionaries** over custom classes — simpler validation at this project scale (~5 NPCs)
- **Declarative condition DSL** — dict-based (`{"type": "slider", "axis": "hope", "op": "gte", "value": 5}`) — type-safe, no arbitrary expression evaluation
- **Lazy-load per NPC** — dialogue JSON loaded only on interaction

## 2. Data Model

### Dialogue Tree Structure

```json
{
  "entry_node_id": "n_01",
  "nodes": {
    "n_01": {
      "speaker": "Bartender",
      "text": "You again. Same as usual?",
      "choices": [
        {
          "text": "Yeah, the usual.",
          "next_node": "n_02",
          "condition": null,
          "effects": []
        }
      ],
      "on_enter": [],
      "tags": ["bartender", "night_1"]
    }
  }
}
```

### Condition DSL

| Type | Fields | Description |
|------|--------|-------------|
| `slider` | `axis`, `op` (gte/lte/gt/lt/eq), `value` | Check slider value against threshold |
| `flag` | `flag`, `value` | Check if a boolean flag matches |
| `choice_made` | `node_id`, `choice_index` | Check if a specific choice was made |
| `and` | `conditions` (array) | All sub-conditions must pass |
| `or` | `conditions` (array) | At least one sub-condition must pass |
| `not` | `condition` | Invert a single sub-condition |

### Effect Types

| Type | Fields | Description |
|------|--------|-------------|
| `slider_delta` | `axis`, `delta` | Modify a slider value (clamped [1, 10]) |
| `set_flag` | `flag`, `value` | Set a named boolean flag |
| `trigger_event` | `event` | Narratively-trigger event (placeholder) |
| `advance_clock` | — | Advance game clock (placeholder) |

## 3. Key Implementation Details

### DialogueParser (`gdscripts/dialogue_parser.gd`)

- Extends `RefCounted` — pure utility, no scene attachment
- `load_dialogue(path)` → `{"ok": true, "data": {nodes, entry_node_id}}` or error
- Validates on load: missing fields, duplicate IDs, dangling next_node references

### DialogueRunner (`gdscripts/dialogue_runner.gd`)

- Extends `Node` — attached to `dialogue_panel.tscn`
- Stateful per conversation: tracks current node, visited nodes, choice history
- Anti-loop protection: `MAX_NODE_VISITS = 3` per node, force-ends conversation
- Default choice fallback: when all gated choices are hidden, uses the choice marked `"default": true`
- Signals: `dialogue_started`, `dialogue_ended`, `node_changed`, `choices_available`, `choice_made`

### DialogueConditionEvaluator (`gdscripts/dialogue_condition_evaluator.gd`)

- Extends `RefCounted` — stateless utility
- `evaluate(condition_dict, state_snapshot)` → bool
- Supports compound nesting: AND/OR/NOT
- Unknown condition types return false with warning

## 4. Scene Integration

- `scenes/main.tscn`: Has `CanvasLayer` child with `DialoguePanel` instance
- `scenes/dialogue/dialogue_panel.tscn`: Dialogue UI overlay (Panel → RichTextLabel + VBoxContainer of Buttons)
- `scenes/dialogue/dialogue_debug_overlay.tscn`: Dev overlay showing node ID, visit count, reachable choices (F12 toggle)

## 5. Constants & Limits

| Constant | Value | Context |
|----------|-------|---------|
| `MAX_NODE_VISITS` | 3 | Anti-loop per-node visit limit |
| Slider range | [1, 10] | All six slider axes |
| Text reveal | 30ms/char | Typewriter effect (skippable) |
| Max visible choices | 4 | UI layout constraint |

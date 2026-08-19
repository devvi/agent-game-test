# godot_dialogue_manager v3.10.5 — Integration Reference

> Research findings from Issue #215. Source: [github.com/nathanhoad/godot_dialogue_manager](https://github.com/nathanhoad/godot_dialogue_manager) (3727⭐, MIT license)
> Latest release: v3.10.5 (2026-07-20) for Godot 4.7

## Core API

### DialogueManager Singleton

Registered automatically by the addon plugin. Accessible as `DialogueManager` globally.

**Key methods:**
- `get_next_dialogue_line(resource, key="", extra_game_states=[], mutation_behaviour) → DialogueLine` — must `await`. Traverses dialogue file, runs mutations, returns the next printable line.
- `show_dialogue_balloon(resource, title="", extra_game_states=[]) → Node` — opens the configured balloon scene.
- `show_dialogue_balloon_scene(balloon_scene, resource, title="", extra_game_states=[]) → Node` — opens a specific balloon scene.
- `get_line(resource, key, extra_game_states) → DialogueLine` — get a specific line by ID.

**Signals:** `dialogue_started`, `got_dialogue`, `mutated`, `dialogue_ended`, `passed_title`

### DialogueLine properties
- `id: String`, `next_id: String`, `character: String`, `text: String`
- `tags: PackedStringArray`, `translation_key: String`
- `responses: Array[DialogueResponse]` — each has: `id`, `next_id`, `is_allowed`, `character`, `text`, `tags`

### DialogueLabel (extends RichTextLabel)
- `seconds_per_step: float = 0.02` — typewriter speed
- `pause_at_characters: String = ".?!"` — auto-pause markers
- `type_out()` — start typing; `skip_typing()` — jump to end
- Signals: `spoke`, `started_typing`, `skipped_typing`, `finished_typing`, `paused_typing`

## Dialogue Language (`.dialogue` files)

### Basic structure
```
~ title_name
CharacterName: Dialogue text here.
- Response text [if condition] => next_title
- Another response => END
```

### State integration via `using`
```
using StateSystem

~ start
Bartender: You again. Same as usual?
- Yeah [if StateSystem.hope_despair >= 0]
    do StateSystem.apply_choice({"hope_despair": 1})
    => n_02
- ...
    => n_02
```

### Condition syntax (in `.dialogue`)
- `if StateSystem.hope_despair >= 5` — comparison
- `if StateSystem.hope_despair >= 0 and StateSystem.conviction < 3` — compound
- `if (StateSystem.hope_despair >= 0 or StateSystem.route_flag == "keep_walking")` — grouped
- `if StateSystem.has_flag("met_stranger")` — method calls on state autoloads
- `[if condition]text[/if]` — inline conditions within dialogue text

### Mutation syntax
- `set StateSystem.route_flag = "keep_walking"` — assign a property
- `do StateSystem.apply_choice({"hope_despair": 1})` — call a method
- `do wait(2.0)` — built-in pause
- `do debug("some text")` — built-in debug print
- `[do some_method()]` — inline mutation within dialogue text (pauses typewriter)

### Advanced features
- `match` — switch/case equivalent
- `while` — looping blocks
- `%` — weighted random lines
- `=> some_title@uid://xxxx` — goto with resource reference (cross-file jumps)
- `=> END` / `=> END_CONVERSATION` — terminal states

## Balloon Pattern

### Minimal balloon flow
```gdscript
# In a custom balloon scene extending CanvasLayer or Control:
func _start_dialogue(resource: DialogueResource, title: String) -> void:
    var line: DialogueLine = await DialogueManager.get_next_dialogue_line(resource, title, [StateSystem])
    if line == null:
        queue_free()
        return
    _show_line(line)

func _show_line(line: DialogueLine) -> void:
    dialogue_label.dialogue_line = line
    dialogue_label.type_out()
    await dialogue_label.finished_typing
    _show_responses(line.responses)

func _on_response_selected(response: DialogueResponse) -> void:
    var next_line = await resource.get_next_dialogue_line(response.next_id)
    if next_line == null:
        queue_free()
        return
    _show_line(next_line)
```

### Input mapping
Map existing InputMap actions to balloon methods:
- `dialogue_up` → `_previous_response()`
- `dialogue_down` → `_next_response()`
- `dialogue_select` → `_confirm_response()`
- `dialogue_skip` → `dialogue_label.skip_typing()`

## StateSystem Integration

The existing `StateSystem` autoload has all properties needed for `.dialogue` conditions:

| `.dialogue` expression | Maps to |
|------------------------|---------|
| `StateSystem.hope_despair` | `hope_despair: float` (-10..+10) |
| `StateSystem.conviction` | `conviction: float` (0..10) |
| `StateSystem.will` | `will: float` (0..10) |
| `StateSystem.route_flag` | `route_flag: String` |
| `StateSystem.has_flag("name")` | `has_flag(name) → bool` |
| `do StateSystem.apply_choice({"hope_despair": 1})` | Effect via StateSystem |
| `set StateSystem.route_flag = "keep_walking"` | Route assignment |

Pass `StateSystem` as an extra_game_state:
```gdscript
var line = await DialogueManager.get_next_dialogue_line(resource, title, [StateSystem])
```

Or use `using StateSystem` in the `.dialogue` file header to make properties accessible directly.

## JSON → .dialogue Migration Pattern

| JSON concept | .dialogue equivalent |
|-------------|----------------------|
| `entry_node_id` | `~ title` at top of file |
| `nodes.n_01.speaker` | `CharacterName: ` prefix on line |
| `nodes.n_01.text` | Text after speaker prefix |
| `nodes.n_01.choices[].text` | `- Response text` |
| `condition: {"type":"slider","axis":"hope","op":"gte","value":5}` | `[if StateSystem.hope >= 5]` |
| `condition: {"type":"flag","flag":"met","value":true}` | `[if StateSystem.has_flag("met")]` |
| `effects: [{"type":"slider_delta","axis":"hope_despair","delta":1}]` | `do StateSystem.apply_choice({"hope_despair": 1})` |
| `next_node: "n_02"` | `=> n_02` |
| no next_node / terminal | `=> END` |

## Pitfalls

- **DialogueLabel requires a Control canvas** — cannot instantiate in `--headless` mode. Use `DialogueManager.get_next_dialogue_line()` API directly for headless tests.
- **`using` autoload must match the autoload name** — if StateSystem is registered as `StateSystem` in project.godot, the `using` line must be `using StateSystem` (case-sensitive).
- **Inline mutations pause typewriter** — `[do something()]` inside text pauses the typewriter until the mutation resolves. Use `[do! async_thing()]` with `!` to skip waiting.
- **Response conditions only filter is_allowed** — the response object is always returned, but `is_allowed` tells the balloon whether to show it.

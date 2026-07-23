# Dialogue Engine — Data Model + Conditional Branching + Runtime + Visual

> Parent Issues: #46, #52
> Added: 2026-07-22 (post-merge GDD updates)
> Updated: 2026-07-22 (added runtime + visual layer — PR #83)

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
| `slider_delta` | `axis`, `delta` | Modify a slider value (clamped to axis range) |
| `set_flag` | `flag`, `value` | Set a named boolean flag |
| `trigger_event` | `event` | Narratively-trigger event (placeholder) |
| `advance_clock` | — | Advance game clock (placeholder) |
| `scene` | (key on choice object) | **Scene transition key** — when present, triggers cross-scene navigation instead of continuing dialogue. Value is a Godot scene path (e.g. `\"res://scenes/lobby/lobby.tscn\"`). Parsed by `SceneManager._on_choice_made()`. Expects `choice.has(\"scene\") == true` for terminal choices, which pairs with `next_node: null`. Added in Issue #155. |

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

- `scenes/main.tscn`: Has `CanvasLayer` child with `DialoguePanel` instance and `Dialogue3D` node
- `scenes/dialogue/dialogue_panel.tscn`: Dialogue UI overlay (Panel → RichTextLabel + VBoxContainer of Buttons)
- `scenes/dialogue/dialogue_debug_overlay.tscn`: Dev overlay showing node ID, visit count, reachable choices (F12 toggle)
- `scenes/dialogue/Dialouge3D.tscn`: 3D dialogue display with SpeakerLabel, DialogueText, choice container (4 choice slots), and ContinuePrompt — all using LoFiText3D for retro pixel-style rendering

### Key Architecture Decisions (Issue #52)

- **Dual display paths**: 2D UI panel (`DialoguePanel`) for editor/fallback; 3D display (`Dialogue3D`) as the primary in-game visual layer
- **Hemingway text enforcer**: Short, punchy dialogue enforced via `HemingwayEnforcer` — domain-aware limits (5 text types), CJK sentence delimiter support, smart word-boundary truncation. See §7 for full constraint table.
- **Signal-driven updates**: `DialogueDisplay3D` listens to `DialogueRunner` signals (`node_changed`, `choices_available`, `dialogue_ended`) rather than polling or being directly driven by the runner

## 5. Runtime Enhancements (Issue #52)

### DialogueRunner Extensions

| Feature | Description |
|---------|-------------|
| `state_provider` callable | Test hook for injecting custom GameState snapshots without GameManager autoload |
| Lazy-load via `load_dialogue()` | Load dialogue from file path, returns bool success |
| Extended effect types | `trigger_event` and `advance_clock` (both placeholder with warning) |
| `get_last_reachable_count()` | Returns reachable choice count — used by debug overlay and tests |

### KineticNovel / Hemingway Text Enforcer (`gdscripts/hemingway_enforcer.gd`)

- Extends `RefCounted` — pure utility, no scene attachment
- `truncate(text)` → dictionary with `truncated_text`, `original_text`, `was_truncated`, `original_sentence_count`, `original_max_sentence_length`
- Enforces 3-sentence max, 25-char-per-sentence max with trailing punctuation removal and ellipsis replacement
- Null/empty/type-safe handling for testability

### Visual Display (`gdscripts/dialogue_display_3d.gd`)

- Extends `Node3D` with `class_name DialogueDisplay3D` for editor usability
- 3D billboarded labels for speaker name, dialogue text, and up to 4 choices
- Choice navigation: `navigate_up()`, `navigate_down()`, `get_focused_choice_index()`, `highlight_choice(index)` with amber emissive focus highlighting
- Animated fade-out on dialogue end via `Tween` (0.3s duration)
- Reveal delay (0.5s) before choices appear
- `_prefix_letter()` static helper maps choice indices to A/B/C/D prefixes

### Input Mapping (Issue #52 — main.gd)

| Action | Key | Effect |
|--------|-----|--------|
| `toggle_dialogue` | F9 | Start a test dialogue |
| `dialogue_up` | Arrow Up | Navigate choice focus up |
| `dialogue_down` | Arrow Down | Navigate choice focus down |
| `dialogue_select` | Space/Enter | Select focused choice |
| `dialogue_skip` | (placeholder) | Skip typewriter animation |
| `digit_1`–`digit_4` | 1–4 | Direct choice selection |

## 6. Constants & Limits

| Constant | Value | Context |
|----------|-------|---------|
| `MAX_NODE_VISITS` | 3 | Anti-loop per-node visit limit |
| Slider range (hope_despair) | [-10, +10] | Bipolar hope/despair axis (Issue #50) |
| Slider range (hope, conviction, will) | [0, 10] | Legacy axis ranges |
| Text reveal | 30ms/char | Typewriter effect (skippable) |
| Max visible choices | 4 | UI layout constraint |

## 7. Hemingway Writing Constraints (Issue #51)

### 7.1 Domain-Specific Limits

The `HemingwayEnforcer` (`gdscripts/hemingway_enforcer.gd`) enforces per-domain limits:

| Domain | Max Sentences | Max Chars/Sentence | Rationale |
|--------|---------------|--------------------|-----------|
| `narration` | 3 | 25 | Narrator text; 3-line Haiku format dominant |
| `dialogue` | 1 | 25 | Spoken NPC lines; one breath per utterance |
| `signage` | 1 | 15 | Environmental text; pixel font illegible above ~15 glyphs |
| `choice_text` | 1 | 30 | Player choices; `"(A) "` prefix consumes 4 chars |
| `echo_variant` | 1 | 25 | Echo system text (same as dialogue) |

### 7.2 Sentence Delimiters

- **English**: `. ! ?` followed by space, newline, tab, or end-of-string
- **CJK**: `。！？` — split unconditionally (no space required)
- **Not delimiters**: `…` (ellipsis, U+2026), `——` (em dash)

### 7.3 CJK Support

Chinese text is detected via Unicode range (U+4E00–U+9FFF). CJK sentences have no word-boundary search during truncation — character-level cut is used instead. `String.length()` in GDScript 4 correctly counts Unicode code points.

### 7.4 Truncation Metadata

When truncation occurs:
- `dialogue_text.set_meta("hemingway_truncated", true)` — truncation indicator
- `dialogue_text.set_meta("hemingway_original", result["original_text"])` — original preserved in metadata
- Editor warning via `push_warning()` with full truncation detail

### 7.5 Python Validator

`scripts/validate_hemingway.py` provides pre-commit and CI validation of dialogue JSON and GDScript files against the same constraints. Features:
- Auto-discovery of `dialogues/*.json` and `gdscripts/*.gd`
- `--fix` flag for in-place auto-truncation
- `--report` flag for markdown violation report
- Exit code 0 = all clean, 1 = violations found

Optional pre-commit hook at `.pre-commit-config.yaml`.

## 8. Slider Axis Reference (Issue #50)

All dialogue condition `axis` values:

| Axis | Range | Description |
|------|-------|-------------|
| `hope_despair` | -10 ~ +10 | Unified bipolar slider (Issue #50) — primary axis for 5-state system |
| `hope` | 0 ~ 10 | Derived from hope_despair, backward compat |
| `conviction` | 0 ~ 10 | Independent axis |
| `will` | 0 ~ 10 | Independent axis |

### 8.1 5-State Condition Patterns

NPC attitude gating example using `hope_despair`:

```json
{
  "text": "「今天过得不好。」",
  "condition": {
    "type": "slider",
    "axis": "hope_despair",
    "op": "lte",
    "value": -2.0
  }
}
```

### 8.2 Disabled Gating (Issue #50)

Choices that don't meet slider conditions should be **grayed out** (not hidden), with tooltip "You don't feel like saying this right now." This maintains player awareness of missed content.

---

## 9. NPC Framework (Issue #54)

> Implemented: 2026-07-23 (PR #127)
> Files: `gdscripts/npc_node.gd` (class_name NPCNode), `scenes/components/NPC.tscn`

### 9.1 Overview

The NPC Framework provides a **reusable drop-in component** (`NPC.tscn` + `npc_node.gd`) for all NPC interactions. Each NPC is a `Node3D` child in its scene with `@export` properties for dialogue configuration, state machine parameters, and personality layers.

Previously, each scene re-implemented the interaction loop (Area3D trigger → signal wiring → `dialogue_runner.start()`). Now all interaction logic is encapsulated in `NPCNode`, and scenes only need to place an `NPC.tscn` instance and configure its exports.

### 9.2 Architecture

```
NPC.tscn (Node3D)
├── InteractionTrigger (Area3D)
│   └── CollisionShape3D (CylinderShape3D)
├── VisualName (Label3D) — billboarded name tag
├── InteractionPrompt (Label3D) — billboarded prompt text
└── CooldownTimer (Timer) — post-dialogue cooldown
```

### 9.3 NPCNode State Machine

The `NPCNode` script implements a 5-state machine referenced via `enum NPCState`:

| State | Value | Meaning | Interactable? |
|-------|-------|---------|---------------|
| `IDLE` | 0 | Waiting for player interaction | ✅ Yes |
| `TALKING` | 1 | Dialogue in progress | ❌ No |
| `COOLDOWN` | 2 | Post-dialogue cooldown timer | ❌ No |
| `EXHAUSTED` | 3 | All dialogue branches visited, terminal | ❌ No |
| `SPECIAL` | 4 | Reserved for contextual states | ❌ No |

**Transition cycle:**
```
IDLE → (player clicks) → TALKING → (dialogue ends) → COOLDOWN → (timer)
                                                              ├── → IDLE (unvisited branches remain)
                                                              └── → EXHAUSTED (all visited, terminal)
```

**Key signals:**
| Signal | Parameters | Description |
|--------|-----------|-------------|
| `npc_interacted` | `npc_id: String` | Emitted when player clicks the NPC |
| `dialogue_completed` | `npc_id: String` | Emitted after dialogue ends |
| `npc_state_changed` | `state: int` | Emitted on every state transition |

### 9.4 Personality Layers

Each NPC can define a `personality_layers: Array[Dictionary]` exported array. Each layer has:

| Field | Type | Description |
|-------|------|-------------|
| `name` | String | Layer identifier (e.g. `"tired_worker"`) |
| `condition` | Dictionary | Condition DSL dict (same format as dialogue branch conditions) |
| `name_prefix` | String | Optional prefix prepended to `speaker_name` when layer is active |
| `greeting_override` | String | Optional dialogue node ID to use as entry point instead of `entry_node_id` |

**Evaluation order:**
1. Condition-based layers are evaluated in array order — first match wins.
2. The `"always"` condition type (or empty condition) is treated as a **fallback** — evaluated last even if defined earlier.
3. If no conditional layer matches and no fallback exists, `active_layer` remains empty.

### 9.5 Exported Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `dialogue_file` | String | `""` | Path to dialogue JSON |
| `dialogue_id` | String | `""` | Dialogue ID (for branch tracking) |
| `speaker_name` | String | `"NPC"` | Base name shown on label |
| `mood_axis` | String | `"hope_despair"` | Axis used for state snapshot |
| `proximity_distance` | float | `3.0` | Cylinder trigger radius |
| `cooldown_seconds` | float | `2.0` | Post-dialogue cooldown duration |
| `name_label_visible` | bool | `true` | Whether name label shows |
| `interaction_prompt_text` | String | `"⌈Talk⌋"` | Prompt label text |
| `personality_layers` | Array[Dict] | `[]` | Personality layer definitions |
| `label_offset` | Vector3 | `(0, 1.5, 0)` | Label position offset |

### 9.6 DialogueRunner Extensions (for NPC support)

| Feature | Description |
|---------|-------------|
| `start(file, id, greeting_override)` | Third optional parameter to override entry_node_id — used by personality layers |
| `has_unvisited_branches(dialogue_id)` | Returns true if any terminal dialogue nodes remain unvisited — used by cooldown state machine logic |

### 9.7 Constants (Issue #54 additions to `constants.gd`)

```gdscript
const NPC_DEFAULT_PROXIMITY: float = 3.0
const NPC_DEFAULT_COOLDOWN: float = 2.0
const NPC_LABEL_OFFSET: Vector3 = Vector3(0, 1.5, 0)

# Office exit flags
const FLAG_OFFICE_EXIT_SIGH: String = "office_exit_sigh"
const FLAG_OFFICE_EXIT_NEUTRAL: String = "office_exit_neutral"
const FLAG_OFFICE_EXIT_DETERMINED: String = "office_exit_determined"

# Clerk dialogue path
const DIALOGUE_STORE_CLERK_EXPANDED: String = "res://dialogues/store_clerk.json"
```

### 9.8 E-Key Activation Path (Issue #152)

> Implemented: 2026-07-23 (PR #182)
> Files: `gdscripts/npc_node.gd`, `scenes/street/street.tscn`, `gdscripts/street.gd`

The NPC Framework originally supported only mouse-click (`input_event`) activation. Issue #152 added a **programmatic activation path** via `start_npc_interaction()` that enables the E-key interaction pathway:

| Addition | File | Description |
|----------|------|-------------|
| `start_npc_interaction()` | `npc_node.gd` | Public method mirroring the core activation block of `_on_interaction()` without requiring an InputEvent |
| Test NPC instance | `street.tscn` | NPC.tscn placed at `InteractionZones/TestNPC` (position `(4, 0, 0)`) with EKeyTrigger child |
| Wiring handler | `street.gd` | `_on_test_npc_interact()` connects `EKeyTrigger.e_key_interacted` → `NPCNode.start_npc_interaction()` |
| Test dialogue | `dialogues/npc_test.json` | 2-node Hemingway-conforming test dialogue (speaker: "???") |
| Constant | `constants.gd` | `DIALOGUE_NPC_TEST: String = "res://dialogues/npc_test.json"` |

**Activation flow:**

```
Player presses E → PlayerController._try_interact()
                     ↓ pops from LIFO stack
                  interaction_requested.emit(EKeyTrigger)
                     ↓
                  SceneBase._on_player_interaction(target)
                     ↓ has_method("start_npc_interaction")?
                  → NPCNode.start_npc_interaction()
                       ↓ is_interactable() guard
                    evaluate_personality_layer()
                    set_state(NPCState.TALKING)
                    _dialogue_runner.start(...)
```

**Key design decisions:**
- `start_npc_interaction()` mirrors `_on_interaction()` exactly — same state transitions, personality evaluation, and dialogue call — without needing an InputEvent
- `is_interactable()` guard prevents both paths (mouse-click and E-key) from activating simultaneously
- The EKeyTrigger is a child of `InteractionTrigger` Area3D (sharing its CollisionShape3D), not a sibling — ensuring both proximity detection and E-key range match
- SceneBase already had the `has_method("start_npc_interaction")` routing since PR #149, so only the method addition on NPCNode was needed

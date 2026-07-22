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
| Slider range | [1, 10] | All six slider axes |
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

# DESIGN: #52 — Dialogue Engine — Runtime + Visual Presentation

> Parent Issue: #52
> Agent: plan-agent
> Date: 2026-07-22
> Depth: standard

---

## 1. Architecture Overview

### Core Idea

Create a **DialogueDisplay3D** controller that listens to `DialogueRunner` signals and renders dialogue text + choices in 3D world space using existing `LoFiText3D` components. A dedicated **HemingwayEnforcer** static utility provides runtime text truncation (max 25 chars/sentence, max 3 sentences) before display.

This implements **Approach A** from the PRD: a dedicated 3D Dialogue Display Controller that separates concerns — DialogueRunner handles logic (traversal, condition evaluation, effects), DialogueDisplay3D handles rendering (LoFiText3D labels, choice navigation, focus highlight).

### Data Flow

```
Player Input (keyboard)
    │
    ▼
main.gd _input(event)
    │
    ├──► dialogue_up / dialogue_down → navigate choice focus
    ├──► dialogue_select → select current choice (Enter/Space)
    └──► digit 1–4 → direct choice selection
            │
            ▼
    DialogueRunner.select_choice(index)
            │
            ├──► Applies effects (slider_delta, set_flag) → GameManager
            ├──► Emits choice_made signal
            └──► Calls enter_node(next_node_id)
                    │
                    ▼
    DialogueRunner.enter_node(node_id)
            │
            ├──► Evaluates conditions → produces reachable choices
            ├──► Emits node_changed(speaker, text)
            ├──► Emits choices_available(choices)
            │
            ▼
    DialogueDisplay3D (listens to signals)
            │
            ├──► HemingwayEnforcer.truncate(text)
            ├──► Set speaker_label.text = speaker_name
            ├──► Set dialogue_text.text = truncated_text
            ├──► Reuse/update pre-allocated LoFiText3D choice labels
            └──► Apply emissive highlight to focused choice
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Text rendering | LoFiText3D (Label3D + shader) | Matches GDD's 3D text direction; uses existing #44 asset |
| Display architecture | Dedicated Node3D controller | Clean separation from DialogueRunner (logic stays pure) |
| Choice label lifecycle | Pre-allocated pool of 4, reuse by hide/show | Avoids instantiation overhead every node transition |
| Focus indicator | `emissive_strength` (0.0 dim / 3.0 bright) + "→" prefix | Leverages Glow pass; visually consistent with neon aesthetic |
| Reveal timing | Two-stage: text appears first, then choices (0.5s delay) | Better pacing — player reads text before deciding |
| Input scheme | Arrow keys + Enter/Space + number keys (1–4) | Keyboard-first CRPG design; no mouse required |
| Input routing | `main.gd` handles input, calls display methods | Keeps input handling in a single, testable location |
| Hemingway truncation | Separate static utility class | Pure function, easily testable in --script mode |
| Camera behavior | Free camera during dialogue | Billboard text handles any angle; preserves player agency |
| Single conversation | DialogueDisplay3D is a singleton-like per-scene instance | Only one NPC conversation active at a time |

### Scene Hierarchy

```
Main (Node3D)
├── WorldLabel (Label3D)
├── Camera3D
├── UI (CanvasLayer)
├── Dialogue (CanvasLayer)
│   └── DialoguePanel (Panel) — existing 2D panel, kept as fallback
├── Dialogue3D (Node3D) — NEW: DialogueDisplay3D script
│   ├── SpeakerLabel (LoFiText3D) — amber emissive, billboarded
│   ├── DialogueText (LoFiText3D) — white, larger font, billboarded
│   ├── ChoiceContainer (Node3D) — holds pre-allocated choice labels
│   │   ├── Choice0 (LoFiText3D) — pre-allocated
│   │   ├── Choice1 (LoFiText3D) — pre-allocated
│   │   ├── Choice2 (LoFiText3D) — pre-allocated
│   │   └── Choice3 (LoFiText3D) — pre-allocated
│   └── ContinuePrompt (LoFiText3D) — hidden by default
└── DialogueDebug (CanvasLayer)
```

---

## 2. Node / Scene Tree Layer

### New Scene: `scenes/dialogue/dialogue_display_3d.tscn`

A Node3D scene with the DialogueDisplay3D script attached. Contains:
- **SpeakerLabel** (LoFiText3D): positioned at `y=0.8` above root, amber emissive (`#FFB000`), `emissive_strength=3.0`, `billboard=true`, `horizontal_alignment=Center`
- **DialogueText** (LoFiText3D): positioned at `y=0.4` (below speaker), white text, `font_size=48` (use `pixel_size` if Label3D property), `billboard=true`
- **ChoiceContainer** (Node3D): positioned at `y=-0.1`, empty container for choice labels
- 4 pre-allocated **LoFiText3D** choice labels as children of ChoiceContainer: positioned at `y = -0.3 - index * 0.25`, dimmed by default (`emissive_strength=0.0`)
- **ContinuePrompt** (LoFiText3D): positioned at `y=-1.5`, small text, hidden (`visible=false`)

Speaker and dialogue text are always visible while active. Choice labels toggle `visible` based on available count (1–4).

### Existing Scene Changes: `scenes/main.tscn`

Add a new child node:
```
[node name="Dialogue3D" type="Node3D" parent="."]
position = Vector3(0, 1.5, -3)  # Offset from camera, visible in world space
script = ExtResource("res://gdscripts/dialogue_display_3d.gd")
```

The existing `Dialogue/DialoguePanel` (2D CanvasLayer) is kept as a fallback and debug view but hidden by default — the 3D display becomes primary for gameplay.

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/hemingway_enforcer.gd`

A `RefCounted` static utility class for text truncation.

```gdscript
extends RefCounted
class_name HemingwayEnforcer

const MAX_SENTENCES := 3
const MAX_CHARS_PER_SENTENCE := 25

# Returns { truncated_text, original_text, was_truncated,
#           original_sentence_count, original_max_sentence_length }
static func truncate(text: String) -> Dictionary:
    pass  # Implementation in implement phase

static func _split_sentences(text: String) -> PackedStringArray:
    pass

static func _truncate_sentence(sentence: String) -> String:
    pass
```

**Logic:**
1. Split text on sentence boundaries (`.`/`!`/`?` followed by space or end-of-string)
2. If >3 sentences, truncate to first 3 and append `"…"`
3. For each sentence, if >25 chars, truncate at last word boundary within limit and append `"…"`
4. Return result dictionary with truncation metadata

### New Script: `gdscripts/dialogue_display_3d.gd`

The core 3D display controller. Extends `Node3D`.

**Exported variables:**
- `@export var max_choices: int = 4`
- `@export var choice_spacing: float = 0.25`
- `@export var emissive_focus: float = 3.0` — emissive strength for focused choice
- `@export var emissive_dim: float = 0.0` — emissive strength for unfocused choices
- `@export var reveal_delay: float = 0.5` — delay before choices appear
- `@export var fade_duration: float = 0.3` — fade-out duration on dialogue end

**Node references (@onready):**
- `speaker_label: LoFiText3D` — `$SpeakerLabel`
- `dialogue_text: LoFiText3D` — `$DialogueText`
- `choice_container: Node3D` — `$ChoiceContainer`
- `continue_prompt: LoFiText3D` — `$ContinuePrompt`
- `_choice_labels: Array[LoFiText3D]` — pre-loaded children of choice_container

**Internal state:**
- `_focused_index: int = 0`
- `_is_active: bool = false`
- `_current_choices: Array = []`

**Methods:**

| Method | Signature | Purpose |
|--------|-----------|---------|
| `_ready()` | `-> void` | Collect choice label references, hide all initially |
| `show_dialogue()` | `-> void` | Make root visible, reset state |
| `hide_dialogue()` | `-> void` | Animate emissive_strength → 0, then hide root |
| `on_node_changed(node_id, speaker, text)` | `(String, String, String) -> void` | Update speaker + dialogue text labels with Hemingway truncation |
| `on_choices_available(choices)` | `(Array) -> void` | Populate/reuse choice labels, highlight first, show after reveal_delay |
| `on_dialogue_ended()` | `-> void` | Fade out and hide all labels |
| `navigate_up()` | `-> void` | Decrement focus index (wrap to last), call highlight_choice |
| `navigate_down()` | `-> void` | Increment focus index (wrap to 0), call highlight_choice |
| `get_focused_choice_index()` | `-> int` | Return current _focused_index |
| `highlight_choice(index)` | `(int) -> void` | Dim all choices, brighten the selected one, set `→` prefix |
| `setup_choice_pool()` | `-> void` | Collect pre-allocated LoFiText3D children of ChoiceContainer |

**Signal wire-up (called from main.gd or via direct connect):**
```
dialogue_runner.node_changed.connect(dialogue_display_3d.on_node_changed)
dialogue_runner.choices_available.connect(dialogue_display_3d.on_choices_available)
dialogue_runner.dialogue_ended.connect(dialogue_display_3d.on_dialogue_ended)
```

### Modified Script: `gdscripts/main.gd`

**New @onready:**
```gdscript
@onready var dialogue_display_3d: Node3D = $Dialogue3D
@onready var dialogue_runner_ref: Node = $Dialogue/DialoguePanel
```

**New state variable:**
```gdscript
var _dialogue_active: bool = false
```

**New signal connections in _ready():**
```gdscript
dialogue_runner_ref.node_changed.connect(dialogue_display_3d.on_node_changed)
dialogue_runner_ref.choices_available.connect(dialogue_display_3d.on_choices_available)
dialogue_runner_ref.dialogue_ended.connect(dialogue_display_3d.on_dialogue_ended)
```

**New input handling blocks in _input():**
```gdscript
elif event.is_action_pressed("dialogue_skip"):
    if _dialogue_active:
        # Skip typewriter animation (future feature)
        pass
```

Replace existing F9 dialogue trigger with:
```gdscript
elif event.is_action_pressed("toggle_dialogue"):
    if dialogue_runner_ref != null:
        dialogue_runner_ref.show()
        dialogue_runner_ref.start("res://dialogues/bartender.json", "bartender")
        _dialogue_active = true
        dialogue_display_3d.show_dialogue()
```

**Updated _on_dialogue_ended():**
```gdscript
func _on_dialogue_ended() -> void:
    print("Dialogue ended")
    _dialogue_active = false
    if dialogue_runner_ref != null and is_instance_valid(dialogue_runner_ref):
        dialogue_runner_ref.hide()
```

### Modified Script: `gdscripts/dialogue_runner.gd`

**Add method (needed by dialogue_debug.gd):**
```gdscript
var _last_reachable_count: int = 0

# In enter_node(), after filtering reachable:
# _last_reachable_count = reachable.size()

func get_last_reachable_count() -> int:
    return _last_reachable_count
```

Also return reachable choice count at the end of `enter_node()`.

---

## 4. Resource / Config Layer

### New Input Map Actions in `project.godot`

Add under `[input]`:

| Action Name | Binding | Purpose |
|-------------|---------|---------|
| `dialogue_up` | Arrow Up | Navigate choice focus up |
| `dialogue_down` | Arrow Down | Navigate choice focus down |
| `dialogue_select` | Enter / Space | Select highlighted choice |
| `dialogue_skip` | Escape | Skip typewriter animation |

Format:
```
dialogue_up={
"deadzone": 0.5,
"events": [{"keycode": 4194319, "type": 0}]
}
dialogue_down={
"deadzone": 0.5,
"events": [{"keycode": 4194321, "type": 0}]
}
dialogue_select={
"deadzone": 0.5,
"events": [{"keycode": 4194306, "type": 0}, {"keycode": 32, "type": 0}]
}
dialogue_skip={
"deadzone": 0.5,
"events": [{"keycode": 4194305, "type": 0}]
}
```

### LoFiText3D Parameters Per Label

| Label | pixel_factor | color_bits | emissive_color | emissive_strength | Billboard |
|-------|-------------|-----------|----------------|-------------------|-----------|
| SpeakerLabel | 0.3 | 8 | `#FFB000` (amber) | 3.0 | true |
| DialogueText | 0.2 | 16 | `#000000` (none) | 0.0 | true |
| Choice (focused) | 0.3 | 8 | `#FFB000` (amber) | 3.0 | true |
| Choice (dimmed) | 0.3 | 8 | `#000000` (none) | 0.0 | true |
| ContinuePrompt | 0.3 | 8 | `#808080` (grey) | 0.5 | true |

---

## 5. Asset / Visual Layer

### Speaker Label Visual Treatment

- Amber emissive (`#FFB000` | `Color(1.0, 0.69, 0.0)`)
- `emissive_strength=3.0` — triggers WorldEnvironment Glow pass for neon effect
- Billboard mode: always faces camera
- Font scale: 32px equivalent (pixel font 8×8 scaled 4×)
- Truncation: max 20 chars with `"…"` if speaker name exceeds

### Dialogue Text Visual Treatment

- White text (`#FFFFFF` | `Color(1.0, 1.0, 1.0)`)
- No emissive glow
- Billboard mode: always faces camera
- Font scale: 48px equivalent (pixel font 8×8 scaled 6×)
- Hemingway-enforced: max 25 chars/sentence, 3 sentences max

### Choice Labels Visual Treatment

- **Focused:** `→` prefix text, amber emissive (`emissive_strength=3.0`), full color
- **Unfocused:** dimmed (no emissive), `emissive_strength=0.0`, greyish text tint
- Billboard mode: always face camera
- Font scale: 28px equivalent
- Format: `→ (A) Choice text` for focused, `(B) Choice text` for unfocused
- Prefix letter: `(A)` through `(D)` for choices 1–4

### Fade-Out Animation

On `dialogue_ended`:
1. Scheduler tween to animate `emissive_strength` → 0.0 on all labels (0.3s)
2. After tween completes, set `visible = false` on root

---

## 6. Input / UI Layer

### Keyboard Navigation

| Key | Action | Behavior |
|-----|--------|----------|
| Arrow Up | `dialogue_up` | Decrement focus index (wrap to last at 0); call `highlight_choice()` |
| Arrow Down | `dialogue_down` | Increment focus index (wrap to 0 at max); call `highlight_choice()` |
| Enter | `dialogue_select` | Call `DialogueRunner.select_choice(focused_index)` |
| Space | `dialogue_select` | Same as Enter |
| 1–4 | N/A | Direct `DialogueRunner.select_choice(digit-1)` — bypass focus |
| Escape | `dialogue_skip` | Skip typewriter animation (placeholder) |

### Focus Wrapping Logic

```gdscript
func navigate_up() -> void:
    if not _is_active or _current_choices.is_empty():
        return
    _focused_index = (_focused_index - 1 + _current_choices.size()) % _current_choices.size()
    highlight_choice(_focused_index)

func navigate_down() -> void:
    if not _is_active or _current_choices.is_empty():
        return
    _focused_index = (_focused_index + 1) % _current_choices.size()
    highlight_choice(_focused_index)
```

### Choice Highlight Mechanism

```gdscript
func highlight_choice(index: int) -> void:
    for i in range(_choice_labels.size()):
        var label: LoFiText3D = _choice_labels[i]
        if i >= _current_choices.size() or i >= max_choices:
            label.visible = false
            continue
        label.visible = true
        if i == index:
            label.emissive_strength = emissive_focus  # 3.0
            label.text = "→ (%s) %s" % [_prefix_letter(i), _current_choices[i].get("text", "")]
        else:
            label.emissive_strength = emissive_dim  # 0.0
            label.text = "(%s) %s" % [_prefix_letter(i), _current_choices[i].get("text", "")]
```

Where `_prefix_letter(i)` maps 0→"A", 1→"B", 2→"C", 3→"D".

---

## 7. Test Layer

All test case descriptions — implement agent writes runnable tests.

### Normal Path Tests (≥2)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| T1 | Display text from dialogue node | Create DialogueDisplay3D, call `on_node_changed("n_01", "Bartender", "You again.")` | SpeakerLabel shows "Bartender", DialogueText shows "You again." | `assert(speaker_label.text == "Bartender")`, `assert(dialogue_text.text == "You again.")` |
| T2 | Display choices and navigate | After `on_choices_available(3 choices)`, call `navigate_down()` then `navigate_down()` | Focus index becomes 2; choice 2 highlighted, choices 0–1 dimmed | `assert(focused_index == 2)`, `assert(choice_labels[2].emissive_strength == 3.0)`, `assert(choice_labels[0].emissive_strength == 0.0)` |
| T3 | Choice selection via focused index | Navigate to index 1, call `get_focused_choice_index()` then `select_choice` | Returns 1 | `assert(get_focused_choice_index() == 1)` |

### Boundary / Edge Case Tests (≥3)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| T4 | Hemingway truncation: >3 sentences | `"First. Second. Third. Fourth."` | Result is `"First. Second. Third.…"` with `was_truncated=true` | `assert(result.truncated_text == "First. Second. Third.…")`, `assert(result.was_truncated)` |
| T5 | Hemingway truncation: sentence >25 chars | `"This is a very long sentence that exceeds the twenty-five character limit."` | Sentence truncated at word boundary, `"…"` appended | `assert(result.truncated_text.length() <= 28)` (25 chars + "…") |
| T6 | Hemingway empty text | Empty string `""` | Returns empty text, `was_truncated=false` | `assert(result.truncated_text == "")`, `assert(not result.was_truncated)` |
| T7 | Focus wrapping: navigate up at index 0 | `navigate_up()` with 4 choices | Focus wraps to last index (3) | `assert(focused_index == 3)` |
| T8 | Focus wrapping: navigate down at last index | `navigate_down()` with 4 choices at index 3 | Focus wraps to index 0 | `assert(focused_index == 0)` |
| T9 | Fewer choices than max_choices | 2 choices available with `max_choices=4` | Only 2 labels visible, label[3] and label[4] hidden | `assert(choice_labels[0].visible)`, `assert(choice_labels[2].visible == false)` |
| T10 | Dialogue end fade-out | Call `on_dialogue_ended()` while active | All labels begin fade tween, then root hides | `assert(tween_running)` or `assert(visible == false after delay)` |

### Failure Path Tests (≥1)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| T11 | Hemingway enforcer receives null/non-string | `truncate(null)` | Returns empty text safely, no crash | `assert(result.truncated_text == "")` |
| T12 | Navigate with no choices | Call `navigate_down()` when `_current_choices` is empty | No-op, no crash | `assert(focused_index == 0)` |
| T13 | Choice select via index out of range | Call `select_choice(10)` when only 2 choices | DialogueRunner logs error, no state change | `assert(current_node_id unchanged)` |

### Debug Function Tests

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| T14 | DialogueRunner.get_last_reachable_count() | After `enter_node("start")` with 2 reachable choices | Returns 2 | `assert(runner.get_last_reachable_count() == 2)` |

---

## 8. Files Changed (per-layer summary)

| Layer | File | Change | Est. Lines |
|-------|------|--------|-----------|
| Script (New) | `gdscripts/hemingway_enforcer.gd` | New static utility: truncate(), _split_sentences(), _truncate_sentence() | +50 |
| Script (New) | `gdscripts/dialogue_display_3d.gd` | New Node3D controller: signal handlers, navigation, highlight, fade | +150 |
| Scene (New) | `scenes/dialogue/dialogue_display_3d.tscn` | New scene: SpeakerLabel, DialogueText, ChoiceContainer with 4 choice labels | +50 |
| Script (Mod) | `gdscripts/main.gd` | Add @onready, dialogue input handling in _input(), signal wiring | +40 |
| Scene (Mod) | `scenes/main.tscn` | Add Dialogue3D node (Node3D, DialogueDisplay3D script) | +5 |
| Config | `project.godot` | Add input map: dialogue_up, dialogue_down, dialogue_select, dialogue_skip | +20 |
| Script (Mod) | `gdscripts/dialogue_runner.gd` | Add get_last_reachable_count() method + _last_reachable_count tracking | +5 |

**Total estimated: ~320 lines**

---

## 9. Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Display approach | Approach A (Dedicated 3D Controller) | Per PRD recommendation — aligns with GDD 3D text direction, uses existing LoFiText3D, clean separation from logic |
| Choice lifecycle | Pre-allocated pool of 4 LoFiText3D labels | Avoids dynamic instantiation; 4 is hard max per design |
| Focus indicator | emissive_strength (0→3) + "→" prefix | Dual-cue (color + glyph) ensures readability from any camera angle |
| Two-stage reveal | Text first, choices after 0.5s delay | Reader processes dialogue text before being presented with options |
| Hemingway enforcer | Static RefCounted utility | Pure function, testable in --script mode, no scene dependency |
| 2D panel | Keep as fallback, hidden by default | Debug/dev use; no breaking change risk |
| Input handling | main.gd dispatches to DialogueDisplay3D | Single input dispatch point; no new autoloads needed |
| Fade-out | Tween emissive_strength → 0 over 0.3s | Visually consistent with neon glow theme; smooth transition |
| Camera | Free camera during dialogue | Billboard handles all angles; no disorienting camera lock |
| Single conversation | One DialogueDisplay3D root | Game state only supports one active NPC conversation |

---

## 10. Verification Checklist

- [ ] `HemingwayEnforcer.truncate()` returns correct Dictionary with all fields
- [ ] Hemingway truncation handles: >3 sentences truncation, per-sentence 25-char limit, empty text, single-sentence text
- [ ] `DialogueDisplay3D` updates speaker label correctly on `node_changed`
- [ ] `DialogueDisplay3D` updates dialogue text with Hemingway-truncated content
- [ ] Pre-allocated choice labels (4) show/hide based on available choice count
- [ ] Arrow Up/Down navigates choices with wrapping
- [ ] 1–4 number keys select choices directly
- [ ] Enter/Space selects focused choice
- [ ] Focused choice shows "→" prefix + emissive highlight
- [ ] Unfocused choices show letter prefix `(A)`–`(D)` without emissive
- [ ] Dialogue end triggers fade-out tween (0.3s)
- [ ] Choice navigation is a no-op when no dialogue is active
- [ ] Input map actions defined in `project.godot`
- [ ] `DialogueRunner.get_last_reachable_count()` returns correct count
- [ ] `dialogue_debug.gd` continues working with `get_last_reachable_count()`
- [ ] Existing `test_dialogue_engine.gd` tests still pass (regression check)

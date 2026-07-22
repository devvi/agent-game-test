# Research: Dialogue Engine — Runtime + Visual Presentation

> Parent Issue: #52
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

The dialogue engine currently has four core components implemented (Issue #46):

1. **DialogueParser.gd** — validates and loads JSON dialogue trees into dictionary format
2. **DialogueConditionEvaluator.gd** — stateless condition evaluator for slider (gte/lte/eq/gt/lt), flag, choice_made, and compound (AND/OR/NOT) conditions
3. **DialogueRunner.gd** — stateful runtime that handles node traversal, choice filtering by condition, anti-loop protection (MAX_NODE_VISITS = 3), effect application (slider_delta, set_flag, trigger_event, advance_clock), and signal emission (dialogue_started, dialogue_ended, node_changed, choices_available, choice_made)
4. **Legacy Resource classes** (DialogueNode.gd, DialogueBranch.gd, DialogueData.gd) — Resource-based data model, superseded by JSON-based approach

The lo-fi 3D text rendering system (Issue #44) provides a **LoFiText3D** component extending `Label3D` with configurable pixelation (`pixel_factor` 0–1), color depth (`color_bits` 2–24), scanline overlay (`scanline_intensity` 0–1), and emissive glow (`emissive_color` + `emissive_strength` 0–5).

The dialogue UI is currently a **2D Control-based Panel** (`scenes/dialogue/dialogue_panel.tscn`) with:
- `SpeakerLabel` (Label node)
- `DialogueText` (RichTextLabel with BBCode)
- `ChoiceContainer` (VBoxContainer for choice buttons)

The dialogue debug overlay (`dialogue_debug.gd`) toggled via F12 shows node ID, choice reachability, and GameState snapshot.

**What does NOT exist yet:**
- No 3D visual presentation of dialogue (the panel is 2D CanvasLayer-based)
- No 3D floating dialogue text using LoFiText3D in world space
- No keyboard input handling for dialogue traversal (arrow keys for choice navigation, Enter/Space to select)
- No Hemingway constraint enforcement at runtime (max 25 chars/sentence, max 3 sentences)
- No integration between DialogueRunner and LoFiText3D for rendering
- No choice indicator/selector in 3D space (hover/highlight for which choice is focused)

### Expected Behavior

The runtime system should:

1. **Render dialogue text in 3D space** — NPC speech appears as a LoFiText3D label positioned above the NPC, with lo-fi aesthetic applied (pixelation, reduced color depth, optional emissive glow for speaker names)
2. **Display choices as 3D floating labels** — reachable choices appear as a vertical list of LoFiText3D labels in world space, with the currently focused choice highlighted (e.g., brighter emissive or arrow indicator)
3. **Accept keyboard input** — Arrow Up/Down navigates choices, Enter/Space selects, keyboard shortcuts (1–4) jump to choice
4. **Enforce Hemingway constraints** — text exceeding 25 chars/sentence or 3 sentences is truncated with "…" appended; authors warned at editor time
5. **Trigger GameState updates** — DialogueRunner's existing effect system applies slider deltas and flag toggles on choice selection, which propagate to the game world via state_changed signals
6. **Integrate with lo-fi aesthetic** — use the existing LoFiText3D scene for all dialogue text, matching the game's visual language

### User Scenarios

- **Scenario A (Player/NPC interaction):** Player walks up to the Bartender NPC. Dialogue text appears in 3D space above the NPC — a LoFiText3D label reading *"You again. Same as usual?"* in pixelated amber. Three choices float below: "(A) Yeah, the usual" (highlighted), "(B) Not tonight", "(C) ...". Player presses Down to navigate to choice B, then Enter to select. The dialogue advances, and the player's Hope slider ticks down.

- **Scenario B (Hemingway truncation):** A dialogue node contains text *"I remember the night we first came here. It was raining hard, and you said this city could never be our home."* (exceeds 3 sentences). The runtime truncates to *"I remember the night we first came here. It was raining hard, and you said this city could never be our home."* → truncated to first 3 sentences with "…" appended.

- **Scenario C (State-gated choices):** Player has Despair=8, Conviction=3. The current dialogue node has 4 choices, but two are gated behind `despair < 5` conditions. Only 2 choices are shown. The player selects one, triggering `{"type": "slider_delta", "axis": "hope", "delta": -1}` — the game world updates immediately (rain intensifies, environment text changes).

- **Frequency:** Every NPC interaction (5+ NPCs across 7+ scenes) — this is the primary gameplay loop.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The dialogue engine was built in layers: first the data model and parser (Issue #46), then the runtime logic (same issue). The visual presentation was intentionally deferred to Issue #52 because:

1. **Separation of concerns:** The data model and runtime can be developed and tested entirely in headless mode (—script tests). The visual layer requires scene integration and 3D rendering.
2. **Dependency order:** Issue #44 (Lo-Fi 3D Text) needed to be implemented first to provide the rendering component. Issue #49 (Text Component Library) is a dependency for the choice display system.
3. **Input system maturity:** The existing `main.gd` has placeholder input handling (F9 triggers dialogue, keyboard changes state). A proper dialogue-specific input scheme needs dedicated design.

### Why Change Now?

1. **MVP completeness:** The dialogue engine is functionally complete at the data/runtime level but invisible to the player. Without the 3D presentation layer, the game has no actual NPC conversations.
2. **Dependency chain resolved:** Issue #44 (Lo-Fi 3D Text) is complete. Issue #49 (Text Component Library) is the next dependency — but the runtime can be built using LoFiText3D directly and migrated to the library later.
3. **Playtesting blocking:** All subsequent features (Issues #53 — UI System, #54 — NPC Framework, #55 — Office → Street scene) depend on the dialogue runtime being visually functional.
4. **Hemingway enforcement gap:** The Writing Constraints design (Issue #51) defines max 25 chars/sentence, max 3 sentences. Without runtime enforcement, long text will break the lo-fi aesthetic (Label3D with pixel font is unreadable at high character counts).

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 |
| Renderer | `forward_plus` with Glow pass enabled |
| Resolution | 1920×1080, Allow HiDPI |
| Theme | Edward Hopper urban night — warm/amber on dark/cool backgrounds |
| Writing style | Hemingway — max 25 chars/sentence, max 3 sentences |
| State system | Three slider axes (Hope/Conviction/Will), each 1–10 |
| Dialogue format | JSON-based, one file per NPC |
| Dialogue runtime | DialogueRunner with signal-based output |
| Text rendering | LoFiText3D (Label3D + lo-fi shader) |
| Pixel font | 8×8 bitmap font (assets/fonts/pixel_font.*) |
| Platform | macOS / Linux |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/dialogue_display_3d.gd` | 3D Dialogue Display | **New** — orchestration script that manages 3D text elements for dialogue |
| `scenes/dialogue/dialogue_display_3d.tscn` | 3D Dialogue Scene | **New** — scene with LoFiText3D nodes for text + choices |
| `gdscripts/hemingway_enforcer.gd` | Hemingway Enforcer | **New** — static utility for text truncation to 25 chars/sentence, 3 sentences |
| `gdscripts/main.gd` | Main Entry | **Extended** — wire DialogueRunner to 3D display, add dialogue-specific input handling |
| `scenes/main.tscn` | Main Scene | **Extended** — add DialogueDisplay3D node, connect to DialogueRunner |
| `gdscripts/dialogue_runner.gd` | Dialogue Runner | **Extended** — add `get_last_reachable_count()` method (needed by debug overlay), add state-provider getter |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `scenes/dialogue/dialogue_panel.tscn` | 2D Dialogue Panel | May be deprecated or repurposed as fallback/debug view |
| `scenes/dialogue/dialogue_debug_overlay.tscn` | Debug Overlay | Should continue working via DialogueRunner signals |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | GDD | Must document 3D presentation system |
| `docs/DESIGN/52-dialogue-engine-runtime-visual.md` | Design Doc | Plan phase output |
| `tests/` | Tests | New tests for Hemingway enforcer, 3D display logic |
| `dialogues/*.json` | Dialogue Data | Existing files need Hemingway compliance check |
| Issue #53 — UI System | UI | Dialogue choices are now 3D (not CanvasLayer); UI system must account for this |
| Issue #54 — NPC Framework | NPC | NPC scenes will need DialogueDisplay3D child nodes |

### Data Flow Impact

```
Player Input (keyboard)
    │
    ▼
main.gd _input(event)
    │
    ├──► Arrow Up/Down → navigate choice focus index
    ├──► Enter/Space → select current choice
    └──► 1–4 → direct choice selection
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
            ├──► Get speaker + text → HemingwayEnforcer.truncate(text)
            ├──► Set speaker_label.text = speaker_name
            ├──► Set dialogue_text.text = truncated_text (LoFiText3D)
            ├──► For each reachable choice:
            │       ├──► Create LoFiText3D choice label
            │       └──► Apply emissive highlight to focused choice
            │
            ▼
    GameState updates (via effects)
            │
            ▼
    World environment responds (rain, signs, etc.)
```

### Documents to Update

- [x] **This output:** `docs/PRD/52-dialogue-engine-runtime-visual-presentation.md`
- [ ] `docs/DESIGN/52-dialogue-engine-runtime-visual.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Add 3D presentation architecture
- [ ] `docs/GAME_DESIGN/INDEX.md` — Update index

---

## 4. Solution Comparison

### Approach A: Dedicated 3D Dialogue Display Controller (DialogueDisplay3D)

**Description:**
Create a `DialogueDisplay3D` script + scene that listens to DialogueRunner signals and manages a set of LoFiText3D nodes in world space. The scene hierarchy:

```
DialogueDisplay3D (Node3D)
├── SpeakerLabel (LoFiText3D)    — NPC name, emissive amber
├── DialogueText (LoFiText3D)    — main dialogue text, large font
├── ChoiceContainer (Node3D)
│   ├── Choice0 (LoFiText3D)     — "→ (A) Yeah, the usual" (highlighted)
│   ├── Choice1 (LoFiText3D)     — "(B) Not tonight"
│   ├── Choice2 (LoFiText3D)     — "(C) ..."
│   └── ... (up to 4 max)
└── ContinuePrompt (LoFiText3D)  — "▼ Press Space" (cycles during typewriter)
```

- `DialogueDisplay3D` is positioned relative to the speaking NPC (set via `global_transform.origin` or as child of NPC node)
- Billboard mode: all labels face camera
- Focused choice gets emissive highlight + arrow prefix, others are dimmed
- Keyboard input handled by `main.gd` and forwarded via signals/method calls
- Hemingway truncation applied before setting `DialogueText.text`
- Choice labels are dynamically created/destroyed on each `choices_available` signal

**Pros:**
- Single point of control — all 3D dialogue rendering logic in one script
- Clean separation from DialogueRunner (which remains purely logic)
- LoFiText3D provides the exact aesthetic out of the box
- Billboard mode ensures readability from any camera angle
- Dynamic choice creation matches variable choice count (1–4)
- Easy to extend with typewriter effect, fade-in/out

**Cons:**
- Requires managing lifecycle of dynamic Labelled nodes (create/remove per node)
- Positioning relative to NPC needs attention (must not clip through geometry)
- Billboard text may overlap if multiple NPCs are in conversation range
- 4 simultaneous LoFiText3D nodes per conversation = manageable but adds draw calls

**Risk:** Low — pattern is straightforward Node3D controller with dynamic children.

**Effort:** Small (1 script + 1 scene + wiring in main.gd ≈ 150 lines)

---

### Approach B: Extend DialoguePanel (2D Control) with 3D SubViewport

**Description:**
Keep the existing 2D `dialogue_panel.tscn` structure but render it into a `SubViewport`, then project the SubViewport texture onto a billboarded `Sprite3D` in world space. The 2D panel retains its layout logic, button click detection, and theme support — only the output surface changes from screen space to 3D world space.

**Pros:**
- Reuses all existing 2D Control layout — choice buttons, text wrapping, font sizing work as-is
- Godot 2D Control text rendering is higher quality than Label3D for small text
- Button click support (mouse/touch) works alongside keyboard
- No dynamic Label3D node management — VBoxContainer handles layout
- Easier to theme and style (StyleBox, theme overrides)

**Cons:**
- Loses the lo-fi aesthetic — 2D text in a SubViewport doesn't get the Label3D pixelation shader
- Would need to apply lo-fi effect as 2D shader on the Viewport texture or Sprite3D, adding complexity
- Two draw passes (SubViewport render + 3D sprite render) per dialogue
- SubViewport resolution mismatch with Label3D pixel font — text appears aliased differently
- Contradicts the game's design direction (all text should be 3D with lo-fi treatment per GDD)
- Billboard behavior must be implemented on the Sprite3D (Label3D has native billboard)
- More nodes involved (SubViewport + Camera2D + Control + Sprite3D) per dialogue

**Risk:** Medium — SubViewport rendering is well-supported but introduces resolution and scaling concerns.

**Effort:** Medium (1 scene + 1 script + shader tweaks ≈ 200 lines)

---

### Approach C: Inline Dialogue UI in CanvasLayer with 3D Aesthetic Overlay

**Description:**
Keep the dialogue UI as a 2D CanvasLayer overlay (similar to current `dialogue_panel.tscn`) but apply the lo-fi shader as a full-screen post-process layer during dialogue mode. Use Label3D nodes placed in a WorldSpace CanvasLayer or render the 2D UI into a low-resolution buffer.

**Pros:**
- Simplest to implement — most UI systems in existing CRPGs use overlays
- Choice selection can use mouse/click
- Rich layout options from Control nodes
- No 3D positioning issues

**Cons:**
- **Design contradiction:** The GDD explicitly states text should be in 3D space as diegetic elements, not 2D overlays. The Hopper aesthetic requires environmental immersion.
- Breaking immersion — a floating 2D panel breaks the 3D world illusion
- Loses the lo-fi text treatment (no Label3D pixelation/scanlines)
- Would need significant justification to deviate from the GDD's 3D text direction
- Debug overlay already shows F12 can coexist — 3D dialogue and 2D debug are fine, but primary interaction should be 3D

**Risk:** Medium-High — design direction violation may affect project coherence.

**Effort:** Small (modify existing panel + post-process shader ≈ 100 lines)

---

### Recommendation

→ **Approach A (Dedicated 3D Dialogue Display Controller)** because:

1. **Design alignment:** The GDD (01-OVERVIEW.md) and Issue #44 PRD establish that all in-world text must be rendered in 3D space using Label3D with the lo-fi shader. Approach A is the only approach that achieves this without workarounds.

2. **Aesthetic integrity:** The lo-fi pixelation, scanline, and emissive effects are designed for Label3D. Rendering dialogue text through any other path (SubViewport, CanvasLayer) would bypass the shader or require duplicating it for 2D.

3. **Proportional complexity:** The game has ~5 NPCs with dialogue. A dedicated 3D controller per NPC is proportionate. There's no need for a generalized UI framework when the number of interactive dialogue scenes is small.

4. **Clean architecture:** DialogueRunner stays pure logic (signals out), DialogueDisplay3D handles all rendering (signal listeners). This separation makes it trivial to swap implementations or add features (typewriter effect, fade transitions, camera punch-in).

5. **LoFiText3D reuse:** The existing `lo_fi_text_3d.gd` component is ready-made for this — just instance it with the right parameters for speaker (amber emissive), text (white, larger font), and choices (dimmed/dimmed-highlighted).

6. **Keyboard-first input:** The CRPG is keyboard-navigated (no mouse required per design). Approach A's programmatic focus management is simpler than 2D Control button navigation for keyboard-only.

**Mitigation for dynamic node management:**
- Use a pre-allocated pool of LoFiText3D choice labels (max 4) instead of creating/freeing each time
- Reuse existing instances, hide unused ones
- Position using a simple vertical offset formula: `y = base_y - index * CHOICE_SPACING`

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Dialogue Start:** Player triggers NPC interaction (F9 for test, or proximity trigger) → `DialogueRunner.start("res://dialogues/bartender.json", "bartender")` returns true
2. **Text Display:** `dialogue_started` signal fires → DialogueDisplay3D shows speaker label (amber emissive, billboarded) and dialogue text (white, pixel font, Hemingway-truncated)
3. **Choice Presentation:** `choices_available(choices)` signal fires → DialogueDisplay3D creates/reuses up to 4 choice labels below the dialogue text, with the first choice highlighted (→ prefix + emissive glow)
4. **Input Navigation:** Player presses Down → focus index increments (wraps to 0 at max) → previous choice dims, new choice highlights
5. **Choice Selection:** Player presses Enter/Space on focused choice → `DialogueRunner.select_choice(index)` called
6. **State Update:** Effects applied (slider_delta may change hope/conviction/will) → `choice_made` signal fires
7. **Advance:** `node_changed` + new `choices_available` signals fire → DialogueDisplay3D updates text and choices
8. **Dialogue End:** Terminal node reached → `dialogue_ended` signal fires → DialogueDisplay3D fades out all labels

### Edge Cases

1. **Zero reachable choices (all gated, no default):** DialogueRunner already handles this by force-ending. DialogueDisplay3D should show a brief "... (no options)" text before fade-out, or just fade out immediately.
2. **Hemingway truncation at sentence boundary:** Enforcer must split on sentence-ending punctuation (`.` / `!` / `?` followed by space or end-of-string). If exactly 3 sentences, no truncation. If subsentence fragment exceeds 25 chars, truncate at word boundary.
3. **Single choice auto-advance:** If only one choice is available (unconditionally reachable), should the game auto-advance or still require player input? **Decision:** Always require input — preserves player agency and pacing control.
4. **Multiple NPCs at same location:** Two NPCs within camera view both showing dialogue. **Decision:** Only one conversation active at a time. DialogueDisplay3D is a singleton that replaces its content on each dialogue start.
5. **Camera perspective changes during dialogue:** Player can theoretically rotate camera during conversation. Billboard mode handles this — all LoFiText3D labels always face the camera.
6. **Very long speaker names:** If an NPC name exceeds visible width of the pixel font at the configured scale. **Solution:** Clamp speaker label to 20 chars with "…" truncation.
7. **Choice label occlusion:** If dialogue choices overlap with scene geometry (e.g., NPC's head, a light fixture). **Mitigation:** Place the display slightly above and to the side of the NPC, with configurable offset in the scene.

### Failure Paths

1. **Dialogue JSON load failure:** `DialogueRunner.start()` returns false. DialogueDisplay3D shows an error label for 2 seconds: *"... (dialogue missing)"* then hides.
2. **GameManager not available during effect application:** DialogueRunner._apply_effects logs warning and skips effects. No visual change — dialogue continues without state updates.
3. **Hemingway enforcer receives empty text:** Returns empty string. Label shows nothing. Not a crash — ensure empty text is handled gracefully.
4. **Choice index out of range on input:** Player somehow sends invalid choice index (e.g., key 5 when only 4 choices exist). DialogueRunner.select_choice checks range and logs error. No change to display.
5. **Font resource missing:** LoFiText3D falls back to system font (Label3D default). Lo-fi aesthetic partially lost but text remains readable.
6. **Rapid input during dialogue:** Player mashes Enter/Space rapidly. DialogueRunner is synchronous — each call completes before next. No risk of double-advancement or state corruption.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #46 — Dialogue Engine Data Model + Conditional Branching | **Completed** — all core files exist (DialogueParser, DialogueRunner, DialogueConditionEvaluator) | Low — stable, tested |
| Issue #44 — Lo-Fi 3D Text Rendering | **Completed** — lo_fi_text_3d.gd + shader exist | Low — stable, tested |
| Issue #49 — Text Component Library | **In-flux** (0% progress per decomposition) | **Med** — this PRD assumes LoFiText3D is used directly as the text component; if #49 introduces a different component interface, DialogueDisplay3D must adapt. However, #49 is not a hard blocker — the runtime can be built with LoFiText3D and migrated to the library later. |
| Issue #51 — Hemingway Writing Constraints | **In-flux** (0% progress per decomposition) | **Low** — the runtime enforcer is a simple utility (~30 lines); the design doc from #51 is advisory for the constraint rules. |
| Issue #47 — GameState System | **In-flux** — GameManager autoload exists, slider API is assumed | **Med** — DialogueRunner._apply_effects calls `gm.apply_slider_delta()` / `gm.set_flag()`. If GameState API differs from these assumed signatures, effects won't apply. Test-friendly because `state_provider` callable exists. |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #53 — UI System | Critical — UI system's choice list design directly depends on how dialogue choices are presented in 3D |
| Issue #54 — NPC Framework + Convenience Clerk | Critical — NPC interaction flow depends on functional dialogue display |
| Issue #55 — Office Door → Street → Convenience Store scene | Critical — first playable scene depends on dialogue being visually functional |
| Issue #57 — MVP Playtest | High — without dialogue visibility, the game has no interaction |

### Preparation Needed

- [ ] Verify that LoFiText3D font size and pixel_factor settings are readable at dialogue-relevant camera distances (2–5 meters, typical NPC conversation distance)
- [ ] Define keyboard input actions in Project Settings > Input Map: `dialogue_up`, `dialogue_down`, `dialogue_select`, `dialogue_skip`
- [ ] Ensure GameManager exposes the methods DialogueRunner assumes: `get_slider(axis)`, `has_flag(flag)`, `apply_slider_delta(axis, delta)`, `set_flag(flag, value)`

---

## 7. Spike / Experiment (Optional — depth/standard only)

> Section 7 is optional for `depth/standard`. No spike experiments required.

### Key Design Decisions Already Resolved

1. **Text rendering path:** LoFiText3D (Label3D + ShaderMaterial) — confirmed in Issue #44
2. **Dialogue data format:** JSON — confirmed in Issue #46
3. **Runtime architecture:** Signal-based (DialogueRunner emits, display listens) — confirmed in existing code
4. **Hemingway rule set:** Max 25 chars/sentence, max 3 sentences — from Issue #51 design

### Open Questions for Plan Phase

1. **Choice focus visual:** Should the focused choice use a colored arrow prefix ("→"), or emissive glow on the text itself, or a subtle background highlight? Arrow prefix is simplest but may not match the lo-fi aesthetic — the plan agent should prototype both.
2. **Camera behavior during dialogue:** Should the camera remain free (player can look around), lock at the NPC, or use a subtle dolly-in? Current design says free camera — the 3D billboard text handles any angle.
3. **Choice count limit:** Current design says max 4 visible choices. If a node has 5+ choices, should they overflow to a scrollable list, or is 4 a hard limit? Decision: 4 is a hard design constraint — enforce in DialogueRunner or display layer.
4. **Continue prompt:** After dialogue text is displayed, should a "▼ Press Space to continue" prompt appear before choices show, or should text and choices appear simultaneously? Two-stage (text first, then choices) creates better pacing. The plan agent should design the timing.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The dialogue engine currently has its core runtime complete: **DialogueParser** (JSON validation/loading), **DialogueConditionEvaluator** (static condition DSL for slider/flag/choice_made/and/or/not), and **DialogueRunner** (stateful traversal with anti-loop, default choice fallback, effect application, signal-based output). The lo-fi text rendering system provides **LoFiText3D** (Label3D + fragment shader with pixelation, color reduction, scanlines, emissive glow).

The proposed approach (Approach A — DialogueDisplay3D) builds a dedicated scene/script that listens to DialogueRunner signals and manages a set of LoFiText3D nodes in 3D world space. The main script (`main.gd`) handles keyboard input (arrow keys for navigation, Enter/Space for selection) and forwards to DialogueRunner.

### Files to Create

1. **`gdscripts/hemingway_enforcer.gd`** — Static utility:
   - `const MAX_SENTENCES := 3`
   - `const MAX_CHARS_PER_SENTENCE := 25`
   - `static func truncate(text: String) -> Dictionary` returns `{truncated_text, original_text, was_truncated, original_sentence_count, original_max_sentence_length}`
   - Logic: split text on sentence boundaries (`.`/`!`/`?` followed by space or EOS). Truncate to first 3 sentences. For each sentence, if >25 chars, truncate at word boundary and append "…". Join truncated sentences. If any truncation occurred, append "…" at the end.

2. **`gdscripts/dialogue_display_3d.gd`** — 3D dialogue display controller:
   - Extends `Node3D`
   - Exported: `@export var max_choices: int = 4`
   - References: preload LoFiText3D scene
   - Methods:
     - `func _ready()` — connect to DialogueRunner signals via owner/main
     - `func _on_node_changed(node_id, speaker, text)` — update speaker + dialogue text labels, apply Hemingway truncation
     - `func _on_choices_available(choices)` — create/reuse choice labels, highlight first choice
     - `func _on_dialogue_ended()` — fade/hide all labels
     - `func highlight_choice(index: int)` — dim previous focus, highlight new
     - `func get_focused_choice_index() -> int` — current focus
   - Internal state: `_focused_index: int`, `_choice_labels: Array[LoFiText3D]`, `_is_active: bool`

3. **`scenes/dialogue/dialogue_display_3d.tscn`** — Scene:
   - Root: Node3D (DialogueDisplay3D script)
   - Children: SpeakerLabel (LoFiText3D), DialogueText (LoFiText3D), ChoiceContainer (Node3D), ContinuePrompt (LoFiText3D, hidden by default)

### Modifications to Existing Files

1. **`gdscripts/main.gd`** — Add dialogue input handling:
   ```
   elif event.is_action_pressed("dialogue_up"):
       if _dialogue_active: dialogue_display_3d.navigate_up()
   elif event.is_action_pressed("dialogue_down"):
       if _dialogue_active: dialogue_display_3d.navigate_down()
   elif event.is_action_pressed("dialogue_select"):
       if _dialogue_active:
           var idx = dialogue_display_3d.get_focused_choice_index()
           dialogue_runner.select_choice(idx)
   ```
   - Add `@onready var dialogue_display_3d: Node3D = $Dialogue/DialogueDisplay3D`
   - Track `_dialogue_active: bool` (set on `dialogue_started`, clear on `dialogue_ended`)
   - Wire signals: `dialogue_runner.node_changed -> dialogue_display_3d._on_node_changed`, etc.

2. **`scenes/main.tscn`** — Add DialogueDisplay3D node under `Dialogue/` path.

3. **Project Settings > Input Map** — Add actions:
   - `dialogue_up` → Arrow Up
   - `dialogue_down` → Arrow Down
   - `dialogue_select` → Enter, Space
   - `dialogue_skip` → Escape (skip typewriter animation)

### Key Risks

1. **LoFiText3D readability at NPC conversation distance:** The pixel font (8×8) with active pixel_factor may be hard to read at 3–5 meters, even with billboarding. The Plan agent should test font size scaling—potentially using Label3D's `pixel_size` property or a larger pixel font variant for dialogue text (16×16 instead of 8×8).
2. **Hemingway enforcer edge cases:** Unicode characters, em-dash, ellipsis punctuation, and parenthetical sentences need careful handling. The truncation logic must not break mid-word.
3. **Choice highlight visibility:** The difference between "focused" and "unfocused" choice must be visually clear at all camera angles. Using emissive_color strength (5.0 vs 0.0) as the highlight mechanism leverages the WorldEnvironment Glow pass for a neon highlight effect — consistent with the game's visual language.
4. **GameManager API surface:** If GameManager (Issue #47) uses different method signatures than DialogueRunner assumes, effect application will silently fail. The Plan agent should verify the actual GameManager API before implementing `_apply_effects`.

### Design Decisions for Plan Agent

1. Pre-allocate 4 LoFiText3D choice labels in the scene and reuse them (hide/show) rather than instantiating dynamically each time
2. Use `emissive_strength` (0.0 = dim, 3.0 = bright amber) as the focus indicator, matching the game's neon aesthetic
3. Two-stage reveal: text appears first with a brief (0.5s) typewriter-like reveal, then choices appear below
4. Auto-hide `dialogue_display_3d` on `dialogue_ended` with a 0.3s fade-out (animate emissive_strength → 0, then hide)
5. Support both "choose then confirm" (Arrow keys + Enter) and "direct select" (1–4 number keys) input schemes

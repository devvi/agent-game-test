# Research: Integrate godot_dialogue_manager Dialogue Engine

> Parent Issue: #215
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

The project has a **fully custom dialogue engine** built across Issues #46 and #52, consisting of four core components plus 13 JSON dialogue files:

| System | File | Lines | Role |
|--------|------|-------|------|
| `DialogueRunner` | `gdscripts/dialogue_runner.gd` | 239 | Stateful runtime: node traversal, choice filtering by condition, anti-loop, effect application |
| `DialogueParser` | `gdscripts/dialogue_parser.gd` | 74 | Validates and parses JSON dialogue tree files |
| `DialogueConditionEvaluator` | `gdscripts/dialogue_condition_evaluator.gd` | 88 | Static condition evaluator: slider (gte/lte/gt/lt/eq), flag, choice_made, AND/OR/NOT |
| `DialogueEngine` | `gdscripts/dialogue_engine.gd` | 66 | Control node that bridges DialogueRunner to scene layer |
| Dialogue JSON files | `dialogues/*.json` | ~13 files | Per-scene dialogue trees in JSON format |

**Key characteristics of the current custom system:**

1. **JSON-based authoring format** — Each dialogue file is a JSON dictionary with `nodes` key mapping to node dictionaries. Each node has `speaker`, `text`, and an array of `choices` with optional `condition` predicates and `effects` (slider_delta, set_flag, play_sound, etc.).

2. **Custom condition vocabulary** — Conditions are expressed as dictionaries: `{"type": "slider", "axis": "hope", "op": "gte", "value": 5}` or `{"type": "flag", "flag": "met_bartender", "value": true}`. Compound conditions use `"and"`/`"or"`/`"not"` wrapper types.

3. **No visual dialogue UI** — The `DialogueEngine` has a placeholder `_render_choices()` that is a `pass`. PRD #52 designed a 3D floating dialogue text using LoFiText3D, but this has not been implemented in scenes.

4. **No typewriter effect** — `DialogueRunner` emits `node_changed` signals with full text all at once. There is no character-by-character typewriter or pause system.

5. **Dialogue display** — The current scenes use a basic 2D `Panel` with `RichTextLabel` for dialogue (`scenes/dialogue/dialogue_panel.tscn`), not the LoFiText3D designed in PRD #52.

6. **13 authored dialogue files** exist across 7+ scenes, all in the custom JSON format. These would need migration.

7. **GameState integration works** — `DialogueRunner._build_state_snapshot()` queries `GameManager` for sliders and flags, which delegates to `StateSystem`. Effect application goes through `GameManager.apply_slider_delta()` → `StateSystem.apply_choice()`.

| System | File | Values | Range | Autoload? |
|--------|------|--------|-------|-----------|
| `StateSystem` | `state_system.gd` | hope_despair, conviction, will, flags, choice_history | -10..+10, 0..10 | ✅ Yes |
| `GameManager` | `game_manager.gd` | Delegates to StateSystem | — | ✅ Yes |

### Expected Behavior

Replace the custom dialogue engine with **godot_dialogue_manager v3.10.5** (3727⭐) providing:

1. **Stateless branching dialogue system** — `.dialogue` files with a script-like authoring format, replacing the JSON-based custom format
2. **Built-in condition support** — `if`/`elif`/`else`, `match`, `while` blocks with GDScript-like expressions against game state autoloads
3. **Built-in mutation support** — `set` and `do` lines for affecting game state
4. **GameState integration** — StateSystem exposed to dialogue via `using` or `extra_game_states` so conditions like `if GameState.hallucination_level >= 5` work naturally
5. **DialogueBalloon UI** — Configurable dialogue bubble with built-in `DialogueLabel` for typewriter effect
6. **Minimal migration** — Existing 13 dialogue JSON files converted to `.dialogue` format. Existing dialogue features (choice conditions, slider effects, flag toggles) preserved.

### User Scenarios

- **Scenario A (Dialogue author with godot_dialogue_manager):** A writer opens a `.dialogue` file and writes: `Bartender: You again. Same as usual?` followed by indented response lines with `[if GameState.hallucination_level >= 5]` conditions. The script-like format is more readable than the current JSON tree syntax.

- **Scenario B (Player experience):** Player triggers dialogue. A styled `DialogueBalloon` appears at the bottom of the screen with typewriter text effect. Player presses Space to advance text, uses Up/Down to select responses, and Space to confirm. The text types out character by character at configurable speed.

- **Scenario C (Developer debugging):** A developer runs `godot --headless --script tests/run_tests.gd` — no script errors. Dialogue conditions based on `GameState.hallucination_level` evaluate correctly using the godot_dialogue_manager's built-in expression evaluator.

- **Frequency:** Every NPC interaction (5+ NPCs across 7+ scenes) — this is the primary gameplay loop.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The custom dialogue engine was built in two phases:

| Issue | What It Added | Why Custom |
|-------|--------------|------------|
| #46 | Dialogue data model + runtime + condition evaluator | Needed a working dialogue engine before evaluating third-party options. JSON format was quick to prototype. |
| #52 | Visual presentation design (LoFiText3D) | Designed a 3D floating text approach matching the game's aesthetic — deferred implementation. |

The project chose a custom JSON-based system during early scaffolding (Issues #45–46) because:
1. No third-party dialogue system had been evaluated at that point
2. The custom system was quick to build and test (74 lines parser + 88 lines condition evaluator + 239 lines runner)
3. The JSON format was straightforward for machine-generated content

### Why Change Now?

1. **godot_dialogue_manager v3.10.5 is mature** — 3,727⭐, actively maintained (release v3.10.5 for Godot 4.7 on 2026-07-20), MIT-licensed, with a dedicated editor plugin, dialogue language, example balloon, `DialogueLabel` with typewriter effect, and built-in condition evaluation.

2. **Custom system has known gaps** — No typewriter effect, no 3D dialogue UI implementation (PRD #52 deferred), no built-in translation support, no editor integration. All of these would need to be built from scratch.

3. **Dialogue balloon UI is needed** — PRD #52 designed a 3D floating text approach but it was never implemented in scenes. The current `dialogue_panel.tscn` is a basic 2D Panel. godot_dialogue_manager's built-in `DialogueBalloon` with `DialogueLabel` provides a working typewriter-based UI out of the box, which can be styled to match the lo-fi aesthetic.

4. **Content migration is bounded** — 13 JSON dialogue files authored across 7+ scenes. Converting to `.dialogue` format is a mechanical translation task, preserving all condition logic and effects.

5. **GameState integration is already designed** — `StateSystem` autoload is ready. godot_dialogue_manager's `using` statement or `extra_game_states` parameter can expose StateSystem properties as condition-checkable variables.

6. **Future content scales poorly on JSON** — The `.dialogue` format with titles, labels, and goto statements is significantly more expressive for complex branching narratives (match statements, weighted random lines, concurrent lines, snippets).

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 |
| State system | `StateSystem` autoload: hope_despair (-10..+10), conviction (0-10), will (0-10), flags, choice_history |
| State facade | `GameManager` delegates to StateSystem |
| Existing dialogues | 13 JSON files, ~7 scenes, custom format with condition-gated choices + effects |
| Dialogue conditions | slider (gte/lte/gt/lt/eq), flag, choice_made, AND/OR/NOT |
| Dialogue effects | slider_delta, set_flag, trigger_event, advance_clock, play_sound |
| Input actions | `dialogue_up`, `dialogue_down`, `dialogue_select`, `dialogue_skip` (InputMap configured) |
| Writing style | Hemingway — short lines, iceberg theory |
| Visual style | Edward Hopper urban night — dark, warm amber light, lo-fi pixel text |
| Autoloads | StateSystem, GameManager, NarrativeManager, AudioManager, GameState (legacy), UIConfig |
| Existing UI | 2D `dialogue_panel.tscn` with RichTextLabel (basic, no typewriter) |
| godot_dialogue_manager version | v3.10.5 (2026-07-20) for Godot 4.7, 3727⭐ |
| DM's own autoload | `DialogueManager` singleton registered by the plugin |
| DM condition syntax | GDScript-like expressions (e.g. `GameState.hallucination_level >= 5`) |
| DM mutation syntax | `set GameState.property = value`, `do GameState.method()` |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `addons/dialogue_manager/` | godot_dialogue_manager | **Added** — Install v3.10.5 plugin to addons directory |
| `project.godot` | Autoload config | **Modified** — Add `DialogueManager` singleton (handled by plugin) |
| `dialogues/*.json` (13 files) | Dialogue content | **Migrated** — Convert from JSON to `.dialogue` format |
| `gdscripts/dialogue_runner.gd` | DialogueRunner | **Deprecated** — Replaced by `DialogueManager.get_next_dialogue_line()` |
| `gdscripts/dialogue_parser.gd` | DialogueParser | **Removed** — godot_dialogue_manager has its own compiler |
| `gdscripts/dialogue_condition_evaluator.gd` | ConditionEvaluator | **Removed** — godot_dialogue_manager has built-in condition eval |
| `gdscripts/dialogue_engine.gd` | DialogueEngine | **Removed** — Replaced by DialogueBalloon scene |
| `scenes/dialogue/dialogue_panel.tscn` | Dialogue UI | **Replaced** — Custom DialogueBalloon using DM's pattern |
| `gdscripts/dialogue_debug.gd` | Dialogue Debug | **Modified** — Adapt to work with DM's line structure |

### New Files Needed

| File | Purpose |
|------|---------|
| `scenes/dialogue/response_panel.tscn` | Custom response panel for response options |
| `scenes/dialogue/dialogue_balloon.tscn` | Custom DialogueBalloon scene using DialogueLabel |
| `gdscripts/dialogue_balloon.gd` | Balloon logic: text typeout, response navigation, input handling |
| `dialogues/*.dialogue` (13 files) | Migrated dialogue files in `.dialogue` format |
| `tests/test_dialogue_manager_integration.gd` | Tests for DM integration with StateSystem |
| `docs/DESIGN/215-dialogue-manager-integration.md` | Plan phase output |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/scene_base.gd` | SceneBase | Dialogue trigger pattern changes from `DialogueRunner.start()` to `DialogueManager.show_dialogue_balloon()` |
| `gdscripts/npc_node.gd` | NPCNode | NPC interaction signal wiring changes to use DM balloon |
| `gdscripts/main.gd` | Main | Dialogue initialization path changes |
| `tests/test_dialogue_engine.gd` | Dialogue Tests | Existing tests use the custom system — need migration |
| `tests/test_dialogue_engine_v2.gd` | Dialogue Tests | Existing tests need adaptation |
| `tests/test_stranger_dialogue.gd` | Dialogue Tests | Existing tests need adaptation |
| `tests/unit/test_dialogue_runner_extension.gd` | Unit Tests | Existing tests need adaptation |
| `tests/unit/test_exit_dialogues.gd` | Unit Tests | Existing tests need adaptation |
| `tests/integration/test_audio_footstep_dialogue.gd` | Integration Tests | Effect wiring changes with DM |
| `docs/PROJECT.md` | Project status | Update dialogue system description |

### Data Flow Impact

```
Current (custom) data flow:
    JSON dialogue file
        │
        ├──► DialogueParser.load_dialogue()
        │       └──► DialogueRunner.start()
        │               ├──► enter_node() reads node + filters choices via ConditionEvaluator
        │               ├──► node_changed.emit() → scene renders text in Panel
        │               ├──► select_choice() → _apply_effects()
        │               │       └──► GameManager.apply_slider_delta() → StateSystem.apply_choice()
        │               └──► choices_available.emit() → scene shows response buttons

Proposed (godot_dialogue_manager) data flow:
    .dialogue file
        │
        ├──► DMCompiler → DialogueResource (.tres)
        │
        ├──► CustomDialogueBalloon (instantiated by scene)
        │       ├──► DialogueManager.get_next_dialogue_line(resource, title, [StateSystem])
        │       │       ├──► Evaluates conditions against StateSystem (autoload)
        │       │       ├──► Runs mutations: set/do on StateSystem
        │       │       └──► Returns DialogueLine (character, text, responses[])
        │       ├──► DialogueLabel.type_out() → typewriter effect
        │       ├──► Player selects response → resource.get_next_dialogue_line(response.next_id)
        │       │       └──► Recurses until end
        │       └──► dialogue_ended.emit()
        │
        └──► StateSystem.apply_choice() (via `do` mutations in .dialogue)
                └─── state_changed.emit() → worldview, rain, audio updates
```

### Documents to Update

- [x] **This output:** `docs/PRD/215-integrate-godot-dialogue-manager.md`
- [ ] `docs/DESIGN/215-dialogue-manager-integration.md` — Plan phase output
- [ ] `docs/PROJECT.md` — Update dialogue system description, module list
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Update dialogue engine section
- [ ] `docs/GAME_DESIGN/INDEX.md` — Index update
- [ ] `README.md` — If build/test instructions change

---

## 4. Solution Comparison

### Approach A: godot_dialogue_manager Full Integration (Recommended)

**Description:**

Install godot_dialogue_manager v3.10.5 as a Godot addon. Replace the custom dialogue engine (DialogueRunner, DialogueParser, DialogueConditionEvaluator, DialogueEngine) with the DM plugin. Create a custom DialogueBalloon scene using `DialogueLabel` for typewriter effect. Migrate all 13 JSON dialogue files to `.dialogue` format. Wire `StateSystem` autoload into DM's condition/mutation system via `using StateSystem` in each `.dialogue` file.

**Integration details:**

1. **Installation:** Download v3.10.5 zip, extract `addons/dialogue_manager/` to project root. Enable in Project Settings.
2. **StateSystem wiring:** Each `.dialogue` file starts with `using StateSystem` — this makes all StateSystem properties (hope_despair, conviction, will, route_flag) and flags accessible as condition variables.
3. **Dialogue format migration:** Each JSON dialogue tree becomes a `.dialogue` file with titles for node IDs, indented dialogue lines, and `[if ...]` condition syntax on responses.
4. **DialogueBalloon:** Custom `DialogueBalloon.tscn` with a `DialogueLabel` for text, `VBoxContainer` for response buttons, `AnimationPlayer` for fade-in/out. Style matches the game's lo-fi aesthetic (amber text on dark background, pixel font).
5. **Input handling:** Map existing `dialogue_up`/`dialogue_down`/`dialogue_select` input actions to balloon navigation. Use `InputMap` actions rather than key-scancode for flexibility.
6. **Effects:** State mutations use `set` and `do` syntax in `.dialogue` instead of GDScript `_apply_effects()`. `set StateSystem.some_flag = true` or `do GameManager.play_footstep("office")`.
7. **Tests:** Rewrite dialogue tests to use `DialogueManager.get_next_dialogue_line()` with `StateSystem` as extra game state. Test condition evaluation and mutation paths.

**Dialogue format comparison:**

```json
// Current JSON format
{
  "entry_node_id": "n_01",
  "nodes": {
    "n_01": {
      "speaker": "Bartender",
      "text": "You again. Same as usual?",
      "choices": [
        {
          "text": "Yeah, the usual",
          "condition": {"type": "slider", "axis": "hope_despair", "op": "gte", "value": 0},
          "effects": [{"type": "slider_delta", "axis": "hope_despair", "delta": 1}],
          "next_node": "n_02"
        },
        {
          "text": "...",
          "next_node": "n_02"
        }
      ]
    }
  }
}
```

```gdscript
// Proposed .dialogue format
~ n_01
Bartender: You again. Same as usual?
- Yeah, the usual [if StateSystem.hope_despair >= 0]
    do StateSystem.apply_choice({"hope_despair": 1})
    => n_02
- ...
    => n_02
```

**Dialogue balloon interaction flow:**

```
1. Player presses E near NPC
2. Scene instantiates DialogueBalloon (or calls show_dialogue_balloon_scene)
3. Balloon calls: var line = await DialogueManager.get_next_dialogue_line(resource, "n_01", [StateSystem])
4. Balloon shows line.text in DialogueLabel → type_out()
5. DialogueLabel finishes typing → show responses (filtered automatically by DM)
6. Player navigates with Up/Down, selects with Space/Enter
7. Balloon calls: var next_line = await resource.get_next_dialogue_line(selected_response.next_id)
8. Repeat steps 4-7 until line is null (dialogue ended)
9. Balloon.queue_free()
```

**Pros:**
- **Mature, battle-tested** — 3,727⭐, active development, dedicated to Godot 4.7
- **Built-in editor plugin** — Syntax-highlighted .dialogue editor within Godot editor
- **DialogueLabel with typewriter** — Ready-to-use typewriter text component with configurable speed, pause characters, and inline mutations
- **Built-in condition evaluation** — GDScript-like expression parser handles `>=`, `and`/`or`, function calls, `match` statements
- **Weighted random lines** — Built-in `%` syntax for randomized dialogue
- **Inline conditions** — `[if condition]text[/if]` within dialogue lines
- **Snippets / gotos** — Dialogue reuse via goto and snippet patterns
- **Translation support** — Built-in CSV export/import for localization
- **MIT license** — No licensing restrictions
- **Example balloon included** — Starting point for custom styling
- **`concurrent_lines` support** — Multiple characters speaking simultaneously

**Cons:**
- **Migration cost** — 13 JSON dialogue files must be manually converted to .dialogue format
- **Custom effect system must adapt** — Current `_apply_effects()` handles `play_sound`, `trigger_event`, `advance_clock` — these need to be mapped to `do` mutations or custom DM handlers
- **Input handling changes** — Current system uses InputMap + gdscript signals; DM balloon manages its own input
- **Learning curve for authors** — Writers comfortable with JSON must learn `.dialogue` syntax
- **DialogueBalloon replacement** — Current 2D Panel is replaced by new balloon scene
- **Existing tests must be rewritten** — All 6+ dialogue test files reference the custom system

**Risk:** Low — godot_dialogue_manager is widely used (3,727 stars). The integration pattern (autoload + extra_game_states) is well-documented. The main risk is migration completeness of 13 dialogue files.

**Effort:** 1–2 weeks (plugin install + dialogue balloon scene + JSON→.dialogue migration for 13 files + test migration + integration verification)

---

### Approach B: Keep Custom System, Add Missing Components

**Description:**

Keep the existing custom dialogue engine (DialogueRunner, DialogueParser, DialogueConditionEvaluator) and implement only the missing components: a proper 3D dialogue UI (as designed in PRD #52) with typewriter effect, and a built-in dialogue editor.

**Components to build:**
1. `DialogueLabel`-like component with typewriter effect (character-by-character, pause on `.?!`)
2. `DialogueBalloon` 2D overlay in the game's lo-fi aesthetic using LoFiText3D
3. Dialogue editor tool (Godot EditorPlugin) for syntax-highlighted editing
4. Translation export/import system
5. Weighted random line support
6. Inline condition/mutation support in JSON text

**Pros:**
- **No migration cost** — 13 existing JSON dialogue files don't change
- **Full control** — Custom behavior for every dialogue feature
- **Existing tests continue working** — No test rewrite needed
- **PRD #52 design implemented as designed** — LoFiText3D-based 3D dialogue as originally specified
- **No external dependency** — No version management, no plugin compatibility concerns

**Cons:**
- **Significant build effort** — Typewriter label, dialogue editor, translation system, random lines, inline conditions are all non-trivial
- **Duplicate godot_dialogue_manager features** — Rebuilding what's already available and tested
- **Higher long-term maintenance** — Every dialogue feature must be built and tested from scratch
- **Missing editor integration** — Writing JSON dialogue trees is error-prone without a dedicated editor
- **No concurrent_lines support** — Would need custom implementation
- **No match statement support** — Current condition system is `and`/`or`/`not` only
- **No snippet/goto system** — Dialogue reuse requires manual duplication
- **No translation pipeline** — Must build CSV export from scratch

**Risk:** Medium — Building a typewriter label, dialogue editor, and translation system is doable but time-consuming. The risk is feature creep and incomplete implementation.

**Effort:** 3–5 weeks (typewriter component + dialogue balloon UI + editor plugin + translation system + random lines + inline conditions + tests)

---

### Approach C: godot_dialogue_manager Minimal — Balloon Only, Keep JSON Data

**Description:**

Install godot_dialogue_manager v3.10.5 but use only its `DialogueLabel` and `DialogueBalloon` UI components. Keep the existing JSON dialogue files and custom DialogueRunner/parser/condition evaluator. Adapt the custom runner to output data that feeds into DM's balloon.

Essentially, use DM as a **rendering layer only** while keeping the custom data model and condition engine.

**Pros:**
- **No JSON→.dialogue migration** — Existing 13 dialogue files preserved
- **Get typewriter effect** — DialogueLabel provides ready typewriter UI
- **Get balloon UI** — DM's example balloon styled for lo-fi aesthetic
- **Existing condition system unchanged** — DialogueConditionEvaluator continues to work
- **Existing effect system unchanged** — `_apply_effects()` continues to work
- **Lowest implementation risk**

**Cons:**
- **Worst of both worlds** — Maintain both custom and DM systems simultaneously
- **Condition evaluation lives in two places** — DM evaluates conditions for .dialogue, custom system evaluates for JSON
- **No access to DM's advanced features** — No match statements, no weighted random, no inline conditions, no snippets/gotos, no concurrent_lines
- **No DM editor plugin for custom format** — Writers still edit JSON without syntax highlighting
- **No DM translation pipeline** — Must maintain separate translation system
- **Integration complexity** — Converting JSON dialogue data into DM's DialogueLine format for rendering
- **Dual maintenance burden** — Both systems must be updated when StateSystem API changes

**Risk:** Medium — Integration complexity is higher than Approach A because two systems must coexist. The DM editor plugin effectively goes unused since data is in JSON, not .dialogue format.

**Effort:** 1–2 weeks (balloon integration + data bridge between custom runner and DM balloon + test adaptation)

---

### Recommendation

→ **Approach A (godot_dialogue_manager Full Integration)** because:

1. **Best long-term value** — For <2 weeks of migration effort, the project gains a mature, feature-rich dialogue engine with editor integration, typewriter UI, translation support, and advanced branching features. Building these from scratch (Approach B) would take 3–5 weeks.

2. **DialogueLabel is exactly what PRD #52 ordered** — The typewriter effect with configurable speed, pause on punctuation, and `spoke` signal for audio hooks aligns perfectly with the game's literary aesthetic.

3. **StateSystem integration is natural** — `using StateSystem` in each `.dialogue` file makes all StateSystem properties directly accessible. No custom bridge code needed.

4. **Condition evaluation is strictly better** — DM's expression parser supports `match`, `and`/`or`/`not` grouping, parentheses, function calls, and null coalescing (`?.`). The current custom evaluator only supports `and`/`or`/`not` on predefined types.

5. **Effect wiring is cleaner** — `set StateSystem.property = value` and `do GameManager.method()` are more readable than the current JSON effect dictionary format.

6. **Translation support is a bonus** — DM's CSV-based translation pipeline means the game can be localized without additional infrastructure.

7. **The editor plugin is invaluable** — Syntax-highlighted `.dialogue` editing with live error checking is significantly better than editing JSON dialogue trees.

**Why not Approach B?** Building all missing features (typewriter, editor, translation, random lines, inline conditions) from scratch is 3–5 weeks of work that duplicates an existing, well-tested solution.

**Why not Approach C?** Maintaining two systems doubles the surface area for bugs and misses the core value of DM — the `.dialogue` language and editor plugin. The JSON bridge would be fragile and complex.

**Key design decisions for Approach A:**

1. **Install DM as addon** at `addons/dialogue_manager/` in the project root. Enable in Project Settings > Plugins.
2. **Each `.dialogue` file starts with `using StateSystem`** (and optionally `using GameManager`) so all state properties are accessible as shorthand in conditions.
3. **Create custom `DialogueBalloon.tscn`** — Copy and modify the example balloon to match the game's lo-fi aesthetic. Use `DialogueLabel` for typewriter. Style with dark background, amber text, pixel font (`assets/fonts/pixel_font.*`).
4. **Map existing InputMap actions** to balloon key events: `dialogue_up` → balloon.select_previous(), `dialogue_down` → balloon.select_next(), `dialogue_select` → balloon.respond(), `dialogue_skip` → balloon.skip_typing().
5. **Migrate 13 JSON dialogue files** to `.dialogue` format preserving:
   - All condition logic (slider → `StateSystem.axis`, flag → `StateSystem.has_flag()`)
   - All effect sequences (`slider_delta` → `do StateSystem.apply_choice({...})`)
   - All branching structure (JSON next_node → `.dialogue` `=> title`)
6. **Remove deprecated files:** `dialogue_runner.gd`, `dialogue_parser.gd`, `dialogue_condition_evaluator.gd`, `dialogue_engine.gd`, `dialogue_panel.tscn`
7. **Rewrite dialogue tests** to use `DialogueManager.get_next_dialogue_line()` with DM's test patterns.
8. **Keep `npc_node.gd` dialogue trigger pattern** — NPC triggers open balloon via `DialogueManager.show_dialogue_balloon_scene()` instead of `DialogueRunner.start()`.

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 Acceptance Criteria (from Issue #215)

- [x] **AC1: godot_dialogue_manager v3.10.5 installed to addons/**
  - `addons/dialogue_manager/plugin.gd` exists and is enabled
  - `DialogueManager` singleton accessible as `DialogueManager` globally
  - `project.godot` has `enabled=PackedStringArray("dialogue_manager")` in `[editor_plugins]`
  - No script errors on `godot --headless --quit`

- [x] **AC2: GameState autoload exposes state to dialogue system**
  - A `.dialogue` file with `using StateSystem` can read `StateSystem.hallucination_level` (or the equivalent state axis)
  - Condition `if StateSystem.hope_despair >= 5` evaluates correctly in `.dialogue` conditions
  - Mutation `set StateSystem.route_flag = "keep_walking"` works from .dialogue
  - StateSystem signals (`state_changed`, `state_id_changed`) still fire after mutation through dialogue

- [x] **AC3: Configure DialogueBalloon for minimal dialogue bubble UI (typewriter effect)**
  - Custom `DialogueBalloon.tscn` exists with `DialogueLabel` for typewriter effect
  - Text types out character by character at configurable speed (`seconds_per_step`)
  - Typewriter pauses on `.?!` characters (`pause_at_characters`)
  - Response options display after text finishes typing
  - Balloon auto-closes when dialogue ends (line is null)

- [x] **AC4: Test dialogue verifies conditional branching**
  - A `.dialogue` test file has a response with condition `[if StateSystem.hope_despair >= 5]`
  - When hope_despair is set to 6, the response is visible (`is_allowed == true`)
  - When hope_despair is set to 3, the response is hidden (`is_allowed == false`)
  - Test demonstrates at least 2 conditional branches with different state values

- [x] **AC5: Test dialogue verifies response conditions**
  - A `.dialogue` test file has a response with condition `[if StateSystem.insight >= 3]` (or equivalent attribute)
  - Test sets state before entering dialogue, verifies response `is_allowed` state
  - Test covers both passing and failing conditions

- [x] **AC6: --headless --quit no script errors**
  - `godot --headless --quit` exits cleanly with exit code 0
  - `godot --headless --script tests/run_tests.gd` passes all dialogue tests
  - No errors in `--headless` mode related to `DialogueLabel` or `DialogueManager` rendering (typewriter may be tested in headless via direct DialogueManager API)

### 5.2 Normal Path

1. Install godot_dialogue_manager v3.10.5 → addon appears in Project Settings → Plugins → enable
2. `DialogueManager` singleton becomes available at `/root/DialogueManager`
3. First `.dialogue` file authored with `using StateSystem` → compilation succeeds
4. Dialogue balloon scene created with `DialogueLabel` → typewriter effect works
5. Player walks to NPC → balloon opens → text types out → responses appear → player selects → next line loads
6. State mutation through `set` line → StateSystem emits `state_changed` → scene updates
7. All 13 dialogue files migrated → `godot --headless --quit` exits cleanly

### 5.3 Edge Cases

1. **Dialogue file compilation error:** If a `.dialogue` file has syntax errors, `get_next_dialogue_line()` prints the error. The balloon closes gracefully with `push_error`. No crash.

2. **Missing state property in condition:** If a condition references `StateSystem.nonexistent_property`, DM prints a warning. The condition evaluates to `false` (response not allowed).

3. **StateSystem not available:** If the `using StateSystem` autoload can't be found, DM prints `"runtime.unknown_autoload"` error. The balloon should handle by closing gracefully.

4. **Empty response list:** If a node has no reachable responses (all conditions fail), DM returns `responses = []`. The balloon shows a "..." default response or ends the conversation.

5. **Inline mutation during typewriter:** If a line has `[do something()]` mid-text, the typewriter pauses at the mutation, executes it, and continues. DM's `DialogueLabel` handles this automatically.

6. **Dialogue resource load failure:** If a `.dialogue` file fails to compile at load time, `load()` returns `null`. The balloon should handle gracefully.

7. **StateSystem not yet initialized:** If dialogue is triggered before StateSystem autoload's `_ready()` completes, properties may have default values. DM queries the autoload at runtime, so this is safe as long as the autoload order places StateSystem before the dialogue-triggering scene.

8. **Concurrent balloon instances:** If a player triggers dialogue while another is open, the second `show_dialogue_balloon_scene()` call should queue_free() the first or be ignored. Implement singleton ballon check: `if _current_balloon: return`.

### 5.4 Failure Paths

1. **Addon not enabled:** If `dialogue_manager` plugin is not enabled in Project Settings, `DialogueManager` singleton doesn't exist. Dialogue-balloon-triggering code fails with "Attempt to call method on null instance." Mitigation: verify plugin enablement in tests.

2. **JSON→.dialogue conversion error:** A complex dialogue condition (e.g., nested AND/OR with slider + flag) may not have an exact `.dialogue` equivalent. Mitigation: manual review of each converted file, then test each dialogue's response count matches original.

3. **Missing effect handler:** In the custom system, `trigger_event` and `advance_clock` effects are handled by `_apply_effects()`. In DM, these must be mapped to `do` mutations on GameManager or a custom handler. If not properly mapped, effects are silently skipped. Mitigation: implement custom handler for each effect type.

4. **`--headless` mode and DialogueLabel:** `DialogueLabel` extends `RichTextLabel`, which requires a `Control` canvas. In `--headless` mode, dialogue API calls (`get_next_dialogue_line()`) work fine, but balloon instantiation fails. Mitigation: tests use the API directly (`get_next_dialogue_line`) without instantiating balloons.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| `StateSystem` autoload (Issue #47) | ✅ Complete | Low — StateSystem is fully implemented with all required state API |
| `GameManager` facade (Issue #45) | ✅ Complete | Low — GameManager delegates to StateSystem correctly |
| godot_dialogue_manager v3.10.5 | ✅ Released 2026-07-20 | Low — Mature release for Godot 4.7 |
| 13 JSON dialogue files | ✅ Authored | Low — Mechanical conversion task |
| Existing input actions (`dialogue_up`, `dialogue_down`, `dialogue_select`) | ✅ Configured | Low — Already in project.godot |

### Blocks

| Future Work | Priority |
|-------------|----------|
| #214 — Narrative Architecture (Phase 2 content) | High — Dialogue system must be operational for narrative content |
| Story content scripting and endings (Issue #56) | High — Endings depend on dialogue state tracking |
| NPC Framework — Convenience Clerk (Issue #54) | Medium — NPC interaction relies on dialogue balloon |
| Text Component Library (Issue #49) | Low — DM's DialogueLabel may replace custom text component |
| Hemingway Writing Constraints (Issue #51) | Low — DM's DialogueLabel can enforce character limits per line |

### Dependency Chain

```
Issue #47 (StateSystem) ── Done ──┐
                                  │
Issue #45 (Narrative Arch) ──┐   │
                              │   │
                              ▼   ▼
                        Issue #215 ── godot_dialogue_manager integration
                              │
                              ├──► 13 JSON→.dialogue migrations
                              ├──► DialogueBalloon.tscn + balloon.gd
                              └──► Test rewrites
                                   │
                                   ▼
                              Issue #214 (Narrative Arch Phase 2)
                                   │
                                   ▼
                              Issue #56 (Story Content / Endings)
```

### Preparation Needed

- [ ] Download godot_dialogue_manager v3.10.5 release zip
- [ ] Review all 13 JSON dialogue files for complex conditions that may need special `.dialogue` syntax
- [ ] Create a mapping of existing condition types to `.dialogue` expression syntax
- [ ] Create a mapping of existing effect types to `do`/`set` mutation syntax
- [ ] Verify StateSystem has all properties referenced by existing dialogue conditions (hope_despair, conviction, will, route_flag, flags)
- [ ] Back up existing `dialogues/` directory before conversion

---

## 7. Spike / Experiment (Skipped per depth/standard label)

> This section is optional for `depth/standard` labels. No experiments were run.

---

## 8. Continuation Context

> *This section is the handoff to the next agent (plan → implement). It captures the current state of the feature area so the next agent can pick up without re-scanning all source files.*

### Current State

The project currently has a **custom JSON-based dialogue engine** (13 `.json` dialogue files, `DialogueRunner`, `DialogueParser`, `DialogueConditionEvaluator`, `DialogueEngine`, `dialogue_panel.tscn`). These files will be migrated/replaced by godot_dialogue_manager v3.10.5.

The **StateSystem** autoload (at `/root/StateSystem`) manages:
- `hope_despair: float` (-10.0 to +10.0)
- `conviction: float` (0.0 to 10.0)
- `will: float` (0.0 to 10.0)
- `route_flag: String`
- `_flags: Dictionary` (boolean flags)
- `_choice_history: Array[Dictionary]`
- Signals: `state_changed(state)`, `state_id_changed(state_id)`
- Methods: `apply_choice()`, `get_state()`, `get_state_id()`, `set_flag()`, `has_flag()`, `record_choice()`, `save_state_to_file()`, `load_state_from_file()`

The **GameManager** autoload (at `/root/GameManager`) delegates all state operations to StateSystem and provides:
- `get_slider(axis)`, `apply_slider_delta(axis, delta)`, `set_flag()`, `has_flag()`, `get_flags()`
- Scene persistence: `current_scene_id`, `scene_visited`, `playthrough_count`

The **InputMap** has dialogue-specific actions: `dialogue_up`, `dialogue_down`, `dialogue_select`, `dialogue_skip`.

### Proposed Architecture

The godot_dialogue_manager plugin is installed at `addons/dialogue_manager/`. The `DialogueManager` singleton is registered automatically by the plugin. No manual autoload entry in `project.godot`.

Each `.dialogue` file begins with `using StateSystem` to expose StateSystem properties for conditions and mutations.

A custom `DialogueBalloon` scene (based on DM's example balloon) handles:
- `DialogueLabel` for typewriter text
- Response button container
- Input action mapping to balloon navigation
- Graceful close on dialogue end

### Main Risks

1. **Dialogue condition mapping accuracy** — Custom conditions use a dictionary format (`{"type": "slider", "axis": "hope", "op": "gte", "value": 5}`). DM uses GDScript expressions (`GameState.hope >= 5`). The 13 JSON→.dialogue conversions must preserve all condition logic exactly.

2. **Effect completeness** — Custom `_apply_effects()` handles 5 effect types: `slider_delta`, `set_flag`, `trigger_event`, `advance_clock`, `play_sound`. `trigger_event` and `advance_clock` currently print warnings (not implemented). DM's `do` mutation syntax can call any method on the state autoload, but `trigger_event` and `advance_clock` must be implemented as `do GameManager.trigger_event(...)` or similar.

3. **Test migration completeness** — 6+ dialogue test files exist across `tests/`, `tests/unit/`, and `tests/integration/`. Each uses the custom dialogue API (`DialogueRunner.load_dialogue()`, `DialogueRunner.start()`, `DialogueConditionEvaluator.evaluate()`). All must be rewritten to use `DialogueManager.get_next_dialogue_line()`.

4. **Headless mode compatibility** — `DialogueLabel` rendering won't work in `--headless` mode (no Control canvas). All headless tests must use the DM API directly without balloon instantiation.

### Next Steps for Plan Agent

1. Install godot_dialogue_manager v3.10.5 (download, extract, enable plugin)
2. Create `DialogueBalloon.tscn` + `dialogue_balloon.gd` (custom balloon, typewriter, response navigation, input mapping)
3. Create one `.dialogue` test file with:
   - `if GameState.hope_despair >= 5` conditional response
   - `if GameState.conviction >= 3` conditional response
   - `set StateSystem.route_flag = "keep_walking"` mutation
4. Write `tests/test_dialogue_manager_integration.gd`:
   - Test conditional branching (response.is_allowed)
   - Test state mutations via dialogue
   - Test headless API calls
5. Migrate the first JSON file (`bartender.json` → `bartender.dialogue`) as proof of concept
6. Remove/disable custom dialogue files (DialogueRunner, DialogueParser, etc.) — keep them until full migration confirmed
7. Run `godot --headless --quit` and `godot --headless --script tests/run_tests.gd` — must pass with no errors

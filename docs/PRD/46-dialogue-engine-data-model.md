# Research: Dialogue Engine — Data Model + Conditional Branching

> Parent Issue: #46
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

The project currently has no dialogue system. `gdscripts/game_manager.gd` is a skeleton Autoload with a single `start_game()` method. `gdscripts/main.gd` displays a "Hello World" label. There is no data model for dialogue nodes, no runtime condition evaluator, and no serialization format for authoring dialogue.

The CRPG core mechanics design (Issue #5 PRD) defines three state axes — **Hope/Despair**, **Vigor/Burnout**, **Conviction/Falter** — plus associated mechanisms (Dialogue-as-Check, World-View Filter, Rain Pressure, 3-Month Clock). However, none of these mechanisms can be implemented without a dialogue engine that reads GameState at runtime and branches accordingly.

The theme-mechanic mapping (Issue #42 PRD) specifies that dialogue is the primary interaction surface: every NPC conversation is a "state check" where the player's current slider values determine available dialogue branches and the tone of responses. This demands a dialogue data model that is **condition-aware by design**.

### Expected Behavior

A dialogue engine data model that:

1. **DialogueNode** — represents a single turn in a conversation, containing speaker text and a list of outgoing choices.
2. **Choice** — represents a player response option, with optional **condition predicates** that gate visibility/availability.
3. **Condition** — a declarative expression that reads `GameState` (sliders, flags, previous choices) at runtime and returns true/false.
4. **DialogueTree** — a graph of `DialogueNode`s serialized from a resource file (JSON or Godot Resource).
5. **Runtime Evaluator** — evaluates conditions against the current `GameState` and resolves which choices/nodes are reachable.
6. **Side Effects** — each choice may trigger state mutations: slider deltas, flag toggles, or narrative event triggers.

### User Scenarios

- **Scenario A (Writer/Designer):** A narrative designer writes dialogue in a JSON file. They define a node with NPC text like *"You look tired. How late did you work last night?"* and three choices: (A) "Didn't sleep" — only visible if `vigor < 4`, adds `+1 despair`; (B) "I'm fine" — only visible if `conviction > 5`, adds `+1 conviction`; (C) "..." — always available, adds no state change. The engine reads this JSON and presents only choice C to a burned-out player, but all three to a confident one.

- **Scenario B (Player):** The player has high Despair (7/10) and low Vigor (3/10). They encounter an NPC. The dialogue engine evaluates all choices for the current node, filters out those whose conditions fail, and presents only the 2 reachable choices. The player picks one, which triggers slider mutations and advances to the next node.

- **Scenario C (Engineer):** A developer writes a dialogue test: they set `GameState.hope = 3`, load a dialogue tree, simulate stepping through it, and assert that exactly 2 of 5 choices are available. They verify that after picking choice B, `hope` increases to 4 and the next node ID matches expectations.

- **Frequency:** Every NPC interaction in the game — this is the primary gameplay loop.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project is in early scaffolding phase. Issues #1 (Hello World) and #6 (scaffold) set up the minimal Godot project. Issue #5 defined the high-level CRPG mechanics. Dialogue has been deferred until the mechanic design stabilized, because the dialogue engine's data model must directly reflect the game's state system — you cannot design dialogue nodes without knowing what conditions they check.

### Why Change Now?

1. **Dependency chain:** The dialogue engine is a prerequisite for Issues #2 (Narrative Architecture), #4 (State-World Feedback), and all subsequent dialogue-dependent features. Without a data model, no dialogue content can be authored or tested.
2. **Design maturity:** The three-axis slider system (Issue #5) and theme-mechanic mapping (Issue #42) are now complete. The condition vocabulary (what the engine checks) is known.
3. **Risk of serialization lock-in:** Early choice of data format (JSON vs Godot Resource) affects authoring workflow, editor tools, and runtime performance. Resolving this now prevents costly migration later.
4. **Previous attempt:** PR #61 was closed without merge, indicating the previous PRD was insufficient or the branch was abandoned. This fresh start incorporates the broader design context now available from Issues #5 and #42.

### Previous Constraints

- Engine: Godot 4.7.1
- Language: GDScript 2.0 (static types)
- State system: Three slider pairs (Hope/Despair, Vigor/Burnout, Conviction/Falter), each 1-10, sum=10
- Dependencies: Issue #43 (GameState implementation) must provide the state reading API
- Content scale: ~7 scenes, 5 NPCs, ~14-21 major interactions (from Issue #5 PRD Spike)
- Authoring format must be human-editable (designers write dialogue, not developers)
- Hemingway constraint: dialogue lines ≤ 25 words, paragraphs ≤ 3 sentences

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/dialogue_engine.gd` | Dialogue Engine | **New** — core runtime: node traversal, condition eval, side effects |
| `gdscripts/dialogue_resource.gd` | Resource Definition | **New** — Godot `@tool` Resource for dialogue tree serialization |
| `docs/PRD/46-dialogue-engine-data-model.md` | PRD | **New** — this document |
| `gdscripts/game_manager.gd` | GameState | Extended — must expose read API for sliders + flags |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `docs/DESIGN/dialogue-engine.md` | Design Doc | Plan agent output depends on this PRD |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | GDD | Core gameplay description needs update |
| `scenes/` | Scenes | NPC scenes will need DialoguePlayer nodes |
| `tests/` | Tests | Dialogue engine unit tests needed |
| `agents/skills/game-implement-agent/` | Agent skill | May need update for dialogue-related PRs |

### Data Flow Impact

```
dialogue.json (authoring format)
       │
       ▼
DialogueResource.gd (loads JSON → Godot Resource)
       │
       ▼
DialogueEngine.gd (runtime)
       │
       ├──► reads GameState (sliders, flags) via game_manager.gd
       ├──► evaluates Condition predicates on each Choice
       ├──► filters unavailable choices → presents reachable set
       ├──► on choice select: applies side effects (slider deltas, flag toggles)
       └──► advances to next DialogueNode
```

### Documents to Update

- [x] **This output:** `docs/PRD/46-dialogue-engine-data-model.md`
- [ ] `docs/DESIGN/dialogue-engine.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md` — Add dialogue engine to core loop description
- [ ] `README.md` — Update feature list (if needed)

---

## 4. Solution Comparison

### Approach A: Godot Custom Resource — `@export`-based data model

**Description:**

Define a Godot `Resource` subclass (`DialogueGraph.gd`) with `@export` arrays for nodes and choices. Each `DialogueNode` is a `Resource` with fields: `id: String`, `speaker: String`, `text: String`, `choices: Array[ChoiceResource]`. Each `ChoiceResource` has: `text: String`, `next_node_id: String`, `condition: ConditionResource`, `side_effects: Array[EffectResource]`. Conditions are also `@export`-based resources with enums for operator (`>=`, `<=`, `==`, `has_flag`) and operands.

The entire graph is authored via Godot's Inspector UI (via `@tool` script) or programmatically. Serialization is native `.tres`/`.res` format.

**Pros:**
- Native Godot serialization (`.tres` is human-readable, `.res` is compact)
- Inspector-driven authoring — designers can edit in-editor
- Strong typing via GDScript 2.0 `@export` type hints
- Native resource caching and loading
- Easy to version control (`.tres` is text-based)

**Cons:**
- Less portable than JSON — cannot be easily edited outside Godot
- `@export` arrays of Resources are verbose in `.tres` format
- Writer-friendly tooling requires Godot editor open
- Nested resource definitions add boilerplate

**Risk:** Low — Godot `Resource` is well-supported and the `.tres` format is human-readable

**Effort:** Medium (2-3 weeks: model, parser, runtime, test)

---

### Approach B: JSON-based data model with GDScript parser

**Description:**

Dialogue trees are authored as standalone JSON files (e.g., `dialogues/npc_bartender.json`). A GDScript parser (`DialogueParser.gd`) reads JSON at runtime (or preload time) and converts it into an internal dictionary-based structure. Condition predicates are string expressions evaluated via a mini-DSL or a dict of operator+operand (e.g., `{"op": "gte", "lhs": "state.hope", "rhs": 5}`).

**Pros:**
- JSON is universal — any editor, any platform
- Non-technical writers can author dialogue in their preferred tools
- No Godot editor dependency for dialogue editing
- Easy to diff and merge in git
- Can be auto-generated from external tools (Twine, Yarn, etc.)

**Cons:**
- No intrinsic type safety — must validate at load time
- JSON parsing adds a loading step and potential runtime errors
- No inspector-based editing inside Godot
- Need a custom validation script for correctness
- Nested JSON can become unwieldy for large trees

**Risk:** Low-Medium — JSON parsing is simple but runtime validation is required

**Effort:** Medium (2-3 weeks: JSON schema + parser + runtime + validation)

---

### Approach C: Hybrid — JSON authoring format + Godot Resource at runtime

**Description:**

Dialogue is authored in JSON (for writer ergonomics). A `@tool` script in Godot converts the JSON into a Godot `Resource` at import time (or on save). The runtime engine always operates on `DialogueResource` objects, never touching JSON directly. This combines the flexibility of Approach B with the type safety of Approach A.

The conversion step is a GDScript `@tool` function that reads JSON, validates it against a schema, and emits a `.tres` file that the runtime loads natively.

**Pros:**
- Best of both worlds — authors write JSON, engine uses Resources
- One-time conversion cost (on save or import)
- Validation happens at conversion time, not at gameplay time
- `.tres` can be hand-edited in a pinch
- Compatible with external authoring pipelines

**Cons:**
- More complex pipeline — two formats to maintain
- Conversion script must be kept in sync with both schemas
- Adds a build/import step to the authoring workflow
- More code to test and debug

**Risk:** Medium — pipeline complexity higher, but each half is individually simple

**Effort:** Large (3-4 weeks: JSON schema + converter + resource model + runtime + tests)

---

### Recommendation

→ **Approach B (JSON-based)** because:

1. **Writer ergonomics:** The project targets a small team (likely solo or 2-person). Designers and writers will author dialogue in markdown/editors before importing to Godot. JSON is universally editable; `.tres` requires Godot open.
2. **Portability:** JSON files can be diffed, merged, reviewed (via PR), and auto-generated from external tools (Twine, Articy, Yarn Spinner export). This aligns with the git-centric workflow.
3. **Proportional complexity:** The game has ~14-21 major interactions across 5 NPCs (from Issue #5 spike). A JSON-to-dict approach at this scale requires far less ceremony than full Resource definitions.
4. **Previous precedent:** The existing codebase is too young to have a resource serialization pattern. Adopting a JSON-first model avoids committing to a Godot-specific approach before the project's toolchain is established.
5. **Condition DSL maturity:** The condition system is compact (3 slider axes + flags + previous choice IDs). A declarative dict format (`{"type": "slider", "axis": "hope", "op": "gte", "value": 5}`) is simpler to implement and debug than a full expression parser.

**Mitigation for typing concerns:**
- Implement a `DialogueValidator.gd` `@tool` script that validates JSON on Godot open
- Use a typed `DialogueParser.gd` that returns `DialogueNode`-like dictionaries with enum-based keys
- Unit test the parser with known-good and known-bad JSON fixtures

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 Data Model Definition

#### DialogueNode

```gdscript
# Internal dict shape (parsed from JSON):
# {
#   "id": "npc_bartender_01",
#   "speaker": "Bartender",
#   "text": "You again. Same as usual?",
#   "choices": [Choice, ...],
#   "on_enter": [Effect, ...],   # side effects when this node is entered
#   "tags": ["bartender", "night_2"]
# }
```

#### Choice

```gdscript
# {
#   "text": "Yeah, the usual.",
#   "next_node": "npc_bartender_02",
#   "condition": Condition,       # optional — if absent, always available
#   "effects": [Effect, ...]      # side effects on selection
# }
```

#### Condition

```gdscript
# Supported types:
#
# 1. Slider comparison (axis: "hope"|"despair"|"vigor"|"burnout"|"conviction"|"falter")
#    {"type": "slider", "axis": "hope", "op": "gte", "value": 5}
#    op: "gte" | "lte" | "eq" | "gt" | "lt"
#
# 2. Flag check
#    {"type": "flag", "flag": "met_bartender", "value": true}
#
# 3. Previous choice check
#    {"type": "choice_made", "node_id": "npc_bartender_01", "choice_index": 0}
#
# 4. Compound (AND / OR)
#    {"type": "and", "conditions": [Condition, Condition, ...]}
#    {"type": "or",  "conditions": [Condition, Condition, ...]}
#
# 5. Not
#    {"type": "not", "condition": Condition}
```

#### Effect (Side Effects)

```gdscript
# {
#   "type": "slider_delta",
#   "axis": "hope",
#   "delta": 1
# }
# {
#   "type": "set_flag",
#   "flag": "helped_bartender",
#   "value": true
# }
# {
#   "type": "trigger_event",
#   "event": "rain_intensifies"
# }
# {
#   "type": "advance_clock",
#   "days": 1
# }
```

### 5.2 Normal Path

1. **Load:** Game loads JSON dialogue file for the current NPC → `DialogueParser.parse()` validates and returns a dict-based dialogue tree indexed by node ID
2. **Enter:** Player triggers an NPC interaction → engine calls `enter_node(start_node_id)`
3. **Evaluate:** Engine evaluates all choices' conditions against `GameState` → produces reachable list
4. **Present:** UI shows NPC text + filtered choice list to player
5. **Select:** Player picks a choice → engine applies side effects (slider deltas, flags), advances to next node
6. **Repeat:** Steps 2-5 until a terminal node (no choices or `next_node` is null) ends conversation

### 5.3 Edge Cases

1. **All choices gated:** Player's state satisfies zero conditions for the current node. **Expected:** Engine falls back to a "default" choice (marked `"default": true` in JSON), or auto-selects the next required node. If no default exists, the conversation ends gracefully.
2. **Circular dialogue:** Two nodes reference each other. **Expected:** Engine tracks visited node IDs in a `visited_nodes` set per conversation; if `max_visits` (configurable, default 3) is exceeded, force-exit the conversation.
3. **Missing node reference:** A choice's `next_node` does not exist in the tree. **Expected:** Parser validation catches this on load; runtime falls back to ending the conversation. Error logged to `push_error()`.
4. **Concurrent side effects:** A choice triggers both `slider_delta` and `set_flag`. **Expected:** Effects are applied in array order, each one mutates GameState before the next is evaluated.
5. **Slider value overflow:** `hope = 10`, effect `{"delta": 1}`. **Expected:** Clamp to [1, 10] range. Similarly for underflow.
6. **Empty dialogue JSON:** File exists but has no nodes. **Expected:** Parse error at load time with descriptive message.

### 5.4 Failure Paths

1. **Malformed JSON:** JSON syntax error in dialogue file. **Expected:** `DialogueParser` returns an error dictionary with line number and description; engine logs error and shows a fallback "..." response.
2. **Missing dialogue file:** File path doesn't exist. **Expected:** `DialogueManager.load_dialogue(id)` returns null; caller handles gracefully (doesn't crash).
3. **Invalid condition type:** Unknown `type` in condition dict. **Expected:** Condition evaluator returns `false` for unknown types, logs a warning.
4. **Parser state corruption:** Dialogue tree has duplicate node IDs. **Expected:** Parser validation detects duplicates on load and returns an error; engine refuses to load the tree.

### 5.5 Acceptance Criteria

- [x] AC1: DialogueNode can hold multiple choice branches with condition predicates.
- [x] AC2: Conditions can read hope/despair slider, flags, and previous choices.
- [x] AC3: Serialization/deserialization of dialogues from a resource file (JSON).
- [ ] AC4: A choice with an unmet condition is hidden from the player.
- [ ] AC5: A choice with a met condition is visible and selectable.
- [ ] AC6: Side effects (slider deltas, flag toggles) are correctly applied on choice selection.
- [ ] AC7: Compound conditions (AND/OR/NOT) evaluate correctly.
- [ ] AC8: Invalid dialogue JSON is caught at load time with a descriptive error.
- [ ] AC9: The engine falls back gracefully when all choices are gated (default choice or graceful exit).

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #43 — GameState implementation | In-flux | **High** — Dialogue engine's condition evaluator needs a concrete GameState API. Without knowing the exact method signatures (e.g., `get_slider("hope") -> int`, `has_flag("met_bartender") -> bool`, `set_slider("hope", 5)`), the condition DSL cannot be finalized. |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #2 — Narrative Architecture & Ending Graph | Critical — dialogue engine is the runtime for all narrative content |
| Issue #4 — State-World Feedback System | Critical — feedback is triggered by dialogue side effects |
| All NPC dialogue implementation | High — every NPC scene depends on this engine |

### Preparation Needed

- [ ] Issue #43 must define the GameState read/write API before condition evaluator can be finalized
- [ ] Define the JSON schema (`dialogue-schema.json`) for validation
- [ ] Write `DialogueParser.gd` with `@tool` support for in-editor validation
- [ ] Write `DialogueConditionEvaluator.gd` — pure function: `evaluate(condition, state) -> bool`
- [ ] Write `DialogueRunner.gd` — stateful runtime that tracks current node, visited nodes, applies effects

---

## 7. Spike / Experiment (Optional — depth/standard)

> Section 7 is optional for `depth/standard`. Key design uncertainties are deferred to the Plan phase through the Open Questions below.

### Open Questions for Plan Phase

1. **Dialogue JSON file organization:** One file per NPC (e.g., `dialogues/bartender.json`) or one master file (`dialogues/all.json`)? One-per-NPC scales better for version control.
2. **String IDs vs integer IDs for nodes:** String IDs (`"bartender_greeting_01"`) are more readable; integer IDs are more compact. Strings preferred for authoring.
3. **Condition DSL evolution:** Should the condition system support arithmetic at runtime (e.g., `hope + vigor > 10`)? Current scope says no — keep it declarative.
4. **Dialogue editor integration:** Is an in-game dialogue debugger (showing reachable choices, current state, history) needed for development? Yes — should be a togglable debug overlay using Godot's `EditorInterface` or a dev-only scene.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The dialogue engine is currently in the design research phase. No code exists for dialogue parsing, condition evaluation, or runtime traversal. The project has a skeleton `GameManager` Autoload at `gdscripts/game_manager.gd` that needs to be extended with the GameState API (Issue #43) before the dialogue engine can be fully implemented.

The recommended approach is **JSON-based data model (Approach B)** with a GDScript parser that validates and loads dialogue trees at runtime. The condition DSL is declarative (operator + operands, no arbitrary expressions) covering slider comparisons, flag checks, previous choice tracking, and compound AND/OR/NOT logic.

The dialogue engine comprises three components:
1. **DialogueParser.gd** — loads JSON, validates schema, returns parsed dict structure
2. **DialogueConditionEvaluator.gd** — evaluates a Condition dict against GameState
3. **DialogueRunner.gd** — stateful runtime: enter node, evaluate choices, apply effects, advance

The main risk is dependency on Issue #43's GameState API. If the API surface differs from what this PRD assumes, the condition evaluator's interface will need adjustment. The condition DSL is designed to be thin — wrapping GameState's read methods — so adaptation should be minimal.

**Key design decisions for the Plan agent:**
1. Exact JSON schema (field names, optionality, nesting)
2. Error handling strategy (graceful fallback vs crash-on-invalid)
3. Dialogue file loading strategy (preload all vs lazy-load per NPC)
4. Debug overlay design for development
5. How `DialogueRunner` integrates with scene nodes (signals? direct calls?)

# Research: [Feature] NPC Framework + Convenience Clerk

> Parent Issue: #54
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project currently has **no reusable NPC framework**. Each NPC is implemented as bespoke logic embedded in its scene:

| NPC | Scene | Implementation Pattern | Reusable? |
|-----|-------|----------------------|-----------|
| Security Guard | `lobby` | Area3D trigger → `dialogue_runner.start()` in `lobby.gd` | ❌ — hardcoded in lobby script |
| Store Clerk | `store` | Area3D trigger → `dialogue_runner.start()` in `store.gd` | ❌ — hardcoded in store script |
| Stranger (first) | `lobby` | Area3D trigger → `dialogue_runner.start()` in `lobby.gd` | ❌ — hardcoded |
| Stranger (echo) | `underpass` | Area3D trigger → `dialogue_runner.start()` in `underpass.gd` | ❌ — hardcoded |
| Homeless Person | `bridge` | Area3D trigger → `dialogue_runner.start()` in `bridge.gd` | ❌ — hardcoded |
| Bartender | (PRD only) | Not yet implemented | ❌ — no pattern to follow |

Each scene re-implements the same interaction loop:
1. Declare an `@onready` Area3D for interaction trigger
2. Wire `input_event` signal in `_ready()`
3. On click, call `dialogue_runner.start(path, id)`
4. Optionally configure state-aware environmental text manually

**Key problems:**

1. **No standardized NPC component** — Every NPC requires ~15–30 lines of boilerplate per scene. Adding an NPC means modifying the scene script, scene TSCN, dialogue JSON, and constants file. There is no single "drop-in" NPC scene.

2. **No NPC state machine** — NPCs have no state system (idle, talking, post-dialogue). The clerk's dialogue has no structural life cycle — once the conversation ends, the NPC has no post-dialogue state (e.g., "has seen the player before" beyond raw flags).

3. **No sprite label or visual indicator** — The store clerk has a static `Label3D` (`⌈Clerk⌋`) in the scene TSCN. Other NPCs have no visual label at all. There is no standardized "interactable NPC" visual indication — no floating name, no interaction prompt, no proximity-based highlight.

4. **No NPC personality metadata** — NPC dialogue JSONs define speaker name inline per node but lack a centralized personality profile: greeting style, attitude spectrum, voice tone hints, or mood modifiers based on game state.

5. **Clerk dialogue exists but lacks layered personality** — The current `store_clerk.json` (283 lines) has solid branching (greeting, coffee purchase, comfort, shelf exploration, window gazing) with basic state gating (hope ≥ 6, hope ≤ 3, will gte/lt 6). However, it lacks the **three-layer personality** required by Issue #54's AC:
   - **Layer 1 (Tired Worker)**: Generic exhausted convenience store worker — survives the shift
   - **Layer 2 (Cynical Veteran)**: Has been doing this for years — resignation masked as humor
   - **Layer 3 (Systemic Exhaustion)**: The job, the system, the city — a shared resignation that subtly acknowledges the player's office life

6. **No office reference in clerk dialogue** — AC3 requires the clerk's lines to contain subtle references to the player's office choice, revealing a shared understanding of "the grind." The current dialogue has no such references.

### Expected Behavior

A reusable **NPC Framework** that:

1. **NPCNode (Reusable Component)** — A Godot scene (`NPC.tscn`) with:
   - An interactable Area3D trigger
   - A floating Label3D (speaker name, conditionally visible)
   - An interaction prompt Label3D (e.g., "⌈Talk⌋") that appears on proximity
   - A built-in state machine: `idle → talking → post_dialogue`
   - Exported properties: `dialogue_file`, `dialogue_id`, `speaker_name`
   - Exported state modifiers: `mood_axis` (which slider drives attitude), `mood_multiplier`
   - Signals: `npc_interacted`, `dialogue_completed`, `npc_state_changed(state)`

2. **NPCState enum** — States: `IDLE` (awaiting interaction), `TALKING` (in dialogue), `COOLDOWN` (brief post-dialogue), `EXHAUSTED` (all branches exhausted), `SPECIAL` (conditional state for unique responses)

3. **Convenience Clerk (First NPC Implementation)** — Implements the framework with three-layer personality:
   - **Tired Worker Layer** (default, all states): Generic "another night shift" exhaustion. The "I'm just here for the paycheck" affect.
   - **Cynical Veteran Layer** (hope < 5 or conviction < 5): Years of doing this have worn through. Lines shift from tired to bitter. Masked cynicism about "the system."
   - **Systemic Exhaustion Layer** (hope_despair ≤ -2): Shared resignation. Clerk's lines subtly reference the player's office choice (e.g., "Some of us clock out, some of us never do" — acknowledging the player just left their office grind).

### User Scenarios

- **Scenario A (Developer adding an NPC):** Developer creates a new NPC by instancing `NPC.tscn` into a scene, sets `dialogue_file = "res://dialogues/new_npc.json"`, `speaker_name = "Bartender"`, and `mood_axis = "hope_despair"`. No scene script modification needed. The NPC automatically shows its name label on proximity, triggers dialogue on click, and cycles through its state machine.

- **Scenario B (Player interacting with clerk at low hope):** Player enters convenience store with hope_despair = -2 (Despair state). The clerk's label reads "⌈Exhausted Voice⌋". Clicking triggers dialogue where the clerk's greeting is from the Systemic Exhaustion layer: "Oh. Another one from the office tower." The player's office choice (from `office_door.json`) is checked via flag — if they chose "Sigh, one more thing to do" (low conviction exit), the clerk says "Yeah. I know that sigh."

- **Scenario C (Player interacting with clerk at high hope):** Player has hope > 5. The clerk's greeting is from the Tired Worker layer: "Hey. Late again?" The player's office choice is checked — if they chose "One more day down" (neutral exit), the clerk says "One more day. That's the spirit, I guess." The cynicism is mild, almost friendly.

- **Frequency:** Every playthrough interacts with the clerk. The NPC framework is used by all 6+ NPCs in the game, making it a core reusable component.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally through layered issues:

| Phase | Issues | What Was Built | NPC Pattern |
|-------|--------|---------------|-------------|
| Scaffold | #43, #6, #1 | Project structure, GameState, main scene | None — no NPCs |
| Dialogue Engine | #46, #52 | DialogueParser, Runner, ConditionEvaluator, Display3D | No scene integration yet |
| Narrative Architecture | #45, #55 | SceneBase, scene sequence, scene scripts | Bespoke triggers per scene |
| Dialogue Content | #55, #56 | Dialogue JSONs (store_clerk, lobby_guard, etc.) | Trigger per scene script |

Each scene was authored independently with inline NPC trigger logic because:
1. **No abstraction pressure** — With only 5–6 NPCs, the repetition wasn't obvious enough to warrant abstraction.
2. **SceneBase is the only shared base** — SceneBase provides `start_dialogue()` but nothing NPC-specific.
3. **Dialogue engine maturity** — The dialogue engine was only recently completed (#46/#52). NPC framework design could not start until the engine was stable.

### Why Change Now?

1. **NPC count crosses the threshold** — With the Stranger (3 encounters), Clerk, Guard, Homeless Person, and planned Bartender, there are 7+ NPC interaction points. The bespoke-per-scene pattern no longer scales.

2. **Issue #59 (Mysterious Stranger) demonstrates the gap** — The Stranger PRD had to design its own state-dependent dialogue triggering within `underpass.gd`. A framework would have provided this infrastructure.

3. **Clerk's layered personality is the prototype** — The three-layer personality (tired worker → cynical veteran → systemic exhaustion) maps naturally to a state-driven NPC framework. Implementing the clerk first validates the framework design.

4. **Dependencies are ready** — Dialogue engine (#46, #52), GameState (#47, #50), SceneBase (#45), and scene structure (#55) are all complete.

5. **Content authoring efficiency** — Future NPCs (Bartender, additional strangers, subway station attendant) will reuse the framework without per-scene boilerplate.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| State system | Tri-axis via StateSystem: hope_despair (-10 to +10), conviction (0-10), will (0-10) |
| Dialogue format | JSON-based, loaded by DialogueRunner (lazy-load) |
| Dialogue engine signals | `dialogue_started`, `dialogue_ended`, `node_changed`, `choices_available`, `choice_made` |
| SceneBase pattern | `_ready()` → fade_in, config env text, restore dialogue state |
| Scene transition | SceneManager with fade curtain (0.5s AnimationPlayer) |
| Visual style | Edward Hopper urban night — dark, warm amber light, lo-fi pixel text |
| Writing style | Hemingway — short lines, iceberg theory |
| Label3D style | LoFiText3D with pixel_factor, emissive, billboard |
| Interaction model | Click-to-interact via Area3D `input_event` signal |
| Existing clerk dialogue | `store_clerk.json` (283 lines, 14 nodes) with basic slider gating |
| Existing clerk flags | `bought_coffee`, `chatted_with_clerk`, `clerk_comforted` |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/npc_node.gd` | NPC Framework | **New** — Core NPC scene script: state machine, interaction handling, label management |
| `scenes/components/NPC.tscn` | NPC Scene | **New** — Reusable NPC scene: Area3D trigger, Label3D name + prompt, state controller |
| `gdscripts/npc_state.gd` | NPC State | **New** — NPCState enum (IDLE, TALKING, COOLDOWN, EXHAUSTED, SPECIAL) |
| `gdscripts/npc_personality.gd` | NPC Personality | **New** — Personality profile resource: layer definitions, mood axis mapping, condition-to-layer mapping |
| `dialogues/store_clerk.json` | Clerk Dialogue | **Modified** — Expand from basic branching to 3-layer personality dialogue; add office reference branches (AC3) |
| `gdscripts/store.gd` | Store Scene | **Modified** — Replace inline clerk trigger with NPC.tscn instance; simplify to framework usage |
| `scenes/store/convenience_store.tscn` | Store Scene | **Modified** — Replace inline ClerkNode/Label/Trigger with NPC.tscn component |
| `gdscripts/constants.gd` | Constants | **Modified** — Add NPC framework constants, dialogue path for expanded clerk file |
| `dialogues/lobby_guard.json` | Guard Dialogue | Optionally updated to demonstrate reusability |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/scene_base.gd` | SceneBase | Optional: Add helper method `spawn_npc(dialogue_file, speaker_name)` for convenience |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | GDD | Document NPC framework alongside dialogue engine |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | GDD | Update NPC interaction patterns |
| `tests/` | Tests | New tests for NPC state machine, personality layer evaluation, and clerk dialogue |
| `dialogues/office_door.json` | Office Dialogue | The office choice flags that clerk references must be clearly documented |
| `gdscripts/dialogue_runner.gd` | Dialogue Runner | No changes needed — NPC framework consumes existing signals |

### Data Flow Impact

```
Scene Load
    │
    ├──► NPC.tscn instance (child of scene)
    │       ├──► _ready(): reads exported dialogue_file, speaker_name,
    │       │             mood_axis. Sets up Area3D trigger.
    │       │             Sets initial NPCState = IDLE.
    │       │             Hides name label (shows on proximity).
    │       │
    │       ├──► On body_entered (player proximity):
    │       │       └──► Shows name label + interaction prompt ("⌈Talk⌋")
    │       │
    │       ├──► On input_event (click):
    │       │       ├──► Sets NPCState = TALKING
    │       │       ├──► Evaluates personality layers against GameState:
    │       │       │       Layer 1 (Tired Worker): default — no condition check
    │       │       │       Layer 2 (Cynical Veteran): hope < 5 OR conviction < 5
    │       │       │       Layer 3 (Systemic Exhaustion): hope_despair ≤ -2
    │       │       └──► Calls dialogue_runner.start(dialogue_file, dialogue_id)
    │       │               └──► DialogueRunner loads JSON → evaluates conditions →
    │       │                   presents layer-appropriate branches
    │       │
    │       ├──► On dialogue_ended signal:
    │       │       ├──► Sets NPCState = COOLDOWN
    │       │       ├──► After cooldown timer: sets NPCState = IDLE
    │       │       │   (or EXHAUSTED if all branches visited)
    │       │       └──► Updates interaction prompt based on state
    │       │
    │       └──► On state_changed signal (optional):
    │               └──► If mood_axis crosses personality layer threshold,
    │                   dynamically updates name label (e.g., "Tired Clerk" → "Exhausted Voice")
    │
    └──► SceneBase._ready() (unchanged from current pattern)

Dialogue Flow (Clerk-specific):
    dialogue_runner.start("store_clerk.json", "store_clerk")
        │
        ├──► Layer determination (NPC framework checks state BEFORE dialogue):
        │       Layer 1: State OK → entry node = "clerk_greet" (existing)
        │       Layer 2: hope < 5 → entry node = "clerk_greet_cynical" (new)
        │       Layer 3: hope_despair ≤ -2 → entry node = "clerk_greet_systemic" (new)
        │
        └──► All layers check office choice flags:
                ├─── office_choice_sigh → clerk acknowledges the sigh
                ├─── office_choice_neutral → clerk mirrors neutrality
                └─── office_choice_determined → clerk: "At least one of us has energy"
```

### Documents to Update

- [x] **This output:** `docs/PRD/54-npc-framework-convenience-clerk.md`
- [ ] `docs/DESIGN/54-npc-framework-convenience-clerk.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Add NPC framework section
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` — Update NPC interaction to reference framework
- [ ] `docs/GAME_DESIGN/INDEX.md` — Update index

---

## 4. Solution Comparison

### Approach A: NPC.gd + NPC.tscn Dedicated Scene Component (Recommended)

**Description:**

Create a standalone `NPC.tscn` scene with an accompanying `NPCNode.gd` script. The scene is a composition node that includes:

```gdscript
# NPCNode.gd — Core NPC framework script
extends Node3D
class_name NPCNode

enum NPCState { IDLE, TALKING, COOLDOWN, EXHAUSTED, SPECIAL }

# --- Exported Properties ---
@export var dialogue_file: String = ""
@export var dialogue_id: String = ""
@export var speaker_name: String = "NPC"
@export var mood_axis: String = "hope_despair"  # Which slider drives personality
@export var proximity_distance: float = 3.0
@export var cooldown_seconds: float = 2.0
@export var name_label_visible: bool = true
@export var interaction_prompt_text: String = "⌈Talk⌋"

# --- Personality Layers (optional) ---
# Each layer is a condition → modifier map
# Conditions use the same DSL as dialogue conditions
@export var personality_layers: Array[Dictionary] = []

# Layers evaluated in order; first match determines tone
# Example:
# [{
#   "name": "tired_worker",
#   "condition": {"type": "always"},  # default
#   "name_prefix": "⌈Clerk⌋",
#   "greeting_override": ""
# }, {
#   "name": "cynical_veteran",
#   "condition": {"type": "and", "conditions": [
#     {"type": "slider", "axis": "hope_despair", "op": "lt", "value": 0}
#   ]},
#   "name_prefix": "⌈Clerk (distant)⌋"
# }, {
#   "name": "systemic_exhaustion",
#   "condition": {"type": "slider", "axis": "hope_despair", "op": "lte", "value": -2},
#   "name_prefix": "⌈Tired Voice⌋",
#   "greeting_override": "clerk_greet_systemic"  # Override entry node
# }]

# --- Internal State ---
var current_state: NPCState = NPCState.IDLE
var active_layer: Dictionary = {}  # Currently active personality layer
var _trigger_area: Area3D
var _name_label: Label3D
var _prompt_label: Label3D
var _player_nearby: bool = false
```

**Scene tree (NPC.tscn):**
```
NPC (NPCNode — root, Node3D)
├── InteractionTrigger (Area3D)
│   └── CollisionShape3D (CylinderShape3D, radius ≈ proximity_distance)
├── VisualName (Label3D or LoFiText3D)
│       — Shows speaker_name, billboarded, emissive amber
│       — Visible only when player is in proximity
├── InteractionPrompt (Label3D or LoFiText3D)
│       — Shows "⌈Talk⌋" text, below name label
│       — Visible only when player is in proximity AND state == IDLE
├── CooldownTimer (Timer)
        — Auto-managed for COOLDOWN state transitions
```

**Lifecycle:**
1. `_ready()`: Connect `body_entered`/`body_exited` on trigger area. Connect `dialogue_ended` signal from DialogueRunner (resolved at runtime via `/root/` or passed via signal bus). Initialize state = IDLE.
2. `body_entered`: Player enters trigger → `_player_nearby = true` → show name + prompt labels.
3. `body_exited`: Player leaves trigger → `_player_nearby = false` → hide labels.
4. `_on_interaction(player)`: If state is IDLE and player clicked → evaluate personality layers → set state = TALKING → call `dialogue_runner.start(dialogue_file, dialogue_id)`. If a layer has `greeting_override`, pass it as the entry node.
5. `_on_dialogue_ended()`: Set state = COOLDOWN → start CooldownTimer → on timeout, set state = IDLE (or EXHAUSTED if dialogue has no remaining unvisited branches).
6. `_evaluate_layers()`: Iterate `personality_layers` in order, evaluate each layer's condition against current GameState, return the first match. Update `active_layer` and name label text.

**Pros:**
- **100% reusable** — Any scene can instance NPC.tscn, set 3–4 exported properties, and have a fully functional NPC
- **Self-contained** — No scene script modification needed. NPC handles its own trigger, labels, state, and interaction
- **Framework-first** — The three-layer personality for the clerk is the first "personality profile" that validates the `personality_layers` system
- **Dialogue-agnostic** — Works with any dialogue JSON; the layer system is purely visual + greeting selection
- **Signal-based integration** — Consumes existing DialogueRunner signals; no wiring changes needed
- **Testable in isolation** — NPCNode can be instanced in a test scene with a mock DialogueRunner
- **Progressive enhancement** — Minimal NPC (just name + trigger) works with 0 exported layers; full personality profile adds layers on top

**Cons:**
- **Label3D positioning** — NPC labels must be positioned above the NPC model; if the NPC has no visual mesh, the label floats at the root position. A `label_offset` export solves this.
- **Dependency on DialogueRunner** — `NPCNode` needs a reference to the DialogueRunner. Resolved at runtime via global signal bus or `/root/` path lookup.
- **Scene-specific tuning** — Proximity radius, label offset, and interaction prompt text may need per-scene overrides (handled by @export).
- **First NPC conversion cost** — Converting the existing store clerk from inline to NPC.tscn requires updating `store.gd` and `convenience_store.tscn`.

**Risk:** Low — Single reusable component with clear exported interface. The dialogue engine already provides the signals we consume.

**Effort:** 1–2 weeks (NPCNode script + NPC.tscn scene + personality layer system + store clerk conversion + expanded dialogue JSON + tests)

---

### Approach B: Extend SceneBase with NPC Methods

**Description:**

Add NPC-specific methods to `SceneBase.gd` rather than creating a standalone component. Each scene calls inherited methods to set up NPCs:

```gdscript
# SceneBase.gd additions
func setup_npc(npc_name: String, dialogue_file: String,
               trigger_node: Area3D, name_label: Label3D) -> void:
    trigger_node.input_event.connect(_on_npc_interacted.bind(npc_name, dialogue_file))
    name_label.text = "⌈%s⌋" % npc_name

func _on_npc_interacted(_camera: Node, event: InputEvent,
                         _position: Vector3, _normal: Vector3,
                         _shape_idx: int, npc_name: String,
                         dialogue_file: String) -> void:
    if event is InputEventMouseButton and event.pressed:
        dialogue_runner.start(dialogue_file, npc_name)
```

Personality layers would be implemented as separate per-NPC methods or a `get_npc_greeting(npc_id, state) → String` dispatcher in `GameManager` or a new `NPCManager`.

**Pros:**
- No new scene file — NPC setup stays within existing SceneBase pattern
- Familiar pattern — scenes already call inherited methods
- Minimal boilerplate reduction over current approach

**Cons:**
- **NOT reusable across non-SceneBase contexts** — If a non-scene Node needs an NPC (e.g., a UI-triggered dialogue), it can't use SceneBase methods
- **Per-scene trigger wiring still needed** — Each scene must still declare Area3D nodes, label nodes, and call `setup_npc()` with the right references
- **No state machine** — NPCs still don't have IDLE/TALKING/COOLDOWN states
- **No personality layer system** — Layer evaluation would need to be reimplemented per NPC
- **No visual label management** — Labels must be set up per scene (visibility, proximity detection, text formatting)
- **Code duplication** — Every NPC needs the same boilerplate: Area3D → input_event → dialogue_runner.start
- **Harder to test** — Can't test NPC behavior without loading a full scene

**Risk:** Low implementation risk, but perpetuates the bespoke-per-NPC pattern with marginal improvement.

**Effort:** 2–3 days (SceneBase extension + per-NPC setup in existing scenes)

---

### Approach C: NPCManager Autoload + Data-Driven NPC Profiles

**Description:**

Create an `NPCManager` autoload singleton that manages all NPC encounters. NPC profiles are defined in a JSON data file (`npc_profiles.json`):

```json
{
  "npcs": {
    "store_clerk": {
      "speaker_name": "Store Clerk",
      "dialogue_file": "res://dialogues/store_clerk.json",
      "mood_axis": "hope_despair",
      "personality_layers": [
        {"name": "tired_worker", "condition": {"type": "always"}, "greeting_override": "clerk_greet"},
        {"name": "cynical_veteran", "condition": {"type": "slider", ...}},
        {"name": "systemic_exhaustion", "condition": {...}}
      ]
    }
  }
}
```

Scene scripts call `NPCManager.register_trigger(npc_id, area_node, label_node)` to connect an Area3D to NPCManager's interaction handler. NPCManager listens to all registered areas and dispatches dialogue starts.

**Pros:**
- Centralized NPC data — all NPC profiles in one file
- Data-driven personality layers — JSON is author-friendly
- Single point of signal management — NPCManager connects to DialogueRunner once
- Profiling per-state is natural — NPCManager evaluates layers on each interaction

**Cons:**
- **Over-abstraction** — For 6 NPCs, a full autoload manager is disproportionate
- **Manager pattern complexity** — NPCManager must track multiple interaction areas across scene loads, handle scene transitions (disconnecting old triggers), and manage per-NPC state
- **Node reference fragility** — Area3D and Label3D references are stored in NPCManager across scene changes; stale references after scene transition are a real risk
- **No visual component** — NPCManager handles logic but doesn't provide the Label3D setup, proximity detection, or state machine
- **More autoloads** — Currently 5 autoloads (GameManager, GameState, NarrativeManager, AudioManager, StateSystem). Adding an NPCManager increases startup complexity
- **Dialogue engine already handles per-dialogue state** — `DialogueRunner.choices_made` already tracks per-conversation state. NPCManager would duplicate this at the NPC level
- **Scene-dependent Node references** — A manager pattern works for logic but poorly for scene-specific visual components

**Risk:** Medium-High — Manager pattern with scene-dependent node references is fragile. The dialogue engine already exists and manages dialogue lifecycle; adding a parallel NPC lifecycle manager creates coordination complexity.

**Effort:** 2–3 weeks (NPCManager autoload + JSON profile system + scene integration + migration of existing NPCs + tests)

---

### Recommendation

→ **Approach A (NPC.gd + NPC.tscn Dedicated Scene Component)** because:

1. **Clean separation of concerns** — The NPC component owns its visual labels, trigger area, and state machine. No scene script modification needed.

2. **Progressive complexity** — Simple NPCs work with 3 exported properties. The clerk's three-layer personality uses the personality_layers system as an advanced feature. Both extremes work without changing the component.

3. **Alignment with Godot composition pattern** — Godot 4.x encourages composition via child scenes. NPC.tscn as a child of any scene is the idiomatic Godot approach.

4. **No manager lifecycle complexity** — Unlike Approach C (NPCManager), each NPC component manages its own lifecycle. On scene unload, the NPC component is freed naturally with its parent scene.

5. **Existing signal infrastructure** — NPCNode connects to `dialogue_runner` signals via `/root/` path (same pattern SceneBase uses). No new signal wiring infrastructure needed.

6. **Testable in isolation** — NPCNode can be instanced in a test scene with a mock DialogueRunner. The state machine transitions and personality layer evaluation are pure methods.

7. **Incremental migration** — Existing NPCs (guard, stranger, homeless) can be migrated to NPC.tscn one at a time without breaking the game.

**Why not Approach B?** It doesn't provide a reusable scene component. Each scene still needs its own Area3D + Label3D + trigger wiring. The personality layer system would need per-NPC reimplementation.

**Why not Approach C?** A manager autoload for 6 NPCs is over-engineering. The manager-autoload pattern creates node reference fragility across scene transitions and adds lifecycle complexity that a composition-based approach avoids.

**Key design decisions for Approach A:**

1. NPCNode is a `Node3D` child of the root scene — not an autoload, not a global
2. DialogueRunner reference resolved at runtime: `get_node_or_null("/root/SceneBase").dialogue_runner` or a signal bus lookup
3. Personality layers are an `@export var Array[Dictionary]` — optional, defaults to empty (no layers = static NPC)
4. The first personality layer with matching condition wins (ordered evaluation)
5. Layer 0 is the "always" default — must match for all states if no layers defined
6. Name label uses LoFiText3D for consistency with the game's visual language
7. Interaction prompt shows only when player is in proximity AND state == IDLE
8. COOLDOWN state prevents rapid re-triggering after dialogue ends (configurable timer)
9. EXHAUSTED state is set when the dialogue tree has no unvisited branches (DialogueRunner tracks this)
10. NPCState signals `npc_state_changed(state: NPCState)` for scene-level listeners (e.g., update environmental text when clerk enters TALKING)

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 NPC Framework Components

#### NPCNode Exported Properties

```gdscript
@export var dialogue_file: String = ""
@export var dialogue_id: String = ""
@export var speaker_name: String = "NPC"
@export var mood_axis: String = "hope_despair"
@export var proximity_distance: float = 3.0
@export var cooldown_seconds: float = 2.0
@export var name_label_visible: bool = true
@export var interaction_prompt_text: String = "⌈Talk⌋"
@export var personality_layers: Array[Dictionary] = []
@export var label_offset: Vector3 = Vector3(0, 1.5, 0)
```

#### NPCState Enum

| State | Description | Transitions |
|-------|-------------|-------------|
| `IDLE` | Awaiting interaction, prompt visible on proximity | → TALKING (on interact) |
| `TALKING` | In dialogue, prompt hidden, waiting for dialogue_ended | → COOLDOWN (on dialogue_ended) |
| `COOLDOWN` | Brief cooldown, no prompt | → IDLE (timer expired) or EXHAUSTED |
| `EXHAUSTED` | All dialogue branches visited, no further interaction | — Terminal state (until scene reload) |
| `SPECIAL` | Reserved for future conditional states | → IDLE (on condition change) |

#### Personality Layer Condition Mapping

| Layer | Condition | Effect on Clerk |
|-------|-----------|-----------------|
| Tired Worker | Always (default, checked last) | "⌈Clerk⌋" — standard greeting |
| Cynical Veteran | `hope_despair < 0` OR `conviction < 5` | "⌈Clerk (distant)⌋" — cynical greeting |
| Systemic Exhaustion | `hope_despair ≤ -2` AND (office_choice_sigh OR office_choice_neutral) | "⌈Tired Voice⌋" — systemic greeting, references office |

### 5.2 Normal Path

1. **Scene Load:** `convenience_store.tscn` loads with `NPC.tscn` as child. NPCNode `_ready()` connects Area3D signals, sets initial state = IDLE, hides labels.
2. **Player Approaches:** Player walks within `proximity_distance` of the clerk → `body_entered` on trigger → NPCNode shows `speaker_name` label and `interaction_prompt_text` ("⌈Talk⌋").
3. **Player Clicks:** Input event on Area3D → NPCNode evaluates personality layers against current GameState:
   - `hope_despair = 3` (mid range) → Layer 1 (Tired Worker) matches (no condition).
   - NPC sets `active_layer` to `tired_worker`, updates name label to "⌈Clerk⌋".
4. **Dialogue Starts:** State = TALKING → `dialogue_runner.start("res://dialogues/store_clerk.json", "store_clerk")`.
5. **Dialogue Flow:** Standard dialogue engine flow. Tired Worker layer means standard greeting at entry node `clerk_greet`.
6. **Dialogue Ends:** `dialogue_ended` signal → NPC sets state = COOLDOWN → starts 2s timer → on timeout, state = IDLE.
7. **Labels:** During COOLDOWN, name label remains but prompt is hidden. After COOLDOWN, full idle state restores.

**AC1 (Shallow) — Clerk has 3 dialogue branches (greeting, purchase, farewell):**
- Greeting branch: Player enters → clerk greets based on active layer (tired/cynical/systemic)
- Purchase branch: Player can buy coffee or browse shelves → effects on hope/will/conviction
- Farewell branch: Player leaves counter or exits store → dialogue ends

### 5.3 Middle Layer (AC2)

**AC2 (Middle) — When hope > 5, clerk is more cheerful; when despair < -5, clerk becomes nihilistic:**

- `hope_despair > 5.0` (Buoyant/Hope states): Clerk enters Layer 1 (Tired Worker) but greeting text is warmer. "Hey. Late night, huh? Coffee's still on." The dialogue offers more positive choice branches (e.g., extra "You seem in a good mood" branch with bonus hope/conviction).
- `hope_despair < -5.0` (Low/Despair states approaching -5): Clerk enters Layer 3 (Systemic Exhaustion) or Layer 2 (Cynical Veteran). Greeting changes: "Oh. You again. Or... first time? They all blur." Dialogue choices skew toward nihilistic/defeatist, with fewer positive effects.
- Neutral (-2 to +2): Clerk alternates between Layer 1 and early Layer 2. Standard exhausted worker mode. "Welcome. Late night shopping?"

The personality layer system determines the entry node and tone. The clerk JSON contains multiple greeting variants keyed to the `active_layer`:

```
Layer 1 (Tired Worker):
  "clerk_greet" — "Welcome. Late night shopping?"
Layer 2 (Cynical Veteran):
  "clerk_greet_cynical" — "Welcome... I guess. Don't buy anything that expires tonight."
Layer 3 (Systemic Exhaustion):
  "clerk_greet_systemic" — "Another one from the towers. You people and your 24/7."
```

Each layer's greeting has its own choice tree. Neutral/hopeful states have more options; despair states have fewer, darker options.

### 5.4 Deep Layer (AC3)

**AC3 (Deep) — Clerk's lines contain subtle references to player's office choice, revealing a shared resignation:**

The clerk dialogue checks office exit flags (set in `office_door.json`):

- **office_exit_sigh** (player chose reluctant exit — "Sigh, one more thing to do"):
  > Clerk (Systemic layer): "I know that sigh. I make the same one when the night shift manager walks in."
  > Clerk (Tired layer): "Heard that before. The universal sound of 'not getting paid enough.'"

- **office_exit_neutral** (player chose matter-of-fact exit — "One more day down"):
  > Clerk (Cynical layer): "One more day. That's what I tell myself when the coffee machine breaks."
  > Clerk (Tired layer): "One more day, huh? Same here. Night shift's almost over."

- **office_exit_determined** (player chose determined exit — "Let's get this over with"):
  > Clerk (Systemic layer): "Still got some fight in you. Give it a few years... or a few hours. Same thing."
  > Clerk (Tired layer): "At least one of us has energy. Coffee's on me."

The office reference is always:
1. **Subtle** — Not explicit "I know you work in an office." Instead, references to "towers," "those night shifts," "the grind," "the universal sound."
2. **State-dependent** — Only appears if the clerk is in Cynical Veteran or Systemic Exhaustion layer (i.e., the player's own negative state reveals the shared resignation).
3. **Revealing** — Each reference contains a micro-revelation: this clerk has been doing this long enough to recognize "the sigh" of an office worker. The shared resignation is between two people trapped in different parts of the same machine.

Implementation: The office reference is a **separate dialogue node branch** gated by `flag` conditions for office exit flags AND `slider` conditions for the mood layer. The NPC framework's `active_layer` determines which office reference branch (if any) is offered.

### 5.5 Edge Cases

1. **Player has never visited the office (skip dialogue):** Technically impossible (office is the entry scene), but if `office_door.json` flags are absent, the office reference dialogue nodes are gated by `flag` condition with default value `false`. Clerk simply doesn't offer the AC3 reference — falls back to standard layer dialogue.

2. **Player's state changes mid-dialogue:** A choice during clerk dialogue modifies `hope_despair`. The active personality layer was evaluated at dialogue start. **Decision:** Layer is locked for the duration of the conversation. On next interaction (after dialogue_ended → COOLDOWN → IDLE), the layer is re-evaluated.

3. **All layers have no match (empty personality_layers):** NPCNode defaults to Layer 0 behavior — uses `speaker_name` as-is, no greeting override. The entry node is the dialogue file's default `entry_node_id`.

4. **Rapid re-triggering:** Player clicks the NPC repeatedly before dialogue ends. **Mitigation:** NPCNode ignores input events while state != IDLE. Only re-enables `input_event` processing when state transitions back to IDLE.

5. **NPC with no dialogue_file:** If `dialogue_file` is empty, the interaction prompt shows "⌈(Silent)⌋" and no dialogue starts. The NPC is decorative rather than interactive.

6. **Dialogue file load failure:** If `dialogue_runner.start()` returns false, NPCNode sets state = IDLE and shows prompt again (allows retry). A `push_error` is logged.

7. **Multiple NPCs in same scene:** Each NPC instance manages its own state independently. If the player interacts with NPC A while NPC B is in COOLDOWN, NPC B's state is unaffected. Two simultaneous TALKING NPCs is prevented by the dialogue engine (one conversation at a time).

8. **State change during COOLDOWN:** If `hope_despair` changes while the clerk is in COOLDOWN (e.g., from an environmental effect), the personality layer is NOT re-evaluated until the next state transition to IDLE. This prevents rapid label flickering.

### 5.6 Failure Paths

1. **DialogueRunner not available:** If NPCNode can't find the DialogueRunner at scene start, it logs a `push_error` and sets any interaction to no-op. The NPC remains in IDLE but clicking does nothing.

2. **Personality layer condition references invalid axis:** If a layer condition references `axis = "nonexistent"`, `DialogueConditionEvaluator.evaluate()` returns false (unknown type → false). The layer is skipped, and the next layer is evaluated.

3. **Infinite personality layer nesting:** If a layer condition references itself (circular), the evaluation is still finite — each layer is evaluated once in array order. No recursion risk.

4. **Exported dialogue_file path invalid:** The path is validated when `dialogue_runner.start()` is called. If the file doesn't exist, DialogueParser returns error. NPCNode catches this and doesn't change state — remains IDLE.

### 5.7 Acceptance Criteria Status

- [ ] **AC1 (Shallow):** Clerk has 3 dialogue branches (greeting, purchase, farewell).
  - Greeting branch triggered on dialogue start
  - Purchase branch: coffee/no coffee, shelf explore
  - Farewell branch: leave counter, exit store

- [ ] **AC2 (Middle):** When hope > 5, clerk is more cheerful; when despair < -5, clerk becomes nihilistic.
  - `hope_despair > 5.0` → Layer 1 (Tired Worker) with warmer greeting variants
  - `hope_despair < -5.0` → Layer 2 (Cynical Veteran) or Layer 3 (Systemic Exhaustion)
  - State evaluation via DialogueConditionEvaluator on existing slider DSL
  - Layered greeting visible in name label prefix update

- [ ] **AC3 (Deep):** Clerk's lines contain subtle references to player's office choice, revealing a shared resignation.
  - Office exit flags (`office_exit_sigh`, `office_exit_neutral`, `office_exit_determined`) gated via `choice_made` conditions
  - Office reference appears only in Cynical/Systemic layers
  - References are subtle (shared resignation, not explicit "you work in an office")

- [ ] **Framework Reusability:** NPC.tscn can be instanced in any scene with 3 exported properties (`dialogue_file`, `speaker_name`, `personality_layers`) and immediately functions.

- [ ] **State Machine:** NPCNode correctly cycles through IDLE → TALKING → COOLDOWN → IDLE (or EXHAUSTED) on each interaction cycle.

- [ ] **State Locking:** Input events are ignored while state != IDLE. No double-triggering.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #46 — Dialogue Engine Data Model | ✅ **Merged** (PR #77) | **Low** — Core dialogue parsing and condition evaluation |
| Issue #52 — Dialogue Engine Runtime + Visual | ✅ **Merged** (PR #83) | **Low** — DialogueRunner, DialogueDisplay3D, signals |
| Issue #47 — GameState System | ✅ **Merged** (PR #87?) | **Low** — StateSystem autoload, flags, choice history |
| Issue #50 — State-World Feedback | ✅ **Merged** | **Low** — Bipolar hope_despair axis, 5-state system |
| Issue #45 — Narrative Architecture | ✅ **Merged** (PR #96) | **Low** — SceneBase, scene sequence, SceneManager |
| Issue #55 — Office → Street → Store scene | ✅ **Merged** | **Low** — convenience_store.tscn exists with clerk trigger pattern |
| DialogueRunner global reference pattern | Existing | **Low** — `get_node_or_null("/root/...")` pattern used by SceneBase |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #57 — MVP Playtest | **High** — NPC interaction is core to playtest |
| Issue #56 — Story Content | **Medium** — NPC framework provides the authoring interface for story content |
| Other NPC implementations (Bartender, etc.) | **High** — Framework must exist before new NPCs can be efficiently added |
| Any NPC dialogue content authoring | **High** — Framework defines the dialogue-context interface |

### Preparation Needed

- [ ] Verify office_door.json flag names and ensure they're set reliably. The office exit flags are: `office_exit_sigh`, `office_exit_neutral`, `office_exit_determined`. These must be documented in `constants.gd` alongside other dialogue effect constants.
- [ ] Review existing store_clerk.json for node IDs and ensure no conflicts with new layer-specific nodes.
- [ ] Confirm DialogueRunner's global reference pattern (SceneBase resolves it as `$CanvasLayer/DialoguePanel` — NPCNode needs a compatible lookup).
- [ ] Verify that `DialogueRunner.start(dialogue_file, dialogue_id)` supports passing an entry node override (or if NPCNode needs to call `load_dialogue` then `enter_node` separately).

---

## 7. Spike / Experiment (Optional — depth/deep)

### Spike 1: Dialogue Entry Node Override

**Question to Answer:**
Can `DialogueRunner.start()` accept an optional `entry_node_id` parameter to allow the NPC framework to override the default greeting? Or does the NPC framework need to call `load_dialogue()` + `enter_node()` separately?

**Method:**
1. Read `DialogueRunner.start()` — currently calls `load_dialogue()` then `enter_node(dialogue_tree["entry_node_id"])`.
2. Two options:
   - (a) Add optional parameter: `func start(dialogue_file: String, dialogue_id: String = "", entry_override: String = "") -> bool`. If `entry_override` is non-empty, use it instead of `dialogue_tree.entry_node_id`.
   - (b) In NPCNode, call `dialogue_runner.load_dialogue(file)` then directly call `dialogue_runner.enter_node(override_node_id)`.

**Expected Result:**
Option (a) is cleaner — extends DialogueRunner minimally. Option (b) works but bypasses `start()`'s error handling and `dialogue_started` signal. **Decision:** Option (a), single parameter addition to DialogueRunner.

**Impact on Approach:**
If adopted, `DialogueRunner.start()` gains an optional 3rd parameter `entry_override`. The personality layer's `greeting_override` field passes this value. If empty, standard entry_node_id is used.

### Spike 2: Name Label Visibility on Proximity Detection

**Question to Answer:**
What is the optimal `proximity_distance` for NPC labels? The camera is ~2–5m from the NPC during typical interaction (per Issue #52 design). LoFiText3D must be readable at this distance.

**Method:**
1. Load `convenience_store.tscn` with NPC.tscn at the clerk position.
2. Place the camera at 2m, 3.5m, 5m from the NPC.
3. Test three proximity distances: 2.0, 3.0, 4.0.
4. Visual check: labels visible before player is on top of NPC, don't pop in too early.

**Expected Result:**
`proximity_distance = 3.0` provides a comfortable detection radius. Label appears when the player is ~2 steps from the counter. At 4.0, the label triggers from the store entrance (too early). At 2.0, the player is already at the counter before seeing the label (too late).

**Impact on Approach:**
Default proximity_distance set to 3.0. Per-NPC override via `@export var proximity_distance`.

### Spike 3: Three-Layer Dialogue Tree Size Estimation

**Question to Answer:**
How many additional nodes does the three-layer personality add to `store_clerk.json`? Does the expanded file exceed maintainable size?

**Method:**
Count existing nodes in store_clerk.json (14 nodes). Estimate new nodes per layer:
- Layer 1 additions: 2 variant greeting nodes + 2 additional choice paths = ~4 new nodes
- Layer 2 additions: 1 cynical greeting + 2 cynical-specific choices + 1 cynical farewell = ~4 new nodes
- Layer 3 additions: 1 systemic greeting + 1 office reference + 2 systemic choices = ~4 new nodes
- Office reference branches: 3 office exit variants × 2 response nodes = ~6 new nodes

**Expected Result:**
Total ~28–32 nodes (14 existing + 14–18 new). Well within the 50-node practical limit. Each node has 2–4 choices.

**Impact on Approach:**
Single file approach is confirmed feasible. If the file exceeds 400 lines, consider splitting into `store_clerk_base.json` (shared nodes) + `store_clerk_cynical.json` / `store_clerk_systemic.json` (layer-specific nodes), loaded via the NPC framework's layer selector. However, single file is preferred for simplicity.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

### Current State

The game has a fully functional dialogue engine (DialogueRunner, DialogueParser, DialogueConditionEvaluator, DialogueDisplay3D, HemingwayEnforcer) and scene infrastructure (SceneBase, SceneManager, 6 scenes with environmental text). NPCs are currently implemented as bespoke Area3D triggers inline in scene scripts.

The convenience store clerk exists in:
- `dialogues/store_clerk.json` (283 lines, 14 nodes) — basic branching with condition-gated choices
- `gdscripts/store.gd` (56 lines) — inline trigger + environmental text config
- `scenes/store/convenience_store.tscn` — with ClerkNPC node, Label3D, and Area3D trigger

### Files to Create

1. **`gdscripts/npc_node.gd`** — NPC framework core script (~200 lines):
   - `class_name NPCNode extends Node3D`
   - NPCState enum (IDLE, TALKING, COOLDOWN, EXHAUSTED, SPECIAL)
   - Exported properties: `dialogue_file`, `dialogue_id`, `speaker_name`, `mood_axis`, `proximity_distance`, `cooldown_seconds`, `personality_layers[]`, `label_offset`
   - Internal state: `current_state`, `active_layer`, `_player_nearby`
   - Methods:
     - `_ready()` — setup trigger area, connect signals, state = IDLE
     - `_evaluate_personality_layer() -> Dictionary` — evaluate personality_layers against GameState, return first match
     - `_on_body_entered(body)` / `_on_body_exited(body)` — proximity detection
     - `_on_interaction(event)` — handle click, evaluate layer, start dialogue
     - `_on_dialogue_ended()` — transition to COOLDOWN, start timer
     - `_on_cooldown_timeout()` — transition to IDLE
     - `set_state(new_state: NPCState)` — state transition with signal emission
     - `update_name_label()` — update label text based on active layer
     - `show_prompt()` / `hide_prompt()` — visibility management

2. **`scenes/components/NPC.tscn`** — NPC scene file:
   - Root: Node3D (NPCNode script)
   - Children:
     - `InteractionTrigger (Area3D)` — with CollisionShape3D (cylinder)
     - `VisualName (LoFiText3D)` — billboarded name label
     - `InteractionPrompt (LoFiText3D)` — billboarded prompt label
     - `CooldownTimer (Timer)` — single-shot timer

3. **`gdscripts/npc_personality.gd`** — Resource class for personality profiles (optional, can stay as inline Dict):
   - `class_name NPCPersonality extends Resource`
   - `@export var name: String`
   - `@export var condition: Dictionary`
   - `@export var name_prefix: String`
   - `@export var greeting_override: String`

### Files to Modify

1. **`dialogues/store_clerk.json`** — Expanded to 3-layer dialogue:
   - Add greeting variants: `clerk_greet_cynical`, `clerk_greet_systemic`
   - Add office reference nodes: `clerk_office_sigh`, `clerk_office_neutral`, `clerk_office_determined`
   - Add layer-specific choice branches for cynical and systemic states
   - Ensure all new nodes use the Condition DSL (slider conditions on hope_despair, flag conditions on office exit flags)

2. **`gdscripts/store.gd`** — Simplified:
   - Remove inline `ClerkTrigger` Area3D setup
   - Remove `_on_clerk_trigger_input()` — replaced by NPCNode
   - Keep `_configure_environmental_text()` (OPEN sign, Stranger foreshadowing)
   - Keep `_on_exit_trigger_input()` (store exit still exists)

3. **`scenes/store/convenience_store.tscn`** — Modified:
   - Remove inline `ClerkNPC` (Label3D), `ClerkTrigger` (Area3D + CollisionShape3D + Label3D)
   - Add `NPC.tscn` instance at the clerk position with exported properties

4. **`gdscripts/dialogue_runner.gd`** — Optional minor change:
   - Add optional `entry_override: String = ""` parameter to `start()` method
   - If non-empty, use as entry node instead of `dialogue_tree.entry_node_id`

5. **`gdscripts/constants.gd`** — Add:
   - Office exit flag constants (document existing flags from office_door.json)

### Key Risks

1. **DialogueRunner `start()` entity parameter** — Currently `start(file, dialogue_id)` always uses `entry_node_id` from the JSON. If we add an `entry_override` parameter, existing callers (SceneBase, main.gd test dialogue) must continue to work unchanged. Default empty string = existing behavior.

2. **NPCNode DialogueRunner reference resolution** — SceneBase resolves dialogue_runner as `$CanvasLayer/DialoguePanel`. NPCNode must find the same DialogueRunner. If the NPC is a child of a scene that also has a CanvasLayer → DialoguePanel, the path is `../../CanvasLayer/DialoguePanel`. Networked autoload lookup (`get_node("/root/...")`) is more reliable. **Decision:** NPCNode finds the active DialogueRunner by querying `get_tree().current_scene` for the DialoguePanel path, or via a dedicated signal bus.

3. **Layer dialog file size** — The expanded `store_clerk.json` may reach 400–500 lines. For readability, consider adding a helper script to validate the file's JSON structure during Godot editor load (Judd-like pattern in DialogueParser).

4. **Office exit flag consistency** — Office_door.json sets flags on exit. These flags MUST be set before the player reaches the convenience store. If office dialogue changes (future issue), the flag names must remain stable.

### Design Decisions for Plan Agent

1. NPCNode resolves DialogueRunner at runtime via `get_node_or_null("/root/GameManager")`'s scene reference or by scanning `get_tree().current_scene` for a DialoguePanel node — NOT by hardcoded path.
2. `personality_layers` is an `Array[Dictionary]` (not a custom Resource type) for simplicity — each dict follows the existing Condition DSL format.
3. Layer condition evaluation reuses `DialogueConditionEvaluator.evaluate()` — no new condition evaluation code.
4. Office reference is implemented as gated dialogue nodes (choice_made conditions), not as NPCNode-level logic.
5. Cooldown timer defaults to 2.0 seconds — configurable per NPC.
6. The name label uses `active_layer.name_prefix` if available, otherwise `speaker_name`. If the layer name_prefix is empty, the base `speaker_name` is used.
7. The interaction prompt is always the static `interaction_prompt_text` string — not layer-dependent.
8. NPCNode stores `_player_nearby: bool` but does NOT track multiple players. Single-player assumption.
9. Debug overlay integration: NPCNode emits `npc_state_changed(state)` for the F12 debug overlay to display.
10. The EXHAUSTED terminal state is set ONLY if the NPC's dialogue file has no remaining unvisited branches. This requires DialogueRunner to expose `has_unvisited_branches(dialogue_id) → bool`. If this method doesn't exist, NPCNode always cycles back to IDLE (simpler but less precise).

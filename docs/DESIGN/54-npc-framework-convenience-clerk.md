# Design: #54 — NPC Framework + Convenience Clerk

> Parent Issue: #54
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Create a reusable `NPCNode` component (`NPC.tscn` scene + `npc_node.gd` script) that encapsulates interaction trigger, name/prompt labels, state machine, and personality layer evaluation. The convenience store clerk is the first NPC to use the framework, converting from inline bespoke logic to a drop-in component with a three-layer personality (Tired Worker → Cynical Veteran → Systemic Exhaustion).

### Data Flow

```
Scene Load
    │
    ├──► NPC.tscn instance (child of scene root)
    │       ├──► _ready(): reads @export properties (dialogue_file, speaker_name,
    │       │             mood_axis, personality_layers). Creates Area3D trigger
    │       │             with CylinderShape3D. Sets initial NPCState = IDLE.
    │       │             Connects body_entered/body_exited/exited_tree signals.
    │       │             Hides VisualName + InteractionPrompt labels.
    │       │
    │       ├──► On body_entered (player enters proximity):
    │       │       └──► _player_nearby = true
    │       │           └──► show VisualName + InteractionPrompt
    │       │
    │       ├──► On body_exited (player leaves proximity):
    │       │       └──► _player_nearby = false
    │       │           └──► hide VisualName + InteractionPrompt
    │       │
    │       ├──► On input_event (click on Area3D):
    │       │       └──► If state == IDLE:
    │       │               ├──► _evaluate_personality_layer()
    │       │               │       └──► Iterate personality_layers[Array[Dict]]
    │       │               │           │   For each layer, evaluate condition
    │       │               │           │   using DialogueConditionEvaluator
    │       │               │           │   with current GameState snapshot.
    │       │               │           └──► Return first matching layer dict
    │       │               │
    │       │               ├──► set_state(TALKING)
    │       │               │       └──► Emit npc_state_changed(NPCState.TALKING)
    │       │               │       └──► Hide InteractionPrompt
    │       │               │
    │       │               ├──► update_name_label()
    │       │               │       └──► Use active_layer.name_prefix if set,
    │       │               │           │   else speaker_name. Apply to Label3D.
    │       │               │           └──► If greeting_override exists, store for
    │       │               │               dialogue entry
    │       │               │
    │       │               └──► dialogue_runner.start(dialogue_file, dialogue_id,
    │       │                         greeting_override)
    │       │
    │       ├──► On dialogue_ended signal (from DialogueRunner):
    │       │       ├──► set_state(COOLDOWN)
    │       │       │       └──► Emit npc_state_changed(NPCState.COOLDOWN)
    │       │       ├──► Start CooldownTimer (cooldown_seconds)
    │       │       └──► Show InteractionPrompt if _player_nearby still true
    │       │
    │       ├──► On CooldownTimer timeout:
    │       │       ├──► If dialogue has no unvisited branches:
    │       │       │       └──► set_state(EXHAUSTED)  [terminal]
    │       │       │           └──► Hide InteractionPrompt
    │       │       │           └──► Emit npc_state_changed(NPCState.EXHAUSTED)
    │       │       └──► Else:
    │       │               └──► set_state(IDLE)
    │       │                   └──► Show InteractionPrompt if _player_nearby
    │       │                   └──► Emit npc_state_changed(NPCState.IDLE)
    │       │
    │       └──► On tree_exited (scene unload):
    │               └──► Disconnect all signals, free timer

Clerk-Specific Data Flow (3-Layer Personality):
    _evaluate_personality_layer()
        │
        ├──► Layer 3 (Systemic Exhaustion): check hope_despair ≤ -2
        │       └──► Match → active_layer = systemic_exhaustion
    │           └──► name_prefix = "⌈Tired Voice⌋"
    │           └──► greeting_override = "clerk_greet_systemic"
        │
        ├──► Layer 2 (Cynical Veteran): check hope_despair < 0 OR conviction < 5
        │       └──► Match → active_layer = cynical_veteran
    │           └──► name_prefix = "⌈Clerk (distant)⌋"
    │           └──► greeting_override = "clerk_greet_cynical"
        │
        └──► Layer 1 (Tired Worker): default (no condition, checked last)
                └──► active_layer = tired_worker
                    └──► name_prefix = "⌈Clerk⌋"
                    └──► greeting_override = "" (use default entry_node_id)

Dialogue Flow (Clerk, post-greeting):
    Entry → greeting node    ─┬─► clerk_greet (Tired Worker, default)
                              ├─► clerk_greet_cynical (Cynical Veteran)
                              └─► clerk_greet_systemic (Systemic Exhaustion)
                                    │
                                    ├──► Branch: coffee purchase
                                    │       └──► effects: hope +0.5, will +1.0
                                    ├──► Branch: comfort/chat
                                    │       └──► effects: hope +0.5
                                    ├──► Branch: AC3 office reference
                                    │       └──► condition: flag(office_exit_sigh/neutral/determined)
                                    └──► Branch: farewell
                                            └──► dialogue_ended
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| NPC Component Pattern | Standalone `NPC.tscn` scene + `NPCNode` script | Godot 4.x composition pattern — NPC is a child scene with self-contained logic. No manager autoload needed for ~6 NPCs. |
| State Machine Location | Inside `NPCNode` (per-instance, not global) | Each NPC manages its own lifecycle independently. On scene unload, state is freed naturally. |
| Personality Layer Format | `Array[Dictionary]` (not custom Resource) | Reuses existing `DialogueConditionEvaluator` condition DSL. Simpler than a custom Resource type. No new condition evaluation code. |
| DialogueRunner Reference Resolution | Runtime lookup via `get_tree().current_scene` → DialoguePanel | Follows same pattern as SceneBase (`$CanvasLayer/DialoguePanel`). Avoids hardcoded `/root/` paths that break on scene structure changes. |
| Dialogue Entry Override | Optional 3rd parameter in `DialogueRunner.start()` | Minimal change — `start(file, id, entry_override="")`. Empty string preserves existing behavior. |
| Layer Locking | Locked for conversation duration | Personality layer is evaluated once at dialogue start, not re-evaluated mid-conversation. Prevents label flickering. |
| Office Reference Implementation | Gated dialogue nodes (not NPCNode logic) | Office exit flag conditions are standard dialogue DSL (`flag` + `slider` conditions) inside the JSON. NPCNode doesn't need to know about offices. |
| EXHAUSTED State Detection | DialogueRunner exposes `has_unvisited_branches(dialogue_id) → bool` | If method doesn't exist, fallback: always cycle back to IDLE. |
| Name Label Update | Re-evaluates on each interaction start | `active_layer.name_prefix` is applied to `VisualName` label text when dialogue starts. Not reactive to state changes during conversation. |

---

## 2. New Files

### `gdscripts/npc_node.gd` — Core NPC Framework Script

- **Role:** Root script for `NPC.tscn`. Handles state machine, proximity detection, interaction, personality layer evaluation, label management.
- **Class:** `class_name NPCNode extends Node3D`

#### Public API

```gdscript
# === Exported Properties ===
@export var dialogue_file: String = ""
@export var dialogue_id: String = ""
@export var speaker_name: String = "NPC"
@export var mood_axis: String = "hope_despair"       # slider used by personality layers
@export var proximity_distance: float = 3.0           # trigger cylinder radius
@export var cooldown_seconds: float = 2.0             # COOLDOWN → IDLE timer
@export var name_label_visible: bool = true            # master toggle for name label
@export var interaction_prompt_text: String = "⌈Talk⌋"
@export var personality_layers: Array[Dictionary] = [] # ordered layer definitions
@export var label_offset: Vector3 = Vector3(0, 1.5, 0)

# === Signals ===
signal npc_interacted(npc_id: String)                  # emitted when player clicks NPC
signal dialogue_completed(npc_id: String)              # emitted when dialogue_ends
signal npc_state_changed(state: int)                   # state transitions

# === Public Methods ===
func set_state(new_state: int) -> void
func evaluate_personality_layer() -> Dictionary
func get_active_layer_name() -> String
func is_interactable() -> bool                         # true when state == IDLE
```

#### Internal State Variables

```gdscript
var current_state: int = IDLE                     # NPCState enum value
var active_layer: Dictionary = {}                 # current matching layer dict
var _trigger_area: Area3D                         # interaction Area3D
var _name_label: Label3D                          # VisualName (LoFiText3D)
var _prompt_label: Label3D                        # InteractionPrompt (LoFiText3D)
var _cooldown_timer: Timer                        # transition timer
var _player_nearby: bool = false                  # proximity flag
var _dialogue_runner: Node                        # resolved reference
var _greeting_override: String = ""               # entry node override from layer
```

#### Signal Declarations

| Signal | Arguments | Emitted When |
|--------|-----------|-------------|
| `npc_interacted` | `(npc_id: String)` | Player clicks NPC and state is IDLE |
| `dialogue_completed` | `(npc_id: String)` | `dialogue_ended` signal received |
| `npc_state_changed` | `(state: int)` | Any state transition via `set_state()` |

#### NPCState Enum

```gdscript
enum NPCState {
    IDLE       = 0,  # Awaiting interaction
    TALKING    = 1,  # In dialogue
    COOLDOWN   = 2,  # Post-dialogue brief pause
    EXHAUSTED  = 3,  # All branches visited (terminal per scene load)
    SPECIAL    = 4   # Reserved for future conditional states
}
```

---

### `scenes/components/NPC.tscn` — NPC Scene File

- **Role:** Reusable scene component with NPCNode script attached.
- **Scene Tree Structure:**
  ```
  NPC (NPCNode — root, Node3D)
  │
  ├── InteractionTrigger (Area3D)
  │   └── CollisionShape3D (CylinderShape3D, radius = proximity_distance, height = 2.0)
  │
  ├── VisualName (LoFiText3D)
  │   — Billboard-enabled Label3D
  │   — Font: res://assets/fonts/pixel.tres
  │   — Pixel factor: 0.5
  │   — Modulate: #d4a574 (amber emissive, Hopper palette)
  │   — Offset: label_offset.y units above root
  │   — Visible: false (shows on proximity)
  │
  ├── InteractionPrompt (LoFiText3D)
  │   — Billboard-enabled Label3D
  │   — Text: "⌈Talk⌋" (configurable via interaction_prompt_text)
  │   — Font: same as VisualName
  │   — Modulate: #8a6e52 (muted amber)
  │   — Offset: label_offset.y - 0.3 below VisualName
  │   — Visible: false (shows on proximity AND state == IDLE)
  │
  └── CooldownTimer (Timer)
      — One-shot, wait_time = cooldown_seconds
      — Autostart: false
  ```

#### Exported Property Mapping

| Export Field | Connects To | At |
|-------------|-------------|-----|
| `dialogue_file` | NPCNode.dialogue_file | Scene inspector |
| `speaker_name` | NPCNode.speaker_name | Scene inspector |
| `mood_axis` | NPCNode.mood_axis | Scene inspector |
| `proximity_distance` | CollisionShape3D.shape.radius (at ready) | `_ready()` override |
| `personality_layers` | NPCNode.personality_layers | Scene inspector |

---

### `gdscripts/npc_state.gd` — NPC State Constants (Optional Reference File)

- **Role:** Shared enum definition for `NPCState` — imported by NPCNode and any scene that needs to check NPC states.
- **Alternative:** Enum can live inside `npc_node.gd` as a regular Godot enum (project preference: inline enum minimizes imports).

```gdscript
extends RefCounted

enum NPCState {
    IDLE = 0,
    TALKING = 1,
    COOLDOWN = 2,
    EXHAUSTED = 3,
    SPECIAL = 4
}
```

---

### `gdscripts/npc_personality.gd` — Personality Profile Resource (Optional)

- **Role:** Optional `Resource` subclass for defining personality profiles. Used when a full Resource is preferred over inline `Array[Dictionary]`. Not required for initial implementation — the inline dict approach from the PRD is simpler and sufficient for the clerk's three layers.
- **If implemented:**

```gdscript
extends Resource
class_name NPCPersonality

@export var layer_name: String = ""
@export var condition: Dictionary = {}     # Uses same Condition DSL
@export var name_prefix: String = ""       # e.g. "⌈Clerk⌋"
@export var greeting_override: String = "" # entry node override
```

---

## 3. Modified Files

### Dialogue Runner (`gdscripts/dialogue_runner.gd`)

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Add `entry_override: String = ""` parameter to `start()` | If non-empty, use as entry node instead of `dialogue_tree.entry_node_id` | +2 |
| Add `has_unvisited_branches(dialogue_id: String) → bool` method | Check if dialogue JSON has any nodes with `next_node == null` that haven't been visited | +15 |
| Existing callers (SceneBase, main.gd) unchanged by default parameter | No regression | 0 |

### Store Scene Script (`gdscripts/store.gd`)

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Remove `@onready var clerk_trigger: Area3D` | Replaced by NPC.tscn's internal trigger | -1 |
| Remove `_on_clerk_trigger_input()` | Replaced by NPCNode's `_on_interaction()` | -8 |
| Keep `_configure_environmental_text()` | OPEN sign + Stranger foreshadowing | 0 |
| Keep `_on_exit_trigger_input()` | Store exit still exists | 0 |
| Keep `_restore_dialogue_state()` | Still needed for dialogue state restoration | 0 |
| Keep `_configure_ambient_audio()` | Still needed | 0 |

### Store Scene TSCN (`scenes/store/convenience_store.tscn`)

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Remove `ClerkNPC` Label3D node | Inline name label no longer needed | -5 |
| Remove `ClerkTrigger` Area3D + CollisionShape3D | Inline trigger no longer needed | -10 |
| Add `NPC.tscn` instance as child of root | At clerk counter position | +3 |
| Set exported properties on NPC instance | `dialogue_file`, `speaker_name`, `personality_layers`, `mood_axis` | +6 |

### Constants (`gdscripts/constants.gd`)

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Add NPC dialogue file constants | `DIALOGUE_STORE_CLERK_EXPANDED` for the 3-layer version | +2 |
| Add office exit flag constants | Document `office_exit_sigh`, `office_exit_neutral`, `office_exit_determined` | +4 |
| Add NPC framework constants | Default proximity distance, cooldown seconds | +3 |

### Dialogue JSON (`dialogues/store_clerk.json`)

| Change | Nature | Est. Lines |
|--------|--------|-----------|
| Expand from ~14 nodes to ~30 nodes | Add greeting variants (cynical, systemic) | +200 |
| Add `clerk_greet_cynical` node | Entry for Layer 2 | +15 |
| Add `clerk_greet_systemic` node | Entry for Layer 3 | +15 |
| Add office reference nodes (6 nodes) | `clerk_office_sigh`, `clerk_office_neutral`, `clerk_office_determined` with responses | +60 |
| Add layer-specific choice branches | Cynical and systemic variants of coffee, comfort, farewell | +80 |
| Gate office reference nodes with conditions | `slider` + `flag` conditions | +10 |

---

## 4. API Contracts

### Signal Connections

```gdscript
# === NPCNode Internal Wiring (in _ready()) ===
InteractionTrigger.body_entered.connect(_on_body_entered)
InteractionTrigger.body_exited.connect(_on_body_exited)
InteractionTrigger.input_event.connect(_on_interaction)
CooldownTimer.timeout.connect(_on_cooldown_timeout)

# === NPCNode → DialogueRunner (resolved at runtime) ===
# NPCNode connects to dialogue_runner's dialogue_ended signal
# Resolution strategy:
var dr := _resolve_dialogue_runner()
if dr:
    dr.dialogue_ended.connect(_on_dialogue_ended)

func _resolve_dialogue_runner() -> Node:
    # Strategy: walk up from this node to the scene root,
    # look for CanvasLayer → DialoguePanel path
    var scene_root := get_tree().current_scene
    if scene_root and scene_root.has_node("CanvasLayer/DialoguePanel"):
        return scene_root.get_node("CanvasLayer/DialoguePanel")
    # Fallback: /root/GameManager or signal bus
    return get_node_or_null("/root/GameManager")
```

### Method Call Chains

```
NPCNode._on_interaction(event)
    ├──► NPCNode._evaluate_personality_layer()
    │       └──► DialogueConditionEvaluator.evaluate(condition, state)
    │               └──► NPCNode._build_state_snapshot()
    │                       └──► GameManager.get_slider(), get_flags()
    ├──► NPCNode.set_state(NPCState.TALKING)
    │       └──► npc_state_changed.emit(NPCState.TALKING)
    ├──► NPCNode.update_name_label()
    └──► dialogue_runner.start(dialogue_file, dialogue_id, greeting_override)
            ├──► dialogue_started.emit(dialogue_id)
            ├──► enter_node(greeting_override or dialogue_tree.entry_node_id)
            │       └──► DialogueConditionEvaluator.evaluate() — per choice
            └──► NPCNode._on_dialogue_ended() [via signal]
                    ├──► set_state(COOLDOWN)
                    └──► CooldownTimer.start()

NPCNode._on_cooldown_timeout()
    ├──► check: dialogue_runner.has_unvisited_branches(dialogue_id)
    ├──► if false: set_state(EXHAUSTED)
    └──► if true: set_state(IDLE)
```

### DialogueRunner.start() Extension

The existing `start()` method (line 143-148 in `dialogue_runner.gd`) is extended with an optional third parameter:

```gdscript
func start(dialogue_file_path: String, dialogue_id: String = "",
           entry_override: String = "") -> bool:
    if not load_dialogue(dialogue_file_path, dialogue_id):
        return false
    dialogue_started.emit(current_dialogue_id)
    var entry: String = entry_override if not entry_override.is_empty() \
                       else dialogue_tree.get("entry_node_id", "")
    enter_node(entry)
    return true
```

### NPCNode DialogueRunner Resolution Priority

1. **Primary:** `get_tree().current_scene.get_node("CanvasLayer/DialoguePanel")`
   - Matches SceneBase's existing `@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel`
   - Works when NPC is a child of a scene that has DialoguePanel
2. **Fallback:** Walk up ancestor chain looking for `$"../../CanvasLayer/DialoguePanel"`
   - Handles nested NPC deeper in scene tree
3. **Last resort:** `get_node_or_null("/root/GameManager")` and scan for dialogue_runner
   - Catches edge cases where scene structure differs

### Personality Layer Condition Format

Each entry in `personality_layers` follows this schema (uses existing Condition DSL):

```gdscript
{
    "name": "tired_worker",          # Layer identifier
    "condition": {"type": "always"}, # Condition DSL dict; "always" = always match (checked last)
    "name_prefix": "⌈Clerk⌋",       # Override for VisualName label
    "greeting_override": ""          # Entry node override; empty = use default entry_node_id
}
```

Supported condition types (100% compatible with `DialogueConditionEvaluator`):
- `{"type": "always"}` — always matches (internal convention, not part of evaluator)
- `{"type": "slider", "axis": "hope_despair", "op": "lte", "value": -2}`
- `{"type": "and", "conditions": [Cond, Cond, ...]}`
- `{"type": "or", "conditions": [Cond, Cond, ...]}`
- `{"type": "not", "condition": Cond}`

---

## 5. Test Plan

### Test File Overview

| File | Type | Target |
|------|------|--------|
| `tests/unit/test_npc_node.gd` | Unit | NPCNode state machine, layer evaluation, proximity logic (via mocked dependencies) |
| `tests/unit/test_npc_personality.gd` | Unit | Personality layer condition evaluation, layer ordering, edge cases |
| `tests/unit/test_dialogue_runner_extension.gd` | Unit | `start()` entry_override parameter, `has_unvisited_branches()` |
| `tests/integration/test_npc_in_scene.gd` | Integration | NPC.tscn instanced in a test scene, full interaction cycle |

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| NPCState machine | ✅ | ≥4 | ✅ |
| Personality layer eval | ✅ | ≥3 | ✅ |
| Proximity detection | ✅ | ≥2 | ✅ |
| Dialogue entry override | ✅ | ≥2 | ✅ |
| Clerk 3-layer dialogue | ✅ | ≥3 | ✅ |
| Office reference gating | ✅ | ≥2 | ✅ |
| DialogueRunner extension | ✅ | ≥2 | ✅ |

### Test Cases

#### NPCState Machine Tests (TC1–TC8)

**TC1: IDLE → TALKING transition (normal path)**
- Type: Unit
- Setup: Instance NPCNode with mock DialogueRunner. Set state = IDLE.
- Steps: Call `_on_interaction()` with a simulated left-click InputEvent.
- Assert: `current_state == NPCState.TALKING`, `npc_state_changed` emitted with TALKING, `dialogue_runner.start()` called with correct dialogue_file.

**TC2: TALKING → COOLDOWN transition (normal path)**
- Type: Unit
- Setup: State = TALKING. Mock `dialogue_runner.dialogue_ended` signal.
- Steps: Emit `dialogue_ended` signal.
- Assert: `current_state == NPCState.COOLDOWN`, CooldownTimer started, `npc_state_changed` emitted with COOLDOWN.

**TC3: COOLDOWN → IDLE transition (normal path)**
- Type: Unit
- Setup: State = COOLDOWN. Mock `has_unvisited_branches` returns true.
- Steps: Emit `CooldownTimer.timeout`.
- Assert: `current_state == NPCState.IDLE`, `npc_state_changed` emitted with IDLE, prompt visible.

**TC4: COOLDOWN → EXHAUSTED (edge — all branches visited)**
- Type: Unit / Edge
- Setup: State = COOLDOWN. Mock `has_unvisited_branches` returns false.
- Steps: Emit `CooldownTimer.timeout`.
- Assert: `current_state == NPCState.EXHAUSTED`, prompt hidden, `npc_state_changed` emitted with EXHAUSTED.

**TC5: Input ignored while TALKING (edge — rapid click prevention)**
- Type: Unit / Edge
- Setup: State = TALKING.
- Steps: Call `_on_interaction()` with click event.
- Assert: `dialogue_runner.start()` NOT called. State unchanged.

**TC6: Input ignored while COOLDOWN**
- Type: Unit / Edge
- Setup: State = COOLDOWN.
- Steps: Call `_on_interaction()` with click event.
- Assert: No state change. Dialogue not started.

**TC7: State locked for dialogue duration (failure path — mid-dialogue state change)**
- Type: Unit / Failure
- Setup: State = TALKING. Player's hope_despair changes mid-dialogue (mocked).
- Steps: Evaluate personality layer mid-conversation.
- Assert: Active layer unchanged from dialogue start. Layer is NOT re-evaluated.

**TC8: DialogueRunner not available (failure path)**
- Type: Unit / Failure
- Setup: NPCNode with `_dialogue_runner = null`.
- Steps: Call `_on_interaction()`.
- Assert: `push_error` logged. State remains IDLE. No crash.

#### Personality Layer Evaluation Tests (TC9–TC14)

**TC9: Default layer match (no layers defined)**
- Type: Unit
- Setup: `personality_layers = []`. State = IDLE.
- Steps: Call `evaluate_personality_layer()`.
- Assert: Returns empty dictionary. `active_layer` is empty. Name label uses base `speaker_name`.

**TC10: Single layer match**
- Type: Unit
- Setup: `personality_layers = [{"name": "tired", "condition": {"type": "always"}, "name_prefix": "⌈Clerk⌋"}]`.
- Steps: Call `evaluate_personality_layer()`.
- Assert: Returns first layer. Name label updates to "⌈Clerk⌋". `greeting_override` is empty.

**TC11: Ordered evaluation — first match wins**
- Type: Unit
- Setup: Layer 0 (Tired) has `{"type": "always"}`. Layer 1 (Cynical) has `{"type": "slider", "axis": "hope_despair", "op": "lte", "value": 0}`.
- Steps: Set state `hope_despair = -5`. Evaluate.
- Assert: Layer 1 (Cynical) matches and is returned (always-match Layer 0 is checked but always-match should be evaluated last — test validates ordering).

**TC12: Layer with invalid axis reference (failure path)**
- Type: Unit / Failure
- Setup: Layer condition references `"axis": "nonexistent"`.
- Steps: Evaluate.
- Assert: `DialogueConditionEvaluator.evaluate()` returns false. Layer skipped. Next layer evaluated.

**TC13: All layers fail to match**
- Type: Unit / Edge
- Setup: Two layers with mutually exclusive conditions, neither matches current state.
- Steps: Evaluate.
- Assert: Returns empty dict. `active_layer` is empty. Falls back to base `speaker_name` and default entry node.

**TC14: Empty personality_layers with all exported defaults**
- Type: Unit / Edge
- Setup: NPCNode with default exports, `personality_layers = []`.
- Steps: Call `is_interactable()` then simulate interaction.
- Assert: `is_interactable() == true` when IDLE. `dialogue_runner.start()` called with bare dialogue_file, no entry override. Name label shows `speaker_name`.

#### Proximity Detection Tests (TC15–TC17)

**TC15: Body entered shows labels (normal path)**
- Type: Unit
- Setup: Player body enters trigger area. `_player_nearby = false`.
- Steps: Call `_on_body_entered(player_body)`.
- Assert: `_player_nearby == true`. VisualName visible. InteractionPrompt visible (if state == IDLE).

**TC16: Body exited hides labels (normal path)**
- Type: Unit
- Setup: Player body exits trigger area. `_player_nearby = true`.
- Steps: Call `_on_body_exited(player_body)`.
- Assert: `_player_nearby == false`. VisualName hidden. InteractionPrompt hidden.

**TC17: Prompt hidden during TALKING even when nearby (edge)**
- Type: Unit / Edge
- Setup: `_player_nearby = true`, state = TALKING.
- Steps: Call `update_prompt_visibility()`.
- Assert: InteractionPrompt hidden (because state != IDLE).

#### DialogueRunner Extension Tests (TC18–TC21)

**TC18: entry_override with valid override**
- Type: Unit
- Setup: Load a test dialogue JSON with `entry_node_id = "greet"` and a second entry `"greet_alt"`.
- Steps: Call `start("test.json", "test_id", "greet_alt")`.
- Assert: `enter_node("greet_alt")` called instead of `enter_node("greet")`. `dialogue_started` emitted.

**TC19: entry_override empty uses default entry_node_id**
- Type: Unit
- Setup: Same test JSON.
- Steps: Call `start("test.json", "test_id", "")`.
- Assert: `enter_node(dialogue_tree.entry_node_id)` called. Existing behavior preserved.

**TC20: has_unvisited_branches returns true when branches remain**
- Type: Unit
- Setup: Load dialogue with 3 terminal nodes (no next_node). Visit 1.
- Steps: Call `has_unvisited_branches("test_id")`.
- Assert: Returns true (2 unvisited branches remain).

**TC21: has_unvisited_branches returns false when all branches visited**
- Type: Unit
- Setup: Load dialogue with 1 terminal node. Visit it.
- Steps: Call `has_unvisited_branches("test_id")`.
- Assert: Returns false (0 unvisited branches).

#### Clerk 3-Layer Dialogue Tests (TC22–TC25)

**TC22: Tired Worker layer greeting (normal — mid state)**
- Type: Integration
- Setup: NPCNode with clerk personality layers. GameState: `hope_despair = 0, conviction = 5`.
- Steps: Evaluate personality layer. Start dialogue.
- Assert: `active_layer.name == "tired_worker"`. Greeting override empty. Dialogue starts at `clerk_greet`.

**TC23: Cynical Veteran layer greeting (edge — low conviction)**
- Type: Integration / Edge
- Setup: GameState: `hope_despair = 2, conviction = 3`. (hope_despair >= 0 but conviction < 5).
- Steps: Evaluate.
- Assert: `active_layer.name == "cynical_veteran"`. Name label shows "⌈Clerk (distant)⌋". Greeting override = "clerk_greet_cynical".

**TC24: Systemic Exhaustion layer greeting with office sigh flag (deep path)**
- Type: Integration
- Setup: GameState: `hope_despair = -3, office_exit_sigh = true`. (hope_despair ≤ -2).
- Steps: Evaluate layer. Start dialogue with greeting_override. Navigate to coffee branch then office reference.
- Assert: `active_layer.name == "systemic_exhaustion"`. Name label shows "⌈Tired Voice⌋". Dialogue greeting shows systemic text. Office reference node appears with "I know that sigh..." text.

**TC25: Office reference hidden when flags absent (failure path — no office visit)**
- Type: Integration / Failure
- Setup: GameState: `hope_despair = -3`. No office exit flags set (all false).
- Steps: Evaluate layer. Start dialogue. Navigate through available choices.
- Assert: Systemic greeting shown. Office reference choice branch is NOT present (gated by flag conditions). Player sees standard systemic farewell instead.

---

## 6. Files Changed

### Master Summary

| File | Type | Change | Est. Lines |
|------|------|--------|-----------|
| `gdscripts/npc_node.gd` | **New** | NPC framework core script: class_name, enum, signals, state machine, proximity detection, personality layer evaluation | +250 |
| `scenes/components/NPC.tscn` | **New** | NPC scene file with Area3D, Label3Ds, Timer | +30 |
| `gdscripts/npc_state.gd` | **New** | NPCState enum reference (optional, inline if preferred) | +15 |
| `gdscripts/npc_personality.gd` | **New** | NPCPersonality Resource class (optional) | +25 |
| `gdscripts/dialogue_runner.gd` | **Modified** | Add `entry_override` param to `start()`, add `has_unvisited_branches()` | +17 |
| `gdscripts/store.gd` | **Modified** | Remove inline clerk trigger, simplify to NPC.tscn usage | -9 |
| `scenes/store/convenience_store.tscn` | **Modified** | Replace inline clerk nodes with NPC.tscn instance | +9/-15 |
| `gdscripts/constants.gd` | **Modified** | Add NPC constants, office flag constants | +9 |
| `dialogues/store_clerk.json` | **Modified** | Expand to 3-layer personality dialogue with office references | +200 |
| `tests/unit/test_npc_node.gd` | **New** | State machine, proximity, interaction unit tests | +150 |
| `tests/unit/test_npc_personality.gd` | **New** | Layer evaluation unit tests | +100 |
| `tests/unit/test_dialogue_runner_extension.gd` | **New** | entry_override and has_unvisited_branches tests | +80 |
| `tests/integration/test_npc_in_scene.gd` | **New** | Full interaction cycle integration test | +120 |

### Legend

| Column | Meaning |
|--------|---------|
| **Type** | New file or modification to existing file |
| **Change** | Concise description of what changes |
| **Est. Lines** | Estimated line delta (+ added, - removed, ± net change) |

---

## 7. Verification Checklist

- [ ] **AC1 — Clerk has 3 dialogue branches (greeting, purchase, farewell):**
  - [ ] Greeting branch triggered on dialogue start (state-dependent layer)
  - [ ] Purchase branch: coffee (+hope/will), no coffee (no effect)
  - [ ] Farewell branch: ends conversation gracefully
  - [ ] All three branches present regardless of active layer

- [ ] **AC2 — State-dependent personality layers:**
  - [ ] `hope_despair > 5.0` → Layer 1 (Tired Worker) with warmer greeting
  - [ ] `hope_despair < -5.0` → Layer 2 (Cynical Veteran) or Layer 3 (Systemic Exhaustion)
  - [ ] Neutral (-2 to +2) → Tired Worker default
  - [ ] Layer evaluation uses existing `DialogueConditionEvaluator.evaluate()`
  - [ ] Name label updates with layer name prefix

- [ ] **AC3 — Office reference in clerk dialogue:**
  - [ ] `office_exit_sigh` → clerk references "that sigh" (Systemic layer) or "universal sound" (Tired layer)
  - [ ] `office_exit_neutral` → clerk references "one more day"
  - [ ] `office_exit_determined` → clerk references "still got fight in you"
  - [ ] Office reference appears ONLY in Cynical/Systemic layers
  - [ ] References are subtle (shared resignation, not explicit)
  - [ ] No office reference when flags are absent

- [ ] **NPC Framework Reusability:**
  - [ ] NPC.tscn can be instanced in any scene with 3 exported properties
  - [ ] Minimal NPC (no personality_layers) works with bare exports
  - [ ] NPC with full personality layers works end-to-end
  - [ ] State machine: IDLE → TALKING → COOLDOWN → IDLE/EXHAUSTED

- [ ] **State Machine & Robustness:**
  - [ ] Input events ignored while state != IDLE (no double-triggering)
  - [ ] DialogueRunner not available → push_error, no crash, remains IDLE
  - [ ] Invalid dialogue file → push_error, remains IDLE
  - [ ] Invalid axis in layer condition → layer skipped gracefully
  - [ ] Empty personality_layers → uses speaker_name, default entry node
  - [ ] Multiple NPCs in same scene operate independently

- [ ] **DialogueRunner Compatibility:**
  - [ ] `start()` with empty `entry_override` behaves exactly as before
  - [ ] All existing callers (SceneBase, main.gd) continue to work
  - [ ] `has_unvisited_branches()` correctly reports remaining branches
  - [ ] Fallback when NPCNode can't find DialogueRunner degrades gracefully

- [ ] **No regression on existing features:**
  - [ ] All pre-existing tests still pass
  - [ ] Store scene exit trigger still works
  - [ ] Store environmental text (OPEN sign) still configures correctly
  - [ ] Dialogue state restoration still works on scene revisit
  - [ ] Scene transitions (fade-in) unaffected

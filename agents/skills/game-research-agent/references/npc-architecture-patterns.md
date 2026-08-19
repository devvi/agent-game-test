# NPC Architecture Patterns for Godot 4.x

Patterns for implementing NPC (non-player character) interaction in Godot 4.x games, derived from Issue #54 research on a Godot 4.7 / GDScript 2.0 project with dialogue-engine integration.

## Context

The game had multiple NPCs (guard, clerk, stranger ×3, homeless person) each implemented as bespoke Area3D trigger + dialogue start logic inline in scene scripts. As the count crossed ~6 NPCs, three architectural approaches were evaluated.

## Approach A: Dedicated NPC Scene Component (Recommended)

Create a standalone `NPC.tscn` scene with an `NPCNode.gd` script. The scene is a composition node dropped into any parent scene.

### Scene Tree

```
NPC (NPCNode — root, Node3D)
├── InteractionTrigger (Area3D)
│   └── CollisionShape3D (cylinder, radius = proximity_distance)
├── VisualName (Label3D or LoFiText3D)     — speaker name, billboarded
├── InteractionPrompt (Label3D)             — "⌈Talk⌋" prompt
└── CooldownTimer (Timer)                   — auto-managed
```

### Exported Properties

```gdscript
@export var dialogue_file: String = ""
@export var dialogue_id: String = ""
@export var speaker_name: String = "NPC"
@export var mood_axis: String = "hope_despair"
@export var proximity_distance: float = 3.0
@export var cooldown_seconds: float = 2.0
@export var personality_layers: Array[Dictionary] = []
```

### State Machine

| State | Description | Transitions |
|-------|-------------|-------------|
| `IDLE` | Awaiting interaction, showing prompt on proximity | → TALKING (on click) |
| `TALKING` | In dialogue, ignoring input | → COOLDOWN (on dialogue_ended) |
| `COOLDOWN` | Brief non-interactive period after dialogue | → IDLE or EXHAUSTED (timer) |
| `EXHAUSTED` | All branches visited — terminal until scene reload | — |
| `SPECIAL` | Reserved for conditional states | → IDLE |

### Personality Layers (Optional Advanced Feature)

Each NPC can define personality layers evaluated against GameState at interaction time:

```gdscript
# Example: three-layer clerk personality
personality_layers = [
  {
    "name": "tired_worker",
    "condition": {"type": "always"},  # default
    "name_prefix": "⌈Clerk⌋",
    "greeting_override": ""  # use default entry node
  },
  {
    "name": "cynical_veteran",
    "condition": {"type": "and", "conditions": [
      {"type": "slider", "axis": "hope_despair", "op": "lt", "value": 0}
    ]},
    "name_prefix": "⌈Clerk (distant)⌋",
    "greeting_override": "clerk_greet_cynical"
  },
  {
    "name": "systemic_exhaustion",
    "condition": {"type": "slider", "axis": "hope_despair", "op": "lte", "value": -2},
    "name_prefix": "⌈Tired Voice⌋",
    "greeting_override": "clerk_greet_systemic"
  }
]
```

Layer conditions reuse the project's existing Condition DSL (`DialogueConditionEvaluator`), so no new evaluation code is needed. Layers evaluated in order; first match wins.

### Pros/Cons

**Pros:** 100% reusable, self-contained, no scene-script modification, testable in isolation, progressive complexity (3 exports for simple → personality layers for advanced).

**Cons:** DialogueRunner reference must be resolved at runtime (signal bus or `/root/` lookup), labels need positioning offset per scene.

## Approach B: Extend SceneBase with NPC Methods

Add NPC helper methods to an existing base class (`SceneBase.gd`):

```gdscript
func setup_npc(npc_name: String, dialogue_file: String,
               trigger_node: Area3D, name_label: Label3D) -> void:
    trigger_node.input_event.connect(_on_npc_interacted.bind(npc_name, dialogue_file))
    name_label.text = "⌈%s⌋" % npc_name
```

**Pros:** Familiar pattern, known base class, minimal new code.

**Cons:** NOT reusable outside SceneBase inheritance tree, per-scene trigger/label wiring still required, no state machine, no personality layer system, harder to test.

## Approach C: NPCManager Autoload + Data-Driven Profiles

Create an autoload `NPCManager` that manages all NPC encounters with data-driven profiles in a JSON file:

```json
{
  "npcs": {
    "store_clerk": {
      "speaker_name": "Store Clerk",
      "dialogue_file": "res://dialogues/store_clerk.json",
      "mood_axis": "hope_despair",
      "personality_layers": [...]
    }
  }
}
```

**Pros:** Centralized NPC data, data-driven personality, single point of signal management.

**Cons:** Over-engineered for <10 NPCs, node reference fragility across scene changes (Area3D refs in manager = stale after scene unload), more autoloads, manager lifecycle complexity (track which NPCs are in current scene, disconnect on scene change).

## Decision Flow

Use this decision tree:

```
Is NPC count ≤ 4?           ──→ Approach B (SceneBase extension), fast to implement
Is NPC count 5–15?          ──→ Approach A (NPC.tscn component), best balance
Is this a dialogue-focused  ──→ Approach A (personality layers integrate naturally)
  game with state-driven
  NPC attitudes?
Is NPC count > 15 with      ──→ Approach C (NPCManager), but only if scene transitions
  complex profiles?              are managed (un/register on scene load/unload)
```

## Dialogue Engine Integration

The NPC component consumes existing dialogue engine signals:

| DialogueEngine Signal | NPCNode Listener | Purpose |
|----------------------|------------------|---------|
| `dialogue_started` | Start TALKING state | Lock interaction, hide prompt |
| `dialogue_ended` | Transition to COOLDOWN | Start cooldown timer, re-show prompt after |
| `node_changed` | (Optional) | Could update name label if speaker changes |
| `choices_available` | (Optional) | Could show/hide additional labels |

## Key Design Decisions

1. **DialogueRunner reference:** Resolve at runtime via `get_node_or_null()` or a global signal bus — NOT a hardcoded node path (NPC may be in any scene).
2. **Layer evaluation:** Reuses the existing `DialogueConditionEvaluator.evaluate()` — no new condition code.
3. **State-locked input:** NPCNode ignores `input_event` while state != IDLE to prevent double-triggering.
4. **Layer locked per conversation:** Re-evaluated only on next interaction (after COOLDOWN → IDLE), not mid-dialogue.

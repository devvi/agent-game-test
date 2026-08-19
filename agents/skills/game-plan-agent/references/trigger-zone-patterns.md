# Trigger Zone Patterns (agent-game-test)

> Discovered during plan phase for #218 (2026-07-25)
> This reference documents the two trigger zone archetypes found across the project's 8 scenes.
> Future plan agents should consult this when designing components that integrate with or replace trigger zones.

## Archetype 1: Area3D + `input_event` (found in lobby, bridge, underpass, subway_station)

The simplest pattern. A plain `Area3D` node with a `CollisionShape3D` child. The scene script connects the `input_event` signal directly to a handler method.

### TSCN structure
```
InteractionZones (Node3D)
├── SecurityGuardTrigger (Area3D)          # No script — plain Area3D
│   ├── GuardCollision (CollisionShape3D)   # shape = BoxShape3D
├── StrangerTrigger (Area3D)
│   ├── StrangerCollision (CollisionShape3D)
├── ExitTrigger (Area3D)
│   ├── ExitCollision (CollisionShape3D)
```

### Script wiring (`lobby.gd`)
```gdscript
# In _ready() — manual connection per trigger
if guard_trigger:
    guard_trigger.input_event.connect(_on_guard_trigger_input)
if stranger_trigger:
    stranger_trigger.input_event.connect(_on_stranger_trigger_input)
if exit_trigger:
    exit_trigger.input_event.connect(_on_exit_trigger_input)
```

### No EKeyTrigger child
These zones rely entirely on mouse-click via `input_event`. There is no EKeyTrigger instance and no `body_entered`/`body_exited` wiring for E-key proximity in the scene script.

**Scenes using this pattern:** lobby.tscn, bridge.tscn, underpass.tscn, subway_station.tscn

## Archetype 2: Area3D + EKeyTrigger child (found in office, street)

The trigger zone includes an `EKeyTrigger` (extends Area3D) child that adds E-key proximity interaction. The parent Area3D may also have an `input_event` connection for mouse-click.

### TSCN structure (office.tscn)
```
InteractionZones (Node3D)
├── OfficeDoorTrigger (Area3D)              # Plain Area3D
│   ├── CollisionShape3D (CollisionShape3D)
│   ├── CSGBox3D (CSGBox3D)                # Visual mesh
│   ├── EKeyTrigger (Area3D)               # Script: e_key_trigger.gd
│       ├── CollisionShape3D (CollisionShape3D)
├── DoorLabel (Label3D)
```

### Script wiring (`office.gd`)
```gdscript
# In _ready()
door_trigger.input_event.connect(_on_door_trigger_input)

# E-key interaction wiring
var ekey := $InteractionZones/OfficeDoorTrigger/EKeyTrigger
if ekey and ekey.has_signal("e_key_interacted"):
    if not ekey.e_key_interacted.is_connected(_start_door_dialogue):
        ekey.e_key_interacted.connect(_start_door_dialogue)
```

**EKeyTrigger** (`e_key_trigger.gd`) adds itself to the `"interactable"` group in `_ready()`, and connects the PlayerController's `interaction_requested` signal (from `_nearby_interactables` stack) when the player enters the EKeyTrigger's collision zone.

**Scenes using this pattern:** office.tscn, street.tscn (street's StoreEntranceTrigger has Area3D + CSGBox3D but no EKeyTrigger; the TestNPC zone has an EKeyTrigger on its NPC's InteractionTrigger)

## Archetype 3: ExitZone subclass (found in street)

ExitZone is a standalone Area3D subclass (`exit_zone.gd`, class_name `ExitZone`) that handles scene transitions. It is NOT placed under `InteractionZones` — it is a direct child of the scene root.

### TSCN structure (street.tscn)
```
StreetRoot (Node3D)
├── ExitZoneToOffice (Area3D)              # Script: exit_zone.gd
│   ├── target_scene = "res://scenes/office/office.tscn"
│   ├── spawn_point = Vector3(0, 0, 2)
│   ├── transition_mode = 0 (AUTO)
│   ├── CollisionShape3D (CollisionShape3D)
├── ExitZoneToStore (Area3D)
│   ├── target_scene = "res://scenes/store/convenience_store.tscn"
│   ├── spawn_point = Vector3(0, 0, 0)
│   ├── transition_mode = 0 (AUTO)
│   ├── CollisionShape3D (CollisionShape3D)
```

### Key characteristics
- Extends Area3D, not Node3D
- Has `body_entered` for player proximity → triggers `_transition()` (AUTO mode) or shows label + connects E-key (EKEY mode)
- Creates `_prompt_label` (Label3D) dynamically in `_ready()` if `prompt_text` is set
- Creates `_cooldown_timer` (Timer) dynamically for AUTO mode debounce
- Calls `sm.trigger_zone_transition(target_scene)` on the parent's SceneManager
- Has 0.5s deferred monitoring start to prevent spawn-inside-zone trigger
- `input_event` is NOT connected on ExitZone — it uses `body_entered` exclusively

**Scenes using this pattern:** street.tscn (two ExitZones)

## Archetype 4: NPC.tscn (packed scene, found in street)

NPC.tscn is a packed scene with NPCNode (extends Node3D) as root, containing an InteractionTrigger (Area3D) child.

### TSCN structure
```
NPC (Node3D)                               # Script: npc_node.gd
├── InteractionTrigger (Area3D)            # No script — plain Area3D
│   ├── CollisionShape3D (CollisionShape3D) # CylinderShape3D
├── VisualName (Label3D)                    # Billboarded
├── InteractionPrompt (Label3D)             # Billboarded
├── CooldownTimer (Timer)                   # One-shot
```

### Script wiring (`npc_node.gd`)
```gdscript
# In _ready() — connects to the InteractionTrigger child
_trigger_area = $InteractionTrigger as Area3D
_trigger_area.body_entered.connect(_on_body_entered)    # Show/hide labels
_trigger_area.body_exited.connect(_on_body_exited)
_trigger_area.input_event.connect(_on_interaction)      # Mouse click → dialogue
```

NPCNode does NOT have an `EKeyTrigger` child by default. The street.tscn scene adds one manually:
```
NPC.tscn instance → InteractionTrigger → EKeyTrigger (Area3D) [script: e_key_trigger.gd]
```

## Summary Table

| Archetype | Base Class | Detection | EKey Support | Scene Script Wiring |
|-----------|-----------|-----------|-------------|-------------------|
| Area3D + `input_event` | Area3D | Mouse click | ❌ Manual (add EKeyTrigger instance) | `trigger.input_event.connect(handler)` in `_ready()` |
| Area3D + EKeyTrigger | Area3D | Mouse click + E-key proximity | ✅ Built-in via EKeyTrigger child | Both `input_event` and EKey `e_key_interacted` in `_ready()` |
| ExitZone | Area3D (subclass) | Body proximity (auto/E-key) | ✅ Via `interaction_requested` signal from PlayerController | Built into ExitZone._ready() — no scene script wiring needed |
| NPC.tscn | Node3D (NPCNode) | Body proximity + mouse click | ⚠️ Optional (street adds manually) | `body_entered` for labels, `input_event` for click |

## Common Integration Decisions

When adding a new component (e.g., InteractiveArea) to an existing zone:

1. **Arch 1 (Input-event-only zone):** Best suited for wrapping the plain Area3D with the new component (Pattern 2). Replace the Area3D node with InteractiveArea, connect `interactable_clicked` to the scene script handler instead of `input_event`.

2. **Arch 2 (Area3D + EKeyTrigger):** Add InteractiveArea as a sibling under the parent Area3D (Pattern 1). The existing EKeyTrigger and `input_event` continue working. InteractiveArea handles only visual feedback.

3. **Arch 3 (ExitZone):** Add InteractiveArea as a sibling of ExitZone (Pattern 1). Do NOT subclass ExitZone with InteractiveArea unless ExitZone is being generalized. ExitZone's body_entered triggers scene transitions; InteractiveArea's visual feedback is separate.

4. **Arch 4 (NPC.tscn):** Add InteractiveArea as a child of the NPC root (Node3D), sibling to InteractionTrigger (Pattern 1). NPCNode's label visibility continues; InteractiveArea adds visual feedback independently.

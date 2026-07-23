# Design: #142 — Player Controller (WASD/Mouse/E)

> Parent Issue: #142
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Add a first-person CharacterBody3D player controller to the existing narrative-driven Metroidvania Snake. The player navigates scenes using WASD (relative to camera facing), looks around via click-and-drag mouse (NOT captured pointer — preserves cursor for UI interactions), and presses E to interact with NPCs within 2m proximity. The controller is re-created on each scene load by SceneBase, with position/rotation persisted via GameManager.

**Key constraint:** This is a narrative walking sim, not an action game — no jump, no sprint, no crouch. Walk speed is a leisurely 2.5 m/s. The player's primary agency is walking to interactable areas and engaging in dialogue.

### Data Flow

```
Scene Load (change_scene_to_file)
    │
    ├──► Scene root node (e.g. Office, Lobby) — scene-specific Node3D
    │       ├──► SceneBase._ready()
    │       │       ├──► Instantiate PlayerController as child of ENVIRONMENT root
    │       │       │       └──► Set position/rotation from GameManager.player_position/player_rotation
    │       │       │       └──► add_to_group("player") — needed by NPCNode proximity
    │       │       │
    │       │       ├──► scene_manager.fade_in() — existing fade transition
    │       │       ├──► _configure_environmental_text() — existing state-aware text
    │       │       └──► _restore_dialogue_state() — existing dialogue persistence
    │       │
    │       ├──► PlayerController (PlayerController.gd) — CharacterBody3D child
    │       │       ├──► _physics_process(delta):
    │       │       │       ├──► If _dialogue_active: skip movement
    │       │       │       ├──► Read Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
    │       │       │       ├──► Transform input direction by camera basis (relative movement)
    │       │       │       ├──► velocity = direction * WALK_SPEED (2.5 m/s)
    │       │       │       └──► move_and_slide() — resolves against StaticBody3D colliders
    │       │       │
    │       │       ├──► _input(event):
    │       │       │       ├──► If MouseButton + dragged:
    │       │       │       │       ├──► rotate_y(-event.relative.x * LOOK_SENSITIVITY)
    │       │       │       │       └──► head.rotate_x(-event.relative.y * LOOK_SENSITIVITY)
    │       │       │       │           └──► Clamp head.rotation.x to [-60°, +60°]
    │       │       │       │
    │       │       │       ├──► If interact (E) — key was pressed:
    │       │       │       │       ├──► Check _nearby_npcs stack (LIFO)
    │       │       │       │       ├──► If stack not empty:
    │       │       │       │       │       └──► Emit interaction_requested(npc)
    │       │       │       │       └──► Else: silent (no feedback)
    │       │       │       │
    │       │       │       ├──► If dialogue_active:
    │       │       │       │       ├──► E → route to dialogue_select (if E not already mapped)
    │       │       │       │       └──► Space → dialogue_select (already mapped in project.godot)
    │       │       │       │
    │       │       │       └──► Release mouse button → stop look drag
    │       │       │
    │       │       ├──► _on_NPC_body_entered(body):
    │       │       │       └──► If body is_in_group("interactable"):
    │       │       │               └──► Push to _nearby_npcs stack
    │       │       │
    │       │       └──► _on_NPC_body_exited(body):
    │       │               └──► Remove from _nearby_npcs stack
    │       │
    │       └──► Existing scene content (NPCs, text, triggers)
    │
    ├──► SceneManager (child of scene root)
    │       └──► fade_transition → change_scene_to_file(new_scene)
    │
    └──► Autoloads (persist across scene change)
            ├──► GameManager — stores player_position, player_rotation, player_scene
            │       ├──► On scene change: SceneBase saves position before fade
            │       └──► On scene load: SceneBase reads position from GameManager
            ├──► StateSystem — tri-axis state
            ├──► NarrativeManager — scene sequence, echo system
            └──► AudioManager — ambient audio
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Body type | CharacterBody3D | Full velocity control, move_and_slide() collision resolution. No gravity needed (narrative pace: no fall damage). |
| Player lifetime | Per-scene instance, not autoload | Each scene has a unique spawn point. PlayerController is created/freed with each scene load, keeping memory clean. |
| Position persistence | GameManager.player_position, .player_rotation | Saved in SceneBase._exit_tree() before scene unload, restored in SceneBase._ready() after instantiation. |
| Mouse look | Click-and-drag (NOT captured) | Preserves cursor for existing UI interactions (dialogue choices, status bar). Players click-drag to look instead of losing cursor. |
| Camera location | Child of PlayerController (Camera3D at head), current=true | Each scene's PlayerController has its own camera. The main.tscn Camera3D at (0,2,5) uses current=false. |
| Interaction detection | E-key proximity via NPCNode.body_entered (existing) | NPCNode already detects body.is_in_group("player"). PlayerController adds itself to "player" group. A proximity Area3D on PlayerController detects nearby NPC nodes. |
| Dialogue mode blocking | WASD pauses when _dialogue_active == true | Prevents player walking during conversations. E routes to dialogue_select to avoid conflict. |
| Scene change position | SceneBase saves position in _exit_tree() | SceneBase already has lifecycle hooks. Adding save/restore there is minimal change. |
| Collision layers | Layer 1 (default) for player, Layer 2 for scene geometry | Simple two-layer setup avoids collision mismatch issues. |

---

## 2. Node / Scene Tree Layer

### New Component: PlayerController (gdscripts/player_controller.gd)

Not a standalone scene — instantiated programmatically by SceneBase._ready(). The node tree at runtime:

```
PlayerController (CharacterBody3D)
    ├── CollisionShape3D (CapsuleShape3D) — player body collision
    ├── Head (Node3D) — mouse look pitch rotation
    │       └── Camera3D — current=true, position=(0, 1.6, 0), slight tilt
    ├── InteractionArea (Area3D) — 2m proximity trigger
    │       └── CollisionShape3D (SphereShape3D, radius=2.0)
    └── FallReset (Area3D) — detects player falling off world
            └── CollisionShape3D (BoxShape3D, huge bounds)
```

### Existing Scene Modifications

#### `scenes/main.tscn`

- **Camera3D** at line 19-22: Set `current = false` (PlayerController's camera becomes current). Also optionally mark as comment or remove since each scene's PlayerController provides the camera.

#### Scene root nodes (all game scenes)

No structural changes needed — PlayerController is added as a child programmatically.

### PlayerController Scene Parenting

PlayerController is added to the **scene root** (e.g., the root Node3D of office.tscn, lobby.tscn, etc.) by SceneBase._ready(). This means:

- PlayerController's transform is in the scene's local coordinate space
- Collision resolves against scene StaticBody3D geometry
- NPCNode Area3D triggers detect the PlayerController body
- Camera is a child of PlayerController's Head node → moves/looks with player

---

## 3. GDScript / Logic Layer

### New Script: `gdscripts/player_controller.gd`

**Extends:** `CharacterBody3D`

**Purpose:** WASD movement, click-and-drag mouse look, E-key interaction trigger, dialogue mode blocking.

**class_name:** `PlayerController` (for type checks and potential future reuse)

```gdscript
extends CharacterBody3D
class_name PlayerController

# ── Exports ──
@export var walk_speed: float = 2.5            # m/s — leisurely narrative pace
@export var look_sensitivity: float = 0.003     # radians per pixel
@export var interaction_range: float = 2.0      # meters — E-key proximity
@export var camera_height: float = 1.6          # meters — eye level
@export var camera_tilt: float = -0.087         # radians (~-5°) slight downward tilt
@export var look_vertical_clamp: float = 1.047  # radians (60°) — ±60° vertical look

# ── Nodes ──
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var camera_collision: RayCast3D = $Head/CameraCollision  # optional: prevent camera clip

# ── State ──
var _dialogue_active: bool = false
var _mouse_dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _nearby_interactables: Array[Node] = []  # LIFO stack of nearby interactable nodes
var _fall_reset_position: Vector3 = Vector3.ZERO

# ── Signals ──
signal interaction_requested(target: Node)
signal dialogue_mode_changed(active: bool)

func _ready() -> void:
    add_to_group("player")
    camera.current = true
    head.rotation.x = camera_tilt  # slight downward tilt

    # Interaction area setup
    if interaction_area:
        interaction_area.body_entered.connect(_on_interaction_body_entered)
        interaction_area.body_exited.connect(_on_interaction_body_exited)

    # Set camera current and disable main scene camera
    _disable_other_cameras()

    # Connect to dialogue runner for mode changes
    _connect_dialogue_signals()

func _disable_other_cameras() -> void:
    # Ensure this PlayerController's camera is the only active one
    for c in get_tree().get_nodes_in_group("Cameras"):
        if c != camera:
            c.current = false

func _connect_dialogue_signals() -> void:
    var scene_root := get_tree().current_scene
    if not scene_root:
        return
    var dr := scene_root.get_node_or_null("CanvasLayer/DialoguePanel")
    if dr:
        if dr.has_signal("dialogue_started"):
            dr.dialogue_started.connect(_on_dialogue_started)
        if dr.has_signal("dialogue_ended"):
            dr.dialogue_ended.connect(_on_dialogue_ended)

# ── Input ──

func _input(event: InputEvent) -> void:
    # Mouse look: click-and-drag (button held)
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed and not _dialogue_active:
            _mouse_dragging = true
            _last_mouse_pos = event.global_position
        elif not event.pressed:
            _mouse_dragging = false

    if event is InputEventMouseMotion and _mouse_dragging and not _dialogue_active:
        var delta: Vector2 = event.global_position - _last_mouse_pos
        _last_mouse_pos = event.global_position
        _handle_mouse_look(delta)

    # E-key interaction (only when not in dialogue)
    if event.is_action_pressed("interact") and not _dialogue_active:
        _try_interact()

    # Dialogue mode: route E/Space to dialogue_select
    if _dialogue_active and event.is_action_pressed("interact"):
        # E in dialogue mode: treat as dialogue_select if configured
        _route_to_dialogue_select()
    if _dialogue_active and event.is_action_pressed("dialogue_select"):
        # Space already mapped — handled by main.gd; no action needed here
        pass

func _handle_mouse_look(delta: Vector2) -> void:
    # Yaw: rotate entire body (horizontal look)
    rotate_y(-delta.x * look_sensitivity)

    # Pitch: rotate head only (vertical look), clamped
    var pitch_delta: float = -delta.y * look_sensitivity
    head.rotation.x = clamp(
        head.rotation.x + pitch_delta,
        -look_vertical_clamp + camera_tilt,
        look_vertical_clamp + camera_tilt
    )

func _try_interact() -> void:
    if _nearby_interactables.is_empty():
        return
    # LIFO: interact with the most recent body_entered
    var target: Node = _nearby_interactables.back()
    if not is_instance_valid(target):
        _nearby_interactables.pop_back()
        _try_interact()  # recurse to next valid
        return
    interaction_requested.emit(target)

func _route_to_dialogue_select() -> void:
    # Only route E to dialogue if the dialogue runner is expecting input
    var scene_root := get_tree().current_scene
    if not scene_root:
        return
    var dr := scene_root.get_node_or_null("CanvasLayer/DialoguePanel")
    if dr and dr.has_method("select_current") and dr.visible:
        dr.select_current()

# ── Physics ──

func _physics_process(delta: float) -> void:
    # Skip movement during dialogue
    if _dialogue_active:
        # Apply gentle braking if any residual velocity
        velocity = velocity.move_toward(Vector3.ZERO, walk_speed * delta)
        move_and_slide()
        return

    # WASD input relative to camera facing
    var input_dir: Vector2 = Input.get_vector(
        "move_left", "move_right",
        "move_forward", "move_backward"
    )

    # Project camera forward onto XZ plane (ignore pitch)
    var camera_basis: Basis = head.global_transform.basis
    var forward: Vector3 = -camera_basis.z
    forward.y = 0.0
    forward = forward.normalized()
    var right: Vector3 = camera_basis.x
    right.y = 0.0
    right = right.normalized()

    var direction: Vector3 = Vector3.ZERO
    direction += forward * -input_dir.y  # move_forward/backward
    direction += right * input_dir.x     # move_left/right
    direction = direction.normalized()

    if direction != Vector3.ZERO:
        velocity.x = direction.x * walk_speed
        velocity.z = direction.z * walk_speed
    else:
        # Deceleration
        velocity.x = move_toward(velocity.x, 0.0, walk_speed)
        velocity.z = move_toward(velocity.z, 0.0, walk_speed)

    move_and_slide()

# ── Interaction Proximity ──

func _on_interaction_body_entered(body: Node) -> void:
    if body.is_in_group("interactable") and not _nearby_interactables.has(body):
        _nearby_interactables.append(body)

func _on_interaction_body_exited(body: Node) -> void:
    _nearby_interactables.erase(body)

# ── Dialogue Mode ──

func _on_dialogue_started(_dialogue_id: String) -> void:
    _dialogue_active = true
    dialogue_mode_changed.emit(true)

func _on_dialogue_ended() -> void:
    _dialogue_active = false
    dialogue_mode_changed.emit(false)

# ── Fall Recovery ──

func set_fall_reset_position(pos: Vector3) -> void:
    _fall_reset_position = pos

func _on_fall_detector_body_entered(body: Node) -> void:
    if body == self:
        global_position = _fall_reset_position
        velocity = Vector3.ZERO
```

### Modified Script: `gdscripts/scene_base.gd`

**Changes needed:**
- Import PlayerController
- Add `_player: Node` member
- In `_ready()`, after fade-in: call `_instantiate_player()`
- Add `_instantiate_player()` method: creates PlayerController at spawn point
- Override `_exit_tree()` (new): save player position to GameManager before scene unload
- Add `_get_player_spawn_point()`: returns spawn marker position (configurable per scene)

```gdscript
# Add to top of file:
const PLAYER_CONTROLLER := preload("res://gdscripts/player_controller.gd")

# Add member variable:
var _player: Node = null

# Add method:
func _instantiate_player() -> void:
    if _player and is_instance_valid(_player):
        return  # Already exists
    _player = PLAYER_CONTROLLER.instantiate()
    _player.name = "PlayerController"
    add_child(_player)
    
    # Restore position from GameManager
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm:
        var saved_pos: Variant = gm.get("player_position", null)
        if saved_pos != null and saved_pos is Vector3:
            _player.global_position = saved_pos
        var saved_rot: Variant = gm.get("player_rotation", null)
        if saved_rot != null and saved_rot is Vector3:
            _player.global_rotation = saved_rot
        var saved_head_rot: Variant = gm.get("player_head_rotation", null)
        if saved_head_rot != null and saved_head_rot is float:
            _player.get_node("Head").rotation.x = saved_head_rot
    
    # Connect interaction_requested signal
    if _player.has_signal("interaction_requested"):
        _player.interaction_requested.connect(_on_player_interaction)
    
    # Set fall reset position to spawn point
    if _player.has_method("set_fall_reset_position"):
        _player.set_fall_reset_position(_get_player_spawn_position())

# Add:
func _get_player_spawn_position() -> Vector3:
    # Default spawn: position of SpawnPoint marker if exists, else origin
    var sp := get_node_or_null("SpawnPoint")
    if sp:
        return sp.global_position
    return Vector3.ZERO

# Add new method (empty default — scenes override if they have E-key NPCs):
func _on_player_interaction(target: Node) -> void:
    # Default: delegate to NPCNode if target has npc_interaction method
    if target.has_method("start_npc_interaction"):
        target.start_npc_interaction()
    elif target.has_method("start_dialogue"):
        # Legacy: some triggers have start_dialogue
        pass
    push_warning("SceneBase._on_player_interaction: unhandled target '%s'" % target.name)

# Modify _ready() to call _instantiate_player():
func _ready() -> void:
    if scene_manager and scene_manager.has_method("fade_in"):
        scene_manager.fade_in()
    _instantiate_player()  # NEW
    _configure_environmental_text()
    _configure_ambient_audio()
    _restore_dialogue_state()

# Add _exit_tree() to save player state:
func _exit_tree() -> void:
    _save_player_state()

func _save_player_state() -> void:
    if not _player or not is_instance_valid(_player):
        return
    var gm: Node = get_node_or_null("/root/GameManager")
    if not gm:
        return
    gm.set("player_position", _player.global_position)
    gm.set("player_rotation", _player.global_rotation)
    var head := _player.get_node_or_null("Head")
    if head:
        gm.set("player_head_rotation", head.rotation.x)
```

### Modified Script: `gdscripts/game_manager.gd`

**Changes needed:**
- Add three new member variables for player persistence:

```gdscript
# Player position/rotation across scene transitions (Issue #142)
var player_position: Vector3 = Vector3.ZERO
var player_rotation: Vector3 = Vector3.ZERO
var player_head_rotation: float = 0.0
```

These are set by SceneBase._exit_tree() and read by SceneBase._instantiate_player().

### Modified Script: `gdscripts/main.gd`

**Changes needed:**
- The Camera3D in main.tscn should have `current = false` (it's a fallback; the PlayerController's camera becomes current).
- Optionally, remove the Camera3D from main.tscn entirely since each scene's PlayerController provides one.

### Existing NPC Scripts (No Changes Needed)

- `npc_node.gd` — Already checks `body.is_in_group("player")` in `_on_body_entered`/`_on_body_exited`. The PlayerController adds itself to "player" group. No changes needed.
- However, NPCNode currently uses `is_interactable()` which checks `current_state == NPCState.IDLE`. This is fine for both mouse-click and E-key interaction. E-key adds an additional path.

### All Scene Scripts (office.gd, lobby.gd, bridge.gd, etc.)

**Changes needed (minor):** Add `body_entered`/`body_exited` handlers on scene-specific Area3D triggers that reference `body.is_in_group("player")` if they should respond to E-key proximity. However, the simplest approach is:

- The **existing click-based triggers** (`_on_door_trigger_input` etc.) continue to work unchanged.
- **NPC nodes** already use body_entered/body_exited with "player" group detection.
- **New E-key door triggers** can be added as Area3D children of the scene with a script that checks `body.is_in_group("player")` and routes to the same handler.

To minimize changes, we introduce a **generic E-key interaction component** (`EKeyTrigger.gd`) that scenes can drop in:

```gdscript
# gdscripts/e_key_trigger.gd — Drop-in Area3D child for E-key interaction
extends Area3D
class_name EKeyTrigger

signal e_key_interacted()

func _ready() -> void:
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)
    add_to_group("interactable")

func _on_body_entered(body: Node) -> void:
    if body.is_in_group("player") and body.has_signal("interaction_requested"):
        if not body.interaction_requested.is_connected(_on_player_interact):
            body.interaction_requested.connect(_on_player_interact)

func _on_body_exited(body: Node) -> void:
    if body.is_in_group("player") and body.has_signal("interaction_requested"):
        if body.interaction_requested.is_connected(_on_player_interact):
            body.interaction_requested.disconnect(_on_player_interact)

func _on_player_interact(_target: Node) -> void:
    if is_instance_valid(self):
        e_key_interacted.emit()
```

Each scene can drop EKeyTrigger as a child of its trigger Area3D and connect `e_key_interacted` to the existing handler (e.g., `_start_door_dialogue()`).

---

## 4. Resource / Config Layer

### Project Configuration: Input Map

Add the following input actions to `project.godot` in the `[input]` section:

```ini
# — Player Controller Input (Issue #142) —

move_forward={
"deadzone": 0.5,
"events": [{"keycode": 87, "type": 0}, {"keycode": 4194320, "type": 0}]
}
move_backward={
"deadzone": 0.5,
"events": [{"keycode": 83, "type": 0}, {"keycode": 4194322, "type": 0}]
}
move_left={
"deadzone": 0.5,
"events": [{"keycode": 65, "type": 0}, {"keycode": 4194319, "type": 0}]
}
move_right={
"deadzone": 0.5,
"events": [{"keycode": 68, "type": 0}, {"keycode": 4194321, "type": 0}]
}
interact={
"deadzone": 0.5,
"events": [{"keycode": 69, "type": 0}]
}
```

Keycode reference:
- W=87, S=83, A=65, D=68
- ↑=4194320, ↓=4194322, ←=4194319, →=4194321
- E=69

No new Autoloads needed.

---

## 5. Input / UI Layer

### Complete Input Action Table

| Action | Key(s) | Context | Effect |
|--------|--------|---------|--------|
| move_forward | W / ↑ | Gameplay | Move camera direction |
| move_backward | S / ↓ | Gameplay | Move opposite camera direction |
| move_left | A / ← | Gameplay | Strafe left |
| move_right | D / → | Gameplay | Strafe right |
| interact | E | Gameplay, Near interactable | Trigger nearest NPC/door interaction |
| look (mouse) | Left-click drag | Gameplay, Not in dialogue | Rotate camera (yaw/pitch) |
| dialogue_select | Space / Enter | Dialogue mode | Select focused choice |
| dialogue_up | ↑ | Dialogue mode | Navigate choice up |
| dialogue_down | ↓ | Dialogue mode | Navigate choice down |

### Dialogue Mode Input Routing

When `_dialogue_active == true`:
- **WASD**: ignored (movement pauses)
- **Mouse look**: ignored (drag doesn't rotate)
- **E**: routes to `dialogue_select` (not `interact`) — provides alternative to Space
- **Space**: handled by existing `dialogue_select` action in main.gd

### Multiple Interactable Stack (LIFO)

When the player is within range of multiple interactables simultaneously:

```
player walks near NPC A       → [A]
player walks near NPC B       → [A, B]  (B stacked on top)
player presses E              → NPC B interacts (most recent)
player walks away from B      → [A]
player presses E              → NPC A interacts
player walks away from A      → []
```

The LIFO behavior ensures the player interacts with the most recently entered trigger, which feels natural (nearest/most recently seen).

---

## 6. Scene Transition Flow

### Scene Change Sequence

```
1. Gameplay → dialogue choice triggers scene change
2. DialogueRunner.choice_made → SceneManager._on_choice_made()
3. SceneManager.trigger_scene_change(target_scene):
    a. Persist dialogue choices_made to GameManager
    b. Fade out (0.5s)
    c. change_scene_to_file(target_scene)
       → Old scene tree freed
       → SceneBase._exit_tree() fires → saves player position/rotation to GameManager
       → New scene loads
       → New SceneBase._ready() fires:
            → scene_manager.fade_in()
            → _instantiate_player() → reads GameManager.player_position
            → _configure_environmental_text()
            → _restore_dialogue_state()
```

### Initial Scene Load (main.tscn → first scene)

```
1. main.tscn loads
2. main.gd._ready() → call_deferred("_load_starting_scene")
3. change_scene_to_file("res://scenes/office/office.tscn")
4. office.gd._ready():
    → scene_id = "office"
    → super._ready() = SceneBase._ready()
        → scene_manager.fade_in()
        → _instantiate_player() → creates PlayerController at office spawn
            → GameManager.player_position is Vector3.ZERO (first time)
            → Falls through to SpawnPoint marker or origin
        → _configure_environmental_text()
        → _restore_dialogue_state()
```

---

## 7. Collision and Spatial Setup

### Collision Layers

| Layer | Mask Bits | Used By |
|-------|-----------|---------|
| 1 (Default) | Collide with 2 | PlayerController body |
| 2 (Scene Geometry) | Collide with 1 | StaticBody3D walls, floors |
| 3 (Interaction Trigger) | Detect 1 | Area3D interaction triggers (NPCNode, EKeyTrigger) |

PlayerController: `collision_layer = 1`, `collision_mask = 2`
Scene geometry: `collision_layer = 2`, `collision_mask = 1`
Interaction triggers: `collision_layer = 3`, `collision_mask = 1`

### Spawn Points

Each scene should have a `SpawnPoint` Marker3D child at the intended player spawn location. SceneBase._get_player_spawn_position() reads this. If missing, falls back to Vector3.ZERO.

### Fall-Off-World Recovery

- An Area3D child of PlayerController with a large box shape at y = -10 detects fall
- On body_entered, resets player to _fall_reset_position (set to spawn point)
- For scenes with raised platforms or balconies, the spawn point should be at ground level

---

## 8. EKeyTrigger Integration Per Scene

| Scene | Interactables | E-key needed? | Notes |
|-------|--------------|---------------|-------|
| Office | OfficeDoorTrigger | Yes | Door dialogue (existing click + E-key) |
| Office | — | No | NPCs use NPCNode (already E-key ready) |
| Lobby | GuardTrigger | Yes | Guard dialogue (click + E-key) |
| Lobby | StrangerTrigger | Yes | Stranger dialogue (click + E-key) |
| Street | StoreEntranceTrigger | Yes | Store entrance dialogue |
| Store | ExitTrigger | Yes | Exit dialogue |
| Store | Clerk NPC | No | NPCNode handles E-key via "player" group |
| Bridge | RailingTrigger | Optional | Flavor text, no dialogue needed |
| Bridge | HomelessTrigger | Yes | Homeless dialogue |
| Underpass | GraffitiTrigger | Optional | Flavor text |
| Underpass | StrangerEchoTrigger | Yes | Echo dialogue |
| Subway Station | GateTrigger | Yes | Ending dialogue |
| Subway Station | TurnBackTrigger | Yes | Ending dialogue |
| Subway Station | BenchTrigger | Yes | Ending dialogue |

For each scene with E-key needed, add an EKeyTrigger child to the relevant Area3D and connect `e_key_interacted` to the existing handler.

---

## 9. Files Changed

| Layer | File | Change | Est. Lines |
|-------|------|--------|-----------|
| Script | `gdscripts/player_controller.gd` | **New** | +210 |
| Script | `gdscripts/e_key_trigger.gd` | **New** | +45 |
| Script | `gdscripts/scene_base.gd` | **Modify** | +55 |
| Script | `gdscripts/game_manager.gd` | **Modify** | +6 |
| Script | `gdscripts/main.gd` | **Modify** | ~2 (camera current=false) |
| Config | `project.godot` | **Modify** | +35 (input map actions) |
| Scene | `scenes/main.tscn` | **Modify** | ~2 (Camera3D current=false) |
| Scene | each scene .tscn | **Modify** | +5 per scene with EKeyTrigger |
| Test | `tests/unit/test_player_controller.gd` | **New** | +180 |
| Test | `tests/unit/test_e_key_trigger.gd` | **New** | +80 |
| Test | `tests/integration/test_player_in_scene.gd` | **New** | +100 |
| Design | `docs/DESIGN/142-player-controller.md` | **New** | — |

---

## 10. Verification Checklist

- [ ] WASD moves player at 2.5 m/s relative to camera facing direction
- [ ] Left-click drag rotates view, clamped vertically to ±60°
- [ ] Releasing mouse button stops look rotation immediately
- [ ] E-key within 2m of interactable triggers interaction_requested signal
- [ ] E-key with no nearby interactable: silent (no error, no feedback)
- [ ] NPCNode proximity detection works: body.is_in_group("player") returns true
- [ ] Mouse click on existing Area3D triggers still work (backward compatible)
- [ ] Dialogue mode: WASD pauses, E routes to dialogue_select
- [ ] Dialogue mode: Space continues to work for dialogue_select
- [ ] Scene transition: player position persists across scene changes
- [ ] Multiple overlapping interactables: LIFO stack prioritizes most recently entered
- [ ] Fall-off-world: player resets to spawn point
- [ ] Camera conflict: only PlayerController's Camera3D has current=true
- [ ] Collision: player collides with StaticBody3D walls, doesn't clip through
- [ ] Main.tscn Camera3D has current=false (or removed)
- [ ] All existing scene scripts compile without errors
- [ ] All existing test suites pass

---

## 11. Edge Cases and Failure Paths

### Edge Cases

| # | Edge Case | Expected Behavior |
|---|-----------|-------------------|
| EC1 | Multiple overlapping triggers | LIFO stack: press E interacts with most recently entered |
| EC2 | Scene change during movement | PlayerController freed by scene unload; position saved by _exit_tree() before free |
| EC3 | Escape pressed during mouse drag | Mouse button released → _mouse_dragging = false; cursor stays visible |
| EC4 | E-key during dialogue | Routes to dialogue_select (not interact); no movement change |
| EC5 | E-key with no interactable | Silent failure — no error, no feedback |
| EC6 | SpawnPoint missing in scene | Graceful fallback to Vector3.ZERO |
| EC7 | Player falls off world | FallDetector Area3D catches it; player repositioned to spawn |
| EC8 | Camera duplicate conflict | PlayerController's camera set current=true; all others set current=false in _ready() |
| EC9 | Dialogue runner not present | PlayerController._connect_dialogue_signals() is a no-op; dialogue_active stays false |
| EC10 | GameManager not present | Player position defaults to Vector3.ZERO (first playthrough) |
| EC11 | Collision layer mismatch | Player on layer 1, geometry on layer 2, masks set correctly |
| EC12 | Head node rotation after scene transition | Saved via player_head_rotation, restored on scene load |
| EC13 | Two PlayerControllers in scene | Guard in _instantiate_player(): check if _player exists before creating |
| EC14 | Walk speed 0 (edge freeze) | velocity stays Vector3.ZERO; move_and_slide() safe with zero velocity |
| EC15 | Very high delta (frame hitch) | move_toward clamps velocity; move_and_slide() handles variable delta safely |

### Failure Paths

| # | Failure Path | Mitigation |
|---|--------------|------------|
| FP1 | GameManager autoload missing (headless test) | Null check on get_node_or_null("/root/GameManager") in SceneBase._save_player_state() |
| FP2 | Scene tree.current_scene null during init | Guard with `if not get_tree() or not get_tree().current_scene: return` |
| FP3 | Interaction target freed mid-stack | is_instance_valid() check in _try_interact() before using target |
| FP4 | Camera3D node path changed | @onready var fails gracefully with null; _disable_other_cameras() skips null |
| FP5 | Head node missing | Null check in _handle_mouse_look() and _save_player_state() |
| FP6 | Input action 'interact' not defined | Input.get_action_strength returns 0.0; _input won't fire for undefined action |
| FP7 | player_position/player_rotation not in GameManager | `get("player_position", null)` returns null; code checks for null |
| FP8 | Signal connection to already-freed dialogue runner | disconnect before connect; use is_connected() guard |

---

## Appendix A: SceneBase._ready() Injection Point Architecture

The key architectural choice is using `SceneBase._ready()` as the player instantiation point. Here is the complete flow:

```
Godot engine loads scene file (e.g., office.tscn)
    → Scene root Node3D with office.gd (extends SceneBase)
    → Children instantiated (Environments, InteractionZones, NPCs)
    → SceneBase._ready() called:
        1. scene_manager.fade_in()
        2. _instantiate_player()
            → PlayerController instance created
            → add_child called
            → PlayerController._ready() fires:
                - add_to_group("player")
                - Camera3D sets current=true
                - Connects interaction_area signals
                - Connects dialogue runner signals
            → Position/rotation restored from GameManager
            → interaction_requested signal connected
        3. _configure_environmental_text()
        4. _configure_ambient_audio()
        5. _restore_dialogue_state()
```

This ensures the PlayerController exists before any environmental logic runs that might reference it, and all NPC Area3D triggers can detect the player on the first physics frame.

---

## Appendix B: Interaction Request Signal Flow

```
Player presses E (while near NPC)
    │
    └──► PlayerController._input()
            └──► _try_interact()
                    └──► Check _nearby_interactables stack (LIFO)
                            └──► If top valid:
                                    └──► emit interaction_requested(top_npc)
                                            │
                                            └──► SceneBase._on_player_interaction(target)
                                                    │
                                                    ├──► [if target.has_method("start_npc_interaction")]
                                                    │       └──► NPCNode.start_npc_interaction()
                                                    │               └──► Same as mouse-click path:
                                                    │                   evaluate_personality_layer()
                                                    │                   set_state(TALKING)
                                                    │                   dialogue_runner.start(...)
                                                    │
                                                    ├──► [if EKeyTrigger connected]
                                                    │       └──► e_key_interacted.emit()
                                                    │               └──► Connected handler calls dialogue
                                                    │
                                                    └──► [neither]: push_warning (unhandled)
```

---

## Appendix C: Existing main.gd + Dialogue Input No-Conflict Strategy

The existing `main.gd` handles dialogue input (`dialogue_up`, `dialogue_down`, `dialogue_select`, `dialogue_skip`, digit keys) in its `_input()` method. PlayerController also uses `_input()` for mouse look and E-key.

**No conflict** because:
1. PlayerController and main.gd are in different scene trees (PlayerController is in the game scene child; main.gd is in the persistent main.tscn)
2. Both receive `_input()` calls — Godot dispatches input to all nodes
3. PlayerController only processes `interact` action and mouse events — no overlap with dialogue actions
4. When `_dialogue_active == true`, PlayerController skips movement and routes E to dialogue_select

**Potential conflict:** `interact` (E) in dialogue mode should not also fire `dialogue_select`. The `dialogue_select` action is mapped to Space/Enter, NOT E. If we want E to also select choices, we need to add E to the `dialogue_select` action OR have PlayerController manually fire `dialogue_select` in dialogue mode. The latter is cleaner to avoid changing existing input bindings.

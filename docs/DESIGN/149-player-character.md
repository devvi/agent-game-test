# Design: #149 — Player Character — CharacterBody3D + Controller

> Parent Issue: #149
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

The PlayerController (created in #142) has full GDScript logic for WASD movement, mouse look, and E-key interaction, but **cannot function at runtime** because calling `PlayerControllerScript.new()` only creates a bare `CharacterBody3D` with no child nodes. The `@onready` references (`$Head`, `$Head/Camera3D`, `$InteractionArea`) produce `null` values, causing crashes. This issue adds programmatic node-tree construction and a collision shape to `_ready()`, making the player character physically functional.

### Data Flow

```
SceneBase._ready()
    │
    ├── _instantiate_player()
    │       └── PLAYER_CONTROLLER.new()       # Bare CharacterBody3D + script
    │           └── _ready():
    │               ├── _build_node_tree()      [NEW] Creates Head, Camera3D, InteractionArea
    │               ├── _build_collision_shape() [NEW] Creates CapsuleShape3D
    │               ├── Reassign @onready vars   [NEW] After node tree is built
    │               ├── camera.current = true
    │               ├── add_to_group("player")
    │               └── _disable_other_cameras() # Sets main.tscn Camera3D to current=false
    │
    ├── _physics_process(delta):
    │       ├── WASD → Input.get_vector()
    │       ├── velocity = direction * walk_speed
    │       └── move_and_slide()                # Now resolves against CapsuleShape3D 🔄
    │
    └── _save_player_state() on scene unload
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Node tree creation | Programmatic in `_ready()` (Approach A) | Zero ripple effects — same `.new()` API, tests unaffected. Adding a `.tscn` file would break `PLAYER_CONTROLLER.new()` across 4+ call sites. |
| Guard pattern | `if not has_node("X"): create` | Backward compatible with tests that manually pre-create child nodes before `_ready()` |
| Collision shape | CapsuleShape3D (r=0.3, h=1.4) | Standard player collision shape for 3D FPS/TPS; centered at y=0.7 (half height) to sit on ground. |
| Camera conflict resolution | `_disable_other_cameras()` in `_ready()` | Already implemented in #142 — loops `get_nodes_in_group("Cameras")` and sets non-player cameras to `current=false` |
| main.tscn Camera3D | Set `current=false` | Already planned in #142 DESIGN doc; now explicitly applied. |

---

## 2. Modified Files

### `gdscripts/player_controller.gd` — Add Node Tree & Collision Builder

**Change: Add `_build_node_tree()` and `_build_collision_shape()`, update `_ready()`**

The current `_ready()` assumes `$Head`, `$Head/Camera3D`, and `$InteractionArea` exist as child nodes. Since `new()` creates a bare body, these `@onready` vars resolve to `null`. The fix adds guard-based node creation in `_ready()`, called *before* the existing logic:

```gdscript
func _build_node_tree() -> void:
    # Build Head node (pitch rotation mount for camera)
    if not has_node("Head"):
        var head_node := Node3D.new()
        head_node.name = "Head"
        add_child(head_node)
        head_node.owner = self

    # Build Camera3D child of Head
    if not has_node("Head/Camera3D"):
        var cam := Camera3D.new()
        cam.name = "Camera3D"
        cam.position = Vector3(0, camera_height, 0)
        cam.current = true
        $Head.add_child(cam)
        cam.owner = $Head

    # Build InteractionArea (proximity trigger for E-key)
    if not has_node("InteractionArea"):
        var area := Area3D.new()
        area.name = "InteractionArea"
        var shape := CollisionShape3D.new()
        shape.name = "CollisionShape3D"
        var sphere := SphereShape3D.new()
        sphere.radius = interaction_range
        shape.shape = sphere
        area.add_child(shape)
        shape.owner = area
        add_child(area)
        area.owner = self

    # Build FallReset area (detects player falling off world)
    if not has_node("FallReset"):
        var fall := Area3D.new()
        fall.name = "FallReset"
        var fall_shape := CollisionShape3D.new()
        fall_shape.name = "CollisionShape3D"
        var box := BoxShape3D.new()
        box.size = Vector3(1000, 0.5, 1000)  # Huge floor sensor
        fall_shape.shape = box
        fall_shape.position = Vector3(0, -100, 0)  # Below all walkable surfaces
        fall.add_child(fall_shape)
        fall_shape.owner = fall
        add_child(fall)
        fall.owner = self
        fall.body_entered.connect(_on_fall_detector_body_entered)


func _build_collision_shape() -> void:
    # Build CapsuleShape3D on the root CharacterBody3D
    if not has_node("PlayerCollisionShape"):
        var shape := CollisionShape3D.new()
        shape.name = "PlayerCollisionShape"
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.3
        capsule.height = 1.4
        shape.shape = capsule
        shape.position = Vector3(0, 0.7, 0)  # Half-height offset
        add_child(shape)
        shape.owner = self
```

**Modified `_ready()`:**

```gdscript
func _ready() -> void:
    # Build node tree before accessing @onready vars
    _build_node_tree()
    _build_collision_shape()

    # Reassign @onready vars since they were set to null before nodes existed
    head = $Head
    camera = $Head/Camera3D
    interaction_area = $InteractionArea

    add_to_group("player")
    camera.current = true
    head.rotation.x = camera_tilt  # slight downward tilt

    # Interaction area setup
    if interaction_area:
        interaction_area.body_entered.connect(_on_interaction_body_entered)
        interaction_area.body_exited.connect(_on_interaction_body_exited)

    # Set camera current and disable other cameras
    _disable_other_cameras()

    # Connect to dialogue runner for mode changes
    _connect_dialogue_signals()
```

**Est. change:** +75 lines (new functions + _ready() modification)

### `scenes/main.tscn` — Camera3D current = false

**Change:** Set the existing Camera3D node's `current = false` to prevent camera conflict with PlayerController's camera.

The #142 DESIGN doc planned this change but it was not fully applied. This is a one-line property change.

**Est. change:** 1 line

---

## 3. Existing Infrastructure (No Changes Needed)

The following are already complete from #142 and require no modifications for #149:

| Component | Status |
|-----------|--------|
| PlayerController GDScript logic (WASD, mouse look, E-key, dialogue blocking) | ✅ Complete |
| Input Map actions (`move_forward/backward/left/right/interact`) | ✅ Complete |
| SceneBase._instantiate_player() hook | ✅ Complete |
| SceneBase._save_player_state() on exit | ✅ Complete |
| GameManager player vars (`player_position/rotation/head_rotation`) | ✅ Complete |
| NPCNode proximity detection (`is_in_group("player")`) | ✅ Complete |
| Existing unit + integration tests (34 unit, 6 integration) | ✅ Complete |

---

## 4. Test Layer

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Node tree building (Head, Camera, InteractionArea) | ✅ ≥3 | ✅ ≥3 | ✅ ≥2 |
| Collision shape creation | ✅ ≥1 | ✅ ≥2 | ✅ ≥1 |
| @onready reassignment after build | ✅ ≥1 | ✅ ≥1 | — |
| Cap/main.tscn camera conflict resolution | ✅ ≥1 | ✅ ≥1 | — |
| FallReset area creation and wiring | ✅ ≥1 | ✅ ≥2 | ✅ ≥1 |
| Guard pattern (already-has-node) | ✅ ≥1 | ✅ ≥2 | — |
| Test helper backward compat | — | ✅ ≥1 | ✅ ≥1 |

### Test Case Tables

#### Normal Path (PC-N) — Node Tree Building

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| PC-N-1-1 | `_build_node_tree()` creates Head | Create bare PlayerController, call `_build_node_tree()` | `$Head` exists and is a Node3D | `_assert(node.has_node("Head"))` |
| PC-N-1-2 | `_build_node_tree()` creates Camera3D | After PC-N-1-1 | `$Head/Camera3D` exists and is a Camera3D | `_assert($Head/Camera3D is Camera3D)` |
| PC-N-1-3 | `_build_node_tree()` creates InteractionArea | After PC-N-1-1 | `$InteractionArea` exists, has CollisionShape3D child with SphereShape3D | `_assert($InteractionArea.get_child(0).shape is SphereShape3D)` |
| PC-N-1-4 | Camera height set correctly | After PC-N-1-1 | Camera3D.position.y == camera_height (1.6) | `_assert(abs(camera.position.y - 1.6) < 0.01)` |
| PC-N-2-1 | `_build_collision_shape()` creates shape | Create bare PlayerController, call `_build_collision_shape()` | `$PlayerCollisionShape` exists with CapsuleShape3D | `_assert($PlayerCollisionShape.shape is CapsuleShape3D)` |
| PC-N-2-2 | Capsule dimensions match exports | After PC-N-2-1 | radius=0.3, height=1.4 | `_assert(capsule.radius == 0.3 && capsule.height == 1.4)` |
| PC-N-2-3 | Collision shape position offset | After PC-N-2-1 | position.y == 0.7 | `_assert(abs(shape.position.y - 0.7) < 0.01)` |
| PC-N-3-1 | `_ready()` calls both builders | `PlayerControllerScript.new()` → `_ready()` | Head, Camera3D, InteractionArea, PlayerCollisionShape all exist | All `has_node` checks pass |
| PC-N-3-2 | Camera is current after _ready | After PC-N-3-1 | Camera3D.current == true | `_assert(camera.current == true)` |
| PC-N-4-1 | FallReset area created | `_build_node_tree()` | `$FallReset` exists with BoxShape3D | `_assert($FallReset.get_child(0).shape is BoxShape3D)` |
| PC-N-4-2 | FallReset body_entered connected | After PC-N-4-1 | `body_entered` signal connected to `_on_fall_detector_body_entered` | `_assert($FallReset.body_entered.is_connected(callable))` |

#### Edge Cases (PC-E)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| PC-E-1-1 | Guard: Head already exists | Pre-create Head, call `_build_node_tree()` | No duplicate Head created, no error | `_assert($Head.get_child_count() == 1)` (Camera3D only) |
| PC-E-1-2 | Guard: InteractionArea already exists | Pre-create InteractionArea, call `_build_node_tree()` | No duplicate, no error | `_assert($InteractionArea.get_child(0).name == "CollisionShape3D")` |
| PC-E-1-3 | Guard: Camera already exists | Pre-create Camera3D under Head, call `_build_node_tree()` | Camera position preserved, no overwrite | `_assert(camera.position == original_position)` |
| PC-E-1-4 | Guard: CollisionShape already exists | Pre-create PlayerCollisionShape, call `_build_collision_shape()` | No duplicate, no error | `_assert($PlayerCollisionShape.shape is CapsuleShape3D)` |
| PC-E-2-1 | `_ready()` called twice | Create PC, call `_ready()`, call `_ready()` again | No duplicate nodes, no crash | Child count unchanged between first and second call |
| PC-E-2-2 | @onready reassignment after second _ready | After PC-E-2-1 | head, camera, interaction_area all reference valid nodes | All three non-null |

#### Failure Paths (PC-F)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| PC-F-1-1 | _build_node_tree with no Node3D | Call on stripped object | Graceful return, no crash | Catch any errors |
| PC-F-1-2 | CameraHeight set to 0 or negative | Set `camera_height = 0`, call _ready | Camera at y=0, no crash | `_assert(camera.position.y == 0)` |
| PC-F-2-1 | FallReset collision with self | PlayerController falls, FallReset detects | Position reset to fall_reset_position | `_assert(global_position == Vector3.ZERO)` |
| PC-F-3-1 | Test helper backward compat | `_make_pc()` pre-creates children, then _ready() called | Guard pattern skips creation, no crash | Test passes as before |

### Integration Tests (PC-INT)

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| INT-N-1-1 | Scene loads with working PlayerController | Create SceneBase inheritor, call _ready() | PlayerController has collision shape and all nodes | `_assert(pc.$PlayerCollisionShape != null)` |
| INT-N-1-2 | PlayerController collides with wall | Place PC next to StaticBody3D, move forward for 2 seconds | Player stops at wall, does not clip through | `_assert(abs(player.global_position.x - wall_position.x) < 0.5)` |
| INT-N-1-3 | Camera remains current after scene load | Scene loads with PC | Only PC's camera is current, main.tscn camera is not | `_assert(pc.camera.current == true)` |

---

## 5. Files Changed

| Layer | File | Change | Est. Lines |
|-------|------|--------|-----------|
| GDScript | `gdscripts/player_controller.gd` | **Modify:** Add `_build_node_tree()`, `_build_collision_shape()`, update `_ready()` | +75 |
| Scene | `scenes/main.tscn` | **Modify:** Set Camera3D `current=false` | ±1 |
| Test | `tests/unit/test_player_controller.gd` | **Modify:** Add tests for node tree building and collision shape | +50 |

---

## 6. Verification Checklist

- [ ] `PlayerControllerScript.new()` → `_ready()` builds complete node tree: Head, Camera3D, InteractionArea, FallReset, PlayerCollisionShape
- [ ] CapsuleShape3D exists on root with radius=0.3, height=1.4, position.y=0.7
- [ ] `move_and_slide()` resolves against StaticBody3D walls (no clipping)
- [ ] main.tscn Camera3D has `current=false`, PlayerController camera is `current=true`
- [ ] FallReset area detects player fall and resets position
- [ ] Guard pattern: pre-existing child nodes are not duplicated
- [ ] `_ready()` can be called multiple times without side effects
- [ ] All existing unit tests (34) still pass with zero changes
- [ ] All existing integration tests (6) still pass

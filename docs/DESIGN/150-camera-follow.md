# Design: #150 — Camera Follow — Player-relative Perspective

> Parent Issue: #150
> Agent: plan-agent
> Date: 2026-07-24

---

## 1. Architecture Overview

### Core Idea

Replace the current **first-person** camera setup (Camera3D as child of `Head` at `(0, 1.6, 0)`) with a **third-person shoulder-cam** using Godot 4's `SpringArm3D` node. The camera orbits around the player character on mouse input, auto-shortens when obstructed by walls, and always frames the player character in view.

### Current Camera Hierarchy

```
PlayerController (CharacterBody3D)
    ├── Head (Node3D)              ← pitch rotation (mouse vertical)
    │   └── Camera3D               ← position (0, camera_height, 0), tilt -5°
    ├── PlayerCollisionShape       ← CapsuleShape3D
    ├── InteractionArea (Area3D)
    └── FallReset (Area3D)
```

### Proposed Camera Hierarchy

```
PlayerController (CharacterBody3D)
    ├── Head (Node3D)              ← optional — kept for backward compat but no longer drives camera
    ├── CameraPivot (Node3D)       ← [NEW] orbit yaw rotation node
    │   └── SpringArm3D            ← [NEW] collision-aware arm, length 4.0m, margin 0.3m
    │       └── Camera3D           ← position (0, 2.0, 0) relative to SpringArm end
    ├── PlayerCollisionShape       ← CapsuleShape3D
    ├── PlayerVisual (MeshInstance3D)  ← [NEW] placeholder capsule mesh for the camera to frame
    ├── InteractionArea (Area3D)
    └── FallReset (Area3D)
```

### Data Flow

```
Input (mouse drag horizontal)
    → rotate CameraPivot.y (orbit yaw)
    → SpringArm3D automatically repositions Camera3D at new orbit angle
    → SpringArm3D raycasts from origin to target; if obstructed, shortens arm
    → Camera3D always looks at player chest height (y = 1.0)

Input (mouse drag vertical)
    → rotate SpringArm3D.x (orbit pitch, clamped -30° to +45°)
    → SpringArm3D auto-handles collision shortening in new vertical position
```

**Movement relative to camera (WASD):**
```
Input direction is computed from CameraPivot's basis, not Head's basis:
    forward = -CameraPivot.global_transform.basis.z (projected to XZ)
    right   =  CameraPivot.global_transform.basis.x (projected to XZ)
```

### SpringArm3D Collision Resolution

```
SpringArm3D origin = CameraPivot position (at player center)
SpringArm3D length = 4.0m (default shoulder offset)
RayCast from origin toward Camera3D at full extension:
    ├── If clear: Camera3D at full length → Vector3(0, 2.0, 4.0) behind player
    ├── If obstructed: SpringArm3D auto-shortens to hit point minus 0.3m margin
    └── If fully blocked (arm < 0.5m): Camera at near-player position (acceptable degraded mode)
```

---

## 2. Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Camera collision | SpringArm3D (Godot built-in) | Zero collision math, auto-raycast, built-in smoothing. Godot 4.7.1 supports it natively. |
| Orbit node | Separate `CameraPivot` Node3D | Keeps orbit yaw independent of body rotation. Player can orbit camera without turning the character. |
| Player visual | Capsule MeshInstance3D (placeholder) | Third-person camera needs something to frame. Simple emissive capsule, replaced later with proper character model. |
| WASD direction basis | CameraPivot (not Head) | Movement relative to camera view is standard third-person convention. Head basis would point up/down with pitch. |
| Camera mode config | `@export var camera_mode: String = "third_person"` | Backward compat with first-person. Scenes like tight corridors may prefer first-person. |
| Dialogue mode camera | Keep third-person, allow mouse look | No change — dialogue mode already blocks WASD. Mouse can still orbit during dialogue. |
| Orbit persistence | Store in GameManager | Camera yaw/pitch saved on scene unload, restored on load. Prevents disorienting camera reset. |
| SpringArm3D creation | Programmatic in `_build_node_tree()` | Matches existing pattern from #149. No .tscn file needed — `.new()` API works everywhere. |
| Vertical clamp | -30° to +45° (orbit_pitch) | Prevents camera going underground or flipping overhead. Clamp applied to SpringArm3D.rotation.x. |

### SpringArm3D Availability

Godot 4.7.1 includes `SpringArm3D` as a stable node. No fallback needed. Confirmed by `game-env/manifest.yaml` (`godot` engine, version `4.7.1`).

---

## 3. Modified Files

### `gdscripts/player_controller.gd` — Camera Restructure

**Change: Add `CameraPivot` and `SpringArm3D`, move Camera3D under SpringArm3D, update mouse look to orbit instead of body yaw**

New node references:
```gdscript
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
# camera is now $CameraPivot/SpringArm3D/Camera3D
```

New exports:
```gdscript
@export var camera_mode: String = "third_person":           # "third_person" or "first_person"
@export var spring_arm_length: float = 4.0                   # max shoulder offset
@export var orbit_sensitivity: float = 0.003                 # radians per pixel (matches current)
@export_range(-1.0, 0.0, 0.01) var orbit_pitch_min: float = -0.523  # -30°
@export_range(0.0, 1.0, 0.01) var orbit_pitch_max: float = 0.785    # +45°
```

New state:
```gdscript
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = -0.2  # slight downward default
```

New `_build_camera_system()` in `_ready()`:
```gdscript
func _build_camera_system() -> void:
    # Build CameraPivot (orbit yaw mount)
    if not has_node("CameraPivot"):
        var pivot := Node3D.new()
        pivot.name = "CameraPivot"
        add_child(pivot)
        pivot.owner = self

    # Build SpringArm3D
    if not has_node("CameraPivot/SpringArm3D"):
        var arm := SpringArm3D.new()
        arm.name = "SpringArm3D"
        arm.spring_length = spring_arm_length
        arm.margin = 0.3  # collision margin from wall surface
        arm.add_excluded_object(self)  # don't collide with player body
        # Mask: only collide with scene geometry layer (layer 2)
        arm.collision_mask = 0b100  # layer 3 → mask bit 2
        $CameraPivot.add_child(arm)
        arm.owner = $CameraPivot

    # Move existing Camera3D under SpringArm3D
    if not has_node("CameraPivot/SpringArm3D/Camera3D"):
        if camera and camera.get_parent():
            camera.reparent($CameraPivot/SpringArm3D)
        else:
            # Create new Camera3D if none exists
            var cam := Camera3D.new()
            cam.name = "Camera3D"
            cam.position = Vector3(0, 2.0, 0)  # 2m above pivot
            cam.current = true
            $CameraPivot/SpringArm3D.add_child(cam)
            cam.owner = $CameraPivot/SpringArm3D
            camera = cam
```

Modified `_handle_mouse_look()` — orbit mode:
```gdscript
func _handle_mouse_look(delta: Vector2) -> void:
    if camera_mode == "first_person":
        # Keep original first-person behavior
        rotate_y(-delta.x * look_sensitivity)
        if head:
            head.rotation.x = clamp(
                head.rotation.x + (-delta.y * look_sensitivity),
                -look_vertical_clamp + camera_tilt,
                look_vertical_clamp + camera_tilt
            )
        return

    # Third-person orbit
    _orbit_yaw -= delta.x * orbit_sensitivity
    _orbit_pitch -= delta.y * orbit_sensitivity
    _orbit_pitch = clamp(_orbit_pitch, orbit_pitch_min, orbit_pitch_max)
    camera_pivot.rotation.y = _orbit_yaw
    spring_arm.rotation.x = _orbit_pitch
```

Modified WASD direction in `_physics_process()` — use CameraPivot basis:
```gdscript
# For third-person, use CameraPivot basis (not Head)
var look_basis: Basis
if camera_mode == "third_person" and camera_pivot:
    look_basis = camera_pivot.global_transform.basis
else:
    look_basis = head.global_transform.basis  # first-person uses Head

var forward := -look_basis.z
forward.y = 0.0
forward = forward.normalized()
var right := look_basis.x
right.y = 0.0
right = right.normalized()
```

### `gdscripts/player_controller.gd` — Add Placeholder Player Mesh

**Change: Add `_build_player_visual()` that creates a capsule MeshInstance3D**

```gdscript
func _build_player_visual() -> void:
    if not has_node("PlayerVisual"):
        var mesh := MeshInstance3D.new()
        mesh.name = "PlayerVisual"
        var capsule := CapsuleMesh.new()
        capsule.radius = 0.3
        capsule.height = 1.4
        mesh.mesh = capsule
        # Emissive material so player is visible in low-light scenes
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(0.3, 0.6, 1.0)  # soft blue
        mat.emission_enabled = true
        mat.emission = Color(0.1, 0.2, 0.4)
        mesh.material_override = mat
        mesh.position = Vector3(0, 0.7, 0)  # same as collision shape
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        add_child(mesh)
        mesh.owner = self
```

### `gdscripts/game_manager.gd` — Orbit State Persistence

**Change: Add camera orbit fields for scene transition persistence**

```gdscript
# Add to GameManager:
var camera_orbit_yaw: float = 0.0
var camera_orbit_pitch: float = -0.2

# On scene unload (in _save_player_state):
player_state["camera_orbit_yaw"] = _orbit_yaw
player_state["camera_orbit_pitch"] = _orbit_pitch

# On scene load (in _restore_player_state):
if "camera_orbit_yaw" in player_state:
    _orbit_yaw = player_state["camera_orbit_yaw"]
    _orbit_pitch = player_state["camera_orbit_pitch"]
```

### `docs/GAME_DESIGN/08-PLAYER-CONTROLLER.md` — Update Camera Section

**Change: Rewrite camera section to describe third-person hierarchy**

Replace the first-person camera description with the new third-person hierarchy. Document the orbit controls, SpringArm3D collision behavior, and camera_mode export for switching between first/third person.

---

## 4. Test Case Descriptions

These test cases describe the expected behavior. The implement agent will create actual GDScript test files.

### Unit Tests

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-CAM-N-1 | Default third-person camera position | Instantiate PlayerController with `camera_mode="third_person"` | CameraPivot exists as child of PlayerController. SpringArm3D exists as child of CameraPivot. Camera3D exists as child of SpringArm3D. Camera position is Vector3(0, 2.0, 0) relative to SpringArm3D. |
| TC-CAM-N-2 | Camera follows player movement | Move player forward 5m | Camera3D.global_position changes by the same translation. Camera remains at shoulder offset behind player. |
| TC-CAM-N-3 | Mouse horizontal orbit | Simulate mouse drag 100px right | `_orbit_yaw` decreases by `100 * orbit_sensitivity`. CameraPivot.rotation.y equals new `_orbit_yaw`. |
| TC-CAM-N-4 | Mouse vertical orbit clamped | Simulate mouse drag 500px up then 500px down | `_orbit_pitch` does not exceed `orbit_pitch_max` (+45°). `_orbit_pitch` does not go below `orbit_pitch_min` (-30°). |
| TC-CAM-N-5 | First-person fallback mode | Set `camera_mode="first_person"` | Camera behaves as original: Camera3D at Head position (0, 1.6, 0), mouse look rotates body yaw + head pitch. |
| TC-CAM-N-6 | SpringArm3D collision shortening | Place wall 2m behind player | SpringArm3D.spring_length is reduced to ~2.0 - margin. Camera3D does not clip through wall. |
| TC-CAM-N-7 | SpringArm3D extends after obstruction removed | Remove wall | SpringArm3D.spring_length returns to 4.0m over smoothing frames. |
| TC-CAM-N-8 | Player visual mesh exists | Instantiate PlayerController | `$PlayerVisual` is a MeshInstance3D with CapsuleMesh. Material has emission enabled. Position at Vector3(0, 0.7, 0). |
| TC-CAM-E-1 | Camera minimum length in tight corner | Place walls on three sides at 0.5m from player | SpringArm3D shortens to near-minimum. Camera does not clip through walls. No error from look_at() at zero distance. |
| TC-CAM-E-2 | Rapid mouse orbit 360° | Simulate fast full-circle drag | Camera orbits smoothly. No snapping or disorienting jumps. Per-frame rotation clamp prevents >5° per tick. |
| TC-CAM-E-3 | Dialogue mode keeps camera position | Trigger dialogue while orbiting at 90° yaw | Camera stays at 90° orbit. Mouse look may be blocked or allowed per dialogue mode setting. |
| TC-CAM-E-4 | Scene transition preserves orbit | Save then load scene | `_orbit_yaw` and `_orbit_pitch` are saved to GameManager.player_state and restored on next scene load. |
| TC-CAM-E-5 | SpringArm3D excluded object | Check `add_excluded_object(self)` | PlayerController body does not trigger SpringArm3D collision shortening. Only scene geometry triggers it. |

---

## 5. Dependencies & Sequencing

| Dependency | Issue # | Status | Required For |
|------------|---------|--------|-------------|
| Player Character (CharacterBody3D) | #149 | ✅ Merged | PlayerController with collision shape for camera to anchor to |
| Player Controller (first-person) | #142 | ✅ Merged | Movement, input, interaction foundation |
| Scene Transition System | #156 | ✅ Merged | GameManager player_state persistence for orbit yaw/pitch |

### Implementation Order

1. Add `CameraPivot` + `SpringArm3D` + move `Camera3D` under SpringArm3D in `_build_node_tree()`
2. Add `PlayerVisual` capsule mesh in `_build_player_visual()`
3. Modify `_handle_mouse_look()` for orbit mode
4. Modify `_physics_process()` WASD basis to use CameraPivot for third-person
5. Add camera_mode export with first-person fallback
6. Add orbit yaw/pitch persistence in GameManager
7. Update `docs/GAME_DESIGN/08-PLAYER-CONTROLLER.md`

---

## 6. Boundary Conditions

### SpringArm3D Collision Layers

| Layer | Object | Purpose |
|-------|--------|---------|
| Layer 1 | Player body | - (SpringArm3D adds player as excluded object) |
| Layer 2 | Scene geometry | Walls, floors, ceilings — SpringArm3D mask bit 1 |
| Layer 3 | Camera collision ray | SpringArm3D raycast mask bit 2 — hits layer 2 |

### Parameters

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `spring_arm_length` | 4.0 | 1.0-10.0 | Maximum shoulder offset in meters |
| `spring_arm_margin` | 0.3 | 0.1-1.0 | Collision margin from wall surface |
| `orbit_sensitivity` | 0.003 | 0.001-0.02 | Radians per pixel (same as look_sensitivity) |
| `orbit_pitch_min` | -0.523 (-30°) | -1.0-0.0 | Minimum vertical angle |
| `orbit_pitch_max` | 0.785 (+45°) | 0.0-1.57 | Maximum vertical angle |
| `camera_height` | 2.0 | 0.5-3.0 | Camera Y offset relative to SpringArm3D origin |
| `camera_mode` | "third_person" | ["third_person", "first_person"] | Camera behavior mode |

### Failure Modes

| Failure | Detection | Mitigation |
|---------|-----------|------------|
| SpringArm3D not available (pre-4.2 Godot) | `@onready var spring_arm: SpringArm3D` returns null | Fall back to first-person mode. Log clear error. |
| `look_at()` zero distance | Camera position == player position (arm fully compressed) | Clamp `camera.global_position` to be at least 0.1m from player center. |
| Camera clips through floor on slope | SpringArm3D origin at player center, arm extending upward on slope | Add downward RayCast3D from camera position to check floor proximity; push camera up if below floor. |
| Orbit state not restored on scene transition | `camera_orbit_yaw` not saved to GameManager | Verify persistence in integration test TC-CAM-E-4. |

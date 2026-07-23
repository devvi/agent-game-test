# Research: Camera Follow — Player-relative Perspective

> Parent Issue: #150
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The PlayerController (implemented in #142) uses a **first-person** camera setup. Camera3D is a child of the Head node at position `(0, 1.6, 0)` — the player's eye level. While this works for basic orientation, it does not match the game's third-person narrative framing:

- **Camera is at eye level:** The camera sits at the player's head height, making the game a first-person experience
- **No player model visible:** The player does not see their own character, which conflicts with the atmospheric "walk through a rainy city at night" visual premise
- **Mouse look rotates the world:** Yaw rotates the entire CharacterBody3D, pitch rotates just the Head node — the player sees no character in front of them
- **Scene compositions assume third-person framing:** The existing static camera positions in scenes were placed at `(0, 2, 5)` — behind-looking-over-shoulder — which suggests an original intent for third-person perspective

The current camera hierarchy:
```
PlayerController (CharacterBody3D)
    └── Head (Node3D)         ← pitch rotation node
        └── Camera3D          ← current=true, position (0, 1.6, 0), tilt -5°
```

### Expected Behavior

The issue requests a **third-person shoulder-cam perspective**:

- Camera is positioned **behind and above** the player character, at an offset like `Vector3(0, 2, 4)` — looking at the player from over-the-shoulder
- Camera is a **child of the Player node** so it follows automatically as the player moves
- **Mouse horizontal movement** rotates the camera around the player (orbit, not yaw body)
- Camera does **not clip through floors or objects**
- The player character model is visible in the frame

### User Scenarios

- **Scenario A (Default Walking):** Player presses W to walk forward. Camera follows from behind at shoulder height. Player character is visible walking below.
- **Scenario B (Orbit Look):** Player drags mouse horizontally. Camera orbits around the player character. Player drags mouse vertically. Camera tilts up/down, still aimed at the player.
- **Scenario C (Tight Spaces):** Player walks into a narrow corridor. Camera auto-adjusts or collides with geometry to avoid clipping through walls.
- **Frequency:** Every frame during gameplay. This is the primary visual framing for the entire game.

---

## 2. Root Cause Analysis / Design Intent

### Why Does Current Behavior Exist?

The PlayerController from #142 was built as a **first-person** controller because:

1. **First-person was the simplest path to implement WASD + mouse look.** No need to handle camera collision, orbit math, or player model visibility.
2. **The #142 PRD explicitly recommended first-person:** Section 4 (Recommendation, item 2) states: *"First-person, not third-person: The camera should be at eye level (~1.6m), not the current (0, 2, 5). The player IS the camera — no avatar rendering needed."*
3. **The game's lo-fi aesthetic** (text-only 3D, no character models) made a first-person view the natural default — no visible character to break immersion.
4. **No player character model exists.** Even #149 (the prerequisite) only provides a capsule collider, not a visual mesh. A third-person camera requires some visual representation of the player character.

### Why Change Now?

1. **The original static cameras** in all scenes (office, street, lobby) were positioned at third-person framing `(0, 2, 5)` — suggesting the original creative vision was third-person.
2. **Atmospheric CRPGs** (like Disco Elysium, Kentucky Route Zero) use third-person views to ground the player in the space and emphasize the character's physical presence in the environment.
3. **Mouse-look orbit** creates a more natural exploration feel — the player character stays centered while the world rotates around them, reinforcing the narrative focus on the character's perspective.
4. **Future features** (character animation, clothing/state visual feedback, player reflection in water/mirrors) require a visible player character that a third-person camera can frame.

### Previous Constraints

- **No player model exists:** The game has only Label3D text and CSG geometry. A third-person camera looking at an invisible capsule would look broken. A minimal visual player representation is needed.
- **Collision culling:** Third-person cameras clip through walls. A camera collision system (RayCast3D or ShapeCast3D) is required.
- **#149's physical body:** The capsule collider from #149 provides the physical presence, but no visual. The camera will orbit around an invisible capsule unless a placeholder mesh is added.
- **#142's input model:** Mouse look currently rotates the player body (yaw) + head (pitch). Third-person orbit requires camera rotation independent of body rotation.

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/player_controller.gd` | PlayerController | **Major** — Camera becomes child of PlayerController directly (not Head). Camera position set to shoulder offset `(0, 2, 4)` instead of eye level `(0, 1.6, 0)`. Mouse look becomes camera orbit instead of body yaw + head pitch. Add camera collision detection. |
| `gdscripts/player_controller.gd` | Camera Follow | **Add** — `_physics_process` spring-arm or RayCast3D logic to keep camera at shoulder offset, resolving against world geometry to prevent clipping. |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/scene_base.gd` | SceneBase | Spawn position may need offset adjustment for third-person framing. |
| `gdscripts/e_key_trigger.gd` | EKeyTrigger | Interaction detection still works (Area3D on PlayerController body), but camera orbit may affect player orientation for direction-based interactions. |
| `docs/GAME_DESIGN/08-PLAYER-CONTROLLER.md` | Design Doc | Must be updated to reflect third-person camera structure instead of first-person. |
| `docs/DESIGN/142-player-controller.md` | Design Doc | Camera section must be rewritten. |
| `docs/DESIGN/142-player-controller-test-spec.md` | Test Spec | Tests for camera position, mouse look, and vertical clamp change significantly. |
| `tests/unit/test_player_controller.gd` | Unit Tests | Tests for camera_current, mouse look (yaw/pitch), head rotation need updating. |
| `tests/integration/test_player_in_scene.gd` | Integration Tests | Camera position validation, rotation persistence tests affected. |

### Data Flow Impact

**Current (first-person) flow:**
```
Input (mouse drag)
  → rotate_y(delta.x * sensitivity)  [body yaw]
  → head.rotation.x += delta.y       [head pitch]
  → Camera3D at head position (0, 1.6, 0) moves with head
```

**Proposed (third-person orbit) flow:**
```
Input (mouse drag)
  → Camera orbits around player via rotation of SpringArm/Pivot node
  → Camera position = pivot position + shoulder offset, rotated by orbit angle
  → RayCast3D from player to camera: if obstructed, lerp camera closer
  → Player body yaw optionally follows camera yaw (or independent)
```

**Camera collision resolution:**
```
Camera target position = shoulder_offset rotated by orbit angles
RayCast3D from player center to camera target
if ray hits wall:
    Camera shortens to hit point minus margin
else:
    Camera at full shoulder offset
```

### Documents to Update

- [x] `docs/PRD/150-camera-follow.md` — This document
- [ ] `docs/GAME_DESIGN/08-PLAYER-CONTROLLER.md` — Rewrite camera section for third-person
- [ ] `docs/DESIGN/142-player-controller.md` — Update camera hierarchy and orbit logic
- [ ] `docs/DESIGN/142-player-controller-test-spec.md` — Update camera-related test cases

---

## 4. Solution Comparison

### Approach A: SpringArm3D (Godot Built-in)

**Description:** Use Godot 4's built-in `SpringArm3D` node as the camera mount. SpringArm3D automatically handles collision detection by raycasting from its origin toward its child (the Camera3D) and shortening when obstructed. The camera is attached as a child of the SpringArm3D, which is itself a child of the PlayerController but NOT of the Head node.

**Node hierarchy:**
```
PlayerController (CharacterBody3D)
    ├── CollisionShape3D (CapsuleShape3D)
    ├── Head (Node3D)                 ← optional, for independent pitch if needed
    ├── CameraPivot (Node3D)          ← orbit yaw rotation node
    │   └── SpringArm3D               ← collision-aware arm, length = 4.0
    │       └── Camera3D              ← position (0, 2.0, 0) relative to SpringArm
    ├── InteractionArea (Area3D)
    └── FallReset (Area3D)
```

**Camera movement logic:**
```gdscript
# Mouse horizontal → rotate CameraPivot (orbit yaw)
# Mouse vertical → rotate SpringArm3D (orbit pitch)
# SpringArm3D auto-handles collision shortening
```

**Pros:**
- **Zero collision math** — SpringArm3D handles wall clipping detection natively
- **Built-in spring smoothing** — configurable damping for smooth camera movement
- **Godot 4 native** — no custom raycast code needed, well-documented
- **Simple hierarchy** — just reparent the Camera3D under a SpringArm3D
- **Configurable arm length** — can be adjusted per-scene or via export

**Cons:**
- **SpringArm3D may not exist in all Godot 4.x builds** (was experimental in early 4.0, stable in 4.2+)
- **Limited customization** — spring behavior is built-in, hard to override for specific edge cases
- **No pitch independent of yaw** — single SpringArm3D rotates as a unit
- **No player-facing behavior** — camera always looks in SpringArm3D's -Z, not necessarily at the player

**Risk:** Low-Medium. SpringArm3D is the recommended Godot 4 way to do third-person cameras. If unavailable (older Godot version), fall back to Approach B. The project's Godot version needs confirmation.

**Effort:** Low (~1-2 hours for integration)

### Approach B: Custom RayCast3D Camera Arm

**Description:** Implement a custom camera system using a RayCast3D from the player character toward the target camera position. When the ray hits geometry, the camera is shortened to the collision point minus a buffer. The orbit is achieved by rotating a CameraPivot Node3D child of the PlayerController.

**Node hierarchy:**
```
PlayerController (CharacterBody3D)
    ├── CollisionShape3D (CapsuleShape3D)
    ├── CameraPivot (Node3D)          ← orbit yaw rotation node
    │   └── CameraArm (Node3D)        ← offset from pivot, orbit pitch rotation
    │       └── Camera3D              ← visual camera
    ├── CameraCollision (RayCast3D)   ← from player center to camera target
    ├── InteractionArea (Area3D)
    └── FallReset (Area3D)
```

**Camera movement logic:**
```gdscript
# _physics_process:
var orbit_yaw: float   # mouse horizontal → changes this
var orbit_pitch: float # mouse vertical → changes this (clamped)

CameraPivot.rotation.y = orbit_yaw
CameraArm.rotation.x = orbit_pitch

# Target camera position relative to pivot:
var target_offset: Vector3 = Vector3(0, 2.0, 4.0)
target_offset = CameraPivot.transform.basis * target_offset

# Collision check:
CameraCollision.target_position = target_offset
CameraCollision.force_raycast_update()
if CameraCollision.is_colliding():
    var hit_point: Vector3 = CameraCollision.get_collision_point()
    var adjusted_pos = to_local(hit_point) - Vector3(0, 0, 0.3)  # margin
    camera.global_position = CameraPivot.global_position + CameraCollision.transform.basis * adjusted_pos
else:
    camera.global_position = CameraPivot.global_position + target_offset

# Camera always looks at player:
camera.look_at(global_position + Vector3(0, 1.0, 0))  # look at player chest
```

**Pros:**
- **Full control** — every aspect of camera behavior is customizable
- **No Godot version dependency** — works in any Godot 4.x
- **Precise collision resolution** — can fine-tune lerp speed, margin, smoothing
- **Independent yaw/pitch** — easy to add features like auto-orbit, wall push, camera pop prevention
- **Camera always faces player** — `look_at()` ensures the player character stays in frame

**Cons:**
- **More code to write and maintain** — collision detection, smoothing, orbit all custom
- **Edge case responsibility** — every edge case (camera pops through thin walls, sudden obstruction) must be handled manually
- **More complex debugging** — no built-in gizmo support like SpringArm3D
- **Smoothing is manual** — must implement lerp/slerp with delta

**Risk:** Medium. More code means more surface for bugs. The collision raycast approach is well-understood but each edge case (camera popping, sudden wall obstruction, player backing into a corner) must be explicitly handled.

**Effort:** Medium (~3-5 hours for robust implementation)

### Approach C: Orbital Camera with Lerp Smoothing (No Collision)

**Description:** Simplified third-person camera that orbits around the player but does NOT handle collision clipping. The camera follows the player at a fixed shoulder offset, orbiting on mouse input, but glitches through walls. This is a quick prototype approach before adding collision resolution.

**Implementation sketch:**
```gdscript
# Simple orbit without collision
var orbit_yaw: float = 0.0
var orbit_pitch: float = -0.2  # slight downward angle

func _physics_process(delta: float) -> void:
    # Camera offset in world space
    var offset := Vector3(0, 2.0, 4.0)
    # Apply orbit rotation
    var orbit_basis := Basis.from_euler(Vector3(orbit_pitch, orbit_yaw, 0.0))
    offset = orbit_basis * offset
    # Lerp camera position for smoothness
    camera.global_position = camera.global_position.lerp(
        global_position + offset,
        delta * 5.0
    )
    # Look at player
    camera.look_at(global_position + Vector3(0, 1.5, 0))

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and _mouse_dragging:
        orbit_yaw -= event.relative.x * look_sensitivity
        orbit_pitch -= event.relative.y * look_sensitivity
        orbit_pitch = clamp(orbit_pitch, -1.0, 0.5)  # limit vertical
```

**Pros:**
- **Fastest to implement** — minimal code changes from current first-person
- **Demonstrates the feel** — lets the team evaluate third-person before committing to collision complexity
- **Simple lerp smoothing** — camera movement feels natural
- **No hierarchy changes** — camera can remain as child of PlayerController (not Head)

**Cons:**
- **No collision handling** — camera clips through walls, floors, objects — game-breaking for release
- **Not shippable** — purely a prototype/demo approach
- **Player invisible** — still no visual player character to frame
- **Camera may clip through floor** — no floor collision = camera goes underground on slopes

**Risk:** Low for prototype. High for production — clipping makes the game unplayable in tight spaces.

**Effort:** Very Low (~30 minutes for prototype)

### Recommendation

→ **Approach A (SpringArm3D)** with **Approach C as an initial prototyping step.**

**Rationale:**

1. **SpringArm3D is the Godot-native correct tool** for third-person cameras. It handles the hardest part (collision detection and camera shortening) with zero custom code. This eliminates the most common source of third-person camera bugs.

2. **The game's scenes are small** (6-8m rooms, narrow corridors). Camera collision is critical — the player will constantly be near walls. SpringArm3D's auto-shortening is essential for playability.

3. **Approach C first for rapid prototyping:** Implement the simple orbital camera (no collision) in a quick branch to verify the third-person feel works for the game's atmosphere. If the team and playtesters confirm third-person is right, replace with SpringArm3D.

4. **Backward compatibility with first-person:** The existing first-person code should be kept as a configurable option (e.g., `@export var camera_mode: String = "third_person"`). Some scenes may work better in first-person (tight corridors, the underpass).

5. **Player representation:** A simple MeshInstance3D (capsule or placeholder) should be added to the PlayerController so the camera has something to frame. Without a visible character, third-person shows an invisible capsule sliding around — immersion-breaking.

**Design constraints for third-person fit:**
- Shoulder offset: `Vector3(0, 2.0, 4.0)` — behind and slightly above
- Orbit vertical clamp: -30° to +45° (prevent camera going underground or flipping)
- Camera smoothing: lerp with factor 5-8 for responsive but smooth follow
- Collision margin: 0.3m from wall surface
- Default look-at point: player chest height (y = 1.0)
- No auto-rotation: camera stays behind player unless mouse-dragged
- On scene transition: camera yaw/pitch resets to default (behind player)

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Camera Follow:** Player moves forward. Camera follows at `Vector3(0, 2, 4)` offset behind player, maintaining the shoulder view.
2. **Orbit Look (Horizontal):** Player drags mouse left → camera orbits around player to the left. Player drags right → orbits right. Player character stays centered in frame.
3. **Orbit Look (Vertical):** Player drags mouse up → camera tilts up (max 45° above horizon). Player drags down → tilts down (max -30° below horizon).
4. **Collision Avoidance:** Player walks backward toward a wall. Camera reaches wall → SpringArm3D shortens → camera does not clip through. Player walks away from wall → camera extends back to full offset.
5. **Player Character Visible:** The player character (placeholder mesh or capsule) is visible in the bottom-center of the frame at all times during normal play.
6. **Dialogue Mode:** During dialogue, camera stays in third-person position. Mouse look is still available (if not blocked by dialogue input).
7. **Scene Transition:** Camera position/orbit state is saved in GameManager and restored on next scene load. Camera yaw/pitch matches previous scene.

### Edge Cases

1. **Camera corner trapped:** Player stands in a corner with walls on two sides. SpringArm3D shortens to minimum. Camera looks at player from very close (over-the-shoulder becomes over-the-head). **Acceptable** — better than clipping.
2. **Camera pinned by ceiling:** Player walks under a low overhang. Camera at y=2.0 hits ceiling. SpringArm3D shortens from top. Player walks out → camera returns to normal.
3. **Rapid mouse orbit:** Player quickly drags mouse in a full circle. Camera orbits smoothly with lerp smoothing. No snapping or disorienting jumps.
4. **Player rotates 180°:** Player turns around. Camera should smoothly follow, staying behind the player (or staying in orbit position if independent orbit is used).
5. **Camera at min arm length:** In extreme tight spaces (narrow corridor), SpringArm3D may reduce to near-zero length. Camera is essentially at player position. **Acceptable degraded mode** — better than clipping.
6. **Multiple players (debug):** Two PlayerControllers somehow exist. Each has its own camera. `_disable_other_cameras()` ensures only one is `current`.
7. **Very high mouse sensitivity:** Player moves mouse extremely fast → large delta → orbit rotates rapidly. Clamp per-frame rotation to prevent disorientation (max ~5° per physics tick).

### Failure Paths

1. **SpringArm3D not available:** If using a Godot version without SpringArm3D (pre-4.2), the `@onready var spring_arm` will be null. A fallback to Approach B (custom RayCast3D) is needed. **Mitigation:** detect at `_ready()` and log a clear error.
2. **RayCast3D collision layer mismatch:** Player on layer 1, walls on layer 2, but RayCast3D mask doesn't include layer 2 → camera clips through walls. **Fix:** ensure CameraCollision raycast mask includes scene geometry layer.
3. **Camera look_at fails:** If camera position == player position (zero arm length), `look_at()` produces garbage or error. **Fix:** clamp camera minimum distance from player to > 0.1m.
4. **Camera state lost on scene change:** GameManager.player_head_rotation (first-person pitch) is stored but camera orbit uses different variables. **Fix:** add `camera_orbit_yaw` and `camera_orbit_pitch` to GameManager for persistence.
5. **Camera clips through floor on slope:** SpringArm3D shoots upward from player origin. On a slope, the arm may go through the floor geometry. **Fix:** Use a downward raycast from camera position to prevent sub-floor clipping.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #149 — Player Character (CharacterBody3D + collision) | 🟡 In Progress | **High** — Without #149, there is no physical player body for the camera to follow. The capsule collider from #149 is the camera's anchor point. |
| #142 — Player Controller (first-person) | ✅ Complete | Low — The existing WASD/mouse look/interaction code provides the movement foundation. Camera mode is the main change. |
| Player placeholder mesh | ❌ Needs Creation | Medium — Third-person camera without a visible player character shows an invisible entity. A simple placeholder (capsule + glow or silhouette) is needed for the camera to frame. |
| Godot 4.2+ (for SpringArm3D) | 🟡 Unknown | Medium — Need to verify project's Godot version. If pre-4.2, fall back to custom RayCast3D approach. |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Player character animation (walk cycle) | P2 |
| Player reflection in puddles/mirrors | P3 |
| Character customization / outfit states | P3 |
| Camera effects (rain on lens, vignette, breathing) | P3 |

### Preparation Needed

- [ ] **Verify Godot version** — Run `godot --version` in the project to confirm SpringArm3D support (requires 4.2+).
- [ ] **Add placeholder player mesh** — Create a simple MeshInstance3D child of PlayerController (capsule with emissive material or shadow-receiving silhouette) so the third-person camera has something to frame.
- [ ] **Decide orbit persistence** — Should camera orbit yaw/pitch persist across scene transitions? If yes, add `camera_orbit_yaw` and `camera_orbit_pitch` to GameManager.
- [ ] **Define collision layers for camera** — Camera collision raycast needs a specific layer/mask combination. Recommend: camera raycast on layer 3, mask against layer 2 (scene geometry).
- [ ] **First-person fallback mode** — Add `@export var camera_mode: String = "third_person"` with options `["third_person", "first_person"]` so the old first-person view is configurable for tight scenes.

---

## 7. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up
> without re-scanning all source files.*

The camera system currently uses a **first-person** setup: Camera3D is a child of `Head` (Node3D) at `(0, 1.6, 0)`, with mouse look rotating the body (yaw) and head (pitch). The player has no visual representation — only a CapsuleShape3D collider.

The proposed change replaces this with a **third-person shoulder-cam**: Camera becomes a child of a `CameraPivot` (orbit yaw) → `SpringArm3D` (collision-aware arm) → positions camera at ~`(0, 2, 4)` behind the player. Mouse look orbits the pivot instead of rotating the body. A placeholder mesh is needed so the camera has something to frame.

The main risk is **#149 not being complete** — without the physical CharacterBody3D the camera has nothing to anchor to. The second risk is **SpringArm3D availability** on the project's Godot version. Approach B (custom RayCast3D) is the fallback.

Existing test cases for camera behavior (TC-PC-N-4, TC-PC-N-6, TC-PC-E-4) will need rewriting since the camera position, rotation model, and mouse look behavior change fundamentally from first-person to third-person.

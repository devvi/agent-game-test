# Research: Player Character — CharacterBody3D + Controller

> Parent Issue: #149
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The game has a `PlayerController.gd` script extending `CharacterBody3D` with full GDScript logic for WASD movement, click-and-drag mouse look, E-key interaction detection, dialogue mode blocking, and fall recovery. The Input Map (`project.godot`) has movement actions (`move_forward`, `move_backward`, `move_left`, `move_right`, `interact`). SceneBase integrates player instantiation via `_instantiate_player()`, and GameManager stores `player_position`, `player_rotation`, `player_head_rotation`.

**However, the player character does not physically work** because:

1. **No CollisionShape3D exists on the player body:** `PlayerController.gd:new()` creates a bare `CharacterBody3D` with no collision shape. `move_and_slide()` resolves against nothing — the player clips through walls.
2. **Child nodes (Head, Camera3D, InteractionArea) are not created at instantiation:** The script's `@onready var head: Node3D = $Head` assumes `$Head` exists as a child node, but `PLAYER_CONTROLLER.new()` (called in `scene_base.gd:78`) only creates a `CharacterBody3D` with the script attached — no child nodes are created. At runtime, `$Head` returns `null`, causing errors when `head.rotation.x` or `head.global_transform` is accessed.
3. **Camera conflict in main.tscn:** The existing `Camera3D` at position `(0, 2, 5)` in `main.tscn` has `current = true`, which conflicts with the PlayerController's own camera. Camera switching is unreliable.
4. **No player body exists in any scene:** `main.tscn` has no `CharacterBody3D` — only a standalone `Camera3D`. SceneBase's `_instantiate_player()` creates the PlayerController at runtime, but without child nodes or collision it cannot function.

### Expected Behavior

1. **PlayerController instantiation creates a functional physics body:** The `CharacterBody3D` has a `CapsuleShape3D` collision shape, a `Head` node with `Camera3D`, and an `InteractionArea` for E-key proximity detection.
2. **Player collides with scene geometry:** `move_and_slide()` resolves against `StaticBody3D` walls and floors. The player cannot clip through walls.
3. **Camera works without conflicts:** The PlayerController's camera is the only `current = true` camera. The main.tscn fallback camera is `current = false` or removed.
4. **NPCNode proximity detection works:** The PlayerController adds itself to the `"player"` group, which NPCNode's `_on_body_entered` checks — proximity labels appear when near NPCs.

### User Scenarios

- **Scenario A (Movement with collision):** Player presses W to walk forward — moves at 2.5 m/s until reaching a wall — stops at the wall, does not clip through.
- **Scenario B (Mouse look):** Player holds left mouse button and drags — camera rotates horizontally (yaw on body) and vertically (pitch on Head), clamped at ±60°.
- **Scenario C (E-key interaction):** Player walks within 2m of an NPC — `InteractionArea.body_entered` fires — NPCNode proximity labels appear — player presses E — dialogue starts.
- **Scenario D (Scene transition):** Player walks to exit trigger — dialogue choice triggers scene change — fade out — new scene loads — PlayerController re-instantiated — position restored from GameManager.

### Core Question

> **The GDScript logic exists. The Input Map exists. SceneBase integration exists. What is the minimum structural change to make the player character physically work?**

The evidence shows the codebase has reached "script-complete but physically-incomplete" state for #142. Issue #149 is the physical embodiment gap: create the CharacterBody3D node structure with collision, ensuring the existing script can execute without errors.

---

## 2. Root Cause Analysis / Architectural Gap

### Why Does Current Behavior Exist?

1. **Script-driven vs. scene-driven instantiation:** `PlayerController.gd` was designed as a script-on-node pattern where the child node structure (Head, Camera3D, InteractionArea, CollisionShape3D) was expected to come from a scene file or from `_ready()` node creation — but **neither was built**. The script assumes `$Head` etc. exist, but `PLAYER_CONTROLLER.new()` creates only a bare `CharacterBody3D`.

2. **Collision shape omission:** The original #142 implementation focused on GDScript logic (movement, input, interaction flow) and did not add a collision shape. Without it, `move_and_slide()` has no effect — the player is a ghost.

3. **#142/#149 split rationale:** The original issue breakdown split "controller logic" (#142) from "player character body" (#149) — but #142's implementation was kept script-only, leaving the physical body to #149. The split means #149 must now add the node structure that #142's script depends on.

### Code Path of Failure

```
SceneBase._ready()
  → _instantiate_player()
    → var _player = PLAYER_CONTROLLER.new()   # Creates Node + script only
    → add_child(_player)
      → _player._ready() fires:
        → $Head → null  ❌  (@onready fails, head = null)
        → $Head/Camera3D → null  ❌
        → $InteractionArea → null  ❌
        → head.rotation.x = camera_tilt → ERROR: Attempt to call 'rotation' on null
```

### What Already Works (No Changes Needed)

| Component | Status | Evidence |
|-----------|--------|----------|
| PlayerController GDScript logic | ✅ Complete | Movement, look, interaction, dialogue blocking, fall recovery |
| Input Map actions | ✅ Complete | `move_forward`, `move_backward`, `move_left`, `move_right`, `interact` in `project.godot` |
| SceneBase instantiation hook | ✅ Complete | `_instantiate_player()`, `_save_player_state()` in `scene_base.gd` |
| GameManager persistence | ✅ Complete | `player_position`, `player_rotation`, `player_head_rotation` |
| NPCNode proximity | ✅ Complete | `is_in_group("player")` checks. PlayerController already calls `add_to_group("player")` |
| Unit tests | ✅ Complete | 34 tests across test_player_controller.gd, test_scene_base_player.gd, test_game_manager_player.gd, test_input_map_validation.gd |
| Integration tests | ✅ Complete | test_player_in_scene.gd, test_npc_in_scene.gd |

### Architectural Intent Signal

The codebase **clearly intended** a CharacterBody3D with child nodes:

| Evidence | Location |
|----------|----------|
| `@onready var head: Node3D = $Head` | `player_controller.gd:13` |
| `@onready var camera: Camera3D = $Head/Camera3D` | `player_controller.gd:14` |
| `@onready var interaction_area: Area3D = $InteractionArea` | `player_controller.gd:15` |
| `$FallReset` referenced in design doc | `docs/DESIGN/142-player-controller.md:110` |
| CapsuleShape3D for collision | `docs/DESIGN/142-player-controller.md:103` |

---

## 3. Impact Analysis

### Directly Affected Files

| File | Change Type | Nature |
|------|-------------|--------|
| `gdscripts/player_controller.gd` | **Modify** | Add `_build_node_tree()` in `_ready()` to create child nodes programmatically when they don't exist |
| `scenes/main.tscn` | **Modify** | Set existing Camera3D `current = false` (PlayerController's camera becomes primary) |
| `tests/unit/test_player_controller.gd` | **Modify** | Update `_make_pc()` helper to use the new node-building path or test without pre-created children |

### Indirectly Affected Modules

| File | Why Affected |
|------|-------------|
| All scene scripts (office.gd, lobby.gd, etc.) | No code changes needed, but collision layer/mask audit ensures player collides with scene geometry |
| `gdscripts/scene_base.gd` | No changes needed — already instantiates PlayerController. The fix is in `player_controller.gd._ready()` |
| `gdscripts/npc_node.gd` | No changes needed — `is_in_group("player")` check works once PlayerController has collision and is a real body |
| `gdscripts/game_manager.gd` | No changes needed — persistence variables are already present |

### Data Flow Impact

**Current (broken) flow:**
```
PLAYER_CONTROLLER.new() → CharacterBody3D (no children, no collision)
  → _ready() → @onready $Head = null → ERROR
```

**Proposed (working) flow:**
```
PLAYER_CONTROLLER.new() → CharacterBody3D (script only)
  → _ready()
    → _build_node_tree() creates Head/Camera3D/InteractionArea/CollisionShape3D
    → add_to_group("player")
    → camera.current = true
    → Connect body_entered/body_exited signals on InteractionArea
    → Normal input/physics loop
```

---

## 4. Solution Design

### Approach A (Recommended): Programmatic Node Tree in _ready()

**Description:** Modify `PlayerController._ready()` to detect missing child nodes and create them programmatically. This avoids creating a separate `.tscn` file and keeps the instantiation path (`PLAYER_CONTROLLER.new()`) unchanged.

**Implementation sketch:**
```gdscript
# Add to _ready(), before @onready var references:
func _build_node_tree() -> void:
    # Only build if child nodes don't exist (supports both .tscn and .new() instantiation)
    if not has_node("Head"):
        var head := Node3D.new()
        head.name = "Head"
        add_child(head)
        head.owner = self
    
    if not has_node("Head/Camera3D"):
        var cam := Camera3D.new()
        cam.name = "Camera3D"
        cam.position = Vector3(0, camera_height, 0)
        $Head.add_child(cam)
    
    if not has_node("InteractionArea"):
        var area := Area3D.new()
        area.name = "InteractionArea"
        var shape := CollisionShape3D.new()
        shape.name = "CollisionShape3D"
        var sphere := SphereShape3D.new()
        sphere.radius = interaction_range
        shape.shape = sphere
        area.add_child(shape)
        add_child(area)

# Add CollisionShape3D on the root CharacterBody3D
func _build_collision_shape() -> void:
    if not has_node("PlayerCollisionShape"):
        var shape := CollisionShape3D.new()
        shape.name = "PlayerCollisionShape"
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.3
        capsule.height = 1.4  # ~eye height match
        shape.shape = capsule
        shape.position = Vector3(0, 0.7, 0)  # centered on body
        add_child(shape)
```

**Then restructure _ready():**
```gdscript
func _ready() -> void:
    _build_node_tree()
    _build_collision_shape()
    # Now @onready vars work because nodes exist
    head = $Head
    camera = $Head/Camera3D
    interaction_area = $InteractionArea
    
    add_to_group("player")
    camera.current = true
    head.rotation.x = camera_tilt
    # ... rest of existing _ready()
```

**Pros:**
- Zero scene file changes — single script fix
- Backward compatible with existing `PLAYER_CONTROLLER.new()` in SceneBase
- Works in both headless tests and runtime
- No new assets or TSCN files
- Easy to override for future scene-based PlayerController

**Cons:**
- Slightly more code in _ready()
- @onready vars need manual reassignment (or switch to onready + guard)
- Collision shape dimensions are hardcoded (but exported vars can be added later)

**Risk:** Low. Minimal change, high impact. The only risk is collision shape dimensions not matching scene geometry perfectly — can be tuned.

**Effort:** Low (~1-2 hours including testing)

### Approach B (Alternative): Create player_controller.tscn Scene File

**Description:** Create a `scenes/player/player_controller.tscn` packed scene with the full node hierarchy. Modify `SceneBase._instantiate_player()` to use `preload()` of the scene instead of `PLAYER_CONTROLLER.new()`.

**Implementation sketch:**
```
# scenes/player/player_controller.tscn
[gd_scene load_steps=4 format=3]
[ext_resource type="Script" path="res://gdscripts/player_controller.gd"]
[sub_resource type="CapsuleShape3D" id="capsule"]
[sub_resource type="SphereShape3D" id="sphere"]

[node name="PlayerController" type="CharacterBody3D"]
script = ExtResource("1")
[node name="CollisionShape3D" type="CollisionShape3D"]
shape = SubResource("capsule")
[node name="Head" type="Node3D"]
[node name="Camera3D" type="Camera3D" parent="Head"]
[node name="InteractionArea" type="Area3D"]
[node name="CollisionShape3D" type="CollisionShape3D" parent="InteractionArea"]
shape = SubResource("sphere")
```

**Modify scene_base.gd:**
```gdscript
const PLAYER_CONTROLLER_SCENE := preload("res://scenes/player/player_controller.tscn")

func _instantiate_player() -> void:
    if _player and is_instance_valid(_player):
        return
    _player = PLAYER_CONTROLLER_SCENE.instantiate()
    _player.name = "PlayerController"
    add_child(_player)
    # ... restore position etc.
```

**Pros:**
- Clean separation of node structure from script logic
- Visual editing in Godot editor
- Standard Godot pattern (scene + script)

**Cons:**
- Requires creating a new TSCN file
- Changes the instantiation path in SceneBase (breaks current `PLAYER_CONTROLLER.new()`)
- Need to update 3 instantiation paths (scene_base.gd + tests)
- More files to maintain

**Risk:** Low-Medium. The scene file is simple, but changing the instantiation path affects existing tests.

**Effort:** Low (~1 hour)

### Approach Comparison

| Criterion | Approach A (Programmatic) | Approach B (Scene File) |
|-----------|--------------------------|------------------------|
| Files changed | 2 (player_controller.gd, main.tscn) | 3 (new TSCN, scene_base.gd, main.tscn) |
| Backward compat | ✅ Full — same `.new()` API | ❌ Breaks existing `.new()` instantiations |
| Test compat | ✅ Tests continue to work | ❌ Tests need scene path updates |
| Editor editability | ❌ No visual editing | ✅ Can edit in Godot |
| Future extensibility | ✅ Can switch to scene later | ✅ Standard pattern |
| Complexity delta | +30 lines in _ready() | +1 new file, 2 file modifications |

### Recommendation

→ **Approach A (Programmatic Node Tree)** for this issue. The codebase already uses `PLAYER_CONTROLLER.new()` in `scene_base.gd` and in every unit test helper (`_make_pc()`). Changing to a scene file would break 4+ files. The programmatic approach is a self-contained fix with zero ripple effects. A `.tscn` file can be added later for visual editing when the player needs a model or animation.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **PlayerController instantiation:** SceneBase calls `_instantiate_player()` → `PLAYER_CONTROLLER.new()` → `_ready()` builds node tree → Head, Camera3D, CollisionShape3D, InteractionArea exist as children → no null reference errors.
2. **Collision:** Player presses W → CharacterBody3D moves via `move_and_slide()` → collides with StaticBody3D wall → player stops at wall boundary → no clipping.
3. **Camera:** PlayerController's Camera3D is `current = true` after `_ready()` → viewport shows camera view from eye level (1.6m). main.tscn Camera3D is `current = false`.
4. **Mouse look:** Player holds left mouse button and drags → body yaws, Head pitches → camera moves with head → vertical rotation clamped at ±60°.
5. **E-key interaction:** Player walks within 2m of NPC → InteractionArea.body_entered fires → NPCNode proximity labels appear → player presses E → `interaction_requested` signal emitted → dialogue starts.
6. **Dialogue mode:** During dialogue, WASD movement pauses. E routes to dialogue selection.
7. **Scene transition:** Player changes scene → GameManager saves position → new scene loads → PlayerController re-instantiated at saved position.

### Edge Cases

1. **Double instantiation:** _instantiate_player() called twice → guard check `if _player and is_instance_valid(_player): return` prevents duplicates.
2. **Head node missing:** If Head was manually removed → `_build_node_tree()` re-creates it. If that also fails → mouse look silently skips (handled by `if not head: return`).
3. **InteractionArea missing:** Same pattern — `_build_node_tree()` re-creates. body_entered/body_exited connections re-established.
4. **Scene unload during movement:** Player is moving when dialogue choice triggers scene change → `_exit_tree()` saves position → scene unloads → PlayerController freed → no orphan or crash.
5. **No GameManager at startup:** `_connect_dialogue_signals()` gracefully handles null `/root/GameManager`.

### Failure Paths

1. **Collision layer mismatch:** Player on layer 1, scene geometry on layer 2 → player clips through walls. **Mitigation:** All StaticBody3D should be on layer 1, mask 1. Add layer/mask audit to implementation.
2. **Capsule shape too tall:** Capsule height > door frame height → player gets stuck at doorways. **Mitigation:** Capsule height 1.4m (standard human height), radius 0.3m.
3. **Capsule shape too wide:** Capsule radius > corridor width → player can't navigate tight spaces. **Mitigation:** Radius 0.3m (~1ft) fits standard door widths.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| PlayerController.gd script | ✅ Complete (#142) | Low — script is tested and stable |
| Input Map actions (project.godot) | ✅ Complete (#142) | Low — `move_forward/backward/left/right/interact` exist |
| SceneBase._instantiate_player() | ✅ Complete (#142) | Low — function exists, just needs working PlayerController |
| GameManager player persistence | ✅ Complete (#142) | Low — position/rotation vars exist |
| Scene geometry with StaticBody3D | ✅ Complete (office, street, lobby) | Low — collision shapes exist |
| NPCNode proximity detection | ✅ Complete | Low — `is_in_group("player")` check ready |

### Blocks

| Future Work | Priority |
|-------------|----------|
| #150 — Camera Follow (third-person) | P1 — needs player body to anchor the camera |
| Player character model/visual | P2 — needs collision body first |
| Footstep audio (Issue #48 integration) | P3 — needs moving body generating signals |
| Interaction prompt UI (E-key indicator) | P3 — proximity detection works but needs visual polish |

---

## 7. Spike / Experiment Results

### Experiment 1: Verify PLAYER_CONTROLLER.new() Child Node Status

**Method:** Trace the instantiation path in `scene_base.gd` and `_make_pc()` in test files.

**Result:**
- `scene_base.gd:78`: `_player = PLAYER_CONTROLLER.new()` — creates bare CharacterBody3D with script only
- No CollisionShape3D, Head, Camera3D, or InteractionArea children exist
- `_make_pc()` in tests manually creates Head/Camera3D/InteractionArea: lines 76-84 of `test_player_controller.gd`
- This confirms the @onready vars will fail in production (the tests work because they manually build the tree)

**Verdict:** Confirmed — programmatic node tree creation is necessary.

### Experiment 2: Collision Layer Audit

**Method:** Check `project.godot` for collision layer defaults and audit scene TSCN files.

**Result:**
- `project.godot` has no custom collision layer configuration — uses Godot defaults (layer 1)
- Scene StaticBody3D nodes (office.tscn, street.tscn, etc.) use default layer/mask (layer 1, mask 1)
- No custom layers configured — all physics bodies use layer 1
- An empty CharacterBody3D with mask 1 will collide with everything on layer 1

**Verdict:** Default layer 1 is sufficient. No layer configuration needed for MVP. If custom layers are added later, they should use layers 2+.

### Experiment 3: Existing Test Compatibility

**Method:** Check if adding `_build_node_tree()` to `_ready()` breaks existing test `_make_pc()` helpers.

**Result:**
- `_make_pc()` manually creates Head/Camera3D/InteractionArea children before calling PC methods
- If `_build_node_tree()` checks `if not has_node("Head")` — the guard prevents double-creation
- Existing tests continue to work because the guard detects pre-existing children
- Tests that call `PlayerControllerScript.new()` directly (without `_make_pc()`) will now get working node trees

**Verdict:** No test breakage. Full backward compatibility.

---

## 8. Continuation Context

### Current State Summary

| System | State | Key Details |
|--------|-------|-------------|
| PlayerController.gd | Script-complete, physically incomplete | WASD/mouse/E logic exists. No child nodes, no collision shape. |
| CollisionShape3D | **Missing** | CapsuleShape3D needs to be added programmatically in `_ready()` |
| Head/Camera3D/InteractionArea | **Missing** | Need to be created in `_build_node_tree()` |
| main.tscn Camera3D | `current = true` | Must be set to `current = false` — PlayerController camera takes over |
| Unit tests | ✅ 34 tests exist | `_make_pc()` helpers need no changes (guard prevents double-creation) |
| Integration tests | ✅ 6 tests exist | test_player_in_scene.gd tests dialogue blocking, persistence |

### Architecture Decisions for Implementation

1. **Programmatic node creation in `_ready()`:** Use `_build_node_tree()` and `_build_collision_shape()` methods that create child nodes only when missing. This preserves the `PLAYER_CONTROLLER.new()` instantiation path.

2. **Guard-based @onready reassignment:** After building the tree, reassign `head`, `camera`, `interaction_area` from the actual node paths. The @onready vars become fallbacks.

3. **Collision shape dimensions:** Capsule radius 0.3m, height 1.4m. These fit standard human proportions and allow navigation through doorways.

4. **Camera conflict resolution:** Set `main.tscn` Camera3D `current = false`. PlayerController's camera is the only `current = true` camera in any scene.

5. **No additional Input Map changes:** All necessary actions exist from #142.

6. **No SceneBase changes:** The `_instantiate_player()` hook and `PLAYER_CONTROLLER.new()` call remain identical.

### Main Risk

The **collision layer/mask consistency** is the primary risk. If scene geometry StaticBody3D nodes use non-default layers, the player's default-layer CharacterBody3D won't collide. A systematic TSCN audit during implementation is needed.

**Secondary risk:** Capsule shape dimensions may need tuning. Height of 1.4m + radius 0.3m may feel wrong in scenes with low ceilings or narrow corridors. Walk speed (2.5 m/s) combined with collision may feel clunky if scenes are too small.

### Checklist for Implementation

- [ ] Add `_build_node_tree()` to `player_controller.gd` — creates Head, Camera3D, InteractionArea with SphereShape3D
- [ ] Add `_build_collision_shape()` to `player_controller.gd` — creates CapsuleShape3D on root body
- [ ] Modify `_ready()` to call both builders before @onready reassignment or access
- [ ] Set `main.tscn` Camera3D `current = false`
- [ ] Audit all scene TSCN files for StaticBody3D collision layer consistency
- [ ] Run all unit tests (`tests/unit/test_player_controller.gd`, `test_scene_base_player.gd`, `test_game_manager_player.gd`, `test_input_map_validation.gd`)
- [ ] Run integration tests (`tests/integration/test_player_in_scene.gd`)
- [ ] Manual verification: Walk through office scene, verify collision with walls, E-key proximity with NPC
- [ ] Verify scene transition preserves position/rotation

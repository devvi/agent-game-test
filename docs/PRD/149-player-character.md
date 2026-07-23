# Research: Player Character — CharacterBody3D + Controller

> Parent Issue: #149
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

[Content intentionally shortened to fit — see continuation context for full structure]

### Current Behavior

The game has a `PlayerController.gd` script extending `CharacterBody3D` with full GDScript logic for WASD movement, click-and-drag mouse look, E-key interaction detection, dialogue mode blocking, and fall recovery. The Input Map (`project.godot`) has movement actions (`move_forward`, `move_backward`, `move_left`, `move_right`, `interact`). SceneBase integrates player instantiation via `_instantiate_player()`, and GameManager stores `player_position`, `player_rotation`, `player_head_rotation`.

**However, the player character does not physically work** because:

1. **No CollisionShape3D exists on the player body:** `PlayerController.gd:new()` creates a bare `CharacterBody3D` with no collision shape. `move_and_slide()` resolves against nothing — the player clips through walls.
2. **Child nodes (Head, Camera3D, InteractionArea) are not created at instantiation:** The script's `@onready var head: Node3D = $Head` assumes `$Head` exists as a child node, but `PLAYER_CONTROLLER.new()` only creates a `CharacterBody3D` with the script attached — no child nodes are created.
3. **Camera conflict in main.tscn:** The existing `Camera3D` at `(0, 2, 5)` has `current = true`, conflicting with PlayerController's camera.
4. **No player body exists in any scene:** No `CharacterBody3D` is present in `main.tscn` or any scene file.

---

## 2. Root Cause Analysis

### Code Path of Failure

```
SceneBase._ready()
  → _instantiate_player()
    → _player = PLAYER_CONTROLLER.new()   # Bare CharacterBody3D + script only
    → add_child(_player)
      → _player._ready():
        → $Head → null  ❌  (@onready fails)
        → $Head/Camera3D → null  ❌
        → $InteractionArea → null  ❌
        → head.rotation.x → ERROR on null
```

### What Already Works (No Changes Needed)

| Component | Status |
|-----------|--------|
| PlayerController GDScript logic | ✅ Complete — WASD, mouse look, E-key, dialogue blocking |
| Input Map actions | ✅ Complete — `move_forward/backward/left/right/interact` |
| SceneBase._instantiate_player() | ✅ Complete — hook exists from #142 |
| SceneBase._save_player_state() | ✅ Complete — position/rotation persist |
| GameManager player vars | ✅ Complete — `player_position`, `player_rotation`, `player_head_rotation` |
| NPCNode proximity detection | ✅ Complete — `is_in_group("player")` checks |
| Unit tests (34) + Integration tests (6) | ✅ Complete — test_player_controller, test_scene_base_player, etc. |

---

## 3. Solution Design

### Approach A (Recommended): Programmatic Node Tree in _ready()

**Description:** Modify `PlayerController._ready()` to detect missing child nodes and create them programmatically.

```gdscript
func _build_node_tree() -> void:
    if not has_node("Head"):
        var head := Node3D.new()
        head.name = "Head"
        add_child(head)
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

func _build_collision_shape() -> void:
    if not has_node("PlayerCollisionShape"):
        var shape := CollisionShape3D.new()
        shape.name = "PlayerCollisionShape"
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.3
        capsule.height = 1.4
        shape.shape = capsule
        shape.position = Vector3(0, 0.7, 0)
        add_child(shape)
```

**Pros:** Zero ripple effects — same `.new()` API, tests unaffected, no new files.
**Cons:** Slightly more code in _ready().
**Risk:** Low. Guard-based creation (`if not has_node`) ensures backward compat.

### Approach B (Alternative): player_controller.tscn Scene File

Create `scenes/player/player_controller.tscn` with full node hierarchy. Modify `SceneBase._instantiate_player()` to use `preload()` + `.instantiate()` instead of `.new()`.

**Pros:** Standard Godot pattern, visual editing. **Cons:** Breaks `.new()` path across 4+ files.

### Recommendation

→ **Approach A (Programmatic Node Tree).** The `PLAYER_CONTROLLER.new()` path is used in `scene_base.gd` and all test helpers. Changing to a scene file would break everything. A TSCN can be added later for visual editing.

---

## 4. Boundary Conditions & Acceptance Criteria

### Normal Path

1. `_instantiate_player()` → `PLAYER_CONTROLLER.new()` → `_ready()` builds node tree → Head, Camera3D, CollisionShape3D, InteractionArea exist → no null errors.
2. Player presses W → `move_and_slide()` collides with StaticBody3D walls → no clipping.
3. PlayerController camera is `current = true` after _ready(). main.tscn Camera3D is `current = false`.
4. Player walks within 2m of NPC → InteractionArea.body_entered fires → NPCNode labels appear → E-key triggers dialogue.

### Edge Cases

- **Double instantiation:** Guard `if _player and is_instance_valid(_player): return` prevents duplicates.
- **Head missing:** `_build_node_tree()` re-creates it. `if not head: return` in mouse look for safety.
- **Scene unload:** `_exit_tree()` saves position → no orphan or crash.
- **No GameManager:** `_connect_dialogue_signals()` handles null gracefully.

### Failure Paths

- **Collision layer mismatch:** Audit needed — all StaticBody3D on layer 1, player on layer 1.
- **Capsule dimensions:** Height 1.4m, radius 0.3m. May need tuning for narrow corridors.

---

## 5. Dependencies & Blockers

### Depends On (All ✅ Complete)

| Dependency | Issue |
|------------|-------|
| PlayerController.gd script | #142 |
| Input Map actions | #142 |
| SceneBase._instantiate_player() | #142 |
| GameManager player persistence | #142 |
| Scene geometry with StaticBody3D | Initial scaffold |
| NPCNode proximity detection | #54 |

### Blocks

- #150 — Camera Follow (third-person) — needs player body to anchor camera
- Player character model — needs collision body first

---

## 6. Spike / Experiment Results

### Experiment 1: Verify Child Nodes

`PLAYER_CONTROLLER.new()` creates bare CharacterBody3D — no Head, Camera3D, or InteractionArea children. `_make_pc()` in tests manually creates them (lines 76-84). Confirmed: programmatic node creation is necessary.

### Experiment 2: Collision Layer Audit

All physics bodies use default layer/mask (layer 1). No custom layers configured. Default layer 1 is sufficient.

### Experiment 3: Test Compatibility

`_build_node_tree()` uses `if not has_node("Head")` guard — tests that pre-create children are unaffected. Full backward compatibility.

---

## 7. Continuation Context

### Implementation Checklist

- [ ] Add `_build_node_tree()` to `player_controller.gd` — Head, Camera3D, InteractionArea + SphereShape3D
- [ ] Add `_build_collision_shape()` — CapsuleShape3D (r=0.3, h=1.4) on root body
- [ ] Modify `_ready()` to call builders before @onready reassignment
- [ ] Set `main.tscn` Camera3D `current = false`
- [ ] Audit all scene TSCN files for StaticBody3D collision layer consistency
- [ ] Run unit tests: `test_player_controller.gd`, `test_scene_base_player.gd`, `test_game_manager_player.gd`, `test_input_map_validation.gd`
- [ ] Run integration tests: `test_player_in_scene.gd`
- [ ] Manual verification: walk through office, verify wall collision, E-key NPC proximity
- [ ] Verify scene transition preserves position/rotation

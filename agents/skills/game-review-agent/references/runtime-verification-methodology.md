# Runtime Verification Methodology

> Static resource-loading tests are NOT sufficient. They verify files exist
> but miss: missing collision shapes, objects at origin (0,0,0), parse errors
> in sub-resource references, physics/gravity failures.

## The Lesson

A test that says "scene loads" is lying to you. A scene can load successfully
but have:
- CollisionShape3D nodes with `shape = null` — player falls through floor
- Label3D nodes at `position = Vector3(0,0,0)` — text piles up at origin
- CSGBox3D with `use_collision = false` — no physics interaction
- Broken sub-resource IDs — parse errors at instantiation time
- Missing autoloads — runtime crashes when signals fire

## Runtime Test Script Template

Save as `tests/verify_runtime.gd`, extends `SceneTree`, runs via:
```bash
godot --headless --script tests/verify_runtime.gd 2>&1
```

### What to Check

**1. Collision Integrity**
```
For each scene file in the scene chain:
  - Load and instantiate the scene
  - Find ALL CollisionShape3D nodes
  - Assert each has a non-null `shape` property
  - Report: "OK lobby (3/3 collision shapes)" vs "FAIL lobby (2/3 missing)"
```

**2. Object Positioning**
```
For each scene:
  - Find ALL Label3D nodes
  - Check that most are NOT at Vector3.ZERO
  - Allow 1-2 at origin if intentional (e.g. hidden debug labels)
  - Report: "OK office — all Label3D positioned" vs "FAIL street — 5/8 at origin"
```

**3. Scene Load Integrity**
```
For each scene:
  - Attempt ResourceLoader.load() — catches parse errors
  - Instantiate and queue_free() — catches runtime init errors
  - Catch sub-resource ID mismatches (load_steps count)
```

**4. Physics Smoke Test (advanced)**
```
- Create a CharacterBody3D at spawn point
- Let gravity pull it down for 10 frames
- Verify it's standing on the floor (y > floor_level - epsilon)
```

## When to Run

1. **During CI**: after `godot --headless --script tests/run_tests.gd` passes
2. **During review agent review**: before merging an implement PR that changes scenes
3. **Before reporting "game works" to the user**: always run runtime verification first

## Pitfalls

- **Scene file format**: `[sub_resource]` blocks must come BEFORE `[node]` blocks.
  Count must match `load_steps` in the `[gd_scene]` header. Missing sub-resources
  cause parse errors at instantiation time, not load time.
- **CSGBox3D vs CollisionShape3D**: A CSGBox3D with `use_collision = true` provides
  its own collision. The separate CollisionShape3D child is redundant UNLESS it
  has a `shape` sub-resource. Without shape, the CollisionShape3D is a no-op.
- **Timer as sub-resource**: `[sub_resource type="Timer"]` is invalid — Timer is
  a Node, not a Resource. Use a direct child node instead.

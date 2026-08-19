# Godot Particle Diagnostics — GPUParticles2D "few/no particles visible"

Session trace: Issue #465 (rain curtain "single leak point" symptom, 2026-08-13).
Root cause + verification technique, reusable for any Godot particle-display bug
research session.

## The #1 root cause: default `visibility_rect` culling

`GPUParticles2D.visibility_rect` (Rect2, **node-local coords**, **default
Rect2(-100,-100,200,200)**) culls every particle whose position falls outside the rect.
If the node sits at `position=(360,-20)` and the emission rect spans the full 720px
width, only particles in the central ~200px column (world x∈[260,460]) render →
symptom: "a single particle hangs near the middle of the screen, like a leak point".

Fix pattern:
- Move node to screen center: `position = Vector2(360, 640)` (720×1280 project)
- Full-screen emission: `emission_rect_extents = Vector2(360, 640)` — **half-extents!**
- Un-cull everything: `visibility_rect = Rect2(-360, -640, 720, 1280)` (local coords;
  world rect = (0,0,720,1280) given the centered node). Bind rect to node position with
  a comment — if the node moves, the rect must move with it.

## Verify property existence/defaults without docs — headless ClassDB dump

Godot 4.x lets you inspect ANY class's properties and defaults at runtime; no docs lookup:

```gdscript
extends SceneTree
func _init() -> void:
    for p in ClassDB.class_get_property_list("GPUParticles2D"):
        print(p.name, " : ", p.type)   # type 7 = Rect2
    var v = ClassDB.class_get_property_default_value("GPUParticles2D", "visibility_rect")
    print("default visibility_rect = ", v)
    quit()
```

Run: `godot --path mini-pong/ --headless --script /tmp/check.gd`

Pitfalls:
- Project autoloads (e.g. audio_engine headless warnings) print to stdout BEFORE your
  script output — pipe through grep for your print markers.
- `ClassDB.class_get_property_list` entries may need a usage-flag filter (e.g.
  `p.usage & PROPERTY_USAGE_EDITOR`) to get a clean list.

## Emission geometry math (half-extents semantics)

`emission_rect_extents` is HALF the rectangle size. `Vector2(360,8)` = 720×16, not 720×8.
World emission rect = node.position ± extents. A "full-width band at top" config
(node (360,-20), extents (360,8)) → world y∈[-28,-12]: only a 16px band, NOT full screen.
Full-screen 720×1280 needs node (360,640) + extents (360,640).

## Diagnosis decision tree for "particles not showing"

1. **D1 culling** — `visibility_rect` too small / node off-center (most common; check the
   DEFAULT value first — it culls anything outside a 200×200 local window)
2. **D2 emission geometry** — extents/position math wrong (half-extents confusion, band
   too thin, emission_shape not RECTANGLE)
3. **D3 platform backend** — macOS Metal / device-specific GPU particle bugs. Only
   investigate AFTER fixing D1/D2; verify by toggling renderer (Compatibility) or a
   CPUParticles2D prototype. Note: **CPUParticles2D has NO `process_material`**
   (ParticleProcessMaterial is GPU-only) — swapping breaks any
   `_material.initial_velocity_min`-style modulation code and its tests.

## Runtime-modulation contract interplay

If a controller modulates `initial_velocity_min/max` / `scale_min/max` / color alpha at
runtime (e.g. a rain-intensity formula), the tscn values are the *base band* and the
runtime multiplier scales them. An issue spec like "velocity 800–1200 px/s" maps to the
**BASE constants**; document in the PRD how the modulated band behaves at default vs max
intensity (e.g. `k=0.6+0.8×rain` → default rain ≈672–1008, storm ≈1120–1680).
NEVER write `amount` at runtime — Godot restarts the particle system → visible jumps
(#389 contract red line, godot-weather-2D README evidence).

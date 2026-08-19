# Multi-Subsystem PRD Pattern — Issue #217 Session Trace

> Captured from research session 2026-07-25 for Issue #217 (basic visual atmosphere system).

## Situation

Issue #217 called for a "basic visual atmosphere system — Decal/GPUParticles" spanning **4 independent subsystems**:

1. GPUParticles3D raindrops (≥1000 particles, wind effect, elongated shader)
2. Decal neon light halos (≥3 colors, dynamic cycling)
3. GPUParticles3D ground fog (height < 0.5 units, slow drift)
4. SpotLight3D+Decal combo light cones (replace OmniLight3D)

## Multi-Subsystem PRD Structure

The PRD (docs/PRD/217-basic-visual-atmosphere-system.md) used:

- **Section 4 subdivided** into 4.1 (Rain), 4.2 (Decal halos), 4.3 (Ground fog), 4.4 (Light cones)
- **Each subsection** had 3 approaches (A/B/C) with full Pros/Cons/Risk/Effort
- **End-of-section recommendation table**:

  | Subsystem | Recommended | Core File |
  |-----------|-------------|-----------|
  | Raindrops | A: Single GPUParticles3D + shader | `rain_particles.gd` |
  | Neon halos | A: Independent Decal + dynamic color | `neon_decal_controller.gd` |
  | Ground fog | A: GPUParticles3D + semi-transparent | `ground_fog.gd` |
  | Light cones | A: SpotLight3D + Decal ground spot | scene node config |

- **Section 7 had 4 experiments** (one per subsystem + a parameter tuning one), exceeding the `depth/deep` minimum of 3

## Parameter-Contract-to-Execution-Layer Discovery

### The Contract (from Issue #214)

`gdscripts/worldview_controller.gd` defined `get_hallucination_params(level: int) -> Dictionary` returning:

```gdscript
{
  "vignette": 0.0..0.8,
  "rain_density": 0.0..0.9,
  "light_flicker": 0.0..0.8,
  "text_drift": 0.0..0.5,
  "view_instability": 0.0..0.4
}
```

This is a **parameter contract** — it defines what values exist and what they mean, but there is zero code that consumes these values at runtime. No GPUParticles3D.amount is set from `rain_density`. No light intensity is modulated from `light_flicker`. No vignette shader is driven.

### The Execution Layer (Issue #217)

#217 creates the infrastructure that makes those parameters actionable:

- `rain_particles.gd` — exposes `@export var base_density: float` (will be modulated by `rain_density` from #214 in #19)
- `neon_decal_controller.gd` — exposes `@export var current_color_index: int` (could be modulated by `light_flicker` in #19)
- `ground_fog.gd` — exposes `@export var density: float`, `@export var drift_speed: float`
- `light_cone_controller.gd` — exposes `@export var light_energy: float`

### The Deferred Dynamic Layer (Future Issue #19)

The chain: `hallucination_level → worldview_controller.get_hallucination_params() → rain_particles.amount, light_cone_controller.light_energy, neon_decal_controller.flicker_intensity`

Was explicitly scoped out of #217 with: "本Issue只做基础视觉效果，幻觉等级驱动的动态变化在#19中扩展"

## Commands Used During Research

```bash
# Discover the parameter contract
grep -r 'get_hallucination_params\|rain_density\|light_flicker' gdscripts/*.gd

# Find orphaned parameters (defined but not consumed)
grep -rn 'rain_intensity' gdscripts/*.gd
# → Found in rain_controller.gd, but no GPUParticles3D.amount references anywhere

# Check existing PRDs for subsystem-level overlap
for prd in docs/PRD/*.md; do
  base=$(basename "$prd" .md)
  [[ "$base" =~ ^217- ]] && continue
  echo "=== $base ==="
  echo "$ISSUE_TITLE" | grep -oE '\w+' | while read -r word; do
    head -20 "$prd" | grep -qi "\b$word\b" && echo "  overlap:$word"
  done
done

# Check existing scene for current light types
grep -E 'SpotLight3D|OmniLight3D|DirectionalLight3D' scenes/street/street.tscn
```

## Key Pitfalls

| Pitfall | Resolution |
|---------|-----------|
| Proposing hallucination-driven parameters in #217 itself | Check issue body for explicit deferral language like "本Issue只做基础..." |
| Listing all subsystems under one "visual system" section | Subdivide Section 4 into 4.1/4.2/4.3/4.n per subsystem |
| One experiment covering all subsystems | Each subsystem needs its own focused experiment |
| Not noticing the existing parameter contract (from #214) | Search for `get_hallucination_params` or similar mapping functions in worldview/state controllers |
| Deconflicting at issue level instead of subsystem level | Check overlap per subsystem — one may overlap while others don't |

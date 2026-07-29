# Neon Cyber Visual System

> Reference: ../DESIGN/289-neon-visual.md

## Overview

A pure visual layer for Mini Pong using Godot 4.x built-in effects:
WorldEnvironment glow/bloom, GPUParticles2D ball trail, ShaderMaterial canvas_item
edge glow, and ColorRect score flash. Zero third-party dependencies.

## Design Principles

| # | Principle | Explanation |
|---|-----------|-------------|
| 1 | Pure visual layer | No game logic changes |
| 2 | Leverage existing infra | Forward+ and glow enabled in #301 |
| 3 | Minimal intrusion | Standalone resource files, no scene hierarchy changes |
| 4 | 2D convention | canvas_item shaders, GPUParticles2D (not 3D) |

## Color Constants

```gdscript
const PLAYER_NEON_BLUE = Color(0.29, 0.56, 0.85, 1)  # #4a90d9
const AI_NEON_RED      = Color(1.0, 0.2, 0.33, 1)     # #ff3355
const TRAIL_PURPLE     = Color(0.53, 0.2, 1.0, 1)     # #8833ff
const CENTER_LINE      = Color(0.4, 0.6, 0.9, 0.5)    # semi-transparent blue
const BG_COLOR_LINEAR  = Color(0.039, 0.039, 0.071, 1) # #0a0a12
```

## WorldEnvironment Configuration

File: `scenes/world_environment.tscn`

| Property | Value | Purpose |
|----------|-------|---------|
| glow_enabled | true | Enable glow post-processing |
| glow_intensity | 0.6 | Overall glow strength |
| glow_bloom | 0.8 | Bloom threshold — only pixels > 0.8 brightness bloom |
| background_color | #0a0a12 | Dark blue-black background |

## Edge Glow Shader

File: `gdscripts/neon_glow.gdshader` (canvas_item mode)

Uniforms:
- `glow_color` (#4a90d9 default, override per-element)
- `glow_width` (3.0, range 1.0–10.0)
- `glow_intensity` (1.0, range 0.0–2.0)

Algorithm: Edge detection via neighbor alpha difference → overlay glow_color outside edge.

## Ball Trail System

File: `gdscripts/ball_trail.gd` (attached as child of ball)

| Constant | Value | Purpose |
|----------|-------|---------|
| MIN_SPEED_FOR_TRAIL | 20.0 | Below this speed, no particles |
| MAX_SPEED_FOR_TRAIL | 600.0 | Max speed for emission rate normalization |

Behavior: Reads `get_parent().velocity.length()` in `_process()`. If speed < 20.0, particles stop.
Otherwise emission rate proportional to speed (0.3–1.0 range).

Particles use `particle_material.tres` (ParticleProcessMaterial):
- lifetime = 0.5s, spread = 15°
- Color ramp: gradient_neon.tres (blue #4a90d9 → purple #8833ff)

## Score Flash

File: `gdscripts/score_flash.gd`

| Signal | Source | Behavior |
|--------|--------|----------|
| score_changed(side: String) | Scoring system (future) | Flash blue for "player", red for "ai" |

Flash: Full-screen ColorRect overlay → 0.2s fade via `create_tween()`.
Old tweens killed on new flash (prevents overlap).

## Data Flows

### Game Start → Visual Init
load project.godot (clear_color) → load world_environment.tscn (glow/bloom) → compile shaders/scripts → ready

### Ball Movement → Trail
_physics_process() updates velocity → ball_trail.gd._process() reads speed → GPUParticles2D emits → gradient particles render

### Score → Flash
score_changed signal → _on_score_changed(side) → flash(color) → create_tween() → 0.2s fade out

### Edge Glow
ShaderMaterial applied to Sprite2D → fragment shader detects edge → overlays glow_color → WorldEnvironment bloom post-processes

## Integration Points

| Component | Connected To | Via |
|-----------|-------------|-----|
| Ball trail | Ball CharacterBody2D | get_parent().velocity |
| Ball glow | Ball Sprite2D | ShaderMaterial (neon_glow.gdshader) |
| Player paddle glow | Paddle Sprite2D | ShaderMaterial, glow_color=#4a90d9 |
| AI paddle glow | AI Paddle Sprite2D | ShaderMaterial, glow_color=#ff3355 |
| Score flash | Scoring system | score_changed signal |
| Center line | Main scene | Line2D child node |
| Background | Rendering pipeline | WorldEnvironment + project.godot clear_color |
| Bloom | Forward+ renderer | glow_bloom=0.8 threshold |

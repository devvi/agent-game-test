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

## Neon Label Style — NeonStyle（#392, 2026-08-13）

霓虹 HUD 的描边 + 微投影样式由 `gdscripts/ui_neon_style.gd`（`class_name NeonStyle`，静态工具）统一提供，
供 #388/#390/#391 复用保证全 UI 视觉一致：

| 属性 | 默认值 | 说明 |
|------|--------|------|
| `font_color` | 调用方传入 | 本体色（蓝 #4a90d9 / 红 #ff3355 / 信息条中性色） |
| `font_outline_color` | = 本体色 | 描边色默认同本体色（霓虹辉光感） |
| `outline_size` | 6px | `HUD_OUTLINE_SIZE`（taste-draft 可调 4–6） |
| `font_shadow_color` | 半透明黑 (0,0,0,0.6) | 微投影而非重阴影（克制优先） |
| `shadow_offset_x/y` | 2px | `HUD_SHADOW_OFFSET_*`（taste-draft） |

**设计约束**：
- 默认字体 + Label 主题覆盖（`add_theme_*_override`），零第三方字体/license 成本
- headless 安全：测试用 `label.get("theme_override_...")` 断言（GDD16 已知 `get_theme_font_size` headless 返回 0）
- 样式数值（描边粗细/投影偏移/信息条配色）为 taste-draft 占位，集中在 `constants.gd` `HUD_*` 组，human-review 可直接微调

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

File: `gdscripts/score_flash.gd`, instanced as child of `Main.tscn`

| Signal | Source | Behavior |
|--------|--------|----------|
| `scored(winner)` | ScoringManager | Flash blue for "player", red for "ai" |

The `ScoringManager → ScoreFlash` signal chain is active as of #295. ScoreFlash is a Node
with a full-screen ColorRect child in `Main.tscn`.

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
| WorldEnvironment | Main.tscn | instance of world_environment.tscn (#295) |
| Score flash | ScoringManager | scored signal → flash(color) → 0.2s fade |
| Center line | Main scene | Line2D child node |
| Background | Rendering pipeline | WorldEnvironment + project.godot clear_color |
| Bloom | Forward+ renderer | glow_bloom=0.8 threshold |

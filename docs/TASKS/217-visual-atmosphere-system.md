# Tasks: #217 — 基础视觉氛围系统 — Decal/GPUParticles

> Parent Issue: #217

| 字段 | 值 |
|------|----|
| Issue | #217 |
| 优先级 | P0 |
| 预估 | large (8-12 文件, ~450 行新增) |

## Overview

为雨夜普罗摩茨 `street.tscn` 实现 4 个视觉氛围子系统：GPUParticles3D 雨滴、Decal 霓虹灯光晕、GPUParticles3D 地面雾气、SpotLight3D+Decal 灯光锥体。本 Issue 只做静态 baseline 视觉效果，不实现幻觉驱动的动态变化（#19）。

详见 `docs/DESIGN/217-visual-atmosphere-system.md`。

## Phase 1: Asset Resources (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 1.1 | `rainy-night-prometheus/assets/materials/rain_drop.tres` | **新建** — BaseMaterial3D 雨滴材质（细长、半透明、发光） | 无 | P0 |
| 1.2 | `rainy-night-prometheus/assets/materials/neon_decal_orange.tres` | **新建** — 暖橙 #FF8844 Decal 材质 | 无 | P0 |
| 1.3 | `rainy-night-prometheus/assets/materials/neon_decal_purple.tres` | **新建** — 霓虹紫 #9944FF Decal 材质 | 无 | P0 |
| 1.4 | `rainy-night-prometheus/assets/materials/neon_decal_blue.tres` | **新建** — 冰蓝 #44AAFF Decal 材质 | 无 | P0 |
| 1.5 | `rainy-night-prometheus/assets/materials/fog_particle.tres` | **新建** — BaseMaterial3D 雾气粒子材质（半透明白） | 无 | P0 |
| 1.6 | `rainy-night-prometheus/assets/materials/light_cone_decal.tres` | **新建** — BaseMaterial3D 光锥光斑 Decal 材质（环形渐变） | 无 | P0 |

## Phase 2: GPUParticles3D Rain System (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 2.1 | `rainy-night-prometheus/gdscripts/rain_particles.gd` | **新建** — 雨滴粒子控制器 | 1.1 | P0 |
| 2.2 | `rainy-night-prometheus/scenes/street/street.tscn` | **修改** — 添加 `RainParticles` 节点 (GPUParticles3D) | 2.1 | P0 |

### 2.1 rain_particles.gd 实现要求
- `@export` 参数: `amount` (1000), `lifetime` (2.0s), `initial_velocity` (8.0), `wind_strength` (0.5), `spread_angle` (10°), `emission_box` (12,8,10), `rain_color` (0.7,0.8,1.0,0.6)
- `_ready()`: headless 防护 → 创建 GPUParticles3D → 配置材质（BaseMaterial3D, billboard=Y, scale_3d, 细长形状 0.02×0.3×0.02）→ 配置发射器参数 → 应用风效果 → 添加随机性
- 方法: `set_wind(strength)`, `set_density(factor)`, `set_emitting(active)`

## Phase 3: Decal Neon Light Halos (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 3.1 | `rainy-night-prometheus/gdscripts/neon_decal_controller.gd` | **新建** — 霓虹灯光晕 Decal 控制器 | 1.2, 1.3, 1.4 | P0 |
| 3.2 | `rainy-night-prometheus/scenes/street/street.tscn` | **修改** — 添加 `NeonDecals` 节点 | 3.1 | P0 |

### 3.1 neon_decal_controller.gd 实现要求
- `@export` 参数: `decal_positions` (3个地面位置), `decal_extents` (0.8,0.05,0.8), `colors` (暖橙/霓虹紫/冰蓝), `color_cycle_time` (3s), `color_transition_time` (0.5s), `base_color_index` (0)
- `_ready()`: headless 防护 → 在每位置创建 Decal → 创建 BaseMaterial3D → 设置初始颜色 → 启动 Timer 循环切换
- 方法: `switch_color(index)`, `get_current_color()`, `set_emission_strength()`, `stop_color_cycle()`, `resume_color_cycle()`
- 颜色切换: Tween 0.5s 过渡，Timer 3s 触发下一个

## Phase 4: GPUParticles3D Ground Fog (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 4.1 | `rainy-night-prometheus/gdscripts/ground_fog.gd` | **新建** — 地面雾气控制器 | 1.5 | P0 |
| 4.2 | `rainy-night-prometheus/scenes/street/street.tscn` | **修改** — 添加 `GroundFog` 节点 (GPUParticles3D) | 4.1 | P0 |

### 4.1 ground_fog.gd 实现要求
- `@export` 参数: `amount` (300), `lifetime_min` (5.0), `lifetime_max` (8.0), `particle_size_min` (0.3), `particle_size_max` (1.0), `drift_speed` (0.2), `height_limit` (0.5), `fog_color` (1,1,1,0.15), `emission_box` (12,0.1,10)
- `_ready()`: headless 防护 → 创建 GPUParticles3D → 配置材质（半透明白）→ 配置 emitter BOX → 配置 lifetime 随机 → 配置速度/散度 → 透明度 0.15
- 方法: `set_density(factor)`, `set_opacity(alpha)`, `set_emitting(active)`

## Phase 5: SpotLight3D+Decal Light Cone (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 5.1 | `rainy-night-prometheus/gdscripts/light_cone_controller.gd` | **新建** — 灯光锥体控制器 | 1.6 | P0 |
| 5.2 | `rainy-night-prometheus/scenes/street/street.tscn` | **修改** — 替换 OmniLight3D 为 SpotLight3D，添加地面 Decal | 5.1 | P0 |

### 5.1 light_cone_controller.gd 实现要求
- `@export` 参数: `spot_angle` (60°), `spot_attenuation` (1.0), `light_color` (1,0.9,0.6), `light_energy` (1.5), `light_range` (8.0), `decal_extents` (0.6,0.02,0.6), `decal_color` (1,0.9,0.6,0.4)
- `_ready()`: headless 防护 → 创建 SpotLight3D → 配置参数 → 替换/删除父节点下的 OmniLight3D → 创建地面 Decal 光斑 → 配置环形渐变材质
- 方法: `set_energy(value)`, `set_spot_color(color)`, `flicker(enable)` (占位)

## Phase 6: Street Scene Integration (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 6.1 | `rainy-night-prometheus/scenes/street/street.tscn` | **修改** — 添加 Visual Atmosphere 节点组 | 2.2, 3.2, 4.2, 5.2 | P0 |

### 6.1 street.tscn 修改细则
- 在 `Environments` 节点下添加:
  - `RainParticles` (GPUParticles3D) — 位置 (0, 6, 0)
  - `NeonDecals` (Node3D) — 脚本 `neon_decal_controller.gd`
  - `GroundFog` (GPUParticles3D) — 位置 (0, 0, 0)
  - 在 `Environments/Streetlamp` 下添加 `LightCone` (Node3D) — 脚本 `light_cone_controller.gd`
- 删除 `Environments/OmniLight3D`（由 SpotLight3D 替代）

## Phase 7: Validation (P0)

| Step | 文件 | 变更 | 前置 | 优先级 |
|------|------|------|------|--------|
| 7.1 | 终端 | `godot --path rainy-night-prometheus/ --headless --quit` | 6.1 | P0 |
| 7.2 | 终端 | 手动验证 4 个子系统初始化无报错 | 7.1 | P0 |

## Dependency Graph

```
Phase 1 (Asset Resources)
├─ 1.1 rain_drop.tres ──────────┐
├─ 1.2-1.4 neon_decal_*.tres ───┤
├─ 1.5 fog_particle.tres ───────┤
└─ 1.6 light_cone_decal.tres ───┤
                                 │
Phase 2 (Rain)  ←── 1.1         │
├─ 2.1 rain_particles.gd        │
└─ 2.2 Add to street.tscn       │
                                 │
Phase 3 (Decal) ←── 1.2-1.4     │
├─ 3.1 neon_decal_controller.gd  │
└─ 3.2 Add to street.tscn       │
                                 │
Phase 4 (Fog)  ←── 1.5          │
├─ 4.1 ground_fog.gd             │
└─ 4.2 Add to street.tscn       │
                                 │
Phase 5 (Light Cone) ←── 1.6    │
├─ 5.1 light_cone_controller.gd  │
└─ 5.2 Add to street.tscn       │
                                 │
Phase 6 (Integration) ───────────┘
├─ 6.1 street.tscn Atmosphere group
│
Phase 7 (Validation)
└─ 7.1-7.2 headless --quit
```

## Summary: Changed Files

| 文件 | 变更类型 | 预估行数 |
|------|----------|----------|
| `rainy-night-prometheus/gdscripts/rain_particles.gd` | 新增 | ~100 |
| `rainy-night-prometheus/gdscripts/neon_decal_controller.gd` | 新增 | ~120 |
| `rainy-night-prometheus/gdscripts/ground_fog.gd` | 新增 | ~100 |
| `rainy-night-prometheus/gdscripts/light_cone_controller.gd` | 新增 | ~90 |
| `rainy-night-prometheus/assets/materials/rain_drop.tres` | 新增 | ~20 |
| `rainy-night-prometheus/assets/materials/neon_decal_orange.tres` | 新增 | ~20 |
| `rainy-night-prometheus/assets/materials/neon_decal_purple.tres` | 新增 | ~20 |
| `rainy-night-prometheus/assets/materials/neon_decal_blue.tres` | 新增 | ~20 |
| `rainy-night-prometheus/assets/materials/fog_particle.tres` | 新增 | ~20 |
| `rainy-night-prometheus/assets/materials/light_cone_decal.tres` | 新增 | ~20 |
| `rainy-night-prometheus/scenes/street/street.tscn` | 修改 | ±50 |
| `docs/DESIGN/217-visual-atmosphere-system.md` | 新增 | ~350 |
| `docs/TASKS/217-visual-atmosphere-system.md` | 新增 | ~80 |

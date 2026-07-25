# Design: #217 — 基础视觉氛围系统 — Decal/GPUParticles

> Parent Issue: #217
> Agent: plan-agent
> Date: 2026-07-25

---

## 1. Architecture Overview

### Core Idea

为雨夜普罗摩茨街道场景（`street.tscn`）添加 4 个视觉氛围子系统：GPUParticles3D 雨滴、Decal 霓虹灯光晕、GPUParticles3D 地面雾气、SpotLight3D+Decal 组合灯光锥体。所有组件实现**静态 baseline** 视觉效果，为 #19 的幻觉驱动动态变化预留参数入口。脚本放置于 `rainy-night-prometheus/gdscripts/` 下，不修改根项目脚本。

**核心设计原则：**
1. **四组件独立运行** — 每个子系统有独立脚本和节点，互不依赖，可单独启用/禁用
2. **静态 baseline 约束** — 本 Issue 不实现任何由外部参数（hallucination 等级）驱动的动态变化；所有参数为固定初始值
3. **可扩展参数设计** — 所有可调参数（density, wind_strength, glow_color, opacity 等）均以 `@export` 暴露，供 #19 在运行时通过脚本修改
4. **Headless 安全** — 所有组件在 headless 模式下跳过初始化或静默降级，不报错
5. **Rainy Night Prometheus 子项目隔离** — 新增文件全部位于 `rainy-night-prometheus/` 下，与根项目 `gdscripts/` 分离

### Data Flow

```ascii
street.tscn 场景加载 (_ready)
    │
    ├── rain_particles.gd (child: GPUParticles3D)
    │     └── _ready()
    │           ├── if headless: return
    │           ├── 创建 GPUParticles3D 节点
    │           ├── 设置 particle_material (BaseMaterial3D, 细长雨滴形状)
    │           ├── 设置 amount=1000, lifetime=2.0
    │           ├── 设置 emission_shape=BOX, box_extents=(12, 8, 10)
    │           ├── 设置 direction=(0,-1,0), initial_velocity=8.0
    │           ├── 设置 gravity=(wind_x, -9.8, wind_z)  # 风效果
    │           └── 设置 randomness (angle, scale, velocity)
    │
    ├── neon_decal_controller.gd (children: Decal × N)
    │     └── _ready()
    │           ├── if headless: return
    │           ├── 在指定地面位置创建 Decal 节点
    │           ├── 创建 BaseMaterial3D (emission_enabled, alpha)
    │           ├── 设置颜色为暖橙 #FF8844 (baseline)
    │           ├── 启动定时器 → 每 3s 循环切换颜色
    │           └── 暴露 switch_color() 接口供外部调用
    │
    ├── ground_fog.gd (child: GPUParticles3D)
    │     └── _ready()
    │           ├── if headless: return
    │           ├── 创建 GPUParticles3D 节点
    │           ├── 设置 particle_material (半透明白色渐变)
    │           ├── 设置 amount=300, lifetime=5.0-8.0
    │           ├── 设置 emission_shape=BOX, box_extents=(12, 0.1, 10)
    │           ├── 设置 direction=(0,0,0) [随机散度]
    │           ├── 设置速度 0.2 m/s, 大小 0.5-0.8
    │           └── 设置 modulate.a=0.15
    │
    └── light_cone_controller.gd (child: SpotLight3D + Decal)
          └── _ready()
                ├── if headless: return
                ├── 替换/创建 SpotLight3D (代替 OmniLight3D)
                ├── 设置 spot_angle=60°, spot_attenuation=1.0
                ├── 设置 light_color=暖黄 (1,0.9,0.6), energy=1.5
                ├── 设置 range=8
                └── 在地面创建 Decal 光斑 (环形渐变)
                      └── 材质: 半透明环形渐变, emission
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| 雨滴粒子系统 | 单 GPUParticles3D + BaseMaterial3D | MVP 阶段单层足够；分层方案（3 层）过于奢侈 |
| 霓虹灯光晕 | 独立 Decal 节点 + 动态材质颜色 | Godot Decal 原生支持；霓虹灯数量少（≤3），手动放置成本低 |
| 地面雾气 | GPUParticles3D + 半透材质 | 标准用法，性能高效；参数暴露供 #19 扩展 |
| 灯光锥体 | SpotLight3D 替换 OmniLight3D + Decal 光斑 | 雨滴穿过光锥时自动被照亮；光锥底面 Decal 提供视觉光斑 |
| 头部兼容性 | `OS.has_feature("headless")` 防护 | Godot headless 模式缺少 GPU 上下文，粒子系统初始化需跳过 |
| 参数暴露方式 | `@export` 注解 | Godot 4 原生支持编辑器可视化编辑和运行时修改 |
| 颜色切换机制 | Tween + Timer 组合 | 平滑过渡（0.5s），Timer 循环 3s 切换 |
| 风效果实现 | `gravity.x` 偏移模拟 | 最简单有效的方式；`gravity = (wind_x, -9.8, wind_z)` |

---

## 2. Engine Layer 变更

> 本 Issue 不修改任何 Engine Layer 文件（`gdscripts/` 根目录下的 autoload）。所有新增代码位于 `rainy-night-prometheus/gdscripts/`。

### 状态系统变更

无。本 Issue 不新增 state 字段、不修改 autoload。所有参数均为 `@export` 本地设置，不依赖全局状态。

### 现有 autoload 接口消费

| Autoload | 接口 | 消费方式 | 触发条件 |
|----------|------|----------|----------|
| RainController (假设) | `rain_intensity` | 读取 baseline 值（静态）；#19 中会被动态修改 | `_ready()` 初始化时读取 |
| WorldviewController | `get_hallucination_params()` | 本 Issue **不消费**；#19 中由 hallucination 驱动脚本修改粒子参数 | 本 Issue 不触发 |

---

## 3. Entity Layer 变更

> 场景节点变更 — `street.tscn`

### 新增节点组: Visual Atmosphere

在 `street.tscn` 的 `Environments` 节点下新增以下子节点：

| 节点名称 | 类型 | 父节点 | 脚本 | 说明 |
|----------|------|--------|------|------|
| `RainParticles` | `GPUParticles3D` | `Environments` | `rain_particles.gd` | 雨滴粒子发射器 |
| `NeonDecals` | `Node3D` | `Environments` | `neon_decal_controller.gd` | 霓虹灯光晕控制器（管理多个 Decal 子节点） |
| `GroundFog` | `GPUParticles3D` | `Environments` | `ground_fog.gd` | 地面雾气粒子发射器 |
| `StreetLampLightCone` | `Node3D` | `Environments/Streetlamp` | `light_cone_controller.gd` | 路灯灯光锥体控制器 |

### 现有节点修改

| 节点 | 当前配置 | 修改内容 |
|------|----------|----------|
| `Environments/OmniLight3D` | 暖黄, energy=0.8, range=10 | **替换为** `SpotLight3D`（由 `light_cone_controller.gd` 管理） |
| `Environments/NeonSign` | Label3D, 静态颜色 | **无修改**；Decal 作为独立节点跟随其位置 |

---

## 4. Data Layer 变更

### 新增常量/资源

| 资源 | 路径 | 类型 | 用途 |
|------|------|------|------|
| `rain_drop.tres` | `rainy-night-prometheus/assets/materials/rain_drop.tres` | `BaseMaterial3D` | 雨滴粒子材质（细长、半透明、发光） |
| `neon_decal_orange.tres` | `rainy-night-prometheus/assets/materials/neon_decal_orange.tres` | `BaseMaterial3D` | 暖橙霓虹灯光晕 Decal 材质 |
| `neon_decal_purple.tres` | `rainy-night-prometheus/assets/materials/neon_decal_purple.tres` | `BaseMaterial3D` | 霓虹紫光晕 Decal 材质 |
| `neon_decal_blue.tres` | `rainy-night-prometheus/assets/materials/neon_decal_blue.tres` | `BaseMaterial3D` | 冰蓝光晕 Decal 材质 |
| `fog_particle.tres` | `rainy-night-prometheus/assets/materials/fog_particle.tres` | `BaseMaterial3D` | 雾气粒子材质（半透明白色渐变） |
| `light_cone_decal.tres` | `rainy-night-prometheus/assets/materials/light_cone_decal.tres` | `BaseMaterial3D` | 灯光锥体地面光斑 Decal 材质 |

### 颜色预设表

| 颜色名称 | Hex | RGB | 用途 |
|----------|-----|-----|------|
| 暖橙 | `#FF8844` | `(1.0, 0.533, 0.267)` | 霓虹灯光晕 baseline |
| 霓虹紫 | `#9944FF` | `(0.6, 0.267, 1.0)` | 颜色循环切换 |
| 冰蓝 | `#44AAFF` | `(0.267, 0.667, 1.0)` | 颜色循环切换 |

### 粒子参数预设表

| 参数 | 雨滴 | 雾气 |
|------|------|------|
| 粒子数量 | 1000 | 300 |
| 生命周期 | 2.0s | 5.0-8.0s |
| 初始速度 | 8.0 m/s | 0.2 m/s |
| 速度随机性 | ±30% | ±50% |
| 粒子大小 | (0.02, 0.3, 0.02) | 0.5-0.8 单位 |
| 大小随机性 | ±50% | ±50% |
| 发射区域 | Box (12, 8, 10) | Box (12, 0.1, 10) |
| 方向 | (0, -1, 0) | (0, 0, 0) 随机散度 |
| 重力 | (0.5, -9.8, 0) | 无 |
| 透明度 | 1.0 | 0.15 |

---

## 5. Render Layer 变更

### 5.1 GPUParticles3D 雨滴系统

**文件：** `rainy-night-prometheus/gdscripts/rain_particles.gd`

```gdscript
# @export 参数:
@export var amount: int = 1000                    # 粒子数量
@export var lifetime: float = 2.0                 # 生命周期 (s)
@export var initial_velocity: float = 8.0         # 下落速度 (m/s)
@export var wind_strength: float = 0.5            # 风力 (X轴偏移)
@export var spread_angle: float = 10.0            # 散度角度 (°)
@export var emission_box: Vector3 = Vector3(12, 8, 10)  # 发射区域
@export var rain_color: Color = Color(0.7, 0.8, 1.0, 0.6)  # 雨滴颜色

# 内部状态
var _particles: GPUParticles3D
var _material: BaseMaterial3D

# 方法:
func _ready() -> void
    # headless 防护 → 跳过粒子初始化
    # 创建 GPUParticles3D 节点
    # 配置粒子材质（BaseMaterial3D: billboard, scale_3d, 细长形状）
    # 配置发射器参数（amount, lifetime, box extents, direction, velocity）
    # 应用风效果（gravity.x = wind_strength）
    # 添加随机性
    # 添加到场景树

func set_wind(strength: float) -> void
    # 运行时修改风力（供 #19 使用）
    # _particles.gravity.x = strength

func set_density(factor: float) -> void
    # 运行时修改密度（供 #19 使用）
    # _particles.amount = int(amount * clamp(factor, 0.0, 2.0))

func set_emitting(active: bool) -> void
    # 开关粒子发射
    # _particles.emitting = active
```

**粒子材质配置：**
- `BaseMaterial3D`: `billboard_mode = BillboardY`
- `particle_flag_use_scale_3d = true`
- 缩放 `Vector3(0.02, 0.3, 0.02)`（细长雨滴形状）
- `albedo_color = Color(0.7, 0.8, 1.0, 0.6)`（淡蓝半透明）
- `emission_enabled = true`, `emission = Color(0.5, 0.6, 0.8)`
- `transparency = Alpha`（使用 alpha 混合）

### 5.2 Decal 霓虹灯光晕

**文件：** `rainy-night-prometheus/gdscripts/neon_decal_controller.gd`

```gdscript
# @export 参数:
@export var decal_positions: Array[Vector3] = [
    Vector3(4.5, 0.0, 3.0),   # 霓虹灯地面位置
    Vector3(4.5, 0.0, 2.5),   # 第二个光晕
    Vector3(4.5, 0.0, 3.5),   # 第三个光晕
]
@export var decal_extents: Vector3 = Vector3(0.8, 0.05, 0.8)  # Decal 尺寸
@export var colors: Array[Color] = [
    Color(1.0, 0.533, 0.267),  # 暖橙 #FF8844
    Color(0.6, 0.267, 1.0),    # 霓虹紫 #9944FF
    Color(0.267, 0.667, 1.0),  # 冰蓝 #44AAFF
]
@export var color_cycle_time: float = 3.0      # 颜色切换间隔 (s)
@export var color_transition_time: float = 0.5 # 过渡时间 (s)
@export var base_color_index: int = 0          # baseline 颜色索引

# 内部状态
var _decals: Array[Decal] = []
var _decal_materials: Array[BaseMaterial3D] = []
var _color_timer: Timer
var _current_color_index: int = 0

# 方法:
func _ready() -> void
    # headless 防护 → 跳过
    # 在 decal_positions 每个位置创建 Decal 节点
    # 为每个 Decal 创建 BaseMaterial3D（emission, alpha）
    # 设置初始颜色为 colors[base_color_index]
    # 启动颜色切换定时器

func _on_color_cycle_timeout() -> void
    # 使用 Tween 将颜色过渡到下一个
    # _current_color_index = (_current_color_index + 1) % colors.size()

func switch_color(index: int) -> void
    # 外部调用接口：切换到指定颜色
    # 参数范围 0..colors.size()-1

func get_current_color() -> Color
    # 返回当前颜色

func set_emission_strength(strength: float) -> void
    # 运行时修改 Decal 发射强度（供 #19 使用）

func stop_color_cycle() -> void
    # 停止颜色循环（冻结在当前颜色）

func resume_color_cycle() -> void
    # 恢复颜色循环
```

### 5.3 GPUParticles3D 地面雾气

**文件：** `rainy-night-prometheus/gdscripts/ground_fog.gd`

```gdscript
# @export 参数:
@export var amount: int = 300                     # 粒子数量
@export var lifetime_min: float = 5.0             # 最小生命周期 (s)
@export var lifetime_max: float = 8.0             # 最大生命周期 (s)
@export var particle_size_min: float = 0.3        # 最小粒子大小
@export var particle_size_max: float = 1.0        # 最大粒子大小
@export var drift_speed: float = 0.2              # 飘移速度 (m/s)
@export var height_limit: float = 0.5             # 高度限制 (m)
@export var fog_color: Color = Color(1, 1, 1, 0.15)  # 雾气颜色+透明度
@export var emission_box: Vector3 = Vector3(12, 0.1, 10)  # 发射区域

# 内部状态
var _particles: GPUParticles3D
var _material: BaseMaterial3D

# 方法:
func _ready() -> void
    # headless 防护 → 跳过
    # 创建 GPUParticles3D 节点
    # 配置粒子材质（半透明白色渐变，3D 缩放）
    # 配置 emitter: BOX, (12, 0.1, 10), 地面高度
    # 配置 lifetime 随机化 (5-8s)
    # 配置速度 0.2 m/s, 随机散度 360°
    # 配置 modulate.a = 0.15
    # 添加到场景树

func set_density(factor: float) -> void
    # 运行时修改密度（供 #19 使用）
    # _particles.amount = int(amount * clamp(factor, 0.0, 2.0))

func set_opacity(alpha: float) -> void
    # 运行时修改透明度（供 #19 使用）
    # _material.albedo_color.a = clamp(alpha, 0.0, 1.0)
    # _particles.modulate.a = clamp(alpha, 0.0, 1.0)

func set_emitting(active: bool) -> void
    # 开关雾效
```

**雾气粒子材质配置：**
- `BaseMaterial3D` 使用 `billboard_mode = BillboardY`
- `particle_flag_use_scale_3d = true`
- `albedo_color = Color(1, 1, 1, 0.15)`（半透明白）
- `transparency = Alpha`
- 粒子缩放：随机 0.3-1.0 通过 `scale_randomness` 控制
- **纹理提示：** 若无自定义纹理，使用程序化渐变圆点（通过 `_generate_fog_texture()` 在 `_ready()` 中生成）

### 5.4 SpotLight3D+Decal 组合灯光锥体

**文件：** `rainy-night-prometheus/gdscripts/light_cone_controller.gd`

```gdscript
# @export 参数:
@export var spot_angle: float = 60.0              # 光锥角度 (°)
@export var spot_attenuation: float = 1.0         # 衰减
@export var light_color: Color = Color(1, 0.9, 0.6)  # 暖黄
@export var light_energy: float = 1.5             # 亮度
@export var light_range: float = 8.0              # 照射距离
@export var decal_extents: Vector3 = Vector3(0.6, 0.02, 0.6)  # 地面光斑尺寸
@export var decal_color: Color = Color(1, 0.9, 0.6, 0.4)      # 光斑颜色

# 内部状态
var _spot_light: SpotLight3D
var _decal: Decal
var _decal_material: BaseMaterial3D

# 方法:
func _ready() -> void
    # headless 防护 → 跳过
    # 创建 SpotLight3D 节点
    #   设置 spot_angle, spot_attenuation, light_color, energy, range
    #   设置父节点的位置偏移（路灯高度）
    #   设置方向 (0, -1, 0)
    #   查找并替换父节点下可能存在的 OmniLight3D（如找到则删除）
    # 创建 Decal 光斑节点
    #   设置 extents, 位置于 SpotLight3D 正下方地面
    #   创建 BaseMaterial3D（环形渐变, emission, alpha）
    # 添加到场景树

func set_energy(value: float) -> void
    # 运行时修改灯光亮度（供 #19 使用）

func set_spot_color(color: Color) -> void
    # 运行时修改灯光颜色（供 #19 使用）

func flicker(enable: bool) -> void
    # 本 Issue 不实现 — 占位接口供 #19 扩展
    pass
```

---

## 6. Input / UI Layer 变更

无。本 Issue 不涉及任何输入处理或 UI 变更。

---

## 7. Test Layer

### Test Structure

不创建独立的 GDScript 测试文件。验证通过以下方式完成：

| 验证方式 | 覆盖范围 |
|----------|----------|
| `godot --path rainy-night-prometheus/ --headless --quit` | 所有脚本无编译/运行时错误 |
| 场景编辑器手动检查 | 粒子可见性、Decal 投射、灯光效果 |
| `OS.has_feature("headless")` 防护 | headless 模式静默降级 |

### 验证清单（集成到 street.gd 或单独的 verify_atmosphere.gd）

| # | 验证项 | 方法 |
|---|--------|------|
| TC1 | 雨滴粒子≥1000，发射区域覆盖场景 | `_particles.amount >= 1000`, `box_extents` 正确 |
| TC2 | 雨滴有风效果（gravity.x ≠ 0） | `_particles.gravity.x > 0` |
| TC3 | 霓虹灯 Decal ≥3 个 | `_decals.size() >= 3` |
| TC4 | Decal 颜色可切换 ≥3 种 | `colors.size() >= 3` |
| TC5 | 雾气粒子高度 < 0.5 单位 | `height_limit <= 0.5` |
| TC6 | 雾气粒子数量 200-500 | `amount >= 200 and <= 500` |
| TC7 | SpotLight3D 存在且配置正确 | `_spot_light is SpotLight3D`, `spot_angle == 60°` |
| TC8 | 地面光斑 Decal 存在 | `_decal is Decal` |
| TC9 | Headless 模式下无报错 | `godot --headless --quit` exit code 0 |
| TC10 | 4 个子系统相互独立（禁用任一不影响其他） | 逐个禁用验证 |

### Edge Cases

| # | 场景 | 预期行为 |
|---|------|----------|
| E1 | 粒子数量过高 (5000+) | 性能下降但无崩溃；`amount` 可在编辑器中调低 |
| E2 | Decal 与 CSG 渲染顺序冲突 | Decal 渲染在 CSG 之上，调整 `modulate.a` 降低冲突 |
| E3 | SpotLight3D 锥体顶部被裁剪 | 调整 `spot_angle` 至 45°-60°，`range` 至 5-8 |
| E4 | Headless 模式粒子 init | 脚本在 `_ready()` 中检查 `OS.has_feature("headless")` 后跳过 |
| E5 | 雾气粒子穿墙/超出场景边界 | 缩小 `box_extents` 至场景有效范围 |
| E6 | 室内区域被雨滴粒子覆盖 | 限制发射区域到室外空间 |

### Failure Paths

| # | 失败场景 | 防护措施 |
|---|----------|----------|
| F1 | GPUParticles3D.new() 在 headless 返回 null | `if is_instance_valid(_particles):` 检查 |
| F2 | preload 材质路径错误 | 使用 `load()` + `if resource:` 验证 |
| F3 | OmniLight3D 替换后场景照明变化 | 逐一验证每个受影响节点 |
| F4 | Decal 材质未找到 | `load()` 返回 null → `push_warning()` + 使用程序化生成材质降级 |

---

## 8. Files Changed（按层汇总）

### New Files — Rainy Night Prometheus Atmosphere

| File | Change | Est. Lines |
|------|--------|-----------|
| `rainy-night-prometheus/gdscripts/rain_particles.gd` | **新建** — GPUParticles3D 雨滴控制器 | ~100 |
| `rainy-night-prometheus/gdscripts/neon_decal_controller.gd` | **新建** — Decal 霓虹灯光晕控制器 | ~120 |
| `rainy-night-prometheus/gdscripts/ground_fog.gd` | **新建** — GPUParticles3D 地面雾气控制器 | ~100 |
| `rainy-night-prometheus/gdscripts/light_cone_controller.gd` | **新建** — SpotLight3D+Decal 灯光锥体 | ~90 |
| `rainy-night-prometheus/assets/materials/rain_drop.tres` | **新建** — 雨滴粒子材质 | ~20 |
| `rainy-night-prometheus/assets/materials/neon_decal_orange.tres` | **新建** — 暖橙 Decal 材质 | ~20 |
| `rainy-night-prometheus/assets/materials/neon_decal_purple.tres` | **新建** — 霓虹紫 Decal 材质 | ~20 |
| `rainy-night-prometheus/assets/materials/neon_decal_blue.tres` | **新建** — 冰蓝 Decal 材质 | ~20 |
| `rainy-night-prometheus/assets/materials/fog_particle.tres` | **新建** — 雾气粒子材质 | ~20 |
| `rainy-night-prometheus/assets/materials/light_cone_decal.tres` | **新建** — 光锥光斑 Decal 材质 | ~20 |

### Modified Files

| File | Change | Est. Lines |
|------|--------|-----------|
| `rainy-night-prometheus/scenes/street/street.tscn` | **修改** — 添加 Atmosphere 节点组，替换 OmniLight3D 为 SpotLight3D | ±50 |
| `rainy-night-prometheus/assets/materials/` | **创建目录** | ±0 |

### Documentation Files

| File | Change | Est. Lines |
|------|--------|-----------|
| `docs/DESIGN/217-visual-atmosphere-system.md` | **新建** — 本文档 | ~350 |
| `docs/TASKS/217-visual-atmosphere-system.md` | **新建** — 任务分解 | ~80 |

---

## 9. Verification Checklist

- [x] PRD reviewed and 4 subsystems identified
- [x] Current scene (street.tscn) analyzed — has WorldEnvironment, DirectionalLight3D, OmniLight3D, NeonSign — NO particles/Decals
- [x] 4 scripts designed with `@export` parameters for #19 extensibility
- [x] Headless mode compatibility handled via `OS.has_feature("headless")` guard
- [x] Decal colors defined: 暖橙 #FF8844, 霓虹紫 #9944FF, 冰蓝 #44AAFF
- [x] Particle parameters baseline values defined (rain: 1000, fog: 300)
- [x] SpotLight3D replaces OmniLight3D for raindrop visibility through cone
- [x] All new files under `rainy-night-prometheus/` subdirectory
- [x] No modification to root `gdscripts/` autoloads
- [x] Edge cases documented (6 scenarios)
- [x] Failure paths documented (4 scenarios)

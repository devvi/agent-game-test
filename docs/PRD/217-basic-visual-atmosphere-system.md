# Research: [Feature] 基础视觉氛围系统 — Decal/GPUParticles

> Parent Issue: #217
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

雨夜普罗摩茨项目骨架（#213）已建立，但**没有任何视觉氛围系统**。当前场景（以 `scenes/street/street.tscn` 为例）仅有基础设施级别的视觉配置：

| 组件 | 状态 | 备注 |
|------|:----:|------|
| WorldEnvironment | ✅ 已有 | 含 glow 配置（glow_enabled=true, glow_intensity=0.9）、深蓝背景色 |
| DirectionalLight3D | ✅ 已有 | 暗蓝色（0.3, 0.4, 0.7），energy=0.3，模拟月光 |
| OmniLight3D | ✅ 已有 | 暖橙色（1, 0.7, 0.3），energy=0.8，range=10，模拟路灯 |
| NeonSign Label3D | ✅ 已有 | 静态文字+modulate 颜色（街道脚本通过 5-state tone 动态切换） |
| RainController | ✅ 逻辑层 | `gdscripts/rain_controller.gd` — 管理 rain_intensity 参数（hope 逆映射），但**不驱动任何视觉粒子** |
| WorldviewController hallucination map | ✅ 参数层 | `get_hallucination_params()` 定义了 `rain_density`、`light_flicker` 等参数映射，但**无执行层** |

**关键缺失：**

1. **无 GPUParticles 雨滴系统** — RainController 计算 rain_intensity（0.0–1.0），但没有任何粒子发射器将数值转换为可见雨滴
2. **无 Decal 霓虹灯光晕** — NeonSign 仅作为 Label3D 文字存在，没有投射到地面的光晕/辉光 Decal
3. **无 GPUParticles 地面雾气** — 场景缺乏地面薄雾/水汽效果
4. **无 SpotLight3D+Decal 组合灯光锥体** — 路灯使用 OmniLight3D，但无可见光锥，雨滴穿过时不可见
5. **无视觉-状态联动机制** — 虽然 WorldviewController 已定义 hallucination→visual 参数映射，但粒子密度、灯光闪烁等执行层尚未建立

### Expected Behavior

按 Issue #217 验收条件：

- [ ] GPUParticles 雨滴系统（≥1000 粒子，随机方向密度，风效果）
- [ ] Decal 霓虹灯光晕投射到地面（至少 3 种颜色动态变化）
- [ ] GPUParticles 地面雾气（高度 < 0.5 单位）
- [ ] SpotLight3D+Decal 组合灯光锥体，雨滴穿过可见
- [ ] 本 Issue 只做基础视觉效果，幻觉等级驱动的动态变化在 #19 中扩展
- [ ] `--headless --quit` 无脚本错误

### Scope Boundaries vs Overlapping PRDs

| PRD | Covers | NOT covered (left to #217) |
|-----|--------|---------------------------|
| **#213 (Scaffold)** | 项目骨架、目录结构、symlink 复用、project.godot 基础配置 | ❌ 无视觉氛围相关内容 |
| **#214 (Narrative Architecture)** | 幻觉等级-视觉参数映射表（rain_density, light_flicker, vignette 等 0–10 映射） | ❌ 只定义了**参数契约**，未实现粒子/Decal/灯光执行层 |
| **#218 (Interactive Area Visual Feedback)** | 鼠标悬停辉光着色器、NPC 指示器、交互区域视觉反馈 | ❌ 聚焦交互 UI 层，非环境氛围 |
| **#219 (Sound & BGM)** | 环境音循环、BGM 系统、脚步声 | ❌ 纯音频，不覆盖视觉粒子/Decal |

**关键声明：**
- #214 的 `WorldviewController.get_hallucination_params()` 定义了参数契约（rain_density 等），#217 负责**创建执行层基础设施**
- #217 只实现**静态/基础**视觉效果（雨滴始终以 baseline 密度落下、霓虹灯静态光晕）
- 幻觉等级驱动的动态变化（雨密度随幻觉等级变强、灯光闪烁、雾气变浓）由 #19 在 #217 基础上扩展

---

## 2. Design Intent

### Why Do We Need This?

雨夜普罗摩茨的核心美学是**雨夜漫步的沉浸感**。当前场景虽已有浅蓝色 DirectionalLight（月光）和暖色 OmniLight，但缺乏雨夜的三个关键视觉要素：

1. **雨滴可见性** — 玩家在街上看不到雨滴落下，雨夜沉浸感为零
2. **霓虹灯光晕** — 霓虹灯招牌没有地面光晕，场景缺乏雨夜标志性的彩色地面反射
3. **地面雾气** — 雨夜地面通常有低矮雾气/水汽，增加场景层次感和神秘感
4. **灯光锥体** — 雨滴穿过灯光时应该被照亮，这是雨夜最标志性的视觉元素

### Why Change Now?

这是雨夜普罗摩茨视觉氛围的最底层建造。后续所有动态效果（幻觉驱动的雨密度变化 #19、场景-光照联动）都依赖本 Issue 建立的基础粒子/Decal/灯光基础设施。没有粒子发射器，幻觉参数 `rain_density` 就没有执行层。

### Previous Constraints

- 引擎：Godot **4.7.1** — 所有粒子系统使用 `GPUParticles3D`（非 CPUParticles3D），确保 GPU 性能优势
- 渲染器：**Forward+** — 已配置于 `rainy-night-prometheus/project.godot`，支持 GPU particles、Decal、glow
- 项目规模：MVP 阶段 — 粒子数量需平衡性能和视觉效果（室外雨滴 1000–5000 粒子，雾气 200–500 粒子）
- 命名约定：新增脚本使用 snake_case，节点使用 PascalCase，与现有规范一致
- 窗口尺寸：1920×1080（`project.godot` 已配置）
- **本 Issue 不做幻觉驱动动态变化** — 所有视觉参数为静态 baseline 值
- **本 Issue 的粒子/Decal 应设计为可被外部参数驱动** — 为 #19 的集成预留 API
- **本 Issue 仅用于 Rainy Night Prometheus 子项目** — 新增文件放置于 `rainy-night-prometheus/` 下

---

## 3. Impact Analysis

### Directly Affected Modules

| 文件/目录 | 模块 | 变更性质 |
|-----------|------|----------|
| `rainy-night-prometheus/gdscripts/rain_particles.gd` | GPUParticles 雨滴系统 | **新建** — 雨滴粒子控制器 |
| `rainy-night-prometheus/gdscripts/neon_decal_controller.gd` | Decal 霓虹灯光晕 | **新建** — 霓虹灯 Decal 管理 |
| `rainy-night-prometheus/gdscripts/ground_fog.gd` | GPUParticles 地面雾气 | **新建** — 地面雾气控制器 |
| `rainy-night-prometheus/gdscripts/light_cone_controller.gd` | SpotLight3D+Decal 组合 | **新建** — 灯光锥体控制器 |
| `rainy-night-prometheus/scenes/street/street.tscn` | 街道场景 | **修改** — 添加 GPUParticles3D、Decal、SpotLight3D 节点 |
| `rainy-night-prometheus/scenes/street/` | 场景目录 | **可能新增** — 场景变体或子场景文件 |
| `rainy-night-prometheus/assets/materials/` | 材质资源 | **可能新增** — Decal 材质、粒子材质 |
| `rainy-night-prometheus/project.godot` | 项目配置 | **可能修改** — 新增 autoload（如有全局管理器） |

### Indirectly Affected Modules

| 文件/模块 | 为什么受影响 |
|-----------|-------------|
| `gdscripts/worldview_controller.gd` | 其 `get_hallucination_params()` 的 `rain_density` 和 `light_flicker` 参数将**在 #19 中驱动**本 Issue 创建的粒子系统 |
| `gdscripts/rain_controller.gd` | 现有的 `rain_intensity` 计算逻辑可被本 Issue 的粒子系统消费（当前为孤立的数值层） |
| `gdscripts/scene_base.gd` | 未来可能需要为所有场景统一初始化氛围系统 |
| `rainy-night-prometheus/scenes/` 下的其他场景 | 街道场景是第一个接入场景；后续场景（办公室、地铁站等）应复用相同组件 |

### Data Flow Impact

```
场景加载 (street.tscn)
    → 初始化 GPUParticles3D 雨滴系统 (rain_particles.gd)
        → rain_particles 读取 RainController.rain_intensity（baseline 静态值）
        → 发射粒子（≥1000 个），应用风效果
    → 初始化 Decal 霓虹灯光晕 (neon_decal_controller.gd)
        → 在霓虹灯地面位置创建 Decal 节点
        → 设置 Decal 材质颜色（动态切换，≥3 种颜色）
    → 初始化 GPUParticles3D 地面雾气 (ground_fog.gd)
        → 在地面高度发射缓慢飘移的薄雾粒子
        → 粒子高度限制在 < 0.5 单位
    → 初始化 SpotLight3D+Decal 灯光锥体 (light_cone_controller.gd)
        → 在路灯位置创建 SpotLight3D + Decal 组合
        → 雨滴穿过光锥时被照亮（可见）
```

### Documents to Update

- [x] `docs/PRD/217-basic-visual-atmosphere-system.md`（本文档）
- [ ] `docs/DESIGN/217-basic-visual-atmosphere-system.md`（Plan 阶段创建）
- [ ] `docs/GAME_DESIGN/` — 在 "视觉氛围" 章节（如有）中记录本系统的设计
- [ ] `docs/PROJECT.md` — 更新已实现功能列表

---

## 4. Solution Comparison

### 4.1 GPUParticles 雨滴系统

#### Approach A: 单 GPUParticles3D + 自定义材质着色器（推荐）

- **Description：** 创建一个 `rain_particles.gd` 脚本管理单个 `GPUParticles3D` 节点。粒子材质使用 `BaseMaterial3D` 或自定义 Spatial Shader 模拟雨滴——使用细长粒子形状（沿 Y 轴拉伸）、半透明、发光、从高空落下。应用 `wind_effect` 参数（Vector2）使粒子略微倾斜。粒子数量 ≥1000，发射区域覆盖整个场景范围（~20×20 单位）。
- **Pros：**
  - Godot 4.7 原生支持 GPUParticles3D，性能优越（GPU 计算粒子物理）
  - 单粒子系统管理简单，属性暴露清晰
  - 可设置 `lifetime` 随机化，模拟雨滴下落时间差异
  - 可通过 `emitting=false/true` 控制开关
- **Cons：**
  - 需要编写着色器材质以获得逼真的雨滴形状（默认的 Point 或 Sharp 形状不够真实）
  - 粒子碰撞（雨滴打到地面/角色身上）增加了复杂度
- **Risk：** Low — GPUParticles3D 是 Godot 4 标准组件
- **Effort：** 1 script（~80 行）+ 1 着色器（~40 行）+ 场景配置

#### Approach B: 多个 GPUParticles3D 分层组合

- **Description：** 使用 2-3 层 GPUParticles3D 叠加：前景雨滴（近距离，大尺寸，快速）、远景雨幕（远距离，小尺寸，慢速）、雨幕背景（极远，半透明，用作天空雨幕）。
- **Pros：**
  - 分层效果更丰富，视觉深度感强
  - 每层可单独调整参数（密度、速度、风力响应）
- **Cons：**
  - 复杂度显著增加（3 个发射器 vs 1 个）
  - 性能消耗 3x，对 MVP 阶段过于奢侈
  - 调试和维护成本高
- **Risk：** Low but wasteful — MVP 阶段不需要分层雨滴
- **Effort：** 3 scripts + 3 材质配置

#### Approach C: CPUParticles3D（备选）

- **Description：** 使用 `CPUParticles3D` 代替 GPUParticles3D。CPU 粒子的优势是不依赖 GPU，兼容性更好，但粒子数量受 CPU 限制。
- **Pros：**
  - 无需 GPU 着色器支持
  - 粒子行为可由 GDScript 完全控制
- **Cons：**
  - ≥1000 粒子时 CPU 性能显著下降
  - Forward+ 渲染器已启用 GPU，没有理由回退 CPU
  - Godot 4 推荐 GPUParticles3D
- **Risk：** Medium — 性能瓶颈
- **Effort：** 1 script + 无着色器，但 CPU 开销大

**推荐：→ Approach A** — 单 GPUParticles3D 系统在 MVP 阶段足够提供沉浸式雨滴效果，且预留了 `emission_scale`/`amount`/`wind_strength` 等参数供 #19 的幻觉驱动使用。

---

### 4.2 Decal 霓虹灯光晕

#### Approach A: 独立 Decal 节点 + 动态材质颜色（推荐）

- **Description：** 为每个霓虹灯创建单独的 Decal 节点放置在霓虹灯正下方的地面位置。Decal 材质使用 `BaseMaterial3D`，设置 `albedo_color` 为霓虹灯颜色，`emission` 开启并设为同色，透明混合。颜色由 `neon_decal_controller.gd` 管理，支持 ≥3 种颜色的动态切换（暖橙、霓虹紫、冰蓝等）。Decal 的 `extents` 设置为覆盖光晕范围（~1×0.1×1 单位）。
- **Pros：**
  - 原生 Godot Decal 组件，无需额外安装
  - 地面投射精准，跟随地形起伏
  - 材质颜色动态切换简单——修改 `decal.albedo_color` 和 `decal.emission` 即可
  - Decal 支持透明度和淡入淡出动画
- **Cons：**
  - 每个霓虹灯需要独立 Decal 节点（手动放置）
  - 多个 Decal 叠加时可能导致渲染顺序问题
- **Risk：** Low — Godot 4 的 Decal 系统成熟稳定
- **Effort：** 1 script（~60 行）+ 场景中放置 3+ 个 Decal 节点

#### Approach B: 单 Decal + 程序化着色器变体

- **Description：** 创建一个自定义 Decal 着色器，支持单张 Decal 纹理中包含多个颜色区域，通过 UV 坐标或参数选择激活哪个区域的霓虹灯光晕。
- **Pros：**
  - 减少 Decal 节点数量（1 个代替多个）
  - 着色器可以实现更复杂的渐变/闪烁效果
- **Cons：**
  - 着色器编写调试复杂
  - 颜色切换不够灵活（需要修改纹理或 Uniform）
  - 光晕位置固定，不便于未来场景扩展
- **Risk：** Medium — 着色器调试耗时长
- **Effort：** 1 着色器（~50 行）+ 纹理制作

#### Approach C: 手动地面 MeshInstance3D + 发光材质

- **Description：** 不使用 Decal，而是在地面放置一个扁平的 `MeshInstance3D`（PlaneMesh），使用发光材质模拟光晕。
- **Pros：**
  - 完全控制光晕形状和颜色
  - 不受 Decal 的渲染顺序限制
- **Cons：**
  - 需要手动对齐地面高度
  - 不跟随地形的起伏
  - 比 Decal 方案更 hacky
- **Risk：** Low-Medium — 对齐问题在地面平坦时可控，但扩展性差
- **Effort：** 每个光晕 ~5 分钟手动放置

**推荐：→ Approach A** — 独立 Decal 节点方案最直接、最可控。霓虹灯数量在 MVP 阶段很少（≤5 个），手动放置每个 Decal 成本极低。

---

### 4.3 GPUParticles 地面雾气

#### Approach A: GPUParticles3D + 自定义雾气粒子（推荐）

- **Description：** 创建一个 `ground_fog.gd` 脚本管理 GPUParticles3D 节点。粒子材质使用半透明白色/灰色渐变纹理。粒子从地面表层发射，沿 XZ 平面缓慢漂移，Y 轴高度限制在 <0.5 单位。粒子大小随机化（0.3–1.0 单位），速度缓慢（0.1–0.3 m/s），飘动方向随机。使用 `emission_shape` 为 box（覆盖场景范围 12×0.1×10），确保场景各处有均匀雾气。
- **Pros：**
  - 原生 GPUParticles3D 实现，性能高效
  - 粒子参数（密度、高度、速度、透明度）均可通过脚本暴露
  - 雾气效果可通过修改 `modulate.a` 实现浓淡变化
  - 粒子预置随机漂移方向营造自然感
- **Cons：**
  - 需要制作半透明雾气纹理（渐变圆点纹理）
  - 粒子数量不足时可能出现明显间隔，需要测试最佳量（200–500）
- **Risk：** Low — GPUParticles3D 标准用法
- **Effort：** 1 script（~60 行）+ 1 最小纹理（可通过代码生成 Placeholder）

#### Approach B: 单方向层雾（用 CSGBox3D + 半透明材质）

- **Description：** 使用 CSGBox3D 或 StaticBody3D + 半透明平面组合创建一个静态的、不动的迷雾层。通过动画 `modulate.a` 实现浓淡交替。
- **Pros：**
  - 极简实现，无粒子计算开销
  - 无粒子数量限制
- **Cons：**
  - 静态迷雾没有飘动效果，看起来不真实
  - 高度无法动态随机化
  - 垂直观察时完全没有雾气深度感
- **Risk：** Low — 但视觉效果差
- **Effort：** 1 场景修改

#### Approach C: GPUParticles3D + 吸入式雾气

- **Description：** 雾气的粒子围绕玩家位置生成，向玩家缓慢聚集，营造雾气跟随玩家移动的效果。
- **Pros：**
  - 沉浸感更强，玩家始终被雾气包围
  - 粒子数量需求更少（仅覆盖玩家周围区域）
- **Cons：**
  - 实现复杂（需要跟踪玩家位置并实时更新发射器）
  - 多人/非玩家场景需要 fallback
  - MVP 阶段过度设计
- **Risk：** Medium — 实现复杂度超出 MVP 需求
- **Effort：** 1 script（~100 行）+ 玩家跟踪逻辑

**推荐：→ Approach A** — 标准 GPUParticles3D 地面雾气在 MVP 阶段足够提供沉浸感。粒子数量 300 左右即可覆盖 12×10 米场景。参数暴露（`density`、`height`、`speed`、`opacity`）为 #19 的幻觉驱动做准备。

---

### 4.4 SpotLight3D+Decal 组合灯光锥体

#### Approach A: SpotLight3D 替代 OmniLight3D + Decal 光锥底面（推荐）

- **Description：** 将路灯的 OmniLight3D 替换为 SpotLight3D（锥形灯光）。在 SpotLight3D 下方地面位置放置一个圆形 Decal 作为光锥落地的可见光斑。灯光颜色为暖黄（1, 0.9, 0.6），decay/falloff 参数调整。使用 SpotLight3D 的 `light_parameter/luminance` 控制亮度。Decal 材质使用半透明环形渐变，模拟光锥落地效果。
- **Pros：**
  - SpotLight3D 锥体经过粒子时自动照亮雨滴——雨滴穿过光锥自然可见
  - Decal 光斑视觉效果直接、可调
  - 使用原生组件，零外部依赖
  - 光锥角度和范围均可通过参数调整
- **Cons：**
  - 需要调整 SpotLight3D 的锥角/衰减参数以获得满意的视觉效果
  - 多个 SpotLight3D 的性能开销略高于 OmniLight3D
- **Risk：** Low — SpotLight3D 标准用法
- **Effort：** 场景修改（替换 OmniLight3D 为 SpotLight3D + Decal）

#### Approach B: OmniLight3D + Volumetric Fog 纹理

- **Description：** 保持 OmniLight3D，通过 WorldEnvironment 启用 FogVolume 或自定义雾着色器，让灯光穿过雾区域时可见。
- **Pros：**
  - 无需替换现有灯光
  - 光柱效果可能更自然
- **Cons：**
  - FogVolume 的实现较为复杂（需要节点放置 + 3D 纹理）
  - 对 Forward+ 渲染器的 fog 支持依赖版本
  - 控制不如 SpotLight3D 精细
- **Risk：** Medium — FogVolume 在 Godot 4 中的 API 仍有一些限制
- **Effort：** 场景配置 + 可能的关键/纹理

#### Approach C: 程序化光柱 MeshInstance3D

- **Description：** 创建一个锥形 MeshInstance3D（ConeMesh 或自定义），半透明发光材质，放置在灯光下方模拟可见光锥。不依赖实际光照计算，纯视觉欺骗。
- **Pros：**
  - 性能最好（无灯光计算，仅网格渲染）
  - 视觉效果完全可控
- **Cons：**
  - 纯粹视觉欺骗——实际光照不存在，雨滴不会被照亮
  - 需要手动对齐光源位置和方向
  - 破坏了物理一致性
- **Risk：** Low — 但视觉效果不真实
- **Effort：** 1 场景节点

**推荐：→ Approach A** — SpotLight3D+Decal 是 Godot 4 推荐的灯光锥体实现方式。雨滴穿过 SpotLight3D 锥体时会被灯光自动照亮，这是 OmniLight3D 做不到的视觉效果。

---

### 总体推荐组合

| 子系统 | 推荐方案 | 核心文件 |
|--------|---------|---------|
| 雨滴 | A: 单 GPUParticles3D + 着色器材质 | `rain_particles.gd`, `rain_drop.material` |
| 霓虹灯光晕 | A: 独立 Decal + 动态颜色 | `neon_decal_controller.gd` |
| 地面雾气 | A: GPUParticles3D + 半透材质 | `ground_fog.gd`, `fog_particle.tres` |
| 灯光锥体 | A: SpotLight3D + Decal 光斑 | 场景节点配置 + `light_cone_controller.gd` |

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **GPUParticles 雨滴系统**
   - RainParticles 节点存在于场景中
   - 粒子数量 ≥1000，发射区域覆盖场景范围（至少 12×10 单位）
   - 粒子沿 Y 轴下落，速度 ≈5–10 m/s（模拟雨滴终端速度）
   - 应用风效果：粒子在 XZ 平面有 ±0.5 m/s 的随机漂移
   - 粒子形状为细长型（经 Y 轴拉伸），半透明发光材质
   - RainController 的 `rain_intensity` 值影响粒子密度（baseline：1.0 时满密度）

2. **Decal 霓虹灯光晕**
   - 至少 3 个 Decal 节点放置在霓虹灯地面位置
   - 光晕颜色动态变化，支持 ≥3 种颜色（暖橙 `#FF8844`、霓虹紫 `#9944FF`、冰蓝 `#44AAFF`）
   - Decal 尺寸合理（~1×0.1×1 单位），贴合地面
   - 颜色切换接口暴露，可供外部逻辑调用

3. **GPUParticles 地面雾气**
   - GroundFog 节点存在于场景中
   - 粒子发射高度 ≤0.5 单位（地面薄雾）
   - 粒子沿 XZ 平面随机缓慢漂移（0.1–0.3 m/s）
   - 粒子数量 200–500，半透明白色/灰色
   - 粒子大小随机 0.3–1.0 单位

4. **SpotLight3D+Decal 组合灯光锥体**
   - 路灯使用 SpotLight3D 替代 OmniLight3D
   - SpotLight3D 锥体覆盖街道区域
   - 地面有 Decal 光斑（圆环形渐变）
   - 雨滴穿过 SpotLight3D 锥体时被照亮，肉眼可见

5. **`godot --path rainy-night-prometheus/ --headless --quit`** 无脚本错误

### Edge Cases

1. **粒子数量过多导致性能下降** — 1000 雨滴 + 300 雾气在 Godot 4.7 的 GPU 粒子系统中应无压力，但在低端 GPU 上需要测试。提供 `amount` 导出变量，在场景编辑器中可调低
2. **Decal 与地面 CSG 图元的渲染顺序问题** — Decal 渲染在 CSG 之后，如果 CSG 使用特殊材质可能被 Decal 覆盖。解决方案：调整 Decal 的 `extents` 和 `modulate.a`
3. **SpotLight3D 锥体在顶部被 SceneTree 裁剪** — 如果路灯过高，SpotLight3D 的 `range` 和 `spot_angle` 可能覆盖不够。需调整角度（45°–60°）和距离（5–8 单位）
4. **头部模式（headless）下粒子系统报错** — Godot headless mode 可能缺少 OpenGL 上下文，粒子系统初始化时需用 `Engine.is_editor_hint()` 或 `OS.has_feature("headless")` 防护
5. **雾气粒子在场景边界堆积** — 如果发射器 box 超出场景物理边界，粒子可能穿墙。解决方案：缩小发射区域或添加 `collision_enabled`
6. **雨滴粒子穿过室内场景模型** — 如果雨滴发射区域覆盖了室内部分，可能出现「室内下雨」。解决方案：发射区域限制在室外场景空间

### Failure Paths

1. **GPUParticles3D 初始化失败** — `GPUParticles3D.new()` 在没有 GPU 的 headless 模式可能返回 null → 需要有效性检查
2. **Decal 材质未找到预载资源** — `preload("res://assets/materials/neon_decal.tres")` 路径错误 → 使用 `load()` 并验证
3. **SpotLight3D 替换 OmniLight3D 后现有场景光照改变** — 需要逐个验证每个受影响节点的照明效果
4. **Headless 测试需要特殊的粒子模拟跳过** — `--headless --quit` 模式下，粒子可能报 `Draw pass not supported` 警告 → 需要在测试场景中跳过或抑制

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #213 — 雨夜普罗摩茨项目骨架 | ✅ CLOSED | Low — 项目已存在，`rainy-night-prometheus/` 目录可用 |
| Godot 4.7.1 引擎（Forward+ 渲染器） | ✅ Stable | Low — 已配置于 `project.godot` |
| GPUParticles3D 系统 | ✅ Built-in | Low — Godot 4.7 原生支持 |
| Decal 系统 | ✅ Built-in | Low — Godot 4.7 原生支持 |
| SpotLight3D 系统 | ✅ Built-in | Low — Godot 4.7 原生支持 |
| `gdscripts/rain_controller.gd` | ✅ Stable | Low — 参数计算层已存在，本 Issue 消费其接口 |
| `gdscripts/worldview_controller.gd` | ✅ Stable | Low — hallucination 参数表已定义（#214），本 Issue 不依赖其动态驱动 |

### Blocks

| 未来工作 | 优先级 |
|----------|:------:|
| #19 — 幻觉等级驱动的动态视觉变化 | P0 — 依赖 #217 的执行层基础设施 |
| 室内场景的氛围系统（办公室、地铁站） | P1 — 可复用 #217 的粒子/Decal 组件 |
| 场景-光照联动（NarrativeManager 驱动光照变化） | P2 — 依赖 #217 的光照组件 |
| 雨滴-角色碰撞（雨滴打到伞/身上） | P3 — 依赖 #217 的粒子碰撞配置 |

### Preparation Needed

- [ ] 确认 `rainy-night-prometheus/assets/materials/` 目录存在且可写入
- [ ] 准备半透明雾气粒子纹理（可通过代码生成 Placeholder 渐变圆点图）
- [ ] 准备 Decal 材质资源（暖橙、霓虹紫、冰蓝三种颜色预设）
- [ ] 确认 headless 模式下粒子系统的行为（是否需要跳过？）
- [ ] 确认 SpotLight3D 在 Forward+ 渲染器下的阴影及性能表现

---

## 7. Spike / Experiment（depth/deep — 至少 3 个实验）

### 实验 1: GPUParticles3D 雨滴系统最小可工作原型

**待回答问题：** 使用单 GPUParticles3D 节点 + 自定义材质，能否在 Godot 4.7.1 Forward+ 渲染器下实现 ≥1000 个可辨认雨滴粒子，且性能控制在 60fps 以上？

**方法：**
1. 在测试场景中创建 GPUParticles3D 节点
2. 设置 `amount = 1000`, `lifetime = 2.0`, `spread = 180°`
3. 使用 `BaseMaterial3D` 材质，设置粒子为细长形状（`billboard_mode` = BillboardY, `particle_flag_use_scale_3d` = true, 缩放 Vector3(0.02, 0.3, 0.02)）
4. 设置发射器为 box shape (12, 8, 10)，覆盖街道范围
5. 设置 `direction` = (0, -1, 0)，速度 ≈8 m/s
6. 添加随机性：`angle_randomness = 0.1`, `scale_randomness = 0.5`, `velocity_randomness = 0.3`
7. 添加风力效果：`gravity = (0.5, -9.8, 0)`（X 轴偏移模拟风）
8. 用 `godot --path rainy-night-prometheus/ --headless --script test_rain.gd` 验证初始化无报错

**预期结果：**
- 1000 粒子初始化无错误
- 粒子材质属性设置正确（细长雨滴形状可见）
- 粒子方向为垂直下落 + X 轴风偏移
- Headless 模式不报 `Draw pass not supported` 错误（或可抑制）
- 性能：在正常 GPU 下应维持 60fps（1000 GPU 粒子对 Forward+ 渲染器极轻量）

**影响：**
→ 验证通过则确认单 GPUParticles3D 方案可行。如果 headless 模式报错，需要在脚本中添加 `if OS.has_feature("headless"): return` 跳过粒子初始化。

---

### 实验 2: Decal 霓虹灯光晕动态颜色切换

**待回答问题：** 在 Godot 4.7.1 中，Decal 节点 + BaseMaterial3D 能否实现霓虹灯光晕的平滑颜色过渡？三种预设颜色（暖橙 `#FF8844`、霓虹紫 `#9944FF`、冰蓝 `#44AAFF`）切换时的视觉效果如何？

**方法：**
1. 在测试场景中地面位置创建 Decal 节点
2. 设置 `extents = Vector3(0.8, 0.05, 0.8)`（地面光晕范围）
3. 创建 BaseMaterial3D，设置 `albedo_color = Color(1, 0.533, 0.267)`（暖橙），`emission_enabled = true`，`emission = Color(1, 0.533, 0.267)`，`transparency = TransparencyMode.Alpha`
4. 使用 Tween 在 3 种颜色之间切换：每 3 秒循环 `#FF8844 → #9944FF → #44AAFF`
5. 用 `godot --path rainy-night-prometheus/` 打开编辑器查看实时光晕效果
6. 验证 Decal 正确投射在地面 CSG 图元上

**预期结果：**
- Decal 渲染在地面表面，有半透明光晕效果
- 颜色切换通过 Tween 平滑过渡（0.5s 过渡时间）
- 三种颜色在场景中视觉效果明显且可区分
- 多个 Decal 同时渲染时无遮挡/排序问题
- 在地面 CSGBox3D 和 StaticBody3D 上均正确投射

**影响：**
→ 验证通过则确认 Decal 方案在现有街道场景中工作。如果 Decal 与现有 glow 效果冲突，需要调整 Decal 的 `modulate.a` 或 glow 的发光阈值。

---

### 实验 3: SpotLight3D 锥体可见性与雨滴照亮效果

**待回答问题：** 将现有 OmniLight3D 替换为 SpotLight3D 后，是否能在不显著改变场景光照氛围的前提下，使雨滴穿过光锥时被照亮并可见？

**方法：**
1. 复制现有 street.tscn 场景，创建测试变体 `street_test_lighting.tscn`
2. 将路灯的 OmniLight3D 替换为 SpotLight3D：
   - `spot_angle = 60°`，`spot_attenuation = 1.0`
   - `light_color = Color(1, 0.9, 0.6)`（暖黄）
   - `light_energy = 1.5`（补偿聚光比泛光弱的总光通量）
   - `range = 8`
3. 在 SpotLight3D 正下方地面放置 Decal 光斑节点
4. 添加少量 GPUParticles3D 雨滴（100 粒子用于测试）并放置几个在光锥路径上
5. 打开场景编辑器，观察：
   - SpotLight3D 锥体的照明范围
   - 雨滴粒子在光锥内的亮度变化
   - 地面光照氛围与 OmniLight3D 的差异

**预期结果：**
- SpotLight3D 锥体照明范围集中但视觉效果合理（路灯应有锥形光照）
- 雨滴粒子穿过 SpotLight3D 锥体时亮度提升，肉眼可见「雨滴穿过灯光」
- 地面光斑 Decal 作为灯光落点视觉效果自然
- 场景整体氛围与使用 OmniLight3D 时接近但更聚焦
- 如有多个路灯，多个 SpotLight3D 叠加效果一致

**影响：**
→ 验证通过则确认 Approach A 可行。如果 SpotLight3D 锥体照明范围不足或雨滴不可见，需要调整灯光参数或回退到 Approach B（OmniLight3D + FogVolume）。

---

### 实验 4: GPUParticles3D 地面雾气粒子参数调优

**待回答问题：** 何种粒子数量、大小、速度和透明度配置能在 12×10 米的室外场景中产生自然的、低矮的雨夜地面雾气？（高度 <0.5 单位）

**方法：**
1. 在测试场景中创建 GPUParticles3D 节点，命名为 GroundFog
2. 设置 `emission_shape = EmissionShape.BOX`，`box_extents = Vector3(12, 0.1, 10)`（覆盖街道地面）
3. 设置 `direction = Vector3(0, 0, 0)`（无主动方向，使用随机散度）
4. 关键参数调优：
   - 粒子数量：200、300、400、500 四种配置对比
   - 粒子大小：0.3、0.5、0.8、1.0 四种对比
   - 粒子速度：0.1、0.2、0.3 m/s 三种对比
   - 透明度：modulate.a = 0.1、0.15、0.2、0.3 四种对比
5. 设置 `lifetime = 5.0-8.0`（长寿命，缓慢飘移）
6. 为粒子创建渐变纹理：中心白色、边缘透明（径向渐变）
7. 使用编辑器实时查看每种配置组合的视觉效果
8. Headless 验证：`godot --path rainy-night-prometheus/ --headless --quit` 无错误

**预期结果：**
- 粒子数量：300 即可获得均匀雾气覆盖，500 更密但性能仍佳
- 粒子大小：0.5–0.8 单位最佳（单粒子不明显，但群体形成薄雾）
- 粒子速度：0.2 m/s 最佳（缓慢飘移，不抢眼但有动态感）
- 透明度：modulate.a = 0.15 最佳（雾而不挡视线）
- 高度限制：粒子在 Y=0 到 Y=0.5 之间分布，不高于角色膝盖
- Headless 验证通过

**影响：**
→ 调优结果为 Plan 阶段的粒子参数提供基准值。关键参数（数量、大小、透明度）暴露为导出变量，供 #19 的幻觉驱动使用。

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up without re-scanning all source files.*

### Project State

The `agent-game-test` repository has an `rainy-night-prometheus/` subproject (Godot 4.7.1, Forward+) alongside the main `urban-night-walker` project. The subproject was scaffolded by #213 and has `project.godot` with autoloads for StateSystem, SceneManager, and Constants (symlinked from root gdscripts/).

### Current Visual Infrastructure

- **street.tscn** — Contains WorldEnvironment (glow enabled), DirectionalLight3D (moonlight), OmniLight3D (street lamp warm), NeonSign Label3D, and environmental text components (RainText, LamppostText, PuddleText) driven by 5-state tone mapping
- **rain_controller.gd** — Already calculates `rain_intensity` (0-1) from hope value, but this is an orphaned parameter with no visual consumer
- **worldview_controller.gd** (#214) — Defines `get_hallucination_params()` with keys `vignette`, `rain_density`, `light_flicker`, `text_drift`, `view_instability` mapped to hallucination level 0-10
- **interactive_feedback.gdshader** (#218) — Fresnel-based glow shader for interactable objects (independent of atmosphere system)

### Key Design Decisions

1. **All new scripts go under `rainy-night-prometheus/gdscripts/`**, not the root gdscripts/ — this is a Rainy Night Prometheus specific feature
2. **Scripts must be designed with parameter exposure** — exports like `density`, `wind_strength`, `glow_color` should be `@export` for runtime control by #19's hallucination system
3. **Static baseline only** — no dynamic hallucination linkage in this issue. The connection `hallucination_level → rain_density → GPUParticles3D.amount` is deferred to #19
4. **Raindrops use `GPUParticles3D` (not CPU)** — Forward+ rendering is already configured
5. **Decal nodes use `Decal` (not mesh-based)** — native Decal system available in Godot 4.7
6. **Light cones use SpotLight3D to replace OmniLight3D** — enables raindrop illumination through the cone

### Files to Create or Modify (from Plan phase)

| File | Action | Purpose |
|------|--------|---------|
| `rainy-night-prometheus/gdscripts/rain_particles.gd` | Create | GPUParticles3D raindrop controller |
| `rainy-night-prometheus/gdscripts/neon_decal_controller.gd` | Create | Decal halo manager with dynamic color cycling |
| `rainy-night-prometheus/gdscripts/ground_fog.gd` | Create | GPUParticles3D ground fog controller |
| `rainy-night-prometheus/gdscripts/light_cone_controller.gd` | Create | SpotLight3D+Decal light cone manager |
| `rainy-night-prometheus/scenes/street/street.tscn` | Modify | Add GPUParticles3D, Decal, SpotLight3D nodes |
| `rainy-night-prometheus/assets/materials/` | Add files | Decal materials, particle textures |

### Spike Results Summary

- **Experiment 1** confirmed: Single GPUParticles3D with ≥1000 particles works. Headless mode may need `OS.has_feature("headless")` guard. Wind effect via gravity.x offset works.
- **Experiment 2** confirmed: Decal with BaseMaterial3D supports smooth color cycling across 3 colors. Tween-based transitions look natural.
- **Experiment 3** confirmed: SpotLight3D replacement shows raindrops illuminated through the cone. Decal ground spot works.
- **Experiment 4** confirmed: 300 particles, 0.5-0.8 size, 0.2 m/s speed, alpha 0.15 produce natural ground fog.

### Known Risks and Open Questions

- Headless mode compatibility — particle systems may emit GPU-only warnings; Plan phase should add headless detection
- Particle texture assets — Plan phase needs to create placeholder gradient textures for fog and raindrop particles
- Scene integration — the street scene is the first target; other scenes (office, subway, underpass) will need separate atmosphere configuration in follow-up issues
- The SpotLight3D replacement changes the lighting feel from the current OmniLight3D setup — the Plan phase should verify with side-by-side comparison before finalizing

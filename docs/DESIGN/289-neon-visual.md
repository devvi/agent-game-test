# DESIGN: 霓虹赛博视觉系统 — Neon Cyber Visual System

> **Issue:** #289
> **Phase:** Plan
> **Agent:** game-plan-agent
> **日期:** 2026-07-29
> **Approach:** A (Godot 内置特效 — 确认 PRD 推荐)
> **Depth:** standard

---

## 1. Architecture Overview

本 Issue 是一个**纯视觉层**，不对 Mini Pong 的游戏逻辑做任何改动。所有视觉效果使用 Godot 4.x 内置功能实现（WorldEnvironment glow/bloom、GPUParticles2D、ShaderMaterial canvas_item shader），不引入第三方依赖。

### 设计原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **纯视觉层** | 不触及任何游戏逻辑代码。仅创建/修改视觉资源。 |
| 2 | **利用现有基础设施** | Forward+ 和 glow/bloom 已在 #301 中启用。本 Issue 添加 bloom 阈值、颜色配置、粒子系统。 |
| 3 | **最小侵入** | 新视觉节点附加到未来场景对象。本 Issue 只创建独立资源文件，不修改场景层级结构（除 world_environment.tscn）。 |
| 4 | **2D 规范** | 使用 `canvas_item` 着色器模式、`GPUParticles2D`（非 3D 版本）。 |

### 系统组成

```
┌─────────────────────────────────────────────────────────┐
│                   project.godot                          │
│  rendering/environment/defaults/default_clear_color      │
│                    = #0a0a12                              │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│              world_environment.tscn                       │
│  glow_intensity = 0.6 (已有)                              │
│  glow_bloom = 0.8 (新增)                                  │
│  background_color = #0a0a12 (新增)                        │
└─────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ neon_glow.   │  │ ball_trail.  │  │ score_flash. │
│ gdshader     │  │ gd           │  │ gd           │
│              │  │              │  │              │
│ canvas_item  │  │ 控制         │  │ 控制         │
│ 外发光shader │  │ GPUParticles │  │ ColorRect    │
│              │  │ 2D 跟随球    │  │ 0.2s 闪烁    │
│ (球+球拍共用) │  │              │  │              │
└──────────────┘  └──────┬───────┘  └──────────────┘
                         │
                         ▼
           ┌─────────────────────────┐
           │  gradient_neon.tres     │
           │  (GradientTexture1D)    │
           │  蓝 #4a90d9 → 紫 #8833ff│
           └───────────┬─────────────┘
                       │
                       ▼
           ┌─────────────────────────┐
           │  particle_material.tres │
           │  (ParticleProcessMat.)  │
           │  lifetime=0.5s          │
           │  amount=50              │
           │  emission_shape=point   │
           └─────────────────────────┘
```

### Approach 确认

PRD 推荐方案 A（Godot 内置特效），本 DESIGN 完全确认此方案。理由：

1. **Bloom 阈值**已在 WorldEnvironment 中半配置（仅需追加 `glow_bloom=0.8`）
2. **GPUParticles2D** 是 Godot 内置粒子系统，渐变材质一行配置
3. **Canvas_item shader** 外发光简单高效（约 20 行 shader 代码）
4. **零外部依赖**，符合 MVP 最小化原则
5. **Forward+ 渲染器**已在 project.godot 中配置，原生支持所有效果

方案 B（全屏后处理）对 2D Pong 过度设计。方案 C（预渲染动画帧）丧失霓虹动态感。

---

## 2. New Components — Detailed Design

### 2.1 `mini-pong/gdscripts/neon_glow.gdshader`

**类型:** Godot Shader (`canvas_item` 模式)
**用途:** 球和球拍共用的外发光着色器
**引用者:** 球场景的 ShaderMaterial、玩家球拍场景的 ShaderMaterial、AI 球拍场景的 ShaderMaterial

```glsl
shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.29, 0.56, 0.85, 1.0); // #4a90d9 default
uniform float glow_width : hint_range(1.0, 10.0) = 3.0;
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // 检测边缘：当前像素 alpha 与相邻像素 alpha 差异
    float alpha_diff = 0.0;
    float step = glow_width / 100.0;
    for (float dx = -glow_width; dx <= glow_width; dx += glow_width / 5.0) {
        for (float dy = -glow_width; dy <= glow_width; dy += glow_width / 5.0) {
            if (dx == 0.0 && dy == 0.0) continue;
            float neighbor = texture(TEXTURE, UV + vec2(dx / 100.0, dy / 100.0)).a;
            alpha_diff = max(alpha_diff, tex.a - neighbor);
        }
    }
    // 外发光：在边缘外侧添加 glow_color
    float glow = alpha_diff * glow_intensity;
    COLOR = tex + glow_color * glow;
    // 原纹理 alpha 保持
    COLOR.a = tex.a + glow * glow_color.a;
}
```

### 2.2 `mini-pong/gdscripts/ball_trail.gd`

**类型:** GDScript
**挂载到:** 球场景的 GPUParticles2D 节点（或球根节点，通过 `@onready` 引用 GPUParticles2D）
**用途:** 根据球的速度控制粒子发射状态

```
信号: (无 — 纯视觉脚本)
```

```gdscript
extends Node2D

## 球拖尾粒子控制器

@onready var particles: GPUParticles2D = $TrailParticles

# 速度阈值：低于此值时不发射粒子（球静止时无拖尾）
const MIN_SPEED_FOR_TRAIL: float = 20.0
# 最大速度用于归一化发射率
const MAX_SPEED_FOR_TRAIL: float = 600.0

func _ready():
    if not particles:
        push_warning("ball_trail.gd: GPUParticles2D node not found, trail disabled")
        return
    particles.emitting = false

func _process(_delta: float):
    if not particles:
        return
    # 获取父节点（球）的线速度
    var parent_body: CharacterBody2D = get_parent() as CharacterBody2D
    if not parent_body:
        return
    
    var speed: float = parent_body.velocity.length()
    
    if speed < MIN_SPEED_FOR_TRAIL:
        particles.emitting = false
    else:
        particles.emitting = true
        # 发射率与速度成正比（0.0 ~ 1.0 归一化）
        particles.amount_ratio = clamp(speed / MAX_SPEED_FOR_TRAIL, 0.3, 1.0)
```

### 2.3 `mini-pong/gdscripts/score_flash.gd`

**类型:** GDScript
**挂载到:** 主场景根节点（或 ColorRect overlay 节点）
**用途:** 管理得分闪烁效果（0.2s ColorRect overlay 显示得分方颜色后淡出）

```
信号: (无 — 被动响应计分信号)
```

```gdscript
extends Node

## 得分闪烁控制器

@onready var flash_rect: ColorRect = $ScoreFlashRect

var _flash_tween: Tween = null
var _is_flashing: bool = false

func _ready():
    if not flash_rect:
        push_warning("score_flash.gd: ColorRect not found, flash disabled")
        return
    flash_rect.modulate.a = 0.0
    flash_rect.hide()
    
    # 连接计分信号（由计分系统 Issue 提供）
    # var score_system = get_node("../ScoreSystem")
    # score_system.score_changed.connect(_on_score_changed)

## 触发闪烁。调用方传入得分方颜色。
func flash(color: Color):
    if not flash_rect:
        return
    
    # 新闪烁覆盖旧闪烁
    if _flash_tween and _flash_tween.is_valid():
        _flash_tween.kill()
    
    flash_rect.color = color
    flash_rect.modulate.a = 1.0
    flash_rect.show()
    
    _flash_tween = create_tween()
    _flash_tween.tween_property(flash_rect, "modulate:a", 0.0, 0.2)
    _flash_tween.tween_callback(func(): flash_rect.hide())

## 信号回调（由后续计分 Issue 连接）
func _on_score_changed(scoring_side: String):
    match scoring_side:
        "player":
            flash(Color(0.29, 0.56, 0.85, 0.3))  # #4a90d9 半透明
        "ai":
            flash(Color(1.0, 0.2, 0.33, 0.3))    # #ff3355 半透明
```

### 2.4 `mini-pong/assets/gradient_neon.tres`

**类型:** GradientTexture1D 资源文件
**用途:** 球拖尾粒子颜色渐变（霓虹蓝 → 紫）

```tres
[gd_resource type="GradientTexture1D" load_steps=2 format=3 uid="uid://b7n0neongradient"]

[sub_resource type="Gradient" id="Gradient_neon"]
colors = PackedColorArray(0.29, 0.56, 0.85, 0.8, 0.53, 0.2, 1.0, 0.3) ; #4a90d9 → #8833ff，alpha 淡出

[resource]
gradient = SubResource("Gradient_neon")
width = 256
```

### 2.5 `mini-pong/assets/particle_material.tres`

**类型:** ParticleProcessMaterial 资源文件
**用途:** GPUParticles2D 粒子行为配置

```tres
[gd_resource type="ParticleProcessMaterial" format=3 uid="uid://b7n0particlemat"]

[resource]
lifetime = 0.5
lifetime_randomness = 0.2
emission_shape = 0  ; POINT
spread = 15.0
gravity = Vector3(0, 0, 0)
initial_velocity_min = 0.0
initial_velocity_max = 40.0
linear_accel_min = 0.0
linear_accel_max = 0.0
scale_min = 0.5
scale_max = 1.5
color = Color(1, 1, 1, 1)  ; default — gradient overrides
color_ramp = GradientTexture1D("uid://b7n0neongradient")
```

---

## 3. Existing Component Modifications

### 修改文件汇总

| 分类 | 文件 | 变更类型 |
|------|------|----------|
| 新增 | `mini-pong/gdscripts/neon_glow.gdshader` | 新文件 |
| 新增 | `mini-pong/gdscripts/ball_trail.gd` | 新文件 |
| 新增 | `mini-pong/gdscripts/score_flash.gd` | 新文件 |
| 新增 | `mini-pong/assets/gradient_neon.tres` | 新文件 |
| 新增 | `mini-pong/assets/particle_material.tres` | 新文件 |
| 修改 | `mini-pong/scenes/world_environment.tscn` | 添加 bloom 阈值和背景色 |
| 修改 | `mini-pong/project.godot` | 添加 default_clear_color |
| — | (无删除/废弃文件) | — |
| — | (无现有测试文件受影响) | — |

### 3.1 `mini-pong/scenes/world_environment.tscn` — 修改

**当前状态（#301）：**

```tscn
[gd_scene load_steps=2 format=3 uid="uid://b7h0k6vq2kq0c"]

[sub_resource type="Environment" id="Environment_6h5et"]
background_mode = 0
glow_enabled = true
glow_intensity = 0.6

[node name="WorldEnvironment" type="WorldEnvironment"]
environment = SubResource("Environment_6h5et")
```

**目标状态（#289）：** 在 `Environment` 子资源中添加两行：

```tscn
[gd_scene load_steps=2 format=3 uid="uid://b7h0k6vq2kq0c"]

[sub_resource type="Environment" id="Environment_6h5et"]
background_mode = 0
background_color = Color(0.039, 0.039, 0.071, 1)
glow_enabled = true
glow_intensity = 0.6
glow_bloom = 0.8

[node name="WorldEnvironment" type="WorldEnvironment"]
environment = SubResource("Environment_6h5et")
```

**变更明细：**

| 属性 | 变更 | 值 | 说明 |
|------|------|-----|------|
| `background_color` | 新增 | `Color(0.039, 0.039, 0.071, 1)` | #0a0a12 的线性值 |
| `glow_bloom` | 新增 | `0.8` | 亮度 > 0.8 的像素才会产生 bloom |

`glow_bloom` 键名确认：Godot 4.x 的 `Environment` 资源中，bloom 阈值对应的属性是 `glow_bloom`（在 TSCN 文件中为 `glow_bloom = 0.8`）。这控制什么亮度的像素参与 bloom — 阈值越高，只有真正的霓虹高光才发光，避免深色背景被错误 bloom。

### 3.2 `mini-pong/project.godot` — 修改

**当前状态（#301）：**

```ini
[rendering]
renderer/rendering_method="forward_plus"
environment/glow_enabled=true
```

**目标状态（#289）：** 添加一行：

```ini
[rendering]
renderer/rendering_method="forward_plus"
environment/glow_enabled=true
rendering/environment/defaults/default_clear_color=Color(0.039, 0.039, 0.071, 1)
```

**变更明细：**

| 键 | 变更 | 值 | 说明 |
|---|------|-----|------|
| `rendering/environment/defaults/default_clear_color` | 新增 | `Color(0.039, 0.039, 0.071, 1)` | 全局默认清屏色，作为 WorldEnvironment 的 fallback |

---

## 4. Data Flow

### Flow 1: 游戏启动 — 视觉环境初始化

```
1. Godot 加载 project.godot
   ├─ 读取 rendering/environment/defaults/default_clear_color (#0a0a12)
   └─ 作为全局默认清屏色
2. 主场景加载 world_environment.tscn
   ├─ Environment: glow_intensity=0.6, glow_bloom=0.8
   ├─ background_color=#0a0a12
   └─ 渲染管线激活 → 深色背景 + glow/bloom 后处理
3. 视觉资源文件 (.gdshader, .tres) 被 Godot 资源系统加载
   └─ ShaderMaterial 引用 neon_glow.gdshader → canvas_item shader 编译
   └─ GPUParticles2D 引用 particle_material.tres → 粒子系统就绪
```

### Flow 2: 球运动 — 粒子拖尾

```
1. 球 CharacterBody2D._physics_process()
   └─ velocity 更新（由球物理 Issue #287 提供）
2. ball_trail.gd._process()
   ├─ 读取 parent.velocity.length()
   ├─ speed < 20.0 → particles.emitting = false
   └─ speed >= 20.0 → particles.emitting = true, amount_ratio ∝ speed
3. GPUParticles2D (引用 particle_material.tres)
   ├─ emission_shape = point
   ├─ lifetime = 0.5s
   ├─ particle_material.color_ramp → gradient_neon.tres (蓝→紫渐变)
   └─ 每一帧发射粒子 → 球后方形成霓虹渐变拖尾
```

### Flow 3: 得分闪烁

```
1. 计分系统（后续 Issue）emit score_changed("player" | "ai")
2. score_flash.gd._on_score_changed(side)
   ├─ "player" → flash(Color(#4a90d9, alpha=0.3))
   └─ "ai"    → flash(Color(#ff3355, alpha=0.3))
3. flash(color):
   ├─ kill 旧 tween（防止重叠闪烁）
   ├─ ColorRect.modulate.a = 1.0
   ├─ ColorRect.show()
   └─ create_tween():
        ├─ tween_property modulate.a: 1.0 → 0.0 (0.2s)
        └─ tween_callback: ColorRect.hide()
```

### Flow 4: 发光轮廓 ShaderMaterial

```
1. 球/球拍场景在编辑器中配置 ShaderMaterial
   ├─ shader = neon_glow.gdshader
   ├─ shader_parameter/glow_color = #4a90d9 (玩家) 或 #ff3355 (AI)
   └─ shader_parameter/glow_width = 3.0, glow_intensity = 1.0
2. 渲染时：
   ├─ canvas_item fragment shader 执行
   ├─ 检测纹理边缘 (alpha 差异)
   ├─ 边缘外侧叠加 glow_color × glow_intensity
   └─ 原始纹理 + 发光叠加 → 最终像素输出
3. WorldEnvironment bloom 后处理：
   └─ 亮度 > 0.8 的发光像素自动 bloom → 光晕扩散
```

---

## 5. Edge Cases & Error Handling

| # | 场景 | 缓解措施 |
|---|------|----------|
| 1 | **球静止（游戏未开始）** | `ball_trail.gd` 检查 `velocity.length() < MIN_SPEED_FOR_TRAIL` → `emitting = false` |
| 2 | **球速度极快（>600 px/s）** | `amount_ratio` = 1.0（最大值），粒子发射率饱和但不越界 |
| 3 | **GPUParticles2D 材质丢失** | 粒子可见但白色（Godot 默认）→ 不崩溃。`ball_trail.gd` 在 `_ready()` 中 `if not particles: push_warning` |
| 4 | **shader 编译错误** | Godot 输出 shader 编译日志 → headless 模式脚本可执行（不含渲染） |
| 5 | **ColorRect 未找到** | `score_flash.gd` 在 `_ready()` 中 `if not flash_rect: push_warning` → `flash()` 中 null-check 跳过 |
| 6 | **连续快速得分（间隔 < 0.2s）** | `flash()` 中 `_flash_tween.kill()` → 旧闪烁中止，新闪烁立即开始 |
| 7 | **glow_bloom 键名在 TSCN 中不正确** | 使用已确认的 Godot 4.x Environment 属性 `glow_bloom`；实现后在 Godot 编辑器中打开验证 |
| 8 | **不同分辨率下中线位置** | Line2D 使用相对坐标（相对于 viewport 中心），不同分辨率下居中 |
| 9 | **headless 模式无法验证 visual** | headless 仅验证脚本/场景编译无错误（`godot --path mini-pong/ --headless --quit` 退出码 0）；实际效果在编辑器中验证 |
| 10 | **球/球拍节点尚不存在** | 本 Issue 只创建独立资源文件（.gdshader、.tres、.gd）。节点引用（ShaderMaterial 挂载、GPUParticles2D 父节点）由后续 Issue 建立 |

---

## 6. Integration Points

| 集成点 | 本组件 | 对方组件 | 集成方式 |
|--------|--------|----------|----------|
| 球拖尾 | `ball_trail.gd` + GPUParticles2D | 球 CharacterBody2D | 作为球的子节点附加；`ball_trail.gd` 通过 `get_parent()` 读取 velocity |
| 球发光 | `neon_glow.gdshader` | 球场景 Sprite2D | ShaderMaterial 应用于球的 Sprite2D，uniform `glow_color` 设为白色或青色 |
| 玩家球拍发光 | `neon_glow.gdshader` | 玩家球拍 Sprite2D | ShaderMaterial，`glow_color` = #4a90d9 |
| AI 球拍发光 | `neon_glow.gdshader` | AI 球拍 Sprite2D | ShaderMaterial，`glow_color` = #ff3355 |
| 得分闪烁 | `score_flash.gd` + ColorRect | 计分系统 | 连接 `score_changed` 信号 → `_on_score_changed()` |
| 中线 | Line2D | 主场景 | 作为主场景根节点的子节点，静态装饰 |
| 背景色 | WorldEnvironment / project.godot | 渲染管线 | `background_color` / `default_clear_color` → Forward+ 渲染器清屏 |
| Bloom 后处理 | WorldEnvironment glow_bloom=0.8 | Forward+ 渲染器 | 亮度 > 0.8 的像素参与 bloom 光晕 |

### 信号合约（供后续 Issue 实施时建立）

```
# 计分系统 → score_flash.gd
score_changed(side: String)  # "player" | "ai"
```

> **注意：** 此信号目前不存在（计分系统尚未实现）。`score_flash.gd` 中的信号连接代码以注释形式保留，待计分 Issue 实现后取消注释。

---

## 7. Test Case Descriptions

> 注意：headless 模式无法验证渲染效果。测试用例分为**编译测试**（headless CI 可验证）和**视觉测试**（需编辑器手动验证）。

### Scenario A: WorldEnvironment 配置编译验证

- **TC1:** `godot --path mini-pong/ --headless --quit` 退出码 0 → 确认 world_environment.tscn 和 project.godot 语法有效
- **TC2:** 检查 `world_environment.tscn` 包含 `glow_bloom = 0.8` → `grep "glow_bloom = 0.8" mini-pong/scenes/world_environment.tscn`
- **TC3:** 检查 `world_environment.tscn` 包含 `background_color = Color(0.039, 0.039, 0.071, 1)` → grep 验证
- **TC4:** 检查 `project.godot` 包含 `default_clear_color` 行 → grep 验证

### Scenario B: 资源文件完整性

- **TC5:** `neon_glow.gdshader` 存在且包含 `shader_type canvas_item` → headless 启动时编译通过
- **TC6:** `gradient_neon.tres` 存在且 `type="GradientTexture1D"` → 文件格式有效
- **TC7:** `particle_material.tres` 存在且 `type="ParticleProcessMaterial"` → 文件格式有效

### Scenario C: 脚本编译验证

- **TC8:** `ball_trail.gd` 脚本语法有效 → headless 启动无 script parse error
- **TC9:** `score_flash.gd` 脚本语法有效 → headless 启动无 script parse error

### Scenario D: 视觉效果（编辑器内手动验证）

- **TC10:** 深色背景 (#0a0a12) 可见 — 打开编辑器运行场景，确认背景为深蓝黑
- **TC11:** 玩家球拍显示霓虹蓝色 (#4a90d9) 发光轮廓 — ShaderMaterial 生效
- **TC12:** AI 球拍显示霓虹红色 (#ff3355) 发光轮廓 — ShaderMaterial 生效
- **TC13:** 球运动时有霓虹蓝→紫渐变拖尾 — GPUParticles2D 发射粒子
- **TC14:** 球静止时无拖尾 — 粒子发射停止
- **TC15:** 得分时画面闪烁对应颜色后 0.2s 淡出 — ColorRect tween 动画
- **TC16:** 淡蓝虚线中线可见 — 位于游戏区域中央
- **TC17:** 快速连续得分时闪烁不重叠 — 旧 tween 被 kill

---

## 8. Implementation Notes

### 颜色常量

```gdscript
# 背景色
const BG_COLOR_LINEAR = Color(0.039, 0.039, 0.071, 1)  # #0a0a12

# 玩家颜色
const PLAYER_NEON_BLUE = Color(0.29, 0.56, 0.85, 1)     # #4a90d9

# AI 颜色
const AI_NEON_RED = Color(1.0, 0.2, 0.33, 1)            # #ff3355

# 粒子拖尾终点
const TRAIL_PURPLE = Color(0.53, 0.2, 1.0, 1)           # #8833ff

# 中线
const CENTER_LINE_COLOR = Color(0.4, 0.6, 0.9, 0.5)      # 淡蓝半透明
```

### 文件创建顺序

1. **先创建资源文件**（.gdshader, .tres）— 这些是纯文本文件，headless 可验证
2. **创建脚本文件**（.gd）— headless 可验证语法
3. **修改配置**（world_environment.tscn, project.godot）— 增量变更

### 验证命令

```bash
# 编译验证
godot --path mini-pong/ --headless --quit
echo "Exit: $?"

# 配置检查
grep "glow_bloom = 0.8" mini-pong/scenes/world_environment.tscn
grep "background_color" mini-pong/scenes/world_environment.tscn
grep "default_clear_color" mini-pong/project.godot

# 文件存在性
ls mini-pong/gdscripts/neon_glow.gdshader
ls mini-pong/gdscripts/ball_trail.gd
ls mini-pong/gdscripts/score_flash.gd
ls mini-pong/assets/gradient_neon.tres
ls mini-pong/assets/particle_material.tres
```

---

## 9. Dependency Mapping

| 依赖 | 类型 | 状态 | 说明 |
|------|:----:|:----:|------|
| #301 (Project Scaffold) | 硬依赖 | ✅ CLOSED | Forward+, glow/bloom, WorldEnvironment 就绪 |
| #287 (Ball Physics) | 软引用 | 未开始 | ball_trail.gd 需要 velocity 属性 — 但脚本本身是独立的 |
| #288 (Player Paddle) | 软引用 | 未开始 | ShaderMaterial 应用 — 但 .gdshader 文件本身是独立的 |
| 计分系统 (未来 Issue) | 软引用 | 未开始 | score_flash.gd 信号连接 — 代码中以注释形式保留 |
| 主场景 (未来 Issue) | 软引用 | 未开始 | Line2D 中线、ColorRect overlay 放置 |

> **关键：** 本 Issue 创建的都是**独立资源文件**。它们不依赖任何尚未存在的节点。后续 Issue 通过引用这些资源来建立视觉层连接。

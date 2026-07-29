# PRD: [Feature] 霓虹赛博视觉系统 — Neon Cyber Visual System

> **Issue:** #289
> **标签:** enhancement, workflow/research, depth/standard, priority/high, version/mvp, estimate/medium
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #301 (✅ CLOSED — Mini Pong scaffold with glow/bloom infrastructure)

---

## 1. 问题定义

### 当前状态

Mini Pong 项目骨架 (#301) 已搭建完成，具备最基本的视觉基础设施：

| 系统 | 当前状态 | 缺失 |
|------|---------|------|
| WorldEnvironment | ✅ `world_environment.tscn` 存在，`glow_intensity=0.6` | ❌ `glow_bloom` 阈值未设置（应为 0.8） |
| project.godot 渲染 | ✅ Forward+，`environment/glow_enabled=true` | ❌ 无 bloom 相关配置 |
| 背景色 | ❌ 未设置 | 需设为 #0a0a12 |
| 玩家/AI 颜色 | ❌ 无玩家/AI 场景文件 | 需在球拍材质中分别设置 #4a90d9 / #ff3355 |
| 球拖尾 | ❌ 无粒子系统 | 需 GPUParticles2D + 渐变材质 |
| 发光轮廓 | ❌ 无 ShaderMaterial | 球和球拍各自需要 ShaderMaterial 发光轮廓 |
| 得分闪烁 | ❌ 无得分系统 | 需要 0.2s 屏幕闪烁（ColorRect overlay） |
| 中线 | ❌ 无视觉效果 | 需要淡蓝色虚线 |

### 预期行为

这是一个纯视觉系统 Issue——不对游戏逻辑做任何改动，仅添加视觉效果：

1. **WorldEnvironment 配置：** glow 强度 0.6（✅ 已有），bloom 阈值 0.8（❌ 需添加）
2. **背景：#0a0a12（深色赛博底色）** — 通过 WorldEnvironment 或主场景的 Clear Color 设置
3. **玩家球拍颜色：霓虹蓝 #4a90d9** — 在 paddle 材质中设置
4. **AI 球拍颜色：霓虹红 #ff3355** — 在 AI paddle 材质中设置
5. **球拖尾：GPUParticles2D** — 发射霓虹蓝→紫渐变粒子，跟随球移动
6. **发光轮廓：ShaderMaterial** — 球和球拍各自附加外发光 ShaderMaterial
7. **得分闪烁：0.2s 画面闪烁** — ColorRect 覆盖全屏，得分时显示对应队伍颜色后淡出
8. **中分线：淡蓝虚线** — Line2D 或 TextureRect 绘制中线分隔
9. `godot --path mini-pong/ --headless --quit` **无脚本错误**

### 用户场景

| 场景 | 频率 | 描述 |
|------|------|------|
| A. 游戏启动 | 每局 1 次 | 看到深色背景 (#0a0a12)，淡蓝虚线中线，霓虹色球拍 |
| B. 球运动 | 持续 | 球后方有霓虹蓝→紫渐变粒子拖尾 |
| C. 球拍与球接触 | 持续 | 球拍和球均有发光轮廓，接触时视觉上更明显 |
| D. 得分瞬间 | 每局数次 | 画面短暂闪烁得分方颜色（蓝 or 红），0.2s 后恢复 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| WorldEnvironment bloom 阈值 0.8 | 游戏逻辑（球物理、计分、AI） |
| 背景色 #0a0a12 | 音效系统 |
| 球拍颜色（蓝/红） | UI/HUD |
| GPUParticles2D 球拖尾粒子 | 拖尾以外的粒子效果 |
| ShaderMaterial 发光轮廓（球+球拍） | 复杂着色器（仅需简单外发光） |
| 得分时 0.2s 画面闪烁 | 得分动画或文字效果 |
| 中线淡蓝虚线 | 其他装饰元素 |
| `--headless --quit` 无错误 | 性能优化（Forward+ 渲染器足以处理此规模） |

---

## 2. 设计意图

### 为什么是现在

#301 已搭建 Mini Pong 骨架，包括 Forward+ 渲染器和 glow/bloom 基础设施。Issue #289 是 Mini Pong 的**第一个视觉层**——在骨架之上建立视觉风格。没有此视觉系统，后续所有 Pong 功能开发都在默认灰底上运行，无法体现赛博霓虹风格。

### 为什么选择此方案

用户明确指定了赛博霓虹（Cyber Neon）风格：深色底、霓虹色对比、发光效果、粒子拖尾。Godot 4.x 的 Forward+ 渲染器原生支持 glow/bloom，GPU 粒子系统，以及 ShaderMaterial——所有需求都可以用内置功能实现，无需第三方插件。

### 设计原则

1. **纯视觉层：** 不触及任何游戏逻辑代码。本 Issue 只创建/修改视觉资源（场景节点、材质、着色器）。
2. **利用现有基础设施：** Forward+ 和 glow/bloom 已在 #301 中启用。本 Issue 在此之上配置 bloom 阈值、调整颜色、添加粒子系统的材质。
3. **最小侵入：** 新的视觉节点（GPUParticles2D、ColorRect、Line2D）附加到现有游戏对象，不改变节点层级结构。
4. **2D 对应：** 虽然 Mini Pong 是 2D 项目，GPUParticles2D（不是 3D 版本）适用。ShaderMaterial 使用 canvas_item 着色器（2D 着色器）。

### 先前约束

| 约束 | 来源 | 影响 |
|------|------|------|
| Forward+ 渲染器，glow/bloom 已启用 | #301 project.godot | 发光效果可直接工作，无需额外配置 |
| `glow_intensity=0.6` 已在 WorldEnvironment | #301 world_environment.tscn | bloom 阈值需额外设置为 0.8 |
| Mini Pong 为独立子项目 | #301 | 所有文件在 `mini-pong/` 下，不影响根项目 |
| 无 main_scene | #301 | 视觉资源创建后可被后续 Issue 的主场景引用 |
| 2D 项目 | #301 project.godot | 使用 CanvasItem 着色器、GPUParticles2D（非 3D） |

---

## 3. 影响分析

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/gdscripts/neon_glow.gdshader` | Godot Shader | canvas_item 外发光着色器（球+球拍共用） |
| `mini-pong/gdscripts/ball_trail.gd` | GDScript | 控制 GPUParticles2D 跟随球、管理发射状态 |
| `mini-pong/gdscripts/score_flash.gd` | GDScript | 管理得分闪烁 ColorRect，触发信号后 0.2s 淡出 |
| `mini-pong/assets/gradient_neon.tres` | GradientTexture1D | 球拖尾渐变（霓虹蓝→紫） |
| `mini-pong/assets/particle_material.tres` | ParticleProcessMaterial | GPUParticles2D 粒子材质配置 |

### 修改文件

| 文件 | 修改内容 | 性质 |
|------|----------|------|
| `mini-pong/scenes/world_environment.tscn` | 添加 `glow_bloom` 阈值 0.8；设置背景色 #0a0a12 | 配置增量 |
| `mini-pong/project.godot` | 添加 `rendering/environment/defaults/default_clear_color` = #0a0a12 | 配置增量 |

### 被影响的现有文件（由后续 Issue 创建后影响）

| 未来文件 | 视觉层注入 | 方式 |
|----------|-----------|------|
| 球场景 | GPUParticles2D 子节点 + ShaderMaterial | 附加节点 |
| 玩家球拍场景 | ShaderMaterial 覆盖 + modulate #4a90d9 | 材质替换 |
| AI 球拍场景 | ShaderMaterial 覆盖 + modulate #ff3355 | 材质替换 |
| 主场景 | ColorRect overlay（得分闪烁）、Line2D 中线 | 附加节点 |

### 数据流

```
project.godot
    │  rendering/environment/defaults/default_clear_color = #0a0a12
    │
world_environment.tscn
    │  glow_intensity = 0.6 (已有)
    │  glow_bloom = 0.8 (新增)
    │  background_mode → clear_color → #0a0a12
    │
neon_glow.gdshader (canvas_item)
    │  └──► 被球拍 ShaderMaterial 引用（玩家: #4a90d9 / AI: #ff3355）
    │       被球 ShaderMaterial 引用
    │
ball_trail.gd
    │  └──► 控制 GPUParticles2D 节点
    │        └──► particle_material.tres (ParticleProcessMaterial)
    │             └──► gradient_neon.tres (GradientTexture1D: 蓝→紫)
    │
score_flash.gd
    │  └──► 控制 ColorRect overlay (0.2s 闪烁)
    │       signal: player_scored(color) → flash(color) → tween fade out
    │
Line2D / TextureRect (中线)
    │  淡蓝色虚线，静态装饰
```

### 文档更新

- 无需更新现有文档——这是视觉层，不改变架构或设计约定

---

## 4. 方案对比

### 方案 A：Godot 内置特效（推荐）

使用 Godot 内置的 WorldEnvironment glow/bloom + GPUParticles2D + 简单 canvas_item ShaderMaterial。

**描述：** 所有效果均使用 Godot 4.x 内置功能实现。Bloom 阈值通过 WorldEnvironment 配置，粒子拖尾用 GPUParticles2D + GradientTexture1D，发光轮廓用 canvas_item shader 绘制外发光边框。

| 维度 | 评估 |
|------|------|
| 优点 | 零依赖、性能优秀（GPU 原生）、代码量少、与其他 Godot 项目兼容性好 |
| 缺点 | canvas_item shader 外发光效果比全屏后处理简单——但对于 2D Pong 足够 |
| 风险 | 低 |
| 工作量 | 2-3 天 |

### 方案 B：全屏后处理 Shader

使用全屏 ColorRect + 自定义 screen-reading shader 做后处理发光。

**描述：** 用一个覆盖全屏的 ColorRect 运行 screen-reading shader，检测边缘并叠加发光。所有发光效果统一由后处理完成，不需要逐对象 ShaderMaterial。

| 维度 | 评估 |
|------|------|
| 优点 | 统一发光效果、画面更一致 |
| 缺点 | 额外 draw call 开销、screen texture 采样性能成本、粒子拖尾仍需独立系统、过度设计 |
| 风险 | 中 |
| 工作量 | 3-5 天 |

### 方案 C：AnimatedSprite2D 帧动画伪装

用预渲染的发光精灵帧（带 glow 的球/球拍）代替实时渲染发光。

**描述：** 在外部工具中渲染好带发光效果的精灵动画帧，以 AnimatedSprite2D 播放，不使用实时 shader。

| 维度 | 评估 |
|------|------|
| 优点 | 完全控制视觉效果、无 shader 编译问题 |
| 缺点 | 资产体积大、无法动态变色、不支持粒子拖尾的实时渐变、与赛博动态风格理念冲突 |
| 风险 | 低（技术）但高（灵活性） |
| 工作量 | 4-6 天（需大量资产制作） |

### 推荐：方案 A

方案 A 最契合 Issue 需求：

1. **Bloom 阈值已在 WorldEnvironment 半配置** — 仅需添加 `glow_bloom = 0.8`
2. **GPUParticles2D 是 Godot 内置粒子系统** — 渐变材质一行代码配置，发射器跟随球节点
3. **Canvas_item shader 外发光** — 简单高效，约 20 行 shader 代码
4. **全内置、零外部依赖** — 符合 MVP 最小化原则
5. **Forward+ 渲染器原生支持** — 已在 project.godot 中配置

方案 B 对简单的 2D Pong 过度设计。方案 C 丧失了霓虹动态感的核心体验。

---

## 5. 边界条件与验收标准

### 验收标准

- [ ] **AC1: glow 强度 0.6, bloom 阈值 0.8** — `world_environment.tscn` 中 `glow_intensity=0.6`（已有）且 `glow_bloom=0.8`
- [ ] **AC2: 背景 #0a0a12** — WorldEnvironment / project.godot default_clear_color = `Color(0.039, 0.039, 0.071, 1)`（#0a0a12）
- [ ] **AC3: 玩家球拍霓虹蓝 #4a90d9** — 玩家 paddle modulate 或 ShaderMaterial 设置为 #4a90d9
- [ ] **AC4: AI 球拍霓虹红 #ff3355** — AI paddle modulate 或 ShaderMaterial 设置为 #ff3355
- [ ] **AC5: 球 GPUParticles2D 拖尾** — 球节点附加 GPUParticles2D 子节点，发射霓虹蓝→紫渐变粒子
- [ ] **AC6: 球发光轮廓** — 球节点使用 ShaderMaterial（canvas_item 外发光 shader）
- [ ] **AC7: 球拍发光轮廓** — 玩家和 AI 球拍均使用 ShaderMaterial 外发光
- [ ] **AC8: 得分闪烁 0.2s** — 得分时 ColorRect overlay 显示对应队伍颜色，0.2s 淡出
- [ ] **AC9: 淡蓝虚线中线** — 场景中有淡蓝色虚线分隔线
- [ ] **AC10: --headless 无错误** — `godot --path mini-pong/ --headless --quit` 退出码 0

### 边缘情况

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | 球静止（游戏未开始） | GPUParticles2D 发射 paused/lifetime=0，不产生拖尾 |
| 2 | 球速度极快 | 粒子发射率与球速度成正比，拖尾连续不中断 |
| 3 | 球拍未创建（场景无 paddle 节点） | ShaderMaterial 路径缺失不应导致崩溃——fallback 默认材质 |
| 4 | 连续快速得分（2 次得分间隔 < 0.2s） | 新闪烁覆盖旧闪烁——用 Tween 时 kill 旧 tween 再启动新 tween |
| 5 | bloom 阈值 0.8 在高亮场景下 | Forward+ 渲染器仅对亮度 > 0.8 的像素应用 bloom——深色背景不会被错误 bloom |
| 6 | 编辑器 vs headless 渲染差异 | headless 模式无 GPU 渲染输出，不验证视觉效果——仅验证脚本/场景编译无误 |
| 7 | 中线在不同分辨率下 | Line2D 位置使用相对坐标（相对于 viewport 中心），不同分辨率下居中 |

### 失败路径

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | GPUParticles2D 材质丢失 | 粒子可见但无色（白色默认）——不应崩溃 |
| 2 | shader 编译错误 | Godot 输出 shader 编译日志错误——headless 模式下脚本仍可执行 |
| 3 | ColorRect 未找到（score_flash.gd 路径错误） | `get_node()` 返回 null 时跳过闪烁——不抛异常 |

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #301 Mini Pong 骨架 | ✅ CLOSED | 无 | Forward+、glow/bloom、WorldEnvironment 已就绪 |
| Godot 4.7 | ✅ 已安装 | 无 | 构建环境 |
| GPUParticles2D API | ✅ 内置于 Godot | 无 | Godot 4.x 标准节点 |
| ShaderMaterial canvas_item | ✅ 内置于 Godot | 无 | 无需外部着色器编译器 |

### 阻塞

| 未来工作 | 优先级 | 说明 |
|----------|:------:|------|
| 球物理 + 球拍控制 | 高 | 视觉系统附着在球/球拍节点上——需要这些节点存在 |
| 计分系统 | 高 | score_flash.gd 需要 score_changed 信号 |
| 主场景组装 | 高 | 中线 Line2D、ColorRect overlay 放在主场景中 |

### 依赖链

```
#301 (Scaffold) ✅
    │
    └──► #289 (本 PRD — 视觉系统)
            │
            ├──► 球/球拍逻辑 Issue (需要视觉材质)
            ├──► 主场景组装 Issue (需要中线、ColorRect)
            └──► 计分系统 Issue (需要 score_flash.gd 闪烁)
```

### 前置准备

- [x] `mini-pong/project.godot` 存在，glow/bloom 已启用
- [x] `mini-pong/scenes/world_environment.tscn` 存在，glow_intensity=0.6
- [ ] 确认 `mini-pong/gdscripts/` 目录存在（用于存放 .gd 和 .gdshader）
- [ ] 确认 `mini-pong/assets/` 目录存在（用于存放 .tres 资源）

---

## 7. Spike / 实验

> **Skipped per `depth/standard` label.**
>
> 此 Issue 的视觉效果在 Godot 4.x Forward+ 中有成熟的内置支持（glow/bloom、GPUParticles2D、ShaderMaterial），不存在技术不确定性。
> 如发现 glow_bloom 0.8 在 headless 模式下无法验证视觉效果，可在 plan 阶段添加编辑器内截图验证步骤。

---

## 8. 延续上下文（Plan Agent 交接）

### 当前系统状态

- `mini-pong/project.godot`：Forward+ 渲染器，`environment/glow_enabled=true`，无 `default_clear_color`，无 `main_scene`
- `mini-pong/scenes/world_environment.tscn`：WorldEnvironment 节点，`glow_intensity=0.6`，无 `glow_bloom`，背景模式为 `background_mode=0`（Clear Color）
- `mini-pong/gdscripts/`：空目录
- `mini-pong/assets/`：空目录
- 项目默认分支：`main`

### 本 PRD 的核心交付物

| 类型 | 文件 | 关键内容 |
|------|------|----------|
| 场景修改 | `world_environment.tscn` | +`glow_bloom=0.8`, +`background_color=#0a0a12` |
| 配置文件 | `project.godot` | +`rendering/environment/defaults/default_clear_color` |
| Shader | `gdscripts/neon_glow.gdshader` | canvas_item 外发光（uniform: glow_color, glow_width） |
| 资源 | `assets/gradient_neon.tres` | GradientTexture1D：霓虹蓝(#4a90d9)→紫(#8833ff) |
| 资源 | `assets/particle_material.tres` | ParticleProcessMaterial：寿命、发射率、渐变指向 |
| 脚本 | `gdscripts/ball_trail.gd` | 挂载到球场景，管理 GPUParticles2D 发射 |
| 脚本 | `gdscripts/score_flash.gd` | 挂载到主场景 ColorRect，0.2s 闪烁动画 |

### 实施注意事项

1. **WorldEnvironment 背景色：** 在现有 `world_environment.tscn` 中添加 `background_color = Color(0.039, 0.039, 0.071, 1)`（#0a0a12 的线性值）。或者通过 `project.godot` 的 `rendering/environment/defaults/default_clear_color` 设置全局默认。

2. **Bloom 阈值配置：** 在 WorldEnvironment 的 Environment 资源子资源中添加 `glow_bloom = 0.8`。这控制什么亮度的像素参与 bloom——阈值越高，只有真正的霓虹高光才发光。

3. **Canvas_item 外发光 Shader：** `neon_glow.gdshader` 应使用 `canvas_item` 渲染模式，在 FRAGMENT 函数中沿 UV 边缘叠加发光颜色。简单实现：检测到当前像素与相邻像素的 alpha 差异时输出 glow_color。

4. **GPUParticles2D 拖尾：** 
   - 作为球节点的子节点附加
   - 使用 `ParticleProcessMaterial`（而非 ShaderMaterial）配置粒子属性
   - `gradient` 属性引用 `gradient_neon.tres`（GradientTexture1D）
   - `lifetime` ~0.5s，`amount` ~50，`emission_shape` = point
   - 脚本 `ball_trail.gd` 根据球的速度调整 `emitting` 和 `amount_ratio`

5. **得分闪烁实现：**
   - 在主场景根节点下放置 ColorRect（全屏、初始 alpha=0）
   - `score_flash.gd` 暴露 `flash(color: Color)` 方法
   - 使用 `create_tween()` 将 modulate.a 从 1.0 → 0.0，持续时间 0.2s
   - 在 `_ready()` 中连接计分信号

6. **中线 Line2D：** 在游戏区域中央画一条竖线，颜色 = `Color(0.4, 0.6, 0.9, 0.5)`（淡蓝半透明），使用虚线样式（`width=2`, dash 线段）。

7. **验证方法：**
   ```bash
   godot --path mini-pong/ --headless --quit
   echo "Exit: $?"
   ```
   注意：headless 模式不渲染视觉效果，只能验证脚本/场景编译无误。实际视觉效果需在 Godot 编辑器中验证。

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|:------:|:----:|----------|
| `glow_bloom` 键名在 Godot 4.x TSCN 中不正确 | 中 | 中（bloom 不生效） | 在 Godot 编辑器中打开 world_environment.tscn 验证 bloom 属性显示 |
| GPUParticles2D 在 headless 模式下报错 | 低 | 低 | 粒子系统是 Godot 核心节点，headless 模式应正常编译 |
| ShaderMaterial 中的 canvas_item shader 语法错误 | 中 | 中（球拍无发光） | headless 验证 + 编辑器 compile 检查 |
| 球/球拍节点尚不存在，视觉脚本引用空路径 | 高 | 中（脚本无法测试） | Plan Agent 应与球/球拍 Issue 协调——本 PRD 只创建资源，引用在后续 Issue 中建立 |

### 下一步

Plan Agent 将使用此 PRD 创建 DESIGN 文档，详细指定每个文件的内容（shader 代码、TSCN 片段、GDScript 逻辑）。Implement Agent 将创建所有新文件并修改 WorldEnvironment。视觉资源创建后，球/球拍逻辑 Issue 可以直接引用已存在的 ShaderMaterial 和粒子系统资源。

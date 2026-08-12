# PRD: [Feature] 动态雨幕 — Dynamic Rain Screen

> **Issue:** #389
> **标签:** enhancement, graphics, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#383/#378 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 跳过）
> **所有权:** `content_ownership: mechanical`（雨量映射规则机械可测；浓度曲线数值走 @export 可调，供后续 taste 校准，不阻塞本 Issue）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3.1/§3.2（2026-08-13 用户已确认「雨夜竞技场」画面方案 + 动态雨量公式）— 本 PRD 是该方案 L0 氛围层 Issue 的研究落地

---

## 1. 问题定义

### 当前状态

Mini Pong 已随 #383 完成竖屏改造（720×1280，球沿 Y 轴垂直对打）。Rogue Pong 的画面方案（PLAN-rogue-pong §3.1）定义 4 层 CanvasLayer 架构，其中 **L0 氛围层 = 雨幕粒子** 目前完全缺失：

| 系统 | 当前状态 | 差距 |
|------|---------|------|
| 雨幕 GPUParticles2D | ❌ 不存在 | 需新建雨幕粒子 + 材质 + 控制器 |
| 雨量公式执行层 | ❌ 不存在 | PLAN §3.2 只定义了公式契约（`rain = base(0.3) + 球速因子 + 波次因子(+0.1/波) + 紧张因子(比分差≤2→+0.2) + 事件脉冲(穿墙+0.4 / 失败→1.0) − 喘息(升级选择→0.15)`，clamp(0.1,1.0)），没有任何运行时组件消费它 |
| 粒子基础设施 | ✅ 已有 | #289 已建 `ball_trail.gd` + `assets/particle_material.tres`（GPUParticles2D + ParticleProcessMaterial 模式，headless 安全），可复用同款模式 |
| 球速数据源 | ✅ 已有 | `ball.gd` 公开 `speed` 属性（330→627 px/s，指数递增），随 paddle 击打上升 |
| 比分紧张数据源 | ✅ 已有 | `GameManager.player_score/ai_score` + `score_changed` 信号 |
| 事件脉冲源 | ✅ 部分 | `ball.score(side)` → `ScoringManager.scored`（得分=可挂脉冲）；`GameManager.match_over`（对局结束=可挂 1.0 宣泄）；**穿墙/拆砖/波次/升级选择尚不存在**（#384/#386/#388 未实现） |
| 波次/砖墙/喘息窗口 | ❌ 未实现 | #384 砖墙、#386 波次循环、#388 升级 UI 均为 OPEN——雨量公式中的波次因子/拆砖脉冲/喘息项只能以 **API 钩子 + @export 默认值** 形式预留 |

### 预期行为（验收条件，源自 Issue #389）

1. **场景内存在 GPUParticles2D 雨幕且默认雨量可调** — Main.tscn 新增 L0 雨幕层；雨量 = `rain_controller` 上可读可写的 `display_intensity`（0.1..1.0），默认 0.3（base）
2. **雨量由公式计算并 clamp 在 0.1..1.0** — `target = clamp(base + 球速因子 + 波次因子 + 紧张因子 + 事件脉冲 − 喘息, 0.1, 1.0)`，映射规则机械可测
3. **球速/波次/拆砖事件会提高雨量，喘息期会降低雨量** — 球速因子现接（读 `ball.speed`）；波次因子/拆砖脉冲/喘息以公开 API（`set_wave_factor(n)` / `add_event_pulse(v)` / `set_resting(b)`）预留，待 #384/#386/#388 接入后驱动（验收：API 级测试可断言）
4. **雨量变化在 0.5s 内平滑过渡，不产生突兀跳变** — 指数平滑（τ=0.15s，0.5s 内到达目标的 ~96%），单帧跳变有上限
5. **--headless 下粒子场景不报错** — 沿用 ball_trail 的节点守卫模式（`push_warning` 降级不崩）

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 开局/菜单 | 每次启动 | 雨夜竞技场 L0：雨幕以 base(0.3) 强度存在，默认雨量可调（编辑器 @export / 运行时属性） |
| B | 对打中 | 持续 | 球速越打越快 → 球速因子 0→0.3 抬升雨量，紧张感"看见"难度曲线 |
| C | 得分瞬间 | 每分 1 次 | 事件脉冲 +0.4 快速抬升后 ~1.5s 回落（穿墙脉冲语义的现役替身）；对局结束脉冲 → 1.0 宣泄 |
| D | 比分胶着 | 随机 | 比分差 ≤2 → 紧张因子 +0.2，雨量进入 0.7 窒息区 |
| E | Rogue Pong 后续 | #384/#386/#388 之后 | 波次因子（+0.1/波）、拆砖脉冲、升级喘息（−0.15）通过公开 API 接入，无需改雨幕组件 |
| F | 本地 E2E | 每个实现 PR | headless 全绿 + `run-e2e-review.sh` 竖屏截图；雨幕不得破坏 `theme_color=4a90d9` 断言 |

### 技术约束（继承自 Issue #389 + PLAN-rogue-pong §3.1/§3.2）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`） |
| 画幅 | 720×1280 竖屏；雨幕垂直下落（gravity +Y）与球攻击主轴同轴 |
| 粒子类型 | **GPUParticles2D 强制**（AC-1 字面要求；非 shader-only） |
| 层序 | L0 氛围层（CanvasLayer，位于世界层之下/背景之上）— 不遮挡球/挡板/HUD |
| 公式 | Issue body + PLAN §3.2：`base + 球速 + 波次 + 紧张度 + 事件脉冲 − 喘息`，`clamp(0.1,1.0)` |
| 平滑 | 0.5s 内过渡，无突兀跳变（AC-4） |
| 所有权 | `content_ownership: mechanical` — 映射规则机械可测；浓度曲线数值（base/增益/阈值）走 constants + @export，后续 taste 校准不阻塞 |
| 开源优先 | 调研结果见 §1.4 |
| headless | `--headless` 下粒子场景不报错（AC-5） |

### 1.4 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索）+ 社区：

- **Godot Asset Library**（assetlibrary.godotengine.org，godot 4.x，filter=rain / filter=particles）：无任何 2D 雨幕资产。「rain」过滤返回的全是子串误匹配（brainCloud SDK、Terrain3D 系列、FilmGrain 等）；particles 过滤仅 UniParticles3D（3D 工具）、BurstParticles2D（爆发特效工具，非雨幕）、Fancy particles（杂项）
- **GitHub**（GDScript 过滤，按 star）：`Lexpartizan/Godot_rain_shader` ⭐102 = **3D PBR 材质 shader**（湿表面/积水/雨滴纹理，Unreal 系教程衍生，WIP）— 与 2D GPUParticles2D 雨幕完全不适用；`ffttasd/godot_rain` ⭐9、`realjf/godot-rain-particle-system-demo` ⭐2、`ffttasd/godot_rain_2d` ⭐1 — 均为无 README/无维护的微型 demo，license 与质量不可依赖
- **结论**：**不存在可插拔的成熟 2D 雨幕资产**；且 AC-1 强制 GPUParticles2D，第三方 shader 方案直接违反验收条件。**自行实现**，复用 #289 已建立的 `GPUParticles2D + ParticleProcessMaterial` 第一方模式（`ball_trail.gd` 同款），零第三方依赖。砖块生成/UI 主题等其它资产类别的开源调研分属 #384/#392 各自 Issue body，不在本 Issue 范围。

---

## 2. 设计意图

### 为什么当前状态存在

Rogue Pong 的画面方案（PLAN §3.1）在 2026-08-13 才被用户确认（「雨夜竞技场 — 动态雨量是情绪仪表盘」），而 mini-pong 本体（#287→#295→#383）一直在打 Pong 的物理/布局地基。雨幕作为 L0 氛围层排在砖墙（#384）、波次（#386）之前实现，因为它是**整局贯穿的视觉基调**：球速、得分、未来的波次/拆砖全都映射到雨量上，雨幕必须先行存在，后续系统才能往它上面挂因子。

### 为什么现在改

1. **参数契约已就绪**：PLAN §3.2 把雨量公式钉死了（base/波次因子/紧张因子/事件脉冲/喘息/clamp），本 Issue 正是该契约的**执行层**（Patch 19 参数契约→执行层模式）：契约定义了"有哪些值、什么含义"，执行层负责"这些值如何变成粒子行为"
2. **数据源全部在位**：球速（`ball.speed`）、比分（`GameManager`）、得分事件（`ScoringManager.scored`）、对局结束（`match_over`）——机械映射无需等待任何未来系统
3. **粒子模式已验证**：#289 的 `ball_trail.gd` 证明 GPUParticles2D 在本项目 headless 下安全可测（test_neon TC7/TC13/TC14），雨幕沿用同款即可
4. **审美坐标系**（Obsidian 知识库检索，§8 引用）：《体验引擎-glossary》——**Atmosphere（氛围）= 弥漫在整个体验中的情感背景，在没有特定事件吸引注意力时被感知**（雨幕正属于 L0"被感知但不抢戏"层）；**Challenge = 紧张感与精通的潜力**（雨量 = 紧张感的可视化仪表）。《体验引擎-patterns》——"低技能的情绪触发器（美术、音乐、叙事钩子）在学习期间保持参与度，案例：BioShock 氛围开场"。雨幕是典型的低技能情绪触发器：不增加操作负担，只抬升情绪水位

### 先前约束

- #289 已用 GPUParticles2D 做球拖尾 → 粒子渲染管线（Forward+、glow）已配置，雨幕零新渲染配置
- #383 竖屏已定 720×1280 → 雨幕发射区覆盖顶部 720px 宽、下落贯穿 1280px
- PLAN §3.2 明示「映射规则 = **机械**(可测)；浓度曲线 = **taste-draft**(人调)」→ 本 Issue（mechanical）实现机械映射；浓度数值放 constants + @export，后续人调不碰代码结构

---

## 3. 影响分析

### 直接改动文件

| 文件 | 改动 | 说明 |
|------|------|------|
| `mini-pong/gdscripts/constants.gd` | 修改 | 新增 `RAIN_*` 常量组（base/clamp/波次步进/紧张阈值与增益/脉冲/喘息/平滑 τ）— 单一事实源惯例（#295） |
| `mini-pong/scenes/Main.tscn` | 修改 | 新增 `RainScreen`（CanvasLayer L0）+ 实例化 `rain_screen.tscn`；位于世界层节点之下（背景之上） |

### 新文件

| 文件 | 内容 |
|------|------|
| `mini-pong/scenes/rain_screen.tscn` | CanvasLayer(L0) + `RainParticles`(GPUParticles2D) + `rain_controller.gd`（镜像 ball_trail 模式） |
| `mini-pong/gdscripts/rain_controller.gd` | 雨量公式执行层：`target_intensity` 计算（base+球速因子+波次因子+紧张因子+脉冲−喘息，clamp）、指数平滑（τ=0.15s）、`amount_ratio`/速度/密度驱动、公开 API（`set_wave_factor`/`add_event_pulse`/`set_resting`）、信号接线（score→脉冲、match_over→1.0）、节点守卫 |
| `mini-pong/assets/rain_material.tres` | ParticleProcessMaterial：gravity(0, +2000)、initial_velocity 600–900、lifetime 0.6–1.0、细线粒子（scale 1–2px 纵向拉伸）、冷灰蓝半透色、emission_shape=Rectangle 覆盖顶部 |
| `mini-pong/tests/test_rain.gd` | TC 组：公式 clamp / 球速因子单调 / 紧张因子 / 脉冲衰减 / 0.5s 平滑无跳变 / headless 场景加载（镜像 test_neon 结构） |

### 间接影响（需回归验证）

| 影响面 | 风险 | 缓解 |
|--------|------|------|
| `e2e_shots.json` loop 组（match `gdscripts/.*\.gd` + `scenes/.*\.tscn`） | 雨幕改动必然命中 → L3 视觉截图会执行 | 雨幕在 MENU 态保持 base(0.3) 低强度 + 低透明度，`analyze_bmp` 的 `theme_color=4a90d9` 断言不受雨粒干扰；实现 PR 必须真实跑 E2E |
| `test_main_scene.gd` / `test_neon.gd` | Main.tscn 加节点可能触碰现有断言 | 只新增节点不移动现有节点路径；test_neon 只断言 ball_trail 相关，不受影响 |
| `game_state_machine.gd` | 雨幕在 PAUSED/MENU 态行为 | 雨幕常驻但不影响输入/FSM（L0 纯视觉层，FSM 零改动） |
| `run_tests.gd` | 新增 test_rain.gd 需被收集 | run_tests.gd 若显式枚举测试文件需登记（实现时核对） |

### 数据流影响

```
Ball.speed ──────────────────────────────► RainController._process() 读 ball.speed → 球速因子
GameManager.score_changed(p,a) ──────────► RainController._on_score_changed → 紧张因子(比分差≤2→+0.2)
ScoringManager.scored / Ball.score ──────► RainController._on_score → add_event_pulse(+0.4, 衰减~1.5s)
GameManager.match_over ──────────────────► RainController._on_match_over → add_event_pulse(→1.0 宣泄)
[未来] #386 波次循环 ────────────────────► RainController.set_wave_factor(n)  (+0.1/波)
[未来] #384 拆砖事件 ────────────────────► RainController.add_event_pulse(v)（拆砖脉冲）
[未来] #388 升级 UI ─────────────────────► RainController.set_resting(true)  (−0.15)
target_intensity ── 指数平滑(τ=0.15s, 0.5s≈96%) ──► GPUParticles2D.amount_ratio（主）+ initial_velocity 缩放（次）
```

### 文档更新

- 本 PRD 即文档；`docs/GAME_DESIGN/` 由后续 pipeline 沉淀（雨量系统 = f(波次) 同构关系已在 #396 PRD §2 / 21-WAVE-FAILURE-TEXT.md 引用，本 PRD 为其提供机械地基）

---

## 4. 方案对比

### Approach A：单一控制器 + 指数平滑（推荐）

`rain_controller.gd` 持有 `target_intensity`（公式输出）与 `display_intensity`（平滑后），每帧 `display += (target − display) * (1 − exp(−delta/τ))`，τ=0.15s → 0.5s 内到达目标的 ~96%；`amount_ratio = display_intensity`，粒子初速随强度线性缩放。

- **Pros**：连续量（球速逐帧变化）天然平滑，无 tween 重启抖动；公式/平滑/API 全部集中一处，机械可测（纯函数 + 确定性断言）；与 ball_trail 模式同构，实现成本低
- **Cons**：指数平滑的"到达率"是渐近而非线性——验收断言需用"0.5s 内 ≥95%"或"单帧跳变上限"表述，不能钉死 0.5s 整点值
- **Risk**：低（模式已被 ball_trail 验证）
- **Effort**：S（~200 行 + 1 测试文件）

### Approach B：Tween 固定 0.5s 线性过渡

每次 `target` 变化时 kill 旧 tween、起新 tween 线性插值 0.5s。

- **Pros**：0.5s 语义字面贴合 AC-4，断言直观（t=0.25s 取中值）
- **Cons**：球速每帧都在变 → tween 每帧重启 → 雨量永远追不上目标（抖动/滞后）；事件脉冲与连续因子混用同一通道会互相打断
- **Risk**：中（连续输入下行为劣化）
- **Effort**：S

### Approach C：Shader-only 雨幕（屏幕空间 shader）

CanvasLayer 上挂全屏 shader 画雨丝，不用 GPUParticles2D。

- **Pros**：单文件、性能最好
- **Cons**：**直接违反 AC-1（场景内存在 GPUParticles2D 雨幕）**；动态雨量需另写 uniform 传递，机械可测性差
- **Risk**：高（验收必挂）
- **Effort**：S

### Approach D：复用第三方资产

调研结论（§1.4）：Godot Asset Library 无 2D 雨幕资产；GitHub 候选均为 3D 材质 shader（Lexpartizan ⭐102）或无维护微型 demo（≤9⭐）。

- **Pros**：无
- **Cons**：适用性为零（3D PBR vs 2D 粒子），license/质量不可依赖
- **Risk**：高（引入即返工）
- **Effort**：M（含集成/改写成本）

### 推荐

**Approach A**。理由：唯一满足全部 AC 且对连续输入（球速）鲁棒的方案；与 #289 既有粒子模式一致；公式执行层 + API 钩子结构天然承接 PLAN §3.2 契约与未来 #384/#386/#388 接入。B 的 0.5s 语义由 A 的 τ 参数（0.15s → 0.5s ≈ 96%）等价覆盖，并在测试中显式断言。

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body）

| AC | 验收方式 |
|----|---------|
| 场景内存在 GPUParticles2D 雨幕且默认雨量可调 | `test_rain.gd`：实例化 `rain_screen.tscn`，断言 `RainParticles` 为 GPUParticles2D；`display_intensity` 可写且默认 0.3 |
| 雨量由公式计算并 clamp 在 0.1..1.0 | 纯函数测试：输入极端因子组合，断言输出 ∈ [0.1, 1.0] |
| 球速/波次/拆砖事件提高雨量，喘息降低 | `set_wave_factor(3)` → target 上升 0.3；`add_event_pulse(0.4)` → 脉冲抬升；`set_resting(true)` → 降低 0.15；球速因子随 `ball.speed` 单调（当前代码球速/得分信号已接，波次/拆砖/喘息走 API） |
| 0.5s 内平滑过渡无跳变 | 设定 target 0.3→0.9：单帧 `|Δdisplay|` 有上限；0.5s 后 `display ≥ 0.9*0.96`；无 NaN |
| --headless 粒子场景不报错 | `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿 + `--headless --quit` 无脚本错误 |

### 边界情况（Edge Cases）

1. **菜单态（MENU）**：雨幕以 base(0.3) 常驻（L0 氛围不随状态切换），FSM 零改动
2. **暂停（PAUSED）**：`_process` 的 delta 守卫（沿用 ball.gd 的 `delta > 0.1` 跳过）防帧尖峰把雨量拉飞
3. **球静止/发球**：`ball.speed` 回到 initial → 球速因子归零，雨量回 base
4. **比分差波动**：紧张因子随 `score_changed` 重算，不累积、不迟滞
5. **连续得分**：脉冲叠加取 max（`pulse = max(pulse, new)`）而非累加，防两次得分脉冲爆 1.0 顶格失真
6. **节点缺失**：`RainParticles` 不存在时 `push_warning` 降级（ball_trail 同款），不崩
7. **E2E 截图**：雨幕半透明 + 低对比，`analyze_bmp` 的 `theme_color=4a90d9` 断言不破（实现 PR 必须实跑验证）

### 失败路径（Failure Paths）

1. **粒子材质引用断裂**：`rain_material.tres` 路径错误 → test 断言材质可读（镜像 test_neon TC7 写法）
2. **公式 NaN**：`ball.speed` 为 0 时除法 → 除零守卫（`max(speed, 1)`），NaN 检查落入测试
3. **E2E 颜色断言被雨粒破坏**：降粒子透明度/减少 MENU 态发射量，或调 `amount_ratio` 上限映射

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 关系 |
|------|------|------|
| #383 轴交换+竖屏（P0 前置） | ✅ CLOSED | 竖屏坐标系为雨幕提供画幅；Main.tscn 布局已定 |
| #289 霓虹视觉 | ✅ CLOSED | GPUParticles2D 渲染管线/glow 已配置，ball_trail 模式可复用 |
| #295 Main 组装 | ✅ CLOSED | Main.tscn 节点结构与 constants 单一事实源惯例 |

### 阻塞（Blocks）

无。本 Issue 不阻塞任何现有 OPEN Issue（#384/#386/#388 依赖雨幕 API，但以"接入方"身份出现，非本 PRD 前置）。

### 依赖链

```
#383 (✅) ──► #389 动态雨幕 ──► (API 钩子) #384 砖墙 / #386 波次循环 / #388 3选1升级UI
```

---

## 7. Spike / 实验

> depth/standard：本节可选，跳过（粒子方案已被 #289 ball_trail 实证，公式已被 PLAN §3.2 钉死，无未验证技术风险）。

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #389 当前 `workflow/research`，本 PRD merge 后 workflow-chain 自动推进 → `workflow/plan`
- 基线：`main` 为竖屏 720×1280 完整可跑（#383 已合，headless 测试绿）
- 上游方案：`docs/PLAN-rogue-pong.md` §3.1（L0 雨幕）/§3.2（雨量公式）——plan agent 必须读

### 关键决策（plan agent 必须继承）

1. **Approach A 单一控制器 + 指数平滑**（§4）：`rain_controller.gd` 持有 `target_intensity`/`display_intensity`，τ=0.15s；`amount_ratio = display_intensity` 为主驱动，粒子初速线性缩放为次
2. **公式**（PLAN §3.2 + Issue body）：`target = clamp(base(0.3) + 球速因子(0..0.3) + 波次因子(0.1×wave) + 紧张因子(比分差≤2→+0.2) + 事件脉冲(得分+0.4 衰减~1.5s / 对局结束→1.0) − 喘息(0.15), 0.1, 1.0)`；球速因子 = `(speed − 330) / (627 − 330) × 0.3`
3. **常量进 `constants.gd`**（`RAIN_*` 组，单一事实源 #295 惯例）+ 控制器 `@export` 镜像（ball.gd 同款写法），浓度数值后续 taste 校准不碰结构
4. **API 钩子（未来系统接入契约，机械可测）**：`set_wave_factor(n: float)`、`add_event_pulse(v: float)`、`set_resting(b: bool)`；#384 拆砖→`add_event_pulse(0.4)`、#386 波次→`set_wave_factor(0.1×wave)`、#388 升级 UI→`set_resting(true)`
5. **现接信号**：`ScoringManager.scored`（或 `Ball.score`）→ 脉冲 +0.4；`GameManager.match_over` → 脉冲 1.0；比分差读 `GameManager` 或 `score_changed` 重算；球速每帧读 `ball.speed`
6. **L0 层序**：`RainScreen`(CanvasLayer) 置于 Main.tscn 世界节点之前/之下（背景之上、球/挡板/HUD 之下）；FSM/scoring 零改动
7. **粒子参数**：gravity(0,+2000)、initial_velocity 600–900、lifetime 0.6–1.0、纵向细线、冷灰蓝半透、emission Rectangle 覆盖顶部 720px；默认 amount ~600（`amount_ratio` 驱动）
8. **E2E**：雨幕改动命中 `e2e_shots.json` loop 组 → 实现 PR 必须真实跑 `run-e2e-review.sh`（竖屏 720×1280），MENU 态雨量 0.3 + 低透明度确保 `theme_color=4a90d9` 断言不破

### 实现顺序建议（plan agent 参考）

1. `constants.gd`（RAIN_* 常量）→ 2. `rain_material.tres` + `rain_screen.tscn` → 3. `rain_controller.gd`（公式→平滑→驱动→API→信号接线）→ 4. `Main.tscn` 挂 L0 → 5. `tests/test_rain.gd`（登记进 run_tests.gd）→ 6. 本地 headless 全绿 + E2E 实弹截图

### 主要风险

- E2E 颜色断言被雨粒干扰（§5 失败路径 3）——实现时优先验证 MENU 态截图
- 连续得分脉冲叠加爆顶（§5 边界 5）——`pulse = max(pulse, new)` 必须实现
- run_tests.gd 显式枚举漏登记 test_rain.gd（§3 间接影响）——实现时核对

### 交接清单

- [ ] 本 PRD 文件 `docs/PRD/389-dynamic-rain-screen.md`
- [ ] 上游方案 `docs/PLAN-rogue-pong.md` §3.1/§3.2
- [ ] 参数契约引用：PLAN §3.2 公式（机械映射）+ 浓度曲线 taste 可调说明
- [ ] Obsidian 知识引用：`wiki/体验引擎-glossary.md`（Atmosphere/Challenge）、`wiki/体验引擎-patterns.md`（低技能情绪触发器）
- [ ] 实测基线：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 当前全绿（实现前可复跑对照）

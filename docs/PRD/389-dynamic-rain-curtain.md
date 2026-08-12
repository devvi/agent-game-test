# PRD: [Feature] 动态雨幕 — Dynamic Rain Curtain

> **Issue:** #389
> **标签:** enhancement, graphics, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（粒子参数调制）而包含 2 个轻量实验）
> **所有权:** `content_ownership: mechanical`（雨量映射规则 = 机械可测；浓度曲线与视觉细节 = taste-draft，走 human-review 定稿）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3.2 动态雨量（2026-08-13 已确认公式）— 本 PRD 是该公式**执行层**的研究落地
> **前置依赖:** #383（✅ CLOSED — 轴交换 + 竖屏 720×1280，雨幕垂直下落与球攻击同轴）

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong 已具备 #289 霓虹赛博视觉（glow/bloom、深底 #0a0a12、球拖尾 GPUParticles2D）与 #383 竖屏坐标系（720×1280），但 **L0 氛围层的「雨幕粒子」完全不存在**：场景中没有 GPUParticles2D 雨幕节点，没有雨量公式的执行层，也没有任何雨相关资源。PLAN-rogue-pong §3.2 已确认的雨量公式（`rain = base(0.3) + 球速因子 + 波次因子(+0.1/波) + 紧张因子(比分差≤2→+0.2) + 事件脉冲(穿墙→+0.4 回落; 失败→1.0) − 喘息窗口(升级选择→0.15)，clamp(0.1, 1.0)`）目前只是纸面契约，无人消费。

| 系统 | 当前状态 | 与需求的差距 |
|------|---------|------------|
| `mini-pong/scenes/Main.tscn` | 12 个节点（WorldEnvironment/墙/Ball/Paddle/ScoreZone/FSM/UI 层），无任何氛围层节点 | ❌ 无 L0 CanvasLayer，无雨幕实例 |
| `mini-pong/gdscripts/` | ball_trail.gd 是唯一的 GPUParticles2D 控制器（球拖尾，跟随球移动） | ✅ 粒子控制器先例存在；❌ 无雨幕控制器 |
| 雨量公式（PLAN §3.2） | ✅ 已确认（2026-08-13），含情境表（0.3 平静 → 0.9 脉冲 → 1.0 宣泄） | ❌ 无执行层消费该公式 |
| 公式输入：base / 球速 / 紧张度 | ✅ 现在可用（constants.gd 球速参数、GameManager/ScoringManager 比分） | — 本次接线 |
| 公式输入：波次因子 | ❌ 波次循环未实现（#386 backlog） | 契约接口预留，默认 0 |
| 公式输入：事件脉冲（穿墙/失败） | ❌ 砖墙 #384、双得分 #385、波次 #386 均未实现 | 契约接口预留，默认 0 |
| 公式输入：喘息窗口（升级选择） | ❌ 3选1升级 UI #388 未实现 | 契约接口预留，默认 0 |
| 视觉资源 `mini-pong/assets/` | ✅ neon_glow_material.tres / gradient_neon.tres / particle_material.tres（#289 产物） | ❌ 无雨滴纹理/雨材质 |
| `mini-pong/e2e_shots.json` | loop 原型 3 shots（01_title/02_midgame/03_gameover），`gdscripts/.*\.gd` 命中即跑 L3 | ⚠️ 雨幕加入后 02_midgame 截图自动包含雨幕，需确认 4 重断言仍过 |

### 1.2 预期行为（验收条件，源自 Issue #389）

1. **场景内存在 GPUParticles2D 雨幕且默认雨量可调** — `rain_curtain.tscn` 实例挂在 Main.tscn 的 L0 氛围层（CanvasLayer）；`rain_curtain.gd` 暴露 `@export var base_intensity` 等参数，默认雨量 = 0.3 可在检查器直接调
2. **雨量由公式计算并 clamp 在 0.1..1.0** — 公式与 PLAN §3.2 一致：`rain = clamp(base + 球速因子 + 波次因子 + 紧张因子 + 事件脉冲 − 喘息, 0.1, 1.0)`；clamp 边界由单元测试钉死
3. **球速/波次/拆砖事件会提高雨量，喘息期会降低雨量** — 球速因子与紧张因子本次接线（实时生效）；波次/事件脉冲/喘息为契约接口（`set_wave_factor()` / `trigger_event_pulse()` / `set_breathing()`），默认值下当前玩法雨量 = base + 球速 + 紧张度，不报错
4. **雨量变化在 0.5s 内平滑过渡，不产生突兀跳变** — 指数平滑（τ≈0.15s，0.5s 内到达目标的 95%+）；**禁止直接改 `amount`**（Godot 会重启粒子系统产生跳动，见 §1.5 调研证据）
5. **--headless 下粒子场景不报错** — `godot --path mini-pong/ --headless` 编译与 `run_tests.gd` 全绿；GPUParticles2D 在 headless 下不渲染但不报错

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 游戏启动/波次开始 | 每次启动 | 竖屏雨夜竞技场：细雨（0.3）开场，霓虹 glow 之上雨丝垂直下落，与攻防同轴 |
| B | Rally 进行中 | 持续 | 球速攀升雨量升至 0.4→0.6；比分胶着（差≤2）→ 0.7 窒息感；穿墙得分 → 0.9 爆发脉冲后回落 |
| C | 未来升级/失败（契约预留） | MVP 后期 | 升级选择时雨歇（0.15 喘息）；波失败雨量 1.0 宣泄（由 #384/#386/#388 驱动） |

### 1.4 技术约束（继承自 Issue #389 + PLAN-rogue-pong §3.2）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，Forward+ 渲染） |
| 画幅 | 720×1280 竖屏（#383 已落地）；雨幕 emission rect 覆盖全屏宽 720px |
| 分层架构 | PLAN §3.1 的 L0 氛围层（CanvasLayer）承载雨幕粒子；**低于** L1 世界层，不遮挡砖墙/球/挡板 |
| 公式 | PLAN §3.2 确认版（见 §1.1）；映射规则 = 机械可测；浓度曲线 = taste-draft |
| 平滑 | 0.5s 内平滑过渡，无跳变；不直接改 `amount`（粒子重启风险，§1.5） |
| 输入接线 | base/球速/紧张度本次接线；波次/事件脉冲/喘息仅契约（默认 0） |
| 不变项 | `game_state_machine.gd` / `scoring_manager.gd` / `ball.gd` 物理逻辑零改动（雨幕只读球速与比分） |
| 开源优先 | 调研结果见 §1.5 — 结论：不引入第三方资产，第一方实现并说明理由 |
| 所有权 | mechanical（映射规则）；浓度曲线/雨滴视觉 = taste-draft 候补 |

### 1.5 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索，GDScript 过滤按 star 排序）：

- **Godot Asset Library**（assetlibrary.godotengine.org，godot 4.x）：关键字 rain / 2d rain 检索无相关结果（返回均为无关工具类资产，如 Terrain3D、Spreen 等）——**无可复用 2D 雨资产**
- **GitHub `godot rain 2d` 检索（按 star）**：
  - `pirachute/godot-weather-2D` **93⭐ MIT**（2026-07 更新，GDScript，Godot 4.x）— 最成熟候选。README 明确警告：**"It's not recommended to change 'Particles Amount' while rain or snow are falling!! Godot restarts the particle system every time you change this... still it looks weird"** —— 与 AC4「0.5s 平滑过渡」直接冲突（本 Issue 的核心需求恰是运行时按公式实时调强度）；且它是风/雪/暗化全套天气系统（超出单雨幕 scope），自带纹理集与节点结构，与 PLAN §3.1 的 4 层 CanvasLayer 架构不匹配
  - `ImRains/rain-2d` 11⭐（Godot 2D 雨 demo）— 无文档、无动态强度接口，参考价值有限
  - `brendor/godot3_rain2d` 6⭐ — Godot 3 时代，已过时
- **结论**：**无可直接复用的成熟雨幕方案**。godot-weather-2D 的「参数调制而非改 amount」结论作为本 PRD 的技术证据被采纳（§4 Approach A 与 §7 Spike 直接引用）；雨滴参数（emission rect、垂直重力、速度/尺寸调制）参考其做法。实现采用**第一方 `rain_curtain.gd` + `rain_curtain.tscn`**，不引入第三方依赖，符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。

---

## 2. 设计意图

### 2.1 为什么当前状态存在

视觉系统按阶段累积，L0 氛围层被推迟到 Rogue Pong MVP：

| 现状来源 | Issue | 贡献 |
|---------|-------|------|
| 霓虹赛博视觉（glow/bloom、深底、球拖尾粒子、发光 shader） | #289 | `world_environment.tscn` + `neon_glow.gdshader` + `ball_trail.gd` |
| 竖屏坐标系（720×1280、垂直攻防） | #383 | 雨幕垂直下落与攻击同轴的地基 |
| 球速手感定稿（330 → 627 px/s） | #367 | 球速因子的映射基准（constants.gd） |
| 比分/得分信号链 | #291/#293 | 紧张因子的数据源（GameManager.score_changed） |
| 雨夜竞技场画面方案 + 雨量公式 | PLAN §3.2（2026-08-13 确认） | 公式契约（本 Issue 的执行对象） |

### 2.2 为什么现在改

1. **L0 氛围层是雨夜竞技场的门面**：PLAN §3.2 已确认「雨是情绪仪表盘」——雨量 = 视觉紧张度的动态指示器。没有雨幕，竖屏竞技场只是「深底 + 霓虹」的空壳，情绪曲线无从视觉化。
2. **公式契约已确认，执行层缺失**：PLAN §3.2 定义了完整的参数契约（base/球速/波次/紧张/脉冲/喘息），但无任何代码消费它。本 Issue 是执行层：建立公式引擎 + 粒子调制 + 平滑过渡，并按「参数契约 → 执行层」模式（项目既有模式，见 #217 先例）为未来 Issue 预留驱动接口。
3. **输入就绪度恰逢其时**：base/球速/紧张度现在即可接线（#383 竖屏已落地、#367 手感已定稿）；波次/事件脉冲/喘息由 #384/#385/#386/#388 在 MVP 后期接入——先建执行层，后续 Issue 只写 `rain_curtain.set_wave_factor(n)` 一行接入，无需改雨幕本体。
4. **成本窗口**：当前无砖墙/波次/升级，雨幕公式的真实输入少，改动面收敛（1 新控制器 + 1 新场景 + Main.tscn 挂载 + 测试），是落地 L0 层成本最低的时刻。

### 2.3 先前约束

| 约束 | 细节 |
|------|------|
| #289 视觉基调 | 深底 #0a0a12、glow_intensity 0.6、bloom 0.8；雨滴颜色建议蓝白半透明（低于霓虹主体亮度，克制优先），不得抢戏 |
| #367 手感数值 | 球速 330 → 627（×1.9 上限）为球速因子映射基准；**不改任何手感参数** |
| #383 竖屏 | 720×1280；雨幕 emission rect 覆盖全屏（720 宽），垂直下落（gravity 沿 +Y） |
| #291/#293 信号链 | 只读 `GameManager.score_changed` / ScoringManager 比分算紧张因子，**不修改信号链** |
| 测试即验收 | 新增 `test_rain.gd` 走 run_tests.gd；沿用 test_neon.gd 的资源完整性断言风格（读 .tscn/.tres 文件内容断言） |
| E2E | e2e_shots.json loop 原型命中 `gdscripts/.*\.gd`（rain_curtain.gd 必命中）→ 02_midgame 截图自动含雨幕；4 重断言（非黑/色数/主题色/帧间差异）需实测通过 |

---

## 3. 影响分析

### 3.1 新文件

| 文件 | 类型 | 职责 |
|------|------|------|
| `mini-pong/gdscripts/rain_curtain.gd` | 脚本 | 雨量公式引擎 + 粒子参数调制 + 0.5s 指数平滑 + 契约 API（`set_wave_factor` / `trigger_event_pulse` / `set_breathing` / `set_intensity` 调试口） |
| `mini-pong/scenes/rain_curtain.tscn` | 场景 | L0 氛围层实例：GPUParticles2D（ParticleProcessMaterial：emission rect 720 宽、gravity +Y、initial_velocity/scale 可调）+ rain_curtain.gd |
| `mini-pong/assets/rain_drop.png` | 纹理 | 3×14 竖条半透明白色雨滴纹理（Godot 自动生成 .import；headless 安全） |
| `mini-pong/tests/test_rain.gd` | 测试 | 公式/clamp/平滑/契约默认值/资源完整性断言 |

### 3.2 直接改动文件

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/scenes/Main.tscn` | 场景 | 新增 L0 `AtmosphereLayer`（CanvasLayer，layer=0 或低于世界层）→ 实例化 `rain_curtain.tscn`；不改动任何现有节点 |
| `mini-pong/gdscripts/constants.gd` | 常量 | 新增 `RAIN_*` 组：`RAIN_BASE=0.3`、`RAIN_MIN=0.1`、`RAIN_MAX=1.0`、`RAIN_SMOOTH_TAU=0.15`、`RAIN_SPEED_FACTOR_MAX=0.3`、`RAIN_TENSION_THRESHOLD=2`、`RAIN_TENSION_BONUS=0.2`、`RAIN_WAVE_STEP=0.1`、`RAIN_PULSE_PIERCE=0.4`、`RAIN_BREATHING_DROP=0.15` |
| `mini-pong/tests/run_tests.gd` | 测试 | 注册 `test_rain.gd` |

### 3.3 间接影响（需回归验证）

| 文件 | 影响 | 处理 |
|------|------|------|
| `mini-pong/gdscripts/ball.gd` | 只读 `speed`（公式输入） | 零改动（只读公开属性） |
| `mini-pong/gdscripts/scoring_manager.gd` / `game_manager.gd` | 只读比分算紧张因子 | 零改动（连接 `score_changed` 信号或读属性） |
| `mini-pong/gdscripts/ball_trail.gd` | 同为粒子控制器 | 零改动（雨幕独立，不共用节点） |
| `mini-pong/e2e_shots.json` | 02_midgame 截图将包含雨幕 | 断言需实测：雨幕为半透明蓝白粒子，色数/主题色断言大概率仍过；若 `非黑` 或 `帧间差异` 断言受影响，调整 shot 参数（如 settle_frames）而非删雨幕 |
| `docs/GAME_DESIGN/` | 无 720×1280/雨幕硬编码（已 grep 验证） | 实现 PR merge 后由 review agent 按 GDD 维护规则增量更新 |

### 3.4 数据流影响

```
公式输入（只读，不修改任何现有信号链）:
    constants.gd RAIN_* 参数 ──► rain_curtain.gd
    ball.speed（330→627）      │   ├─ 球速因子 = (speed − 330)/(627−330) × 0.3
    GameManager 比分差 ≤2      │   ├─ 紧张因子 = +0.2（差 ≤ 2）
    未来: #386 set_wave_factor │   ├─ 波次因子 = +0.1/波（默认 0）
    未来: #384/#385 trigger_event_pulse(穿墙 +0.4 回落 / 失败 1.0)（默认 0）
    未来: #388 set_breathing   │   └─ 喘息 = −0.15（默认 0）
                               ▼
        target_rain = clamp(base + 球速 + 波次 + 紧张 + 脉冲 − 喘息, 0.1, 1.0)
                               ▼
        指数平滑: current += (target − current) × (1 − exp(−delta/τ)), τ=0.15s  → 0.5s 达 95%+
                               ▼
        GPUParticles2D 参数调制（不改 amount）:
            process_material.initial_velocity_min/max  ← 下落速度 × (0.6 + 0.8×rain)
            process_material.scale_min/max             ← 雨滴尺寸 × (0.5 + 0.7×rain)
            process_material.color/color_ramp 的 alpha  ← 透明度（低雨量更淡）
            emitting = rain > 0.05（近乎 0 时停发，防浪费）
```

### 3.5 文档更新

- [ ] `docs/PRD/389-dynamic-rain-curtain.md`（本文件）
- [ ] `docs/GAME_DESIGN/` — 实现 PR merge 后由 review agent 增量更新（L0 氛围层章节）
- [ ] 本 PRD merge 后自动推进 Issue #389 → `workflow/plan`（workflow-chain）

---

## 4. 方案对比

### Approach A：第一方 GPUParticles2D 雨幕 + rain_curtain.gd 控制器（推荐）

自建 `rain_curtain.tscn`（GPUParticles2D + ParticleProcessMaterial），`rain_curtain.gd` 实现公式引擎、指数平滑、参数调制与契约 API。

- **Pros**：完全满足 AC1（GPUParticles2D 雨幕）+ AC4（0.5s 平滑，调制 initial_velocity/scale/alpha 而非 amount，避开粒子重启跳动）；无第三方依赖；公式/参数全部 @export + constants 可测可调；契约 API 让 #384/#386/#388 一行接入；与 PLAN §3.1 4 层架构天然契合（L0 CanvasLayer）
- **Cons**：自研成本（约 150-200 行脚本 + 场景 + 纹理）；浓度曲线需人工 taste 校准（已在所有权中标注 taste-draft）
- **Risk**：Low — 风险集中在粒子参数调制是否平滑（§7 Spike 1 实证）；物理/信号链零改动
- **Effort**：0.5–1 周

### Approach B：复用 godot-weather-2D（93⭐ MIT）Weather 节点

vendor `pirachute/godot-weather-2D`，实例化 Weather 节点并驱动其参数。

- **Pros**：现成雨/雪/风/暗化；MIT 可商用；93⭐ 社区验证
- **Cons**：**README 明确警告运行时改 `amount` 会重启粒子系统、产生跳动** —— 与 AC4「0.5s 平滑过渡」核心需求直接冲突（该库的设计前提是天气切换而非公式驱动连续调制）；全套天气系统（风/雪/暗化/天气碰撞器）远超单雨幕 scope；自带 rain.png 纹理集与节点结构，与 4 层 CanvasLayer 架构不匹配；vendor 后升级/维护成本由本仓库承担
- **Risk**：High（核心 AC 不满足 + 架构错位）
- **Effort**：0.5 周（集成）+ 无底洞式适配

### Approach C：纯 canvas shader 程序化雨丝

`rain_curtain.gdshader`（canvas_item）在 L0 层用噪声/正弦画雨丝，uniform 驱动密度/速度。

- **Pros**：无粒子节点、性能最优；雨丝视觉可控性最强
- **Cons**：**违反 AC1 字面要求**（「场景内存在 GPUParticles2D 雨幕」）；无法用粒子参数表达雨量（发射速率/速度/密度是 AC 明示的调制对象）；与 #289 neon shader 风格分层不清；headless 下 shader 编译报错面更大；测试粒子参数断言不可行
- **Risk**：Med（AC 不合规 + 测试不可行）
- **Effort**：1 周

### 推荐

**Approach A**。理由：(1) 唯一同时满足全部 5 条 AC 的方案（GPUParticles2D 节点、公式驱动、0.5s 平滑、headless 安全、可测）；(2) 调研证据（§1.5）证明 B 的核心机制与 AC4 冲突、C 违反 AC1；(3) 「参数契约 → 执行层」是本项目已验证模式（#217 先例），A 的契约 API 为 #384/#385/#386/#388 提供最小接入面；(4) 第一方实现 ≈150-200 行，成本可控，无 vendor 维护负担。B 的「调制而非改 amount」结论作为 A 的技术依据被采纳。

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body）

- [x] **AC1: 场景内存在 GPUParticles2D 雨幕且默认雨量可调** — `rain_curtain.tscn` 含 GPUParticles2D 节点，实例化于 Main.tscn `AtmosphereLayer`；`rain_curtain.gd` 暴露 `@export var base_intensity: float = 0.3`（检查器可调）；test_rain.gd 断言 Main.tscn 含 AtmosphereLayer/雨幕实例、rain_curtain.tscn 含 GPUParticles2D
- [x] **AC2: 雨量由公式计算并 clamp 在 0.1..1.0** — 公式 = PLAN §3.2 确认版；单元测试钉 clamp：输入 −1 → 0.1、输入 2 → 1.0、正常输入保序；constants.gd `RAIN_MIN/RAIN_MAX` 为唯一边界源
- [x] **AC3: 球速/波次/拆砖事件会提高雨量，喘息期会降低雨量** — 球速因子 + 紧张因子实时接线（ball.speed、比分差）；`set_wave_factor(+0.1/波)`、`trigger_event_pulse(穿墙 +0.4 回落 / 拆砖小脉冲 / 失败 1.0)`、`set_breathing(−0.15)` 为契约 API；测试验证：默认值下雨量 = base+球速+紧张（无波次系统也不报错）；契约 API 调用后雨量单调上升/下降
- [x] **AC4: 雨量变化在 0.5s 内平滑过渡，不产生突兀跳变** — 指数平滑 τ=0.15s（0.5s 达 95%+）；测试：目标阶跃后采样曲线无单帧跳变 >20%；**实现禁止改 `amount`**（仅 initial_velocity/scale/alpha 调制，§1.5 证据）
- [x] **AC5: --headless 下粒子场景不报错** — `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；check_compile 覆盖 rain_curtain.gd；GPUParticles2D headless 不渲染但不报错

### 边界情况（Edge Cases）

1. **clamp 边界**：`base(0.3) − 喘息(0.15)` = 0.15（情境表 升级选择）；若未来喘息 > base 总和，clamp 到 0.1 下限——测试钉 `0.1` 与 `1.0` 双边界
2. **球速因子边界**：发球瞬间 speed = 330（初始）→ 因子 0，雨量 = base（0.3，波次开始情境 ✓）；速度达上限 627 → 因子 +0.3 → 0.6（球速上升情境 ✓）
3. **紧张因子边界**：比分差恰好 = 2（`≤2` 含等号）→ +0.2；差 = 3 → 0——测试钉等号边界
4. **NaN/异常输入**：ball.speed 为 NaN（#287 已有 NaN 防护先例）→ 球速因子按 0 处理；公式输入非法时回退 base，不污染平滑状态
5. **契约输入默认值**：波次/脉冲/喘息未接线时（当前玩法）恒为 0，雨量 = base+球速+紧张 ∈ [0.3, 0.8]——正常可玩，无报错
6. **事件脉冲回落**：穿墙 +0.4 后需平滑回落（~1.5s 指数衰减到 0），不是瞬间消失——测试钉回落曲线单调递减
7. **暂停/菜单状态**：雨幕不依赖 FSM（L0 氛围层独立运行）；MENU 态雨量 = base 细雨即可；PAUSED 态建议 `emitting` 保持（粒子自然衰减）或冻结均可——实现取「保持运行」，E2E 01_title 截图含细雨
8. **全屏覆盖**：emission rect 宽 720（贴竖屏宽度），雨滴从 rect 顶生成、重力 +Y 下落、超出屏幕底部自然消失；不得有雨滴"出生在屏幕内"的可见 pop-in（preprocess 预热）

### 失败路径（Failure Paths）

1. **粒子参数调制引发跳动**（改 amount 或调制过猛）→ 违反 AC4；兜底：§7 Spike 1 先实证调制矩阵，测试断言单帧变化 ≤20%
2. **Main.tscn 挂载遗漏/路径错误** → 雨幕不显示但游戏不报错（静默失败）；兜底：test_main_scene.gd 增加「AtmosphereLayer 存在」断言 + E2E 02_midgame 截图肉眼可见雨幕
3. **headless 下纹理/材质加载报错**（rain_drop.png .import 缺失）→ CI 编译红；兜底：test_rain.gd 断言资源文件存在 + check_compile 覆盖；纹理用 Godot 标准导入流程，无第三方依赖
4. **契约 API 被未来 Issue 误用**（如 #388 直接改 amount）→ 跳动回归；兜底：rain_curtain.gd 提供 `set_intensity()` 为唯一写入口，文档（§8）明确未来 Issue 只准走契约 API

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #383 轴交换 + 竖屏 720×1280 | ✅ CLOSED（main HEAD 77ff437） | Low — 雨幕坐标/重力方向已确定 |
| PLAN-rogue-pong §3.2 雨量公式 | ✅ 已确认（2026-08-13） | Low — 唯一公式权威源 |
| #289 霓虹视觉（glow/bloom/深底） | ✅ 已落地 | Low — 雨幕叠加在既有视觉基调上 |
| #367 手感数值（球速 330→627） | ✅ 已定稿 | Low — 球速因子映射基准 |

### 公式输入契约（本 Issue 预留，未来 Issue 驱动 —— 不阻塞）

| 输入 | 契约接口（rain_curtain.gd） | 来源 Issue | 状态 | 默认 |
|------|---------------------------|-----------|:----:|:----:|
| 波次因子 +0.1/波 | `set_wave_factor(wave_index: int)` | #386 波次循环 | backlog | 0 |
| 事件脉冲：穿墙 +0.4 回落 | `trigger_event_pulse(RAIN_PULSE_PIERCE)` | #384 砖墙 / #385 双得分 | backlog | 0 |
| 事件脉冲：拆砖小脉冲 | `trigger_event_pulse(small)`（数值 taste-draft） | #384 砖墙 | backlog | 0 |
| 事件脉冲：波失败 → 1.0 | `trigger_event_pulse(1.0)`（或 `set_forced_intensity(1.0)`） | #386 波次循环 | backlog | 0 |
| 喘息窗口 −0.15 | `set_breathing(true/false)` | #388 3选1升级UI | backlog | false |

### 阻塞（Blocks）

| 后续工作 | 优先级 | 说明 |
|---------|:---:|------|
| #393 主场景组装（Integration） | P0 | 雨幕作为 L0 组件被组装进最终主场景（本 PRD 已先行挂载 Main.tscn，组装时核对） |
| #392 霓虹 UI 升级 | P1 | 视觉一致性参照（雨幕为 L0，UI 为 L3，互不遮挡） |

### 依赖链

```
PLAN-rogue-pong.md §3.2（2026-08-13 确认公式）
        │
        ▼
Issue #383 轴交换+竖屏（✅ CLOSED）
        │
        ▼
Issue #389 动态雨幕（本 PRD — L0 执行层）
        │
        ├──► 驱动输入（契约 API，非阻塞）: #384 砖墙 / #385 双得分 / #386 波次 / #388 升级UI
        └──► 被组装: #393 主场景组装
```

---

## 7. Spike / 实验

depth/standard 下 Section 7 非必填，但存在一项真实技术不确定性（粒子参数调制是否平滑、headless 行为），故包含 2 个轻量实验，成本各 ≤0.5 天：

### 实验 1：粒子参数调制矩阵 —— 哪组参数在 0.5s 内无跳变

- **问题**：AC4 要求 0.5s 平滑过渡。godot-weather-2D 证据表明改 `amount` 会重启粒子系统产生跳动（§1.5）；需实证 `initial_velocity_min/max`、`scale_min/max`、`color/color_ramp` alpha、`gravity` 哪些组合在运行时调制视觉平滑
- **方法**：临时场景跑 GPUParticles2D，运行时按 0.15s τ 指数平滑调制各参数组合，录制帧序列肉眼 + 截图对比（复用 E2E analyze_bmp 帧间差异断言）
- **预期结果**：`initial_velocity + scale + alpha` 组合平滑（雨滴加速/变大/变亮 = 雨量增强的自然视觉语义）；`amount` 调制出现可见跳变（复现 README 警告）→ 确认 Approach A 的调制集
- **对方案影响**：若某参数组合跳变，从调制集剔除（保守集：仅 alpha + scale）；不改 amount 的结论强化

### 实验 2：headless 下雨幕场景加载与测试可行性

- **问题**：AC5 要求 `--headless` 不报错；test_rain.gd 需要能在 headless 下实例化 rain_curtain.tscn 并驱动公式（不依赖真实渲染）
- **方法**：headless 下 `load("res://scenes/rain_curtain.tscn").instantiate()` + 调用 `set_intensity(0.9)` + `_process` 步进若干帧，断言 target/current 收敛；检查 GPUParticles2D 在 headless 下是否静默无错误
- **预期结果**：场景可实例化、公式可测（粒子不渲染但逻辑全通）；若 headless 下粒子节点报渲染警告，测试改用「加载 + 公式层」分离（公式引擎独立于粒子节点可单测）
- **对方案影响**：若公式引擎需与粒子节点解耦才能 headless 单测，则 rain_curtain.gd 拆 `RainIntensityEngine`（纯逻辑，可单测）+ 粒子调制薄层（场景内）——结构微调，Approach A 不变

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #389 当前 `workflow/research`，本 PRD merge 后 workflow-chain 自动推进 → `workflow/plan`
- 基线：`main` HEAD = `77ff437`（#383 竖屏已 merge）；竖屏 720×1280 代码完整可跑（headless 测试绿）
- 上游方案已确认：`docs/PLAN-rogue-pong.md` §3.2（公式 + 情境表，本 PRD 已细化为参数级映射）
- Obsidian 知识检索完成（`/Volumes/Obsidian/Knowledge Ocean/wiki/`）：空洞骑士「泪城永恒雨水创造忧郁空间」→ 雨作为情绪/负空间叙事；体验引擎「情绪维持/世界叙事」→ 氛围层是低技能情绪触发器；90 年代地摊文艺 → 反例约束（雨幕克制、不堆砌特效）——已注入 §2/§5 的设计语言

### 关键决策（plan agent 必须继承）

1. **Approach A 第一方实现**：`rain_curtain.gd` + `rain_curtain.tscn`（GPUParticles2D），不引入 godot-weather-2D 等第三方（§1.5 调研证据 + §4）
2. **公式** = PLAN §3.2 确认版，常量全部进 `constants.gd` `RAIN_*` 组（§3.2 清单）；clamp(0.1, 1.0)
3. **接线输入**：base(0.3) + 球速因子（`(speed−330)/297×0.3`，0→0.3）+ 紧张因子（比分差 ≤2 → +0.2）；**只读** ball.speed 与 GameManager 比分，不改信号链/物理
4. **契约 API**（未来 Issue 唯一写入口）：`set_wave_factor(int)` / `trigger_event_pulse(float)` / `set_breathing(bool)` / `set_intensity(float)`（调试口）；当前默认值下雨量 = base+球速+紧张 ∈ [0.3, 0.8]
5. **平滑**：指数平滑 τ=0.15s（0.5s 达 95%+）；**禁止改 `amount`**（粒子重启跳动证据 §1.5）；调制集 = initial_velocity_min/max + scale_min/max + color/color_ramp alpha（Spike 1 实证后定稿）
6. **分层**：L0 `AtmosphereLayer`（CanvasLayer）承载雨幕，低于 L1 世界层；emission rect 宽 720、gravity +Y、preprocess 预热防 pop-in
7. **纹理**：`assets/rain_drop.png`（3×14 半透明白竖条），标准导入流程，headless 安全
8. **浓度曲线 = taste-draft**：默认线性映射（§3.4 公式）作为初版，曲线形状由用户 human-review 定稿；雨滴颜色蓝白半透明，克制优先（#289 基调）
9. **测试**：`test_rain.gd` 覆盖 clamp 边界/公式单调性/平滑无跳变/契约默认值/资源完整性；注册进 `run_tests.gd`；若 headless 无法实例化粒子节点，公式引擎拆纯逻辑层单测（Spike 2）
10. **E2E**：e2e_shots.json loop 原型自动命中 rain_curtain.gd；02_midgame 截图含雨幕，4 重断言实测通过（必要时调 settle_frames，不删雨幕）

### 实现顺序建议（plan agent 参考）

1. `constants.gd`（RAIN_* 常量）→ 2. `rain_drop.png`（纹理 + .import）→ 3. `rain_curtain.tscn`（GPUParticles2D + ParticleProcessMaterial）→ 4. `rain_curtain.gd`（公式引擎 + 平滑 + 调制 + 契约 API）→ 5. `Main.tscn`（AtmosphereLayer 挂载）→ 6. `test_rain.gd` + `run_tests.gd` 注册 → 7. Spike 1 实证调制矩阵定稿调制集 → 8. 本地 headless 全绿 + E2E 实弹截图（02_midgame 含雨幕）

### 主要风险

- 粒子调制不平滑 → AC4 失败（Spike 1 前置实证兜底）
- Main.tscn 挂载静默失败 → 雨幕不显示（test_main_scene 断言 + E2E 截图兜底）
- 未来 Issue 误改 amount → 跳动回归（契约 API 唯一写入口 + §8 文档约束）

### 交接清单

- [ ] 本 PRD 文件 `docs/PRD/389-dynamic-rain-curtain.md`
- [ ] 上游方案 `docs/PLAN-rogue-pong.md` §3.2（公式权威源）
- [ ] 调研证据：godot-weather-2D README「改 amount 会重启粒子系统」（§1.5）
- [ ] 实测基线：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 当前全绿（实现前可复跑对照）

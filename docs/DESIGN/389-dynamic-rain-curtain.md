# DESIGN: [Feature] 动态雨幕 — Dynamic Rain Curtain (L0 氛围层)

> **Parent Issue:** #389
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — 第一方 GPUParticles2D 雨幕 + `rain_curtain.gd` 控制器（确认 PRD §4 推荐；不引入 godot-weather-2D 等第三方，不采用纯 shader 方案 C）
> **Reference PRD:** docs/PRD/389-dynamic-rain-curtain.md（research PR #410，已合并）
> **上游方案:** docs/PLAN-rogue-pong.md §3.1/§3.2（4 层 CanvasLayer 架构 + 雨量公式，已确认）
> **所有权:** `content_ownership: mechanical`（雨量映射规则 = 机械可测；浓度曲线/雨滴视觉 = taste-draft，@export-tunable 交由 human-review 定稿，不阻塞本 Issue）
> **深度:** depth/standard —— 仅产出 DESIGN 文档；不产出 TASKS 文档；测试仅描述不写代码

---

## 1. 概述

Mini Pong 已具备 #289 霓虹赛博视觉与 #383 竖屏坐标系（720×1280），但 PLAN-rogue-pong §3.1 的 **L0 氛围层「雨幕粒子」完全缺失**。本设计将雨幕作为情绪仪表盘落地：`rain_curtain.tscn`（GPUParticles2D 雨幕）实例化于 Main.tscn 的 L0 CanvasLayer，`rain_curtain.gd` 消费 PLAN §3.2 已确认的雨量公式并实时调制粒子参数。

**Plan 阶段边界**：本阶段只产出本文档，不碰任何 `.gd` / `.tscn` / `.png` 文件 —— 下列全部内容为 implement agent 的契约。

### 设计哲学

1. **公式即契约**：雨量公式 = PLAN §3.2 确认版（`rain = clamp(base + 球速因子 + 波次因子 + 紧张因子 + 事件脉冲 − 喘息, 0.1, 1.0)`），常量全部进 `constants.gd` `RAIN_*` 组，clamp 边界由测试钉死。
2. **调制而非改 amount**：调研证据（PRD §1.5，godot-weather-2D README）表明运行时改 `amount` 会重启粒子系统产生跳动，与 AC4「0.5s 平滑过渡」冲突。雨量变化通过调制 `initial_velocity_min/max`、`scale_min/max`、`color/color_ramp` alpha 表达 —— **实现禁止改 `amount`**。
3. **零侵入**：`game_state_machine.gd` / `scoring_manager.gd` / `ball.gd` 物理逻辑零改动（雨幕只读 `ball.speed` 与比分，不改信号链）。
4. **契约 API 为未来唯一写入口**：波次/事件脉冲/喘息为契约接口（`set_wave_factor()` / `trigger_event_pulse()` / `set_breathing()` / `set_intensity()` 调试口），#384/#385/#386/#388 一行接入，当前默认值下不报错。
5. **测试即验收**：新增 `test_rain.gd` 走 run_tests.gd，沿用 test_neon.gd 的资源完整性断言风格；E2E 02_midgame 截图自动含雨幕，4 重断言需实测通过。

---

## 2. 现状核实（plan agent 已对照源码确认）

| 文件 | 现状（已核实） |
|------|---------------|
| `mini-pong/scenes/Main.tscn` | 12 个节点：WorldEnvironment / LeftWall / RightWall / Ball / PlayerPaddle / AIPaddle / ScoringManager / GameStateMachine / ScoreZoneTop(360,0) / ScoreZoneBottom(360,1280) / ScoreFlash / StartMenu(layer=1) / GameHUD(layer=1) / GameOverScreen(layer=1) / PauseOverlay(layer=10) — **无任何 L0 氛围层节点** |
| `mini-pong/gdscripts/ball.gd` | L33-34：`var velocity` / `var speed`（公开属性，公式输入可直接读取）；L116-118 NaN 防护先例 |
| `mini-pong/gdscripts/game_manager.gd` | L15：`signal score_changed(player_score, ai_score)`（autoload GameManager，紧张因子数据源） |
| `mini-pong/gdscripts/constants.gd` | 含 `BALL_INITIAL_SPEED=330.0`、`BALL_MAX_SPEED_MULTIPLIER=1.9`（→上限 627）、`SCREEN_WIDTH=720/SCREEN_HEIGHT=1280`；**无 RAIN_* 组** |
| `mini-pong/gdscripts/ball_trail.gd` | 既有 GPUParticles2D 控制器先例（#289）：`_process` 读父节点 velocity，调 `amount_ratio` —— 雨幕调制风格参照 |
| `mini-pong/tests/run_tests.gd` | `_run_tests()` 注册 14 个测试文件，`_run(\"res://tests/test_neon.gd\", ...)` 模式；**无 test_rain.gd** |
| `mini-pong/e2e_shots.json` | loop 原型 `match: ["gdscripts/.*\\.gd", ...]` → rain_curtain.gd 必命中；02_midgame PLAYING 截图将自动含雨幕 |
| `mini-pong/assets/` | neon_glow_material.tres / gradient_neon.tres / particle_material.tres（#289 产物）；**无雨滴纹理** |

---

## 3. 核心设计（implement 契约）

### 3.1 分层挂载（PLAN §3.1 对齐）

Main.tscn 新增 L0 氛围层节点树（不改动任何现有节点）：

```
Game (Node2D)
└── AtmosphereLayer (CanvasLayer, layer = 0)      # L0 氛围层，低于 L1 世界层
    └── RainCurtain (instance: rain_curtain.tscn) # GPUParticles2D 雨幕 + rain_curtain.gd
```

- `layer = 0` 为 CanvasLayer 默认最低层，低于 StartMenu/GameHUD/GameOverScreen（layer=1）与 PauseOverlay（layer=10），雨幕不遮挡砖墙/球/挡板/UI。
- 雨幕不依赖 FSM：L0 氛围层独立运行，MENU 态细雨（0.3）、PLAYING 态按公式驱动、PAUSED 态保持 emitting（粒子自然衰减），E2E 01_title 截图含细雨。

### 3.2 雨量公式引擎（rain_curtain.gd）

**公式**（PLAN §3.2 确认版，PRD §3.4 参数级细化）：

```
target_rain = clamp(
    RAIN_BASE(0.3)
  + 球速因子:  (speed − BALL_INITIAL_SPEED) / (627 − 330) × RAIN_SPEED_FACTOR_MAX(0.3)   # 0 → 0.3
  + 波次因子:  wave_factor × RAIN_WAVE_STEP(0.1)                                           # 契约，默认 0
  + 紧张因子:  |player_score − ai_score| ≤ RAIN_TENSION_THRESHOLD(2) ? RAIN_TENSION_BONUS(0.2) : 0
  + 事件脉冲:  _pulse_current（衰减中，默认 0）                                              # 契约
  − 喘息窗口:  _breathing ? RAIN_BREATHING_DROP(0.15) : 0                                   # 契约，默认 false
, RAIN_MIN(0.1), RAIN_MAX(1.0))
```

**球速因子边界**：发球瞬间 speed=330 → 因子 0，雨量=base（0.3，波次开始情境 ✓）；速度达上限 330×1.9≈627 → 因子 +0.3 → 0.6（球速上升情境 ✓）。speed 为 NaN（#287 防护先例）→ 按 0 处理，回退 base，不污染平滑状态。

**紧张因子边界**：比分差恰好 = 2（`≤2` 含等号）→ +0.2；差 = 3 → 0。数据源为 autoload `GameManager.player_score / ai_score`（只读属性，不连接/不修改 score_changed 信号链）。

**事件脉冲回落**：`trigger_event_pulse(amount)` 将 `_pulse_current` 设为 amount，随后以 τ 指数衰减回 0（~1.5s 内单调递减，测试钉回落曲线单调性），不是瞬间消失。穿墙 +0.4（RAIN_PULSE_PIERCE）、波失败 1.0 由未来 Issue 传入。

### 3.3 指数平滑（AC4）

```
current += (target_rain − current) × (1 − exp(−delta / RAIN_SMOOTH_TAU))   # τ = 0.15s
```

- 0.5s 内到达目标的 95%+（1−exp(−0.5/0.15) ≈ 96.4%）。
- **禁止直接改 `amount`**（粒子重启跳动证据，PRD §1.5）；`emitting = rain > 0.05`（近乎 0 时停发防浪费）。
- 测试：目标阶跃后采样曲线无单帧跳变 >20%；0.5s 后 |current − target| < 0.05×range。

### 3.4 粒子参数调制（AC4 表达雨量）

调制集（PRD §7 Spike 1 实证后定稿；保守集 = alpha + scale，若某参数组合跳变则剔除）：

| 参数 | 调制公式（线性默认，taste-draft 可调） |
|------|--------------------------------------|
| `process_material.initial_velocity_min/max` | 下落速度 × (0.6 + 0.8×rain) |
| `process_material.scale_min/max` | 雨滴尺寸 × (0.5 + 0.7×rain) |
| `process_material.color` / `color_ramp` alpha | 透明度（低雨量更淡），蓝白半透明克制优先（#289 基调） |
| `emitting` | `rain > 0.05` |

**场景参数**（rain_curtain.tscn）：emission rect 宽 720（贴竖屏宽）、gravity 沿 +Y（垂直下落与攻击同轴）、preprocess 预热防 pop-in（雨滴不得"出生在屏幕内"）、超出屏幕底部自然消失。纹理 `assets/rain_drop.png`（3×14 半透明白竖条，标准导入流程，headless 安全）。

### 3.5 契约 API（未来 Issue 唯一写入口）

| API | 语义 | 来源 Issue | 默认 |
|-----|------|-----------|:----:|
| `set_wave_factor(wave_index: int)` | 波次因子 = wave_index × +0.1 | #386 波次循环 | 0 |
| `trigger_event_pulse(amount: float)` | 事件脉冲（穿墙 +0.4 回落 / 波失败 1.0 / 拆砖小脉冲） | #384/#385/#386 | 0 |
| `set_breathing(active: bool)` | 喘息窗口 −0.15 | #388 升级 UI | false |
| `set_intensity(value: float)` | 调试口：直接设目标雨量（不走公式） | — | — |

当前玩法（无波次/砖墙/升级）雨量 = base + 球速 + 紧张 ∈ [0.3, 0.8]，正常可玩无报错。文档（§9 不做的事 + 本文件 §8）明确未来 Issue 只准走契约 API，不得直接改 amount。

### 3.6 @export 可调参数（taste-draft 定稿窗口）

`rain_curtain.gd` 暴露 `@export`：`base_intensity`（默认 0.3，检查器可调，AC1）、`smooth_tau`（默认 0.15）、浓度曲线形态参数（默认线性映射）。浓度曲线与雨滴视觉细节为 taste-draft 候补，由用户 human-review 定稿，不阻塞本 Issue。

---

## 4. 组件修改清单（implement 契约）

### 4.1 新文件

| 文件 | 职责 |
|------|------|
| `mini-pong/gdscripts/rain_curtain.gd` | 公式引擎 + 指数平滑 + 粒子参数调制 + 契约 API + @export 参数（约 150-200 行） |
| `mini-pong/scenes/rain_curtain.tscn` | L0 雨幕实例：GPUParticles2D + ParticleProcessMaterial（emission rect 720、gravity +Y、preprocess 预热）+ rain_curtain.gd |
| `mini-pong/assets/rain_drop.png` | 3×14 半透明白竖条雨滴纹理（Godot 自动生成 .import；headless 安全） |
| `mini-pong/tests/test_rain.gd` | 公式/clamp/平滑/契约默认值/资源完整性断言（test_neon.gd 风格） |

### 4.2 直接改动文件

| 文件 | 改动 |
|------|------|
| `mini-pong/scenes/Main.tscn` | 新增 `AtmosphereLayer`（CanvasLayer, layer=0）→ 实例化 `rain_curtain.tscn`；**不改动任何现有节点** |
| `mini-pong/gdscripts/constants.gd` | 新增 `RAIN_*` 组：`RAIN_BASE=0.3`、`RAIN_MIN=0.1`、`RAIN_MAX=1.0`、`RAIN_SMOOTH_TAU=0.15`、`RAIN_SPEED_FACTOR_MAX=0.3`、`RAIN_TENSION_THRESHOLD=2`、`RAIN_TENSION_BONUS=0.2`、`RAIN_WAVE_STEP=0.1`、`RAIN_PULSE_PIERCE=0.4`、`RAIN_BREATHING_DROP=0.15` |
| `mini-pong/tests/run_tests.gd` | 注册 `test_rain.gd` |

### 4.3 不动文件（明确排除）

`game_state_machine.gd`、`scoring_manager.gd`、`ball.gd`（物理零改动，雨幕只读公开属性）、`ball_trail.gd`、`world_environment.tscn`、`e2e_shots.json`（4 重断言实测，必要时调 shot 参数而非删雨幕）、`docs/GAME_DESIGN/`（GDD 由 review agent 在实现 PR merge 后按 INDEX 规则增量更新，本 PR 不动）。

---

## 5. 测试契约（仅描述，不写代码）

> 新增 `test_rain.gd`（RefCounted + run()，test_neon.gd 风格）；全部为描述性规格，implement 依此实现用例。

| 测试组 | 描述 |
|--------|------|
| clamp 边界 | 公式输入 −1 → 0.1；输入 2 → 1.0；正常输入保序；`RAIN_MIN/RAIN_MAX` 为唯一边界源（钉死双边界） |
| 公式单调性 | 球速 330→627 雨量单调不减；紧张因子等号边界（差=2 → +0.2，差=3 → 0） |
| 平滑无跳变 | 目标阶跃后采样曲线单帧变化 ≤20%；0.5s 后收敛到目标 95%+（τ=0.15 指数平滑） |
| 事件脉冲回落 | `trigger_event_pulse` 后雨量上升，随后 ~1.5s 单调递减回基线（非瞬间消失） |
| 契约默认值 | 未接线时波次/脉冲/喘息恒为 0，雨量 = base+球速+紧张 ∈ [0.3, 0.8]；契约 API 调用后雨量单调上升/下降 |
| NaN 防护 | ball.speed 为 NaN → 球速因子按 0，回退 base，不污染平滑状态 |
| 资源完整性 | rain_curtain.tscn 含 GPUParticles2D；rain_drop.png 存在；Main.tscn 含 AtmosphereLayer + 雨幕实例；constants.gd 含 RAIN_* 组 |
| headless 安全 | `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；若 headless 无法实例化粒子节点，公式引擎拆纯逻辑层单测（PRD §7 Spike 2） |

**E2E**：e2e_shots.json loop 原型自动命中 rain_curtain.gd → 02_midgame 截图含雨幕，4 重断言（非黑/色数/主题色/帧间差异）实测通过；若 `非黑` 或 `帧间差异` 受影响，调整 shot 参数（如 settle_frames）而非删雨幕。

---

## 6. 边界条件与失败路径（implement 必须遵守）

1. **改 amount = 违规**：AC4 核心约束，任何调制不得直接写 `amount`（粒子重启跳动）；雨量表达走 §3.4 调制集。
2. **clamp 下限**：base(0.3) − 喘息(0.15) = 0.15（升级选择情境 ✓）；未来喘息 > base 总和 → clamp 到 0.1，测试钉双边界。
3. **Main.tscn 挂载静默失败**：路径错误 → 雨幕不显示但游戏不报错；test_main_scene 增加「AtmosphereLayer 存在」断言 + E2E 截图兜底。
4. **headless 资源加载报错**：rain_drop.png .import 缺失 → CI 编译红；test_rain 断言资源存在 + check_compile 覆盖。
5. **契约 API 误用**：#388 等未来 Issue 直接改 amount → 跳动回归；`set_intensity()` 为唯一写入口 + 本文档 §8 约束。
6. **PAUSED 态**：雨幕不依赖 FSM；PAUSED 态保持 emitting（粒子自然衰减）或冻结均可 —— 实现取「保持运行」，E2E 01_title 截图含细雨。

---

## 7. 验收标准映射（Issue #389 AC）

| AC | 验收标准 | 设计覆盖 |
|----|---------|---------|
| AC1 | 场景内存在 GPUParticles2D 雨幕且默认雨量可调 | §3.1 挂载 + rain_curtain.tscn 含 GPUParticles2D + `@export base_intensity=0.3` + test_rain 资源断言 |
| AC2 | 雨量由公式计算并 clamp 在 0.1..1.0 | §3.2 公式 + constants RAIN_MIN/MAX 唯一边界源 + clamp 双边界测试 |
| AC3 | 球速/波次/拆砖事件提高雨量、喘息期降低 | §3.2 球速+紧张实时接线 + §3.5 契约 API（默认 0 不报错）+ 单调性测试 |
| AC4 | 0.5s 内平滑过渡无跳变 | §3.3 指数平滑 τ=0.15 + §3.4 调制集（禁改 amount）+ 平滑测试 |
| AC5 | --headless 下粒子场景不报错 | §5 headless 测试 + check_compile 覆盖 rain_curtain.gd |

---

## 8. 验证步骤（implement 执行顺序）

1. `constants.gd`（RAIN_* 组）→ 2. `rain_drop.png`（纹理 + .import）→ 3. `rain_curtain.tscn`（GPUParticles2D + ParticleProcessMaterial）→ 4. `rain_curtain.gd`（公式引擎 + 平滑 + 调制 + 契约 API）→ 5. `Main.tscn`（AtmosphereLayer 挂载）→ 6. `test_rain.gd` + `run_tests.gd` 注册 → 7. PRD §7 Spike 1 实证调制矩阵定稿调制集 → 8. 本地验证：

- `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿
- `godot --path mini-pong/ --headless --quit`（project.godot 有效）
- E2E 实弹截图：02_midgame 含雨幕，4 重断言通过（必要时调 settle_frames）
- `game_state_machine.gd` / `scoring_manager.gd` / `ball.gd` git diff 为空（或仅注释）

---

## 9. 不做的事（明确排除）

- ❌ 不引入 godot-weather-2D 等第三方资产（PRD §1.5 调研：其改 amount 机制与 AC4 冲突；风/雪/暗化全套超出单雨幕 scope）
- ❌ 不采用纯 canvas shader 程序化雨丝（Approach C，违反 AC1「GPUParticles2D 雨幕」字面要求，测试不可行）
- ❌ 不改 `amount`（粒子重启跳动，AC4 违规）
- ❌ 不改 `game_state_machine.gd` / `scoring_manager.gd` / `ball.gd` 物理与信号链（雨幕只读公开属性）
- ❌ 不改手感数值（#367 定稿）与 e2e_shots.json（除非断言实测不过才调 shot 参数）
- ❌ 不写 runnable 测试文件于本 PR（测试实现归 implement PR；本文档仅描述规格）
- ❌ 不更新 docs/GAME_DESIGN/（GDD 由 review agent 在实现 PR merge 后增量更新）

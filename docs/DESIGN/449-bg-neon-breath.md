# DESIGN: [Feature] 背景霓虹呼吸 — Background Neon Breath (L0 氛围层)

> **Parent Issue:** #449
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — ColorRect + 脚本正弦 alpha（确认 PRD §4.1/§4.2 推荐组合：`compute_alpha` 纯函数 + AtmosphereLayer 首子节点挂载；不采用共享 Environment 突变、不采用自写 shader）
> **Reference PRD:** docs/PRD/449-bg-neon-breath.md（research PR #452，已合并）
> **上游方案:** docs/PLAN-rogue-pong.md §3.1（L0 氛围层 = 雨幕粒子 + 底部城市光晕 + 暗角 ≤10%，用户已拍板）+ docs/GAME_DESIGN/22-RAIN-CURTAIN.md（AtmosphereLayer layer=0 分层纪律）
> **所有权:** `content_ownership: mechanical`（正弦机制/常量定义/节点挂载 = 机械可测；脉冲峰值不透明度、霓虹色调值 = taste-draft，全部收敛于 `BG_PULSE_*` 常量交由 human-review 定稿，调参零代码改动）
> **深度:** depth/standard —— 仅产出 DESIGN 文档；不产出 TASKS 文档（文件域 3 个、无迁移/弃用、单一子系统，未达 TASKS 阈值）；测试仅描述不写代码
> **并行上下文:** worktree 并行测试 T2 —— T1 #448（constants.gd HUD 区，plan PR #454 已合并）/ T3 #450（AUDIO 区，research 中）与本 Issue（BG 区）同改 `constants.gd` 不同区，验证「提交前 merge main」自动合并。本 DESIGN 只改 docs，无代码冲突面

---

## 1. 概述

Mini Pong 的 L0 氛围层（#389 雨幕已落地）目前「只有雨在呼吸，背景是死的」：`world_environment.tscn` 背景底色 `#0a0a12` 恒定不变，而 PLAN §3.1 已确认的 L0 规格（雨幕 + 底部城市光晕 + 暗角）中「背景光晕」尚未执行。本设计以**最小增量**补全：新增 `bg_pulse.gd`（extends ColorRect）全屏铺底，`_process` 按正弦公式写 `color.a`，由既有 WorldEnvironment glow(0.6)/bloom(0.8) 放大为「呼吸的光晕」。

**Plan 阶段边界**：本阶段只产出本文档，不碰任何 `.gd` / `.tscn` / `.json` 文件 —— 下列全部内容为 implement agent 的契约。

### 设计哲学

1. **公式即契约**：`compute_alpha(t) = clamp(base + amplitude·sin(TAU·t/period), 0, 1)` 为**静态纯函数**（headless 可求值、可断言），周期/基线/振幅/色调全部来自 `constants.gd` 新增 `BG_PULSE_*` 区；`period ≤ 0` 时返回 `base`（防除零 NaN，沿用 #287/#389 的 NaN 防护先例）。
2. **克制原则**：alpha ∈ [0.01, 0.15]（基线 0.08 ± 振幅 0.07），峰值 ≤15% 与 PLAN 暗角 ≤10% 同量级；恒定正弦、周期 4s 缓慢，不随游戏事件突变（事件性起伏已由雨幕 #389 承担，背景呼吸只做基底）。taste 数值（峰值/色调）human-review 定稿。
3. **零侵入 / additive**：Main.tscn 既有节点零改动，只新增 1 个 ColorRect 子节点（`test_main_scene.gd` TC1-2~TC1-15 均为 has_node 存在性断言，无「节点数不变」断言 → additive-safe，已核实）；constants.gd 只**追加**新区，既有区逐字节不动。
4. **分层纪律**：BgPulse 挂 `AtmosphereLayer`（layer=0，最低 CanvasLayer）首子节点（RainCurtain **之前** = 同层最底），结构性保证低于世界 L1/UI L3；不新建 CanvasLayer。
5. **FSM-independent**（同雨幕纪律）：MENU/PLAYING/PAUSED 全程呼吸，无状态切换逻辑、无信号依赖、无外部写入口。
6. **文件域红线（AC5）**：实现 PR 只允许 3 文件 —— `gdscripts/bg_pulse.gd`（新）+ `scenes/Main.tscn` + `gdscripts/constants.gd`（仅 BG 区）；**不新增测试文件**；用 `worktree-commit.sh` 白名单 add，绝不 `git add .`。

---

## 2. 现状核实（plan agent 已对照源码确认）

| 文件 | 现状（已核实，2026-08-13） |
|------|---------------------------|
| `mini-pong/scenes/Main.tscn` | 179 行；`AtmosphereLayer`（CanvasLayer, `layer = 0`）下**仅** `RainCurtain` 一个子节点（instance `11_rain_curtain`）；ext_resource id 最高 `16_game_over_scene`；分层：L0 AtmosphereLayer / L1 世界 / StartMenu·GameHUD·GameOverScreen layer=1 / PauseOverlay layer=10 / UpgradePickUI layer=2 / WaveTransition layer=3 |
| `mini-pong/gdscripts/constants.gd` | 189 行，`class_name GameConstants`；分区：Screen/Version/Ball/Paddle/AI/Scoring/Dual Scoring(#385)/Wave Cycle(#386)/Colors/`# ── Rain` 区（含 `BG_COLOR: Color(0.039,0.039,0.071,1.0)` L139）/Neon HUD(#392)/Upgrade Pool(#387)/Failure Screen(#391)/Upgrade Pick UI(#388)；**无 BG_PULSE 区**；文件以 `UPGRADE_RARITY_NAMES` 结尾（L189） |
| `mini-pong/gdscripts/rain_curtain.gd` | 先例：`set_breathing()` 契约 API、`compute_target_rain()` 纯函数公式引擎、NaN 防护（`is_nan(speed)`）、氛围层 FSM-independent —— bg_pulse.gd 的设计母版 |
| `mini-pong/scenes/world_environment.tscn` | `background_mode = 0`（清屏色）+ `glow_enabled=true` + `glow_intensity=0.6` + `glow_bloom=0.8` → 2D ColorRect 的 alpha 起伏会被 glow/bloom 放大为「光晕呼吸」。**本 Issue 不修改此文件**（`test_neon.gd` TC2/TC3 文本断言其内容） |
| `mini-pong/tests/test_main_scene.gd` | L55-70：TC1-2~TC1-15 全部为 `has_node("既有节点名")` 存在性断言 → 新增 `BgPulse` 节点 additive-safe，零改动 |
| `mini-pong/tests/run_tests.gd` | 注册 18 个 `_run(...)` 套件；基线 2214 passed / 0 failed（2026-08-13 复跑，PRD §8）不得回退（AC4） |
| `mini-pong/e2e_shots.json` | loop 组 match `gdscripts/.*\.gd` + `scenes/.*\.tscn` + `project\.godot` → bg_pulse.gd / Main.tscn 改动必然命中；`02_midgame`：state PLAYING、press enter、require `player_score ≥ 1`、settle_frames=5、theme_color `4a90d9` |
| 当前 `origin/main` | HEAD = `11af230`（#454「docs(plan): DESIGN for #448」已合并 → T1 #448 的 HUD 区已进 main）—— PRD §8 记录的基线 `f6785cb` 已前进，对本设计无影响（docs-only） |

### PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计处置 |
|---------|-----------|---------|
| 「ext_resource 需新增」 | Main.tscn 现有 id `1_ball`…`16_game_over_scene` | 新增 `id="17_bg_pulse"`（见 §3.3） |
| 「test_main_scene TC1 系 additive-safe」 | 已核实：14 条 has_node 存在性断言、无数量断言 | ✅ 成立，零改动 |
| 「main HEAD = f6785cb」 | 实际 `11af230`（#454 合并后） | 文档级差异，设计不受影响；本 DESIGN 以当前 main 为基线 |
| 「RainCurtain 是 AtmosphereLayer 唯一子节点」 | 已核实 | BgPulse 声明于 RainCurtain 之前（同层先绘制 = 最底） |
| 「glow/bloom 已开启」 | `world_environment.tscn` 已核实 | ✅ 成立，「光晕」语义由 bloom 免费提供 |

---

## 3. 核心设计（implement 契约）

### 3.1 `bg_pulse.gd`（新文件）

- **文件:** `mini-pong/gdscripts/bg_pulse.gd`（本 Issue 唯一新文件；`.uid` 由 Godot 首次导入自动生成，不入 PR 白名单）
- **基类:** `ColorRect`（2D Control，全屏铺底；headless 下不渲染但脚本照常求值，无错误）
- **节点结构（挂载后整体）:**

```
Game (Node2D)
└── AtmosphereLayer (CanvasLayer, layer = 0)      # L0 氛围层（既有）
    ├── BgPulse (ColorRect, script: bg_pulse.gd)  # 新增 —— 首子节点，最底
    └── RainCurtain (instance: rain_curtain.tscn) # 既有，零改动
```

- **Signals:** 无（氛围层 FSM-independent，不发出/连接任何信号）
- **State Properties:**
  - `var _t: float = 0.0` — 呼吸相位累积（每帧 `_process` 递增；场景加载即从 0 起，`t=0 → alpha=base`，无跳变）
- **Key Methods:**

```gdscript
extends ColorRect
## Background neon breath — L0 atmosphere layer (#449).
## 背景光晕缓慢正弦呼吸：color.a = compute_alpha(t)。色调 BG_PULSE_TINT（霓虹蓝同系），
## WorldEnvironment 既有 glow(0.6)/bloom(0.8) 放大为「光晕」。氛围层 FSM-independent。
## Design: docs/DESIGN/449-bg-neon-breath.md

const CONSTS = preload("res://gdscripts/constants.gd")

var _t: float = 0.0

## 纯函数：alpha = clamp(base + amplitude·sin(TAU·t/period), 0, 1)。
## period <= 0 时返回 base（防除零 NaN，沿用 #287/#389 NaN 防护先例）。
static func compute_alpha(t: float, period: float, base: float, amplitude: float) -> float:
	if period <= 0.0:
		return base
	return clamp(base + amplitude * sin(TAU * t / period), 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	color.a = compute_alpha(_t, CONSTS.BG_PULSE_PERIOD,
		CONSTS.BG_PULSE_BASE_ALPHA, CONSTS.BG_PULSE_AMPLITUDE)
```

- **Integration notes:**
  - 不读 `GameStateMachine`、不监听任何信号 —— 与 FSM 零耦合
  - 不修改 `amount`/粒子/材质 —— 只写自身 `color.a`，单 Control 每帧开销可忽略
  - `color` 的 RGB 由 tscn 初始为 `BG_PULSE_TINT`（§3.3），脚本只驱动 alpha

### 3.2 `constants.gd` — 新增 `BG_PULSE` 区

- **位置:** 文件**末尾**（当前末尾为 `# ── Upgrade Pick UI (#388) ──` 区，L189 `UPGRADE_RARITY_NAMES` 之后）追加；既有区**逐字节不动**（AC3；并行 T1 #448 HUD 区已在 main、T3 #450 AUDIO 区未合 —— 三区互不重叠，提交前 merge main 自动合并）
- **追加内容（精确文本）:**

```gdscript

# ── Background Pulse (#449) ──
# 背景霓虹呼吸 (PLAN-rogue-pong §3.1 L0「背景光晕」执行层; 机制/常量 = mechanical,
# 峰值不透明度与色调 = taste-draft, human-review 定稿, 调参零代码改动)
const BG_PULSE_PERIOD: float = 4.0          # 呼吸周期 ~4s（AC1 默认，可配）
const BG_PULSE_BASE_ALPHA: float = 0.08     # 基线 alpha
const BG_PULSE_AMPLITUDE: float = 0.07      # 振幅 → alpha ∈ [0.01, 0.15]（克制 ≤15%，PLAN 暗角 ≤10% 同量级）
const BG_PULSE_TINT: Color = Color(0.29, 0.56, 0.85, 1.0)  # 霓虹蓝同系（PLAYER_NEON_BLUE #4a90d9）
```

### 3.3 `Main.tscn` — 挂载 `BgPulse` 节点

- **改动性质:** 纯增量 —— 1 条 ext_resource + 1 个节点块；既有 15 个节点/16 条 ext_resource **零改动**（AC2）
- **ext_resource（新增，追加在现有 16 条之后）:**

```
[ext_resource type="Script" path="res://gdscripts/bg_pulse.gd" id="17_bg_pulse"]
```

- **节点块（插入 `AtmosphereLayer` 内、`RainCurtain` 节点声明**之前**，即 AtmosphereLayer 首子）:**

```
[node name="BgPulse" type="ColorRect" parent="AtmosphereLayer"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.29, 0.56, 0.85, 1)
script = ExtResource("17_bg_pulse")
```

  - 全屏锚点（anchors_preset=15，同 ScoreFlashRect/PauseOverlay ColorRect 既有写法）
  - `color` 初始 = `BG_PULSE_TINT`（RGB 定、alpha 由脚本逐帧驱动）
  - 子节点顺序 = 绘制顺序：BgPulse（最底）→ RainCurtain → L1 世界 → L3 UI（Spike 2 实机截图确认）

---

## 4. 数据流

### Flow 1：每帧运行流（正常路径）

```
_process(delta)                              [每帧，与 FSM 状态无关]
    _t += delta
    alpha = compute_alpha(_t, BG_PULSE_PERIOD=4.0,
                          BG_PULSE_BASE_ALPHA=0.08,
                          BG_PULSE_AMPLITUDE=0.07)
          = clamp(0.08 + 0.07·sin(TAU·t/4.0), 0, 1)
    color.a = alpha                          # RGB = BG_PULSE_TINT 恒定
        │
        ▼
WorldEnvironment glow(0.6)/bloom(0.8) 放大 → 背景微光起伏（「光晕呼吸」）
        │
        ▼
渲染顺序（同层先声明 = 先绘制 = 更底）:
  AtmosphereLayer(layer=0): BgPulse → RainCurtain
  → 世界 L1（球/挡板/砖墙）→ 反馈 L2 → UI L3（GameHUD layer=1 / PauseOverlay layer=10）
```

### alpha 相位表（t ∈ [0, 4s)）

| t (s) | sin(TAU·t/4) | alpha |
|:-----:|:------------:|:-----:|
| 0.0 | 0 | 0.08（基线） |
| 1.0 | +1 | 0.15（峰值） |
| 2.0 | 0 | 0.08（基线） |
| 3.0 | −1 | 0.01（谷值） |
| 4.0 | 0 | 0.08（回到基线，周期闭合） |

### Flow 2：异常路径（period ≤ 0）

```
compute_alpha 收到 period ≤ 0 → 直接返回 base（0.08），不产生 NaN/除零
→ 视觉上背景恒为基线（安全退化），无脚本错误（AC4 不破坏）
```

### Flow 3：场景加载 / 重启

```
Main.tscn 重载 → _t 从 0 起 → alpha 从 0.08（基线）起步
→ 与上一帧任意 alpha 值最多差 0.07（半周期），无可见跳变
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | **headless 运行**（AC4） | `_process` 在 headless 下照常 tick、ColorRect 不参与渲染 → 无脚本错误即通过；断言走纯函数（不依赖渲染） |
| 2 | **`period ≤ 0`** | `compute_alpha` 前置守卫返回 `base`（防除零 NaN，先例 #287/#389） |
| 3 | **并行 constants.gd 合并（T2 核心）** | T1 #448（HUD 区，已在 main）/ T3 #450（AUDIO 区，research 中）与本 Issue（BG 区）三区互不重叠 → 提交前 `git merge origin/main` 自动合并；真冲突（≤2 文件）由 worktree-commit.sh 自动解决，否则 abort + 报告（不硬解） |
| 4 | **E2E 帧间差异断言敏感** | 4s 周期正弦在 settle_frames=5 窗口内 alpha 变化 ≈ 0.07·sin(微弧) ≈ 满幅 1% 量级，亮度差 <1% → 理论上不受影响；若实测过敏 → 调 shot 参数（settle_frames），**不删脉冲**（Spike 1） |
| 5 | **MENU / PLAYING / PAUSED / SCORED / GAME_OVER** | 氛围层 FSM-independent（同雨幕纪律）：全程呼吸；无状态切换逻辑、无信号依赖；PauseOverlay（layer=10）在呼吸之上，可读性不受影响 |
| 6 | **色数/主题色断言（4a90d9）** | BgPulse 色调 = PLAYER_NEON_BLUE 同系（0.29,0.56,0.85）→ 与主题色同色系，色数断言不因新增色而漂移（Spike 1 确认） |
| 7 | **场景重载相位重置** | `_t` 从 0 起 → alpha 从基线起步，无跳变（Flow 3） |
| 8 | **glow/bloom 放大过度（太亮抢注意力）** | 收窄振幅（AMP 0.07→0.04）或降 BASE —— 常量级修正，零代码改动（taste-draft，human-review 定稿） |
| 9 | **渲染顺序不对（BgPulse 意外盖住雨幕/球）** | 子节点顺序/z-index 修正（AtmosphereLayer 内 BgPulse 先于 RainCurtain 声明）；Spike 2 实机截图验证 |

---

## 6. 集成点

> **Status 约定:** ⬜ = pending（由 implement agent 接线）；✅ = 已由实现验证。implement agent 完成接线后须更新本表；review agent 合并前验证所有 ⬜ 已解决或显式延期。

| Integration | Our Component | Target | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 常量供给 | bg_pulse.gd | constants.gd `BG_PULSE_*` | `const CONSTS = preload(...)` + `_process` 引用 4 个常量 | ⬜ pending |
| 节点挂载 | `BgPulse` ColorRect | Main.tscn `AtmosphereLayer`（layer=0）首子 | ext_resource `17_bg_pulse` + 节点块，声明于 RainCurtain 之前 | ⬜ pending |
| 光晕放大 | `BgPulse.color.a` | `world_environment.tscn` glow(0.6)/bloom(0.8) | 被动集成：零代码改动，bloom 放大 2D 内容 | ⬜ pending（Spike 2 截图验证） |
| 同层顺序 | `BgPulse` | `RainCurtain`（AtmosphereLayer 内） | 同层子节点顺序 = 绘制顺序（BgPulse 先声明 = 最底） | ⬜ pending（Spike 2） |
| FSM / 信号链 | bg_pulse.gd | game_state_machine.gd 等 | **无集成**（FSM-independent，不连接任何信号） | ✅ n/a |
| 测试域 | — | tests/、run_tests.gd | **零改动**（AC5 文件域红线；纯函数为后续独立测试留口） | ✅ n/a |

---

## 7. 测试策略与用例描述

**红线（AC5）**：本 Issue **不新增/不修改任何测试文件**（`tests/` 零改动）；验收 = 既有测试全绿 + E2E 断言实测 + 纯函数边界手测。以下为 implement agent 的验证动作描述（非可运行代码）。

### Scenario A：headless 健康（AC4）
- Test A1：`godot --path mini-pong/ --headless --quit` 退出码 0、无脚本错误（含 bg_pulse.gd 加载与 `_process` 求值）
- Test A2：`run_tests.gd` 全绿 —— 基线 2214 passed / 0 failed 不回退

### Scenario B：纯函数边界（compute_alpha，可手测/未来独立单测留口）
- Test B1：`compute_alpha(0, 4.0, 0.08, 0.07) == 0.08`（t=0 → 基线）
- Test B2：`compute_alpha(1.0, 4.0, 0.08, 0.07) ≈ 0.15`（t=period/4 → base+amp）
- Test B3：`compute_alpha(2.0, 4.0, 0.08, 0.07) ≈ 0.08`（t=period/2 → 回到基线）
- Test B4：极端参数 clamp：`compute_alpha(1.0, 4.0, 0.9, 0.5) == 1.0`、`compute_alpha(3.0, 4.0, 0.1, 0.5) == 0.0`
- Test B5：`compute_alpha(1.0, 0.0, 0.08, 0.07) == 0.08`（period ≤ 0 守卫，无 NaN）

### Scenario C：E2E 截图断言（loop 组，L3 视觉层）
- Test C1：`01_title`（MENU）4 重断言（非黑/色数/主题色 4a90d9/帧间差异）通过，呼吸背景不破坏
- Test C2：`02_midgame`（PLAYING，settle_frames=5）4 重断言通过；若帧间差异断言对 4s 正弦过敏 → 调 shot 参数（settle_frames），**不删脉冲**（Spike 1）
- Test C3：实机截图确认 BgPulse 在雨幕/球/砖/UI 之下、峰值亮度差肉眼可辨但克制（Spike 2）

---

## 8. 实现阶段

| Phase | Priority | 内容 | 文件 | 估计 |
|:-----:|:--------:|------|------|:----:|
| Phase 1 | P0 | 追加 `BG_PULSE_*` 常量区（文件末尾，既有区逐字节不动） | `gdscripts/constants.gd` | 0.1 天 |
| Phase 2 | P0 | 新建 `bg_pulse.gd`（纯函数 + `_process`） | `gdscripts/bg_pulse.gd`（新） | 0.2 天 |
| Phase 3 | P0 | Main.tscn 挂载 `BgPulse`（ext_resource `17_bg_pulse` + AtmosphereLayer 首子节点） | `scenes/Main.tscn` | 0.1 天 |
| Phase 4 | P0 | 验证：headless `--quit` + run_tests 全绿 + E2E loop（Spike 1 断言实测） | — | 0.2 天 |
| Phase 5 | P1 | Spike 2 实机截图：渲染顺序 + 克制观感确认（taste 数值交 human-review） | — | 0.2 天 |

**实现顺序建议（继承 PRD §8）：** constants → bg_pulse.gd → Main.tscn → headless 验证 → Spike 1（E2E 断言实测）→ Spike 2（顺序 + 观感）→ `worktree-commit.sh` 白名单提交（提交前 merge main 自动合并 T1/T3 的 constants 区）→ PR + CI。

---

## 9. 验收条件映射（AC checklist，源自 Issue #449 body）

| AC | 内容 | 设计落实 |
|----|------|---------|
| AC1 | bg_pulse.gd 实现背景光晕正弦呼吸（周期可配，默认 ~4s） | §3.1 `compute_alpha` 纯函数 + `_process`；`BG_PULSE_PERIOD = 4.0` 常量可配 |
| AC2 | Main.tscn 挂载 bg_pulse 节点，不影响现有场景树 | §3.3 纯增量（1 ext_resource + 1 节点块）；既有 15 节点零改动；has_node 断言 additive-safe（已核实） |
| AC3 | constants.gd 新增 BG 区常量，不影响现有常量 | §3.2 文件末尾追加 `BG_PULSE_*` 4 常量；既有区逐字节不动 |
| AC4 | --headless --quit 无脚本错误，run_tests.gd 全绿 | §7 Scenario A；基线 2214 passed / 0 failed 不回退 |
| AC5 | PR files 仅含本 Issue 文件域 | 白名单 = `bg_pulse.gd` + `Main.tscn` + `constants.gd`；worktree-commit.sh 白名单 add；不新增测试文件 |

### 明确不修改（继承 PRD §1.4/§3.3）

- `mini-pong/scenes/world_environment.tscn`（test_neon TC2/TC3 文本断言）
- `mini-pong/gdscripts/rain_curtain.gd`、雨量公式、`RAIN_*` 常量（#389 契约）
- FSM / 信号链 / `game_state_machine.gd` 等
- `mini-pong/tests/*`、`run_tests.gd`
- Main.tscn 既有节点与既有 ext_resource
- 其他 issue 文件（#448 HUD 区 / #450 AUDIO 区）

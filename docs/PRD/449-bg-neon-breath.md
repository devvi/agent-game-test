# PRD: [Feature] 背景霓虹呼吸 — 背景光晕缓慢脉冲

> **Issue:** #449
> **标签:** enhancement, workflow/research, graphics, version/v1
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386/#389/#392 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（headless 下 ColorRect 渲染、E2E 帧间差异断言、L0 层内渲染顺序）而包含 2 个轻量实验）
> **所有权:** `content_ownership: mechanical`（正弦脉冲机制/常量定义/节点挂载 = 机械可测；脉冲峰值不透明度、霓虹色调值 = taste-draft，走 human-review 定稿）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3.1 分层（L0 氛围层: 雨幕粒子 + 底部城市光晕 + 暗角(≤10%)）— 本 Issue 是 L0「背景光晕」的执行层；雨幕（#389）已落地，背景光晕/暗角未落地
> **并行上下文:** worktree 并行测试 T2（2026-08-13）— 三个并行 issue 刻意都改 `constants.gd` 的**不同区域**（T1 #448 → HUD 区、T2 #449 → 新增 BG 区、T3 #450 → AUDIO 区），验证「提交前 merge main」的自动合并。本 Issue 文件域（红线）：`mini-pong/gdscripts/bg_pulse.gd`（新）+ `mini-pong/scenes/Main.tscn` + `constants.gd` 新增 BG_PULSE 区

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）的 L0 氛围层**只有雨在呼吸，背景是死的**：雨幕粒子随球速/波次/紧张度动态起伏（#389），但其下方的背景底色 `#0a0a12` 恒定不变。PLAN §3.1 已确认的 L0 规格「雨幕粒子 + 底部城市光晕 + 暗角(≤10%)」目前只落地了雨幕一项。

| 文件 | 当前状态 | 与 #449 需求的差距 |
|------|---------|------------------|
| `mini-pong/scenes/world_environment.tscn` | Environment：`background_color = Color(0.039,0.039,0.071,1)`（#0a0a12）、`glow_enabled=true`、`glow_intensity=0.6`、`glow_bloom=0.8`（#289） | ⚠️ 背景完全静止；glow/bloom 已开启，是「呼吸光晕」的天然放大器 — **本 Issue 不修改此文件**（`test_neon.gd` TC2/TC3 文本断言其内容） |
| `mini-pong/gdscripts/constants.gd` | `BG_COLOR` 已在 Rain 区（#389）；无 BG_PULSE 区；文件按区域分节（Screen/Ball/Paddle/AI/Scoring/Rain/HUD/Upgrade/Failure） | ❌ 缺 `BG_PULSE_*` 常量区（周期/基线/振幅/色调） |
| `mini-pong/scenes/Main.tscn` | `AtmosphereLayer`（CanvasLayer layer=0）> `RainCurtain`；L1 世界（球/挡板/砖墙）、L2 反馈、L3 UI（GameHUD layer=1 等）分层就位（GDD22） | ❌ 无背景呼吸节点；AtmosphereLayer 目前只有 RainCurtain 一个子节点 |
| `mini-pong/gdscripts/bg_pulse.gd` | **❌ 不存在** | 需新建（本 Issue 唯一新文件） |
| `mini-pong/tests/` | run_tests.gd 注册 20+ 套件（基线 2214 passed / 0 failed，2026-08-13 复跑） | ✅ 保持全绿（AC4）；文件域红线（AC5）不含新测试文件，测试性靠纯函数设计（§3.1） |
| `mini-pong/e2e_shots.json` | loop 组 match `gdscripts/.*\.gd` + `scenes/.*\.tscn` + `project\.godot` → bg_pulse.gd / Main.tscn 改动必然命中；02_midgame（PLAYING，settle 5 帧）截图含背景 | ⚠️ 背景 alpha 随时间正弦变化 → 4 重断言（非黑/色数/主题色 4a90d9/帧间差异）需实测（Spike 1） |

**关键事实核查（来自源码）：**

- `world_environment.tscn` 的 `background_mode = 0`（清屏色模式）+ glow 已启用 → 2D 内容（含 ColorRect）会被 glow/bloom 放大，「呼吸」在视觉上表现为背景微光起伏，符合「背景光晕」语义
- `AtmosphereLayer` layer=0 是**最低 CanvasLayer**（GDD22 明确「Layer 0 is the lowest CanvasLayer — rain never covers walls/ball/paddles/UI」）→ 背景呼吸节点挂在此层内即可结构性保证低于世界/UI
- 雨幕已有 `set_breathing()` 与 `RAIN_BREATHING_DROP`（#389）——「呼吸」概念在氛围层已有先例，本 Issue 把它扩展到背景基底
- `test_main_scene.gd` TC1-2~TC1-15 用 `has_node` 断言既有节点存在（WorldEnvironment/LeftWall/Ball/GameHUD…）——**新增节点是 additive-safe**，不破坏任何既有断言
- `test_constants.gd` 只断言既有常量的值（TC6/TC7/TC8 + dual-scoring/wave-cycle 区）——新增 `BG_PULSE_*` 常量零风险
- 本 Issue 无依赖链前置（不依赖 #448/#450；#448/#450 是并行 peer 而非依赖）

### 1.2 预期行为（验收条件，源自 Issue #449）

1. **AC1 — bg_pulse.gd 实现背景光晕正弦呼吸（周期可配，默认 ~4s）** — `compute_alpha(t)` 为纯函数：`clamp(base + amplitude * sin(TAU * t / period), 0.0, 1.0)`；周期/基线/振幅来自 constants.gd `BG_PULSE_*`，默认 `BG_PULSE_PERIOD = 4.0`
2. **AC2 — Main.tscn 挂载 bg_pulse 节点，不影响现有场景树** — AtmosphereLayer 下新增 ColorRect 子节点（bg_pulse.gd），全屏锚点，置于 RainCurtain 之前；既有节点零改动
3. **AC3 — constants.gd 新增 BG 区常量（BG_PULSE_PERIOD: float = 4.0 等），不影响现有常量** — 只新增 `# ── Background Pulse (#449) ──` 区；RAIN_/HUD_/UPGRADE_/WAVE_ 等既有区**逐字节不动**（并行 T1 #448 / T3 #450 各改各的区）
4. **AC4 — --headless --quit 无脚本错误，run_tests.gd 全绿** — 基线 2214 passed / 0 failed 不得回退；headless 下 _process 照常 tick、无渲染错误即通过
5. **AC5 — PR files 仅含本 Issue 文件域，不混入其他 issue 文件** — 实现 PR 只允许 3 个文件：`gdscripts/bg_pulse.gd`（新）、`scenes/Main.tscn`、`gdscripts/constants.gd`（仅 BG 区）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 标题画面（MENU） | 持续 | 雨幕微雨 + 背景缓慢明暗呼吸（周期 4s），「雨夜竞技场」第一眼氛围；VersionLabel/HUD 文字不受影响 |
| B | 对打进行中（PLAYING） | 持续 | 球速/比分制造的雨量起伏叠加在呼吸的背景基底上；呼吸节奏恒定可预测（正弦），不与事件脉冲抢注意力 |
| C | 暂停（PAUSED） | 每局多次 | 背景继续呼吸（氛围层 FSM-independent，同雨幕纪律）；PauseOverlay（layer=10）在呼吸之上，可读性不受影响 |

### 1.4 技术约束（继承 Issue #449 + PLAN-rogue-pong + 并行测试上下文）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 project.godot，720×1280 竖屏，Forward+） |
| 文件域（AC5 红线） | 仅 `bg_pulse.gd`（新）+ `scenes/Main.tscn` + `constants.gd` BG 区；**不得**新增测试文件/改其他文件（与 #448/#450 的并行域隔离） |
| constants.gd 分区纪律 | 只新增 `BG_PULSE_*` 区；既有区逐字节不动（自动合并测试的核心假设） |
| 分层 | 背景呼吸 = L0（AtmosphereLayer layer=0，RainCurtain 之前），低于世界/反馈/UI；不得新建更高层 |
| 不变项 | `world_environment.tscn` 零改动（test_neon 文本断言）；FSM/信号链/雨幕公式（#389）/手感数值（#367）不变；Main.tscn 既有节点零改动 |
| headless | `--headless --quit` 无脚本错误；run_tests.gd 全绿（AC4） |
| 克制原则 | 脉冲峰值 ≤10–15%（PLAN §3.1 暗角上限 ≤10% 同量级），周期 ~4s 缓慢；不堆砌特效（Obsidian「90 年代地摊文艺」反例约束） |
| 所有权 | `content_ownership: mechanical`（机制/常量/挂载）；峰值不透明度、霓虹色调 = taste-draft（human-review 定稿） |
| 开源优先 | 调研结果见 §1.5 — 结论：不引入第三方资产，第一方实现并说明理由 |

### 1.5 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library（官方 API，godot_version=4.7）+ GitHub 社区：

- **Godot Asset Library**：`background` → Chey's Background Addon（**编辑器背景工具**）、Pixel space background generator（**生成器工具**）、Scrolling Backgrounds Tool（**编辑器工具**）——均为编辑期工具，非运行时背景动画；`pulse` → DwarfImpulse（C# 相机震动插件，无关）；`glow` → Glowing Border Effect（4.3 边框描边 shader，非背景呼吸）、其余为 3D 工具；`vignette` / `breathing` → 0 条
- **GitHub/社区**：无「背景霓虹呼吸 / background breathing」成熟运行时方案；呼吸背景在 Godot 生态中的通行做法是 ColorRect/CanvasModulate 脚本动画或自写 shader，属引擎内建能力（无 addon 依赖）
- **结论**：**无可直接复用的成熟方案**。第一方实现（ColorRect + 正弦 alpha + 既有 glow/bloom 放大）零依赖、headless 安全、成本最低，符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，含 `raw/` + `wiki/`）：检索关键词「呼吸 / 光晕 / 氛围 / 背景 / 霓虹 / 克制」命中以下笔记——
- `wiki/体验引擎-patterns.md`：「沉浸感被 UI 破坏 → 隐形界面」（:112）+ §14「可预测的奖励变得无聊」——氛围层是沉浸感载体；呼吸必须**恒定周期、可预测**（正弦而非随机），不随游戏事件突变（事件性起伏已由雨幕承担，背景呼吸只做基底）
- `wiki/九十年代素材与文化参考.md`：90 年代地摊猎奇美学是「雨夜竞技场」氛围参考（:37，同 #389/#392 引用链）
- `wiki/90年代地摊文艺.md`：反例约束（克制、不堆砌特效）——脉冲峰值 ≤10–15%、周期 4s 缓慢、色调贴近既有霓虹蓝（PLAYER_NEON_BLUE 同系），不抢球/砖/UI 注意力
- **上游确认**：L0 规格已由 `docs/PLAN-rogue-pong.md` §3.1 **用户拍板**（雨幕 + 底部城市光晕 + 暗角 ≤10%）；本 Issue 只执行「背景光晕」一项，暗角（≤10%）与底部城市光晕属后续 backlog，不在本 Issue 范围

### 1.7 范围边界（与相邻 PRD/Issue 解冲突）

| PRD/Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #289 霓虹视觉基调 | 深底 #0a0a12、glow 0.6/bloom 0.8、PLAYER_NEON_BLUE/AI_NEON_RED、球拖尾/score flash | ❌ 不改 world_environment.tscn 任何参数；呼吸叠加在既有 glow 之上（glow 即放大器） |
| #389 动态雨幕 | L0 雨幕粒子、雨量公式、`RAIN_BREATHING_DROP`、`set_breathing()` 契约 | ❌ 不碰 rain_curtain.gd/雨公式/RAIN_ 常量；只做雨幕**下方**的背景基底 |
| #448 球速 HUD（T1） | constants.gd HUD 区 + 球速显示（OPEN，workflow/available） | ❌ 不碰 HUD 区与 UI 层；并行 merge 测试 peer |
| #450 拆砖音效（T3） | constants.gd AUDIO 区 + 音效（OPEN，workflow/research） | ❌ 不碰 AUDIO 区；并行 merge 测试 peer |
| #392 霓虹 HUD | L3 UI（描边/投影/分区） | ❌ 背景是 L0，结构性低于 HUD；互不干扰 |
| PLAN §3.1 L0 未落地项 | 底部城市光晕、暗角（≤10%） | ❌ 属后续 backlog；本 Issue 只做「背景光晕缓慢脉冲」 |

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 现状 | 成因 | 证据 |
|------|------|------|
| 背景底色静止 | #289 只定了静态深底 #0a0a12 + glow/bloom；「呼吸」概念当时尚未进入氛围层 | world_environment.tscn 无任何动画 |
| 只有雨在呼吸 | #389 落地了 PLAN §3.1 三件套中的雨幕；背景光晕/暗角未排期 | rain_curtain.gd 有 `_breathing`/`RAIN_BREATHING_DROP`；无背景对应物 |
| 无 BG_PULSE 常量区 | 背景无动态参数需求，constants.gd 无对应区域 | constants.gd 区域清单（§1.1） |

### 2.2 为什么现在改

1. **上游已拍板**：PLAN §3.1 明确 L0 = 雨幕 + 底部城市光晕 + 暗角；本 Issue 是 L0 氛围层的补全（背景光晕呼吸），雨夜竞技场观感的最后一块基底
2. **雨已呼吸、底不呼吸 = 视觉断层**：雨量是「情绪仪表盘」（#389），但背景静止会让整个氛围层缺了基底衬托；背景缓慢呼吸让「雨夜」有生命感，且不抢事件性表达（事件脉冲归雨幕）
3. **成本窗口**：AtmosphereLayer 已存在、glow/bloom 已开启、无任何前置依赖——纯增量挂载一个 ColorRect + 一段纯函数，零回归面（additive 节点 + 新增常量）
4. **并行测试 T2 的验收载体**：三个 issue 同改 constants.gd 不同区，本 Issue 是验证「提交前 merge main 自动合并」的三个样本之一（§5 边界 2）

### 2.3 先前约束

| 约束 | 细节 |
|------|------|
| #289 视觉基调 | 深底 #0a0a12、glow_intensity 0.6、bloom 0.8；霓虹色源 = PLAYER_NEON_BLUE（#4a90d9） |
| #389 分层纪律 | AtmosphereLayer layer=0 为最低层；雨幕「modulate 不 re-seed」「契约 API 唯一写入口」；氛围层 FSM-independent（MENU/PLAYING/PAUSED 都运行） |
| PLAN §3.1 | L0 三件套已确认；克制量级参考：暗角 ≤10% |
| Obsidian 克制原则 | 90 年代地摊文艺反例约束：不堆砌特效；呼吸 = 恒定正弦、缓慢、低峰值 |

---

## 3. 影响分析

### 3.1 新文件

| 文件 | 类型 | 职责 |
|------|------|------|
| `mini-pong/gdscripts/bg_pulse.gd` | 脚本（extends ColorRect） | 背景呼吸控制器：`static func compute_alpha(t: float, period: float, base: float, amplitude: float) -> float`（纯函数，headless 可单测）+ `_process` 内 `color.a = compute_alpha(...)`；色调 `color = BG_PULSE_TINT`（霓虹蓝同系，alpha 驱动呼吸）；glow/bloom 自动放大为「背景光晕」 |

### 3.2 直接改动文件

| 文件 | 改动性质 |
|------|---------|
| `mini-pong/gdscripts/constants.gd` | **新增** `# ── Background Pulse (#449) ──` 区（置于文件末尾既有区之后）：`BG_PULSE_PERIOD: float = 4.0`（周期 ~4s，AC1）、`BG_PULSE_BASE_ALPHA: float = 0.08`、`BG_PULSE_AMPLITUDE: float = 0.07`（alpha ∈ [0.01, 0.15]，克制区间 ≤15%）、`BG_PULSE_TINT: Color = Color(0.29, 0.56, 0.85, 1.0)`（PLAYER_NEON_BLUE 同系）。既有区逐字节不动（AC3） |
| `mini-pong/scenes/Main.tscn` | **增量**：AtmosphereLayer 下新增 ColorRect 子节点（name=`BgPulse`，script=bg_pulse.gd，anchors_preset=15 全屏，置于 RainCurtain **之前**）——新增节点、不改动既有节点（AC2；test_main_scene has_node 断言 additive-safe） |

### 3.3 间接影响（需回归验证）

| 文件 | 影响 | 处理 |
|------|------|------|
| `mini-pong/scenes/world_environment.tscn` | 零改动（test_neon TC2/TC3 文本断言 `glow_bloom = 0.8` / 背景色） | ✅ 不碰；呼吸叠加在既有 glow 之上 |
| `mini-pong/tests/test_main_scene.gd` | TC1 系 has_node 断言（WorldEnvironment/…/GameHUD）对新增节点 additive-safe | 零改动；实现 PR 后跑全绿确认 |
| `mini-pong/tests/test_constants.gd` | 只断言既有常量值 | 零改动；新增 BG_PULSE_* 不触及 |
| `mini-pong/tests/run_tests.gd` | 保持全绿（AC4） | 无新测试文件（AC5 文件域红线）；`compute_alpha` 纯函数设计为后续测试留口 |
| `mini-pong/e2e_shots.json` | 02_midgame 截图含背景呼吸 | 4 重断言实测（Spike 1）：帧间差异断言对 4s 周期正弦的敏感度需验证 |
| `docs/GAME_DESIGN/12-NEON-VISUAL.md` / `22-RAIN-CURTAIN.md` | L0 描述将过时（背景呼吸未记载） | 实现 PR merge 后由 review agent 增量更新（GDD 惯例） |

### 3.4 运行流

```
_process(delta)  [每帧]
    t += delta
    alpha = bg_pulse.compute_alpha(t, CONSTS.BG_PULSE_PERIOD,
                                   CONSTS.BG_PULSE_BASE_ALPHA,
                                   CONSTS.BG_PULSE_AMPLITUDE)
    color.a = alpha        # color = BG_PULSE_TINT（霓虹蓝同系）
        │
        ▼
WorldEnvironment glow(0.6)/bloom(0.8) 放大 → 背景微光起伏（"光晕呼吸"）
        │
        ▼
渲染顺序: AtmosphereLayer(layer=0) 首子 = BgPulse（最底）→ RainCurtain → 世界 L1 → UI L3
```

- 纯函数 `compute_alpha` 无状态依赖（除 t 递增），headless 下照常求值、无渲染错误
- 氛围层 FSM-independent（同雨幕纪律）：MENU/PLAYING/PAUSED 全程呼吸，无状态切换逻辑

### 3.5 文档更新

- [ ] `docs/PRD/449-bg-neon-breath.md`（本文件）
- [ ] `docs/GAME_DESIGN/12-NEON-VISUAL.md` / `22-RAIN-CURTAIN.md` — 实现 PR merge 后由 review agent 增量更新（L0 背景呼吸）
- [ ] 本 PRD merge 后自动推进 Issue #449 → `workflow/plan`（workflow-chain.yml；squash-merge 若不触发则 REST API 手动推进）

---

## 4. 方案对比

本 Issue 含两个设计轴：**脉冲实现机制**（4.1）与**场景挂载位置**（4.2），按项目多轴 PRD 惯例（#392/#389 先例）分节对比，末尾汇总推荐组合。

### 4.1 脉冲实现机制

#### Approach A：ColorRect + 脚本正弦 alpha（推荐）

`bg_pulse.gd`（extends ColorRect）全屏铺底，`_process` 按 `compute_alpha(t) = clamp(base + amp·sin(TAU·t/period), 0, 1)` 写 `color.a`；色调 = `BG_PULSE_TINT`（霓虹蓝同系）；WorldEnvironment 既有 glow/bloom 自动放大为光晕。

- **Pros**：纯增量（1 新脚本 + 1 节点）；纯函数可 headless 单测；零第三方依赖；headless 安全（ColorRect 无渲染错误）；glow/bloom 放大是免费的光晕来源；克制量级精确可控（alpha 区间即常量）
- **Cons**：均匀提亮（非径向「光晕中心」渐变）——但「光晕」语义由 bloom 承担，均匀呼吸正是「背景呼吸」的字面含义；每帧写 alpha 开销极低（单 Control）
- **Risk**：Low — 纯函数 + additive 节点；E2E 帧间差异断言需实测（Spike 1）
- **Effort**：0.5 天

#### Approach B：Environment.background_color 运行时动画

脚本每帧改 `WorldEnvironment.environment.background_color`（在 #0a0a12 与提亮色之间摆动）。

- **Pros**：直接改「真正的背景」，无额外节点
- **Cons**：`environment` 是**共享资源**（world_environment.tscn 的 SubResource），运行时突变污染全局环境语义、与未来暗角/城市光晕（同改 Environment）冲突；test_neon TC3 若读背景色（运行时值 vs 文件文本断言）有歧义；glow 对 clear color 的放大行为不如 2D ColorRect 直观；调试/回滚差
- **Risk**：Med — 共享资源突变是隐性全局状态
- **Effort**：0.5 天

#### Approach C：ColorRect + 自写 shader（时间参数/径向渐变）

自定义 canvas shader（`TIME` 驱动，径向渐变 + 正弦）。

- **Pros**：视觉最强（真「光晕中心」渐变）
- **Cons**：**违背克制原则**（§1.6：不堆砌特效）；shader 时间参数在 headless 下不可断言、难单测；增加导入/渲染面（#216 addon 分类调研先例：视觉资产常是运行时坑）；对「缓慢均匀呼吸」需求属过度设计
- **Risk**：Med-High（测试性差 + 复杂度）
- **Effort**：1–2 天

**推荐：Approach A。** 理由：(1) 唯一满足 AC1「正弦呼吸、周期可配」且 headless 可测的方案（纯函数）；(2) 零第三方/零 shader，符合开源优先调研结论与克制原则；(3) 纯增量、零回归面（AC2/AC4）；(4) 既有 glow/bloom 免费提供「光晕」语义。

### 4.2 场景挂载位置

#### Approach A：AtmosphereLayer（layer=0）首子节点（推荐）

`BgPulse`（ColorRect）挂在 `AtmosphereLayer` 下、`RainCurtain` **之前**（同层内先绘制 = 最底）。

- **Pros**：与 GDD22 架构一致（layer=0 是最低 CanvasLayer，结构性保证低于世界/UI）；零新层；节点顺序语义清晰（背景 → 雨 → 世界 → UI）；test_main_scene additive-safe
- **Cons**：同层内渲染顺序依赖子节点顺序（ColorRect 先于 RainCurtain 声明）——实现时需确认（Spike 2）
- **Risk**：Low — 分层已由 #389 验证；顺序问题可在 Spike 2 截图确认
- **Effort**：0.1 天

#### Approach B：独立 CanvasLayer（layer=-1）

新建 `BackgroundLayer`（layer=-1）挂 BgPulse，确保在默认画布之下。

- **Pros**：渲染顺序最保险
- **Cons**：**与 GDD22「L0 是最低层」文档冲突**（引入 layer=-1 打破分层文档）；负 layer 在部分平台/headless 有边缘情况；多一层徒增复杂度
- **Risk**：Med（文档漂移 + 边缘情况）
- **Effort**：0.2 天

#### Approach C：Game 根节点直接子 Control

ColorRect 直接挂 `Game`（Node2D）下，anchors 相对视口全屏。

- **Pros**：最简
- **Cons**：脱离 CanvasLayer 分层体系，渲染顺序依赖 z 值，与雨幕分层文档不一致；未来暗角/城市光晕加入时无层可归
- **Risk**：Med（分层纪律破坏）
- **Effort**：0.1 天

**推荐：Approach A。** 理由：(1) 完全复用 #389 已验证的 L0 分层；(2) 结构性保证低于世界/UI（AC2「不影响现有场景树」）；(3) 不引入新层/新概念，与 GDD22 文档一致。

### 4.3 推荐组合汇总

| 设计轴 | 推荐 | 核心文件 |
|--------|------|---------|
| 脉冲实现机制 | A：ColorRect + 脚本正弦 alpha（纯函数 compute_alpha） | `bg_pulse.gd`（新） |
| 场景挂载 | A：AtmosphereLayer 首子节点（RainCurtain 之前） | `scenes/Main.tscn` |
| 常量 | 新增 `BG_PULSE_*` 区（PERIOD=4.0 / BASE=0.08 / AMP=0.07 / TINT=霓虹蓝同系） | `gdscripts/constants.gd`（仅新增区） |

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body）

- [x] **AC1: bg_pulse.gd 实现背景光晕正弦呼吸（周期可配，默认 ~4s）** — `compute_alpha(t, period, base, amplitude) = clamp(base + amplitude·sin(TAU·t/period), 0, 1)`；`BG_PULSE_PERIOD = 4.0`（常量可配）；headless 下纯函数可断言（Spike 1）
- [x] **AC2: Main.tscn 挂载 bg_pulse 节点，不影响现有场景树** — AtmosphereLayer 下新增 `BgPulse` ColorRect（全屏锚点，RainCurtain 之前）；既有节点零改动；test_main_scene TC1 系 additive-safe
- [x] **AC3: constants.gd 新增 BG 区常量，不影响现有常量** — 只新增 `BG_PULSE_*` 区；既有区逐字节不动；test_constants 只断言既有值 → 零风险
- [x] **AC4: --headless --quit 无脚本错误，run_tests.gd 全绿** — 基线 2214 passed / 0 failed（2026-08-13 复跑）不回退；实现 PR 后复跑确认
- [x] **AC5: PR files 仅含本 Issue 文件域** — 实现 PR 白名单 = `bg_pulse.gd` + `Main.tscn` + `constants.gd`（worktree-commit.sh 白名单 add，绝不 add .）

### 边界情况（Edge Cases）

1. **headless 运行** — `_process` 在 headless 下照常 tick，但 ColorRect 不参与渲染：无脚本错误即通过（AC4 字面要求）；断言走纯函数（不依赖渲染）
2. **并行 constants.gd 合并（T2 测试核心）** — T1 #448（HUD 区）/ T3 #450（AUDIO 区）与本 Issue（BG 区）提交前 merge main：三区互不重叠 → git 自动合并应成功；若真冲突（≤2 文件），worktree-commit.sh 自动解决，否则 abort + 报告（不硬解）
3. **E2E 帧间差异断言** — 周期 4s 正弦，settle 5 帧窗口内 alpha 变化 ≈ 满幅的 1% 量级（0.07·sin 微弧），亮度变化 < 1% → 帧间差异断言理论上不受影响；若实测敏感 → 调 shot 参数（settle_frames），**不删脉冲**（Spike 1）
4. **主菜单/暂停/终局** — 氛围层 FSM-independent（同雨幕）：全程呼吸，无状态切换逻辑、无信号依赖
5. **色数断言（主题色 4a90d9）** — BgPulse 使用 PLAYER_NEON_BLUE 同系色调（0.29,0.56,0.85）→ 与主题色同色系，色数/主题色断言不受新增色干扰（Spike 1 确认）

### 失败路径（Failure Paths）

1. **E2E 断言变红**（02_midgame 帧间差异/色数）→ 先调 shot 参数（settle_frames/断言阈值），不删脉冲内容；若主题色断言被干扰，检查断言实现允许多主题色（同 #392 先例）
2. **渲染顺序不对**（BgPulse 意外盖住雨幕/球）→ 子节点顺序/z-index 修正（AtmosphereLayer 内 BgPulse 先于 RainCurtain）；Spike 2 实机截图验证
3. **constants 合并冲突无法自动解决** → worktree-commit.sh abort + 报告人工处理（并行测试 T2 的预期风险之一，有预案）
4. **taste 数值不被认可**（峰值/色调）→ human-review 定稿：alpha 区间/色调全部收敛在 `BG_PULSE_*` 常量，调参零代码改动
5. **glow/bloom 放大过度**（呼吸太亮抢注意力）→ 收窄振幅（AMP 0.07 → 0.04）或降 BASE，常量级修正（Spike 2 视觉确认）

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #289 霓虹视觉基调（glow/bloom/底色） | ✅ CLOSED | Low — 呼吸的放大器与底色 |
| #389 动态雨幕（L0 分层 + AtmosphereLayer） | ✅ CLOSED（PR #416） | Low — 挂载容器与分层纪律 |
| PLAN-rogue-pong §3.1（L0 规格已确认） | ✅ 已确认 | Low — 上游方案 |

### 并行 Peer（非依赖）

| Peer | 状态 | 共享面 |
|------|------|--------|
| #448 球速 HUD（T1） | OPEN（workflow/available） | constants.gd HUD 区（本 Issue 不碰） |
| #450 拆砖音效（T3） | OPEN（workflow/research） | constants.gd AUDIO 区（本 Issue 不碰） |

三个 peer 共改 constants.gd 不同区 → 提交前 merge main 自动合并（T2 验证目标）；无阻塞关系。

### 依赖链

```
#289 霓虹基调（✅） → #389 雨幕/L0 分层（✅）→ Issue #449 背景霓虹呼吸（本 PRD — L0 背景光晕执行层）
                                                          │
        ├──► 并行: #448（HUD 区）/ #450（AUDIO 区）— constants.gd 分区合并测试
        ├──► 被复用: PLAN §3.1 后续 L0 项（底部城市光晕/暗角 ≤10%，backlog）
        └──► 被验证: workflow-chain → workflow/plan（下一阶段 plan agent）
```

---

## 7. Spike / 实验

depth/standard 下 Section 7 非必填，但存在两项真实技术不确定性（headless 下 ColorRect 渲染行为与 E2E 帧间差异断言、L0 层内渲染顺序与视觉克制），故包含 2 个轻量实验，成本各 ≤0.5 天：

### 实验 1：headless 安全 + E2E 断言影响

- **问题**：AC4 要求 headless 无错误 + run_tests 全绿；02_midgame 截图将包含呼吸背景，4 重断言（非黑/色数/主题色/帧间差异）是否仍过未知；BgPulse 色调与主题色同系是否影响色数断言
- **方法**：实现最小原型（BgPulse 节点 + 纯函数）后：headless 跑 `--quit` + run_tests.gd（断言 compute_alpha 边界：t=0 → base、t=period/4 → base+amp、t=period/2 → base，clamp 生效）；实机跑 e2e loop 截图，对比改造前后 02_midgame 的 analyze_bmp 断言输出
- **预期结果**：headless 无错误、run_tests 全绿；E2E 断言全过或仅需微调 shot 参数（settle_frames）——不得删除脉冲
- **对方案影响**：若帧间差异断言对 4s 周期正弦过敏，调 settle_frames；若色数断言对新增同系色过敏，调断言阈值（方案 A 结构不变）

### 实验 2：L0 渲染顺序 + 视觉克制实测

- **问题**：AC2 要求不影响现有场景树；BgPulse 置于 AtmosphereLayer 内 RainCurtain 之前，同层内顺序是否保证背景最底未知；峰值 alpha 0.15 在 720×1280 上的肉眼观感是否「克制可辨」而非「过亮」
- **方法**：实机截图（720×1280）叠加球/砖墙/UI 参考线，验证 BgPulse 不遮雨幕与世界；录 4s 周期对比 alpha=0.01 与 0.15 两帧亮度差
- **预期结果**：BgPulse 在所有内容之下（结构性成立）；峰值亮度差肉眼可辨但克制（≤15% 量级，同 PLAN 暗角 ≤10% 量级）
- **对方案影响**：若顺序不对 → 调子节点顺序/z-index；若过亮 → 收窄 AMP/BASE（常量级修正）；若过暗不可辨 → 微升 BASE（taste 参数，human-review 定稿）

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #449 当前 `workflow/research`，本 PRD merge 后 workflow-chain.yml 自动推进 → `workflow/plan`（squash-merge 已知 gap：若未自动推进，用 REST API 手动推进 `echo '{"labels":["workflow/plan"]}' | gh api repos/devvi/agent-game-test/issues/449/labels -X POST --input -`）
- 基线：`main` HEAD = `f6785cb`（全阶段 worktree 隔离 + 提交前 merge main）；`godot --path mini-pong/ --headless --quit` ✅ 无脚本错误（audio_engine.gd push_warning 为既有无害警告）；`run_tests.gd` 基线复跑 **2214 passed / 0 failed**（2026-08-13）
- 上游方案已确认：`docs/PLAN-rogue-pong.md` §3.1（L0 氛围层规格权威源）；GDD22（AtmosphereLayer layer=0 分层纪律）
- Obsidian 知识检索：成功（§1.6）——克制/沉浸原则已注入 §4.1/§5 设计语言
- 并行 peer：#448（T1，workflow/available）、#450（T3，workflow/research）——同改 constants.gd 不同区

### 关键决策（plan agent 必须继承）

1. **Approach A（4.1）**：`bg_pulse.gd` extends ColorRect，`static func compute_alpha(t, period, base, amplitude) -> float`（纯函数）+ `_process` 写 `color.a`；色调 `BG_PULSE_TINT`（霓虹蓝同系）；**无 shader、无第三方依赖**
2. **Approach A（4.2）**：`BgPulse` 节点挂 AtmosphereLayer（layer=0）、RainCurtain **之前**（同层最底）；全屏锚点（anchors_preset=15）；不新建 CanvasLayer
3. **常量区**：`constants.gd` 末尾新增 `# ── Background Pulse (#449) ──` 区：`BG_PULSE_PERIOD=4.0` / `BG_PULSE_BASE_ALPHA=0.08` / `BG_PULSE_AMPLITUDE=0.07` / `BG_PULSE_TINT`（PLAYER_NEON_BLUE 同系）；既有区逐字节不动
4. **文件域红线（AC5）**：实现 PR 只允许 3 文件（bg_pulse.gd + Main.tscn + constants.gd）；**不新增测试文件**（AC5 域外；纯函数已为后续测试留口）；用 worktree-commit.sh 白名单 add
5. **不改**：world_environment.tscn（test_neon 文本断言）、rain_curtain.gd/雨公式、FSM/信号链、Main.tscn 既有节点
6. **氛围层纪律**：FSM-independent（MENU/PLAYING/PAUSED 全程呼吸）；无信号依赖、无状态切换
7. **测试策略**：无新测试文件；验收 = `--headless --quit` 无错误 + run_tests.gd 全绿 + E2E 02_midgame 断言实测（Spike 1）；compute_alpha 纯函数供未来测试
8. **E2E**：02_midgame 截图含呼吸背景；断言受影响时调 shot 参数（settle_frames），不删脉冲

### 实现顺序建议（plan agent 参考）

1. `constants.gd` 新增 BG_PULSE 区 → 2. `bg_pulse.gd`（纯函数 + _process）→ 3. `Main.tscn` 挂载 BgPulse（AtmosphereLayer 首子）→ 4. headless 验证（--quit + run_tests.gd 全绿）→ 5. Spike 1（E2E 断言实测）→ 6. Spike 2（渲染顺序 + 克制观感截图）→ 7. worktree-commit.sh 白名单提交（提交前 merge main 自动合并 T1/T3 的 constants 区）→ 8. PR + CI

### 主要风险

- E2E 帧间差异断言对呼吸背景敏感（Spike 1 前置实测兜底；调 settle_frames 而非回退）
- L0 层内渲染顺序（BgPulse 需在 RainCurtain 之前；Spike 2 截图确认）
- 并行 constants.gd 合并冲突（不同区自动合并应成功；真冲突则 abort + 报告，worktree-commit.sh 预案）
- taste 数值（峰值/色调）human-review 微调（常量级修正，零代码改动）

### 交接清单

- [ ] 本 PRD 文件 `docs/PRD/449-bg-neon-breath.md`
- [ ] 上游方案 `docs/PLAN-rogue-pong.md` §3.1（L0 氛围层规格）+ §3.2（雨量公式上下文）
- [ ] 分层纪律 `docs/GAME_DESIGN/22-RAIN-CURTAIN.md`（AtmosphereLayer layer=0 架构）
- [ ] 文件域红线（AC5）与并行 peer：#448（HUD 区）/ #450（AUDIO 区）——constants.gd 分区不重叠
- [ ] 数据源 `constants.gd`（BG_COLOR 在 Rain 区 #389；新增 BG_PULSE 区）

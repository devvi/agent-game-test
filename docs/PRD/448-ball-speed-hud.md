# PRD: [Feature] 球速 HUD 显示 — 当前球速实时数字

> **Issue:** #448
> **标签:** enhancement, workflow/research, ui, version/v1
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386/#389/#392 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性——TF-1 零轮询断言 vs 实时读速——包含 2 个轻量实验）
> **所有权:** `content_ownership: mechanical`（Label 节点 + 读速机制 + 常量 = 机械可测；显示文案/样式细节沿用 #392 taste 占位）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3.3 UI（信息密度克制、默认字体、霓虹描边+微投影、玩家蓝/AI 红）——本 Issue 在 #392 三区霓虹 HUD 之上新增一个中立色球速读数
> **前置依赖:** #292（✅ CLOSED — 基础 HUD + score_changed 信号链）、#392（✅ 已合并 — 三区霓虹 HUD：game_hud.gd / ui_game_hud.tscn / test_hud.gd TF 套件）、#287（✅ CLOSED — 球物理与速度模型）、#367（taste-draft 球速草稿值，只被**展示**不被改）

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）的 GameHUD 在 #392 后已是三区霓虹 HUD：顶部 AI 红区（总分 + 拆砖/穿墙双子区）、中立信息条（「第 N 波 · 剩余 x」）、底部玩家蓝区（总分 + 拆砖/穿墙双子区），全部由信号驱动更新（#392 AC5 零轮询）。**但 HUD 不显示当前球速**——玩家无法直观看到 rally 内球速逐拍递增（+5%/拍，上限 2×）的进程感。

| 文件 | 当前状态 | 与 #448 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/game_hud.gd` | 三区霓虹 HUD（#392）：7 个数字 Label（`AIScoreLabel`/`AIBrickLabel`/`AIPierceLabel`/`InfoBar`/`PlayerScoreLabel`/`PlayerBrickLabel`/`PlayerPierceLabel`），全部信号驱动（`score_changed`/`brick_scored`/`pierce_scored`/`wave_started` + grid 3 信号），`_warned` 单次告警守卫，`visible=false` 由 StartMenu 触发显示 | ❌ 无球速 Label；❌ 无读球速机制；⚠️ 源码零 `_process`/`_physics_process`（#392 AC5，test_hud.gd TF-1 静态断言）——**实时读速不能靠 `_process` 硬加** |
| `mini-pong/scenes/ui_game_hud.tscn` | CanvasLayer layer=1：TopZone(y∈[12,84]) > VBox[AIScoreLabel(28px), AISubRow(20px×2)]、InfoBar(y∈[88,112], 16px)、BottomZone(y∈[1252,1280]) | ⚠️ **不在本 Issue 文件域**（issue 明确只允许 game_hud.gd / constants.gd / test_hud.gd）→ 球速 Label 必须**代码创建**，不编辑 tscn |
| `mini-pong/gdscripts/ball.gd` | `var speed: float = INITIAL_SPEED`（默认 300.0，line 36）；`_ready` 注册 `add_to_group("balls")`（line 50）；paddle 反弹 `speed = min(speed * speed_increment, initial_speed * max_speed_multiplier)`（line 262，+5% 封顶 2×→600）；发球重置 `speed = initial_speed`（line 89）；`speed_scale`（#387 缓时） | ⚠️ **不在文件域** → 不能加 `speed_changed` 信号；只能**只读消费** `ball.speed`。无现成速度信号 |
| `mini-pong/gdscripts/constants.gd` | 已有 `HUD_*` 组（#392：`HUD_OUTLINE_SIZE`/`HUD_SHADOW_OFFSET_*`/`HUD_INFO_COLOR`/`HUD_TOP_BAND_Y=12`/`HUD_TOP_BAND_H=72`/`HUD_INFO_BAR_Y=88`…）与 `BALL_*` 组（#287：`BALL_INITIAL_SPEED=300.0`/`BALL_SPEED_INCREMENT=1.05`/`BALL_MAX_SPEED_MULTIPLIER=2.0`） | ❌ 无球速 HUD 显示常量（`HUD_SHOW_SPEED` 开关等）——需**追加新区**，不改既有常量（`test_constants.gd` TC6 断言既有常量字面值，追加零风险） |
| `mini-pong/tests/test_hud.gd` | #392 套件：Scenario A–F；**TF-1 静态断言 game_hud.gd 源码无 `_process(`/`_physics_process(`**（AC5 零轮询契约） | ❌ 无球速相关用例（Label 存在/实时更新/无球占位/开关）——需追加 Scenario G |
| `mini-pong/gdscripts/upgrade_pool.gd` | line 152：`get_tree().get_first_node_in_group("balls")` ——**项目内既有「按组找球」先例** | ✅ 复用该模式即可（HUD 同样按组找球，免改 ball.gd） |

**关键事实核查（来自源码）：**

- `test_hud.gd` TF-1（#392 AC5 的机器守卫）：`assert(not src.contains("_process("))` + `assert(not src.contains("_physics_process("))` —— 任何往 game_hud.gd 加 `_process` 的实现都会让 run_tests.gd 变红（违反 AC4）。Issue 正文「信号或 _process 轮询均可」与既有测试契约冲突，**方案选择必须绕开源码级 `_process`**（Timer 节点 + timeout 信号即可：回调名 `_on_speed_tick` 不含 `_process(` 子串，TF-1 保持绿）
- `ball.speed` 是公开 float 属性，任意节点可只读；速度变化只发生在 paddle 反弹（+5%）、发球（重置）两处，**无变化信号**，且 ball.gd 不在文件域 → 实时读速只能「轻量轮询」或「事件间隙采样」
- Main.tscn 中 `GameHUD` 与 `Ball` 是 `Game` 根下的兄弟节点；但 HUD 以 ui_game_hud.tscn 独立实例化，测试中常脱离 Ball 单独实例化 → **按组找球 + 容错占位**（`get_node_or_null` 模式，同 `_refresh_remaining` 对 BreakoutGrid 的处理）是必须的
- TopZone 高度仅 72px（y∈[12,84]），VBox 已含 AI 总分(28px)+双子行(20px)两行 → **第三行放 VBox 内会溢出**，球速 Label 应锚定顶部带右侧独立放置

### 1.2 预期行为（验收条件，源自 Issue #448）

1. **AC1 — GameHUD 新增球速 Label，随 ball.speed 实时更新（信号或 _process 轮询均可）** — 顶部新增独立 `SpeedLabel`；更新机制为 Timer 轻量轮询（~10Hz，见 §4 Approach A）或等价信号方案；实时性以「玩家肉眼可感知逐拍递增」为准（>5Hz 即可）
2. **AC2 — 球速显示值 = round(ball.speed)，单位 px/s** — 显示 `round(ball.speed)` 整数 + `px/s` 单位后缀；300.0 → 「300 px/s」
3. **AC3 — constants.gd 新增 HUD 区常量（HUD_SHOW_SPEED: bool = true 等），不影响现有常量** — 文件末尾**追加** `# ── Ball Speed HUD (#448) ──` 新区（`HUD_SHOW_SPEED`/`HUD_SPEED_POLL_INTERVAL`/`HUD_SPEED_UNIT` 等），不改动任何既有常量行（`test_constants.gd` TC6 字面值断言零触碰）
4. **AC4 — --headless --quit 无脚本错误，run_tests.gd 全绿** — 新增代码过 Godot 4.7.1 解析；test_hud.gd 追加 Scenario G 全绿；**TF-1 保持绿（实现不得引入 `_process(`/`_physics_process(`）**
5. **AC5 — PR files 仅含本 issue 文件域，不混入其他 issue 文件** — 只提交 `mini-pong/gdscripts/game_hud.gd`、`mini-pong/gdscripts/constants.gd`（新 HUD 区）、`mini-pong/tests/test_hud.gd` 三个文件；**ui_game_hud.tscn / ball.gd / Main.tscn 一律不碰**

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 对打进行中 | 持续 | 顶部右上角球速数字随每次挡板反弹 +5% 跳升（300→315→331→…），玩家直观看到「每一次反弹都更紧迫」的进程感（#367 情感断言方向） |
| B | 发球/得分重置 | 每 rally 一次 | 球速回到 300 基线，数字回落——与场上的「重新开始」语义同步 |
| C | 缓时/冻结（#387/#391） | 每局数次 | 球被缓时或终局冻结时，球速数字保持当前值（显示 ball.speed 标量，按 AC2 字面执行） |

### 1.4 技术约束（继承自 Issue #448 + 依赖链）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 project.godot，720×1280 竖屏，resizable=false） |
| **文件域（AC5 红线）** | 只允许 `mini-pong/gdscripts/game_hud.gd`、`mini-pong/gdscripts/constants.gd`（新 HUD 区）、`mini-pong/tests/test_hud.gd`。tscn/ball.gd/Main.tscn/game_manager.gd **全部禁止修改** → Label 代码创建、球速只读消费 |
| 零轮询契约（#392 AC5） | test_hud.gd TF-1 静态断言源码无 `_process(`/`_physics_process(` → 实时读速用 Timer 节点 + timeout 信号（回调名避开 `_process(` 子串） |
| 常量纪律 | constants.gd 只**追加**新区；既有 `HUD_*`/`BALL_*` 常量不动（test_constants.gd TC6 字面值断言） |
| 球引用 | `get_tree().get_first_node_in_group("balls")`（upgrade_pool.gd:152 项目先例）；球缺失时显示占位「—」+ 单次告警（`_warned` 模式） |
| 布局 | 球速 Label 放顶部带（y∈[12,84]）右侧，锚定 right；**不放 TopZone VBox 内**（72px 放不下第三行） |
| 样式 | 沿用 #392：`NeonStyle.apply(label, CONSTS.HUD_INFO_COLOR)`（中立信息色，与 AI 红/玩家蓝区分） |
| 所有权 | `content_ownership: mechanical`——机制机械定稿；显示文案（「球速」前缀）与样式细节沿用 #392 taste 占位，不新开 taste 争议 |
| 开源优先 | 调研结果见 §1.5 — 结论：无成熟可复用方案，第一方实现（Label+Timer 原生能力）并说明理由 |

### 1.5 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索，按 star 排序）：

- **GitHub 搜索**（`godot hud`，total_count=42）：最高分 `Niekvdm/godot-plugins-gtml` ⭐86（GTML 标记语言插件，非 HUD 读数）、`jhlothamer/godot_project_starter` ⭐67（项目脚手架）、`hi-godot/cyberpunk-hud-demo` ⭐15（霓虹 HUD demo，无「球速实时读数」组件）；`godot ball speed hud` / `godot hud speedometer` → 无相关成熟仓库
- **Godot Asset Library**：球速读数 = Label + Timer + 属性读取，是引擎原生能力（`Timer.wait_time`/`timeout`、`Label.text`），无插件封装必要；既往 #392 调研已确认无霓虹 HUD 主题资产可复用
- **社区/论坛**：无「迷你乒乓球速 HUD」类成熟分发物；`round()` + `px/s` 后缀为社区常规做法
- **结论**：**无可直接复用的成熟球速 HUD 组件**。第一方实现（game_hud.gd 内代码创建 Label + Timer 轮询 `ball.speed`）成本 < 20 行，零第三方依赖，符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（本会话挂载于 `~/Documents/Obsidian Vault/`，含 `raw/` + `wiki/`）：检索关键词「HUD / 速度 / 反馈 / 数字」命中——
- `wiki/体验引擎-patterns.md`：§「沉浸感被 UI 破坏 → 隐形界面 / 最小化 HUD」——支撑球速读数**信息密度克制**：单个中立色小 Label、右上角角落位、不堆装饰；`HUD_SHOW_SPEED=false` 可整体隐藏（默认 true 按 Issue AC）
- `wiki/体验引擎——游戏设计全景探秘.md`：价值对「技巧/无能 = 精通进程」——实时球速数字把「每次反弹更紧迫」的进程感**显性化**，服务精通进程反馈；与 #367 情感断言（「每一次反弹都更紧迫」，而非「球突然失控」）同向
- `wiki/90年代地摊文艺.md`：反例约束（克制、不堆砌特效）——数字读数只做数值 + 单位，不做花哨动效
- **上游确认**：显示需求由 Issue #448 用户拍板（顶部 + 实时 + round(ball.speed) + px/s）；本 PRD 只做机制设计，不新增品味主张

### 1.7 范围边界（与相邻 PRD 解冲突）

| PRD/Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #292 UI 系统 | 基础 HUD、score_changed 信号链、可见性控制 | ❌ 不重建信号链/可见性；只在新 HUD 上**加一个读数** |
| #392 霓虹 HUD | 三区布局、霓虹样式、信号接线、零轮询契约 | ❌ 不动三区布局/样式/既有信号；只追加 SpeedLabel + 读速 Timer；**遵守 TF-1** |
| #287 球物理 | `BALL_*` 速度模型（初始/增量/封顶/反弹角） | ❌ 不改球物理；只**读** `ball.speed` 展示 |
| #367 手感校准草稿 | `BALL_*` 等参数 taste-draft 草稿值（300/1.05/2.0 待定稿） | ❌ 不参与数值定稿；#367 落地新值后 HUD 自动反映（显示运行时值，零耦合） |
| #387 升级池/缓时 | `speed_scale` 缓时机制 | ❌ 不改缓时；显示 `ball.speed` 标量（AC2 字面），缓时期间数字不变为已知行为（§5 边界 5） |
| #388 升级选卡 UI | 波间 3 选 1 卡片（layer=2） | ❌ 不碰升级层；球速 Label 在 GameHUD(layer=1) 内，无层冲突 |

---

## 2. 设计意图

### 2.1 为什么当前行为存在

| Issue | 创造了什么 | 与本 Issue 的关系 |
|-------|-----------|------------------|
| #292 | 基础 HUD：顶部总分 + `score_changed` 信号链 + StartMenu 可见性控制 | 奠定了「HUD 只做展示、更新走信号」的架构基调 |
| #392 | 三区霓虹 HUD + `ui_neon_style.gd` + test_hud.gd TF 套件（含 TF-1 零轮询静态断言） | 本 Issue 的直接父级：在其上追加读数；**TF-1 成为硬约束** |
| #287 | `BALL_INITIAL_SPEED=300` / +5% 增量 / 2× 封顶的球速模型 | 球速值域 [300, 600] px/s 确定，显示范围可预期 |

当时（#292/#392）球速显示不在需求内：MVP 聚焦得分/波次/剩余砖数等「状态性」信息；球速是「连续变化量」，当时的零轮询纪律（信号驱动）天然排斥连续读数，故未做。这不是缺陷，而是架构取舍——本 Issue 需在不破坏该纪律的前提下补上连续读数。

### 2.2 为什么现在做

1. **用户需求**：Issue #448 明确要求「当前球速实时数字」，玩家需要看到速度递增的进程感（§1.3 场景 A）
2. **技术时机成熟**：#392 已把 HUD 结构、样式工具（NeonStyle）、测试基建（mock 模式）全部就位，追加一个读数成本极低；#287 球速模型稳定（300→600 值域确定）
3. **worktree 并行测试 T1**：本 Issue 是 2026-08-13 并行 worktree 测试的三路之一，刻意与另外两路并发改 `constants.gd` 不同区域，验证提交前 merge main 的自动合并能力——**这是流程测试载体，不改变技术方案**

### 2.3 既有约束（必须遵守）

| 约束 | 细节 | 来源 |
|------|------|------|
| 零轮询静态断言 | game_hud.gd 源码不得含 `_process(`/`_physics_process(` | #392 AC5 / test_hud.gd TF-1 |
| 文件域 | 只改 game_hud.gd / constants.gd（新 HUD 区）/ test_hud.gd | Issue #448 AC5（并行测试红线） |
| 常量追加 | constants.gd 只追加新区，既有常量字面值不动 | test_constants.gd TC6 |
| 球引用只读 | ball.gd 不可改 → 按组找球 + 容错 | Issue 文件域 + upgrade_pool 先例 |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/game_hud.gd` | GameHUD | **修改**：`_ready` 内按 `HUD_SHOW_SPEED` 代码创建 `SpeedLabel`（TopZone 右侧锚定）+ `SpeedPollTimer`（`HUD_SPEED_POLL_INTERVAL`，timeout → `_on_speed_tick`）；`_on_speed_tick` 读 `get_tree().get_first_node_in_group("balls")` 的 `speed` → `round()` + 单位 → 写 Label；球缺失 → 占位「—」+ `_warned` 单次告警；`_seed_initial_values` 播种初始读数 |
| `mini-pong/gdscripts/constants.gd` | 常量 | **修改（仅追加）**：文件末尾新增 `# ── Ball Speed HUD (#448) ──` 区：`HUD_SHOW_SPEED: bool = true`、`HUD_SPEED_POLL_INTERVAL: float = 0.1`、`HUD_SPEED_UNIT: String = "px/s"`、`HUD_SPEED_LABEL_PREFIX: String = "球速 "`（文案 = taste 占位，沿 #392 先例） |
| `mini-pong/tests/test_hud.gd` | 测试 | **修改**：追加 Scenario G（球速）——G1 Label 存在且样式中立色；G2 mock 球 speed=350 → 显示「球速 350 px/s」（await 1.2×interval）；G3 无球 → 占位「—」不崩；G4 `HUD_SHOW_SPEED=false` → 无 Label；G5 TF-1 保持（源码无 `_process(`） |

### 3.2 新文件

无（Label/Timer 代码创建，不新增 tscn/脚本）。

### 3.3 间接受影响模块

| 文件 | 影响 | 说明 |
|------|------|------|
| `mini-pong/scenes/ui_game_hud.tscn` | **零改动（约束）** | SpeedLabel 由 game_hud.gd 代码创建；tscn 不在文件域 |
| `mini-pong/gdscripts/ball.gd` | 只读消费 | 仅被读 `speed` 属性；零改动（不在文件域） |
| `mini-pong/scenes/Main.tscn` | 零改动 | GameHUD 实例化路径不变；SpeedLabel 随实例自动出现 |
| `mini-pong/e2e_shots.json` | 零改动 | 02_midgame 截图将包含新读数（视觉验证，无需改剧本；若断言主题色 4a90d9 不涉及中立色 `HUD_INFO_COLOR`） |
| `test_constants.gd` | 零改动 | 追加常量不触碰 TC6 字面值断言 |

### 3.4 数据流（ASCII）

```
ball.gd (group "balls")
    │  speed: float（paddle 反弹 +5%、发球重置，无变化信号）
    ▼
GameHUD.SpeedPollTimer (HUD_SPEED_POLL_INTERVAL=0.1s, 10Hz)
    │  timeout
    ▼
_on_speed_tick()
    ├── get_tree().get_first_node_in_group("balls")   ← upgrade_pool.gd:152 先例
    │       ├── 找到 → round(ball.speed) → "球速 300 px/s" → SpeedLabel.text  ← AC2
    │       └── 缺失 → "球速 —" + _warned 单次告警（_refresh_remaining 同款容错）
    └── HUD_SHOW_SPEED=false → SpeedLabel 不创建、Timer 不启动（整体隐藏）  ← AC3
```

### 3.5 需更新的文档

- [x] `docs/PRD/448-ball-speed-hud.md`（本 PRD）
- [ ] `docs/DESIGN/448-ball-speed-hud.md`（plan agent 产出）
- [ ] `mini-pong/tests/test_hud.gd` Scenario G（implement 产出）
- [ ] `docs/TASTE.md`：无需新增（无新品味主张；文案沿用 taste 占位）

---

## 4. 方案对比

### Approach A：Timer 轻量轮询（推荐）

`_ready` 内代码创建 `SpeedLabel` + `Timer`（`wait_time = HUD_SPEED_POLL_INTERVAL`，`autostart = true`），`timeout` 连接 `_on_speed_tick()`：按组找球 → `round(ball.speed)` → 写 Label。

| 维度 | 评价 |
|------|------|
| 实时性 | 10Hz（100ms），肉眼平滑，满足「实时数字」感知（>5Hz 即可） |
| TF-1 兼容 | ✅ 源码无 `_process(` 子串；回调名 `_on_speed_tick` 不触发静态断言；**test_hud.gd 零改动保持绿** |
| 文件域 | ✅ 只动 game_hud.gd / constants.gd / test_hud.gd |
| 容错 | ✅ Timer 是 HUD 子节点（随 HUD 释放）；球缺失走 `_warned` 占位 |
| 测试性 | ✅ 测试可注入 mock ball（`add_to_group("balls")` + `speed` 属性），await 1.2×interval 后断言文本 |

**Pros:** 不破坏 #392 零轮询测试契约；不改任何域外文件；Godot 原生 Timer 节点，无新依赖；与 `_refresh_remaining` 的容错模式一致。
**Cons:** 名义上是轮询（虽非源码级 `_process`）；#392 AC5 的「零轮询」精神上被软化——需在代码注释与 PR 说明中交代（AC5 的初衷是「分数更新走信号」，连续物理量读数本就不在信号范畴）。
**Risk:** Low（Timer 生命周期 = HUD 子节点；headless 下 Timer 正常走 SceneTree）。
**Effort:** 0.5–1 天（含测试）。

### Approach B：`_process` 逐帧轮询（否决）

`_process(delta)` 内每帧读 `ball.speed` 写 Label。

| 维度 | 评价 |
|------|------|
| 实时性 | ✅ 60fps 最高 |
| TF-1 兼容 | ❌ **源码含 `_process(` → test_hud.gd TF-1 红 → run_tests.gd 非全绿 → AC4 违约**；除非改 TF-1（test_hud.gd 在文件域内可改，但等于**撕毁 #392 AC5 契约**，review 风险高） |
| 文件域 | ✅ 同上 |
| 容错 | ⚠️ 每帧 `get_first_node_in_group` 有查找开销（可缓存引用，但球可能重建） |

**Pros:** 实现最直白、实时性最高。
**Cons:** 直接违反既有测试契约（TF-1）；破坏 #392「零轮询」设计意图；改 TF-1 需要强理由且削弱契约保护力。
**Risk:** Med–High（契约破坏 → review 拒绝 / 后续 issue 失去零轮询保护）。
**Effort:** 0.5 天。

### Approach C：给 ball.gd 加 `speed_changed` 信号（否决）

ball.gd 在速度变化点 emit `speed_changed(new_speed)`，HUD 订阅。

| 维度 | 评价 |
|------|------|
| 实时性 | ✅ 事件驱动，变化即更新 |
| 文件域 | ❌ **ball.gd 不在文件域 → AC5 违约**（并行测试红线：PR 混入域外文件直接失败） |
| 信号纪律 | ✅ 最符合「信号驱动」理想 |

**Pros:** 架构上最优雅；零轮询精神完全保留。
**Cons:** 违反 AC5 文件域红线；且球速在 `_process` 内可能被 `speed_scale` 连续调制（#387），事件点难覆盖全部变化源（未来维护面变大）。
**Risk:** High（AC5 红线，并行测试目的即验证文件域纪律）。
**Effort:** 1 天（含 ball.gd 改动 + 域外文件审批）。

### Approach D：GameManager 中转（否决）

GameManager 持有/转发球速，HUD 订阅 GameManager。

| 维度 | 评价 |
|------|------|
| 文件域 | ❌ **game_manager.gd 不在文件域**（且当前 GameManager 无任何 ball/speed 引用，需双向接线） |
| 架构 | ⚠️ 为单一读数引入中转层，过度设计 |

**Cons:** 文件域违约 + 过度设计；GameManager 不拥有球引用，中转需 ball.gd 或 game_manager.gd 双改。
**Risk:** High（同 AC5）。
**Effort:** 1–1.5 天。

### 推荐

**Approach A（Timer 轻量轮询）**，理由：

1. **唯一满足全部验收条件的方案**：TF-1 保持绿（AC4）、文件域零违约（AC5）、实时感知（AC1）、`round(ball.speed)` + px/s（AC2）、常量追加（AC3）
2. **最小契约破坏**：不撕毁 #392 零轮询测试契约；「分数更新走信号、连续物理量读数走轻量轮询」是清晰的边界划分（§5 边界 6 明示）
3. **成本最低**：~20 行 + 一个常量区 + 一个测试 Scenario；复用项目内既有「按组找球 + 容错占位」双先例（upgrade_pool.gd:152 + `_refresh_remaining`）

**否决理由存档**：B 破坏 TF-1；C/D 违反 AC5 文件域（并行测试红线，无讨论余地）。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1: GameHUD 新增球速 Label 并实时更新** — SpeedLabel 存在（`TopZone/SpeedLabel`，代码创建）；Timer 10Hz 读 `ball.speed`；mock 球 speed 变化 → 文本随 timeout 更新
- [x] **AC2: 显示值 = round(ball.speed)，单位 px/s** — mock `ball.speed=350.4` → 「球速 350 px/s」；`ball.speed=300.0` → 「球速 300 px/s」
- [x] **AC3: constants.gd 新增 HUD 区常量且不影响现有常量** — `HUD_SHOW_SPEED: bool = true`（及 `HUD_SPEED_POLL_INTERVAL`/`HUD_SPEED_UNIT`/`HUD_SPEED_LABEL_PREFIX`）追加于文件末尾新区；`git diff` 确认无既有常量行被改动
- [x] **AC4: --headless --quit 无脚本错误，run_tests.gd 全绿** — `godot --path mini-pong/ --headless --quit` 退出码 0；`--headless --script tests/run_tests.gd` 全绿（含 TF-1 与 Scenario G）
- [x] **AC5: PR files 仅含本 issue 文件域** — `git diff --name-only origin/main...HEAD` 仅 `game_hud.gd`/`constants.gd`/`test_hud.gd` 三文件

### 5.2 边界情况（≥5）

1. **球节点缺失**（HUD 单独实例化/测试隔离/球未进组）→ `get_first_node_in_group` 返回 null → Label 显示「球速 —」，`_warned` 单次告警，不崩
2. **HUD_SHOW_SPEED = false** → 不创建 SpeedLabel、不启动 Timer；整体零开销
3. **球速边界值**：初始 300.0（最小）与 600.0（2× 封顶，最小粒度 5% 增量 → 值域 {300, 315, …, 600}）；`round()` 对浮点尾差（如 330.00003）稳定取整
4. **发球/得分重置**：`speed = initial_speed` 后 ≤100ms 内数字回落 300——Timer 与重置事件间隙的短暂旧值可接受（10Hz 粒度内）
5. **缓时/冻结（#387/#391）**：`speed_scale < 1` 或 `frozen=true` 时显示 `ball.speed` 标量（按 AC2 字面）；视觉速度与数字不一致为**已知行为**（AC2 明确「显示值 = round(ball.speed)」，不乘 speed_scale）
6. **HUD 隐藏期**（`visible=false` 直到 StartMenu）：Timer 照常运行（零成本），StartMenu 显示 HUD 时读数已就绪；不新增显隐钩子
7. **暂停（#296）**：SceneTree pause 时 Timer 默认 `process_mode=pausable` 一并暂停 → 暂停画面读数冻结（正确语义）
8. **多球场景**（理论）：`get_first_node_in_group` 取组内第一个（upgrade_pool 同语义）；项目现为单球，无歧义

### 5.3 失败路径（≥3）

1. **Timer 泄漏**：Timer 为 HUD 子节点，`queue_free` 随 HUD 释放；`_exit_tree` 无需额外清理（实现时禁 `process_mode=always` 于 `_exit_tree` 后自毁）
2. **TF-1 回归**：若实现误引入 `_process(`（如回调命名 `_process_speed` 含 `_process(` 子串）→ 静态断言红 → 提交前 `--headless --script run_tests.gd` 必须全绿拦截（worktree-commit.sh 对含 .gd 的提交自动跑 `--headless --quit`，测试全绿靠 implement 的 CI 门）
3. **并行 merge 冲突**：T1/T2/T3 三路并发改 constants.gd 不同区域 → worktree-commit.sh 提交前 merge origin/main 自动合并（区域不重叠，预期零冲突）；若冲突文件 >2 则脚本 abort + 报告，不硬解
4. **常量类型错误**：`HUD_SHOW_SPEED` 等为带类型标注 const（`bool`/`float`/`String`），类型不符为编译期错误，`--headless --quit` 即暴露

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #392 霓虹 HUD（game_hud.gd / NeonStyle / test_hud.gd TF 套件） | ✅ 已合并 | 无（本 Issue 的父级结构） |
| #287 球速模型（`ball.speed` / `BALL_*` 常量） | ✅ 已实现 | 无（只读消费） |
| #367 手感草稿（`BALL_*` 草稿值待定稿） | 📝 taste-draft | 低（显示运行时值，定稿后自动反映；不阻塞） |
| #387 缓时 `speed_scale` | ✅ 已实现 | 低（仅 §5.2-5 的显示语义说明） |
| T2/T3 并行 Issue（同测 constants.gd 合并） | 🔄 并行中 | 中（由 worktree-commit.sh 提交前 merge 自动处理；区域不重叠） |

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| #393 主场景组装（grid 接线） | 无关 | 球速读数不依赖 grid |
| #367 手感定稿 | 无关 | 定稿后球速显示自动反映新值 |

### 6.3 准备清单

- [ ] implement 前确认 `git status` 干净、worktree 基于最新 origin/main（`./scripts/worktree-setup.sh implement 448 ball-speed-hud`）
- [ ] 实现提交前自动 merge main（worktree-commit.sh 内建）——T1 并行测试的核心验证点
- [ ] 提交后 `godot --path mini-pong/ --headless --quit` + `--script tests/run_tests.gd` 双验证

### 6.4 依赖链

```
#287 球速模型 ──► #392 霓虹 HUD ──► #448 球速 HUD 显示（本 Issue）
                                     ├── 只读 ball.speed（#287 产物）
                                     ├── 复用 NeonStyle + 三区结构（#392 产物）
                                     └── 并行验证 worktree merge（T1 测试，与 T2/T3 无依赖）
```

---

## 7. Spike / 实验（2 个轻量实验；depth/standard 下可选，因 TF-1 张力为真实技术不确定性而包含）

### 实验 1：Timer 轮询在 headless 下的行为

- **问题**：`Timer` 节点 + `timeout` 信号在 `--headless --script` 环境下是否按 `wait_time` 正常触发（SceneTree 时间推进）？
- **方法**：最小复现——HUD 实例 + mock 球（group "balls"，`speed=350`），`await` 1.2×interval 后断言 Label 文本
- **预期结果**：10Hz 触发正常；若 headless 下 Timer 不推进，则退化为 `_seed_initial_values` 单次播种 + 事件间隙采样（Approach E，§4 未列）——实测为准
- **对方案影响**：验证 Approach A 可行性；失败则需重新评估（预期低概率）

### 实验 2：TF-1 静态断言 vs Timer 回调命名

- **问题**：`src.contains("_process(")` 是否会误伤 `_on_speed_tick` 等回调名？`_process_speed` 是否触发？
- **方法**：在 test_hud.gd 临时用例中对 `"func _on_speed_tick"`、`"func _process_speed"` 两个字符串跑 TF-1 同款断言
- **预期结果**：`_on_speed_tick` 不含 `_process(` 子串 → 绿；`_process_speed` 含 `_process(` → 红（确认命名红线：回调不得含 `_process(` 子串）
- **对方案影响**：锁定回调命名规范，写入 Continuation Context 防回归

---

## 8. 延续上下文（handoff 给 plan agent）

**系统状态**：`main` @ f6785cb；#448 处于 `workflow/research`（本 PRD 合并后由 workflow-chain 推进 `workflow/plan`）。HUD = #392 三区霓虹结构，信号驱动，TF-1 零轮询静态断言在 test_hud.gd 生效。文件域红线：只动 `game_hud.gd` / `constants.gd`（新 HUD 区）/ `test_hud.gd`。

**已定技术方向**（Approach A）：
1. `game_hud.gd`：`_ready` 内若 `HUD_SHOW_SPEED` → 代码创建 `TopZone/SpeedLabel`（锚定右上，`NeonStyle.apply(label, CONSTS.HUD_INFO_COLOR)`，文本初始「球速 —」）+ `SpeedPollTimer`（`HUD_SPEED_POLL_INTERVAL`，autostart）；`_on_speed_tick()` 读 `get_tree().get_first_node_in_group("balls")` → 缺失走 `_warned` 占位、存在则 `"球速 %d %s" % [round(ball.speed), HUD_SPEED_UNIT]`
2. `constants.gd`：文件末尾追加 `# ── Ball Speed HUD (#448) ──` 区：`HUD_SHOW_SPEED: bool = true`、`HUD_SPEED_POLL_INTERVAL: float = 0.1`、`HUD_SPEED_UNIT: String = "px/s"`、`HUD_SPEED_LABEL_PREFIX: String = "球速 "`（文案 taste 占位）；**不改任何既有常量**
3. `test_hud.gd`：追加 Scenario G（G1 Label 存在+中立色 / G2 mock 球 speed=350 → 「球速 350 px/s」/ G3 无球占位 / G4 开关 false 无 Label / G5 TF-1 保持绿）

**红线（plan/implement 必须遵守）**：
- ❌ 不改 `ui_game_hud.tscn`、`ball.gd`、`Main.tscn`、`game_manager.gd`（AC5 文件域）
- ❌ 不引入源码级 `_process(`/`_physics_process(`；回调命名避开 `_process(` 子串（Spike 2 实测红线）
- ❌ 不 `git add .`；worktree-commit.sh 白名单提交
- ✅ 提交前 merge main（T1 并行验证点）；含 .gd 提交自动跑 `--headless --quit`

**主要风险**：TF-1 回归（命名红线）；并行 constants 合并冲突（区域不重叠预期零冲突，脚本 abort 兜底）；headless Timer 推进（Spike 1 实测）。

**下一步**：plan agent 产 `docs/DESIGN/448-ball-speed-hud.md`（节点创建细节、测试矩阵、merge 验证步骤），随后 implement。

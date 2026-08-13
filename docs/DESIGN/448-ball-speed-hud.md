# DESIGN: 球速 HUD 显示 — 当前球速实时数字

> **Parent Issue:** #448
> **Agent:** game-plan-agent（operator-direct，depth/standard）
> **Date:** 2026-08-13
> **Approach:** A — Timer 轻量轮询（确认 PRD §4 推荐；否决 B 逐帧 `_process` / C ball.gd 信号 / D GameManager 中转）
> **Reference PRD:** docs/PRD/448-ball-speed-hud.md（research PR #451，已合并）
> **所有权:** `content_ownership: mechanical`（Label 节点 + 读速机制 + 常量 = 机械可测；显示文案/样式细节沿用 #392 taste 占位）
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386/#389/#392 惯例）—— 产出 DESIGN；**TASKS 跳过**（受影响文件 3、子系统 1、无迁移/替换，未达 skill 阈值：10 文件 / 5 子任务）
> **上游方案:** docs/PLAN-rogue-pong.md §3.3 UI（信息密度克制、默认字体、霓虹描边+微投影、玩家蓝/AI 红）；docs/DESIGN/392-neon-ui-upgrade.md（三区霓虹 HUD + test_hud.gd TF 套件）
> **测试仅描述，不写可运行测试代码**（implement agent 依此在 test_hud.gd 追加 Scenario G）

---

## 1. 概述

Mini Pong（`mini-pong/`，Godot 4.7.1，720×1280 竖屏）的 GameHUD 自 #392 已是三区霓虹 HUD（顶部 AI 红区 / 中立信息条 / 底部玩家蓝区），全部数字由信号驱动（`score_changed`/`brick_scored`/`pierce_scored`/`wave_started` + grid 3 信号），且 **test_hud.gd TF-1 静态断言源码不含 `_process(`/`_physics_process(`**（#392 AC5 零轮询契约）。但 HUD 不显示当前球速——玩家看不到 rally 内球速逐拍递增（+5%/拍，上限 2×→[300,600] px/s）的进程感。

本设计按 PRD 推荐 Approach A 在 **GameHUD 内代码创建** 球速读数（不改 tscn）：

1. `game_hud.gd`：`_ready` 内若 `HUD_SHOW_SPEED=true` → 代码创建 `TopZone/SpeedLabel`（锚定右上）+ `SpeedPollTimer`（`HUD_SPEED_POLL_INTERVAL=0.1s`，10Hz，autostart）；`_on_speed_tick()` 按组找球（`get_tree().get_first_node_in_group("balls")`，upgrade_pool.gd:152 先例）→ `round(ball.speed)` + 单位 → 写 Label；球缺失 → 占位「球速 —」+ `_warned` 单次告警
2. `constants.gd`：文件末尾**追加** `# ── Ball Speed HUD (#448) ──` 新区（4 个常量），不改任何既有常量行（test_constants.gd TC6 字面值断言零触碰）
3. `test_hud.gd`：追加 Scenario G（5 用例）

### 设计哲学

1. **零轮询契约不撕毁**：读速用 Timer 节点 + `timeout` 信号（Godot 原生，非源码级 `_process`）；回调命名 `_on_speed_tick` 不含 `_process(` 子串 → TF-1 静态断言保持绿（PRD Spike 2 已锁定命名红线）
2. **文件域纪律（AC5 红线）**：只改 `game_hud.gd` / `constants.gd`（新 HUD 区）/ `test_hud.gd`；`ui_game_hud.tscn`、`ball.gd`、`Main.tscn`、`game_manager.gd` 一律不碰 —— 本 Issue 是 2026-08-13 并行 worktree 测试 T1，文件域是核心验证点
3. **只读消费**：球速变化点（paddle 反弹 +5%、发球重置）都在 ball.gd，而 ball.gd 不在文件域 → 无 `speed_changed` 信号可用，只能轻量轮询 `ball.speed` 公开属性
4. **容错先例复用**：按组找球 + 缺失占位 + `_warned` 单次告警 = `_refresh_remaining` 对 BreakoutGrid 的既有模式，测试常脱离 Ball 单独实例化 HUD 时零崩溃
5. **显示语义字面执行**：显示值 = `round(ball.speed)`（不乘 `speed_scale`）——缓时/冻结期间数字保持当前标量是**已知行为**（AC2 字面，非缺陷）

### 1.1 关键事实（plan agent 已对照源码核实）

| 事实 | 核实结果 |
|------|---------|
| game_hud.gd 结构 | `extends CanvasLayer`；`@onready` 7 个 Label（TopZone VBox / InfoBar / BottomZone HBox）；`_ready` = resolve GameManager → `_apply_neon` → `_connect_signals` → `_seed_initial_values` → `visible=false`；**源码零 `_process`/`_physics_process`**（TF-1 契约） |
| 顶部布局余量 | TopZone y∈[12,84] 高 72px，VBox 已含 AI 总分(28px)+双子行(20px) 两行 → **第三行放 VBox 内会溢出**；SpeedLabel 必须锚定 TopZone 右侧独立放置 |
| 常量区现状 | `HUD_*` 组（#392）含 `HUD_TOP_BAND_Y=12`/`HUD_TOP_BAND_H=72`/`HUD_INFO_COLOR=Color(0.72,0.76,0.85)` 等；`BALL_*` 组（#287）含 `BALL_INITIAL_SPEED=300.0`/`BALL_SPEED_INCREMENT=1.05`/`BALL_MAX_SPEED_MULTIPLIER=2.0`；追加新区零风险（TC6 只断言既有字面值） |
| 找球先例 | `upgrade_pool.gd:152`：`get_tree().get_first_node_in_group("balls")` —— 项目内既有「按组找球」模式，HUD 直接复用 |
| ball.speed 语义 | 公开 float；paddle 反弹 `min(speed * speed_increment, initial_speed * max_speed_multiplier)`（+5% 封顶 2×→600）；发球重置 `= initial_speed`（300）；`speed_scale`（#387 缓时）不改变 speed 标量 |
| NeonStyle 工具 | `preload("res://gdscripts/ui_neon_style.gd")`，`apply(label, color)` 套描边+微投影；`HUD_INFO_COLOR` 为中立信息色（与 AI 红/玩家蓝区分） |
| test_hud.gd 结构 | `run()` 入口；Scenario A–F（TA2/TB3…TF）；`_wait(seconds)` = SceneTree timer await；TF-1 静态断言源码无 `_process(`/`_physics_process(`；mock 惯例：HUD 单独实例化 + 注入 mock GameManager/grid |
| 文件域 | 只允许 game_hud.gd / constants.gd / test_hud.gd 三文件（PRD AC5，并行测试红线） |

### 1.2 与 PRD 的差异决策（plan 定稿）

| PRD 断言 / 待决项 | 本设计定稿 | 理由 |
|------------------|-----------|------|
| 读速机制（PRD §4 推荐 A） | **确认 Approach A**（Timer 10Hz + timeout 信号） | 唯一满足全部 AC：TF-1 保持绿、文件域零违约、实时感知（>5Hz） |
| Label 创建方式（PRD §1.4 布局约束） | `TopZone` 下 `add_child` 代码创建，锚定 `right`（`set_anchors_preset(Control.PRESET_TOP_RIGHT)`）+ `position.x` 偏移，**不挂 VBoxContainer** | TopZone VBox 72px 放不下第三行；右侧独立锚定零布局冲突 |
| 回调命名（PRD Spike 2） | 统一 `_on_speed_tick`；**禁止** `_process_speed` 等含 `_process(` 子串命名 | TF-1 静态断言 `src.contains("_process(")` 会误伤 |
| 占位文案（PRD §8 延续上下文） | 「球速 —」（无球时）；前缀「球速 」走 `HUD_SPEED_LABEL_PREFIX` 常量 | 文案 = taste 占位（#392 先例），机制定稿；显示文案「球速」前缀为 PRD 既定 |
| 播种（PRD §5.2-6） | `_seed_initial_values` 末尾追加一次同步播种（找球读速写 Label） | HUD 显示时读数已就绪，不依赖首个 timeout（10Hz 内也够，但播种零成本） |
| `_warned` 复用 | **复用既有 `_warned` 标志**（不新增 `_speed_warned`） | 语义同为「缺依赖单次告警」；避免标志扩散 |

---

## 2. 现有组件修改

| 文件 | 改动 | 为什么 |
|------|------|--------|
| `mini-pong/gdscripts/game_hud.gd` | ① `_ready` 末尾（`_seed_initial_values` 后）调 `_setup_speed_hud()`：`if not CONSTS.HUD_SHOW_SPEED: return`；代码创建 `SpeedLabel`（Label.new，锚定 TopZone 右上，`NeonStyle.apply(label, CONSTS.HUD_INFO_COLOR)`，初始文本 `"球速 —"`，`add_child` 到 TopZone）+ `SpeedPollTimer`（`Timer.new`，`wait_time=CONSTS.HUD_SPEED_POLL_INTERVAL`，`autostart=true`，`timeout.connect(_on_speed_tick)`，`add_child` 到 self）<br>② 新增 `_on_speed_tick()`：`var ball = get_tree().get_first_node_in_group("balls")`；null → `_warn_once_speed()` + `speed_label.text = CONSTS.HUD_SPEED_LABEL_PREFIX + "—"`；否则 `speed_label.text = CONSTS.HUD_SPEED_LABEL_PREFIX + "%d %s" % [round(ball.speed), CONSTS.HUD_SPEED_UNIT]`<br>③ `_seed_initial_values` 末尾追加一次同步播种（同 ② 的读速逻辑，抽 `_refresh_speed()` 复用） | AC1（Label 存在+实时更新）/AC2（round+px/s）/AC3（常量开关）/AC4（TF-1 保持绿）；文件域内唯一允许的机制改动 |
| `mini-pong/gdscripts/constants.gd` | 文件末尾**追加** `# ── Ball Speed HUD (#448) ──` 区：<br>`const HUD_SHOW_SPEED: bool = true`<br>`const HUD_SPEED_POLL_INTERVAL: float = 0.1`<br>`const HUD_SPEED_UNIT: String = "px/s"`<br>`const HUD_SPEED_LABEL_PREFIX: String = "球速 "`（taste 占位） | AC3：追加新区，零触碰既有常量（TC6 字面值断言） |
| `mini-pong/tests/test_hud.gd` | `run()` 追加 Scenario G 调用；新增 5 用例（§4 测试矩阵） | AC4：新功能必须有测试；TF-1 保持绿是回归红线 |

> **受影响测试文件清单（implement 改造面）：** 仅 `test_hud.gd`（追加 Scenario G 5 用例）。既有 Scenario A–F 零改动；TF-1 静态断言**不得删除或放宽**。

---

## 3. 新建文件

无（Label/Timer 代码创建，不新增 tscn/脚本 —— PRD §3.2 定稿）。

---

## 4. 测试矩阵（implement 在 test_hud.gd 追加 Scenario G）

> 测试仅描述；实现者按 test_hud.gd 既有 mock 惯例（HUD 单独实例化 + 注入 mock）编写。

| ID | 场景 | 前置 | 步骤 | 断言 |
|----|------|------|------|------|
| G1 | SpeedLabel 存在 + 中立色 | HUD 实例化（mock GM） | 读 TopZone/SpeedLabel | 非 null；`modulate` 或样式色 = `HUD_INFO_COLOR`（沿用 TA2 断言方式） |
| G2 | 实时更新（AC1/AC2） | HUD + mock 球（`add_to_group("balls")`，`speed=350.4`） | `await _wait(0.05)` 后设 `ball.speed=350.4` → `await _wait(HUD_SPEED_POLL_INTERVAL*1.2)` | `SpeedLabel.text == "球速 350 px/s"`（round 生效） |
| G3 | 无球占位（容错） | HUD 单独实例化，**无** ball 节点 | `await _wait(HUD_SPEED_POLL_INTERVAL*1.2)` | 不崩；`SpeedLabel.text == "球速 —"` |
| G4 | HUD_SHOW_SPEED=false | mock 常量注入（或改常量再还原） | 实例化 HUD | `TopZone` 下无 SpeedLabel；无 Timer 子节点 |
| G5 | TF-1 保持绿（AC4 回归） | 静态断言 | 读 game_hud.gd 源码 | `not src.contains("_process(")` 且 `not src.contains("_physics_process(")`（沿用 TF-1 原文，禁止放宽） |

**边界（PRD §5.2 在测试中的体现）：** 球速边界 300.0/600.0 由 G2 的 round 断言覆盖（350.4→350）；发球重置回落（300）由实时性断言同机制覆盖（不单独用例，10Hz 粒度内）；缓时/冻结显示标量 = AC2 字面，不测（已知行为）。

---

## 5. 数据流

```
ball.gd (group "balls")
    │  speed: float（paddle 反弹 +5% → [300,600]，发球重置 300；无变化信号）
    ▼
GameHUD.SpeedPollTimer (HUD_SPEED_POLL_INTERVAL=0.1s, autostart)
    │  timeout (10Hz)
    ▼
_on_speed_tick() / _refresh_speed()（播种复用）
    ├── get_tree().get_first_node_in_group("balls")   ← upgrade_pool.gd:152 先例
    │       ├── 找到 → round(ball.speed) → "球速 %d px/s" → SpeedLabel.text   ← AC2
    │       └── 缺失 → "球速 —" + _warned 单次告警（_refresh_remaining 同款容错）
    └── HUD_SHOW_SPEED=false → _setup_speed_hud 直接 return（Label/Timer 均不创建）  ← AC3
```

---

## 6. 实现注意事项（handoff 给 implement agent）

1. **命名红线**：新增函数/回调名不得含 `_process(` 或 `_physics_process(` 子串（`_on_speed_tick` ✓，`_process_speed` ✗ —— TF-1 会红）
2. **文件域红线**：只提交 `game_hud.gd` / `constants.gd` / `test_hud.gd`；worktree-commit.sh 白名单 add；`git diff --name-only origin/main...HEAD` 仅 3 文件
3. **常量追加**：`constants.gd` 新区加在**文件末尾**；不改任何既有行（`git diff` 检查）
4. **Timer 生命周期**：`add_child` 到 HUD（self）→ 随 HUD 释放，无泄漏；**不设** `process_mode=always`（pause 时读数冻结 = 正确语义，PRD §5.2-7）
5. **验证顺序**（提交前）：`godot --path mini-pong/ --headless --quit`（无脚本错误）→ `godot --path mini-pong/ --headless --script tests/run_tests.gd`（全绿，含 TF-1 + Scenario G）
6. **PR 约定**：branch `impl/448-ball-speed-hud`，title `feat: 球速 HUD 显示 (#448)`，body `Parent #448`（无冒号）；创建后 stage-gate 自动校验

**主要风险**：TF-1 回归（命名红线，Spike 2 实测）；并行 constants 合并冲突（T1/T2/T3 区域不重叠，worktree-commit.sh 提交前 merge main 自动合并，>2 冲突文件则 abort 报告）；headless Timer 推进（PRD Spike 1，预期正常——SceneTree timer 在 headless 下照常推进，test_hud.gd 既有 `_wait` 已依赖此行为）。

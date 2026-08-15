# PRD: [Test] 玩家板加速反馈 — 连击得分时板速+20%

> **Issue:** #504
> **标签:** enhancement, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-15
> **深度:** depth/standard（Issue 无 depth 标签，按 #448/#358/#378 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性——连击时间源与 AI 得分语义——包含 2 个轻量实验）
> **所有权:** `content_ownership: mechanical`（连击窗口 2s + 速度倍率 +20% + 恢复 = 机械可测；数值按 issue 字面执行，不做手感再校准）
> **设计依据:** Obsidian 知识库设计笔记（§1.4 引用「体验引擎」系列 + 「游戏设计理念」）
> **前置依赖:** #288（✅ CLOSED — paddle.gd 玩家模式）、#290（✅ CLOSED — AI 模式，本 issue 不触碰）、#367（✅ 已合并 — PADDLE_SPEED=430.0 定稿）、#385（✅ CLOSED — 双得分制 `score_changed` 信号）、#394（✅ 已合并 — playthrough/E2E harness）

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）的玩家板（PlayerPaddle）当前**恒定速度**：`paddle.gd` 玩家模式每帧 `position.x += move * paddle_speed * delta`，`paddle_speed` 为实例级 `@export`（默认 `CONSTS.PADDLE_SPEED = 430.0`，#367 定稿）。得分只驱动记分与 HUD（#385/#392），**没有任何连击（combo）概念**，板速不随得分节奏变化。

| 文件 | 当前状态 | 与 #504 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/paddle.gd` | 单一脚本双模式（`Mode.PLAYER`/`Mode.AI`）；玩家模式读 `paddle_left`/`paddle_right` 输入 → `position.x += move * paddle_speed * delta` → clamp；`@export var paddle_speed: float = CONSTS.PADDLE_SPEED`（430.0，#387 实例化改造）；`frozen` 时 `_process` 直接 return（FSM #294） | ❌ 无连击状态；❌ 无板速倍率；❌ 不感知玩家得分事件 |
| `mini-pong/gdscripts/constants.gd` | `PADDLE_SPEED=430.0`（#367 定稿，line 49）；`test_constants.gd` TC6 断言既有常量**精确字面值** | ❌ 无连击常量（窗口/倍率）——需文件末尾**追加新区**，不改既有行 |
| `mini-pong/gdscripts/game_manager.gd` | `signal score_changed(player_score, ai_score)`（line 16，每次 `add_score` 后 emit，line 58）；`player_score` 公开 int（line 29）；`reset()` 清零（line 102） | ✅ 提供连击检测的**只读事件源**；⚠️ **不在文件域**（见 §1.4）→ 只能消费信号，不能改 |
| `mini-pong/gdscripts/scoring_manager.gd` | 事件路由：`ball.score(side)` → `GameManager.add_score(winner, amount, kind)`；拆砖分不触发 `scored` 但同样走 `score_changed` | ⚠️ 不在文件域 → 连击检测**不得**依赖 `scored`（只覆盖出界分），须用 `score_changed`（覆盖全 kind） |
| `mini-pong/tests/test_paddle.gd` | 17 用例（TC-A1~F4）：InputMap 绑定、移动/夹取、层级、实例宽度/速度 | ❌ 无连击相关用例（阈值/加成/恢复）——需追加 Scenario G |
| `mini-pong/tests/run_tests.gd` | 全量注册入口（`godot --path mini-pong/ --headless --script tests/run_tests.gd`，CI opencode-review.yml 执行）；`_run_async` 挂 e2e_playthrough.gd | ✅ 新增用例自动纳入 |
| `mini-pong/tests/e2e_playthrough.gd` / `e2e_shots.json` | #394 AI vs AI 真实物理一局（AC1-4）；#358 截图 E2E shot plan | ✅ AC2/AC3 的验证载体（不修改） |

**关键事实核查（来自源码）：**

- `paddle.gd` 是**唯一**板脚本（`player_paddle.tscn` 与 AI 板共用，Main.tscn 中 AI 板 `mode=1` 覆盖）——连击逻辑必须只作用于 `Mode.PLAYER` 分支，AI 分支零改动（issue 范围红线）
- `GameManager.score_changed(player_score, ai_score)` 对**所有**计分（boundary/brick/pierce、双方）都会 emit——连击检测需按「玩家得分」过滤：比较 `player_score` 增量或记录上次玩家分
- `scored(winner)` 信号只覆盖出界分（scoring_manager.gd 注释「拆砖分不触发」）——**不可**作为连击事件源，否则拆砖连击漏检
- 引擎时间：headless 测试无真实时钟依赖问题——`_process(delta)` 的 delta 累计即可确定性驱动（test_paddle 现有模式直接调 `_process(0.016)`）
- 无任何 `combo/连击` 符号存在于 `mini-pong/` 代码库（grep 全库零命中）——全新机制，无历史包袱

### 1.2 预期行为（验收条件，源自 Issue #504）

1. **AC1 — 速度逻辑有单元测试（连击阈值/速度加成/恢复）** — `test_paddle.gd` 追加 Scenario G：2s 窗口内玩家再次得分 → 有效速度 = `paddle_speed × (1 + 0.2)`；窗口过期 → 恢复 `paddle_speed`
2. **AC2 — 运行时 playthrough 通过（游戏可玩，无回归）** — `run_tests.gd` 全绿（含既有 17 个 paddle 用例 + e2e_playthrough #394 + auto_play #297）；`--headless --quit` 无脚本错误
3. **AC3 — 视觉 E2E 通过（截图断言真实渲染）** — CI 视觉 E2E（e2e_shots.json 截图断言）全绿，渲染无回归
4. **范围红线（issue「范围」节）** — 只改 PlayerPaddle 相关代码 + 测试；**不动 AI 板、不动雨幕**；`scoring_manager.gd`/`game_manager.gd`/`ball.gd`/`*.tscn` 只读消费或零触碰

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 连击得分 | 每局数次 | 玩家 2s 内连续得分（如穿墙 3 分后立刻拆砖 +1）→ 板速 430→516（+20%），追球更跟手，得分节奏「被物理化」 |
| B | 连击中断 | 每局数次 | 2s 窗口内无新得分（或玩家专注防守）→ 板速恢复 430，操作手感回到基线 |
| C | 单次得分 | 每局多次 | 0-1 分阶段：第一次得分不加速（「0-1 分：正常速度」字面语义） |
| D | 冻结/终局 | 每局数次 | FSM 冻结（#294）或终局（#391）期间 `_process` early-return → 连击计时不衰减、速度不生效（冻结语义优先） |

### 1.4 技术约束（继承自 Issue #504 + 依赖链）+ Obsidian 设计笔记搜索依据

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，`mini-pong/`（自有 project.godot，720×1280 竖屏） |
| **文件域（范围红线）** | 只允许 `mini-pong/gdscripts/paddle.gd`、`mini-pong/gdscripts/constants.gd`（追加新区）、`mini-pong/tests/test_paddle.gd`。AI 板（paddle.gd AI 分支）、雨幕、`scoring_manager.gd`、`game_manager.gd`、`ball.gd`、`*.tscn` **禁止修改** → 连击事件源只能**只读消费**既有 `score_changed` 信号 |
| 常量纪律 | `constants.gd` 只**追加**新区（`test_constants.gd` TC6 字面值断言零触碰，PRD #448 同款先例）；`PADDLE_SPEED=430.0` 基值不动（#367 定稿） |
| AI 隔离 | `Mode.AI` 分支零代码改动；`test_ai_paddle.gd` 不新增、不修改 |
| 数值字面执行 | `+20%`、`2s` 窗口按 issue 字面实现（`0.2` / `2.0`），不做 taste 再校准（数值所有权归 #367 taste 域，本 issue 是机械执行层） |

**Obsidian 设计笔记搜索依据（`~/Documents/Obsidian Vault/wiki/`，2026-08-15 检索）：**

| 笔记 | 关键词命中 | 设计依据 |
|------|-----------|---------|
| `体验引擎——游戏设计全景探秘.md` §1️⃣4️⃣ 驱动力 | 及时反馈 | 「创造产生心流的工作条件——明确目标、及时反馈、难度匹配」→ 连击 +20% 板速是「及时反馈」的物理化：得分瞬间玩家可感知自身操作被奖励 |
| `体验引擎-游戏设计框架.md` 情感误归因 | 反馈 | 「人无法直接感知情绪的真正来源，会自动归因于最显眼的诱因」→ 板速变快把「得分快感」转移到可见的板速变化上，强化归因 |
| `游戏设计理念.md` 多周目与重复设计 | 加速、时间游戏化 | 「加速和跳过——解构持续流动时间的工具，即让时间的流动也变得'游戏化'」→ 连击加速把 rally 节奏本身变成奖励载体，是时间维度上的游戏化 |
| `体验引擎-glossary.md` Flow（心流） | 心流、时间扭曲 | 「挑战与技巧完美匹配的完全沉浸状态。时间扭曲、内在回报」→ 连击奖励窗口（2s）制造短时心流脉冲，鼓励进攻节奏 |

> 检索方法：`grep -rli "连击\|combo\|板速\|加速反馈\|paddle" ~/Documents/Obsidian\ Vault/wiki/` 初筛 → 「体验引擎」系列与「游戏设计理念」二次命中（加速/反馈/速度关键词）→ 定位相关段落原文。vault 中无「连击/paddle」直配笔记，本 issue 属通用 game-feel 反馈机制，取心流/反馈/时间游戏化三条设计原理为据。

---

## 2. 设计意图

### 2.1 为什么现状如此

| Issue | 贡献 | 与本 issue 的关系 |
|-------|------|------------------|
| #288 | paddle.gd 玩家模式基础（InputMap 绑定 + 移动 + clamp） | 板速常量化的来源 |
| #290 | AI 模式（同脚本 `Mode.AI`） | 双模式结构约束——连击必须按模式隔离 |
| #367 | 手感校准定稿：`PADDLE_SPEED=430.0`（line 49 注释「跟手——玩家感到够得着」）；球速逐拍 +7% 且注明「远低于 20% 廉价感红线」（line 211） | 基值不可改；**20% 感知红线背景**：该红线针对球速**逐拍递增**，本 issue 的 +20% 是板速**连击奖励**（2s 窗口门控 + 结束恢复），语义不同——但方案必须保证「奖励性爆发」而非「永久提速」 |
| #385 | 双得分制：`GameManager.add_score(winner, amount, kind)` + `score_changed` 信号 | 连击事件源（全 kind 覆盖） |
| #394 | playthrough/E2E harness | AC2/AC3 验证载体 |

现状无连击 = 得分与操控反馈解耦：得分只改变数字（HUD/记分），玩家板速度恒定。`score_changed` 信号已存在但无消费方做节奏反馈。

### 2.2 为什么现在改

1. **信号基建已就绪**：`score_changed(player_score, ai_score)`（#385）为连击检测提供现成事件源，无需改记分系统（符合文件域红线）
2. **手感基值已定稿**：#367 将 `PADDLE_SPEED` 定稿 430.0，连击倍率在其上做**乘性叠加**不破坏既有测试字面量
3. **测试/E2E 基建成熟**：#394 playthrough + #358 截图 E2E 已具备，AC2/AC3 可直接挂接
4. **设计依据充分**：Obsidian 设计笔记（§1.4）支持「连击 → 板速反馈」作为心流/及时反馈的物理化机制

### 2.3 历史约束（Previous Constraints）

| 约束 | 细节 |
|------|------|
| `PADDLE_SPEED` 定稿值 | 430.0（#367 用户全采纳，constants.gd line 49）——连击倍率乘性叠加，不改基值 |
| 20% 廉价感红线（#367 line 211） | 针对球速逐拍递增的警告；本 issue 通过「2s 窗口门控 + 结束恢复」把 +20% 限定为奖励爆发 |
| 双模式单脚本 | `paddle.gd` 一个脚本管玩家+AI——连击只进 `Mode.PLAYER` 分支 |
| 零轮询偏好（#392 AC5 精神） | HUD 曾强制零 `_process`；本 issue 的 paddle 本身有 `_process`（移动必需），连击计时复用该循环属自然延伸，不新增轮询 |
| 测试字面量纪律 | `test_constants.gd` TC6 断言既有常量精确值——新增常量只能追加 |
| FSM 冻结 | `frozen` 时 `_process` early-return（#294）——冻结期连击计时不衰减、不生效 |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/paddle.gd` | PlayerPaddle | 修改：`Mode.PLAYER` 分支新增连击状态（`_combo_active`/`_combo_timer`）+ 有效速度乘算 + `score_changed` 消费（null-guard）；AI 分支零改动 |
| `mini-pong/gdscripts/constants.gd` | GameConstants | 修改：文件末尾**追加** `# ── Combo Speed Feedback (#504) ──` 新区（`COMBO_WINDOW_SECONDS=2.0`、`COMBO_SPEED_BONUS=0.2`）；既有常量行零触碰 |
| `mini-pong/tests/test_paddle.gd` | 测试 | 修改：追加 Scenario G（连击阈值/加成/恢复），沿用 `_make_paddle()` + 直接调 `_process(delta)` 模式 |

### 3.2 新增文件

无（连击逻辑全部内聚于既有 paddle.gd；不新建脚本/场景/常量文件）。

### 3.3 间接影响模块（只读消费，零修改）

| 文件 | 影响 | 性质 |
|------|------|------|
| `mini-pong/gdscripts/game_manager.gd` | `score_changed` 信号被 paddle 新增消费方（只读） | 只读消费 |
| `mini-pong/gdscripts/scoring_manager.gd` | 无改动；连击不依赖其 `scored` 信号（覆盖不全） | 无 |
| `mini-pong/gdscripts/ball.gd` | 无改动；板速变化不影响球碰撞（碰撞由碰撞体决定） | 无 |
| `mini-pong/scenes/Main.tscn` / `player_paddle.tscn` | 无改动（无导出覆盖，`@export` 默认值生效） | 无 |
| `mini-pong/tests/run_tests.gd` | 无改动（test_paddle.gd 已注册） | 无 |

### 3.4 数据流

```
GameManager.add_score(winner, amount, kind)   [#385 事件源，全 kind]
    │  score_changed.emit(player_score, ai_score)
    ▼
PlayerPaddle._on_score_changed(p, a)          [paddle.gd 新连接，PLAYER 模式 + null-guard]
    ├── 玩家得分? (p > 上次记录的 p)
    │     ├── _combo_timer > 0  → 连击延续: _combo_active = true, 刷新 _combo_timer = 2.0s
    │     └── _combo_timer == 0 → 首分: _combo_active = false, _combo_timer = 2.0s (0-1 分正常速度)
    └── AI 得分? → 不重置 _combo_timer (仅时间窗判定, 见 §5.2 边界 3)

PlayerPaddle._process(delta)                  [PLAYER 模式, 既有循环]
    ├── _combo_timer = max(0, _combo_timer - delta)
    ├── _combo_timer == 0 → _combo_active = false (连击结束 → 恢复)
    └── effective_speed = paddle_speed × (1.0 + (COMBO_SPEED_BONUS if _combo_active else 0.0))
        position.x += move × effective_speed × delta → clamp

AI 板 (同脚本 Mode.AI): _ai_process(delta) 原样 —— 连击逻辑完全隔离在 PLAYER 分支
```

### 3.5 文档更新

- [ ] `docs/GAME_DESIGN/11-PLAYER-PADDLE.md` — 追加「连击加速反馈（#504）」小节（实施 PR 时同步，本 PR 只产出 PRD）
- [ ] `docs/PRD/504-combo-speed-feedback.md`（本文件）
- [ ] `docs/TASTE.md`（若存在）— 不更新（数值按 issue 字面执行，不属 taste 校准）

---

## 4. 方案比较

### Approach A：paddle 内聚连击状态机（推荐）

**描述：** `paddle.gd` 玩家模式内维护连击状态：`_ready()`（PLAYER 模式）连接 `GameManager.score_changed`（autoload 名引用 + null-guard）；`_on_score_changed(p, a)` 按玩家得分增量判定并刷新 `_combo_timer`；`_process(delta)` 递减计时器、过期复位 `_combo_active`；移动行按 `_combo_active` 乘算 `(1 + COMBO_SPEED_BONUS)`。

| 维度 | 评估 |
|------|------|
| Pros | 零改动文件域外代码（只读消费既有信号）；事件驱动（得分即响应，无轮询）；测试可直接调 `_process(delta)` 快进时间（确定性）；AI 分支物理隔离 |
| Cons | paddle 需感知 GameManager（已有先例：`GameManager` autoload 在 paddle 测试外多处直用）；autoload 缺失需 null-guard |
| Risk | Low |
| Effort | 0.5-1 周（含测试） |

### Approach B：ScoringManager 新增 `player_scored`/`combo` 信号

**描述：** 在 `scoring_manager.gd` 增加玩家得分专用信号，paddle 订阅之。

| 维度 | 评估 |
|------|------|
| Pros | 事件语义更精确（只玩家得分）；与记分系统解耦更干净 |
| Cons | **违反文件域红线**（issue 范围明确只改 PlayerPaddle 相关代码 + 测试）；scoring_manager 需感知连击语义（职责膨胀）；`scored` 已存在但覆盖不全的教训重演 |
| Risk | Med（范围违规 → 评审/CI 白名单拒绝） |
| Effort | 0.5-1 周 |

### Approach C：`_process` 轮询 `GameManager.player_score` 差值

**描述：** paddle 每帧对比 `GameManager.player_score` 与上次值，检测玩家得分。

| 维度 | 评估 |
|------|------|
| Pros | 无信号连接，实现最朴素 |
| Cons | 轮询式检测（得分事件延迟 ≤1 帧可接受，但语义弱）；依赖公开变量而非信号契约（未来重构脆弱）；与项目「事件驱动优先」惯例（#392 AC5 零轮询精神）相悖 |
| Risk | Med |
| Effort | 0.5 周 |

### 推荐

**Approach A。** 理由：
1. 唯一满足文件域红线的方案——`score_changed` 已是现成事件源（#385），只读消费即零越界
2. 事件驱动 + 确定性测试：`_process(delta)` 直接快进 2.1s 即可断言恢复，与 test_paddle 现有模式（TC-B1~F4 直接调 `_process`）完全一致
3. AI 隔离天然成立：连击状态机只在 `Mode.PLAYER` 分支注册/生效，AI 分支代码零触碰
4. `@export` 默认值接 CONSTS（#387 先例）：`combo_window_seconds`/`combo_speed_bonus` 可编辑器调参，后续 taste 校准（#367 域）零代码改动

---

## 5. 边界条件与验收标准

### 5.1 验收条件

- [x] **AC1: 速度逻辑单元测试** — `test_paddle.gd` Scenario G 覆盖：连击阈值（2s 窗口判定）、速度加成（有效速度 = 430 × 1.2 = 516）、恢复（窗口过期 → 430）
  - G1: 首分后 `_process(1.5)` 再触发玩家得分 → `_combo_active == true`，`_process(0.016)` 移动距离 = `move × 516 × 0.016`
  - G2: 得分间隔 > 2s → `_combo_active == false`，移动距离 = `move × 430 × 0.016`
  - G3: 连击激活后 `_process(2.1)` 无新得分 → 恢复 430
  - G4: 首分（0-1 分阶段）→ 不加速
  - G5: AI 模式 paddle 永不激活连击（`mode = Mode.AI` 构造 → `_combo_active` 恒 false）
- [x] **AC2: playthrough 通过** — `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含既有 17 paddle 用例、e2e_playthrough、auto_play）；`--headless --quit` 无脚本错误
- [x] **AC3: 视觉 E2E 通过** — e2e_shots.json 截图断言全绿（CI pipeline 视觉 E2E）
- [x] **范围红线** — PR files 仅含 `paddle.gd`/`constants.gd`/`test_paddle.gd`；AI 板、雨幕、scoring_manager/game_manager/ball/tscn 零修改

### 5.2 边界情况

1. **首分不加速** — 玩家第 1 次得分（0-1 分阶段）：`_combo_timer` 从 0 起计，`_combo_active` 保持 false（issue 字面「0-1 分：正常速度」）
2. **窗口内连击延续** — 2s 内第 2/3/… 次得分：每次刷新 `_combo_timer = 2.0`，加速持续（连击不因中间 AI 得分中断，见边界 3）
3. **AI 得分不重置计时** — 连击判定仅基于「玩家得分时间窗」：AI 得分不触碰 `_combo_timer`（时间窗语义最简，符合 issue 字面；备选语义见 §7 实验 TF-2）
4. **窗口过期恢复** — `_combo_timer` 归零 → `_combo_active = false`，下一帧起恢复基速（同一 rally 内即时恢复，不等下次得分）
5. **冻结期间** — `frozen == true` 时 `_process` early-return：计时不衰减、倍率不生效；解冻后按剩余窗口继续（冻结语义优先，#294）
6. **终局/重开** — `GameManager.reset()` 清零 `player_score`；paddle 连击状态需同步复位（实现：`_on_score_changed` 检测 `p < 上次 p` 视为重开 → 复位计时器；或监听 `match_over` 只读复位）
7. **AI 模式板** — 不连接信号、不维护连击状态（`Mode.AI` 分支零改动）
8. **headless/测试上下文** — GameManager autoload 缺失或 `score_changed` 未连接 → null-guard 跳过，板以基速运行（不崩、不告警刷屏）
9. **delta 尖峰** — `_combo_timer = max(0, _combo_timer - delta)` 防负值；单帧大 delta 只可能提前结束连击，不产生负加速
10. **多 paddle 实例** — 测试场景多实例时仅 PLAYER 模式实例连接信号（每个实例独立状态，互不干扰）

### 5.3 失败路径

1. **GameManager autoload 未就绪/缺失** — `_ready` 连接前判空；连接失败 → 连击功能降级为恒基速，游戏可玩（log 单次告警，不刷屏）
2. **`score_changed` 语义变更（未来记分重构）** — 连击只依赖「玩家得分增量」这一稳定语义；若信号参数变化，paddle 内聚的判定函数是唯一修改点（隔离良好）
3. **CI 白名单拦截** — 若 worktree-commit 白名单或 stage-gate 发现文件域外文件（如误改 tscn）→ PR 拒绝；本 PR 仅 1 个 PRD 文件，无此风险
4. **测试时间源不稳定** — 若实现用 `Time.get_ticks_msec()` 真实时钟而非 `_process(delta)` 累计，headless 下断言可能抖动 → 方案 A 强制 delta 累计（确定性），TF-1 实验验证

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #288 paddle.gd 玩家模式 | ✅ CLOSED | 无 |
| #290 AI 模式（隔离基准） | ✅ CLOSED | 无 |
| #367 `PADDLE_SPEED=430.0` 定稿 | ✅ 已合并 | 低（基值不可改，倍率乘性叠加） |
| #385 `score_changed` 信号 | ✅ CLOSED | 低（信号已稳定，全 kind 覆盖） |
| #394 playthrough/E2E harness | ✅ 已合并 | 无（AC2/AC3 载体） |

```
#288 paddle 基础 → #290 AI 模式 ─┐
                                  ├─→ #504 玩家板连击加速反馈
#367 手感定稿 → #385 双得分制 ────┘
                                  └─→ #394 playthrough/E2E（验证载体）
```

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| 连击数值 taste 校准（#367 域） | P3 | 本 issue 数值字面执行；后续可经 `@export` 调参 |
| 连击视觉反馈（板发光/拖尾强化） | P3 | 本 issue 只做速度反馈；视觉层留待后续 |
| 连击音效 | P3 | 同视觉，不在本 issue 范围 |

### 6.3 准备清单

- [ ] 确认 `test_paddle.gd` Scenario G 直接调 `_process(delta)` 快进时间（现有 TC-B1 模式，无需真实等待 2s）
- [ ] 确认 paddle `_ready()` 中 PLAYER 分支新增信号连接带 null-guard（autoload 引用 `GameManager` 类名，测试中需注入或跳过）
- [ ] 确认 constants.gd 追加新区不触碰既有行（`test_constants.gd` TC6 保持绿）

---

## 7. Spike / 实验

> 深度 depth/standard：Section 7 可选。因存在真实技术不确定性，按 PRD #448 先例纳入 2 个轻量实验（实施阶段在测试中验证，非独立 spike PR）。

### TF-1：连击时间源 — `_process(delta)` 累计 vs `Time.get_ticks_msec()`

- **要回答的问题：** headless 单元测试下，哪个时间源能确定性断言「2s 阈值/恢复」？
- **方法：** 原型实现 delta 累计版（`_combo_timer -= delta`）；对照真实时钟版（`Time.get_ticks_msec()` 差值）各写 3 条断言（阈值命中/过期恢复/连续刷新）
- **预期结果：** delta 累计版确定性通过；真实时钟版在 headless 下受帧调度抖动影响断言不稳
- **对方案的影响：** 确认 Approach A 用 delta 累计（也顺带解决冻结期不衰减语义，见边界 5）

### TF-2：AI 得分是否中断连击 — 时间窗 vs 回合重置

- **要回答的问题：** 玩家得分后 AI 立即得分，连击窗口是否继续？两种语义对 AC1 测试的影响？
- **方法：** 场景模拟：t=0 玩家得分 → t=1.0 AI 得分 → t=1.5 玩家得分；断言两种语义下 `_combo_active` 与有效速度
- **预期结果：** 时间窗语义（推荐）：t=1.5 玩家得分仍在 2s 窗内 → 连击成立（AI 得分不重置）；回合重置语义：连击中断
- **对方案的影响：** 采用时间窗语义（最简、贴合 issue 字面「2 秒内连续得分」）；若用户/评审偏好回合重置，仅需在 `_on_score_changed` 加一行 AI 得分复位（改动局部化）

---

## 8. 交接上下文（Continuation Context）

### 系统状态

- `paddle.gd`：单一脚本双模式；玩家模式 `position.x += move * paddle_speed * delta`（`paddle_speed` 为 `@export`，默认 `CONSTS.PADDLE_SPEED=430.0`）；`frozen` 时 `_process` early-return；`_ready` PLAYER 分支做 InputMap 绑定 + 边界计算 + `add_to_group("paddles")`
- `constants.gd`：`PADDLE_SPEED=430.0`（line 49，#367 定稿）；追加新区安全（TC6 只断言既有行）
- `GameManager`（autoload）：`score_changed(player_score, ai_score)` 每次 `add_score` 后 emit（全 kind）；`reset()` 清零
- 测试：`test_paddle.gd` 17 用例直接调 `_process(delta)` 模式；`run_tests.gd` 全量注册；e2e_playthrough + e2e_shots 为 AC2/AC3 载体

### 实施要点（plan agent 接续）

1. **constants.gd**：文件末尾追加 `# ── Combo Speed Feedback (#504) ──`：`COMBO_WINDOW_SECONDS: float = 2.0`、`COMBO_SPEED_BONUS: float = 0.2`（追加，零触碰既有行）
2. **paddle.gd**：新增 `@export var combo_window_seconds/combo_speed_bonus`（默认 CONSTS，#387 先例）；PLAYER 分支 `_ready` 连接 `GameManager.score_changed`（null-guard）；`_on_score_changed(p, a)` 按玩家得分增量判定（`p > _last_player_score`）；`_combo_timer` 在 `_process` 递减（frozen early-return 前）；移动行乘算 `(1.0 + bonus if _combo_active)`；`_last_player_score` 检测重开复位；**AI 分支零改动**
3. **test_paddle.gd**：追加 Scenario G（G1-G5，见 §5.1）；沿用 `_make_paddle()` + 直接调 `_process(delta)`；GameManager 缺失时注入桩或跳过信号连接断言
4. **红线**：不碰 `scoring_manager.gd`/`game_manager.gd`/`ball.gd`/`*.tscn`/AI 分支/雨幕；PR files 白名单仅 3 个文件
5. **验证命令**：`godot --path mini-pong/ --headless --script tests/run_tests.gd`（全绿含既有 17 用例）；`godot --path mini-pong/ --headless --quit`（无脚本错误）；CI 视觉 E2E（e2e_shots 截图断言）
6. **数值字面执行**：+20%（0.2）与 2s（2.0）按 issue 字面，不做 taste 校准（#367 域）

### 主要风险

- **低：** `score_changed` 信号语义稳定（#385 已定）；测试用 delta 累计时间源保证确定性（TF-1 已验）
- **中：** 若实施误触 AI 分支或文件域外文件 → CI/评审拒绝；红线在 §5.1 AC 中已机器可查
- **无阻塞依赖**：前置全部 CLOSED/已合并

# PRD: [Feature] 游戏波数触发迭代 — 核心砖提前结算（特殊砖触发三选一升级）

> **所有权:** `content_ownership: mechanical` — 波次触发机制接线 + 状态机复用（架构/管线/测试 = agent 全权域）。品味子项（AI 打碎奖励策略、核心砖视觉 → #527、放置阈值常量）以 **DRAFT 常量 + 候补值** 注入 constants.gd，经 taste 队列校准（taste-ownership-domains v4：草稿达标即 merge，不等人定稿）。
> **前置依赖:** #386（✅ 波次循环 wave_started/wave_settled）、#388（✅ 升级 UI 推进接管 settle_hold/advance_settlement）、#384/#393（✅ BreakoutGrid 砖墙 + 组装）、#387（✅ 升级池/钩子）、#392（✅ HUD 剩余砖数）、#527（📝 并行 research：特殊砖视觉载体 variant 枚举，本 PRD 仅借用语义不重复设计）。
> **引擎/目录约束（继承 Issue #529）:** Godot 4.7.1，代码位于 `mini-pong/gdscripts/`，参数集中 `mini-pong/gdscripts/constants.gd`（单一事实源），测试 `mini-pong/tests/`（`godot --headless --script` 跑批）。

---

## 1. 问题定义

### 1.1 当前状态（源码事实，2026-08-17 主分支）

波次轮换的唯一触发条件是**全墙清空**，链路如下（逐行核对源码）：

```
BreakoutGrid.generate_wave(thickness, layout, seed)   # 每波开始：clear_wall() → 铺砖 → wall_generated(remaining)
   ↓ 球碰砖
brick.destroy() → grid._on_brick_destroyed()          # breakout_grid.gd:113 — 唯一递减入口
   ├── remaining_bricks -= 1                          # 计数防漂移
   ├── brick_destroyed.emit(brick, pos)               # → ScoringManager._on_brick_destroyed（last_toucher 计 1 分，kind="brick"）
   └── remaining_bricks <= 0 → wall_cleared.emit()    # breakout_grid.gd:119 — 每墙恰好一次（_wall_cleared_emitted 守卫）
WaveController._on_wall_cleared()                     # wave_controller.gd:35
   → GameManager.settle_wave() → wave_settled.emit()  # game_manager.gd:86
UpgradePickUI.open(wave_index)                        # 三选一升级窗（get_tree().paused = true 冻结游戏）
   → advance_settlement() → WaveController._advance_wave() → 下一波
```

**节奏问题（Issue 动机）**：砖块越打越少、越打越散，玩家和 AI 都越来越难命中残砖 → 波与波之间出现**长尾空窗**，游戏节奏被拉慢（"游戏节奏越来越慢"）。全清触发是**可预测的固定间隔**奖励节奏（详见 §1.6 Obsidian 佐证）。

### 1.2 预期行为（验收条件，源自 Issue #529）

砖块堆内部（被包围）埋藏 **1 颗核心砖（特殊砖）**，任一方（player/AI）打碎它 → **立即触发三选一升级**（wave settlement），无需等全墙清空。

| # | AC | 验收断言（可机器验证） |
|---|----|----------------------|
| AC1 | 核心砖被包围放置 | 厚度 ≥ `WAVE_CORE_MIN_THICKNESS` 的波：核心砖位于墙内（非边缘行），周围存在 ≥ `CORE_SURROUND_MIN` 块普通砖 |
| AC2 | 核心砖打碎 → 升级 | 核心砖 destroy → `wave_settled` 恰触发 1 次（与全清触发互斥幂等），升级窗打开 |
| AC3 | 谁打碎谁计分 | 拆砖分沿用 `ball.last_toucher`（既有机制，player/AI 均可触发，触发方 +1 分） |
| AC4 | 波 1–2 无核心砖 | 厚度 < `WAVE_CORE_MIN_THICKNESS` 时维持**全清触发**（教学节奏不变，回归既有行为） |
| AC5 | 全清兜底保留 | 核心砖存在时，若整墙先被清空（如核心砖被洞/布局隔离），全清触发仍然有效 —— 双触发源共用同一结算路径，`_settling` 守卫保证恰好一次 |
| AC6 | 剩余砖处理 | 核心砖结算后剩余砖保留在场上；升级窗期间游戏暂停；下波 `generate_wave → clear_wall()` 统一清理（零新增清理逻辑） |

### 1.3 用户场景

- **场景 A（追核心砖）**：玩家看到被围住的核心砖，选择激进打法——开洞/冲击波升级（#387 钩子）优先打穿包围层，提前拿升级，用升级反哺下一波。
- **场景 B（AI 先手）**：AI 反弹恰好打碎核心砖 → 升级窗照常弹出（玩家操作），波次提前结算。
- **场景 C（残局兜底）**：场上只剩零散砖块谁都打不中时，核心砖是**可预期的保底目标**——只要核心砖还在，节奏就不会死锁。

### 1.4 技术约束（继承 Issue #529 + 既有架构）

- Godot 4.7.1 / GDScript；`mini-pong/` 目录；常量集中 `constants.gd`。
- **不修改既有信号契约**（#384 DESIGN #414 红线）：`brick_destroyed` / `wall_cleared` / `wall_generated` 的语义与消费方（ScoringManager/WaveController/HUD）不动。
- **不修改 UpgradePickUI 内部**（#388）：推进接管（settle_hold / advance_settlement）与升级池（#387）零改动，只扩展触发源。
- 计分语义（#385）：拆砖分 = 最后触球方 +1；核心砖沿用，不引入特殊分（加分列为 taste 候补，见 §8）。
- 测试契约：`tests/run_tests.gd` 跑批 + `--headless`；波次测试以 mock BreakoutGrid（#414 契约子集）驱动（test_wave_cycle.gd 既有模式）。

### 1.5 开源优先调研结果

不涉及第三方依赖。核心砖机制为内部迭代：既有 `blast_neighbors`（#387 钩子，炸碎邻近砖）与 `open_hole`（开洞）已提供"批量毁砖"原语，本 PRD 的触发方案可与之正交组合（追核心砖 = 玩家可用冲击波/开洞升级加速拆包围层）。无需外部库。

### 1.6 Obsidian 知识检索

Vault 直接读取成功（`~/Documents/Obsidian Vault/`，含 `raw/` + `wiki/`）。检索关键词「波次 / 节奏 / 升级 / 砖块 / 难度 / 奖励 / 变强」命中：

- `wiki/体验引擎-patterns.md` §3 隐式难度选择：「让玩家的选择自然地选择难度。职业选择、策略选择、**节奏决策**」→ **核心砖 = 节奏的隐式选择器**：追核心砖 = 激进速推（早结算早升级），清砖 = 求稳刷分（拆砖分 + 墙清空成就）。玩家用打法自选节奏，而非系统强推——直接回应 Issue「节奏变慢」的解法方向
- `wiki/体验引擎-patterns.md` §14 变比率强化：「**可预测的奖励变得无聊**。在不可预测的时间间隔传递奖励」→ 现触发 = 全清（可预测固定间隔）；核心砖 = **事件驱动触发**（谁先打碎不确定）——把升级奖励从"固定节奏"变为"可变强化"，提升参与度
- `wiki/体验引擎-glossary.md`：`Implicit Difficulty（隐式难度）` / `Variable Reinforcement（可变强化）` / `Flow（心流）` / `Goldilocks Zone（金发姑娘区）` 定义锚点——核心砖同时服务：难度自适应（玩家可选快节奏）与心流维持（消除长尾空窗）
- `wiki/CUSGA 2026 游戏评选笔记.md` + `raw/Clippings/文字记录-CUSGA游戏评选作品评估-2026年7月3日.md`（附魔师）：「视觉反馈做的比较好，但是关卡内容上好像有点**节奏问题**」→ 内容节奏缺陷是评选扣分项的先例；「QLOOP（弹球游戏）：很爽快」→ 街机快节奏为正价值锚点（本游戏 = 街机/动作类，A1 校准对象 = 手感爽感）
- **Vault 缺口记录**：无「Pong/打砖块类波次触发节奏」专笔记；本 PRD 的量化约束（最小厚度 3、包围数 ≥6、双触发幂等）为项目内首创，已在本 PRD §1.2/§4 给出可复算值

### 1.7 范围边界（与相邻 PRD/Issue 解冲突）

| PRD/Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #527 特殊砖视觉（并行 research） | `brick_variant` 枚举 + 显式色映射（铁砖/奖励砖视觉载体） | ❌ 不设计视觉；核心砖的**视觉身份**跟随 #527 落地（本 PRD 的 `is_core` 标志在 #527 variant 落地后可映射为 variant 值）。#527 的"奖励砖"语义（加成）与本 PRD 的"核心砖"语义（触发）不同，实现时需区分 variant 值域 |
| #526 升级无效果（并行 research） | 升级池生效性/视觉同步 | ❌ 不碰 UpgradePool 候选/效果/视觉同步；本 PRD 只改**触发时机** |
| #386 波次循环 | wave_started/wave_settled 状态机、难度递增 | ✅ **继承**其结算路径（settle_wave → wave_settled）；不重设计状态机，仅新增一个触发源 |
| #388 升级 UI 推进接管 | settle_hold / advance_settlement、升级窗交互 | ❌ 不碰 UpgradePickUI 内部；核心砖触发 → 走同一 `wave_settled` 入口 |
| #384/#393 砖墙与组装 | BreakoutGrid 信号契约、Main.tscn 组装 | ✅ 继承 grid 内部计数/守卫；只加 core 放置与触发，不动既有信号签名 |
| #390/#429 波次转场 | 转场文案/演员冻结/分档选句 | ❌ 不触碰转场层；波次转场文案（#396 wave_failure_text.json，B1 taste-draft）语义上"第 N 道墙"可沿用（墙被核心砖提前告破亦为"告破"），不新开文案争议 |
| #392 HUD 剩余砖数 | wall_generated(remaining) 展示 | ❌ 不改 HUD；核心砖结算时 remaining>0 仅存在于升级窗期间（游戏暂停），下波 wall_generated 重置 |

---

## 2. 设计意图

### 2.1 为什么现状如此

波次推进最初设计为「清完一波墙 → 结算」的**线性教学节奏**（#386 AC1），全清触发简单、可预测、与拆砖分（#385）天然耦合。它没有预见到长尾问题：砖越少命中率越低 → 结算等待期随波次延长。

### 2.2 为什么现在改

- **节奏**：核心砖 = 保底目标，把"等残砖清完"的被动等待改为"主动追核心砖"的决策（§1.6 隐式难度选择）。
- **奖励结构**：升级从"固定间隔"（全清）变为"事件驱动"（打碎核心砖），消除可预测奖励的疲态（§1.6 变比率强化）。
- **AI 对局公平性**：AI 打碎核心砖同样推进节奏——双方共用的节奏杠杆，避免 AI 侧拖慢游戏。

### 2.3 既有约束（表）

| 约束 | 来源 | 影响 |
|------|------|------|
| 信号契约不可改 | #384 DESIGN #414 | 新增 `core_brick_destroyed` 为**追加**信号，不改既有 3 信号签名 |
| 结算恰好一次 | #386 边界 4 + grid `_wall_cleared_emitted` | 双触发源共用 `WaveController._settling` 守卫（wave_controller.gd:22），幂等 |
| 升级窗期间暂停 | #388 AC4 `get_tree().paused = true` | 剩余砖在升级窗期间静态保留，无需额外冻结逻辑 |
| 波 1–2 教学 | `WAVE_START_THICKNESS=1` + STEP=1 → 波 N 厚度 N | 厚度 1–2 行无"内部"可言 → 核心砖从厚度 ≥3 起放置（AC4） |
| 洞/缝隙布局 | grid GAPS/OFFSET/HOLES/MIXED | 核心砖放置需避开洞柱与缝隙列（§4.1 放置规则） |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 改动 | 说明 |
|------|------|------|
| `mini-pong/gdscripts/breakout_grid.gd` | **修改** | 新增 `core_brick_destroyed` 信号；generate_wave 内核心砖放置；`_on_brick_destroyed` 内 core 判定 + 一次性触发；`clear_wall` 重置 core 守卫 |
| `mini-pong/gdscripts/brick.gd` | **修改** | 新增 `@export var is_core: bool = false`（与 #527 variant 正交的低耦合标志）；destroy() 无需改（grid 侧判定） |
| `mini-pong/gdscripts/wave_controller.gd` | **修改** | `_ready` 连接 `core_brick_destroyed` → 新 `_on_core_brick_destroyed()`：与 `_on_wall_cleared` 同路径（settle_wave），`_settling` 守卫幂等 |
| `mini-pong/gdscripts/constants.gd` | **修改** | 新增 §4.4 常量块（DRAFT 标注 + 候补值注释，taste 队列可校准） |
| `mini-pong/scenes/brick.tscn` | **不改** | `is_core` 运行时由 grid 注入，场景零改动 |

### 3.2 新文件清单

| 文件 | 用途 |
|------|------|
| （无新增运行时文件） | 机制全部落在既有文件内 —— 改动面最小，符合"触发迭代"定位 |
| `mini-pong/tests/test_wave_cycle.gd`（追加场景） | 核心砖触发结算 / 双触发幂等 / 波 1–2 无 core 回归 |
| `mini-pong/tests/test_breakout_grid.gd`（追加用例） | 核心砖放置（中心/避洞/包围数）/ core destroy → 信号一次 |
| `mini-pong/tests/test_integration_393.gd`（追加用例） | 核心砖 → 升级窗打开 → advance → 下波（全链路） |

### 3.3 间接受影响模块

- **ScoringManager**（#385）：核心砖拆砖分沿用 `brick_destroyed` 既有路径，零改动；若 taste 采纳"核心砖加分"候补，则需在 `_on_brick_destroyed` 加 `brick.is_core` 分支（已列入 §8 候补，默认不做）。
- **HUD**（#392）：零改动（§1.7 说明）。
- **UpgradePickUI**（#388）：零改动（触发源扩展，消费方不变）。
- **波次转场**（#390）：零改动；`_settling` 期间转场照常（核心砖触发与全清触发在转场视角无差异）。

### 3.4 数据流影响（改造后）

```
generate_wave(thickness≥3) ──► 铺普通砖 + 中心放置 1 颗 is_core 砖 ──► wall_generated(remaining)
   │
   ├─ 路径 1（新增）: 核心砖被球打碎
   │    brick.destroy() → grid._on_brick_destroyed(brick)
   │       ├── 计分: brick_destroyed.emit → ScoringManager（last_toucher +1, kind="brick"）
   │       └── brick.is_core && !_core_triggered ──► core_brick_destroyed.emit()   ← 新增信号
   │                └─► WaveController._on_core_brick_destroyed()
   │                       └─► GameManager.settle_wave() → wave_settled.emit()（_settling 守卫）
   │
   ├─ 路径 2（既有）: remaining_bricks ≤ 0 → wall_cleared.emit() → 同上 settle_wave()
   │
   └─ 合并: UpgradePickUI.open(wave_index)（暂停）→ advance_settlement()
            → WaveController._advance_wave() → generate_wave（clear_wall 清剩余砖 + 放新核心砖）
```

### 3.5 文档更新清单

| 文档 | 更新 |
|------|------|
| `docs/PRD/529-wave-trigger-core-brick.md` | 本文件（新增） |
| `docs/DESIGN/386-wave-cycle.md`（后续 plan 阶段） | plan agent 落地时补充双触发源状态图 |
| `mini-pong/gdscripts/constants.gd` 注释 | 新增常量块附 DRAFT/taste 校准说明 |

---

## 4. 方案对比

### 4.1 Approach A — 核心砖显式触发信号（推荐）

- 描述：grid 新增 `core_brick_destroyed()` 信号；generate_wave 在厚度 ≥ `WAVE_CORE_MIN_THICKNESS` 时于墙中心放置 1 颗 `is_core` 砖（避洞避缝，§5.2 放置规则）；`_on_brick_destroyed` 中 `brick.is_core` → 一次性 emit；WaveController 新增 `_on_core_brick_destroyed()` 走既有结算路径。
- Pros：语义显式、可单测（信号即契约）；与 #384 信号追加模式一致（不动既有 3 信号）；触发与清理解耦（剩余砖由下波 clear_wall 统一处理）
- Cons：新增 1 信号 + 2 处接线；需要放置/避洞逻辑（小）
- Risk：低（完全增量，回滚 = 移除信号连接）
- Effort：S–M（0.5–1 天 + 测试）

### 4.2 Approach B — 连锁清除复用 wall_cleared

- 描述：核心砖 destroy → grid 触发 blast 逻辑销毁全部剩余砖 → `wall_cleared` 自然触发（零新信号）。
- Pros：零新信号，100% 复用既有路径；"全墙爆炸"视觉冲击强（可与 #527 L2 反馈层叠加）
- Cons：**语义污染**——`wall_cleared` 被降级为"触发砖被打碎"而非"墙真的清空"，破坏 #384 契约语义与既有测试断言（test_breakout_grid 全清用例）；剩余砖连锁销毁会批量触发 `brick_destroyed` → 拆砖分暴涨（需额外去重/封分逻辑）；与 #387 `blast_neighbors` 钩子职责重叠
- Risk：中–高（契约语义破坏 + 计分连带）
- Effort：M

### 4.3 Approach C — 双触发源（核心砖 + 全清兜底，作为 A 的补充采纳）

- 描述：A 的基础上**保留**全清触发作为兜底：核心砖被洞/缝隙隔离到无法命中的极端布局下，全清仍可推进波次（防死局）。
- Pros：鲁棒性（波次永不卡死）；对既有行为零回归（全清路径原样保留）；实现成本 ≈ A（仅多保留一段既有代码）
- Cons：两触发源需共享幂等守卫（`WaveController._settling` + grid `_core_triggered`），测试需覆盖互斥性
- Risk：低（守卫模式与 #386 边界 4 同构）
- Effort：S（在 A 之上 +0.1 天）

### 4.4 推荐组合表

| 子系统 | 推荐 | 核心文件 | Effort |
|--------|------|---------|--------|
| 触发机制 | A：显式信号 `core_brick_destroyed` | breakout_grid.gd + wave_controller.gd | S |
| 兜底 | C：全清路径保留（双触发幂等） | wave_controller.gd（`_settling` 守卫） | S |
| 核心砖标志 | `is_core` @export（与 #527 variant 正交；落地后可映射） | brick.gd | XS |
| 放置规则 | 墙中心行/列，避洞避缝，厚度 ≥3 | breakout_grid.gd generate_wave | S |
| 常量 | `WAVE_CORE_MIN_THICKNESS` 等（DRAFT） | constants.gd | XS |
| 视觉 | ❌ 不实现 —— 跟随 #527 | — | — |

组合原则：**增量 + 契约不破 + 幂等复用**；总 Effort ≈ 1–1.5 天（含测试），单 PR 可落地。

---

## 5. 边界条件与验收标准

### 5.1 验收条件（AC，见 §1.2 详细清单）

AC1–AC6 全部可机器断言（GDScript 测试，`--headless` 跑批）。

### 5.2 边界用例

| # | 用例 | 预期 |
|---|------|------|
| E1 | 核心砖与剩余砖**同帧**被毁（冲击波升级 blast_neighbors 波及） | 恰好结算 1 次（`_core_triggered` + `_settling` 双守卫）；若剩余砖清空则 wall_cleared 不发（core 已结算） |
| E2 | 厚度 1–2 波（无核心砖） | 全清触发照旧，零新信号（回归断言） |
| E3 | 核心砖所在列被 `open_hole` 升级开洞 | 放置时已避洞；若开洞升级**命中**核心砖列 → 核心砖随洞销毁？——**设计决定**：开洞只移除洞柱砖，若核心砖恰在洞柱 → 不放置核心砖到洞柱（放置规则保证），升级开洞不影响已放置核心砖（洞柱选择避让核心砖列，见 §8 交接项） |
| E4 | 核心砖打碎时一方恰达 21 分 | 走既有终局路径（#386 边界 5：升级窗跳过 → end_wave_cycle），零新接线 |
| E5 | 核心砖被 AI 打碎 | 结算照常；升级窗由玩家操作（§1.2 AC3）；AI 奖励策略 = taste 候补（§8），默认无额外 AI 增益 |
| E6 | 双触发竞态（core 与 wall_cleared 同帧） | `_settling` 守卫：仅第一次生效（#386 边界 4 同构） |

### 5.3 失败路径

| 路径 | 处理 |
|------|------|
| grid 未接线（#384 未落地场景，容错惯例） | `has_signal` 守卫跳过连接（wave_controller.gd:29 既有模式），push_warning |
| 核心砖放置失败（无合法中心格：全洞/全缝） | 跳过本波放置（不 panic），全清兜底（Approach C）保证推进 |
| 升级候选为空（#388 失败路径 1） | 既有静默跳过逻辑，本 PRD 零改动 |

---

## 6. 依赖

| 依赖 | 状态 | 说明 |
|------|------|------|
| #386 波次循环（wave_settled 挂点） | ✅ 已落地 | 结算路径复用前提 |
| #388 升级 UI（settle_hold/advance_settlement） | ✅ 已落地 | 升级窗消费方，零改动 |
| #384/#393 砖墙与组装（BreakoutGrid 契约） | ✅ 已落地 | 放置/触发落点 |
| #527 特殊砖视觉（variant 枚举） | 📝 并行 research（PR #530 已开） | **不阻塞**：本 PRD 用独立 `is_core` 标志，二者实现时在 brick.gd 上正交合并；若 #527 先落地 variant，`is_core` 可映射为 variant 值 |
| #526 升级池生效性 | 📝 并行 research（PR #528 已开） | 不阻塞：触发时机与池生效性正交 |

---

## 7. Spike / 实验

（depth/standard：可选，但为降低实现风险给出 2 项最小实验）

- **Spike 1 — 中心格避洞算法**：用真实 grid（MIXED 布局 + 固定 seed）验证"中心列被洞/缝占据时的最近合法格回退"覆盖 E3；断言：厚度 3–6 全 seed 域内核心砖必落位且包围数 ≥ `CORE_SURROUND_MIN`。失败标准：任意 seed 下核心砖落入洞柱或包围数 < 下限。
- **Spike 2 — 双触发同帧幂等**：headless mini-tree（mock grid，仿 test_wave_cycle.gd）构造"core 与 wall_cleared 同帧"场景，断言 `wave_settled` 恰 1 次。失败标准：重复触发。

---

## 8. 延续上下文（交接给 plan agent）

**任务边界**：本 PRD 只做「触发时机迭代」——核心砖放置 + 双触发源 + 幂等。**不做**：核心砖视觉（#527）、AI 打碎奖励实现（taste 候补，见下）、升级池/效果改动（#526）、波次转场文案（#396）。

**实施顺序建议**（plan 阶段可微调）：
1. `constants.gd`：新增常量块（§4.4，DRAFT 标注）：
   ```gdscript
   # ── 核心砖（#529 wave-trigger-core-brick; DRAFT — taste 可校准）──
   const WAVE_CORE_MIN_THICKNESS: int = 3    # 厚度 ≥3 才放置核心砖（波 1–2 教学）
   const CORE_SURROUND_MIN: int = 6          # 核心砖至少被 6 块普通砖包围（防御校验）
   # 候补（taste 队列候选，默认不启用）:
   # const CORE_BRICK_SCORE: int = 1         # 核心砖拆砖分（默认 = 普通砖 1 分）
   # const CORE_AI_BONUS_PADDLE_WIDTH: float = 0.15   # AI 打碎 → AI 挡板 +15% 宽（对称奖励候补）
   # const CORE_AI_BONUS_REACTION: float = 0.05       # AI 打碎 → 反应延迟 -0.05s（对称奖励候补）
   ```
2. `brick.gd`：`@export var is_core: bool = false`。
3. `breakout_grid.gd`：`core_brick_destroyed` 信号；generate_wave 放置（中心行列、避 `_is_hole_column`/`_is_gap_column`、Spike 1 回退算法）；`_on_brick_destroyed` 判定 + `_core_triggered` 一次性守卫；`clear_wall`/`generate_wave` 重置守卫。
4. `wave_controller.gd`：`has_signal` 容错连接 → `_on_core_brick_destroyed()` → 与 `_on_wall_cleared` 共用 `_settle_wave_common()`（或直接复用其体，提取公共方法）。
5. 测试（§3.2 三文件追加），跑 `./run-tests.sh`（或等价 `--headless --script` 跑批）全绿。

**taste 交接（人机共做队列）**：
- 已注入 DRAFT 候补：`WAVE_CORE_MIN_THICKNESS`、`CORE_SURROUND_MIN`、核心砖加分、AI 打碎奖励（宽/反应）——plan/implement 阶段**默认用 DRAFT 值**，不阻塞；
- 核心砖视觉身份 → #527（variant 语义冲突点：建议 #527 落地时给核心砖独立 variant 值域，如 variant=3 或复用 reward 语义需用户裁决）；
- 波次转场文案「第 N 道墙」语义（核心砖提前告破）→ #396 taste-draft 队列，本 PRD 不触碰。

**实现后验证清单**：`godot --headless` 编译通过；`run_tests.gd` 全绿（含新增 3 组用例）；`test_visual_contrast.gd` / `test_neon.gd` 等既有视觉断言不回归（核心砖视觉未落地，无新颜色断言）。

**关键源码锚点**（plan agent 直接引用）：`breakout_grid.gd:113`（_on_brick_destroyed）、`:119`（wall_cleared 触发）、`:229`（_spawn_brick）、`wave_controller.gd:29-35`（信号连接 + _on_wall_cleared）、`:22`（_settling 守卫）、`game_manager.gd:86`（settle_wave）、`upgrade_pick_ui.gd:43`（open 幂等）。

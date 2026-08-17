# PRD: [Feature] 游戏波数触发迭代 — 特殊砖触发升级 (Special-Brick Wave Trigger)

> **Issue:** #529
> **标签:** enhancement, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** depth/standard（Issue 工作深度=auto，无显式 depth 标签，按 #358/#378/#383/#384/#386/#388/#390 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 跳过并注明）
> **所有权:** `content_ownership: mechanical`（触发语义/内部位生成/信号链路为纯机械实现；特殊砖配色/光晕等视觉数值归 taste-draft，本 PRD 只定映射键）
> **知识库检索（Obsidian 笔记）:** `docs/GAME_DESIGN/`（GDD 23-UPGRADE-POOL / 24-WAVE-CYCLE / 25-UPGRADE-UI）、`docs/PLAN-rogue-pong.md`、`docs/PRD/`、`docs/DESIGN/` 交叉检索（详见 §2 知识库检索记录）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.1 核心循环（波次开始 → 生成中立砖墙 → 对打 → 砖墙打空 = 一局结束 → 结算 → 3选1升级 → 下一波）+ §v1 清单「特殊砖视觉 (铁砖/奖励砖)」（本 Issue 是特殊砖家族的第一块：**波数触发迭代**，不是视觉扩展）
> **前置依赖:** #384（砖墙系统，✅ 实现随 #393 组装落地）→ #386（波次循环 ✅ PR #428）→ #387（升级池 ✅ PR #423）→ #388（升级 UI ✅）→ #390（波次转场 ✅）→ 本 Issue。全部已合并，无阻塞

---

## 1. 问题定义 (Problem Definition)

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）的波次循环与升级链路已全部落地，但**升级/波数轮换的唯一触发条件是「整墙砖块打空」（`BreakoutGrid.wall_cleared`）**。波次尾部（剩余砖块稀疏）时，玩家与 AI 都越来越难击中剩余砖块 → 节奏拖沓，直接命中 Issue 动机「游戏节奏越来越慢」。

| 系统 | Issue | 当前状态 | 与 #529 的差距 |
|------|-------|---------|----------------|
| `mini-pong/gdscripts/breakout_grid.gd` | #384（✅ 实现随 #393 落地） | `generate_wave(thickness, layout, seed)` 生成 GAPS 布局砖墙；`_on_brick_destroyed` 单一递减入口 → `remaining_bricks==0` 时发 `wall_cleared`（整墙恰好一次）；已有 `upgrade_hooks` 注册表（#387 open_hole/blast_neighbors） | ❌ **无特殊砖概念**——所有砖同质（同一 brick.tscn / 同一 group `bricks` / 同一销毁路径）；PRD #384 §4.3 注释预留「v1 特殊砖/奖励砖入场钩子」但未落地 |
| `mini-pong/gdscripts/brick.gd` | #384 | `StaticBody2D`，`destroy()` 幂等：通知 grid + 拆砖音（#450）+ `queue_free`；无任何类型/标记字段 | ❌ 无 `is_special` 之类的类型标记；特殊砖需要区分实例 |
| `mini-pong/gdscripts/wave_controller.gd` | #386（✅ PR #428） | 唯一波次编排方：`wall_cleared` → `_on_wall_cleared`（`_settling` 守卫）→ `settle_wave()` → `wave_settled`（#388 挂点）→ `settle_hold` 等 UI 接管 / 延时自动推进 → `_advance_wave()`（`begin_wave` + 难度 + `generate_wave`） | ❌ 触发源单一（wall_cleared）；无特殊砖触发路径；`_settling`/`advance_settlement` 基础设施可直接复用 |
| `mini-pong/gdscripts/upgrade_pick_ui.gd` | #388（✅） | 消费 `GameManager.wave_settled(wave_index)` → `get_candidates(3)` → 三态状态机 → 确认 → `advance_settlement()` | ⚠️ **零改动**——只要 `wave_settled` 照常发出，UI 无感知触发源变化 |
| `mini-pong/gdscripts/scoring_manager.gd` | #385（✅ PR #424） | `_on_brick_destroyed` 用 `ball.last_toucher`（"player"/"ai"/""）给拆砖分（BRICK_SCORE=1）；发球直撞砖（无归属）不计分（边界 2 先例） | ⚠️ 归属判定机制已就绪——特殊砖触发归属可直接复用 `ball.last_toucher` |
| `mini-pong/gdscripts/game_manager.gd` | #386 | autoload：`wave_index` / `WaveState` / `wave_started` / `wave_settled` / `begin_wave` / `settle_wave` / `end_wave_cycle` / `is_run_over` | ✅ 无改动——settle 流与 21 分终局守卫全部复用 |
| `mini-pong/scenes/brick.tscn` | #384 | 单砖场景（StaticBody2D + CollisionShape2D + 视觉） | ❌ 特殊砖视觉（配色/光晕）需区分——机械键定稿，色值归 taste |
| `mini-pong/gdscripts/constants.gd` | #367/#386 | `BRICK_*` / `WAVE_*` / `UPGRADE_*` 常量组 | ❌ 无 `SPECIAL_BRICK_*` 常量组 |
| `mini-pong/tests/test_breakout_grid.gd` / `test_wave_cycle.gd` | — | 已有墙生成/波次推进/去重测试 | ❌ 无特殊砖生成与触发测试 |

### 预期行为（验收条件，源自 Issue #529）

1. **AC1 — 砖块堆内部存在一颗特殊砖** — 每波生成砖墙时，在砖块堆**内部（被包围）**位置生成恰好 1 颗特殊砖（4 正交邻域均有砖）；特殊砖视觉可辨识（机械映射键定稿，色值 taste 占位）
2. **AC2 — 谁击碎特殊砖，谁触发三选一升级** — 特殊砖被球击碎（`ball.last_toucher` 非空）→ 触发既有结算链路：`settle_wave()` → `wave_settled` → 升级 UI 弹出三选一 → 关闭后推进下一波
3. **AC3 — 波数轮换不再等待整墙打空** — 特殊砖击碎即轮换（升级窗口 + 下一波生成，剩余旧砖由 `generate_wave` 内部 `clear_wall` 清理）；不再要求 `wall_cleared`
4. **AC4 — 兼容既有整墙打空路径** — 波次厚度不足以形成内部位（厚度 < 3）时不生成特殊砖，回退 `wall_cleared` 触发（首波行为与现状一致）
5. **AC5 — 拆砖分与终局规则不变** — 特殊砖击碎仍计 1 分拆砖分给最后触球方；21 分终局判定、`_settling` 去重、`WAVE_MAX_INDEX` 防御全部沿用

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 波中触发升级（核心） | 每波一次（厚度≥3） | 球在砖堆中穿梭，击碎被包围的特殊砖 → 游戏暂停 → 三选一升级 → 确认后新墙生成、波次 +1，剩余旧砖消失——节奏不再拖到墙尾 |
| B | 薄墙回退 | 波 1-2 | 厚度 1-2 无内部位 → 无特殊砖 → 整墙打空照旧触发升级（现状不变） |
| C | AI 抢先击碎特殊砖 | 偶发 | AI 把球打回砖堆击碎特殊砖 → 窗口同样弹出、玩家三选一（设计决策，见 §4 方案 A） |
---

## 2. 设计意图 (Design Intent)

### 为什么当前行为存在

「整墙打空才轮换」是 #386 波次循环的原始契约：`PLAN-rogue-pong.md` §2.1 定义「砖墙打空 = 一局结束 → 结算 → 3选1升级 → 下一波」，#386 DESIGN 把 `wall_cleared` 定为唯一波次推进触发源，#388/#390 均在该契约上挂载。**该契约在 MVP 阶段成立**（墙薄、节奏快），但波次变厚（`WAVE_THICKNESS_STEP=1` 线性递增）后暴露尾部拖沓问题。

| Issue | 创建的约束 | 与 #529 的关系 |
|-------|-----------|---------------|
| #386（PR #428） | `wall_cleared` = 波次结算唯一触发；`_settling` 守卫；`settle_hold`/`advance_settlement` 推进接管 | ✅ 结算/推进基础设施全部复用，只**新增一个触发源** |
| #384（PR #414 DESIGN） | `generate_wave`/`clear_wall`/`brick_destroyed`/`wall_cleared` 四方法契约；砖墙布局算法 | ✅ 内部位生成是对 `generate_wave` 的**增量扩展**，不破坏契约 |
| #385（PR #424） | `ball.last_toucher` 归属判定；发球直撞无归属不计分（边界 2） | ✅ 归属机制直接复用 |
| #387（PR #423） | 升级池 60/30/10；玩家侧成长（paddle/ball/grid 惰性解析） | ✅ 升级内容零改动，只换触发时机 |

### 为什么现在改

1. **节奏问题是当前体验瓶颈**：Issue 明确「游戏节奏越来越慢」；波次越厚、尾部越难收（剩余砖稀疏 → 玩家与 AI 都难命中）→ 波间空转拉长 → 升级节奏（PLAN-rogue-pong §2.5 情绪曲线「约 5-8 次有效攻击 → 一次升级」）被稀释
2. **基础设施已就绪**：结算链路（settle_hold/advance_settlement）、归属判定（last_toucher）、升级池/UI 全部落地且稳定——只差「更早、更主动的触发源」
3. **上游方案已预留**：`PLAN-rogue-pong.md` §v1「特殊砖视觉 (铁砖/奖励砖)」+ PRD #384 §4.3「砖侧可扩展性强（后续 v1 特殊砖/奖励砖的入场钩子）」+ PRD #393「砖块硬度/特殊砖（#384 DESIGN 预留扩展）」——本 Issue 是该预留的第一落地

### 知识库检索记录（Obsidian 笔记交叉检索）

| 来源 | 命中 | 结论 |
|------|------|------|
| `docs/GAME_DESIGN/24-WAVE-CYCLE.md` | 波次状态机、`wall_cleared` 编排、双杠杆难度、21 分停止 | 触发契约唯一来源 = `wall_cleared`；#529 是**契约升级**，不是新系统 |
| `docs/GAME_DESIGN/23-UPGRADE-POOL.md` | 升级池 9 定义、60/30/10、`get_candidates`/`apply`、升级 hooks 契约 | 升级池「不自己触发流程」——触发方在波次侧；#529 换触发方不改池 |
| `docs/GAME_DESIGN/25-UPGRADE-UI.md` | `wave_settled` 挂点、三态状态机、推进接管 | UI 对触发源无感知——`wave_settled` 照常即零改动 |
| `docs/PLAN-rogue-pong.md` §2.1/§2.5/§v1 | 核心循环「砖墙打空 = 一局结束」；升级=玩家体验引擎（情感误归因）；v1「特殊砖视觉 (铁砖/奖励砖)」 | ① 打空触发是**设计稿原案**，可迭代（Issue 即迭代指令）② 升级天然归玩家侧 → 支持 §4 方案 A ③ 本 Issue 与 v1 特殊砖**家族**同源不同层（触发 vs 视觉） |
| `docs/PRD/384-breakout-grid-brick-wall.md` §4.3 | 「砖侧可扩展性强（后续 v1 特殊砖/奖励砖的入场钩子）」 | 生成侧预留确认——内部位替换式生成与预留方向一致 |
| `docs/PRD/386-wave-cycle.md` / `docs/PRD/388-upgrade-pick-ui.md` / `docs/PRD/390-wave-transition.md` | 结算链路契约、`wave_started` 消费方、「第 N 道墙」转场 | 波次转场消费 `wave_started`，与触发源无关——特殊砖触发轮换后转场照常播放（时序事实：`wave_started` 与 `generate_wave` 同帧，转场时新墙已在背后生成，#390 已接受） |
| 检索范围外（无 vault 目录） | `~/.hermes` 无独立 Obsidian vault；设计笔记 = 项目 `docs/GAME_DESIGN/`（INDEX.md 索引） | 已全量检索 |

### 范围去冲突（与既有 PRD）

| 既有 PRD | 覆盖 | 本 PRD 不重复覆盖 |
|----------|------|------------------|
| #384（砖墙系统） | 墙生成/销毁/反弹/布局 | ❌ 不改 `generate_wave` 主流程与销毁契约——只在其**末尾追加**特殊砖替换步骤 |
| #386（波次循环） | 状态机/难度/推进 | ❌ 不改 settle/advance 链路——只**新增触发入口**并共享 `_begin_settlement()` |
| #387（升级池） | 9 升级/抽取/apply | ❌ 不碰升级定义与抽取——只换触发时机 |
| #388（升级 UI） | 三选一交互 | ❌ 零改动 |
| PLAN-rogue-pong §v1 特殊砖 | 铁砖/奖励砖**视觉**扩展 | ⚠️ 本 Issue 只做**触发机制**（特殊砖 = 波数触发迭代的载体）；硬度/奖励类型/更多特殊砖视觉属 v1 后续，本 PRD 明确排除 |

---

## 3. 影响分析 (Impact Analysis)

### 直接影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/breakout_grid.gd` | BreakoutGrid | **修改（核心）**：① `generate_wave` 末尾追加 `_spawn_special_brick()`（内部位计算 + 替换式生成，仅厚度≥3 且存在内部位时）；② 新增信号 `special_brick_destroyed(breaker: String)`；③ `_on_brick_destroyed` 中识别特殊砖并 emit（breaker 取自实例注入的 `last_toucher` 快照）；④ 新增常量引用 |
| `mini-pong/gdscripts/brick.gd` | Brick | **修改（小）**：新增 `var is_special: bool = false` + `var breaker: String = ""`（销毁时由球触球方快照注入，grid 生成特殊砖时设置）；`destroy()` 无逻辑变化（grid 回调识别） |
| `mini-pong/gdscripts/wave_controller.gd` | WaveController | **修改（核心）**：① 抽取 `_on_wall_cleared` 主体为共享 `_begin_settlement()`；② 新增 `_on_special_brick_destroyed(breaker)` → 同守卫（`_settling`/`is_run_over`）→ `_begin_settlement()`；③ 新增 `@onready var ball = get_node_or_null("../Ball")`（容错，读 `last_toucher` 归属——Approach A 下仅用于记录，窗口不区分归属方） |
| `mini-pong/gdscripts/constants.gd` | 常量 | **修改（小）**：新增 `SPECIAL_BRICK_*` 组——`SPECIAL_BRICK_PER_WAVE=1`、`SPECIAL_BRICK_MIN_THICKNESS=3`、`SPECIAL_BRICK_COLOR`（taste 占位色值）、`SPECIAL_BRICK_GLOW_*`（taste 占位，映射键机械定稿） |
| `mini-pong/scenes/brick.tscn` 或 `brick_special.tscn` | 场景 | **修改/新增（小）**：视觉区分——优先同场景 + 脚本改色（`is_special` 时覆写 modulate/加 glow），避免新增场景文件（实现期定稿，plan agent 决策） |
| `mini-pong/tests/test_breakout_grid.gd` | 测试 | **修改**：内部位生成测试（厚度≥3 有特殊砖且 4 邻域砖存在 / 厚度<3 无特殊砖 / 每波恰好 1 颗 / 洞缝列不选） |
| `mini-pong/tests/test_wave_cycle.gd` | 测试 | **修改**：特殊砖击碎 → settle → 升级窗口 → advance 全链路；同帧 wall_cleared 去重；终局竞态 |
| `mini-pong/tests/test_dual_scoring.gd` | 测试 | **修改（小）**：特殊砖拆砖分 = 1 分给 last_toucher（不变式断言） |

### 新建文件

| 文件 | 内容 | 备注 |
|------|------|------|
| （无强制新建） | 若视觉无法在 brick.tscn 内区分，则新建 `scenes/brick_special.tscn` | 实现期按最小改动原则决策 |

### 间接影响模块

| 文件 | 影响 |
|------|------|
| `mini-pong/gdscripts/upgrade_pick_ui.gd` | **零改动**（`wave_settled` 照常消费）；确认后 `advance_settlement()` 推进下一波——行为与现状一致 |
| `mini-pong/gdscripts/wave_transition_controller.gd` | **零改动**（消费 `wave_started`）；特殊砖触发轮换后「第 N 道墙」转场照常播放 |
| `mini-pong/gdscripts/scoring_manager.gd` | **零改动**（`brick_destroyed` 照常计拆砖分）；特殊砖也是普通砖，走既有路径 |
| `mini-pong/gdscripts/game_manager.gd` | **零改动**（settle 流/终局守卫复用） |
| `mini-pong/gdscripts/upgrade_pool.gd` | **零改动**（`get_candidates`/`apply` 无感知） |

### 数据流影响（ASCII）

```
BreakoutGrid.generate_wave(厚度, GAPS, -1)
    ├── 常规生成 → _spawn_special_brick()   [新增: 厚度≥3 且存在内部位时替换 1 颗]
    │        └── 特殊砖: is_special=true, breaker="", 视觉区分
    │
球击碎特殊砖 (ball.last_toucher ∈ {player, ai})
    │
    ▼
brick.destroy()
    ├── grid._on_brick_destroyed(brick)        [既有: 计数/拆砖分不变]
    │     └── brick.is_special → special_brick_destroyed.emit(breaker)   [新增]
    │
    ▼
WaveController._on_special_brick_destroyed(breaker)      [新增]
    ├── guard: _settling / GameManager.is_run_over() → return   [既有守卫复用]
    ▼
_begin_settlement()                            [既有 _on_wall_cleared 主体抽取]
    ├── settle_wave() → SETTLED → wave_settled.emit(wave_index)
    │       └──► UpgradePickUI.open() → 三选一 → close() → advance_settlement()
    └── (settle_hold 等 UI 接管 / 延时自动推进 — 与现状一致)
            ▼
    _advance_wave(): begin_wave() → wave_started.emit  → [转场/雨幕/HUD 照常]
                    → generate_wave(更厚)   [内部 clear_wall → 剩余旧砖清除]
                    → _spawn_special_brick()  [下一波新特殊砖]

回退路径 (厚度<3 无内部位): wall_cleared → _on_wall_cleared → _begin_settlement()  [现状不变]
```

### 需更新的文档

- [x] `docs/PRD/529-wave-trigger-special-brick.md`（本 PRD）
- [ ] `docs/GAME_DESIGN/24-WAVE-CYCLE.md`（触发源：wall_cleared + special_brick_destroyed 双源）
- [ ] `docs/GAME_DESIGN/23-UPGRADE-POOL.md`（触发时机备注：波中特殊砖击碎，非仅墙清空）
- [ ] `docs/DESIGN/529-wave-trigger-special-brick.md`（plan 阶段产出）
- [ ] `docs/GAME_DESIGN/INDEX.md`（如新增条目）
---

## 4. 方案对比 (Solution Comparison)

### 4.1 触发归属语义（"谁击碎谁获益"）

#### 方案 A：对称触发，升级窗口归玩家（推荐）

任何一方（player/AI）击碎特殊砖 → `wave_settled` → 升级窗口弹出，**玩家三选一**；归属方仅用于记录/拆砖分（既有机制），不影响窗口归属。

**理由链：**
1. **升级池语义即玩家侧成长**（PLAN-rogue-pong §2.5「情感误归因」：升级 = 玩家体验引擎；GDD 23 明确 upgrades 作用于 paddle/ball/grid，`paddle_ref` 解析 `paddles` 组首个 = PlayerPaddle）。「谁触发」在现有架构里天然是**玩家获益**——AI 击碎特殊砖 = 玩家白得一次升级窗口，**对玩家是正反馈**（鼓励主动攻击砖堆），符合节奏修复目标
2. **实现最小**：触发链路只加信号 + 共享 settle；归属 `last_toucher` 已有
3. **与既有失败路径一致**：发球直撞（无归属）沿用 #385 边界 2 先例——不触发窗口，只碎砖

| 维度 | 评价 |
|------|------|
| Pros | 实现最小；玩家正反馈；节奏修复确定；不动升级池/UI/AI 侧 |
| Cons | AI 击碎时「谁」字面未兑现（AI 不获益）；极少数玩家可能困惑「AI 打碎的为什么是我选」 |
| Risk | **Low**（仅语义约定，机制复用成熟链路） |
| Effort | 0.5–1 周（信号 + 共享 settle + 测试） |

#### 方案 B：仅玩家触发（AI 击碎 = 普通砖）

`special_brick_destroyed` 仅在 `last_toucher == "player"` 时触发窗口；AI 击碎只计拆砖分，特殊砖对 AI 等同普通砖。

| 维度 | 评价 |
|------|------|
| Pros | 归属语义最干净（三选一只有玩家能做）；无 AI 侧改动 |
| Cons | **节奏修复打折**——AI 抢先击碎特殊砖时玩家错过一次升级机会，波次尾部拖沓仍可能发生（随机性惩罚玩家）；「谁...谁」对 AI 分支悬空 |
| Risk | Med（触发概率被 AI 分走 → 升级次数/节奏不可控） |
| Effort | 0.5 周（在方案 A 基础上加归属判断） |

#### 方案 C：对称触发 + 击碎方获益（AI 自动随机升级）

玩家击碎 → 三选一；AI 击碎 → `UpgradePool` 随机抽 1 项自动 apply 到 **AI 挡板**（AI 变强）。

| 维度 | 评价 |
|------|------|
| Pros | 最忠实字面「谁击碎谁获益」；竞争性语义完整 |
| Cons | **范围显著扩大**：① `paddle_ref` 归属解析需改造（当前 `get_first_node_in_group("paddles")` = PlayerPaddle，AI 升级需按 mode 区分或新组 `ai_paddles`）；② AI 侧升级应用（长臂=AI 挡板变宽、火球=AI 球速… 数值平衡未知）；③ 升级池设计未考虑 AI 消费方；④ 超出本 Issue「节奏修复」核心目标 |
| Risk | High（AI 升级平衡性未知；改动波及 #387 契约面） |
| Effort | 1.5–2.5 周 |

**推荐：方案 A。** 满足 Issue 核心诉求（节奏修复 + 特殊砖触发 + 三选一），与现有「升级=玩家侧」架构语义一致，实现面最小。方案 C 记入 §6 Blocks（v1 特殊砖家族扩展时评估，与 PLAN-rogue-pong §v1 铁砖/奖励砖同期）。

### 4.2 特殊砖生成与表示

#### 方案 1：替换式 + 条件生成（推荐）

`generate_wave` 完成常规砖放置后：若 `thickness ≥ SPECIAL_BRICK_MIN_THICKNESS(3)`，计算内部位（4 正交邻域均存在砖的砖位，避开洞/缝列），将其中 1 颗普通砖标记为特殊砖（`is_special=true` + 视觉覆写）。特殊砖**仍是普通砖**：占 `remaining_bricks` 计数、参与 `wall_cleared`、拆砖分不变。

| 维度 | 评价 |
|------|------|
| Pros | 计数/销毁/信号全部复用既有契约（#384 单一递减入口）；「被包围」语义由内部位判定保证；薄墙自动回退（AC4）；洞缝冲突天然规避（基于实际砖位判定） |
| Cons | 厚度 1-2 无特殊砖（回退 wall_cleared——可接受，首波本就不该提前轮换） |
| Risk | Low |
| Effort | 0.5 周（含测试） |

#### 方案 2：独立特殊砖节点（不占普通砖位）

特殊砖单独 spawn（额外砖，不计入墙砖数），击碎触发轮换但不算拆砖分/不参与 wall_cleared。

| 维度 | 评价 |
|------|------|
| Pros | 语义独立（不算墙的一部分） |
| Cons | 破坏 #384 契约面（wall_cleared 无法再覆盖特殊砖——「墙清空但特殊砖还在」状态需新语义）；计数/去重逻辑分叉；「被包围」需在布局空隙中找位，生成逻辑更复杂 |
| Risk | Med（契约分叉 → #386/#385 消费方需重审） |
| Effort | 1 周 |

**推荐：方案 1。** 增量最小、契约不变、语义清晰。

### 4.3 推荐组合

| 维度 | 选择 | 理由 |
|------|------|------|
| 触发归属 | **方案 A**（对称触发，窗口归玩家） | 升级=玩家侧语义 + 实现最小 |
| 特殊砖生成 | **方案 1**（替换式 + 厚度≥3 条件生成） | 契约不变 + 自动回退 |
| 信号设计 | `BreakoutGrid.special_brick_destroyed(breaker)` 新信号 | 与 `brick_destroyed` 正交，WaveController 单点消费 |
| 结算复用 | `_on_wall_cleared` 主体抽 `_begin_settlement()` | 双触发源共享，守卫/接管零重复 |
| 视觉 | `is_special` 时覆写颜色/光晕（常量键机械定稿，色值 taste 占位） | 沿用 #387 机械/品味分离先例 |
---

## 5. 边界条件与验收标准 (Boundary Conditions & Acceptance Criteria)

### 正常路径（AC 检查清单）

- [x] **AC1: 内部位特殊砖** — 厚度≥3 的每波：存在恰好 1 颗 `is_special` 砖；其 4 正交邻域（上/下/左/右同墙位）均为存在砖；不在洞/缝列；位置非墙边缘
- [x] **AC2: 击碎触发三选一** — `last_toucher ∈ {player, ai}` 击碎特殊砖 → `special_brick_destroyed` → `_begin_settlement` → `wave_settled` → 升级 UI 弹出（`get_candidates(3)`）→ 确认 → `advance_settlement` → 下一波
- [x] **AC3: 轮换不再等墙空** — 特殊砖击碎后：升级窗口关闭 → `begin_wave`（wave_index+1）→ `generate_wave(更厚)` 内部 `clear_wall` 清除剩余旧砖 → 新墙含新特殊砖
- [x] **AC4: 薄墙回退** — 厚度 1-2 波次无特殊砖；`wall_cleared` 照常触发（行为与现状完全一致）
- [x] **AC5: 分数与终局不变** — 特殊砖拆砖分 = 1 分给 `last_toucher`；21 分终局（`is_run_over` 守卫）优先于轮换；`WAVE_MAX_INDEX` 防御不变

### 边界情况

1. **特殊砖 = 最后一块砖（同帧 wall_cleared）** — `_on_brick_destroyed` 中特殊砖 emit 与 `wall_cleared` emit 同帧先后发生 → WaveController `_settling` 守卫去重，结算恰好一次
2. **发球直撞特殊砖（`last_toucher == ""`）** — 沿用 #385 边界 2 先例：砖碎、计墙、**不触发**升级窗口（无归属不轮换，防发球瞬间误触发）
3. **厚度 < 3 / 无内部位** — 本波不生成特殊砖，`wall_cleared` 回退（AC4）
4. **blast_neighbors / open_hole 波及特殊砖** — `destroy()` 正常走统一回调 → 视为击碎触发（升级可被升级效果连锁触发——fireball/破城锤 击碎特殊砖同样轮换，属预期）
5. **升级窗口打开期间（paused）残余信号** — `_settling` 保持 true 直到 `advance_settlement` 复位；重复 `special_brick_destroyed`/`wall_cleared` 被忽略（现状机制）
6. **21 分竞态** — 特殊砖击碎使一方到 21：`match_over` 先发 → `is_run_over()` 守卫 return → `end_wave_cycle`，不生成新墙（与 #386 边界 5 一致）
7. **特殊砖位置与洞/缝冲突** — 内部位判定基于**实际存在的砖**（生成后遍历），洞/缝列天然不产生候选，无冲突
8. **每波一致性** — `SPECIAL_BRICK_PER_WAVE=1`；生成失败（无候选）静默跳过 + 本波回退，不 push_error（容错先例）

### 失败路径

1. **grid 未接线 / 信号无消费者** — `special_brick_destroyed` 无监听 → no-op（容错模式同 #384 未接线期；`has_signal`/`has_method` 双守卫）
2. **`ball` 节点缺失** — WaveController `get_node_or_null("../Ball")` 为 null → 归属记录跳过，窗口仍触发（Approach A 下归属仅记录用途）
3. **内部位计算异常（候选为空）** — 静默跳过生成，回退 `wall_cleared`（并入边界 3/8），游戏不崩、节奏不卡死

---

## 6. 依赖与阻塞 (Dependencies & Blockers)

### 依赖（全部已合并，无阻塞）

| 依赖 | 状态 | 风险 |
|------|:----:|------|
| #384 砖墙系统（BreakoutGrid/Brick 契约） | ✅ 已落地（#393 组装） | Low |
| #386 波次循环（wave_settled/settle_hold/advance_settlement） | ✅ PR #428 | Low |
| #387 升级池（get_candidates/apply） | ✅ PR #423 | Low |
| #388 升级 UI（wave_settled 消费） | ✅ 已落地 | Low |
| #390 波次转场（wave_started 消费） | ✅ 已落地 | Low |
| #385 双得分（last_toucher 归属） | ✅ PR #424 | Low |

```
#384 → #385 → #386 → #387 → #388 → #390 → 本 Issue (#529)
                └──────────► 全部已合并，无阻塞
```

### Blocks（未来工作）

| 未来工作 | 优先级 | 备注 |
|----------|:------:|------|
| 方案 C：AI 侧升级（击碎方获益完整化） | P2 | 需 `paddle_ref` 归属解析改造 + AI 升级平衡；与 PLAN-rogue-pong §v1 特殊砖家族同期评估 |
| v1 特殊砖视觉家族（铁砖/奖励砖） | P2 | PLAN-rogue-pong §v1；本 Issue 只做触发载体 |
| 特殊砖触发反馈（HUD 提示/音效） | P3 | 本 Issue 不含；taste 域可后续独立 Issue |

### 准备清单

- [ ] plan 阶段：确认视觉区分实现方式（brick.tscn 内覆写 vs 新 brick_special.tscn）
- [ ] implement 阶段：`SPECIAL_BRICK_COLOR`/`SPECIAL_BRICK_GLOW_*` 取 taste 占位值（机械定稿键）
- [ ] 测试注册：`run_tests.gd` 无需新增套件（扩展 test_breakout_grid/test_wave_cycle/test_dual_scoring）

---

## 7. Spike / 实验 (Spike / Experiment)

**Skipped per depth/standard 惯例**（Issue 无 depth 标签，按 #358/#378/#383/#384/#386/#388/#390 先例：Section 1–6 + 8 必填，Section 7 跳过）。

研究期已执行的验证（非 spike 实验，直接证据）：
1. **契约面核对**：`wave_controller.gd` 的 `_settling`/`settle_hold`/`advance_settlement` 与 `upgrade_pick_ui.gd` 的 `wave_settled` 消费已读源码确认可复用（§1 表格）
2. **归属机制核对**：`ball.last_toucher` 写入点（paddle 碰撞）+ `scoring_manager._on_brick_destroyed` 读取点已读源码确认（§1/§4.1）
3. **内部位可行性**：`breakout_grid.gd` 生成循环（行/列/洞/缝跳过逻辑）已读——基于实际砖位遍历可计算 4 邻域内部位；GAPS 布局（每 5 列 1 缝）仍有充足内部候选列
4. **同帧竞态核对**：`_on_brick_destroyed` 单入口 → 特殊砖 emit 与 `wall_cleared` emit 同函数先后 → `_settling` 守卫去重成立（边界 1）

---

## 8. 延续上下文 (Continuation Context)

### 交接摘要（→ plan agent）

**任务：** 把波数轮换/升级触发从「整墙打空」迭代为「砖堆内部特殊砖被击碎即触发」（Issue #529），修复波次尾部节奏拖沓。

**推荐组合（§4.3）：** 方案 A（对称触发，窗口归玩家，`last_toucher` 仅记录）+ 方案 1（替换式生成，厚度≥3 条件，回退 wall_cleared）。

**核心改动清单（按实现顺序）：**

| # | 改动 | 文件 | 契约要点 |
|---|------|------|---------|
| 1 | `SPECIAL_BRICK_*` 常量组 | `constants.gd` | `PER_WAVE=1` / `MIN_THICKNESS=3` / 颜色光晕键（taste 占位） |
| 2 | `is_special` + `breaker` 字段 | `brick.gd` | 默认 false/""；grid 生成时注入 |
| 3 | `_spawn_special_brick()` + 内部位判定 + `special_brick_destroyed(breaker)` 信号 | `breakout_grid.gd` | `generate_wave` 末尾追加；4 邻域内部位；**不破坏** `generate_wave`/`clear_wall`/`brick_destroyed`/`wall_cleared` 四方法契约（#384） |
| 4 | `_begin_settlement()` 抽取 + `_on_special_brick_destroyed` | `wave_controller.gd` | 双触发源共享守卫/接管；`ball` 引用 get_node_or_null 容错 |
| 5 | 视觉区分（覆写 modulate/glow） | `brick.tscn` 或新场景 | 实现期按最小改动决策 |
| 6 | 测试扩展 | `test_breakout_grid.gd` / `test_wave_cycle.gd` / `test_dual_scoring.gd` | 内部位/触发链路/去重/终局竞态/拆砖分不变式 |

**零改动红线：** `upgrade_pick_ui.gd`、`upgrade_pool.gd`、`scoring_manager.gd`、`game_manager.gd`、`wave_transition_controller.gd`、FSM —— 全部沿用现状。

**主要风险：**
1. **归属语义（方案 A vs C）** — 已决策 A（玩家获益），plan/implement 不得擅自扩为 C（需 §6 Blocks 评估）
2. **同帧竞态** — 特殊砖=最后一块时 wall_cleared 同帧；`_settling` 守卫已覆盖，测试必须断言「恰好一次」
3. **薄墙回退** — 厚度 1-2 无特殊砖是**设计决策**（AC4），不是缺陷；测试不得要求薄墙出特殊砖
4. **节奏影响** — 轮换加速 → wave_index 增长更快 → 难度/AI 收紧更快；数值（厚度增速/升级频率）归 taste，本 Issue 只保证机制正确

**下一步（plan agent）：** 产出 `docs/DESIGN/529-wave-trigger-special-brick.md`，定稿视觉区分方式（同场景覆写 vs 新场景）与 `SPECIAL_BRICK_*` 常量取值，给出文件级修改清单与本 PRD §5 AC 的测试映射。

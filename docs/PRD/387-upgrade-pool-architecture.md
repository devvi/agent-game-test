# PRD: [Feature] 升级池架构 (UpgradePool)

> **Issue:** #387
> **标签:** enhancement, gameplay, version/mvp, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行实验补齐）
> **所有权:** `content_ownership: mechanical`（纯机械架构：升级数据模型 + 权重抽取 + 参数实例化 + hooks 预留；文案/数值设计归 #395 与 taste-draft Issue）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.5 升级池结构（60/30/10 权重 + 9 升级清单 + 情感断言，已确认 2026-08-13）
> **前置依赖:** #383（轴交换+竖屏，**已合并** PR #409）→ #384（BreakoutGrid 砖墙系统，PRD #411 + DESIGN #414 **已合并**，代码实现未落地）→ 本 Issue

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）**不存在任何升级系统**：波次循环（#386）、3 选 1 升级 UI（#388）等下游消费方已排期，但升级的数据模型、权重抽取、效果应用接口完全空白。ball/paddle 的全部手感参数仍以 `const` 常量形式固化（#295 单一事实源 constants.gd），无法被运行时修改；砖墙系统（#384）的 DESIGN 已定义 `brick_destroyed`/`wall_cleared` 信号契约，但**未预留任何升级挂钩点**。

| 文件 | 当前状态 | 与 #387 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/constants.gd` | ball/paddle 手感参数单一事实源（#295）；`BALL_*`、`PADDLE_*` 全部 `const` | ❌ AC3 要求参数实例级可修改——常量只作默认值来源 |
| `mini-pong/gdscripts/ball.gd` | 已有 `@export` 实例变量（`initial_speed`/`max_speed_multiplier`/`speed_increment` 等，编辑器可调）且 `speed` 已是实例状态；但 `INITIAL_SPEED` 等 `const` 仍被直接引用（`var speed: float = INITIAL_SPEED`） | ⚠️ 部分满足 AC3（导出变量已是实例级），需消除常量直引用 |
| `mini-pong/gdscripts/paddle.gd` | `const SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` 直接用于移动与边界计算（`position.x += move * SPEED * delta`、`PADDLE_WIDTH / 2.0`） | ❌ AC3 未满足：宽度/速度全部 const，升级（长臂 +30% 等）无法落地 |
| `mini-pong/scenes/player_paddle.tscn` | CollisionShape2D `Vector2(120,20)` 硬编码 | ⚠️ 升级改宽度时需同步改 shape（或运行时 set） |
| `mini-pong/gdscripts/` | 无 `upgrade_pool.gd` / `upgrades/` 目录 | ❌ 升级池完全不存在（AC1/AC2/AC5 全空） |
| `mini-pong/gdscripts/breakout_grid.gd` | **不存在**（#384 DESIGN #414 已合并但实现未落地；预期含 `generate_wave`/`clear_wall` + 两信号） | ❌ AC4 要求预留 `upgrade_hooks`——趁实现前在 DESIGN 契约中补挂钩点最经济 |
| `mini-pong/assets/content/upgrade_pool.json` | 不存在（#395 文案 PRD 已定义 schema `upgrade-pool-content/v1`，实现未落地） | ⚠️ 本 Issue 定义机械接口，文案数据契约已归 #395，不重复 |
| `mini-pong/tests/run_tests.gd` | 注册 14 个测试套件 | ❌ 无升级池测试 |

### 预期行为（验收条件，源自 Issue #387）

1. **AC1 — 升级池包含 9 个独立升级定义** — 每个定义含 `id`/名称/稀有度/效果回调；9 个升级 = 长臂/燃烧弹/破城锤/磁心/双生/缓时/预开洞/星尘/幻影（PLAN §2.5 确认清单）
2. **AC2 — 抽取按 60/30/10 权重返回** — 普通 60% / 稀有 30% / 传说 10%；支持不可重复或堆叠配置（每升级可配 `stackable: bool` 与 `max_stacks`）
3. **AC3 — 升级后 ball/paddle 参数是实例级** — 参数变化在下一帧生效；const 只作初始默认值
4. **AC4 — 砖墙类升级通过 BreakoutGrid `upgrade_hooks` 接入** — 预开洞等升级通过 hooks 修改砖墙生成/砖销毁行为
5. **AC5 — 提供 `get_candidates(3)` 与 `apply(upgrade_id)` 接口** — 供 #388 3 选 1 UI 调用

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 波间升级（玩家） | 每波一次 | 砖墙打空 → #386 波次循环触发 → UI 调 `get_candidates(3)` 取三张卡 → 玩家选一 → `apply(id)` 生效 |
| B | 稀有度 reveal（玩家） | 每波一次 | 3 选 1 卡片稀有度选择后 reveal（PLAN §2.5 情绪机制 2）——权重抽取保证 60/30/10 分布 |
| C | 实现期回归 | 每次改参数 | 升级后 ball/paddle 参数下一帧生效；测试断言参数实例级变更 |

### 技术约束（继承自 Issue #387 与上游）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`；竖屏 720×1280，#383 已合并） |
| 所有权 | mechanical——只做机械架构；9 升级的文案短句/命名候选归 #395（`assets/content/upgrade_pool.json`），数值手感归 taste-draft |
| 依赖契约 | #384 已定义 `brick_destroyed(brick,pos)` / `wall_cleared()` 信号（DESIGN #414 §3.4）；`upgrade_hooks` 是本 Issue 在生成/销毁链路上追加的挂钩点 |
| 消费方 | #388（3 选 1 UI，依赖 #386+#387）调用 `get_candidates(3)`/`apply()`；#386（波次循环）在波间触发升级窗口 |
| 开源优先 | Issue 上下文要求先搜 Asset Library/GitHub——调研结论见 §7 实验 1：**无可复用成熟方案，第一方实现** |

---

## 2. 设计意图

### 为什么当前行为存在

升级池是 Rogue Pong 改造（PLAN-rogue-pong.md）引入的**全新系统**，项目从经典对打 Pong（#287-#297 时代）演进而来，彼时无波次/无升级概念；手感参数以 `const` 固化的设计（#295 单一事实源）在无动态修改需求时是正确的——简单、可静态校验。砖墙系统 #384 DESIGN 定义信号契约时，#387 尚未进入研究，故未预留升级挂钩点。

| Issue/文档 | 创建现状的原因 |
|-----------|---------------|
| #295（GameConstants 单一事实源） | 收拢散落常量，当时无运行时修改需求 → 全 const 合理 |
| #287-#297（经典 Pong 组件） | 无波次/升级概念 → 无升级相关代码 |
| #384 DESIGN #414（BreakoutGrid 信号契约） | 只定义了砖墙自身的 `brick_destroyed`/`wall_cleared`，未预见升级挂钩需求 |

### 为什么现在改

1. **下游已排队**：#386 波次循环、#388 3 选 1 UI 均依赖本 Issue 的接口（`get_candidates(3)`/`apply()`）——升级池是整条波次成长链路的机械地基
2. **时机窗口**：#384 砖墙**实现尚未落地**——此时补 `upgrade_hooks` 契约只需改 DESIGN 文档与实现清单，成本最低；若等 #384 实现完成后才补，需改已合入代码
3. **PLAN 已确认**：§2.5 升级池结构（60/30/10 + 9 升级 + 情感断言）2026-08-13 用户已拍板，机械实现的前置设计决策已齐备

### 前置约束

| 约束 | 详情 |
|------|------|
| 权重表 | 普通 60% / 稀有 30% / 传说 10%（PLAN §2.5 确认，唯一权威） |
| 9 升级清单 | 长臂/燃烧弹/破城锤（普通）；磁心/双生/缓时/预开洞（稀有）；星尘/幻影（传说） |
| 文案边界 | 短句/命名/情绪断言归 #395 JSON（`upgrade-pool-content/v1`），本 Issue 不重复 |
| 信号契约 | `brick_destroyed(brick,pos)`→#385 拆砖分；`wall_cleared()`→#386 波次重置（#384 DESIGN §3.4） |
| 参数来源 | `constants.gd` 仍为默认值单一事实源；实例属性初值 = 常量，运行时可变 |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/upgrade_pool.gd`（新） | 升级池核心 | **新增**：9 升级定义 + 权重抽取 + `get_candidates(3)`/`apply(id)` |
| `mini-pong/gdscripts/upgrades/`（新目录，可选） | 升级效果回调 | **新增**：按升级拆分的回调脚本（或集中在一文件，见 §4 方案对比） |
| `mini-pong/gdscripts/paddle.gd` | 挡板 | **修改**：`SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` const → 实例属性（初值 = 常量）；移动/边界计算改用实例属性 |
| `mini-pong/gdscripts/ball.gd` | 球 | **修改**：消除 `INITIAL_SPEED` 等常量直引用，统一走实例属性（export 变量已是实例级） |
| `mini-pong/gdscripts/constants.gd` | 默认值 | **修改**：保持 const 不变（作为默认值来源），可能新增升级池权重常量组 |
| `mini-pong/scenes/player_paddle.tscn` | 挡板场景 | **修改**（或运行时 set）：CollisionShape2D 尺寸改为可运行时调整（长臂升级） |
| `mini-pong/gdscripts/breakout_grid.gd`（#384 待实现） | 砖墙 | **契约补充**：DESIGN 追加 `upgrade_hooks` 挂钩点（AC4，趁实现前） |
| `mini-pong/tests/run_tests.gd` | 测试注册 | **修改**：注册 `test_upgrade_pool.gd` |
| `mini-pong/tests/test_upgrade_pool.gd`（新） | 测试 | **新增**：权重分布/候选/apply/实例化生效用例 |

### 间接影响模块

| 文件 | 影响 |
|------|------|
| `mini-pong/gdscripts/game_manager.gd` | 无直接改动；波次状态机归 #386，升级窗口触发归 #386 |
| `mini-pong/gdscripts/scoring_manager.gd` | 无改动；拆砖分消费 `brick_destroyed`（#385），与升级池无交集 |
| `mini-pong/gdscripts/game_state_machine.gd` | 无改动；升级 UI 暂停态归 #388 |
| `docs/DESIGN/384-breakout-grid-brick-wall.md` | 追加 `upgrade_hooks` 契约小节（本 Issue 产出的契约补充） |
| `mini-pong/assets/content/upgrade_pool.json` | #395 实现时被 `apply()` 读取（文案字段），本 Issue 不创建 |

### 数据流图（升级窗口 → 应用）

```
#386 波次循环 (wall_cleared)
    │
    ▼
UpgradePool.get_candidates(3)          ← AC5 接口
    │  按 60/30/10 权重抽取 3 个不重复候选 (AC2)
    ▼
#388 3选1 UI 展示三张卡 → 玩家选择
    │
    ▼
UpgradePool.apply(upgrade_id)          ← AC5 接口
    │
    ├──► 直接数值类 (长臂/燃烧弹/缓时/星尘)
    │       └──► 改 ball/paddle 实例属性 → 下一帧 _process 生效 (AC3)
    │
    └──► 砖墙类 (预开洞/破城锤/燃烧弹-链式)
            └──► 写 BreakoutGrid.upgrade_hooks (AC4)
                  ├──► pre_wave hook：预开洞在 generate_wave 时强制开洞
                  └──► on_brick_destroyed hook：破城锤/燃烧弹链式碎邻砖
```

### 文档更新清单

- [x] `docs/PRD/387-upgrade-pool-architecture.md`（本文件）
- [ ] `docs/DESIGN/384-breakout-grid-brick-wall.md` — plan agent 补充 `upgrade_hooks` 契约小节
- [ ] `docs/PLAN-rogue-pong.md` — 无需改（§2.5 已是权威）

---

## 4. 方案对比

### Approach A：集中式数据驱动 UpgradePool（推荐）

**描述**：`upgrade_pool.gd` 单文件（class_name UpgradePool）+ 9 条升级定义 Dictionary（id → {名称, 稀有度, 权重, 回调 Callable, stackable, max_stacks}）+ 权重抽取算法。效果回调注册为 Callable（可指向 `upgrades/` 下独立脚本或同文件内函数）。`apply(id)` 按升级类型分发：数值类写 ball/paddle 实例属性；砖墙类写 BreakoutGrid hooks。

| 维度 | 内容 |
|------|------|
| 文件 | `upgrade_pool.gd`（+ 可选 `upgrades/` 回调脚本） |
| 权重算法 | `randf()` × 累计权重区间映射（60/30/10） |
| 接口 | `get_candidates(count) -> Array[Dictionary]`（去重采样）、`apply(id) -> bool`、`is_applied(id)`、`reset()` |
| 回调组织 | Callable 字段：`effect: Callable`（apply 时调用） |

**Pros**：
- 单文件核心，接口面最小，测试易写（权重分布可注入随机种子）
- Callable 天然适配"数据驱动"——升级定义即数据，回调即行为
- 与项目现有"单一事实源"风格一致（constants.gd 默认值 + 实例属性）

**Cons**：9 个回调集中在一文件会膨胀（~300 行）；需注意回调按 `upgrade_id` 分发清晰度。

**Risk**: Low — 纯新增模块，不改动核心碰撞/得分链路
**Effort**: 1-2 周（含 paddle/ball 参数实例化改造 + 测试）

### Approach B：每升级一个独立脚本 + 注册表

**描述**：`upgrades/` 目录下 9 个脚本（`long_arm.gd`/`incendiary.gd`/…），各继承 `UpgradeBase`（含 `id`/`name`/`rarity`/`weight`/`apply()` 虚方法），UpgradePool 启动时扫描注册。

| 维度 | 内容 |
|------|------|
| 文件 | `upgrades/` × 9 + `upgrade_base.gd` + `upgrade_pool.gd` |
| 权重算法 | 注册表遍历求和 + 区间映射 |
| 接口 | 同 A |
| 回调组织 | 每升级一个 `apply()` 覆写 |

**Pros**：升级间隔离清晰，未来扩升级（v1 分裂球/多球）只加文件不碰池；符合 OCP。
**Cons**：9 个文件 + 基类对 MVP 偏重；Godot 无反射扫描，需手动注册表（List），仪式感大于收益。

**Risk**: Low-Med — 文件多但无架构风险
**Effort**: 1.5-2.5 周

### Approach C：纯 JSON 数据 + 通用解释器

**描述**：升级定义全放 JSON（含效果参数），UpgradePool 用通用解释器逐字段应用。

| 维度 | 内容 |
|------|------|
| 文件 | `assets/content/upgrade_defs.json` + `upgrade_pool.gd` |
| 权重算法 | 同 A |
| 回调组织 | JSON 字段 → 解释器分支（`effect_type: "paddle_width_mult"` 等） |

**Pros**：数据与代码彻底分离；与 #395 文案 JSON 同构。
**Cons**：Godot 无运行时反射，解释器需手写全效果分支——**等于把 Approach A 的回调拆成 if-elif 链**，可读性最差；类型安全弱（JSON 字符串易错）。

**Risk**: Med — 解释器膨胀 + 调试困难
**Effort**: 2-3 周

### 推荐

**选 Approach A**。理由：
1. **MVP 最小成本**：9 个升级一次性定义，单文件数据驱动足够清晰，无需 9 文件基类体系（B 的收益在 v1+ 扩升级时才显现）
2. **可读性最优**：每个升级一条 Dictionary 记录 + 一个 Callable，比 C 的 if-elif 解释器可读、可测
3. **AC 全覆盖**：AC1（9 定义）、AC2（权重+stackable）、AC5（两接口）在 A 中都是直接数据结构；AC3/AC4 是 `apply()` 分发的两分支，与文件组织无关
4. **迁移路径清晰**：若 v1 需要升级爆炸式增长，A → B 的迁移是机械拆文件（每条记录抽出为脚本），不返工

---

## 5. 边界条件与验收标准

### 验收条件（源自 Issue #387）

- [x] **AC1: 9 个独立升级定义** — `upgrade_pool.gd` 含 9 条记录：长臂/燃烧弹/破城锤（普通）、磁心/双生/缓时/预开洞（稀有）、星尘/幻影（传说）；每条含 `id`/`name`/`rarity`/`weight`/`effect` Callable
  - 验证：遍历定义表断言 9 条、id 唯一、稀有度 ∈ {common, rare, legendary}
- [x] **AC2: 60/30/10 权重抽取 + 不可重复/堆叠配置** — 抽取算法按权重区间采样；每条记录含 `stackable: bool`、`max_stacks: int`
  - 验证：注入种子跑 N=10000 次统计分布 ≈ 60/30/10（±2%）；`get_candidates(3)` 返回 3 个**不重复** id；`stackable=false` 的升级重复抽中时被跳过/替换
- [x] **AC3: ball/paddle 参数实例级** — `paddle.gd` 的 `SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` 改实例属性（初值=常量）；`ball.gd` 消除常量直引用
  - 验证：apply 长臂后 paddle 宽度实例属性变化且**下一帧** `_process` 生效（移动/边界/碰撞 shape 同步）；`constants.gd` 值不变
- [x] **AC4: 砖墙类升级走 BreakoutGrid upgrade_hooks** — 预开洞（pre_wave hook）/破城锤、燃烧弹链式（on_brick_destroyed hook）
  - 验证：`upgrade_hooks` 契约在 #384 DESIGN 中补充；apply 预开洞后 `generate_wave` 强制开洞；砖碎时链式触发
- [x] **AC5: get_candidates(3) 与 apply(upgrade_id)** — 接口签名稳定，供 #388 调用
  - 验证：`get_candidates(3)` 返回数组长度 3；`apply("long_arm")` 返回 true 且效果生效；`apply("unknown_id")` 返回 false 不崩溃

### 边界情况

1. **候选不足 3 个**：9 升级全被选过且不可重复时，`get_candidates` 应返回剩余可用升级（可能 <3），或按规则放行已选升级——需明确行为并测试
2. **重复抽中不可堆叠升级**：权重采样命中间隔内已应用且 `stackable=false` 的升级 → 跳过重抽（有限重试，防死循环）
3. **堆叠上限**：`max_stacks=3` 的升级第 4 次抽中 → 视为不可用；数值类堆叠需定义叠加语义（乘法/加法）
4. **apply 未知 id**：返回 `false` + `push_warning`，不抛异常不崩溃
5. **权重和 ≠ 100**：防御性归一化（除以总和），保证任意权重配置不越界
6. **升级后参数越界**：长臂多次堆叠使 paddle 宽度 > 屏幕 → clamp 到 [min, max] 边界（与 #383 边界逻辑一致）
7. **hook 未注册**：BreakoutGrid 尚未实例化/未实现时 apply 砖墙类升级 → 挂起 hook 或返回 false，不空指针
8. **测试种子确定性**：权重测试注入固定种子，CI 可复现

### 失败路径

1. **paddle.gd 改实例属性破坏现有测试**：#288/#383 测试钉死常量行为 → 改造必须保持默认值语义不变（初值=常量），跑全量回归
2. **升级池与 #384 实现时序竞态**：本 Issue PRD 先行、#384 实现后置 → `upgrade_hooks` 契约先写入 DESIGN；若 #384 实现先落地，实现时按契约补 hooks
3. **Callable 引用失效**：升级回调引用已释放节点 → `is_instance_valid` 守卫 + 日志
4. **文案 JSON（#395）未就绪**：`apply()` 不依赖文案字段（机械独立），UI 展示才需文案 → 无阻塞

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #383 轴交换+竖屏 | ✅ 已合并（PR #409） | 无 — 竖屏坐标系已就绪 |
| #384 BreakoutGrid | ⚠️ PRD #411 + DESIGN #414 已合并，代码未实现 | Low — `upgrade_hooks` 契约趁实现前写入 DESIGN，零返工 |
| #395 升级池文案 | ⚠️ PRD 已合并，JSON 未落地 | Low — 机械层独立，不依赖文案字段 |
| PLAN-rogue-pong §2.5 | ✅ 已确认 2026-08-13 | 无 |

### 阻塞（下游消费者）

| 下游 | 优先级 | 本 Issue 提供的契约 |
|------|--------|-------------------|
| #386 波次循环 | P0 | 波间触发升级窗口的数据源（可调用 `get_candidates`） |
| #388 3 选 1 升级 UI | P0（依赖 #386+#387） | `get_candidates(3)` 候选 + `apply(id)` 应用 |
| #393 主场景组装 | P0 | 升级池节点/autoload 接线清单 |

### 依赖链

```
#383 (竖屏) ──✅──► #384 (BreakoutGrid) ──► #385 (双得分制, brick_destroyed)
                          │                    └──► #386 (波次循环, wall_cleared)
                          │                              │
                          └── upgrade_hooks 契约(本Issue) └──► #387 (本Issue: 升级池)
                                                                     │
                                                                     └──► #388 (3选1 UI)
```

### 准备清单

- [x] 开源优先调研（Asset Library + GitHub，§7 实验 1）
- [x] 现有参数实例化水平核查（ball 部分满足/ paddle 全 const，§7 实验 2）
- [x] #384 DESIGN 信号契约与 hooks 缺口核查（§7 实验 3）
- [ ] plan agent：确认 `upgrade_hooks` 契约小节写入 #384 DESIGN 的措辞
- [ ] plan agent：确认 paddle CollisionShape 运行时调整方式（tscn 修改 vs 代码 set）

---

## 7. Spike / 实验

> 本 Issue 无 `depth/deep` 标签，按 standard 惯例 Section 7 可选；鉴于 Issue body 明确要求「开源优先」调研，以下 3 个实验已在**研究阶段实际执行**并给出结论。

| # | 问题 | 方法 | 结果 | 对方案的影响 |
|---|------|------|------|-------------|
| 1 | 是否存在可复用的升级池/权重抽取插件？ | Godot Asset Library（4.x 过滤 `upgrade`/`roguelike`）+ GitHub 搜索（`godot upgrade system`） | Asset Library：`upgrade` 2 结果（Wyvernshield 2 战斗升级 4.0、GDScript Code Upgrader 工具类）、`roguelike` 0 结果；GitHub：全部 <5⭐ 学习向 demo（idleclicker/learnings_upgrades），无可插拔升级池模块 | 确认第一方实现（Approach A），零第三方依赖 |
| 2 | ball/paddle 参数实例化现状如何？ | 读 `ball.gd`/`paddle.gd`/`constants.gd` 源码 | ball 已有 `@export` 实例变量（initial_speed 等）+ `speed` 实例状态，但 `var speed = INITIAL_SPEED` 常量直引用；paddle 的 `SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` 全 const 且用于移动/边界计算 | Approach A 需改造 paddle（const→var，初值=常量）+ ball 消除常量直引用；测试回归由 #288/#383 兜底 |
| 3 | BreakoutGrid 有无升级挂钩点？ | 读 #384 DESIGN #414 §3.4/§4.1 API 清单 | 仅 `brick_destroyed`/`wall_cleared` 两信号 + `generate_wave`/`clear_wall` API，无 hooks；#384 代码未落地 | 趁实现前在 DESIGN 补 `upgrade_hooks` 契约（pre_wave / on_brick_destroyed），成本最低 |

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- 竖屏 720×1280 就绪（#383，PR #409）；ball 为 Area2D（layer 3、mask 3），砖墙契约已在 #384 DESIGN（layer 2 空闲且球 mask 已含）
- **ball.gd 参数已部分实例化**（`@export` 变量 + `speed` 实例状态）——AC3 工作量主要在 paddle 与常量直引用清理
- **paddle.gd 全 const**：`SPEED`（移动）、`PADDLE_WIDTH`（边界）、`PADDLE_HEIGHT` 需改实例属性，`player_paddle.tscn` CollisionShape2D `Vector2(120,20)` 需可运行时调整
- **无任何升级代码**；`assets/content/upgrade_pool.json` 属 #395（文案 schema `upgrade-pool-content/v1` 已定义）
- **#384 代码未实现**：`upgrade_hooks` 契约必须在 plan 阶段写入 DESIGN #414 补充小节，避免实现后返工

### 本 PRD 的核心决策（勿偏离）

1. **Approach A**：`upgrade_pool.gd` 单文件数据驱动（9 条 Dictionary 定义 + Callable 回调 + 权重区间抽取）
2. **权重**：普通 60% / 稀有 30% / 传说 10%（PLAN §2.5 唯一权威），防御性归一化
3. **AC3 落地**：const → 实例属性（初值=常量）；paddle 移动/边界/CollisionShape 全走实例值；ball 消除 `INITIAL_SPEED` 等直引用
4. **AC4 落地**：BreakoutGrid 追加 `upgrade_hooks`（`pre_wave: Array[Callable]`、`on_brick_destroyed: Array[Callable]`）——预开洞挂 pre_wave，破城锤/燃烧弹挂 on_brick_destroyed
5. **接口**：`get_candidates(count) -> Array[Dictionary]`（去重）、`apply(id) -> bool`（未知 id 返回 false）、`is_applied(id)`、`reset()`
6. **文案边界**：不碰 #395 的 JSON；`apply()` 机械独立

### 新建文件清单

| 文件 | 要点 |
|------|------|
| `mini-pong/gdscripts/upgrade_pool.gd` | 9 升级定义 + 权重抽取 + `get_candidates`/`apply`/`is_applied`/`reset` |
| `mini-pong/tests/test_upgrade_pool.gd` | 见下「测试要点」 |

### 修改文件清单

| 文件 | 改动 |
|------|------|
| `mini-pong/gdscripts/paddle.gd` | `SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` → 实例属性；移动/边界用实例值 |
| `mini-pong/gdscripts/ball.gd` | 消除常量直引用（`var speed` 初值改走实例）；确保升级可改 `speed_increment`/`max_speed_multiplier` 等 |
| `mini-pong/scenes/player_paddle.tscn` | CollisionShape2D 尺寸可运行时调整（或 paddle.gd 代码 set） |
| `mini-pong/gdscripts/constants.gd` | 不变（默认值来源）；如需新增 `UPGRADE_WEIGHTS` 常量组 |
| `mini-pong/tests/run_tests.gd` | 注册 `test_upgrade_pool.gd` |
| `docs/DESIGN/384-breakout-grid-brick-wall.md` | plan 阶段追加 `upgrade_hooks` 契约小节 |

### 测试要点（test_upgrade_pool.gd）

- 定义完整性：9 条、id 唯一、稀有度/权重合法
- 权重分布：固定种子 × 10000 次抽样 ≈ 60/30/10（±2%）
- 去重候选：`get_candidates(3)` 三 id 互不重复；候选不足时行为明确
- stackable：false 的升级不重复入池；max_stacks 上限生效
- apply：数值类改实例属性且下一帧生效（paddle 宽度、ball 速度）；砖墙类写入 hooks；未知 id 返回 false
- 回归：#288/#383 既有 paddle/ball 测试全绿（默认值语义不变）

### 主要风险

- **paddle const→var 回归**：默认值语义必须不变（初值=常量），#288/#383 测试兜底
- **#384 时序**：upgrade_hooks 契约先入 DESIGN，实现后置——plan agent 必须在 #384 实现 PR 前完成 DESIGN 补充
- **Callable 生命周期**：回调引用守卫 `is_instance_valid`

### 下一步

1. plan agent 依据本 PRD 产出 DESIGN（含 `upgrade_hooks` 契约补充小节 + paddle 实例化细节）
2. #384 实现时按契约落地 `upgrade_hooks`（或 #387 实现时若 #384 已落地则直接接线）
3. implement agent 实现 upgrade_pool.gd + paddle/ball 改造 + 测试
4. #386 波次循环在波间调用 `get_candidates`；#388 UI 消费候选与 `apply`

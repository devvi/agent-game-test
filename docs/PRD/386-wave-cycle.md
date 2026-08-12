# PRD: [Feature] 波次循环 (Wave Cycle)

> **Issue:** #386
> **标签:** enhancement, gameplay, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验补齐）
> **所有权:** `content_ownership: mechanical`（波次状态机/递增/清理/终局停止为纯机械实现；波次难度数值曲线归 taste-draft Issue）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.1 核心循环（已确认）：波次开始 → 生成中立砖墙 → 对打 → 砖墙打空 = 一局结束 → 结算 → 3选1升级 → 下一波（墙更厚 + AI 更强）→ 失败 = 比分落后到阈值
> **前置依赖:** #383（轴交换+竖屏，**已合并** PR #409）→ #384（砖墙系统，PRD #411 + DESIGN #414 **已合并**，**实现未落地**）→ #385（双得分制，**已实现并合并** PR #424）→ 本 Issue

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）目前是**单局 21 分制对打**（#385 已落地）：一场比赛 = 从 MENU 发球对打直到任意一方先到 21 分。**不存在波次概念**：没有 wave_index、没有波次状态机、没有墙清空→结算→下一波的循环；砖墙（#384）本身 PRD/DESIGN 已合并但**实现未落地**（`gdscripts/` 中无 `breakout_grid.gd` / `brick.gd`）。

| 文件 | 当前状态 | 与 #386 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/game_manager.gd` | autoload 全局状态：`player_score/ai_score`、`add_score(winner, amount, kind)`（#385）、`WIN_SCORE=21`、`is_run_over()`、`match_over` 信号、拆砖/穿墙计数 | ❌ **无 wave_index、无波次状态机、无 wave_* 信号**——Issue 明确要求「GameManager 持有波次状态机」 |
| `mini-pong/gdscripts/game_state_machine.gd` | 6 态 FSM：MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER；SCORED 内 `is_run_over()` → GAME_OVER 否则 SERVING（#385 AC3） | ❌ 无 WAVE/SETTLEMENT 状态；波次结算阶段的暂停/转场时机未定义（#390 依赖） |
| `mini-pong/gdscripts/paddle.gd` | AI 模式参数已实例级 `@export`（#387 落地后）：`ai_reaction_delay_min/max`、`ai_position_error`、`ai_speed_boost/slow`、`paddle_speed` | ✅ **运行时可直接缩放 AI 难度**——每波改实例属性即可（AC2 的 AI 侧杠杆） |
| `mini-pong/gdscripts/scoring_manager.gd` | 消费 `ball.score(side)` + `BreakoutGrid.brick_destroyed`（`get_node_or_null("../BreakoutGrid")` 容错，#385 已落地） | ✅ 提供了「#384 未接线时容错」的既有模式，本 Issue 的 wall_cleared 消费方照抄 |
| `mini-pong/gdscripts/upgrade_pool.gd` + `brick_upgrade_hooks.gd` | autoload（#387 已合并 PR #423）：`get_candidates(n)` / `apply(id)` / `upgrade_applied` 信号 / `grid_ref/ball_ref/paddle_ref` 目标解析 / `register_all(grid)` | ⚠️ 升级池就绪但**无人触发**——波次结算（#388 依赖本 Issue）是升级抽取的触发点 |
| `mini-pong/gdscripts/rain_curtain.gd` | 动态雨幕（#389 已合并，Main.tscn 已实例化）：`set_wave_factor(wave_index)` 契约 API——波次因子 = wave_index × +0.1（RAIN_WAVE_STEP） | ⚠️ 契约就绪但**无人调用**——#386 是 DESIGN #389 §3.5 指定的唯一写入口（波次开始一行接入） |
| `mini-pong/gdscripts/constants.gd` | `WIN_SCORE=21`（#385）、AI 手感常量（#367 定稿值） | ❌ 无 `WAVE_*` 常量组（首波厚度/每波增量/上限） |
| `mini-pong/scenes/Main.tscn` | 无 BreakoutGrid 节点（接线归 #393） | ⚠️ wall_cleared 信号源缺失 → 本 Issue 消费方必须容错 + 隔离测试 |
| `mini-pong/tests/run_tests.gd` | 注册 17 个测试套件 | ❌ 无波次循环测试 |

**#384 契约核查（本 Issue 消费的 API，来自 DESIGN #414）：**

- `BreakoutGrid.wall_cleared()` 信号——整墙打空**只发一次**（`_wall_cleared_emitted` 守卫，`generate_wave()` 重置）→ **本 Issue 的波次推进触发器**
- `BreakoutGrid.generate_wave(thickness: int, layout: BrickLayout, seed: int)`——**先 `clear_wall()`**（快照遍历 `queue_free` 全部旧砖 + 重置计数/守卫/集合）→ **AC4「旧墙不叠加」由该 API 保证**；`rows = thickness`
- `BreakoutGrid.clear_wall()`——防旧信号泄漏
- **⚠️ #384 实现未落地**：`git ls-tree origin/main mini-pong/gdscripts/` 无 `breakout_grid.gd` / `brick.gd`。本 Issue 的 WaveController 必须 `get_node_or_null` 容错（同 ScoringManager 模式），隔离测试直接实例化脚本。

### 预期行为（验收条件，源自 Issue #386）

1. **AC1 — 每波清空后进入波次结算，然后自动生成新墙并开始下一波** — `wall_cleared` → 波次结算（短暂状态，给 #388 升级 UI / #390 转场挂接点）→ `generate_wave(更厚参数)` → 下一波开始
2. **AC2 — 下一波的 AI 速度/反应或砖墙厚度至少有一项高于上一波** — 波次难度递增：`thickness` 每波 +1 **或** AI 参数（反应延迟/位置误差）收紧，二者至少其一严格递增
3. **AC3 — 全局 wave_index 从 1 开始递增，并在 UI/转场中可读** — `GameManager.wave_index` 从 1 起；`wave_started(wave_index)` 信号供 #390 转场（「第 N 道墙」）/ #393 HUD 消费
4. **AC4 — 波次循环不会叠加多个旧墙，旧砖/旧粒子全部清理** — 单 BreakoutGrid 实例，只调 `generate_wave()`（内部先 `clear_wall()`）；不重复实例化网格
5. **AC5 — 任一玩家达到 21 分后波次循环停止，不再生成新墙** — 结算时检查 `GameManager.is_run_over()` → 停止生成，FSM 走既有 `match_over → GAME_OVER` 路径

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 波次推进 | 每波一次 | 玩家/AI 打空整墙 → `wall_cleared` → 结算（升级/转场挂点）→ 自动生成更厚新墙 → 下一波 |
| B | 难度爬升 | 每波 | HUD/转场显示「第 N 道墙」（#390）；AI 反应更快或墙更厚（AC2），直到一方 21 分 |
| C | 终局停止 | 每局一次 | 任一玩家到 21 分 → 波次循环停止，不再生成新墙 → GAME_OVER 屏（run 数据含波次数） |

### 技术约束（继承自 Issue #386 + PLAN-rogue-pong）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，720×1280 竖屏，resizable=false） |
| 状态机归属 | **GameManager 持有波次状态机**（Issue 原文）；场景侧消费方遵循 ScoringManager 容错模式 |
| 循环语义 | 墙打空 ≠ 终局（#385 确认）：21 分制下比赛继续直到 21；AC5 是唯一停止条件 |
| 清理语义 | 旧砖清理由 `generate_wave()` 内部 `clear_wall()` 保证（#384 DESIGN §4.1），本 Issue 不重复实现 |
| 难度数值 | 波次难度**曲线数值**归 taste-draft（PLAN §4.2 波次规则数值）；本 Issue 只保证「至少一项严格递增」的机械机制 + 可调常量占位 |
| 不变项 | FSM（#294）、scoring 信号链（#291/#295/#385）、升级池（#387）、手感数值（#367）不变；`ball.gd` 零改动 |

### Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（WebDAV，`OBSIDIAN_VAULT_PATH`），本会话 **Knowledge Ocean 目录读取超时**（挂载层报 `Too many open files in system`，与 #384 会话同症状），未能直接检索到波次/肉鸽循环相关笔记
- **兜底**：波次循环设计已由 `docs/PLAN-rogue-pong.md` §2.1（核心循环：墙打空=一局结束 → 结算 → 3选1升级 → 下一波墙更厚+AI更强）**固化并用户拍板**；其肉鸽循环语义（波次递增 + 程序化砖墙 + 3 选 1 升级池 + 失败即叙事，§1.2）为本 PRD 的上游依据。GDD `docs/GAME_DESIGN/23-UPGRADE-POOL.md` 确认升级池定位为「wave settlement (#386, not yet wired) 与 paddle/ball/grid 之间的 data hub」——即结算触发升级是本 Issue 预留的挂接点。

---

## 2. 设计意图

### 为什么现状如此

| 现状 | 成因 | 证据 |
|------|------|------|
| 单局 21 分制，无波次 | #385 只落地了「先到 21 分者赢」的终局判定，未包含循环 | `game_manager.gd` 无 wave 字段；FSM 6 态无 WAVE |
| 砖墙信号契约存在但无实现 | #384 走 PRD(#411)+DESIGN(#414) 合并、实现未落地的分步管线 | `gdscripts/` 无 breakout_grid.gd/brick.gd |
| AI 参数已是实例级 @export | #387 升级池把 const 参数化（AC3） | `paddle.gd` L16-31 @export 组 |
| 升级池无人触发 | #387 只交付数据模型/抽取/应用 API，触发点（结算）依赖 #386 | `upgrade_pool.gd` 无主动调用方 |

### 为什么现在做

- **前置已就绪**：#383（竖屏坐标）✅、#385（21 分终局 + `is_run_over()`）✅、#387（升级池 + 实例参数化）✅；#384 虽实现未落地，但其 DESIGN 契约（`wall_cleared` / `generate_wave` / `clear_wall`）已合并且明确「#386 波次重置」为消费方——契约先行，本 Issue 可容错对接
- **下游全部依赖本 Issue**：#388（3选1升级UI）、#390（波次转场）、#393（主场景组装）均以 #386 的 wave_index/结算状态为前提（GDD 23 明确 UpgradePool 是「wave settlement (#386, not yet wired) 的 data hub」）
- **MVP 切片要求**：PLAN §5 将「波次循环」列为 MVP 必需件；§6 DoD 完成路径「MENU → 波1 → 3选1 → 波2 → … → 失败屏」以波次循环为骨架

### 前置约束（继承）

| 约束 | 细节 |
|------|------|
| FSM 不重构 | 6 态机器保持；波次状态放 GameManager（Issue 原文），FSM 只消费 `match_over`（既有） |
| 容错接线 | #384 未落地前 wall_cleared 不可用 → WaveController `get_node_or_null` + 隔离测试（ScoringManager 同款） |
| 单实例网格 | 波次循环绝不 `new` 第二个 BreakoutGrid；只调既有实例的 `generate_wave()` |
| 停止条件唯一 | 只有 21 分（`is_run_over()`）停止循环；不引入其他停止规则 |

---

## 3. 影响分析

### 直接影响的模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/game_manager.gd` | 波次状态机宿主 | **新增**：`wave_index`（从 1 起）、`wave_state` 枚举（IDLE/RUNNING/SETTLED）、`wave_started(wave_index)` / `wave_settled(wave_index)` 信号、`begin_wave()` / `settle_wave()` / `is_wave_cycle_active()` API |
| `mini-pong/gdscripts/wave_controller.gd`（新） | 场景侧波次编排（ScoringManager 同构） | **新建**：消费 `BreakoutGrid.wall_cleared`（容错）→ `GameManager.settle_wave()` → 难度递增（厚度/AI 参数）→ `generate_wave(next_thickness, ...)` → `RainCurtain.set_wave_factor(wave_index)`（#389 契约，一行接入）→ 检查 `is_run_over()` 决定是否生成新墙 |
| `mini-pong/gdscripts/rain_curtain.gd` | 动态雨幕（#389 已合并，Main.tscn 已实例化）：`set_wave_factor(wave_index)` 契约 API——波次因子 = wave_index × +0.1（RAIN_WAVE_STEP） | ⚠️ 契约就绪但**无人调用**——#386 是 DESIGN #389 §3.5 指定的唯一写入口（波次开始一行接入） |
| `mini-pong/gdscripts/constants.gd` | 波次常量 | **新增** `WAVE_*` 组：`WAVE_START_THICKNESS`、`WAVE_THICKNESS_STEP`、`WAVE_MAX_INDEX`（防御）、AI 难度缩放因子占位（taste-draft 可调） |
| `mini-pong/tests/run_tests.gd` | 测试注册 | **修改**：注册 `test_wave_cycle.gd` |
| `mini-pong/tests/test_wave_cycle.gd`（新） | 波次循环测试 | **新建**：见 §5 边界条件 |

### 新建文件

| 文件 | 用途 |
|------|------|
| `mini-pong/gdscripts/wave_controller.gd` | 场景侧节点，消费 wall_cleared + 驱动 GameManager 波次状态机 + 难度递增 + 调用 generate_wave |
| `mini-pong/tests/test_wave_cycle.gd` | 隔离测试（mock BreakoutGrid 发 wall_cleared） |

### 间接影响的模块

| 文件 | 影响 |
|------|------|
| `mini-pong/scenes/Main.tscn` | **不动**（本 Issue 不接线；WaveController/BreakoutGrid 接线归 #393；容错模式可独立运行） |
| `mini-pong/gdscripts/game_state_machine.gd` | **不动**（波次状态在 GameManager；FSM 仅既有 `match_over` 路径已覆盖 AC5 的 GAME_OVER 到达） |
| `mini-pong/gdscripts/game_hud.gd` | **不动**（波次号 UI 归 #390/#393；本 Issue 只保证 `wave_index` 可读 + `wave_started` 信号） |
| `mini-pong/gdscripts/upgrade_pool.gd` | **不动**（#388 消费其 API；本 Issue 的结算状态是其触发挂点） |
| `mini-pong/gdscripts/scoring_manager.gd` | **不动**（已有 brick_destroyed 容错消费，#385） |

### 数据流影响

```
BreakoutGrid.wall_cleared()  [#384 契约; 未接线时容错跳过]
    │
    ▼
WaveController._on_wall_cleared()            [场景侧, get_node_or_null("../BreakoutGrid")]
    │
    ▼
GameManager.settle_wave()  →  wave_state = SETTLED
    │                          wave_settled.emit(wave_index) ──► #388 升级UI / #390 转场挂点
    ▼
WaveController._on_settled():
    ├── if GameManager.is_run_over(): 停止循环 ──► FSM match_over → GAME_OVER (AC5)
    └── else:
            wave_index += 1  (GameManager.begin_wave())
            difficulty: thickness = WAVE_START_THICKNESS + (wave_index-1)*WAVE_THICKNESS_STEP
                        AI 参数收紧 (ai_reaction_delay_min/max, ai_position_error)
            grid.generate_wave(thickness, layout, seed)   [内部 clear_wall() → AC4]
            RainCurtain.set_wave_factor(wave_index)          [#389 契约：雨量波次因子 +0.1/波]
            wave_started.emit(wave_index) ──► #390 「第 N 道墙」 / #393 HUD (AC3)
```

### 需更新的文档

- [x] `docs/GAME_DESIGN/15-GAME-MANAGER.md`（#386 合并后补波次状态机小节）
- [x] `docs/GAME_DESIGN/INDEX.md`（新增 24-WAVE-CYCLE 条目）
- [x] `docs/PROJECT.md` / GDD（波次循环状态）
- [ ] plan agent 的 DESIGN 文档（本 PRD 交接后）

---

## 4. 方案对比

### 4.1 波次状态机归属

**Approach A：GameManager 持有状态机 + 场景侧 WaveController 消费信号（推荐）**

| 维度 | 内容 |
|------|------|
| 描述 | GameManager（autoload）持有 `wave_index` + `wave_state` 枚举 + `wave_started/wave_settled` 信号（纯状态，无场景引用）；新建场景侧 `WaveController` 节点消费 `BreakoutGrid.wall_cleared`（`get_node_or_null` 容错）→ 驱动 GameManager → 难度递增 → 调 `generate_wave()`。与 ScoringManager（消费 ball.score + brick_destroyed）完全同构 |
| Pros | ① 贴合 Issue 原文「GameManager 持有波次状态机」；② autoload 保持无场景依赖（可隔离测试，同 #385 的 GameManager 直测模式）；③ 容错接线模式有先例（ScoringManager）；④ 下游 #388/#390/#393 消费 GameManager 信号即可，不碰场景树 |
| Cons | 两个文件协同（状态在 autoload、编排在场景侧），职责边界需文档固化 |
| Risk | Low（模式与 #385 完全一致） |
| Effort | 0.5–1 周（含测试） |

**Approach B：全部逻辑塞进 GameManager**

| 维度 | 内容 |
|------|------|
| 描述 | GameManager 直接 `get_node` 场景节点（BreakoutGrid/paddle），自己消费 wall_cleared |
| Pros | 单文件 |
| Cons | ① autoload 依赖场景树，破坏 #385 建立的「GameManager=纯状态」测试模式；② 与 `UpgradePool` 的 `grid_ref` 目标解析模式（#387 注入式）冲突；③ 隔离测试需 mock 场景树，成本高 |
| Risk | Med（架构回归） |
| Effort | 0.5 周（实现快但测试难） |

**Approach C：FSM 扩展 WAVE/SETTLEMENT 状态**

| 维度 | 内容 |
|------|------|
| 描述 | 波次推进逻辑放进 `game_state_machine.gd` 的新状态 |
| Pros | 转场时机（#390）天然在 FSM 里 |
| Cons | ① 违背 Issue 原文「GameManager 持有波次状态机」；② FSM 已是场景级编排（@onready 场景引用），波次是**全局运行状态**（跨场景/结算屏可读），放 FSM 后 #391 失败屏读不到；③ FSM 状态爆炸（6→9） |
| Risk | High（状态归属错误，下游全部受影响） |
| Effort | 0.5 周（但返工风险高） |

**推荐：Approach A。** 理由：① Issue 明确指定 GameManager 持有；② 与 #385 架构同构（autoload=状态+信号，场景节点=消费编排），容错模式有先例；③ 下游消费方（#388/#390/#391/#393）只需连 GameManager 信号，与场景树解耦。

### 4.2 波次难度递增机制

**Approach A：线性递增 + 常量占位（推荐）**

| 维度 | 内容 |
|------|------|
| 描述 | `thickness = WAVE_START_THICKNESS + (wave_index-1) * WAVE_THICKNESS_STEP`；AI 侧每波收紧：`ai_reaction_delay_min/max *= AI_DIFFICULTY_FACTOR`（clamp 到下限）、`ai_position_error *= AI_DIFFICULTY_FACTOR`。常量在 `constants.gd`，默认值机械占位（taste-draft 可调） |
| Pros | ① 机械可测：AC2「至少一项严格递增」可断言；② 常量集中单一事实源；③ 数值曲线留 taste-draft（PLAN §4.2 波次规则数值） |
| Cons | 曲线非最优（但 MVP 无 taste 需求） |
| Risk | Low |
| Effort | 小 |

**Approach B：难度曲线表（每波查表）**

| 维度 | 内容 |
|------|------|
| 描述 | 预定义每波厚度/AI 参数的查表 |
| Pros | 曲线可控 |
| Cons | ① 数值即 taste 内容，MVP 阶段无数据来源（PLAN §4.2 归 taste-draft）；② 查表逻辑比公式重 |
| Risk | Med（taste 前置） |
| Effort | 中 |

**Approach C：随机难度**

| 维度 | 内容 |
|------|------|
| 描述 | 每波随机生成厚度/AI 参数 |
| Pros | 变化丰富 |
| Cons | ① **违反 AC2**「至少有一项高于上一波」的确定性要求；② 不可测 |
| Risk | High（AC 违反） |
| Effort | 小 |

**推荐：Approach A。** 理由：AC2 要求确定性递增，线性公式 + 常量占位是唯一满足「机械可测 + taste 后置」的组合。

---

## 5. 边界条件与验收标准

### 正常路径（AC 清单）

- [x] **AC1: 每波清空后进入波次结算，然后自动生成新墙并开始下一波**
  - `wall_cleared` → `GameManager.settle_wave()` → `wave_state=SETTLED` → `wave_settled.emit()` → 自动 `generate_wave(next)` → `wave_started.emit()`
  - 验证：mock grid 发 wall_cleared → 断言 generate_wave 被调、wave_index +1
- [x] **AC2: 下一波的 AI 速度/反应或砖墙厚度至少有一项高于上一波**
  - `thickness` 每波 +`WAVE_THICKNESS_STEP`（默认 1）**且** AI 反应延迟/位置误差每波收紧（clamp 下限）
  - 验证：波 N+1 的 thickness > 波 N；AI 参数 ≤ 波 N（收紧方向）
- [x] **AC3: 全局 wave_index 从 1 开始递增，并在 UI/转场中可读**
  - `GameManager.wave_index` 初始 1，每波 +1；`wave_started(wave_index)` 信号带当前 index
  - 验证：首波 wave_index==1；连续两波后 ==2；信号负载正确
- [x] **AC4: 波次循环不会叠加多个旧墙，旧砖/旧粒子全部清理**
  - 单 BreakoutGrid 实例；只调 `generate_wave()`（内部 `clear_wall()` 先 queue_free 全部旧砖 + 重置守卫）
  - 验证：连续 3 波后场景中砖节点数 == 第 3 波砖数（无残留）；`remaining_bricks` 正确
- [x] **AC5: 任一玩家达到 21 分后波次循环停止，不再生成新墙**
  - 结算时 `GameManager.is_run_over()` → 不调 `generate_wave()`；`wave_state=IDLE`；FSM 既有 `match_over → GAME_OVER`
  - 验证：21 分后 mock grid 再发 wall_cleared → 不生成新墙

### 边界情况（≥5）

1. **首波起始** — 从 MENU 进入第一局：`wave_index` 从 1 开始，首波厚度 = `WAVE_START_THICKNESS`；GameManager `reset_match()`（#385 既有）时波次状态一并重置
2. **wall_cleared 与 match_over 同帧/相邻** — 最后一砖与 21 分同帧：结算先判 `is_run_over()` → 停止，不生成新墙；FSM `_on_match_over` 已守卫（GAME_OVER 幂等）
3. **#384 未接线（实现未落地期）** — `get_node_or_null("../BreakoutGrid")` 为 null → WaveController 跳过消费并 push_warning（ScoringManager 同款）；隔离测试直接实例化脚本验证逻辑
4. **wall_cleared 重复发出** — #384 DESIGN 的 `_wall_cleared_emitted` 守卫保证每墙一次；WaveController 侧再加 `_settling` 布尔守卫（结算中忽略重复信号）
5. **wave_index 上限防御** — `WAVE_MAX_INDEX`（默认如 99）到达后停止递增（21 分制下实际远早触发 AC5，纯防御）
6. **发球/暂停态** — 球静止或 PAUSED 时无砖接触，wall_cleared 不可能触发（#384 边界 6 已覆盖），波次状态机无需处理
7. **结算阶段再得分** — SETTLED 期间球已停（FSM 冻结挡板），无新得分路径；`scored` 信号被 FSM 状态守卫忽略（既有）

### 失败路径（≥3）

1. **generate_wave 抛错/网格为空** — `generate_wave` 后校验 `remaining_bricks > 0`，否则回退重试一次（seed 变化）；仍失败 → push_warning + 波次暂停（不崩溃）
2. **升级 UI（#388）未接线时结算挂起** — 结算状态**不依赖**升级 UI：`wave_settled` 发出后按配置延时自动进入下一波（`WAVE_SETTLE_DELAY`，默认如 1.0s）；#388 接线后由 UI 决定推进时机（其 AC 独立）
3. **wave_index 溢出** — 达到 `WAVE_MAX_INDEX` 后停止递增并停止生成（防御；AC5 先触发则走 AC5 路径）

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #383 轴交换+竖屏（720×1280） | ✅ 已合并（PR #409） | 无 |
| #384 砖墙系统（`wall_cleared` / `generate_wave` / `clear_wall` 契约） | ⚠️ PRD #411 + DESIGN #414 已合并，**实现未落地**（无 breakout_grid.gd） | **中**：契约已定但信号源缺失；本 Issue 用 `get_node_or_null` 容错 + 隔离测试先行，不阻塞 |
| #385 双得分制（`WIN_SCORE=21` / `is_run_over()` / `match_over`） | ✅ 已实现并合并（PR #424） | 无（AC5 停止条件直接复用） |
| #387 升级池（实例参数化 + UpgradePool autoload） | ✅ 已合并（PR #423） | 无（AI 参数实例级缩放依赖其落地，已就绪） |
| #367 手感数值（AI 参数定稿值） | ✅ 已定稿 | 无（缩放基于定稿值） |

### 阻塞（下游消费者）

| 下游 | 优先级 | 本 Issue 提供的契约 |
|------|--------|-------------------|
| #388 3选1升级UI | P0 | `wave_settled(wave_index)` 结算挂点 + `wave_state=SETTLED`（其触发时机） |
| #390 波次转场 | P0 | `wave_started(wave_index)` + `GameManager.wave_index` 可读（「第 N 道墙」文案） |
| #393 主场景组装 | P0 | WaveController 节点 + wall_cleared 接线点（连同 #384 的 BreakoutGrid 一并接入） |
| #394 端到端可玩验证 | P0 | 波次循环 E2E（多波推进 + 21 分停止截图） |

### 依赖链

```
#383 (轴交换+竖屏) ──✅ 已合并──► #384 (砖墙系统) ──⚠️实现未落地──► #385 (双得分制) ──✅ 已合并──► #386 (本 Issue: 波次循环)
                                                                                                    │
                            #387 (升级池) ──✅ 已合并──► 实例级 AI 参数 (paddle.gd @export)          │
                                                                                                    ▼
                                                          #388 (3选1升级UI) / #390 (波次转场) / #393 (组装) / #394 (E2E)
```

### 准备清单

- [x] 开源优先调研（Asset Library + GitHub，§7 实验 1）
- [x] 既有状态核实（GameManager 无 wave 字段；FSM 6 态；AI 参数已实例级）
- [x] #384 契约核实（wall_cleared/generate_wave/clear_wall 语义 + 实现未落地 → 容错设计）
- [x] Obsidian 知识检索（读取超时；设计已由 PLAN-rogue-pong §2.1 固化）
- [ ] plan agent：确认 `WAVE_START_THICKNESS` / `WAVE_THICKNESS_STEP` 默认值与 AI 缩放因子（taste-draft 占位）；确认 WaveController 挂载方式（#393 接线时）

---

## 7. Spike / 实验

> 本 Issue 无 `depth/deep` 标签，按 standard 惯例 Section 7 可选；鉴于 Issue body 明确要求「开源优先」调研，以下 3 个实验已在**研究阶段实际执行**并给出结论，供 plan agent 直接引用。

| # | 问题 | 方法 | 结果 | 对方案的影响 |
|---|------|------|------|-------------|
| 1 | 是否存在可复用的波次/肉鸽循环插件？ | Godot Asset Library（4.7 过滤 `wave`/`roguelike`/`spawn`）+ GitHub 搜索（`godot wave spawner`、`godot roguelike loop`） | Asset Library 0 相关结果；GitHub 无高星可插拔波次管理器（波次逻辑与游戏规则强耦合，且本项目波次=砖墙+AI 参数，无通用插件可套） | 确认第一方实现（Approach A），零第三方依赖（与 #384 调研结论一致） |
| 2 | AI 难度能否运行时缩放？ | 读 `paddle.gd` L16-31（#387 落地后 `@export` 实例变量）与 `_ai_process`（L122-140 消费这些参数） | `ai_reaction_delay_min/max`、`ai_position_error`、`ai_speed_boost/slow` 均为实例级 @export，`_ai_process` 每帧读取 → **运行时改属性即生效**，无需重启/重建节点 | AC2 的 AI 侧杠杆可行：每波直接改 AIPaddle 实例属性 |
| 3 | 波次因子如何接入雨幕？ | 读 `rain_curtain.gd`（#389 落地后）契约 API 与 DESIGN #389 §3.5 消费方表 | `set_wave_factor(wave_index)` 存在且 DESIGN 明确消费方 = **#386 波次循环**（默认 0 不报错，未接线时雨量 = base+球速+紧张） | AC3 的 wave_index 同时驱动雨量波次因子；WaveController 在 wave_started 时一行调用，未接线容错（#389 契约默认值安全） |
| 4 | 旧墙清理能否复用 #384 契约？ | 读 DESIGN #414 §4.1（`generate_wave` 先 `clear_wall()`：快照 queue_free 全部旧砖 + 重置计数/守卫/集合）与 §5.1 再生用例（打空→再生→再打空，wall_cleared 恰好两次） | 清理契约完整且已测试规划：`generate_wave` 幂等再生，旧砖零残留、旧信号不泄漏 | AC4 直接依赖该 API；本 Issue 只保证「单实例 + 只调 generate_wave」，不重复实现清理 |

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- 竖屏 720×1280 已就绪（#383，PR #409）；21 分终局已落地（#385，PR #424：`WIN_SCORE=21`、`add_score(winner, amount, kind)`、`is_run_over()`、`match_over`、拆砖/穿墙计数）
- 升级池已落地（#387，PR #423：UpgradePool autoload + 9 定义 + 60/30/10 抽取 + 实例参数化 + `brick_upgrade_hooks.register_all(grid)`）；`paddle.gd` AI 参数全部实例级 @export（可直接缩放）
- **#384 实现未落地**：无 `breakout_grid.gd`/`brick.gd`；其 DESIGN 契约（`wall_cleared()`、`generate_wave(thickness, layout, seed)`、`clear_wall()`）已合并，明确 #386 为 `wall_cleared` 消费方 → **WaveController 必须 `get_node_or_null` 容错**（ScoringManager 同款）
- 工作区注意：并行 agent 管线活跃（#385 实现 PR #424 刚合并、#389/#396 等并行），实现时先 `git pull origin main`

### 本 PRD 的核心决策（勿偏离）

1. **Approach A（4.1）**：GameManager 持有波次状态机（`wave_index` 从 1 起 + `wave_state` 枚举 + `wave_started/wave_settled` 信号 + `begin_wave()/settle_wave()`）；场景侧新建 `WaveController` 消费 `wall_cleared`（容错）→ 驱动状态机 → 难度递增 → `generate_wave()` → 判 `is_run_over()` 停止
2. **Approach A（4.2）**：难度线性递增 + `constants.gd` `WAVE_*` 常量占位（taste-draft 后调）；AC2 保证「厚度或 AI 参数至少一项严格递增」
3. **AC4 不重复实现清理**：只调 `generate_wave()`（内部 `clear_wall()`），绝不 new 第二个网格
4. **AC5 停止条件唯一**：`is_run_over()`；FSM 走既有 `match_over → GAME_OVER`
5. **结算不依赖 #388**：`wave_settled` 后延时自动进下一波；升级 UI 接线后由其接管推进时机
6. **雨幕波次因子（#389 契约）**：WaveController 在 wave_started 时调 `RainCurtain.set_wave_factor(wave_index)`——DESIGN #389 §3.5 指定 #386 为唯一写入口；未接线时契约默认值安全（雨量回退 base+球速+紧张）

### 下一步（plan agent）

1. 读 `docs/DESIGN/384-breakout-grid-brick-wall.md` §3.4/§4.1（契约）与 `mini-pong/gdscripts/scoring_manager.gd`（容错模式范本）
2. 定 `constants.gd` `WAVE_*` 默认值（厚度起点/步进/AI 缩放因子，机械占位）
3. 设计 `WaveController` 节点挂载路径（#393 接线；独立可实例化 + 隔离测试，同 #384 交付模式）
4. 测试策略：mock grid 发 `wall_cleared`（同 test_dual_scoring 的 mock BreakoutGrid 模式）；断言 wave_index 递增、generate_wave 参数递增、21 分后不生成
5. 雨幕接线：验证 `RainCurtain.set_wave_factor(wave_index)` 调用（headless 可断言 `_wave_index` 状态，见 test_rain.gd 既有模式）
5. 若 #384 实现在本 Issue 实现前落地，接入真实信号；否则保持容错并注明

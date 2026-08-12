# PRD: [Integration] 主场景组装 — Main Scene Assembly

> **Issue:** #393
> **标签:** enhancement, feature, gameplay, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#383/#384/#386 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验补齐）
> **所有权:** `content_ownership: mechanical`（纯组装：接线 + 节点编排 + 临时调试代码清理；数值/文案归 taste-draft Issue）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.1 核心循环：波次开始 → 生成中立砖墙 → 对打 → 砖墙打空 = 一局结束 → 结算 → 3选1升级 → 下一波（墙更厚 + AI 更强）→ 失败 = 比分落后到阈值
> **前置依赖:** #383–#392（10 个组件，全部 CLOSED；其中 **#384/#390 仅文档落地、实现未落地**，见 §1 缺口分析）

---

## 1. 问题定义

### 1.0 开源调研结论（Issue 要求，PR 需说明）

**调研范围：** Godot Asset Library (assetlibrary.godotengine.org)、GitHub 仓库搜索、社区惯例。

| 资产类别 | Godot Asset Library | GitHub | 结论 |
|---------|-------------------|--------|------|
| 砖墙/Breakout 生成 | `filter=breakout` → **0 结果**（Godot 4） | Breakout4Godot ⭐3（tilemap 教学 demo）、had2020/Breakout ⭐3（Godot 4.2 演示）、其余 ⭐1–2 克隆 | ❌ 无成熟可复用插件；均为最小教学 demo，无布局模式/信号契约/升级钩子 |
| 雨幕粒子 | `filter=rain` → 9 结果全为 3D 地形工具；`filter=particle` → BurstParticles2D ⭐0、Fancy particles ⭐0 | 无 Godot 4 GPUParticles2D 雨幕成熟插件 | ❌ 无可用；项目已自研 #389 RainCurtain（已落地） |
| 霓虹 UI 主题 | 无 Godot 4 相关 | NeoCade-Theme ⭐0（2026 年新项目，未经受检验） | ❌ 项目已自研 #392 NeonStyle + 常量色系（已落地） |
| 波次转场 | 无 | 无 | ❌ 无可用；按 PRD #429 自研 |

**调研结论：** 未发现可复用的成熟插件/模板/开源资产。全部 10 个组件按项目既有模式自研（雨幕 #389、霓虹 HUD #392、升级 UI #388 均已自研落地）。本 PRD 的组装不引入任何第三方资产，沿用 `docs/DESIGN/384-breakout-grid-brick-wall.md`（#414）与 `docs/PRD/390-wave-transition.md`（#429）已定稿的契约实现缺口组件。

### 1.1 当前状态 — 组件落地盘点（#383–#392 → 代码库实况）

| 组件 | Issue # | Issue 状态 | 代码实况 | Main.tscn 实例 |
|------|---------|:---------:|---------|:--------------:|
| 轴交换+竖屏 720×1280 | #383 | CLOSED (COMPLETED) | ✅ PR #409 落地：project.godot 720×1280、paddle X 轴移动、球 Y 轴得分 | ✅ 布局已生效 |
| 砖墙系统 BreakoutGrid | #384 | CLOSED (COMPLETED) | ❌ **仅 PRD #411 + DESIGN #414 合并；`brick.gd` / `breakout_grid.gd` / `brick.tscn` / `breakout_grid.tscn` / `test_breakout_grid.gd` 均不存在** | ❌ 无节点 |
| 双得分制 | #385 | CLOSED (COMPLETED) | ✅ PR #424 落地：scoring_manager.gd 拆砖 1 分/穿墙 3 分/21 分终局 | ✅ ScoringManager |
| 波次循环 | #386 | CLOSED (COMPLETED) | ✅ PR #428 落地：wave_controller.gd（`get_node_or_null("../BreakoutGrid")` 容错模式） | ❌ **WaveController 节点未实例化**（脚本存在但场景无节点） |
| 升级池架构 | #387 | CLOSED (COMPLETED) | ✅ PR #423 落地：UpgradePool autoload + upgrade_pool.json + brick_upgrade_hooks.gd（`register_all` 契约，等待 grid） | ✅ autoload |
| 3选1升级UI | #388 | CLOSED (COMPLETED) | ✅ PR #440 落地：upgrade_pick_ui.gd（`wave_settled` → open → `advance_settlement`） | ✅ UpgradePickUI 实例 |
| 动态雨幕 | #389 | CLOSED (COMPLETED) | ✅ PR #416 落地：rain_curtain.gd（`set_wave_factor` 契约） | ✅ AtmosphereLayer/RainCurtain |
| 波次转场 | #390 | CLOSED (COMPLETED) | ❌ **仅 PRD #429 合并（无 DESIGN 文档）；`wave_transition_controller.gd` / `wave_transition.tscn` / `test_wave_transition.gd` / `WAVE_TRANSITION_*` 常量均不存在** | ❌ 无节点 |
| 失败屏 | #391 | CLOSED (COMPLETED) | ✅ PR #439 落地：game_over_screen.gd（win/fail 双分支 + run 数据） | ✅ GameOverScreen |
| 霓虹 HUD | #392 | CLOSED (COMPLETED) | ✅ PR #438 落地：game_hud.gd 三区霓虹（`get_node_or_null("../BreakoutGrid")` 容错） | ✅ GameHUD |

**⚠️ 关键事实（#384/#390 实现未落地）：** 两个 Issue 被标记 COMPLETED 并关闭，但 `git ls-tree origin/main` 证实 `mini-pong/gdscripts/` 下无 `brick.gd` / `breakout_grid.gd` / `wave_transition_controller.gd`，`mini-pong/scenes/` 下无 `brick.tscn` / `breakout_grid.tscn` / `wave_transition.tscn`。关闭事件为 `closed by devvi`（无实现 PR）。**#393 组装必须包含这两个组件的实现落地**（按已定稿契约：DESIGN #414 / PRD #429）。下游 5 处容错代码（scoring_manager / wave_controller / game_hud / upgrade_pool / brick_upgrade_hooks）都在等待 grid 落地——这正是"临时调试代码"待清理的源头。

### 1.2 当前 Main.tscn 节点清单（36 节点，现有 26 个命名节点）

```
Game (Node2D)  [root]
├── WorldEnvironment (instance world_environment.tscn)
├── AtmosphereLayer (CanvasLayer, layer=0)
│   └── RainCurtain (instance rain_curtain.tscn)          ← #389 ✅
├── LeftWall / RightWall (StaticBody2D, groups=[walls])
├── Ball (instance ball.tscn)                             ← #383 竖屏 ✅
├── PlayerPaddle / AIPaddle (instance player_paddle.tscn)
├── ScoringManager (Node, scoring_manager.gd)             ← #385 ✅
├── GameStateMachine (Node, game_state_machine.gd, NodePath exports)
├── ScoreZoneTop / ScoreZoneBottom (Area2D)
├── ScoreFlash (Node + ScoreFlashRect)
├── StartMenu (CanvasLayer, layer=1)                      ← #292
├── GameHUD (instance ui_game_hud.tscn)                   ← #392 ✅ 霓虹三区
├── GameOverScreen (CanvasLayer, layer=1)                 ← #391 ✅
├── PauseOverlay (CanvasLayer, layer=10)                  ← #296
└── UpgradePickUI (instance ui_upgrade_pick.tscn)         ← #388 ✅
```

**缺失节点（组装目标）：**
1. **BreakoutGrid**（#384，`breakout_grid.tscn` + `breakout_grid.gd`，组 `breakout_grids`）
2. **WaveController**（#386，脚本已存在 `wave_controller.gd`，需实例化 + 组 `wave_controllers`）
3. **WaveTransition**（#390，`wave_transition.tscn` + `wave_transition_controller.gd`）

### 1.3 信号链审计（Patch 20 Phase 3）

现状（组装前）——`✅` 已接线可用，`⚠️` 声明但无消费方/等待接线，`❌` 断裂：

```
Ball.score(side) ──► ScoringManager._on_ball_score(side)
    │                     ├── scored(winner) ──► GameStateMachine._on_scored()        ✅
    │                     │                    ──► ScoreFlash._on_score_changed()     ✅
    │                     └── GameManager.add_score(winner, amount, kind)
    │                             ├── score_changed(p,a) ──► GameHUD._on_score_changed()  ✅
    │                             ├── brick_scored(side) ──► GameHUD._on_brick_scored()   ✅
    │                             ├── pierce_scored(side) ──► GameHUD._on_pierce_scored() ✅
    │                             ├── wave_started(i)   ──► GameHUD._on_wave_started()    ✅
    │                             │                    ──► ⚠️ WaveTransition（#390 未落地）
    │                             ├── wave_settled(i)  ──► UpgradePickUI.open()           ✅ (autoload)
    │                             └── match_over(w)    ──► GameStateMachine._on_match_over() ✅
    │                                                  ──► GameOverScreen._on_match_over()  ✅

BreakoutGrid（❌ 不存在）
    ├── brick_destroyed(brick,pos) ──► ScoringManager._on_brick_destroyed  ⚠️ get_node_or_null 容错（现 null）
    │                              ──► GameHUD._on_grid_brick_destroyed    ⚠️ 同上
    ├── wall_cleared()           ──► WaveController._on_wall_cleared       ⚠️ 同上
    │                              ──► GameHUD._on_grid_wall_cleared       ⚠️ 同上
    ├── wall_generated()         ──► GameHUD._on_grid_wall_generated      ⚠️ 同上
    └── upgrade_hooks 注册表      ──► BrickUpgradeHooks.register_all(self)  ⚠️ 契约（#387）

WaveController（❌ 节点缺失，脚本存在）
    ├── advance_settlement()  ◄── UpgradePickUI.close() → _advance_settlement()  ⚠️ 组寻址（无节点 → no-op）
    ├── generate_wave()       ──► BreakoutGrid.generate_wave(thickness, layout, seed)  ❌
    └── set_wave_factor(i)    ──► RainCurtain.set_wave_factor(i)  ✅（_find_rain_curtain 已解析）
```

**已发现的具体问题：**

1. **首波触发缺失（组装关键缺口）：** 全代码库只有 `WaveController._advance_wave()` 调用 `GameManager.begin_wave()`，而 `_advance_wave()` 只在 `wall_cleared` 之后触发。**没有任何代码启动第 1 波**（`start_menu._on_start_pressed` 只 `reset_match()`；FSM MENU→SERVING→PLAYING 不调用 `begin_wave`）。组装必须定义首波触发路径（PRD #390 边界 1 明确"首波触发路径归 #393 组装"）。
2. **BreakoutGrid 全缺：** 节点、脚本、场景、常量组（`BRICK_SIZE/BRICK_GAP/BRICK_MIN_DIM`）、ball.gd `bricks` 碰撞分支全部缺失（DESIGN #414 §4.1/§4.2）。
3. **WaveTransition 全缺：** 控制器、场景、`WAVE_TRANSITION_*` 常量组缺失（PRD #429 §4）；ball.gd `frozen` 标志已存在（#391 已加，PRD #390 的 Approach A 前置条件已满足）。
4. **WaveController 未实例化：** `wave_controller.gd` 已合并但 Main.tscn 无节点 → 波次循环在真实场景中不运转（仅测试 mini-tree 可用）。
5. **UpgradePool.grid_ref 组契约未满足：** `upgrade_pool.gd:156` 通过组 `breakout_grids` 解析 grid（#387 契约），BreakoutGrid 落地时须 `add_to_group("breakout_grids")`。
6. **临时调试/容错代码待清理：** `scoring_manager.gd:50` / `wave_controller.gd:22` / `game_hud.gd:192` 的 `push_warning("BreakoutGrid 未接线（#393 前）...")` 容错分支——组装完成后应移除或降级（不再存在未接线状态）。

### 1.4 预期行为（验收条件，源自 Issue #393）

1. **AC1 — Main.tscn 可直接运行完整一局，不需要额外手工连线** — 从 StartMenu 按 SPACE 开始 → 第 1 波墙生成 → 对打 → 拆砖/穿墙/出界计分 → 21 分终局，全程零手工接线
2. **AC2 — 墙清空→波次结算→升级→新墙→AI 增强的循环完整** — `wall_cleared` → `settle_wave` → `wave_settled` → UpgradePickUI 3 选 1 → `advance_settlement` → `begin_wave` → 更厚新墙 + AI 收紧
3. **AC3 — HUD 分数/波次/剩余砖数随信号实时更新** — 总分（score_changed）、拆/穿计数（brick_scored/pierce_scored）、波次号（wave_started）、剩余砖数（brick_destroyed/wall_generated）全部实时刷新
4. **AC4 — 失败屏与获胜状态均可到达，无孤立信号或错误** — 玩家/AI 任一方 21 分 → `match_over` → GAME_OVER 屏（win/fail 双分支 + run 数据）；波次转场（第 N 道墙）在每波开始时播放
5. **AC5 — 运行 10 局无脚本错误/空引用，场景树无泄漏** — 连续多局（含重开、升级、终局）无错误输出；旧砖/旧转场节点全部清理（`generate_wave` 内部 `clear_wall`，转场单实例复用）

### 1.5 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 完整一局 | 每局 | 开始 → 首波墙 → 对打拆砖 → 清墙 → 升级 3 选 1 → 新墙（更厚）→ … → 21 分终局 |
| B | 波次节奏 | 每波 | 「第 N 道墙」转场 2s → 对打 → 雨幕随球速/波次增强（#389 已落地） |
| C | 重开 | 每局 | 终局 → SPACE → MENU → 再开始：全部状态重置、场景树无残留节点 |

---

## 2. 设计意图

### 为什么当前是这种状态

| Issue | 贡献 | 对组装的影响 |
|-------|------|-------------|
| #295 (Main Scene Assembly) | 首次组装 12 组件：Ball/Paddle/ScoringManager/FSM/UI 三屏 + WorldEnvironment/ScoreZones/ScoreFlash | 确立了 Main.tscn 结构、`Game` 根节点名、NodePath export 惯例 |
| #383–#392 | 10 个组件各自独立落地（8 个实现 + 2 个仅文档） | 全部组件按 `get_node_or_null` + `has_signal` 容错模式编写，**显式等待 #393 接线**（注释中反复出现"#393 接线前为 null"） |
| #384/#390 | 文档定稿（DESIGN #414 / PRD #429）但实现未落地 | 组装必须补实现，否则波次循环/转场不可玩 |

### 为什么现在做

1. 10 个前置组件契约全部定稿，8 个已实现落地——组装是"最后一公里"。
2. 所有容错代码（push_warning 占位）都在等待真实接线，此刻清理它们具备唯一正确时机（接线后不存在未接线状态）。
3. `content_ownership: mechanical`——本 Issue 不引入新设计，只按已定稿契约落地 + 编排。

### 先前约束（表：约束 × 细节）

| 约束 | 细节 |
|------|------|
| 不扩展 FSM | DESIGN #386 决策 1：转场/结算不得新增 FSM 状态；呈现层走场景节点消费信号模式 |
| 不修改 WaveController/GameManager 契约 | 转场只消费 `wave_started`；升级 UI 通过 `settle_hold`/`advance_settlement` 接管推进时机 |
| 单一事实源 | 常量全部进 `constants.gd`（`BRICK_*`、`WAVE_TRANSITION_*` 组）；文本零硬编码（#396 JSON） |
| 场景根节点名 | `Game`（e2e_shots.json `state_node=/root/Game/GameStateMachine` 依赖） |
| 层序 | HUD(layer=1) < UpgradePickUI(layer=2) < PauseOverlay(layer=10)；WaveTransition 置于 HUD 之上、PauseOverlay 之下 |

---

## 3. 影响分析

### 直接影响的模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/scenes/Main.tscn` | 主场景 | **核心组装**：新增 BreakoutGrid / WaveController / WaveTransition 节点 + 首波触发接线（36 节点 → ~40 节点） |
| `mini-pong/gdscripts/brick.gd` | #384 | **新建**（DESIGN #414 §4.1）：StaticBody2D，组 `bricks`，`destroy()` 幂等 |
| `mini-pong/gdscripts/breakout_grid.gd` | #384 | **新建**（DESIGN #414 §4.1）：class_name BreakoutGrid，4 布局算法，信号 ×2，upgrade_hooks 注册表，组 `breakout_grids` |
| `mini-pong/scenes/brick.tscn` | #384 | **新建**：StaticBody2D + ColorRect（霓虹材质）+ CollisionShape2D |
| `mini-pong/scenes/breakout_grid.tscn` | #384 | **新建**：Node2D + breakout_grid.gd |
| `mini-pong/gdscripts/wave_transition_controller.gd` | #390 | **新建**（PRD #429 §3）：消费 `wave_started` → 冻结 → 2.0s Tween → 解锁 |
| `mini-pong/scenes/wave_transition.tscn` | #390 | **新建**：CanvasLayer + dim ColorRect + 大字 Label + 副句 Label |
| `mini-pong/gdscripts/constants.gd` | #384/#390 | 追加 `BRICK_SIZE/BRICK_GAP/BRICK_MIN_DIM` 与 `WAVE_TRANSITION_*` 两组常量 |
| `mini-pong/gdscripts/ball.gd` | #384 | `_on_body_entered` 新增 `bricks` 分支（DESIGN #414 §4.2 ~10 行） |
| `mini-pong/gdscripts/game_state_machine.gd` | #393 | 首波触发：SERVING 进入（`previous_state == MENU`）时经 WaveController 启动首波（最小改动，不新增状态） |
| `mini-pong/gdscripts/scoring_manager.gd` | #393 | 移除"BreakoutGrid 未接线"容错 push_warning（接线后不再需要） |
| `mini-pong/gdscripts/wave_controller.gd` | #393 | 移除同类容错；确认组 `wave_controllers` 注册 |
| `mini-pong/gdscripts/game_hud.gd` | #393 | 移除占位符分支（`_on_grid_brick_destroyed` 等容错） |
| `mini-pong/tests/test_main_scene.gd` | #393 | 新增 TC：BreakoutGrid/WaveController/WaveTransition 节点存在性 + 信号接线断言 |
| `mini-pong/tests/test_breakout_grid.gd` | #384 | **新建**（DESIGN #414 §5 契约） |
| `mini-pong/tests/test_wave_transition.gd` | #390 | **新建**（PRD #429 §5 契约） |
| `mini-pong/tests/run_tests.gd` | #393 | 注册 `test_breakout_grid` + `test_wave_transition` |
| `mini-pong/tests/auto_play_test.gd` | #393 | 扩展为带墙多局回归（或新增集成套件）：10 局无错误（AC5） |

### 间接影响的模块

| 模块 | 影响 |
|------|------|
| UpgradePool (autoload) | 首次获得真实 `grid_ref`（组 `breakout_grids`）——升级钩子 open_hole/blast_neighbors 生效 |
| UpgradePickUI | 首次获得真实 WaveController（组 `wave_controllers`）——`advance_settlement` 推进接管生效 |
| RainCurtain | `set_wave_factor` 首次被真实波次驱动（原 wave_controller `_find_rain_curtain` 已解析路径） |
| e2e_shots.json | 若新增波次截图点位需扩展 shot plan（loop 原型已覆盖 gdscripts/scenes 变更，自动命中） |
| docs/GAME_DESIGN/ | 组装完成后补 GDD 章节（24-WAVE-CYCLE 可加"组装状态"标记） |

### 数据流影响（组装后完整循环）

```
StartMenu SPACE
    ▼
FSM MENU → SERVING (首波触发) ──► WaveController.start_first_wave()（组装新增）
    │                                 ├── GameManager.begin_wave() → wave_started(1) ──► WaveTransition「第 1 道墙」2s
    │                                 │                                              ──► GameHUD 波次号
    │                                 └── BreakoutGrid.generate_wave(1, GAPS, -1) ──► wall_generated ──► HUD 剩余砖数
    ▼
PLAYING: Ball 碰砖 → body.is_in_group("bricks") → brick.destroy()
    │         └── BreakoutGrid.brick_destroyed ──► ScoringManager._on_brick_destroyed → add_score(+1 brick)
    │                                            ──► HUD 剩余砖数 -1
    ▼
BreakoutGrid.wall_cleared() ──► WaveController._on_wall_cleared
    │                            ├── GameManager.settle_wave() → wave_settled(i) ──► UpgradePickUI.open(3 选 1)
    │                            │                                                   └── settle_hold=true
    │                            └── (等待 advance_settlement)
    ▼
UpgradePickUI 确认 → UpgradePool.apply(id)（含 grid 钩子）→ reveal → close()
    └── WaveController.advance_settlement() → begin_wave(i+1) → 更厚新墙 + AI 收紧（难度杠杆）
    ▼
（循环）… 任一方 21 分 → GameManager.match_over ──► FSM GAME_OVER ──► GameOverScreen（win/fail + run 数据）
```

### 需更新的文档

- [x] 本 PRD（`docs/PRD/393-main-scene-assembly.md`）
- [ ] `docs/GAME_DESIGN/24-WAVE-CYCLE.md` — 补充"组装状态"（可选，GDD 更新归后续 commit）
- [ ] `docs/PROJECT.md` — 组件清单勾选（若项目惯例要求）

---

## 4. 方案对比

组装策略对比（Patch 20：Assembly PRD 的 Solution Comparison 对比组装策略，而非新组件架构——组件架构已由 #384/#390 文档定稿）：

### Approach A：增量组装 + 契约落地（推荐）

按已定稿契约补实现缺失组件（#384/#390），然后增量修改 Main.tscn：

1. 实现 `brick.gd` / `breakout_grid.gd` / `brick.tscn` / `breakout_grid.tscn`（DESIGN #414 契约逐条落地）
2. 实现 `wave_transition_controller.gd` / `wave_transition.tscn` + 常量组（PRD #429 契约）
3. Main.tscn 实例化 3 个新节点 + FSM 首波触发 + 清理容错代码
4. 测试：新建 2 套件 + 扩展 test_main_scene + auto_play 10 局回归

- **Pros:** 所有组件契约已定稿（DESIGN #414 含精确文件清单/布局算法/测试契约），实现即落地无设计决策；容错代码清理时机唯一正确；风险最低（每个组件独立可测）
- **Cons:** 组装 PR 体积大（2 个新组件 + 接线）；需按 DESIGN #414 §5 测试契约补全
- **Risk:** Low（契约已定稿；#386/#388/#392 的 mock 测试已验证契约子集）
- **Effort:** 2–3 天（组装）+ 1–2 天（#384 实现）+ 1 天（#390 实现）

### Approach B：拆分实现——先补 #384/#390 实现，再单独组装

先以独立 PR 落地 #384/#390 实现（各自带测试），#393 只做接线。

- **Pros:** PR 体积小、审查粒度细；每个实现 PR 独立可验证
- **Cons:** #384/#390 已关闭——需重开或新建实现 Issue，破坏"#393 一个 PR 完成组装"的意图；且两个组件实现时 Main.tscn 无节点，容错代码继续存在，产生中间态
- **Risk:** Med（流程绕路；workflow label 链需重新编排）
- **Effort:** 3–4 天（串行两个 PR + 组装 PR）

### Approach C：从零重建 Main.tscn

废弃现有 36 节点场景，按 GDD/PRD 重新手写场景文件。

- **Pros:** 场景结构可完全按最终目标组织
- **Cons:** 丢失既有 26 节点资产（布局/NodePath/材质引用/测试断言全部重写）；test_main_scene.gd TC1–TC21 全部失效；e2e_shots.json 路径依赖 `Game` 根节点；改动面失控
- **Risk:** High（回归面大，违背"不重复造轮子"与既有测试基线）
- **Effort:** 3+ 天（重写 + 全量回归）

### 推荐

**Approach A。** 理由：

1. 组件契约全部定稿（#384 DESIGN #414 含 §4.1 文件清单 + §4.3 布局算法 + §5 测试契约；#390 PRD #429 含 §3 文件清单 + §4 推荐方案 + §5 AC 映射）——实现即落地，无设计决策空间；
2. 8/10 组件已落地且**全部按"等待 #393 接线"编写**（容错模式），接线是它们唯一缺失的环节；
3. 与 Issue 语义一致："将 1-10 全部组件接入 Main.tscn"——#384/#390 的"接入"天然包含让它们存在；
4. 首波触发、组注册（`breakout_grids`/`wave_controllers`）、容错清理三点是本 PR 的独有增量，任何其他策略都无法回避。

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 5 条 AC）

- [x] **AC1: Main.tscn 可直接运行完整一局，不需要额外手工连线**
  - 验证：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；手动运行 Main.tscn 从 MENU → SPACE → 首波墙生成 → 对打
  - 验证：test_main_scene 新增 TC 断言 BreakoutGrid/WaveController/WaveTransition 节点存在且信号已连接
- [x] **AC2: 墙清空→波次结算→升级→新墙→AI 增强的循环完整**
  - 验证：集成测试直调 `WaveController._on_wall_cleared()`（mock grid）→ `wave_settled` → UpgradePickUI 打开 → 确认 → `advance_settlement` → `begin_wave`（wave_index+1）→ `generate_wave(更厚)` → AI 参数收紧断言（沿用 test_wave_cycle 既有模式）
  - 验证：首波触发——FSM SERVING（首次）→ `begin_wave(1)` + `generate_wave`（新测试覆盖）
- [x] **AC3: HUD 分数/波次/剩余砖数随信号实时更新**
  - 验证：test_hud 扩展：brick_destroyed → 剩余砖数 label；wave_started → 波次 label；score_changed → 总分 label（真实 BreakoutGrid 或 mock grid 均可）
- [x] **AC4: 失败屏与获胜状态均可到达，无孤立信号或错误**
  - 验证：player/ai 到 21 分 → `match_over` → GAME_OVER 屏；`wave_started` 有 WaveTransition 消费者（无孤立信号——`grep` 全信号连接核对）
  - 验证：转场期间无 push_warning/错误输出
- [x] **AC5: 运行 10 局无脚本错误/空引用，场景树无泄漏**
  - 验证：auto_play_test 扩展为带 BreakoutGrid 的连续多局（或新集成套件 10 局循环）；每局后断言场景树无残留砖节点、无悬挂协程
  - 验证：全量测试套件 `=== TOTAL: N passed, 0 failed ===`

### 边界条件（Edge Cases）

1. **首波（wave 1）**：FSM MENU→SERVING 首次进入触发首波；重开（GAME_OVER → MENU → SPACE）后 `reset_match()` 重置 wave_index=0 → 再次首波从 1 起
2. **终局竞态**：升级 reveal 期间到 21 分 → `end_wave_cycle` 分支（wave_controller 已处理 `is_run_over` 守卫，不生成新墙）
3. **穿墙判定与砖墙共存**：球穿越墙带缺口（HOLES 布局）→ `_crossed_wall` 置位 → 出界 3 分（#385 已落地；组装不改动）
4. **同帧砖碎 + 出界**：ScoringManager `_brick_destroyed_this_frame` 守卫已落地（#385 AC4），组装不回归
5. **转场期间输入**：WaveTransition 持转场锁，忽略 `ui_cancel`/状态切换（PRD #429 边界 4）；ball frozen 标志已存在（#391）
6. **WAVE_MAX_INDEX 防御**：99 波上限（#386），实际 21 分制远早触发
7. **UpgradePool 网格引用**：grid 落地后 `grid_ref` 惰性解析首次命中——旧存档/测试无 grid 时保持 null 容错（不回归）
8. **e2e 状态机路径**：`state_node=/root/Game/GameStateMachine` 不变；若新增波次截图点位需同步 e2e_shots.json

### 失败路径

1. **#384/#390 实现与契约偏差**：DESIGN #414 的 API（generate_wave/clear_wall/brick_destroyed/wall_cleared/register_upgrade_hook）是 5 个下游消费方的契约——实现必须逐条对齐，否则下游 has_signal/has_method 守卫静默降级（测试用真实 grid 断言信号发射）
2. **首波触发接入点错误**：若在 StartMenu 触发而非 FSM SERVING，重开路径可能二次触发——用 `previous_state == MENU` 守卫（FSM 既有语义）
3. **转场/升级 UI 层序冲突**：WaveTransition(layer 2–9) 与 UpgradePickUI(layer 2) 需明确先后；波次时序上二者不重叠（wave_started 与 wave_settled 分属相邻波次），但层序需在场景中显式设定
4. **10 局回归超时**：auto_play 带真实网格可能拉长——沿用 test_wave_cycle 的短延时注入（settle_delay 测试注入）

---

## 6. 依赖与阻塞

### 依赖链

```
#383 (轴交换+竖屏) ──► #384 (砖墙) ──► #385 (双得分) ──► #386 (波次) ──► #388 (升级UI) ─┐
        │                │                │                 └──► #390 (转场) ──────────┤
        │                └──► #389 (雨幕) ─────────────────────────────────────────────┼──► #393 (组装)
        └──► #387 (升级池) ────────────────────────────────────────────────────────────┘
                          #391 (失败屏) ──► #392 (霓虹HUD) ─────────────────────────────┘
```

| 依赖 | 状态 | 风险 |
|------|:----:|------|
| #383 轴交换+竖屏 | ✅ 已合并 (PR #409) | Low |
| #384 砖墙系统 | ⚠️ 文档已合并 (PRD #411 + DESIGN #414)，**实现未落地** | **High — 本 PR 补实现** |
| #385 双得分制 | ✅ 已合并 (PR #424) | Low |
| #386 波次循环 | ✅ 已合并 (PR #428) | Low — WaveController 需实例化 |
| #387 升级池 | ✅ 已合并 (PR #423) | Low — grid 组契约待满足 |
| #388 升级UI | ✅ 已合并 (PR #440) | Low |
| #389 动态雨幕 | ✅ 已合并 (PR #416) | Low |
| #390 波次转场 | ⚠️ PRD #429 已合并（无 DESIGN），**实现未落地** | **High — 本 PR 补实现** |
| #391 失败屏 | ✅ 已合并 (PR #439) | Low |
| #392 霓虹HUD | ✅ 已合并 (PR #438) | Low |

### 阻塞

无外部阻塞。内部顺序约束：先落地 #384/#390 实现（各自可测）→ 再 Main.tscn 组装 → 再容错清理 → 最后全量回归。

### 准备工作

- [x] 阅读 DESIGN #414（#384 契约：文件清单/布局算法/测试契约）
- [x] 阅读 PRD #429（#390 契约：推荐方案 A/A/A + 常量组 + AC 映射）
- [x] 核对 5 处消费方容错代码（scoring_manager/wave_controller/game_hud/upgrade_pool/brick_upgrade_hooks）
- [x] 核对 test_main_scene.gd 既有 TC 基线（TC1–TC21 不得回归）
- [ ] implement 阶段按 §8 延续上下文执行

---

## 7. Spike / 实验

**Skipped per depth/standard label**（Issue 无 depth/deep；组件技术路线已被 #384 DESIGN #414 与 #390 PRD #429 的既有 spike 覆盖——#414 的布局算法与 #429 的暂停机制/Tween 三段式均已研究定稿）。研究期已验证的替代方案：
- #384 布局算法：GAPS/OFFSET/HOLES/MIXED 四布局（#414 §4.3 已定稿，无需再 spike）
- #390 暂停机制：Approach A 演员冻结（ball.frozen 已由 #391 落地）vs Approach B 全局暂停 vs Approach C FSM 状态（#429 已选 A，理由记录在案）
- 组装策略三选一：本 PRD §4 已对比（A 增量组装胜出）

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- **已落地（8/10）：** #383 竖屏、#385 双得分、#386 波次脚本（未实例化）、#387 升级池 autoload、#388 升级 UI（实例化）、#389 雨幕（实例化）、#391 失败屏（实例化）、#392 霓虹 HUD（实例化）
- **未落地（2/10）：** #384 BreakoutGrid（有 DESIGN #414 完整契约）、#390 WaveTransition（有 PRD #429 完整契约）
- **Main.tscn 现状：** 36 节点、26 个命名节点；缺 BreakoutGrid / WaveController / WaveTransition 三个节点；零 `[connection]` 段（全部信号在 `_ready()` 代码连接）
- **容错代码待清理：** `scoring_manager.gd:50`、`wave_controller.gd:22`、`game_hud.gd:192` 的 "BreakoutGrid 未接线（#393 前）" push_warning

### 组装实施顺序（plan agent 按此排序）

1. **常量先行**：constants.gd 追加 `BRICK_SIZE/BRICK_GAP/BRICK_MIN_DIM`（#384）+ `WAVE_TRANSITION_*`（#390）两组
2. **#384 实现**（按 DESIGN #414 §4.1/§4.3/§5）：brick.gd → brick.tscn → breakout_grid.gd（含 `add_to_group("breakout_grids")`、upgrade_hooks 注册表、四布局算法）→ breakout_grid.tscn → ball.gd `bricks` 分支 → test_breakout_grid.gd 注册
3. **#390 实现**（按 PRD #429 §3/§4）：wave_transition_controller.gd → wave_transition.tscn → test_wave_transition.gd 注册（ball.frozen 已存在，无需改动）
4. **Main.tscn 组装**：实例化 BreakoutGrid（组 breakout_grids）/ WaveController（组 wave_controllers）/ WaveTransition（层序 HUD 之上）；FSM NodePath exports 不变（新节点走代码寻址 + 组）
5. **首波触发**：FSM SERVING 进入（`previous_state == MENU`）→ WaveController 新增 `start_first_wave()`（或复用 `_advance_wave()` 逻辑）→ `begin_wave(1)` + `generate_wave`；GAME_OVER→MENU 重开路径复用同一入口
6. **容错清理**：三处 push_warning 容错分支移除/降级（接线后无未接线状态）；保留 `get_node_or_null` 防御（防测试场景缺节点）
7. **测试**：test_main_scene 新增节点存在性 + 接线 TC；test_breakout_grid/test_wave_transition 注册；auto_play 扩展 10 局（AC5）回归
8. **回归**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；e2e shot plan 确认

### 主要风险

1. **#384/#390 契约偏差**——实现必须逐条对齐 DESIGN #414 / PRD #429 的 API 与信号（5 个下游消费方依赖）；用真实 grid 的集成测试兜底
2. **首波触发接入点**——FSM SERVING + `previous_state == MENU` 守卫，防重开二次触发
3. **转场/升级 UI 层序**——WaveTransition 与 UpgradePickUI 层序显式设定（转场 layer 建议 3，位于 HUD(1) 与 PauseOverlay(10) 之间）

### plan agent 交接清单

- DESIGN 输出路径：`docs/DESIGN/393-main-scene-assembly.md`
- 实现契约源：DESIGN #414（§4.1 文件清单、§4.3 布局算法、§5 测试契约）+ PRD #429（§3 文件清单、§4 推荐方案、§5 AC 映射）+ 本 PRD §8 顺序
- 测试基线：test_main_scene TC1–TC21 不得回归；新增 3 套件（grid/transition/main-scene 扩展）+ auto_play 10 局
- e2e：若加波次截图点位，同步 `mini-pong/e2e_shots.json`（state_node 不变）

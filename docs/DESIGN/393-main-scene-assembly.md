# DESIGN: [Integration] 主场景组装 (Main Scene Assembly)

> **Parent Issue:** #393
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — 增量组装 + 缺口补齐（确认 PRD §4.1 推荐；内含 #384 BreakoutGrid 与 #390 WaveTransition 两个契约落地，实施粒度决策同 PRD §6.2）
> **Reference PRD:** docs/PRD/393-main-scene-assembly.md（research PR #441，已合并）
> **所有权:** `content_ownership: mechanical`（场景节点组装/信号接线/常量收敛为纯机械实现；波次数值、文案、配色归 taste-draft Issue）
> **深度:** depth/standard（Issue 无 depth 标签，按 PRD 惯例）—— 产出 DESIGN + TASKS；**测试仅描述，不写可运行测试代码**

---

## 1. 概述

Mini Pong（`mini-pong/`，Godot 4.7.1，720×1280 竖屏）的 10 个前置组件（#383–#392）中 8 个已实现并各自交付，但 **Main.tscn 从未整体组装**：8 个组件实例已挂载，缺 3 个节点接线（BreakoutGrid / WaveController / WaveTransition），失败屏内联节点落后于 #391 实现，且 #384（砖墙）与 #390（波次转场）**代码从未落地**（仅契约文档）。本设计按 PRD 推荐 Approach A 完成：

1. **契约落地 #384**：按 `docs/DESIGN/384-breakout-grid-brick-wall.md`（PR #414）逐条落地 `brick.gd/tscn` + `breakout_grid.gd/tscn` + `ball.gd` bricks 分支 + `BRICK_*` 常量组（API/信号/参数已定稿，零设计歧义）
2. **契约落地 #390**：按 `docs/PRD/390-wave-transition.md` §4 推荐组合（演员冻结 + Tween 三段式 + 分档选句）落地 `wave_transition_controller.gd` + `wave_transition.tscn` + `WAVE_TRANSITION_*` 常量组
3. **Main.tscn 组装**：挂入 BreakoutGrid / WaveController / WaveTransition 三节点；失败屏内联节点树换为 `ui_game_over.tscn` 实例；8 个已落地组件**零逻辑改动**

组装完成后形成完整可玩闭环：**墙清空 → 波次结算 → 升级 → 新墙 → AI 增强 → 21 分终局**（AC2），HUD 实时更新（AC3），失败屏/获胜双分支可达（AC4），10 局无错误（AC5）。

### 设计哲学

1. **增量组装，缺口补齐**（Approach A 确认）：在现有 Main.tscn 节点树基础上只做加法 + 两处定点修正；否决 Approach B（从零重建，回归面爆炸）与 Approach C（缺组件不组装，验收不通过）——与 #295 旧版组装先例同法
2. **契约即代码**：#384 DESIGN / #390 PRD 已把 API、信号、常量、边界全部定稿——本 Issue 是**执行层**，不重设计（Patch 19 参数契约→执行层模式，先例 #217）
3. **接线零破坏面**：全部消费方（ScoringManager / WaveController / GameHUD / UpgradePickUI）已用 `get_node_or_null` + `has_signal`/`has_method` 双守卫写好容错——节点一挂即自动接线，未挂也不崩
4. **FSM 不变项**：不扩展 FSM（DESIGN #386 决策 1）；转场/升级/失败屏全部走信号消费模式，呈现层与状态机解耦
5. **层序常量收敛**：Atmosphere 0 / HUD 1 / Upgrade 2 / **Transition 3** / Pause 10——转场层按 PRD §8 Phase 3 建议设为 3，高于升级 UI(2)、低于暂停层(10)
6. **测试即验收**：新测试注册进 `run_tests.gd`；`godot --headless --script tests/run_tests.gd` 全绿（基线 1781 用例，PRD 2026-08-13 实跑）；本 PR 只描述用例，implement 写代码

### 1.1 关键事实（plan agent 已对照源码 + headless 实跑核实）

| 事实 | 核实结果 |
|------|---------|
| `Main.tscn` 现状（headless 实例化实测） | `BreakoutGrid` / `WaveController` / `WaveTransition` **均不存在**；`GameOverScreen` 为内联 CanvasLayer 节点树，**缺** `FailurePhraseLabel` / `RunStatsLabel`（`get_node_or_null` 兜底不崩但文本不显示）；UpgradePickUI / GameHUD 实例存在 |
| **UpgradePickUI layer（PRD 断言修正）** | `ui_upgrade_pick.tscn` 根节点**已设 `layer = 2`**（commit aba2487, PR #440），Main.tscn 实例无 layer 覆盖 → 实例**继承 layer==2**（headless 实测 `UpgradePickUI.layer == 2`）——PRD「实例 layer 未设（默认 1）」**已过时**，组装时**无需改动**，只补断言 |
| **ball.gd frozen（PRD #390 依赖修正）** | `frozen: bool` + `func set_frozen(value)` **已存在**（#391 PR #439 交付，终局软冻结）——波次转场演员冻结**直接复用既有 API**，ball.gd 仅需新增 bricks 碰撞分支，无需再加冻结标志 |
| paddle.gd | `frozen` + `set_frozen(value)` 已存在（#296 冻结惯例）——转场可冻结双拍 |
| autoload | `project.godot [autoload]`：`GameManager` / `AudioEngine` / `UpgradePool` 已注册（`*res://gdscripts/*.gd`）——**不创建对应场景节点**；`run/main_scene="res://scenes/Main.tscn"` |
| 消费方守卫就绪 | `scoring_manager.gd`：`@onready var breakout_grid = get_node_or_null("../BreakoutGrid")` + `brick_destroyed` 容错连接；`wave_controller.gd`：`../BreakoutGrid`（wall_cleared）+ `../AIPaddle` + `../AtmosphereLayer/RainCurtain` 三引用 + `generate_wave` has_method 守卫；`game_hud.gd`：`../BreakoutGrid` 3 信号（brick_destroyed/wall_cleared/wall_generated）守卫消费；`upgrade_pick_ui.gd`：`GameManager.wave_settled.connect(open)` + `group("wave_controllers")` 寻址 `advance_settlement`（节点挂载后自动激活） |
| 碰撞层 | `ball.tscn`：`collision_layer=4`(bit 3)、`collision_mask=3`(bit 1+2)——**砖放 layer 2 零配置生效**（DESIGN #384 已核查） |
| 失败屏换实例可行性 | `ui_game_over.tscn`（PR #439 交付）根 = CanvasLayer `layer=1` `visible=false` + `game_over_screen.gd`；节点路径 `CenterContainer/VBoxContainer/{WinnerLabel, FailurePhraseLabel, RunStatsLabel, Spacer, RestartPromptLabel}` 与 `game_over_screen.gd` 的 `@onready` 路径**逐一匹配**（含两个 get_node_or_null 容错引用）→ 换实例后脚本零改动 |
| FSM NodePath | `game_state_machine.gd`：`$"../GameOverScreen"` / `$"../GameHUD"` / `$"../StartMenu"` 等——**节点名必须保持** `GameOverScreen` / `GameHUD` |
| 内容资源 | `mini-pong/content/wave_failure_text.json`（schema `wave-failure-text/v1`）含 `wave_subtitles` ws1–ws4 + `failure_phrases` fp1–fp4——转场/失败屏只读消费，零硬编码（AC5 红线） |
| 常量现状 | `constants.gd` 已有 `GRID_WALL_Y=640` / `WALL_BAND_HALF_HEIGHT=22`（#385）、`WAVE_*` 组（#386）、`UPGRADE_UI_LAYER=2`（#388）——**无 `BRICK_*` / `WAVE_TRANSITION_*` 组**（缺口） |
| 测试基线 | `run_tests.gd` 注册 20 套件；PRD 实跑 **1781 passed / 0 failed**（2026-08-13）——组装后需全量回归 + 波次路径重验 |

### 1.2 与 PRD 的差异决策（plan 定稿）

| PRD 断言 / 待决项 | 本设计定稿 | 理由 |
|------------------|-----------|------|
| UpgradePickUI 实例 layer 未设（§1.1 Phase 1 / §8 Phase 3 step 5） | **无需改动**——实例继承 `ui_upgrade_pick.tscn` 根 layer=2（headless 实测） | PRD 断言基于 #388 合并前的旧状态；实测已满足，改动反而多余 |
| #390 转场需 ball.gd 新增 frozen 标志（PRD #390 §4.1） | **复用 #391 已交付的 `frozen` + `set_frozen`**——ball.gd 只加 bricks 分支 | 冻结能力已存在（终局软冻结），转场直接调用 `set_frozen(true/false)` |
| BreakoutGrid 节点挂载位置（PRD §8 Phase 3） | **直挂 Game 根**，`position=(0, 640)`（wall_y 导出默认 `GRID_WALL_Y=640`，砖行以 world y=640 垂直居中） | 与 WaveController `../BreakoutGrid` / ScoringManager `../BreakoutGrid` / HUD `../BreakoutGrid` 相对路径全部解析；x=0 使布局算法坐标即世界坐标（DESIGN #384 §4.3 铺满断言直接成立） |
| 转场层序（PRD §8 建议 layer=3） | **确认 layer=3**（Atmosphere 0 < HUD 1 < Upgrade 2 < Transition 3 < Pause 10） | 高于升级 UI、低于暂停层；遮挡面零交集（PRD §5 风险 4 缓解） |
| `BRICK_*` 组是否重复定义 `GRID_WALL_Y` | **不重复**——引用既有 `GRID_WALL_Y`（#385）；`BRICK_*` 组只新增 `BRICK_SIZE` / `BRICK_GAP` / `BRICK_MIN_DIM` | 单一事实源（#295 原则） |
| 失败屏换实例 vs 补齐内联 Label（PRD §1.1 两选项） | **换 `ui_game_over.tscn` 实例**（节点名 `GameOverScreen`、layer=1、visible=false 覆盖保留） | 消除内联与实现的双份漂移（#391 交付物被闲置）；脚本路径逐项匹配已核实 |

---

## 2. 现有组件修改 — 详细设计

### 2.1 `mini-pong/gdscripts/constants.gd`（修改 — 两个常量组，纯增量）

新增「── Brick Wall (#384) ──」组（置于 Colors 组之后；**不重复** `GRID_WALL_Y`——既有 #385 常量）：

```gdscript
# ── Brick Wall (#384) ──
# 砖墙系统 (PLAN-rogue-pong §2.2; mechanical; 数值归 taste-draft)
const BRICK_SIZE: Vector2 = Vector2(64.0, 24.0)   # 单砖尺寸（DESIGN #384 §4.2）
const BRICK_GAP: float = 4.0                      # 砖缝（DESIGN #384 §4.2）
const BRICK_MIN_DIM: float = 14.0                 # 防隧穿下限（球速上限 627px/s → 单帧 10.5px）
# GRID_WALL_Y / WALL_BAND_HALF_HEIGHT 已由 #385 定义，此处引用不重复
```

新增「── Wave Transition (#390) ──」组（PRD #390 §4 推荐表逐条落地）：

```gdscript
# ── Wave Transition (#390) ──
# 波次转场 (PLAN-rogue-pong §L3; mechanical; 时长三段和恒=2.0 AC2；字号/描边 taste-draft 可调)
const WAVE_TRANSITION_FADE_IN: float = 0.5
const WAVE_TRANSITION_HOLD: float = 1.0
const WAVE_TRANSITION_FADE_OUT: float = 0.5      # 三段和恒 == 2.0（AC2，常量注释 + 测试双保险）
const WAVE_TRANSITION_TITLE_FONT_SIZE: int = 112 # 大字「第 N 道墙」字号（720×1280）
const WAVE_TRANSITION_SUBTITLE_FONT_SIZE: int = 40
const WAVE_TRANSITION_OUTLINE_SIZE: int = 10     # LabelSettings 描边（AC4）
const WAVE_TRANSITION_JSON_PATH: String = "res://content/wave_failure_text.json"  # #396 唯一内容源
const WAVE_TRANSITION_DECISIVE_SCORE: int = 18   # 决胜波阈值（任一方 ≥ 此值 → ws4 覆盖）
const WAVE_TRANSITION_LAYER: int = 3             # 转场层序（Atmosphere 0 < HUD 1 < Upgrade 2 < 本层 3 < Pause 10）
# 波次分档边界（对应 ws1/ws2/ws3）：1-2 / 3-5 / 6+（机械占位，与 #396 context 对齐）
const WAVE_TRANSITION_BAND1_MAX: int = 2
const WAVE_TRANSITION_BAND2_MAX: int = 5
```

### 2.2 `mini-pong/gdscripts/ball.gd`（修改 — bricks 分支，~10 行增量）

`_on_body_entered` 现有 walls 分支旁新增 bricks 分支（DESIGN #384 §4.2 契约；**不调用音频**——play_brick_break 归 #392 已定稿不引入）：

```gdscript
# ── Bricks (#384) ── 砖墙碰撞：dominant-axis 反弹 + 原子销毁（#393 组装契约）
if body.is_in_group("bricks"):
	if _bounce_cooldown > 0:
		return
	if abs(velocity.x) >= abs(velocity.y):
		velocity.x = -velocity.x
	else:
		velocity.y = -velocity.y
	_bounce_cooldown = BOUNCE_COOLDOWN_FRAMES
	if body.has_method("destroy"):
		body.destroy()
	return
```

**不改动**：`frozen` / `set_frozen`（#391 已交付，转场直接复用）、`_is_serving`、walls/paddles 分支、得分/墙带判定逻辑。

### 2.3 `mini-pong/scenes/Main.tscn`（组装 — 核心）

目标节点树（新增/替换以 ★ 标记；节点名全部保持既有契约）：

```
Game (Node2D)
├── WorldEnvironment (instance world_environment.tscn)
├── AtmosphereLayer (CanvasLayer layer=0)
│   └── RainCurtain (instance rain_curtain.tscn)
├── LeftWall / RightWall (StaticBody2D, groups=[walls])
├── Ball (instance ball.tscn)
├── PlayerPaddle (instance player_paddle.tscn)
├── AIPaddle (instance player_paddle.tscn, mode=1)
├── ★ BreakoutGrid (instance breakout_grid.tscn, position=(0, 640))   ← #384 落地
├── ScoringManager (scoring_manager.gd)
├── GameStateMachine (game_state_machine.gd — NodePath 全部不变)
├── ScoreZoneTop / ScoreZoneBottom
├── ScoreFlash
├── StartMenu (CanvasLayer layer=1 内联)
├── GameHUD (instance ui_game_hud.tscn, layer=1)
├── ★ GameOverScreen (替换为 instance ui_game_over.tscn；layer=1, visible=false 覆盖保留)  ← #391 实例化
├── ★ WaveController (Node + wave_controller.gd)                       ← #386 挂载
├── ★ WaveTransition (CanvasLayer layer=3, visible=false + wave_transition_controller.gd)  ← #390 落地
├── PauseOverlay (CanvasLayer layer=10)
└── UpgradePickUI (instance ui_upgrade_pick.tscn — layer=2 实例继承，已验证，无改动)
```

组装清单（implement 逐条执行）：

| # | 操作 | 说明 |
|---|------|------|
| 1 | 添加 `BreakoutGrid` 实例 | `[ext_resource] breakout_grid.tscn`；节点直挂 Game 根，`position = Vector2(0, 640)`；`wall_y` 导出默认 640（常量 `GRID_WALL_Y`），砖行世界坐标垂直居中 |
| 2 | 添加 `WaveController` 节点 | `[ext_resource] wave_controller.gd`；直挂 Game 根——`../BreakoutGrid` / `../AIPaddle` / `../AtmosphereLayer/RainCurtain` 三相对路径即解析（`_find_rain_curtain` 主路径命中） |
| 3 | 添加 `WaveTransition` 实例 | `[ext_resource] wave_transition.tscn`；CanvasLayer `layer = 3`（`WAVE_TRANSITION_LAYER`）、`visible = false` 初始隐藏 |
| 4 | 失败屏换实例 | 删除内联 `GameOverScreen` 子树（WinnerLabel/Spacer/RestartPromptLabel），替换为 `instance ui_game_over.tscn`；**节点名保持 `GameOverScreen`**、覆盖 `layer = 1`、`visible = false`——FSM `$"../GameOverScreen"` 与 `_set_ui("game_over")` 显隐逻辑零改动 |
| 5 | UpgradePickUI | **无改动**（实例已继承 layer=2，headless 实测）——仅测试断言 |
| 6 | 清理 | 移除任何临时调试代码/孤立节点（PRD Issue body 要求「清理临时调试代码」） |

### 2.4 `mini-pong/tests/run_tests.gd`（修改 — 注册 2 个新套件）

在 `test_ball.gd` 之后注册 `Breakout Grid`（`_run("res://tests/test_breakout_grid.gd", "Breakout Grid")`）；在 `test_wave_cycle.gd` 附近注册 `Wave Transition`（`_run_async("res://tests/test_wave_transition.gd", "Wave Transition")`——沿用 await 模式，与既有套件一致）。

### 2.5 `mini-pong/tests/test_main_scene.gd`（修改 — 组装断言）

在既有 TC 基础上追加（用例描述见 §9 Scenario A；implement 写代码时对照）：

- 新增 TC：`BreakoutGrid` 节点存在（Node2D）、`position.y == 640`、`wall_y` 导出 == 640
- 新增 TC：`WaveController` 节点存在且脚本 `wave_controller.gd` 已挂；实例化后 `wall_cleared` 连接成立（或断言 `_ready` 无 push_warning 路径——以守卫语义为准）
- 新增 TC：`WaveTransition` 节点存在、`CanvasLayer.layer == 3`、初始 `visible == false`
- 新增 TC：`GameOverScreen` 存在 `CenterContainer/VBoxContainer/FailurePhraseLabel` 与 `RunStatsLabel`（换实例生效证明）；`layer == 1`、`visible == false`、节点名不变
- 新增 TC：`UpgradePickUI.layer == 2`（实例继承断言）
- 既有 TC1 节点清单断言无需删除（新节点为增量）

### 2.6 受影响测试文件清单（implement 改造面）

| 文件 | 改动性质 |
|------|---------|
| `tests/test_breakout_grid.gd` | **新建**（§9 Scenario F 用例） |
| `tests/test_wave_transition.gd` | **新建**（§9 Scenario G 用例） |
| `tests/test_ball.gd` | **追加**砖块反弹用例（侧击翻 X / 顶底翻 Y / 砖移除） |
| `tests/test_main_scene.gd` | **追加**组装节点断言（§2.5） |
| `tests/run_tests.gd` | **注册** 2 新套件 |
| `tests/test_hud.gd` / `test_wave_cycle.gd` / `test_scoring_manager.gd` / `test_dual_scoring.gd` / `test_upgrade_pool.gd` / `test_rain.gd` / `auto_play_test.gd` | **回归**（grid 信号激活后断言不再走占位路径）——预期零改动或仅断言同步 |

---

## 3. 新建文件（实现期）

> 全部按既有契约定稿实现，本设计不引入新 API。

### 3.1 `mini-pong/gdscripts/brick.gd` + `mini-pong/scenes/brick.tscn`（#384 落地）

- `extends StaticBody2D`；`_ready()`：`add_to_group("bricks")`、`collision_layer = 2`、`collision_mask = 0`
- `var grid: Node`（BreakoutGrid 实例化时注入）；`var _destroyed: bool = false`
- `func destroy() -> void`：幂等（`_destroyed` 守卫）→ `is_instance_valid(grid)` 后通知 `grid._on_brick_destroyed(self)` → `queue_free()`
- `brick.tscn`：StaticBody2D 根（挂 brick.gd）+ ColorRect（复用 `assets/neon_glow_material.tres`）+ CollisionShape2D（RectangleShape2D 64×24）
- 参照：DESIGN #384 §4.1

### 3.2 `mini-pong/gdscripts/breakout_grid.gd` + `mini-pong/scenes/breakout_grid.tscn`（#384 落地）

- `extends Node2D`；`class_name BreakoutGrid`
- **@export**：`brick_size`（默认 `CONSTS.BRICK_SIZE`）、`brick_gap`、`layout: BrickLayout`（enum `{GAPS, OFFSET, HOLES, MIXED}`）、`rows`（默认 3 机械占位）、`hole_count`、`hole_seed`、`wall_y`（默认 `CONSTS.GRID_WALL_Y`）、`brick_scene`（默认 `res://scenes/brick.tscn`）
- **信号**：`brick_destroyed(brick: Node2D, pos: Vector2)`、`wall_cleared()`、`wall_generated(remaining: int)`（#392 契约增补，DESIGN #384 附录 A）
- **状态**：`remaining_bricks: int`（只读语义）、`_wall_cleared_emitted: bool`、`_destroyed: Dictionary`（按砖对象身份去重）
- **API**：`generate_wave(thickness, layout, seed)`（先 `clear_wall()` → 布局算法实例化 → 重置计数/守卫/集合 → 末尾 `wall_generated.emit(remaining_bricks)`）；`clear_wall()`（快照遍历 queue_free + 重置）；`_on_brick_destroyed(brick)`（去重 → 递减 → 两信号；归零时 `wall_cleared` 恰好一次）
- **布局**：`cols = floor(SCREEN_WIDTH / (brick_size.x + brick_gap))`；GAPS 留缝 / OFFSET 奇数行偏移 `(size.x+gap)/2` 且边缘 clamp / HOLES 柱位不实例化（穿墙路径）/ MIXED 组合；两轴 `max(size, BRICK_MIN_DIM)` clamp
- `breakout_grid.tscn`：Node2D 根 + 脚本；独立可实例化
- 参照：DESIGN #384 §4.1/§4.3

### 3.3 `mini-pong/gdscripts/wave_transition_controller.gd` + `mini-pong/scenes/wave_transition.tscn`（#390 落地）

- `extends CanvasLayer`（挂在场景根）；连接 `GameManager.wave_started`（autoload 信号，`has_signal` 守卫）→ `_on_wave_started(index)`
- **演员冻结**（Approach A）：`../Ball` `set_frozen(true)` + `../PlayerPaddle` / `../AIPaddle` `set_frozen(true)`（`get_node_or_null` + `has_method` 守卫；ball 的 frozen API 由 #391 提供，零新增）；结束时解冻
- **选句**（Approach A）：`FileAccess` + `JSON.parse_string` 读 `WAVE_TRANSITION_JSON_PATH` 的 `wave_subtitles`；任一方比分 ≥ `WAVE_TRANSITION_DECISIVE_SCORE`(18) → ws4 覆盖；否则按 `wave_index` 分档（≤2→ws1 / ≤5→ws2 / 6+→ws3）；JSON 缺失/解析失败 → 副句留空 + `push_warning` 一次
- **呈现**（Approach A）：Tween 三段 `modulate:a` 0→1（FADE_IN 0.5）→ `tween_interval`（HOLD 1.0）→ 1→0（FADE_OUT 0.5），总时长恒 2.0s；结束回调 → 解冻 + 隐藏；`_transitioning` 重入守卫 + `is_inside_tree()` 兜底解锁（防卡死）
- `wave_transition.tscn`：CanvasLayer（layer=3）+ 全屏半透明 ColorRect（dim）+ 居中 VBox：`TitleLabel`（「第 N 道墙」，112px）+ `SubtitleLabel`（40px），LabelSettings 描边 10px（`WAVE_TRANSITION_OUTLINE_SIZE`）；文字居中 y≈640 安全区，HUD 顶部条带（0–160px）零遮挡
- **不碰**：FSM（无新状态）、WaveController、GameManager、雨幕/音频（继续运行——「雨还在下」氛围）
- 参照：PRD #390 §4.1/§4.2/§4.3

### 3.4 测试文件（实现期新建）

- `mini-pong/tests/test_breakout_grid.gd`：对照 DESIGN #384 §5.1（布局/生成 API/信号/缺口/再生/幂等/常量）
- `mini-pong/tests/test_wave_transition.gd`：对照 PRD #390 §5（大字文本/选句分档/三段和 2.0/冻结解锁/兜底/JSON 容错/AC5 grep 卡口）——用例描述见 §9 Scenario G

---

## 4. 数据流

### Flow 1: 完整波次循环（AC2 — 组装后激活的主路径）

```
BreakoutGrid 最后一砖 destroy()
    └─► wall_cleared()  [恰好一次守卫]
           └─► WaveController._on_wall_cleared
                  ├─ GameManager.settle_wave() → wave_state=SETTLED → wave_settled(idx)
                  │     └─► UpgradePickUI.open(idx)  [3 选 1；get_tree().paused=true；_set_settle_hold(true)]
                  │           └─► ui_accept 确认 → UpgradePool.apply(id) → reveal → close()
                  │                 └─► group("wave_controllers").advance_settlement()
                  │                       └─► WaveController.advance_settlement() → _advance_wave()
                  └─（#388 未接线 fallback：settle_hold=false → 1.0s 定时器自动推进，行为不变）
_advance_wave():
    ├─ GameManager.begin_wave() → wave_index+1 → wave_started(idx)   [AC3 HUD 波次号]
    │     └─► WaveTransition._on_wave_started(idx)  [冻结 → 选句 → 2.0s Tween → 解冻]
    ├─ _apply_difficulty(idx) → AIPaddle 参数收紧（clamp 下限）       [AC2 AI 增强]
    ├─ rain_curtain.set_wave_factor(idx)                             [#389 雨量波次因子]
    └─ BreakoutGrid.generate_wave(厚度, GAPS, -1)                    [先 clear_wall → 新墙]
          └─► wall_generated(remaining) → GameHUD 剩余砖数播种        [AC3]
```

### Flow 2: 拆砖得分 + 剩余砖数（AC3）

```
Ball._on_body_entered(brick)  [球 mask bit2 ∩ 砖 layer2]
    ├─ dominant-axis 翻转 velocity + _bounce_cooldown=2
    └─ brick.destroy()
          └─► BreakoutGrid._on_brick_destroyed
                 ├─ brick_destroyed(brick, pos)
                 │     └─► ScoringManager._on_brick_destroyed → last_toucher 非空
                 │           └─► GameManager.add_score(toucher, 1, "brick")
                 │                 ├─ brick_scored(side) → GameHUD 拆砖子区
                 │                 └─ score_changed → GameHUD 总分
                 ├─ remaining_bricks -= 1 → GameHUD._on_grid_brick_destroyed → 剩余砖数刷新
                 └─ 归零 → wall_cleared()（Flow 1）
```

### Flow 3: 波次转场呈现（AC2 仪式感，#390）

```
GameManager.begin_wave() ── wave_started(idx) ──► WaveTransition._on_wave_started(idx)
    ├─ _transitioning 守卫（重入忽略）
    ├─ 冻结：Ball.set_frozen(true) + PlayerPaddle/AIPaddle.set_frozen(true)
    ├─ 读 wave_failure_text.json → wave_subtitles 分档选句（决胜波 ws4 覆盖；缺失→副句留空）
    ├─ TitleLabel = "第 %d 道墙" % idx；SubtitleLabel = 选句
    ├─ visible=true → Tween: fade_in(0.5) → hold(1.0) → fade_out(0.5)  [总 2.0s]
    └─ finished → 解冻 + visible=false（兜底：is_inside_tree 守卫必达）
```

### Flow 4: 失败 / 获胜终局（AC4）

```
任一方到 21 → GameManager._check_run_end → match_over(winner)
    ├─► GameStateMachine._on_match_over → GAME_OVER 态 → _set_ui("game_over") → GameOverScreen.visible=true
    └─► GameOverScreen._on_match_over(winner)
           ├─ player → win 分支：YOU WIN! + 脉冲（#292 保留）
           └─ ai → fail 分支：FailurePhraseLabel 分档选句（fp1-fp4，JSON 容错）+ RunStatsLabel 三项
                 （波次 get_wave_index / 拆砖 get_brick_count("player") / 穿墙 get_pierce_count("player")）
    └─ 终局后：GameManager._is_run_over 守卫 → wave_started 不再发出（无孤立信号）
```

### Flow 5: 容错回退（任一节点缺失，守卫仍生效）

```
BreakoutGrid 未挂载/信号未实现 → ScoringManager/WaveController/GameHUD 各自
get_node_or_null == null → push_warning 一次 → 跳过该路径（波次状态机照常推进，仅生成环节跳过）
—— 现状 1781 用例全绿的容错设计即证明；组装后此路径不再触发（断言其不再 warn 亦可）
```

---

## 5. 边界条件与失败路径

### 边界条件（≥8）

| # | 场景 | 处理 |
|---|------|------|
| 1 | 波次上限（WAVE_MAX_INDEX=99） | WaveController push_warning 停止推进（#386 已实现） |
| 2 | 发球直撞砖（无 last_toucher） | 砖碎反弹但不计分（#385 边界 2 已实现）；砖仍销毁（#384 行为不变） |
| 3 | 同帧双砖 / 砖+出界同帧 | 砖对象身份去重（`_destroyed` 字典）+ ScoringManager 帧守卫（#384/#385 契约） |
| 4 | 升级窗口打开期间到 21 分 | run-over 分支 `end_wave_cycle`，不生成新墙（#388 边界 5；WaveController.advance_settlement 同守卫） |
| 5 | 决胜波副句 | 任一方 ≥18 → ws4 覆盖波次分档（#390 分档规则） |
| 6 | JSON 缺失/解析失败/schema 字段缺失 | 转场只显大字、副句留空、push_warning 一次；失败屏兜底短句（#396 容错契约） |
| 7 | 转场中按 Escape | 演员冻结（非全局暂停）→ FSM 无输入冲突面；`_transitioning` 重入守卫（#390 Approach A） |
| 8 | 砖角双砖同时接触 / 高速隧穿 | `_bounce_cooldown=2` 帧串行化；砖尺寸 clamp ≥ BRICK_MIN_DIM(14px)（#384 边界 1/3） |
| 9 | queue_free 期间回调 | `is_instance_valid(brick)` + clear_wall 快照遍历（#384 契约） |
| 10 | 失败屏换实例的视觉/路径回归 | ui_game_over.tscn 与 game_over_screen.gd 路径逐项匹配（§1.1 已核实）；layer/visible/节点名覆盖保留 |

### 失败路径（≥4）

| # | 场景 | 处理 |
|---|------|------|
| 1 | wall_cleared 重复发出 | `_wall_cleared_emitted` 守卫 + `generate_wave()` 重置（测试：打空→再生→再打空，恰好两次） |
| 2 | 转场解锁缺失导致卡死 | Tween finished 回调 + `is_inside_tree()` 守卫 + `_transitioning` finally 语义恢复冻结状态（#390 失败路径 2） |
| 3 | 副句/文案硬编码进 .gd | 违反 AC5 —— review 用 grep 卡口（`grep -rn "雨声盖过心跳\|每一道墙都更厚" mini-pong/gdscripts/` 为空） |
| 4 | 转场层遮挡（layer 选错盖住升级 UI 或露出 HUD） | 层序常量 `WAVE_TRANSITION_LAYER=3`；test_main_scene 断言 layer 值 |
| 5 | 砖层碰撞回归（砖 layer2 与球 mask 交互） | DESIGN #384 已核查（球 mask=3 含 bit 2）；落地后 test_ball.gd 回归 |
| 6 | 终局后残留事件 | GameManager `_is_run_over` 守卫 return（#385 已实现） |

---

## 6. 每场景 / 每组件配置（Main.tscn 目标态）

| 节点 | 类型 | 位置/关键属性 | 来源 |
|------|------|--------------|------|
| BreakoutGrid | Node2D（instance breakout_grid.tscn） | position=(0, 640)；wall_y=640（GRID_WALL_Y） | ★ 新增 |
| WaveController | Node（wave_controller.gd） | 直挂 Game 根；`../BreakoutGrid` `../AIPaddle` `../AtmosphereLayer/RainCurtain` 解析 | ★ 新增 |
| WaveTransition | CanvasLayer（instance wave_transition.tscn） | layer=3（WAVE_TRANSITION_LAYER）；visible=false | ★ 新增 |
| GameOverScreen | CanvasLayer（instance ui_game_over.tscn） | layer=1；visible=false；节点名不变 | ★ 替换 |
| UpgradePickUI | CanvasLayer（instance ui_upgrade_pick.tscn） | layer=2（实例继承，已验证） | 无改动 |
| GameHUD | CanvasLayer（instance ui_game_hud.tscn） | layer=1 | 无改动 |
| AtmosphereLayer/RainCurtain | CanvasLayer/instance | layer=0 | 无改动 |
| PauseOverlay | CanvasLayer | layer=10 | 无改动 |

**层序不变式**：Atmosphere(0) < HUD(1) < Upgrade(2) < **Transition(3)** < Pause(10)。

**砖墙配置**：`wall_y=640`（墙带判定 `WALL_BAND_HALF_HEIGHT=22` 已由 #385 定义）；首波厚度 `WAVE_START_THICKNESS=1`，每波 `+WAVE_THICKNESS_STEP=1`（WaveController `_wave_thickness` 计算，机械占位归 taste-draft）。

---

## 7. 集成点

> **Status 约定：** ✅ = 待 implement 接线（节点挂载/信号连接后完成）；✅ = 脚本内已连接（组装即激活）。
> implement agent 完成接线后更新本表；review agent 验证全部 ✅ 已解决或显式推迟。

| 集成 | 我们的组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| BreakoutGrid.brick_destroyed → ScoringManager._on_brick_destroyed | BreakoutGrid | #385 | 信号连接（守卫已就绪，节点挂载即触发） | ✅ |
| BreakoutGrid.wall_cleared → WaveController._on_wall_cleared | BreakoutGrid | #386 | 信号连接（同上） | ✅ |
| BreakoutGrid.wall_generated → GameHUD._on_grid_wall_generated | BreakoutGrid | #392 | 信号连接（剩余砖数播种主路径） | ✅ |
| BreakoutGrid.brick_destroyed → GameHUD._on_grid_brick_destroyed | BreakoutGrid | #392 | 信号连接（剩余砖数递减） | ✅ |
| WaveController → AIPaddle 难度收紧 | WaveController | #386 | 节点引用 + 属性写入（`../AIPaddle`） | ✅ |
| WaveController → RainCurtain.set_wave_factor | WaveController | #389 | 节点引用 + 方法调用（`../AtmosphereLayer/RainCurtain`） | ✅ |
| GameManager.wave_started → WaveTransitionController._on_wave_started | WaveTransition | #390 | 信号连接（autoload，_ready 内 connect） | ✅ |
| GameManager.wave_started → GameHUD 波次号 | GameHUD | #392 | 信号连接（脚本内已连接） | ✅ |
| GameManager.wave_settled → UpgradePickUI.open | UpgradePickUI | #388 | 信号连接（脚本内已连接） | ✅ |
| UpgradePickUI → WaveController.advance_settlement（group wave_controllers） | UpgradePickUI | #388 | group 寻址 + 方法调用（WaveController 挂载后激活） | ✅ |
| GameManager.match_over → GameStateMachine GAME_OVER | GameStateMachine | #385/#391 | 信号连接（脚本内已连接） | ✅ |
| GameManager.match_over → GameOverScreen win/fail 双分支 | GameOverScreen | #391 | 信号连接（脚本内已连接；换实例后 Label 全量生效） | ✅ |
| Ball.bricks 分支 ↔ Brick.destroy | Ball/Brick | #384 | 碰撞 + 方法调用（组 "bricks" 识别） | ✅ |

---

## 8. 实施阶段

| Phase | 优先级 | 组件 | 估计 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | **BreakoutGrid 契约落地（#384）**：constants BRICK_* → brick.gd/tscn → breakout_grid.gd/tscn → ball.gd bricks 分支 → test_breakout_grid.gd + test_ball.gd 用例 → 全量回归 | 1–1.5 天 |
| Phase 2 | P0 | **WaveTransition 契约落地（#390）**：constants WAVE_TRANSITION_* → wave_transition.tscn → wave_transition_controller.gd → test_wave_transition.gd → 全量回归 | 1 天 |
| Phase 3 | P0 | **Main.tscn 组装**：3 节点挂载 + 失败屏换实例 + UpgradePickUI 断言 + test_main_scene 追加 → 全量回归 | 0.5–1 天 |
| Phase 4 | P0 | **运行验证（AC 清单）**：headless 编译 + 全量测试 + auto_play 100 局 + 可选 L3 截图 | 0.5 天 |

**依赖顺序**：Phase 1/2 相互独立（各自可独立全量回归），Phase 3 依赖两者完成（组装前提是组件存在）；Phase 4 依赖全部。Phase 1/2 每步后跑 `godot --path mini-pong/ --headless --script tests/run_tests.gd` 定位回归。

---

## 9. 测试用例描述

> 仅描述，不写可运行测试代码（implement agent 依此写 `tests/test_*.gd`）。

### Scenario A: Main.tscn 组装完整性（AC1）

- Test 1：加载并实例化 Main.tscn → 断言 `BreakoutGrid` 节点存在且为 Node2D；`position.y == 640`；`wall_y` 导出 == `GRID_WALL_Y`(640)
- Test 2：断言 `WaveController` 节点存在且脚本为 wave_controller.gd；`_ready` 后 `wall_cleared` 已连接（或经 has_signal 守卫无警告路径）
- Test 3：断言 `WaveTransition` 节点存在、`CanvasLayer.layer == 3`（`WAVE_TRANSITION_LAYER`）、初始 `visible == false`
- Test 4：断言 `GameOverScreen` 为 ui_game_over.tscn 实例：`CenterContainer/VBoxContainer/FailurePhraseLabel` 与 `RunStatsLabel` 存在；`layer == 1`、`visible == false`
- Test 5：断言 `UpgradePickUI.layer == 2`（实例继承，无需 Main.tscn 覆盖）
- Test 6：断言全部 ext_resource 路径可解析；实例化过程零脚本错误
- Test 7：断言 FSM 全部 NodePath 解析（GameHUD / GameOverScreen / StartMenu / PauseOverlay / Ball / 双挡板 / ScoringManager）——既有 TC1/TC15 语义保留

### Scenario B: 完整波次循环（AC2）

- Test 1：mock/真球打空整墙 → `wall_cleared` 恰好一次 → `settle_wave` → `wave_settled(idx)` → UpgradePickUI 打开（`visible == true`）
- Test 2：确认升级 → `close()` → `advance_settlement()` → `begin_wave()` → `wave_index` +1 且 `wave_started` 负载正确
- Test 3：新墙生成：`generate_wave` 厚度 = `WAVE_START_THICKNESS + (index-1) * WAVE_THICKNESS_STEP`（第 N 波更厚）
- Test 4：AI 增强：`ai_reaction_delay_min/max`、`ai_position_error` 按 `AI_DIFFICULTY_FACTOR` 收紧且 clamp 到 FLOOR 下限
- Test 5：升级窗口打开期间任一方到 21 → `end_wave_cycle`，不生成新墙
- Test 6：波次达 `WAVE_MAX_INDEX` → push_warning 停止推进（#386 回归）

### Scenario C: HUD 实时更新（AC3）

- Test 1：拆砖 → `brick_scored(side)` → HUD 拆砖子区更新；`brick_destroyed` → 剩余砖数递减
- Test 2：新墙生成 → `wall_generated(remaining)` → HUD 信息条「第 N 波 · 剩余 M」播种
- Test 3：`wave_started(idx)` → HUD 波次号更新
- Test 4：`game_hud.gd` 无 `_process`（信号驱动零轮询，AC5）
- Test 5：test_hud.gd 全量回归——grid 信号激活后剩余砖数从「—」占位变为真实数据

### Scenario D: 失败屏 / 获胜可达（AC4）

- Test 1：player 到 21 → `match_over("player")` → FSM GAME_OVER + GameOverScreen win 分支（YOU WIN! + 脉冲）
- Test 2：ai 到 21 → `match_over("ai")` → fail 分支：FailurePhraseLabel 按波次分档选句 + RunStatsLabel 三项数据（波次/拆砖/穿墙）
- Test 3：`FailurePhraseLabel` / `RunStatsLabel` 文本实际渲染（换实例后不再被 get_node_or_null 静默跳过）
- Test 4：终局后 `wave_started` 不再发出（无孤立信号）；SPACE 回菜单 → reset → 新 run 正常

### Scenario E: 稳定性（AC5）

- Test 1：`auto_play_test.gd`（100 局 AI vs AI）在组装后重跑：0 脚本错误 / 0 空引用
- Test 2：场景树无泄漏：连续多局后节点计数稳定（`clear_wall` 快照遍历 + `is_instance_valid` 检查）
- Test 3：10 局完整波次路径运行（含拆砖/升级/转场/终局）无错误

### Scenario F: BreakoutGrid 契约回归（#384，新套件）

- Test 1：布局——GAPS/OFFSET/HOLES/MIXED 各自砖数断言；X 铺满（首砖 x ≥ 砖宽/2、末砖 x ≤ 720−砖宽/2）；OFFSET 奇数行偏移 = (砖宽+缝)/2；HOLES 柱位×行无砖节点
- Test 2：生成 API——`generate_wave(thickness, layout, seed)`：`rows == thickness`；相同 seed 布局可复现；`seed < 0` 不抛错
- Test 3：信号——逐砖 destroy → 每次 `brick_destroyed(brick, pos)` 且 pos 正确；打空 → `wall_cleared` 恰好一次；新墙 → `wall_generated(remaining)` 负载正确
- Test 4：缺口直穿——HOLES 洞轴心放球移动 → 无反弹、无砖碎
- Test 5：再生——`generate_wave` 后旧砖清空、守卫重置；打空→再生→再打空 → `wall_cleared` 恰好两次
- Test 6：幂等——同一砖 destroy 两次 → 计数只减一、信号只发一次
- Test 7：常量——`BRICK_MIN_DIM >= 14`；默认 brick_size 两轴 ≥ 14
- Test 8：ball.gd 反弹——侧击翻 X / 顶底翻 Y / 撞砖后砖 `_destroyed` 且已 queue_free / walls·paddles 分支回归不变

### Scenario G: WaveTransition 契约回归（#390，新套件）

- Test 1：`wave_started(idx)` → TitleLabel == 「第 N 道墙」；副句按分档选句（波 1-2→ws1 / 3-5→ws2 / 6+→ws3）
- Test 2：决胜波——任一方 ≥18 → ws4 覆盖（优先级高于波次分档）
- Test 3：时长——`FADE_IN + HOLD + FADE_OUT == 2.0`；短时长注入下 Tween 结束覆盖层隐藏
- Test 4：冻结/解锁——转场期间 `Ball.frozen == true` 且双拍 frozen；结束后全部恢复 false
- Test 5：解锁兜底——异常路径（节点移出场景）必解锁，不卡死
- Test 6：JSON 容错——缺失/损坏文件 → 大字显示、副句留空、push_warning 一次、波次推进不阻塞
- Test 7：AC5 grep 卡口——`mini-pong/gdscripts/` 零硬编码副句文案

---

## 附录 A: 与 PRD 的差异记录（plan agent 源码核实后定稿）

| PRD 断言 | 实际代码（核实） | 设计决议 |
|---------|----------------|---------|
| UpgradePickUI 实例 layer 未设（默认 1） | `ui_upgrade_pick.tscn` 根已设 `layer = 2`（PR #440）；Main.tscn 实例继承 → headless 实测 `layer == 2` | 组装**零改动**；仅 test_main_scene 补断言（§2.5） |
| #390 需 ball.gd 新增 frozen 标志 | `ball.gd` 已有 `frozen` + `set_frozen`（#391 PR #439 交付） | 转场直接复用既有 API；ball.gd 仅加 bricks 分支 |
| BRICK_* 组含 `GRID_WALL_Y`（DESIGN #384 §4.2） | `GRID_WALL_Y` 已由 #385 定义于 constants.gd | BRICK_* 组**不重复定义**，引用既有常量 |
| 失败屏两选项（换实例 or 补齐内联 Label） | `ui_game_over.tscn` 路径与 `game_over_screen.gd` 逐项匹配（已核实） | 定稿**换实例**（消除双份漂移；#391 交付物启用） |
| 转场层建议 layer=3 | — | 确认 layer=3，新增 `WAVE_TRANSITION_LAYER` 常量收敛层序 |
| 组装边界「不改 8 个已落地组件脚本逻辑」 | ball.gd bricks 分支为 #384 契约组成部分（PRD 明确豁免） | 遵守：唯一脚本改动 = ball.gd bricks 分支 + constants.gd 常量组 |


---

## 附录 B: 首波触发 + #387 组契约（plan agent 增补，2026-08-13）

> **背景:** 本 DESIGN 初版（PR #442）未覆盖两个机械缺口——① **首波触发缺失**：全代码库无任何代码启动第 1 波；② **#387 组契约未落地**：BreakoutGrid 未满足 UpgradePool.grid_ref 组解析与升级钩子注册表。Research Round 2 修订（#393 PRD 工作副本）已将①列为「组装关键缺口」并注明「首波触发路径归 #393 组装」（PRD #390 边界 1 同文）。本增补与正文同权，为 implement 契约的一部分。

### B.1 首波触发（缺口①，AC2 前置）

**现状核实（2026-08-13）：**
- 全库仅 `wave_controller.gd:_advance_wave()` 调用 `GameManager.begin_wave()`；`_advance_wave()` 仅由 `_on_wall_cleared`（墙清空后）与 `advance_settlement()`（#388）触发。
- `game_state_machine.gd` MENU→SERVING→PLAYING 与 `start_menu.gd:_on_start_pressed()` 均不调用 begin_wave/generate_wave。
- 结果：若不增补，**第 1 波永远不会开始**——无初始墙、无 `wave_started(1)`，AC2 循环无法启动（`start_menu` 中 `_on_start_pressed` 为孤儿代码——FSM 直接处理 SPACE 输入，不可作挂点）。

**设计定稿：**

1. `mini-pong/gdscripts/wave_controller.gd` 新增**幂等**公开方法 `start_first_wave()`（既有逻辑零改动；先例：#388 为 wave_controller.gd 新增 `advance_settlement`）：

```gdscript
## #393 增补：首波触发（PRD #390 边界 1）。幂等：仅 wave_index==0 且非 run-over 时生效。
func start_first_wave() -> void:
    if GameManager.wave_index != 0 or GameManager.is_run_over():
        return
    _advance_wave()   # begin_wave(1) + _apply_difficulty(1) + rain.set_wave_factor(1) + generate_wave(厚度 1)
```

2. `mini-pong/gdscripts/game_state_machine.gd` `enter_state(State.PLAYING)` 增补触发（additive ~5 行；FSM 不变项「不扩展状态机」语义保持——无新状态）：

```gdscript
State.PLAYING:
    # ...既有逻辑不变（_set_ui/_freeze_paddles(false)/pause_overlay/AudioEngine）...
    # #393 增补：首波触发 —— wave_index==0 时首次进入 PLAYING → 启动第 1 波（幂等，重复进入 no-op）
    if is_instance_valid(GameManager) and GameManager.has_method("get_wave_index") \
            and GameManager.get_wave_index() == 0:
        var wc = get_tree().get_first_node_in_group("wave_controllers")
        if wc and wc.has_method("start_first_wave"):
            wc.start_first_wave()
```

- **触发时序**：发球动画完成 → PLAYING → `begin_wave(1)` → `wave_started(1)` → 转场冻结演员 2.0s → 解冻开打——与后续每波「begin_wave → 转场 → 对打」时序完全一致（AC3 冻结语义在首波同样成立）。
- **为何选 PLAYING 而非 SERVING**：SERVING 触发会在 `ball.serve()`（ball.gd L93 防御性复位 `frozen=false`）之后失效冻结，AC3 破坏；PLAYING 进入时球已发球完毕，冻结语义与后续波次一致。
- **为何 group + has_method 寻址**：与 #388 UpgradePickUI→WaveController 同模式；WaveController 未挂载时 no-op 不崩（容错惯例）。
- **重开路径**：GAME_OVER → SPACE → MENU → SPACE → SERVING：FSM 首服分支 `reset_match()`（game_state_machine.gd L105-106）将 wave_index 归 0 → 再进 PLAYING 时 `get_wave_index()==0` → 新 run 首波正常触发（无残留状态）。

**差异记录（vs 已合并契约）：**

| 已合并契约 | 本增补 | 理由 |
|-----------|--------|------|
| TASKS「不动文件」含 `game_state_machine.gd` / `wave_controller.gd` | 两文件各 +1 additive 方法/调用（既有逻辑零改动） | 首波触发无处可挂：StartMenu._on_start_pressed 为孤儿代码；新节点轮询 FSM 状态违反零轮询惯例；唯一信号式入口即 FSM PLAYING 进入（Research Round 2 修订 gap 1 要求组装定义首波路径） |
| DESIGN §4 Flow 1 从「最后一砖 destroy」起 | 前置 Flow 0：`PLAYING 首次进入 → start_first_wave → begin_wave(1) → 转场 + 首墙生成` | 补全循环入口；无 Flow 0 则 AC2 永不可达 |

### B.2 #387 组契约 + 升级钩子（缺口②）

**现状核实（2026-08-13）：** `upgrade_pool.gd` L156 `grid_ref = get_tree().get_first_node_in_group("breakout_grids")`（惰性解析，组不存在时 upgrade 的 grid 类效果为 no-op）；`brick_upgrade_hooks.gd` 头部契约：「注册时机归 grid 侧（BreakoutGrid._ready() 调 `BrickUpgradeHooks.register_all(self)`）」+ grid 需实现 `register_upgrade_hook` / `open_hole` / `blast_neighbors`。DESIGN #414 §4.1 本就含这三个 API（本 DESIGN §3.2 漏列）。

**增补（并入 §3.2 BreakoutGrid 契约）：**

- `_ready()`：`add_to_group("breakout_grids")` + `BrickUpgradeHooks.register_all(self)`（brick_upgrade_hooks.gd 契约注释指定注册时机归 grid 侧）
- API 增补：
  - `register_upgrade_hook(id: String, fn: Callable) -> void`：写入 `upgrade_hooks: Dictionary` 注册表
  - `apply_upgrade_hook(id: String, ctx: Dictionary) -> void`：分发（ctx 注入 `"grid"` 键——brick_upgrade_hooks.gd 契约）
  - `open_hole(count: int) -> void`：下波 `generate_wave()` 末尾消费 pending 洞请求，复用 HOLES 柱位逻辑
  - `blast_neighbors(pos: Vector2, radius: float) -> void`：以 pos 为中心炸碎 radius 内砖——逐砖走 `_on_brick_destroyed` 语义（身份去重/递减/信号；归零时 wall_cleared 恰好一次）
- 不动项：`brick_upgrade_hooks.gd` 不改（契约先行，已定稿；test_upgrade_pool.gd TC-H1/H2 假 grid 桩继续可用）

### B.3 边界条件增补（并入 §5）

| # | 场景 | 处理 |
|---|------|------|
| 11 | 首波触发重入（PLAYING 每分进入） | `start_first_wave()` 幂等（wave_index==0 守卫）——wave_index>0 时 no-op |
| 12 | run-over 后重开 | `reset_match()` 归零 wave_index/状态 → 新 run PLAYING 再触发；`is_run_over()` 守卫防终局后误触发 |
| 13 | 升级 hook 在下波生成前调用 | `open_hole` 请求挂起至下波 `generate_wave()` 末尾消费（pending 队列）；`blast_neighbors` 立即生效 |
| 14 | WaveController 未挂载时首波触发 | group 寻址 null → no-op（容错惯例；测试 mock 树不受影响） |

### B.4 集成点增补（并入 §7）

| 集成 | 组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| FSM PLAYING 首次进入 → WaveController.start_first_wave | FSM / WaveController | #386/#393 | group `wave_controllers` + has_method | ✅ |
| BreakoutGrid ← UpgradePool.grid_ref | BreakoutGrid | #387 | `_ready()` 加组 `breakout_grids`（惰性解析激活） | ✅ |
| BreakoutGrid ← BrickUpgradeHooks | BreakoutGrid | #387 | `_ready()` 调 `register_all(self)`；实现 register_upgrade_hook / apply_upgrade_hook / open_hole / blast_neighbors | ✅ |

### B.5 测试用例增补（并入 §9，Scenario H: 首波触发 + #387 组契约）

- Test 1：`start_first_wave()` 幂等——连续调用两次 → wave_index 只到 1、`wave_started` 只发一次、墙只生成一面
- Test 2：FSM PLAYING 首次进入（wave_index==0）→ begin_wave(1) → 墙生成 + 转场播放（TitleLabel「第 1 道墙」）；再次进入 PLAYING（wave_index==1）→ 不重复触发
- Test 3：重开路径——GAME_OVER → MENU → 再开始 → reset_match 后新 run 首波正常触发
- Test 4：run-over 后（is_run_over）→ `start_first_wave` no-op
- Test 5：`breakout_grids` 组断言——实例化 BreakoutGrid 后 `is_in_group("breakout_grids")` 为真；UpgradePool 惰性 `grid_ref` 解析到真实 grid（非 null）
- Test 6：升级钩子分发——`register_upgrade_hook` 后经 `BrickUpgradeHooks` 调 `apply_upgrade_hook("open_hole", {grid=…, count=1})` → 下波生成后洞数正确；`blast_neighbors(pos, r)` → 半径内砖碎、brick_destroyed/计数正确、归零 wall_cleared 恰好一次（test_upgrade_pool TC-H1/H2 的真实 grid 版）
- Test 7：转场覆盖首波——首波 `wave_started(1)` 期间 Ball/双拍 frozen，结束后恢复（AC3 在首波同样成立）

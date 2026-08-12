# Tasks: [Integration] 主场景组装 (Main Scene Assembly)

> **Parent Issue:** #393
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Design:** docs/DESIGN/393-main-scene-assembly.md
> **深度:** depth/standard（涉及 12+ 文件 + 2 个契约落地，按 #392 惯例产出 TASKS 供 implement 使用）
> **所有权:** `content_ownership: mechanical` — 节点组装/信号接线/常量收敛机械实现；波次数值、副句文案、配色归 taste-draft Issue（#395/#396）

---

## Phase 1: BreakoutGrid 契约落地（#384，P0）

- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): 新增「── Brick Wall (#384) ──」常量组 —— `BRICK_SIZE=Vector2(64,24)`、`BRICK_GAP=4`、`BRICK_MIN_DIM=14`（**不重复** `GRID_WALL_Y`，引用 #385 既有常量）（DESIGN §2.1）
- [ ] Task 2 (`mini-pong/gdscripts/brick.gd`): **新建** —— `extends StaticBody2D`；`_ready()` 加组 `bricks`、`collision_layer=2`、`collision_mask=0`；`var grid`（注入）；`var _destroyed=false`；`destroy()` 幂等 → `grid._on_brick_destroyed(self)`（is_instance_valid 守卫）→ `queue_free()`（DESIGN §3.1）
- [ ] Task 3 (`mini-pong/scenes/brick.tscn`): **新建** —— StaticBody2D 根（挂 brick.gd）+ ColorRect（复用 `assets/neon_glow_material.tres`）+ CollisionShape2D（RectangleShape2D 64×24）（DESIGN §3.1）
- [ ] Task 4 (`mini-pong/gdscripts/breakout_grid.gd`): **新建** —— `class_name BreakoutGrid`；@export 参数组（brick_size/brick_gap/layout/rows/hole_count/hole_seed/wall_y/brick_scene）；`enum BrickLayout {GAPS, OFFSET, HOLES, MIXED}`；信号 `brick_destroyed`/`wall_cleared`/`wall_generated`；`generate_wave(thickness, layout, seed)`（先 clear_wall → 布局实例化 → 重置守卫 → 末尾 emit wall_generated）；`clear_wall()`（快照 queue_free）；`_on_brick_destroyed`（身份去重 → 递减 → 归零 wall_cleared 恰好一次）（DESIGN §3.2）
- [ ] Task 5 (`mini-pong/scenes/breakout_grid.tscn`): **新建** —— Node2D 根 + 脚本；独立可实例化（DESIGN §3.2）
- [ ] Task 6 (`mini-pong/gdscripts/ball.gd`): `_on_body_entered` 新增 `bricks` 分支 —— group 识别 → dominant-axis 翻转 → `_bounce_cooldown=BOUNCE_COOLDOWN_FRAMES` → `body.destroy()`；不调用音频（DESIGN §2.2）
- [ ] Task 7 (`mini-pong/tests/test_breakout_grid.gd`): **新建** —— 布局（GAPS/OFFSET/HOLES/MIXED 砖数 + X 铺满 + OFFSET 偏移 + HOLES 无砖）/ 生成 API（thickness、seed 可复现）/ 信号（brick_destroyed pos、wall_cleared 恰好一次、wall_generated 负载）/ 缺口直穿 / 再生 / 幂等 / 常量 ≥14（DESIGN §9 Scenario F）
- [ ] Task 8 (`mini-pong/tests/test_ball.gd`): 追加砖块反弹用例 —— 侧击翻 X / 顶底翻 Y / 撞砖后砖 `_destroyed` 且已 queue_free / walls·paddles 分支回归（DESIGN §9 Scenario F-8）
- [ ] Task 9 (`mini-pong/tests/run_tests.gd`): 注册 `res://tests/test_breakout_grid.gd`（"Breakout Grid"，置于 test_ball 之后）
- [ ] **验证点**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含既有 20 套件回归）

## Phase 2: WaveTransition 契约落地（#390，P0）

- [ ] Task 10 (`mini-pong/gdscripts/constants.gd`): 新增「── Wave Transition (#390) ──」常量组 —— `WAVE_TRANSITION_FADE_IN=0.5`/`HOLD=1.0`/`FADE_OUT=0.5`（三段和恒 2.0）、`TITLE_FONT_SIZE=112`、`SUBTITLE_FONT_SIZE=40`、`OUTLINE_SIZE=10`、`JSON_PATH=res://content/wave_failure_text.json`、`DECISIVE_SCORE=18`、`LAYER=3`、分档边界 `BAND1_MAX=2`/`BAND2_MAX=5`（DESIGN §2.1）
- [ ] Task 11 (`mini-pong/scenes/wave_transition.tscn`): **新建** —— CanvasLayer（layer=3, visible=false）+ 全屏半透明 ColorRect（dim）+ 居中 VBox：TitleLabel（112px）+ SubtitleLabel（40px），LabelSettings 描边 10px；文字居中 y≈640 安全区（DESIGN §3.3）
- [ ] Task 12 (`mini-pong/gdscripts/wave_transition_controller.gd`): **新建** —— `extends CanvasLayer`；`_ready` 连接 `GameManager.wave_started`（has_signal 守卫）→ `_on_wave_started(idx)`：`_transitioning` 重入守卫 → 冻结（`../Ball` `set_frozen(true)` + `../PlayerPaddle`/`../AIPaddle` `set_frozen(true)`，get_node_or_null + has_method 守卫）→ 读 JSON 分档选句（决胜波 ws4 覆盖，缺失→副句留空 + push_warning 一次）→ TitleLabel「第 N 道墙」→ Tween 三段 2.0s（fade_in→interval→fade_out）→ finished 解冻 + 隐藏；`is_inside_tree()` 兜底解锁（DESIGN §3.3）
- [ ] Task 13 (`mini-pong/tests/test_wave_transition.gd`): **新建** —— 大字/选句分档（ws1-3 + 决胜波 ws4 覆盖）/ 三段和 2.0 + 短时长注入 / 冻结解锁 / 解锁兜底 / JSON 容错 / AC5 grep 卡口（DESIGN §9 Scenario G）
- [ ] Task 14 (`mini-pong/tests/run_tests.gd`): 注册 `res://tests/test_wave_transition.gd`（"Wave Transition"，await 模式）
- [ ] **验证点**：全量回归全绿

## Phase 3: Main.tscn 组装（P0，核心）

- [ ] Task 15 (`mini-pong/scenes/Main.tscn`): 添加 `BreakoutGrid` 实例（ext_resource breakout_grid.tscn，position=(0, 640)，直挂 Game 根）（DESIGN §2.3）
- [ ] Task 16 (`mini-pong/scenes/Main.tscn`): 添加 `WaveController` 节点（ext_resource wave_controller.gd，直挂 Game 根 —— `../BreakoutGrid`/`../AIPaddle`/`../AtmosphereLayer/RainCurtain` 相对路径解析）（DESIGN §2.3）
- [ ] Task 17 (`mini-pong/scenes/Main.tscn`): 添加 `WaveTransition` 实例（ext_resource wave_transition.tscn；layer=3 覆盖、visible=false）（DESIGN §2.3）
- [ ] Task 18 (`mini-pong/scenes/Main.tscn`): 删除内联 GameOverScreen 子树 → 替换为 `instance ui_game_over.tscn`；节点名 `GameOverScreen` 不变、覆盖 `layer=1`、`visible=false`（FSM NodePath 与显隐逻辑零改动）（DESIGN §2.3）
- [ ] Task 19 (`mini-pong/scenes/Main.tscn`): 清理临时调试代码；确认 UpgradePickUI **无改动**（layer=2 实例继承，已核实）（DESIGN §2.3）
- [ ] Task 20 (`mini-pong/tests/test_main_scene.gd`): 追加组装断言 —— BreakoutGrid 存在/position.y==640/wall_y；WaveController 存在；WaveTransition layer==3 且初始隐藏；GameOverScreen FailurePhraseLabel+RunStatsLabel 存在/layer==1/visible==false；UpgradePickUI layer==2（DESIGN §2.5 / §9 Scenario A）
- [ ] **验证点**：全量回归全绿 + `godot --path mini-pong/ --headless --quit` 编译通过

## Phase 4: 运行验证（AC 清单，P0）

- [ ] Task 21: `godot --path mini-pong/ --headless --quit` → exit 0（编译/场景加载零错误）
- [ ] Task 22: `godot --path mini-pong/ --headless --script tests/check_compile.gd` → exit 0
- [ ] Task 23: `godot --path mini-pong/ --headless --script tests/run_tests.gd` → 全绿（含新增 2 套件 + 既有 20 套件回归；基线 1781 用例之上增量）
- [ ] Task 24: `auto_play_test.gd`（100 局 AI vs AI）→ 0 脚本错误/0 空引用（波次路径激活后重跑，AC5）
- [ ] Task 25（可选）: L3 视觉验证 —— run-e2e-review.sh 截图：转场大字/升级 UI/失败屏渲染、HUD 无遮挡（720×1280）
- [ ] Task 26（可选）: `docs/GAME_DESIGN/10-SCENE-LAYOUT.md` 场景树示意同步（PRD §3.5；mini-pong 场景树变化较大时）

## 依赖图

```
Phase 1 (BreakoutGrid #384) ──┐
                              ├──► Phase 3 (Main.tscn 组装) ──► Phase 4 (验证)
Phase 2 (WaveTransition #390) ─┘
```

Phase 1/2 相互独立（各自可独立全量回归）；Phase 3 依赖两者完成；Phase 4 依赖全部。每 Phase 结束跑全量回归定位回归。

## Summary: Changed Files

| 文件 | 变更类型 | 估计行数 |
|------|:-------:|:-------:|
| `mini-pong/gdscripts/constants.gd` | 修改（2 常量组） | +20 |
| `mini-pong/gdscripts/brick.gd` | **新建** | ~25 |
| `mini-pong/scenes/brick.tscn` | **新建** | ~15 |
| `mini-pong/gdscripts/breakout_grid.gd` | **新建** | ~120 |
| `mini-pong/scenes/breakout_grid.tscn` | **新建** | ~8 |
| `mini-pong/gdscripts/wave_transition_controller.gd` | **新建** | ~90 |
| `mini-pong/scenes/wave_transition.tscn` | **新建** | ~20 |
| `mini-pong/gdscripts/ball.gd` | 修改（bricks 分支） | +12 |
| `mini-pong/scenes/Main.tscn` | 修改（组装） | +40/−40 |
| `mini-pong/tests/test_breakout_grid.gd` | **新建** | ~150 |
| `mini-pong/tests/test_wave_transition.gd` | **新建** | ~120 |
| `mini-pong/tests/test_ball.gd` | 修改（追加用例） | +25 |
| `mini-pong/tests/test_main_scene.gd` | 修改（追加断言） | +60 |
| `mini-pong/tests/run_tests.gd` | 修改（注册） | +2 |
| `docs/GAME_DESIGN/10-SCENE-LAYOUT.md` | 修改（可选） | ±15 |

**不动文件（明确排除）**：`game_state_machine.gd`（FSM 不扩展）、`game_manager.gd` / `scoring_manager.gd`（#385 已 ✅）、`wave_controller.gd`（#386 已 ✅，仅挂节点）、`upgrade_pool.gd`（#387 autoload）、`upgrade_pick_ui.gd`（#388 已 ✅）、`game_hud.gd`（#392 已 ✅）、`rain_curtain.gd`（#389 已 ✅）、`game_over_screen.gd`（#391 已 ✅，换实例不改脚本）、`project.godot`（autoload/层配置零改动）、`content/wave_failure_text.json`（只读，归 #396）。


## Phase 3.5: 首波触发 + #387 组契约（增补 2026-08-13 — 见 DESIGN 附录 B）

> **背景:** 初版契约（PR #442）缺两个机械缺口：首波触发（AC2 前置——全库无代码启动第 1 波）与 #387 组契约（UpgradePool.grid_ref / 升级钩子注册表）。本阶段并入 Phase 3（组装）之前完成，否则组装后游戏无法开始第 1 波。

- [ ] Task 27 (`mini-pong/gdscripts/wave_controller.gd`): 新增幂等 `start_first_wave()` —— `wave_index==0` 且非 run-over 时调 `_advance_wave()`（既有逻辑零改动；先例 #388 `advance_settlement`）（DESIGN 附录 B.1）
- [ ] Task 28 (`mini-pong/gdscripts/game_state_machine.gd`): `enter_state(PLAYING)` 增补首波触发 —— `get_wave_index()==0` → group `wave_controllers` + `has_method("start_first_wave")` 调用（~5 行 additive；无新 FSM 状态）（DESIGN 附录 B.1）
- [ ] Task 29 (`mini-pong/gdscripts/breakout_grid.gd`): `_ready()` 加 `add_to_group("breakout_grids")` + `BrickUpgradeHooks.register_all(self)`；实现 `register_upgrade_hook` / `apply_upgrade_hook` / `open_hole`（pending 至下波生成）/ `blast_neighbors`（DESIGN 附录 B.2；契约 brick_upgrade_hooks.gd）
- [ ] Task 30 (`mini-pong/tests/test_first_wave.gd` 或并入 test_main_scene / test_wave_transition): 首波触发用例（幂等 / PLAYING 首次 / 重开 / run-over no-op）+ `breakout_grids` 组断言 + 升级钩子分发用例（DESIGN 附录 B.5）
- [ ] **验证点**：全量回归全绿 + `auto_play_test.gd` 100 局——首波路径必须实际跑通（AC2/AC5 前置；组装后首波不触发即验收失败）

**不动文件例外说明：** `game_state_machine.gd` / `wave_controller.gd` 由「不动」改为「仅新增 additive 触发方法/调用，既有逻辑零改动」（理由见 DESIGN 附录 B.1 差异记录）。

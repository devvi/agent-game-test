# Tasks: [Feature] 双得分制 (Dual Scoring)

> **Parent Issue:** #385
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Design:** docs/DESIGN/385-dual-scoring-system.md
> **深度:** depth/standard（影响文件 ≥10，满足 TASKS 阈值）
> **所有权:** `content_ownership: mechanical` — 机械实现，无需人审

---

## Phase 1: 常量与全局状态（P0，核心链路地基）
- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): 新增 Dual Scoring 常量组 —— `BRICK_SCORE=1`、`PIERCE_SCORE=3`、`WIN_SCORE=21`、`GRID_WALL_Y=640.0`、`WALL_BAND_HALF_HEIGHT=22.0`；`POINTS_TO_WIN_GAME`/`GAMES_TO_WIN_MATCH` 标记弃用（DESIGN §2.1）
- [ ] Task 2 (`mini-pong/gdscripts/game_manager.gd`): 新增 4 个计数状态（player/ai × brick/pierce）+ `_is_run_over`；`add_score(winner, amount, kind)` 扩展；`_check_run_end()` 21 分终局 → `match_over`；`get_brick_count`/`get_pierce_count`/`is_run_over`；`reset_match()` 全量重置；删除局/比赛分层（games_won/get_winner/game_won 信号）（DESIGN §2.2）

## Phase 2: ball 归属与穿越状态（P0）
- [ ] Task 3 (`mini-pong/gdscripts/ball.gd`): 新增 `last_toucher`（`_on_area_entered` 按节点名 `PlayerPaddle`/`AIPaddle` 判定）与 `_crossed_wall`（墙带**边沿触发**置位，`wall_y ± WALL_BAND_HALF_HEIGHT`）；`serve()` 与挡板触球时复位两者；walls/paddles 既有分支零改动（DESIGN §2.4）

## Phase 3: 场景侧事件消费（P0）
- [ ] Task 4 (`mini-pong/gdscripts/scoring_manager.gd`): 重构为薄事件路由 —— `_on_ball_score` 穿墙 3 分/普通 1 分判定 → `GameManager.add_score`；新增 `_on_brick_destroyed`（读 `ball.last_toucher`，空值跳过，`get_node_or_null("../BreakoutGrid")` 容错连接）；同帧去重 `_brick_destroyed_this_frame`；删除本地局/比赛追踪与 game_won/match_over 信号（DESIGN §2.3、§4 Flow 5）

## Phase 4: FSM 与结算屏（P1，可与 Phase 5 并行）
- [ ] Task 5 (`mini-pong/gdscripts/game_state_machine.gd`): SCORED 状态 1s 后判定改为 `GameManager.is_run_over()` → GAME_OVER / SERVING（DESIGN §2.5）
- [ ] Task 6 (`mini-pong/gdscripts/game_over_screen.gd`): `_on_match_over` 读取 `get_brick_count`/`get_pierce_count` 写入 `RunStatsLabel`（`get_node_or_null` 容错，布局归 #391）（DESIGN §2.7）

## Phase 5: 测试改造与验收（P0）
- [ ] Task 7 (`mini-pong/tests/test_game_manager.gd`): 重写 —— 移除 5 分/2 局断言；`add_score(winner, amount, kind)`、计数、21 分终局恰好一次、is_run_over、查询 API、reset_match（DESIGN §2.9 / §9 Scenario C/E）
- [ ] Task 8 (`mini-pong/tests/test_scoring_manager.gd`): 重写 —— 出界 3/1 路由、brick_destroyed 消费（含空触球者）、拆砖不触发 scored、终局守卫（§9 Scenario A/B/H）
- [ ] Task 9 (`mini-pong/tests/test_ball.gd`): 扩展 —— last_toucher/_crossed_wall 生命周期（边沿置位、发球位不误置位、触球/发球复位）（§9 Scenario F）
- [ ] Task 10 (`mini-pong/tests/test_constants.gd`): 扩展 —— 新常量断言（§9 Scenario G-4）
- [ ] Task 11 (`mini-pong/tests/test_dual_scoring.gd`): **新建** —— §9 场景 A–I 的可运行实现（拆砖归属/穿墙 3 分/21 分终局/同帧去重/查询 API/失败路径）
- [ ] Task 12 (`mini-pong/tests/run_tests.gd`): 注册 `test_dual_scoring.gd`
- [ ] Task 13 (验收): `godot --headless --script tests/run_tests.gd` 全绿（含既有套件零回归）

## 明确不做（范围边界）
- ❌ `mini-pong/gdscripts/paddle.gd`（按节点名判定，无需分组）
- ❌ `mini-pong/gdscripts/game_hud.gd`（总分联动已满足 AC1；细分 UI 归 #390/#392）
- ❌ `mini-pong/scenes/Main.tscn`（BreakoutGrid 接线归 #393）
- ❌ `wall_cleared()` 消费（归 #386）
- ❌ 任何 taste/视觉内容（破砖闪光/穿墙脉冲归 taste-draft UI Issues）

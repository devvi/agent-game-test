# Tasks: 游戏波数触发迭代 — 特殊砖触发升级（Special-Brick Wave Trigger）

> **Parent Issue:** #529
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **来源:** docs/DESIGN/529-wave-trigger-special-brick.md（§3 详细设计 + §8 测试映射）
> **文件白名单（8 文件）:** constants.gd / brick.gd / breakout_grid.gd / wave_controller.gd / ball.gd + 3 个测试文件；红线见 DESIGN §7

## Phase 1: 机械核心（P0，实现顺序）

- [ ] 1.1 (`mini-pong/gdscripts/constants.gd`)：文件末尾追加 `SPECIAL_BRICK_*` 区 4 常量（`PER_WAVE=1` / `MIN_THICKNESS=3` / `COLOR` / `GLOW_COLOR`，色值 taste 占位）；既有区逐字节不动（DESIGN §3.1）
- [ ] 1.2 (`mini-pong/gdscripts/brick.gd`)：加 `const CONSTS = preload(...)`；`var is_special := false`、`var breaker := ""`；`destroy(source := "")` 签名（`breaker = source` 快照）；`apply_special_visual()`（ColorRect 判空 no-op + 改色 + 材质 `duplicate()` 后 `set_shader_parameter("glow_color", ...)`，#464 教训）（DESIGN §3.2）
- [ ] 1.3 (`mini-pong/gdscripts/breakout_grid.gd`)：新信号 `special_brick_destroyed(breaker: String)`；`generate_wave` 末尾（`_consume_pending_holes()` 之后、`wall_generated.emit` 之前）调 `_spawn_special_brick()`；实现 `_spawn_special_brick` / `_pick_internal_brick`（位置量化 0.5 网格字典 + 4 邻域距离判定 + 距墙中心最近选择）/ `_key` / `_wall_center_local`；`_on_brick_destroyed` 加 `is_special && breaker != ""` emit 分支；`blast_neighbors` / `_remove_column` 改 `b.destroy("upgrade")`（DESIGN §3.3）
- [ ] 1.4 (`mini-pong/gdscripts/wave_controller.gd`)：`_on_wall_cleared` 主体抽 `_begin_settlement()`（行为逐位一致）；新增 `_on_special_brick_destroyed(breaker)`（守卫 → 记录 → `_begin_settlement`）；`_ready` 加 `special_brick_destroyed` has_signal 双守卫接线；`@onready var ball = get_node_or_null("../Ball")`（仅记录，null 跳过）（DESIGN §3.5）
- [ ] 1.5 (`mini-pong/gdscripts/ball.gd`)：bricks 分支 `body.destroy()` → `body.destroy(last_toucher)`（1 行）（DESIGN §3.4）

## Phase 2: 测试扩展（P0，依赖 Phase 1）

- [ ] 2.1 (`mini-pong/tests/test_breakout_grid.gd`)：Scenario A（A1-A3 常量/机械约束）+ Scenario B（B1-B7 内部位生成/薄墙回退/可复现/挂起洞/容错/计数）（DESIGN §8）
- [ ] 2.2 (`mini-pong/tests/test_wave_cycle.gd`)：Scenario C 新 H 组（C1-C10 全链路/不等墙空/对称触发/发球直撞/同帧去重/结算期忽略/终局竞态/升级连锁/回退回归/MAX_INDEX）（DESIGN §8）
- [ ] 2.3 (`mini-pong/tests/test_dual_scoring.gd`)：Scenario D 新 J 组（D1 拆砖分不变式 / D2 发球直撞零分）（DESIGN §8）

## Phase 3: 验证（P1）

- [ ] 3.1 全量套件全绿（run_tests.gd，24 套件零回归）
- [ ] 3.2 `godot --path mini-pong --headless --quit` 无脚本错误
- [ ] 3.3 E2E 视觉回归（`run-e2e-review.sh --with-visual`：01_title theme_absent / 02_midgame 4 重断言；需图形环境，软性依赖）
- [ ] 3.4 文件域核查：PR files ⊆ 白名单 8 文件；DESIGN §6 集成点表 ⬜ 全部勾选 ✅

## Phase 4: taste 定稿（P2，human-review）

- [ ] 4.1 `SPECIAL_BRICK_COLOR` / `SPECIAL_BRICK_GLOW_COLOR` 占位值 human-review 定稿（调参零代码改动；机械约束：避开 #4a90d9 tol 32、与 BRICK_NEON 可区分，DESIGN §3.1）

# Tasks: [Feature] 波次循环 (Wave Cycle)

> **Parent Issue:** #386
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Design:** docs/DESIGN/386-wave-cycle.md
> **深度:** depth/standard（波次循环涉及 7 个代码文件 + 2 文档，按 #385 惯例产出 TASKS 供 implement 使用）
> **所有权:** `content_ownership: mechanical` — 机械实现，无需人审（难度数值曲线归 taste-draft）

---

## Phase 1: 常量与波次状态机（P0，核心链路地基）
- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): 新增 Wave Cycle 常量组 —— `WAVE_START_THICKNESS=1`、`WAVE_THICKNESS_STEP=1`、`WAVE_MAX_INDEX=99`、`WAVE_SETTLE_DELAY=1.0`、`AI_DIFFICULTY_FACTOR=0.9`、`AI_REACTION_DELAY_MIN_FLOOR=0.05`、`AI_REACTION_DELAY_MAX_FLOOR=0.12`、`AI_POSITION_ERROR_FLOOR=8.0`（DESIGN §2.1）
- [ ] Task 2 (`mini-pong/gdscripts/game_manager.gd`): 新增波次状态机 —— `enum WaveState { IDLE, RUNNING, SETTLED }`、`wave_started(wave_index)` / `wave_settled(wave_index)` 信号、`wave_index`（IDLE 期 0）/`wave_state`、`begin_wave()` / `settle_wave()` / `end_wave_cycle()` / `is_wave_cycle_active()`；`reset_match()` 追加 `wave_index=0` + `wave_state=IDLE`（DESIGN §2.2）

## Phase 2: 场景侧编排（P0）
- [ ] Task 3 (`mini-pong/gdscripts/wave_controller.gd`): **新建** —— `get_node_or_null("../BreakoutGrid")` / `("../AIPaddle")` 容错引用；`_ready()` 按 `has_signal("wall_cleared")` 条件连接；`_on_wall_cleared()`（`_settling` + `is_run_over()` 双守卫 → `settle_wave()` → 21 分则 `end_wave_cycle()` 停止 → 否则 `WAVE_SETTLE_DELAY` 延时后 `_advance_wave()`）；`_advance_wave()`（`begin_wave()` → `_apply_difficulty()` → `generate_wave(thickness, 0, -1)`，grid 无 `generate_wave` 方法时 `push_warning` 跳过但状态机照常推进）；`_wave_thickness(index)` 线性公式；`_apply_difficulty(index)` AI 参数收紧 + FLOOR clamp（DESIGN §3.1）

## Phase 3: 测试改造与验收（P0）
- [ ] Task 4 (`mini-pong/tests/test_wave_cycle.gd`): **新建** —— mock BreakoutGrid（模拟 #414 契约：`wall_cleared` 信号 + `generate_wave` 先清空再生成 + `remaining_bricks` + 调用记录）与 mock paddle；§9 场景 A–G 可运行实现（波次推进/难度递增/wave_index 生命周期/旧墙不叠加/21 分停止/容错守卫/重置防御）
- [ ] Task 5 (`mini-pong/tests/test_game_manager.gd`): 扩展 —— wave API 单元断言（begin/settle/end/is_wave_cycle_active 状态转移 + reset_match 重置）（§9 Scenario G-2）
- [ ] Task 6 (`mini-pong/tests/test_constants.gd`): 扩展 —— `WAVE_*` / `AI_DIFFICULTY_*` 常量断言（§9 Scenario G-3）
- [ ] Task 7 (`mini-pong/tests/run_tests.gd`): 注册 `test_wave_cycle.gd`
- [ ] Task 8 (验收): `godot --headless --script tests/run_tests.gd` 全绿（含既有 14+ 套件零回归）

## 明确不做（范围边界）
- ❌ `mini-pong/gdscripts/game_state_machine.gd`（AC5 复用既有 `match_over → GAME_OVER`，零改动）
- ❌ `mini-pong/gdscripts/game_hud.gd` / `game_over_screen.gd`（波次号 UI 与 run 统计布局归 #390/#391/#393；本 Issue 只保证 `wave_index` 可读 + 信号）
- ❌ `mini-pong/scenes/Main.tscn`（WaveController / BreakoutGrid 接线归 #393）
- ❌ `mini-pong/gdscripts/upgrade_pool.gd` 触发（#388 消费 `wave_settled` 挂点）
- ❌ `mini-pong/gdscripts/ball.gd`（零改动）
- ❌ 任何 taste/视觉内容（波次难度数值曲线、墙布局轮换归 taste-draft）

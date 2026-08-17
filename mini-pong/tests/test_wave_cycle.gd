extends RefCounted
## Wave Cycle test suite (#386) — 波次循环。
## Covers DESIGN docs/DESIGN/386-wave-cycle.md §9 Scenarios A–G（测试契约）。
## (Scenario E-3: FSM 既有 match_over → GAME_OVER 路径由 test_integration_fsm 覆盖，本套件零新增接线)
##
## Uses the REAL GameManager autoload (reset between tests) + isolated WaveController
## instances in a mini tree with mock BreakoutGrid (#414 契约子集：wall_cleared 信号 +
## generate_wave 先清空再生成 + remaining_bricks + 调用记录) / mock AIPaddle (#387 实例级
## AI 参数) / mock RainCurtain (#389 契约 set_wave_factor)。
##
## Runs under godot --headless --script via run_tests.gd (_run_async — 结算延时 await 需要帧循环)。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const SHORT_SETTLE: float = 0.01   # 测试用短结算延时（DESIGN §9 A-2 明确允许）；生产默认 WAVE_SETTLE_DELAY
const WAIT: float = 0.05           # > SHORT_SETTLE 的等待余量

# ── Signal capture state (member vars, not lambda closures) ──
var _captured_wave_started: Array = []
var _captured_wave_settled: Array = []
var _grid_instances: int = 0

func _on_wave_started(index: int) -> void:
	_captured_wave_started.append(index)

func _on_wave_settled(index: int) -> void:
	_captured_wave_settled.append(index)

func _on_settled_reach_21(_index: int) -> void:
	## E-2: 模拟「最后一砖既清墙又使一方到 21 分」（wave_settled 挂点内加分）
	GameManager.add_score("player", 1, "brick")


func run() -> void:
	print("\n=== Wave Cycle Tests (#386) ===")
	GameManager.wave_started.connect(_on_wave_started)
	GameManager.wave_settled.connect(_on_wave_settled)

	# Scenario A: 波次推进 (AC1)
	await _test_a1_wall_cleared_settles()
	await _test_a2_settle_advances_wave()
	await _test_a3_thickness_increments()
	await _test_a4_three_waves()
	# Scenario B: 难度递增 (AC2)
	await _test_b1_thickness_strictly_increasing()
	await _test_b2_ai_params_tighten()
	await _test_b3_at_least_one_lever()
	await _test_b4_floor_clamp()
	# Scenario C: wave_index 生命周期 (AC3)
	await _test_c1_first_wave_is_one()
	await _test_c2_increments()
	await _test_c3_signal_payloads()
	await _test_c4_reset_zeroes()
	# Scenario D: 旧墙不叠加 (AC4)
	await _test_d1_single_instance()
	await _test_d2_only_generate_wave()
	await _test_d3_no_brick_residue()
	await _test_d4_duplicate_signal_ignored()
	# Scenario E: 21 分停止 (AC5)
	await _test_e1_no_settle_after_end()
	await _test_e2_end_wave_cycle_keeps_index()
	# Scenario F: 容错与守卫
	await _test_f1_no_grid_no_crash()
	await _test_f2_no_ai_paddle_thickness_still_works()
	await _test_f3_settling_ignores_duplicate()
	await _test_f4_generate_wave_missing()
	# Scenario G: 重置与防御
	await _test_g1_max_index_defense()
	# Scenario H: #529 特殊砖触发链路（真实 grid，PRD #529 §5.1 AC1–AC5）
	await _test_h1_special_full_chain()
	await _test_h2_not_wait_wall_clear()
	await _test_h3_ai_symmetric()
	await _test_h4_empty_breaker()
	await _test_h5_same_frame_dedup()
	await _test_h6_settling_ignored()
	await _test_h7_run_over()
	await _test_h8_upgrade_chain()
	await _test_h9_thin_wall_fallback()
	await _test_h10_max_index()
	GameManager.wave_started.disconnect(_on_wave_started)
	GameManager.wave_settled.disconnect(_on_wave_settled)
	print("  Wave Cycle: %d passed, %d failed" % [passed, failed])


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout


func _reset() -> void:
	GameManager.reset_match()
	_captured_wave_started.clear()
	_captured_wave_settled.clear()
	_grid_instances = 0   # D-1: 每测试独立计数（WaveController 绝不 new 网格）


func _make_mock_grid(with_generate: bool) -> Node2D:
	## Mock BreakoutGrid — #414 契约子集：wall_cleared 信号 + generate_wave 先清空再生成
	## + remaining_bricks + 调用记录。with_generate=false 模拟 #384 未落地的半实现 grid
	## （有 wall_cleared 信号但无 generate_wave 方法，失败路径 4）。
	_grid_instances += 1
	var code = GDScript.new()
	if with_generate:
		code.source_code = """extends Node2D
## Mock BreakoutGrid (#414 契约子集，test_wave_cycle.gd 内部使用)

signal wall_cleared()

var remaining_bricks: int = 0
var generate_calls: Array = []
var clear_calls: int = 0

func generate_wave(thickness: int, layout: int, seed: int) -> void:
	clear_wall()
	generate_calls.append([thickness, layout, seed])
	remaining_bricks = thickness

func clear_wall() -> void:
	clear_calls += 1
	remaining_bricks = 0
"""
	else:
		code.source_code = """extends Node2D
## Mock BreakoutGrid — 半实现（无 generate_wave，失败路径 4）

signal wall_cleared()
"""
	code.reload()
	var grid = Node2D.new()
	grid.name = "BreakoutGrid"
	grid.set_script(code)
	return grid


func _make_mock_paddle() -> Node2D:
	## Mock AIPaddle — #387 实例级 AI 参数（@export 同名字段）。
	var code = GDScript.new()
	code.source_code = """extends Node2D
## Mock AIPaddle (test_wave_cycle.gd 内部使用)

var ai_reaction_delay_min: float = 0.15
var ai_reaction_delay_max: float = 0.4
var ai_position_error: float = 24.0
"""
	code.reload()
	var paddle = Node2D.new()
	paddle.name = "AIPaddle"
	paddle.set_script(code)
	# 与 constants.gd 定稿值对齐（#367），保证 FLOOR clamp 断言基于真实常量
	paddle.ai_reaction_delay_min = CONSTS.AI_REACTION_DELAY_MIN
	paddle.ai_reaction_delay_max = CONSTS.AI_REACTION_DELAY_MAX
	paddle.ai_position_error = CONSTS.AI_POSITION_ERROR
	return paddle


func _make_mock_rain() -> Node2D:
	## Mock RainCurtain — #389 契约 API set_wave_factor（记录 wave_index）。
	var code = GDScript.new()
	code.source_code = """extends Node2D
## Mock RainCurtain (#389 契约，test_wave_cycle.gd 内部使用)

var wave_factor: int = -1

func set_wave_factor(index: int) -> void:
	wave_factor = index
"""
	code.reload()
	var rain = Node2D.new()
	rain.name = "RainCurtain"
	rain.set_script(code)
	return rain


func _make_controller(with_grid: bool = true, with_paddle: bool = true, with_rain: bool = true, with_grid_generate: bool = true) -> Dictionary:
	## 建真实 mini-tree 让 _ready() 运行（@onready get_node_or_null 解析），
	## 与 test_dual_scoring 的 mock tree 同模式。
	## 返回 {host, controller, grid, paddle, rain}；未挂载项为 null。
	var tree = Engine.get_main_loop() as SceneTree
	var host = Node2D.new()
	host.name = "TestHost"
	tree.root.add_child(host)

	var grid = null
	if with_grid:
		grid = _make_mock_grid(with_grid_generate)
		host.add_child(grid)

	var atmosphere = Node2D.new()
	atmosphere.name = "AtmosphereLayer"
	host.add_child(atmosphere)
	var rain_node = null
	if with_rain:
		rain_node = _make_mock_rain()
		atmosphere.add_child(rain_node)

	var paddle_node = null
	if with_paddle:
		paddle_node = _make_mock_paddle()
		host.add_child(paddle_node)

	var controller = Node.new()
	controller.set_script(load("res://gdscripts/wave_controller.gd"))
	controller.name = "WaveController"
	host.add_child(controller)
	controller.settle_delay = SHORT_SETTLE   # 测试用短延时（生产默认 WAVE_SETTLE_DELAY）

	return {"host": host, "controller": controller, "grid": grid, "paddle": paddle_node, "rain": rain_node}


func _cleanup(fx: Dictionary) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var host = fx.get("host")
	if host != null and is_instance_valid(host) and host.get_parent() != null:
		host.get_parent().remove_child(host)
		host.queue_free()


# ── Scenario A: 波次推进 (AC1) ──

## A-1: 墙清空进入结算 → wave_state == SETTLED、wave_settled 恰好一次且负载 == 当前 wave_index
func _test_a1_wall_cleared_settles() -> void:
	_reset()
	var fx = _make_controller()
	fx.controller._advance_wave()   # 波 1 开始（RUNNING，wave_index=1，generate 一次）
	_captured_wave_settled.clear()
	fx.grid.wall_cleared.emit()

	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "A-1: 墙清空 → SETTLED")
	_assert(_captured_wave_settled.size() == 1, "A-1: wave_settled 恰好一次")
	_assert(_captured_wave_settled[0] == 1, "A-1: wave_settled 负载 == 当前 wave_index(1)")

	await _wait(WAIT)   # 等结算延时协程跑完再清理（防悬挂协程）
	_cleanup(fx)


## A-2: 结算后自动下一波 → wave_index +1、RUNNING、wave_started 一次、generate_wave 被调
func _test_a2_settle_advances_wave() -> void:
	_reset()
	var fx = _make_controller()
	fx.controller._advance_wave()   # 波 1
	_captured_wave_started.clear()
	_captured_wave_settled.clear()
	fx.grid.wall_cleared.emit()
	await _wait(WAIT)   # SHORT_SETTLE(0.01) 后自动推进

	_assert(GameManager.wave_index == 2, "A-2: 结算延时后 wave_index == 2")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "A-2: 自动进下一波 → RUNNING")
	_assert(_captured_wave_started.size() == 1 and _captured_wave_started[0] == 2,
		"A-2: wave_started 恰好一次且负载 == 2")
	_assert(fx.grid.generate_calls.size() == 2, "A-2: 第二波 generate_wave 被调（波1 + 波2）")
	_assert(fx.rain.wave_factor == 2, "A-2: #389 雨幕波次因子 == wave_index(2)")
	_cleanup(fx)


## A-3: 生成参数递增 — 波 N 与波 N+1 的 thickness 差 == WAVE_THICKNESS_STEP
func _test_a3_thickness_increments() -> void:
	_reset()
	var fx = _make_controller()
	fx.controller._advance_wave()
	fx.controller._advance_wave()
	var t1: int = fx.grid.generate_calls[0][0]
	var t2: int = fx.grid.generate_calls[1][0]
	_assert(t2 - t1 == CONSTS.WAVE_THICKNESS_STEP, "A-3: 相邻波 thickness 差 == WAVE_THICKNESS_STEP")
	_assert(t2 == CONSTS.WAVE_START_THICKNESS + CONSTS.WAVE_THICKNESS_STEP, "A-3: 第 2 波厚度 == 起始 + 步进")
	_cleanup(fx)


## A-4: 连续 3 次 wall_cleared → wave_index == 3、generate_wave 恰好 3 次（无跳过/无重复）
func _test_a4_three_waves() -> void:
	_reset()
	var fx = _make_controller()
	fx.controller._advance_wave()   # 波 1（直调，免去首波延时）
	for i in range(2):
		fx.grid.wall_cleared.emit()
		await _wait(WAIT)

	_assert(GameManager.wave_index == 3, "A-4: 连续 3 波后 wave_index == 3")
	_assert(fx.grid.generate_calls.size() == 3, "A-4: generate_wave 恰好 3 次（无跳过/无重复）")
	_assert(fx.grid.generate_calls[2][0] == 3, "A-4: 第 3 波厚度 == 3")
	_cleanup(fx)


# ── Scenario B: 难度递增 (AC2) ──

## B-1: 厚度严格递增
func _test_b1_thickness_strictly_increasing() -> void:
	_reset()
	var fx = _make_controller()
	_assert(fx.controller._wave_thickness(2) > fx.controller._wave_thickness(1), "B-1: thickness(2) > thickness(1)")
	_assert(fx.controller._wave_thickness(2) == CONSTS.WAVE_START_THICKNESS + CONSTS.WAVE_THICKNESS_STEP,
		"B-1: thickness(2) == 起始 + 步进")
	_cleanup(fx)


## B-2: AI 参数每波收紧且 ≥ FLOOR（clamp 不越界）
func _test_b2_ai_params_tighten() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	var paddle = fx.paddle
	var min0: float = paddle.ai_reaction_delay_min
	var max0: float = paddle.ai_reaction_delay_max
	var err0: float = paddle.ai_position_error

	ctrl._advance_wave()   # 波 1
	ctrl._advance_wave()   # 波 2

	_assert(paddle.ai_reaction_delay_min < min0, "B-2: ai_reaction_delay_min 收紧")
	_assert(paddle.ai_reaction_delay_max < max0, "B-2: ai_reaction_delay_max 收紧")
	_assert(paddle.ai_position_error < err0, "B-2: ai_position_error 收紧")
	_assert(paddle.ai_reaction_delay_min >= CONSTS.AI_REACTION_DELAY_MIN_FLOOR, "B-2: min ≥ FLOOR")
	_assert(paddle.ai_reaction_delay_max >= CONSTS.AI_REACTION_DELAY_MAX_FLOOR, "B-2: max ≥ FLOOR")
	_assert(paddle.ai_position_error >= CONSTS.AI_POSITION_ERROR_FLOOR, "B-2: err ≥ FLOOR")
	_cleanup(fx)


## B-3: 至少一项严格递增（双杠杆都实现，实际两者同时成立）
func _test_b3_at_least_one_lever() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	var paddle = fx.paddle
	var min0: float = paddle.ai_reaction_delay_min

	ctrl._advance_wave()
	ctrl._advance_wave()

	var thickness_up: bool = ctrl._wave_thickness(3) > ctrl._wave_thickness(2)
	var ai_tighter: bool = paddle.ai_reaction_delay_min < min0
	_assert(thickness_up or ai_tighter, "B-3: 相邻波「厚度更大 或 AI 更紧」恒真")
	_assert(thickness_up and ai_tighter, "B-3: 双杠杆同时成立（强度断言）")
	_cleanup(fx)


## B-4: 多波循环后参数不低于 FLOOR（不趋零/不 NaN）
func _test_b4_floor_clamp() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	var paddle = fx.paddle

	for i in range(60):
		ctrl._advance_wave()

	_assert(paddle.ai_reaction_delay_min >= CONSTS.AI_REACTION_DELAY_MIN_FLOOR - 0.0001, "B-4: min 不低于 FLOOR")
	_assert(paddle.ai_reaction_delay_max >= CONSTS.AI_REACTION_DELAY_MAX_FLOOR - 0.0001, "B-4: max 不低于 FLOOR")
	_assert(paddle.ai_position_error >= CONSTS.AI_POSITION_ERROR_FLOOR - 0.0001, "B-4: err 不低于 FLOOR")
	_assert(not is_nan(paddle.ai_reaction_delay_min) and not is_nan(paddle.ai_position_error), "B-4: 无 NaN")
	_cleanup(fx)


# ── Scenario C: wave_index 生命周期 (AC3) ──

## C-1: reset 后首次 begin_wave → wave_index == 1
func _test_c1_first_wave_is_one() -> void:
	_reset()
	GameManager.begin_wave()
	_assert(GameManager.wave_index == 1, "C-1: 首波 wave_index == 1")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "C-1: 首波 RUNNING")


## C-2: 连续两波 → wave_index == 2
func _test_c2_increments() -> void:
	_reset()
	GameManager.begin_wave()
	GameManager.begin_wave()
	_assert(GameManager.wave_index == 2, "C-2: 连续两波 wave_index == 2")


## C-3: 信号负载与 wave_index 一致（可读性契约，#390/#393 依赖）
func _test_c3_signal_payloads() -> void:
	_reset()
	GameManager.begin_wave()
	GameManager.settle_wave()
	_assert(_captured_wave_started.size() == 1 and _captured_wave_started[0] == GameManager.wave_index,
		"C-3: wave_started 负载一致")
	_assert(_captured_wave_settled.size() == 1 and _captured_wave_settled[0] == GameManager.wave_index,
		"C-3: wave_settled 负载一致")


## C-4: reset_match → wave_index == 0、IDLE、is_wave_cycle_active == false
func _test_c4_reset_zeroes() -> void:
	_reset()
	GameManager.begin_wave()
	GameManager.settle_wave()
	GameManager.reset_match()
	_assert(GameManager.wave_index == 0, "C-4: reset 后 wave_index == 0")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "C-4: reset 后 IDLE")
	_assert(GameManager.is_wave_cycle_active() == false, "C-4: reset 后 is_wave_cycle_active == false")


# ── Scenario D: 旧墙不叠加 (AC4) ──

## D-1: 整轮测试中 mock grid 实例化次数 == 1（WaveController 绝不 new 网格）
func _test_d1_single_instance() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	ctrl._advance_wave()
	ctrl._advance_wave()
	ctrl._advance_wave()
	_assert(_grid_instances == 1, "D-1: 3 波后 grid 实例数 == 1（单实例）")
	_cleanup(fx)


## D-2: 只调 generate_wave（清理由其内部保证）— clear_calls 只能来自 generate_wave 内部
func _test_d2_only_generate_wave() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	ctrl._advance_wave()
	ctrl._advance_wave()
	_assert(grid.clear_calls == grid.generate_calls.size(),
		"D-2: clear_wall 调用数 == generate_wave 调用数（无外部直接 clear_wall）")
	_cleanup(fx)


## D-3: 连续 3 波后 mock 砖计数 == 第 3 波应生成数（0 残留）
func _test_d3_no_brick_residue() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	ctrl._advance_wave()
	ctrl._advance_wave()
	_assert(grid.remaining_bricks == 3, "D-3: 3 波后 remaining_bricks == 第 3 波厚度 3（0 残留）")
	_cleanup(fx)


## D-4: 同一墙连发两次 wall_cleared → 只推进一波（_settling 守卫，边界 4）
func _test_d4_duplicate_signal_ignored() -> void:
	_reset()
	var fx = _make_controller()
	var grid = fx.grid
	fx.controller._advance_wave()
	_captured_wave_settled.clear()

	grid.wall_cleared.emit()
	grid.wall_cleared.emit()   # 重复信号（模拟 #384 守卫失效的异常 grid）
	_assert(_captured_wave_settled.size() == 1, "D-4: 重复 wall_cleared 只 settle 一次")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "D-4: 仍处 SETTLED")
	await _wait(WAIT)
	_cleanup(fx)


# ── Scenario E: 21 分停止 (AC5) ──

## E-1: 终局后 wall_cleared → 不结算、不生成、状态不变
func _test_e1_no_settle_after_end() -> void:
	_reset()
	for i in range(21):
		GameManager.add_score("player")
	_assert(GameManager.is_run_over() == true, "E-1: 前置 is_run_over == true")

	var fx = _make_controller()
	var grid = fx.grid
	fx.grid.wall_cleared.emit()
	_assert(_captured_wave_settled.size() == 0, "E-1: 终局后无 wave_settled")
	_assert(_captured_wave_started.size() == 0, "E-1: 终局后无 wave_started")
	_assert(grid.generate_calls.size() == 0, "E-1: 终局后不生成新墙")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "E-1: 波次状态不变（IDLE）")
	_cleanup(fx)


## E-2: 结算时 is_run_over() 变 true（最后一砖到 21 分）→ end_wave_cycle：IDLE、不生成、wave_index 保留
func _test_e2_end_wave_cycle_keeps_index() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()   # 波 1
	for i in range(20):
		GameManager.add_score("player")   # 差 1 分到 21

	GameManager.wave_settled.connect(_on_settled_reach_21)
	grid.wall_cleared.emit()   # 最后一砖: 清墙 + 21 分
	GameManager.wave_settled.disconnect(_on_settled_reach_21)

	_assert(GameManager.is_run_over() == true, "E-2: 结算时到 21 分 → run over")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "E-2: end_wave_cycle → IDLE")
	_assert(GameManager.wave_index == 1, "E-2: wave_index 保留（run 统计可读）")
	_assert(grid.generate_calls.size() == 1, "E-2: 不再生成新墙（仅波 1 那次）")
	_cleanup(fx)


# ── Scenario F: 容错与守卫 ──

## F-1: 无 BreakoutGrid 节点 → _ready 不崩、波次状态机保持 IDLE
func _test_f1_no_grid_no_crash() -> void:
	_reset()
	var fx = _make_controller(false)
	_assert(fx.controller.breakout_grid == null, "F-1: 无 grid → breakout_grid == null（不崩）")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "F-1: 波次状态机保持 IDLE")
	_assert(GameManager.wave_index == 0, "F-1: wave_index == 0")
	_cleanup(fx)


## F-2: 无 ai_paddle → AI 缩放跳过 + 警告；厚度杠杆仍生效（AC2 不失效）
func _test_f2_no_ai_paddle_thickness_still_works() -> void:
	_reset()
	var fx = _make_controller(true, false)
	fx.controller._advance_wave()
	_assert(GameManager.wave_index == 1, "F-2: 状态机照常推进")
	_assert(fx.grid.generate_calls.size() == 1 and fx.grid.generate_calls[0][0] == CONSTS.WAVE_START_THICKNESS,
		"F-2: 厚度杠杆仍生效（首波厚度 == WAVE_START_THICKNESS）")
	_cleanup(fx)


## F-3: _settling 期间重复 wall_cleared → 忽略（边界 4）
func _test_f3_settling_ignores_duplicate() -> void:
	_reset()
	var fx = _make_controller()
	var grid = fx.grid
	fx.controller._advance_wave()
	_captured_wave_settled.clear()

	grid.wall_cleared.emit()
	var settled_count: int = _captured_wave_settled.size()
	grid.wall_cleared.emit()
	_assert(_captured_wave_settled.size() == settled_count, "F-3: 结算中重复信号被忽略")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "F-3: 仍 SETTLED")
	await _wait(WAIT)
	_cleanup(fx)


## F-4: grid 有 wall_cleared 但无 generate_wave → 警告跳过生成，wave_index 仍 +1（状态机不卡死）
func _test_f4_generate_wave_missing() -> void:
	_reset()
	var fx = _make_controller(true, true, true, false)   # 半实现 grid：有信号无 generate_wave
	fx.grid.wall_cleared.emit()   # 触发 _on_wall_cleared → settle（IDLE 期 no-op）→ 延时后 advance
	await _wait(WAIT)

	_assert(GameManager.wave_index == 1, "F-4: generate_wave 不可用仍 wave_index +1（不卡死）")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "F-4: 状态机推进到 RUNNING")
	_assert(_captured_wave_started.size() == 1 and _captured_wave_started[0] == 1, "F-4: wave_started 发出")
	_cleanup(fx)


# ── Scenario G: 重置与防御 ──

## G-1: WAVE_MAX_INDEX 防御 — 达到上限后停止递增与生成
func _test_g1_max_index_defense() -> void:
	_reset()
	var fx = _make_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	GameManager.wave_index = CONSTS.WAVE_MAX_INDEX
	GameManager.wave_state = GameManager.WaveState.RUNNING

	ctrl._advance_wave()
	_assert(GameManager.wave_index == CONSTS.WAVE_MAX_INDEX, "G-1: 达上限不再递增")
	_assert(grid.generate_calls.size() == 0, "G-1: 达上限不再生成")
	_cleanup(fx)


# ── Scenario H: #529 特殊砖触发链路（PRD §5.1 AC1–AC5；DESIGN §8 Scenario C）──
# 特殊砖链路需要真实 BreakoutGrid（is_special / special_brick_destroyed / _spawn_special_brick），
# mock 只覆盖 #414 契约子集 → 用 _make_real_controller 建真实 mini-tree。

func _make_real_controller() -> Dictionary:
	## 真实 BreakoutGrid + 真实 WaveController 的 mini-tree（H 组专用）。
	## 返回 {host, controller, grid}；挂 SceneTree.root 触发 _ready（组注册 + 双守卫接线）。
	var tree = Engine.get_main_loop() as SceneTree
	var host = Node2D.new()
	host.name = "TestHost"
	tree.root.add_child(host)

	var grid = Node2D.new()
	grid.set_script(load("res://gdscripts/breakout_grid.gd"))
	grid.name = "BreakoutGrid"
	host.add_child(grid)   # _ready: breakout_grids 组 + brick_scene 惰性加载 + 升级钩子

	var controller = Node.new()
	controller.set_script(load("res://gdscripts/wave_controller.gd"))
	controller.name = "WaveController"
	host.add_child(controller)   # _ready: wall_cleared / special_brick_destroyed 双守卫接线
	controller.settle_delay = SHORT_SETTLE   # 测试用短结算延时（DESIGN §9 A-2 允许）
	controller.settle_hold = true            # H 组用显式 advance_settlement() 驱动推进（#388 接管）

	return {"host": host, "controller": controller, "grid": grid}


func _grid_brick_children(grid) -> Array:
	var out: Array = []
	for child in grid.get_children():
		if child.is_in_group("bricks"):
			out.append(child)
	return out


func _find_special_brick(grid) -> Node2D:
	for child in grid.get_children():
		if child.is_in_group("bricks") and child.is_special:
			return child
	return null


## H-1（AC2 全链路）：击碎特殊砖 → wave_settled → advance_settlement → 下一波含新特殊砖。
## 建波 2（推进后新墙厚 3 才有内部位）→ 换确定性 3 行墙 → destroy("player")
func _test_h1_special_full_chain() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	ctrl._advance_wave()          # 波 2（RUNNING，wave_index=2；下一波厚 3 有内部位）
	grid.generate_wave(3, 0, 42)  # 确定性厚墙（含特殊砖，seed 契约同 #384）
	await _wait(0.02)
	var special = _find_special_brick(grid)
	_assert(special != null, "H-1: 3 行墙含特殊砖")
	if special == null:
		_cleanup(fx)
		return
	_captured_wave_settled.clear()
	special.destroy("player")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "H-1: 特殊砖击碎 → SETTLED")
	_assert(_captured_wave_settled.size() == 1 and _captured_wave_settled[0] == 2,
		"H-1: wave_settled 恰好一次且负载 == 2")
	await _wait(WAIT)
	_assert(GameManager.wave_index == 2, "H-1: settle_hold 接管，wave_index 未自动推进")
	ctrl.advance_settlement()
	_assert(GameManager.wave_index == 3, "H-1: advance_settlement → wave_index +1")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "H-1: 推进后 RUNNING")
	await _wait(0.02)
	var new_special: int = 0
	for b in _grid_brick_children(grid):
		if b.is_special:
			new_special += 1
	_assert(new_special == 1, "H-1: 新墙（厚 3）含 1 颗特殊砖 (got %d)" % new_special)
	_cleanup(fx)


## H-2（AC3 不等墙空）：击碎特殊砖时剩余旧砖 > 0 → 轮换仍发生；advance 后旧砖全部清除
func _test_h2_not_wait_wall_clear() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	grid.generate_wave(3, 0, 42)
	await _wait(0.02)
	var old_bricks: Array = _grid_brick_children(grid)
	var old_count: int = old_bricks.size()
	_assert(old_count > 0, "H-2: 旧墙砖数 > 0 (got %d)" % old_count)
	var special = _find_special_brick(grid)
	if special == null:
		_cleanup(fx)
		return
	_captured_wave_settled.clear()
	special.destroy("player")
	_assert(_captured_wave_settled.size() == 1, "H-2: 未清空也轮换（wave_settled 发出）")
	_assert(grid.remaining_bricks == old_count - 1, "H-2: 剩余旧砖仍 > 0 (got %d)" % grid.remaining_bricks)
	ctrl.advance_settlement()
	await _wait(0.05)   # queue_free 生效
	var all_invalid: bool = true
	for b in old_bricks:
		if is_instance_valid(b):
			all_invalid = false
	_assert(all_invalid, "H-2: advance 后旧砖全部清除（is_instance_valid == false）")
	_cleanup(fx)


## H-3（方案 A 对称触发）：destroy("ai") → 同样 wave_settled（窗口归玩家，不断言 AI 分支）
func _test_h3_ai_symmetric() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	grid.generate_wave(3, 0, 42)
	await _wait(0.02)
	var special = _find_special_brick(grid)
	if special == null:
		_cleanup(fx)
		return
	_captured_wave_settled.clear()
	special.destroy("ai")
	_assert(_captured_wave_settled.size() == 1, "H-3: 方案 A 对称触发（ai 击碎同样 wave_settled）")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "H-3: SETTLED")
	await _wait(WAIT)
	_cleanup(fx)


## H-4（边界 2 发球直撞）：destroy("") → 不 wave_settled、不轮换；砖碎 + 计数减
func _test_h4_empty_breaker() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	grid.generate_wave(3, 0, 42)
	await _wait(0.02)
	var special = _find_special_brick(grid)
	if special == null:
		_cleanup(fx)
		return
	var before: int = grid.remaining_bricks
	_captured_wave_settled.clear()
	special.destroy("")   # 发球直撞（last_toucher == ""）
	_assert(grid.remaining_bricks == before - 1, "H-4: 砖碎 + 计数减 (got %d)" % grid.remaining_bricks)
	_assert(_captured_wave_settled.size() == 0, "H-4: 空 breaker 不 wave_settled")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "H-4: 不轮换（仍 RUNNING）")
	await _wait(WAIT)
	_cleanup(fx)


## H-5（边界 1 同帧去重）：特殊砖 = 最后一块 → special_brick_destroyed 与 wall_cleared 同帧
## → wave_settled 计数 == 1（_settling 守卫恰好一次）
func _test_h5_same_frame_dedup() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	grid.generate_wave(3, 0, 42)
	await _wait(0.02)
	var special = _find_special_brick(grid)
	if special == null:
		_cleanup(fx)
		return
	for b in _grid_brick_children(grid):
		if b != special:
			b.destroy("")   # 非特殊砖清掉（breaker == "" 不触发）
	_assert(grid.remaining_bricks == 1, "H-5: 仅剩特殊砖 (got %d)" % grid.remaining_bricks)
	_captured_wave_settled.clear()
	special.destroy("player")   # 最后一块 → 同帧 wall_cleared + special_brick_destroyed
	_assert(_captured_wave_settled.size() == 1,
		"H-5: 同帧双信号 → wave_settled 恰好一次 (got %d)" % _captured_wave_settled.size())
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "H-5: SETTLED")
	_assert(grid.remaining_bricks == 0, "H-5: remaining 归 0")
	await _wait(WAIT)
	_cleanup(fx)


## H-6（边界 5 结算期忽略）：_settling == true 期间再发 wall_cleared / special_brick_destroyed
## → 无二次结算（wave_settled 计数仍 1）
func _test_h6_settling_ignored() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	grid.generate_wave(3, 0, 42)
	await _wait(0.02)
	var special = _find_special_brick(grid)
	if special == null:
		_cleanup(fx)
		return
	_captured_wave_settled.clear()
	special.destroy("player")   # 首次结算 → _settling == true
	_assert(_captured_wave_settled.size() == 1, "H-6: 首次结算 wave_settled == 1")
	grid.wall_cleared.emit()
	grid.special_brick_destroyed.emit("player")
	_assert(_captured_wave_settled.size() == 1,
		"H-6: 结算中重复信号被忽略 (got %d)" % _captured_wave_settled.size())
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "H-6: 仍 SETTLED")
	await _wait(WAIT)
	_cleanup(fx)


## H-7（边界 6 终局竞态）：击碎特殊砖使一方到 21 分 → end_wave_cycle、不生成新墙、wave_index 冻结
func _test_h7_run_over() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	grid.generate_wave(3, 0, 42)
	await _wait(0.02)
	var special = _find_special_brick(grid)
	if special == null:
		_cleanup(fx)
		return
	for i in range(20):
		GameManager.add_score("player")   # 差 1 分到 21
	var index_before: int = GameManager.wave_index
	GameManager.wave_settled.connect(_on_settled_reach_21)   # 挂点内 add_score 到 21
	special.destroy("player")
	GameManager.wave_settled.disconnect(_on_settled_reach_21)
	_assert(GameManager.is_run_over() == true, "H-7: 结算时到 21 分 → run over")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "H-7: end_wave_cycle → IDLE")
	_assert(GameManager.wave_index == index_before, "H-7: wave_index 冻结")
	_assert(grid.remaining_bricks == 23, "H-7: 不生成新墙（剩余旧砖仍在，got %d）" % grid.remaining_bricks)
	_cleanup(fx)


## H-8（边界 4 升级连锁）：blast_neighbors 波及特殊砖（内部 destroy("upgrade")）→ wave_settled 触发
func _test_h8_upgrade_chain() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()
	grid.generate_wave(3, 0, 42)
	await _wait(0.02)
	var special = _find_special_brick(grid)
	if special == null:
		_cleanup(fx)
		return
	_captured_wave_settled.clear()
	grid.blast_neighbors(special.global_position, 200)
	_assert(_captured_wave_settled.size() == 1,
		"H-8: blast 波及特殊砖 → wave_settled 触发 (got %d)" % _captured_wave_settled.size())
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "H-8: SETTLED")
	await _wait(WAIT)
	_cleanup(fx)


## H-9（AC4 回退回归）：薄墙无特殊砖 → wall_cleared 路径照旧（a1 回归）
func _test_h9_thin_wall_fallback() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	var grid = fx.grid
	ctrl._advance_wave()   # 波 1：厚 1 薄墙
	var special_count: int = 0
	for b in _grid_brick_children(grid):
		if b.is_special:
			special_count += 1
	_assert(special_count == 0, "H-9: 薄墙（厚 1）无特殊砖 (got %d)" % special_count)
	_captured_wave_settled.clear()
	grid.wall_cleared.emit()   # 既有 a1 路径
	_assert(_captured_wave_settled.size() == 1, "H-9: wall_cleared 回退 → wave_settled (a1 回归)")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "H-9: SETTLED")
	await _wait(WAIT)
	_cleanup(fx)


## H-10（WAVE_MAX_INDEX 防御）：特殊砖路径同样受 _advance_wave 防御（g1 回归）
func _test_h10_max_index() -> void:
	_reset()
	var fx = _make_real_controller()
	var ctrl = fx.controller
	GameManager.wave_index = CONSTS.WAVE_MAX_INDEX
	GameManager.wave_state = GameManager.WaveState.RUNNING
	ctrl._advance_wave()
	_assert(GameManager.wave_index == CONSTS.WAVE_MAX_INDEX, "H-10: 达上限 wave_index 不变 (g1 回归)")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "H-10: 状态不变")
	_cleanup(fx)

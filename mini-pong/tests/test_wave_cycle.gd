extends RefCounted
## Wave Cycle test suite (#386) — 波次循环。
## Covers DESIGN docs/DESIGN/386-wave-cycle.md §9 Scenarios A–G.
## Uses the REAL GameManager autoload (reset between tests) + isolated WaveController
## instances in a mini tree with mock BreakoutGrid (#414 契约模拟) / mock AIPaddle.
## 结算延时测试使用真实 SceneTree 计时器（headless 已验证可用）。
## Runs under godot --headless --script via run_tests.gd (_run_async).

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const SETTLE_WAIT: float = 1.3   # > WAVE_SETTLE_DELAY(1.0) 的等待余量

# ── Signal capture state (member vars, not lambda closures) ──
var _wave_started: Array = []
var _wave_settled: Array = []
var _grid_instances: int = 0

func _on_wave_started(idx: int) -> void:
	_wave_started.append(idx)

func _on_wave_settled(idx: int) -> void:
	_wave_settled.append(idx)

func _on_settled_reach_21(_idx: int) -> void:
	## E-2: 模拟「最后一砖既清墙又使一方到 21 分」（wave_settled 挂点内加分）
	GameManager.add_score("player", 1, "brick")


func run() -> void:
	print("\n=== Wave Cycle Tests (#386) ===")
	GameManager.wave_started.connect(_on_wave_started)
	GameManager.wave_settled.connect(_on_wave_settled)

	# Scenario A: 波次推进 (AC1)
	await _test_a1_settle_then_next_wave()
	_test_a3_thickness_increment()
	await _test_a4_three_waves()
	# Scenario B: 难度递增 (AC2)
	_test_b1_thickness_strict_increase()
	_test_b2_ai_params_tighten()
	_test_b3_at_least_one_strict()
	_test_b4_floor_clamp()
	# Scenario C: wave_index 生命周期 (AC3)
	_test_c1_first_wave_is_1()
	_test_c2_increment()
	_test_c3_signal_payload()
	_test_c4_reset_resets()
	# Scenario D: 旧墙不叠加 (AC4)
	_test_d1_single_instance()
	_test_d2_only_generate_wave()
	_test_d3_no_residue()
	_test_d4_duplicate_ignored_once()
	# Scenario E: 21 分停止 (AC5)
	_test_e1_no_settle_after_end()
	_test_e2_stop_when_settle_reaches_21()
	# Scenario F: 容错与守卫
	_test_f1_no_grid_no_crash()
	_test_f2_no_ai_paddle()
	_test_f3_duplicate_during_settling()
	await _test_f4_generate_unavailable()
	# Scenario G: 重置与防御
	_test_g1_max_index_defense()

	GameManager.wave_started.disconnect(_on_wave_started)
	GameManager.wave_settled.disconnect(_on_wave_settled)
	print("  Wave Cycle: %d passed, %d failed" % [passed, failed])


# ── Mocks (#414 契约模拟) ──

const MOCK_GRID_SRC := """
extends Node2D
## Mock BreakoutGrid (#414 契约): wall_cleared 信号 + generate_wave 先清空再生成 + remaining_bricks + 调用记录。

signal wall_cleared

var remaining_bricks: int = 0
var generate_calls: Array = []
var clear_wall_calls: int = 0
var _bricks: Array = []
var _emitted: bool = false

func generate_wave(thickness: int, layout: int, seed: int) -> void:
	clear_wall()
	generate_calls.append([thickness, layout, seed])
	for i in range(thickness):
		_bricks.append(Node2D.new())
	remaining_bricks = _bricks.size()
	_emitted = false

func clear_wall() -> void:
	clear_wall_calls += 1
	_bricks.clear()
	remaining_bricks = 0
	_emitted = false

func destroy_all_bricks() -> void:
	## 模拟整墙打空 → wall_cleared 只发一次（#384 _wall_cleared_emitted 守卫）
	remaining_bricks = 0
	if not _emitted:
		_emitted = true
		wall_cleared.emit()
"""

const MOCK_GRID_NO_GEN_SRC := """
extends Node2D
## Mock BreakoutGrid 变体: 有 wall_cleared 信号但无 generate_wave 方法（失败路径 4 / F-4）。
signal wall_cleared
"""

const MOCK_PADDLE_SRC := """
extends Node2D
## Mock AIPaddle: 实例级 AI 参数（#387 契约）。
var ai_reaction_delay_min: float = 0.15
var ai_reaction_delay_max: float = 0.4
var ai_position_error: float = 24.0
"""


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _reset_all() -> void:
	GameManager.reset_match()
	_wave_started.clear()
	_wave_settled.clear()
	_grid_instances = 0


func _make_mock_grid() -> Node2D:
	_grid_instances += 1
	var code = GDScript.new()
	code.source_code = MOCK_GRID_SRC
	code.reload()
	var grid = Node2D.new()
	grid.name = "BreakoutGrid"
	grid.set_script(code)
	return grid


func _make_mock_grid_no_gen() -> Node2D:
	_grid_instances += 1
	var code = GDScript.new()
	code.source_code = MOCK_GRID_NO_GEN_SRC
	code.reload()
	var grid = Node2D.new()
	grid.name = "BreakoutGrid"
	grid.set_script(code)
	return grid


func _make_mock_paddle() -> Node2D:
	var code = GDScript.new()
	code.source_code = MOCK_PADDLE_SRC
	code.reload()
	var paddle = Node2D.new()
	paddle.name = "AIPaddle"
	paddle.set_script(code)
	return paddle


## Build a mini tree so WaveController._ready() runs with @onready resolving
## ../BreakoutGrid and ../AIPaddle (siblings under tree root).
## Returns [ctrl, grid, paddle, nodes_for_cleanup]; grid/paddle may be null.
func _make_controller(with_grid: bool, with_paddle: bool) -> Array:
	var tree = _tree()
	var nodes: Array = []
	var grid = null
	var paddle = null
	if with_grid:
		grid = _make_mock_grid()
		tree.root.add_child(grid)
		nodes.append(grid)
	if with_paddle:
		paddle = _make_mock_paddle()
		tree.root.add_child(paddle)
		nodes.append(paddle)
	var ctrl = Node.new()
	ctrl.set_script(load("res://gdscripts/wave_controller.gd"))
	ctrl.name = "WaveController"
	tree.root.add_child(ctrl)
	nodes.append(ctrl)
	return [ctrl, grid, paddle, nodes]


func _cleanup_tree(nodes: Array) -> void:
	var tree = _tree()
	for n in nodes:
		if n != null and is_instance_valid(n) and n.get_parent() != null:
			n.get_parent().remove_child(n)
			n.queue_free()


# ── Scenario A: 波次推进 (AC1) ──

## A-1 + A-2（端到端）: 墙清空 → 结算(SETTLED + wave_settled) → 延时后自动下一波
## (wave_index+1, RUNNING, wave_started, generate_wave 被调)
func _test_a1_settle_then_next_wave() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]

	ctrl._advance_wave()   # 首波开始（模拟第一局）
	_assert(GameManager.wave_index == 1, "A: 首波 wave_index == 1")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "A: 首波 RUNNING")
	_assert(grid.generate_calls.size() == 1, "A: 首波 generate_wave 恰好 1 次")

	_wave_started.clear()
	_wave_settled.clear()
	grid.destroy_all_bricks()   # 整墙打空 → wall_cleared
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "A-1: 墙清空 → SETTLED")
	_assert(_wave_settled.size() == 1 and _wave_settled[0] == 1, "A-1: wave_settled 恰好一次且负载 == 当前 wave_index")

	await _tree().create_timer(SETTLE_WAIT).timeout   # WAVE_SETTLE_DELAY 延时自动推进
	_assert(GameManager.wave_index == 2, "A-2: 结算延时后 wave_index == 2")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "A-2: 自动进下一波 → RUNNING")
	_assert(_wave_started.size() == 1 and _wave_started[0] == 2, "A-2: wave_started 恰好一次且负载 == 2")
	_assert(grid.generate_calls.size() == 2, "A-2: 第二波 generate_wave 被调")

	_cleanup_tree(arr[3])


## A-3: 生成参数递增 — 波 N 与波 N+1 的 thickness 差 == WAVE_THICKNESS_STEP
func _test_a3_thickness_increment() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]

	ctrl._advance_wave()
	ctrl._advance_wave()
	var t1: int = grid.generate_calls[0][0]
	var t2: int = grid.generate_calls[1][0]
	_assert(t2 - t1 == CONSTS.WAVE_THICKNESS_STEP, "A-3: 相邻波 thickness 差 == WAVE_THICKNESS_STEP")
	_assert(t2 == CONSTS.WAVE_START_THICKNESS + CONSTS.WAVE_THICKNESS_STEP, "A-3: 第 2 波厚度 == 起始 + 步进")

	_cleanup_tree(arr[3])


## A-4: 连续 3 次 wall_cleared → wave_index == 3、generate_wave 恰好 3 次（无跳过/无重复）
func _test_a4_three_waves() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]

	ctrl._advance_wave()   # 波 1（直调，免去首波延时）
	for i in range(2):
		grid.destroy_all_bricks()
		await _tree().create_timer(SETTLE_WAIT).timeout

	_assert(GameManager.wave_index == 3, "A-4: 连续 3 波后 wave_index == 3")
	_assert(grid.generate_calls.size() == 3, "A-4: generate_wave 恰好 3 次（无跳过/无重复）")
	_assert(grid.generate_calls[2][0] == 3, "A-4: 第 3 波厚度 == 3")

	_cleanup_tree(arr[3])


# ── Scenario B: 难度递增 (AC2) ──

## B-1: 厚度严格递增
func _test_b1_thickness_strict_increase() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]

	_assert(ctrl._wave_thickness(2) > ctrl._wave_thickness(1), "B-1: thickness(2) > thickness(1)")
	_assert(ctrl._wave_thickness(2) == CONSTS.WAVE_START_THICKNESS + CONSTS.WAVE_THICKNESS_STEP,
		"B-1: thickness(2) == 起始 + 步进")

	_cleanup_tree(arr[3])


## B-2: AI 参数每波收紧且 ≥ FLOOR（clamp 不越界）
func _test_b2_ai_params_tighten() -> void:
	_reset_all()
	var arr = _make_controller(true, true)
	var ctrl = arr[0]
	var paddle = arr[2]
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

	_cleanup_tree(arr[3])


## B-3: 至少一项严格递增（双杠杆都实现，实际两者同时成立）
func _test_b3_at_least_one_strict() -> void:
	_reset_all()
	var arr = _make_controller(true, true)
	var ctrl = arr[0]
	var paddle = arr[2]
	var min0: float = paddle.ai_reaction_delay_min

	ctrl._advance_wave()
	ctrl._advance_wave()

	var thickness_up: bool = ctrl._wave_thickness(3) > ctrl._wave_thickness(2)
	var ai_tighter: bool = paddle.ai_reaction_delay_min < min0
	_assert(thickness_up or ai_tighter, "B-3: 相邻波「厚度更大 或 AI 更紧」恒真")
	_assert(thickness_up and ai_tighter, "B-3: 双杠杆同时成立（强度断言）")

	_cleanup_tree(arr[3])


## B-4: 多波循环后参数不低于 FLOOR（不趋零/不 NaN）
func _test_b4_floor_clamp() -> void:
	_reset_all()
	var arr = _make_controller(true, true)
	var ctrl = arr[0]
	var paddle = arr[2]

	for i in range(60):
		ctrl._advance_wave()

	_assert(paddle.ai_reaction_delay_min >= CONSTS.AI_REACTION_DELAY_MIN_FLOOR - 0.0001, "B-4: min 不低于 FLOOR")
	_assert(paddle.ai_reaction_delay_max >= CONSTS.AI_REACTION_DELAY_MAX_FLOOR - 0.0001, "B-4: max 不低于 FLOOR")
	_assert(paddle.ai_position_error >= CONSTS.AI_POSITION_ERROR_FLOOR - 0.0001, "B-4: err 不低于 FLOOR")
	_assert(not is_nan(paddle.ai_reaction_delay_min) and not is_nan(paddle.ai_position_error), "B-4: 无 NaN")

	_cleanup_tree(arr[3])


# ── Scenario C: wave_index 生命周期 (AC3) ──

## C-1: reset 后首次 begin_wave → wave_index == 1
func _test_c1_first_wave_is_1() -> void:
	_reset_all()
	GameManager.begin_wave()
	_assert(GameManager.wave_index == 1, "C-1: 首波 wave_index == 1")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "C-1: 首波 RUNNING")


## C-2: 连续两波 → wave_index == 2
func _test_c2_increment() -> void:
	_reset_all()
	GameManager.begin_wave()
	GameManager.begin_wave()
	_assert(GameManager.wave_index == 2, "C-2: 连续两波 wave_index == 2")


## C-3: 信号负载与 wave_index 一致（可读性契约，#390/#393 依赖）
func _test_c3_signal_payload() -> void:
	_reset_all()
	GameManager.begin_wave()
	GameManager.settle_wave()
	_assert(_wave_started.size() == 1 and _wave_started[0] == GameManager.wave_index, "C-3: wave_started 负载一致")
	_assert(_wave_settled.size() == 1 and _wave_settled[0] == GameManager.wave_index, "C-3: wave_settled 负载一致")


## C-4: reset_match → wave_index == 0、IDLE、is_wave_cycle_active == false
func _test_c4_reset_resets() -> void:
	_reset_all()
	GameManager.begin_wave()
	GameManager.settle_wave()
	GameManager.reset_match()
	_assert(GameManager.wave_index == 0, "C-4: reset 后 wave_index == 0")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "C-4: reset 后 IDLE")
	_assert(GameManager.is_wave_cycle_active() == false, "C-4: reset 后 is_wave_cycle_active == false")


# ── Scenario D: 旧墙不叠加 (AC4) ──

## D-1: 整轮测试中 mock grid 实例化次数 == 1（WaveController 绝不 new 网格）
func _test_d1_single_instance() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	ctrl._advance_wave()
	ctrl._advance_wave()
	ctrl._advance_wave()
	_assert(_grid_instances == 1, "D-1: 3 波后 grid 实例数 == 1（单实例）")
	_cleanup_tree(arr[3])


## D-2: 只调 generate_wave（清理由其内部保证）— clear_wall_calls 只能来自 generate_wave 内部
func _test_d2_only_generate_wave() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]
	ctrl._advance_wave()
	ctrl._advance_wave()
	ctrl._advance_wave()
	_assert(grid.clear_wall_calls == grid.generate_calls.size(),
		"D-2: clear_wall 调用数 == generate_wave 调用数（无外部直接 clear_wall）")
	_cleanup_tree(arr[3])


## D-3: 连续 3 波后 mock 砖计数 == 第 3 波应生成数（0 残留）
func _test_d3_no_residue() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]
	ctrl._advance_wave()
	ctrl._advance_wave()
	ctrl._advance_wave()
	_assert(grid.remaining_bricks == 3, "D-3: 3 波后 remaining_bricks == 第 3 波厚度 3（0 残留）")
	_cleanup_tree(arr[3])


## D-4: 同一墙连发两次 wall_cleared → 只推进一波（_settling 守卫）
func _test_d4_duplicate_ignored_once() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]
	ctrl._advance_wave()
	_wave_settled.clear()

	grid.wall_cleared.emit()
	grid.wall_cleared.emit()   # 重复信号（模拟 #384 守卫失效的异常 grid）
	_assert(_wave_settled.size() == 1, "D-4: 重复 wall_cleared 只 settle 一次")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "D-4: 仍处 SETTLED")
	_cleanup_tree(arr[3])


# ── Scenario E: 21 分停止 (AC5) ──

## E-1: 终局后 wall_cleared → 不结算、不生成、状态不变
func _test_e1_no_settle_after_end() -> void:
	_reset_all()
	for i in range(21):
		GameManager.add_score("player")
	_assert(GameManager.is_run_over() == true, "E-1: 前置 is_run_over == true")

	var arr = _make_controller(true, false)
	var grid = arr[1]
	_wave_started.clear()
	_wave_settled.clear()

	grid.wall_cleared.emit()
	_assert(_wave_settled.size() == 0, "E-1: 终局后无 wave_settled")
	_assert(_wave_started.size() == 0, "E-1: 终局后无 wave_started")
	_assert(grid.generate_calls.size() == 0, "E-1: 终局后不生成新墙")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "E-1: 波次状态不变（IDLE）")
	_cleanup_tree(arr[3])


## E-2: 结算时 is_run_over() 变 true（最后一砖到 21 分）→ end_wave_cycle：IDLE、不生成、wave_index 保留
func _test_e2_stop_when_settle_reaches_21() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]
	ctrl._advance_wave()   # 波 1
	for i in range(20):
		GameManager.add_score("player")   # 差 1 分到 21

	GameManager.wave_settled.connect(_on_settled_reach_21)
	grid.destroy_all_bricks()   # 最后一砖: 清墙 + 21 分
	GameManager.wave_settled.disconnect(_on_settled_reach_21)

	_assert(GameManager.is_run_over() == true, "E-2: 结算时到 21 分 → run over")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "E-2: end_wave_cycle → IDLE")
	_assert(GameManager.wave_index == 1, "E-2: wave_index 保留（run 统计可读）")
	_assert(grid.generate_calls.size() == 1, "E-2: 不再生成新墙（仅波 1 那次）")
	_cleanup_tree(arr[3])


# ── Scenario F: 容错与守卫 ──

## F-1: 无 BreakoutGrid 节点 → _ready 不崩、波次状态机保持 IDLE
func _test_f1_no_grid_no_crash() -> void:
	_reset_all()
	var arr = _make_controller(false, false)
	var ctrl = arr[0]
	_assert(ctrl.breakout_grid == null, "F-1: 无 grid → breakout_grid == null（不崩）")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "F-1: 波次状态机保持 IDLE")
	_assert(GameManager.wave_index == 0, "F-1: wave_index == 0")
	_cleanup_tree(arr[3])


## F-2: 无 ai_paddle → AI 缩放跳过 + 警告；厚度杠杆仍生效（AC2 不失效）
func _test_f2_no_ai_paddle() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]
	_assert(ctrl.ai_paddle == null, "F-2: 无 AIPaddle → ai_paddle == null")

	ctrl._advance_wave()
	_assert(GameManager.wave_index == 1, "F-2: 状态机照常推进")
	_assert(grid.generate_calls.size() == 1 and grid.generate_calls[0][0] == CONSTS.WAVE_START_THICKNESS,
		"F-2: 厚度杠杆仍生效（首波厚度 == WAVE_START_THICKNESS）")
	_cleanup_tree(arr[3])


## F-3: _settling 期间重复 wall_cleared → 忽略（边界 4）
func _test_f3_duplicate_during_settling() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]
	ctrl._advance_wave()
	_wave_settled.clear()

	grid.wall_cleared.emit()
	var settled_count: int = _wave_settled.size()
	grid.wall_cleared.emit()
	_assert(_wave_settled.size() == settled_count, "F-3: 结算中重复信号被忽略")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "F-3: 仍 SETTLED")
	_cleanup_tree(arr[3])


## F-4: grid 有 wall_cleared 但无 generate_wave → 警告跳过生成，wave_index 仍 +1（状态机不卡死）
func _test_f4_generate_unavailable() -> void:
	_reset_all()
	var tree = _tree()
	var grid = _make_mock_grid_no_gen()
	tree.root.add_child(grid)
	var ctrl = Node.new()
	ctrl.set_script(load("res://gdscripts/wave_controller.gd"))
	ctrl.name = "WaveController"
	tree.root.add_child(ctrl)
	_wave_started.clear()

	grid.wall_cleared.emit()   # 触发 _on_wall_cleared → settle（IDLE 期 settle 为 no-op）→ 延时后 advance
	await _tree().create_timer(SETTLE_WAIT).timeout

	_assert(GameManager.wave_index == 1, "F-4: generate_wave 不可用仍 wave_index +1（不卡死）")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "F-4: 状态机推进到 RUNNING")
	_assert(_wave_started.size() == 1 and _wave_started[0] == 1, "F-4: wave_started 发出")
	_cleanup_tree([ctrl, grid])


# ── Scenario G: 重置与防御 ──

## G-1: WAVE_MAX_INDEX 防御 — 达到上限后停止递增与生成
func _test_g1_max_index_defense() -> void:
	_reset_all()
	var arr = _make_controller(true, false)
	var ctrl = arr[0]
	var grid = arr[1]
	GameManager.wave_index = CONSTS.WAVE_MAX_INDEX
	GameManager.wave_state = GameManager.WaveState.RUNNING

	ctrl._advance_wave()
	_assert(GameManager.wave_index == CONSTS.WAVE_MAX_INDEX, "G-1: 达上限不再递增")
	_assert(grid.generate_calls.size() == 0, "G-1: 达上限不再生成")
	_cleanup_tree(arr[3])

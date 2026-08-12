extends RefCounted
## Breakout Grid test suite (#384 契约 DESIGN #414 §5.1；实现随 #393 组装落地)。
## 布局（GAPS/OFFSET/HOLES/MIXED 砖数 + X 铺满 + 错位偏移 + 洞位无砖）/ 生成 API
## （thickness / seed 可复现 / 负 seed 不崩）/ 信号（brick_destroyed 逐砖 + pos 正确、
## wall_cleared 恰好一次、wall_generated 每墙一次）/ 缺口无碰撞体 / 再生清理 /
## destroy 幂等 / 常量下限。
## Runs under godot --headless --script via run_tests.gd (_run_async)。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")

# ── Signal capture state (member vars, not lambda closures) ──
var _destroyed_events: Array = []
var _cleared_count: int = 0
var _generated_events: Array = []

func _on_brick_destroyed(brick, pos: Vector2) -> void:
	_destroyed_events.append([brick, pos])

func _on_wall_cleared() -> void:
	_cleared_count += 1

func _on_wall_generated(remaining: int) -> void:
	_generated_events.append(remaining)


func run() -> void:
	print("\n=== Breakout Grid Tests (#384) ===")
	await _test_layout_gaps()
	await _test_layout_offset()
	await _test_layout_holes()
	await _test_layout_mixed()
	await _test_generate_api_reproducible()
	await _test_generate_api_negative_seed()
	await _test_signals_brick_destroyed()
	await _test_signals_wall_cleared_once()
	await _test_holes_no_collision_body()
	await _test_regeneration_clears_old()
	await _test_destroy_idempotent()
	await _test_constants()
	print("  Breakout Grid: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout


func _make_grid() -> Node2D:
	## 真实 BreakoutGrid 脚本（挂树触发 _ready：组注册 + brick_scene 加载）。
	var grid = Node2D.new()
	grid.set_script(load("res://gdscripts/breakout_grid.gd"))
	grid.name = "BreakoutGrid"
	(Engine.get_main_loop() as SceneTree).root.add_child(grid)
	grid.brick_destroyed.connect(_on_brick_destroyed)
	grid.wall_cleared.connect(_on_wall_cleared)
	grid.wall_generated.connect(_on_wall_generated)
	return grid


func _brick_children(grid: Node2D) -> Array:
	var out: Array = []
	for child in grid.get_children():
		if child.is_in_group("bricks"):
			out.append(child)
	return out


func _reset_signals() -> void:
	_destroyed_events.clear()
	_cleared_count = 0
	_generated_events.clear()


func _cleanup(grid: Node2D) -> void:
	if grid != null and is_instance_valid(grid) and grid.get_parent() != null:
		grid.get_parent().remove_child(grid)
		grid.queue_free()
	await _wait(0.02)


# ── 布局 ──

## GAPS: cols=floor(720/68)=10，每 5 列留 1 缝（c%5==4 → 列 4、9）→ 每行 8 砖
func _test_layout_gaps() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 0, 42)   # BrickLayout.GAPS
	var bricks = _brick_children(grid)
	_assert(grid.remaining_bricks == 24, "GAPS: 3 行 × 8 砖 == 24 (got %d)" % grid.remaining_bricks)
	_assert(bricks.size() == 24, "GAPS: 树内砖节点 == 24 (got %d)" % bricks.size())
	var w: float = maxf(CONSTS.BRICK_SIZE.x, CONSTS.BRICK_MIN_DIM)
	var min_x: float = 99999.0
	var max_x: float = -99999.0
	for b in bricks:
		min_x = minf(min_x, b.position.x)
		max_x = maxf(max_x, b.position.x)
	_assert(min_x >= w / 2.0, "GAPS: 首砖 x >= 砖宽/2 (got %.1f)" % min_x)
	_assert(max_x <= CONSTS.SCREEN_WIDTH - w / 2.0, "GAPS: 末砖 x <= 720-砖宽/2 (got %.1f)" % max_x)
	await _cleanup(grid)


## OFFSET: 奇数行偏移 (砖宽+缝)/2 = 34；末砖越界 → 行少 1 块（10+9+10=29）
func _test_layout_offset() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 1, 7)   # BrickLayout.OFFSET
	var bricks = _brick_children(grid)
	_assert(grid.remaining_bricks == 29, "OFFSET: 3 行 10/9/10 == 29 (got %d)" % grid.remaining_bricks)
	# 奇数行（第 2 行，0-based 1）y == 640（墙垂直居中于 wall_y=640，DESIGN §4.3）且首砖 x == 54 + 34 == 88
	var odd_row_found: bool = false
	var odd_x: float = 0.0
	for b in bricks:
		if abs(b.position.y - 640.0) < 1.0 and abs(b.position.x - 88.0) < 1.0:
			odd_row_found = true
			odd_x = b.position.x
	_assert(odd_row_found, "OFFSET: 奇数行存在偏移砖 x==88 (got %.1f)" % odd_x)
	var w: float = maxf(CONSTS.BRICK_SIZE.x, CONSTS.BRICK_MIN_DIM)
	for b in bricks:
		_assert(b.position.x >= w / 2.0 and b.position.x <= CONSTS.SCREEN_WIDTH - w / 2.0,
			"OFFSET: 全部砖在 X 边界内 (x=%.1f)" % b.position.x)
	await _cleanup(grid)


## HOLES: hole_count=2 柱位 × 全部行不实例化 → 30 - 6 == 24；洞柱位无砖节点
func _test_layout_holes() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 2, 11)   # BrickLayout.HOLES
	_assert(grid.remaining_bricks == 24, "HOLES: 30 - 2×3 == 24 (got %d)" % grid.remaining_bricks)
	_assert(grid._hole_columns.size() == 2, "HOLES: 恰好 2 个洞柱位 (got %d)" % grid._hole_columns.size())
	var bricks = _brick_children(grid)
	var w: float = maxf(CONSTS.BRICK_SIZE.x, CONSTS.BRICK_MIN_DIM)
	var cols: int = grid._compute_cols()
	var start_x: float = grid._compute_start_x(cols)
	for c in grid._hole_columns:
		var cx: float = start_x + c * (w + grid.brick_gap)
		for b in bricks:
			_assert(abs(b.position.x - cx) >= w / 2.0,
				"HOLES: 洞柱位 %d 无砖节点 (砖 x=%.1f 洞轴 %.1f)" % [c, b.position.x, cx])
	await _cleanup(grid)


## MIXED: GAPS+OFFSET+HOLES 组合 — 砖数 < 满格、全部在界内、洞柱位无砖
func _test_layout_mixed() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 3, 13)   # BrickLayout.MIXED
	_assert(grid.remaining_bricks > 0 and grid.remaining_bricks < 30,
		"MIXED: 砖数在 (0,30) 内 (got %d)" % grid.remaining_bricks)
	var bricks = _brick_children(grid)
	var w: float = maxf(CONSTS.BRICK_SIZE.x, CONSTS.BRICK_MIN_DIM)
	var cols: int = grid._compute_cols()
	var start_x: float = grid._compute_start_x(cols)
	for b in bricks:
		_assert(b.position.x >= w / 2.0 and b.position.x <= CONSTS.SCREEN_WIDTH - w / 2.0,
			"MIXED: 全部砖在 X 边界内 (x=%.1f)" % b.position.x)
	for c in grid._hole_columns:
		var cx: float = start_x + c * (w + grid.brick_gap)
		for b in bricks:
			_assert(abs(b.position.x - cx) >= w / 2.0,
				"MIXED: 洞柱位 %d 无砖节点 (砖 x=%.1f)" % [c, b.position.x])
	await _cleanup(grid)


# ── 生成 API ──

## 相同 seed → 布局可复现（砖数 + 位置集合一致）
func _test_generate_api_reproducible() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(2, 1, 123)
	var pos_a: Array = []
	for b in _brick_children(grid):
		pos_a.append(b.position)
	grid.generate_wave(2, 1, 123)
	await _wait(0.05)   # 旧墙 queue_free 生效（快照遍历延迟释放），避免新旧砖混数
	var pos_b: Array = []
	for b in _brick_children(grid):
		pos_b.append(b.position)
	_assert(pos_a.size() == pos_b.size(), "API: 同 seed 砖数一致 (%d vs %d)" % [pos_a.size(), pos_b.size()])
	var same: bool = pos_a.size() == pos_b.size()
	if same:
		for p in pos_a:
			if not pos_b.has(p):
				same = false
	_assert(same, "API: 同 seed 位置集合一致")
	await _cleanup(grid)


## 负 seed（随机）→ 不抛错、能生成
func _test_generate_api_negative_seed() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(2, 2, -1)
	_assert(grid.remaining_bricks > 0, "API: 负 seed 生成成功 (got %d)" % grid.remaining_bricks)
	grid.generate_wave(1, 0, -1)
	_assert(grid.remaining_bricks > 0, "API: 负 seed 二次生成成功 (got %d)" % grid.remaining_bricks)
	await _cleanup(grid)


# ── 信号 ──

## 逐砖 destroy → 每砖一次 brick_destroyed(brick, pos) 且 pos == 砖全局坐标
func _test_signals_brick_destroyed() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 5)   # 8 砖
	var bricks = _brick_children(grid)
	for b in bricks:
		b.destroy()
	_assert(_destroyed_events.size() == 8, "SIG: 8 砖 → 8 次 brick_destroyed (got %d)" % _destroyed_events.size())
	var pos_ok: bool = true
	for ev in _destroyed_events:
		if ev[1] != ev[0].global_position:
			pos_ok = false
	_assert(pos_ok, "SIG: brick_destroyed pos == 砖全局坐标")
	await _cleanup(grid)


## 全部打空 → wall_cleared 恰好一次；wall_generated 每墙一次
func _test_signals_wall_cleared_once() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 5)
	_assert(_generated_events.size() == 1 and _generated_events[0] == 8,
		"SIG: wall_generated 一次且负载 8 (got %s)" % str(_generated_events))
	var bricks = _brick_children(grid)
	for b in bricks:
		b.destroy()
	_assert(_cleared_count == 1, "SIG: wall_cleared 恰好一次 (got %d)" % _cleared_count)
	_assert(grid.remaining_bricks == 0, "SIG: remaining_bricks == 0")
	# 清空后再 destroy（已销毁砖）→ 不重复发
	for b in bricks:
		if is_instance_valid(b):
			b.destroy()
	_assert(_cleared_count == 1, "SIG: 重复 destroy 不重复发 wall_cleared (got %d)" % _cleared_count)
	await _cleanup(grid)


# ── 缺口（AC3）：洞柱位无碰撞体（无砖节点 = 无碰撞体，DESIGN §2 决策 3）──

func _test_holes_no_collision_body() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 2, 11)
	var bricks = _brick_children(grid)
	var w: float = maxf(CONSTS.BRICK_SIZE.x, CONSTS.BRICK_MIN_DIM)
	var cols: int = grid._compute_cols()
	var start_x: float = grid._compute_start_x(cols)
	_assert(grid._hole_columns.size() == 2, "HOLE: 洞柱位 == 2")
	for c in grid._hole_columns:
		var cx: float = start_x + c * (w + grid.brick_gap)
		for b in bricks:
			_assert(abs(b.position.x - cx) >= w / 2.0,
				"HOLE: 洞柱位 %d 无碰撞体（无砖节点）" % c)
	await _cleanup(grid)


# ── 再生（失败路径覆盖）──

## generate_wave 后旧砖清空、计数/守卫重置；打空 → 再生 → 再打空 → wall_cleared 恰好两次
func _test_regeneration_clears_old() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 5)
	var first_bricks = _brick_children(grid)
	for b in first_bricks:
		b.destroy()
	await _wait(0.02)   # queue_free 生效
	_assert(_cleared_count == 1, "REGEN: 第一次清空 wall_cleared 一次")
	grid.generate_wave(2, 0, 5)
	await _wait(0.02)
	var second_bricks = _brick_children(grid)
	_assert(second_bricks.size() == 16, "REGEN: 第二墙 16 砖、旧砖零残留 (got %d)" % second_bricks.size())
	_assert(grid.remaining_bricks == 16, "REGEN: remaining_bricks == 16")
	_reset_signals()
	for b in second_bricks:
		b.destroy()
	_assert(_cleared_count == 1, "REGEN: 第二墙清空 wall_cleared 恰好一次")
	_assert(_cleared_count == 1, "REGEN: 两墙各一次（本墙计数 1）")
	await _cleanup(grid)


# ── 幂等 ──

## 同一砖 destroy() 两次 → 计数只减一、brick_destroyed 只发一次
func _test_destroy_idempotent() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 5)
	var bricks = _brick_children(grid)
	var target = bricks[0]
	var before: int = grid.remaining_bricks
	target.destroy()
	target.destroy()
	_assert(grid.remaining_bricks == before - 1, "IDEM: 计数只减一 (%d → %d)" % [before, grid.remaining_bricks])
	_assert(_destroyed_events.size() == 1, "IDEM: brick_destroyed 只发一次 (got %d)" % _destroyed_events.size())
	await _cleanup(grid)


# ── 常量 ──

func _test_constants() -> void:
	_assert(CONSTS.BRICK_MIN_DIM >= 14.0, "CONST: BRICK_MIN_DIM >= 14 (got %f)" % CONSTS.BRICK_MIN_DIM)
	_assert(CONSTS.BRICK_SIZE.x >= 14.0 and CONSTS.BRICK_SIZE.y >= 14.0,
		"CONST: BRICK_SIZE 两轴 >= 14 (got %s)" % str(CONSTS.BRICK_SIZE))
	_assert(CONSTS.GRID_WALL_Y == 640.0, "CONST: GRID_WALL_Y == 640（#385/#384 对齐）")

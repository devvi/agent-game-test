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
	await _test_upgrade_hook_open_hole()
	await _test_upgrade_hook_blast()
	# #529 Scenario A/B: 特殊砖常量约束 + 内部位生成（PRD #529 §5.1 AC1/AC4）
	_test_constants_special_a1()
	_test_constants_special_a2()
	await _test_constants_special_a3()
	await _test_special_b1_internal()
	await _test_special_b2_thin_wall()
	await _test_special_b3_reproducible()
	await _test_special_b4_per_wave()
	await _test_special_b5_pending_hole()
	await _test_special_b6_no_candidate()
	await _test_special_b7_counting()
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


# ── #387 升级钩子（DESIGN #393 附录 B.5 Test 6：真实 grid 版）──

## open_hole 请求挂起 → 下波 generate_wave 末尾消费：洞柱位补开、砖数减少、无残留请求
func _test_upgrade_hook_open_hole() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(2, 0, 5)              # GAPS 2 行: 8×2 == 16 砖
	var before: int = grid.remaining_bricks
	grid.open_hole(1)                        # 结算期请求（升级调用路径）
	_assert(grid._pending_holes.size() == 1, "HOOK: open_hole 请求挂起 (got %d)" % grid._pending_holes.size())
	_assert(grid.remaining_bricks == before, "HOOK: 当前墙不立即改变（下波生效）")
	grid.generate_wave(2, 0, 5)              # 下波生成 → 消费
	await _wait(0.02)                       # queue_free 生效（洞柱位砖延迟帧末释放）
	_assert(grid._pending_holes.is_empty(), "HOOK: 挂起队列已清空")
	var w: float = maxf(CONSTS.BRICK_SIZE.x, CONSTS.BRICK_MIN_DIM)
	var cols: int = grid._compute_cols()
	var start_x: float = grid._compute_start_x(cols)
	var hole_ok: bool = true
	for c in grid._hole_columns:
		for b in _brick_children(grid):
			if abs(b.position.x - (start_x + c * (w + grid.brick_gap))) < w / 2.0:
				hole_ok = false
	_assert(hole_ok, "HOOK: 洞柱位无砖节点")
	_assert(grid.remaining_bricks < _expected_plain_bricks(2), "HOOK: 洞后砖数减少 (got %d)" % grid.remaining_bricks)
	await _cleanup(grid)


## blast_neighbors(pos, r): 半径内砖碎、计数/信号正确；归零时 wall_cleared 恰好一次
func _test_upgrade_hook_blast() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 5)              # 单行 8 砖，砖心 y==640
	var bricks = _brick_children(grid)
	var center: Vector2 = Vector2(360, 640)  # 墙中心
	var radius: float = 200.0                # 覆盖约 6-7 砖
	var in_range: int = 0
	for b in bricks:
		if b.position.distance_to(center) <= radius:
			in_range += 1
	grid.blast_neighbors(center, radius)
	_assert(_destroyed_events.size() == in_range,
		"BLAST: 半径内砖全部销毁 (%d/%d)" % [_destroyed_events.size(), in_range])
	_assert(grid.remaining_bricks == 8 - in_range,
		"BLAST: remaining == 8 - 半径内 (%d)" % grid.remaining_bricks)
	# 全部清空 → wall_cleared 恰好一次
	for b in _brick_children(grid):
		b.destroy()
	_assert(_cleared_count == 1, "BLAST: 归零 wall_cleared 恰好一次 (got %d)" % _cleared_count)
	await _cleanup(grid)


## GAPS 无洞布局的满格砖数（供 HOOK 断言）：cols=10 − 2 缝列 == 8
func _expected_plain_bricks(thickness: int) -> int:
	return 8 * thickness


# ── #529 特殊砖 Scenario A：常量与机械约束（PRD #529 §5.1）──

## A1（机械键）：每波恰好 1 颗 + 厚度下限 == 3（薄墙回退阈值）
func _test_constants_special_a1() -> void:
	_assert(CONSTS.SPECIAL_BRICK_PER_WAVE == 1,
		"A1: SPECIAL_BRICK_PER_WAVE == 1 (got %d)" % CONSTS.SPECIAL_BRICK_PER_WAVE)
	_assert(CONSTS.SPECIAL_BRICK_MIN_THICKNESS == 3,
		"A1: SPECIAL_BRICK_MIN_THICKNESS == 3 (got %d)" % CONSTS.SPECIAL_BRICK_MIN_THICKNESS)


## A2（E2E theme 保护）：SPECIAL_BRICK_COLOR 与玩家霓虹蓝 RGB 距离 ×255 ≥ 32、
## 与普通砖琥珀橙 RGB 距离 ×255 ≥ 60（可辨识，tol 32/60 先例 #527/#464）
func _test_constants_special_a2() -> void:
	var c: Color = CONSTS.SPECIAL_BRICK_COLOR
	var d_blue: float = abs(c.r - CONSTS.PLAYER_NEON_BLUE.r) + abs(c.g - CONSTS.PLAYER_NEON_BLUE.g) + abs(c.b - CONSTS.PLAYER_NEON_BLUE.b)
	_assert(d_blue * 255.0 >= 32.0,
		"A2: SPECIAL vs PLAYER_NEON_BLUE RGB 距离×255 ≥ 32 (got %.1f)" % (d_blue * 255.0))
	var d_brick: float = abs(c.r - CONSTS.BRICK_NEON.r) + abs(c.g - CONSTS.BRICK_NEON.g) + abs(c.b - CONSTS.BRICK_NEON.b)
	_assert(d_brick * 255.0 >= 60.0,
		"A2: SPECIAL vs BRICK_NEON RGB 距离×255 ≥ 60 (got %.1f)" % (d_brick * 255.0))


## A3（默认砖零回归）：普通砖 ColorRect.color == tscn 字面 Color(1,0.616,0.271,1)
## 且材质与共享 res://assets/neon_glow_material.tres 同引用（== 引用相等，证明 brick.tscn
## 未被修改，E2-2 文本断言保护；#464 教训：特殊砖才 duplicate 材质，普通砖零改动）
## 注: is_same() 在 Godot 4.7.1 不存在（Resource 无此方法）→ 用 == 引用相等（实测等价）
func _test_constants_special_a3() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 42)
	var bricks = _brick_children(grid)
	var brick = bricks[0]
	_assert(bricks.size() >= 1, "A3: 生成至少 1 砖")
	_assert(brick.is_special == false, "A3: 默认砖 is_special == false")
	var rect: ColorRect = brick.get_node("ColorRect") as ColorRect
	_assert(rect != null, "A3: ColorRect 节点存在")
	if rect != null:
		_assert(rect.color == Color(1, 0.616, 0.271, 1),
			"A3: 默认砖色 == tscn 字面 (got %s)" % rect.color)
		var shared_mat = load("res://assets/neon_glow_material.tres")
		_assert(rect.material != null and rect.material == shared_mat,
			"A3: 默认砖材质与共享 .tres 同引用（tscn 未被改）")
	await _cleanup(grid)


# ── #529 特殊砖 Scenario B：内部位生成（PRD #529 AC1/AC4，DESIGN §3.3）──

## B1（AC1 内部位）：GAPS 3 行 → 恰好 1 颗 is_special；其 4 正交邻域（上/下/左/右）
## 均为存在砖（_key 量化 0.5 网格查邻位，step_x=brick_w+gap, step_y=brick_h+gap）；
## 不在缝列（c%5==4 无砖列 —— 有左右邻天然保证，显式断言列非缝列）
func _test_special_b1_internal() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 0, 42)   # BrickLayout.GAPS
	var special: Array = []
	for b in _brick_children(grid):
		if b.is_special:
			special.append(b)
	_assert(special.size() == 1, "B1: GAPS 3 行恰好 1 颗特殊砖 (got %d)" % special.size())
	_assert(grid.remaining_bricks == 24, "B1: 特殊砖为替换式，砖数 == 24 (got %d)" % grid.remaining_bricks)
	if special.size() == 1:
		var s = special[0]
		var step_x: float = grid._brick_w() + grid.brick_gap
		var step_y: float = grid._brick_h() + grid.brick_gap
		var keyed: Dictionary = {}
		for b in _brick_children(grid):
			keyed[grid._key(b.position)] = true
		var offsets: Array = [Vector2(-step_x, 0), Vector2(step_x, 0), Vector2(0, -step_y), Vector2(0, step_y)]
		var neighbors_ok: bool = true
		for off in offsets:
			if not keyed.has(grid._key(s.position + off)):
				neighbors_ok = false
		_assert(neighbors_ok, "B1: 特殊砖 4 正交邻域均有存在砖")
		var w: float = grid._brick_w()
		var cols: int = grid._compute_cols()
		var start_x: float = grid._compute_start_x(cols)
		var c: int = int(round((s.position.x - start_x) / (w + grid.brick_gap)))
		_assert(c % 5 != 4, "B1: 特殊砖不在缝列 (c=%d)" % c)
	await _cleanup(grid)


## B2（AC4 薄墙回退）：厚度 1/2 → 0 颗 is_special（设计决策非缺陷，不得断言薄墙出特殊砖）
func _test_special_b2_thin_wall() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 42)
	var c1: int = 0
	for b in _brick_children(grid):
		if b.is_special:
			c1 += 1
	grid.generate_wave(2, 0, 42)
	await _wait(0.02)   # 旧墙 queue_free 生效
	var c2: int = 0
	for b in _brick_children(grid):
		if b.is_special:
			c2 += 1
	_assert(c1 == 0, "B2: 厚度 1 无特殊砖 (got %d)" % c1)
	_assert(c2 == 0, "B2: 厚度 2 无特殊砖 (got %d)" % c2)
	await _cleanup(grid)


## B3（可复现）：同 seed 42 两次 generate_wave(4, GAPS) → 特殊砖 position 一致
func _test_special_b3_reproducible() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(4, 0, 42)
	var pos_a: Vector2 = Vector2.ZERO
	for b in _brick_children(grid):
		if b.is_special:
			pos_a = b.position
	grid.generate_wave(4, 0, 42)
	await _wait(0.02)
	var pos_b: Vector2 = Vector2.ZERO
	var count_b: int = 0
	for b in _brick_children(grid):
		if b.is_special:
			pos_b = b.position
			count_b += 1
	_assert(pos_a != Vector2.ZERO, "B3: 第一波存在特殊砖")
	_assert(count_b == 1, "B3: 第二波恰好 1 颗 (got %d)" % count_b)
	_assert(pos_b == pos_a, "B3: 同 seed 特殊砖 position 一致")
	await _cleanup(grid)


## B4（每波恰好 1 颗）：厚度 4/5 → is_special 计数均 == 1（PER_WAVE 约束，厚度不增颗）
func _test_special_b4_per_wave() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(4, 0, 42)
	var c4: int = 0
	for b in _brick_children(grid):
		if b.is_special:
			c4 += 1
	grid.generate_wave(5, 0, 42)
	await _wait(0.02)
	var c5: int = 0
	for b in _brick_children(grid):
		if b.is_special:
			c5 += 1
	_assert(c4 == 1, "B4: 厚度 4 恰好 1 颗 (got %d)" % c4)
	_assert(c5 == 1, "B4: 厚度 5 恰好 1 颗 (got %d)" % c5)
	await _cleanup(grid)


## B5（挂起洞后存活）：open_hole(1) → generate_wave(3)（消费挂起洞）→ 特殊砖存在且
## 不在被洞清除的列（_spawn_special_brick 在 _consume_pending_holes 之后，边界 9）；
## remaining_bricks == 生成净数（洞后）
func _test_special_b5_pending_hole() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 0, 42)
	grid.open_hole(1)
	grid.generate_wave(3, 0, 42)   # 消费挂起洞
	await _wait(0.02)
	var special: Array = []
	for b in _brick_children(grid):
		if b.is_special:
			special.append(b)
	_assert(special.size() == 1, "B5: 挂起洞后仍恰好 1 颗特殊砖 (got %d)" % special.size())
	var w: float = grid._brick_w()
	var cols: int = grid._compute_cols()
	var start_x: float = grid._compute_start_x(cols)
	if special.size() == 1:
		var s = special[0]
		var c: int = int(round((s.position.x - start_x) / (w + grid.brick_gap)))
		_assert(c not in grid._hole_columns, "B5: 特殊砖不在被洞清除的列 (c=%d)" % c)
	var full: int = _expected_plain_bricks(3)
	var removed: int = 0
	for c in grid._hole_columns:
		if c % 5 != 4:          # 缝列本就无砖，不计洞除
			removed += 3
	_assert(grid.remaining_bricks == full - removed,
		"B5: remaining == 生成净数（洞后）(%d == %d)" % [grid.remaining_bricks, full - removed])
	await _cleanup(grid)


## B6（无候选容错）：空 grid / 清墙后直接 _spawn_special_brick → 0 颗、静默跳过
## 不 push_error；wall_generated 照常 emit（边界 8，容错先例）
func _test_special_b6_no_candidate() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid._spawn_special_brick()   # 空 grid（rows==0）→ 无候选
	var c0: int = 0
	for b in _brick_children(grid):
		if b.is_special:
			c0 += 1
	_assert(c0 == 0, "B6: 空 grid 无特殊砖")
	grid.generate_wave(3, 0, 42)
	_assert(_generated_events.size() == 1, "B6: wall_generated 照常 emit")
	grid.clear_wall()
	await _wait(0.02)
	grid._spawn_special_brick()   # rows==3 但 0 砖 → 无候选静默回退
	var c1: int = 0
	for b in _brick_children(grid):
		if b.is_special:
			c1 += 1
	_assert(c1 == 0, "B6: 无候选 → 0 颗、静默回退")
	_assert(_brick_children(grid).size() == 0, "B6: 清墙后无砖节点")
	await _cleanup(grid)


## B7（计数参与）：特殊砖计入 remaining_bricks；destroy 后 remaining-1、brick_destroyed 发出
func _test_special_b7_counting() -> void:
	_reset_signals()
	var grid = _make_grid()
	grid.generate_wave(3, 0, 42)
	var before: int = grid.remaining_bricks
	_assert(before == 24, "B7: 特殊砖计入 remaining_bricks (got %d)" % before)
	var special: Array = []
	for b in _brick_children(grid):
		if b.is_special:
			special.append(b)
	if special.size() == 1:
		special[0].destroy("player")
		_assert(grid.remaining_bricks == before - 1, "B7: 击碎特殊砖后 remaining-1 (%d)" % grid.remaining_bricks)
		_assert(_destroyed_events.size() == 1, "B7: brick_destroyed 发出")
		_assert(_cleared_count == 0, "B7: 非清空（剩 23 砖）不 wall_cleared")
	await _cleanup(grid)

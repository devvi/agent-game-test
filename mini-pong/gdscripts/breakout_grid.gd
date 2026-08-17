extends Node2D
## BreakoutGrid — 程序化砖墙系统（#384 契约 DESIGN #414，实现随 #393 组装落地）。
## 生成横跨 720px 的砖墙（GAPS/OFFSET/HOLES/MIXED 四布局，§4.3），球碰砖 →
## 原子销毁 + dominant-axis 反弹（ball.gd bricks 分支）。
##
## 信号契约（5 个下游消费方依赖，逐条对齐）:
##   brick_destroyed(brick, pos) → #385 拆砖分（ScoringManager._on_brick_destroyed）
##   wall_cleared()              → #386 波次推进（WaveController._on_wall_cleared）——每墙恰好一次
##   wall_generated(remaining)   → #392 HUD 剩余砖数（#414 附录 A 增补）——每墙一次
##
## 组契约: `breakout_grids`（#387 UpgradePool.grid_ref 惰性解析）
## upgrade_hooks 注册表: #387 brick_upgrade_hooks.register_all(self) 于 _ready 注册；
## 分发经 apply_upgrade_hook(id, ctx)（ctx 注入 "grid" 键）。
##
## Design: docs/DESIGN/384-breakout-grid-brick-wall.md
## Parent Issue: #384 (实现随 #393 组装落地)

class_name BreakoutGrid

enum BrickLayout { GAPS, OFFSET, HOLES, MIXED }

signal brick_destroyed(brick: Node2D, pos: Vector2)
signal wall_cleared()
signal wall_generated(remaining: int)
signal special_brick_destroyed(breaker: String)   # #529: 特殊砖被击碎 (breaker 非空才发)

const CONSTS = preload("res://gdscripts/constants.gd")
const BrickUpgradeHooks = preload("res://gdscripts/brick_upgrade_hooks.gd")

# ── @export 参数（AC5 集中配置；波次数值/配色归 taste-draft）──
@export var brick_size: Vector2 = CONSTS.BRICK_SIZE
@export var brick_gap: float = CONSTS.BRICK_GAP
@export var layout: int = BrickLayout.GAPS
@export var rows: int = 3                 # 默认厚度为机械占位
@export var hole_count: int = 2
@export var hole_seed: int = -1
@export var wall_y: float = CONSTS.GRID_WALL_Y
@export var brick_scene: PackedScene      # 默认 res://scenes/brick.tscn（_ready 惰性加载）

# ── 状态 ──
var remaining_bricks: int = 0
var _wall_cleared_emitted: bool = false
var _destroyed: Dictionary = {}           # 按砖对象身份去重（勿用位置/索引）
var _hole_columns: Array = []             # 当前墙洞柱位（HOLES/MIXED；open_hole 追加）
var _pending_holes: Array = []             # #387 open_hole 挂起队列（下波 generate_wave 消费）
var upgrade_hooks: Dictionary = {}        # #387: id → Callable


func _ready() -> void:
	add_to_group("breakout_grids")         # #387 grid_ref 组契约
	if brick_scene == null:
		brick_scene = load("res://scenes/brick.tscn")
	BrickUpgradeHooks.register_all(self)   # #387 钩子注册（open_hole / blast_neighbors）


# ── 生成 API（#386/#393 契约: generate_wave 内部先 clear_wall → 单实例清理）──

func generate_wave(thickness: int, layout: int, seed_value: int) -> void:
	clear_wall()
	rows = maxi(thickness, 1)
	var rng_seed: int = seed_value
	if rng_seed < 0:
		rng_seed = randi()                 # 随机（不抛错）
	seed(rng_seed)                         # 全局播种 → 同 seed 布局可复现（测试契约）
	var cols: int = _compute_cols()
	var start_x: float = _compute_start_x(cols)
	var w: float = _brick_w()
	var g: float = brick_gap
	# wall_y 为世界坐标（GRID_WALL_Y=640，与 ball.gd 墙带判定同源）→ 砖行本地 Y 需扣节点偏移
	var local_wall_y: float = wall_y - position.y
	var total_h: float = rows * _brick_h() + (rows - 1) * g
	var top_y: float = local_wall_y - total_h / 2.0   # 墙垂直居中于 world wall_y
	_hole_columns.clear()
	if layout == BrickLayout.HOLES or layout == BrickLayout.MIXED:
		_pick_hole_columns(cols)
	var placed: int = 0
	for r in range(rows):
		var odd_offset: float = 0.0
		if (layout == BrickLayout.OFFSET or layout == BrickLayout.MIXED) and r % 2 == 1:
			odd_offset = (w + g) * 0.5     # 奇数行 X 偏移（标准 Breakout 砖纹）
		var cy: float = top_y + r * (_brick_h() + g) + _brick_h() / 2.0
		for c in range(cols):
			if _is_gap_column(c, layout):
				continue                   # GAPS/MIXED: 每 5 列留 1 缝
			if _is_hole_column(c):
				continue                   # HOLES/MIXED: 洞柱位整列不实例化 → 无碰撞体
			var cx: float = start_x + c * (w + g) + odd_offset
			if cx + w / 2.0 > CONSTS.SCREEN_WIDTH:
				continue                   # 错位行末砖越界 → 跳过（行可能少 1 块，§4.3）
			_spawn_brick(Vector2(cx, cy))
			placed += 1
	remaining_bricks = placed
	_wall_cleared_emitted = false
	_destroyed = {}
	_consume_pending_holes()               # B.3 #13: 消费上波挂起的 open_hole 请求（升级在下波生效）
	_spawn_special_brick()                 # #529 新增: 内部位特殊砖 (见下)
	wall_generated.emit(remaining_bricks)  # #392 增补：新墙总数（每墙一次，含洞后净数）


## 清空全部旧砖 + 重置计数/守卫/集合（防旧信号泄漏到新墙）
func clear_wall() -> void:
	var old: Array = get_children()
	for child in old:
		if child.is_in_group("bricks"):
			remove_child(child)   # 立即脱离树（防同帧旧砖残留计数，DESIGN #414 单实例清理）
			child.queue_free()
	remaining_bricks = 0
	_wall_cleared_emitted = false
	_destroyed = {}
	_hole_columns.clear()


# ── 砖销毁回调（brick.destroy() → 本方法；单一递减入口，防计数漂移）──

func _on_brick_destroyed(brick: Node2D) -> void:
	if _destroyed.has(brick):
		return                             # 按对象身份去重（幂等）
	_destroyed[brick] = true
	remaining_bricks -= 1
	brick_destroyed.emit(brick, brick.global_position)
	if brick.get("is_special") == true and brick.get("breaker") != "":     # #529 新增: 触发规则见 §2 gap 核查
		special_brick_destroyed.emit(brick.get("breaker"))
	if remaining_bricks <= 0 and not _wall_cleared_emitted:
		_wall_cleared_emitted = true
		wall_cleared.emit()                # 每墙恰好一次（generate_wave 重置守卫）


# ── #387 upgrade_hooks 注册表 ──

func register_upgrade_hook(id: String, fn: Callable) -> void:
	upgrade_hooks[id] = fn


## 分发升级钩子（ctx 注入 "grid" 键，供 brick_upgrade_hooks 实现读取）
func apply_upgrade_hook(id: String, ctx: Dictionary) -> bool:
	if not upgrade_hooks.has(id):
		return false
	ctx["grid"] = self
	upgrade_hooks[id].call(ctx)
	return true


## open_hole(count): 请求挂起至下波 generate_wave() 末尾消费（DESIGN #393 附录 B.3 #13：
## 升级在结算期调用 → 下一道墙生成时补开洞，复用 HOLES 柱位逻辑）
func open_hole(count: int) -> void:
	if count > 0:
		_pending_holes.append(count)


func _consume_pending_holes() -> void:
	for i in _pending_holes:
		_open_hole_now(i)
	_pending_holes.clear()


func _open_hole_now(count: int) -> void:
	var cols: int = _compute_cols()
	for i in count:
		if _hole_columns.size() >= cols:
			break
		var c: int = randi_range(0, cols - 1)
		if c in _hole_columns:
			continue
		_hole_columns.append(c)
		_remove_column(c)


# ── #529 特殊砖（替换式生成 + 内部位判定）──

## 替换式特殊砖生成 (PRD 方案1)。仅厚度 ≥ SPECIAL_BRICK_MIN_THICKNESS 且存在
## 4 正交邻域齐全的砖位时, 标记恰好 1 颗。无候选 → 静默跳过 + 回退 wall_cleared (容错先例)。
func _spawn_special_brick() -> void:
	if rows < CONSTS.SPECIAL_BRICK_MIN_THICKNESS:
		return                              # AC4: 薄墙回退 (行为与现状一致)
	var target = _pick_internal_brick()
	if target == null:
		return                              # 无内部位 → 本波回退, 不 push_error (边界 8)
	target.set("is_special", true)
	target.set("breaker", "")
	if target.has_method("apply_special_visual"):
		target.call("apply_special_visual")


## 内部位候选: 4 正交邻域 (上/下/左/右) 均为存在砖。邻域判定 = 距离判定
## (dx==±(w+g) ∧ dy==0 或 dx==0 ∧ dy==±(h+g)), 布局无关 (洞/缝列无砖 → 天然不产生候选)。
## 候选选择: 距墙几何中心最近 (欧氏距离平方), 平局取行主序首个 — 确定性, 同 seed 可复现。
func _pick_internal_brick() -> Node2D:
	var step_x: float = _brick_w() + brick_gap
	var step_y: float = _brick_h() + brick_gap
	var by_pos: Dictionary = {}             # 位置量化 0.5 网格 → 砖 (浮点容差)
	for child in get_children():
		if child.is_in_group("bricks"):
			by_pos[_key(child.position)] = child
	if by_pos.size() < 5:
		return null                          # 少于 5 砖不可能有完整 4 邻域
	var center: Vector2 = _wall_center_local()
	var best: Node2D = null
	var best_d: float = INF
	for b in by_pos.values():
		var p: Vector2 = b.position
		if not (by_pos.has(_key(p + Vector2(-step_x, 0))) and by_pos.has(_key(p + Vector2(step_x, 0)))
			and by_pos.has(_key(p + Vector2(0, -step_y))) and by_pos.has(_key(p + Vector2(0, step_y)))):
			continue
		var d: float = b.position.distance_squared_to(center)
		if d < best_d:
			best_d = d
			best = b
	return best


func _key(v: Vector2) -> Vector2:
	return (v * 2.0).round() / 2.0          # 量化到 0.5 网格 (步长 68/28 整数, 位置精度 ≤0.5)


func _wall_center_local() -> Vector2:
	var cols: int = _compute_cols()
	var step_x: float = _brick_w() + brick_gap
	return Vector2(_compute_start_x(cols) + (cols - 1) * step_x * 0.5,
		wall_y - position.y)                # local_wall_y 同 generate_wave 推导


## blast_neighbors(pos, radius): 以 pos 为中心 radius 半径炸碎邻近砖
func blast_neighbors(pos: Vector2, radius: float) -> void:
	var to_destroy: Array = []
	for child in get_children():
		if child.is_in_group("bricks") and child.global_position.distance_to(pos) <= radius:
			to_destroy.append(child)
	for b in to_destroy:
		b.destroy("upgrade")                 # #529: 升级连锁来源标记 (≠ "" → 触发, 边界 4)


# ── 布局算法（§4.3）──

func _is_gap_column(c: int, layout: int) -> bool:
	return (layout == BrickLayout.GAPS or layout == BrickLayout.MIXED) and c % 5 == 4


func _is_hole_column(c: int) -> bool:
	return c in _hole_columns


func _pick_hole_columns(cols: int) -> void:
	var pool: Array = []
	for c in range(cols):
		pool.append(c)
	for i in hole_count:
		if pool.is_empty():
			break
		var idx: int = randi_range(0, pool.size() - 1)
		_hole_columns.append(pool[idx])
		pool.remove_at(idx)


func _remove_column(c: int) -> void:
	var w: float = _brick_w()
	var cols: int = _compute_cols()
	var cx: float = _compute_start_x(cols) + c * (w + brick_gap)
	var to_destroy: Array = []
	for child in get_children():
		if child.is_in_group("bricks") and abs(child.position.x - cx) <= w / 2.0:
			to_destroy.append(child)
	for b in to_destroy:
		b.destroy("upgrade")                 # #529: 升级连锁来源标记 (≠ "" → 触发, 边界 4)


# ── 几何 ──

func _brick_w() -> float:
	return maxf(brick_size.x, CONSTS.BRICK_MIN_DIM)   # 防隧穿 clamp（§6 边界 3）


func _brick_h() -> float:
	return maxf(brick_size.y, CONSTS.BRICK_MIN_DIM)


## cols = floor(SCREEN_WIDTH / (砖宽+缝))（720px 铺满，余量左右居中）
func _compute_cols() -> int:
	return maxi(int(floor(CONSTS.SCREEN_WIDTH / (_brick_w() + brick_gap))), 1)


func _compute_start_x(cols: int) -> float:
	var w: float = _brick_w()
	var total_w: float = cols * w + (cols - 1) * brick_gap
	return (CONSTS.SCREEN_WIDTH - total_w) / 2.0 + w / 2.0


func _spawn_brick(pos: Vector2) -> void:
	var scene: PackedScene = brick_scene
	if scene == null:
		scene = load("res://scenes/brick.tscn")
	var brick = scene.instantiate()
	brick.name = "Brick%03d" % get_child_count()
	brick.position = pos
	brick.grid = self
	add_child(brick)

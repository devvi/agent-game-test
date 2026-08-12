extends RefCounted
## 砖类升级效果实现（#387 §3.3）— 向 BreakoutGrid.upgrade_hooks 注册表注册实现。
## #384 BreakoutGrid 代码未落地 → 契约先行：
##   - 注册时机归 grid 侧（BreakoutGrid._ready() 调 BrickUpgradeHooks.register_all(self)）
##   - 分发经 grid.apply_upgrade_hook(id, ctx)，ctx 内 grid 引用由分发方注入 "grid" 键
##   - 假 grid 桩可测（tests/test_upgrade_pool.gd TC-H1/H2），不依赖 #384 落地
## 不变量: 不修改 #384 DESIGN 已合并的 API（generate_wave/clear_wall/
## brick_destroyed/wall_cleared）。

const _SELF = preload("res://gdscripts/brick_upgrade_hooks.gd")  # 自身脚本引用（规避 class_name 缓存问题）


static func register_all(grid: Object) -> void:
	if grid == null:
		return
	if grid.has_method("register_upgrade_hook"):
		grid.register_upgrade_hook("open_hole", Callable(_SELF, "_open_hole"))
		grid.register_upgrade_hook("blast_neighbors", Callable(_SELF, "_blast_neighbors"))


## open_hole(ctx): 下波 generate_wave 后补开洞（复用 #384 hole 布局逻辑）
static func _open_hole(ctx: Dictionary) -> void:
	var grid = ctx.get("grid")
	if grid == null or not grid.has_method("open_hole"):
		return
	grid.open_hole(int(ctx.get("count", 1)))


## blast_neighbors(ctx): 以 pos 为中心 radius 半径炸碎邻近砖
static func _blast_neighbors(ctx: Dictionary) -> void:
	var grid = ctx.get("grid")
	if grid == null or not grid.has_method("blast_neighbors"):
		return
	grid.blast_neighbors(ctx.get("pos", Vector2.ZERO), float(ctx.get("radius", 0.0)))

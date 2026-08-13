extends StaticBody2D
## 单砖（#384 DESIGN #414 §4.1）。
## StaticBody2D：group `bricks`、collision_layer=2（球 mask=3 已含 layer 2 → 零配置生效）、
## collision_mask=0（砖不需探测任何东西，只被球探测）。
## destroy() 幂等：通知 grid._on_brick_destroyed(self) 后 queue_free（延迟帧释放，
## grid 回调先 is_instance_valid 检查）。
##
## Design: docs/DESIGN/384-breakout-grid-brick-wall.md §4.1
## Parent Issue: #384 (实现随 #393 组装落地)


var grid: Node                 # 实例化时由 BreakoutGrid 注入
var _destroyed: bool = false


func _ready() -> void:
	add_to_group("bricks")
	collision_layer = 2
	collision_mask = 0


func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if grid != null and is_instance_valid(grid) and grid.has_method("_on_brick_destroyed"):
		grid._on_brick_destroyed(self)
	queue_free()

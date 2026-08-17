extends StaticBody2D
## 单砖（#384 DESIGN #414 §4.1）。
## StaticBody2D：group `bricks`、collision_layer=2（球 mask=3 已含 layer 2 → 零配置生效）、
## collision_mask=0（砖不需探测任何东西，只被球探测）。
## destroy() 幂等：通知 grid._on_brick_destroyed(self) 后 queue_free（延迟帧释放，
## grid 回调先 is_instance_valid 检查）。
##
## Design: docs/DESIGN/384-breakout-grid-brick-wall.md §4.1
## Parent Issue: #384 (实现随 #393 组装落地)

const CONSTS = preload("res://gdscripts/constants.gd")   # #529 新增

var grid: Node                 # 实例化时由 BreakoutGrid 注入
var _destroyed: bool = false
var is_special: bool = false      # #529: grid 生成时标记 (替换式, 每波 ≤1)
var breaker: String = ""          # #529: 销毁来源快照 ("player"/"ai"/"upgrade"/"")


func _ready() -> void:
	add_to_group("bricks")
	collision_layer = 2
	collision_mask = 0


func destroy(source: String = "") -> void:    # #529: 签名加默认参 (既有调用零破坏)
	if _destroyed:
		return
	_destroyed = true
	breaker = source                          # #529: 来源快照 (ball 传 last_toucher; grid 内部销毁传 "upgrade")
	if grid != null and is_instance_valid(grid) and grid.has_method("_on_brick_destroyed"):
		grid._on_brick_destroyed(self)
	if is_instance_valid(AudioEngine):   # #450 null-safe: 无 autoload 环境静默跳过
		AudioEngine.play_brick_break()
	queue_free()


## #529: 特殊砖视觉覆写 (brick.tscn 内运行时改色, 零 tscn 改动 — E2-2 文本断言保护)
## 由 grid._spawn_special_brick() 在 is_special=true 后调用; 无 ColorRect → no-op (容错先例 #526)。
func apply_special_visual() -> void:
	var rect := find_child("ColorRect", false, false) as ColorRect
	if rect == null:
		return
	rect.color = CONSTS.SPECIAL_BRICK_COLOR
	if rect.material != null:
		var mat: ShaderMaterial = rect.material.duplicate()
		mat.set_shader_parameter("glow_color", CONSTS.SPECIAL_BRICK_GLOW_COLOR)
		rect.material = mat       # #464 教训: 共享 .tres glow_color.a=1.0 → 必须独立材质实例

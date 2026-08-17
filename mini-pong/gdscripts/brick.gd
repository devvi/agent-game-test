extends StaticBody2D
## 单砖（#384 DESIGN #414 §4.1）。
## StaticBody2D：group `bricks`、collision_layer=2（球 mask=3 已含 layer 2 → 零配置生效）、
## collision_mask=0（砖不需探测任何东西，只被球探测）。
## destroy() 幂等：通知 grid._on_brick_destroyed(self) 后 queue_free（延迟帧释放，
## grid 回调先 is_instance_valid 检查）。
##
## #527 增补: brick_variant 视觉变体（0=普通/1=铁砖/2=奖励砖接口）。
## 仅视觉（颜色/glow），不改变可破坏性/分数/碰撞 —— 玩法语义留给未来玩法 issue。
##
## Design: docs/DESIGN/384-breakout-grid-brick-wall.md §4.1
## Design: docs/DESIGN/527-visual-enrichment.md §4.3
## Parent Issue: #384 (实现随 #393 组装落地), #527

const CONSTS = preload("res://gdscripts/constants.gd")

@export var brick_variant: int = 0        # 默认 0 → 既有渲染逐字节不变（AC5）

var grid: Node                 # 实例化时由 BreakoutGrid 注入
var _destroyed: bool = false
var _variant_applied: bool = false


func _ready() -> void:
	add_to_group("bricks")
	collision_layer = 2
	collision_mask = 0


## #527: 设置变体视觉。variant=0 → 颜色=base_color（默认 BRICK_NEON），材质不动（共享 .tres，
## 逐字节不变）；variant>=1 → ColorRect 显式设色 + 材质 duplicate 后改 glow_color
## （#464 教训: mix 权重 = glow*glow_color.a=1.0 → 边缘被 glow_color 完全覆盖）。
## 幂等：重复调用同 variant 直接返回（防重复 duplicate 泄漏）。
func apply_variant(variant: int, base_color: Color) -> void:
	if _variant_applied and brick_variant == variant:
		return
	brick_variant = variant
	_variant_applied = true
	var rect: ColorRect = $ColorRect
	if variant == 0:
		rect.color = base_color
		return
	var vcolor: Color = CONSTS.BRICK_VARIANT_COLORS.get(variant, base_color)
	rect.color = vcolor
	rect.material = rect.material.duplicate()                    # 独立材质实例（不污染共享 .tres）
	rect.material.set_shader_parameter("glow_color", vcolor)     # glow 同色（视觉一致）


func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if grid != null and is_instance_valid(grid) and grid.has_method("_on_brick_destroyed"):
		grid._on_brick_destroyed(self)
	if is_instance_valid(AudioEngine):   # #450 null-safe: 无 autoload 环境静默跳过
		AudioEngine.play_brick_break()
	queue_free()

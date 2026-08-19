extends Node2D
## StickFigure — 程序化火柴人剪影骨架（#574）。
## 归属: docs/DESIGN/574-stick-figure-silhouette-animation.md §2.2（骨架构建）
## 设计要点:
##   - 零 tscn / 零美术资产: _ready() 代码构建全部 pivot + Line2D/Polygon2D（AC5）
##   - 摆姿结构: 每肢体 = Node2D pivot（动画关键帧旋转/位移锚点）+ 子 Line2D；
##     头 = Polygon2D 实心圆（「剪影」语义要求实心填充而非描边）
##   - 参数校验: 非法几何参数 → push_warning + 回退 constants 默认值（不崩溃，§5-10 / Scenario L）
##   - 原画接入点: set_sprite_slot() 预留 sprite_slot 命名位（换 Sprite2D 层保留骨架，PRD §4.1）
##   - 节点树（DESIGN §2.2）:
##     TorsoPivot ─┬─ Line2D 躯干
##                 ├─ HeadPivot ── Polygon2D 头圆
##                 ├─ ArmLPivot ── Line2D 左臂
##                 ├─ ArmRPivot ── Line2D 右臂
##                 └─ SwordPivot ── Line2D 刀
##                    └── SwordArc（Polygon2D additive 刀光）
##     LegLPivot ── Line2D 左腿 / LegRPivot ── Line2D 右腿

class_name StickFigure

const C = preload("res://gdscripts/constants.gd")

@export var body_torso_length: float = C.BODY_TORSO_LENGTH
@export var body_arm_length: float = C.BODY_ARM_LENGTH
@export var body_leg_length: float = C.BODY_LEG_LENGTH
@export var body_head_radius: float = C.BODY_HEAD_RADIUS
@export var body_limb_width: float = C.BODY_LIMB_WIDTH
@export var sword_length: float = C.SWORD_LENGTH
@export var sword_width: float = C.SWORD_WIDTH

const HEAD_SEGMENTS: int = 16

var _pivots: Dictionary = {}


func _ready() -> void:
	_validate_geometry()
	_build_skeleton()


func _validate_geometry() -> void:
	## 非法几何参数（负长度/零宽度/非有限值）→ push_warning + 回退 constants 默认值（§5-10）
	var defaults: Dictionary = {
		"body_torso_length": C.BODY_TORSO_LENGTH,
		"body_arm_length": C.BODY_ARM_LENGTH,
		"body_leg_length": C.BODY_LEG_LENGTH,
		"body_head_radius": C.BODY_HEAD_RADIUS,
		"body_limb_width": C.BODY_LIMB_WIDTH,
		"sword_length": C.SWORD_LENGTH,
		"sword_width": C.SWORD_WIDTH,
	}
	for prop in defaults.keys():
		var v: float = get(prop)
		if not is_finite(v) or v <= 0.0:
			push_warning("StickFigure: invalid %s=%s, fallback to default %s" % [prop, str(v), str(defaults[prop])])
			set(prop, defaults[prop])


func _build_skeleton() -> void:
	## 按 DESIGN §2.2 节点树构建 7 pivot + Line2D 肢体 + Polygon2D 头圆 + SwordArc
	var torso_pivot: Node2D = _make_limb("TorsoPivot", body_torso_length, body_limb_width, C.BODY_COLOR)
	add_child(torso_pivot)
	_pivots["torso"] = torso_pivot

	var head_pivot: Node2D = Node2D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector2(0, -body_torso_length)
	head_pivot.add_child(_make_head())
	torso_pivot.add_child(head_pivot)
	_pivots["head"] = head_pivot

	var arm_l: Node2D = _make_limb("ArmLPivot", body_arm_length, body_limb_width, C.BODY_COLOR)
	arm_l.position = Vector2(-5, -body_torso_length)
	torso_pivot.add_child(arm_l)
	_pivots["arm_l"] = arm_l

	var arm_r: Node2D = _make_limb("ArmRPivot", body_arm_length, body_limb_width, C.BODY_COLOR)
	arm_r.position = Vector2(5, -body_torso_length)
	torso_pivot.add_child(arm_r)
	_pivots["arm_r"] = arm_r

	var sword_pivot: Node2D = _make_limb("SwordPivot", sword_length, sword_width, C.SWORD_COLOR)
	sword_pivot.position = Vector2(5, -body_torso_length)
	var arc: Polygon2D = _make_sword_arc()
	if arc != null:
		sword_pivot.add_child(arc)
	torso_pivot.add_child(sword_pivot)
	_pivots["sword"] = sword_pivot

	var leg_l: Node2D = _make_limb("LegLPivot", body_leg_length, body_limb_width, C.BODY_COLOR)
	leg_l.position = Vector2(-4, 0)
	add_child(leg_l)
	_pivots["leg_l"] = leg_l

	var leg_r: Node2D = _make_limb("LegRPivot", body_leg_length, body_limb_width, C.BODY_COLOR)
	leg_r.position = Vector2(4, 0)
	add_child(leg_r)
	_pivots["leg_r"] = leg_r

	# 原画接入点预留（sprite_slot 命名位，本期为空）
	var sprite_slot: Node2D = Node2D.new()
	sprite_slot.name = "sprite_slot"
	add_child(sprite_slot)


func _make_limb(limb_name: String, length: float, width: float, color: Color) -> Node2D:
	## 创建 pivot Node2D + 子 Line2D（自 pivot 原点向 -Y 延伸 length）
	var pivot: Node2D = Node2D.new()
	pivot.name = limb_name
	var line: Line2D = Line2D.new()
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -length)])
	line.width = width
	line.default_color = color
	pivot.add_child(line)
	return pivot


func _make_head() -> Polygon2D:
	## 头 = 圆多边形（BODY_HEAD_RADIUS，16 段），实心剪影填充
	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = _circle_points(body_head_radius, HEAD_SEGMENTS)
	poly.color = C.BODY_COLOR
	return poly


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _make_sword_arc() -> Polygon2D:
	## SwordArc（Polygon2D additive 刀光）经脚本资源创建（class_name 在 --script 下不可靠，用 load）
	var arc_script: GDScript = load("res://gdscripts/sword_arc.gd")
	if arc_script == null:
		push_warning("StickFigure: sword_arc.gd failed to load, sword arc omitted")
		return null
	var arc: Polygon2D = arc_script.new()
	arc.name = "SwordArc"
	return arc


func get_pivot(part: String) -> Node2D:
	## 按名取 pivot（"torso"/"head"/"arm_l"/"arm_r"/"sword"/"leg_l"/"leg_r"）
	## 供 AnimationPlayer 关键帧寻址 + 单测断言
	return _pivots.get(part)


func set_sprite_slot(sprite: Node2D) -> void:
	## 正式原画接入点（PRD §4.1）: 将 Sprite2D 视觉层挂入 sprite_slot 命名位，保留骨架结构。
	## 本期不实现，仅预留命名位（§1.2 交叉对照）。
	var slot: Node2D = get_node_or_null("sprite_slot")
	if slot == null:
		slot = Node2D.new()
		slot.name = "sprite_slot"
		add_child(slot)
	slot.add_child(sprite)

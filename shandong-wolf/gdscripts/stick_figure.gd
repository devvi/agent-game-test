extends Node2D
## StickFigure — 程序化火柴人剪影骨架（#574）。
## 归属: docs/DESIGN/574-stick-figure-silhouette-animation.md §2.2（骨架构建）
## 设计要点:
##   - 零 tscn / 零美术资产: _ready() 代码构建全部 pivot + Line2D/Polygon2D（AC5）
##   - 摆姿结构: 每肢体 = Node2D pivot（动画关键帧旋转/位移锚点）+ 子 Line2D；
##     头 = Polygon2D 实心圆（「剪影」语义要求实心填充而非描边）
##   - 参数校验: 非法几何参数 → push_warning + 回退 constants 默认值（不崩溃，§5-10 / Scenario L）
##   - 原画接入点: set_sprite_slot() 预留 sprite_slot 命名位（换 Sprite2D 层保留骨架，PRD §4.1）
##   - 节点树（DESIGN §2.2，#683 增颈/膝）:
##     TorsoPivot ─┬─ Line2D 躯干
##                 ├─ NeckPivot ─┬─ Line2D 颈
##                 │             └─ HeadPivot ── Polygon2D 头圆
##                 │                  └── [可选] HeadOutline Polygon2D 冷白环
##                 ├─ ArmLPivot ── Line2D 左臂
##                 ├─ ArmRPivot ── Line2D 右臂
##                 └─ SwordPivot ── Line2D 刀
##                    └── SwordArc（Polygon2D additive 刀光）
##     LegLPivot ── Line2D 大腿 ── LegKPivot ── Line2D 小腿
##     LegRPivot ── Line2D 大腿 ── LegKPivot ── Line2D 小腿

class_name StickFigure

const C = preload("res://gdscripts/constants.gd")

@export var body_torso_length: float = C.BODY_TORSO_LENGTH
@export var body_arm_length: float = C.BODY_ARM_LENGTH
@export var body_leg_length: float = C.BODY_LEG_LENGTH
@export var body_head_radius: float = C.BODY_HEAD_RADIUS
@export var body_limb_width: float = C.BODY_LIMB_WIDTH
@export var sword_length: float = C.SWORD_LENGTH
@export var sword_width: float = C.SWORD_WIDTH
@export var body_neck_length: float = C.BODY_NECK_LENGTH
@export var body_leg_upper_length: float = C.BODY_LEG_UPPER_LENGTH
@export var body_leg_lower_length: float = C.BODY_LEG_LOWER_LENGTH
@export var head_outline_enabled: bool = C.HEAD_OUTLINE_ENABLED
@export var head_outline_width: float = C.HEAD_OUTLINE_WIDTH
@export var head_outline_color: Color = C.HEAD_OUTLINE_COLOR

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
		"body_neck_length": C.BODY_NECK_LENGTH,
		"body_leg_upper_length": C.BODY_LEG_UPPER_LENGTH,
		"body_leg_lower_length": C.BODY_LEG_LOWER_LENGTH,
		"head_outline_width": C.HEAD_OUTLINE_WIDTH,
	}
	for prop in defaults.keys():
		var v: float = get(prop)
		if not is_finite(v) or v <= 0.0:
			push_warning("StickFigure: invalid %s=%s, fallback to default %s" % [prop, str(v), str(defaults[prop])])
			set(prop, defaults[prop])


func _build_skeleton() -> void:
	## 按 DESIGN §2.2 + #683 §2.1/§2.2 构建 10 pivot + Line2D 肢体 + Polygon2D 头圆 + SwordArc
	var torso_pivot: Node2D = _make_limb("TorsoPivot", body_torso_length, body_limb_width, C.BODY_COLOR)
	add_child(torso_pivot)
	_pivots["torso"] = torso_pivot

	var neck_pivot: Node2D = _make_limb("NeckPivot", body_neck_length, body_limb_width, C.BODY_COLOR)
	neck_pivot.position = Vector2(0, -body_torso_length)
	torso_pivot.add_child(neck_pivot)
	_pivots["neck"] = neck_pivot

	var head_pivot: Node2D = Node2D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector2(0, -body_neck_length)
	head_pivot.add_child(_make_head())
	if head_outline_enabled:
		head_pivot.add_child(_make_head_outline())
	neck_pivot.add_child(head_pivot)
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

	var leg_l: Node2D = _make_limb("LegLPivot", body_leg_upper_length, body_limb_width, C.BODY_COLOR)
	leg_l.position = Vector2(-4, 0)
	_reverse_limb(leg_l)
	leg_l.add_child(_make_knee_pivot("LegKPivot", body_leg_lower_length))
	add_child(leg_l)
	_pivots["leg_l"] = leg_l
	_pivots["leg_k_l"] = leg_l.get_node("LegKPivot")

	var leg_r: Node2D = _make_limb("LegRPivot", body_leg_upper_length, body_limb_width, C.BODY_COLOR)
	leg_r.position = Vector2(4, 0)
	_reverse_limb(leg_r)
	leg_r.add_child(_make_knee_pivot("LegKPivot", body_leg_lower_length))
	add_child(leg_r)
	_pivots["leg_r"] = leg_r
	_pivots["leg_k_r"] = leg_r.get_node("LegKPivot")

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


func _make_knee_pivot(pivot_name: String, shin_length: float) -> Node2D:
	## 膝 pivot（#683 §2.2，#704 反向）: 挂于髋 pivot 下 @ (0,+body_leg_upper_length)，
	## 内含小腿 Line2D（自膝点向 +Y 延伸 shin_length）
	var knee: Node2D = _make_limb(pivot_name, shin_length, body_limb_width, C.BODY_COLOR)
	knee.position = Vector2(0, body_leg_upper_length)
	_reverse_limb(knee)
	return knee


func _reverse_limb(pivot: Node2D) -> void:
	## #704 专用: 取 pivot 首个子 Line2D，将 points[1] 自 -Y 反向为 +Y（方向翻转，长度不变）。
	## 非 Line2D 首子或 points.size() < 2 时 no-op。
	var child: Node = pivot.get_child(0) if pivot.get_child_count() > 0 else null
	if child == null or not child is Line2D:
		return
	var line: Line2D = child as Line2D
	var points: PackedVector2Array = line.points
	if points.size() < 2:
		return
	points[1] = Vector2(0, points[1].length())
	line.points = points


func _make_head() -> Polygon2D:
	## 头 = 圆多边形（body_head_radius，16 段），实心剪影填充
	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = _circle_points(body_head_radius, HEAD_SEGMENTS)
	poly.color = C.BODY_COLOR
	return poly


func _make_head_outline() -> Polygon2D:
	## 头轮廓（#683 §2.1 可选，taste 决策点实验 1）: 冷白圆环 Polygon2D，
	## polygon = 外圆（头径 + 轮廓宽，16 段），holes = [内圆（头径）]
	var ring: Polygon2D = Polygon2D.new()
	ring.name = "HeadOutline"
	var outer_r: float = body_head_radius + head_outline_width
	ring.polygon = _circle_points(outer_r, HEAD_SEGMENTS)
	var holes: Array[PackedVector2Array] = [_circle_points(body_head_radius, HEAD_SEGMENTS)]
	ring.holes = holes
	ring.color = head_outline_color
	return ring


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
	## 按名取 pivot（"torso"/"head"/"arm_l"/"arm_r"/"sword"/"leg_l"/"leg_r"/"neck"/"leg_k_l"/"leg_k_r"）
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

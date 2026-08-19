extends Polygon2D
## SwordArc — additive 刀光弧线（#574）。
## 归属: docs/DESIGN/574-stick-figure-silhouette-animation.md §2.5（刀光）
## 设计要点:
##   - 纯视觉层（AC2）: 节点树无 Area2D/CollisionShape2D/任何碰撞类型，碰撞判定归 #577
##   - additive 材质: CanvasItemMaterial blend_mode=BLEND_MODE_ADD（代码创建，零 .tres）
##   - 几何: 扇形弧（SWORD_ARC_RADIUS 半径 / SWORD_ARC_SWEEP_DEG 120° 张角 / SWORD_ARC_RINGS 4 环，
##           逐顶点 alpha 从 SWORD_ARC_ALPHA_START 径向线性衰减到 0）
##   - 生命周期: trigger_burst() 显示 → _process 按 FRAME_ANIM_SWORD_ARC_FADE(4) 帧淡出隐藏（反页游光效）
##   - 挂载: SwordPivot 子节点，随刀旋转（挥砍轨迹锚定刀身中轴，配方 §6.5「刀是视觉焦点」）

class_name SwordArc

const C = preload("res://gdscripts/constants.gd")

var _fade_frames: int = 0
var _fade_step: float = 0.0


func _ready() -> void:
	_build_material()
	_build_polygon()
	visible = false


func _build_material() -> void:
	## additive 合成（代码创建，零 .tres 资源文件）
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _build_polygon() -> void:
	## 扇形弧 + 径向透明度衰减环（RINGS 环从内到外 alpha 线性衰减到 0）
	## 以 SwordPivot 原点为圆心；ring 折扇构造已实测 Geometry2D.triangulate_polygon 可三角化。
	var sweep_rad: float = deg_to_rad(C.SWORD_ARC_SWEEP_DEG)
	var rings: int = max(C.SWORD_ARC_RINGS, 1)
	var steps: int = 20
	var pts: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	pts.append(Vector2.ZERO)
	cols.append(Color(1, 1, 1, C.SWORD_ARC_ALPHA_START))
	for ring in range(1, rings + 1):
		var r: float = C.SWORD_ARC_RADIUS * float(ring) / float(rings)
		var alpha: float = C.SWORD_ARC_ALPHA_START * (1.0 - float(ring - 1) / float(rings))
		for j in range(steps + 1):
			var a: float = -sweep_rad / 2.0 + sweep_rad * float(j) / float(steps)
			pts.append(Vector2(cos(a), sin(a)) * r)
			cols.append(Color(1, 1, 1, alpha))
	polygon = pts
	vertex_colors = cols


func trigger_burst() -> void:
	## 攻击暴发段首帧调用: 显示 + 开始 FRAME_ANIM_SWORD_ARC_FADE 帧淡出
	visible = true
	_fade_frames = C.FRAME_ANIM_SWORD_ARC_FADE
	_fade_step = 1.0 / float(max(_fade_frames, 1))
	modulate.a = 1.0


func _process(_delta: float) -> void:
	## 每帧衰减 modulate.a → 归零隐藏（短衰减 ≈4 帧，轨迹醒目但不滞留）
	if not visible:
		return
	if _fade_frames <= 0:
		visible = false
		return
	_fade_frames -= 1
	modulate.a = max(0.0, modulate.a - _fade_step)
	if _fade_frames <= 0 or modulate.a <= 0.0:
		visible = false

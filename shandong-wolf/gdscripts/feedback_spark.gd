extends GPUParticles2D
class_name FeedbackSpark
## FeedbackSpark — 打击反馈火花粒子（#579，AC3）。
## 归属: docs/DESIGN/579-combat-feedback-system.md §2.2
## 职责: one_shot 火花 burst —— 位置/法线/等级参数化，苍白金 #ffd9a0 系（issue 禁橙色页游爆焰）。
## 设计要点:
##   - 材质代码创建（零 .tres，与项目零美术资产红线一致）；z_index < 角色层（粒子不盖角色）
##   - burst_at(world_pos, normal, level): 碰撞点直传（AC3，无中心猜测）、方向沿刀面法线、
##     amount 按等级、restart() + emitting=true 标准序列（PRD §5.3-2）
##   - 重复触发: one_shot restart() 覆盖旧 burst 不叠加粒子池（边界 1）
## 全部 # DRAFT 候补值，定稿归 #584/用户。

const C = preload("res://gdscripts/constants.gd")

const SPARK_TRAIL_COLOR: Color = Color("#d3b188")  # 尾色: 略暗苍白金（禁橙色）


func _ready() -> void:
	one_shot = true
	emitting = false
	z_index = C.FEEDBACK_SPARK_Z_INDEX
	_build_material()


func _build_material() -> void:
	## 代码创建 ParticleProcessMaterial: 苍白金渐变 + 默认方向向上 + 按 A 级默认参数初始化
	var ppm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([C.FEEDBACK_SPARK_COLOR, SPARK_TRAIL_COLOR])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = gradient
	ppm.color_ramp = ramp
	ppm.direction = Vector3(0, -1, 0)
	ppm.gravity = Vector3.ZERO
	ppm.spread = 30.0
	ppm.initial_velocity_min = float(C.FEEDBACK_SPARK_VELOCITY.get("A", 240.0)) * 0.8
	ppm.initial_velocity_max = float(C.FEEDBACK_SPARK_VELOCITY.get("A", 240.0))
	process_material = ppm
	lifetime = float(C.FEEDBACK_SPARK_LIFETIME.get("A", 0.45))


func burst_at(world_pos: Vector2, normal: Vector2, level: String) -> void:
	## 碰撞点直传（AC3）: 位置=注入值、方向=注入法线、数量/速度/寿命按等级参数包。
	global_position = world_pos
	if process_material is ParticleProcessMaterial:
		var ppm: ParticleProcessMaterial = process_material as ParticleProcessMaterial
		ppm.direction = Vector3(normal.x, normal.y, 0)
		var vel: float = float(C.FEEDBACK_SPARK_VELOCITY.get(level, 170.0))
		ppm.initial_velocity_min = vel * 0.8
		ppm.initial_velocity_max = vel
		lifetime = float(C.FEEDBACK_SPARK_LIFETIME.get(level, 0.35))
	amount = int(C.FEEDBACK_SPARK_COUNT.get(level, 6))
	restart()
	emitting = true

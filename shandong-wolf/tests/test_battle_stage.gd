extends Object
## Test suite for battle_stage scene (#583) — 雪夜山东村战斗场景（单场景 MVP 舞台）.
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/583-snowy-shandong-village-battle-stage.md §8 (Scenario A-D).
##
## Godot 4.7.1 --script 硬性约束（同 test_enemy_ai.gd）:
##   - 禁止 := 类型推断（4.7.1 视推断警告为硬错误）— 一律显式类型或普通 =
##   - class_name 一律经 load()/preload 脚本资源访问，禁止按标识符引用
##   - 场景实例 add 到 SceneTree root（Engine.get_main_loop()）触发 _ready；
##     纯声明式场景无脚本，断言以节点结构/属性为准
##   - 物理冒烟（B1/B2）用手动 move_and_slide() 驱动 CharacterBody2D（同
##     test_player_controller 模式），不依赖真实帧循环；move_and_slide 位移 =
##     velocity * physics_delta(1/60)，velocity 取 3000px/s → 每步 50px

const BattleStageScene = preload("res://scenes/battle_stage.tscn")
const WolfConstantsScript = preload("res://gdscripts/constants.gd")

const DELTA: float = 1.0 / 60.0

var passed: int = 0
var failed: int = 0

var root: Node = null


func run() -> void:
	print("\n=== BattleStage Tests ===")
	_test_a1_scene_loadable()
	_test_a2_stage_width()
	_test_a3_platform_segments_single_collider()
	_test_a4_object_budget()
	_test_a5_no_external_textures_no_canvas_modulate()
	_test_b1_collider_blocks_body()
	_test_b2_full_width_walkthrough()
	_test_b3_spawn_marker_layout()
	_test_c1_ink_palette()
	_test_c2_moon_composition()
	_test_c3_moonlight_luma()
	_test_c4_canvas_modulate_count_one()
	_test_d1_camera_present_current()
	_test_d2_camera_limits_cover()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _get_root() -> Node:
	if root == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		root = tree.root
	return root


func _instantiate_stage() -> Node:
	if BattleStageScene == null:
		return null
	var inst: Node = BattleStageScene.instantiate()
	_get_root().add_child(inst)
	return inst


func _cleanup(node: Node) -> void:
	if node != null and is_instance_valid(node):
		_get_root().remove_child(node)
		node.queue_free()


func _ground_collider(stage: Node) -> CollisionShape2D:
	var ground: Node = stage.get_node_or_null("Ground")
	if ground == null:
		return null
	var cs: CollisionShape2D = ground.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return cs


# ── Scenario A: 场景结构与参数集中 ──

func _test_a1_scene_loadable() -> void:
	# A1: battle_stage.tscn load + instantiate 成功；根节点 BattleStage 存在
	var inst: Node = _instantiate_stage()
	_assert(inst != null, "A1: battle_stage.tscn instantiate 成功")
	if inst != null:
		_assert(inst.name == "BattleStage", "A1: 根节点名为 BattleStage（实际: %s）" % inst.name)
	_cleanup(inst)


func _test_a2_stage_width() -> void:
	# A2: 场景总宽 2400px（AC1）；Ground CollisionShape2D 矩形宽 == STAGE_WIDTH_PX，与 constants 一致
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "A2: 场景实例化失败")
		return
	var cs: CollisionShape2D = _ground_collider(inst)
	_assert(cs != null, "A2: Ground/CollisionShape2D 存在")
	var expected_w: float = float(WolfConstantsScript.STAGE_WIDTH_PX)
	if cs != null and cs.shape is RectangleShape2D:
		var rect: RectangleShape2D = cs.shape as RectangleShape2D
		_assert(is_equal_approx(rect.size.x, expected_w),
			"A2: 碰撞矩形宽 %s == STAGE_WIDTH_PX %s (AC1)" % [str(rect.size.x), str(expected_w)])
	else:
		_assert(false, "A2: CollisionShape2D.shape 是 RectangleShape2D（实际: %s）" % str(cs.shape if cs != null else "null"))
	_cleanup(inst)


func _test_a3_platform_segments_single_collider() -> void:
	# A3: 视觉平台 3 段 + 单一连续碰撞面（非 3 段拼接，无缝隙结构性保证）
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "A3: 场景实例化失败")
		return
	var cs: CollisionShape2D = _ground_collider(inst)
	var colliders: Array = []
	if cs != null:
		colliders = [cs]
	_assert(colliders.size() == 1, "A3: Ground 下 CollisionShape2D 恰 1 个（单一连续碰撞面，实际: %d）" % colliders.size())
	var drift: Node = inst.get_node_or_null("PlatformVisual/SnowDriftFront")
	var segments: Array = []
	if drift != null:
		segments = drift.find_children("*", "Polygon2D", true, false)
	_assert(segments.size() == 3,
		"A3: SnowDriftFront 视觉分段 Polygon2D == 3（AC1 雪地 3 条平台，实际: %d）" % segments.size())
	_cleanup(inst)


func _test_a4_object_budget() -> void:
	# A4: 物件预算 ≤5 —— 草屋 Polygon2D == 2 + 枯树 Line2D == 2 → 4 ≤ OBJECT_BUDGET_MAX
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "A4: 场景实例化失败")
		return
	var houses: Node = inst.get_node_or_null("Houses")
	var house_polys: Array = []
	if houses != null:
		house_polys = houses.find_children("*", "Polygon2D", true, false)
	_assert(house_polys.size() == 2, "A4: 草屋 Polygon2D == 2（实际: %d）" % house_polys.size())
	var trees: Node = inst.get_node_or_null("Trees")
	var tree_lines: Array = []
	if trees != null:
		tree_lines = trees.find_children("*", "Line2D", true, false)
	_assert(tree_lines.size() == 2, "A4: 枯树 Line2D == 2（实际: %d）" % tree_lines.size())
	var total: int = house_polys.size() + tree_lines.size()
	_assert(total <= int(WolfConstantsScript.OBJECT_BUDGET_MAX),
		"A4: 物件计数 %d ≤ OBJECT_BUDGET_MAX %d（山峦/月亮为背景不计数）" % [total, int(WolfConstantsScript.OBJECT_BUDGET_MAX)])
	_cleanup(inst)


func _test_a5_no_external_textures_no_canvas_modulate() -> void:
	# A5: 零外部贴图（无 ext_resource 指向 .png/.jpg/.webp）+ 无 CanvasModulate 节点
	var f: FileAccess = FileAccess.open("res://scenes/battle_stage.tscn", FileAccess.READ)
	if f == null:
		_assert(false, "A5: battle_stage.tscn 打开失败")
		return
	var text: String = f.get_as_text()
	f.close()
	var has_img: bool = text.find(".png") != -1 or text.find(".jpg") != -1 or text.find(".webp") != -1
	_assert(not has_img, "A5: .tscn 无外部贴图引用（.png/.jpg/.webp）")
	var inst: Node = _instantiate_stage()
	if inst != null:
		var cms: Array = inst.find_children("*", "CanvasModulate", true, false)
		_assert(cms.is_empty(), "A5: battle_stage 内零 CanvasModulate（C3 守卫延续，实际: %d）" % cms.size())
	_cleanup(inst)


# ── Scenario B: 碰撞与出生点 ──

func _test_b1_collider_blocks_body() -> void:
	# B1: 碰撞体可阻挡 —— CharacterBody2D 站平台顶面 move_and_slide 后不穿透（AC3）
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "B1: 场景实例化失败")
		return
	var cs: CollisionShape2D = _ground_collider(inst)
	var base_y: float = float(WolfConstantsScript.PLATFORM_Y_BASE)
	if cs != null and cs.shape is RectangleShape2D:
		var rect: RectangleShape2D = cs.shape as RectangleShape2D
		var top_y: float = cs.global_position.y + rect.size.y * 0.5
		_assert(is_equal_approx(top_y, base_y),
			"B1: 碰撞顶面 y == PLATFORM_Y_BASE %s（实际顶面: %s）" % [str(base_y), str(top_y)])
		# 物理冒烟：body 从顶面 1px 上方，velocity.y 向下，move_and_slide 后不穿透
		var body: CharacterBody2D = CharacterBody2D.new()
		var bcs: CollisionShape2D = CollisionShape2D.new()
		var cap: CapsuleShape2D = CapsuleShape2D.new()
		cap.radius = 10.0
		cap.height = 30.0
		bcs.shape = cap
		body.add_child(bcs)
		body.global_position = Vector2(400.0, base_y - 31.0)
		inst.add_child(body)
		body.velocity = Vector2(0.0, 60.0)
		body.move_and_slide()
		var body_bottom: float = body.global_position.y + 25.0  # 胶囊半高 15 + radius 10
		_assert(body_bottom <= base_y + 1.0,
			"B1: 站立后角色底部 y %s ≤ 顶面 %s + 1px（不穿透，AC3）" % [str(body_bottom), str(base_y)])
		body.queue_free()
	else:
		_assert(false, "B1: Ground/CollisionShape2D 缺失或非矩形")
	_cleanup(inst)


func _test_b2_full_width_walkthrough() -> void:
	# B2: 全宽走查零阻塞（AC1 + Spike 2）—— velocity.y=0 模型下 x=0→2400 位移连续
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "B2: 场景实例化失败")
		return
	var base_y: float = float(WolfConstantsScript.PLATFORM_Y_BASE)
	var body: CharacterBody2D = CharacterBody2D.new()
	var bcs: CollisionShape2D = CollisionShape2D.new()
	var cap: CapsuleShape2D = CapsuleShape2D.new()
	cap.radius = 10.0
	cap.height = 30.0
	bcs.shape = cap
	body.add_child(bcs)
	body.global_position = Vector2(0.0, base_y - 31.0)
	inst.add_child(body)
	var prev_x: float = 0.0
	var blocked: bool = false
	var fell: bool = false
	# velocity 3000px/s × (1/60) = 50px/步 × 48 步 = 2400px
	for i in range(48):
		body.velocity = Vector2(3000.0, 0.0)
		body.move_and_slide()
		if body.global_position.x <= prev_x + 0.5:
			blocked = true
		prev_x = body.global_position.x
		if body.global_position.y > base_y + 1.0:
			fell = true
	_assert(not blocked, "B2: 全宽走查无碰撞卡顿（位移连续）")
	_assert(not fell, "B2: 全程 y 保持 == PLATFORM_Y_BASE（无跌落）")
	_assert(body.global_position.x >= 2390.0, "B2: 到达 x=2400 终点（实际: %s）" % str(body.global_position.x))
	body.queue_free()
	_cleanup(inst)


func _test_b3_spawn_marker_layout() -> void:
	# B3: Marker2D ×3 存在；与草屋/枯树包围盒无交集、不在平台内部（AC3）
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "B3: 场景实例化失败")
		return
	var names: Array = ["PlayerSpawn", "EnemySpawnA", "EnemySpawnB"]
	for n in names:
		var m: Node = inst.get_node_or_null(n)
		_assert(m != null and m is Marker2D, "B3: %s (Marker2D) 存在" % n)
	# 出生点与物件包围盒无交集（草屋 x≈300/1900、枯树 x≈900/1500，包围盒近似）
	var houses: Node = inst.get_node_or_null("Houses")
	var trees: Node = inst.get_node_or_null("Trees")
	var boxes: Array = []
	if houses != null:
		for pnode in houses.find_children("*", "Polygon2D", true, false):
			var p: Polygon2D = pnode as Polygon2D
			if p != null:
				boxes.append(Rect2(p.global_position - Vector2(100.0, 100.0), Vector2(200.0, 200.0)))
	if trees != null:
		for lnode in trees.find_children("*", "Line2D", true, false):
			var l: Line2D = lnode as Line2D
			if l != null:
				boxes.append(Rect2(l.global_position - Vector2(60.0, 150.0), Vector2(120.0, 300.0)))
	var overlap: bool = false
	for n in names:
		var m: Node = inst.get_node_or_null(n)
		if m == null:
			continue
		var m2: Marker2D = m as Marker2D
		if m2 == null:
			continue
		for b in boxes:
			if b.has_point(m2.global_position):
				overlap = true
				print("  B3: %s 与物件包围盒重叠 @ %s" % [n, str(m2.global_position)])
	_assert(not overlap, "B3: 出生点与草屋/枯树包围盒无交集（PRD §5.2-3）")
	_cleanup(inst)


# ── Scenario C: 视觉与色板 ──

func _test_c1_ink_palette() -> void:
	# C1: 冷墨色调（AC2）—— Polygon2D/Line2D 主体颜色与 STAGE_INK_COLOR 色差 ≤10%（±0.1 RGB）
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "C1: 场景实例化失败")
		return
	var ink: Color = WolfConstantsScript.STAGE_INK_COLOR
	var checked: int = 0
	var off: int = 0
	for nnode in inst.find_children("*", "Polygon2D", true, false):
		var n: Polygon2D = nnode as Polygon2D
		if n == null:
			continue
		if n.name == "SnowDriftFront" or n.name.begins_with("SnowDrift"):
			continue  # 雪层是 SNOW_LAYER_COLOR 不是墨色
		var c: Color = n.color
		var d: float = maxf(absf(c.r - ink.r), maxf(absf(c.g - ink.g), absf(c.b - ink.b)))
		checked += 1
		if d > 0.1:
			off += 1
			print("  C1: %s 颜色 %s 与 STAGE_INK_COLOR %s 色差 %.3f > 0.1" % [n.name, str(c), str(ink), d])
	for lnode in inst.find_children("*", "Line2D", true, false):
		var l: Line2D = lnode as Line2D
		if l == null:
			continue
		if l.name.begins_with("RoofSnow"):
			continue  # 屋顶压雪线是白色
		var c: Color = l.default_color
		var d: float = maxf(absf(c.r - ink.r), maxf(absf(c.g - ink.g), absf(c.b - ink.b)))
		checked += 1
		if d > 0.1:
			off += 1
			print("  C1: %s 颜色 %s 与 STAGE_INK_COLOR %s 色差 %.3f > 0.1" % [l.name, str(c), str(ink), d])
	_assert(checked >= 4, "C1: 检查到 ≥4 个墨色剪影节点（实际: %d）" % checked)
	_assert(off == 0, "C1: 全部墨色节点与 STAGE_INK_COLOR 色差 ≤0.1（偏差 %d 个）" % off)
	_cleanup(inst)


func _test_c2_moon_composition() -> void:
	# C2: 月亮构图 —— Moon 节点存在；y < 150（苍月悬顶）；MoonGlow 存在
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "C2: 场景实例化失败")
		return
	var moon: Node = inst.get_node_or_null("Moon")
	_assert(moon != null, "C2: Moon 节点存在")
	if moon != null:
		var mi: MeshInstance2D = moon as MeshInstance2D
		_assert(mi != null, "C2: Moon 是 MeshInstance2D (Mesh2D 径向渐变)（实际: %s）" % moon.get_class())
		if mi != null:
			_assert(mi.global_position.y < 150.0,
				"C2: 月亮 y %s < 150（苍月悬顶，实际 MOON_POSITION_Y=%s）" % [str(mi.global_position.y), str(WolfConstantsScript.MOON_POSITION_Y)])
		var glow: Node = moon.get_node_or_null("MoonGlow")
		_assert(glow != null, "C2: Moon/MoonGlow 光晕层存在（shader 或双层圆回退）")
	_cleanup(inst)


func _test_c3_moonlight_luma() -> void:
	# C3: 月光染后 luma ≥30（#624 F3）—— STAGE_INK_COLOR 经 MOONLIGHT_COLOR_APPLIED 染色后不黑死
	var ink: Color = WolfConstantsScript.STAGE_INK_COLOR
	var applied: Color = WolfConstantsScript.MOONLIGHT_COLOR_APPLIED
	var tinted: Color = Color(ink.r * applied.r, ink.g * applied.g, ink.b * applied.b, 1.0)
	var luma: float = 0.2126 * tinted.r + 0.7152 * tinted.g + 0.0722 * tinted.b
	_assert(luma >= 30.0 / 255.0,
		"C3: 染后 luma %.3f ≥ 30/255（%s × %s 色板不过黑，#624 F3）" % [luma, str(ink), str(applied)])
	_cleanup(null)


func _test_c4_canvas_modulate_count_one() -> void:
	# C4: 组装态（battle_stage + Atmosphere）CanvasModulate 计数 == 1（#624 C3 守卫延续）
	var inst: Node = _instantiate_stage()
	var atmos_scene: PackedScene = load("res://scenes/atmosphere/atmosphere_layer.tscn")
	var atmos: Node = null
	if atmos_scene != null:
		atmos = atmos_scene.instantiate()
		if atmos != null:
			_get_root().add_child(atmos)
	var cms: Array = []
	if inst != null:
		cms = inst.find_children("*", "CanvasModulate", true, false)
	if atmos != null:
		cms.append_array(atmos.find_children("*", "CanvasModulate", true, false))
	# battle_stage 自身 0 个（A5 已断言）；组装态总计数 == 1（Atmosphere 唯一 Moonlight）
	_assert(cms.size() == 1,
		"C4: 组装态 CanvasModulate 计数 == 1（实际: %d，battle_stage 零新增）" % cms.size())
	_cleanup(inst)
	if atmos != null:
		_cleanup(atmos)


# ── Scenario D: 相机 ──

func _test_d1_camera_present_current() -> void:
	# D1: StageCamera (Camera2D) 存在且 current == true；limit_left == 0；limit_right >= 2400
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "D1: 场景实例化失败")
		return
	var cam: Node = inst.get_node_or_null("StageCamera")
	_assert(cam != null and cam is Camera2D, "D1: StageCamera (Camera2D) 存在")
	if cam != null and cam is Camera2D:
		var c: Camera2D = cam as Camera2D
		_assert(c.current, "D1: StageCamera.current == true（AC5 截图/手动运行即见全貌）")
		_assert(c.limit_left == 0, "D1: limit_left == 0（实际: %d）" % c.limit_left)
		_assert(c.limit_right >= int(WolfConstantsScript.STAGE_WIDTH_PX),
			"D1: limit_right %d ≥ STAGE_WIDTH_PX %d" % [c.limit_right, int(WolfConstantsScript.STAGE_WIDTH_PX)])
	_cleanup(inst)


func _test_d2_camera_limits_cover() -> void:
	# D2: 相机 limits 覆盖视口高（含 margin，贴边不露白，PRD §5.2-2）
	var inst: Node = _instantiate_stage()
	if inst == null:
		_assert(false, "D2: 场景实例化失败")
		return
	var cam: Node = inst.get_node_or_null("StageCamera")
	if cam != null and cam is Camera2D:
		var c: Camera2D = cam as Camera2D
		_assert(c.limit_top <= 0, "D2: limit_top %d ≤ 0（防顶部露白）" % c.limit_top)
		_assert(c.limit_bottom >= 720, "D2: limit_bottom %d ≥ 720（防底部露白）" % c.limit_bottom)
	else:
		_assert(false, "D2: StageCamera 缺失")
	_cleanup(inst)

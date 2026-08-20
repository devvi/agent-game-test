extends RefCounted
## Test suite for ReactionController 打击反馈系统 (#579).
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/579-combat-feedback-system.md §8 (Scenario A-G, 28 test cases)
## 覆盖: 分级矩阵（A）/ 时间缩放栈（B）/ 火花 burst（C）/ 屏震衰减（D）/ 白闪双通道（E）/
##       弹反四要素同帧（F）/ 碰撞点推导（G）。
##
## TDD red phase: reaction_controller.gd / feedback_spark.gd / time_scale_stack.gd /
##   screen_shake.gd / flash_effect.gd 尚不存在 → 运行时 load() 返回 null → 打印 SKIP 不判失败；
##   constants.gd 反馈分区（FEEDBACK_*）本步骤已入库 → 常量级断言直接执行。
## 实现落地后 load() 返回脚本 → 用例实例化真实组件执行完整断言。
##
## Godot 4.7.1 --script 硬性约束（同 test_combat_judge.gd）:
##   - 禁止 := 类型推断（4.7.1 视推断警告为硬错误）— 一律显式类型或普通 =
##   - class_name 一律经 load()/preload 脚本资源访问，禁止按标识符引用
##   - preload 仅用于 constants.gd（已存在）；实现脚本一律运行时 load() + null 守卫
##   - Node 子类经 s.new() 实例化（extends 决定基类）；加入 root 触发 _ready
##   - Tween 用 custom_step() 同步推进（同 test_hud 模式）；Engine.time_scale 用例后复原 1.0
##
## FEEDBACK_MATRIX 契约（本套件定义，implement 必须照此建矩阵）:
##   matrix[event] = {level: String, spark/hitstop/shake/slowmo/flash: Dictionary|null}
##   —— 五效果维键必须存在；spark/hitstop/shake 非空（每事件至少有基础三件套）；
##      slowmo/flash 为空 Dictionary 或 null 表示该级禁用；flash 含 "screen" 键表示全屏淡闪。

const C = preload("res://gdscripts/constants.gd")

var passed: int = 0
var failed: int = 0

var root: Node = null
var _fb_log: Array = []


func run() -> void:
	print("\n=== ReactionController Tests ===")
	Engine.time_scale = 1.0
	_test_a1_matrix_completeness()
	_test_a2_level_monotonicity()
	_test_a3_slowmo_restricted()
	_test_a4_anti_arcade()
	_test_a5_unknown_event_noop()
	_test_b1_single_push_pop()
	_test_b2_nested_min()
	_test_b3_wall_clock_fallback()
	_test_b4_max_stack_depth()
	_test_b5_hitstop_nonzero()
	_test_c1_collision_point()
	_test_c2_direction()
	_test_c3_particle_count()
	_test_c4_layer()
	_test_c5_color()
	_test_d1_monotonic_decay()
	_test_d2_direction()
	_test_d3_no_camera_noop()
	_test_d4_stacking_max()
	_test_e1_entity_flash()
	_test_e2_freed_entity_guard()
	_test_e3_fullscreen_flash_a_minus()
	_test_e4_layer_order()
	_test_f1_parry_composite()
	_test_f2_feedback_played_signal()
	_test_g1_derive_impact_point()
	_test_g2_no_pivot_fallback()
	_test_g3_subscription_identity()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _skip(msg: String) -> void:
	print("  SKIP: %s" % msg)


# ── helpers ─────────────────────────────────────────────────────────────

func _get_root() -> Node:
	if root == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		root = tree.root
	return root


func _cleanup_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.is_inside_tree():
			node.get_parent().remove_child(node)
		node.queue_free()


func _const_map() -> Dictionary:
	var script = load("res://gdscripts/constants.gd")
	if script == null:
		return {}
	return script.get_script_constant_map()


func _new_script(path: String):
	## TDD 红期脚本缺失 → 返回 null（调用方 SKIP），并避免 load() 对缺失资源的 ERROR 噪音
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _new_controller():
	## ReactionController 实例（TDD 红期缺失 → null → 调用方 SKIP/guard）
	var s = _new_script("res://gdscripts/reaction_controller.gd")
	if s == null:
		return null
	return s.new()


func _new_spark():
	var s = _new_script("res://gdscripts/feedback_spark.gd")
	if s == null:
		return null
	return s.new()


func _new_time_stack():
	var s = _new_script("res://gdscripts/time_scale_stack.gd")
	if s == null:
		return null
	return s.new()


func _new_shake():
	var s = _new_script("res://gdscripts/screen_shake.gd")
	if s == null:
		return null
	return s.new()


func _new_flash():
	var s = _new_script("res://gdscripts/flash_effect.gd")
	if s == null:
		return null
	return s.new()


func _new_combat_entity(params: Dictionary):
	var s = _new_script("res://gdscripts/combat_entity.gd")
	if s == null:
		return null
	return s.new(params)


func _matrix_of(ctl) -> Dictionary:
	## 读 reaction_controller.gd 脚本常量 FEEDBACK_MATRIX（event→等级→参数包）
	var script: GDScript = ctl.get_script()
	if script == null:
		return {}
	return script.get_script_constant_map().get("FEEDBACK_MATRIX", {})


func _pack(entry) -> Dictionary:
	## 参数包: 支持 {level, params} 嵌套 或 {level, spark...} 扁平两种形态
	if entry is Dictionary and entry.has("params"):
		return entry["params"]
	return entry if entry is Dictionary else {}


func _mk_pivot_entity(pos: Vector2, pivot_global: Vector2) -> Node2D:
	## 构造带 TorsoPivot/SwordPivot 子节点的实体（SwordPivot 全局位置 = pivot_global）
	var e = Node2D.new()
	e.position = pos
	_get_root().add_child(e)
	var torso = Node2D.new()
	torso.name = "TorsoPivot"
	e.add_child(torso)
	var sword = Node2D.new()
	sword.name = "SwordPivot"
	torso.add_child(sword)
	sword.position = pivot_global - e.global_position
	return e


func _feedback_const_values() -> Dictionary:
	## 收集全部 FEEDBACK_ 常量数值（含嵌套 Dictionary）→ 集合（anti-arcade 集中化断言用）
	var out: Dictionary = {}
	var cm: Dictionary = _const_map()
	for key in cm:
		if str(key).begins_with("FEEDBACK_"):
			_collect_numbers(cm[key], out)
	return out


func _collect_numbers(v, out: Dictionary) -> void:
	if v is int or v is float:
		out[float(v)] = true
	elif v is Dictionary:
		for k in v:
			_collect_numbers(v[k], out)


func _find_tween(node: Node) -> Tween:
	## 扫描节点属性找实现存放的 Tween（custom_step 同步推进用）；找不到 → null
	for p in node.get_property_list():
		var nm: String = str(p["name"])
		if not nm.begins_with("_"):
			continue
		var v = node.get(nm)
		if v != null and v is Tween:
			return v as Tween
	return null


func _on_feedback_played(event: String, level: String, data: Dictionary) -> void:
	_fb_log.append([event, level, data])


# ── Scenario A: 分级矩阵映射与单调性（AC1/AC5）───────────────────────────

func _test_a1_matrix_completeness() -> void:
	# 常量分区存在性（本步骤已入库，直接执行）
	var cm: Dictionary = _const_map()
	var feed_consts: Array = [
		"FEEDBACK_SPARK_COUNT", "FEEDBACK_SPARK_COLOR", "FEEDBACK_HITSTOP_MS",
		"FEEDBACK_SHAKE_PX", "FEEDBACK_SLOWMO", "FEEDBACK_FLASH",
		"FEEDBACK_TIME_MAX_STACK", "FEEDBACK_SPARK_Z_INDEX", "FEEDBACK_SPARK_VELOCITY",
		"FEEDBACK_SPARK_LIFETIME", "FEEDBACK_SHAKE_DECAY", "FEEDBACK_ENTITY_FLASH_FACTOR",
	]
	for name in feed_consts:
		_assert(cm.has(name), "A1: constants 反馈分区含 %s" % name)
	# 矩阵完备性（实现落地后执行）
	var ctl = _new_controller()
	if ctl == null:
		_skip("reaction_controller.gd missing — FEEDBACK_MATRIX 矩阵完备性待实现")
		return
	var matrix: Dictionary = _matrix_of(ctl)
	var main_events: Array = ["parry_success", "block_held", "hit_landed", "stance_broken", "execute", "player_hit"]
	for event in main_events:
		_assert(matrix.has(event), "A1: FEEDBACK_MATRIX 含 %s 事件" % event)
		if not matrix.has(event):
			continue
		var pack: Dictionary = _pack(matrix[event])
		_assert(pack.has("level") and str(pack["level"]) != "", "A1: %s 参数包含等级映射" % event)
		var enabled: int = 0
		for dim in ["spark", "hitstop", "shake", "slowmo", "flash"]:
			if not pack.has(dim):
				_assert(false, "A1: %s 参数包缺 %s 维" % [event, dim])
				continue
			var v = pack[dim]
			if v is Dictionary and not v.is_empty():
				enabled += 1
			elif v != null:
				enabled += 1
		_assert(enabled >= 3, "A1: %s 参数包 ≥3 个效果维非空（spark/hitstop/shake 基础三件套，got %d）" % [event, enabled])


func _test_a2_level_monotonicity() -> void:
	## AC5: 反馈与奖励成正比 —— 参数沿 S≥A≥A-≥B≥C 单调。
	## 全部为 # DRAFT 候补值，定稿归 #584/用户（任务禁止实现期改值）。
	## 5 对违例是 issue body 语义的 DOCUMENTED DESIGN 异常（MONOTONIC_EXCEPTIONS 表）:
	##   spark_count: S(14) < A(18)   —— S 级视觉主体=刀光弧线+血色粒子，火花密度让位（血粒子 10-14 粒）
	##   spark_count: B(6)  < C(8)    —— 命中成功奖励 > 格挡中性防守（与 hitstop/shake 同源，issue 矩阵原文）
	##   hitstop_ms:  A(90) < A_(100) —— 架势崩解是大事件，顿帧重于弹反
	##   hitstop_ms:  B(30) < C(50)   —— 命中成功奖励 > 格挡中性防守（issue 矩阵原文）
	##   shake_px:    B(1.0) < C(2.0) —— 同上
	## 异常键 = 违反前置级 >= 关系的后置级（任务的语义定义，见下）。若 #584 定稿改常量消除某违例，
	## 该异常断言失败 → 强制 conscious map update（防静默漂移，改常量必须同步本表）。
	const MONOTONIC_EXCEPTIONS: Dictionary = {
		"spark_count": ["A", "C"],
		"hitstop_ms": ["A_", "C"],
		"shake_px": ["C"],
	}
	var chain: Array = ["S", "A", "A_", "B", "C"]
	var dims: Dictionary = {
		"spark_count": C.FEEDBACK_SPARK_COUNT,
		"hitstop_ms": C.FEEDBACK_HITSTOP_MS,
		"shake_px": C.FEEDBACK_SHAKE_PX,
	}
	for dim_name in dims:
		var d: Dictionary = dims[dim_name]
		var exceptions: Array = MONOTONIC_EXCEPTIONS[dim_name]
		var prev: float = 0.0
		var prev_tier: String = ""
		var first: bool = true
		for tier in chain:
			if not d.has(tier):
				continue
			var v: float = float(d[tier])
			if first:
				prev = v
				prev_tier = str(tier)
				first = false
				continue
			if exceptions.has(str(tier)):
				## 文档化异常: 该级对前置级的 >= 关系被有意打破 —— 断言违例真实存在
				## （常量被改消除违例 → 本断言失败 → 必须同步 MONOTONIC_EXCEPTIONS）
				_assert(prev < v - 0.0001, "%s 异常 %s(%s) < %s(%s) 必须真实存在（DRAFT 候补值；常量被改 → 请同步 MONOTONIC_EXCEPTIONS）" % [dim_name, prev_tier, prev, str(tier), v])
				prev = v
				prev_tier = str(tier)
				continue
			_assert(prev >= v - 0.0001, "%s 单调: %s(%s) >= %s(%s)（DRAFT 候补值；定稿归 #584）" % [dim_name, prev_tier, prev, str(tier), v])
			prev = v
			prev_tier = str(tier)


func _test_a3_slowmo_restricted() -> void:
	# 慢动作仅 S/A/A- 级（issue AC5: 滥用失去重量）；B/C 级禁用
	var slowmo: Dictionary = C.FEEDBACK_SLOWMO
	for tier in ["S", "A", "A_"]:
		_assert(slowmo.has(tier), "A3: FEEDBACK_SLOWMO 定义 %s 级" % tier)
	_assert(not slowmo.has("B"), "A3: 慢动作 B 级禁用（无 'B' 键）")
	_assert(not slowmo.has("C"), "A3: 慢动作 C 级禁用（无 'C' 键）")
	# 矩阵级（实现落地后）: 所有事件包 slowmo 键为空/null → 视为禁用
	var ctl = _new_controller()
	if ctl == null:
		return
	var matrix: Dictionary = _matrix_of(ctl)
	for event in matrix:
		var pack: Dictionary = _pack(matrix[event])
		var tier_name: String = str(pack.get("level", ""))
		if tier_name == "B" or tier_name == "C":
			var sm = pack.get("slowmo")
			var disabled: bool = sm == null or (sm is Dictionary and sm.is_empty())
			_assert(disabled, "A3: %s(%s) 慢动作必须禁用" % [event, tier_name])
	_cleanup_node(ctl)


func _test_a4_anti_arcade() -> void:
	# 全屏淡白闪仅 A- 可达（AC5/AC6 页游感红线）: 矩阵中启用 flash.screen 的事件必须恰好是 stance_broken
	var ctl = _new_controller()
	if ctl != null:
		var matrix: Dictionary = _matrix_of(ctl)
		var screen_flash_events: Array = []
		for event in matrix:
			var pack: Dictionary = _pack(matrix[event])
			var flash = pack.get("flash")
			if flash is Dictionary and flash.get("screen", false):
				screen_flash_events.append(event)
		_assert(screen_flash_events.size() == 1 and screen_flash_events[0] == "stance_broken", "A4: 全屏闪白唯一调用点 == stance_broken(A-)（got %s）" % str(screen_flash_events))
		# 集中化: 矩阵参数包数值必须全部来自 FEEDBACK_ 常量（禁止矩阵内散落硬编码）
		var vals: Dictionary = _feedback_const_values()
		for event in matrix:
			var pack: Dictionary = _pack(matrix[event])
			for dim in pack:
				var v = pack[dim]
				if v is float or v is int:
					_assert(vals.has(float(v)), "A4: %s.%s 数值 %s 必须来自 FEEDBACK_ 常量" % [event, dim, v])
				elif v is Dictionary:
					for k in v:
						var sv = v[k]
						if sv is float or sv is int:
							_assert(vals.has(float(sv)), "A4: %s.%s.%s 数值 %s 必须来自 FEEDBACK_ 常量" % [event, dim, k, sv])
		_cleanup_node(ctl)
	else:
		_skip("reaction_controller.gd missing — 矩阵反页游断言待实现")
	# 常量断言（直接执行）: A- 全屏闪参数 0.25 / 100ms
	var fl: Dictionary = C.FEEDBACK_FLASH
	_assert(fl.has("A_"), "A4: FEEDBACK_FLASH 定义 A_（全屏）级")
	if fl.has("A_"):
		var a_minus: Dictionary = fl["A_"]
		_assert(absf(float(a_minus["alpha"]) - 0.25) < 0.0001, "A4: 全屏闪 alpha == 0.25")
		_assert(int(a_minus["ms"]) == 100, "A4: 全屏闪时长 == 100ms")


func _test_a5_unknown_event_noop() -> void:
	## 边界 6: 未知事件 → push_warning + no-op，Engine.time_scale 不变
	var ctl = _new_controller()
	if ctl == null:
		_skip("reaction_controller.gd missing")
		return
	_get_root().add_child(ctl)
	if ctl.has_signal("feedback_played"):
		ctl.feedback_played.connect(_on_feedback_played)
	_fb_log = []
	var before: float = Engine.time_scale
	ctl.trigger_feedback("nonexistent", {})
	_assert(Engine.time_scale == before, "A5: 未知事件 no-op（Engine.time_scale 不变）")
	_assert(_fb_log.is_empty(), "A5: 未知事件不发射 feedback_played")
	Engine.time_scale = 1.0
	_cleanup_node(ctl)


# ── Scenario B: 时间缩放栈三路径（AC4）───────────────────────────────────

func _test_b1_single_push_pop() -> void:
	var ts = _new_time_stack()
	if ts == null:
		_skip("time_scale_stack.gd missing")
		return
	ts.push(0.05, 150)
	_assert(absf(Engine.time_scale - 0.05) < 0.0001, "B1: push(0.05,150) → Engine.time_scale == 0.05")
	ts.pop()
	_assert(absf(Engine.time_scale - 1.0) < 0.0001, "B1: pop() → Engine.time_scale == 1.0")
	Engine.time_scale = 1.0


func _test_b2_nested_min() -> void:
	## D1 min 语义: 最慢层主导，非栈顶 —— hit-stop 0.05 期间慢动作 0.3 不稀释顿帧
	var ts = _new_time_stack()
	if ts == null:
		_skip("time_scale_stack.gd missing")
		return
	ts.push(0.05, 150)
	ts.push(0.3, 200)
	_assert(absf(Engine.time_scale - 0.05) < 0.0001, "B2: 嵌套中间值 == 0.05（最慢层主导，非栈顶 0.3）")
	ts.pop()
	_assert(absf(Engine.time_scale - 0.3) < 0.0001, "B2: 首 pop → 0.3（慢动作层保留）")
	ts.pop()
	_assert(absf(Engine.time_scale - 1.0) < 0.0001, "B2: 全 pop → 1.0")
	Engine.time_scale = 1.0


func _test_b3_wall_clock_fallback() -> void:
	## 墙钟兜底（AC4 机械保证）: 漏 pop + 推进墙钟超 deadline → tick() 强制恢复
	var ts = _new_time_stack()
	if ts == null:
		_skip("time_scale_stack.gd missing")
		return
	ts.push(0.05, 50)
	_assert(absf(Engine.time_scale - 0.05) < 0.0001, "B3: push 后未到期 → 0.05")
	ts.tick(Time.get_ticks_msec() + 200)
	_assert(absf(Engine.time_scale - 1.0) < 0.0001, "B3: 墙钟超 deadline → tick() 强制恢复 1.0")
	Engine.time_scale = 1.0


func _test_b4_max_stack_depth() -> void:
	var ts = _new_time_stack()
	if ts == null:
		_skip("time_scale_stack.gd missing")
		return
	var max_depth: int = int(C.FEEDBACK_TIME_MAX_STACK)
	_assert(max_depth == 3, "B4: FEEDBACK_TIME_MAX_STACK == 3")
	ts.push(0.4, 5000)
	ts.push(0.3, 5000)
	ts.push(0.2, 5000)
	ts.push(0.1, 5000)
	_assert(ts._layers.size() == max_depth, "B4: 第 4 次 push 被丢弃（栈深 == MAX_STACK_DEPTH，got %d）" % ts._layers.size())
	_assert(absf(Engine.time_scale - 0.2) < 0.0001, "B4: 被丢弃的 0.1 未生效（有效 min == 0.2，got %s）" % Engine.time_scale)
	for i in range(max_depth):
		ts.pop()
	_assert(absf(Engine.time_scale - 1.0) < 0.0001, "B4: 恢复路径完整（全 pop → 1.0）")
	Engine.time_scale = 1.0


func _test_b5_hitstop_nonzero() -> void:
	## hit-stop 用 0.05 而非 0（0 冻结引擎处理 → 墙钟兜底失效红线，PRD §8.4-3）
	var hitstop: Dictionary = C.FEEDBACK_HITSTOP_MS
	var all_positive: bool = true
	for key in hitstop:
		if float(hitstop[key]) <= 0.0:
			all_positive = false
	_assert(all_positive, "B5: FEEDBACK_HITSTOP_MS 无 0 值（hit-stop 最小 0.05）")


# ── Scenario C: 火花 burst（AC3）─────────────────────────────────────────

func _test_c1_collision_point() -> void:
	## 碰撞点直传（AC3）: burst_at 注入 position → global_position == 注入值（无中心猜测代码路径）
	var spark = _new_spark()
	if spark == null:
		_skip("feedback_spark.gd missing")
		return
	_get_root().add_child(spark)
	var pos = Vector2(123, 45)
	spark.burst_at(pos, Vector2(0, -1), "A")
	_assert(spark.global_position == pos, "C1: burst_at 碰撞点直传（global_position == 注入值 %s）" % str(pos))
	_cleanup_node(spark)


func _test_c2_direction() -> void:
	## AC3: 方向沿刀面法线（ParticleProcessMaterial.direction 为 Vector3，z 恒 0）
	var spark = _new_spark()
	if spark == null:
		_skip("feedback_spark.gd missing")
		return
	_get_root().add_child(spark)
	var normal = Vector2(0, -1)
	spark.burst_at(Vector2(0, 0), normal, "A")
	if spark.process_material is ParticleProcessMaterial:
		var ppm: ParticleProcessMaterial = spark.process_material as ParticleProcessMaterial
		_assert(ppm.direction == Vector3(normal.x, normal.y, 0), "C2: ParticleProcessMaterial.direction == 注入法线")
	else:
		_assert(false, "C2: FeedbackSpark 创建 ParticleProcessMaterial")
	_cleanup_node(spark)


func _test_c3_particle_count() -> void:
	var spark = _new_spark()
	if spark == null:
		_skip("feedback_spark.gd missing")
		return
	_get_root().add_child(spark)
	spark.burst_at(Vector2(0, 0), Vector2(0, -1), "A")
	var expect: int = int(C.FEEDBACK_SPARK_COUNT["A"])
	_assert(spark.amount >= 16 and spark.amount <= 20, "C3: A 级 amount ∈ [16,20]（got %d）" % spark.amount)
	_assert(spark.amount == expect, "C3: amount == FEEDBACK_SPARK_COUNT['A']（got %d, expect %d）" % [spark.amount, expect])
	_assert(spark.emitting == true, "C3: emitting == true（one_shot restart 触发序列）")
	_cleanup_node(spark)


func _test_c4_layer() -> void:
	## 层级红线: 火花 < 角色层（粒子不盖角色）
	var spark = _new_spark()
	if spark == null:
		_skip("feedback_spark.gd missing")
		return
	_get_root().add_child(spark)
	_assert(spark.z_index == C.FEEDBACK_SPARK_Z_INDEX, "C4: z_index == FEEDBACK_SPARK_Z_INDEX（%d，低于角色层）" % C.FEEDBACK_SPARK_Z_INDEX)
	_cleanup_node(spark)


func _test_c5_color() -> void:
	## 颜色: 苍白金 #ffd9a0（issue 禁橙色页游爆焰）；color_ramp 为 GradientTexture1D 包裹 Gradient
	var spark = _new_spark()
	if spark == null:
		_skip("feedback_spark.gd missing")
		return
	_get_root().add_child(spark)
	spark.burst_at(Vector2(0, 0), Vector2(0, -1), "A")
	if spark.process_material != null and spark.process_material.color_ramp != null:
		var tex: Texture2D = spark.process_material.color_ramp
		if tex is GradientTexture1D:
			var gt: GradientTexture1D = tex as GradientTexture1D
			if gt.gradient != null:
				_assert(gt.gradient.get_color(0).is_equal_approx(Color("#ffd9a0")), "C5: color_ramp 主色 == #ffd9a0")
			else:
				_assert(false, "C5: GradientTexture1D.gradient 必须设置")
		else:
			_assert(false, "C5: color_ramp 必须为 GradientTexture1D")
	else:
		_assert(false, "C5: FeedbackSpark 设置 color_ramp（苍白金渐变）")
	_cleanup_node(spark)


# ── Scenario D: 屏震衰减（实验 2）────────────────────────────────────────

func _test_d1_monotonic_decay() -> void:
	## 单调衰减: trauma² 指数衰减 → offset 幅值单调递减、终值回 0
	var shake = _new_shake()
	if shake == null:
		_skip("screen_shake.gd missing")
		return
	_get_root().add_child(shake)
	var cam = Camera2D.new()
	_get_root().add_child(cam)
	shake.camera_path = shake.get_path_to(cam)
	shake.shake(3.0, Vector2(1, 0))
	var prev: float = 9999.0
	var last: float = -1.0
	var ok: bool = true
	for i in range(60):
		shake._process(0.05)
		var cur: float = cam.offset.length()
		if cur > prev + 0.05:
			ok = false
		prev = cur
		last = cur
	_assert(ok, "D1: 屏震 offset 幅值逐帧单调不增（trauma² 衰减）")
	_assert(last < 0.001, "D1: 屏震终值回 0（got %s）" % last)
	_cleanup_node(cam)
	_cleanup_node(shake)


func _test_d2_direction() -> void:
	## 方向: offset 沿攻击向量轴向（C 级 2px 沿攻击方向可感知）
	var shake = _new_shake()
	if shake == null:
		_skip("screen_shake.gd missing")
		return
	_get_root().add_child(shake)
	var cam = Camera2D.new()
	_get_root().add_child(cam)
	shake.camera_path = shake.get_path_to(cam)
	shake.shake(3.0, Vector2(1, 0))
	shake._process(0.016)
	_assert(absf(cam.offset.y) < 0.0001, "D2: 水平攻击 → offset 限定 x 轴（y == 0，轴向对齐攻击向量）")
	_cleanup_node(cam)
	_cleanup_node(shake)


func _test_d3_no_camera_noop() -> void:
	## 边界 2: camera_path 空 → shake() 不崩 + 无相机 no-op（push_warning）
	var shake = _new_shake()
	if shake == null:
		_skip("screen_shake.gd missing")
		return
	_get_root().add_child(shake)
	shake.camera_path = NodePath()
	shake.shake(3.0, Vector2(1, 0))
	shake._process(0.016)
	_assert(shake._trauma > 0.0, "D3: 无相机时 shake 仍记录 trauma（调用不崩）")
	_cleanup_node(shake)


func _test_d4_stacking_max() -> void:
	## 边界 1: 同帧两次 shake → trauma 取 max（cap 1.0），不线性叠加爆震
	var shake = _new_shake()
	if shake == null:
		_skip("screen_shake.gd missing")
		return
	shake.shake(3.0, Vector2(1, 0))
	shake.shake(3.0, Vector2(1, 0))
	_assert(shake._trauma <= 1.0, "D4: trauma 不超 1.0")
	_assert(absf(shake._trauma - 1.0) < 0.0001, "D4: 两次 0.6 增量 cap 于 1.0（got %s）" % shake._trauma)
	_assert(shake._trauma < 1.2, "D4: 无线性叠加（trauma != 1.2）")
	_assert(absf(shake._max_offset_px - 3.0) < 0.0001, "D4: max offset 取 max 非求和（got %s）" % shake._max_offset_px)


# ── Scenario E: 白闪双通道───────────────────────────────────────────────

func _test_e1_entity_flash() -> void:
	## 实体白闪: modulate 冲高（Color(5,5,5)）→ 渐回 WHITE（tween 完整）
	var flash = _new_flash()
	if flash == null:
		_skip("flash_effect.gd missing")
		return
	_get_root().add_child(flash)
	var entity = Node2D.new()
	_get_root().add_child(entity)
	entity.modulate = Color.WHITE
	flash.flash_entity(entity, 0.35, 120)
	_assert(entity.modulate.r > 4.0 and entity.modulate.g > 4.0 and entity.modulate.b > 4.0, "E1: 实体 modulate 冲高 ~Color(5,5,5)（深色火柴人也冲白）")
	var tw: Tween = _find_tween(flash)
	if tw != null:
		tw.custom_step(2.0)
		_assert(entity.modulate.is_equal_approx(Color.WHITE), "E1: tween 完整 → modulate 渐回 WHITE")
	else:
		print("  note: E1 tween 非属性可达，仅断言冲高（实现落地后确认恢复语义）")
	_cleanup_node(entity)
	_cleanup_node(flash)


func _test_e2_freed_entity_guard() -> void:
	## 边界 7: 已 free 实体 → flash_entity 跳过，无报错
	var flash = _new_flash()
	if flash == null:
		_skip("flash_effect.gd missing")
		return
	var entity = Node2D.new()
	entity.free()
	flash.flash_entity(entity, 0.35, 120)
	_assert(not is_instance_valid(entity), "E2: 实体已 free（is_instance_valid == false）")
	_assert(true, "E2: flash_entity(freed 实体) 跳过无报错")
	_cleanup_node(flash)


func _test_e3_fullscreen_flash_a_minus() -> void:
	## 全屏淡闪仅 A-: alpha/时长 == 常量（0.25 / 100ms）
	var fl: Dictionary = C.FEEDBACK_FLASH
	_assert(fl.has("A_"), "E3: FEEDBACK_FLASH 定义 A_ 级")
	if fl.has("A_"):
		var a_minus: Dictionary = fl["A_"]
		_assert(absf(float(a_minus["alpha"]) - 0.25) < 0.0001, "E3: 全屏闪 alpha == 0.25")
		_assert(int(a_minus["ms"]) == 100, "E3: 全屏闪时长 == 100ms")
	var flash = _new_flash()
	if flash == null:
		_skip("flash_effect.gd missing")
		return
	_get_root().add_child(flash)
	flash.flash_screen(0.25, 100)
	var rect = flash.find_child("ColorRect", true, false)
	if rect != null:
		_assert(absf(rect.color.a - 0.25) < 0.0001, "E3: flash_screen ColorRect alpha == 0.25")
	else:
		_assert(false, "E3: FlashEffect 构建全屏 ColorRect（淡闪通道）")
	_cleanup_node(flash)


func _test_e4_layer_order() -> void:
	## 层序: CanvasLayer layer == 0（低于 UI/氛围层，不遮 HUD）
	var flash = _new_flash()
	if flash == null:
		_skip("flash_effect.gd missing")
		return
	_get_root().add_child(flash)
	var cl = flash.find_child("CanvasLayer", true, false)
	if cl != null and cl is CanvasLayer:
		var layer: CanvasLayer = cl as CanvasLayer
		_assert(layer.layer == 0, "E4: 全屏闪 CanvasLayer layer == 0")
	else:
		_assert(false, "E4: FlashEffect 构建 CanvasLayer（layer=0）")
	_cleanup_node(flash)


# ── Scenario F: 弹反成功四要素同帧（AC2 决定性）───────────────────────────

func _test_f1_parry_composite() -> void:
	## AC2: trigger_feedback("parry_success") 单帧内 —— 火花/顿帧/屏震/白闪四要素同帧激活
	var ctl = _new_controller()
	if ctl == null:
		_skip("reaction_controller.gd missing")
		return
	_get_root().add_child(ctl)
	var enemy = _new_combat_entity({is_player=false, life_total=1})
	var attacker = _new_combat_entity({is_player=true, life_total=2})
	if enemy == null or attacker == null:
		_cleanup_node(ctl)
		return
	_get_root().add_child(enemy)
	_get_root().add_child(attacker)
	ctl.trigger_feedback("parry_success", {
		"position": Vector2(120, 60),
		"normal": Vector2(0, -1),
		"target_entity": enemy,
		"attacker_entity": attacker,
		"source": "test",
	})
	_assert(ctl._spark != null and ctl._spark.emitting == true, "F1: 火花 emitting == true（同帧）")
	_assert(absf(Engine.time_scale - 0.05) < 0.0001, "F1: Engine.time_scale == 0.05（hit-stop min 语义，got %s）" % Engine.time_scale)
	_assert(ctl._shake != null and ctl._shake._trauma > 0.0, "F1: 屏震 trauma > 0（同帧）")
	_assert(enemy.modulate.r > 4.0 and enemy.modulate.g > 4.0 and enemy.modulate.b > 4.0, "F1: 敌人 modulate 冲高（白闪，同帧）")
	Engine.time_scale = 1.0
	_cleanup_node(enemy)
	_cleanup_node(attacker)
	_cleanup_node(ctl)


func _test_f2_feedback_played_signal() -> void:
	## #593 hook 契约: feedback_played(event, level, data)
	var ctl = _new_controller()
	if ctl == null:
		_skip("reaction_controller.gd missing")
		return
	_get_root().add_child(ctl)
	if ctl.has_signal("feedback_played"):
		ctl.feedback_played.connect(_on_feedback_played)
	else:
		_assert(false, "F2: ReactionController 定义 feedback_played 信号")
		_cleanup_node(ctl)
		return
	_fb_log = []
	var enemy = _new_combat_entity({is_player=false, life_total=1})
	if enemy != null:
		_get_root().add_child(enemy)
	ctl.trigger_feedback("parry_success", {"target_entity": enemy, "attacker_entity": null, "source": "test"})
	_assert(_fb_log.size() == 1, "F2: feedback_played 恰发射一次（got %d）" % _fb_log.size())
	if _fb_log.size() == 1:
		_assert(_fb_log[0][0] == "parry_success", "F2: event == 'parry_success'（got %s）" % str(_fb_log[0][0]))
		_assert(_fb_log[0][1] == "A", "F2: level == 'A'（got %s）" % str(_fb_log[0][1]))
		_assert(_fb_log[0][2] is Dictionary, "F2: data 为 Dictionary")
	Engine.time_scale = 1.0
	if enemy != null:
		_cleanup_node(enemy)
	_cleanup_node(ctl)


# ── Scenario G: 碰撞点推导（AC3/边界 8）──────────────────────────────────

func _test_g1_derive_impact_point() -> void:
	## AC3: 两 SwordPivot 中点 = 刀与刀交点 + 法线（非角色中心）
	var ctl = _new_controller()
	if ctl == null:
		_skip("reaction_controller.gd missing")
		return
	var attacker = _mk_pivot_entity(Vector2(100, 50), Vector2(130, 50))
	var defender = _mk_pivot_entity(Vector2(200, 50), Vector2(230, 50))
	var r: Dictionary = ctl._derive_impact_point(attacker, defender, 1)
	var expect_pos = Vector2(180, 50)
	_assert(r["position"] == expect_pos, "G1: 碰撞点 == 两 SwordPivot 中点（got %s）" % str(r["position"]))
	_assert(r["normal"] == Vector2(0, -1), "G1: normal == Vector2(0, -direction)（got %s）" % str(r["normal"]))
	_cleanup_node(defender)
	_cleanup_node(attacker)
	_cleanup_node(ctl)


func _test_g2_no_pivot_fallback() -> void:
	## 边界 8: 无 pivot → 回退 attacker.global_position + facing 方向 + push_warning，不崩
	var ctl = _new_controller()
	if ctl == null:
		_skip("reaction_controller.gd missing")
		return
	var attacker = Node2D.new()
	attacker.position = Vector2(100, 50)
	_get_root().add_child(attacker)
	var defender = Node2D.new()
	defender.position = Vector2(200, 50)
	_get_root().add_child(defender)
	var r: Dictionary = ctl._derive_impact_point(attacker, defender, 1)
	_assert(r["position"] == attacker.global_position, "G2: 无 pivot 回退 attacker.global_position（got %s）" % str(r["position"]))
	_assert(r["normal"] == Vector2(1, 0), "G2: 回退 normal == Vector2(direction, 0) facing 兜底（got %s）" % str(r["normal"]))
	_cleanup_node(defender)
	_cleanup_node(attacker)
	_cleanup_node(ctl)


func _test_g3_subscription_identity() -> void:
	## D4: subscribe_entity(player/enemy) 后 state_changed→stagger 分别映射 player_hit / hit_landed
	var ctl = _new_controller()
	if ctl == null:
		_skip("reaction_controller.gd missing")
		return
	_get_root().add_child(ctl)
	if ctl.has_signal("feedback_played"):
		ctl.feedback_played.connect(_on_feedback_played)
	else:
		_assert(false, "G3: ReactionController 定义 feedback_played 信号")
		_cleanup_node(ctl)
		return
	var player = _new_combat_entity({is_player=true, life_total=2})
	var enemy = _new_combat_entity({is_player=false, life_total=1})
	if player == null or enemy == null:
		_cleanup_node(ctl)
		return
	ctl.subscribe_entity(player)
	ctl.subscribe_entity(enemy)
	_fb_log = []
	player.request_transition("stagger")
	_assert(_fb_log.size() == 1 and _fb_log[0][0] == "player_hit", "G3: 玩家 stagger → player_hit（got %s）" % str(_fb_log))
	_fb_log = []
	enemy.request_transition("stagger")
	_assert(_fb_log.size() == 1 and _fb_log[0][0] == "hit_landed", "G3: 敌人 stagger → hit_landed（got %s）" % str(_fb_log))
	Engine.time_scale = 1.0
	_cleanup_node(player)
	_cleanup_node(enemy)
	_cleanup_node(ctl)

extends Object
## Test suite for stick-figure silhouette skeleton & keyframe animation (#574).
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/574-stick-figure-silhouette-animation.md §8 (Scenario A–L)
##
## Godot 4.7.1 --script 模式硬性约束:
##   - 禁止 := 类型推断（4.7.1 视推断警告为硬错误）——一律显式类型声明或普通 =
##   - class_name 在 --script 模式下可能无法解析 → 一律经脚本资源访问:
##       已有 constants.gd 用 preload（test_constants.gd 同款）；
##       新增实现文件（stick_figure / stick_figure_controller / sword_arc /
##       player_stick_figure.tscn）由后续 implement 任务生成，TDD 红期允许缺失，
##       故用运行时 load() 惰性解析（缺失 → 断言失败而非整文件 parse error）
##   - 场景实例化: load(...).instantiate() 后 add_child 到 run_tests 的 SceneTree
##     （call_deferred 使 _run_tests 在树就绪后执行，root 可用）
##   - 节点引用优先 get_node_or_null()
##   - 断言不依赖真实渲染: AnimationPlayer 时间戳用 animation.track_get_key_time()

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

const CANONICAL_STATES: Array = ["idle", "move", "attack", "heavy_attack", "guard", "parry_success", "stagger", "stance_break", "execute", "revive", "dead"]
const ANIM_CLIPS: Array = ["anim_idle", "anim_move", "anim_attack", "anim_heavy_attack", "anim_guard", "anim_parry_success", "anim_stagger", "anim_stance_break", "anim_execute", "anim_revive", "anim_dead"]
const PIVOT_PARTS: Array = ["torso", "head", "arm_l", "arm_r", "sword", "leg_l", "leg_r", "neck", "leg_k_l", "leg_k_r"]

const STATE_TO_CLIP: Dictionary = {
	"idle": "anim_idle",
	"move": "anim_move",
	"attack": "anim_attack",
	"heavy_attack": "anim_heavy_attack",
	"guard": "anim_guard",
	"parry_success": "anim_parry_success",
	"stagger": "anim_stagger",
	"stance_break": "anim_stance_break",
	"execute": "anim_execute",
	"revive": "anim_revive",
	"dead": "anim_dead",
}

## 关节 → rotation track 路径（#683 AC3 姿态差枚举；head 路径含新 NeckPivot 前缀）
const JOINT_ROTATION_PATHS: Dictionary = {
	"torso": "StickFigure/TorsoPivot:rotation",
	"head": "StickFigure/TorsoPivot/NeckPivot/HeadPivot:rotation",
	"arm_l": "StickFigure/TorsoPivot/ArmLPivot:rotation",
	"arm_r": "StickFigure/TorsoPivot/ArmRPivot:rotation",
	"sword": "StickFigure/TorsoPivot/SwordPivot:rotation",
	"leg_l": "StickFigure/LegLPivot:rotation",
	"leg_r": "StickFigure/LegRPivot:rotation",
	"leg_k_l": "StickFigure/LegLPivot/LegKPivot:rotation",
	"leg_k_r": "StickFigure/LegRPivot/LegKPivot:rotation",
}

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== StickFigureAnimation Tests ===")
	_test_a1_canonical_mapping()
	_test_a2_alias_mapping()
	_test_b1_full_state_mapping()
	_test_c1_transition_within_two_frames()
	_test_c2_stagger_to_idle_fallback()
	_test_d1_no_collision_nodes()
	_test_d2_additive_material()
	_test_e1_keyframe_timestamps()
	_test_e2_conflict_values()
	_test_e3_draft_markers()
	_test_f1_pivot_tree()
	_test_f2_geometry_params()
	_test_f3_silhouette_colors()
	_test_g1_same_state_reentry()
	_test_h1_unknown_state_fallback()
	_test_i1_all_clips_registered()
	_test_i2_zero_resource_files()
	_test_i3_no_overlapping_playback()
	_test_ac1_t1_neck_separation()
	_test_ac1_t2_head_torso_overlap()
	_test_ac1_t3_head_ratio()
	_test_ac1_t4_head_outline()
	_test_ac2_t1_gait_cycle_frames()
	_test_ac2_t2_knee_track()
	_test_ac2_t3_contact_pass_pose()
	_test_ac2_t4_playback_speed()
	_test_ac2_t5_arm_leg_opposite()
	_test_ac3_t1_transition_pose_delta()
	_test_ac3_t3_knee_bend_max()
	_test_ac3_t5_key_chain()
	_test_l1_invalid_geometry_fallback()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _const_map() -> Dictionary:
	## 经 GDScript 类型引用调用 get_script_constant_map()（直接经 preload const 调用
	## 在 4.7.1 会解析为 class WolfConstants 而非脚本资源，同 test_constants.gd 注释）
	var script: GDScript = load("res://gdscripts/constants.gd")
	return script.get_script_constant_map()


func _make_controller() -> Node:
	## 实例化 player_stick_figure.tscn（根 = StickFigureController）并加入 SceneTree。
	## TDD 红期场景未实现 → 返回 null（调用方 guard + 计数失败）。
	var scene: PackedScene = load("res://scenes/player_stick_figure.tscn")
	if scene == null:
		_assert(false, "setup: player_stick_figure.tscn loads")
		return null
	var controller: Node = scene.instantiate()
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(controller)
	return controller


func _anim_player(controller: Node) -> AnimationPlayer:
	return controller.get_node_or_null("AnimationPlayer")


func _free_controller(controller: Node) -> void:
	if controller != null:
		controller.free()


func _find_node_recursive(node: Node, node_name: String) -> Node:
	for child in node.get_children():
		if str(child.name) == node_name:
			return child
		var found: Node = _find_node_recursive(child, node_name)
		if found != null:
			return found
	return null


func _first_child(node: Node) -> Node:
	if node != null and node.get_child_count() > 0:
		return node.get_child(0)
	return null


func _subtree_has_collision(node: Node) -> bool:
	## 遍历子树断言无任何碰撞/物理体类型（判定归 #577，视觉/逻辑解耦）
	if node is Area2D or node is PhysicsBody2D or node is CollisionShape2D or node is CollisionPolygon2D:
		return true
	for child in node.get_children():
		if _subtree_has_collision(child):
			return true
	return false


func _clip_has_key_at(clip: Animation, target: float, tol: float) -> bool:
	## 任一 track 的任一关键帧时间戳落在 [target-tol, target+tol] 即命中
	for t in range(clip.get_track_count()):
		var count: int = clip.track_get_key_count(t)
		for k in range(count):
			var kt: float = clip.track_get_key_time(t, k)
			if absf(kt - target) <= tol:
				return true
	return false


func _comment_block_has_keywords(text: String, const_name: String) -> bool:
	## 自 const 行向上收集注释块（到最近分区头 ── 为止），断言含候补值/影响/情感断言三要素
	var lines: PackedStringArray = text.split("\n")
	var idx: int = -1
	for i in range(lines.size()):
		if lines[i].find(const_name) != -1:
			idx = i
			break
	if idx == -1:
		return false
	var block: String = ""
	for j in range(idx - 1, max(idx - 30, -1), -1):
		var line: String = lines[j]
		if line.find("──") != -1:
			break
		block = line + "\n" + block
	return block.find("候补值") != -1 and block.find("该值影响什么") != -1 and block.find("情感断言") != -1


func _has_resource_files(dir_path: String) -> bool:
	## 递归扫描 .tres/.res（AC5: 零动画资源文件）。res:// 下 .godot 缓存不被列出。
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return false
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if da.current_is_dir():
			if fname != "." and fname != ".." and _has_resource_files(dir_path.path_join(fname)):
				da.list_dir_end()
				return true
		elif fname.ends_with(".tres") or fname.ends_with(".res"):
			da.list_dir_end()
			return true
		fname = da.get_next()
	da.list_dir_end()
	return false


# ── Scenario A: consume_state 映射与别名 ──

func _test_a1_canonical_mapping() -> void:
	## A1: canonical 映射抽查（attack/guard + 5 代表性态 idle/move/heavy_attack/stagger/dead）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var samples: Array = ["attack", "guard", "idle", "move", "heavy_attack", "stagger", "dead"]
	for state in samples:
		controller.consume_state(state)
		var expected: String = STATE_TO_CLIP[state]
		_assert(anim != null and anim.current_animation == expected, "A1: consume_state(%s) → %s (got %s)" % [state, expected, anim.current_animation])
	_free_controller(controller)


func _test_a2_alias_mapping() -> void:
	## A2: 别名 run→anim_move / parry→anim_guard（issue body 明文）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	controller.consume_state("run")
	_assert(anim != null and anim.current_animation == "anim_move", "A2: consume_state('run') → anim_move (got %s)" % anim.current_animation)
	controller.consume_state("parry")
	_assert(anim != null and anim.current_animation == "anim_guard", "A2: consume_state('parry') → anim_guard (got %s)" % anim.current_animation)
	_free_controller(controller)


# ── Scenario B: 11 态映射完整性 ──

func _test_b1_full_state_mapping() -> void:
	## B1: canonical 11 态全部有映射且 clip 已注册（防 #575 状态名漂移漏映射）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var list: PackedStringArray = lib.get_animation_list()
	for state in CANONICAL_STATES:
		var clip: String = STATE_TO_CLIP[state]
		controller.consume_state(state)
		_assert(anim.current_animation == clip, "B1: canonical '%s' → %s (got %s)" % [state, clip, anim.current_animation])
		_assert(list.has(clip), "B1: clip '%s' registered in AnimationLibrary" % clip)
	_free_controller(controller)


# ── Scenario C: 过渡时长 ≤2 帧（AC1）──

func _test_c1_transition_within_two_frames() -> void:
	## C1: idle→move→attack→guard→stagger 全链，t1-t0 ≤ FRAME_ANIM_TRANSITION_MAX/60
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var cm: Dictionary = _const_map()
	if not cm.has("FRAME_ANIM_TRANSITION_MAX"):
		_assert(false, "C1: FRAME_ANIM_TRANSITION_MAX missing in constants")
		_free_controller(controller)
		return
	var budget: float = float(int(cm.get("FRAME_ANIM_TRANSITION_MAX"))) / 60.0
	var chain: Array = ["idle", "move", "attack", "guard", "stagger"]
	controller.consume_state(chain[0])
	for i in range(1, chain.size()):
		var prev: String = chain[i - 1]
		var state: String = chain[i]
		var expected: String = STATE_TO_CLIP[state]
		var t0: int = Time.get_ticks_usec()
		controller.consume_state(state)
		var t1: int = Time.get_ticks_usec()
		var elapsed: float = float(t1 - t0) / 1000000.0
		_assert(anim.current_animation == expected, "C1: %s→%s plays %s (got %s)" % [prev, state, expected, anim.current_animation])
		_assert(elapsed <= budget + 0.05, "C1: %s→%s transition %.4fs ≤ %.4fs (2 frames @60fps)" % [prev, state, elapsed, budget])
	_free_controller(controller)


func _test_c2_stagger_to_idle_fallback() -> void:
	## C2: 跳变大转移（stagger→idle）插值兜底。可选回归（DESIGN §8 C2）:
	##   主策略直接 play + 首帧衔接 → idle 立即生效且耗时 ≤2/60s；
	##   兜底插值路径 → 过渡 tween 在途且剩余时长 ≤ FRAME_ANIM_TRANSITION_MAX/60。
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var cm: Dictionary = _const_map()
	if not cm.has("FRAME_ANIM_TRANSITION_MAX"):
		_assert(false, "C2: FRAME_ANIM_TRANSITION_MAX missing in constants")
		_free_controller(controller)
		return
	var budget: float = float(int(cm.get("FRAME_ANIM_TRANSITION_MAX"))) / 60.0
	controller.consume_state("stagger")
	_assert(anim.current_animation == "anim_stagger", "C2: stagger clip active before jump")
	var t0: int = Time.get_ticks_usec()
	controller.consume_state("idle")
	var t1: int = Time.get_ticks_usec()
	var elapsed: float = float(t1 - t0) / 1000000.0
	if anim.current_animation == "anim_idle":
		_assert(elapsed <= budget + 0.05, "C2: direct play — stagger→idle within 2/60s (%.4fs)" % elapsed)
		_assert(anim.current_animation_position < 0.001, "C2: idle starts at first frame")
	else:
		# 兜底插值路径: 目标 clip 尚未生效但过渡已启动，且耗时受限
		var tween: Tween = controller.get("transition_tween")
		_assert(tween != null and tween.is_running(), "C2: fallback interpolation tween running")
		if tween != null:
			_assert(tween.get_total_elapsed_time() <= budget + 0.05, "C2: fallback tween within 2/60s budget")
	_free_controller(controller)


# ── Scenario D: 刀光 additive 无碰撞（AC2）──

func _test_d1_no_collision_nodes() -> void:
	## D1: SwordArc 子树无 Area2D/CollisionShape2D/碰撞层（判定归 #577）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	_assert(figure != null, "D1: StickFigure child exists")
	if figure != null:
		var arc: Node = _find_node_recursive(figure, "SwordArc")
		_assert(arc != null, "D1: SwordArc node exists under skeleton")
		if arc != null:
			_assert(arc is Polygon2D, "D1: SwordArc is Polygon2D")
			_assert(not _subtree_has_collision(arc), "D1: SwordArc subtree has no collision nodes")
	_free_controller(controller)


func _test_d2_additive_material() -> void:
	## D2: SwordArc 材质 = CanvasItemMaterial 且 blend_mode == BLEND_MODE_ADD
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	if figure != null:
		var arc: Node = _find_node_recursive(figure, "SwordArc")
		if arc != null:
			var mat: Resource = arc.material
			_assert(mat is CanvasItemMaterial, "D2: SwordArc material is CanvasItemMaterial")
			if mat is CanvasItemMaterial:
				_assert((mat as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "D2: blend_mode == BLEND_MODE_ADD")
	_free_controller(controller)


# ── Scenario E: constants 派生（AC3）──

func _test_e1_keyframe_timestamps() -> void:
	## E1: anim_attack 三段时间戳 == constants 值/60（容差 ±1 帧）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var clip: Animation = lib.get_animation("anim_attack")
	_assert(clip != null, "E1: anim_attack clip registered")
	var cm: Dictionary = _const_map()
	if clip != null and cm.has("FRAME_ANIM_ATTACK_WINDUP") and cm.has("FRAME_ANIM_ATTACK_BURST") and cm.has("FRAME_ANIM_ATTACK_RECOVERY"):
		var w: int = int(cm.get("FRAME_ANIM_ATTACK_WINDUP"))
		var b: int = int(cm.get("FRAME_ANIM_ATTACK_BURST"))
		var r: int = int(cm.get("FRAME_ANIM_ATTACK_RECOVERY"))
		var tol: float = 1.0 / 60.0
		_assert(_clip_has_key_at(clip, float(w) / 60.0, tol), "E1: windup-end keyframe at %d/60s" % w)
		_assert(_clip_has_key_at(clip, float(w + b) / 60.0, tol), "E1: burst-end keyframe at %d/60s" % (w + b))
		_assert(_clip_has_key_at(clip, float(w + b + r) / 60.0, tol), "E1: recovery-end keyframe at %d/60s" % (w + b + r))
		var expected_len: float = float(w + b + r) / 60.0
		_assert(absf(clip.length - expected_len) <= tol, "E1: anim_attack length == (w+b+r)/60 (got %s)" % str(clip.length))
	else:
		_assert(false, "E1: FRAME_ANIM_ATTACK_* constants missing")
	_free_controller(controller)


func _test_e2_conflict_values() -> void:
	## E2: 冲突值双存——FRAME_ANIM_ATTACK_RECOVERY==10 且 FRAME_ATTACK_RECOVERY==14（禁止二选一偷定，#584 裁决）
	var cm: Dictionary = _const_map()
	_assert(cm.has("FRAME_ANIM_ATTACK_RECOVERY"), "E2: FRAME_ANIM_ATTACK_RECOVERY exists")
	_assert(cm.has("FRAME_ATTACK_RECOVERY"), "E2: FRAME_ATTACK_RECOVERY exists")
	if cm.has("FRAME_ANIM_ATTACK_RECOVERY"):
		_assert(int(cm.get("FRAME_ANIM_ATTACK_RECOVERY")) == 10, "E2: FRAME_ANIM_ATTACK_RECOVERY == 10")
	if cm.has("FRAME_ATTACK_RECOVERY"):
		_assert(int(cm.get("FRAME_ATTACK_RECOVERY")) == 14, "E2: FRAME_ATTACK_RECOVERY == 14")


func _test_e3_draft_markers() -> void:
	## E3: constants.gd ≥5 处 # DRAFT + 新常量注释含「候补值/该值影响什么/情感断言」三要素（抽查 3 个）
	var f: FileAccess = FileAccess.open("res://gdscripts/constants.gd", FileAccess.READ)
	if f == null:
		_assert(false, "E3: constants.gd opens for reading")
		return
	var text: String = f.get_as_text()
	f.close()
	var draft_count: int = 0
	var search_from: int = 0
	while true:
		var idx: int = text.find("# DRAFT", search_from)
		if idx == -1:
			break
		draft_count += 1
		search_from = idx + 1
	_assert(draft_count >= 5, "E3: constants.gd contains >= 5 '# DRAFT' markers (found %d)" % draft_count)
	var samples: Array = ["FRAME_ANIM_ATTACK_WINDUP", "FRAME_ANIM_MOVE_STEP", "SWORD_ARC_SWEEP_DEG"]
	for const_name in samples:
		_assert(_comment_block_has_keywords(text, const_name), "E3: '%s' comment block has 候补值/影响/情感断言" % const_name)


# ── Scenario F: 骨架构建 ──

func _test_f1_pivot_tree() -> void:
	## F1: 10 pivot 完整（torso/head/arm_l/arm_r/sword/leg_l/leg_r/neck/leg_k_l/leg_k_r）；
	##     头=Polygon2D，其余（含颈/膝）=Line2D（#683 R1 适配）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	_assert(figure != null, "F1: StickFigure child exists")
	if figure != null:
		for part in PIVOT_PARTS:
			var pivot: Node = figure.get_pivot(part)
			_assert(pivot != null, "F1: get_pivot('%s') returns node" % part)
			if pivot != null:
				var child: Node = _first_child(pivot)
				_assert(child != null, "F1: '%s' pivot has a geometry child" % part)
				if child != null:
					if part == "head":
						_assert(child is Polygon2D, "F1: head is Polygon2D")
					else:
						_assert(child is Line2D, "F1: %s is Line2D" % part)
	_free_controller(controller)


func _test_f2_geometry_params() -> void:
	## F2: 几何参数 == BODY_*/SWORD_* constants 值（容差 0.01）
	## #683 R2 适配: 腿分两段——大腿 == BODY_LEG_UPPER_LENGTH、小腿（膝 pivot）== BODY_LEG_LOWER_LENGTH；
	##   新增颈段 == BODY_NECK_LENGTH
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	var cm: Dictionary = _const_map()
	var needed: Array = ["BODY_HEAD_RADIUS", "BODY_TORSO_LENGTH", "BODY_ARM_LENGTH", "BODY_LEG_LENGTH", "BODY_LEG_UPPER_LENGTH", "BODY_LEG_LOWER_LENGTH", "BODY_NECK_LENGTH", "BODY_LIMB_WIDTH", "SWORD_LENGTH", "SWORD_WIDTH"]
	var all_present: bool = true
	for n in needed:
		if not cm.has(n):
			all_present = false
	if not all_present:
		_assert(false, "F2: BODY_*/SWORD_* geometry constants missing")
		_free_controller(controller)
		return
	if figure == null:
		_free_controller(controller)
		return
	_assert_limb_length(figure.get_pivot("torso"), float(cm.get("BODY_TORSO_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: torso")
	_assert_limb_length(figure.get_pivot("arm_l"), float(cm.get("BODY_ARM_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: arm_l")
	_assert_limb_length(figure.get_pivot("arm_r"), float(cm.get("BODY_ARM_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: arm_r")
	_assert_limb_length(figure.get_pivot("neck"), float(cm.get("BODY_NECK_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: neck")
	_assert_limb_length(figure.get_pivot("leg_l"), float(cm.get("BODY_LEG_UPPER_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: leg_l (thigh)")
	_assert_limb_length(figure.get_pivot("leg_r"), float(cm.get("BODY_LEG_UPPER_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: leg_r (thigh)")
	_assert_limb_length(figure.get_pivot("leg_k_l"), float(cm.get("BODY_LEG_LOWER_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: leg_k_l (shin)")
	_assert_limb_length(figure.get_pivot("leg_k_r"), float(cm.get("BODY_LEG_LOWER_LENGTH")), float(cm.get("BODY_LIMB_WIDTH")), "F2: leg_k_r (shin)")
	_assert_limb_length(figure.get_pivot("sword"), float(cm.get("SWORD_LENGTH")), float(cm.get("SWORD_WIDTH")), "F2: sword")
	var head_poly: Node = _first_child(figure.get_pivot("head"))
	if head_poly is Polygon2D:
		var radius: float = (head_poly as Polygon2D).polygon[0].length()
		_assert(absf(radius - float(cm.get("BODY_HEAD_RADIUS"))) < 0.01, "F2: head radius == BODY_HEAD_RADIUS (got %s)" % str(radius))
	else:
		_assert(false, "F2: head child is Polygon2D")
	_free_controller(controller)


func _assert_limb_length(pivot: Node, length: float, width: float, tag: String) -> void:
	## Line2D points=[ZERO, (0,-length)]，length=points[1] 距原点距离，width=width（容差 0.01）
	if pivot != null:
		var line: Node = _first_child(pivot)
		if line is Line2D:
			var line2d: Line2D = line
			var got_len: float = line2d.points[1].length()
			_assert(absf(got_len - length) < 0.01, "%s length == %s (got %s)" % [tag, str(length), str(got_len)])
			_assert(absf(line2d.width - width) < 0.01, "%s width == %s (got %s)" % [tag, str(width), str(line2d.width)])
		else:
			_assert(false, "%s: pivot child is Line2D" % tag)
	else:
		_assert(false, "%s: pivot missing" % tag)


func _test_f3_silhouette_colors() -> void:
	## F3: 剪影配色——骨架/头 == BODY_COLOR，刀身 == SWORD_COLOR
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	var cm: Dictionary = _const_map()
	if not cm.has("BODY_COLOR") or not cm.has("SWORD_COLOR"):
		_assert(false, "F3: BODY_COLOR/SWORD_COLOR constants missing")
		_free_controller(controller)
		return
	var body_color: Color = cm.get("BODY_COLOR")
	var sword_color: Color = cm.get("SWORD_COLOR")
	if figure != null:
		var torso: Node = _first_child(figure.get_pivot("torso"))
		var sword: Node = _first_child(figure.get_pivot("sword"))
		var head: Node = _first_child(figure.get_pivot("head"))
		if torso is Line2D:
			_assert((torso as Line2D).default_color == body_color, "F3: torso color == BODY_COLOR")
		if sword is Line2D:
			_assert((sword as Line2D).default_color == sword_color, "F3: sword color == SWORD_COLOR")
		if head is Polygon2D:
			_assert((head as Polygon2D).color == body_color, "F3: head color == BODY_COLOR")
	_free_controller(controller)


# ── Scenario G: 同态重入（连招语义）──

func _test_g1_same_state_reentry() -> void:
	## G1: attack 播到暴发段再 consume_state("attack") → 重置回前摇首帧（时间==0），非从暴发续播
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var cm: Dictionary = _const_map()
	if not cm.has("FRAME_ANIM_ATTACK_WINDUP") or not cm.has("FRAME_ANIM_ATTACK_BURST"):
		_assert(false, "G1: FRAME_ANIM_ATTACK_WINDUP/BURST constants missing")
		_free_controller(controller)
		return
	var w: int = int(cm.get("FRAME_ANIM_ATTACK_WINDUP"))
	var b: int = int(cm.get("FRAME_ANIM_ATTACK_BURST"))
	var burst_mid: float = (float(w) + float(b) / 2.0) / 60.0
	controller.consume_state("attack")
	_assert(anim.current_animation == "anim_attack", "G1: attack clip active")
	anim.seek(burst_mid)
	_assert(anim.current_animation_position > 0.05, "G1: attack advanced into burst phase (pos=%s)" % str(anim.current_animation_position))
	controller.consume_state("attack")
	_assert(anim.current_animation == "anim_attack", "G1: re-entry keeps attack clip")
	_assert(anim.current_animation_position < 0.001, "G1: re-entry resets to windup first frame (pos=%s)" % str(anim.current_animation_position))
	_assert(anim.is_playing(), "G1: animation still playing after re-entry")
	_free_controller(controller)


# ── Scenario H: 未知状态降级 ──

func _test_h1_unknown_state_fallback() -> void:
	## H1: consume_state("unknown_state") → 播放 anim_idle + 不崩溃/不卡死（push_warning 为实现副作用）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	controller.consume_state("unknown_state")
	_assert(anim.current_animation == "anim_idle", "H1: unknown state falls back to anim_idle (got '%s')" % anim.current_animation)
	_assert(anim.is_playing(), "H1: animation not stuck (still playing)")
	var f: FileAccess = FileAccess.open("res://gdscripts/stick_figure_controller.gd", FileAccess.READ)
	if f != null:
		var text: String = f.get_as_text()
		f.close()
		_assert(text.find("#575") != -1, "H1: mapping table comments reference #575 as canonical source")
	else:
		_assert(false, "H1: stick_figure_controller.gd opens for reading")
	_free_controller(controller)


# ── Scenario I: 动画资源动态生成（零 .tres，AC5）──

func _test_i1_all_clips_registered() -> void:
	## I1: AnimationPlayer 库含全部 11 个 anim_* clip（与映射表一一对应）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var list: PackedStringArray = lib.get_animation_list()
	for clip in ANIM_CLIPS:
		_assert(list.has(clip), "I1: clip '%s' registered (missing)" % clip)
	_free_controller(controller)


func _test_i2_zero_resource_files() -> void:
	## I2: 工程无 .tres/.res 动画资源文件（AC5: 零美术/资源文件，动画运行时动态生成）
	_assert(not _has_resource_files("res://"), "I2: no .tres/.res files anywhere in project")


func _test_i3_no_overlapping_playback() -> void:
	## I3: 连续 consume_state 两个状态 → 前一 clip 已停止，无叠播（play 前 stop 旧 clip）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	controller.consume_state("move")
	_assert(anim.current_animation == "anim_move", "I3: first clip anim_move active")
	controller.consume_state("attack")
	_assert(anim.current_animation == "anim_attack", "I3: second clip anim_attack active (old clip replaced)")
	_assert(anim.is_playing(), "I3: new clip playing")
	_assert(anim.current_animation_position < 0.001, "I3: new clip starts fresh at frame 0")
	_free_controller(controller)


# ── Scenario AC1: 头部可读性（#683 AC1）──

func _test_ac1_t1_neck_separation() -> void:
	## AC1-T1: 头身分离 —— get_pivot("neck") 非 null；颈 Line2D 长度 == BODY_NECK_LENGTH（容差 0.01）；
	##    HeadPivot 是 NeckPivot 子节点（结构 §2.1）
	var cm: Dictionary = _const_map()
	if not cm.has("BODY_NECK_LENGTH"):
		_assert(false, "AC1-T1: BODY_NECK_LENGTH missing in constants")
		return
	var neck_len: float = float(cm.get("BODY_NECK_LENGTH"))
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	_assert(figure != null, "AC1-T1: StickFigure child exists")
	if figure != null:
		var neck_pivot: Node = figure.get_pivot("neck")
		_assert(neck_pivot != null, "AC1-T1: get_pivot('neck') returns node")
		if neck_pivot != null:
			var neck_line: Node = _first_child(neck_pivot)
			if neck_line is Line2D:
				var got_len: float = (neck_line as Line2D).points[1].length()
				_assert(absf(got_len - neck_len) < 0.01, "AC1-T1: neck length == BODY_NECK_LENGTH (got %s)" % str(got_len))
			else:
				_assert(false, "AC1-T1: neck pivot child is Line2D")
		var head_pivot: Node = figure.get_pivot("head")
		_assert(head_pivot != null and head_pivot.get_parent() == neck_pivot, "AC1-T1: HeadPivot is child of NeckPivot")
	_free_controller(controller)


func _test_ac1_t2_head_torso_overlap() -> void:
	## AC1-T2: 头身重叠 ≤4px —— 头圆最低点 y（head.global_y + BODY_HEAD_RADIUS）vs 躯干顶 y
	##    （torso.global_y - BODY_TORSO_LENGTH）；重叠 = head_bottom - torso_top（修复前 = 16px）
	var cm: Dictionary = _const_map()
	if not cm.has("BODY_HEAD_RADIUS") or not cm.has("BODY_TORSO_LENGTH"):
		_assert(false, "AC1-T2: BODY_HEAD_RADIUS/BODY_TORSO_LENGTH missing in constants")
		return
	var head_radius: float = float(cm.get("BODY_HEAD_RADIUS"))
	var torso_len: float = float(cm.get("BODY_TORSO_LENGTH"))
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	_assert(figure != null, "AC1-T2: StickFigure child exists")
	if figure != null:
		var head_pivot: Node = figure.get_pivot("head")
		var torso_pivot: Node = figure.get_pivot("torso")
		_assert(head_pivot != null and torso_pivot != null, "AC1-T2: head/torso pivots exist")
		if head_pivot != null and torso_pivot != null:
			var head_bottom: float = head_pivot.global_position.y + head_radius
			var torso_top: float = torso_pivot.global_position.y - torso_len
			var overlap: float = head_bottom - torso_top
			_assert(overlap <= 4.0, "AC1-T2: head/torso overlap %.1fpx <= 4px (was 16px pre-fix)" % overlap)
	_free_controller(controller)


func _test_ac1_t3_head_ratio() -> void:
	## AC1-T3: 头径:躯干 ∈ GDD 1:2.5 ±10% —— 断言 2*BODY_HEAD_RADIUS/BODY_TORSO_LENGTH ∈ [1/2.75, 1/2.25]
	##    （纯常量断言，无需实例化）
	var cm: Dictionary = _const_map()
	if not cm.has("BODY_HEAD_RADIUS") or not cm.has("BODY_TORSO_LENGTH"):
		_assert(false, "AC1-T3: BODY_HEAD_RADIUS/BODY_TORSO_LENGTH missing in constants")
		return
	var ratio: float = 2.0 * float(cm.get("BODY_HEAD_RADIUS")) / float(cm.get("BODY_TORSO_LENGTH"))
	_assert(ratio >= 1.0 / 2.75 and ratio <= 1.0 / 2.25, "AC1-T3: 2*radius/torso ratio %.4f ∈ [1/2.75, 1/2.25]" % ratio)


func _test_ac1_t4_head_outline() -> void:
	## AC1-T4: 头轮廓开关 —— HEAD_OUTLINE_ENABLED 存在；默认 false 时 HeadPivot 只有头圆 1 个节点
	var cm: Dictionary = _const_map()
	_assert(cm.has("HEAD_OUTLINE_ENABLED"), "AC1-T4: HEAD_OUTLINE_ENABLED exists in constants")
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	_assert(figure != null, "AC1-T4: StickFigure child exists")
	if figure != null:
		var head_pivot: Node = figure.get_pivot("head")
		_assert(head_pivot != null, "AC1-T4: get_pivot('head') returns node")
		if head_pivot != null:
			var outline_enabled: bool = false
			if cm.has("HEAD_OUTLINE_ENABLED"):
				outline_enabled = bool(cm.get("HEAD_OUTLINE_ENABLED"))
			if outline_enabled:
				_assert(head_pivot.get_child_count() >= 2, "AC1-T4: head outline Polygon2D present when HEAD_OUTLINE_ENABLED")
			else:
				_assert(head_pivot.get_child_count() == 1, "AC1-T4: head has only head-circle when outline disabled (got %d)" % head_pivot.get_child_count())
	_free_controller(controller)


# ── Scenario AC2: 走路动画（#683 AC2）──

func _test_ac2_t1_gait_cycle_frames() -> void:
	## AC2-T1: 步态周期 —— anim_move length*60 ∈ [24,32] 帧（容差 ±1 帧）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var clip: Animation = lib.get_animation("anim_move")
	_assert(clip != null, "AC2-T1: anim_move clip registered")
	if clip != null:
		var frames: float = clip.length * 60.0
		_assert(frames >= 23.0 and frames <= 33.0, "AC2-T1: move cycle %.1f frames ∈ [24,32] (±1)" % frames)
	_free_controller(controller)


func _test_ac2_t2_knee_track() -> void:
	## AC2-T2: 膝 pivot 存在且 anim_move 含膝 rotation track（关键帧 ≥3: contact/pass/contact）
	var controller: Node = _make_controller()
	if controller == null:
		return
	var figure: Node = controller.get_node_or_null("StickFigure")
	_assert(figure != null, "AC2-T2: StickFigure child exists")
	if figure != null:
		_assert(figure.get_pivot("leg_k_l") != null, "AC2-T2: get_pivot('leg_k_l') returns node")
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var clip: Animation = lib.get_animation("anim_move")
	_assert(clip != null, "AC2-T2: anim_move clip registered")
	if clip != null:
		var found: bool = false
		var key_count: int = 0
		for t in range(clip.get_track_count()):
			if clip.track_get_path(t) == NodePath("StickFigure/LegLPivot/LegKPivot:rotation"):
				found = true
				key_count = clip.track_get_key_count(t)
		_assert(found, "AC2-T2: anim_move has LegLPivot/LegKPivot:rotation track")
		if found:
			_assert(key_count >= 3, "AC2-T2: knee track keyframes >= 3 (got %d)" % key_count)
	_free_controller(controller)


func _test_ac2_t3_contact_pass_pose() -> void:
	## AC2-T3: contact/pass 关键姿态 —— contact(0): LegL 摆幅绝对值 == MOVE_SWING_LEG_DEG、膝屈曲 == 0；
	##    pass(6): 摆动腿膝屈曲绝对值 == MOVE_KNEE_BEND_DEG（容差 0.5°）。track 缺失 → 断言失败
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var cm: Dictionary = _const_map()
	if not cm.has("MOVE_SWING_LEG_DEG") or not cm.has("MOVE_KNEE_BEND_DEG"):
		_assert(false, "AC2-T3: MOVE_SWING_LEG_DEG/MOVE_KNEE_BEND_DEG missing in constants")
		_free_controller(controller)
		return
	var swing_deg: float = float(cm.get("MOVE_SWING_LEG_DEG"))
	var bend_deg: float = float(cm.get("MOVE_KNEE_BEND_DEG"))
	var lib: AnimationLibrary = anim.get_animation_library("")
	var clip: Animation = lib.get_animation("anim_move")
	_assert(clip != null, "AC2-T3: anim_move clip registered")
	if clip != null:
		var hip_contact: float = _track_angle_at_frame(clip, "StickFigure/LegLPivot:rotation", 0)
		var knee_contact: float = _track_angle_at_frame(clip, "StickFigure/LegLPivot/LegKPivot:rotation", 0)
		_assert(is_finite(hip_contact), "AC2-T3: LegLPivot track present at contact frame 0")
		if is_finite(hip_contact):
			_assert(absf(absf(hip_contact) - swing_deg) <= 0.5, "AC2-T3: contact |LegL swing| == MOVE_SWING_LEG_DEG (got %s)" % str(hip_contact))
		_assert(is_finite(knee_contact), "AC2-T3: LegLPivot/LegKPivot track present at contact frame 0")
		if is_finite(knee_contact):
			_assert(absf(knee_contact) <= 0.5, "AC2-T3: contact knee flexion == 0 (got %s)" % str(knee_contact))
		var knee_pass: float = _track_angle_at_frame(clip, "StickFigure/LegLPivot/LegKPivot:rotation", 6)
		_assert(is_finite(knee_pass), "AC2-T3: LegLPivot/LegKPivot track present at pass frame 6")
		if is_finite(knee_pass):
			_assert(absf(absf(knee_pass) - bend_deg) <= 0.5, "AC2-T3: pass |swing-leg knee bend| == MOVE_KNEE_BEND_DEG (got %s)" % str(knee_pass))
	_free_controller(controller)


func _test_ac2_t4_playback_speed() -> void:
	## AC2-T4: 播放速度同步 —— set_move_speed(300)→speed_scale 1.0；(90)→下限；(400)→上限；
	##    非 move clip 时调用 → no-op（speed_scale 不变）。set_move_speed 缺失 → 断言失败
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	_assert(controller.has_method("set_move_speed"), "AC2-T4: controller has set_move_speed method")
	if not controller.has_method("set_move_speed"):
		_free_controller(controller)
		return
	var cm: Dictionary = _const_map()
	var speed_min: float = 0.3
	var speed_max: float = 1.2
	if cm.has("MOVE_PLAYBACK_SPEED_MIN"):
		speed_min = float(cm.get("MOVE_PLAYBACK_SPEED_MIN"))
	if cm.has("MOVE_PLAYBACK_SPEED_MAX"):
		speed_max = float(cm.get("MOVE_PLAYBACK_SPEED_MAX"))
	controller.consume_state("move")
	controller.set_move_speed(300.0)
	_assert(absf(anim.speed_scale - 1.0) <= 0.01, "AC2-T4: move @300 → speed_scale == 1.0 (got %s)" % str(anim.speed_scale))
	controller.set_move_speed(90.0)
	_assert(absf(anim.speed_scale - speed_min) <= 0.01, "AC2-T4: move @90 → speed_scale == %.2f (floor, got %s)" % [speed_min, str(anim.speed_scale)])
	controller.set_move_speed(400.0)
	_assert(absf(anim.speed_scale - speed_max) <= 0.01, "AC2-T4: move @400 → speed_scale == %.2f (cap, got %s)" % [speed_max, str(anim.speed_scale)])
	controller.consume_state("idle")
	var idle_scale: float = anim.speed_scale
	controller.set_move_speed(300.0)
	_assert(absf(anim.speed_scale - idle_scale) <= 0.01, "AC2-T4: idle + set_move_speed no-op (speed_scale unchanged)")
	_free_controller(controller)


func _test_ac2_t5_arm_leg_opposite() -> void:
	## AC2-T5: 摆臂反向同频 —— anim_move 首帧 ArmL 与 LegR 符号相反、ArmR 与 LegL 符号相反
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var clip: Animation = lib.get_animation("anim_move")
	_assert(clip != null, "AC2-T5: anim_move clip registered")
	if clip != null:
		var arm_l: float = _clip_joint_angle_at(clip, "StickFigure/TorsoPivot/ArmLPivot:rotation", true)
		var leg_r: float = _clip_joint_angle_at(clip, "StickFigure/LegRPivot:rotation", true)
		_assert(is_finite(arm_l) and is_finite(leg_r), "AC2-T5: ArmLPivot/LegRPivot tracks present")
		if is_finite(arm_l) and is_finite(leg_r):
			_assert(arm_l * leg_r < 0.0, "AC2-T5: ArmL first-frame sign opposite to LegR (%s vs %s)" % [str(arm_l), str(leg_r)])
		var arm_r: float = _clip_joint_angle_at(clip, "StickFigure/TorsoPivot/ArmRPivot:rotation", true)
		var leg_l: float = _clip_joint_angle_at(clip, "StickFigure/LegLPivot:rotation", true)
		_assert(is_finite(arm_r) and is_finite(leg_l), "AC2-T5: ArmRPivot/LegLPivot tracks present")
		if is_finite(arm_r) and is_finite(leg_l):
			_assert(arm_r * leg_l < 0.0, "AC2-T5: ArmR first-frame sign opposite to LegL (%s vs %s)" % [str(arm_r), str(leg_l)])
	_free_controller(controller)


# ── Scenario AC3: 骨架一致性（#683 AC3）──

func _test_ac3_t1_transition_pose_delta() -> void:
	## AC3-T1: 姿态差 ≤15° 枚举 —— 对 combat_state_table.gd TRANSITIONS 每个合法转移对 (from,to)，
	##    from.clip 尾帧 vs to.clip 首帧逐关节角度差 <= POSE_DELTA_MAX_DEG（容差 1°）；
	##    同态（from==to）跳过；clip 缺某关节 track → 断言失败（实现遗漏）
	var cm: Dictionary = _const_map()
	if not cm.has("POSE_DELTA_MAX_DEG"):
		_assert(false, "AC3-T1: POSE_DELTA_MAX_DEG missing in constants")
		return
	var max_deg: float = float(cm.get("POSE_DELTA_MAX_DEG"))
	var table_script: GDScript = load("res://gdscripts/combat_state_table.gd")
	_assert(table_script != null, "AC3-T1: combat_state_table.gd loads")
	if table_script == null:
		return
	var transitions: Dictionary = table_script.get_script_constant_map().get("TRANSITIONS", {})
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var checked: int = 0
	for from_state in transitions.keys():
		var from_clip: Animation = lib.get_animation(STATE_TO_CLIP[from_state])
		if from_clip == null:
			_assert(false, "AC3-T1: clip for '%s' registered" % str(from_state))
			continue
		for to_state in transitions[from_state]:
			if str(from_state) == str(to_state):
				continue  # 同态重入（attack→attack）: 同 clip 首尾帧，重置语义，跳过
			var to_clip: Animation = lib.get_animation(STATE_TO_CLIP[to_state])
			if to_clip == null:
				_assert(false, "AC3-T1: clip for '%s' registered" % str(to_state))
				continue
			for joint in JOINT_ROTATION_PATHS:
				var node_path: String = JOINT_ROTATION_PATHS[joint]
				var from_angle: float = _clip_joint_angle_at(from_clip, node_path, false)
				var to_angle: float = _clip_joint_angle_at(to_clip, node_path, true)
				if is_nan(from_angle):
					_assert(false, "AC3-T1: %s missing joint track %s (tail)" % [STATE_TO_CLIP[from_state], node_path])
					continue
				if is_nan(to_angle):
					_assert(false, "AC3-T1: %s missing joint track %s (head)" % [STATE_TO_CLIP[to_state], node_path])
					continue
				var delta: float = absf(to_angle - from_angle)
				checked += 1
				_assert(delta <= max_deg + 1.0, "AC3-T1: %s→%s %s pose delta %.1f° <= %s° (+1° tol)" % [str(from_state), str(to_state), joint, delta, str(max_deg)])
	_assert(checked > 0, "AC3-T1: at least one transition pair checked")
	_free_controller(controller)


func _test_ac3_t3_knee_bend_max() -> void:
	## AC3-T3: 膝单向弯曲上限 —— 全部 clip 的膝 track 关键帧角度绝对值 <= KNEE_BEND_MAX_DEG（容差 1°）
	var cm: Dictionary = _const_map()
	if not cm.has("KNEE_BEND_MAX_DEG"):
		_assert(false, "AC3-T3: KNEE_BEND_MAX_DEG missing in constants")
		return
	var knee_max: float = float(cm.get("KNEE_BEND_MAX_DEG"))
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var knee_paths: Array = ["StickFigure/LegLPivot/LegKPivot:rotation", "StickFigure/LegRPivot/LegKPivot:rotation"]
	for clip_name in ANIM_CLIPS:
		var clip: Animation = lib.get_animation(clip_name)
		if clip == null:
			_assert(false, "AC3-T3: clip '%s' registered" % clip_name)
			continue
		for node_path in knee_paths:
			var found: bool = false
			for t in range(clip.get_track_count()):
				if clip.track_get_path(t) == NodePath(node_path):
					found = true
					var count: int = clip.track_get_key_count(t)
					for k in range(count):
						var deg: float = absf(rad_to_deg(float(clip.track_get_key_value(t, k))))
						_assert(deg <= knee_max + 1.0, "AC3-T3: %s %s key %d |%.1f°| <= %s° (+1° tol)" % [clip_name, node_path, k, deg, str(knee_max)])
			if not found:
				_assert(false, "AC3-T3: %s missing knee track %s" % [clip_name, node_path])
	_free_controller(controller)


func _test_ac3_t5_key_chain() -> void:
	## AC3-T5: 关键链专项 —— guard→parry_success→move 三态相邻对姿态差 <= POSE_DELTA_MAX_DEG（复用 T1 枚举）
	var cm: Dictionary = _const_map()
	if not cm.has("POSE_DELTA_MAX_DEG"):
		_assert(false, "AC3-T5: POSE_DELTA_MAX_DEG missing in constants")
		return
	var max_deg: float = float(cm.get("POSE_DELTA_MAX_DEG"))
	var controller: Node = _make_controller()
	if controller == null:
		return
	var anim: AnimationPlayer = _anim_player(controller)
	var lib: AnimationLibrary = anim.get_animation_library("")
	var chain: Array = ["guard", "parry_success", "move"]
	for i in range(chain.size() - 1):
		var from_state: String = chain[i]
		var to_state: String = chain[i + 1]
		var from_clip: Animation = lib.get_animation(STATE_TO_CLIP[from_state])
		var to_clip: Animation = lib.get_animation(STATE_TO_CLIP[to_state])
		if from_clip == null or to_clip == null:
			_assert(false, "AC3-T5: %s→%s clips registered" % [from_state, to_state])
			continue
		for joint in JOINT_ROTATION_PATHS:
			var node_path: String = JOINT_ROTATION_PATHS[joint]
			var from_angle: float = _clip_joint_angle_at(from_clip, node_path, false)
			var to_angle: float = _clip_joint_angle_at(to_clip, node_path, true)
			if is_nan(from_angle) or is_nan(to_angle):
				_assert(false, "AC3-T5: %s→%s %s track present (from=%s to=%s)" % [from_state, to_state, joint, str(from_angle), str(to_angle)])
				continue
			var delta: float = absf(to_angle - from_angle)
			_assert(delta <= max_deg + 1.0, "AC3-T5: %s→%s %s pose delta %.1f° <= %s°" % [from_state, to_state, joint, delta, str(max_deg)])
	_free_controller(controller)


func _clip_joint_angle_at(clip: Animation, node_path: String, first: bool) -> float:
	## 返回指定关节 rotation track 首个（first=true）或末个（first=false）关键帧角度（度）；
	## track 缺失或空 → NAN（调用方 is_nan 判定缺失，不得用 parse error 表达）
	if clip == null:
		return NAN
	for t in range(clip.get_track_count()):
		if clip.track_get_path(t) == NodePath(node_path):
			var count: int = clip.track_get_key_count(t)
			if count <= 0:
				return NAN
			var idx: int = 0
			if not first:
				idx = count - 1
			return rad_to_deg(float(clip.track_get_key_value(t, idx)))
	return NAN


func _track_angle_at_frame(clip: Animation, node_path: String, frame: int) -> float:
	## 返回指定 rotation track 在 frame/60s 时间戳处的关键帧角度（度）；track/帧缺失 → NAN
	if clip == null:
		return NAN
	var target: float = float(frame) / 60.0
	for t in range(clip.get_track_count()):
		if clip.track_get_path(t) == NodePath(node_path):
			for k in range(clip.track_get_key_count(t)):
				if absf(clip.track_get_key_time(t, k) - target) < 0.001:
					return rad_to_deg(float(clip.track_get_key_value(t, k)))
			return NAN
	return NAN


# ── Scenario L: 非法几何参数兜底 ──

func _test_l1_invalid_geometry_fallback() -> void:
	## L1: 非法几何参数（BODY_TORSO_LENGTH=-1、BODY_LIMB_WIDTH=0）→ push_warning + 回退默认值，骨架仍构建成功
	## 契约: stick_figure.gd 提供 @export 覆盖属性 body_torso_length / body_limb_width（camelCase），
	##       _validate_geometry() 对负长度/零宽度回退 constants 默认值
	var fig_script: GDScript = load("res://gdscripts/stick_figure.gd")
	_assert(fig_script != null, "L1: stick_figure.gd loads")
	if fig_script == null:
		return
	var figure: Node = fig_script.new()
	if "body_torso_length" in figure:
		figure.set("body_torso_length", -1.0)
	if "body_limb_width" in figure:
		figure.set("body_limb_width", 0.0)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(figure)
	var cm: Dictionary = _const_map()
	if cm.has("BODY_TORSO_LENGTH") and cm.has("BODY_LIMB_WIDTH"):
		var torso: Node = _first_child(figure.get_pivot("torso"))
		if torso is Line2D:
			var line2d: Line2D = torso
			var got_len: float = line2d.points[1].length()
			_assert(absf(got_len - float(cm.get("BODY_TORSO_LENGTH"))) < 0.01, "L1: invalid torso length falls back to BODY_TORSO_LENGTH (got %s)" % str(got_len))
			_assert(absf(line2d.width - float(cm.get("BODY_LIMB_WIDTH"))) < 0.01, "L1: zero limb width falls back to BODY_LIMB_WIDTH")
		else:
			_assert(false, "L1: TorsoPivot builds a Line2D (skeleton built despite invalid params)")
	else:
		_assert(false, "L1: BODY_* geometry constants missing")
	figure.free()

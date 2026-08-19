extends Object
## Test suite for atmosphere layer (#582) — snow night ambience: snow curtain
## three-layer particles, moonlight tint, ink wash overlay, and blood vignette.
## Runs under godot --headless --script via run_tests.gd.
## Test-first: atmosphere scene/scripts are not landed yet, so scene-based
## assertions fail until the implement PR lands.
##
## NOTE: class_name may not resolve in --script mode, so the constants script is
## accessed via preload and its constants read through the loaded resource.
## Scene instances are added to the SceneTree root (via Engine.get_main_loop())
## to trigger _ready; every instantiation test queue_free()s its instance.

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Atmosphere Tests ===")
	_test_a1_constants_exist()
	_test_a2_draft_markers()
	_test_a3_atmosphere_values()
	_test_b1_particle_structure()
	_test_b2_particle_scale()
	_test_b3_no_amount_override()
	_test_b4_emitting_state()
	_test_c1_moonlight()
	_test_c2_moonlight_convert_comment()
	_test_c3_moonlight_covers_visible_layers()
	_test_d1_ink_shader_range()
	_test_d2_ink_wash_rect()
	_test_e1_blood_vignette_standby()
	_test_e2_blood_trigger_and_convert()
	_test_e3_blood_idempotent()
	_test_e4_blood_same_path()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


# ── shared helpers ──

func _scene_tree() -> SceneTree:
	var main: MainLoop = Engine.get_main_loop()
	return main as SceneTree


func _instantiate_scene() -> Node:
	var scene: PackedScene = load("res://scenes/atmosphere/atmosphere_layer.tscn")
	if scene == null:
		return null
	var inst: Node = scene.instantiate()
	var tree: SceneTree = _scene_tree()
	if tree != null and tree.root != null:
		tree.root.add_child(inst)
	return inst


func _particle_layers(root: Node) -> Dictionary:
	var layers: Dictionary = {}
	var nodes: Array[Node] = root.find_children("*", "GPUParticles2D", true, false)
	for p: Node in nodes:
		var parent: Node = p.get_parent()
		var parallax: Parallax2D = parent as Parallax2D
		if parallax == null:
			continue
		layers[parallax.scroll_scale] = p
	return layers


func _sorted_scales(layers: Dictionary) -> Array:
	var scales: Array = layers.keys()
	scales.sort()
	return scales


func _particle_amounts(layers: Dictionary) -> Array:
	var scales: Array = _sorted_scales(layers)
	var amounts: Array = []
	for s in scales:
		var gp: GPUParticles2D = layers[s] as GPUParticles2D
		if gp == null:
			amounts.append(-1)
		else:
			amounts.append(gp.amount)
	return amounts


func _visual_alpha(node: Node) -> float:
	var val: Variant = node.call("get_visual_alpha")
	if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
		return float(val)
	return -1.0


func _const_map() -> Dictionary:
	var script: GDScript = load("res://gdscripts/constants.gd")
	return script.get_script_constant_map()


# ── Scenario A: constants ──

func _test_a1_constants_exist() -> void:
	var consts: Dictionary = _const_map()
	var names: Array = [
		"SNOW_PARTICLES_FAR", "SNOW_PARTICLES_MID", "SNOW_PARTICLES_NEAR",
		"SNOW_PARALLAX_FAR", "SNOW_PARALLAX_MID", "SNOW_PARALLAX_NEAR",
		"SNOW_SCALE_FAR", "SNOW_SCALE_NEAR",
		"SNOW_VELOCITY_MIN", "SNOW_VELOCITY_MAX",
		"SNOW_ALPHA_MIN", "SNOW_ALPHA_MAX",
		"SNOW_WIND_DEFAULT",
		"MOONLIGHT_COLOR_TARGET", "MOONLIGHT_COLOR_APPLIED", "MOONLIGHT_BRIGHTNESS",
		"INK_EDGE_ALPHA_MAX", "INK_COLOR", "INK_INNER_RADIUS", "INK_SOFTNESS", "INK_NOISE_AMOUNT",
		"BLOOD_VIGNETTE_ALPHA_MAX", "BLOOD_VIGNETTE_FADE_SECONDS", "BLOOD_VIGNETTE_LAYER",
	]
	for name: String in names:
		_assert(consts.has(name), "A1: constant %s exists (雪夜氛围)" % name)


func _test_a2_draft_markers() -> void:
	var f: FileAccess = FileAccess.open("res://gdscripts/constants.gd", FileAccess.READ)
	if f == null:
		_assert(false, "A2: constants.gd opens for reading")
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
	_assert(draft_count >= 20, "A2: constants.gd contains >= 20 '# DRAFT' markers (found %d)" % draft_count)
	_assert(text.find("待 #582 用户裁决") != -1, "A2: constants.gd contains '待 #582 用户裁决'")
	_assert(text.find("# 定稿") == -1, "A2: constants.gd does NOT contain '# 定稿' (no stealth finalization)")


func _test_a3_atmosphere_values() -> void:
	var consts: Dictionary = _const_map()
	var edge_alpha: float = float(consts.get("INK_EDGE_ALPHA_MAX", 0.0))
	_assert(edge_alpha <= 0.3, "A3: INK_EDGE_ALPHA_MAX <= 0.3 (got %s)" % str(edge_alpha))
	var v_alpha: float = float(consts.get("BLOOD_VIGNETTE_ALPHA_MAX", 0.0))
	_assert(is_equal_approx(v_alpha, 0.35), "A3: BLOOD_VIGNETTE_ALPHA_MAX == 0.35 (got %s)" % str(v_alpha))
	var v_fade: float = float(consts.get("BLOOD_VIGNETTE_FADE_SECONDS", 0.0))
	_assert(is_equal_approx(v_fade, 0.5), "A3: BLOOD_VIGNETTE_FADE_SECONDS == 0.5 (got %s)" % str(v_fade))
	var p_far: int = int(consts.get("SNOW_PARTICLES_FAR", 0))
	var p_mid: int = int(consts.get("SNOW_PARTICLES_MID", 0))
	var p_near: int = int(consts.get("SNOW_PARTICLES_NEAR", 0))
	var total: int = p_far + p_mid + p_near
	_assert(total == 200, "A3: SNOW_PARTICLES far+mid+near == 200 (got %d)" % total)


# ── Scenario B: snow curtain ──

func _test_b1_particle_structure() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "B1: atmosphere_layer.tscn loads and instantiates")
		return
	var layers: Dictionary = _particle_layers(inst)
	_assert(layers.size() == 3, "B1: exactly 3 GPUParticles2D layers (found %d)" % layers.size())
	var amounts: Array = _particle_amounts(layers)
	var total: int = 0
	for a in amounts:
		total += int(a)
	_assert(total >= 180 and total <= 220, "B1: total particle amount in [180, 220] (got %d)" % total)
	_assert(amounts == [60, 60, 80], "B1: amounts by layer (far,mid,near) == [60, 60, 80] (got %s)" % str(amounts))
	var scales: Array = _sorted_scales(layers)
	var scale_ok: bool = scales.size() == 3
	if scale_ok:
		scale_ok = is_equal_approx(scales[0].x, 0.2) and is_equal_approx(scales[0].y, 0.2) \
			and is_equal_approx(scales[1].x, 0.5) and is_equal_approx(scales[1].y, 0.5) \
			and is_equal_approx(scales[2].x, 1.0) and is_equal_approx(scales[2].y, 1.0)
	_assert(scale_ok, "B1: Parallax2D scroll_scale set == [0.2, 0.5, 1.0] (got %s)" % str(scales))
	inst.queue_free()


func _test_b2_particle_scale() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "B2: atmosphere_layer.tscn loads and instantiates")
		return
	var layers: Dictionary = _particle_layers(inst)
	if not layers.has(Vector2(0.2, 0.2)) or not layers.has(Vector2(0.5, 0.5)) or not layers.has(Vector2(1.0, 1.0)):
		_assert(false, "B2: far/mid/near layers found by scroll_scale")
	else:
		var near_gp: GPUParticles2D = layers[Vector2(1.0, 1.0)] as GPUParticles2D
		var mid_gp: GPUParticles2D = layers[Vector2(0.5, 0.5)] as GPUParticles2D
		var far_gp: GPUParticles2D = layers[Vector2(0.2, 0.2)] as GPUParticles2D
		var near_mat: ParticleProcessMaterial = near_gp.process_material as ParticleProcessMaterial
		var mid_mat: ParticleProcessMaterial = mid_gp.process_material as ParticleProcessMaterial
		var far_mat: ParticleProcessMaterial = far_gp.process_material as ParticleProcessMaterial
		_assert(is_equal_approx(near_mat.scale_min, 1.5) and is_equal_approx(near_mat.scale_max, 1.5), "B2: near layer particle scale ≈ 1.5 (got min=%s max=%s)" % [str(near_mat.scale_min), str(near_mat.scale_max)])
		_assert(is_equal_approx(mid_mat.scale_min, 1.0) and is_equal_approx(mid_mat.scale_max, 1.0), "B2: mid layer particle scale ≈ 1.0 (got min=%s max=%s)" % [str(mid_mat.scale_min), str(mid_mat.scale_max)])
		_assert(is_equal_approx(far_mat.scale_min, 0.5) and is_equal_approx(far_mat.scale_max, 0.5), "B2: far layer particle scale ≈ 0.5 (got min=%s max=%s)" % [str(far_mat.scale_min), str(far_mat.scale_max)])
	inst.queue_free()


func _test_b3_no_amount_override() -> void:
	var f: FileAccess = FileAccess.open("res://gdscripts/snow_curtain.gd", FileAccess.READ)
	if f == null:
		_assert(false, "B3: snow_curtain.gd opens for reading")
		return
	var text: String = f.get_as_text()
	f.close()
	_assert(text.find("amount =") == -1, "B3: snow_curtain.gd has no 'amount =' assignment (禁改 amount 红线)")


func _test_b4_emitting_state() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "B4: atmosphere_layer.tscn loads and instantiates")
		return
	var layers: Dictionary = _particle_layers(inst)
	if layers.size() != 3:
		_assert(false, "B4: exactly 3 GPUParticles2D layers found")
	else:
		var scales: Array = _sorted_scales(layers)
		for s in scales:
			var gp: GPUParticles2D = layers[s] as GPUParticles2D
			_assert(gp.emitting, "B4: layer scroll_scale=%s emitting == true" % str(s))
			_assert(not gp.one_shot, "B4: layer scroll_scale=%s one_shot == false" % str(s))
	inst.queue_free()


# ── Scenario C: moonlight ──

func _test_c1_moonlight() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "C1: atmosphere_layer.tscn loads and instantiates")
		return
	var cm: CanvasModulate = inst.find_child("Moonlight", true, false) as CanvasModulate
	if cm == null:
		_assert(false, "C1: Moonlight CanvasModulate exists")
	else:
		var consts: Dictionary = _const_map()
		var applied_v: Variant = consts.get("MOONLIGHT_COLOR_APPLIED")
		if typeof(applied_v) != TYPE_COLOR:
			_assert(false, "C1: MOONLIGHT_COLOR_APPLIED readable as Color")
		else:
			var applied: Color = applied_v
			var rgb_ok: bool = is_equal_approx(cm.color.r, applied.r) \
				and is_equal_approx(cm.color.g, applied.g) \
				and is_equal_approx(cm.color.b, applied.b)
			_assert(rgb_ok, "C1: Moonlight color RGB == MOONLIGHT_COLOR_APPLIED (got %s, expected %s)" % [str(cm.color), str(applied)])
	inst.queue_free()


func _test_c2_moonlight_convert_comment() -> void:
	var f: FileAccess = FileAccess.open("res://gdscripts/constants.gd", FileAccess.READ)
	if f == null:
		_assert(false, "C2: constants.gd opens for reading")
		return
	var text: String = f.get_as_text()
	f.close()
	var idx: int = text.find("MOONLIGHT_COLOR_APPLIED")
	if idx == -1:
		_assert(false, "C2: MOONLIGHT_COLOR_APPLIED defined in constants.gd")
		return
	var line_start: int = text.rfind("\n", idx) + 1
	var line_end: int = text.find("\n", idx)
	if line_end == -1:
		line_end = text.length()
	var line: String = text.substr(line_start, line_end - line_start)
	_assert(line.contains("× 0.6") or line.contains("* 0.6"), "C2: MOONLIGHT_COLOR_APPLIED line carries '× 0.6'/'* 0.6' conversion comment (got: %s)" % line)


func _test_c3_moonlight_covers_visible_layers() -> void:
	# self-correct #613（review D 类缺陷）: CanvasModulate 只调制其所在 canvas layer，
	# 根节点 Moonlight（layer 0）对可见内容无效。每个可见 CanvasLayer（2 水墨 / 3-5 雪幕 /
	# 10 血色）下必须各有一份 Moonlight CanvasModulate 且颜色 == MOONLIGHT_COLOR_APPLIED
	# （UI layer 1 的调制由 Main.tscn 自带，本测试只覆盖 atmosphere 场景内的 5 层）。
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "C3: atmosphere_layer.tscn loads and instantiates")
		return
	var consts: Dictionary = _const_map()
	var applied_v: Variant = consts.get("MOONLIGHT_COLOR_APPLIED")
	var expected: Color = Color(0.431, 0.463, 0.518, 1)
	if typeof(applied_v) == TYPE_COLOR:
		expected = applied_v
	var layer_nums: Array = [2, 3, 4, 5, 10]
	var canvas_layers: Array[Node] = inst.find_children("*", "CanvasLayer", true, false)
	var found: Dictionary = {}
	for cl in canvas_layers:
		var canvas: CanvasLayer = cl as CanvasLayer
		if canvas != null:
			found[canvas.layer] = canvas
	var any_fail: bool = false
	for ln in layer_nums:
		if not found.has(ln):
			_assert(false, "C3: CanvasLayer %d exists in atmosphere scene" % ln)
			any_fail = true
			continue
		var canvas: CanvasLayer = found[ln]
		var cm: CanvasModulate = canvas.find_child("Moonlight", false, false) as CanvasModulate
		if cm == null:
			_assert(false, "C3: CanvasLayer %d has a Moonlight CanvasModulate child" % ln)
			any_fail = true
		else:
			var rgb_ok: bool = is_equal_approx(cm.color.r, expected.r) \
				and is_equal_approx(cm.color.g, expected.g) \
				and is_equal_approx(cm.color.b, expected.b)
			_assert(rgb_ok, "C3: CanvasLayer %d Moonlight color == MOONLIGHT_COLOR_APPLIED (got %s, expected %s)" % [ln, str(cm.color), str(expected)])
			if not rgb_ok:
				any_fail = true
	_assert(not any_fail, "C3: all visible CanvasLayers covered by cold moonlight (composite)")


# ── Scenario D: ink wash ──

func _test_d1_ink_shader_range() -> void:
	var f: FileAccess = FileAccess.open("res://gdscripts/ink_wash.gdshader", FileAccess.READ)
	if f == null:
		_assert(false, "D1: ink_wash.gdshader opens for reading")
		return
	var text: String = f.get_as_text()
	f.close()
	_assert(text.find("hint_range(0.0, 0.3)") != -1, "D1: ink_wash.gdshader declares edge_alpha hint_range(0.0, 0.3)")


func _test_d2_ink_wash_rect() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "D2: atmosphere_layer.tscn loads and instantiates")
		return
	var ink: Control = inst.find_child("InkWash", true, false) as Control
	if ink == null:
		_assert(false, "D2: InkWash ColorRect exists")
	else:
		_assert(ink.anchors_preset == 15, "D2: InkWash anchors_preset == 15 (full rect, got %d)" % ink.anchors_preset)
		_assert(ink.mouse_filter == 2, "D2: InkWash mouse_filter == 2 (IGNORE, got %d)" % ink.mouse_filter)
	inst.queue_free()


# ── Scenario E: blood vignette ──

func _test_e1_blood_vignette_standby() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "E1: atmosphere_layer.tscn loads and instantiates")
		return
	var bl: CanvasLayer = inst.find_child("BloodVignette", true, false) as CanvasLayer
	if bl == null:
		_assert(false, "E1: BloodVignette CanvasLayer exists")
	else:
		var consts: Dictionary = _const_map()
		var layer_const: int = int(consts.get("BLOOD_VIGNETTE_LAYER", 0))
		_assert(bl.layer == layer_const, "E1: BloodVignette layer == BLOOD_VIGNETTE_LAYER (%d, got %d)" % [layer_const, bl.layer])
		_assert(bl.layer == 10, "E1: BloodVignette layer == 10 (got %d)" % bl.layer)
		_assert(is_equal_approx(_visual_alpha(bl), 0.0), "E1: get_visual_alpha() == 0.0 on standby (got %s)" % str(_visual_alpha(bl)))
	inst.queue_free()


func _test_e2_blood_trigger_and_convert() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "E2: atmosphere_layer.tscn loads and instantiates")
		return
	var bl: CanvasLayer = inst.find_child("BloodVignette", true, false) as CanvasLayer
	if bl == null:
		_assert(false, "E2: BloodVignette CanvasLayer exists")
	else:
		bl.call("debug_trigger_low_health")
		_assert(_visual_alpha(bl) < 0.05, "E2: after debug_trigger_low_health() alpha < 0.05 (gradual, not jump; got %s)" % str(_visual_alpha(bl)))
		var blood_rect: ColorRect = inst.find_child("BloodRect", true, false) as ColorRect
		if blood_rect == null:
			_assert(false, "E2: BloodRect ColorRect exists")
		else:
			var c: Color = blood_rect.modulate
			c.a = 1.0
			blood_rect.modulate = c
			_assert(is_equal_approx(_visual_alpha(bl), 0.35), "E2: modulate.a=1.0 → get_visual_alpha() ≈ 0.35 (conversion; got %s)" % str(_visual_alpha(bl)))
	inst.queue_free()


func _test_e3_blood_idempotent() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "E3: atmosphere_layer.tscn loads and instantiates")
		return
	var bl: CanvasLayer = inst.find_child("BloodVignette", true, false) as CanvasLayer
	if bl == null:
		_assert(false, "E3: BloodVignette CanvasLayer exists")
	else:
		bl.call("set_low_health", true)
		bl.call("set_low_health", true)
		_assert(_visual_alpha(bl) < 0.05, "E3: set_low_health(true) twice → alpha still < 0.05 (idempotent guard, no jump; got %s)" % str(_visual_alpha(bl)))
		bl.call("debug_clear_low_health")
		_assert(_visual_alpha(bl) < 0.05, "E3: after debug_clear_low_health() alpha < 0.05 (got %s)" % str(_visual_alpha(bl)))
		_assert(bl.get("_enabled") == false, "E3: internal _enabled == false after clear (got %s)" % str(bl.get("_enabled")))
	inst.queue_free()


func _test_e4_blood_same_path() -> void:
	var inst: Node = _instantiate_scene()
	if inst == null:
		_assert(false, "E4: atmosphere_layer.tscn loads and instantiates")
		return
	var bl: CanvasLayer = inst.find_child("BloodVignette", true, false) as CanvasLayer
	if bl == null:
		_assert(false, "E4: BloodVignette CanvasLayer exists")
	else:
		bl.call("set_low_health", true)
		_assert(_visual_alpha(bl) < 0.05, "E4: set_low_health(true) → immediate alpha < 0.05 (gradual path; got %s)" % str(_visual_alpha(bl)))
		bl.call("debug_clear_low_health")
		bl.call("debug_trigger_low_health")
		_assert(_visual_alpha(bl) < 0.05, "E4: debug_trigger_low_health() → immediate alpha < 0.05 (same gradual path; got %s)" % str(_visual_alpha(bl)))
	inst.queue_free()

extends RefCounted

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")

func run() -> void:
	print("=== Visual Enrichment Tests ===")
	await _test_a1_palette()
	await _test_a2_palette_hue_domain()
	await _test_a3_vignette_cap()
	await _test_a4_glow_avoids_theme()
	await _test_a5_variant_map()
	await _test_a6_fx_durations()
	await _test_b1_wave1_all_normal()
	await _test_b2_wave3_color()
	await _test_b3_iron_injection()
	await _test_b5_same_seed_reproducible()
	await _test_b6_no_gamemanager_fallback()
	await _test_c1_compute_alpha()
	await _test_c2_city_glow_texture()
	await _test_c3_vignette_shader_text()
	await _test_c4_main_scene_nodes()
	await _test_c5_menu_structural_hide()
	await _test_d5_unwired_no_crash()
	await _test_d1_brick_flash()
	await _test_d2_pierce_pulse()
	await _test_d3_same_frame_arbitration()
	await _test_d4_run_over_guard()
	print("Passed: %d, Failed: %d" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  PASS: " + name)
	else:
		failed += 1
		print("  FAIL: " + name)

func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout

func _reset_game() -> void:
	if is_instance_valid(GameManager):
		GameManager.reset_match()

func _make_grid() -> Node2D:
	var grid: Node2D = Node2D.new()
	grid.set_script(load("res://gdscripts/breakout_grid.gd"))
	grid.name = "BreakoutGrid"
	(Engine.get_main_loop() as SceneTree).root.add_child(grid)
	return grid

func _brick_children(grid) -> Array:
	var children = []
	for child in grid.get_children():
		if child.is_in_group("bricks"):
			children.append(child)
	return children

func _free_node(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()
	await _wait(0.1)

func _rect_color(brick) -> Color:
	return brick.get_node("ColorRect").color

func _make_fx_node() -> Node:
	var fx = Node.new()
	fx.set_script(load("res://gdscripts/feedback_fx.gd"))
	var pr = ColorRect.new()
	pr.name = "PiercePulseRect"
	pr.visible = false
	fx.add_child(pr)
	var pool = Node2D.new()
	pool.name = "BrickFlashPool"
	fx.add_child(pool)
	(Engine.get_main_loop() as SceneTree).root.add_child(fx)
	return fx

func _visible_flash_rects(fx) -> Array:
	var rects = []
	for c in fx.get_node("BrickFlashPool").get_children():
		if c.visible:
			rects.append(c)
	return rects

func _sorted_positions(grid) -> Array:
	var pos = []
	for b in _brick_children(grid):
		pos.append(b.position)
	pos.sort_custom(_sort_pos)
	return pos

func _sorted_iron_positions(grid) -> Array:
	var pos = []
	for b in _brick_children(grid):
		if b.brick_variant == 1:
			pos.append(b.position)
	pos.sort_custom(_sort_pos)
	return pos

func _sort_pos(a, b) -> bool:
	return a.x < b.x if abs(a.x - b.x) > 0.001 else a.y < b.y

func _test_a1_palette() -> void:
	print("--- A1: wave color palette ---")
	var size: int = CONSTS.WAVE_COLOR_PALETTE.size()
	_assert(size >= 4 and size <= 6, "WAVE_COLOR_PALETTE size %d in [4,6]" % size)
	_assert(CONSTS.WAVE_COLOR_PALETTE[0] == CONSTS.BRICK_NEON, "WAVE_COLOR_PALETTE[0] == BRICK_NEON")

func _test_a2_palette_hue_domain() -> void:
	print("--- A2: palette hue domain ---")
	var paddle_hue: float = CONSTS.PADDLE_NEON.h * 360.0
	for i in CONSTS.WAVE_COLOR_PALETTE.size():
		var c: Color = CONSTS.WAVE_COLOR_PALETTE[i]
		var deg: float = c.h * 360.0
		_assert(deg >= 20.0 and deg <= 60.0, "palette[%d] hue %.1f in [20,60]" % [i, deg])
		var ring: float = abs(deg - paddle_hue)
		ring = min(ring, 360.0 - ring)
		_assert(ring >= 126.0, "palette[%d] hue ring %.1f >= 126" % [i, ring])

func _test_a3_vignette_cap() -> void:
	print("--- A3: vignette strength cap ---")
	_assert(CONSTS.VIGNETTE_MAX_STRENGTH <= 0.10, "VIGNETTE_MAX_STRENGTH %f <= 0.10" % CONSTS.VIGNETTE_MAX_STRENGTH)

func _test_a4_glow_avoids_theme() -> void:
	print("--- A4: city glow avoids player theme ---")
	var diff: Color = CONSTS.CITY_GLOW_TINT - CONSTS.PLAYER_NEON_BLUE
	var dist: float = sqrt(diff.r * diff.r + diff.g * diff.g + diff.b * diff.b)
	_assert(dist * 255.0 >= 32.0, "CITY_GLOW_TINT dist %.1f/255 >= 32/255" % (dist * 255.0))

func _test_a5_variant_map() -> void:
	print("--- A5: brick variant map ---")
	var d = CONSTS.BRICK_VARIANT_COLORS
	_assert(d.has(0), "BRICK_VARIANT_COLORS has key 0")
	_assert(d.has(1), "BRICK_VARIANT_COLORS has key 1")
	_assert(d.has(2), "BRICK_VARIANT_COLORS has key 2")
	_assert(d[0] == CONSTS.BRICK_NEON, "BRICK_VARIANT_COLORS[0] == BRICK_NEON")
	var diff: Color = d[1] - CONSTS.PADDLE_NEON
	var dist: float = sqrt(diff.r * diff.r + diff.g * diff.g + diff.b * diff.b)
	_assert(dist >= 0.24, "BRICK_VARIANT_COLORS[1] dist %.4f to PADDLE_NEON >= 0.24" % dist)

func _test_a6_fx_durations() -> void:
	print("--- A6: FX durations ---")
	_assert(CONSTS.FX_BRICK_FLASH_DURATION >= 0.15 and CONSTS.FX_BRICK_FLASH_DURATION <= 0.30, "FX_BRICK_FLASH_DURATION %f in [0.15,0.30]" % CONSTS.FX_BRICK_FLASH_DURATION)
	_assert(CONSTS.FX_PIERCE_DURATION >= 0.15 and CONSTS.FX_PIERCE_DURATION <= 0.30, "FX_PIERCE_DURATION %f in [0.15,0.30]" % CONSTS.FX_PIERCE_DURATION)

func _test_b1_wave1_all_normal() -> void:
	print("--- B1: wave 1 all normal ---")
	_reset_game()
	GameManager.begin_wave()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 527)
	var bricks = _brick_children(grid)
	_assert(bricks.size() > 0, "wave 1 produces bricks")
	var iron_count: int = 0
	for b in bricks:
		_assert(b.brick_variant == 0, "wave 1 brick variant == 0")
		if b.brick_variant == 0:
			_assert(_rect_color(b) == CONSTS.BRICK_NEON, "wave 1 brick color == BRICK_NEON")
		else:
			iron_count += 1
	_assert(iron_count == 0, "wave 1 iron count == 0")
	_free_node(grid)

func _test_b2_wave3_color() -> void:
	print("--- B2: wave 3 palette color ---")
	_reset_game()
	GameManager.begin_wave()
	GameManager.begin_wave()
	GameManager.begin_wave()
	var grid = _make_grid()
	grid.generate_wave(2, 0, 528)
	var bricks = _brick_children(grid)
	var normals = []
	for b in bricks:
		if b.brick_variant == 0:
			normals.append(b)
	_assert(normals.size() > 0, "wave 3 has normal bricks")
	for b in normals:
		_assert(_rect_color(b) == CONSTS.WAVE_COLOR_PALETTE[2], "wave 3 normal brick == palette[2]")
	_free_node(grid)

func _test_b3_iron_injection() -> void:
	print("--- B3: iron injection ---")
	_reset_game()
	GameManager.begin_wave()
	GameManager.begin_wave()
	var grid = _make_grid()
	grid.generate_wave(3, 0, 529)
	var bricks = _brick_children(grid)
	var iron = []
	for b in bricks:
		if b.brick_variant == 1:
			iron.append(b)
	_assert(iron.size() <= CONSTS.IRON_BRICK_COUNT_PER_WAVE * 2, "iron count %d <= %d" % [iron.size(), CONSTS.IRON_BRICK_COUNT_PER_WAVE * 2])
	var shared = load("res://assets/neon_glow_material.tres")
	for b in iron:
		_assert(_rect_color(b) == CONSTS.BRICK_VARIANT_COLORS[1], "iron brick color == variant[1]")
		var m = b.get_node("ColorRect").material
		_assert(m != shared, "iron brick material is duplicated")
		_assert(m.get_shader_parameter("glow_color") == CONSTS.BRICK_VARIANT_COLORS[1], "iron glow_color == variant[1]")
	for b in bricks:
		if b.brick_variant == 0:
			_assert(b.get_node("ColorRect").material == shared, "normal brick shares material")
	_free_node(grid)

func _test_b5_same_seed_reproducible() -> void:
	print("--- B5: same seed reproducible ---")
	_reset_game()
	GameManager.begin_wave()
	GameManager.begin_wave()
	var grid1 = _make_grid()
	grid1.generate_wave(2, 0, 777)
	var pos1 = _sorted_positions(grid1)
	var iron1 = _sorted_iron_positions(grid1)
	_free_node(grid1)
	var grid2 = _make_grid()
	grid2.generate_wave(2, 0, 777)
	var pos2 = _sorted_positions(grid2)
	var iron2 = _sorted_iron_positions(grid2)
	_assert(pos1.size() == pos2.size(), "position counts match %d == %d" % [pos1.size(), pos2.size()])
	for i in pos1.size():
		_assert(pos1[i].distance_to(pos2[i]) < 0.001, "brick position %d reproducible" % i)
	_assert(iron1.size() == iron2.size(), "iron counts match %d == %d" % [iron1.size(), iron2.size()])
	for i in iron1.size():
		_assert(iron1[i].distance_to(iron2[i]) < 0.001, "iron position %d reproducible" % i)
	_free_node(grid2)

func _test_b6_no_gamemanager_fallback() -> void:
	print("--- B6: no GameManager fallback ---")
	_reset_game()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 530)
	_assert(is_instance_valid(grid), "grid generated without GameManager crash")
	var bricks = _brick_children(grid)
	var normals = []
	for b in bricks:
		if b.brick_variant == 0:
			normals.append(b)
	_assert(normals.size() > 0, "fallback normal bricks > 0")
	for b in normals:
		_assert(_rect_color(b) == CONSTS.WAVE_COLOR_PALETTE[0], "fallback brick == palette[0]")
	_free_node(grid)

func _test_c1_compute_alpha() -> void:
	print("--- C1: BgPulse compute_alpha ---")
	var BgPulse = preload("res://gdscripts/bg_pulse.gd")
	var a1: float = BgPulse.compute_alpha(0.0, 6.0, 0.05, 0.05)
	_assert(abs(a1 - 0.05) < 1e-4, "compute_alpha(0.0) == 0.05")
	var a2: float = BgPulse.compute_alpha(1.5, 6.0, 0.05, 0.05)
	_assert(abs(a2 - 0.10) < 1e-4, "compute_alpha(1.5) == 0.10")
	var a3: float = BgPulse.compute_alpha(1.0, 0.0, 0.05, 0.05)
	_assert(abs(a3 - 0.05) < 1e-4, "compute_alpha(period<=0) == base")
	var t: float = 0.0
	while t <= 6.0:
		var a: float = BgPulse.compute_alpha(t, 6.0, 0.05, 0.05)
		_assert(a <= 0.101, "compute_alpha(%.2f) = %.4f <= 0.101" % [t, a])
		t += 0.25

func _test_c2_city_glow_texture() -> void:
	print("--- C2: city glow texture ---")
	var node = TextureRect.new()
	node.set_script(load("res://gdscripts/city_glow.gd"))
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	_assert(node.texture is GradientTexture2D, "city glow uses GradientTexture2D")
	var tex = node.texture
	_assert(tex.fill_from == Vector2(0, 1) and tex.fill_to == Vector2(0, 0), "gradient fill vertical")
	_assert(tex.gradient.get_color(0) == CONSTS.CITY_GLOW_TINT, "gradient top == CITY_GLOW_TINT")
	_assert(tex.gradient.get_color(1).a < 0.001, "gradient bottom alpha ~ 0")
	_assert(int(tex.height) == int(CONSTS.CITY_GLOW_HEIGHT), "texture height == CITY_GLOW_HEIGHT")
	_free_node(node)

func _test_c3_vignette_shader_text() -> void:
	print("--- C3: vignette shader text ---")
	var f = FileAccess.open("res://gdscripts/vignette.gdshader", FileAccess.READ)
	_assert(f != null, "vignette.gdshader openable")
	if f != null:
		var content: String = f.get_as_text()
		_assert(content.contains("hint_range(0.0, 0.10)"), "shader contains hint_range(0.0, 0.10)")
		_assert(content.contains("strength"), "shader references strength")
	_assert(ResourceLoader.exists("res://gdscripts/vignette.gd"), "vignette.gd exists")

func _test_c4_main_scene_nodes() -> void:
	print("--- C4: main scene nodes ---")
	var scene = load("res://scenes/Main.tscn")
	var game = scene.instantiate()
	_assert(game.has_node("AtmosphereLayer/CityGlow"), "Main has AtmosphereLayer/CityGlow")
	_assert(game.has_node("AtmosphereLayer/Vignette"), "Main has AtmosphereLayer/Vignette")
	_assert(game.has_node("FeedbackFX"), "Main has FeedbackFX")
	_assert(game.has_node("FeedbackFX/PiercePulseRect"), "Main has FeedbackFX/PiercePulseRect")
	_assert(game.has_node("FeedbackFX/BrickFlashPool"), "Main has FeedbackFX/BrickFlashPool")
	game.free()

func _test_c5_menu_structural_hide() -> void:
	print("--- C5: menu structural hide ---")
	var layer = CanvasLayer.new()
	layer.add_to_group("game_world")
	var glow = TextureRect.new()
	glow.set_script(load("res://gdscripts/city_glow.gd"))
	layer.add_child(glow)
	var vig = ColorRect.new()
	vig.set_script(load("res://gdscripts/vignette.gd"))
	layer.add_child(vig)
	(Engine.get_main_loop() as SceneTree).root.add_child(layer)
	layer.visible = false
	_assert(glow.visible == false and vig.visible == false, "glow/vignette hidden with layer")
	layer.visible = true
	_assert(glow.visible == true and vig.visible == true, "glow/vignette visible with layer")
	_free_node(layer)

func _test_d5_unwired_no_crash() -> void:
	print("--- D5: unwired FX no crash ---")
	_reset_game()
	var fx = _make_fx_node()
	_assert(fx.get_node("PiercePulseRect").visible == false, "pierce rect starts hidden")
	_assert(fx.get_node("BrickFlashPool").get_child_count() == CONSTS.FX_FLASH_POOL_SIZE, "flash pool pre-populated")
	_free_node(fx)

func _test_d1_brick_flash() -> void:
	print("--- D1: brick flash ---")
	_reset_game()
	var grid = _make_grid()
	grid.generate_wave(1, 0, 999)
	var fx = _make_fx_node()
	for c in fx.get_node("BrickFlashPool").get_children():
		_assert(not c.visible, "flash rect initially hidden")
	grid.brick_destroyed.emit(Node2D.new(), Vector2(100, 200))
	var visible_rects = _visible_flash_rects(fx)
	_assert(visible_rects.size() == 1, "exactly one flash rect visible after emit")
	if visible_rects.size() == 1:
		var rect = visible_rects[0]
		_assert(rect.global_position.distance_to(Vector2(100, 200)) < 0.001, "flash positioned at brick location")
		_assert(abs(rect.modulate.a - 1.0) < 1e-4, "flash alpha at peak")
	await _wait(0.35)
	if visible_rects.size() == 1:
		_assert(visible_rects[0].visible == false, "flash rect hidden after duration")
	for i in 5:
		grid.brick_destroyed.emit(Node2D.new(), Vector2(150 + i, 220))
	var vis_now = _visible_flash_rects(fx)
	_assert(vis_now.size() <= CONSTS.FX_FLASH_POOL_SIZE, "flash pool capped at pool size")
	_free_node(fx)
	_free_node(grid)

func _test_d2_pierce_pulse() -> void:
	print("--- D2: pierce pulse ---")
	_reset_game()
	var fx = _make_fx_node()
	GameManager.pierce_scored.emit("player")
	var pr = fx.get_node("PiercePulseRect")
	_assert(pr.visible == true, "pierce rect visible after score")
	_assert(pr.color == CONSTS.FX_PIERCE_COLOR, "pierce rect color matches")
	_assert(abs(pr.modulate.a - CONSTS.FX_PIERCE_PEAK_ALPHA) < 1e-4, "pierce alpha at peak")
	await _wait(0.4)
	_assert(pr.visible == false, "pierce rect hidden after duration")
	_free_node(fx)

func _test_d3_same_frame_arbitration() -> void:
	print("--- D3: same-frame arbitration ---")
	_reset_game()
	var fx = _make_fx_node()
	fx._on_pierce("player")
	fx._on_brick_destroyed(Node2D.new(), Vector2(50, 50))
	_assert(_visible_flash_rects(fx).size() == 0, "no brick flash when pierce same frame")
	_free_node(fx)

func _test_d4_run_over_guard() -> void:
	print("--- D4: run over guard ---")
	_reset_game()
	GameManager.add_score("player", 21)
	_assert(GameManager.is_run_over(), "run over after 21 player score")
	var fx = _make_fx_node()
	fx._on_brick_destroyed(Node2D.new(), Vector2(50, 50))
	_assert(_visible_flash_rects(fx).size() == 0, "no brick flash when run over")
	GameManager.pierce_scored.emit("player")
	_assert(fx.get_node("PiercePulseRect").visible == false, "no pierce pulse when run over")
	_free_node(fx)
	GameManager.reset_match()

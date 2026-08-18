extends RefCounted
## Test suite for Main Scene Assembly (#295) — Scene tree integrity, ScoreZones, ScoreFlash.
## Runs under godot --headless --script via run_tests.gd.
## 竖屏重写 (#383): 得分区改上下 ScoreZoneTop(360,0)/ScoreZoneBottom(360,1280) 720×20；
## 墙改左右 LeftWall(5,640)/RightWall(715,640) 10×1280；Ball(360,640)；
## PlayerPaddle(360,1240)/AIPaddle(360,40)；GameHUD offset_right=720。

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Main Scene Assembly Tests (#295) ===")
	_test_tc1_scene_tree_nodes()
	_test_tc2_ext_resource_references()
	_test_tc3_world_environment()
	_test_tc4_score_zone_top()
	_test_tc5_score_zone_bottom()
	_test_tc9_score_flash_node()
	_test_tc12_score_zone_collision()
	_test_tc14_scorezone_shape_dimensions()
	_test_tc17_no_game_tscn_refs()
	_test_tc18_scorezone_ball_collision_contract()
	_test_tc19_version_label_in_start_menu()
	_test_tc20_portrait_layout_coords()
	_test_tc21_atmosphere_layer()
	_test_tc22_assembly_nodes()


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── TC1: Main.tscn contains all 12+ node types (Normal) ──

func _test_tc1_scene_tree_nodes() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		failed += 1
		return

	var scene = load("res://scenes/Main.tscn")
	_assert(scene != null, "TC1-0: Main.tscn loaded")
	if scene == null:
		return

	var game = scene.instantiate()
	_assert(game != null, "TC1-1: Main.tscn instantiates")

	# Verify all mandatory nodes exist (竖屏: LeftWall/RightWall, #383)
	_assert(game.has_node("WorldEnvironment"), "TC1-2: WorldEnvironment node exists")
	_assert(game.has_node("LeftWall"), "TC1-3: LeftWall node exists")
	_assert(game.has_node("RightWall"), "TC1-4: RightWall node exists")
	_assert(game.has_node("Ball"), "TC1-5: Ball node exists")
	_assert(game.has_node("PlayerPaddle"), "TC1-6: PlayerPaddle node exists")
	_assert(game.has_node("AIPaddle"), "TC1-7: AIPaddle node exists")
	_assert(game.has_node("ScoringManager"), "TC1-8: ScoringManager node exists")
	_assert(game.has_node("GameStateMachine"), "TC1-9: GameStateMachine node exists")
	_assert(game.has_node("StartMenu"), "TC1-10: StartMenu node exists")
	_assert(game.has_node("GameHUD"), "TC1-11: GameHUD node exists")
	_assert(game.has_node("GameOverScreen"), "TC1-12: GameOverScreen node exists")

	# 竖屏得分区 (#383)
	_assert(game.has_node("ScoreZoneTop"), "TC1-13: ScoreZoneTop node exists")
	_assert(game.has_node("ScoreZoneBottom"), "TC1-14: ScoreZoneBottom node exists")
	_assert(game.has_node("ScoreFlash"), "TC1-15: ScoreFlash node exists")

	game.queue_free()


# ── TC2: Main.tscn ext_resource references resolve ──

func _test_tc2_ext_resource_references() -> void:
	# Verify ext_resource files exist on disk
	var resources := [
		"res://scenes/ball.tscn",
		"res://scenes/player_paddle.tscn",
		"res://gdscripts/scoring_manager.gd",
		"res://gdscripts/start_menu.gd",
		"res://gdscripts/game_hud.gd",
		"res://gdscripts/game_over_screen.gd",
		"res://gdscripts/game_state_machine.gd",
		"res://scenes/world_environment.tscn",
		"res://gdscripts/score_flash.gd",
	]
	for path in resources:
		var exists = ResourceLoader.exists(path)
		_assert(exists, "TC2: %s exists" % path)


# ── TC3: WorldEnvironment node references world_environment.tscn ──

func _test_tc3_world_environment() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()
	var we = game.get_node_or_null("WorldEnvironment")
	_assert(we != null, "TC3-1: WorldEnvironment node present")
	if we:
		_assert(we is WorldEnvironment, "TC3-2: WorldEnvironment is correct type")
		_assert(we.environment != null, "TC3-3: WorldEnvironment has environment resource")
		if we.environment:
			_assert(abs(we.environment.glow_intensity - 0.6) < 0.01, "TC3-4: glow_intensity == 0.6")
			_assert(abs(we.environment.glow_bloom - 0.8) < 0.01, "TC3-5: glow_bloom == 0.8")

	game.queue_free()


# ── TC4: ScoreZoneTop is Area2D at pos (360, 0) ──

func _test_tc4_score_zone_top() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()
	var zone = game.get_node_or_null("ScoreZoneTop")
	_assert(zone != null, "TC4-1: ScoreZoneTop node exists")
	if zone:
		_assert(zone is Area2D, "TC4-2: ScoreZoneTop is Area2D")
		_assert(abs(zone.position.x - 360.0) < 0.01, "TC4-3: ScoreZoneTop position.x == 360")
		_assert(abs(zone.position.y - 0.0) < 0.01, "TC4-4: ScoreZoneTop position.y == 0")
		_assert(zone.has_node("CollisionShape2D"), "TC4-5: ScoreZoneTop has CollisionShape2D")
		var cs = zone.get_node("CollisionShape2D")
		_assert(cs.shape != null, "TC4-6: ScoreZoneTop CollisionShape2D has non-null shape")

	game.queue_free()


# ── TC5: ScoreZoneBottom is Area2D at pos (360, 1280) ──

func _test_tc5_score_zone_bottom() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()
	var zone = game.get_node_or_null("ScoreZoneBottom")
	_assert(zone != null, "TC5-1: ScoreZoneBottom node exists")
	if zone:
		_assert(zone is Area2D, "TC5-2: ScoreZoneBottom is Area2D")
		_assert(abs(zone.position.x - 360.0) < 0.01, "TC5-3: ScoreZoneBottom position.x == 360")
		_assert(abs(zone.position.y - 1280.0) < 0.01, "TC5-4: ScoreZoneBottom position.y == 1280")
		_assert(zone.has_node("CollisionShape2D"), "TC5-5: ScoreZoneBottom has CollisionShape2D")
		var cs = zone.get_node("CollisionShape2D")
		_assert(cs.shape != null, "TC5-6: ScoreZoneBottom CollisionShape2D has non-null shape")

	game.queue_free()


# ── TC9: ScoreFlash node with ColorRect child ──

func _test_tc9_score_flash_node() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()
	var sf = game.get_node_or_null("ScoreFlash")
	_assert(sf != null, "TC9-1: ScoreFlash node exists")
	if sf:
		_assert(sf.has_node("ScoreFlashRect"), "TC9-2: ScoreFlash has ScoreFlashRect child")
		var rect = sf.get_node_or_null("ScoreFlashRect")
		if rect:
			_assert(rect is ColorRect, "TC9-3: ScoreFlashRect is ColorRect")

	game.queue_free()


# ── TC12 / TC14: ScoreZone collision shape dimensions ──

func _test_tc12_score_zone_collision() -> void:
	# Verify score_flash.gd exists (needed for ScoreFlash node)
	var exists = ResourceLoader.exists("res://gdscripts/score_flash.gd")
	_assert(exists, "TC12-1: score_flash.gd exists")

	# Verify world_environment.tscn exists
	exists = ResourceLoader.exists("res://scenes/world_environment.tscn")
	_assert(exists, "TC12-2: world_environment.tscn exists")


func _test_tc14_scorezone_shape_dimensions() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()

	# 竖屏: ScoreZoneTop/Bottom shape 720×20 (#383)
	var zone_top = game.get_node_or_null("ScoreZoneTop")
	if zone_top and zone_top.has_node("CollisionShape2D"):
		var cs = zone_top.get_node("CollisionShape2D")
		var shape = cs.shape
		if shape is RectangleShape2D:
			_assert(abs(shape.size.x - 720.0) < 0.01, "TC14-1: ScoreZoneTop shape width == 720")
			_assert(abs(shape.size.y - 20.0) < 0.01, "TC14-2: ScoreZoneTop shape height == 20")

	var zone_bottom = game.get_node_or_null("ScoreZoneBottom")
	if zone_bottom and zone_bottom.has_node("CollisionShape2D"):
		var cs = zone_bottom.get_node("CollisionShape2D")
		var shape = cs.shape
		if shape is RectangleShape2D:
			_assert(abs(shape.size.x - 720.0) < 0.01, "TC14-3: ScoreZoneBottom shape width == 720")
			_assert(abs(shape.size.y - 20.0) < 0.01, "TC14-4: ScoreZoneBottom shape height == 20")

	game.queue_free()


# ── TC17: No remaining game.tscn references in project ──

func _test_tc17_no_game_tscn_refs() -> void:
	# This test verifies that project.godot references Main.tscn not game.tscn
	var content = FileAccess.get_file_as_string("res://project.godot")
	_assert(content != "", "TC17-1: project.godot readable")
	_assert(content.contains("run/main_scene=\"res://scenes/Main.tscn\""), "TC17-2: run/main_scene set to Main.tscn")
	_assert(not content.contains("game.tscn"), "TC17-3: no game.tscn reference in project.godot")


# ── TC18: ScoreZone ↔ Ball collision contract (Integration) ──

func _test_tc18_scorezone_ball_collision_contract() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()

	var ball = game.get_node_or_null("Ball")
	_assert(ball != null, "TC18-1: Ball node exists")
	if ball:
		_assert(ball is Area2D, "TC18-2: Ball is Area2D")

	var zone_top = game.get_node_or_null("ScoreZoneTop")
	if zone_top and ball:
		_assert(zone_top.collision_mask & ball.collision_layer != 0,
			"TC18-3: ScoreZoneTop collision_mask includes ball's collision_layer")
		_assert(ball.collision_mask & zone_top.collision_layer != 0,
			"TC18-4: Ball collision_mask includes ScoreZoneTop's collision_layer")

	var zone_bottom = game.get_node_or_null("ScoreZoneBottom")
	if zone_bottom and ball:
		_assert(zone_bottom.collision_mask & ball.collision_layer != 0,
			"TC18-5: ScoreZoneBottom collision_mask includes ball's collision_layer")
		_assert(ball.collision_mask & zone_bottom.collision_layer != 0,
			"TC18-6: Ball collision_mask includes ScoreZoneBottom's collision_layer")

	var ball_src = FileAccess.get_file_as_string("res://gdscripts/ball.gd")
	_assert(ball_src != "", "TC18-7: ball.gd readable")
	_assert(ball_src.contains("area_entered.connect"),
		"TC18-8: ball.gd uses area_entered (not body_entered) for ScoreZone")

	game.queue_free()

# ── TC19: StartMenu VersionLabel in Main.tscn inline tree (R2 sync) ──

func _test_tc19_version_label_in_start_menu() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		_assert(false, "TC19: Main.tscn missing")
		return
	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		_assert(false, "TC19: Main.tscn failed to load")
		return
	var game = scene.instantiate()

	var vl = game.get_node_or_null("StartMenu/VersionLabel")
	_assert(vl != null, "TC19-1: StartMenu/VersionLabel exists in Main.tscn")
	if vl:
		_assert(vl is Label, "TC19-2: VersionLabel is Label type")
		_assert(vl.text == "v1.0.0", "TC19-3: VersionLabel static text is 'v1.0.0'")

		var packed = load("res://scenes/ui_start_menu.tscn")
		if packed:
			var ui_instance = packed.instantiate()
			var ui_vl = ui_instance.get_node_or_null("VersionLabel")
			if ui_vl:
				_assert(vl.get("theme_override_font_sizes/font_size") == ui_vl.get("theme_override_font_sizes/font_size"),
					"TC19-4: font_size matches ui_start_menu.tscn")
				_assert(vl.modulate == ui_vl.modulate, "TC19-5: modulate matches ui_start_menu.tscn")
				_assert(abs(vl.anchor_left - ui_vl.anchor_left) < 0.001 and abs(vl.anchor_top - ui_vl.anchor_top) < 0.001,
					"TC19-6: anchors match ui_start_menu.tscn")
			ui_instance.queue_free()

	# TC19-7..13: ModeSelect 区存在性 + 与 ui_start_menu.tscn R2 同步 (#551)
	var mode_vbox = game.get_node_or_null("StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox")
	_assert(mode_vbox != null, "TC19-7: ModeSelectVBox exists in Main.tscn")
	var option1 = game.get_node_or_null("StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption1")
	var option2 = game.get_node_or_null("StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption2")
	_assert(option1 != null and option1 is Label and option1.text == "单人模式（AI 对战）", "TC19-8: ModeOption1 Label with text 单人模式（AI 对战）")
	_assert(option2 != null and option2 is Label and option2.text == "本地双人对战", "TC19-9: ModeOption2 Label with text 本地双人对战")
	var vbox = game.get_node_or_null("StartMenu/CenterContainer/VBoxContainer")
	if vbox and option1 and option2:
		var children = vbox.get_children()
		_assert(children.size() >= 3 and children[0].name == "TitleLabel" and children[1].name == "ModeSelectVBox" and children[2].name == "PromptLabel", "TC19-10: VBox child order TitleLabel < ModeSelectVBox < PromptLabel")
	var packed = load("res://scenes/ui_start_menu.tscn")
	if packed and mode_vbox and option1 and option2:
		var ui_instance = packed.instantiate()
		var ui_mv = ui_instance.get_node_or_null("CenterContainer/VBoxContainer/ModeSelectVBox")
		var ui_o1 = ui_instance.get_node_or_null("CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption1")
		var ui_o2 = ui_instance.get_node_or_null("CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption2")
		if ui_mv and ui_o1 and ui_o2:
			_assert(option1.get("theme_override_font_sizes/font_size") == 22 and option1.get("theme_override_font_sizes/font_size") == ui_o1.get("theme_override_font_sizes/font_size") and option2.get("theme_override_font_sizes/font_size") == 22 and option2.get("theme_override_font_sizes/font_size") == ui_o2.get("theme_override_font_sizes/font_size"), "TC19-11: ModeOption font_size == 22 matches ui_start_menu.tscn")
			_assert(mode_vbox.get("theme_override_constants/separation") == 8 and mode_vbox.get("theme_override_constants/separation") == ui_mv.get("theme_override_constants/separation"), "TC19-12: ModeSelectVBox separation == 8 matches ui_start_menu.tscn")
			_assert(option1.horizontal_alignment == 1 and option1.horizontal_alignment == ui_o1.horizontal_alignment and option2.horizontal_alignment == 1 and option2.horizontal_alignment == ui_o2.horizontal_alignment, "TC19-13: ModeOption horizontal_alignment == 1 matches ui_start_menu.tscn")
		ui_instance.queue_free()

	game.queue_free()


# ── TC20: 竖屏布局坐标 (验收条件 AC2, #383) ──

func _test_tc20_portrait_layout_coords() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()

	# 墙: LeftWall(5,640) / RightWall(715,640)
	var left = game.get_node_or_null("LeftWall")
	if left:
		_assert(abs(left.position.x - 5.0) < 0.01, "TC20-1: LeftWall position.x == 5")
		_assert(abs(left.position.y - 640.0) < 0.01, "TC20-2: LeftWall position.y == 640")
	var right = game.get_node_or_null("RightWall")
	if right:
		_assert(abs(right.position.x - 715.0) < 0.01, "TC20-3: RightWall position.x == 715")
		_assert(abs(right.position.y - 640.0) < 0.01, "TC20-4: RightWall position.y == 640")

	# Ball(360,640)
	var ball = game.get_node_or_null("Ball")
	if ball:
		_assert(abs(ball.position.x - 360.0) < 0.01, "TC20-5: Ball position.x == 360")
		_assert(abs(ball.position.y - 640.0) < 0.01, "TC20-6: Ball position.y == 640")

	# PlayerPaddle(360,1240) / AIPaddle(360,40)
	var pp = game.get_node_or_null("PlayerPaddle")
	if pp:
		_assert(abs(pp.position.x - 360.0) < 0.01, "TC20-7: PlayerPaddle position.x == 360")
		_assert(abs(pp.position.y - 1240.0) < 0.01, "TC20-8: PlayerPaddle position.y == 1240")
	var ap = game.get_node_or_null("AIPaddle")
	if ap:
		_assert(abs(ap.position.x - 360.0) < 0.01, "TC20-9: AIPaddle position.x == 360")
		_assert(abs(ap.position.y - 40.0) < 0.01, "TC20-10: AIPaddle position.y == 40")

	# GameHUD 三区安全区 (#392): TopZone/BottomZone 锚点全宽（替代旧 MarginContainer offset_right==720）
	var hud = game.get_node_or_null("GameHUD")
	if hud:
		var top_zone = hud.get_node_or_null("TopZone")
		if top_zone:
			_assert(abs(top_zone.anchor_right - 1.0) < 0.01, "TC20-11: GameHUD TopZone 锚点全宽")
			_assert(abs(top_zone.offset_top - 12.0) < 0.01, "TC20-12: TopZone offset_top == 12")
			_assert(abs(top_zone.offset_bottom - 84.0) < 0.01, "TC20-13: TopZone offset_bottom == 84")
		var bottom_zone = hud.get_node_or_null("BottomZone")
		if bottom_zone:
			_assert(abs(bottom_zone.anchor_right - 1.0) < 0.01, "TC20-14: GameHUD BottomZone 锚点全宽")
			_assert(abs(bottom_zone.anchor_top - 1.0) < 0.01 and abs(bottom_zone.anchor_bottom - 1.0) < 0.01,
				"TC20-15: BottomZone 锚定底部")
			_assert(abs(bottom_zone.offset_top - (-28.0)) < 0.01, "TC20-16: BottomZone offset_top == -28（y∈[1252,1280]）")

	game.queue_free()

# ── TC21: AtmosphereLayer + RainCurtain (L0 氛围层, #389) ──

func _test_tc21_atmosphere_layer() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		_assert(false, "TC21: Main.tscn failed to load")
		return

	var game = scene.instantiate()
	_assert(game.has_node("AtmosphereLayer"), "TC21-1: AtmosphereLayer node exists")
	var al = game.get_node_or_null("AtmosphereLayer")
	if al:
		_assert(al is CanvasLayer, "TC21-2: AtmosphereLayer is CanvasLayer")
		_assert(al.layer == 0, "TC21-3: AtmosphereLayer layer == 0")
	_assert(game.has_node("AtmosphereLayer/RainCurtain"), "TC21-4: RainCurtain instance exists")
	var rc = game.get_node_or_null("AtmosphereLayer/RainCurtain")
	if rc:
		_assert(rc.has_node("Particles"), "TC21-5: RainCurtain has Particles child")
		var p = rc.get_node_or_null("Particles")
		_assert(p is GPUParticles2D, "TC21-6: Particles is GPUParticles2D")
	game.queue_free()


# ── TC22: #393 组装 — BreakoutGrid / WaveController / WaveTransition 节点与接线契约 ──

func _test_tc22_assembly_nodes() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		_assert(false, "TC22: Main.tscn missing")
		return
	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		_assert(false, "TC22: Main.tscn failed to load")
		return
	var game = scene.instantiate()
	# 挂树触发 _ready（组注册/信号连接依赖 _ready；既有 TC 的 instantiate-only 模式无法断言组）
	(Engine.get_main_loop() as SceneTree).root.add_child(game)

	_assert(game.has_node("BreakoutGrid"), "TC22-1: BreakoutGrid node exists")
	_assert(game.has_node("WaveController"), "TC22-2: WaveController node exists")
	_assert(game.has_node("WaveTransition"), "TC22-3: WaveTransition node exists")

	var grid = game.get_node_or_null("BreakoutGrid")
	if grid:
		_assert(grid.is_in_group("breakout_grids"), "TC22-4: BreakoutGrid in group breakout_grids")
		_assert(grid.has_signal("brick_destroyed"), "TC22-5: grid has brick_destroyed signal")
		_assert(grid.has_signal("wall_cleared"), "TC22-6: grid has wall_cleared signal")
		_assert(grid.has_signal("wall_generated"), "TC22-7: grid has wall_generated signal")
		_assert(grid.has_method("generate_wave"), "TC22-8: grid has generate_wave")

	var wc = game.get_node_or_null("WaveController")
	if wc:
		_assert(wc.is_in_group("wave_controllers"), "TC22-9: WaveController in group wave_controllers")
		_assert(wc.has_method("start_first_wave"), "TC22-10: WaveController has start_first_wave")

	var wt = game.get_node_or_null("WaveTransition")
	if wt:
		_assert(wt is CanvasLayer, "TC22-11: WaveTransition is CanvasLayer")
		_assert(wt.layer >= 2 and wt.layer < 10,
			"TC22-12: WaveTransition layer 于 HUD(1) 与 PauseOverlay(10) 之间 (layer=%d)" % wt.layer)

	# 层序: HUD(1) < UpgradePickUI(2) < WaveTransition < PauseOverlay(10)
	var hud = game.get_node_or_null("GameHUD")
	var pause = game.get_node_or_null("PauseOverlay")
	if hud and wt:
		_assert(hud.layer < wt.layer, "TC22-13: HUD layer < WaveTransition layer")
	if wt and pause:
		_assert(wt.layer < pause.layer, "TC22-14: WaveTransition layer < PauseOverlay layer")

	# ── DESIGN §2.5 组装断言（#393）──
	if grid:
		_assert(abs(grid.position.y - 640.0) < 0.01,
			"TC22-15: BreakoutGrid position.y == 640 (got %f)" % grid.position.y)
		_assert(abs(float(grid.wall_y) - 640.0) < 0.01,
			"TC22-16: BreakoutGrid wall_y 导出 == GRID_WALL_Y(640) (got %f)" % float(grid.wall_y))
	if wc:
		var wc_script = wc.get_script()
		_assert(wc_script != null and String(wc_script.resource_path).ends_with("wave_controller.gd"),
			"TC22-26: WaveController 挂载 wave_controller.gd")
	_assert(game.has_node("GameOverScreen/CenterContainer/VBoxContainer/FailurePhraseLabel"),
		"TC22-17: GameOverScreen 为 ui_game_over.tscn 实例（FailurePhraseLabel 存在）")
	_assert(game.has_node("GameOverScreen/CenterContainer/VBoxContainer/RunStatsLabel"),
		"TC22-18: GameOverScreen 为 ui_game_over.tscn 实例（RunStatsLabel 存在）")
	var gos = game.get_node_or_null("GameOverScreen")
	if gos:
		_assert(gos is CanvasLayer, "TC22-19: GameOverScreen is CanvasLayer")
		_assert(gos.layer == 1, "TC22-20: GameOverScreen layer == 1 (got %d)" % gos.layer)
		_assert(gos.visible == false, "TC22-21: GameOverScreen 初始 visible == false")
		_assert(gos.name == "GameOverScreen", "TC22-22: 节点名保持 GameOverScreen（FSM NodePath 契约）")
	var upi = game.get_node_or_null("UpgradePickUI")
	if upi:
		_assert(upi.layer == 2, "TC22-23: UpgradePickUI.layer == 2（实例继承，无需 Main.tscn 覆盖）")
	if wt:
		_assert(wt.layer == 3, "TC22-24: WaveTransition.layer == WAVE_TRANSITION_LAYER(3) (got %d)" % wt.layer)
		_assert(wt.visible == false, "TC22-25: WaveTransition 初始 visible == false")

	game.queue_free()

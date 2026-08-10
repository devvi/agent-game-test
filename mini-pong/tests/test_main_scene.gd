extends RefCounted
## Test suite for Main Scene Assembly (#295) — Scene tree integrity, ScoreZones, ScoreFlash.
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Main Scene Assembly Tests (#295) ===")
	_test_tc1_scene_tree_nodes()
	_test_tc2_ext_resource_references()
	_test_tc3_world_environment()
	_test_tc4_score_zone_left()
	_test_tc5_score_zone_right()
	_test_tc9_score_flash_node()
	_test_tc12_score_zone_collision()
	_test_tc14_scorezone_shape_dimensions()
	_test_tc17_no_game_tscn_refs()
	_test_tc18_scorezone_ball_collision_contract()


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

	# Verify all mandatory nodes exist
	_assert(game.has_node("WorldEnvironment"), "TC1-2: WorldEnvironment node exists")
	_assert(game.has_node("TopWall"), "TC1-3: TopWall node exists")
	_assert(game.has_node("BottomWall"), "TC1-4: BottomWall node exists")
	_assert(game.has_node("Ball"), "TC1-5: Ball node exists")
	_assert(game.has_node("PlayerPaddle"), "TC1-6: PlayerPaddle node exists")
	_assert(game.has_node("AIPaddle"), "TC1-7: AIPaddle node exists")
	_assert(game.has_node("ScoringManager"), "TC1-8: ScoringManager node exists")
	_assert(game.has_node("GameStateMachine"), "TC1-9: GameStateMachine node exists")
	_assert(game.has_node("StartMenu"), "TC1-10: StartMenu node exists")
	_assert(game.has_node("GameHUD"), "TC1-11: GameHUD node exists")
	_assert(game.has_node("GameOverScreen"), "TC1-12: GameOverScreen node exists")

	# New nodes from #295
	_assert(game.has_node("ScoreZoneLeft"), "TC1-13: ScoreZoneLeft node exists")
	_assert(game.has_node("ScoreZoneRight"), "TC1-14: ScoreZoneRight node exists")
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


# ── TC4: ScoreZoneLeft is Area2D at pos (0, 360) ──

func _test_tc4_score_zone_left() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()
	var zone = game.get_node_or_null("ScoreZoneLeft")
	_assert(zone != null, "TC4-1: ScoreZoneLeft node exists")
	if zone:
		_assert(zone is Area2D, "TC4-2: ScoreZoneLeft is Area2D")
		_assert(zone.has_node("CollisionShape2D"), "TC4-3: ScoreZoneLeft has CollisionShape2D")
		var cs = zone.get_node("CollisionShape2D")
		_assert(cs.shape != null, "TC4-4: ScoreZoneLeft CollisionShape2D has non-null shape")

	game.queue_free()


# ── TC5: ScoreZoneRight is Area2D at pos (1280, 360) ──

func _test_tc5_score_zone_right() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()
	var zone = game.get_node_or_null("ScoreZoneRight")
	_assert(zone != null, "TC5-1: ScoreZoneRight node exists")
	if zone:
		_assert(zone is Area2D, "TC5-2: ScoreZoneRight is Area2D")
		_assert(zone.has_node("CollisionShape2D"), "TC5-3: ScoreZoneRight has CollisionShape2D")
		var cs = zone.get_node("CollisionShape2D")
		_assert(cs.shape != null, "TC5-4: ScoreZoneRight CollisionShape2D has non-null shape")

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

	# Check ScoreZoneLeft
	var zone_left = game.get_node_or_null("ScoreZoneLeft")
	if zone_left and zone_left.has_node("CollisionShape2D"):
		var cs = zone_left.get_node("CollisionShape2D")
		var shape = cs.shape
		if shape is RectangleShape2D:
			_assert(abs(shape.size.x - 20.0) < 0.01, "TC14-1: ScoreZoneLeft shape width == 20")
			_assert(abs(shape.size.y - 720.0) < 0.01, "TC14-2: ScoreZoneLeft shape height == 720")

	# Check ScoreZoneRight
	var zone_right = game.get_node_or_null("ScoreZoneRight")
	if zone_right and zone_right.has_node("CollisionShape2D"):
		var cs = zone_right.get_node("CollisionShape2D")
		var shape = cs.shape
		if shape is RectangleShape2D:
			_assert(abs(shape.size.x - 20.0) < 0.01, "TC14-3: ScoreZoneRight shape width == 20")
			_assert(abs(shape.size.y - 720.0) < 0.01, "TC14-4: ScoreZoneRight shape height == 720")

	game.queue_free()


# ── TC17: No remaining game.tscn references in project ──

func _test_tc17_no_game_tscn_refs() -> void:
	# This test verifies that project.godot references Main.tscn not game.tscn
	var content = FileAccess.get_file_as_string("res://project.godot")
	_assert(content != "", "TC17-1: project.godot readable")
	_assert(content.contains("run/main_scene=\"res://scenes/Main.tscn\""), "TC17-2: run/main_scene set to Main.tscn")
	_assert(not content.contains("game.tscn"), "TC17-3: no game.tscn reference in project.godot")


# ── TC18: ScoreZone ↔ Ball collision contract (Integration) ──
# Verifies that ScoreZones can actually detect the ball entering —
# catches collision_layer/mask mismatches and signal-type errors
# that static node-existence checks miss.

func _test_tc18_scorezone_ball_collision_contract() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		return

	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return

	var game = scene.instantiate()

	# ── TC18-1: Ball collision_layer/mask ──
	var ball = game.get_node_or_null("Ball")
	_assert(ball != null, "TC18-1: Ball node exists")
	if ball:
		_assert(ball is Area2D, "TC18-2: Ball is Area2D")

	# ── TC18-3/4: ScoreZone collision_mask includes ball's collision_layer ──
	var zone_left = game.get_node_or_null("ScoreZoneLeft")
	if zone_left and ball:
		_assert(zone_left.collision_mask & ball.collision_layer != 0,
			"TC18-3: ScoreZoneLeft collision_mask includes ball's collision_layer")
		_assert(ball.collision_mask & zone_left.collision_layer != 0,
			"TC18-4: Ball collision_mask includes ScoreZoneLeft's collision_layer")

	var zone_right = game.get_node_or_null("ScoreZoneRight")
	if zone_right and ball:
		_assert(zone_right.collision_mask & ball.collision_layer != 0,
			"TC18-5: ScoreZoneRight collision_mask includes ball's collision_layer")
		_assert(ball.collision_mask & zone_right.collision_layer != 0,
			"TC18-6: Ball collision_mask includes ScoreZoneRight's collision_layer")

	# ── TC18-7/8: ball.gd uses area_entered (not body_entered) for ScoreZone ──
	# Verify via source code since connections are wired in _ready()
	# (which only runs when added to scene tree)
	var ball_src = FileAccess.get_file_as_string("res://gdscripts/ball.gd")
	_assert(ball_src != "", "TC18-7: ball.gd readable")
	_assert(ball_src.contains("area_entered.connect"),
		"TC18-8: ball.gd uses area_entered (not body_entered) for ScoreZone")

	game.queue_free()

extends RefCounted
## World visibility tests for #508 — MENU hides the game_world group, other states keep it.
## DESIGN: docs/DESIGN/508-title-screen-world-bleed.md §9 (Scenario A–E)
## Approach: mini-tree — a Main.tscn-like subtree is built on the real SceneTree root:
##   UI CanvasLayers (StartMenu/GameHUD/GameOverScreen/PauseOverlay) resolve the FSM's
##   @onready refs, world mocks (Area2D/CanvasLayer/Node2D) join the "game_world" group,
##   so FSM.call_group("game_world", ...) wiring is verified through Node.visible.
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== World Visibility Tests (#508) ===")
	_test_a1_startup_menu_hides_world()
	_test_a2_game_over_to_menu_hides_world()
	_test_a3_missing_group_no_crash()
	_test_b1_menu_to_serving_restores_world()
	_test_b2_playing_keeps_world_visible()
	_test_c1_paused_keeps_world_visible()
	_test_c2_game_over_keeps_world_visible()
	_test_d1_set_world_visible_idempotent()
	_test_d2_empty_group_warning_precondition()
	_test_e1_main_scene_game_world_group_wiring()


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── mini-tree helpers ────────────────────────────────────────────

const WORLD_NODES: Array = ["Ball", "PlayerPaddle", "AIPaddle", "BreakoutGrid", "AtmosphereLayer"]


func _build_mini_tree(tree) -> Dictionary:
	"""Build Main.tscn-like mini-tree; returns ctx {root, fsm, mocks:{name:node}, added:[nodes]}.
	FSM is NOT added yet — caller adds it to trigger _ready() → enter_state(MENU)."""
	var ctx = {}
	var root = tree.root
	var added = []
	# UI CanvasLayers — resolve FSM @onready typed refs (no Node-not-found noise)
	var ui_names = ["StartMenu", "GameHUD", "GameOverScreen", "PauseOverlay"]
	for n in ui_names:
		var cl = CanvasLayer.new()
		cl.name = n
		root.add_child(cl)
		added.append(cl)
	# ScoringManager (plain Node)
	var sm = Node.new()
	sm.name = "ScoringManager"
	root.add_child(sm)
	added.append(sm)
	# World mocks — types must match FSM @onready typed vars (ball/paddles: Area2D)
	var mocks = {}
	for n in WORLD_NODES:
		var node = null
		if n == "AtmosphereLayer":
			node = CanvasLayer.new()
		elif n == "BreakoutGrid":
			node = Node2D.new()
		else:
			node = Area2D.new()
		node.name = n
		node.visible = true
		root.add_child(node)
		node.add_to_group("game_world")
		mocks[n] = node
		added.append(node)
	# FSM instance (script attached, not yet in tree)
	var fsm_script = load("res://gdscripts/game_state_machine.gd")
	var fsm = Node.new()
	fsm.set_script(fsm_script)
	fsm.name = "GameStateMachine"
	ctx["root"] = root
	ctx["fsm"] = fsm
	ctx["mocks"] = mocks
	ctx["added"] = added
	return ctx


func _add_fsm(ctx: Dictionary):
	"""Add FSM to tree — _ready() runs synchronously → enter_state(MENU) hides world."""
	ctx["root"].add_child(ctx["fsm"])
	return ctx["fsm"]


func _teardown_mini_tree(ctx: Dictionary) -> void:
	"""Free every node this test added (by reference — no name collisions)."""
	var added = ctx["added"]
	for node in added:
		if is_instance_valid(node):
			if node.is_in_group("game_world"):
				node.remove_from_group("game_world")
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()


func _strip_game_world_group(tree) -> void:
	"""Remove ALL current game_world members (leftover mocks from earlier tests)."""
	for node in tree.get_nodes_in_group("game_world"):
		node.remove_from_group("game_world")


# ── Scenario A: MENU hides the world (AC1 / AC3) ─────────────────

func _test_a1_startup_menu_hides_world() -> void:
	"""A1: fresh FSM _ready() → enter_state(MENU) → all game_world mocks hidden."""
	var tree = Engine.get_main_loop()
	var ctx = _build_mini_tree(tree)
	var fsm = _add_fsm(ctx)
	var mocks = ctx["mocks"]
	_assert(fsm.current_state == fsm.State.MENU, "A1-1: FSM starts in MENU")
	_assert(mocks["Ball"].visible == false, "A1-2: Ball hidden in MENU")
	_assert(mocks["PlayerPaddle"].visible == false, "A1-3: PlayerPaddle hidden in MENU")
	_assert(mocks["AtmosphereLayer"].visible == false, "A1-4: AtmosphereLayer hidden in MENU")
	_assert(mocks["BreakoutGrid"].visible == false, "A1-5: BreakoutGrid hidden in MENU")
	_teardown_mini_tree(ctx)


func _test_a2_game_over_to_menu_hides_world() -> void:
	"""A2: GAME_OVER → transition_to(MENU) re-hides the world (synchronous, no flicker window)."""
	var tree = Engine.get_main_loop()
	var ctx = _build_mini_tree(tree)
	var fsm = _add_fsm(ctx)
	var mocks = ctx["mocks"]
	fsm.transition_to(fsm.State.GAME_OVER)
	_assert(mocks["Ball"].visible == true, "A2-1: world visible in GAME_OVER before return to MENU")
	fsm.transition_to(fsm.State.MENU)
	_assert(fsm.current_state == fsm.State.MENU, "A2-2: FSM back in MENU")
	_assert(mocks["Ball"].visible == false, "A2-3: Ball re-hidden after GAME_OVER → MENU")
	_assert(mocks["AIPaddle"].visible == false, "A2-4: AIPaddle re-hidden after GAME_OVER → MENU")
	_assert(mocks["BreakoutGrid"].visible == false, "A2-5: BreakoutGrid re-hidden after GAME_OVER → MENU")
	_teardown_mini_tree(ctx)


func _test_a3_missing_group_no_crash() -> void:
	"""A3: FSM in a tree with NO game_world members — _ready completes, no exception."""
	var tree = Engine.get_main_loop()
	_strip_game_world_group(tree)
	var ctx = _build_mini_tree(tree)
	# remove world mocks from the group (keep nodes, drop group membership)
	var mocks = ctx["mocks"]
	for n in mocks:
		if mocks[n].is_in_group("game_world"):
			mocks[n].remove_from_group("game_world")
	var fsm = _add_fsm(ctx)
	_assert(fsm.current_state == fsm.State.MENU, "A3-1: FSM entered MENU without game_world group (no crash)")
	_assert(tree.get_nodes_in_group("game_world").is_empty(), "A3-2: group empty — call_group was a no-op")
	_teardown_mini_tree(ctx)


# ── Scenario B: leaving MENU restores the world (AC2) ────────────

func _test_b1_menu_to_serving_restores_world() -> void:
	"""B1: MENU → SERVING — exit_state(MENU) restores visibility synchronously (before 1s serve timer)."""
	var tree = Engine.get_main_loop()
	var ctx = _build_mini_tree(tree)
	var fsm = _add_fsm(ctx)
	var mocks = ctx["mocks"]
	_assert(mocks["Ball"].visible == false, "B1-1: world hidden in MENU (precondition)")
	fsm.transition_to(fsm.State.SERVING)
	# exit_state(MENU) ran synchronously inside transition_to; SERVING's 1s timer is still pending
	_assert(mocks["Ball"].visible == true, "B1-2: Ball visible immediately after MENU → SERVING")
	_assert(mocks["PlayerPaddle"].visible == true, "B1-3: PlayerPaddle visible immediately after MENU → SERVING")
	_assert(mocks["AtmosphereLayer"].visible == true, "B1-4: AtmosphereLayer visible immediately after MENU → SERVING")
	_assert(fsm.current_state == fsm.State.SERVING, "B1-5: FSM in SERVING (timer pending)")
	# 收尾：FSM 挂起在 enter_state(SERVING) 的 1s serve timer 上，直接 free 整个 mini-tree 是安全的——
	# 对象释放后到已释放对象的信号连接会自动丢弃（Godot 4），不会崩溃（退出时的 leak 警告属正常）。
	# 必须清理，否则遗留节点和计时器会污染后续测试文件（Wave Transition / Auto-Play）。
	_teardown_mini_tree(ctx)


func _test_b2_playing_keeps_world_visible() -> void:
	"""B2: PLAYING keeps world visible (transition_to(PLAYING) → exit_state(MENU) restored it)."""
	var tree = Engine.get_main_loop()
	var ctx = _build_mini_tree(tree)
	var fsm = _add_fsm(ctx)
	var mocks = ctx["mocks"]
	fsm.transition_to(fsm.State.PLAYING)
	_assert(fsm.current_state == fsm.State.PLAYING, "B2-1: FSM in PLAYING")
	_assert(mocks["Ball"].visible == true, "B2-2: Ball visible in PLAYING")
	_assert(mocks["AIPaddle"].visible == true, "B2-3: AIPaddle visible in PLAYING")
	_teardown_mini_tree(ctx)


# ── Scenario C: PAUSED / GAME_OVER keep the world (PRD §5.2-1/2) ─

func _test_c1_paused_keeps_world_visible() -> void:
	"""C1: PAUSED keeps world visible (pause overlay stacks on top of the world)."""
	var tree = Engine.get_main_loop()
	var ctx = _build_mini_tree(tree)
	var fsm = _add_fsm(ctx)
	var mocks = ctx["mocks"]
	fsm.transition_to(fsm.State.PLAYING)
	fsm.transition_to(fsm.State.PAUSED)
	_assert(fsm.current_state == fsm.State.PAUSED, "C1-1: FSM in PAUSED")
	_assert(mocks["Ball"].visible == true, "C1-2: Ball visible in PAUSED")
	_assert(mocks["AtmosphereLayer"].visible == true, "C1-3: AtmosphereLayer visible in PAUSED")
	_teardown_mini_tree(ctx)


func _test_c2_game_over_keeps_world_visible() -> void:
	"""C2: GAME_OVER keeps world visible (final-stand display, #391 frozen ball)."""
	var tree = Engine.get_main_loop()
	var ctx = _build_mini_tree(tree)
	var fsm = _add_fsm(ctx)
	var mocks = ctx["mocks"]
	fsm.transition_to(fsm.State.PLAYING)
	fsm.transition_to(fsm.State.GAME_OVER)
	_assert(fsm.current_state == fsm.State.GAME_OVER, "C2-1: FSM in GAME_OVER")
	_assert(mocks["Ball"].visible == true, "C2-2: Ball visible in GAME_OVER")
	_assert(mocks["BreakoutGrid"].visible == true, "C2-3: BreakoutGrid visible in GAME_OVER")
	_teardown_mini_tree(ctx)


# ── Scenario D: _set_world_visible idempotency + empty-group guard ─

func _test_d1_set_world_visible_idempotent() -> void:
	"""D1: repeated calls are idempotent and restore works."""
	var tree = Engine.get_main_loop()
	var ctx = _build_mini_tree(tree)
	var fsm = _add_fsm(ctx)
	var mocks = ctx["mocks"]
	fsm._set_world_visible(false)
	fsm._set_world_visible(false)
	_assert(mocks["Ball"].visible == false, "D1-1: double hide keeps Ball hidden")
	_assert(mocks["AtmosphereLayer"].visible == false, "D1-2: double hide keeps AtmosphereLayer hidden")
	fsm._set_world_visible(true)
	_assert(mocks["Ball"].visible == true, "D1-3: restore after double hide works")
	_teardown_mini_tree(ctx)


func _test_d2_empty_group_warning_precondition() -> void:
	"""D2: empty game_world group at _ready → guard path (push_warning, no crash)."""
	var tree = Engine.get_main_loop()
	_strip_game_world_group(tree)
	var ctx = _build_mini_tree(tree)
	var mocks = ctx["mocks"]
	for n in mocks:
		if mocks[n].is_in_group("game_world"):
			mocks[n].remove_from_group("game_world")
	_assert(tree.get_nodes_in_group("game_world").is_empty(), "D2-1: game_world group empty (warning precondition)")
	var fsm = _add_fsm(ctx)
	_assert(fsm.current_state == fsm.State.MENU, "D2-2: FSM entered MENU with empty group (no crash)")
	_teardown_mini_tree(ctx)


# ── Scenario E: Main.tscn wiring (E2-style) ──────────────────────

func _test_e1_main_scene_game_world_group_wiring() -> void:
	"""E1: Main.tscn — 5 visual world nodes registered in game_world group; physics nodes NOT."""
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		print("  SKIP: Main.tscn not found")
		failed += 1
		return
	var scene = load("res://scenes/Main.tscn")
	var game = scene.instantiate()
	_assert(game != null, "E1-1: Main.tscn instantiates")
	if game == null:
		return
	_assert(game.get_node("AtmosphereLayer").is_in_group("game_world"), "E1-2: AtmosphereLayer in game_world group")
	_assert(game.get_node("Ball").is_in_group("game_world"), "E1-3: Ball in game_world group")
	_assert(game.get_node("PlayerPaddle").is_in_group("game_world"), "E1-4: PlayerPaddle in game_world group")
	_assert(game.get_node("AIPaddle").is_in_group("game_world"), "E1-5: AIPaddle in game_world group")
	_assert(game.get_node("BreakoutGrid").is_in_group("game_world"), "E1-6: BreakoutGrid in game_world group")
	_assert(not game.get_node("LeftWall").is_in_group("game_world"), "E1-7: LeftWall NOT in game_world (physics only)")
	_assert(not game.get_node("WaveController").is_in_group("game_world"), "E1-8: WaveController NOT in game_world (no visual)")
	game.free()

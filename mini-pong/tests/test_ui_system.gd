extends RefCounted
## Test suite for UI System (#292) — Menus / Scoring / End Screen.
## Runs under godot --headless --script via run_tests.gd.
##
## Tests the three CanvasLayer scripts (start_menu.gd, game_hud.gd, game_over_screen.gd)
## and their scene files. Follows the test case descriptions from
## docs/DESIGN/292-ui-system.md §10.

var passed: int = 0
var failed: int = 0

# ── Constants from DESIGN doc ──
const COLOR_PLAYER: Color = Color(0.29, 0.56, 0.85, 1.0)   # #4a90d9
const COLOR_AI: Color     = Color(1.0, 0.2, 0.33, 1.0)      # #ff3355

# ── Signal capture state (Pattern 11: member vars, not lambda closures) ──
var _captured_hud_player_text: String = ""
var _captured_hud_ai_text: String = ""
var _captured_winner_text: String = ""
var _captured_winner_color: Color = Color.WHITE


# ── Signal handlers for HUD ──
func _on_hud_score_changed(p_score: int, a_score: int) -> void:
	_captured_hud_player_text = "Player: " + str(p_score)
	_captured_hud_ai_text = "AI: " + str(a_score)


func run() -> void:
	print("\n=== UI System Tests (#292) ===")
	_test_tc1_script_compilation()
	_test_tc2_script_base_classes()
	_test_tc3_headless_safety()
	_test_tc4_scene_loading()
	_test_tc5_start_menu_labels()
	_test_tc6_game_hud_labels()
	_test_tc7_game_over_labels()
	_test_tc8_start_menu_transition()
	_test_tc9_hud_signal_update()
	_test_tc10_game_over_signal_update()
	_test_tc11_winner_text_color()
	_test_tc12_invalid_winner()
	_test_tc13_debounce_transition()
	_test_tc14_game_over_restart()
	_test_tc15_game_tscn_integration()
	_test_tc16_version_label()


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


## Load a script resource, returning null on failure.
func _load_script(path: String):
	var script = load(path)
	if script == null:
		print("  SKIP: %s not found" % path)
	return script


## Instantiate a CanvasLayer by loading its script and setting it on a Node.
## Uses Node.new() + set_script() pattern (Pattern 2 from godot-headless-test-patterns).
func _make_canvas_layer(script_path: String):
	var script = _load_script(script_path)
	if script == null:
		return null
	var node = CanvasLayer.new()
	node.set_script(script)
	return node


## Create a mock GameManager node with the same API as the real autoload.
func _make_mock_game_manager():
	var gm = Node.new()
	gm.set_script(load("res://gdscripts/game_manager.gd"))
	gm.name = "GameManager"
	return gm


# ── TC1: Compilation — All Scripts Parse Without Errors ──

func _test_tc1_script_compilation() -> void:
	# Verify that each script file exists and is valid GDScript
	var scripts := {
		"start_menu": "res://gdscripts/start_menu.gd",
		"game_hud": "res://gdscripts/game_hud.gd",
		"game_over_screen": "res://gdscripts/game_over_screen.gd",
	}
	for name in scripts:
		var path: String = scripts[name]
		var script = ResourceLoader.exists(path)
		_assert(script, "TC1-%s: %s exists" % [name, path])
		if script:
			var loaded = load(path)
			_assert(loaded != null, "TC1-%s: %s loads without parse errors" % [name, path])


# ── TC2: All Scripts Extend Correct Base Class ──

func _test_tc2_script_base_classes() -> void:
	var scripts := {
		"start_menu": "res://gdscripts/start_menu.gd",
		"game_hud": "res://gdscripts/game_hud.gd",
		"game_over_screen": "res://gdscripts/game_over_screen.gd",
	}
	for name in scripts:
		var path: String = scripts[name]
		if not ResourceLoader.exists(path):
			_assert(false, "TC2-%s: script missing" % name)
			continue
		var node = _make_canvas_layer(path)
		_assert(node != null, "TC2-%s: instantiates as CanvasLayer" % name)
		_assert(node is CanvasLayer, "TC2-%s: is CanvasLayer type" % name)


# ── TC3: Headless Safety — No Crashes on get_tree()==null ──

func _test_tc3_headless_safety() -> void:
	# Test that start_menu.gd _ready() doesn't crash in headless (get_tree()==null)
	var start_menu = _make_canvas_layer("res://gdscripts/start_menu.gd")
	if start_menu == null:
		_assert(false, "TC3-1: start_menu script not found")
		return
	# _ready() should not crash even with null get_tree() — guarded internally
	_assert(true, "TC3-1: start_menu created without crash")

	var game_over = _make_canvas_layer("res://gdscripts/game_over_screen.gd")
	if game_over == null:
		_assert(false, "TC3-2: game_over script not found")
		return
	_assert(true, "TC3-2: game_over created without crash")

	# Call _on_match_over in headless — should guard against null get_tree()
	if game_over.has_method("_on_match_over"):
		game_over._on_match_over("player")
		_assert(true, "TC3-3: _on_match_over(player) did not crash in headless")
	else:
		_assert(false, "TC3-3: _on_match_over method missing")


# ── TC4: Scene Loading — All Three Scenes Instantiate ──

func _test_tc4_scene_loading() -> void:
	var scene_paths := {
		"start_menu": "res://scenes/ui_start_menu.tscn",
		"game_hud": "res://scenes/ui_game_hud.tscn",
		"game_over": "res://scenes/ui_game_over.tscn",
	}
	for name in scene_paths:
		var path: String = scene_paths[name]
		if not ResourceLoader.exists(path):
			_assert(false, "TC4-%s: %s not found" % [name, path])
			continue
		var packed = load(path)
		_assert(packed != null, "TC4-%s: %s loads as PackedScene" % [name, path])
		if packed == null:
			continue
		var instance = packed.instantiate()
		_assert(instance != null, "TC4-%s: %s instantiates" % [name, path])
		_assert(instance is CanvasLayer, "TC4-%s: instance is CanvasLayer" % name)
		instance.queue_free()


# ── TC5: StartMenu Labels Exist ──

func _test_tc5_start_menu_labels() -> void:
	if not ResourceLoader.exists("res://scenes/ui_start_menu.tscn"):
		_assert(false, "TC5: scene missing")
		return
	var packed = load("res://scenes/ui_start_menu.tscn")
	var instance = packed.instantiate()

	_assert(instance.visible == true, "TC5-1: StartMenu starts visible=true")

	# Verify title label
	var title: Label = instance.get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
	_assert(title != null, "TC5-2: TitleLabel exists")
	if title:
		_assert(title.text == "Mini Pong", "TC5-3: TitleLabel text is 'Mini Pong'")
		_assert(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "TC5-4: TitleLabel centered")
		_assert(title.get("theme_override_font_sizes/font_size") >= 48, "TC5-5: TitleLabel font_size >= 48")

	# Verify prompt label
	var prompt: Label = instance.get_node_or_null("CenterContainer/VBoxContainer/PromptLabel")
	_assert(prompt != null, "TC5-6: PromptLabel exists")
	if prompt:
		_assert(prompt.text == "按 SPACE 开始", "TC5-7: PromptLabel text correct")
		_assert(prompt.get("theme_override_font_sizes/font_size") >= 24, "TC5-8: PromptLabel font_size >= 24")

	instance.queue_free()


# ── TC6: GameHUD Labels Exist ──

func _test_tc6_game_hud_labels() -> void:
	if not ResourceLoader.exists("res://scenes/ui_game_hud.tscn"):
		_assert(false, "TC6: scene missing")
		return
	var packed = load("res://scenes/ui_game_hud.tscn")
	var instance = packed.instantiate()

	_assert(instance.visible == false, "TC6-1: GameHUD starts visible=false")

	var player_lbl: Label = instance.get_node_or_null("MarginContainer/HBoxContainer/PlayerScoreLabel")
	_assert(player_lbl != null, "TC6-2: PlayerScoreLabel exists")
	if player_lbl:
		_assert(player_lbl.text == "Player: 0", "TC6-3: PlayerScoreLabel initial text")
		_assert(player_lbl.get("theme_override_font_sizes/font_size") >= 24, "TC6-4: PlayerScoreLabel font_size >= 24")

	var ai_lbl: Label = instance.get_node_or_null("MarginContainer/HBoxContainer/AIScoreLabel")
	_assert(ai_lbl != null, "TC6-5: AIScoreLabel exists")
	if ai_lbl:
		_assert(ai_lbl.text == "AI: 0", "TC6-6: AIScoreLabel initial text")
		_assert(ai_lbl.get("theme_override_font_sizes/font_size") >= 24, "TC6-7: AIScoreLabel font_size >= 24")

	instance.queue_free()


# ── TC7: GameOverScreen Labels Exist ──

func _test_tc7_game_over_labels() -> void:
	if not ResourceLoader.exists("res://scenes/ui_game_over.tscn"):
		_assert(false, "TC7: scene missing")
		return
	var packed = load("res://scenes/ui_game_over.tscn")
	var instance = packed.instantiate()

	_assert(instance.visible == false, "TC7-1: GameOverScreen starts visible=false")

	var winner_lbl: Label = instance.get_node_or_null("CenterContainer/VBoxContainer/WinnerLabel")
	_assert(winner_lbl != null, "TC7-2: WinnerLabel exists")
	if winner_lbl:
		_assert(winner_lbl.text == "", "TC7-3: WinnerLabel initially empty")
		_assert(winner_lbl.get("theme_override_font_sizes/font_size") >= 48, "TC7-4: WinnerLabel font_size >= 48")

	var restart_lbl: Label = instance.get_node_or_null("CenterContainer/VBoxContainer/RestartPromptLabel")
	_assert(restart_lbl != null, "TC7-5: RestartPromptLabel exists")
	if restart_lbl:
		_assert(restart_lbl.text == "按 SPACE 重新开始", "TC7-6: RestartPromptLabel text correct")
		_assert(restart_lbl.get("theme_override_font_sizes/font_size") >= 24, "TC7-7: RestartPromptLabel font_size >= 24")

	instance.queue_free()


# ── TC8: StartMenu Transition — hide_menu() + sibling toggling ──

func _test_tc8_start_menu_transition() -> void:
	var script = _load_script("res://gdscripts/start_menu.gd")
	if script == null:
		_assert(false, "TC8: script not found")
		return

	var start_menu = _make_canvas_layer("res://gdscripts/start_menu.gd")
	if start_menu == null:
		_assert(false, "TC8: instantiation failed")
		return

	_assert(start_menu.has_method("hide_menu"), "TC8-1: has hide_menu method")
	_assert(start_menu.has_method("show_menu"), "TC8-2: has show_menu method")

	# Test hide_menu sets visible = false
	start_menu.visible = true
	start_menu.hide_menu()
	_assert(start_menu.visible == false, "TC8-3: visible=false after hide_menu")

	# Test show_menu sets visible = true
	start_menu._transitioning = false
	start_menu.show_menu()
	_assert(start_menu.visible == true, "TC8-4: visible=true after show_menu")


# ── TC9: HUD Signal Update — label text changes on score update ──

func _test_tc9_hud_signal_update() -> void:
	var script = _load_script("res://gdscripts/game_hud.gd")
	if script == null:
		_assert(false, "TC9: script not found")
		return

	var hud = _make_canvas_layer("res://gdscripts/game_hud.gd")
	if hud == null:
		_assert(false, "TC9: instantiation failed")
		return

	_assert(hud.has_method("_on_score_changed"), "TC9-1: has _on_score_changed method")

	# Test direct method call with various scores
	hud._on_score_changed(0, 0)
	# Labels updated via the method
	if hud.get_node_or_null("MarginContainer/HBoxContainer/PlayerScoreLabel"):
		_assert(hud.get_node("MarginContainer/HBoxContainer/PlayerScoreLabel").text == "Player: 0", "TC9-2: score 0,0 → Player: 0")
	if hud.get_node_or_null("MarginContainer/HBoxContainer/AIScoreLabel"):
		_assert(hud.get_node("MarginContainer/HBoxContainer/AIScoreLabel").text == "AI: 0", "TC9-3: score 0,0 → AI: 0")

	hud._on_score_changed(5, 3)
	if hud.get_node_or_null("MarginContainer/HBoxContainer/PlayerScoreLabel"):
		_assert(hud.get_node("MarginContainer/HBoxContainer/PlayerScoreLabel").text == "Player: 5", "TC9-4: score 5,3 → Player: 5")
	if hud.get_node_or_null("MarginContainer/HBoxContainer/AIScoreLabel"):
		_assert(hud.get_node("MarginContainer/HBoxContainer/AIScoreLabel").text == "AI: 3", "TC9-5: score 5,3 → AI: 3")


# ── TC10: GameOverScreen Signal Update ──

func _test_tc10_game_over_signal_update() -> void:
	var script = _load_script("res://gdscripts/game_over_screen.gd")
	if script == null:
		_assert(false, "TC10: script not found")
		return

	var game_over = _make_canvas_layer("res://gdscripts/game_over_screen.gd")
	if game_over == null:
		_assert(false, "TC10: instantiation failed")
		return

	_assert(game_over.has_method("_on_match_over"), "TC10-1: has _on_match_over method")

	# Test that we can call _on_match_over without crashing
	game_over._on_match_over("player")
	_assert(true, "TC10-2: _on_match_over(player) called without error")

	game_over._on_match_over("ai")
	_assert(true, "TC10-3: _on_match_over(ai) called without error")


# ── TC11: Winner Text — Correct Color and Text ──

func _test_tc11_winner_text_color() -> void:
	var script = _load_script("res://gdscripts/game_over_screen.gd")
	if script == null:
		_assert(false, "TC11: script not found")
		return

	var game_over = _make_canvas_layer("res://gdscripts/game_over_screen.gd")
	if game_over == null:
		_assert(false, "TC11: instantiation failed")
		return

	# Check constants exist
	_assert(game_over.get("COLOR_PLAYER") != null, "TC11-1: COLOR_PLAYER constant exists")
	_assert(game_over.get("COLOR_AI") != null, "TC11-2: COLOR_AI constant exists")

	var color_player: Color = game_over.COLOR_PLAYER
	var color_ai: Color = game_over.COLOR_AI

	_assert(abs(color_player.r - 0.29) < 0.01, "TC11-3: COLOR_PLAYER R ≈ 0.29")
	_assert(abs(color_player.g - 0.56) < 0.01, "TC11-4: COLOR_PLAYER G ≈ 0.56")
	_assert(abs(color_player.b - 0.85) < 0.01, "TC11-5: COLOR_PLAYER B ≈ 0.85")

	_assert(abs(color_ai.r - 1.0) < 0.01, "TC11-6: COLOR_AI R ≈ 1.0")
	_assert(abs(color_ai.g - 0.2) < 0.01, "TC11-7: COLOR_AI G ≈ 0.2")
	_assert(abs(color_ai.b - 0.33) < 0.01, "TC11-8: COLOR_AI B ≈ 0.33")

	_assert(game_over.get("TEXT_PLAYER_WIN") != null, "TC11-9: TEXT_PLAYER_WIN constant exists")
	_assert(game_over.get("TEXT_AI_WIN") != null, "TC11-10: TEXT_AI_WIN constant exists")
	_assert(game_over.TEXT_PLAYER_WIN == "YOU WIN!", "TC11-11: TEXT_PLAYER_WIN correct")
	_assert(game_over.TEXT_AI_WIN == "AI WINS!", "TC11-12: TEXT_AI_WIN correct")


# ── TC12: Invalid Winner — Guard Clause Returns Early ──

func _test_tc12_invalid_winner() -> void:
	var script = _load_script("res://gdscripts/game_over_screen.gd")
	if script == null:
		_assert(false, "TC12: script not found")
		return

	var game_over = _make_canvas_layer("res://gdscripts/game_over_screen.gd")
	if game_over == null:
		_assert(false, "TC12: instantiation failed")
		return

	# Call with invalid winner — should not crash
	var visible_before = game_over.visible
	game_over._on_match_over("invalid")
	_assert(game_over.visible == visible_before, "TC12-1: visible unchanged for invalid winner")


# ── TC13: Debounce — _transitioning prevents double transition ──

func _test_tc13_debounce_transition() -> void:
	var start_menu = _make_canvas_layer("res://gdscripts/start_menu.gd")
	if start_menu == null:
		_assert(false, "TC13: script not found")
		return

	_assert(start_menu.get("_transitioning") != null, "TC13-1: _transitioning flag exists")

	start_menu._transitioning = true
	start_menu.visible = true

	# With _transitioning=true, _on_start_pressed should be guarded
	if start_menu.has_method("_on_start_pressed"):
		start_menu._on_start_pressed()
		_assert(start_menu.get("_transitioning") == true, "TC13-2: _on_start_pressed called while _transitioning=true")
	else:
		_assert(false, "TC13-2: _on_start_pressed method missing")


# ── TC14: GameOver Restart Flow ──

func _test_tc14_game_over_restart() -> void:
	var game_over = _make_canvas_layer("res://gdscripts/game_over_screen.gd")
	if game_over == null:
		_assert(false, "TC14: script not found")
		return

	_assert(game_over.has_method("_on_restart_pressed"), "TC14-1: has _on_restart_pressed method")
	_assert(game_over.has_method("hide_menu") or game_over.has_method("_kill_tweens"), "TC14-2: has tween cleanup method")


# ── TC15: Main.tscn Integration — CanvasLayers Present ──

func _test_tc15_game_tscn_integration() -> void:
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		_assert(false, "TC15: Main.tscn missing")
		return
	var packed = load("res://scenes/Main.tscn")
	if packed == null:
		_assert(false, "TC15: Main.tscn failed to load")
		return
	var instance = packed.instantiate()
	_assert(instance != null, "TC15-1: Main.tscn instantiates")

	# Check each CanvasLayer exists
	var start_menu: CanvasLayer = instance.get_node_or_null("StartMenu")
	_assert(start_menu != null, "TC15-2: StartMenu CanvasLayer exists")
	if start_menu:
		_assert(start_menu is CanvasLayer, "TC15-3: StartMenu is CanvasLayer")
		_assert(start_menu.visible == true, "TC15-4: StartMenu visible=true initially")
		_assert(start_menu.layer == 1, "TC15-5: StartMenu layer=1")

	var game_hud: CanvasLayer = instance.get_node_or_null("GameHUD")
	_assert(game_hud != null, "TC15-6: GameHUD CanvasLayer exists")
	if game_hud:
		_assert(game_hud is CanvasLayer, "TC15-7: GameHUD is CanvasLayer")
		_assert(game_hud.visible == false, "TC15-8: GameHUD visible=false initially")
		_assert(game_hud.layer == 1, "TC15-9: GameHUD layer=1")

	var game_over: CanvasLayer = instance.get_node_or_null("GameOverScreen")
	_assert(game_over != null, "TC15-10: GameOverScreen CanvasLayer exists")
	if game_over:
		_assert(game_over is CanvasLayer, "TC15-11: GameOverScreen is CanvasLayer")
		_assert(game_over.visible == false, "TC15-12: GameOverScreen visible=false initially")
		_assert(game_over.layer == 1, "TC15-13: GameOverScreen layer=1")

	instance.queue_free()

# ── TC16: StartMenu VersionLabel — version text v1.0.0 (bottom-left) ──
# DESIGN: docs/DESIGN/358-title-screen-version.md §9 Scenario B

func _test_tc16_version_label() -> void:
	if not ResourceLoader.exists("res://scenes/ui_start_menu.tscn"):
		_assert(false, "TC16: scene missing")
		return
	var packed = load("res://scenes/ui_start_menu.tscn")
	if packed == null:
		_assert(false, "TC16: ui_start_menu.tscn failed to load")
		return
	var instance = packed.instantiate()

	# B-1: VersionLabel node exists
	var version_label = instance.get_node_or_null("VersionLabel")
	_assert(version_label != null, "TC16-1: VersionLabel exists")
	# B-2: node is a Label
	_assert(version_label is Label, "TC16-2: VersionLabel is Label type")

	var CONSTS = load("res://gdscripts/constants.gd")

	if version_label:
		# B-3: static text from .tscn (bare instantiate does not run _ready())
		_assert(version_label.text == "v1.0.0", "TC16-3: VersionLabel static text is 'v1.0.0'")
		# B-4: font_size in spec range (use theme override getter — #346 lesson)
		var fs = version_label.get("theme_override_font_sizes/font_size")
		_assert(fs >= 12, "TC16-4: VersionLabel font_size >= 12 (got %s)" % str(fs))
		# B-5: bottom-left anchor
		_assert(abs(version_label.anchor_left - 0.0) < 0.001 and abs(version_label.anchor_top - 1.0) < 0.001,
			"TC16-5: VersionLabel anchored bottom-left")
		# B-7: neon blue modulate (#4a90d9 @ 60% alpha)
		_assert(abs(version_label.modulate.r - 0.29) < 0.01, "TC16-6: VersionLabel modulate R ~ 0.29")
		_assert(abs(version_label.modulate.g - 0.56) < 0.01, "TC16-7: VersionLabel modulate G ~ 0.56")
		_assert(abs(version_label.modulate.b - 0.85) < 0.01, "TC16-8: VersionLabel modulate B ~ 0.85")

		# B-6: entering the tree triggers _ready() -> text set from GameConstants
		var main_loop = Engine.get_main_loop()
		var root = main_loop.root
		root.add_child(instance)
		_assert(version_label.text == CONSTS.GAME_VERSION,
			"TC16-9: _ready() sets text from GameConstants.GAME_VERSION")
		_assert(version_label.text == "v1.0.0", "TC16-10: version text is 'v1.0.0' after _ready()")

	instance.queue_free()

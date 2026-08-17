extends RefCounted
## Test suite for PauseOverlay score/wave display (#513) — show_overlay() reads GameManager state.
## Design: docs/DESIGN/513-pause-score-wave.md §9
## Parent Issue: #513

var passed: int = 0
var failed: int = 0

func run() -> void:
	print("\n=== Pause Overlay Tests (#513) ===")
	_test_a1_score_fill()
	_test_a2_wave_fill()
	_test_a3_neon_applied()
	_test_b1_frozen_while_paused()
	_test_b2_refresh_on_reshow()
	_test_c1_missing_gm_placeholder()
	_test_c2_warn_once()
	_test_e1_hide_no_residue()
	_test_e2_reshow_new_values()
	print("Passed: %d, Failed: %d" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── Helpers ──

func _make_overlay() -> Array:
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.set_script(load("res://gdscripts/pause_overlay.gd"))
	overlay.name = "PauseOverlay"
	# 镜像 Main.tscn PauseOverlay 子树（ColorRect/Label/ScoreLabel/WaveLabel）——
	# 脚本 @onready 依赖这 4 个子节点（DESIGN §3.1：@onready + 场景同步变更）
	var color_rect: ColorRect = ColorRect.new()
	color_rect.name = "ColorRect"
	overlay.add_child(color_rect)
	var title_label: Label = Label.new()
	title_label.name = "Label"
	overlay.add_child(title_label)
	var score_label: Label = Label.new()
	score_label.name = "ScoreLabel"
	overlay.add_child(score_label)
	var wave_label: Label = Label.new()
	wave_label.name = "WaveLabel"
	overlay.add_child(wave_label)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(overlay)
	else:
		overlay.set("score_label", score_label)
		overlay.set("wave_label", wave_label)
	return [overlay, score_label, wave_label]


func _make_gm_mock(player_score: int, ai_score: int, wave_index: int) -> Node:
	var mock_script = GDScript.new()
	mock_script.source_code = "extends Node\nvar player_score: int = 0\nvar ai_score: int = 0\nvar wave_index: int = 0\n"
	mock_script.reload()
	var mock: Node = Node.new()
	mock.set_script(mock_script)
	mock.set("player_score", player_score)
	mock.set("ai_score", ai_score)
	mock.set("wave_index", wave_index)
	return mock


func _detach_real_gm() -> Node:
	# 真实 GameManager autoload（lazy `*` 前缀）节点常驻 /root/GameManager；
	# pause_overlay.gd 走树查找，测试临时摘除节点以模拟「GameManager 缺失」（DESIGN §9 C1/C2）。
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var root_gm: Node = null
	if tree != null and tree.root != null:
		root_gm = tree.root.get_node_or_null("GameManager")
		if root_gm != null:
			tree.root.remove_child(root_gm)
	return root_gm


func _reattach_real_gm(root_gm: Node) -> void:
	if root_gm == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and root_gm.get_parent() == null:
		tree.root.add_child(root_gm)


func _cleanup(overlay: CanvasLayer) -> void:
	if overlay == null:
		return
	if overlay.get_parent() != null:
		overlay.get_parent().remove_child(overlay)
	overlay.queue_free()


# ── Tests ──

func _test_a1_score_fill() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var score_label: Label = result[1]
	var mock: Node = _make_gm_mock(7, 3, 4)
	overlay.set("game_manager", mock)
	overlay.call("show_overlay")
	_assert(score_label.text == "Player: 7   AI: 3", "A1: score_label filled from GameManager state")
	_cleanup(overlay)


func _test_a2_wave_fill() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var wave_label: Label = result[2]
	var mock: Node = _make_gm_mock(7, 3, 4)
	overlay.set("game_manager", mock)
	overlay.call("show_overlay")
	_assert(wave_label.text == "第 4 波", "A2: wave_label filled from GameManager state")
	_cleanup(overlay)


func _test_a3_neon_applied() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var score_label: Label = result[1]
	var mock: Node = _make_gm_mock(7, 3, 4)
	overlay.set("game_manager", mock)
	overlay.call("show_overlay")
	_assert(score_label.has_theme_color_override("font_color"), "A3: neon font_color override applied")
	_cleanup(overlay)


func _test_b1_frozen_while_paused() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var score_label: Label = result[1]
	var mock: Node = _make_gm_mock(5, 2, 1)
	overlay.set("game_manager", mock)
	overlay.call("show_overlay")
	mock.set("player_score", 99)
	_assert(score_label.text == "Player: 5   AI: 2", "B1: label frozen after GM change (no signal subscription)")
	_cleanup(overlay)


func _test_b2_refresh_on_reshow() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var score_label: Label = result[1]
	var wave_label: Label = result[2]
	var mock: Node = _make_gm_mock(5, 2, 1)
	overlay.set("game_manager", mock)
	overlay.call("show_overlay")
	mock.set("player_score", 8)
	mock.set("wave_index", 3)
	overlay.call("show_overlay")
	_assert(score_label.text == "Player: 8   AI: 2", "B2: score refreshes on reshow")
	_assert(wave_label.text == "第 3 波", "B2: wave refreshes on reshow")
	_cleanup(overlay)


func _test_c1_missing_gm_placeholder() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var score_label: Label = result[1]
	var wave_label: Label = result[2]
	var root_gm: Node = _detach_real_gm()
	overlay.call("show_overlay")
	_assert(score_label.text == "—", "C1: score placeholder when GM missing")
	_assert(wave_label.text == "—", "C1: wave placeholder when GM missing")
	_reattach_real_gm(root_gm)
	_cleanup(overlay)


func _test_c2_warn_once() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var root_gm: Node = _detach_real_gm()
	overlay.call("show_overlay")
	_assert(overlay.get("_warned_gm") == true, "C2: _warned_gm set on missing GM")
	overlay.call("show_overlay")
	_assert(overlay.get("_warned_gm") == true, "C2: second show_overlay with missing GM does not crash")
	_reattach_real_gm(root_gm)
	_cleanup(overlay)


func _test_e1_hide_no_residue() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var mock: Node = _make_gm_mock(1, 1, 1)
	overlay.set("game_manager", mock)
	overlay.call("show_overlay")
	overlay.call("hide_overlay")
	_assert(overlay.visible == false, "E1: overlay hidden after hide_overlay")
	_cleanup(overlay)


func _test_e2_reshow_new_values() -> void:
	var result: Array = _make_overlay()
	var overlay: CanvasLayer = result[0]
	var score_label: Label = result[1]
	var mock: Node = _make_gm_mock(2, 3, 2)
	overlay.set("game_manager", mock)
	overlay.call("show_overlay")
	overlay.call("hide_overlay")
	mock.set("player_score", 9)
	overlay.call("show_overlay")
	_assert(score_label.text == "Player: 9   AI: 3", "E2: score refreshed after hide/reshow")
	_cleanup(overlay)

extends RefCounted
## Neon HUD test suite (#392) — DESIGN docs/DESIGN/392-neon-ui-upgrade.md §10 Scenarios A–F。
## Covers: 霓虹样式（描边+微投影）/ 信号接线（score_changed/brick_scored/pierce_scored/wave_started）/
## 剩余砖数（mock BreakoutGrid #414 契约）/ 容错（#384 未接线）/ 布局安全区 / 无轮询（AC5）。
## Uses the REAL GameManager autoload (reset between tests) + mock BreakoutGrid siblings。
## Runs under run_tests.gd (_run_async — 帧末 deferred 与布局需要 await)。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const NeonStyle = preload("res://gdscripts/ui_neon_style.gd")

var _root
var _gm


func run() -> void:
	print("\n=== Neon HUD Tests (#392) ===")
	_root = (Engine.get_main_loop() as SceneTree).root
	# 固定竖屏视口（headless --script 默认 root 窗口为 64×64，非项目 720×1280）
	_root.size = Vector2i(720, 1280)
	await _wait(0.05)   # 布局按新视口尺寸重排
	_gm = GameManager
	_gm.reset_match()

	# Scenario A: 霓虹样式应用 (AC1)
	_test_ta1_neon_apply()
	await _test_ta2_hud_labels_neon()
	_test_ta3_no_custom_font()

	# Scenario B: 信号接线 (game_manager × game_hud)
	await _test_tb3_score_changed_updates()
	await _test_tb4_brick_scored_updates()
	await _test_tb5_wave_started_info()
	await _test_tb6_old_gm_no_crash()

	# Scenario C: 剩余砖数（mock grid）
	await _test_tc1_brick_destroyed_remaining()
	await _test_tc2_wall_cleared_zero()
	await _test_tc3_wall_generated()
	await _test_tc4_fallback_deferred()

	# Scenario D: 容错（#384 未接线 / #393 未组装）
	await _test_td1_no_grid_placeholder()
	await _test_td2_grid_no_wall_generated()

	# Scenario E: 布局安全区与场景组装 (AC2/AC4)
	await _test_te1_safety_zones()
	await _test_te2_main_tscn_instance()

	# Scenario F: 无轮询与常量 (AC5)
	_test_tf1_no_polling()
	_test_tf2_hud_constants()

	print("  Neon HUD: %d passed, %d failed" % [passed, failed])


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout


func _make_hud() -> CanvasLayer:
	var packed = load("res://scenes/ui_game_hud.tscn")
	if packed == null:
		return null
	return packed.instantiate()


func _make_mock_grid(with_wall_generated: bool) -> Node:
	## Mock BreakoutGrid — #414 契约子集：brick_destroyed / wall_cleared /
	## wall_generated（可选）+ remaining_bricks 属性。with_wall_generated=false
	## 模拟 #384 半实现 grid（无新墙信号，回退路径 TC-4）。
	var code = GDScript.new()
	if with_wall_generated:
		code.source_code = """extends Node
## Mock BreakoutGrid (#414 契约子集，test_hud.gd 内部使用)
signal brick_destroyed(brick, pos)
signal wall_cleared()
signal wall_generated(remaining)
var remaining_bricks: int = 0
"""
	else:
		code.source_code = """extends Node
## Mock BreakoutGrid — 无 wall_generated 信号（回退路径）
signal brick_destroyed(brick, pos)
signal wall_cleared()
var remaining_bricks: int = 0
"""
	code.reload()
	var grid = Node.new()
	grid.set_script(code)
	grid.name = "BreakoutGrid"
	return grid


# ── Scenario A: 霓虹样式 ──

func _test_ta1_neon_apply() -> void:
	# TA-1: NeonStyle.apply 后 font_color / outline_size > 0 / shadow_offset 非零
	var label = Label.new()
	NeonStyle.apply(label, Color(1.0, 0.2, 0.33, 1.0))
	_assert(label.get("theme_override_colors/font_color") == Color(1.0, 0.2, 0.33, 1.0),
		"TA-1: font_color == 传入色")
	var outline: int = label.get("theme_override_constants/outline_size")
	_assert(outline > 0, "TA-1: outline_size > 0 (got %s)" % str(outline))
	var sx: int = label.get("theme_override_constants/shadow_offset_x")
	var sy: int = label.get("theme_override_constants/shadow_offset_y")
	_assert(sx != 0 and sy != 0, "TA-1: shadow_offset 非零 (%s,%s)" % [str(sx), str(sy)])
	label.free()


func _test_ta2_hud_labels_neon() -> void:
	# TA-2: ui_game_hud.tscn 实例 _ready 后 7 个数字 Label 全部 outline>0 + shadow 非零 (AC1)
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TA-2: ui_game_hud.tscn 加载失败")
		return
	_root.add_child(hud)
	var paths := [
		"TopZone/VBoxContainer/AIScoreLabel",
		"TopZone/VBoxContainer/AISubRow/AIBrickLabel",
		"TopZone/VBoxContainer/AISubRow/AIPierceLabel",
		"InfoBar",
		"BottomZone/HBoxContainer/PlayerScoreLabel",
		"BottomZone/HBoxContainer/PlayerBrickLabel",
		"BottomZone/HBoxContainer/PlayerPierceLabel",
	]
	for path in paths:
		var lbl: Label = hud.get_node_or_null(path)
		_assert(lbl != null, "TA-2: %s exists" % path)
		if lbl == null:
			continue
		var outline: int = lbl.get("theme_override_constants/outline_size")
		var sx: int = lbl.get("theme_override_constants/shadow_offset_x")
		var sy: int = lbl.get("theme_override_constants/shadow_offset_y")
		_assert(outline > 0, "TA-2: %s outline_size > 0 (got %s)" % [path, str(outline)])
		_assert(sx != 0 and sy != 0, "TA-2: %s shadow_offset 非零" % path)
	hud.queue_free()
	await _wait(0.02)


func _test_ta3_no_custom_font() -> void:
	# TA-3: apply 不引入第三方字体（默认字体）
	var label = Label.new()
	NeonStyle.apply(label, Color.WHITE)
	_assert(label.get("theme_override_fonts/font") == null, "TA-3: 无自定义字体 override（默认字体）")
	label.free()


# ── Scenario B: 信号接线 ──

func _test_tb3_score_changed_updates() -> void:
	# TB-3: score_changed(5,3) → PlayerScoreLabel "Player: 5" / AIScoreLabel "AI: 3"
	_gm.reset_match()
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TB-3: hud 加载失败")
		return
	_root.add_child(hud)
	_gm.add_score("player", 2, "boundary")
	_gm.add_score("ai", 3, "boundary")
	var p_lbl: Label = hud.get_node_or_null("BottomZone/HBoxContainer/PlayerScoreLabel")
	var a_lbl: Label = hud.get_node_or_null("TopZone/VBoxContainer/AIScoreLabel")
	if p_lbl:
		_assert(p_lbl.text == "Player: 2", "TB-3: PlayerScoreLabel == 'Player: 2' (got %s)" % p_lbl.text)
	if a_lbl:
		_assert(a_lbl.text == "AI: 3", "TB-3: AIScoreLabel == 'AI: 3' (got %s)" % a_lbl.text)
	hud.queue_free()
	await _wait(0.02)


func _test_tb4_brick_scored_updates() -> void:
	# TB-4: brick_scored("player") → PlayerBrickLabel "拆 1"（读 get_brick_count）
	_gm.reset_match()
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TB-4: hud 加载失败")
		return
	_root.add_child(hud)
	_gm.add_score("player", 1, "brick")
	var pb: Label = hud.get_node_or_null("BottomZone/HBoxContainer/PlayerBrickLabel")
	if pb:
		_assert(pb.text == "拆 1", "TB-4: PlayerBrickLabel == '拆 1' (got %s)" % pb.text)
	var pp: Label = hud.get_node_or_null("BottomZone/HBoxContainer/PlayerPierceLabel")
	if pp:
		_assert(pp.text == "穿 0", "TB-4: brick 信号不更新穿墙区 (got %s)" % pp.text)
	_gm.add_score("ai", 1, "brick")
	var ab: Label = hud.get_node_or_null("TopZone/VBoxContainer/AISubRow/AIBrickLabel")
	if ab:
		_assert(ab.text == "拆 1", "TB-4: AIBrickLabel == '拆 1' (got %s)" % ab.text)
	hud.queue_free()
	await _wait(0.02)


func _test_tb5_wave_started_info() -> void:
	# TB-5: wave_started(2) → 信息条含「第 2 波」
	_gm.reset_match()
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TB-5: hud 加载失败")
		return
	_root.add_child(hud)
	_gm.begin_wave()
	_gm.begin_wave()
	var info: Label = hud.get_node_or_null("InfoBar")
	if info:
		_assert(info.text.contains("第 2 波"), "TB-5: 信息条含 '第 2 波' (got %s)" % info.text)
	await _wait(0.05)
	if info:
		_assert(info.text.contains("第 2 波"), "TB-5: 帧末回退刷新后波次号保留 (got %s)" % info.text)
	hud.queue_free()
	await _wait(0.02)


func _test_tb6_old_gm_no_crash() -> void:
	# TB-6 / TD-3: mock 旧版 GameManager（无新信号）→ _ready 不崩（has_signal 守卫）
	var fake = Node.new()
	fake.name = "FakeGM"
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TB-6: hud 加载失败")
		fake.free()
		return
	hud.game_manager = fake
	_root.add_child(hud)
	_assert(true, "TB-6: 旧版 GM mock 下 _ready 不崩")
	hud.queue_free()
	fake.free()
	await _wait(0.02)


# ── Scenario C: 剩余砖数（mock grid）──

func _test_tc1_brick_destroyed_remaining() -> void:
	# TC-1: brick_destroyed 后 remaining_bricks=5 → 「剩余 5」（即时单读）
	_gm.reset_match()
	var grid = _make_mock_grid(true)
	_root.add_child(grid)
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TC-1: hud 加载失败")
		grid.queue_free()
		return
	_root.add_child(hud)
	grid.remaining_bricks = 5
	grid.brick_destroyed.emit(null, Vector2.ZERO)
	var info: Label = hud.get_node_or_null("InfoBar")
	if info:
		_assert(info.text.contains("剩余 5"), "TC-1: brick_destroyed → '剩余 5' (got %s)" % info.text)
	hud.queue_free()
	grid.queue_free()
	await _wait(0.02)


func _test_tc2_wall_cleared_zero() -> void:
	# TC-2: wall_cleared → 「剩余 0」
	_gm.reset_match()
	var grid = _make_mock_grid(true)
	_root.add_child(grid)
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TC-2: hud 加载失败")
		grid.queue_free()
		return
	_root.add_child(hud)
	grid.remaining_bricks = 3
	grid.wall_cleared.emit()
	var info: Label = hud.get_node_or_null("InfoBar")
	if info:
		_assert(info.text.contains("剩余 0"), "TC-2: wall_cleared → '剩余 0' (got %s)" % info.text)
	hud.queue_free()
	grid.queue_free()
	await _wait(0.02)


func _test_tc3_wall_generated() -> void:
	# TC-3: wall_generated(12) → 「剩余 12」（首选路径）
	_gm.reset_match()
	var grid = _make_mock_grid(true)
	_root.add_child(grid)
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TC-3: hud 加载失败")
		grid.queue_free()
		return
	_root.add_child(hud)
	grid.wall_generated.emit(12)
	var info: Label = hud.get_node_or_null("InfoBar")
	if info:
		_assert(info.text.contains("剩余 12"), "TC-3: wall_generated(12) → '剩余 12' (got %s)" % info.text)
	hud.queue_free()
	grid.queue_free()
	await _wait(0.02)


func _test_tc4_fallback_deferred() -> void:
	# TC-4: 回退路径 — 仅 wave_started + mock grid（无 wall_generated）→ 帧末读到新墙总数
	_gm.reset_match()
	var grid = _make_mock_grid(false)
	_root.add_child(grid)
	grid.remaining_bricks = 7
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TC-4: hud 加载失败")
		grid.queue_free()
		return
	_root.add_child(hud)
	_gm.begin_wave()
	var info: Label = hud.get_node_or_null("InfoBar")
	if info:
		_assert(info.text.contains("第 1 波"), "TC-4: wave_started 立即更新波次号 (got %s)" % info.text)
	await _wait(0.05)
	if info:
		_assert(info.text.contains("剩余 7"), "TC-4: 帧末回退读到 remaining_bricks=7 (got %s)" % info.text)
	hud.queue_free()
	grid.queue_free()
	await _wait(0.02)


# ── Scenario D: 容错 ──

func _test_td1_no_grid_placeholder() -> void:
	# TD-1: 无 ../BreakoutGrid sibling → 「剩余 —」+ _warned 守卫（push_warning 一次）
	_gm.reset_match()
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TD-1: hud 加载失败")
		return
	_root.add_child(hud)
	var info: Label = hud.get_node_or_null("InfoBar")
	if info:
		_assert(info.text.contains("剩余 —"), "TD-1: 无 grid → 信息条 '剩余 —' (got %s)" % info.text)
	_assert(hud.get("_warned") == true, "TD-1: _warned 守卫置位（push_warning 只一次）")
	hud._refresh_remaining()
	_assert(true, "TD-1: 重复刷新不崩")
	hud.queue_free()
	await _wait(0.02)


func _test_td2_grid_no_wall_generated() -> void:
	# TD-2: grid 存在但缺 wall_generated 信号 → 不崩，走 call_deferred 回退
	_gm.reset_match()
	var grid = _make_mock_grid(false)
	_root.add_child(grid)
	grid.remaining_bricks = 4
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TD-2: hud 加载失败")
		grid.queue_free()
		return
	_root.add_child(hud)
	_assert(true, "TD-2: grid 缺 wall_generated → 不崩")
	await _wait(0.05)
	var info: Label = hud.get_node_or_null("InfoBar")
	if info:
		_assert(info.text.contains("剩余 4"), "TD-2: 回退路径显示 remaining (got %s)" % info.text)
	hud.queue_free()
	grid.queue_free()
	await _wait(0.02)


# ── Scenario E: 布局安全区与场景组装 (AC2/AC4) ──

func _test_te1_safety_zones() -> void:
	# TE-1: 720×1280 下 TopZone y∈[12,84]、BottomZone y∈[1252,1280]、全宽、
	# 与砖墙 y=640 / 玩家挡板 y∈[1230,1250] 零交集 (AC4)
	_gm.reset_match()
	var hud = _make_hud()
	if hud == null:
		_assert(false, "TE-1: hud 加载失败")
		return
	_root.add_child(hud)
	await _wait(0.05)   # 布局一帧后生效
	var top: Control = hud.get_node_or_null("TopZone")
	var bottom: Control = hud.get_node_or_null("BottomZone")
	if top:
		var tr = top.get_global_rect()
		_assert(tr.position.y >= 12.0, "TE-1: TopZone top >= 12 (got %s)" % str(tr.position.y))
		_assert(tr.end.y <= 84.0, "TE-1: TopZone bottom <= 84 (got %s)" % str(tr.end.y))
		_assert(abs(tr.size.x - 720.0) < 0.5, "TE-1: TopZone 全宽 (got %s)" % str(tr.size.x))
		_assert(tr.end.y < 640.0, "TE-1: 顶部区在砖墙 y=640 之上")
	if bottom:
		var br = bottom.get_global_rect()
		_assert(br.position.y >= 1252.0, "TE-1: BottomZone top >= 1252 (got %s)" % str(br.position.y))
		_assert(br.end.y <= 1280.0, "TE-1: BottomZone bottom <= 1280 (got %s)" % str(br.end.y))
		_assert(abs(br.size.x - 720.0) < 0.5, "TE-1: BottomZone 全宽 (got %s)" % str(br.size.x))
		_assert(br.position.y > 1250.0, "TE-1: 底部区在玩家挡板 y∈[1230,1250] 之下")
	hud.queue_free()
	await _wait(0.02)


func _test_te2_main_tscn_instance() -> void:
	# TE-2: Main.tscn GameHUD 为 ui_game_hud.tscn 实例、layer==1、visible==false、节点名 GameHUD
	if not ResourceLoader.exists("res://scenes/Main.tscn"):
		_assert(false, "TE-2: Main.tscn missing")
		return
	var game = load("res://scenes/Main.tscn").instantiate()
	_root.add_child(game)
	var hud = game.get_node_or_null("GameHUD")
	_assert(hud != null, "TE-2: GameHUD exists")
	if hud:
		_assert(hud is CanvasLayer, "TE-2: GameHUD is CanvasLayer")
		_assert(hud.name == "GameHUD", "TE-2: 节点名保持 'GameHUD'")
		_assert(hud.layer == 1, "TE-2: layer == 1 (got %s)" % str(hud.layer))
		_assert(hud.visible == false, "TE-2: visible == false")
		_assert(hud.scene_file_path == "res://scenes/ui_game_hud.tscn",
			"TE-2: GameHUD 为 ui_game_hud.tscn 实例 (got %s)" % str(hud.scene_file_path))
		_assert(hud.get_node_or_null("TopZone") != null, "TE-2: 实例含新节点树 TopZone")
	game.queue_free()
	await _wait(0.02)


# ── Scenario F: 无轮询与常量 (AC5) ──

func _test_tf1_no_polling() -> void:
	# TF-1: game_hud.gd 源码无 _process / _physics_process（AC5 零轮询）
	var script = load("res://gdscripts/game_hud.gd")
	if script == null:
		_assert(false, "TF-1: game_hud.gd 加载失败")
		return
	var src: String = script.source_code
	_assert(not src.contains("_process("), "TF-1: game_hud.gd 无 _process 轮询")
	_assert(not src.contains("_physics_process("), "TF-1: game_hud.gd 无 _physics_process")


func _test_tf2_hud_constants() -> void:
	# TF-2: constants.gd HUD_* 组存在且数值非零 / 安全区在 [0,1280] 内
	_assert(CONSTS.HUD_OUTLINE_SIZE > 0, "TF-2: HUD_OUTLINE_SIZE > 0")
	_assert(CONSTS.HUD_SHADOW_OFFSET_X > 0 and CONSTS.HUD_SHADOW_OFFSET_Y > 0, "TF-2: shadow offset > 0")
	_assert(CONSTS.HUD_TOP_BAND_Y >= 0.0 and CONSTS.HUD_TOP_BAND_Y <= 1280.0, "TF-2: HUD_TOP_BAND_Y in [0,1280]")
	_assert(CONSTS.HUD_BOTTOM_BAND_Y >= 0.0 and CONSTS.HUD_BOTTOM_BAND_Y <= 1280.0, "TF-2: HUD_BOTTOM_BAND_Y in [0,1280]")

extends RefCounted
## Test suite for Issue #543 — 游戏模式选择 + 本地双人对战。
## 规格: docs/DESIGN/543-mode-select-local-2p.md §9 场景 A–H（测试契约）。
## 覆盖: 模式状态机与常量 / InputMap 分键拆分与幂等 / 双板配置与连击通道 /
##       2P 目标解析 _build_ctx / debuff 回调与挡板定时状态 / 双游标升级交互 /
##       HUD 与结算显示 / 编译回归标记。
## 所有权: content_ownership: mechanical（debuff 数值/文案为 taste 占位，#395 定稿）。
##
## TDD 契约说明: 本套件引用的契约 API（GameManager.GameMode/set_game_mode/
## apply_mode_to_paddles、paddle.gd rebind_for_mode/set_frozen_timed/set_speed_scale_timed/
## set_input_invert_timed/is_effectively_frozen/player_index、UpgradePool.get_candidates
## (n, allow_opponent)/apply(id, player_index)/_build_ctx(player_index)、UpgradePickUI
## 2P 双游标、HUD/结算 2P 分支）在实现落地前不存在——测试可能解析失败，属预期（TDD 管道）。
## 常量契约: constants.gd 新增 UPGRADE_2P_CONFIRM_TIMEOUT(10.0) 与 action 名常量
## P1_CONFIRM_ACTION("p1_confirm")/P2_CONFIRM_ACTION("p2_confirm")/P2_LEFT_ACTION
## ("p2_left")/P2_RIGHT_ACTION("p2_right")。
##
## Runs under godot --headless --script via run_tests.gd（同步 _run，无 await）。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const Defs = preload("res://gdscripts/upgrade_defs.gd")

# ── 信号捕获（member vars，不用 lambda 闭包）──
var _upgrade_applied_calls: Array = []

func _on_upgrade_applied(id: String) -> void:
	_upgrade_applied_calls.append(id)


# ── 测试夹具 ──

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_gm():
	var gm = Node.new()
	gm.set_script(load("res://gdscripts/game_manager.gd"))
	gm.name = "GameManager"
	return gm


func _make_pool():
	var pool = Node.new()
	pool.set_script(load("res://gdscripts/upgrade_pool.gd"))
	return pool


## 真实 paddle.gd 实例（不进树，避免 _ready 的 InputMap 绑定/组注册副作用）。
## player_index = 1 → P2（顶侧，2P）。
func _make_paddle_instance(index: int = 0):
	var PaddleScript = load("res://gdscripts/paddle.gd")
	var p = Area2D.new()
	p.set_script(PaddleScript)
	p.mode = PaddleScript.Mode.PLAYER
	p.player_index = index
	p.position = Vector2(500.0, 500.0)
	p.min_x = -10000.0
	p.max_x = 10000.0
	return p


var _mock_script = null

func _get_mock_script():
	if _mock_script == null:
		var code = GDScript.new()
		code.source_code = """extends Node
## Mock 2P paddle（test_local_2p.gd 内部使用）— paddle.gd 契约子集
var player_index: int = 0
var mode: int = 0
var paddle_width: float = 120.0
var base_paddle_width: float = 120.0
var magnet_enabled: bool = false
var set_width_calls: Array = []
var frozen_timed_calls: Array = []
var speed_scale_calls: Array = []
var input_invert_calls: Array = []
func set_paddle_width(w: float) -> void:
	paddle_width = w
	set_width_calls.append(w)
func set_frozen_timed(d: float) -> void:
	frozen_timed_calls.append(d)
func set_speed_scale_timed(s: float, d: float) -> void:
	speed_scale_calls.append([s, d])
func set_input_invert_timed(d: float) -> void:
	input_invert_calls.append(d)
func is_effectively_frozen() -> bool:
	return false
"""
		code.reload()
		_mock_script = code
	return _mock_script


## 建 mock paddle 并挂进 host + paddles 组。node_name 是 apply_mode_to_paddles 的
## 身份契约：节点名 "PlayerPaddle" = P1（player_index 0）、"AIPaddle" = P2（顶侧）。
func _add_mock_paddle(host, node_name: String, index: int) -> Node:
	var n = Node.new()
	n.name = node_name
	n.set_script(_get_mock_script())
	n.player_index = index
	host.add_child(n)
	n.add_to_group("paddles")
	return n


func _make_host(node_name: String) -> Node2D:
	var host = Node2D.new()
	host.name = node_name
	_tree().root.add_child(host)
	return host


func _free_host(host) -> void:
	if host != null and is_instance_valid(host) and host.get_parent() != null:
		host.get_parent().remove_child(host)
		host.queue_free()


## 把 paddles / wave_controllers 组的既有成员移出（仅移除组籍，不 free 节点），
## 使目标解析/推进断言确定性（前序套件可能残留）。
func _clear_group(group: String) -> void:
	for n in _tree().get_nodes_in_group(group):
		n.remove_from_group(group)


func _setup_pool(host) -> Node:
	var pool = _make_pool()
	host.add_child(pool)
	return pool


## InputMap 断言辅助
func _keycodes(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(ev.keycode)
	return out


func _has_keycode(action: String, keycode: int) -> bool:
	for k in _keycodes(action):
		if k == keycode:
			return true
	return false


func _count_keycode(action: String, keycode: int) -> int:
	var n: int = 0
	for k in _keycodes(action):
		if k == keycode:
			n += 1
	return n


func _rebind(mode: int) -> void:
	load("res://gdscripts/paddle.gd").rebind_for_mode(mode)


## 颜色距离（0–1 归一化 → ×255 到 0–255 空间）
func _rgb_distance(a: Color, b: Color) -> float:
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


# ── Scenario F 夹具（真实 autoload + mini tree）──

func _non_stub_definitions() -> Array:
	var out: Array = []
	for d in UpgradePool.get_definitions():
		if not d.get("is_stub", false):
			out.append(d)
	return out


## 重置 2P 升级 UI 测试前置状态（真实 autoload，确定性）。
func _reset_pool_2p() -> void:
	GameManager.reset_match()
	_tree().paused = false
	UpgradePool.stacks = {}
	UpgradePool.stub_activated = {}
	UpgradePool._available = _non_stub_definitions()
	UpgradePool.rng.seed = 20260818
	_upgrade_applied_calls.clear()
	if UpgradePool.upgrade_applied.is_connected(_on_upgrade_applied):
		UpgradePool.upgrade_applied.disconnect(_on_upgrade_applied)


func _make_ui_fx() -> Dictionary:
	_clear_group("paddles")
	_clear_group("wave_controllers")
	var tree = _tree()
	var host = Node2D.new()
	host.name = "TestHost2P"
	tree.root.add_child(host)

	var ui_scene = load("res://scenes/ui_upgrade_pick.tscn")
	var ui = ui_scene.instantiate()
	host.add_child(ui)

	var code = GDScript.new()
	code.source_code = """extends Node
## Mock WaveController（test_local_2p.gd 内部使用）— advance 接管计数
var settle_hold: bool = false
var advance_calls: int = 0
func advance_settlement() -> void:
	advance_calls += 1
"""
	code.reload()
	var wc = Node.new()
	wc.set_script(code)
	wc.name = "MockWaveController"
	host.add_child(wc)
	wc.add_to_group("wave_controllers")
	return {"host": host, "ui": ui, "wc": wc}


func _cleanup_ui_fx(fx: Dictionary) -> void:
	_tree().paused = false   # 防残留暂停污染后续套件
	var ui = fx.get("ui")
	if ui != null and is_instance_valid(ui) and GameManager.wave_settled.is_connected(ui.open):
		GameManager.wave_settled.disconnect(ui.open)
	var wc = fx.get("wc")
	if wc != null and is_instance_valid(wc):
		wc.remove_from_group("wave_controllers")
	var host = fx.get("host")
	if host != null and is_instance_valid(host) and host.get_parent() != null:
		host.get_parent().remove_child(host)
		host.queue_free()


## 直接向 _unhandled_input 注入 InputEventAction（同步、确定性，等价于 Godot 分发的下一帧输入）
func _press(ui, action: String) -> void:
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ui._unhandled_input(ev)


# ── Scenario G 夹具（沿用 test_failure_screen / test_hud 模式）──

func _make_screen() -> CanvasLayer:
	var script = load("res://gdscripts/game_over_screen.gd")
	var screen = CanvasLayer.new()
	screen.set_script(script)
	screen.name = "GameOverScreen"
	return screen


func _wire_labels(screen: CanvasLayer) -> Dictionary:
	var winner := Label.new()
	winner.name = "WinnerLabel"
	var restart := Label.new()
	restart.name = "RestartPromptLabel"
	screen.winner_label = winner
	screen.restart_label = restart
	var fp := Label.new()
	fp.name = "FailurePhraseLabel"
	var rs := Label.new()
	rs.name = "RunStatsLabel"
	screen.failure_phrase_label = fp
	screen.run_stats_label = rs
	return {"winner": winner, "restart": restart, "phrase": fp, "stats": rs}


func _make_hud() -> CanvasLayer:
	var packed = load("res://scenes/ui_game_hud.tscn")
	if packed == null:
		return null
	return packed.instantiate()


# ── 主入口 ──

func run() -> void:
	print("\n=== Local 2P Tests (#543) ===")
	# Scenario A: 模式状态机与常量
	_test_a1_constants_and_enums()
	_test_a2_mode_highlight_colors()
	_test_a3_default_single()
	_test_a4_out_of_range_clamp()
	# Scenario B: InputMap 分键拆分与幂等
	_test_b1_2p_key_split()
	_test_b2_single_zero_regression()
	_test_b3_idempotent_cycles()
	_test_b4_headless_rebuild()
	_test_b5_unbound_guarded_read()
	# Scenario C: 2P 挡板配置与连击通道
	_test_c1_apply_mode_to_paddles()
	_test_c2_combo_channel_split()
	_test_c3_empty_group_no_crash()
	# Scenario D: 2P 目标解析
	_test_d1_build_ctx_self_opponent()
	_test_d2_fallback_compat()
	_test_d3_single_paddle_debuff_noop()
	# Scenario E: debuff 回调与定时状态
	_test_e1_definitions_and_callbacks()
	_test_e2_frozen_timed_semantics()
	_test_e3_slow_scale_timed()
	_test_e4_reverse_invert()
	_test_e5_pool_opponent_isolation()
	# Scenario F: 双游标升级交互
	_test_f1_2p_independent_cursors()
	_test_f2_lock_then_pick()
	_test_f3_same_frame_same_card_p1_wins()
	_test_f4_timeout_auto_pick()
	_test_f5_single_path_unchanged()
	# Scenario G: HUD / 结算显示
	_test_g1_hud_2p_label()
	_test_g2_game_over_2p_winners()
	_test_g3_game_over_single_fail()
	# Scenario H: 编译/回归标记
	_test_h1_contract_markers()
	# 恢复默认状态（不污染后续套件）
	if is_instance_valid(GameManager) and GameManager.has_method("set_game_mode"):
		GameManager.set_game_mode(0)
	var PaddleScript = load("res://gdscripts/paddle.gd")
	if PaddleScript != null and PaddleScript.has_method("rebind_for_mode"):
		PaddleScript.rebind_for_mode(0)
	_clear_group("paddles")
	print("  Local 2P: %d passed, %d failed" % [passed, failed])


# ── Scenario A — 模式状态机与常量 ──

## A1（机械键）: GameMode 枚举 / 超时常量 / action 名常量
func _test_a1_constants_and_enums() -> void:
	var gm = _make_gm()
	_assert(gm != null, "A1: game_manager.gd 可加载")
	if gm == null:
		return
	_assert(gm.GameMode.SINGLE == 0, "A1: GameMode.SINGLE == 0")
	_assert(gm.GameMode.LOCAL_2P == 1, "A1: GameMode.LOCAL_2P == 1")
	_assert(CONSTS.UPGRADE_2P_CONFIRM_TIMEOUT == 10.0, "A1: UPGRADE_2P_CONFIRM_TIMEOUT == 10.0")
	_assert(CONSTS.P1_CONFIRM_ACTION == "p1_confirm", "A1: P1_CONFIRM_ACTION == 'p1_confirm'")
	_assert(CONSTS.P2_CONFIRM_ACTION == "p2_confirm", "A1: P2_CONFIRM_ACTION == 'p2_confirm'")
	_assert(CONSTS.P2_LEFT_ACTION == "p2_left", "A1: P2_LEFT_ACTION == 'p2_left'")
	_assert(CONSTS.P2_RIGHT_ACTION == "p2_right", "A1: P2_RIGHT_ACTION == 'p2_right'")


## A2（E2E theme 保护）: 模式高亮色距 PLAYER_NEON_BLUE(#4a90d9) RGB 距离×255 ≥ 32
func _test_a2_mode_highlight_colors() -> void:
	var d_paddle = _rgb_distance(CONSTS.PADDLE_NEON, CONSTS.PLAYER_NEON_BLUE) * 255.0
	var d_brick = _rgb_distance(CONSTS.BRICK_NEON, CONSTS.PLAYER_NEON_BLUE) * 255.0
	_assert(d_paddle >= 32.0, "A2: PADDLE_NEON 距 PLAYER_NEON_BLUE >= 32 (got %.1f)" % d_paddle)
	_assert(d_brick >= 32.0, "A2: BRICK_NEON 距 PLAYER_NEON_BLUE >= 32 (got %.1f)" % d_brick)


## A3（默认单人）: GameManager.game_mode 初始 SINGLE；StartMenu.get_selected_mode() 初始 0
func _test_a3_default_single() -> void:
	var gm = _make_gm()
	if gm == null:
		_assert(false, "A3: game_manager.gd 可加载")
		return
	_assert(gm.game_mode == gm.GameMode.SINGLE, "A3: GameManager.game_mode 默认 == SINGLE (0)")
	_assert(gm.get_game_mode() == 0, "A3: get_game_mode() == 0")
	var sm = CanvasLayer.new()
	sm.set_script(load("res://gdscripts/start_menu.gd"))
	_assert(sm.get_selected_mode() == 0, "A3: StartMenu.get_selected_mode() 初始 == 0")


## A4（越界 clamp）: set_game_mode(99) → 落回 SINGLE
func _test_a4_out_of_range_clamp() -> void:
	var gm = _make_gm()
	if gm == null:
		_assert(false, "A4: game_manager.gd 可加载")
		return
	gm.set_game_mode(99)
	_assert(gm.game_mode == 0, "A4: set_game_mode(99) → clamp 回 SINGLE (0)")
	_assert(gm.get_game_mode() == 0, "A4: get_game_mode() == 0 after clamp")
	gm.set_game_mode(1)
	_assert(gm.game_mode == 1, "A4: set_game_mode(1) → LOCAL_2P")


# ── Scenario B — InputMap 分键拆分与幂等 ──

## B1（AC3 分键隔离）: LOCAL_2P 下 paddle_left 只留 A、paddle_right 只留 D；p2/confirm 键就位
func _test_b1_2p_key_split() -> void:
	_rebind(0)   # 先归一单人
	_rebind(1)   # 切 2P
	_assert(_has_keycode("paddle_left", KEY_A), "B1: 2P 下 paddle_left 含 A")
	_assert(not _has_keycode("paddle_left", KEY_LEFT), "B1: 2P 下 paddle_left 不含 ←")
	_assert(_has_keycode("paddle_right", KEY_D), "B1: 2P 下 paddle_right 含 D")
	_assert(not _has_keycode("paddle_right", KEY_RIGHT), "B1: 2P 下 paddle_right 不含 →")
	_assert(_has_keycode("p2_left", KEY_LEFT), "B1: p2_left 含 ←")
	_assert(_has_keycode("p2_right", KEY_RIGHT), "B1: p2_right 含 →")
	_assert(_has_keycode("p1_confirm", KEY_E), "B1: p1_confirm 含 E")
	_assert(_has_keycode("p2_confirm", KEY_SHIFT), "B1: p2_confirm 含 Shift")
	_assert(_count_keycode("paddle_left", KEY_A) == 1, "B1: paddle_left A 无重复")
	_assert(_count_keycode("p2_left", KEY_LEFT) == 1, "B1: p2_left ← 无重复")


## B2（AC2 单人零回归）: SINGLE 下 paddle_left == {A, ←}、paddle_right == {D, →} 逐元素一致
func _test_b2_single_zero_regression() -> void:
	_rebind(1)
	_rebind(0)
	_assert(_has_keycode("paddle_left", KEY_A) and _has_keycode("paddle_left", KEY_LEFT),
		"B2: SINGLE 下 paddle_left 含 A+←")
	_assert(_has_keycode("paddle_right", KEY_D) and _has_keycode("paddle_right", KEY_RIGHT),
		"B2: SINGLE 下 paddle_right 含 D+→")
	_assert(_count_keycode("paddle_left", KEY_A) == 1 and _count_keycode("paddle_left", KEY_LEFT) == 1,
		"B2: paddle_left A/← 各 1（无重复）")
	_assert(_count_keycode("paddle_right", KEY_D) == 1 and _count_keycode("paddle_right", KEY_RIGHT) == 1,
		"B2: paddle_right D/→ 各 1（无重复）")
	_assert(not _has_keycode("p2_left", KEY_LEFT), "B2: SINGLE 下 p2_left 无 ←（已清）")
	_assert(not _has_keycode("p2_right", KEY_RIGHT), "B2: SINGLE 下 p2_right 无 →（已清）")


## B3（幂等重建）: 连续 3 轮 SINGLE→LOCAL_2P→SINGLE 无残留、无重复
func _test_b3_idempotent_cycles() -> void:
	for i in 3:
		_rebind(0)
		_rebind(1)
		_rebind(0)
	_assert(_count_keycode("paddle_left", KEY_A) == 1 and _count_keycode("paddle_left", KEY_LEFT) == 1,
		"B3: 3 轮后 paddle_left A+← 各 1")
	_assert(_count_keycode("paddle_right", KEY_D) == 1 and _count_keycode("paddle_right", KEY_RIGHT) == 1,
		"B3: 3 轮后 paddle_right D+→ 各 1")
	_assert(not _has_keycode("p2_left", KEY_LEFT) and not _has_keycode("p2_right", KEY_RIGHT),
		"B3: 3 轮后 p2_left/p2_right 无 ←/→ 残留")
	_assert(_keycodes("p2_left").is_empty(), "B3: p2_left 事件集清空（无残留）")


## B4（headless 安全）: --headless 下重建无脚本错误（Spike 1 结论固化）
func _test_b4_headless_rebuild() -> void:
	_rebind(0)
	_rebind(1)
	_rebind(0)
	_assert(true, "B4: headless 下 3 次重建无脚本错误")


## B5（未绑定 key 读 false）: SINGLE 下 p2_left/p2_right is_action_pressed == false（has_action 守卫）
func _test_b5_unbound_guarded_read() -> void:
	_rebind(0)
	var p2_left_pressed := false
	if InputMap.has_action("p2_left"):
		p2_left_pressed = Input.is_action_pressed("p2_left")
	_assert(p2_left_pressed == false, "B5: SINGLE 下 p2_left 守卫读 == false")
	var p2_right_pressed := false
	if InputMap.has_action("p2_right"):
		p2_right_pressed = Input.is_action_pressed("p2_right")
	_assert(p2_right_pressed == false, "B5: SINGLE 下 p2_right 守卫读 == false")


# ── Scenario C — 2P 挡板配置与连击通道 ──

## C1（AC3 双板配置）: apply_mode_to_paddles — LOCAL_2P 双板均 PLAYER(0/1)、SINGLE 回写 AI + InputMap 联动
## 身份契约: paddles 组内按节点名 "PlayerPaddle"(P1, index 0) / "AIPaddle"(P2, index 1) 区分。
func _test_c1_apply_mode_to_paddles() -> void:
	_clear_group("paddles")
	var host = _make_host("HostC1")
	var player = _add_mock_paddle(host, "PlayerPaddle", 0)
	var ai = _add_mock_paddle(host, "AIPaddle", 1)
	ai.mode = 1   # 场景默认 AIPaddle.mode = AI
	var gm = _make_gm()
	host.add_child(gm)

	gm.set_game_mode(gm.GameMode.LOCAL_2P)
	gm.apply_mode_to_paddles()
	_assert(player.mode == 0, "C1: LOCAL_2P PlayerPaddle.mode == PLAYER")
	_assert(player.player_index == 0, "C1: LOCAL_2P PlayerPaddle.player_index == 0")
	_assert(ai.mode == 0, "C1: LOCAL_2P AIPaddle.mode == PLAYER")
	_assert(ai.player_index == 1, "C1: LOCAL_2P AIPaddle.player_index == 1")
	_assert(_has_keycode("p2_left", KEY_LEFT), "C1: LOCAL_2P InputMap 已切 2P（p2_left 含 ←）")
	_assert(not _has_keycode("paddle_left", KEY_LEFT), "C1: LOCAL_2P paddle_left 不含 ←")

	gm.set_game_mode(gm.GameMode.SINGLE)
	gm.apply_mode_to_paddles()
	_assert(ai.mode == 1, "C1: SINGLE AIPaddle.mode 回写 AI")
	_assert(player.mode == 0, "C1: SINGLE PlayerPaddle.mode == PLAYER")
	_assert(player.player_index == 0, "C1: SINGLE PlayerPaddle.player_index == 0")
	_assert(_has_keycode("paddle_left", KEY_LEFT), "C1: SINGLE InputMap 恢复单人（paddle_left 含 ←）")

	_free_host(host)
	_rebind(0)


## C2（#504 连击分流）: P2(player_index=1) 跟踪 ai_score 通道，互不污染
func _test_c2_combo_channel_split() -> void:
	var p2 = _make_paddle_instance(1)
	p2._on_score_changed(0, 0)
	p2._on_score_changed(5, 0)   # player 侧涨分 → P2 通道不变
	_assert(p2._last_player_score == 0, "C2: P2 忽略 player_score（_last_player_score 仍 0）")
	_assert(p2._combo_active == false, "C2: P2 未被 player 侧触发连击")
	p2._on_score_changed(5, 1)   # ai 侧首分 → P2 通道起算
	_assert(p2._last_player_score == 1, "C2: P2 跟踪 ai_score（首分 → 1）")
	p2._on_score_changed(5, 2)   # 窗口内 ai 再涨 → 连击成立
	_assert(p2._combo_active == true, "C2: P2 ai 通道连击成立")
	p2._on_score_changed(10, 2)  # player 侧再涨不影响 P2 基准
	_assert(p2._last_player_score == 2, "C2: P2 基准不随 player_score 变")

	var p1 = _make_paddle_instance(0)
	p1._on_score_changed(1, 0)
	_assert(p1._last_player_score == 1, "C2: P1 跟踪 player_score")
	p1._on_score_changed(1, 5)   # ai 侧涨分 → P1 通道不变
	_assert(p1._last_player_score == 1, "C2: P1 忽略 ai_score（互不污染）")

	p2.free()
	p1.free()


## C3（组空容错）: paddles 组空 → apply_mode_to_paddles push_warning + 不崩溃
func _test_c3_empty_group_no_crash() -> void:
	_clear_group("paddles")
	var host = _make_host("HostC3")
	var gm = _make_gm()
	host.add_child(gm)
	gm.set_game_mode(gm.GameMode.LOCAL_2P)
	gm.apply_mode_to_paddles()
	_assert(true, "C3: 空 paddles 组 LOCAL_2P 不崩溃")
	gm.set_game_mode(gm.GameMode.SINGLE)
	gm.apply_mode_to_paddles()
	_assert(true, "C3: 空组 SINGLE 路径不崩溃")
	_free_host(host)


# ── Scenario D — 2P 目标解析 ──

## D1（AC4 self/opponent）: 双板 mock 下 _build_ctx(1) → self/opponent/paddle 回退键
func _test_d1_build_ctx_self_opponent() -> void:
	_clear_group("paddles")
	var host = _make_host("HostD1")
	var player = _add_mock_paddle(host, "PlayerPaddle", 0)
	var ai = _add_mock_paddle(host, "AIPaddle", 1)
	var pool = _setup_pool(host)

	var ctx: Dictionary = pool._build_ctx(1)
	_assert(ctx["self_paddle"] == ai, "D1: self_paddle == player_index 1 挡板（AIPaddle）")
	_assert(ctx["opponent_paddle"] == player, "D1: opponent_paddle == 另一挡板（PlayerPaddle）")
	_assert(ctx["paddle"] == ctx["self_paddle"], "D1: paddle 键 == self_paddle（回退键）")
	_assert(ctx["player_index"] == 1, "D1: ctx.player_index == 1")

	var ctx0: Dictionary = pool._build_ctx(0)
	_assert(ctx0["self_paddle"] == player, "D1: _build_ctx(0) self_paddle == PlayerPaddle")
	_assert(ctx0["opponent_paddle"] == ai, "D1: _build_ctx(0) opponent_paddle == AIPaddle")
	_free_host(host)


## D2（回退兼容）: 无 player_index mock（既有测试风格）→ self_paddle == 组内第一个、opponent == null
func _test_d2_fallback_compat() -> void:
	_clear_group("paddles")
	var host = _make_host("HostD2")
	var single = _add_mock_paddle(host, "PaddleOnly", 0)
	var pool = _setup_pool(host)

	var ctx: Dictionary = pool._build_ctx(0)
	_assert(ctx["self_paddle"] == single, "D2: self_paddle == 组内第一个（回退现状）")
	_assert(ctx["opponent_paddle"] == null, "D2: 单板 → opponent_paddle == null")
	_assert(ctx["paddle"] == single, "D2: paddle 键行为与旧 paddle_ref 一致")
	var ctx_miss: Dictionary = pool._build_ctx(9)
	_assert(ctx_miss["self_paddle"] == single, "D2: 无匹配 player_index → self_paddle 回退第一个")
	_assert(ctx_miss["opponent_paddle"] == null, "D2: 无匹配单板 → opponent == null")
	_free_host(host)


## D3（单板判空）: 单板组 → opponent null；debuff 效果调用 push_warning + no-op，不崩溃
func _test_d3_single_paddle_debuff_noop() -> void:
	_clear_group("paddles")
	var host = _make_host("HostD3")
	var single = _add_mock_paddle(host, "PaddleOnly", 0)
	var pool = _setup_pool(host)

	var ok: bool = pool.apply("shrink_opponent", 0)
	_assert(ok, "D3: 单板下 apply('shrink_opponent') 不崩溃返回 true")
	_assert(single.set_width_calls.is_empty(), "D3: 单板无 opponent → shrink 效果 no-op（宽度未改）")
	_assert(pool.get_stacks("shrink_opponent") == 1, "D3: apply 计数仍递增")
	_free_host(host)


# ── Scenario E — debuff 回调与定时状态 ──

## E1: 定义 target 契约 + pool.apply 触发 4 种 debuff 回调 + shrink max_stacks=2
func _test_e1_definitions_and_callbacks() -> void:
	var defs: Array = Defs.definitions()
	var opponent_ids: Array = ["shrink_opponent", "freeze_opponent", "slow_opponent", "reverse_opponent"]
	var playable_self: Array = ["long_arm", "fireball", "battering_ram", "magnet_core", "slow_time", "pre_hole"]
	var seen: Dictionary = {}
	for d in defs:
		var id_str: String = d.get("id", "")
		seen[id_str] = true
		if opponent_ids.has(id_str):
			_assert(d.get("target", "") == "opponent", "E1: %s target == opponent" % id_str)
			_assert(not bool(d.get("is_stub", true)), "E1: %s 非桩（#526 可见反馈纪律）" % id_str)
		else:
			_assert(d.get("target", "self") == "self", "E1: %s target 默认 self" % id_str)
	for id_str in opponent_ids:
		_assert(seen.has(id_str), "E1: 定义含 '%s'" % id_str)
	for id_str in playable_self:
		_assert(seen.has(id_str), "E1: 既有 6 卡 '%s' 保留" % id_str)

	# pool.apply(id, player_index) 触发回调（双板 mock）
	_clear_group("paddles")
	var host = _make_host("HostE1")
	var self_p = _add_mock_paddle(host, "SelfPaddle", 0)
	var opp = _add_mock_paddle(host, "OpponentPaddle", 1)
	var pool = _setup_pool(host)

	var w_before: float = opp.paddle_width
	_assert(pool.apply("shrink_opponent", 0), "E1: apply('shrink_opponent') 成功")
	_assert(opp.set_width_calls.size() == 1 and abs(opp.paddle_width - w_before * 0.7) < 0.01,
		"E1: shrink → set_paddle_width(w*0.7)（%.1f → %.1f）" % [w_before, opp.paddle_width])
	_assert(pool.apply("shrink_opponent", 0), "E1: shrink 第 2 次成功（max_stacks=2）")
	_assert(not pool.apply("shrink_opponent", 0), "E1: shrink 第 3 次返回 false（max_stacks 已满）")
	_assert(pool.get_stacks("shrink_opponent") == 2, "E1: shrink stacks == 2")

	_assert(pool.apply("freeze_opponent", 0), "E1: apply('freeze_opponent') 成功")
	_assert(opp.frozen_timed_calls.size() == 1 and opp.frozen_timed_calls[0] == 1.5,
		"E1: freeze → set_frozen_timed(1.5)")

	_assert(pool.apply("slow_opponent", 0), "E1: apply('slow_opponent') 成功")
	_assert(opp.speed_scale_calls.size() == 1 and opp.speed_scale_calls[0][0] == 0.75
		and opp.speed_scale_calls[0][1] == 8.0, "E1: slow → set_speed_scale_timed(0.75, 8.0)")

	_assert(pool.apply("reverse_opponent", 0), "E1: apply('reverse_opponent') 成功")
	_assert(opp.input_invert_calls.size() == 1 and opp.input_invert_calls[0] == 3.0,
		"E1: reverse → set_input_invert_timed(3.0)")
	_free_host(host)


## E2: 真实 paddle 定时冻结 — is_effectively_frozen 或关系（FSM 冻结与临时冻结互斥续走）
func _test_e2_frozen_timed_semantics() -> void:
	var p = _make_paddle_instance(0)
	_assert(p.is_effectively_frozen() == false, "E2: 初始未冻结")
	p.set_frozen_timed(1.5)
	_assert(p.is_effectively_frozen() == true, "E2: set_frozen_timed(1.5) → 冻结")
	p.set_frozen(true)
	_assert(p.is_effectively_frozen() == true, "E2: FSM 冻结叠加仍冻结")
	p.set_frozen(false)   # FSM 解冻
	_assert(p.is_effectively_frozen() == true, "E2: FSM 解冻后临时冻结剩余继续走完（或关系）")
	p.set_frozen_timed(0.0)
	_assert(p.is_effectively_frozen() == false, "E2: 临时冻结归零 → 解除")
	p.set_frozen(true)
	_assert(p.is_effectively_frozen() == true, "E2: FSM 冻结独立成立")
	p.free()


## E3: slow — set_speed_scale_timed(0.75, 8.0) 期间速度 ×0.75，8s 后恢复 1.0
func _test_e3_slow_scale_timed() -> void:
	var p = _make_paddle_instance(0)
	p.set_speed_scale_timed(0.75, 8.0)
	_assert(abs(p._speed_scale - 0.75) < 0.001, "E3: _speed_scale == 0.75")
	_assert(abs(p._speed_scale_remaining - 8.0) < 0.001, "E3: _speed_scale_remaining == 8.0")
	for i in 9:
		p._process(1.0)   # 9s > 8s
	_assert(p._speed_scale_remaining <= 0.001, "E3: 8s 后 remaining 归零")
	_assert(abs(p._speed_scale - 1.0) < 0.001, "E3: 8s 后 _speed_scale 恢复 1.0")
	p.free()


## E4: reverse — set_input_invert_timed(3.0) 期间右按 → 挡板左移；3s 后恢复正常
func _test_e4_reverse_invert() -> void:
	var PaddleScript = load("res://gdscripts/paddle.gd")
	if PaddleScript != null and PaddleScript.has_method("rebind_for_mode"):
		PaddleScript.rebind_for_mode(0)
	var p = _make_paddle_instance(0)
	p.set_input_invert_timed(3.0)
	_assert(abs(p._input_invert_remaining - 3.0) < 0.001, "E4: _input_invert_remaining == 3.0")
	var before: float = p.position.x
	Input.action_press("paddle_right")
	p._process(0.016)
	Input.action_release("paddle_right")
	_assert(p.position.x < before - 0.1, "E4: 反转期右按 → 挡板左移（轴取反）")
	for i in 190:
		p._process(0.016)   # ≈3.04s
	_assert(p._input_invert_remaining <= 0.001, "E4: 3s 后反转结束")
	before = p.position.x
	Input.action_press("paddle_right")
	p._process(0.016)
	Input.action_release("paddle_right")
	_assert(p.position.x > before + 0.1, "E4: 结束后右按 → 恢复正常右移")
	p.free()


## E5（单人池隔离）: get_candidates(3) 默认不含 opponent；get_candidates(3, true) 可含
func _test_e5_pool_opponent_isolation() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "E5: upgrade_pool.gd 可加载")
		return
	pool._ready()
	var opponent_ids: Array = ["shrink_opponent", "freeze_opponent", "slow_opponent", "reverse_opponent"]
	var leak := false
	for i in 50:
		for c in pool.get_candidates(3):
			if opponent_ids.has(c.id):
				leak = true
	_assert(not leak, "E5: get_candidates(3) 单人池永不含 opponent 卡")
	pool.rng.seed = 20260818
	var saw := false
	for i in 300:
		var cards = pool.get_candidates(3, true)
		for c in cards:
			if opponent_ids.has(c.id):
				saw = true
				break
		if saw:
			break
	_assert(saw, "E5: get_candidates(3, true) 可含 opponent 卡（debuff 非桩可出）")


# ── Scenario F — 双游标升级交互 ──

## F1（AC2/AC3 独立游标）: P1 键只动 _p1_focus_index、P2 键只动 _p2_focus_index
func _test_f1_2p_independent_cursors() -> void:
	_reset_pool_2p()
	GameManager.set_game_mode(GameManager.GameMode.LOCAL_2P)
	var fx = _make_ui_fx()
	var ui = fx.ui
	ui.open(1)
	_assert(ui._is_2p == true, "F1: 2P 模式 _is_2p == true")
	_assert(ui._p1_focus_index == 0 and ui._p2_focus_index == 0, "F1: 双游标初始 0")
	_press(ui, "p1_right")
	_assert(ui._p1_focus_index == 1, "F1: p1_right → _p1_focus_index == 1")
	_assert(ui._p2_focus_index == 0, "F1: p1_right 不动 P2 游标")
	_press(ui, "p2_left")
	_assert(ui._p2_focus_index == 2, "F1: p2_left → _p2_focus_index == 2（反绕）")
	_assert(ui._p1_focus_index == 1, "F1: p2_left 不动 P1 游标")
	_press(ui, "p2_right")
	_assert(ui._p2_focus_index == 0, "F1: p2_right → 0")
	_cleanup_ui_fx(fx)


## F2（先锁后选）: P1 锁卡 → P2 同卡被拒（不 apply）；P2 换卡成功 → 窗口关闭 + advance 一次
func _test_f2_lock_then_pick() -> void:
	_reset_pool_2p()
	GameManager.set_game_mode(GameManager.GameMode.LOCAL_2P)
	UpgradePool.upgrade_applied.connect(_on_upgrade_applied)
	_upgrade_applied_calls.clear()
	var fx = _make_ui_fx()
	var ui = fx.ui
	ui.open(1)
	_press(ui, "p1_confirm")   # P1 锁卡 0
	_assert(ui._locked_cards.has(0), "F2: P1 确认后卡 0 入 locked")
	_assert(ui._p1_confirmed == true and ui._p2_confirmed == false, "F2: P1 已确认、P2 未确认")
	_assert(_upgrade_applied_calls.size() == 1, "F2: P1 apply 恰好一次")
	_press(ui, "p2_confirm")   # P2 默认焦点 0 = 已锁卡
	_assert(_upgrade_applied_calls.size() == 1, "F2: P2 确认已锁卡被拒（不 apply）")
	_assert(ui._p2_confirmed == false, "F2: P2 未确认")
	_assert(ui._state == ui.UIState.SELECTING, "F2: 窗口仍打开")
	_press(ui, "p2_right")     # P2 焦点 → 1
	_press(ui, "p2_confirm")   # P2 锁卡 1
	_assert(_upgrade_applied_calls.size() == 2, "F2: P2 换卡成功（apply 第 2 次）")
	_assert(ui._locked_cards.has(1), "F2: 卡 1 入 locked")
	_assert(ui._state == ui.UIState.CLOSED, "F2: 双方确认 → 窗口关闭")
	_assert(fx.wc.advance_calls == 1, "F2: _advance_settlement 恰好一次")
	_assert(_tree().paused == false, "F2: 暂停恢复")
	_cleanup_ui_fx(fx)
	if UpgradePool.upgrade_applied.is_connected(_on_upgrade_applied):
		UpgradePool.upgrade_applied.disconnect(_on_upgrade_applied)


## F3（同帧同卡裁决）: P1 先处理锁定成功、P2 后到收「已锁」——不双扣（apply 计数 == 1）
func _test_f3_same_frame_same_card_p1_wins() -> void:
	_reset_pool_2p()
	GameManager.set_game_mode(GameManager.GameMode.LOCAL_2P)
	UpgradePool.upgrade_applied.connect(_on_upgrade_applied)
	_upgrade_applied_calls.clear()
	var fx = _make_ui_fx()
	var ui = fx.ui
	ui.open(1)
	_press(ui, "p1_right")   # P1 → 卡 1
	_press(ui, "p2_right")   # P2 → 卡 1
	_press(ui, "p1_confirm") # P1 先锁卡 1（帧内 P1 先处理）
	_assert(ui._locked_cards.has(1), "F3: P1 锁定卡 1 成功")
	_assert(_upgrade_applied_calls.size() == 1, "F3: P1 apply 计数 1")
	_press(ui, "p2_confirm") # P2 后到同卡 → 已锁
	_assert(_upgrade_applied_calls.size() == 1, "F3: 不双扣（apply 计数仍 1）")
	_assert(ui._p2_confirmed == false, "F3: P2 收到已锁未确认")
	ui.close()   # 收尾恢复暂停/推进
	_cleanup_ui_fx(fx)
	if UpgradePool.upgrade_applied.is_connected(_on_upgrade_applied):
		UpgradePool.upgrade_applied.disconnect(_on_upgrade_applied)


## F4（超时代选）: P1 确认后 10s 无 P2 操作 → P2 自动代选 → 窗口关闭 + advance 恰好一次
func _test_f4_timeout_auto_pick() -> void:
	_reset_pool_2p()
	GameManager.set_game_mode(GameManager.GameMode.LOCAL_2P)
	UpgradePool.upgrade_applied.connect(_on_upgrade_applied)
	_upgrade_applied_calls.clear()
	var fx = _make_ui_fx()
	var ui = fx.ui
	ui.open(1)
	_assert(abs(ui._confirm_timeout - CONSTS.UPGRADE_2P_CONFIRM_TIMEOUT) < 0.001,
		"F4: open 后 _confirm_timeout == UPGRADE_2P_CONFIRM_TIMEOUT")
	_press(ui, "p1_confirm")   # P1 确认（卡 0）
	_assert(ui._p1_confirmed == true and ui._p2_confirmed == false, "F4: 单方确认")
	_assert(ui._state == ui.UIState.SELECTING, "F4: 窗口仍打开（等 P2）")
	for i in 20:
		ui._process(0.6)   # 累计 12s > 10s 超时
	_assert(ui._state == ui.UIState.CLOSED, "F4: 超时 → 自动代选 → 窗口关闭")
	_assert(_upgrade_applied_calls.size() == 2, "F4: P2 被代选（apply 共 2 次）")
	_assert(fx.wc.advance_calls == 1, "F4: _advance_settlement 恰好一次")
	_assert(_tree().paused == false, "F4: 暂停恢复")
	_cleanup_ui_fx(fx)
	if UpgradePool.upgrade_applied.is_connected(_on_upgrade_applied):
		UpgradePool.upgrade_applied.disconnect(_on_upgrade_applied)


## F5（SINGLE 回归）: 单人窗口 ui_left/ui_right 路径不变；P1/P2 键在单人下无动作
func _test_f5_single_path_unchanged() -> void:
	_reset_pool_2p()
	GameManager.set_game_mode(GameManager.GameMode.SINGLE)
	var fx = _make_ui_fx()
	var ui = fx.ui
	ui.open(1)
	_assert(ui._is_2p == false, "F5: SINGLE 下 _is_2p == false")
	_assert(ui._focus_index == 0, "F5: 单游标初始 0")
	_press(ui, "ui_right")
	_assert(ui._focus_index == 1, "F5: ui_right → _focus_index == 1")
	_assert(ui._p1_focus_index == 0 and ui._p2_focus_index == 0, "F5: 双游标成员不被单人键改动")
	_press(ui, "p1_confirm")   # 单人下 P1 键无动作
	_assert(ui._state == ui.UIState.SELECTING, "F5: p1_confirm 在单人窗口无动作")
	ui.close()
	_cleanup_ui_fx(fx)


# ── Scenario G — HUD / 结算显示 ──

## G1（AC5 HUD）: 2P 下顶区 == 「P2: N」；SINGLE 下 == 「AI: N」（现状）
func _test_g1_hud_2p_label() -> void:
	GameManager.reset_match()
	var host = _make_host("HostG1")
	var hud = _make_hud()
	if hud == null:
		_assert(false, "G1: ui_game_hud.tscn 加载失败")
		_free_host(host)
		return
	host.add_child(hud)
	GameManager.set_game_mode(GameManager.GameMode.LOCAL_2P)
	hud._on_score_changed(3, 5)
	_assert(hud.ai_score_label.text == "P2: 5", "G1: LOCAL_2P 顶区 == 'P2: 5' (got %s)" % hud.ai_score_label.text)
	_assert(hud.player_score_label.text == "Player: 3", "G1: LOCAL_2P 底区不变 'Player: 3'")
	GameManager.set_game_mode(GameManager.GameMode.SINGLE)
	hud._on_score_changed(3, 5)
	_assert(hud.ai_score_label.text == "AI: 5", "G1: SINGLE 顶区 == 'AI: 5'（现状）")
	_free_host(host)


## G2（AC5 结算）: 2P 下 "ai" → P2 WIN!（胜者宣告分支）；"player" → P1 WIN!
func _test_g2_game_over_2p_winners() -> void:
	GameManager.reset_match()
	GameManager.set_game_mode(GameManager.GameMode.LOCAL_2P)
	var screen = _make_screen()
	var labels = _wire_labels(screen)
	screen._on_match_over("ai")
	_assert(labels.winner.text == "P2 WIN!", "G2: 2P winner ai → 'P2 WIN!' (got %s)" % labels.winner.text)
	_assert(labels.winner.visible == true, "G2: 2P 胜者宣告可见（不走失败分支）")
	_assert(labels.phrase.visible == false, "G2: failure_phrase 隐藏")
	_assert(labels.stats.visible == false, "G2: run_stats 隐藏")
	screen._on_match_over("player")
	_assert(labels.winner.text == "P1 WIN!", "G2: 2P winner player → 'P1 WIN!' (got %s)" % labels.winner.text)
	_assert(labels.winner.visible == true, "G2: P1 胜者宣告可见")
	_assert(labels.phrase.visible == false, "G2: P1 胜利亦隐藏失败分支")
	GameManager.reset_match()


## G3（SINGLE 结算回归）: SINGLE 下 "ai" → 失败文案分支（现状逐字节不变）
func _test_g3_game_over_single_fail() -> void:
	GameManager.reset_match()
	GameManager.set_game_mode(GameManager.GameMode.SINGLE)
	var screen = _make_screen()
	var labels = _wire_labels(screen)
	screen._on_match_over("ai")
	_assert(labels.winner.visible == false, "G3: SINGLE ai → WinnerLabel 隐藏（失败分支）")
	_assert(labels.phrase.visible == true, "G3: FailurePhraseLabel 可见")
	_assert(labels.stats.visible == true, "G3: RunStatsLabel 可见")
	GameManager.reset_match()


# ── Scenario H — 编译/回归标记 ──

## H1: 相关脚本/场景可加载 + 既有常量与枚举回归（AC6/H2 先决）
func _test_h1_contract_markers() -> void:
	var scripts: Array = [
		"res://gdscripts/paddle.gd",
		"res://gdscripts/game_manager.gd",
		"res://gdscripts/upgrade_defs.gd",
		"res://gdscripts/upgrade_pool.gd",
		"res://gdscripts/upgrade_pick_ui.gd",
		"res://gdscripts/game_hud.gd",
		"res://gdscripts/game_over_screen.gd",
		"res://gdscripts/start_menu.gd",
		"res://gdscripts/constants.gd",
	]
	for path in scripts:
		_assert(load(path) != null, "H1: %s 可加载" % path)
	var scenes: Array = [
		"res://scenes/ui_upgrade_pick.tscn",
		"res://scenes/ui_game_hud.tscn",
		"res://scenes/ui_start_menu.tscn",
	]
	for path in scenes:
		_assert(load(path) != null, "H1: %s 可加载" % path)
	_assert(CONSTS.UPGRADE_CANDIDATE_COUNT == 3, "H1: 既有候选数常量回归")
	_assert(GameManager.GameMode.SINGLE == 0 and GameManager.GameMode.LOCAL_2P == 1,
		"H1: GameManager.GameMode 枚举回归")

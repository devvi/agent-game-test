extends RefCounted
## Upgrade Pick UI test suite (#388) — 波间 3 选 1 升级选择层。
## Covers DESIGN docs/DESIGN/388-upgrade-pick-ui.md §9 Scenarios A–H（测试契约）。
##
## Uses REAL autoloads (GameManager / UpgradePool) + mini tree（ui_upgrade_pick.tscn 实例
## + 真实 WaveController + mock BreakoutGrid，#414 契约子集）。确定性前提:
## UpgradePool.rng.seed(固定值) + _reveal_hold 注入短时长 + Input.parse_input_event feed
## 动作事件（4.4-A 手动焦点状态机，无 Control focus 依赖）。
##
## Runs under godot --headless --script via run_tests.gd (_run_async — reveal/结算延时 await 需要帧循环)。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const SEED: int = 20260813
const SHORT_HOLD: float = 0.2     # _reveal_hold 注入短时长（> 输入 flush 抖动；DESIGN §9 允许）
const WAIT: float = 0.5           # > SHORT_HOLD 的等待余量

# ── Signal capture state (member vars, not lambda closures) ──
var _upgrade_applied_calls: Array = []

func _on_upgrade_applied(id: String) -> void:
	_upgrade_applied_calls.append(id)


func run() -> void:
	print("\n=== Upgrade Pick UI Tests (#388) ===")
	UpgradePool.upgrade_applied.connect(_on_upgrade_applied)

	# Scenario A: 打开与候选渲染 (AC1/AC5)
	await _test_a1_open_three_cards_focus_first()
	await _test_a2_candidates_exactly_once()
	await _test_a3_display_fallback()
	await _test_a4_wave_index_held()
	await _test_a5_idempotent_open()
	# Scenario B: 焦点切换 (AC2)
	await _test_b1_right_wraps()
	await _test_b2_left_wraps()
	await _test_b3_closed_input_gated()
	await _test_b4_revealing_input_locked()
	# Scenario C: 确认与 apply (AC2)
	await _test_c1_accept_applies_once_and_closes()
	await _test_c2_accept_applies_moved_focus()
	await _test_c3_apply_false_keeps_open()
	await _test_c4_upgrade_applied_emitted_once()
	await _test_c5_close_idempotent()
	# Scenario D: 稀有度 reveal (AC3)
	await _test_d1_before_confirm_no_rarity_clue()
	await _test_d2_after_confirm_rarity_revealed()
	await _test_d3_unselected_cards_stay_neutral()
	await _test_d4_reveal_auto_close_under_pause()
	# Scenario E: 暂停与恢复 (AC4)
	await _test_e1_open_pauses()
	await _test_e2_close_resumes()
	await _test_e3_escape_blocked_while_open()
	await _test_e4_reveal_timer_advances_under_pause()
	# Scenario F: 推进接管 (WaveController hold/advance)
	await _test_f1_default_auto_advance()
	await _test_f2_open_holds_settlement()
	await _test_f3_close_advances()
	await _test_f4_advance_not_settling_noop()
	await _test_f5_no_controller_no_crash()
	# Scenario G: 边界与失败路径
	await _test_g1_two_candidates_render()
	await _test_g2_zero_candidates_skip()
	await _test_g3_run_over_skips_ui()
	await _test_g4_reveal_then_run_over()
	await _test_g5_display_missing_fallback()
	# Scenario H: 注册与回归
	await _test_h1_scene_loads()
	await _test_h3_full_flow_smoke()

	UpgradePool.upgrade_applied.disconnect(_on_upgrade_applied)
	print("  Upgrade Pick UI: %d passed, %d failed" % [passed, failed])


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _wait(seconds: float) -> void:
	await _tree().create_timer(seconds).timeout


## 轮询等待条件成立（输入 flush / reveal 计时为帧驱动，固定延时不可靠）。
## check: Callable 返回 bool；timeout 秒内成立返回 true。lambda 只捕获节点引用（值语义安全）。
func _wait_until(check: Callable, timeout: float = 1.0) -> bool:
	var elapsed: float = 0.0
	while elapsed < timeout:
		if check.call():
			return true
		await _wait(0.02)
		elapsed += 0.02
	return false


func _reset() -> void:
	GameManager.reset_match()
	UpgradePool.stacks = {}
	UpgradePool.stub_activated = {}
	UpgradePool._available = UpgradePool.get_definitions().duplicate()
	_tree().paused = false
	_upgrade_applied_calls.clear()


func _make_mock_grid() -> Node2D:
	## Mock BreakoutGrid — #414 契约子集（同 test_wave_cycle.gd 夹具）。
	var code = GDScript.new()
	code.source_code = """extends Node2D
## Mock BreakoutGrid (#414 契约子集，test_upgrade_pick_ui.gd 内部使用)

signal wall_cleared()

var remaining_bricks: int = 0
var generate_calls: Array = []
var clear_calls: int = 0

func generate_wave(thickness: int, layout: int, seed: int) -> void:
	clear_wall()
	generate_calls.append([thickness, layout, seed])
	remaining_bricks = thickness

func clear_wall() -> void:
	clear_calls += 1
	remaining_bricks = 0
"""
	code.reload()
	var grid = Node2D.new()
	grid.name = "BreakoutGrid"
	grid.set_script(code)
	return grid


func _make_input_sentinel() -> Node:
	## PAUSABLE 输入哨兵（TC-E3）：树级暂停下 _input 应被 process_mode 门控抑制。
	var code = GDScript.new()
	code.source_code = """extends Node
var cancel_seen: int = 0
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancel_seen += 1
"""
	code.reload()
	var n = Node.new()
	n.name = "InputSentinel"
	n.set_script(code)
	return n


## 建 mini tree: host + 可选 WaveController(含 mock grid)。返回 {host, ui, controller, grid}。
func _make_ui(with_controller: bool = true) -> Dictionary:
	var tree = _tree()
	var host = Node2D.new()
	host.name = "TestHost"
	tree.root.add_child(host)

	var ui_scene = load("res://scenes/ui_upgrade_pick.tscn")
	var ui = ui_scene.instantiate()
	host.add_child(ui)
	ui._reveal_hold = SHORT_HOLD   # 注入短 reveal 展示时长（DESIGN §9）

	var controller = null
	var grid = null
	if with_controller:
		grid = _make_mock_grid()
		host.add_child(grid)
		controller = Node.new()
		controller.set_script(load("res://gdscripts/wave_controller.gd"))
		controller.name = "WaveController"
		host.add_child(controller)
		controller.settle_delay = 0.01

	return {"host": host, "ui": ui, "controller": controller, "grid": grid}


## 仅控制器 mini-tree（无 UI）——F1/F4：默认自动推进回归必须无 wave_settled 监听者。
func _make_controller_only() -> Dictionary:
	var tree = _tree()
	var host = Node2D.new()
	host.name = "TestHost"
	tree.root.add_child(host)
	var grid = _make_mock_grid()
	host.add_child(grid)
	var controller = Node.new()
	controller.set_script(load("res://gdscripts/wave_controller.gd"))
	controller.name = "WaveController"
	host.add_child(controller)
	controller.settle_delay = 0.01
	return {"host": host, "ui": null, "controller": controller, "grid": grid}


func _cleanup(fx: Dictionary) -> void:
	_tree().paused = false   # 防残留暂停污染后续套件
	var ui = fx.get("ui")
	if ui != null and is_instance_valid(ui) and GameManager.wave_settled.is_connected(ui.open):
		GameManager.wave_settled.disconnect(ui.open)   # 防 queue_free 前同帧残留信号
	var host = fx.get("host")
	if host != null and is_instance_valid(host) and host.get_parent() != null:
		host.get_parent().remove_child(host)
		host.queue_free()


func _feed_action(action: String) -> void:
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.03)   # 事件在下一帧 flush 到 _unhandled_input


func _open_ui(fx: Dictionary, wave_index: int = 1) -> void:
	GameManager.wave_settled.emit(wave_index)


func _card(ui, i: int) -> PanelContainer:
	return ui._cards[i]


func _card_label(ui, i: int, label_name: String) -> Label:
	var card = _card(ui, i)
	return card.get_node("VBoxContainer/" + label_name)


func _card_border(ui, i: int) -> Color:
	var card = _card(ui, i)
	var sb = card.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		return sb.border_color
	return Color.BLACK


# ── Scenario A: 打开与候选渲染 (AC1/AC5) ──

## TC-A1: seed rng + wave_settled → visible、3 卡、focus==0、卡 0 聚焦高亮
func _test_a1_open_three_cards_focus_first() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)

	_assert(fx.ui.visible == true, "A1: open 后 UI visible")
	_assert(fx.ui._candidates.size() == 3, "A1: 3 张候选")
	_assert(fx.ui._focus_index == 0, "A1: 焦点默认在第一张")
	_assert(_card(fx.ui, 0).visible, "A1: 卡 0 可见")
	_assert(_card(fx.ui, 1).visible, "A1: 卡 1 可见")
	_assert(_card(fx.ui, 2).visible, "A1: 卡 2 可见")
	_assert(_card(fx.ui, 0).modulate == CONSTS.UPGRADE_UI_FOCUS_MODULATE, "A1: 卡 0 聚焦高亮")
	_assert(_card(fx.ui, 1).modulate == CONSTS.UPGRADE_UI_IDLE_MODULATE, "A1: 卡 1 非焦点调暗")
	_cleanup(fx)


## TC-A2: get_candidates 恰好被调一次 + 卡片内容与候选一致（rng 消耗量探针）
func _test_a2_candidates_exactly_once() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var ref_a: Array = UpgradePool.get_candidates(3)   # 掷 1–3
	var ref_b: Array = UpgradePool.get_candidates(3)   # 掷 4–6（连续两次调用的基准）
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)

	var probe: Array = UpgradePool.get_candidates(3)   # 从 UI 消耗后的 rng 状态继续
	_assert(fx.ui._candidates.size() == 3, "A2: 候选 3 张")
	_assert(fx.ui._candidates[0].id == ref_a[0].id, "A2: 卡 0 id == 种子序列首掷结果")
	_assert(fx.ui._candidates[1].id == ref_a[1].id, "A2: 卡 1 id == 种子序列结果")
	_assert(fx.ui._candidates[2].id == ref_a[2].id, "A2: 卡 2 id == 种子序列结果")
	_assert(probe[0].id == ref_b[0].id and probe[1].id == ref_b[1].id and probe[2].id == ref_b[2].id,
		"A2: get_candidates 恰好被调一次（rng 消耗量 == 一次调用）")
	_assert(_card_label(fx.ui, 0, "NameLabel").text == ref_a[0].get("name", ""),
		"A2: 卡 0 名称 == 候选 name（兜底链）")
	_assert(_card_label(fx.ui, 0, "EffectDescLabel").text == ref_a[0].get("effect_desc", ""),
		"A2: 卡 0 效果描述 == 候选 effect_desc")
	_cleanup(fx)


## TC-A3: display 兜底链 — display 为空时回退 name / 短句留空
func _test_a3_display_fallback() -> void:
	_reset()
	UpgradePool._display = {}   # 模拟 #395 JSON 缺失/损坏（UpgradePool 兜底后 display 为空）
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)

	var cand0: Dictionary = fx.ui._candidates[0]
	_assert(cand0.get("display", {}).is_empty(), "A3: 前置 display 为空")
	_assert(_card_label(fx.ui, 0, "NameLabel").text == cand0.get("name", ""),
		"A3: 名称回退工作名 name")
	_assert(_card_label(fx.ui, 0, "ShortPhraseLabel").text == "",
		"A3: 短句留空（display 缺失不崩）")
	_cleanup(fx)
	UpgradePool.reload_display_names()   # 恢复 #395 JSON 显示名


## TC-A4: open(wave_index) 的波次号被正确持有
func _test_a4_wave_index_held() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx, 7)
	_assert(fx.ui._wave_index == 7, "A4: _wave_index == 7")
	_cleanup(fx)


## TC-A5: 幂等 — 已打开再收 wave_settled → no-op（候选不重复取、状态不变）
func _test_a5_idempotent_open() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	var before: Array = fx.ui._candidates.duplicate()
	await _open_ui(fx)   # 重复 wave_settled → 应 no-op（幂等，边界 3）
	await _wait(0.03)

	_assert(fx.ui._candidates == before, "A5: 候选未变（未重取 get_candidates）")
	_assert(fx.ui._state == fx.ui.UIState.SELECTING, "A5: 状态仍 SELECTING")
	_assert(fx.ui.visible == true, "A5: UI 保持打开")
	_cleanup(fx)


# ── Scenario B: 焦点切换 (AC2) ──

## TC-B1: ui_right ×3 → 0→1→2→0 环绕，聚焦高亮跟随
func _test_b1_right_wraps() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)

	await _feed_action("ui_right")
	_assert(fx.ui._focus_index == 1, "B1: 右移 → 1")
	_assert(_card(fx.ui, 1).modulate == CONSTS.UPGRADE_UI_FOCUS_MODULATE, "B1: 卡 1 高亮跟随")
	await _feed_action("ui_right")
	_assert(fx.ui._focus_index == 2, "B1: 右移 → 2")
	await _feed_action("ui_right")
	_assert(fx.ui._focus_index == 0, "B1: 右移环绕 → 0")
	_assert(_card(fx.ui, 0).modulate == CONSTS.UPGRADE_UI_FOCUS_MODULATE, "B1: 卡 0 高亮跟随")
	_cleanup(fx)


## TC-B2: ui_left → 0→2 反向环绕
func _test_b2_left_wraps() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	await _feed_action("ui_left")
	_assert(fx.ui._focus_index == 2, "B2: 左移反向环绕 → 2")
	await _feed_action("ui_left")
	_assert(fx.ui._focus_index == 1, "B2: 左移 → 1")
	_cleanup(fx)


## TC-B3: CLOSED 态 feed 方向/确认键 → 无任何状态变化（输入门控）
func _test_b3_closed_input_gated() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _feed_action("ui_right")
	await _feed_action("ui_accept")
	_assert(fx.ui.visible == false, "B3: CLOSED 下输入不弹 UI")
	_assert(fx.ui._focus_index == 0, "B3: 焦点不变")
	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "B3: 状态不变")
	_assert(_tree().paused == false, "B3: 不暂停")
	_cleanup(fx)


## TC-B4: REVEALING 态 feed 方向/确认键 → 无状态变化（确认后输入锁定）
func _test_b4_revealing_input_locked() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	var chosen_id: String = fx.ui._candidates[0].id
	await _feed_action("ui_accept")   # → REVEALING
	_assert(await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.REVEALING),
		"B4: 确认后 REVEALING")
	var focus_before: int = fx.ui._focus_index
	await _feed_action("ui_right")
	await _feed_action("ui_accept")
	_assert(fx.ui._focus_index == focus_before, "B4: REVEALING 中方向键被锁定")
	_assert(UpgradePool.get_stacks(chosen_id) == 1, "B4: REVEALING 中确认键不重复 apply")
	await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED)
	_cleanup(fx)


# ── Scenario C: 确认与 apply (AC2) ──

## TC-C1: ui_accept → apply(选中 id) 恰好一次 → 短暂 reveal 后 UI 隐藏
func _test_c1_accept_applies_once_and_closes() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	var chosen_id: String = fx.ui._candidates[0].id
	await _feed_action("ui_accept")
	_assert(await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED),
		"C1: reveal 展示后自动 close")

	_assert(UpgradePool.get_stacks(chosen_id) == 1, "C1: apply 恰好一次（stacks == 1）")
	_assert(_upgrade_applied_calls.size() == 1 and _upgrade_applied_calls[0] == chosen_id,
		"C1: upgrade_applied 恰好一次且 id 正确")
	_assert(fx.ui.visible == false, "C1: UI 隐藏")
	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "C1: 状态回 CLOSED")
	_assert(_tree().paused == false, "C1: 暂停恢复")
	_cleanup(fx)


## TC-C2: 先 ui_right 再 ui_accept → apply 参数为移动后的焦点卡 id
func _test_c2_accept_applies_moved_focus() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	var moved_id: String = fx.ui._candidates[2].id   # 左移一格到 2
	await _feed_action("ui_left")
	await _feed_action("ui_accept")
	await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED)

	_assert(fx.ui._focus_index == 2, "C2: 确认前焦点在 2")
	_assert(UpgradePool.get_stacks(moved_id) == 1, "C2: apply 的是移动后的焦点卡 id")
	_cleanup(fx)


## TC-C3: apply 返回 false → 保持打开、paused 保持 true、无推进调用
func _test_c3_apply_false_keeps_open() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(true)
	await _open_ui(fx)
	UpgradePool._available = []   # 注入耗尽场景 → apply 返回 false
	await _feed_action("ui_accept")
	await _wait(WAIT)   # 反断言：足够长时间后仍应保持打开（无 close 路径）

	_assert(fx.ui.visible == true, "C3: apply 失败保持打开")
	_assert(fx.ui._state == fx.ui.UIState.SELECTING, "C3: 状态仍 SELECTING（可重选）")
	_assert(_tree().paused == true, "C3: 暂停保持 true")
	_assert(UpgradePool.get_stacks(fx.ui._candidates[0].id) == 0, "C3: 未应用（stacks == 0）")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "C3: 未推进（波次状态不变）")
	_assert(GameManager.wave_index == 0, "C3: 未推进（wave_index 不变）")
	_cleanup(fx)


## TC-C4: 成功 apply 时 upgrade_applied 恰好 emit 一次（reveal 锚点）
func _test_c4_upgrade_applied_emitted_once() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	await _feed_action("ui_accept")
	await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED)
	_assert(_upgrade_applied_calls.size() == 1, "C4: upgrade_applied 恰好一次")
	_cleanup(fx)


## TC-C5: close() 重复调用幂等（第二次直接 return）
func _test_c5_close_idempotent() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	fx.ui.close()
	fx.ui.close()   # 第二次：_state 已 CLOSED → no-op
	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "C5: close 幂等")
	_assert(_tree().paused == false, "C5: 暂停已恢复")
	_cleanup(fx)


# ── Scenario D: 稀有度 reveal (AC3) ──

## TC-D1: 确认前无稀有度线索 — RarityLabel 空/隐藏、边框中性
func _test_d1_before_confirm_no_rarity_clue() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	_assert(_card_label(fx.ui, 0, "RarityLabel").text == "", "D1: 确认前稀有度名称为空")
	_assert(_card_label(fx.ui, 0, "RarityLabel").visible == false, "D1: 确认前稀有度标签隐藏")
	_assert(_card_label(fx.ui, 1, "RarityLabel").text == "", "D1: 卡 1 亦无稀有度线索")
	_assert(_card_border(fx.ui, 0) == CONSTS.UPGRADE_UI_FOCUS_BORDER, "D1: 焦点卡边框为聚焦高亮（中性系，非稀有度色）")
	_assert(_card_border(fx.ui, 1) == CONSTS.UPGRADE_UI_NEUTRAL_BORDER, "D1: 非焦点卡边框为中性霓虹色")
	var rarity: int = fx.ui._candidates[0].rarity
	_assert(_card_border(fx.ui, 0) != CONSTS.UPGRADE_RARITY_COLORS[rarity], "D1: 确认前边框不含稀有度色")
	_cleanup(fx)


## TC-D2: 确认后边框切稀有度色 + RarityLabel 显示「普通/稀有/传说」
func _test_d2_after_confirm_rarity_revealed() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	var rarity: int = fx.ui._candidates[0].rarity
	var expected_color: Color = CONSTS.UPGRADE_RARITY_COLORS[rarity]
	var expected_name: String = CONSTS.UPGRADE_RARITY_NAMES[rarity]
	await _feed_action("ui_accept")   # → REVEALING
	_assert(await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.REVEALING),
		"D2: REVEALING 态")
	_assert(_card_border(fx.ui, 0) == expected_color, "D2: 边框切稀有度色")
	_assert(_card_label(fx.ui, 0, "RarityLabel").text == expected_name, "D2: 稀有度名称显示")
	_assert(_card_label(fx.ui, 0, "RarityLabel").visible == true, "D2: 稀有度标签可见")
	await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED)
	_cleanup(fx)


## TC-D3: 确认后未选卡保持中性（仅所选卡 reveal）
func _test_d3_unselected_cards_stay_neutral() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	await _feed_action("ui_right")   # 焦点 → 1
	await _feed_action("ui_accept")  # 确认卡 1
	_assert(await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.REVEALING),
		"D3: 确认后 REVEALING")

	_assert(_card_border(fx.ui, 1) == CONSTS.UPGRADE_RARITY_COLORS[fx.ui._candidates[1].rarity],
		"D3: 所选卡 reveal 稀有度色")
	_assert(_card_border(fx.ui, 0) == CONSTS.UPGRADE_UI_NEUTRAL_BORDER, "D3: 卡 0 保持中性边框")
	_assert(_card_label(fx.ui, 0, "RarityLabel").text == "", "D3: 卡 0 无稀有度名称")
	_assert(_card_label(fx.ui, 2, "RarityLabel").text == "", "D3: 卡 2 无稀有度名称")
	await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED)
	_cleanup(fx)


## TC-D4: REVEALING 展示时长按 _reveal_hold → 超时自动 close（paused 下计时仍推进）
func _test_d4_reveal_auto_close_under_pause() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	await _feed_action("ui_accept")
	_assert(await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.REVEALING),
		"D4: 进入 REVEALING")
	_assert(_tree().paused == true and fx.ui.visible == true, "D4: reveal 期间 paused + 可见")
	_assert(await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED),
		"D4: 超时后自动 close（paused 下计时推进）")
	_assert(fx.ui.visible == false, "D4: 超时后隐藏")
	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "D4: 状态回 CLOSED")
	_assert(_tree().paused == false, "D4: close 恢复 paused")
	_cleanup(fx)


# ── Scenario E: 暂停与恢复 (AC4) ──

## TC-E1: open() 后 get_tree().paused == true
func _test_e1_open_pauses() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	_assert(_tree().paused == true, "E1: open 后游戏时间暂停")
	_cleanup(fx)


## TC-E2: close() 后 get_tree().paused == false
func _test_e2_close_resumes() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	fx.ui.close()
	_assert(_tree().paused == false, "E2: close 后恢复")
	_cleanup(fx)


## TC-E3: UI 打开（paused=true）时 feed ui_cancel → PAUSABLE 输入被屏蔽、UI 保持打开
func _test_e3_escape_blocked_while_open() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	var sentinel = _make_input_sentinel()
	fx.host.add_child(sentinel)
	await _open_ui(fx)
	await _feed_action("ui_cancel")
	await _feed_action("ui_cancel")

	_assert(sentinel.cancel_seen == 0, "E3: 暂停下 PAUSABLE 节点 _input 被屏蔽（Escape 不误触 FSM）")
	_assert(fx.ui.visible == true, "E3: UI 保持打开")
	_assert(fx.ui._state == fx.ui.UIState.SELECTING, "E3: 状态不变")
	_assert(_tree().paused == true, "E3: 暂停保持")
	_cleanup(fx)


## TC-E4: paused=true 下 REVEALING 计时照常推进（close 在 paused 态发生且恢复）
func _test_e4_reveal_timer_advances_under_pause() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	await _feed_action("ui_accept")
	_assert(await _wait_until(func() -> bool: return fx.ui._state == fx.ui.UIState.CLOSED),
		"E4: paused 下 reveal 计时照常推进 → close")
	_assert(_tree().paused == false, "E4: close 恢复 paused=false")
	_cleanup(fx)


# ── Scenario F: 推进接管 (WaveController hold/advance) ──

## TC-F1: 默认 settle_hold == false → wall_cleared 后自动延时推进（回归 #386 行为）
func _test_f1_default_auto_advance() -> void:
	_reset()
	var fx = _make_controller_only()   # 无 UI 监听者 → 默认自动推进（#386 行为回归）
	fx.controller._advance_wave()   # 波 1 RUNNING
	await _wait(0.02)
	fx.grid.wall_cleared.emit()
	await _wait(WAIT)   # SHORT_SETTLE(0.01) 后自动推进

	_assert(fx.controller.settle_hold == false, "F1: 默认 settle_hold == false")
	_assert(GameManager.wave_index == 2, "F1: 自动进下一波（wave_index == 2）")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "F1: RUNNING")
	_assert(fx.grid.generate_calls.size() == 2, "F1: 第二波 generate_wave 被调")
	_cleanup(fx)


## TC-F2: UI open 后 settle_hold == true → wall_cleared 结算后不自动推进
func _test_f2_open_holds_settlement() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(true)
	fx.controller._advance_wave()   # 波 1
	await _wait(0.02)
	fx.grid.wall_cleared.emit()     # → settle_wave → wave_settled → UI.open → hold
	await _wait(0.03)

	_assert(fx.ui.visible == true, "F2: UI 已打开")
	_assert(fx.controller.settle_hold == true, "F2: UI open 置 settle_hold == true")
	_assert(GameManager.wave_state == GameManager.WaveState.SETTLED, "F2: 仍 SETTLED")
	_assert(GameManager.wave_index == 1, "F2: 未自动推进（wave_index 仍 1）")
	_assert(fx.grid.generate_calls.size() == 1, "F2: 无新墙生成")
	await _wait(WAIT)   # 若误推进会在此暴露
	_assert(GameManager.wave_index == 1, "F2: 等待后仍未推进（hold 生效）")
	_cleanup(fx)


## TC-F3: UI close → advance_settlement → _advance_wave（wave_index +1、wave_started）
func _test_f3_close_advances() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(true)
	fx.controller._advance_wave()
	await _wait(0.02)
	fx.grid.wall_cleared.emit()
	await _wait(0.03)
	fx.ui.close()
	await _wait(0.03)

	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "F3: UI 已关闭")
	_assert(_tree().paused == false, "F3: 暂停恢复")
	_assert(fx.controller._settling == false, "F3: _settling 复位")
	_assert(GameManager.wave_index == 2, "F3: advance_settlement 推进 → wave_index == 2")
	_assert(GameManager.wave_state == GameManager.WaveState.RUNNING, "F3: RUNNING")
	_assert(fx.grid.generate_calls.size() == 2, "F3: 第二波墙已生成")
	_cleanup(fx)


## TC-F4: 非结算期调 advance_settlement() → no-op（不推进、不崩）
func _test_f4_advance_not_settling_noop() -> void:
	_reset()
	var fx = _make_controller_only()
	fx.controller.advance_settlement()
	_assert(GameManager.wave_index == 0, "F4: 非结算期不推进")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "F4: 状态不变")
	_assert(fx.grid.generate_calls.size() == 0, "F4: 不生成")
	_cleanup(fx)


## TC-F5: group 无 WaveController → UI open/close 不崩；close 不推进
func _test_f5_no_controller_no_crash() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)   # 无 WaveController
	await _open_ui(fx)
	_assert(fx.ui.visible == true, "F5: 无 controller 时 UI 照常打开")
	fx.ui.close()
	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "F5: close 不崩")
	_assert(_tree().paused == false, "F5: 暂停恢复")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "F5: 无推进（no-op）")
	_cleanup(fx)


# ── Scenario G: 边界与失败路径 ──

## TC-G1: 候选 2 张 → 渲染 2 卡（第 3 卡隐藏）、ui_right 0→1→0 环绕
func _test_g1_two_candidates_render() -> void:
	_reset()
	var defs: Array = UpgradePool.get_definitions()
	UpgradePool._available = [defs[0], defs[1]]   # 只剩 2 张（池耗尽场景）
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)

	_assert(fx.ui._candidates.size() == 2, "G1: 候选 2 张")
	_assert(_card(fx.ui, 0).visible and _card(fx.ui, 1).visible, "G1: 卡 0/1 可见")
	_assert(_card(fx.ui, 2).visible == false, "G1: 第 3 卡隐藏")
	_assert(fx.ui._focus_index == 0, "G1: 焦点 clamp 到 0")
	await _feed_action("ui_right")
	_assert(fx.ui._focus_index == 1, "G1: 右移 → 1")
	await _feed_action("ui_right")
	_assert(fx.ui._focus_index == 0, "G1: 环绕 → 0")
	_cleanup(fx)


## TC-G2: 候选 0 张 → 不弹 UI、paused 保持 false（静默跳过）
func _test_g2_zero_candidates_skip() -> void:
	_reset()
	UpgradePool._available = []
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	await _wait(0.03)

	_assert(fx.ui.visible == false, "G2: 无候选不弹 UI")
	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "G2: 状态保持 CLOSED")
	_assert(_tree().paused == false, "G2: 不暂停")
	_cleanup(fx)


## TC-G3: 终局竞态 — is_run_over() 时 emit wave_settled → 不弹 UI、不暂停
func _test_g3_run_over_skips_ui() -> void:
	_reset()
	GameManager.add_score("player", 21)
	_assert(GameManager.is_run_over() == true, "G3: 前置 run over")
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)
	await _wait(0.03)

	_assert(fx.ui.visible == false, "G3: 终局不弹 UI")
	_assert(_tree().paused == false, "G3: 不暂停")
	_cleanup(fx)


## TC-G4: reveal 期间终局 → close 后 advance_settlement 走 run-over 分支（end_wave_cycle 不生成新墙）
func _test_g4_reveal_then_run_over() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(true)
	fx.controller._advance_wave()   # 波 1
	await _wait(0.02)
	fx.grid.wall_cleared.emit()     # → UI.open + hold
	await _wait(0.03)
	await _feed_action("ui_accept") # → REVEALING
	await _wait(0.02)
	GameManager.add_score("player", 21)   # reveal 期间终局
	await _wait(WAIT)   # SHORT_HOLD 后 close → advance_settlement → run-over 分支

	_assert(GameManager.is_run_over() == true, "G4: 终局成立")
	_assert(GameManager.wave_state == GameManager.WaveState.IDLE, "G4: end_wave_cycle → IDLE")
	_assert(GameManager.wave_index == 1, "G4: wave_index 保留")
	_assert(fx.grid.generate_calls.size() == 1, "G4: 不生成新墙（仅波 1）")
	_assert(fx.controller._settling == false, "G4: _settling 复位")
	_cleanup(fx)


## TC-G5: display 字段全缺失 → 卡片用工作名/effect_desc 兜底渲染（极端兜底）
func _test_g5_display_missing_fallback() -> void:
	_reset()
	UpgradePool._display = {}
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(false)
	await _open_ui(fx)

	for i in fx.ui._candidates.size():
		var cand: Dictionary = fx.ui._candidates[i]
		_assert(_card_label(fx.ui, i, "NameLabel").text == cand.get("name", ""),
			"G5: 卡 %d 名称回退 name" % i)
		_assert(_card_label(fx.ui, i, "EffectDescLabel").text == cand.get("effect_desc", ""),
			"G5: 卡 %d 效果回退 effect_desc" % i)
		_assert(_card_label(fx.ui, i, "ShortPhraseLabel").text == "", "G5: 卡 %d 短句为空" % i)
	_cleanup(fx)
	UpgradePool.reload_display_names()


# ── Scenario H: 注册与回归 ──

## TC-H1: 场景与脚本可加载（run_tests.gd 注册由套件被调用本身证明）
func _test_h1_scene_loads() -> void:
	_reset()
	var scene = load("res://scenes/ui_upgrade_pick.tscn")
	var script = load("res://gdscripts/upgrade_pick_ui.gd")
	_assert(scene != null, "H1: ui_upgrade_pick.tscn 可加载")
	_assert(script != null, "H1: upgrade_pick_ui.gd 可加载")


## TC-H3: headless 全流程 smoke — seed → open → 切换 → 确认 → reveal → close 无异常
func _test_h3_full_flow_smoke() -> void:
	_reset()
	UpgradePool.rng.seed = SEED
	var fx = _make_ui(true)
	fx.controller._advance_wave()
	await _wait(0.02)
	fx.grid.wall_cleared.emit()
	await _wait(0.03)

	_assert(fx.ui.visible == true and fx.ui._focus_index == 0, "H3: 弹出且焦点 0")
	await _feed_action("ui_right")
	await _feed_action("ui_right")
	_assert(fx.ui._focus_index == 2, "H3: 切换焦点到 2")
	await _feed_action("ui_accept")
	await _wait(0.02)
	_assert(fx.ui._state == fx.ui.UIState.REVEALING, "H3: reveal 态")
	await _wait(WAIT)
	_assert(fx.ui._state == fx.ui.UIState.CLOSED, "H3: 自动 close")
	_assert(_tree().paused == false, "H3: 暂停恢复")
	_assert(GameManager.wave_index == 2, "H3: 推进到波 2")
	_cleanup(fx)

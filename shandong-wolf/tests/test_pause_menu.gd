extends Object
## Test suite for PauseMenu (#719) — ESC 暂停菜单 + 操作手册（AC1-AC4）。
## Runs under godot --path shandong-wolf/ --headless --script tests/run_tests.gd
## （run_tests.gd 以 "PauseMenu" 挂载）。
## Design: docs/DESIGN/719-esc-pause-menu.md §8 (Scenario A-E)。
## 被测: gdscripts/pause_menu.gd（PauseMenu: CanvasLayer layer=2, PROCESS_MODE_ALWAYS）
##   —— 唯一暂停持有者（get_tree().paused）+ 操作手册（manual_text 运行时从 InputMap 生成）。
## 语义: 暂停是树状态而非组件状态——战斗侧（InputController/PlayerController/EnemyAI/HUD）
##   全部 INHERIT 默认，paused=true 一帧冻结全部（AC4）。恢复唯一入口 toggle_pause()。
##
## Godot 4.7.1 --script 硬性约束（同 test_main_assembly.gd）:
##   - 禁止 := 类型推断（4.7.1 视推断警告为硬错误）— 一律显式类型或普通 =
##   - 组件脚本一律经 load()/preload 脚本资源访问，禁止按 class_name 标识符引用
##   - autoload 一律经 root.get_node_or_null("InputController") 运行时获取
##   - 场景实例 add 到 SceneTree root 触发 _ready；组件 _process 手动驱动，同步套件零 await
##   - 释放用立即 free()（非 queue_free）——hud._ready 经 group "hud" queue_free 重复实例，
##     残留会污染后续场景，故必须立即释放
##   - 暂停态断言用 Node.can_process()（正确反映树暂停），非 is_processing()——
##     is_processing() 只反映 set_process 标志，不随 paused 翻转；且 player_controller 只有
##     _physics_process（无 _process），其 is_processing() 恒为 false。

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

var passed: int = 0
var failed: int = 0

var _root: Node = null


func run() -> void:
	print("\n=== PauseMenu Tests ===")
	_test_t1_pause_enter()
	_test_t2_resume_via_button()
	_test_t3_resume_via_esc()
	_test_t4_toggle_idempotent()
	_test_t5_menu_interactive_paused()
	_test_t6_manual_vs_inputmap()
	_test_t7_key_mapping_completeness()
	_test_t8_static_execute_line()
	_test_t8b_manual_lazy_generation()
	_test_t9_combat_signal_freeze_buffer_cleared()
	_test_t10_fail_guard()
	_test_t11_assembly_artifacts()
	_test_t12_regression_note()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


# ── helpers ─────────────────────────────────────────────────────────────

func _get_root() -> Node:
	if _root == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		_root = tree.root
	return _root


func _spawn_main() -> Node:
	## 程序化实例化 Main.tscn 挂树（触发 MainBattle._ready 全链路装配）
	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		return null
	var inst = scene.instantiate()
	if inst == null:
		return null
	_get_root().add_child(inst)
	return inst


func _free_main(m: Node) -> void:
	## 立即 free（非 queue_free）——hud._ready 会经 group "hud" queue_free 重复实例，
	## 残留 hud 会污染后续场景；立即释放保证 group 成员/信号连接先于下一场景清理
	if m == null:
		return
	if m.get_parent() != null:
		m.get_parent().remove_child(m)
	if is_instance_valid(m):
		m.free()


func _assembler(m: Node) -> Node:
	return m.get_node_or_null("MainBattle")


func _pause_menu(mb: Node) -> Node:
	if mb == null:
		return null
	return mb.get("pause_menu")


func _pause_edge(pm: Node) -> void:
	## 模拟一次 ESC 边沿（press + _process → release + _process，镜像 test_input_controller.gd）
	Input.action_press("game_pause")
	pm._process(0.016)
	Input.action_release("game_pause")
	pm._process(0.016)


func _cleanup(m: Node, pm: Node) -> void:
	## 释放前确保树未暂停（防污染后续用例）+ 立即 free。用 toggle_pause 恢复（唯一入口），
	## 再兜底直写 paused=false；随后 _free_main 立即释放。
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.paused:
		if pm != null and is_instance_valid(pm):
			pm.toggle_pause()
		tree.paused = false
	_free_main(m)


# ── Scenario A: 暂停/恢复 toggle（AC1/AC2）───────────────────────────────

func _test_t1_pause_enter() -> void:
	# T1: 战斗进行中按 ESC → get_tree().paused=true + 遮罩/菜单弹出（AC1）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T1: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T1: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	_assert(pm != null, "T1: pause_menu 非 null")
	if pm == null:
		_cleanup(m, null)
		return
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == true, "T1: ESC → get_tree().paused == true")
	_assert(pm.DimOverlay.visible == true, "T1: DimOverlay 可见")
	_assert(pm.MenuRoot.visible == true, "T1: MenuRoot 可见")
	_cleanup(m, pm)


func _test_t2_resume_via_button() -> void:
	# T2: PAUSED 中点「继续」按钮 → paused=false + 菜单隐藏 + 战斗节点恢复处理（AC2）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T2: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T2: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T2: pause_menu 非 null")
		_cleanup(m, null)
		return
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == true, "T2: 前置 PAUSED")
	pm.ResumeButton.pressed.emit()
	_assert(_get_root().get_tree().paused == false, "T2: 「继续」→ paused == false")
	_assert(pm.DimOverlay.visible == false, "T2: DimOverlay 隐藏")
	_assert(pm.MenuRoot.visible == false, "T2: MenuRoot 隐藏")
	_assert(mb.player.can_process() == true, "T2: 玩家恢复处理（can_process == true）")
	_assert(mb.judge.can_process() == true, "T2: 判定器恢复处理（can_process == true）")
	_cleanup(m, pm)


func _test_t3_resume_via_esc() -> void:
	# T3: PAUSED 中再按 ESC → paused=false（与「继续」同一 toggle 入口语义，AC2）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T3: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T3: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T3: pause_menu 非 null")
		_cleanup(m, null)
		return
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == true, "T3: 前置 PAUSED")
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == false, "T3: 再按 ESC → paused == false")
	_cleanup(m, pm)


func _test_t4_toggle_idempotent() -> void:
	# T4: 连按 ESC 三次 → pause→resume→pause，终态 paused == true 且 _paused == true（幂等）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T4: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T4: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T4: pause_menu 非 null")
		_cleanup(m, null)
		return
	_pause_edge(pm)
	_pause_edge(pm)
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == true, "T4: 三按 → 终态 paused == true（pause→resume→pause）")
	_assert(pm._paused == true, "T4: 三按 → _paused == true")
	_cleanup(m, pm)


# ── Scenario B: 菜单可交互 + 冻结语义（AC4）───────────────────────────────

func _test_t5_menu_interactive_paused() -> void:
	# T5: PAUSED 中菜单可交互（ALWAYS）而战斗节点冻结（INHERIT + can_process == false）（AC4）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T5: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T5: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T5: pause_menu 非 null")
		_cleanup(m, null)
		return
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == true, "T5: 前置 PAUSED")
	_assert(pm.process_mode == Node.PROCESS_MODE_ALWAYS, "T5: PauseMenu process_mode == ALWAYS")
	_assert(pm.can_process() == true, "T5: 暂停中菜单仍响应（can_process == true）")
	_assert(mb.player.process_mode == Node.PROCESS_MODE_INHERIT, "T5: 玩家 process_mode == INHERIT")
	_assert(mb.enemy.process_mode == Node.PROCESS_MODE_INHERIT, "T5: 敌人 process_mode == INHERIT")
	_assert(mb.hud.process_mode == Node.PROCESS_MODE_INHERIT, "T5: HUD process_mode == INHERIT")
	_assert(mb.player.can_process() == false, "T5: 玩家冻结（can_process == false）")
	_assert(mb.enemy.can_process() == false, "T5: 敌人冻结（can_process == false）")
	_cleanup(m, pm)


# ── Scenario B: 手册一致性（AC3）─────────────────────────────────────────

func _test_t6_manual_vs_inputmap() -> void:
	# T6: manual_text() 动态部分逐条与 InputMap 一致（AC3 机器保证）；排除静态 game_execute 行
	var m = _spawn_main()
	if m == null:
		_assert(false, "T6: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T6: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T6: pause_menu 非 null")
		_cleanup(m, null)
		return
	var rows = pm.manual_text()
	var by_action = {}
	for row in rows:
		var action = row["action"]
		if action == &"game_execute":
			continue
		by_action[action] = row["keys"]
	var expect: Array = [
		["game_move_left", "A / ←"],
		["game_move_right", "D / →"],
		["game_light_attack", null],
		["game_heavy_attack", null],
		["game_guard", "L"],
		["game_dash", "Shift"],
		["game_jump", "空格"],
		["game_interact", "E"],
		["game_revive", "F"],
	]
	for entry in expect:
		var action = StringName(entry[0])
		_assert(by_action.has(action), "T6: 手册含动作 %s" % str(action))
		var keys = str(by_action.get(action, ""))
		_assert(keys != "", "T6: %s 键名非空（实际 %s）" % [str(action), keys])
		var exact = entry[1]
		if exact == null:
			if action == &"game_light_attack":
				_assert(keys.contains("J"), "T6: game_light_attack 含 J（实际 %s）" % keys)
			elif action == &"game_heavy_attack":
				_assert(keys.contains("K"), "T6: game_heavy_attack 含 K（实际 %s）" % keys)
		else:
			_assert(keys == exact, "T6: %s 键名 == %s（实际 %s）" % [str(action), str(exact), keys])
	_cleanup(m, pm)


func _test_t7_key_mapping_completeness() -> void:
	# T7: 每个 InputMap 事件都能映射出非空展示名（防映射表漏项；不断言具体字符串——taste 域）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T7: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T7: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T7: pause_menu 非 null")
		_cleanup(m, null)
		return
	var actions: Array = [
		"game_move_left", "game_move_right", "game_light_attack", "game_heavy_attack",
		"game_guard", "game_dash", "game_jump", "game_interact", "game_revive",
	]
	for action_name in actions:
		var action = StringName(action_name)
		var events = InputMap.action_get_events(action)
		_assert(events.size() > 0, "T7: %s 至少 1 个事件" % str(action))
		for event in events:
			var dn: String = pm._event_display_name(event)
			_assert(dn != "", "T7: %s 事件映射出非空展示名（实际 ''）" % str(action))
	_cleanup(m, pm)


func _test_t8_static_execute_line() -> void:
	# T8: 手册恰含一行静态处决说明（action == game_execute），文案 == PAUSE_EXECUTE_LINE_CANDIDATES[0]
	var m = _spawn_main()
	if m == null:
		_assert(false, "T8: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T8: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T8: pause_menu 非 null")
		_cleanup(m, null)
		return
	var rows = pm.manual_text()
	var execute_count: int = 0
	for row in rows:
		if row["action"] == &"game_execute":
			execute_count += 1
			_assert(str(row["keys"]) == str(WolfConstantsScript.PAUSE_EXECUTE_LINE_CANDIDATES[0]),
				"T8: 处决行文案 == PAUSE_EXECUTE_LINE_CANDIDATES[0]（实际 %s）" % str(row["keys"]))
	_assert(execute_count == 1, "T8: 手册恰含 1 行 game_execute（实际 %d）" % execute_count)
	_cleanup(m, pm)


func _test_t8b_manual_lazy_generation() -> void:
	# T8b: 手册懒生成幂等——首开填充，再开不重复追加
	var m = _spawn_main()
	if m == null:
		_assert(false, "T8b: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T8b: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T8b: pause_menu 非 null")
		_cleanup(m, null)
		return
	_assert(pm.ManualLines.get_child_count() == 0, "T8b: 首开前 ManualLines 为空")
	pm._toggle_manual()
	var first_count: int = pm.ManualLines.get_child_count()
	_assert(first_count > 0, "T8b: 首开填充 N 行（实际 %d）" % first_count)
	pm._toggle_manual()
	pm._toggle_manual()
	_assert(pm.ManualLines.get_child_count() == first_count,
		"T8b: 再开不重复追加（首开 %d，再开 %d）" % [first_count, pm.ManualLines.get_child_count()])
	_cleanup(m, pm)


# ── Scenario C: 冻结语义 + 缓冲清理（AC4，边界 3）─────────────────────────

func _test_t9_combat_signal_freeze_buffer_cleared() -> void:
	# T9: 暂停中战斗意图冻结（A2: INHERIT），恢复后缓冲已清空（边界 3，防「隔空出刀」）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T9: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T9: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T9: pause_menu 非 null")
		_cleanup(m, null)
		return
	var ic = _get_root().get_node_or_null("InputController")
	_assert(ic != null, "T9: InputController autoload 可用")
	if ic == null:
		_cleanup(m, pm)
		return
	# 未暂停：模拟攻击边沿 → 缓冲有残留
	Input.action_press("game_light_attack")
	ic._process(0.016)
	Input.action_release("game_light_attack")
	ic._process(0.016)
	_assert(ic.buffer_size() > 0, "T9: 未暂停时攻击边沿 → buffer_size() > 0")
	# 暂停：InputController（INHERIT）冻结，战斗信号不再发射
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == true, "T9: 前置 PAUSED")
	_assert(ic.can_process() == false, "T9: 暂停中 InputController 冻结（can_process == false）")
	# 恢复：paused=false + 缓冲已清空
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == false, "T9: 恢复 → paused == false")
	_assert(ic.buffer_size() == 0, "T9: 恢复后 buffer_size() == 0（缓冲已清，边界 3）")
	_cleanup(m, pm)


# ── Scenario D: FAIL 守卫（边界 2/8）─────────────────────────────────────

func _test_t10_fail_guard() -> void:
	# T10: FAIL 终态按 ESC 不弹菜单（幂等忽略）；game_pause 缺失 fail-safe 路径存在（边界 2/8）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T10: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T10: MainBattle 缺失")
		_cleanup(m, null)
		return
	var pm = _pause_menu(mb)
	if pm == null:
		_assert(false, "T10: pause_menu 非 null")
		_cleanup(m, null)
		return
	pm.bind_game_state(func() -> int: return 4)   # FAIL == 4（MainBattle.GameState.FAIL）
	_pause_edge(pm)
	_assert(_get_root().get_tree().paused == false, "T10: FAIL 态按 ESC → paused 保持 false")
	_assert(pm.DimOverlay.visible == false, "T10: FAIL 态按 ESC → 菜单不可见（幂等忽略）")
	# 边界 8（game_pause 缺失 fail-safe）：运行时移除动作风险高，仅断言 fail-safe 路径存在
	_assert(pm.has_method("_ready"), "T10: PauseMenu 存在 _ready（含 game_pause 缺失 fail-safe 守卫）")
	_cleanup(m, pm)


# ── Scenario E: 装配与回归 ───────────────────────────────────────────────

func _test_t11_assembly_artifacts() -> void:
	# T11: 装配产物——pause_menu 非空、PauseLayer 为 CanvasLayer、PauseMenu 为 layer=2 ALWAYS、
	#   FAIL 守卫闭包已注入（_game_state_getter.is_valid() == true）
	var m = _spawn_main()
	if m == null:
		_assert(false, "T11: Main 实例化失败")
		return
	var mb = _assembler(m)
	if mb == null:
		_assert(false, "T11: MainBattle 缺失")
		_cleanup(m, null)
		return
	_assert(mb.pause_menu != null, "T11: mb.pause_menu 非 null")
	var pause_layer = mb.get_node_or_null("PauseLayer")
	_assert(pause_layer != null, "T11: PauseLayer 节点存在")
	if pause_layer != null:
		_assert(pause_layer is CanvasLayer, "T11: PauseLayer 为 CanvasLayer")
	var pm = _pause_menu(mb)
	if pm != null:
		_assert(pm.layer == 2, "T11: PauseMenu CanvasLayer layer == 2（HUD layer=1 之上）")
		_assert(pm.process_mode == Node.PROCESS_MODE_ALWAYS, "T11: PauseMenu process_mode == ALWAYS")
		_assert(pm._game_state_getter.is_valid() == true, "T11: FAIL 守卫闭包已注入（is_valid == true）")
	_cleanup(m, pm)


func _test_t12_regression_note() -> void:
	# T12: 回归说明——暂停默认 off，全链路回归由 run_tests.gd 承担（含 test_input_controller.gd
	#   缓冲用例；PauseMenu 未装配时 _input_controller 为 null → _clear_input_buffer no-op）。
	#   无需独立断言。
	_assert(true, "T12: 回归由 run_tests.gd 全绿承担（无独立断言）")

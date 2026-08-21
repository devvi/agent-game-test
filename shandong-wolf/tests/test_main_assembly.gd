extends Object
## Test suite for MainBattle 组装编排（#585）— MVP 战斗闭环装配测试套件。
## Runs under godot --path shandong-wolf/ --headless --script tests/run_tests.gd
## （run_tests.gd 以 "MainAssembly" 挂载，在全部其他套件之后运行）。
## Design: docs/DESIGN/585-mvp-combat-loop-assembly.md §8 (Scenario A-F)。
## 被测: gdscripts/main_battle.gd（BattleAssembler）——程序化装配 + 信号接线 + 游戏状态机。
##
## Godot 4.7.1 --script 硬性约束（同 test_battle_stage.gd / test_combat_judge.gd）:
##   - 禁止 := 类型推断（4.7.1 视推断警告为硬错误）— 一律显式类型或普通 =
##   - 组件脚本一律经 load()/preload 脚本资源访问，禁止按 class_name 标识符引用
##   - autoload 一律经 root.get_node_or_null("InputController") 运行时获取
##     （--script 主脚本编译早于 lazy autoload 注册，标识符不可解析）
##   - 场景实例 add 到 SceneTree root 触发 _ready；组件 _process/timer 全部手动驱动
##     （judge.tick_frame() / entity._process(delta) / revive._process(delta) /
##     execution._process(delta) / timer.timeout.emit()），同步套件，零 await
##   - 释放用立即 free()（非 queue_free）——hud._ready 经 group "hud" queue_free
##     重复实例，残留会污染后续场景，故必须立即释放

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

var passed: int = 0
var failed: int = 0

var _root: Node = null

## 信号间谍（用例间 _reset_logs() 隔离）
var _parry_spy: int = 0
var _feedback_spy: int = 0
var _revived_spy: int = 0
var _fail_subtitle_spy: int = 0
var _died_spy: Array = []       # [final, ...]
var _low_true: int = 0
var _low_false: int = 0
var _state_pairs: Array = []    # [[from, to], ...]


func run() -> void:
	print("\n=== MainAssembly Tests ===")
	_reset_logs()
	_test_a1_main_loadable()
	_reset_logs()
	_test_a2_bind_targets_non_null()
	_reset_logs()
	_test_a3_battle_stage_mounted()
	_reset_logs()
	_test_a4_title_hidden()
	_reset_logs()
	_test_b1_animation_chain()
	_reset_logs()
	_test_b2_judge_chain()
	_reset_logs()
	_test_b3_execution_chain()
	_reset_logs()
	_test_b4_hud_chain()
	_reset_logs()
	_test_b5_feedback_chain()
	_reset_logs()
	_test_b6_revive_chain()
	_reset_logs()
	_test_b7_atmosphere_edge()
	_reset_logs()
	_test_c1_full_loop()
	_reset_logs()
	_test_d1_double_death_subtitle()
	_reset_logs()
	_test_d2_input_frozen()
	_reset_logs()
	_test_d3_ai_stopped()
	_reset_logs()
	_test_d4_terminal_idempotent()
	_reset_logs()
	_test_d5_single_death_not_fail()
	_reset_logs()
	_test_e1_afterglow_timing()
	_reset_logs()
	_test_e2_readonly_input_afterglow()
	_reset_logs()
	_test_e3_snow_continues()
	_reset_logs()
	_test_f1_unbound_judge_red()
	_reset_logs()
	_test_f2_window_missed_recover()
	_reset_logs()
	_test_f3_main_resources()
	# Scenario A(#682): 精英装配（AC5）+ Scenario F(#682): HP 装配失败拦截
	_reset_logs()
	_test_a5_enemy_elite_assembly()
	_reset_logs()
	_test_f4_enemy_hp_default_intercept()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _reset_logs() -> void:
	_parry_spy = 0
	_feedback_spy = 0
	_revived_spy = 0
	_fail_subtitle_spy = 0
	_died_spy = []
	_low_true = 0
	_low_false = 0
	_state_pairs = []


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


func _enemy_hit_ms() -> int:
	## 敌攻击命中时点 = ENEMY_ATTACK_WINDUP 帧 → hit_ms = 帧 × 1000 / FRAME_RHYTHM_BASE
	return int(WolfConstantsScript.ENEMY_ATTACK_WINDUP) * 1000 / int(WolfConstantsScript.FRAME_RHYTHM_BASE)


func _drive_player_final_death(a: Node) -> void:
	## 双死序列（D1-D4 复用）: 第一命耗尽（died false）→ 手动复活 → 清无敌 →
	##   复活演出退场（revive→idle）→ 第二命耗尽（died true，终态）
	a.player_entity.take_damage(100.0)
	a.player_entity.revive()
	a.player_entity.set("_invincible_until_sec", 0.0)
	a.player_entity._process(1.1)
	a.player_entity.take_damage(100.0)


func _drive_fail_subtitle(a: Node) -> void:
	## 失败字幕时序驱动: 延迟 Timer 到期（timeout.emit）→ 淡入 tween 用 custom_step
	##   同步推进（headless 无真实帧循环；tween 由 MainBattle create_tween 绑定节点，
	##   经 SceneTree.get_processed_tweens() 枚举后推进到终点）
	if a.get("_fail_subtitle_timer") != null:
		var t = a._fail_subtitle_timer
		if t != null and is_instance_valid(t):
			t.timeout.emit()
	var tree = a.get_tree()
	if tree != null and tree.has_method("get_processed_tweens"):
		var tweens: Array = tree.get_processed_tweens()
		for t in tweens:
			var tw: Tween = t as Tween
			if tw != null and tw.is_valid():
				tw.custom_step(2.0)


func _state_sequence_has(pairs: Array, names: Array) -> bool:
	## 断言 (from,to) 对按序包含 names 状态序列（如 [IDLE,COMBAT,KILL,AFTERGLOW]）
	var idx: int = 0
	for pair in pairs:
		if pair.size() >= 2 and str(pair[0]) == str(names[idx]) and str(pair[1]) == str(names[idx + 1]):
			idx += 1
			if idx >= names.size() - 1:
				return true
	return false


## 信号 handler（member 间谍写入）
func _on_parry_spy(_defender, _attacker, _stance_damage: float) -> void:
	_parry_spy += 1


func _on_feedback_spy(_event: String, _level: String, _data: Dictionary) -> void:
	_feedback_spy += 1


func _on_revived_spy(_entity) -> void:
	_revived_spy += 1


func _on_fail_subtitle_spy() -> void:
	_fail_subtitle_spy += 1


func _on_died_spy(_entity, final: bool) -> void:
	_died_spy.append(final)


func _on_low_health_spy(enabled: bool) -> void:
	if enabled:
		_low_true += 1
	else:
		_low_false += 1


func _on_game_state_changed(from: String, to: String) -> void:
	_state_pairs.append([from, to])


# ── Scenario A: 挂载完整性（AC5「无 pending 组件」）───────────────────────

func _test_a1_main_loadable() -> void:
	# A1: Main.tscn 可加载；MainBattle 节点存在且 script == main_battle.gd
	var scene = load("res://scenes/Main.tscn")
	_assert(scene != null, "A1: Main.tscn 可加载")
	var m = _spawn_main()
	if m == null:
		_assert(false, "A1: Main.tscn 实例化失败")
		return
	var mb = m.get_node_or_null("MainBattle")
	_assert(mb != null, "A1: MainBattle 节点存在")
	if mb != null:
		_assert(mb.get_script() == load("res://gdscripts/main_battle.gd"),
			"A1: MainBattle script == main_battle.gd")
	_free_main(m)


func _test_a2_bind_targets_non_null() -> void:
	# A2: 组件引用全部非 null + bind 契约逐项断言（AC5）
	var m = _spawn_main()
	if m == null:
		_assert(false, "A2: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_assert(false, "A2: MainBattle 缺失")
		_free_main(m)
		return
	_assert(a.player != null, "A2: player 非 null")
	_assert(a.enemy != null, "A2: enemy 非 null")
	_assert(a.judge != null, "A2: judge 非 null")
	_assert(a.hud != null, "A2: hud 非 null")
	_assert(a.reaction != null, "A2: reaction 非 null")
	_assert(a.execution != null, "A2: execution 非 null")
	_assert(a.revive != null, "A2: revive 非 null")
	_assert(a.atmosphere != null, "A2: atmosphere 非 null")
	_assert(a.player_entity != null, "A2: player_entity 非 null")
	_assert(a.enemy_entity != null, "A2: enemy_entity 非 null")
	_assert(a.hud.get("_player") == a.player_entity, "A2: hud._player == player_entity")
	_assert(a.judge.player == a.player_entity, "A2: judge.player == player_entity")
	_assert(a.judge.enemy == a.enemy_entity, "A2: judge.enemy == enemy_entity")
	_assert(a.enemy.entity == a.enemy_entity, "A2: enemy.entity == enemy_entity")
	_assert(a.execution.get("_enemy") == a.enemy_entity, "A2: execution._enemy == enemy_entity")
	_free_main(m)


func _test_a3_battle_stage_mounted() -> void:
	# A3: BattleStage 挂载 + 出生点定位一致（PlayerSpawn/EnemySpawnA）
	var m = _spawn_main()
	if m == null:
		_assert(false, "A3: Main 实例化失败")
		return
	var a = _assembler(m)
	var stage = m.get_node_or_null("BattleStage")
	_assert(stage != null, "A3: Main 下 BattleStage 存在")
	if stage != null:
		var pspawn = stage.get_node_or_null("PlayerSpawn")
		var espawn = stage.get_node_or_null("EnemySpawnA")
		var cam = stage.get_node_or_null("StageCamera")
		_assert(pspawn != null and espawn != null and cam != null,
			"A3: PlayerSpawn/EnemySpawnA/StageCamera 路径可达")
		if a != null and pspawn != null:
			_assert(is_equal_approx(a.player.position.x, pspawn.position.x)
				and is_equal_approx(a.player.position.y, pspawn.position.y),
				"A3: 玩家定位 PlayerSpawn（实际 %s）" % str(a.player.position))
		if a != null and espawn != null:
			_assert(is_equal_approx(a.enemy.position.x, espawn.position.x)
				and is_equal_approx(a.enemy.position.y, espawn.position.y),
				"A3: 敌人定位 EnemySpawnA（实际 %s）" % str(a.enemy.position))
	_free_main(m)


func _test_a4_title_hidden() -> void:
	# A4: 标题 CenterContainer 已隐藏（MVP 开场直进战斗，#572 节点保留）
	var m = _spawn_main()
	if m == null:
		_assert(false, "A4: Main 实例化失败")
		return
	var canvas = m.get_node_or_null("CanvasLayer")
	_assert(canvas != null, "A4: CanvasLayer 存在")
	if canvas != null:
		var center = canvas.get_node_or_null("CenterContainer")
		_assert(center != null, "A4: CenterContainer 存在")
		if center != null:
			_assert(center.visible == false, "A4: 标题 CenterContainer 已隐藏（visible == false）")
	_free_main(m)


# ── Scenario B: 信号链连通 ───────────────────────────────────────────────

func _test_b1_animation_chain() -> void:
	# B1: 玩家动画链 —— state_changed → stick.consume_state → anim_move
	var m = _spawn_main()
	if m == null:
		_assert(false, "B1: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	var stick = a.player.get_node_or_null("PlayerStickFigure")
	_assert(stick != null, "B1: PlayerStickFigure 挂载")
	if stick != null:
		a.player_entity.state_changed.emit("idle", "move")
		var anim = stick.get("_anim")
		_assert(anim != null, "B1: stick._anim 就绪（AnimationPlayer 已解析）")
		if anim != null:
			_assert(anim.current_animation == "anim_move",
				"B1: consume_state('move') → anim_move（实际 %s）" % str(anim.current_animation))
	_free_main(m)


func _test_b2_judge_chain() -> void:
	# B2: 判定链 —— 敌人 attack → 窗口登记；guard 按下 + tick → parry_success
	var m = _spawn_main()
	if m == null:
		_assert(false, "B2: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.enemy_entity.facing = -1
	a.enemy_entity.request_transition("attack")
	_assert(a.judge._windows.size() >= 1, "B2: 敌人 attack → 判定器窗口已登记")
	a.judge.parry_success.connect(_on_parry_spy)
	a.judge._on_guard_pressed(_enemy_hit_ms())
	for i in range(13):
		a.judge.tick_frame()
	_assert(_parry_spy >= 1, "B2: 弹反触发（guard %dms = 敌命中帧 %d）" % [_enemy_hit_ms(), int(WolfConstantsScript.ENEMY_ATTACK_WINDUP)])
	_free_main(m)


func _test_b3_execution_chain() -> void:
	# B3: 处决链 —— 崩解 → armed → attack_pressed（距离内）→ died(true) 恰一次 → armed 清除
	var m = _spawn_main()
	if m == null:
		_assert(false, "B3: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.enemy_entity.facing = -1
	a.enemy_entity.take_stance_damage(100.0)
	_assert(a.enemy_entity.is_stance_broken == true, "B3: 敌架势崩解")
	_assert(a.execution.get("_armed") == true, "B3: 崩解 → 处决窗口 armed")
	a.enemy_entity.died.connect(_on_died_spy)
	var ic = _get_root().get_node_or_null("InputController")
	_assert(ic != null, "B3: InputController autoload 可用")
	if ic != null:
		ic.attack_pressed.emit()
	_assert(_died_spy.size() == 1 and _died_spy[0] == true,
		"B3: 处决 → enemy died(true) 恰一次（实际 %s）" % str(_died_spy))
	_assert(a.execution.get("_armed") == false, "B3: 触发后 armed 已清除")
	_free_main(m)


func _test_b4_hud_chain() -> void:
	# B4: HUD 链 —— hp_changed → 血条；敌 died(true) → 击杀提示可见
	var m = _spawn_main()
	if m == null:
		_assert(false, "B4: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.player_entity.take_damage(10.0)
	_assert(is_equal_approx(a.player_entity.hp_1, 90.0), "B4: 玩家 hp_1 == 90.0（实际 %s）" % str(a.player_entity.hp_1))
	_assert(a.hud.PlayerHealthBar != null, "B4: Hud.PlayerHealthBar 已创建")
	a.enemy_entity.execute_kill()
	_assert(a.hud.KillPromptLabel != null and a.hud.KillPromptLabel.visible == true,
		"B4: 击杀提示 KillPromptLabel 可见")
	_free_main(m)


func _test_b5_feedback_chain() -> void:
	# B5: 反馈链 —— 弹反 → reaction.feedback_played（bind_judge 触发）
	var m = _spawn_main()
	if m == null:
		_assert(false, "B5: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.reaction.feedback_played.connect(_on_feedback_spy)
	a.enemy_entity.facing = -1
	a.enemy_entity.request_transition("attack")
	a.judge._on_guard_pressed(_enemy_hit_ms())
	for i in range(13):
		a.judge.tick_frame()
	_assert(_feedback_spy >= 1, "B5: 弹反 → reaction.feedback_played ≥ 1（实际 %d）" % _feedback_spy)
	_free_main(m)


func _test_b6_revive_chain() -> void:
	# B6: 复活链 —— died(false) → 计时 → revived 恰一次 → 二命半管血
	var m = _spawn_main()
	if m == null:
		_assert(false, "B6: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.player_entity.take_damage(100.0)
	_assert(a.revive.is_armed() == true, "B6: 第一命耗尽 → 复活计时 armed")
	a.player_entity.revived.connect(_on_revived_spy)
	a.revive._process(1.5)
	_assert(_revived_spy == 1, "B6: 复活计时到期 → revived 恰一次（实际 %d）" % _revived_spy)
	_assert(is_equal_approx(a.player_entity.hp_2, 50.0) and a.player_entity.get("_active_life") == 2,
		"B6: 二命半管血 hp_2 == 50.0 且 active_life == 2")
	_free_main(m)


func _test_b7_atmosphere_edge() -> void:
	# B7: 低血氛围链 —— 边沿触发恰好一次 true/false，同态重驱不重发（不重入不漏发）
	var m = _spawn_main()
	if m == null:
		_assert(false, "B7: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	_assert(a.hud.low_health_changed.is_connected(a.atmosphere.set_low_health) == true,
		"B7: hud.low_health_changed → atmosphere.set_low_health 已接线")
	a.hud.low_health_changed.connect(_on_low_health_spy)
	a.hud.set_debug_hp(10.0, 50.0, 1)
	_assert(_low_true == 1 and _low_false == 0, "B7: 低血 true 边沿恰一次（10/100 < 0.30）")
	a.hud.set_debug_hp(10.0, 50.0, 1)
	_assert(_low_true == 1, "B7: 同 true 重驱不重发（边沿触发）")
	a.hud.set_debug_hp(90.0, 50.0, 1)
	_assert(_low_false == 1 and _low_true == 1, "B7: 低血 false 边沿恰一次")
	a.hud.set_debug_hp(90.0, 50.0, 1)
	_assert(_low_false == 1, "B7: 同 false 重驱不重发（边沿触发）")
	_free_main(m)


# ── Scenario C: 完整闭环（AC1/AC4）─────────────────────────────────────

func _test_c1_full_loop() -> void:
	# C1: 完整闭环 —— 遇敌(COMBAT) → 弹反 → 崩解 → 处决 → 击杀(KILL/AFTERGLOW) → 余韵到期回 IDLE
	#   驱动确定性: 判定器逻辑帧逐帧 tick_frame()；弹反窗活跃帧逐帧重复弹反属既有判定行为，
	#   预期以「弹反链打崩敌架势」收束（5×25 ≥ 100），不逐帧断言中间架势数值
	var m = _spawn_main()
	if m == null:
		_assert(false, "C1: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.game_state_changed.connect(_on_game_state_changed)
	_assert(a.game_state == a.GameState.IDLE, "C1: 初始 IDLE")

	# 1. 遇敌 → COMBAT
	a.enemy_entity.facing = -1
	a.enemy_entity.request_transition("attack")
	_assert(a.game_state == a.GameState.COMBAT, "C1: 敌人 attack → COMBAT")

	# 2. 弹反: guard 按下 hit_ms(200) 后推进到命中帧（ENEMY_ATTACK_WINDUP=12 → hit 帧 12）
	a.judge.parry_success.connect(_on_parry_spy)
	a.judge._on_guard_pressed(_enemy_hit_ms())
	for i in range(12):
		a.judge.tick_frame()
	_assert(_parry_spy >= 1, "C1: 弹反触发")
	_assert(a.enemy_entity.stance < 100.0, "C1: 弹反后敌架势下降")

	# 3-5. 玩家连段合法性（attack→attack 同态重入；窗口不 tick，避免提前结算打死敌人）
	var r1 = a.player_entity.request_transition("attack")
	_assert(r1 == true and a.player_entity.state_name == "attack", "C1: parry_success→attack 合法")
	var r2 = a.player_entity.request_transition("attack")
	_assert(r2 == true and a.player_entity.state_name == "attack", "C1: attack→attack 连段合法")
	var r3 = a.player_entity.request_transition("attack")
	_assert(r3 == true and a.player_entity.state_name == "attack", "C1: 连段再入合法")

	# 弹反活跃帧持续 → 敌架势打崩（判定器既有逐帧弹反行为）→ 处决窗口 armed
	var guard_frames: int = 0
	while not a.enemy_entity.is_stance_broken and guard_frames < 30:
		a.judge.tick_frame()
		guard_frames += 1
	_assert(a.enemy_entity.is_stance_broken == true, "C1: 弹反链 → 敌架势崩解")
	_assert(a.execution.get("_armed") == true, "C1: 崩解 → 处决窗口 armed")

	# 6. 处决 → 击杀 → KILL → AFTERGLOW（玩家输入桥同帧 attack 重入无害，见任务注记）
	a.enemy_entity.died.connect(_on_died_spy)
	var ic = _get_root().get_node_or_null("InputController")
	_assert(ic != null, "C1: InputController autoload 可用")
	if ic != null:
		ic.attack_pressed.emit()
	_assert(_died_spy.size() == 1 and _died_spy[0] == true,
		"C1: 处决 → enemy died(true) 恰一次（实际 %s）" % str(_died_spy))
	_assert(a.game_state == a.GameState.AFTERGLOW, "C1: 击杀 → AFTERGLOW")

	# 7. 状态序列断言（按序包含 IDLE→COMBAT→KILL→AFTERGLOW）
	_assert(_state_sequence_has(_state_pairs, ["IDLE", "COMBAT", "KILL", "AFTERGLOW"]),
		"C1: game_state_changed 序列含 IDLE→COMBAT→KILL→AFTERGLOW（实际 %s）" % str(_state_pairs))

	# 8. 余韵到期 → 回 IDLE（AC3 timer 往返）
	if a._afterglow_timer != null:
		a._afterglow_timer.timeout.emit()
	_assert(a.game_state == a.GameState.IDLE, "C1: 余韵到期 → IDLE")
	_free_main(m)


# ── Scenario D: 失败路径（AC2）─────────────────────────────────────────

func _test_d1_double_death_subtitle() -> void:
	# D1: 双死 → FAIL + 字幕文案 ∈ FAIL_SUBTITLE_CANDIDATES + fail_subtitle_shown 恰一次
	var m = _spawn_main()
	if m == null:
		_assert(false, "D1: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.fail_subtitle_shown.connect(_on_fail_subtitle_spy)
	_drive_player_final_death(a)
	_assert(a.game_state == a.GameState.FAIL, "D1: 双死 → FAIL")
	_drive_fail_subtitle(a)
	_assert(a.fail_label != null, "D1: fail_label 已创建")
	if a.fail_label != null:
		_assert(a.fail_label.visible == true, "D1: fail_label 可见")
		_assert(WolfConstantsScript.FAIL_SUBTITLE_CANDIDATES.has(a.fail_label.text),
			"D1: 字幕文案 ∈ FAIL_SUBTITLE_CANDIDATES（实际 %s）" % a.fail_label.text)
	_assert(_fail_subtitle_spy == 1, "D1: fail_subtitle_shown 恰一次（实际 %d）" % _fail_subtitle_spy)
	_free_main(m)


func _test_d2_input_frozen() -> void:
	# D2: FAIL 后输入冻结 —— InputController.set_process(false)，attack 无实体效果
	var m = _spawn_main()
	if m == null:
		_assert(false, "D2: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	_drive_player_final_death(a)
	var before = a.player_entity.state_name
	_assert(before == "dead", "D2: 双死后玩家处于 dead（实际 %s）" % str(before))
	var ic = _get_root().get_node_or_null("InputController")
	_assert(ic != null, "D2: InputController autoload 可用")
	if ic != null:
		_assert(ic.is_processing() == false, "D2: FAIL 后 InputController 已冻结（set_process(false)）")
		ic.attack_pressed.emit()
		a.player_entity._process(0.016)
		_assert(a.player_entity.state_name == before, "D2: 冻结后输入无效果（状态未迁移）")
	_free_main(m)


func _test_d3_ai_stopped() -> void:
	# D3: FAIL 后 EnemyAI 停用 —— set_physics_process(false)
	var m = _spawn_main()
	if m == null:
		_assert(false, "D3: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	_drive_player_final_death(a)
	_assert(a.enemy.is_physics_processing() == false, "D3: FAIL 后 EnemyAI 已停用（set_physics_process(false)）")
	_free_main(m)


func _test_d4_terminal_idempotent() -> void:
	# D4: 终态幂等 —— 二次 died(true) 无二次字幕、状态不迁移
	var m = _spawn_main()
	if m == null:
		_assert(false, "D4: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.fail_subtitle_shown.connect(_on_fail_subtitle_spy)
	_drive_player_final_death(a)
	_drive_fail_subtitle(a)
	_assert(_fail_subtitle_spy == 1, "D4: 首次字幕恰一次")
	a.player_entity.died.emit(a.player_entity, true)
	_assert(_fail_subtitle_spy == 1, "D4: 二次 died(true) 无二次字幕（幂等守卫）")
	_assert(a.game_state == a.GameState.FAIL, "D4: 状态仍 FAIL（终态不再迁移）")
	_free_main(m)


func _test_d5_single_death_not_fail() -> void:
	# D5: 单死不失败 —— 第一命耗尽仅复活路径接管
	var m = _spawn_main()
	if m == null:
		_assert(false, "D5: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.player_entity.take_damage(100.0)
	_assert(a.game_state != a.GameState.FAIL, "D5: 单死 → 非 FAIL")
	_assert(a.revive.is_armed() == true, "D5: 复活路径接管（revive.is_armed() == true）")
	_free_main(m)


# ── Scenario E: 余韵 5s（AC3）──────────────────────────────────────────

func _test_e1_afterglow_timing() -> void:
	# E1: 余韵时序 —— 击杀 → AFTERGLOW + Timer 计时 → 到期回 IDLE
	var m = _spawn_main()
	if m == null:
		_assert(false, "E1: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.enemy_entity.execute_kill()
	_assert(a.game_state == a.GameState.AFTERGLOW, "E1: 击杀 → AFTERGLOW")
	_assert(a._afterglow_timer != null, "E1: 余韵 Timer 已创建")
	if a._afterglow_timer != null:
		_assert(a._afterglow_timer.time_left > 0.0, "E1: 余韵计时进行中（time_left > 0）")
		a._afterglow_timer.timeout.emit()
		_assert(a.game_state == a.GameState.IDLE, "E1: 余韵到期 → IDLE")
	_free_main(m)


func _test_e2_readonly_input_afterglow() -> void:
	# E2: 余韵期只读交互 —— 移动正常（不打断）；攻击不迁移游戏状态（自然落空无软锁）
	var m = _spawn_main()
	if m == null:
		_assert(false, "E2: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.enemy_entity.execute_kill()
	_assert(a.game_state == a.GameState.AFTERGLOW, "E2: 前置 AFTERGLOW")
	var before_x = a.player.position.x
	Input.action_press("game_move_right")
	a.player._physics_process(0.016)
	Input.action_release("game_move_right")
	_assert(a.player.position.x != before_x, "E2: 余韵期移动只读生效（玩家位移，不打断余韵）")
	var ic = _get_root().get_node_or_null("InputController")
	if ic != null:
		ic.attack_pressed.emit()
	_assert(a.game_state == a.GameState.AFTERGLOW, "E2: 余韵期攻击不迁移游戏状态")
	a.player_entity._process(0.016)
	_assert(a.player_entity.state_name != "dead", "E2: 余韵期玩家状态正常（攻击自然落空，无崩溃无软锁）")
	_free_main(m)


func _test_e3_snow_continues() -> void:
	# E3: 余韵期雪花持续 —— Atmosphere 粒子节点 emitting（无暂停路径）
	var m = _spawn_main()
	if m == null:
		_assert(false, "E3: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.enemy_entity.execute_kill()
	_assert(a.game_state == a.GameState.AFTERGLOW, "E3: 前置 AFTERGLOW")
	var snow = a.atmosphere.get_node_or_null("SnowCurtain/LayerNear/Parallax/Particles")
	_assert(snow != null, "E3: 雪幕 Particles 节点存在")
	if snow != null:
		_assert(snow.get("emitting") == true, "E3: 余韵期雪花持续 emitting")
	_free_main(m)


# ── Scenario F: 防回归 ─────────────────────────────────────────────────

func _test_f1_unbound_judge_red() -> void:
	# F1: 未 bind 判定器红例文档化（resolve → push_warning "not bound" 不崩溃）；
	#   组装态判定器必须已 bind（漏接线会红）
	var m = _spawn_main()
	if m == null:
		_assert(false, "F1: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	var raw = load("res://gdscripts/combat_judge.gd").new()
	raw.tick_frame()
	raw.resolve_attack(raw, raw)
	_assert(raw.get("player") == null, "F1: 未 bind 判定器无绑定目标（红例，resolve 不崩溃）")
	_assert(a.judge.player != null, "F1: 组装态判定器已 bind（player 非 null，漏接线即红）")
	_free_main(m)


func _test_f2_window_missed_recover() -> void:
	# F2: 窗口错过 —— 崩解后不处决 → 起身恢复（recover_from_break 50% 架势 + armed 清除）
	var m = _spawn_main()
	if m == null:
		_assert(false, "F2: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	a.enemy_entity.take_stance_damage(100.0)
	_assert(a.enemy_entity.is_stance_broken == true, "F2: 敌架势崩解")
	_assert(a.execution.get("_armed") == true, "F2: 处决窗口 armed")
	var ok = a.enemy_entity.request_transition("idle")
	_assert(ok == true, "F2: stance_break→idle 合法")
	_assert(a.enemy_entity.is_stance_broken == false, "F2: 起身清崩解标记")
	_assert(is_equal_approx(a.enemy_entity.stance, a.enemy_entity.stance_max * 0.5),
		"F2: 架势恢复 50%%（EXECUTE_RECOVER_RATIO=0.5，实际 %s）" % str(a.enemy_entity.stance))
	_assert(a.execution.get("_armed") == false, "F2: 起身后 armed 清除")
	_free_main(m)


func _test_f3_main_resources() -> void:
	# F3: Main 资源路径可达 —— Main.tscn 加载 + BattleStage/StageCamera 路径解析
	var scene = load("res://scenes/Main.tscn")
	_assert(scene != null, "F3: Main.tscn 可加载")
	var m = _spawn_main()
	if m == null:
		_assert(false, "F3: Main 实例化失败")
		return
	_assert(m.get_node_or_null("BattleStage/StageCamera") != null, "F3: BattleStage/StageCamera 路径可达")
	_free_main(m)


# ── Scenario A(#682): 精英装配与 HP 慢线（AC5）──────────────────────────────

func _test_a5_enemy_elite_assembly() -> void:
	# A1(#682): 装配消费常量——enemy_entity.life_1_max == ENEMY_HP_MAX（精英 80）、
	#   hp_1 同、EnemyAI.elite_mode == true（§3.2-2 一行参数，HP 慢线接通）
	var m = _spawn_main()
	if m == null:
		_assert(false, "A1: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	_assert(is_equal_approx(a.enemy_entity.life_1_max, WolfConstantsScript.ENEMY_HP_MAX),
		"A1: 敌装配 life_1_max == ENEMY_HP_MAX(%.1f)（实际 %.1f）" % [WolfConstantsScript.ENEMY_HP_MAX, a.enemy_entity.life_1_max])
	_assert(is_equal_approx(a.enemy_entity.hp_1, WolfConstantsScript.ENEMY_HP_MAX),
		"A1: 敌初始 hp_1 == ENEMY_HP_MAX(%.1f)（实际 %.1f）" % [WolfConstantsScript.ENEMY_HP_MAX, a.enemy_entity.hp_1])
	_assert(a.enemy.elite_mode == true, "A1: enemy.elite_mode == true（精英档位）")
	_free_main(m)


# ── Scenario F(#682): 失败路径拦截（PRD §5.3-1）────────────────────────────

func _test_f4_enemy_hp_default_intercept() -> void:
	# F1(#682): HP 装配漏改拦截——life_1_max 回落默认 100 即红（与 A1 的 == ENEMY_HP_MAX
	#   双保险：漏装配或常量改动任一回归都被装配断言拦下）
	var m = _spawn_main()
	if m == null:
		_assert(false, "F1: Main 实例化失败")
		return
	var a = _assembler(m)
	if a == null:
		_free_main(m)
		return
	_assert(absf(a.enemy_entity.life_1_max - 100.0) > 0.001,
		"F1: 敌装配 life_1_max 必须非默认 100（漏装配即红，实际 %.1f）" % a.enemy_entity.life_1_max)
	_assert(is_equal_approx(a.enemy_entity.hp_1, a.enemy_entity.life_1_max),
		"F1: hp_1 与 life_1_max 一致（实际 hp %.1f / max %.1f）" % [a.enemy_entity.hp_1, a.enemy_entity.life_1_max])
	_free_main(m)

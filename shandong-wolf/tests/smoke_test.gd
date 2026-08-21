extends SceneTree
## Smoke test for shandong-wolf — verifies project loads headless + #573 AC6 输入/移动链路.
## Usage: godot --path shandong-wolf/ --headless --script tests/smoke_test.gd
## Exit 0 = OK.
## Scenario I (AC6): I1 移动位移 ≥100px；I2 边沿信号捕获（attack/guard/dash）。
## Scenario II (AC4): 完整战斗闭环 —— 遇敌→COMBAT / 弹反→崩解 / 处决→击杀(KILL→AFTERGLOW)
##   / 余韵到期回 IDLE / 双死失败字幕（文案 ∈ FAIL_SUBTITLE_CANDIDATES）。
## NOTE: GDScript lambdas capture by value, so signal capture uses instance methods.

var _attack_cap: int = 0
var _guard_cap: int = 0
var _dash_cap: int = 0
var _failed: bool = false

## Scenario II (AC4) 信号间谍（成员变量 + 成员函数接收，禁 lambda 捕获——GDScript 按值捕获）
var _assembly_state_pairs: Array = []     # [[from, to], ...] game_state_changed 迁移序列
var _assembly_enemy_died_spy: Array = []  # [final, ...] 敌人 died 记录（处决击杀断言）


func _init() -> void:
	call_deferred("_run")


func _on_attack() -> void:
	_attack_cap += 1


func _on_guard(_timestamp_ms: int) -> void:
	_guard_cap += 1


func _on_dash() -> void:
	_dash_cap += 1


func _on_assembly_state_changed(from: String, to: String) -> void:
	_assembly_state_pairs.append([from, to])


func _on_assembly_enemy_died(_entity, final: bool) -> void:
	_assembly_enemy_died_spy.append(final)


func _run() -> void:
	# InputController 是 lazy autoload（project.godot 中 "*res://gdscripts/input_controller.gd"）：
	# --script 主脚本编译早于 autoload 注册，标识符 "InputController" 不可解析（CI smoke 失败根因），
	# 且 Engine.get_singleton() 对 lazy autoload 返回 null —— 必须用 root.get_node_or_null() 运行时获取。
	# I1: 位移（AC6）——120 physics frames = 2s @ 60fps
	# 用 load() 而非 preload()：preload 在脚本编译期解析，会再次触发 autoload 标识符编译错误。
	var PlayerControllerScript = load("res://gdscripts/player_controller.gd")
	var p = PlayerControllerScript.new()
	root.add_child(p)
	Input.action_press("game_move_right")
	for i in range(120):
		await physics_frame
	if p.position.x < 100.0:
		print("SMOKE FAIL: I1 displacement %.1f px < 100 px after 2s move_right (AC6)" % p.position.x)
		_failed = true
	Input.action_release("game_move_right")

	# I2: 边沿信号捕获——用真实 InputController autoload（不新建实例、不释放）。
	# 确定性驱动: 手动 _process(0.016)（与 test_input_controller.gd 同款），
	# 规避 headless 下 physics/idle 帧序竞态（await physics_frame 曾随机漏采边沿）。
	var ic = root.get_node_or_null("InputController")
	if ic == null:
		print("SMOKE FAIL: InputController autoload not available")
		_failed = true
	else:
		ic.attack_pressed.connect(_on_attack)
		ic.guard_pressed.connect(_on_guard)
		ic.dash_pressed.connect(_on_dash)

		Input.action_press("game_light_attack")
		ic._process(0.016)
		Input.action_release("game_light_attack")
		ic._process(0.016)
		if _attack_cap == 0:
			print("SMOKE FAIL: I2 attack_pressed not captured")
			_failed = true

		Input.action_press("game_guard")
		ic._process(0.016)
		Input.action_release("game_guard")
		ic._process(0.016)
		if _guard_cap == 0:
			print("SMOKE FAIL: I2 guard_pressed not captured")
			_failed = true

		Input.action_press("game_dash")
		ic._process(0.016)
		Input.action_release("game_dash")
		ic._process(0.016)
		if _dash_cap == 0:
			print("SMOKE FAIL: I2 dash_pressed not captured (light press = step)")
			_failed = true

		ic.attack_pressed.disconnect(_on_attack)
		ic.guard_pressed.disconnect(_on_guard)
		ic.dash_pressed.disconnect(_on_dash)

	root.remove_child(p)
	p.queue_free()

	# ── Scenario II (AC4) 完整战斗闭环（#585）──────────────────────────────
	# Scenario I 原退出逻辑（print SMOKE OK + quit）移到本块之后统一收口，
	# 最终 exit code 由合并后的 _failed（Scenario I + II）决定。
	_scenario_two_ac4()

	if _failed:
		print("SMOKE FAIL: shandong-wolf #573 AC6 input/movement + #585 AC4 combat loop")
	else:
		print("SMOKE OK: shandong-wolf skeleton loads + #573 input/movement AC6 + #585 AC4 combat loop")
	quit(1 if _failed else 0)


func _scenario_two_ac4() -> void:
	## Scenario II (AC4): 程序化挂载 Main.tscn → MainBattle._ready 全链路装配，
	##   手动驱动完整战斗闭环（遇敌→COMBAT / 弹反→崩解 / 处决→击杀 / 余韵到期回 IDLE）
	##   + 双死失败字幕子场景（文案 ∈ FAIL_SUBTITLE_CANDIDATES）。
	##   headless 确定性（全同步零 await）: 组件接口直接驱动 + timer.timeout.emit() +
	##   tween custom_step 推进（照 test_main_assembly.gd 驱动手法）。
	var C = load("res://gdscripts/constants.gd")
	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		print("SMOKE FAIL: S2 Main.tscn load failed")
		_failed = true
		return
	var m = scene.instantiate()
	root.add_child(m)
	var a = m.get_node_or_null("MainBattle")
	if a == null:
		print("SMOKE FAIL: S2 MainBattle missing")
		_failed = true
		_free_main_instance(m)
		return

	_assembly_state_pairs = []
	_assembly_enemy_died_spy = []
	a.game_state_changed.connect(_on_assembly_state_changed)

	# S2-1 遇敌 → COMBAT（敌人进 attack 态，首次接战 IDLE→COMBAT）
	a.enemy_entity.facing = -1
	a.enemy_entity.request_transition("attack")
	if a.game_state != a.GameState.COMBAT:
		print("SMOKE FAIL: S2-1 enemy attack did not reach COMBAT (state %d)" % a.game_state)
		_failed = true
	if not _assembly_sequence_has(_assembly_state_pairs, ["IDLE", "COMBAT"]):
		print("SMOKE FAIL: S2-1 IDLE->COMBAT not observed: %s" % str(_assembly_state_pairs))
		_failed = true

	# S2-2 弹反→崩解: 敌架势打空 → stance_broken → 处决窗口 armed
	a.enemy_entity.take_stance_damage(100.0)
	if a.enemy_entity.is_stance_broken != true:
		print("SMOKE FAIL: S2-2 enemy stance not broken")
		_failed = true
	if a.execution.get("_armed") != true:
		print("SMOKE FAIL: S2-2 stance break did not arm execution window")
		_failed = true

	# S2-3 处决→击杀: armed 窗口内 attack_pressed（经 execution.bind_input）→ execute_kill → died(true)
	var ic = root.get_node_or_null("InputController")
	if ic == null:
		print("SMOKE FAIL: S2-3 InputController autoload not available")
		_failed = true
	else:
		a.enemy_entity.died.connect(_on_assembly_enemy_died)
		ic.attack_pressed.emit()
		if _assembly_enemy_died_spy.size() != 1 or _assembly_enemy_died_spy[0] != true:
			print("SMOKE FAIL: S2-3 execute kill did not emit enemy died(true): %s" % str(_assembly_enemy_died_spy))
			_failed = true

	# S2-4 余韵 5s: 到期前（time_left > 0）状态保持 AFTERGLOW；timeout.emit() → 回 IDLE
	if a.game_state != a.GameState.AFTERGLOW:
		print("SMOKE FAIL: S2-3 kill did not reach AFTERGLOW (state %d)" % a.game_state)
		_failed = true
	if a._afterglow_timer == null:
		print("SMOKE FAIL: S2-4 afterglow timer missing")
		_failed = true
	elif a._afterglow_timer.time_left > 0.0:
		if a.game_state != a.GameState.AFTERGLOW:
			print("SMOKE FAIL: S2-4 afterglow state changed before 5s elapsed")
			_failed = true
		a._afterglow_timer.timeout.emit()
		if a.game_state != a.GameState.VICTORY:
			print("SMOKE FAIL: S2-4 afterglow timeout did not reach VICTORY (state %d)" % a.game_state)
			_failed = true
	else:
		print("SMOKE FAIL: S2-4 afterglow timer already expired before assertion")
		_failed = true

	# S2-5 状态序列: game_state_changed 观测到 IDLE→COMBAT→KILL→AFTERGLOW
	if not _assembly_sequence_has(_assembly_state_pairs, ["IDLE", "COMBAT", "KILL", "AFTERGLOW"]):
		print("SMOKE FAIL: S2-5 sequence missing IDLE->COMBAT->KILL->AFTERGLOW: %s" % str(_assembly_state_pairs))
		_failed = true

	_free_main_instance(m)

	# S2-6 失败路径子场景: 双死 → FAIL → 字幕淡入 → 文案 ∈ FAIL_SUBTITLE_CANDIDATES
	var m2 = scene.instantiate()
	root.add_child(m2)
	var a2 = m2.get_node_or_null("MainBattle")
	if a2 == null:
		print("SMOKE FAIL: S2-6 MainBattle missing in fail scenario")
		_failed = true
	else:
		a2.player_entity.take_damage(100.0)
		a2.player_entity.revive()
		a2.player_entity.set("_invincible_until_sec", 0.0)
		a2.player_entity._process(1.1)
		a2.player_entity.take_damage(100.0)
		if a2.game_state != a2.GameState.FAIL:
			print("SMOKE FAIL: S2-6 double death did not reach FAIL (state %d)" % a2.game_state)
			_failed = true
		if a2._fail_subtitle_timer != null:
			a2._fail_subtitle_timer.timeout.emit()
		var tweens: Array = get_processed_tweens()
		for t in tweens:
			var tw: Tween = t as Tween
			if tw != null and tw.is_valid():
				tw.custom_step(2.0)
		if a2.fail_label == null:
			print("SMOKE FAIL: S2-6 fail label missing")
			_failed = true
		elif a2.fail_label.visible != true:
			print("SMOKE FAIL: S2-6 fail subtitle not visible")
			_failed = true
		elif not C.FAIL_SUBTITLE_CANDIDATES.has(a2.fail_label.text):
			print("SMOKE FAIL: S2-6 fail subtitle text not in candidates: %s" % a2.fail_label.text)
			_failed = true
	_free_main_instance(m2)


func _assembly_sequence_has(pairs: Array, names: Array) -> bool:
	## 断言 (from,to) 对按序包含 names 状态序列（如 [IDLE,COMBAT,KILL,AFTERGLOW]）
	if names.size() < 2:
		return false
	var idx: int = 0
	for pair in pairs:
		if pair.size() >= 2 and str(pair[0]) == str(names[idx]) and str(pair[1]) == str(names[idx + 1]):
			idx += 1
			if idx >= names.size() - 1:
				return true
	return false


func _free_main_instance(m: Node) -> void:
	## 立即释放 Main 实例（先 remove_child 再 free）——hud._ready 会经 group "hud"
	## queue_free 重复实例，残留会污染后续场景，故必须立即释放（照 test_main_assembly._free_main）。
	if m == null:
		return
	if m.get_parent() != null:
		m.get_parent().remove_child(m)
	if is_instance_valid(m):
		m.free()

extends Node
class_name ExecutionOrchestrator
## ExecutionOrchestrator — 处决触发编排器（#580 处决系统）。
## 归属: docs/DESIGN/580-execution-system.md §2.1
## 职责: 处决触发编排（bind 模式 + armed 窗口 + 时序序列 + headless _process 驱动）。
##   跨组件时序（stance_broken → armed 窗口 → attack_pressed → 距离校验 → execute 转移
##   → execute_kill → 反馈 → 淡出）收敛到本编排器一个组件，与场景解耦（bind 幂等接线）。
## 红线: 零直写 Engine.time_scale（慢动作只经 trigger_feedback → TimeScaleStack，#579 交付）;
##   take_damage execute no-op 是 #575 无敌红线——处决杀敌必须走 execute_kill()，禁止绕道。
## 架构先例: #578 ReviveOrchestrator（bind/unbind 幂等接线 + headless _process(delta) 手动推进）。

const C = preload("res://gdscripts/constants.gd")
const DebugCanvasScript = preload("res://gdscripts/debug_canvas.gd")

var _player: Object = null          # bind_player 注入（处决无敌目标，state 触发时实时查）
var _enemy: Object = null           # bind_enemy 注入（崩解/处决/起身目标）
var _judge: Object = null           # bind_judge 注入（stance_broken 统一出口，可选）
var _input: Object = null           # bind_input 注入（attack_pressed = 处决键）
var _feedback: Object = null        # bind_feedback 注入（trigger_feedback("execute")）
var _armed: bool = false            # 处决窗口开启（stance_broken 置位，触发/起身/解绑清除）
var _arm_elapsed: float = 0.0       # 窗口计时（_process(delta) 累加，headless 手动推进）
var fade: Object = null             # ExecutionFade 实例（_init 创建，测试可注入/断言）


func _init() -> void:
	var fade_script: Resource = load("res://gdscripts/execution_fade.gd")
	if fade_script != null:
		fade = fade_script.new()


func bind_player(p: Object) -> void:
	## 幂等接线: 只存引用，不订阅——玩家 state（dead 守卫）与位置（距离校验）在触发时实时读取。
	_player = p


func bind_enemy(e: Object) -> void:
	## 幂等接线: 先断开旧实体全部订阅（防信号泄漏，PRD §5.3-2），再绑新实体。
	## 订阅 e.state_changed（armed 失效观察）+ e.died（unbind 清理）；
	## 若 _judge == null → 直连 e.stance_broken（降级源，headless 测试免判定器，D3）。
	if _enemy != null and is_instance_valid(_enemy):
		if _enemy.has_signal("state_changed") and _enemy.state_changed.is_connected(_on_enemy_state_changed):
			_enemy.state_changed.disconnect(_on_enemy_state_changed)
		if _enemy.has_signal("died") and _enemy.died.is_connected(_on_enemy_died):
			_enemy.died.disconnect(_on_enemy_died)
		if _judge == null and _enemy.has_signal("stance_broken") and _enemy.stance_broken.is_connected(_on_stance_broken):
			_enemy.stance_broken.disconnect(_on_stance_broken)
	_enemy = e
	_armed = false
	_arm_elapsed = 0.0
	if e == null:
		return
	e.state_changed.connect(_on_enemy_state_changed)
	e.died.connect(_on_enemy_died)
	if _judge == null and e.has_signal("stance_broken"):
		e.stance_broken.connect(_on_stance_broken)


func bind_judge(j: Object) -> void:
	## 统一事件出口优先（#585 组装路径）: 断开敌方直连 → 改连 j.stance_broken（D3 单源互斥切换）。
	if _judge != null and is_instance_valid(_judge) and _judge.has_signal("stance_broken") and _judge.stance_broken.is_connected(_on_stance_broken):
		_judge.stance_broken.disconnect(_on_stance_broken)
	if _enemy != null and is_instance_valid(_enemy) and _enemy.has_signal("stance_broken") and _enemy.stance_broken.is_connected(_on_stance_broken):
		_enemy.stance_broken.disconnect(_on_stance_broken)
	_judge = j
	if j != null and j.has_signal("stance_broken"):
		j.stance_broken.connect(_on_stance_broken)


func bind_input(ic: Object) -> void:
	## 订阅 ic.attack_pressed（攻击键 = 处决键，#573 意图信号契约）。
	if _input != null and is_instance_valid(_input) and _input.has_signal("attack_pressed") and _input.attack_pressed.is_connected(_on_attack_pressed):
		_input.attack_pressed.disconnect(_on_attack_pressed)
	_input = ic
	if ic != null and ic.has_signal("attack_pressed"):
		ic.attack_pressed.connect(_on_attack_pressed)


func bind_feedback(rc: Object) -> void:
	## 反馈注入（D6）: 只存引用，不订阅——触发时直接调 trigger_feedback("execute")，未绑定静默跳过。
	_feedback = rc


func unbind_enemy() -> void:
	## 场景切换/实体销毁前调用: 断开全部订阅 + 清引用 + 清 armed（防信号泄漏，PRD §5.3-2）。
	if _enemy != null and is_instance_valid(_enemy):
		if _enemy.has_signal("state_changed") and _enemy.state_changed.is_connected(_on_enemy_state_changed):
			_enemy.state_changed.disconnect(_on_enemy_state_changed)
		if _enemy.has_signal("died") and _enemy.died.is_connected(_on_enemy_died):
			_enemy.died.disconnect(_on_enemy_died)
		if _enemy.has_signal("stance_broken") and _enemy.stance_broken.is_connected(_on_stance_broken):
			_enemy.stance_broken.disconnect(_on_stance_broken)
	_enemy = null
	_armed = false
	_arm_elapsed = 0.0


func _read(param_name: String, default_value: Variant) -> Variant:
	## 参数读值: DebugCanvas 热更新优先，release 回落 constants（#584 约定）。
	return DebugCanvasScript.get_value(param_name, default_value)


func _range_px() -> float:
	## D1 距离阈值（px 派生值）: 闭区间 ≤ 触发，与 #577 弹反窗口闭区间语义一致。
	return float(_read("EXECUTE_RANGE_PX", C.EXECUTE_RANGE_PX))


func _on_stance_broken(entity: Object) -> void:
	## 窗口开启（幂等: 重复事件仅重置计时，事件本身单发）。
	if entity != _enemy:
		return
	_armed = true
	_arm_elapsed = 0.0


func _on_enemy_state_changed(from: String, to: String) -> void:
	## armed 失效观察: 状态机 3.0s 自动退 idle → 立即恢复（幂等双保险，PRD §5.2-1）；
	##   进入 execute → 防御性双清（正常路径已由 _trigger_execution 清除）。
	if from == "stance_break" and to == "idle":
		if _armed:
			_armed = false
			if is_instance_valid(_enemy):
				_enemy.recover_from_break()
	elif to == "execute":
		_armed = false
		_arm_elapsed = 0.0


func _on_enemy_died(_ent: Object, _final: bool) -> void:
	## 敌人死亡 → 自动解绑（execute_kill 的 died emit 同步回调，防 queue_free 后访问已释放对象）。
	unbind_enemy()


func _on_attack_pressed() -> void:
	## 处决检查（D4 同键多义）: armed ∧ 玩家存活 ∧ 距离内（闭区间 ≤）→ 触发；否则正常 attack 流程继续。
	if not _armed:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if _player.state_name == "dead":
		return                        # 防「尸体处决」演出（PRD §5.2-3）
	if _enemy == null or not is_instance_valid(_enemy):
		return
	if absf(_player.position.x - _enemy.position.x) > _range_px():
		return                        # 距离外 → 正常 attack
	_trigger_execution()


func _trigger_execution() -> void:
	## 时序序列（PRD §1.5 逐字落实，顺序关键: 先转移后杀敌）。
	## CRITICAL: 必须先捕获 target = _enemy——execute_kill() 的 died emit → _on_enemy_died → unbind_enemy()
	##   会同步置空 _enemy（设计风险①），后续反馈/淡出必须用捕获的 target。
	var target = _enemy
	_armed = false
	_arm_elapsed = 0.0
	if is_instance_valid(_player):
		_player.set_invincible(float(_read("EXECUTE_INVINCIBLE_SECONDS", C.EXECUTE_INVINCIBLE_SECONDS)))
	if is_instance_valid(target):
		if target.state_name != "execute":
			target.request_transition("execute")      # 5 帧 anim_execute（#574 消费；幂等: 已 execute 则跳过）
		target.execute_kill()                          # AC1 杀敌（绕过 take_damage execute no-op 红线）
		if _feedback != null:
			_feedback.trigger_feedback("execute", {"target_entity": target})   # AC4 S 级（#654）
		if fade != null:
			fade.bind(target)                          # AC2 淡出（modulate 1→0 → queue_free）


func _process(delta: float) -> void:
	## 窗口到期驱动（headless 手动推进）: ≥ STANCE_BREAK_RECOVERY_SEC → 起身恢复（幂等，AC3）。
	## 与状态机 3.0s 自动退 idle 同源互引，recover_from_break 幂等防双写。
	if not _armed:
		return
	_arm_elapsed += delta
	if _arm_elapsed >= float(C.STANCE_BREAK_RECOVERY_SEC):
		_armed = false
		_arm_elapsed = 0.0
		if is_instance_valid(_enemy):
			_enemy.recover_from_break()

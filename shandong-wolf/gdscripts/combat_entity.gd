extends Node2D
class_name CombatEntity
## CombatEntity — 战斗实体基类 + 11 态战斗状态机（#575）。
## 归属: docs/DESIGN/575-combat-entity-state-machine.md §2.4-§2.5
## 职责: 战斗数据容器（两段血 hp_1/hp_2 + 架势 stance + facing）+ FSM 持有 +
##   唯一转移入口 request_transition + 受击/架势/生死接口 + 信号广播 + 输入桥。
## 变体: 单类 + @export 参数——玩家 new(is_player=true, life_total=2)；敌人 new(is_player=false, life_total=1)。
## 状态名权威集: combat_state_table.gd CANONICAL_STATES（与 #574 consume_state 逐字对齐）。
## 信号契约: #576 HUD（hp_changed/stance_changed）/ #574 动画（state_changed）/
##   #577/#580（stance_broken）/ #578（died/revived）。
## 下游: #576/#577/#578/#580/#581/#585 全部消费本层接口，本层不做判定/演出。

const StateMachineBaseScript = preload("res://gdscripts/state_machine.gd")
const C = preload("res://gdscripts/constants.gd")
const CombatStateTableScript = preload("res://gdscripts/combat_state_table.gd")
const CombatStatesScript = preload("res://gdscripts/combat_states.gd")

## 变体参数（issue body「差异通过参数配置」）
@export var is_player: bool = false
@export var life_total: int = 2        # 玩家 2 / 小兵 1
@export var life_1_max: float = 100.0  # 默认 WolfConstants.LIFE_1_MAX
@export var life_2_abs: float = 50.0   # 默认 WolfConstants.LIFE_2_ABS
@export var stance_max: float = 100.0  # 默认 WolfConstants.POSTURE_BREAK_THRESHOLD

## 运行期数据
var hp_1: float
var hp_2: float                        # life_total=1 时不参与
var stance: float
var facing: int = 1                    # 1 右 / -1 左（AC1 可读写）
var is_stance_broken: bool = false
var state_name: String = "idle"        # canonical 状态名（#574 consume_state 消费）
var _active_life: int = 1              # 两段血标记: 1 = hp_1 受击条，2 = hp_2 受击条
var _is_final_dead: bool = false       # 终态（final=true 后禁止 revive）
var _invincible_until_sec: float = 0.0 # 复活无敌期截止（Time.get_ticks_msec()/1000.0 比较）
var fsm: Object                        # StateMachineBase 实例
var _state_objs: Dictionary = {}       # canonical 状态名 → 状态对象（_init 预建）
var _ic: Object = null                 # InputController 引用（输入桥，is_player 启用）

## 信号（#576 HUD / #574 动画 / #577/#578/#580 下游契约）
signal hp_changed(hp_1: float, hp_2: float, active_life: int)
signal stance_changed(stance: float, stance_max: float)
signal stance_broken(entity: CombatEntity)
signal state_changed(from: String, to: String)
signal died(entity: CombatEntity, final: bool)
signal revived(entity: CombatEntity)

func _init(config: Dictionary = {}) -> void:
	## 先应用变体参数（测试经 new(params) 传入），再从 constants 初始化战斗数据
	for key in config:
		set(key, config[key])
	hp_1 = life_1_max
	hp_2 = life_2_abs
	stance = stance_max
	fsm = StateMachineBaseScript.new()
	_state_objs = {}
	for name in CombatStateTableScript.CANONICAL_STATES:
		_state_objs[name] = CombatStatesScript.make_state(name, self)

func _ready() -> void:
	## 玩家变体自动接输入桥（headless 无 autoload 时静默跳过；测试可手动 bind_input_controller）
	if is_player:
		var ic = get_node_or_null("/root/InputController")
		if ic != null:
			bind_input_controller(ic)

func _process(delta: float) -> void:
	## 状态机推进 + 无敌期到期自动失效 + 输入桥轮询（_ic 启用时）
	fsm.update(delta)
	if _invincible_until_sec > 0.0 and Time.get_ticks_msec() / 1000.0 >= _invincible_until_sec:
		_invincible_until_sec = 0.0
	if _ic != null:
		_bridge_poll()

func request_transition(to: String) -> bool:
	## 唯一转移入口（表 = 拓扑合法性 + 守卫 = 条件合法性，两层设计）。
	## 守卫序: ① 终态拒（_is_final_dead）② dead 停摆拒（仅 revive 可出）
	##          ③ 同态重入（restart 钩子，静默返回 true，不广播 state_changed）
	##          ④ 查表非法拒（状态不漂移 + push_warning）
	##          ⑤ 合法执行: fsm.transition_to + state_name 更新 + state_changed 广播
	if _is_final_dead:
		push_warning("CombatEntity: final dead — transition rejected: %s" % to)
		return false
	if state_name == "dead" and to != "revive":
		push_warning("CombatEntity: dead lockdown — transition rejected: %s" % to)
		return false
	if to == state_name:
		if fsm.current_state != null and fsm.current_state.has_method("restart"):
			fsm.current_state.restart()
		return true
	if not CombatStateTableScript.is_legal(state_name, to):
		push_warning("CombatEntity: illegal transition %s -> %s" % [state_name, to])
		return false
	fsm.transition_to(_state_objs[to])
	var from: String = state_name
	state_name = to
	emit_signal("state_changed", from, to)
	return true

func take_damage(amount: float, source: Object = null) -> void:
	## 防御性兜底: dead/revive/execute 状态 no-op（§5.2-1）；无敌期内 no-op。
	##   负/NaN/Inf 伤害视为 0 + push_warning；扣当前受击条 → hp_changed；
	##   hp ≤ 0 → die()；否则非 guard/stagger/stance_break/parry_success/revive 状态进入 stagger。
	if state_name == "dead" or state_name == "revive" or state_name == "execute":
		return
	if _invincible_until_sec > Time.get_ticks_msec() / 1000.0:
		return
	if not is_finite(amount) or amount < 0.0:
		push_warning("CombatEntity: invalid damage %s treated as 0" % [amount])
		amount = 0.0
	if _active_life == 1:
		hp_1 = clampf(hp_1 - amount, 0.0, life_1_max)
	else:
		hp_2 = clampf(hp_2 - amount, 0.0, life_2_abs)
	emit_signal("hp_changed", hp_1, hp_2, _active_life)
	if (_active_life == 1 and hp_1 <= 0.0) or (_active_life == 2 and hp_2 <= 0.0):
		die()
		return
	if state_name in ["idle", "move", "attack", "heavy_attack"]:
		request_transition("stagger")

func take_stance_damage(amount: float) -> void:
	## 兜底: dead/revive 状态 no-op；无敌期内 no-op；负/NaN/Inf 视为 0 + push_warning；
	##   stance 扣减 → stance_changed；stance ≤ 0 → break_stance()
	if state_name == "dead" or state_name == "revive":
		return
	if _invincible_until_sec > Time.get_ticks_msec() / 1000.0:
		return
	if not is_finite(amount) or amount < 0.0:
		push_warning("CombatEntity: invalid stance damage %s treated as 0" % [amount])
		amount = 0.0
	stance = clampf(stance - amount, 0.0, stance_max)
	emit_signal("stance_changed", stance, stance_max)
	if stance <= 0.0:
		break_stance()

func break_stance() -> void:
	## 幂等: 已崩解则不再二次广播/二次转移（单次触发，§5 边界 3）
	if is_stance_broken:
		return
	is_stance_broken = true
	stance = 0.0
	emit_signal("stance_broken", self)
	request_transition("stance_break")

func die() -> void:
	## 两段血死亡: active_life=1 且 life_total=2 → 可复活死（died final=false，#578 接管）；
	##   否则 → 终态（died final=true，含 life_total=1 变体，§5 边界 10）
	if _active_life == 1 and life_total == 2:
		emit_signal("died", self, false)
		request_transition("dead")
	else:
		_is_final_dead = true
		emit_signal("died", self, true)
		request_transition("dead")

func revive() -> void:
	## 复活（#578 驱动）: 终态或 life_total<2 不可复活（no-op + push_warning，失败路径 3）；
	##   否则 hp_2 独立计数接管、架势清空、无敌开启、dead→revive 转移 + revived 广播
	if _is_final_dead or life_total < 2:
		push_warning("CombatEntity: revive rejected (final dead or life_total < 2)")
		return
	_active_life = 2
	hp_2 = life_2_abs
	stance = 0.0
	is_stance_broken = false
	_invincible_until_sec = Time.get_ticks_msec() / 1000.0 + float(C.INVINCIBLE_SECONDS)
	request_transition("revive")
	emit_signal("revived", self)
	emit_signal("hp_changed", hp_1, hp_2, _active_life)
	emit_signal("stance_changed", stance, stance_max)

func _recalc_stance_max() -> float:
	## 钩子: MVP 固定 stance_max；未来只狼铁律派生规则（架势上限 = 当前 HP 上限）改此处，信号契约不动
	return stance_max

func bind_input_controller(ic: Object) -> void:
	## 手动接线（#585 组装或测试）: 保存引用 + 订阅意图信号（输入桥启用，is_player 实体）
	_ic = ic
	if ic == null:
		return
	if ic.has_signal("attack_pressed"):
		ic.attack_pressed.connect(_on_bridge_attack_pressed)
	if ic.has_signal("heavy_attack_pressed"):
		ic.heavy_attack_pressed.connect(_on_bridge_heavy_attack_pressed)
	if ic.has_signal("guard_pressed"):
		ic.guard_pressed.connect(_on_bridge_guard_pressed)
	if ic.has_signal("revive_pressed"):
		ic.revive_pressed.connect(_on_bridge_revive_pressed)

func _on_bridge_attack_pressed() -> void:
	request_transition("attack")

func _on_bridge_heavy_attack_pressed() -> void:
	request_transition("heavy_attack")

func _on_bridge_guard_pressed(_timestamp_ms: int) -> void:
	## guard_pressed 时间戳本层不消费（弹反判定归 #577）
	request_transition("guard")

func _on_bridge_revive_pressed() -> void:
	## #578 F 键驱动路径（自动路径由 #578 监听 died(final=false) 计时后调 revive()，两路兼容）
	revive()

func _bridge_poll() -> void:
	## _process 轮询（仅 _ic != null 时）: move 轴 → move/idle 转移 + facing 同步；guard 释放 → idle
	##   垫步/跳不映射（留在移动层，canonical 集无对应状态）
	var axis: float = _ic.get_move_axis()
	if axis != 0.0 and (state_name == "idle" or state_name == "move"):
		facing = 1 if axis > 0.0 else -1
		if state_name == "idle":
			request_transition("move")
	elif axis == 0.0 and state_name == "move":
		request_transition("idle")
	if state_name == "guard" and not Input.is_action_pressed("game_guard"):
		request_transition("idle")

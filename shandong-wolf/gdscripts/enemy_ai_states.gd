extends RefCounted
## EnemyAIStates — 敌人行为状态对象集（#581）。
## 范式: 与 combat_states.gd 同构（make_state 工厂 + enter/exit/update 三接口 + RefCounted 基类）。
## 行为态命名空间: patrol / chase / attack / retreat —— 与 11 态战斗状态机完全分离
##   （#575 CANONICAL_STATES 权威集红线，AI 行为态绝不进战斗状态表）。
## 职责边界: 状态对象只写 ai._move_intent 与调 ai.entity.request_transition()，
##   绝不直接改 entity.state_name（#575 唯一转移入口红线）。

const C = preload("res://gdscripts/constants.gd")
const SelfScript = preload("res://gdscripts/enemy_ai_states.gd")

## 工厂: AI 行为态名 → 状态对象（未知 → PatrolState 兜底）
static func make_state(state_name: String, ai: Object) -> Object:
	match state_name:
		"patrol":
			return PatrolState.new(ai)
		"chase":
			return ChaseState.new(ai)
		"attack":
			return AttackState.new(ai)
		"retreat":
			return RetreatState.new(ai)
		"guard":
			return GuardState.new(ai)
		_:
			return PatrolState.new(ai)


class AIStateBase:
	extends RefCounted
	## 行为状态基类: 持有 EnemyAI 引用 + 计时（enter 重置）
	var ai: Object = null
	var _elapsed: float = 0.0
	var state_name: String = "base"          # 行为态名（测试断言读取；get_class 在 --script 下不可靠）

	func _init(a: Object) -> void:
		ai = a

	func enter() -> void:
		_elapsed = 0.0

	func exit() -> void:
		pass

	func update(_delta: float) -> void:
		pass


class PatrolState:
	extends AIStateBase
	## 巡逻: waypoint ping-pong + 到达停顿 ENEMY_PATROL_PAUSE_SEC。
	##   - waypoints 空数组 → 原地等待（不报错，失败路径 2）
	##   - 单 waypoint → ping-pong 降级原地等待（不报错，边界 8）
	##   - 多 waypoint: 朝 waypoints[_target_idx] 移动（move_toward 步进），
	##     到达 |dx| < 4px → 停顿后翻转 _dir 前进下一目标
	##   - 感知触发（ai.can_sense_player()）→ 行为 FSM 转移 ChaseState
	var _target_idx: int = 0
	var _dir: int = 1
	var _pause_left: float = 0.0

	func enter() -> void:
		ai._behavior = "patrol"
		state_name = "patrol"
		_elapsed = 0.0
		_target_idx = 0
		_dir = 1
		_pause_left = 0.0

	func update(delta: float) -> void:
		if ai.can_sense_player():
			ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
			return
		var wps: Array = ai.waypoints
		if wps.size() < 2:
			ai._move_intent = Vector2.ZERO
			return
		if _pause_left > 0.0:
			_pause_left -= delta
			ai._move_intent = Vector2.ZERO
			if _pause_left <= 0.0:
				_advance()
			return
		var target: Vector2 = wps[_target_idx]
		var dx: float = target.x - ai.position.x
		if absf(dx) < 4.0:
			_pause_left = float(C.ENEMY_PATROL_PAUSE_SEC)
			ai._move_intent = Vector2.ZERO
			return
		ai._move_intent.x = (1.0 if dx > 0.0 else -1.0) * float(C.ENEMY_PATROL_SPEED)

	func _advance() -> void:
		var wps: Array = ai.waypoints
		_target_idx += _dir
		if _target_idx >= wps.size():
			_target_idx = wps.size() - 2
			_dir = -1
		elif _target_idx < 0:
			_target_idx = 1
			_dir = 1


class ChaseState:
	extends AIStateBase
	## 追击: 转向（ENEMY_TURN_DELAY_SEC 延迟防瞬移）+ 逼近 + 停距。
	##   - 丢失（|dx| > ENEMY_LOSE_SIGHT_RANGE）→ 回 PatrolState（位置不瞬移）
	##   - 停距（|dx| <= ENEMY_ATTACK_RANGE）+ 冷却就绪 → AttackState
	func enter() -> void:
		ai._behavior = "chase"
		state_name = "chase"
		_elapsed = 0.0
		ai._turn_timer = 0.0

	func update(delta: float) -> void:
		if ai.player == null:
			ai._move_intent = Vector2.ZERO
			return
		var dx: float = ai.player.position.x - ai.position.x
		if absf(dx) > float(C.ENEMY_LOSE_SIGHT_RANGE):
			ai._move_intent = Vector2.ZERO
			ai._ai_fsm.transition_to(SelfScript.make_state("patrol", ai))
			return
		var target_dir: int = 1 if dx > 0.0 else -1
		if dx == 0.0:
			target_dir = ai.facing
		if ai.facing != target_dir:
			ai._turn_timer += delta
			if ai._turn_timer >= float(C.ENEMY_TURN_DELAY_SEC):
				ai.facing = target_dir
				if ai.entity != null:
					ai.entity.facing = ai.facing
				ai._turn_timer = 0.0
		else:
			ai._turn_timer = 0.0
		if absf(dx) > float(C.ENEMY_ATTACK_RANGE):
			ai._move_intent.x = float(target_dir) * float(C.ENEMY_CHASE_SPEED)
		else:
			ai._move_intent.x = 0.0
		var now: float = Time.get_ticks_msec() / 1000.0
		if absf(dx) <= float(C.ENEMY_ATTACK_RANGE) and now >= ai._attack_cooldown_until_sec:
			ai._ai_fsm.transition_to(SelfScript.make_state("attack", ai))


class AttackState:
	extends AIStateBase
	## 攻击: 蓄力重斩（elite_mode 门控）/ 突刺（heavy_attack 单发）/ 三连砍（attack ×3）三选一 + 冷却。
	##   - 出招决策（概率和 = 1）: charge（elite 时 ENEMY_CHARGE_CHANCE）→ thrust（ENEMY_THRUST_CHANCE）
	##     → combo（余量）；elite_mode=false 时首层门控短路，行为与 #581 二选一逐字节一致
	##   - 蓄力（#682）: 复用 heavy_attack 战斗态 + 瞬时 override 注入（windup=ENEMY_CHARGE_WINDUP /
	##     hp_damage=ENEMY_CHARGE_HP_DAMAGE）→ request_transition 同步触发 judge 登记读取 → 出招后清空
	##   - 连段中断（边界 7）: 实体进入非 idle/move/attack/heavy_attack 态（stagger/崩解等）
	##     或弹反抑制窗内 → 连段计划作废回 Chase（决策门控兜底，这里同步清理）
	var _is_thrust: bool = false
	var _attack_kind: String = "combo"       # "charge" / "thrust" / "combo"
	var _issued: bool = false
	var _strikes: int = 0

	func enter() -> void:
		ai._behavior = "attack"
		state_name = "attack"
		_elapsed = 0.0
		## #720 血线阶段强化（P2 可选）: _enraged → charge 概率 ×1.5（冷却缩短在 update 中按 _enraged 调整）
		var charge_chance: float = float(C.ENEMY_CHARGE_CHANCE) * (1.5 if ai._enraged else 1.0)
		if ai.elite_mode and ai._rng.randf() < charge_chance:
			_attack_kind = "charge"
		elif ai._rng.randf() < float(C.ENEMY_THRUST_CHANCE):
			_attack_kind = "thrust"
		else:
			_attack_kind = "combo"
		_is_thrust = (_attack_kind == "thrust")
		_issued = false
		_strikes = 0
		## #720 差异化前摇（三级可读梯度）: thrust 注入中前摇 override（judge 登记时读取）。
		##   charge/combo 走既有 override/fallback 链（charge 在 update 注入、combo fallback ENEMY_ATTACK_WINDUP）
		if _attack_kind == "thrust":
			ai.entity.current_windup_frames = int(C.ENEMY_THRUST_WINDUP)

	func update(_delta: float) -> void:
		var now: float = Time.get_ticks_msec() / 1000.0
		var st: String = "idle" if ai.entity == null else ai.entity.state_name
		if st != "idle" and st != "move" and st != "attack" and st != "heavy_attack":
			ai._move_intent = Vector2.ZERO
			ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
			return
		if now < ai._parry_stun_until_sec:
			ai._move_intent = Vector2.ZERO
			ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
			return
		if st != "idle" and st != "move":
			ai._move_intent = Vector2.ZERO
			return
		if now < ai._attack_cooldown_until_sec:
			ai._move_intent = Vector2.ZERO
			ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
			return
		if ai.entity == null:
			return
		## #720 血线阶段强化（P2 可选）: _enraged → 冷却缩短 ×0.6（charge 概率 ×1.5 已在 enter 处理）
		var cd: float = float(C.ENEMY_ATTACK_COOLDOWN_SEC) * (0.6 if ai._enraged else 1.0)
		if _attack_kind == "charge":
			if not _issued:
				ai.entity.current_windup_frames = int(C.ENEMY_CHARGE_WINDUP)
				ai.entity.current_hp_damage = float(C.ENEMY_CHARGE_HP_DAMAGE)
				ai.entity.request_transition("heavy_attack")
				ai.entity.current_windup_frames = -1
				ai.entity.current_hp_damage = -1.0
				ai._attack_cooldown_until_sec = now + cd
				_issued = true
			else:
				ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
		elif _is_thrust:
			if not _issued:
				ai.entity.request_transition("heavy_attack")
				ai.entity.current_windup_frames = -1   # #720 清空 thrust 中前摇 override（防泄漏到下一击）
				ai._attack_cooldown_until_sec = now + cd
				_issued = true
			else:
				ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
		else:
			if _strikes < 3:
				ai.entity.request_transition("attack")
				if _strikes == 0:
					ai._attack_cooldown_until_sec = now + cd
				_strikes += 1
			else:
				ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))


class RetreatState:
	extends AIStateBase
	## 回避: 5% 后退一步再扑（AC3，反页游木桩）。
	##   - 进入: 远离玩家方向移动 ENEMY_RETREAT_SECONDS（速度 = ENEMY_CHASE_SPEED）
	##   - 退出（边界 10）: 时长满 → |dx| <= ENEMY_ATTACK_RANGE → AttackState（回扑）；
	##     |dx| > ENEMY_ATTACK_RANGE → ChaseState（玩家后撤不空挥）
	func enter() -> void:
		ai._behavior = "retreat"
		state_name = "retreat"
		_elapsed = 0.0
		if ai.player != null:
			var dx: float = ai.player.position.x - ai.position.x
			var dir: int = 1 if dx > 0.0 else -1
			if dx == 0.0:
				dir = -ai.facing
			ai._move_intent.x = float(-dir) * float(C.ENEMY_CHASE_SPEED)

	func update(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= float(C.ENEMY_RETREAT_SECONDS):
			var dx: float = 0.0
			if ai.player != null:
				dx = ai.player.position.x - ai.position.x
			ai._move_intent = Vector2.ZERO
			if absf(dx) <= float(C.ENEMY_ATTACK_RANGE):
				ai._ai_fsm.transition_to(SelfScript.make_state("attack", ai))
			else:
				ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))


class GuardState:
	extends AIStateBase
	## 防御（#720, issue body 要素 4）: 敌人格挡玩家攻击。复用 11 态 guard 战斗态（零新增状态名）。
	##   - 进入: entity.request_transition("guard")（AI decide 门控冻结位移）→ 玩家攻击命中走 judge
	##     既有 block_held 路径（敌人扣 POSTURE_BLOCK_COST）
	##   - 退出（边界 3）: 持续 ENEMY_GUARD_HOLD_SECONDS → request_transition("idle") + 回 Chase
	##   - 边界: 格挡中敌人被绕背 → facing 不变（MVP 一维，无绕背语义）；格挡中架势归零 → guard→stance_break 表内合法
	func enter() -> void:
		ai._behavior = "guard"
		state_name = "guard"
		_elapsed = 0.0
		ai._guard_until_sec = Time.get_ticks_msec() / 1000.0 + float(C.ENEMY_GUARD_HOLD_SECONDS)
		if ai.entity != null:
			ai.entity.request_transition("guard")

	func update(delta: float) -> void:
		ai._move_intent = Vector2.ZERO
		_elapsed += delta
		if _elapsed >= float(C.ENEMY_GUARD_HOLD_SECONDS):
			if ai.entity != null and ai.entity.state_name == "guard":
				ai.entity.request_transition("idle")
			ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))

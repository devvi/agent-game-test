extends CharacterBody2D
class_name EnemyAI
## EnemyAI — 敌人行为驱动层（#581，基础日本兵 AI）。
## 归属: docs/DESIGN/581-enemy-ai.md §2.1
## 职责: 行为 FSM 持有（第二个 StateMachineBase：patrol/chase/attack/retreat，与 #575 战斗
##   11 态分离）+ 感知（120° 视线 6m 几何判据，无 raycast/Area2D）+ 决策门控（实体非
##   idle/move 不决策 + 弹反抑制窗）+ 位移执行（仿 #573 加速度模型）。
## 单向依赖: AI 决策 → entity.request_transition("attack"/"heavy_attack") + 位移意图；
##   战斗结果 → state_changed / died / judge.parry_success 信号反向门控 AI 决策。
## 可测性核心: decide(delta) 纯决策入口（headless 测试手动驱动，无物理依赖）；
##   _physics_process 只消费 _move_intent。

const C = preload("res://gdscripts/constants.gd")
const StateMachineBaseScript = preload("res://gdscripts/state_machine.gd")
const EnemyAIStatesScript = preload("res://gdscripts/enemy_ai_states.gd")

## @export 参数（#583 场景配置）
@export var waypoints: Array = []            # 巡逻路径（空数组=原地等待，不报错；元素 Vector2）
@export var player: Node2D                   # 玩家实体引用（感知/追击目标；也是 CombatEntity is_player=true）
@export var judge: Node = null               # CombatJudge 引用（null = 不登记窗口，仅行为路径可测）
@export var rng_seed: int = -1               # -1 = 全局 RNG；≥0 = 确定性（测试注入，CI 稳定）
@export var elite_mode: bool = false         # 精英档位（#682）: true → 蓄力重斩出招启用（三选一）；false = #581 小兵二选一

## 运行期成员
var entity: Object = null                    # bind_entity() 注入（#585 组装调用）
var _ai_fsm: Object = null                   # 第二个 StateMachineBase（行为 FSM）
var _move_intent: Vector2 = Vector2.ZERO     # decide() 写、_physics_process 读
var _parry_stun_until_sec: float = 0.0       # 弹反抑制窗截止（AC2 硬直补足，Time 秒）
var _attack_cooldown_until_sec: float = 0.0  # 攻击冷却截止（ENEMY_ATTACK_COOLDOWN_SEC，Time 秒）
var _rng: RandomNumberGenerator              # seed 注入的确定性 RNG
var _dead: bool = false                      # 实体终态后 AI 完全禁用
var facing: int = 1                          # 敌人朝向（1 右 / -1 左；Chase 转向更新）
var _turn_timer: float = 0.0                 # ENEMY_TURN_DELAY_SEC 转向延迟计时
var _behavior: String = "patrol"             # 当前行为态名（调试/回避去重）
var _judge_subscribed: bool = false          # judge 信号已订阅标记（惰性接线）
var _knockback_vel: float = 0.0              # 受击击退初速（#682，stagger 期间沿受击反向，ENEMY_KNOCKBACK_DECAY 衰减）
var _knockback_dir: int = 1                  # 受击反向（相对 attacker 位置，远离攻击者）

func bind_entity(e) -> void:
	## 绑定战斗实体: 注入敌人攻击伤害参数（judge 登记读取）+ 订阅信号
	entity = e
	if e != null:
		e.attack_hp_damage = C.ENEMY_HP_DAMAGE
		e.attack_stance_damage = C.POSTURE_HIT_COST
		e.state_changed.connect(_on_entity_state_changed)
		e.died.connect(_on_entity_died)

func _ready() -> void:
	## 行为 FSM 初始化（PatrolState 起步）+ RNG seed 注入
	_ensure_judge_subscription()
	_ai_fsm = StateMachineBaseScript.new()
	_ai_fsm.transition_to(EnemyAIStatesScript.make_state("patrol", self))
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		_rng.seed = rng_seed
	if player != null and player.has_signal("state_changed"):
		player.state_changed.connect(_on_player_state_changed)

func can_sense_player() -> bool:
	## 120° 视线 6m 几何判据（纯函数，无物理）:
	##   ① entity/player null 或 _dead → false
	##   ② 玩家死亡终态（player.has_method("_is_final_dead") and player._is_final_dead）→ false
	##   ③ 水平距离: dx = player.x - position.x；absf(dx) > ENEMY_SENSE_RANGE_PX → false
	##   ④ 视线锥: to_player.x * facing < cos(60°) * |to_player| → false（半角 60° → cos60°=0.5，
	##      使用 cos(deg_to_rad(C.ENEMY_SENSE_ANGLE_DEG / 2.0)) 计算阈值，闭区间含端点）
	##   ⑤ 高度容忍: 玩家近距（|dx| <= 感知锥水平内切带宽）且 |dy| > ENEMY_SENSE_HEIGHT_TOLERANCE → false
	##   ⑥ 边界语义: 闭区间含端点（距离恰 = RANGE、夹角恰 = 半角均判定为可见）
	if entity == null or _dead:
		return false
	if player == null:
		return false
	if player.has_method("_is_final_dead"):
		if player._is_final_dead:
			return false
	var to_player: Vector2 = player.position - position
	var dx: float = to_player.x
	if absf(to_player.y) > float(C.ENEMY_SENSE_HEIGHT_TOLERANCE):
		return false
	if absf(dx) > float(C.ENEMY_SENSE_RANGE_PX):
		return false
	var half_angle_rad: float = deg_to_rad(float(C.ENEMY_SENSE_ANGLE_DEG) / 2.0)
	var cone_cos: float = cos(half_angle_rad)
	if to_player.x * float(facing) < cone_cos * to_player.length():
		return false
	return true

func decide(delta: float) -> void:
	## 纯决策入口（headless 测试手动调用）:
	##   ① 决策门控: entity == null or _dead → 清 move_intent 返回
	##   ② 实体非 idle/move 态（entity.state_name not in ["idle","move"]）→ 清 move_intent 返回
	##      （战斗动画/硬直期间 combat FSM 接管，AI 不抢戏）
	##   ③ 弹反抑制窗: Time.get_ticks_msec()/1000.0 < _parry_stun_until_sec → 清 move_intent 返回
	##   ④ 推进行为 FSM: _ai_fsm.update(delta)（状态对象写 _move_intent / 调 entity.request_transition）
	_ensure_judge_subscription()
	if entity == null or _dead:
		_move_intent = Vector2.ZERO
		return
	if entity.state_name != "idle" and entity.state_name != "move":
		_move_intent = Vector2.ZERO
		return
	if Time.get_ticks_msec() / 1000.0 < _parry_stun_until_sec:
		_move_intent = Vector2.ZERO
		return
	if _ai_fsm != null:
		_apply_movement(delta)
		_ai_fsm.update(delta)

func move_intent() -> Vector2:
	return _move_intent

func set_rng_seed(seed: int) -> void:
	## RNG seed 注入（测试确定性；CI 稳定）
	rng_seed = seed
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	_rng.seed = seed

func _physics_process(delta: float) -> void:
	## 位移执行（仿 #573 加速度模型）: 只消费 _move_intent
	_apply_movement(delta)

func _apply_movement(delta: float) -> void:
	## 位移模型: 场景树内走物理引擎 move_and_slide（#573 加速度模型）；
	##   headless 免树（--script 测试）手动积分位移——物理空间不存在时 move_and_slide 报错。
	## 击退分支（#682）: 受击击退覆盖 AI 位移意图（stagger 期间 _move_intent 本为 0），
	##   速度按 ENEMY_KNOCKBACK_DECAY 线性衰减，STAGE_WIDTH_PX clamp 兜底（边界 8）。
	##   守卫（边界 1）: 仅实体处于 stagger 态执行击退位移；实体已离开 stagger → 立即清零
	##   _knockback_vel 并走正常位移路径——「stagger 结束 → 击退归零 → Chase 恢复」，
	##   杜绝击退残留（DECAY 线性衰减远慢于 stagger 0.2s）覆盖 Chase 位移（无弹簧抖动）。
	if absf(_knockback_vel) > 0.001:
		if entity == null or entity.state_name != "stagger":
			_knockback_vel = 0.0
		else:
			var kb: float = float(_knockback_dir) * _knockback_vel
			velocity.x = kb
			_knockback_vel = maxf(_knockback_vel - float(C.ENEMY_KNOCKBACK_DECAY) * delta, 0.0)
			if is_inside_tree():
				move_and_slide()
			else:
				position += Vector2(kb * delta, 0.0)
			position.x = clampf(position.x, 0.0, float(C.STAGE_WIDTH_PX))
			return
	if is_inside_tree():
		velocity.x = move_toward(velocity.x, _move_intent.x, C.MOVE_ACCELERATION * delta)
		velocity.y = 0.0
		move_and_slide()
	else:
		velocity.x = _move_intent.x
		velocity.y = 0.0
		position += velocity * delta

func _ensure_judge_subscription() -> void:
	## 惰性接线: judge 绑定后订阅 parry_success（弹反抑制窗触发源 AC2）+ hit_landed（受击击退 #682）
	if judge == null or _judge_subscribed:
		return
	if judge.has_signal("parry_success"):
		judge.parry_success.connect(_on_judge_parry_success)
	if judge.has_signal("hit_landed"):
		judge.hit_landed.connect(_on_judge_hit_landed)
	_judge_subscribed = true

func _on_judge_parry_success(defender, attacker, _stance_damage: float) -> void:
	## 弹反命中本敌人 → 武装弹反抑制窗（AC2: 0.5s 硬直，AI 层补足共享 parry_success 态）
	if _dead or entity == null:
		return
	if attacker != entity:
		return
	_parry_stun_until_sec = Time.get_ticks_msec() / 1000.0 + float(C.ENEMY_PARRY_STUN_SECONDS)

func _on_judge_hit_landed(defender, attacker, _hp_damage: float, _stance_damage: float) -> void:
	## 受击击退（#682）: 本敌人被击中 → 沿受击反向设击退初速（位移在 _apply_movement 衰减执行，
	##   与决策门控正交——硬直中 AI 不决策但击退仍执行）
	if _dead or entity == null:
		return
	if defender != entity:
		return
	var dx: float = 0.0
	if attacker != null:
		dx = attacker.position.x - position.x
	_knockback_dir = -1 if dx >= 0.0 else 1
	_knockback_vel = float(C.ENEMY_KNOCKBACK_PX)

func _on_player_state_changed(_from: String, to: String) -> void:
	## AC3 触发源: 玩家进入 attack/heavy_attack（前摇开始）且玩家在
	##   ENEMY_RETREAT_TRIGGER_RANGE 内 → 掷骰 5%（_rng.randf() < C.ENEMY_RETREAT_CHANCE）
	##   → 行为 FSM 转移 RetreatState（95% 不打断当前行为）
	if to != "attack" and to != "heavy_attack":
		return
	if _ai_fsm == null or entity == null or _dead:
		return
	if entity.state_name != "idle" and entity.state_name != "move":
		return
	if _behavior == "retreat":
		return
	if player == null:
		return
	var dx: float = player.position.x - position.x
	if absf(dx) > float(C.ENEMY_RETREAT_TRIGGER_RANGE):
		return
	if _rng.randf() < float(C.ENEMY_RETREAT_CHANCE):
		_ai_fsm.transition_to(EnemyAIStatesScript.make_state("retreat", self))

func _on_entity_state_changed(_from: String, to: String) -> void:
	## 决策门控补充: 实体进入非 idle/move 态时清 move_intent（decide 内自然被门控，这里同步清理）
	if to != "idle" and to != "move":
		_move_intent = Vector2.ZERO
		_turn_timer = 0.0

func _on_entity_died(_entity, _final: bool) -> void:
	## 实体死亡（终态）→ AI 完全禁用（不再感知/移动/决策）
	_dead = true
	_move_intent = Vector2.ZERO

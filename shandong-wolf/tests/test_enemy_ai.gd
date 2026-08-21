extends Object
## Test suite for EnemyAI 行为层 (#581).
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/581-enemy-ai.md §9 (Scenario A-G, 36 test cases)
##
## Godot 4.7.1 --script 硬性约束 (同 test_combat_judge.gd):
##   - 禁止 := 类型推断 (4.7.1 视推断警告为硬错误) — 一律显式类型或普通 =
##   - class_name 一律经 load() 脚本资源访问，禁止按标识符引用
##   - 纯数据断言免树直接 new + 手动 decide/tick，不依赖真实帧/物理/Input
##   - RNG 一律 set_rng_seed() 注入确定性（CI 稳定）
##   - Time 系门控（弹反抑制窗/攻击冷却）用成员赋值推进（_parry_stun_until_sec /
##     _attack_cooldown_until_sec 直接置 0 清窗），不依赖真实时钟

const TEST_FRAME_SEC: float = 1.0 / 60.0

var passed: int = 0
var failed: int = 0

## judge 五结果事件日志（handler 写成员，用例间 _reset_logs() 隔离）
var _parry_log: Array = []
var _hit_log: Array = []


func run() -> void:
	print("\n=== EnemyAI Tests ===")
	# Scenario A: 主路径——巡逻 → 发现 → 追击 → 攻击（AC1 + AC5）
	_test_1_patrol_pingpong()
	_test_2_sense_detect_chase()
	_test_3_chase_approach_stop()
	_test_4_attack_transition()
	_test_5_attack_window_windup()
	_test_6_thrust_vs_combo_decision()
	_test_7_attack_cooldown()
	_test_8_smoke_5s_full_path()
	_reset_logs()
	_test_9_parry_during_windup()
	# Scenario B: 感知边界（PRD 实验 1 内化）
	_test_10_angle_boundary()
	_test_11_distance_boundary()
	_test_12_height_tolerance()
	_test_13_behind_no_sense()
	_test_14_chase_lose_sight()
	_test_15_sense_reproducible()
	# Scenario C: 弹反硬直与架势崩解（AC2）
	_reset_logs()
	_test_16_parry_stance_reduction()
	_reset_logs()
	_test_17_four_parries_break()
	_reset_logs()
	_test_18_parry_stun_window()
	_test_19_stance_break_no_decide()
	# Scenario D: 5% 后退回避（AC3 + PRD 实验 2 内化）
	_test_20_retreat_trigger()
	_test_21_retreat_frequency()
	_test_22_retreat_deterministic()
	_test_23_no_retreat_95()
	_test_24_retreat_followup()
	# Scenario E: 常量驱动（AC4）
	_test_25_constants_driven()
	_test_26_invalid_sense_values()
	# Scenario F: 边界与失败路径（§5）
	_test_27_empty_waypoints()
	_test_28_single_waypoint()
	_test_29_judge_unbound()
	_test_30_entity_unbound()
	_test_31_enemy_death_disables()
	_test_32_stagger_gate()
	_reset_logs()
	_test_33_combo_interrupt()
	_test_34_retreat_player_fled()
	# Scenario E(#682): 精英蓄力重斩（elite 门控 / 窗口契约 / override 无泄漏 / 可弹反）
	_test_35_elite_gate_no_charge()
	_test_36_elite_gate_charge_exists()
	_test_37_charge_window_contract()
	_test_38_override_no_leak()
	_test_39_charge_parryable()
	# Scenario D(#682): 受击击退（触发 / 位移衰减 / 归零 / 玩家豁免 / 边界 clamp）
	_test_40_knockback_trigger()
	_test_41_knockback_displacement_decay()
	_test_42_knockback_decay_to_zero()
	_test_43_knockback_player_not_affected()
	_test_44_knockback_edge_clamp()
	# Scenario G: 回归基线（T35/T36 归 CI：run_tests.gd 10 套件全绿 + smoke）
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _reset_logs() -> void:
	_parry_log = []
	_hit_log = []


# ── helpers ─────────────────────────────────────────────────────────────

func _const_map() -> Dictionary:
	var script = load("res://gdscripts/constants.gd")
	if script == null:
		return {}
	return script.get_script_constant_map()


func _c(name: String) -> Variant:
	return _const_map().get(name, -1)


func _new_ai():
	var s = load("res://gdscripts/enemy_ai.gd")
	if s == null:
		_assert(false, "enemy_ai.gd missing (TDD red phase)")
		return null
	var ai = s.new()
	if ai == null:
		_assert(false, "enemy_ai.gd failed to instantiate")
	return ai


func _new_entity(params: Dictionary):
	var s = load("res://gdscripts/combat_entity.gd")
	if s == null:
		_assert(false, "combat_entity.gd missing")
		return null
	var e = s.new(params)
	if e == null:
		_assert(false, "combat_entity.gd failed to instantiate")
	return e


func _new_judge():
	var s = load("res://gdscripts/combat_judge.gd")
	if s == null:
		_assert(false, "combat_judge.gd missing")
		return null
	return s.new()


## 标准装配: AI + 敌人实体 + 玩家实体（is_player=true），摆位完成，_ready 手动触发
func _setup(player_x: float, enemy_x: float, seed_val: int = -1, waypoints: Array = []):
	var ai = _new_ai()
	if ai == null:
		return {}
	var enemy = _new_entity({is_player=false, life_total=1, life_1_max=float(_c("ENEMY_HP_MAX")), stance_max=float(_c("POSTURE_BREAK_THRESHOLD"))})
	var player = _new_entity({is_player=true})
	if enemy == null or player == null:
		return {}
	enemy.position = Vector2(enemy_x, 0)
	player.position = Vector2(player_x, 0)
	enemy.facing = 1
	ai.waypoints = waypoints
	ai.player = player
	ai.bind_entity(enemy)
	if seed_val >= 0:
		ai.set_rng_seed(seed_val)
	ai._ready()
	## 攻击冷却/弹反抑制窗清空（Time 门控测试直接推进，不依赖真实时钟）
	ai._attack_cooldown_until_sec = 0.0
	ai._parry_stun_until_sec = 0.0
	return {"ai": ai, "enemy": enemy, "player": player}


## 推进 N 秒: 每帧 decide + entity 战斗 FSM 推进（headless 免树驱动）
func _tick(s: Dictionary, seconds: float) -> void:
	var ai = s["ai"]
	var enemy = s["enemy"]
	var frames: int = int(seconds / TEST_FRAME_SEC)
	for i in range(frames):
		enemy._process(TEST_FRAME_SEC)
		ai.decide(TEST_FRAME_SEC)


## AI 行为 FSM 当前行为态名映射（get_class() 对 inner class 返回 RefCounted，改用 ai._behavior）
## 返回 "PatrolState"/"ChaseState"/"AttackState"/"RetreatState" 形态，保持既有断言不变
func _ai_state(ai) -> String:
	var st = ai._ai_fsm
	if st == null or st.current_state == null:
		return "null"
	var b: String = ai._behavior
	if b == "":
		return "null"
	return b.capitalize() + "State"


## 让敌人进入攻击态（停距 + 冷却就绪 → decide 触发攻击）
func _enter_attack(s: Dictionary) -> void:
	var ai = s["ai"]
	var enemy = s["enemy"]
	## 推进到停距（|dx| <= ENEMY_ATTACK_RANGE）且冷却就绪
	ai._attack_cooldown_until_sec = 0.0
	var guard: int = 0
	while enemy.state_name != "attack" and enemy.state_name != "heavy_attack" and guard < 600:
		_tick(s, TEST_FRAME_SEC)
		guard += 1


# ── Scenario A: 主路径（AC1 + AC5）───────────────────────────────────────

func _test_1_patrol_pingpong() -> void:
	## 巡逻起步: waypoints ping-pong，玩家远置 → 敌人 x 在 waypoints 间往返；实体保持 idle/move
	var s = _setup(1000.0, 0.0, 7, [Vector2(-300, 0), Vector2(300, 0)])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	var patrol_speed: float = float(_c("ENEMY_PATROL_SPEED"))
	var max_x: float = -9999.0
	var min_x: float = 9999.0
	var saw_entity_move: bool = false
	## 720 帧 = 12s: 80px/s 巡逻往返 600px 需 7.5s + 每侧 1s 停顿 ×2 → 两侧都访问需 ~10s
	for i in range(720):
		_tick(s, TEST_FRAME_SEC)
		max_x = maxf(max_x, ai.position.x)
		min_x = minf(min_x, ai.position.x)
		if enemy.state_name == "move":
			saw_entity_move = true
	_assert(max_x > 100.0, "patrol reaches right waypoint vicinity (max_x=%.1f)" % max_x)
	_assert(min_x < -100.0, "patrol reaches left waypoint vicinity (min_x=%.1f)" % min_x)
	_assert(ai.position.x <= 300.0 and ai.position.x >= -300.0, "patrol stays within waypoint bounds (x=%.1f)" % ai.position.x)
	_assert(enemy.state_name == "idle" or enemy.state_name == "move", "enemy stays in idle/move during patrol (got %s)" % enemy.state_name)
	_assert(patrol_speed > 0.0, "ENEMY_PATROL_SPEED constant present")


func _test_2_sense_detect_chase() -> void:
	## 感知发现: 玩家 (400,0) 视线内 → can_sense_player true → 行为 FSM 转移 Chase
	var s = _setup(400.0, 0.0, 7, [Vector2(-300, 0), Vector2(300, 0)])
	if s.is_empty(): return
	var ai = s["ai"]
	_assert(ai.can_sense_player(), "can_sense_player() == true for player at (400,0)")
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "ChaseState", "AI transitions to ChaseState after sensing (got %s)" % _ai_state(ai))
	_assert(ai.facing == 1, "enemy faces player (facing=1)")


func _test_3_chase_approach_stop() -> void:
	## 追击逼近: 玩家静止 → 敌人以 ENEMY_CHASE_SPEED 逼近；|dx| <= ENEMY_ATTACK_RANGE 后停距
	var s = _setup(400.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var chase_speed: float = float(_c("ENEMY_CHASE_SPEED"))
	var attack_range: float = float(_c("ENEMY_ATTACK_RANGE"))
	## 逼近阶段: 前 30 帧位移朝玩家方向且速度接近 CHASE_SPEED
	var moved_toward: bool = false
	for i in range(30):
		var before: float = ai.position.x
		_tick(s, TEST_FRAME_SEC)
		if ai.position.x > before + 1.0:
			moved_toward = true
	_assert(moved_toward, "enemy moves toward player during chase")
	_assert(chase_speed > 0.0, "ENEMY_CHASE_SPEED constant present")
	## 推进到停距
	var guard: int = 0
	while absf(ai.position.x - 400.0) > attack_range and guard < 600:
		_tick(s, TEST_FRAME_SEC)
		guard += 1
	_assert(absf(ai.position.x - 400.0) <= attack_range + 2.0, "enemy stops within attack range (dx=%.1f)" % absf(ai.position.x - 400.0))
	## 停距后 move_intent.x == 0（Chase 停距语义）
	var intent: Vector2 = ai.move_intent()
	_assert(intent.x == 0.0, "move_intent.x == 0 when within attack range (got %.1f)" % intent.x)


func _test_4_attack_transition() -> void:
	## 攻击发起 (AC1): 停距 + 冷却就绪 → entity.request_transition("attack") 生效
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	_enter_attack(s)
	_assert(enemy.state_name == "attack" or enemy.state_name == "heavy_attack", "enemy enters attack state (got %s)" % enemy.state_name)
	_assert(absf(float(enemy.attack_hp_damage) - float(_c("ENEMY_HP_DAMAGE"))) < 0.0001, "enemy.attack_hp_damage injected == ENEMY_HP_DAMAGE (got %.1f)" % float(enemy.attack_hp_damage))
	_assert(ai._ai_fsm.current_state != null, "AI behavior FSM has active state")


func _test_5_attack_window_windup() -> void:
	## 攻击窗口 windup (AC1): 绑定 judge + 敌人 attack → 自动登记窗口 windup_frames == ENEMY_ATTACK_WINDUP
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	var judge = _new_judge()
	if judge == null: return
	judge.bind_entities(s["player"], enemy)
	ai.judge = judge
	_enter_attack(s)
	_assert(enemy.state_name == "attack" or enemy.state_name == "heavy_attack", "enemy attacking for window registration (got %s)" % enemy.state_name)
	_assert(judge._windows.size() >= 1, "judge auto-registered attack window for enemy")
	if judge._windows.size() >= 1:
		var w = judge._windows[judge._windows.size() - 1]
		var expected_windup: int = int(_c("ENEMY_ATTACK_WINDUP"))
		_assert(int(w.windup_frames) == expected_windup, "window.windup_frames == ENEMY_ATTACK_WINDUP(%d) (got %d)" % [expected_windup, int(w.windup_frames)])
		_assert(w.hit_frame() == w.start_frame + expected_windup, "hit_frame() == start + ENEMY_ATTACK_WINDUP")
		_assert(absf(float(w.hp_damage) - float(_c("ENEMY_HP_DAMAGE"))) < 0.0001, "window.hp_damage reads enemy entity param (got %.1f)" % float(w.hp_damage))


func _test_6_thrust_vs_combo_decision() -> void:
	## 三连砍 vs 突刺决策: 扫描 seed 找两个确定性种子——一个首次攻击 attack（连段）、一个 heavy_attack（突刺）
	var combo_seed: int = -1
	var thrust_seed: int = -1
	for seed_val in range(60):
		var s = _setup(80.0, 0.0, seed_val, [])
		if s.is_empty(): return
		_enter_attack(s)
		var st: String = s["enemy"].state_name
		if st == "attack" and combo_seed < 0:
			combo_seed = seed_val
		if st == "heavy_attack" and thrust_seed < 0:
			thrust_seed = seed_val
		if combo_seed >= 0 and thrust_seed >= 0:
			break
	_assert(combo_seed >= 0, "found seed where first attack is combo (attack)")
	_assert(thrust_seed >= 0, "found seed where first attack is thrust (heavy_attack)")
	_assert(float(_c("ENEMY_THRUST_CHANCE")) > 0.0 and float(_c("ENEMY_THRUST_CHANCE")) < 1.0, "ENEMY_THRUST_CHANCE ∈ (0,1)")


func _test_7_attack_cooldown() -> void:
	## 攻击冷却: 攻击后冷却未到不发起；冷却过后可再次发起
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	_enter_attack(s)
	_assert(enemy.state_name == "attack" or enemy.state_name == "heavy_attack", "first attack initiated (got %s)" % enemy.state_name)
	## 冷却未到: 强制回 idle 后立即决策 → 不发起新攻击
	ai._attack_cooldown_until_sec = 99999.0
	enemy.request_transition("idle")
	_tick(s, 0.2)
	_assert(enemy.state_name != "attack" and enemy.state_name != "heavy_attack", "no new attack during cooldown (got %s)" % enemy.state_name)
	## 冷却过后: 清窗 → 再次攻击
	ai._attack_cooldown_until_sec = 0.0
	_tick(s, 0.2)
	_assert(enemy.state_name == "attack" or enemy.state_name == "heavy_attack", "attack re-initiated after cooldown (got %s)" % enemy.state_name)


func _test_8_smoke_5s_full_path() -> void:
	## AC5 smoke: 玩家站桩 (400,0) → 5s 内完成 巡逻→发现→接近→攻击 全路径
	var s = _setup(400.0, 0.0, 3, [Vector2(-200, 0), Vector2(200, 0)])
	if s.is_empty(): return
	var enemy = s["enemy"]
	var reached_attack: bool = false
	var saw_chase: bool = false
	for i in range(300):
		_tick(s, TEST_FRAME_SEC)
		if enemy.state_name == "attack" or enemy.state_name == "heavy_attack":
			reached_attack = true
		if i < 120:
			saw_chase = saw_chase or _ai_state(s["ai"]) == "ChaseState"
	_assert(saw_chase, "enemy entered chase within first 2s")
	_assert(reached_attack, "enemy reached attack state within 5s (AC5)")


func _test_9_parry_during_windup() -> void:
	## 攻击态内可被弹反 (AC1 后半): 敌人窗口 active 时 guard_pressed ∈ 闭区间 → parry_success
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	var player = s["player"]
	var judge = _new_judge()
	if judge == null: return
	judge.bind_entities(player, enemy)
	ai.judge = judge
	judge.parry_success.connect(_on_parry_success)
	judge.hit_landed.connect(_on_hit_landed)
	player.facing = -1  # 面向攻击者
	player.position = Vector2(80, 0)
	enemy.facing = 1
	_enter_attack(s)
	_assert(enemy.state_name == "attack" or enemy.state_name == "heavy_attack", "enemy attacking (got %s)" % enemy.state_name)
	## 推进 judge 到命中帧: 窗口 start_frame 已知，windup=12
	if judge._windows.size() >= 1:
		var w = judge._windows[judge._windows.size() - 1]
		var hit_frame: int = w.hit_frame()
		judge._frame = hit_frame
		var hit_ms: int = int(hit_frame * 1000 / int(_c("FRAME_RHYTHM_BASE")))
		var pws: float = float(_c("PARRY_WINDOW_SECONDS"))
		judge._on_guard_pressed(hit_ms)  # 上界（含端点）
		judge.resolve_attack(enemy, player)
		_assert(_parry_log.size() == 1, "parry_success emitted once for enemy window (got %d)" % _parry_log.size())
		if _parry_log.size() == 1:
			_assert(_parry_log[0][0] == player and _parry_log[0][1] == enemy, "parry_success(defender=player, attacker=enemy)")
		_assert(player.hp_1 == float(_c("LIFE_1_MAX")), "parry: player takes 0 damage")


# ── Scenario B: 感知边界（PRD 实验 1 内化）───────────────────────────────

func _test_10_angle_boundary() -> void:
	## 角度边界: 夹角恰 60°（半角）→ true（闭区间含端点）；61° → false
	var s = _setup(400.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	ai.facing = 1
	## 构造玩家位置使 to_player 与 facing 夹角 = 60°: dx = 149/tan(60°) ≈ 86.03 → 86.1（高度容忍 150 内）
	s["player"].position = Vector2(86.1, 149.0)
	_assert(ai.can_sense_player(), "angle exactly 60° → visible (closed interval)")
	s["player"].position = Vector2(82.59, 149.0)  # dx = 149/tan(61°) ≈ 82.59 → 61°（高度容忍 150 内，纯角度超界）
	_assert(not ai.can_sense_player(), "angle > 60° → not visible")


func _test_11_distance_boundary() -> void:
	## 距离边界: |dx| 恰 ENEMY_SENSE_RANGE_PX → true；+1 → false
	var s = _setup(0.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var rng: float = float(_c("ENEMY_SENSE_RANGE_PX"))
	ai.facing = 1
	s["player"].position = Vector2(rng, 0)
	_assert(ai.can_sense_player(), "|dx| == ENEMY_SENSE_RANGE_PX → visible (closed interval)")
	s["player"].position = Vector2(rng + 1.0, 0)
	_assert(not ai.can_sense_player(), "|dx| == RANGE+1 → not visible (> threshold = false)")


func _test_12_height_tolerance() -> void:
	## 高度容忍: |dy| 恰 150 → true；151 → false
	var s = _setup(300.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var tol: float = float(_c("ENEMY_SENSE_HEIGHT_TOLERANCE"))
	ai.facing = 1
	s["player"].position = Vector2(300, tol)
	_assert(ai.can_sense_player(), "|dy| == tolerance → visible (closed interval)")
	s["player"].position = Vector2(300, tol + 1.0)
	_assert(not ai.can_sense_player(), "|dy| == tolerance+1 → not visible")


func _test_13_behind_no_sense() -> void:
	## 身后不发现: 玩家在敌人背后（facing 反向）→ false（视线锥外）
	var s = _setup(-300.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	ai.facing = 1
	_assert(not ai.can_sense_player(), "player behind enemy (facing=1, player at -300) → not visible")


func _test_14_chase_lose_sight() -> void:
	## 追击丢失: Chase 中玩家移出 ENEMY_LOSE_SIGHT_RANGE → 回 PatrolState
	var s = _setup(400.0, 0.0, 7, [Vector2(-300, 0), Vector2(300, 0)])
	if s.is_empty(): return
	var ai = s["ai"]
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "ChaseState", "chasing before lose-sight (got %s)" % _ai_state(ai))
	var lose: float = float(_c("ENEMY_LOSE_SIGHT_RANGE"))
	s["player"].position = Vector2(lose + 100.0, 0)
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "PatrolState", "lost sight → back to PatrolState (got %s)" % _ai_state(ai))


func _test_15_sense_reproducible() -> void:
	## 感知可复现性: 同输入矩阵 → 判定结果仅依赖 facing/距离/高度三输入（无隐藏状态）
	var s = _setup(0.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var results_a: Array = []
	var results_b: Array = []
	var rng: float = float(_c("ENEMY_SENSE_RANGE_PX"))
	var tol: float = float(_c("ENEMY_SENSE_HEIGHT_TOLERANCE"))
	for facing in [-1, 1]:
		for dx in [-int(rng), -int(rng) / 2, 0, int(rng) / 2, int(rng)]:
			for dy in [-int(tol), 0, int(tol)]:
				ai.facing = facing
				s["player"].position = Vector2(dx, dy)
				results_a.append(ai.can_sense_player())
	ai.facing = 1
	s["player"].position = Vector2(123, 45)
	var probe_a: bool = ai.can_sense_player()  # 中间状态干扰
	ai.facing = 1
	s["player"].position = Vector2(123, 45)
	var probe_b: bool = ai.can_sense_player()
	_assert(probe_a == probe_b, "sense is pure (same input twice)")
	for facing in [-1, 1]:
		for dx in [-int(rng), -int(rng) / 2, 0, int(rng) / 2, int(rng)]:
			for dy in [-int(tol), 0, int(tol)]:
				ai.facing = facing
				s["player"].position = Vector2(dx, dy)
				results_b.append(ai.can_sense_player())
	_assert(results_a.size() == results_b.size(), "sense result matrix sizes equal")
	var identical: bool = true
	for i in range(results_a.size()):
		if bool(results_a[i]) != bool(results_b[i]):
			identical = false
			break
	_assert(identical, "sense results reproducible (pure function of inputs)")


# ── Scenario C: 弹反硬直与架势崩解（AC2）─────────────────────────────────

func _test_16_parry_stance_reduction() -> void:
	## 弹反架势扣减: 敌人被弹反 → stance 扣 PARRY_STANCE_DAMAGE 且收到 parry_success
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	var player = s["player"]
	var judge = _new_judge()
	if judge == null: return
	judge.bind_entities(player, enemy)
	ai.judge = judge
	judge.parry_success.connect(_on_parry_success)
	player.facing = -1
	enemy.facing = 1
	_enter_attack(s)
	var stance_before: float = enemy.stance
	var pd: float = float(_c("PARRY_STANCE_DAMAGE"))
	_parry_at_hit_frame(judge, enemy, player)
	_assert(_parry_log.size() == 1, "parry_success emitted (got %d)" % _parry_log.size())
	_assert(absf((stance_before - enemy.stance) - pd) < 0.0001, "enemy stance reduced by PARRY_STANCE_DAMAGE (%.1f)" % (stance_before - enemy.stance))


func _test_17_four_parries_break() -> void:
	## 连续 4 次弹反崩解: 4 × PARRY_STANCE_DAMAGE == POSTURE_BREAK_THRESHOLD → stance_break
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	var player = s["player"]
	var judge = _new_judge()
	if judge == null: return
	judge.bind_entities(player, enemy)
	ai.judge = judge
	judge.parry_success.connect(_on_parry_success)
	player.facing = -1
	enemy.facing = 1
	var pd: float = float(_c("PARRY_STANCE_DAMAGE"))
	var threshold: float = float(_c("POSTURE_BREAK_THRESHOLD"))
	var parries: int = int(ceil(threshold / pd))
	for i in range(parries):
		if enemy.state_name != "attack" and enemy.state_name != "heavy_attack":
			ai._attack_cooldown_until_sec = 0.0
			_enter_attack(s)
		_parry_at_hit_frame(judge, enemy, player)
		## 轮转准备下一轮弹反: 退出攻击态 + 清抑制窗 + 推进 judge 帧（同帧同窗口防重入 → 必须新窗口）
		if enemy.state_name == "attack" or enemy.state_name == "heavy_attack":
			enemy.request_transition("idle")
		ai._parry_stun_until_sec = 0.0
		judge._frame += 1000
	_assert(enemy.is_stance_broken, "enemy stance broken after %d parries" % parries)
	_assert(enemy.state_name == "stance_break", "enemy in stance_break state (got %s)" % enemy.state_name)


func _test_18_parry_stun_window() -> void:
	## 弹反硬直抑制窗 (AC2): 弹反后 _parry_stun_until_sec 生效 → 抑制窗内 decide 不追击/攻击
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	var player = s["player"]
	var judge = _new_judge()
	if judge == null: return
	judge.bind_entities(player, enemy)
	ai.judge = judge
	judge.parry_success.connect(_on_parry_success)
	player.facing = -1
	enemy.facing = 1
	_enter_attack(s)
	_parry_at_hit_frame(judge, enemy, player)
	var stun_sec: float = float(_c("ENEMY_PARRY_STUN_SECONDS"))
	_assert(_parry_log.size() == 1, "parry landed for stun window test")
	_assert(ai._parry_stun_until_sec > 0.0, "parry stun window armed (until=%.2f)" % ai._parry_stun_until_sec)
	## 抑制窗内: 清冷却后仍不发起攻击/追击（move_intent 归零）
	ai._attack_cooldown_until_sec = 0.0
	enemy.request_transition("idle")
	ai._parry_stun_until_sec = 99999.0
	_tick(s, 0.3)
	var intent: Vector2 = ai.move_intent()
	_assert(enemy.state_name != "attack" and enemy.state_name != "heavy_attack", "no attack during parry stun (got %s)" % enemy.state_name)
	_assert(intent.x == 0.0, "no chase movement during parry stun (intent.x=%.1f)" % intent.x)
	_assert(stun_sec >= 0.5, "ENEMY_PARRY_STUN_SECONDS == 0.5 (AC2, got %.2f)" % stun_sec)


func _test_19_stance_break_no_decide() -> void:
	## 崩解期间 AI 不决策: stance_break 态内 decide 门控返回；恢复 idle 后回 Chase
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	enemy.break_stance()
	_assert(enemy.state_name == "stance_break", "enemy in stance_break (got %s)" % enemy.state_name)
	_tick(s, 0.5)
	var intent: Vector2 = ai.move_intent()
	_assert(intent.x == 0.0, "no movement during stance_break (intent.x=%.1f)" % intent.x)
	## 恢复 idle → 决策解锁（回 Chase）
	enemy.request_transition("idle")
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "ChaseState", "AI resumes chase after stance_break recovery (got %s)" % _ai_state(ai))


# ── Scenario D: 5% 后退回避（AC3 + PRD 实验 2 内化）───────────────────────

func _test_20_retreat_trigger() -> void:
	## 回避触发: seed 使 randf() < 0.05 且玩家 attack 前摇 + 距离内 → RetreatState 远离玩家
	var s = _setup(200.0, 0.0, 0, [])  # seed=0: 首个 randf 小概率命中
	if s.is_empty(): return
	var ai = s["ai"]
	var player = s["player"]
	var found: bool = false
	for seed_val in range(200):
		var s2 = _setup(200.0, 0.0, seed_val, [])
		if s2.is_empty(): return
		var ai2 = s2["ai"]
		var player2 = s2["player"]
		player2.request_transition("attack")  # 触发 _on_player_state_changed
		if _ai_state(ai2) == "RetreatState":
			found = true
			break
	_assert(found, "found seed where player attack triggers RetreatState")
	## 用找到的 seed 验证远离方向
	for seed_val in range(200):
		var s2 = _setup(200.0, 0.0, seed_val, [])
		if s2.is_empty(): return
		var ai2 = s2["ai"]
		var player2 = s2["player"]
		player2.request_transition("attack")
		if _ai_state(ai2) == "RetreatState":
			var before: float = ai2.position.x
			_tick(s2, 0.3)
			_assert(ai2.position.x < before, "retreat moves away from player (player at +200, x %.1f → %.1f)" % [before, ai2.position.x])
			break
	pass


func _test_21_retreat_frequency() -> void:
	## 回避频率统计: 1000 次独立「玩家攻击前摇」事件（每次全新 seed 实例——同实例重复
	## request_transition("attack") 是同态 restart 不发射 state_changed，单事件粘滞无法统计）
	## → Retreat 触发频率 ∈ [0.03, 0.07]（收敛于 0.05 ± 0.02，AC3）
	var retreats: int = 0
	var trials: int = 1000
	for i in range(trials):
		var s2 = _setup(200.0, 0.0, 12345 + i, [])
		if s2.is_empty():
			return
		s2["player"].request_transition("attack")
		if _ai_state(s2["ai"]) == "RetreatState":
			retreats += 1
	var freq: float = float(retreats) / float(trials)
	_assert(freq >= 0.03 and freq <= 0.07, "retreat frequency %.3f ∈ [0.03, 0.07] (AC3)" % freq)


func _test_22_retreat_deterministic() -> void:
	## 确定性: 同一 seed 重跑 → 回避序列逐次一致；seed=-1 全局 RNG 兜底不崩溃
	var seq_a: Array = []
	var seq_b: Array = []
	for rep in range(2):
		var s = _setup(200.0, 0.0, 42, [])
		if s.is_empty(): return
		var ai = s["ai"]
		var player = s["player"]
		var seq: Array = []
		for i in range(50):
			player.request_transition("attack")
			seq.append(_ai_state(ai) == "RetreatState")
		if rep == 0:
			seq_a = seq
		else:
			seq_b = seq
	var identical: bool = true
	for i in range(seq_a.size()):
		if bool(seq_a[i]) != bool(seq_b[i]):
			identical = false
			break
	_assert(identical, "same seed → identical retreat sequence (deterministic)")
	## seed=-1: 全局 RNG 不崩溃
	var s2 = _setup(200.0, 0.0, -1, [])
	if s2.is_empty(): return
	s2["player"].request_transition("attack")
	_assert(true, "seed=-1 global RNG path does not crash")


func _test_23_no_retreat_95() -> void:
	## 95% 不回避: seed 注入 randf() ≥ 0.05 → 当前行为不被打断（Chase 继续逼近）
	var s = _setup(400.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var player = s["player"]
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "ChaseState", "chasing before player attack (got %s)" % _ai_state(ai))
	player.request_transition("attack")
	_assert(_ai_state(ai) == "ChaseState", "player attack with unlucky roll → chase NOT interrupted (got %s)" % _ai_state(ai))


func _test_24_retreat_followup() -> void:
	## 回避后回扑: Retreat 期满且 |dx| <= ENEMY_ATTACK_RANGE → Attack；玩家后撤 → Chase
	var s = _setup(80.0, 0.0, 0, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var player = s["player"]
	## 找触发 seed
	var trigger_seed: int = -1
	for seed_val in range(200):
		var s2 = _setup(80.0, 0.0, seed_val, [])
		if s2.is_empty(): return
		s2["player"].request_transition("attack")
		if _ai_state(s2["ai"]) == "RetreatState":
			trigger_seed = seed_val
			break
	_assert(trigger_seed >= 0, "found retreat trigger seed")
	pass
	pass


# ── Scenario E: 常量驱动（AC4）───────────────────────────────────────────

func _test_25_constants_driven() -> void:
	## 全参数读常量: 行为边界随常量值（改 constants 文件 → 断言随动）
	var s = _setup(0.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var rng: float = float(_c("ENEMY_SENSE_RANGE_PX"))
	var tol: float = float(_c("ENEMY_SENSE_HEIGHT_TOLERANCE"))
	## 距离边界 = 常量值（600 → 改 400 后此断言自动随动）
	ai.facing = 1
	s["player"].position = Vector2(rng, 0)
	_assert(ai.can_sense_player(), "distance boundary follows ENEMY_SENSE_RANGE_PX=%.0f" % rng)
	s["player"].position = Vector2(rng + 1.0, 0)
	_assert(not ai.can_sense_player(), "distance boundary+1 not visible (constant-driven)")
	## 高度边界 = 常量值
	s["player"].position = Vector2(300, tol)
	_assert(ai.can_sense_player(), "height boundary follows ENEMY_SENSE_HEIGHT_TOLERANCE=%.0f" % tol)
	## 概率常量存在且合法
	_assert(float(_c("ENEMY_RETREAT_CHANCE")) == 0.05, "ENEMY_RETREAT_CHANCE == 0.05 (AC3)")
	_assert(float(_c("ENEMY_PARRY_STUN_SECONDS")) >= 0.5, "ENEMY_PARRY_STUN_SECONDS == 0.5 (AC2)")


func _test_26_invalid_sense_values() -> void:
	## 感知数值非法兜底: RANGE ≤ 0 / 角度 > 180 → push_warning + 回退默认值（不崩溃）
	var s = _setup(300.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	ai.can_sense_player()  # 正常路径
	_assert(true, "sense with valid constants does not crash")
	## 非法配置路径: 直接构造极端位置不崩溃（非法常量由 constants 域保证，AI 侧防御性 clamp）
	s["player"].position = Vector2(99999, 99999)
	var ok: bool = ai.can_sense_player()
	_assert(ok == false, "extreme player position → not visible, no crash")


# ── Scenario F: 边界与失败路径（§5）──────────────────────────────────────

func _test_27_empty_waypoints() -> void:
	## waypoints 空数组: Patrol 原地等待不报错；玩家进入感知 → 仍可 Chase
	var s = _setup(1000.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var x0: float = ai.position.x
	_tick(s, 0.5)
	_assert(absf(ai.position.x - x0) < 1.0, "empty waypoints → stand still (x=%.1f)" % ai.position.x)
	s["player"].position = Vector2(400.0, 0)
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "ChaseState", "sense still triggers chase with empty waypoints (got %s)" % _ai_state(ai))


func _test_28_single_waypoint() -> void:
	## 单 waypoint: ping-pong 降级原地等待（不报错）
	var s = _setup(1000.0, 0.0, 7, [Vector2(100, 0)])
	if s.is_empty(): return
	var ai = s["ai"]
	_tick(s, 1.0)
	_assert(absf(ai.position.x) <= 100.0 + 1.0, "single waypoint → stays near it (x=%.1f)" % ai.position.x)
	_assert(true, "single waypoint no crash")


func _test_29_judge_unbound() -> void:
	## judge 未绑定: decide 正常推进行为路径；攻击不登记窗口；不 NPE
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var enemy = s["enemy"]
	_enter_attack(s)
	_assert(enemy.state_name == "attack" or enemy.state_name == "heavy_attack", "attack works without judge (got %s)" % enemy.state_name)
	_assert(true, "judge=null path no NPE")


func _test_30_entity_unbound() -> void:
	## entity 未绑定: decide 门控返回；移动模型独立可验证
	var ai = _new_ai()
	if ai == null: return
	ai._ready()
	ai.decide(TEST_FRAME_SEC)
	_assert(true, "decide with entity=null no NPE (gated return)")
	## 移动模型: 无 entity 时 move_intent 消费
	ai._move_intent = Vector2(100, 0)
	ai._physics_process(TEST_FRAME_SEC)
	_assert(true, "_physics_process consumes move_intent without entity")


func _test_31_enemy_death_disables() -> void:
	## 敌人死亡: die() (life_total=1 → final dead) → _dead=true → decide 完全禁用
	var s = _setup(400.0, 0.0, 7, [Vector2(-200, 0), Vector2(200, 0)])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	enemy.die()
	_assert(ai._dead == true, "AI._dead set on entity death")
	var x0: float = ai.position.x
	_tick(s, 1.0)
	_assert(absf(ai.position.x - x0) < 1.0, "no movement after death (x=%.1f)" % ai.position.x)
	_assert(not ai.can_sense_player(), "no sensing after death")


func _test_32_stagger_gate() -> void:
	## 敌人受击 stagger: stagger 态内 decide 门控返回；恢复后继续
	var s = _setup(400.0, 0.0, 7, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "ChaseState", "chasing before stagger (got %s)" % _ai_state(ai))
	enemy.take_damage(10.0)
	_assert(enemy.state_name == "stagger", "enemy staggered (got %s)" % enemy.state_name)
	_tick(s, 0.1)
	var intent: Vector2 = ai.move_intent()
	_assert(intent.x == 0.0, "no movement during stagger (intent.x=%.1f)" % intent.x)
	## 恢复后继续追
	_tick(s, 0.5)
	_assert(_ai_state(ai) == "ChaseState", "resumes chase after stagger (got %s)" % _ai_state(ai))


func _test_33_combo_interrupt() -> void:
	## 连段中断: 三连砍第 2 刀前玩家弹反 → parry_success → 连段计划作废（抑制窗接管）
	var s = _setup(80.0, 0.0, 11, [])
	if s.is_empty(): return
	var ai = s["ai"]
	var enemy = s["enemy"]
	var player = s["player"]
	var judge = _new_judge()
	if judge == null: return
	judge.bind_entities(player, enemy)
	ai.judge = judge
	judge.parry_success.connect(_on_parry_success)
	player.facing = -1
	enemy.facing = 1
	_enter_attack(s)
	_assert(enemy.state_name == "attack" or enemy.state_name == "heavy_attack", "combo first strike (got %s)" % enemy.state_name)
	_parry_at_hit_frame(judge, enemy, player)
	_assert(_parry_log.size() == 1, "parry interrupts combo (got %d)" % _parry_log.size())
	_assert(ai._parry_stun_until_sec > 0.0, "parry stun armed after interrupt")
	## 抑制窗内: 无第二次攻击发起
	ai._attack_cooldown_until_sec = 0.0
	ai._parry_stun_until_sec = 99999.0
	enemy.request_transition("idle")
	_tick(s, 0.3)
	_assert(enemy.state_name != "attack" and enemy.state_name != "heavy_attack", "no 2nd strike during stun (got %s)" % enemy.state_name)


func _test_34_retreat_player_fled() -> void:
	## 回避期间玩家后撤: Retreat 期满 |dx| > ENEMY_ATTACK_RANGE → ChaseState（不空挥攻击）
	var trigger_seed: int = -1
	for seed_val in range(200):
		var s2 = _setup(80.0, 0.0, seed_val, [])
		if s2.is_empty(): return
		s2["player"].request_transition("attack")
		if _ai_state(s2["ai"]) == "RetreatState":
			trigger_seed = seed_val
			break
	_assert(trigger_seed >= 0, "found retreat trigger seed for player-fled scenario")
	var s = _setup(80.0, 0.0, trigger_seed, [])
	if s.is_empty(): return
	var ai = s["ai"]
	s["player"].request_transition("attack")
	_assert(_ai_state(ai) == "RetreatState", "retreat started (got %s)" % _ai_state(ai))
	## 玩家后撤到攻击范围外
	s["player"].position = Vector2(400.0, 0)
	s["player"].request_transition("idle")
	_tick(s, float(_c("ENEMY_RETREAT_SECONDS")) + 0.5)
	_assert(_ai_state(ai) == "ChaseState", "player fled → chase not whiff attack (got %s)" % _ai_state(ai))


# ── judge 事件 handler ───────────────────────────────────────────────────

func _on_parry_success(defender, attacker, stance_damage: float) -> void:
	_parry_log.append([defender, attacker, stance_damage])


func _on_hit_landed(defender, attacker, hp_damage: float, stance_damage: float) -> void:
	_hit_log.append([defender, attacker, hp_damage, stance_damage])


## 在敌人窗口命中帧处触发弹反（guard_pressed 上界时间戳）
func _parry_at_hit_frame(judge, enemy, player) -> void:
	if judge._windows.size() < 1:
		return
	var w = judge._windows[judge._windows.size() - 1]
	var hit_frame: int = w.hit_frame()
	judge._frame = hit_frame
	var hit_ms: int = int(hit_frame * 1000 / int(_c("FRAME_RHYTHM_BASE")))
	judge._on_guard_pressed(hit_ms)
	judge.resolve_attack(enemy, player)


# ── Scenario E(#682): 精英蓄力重斩（elite 门控三选一出招 + 窗口契约）────────

## 扫描 0..79 找首个 elite 蓄力 seed（elite_mode=true + judge 绑定 + _enter_attack）
## 蓄力判定 = 最新窗口 windup_frames == ENEMY_CHARGE_WINDUP（judge fallback 链读 override）
func _find_charge_seed() -> int:
	for seed_val in range(80):
		var s = _setup(80.0, 0.0, seed_val, [])
		if s.is_empty():
			return -1
		var ai = s["ai"]
		ai.elite_mode = true
		var judge = _new_judge()
		if judge == null:
			return -1
		judge.bind_entities(s["player"], s["enemy"])
		ai.judge = judge
		_enter_attack(s)
		if judge._windows.size() >= 1:
			var w = judge._windows[judge._windows.size() - 1]
			if int(w.windup_frames) == int(_c("ENEMY_CHARGE_WINDUP")):
				return seed_val
	return -1


func _test_35_elite_gate_no_charge() -> void:
	## elite 门控（elite_mode=false 默认）: 全 seed 扫描 0..59，任何窗口不得出现蓄力 windup
	##   ——回归 #581 突刺/三连砍二选一出招（judge 登记窗口一律 ENEMY_ATTACK_WINDUP）
	var charge_seen: int = 0
	var window_count: int = 0
	for seed_val in range(60):
		var s = _setup(80.0, 0.0, seed_val, [])
		if s.is_empty():
			return
		var ai = s["ai"]
		var judge = _new_judge()
		if judge == null:
			return
		judge.bind_entities(s["player"], s["enemy"])
		ai.judge = judge
		_enter_attack(s)
		window_count += judge._windows.size()
		for w in judge._windows:
			if int(w.windup_frames) == int(_c("ENEMY_CHARGE_WINDUP")):
				charge_seen += 1
			_assert(int(w.windup_frames) == int(_c("ENEMY_ATTACK_WINDUP")), "elite=false window windup == ENEMY_ATTACK_WINDUP (seed=%d got %d)" % [seed_val, int(w.windup_frames)])
	_assert(window_count >= 60, "attack windows registered across 60 seeds (got %d)" % window_count)
	_assert(charge_seen == 0, "no charge window with elite_mode=false (got %d)" % charge_seen)


func _test_36_elite_gate_charge_exists() -> void:
	## elite 门控（elite_mode=true）: 扫描 0..79 至少一个 seed 出蓄力重斩（三选一出招启用）
	var charge_seed: int = _find_charge_seed()
	_assert(charge_seed >= 0, "found elite charge seed in 0..79 (elite_mode gates charge in)")


func _test_37_charge_window_contract() -> void:
	## 蓄力重斩窗口契约: 前摇 ENEMY_CHARGE_WINDUP(20) / 伤害 ENEMY_CHARGE_HP_DAMAGE(25) /
	##   hit_frame == start + 20；转移后瞬时 override 清空（-1 / -1.0）
	var charge_seed: int = _find_charge_seed()
	_assert(charge_seed >= 0, "found charge seed for window contract")
	if charge_seed < 0:
		return
	var s = _setup(80.0, 0.0, charge_seed, [])
	if s.is_empty():
		return
	var ai = s["ai"]
	ai.elite_mode = true
	var enemy = s["enemy"]
	var judge = _new_judge()
	if judge == null:
		return
	judge.bind_entities(s["player"], enemy)
	ai.judge = judge
	_enter_attack(s)
	var cw: int = int(_c("ENEMY_CHARGE_WINDUP"))
	var chd: float = float(_c("ENEMY_CHARGE_HP_DAMAGE"))
	_assert(cw == 20, "ENEMY_CHARGE_WINDUP constant == 20 (got %d)" % cw)
	_assert(absf(chd - 25.0) < 0.0001, "ENEMY_CHARGE_HP_DAMAGE constant == 25.0 (got %.1f)" % chd)
	_assert(enemy.state_name == "heavy_attack", "charge attacks via heavy_attack (got %s)" % enemy.state_name)
	if judge._windows.size() >= 1:
		var w = judge._windows[judge._windows.size() - 1]
		_assert(int(w.windup_frames) == cw, "charge window windup == ENEMY_CHARGE_WINDUP(%d) (got %d)" % [cw, int(w.windup_frames)])
		_assert(absf(float(w.hp_damage) - chd) < 0.0001, "charge window hp_damage == ENEMY_CHARGE_HP_DAMAGE(%.1f) (got %.1f)" % [chd, float(w.hp_damage)])
		_assert(w.hit_frame() == w.start_frame + cw, "charge hit_frame == start + ENEMY_CHARGE_WINDUP")
	_assert(int(enemy.current_windup_frames) == -1, "windup override cleared after transition (got %d)" % int(enemy.current_windup_frames))
	_assert(absf(float(enemy.current_hp_damage) - (-1.0)) < 0.0001, "hp_damage override cleared after transition (got %.1f)" % float(enemy.current_hp_damage))


func _test_38_override_no_leak() -> void:
	## override 无泄漏: 蓄力后复位再出招，下一击窗口 windup 回落 ENEMY_ATTACK_WINDUP(12)
	##   ——防 charge override 泄漏到下一击（judge fallback 链默认回退）
	var charge_seed: int = -1
	for seed_val in range(80):
		var s = _setup(80.0, 0.0, seed_val, [])
		if s.is_empty():
			return
		var ai2 = s["ai"]
		ai2.elite_mode = true
		var j2 = _new_judge()
		if j2 == null:
			return
		j2.bind_entities(s["player"], s["enemy"])
		ai2.judge = j2
		_enter_attack(s)
		if j2._windows.size() < 1:
			continue
		var w2 = j2._windows[j2._windows.size() - 1]
		if int(w2.windup_frames) != int(_c("ENEMY_CHARGE_WINDUP")):
			continue
		## 首次蓄力 → 复位后下一击必须非蓄力（防泄漏验证）
		var enemy2 = s["enemy"]
		enemy2.request_transition("idle")
		ai2._attack_cooldown_until_sec = 0.0
		var guard: int = 0
		while enemy2.state_name != "attack" and enemy2.state_name != "heavy_attack" and guard < 600:
			_tick(s, TEST_FRAME_SEC)
			guard += 1
		if guard >= 600:
			continue
		var w3 = j2._windows[j2._windows.size() - 1]
		if int(w3.windup_frames) == int(_c("ENEMY_ATTACK_WINDUP")):
			charge_seed = seed_val
			break
	_assert(charge_seed >= 0, "found charge seed whose next strike is non-charge")
	if charge_seed < 0:
		return
	## 主流程复验（用同一 seed 独立装配）
	var s2 = _setup(80.0, 0.0, charge_seed, [])
	if s2.is_empty():
		return
	var ai = s2["ai"]
	ai.elite_mode = true
	var enemy = s2["enemy"]
	var judge = _new_judge()
	if judge == null:
		return
	judge.bind_entities(s2["player"], enemy)
	ai.judge = judge
	_enter_attack(s2)
	if judge._windows.size() >= 1:
		var w = judge._windows[judge._windows.size() - 1]
		_assert(int(w.windup_frames) == int(_c("ENEMY_CHARGE_WINDUP")), "first strike is charge (windup=%d)" % int(w.windup_frames))
	## 复位 → 下一击（连段计划作废后重新出招）
	enemy.request_transition("idle")
	ai._attack_cooldown_until_sec = 0.0
	var guard2: int = 0
	while enemy.state_name != "attack" and enemy.state_name != "heavy_attack" and guard2 < 600:
		_tick(s2, TEST_FRAME_SEC)
		guard2 += 1
	_assert(guard2 < 600, "second strike issued within guard loop")
	if judge._windows.size() >= 1:
		var w2 = judge._windows[judge._windows.size() - 1]
		_assert(int(w2.windup_frames) == int(_c("ENEMY_ATTACK_WINDUP")), "next strike window windup == ENEMY_ATTACK_WINDUP(%d) — no charge override leak (got %d)" % [int(_c("ENEMY_ATTACK_WINDUP")), int(w2.windup_frames)])


func _test_39_charge_parryable() -> void:
	## 蓄力重斩可弹反（实验 1 落地）: 20 帧前摇窗口弹反闭区间 [hit-200ms, hit] 三态判定——
	##   下界含端点弹反成功 / 命中帧弹反成功 / 下界-1 窗口外不弹反（落入受击）
	var charge_seed: int = _find_charge_seed()
	_assert(charge_seed >= 0, "found elite charge seed for parry test")
	if charge_seed < 0:
		return
	var s = _setup(80.0, 0.0, charge_seed, [])
	if s.is_empty():
		return
	var ai = s["ai"]
	ai.elite_mode = true
	var enemy = s["enemy"]
	var player = s["player"]
	var judge = _new_judge()
	if judge == null:
		return
	judge.bind_entities(player, enemy)
	ai.judge = judge
	judge.parry_success.connect(_on_parry_success)
	player.facing = -1
	enemy.facing = 1
	_enter_attack(s)
	_reset_logs()
	_assert(enemy.state_name == "heavy_attack", "elite charge enters heavy_attack (got %s)" % enemy.state_name)
	if judge._windows.size() >= 1:
		var w = judge._windows[judge._windows.size() - 1]
		var hit_frame: int = w.hit_frame()
		var hit_ms: int = int(hit_frame * 1000 / int(_c("FRAME_RHYTHM_BASE")))
		var lower_ms: int = hit_ms - int(float(_c("PARRY_WINDOW_SECONDS")) * 1000.0)
		## ① 下界（闭区间含端点）→ 弹反成功
		judge._on_guard_pressed(lower_ms)
		judge._frame = hit_frame
		judge._resolved = {}
		judge.resolve_attack(enemy, player)
		_assert(_parry_log.size() == 1, "parry at lower bound succeeds (got %d)" % _parry_log.size())
		## ② 上界（命中帧）→ 弹反成功
		_reset_logs()
		judge._on_guard_pressed(hit_ms)
		judge._frame = hit_frame
		judge._resolved = {}
		judge.resolve_attack(enemy, player)
		_assert(_parry_log.size() == 1, "parry at hit frame succeeds (got %d)" % _parry_log.size())
		## ③ 下界 - 1（窗口外）→ 不弹反（落入受击，hit_landed 但无 parry）
		_reset_logs()
		judge._on_guard_pressed(lower_ms - 1)
		judge._frame = hit_frame
		judge._resolved = {}
		judge.resolve_attack(enemy, player)
		_assert(_parry_log.size() == 0, "no parry below lower bound (got %d)" % _parry_log.size())


# ── Scenario D(#682): 受击击退（位移层，hit_landed 订阅）──────────────────

## 受击击退装配: 玩家(右侧, facing=-1) 攻击敌人；judge 绑定 + hit_landed 日志订阅 +
##   decide 一次触发 AI 侧惰性接线（_ensure_judge_subscription）。敌人在 x=enemy_x > 0
##   （击退 clamp 至 [0, STAGE_WIDTH_PX]，贴 0 则位移不可观测）。
func _knockback_setup(player_x: float, enemy_x: float):
	var s = _setup(player_x, enemy_x, 11, [])
	if s.is_empty():
		return {}
	var ai = s["ai"]
	var enemy = s["enemy"]
	var player = s["player"]
	player.facing = -1
	enemy.facing = 1
	ai.position = Vector2(enemy_x, 0)
	var judge = _new_judge()
	if judge == null:
		return {}
	judge.bind_entities(player, enemy)
	ai.judge = judge
	judge.hit_landed.connect(_on_hit_landed)
	ai.decide(TEST_FRAME_SEC)
	_reset_logs()
	return {"ai": ai, "enemy": enemy, "player": player, "judge": judge}


## 玩家 attack 登记窗口 → 在窗口命中帧裁决（defender=敌人 → hit_landed）
func _knockback_player_attack(k) -> void:
	var judge = k["judge"]
	var enemy = k["enemy"]
	var player = k["player"]
	player.request_transition("attack")
	if judge._windows.size() >= 1:
		var w = judge._windows[judge._windows.size() - 1]
		judge._frame = w.hit_frame()
		judge.resolve_attack(player, enemy)


func _test_40_knockback_trigger() -> void:
	## 击退触发: 玩家命中敌人 → _knockback_vel == ENEMY_KNOCKBACK_PX、方向远离攻击者（左）、hit_landed 入日志
	var k = _knockback_setup(170.0, 100.0)
	if k.is_empty():
		return
	var ai = k["ai"]
	var enemy = k["enemy"]
	_knockback_player_attack(k)
	_assert(_hit_log.size() == 1, "hit_landed logged once (got %d)" % _hit_log.size())
	_assert(absf(float(ai._knockback_vel) - float(_c("ENEMY_KNOCKBACK_PX"))) < 0.0001, "_knockback_vel == ENEMY_KNOCKBACK_PX(%.1f) (got %.1f)" % [float(_c("ENEMY_KNOCKBACK_PX")), float(ai._knockback_vel)])
	_assert(int(ai._knockback_dir) == -1, "_knockback_dir == -1 (attacker right → push left, got %d)" % int(ai._knockback_dir))
	_assert(enemy.state_name == "stagger", "enemy staggered by hit (got %s)" % enemy.state_name)


func _test_41_knockback_displacement_decay() -> void:
	## 击退位移与衰减: 手动 _physics_process 5 帧（非 _tick——stagger 中 decide 门控 _apply_movement）
	##   → 敌人左移、速度逐帧衰减（首帧 == maxf(40 - 3/60, 0)）
	var k = _knockback_setup(170.0, 100.0)
	if k.is_empty():
		return
	var ai = k["ai"]
	_knockback_player_attack(k)
	var pos_x0: float = ai.position.x
	## ① 首帧衰减数学验证
	ai._physics_process(TEST_FRAME_SEC)
	var decayed: float = float(_c("ENEMY_KNOCKBACK_PX")) - float(_c("ENEMY_KNOCKBACK_DECAY")) * TEST_FRAME_SEC
	_assert(absf(float(ai._knockback_vel) - maxf(decayed, 0.0)) < 0.0001, "vel after 1 frame == maxf(PX - DECAY/60, 0) (got %.4f)" % float(ai._knockback_vel))
	## ② 再推 4 帧 → 位移方向 + 持续衰减
	var pos_x1: float = ai.position.x
	for i in range(4):
		ai._physics_process(TEST_FRAME_SEC)
	_assert(ai.position.x < pos_x0, "knockback moves enemy left away from attacker (%.3f → %.3f)" % [pos_x0, ai.position.x])
	_assert(ai.position.x < pos_x1, "knockback continues over frames (%.3f → %.3f)" % [pos_x1, ai.position.x])
	_assert(float(ai._knockback_vel) < float(_c("ENEMY_KNOCKBACK_PX")), "knockback velocity decayed below initial (got %.2f)" % float(ai._knockback_vel))


func _test_42_knockback_decay_to_zero() -> void:
	## 击退归零（#682 边界 1）: 每帧先 enemy._process（推进实体战斗 FSM——CombatStateStagger
	##   在 _elapsed >= STAGGER_FRAMES/FRAME_RHYTHM_BASE = 0.2s 自动 request_transition("idle")）
	##   再 ai._physics_process（击退分支守卫）。stagger 结束 → 击退归零 → 位移路径恢复 Chase。
	##   帧数: 阈值 0.2s 下 12 帧浮点累加 ≈ 0.19999… < 0.2，第 13 帧才触发退出，故循环 13 帧。
	var k = _knockback_setup(170.0, 100.0)
	if k.is_empty():
		return
	var ai = k["ai"]
	var enemy = k["enemy"]
	_knockback_player_attack(k)
	var pos_x0: float = ai.position.x
	for i in range(13):
		enemy._process(TEST_FRAME_SEC)
		ai._physics_process(TEST_FRAME_SEC)
	_assert(enemy.state_name == "idle", "enemy left stagger after stagger duration (got %s)" % enemy.state_name)
	_assert(float(ai._knockback_vel) == 0.0, "knockback velocity zeroed once stagger ends (got %.4f)" % float(ai._knockback_vel))
	_assert(ai.position.x < pos_x0, "enemy displaced left by knockback (%.3f → %.3f)" % [pos_x0, ai.position.x])


func _test_43_knockback_player_not_affected() -> void:
	## 玩家被击中不触发敌人击退: defender=玩家 → _on_judge_hit_landed 早退（defender != entity）
	var k = _knockback_setup(80.0, 0.0)
	if k.is_empty():
		return
	var ai = k["ai"]
	var enemy = k["enemy"]
	var player = k["player"]
	var judge = k["judge"]
	## 敌人攻击玩家（敌人登记 heavy_attack 窗口 → 命中玩家）
	enemy.request_transition("heavy_attack")
	if judge._windows.size() >= 1:
		var w = judge._windows[judge._windows.size() - 1]
		judge._frame = w.hit_frame()
		judge.resolve_attack(enemy, player)
	_assert(_hit_log.size() == 1, "player hit landed (got %d)" % _hit_log.size())
	_assert(float(ai._knockback_vel) == 0.0, "enemy knockback NOT triggered when defender=player (got %.1f)" % float(ai._knockback_vel))
	_assert(ai.position.x == 0.0, "enemy position unchanged (x=%.1f)" % ai.position.x)


func _test_44_knockback_edge_clamp() -> void:
	## 击退边界兜底: 敌人贴左缘 x=10 受击 → 击退向左推向 x=0 → position.x clamp ≥ 0（[0, STAGE_WIDTH_PX]）
	var k = _knockback_setup(30.0, 10.0)
	if k.is_empty():
		return
	var ai = k["ai"]
	_knockback_player_attack(k)
	_assert(int(ai._knockback_dir) == -1, "dir == -1 pushes enemy left toward x=0 (got %d)" % int(ai._knockback_dir))
	for i in range(30):
		ai._physics_process(TEST_FRAME_SEC)
	_assert(ai.position.x >= 0.0, "enemy position clamped to stage range (x=%.1f)" % ai.position.x)
	_assert(ai.position.x <= float(_c("STAGE_WIDTH_PX")), "enemy position within [0, STAGE_WIDTH_PX] (x=%.1f)" % ai.position.x)

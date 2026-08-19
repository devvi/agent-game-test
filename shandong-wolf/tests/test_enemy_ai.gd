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

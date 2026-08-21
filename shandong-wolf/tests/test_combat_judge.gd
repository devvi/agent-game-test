extends Object
## Test suite for CombatJudge 判定层 + AttackWindow 窗口描述器 (#577).
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/577-parry-clash-stance-break.md §8 (Scenario A-E, 25 test cases)
##
## TDD red phase: combat_judge.gd / combat_attack_window.gd do NOT exist yet
## → runtime load() returns null → _assert(false) (red) instead of whole-file parse error.
##
## Godot 4.7.1 --script 硬性约束 (同 test_combat_entity.gd):
##   - 禁止 := 类型推断 (4.7.1 视推断警告为硬错误) — 一律显式类型或普通 =
##   - class_name 一律经 load() 脚本资源访问，禁止按标识符引用
##   - 纯数据断言免树直接 new + 手动 tick/resolve，不依赖真实帧/物理/Input
##
## 帧/时间约定 (与实现对齐): hit_frame = start_frame + FRAME_ATTACK_WINDUP(=8);
##   hit_ms = hit_frame * 1000 / FRAME_RHYTHM_BASE(=60)。TEST_START_FRAME=52 → hit 帧 60 → hit_ms=1000，
##   PARRY_WINDOW_SECONDS=0.2 → 弹反窗闭区间 [800, 1000]。

## 通用攻击窗口起始帧（hit 帧 60 → hit_ms 1000，命中判定时点全部落在整数毫秒）
const TEST_START_FRAME: int = 52

var passed: int = 0
var failed: int = 0

## 判定器五结果事件日志（handler 写成员变量，用例间 _reset_logs() 隔离）
var _parry_log: Array = []
var _block_log: Array = []
var _hit_log: Array = []
var _clash_log: Array = []
var _broken_log: Array = []


func run() -> void:
	print("\n=== CombatJudge Tests ===")
	_reset_logs()
	_test_1_parry_window_lower_bound()
	_reset_logs()
	_test_2_parry_window_upper_bound()
	_reset_logs()
	_test_3_parry_1ms_late_fails()
	_reset_logs()
	_test_4_parry_201ms_early_fails()
	_reset_logs()
	_test_5_parry_same_frame_last_press_wins()
	_reset_logs()
	_test_6_clash_both_windows()
	_reset_logs()
	_test_7_conflict_matrix()
	_reset_logs()
	_test_8_clash_priority_constant_driven()
	_reset_logs()
	_test_9_no_clash_window_expired()
	_reset_logs()
	_test_10_block()
	_reset_logs()
	_test_11_parry_fail_to_block_no_double_punish()
	_reset_logs()
	_test_12_hit_landed()
	_reset_logs()
	_test_13_range_whiff()
	_reset_logs()
	_test_14_facing_check()
	_reset_logs()
	_test_15_stance_broken_forward()
	_reset_logs()
	_test_16_stance_broken_forward_idempotent()
	_reset_logs()
	_test_17_vertical_airhit_misses()
	_test_17_event_signature_contract()
	_reset_logs()
	_test_18_reentry_noop()
	_reset_logs()
	_test_19_unregistered_window_noop()
	_reset_logs()
	_test_20_invincible_noop()
	_reset_logs()
	_test_21_dead_defender_noop()
	_reset_logs()
	_test_22_unbound_judge_noop()
	_reset_logs()
	_test_23_window_overwrite()
	_reset_logs()
	_test_24_constants_driven()
	_reset_logs()
	_test_25_stagger_consecutive_hit_break()
	## Test 25 (stagger 中连续受击崩解, #718): godot --path shandong-wolf/ --headless --script tests/run_tests.gd
	##   8 套件全绿（含既有 7 套件防回归）。本文件 headless 单跑验证 CombatJudge 层；
	##   完整回归 + CLASH_PRIORITY=1 翻转验证（Test 8）在 CI 全量跑中覆盖。
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _reset_logs() -> void:
	_parry_log = []
	_block_log = []
	_hit_log = []
	_clash_log = []
	_broken_log = []


# ── helpers ─────────────────────────────────────────────────────────────

func _const_map() -> Dictionary:
	var script = load("res://gdscripts/constants.gd")
	if script == null:
		return {}
	return script.get_script_constant_map()


func _c(name: String) -> Variant:
	return _const_map().get(name, -1)


func _hit_frame(start_frame: int) -> int:
	return start_frame + int(_c("FRAME_ATTACK_WINDUP"))


func _hit_ms(start_frame: int) -> int:
	var base: int = maxi(int(_c("FRAME_RHYTHM_BASE")), 1)
	return int(_hit_frame(start_frame) * 1000 / base)


func _parry_lower_ms() -> int:
	var pws: float = float(_c("PARRY_WINDOW_SECONDS"))
	return _hit_ms(TEST_START_FRAME) - int(roundf(pws * 1000.0))


func _new_judge():
	var s = load("res://gdscripts/combat_judge.gd")
	if s == null:
		_assert(false, "combat_judge.gd missing (TDD red phase)")
		return null
	var j = s.new()
	if j == null:
		_assert(false, "combat_judge.gd failed to instantiate")
	return j


func _new_entity(params: Dictionary):
	var s = load("res://gdscripts/combat_entity.gd")
	if s == null:
		_assert(false, "combat_entity.gd missing (TDD red phase)")
		return null
	var e = s.new(params)
	if e == null:
		_assert(false, "combat_entity.gd failed to instantiate")
	return e


func _new_window(attacker, start_frame: int, hp: float, stance: float, direction: int):
	var s = load("res://gdscripts/combat_attack_window.gd")
	if s == null:
		_assert(false, "combat_attack_window.gd missing (TDD red phase)")
		return null
	var w = s.new()
	if w == null:
		_assert(false, "combat_attack_window.gd failed to instantiate")
		return null
	w.attacker = attacker
	w.start_frame = start_frame
	w.active_frames = 4  # HITBOX_ACTIVE_FRAMES # DRAFT
	w.hp_damage = hp
	w.stance_damage = stance
	w.direction = direction
	return w


func _mk_player():
	var p = _new_entity({is_player=true})
	if p == null:
		return null
	p.position = Vector2(50, 0)  # 攻击者(enemy)在 x=0，玩家在 x=50（|dx|=50 ≤ HITBOX_RANGE=80）
	p.facing = -1               # 面向攻击者（PARRY_DIRECTION_TOLERANCE=1）
	return p


func _mk_enemy():
	var e = _new_entity({is_player=false, life_total=1, life_1_max=40.0, stance_max=50.0})
	if e == null:
		return null
	e.position = Vector2(0, 0)
	e.facing = 1
	return e


func _connect_judge(j) -> void:
	j.parry_success.connect(_on_parry_success)
	j.block_held.connect(_on_block_held)
	j.hit_landed.connect(_on_hit_landed)
	j.clash.connect(_on_clash)
	j.stance_broken.connect(_on_stance_broken)


func _setup() -> Dictionary:
	## 新鲜判定器 + 双方实体，position/facing 摆位完成，judge 逻辑帧推进到 hit 帧，五事件已接线
	var player = _mk_player()
	var enemy = _mk_enemy()
	if player == null or enemy == null:
		return {}
	var j = _new_judge()
	if j == null:
		return {}
	j.bind_entities(player, enemy)
	j._frame = _hit_frame(TEST_START_FRAME)
	_connect_judge(j)
	return {"j": j, "player": player, "enemy": enemy}


## 五事件 handler（实体引用未类型化、数值 float，与 §2.3 契约一致）
func _on_parry_success(defender, attacker, stance_damage: float) -> void:
	_parry_log.append([defender, attacker, stance_damage])


func _on_block_held(defender, attacker, stance_cost: float) -> void:
	_block_log.append([defender, attacker, stance_cost])


func _on_hit_landed(defender, attacker, hp_damage: float, stance_damage: float) -> void:
	_hit_log.append([defender, attacker, hp_damage, stance_damage])


func _on_clash(entity_a, entity_b, stance_cost: float) -> void:
	_clash_log.append([entity_a, entity_b, stance_cost])


func _on_stance_broken(entity) -> void:
	_broken_log.append([entity])


# ── Scenario A: 弹反成功路径 (AC1 + PRD 实验 1) ─────────────────────────

func _test_1_parry_window_lower_bound() -> void:
	## 弹反窗闭区间下界 (hit_ms - 0.2s = 800ms) 按下 → 成功: 玩家 0 伤害 + 敌架势 PARRY_STANCE_DAMAGE
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var pd: float = float(_c("PARRY_STANCE_DAMAGE"))
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_parry_lower_ms())
	j.resolve_attack(enemy, player)
	_assert(_parry_log.size() == 1, "parry_success emitted exactly once (got %d)" % _parry_log.size())
	if _parry_log.size() == 1:
		_assert(_parry_log[0][0] == player and _parry_log[0][1] == enemy, "parry_success(defender=player, attacker=enemy)")
		_assert(float(_parry_log[0][2]) == pd, "parry stance_damage == PARRY_STANCE_DAMAGE")
	_assert(player.hp_1 == 100.0, "parry: player takes 0 damage (hp unchanged)")
	_assert(absf(enemy.stance - (50.0 - pd)) < 0.0001, "parry: enemy stance reduced by PARRY_STANCE_DAMAGE (got %.2f)" % enemy.stance)
	_assert(player.state_name == "parry_success", "player transitions to parry_success (got %s)" % player.state_name)


func _test_2_parry_window_upper_bound() -> void:
	## 弹反窗闭区间上界 (hit_ms = 1000ms) 按下 → 成功（含端点）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_hit_ms(TEST_START_FRAME))
	j.resolve_attack(enemy, player)
	_assert(_parry_log.size() == 1, "guard_pressed at hit_ms (upper bound) → parry_success (got %d)" % _parry_log.size())
	_assert(_hit_log.is_empty(), "upper-bound parry does not land a hit")
	_assert(player.hp_1 == 100.0, "upper-bound parry: 0 damage")


func _test_3_parry_1ms_late_fails() -> void:
	## 窗外 +1ms (1001ms) → 不弹反 → 走后续裁决（未格挡 → 受击）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_hit_ms(TEST_START_FRAME) + 1)
	j.resolve_attack(enemy, player)
	_assert(_parry_log.is_empty(), "+1ms late press does NOT parry")
	_assert(_hit_log.size() == 1, "late parry → subsequent resolution hits (got %d)" % _hit_log.size())


func _test_4_parry_201ms_early_fails() -> void:
	## 窗外 -201ms (799ms) → 不弹反 → 走后续裁决
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_parry_lower_ms() - 1)
	j.resolve_attack(enemy, player)
	_assert(_parry_log.is_empty(), "201ms-early press does NOT parry")
	_assert(_hit_log.size() == 1, "early parry → subsequent resolution hits (got %d)" % _hit_log.size())


func _test_5_parry_same_frame_last_press_wins() -> void:
	## 同帧两次 guard_pressed，第二次在窗口内 → 帧级去抖取最后一次 → 弹反成功
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_parry_lower_ms() - 100)  # 700ms，窗口外
	j._on_guard_pressed(_parry_lower_ms())        # 800ms，窗口内（最后一次按下）
	j.resolve_attack(enemy, player)
	_assert(_parry_log.size() == 1, "last press wins (frame-level debounce) → parry_success (got %d)" % _parry_log.size())
	_assert(_hit_log.is_empty(), "no hit when last press is in parry window")


# ── Scenario B: 拼刀路径 (AC2 + PRD 实验 2 冲突矩阵) ────────────────────

func _test_6_clash_both_windows() -> void:
	## 双方窗口同帧 active，无 guard_pressed → 双方各扣 CLASH_STANCE_COST + clash 恰好一次
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var cs: float = float(_c("CLASH_STANCE_COST"))
	var we = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	var wp = _new_window(player, TEST_START_FRAME, 12.0, 35.0, 1)
	if we == null or wp == null: return
	j.register_attack_window(we)
	j.register_attack_window(wp)
	j.resolve_attack(enemy, player)
	_assert(_clash_log.size() == 1, "clash emitted exactly once (got %d)" % _clash_log.size())
	if _clash_log.size() == 1:
		var has_both: bool = (_clash_log[0][0] == player and _clash_log[0][1] == enemy) or (_clash_log[0][0] == enemy and _clash_log[0][1] == player)
		_assert(has_both, "clash(entity_a, entity_b) carries both entities")
		_assert(float(_clash_log[0][2]) == cs, "clash stance_cost == CLASH_STANCE_COST")
	_assert(absf(player.stance - (100.0 - cs)) < 0.0001, "clash: player stance reduced by CLASH_STANCE_COST")
	_assert(absf(enemy.stance - (50.0 - cs)) < 0.0001, "clash: enemy stance reduced by CLASH_STANCE_COST")
	_assert(_parry_log.is_empty() and _block_log.is_empty() and _hit_log.is_empty(), "clash: no other result events")


func _test_7_conflict_matrix() -> void:
	## 冲突矩阵 4 组合（CLASH_PRIORITY==0 弹反优先短路）——每种组合恰好一个结果事件
	# ① 弹反+拼刀（三重叠）→ parry_success
	var s1 = _setup()
	if s1.is_empty(): return
	var j1 = s1["j"]
	var p1 = s1["player"]
	var e1 = s1["enemy"]
	var w1e = _new_window(e1, TEST_START_FRAME, 15.0, 35.0, 1)
	var w1p = _new_window(p1, TEST_START_FRAME, 12.0, 35.0, 1)
	if w1e == null or w1p == null: return
	j1.register_attack_window(w1e)
	j1.register_attack_window(w1p)
	j1._on_guard_pressed(_parry_lower_ms())
	j1.resolve_attack(e1, p1)
	_assert(_parry_log.size() == 1, "parry+clash overlap → parry_success wins (got %d)" % _parry_log.size())
	_assert(_clash_log.is_empty(), "parry+clash overlap → no clash emitted")

	# ② 拼刀+格挡 → clash（拼刀优先于格挡）
	_reset_logs()
	var s2 = _setup()
	if s2.is_empty(): return
	var j2 = s2["j"]
	var p2 = s2["player"]
	var e2 = s2["enemy"]
	var w2e = _new_window(e2, TEST_START_FRAME, 15.0, 35.0, 1)
	var w2p = _new_window(p2, TEST_START_FRAME, 12.0, 35.0, 1)
	if w2e == null or w2p == null: return
	j2.register_attack_window(w2e)
	j2.register_attack_window(w2p)
	p2.request_transition("guard")
	j2.resolve_attack(e2, p2)
	_assert(_clash_log.size() == 1, "clash+block overlap → clash wins (got %d)" % _clash_log.size())
	_assert(_block_log.is_empty(), "clash+block overlap → no block_held emitted")

	# ③ 弹反+格挡 → parry_success
	_reset_logs()
	var s3 = _setup()
	if s3.is_empty(): return
	var j3 = s3["j"]
	var p3 = s3["player"]
	var e3 = s3["enemy"]
	var w3e = _new_window(e3, TEST_START_FRAME, 15.0, 35.0, 1)
	if w3e == null: return
	j3.register_attack_window(w3e)
	p3.request_transition("guard")
	j3._on_guard_pressed(_parry_lower_ms())
	j3.resolve_attack(e3, p3)
	_assert(_parry_log.size() == 1, "parry+block overlap → parry_success wins (got %d)" % _parry_log.size())
	_assert(_block_log.is_empty(), "parry+block overlap → no block_held emitted")

	# ④ 三重叠（弹反+拼刀+格挡）→ parry_success
	_reset_logs()
	var s4 = _setup()
	if s4.is_empty(): return
	var j4 = s4["j"]
	var p4 = s4["player"]
	var e4 = s4["enemy"]
	var w4e = _new_window(e4, TEST_START_FRAME, 15.0, 35.0, 1)
	var w4p = _new_window(p4, TEST_START_FRAME, 12.0, 35.0, 1)
	if w4e == null or w4p == null: return
	j4.register_attack_window(w4e)
	j4.register_attack_window(w4p)
	p4.request_transition("guard")
	j4._on_guard_pressed(_parry_lower_ms())
	j4.resolve_attack(e4, p4)
	_assert(_parry_log.size() == 1, "three-way overlap → parry_success (highest priority) (got %d)" % _parry_log.size())
	_assert(_clash_log.is_empty() and _block_log.is_empty() and _hit_log.is_empty(), "three-way overlap → exactly one result event")


func _test_8_clash_priority_constant_driven() -> void:
	## 裁决优先级必须走 CLASH_PRIORITY 常量（红线）。
	## GDScript const 编译期定值，运行时无法翻转常量 → 不可 headless 运行时改 CLASH_PRIORITY。
	## 可行断言: 读取 constants 映射当前值 → 断言裁决结果与常量值驱动的期望一致；
	##   翻转验证（CLASH_PRIORITY=1 → clash）需临时编辑 constants.gd 后跑全量回归（Test 25/CI）。
	var cp: int = int(_c("CLASH_PRIORITY"))
	_assert(cp == 0, "CLASH_PRIORITY default == 0 (DRAFT candidate, parry over clash)")
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var we = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	var wp = _new_window(player, TEST_START_FRAME, 12.0, 35.0, 1)
	if we == null or wp == null: return
	j.register_attack_window(we)
	j.register_attack_window(wp)
	j._on_guard_pressed(_parry_lower_ms())
	j.resolve_attack(enemy, player)
	if cp == 0:
		_assert(_parry_log.size() == 1 and _clash_log.is_empty(), "CLASH_PRIORITY==0 → three-way overlap resolves parry_success (priority from constants)")
	else:
		_assert(_clash_log.size() == 1 and _parry_log.is_empty(), "CLASH_PRIORITY==1 → three-way overlap resolves clash (priority from constants)")


func _test_9_no_clash_window_expired() -> void:
	## 玩家窗口已过期（hit 帧 48 active [48,52]，当前帧 60）→ 敌人命中不触发 clash
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var wp = _new_window(player, 40, 12.0, 35.0, 1)  # hit 48 → active [48,52]，帧 60 已过期
	var we = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if wp == null or we == null: return
	j.register_attack_window(wp)
	j.register_attack_window(we)
	j.resolve_attack(enemy, player)
	_assert(_clash_log.is_empty(), "expired player window → no clash")
	_assert(_hit_log.size() == 1, "expired player window → enemy hit resolves normally (got %d)" % _hit_log.size())


# ── Scenario C: 格挡与受击路径 (AC5-3 + 边界) ───────────────────────────

func _test_10_block() -> void:
	## 格挡: guard_pressed 超窗 + 玩家处于 guard 态 → block_held（扣 POSTURE_BLOCK_COST，不扣血）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var bc: float = float(_c("POSTURE_BLOCK_COST"))
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	player.request_transition("guard")
	j._on_guard_pressed(_parry_lower_ms() - 200)  # 600ms，弹反窗外；按住格挡
	j.resolve_attack(enemy, player)
	_assert(_block_log.size() == 1, "block_held emitted exactly once (got %d)" % _block_log.size())
	if _block_log.size() == 1:
		_assert(_block_log[0][0] == player and _block_log[0][1] == enemy, "block_held(defender=player, attacker=enemy)")
		_assert(float(_block_log[0][2]) == bc, "block stance_cost == POSTURE_BLOCK_COST")
	_assert(absf(player.stance - (100.0 - bc)) < 0.0001, "block: player stance reduced by POSTURE_BLOCK_COST (got %.2f)" % player.stance)
	_assert(player.hp_1 == 100.0, "block: no hp damage")
	_assert(_hit_log.is_empty(), "block: no hit_landed")


func _test_11_parry_fail_to_block_no_double_punish() -> void:
	## 弹反超窗 1ms + 玩家按住格挡 → block_held 而非受击（防双罚：恰好一次事件）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	player.request_transition("guard")
	j._on_guard_pressed(_hit_ms(TEST_START_FRAME) + 1)  # 1001ms，窗口外 1ms
	j.resolve_attack(enemy, player)
	_assert(_block_log.size() == 1, "1ms-late parry while guarding → block_held (got %d)" % _block_log.size())
	_assert(_hit_log.is_empty(), "double-punish prevention: no hit_landed after failed parry in guard")


func _test_12_hit_landed() -> void:
	## 未格挡受击: take_damage(hp_damage) + take_stance_damage(POSTURE_HIT_COST) + hit_landed 参数正确
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var hc: float = float(_c("POSTURE_HIT_COST"))
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, hc, 1)
	if w == null: return
	j.register_attack_window(w)
	j.resolve_attack(enemy, player)  # 无 guard_pressed，玩家 idle
	_assert(_hit_log.size() == 1, "hit_landed emitted exactly once (got %d)" % _hit_log.size())
	if _hit_log.size() == 1:
		_assert(_hit_log[0][0] == player and _hit_log[0][1] == enemy, "hit_landed(defender=player, attacker=enemy)")
		_assert(float(_hit_log[0][2]) == 15.0, "hit hp_damage == window.hp_damage")
		_assert(float(_hit_log[0][3]) == hc, "hit stance_damage == POSTURE_HIT_COST")
	_assert(player.hp_1 == 85.0, "hit: player hp reduced by hp_damage (got %.1f)" % player.hp_1)
	_assert(absf(player.stance - (100.0 - hc)) < 0.0001, "hit: player stance reduced by POSTURE_HIT_COST")
	_assert(player.state_name == "stagger", "unblocked hit → stagger")


func _test_13_range_whiff() -> void:
	## 距离挥空: |attacker.x - defender.x| = 200 > HITBOX_RANGE(80) → 不发射 hit_landed（窗口正常过期）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	player.position = Vector2(200, 0)
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j.resolve_attack(enemy, player)
	_assert(_hit_log.is_empty(), "distance whiff → no hit_landed")
	_assert(_parry_log.is_empty() and _block_log.is_empty() and _clash_log.is_empty(), "whiff emits no result events")
	_assert(player.hp_1 == 100.0, "whiff: player hp unchanged")


func _test_17_vertical_airhit_misses() -> void:
	## 空气击毙根除（2026-08-21，用户回归"player 没靠近也能击毙"）:
	##   剑段 ↔ 身体胶囊 物理判定——剑在 hand 高度(y=-44)水平挥出，敌身体竖直胶囊跨
	##   [root-63.5, root+40]。同一水平距离下:
	##   ① dy=+30（敌在玩家正下方 30px）→ 剑高 y=-44 落在敌胶囊跨外 → 挥空（MISS）
	##   ② dy=-30（敌在玩家正上方 30px）→ 剑高在敌胶囊跨内且水平伸程触及 → HIT
	##   ③ dy=0（同高）→ HIT（合法近身命中）
	##   旧版 `absf(dy)<=40` 从 root(髋) 起量：dy=+30 判命中=空气击毙。
	# 用 _setup() 每个 case 拿新鲜 judge（_resolved 防重入键跨 case 不共享），避免短回路。

	# ① 敌在玩家正下方 30px → 剑(hand y=-44)够不到 → MISS
	var s1 = _setup()
	if s1.is_empty(): return
	var j1 = s1["j"]
	var p1 = s1["player"]
	var e1 = s1["enemy"]
	p1.position = Vector2(30, 30)   # 玩家=(30,30) 敌=(0,0) facing=+1 朝右挥
	var w = _new_window(e1, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j1.register_attack_window(w)
	j1._frame = w.hit_frame()
	j1.resolve_attack(e1, p1)
	_assert(_hit_log.is_empty(), "airhit: enemy below (dy=+30) → sword at hand height can't reach → MISS (got %d hits)" % _hit_log.size())
	_assert(p1.hp_1 == 100.0, "airhit: player below-case hp unchanged")

	# ② 敌在玩家正上方（仍在身体胶囊跨内）→ HIT
	var s2 = _setup()
	if s2.is_empty(): return
	var j2 = s2["j"]
	var p2 = s2["player"]
	var e2 = s2["enemy"]
	p2.position = Vector2(30, -30)
	var w2 = _new_window(e2, TEST_START_FRAME, 15.0, 35.0, 1)
	if w2 == null: return
	j2.register_attack_window(w2)
	j2._frame = w2.hit_frame()
	_reset_logs()
	j2.resolve_attack(e2, p2)
	_assert(_hit_log.size() == 1, "vertical overlap: enemy above (dy=-30) within body capsule → HIT (got %d)" % _hit_log.size())

	# ③ 同高 → HIT（合法近身）
	var s3 = _setup()
	if s3.is_empty(): return
	var j3 = s3["j"]
	var p3 = s3["player"]
	var e3 = s3["enemy"]
	p3.position = Vector2(30, 0)
	var w3 = _new_window(e3, TEST_START_FRAME, 15.0, 35.0, 1)
	if w3 == null: return
	j3.register_attack_window(w3)
	j3._frame = w3.hit_frame()
	_reset_logs()
	j3.resolve_attack(e3, p3)
	_assert(_hit_log.size() == 1, "same-height (dy=0) → legitimate HIT (got %d)" % _hit_log.size())


func _test_14_facing_check() -> void:
	## facing 校验: PARRY_DIRECTION_TOLERANCE=1 且 defender 背对攻击 → 弹反失败 → 走受击
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	player.facing = 1  # 玩家在 x=50 面向右（攻击者敌人在 x=0 左侧）→ 背对攻击者
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_parry_lower_ms())
	j.resolve_attack(enemy, player)
	_assert(_parry_log.is_empty(), "back-turned defender cannot parry (PARRY_DIRECTION_TOLERANCE)")
	_assert(_hit_log.size() == 1, "parry fails on facing → hit_landed instead (got %d)" % _hit_log.size())


# ── Scenario D: 架势崩解与事件契约 (AC3 + PRD 实验 3) ───────────────────

func _test_15_stance_broken_forward() -> void:
	## 敌人 stance=5，弹反 PARRY_STANCE_DAMAGE → #575 break_stance → 判定器转发 stance_broken 恰好一次
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	enemy.stance = 5.0
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_parry_lower_ms())
	j.resolve_attack(enemy, player)
	_assert(_broken_log.size() == 1, "stance_broken forwarded exactly once (got %d)" % _broken_log.size())
	if _broken_log.size() == 1:
		_assert(_broken_log[0][0] == enemy, "forwarded stance_broken(entity) carries the broken entity")
	_assert(enemy.state_name == "stance_break", "enemy enters stance_break")
	_assert(enemy.stance == 0.0, "enemy stance clamped to 0")
	_assert(enemy.is_stance_broken == true, "enemy is_stance_broken flag set")


func _test_16_stance_broken_forward_idempotent() -> void:
	## 转发幂等: 同一实体 stance_broken 二次到达 → 不二次转发
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	enemy.stance = 5.0
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j._on_guard_pressed(_parry_lower_ms())
	j.resolve_attack(enemy, player)
	_assert(_broken_log.size() == 1, "first forward exactly once (got %d)" % _broken_log.size())
	j._on_stance_broken(enemy)  # 模拟二次到达
	_assert(_broken_log.size() == 1, "duplicate stance_broken not re-forwarded (idempotent) (got %d)" % _broken_log.size())


func _test_17_event_signature_contract() -> void:
	## 五事件发射参数与 §2.3 契约逐字一致（实体引用 + float 数值类型）
	# parry_success(defender, attacker, stance_damage: float)
	var s1 = _setup()
	if s1.is_empty(): return
	var j1 = s1["j"]
	var p1 = s1["player"]
	var e1 = s1["enemy"]
	var w1 = _new_window(e1, TEST_START_FRAME, 15.0, 35.0, 1)
	if w1 == null: return
	j1.register_attack_window(w1)
	j1._on_guard_pressed(_parry_lower_ms())
	j1.resolve_attack(e1, p1)
	_assert(_parry_log.size() == 1, "parry_success emitted once")
	if _parry_log.size() == 1:
		_assert(typeof(_parry_log[0][0]) == TYPE_OBJECT and typeof(_parry_log[0][1]) == TYPE_OBJECT and typeof(_parry_log[0][2]) == TYPE_FLOAT, "parry_success(defender, attacker, stance_damage: float) signature")

	# block_held(defender, attacker, stance_cost: float)
	_reset_logs()
	var s2 = _setup()
	if s2.is_empty(): return
	var j2 = s2["j"]
	var p2 = s2["player"]
	var e2 = s2["enemy"]
	var w2 = _new_window(e2, TEST_START_FRAME, 15.0, 35.0, 1)
	if w2 == null: return
	j2.register_attack_window(w2)
	p2.request_transition("guard")
	j2.resolve_attack(e2, p2)
	_assert(_block_log.size() == 1, "block_held emitted once")
	if _block_log.size() == 1:
		_assert(typeof(_block_log[0][0]) == TYPE_OBJECT and typeof(_block_log[0][1]) == TYPE_OBJECT and typeof(_block_log[0][2]) == TYPE_FLOAT, "block_held(defender, attacker, stance_cost: float) signature")

	# hit_landed(defender, attacker, hp_damage: float, stance_damage: float)
	_reset_logs()
	var s3 = _setup()
	if s3.is_empty(): return
	var j3 = s3["j"]
	var p3 = s3["player"]
	var e3 = s3["enemy"]
	var w3 = _new_window(e3, TEST_START_FRAME, 15.0, 35.0, 1)
	if w3 == null: return
	j3.register_attack_window(w3)
	j3.resolve_attack(e3, p3)
	_assert(_hit_log.size() == 1, "hit_landed emitted once")
	if _hit_log.size() == 1:
		_assert(typeof(_hit_log[0][0]) == TYPE_OBJECT and typeof(_hit_log[0][1]) == TYPE_OBJECT and typeof(_hit_log[0][2]) == TYPE_FLOAT and typeof(_hit_log[0][3]) == TYPE_FLOAT, "hit_landed(defender, attacker, hp_damage: float, stance_damage: float) signature")

	# clash(entity_a, entity_b, stance_cost: float)
	_reset_logs()
	var s4 = _setup()
	if s4.is_empty(): return
	var j4 = s4["j"]
	var p4 = s4["player"]
	var e4 = s4["enemy"]
	var w4a = _new_window(e4, TEST_START_FRAME, 15.0, 35.0, 1)
	var w4b = _new_window(p4, TEST_START_FRAME, 12.0, 35.0, 1)
	if w4a == null or w4b == null: return
	j4.register_attack_window(w4a)
	j4.register_attack_window(w4b)
	j4.resolve_attack(e4, p4)
	_assert(_clash_log.size() == 1, "clash emitted once")
	if _clash_log.size() == 1:
		_assert(typeof(_clash_log[0][0]) == TYPE_OBJECT and typeof(_clash_log[0][1]) == TYPE_OBJECT and typeof(_clash_log[0][2]) == TYPE_FLOAT, "clash(entity_a, entity_b, stance_cost: float) signature")

	# stance_broken(entity)
	_reset_logs()
	var s5 = _setup()
	if s5.is_empty(): return
	var j5 = s5["j"]
	var p5 = s5["player"]
	var e5 = s5["enemy"]
	e5.stance = 5.0
	var w5 = _new_window(e5, TEST_START_FRAME, 15.0, 35.0, 1)
	if w5 == null: return
	j5.register_attack_window(w5)
	j5._on_guard_pressed(_parry_lower_ms())
	j5.resolve_attack(e5, p5)
	_assert(_broken_log.size() == 1, "stance_broken emitted once")
	if _broken_log.size() == 1:
		_assert(typeof(_broken_log[0][0]) == TYPE_OBJECT, "stance_broken(entity) signature")


func _test_18_reentry_noop() -> void:
	## 防重入: 同一命中 resolve_attack 连调两次 → 第二次 no-op（事件恰好一次，防双罚）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j.resolve_attack(enemy, player)
	j.resolve_attack(enemy, player)  # 同帧第二次 → no-op
	_assert(_hit_log.size() == 1, "repeated resolve_attack same frame → exactly one event (got %d)" % _hit_log.size())
	_assert(player.hp_1 == 85.0, "reentry: no double damage (hp 85, not 70)")


func _test_19_unregistered_window_noop() -> void:
	## 未注册窗口命中: resolve_attack 无活跃窗口 → no-op + push_warning（不凭空判定）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	j.resolve_attack(enemy, player)  # 未登记任何窗口
	_assert(_parry_log.is_empty() and _block_log.is_empty() and _hit_log.is_empty() and _clash_log.is_empty(), "no registered window → resolve no-op (push_warning)")
	_assert(player.hp_1 == 100.0, "unregistered window: no damage applied")


# ── Scenario E: 边界/失败路径 (§5 + PRD §5.3) ──────────────────────────

func _test_20_invincible_noop() -> void:
	## 无敌期命中: player 无敌期内（INVINCIBLE_SECONDS）→ 判定器 no-op（无 hit_landed）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	player._invincible_until_sec = Time.get_ticks_msec() / 1000.0 + 5.0
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j.resolve_attack(enemy, player)
	_assert(_hit_log.is_empty(), "invincible defender → no hit_landed")
	_assert(_parry_log.is_empty() and _block_log.is_empty() and _clash_log.is_empty(), "invincible defender → no result events")
	_assert(player.hp_1 == 100.0, "invincible: hp unchanged")


func _test_21_dead_defender_noop() -> void:
	## dead 实体命中: defender 处于 dead → 判定器跳过（无事件）
	var player = _new_entity({is_player=true, life_total=1})
	var enemy = _mk_enemy()
	if player == null or enemy == null: return
	player.take_damage(999.0)  # hp_1 打空 → dead（life_total=1 终态）
	_assert(player.state_name == "dead", "player reaches dead state")
	var j = _new_judge()
	if j == null: return
	j.bind_entities(player, enemy)
	j._frame = _hit_frame(TEST_START_FRAME)
	_connect_judge(j)
	var w = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)
	if w == null: return
	j.register_attack_window(w)
	j.resolve_attack(enemy, player)
	_assert(_parry_log.is_empty() and _block_log.is_empty() and _hit_log.is_empty() and _clash_log.is_empty(), "dead defender → judge skips, no events")
	_assert(player.hp_1 == 0.0, "dead defender hp stays 0")


func _test_22_unbound_judge_noop() -> void:
	## 判定器未 bind 实体: resolve 调用 → no-op + push_warning（防 NPE）
	var j = _new_judge()
	if j == null: return
	var player = _mk_player()
	var enemy = _mk_enemy()
	if player == null or enemy == null: return
	j._frame = _hit_frame(TEST_START_FRAME)
	_connect_judge(j)
	j.resolve_attack(enemy, player)  # bind_entities 未调用
	_assert(_parry_log.is_empty() and _block_log.is_empty() and _hit_log.is_empty() and _clash_log.is_empty(), "unbound judge resolve → no-op (push_warning)")


func _test_23_window_overwrite() -> void:
	## 窗口覆盖: 同 attacker 二次登记 → 旧窗口作废新窗口生效（连段/重攻击覆盖语义）
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var wa = _new_window(enemy, TEST_START_FRAME, 999.0, 999.0, 1)  # 旧窗口（大伤害）
	var wb = _new_window(enemy, TEST_START_FRAME, 15.0, 35.0, 1)   # 新窗口覆盖
	if wa == null or wb == null: return
	j.register_attack_window(wa)
	j.register_attack_window(wb)  # 同 attacker → 旧窗口作废
	j.resolve_attack(enemy, player)
	_assert(_hit_log.size() == 1, "overwritten window resolves exactly once (got %d)" % _hit_log.size())
	_assert(player.hp_1 == 85.0, "new window damage applied, old (999) invalidated (got %.1f)" % player.hp_1)


func _test_24_constants_driven() -> void:
	## AC4: 判定数值全部来自 constants（无字面量）——事件发射数值与 constants 映射比对
	var cm: Dictionary = _const_map()
	_assert(absf(float(cm.get("PARRY_STANCE_DAMAGE", -1.0)) - 25.0) < 0.0001, "PARRY_STANCE_DAMAGE == 25.0 (DRAFT)")
	_assert(absf(float(cm.get("CLASH_STANCE_COST", -1.0)) - 10.0) < 0.0001, "CLASH_STANCE_COST == 10.0 (DRAFT)")
	_assert(absf(float(cm.get("POSTURE_BLOCK_COST", -1.0)) - 10.0) < 0.0001, "POSTURE_BLOCK_COST == 10.0 (DRAFT)")
	_assert(absf(float(cm.get("POSTURE_HIT_COST", -1.0)) - 35.0) < 0.0001, "POSTURE_HIT_COST == 35.0 (DRAFT)")
	_assert(int(cm.get("CLASH_PRIORITY", -1)) == 0, "CLASH_PRIORITY == 0 (DRAFT)")
	_assert(int(cm.get("HITBOX_ACTIVE_FRAMES", -1)) == 4, "HITBOX_ACTIVE_FRAMES == 4 (DRAFT)")
	_assert(absf(float(cm.get("HITBOX_RANGE", -1.0)) - 80.0) < 0.0001, "HITBOX_RANGE == 80.0 (DRAFT)")
	_assert(int(cm.get("PARRY_DIRECTION_TOLERANCE", -1)) == 1, "PARRY_DIRECTION_TOLERANCE == 1 (DRAFT)")
	var pd: float = float(cm.get("PARRY_STANCE_DAMAGE", -1.0))
	var cs: float = float(cm.get("CLASH_STANCE_COST", -1.0))
	var bc: float = float(cm.get("POSTURE_BLOCK_COST", -1.0))
	var hc: float = float(cm.get("POSTURE_HIT_COST", -1.0))
	# parry 路径: 事件 cost == PARRY_STANCE_DAMAGE 常量
	var s1 = _setup()
	if s1.is_empty(): return
	var j1 = s1["j"]
	var p1 = s1["player"]
	var e1 = s1["enemy"]
	var w1 = _new_window(e1, TEST_START_FRAME, 15.0, hc, 1)
	if w1 == null: return
	j1.register_attack_window(w1)
	j1._on_guard_pressed(_parry_lower_ms())
	j1.resolve_attack(e1, p1)
	if _parry_log.size() == 1:
		_assert(float(_parry_log[0][2]) == pd, "parry cost follows PARRY_STANCE_DAMAGE constant (no literal, got %s)" % str(_parry_log[0][2]))
	# clash 路径: 事件 cost == CLASH_STANCE_COST 常量
	_reset_logs()
	var s2 = _setup()
	if s2.is_empty(): return
	var j2 = s2["j"]
	var p2 = s2["player"]
	var e2 = s2["enemy"]
	var w2a = _new_window(e2, TEST_START_FRAME, 15.0, hc, 1)
	var w2b = _new_window(p2, TEST_START_FRAME, 12.0, hc, 1)
	if w2a == null or w2b == null: return
	j2.register_attack_window(w2a)
	j2.register_attack_window(w2b)
	j2.resolve_attack(e2, p2)
	if _clash_log.size() == 1:
		_assert(float(_clash_log[0][2]) == cs, "clash cost follows CLASH_STANCE_COST constant (no literal, got %s)" % str(_clash_log[0][2]))
	# block 路径: 事件 cost == POSTURE_BLOCK_COST 常量
	_reset_logs()
	var s3 = _setup()
	if s3.is_empty(): return
	var j3 = s3["j"]
	var p3 = s3["player"]
	var e3 = s3["enemy"]
	var w3 = _new_window(e3, TEST_START_FRAME, 15.0, hc, 1)
	if w3 == null: return
	j3.register_attack_window(w3)
	p3.request_transition("guard")
	j3.resolve_attack(e3, p3)
	if _block_log.size() == 1:
		_assert(float(_block_log[0][2]) == bc, "block cost follows POSTURE_BLOCK_COST constant (no literal, got %s)" % str(_block_log[0][2]))
	# hit 路径: 事件 stance 参数 == POSTURE_HIT_COST 常量
	_reset_logs()
	var s4 = _setup()
	if s4.is_empty(): return
	var j4 = s4["j"]
	var p4 = s4["player"]
	var e4 = s4["enemy"]
	var w4 = _new_window(e4, TEST_START_FRAME, 15.0, hc, 1)
	if w4 == null: return
	j4.register_attack_window(w4)
	j4.resolve_attack(e4, p4)
	if _hit_log.size() == 1:
		_assert(float(_hit_log[0][3]) == hc, "hit stance cost follows POSTURE_HIT_COST constant (no literal, got %s)" % str(_hit_log[0][3]))


func _test_25_stagger_consecutive_hit_break() -> void:
	## #718 AC3: 连续受击（帧 1 进 stagger，帧 2 扣架势归零）→ 表内合法 → stance_break，
	##   判定器转发 stance_broken 恰好一次（修复前 illegal transition + 卡 stagger）。参照 _test_15/_test_16 断言风格。
	var s = _setup()
	if s.is_empty(): return
	var j = s["j"]
	var player = s["player"]
	var enemy = s["enemy"]
	var hc: float = float(_c("POSTURE_HIT_COST"))
	## 帧 1: 命中 → 进 stagger（扣血 + 扣架势，架势未归零）
	var w1 = _new_window(enemy, TEST_START_FRAME, 15.0, hc, 1)
	if w1 == null: return
	j.register_attack_window(w1)
	j.resolve_attack(enemy, player)
	_assert(player.state_name == "stagger", "frame1: player enters stagger (got %s)" % player.state_name)
	_assert(player.stance == (100.0 - hc), "frame1: stance drained but not zero (got %.1f)" % player.stance)
	## 帧 2: 新窗口（覆盖旧窗口）→ 扣血 + 扣架势归零 → 崩解
	j._frame += 1
	var w2 = _new_window(enemy, TEST_START_FRAME, 15.0, 999.0, 1)
	if w2 == null: return
	j.register_attack_window(w2)
	j.resolve_attack(enemy, player)
	_assert(player.state_name == "stance_break", "frame2: consecutive hit drains stance → stance_break (got %s)" % player.state_name)
	_assert(player.is_stance_broken == true, "frame2: is_stance_broken flag set")
	_assert(player.stance == 0.0, "frame2: stance clamped to 0 (got %.1f)" % player.stance)
	_assert(_broken_log.size() == 1, "frame2: stance_broken forwarded exactly once (got %d)" % _broken_log.size())
	if _broken_log.size() == 1:
		_assert(_broken_log[0][0] == player, "forwarded stance_broken(entity) carries the broken entity")

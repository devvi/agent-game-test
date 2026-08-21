extends Object
## Test suite for CombatEntity + 11-state combat state machine (#575).
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/575-combat-entity-state-machine.md §8 (Scenario A-F)
##
## TDD red phase: combat_*.gd do NOT exist yet → runtime load() returns null
## → assertions fail (red) instead of whole-file parse error.
##
## Godot 4.7.1 --script 硬性约束 (同 test_stick_figure_animation.gd):
##   - 禁止 := 类型推断 (4.7.1 视推断警告为硬错误) — 一律显式类型或普通 =
##   - class_name 可能无法解析 → 一律经 load()/preload 脚本资源访问
##   - 纯数据断言免树直接 new；_process 手动推进 (同步, 不依赖真实帧)

const WolfConstantsScript = preload("res://gdscripts/constants.gd")

const CANONICAL: Array = ["idle", "move", "attack", "heavy_attack", "guard", "parry_success", "stagger", "stance_break", "execute", "revive", "dead"]

## 期望转移表 (DESIGN §2.2 逐字镜像) — 与实现 is_legal 121 对遍历比对
const EXPECTED_TRANSITIONS: Dictionary = {
	"idle": ["move", "attack", "heavy_attack", "guard", "stagger", "stance_break", "parry_success", "dead"],
	"move": ["idle", "attack", "heavy_attack", "guard", "stagger", "stance_break", "parry_success", "dead"],
	"attack": ["attack", "idle", "stagger", "stance_break", "dead"],
	"heavy_attack": ["idle", "stagger", "stance_break", "dead"],
	"guard": ["idle", "attack", "heavy_attack", "stance_break", "dead", "parry_success"],
	"parry_success": ["idle", "attack", "heavy_attack", "move"],
	"stagger": ["idle", "dead"],
	"stance_break": ["idle", "execute", "dead"],
	"execute": ["idle"],
	"revive": ["idle"],
	"dead": ["revive"],
}

var passed: int = 0
var failed: int = 0

# 信号记录
var _hp_log: Array = []
var _stance_log: Array = []
var _broken_log: Array = []
var _state_log: Array = []
var _died_log: Array = []
var _revived_count: int = 0


func run() -> void:
	print("\n=== CombatEntity Tests ===")
	_reset_logs()
	_test_a0_timing_constants()
	_reset_logs()
	_test_a1_player_variant_init()
	_reset_logs()
	_test_a2_enemy_variant_init()
	_reset_logs()
	_test_a3_attr_read_write()
	_reset_logs()
	_test_b1_transition_table_121()
	_reset_logs()
	_test_b2_red_line_stance_break()
	_reset_logs()
	_test_b3_dead_lockdown()
	_reset_logs()
	_test_b4_legal_transitions_execute()
	_reset_logs()
	_test_b5_same_state_ignored()
	_reset_logs()
	_test_b6_combo_restart()
	_reset_logs()
	_test_c1_damage_stagger()
	_reset_logs()
	_test_c2_stagger_auto_exit()
	_reset_logs()
	_test_c3_guard_no_stagger()
	_reset_logs()
	_test_c4_invincible_window()
	_reset_logs()
	_test_c5_negative_clamp()
	_reset_logs()
	_test_d1_stance_drain()
	_reset_logs()
	_test_d2_break_broadcast()
	_reset_logs()
	_test_d3_break_idempotent()
	_reset_logs()
	_test_d4_guard_break()
	_reset_logs()
	_test_d5_break_recovery_execute()
	_reset_logs()
	_test_e1_first_life_depleted()
	_reset_logs()
	_test_e2_revive_flow()
	_reset_logs()
	_test_e3_second_life_depleted()
	_reset_logs()
	_test_e4_life_total1_final()
	_reset_logs()
	_test_e5_final_dead_no_revive()
	_reset_logs()
	_test_e6_state_sequence()
	_reset_logs()
	_test_f1_dead_no_op()
	_reset_logs()
	_test_f2_canonical_contract_alignment()
	_reset_logs()
	_test_f3_input_bridge_mock()
	# Scenario E(#682): 架势脱战恢复（AC8 + 实验 2, DESIGN §8 Scenario E）
	_reset_logs()
	_test_recover_e1_delay_no_recover()
	_reset_logs()
	_test_recover_e2_timeout_advance()
	_reset_logs()
	_test_recover_e3_skip_while_broken()
	_reset_logs()
	_test_recover_e4_player_no_trigger()
	_reset_logs()
	_test_recover_e5_redamage_reset()
	_reset_logs()
	_test_recover_e6_dual_write_race()
	_reset_logs()
	_test_recover_e6_fast_line_survives()
	# Scenario #720: 霸体（windup 不打断 / 收招可打断）+ 自动面向（T5-T7）
	_reset_logs()
	_test_720_a1_armor_windup_no_interrupt()
	_reset_logs()
	_test_720_a2_armor_recovery_interrupt()
	_reset_logs()
	_test_720_a3_armor_only_enemy()
	_reset_logs()
	_test_720_b1_auto_face_turn()
	_reset_logs()
	_test_720_b2_auto_face_no_target()
	_reset_logs()
	_test_720_b3_auto_face_no_jitter()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _reset_logs() -> void:
	## 用例间重置信号日志（信号 handler 写成员变量，跨用例累积会污染 size 断言）
	_hp_log = []
	_stance_log = []
	_broken_log = []
	_state_log = []
	_died_log = []
	_revived_count = 0


## 运行时常量查表（#682 精英常量实现期才加入 constants.gd → 禁止编译期引用）：
## load constants.gd + get_script_constant_map().get(name, -1)（同 test_enemy_ai _c helper）
func _const_map() -> Dictionary:
	var script = load("res://gdscripts/constants.gd")
	if script == null:
		return {}
	return script.get_script_constant_map()


func _c(name: String) -> Variant:
	return _const_map().get(name, -1)


# ── helpers ─────────────────────────────────────────────────────────────

func _new_entity(params: Dictionary):
	var s = load("res://gdscripts/combat_entity.gd")
	if s == null:
		_assert(false, "combat_entity.gd missing (TDD red phase)")
		return null
	var e = s.new(params)
	if e == null:
		_assert(false, "combat_entity.gd failed to instantiate")
	return e


func _advance(e, frames: int, delta: float = 1.0 / 60.0) -> void:
	for i in range(frames):
		e._process(delta)


func _on_hp_changed(h1: float, h2: float, active: int) -> void:
	_hp_log.append([h1, h2, active])


func _on_stance_changed(st: float, sm: float) -> void:
	_stance_log.append([st, sm])


func _on_stance_broken(ent) -> void:
	_broken_log.append(1)


func _on_state_changed(from: String, to: String) -> void:
	_state_log.append([from, to])


func _on_died(ent, final: bool) -> void:
	_died_log.append(final)


func _on_revived(ent) -> void:
	_revived_count += 1


# ── Scenario A: 变体实例化与属性读写 (AC1) ──────────────────────────────

func _test_a0_timing_constants() -> void:
	var script = load("res://gdscripts/constants.gd")
	if script == null:
		_assert(false, "constants.gd missing")
		return
	var cm: Dictionary = script.get_script_constant_map()
	_assert(int(cm.get("STAGGER_FRAMES", -1)) == 12, "STAGGER_FRAMES == 12")
	_assert(int(cm.get("PARRY_SUCCESS_FRAMES", -1)) == 10, "PARRY_SUCCESS_FRAMES == 10")
	_assert(absf(float(cm.get("STANCE_BREAK_RECOVERY_SEC", -1.0)) - 3.0) < 0.0001, "STANCE_BREAK_RECOVERY_SEC == 3.0")
	_assert(absf(float(cm.get("REVIVE_SECONDS", -1.0)) - 1.0) < 0.0001, "REVIVE_SECONDS == 1.0")
	_assert(absf(float(cm.get("INVINCIBLE_SECONDS", -1.0)) - 1.0) < 0.0001, "INVINCIBLE_SECONDS == 1.0")


func _test_a1_player_variant_init() -> void:
	var e = _new_entity({is_player=true})
	if e == null: return
	_assert(e.is_player == true and e.life_total == 2, "player variant params (is_player=true, life_total=2)")
	_assert(e.hp_1 == 100.0, "player hp_1 == 100")
	_assert(e.hp_2 == 50.0, "player hp_2 == 50")
	_assert(e.stance == 100.0, "player stance == 100")
	_assert(e.facing == 1, "player facing == 1")
	_assert(e.state_name == "idle", "player initial state == idle")
	_assert(e.is_stance_broken == false, "player not stance broken")


func _test_a2_enemy_variant_init() -> void:
	var e = _new_entity({is_player=false, life_total=1, life_1_max=40.0, stance_max=50.0})
	if e == null: return
	_assert(e.is_player == false and e.life_total == 1, "enemy variant params (life_total=1)")
	_assert(e.hp_1 == 40.0, "enemy hp_1 == 40 (life_1_max)")
	_assert(e.stance == 50.0, "enemy stance == 50 (stance_max)")


func _test_a3_attr_read_write() -> void:
	var e = _new_entity({})
	if e == null: return
	e.hp_1 = 77.0
	e.hp_2 = 33.0
	e.stance = 22.0
	e.facing = -1
	_assert(e.hp_1 == 77.0 and e.hp_2 == 33.0 and e.stance == 22.0 and e.facing == -1, "hp/stance/facing read-write roundtrip")


# ── Scenario B: 状态流转合法性 (AC2 + PRD 实验 1) ───────────────────────

func _test_b1_transition_table_121() -> void:
	var s = load("res://gdscripts/combat_state_table.gd")
	if s == null:
		_assert(false, "combat_state_table.gd missing (TDD red phase)")
		return
	var canonical: Array = s.CANONICAL_STATES
	_assert(canonical.size() == 11, "CANONICAL_STATES has 11 entries")
	var mismatches: Array = []
	for f in canonical:
		for t in canonical:
			var impl: bool = s.is_legal(f, t)
			var expected: bool = EXPECTED_TRANSITIONS[f].has(t)
			if impl != expected:
				mismatches.append("%s→%s (impl=%s exp=%s)" % [f, t, impl, expected])
	_assert(mismatches.is_empty(), "121-pair table fully agrees (mismatches: %s)" % [str(mismatches)])


func _test_b2_red_line_stance_break() -> void:
	var e = _new_entity({})
	if e == null: return
	e.take_stance_damage(100.0)
	_assert(e.state_name == "stance_break", "stance depleted → stance_break state")
	for s in ["attack", "heavy_attack", "guard"]:
		var r = e.request_transition(s)
		_assert(r == false and e.state_name == "stance_break", "red line: %s rejected in stance_break (r=%s)" % [s, r])


func _test_b3_dead_lockdown() -> void:
	var e = _new_entity({})
	if e == null: return
	e.take_damage(100.0)
	_assert(e.state_name == "dead", "hp_1 depleted → dead")
	for s in CANONICAL:
		if s == "revive":
			continue
		var r = e.request_transition(s)
		_assert(r == false and e.state_name == "dead", "dead lockdown: %s rejected (r=%s)" % [s, r])
	var rv = e.request_transition("revive")
	_assert(rv == true and e.state_name == "revive", "dead→revive allowed (rv=%s)" % [rv])


func _test_b4_legal_transitions_execute() -> void:
	var e = _new_entity({})
	if e == null: return
	e.state_changed.connect(_on_state_changed)
	_assert(e.request_transition("attack") == true and e.state_name == "attack", "idle→attack executes")
	_assert(e.request_transition("idle") == true and e.state_name == "idle", "attack→idle executes")
	_assert(e.request_transition("move") == true and e.state_name == "move", "idle→move executes")
	_assert(_state_log.size() == 3, "3 state_changed emissions (got %d)" % _state_log.size())


func _test_b5_same_state_ignored() -> void:
	var e = _new_entity({})
	if e == null: return
	e.state_changed.connect(_on_state_changed)
	var r = e.request_transition("idle")
	_assert(r == true, "same-state request returns true (restart hook)")
	_assert(e.state_name == "idle", "state unchanged")
	_assert(_state_log.is_empty(), "no state_changed emitted for same-state (silent)")


func _test_b6_combo_restart() -> void:
	var e = _new_entity({})
	if e == null: return
	e.request_transition("attack")
	_advance(e, 13)  # frame 13 ≥ WINDUP(8)+BURST(4)=12 → recovery phase (2)
	var st = e.fsm.current_state
	var before: float = st._elapsed
	e.request_transition("attack")
	_assert(st._elapsed < before - 0.1, "combo: restart resets frame count in recovery phase (%.3f → %.3f)" % [before, st._elapsed])
	_advance(e, 2)  # frame 2 < 8 → windup phase (0)
	var w2: float = st._elapsed
	e.request_transition("attack")
	_assert(absf(st._elapsed - w2) < 0.0001, "combo: restart ignored during windup phase (%.3f → %.3f)" % [w2, st._elapsed])


# ── Scenario C: 受击主路径 (AC5-1) ─────────────────────────────────────

func _test_c1_damage_stagger() -> void:
	var e = _new_entity({})
	if e == null: return
	e.hp_changed.connect(_on_hp_changed)
	e.take_damage(12.0)
	_assert(e.hp_1 == 88.0, "take_damage(12) → hp_1=88")
	_assert(e.state_name == "stagger", "damage in idle → stagger")
	_assert(_hp_log.size() == 1 and _hp_log[0] == [88.0, 50.0, 1], "hp_changed(88,50,1) emitted (got %s)" % [str(_hp_log)])


func _test_c2_stagger_auto_exit() -> void:
	var e = _new_entity({})
	if e == null: return
	e.take_damage(12.0)
	_assert(e.state_name == "stagger", "enter stagger")
	_advance(e, 13)
	_assert(e.state_name == "idle", "stagger auto-exits to idle after STAGGER_FRAMES")


func _test_c3_guard_no_stagger() -> void:
	var e = _new_entity({})
	if e == null: return
	e.request_transition("guard")
	e.take_damage(12.0)
	_assert(e.hp_1 == 88.0, "guard hit reduces hp")
	_assert(e.state_name == "guard", "guard hit does NOT stagger (keeps guard stance)")


func _test_c4_invincible_window() -> void:
	var e = _new_entity({})
	if e == null: return
	e.take_damage(100.0)
	e.revive()
	e.take_damage(999.0)
	_assert(e.hp_2 == 50.0, "invincible during revive window: 999 damage no-op")
	_advance(e, 61)  # revive state auto-exits to idle after REVIVE_SECONDS (take_damage no-op in revive, DESIGN §5.2-1)
	e._invincible_until_sec = 0.0
	e.take_damage(10.0)
	_assert(e.hp_2 == 40.0, "damage applies after invincibility expiry")


func _test_c5_negative_clamp() -> void:
	var e = _new_entity({})
	if e == null: return
	e.take_damage(-5.0)
	_assert(e.hp_1 == 100.0, "negative damage treated as 0 (hp unchanged)")
	e.take_stance_damage(-5.0)
	_assert(e.stance == 100.0, "negative stance damage treated as 0 (stance unchanged)")


# ── Scenario D: 架势主路径 (AC3 + AC5-2) ───────────────────────────────

func _test_d1_stance_drain() -> void:
	var e = _new_entity({})
	if e == null: return
	e.stance_changed.connect(_on_stance_changed)
	e.take_stance_damage(30.0)
	e.take_stance_damage(30.0)
	e.take_stance_damage(30.0)
	_assert(e.stance == 10.0, "stance 100-90 = 10")
	_assert(_stance_log.size() == 3, "3 stance_changed emissions (got %d)" % _stance_log.size())


func _test_d2_break_broadcast() -> void:
	var e = _new_entity({})
	if e == null: return
	e.stance_broken.connect(_on_stance_broken)
	e.stance = 5.0
	e.take_stance_damage(10.0)
	_assert(e.stance == 0.0, "stance clamped to 0 (overflow single trigger)")
	_assert(_broken_log.size() == 1, "exactly one stance_broken broadcast (got %d)" % _broken_log.size())
	_assert(e.is_stance_broken == true, "is_stance_broken flag set")
	_assert(e.state_name == "stance_break", "enters stance_break state")


func _test_d3_break_idempotent() -> void:
	var e = _new_entity({})
	if e == null: return
	e.stance_broken.connect(_on_stance_broken)
	e.take_stance_damage(100.0)
	e.take_stance_damage(10.0)
	_assert(_broken_log.size() == 1, "no second broadcast after break (got %d)" % _broken_log.size())
	_assert(e.stance == 0.0, "stance stays 0")


func _test_d4_guard_break() -> void:
	var e = _new_entity({})
	if e == null: return
	e.request_transition("guard")
	e.take_stance_damage(100.0)
	_assert(e.state_name == "stance_break", "guard→stance_break legal (guard break = imbalance)")


func _test_d5_break_recovery_execute() -> void:
	var e = _new_entity({})
	if e == null: return
	e.take_stance_damage(100.0)
	_assert(e.state_name == "stance_break", "enter stance_break")
	var r = e.request_transition("execute")
	_assert(r == true and e.state_name == "execute", "stance_break→execute legal (r=%s)" % [r])
	_advance(e, 6)
	_assert(e.state_name == "idle", "execute auto-exits after FRAME_ANIM_EXECUTE_TOTAL")
	var e2 = _new_entity({})
	if e2 == null: return
	e2.take_stance_damage(100.0)
	_advance(e2, 181)
	_assert(e2.state_name == "idle", "stance_break natural recovery to idle after STANCE_BREAK_RECOVERY_SEC")


# ── Scenario E: 死亡主路径 (AC4 + AC5-3) ───────────────────────────────

func _test_e1_first_life_depleted() -> void:
	var e = _new_entity({})
	if e == null: return
	e.died.connect(_on_died)
	e.take_damage(100.0)
	_assert(e.state_name == "dead", "hp_1 depleted → dead state")
	_assert(e.hp_1 == 0.0, "hp_1 == 0")
	_assert(_died_log.size() == 1 and _died_log[0] == false, "died(final=false) emitted once (got %s)" % [str(_died_log)])


func _test_e2_revive_flow() -> void:
	var e = _new_entity({})
	if e == null: return
	e.died.connect(_on_died)
	e.revived.connect(_on_revived)
	e.take_damage(100.0)
	e.revive()
	_assert(e.state_name == "revive", "revive() enters revive state")
	_assert(e.hp_2 == 50.0, "hp_2 == 50 (independent count)")
	_assert(e.stance == 0.0, "stance cleared after revive")
	_assert(e.is_stance_broken == false, "stance broken flag cleared")
	_assert(_revived_count == 1, "revived signal emitted")
	_advance(e, 61)
	_assert(e.state_name == "idle", "revive auto-exits to idle after REVIVE_SECONDS")


func _test_e3_second_life_depleted() -> void:
	var e = _new_entity({})
	if e == null: return
	e.died.connect(_on_died)
	e.take_damage(100.0)
	e.revive()
	_advance(e, 61)
	e._invincible_until_sec = 0.0
	e.take_damage(50.0)
	_assert(e.state_name == "dead", "hp_2 depleted → dead (final)")
	_assert(e._is_final_dead == true, "_is_final_dead set")
	_assert(_died_log.size() == 2 and _died_log[1] == true, "died(final=true) as second emission (got %s)" % [str(_died_log)])


func _test_e4_life_total1_final() -> void:
	var e = _new_entity({life_total=1, life_1_max=40.0})
	if e == null: return
	e.died.connect(_on_died)
	e.take_damage(40.0)
	_assert(e.state_name == "dead", "enemy hp_1 depleted → dead")
	_assert(_died_log.size() == 1 and _died_log[0] == true, "life_total=1 → died(final=true) directly (got %s)" % [str(_died_log)])
	_assert(e._is_final_dead == true, "final dead set for life_total=1 variant")


func _test_e5_final_dead_no_revive() -> void:
	var e = _new_entity({life_total=1, life_1_max=40.0})
	if e == null: return
	e.revived.connect(_on_revived)
	e.take_damage(40.0)
	e.revive()
	_assert(e.state_name == "dead", "final dead: revive() no-op, state stays dead")
	_assert(_revived_count == 0, "no revived signal after final dead")


func _test_e6_state_sequence() -> void:
	var e = _new_entity({})
	if e == null: return
	e.state_changed.connect(_on_state_changed)
	e.take_damage(100.0)   # idle→dead
	e.revive()             # dead→revive
	_advance(e, 61)        # revive→idle
	e._invincible_until_sec = 0.0
	e.take_damage(50.0)    # idle→dead (final)
	var expected: Array = [["idle", "dead"], ["dead", "revive"], ["revive", "idle"], ["idle", "dead"]]
	_assert(_state_log == expected, "state sequence idle→dead→revive→idle→dead (got %s)" % [str(_state_log)])


# ── Scenario F: 边界/契约对齐 ──────────────────────────────────────────

func _test_f1_dead_no_op() -> void:
	var e = _new_entity({})
	if e == null: return
	e.take_damage(100.0)
	_assert(e.state_name == "dead", "dead state reached")
	e.take_damage(50.0)
	_assert(e.hp_1 == 0.0, "take_damage no-op in dead (hp unchanged)")
	e.take_stance_damage(50.0)
	_assert(e.stance == 100.0, "take_stance_damage no-op in dead (stance unchanged)")


func _test_f2_canonical_contract_alignment() -> void:
	var anim = load("res://gdscripts/stick_figure_anim_states.gd")
	var table = load("res://gdscripts/combat_state_table.gd")
	if anim == null or table == null:
		_assert(false, "scripts missing for contract alignment (red phase)")
		return
	var keys: Array = anim.ANIM_CLIP_NAMES.keys()
	var canonical: Array = table.CANONICAL_STATES
	_assert(keys.size() == 11 and canonical.size() == 11, "both sets have 11 entries (anim=%d table=%d)" % [keys.size(), canonical.size()])
	var missing: Array = []
	var extra: Array = []
	for k in canonical:
		if not keys.has(k):
			missing.append(k)
	for k in keys:
		if not canonical.has(k):
			extra.append(k)
	_assert(missing.is_empty(), "canonical states missing from ANIM_CLIP_NAMES: %s" % [str(missing)])
	_assert(extra.is_empty(), "ANIM_CLIP_NAMES has extra states: %s" % [str(extra)])


class _MockInput:
	extends RefCounted
	signal attack_pressed
	signal heavy_attack_pressed
	signal guard_pressed(timestamp_ms: int)
	signal guard_held
	signal revive_pressed
	var axis: float = 0.0

	func get_move_axis() -> float:
		return axis


func _test_f3_input_bridge_mock() -> void:
	var e = _new_entity({is_player=true})
	if e == null: return
	e.revived.connect(_on_revived)
	var mock = _MockInput.new()
	e.bind_input_controller(mock)
	mock.emit_signal("attack_pressed")
	_assert(e.state_name == "attack", "attack_pressed → attack")
	_advance(e, 23)
	_assert(e.state_name == "idle", "attack auto-exits to idle")
	mock.emit_signal("heavy_attack_pressed")
	_assert(e.state_name == "heavy_attack", "heavy_attack_pressed → heavy_attack")
	_advance(e, 23)
	mock.emit_signal("guard_pressed", 0)
	_assert(e.state_name == "guard", "guard_pressed → guard")
	e._process(1.0 / 60.0)
	_assert(e.state_name == "idle", "guard release detected → idle")
	mock.axis = 1.0
	e._process(1.0 / 60.0)
	_assert(e.state_name == "move" and e.facing == 1, "axis>0 → move + facing=1")
	mock.axis = -1.0
	e._process(1.0 / 60.0)
	_assert(e.facing == -1, "axis<0 → facing=-1")
	mock.axis = 0.0
	e._process(1.0 / 60.0)
	_assert(e.state_name == "idle", "axis=0 → idle")
	e.take_damage(100.0)
	_assert(e.state_name == "dead", "dead via take_damage (bridge entity)")
	mock.emit_signal("revive_pressed")
	_assert(e.state_name == "revive", "revive_pressed → revive()")
	_assert(_revived_count == 1, "revived emitted via bridge")


# ── Scenario E(#682): 架势脱战恢复（AC8 + 实验 2）──────────────────────────
## 敌人专用（is_player=false）: take_stance_damage 重置 _stance_recover_delay_until_sec；
##   _process 轮询超延迟窗后按 ENEMY_STANCE_RECOVER_PER_SEC 恢复至 stance_max。
## 新常量（ENEMY_STANCE_RECOVER_*）实现期才加入 constants.gd → 一律经 _c() 运行时查表，
##   禁止编译期直接引用。时序手法（同 test_enemy_ai Time 门控）: 延迟字段直接落窗，
##   不依赖真实时钟——take_stance_damage 用真实 Time 布窗，测试执行微秒级内必然未到窗。

func _test_recover_e1_delay_no_recover() -> void:
	## E1 延迟窗口内不恢复: take_stance_damage(35) 后 2.5s 内推进 → stance 不变
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if e == null: return
	e.take_stance_damage(35.0)
	_assert(e.stance == 65.0, "E1: stance 100-35 = 65 (got %.1f)" % e.stance)
	_assert(e._stance_recover_delay_until_sec >= 0.0, "E1: take_stance_damage arms recovery delay (until %.2f)" % e._stance_recover_delay_until_sec)
	_advance(e, 120)   # 2.0s < ENEMY_STANCE_RECOVER_DELAY_SEC(2.5) 延迟窗内
	_assert(e.stance == 65.0, "E1: no recovery inside delay window (stance %.1f)" % e.stance)
	_assert(e.state_name == "idle", "E1: entity idle during window (got %s)" % e.state_name)


func _test_recover_e2_timeout_advance() -> void:
	## E2 超时恢复: 延迟窗过后推进 → stance 逐帧 += ENEMY_STANCE_RECOVER_PER_SEC*delta，
	##   至 stance_max 封顶（clamp 不越界）
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if e == null: return
	var per_sec: float = float(_c("ENEMY_STANCE_RECOVER_PER_SEC"))
	_assert(per_sec > 0.0, "E2: ENEMY_STANCE_RECOVER_PER_SEC present (got %.1f)" % per_sec)
	e.take_stance_damage(35.0)
	_assert(e.stance == 65.0, "E2: precondition stance 65")
	e.stance_changed.connect(_on_stance_changed)
	## 延迟窗落窗（强制过期——真实时钟驱动，测试直接置过去时间）
	e._stance_recover_delay_until_sec = Time.get_ticks_msec() / 1000.0 - 0.5
	e._process(1.0 / 60.0)
	_assert(absf(e.stance - (65.0 + per_sec / 60.0)) < 0.01, "E2: single frame recover += PER_SEC*delta (got %.4f)" % e.stance)
	_advance(e, 240)   # 4s → 65 + 80 = 145 → clamp 至 stance_max(100)
	_assert(e.stance == e.stance_max, "E2: recovery caps at stance_max (%.1f)" % e.stance)
	_assert(e.stance <= e.stance_max, "E2: never exceeds stance_max")
	_assert(_stance_log.size() >= 1, "E2: stance_changed emitted during recovery (got %d)" % _stance_log.size())
	if _stance_log.size() >= 1:
		_assert(absf(float(_stance_log[_stance_log.size() - 1][0]) - e.stance_max) < 0.0001, "E2: final stance_changed == stance_max")


func _test_recover_e3_skip_while_broken() -> void:
	## E3 崩解中不恢复: break_stance 后推进 → stance 保持 0（快线处决窗口不被恢复打断）
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if e == null: return
	e.take_stance_damage(100.0)
	_assert(e.is_stance_broken == true and e.state_name == "stance_break", "E3: stance broken → stance_break (got %s)" % e.state_name)
	_assert(e.stance == 0.0, "E3: stance at 0")
	## 即便延迟窗已过，崩解期间（is_stance_broken）轮询跳过
	e._stance_recover_delay_until_sec = Time.get_ticks_msec() / 1000.0 - 0.5
	_advance(e, 60)   # 1s < STANCE_BREAK_RECOVERY_SEC(3) 崩解期
	_assert(e.stance == 0.0, "E3: no recovery while broken (stance %.1f)" % e.stance)
	_assert(e.state_name == "stance_break", "E3: still in stance_break (got %s)" % e.state_name)


func _test_recover_e4_player_no_trigger() -> void:
	## E4 玩家不触发: is_player=true 实体受击 → 无恢复（玩家架势语义不变）
	var e = _new_entity({is_player=true})
	if e == null: return
	e.take_stance_damage(35.0)
	_assert(e.stance == 65.0, "E4: player stance 100-35 = 65 (got %.1f)" % e.stance)
	_assert(e._stance_recover_delay_until_sec == -1.0, "E4: player take_stance_damage does NOT arm delay (got %.1f)" % e._stance_recover_delay_until_sec)
	## 即便强制过期，is_player 门控 → 仍不恢复
	e._stance_recover_delay_until_sec = Time.get_ticks_msec() / 1000.0 - 0.5
	_advance(e, 120)
	_assert(e.stance == 65.0, "E4: player stance does NOT auto-recover (%.1f)" % e.stance)


func _test_recover_e5_redamage_reset() -> void:
	## E5 恢复-再受伤重置: 恢复中再注入 stance 伤害 → 延迟计时重置，恢复暂停（无闪烁）
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if e == null: return
	e.take_stance_damage(35.0)
	e._stance_recover_delay_until_sec = Time.get_ticks_msec() / 1000.0 - 0.5   # 落窗 → 恢复启动
	_advance(e, 60)   # 1s 恢复中
	var recovered: float = e.stance
	_assert(recovered > 65.0 and recovered < e.stance_max, "E5: recovery in progress (65 → %.1f)" % recovered)
	## 再受伤 → 重置延迟 + 恢复暂停
	e.take_stance_damage(10.0)
	var after_hit: float = e.stance
	var delay: float = e._stance_recover_delay_until_sec
	_assert(absf((recovered - after_hit) - 10.0) < 0.001, "E5: re-hit drops stance by 10 (%.1f → %.1f)" % [recovered, after_hit])
	_assert(delay > Time.get_ticks_msec() / 1000.0, "E5: recovery delay re-armed to future (until %.2f)" % delay)
	_advance(e, 120)   # 2s < 2.5s 新延迟窗 → 不恢复
	_assert(e.stance == after_hit, "E5: recovery paused after re-hit (no flicker, stance %.1f)" % e.stance)


func _test_recover_e6_dual_write_race() -> void:
	## E6 双写竞态（实验 2 落地）: 脱战恢复与 recover_from_break 同帧双触发 →
	##   最终 stance ∈ [0, stance_max]（幂等守卫 + 仅非崩解态恢复，双写不越界）
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if e == null: return
	e.take_stance_damage(100.0)
	_assert(e.is_stance_broken == true, "E6: stance broken")
	## 同帧双触发: 起身恢复（50% + 清崩解）+ 脱战恢复轮询（强制过期）
	e.recover_from_break()
	e._stance_recover_delay_until_sec = Time.get_ticks_msec() / 1000.0 - 0.5
	e._process(1.0 / 60.0)
	_assert(is_finite(e.stance), "E6: stance finite (no NaN)")
	_assert(e.stance >= 0.0 and e.stance <= e.stance_max, "E6: dual-write final stance ∈ [0, stance_max] (got %.2f)" % e.stance)


func _test_recover_e6_fast_line_survives() -> void:
	## E6（续）: 弹反序列（间隔 1.2s < 延迟 2.5s）下 4 弹反仍可崩解——快线不被脱战恢复打断
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0, stance_max=float(_c("POSTURE_BREAK_THRESHOLD"))})
	if e == null: return
	var pd: float = float(_c("PARRY_STANCE_DAMAGE"))
	var parries: int = 4
	_assert(pd > 0.0, "E6: PARRY_STANCE_DAMAGE present (got %.1f)" % pd)
	_assert(parries * pd >= e.stance_max, "E6: 4×PARRY_STANCE_DAMAGE(%.0f) ≥ stance_max(%.0f)" % [parries * pd, e.stance_max])
	for i in range(parries):
		e.take_stance_damage(pd)
		_advance(e, int(1.2 * 60.0))   # 间隔 1.2s < 延迟 2.5s → 每次弹反重置延迟，恢复不启动
	_assert(e.is_stance_broken, "E6: 4 parries @ 1.2s gaps still break stance (fast line holds)")
	_assert(e.state_name == "stance_break", "E6: enters stance_break (got %s)" % e.state_name)


# ── Scenario #720: 霸体（windup 不打断 / 收招可打断 / 仅敌人）+ 自动面向（T5-T7）─────

func _test_720_a1_armor_windup_no_interrupt() -> void:
	## #720 霸体（windup 期命中不打断）: 敌人 attack 且 _state_elapsed_frames < windup →
	##   take_damage → 不转 stagger、HP 已扣、hp_changed 已广播（修复前命中即 stagger）
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if e == null: return
	e.hp_changed.connect(_on_hp_changed)
	e.request_transition("attack")
	_assert(e.state_name == "attack", "enemy enters attack (got %s)" % e.state_name)
	_assert(e._windup_frames > 0, "windup frames set on attack enter (got %d)" % e._windup_frames)
	e._state_elapsed_frames = 0
	var hp_before: float = e.hp_1
	e.take_damage(15.0)
	_assert(e.hp_1 < hp_before, "armor hit reduces HP (%.1f → %.1f)" % [hp_before, e.hp_1])
	_assert(e.state_name == "attack", "windup hit does NOT stagger (霸体) (got %s)" % e.state_name)
	_assert(_hp_log.size() == 1, "hp_changed broadcast once (got %d)" % _hp_log.size())


func _test_720_a2_armor_recovery_interrupt() -> void:
	## #720 霸体只拦 windup 期: windup 结束后（收招期）take_damage → stagger（玩家反击窗口保留）
	var e = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if e == null: return
	e.request_transition("attack")
	e._state_elapsed_frames = e._windup_frames + 1
	e.take_damage(15.0)
	_assert(e.state_name == "stagger", "post-windup hit staggers (got %s)" % e.state_name)


func _test_720_a3_armor_only_enemy() -> void:
	## #720 霸体仅敌人（is_player 豁免）: 玩家 attack windup 期 take_damage → 仍 stagger（玩家无霸体）
	var e = _new_entity({is_player=true})
	if e == null: return
	e.request_transition("attack")
	_assert(e.state_name == "attack", "player enters attack (got %s)" % e.state_name)
	e._state_elapsed_frames = 0
	e.take_damage(15.0)
	_assert(e.state_name == "stagger", "player in attack windup still staggers (is_player 无霸体) (got %s)" % e.state_name)


func _test_720_b1_auto_face_turn() -> void:
	## #720 T5 自动面向: 玩家 facing=-1、敌人在右侧(dx>0)、注入 _auto_face_target →
	##   _on_bridge_attack_pressed → facing 翻转为 +1
	var p = _new_entity({is_player=true})
	if p == null: return
	var enemy = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null: return
	p.position = Vector2(50, 0)
	p.facing = -1
	enemy.position = Vector2(150, 0)
	p._auto_face_target = enemy
	_assert(p.facing == -1, "player facing -1 before attack")
	p._on_bridge_attack_pressed()
	_assert(p.facing == 1, "auto-face turns to +1 toward enemy (got %d)" % p.facing)
	_assert(p.state_name == "attack", "attack entered (got %s)" % p.state_name)


func _test_720_b2_auto_face_no_target() -> void:
	## #720 T6 无敌人 no-op: _auto_face_target = null → 攻击 → facing 不变
	var p = _new_entity({is_player=true})
	if p == null: return
	p.position = Vector2(50, 0)
	p.facing = -1
	p._auto_face_target = null
	p._on_bridge_attack_pressed()
	_assert(p.facing == -1, "no target → facing unchanged (got %d)" % p.facing)


func _test_720_b3_auto_face_no_jitter() -> void:
	## #720 T7 攻击中 facing 不抖动: 攻击转向后 _bridge_poll 收到反向移动轴 → facing 保持攻击方向
	var p = _new_entity({is_player=true})
	if p == null: return
	var enemy = _new_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null: return
	p.position = Vector2(50, 0)
	p.facing = -1
	enemy.position = Vector2(150, 0)
	p._auto_face_target = enemy
	var mock = _MockInput.new()
	p.bind_input_controller(mock)
	p._on_bridge_attack_pressed()
	_assert(p.facing == 1, "auto-face turned to +1 (got %d)" % p.facing)
	## 攻击中收到反向移动轴（-1）→ facing 保持 +1（非 idle/move 不更新）
	mock.axis = -1.0
	p._process(1.0 / 60.0)
	_assert(p.facing == 1, "attack-phase reverse move axis does NOT flip facing (no jitter) (got %d)" % p.facing)

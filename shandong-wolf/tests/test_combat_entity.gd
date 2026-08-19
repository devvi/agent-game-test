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

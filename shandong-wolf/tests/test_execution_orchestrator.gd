extends Object
## Test suite for ExecutionOrchestrator + ExecutionFade + CombatEntity additive (#580) — 处决系统。
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/580-execution-system.md §8 (Scenario A-F) / §2.1 (D1-D6) / §2.2 / §3.2
##
## TDD red phase: execution_orchestrator.gd / execution_fade.gd 尚不存在，combat_entity.gd
## 尚未追加 execute_kill()/set_invincible()/recover_from_break()/exhausted
## → 全部经 load() + has_method() 守卫：断言失败（red）而非 parse error / 崩溃。
##
## Godot 4.7.1 --script 硬性约束 (同 test_revive_orchestrator.gd / test_combat_entity.gd):
##   - 禁止 := 类型推断 (4.7.1 视推断警告为硬错误) — 一律显式类型或普通 =
##   - class_name 可能无法解析 → 一律经 load() 脚本资源访问
##   - 编排器/淡出纯逻辑 new + 手动 _process(delta) / _tick(now_ms) 推进（headless 免树）
##   - 实体 load("res://gdscripts/combat_entity.gd").new({...})，Node2D 直接设 .position
##   - 编排器禁止直写 Engine.time_scale（红线，慢动作归 TimeScaleStack/#579）
##   - run() 收尾强制复原 Engine.time_scale = 1.0（全局状态，防跨用例污染）

var passed: int = 0
var failed: int = 0

# 信号记录
var _died_log: Array = []
var _stance_log: Array = []
var _fade_completed: Array = []
var _broken_count: int = 0


func run() -> void:
	print("\n=== ExecutionOrchestrator Tests ===")
	_reset_logs()
	_test_a1_full_trigger_chain()
	_reset_logs()
	_test_b1_out_of_range()
	_reset_logs()
	_test_b1b_range_boundary()
	_reset_logs()
	_test_b2_window_expiry()
	_reset_logs()
	_test_b3_player_dead()
	_reset_logs()
	_test_b4_not_armed()
	_reset_logs()
	_test_b5_same_frame_race()
	_reset_logs()
	_test_c1_invincible_noop()
	_reset_logs()
	_test_c3_no_time_scale_write()
	_reset_logs()
	_test_d1_recover_numbers()
	_reset_logs()
	_test_d2_exhausted_multiplier()
	_reset_logs()
	_test_d3_exhausted_expiry()
	_reset_logs()
	_test_d4_recover_idempotent()
	_reset_logs()
	_test_d5_rebreak()
	_reset_logs()
	_test_e1_fade_progress()
	_reset_logs()
	_test_e3_fade_freed_target()
	_reset_logs()
	_test_e4_fade_rebind()
	_reset_logs()
	_test_f1_take_damage_red_line()
	_reset_logs()
	_test_f2_execute_kill_stop()
	_reset_logs()
	_test_f3_signal_leak_unbind()
	_reset_logs()
	_test_f4_no_feedback_bound()
	_reset_logs()
	_test_w1_judge_single_source()
	_reset_logs()
	_test_w2_input_bind()
	Engine.time_scale = 1.0
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _reset_logs() -> void:
	_died_log = []
	_stance_log = []
	_fade_completed = []
	_broken_count = 0


# ── helpers ─────────────────────────────────────────────────────────────

func _new_entity(params: Dictionary):
	var s = load("res://gdscripts/combat_entity.gd")
	if s == null:
		_assert(false, "combat_entity.gd missing")
		return null
	var e = s.new(params)
	if e == null:
		_assert(false, "combat_entity.gd failed to instantiate")
	return e


func _entity_has_method(e, method_name: String) -> bool:
	return e != null and is_instance_valid(e) and e.has_method(method_name)


func _new_orchestrator():
	var s = load("res://gdscripts/execution_orchestrator.gd")
	if s == null:
		_assert(false, "execution_orchestrator.gd missing (TDD red phase)")
		return null
	var o = s.new()
	if o == null:
		_assert(false, "execution_orchestrator.gd failed to instantiate")
	return o


func _new_fade():
	var s = load("res://gdscripts/execution_fade.gd")
	if s == null:
		_assert(false, "execution_fade.gd missing (TDD red phase)")
		return null
	var f = s.new()
	if f == null:
		_assert(false, "execution_fade.gd failed to instantiate")
	return f


func _setup_chain(player_x: float = 0.0, enemy_x: float = 100.0, with_feedback: bool = true):
	## 公共准备: 玩家(x) + 敌人(x) + 可选 mock 反馈，返回 [orch, player, enemy, feedback]
	var o = _new_orchestrator()
	if o == null:
		return null
	var p = _new_entity({is_player = true})
	var e = _new_entity({is_player = false, life_total = 1})
	if p == null or e == null:
		return null
	p.position.x = player_x
	e.position.x = enemy_x
	o.bind_player(p)
	o.bind_enemy(e)
	var fb = null
	if with_feedback:
		fb = _MockFeedback.new()
		o.bind_feedback(fb)
	return [o, p, e, fb]


func _on_died(ent, final: bool) -> void:
	_died_log.append(final)


func _on_stance_changed(st: float, sm: float) -> void:
	_stance_log.append([st, sm])


func _on_fade_completed(ent) -> void:
	_fade_completed.append(ent)


func _on_stance_broken(ent) -> void:
	_broken_count += 1


# ── Scenario A: 处决触发全链路 (AC1/AC2/AC4) ───────────────────────────

func _test_a1_full_trigger_chain() -> void:
	## A1+A2+A3: 全链路 —— armed → attack_pressed(距离内) → execute 转移 → execute_kill
	##   died(true) 恰一次 + hp 归零 + trigger_feedback 恰一次 + fade 绑定 + 玩家无敌生效
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var p = pair[1]
	var e = pair[2]
	var fb = pair[3]
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(e.state_name == "execute", "enemy state == execute after trigger (got %s)" % e.state_name)
	_assert(_died_log.size() == 1 and _died_log[0] == true, "died(true) exactly once (got %s)" % [str(_died_log)])
	_assert(e.hp_1 == 0.0, "enemy hp_1 == 0.0 (got %s)" % [e.hp_1])
	_assert(fb.calls.size() == 1, "trigger_feedback exactly once (got %d)" % fb.calls.size())
	if fb.calls.size() == 1:
		_assert(fb.calls[0][0] == "execute", "feedback event == execute (got %s)" % [fb.calls[0][0]])
	_assert(o.fade != null, "orchestrator created fade in _init")
	if o.fade != null:
		_assert(o.fade._bound == true, "fade bound after trigger")
		_assert(o.fade._target == e, "fade target == enemy")
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	_assert(p._invincible_until_sec > now_sec, "player invincible set after trigger (until %s <= %s)" % [p._invincible_until_sec, now_sec])
	p.take_damage(15.0)
	_assert(absf(p.hp_1 - 100.0) < 0.0001, "player hp unchanged while invincible (got %s)" % [p.hp_1])


# ── Scenario B: 触发边界（不触发处决）──────────────────────────────────

func _test_b1_out_of_range() -> void:
	## B1: 距离外 |dx|=121 > 120 → 不触发（无 died / 无反馈 / 无无敌）
	var pair = _setup_chain(0.0, 121.0)
	if pair == null: return
	var o = pair[0]
	var p = pair[1]
	var e = pair[2]
	var fb = pair[3]
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(_died_log.is_empty(), "no died when out of range (got %s)" % [str(_died_log)])
	_assert(fb.calls.is_empty(), "no feedback when out of range")
	_assert(p._invincible_until_sec <= Time.get_ticks_msec() / 1000.0, "no invincibility set when out of range")


func _test_b1b_range_boundary() -> void:
	## D1 边界（§5 边界 5）: 恰等 120px（闭区间 ≤）触发；120.1px 不触发。
	var pair = _setup_chain(0.0, 120.0)
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(_died_log.size() == 1, "dx == 120.0 triggers (closed interval) (got %d)" % _died_log.size())
	_reset_logs()
	pair = _setup_chain(0.0, 120.1)
	if pair == null: return
	o = pair[0]
	e = pair[2]
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(_died_log.is_empty(), "dx == 120.1 does not trigger (got %s)" % [str(_died_log)])


func _test_b2_window_expiry() -> void:
	## B2: 窗口过期 —— _process(3.0) → armed 清除 + 敌人起身（stance 50, exhausted true）→ 再按攻击不触发
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	if not _entity_has_method(e, "recover_from_break"):
		_assert(false, "combat_entity.recover_from_break() missing (TDD red phase)")
		return
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(3.0)
	_assert(o._armed == false, "armed cleared after window expiry")
	_assert(absf(float(e.stance) - 50.0) < 0.0001, "enemy recovered to 50%% stance (got %s)" % [e.stance])
	_assert(bool(e.get("exhausted")) == true, "enemy exhausted after recovery")
	o._on_attack_pressed()
	_assert(_died_log.is_empty(), "no died after window expiry")


func _test_b3_player_dead() -> void:
	## B3: 玩家已死 → attack_pressed 不触发处决（防「尸体处决」）
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var p = pair[1]
	var e = pair[2]
	e.died.connect(_on_died)
	p.take_damage(999.0)
	_assert(p.state_name == "dead", "player dead (got %s)" % p.state_name)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(_died_log.is_empty(), "no enemy died (player dead guard) (got %s)" % [str(_died_log)])


func _test_b4_not_armed() -> void:
	## B4: 未 armed（无 stance_broken）直接 attack_pressed → 不触发
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	e.died.connect(_on_died)
	o._on_attack_pressed()
	_assert(o._armed == false, "not armed without stance_broken")
	_assert(_died_log.is_empty(), "no died without stance_broken")


func _test_b5_same_frame_race() -> void:
	## B5: 同帧起身竞态 —— state_changed(stance_break→idle) 与 armed 到期同帧 → recover 恰一次（幂等防双写）
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	if not _entity_has_method(e, "recover_from_break"):
		_assert(false, "combat_entity.recover_from_break() missing (TDD red phase)")
		return
	e.break_stance()
	o._on_stance_broken(e)
	o._on_enemy_state_changed("stance_break", "idle")
	o._process(3.0)
	_assert(absf(float(e.stance) - 50.0) < 0.0001, "stance == 50 exactly once (got %s)" % [e.stance])
	_assert(bool(e.get("exhausted")) == true, "exhausted set exactly once")
	_assert(o._armed == false, "armed cleared by state exit")


# ── Scenario C: 玩家无敌与判定器交互 (AC2) ─────────────────────────────

func _test_c1_invincible_noop() -> void:
	## C1: 处决窗口内玩家 999 伤害全 no-op（hp 与 stance 均不变，判定器无敌期守卫 + 实体无敌双保险）
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var p = pair[1]
	var e = pair[2]
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	p.take_damage(999.0)
	p.take_stance_damage(999.0)
	_assert(absf(p.hp_1 - 100.0) < 0.0001, "player hp unchanged during execution (got %s)" % [p.hp_1])
	_assert(absf(p.stance - 100.0) < 0.0001, "player stance unchanged during execution (got %s)" % [p.stance])


func _test_c3_no_time_scale_write() -> void:
	## C3: 编排器不直写 Engine.time_scale（红线，慢动作归 TimeScaleStack/#579）
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	e.died.connect(_on_died)
	var before: float = Engine.time_scale
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(_died_log.size() == 1, "trigger ran (sanity)")
	_assert(absf(Engine.time_scale - before) < 0.0001, "Engine.time_scale unchanged after trigger (got %s)" % [Engine.time_scale])


# ── Scenario D: 疲惫起身数值闭环 (AC3) ─────────────────────────────────

func _test_d1_recover_numbers() -> void:
	## D1: armed 到期 → recover_from_break 恰一次；stance == 0.5 × stance_max == 50；stance_changed(50, 100)
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	if not _entity_has_method(e, "recover_from_break"):
		_assert(false, "combat_entity.recover_from_break() missing (TDD red phase)")
		return
	e.stance_changed.connect(_on_stance_changed)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(3.0)
	_assert(absf(float(e.stance) - 50.0) < 0.0001, "stance == 50 (0.5 * 100, got %s)" % [e.stance])
	_assert(_stance_log.size() == 1 and absf(float(_stance_log[0][0]) - 50.0) < 0.0001, "stance_changed emitted with 50.0 (got %s)" % [str(_stance_log)])


func _test_d2_exhausted_multiplier() -> void:
	## D2: 疲惫增伤 —— exhausted 期间 take_stance_damage(10) 扣 12（×1.2）: 50 → 38
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	if not _entity_has_method(e, "recover_from_break"):
		_assert(false, "combat_entity.recover_from_break() missing (TDD red phase)")
		return
	e.break_stance()
	o._on_stance_broken(e)
	o._process(3.0)
	_assert(bool(e.get("exhausted")) == true, "exhausted == true after recovery")
	e.take_stance_damage(10.0)
	_assert(absf(float(e.stance) - 38.0) < 0.0001, "stance 50 - 12 == 38 (×1.2, got %s)" % [e.stance])


func _test_d3_exhausted_expiry() -> void:
	## D3: 疲惫到期 —— _exhausted_until_sec=0 → _process 清除 exhausted → take_stance_damage(10) 扣 10
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	if not _entity_has_method(e, "recover_from_break"):
		_assert(false, "combat_entity.recover_from_break() missing (TDD red phase)")
		return
	e.break_stance()
	o._on_stance_broken(e)
	o._process(3.0)
	e.set("_exhausted_until_sec", 0.0)
	e._process(0.01)
	_assert(bool(e.get("exhausted")) == false, "exhausted cleared on expiry")
	e.take_stance_damage(10.0)
	_assert(absf(float(e.stance) - 40.0) < 0.0001, "stance 50 - 10 == 40 (multiplier 1.0, got %s)" % [e.stance])


func _test_d4_recover_idempotent() -> void:
	## D4: 双调 recover_from_break → 第二次 no-op（stance 保持 50，is_stance_broken 已清）
	var e = _new_entity({is_player = false, life_total = 1})
	if e == null: return
	if not _entity_has_method(e, "recover_from_break"):
		_assert(false, "combat_entity.recover_from_break() missing (TDD red phase)")
		return
	e.break_stance()
	e.recover_from_break()
	_assert(absf(float(e.stance) - 50.0) < 0.0001, "recover to 50%% (got %s)" % [e.stance])
	e.recover_from_break()
	_assert(absf(float(e.stance) - 50.0) < 0.0001, "second recover no-op (stance stays 50, got %s)" % [e.stance])


func _test_d5_rebreak() -> void:
	## D5: 再次崩解覆盖 —— 疲惫期 break_stance → is_stance_broken=true、exhausted 复位、stance_broken 再次发出
	var e = _new_entity({is_player = false, life_total = 1})
	if e == null: return
	if not _entity_has_method(e, "recover_from_break"):
		_assert(false, "combat_entity.recover_from_break() missing (TDD red phase)")
		return
	e.stance_broken.connect(_on_stance_broken)
	e.break_stance()
	_assert(_broken_count == 1, "first stance_broken emitted (got %d)" % _broken_count)
	e.recover_from_break()
	_assert(bool(e.get("exhausted")) == true, "exhausted after recovery")
	e.break_stance()
	_assert(e.is_stance_broken == true, "is_stance_broken == true after re-break")
	_assert(bool(e.get("exhausted")) == false, "exhausted reset on re-break")
	_assert(_broken_count == 2, "stance_broken re-emitted on re-break (got %d)" % _broken_count)


# ── Scenario E: 淡出清理 (AC2) ─────────────────────────────────────────

func _test_e1_fade_progress() -> void:
	## E1: 淡出推进 —— bind → _tick 起点 alpha 1.0 → +150ms ≈ 0.5 → +300ms fade_completed 恰一次 + queue_free + 解绑
	var e = _new_entity({is_player = false, life_total = 1})
	if e == null: return
	var f = _new_fade()
	if f == null: return
	f.fade_completed.connect(_on_fade_completed)
	var start: int = 100000
	f.bind(e)
	f._tick(start)
	_assert(absf(e.modulate.a - 1.0) < 0.0001, "alpha 1.0 at start (got %s)" % [e.modulate.a])
	f._tick(start + 150)
	_assert(absf(e.modulate.a - 0.5) < 0.02, "alpha ≈ 0.5 at +150ms (got %s)" % [e.modulate.a])
	f._tick(start + 300)
	_assert(_fade_completed.size() == 1, "fade_completed exactly once (got %d)" % _fade_completed.size())
	_assert(e.is_queued_for_deletion() == true, "target queued for deletion")
	_assert(f._bound == false, "fade unbound after completion")


func _test_e3_fade_freed_target() -> void:
	## E3: 目标释放守卫 —— 淡出中途 target.free() → _tick 静默解绑（无访问已释放对象报错）
	var e = _new_entity({is_player = false, life_total = 1})
	if e == null: return
	var f = _new_fade()
	if f == null: return
	f.bind(e)
	f._tick(1000)
	_assert(absf(e.modulate.a - 1.0) < 0.0001, "alpha 1.0 at start")
	e.free()
	f._tick(1100)
	_assert(f._bound == false, "silently unbound on freed target")


func _test_e4_fade_rebind() -> void:
	## E4: 重绑计时重置 —— bind A → tick 中途 → bind B → 计时重置（B alpha 从 1.0 重新开始）
	var ea = _new_entity({is_player = false, life_total = 1})
	var eb = _new_entity({is_player = false, life_total = 1})
	if ea == null or eb == null: return
	var f = _new_fade()
	if f == null: return
	f.bind(ea)
	f._tick(1000)
	f._tick(1150)
	_assert(absf(ea.modulate.a - 0.5) < 0.02, "A alpha ≈ 0.5 mid-fade (got %s)" % [ea.modulate.a])
	f.bind(eb)
	f._tick(1200)
	_assert(absf(eb.modulate.a - 1.0) < 0.0001, "B alpha restarts at 1.0 after rebind (got %s)" % [eb.modulate.a])


# ── Scenario F: 失败路径防回归 (PRD §5.3) ──────────────────────────────

func _test_f1_take_damage_red_line() -> void:
	## F1: take_damage 红线 —— execute 态 take_damage(999) → hp 不变、无 died（#575 既有守卫）
	var e = _new_entity({is_player = false, life_total = 1})
	if e == null: return
	e.died.connect(_on_died)
	e.break_stance()
	var r = e.request_transition("execute")
	_assert(r == true and e.state_name == "execute", "stance_break→execute legal (r=%s)" % r)
	var hp_before: float = e.hp_1
	e.take_damage(999.0)
	_assert(absf(e.hp_1 - hp_before) < 0.0001, "take_damage no-op in execute (red line) (got %s)" % [e.hp_1])
	_assert(_died_log.is_empty(), "no died via take_damage in execute")


func _test_f2_execute_kill_stop() -> void:
	## F2: execute_kill 停摆 —— died(true) 恰一次、二次 execute_kill no-op、revive 被拒、state 保持 execute
	var e = _new_entity({is_player = false, life_total = 1})
	if e == null: return
	if not _entity_has_method(e, "execute_kill"):
		_assert(false, "combat_entity.execute_kill() missing (TDD red phase)")
		return
	e.died.connect(_on_died)
	e.break_stance()
	e.request_transition("execute")
	e.execute_kill()
	_assert(_died_log.size() == 1 and _died_log[0] == true, "died(true) exactly once (got %s)" % [str(_died_log)])
	_assert(e.hp_1 == 0.0, "hp_1 zeroed by execute_kill (got %s)" % [e.hp_1])
	_assert(e.state_name == "execute", "state stays execute (got %s)" % e.state_name)
	e.execute_kill()
	_assert(_died_log.size() == 1, "second execute_kill no-op (got %d)" % _died_log.size())
	e.revive()
	_assert(e.state_name == "execute", "revive rejected after final dead (got %s)" % e.state_name)
	_assert(_died_log.size() == 1, "no second died from rejected revive")


func _test_f3_signal_leak_unbind() -> void:
	## F3: 信号泄漏 —— 敌人 died → 编排器自动 unbind（_enemy == null）→ 敌人 free 后 _process 无报错
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(_died_log.size() == 1, "trigger ran (sanity)")
	_assert(o._enemy == null, "enemy auto-unbound on died")
	e.free()
	o._process(1.0)
	_assert(true, "_process after unbind + free runs without error")


func _test_f4_no_feedback_bound() -> void:
	## F4: 无反馈绑定 → 触发处决静默跳过（不崩溃，仍完成杀敌）
	var pair = _setup_chain(0.0, 100.0, false)
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	e.died.connect(_on_died)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	o._on_attack_pressed()
	_assert(_died_log.size() == 1 and _died_log[0] == true, "execution completes without feedback (got %s)" % [str(_died_log)])


# ── Wiring: bind_judge / bind_input ────────────────────────────────────

func _test_w1_judge_single_source() -> void:
	## W1: bind_judge 单源（D3）—— judge.stance_broken 开启窗口；敌人直连已断开不重置计时
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	var judge = _MockJudge.new()
	o.bind_judge(judge)
	judge.stance_broken.emit(e)
	_assert(o._armed == true, "judge stance_broken arms window")
	o._process(1.0)
	_assert(absf(float(o._arm_elapsed) - 1.0) < 0.0001, "arm elapsed == 1.0 (got %s)" % [o._arm_elapsed])
	e.stance_broken.emit(e)
	_assert(absf(float(o._arm_elapsed) - 1.0) < 0.0001, "enemy direct emit does NOT reset elapsed (D3 single source) (got %s)" % [o._arm_elapsed])


func _test_w2_input_bind() -> void:
	## W2: bind_input 接线 —— mock_input.emit_attack() 触发处决（armed + 距离内）
	var pair = _setup_chain()
	if pair == null: return
	var o = pair[0]
	var e = pair[2]
	var fb = pair[3]
	e.died.connect(_on_died)
	var mi = _MockInput.new()
	o.bind_input(mi)
	e.break_stance()
	o._on_stance_broken(e)
	o._process(0.5)
	mi.emit_attack()
	_assert(e.state_name == "execute", "attack via bind_input triggers execute (got %s)" % e.state_name)
	_assert(_died_log.size() == 1 and _died_log[0] == true, "died(true) once via input (got %s)" % [str(_died_log)])
	_assert(fb.calls.size() == 1, "feedback triggered once via input (got %d)" % fb.calls.size())


class _MockFeedback:
	extends RefCounted
	var calls: Array = []

	func trigger_feedback(event: String, data: Dictionary = {}) -> void:
		calls.append([event, data])


class _MockJudge:
	extends RefCounted
	signal stance_broken


class _MockInput:
	extends RefCounted
	signal attack_pressed

	func emit_attack() -> void:
		attack_pressed.emit()

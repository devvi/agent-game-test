extends Object
## Test suite for ReviveOrchestrator + ReviveFX (#578) — 两条命原地复活系统。
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/578-two-life-revive.md §9 (Scenario A-G, T1-T24)
##
## TDD red phase: revive_orchestrator.gd / revive_fx.gd do NOT exist yet
## → runtime load() returns null → assertions fail (red) instead of parse error.
##
## Godot 4.7.1 --script 硬性约束 (同 test_combat_entity.gd / test_hud.gd):
##   - 禁止 := 类型推断 (4.7.1 视推断警告为硬错误) — 一律显式类型或普通 =
##   - class_name 可能无法解析 → 一律经 load()/preload 脚本资源访问
##   - 编排器纯逻辑 new + 手动 _process 推进（对齐 test_combat_entity _advance）
##   - FX 是 Node2D → 加入 root 触发 _ready 构建子节点；用例结束立即 free（防污染）
##   - 慢动作测试强制复原 Engine.time_scale = 1.0（全局状态，防跨用例污染）
##   - Tween 用 custom_step() 同步推进闪屏色值断言

var passed: int = 0
var failed: int = 0

# 信号记录
var _died_log: Array = []
var _revived_count: int = 0
var _state_log: Array = []

var root: Node = null


func run() -> void:
	print("\n=== ReviveOrchestrator Tests ===")
	_reset_logs()
	_test_t1_first_life_signal_contract()
	_reset_logs()
	_test_t2_auto_revive_timing()
	_reset_logs()
	_test_t3_not_revived_before_timeout()
	_reset_logs()
	_test_t4_enemy_not_bound()
	_reset_logs()
	_test_t5_revive_posture()
	_reset_logs()
	_test_t6_invincible_no_op()
	_reset_logs()
	_test_t7_invincible_expiry()
	_reset_logs()
	_test_t8_final_dead_contract()
	_reset_logs()
	_test_t9_contract_table_branches()
	_reset_logs()
	_test_t10_fx_nodes_and_constants()
	_test_t11_ink_burst()
	_test_t12_flash_tween()
	_test_t13_slowmo()
	_test_t14_invincible_flicker()
	_reset_logs()
	_test_t15_f_key_before_auto()
	_reset_logs()
	_test_t16_auto_before_f_key()
	_reset_logs()
	_test_t17_entity_freed_guard()
	_reset_logs()
	_test_t18_unbind_no_trigger()
	_reset_logs()
	_test_t19_rebind_idempotent()
	_test_t20_fx_nodes_missing()
	_test_t21_ink_texture_fallback()
	_test_t22_slowmo_overlap()
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
	_revived_count = 0
	_state_log = []


# ── helpers ─────────────────────────────────────────────────────────────

func _get_root() -> Node:
	if root == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		root = tree.root
	return root


func _new_entity(params: Dictionary):
	var s = load("res://gdscripts/combat_entity.gd")
	if s == null:
		_assert(false, "combat_entity.gd missing")
		return null
	var e = s.new(params)
	if e == null:
		_assert(false, "combat_entity.gd failed to instantiate")
	return e


func _new_orchestrator():
	var s = load("res://gdscripts/revive_orchestrator.gd")
	if s == null:
		_assert(false, "revive_orchestrator.gd missing (TDD red phase)")
		return null
	var o = s.new()
	if o == null:
		_assert(false, "revive_orchestrator.gd failed to instantiate")
	return o


func _new_fx():
	var s = load("res://gdscripts/revive_fx.gd")
	if s == null:
		_assert(false, "revive_fx.gd missing (TDD red phase)")
		return null
	var fx = s.new()
	if fx == null:
		_assert(false, "revive_fx.gd failed to instantiate")
	return fx


func _add_fx_to_tree(fx) -> void:
	_get_root().add_child(fx)


func _cleanup_fx(fx) -> void:
	if fx != null and is_instance_valid(fx):
		if fx.get_parent() != null:
			fx.get_parent().remove_child(fx)
		fx.free()


func _new_visual_root() -> Node2D:
	var v = Node2D.new()
	_get_root().add_child(v)
	return v


func _cleanup_node(n) -> void:
	if n != null and is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.free()


func _advance(o, frames: int, delta: float = 1.0 / 60.0) -> void:
	for i in range(frames):
		o._process(delta)


func _advance_both(o, e, frames: int, delta: float = 1.0 / 60.0) -> void:
	## 编排器与实体同步推进（实体 FSM 需要 _process 驱动 revive→idle 自动退出）
	for i in range(frames):
		o._process(delta)
		e._process(delta)


func _kill_player(e) -> void:
	## 第一条血归零 → died(final=false)
	e.died.connect(_on_died)
	e.revived.connect(_on_revived)
	e.state_changed.connect(_on_state_changed)
	e.take_damage(100.0)


func _on_died(ent, final: bool) -> void:
	_died_log.append(final)


func _on_revived(ent) -> void:
	_revived_count += 1


func _on_state_changed(from: String, to: String) -> void:
	_state_log.append([from, to])


# ── Scenario A: 编排主路径 (AC1) ────────────────────────────────────────

func _test_t1_first_life_signal_contract() -> void:
	## T1: 首血归零信号契约 —— died(final=false) 恰一次、state=="dead"、hp_1==0
	var e = _new_entity({is_player=true})
	if e == null: return
	_kill_player(e)
	_assert(_died_log.size() == 1 and _died_log[0] == false, "T1 died(final=false) emitted once (got %s)" % [str(_died_log)])
	_assert(e.state_name == "dead", "T1 state == dead (got %s)" % e.state_name)
	_assert(e.hp_1 == 0.0, "T1 hp_1 == 0")


func _test_t2_auto_revive_timing() -> void:
	## T2: 自动复活计时 —— died(false) 后 _armed==true；推进 60 帧(1.0s) → revive() 被调
	var e = _new_entity({is_player=true})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	_kill_player(e)
	_assert(o.is_armed() == true, "T2 orchestrator armed after died(false)")
	_advance_both(o, e, 61)
	_assert(e.state_name == "revive", "T2 dead→revive after 1.0s (got %s)" % e.state_name)
	_assert(e.hp_2 == 50.0, "T2 hp_2 == 50 (independent count, got %s)" % [e.hp_2])
	_assert(e.hp_1 == 0.0, "T2 hp_1 stays 0 (second life does not refill first)")
	_assert(o.is_armed() == false, "T2 orchestrator disarmed after revive")
	_assert(_revived_count == 1, "T2 revived emitted once (got %d)" % _revived_count)
	_advance_both(o, e, 61)
	_assert(e.state_name == "idle", "T2 revive auto-exits to idle (got %s)" % e.state_name)


func _test_t3_not_revived_before_timeout() -> void:
	## T3: 计时未到期不复活 —— 推进 30 帧(0.5s) → 仍 dead、无 revived
	var e = _new_entity({is_player=true})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	_kill_player(e)
	_advance_both(o, e, 30)
	_assert(e.state_name == "dead", "T3 still dead at 0.5s (got %s)" % e.state_name)
	_assert(_revived_count == 0, "T3 no revived before timeout")
	_assert(o.is_armed() == true, "T3 orchestrator still armed")


func _test_t4_enemy_not_bound() -> void:
	## T4: 敌人(life_total=1)不误绑 —— died(final=true) 不启动计时 → 无 revive
	var e = _new_entity({is_player=false, life_total=1, life_1_max=40.0})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	e.died.connect(_on_died)
	e.revived.connect(_on_revived)
	e.take_damage(40.0)
	_assert(_died_log.size() == 1 and _died_log[0] == true, "T4 enemy died(final=true) (got %s)" % [str(_died_log)])
	_assert(o.is_armed() == false, "T4 final=true does not arm orchestrator")
	_advance(o, 60)
	_assert(e.state_name == "dead", "T4 enemy stays dead (got %s)" % e.state_name)
	_assert(_revived_count == 0, "T4 no revive for enemy")


# ── Scenario B: 复活后无敌 + 架势清空 (AC2) ──────────────────────────────

func _revive_via_orchestrator():
	## 公共准备: 玩家被杀 → 编排器 60 帧自动复活 → 返回 [e, o]
	var e = _new_entity({is_player=true})
	if e == null: return null
	var o = _new_orchestrator()
	if o == null: return null
	o.bind_player(e)
	_kill_player(e)
	_advance_both(o, e, 61)
	return [e, o]


func _test_t5_revive_posture() -> void:
	## T5: 复活后姿态 —— stance==0、is_stance_broken==false（编排器路径）
	var pair = _revive_via_orchestrator()
	if pair == null: return
	var e = pair[0]
	_assert(e.state_name == "revive", "T5 revived (got %s)" % e.state_name)
	_assert(e.stance == 0.0, "T5 stance cleared after revive (got %s)" % [e.stance])
	_assert(e.is_stance_broken == false, "T5 stance broken flag cleared")


func _test_t6_invincible_no_op() -> void:
	## T6: 无敌期双伤害 no-op —— take_damage/take_stance_damage 均不生效
	var pair = _revive_via_orchestrator()
	if pair == null: return
	var e = pair[0]
	e.take_damage(999.0)
	e.take_stance_damage(999.0)
	_assert(e.hp_2 == 50.0, "T6 999 damage no-op during invincible (got %s)" % [e.hp_2])
	_assert(e.stance == 0.0, "T6 999 stance damage no-op during invincible (got %s)" % [e.stance])


func _test_t7_invincible_expiry() -> void:
	## T7: 无敌到期恢复 —— _invincible_until_sec 过期后受击正常扣血
	var pair = _revive_via_orchestrator()
	if pair == null: return
	var e = pair[0]
	var o = pair[1]
	e._invincible_until_sec = 0.0
	_advance_both(o, e, 61)
	_assert(e.state_name == "idle", "T7 back to idle (got %s)" % e.state_name)
	e.take_damage(10.0)
	_assert(e.hp_2 == 40.0, "T7 damage applies after invincibility (got %s)" % [e.hp_2])


# ── Scenario C: SW-015 契约 (AC3) ───────────────────────────────────────

func _test_t8_final_dead_contract() -> void:
	## T8: 终态契约 —— hp_2 归零 → died(final=true) 恰一次、_is_final_dead、
	##     后续 revive() 被拒、编排器不再计时
	var pair = _revive_via_orchestrator()
	if pair == null: return
	var e = pair[0]
	var o = pair[1]
	e._invincible_until_sec = 0.0
	_advance_both(o, e, 61)
	e.take_damage(50.0)
	_assert(e.state_name == "dead", "T8 hp_2 depleted → dead (got %s)" % e.state_name)
	_assert(e._is_final_dead == true, "T8 _is_final_dead set")
	_assert(_died_log.size() == 2 and _died_log[1] == true, "T8 died(final=true) as second emission (got %s)" % [str(_died_log)])
	_assert(o.is_armed() == false, "T8 final=true does not arm orchestrator")
	var revived_before: int = _revived_count
	e.revive()
	_assert(e.state_name == "dead", "T8 revive() rejected after final dead (got %s)" % e.state_name)
	_assert(_revived_count == revived_before, "T8 no revived after rejected revive")


func _test_t9_contract_table_branches() -> void:
	## T9: 契约表逐项 —— final=false 路径可复活（T2 断言）+ final=true 路径终态（T8 断言）互斥覆盖
	var e = _new_entity({is_player=true})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	_kill_player(e)
	_advance_both(o, e, 61)
	_assert(e.state_name == "revive" and _revived_count == 1, "T9 final=false branch: revivable (got %s, revived=%d)" % [e.state_name, _revived_count])
	_advance_both(o, e, 61)
	e._invincible_until_sec = 0.0
	e.take_damage(50.0)
	_assert(e._is_final_dead == true and _revived_count == 1, "T9 final=true branch: terminal (revived=%d)" % _revived_count)


# ── Scenario D: FX (AC4) ────────────────────────────────────────────────

func _constants_map() -> Dictionary:
	## 经 load() 取脚本资源再查常量表（对齐 test_constants.gd 模式: preload const 会解析为
	## WolfConstants 类本身，调用资源方法 get_script_constant_map() 触发 parse error）
	var s = load("res://gdscripts/constants.gd")
	if s == null:
		return {}
	return s.get_script_constant_map()


func _test_t10_fx_nodes_and_constants() -> void:
	## T10: 节点存在 + 零字面量 —— _ready 构建 InkBurst/FlashLayer；参数全部等于 constants
	var fx = _new_fx()
	if fx == null: return
	_add_fx_to_tree(fx)
	_assert(fx._ink_burst != null, "T10 InkBurst (GPUParticles2D) built in _ready")
	_assert(fx._flash_layer != null, "T10 FlashLayer (CanvasModulate) built in _ready")
	var cm: Dictionary = _constants_map()
	if fx._ink_burst != null:
		_assert(int(fx._ink_burst.amount) == int(cm.get("INK_BURST_COUNT", -1)), "T10 amount == INK_BURST_COUNT (got %s)" % [fx._ink_burst.amount])
		_assert(absf(fx._ink_burst.lifetime - float(cm.get("INK_BURST_LIFETIME", -1.0))) < 0.0001, "T10 lifetime == INK_BURST_LIFETIME (got %s)" % [fx._ink_burst.lifetime])
		_assert(fx._ink_burst.process_material != null, "T10 process_material built")
		if fx._ink_burst.process_material != null:
			_assert(absf(fx._ink_burst.process_material.spread - float(cm.get("INK_BURST_SPREAD_DEG", -1.0))) < 0.0001, "T10 spread(deg) == INK_BURST_SPREAD_DEG (got %s)" % [fx._ink_burst.process_material.spread])
			_assert(fx._ink_burst.process_material.color.is_equal_approx(cm.get("INK_BURST_COLOR", Color.WHITE)), "T10 color == INK_COLOR (got %s)" % [fx._ink_burst.process_material.color])

		_assert(fx._ink_burst.one_shot == true, "T10 one_shot == true")
	if fx._flash_layer != null:
		_assert(fx._flash_layer.color.is_equal_approx(cm.get("FLASH_WHITE", Color.WHITE)), "T10 flash initial color == FLASH_WHITE (got %s)" % [fx._flash_layer.color])
	_cleanup_fx(fx)


func _test_t11_ink_burst() -> void:
	## T11: 墨点 burst —— revived 触发 → emitting==true 且 one_shot；参数落 constants
	var fx = _new_fx()
	if fx == null: return
	_add_fx_to_tree(fx)
	var e = _new_entity({is_player=true})
	if e == null: return
	fx.bind_player(e)
	fx.bind_player_visual(_new_visual_root())
	e.take_damage(100.0)
	e.revive()
	_assert(fx._ink_burst.emitting == true, "T11 ink burst emitting after revived")
	_assert(fx._ink_burst.one_shot == true, "T11 one_shot burst semantics")
	_cleanup_fx(fx)


func _test_t12_flash_tween() -> void:
	## T12: 闪屏 Tween —— FLASH_WHITE → FLASH_BLOOD(FLASH_SECONDS) → 停留 → 复原 Color.WHITE（无残留）
	var fx = _new_fx()
	if fx == null: return
	_add_fx_to_tree(fx)
	var cm: Dictionary = _constants_map()
	var flash_seconds: float = float(cm.get("FLASH_SECONDS", 0.2))
	var hold_seconds: float = float(cm.get("FLASH_HOLD_SECONDS", 0.2))
	fx.trigger()
	_assert(fx._flash_tween != null, "T12 flash tween created")
	_assert(fx._flash_layer.color.is_equal_approx(cm.get("FLASH_WHITE", Color.WHITE)), "T12 starts from FLASH_WHITE (got %s)" % [fx._flash_layer.color])
	fx._flash_tween.custom_step(flash_seconds * 0.5)
	_assert(not fx._flash_layer.color.is_equal_approx(cm.get("FLASH_WHITE", Color.WHITE)), "T12 color animating toward blood (mid-step)")
	fx._flash_tween.custom_step(flash_seconds * 0.5)
	_assert(fx._flash_layer.color.is_equal_approx(cm.get("FLASH_BLOOD", Color.WHITE)), "T12 reaches FLASH_BLOOD after FLASH_SECONDS (got %s)" % [fx._flash_layer.color])
	fx._flash_tween.custom_step(hold_seconds)
	_assert(fx._flash_layer.color.is_equal_approx(cm.get("FLASH_BLOOD", Color.WHITE)), "T12 holds blood during FLASH_HOLD_SECONDS (got %s)" % [fx._flash_layer.color])
	fx._flash_tween.custom_step(flash_seconds)
	_assert(fx._flash_layer.color.is_equal_approx(Color.WHITE), "T12 restores Color.WHITE — no residue (#582 coexistence) (got %s)" % [fx._flash_layer.color])
	_cleanup_fx(fx)


func _test_t13_slowmo() -> void:
	## T13: 慢动作 —— trigger 后 Engine.time_scale==SLOWMO_COEFF；到期恢复 1.0
	var fx = _new_fx()
	if fx == null: return
	_add_fx_to_tree(fx)
	var cm: Dictionary = _constants_map()
	var coeff: float = float(cm.get("SLOWMO_COEFF", 0.2))
	fx.trigger()
	_assert(absf(Engine.time_scale - coeff) < 0.0001, "T13 time_scale == SLOWMO_COEFF (got %s)" % [Engine.time_scale])
	fx._slowmo_until_sec = 0.0
	fx._process(1.0 / 60.0)
	_assert(absf(Engine.time_scale - 1.0) < 0.0001, "T13 time_scale restored to 1.0 after SLOWMO_HOLD_SECONDS (got %s)" % [Engine.time_scale])
	_cleanup_fx(fx)
	Engine.time_scale = 1.0


func _test_t14_invincible_flicker() -> void:
	## T14: 无敌闪烁 —— modulate.a 在 [ALPHA_MIN, 1.0] 按 HZ 循环；INVINCIBLE_SECONDS 到期复原 1.0
	var fx = _new_fx()
	if fx == null: return
	_add_fx_to_tree(fx)
	var cm: Dictionary = _constants_map()
	var alpha_min: float = float(cm.get("INVINCIBLE_FLICKER_ALPHA_MIN", 0.3))
	var inv_sec: float = float(cm.get("INVINCIBLE_SECONDS", 1.0))
	var visual = _new_visual_root()
	fx.bind_player_visual(visual)
	fx.trigger()
	_assert(fx._flicker_active == true, "T14 flicker active after trigger")
	# 谷值: phase = π/2 → |sin|=1 → alpha == ALPHA_MIN（1/(4*HZ) 秒处）
	fx._process(1.0 / (4.0 * float(cm.get("INVINCIBLE_FLICKER_HZ", 8.0))))
	_assert(absf(visual.modulate.a - alpha_min) < 0.01, "T14 valley alpha == ALPHA_MIN (got %s)" % [visual.modulate.a])
	# 峰值: 过谷后回升（1/(2*HZ) 秒处）
	fx._process(1.0 / (4.0 * float(cm.get("INVINCIBLE_FLICKER_HZ", 8.0))))
	_assert(absf(visual.modulate.a - 1.0) < 0.01, "T14 peak alpha back to 1.0 (got %s)" % [visual.modulate.a])
	# 到期复原
	fx._process(inv_sec + 0.1)
	_assert(fx._flicker_active == false, "T14 flicker ends after INVINCIBLE_SECONDS")
	_assert(absf(visual.modulate.a - 1.0) < 0.0001, "T14 alpha restored to 1.0 (got %s)" % [visual.modulate.a])
	_cleanup_fx(fx)
	_cleanup_node(visual)
	Engine.time_scale = 1.0


# ── Scenario E: 双路径兼容 (边界 3) ─────────────────────────────────────

func _test_t15_f_key_before_auto() -> void:
	## T15: F 键先于自动计时 —— 手动 revive() 先触发 → 编排器取消 pending → 到期不再二次调
	var e = _new_entity({is_player=true})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	_kill_player(e)
	e.revive()  # 模拟 F 键手动路径
	_assert(_revived_count == 1, "T15 manual revive emitted once (got %d)" % _revived_count)
	_assert(o.is_armed() == false, "T15 orchestrator cancelled pending on revived")
	_advance(o, 60)
	_assert(_revived_count == 1, "T15 no second revive from orchestrator (got %d)" % _revived_count)
	_assert(e.state_name == "revive", "T15 state == revive (got %s)" % e.state_name)


func _test_t16_auto_before_f_key() -> void:
	## T16: 自动先触发后手动重入 —— 编排器到期 revive() 成功 → 手动 revive() 同态重入
	##     静默返回（无 state_changed 二次广播；编排器不再驱动）
	var e = _new_entity({is_player=true})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	_kill_player(e)
	_advance_both(o, e, 61)
	_assert(_revived_count == 1 and e.state_name == "revive", "T16 auto revive fired (revived=%d state=%s)" % [_revived_count, e.state_name])
	_assert(_state_log.size() == 2, "T16 exactly 2 state_changed so far (got %d)" % _state_log.size())
	var count_after_auto: int = _revived_count
	e.revive()  # 同态重入（F 键再按）
	_assert(e.state_name == "revive", "T16 same-state re-entry keeps revive (got %s)" % e.state_name)
	_assert(_state_log.size() == 2, "T16 no state_changed re-broadcast on same-state (got %d)" % _state_log.size())
	_assert(o.is_armed() == false, "T16 orchestrator stays disarmed")
	var count_after_manual: int = _revived_count
	_advance(o, 60)
	_assert(_revived_count == count_after_manual, "T16 orchestrator adds no further revive (got %d)" % _revived_count)
	_assert(count_after_manual <= count_after_auto + 1, "T16 at most one extra emission from manual re-entry (entity semantics, #575 read-only)")


# ── Scenario F: 边界与失败 (§5) ─────────────────────────────────────────

func _test_t17_entity_freed_guard() -> void:
	## T17: 实体销毁守卫 —— 计时期间 entity.free() → 到期 is_instance_valid 守卫静默跳过
	var e = _new_entity({is_player=true})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	e.died.connect(_on_died)
	e.take_damage(100.0)
	_assert(o.is_armed() == true, "T17 armed before free")
	e.free()
	_advance(o, 61)
	_assert(o.is_armed() == false, "T17 disarmed after expiry (freed entity skipped, no crash)")


func _test_t18_unbind_no_trigger() -> void:
	## T18: unbind 后不触发 —— unbind_player() 后 died(false) 不启动计时
	var e = _new_entity({is_player=true})
	if e == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(e)
	o.unbind_player()
	e.died.connect(_on_died)
	e.take_damage(100.0)
	_assert(e.state_name == "dead", "T18 entity still dies")
	_assert(o.is_armed() == false, "T18 orchestrator not armed after unbind")
	_advance(o, 60)
	_assert(_revived_count == 0, "T18 no revive after unbind")


func _test_t19_rebind_idempotent() -> void:
	## T19: 重复 bind 幂等 —— bind A → bind B → A 的 died 不触发，B 的正常触发
	var ea = _new_entity({is_player=true})
	var eb = _new_entity({is_player=true})
	if ea == null or eb == null: return
	var o = _new_orchestrator()
	if o == null: return
	o.bind_player(ea)
	o.bind_player(eb)
	ea.died.connect(_on_died)
	eb.died.connect(_on_died)
	eb.revived.connect(_on_revived)
	ea.take_damage(100.0)
	_assert(o.is_armed() == false, "T19 old entity died does not arm (unbound)")
	eb.take_damage(100.0)
	_assert(o.is_armed() == true, "T19 new entity died arms orchestrator")
	_advance(o, 61)
	_assert(eb.state_name == "revive", "T19 B revived (got %s)" % eb.state_name)
	_assert(ea.state_name == "dead", "T19 A stays dead (got %s)" % ea.state_name)
	_assert(_revived_count == 1, "T19 exactly one revive (got %d)" % _revived_count)


func _test_t20_fx_nodes_missing() -> void:
	## T20: FX 节点缺失 —— 未入树（_ready 未跑，子节点 null）时 trigger() no-op 不崩溃
	var fx = _new_fx()
	if fx == null: return
	fx.trigger()  # _ink_burst/_flash_layer 均为 null → 必须降级不崩溃
	fx._process(1.0 / 60.0)
	_assert(true, "T20 trigger no-op without crash when nodes missing")
	Engine.time_scale = 1.0


func _test_t21_ink_texture_fallback() -> void:
	## T21: texture 生成失败降级 —— _build_ink_texture() 正常返回 Texture2D；
	##     texture 缺失时 trigger 仍完成（默认方形粒子降级，复活链路不受阻）
	var fx = _new_fx()
	if fx == null: return
	_add_fx_to_tree(fx)
	var tex = fx._build_ink_texture()
	_assert(tex != null, "T21 _build_ink_texture returns Texture2D")
	fx._ink_burst.texture = null  # 模拟生成失败
	fx.trigger()
	_assert(fx._ink_burst.emitting == true, "T21 trigger completes with null texture (degraded default particles)")
	_cleanup_fx(fx)
	Engine.time_scale = 1.0


func _test_t22_slowmo_overlap() -> void:
	## T22: 慢动作重叠 —— 两次 trigger 间隔 < SLOWMO_HOLD_SECONDS → 不嵌套破坏；末次到期恢复 1.0
	var fx = _new_fx()
	if fx == null: return
	_add_fx_to_tree(fx)
	var cm: Dictionary = _constants_map()
	var coeff: float = float(cm.get("SLOWMO_COEFF", 0.2))
	fx.trigger()
	_assert(absf(Engine.time_scale - coeff) < 0.0001, "T22 first trigger slows to coeff (got %s)" % [Engine.time_scale])
	var t1: float = fx._slowmo_until_sec
	fx.trigger()
	_assert(absf(Engine.time_scale - coeff) < 0.0001, "T22 overlap keeps coeff (got %s)" % [Engine.time_scale])
	_assert(fx._slowmo_set == true, "T22 slowmo still set (no nested restore)")
	_assert(fx._slowmo_until_sec >= t1, "T22 deadline extended by second trigger")
	fx._slowmo_until_sec = 0.0
	fx._process(1.0 / 60.0)
	_assert(absf(Engine.time_scale - 1.0) < 0.0001, "T22 restored to 1.0 once at end (got %s)" % [Engine.time_scale])
	_cleanup_fx(fx)
	Engine.time_scale = 1.0

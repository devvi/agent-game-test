extends Object
## Test suite for Hud (#576) — 两段式血条 / 玩家与敌人架势条 / 击杀与处决提示。
## Runs under godot --headless --script via run_tests.gd.
## Design: docs/DESIGN/576-hud-stance-bars.md §8 (Scenario A-F, T1-T28)
## 增量: docs/DESIGN/684-boss-hp-bar-ui.md §8（场景 A-D，#684）—— 敌人名字 Label /
##   架势崩解条级闪白 / Boss-杂兵分档三态显隐 / died 名字联动。
##
## TDD red phase: hud.gd does NOT exist yet → runtime load() returns null
## → assertions fail (red) instead of whole-file parse error.
##   #684 红期: hud.gd 已存在（#695），#684 新 API（EnemyNameLabel / set_boss_mode /
##     set_break_flash 等）未实现 → 经 hud.get()/has_method() 守卫访问（红期记一条 FAIL，
##     非 SCRIPT ERROR——CI grep 防误伤；中断路径仍 cleanup 防泄漏污染后续套件）。
##
## Godot 4.7.1 --script 硬性约束 (同 test_combat_entity.gd):
##   - 禁止 := 类型推断 (4.7.1 视推断警告为硬错误) — 一律显式类型或普通 =
##   - hud.gd 缺失红期 → 运行时 load() 惰性解析；combat_entity.gd 已存在 → preload
##   - HUD 常量（HUD_* 尚未入库）一律用字面值 100/50/240/10/6/0.30/3.0/1.5/16/12
##   - Hud 是 CanvasLayer → _spawn_hud 加入 root 触发 _ready/_exit_tree；
##     _cleanup_hud 立即 free（防 hud group 污染后续用例）
##   - _HudBar 内部状态/方法经无类型局部变量鸭子访问（避免 UNSAFE_METHOD_ACCESS 警告）
##   - Timer 手动 emit timeout；Tween 用 custom_step(0.5) 同步推进淡出
##   - 测试契约（实现必须暴露，本套件同步推进依赖）:
##       _HudBar.get_segment_fractions() / get_segment_shares() / get_active_index()
##       Hud._execute_hint_tween / _kill_hint_tween（Tween 淡出可同步推进）

const CombatEntityScript = preload("res://gdscripts/combat_entity.gd")

var passed: int = 0
var failed: int = 0

var root: Node = null
var _low_hp_log: Array = []


func run() -> void:
	print("\n=== Hud Tests ===")
	_test_t1_layout_anchors()
	_test_t2_two_segment_structure()
	_test_t3_active_segment()
	_test_t4_player_stance_bar()
	_test_t5_enemy_stance_bar_layout()
	_test_t6_low_hp_below_threshold()
	_test_t7_low_hp_at_threshold()
	_test_t8_low_hp_edge_recovery()
	_test_t9_low_hp_half_bar()
	_test_t10_low_hp_visual_mode()
	_test_t11_enemy_bar_target()
	_test_t12_enemy_bar_null_target()
	_test_t13_enemy_bar_switch_target()
	_test_t14_enemy_bar_idempotent_inject()
	_test_t15_execute_hint_show()
	_test_t16_execute_hint_hide_after_timeout()
	_test_t17_execute_hint_reset()
	_test_t18_kill_hint_show()
	_test_t19_kill_hint_hide_after_timeout()
	_test_t20_died_non_final()
	_test_t21_player_attack_hides_execute()
	_test_t22_revive_switch()
	_test_t23_player_death_revive()
	_test_t24_low_hp_recovery_on_revive()
	_test_t25_static_no_textures()
	_test_t26_static_no_polling()
	_test_t27_singleton_guard()
	_test_t28_invalid_numbers()
	# Scenario B(#682): EnemyHealthBar（Boss 条组合，AC6, DESIGN §8 Scenario B）
	_test_b1_enemy_health_bar_visible()
	_test_b2_enemy_health_bar_layout()
	_test_b3_enemy_health_bar_hp_changed()
	_test_b4_enemy_health_bar_hide()
	_test_b5_player_bars_fill_override_off()
	# Scenario A/B/C/D(#684): 敌人名字 Label / 架势崩解闪白 / Boss-杂兵分档 / died 名字联动
	_test_a1_name_label_layout()
	_test_a2_boss_shows_name()
	_test_a3_minion_hides_name()
	_test_a4_empty_name_hides()
	_test_a5_long_name_overrun()
	_test_a6_null_target_clears_name()
	_test_b1_stance_break_flash_on()
	_test_b2_stance_break_flash_fades()
	_test_b3_stance_break_data_path_unaffected()
	_test_b4_stance_break_flash_cleared_on_died()
	_test_b5_player_stance_bar_never_flashes()
	_test_b6_debug_stance_break()
	_test_c1_tier_then_inject()
	_test_c2_inject_then_tier()
	_test_c3_boss_tier_toggle()
	_test_c4_boss_tier_idempotent()
	_test_c5_boss_tier_null_target()
	_test_d3_died_final_hides_name()
	_test_d4_died_non_final_clears_name()
	print("Passed: %d, Failed: %d" % [passed, failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % msg)
		failed += 1


func _get_root() -> Node:
	if root == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		root = tree.root
	return root


# ── helpers ─────────────────────────────────────────────────────────────

func _spawn_hud():
	## 运行时 load（TDD 红期 hud.gd 缺失 → 返回 null，调用方 guard）
	var s = load("res://gdscripts/hud.gd")
	if s == null:
		_assert(false, "hud.gd missing (TDD red phase)")
		return null
	var hud = s.new()
	if hud == null:
		_assert(false, "hud.gd failed to instantiate")
		return null
	_get_root().add_child(hud)
	return hud


func _cleanup_hud(hud) -> void:
	if hud == null:
		return
	hud.remove_from_group("hud")
	if hud.is_inside_tree():
		_get_root().remove_child(hud)
	hud.free()


func _spawn_entity(params: Dictionary):
	var e = CombatEntityScript.new(params)
	if e == null:
		_assert(false, "combat_entity.gd failed to instantiate")
		return null
	_get_root().add_child(e)
	return e


func _cleanup_entity(e) -> void:
	if e == null:
		return
	if e.is_inside_tree():
		_get_root().remove_child(e)
	e.free()


func _on_low_health(enabled: bool) -> void:
	_low_hp_log.append(enabled)


# ── Scenario A: 布局与两段式血条结构 (AC1) ──────────────────────────────

func _test_t1_layout_anchors() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	_assert(hud.PlayerBarGroup.position == Vector2(16, 16), "T1: PlayerBarGroup at (16,16) = HUD_PLAYER_MARGIN")
	_assert(hud.PlayerHealthBar.size == Vector2(240, 10), "T1: PlayerHealthBar size (240,10) = HUD_BAR_WIDTH x HUD_BAR_HEIGHT")
	var bar = hud.PlayerHealthBar
	var r: Rect2 = bar.get_global_rect()
	_assert(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= 1280.0 and r.end.y <= 720.0, "T1: health bar fully visible in 1280x720 viewport")
	_cleanup_hud(hud)


func _test_t2_two_segment_structure() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	hud.set_debug_hp(100, 50, 1)
	var bar = hud.PlayerHealthBar
	var shares: Array = bar.get_segment_shares()
	_assert(shares.size() == 2 and absf(shares[0] / shares[1] - 2.0) < 0.001, "T2: segment width shares ratio 2:1 (100:50, got %s)" % [str(shares)])
	var f: Array = bar.get_segment_fractions()
	_assert(f.size() == 2 and absf(f[0] - 1.0) < 0.001 and absf(f[1] - 1.0) < 0.001, "T2: set_debug_hp(100,50,1) → fractions [1,1] (got %s)" % [str(f)])
	hud.set_debug_hp(50, 50, 1)
	var f2: Array = bar.get_segment_fractions()
	_assert(f2.size() == 2 and absf(f2[0] - 0.5) < 0.001 and absf(f2[1] - 1.0) < 0.001, "T2: set_debug_hp(50,50,1) → fractions [0.5,1.0] (got %s)" % [str(f2)])
	_cleanup_hud(hud)


func _test_t3_active_segment() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	hud.set_debug_hp(100, 50, 1)
	var bar = hud.PlayerHealthBar
	_assert(bar.get_active_index() == 0, "T3: active_life=1 → active segment 1 (index 0)")
	hud.set_debug_hp(100, 50, 2)
	_assert(bar.get_active_index() == 1, "T3: active_life=2 → active segment 2 (index 1)")
	_cleanup_hud(hud)


func _test_t4_player_stance_bar() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var bar = hud.PlayerStanceBar
	_assert(absf(bar.position.y - 16.0) < 0.001, "T4: PlayerStanceBar 6px below health bar (10 height + 6 gap → y=16)")
	_assert(bar.size == Vector2(240, 6), "T4: PlayerStanceBar size (240,6) = HUD_BAR_WIDTH x HUD_STANCE_HEIGHT")
	_cleanup_hud(hud)


func _test_t5_enemy_stance_bar_layout() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var bar = hud.EnemyStanceBar
	_assert(absf(bar.anchor_left - 0.5) < 0.001 and absf(bar.anchor_right - 0.5) < 0.001, "T5: EnemyStanceBar anchored top-center (anchor 0.5)")
	_assert(bar.size == Vector2(240, 6), "T5: EnemyStanceBar size (240,6) = HUD_ENEMY_BAR_WIDTH x HUD_STANCE_HEIGHT")
	_assert(absf(bar.offset_top - 26.0) < 0.001, "T5: EnemyStanceBar top offset 26 = HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT + HUD_ENEMY_HP_GAP (#682 血条占位下移)")
	_assert(bar.visible == false, "T5: EnemyStanceBar hidden without set_target_enemy")
	_cleanup_hud(hud)


# ── Scenario B: 低血信号边沿 (AC2) ──────────────────────────────────────

func _test_t6_low_hp_below_threshold() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	_low_hp_log = []
	hud.low_health_changed.connect(_on_low_health)
	hud.set_debug_hp(29.9, 50, 1)
	_assert(_low_hp_log.size() == 1 and _low_hp_log[0] == true, "T6: 29.9%% (< 30%%-0.001) → exactly one low_health_changed(true) (got %s)" % [str(_low_hp_log)])
	_cleanup_hud(hud)


func _test_t7_low_hp_at_threshold() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	_low_hp_log = []
	hud.low_health_changed.connect(_on_low_health)
	hud.set_debug_hp(30.0, 50, 1)
	_assert(_low_hp_log.is_empty(), "T7: 30.0%% (≥ 30%%-0.001) → zero emissions (got %s)" % [str(_low_hp_log)])
	_cleanup_hud(hud)


func _test_t8_low_hp_edge_recovery() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	_low_hp_log = []
	hud.low_health_changed.connect(_on_low_health)
	hud.set_debug_hp(30.0, 50, 1)
	hud.set_debug_hp(29.9, 50, 1)
	hud.set_debug_hp(30.0, 50, 1)
	hud.set_debug_hp(30.0, 50, 1)
	_assert(_low_hp_log.size() == 2, "T8: edge 30→29.9(true)→30(false)→30(no re-emit) → count==2 (got %s)" % [str(_low_hp_log)])
	_assert(_low_hp_log.size() == 2 and _low_hp_log[0] == true and _low_hp_log[1] == false, "T8: sequence exactly [true, false] (got %s)" % [str(_low_hp_log)])
	_cleanup_hud(hud)


func _test_t9_low_hp_half_bar() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	_low_hp_log = []
	hud.low_health_changed.connect(_on_low_health)
	hud.set_debug_hp(0, 14.9, 2)
	_assert(_low_hp_log.size() == 1 and _low_hp_log[0] == true, "T9: active_life=2 @ 14.9/50 (< 15) → true (got %s)" % [str(_low_hp_log)])
	hud.set_debug_hp(0, 15.0, 2)
	_assert(_low_hp_log.size() == 2 and _low_hp_log[1] == false, "T9: active_life=2 @ 15.0/50 (= 15) → false (got %s)" % [str(_low_hp_log)])
	_cleanup_hud(hud)


func _test_t10_low_hp_visual_mode() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	hud.set_debug_hp(29.9, 50, 1)
	var bar = hud.PlayerHealthBar
	_assert(bar._low_hp_mode == true, "T10: low-hp state → _HudBar._low_hp_mode == true (blood-red active segment)")
	hud.set_debug_hp(100, 50, 1)
	_assert(bar._low_hp_mode == false, "T10: recovered → _low_hp_mode returns false")
	_cleanup_hud(hud)


# ── Scenario C: 敌人架势条显隐 (target_enemy) ───────────────────────────

func _test_t11_enemy_bar_target() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	_assert(hud.EnemyStanceBar.visible == true, "T11: EnemyStanceBar visible after set_target_enemy")
	enemy.take_stance_damage(40.0)
	var bar = hud.EnemyStanceBar
	var f: Array = bar.get_segment_fractions()
	_assert(f.size() == 1 and absf(f[0] - 0.6) < 0.001, "T11: enemy stance 60/100 → fraction 0.6 (got %s)" % [str(f)])
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t12_enemy_bar_null_target() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	enemy.take_stance_damage(40.0)
	hud.set_target_enemy(null)
	_assert(hud.EnemyStanceBar.visible == false, "T12: EnemyStanceBar hidden after set_target_enemy(null)")
	var bar = hud.EnemyStanceBar
	var before: Array = bar.get_segment_fractions()
	enemy.take_stance_damage(30.0)
	var after: Array = bar.get_segment_fractions()
	_assert(before == after, "T12: old enemy stance_changed no longer affects bar after null (before %s after %s)" % [str(before), str(after)])
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t13_enemy_bar_switch_target() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy1 = _spawn_entity({is_player=false, life_total=1})
	var enemy2 = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy1)
	enemy1.take_stance_damage(40.0)
	hud.set_target_enemy(enemy2)
	var bar = hud.EnemyStanceBar
	enemy1.take_stance_damage(30.0)
	var f: Array = bar.get_segment_fractions()
	_assert(f.size() == 1 and absf(f[0] - 1.0) < 0.001, "T13: old target signal ignored after switch (bar stays at new target init 1.0, got %s)" % [str(f)])
	enemy2.take_stance_damage(20.0)
	var f2: Array = bar.get_segment_fractions()
	_assert(f2.size() == 1 and absf(f2[0] - 0.8) < 0.001, "T13: new target signal drives bar 80/100 → 0.8 (got %s)" % [str(f2)])
	_cleanup_hud(hud)
	_cleanup_entity(enemy1)
	_cleanup_entity(enemy2)


func _test_t14_enemy_bar_idempotent_inject() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	hud.set_target_enemy(enemy)
	var conns: Array = enemy.stance_changed.get_connections()
	_assert(conns.size() == 1, "T14: repeated injection → single stance_changed subscription (got %d)" % conns.size())
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


# ── Scenario D: 提示文字（处决 / 击杀 / 竞争）────────────────────────────

func _test_t15_execute_hint_show() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	enemy.take_stance_damage(100.0)
	_assert(hud.ExecutePromptLabel.visible == true, "T15: stance_broken → ExecutePromptLabel visible")
	_assert(hud.ExecutePromptLabel.text.length() > 0, "T15: execute hint text non-empty (got '%s')" % hud.ExecutePromptLabel.text)
	_assert(absf(hud._execute_hint_timer.time_left - 3.0) < 0.001, "T15: execute hint timer ≈ 3.0s = STANCE_BREAK_RECOVERY_SEC (got %s)" % hud._execute_hint_timer.time_left)
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t16_execute_hint_hide_after_timeout() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	enemy.take_stance_damage(100.0)
	hud._execute_hint_timer.timeout.emit()
	var tw = hud._execute_hint_tween
	if tw != null:
		tw.custom_step(0.5)
	var hidden: bool = hud.ExecutePromptLabel.visible == false or hud.ExecutePromptLabel.modulate.a <= 0.01
	_assert(hidden, "T16: execute hint hidden after timer timeout + fade-out step")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t17_execute_hint_reset() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	enemy.take_stance_damage(100.0)
	_assert(absf(hud._execute_hint_timer.time_left - 3.0) < 0.001, "T17: first break → timer at 3.0s")
	enemy.stance_broken.emit(enemy)
	_assert(hud.ExecutePromptLabel.visible == true, "T17: repeated stance_broken keeps hint visible (no flicker)")
	_assert(absf(hud._execute_hint_timer.time_left - 3.0) < 0.001, "T17: repeated stance_broken resets timer to 3.0s (got %s)" % hud._execute_hint_timer.time_left)
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t18_kill_hint_show() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	enemy.take_stance_damage(100.0)
	enemy.die()
	_assert(hud.KillPromptLabel.visible == true, "T18: died(final=true) → KillPromptLabel visible")
	_assert(hud.KillPromptLabel.text.length() > 0, "T18: kill hint text non-empty (got '%s')" % hud.KillPromptLabel.text)
	_assert(hud.ExecutePromptLabel.visible == false, "T18: execute hint immediately hidden (kill > execute)")
	_assert(hud.EnemyStanceBar.visible == false, "T18: enemy stance bar hidden on kill")
	_assert(absf(hud._kill_hint_timer.time_left - 1.5) < 0.001, "T18: kill hint timer ≈ 1.5s = HUD_KILL_HINT_SECONDS (got %s)" % hud._kill_hint_timer.time_left)
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t19_kill_hint_hide_after_timeout() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.set_target_enemy(enemy)
	enemy.die()
	hud._kill_hint_timer.timeout.emit()
	var tw = hud._kill_hint_tween
	if tw != null:
		tw.custom_step(0.5)
	var hidden: bool = hud.KillPromptLabel.visible == false or hud.KillPromptLabel.modulate.a <= 0.01
	_assert(hidden, "T19: kill hint hidden after timer timeout + fade-out step")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t20_died_non_final() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=2})
	hud.set_target_enemy(enemy)
	enemy.take_stance_damage(100.0)
	_assert(hud.ExecutePromptLabel.visible == true, "T20: precondition — execute hint visible")
	enemy.die()
	_assert(hud.KillPromptLabel.visible == false, "T20: died(final=false) → no kill prompt")
	_assert(hud.ExecutePromptLabel.visible == false, "T20: died(final=false) → execute hint hidden")
	var bar = hud.EnemyStanceBar
	var f: Array = bar.get_segment_fractions()
	_assert(f.size() >= 1 and absf(f[0] - 0.0) < 0.001, "T20: died(final=false) → enemy stance bar cleared to 0.0 (got %s)" % [str(f)])
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_t21_player_attack_hides_execute() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var player = _spawn_entity({is_player=true, life_total=2})
	var enemy = _spawn_entity({is_player=false, life_total=1})
	hud.bind_player(player)
	hud.set_target_enemy(enemy)
	enemy.take_stance_damage(100.0)
	_assert(hud.ExecutePromptLabel.visible == true, "T21: precondition — execute hint visible")
	var r = player.request_transition("attack")
	_assert(r == true, "T21: player idle→attack legal (request accepted)")
	_assert(hud.ExecutePromptLabel.visible == false, "T21: player attack → execute hint immediately hidden")
	_cleanup_hud(hud)
	_cleanup_entity(player)
	_cleanup_entity(enemy)


# ── Scenario E: 回生 / 死亡 / 复活 ──────────────────────────────────────

func _test_t22_revive_switch() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	hud.set_debug_hp(0, 50, 2)
	var bar = hud.PlayerHealthBar
	var f: Array = bar.get_segment_fractions()
	_assert(f.size() == 2 and absf(f[0] - 0.0) < 0.001 and absf(f[1] - 1.0) < 0.001, "T22: revive switch (0,50,2) → fractions [0.0,1.0] (got %s)" % [str(f)])
	_assert(bar.get_active_index() == 1, "T22: active segment switches to 2nd (index 1)")
	_assert(hud.PlayerHealthBar.size == Vector2(240, 10), "T22: bar container size unchanged (no jump)")
	_cleanup_hud(hud)


func _test_t23_player_death_revive() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	var player = _spawn_entity({is_player=true, life_total=2})
	hud.bind_player(player)
	# die() 不清零 hp_1（#575 契约）→ 先 take_damage 归零；真实死亡路径 =
	# take_damage 归零 → die() → revive() → hp_changed(0,50,2)
	player.take_damage(100.0)
	player.die()
	_assert(hud.KillPromptLabel.visible == false, "T23: player died(final=false) → no kill prompt, no crash")
	player.revive()
	var bar = hud.PlayerHealthBar
	var f: Array = bar.get_segment_fractions()
	_assert(f.size() == 2 and absf(f[0] - 0.0) < 0.001 and absf(f[1] - 1.0) < 0.001, "T23: revive() → hp_changed(0,50,2) restores seg2 full (got %s)" % [str(f)])
	_cleanup_hud(hud)
	_cleanup_entity(player)


func _test_t24_low_hp_recovery_on_revive() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	_low_hp_log = []
	hud.low_health_changed.connect(_on_low_health)
	hud.set_debug_hp(29.9, 50, 1)
	_assert(_low_hp_log.size() == 1 and _low_hp_log[0] == true, "T24: precondition — low hp true")
	hud.set_debug_hp(0, 50, 2)
	_assert(_low_hp_log.size() == 2 and _low_hp_log[1] == false, "T24: revive ratio 1.0 → exactly one low_health_changed(false) (got %s)" % [str(_low_hp_log)])
	_cleanup_hud(hud)


# ── Scenario F: 静态断言 (AC4 + TF-1 零轮询) ────────────────────────────

func _test_t25_static_no_textures() -> void:
	var src: String = FileAccess.get_file_as_string("res://gdscripts/hud.gd")
	_assert(src != "", "T25: hud.gd exists and is readable (TDD red phase: missing)")
	_assert(src.find(".png") == -1 and src.find(".jpg") == -1 and src.find("Texture2D") == -1 and src.find("Image") == -1 and src.find("TextureProgressBar") == -1, "T25: hud.gd uses zero textures/images (no png/jpg/Texture2D/Image/TextureProgressBar)")


func _test_t26_static_no_polling() -> void:
	var src: String = FileAccess.get_file_as_string("res://gdscripts/hud.gd")
	_assert(src != "", "T26: hud.gd exists and is readable (TDD red phase: missing)")
	_assert(src.find("_process(") == -1 and src.find("_physics_process(") == -1, "T26: hud.gd has zero _process/_physics_process polling")


func _test_t27_singleton_guard() -> void:
	var hud1 = _spawn_hud()
	if hud1 == null: return
	var hud2 = _spawn_hud()
	if hud2 == null:
		_cleanup_hud(hud1)
		return
	_assert(hud2.is_queued_for_deletion(), "T27: second Hud instance queue_frees itself (singleton guard on 'hud' group)")
	_cleanup_hud(hud2)
	_cleanup_hud(hud1)


func _test_t28_invalid_numbers() -> void:
	var hud = _spawn_hud()
	if hud == null: return
	hud.set_debug_hp(-5, 50, 1)
	var bar = hud.PlayerHealthBar
	var f: Array = bar.get_segment_fractions()
	var ok1: bool = true
	for v in f:
		if not is_finite(v) or v < 0.0 or v > 1.0:
			ok1 = false
	_assert(ok1, "T28: set_debug_hp(-5,50,1) → fractions finite and clamped to [0,1] (got %s)" % [str(f)])
	hud.set_debug_hp(NAN, 50, 1)
	var f2: Array = bar.get_segment_fractions()
	var ok2: bool = true
	for v in f2:
		if not is_finite(v) or v < 0.0 or v > 1.0:
			ok2 = false
	_assert(ok2, "T28: set_debug_hp(NAN,50,1) → fractions finite and clamped to [0,1] (got %s)" % [str(f2)])
	_cleanup_hud(hud)


# ── Scenario B(#682): EnemyHealthBar（Boss 条组合，AC6）────────────────────
## 血条+架势条顶部组合: EnemyHealthBar(240×10 暗红) 在 EnemyStanceBar 上方；
##   新常量 HUD_ENEMY_HP_GAP 实现期才加入 constants.gd → 布局断言用字面值 26（=12+10+4），
##   既有 T5 断言已同步 12 → 26。EnemyHealthBar/_HudBar 新成员经无类型局部变量鸭子访问。

func _test_b1_enemy_health_bar_visible() -> void:
	## B1 注入可见: set_target_enemy 后 EnemyHealthBar/EnemyStanceBar 双条可见 + 同锚点 0.5
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	_assert(hud.EnemyHealthBar.visible == false, "B1: EnemyHealthBar hidden before set_target_enemy")
	_assert(absf(hud.EnemyHealthBar.anchor_left - 0.5) < 0.001 and absf(hud.EnemyHealthBar.anchor_right - 0.5) < 0.001, "B1: EnemyHealthBar anchored top-center (anchor 0.5)")
	hud.set_target_enemy(enemy)
	_assert(hud.EnemyHealthBar.visible == true, "B1: EnemyHealthBar visible after set_target_enemy")
	_assert(hud.EnemyStanceBar.visible == true, "B1: EnemyStanceBar visible after set_target_enemy")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_b2_enemy_health_bar_layout() -> void:
	## B2 布局: EnemyHealthBar size (240,10) 且 offset_top 12（HUD_ENEMY_BAR_TOP）；
	##   EnemyStanceBar offset_top 26（HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT + HUD_ENEMY_HP_GAP）
	var hud = _spawn_hud()
	if hud == null: return
	var hb = hud.EnemyHealthBar
	_assert(hb.size == Vector2(240, 10), "B2: EnemyHealthBar size (240,10) = HUD_ENEMY_BAR_WIDTH x HUD_BAR_HEIGHT (got %s)" % [str(hb.size)])
	_assert(absf(hb.offset_top - 12.0) < 0.001, "B2: EnemyHealthBar top offset 12 = HUD_ENEMY_BAR_TOP")
	_assert(absf(hud.EnemyStanceBar.offset_top - 26.0) < 0.001, "B2: EnemyStanceBar top offset 26 = HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT + HUD_ENEMY_HP_GAP")
	_assert(hud.EnemyStanceBar.offset_top > hud.EnemyHealthBar.offset_top, "B2: stance bar sits below health bar")
	_cleanup_hud(hud)


func _test_b3_enemy_health_bar_hp_changed() -> void:
	## B3 信号驱动比例: 注入 set_target_enemy 初始化 1.0；hp_changed(40, 0, 1) →
	##   EnemyHealthBar 比例 0.5；fill 色为 HUD_BLOOD_RED（set_fill_color 生效）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	var init: Array = hud.EnemyHealthBar.get_segment_fractions()
	_assert(init.size() == 1 and absf(init[0] - 1.0) < 0.001, "B3: set_target_enemy init fraction 1.0 (got %s)" % [str(init)])
	enemy.hp_changed.emit(40.0, 0.0, 1)
	var f: Array = hud.EnemyHealthBar.get_segment_fractions()
	_assert(f.size() == 1 and absf(f[0] - 0.5) < 0.001, "B3: hp_changed(40,0,1) → fraction 0.5 (got %s)" % [str(f)])
	_assert(hud.EnemyHealthBar._use_fill_override == true, "B3: EnemyHealthBar fill override enabled (set_fill_color)")
	var c = load("res://gdscripts/constants.gd")
	if c != null:
		_assert(hud.EnemyHealthBar._fill_override == c.HUD_BLOOD_RED, "B3: EnemyHealthBar fill color == HUD_BLOOD_RED")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_b4_enemy_health_bar_hide() -> void:
	## B4 died 隐藏: died(final=true) → 双条 hidden；set_target_enemy(null) → 双条隐藏
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	## ① died(final=true)
	hud.set_target_enemy(enemy)
	_assert(hud.EnemyHealthBar.visible == true, "B4: health bar visible before death")
	enemy.take_damage(80.0)
	_assert(enemy.state_name == "dead", "B4: enemy final dead (got %s)" % enemy.state_name)
	_assert(hud.EnemyHealthBar.visible == false, "B4: EnemyHealthBar hidden after died(final=true)")
	_assert(hud.EnemyStanceBar.visible == false, "B4: EnemyStanceBar hidden after died(final=true)")
	## ② set_target_enemy(null)
	var enemy2 = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy2 == null:
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_target_enemy(enemy2)
	_assert(hud.EnemyHealthBar.visible == true, "B4: health bar visible for new target")
	hud.set_target_enemy(null)
	_assert(hud.EnemyHealthBar.visible == false, "B4: EnemyHealthBar hidden after set_target_enemy(null)")
	_assert(hud.EnemyStanceBar.visible == false, "B4: EnemyStanceBar hidden after set_target_enemy(null)")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)
	_cleanup_entity(enemy2)


func _test_b5_player_bars_fill_override_off() -> void:
	## B5 玩家条回归: 玩家血条/架势条 fill_override 默认关闭（additive 零影响 → 月白活性段）
	var hud = _spawn_hud()
	if hud == null: return
	_assert(hud.PlayerHealthBar._use_fill_override == false, "B5: PlayerHealthBar fill_override default off")
	_assert(hud.PlayerStanceBar._use_fill_override == false, "B5: PlayerStanceBar fill_override default off")
	_cleanup_hud(hud)


# ── Scenario A/B/C/D(#684): 敌人名字 Label / 崩解闪白 / Boss-杂兵分档 ────────
## 设计: docs/DESIGN/684-boss-hp-bar-ui.md §8（场景 A-D，#684）。
## 常量: #684 新常量未入库 → 字面值 + 常量名注释（HUD_ENEMY_NAME_WIDTH=240.0 → offset_left=-120.0；
##   HUD_ENEMY_NAME_FONT_SIZE=16；HUD_ENEMY_NAME_TOP=2.0；HUD_STANCE_BREAK_FLASH_SECONDS=0.18）。
## 红期守卫: hud.gd 已存在（#695），#684 新 API 未实现 → 经 hud.get()/has_method() 守卫访问，
##   红期记一条 FAIL（非 SCRIPT ERROR——CI grep 防误伤）并 cleanup（防泄漏污染后续套件）。

func _require_methods(hud, methods: Array, scenario: String) -> bool:
	## TDD 红期守卫（#684 新 API 未实现）: 任一方法缺失 → 记一条 FAIL 并返回 false，
	##   调用方负责 cleanup（避免红期直接调用缺失方法触发 SCRIPT ERROR 中断 cleanup）。
	for m in methods:
		if hud == null or not hud.has_method(m):
			_assert(false, "%s: %s missing (TDD red phase)" % [scenario, str(m)])
			return false
	return true


func _test_a1_name_label_layout() -> void:
	## A1(#684) 布局: EnemyNameLabel 锚点 0.5 居中、offset_left=-120（-HUD_ENEMY_NAME_WIDTH/2）、
	##   offset_top=2（HUD_ENEMY_NAME_TOP）、font_size 覆写 16（HUD_ENEMY_NAME_FONT_SIZE）、无底框
	var hud = _spawn_hud()
	if hud == null: return
	var label = hud.get("EnemyNameLabel")
	if label == null:
		_assert(false, "A1: EnemyNameLabel created (TDD red phase: missing)")
		_cleanup_hud(hud)
		return
	_assert(absf(label.anchor_left - 0.5) < 0.001 and absf(label.anchor_right - 0.5) < 0.001, "A1: EnemyNameLabel anchored top-center (anchor 0.5)")
	_assert(absf(label.offset_left - (-120.0)) < 0.001, "A1: EnemyNameLabel offset_left == -120.0 = -HUD_ENEMY_NAME_WIDTH/2")
	_assert(absf(label.offset_top - 2.0) < 0.001, "A1: EnemyNameLabel offset_top == 2.0 = HUD_ENEMY_NAME_TOP")
	_assert(label.get_theme_font_size("font_size") == 16, "A1: EnemyNameLabel font_size override == 16 = HUD_ENEMY_NAME_FONT_SIZE")
	var sb = label.get_theme_stylebox("normal")
	_assert(sb == null or not (sb is StyleBoxFlat), "A1: EnemyNameLabel has no ink frame (no StyleBoxFlat normal stylebox)")
	_cleanup_hud(hud)


func _test_a2_boss_shows_name() -> void:
	## A2(#684) 显示: boss 档 + 非空 display name → EnemyNameLabel.visible == true 且 text 一致
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "A2"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == true, "A2: EnemyNameLabel visible in boss mode")
	_assert(label != null and label.text == "雪夜刀客", "A2: EnemyNameLabel text == '雪夜刀客'")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_a3_minion_hides_name() -> void:
	## A3(#684) 隐藏: 杂兵档（set_boss_mode(false)）→ 名字 + 血条隐藏、小架势条保留
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "A3"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	hud.set_boss_mode(false)
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == false, "A3: minion tier → EnemyNameLabel hidden")
	_assert(hud.EnemyHealthBar.visible == false, "A3: minion tier → EnemyHealthBar hidden")
	_assert(hud.EnemyStanceBar.visible == true, "A3: minion tier → EnemyStanceBar visible")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_a4_empty_name_hides() -> void:
	## A4(#684) 空串隐藏: boss 档 + display name "" → EnemyNameLabel hidden（_enemy_display_name != "" 判定）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "A4"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("")
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == false, "A4: empty display name → EnemyNameLabel hidden")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_a5_long_name_overrun() -> void:
	## A5(#684) 超长名省略: 50 字名 → text_overrun_behavior == OVERRUN_TRIM_ELLIPSIS（不断言实际像素截断）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "A5"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	var long_name: String = ""
	for i in range(50):
		long_name += "刀"
	hud.set_enemy_display_name(long_name)
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "A5: long name → text_overrun_behavior == OVERRUN_TRIM_ELLIPSIS")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_a6_null_target_clears_name() -> void:
	## A6(#684) null 目标: set_target_enemy(null) → 名字 + 血条 + 架势条三态全隐
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "A6"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	hud.set_target_enemy(null)
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == false, "A6: null target → EnemyNameLabel hidden")
	_assert(hud.EnemyHealthBar.visible == false, "A6: null target → EnemyHealthBar hidden")
	_assert(hud.EnemyStanceBar.visible == false, "A6: null target → EnemyStanceBar hidden")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_b1_stance_break_flash_on() -> void:
	## B1(#684) 崩解闪白触发: stance_broken → EnemyStanceBar.is_break_flashing() == true；
	##   且 ExecutePromptLabel 可见（条级闪白与文字提示正交并存）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode"], "B1"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	enemy.stance_broken.emit(enemy)
	var sb = hud.get("EnemyStanceBar")
	_assert(sb != null and sb.has_method("is_break_flashing") and sb.is_break_flashing() == true, "B1: stance_broken → EnemyStanceBar.is_break_flashing() == true")
	_assert(hud.ExecutePromptLabel.visible == true, "B1: stance_broken → ExecutePromptLabel visible (orthogonal)")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_b2_stance_break_flash_fades() -> void:
	## B2(#684) Tween 结束复位: EnemyStanceBar._flash_tween.custom_step(HUD_STANCE_BREAK_FLASH_SECONDS=0.18)
	##   → is_break_flashing() == false 且 _break_flash_alpha == 0.0（headless 同步推进）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode"], "B2"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	enemy.stance_broken.emit(enemy)
	var sb = hud.get("EnemyStanceBar")
	var flashing: bool = false
	if sb != null and sb.has_method("is_break_flashing"):
		flashing = sb.is_break_flashing()
	_assert(flashing, "B2: precondition — stance_broken → flash active")
	if flashing:
		var tw = sb.get("_flash_tween")
		if tw != null:
			tw.custom_step(0.18)   # HUD_STANCE_BREAK_FLASH_SECONDS
	var cleared: bool = false
	if sb != null and sb.has_method("is_break_flashing"):
		cleared = not sb.is_break_flashing() and sb.get("_break_flash_alpha") == 0.0
	_assert(cleared, "B2: flash tween finished → is_break_flashing() == false and _break_flash_alpha == 0.0")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_b3_stance_break_data_path_unaffected() -> void:
	## B3(#684) 闪白期间重绘接管: flash 置位后 set_segments 仍驱动分数（无竞态，数据路径不受影响）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode"], "B3"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	enemy.stance_broken.emit(enemy)
	var sb = hud.get("EnemyStanceBar")
	_assert(sb != null and sb.has_method("is_break_flashing") and sb.is_break_flashing() == true, "B3: precondition — flash active after stance_broken")
	if sb != null:
		sb.set_segments([0.0], [1.0], 0)
		var f: Array = sb.get_segment_fractions()
		_assert(f.size() == 1 and absf(f[0] - 0.0) < 0.001, "B3: flash active → set_segments data path unaffected (got %s)" % [str(f)])
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_b4_stance_break_flash_cleared_on_died() -> void:
	## B4(#684) died 打断无残影: flash 置位后 died(final=true) → is_break_flashing() == false
	##   （clear_break_flash 路径复位）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode"], "B4"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	enemy.stance_broken.emit(enemy)
	var sb = hud.get("EnemyStanceBar")
	_assert(sb != null and sb.has_method("is_break_flashing") and sb.is_break_flashing() == true, "B4: precondition — flash active after stance_broken")
	enemy.take_damage(80.0)
	_assert(sb != null and sb.has_method("is_break_flashing") and sb.is_break_flashing() == false, "B4: died(final=true) → flash cleared (no residue)")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_b5_player_stance_bar_never_flashes() -> void:
	## B5(#684) 玩家条不受影响: 玩家 stance_changed 触发 → PlayerStanceBar.is_break_flashing() == false
	##   （闪白只作用于敌人架势条）
	var hud = _spawn_hud()
	if hud == null: return
	var player = _spawn_entity({is_player=true, life_total=2})
	if player == null:
		_cleanup_hud(hud)
		return
	hud.bind_player(player)
	player.stance_changed.emit(80.0, 100.0)
	var psb = hud.get("PlayerStanceBar")
	_assert(psb != null and psb.has_method("is_break_flashing") and psb.is_break_flashing() == false, "B5: player stance_changed → PlayerStanceBar.is_break_flashing() == false")
	_cleanup_hud(hud)
	_cleanup_entity(player)


func _test_b6_debug_stance_break() -> void:
	## B6(#684) debug 置位: set_debug_stance_break() → EnemyStanceBar.is_break_flashing() == true
	##   （E2E 截图驱动路径，绕开真实 Tween 时序）
	var hud = _spawn_hud()
	if hud == null: return
	if not _require_methods(hud, ["set_debug_stance_break"], "B6"):
		_cleanup_hud(hud)
		return
	hud.set_debug_stance_break()
	var sb = hud.get("EnemyStanceBar")
	_assert(sb != null and sb.has_method("is_break_flashing") and sb.is_break_flashing() == true, "B6: set_debug_stance_break() → is_break_flashing() == true")
	_cleanup_hud(hud)


func _test_c1_tier_then_inject() -> void:
	## C1(#684) 先档后注入: set_boss_mode(false) → set_target_enemy → 注入时读档位
	##   （血条 + 名字隐藏、小架势条可见）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	if not _require_methods(hud, ["set_boss_mode"], "C1"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(false)
	hud.set_target_enemy(enemy)
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == false, "C1: minion tier → EnemyNameLabel hidden")
	_assert(hud.EnemyHealthBar.visible == false, "C1: minion tier → EnemyHealthBar hidden")
	_assert(hud.EnemyStanceBar.visible == true, "C1: minion tier → EnemyStanceBar visible")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_c2_inject_then_tier() -> void:
	## C2(#684) 先注入后档: set_target_enemy → set_boss_mode(true) → 三组件全显
	##   （名字可见需 display name 非空——补充 set_enemy_display_name 使「全显」成立）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "C2"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == true, "C2: boss tier + display name → EnemyNameLabel visible")
	_assert(hud.EnemyHealthBar.visible == true, "C2: boss tier → EnemyHealthBar visible")
	_assert(hud.EnemyStanceBar.visible == true, "C2: boss tier → EnemyStanceBar visible")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_c3_boss_tier_toggle() -> void:
	## C3(#684) 反复切换: true→false→true → 最终全显，无异常无残留
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "C3"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	hud.set_boss_mode(false)
	hud.set_boss_mode(true)
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == true, "C3: toggle true→false→true → EnemyNameLabel visible (final)")
	_assert(hud.EnemyHealthBar.visible == true, "C3: toggle → EnemyHealthBar visible (final)")
	_assert(hud.EnemyStanceBar.visible == true, "C3: toggle → EnemyStanceBar visible (final)")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_c4_boss_tier_idempotent() -> void:
	## C4(#684) 幂等: set_boss_mode(true) 连续两次 → _boss_mode 恒 true、三态一致（同值早退）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode"], "C4"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_boss_mode(true)
	_assert(hud.get("_boss_mode") == true, "C4: set_boss_mode(true) twice → _boss_mode == true")
	_assert(hud.EnemyHealthBar.visible == true, "C4: repeated set_boss_mode(true) → EnemyHealthBar visible")
	_assert(hud.EnemyStanceBar.visible == true, "C4: repeated set_boss_mode(true) → EnemyStanceBar visible")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_c5_boss_tier_null_target() -> void:
	## C5(#684) null 三态全隐: set_target_enemy(null) → 名字 + 血条 + 架势条全部不可见
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "C5"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	hud.set_target_enemy(null)
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == false, "C5: null target → EnemyNameLabel hidden")
	_assert(hud.EnemyHealthBar.visible == false, "C5: null target → EnemyHealthBar hidden")
	_assert(hud.EnemyStanceBar.visible == false, "C5: null target → EnemyStanceBar hidden")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_d3_died_final_hides_name() -> void:
	## D3(#684) died final=true: 名字 + 双条隐藏 + 击杀提示（T18 扩展断言名字）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=1, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "D3"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == true, "D3: precondition — EnemyNameLabel visible in boss mode")
	enemy.take_damage(80.0)
	_assert(label != null and label.visible == false, "D3: died(final=true) → EnemyNameLabel hidden")
	_assert(hud.KillPromptLabel.visible == true, "D3: died(final=true) → KillPromptLabel visible")
	_cleanup_hud(hud)
	_cleanup_entity(enemy)


func _test_d4_died_non_final_clears_name() -> void:
	## D4(#684) died final=false: 名字隐藏 + 双条清 0（T20 扩展断言名字）
	var hud = _spawn_hud()
	if hud == null: return
	var enemy = _spawn_entity({is_player=false, life_total=2, life_1_max=80.0})
	if enemy == null:
		_cleanup_hud(hud)
		return
	hud.set_target_enemy(enemy)
	if not _require_methods(hud, ["set_boss_mode", "set_enemy_display_name"], "D4"):
		_cleanup_hud(hud)
		_cleanup_entity(enemy)
		return
	hud.set_boss_mode(true)
	hud.set_enemy_display_name("雪夜刀客")
	var label = hud.get("EnemyNameLabel")
	_assert(label != null and label.visible == true, "D4: precondition — EnemyNameLabel visible in boss mode")
	enemy.died.emit(enemy, false)
	_assert(label != null and label.visible == false, "D4: died(final=false) → EnemyNameLabel hidden")
	var hb = hud.EnemyHealthBar
	var hf: Array = hb.get_segment_fractions()
	_assert(hf.size() == 1 and absf(hf[0] - 0.0) < 0.001, "D4: died(final=false) → EnemyHealthBar fraction == 0.0 (got %s)" % [str(hf)])
	var sb = hud.EnemyStanceBar
	var sf: Array = sb.get_segment_fractions()
	_assert(sf.size() == 1 and absf(sf[0] - 0.0) < 0.001, "D4: died(final=false) → EnemyStanceBar fraction == 0.0 (got %s)" % [str(sf)])
	_cleanup_hud(hud)
	_cleanup_entity(enemy)

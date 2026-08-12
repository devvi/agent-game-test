extends RefCounted
## Test suite for UpgradePool (#387) — 场景 A–I（29 条；F5 球侧在 test_ball.gd）。
## 规格: docs/DESIGN/387-upgrade-pool-architecture.md §9
## 覆盖: 9 定义完整性 / 稀有度先掷 60/30/10 / 候选去重 / 不可重复与堆叠 /
##       apply 链路与效果回调 / JSON 显示名兜底 / upgrade_hooks 注册表 / rng 可播种。
## 所有权: content_ownership: mechanical。

var passed: int = 0
var failed: int = 0

const CONSTS = preload("res://gdscripts/constants.gd")
const Defs = preload("res://gdscripts/upgrade_defs.gd")

# ── 信号捕获（Pattern 11: 成员变量，不用 lambda 闭包）──
var _applied_events: Array = []

func _on_upgrade_applied(id: String) -> void:
	_applied_events.append(id)


# ── 测试夹具 ──

func _make_pool():
	var pool = Node.new()
	pool.set_script(load("res://gdscripts/upgrade_pool.gd"))
	if pool.get_script() == null:
		return null
	return pool


class FakePaddle extends RefCounted:
	var paddle_width: float = 120.0
	var base_paddle_width: float = 120.0
	var magnet_enabled: bool = false
	var set_width_calls: Array = []

	func set_paddle_width(w: float) -> void:
		paddle_width = w
		set_width_calls.append(w)


class FakeBall extends RefCounted:
	var speed: float = 330.0
	var initial_speed: float = 330.0
	var max_speed_multiplier: float = 1.9
	var global_position: Vector2 = Vector2(100.0, 200.0)
	var slow_time_calls: Array = []

	func set_speed_scale_timed(scale: float, duration: float) -> void:
		slow_time_calls.append([scale, duration])


## 假 BreakoutGrid（#384 未落地 → 契约先行，TC-H1/H2 对桩可测）
class FakeGrid extends RefCounted:
	var upgrade_hooks: Dictionary = {}
	var open_hole_count: int = -1
	var blast_calls: Array = []

	func register_upgrade_hook(id: String, cb: Callable) -> void:
		upgrade_hooks[id] = cb

	func apply_upgrade_hook(id: String, ctx: Dictionary) -> bool:
		if not upgrade_hooks.has(id):
			return false
		var full_ctx = ctx.duplicate()
		full_ctx["grid"] = self
		upgrade_hooks[id].call(full_ctx)
		return true

	func open_hole(count: int) -> void:
		open_hole_count = count

	func blast_neighbors(pos: Vector2, radius: float) -> void:
		blast_calls.append([pos, radius])


func run() -> void:
	print("\n=== Upgrade Pool Tests (#387) ===")
	# Scenario A: 9 定义完整性（AC1）
	_test_a1_definitions_complete()
	_test_a2_definition_fields()
	_test_a3_rarity_distribution()
	_test_a4_by_id_lookup()
	# Scenario B: 稀有度先掷 60/30/10（AC2）
	_test_b1_rarity_mapping()
	_test_b2_rarity_statistics()
	_test_b3_candidate_rarity_meta()
	_test_b4_independent_rarity_rolls()
	# Scenario C: 候选内去重
	_test_c1_candidates_unique()
	_test_c2_short_candidates()
	# Scenario D: 不可重复 / 堆叠（AC2）
	_test_d1_max_stacks_one()
	_test_d2_max_stacks_multi()
	_test_d3_stack_cap_exhaust()
	_test_d4_candidate_vs_global()
	_test_d5_get_stacks_zero()
	# Scenario E: apply 链路与效果回调（AC5）
	_test_e1_apply_long_arm()
	_test_e2_apply_slow_time()
	_test_e3_apply_magnet_core()
	_test_e4_stub_effects()
	_test_e5_signal_emit()
	# Scenario G: JSON 显示名兜底（#395 只读消费）
	_test_g1_display_from_json()
	_test_g2_display_missing_file()
	_test_g3_display_partial_fields()
	# Scenario H: upgrade_hooks 注册表（AC4，契约先行）
	_test_h1_register_all()
	_test_h2_apply_upgrade_hook_dispatch()
	_test_h3_grid_null_noop()
	# Scenario I: rng 可播种确定性
	_test_i1_rng_seed_determinism()


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── Scenario A: 9 定义完整性（AC1）──

func _test_a1_definitions_complete() -> void:
	var defs = Defs.definitions()
	_assert(defs.size() == CONSTS.UPGRADE_POOL_SIZE, "TC-A1: 9 definitions (%d)" % defs.size())
	var ids: Array = []
	for d in defs:
		ids.append(d.id)
	for expected in ["long_arm", "fireball", "battering_ram", "magnet_core", "twin", "slow_time", "pre_hole", "stardust", "phantom"]:
		_assert(ids.has(expected), "TC-A1: id '%s' present" % expected)


func _test_a2_definition_fields() -> void:
	for d in Defs.definitions():
		var id_str: String = d.get("id", "?")
		_assert(d.has("id") and d.has("name") and d.has("rarity") and d.has("max_stacks") and d.has("effect_desc"), "TC-A2: %s has id/name/rarity/max_stacks/effect_desc" % id_str)
		_assert(d.effect is Callable, "TC-A2: %s effect is Callable" % id_str)


func _test_a3_rarity_distribution() -> void:
	var common := 0
	var rare := 0
	var legendary := 0
	for d in Defs.definitions():
		if d.rarity == Defs.Rarity.COMMON:
			common += 1
		elif d.rarity == Defs.Rarity.RARE:
			rare += 1
		elif d.rarity == Defs.Rarity.LEGENDARY:
			legendary += 1
	_assert(common == 3, "TC-A3: COMMON == 3 (long_arm/fireball/battering_ram)")
	_assert(rare == 4, "TC-A3: RARE == 4 (magnet_core/twin/slow_time/pre_hole)")
	_assert(legendary == 2, "TC-A3: LEGENDARY == 2 (stardust/phantom)")


func _test_a4_by_id_lookup() -> void:
	var la = Defs.by_id("long_arm")
	_assert(not la.is_empty(), "TC-A4: by_id('long_arm') hit")
	_assert(la.id == "long_arm", "TC-A4: id matches")
	_assert(Defs.by_id("unknown").is_empty(), "TC-A4: by_id('unknown') → empty dict, no crash")


# ── Scenario B: 稀有度先掷 60/30/10（AC2）──

func _test_b1_rarity_mapping() -> void:
	# 单卡权重映射边界：1–60→COMMON、61–90→RARE、91–100→LEGENDARY
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-B1: upgrade_pool.gd script loaded")
		return
	_assert(pool.rarity_from_roll(1) == Defs.Rarity.COMMON, "TC-B1: roll 1 → COMMON")
	_assert(pool.rarity_from_roll(60) == Defs.Rarity.COMMON, "TC-B1: roll 60 → COMMON")
	_assert(pool.rarity_from_roll(61) == Defs.Rarity.RARE, "TC-B1: roll 61 → RARE")
	_assert(pool.rarity_from_roll(90) == Defs.Rarity.RARE, "TC-B1: roll 90 → RARE")
	_assert(pool.rarity_from_roll(91) == Defs.Rarity.LEGENDARY, "TC-B1: roll 91 → LEGENDARY")
	_assert(pool.rarity_from_roll(100) == Defs.Rarity.LEGENDARY, "TC-B1: roll 100 → LEGENDARY")


func _test_b2_rarity_statistics() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-B2: upgrade_pool.gd script loaded")
		return
	pool.rng.seed = 20260813
	pool._ready()
	var counts: Array = [0, 0, 0]
	var total: int = 0
	for i in 20000:
		var cards = pool.get_candidates(3)
		for c in cards:
			counts[c.rarity] += 1
			total += 1
	var c_pct: float = 100.0 * counts[0] / total
	var r_pct: float = 100.0 * counts[1] / total
	var l_pct: float = 100.0 * counts[2] / total
	_assert(c_pct >= 55.0 and c_pct <= 65.0, "TC-B2: common %.1f%% ∈ [55,65]" % c_pct)
	_assert(r_pct >= 25.0 and r_pct <= 35.0, "TC-B2: rare %.1f%% ∈ [25,35]" % r_pct)
	_assert(l_pct >= 5.0 and l_pct <= 15.0, "TC-B2: legendary %.1f%% ∈ [5,15]" % l_pct)


func _test_b3_candidate_rarity_meta() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-B3: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var cards = pool.get_candidates(3)
	_assert(cards.size() == 3, "TC-B3: 3 candidates returned")
	for c in cards:
		_assert(c.has("rarity"), "TC-B3: candidate carries rarity meta")
		_assert(c.has("id") and c.has("name") and c.has("max_stacks") and c.has("effect_desc"), "TC-B3: candidate carries id/name/max_stacks/effect_desc")


func _test_b4_independent_rarity_rolls() -> void:
	# 每张卡独立掷稀有度 → 同一候选内可含 2–3 张同稀有度（不强制均匀）
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-B4: upgrade_pool.gd script loaded")
		return
	pool.rng.seed = 777
	pool._ready()
	var saw_dup := false
	for i in 200:
		var cards = pool.get_candidates(3)
		var rarities: Dictionary = {}
		for c in cards:
			rarities[c.rarity] = rarities.get(c.rarity, 0) + 1
		for r in rarities:
			if rarities[r] >= 2:
				saw_dup = true
		if saw_dup:
			break
	_assert(saw_dup, "TC-B4: same-rarity duplicates appear within one candidate set")


# ── Scenario C: 候选内去重 ──

func _test_c1_candidates_unique() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-C1: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var all_unique := true
	for i in 100:
		var cards = pool.get_candidates(3)
		var seen: Dictionary = {}
		for c in cards:
			if seen.has(c.id):
				all_unique = false
			seen[c.id] = true
	_assert(all_unique, "TC-C1: candidate ids unique within every call")


func _test_c2_short_candidates() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-C2: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var defs = Defs.definitions()
	pool._available = [defs[0], defs[1]]
	var cards = pool.get_candidates(3)
	_assert(cards.size() == 2, "TC-C2: returns 2 (not 3) when only 2 left — no error, no dup")


# ── Scenario D: 不可重复 / 堆叠（AC2）──

func _test_d1_max_stacks_one() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-D1: upgrade_pool.gd script loaded")
		return
	pool._ready()
	_assert(pool.apply("stardust"), "TC-D1: first apply('stardust') succeeds")
	_assert(pool.get_stacks("stardust") == 1, "TC-D1: stacks == 1")
	_assert(not pool.apply("stardust"), "TC-D1: second apply returns false (max_stacks=1, 整局不可重复)")
	var seen_later := false
	for i in 10:
		var cards = pool.get_candidates(3)
		for c in cards:
			if c.id == "stardust":
				seen_later = true
	_assert(not seen_later, "TC-D1: stardust absent from future candidates")


func _test_d2_max_stacks_multi() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-D2: upgrade_pool.gd script loaded")
		return
	pool._ready()
	_assert(pool.apply("long_arm"), "TC-D2: 1st apply ok")
	_assert(pool.apply("long_arm"), "TC-D2: 2nd apply ok (max_stacks=3)")
	_assert(pool.get_stacks("long_arm") == 2, "TC-D2: stacks == 2")


func _test_d3_stack_cap_exhaust() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-D3: upgrade_pool.gd script loaded")
		return
	pool._ready()
	pool.apply("long_arm")
	pool.apply("long_arm")
	pool.apply("long_arm")
	_assert(not pool.apply("long_arm"), "TC-D3: 4th apply returns false (cap 3)")
	var seen_later := false
	for i in 10:
		var cards = pool.get_candidates(3)
		for c in cards:
			if c.id == "long_arm":
				seen_later = true
	_assert(not seen_later, "TC-D3: long_arm absent from future candidates")


func _test_d4_candidate_vs_global() -> void:
	# 候选去重（单次调用内）与整局不可重复（max_stacks=1）正交
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-D4: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var seen_before := false
	for i in 50:
		var cards = pool.get_candidates(3)
		for c in cards:
			if c.id == "stardust":
				seen_before = true
		if seen_before:
			break
	_assert(seen_before, "TC-D4: stardust appears in candidates before taking")
	pool.apply("stardust")
	for i in 10:
		var cards = pool.get_candidates(3)
		for c in cards:
			_assert(c.id != "stardust", "TC-D4: stardust gone globally after taking")


func _test_d5_get_stacks_zero() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-D5: upgrade_pool.gd script loaded")
		return
	pool._ready()
	_assert(pool.get_stacks("phantom") == 0, "TC-D5: get_stacks('phantom') == 0 (never taken)")


# ── Scenario E: apply 链路与效果回调（AC5）──

func _test_e1_apply_long_arm() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-E1: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var paddle = FakePaddle.new()
	pool.paddle_ref = paddle
	_assert(pool.apply("long_arm"), "TC-E1: apply ok")
	_assert(abs(paddle.paddle_width - 156.0) < 0.01, "TC-E1: width == base ×1.3 (156)")
	_assert(paddle.set_width_calls.size() == 1 and abs(paddle.set_width_calls[0] - 156.0) < 0.01, "TC-E1: set_paddle_width called with 156")
	pool.apply("long_arm")
	_assert(abs(paddle.paddle_width - 192.0) < 0.01, "TC-E1: second apply → base ×1.6 (192, 加算语义)")


func _test_e2_apply_slow_time() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-E2: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var ball = FakeBall.new()
	pool.ball_ref = ball
	_assert(pool.apply("slow_time"), "TC-E2: apply ok")
	_assert(ball.slow_time_calls.size() == 1, "TC-E2: set_speed_scale_timed called once")
	_assert(ball.slow_time_calls[0][0] == 0.0 and ball.slow_time_calls[0][1] == 2.0, "TC-E2: called with (0.0, 2.0)")


func _test_e3_apply_magnet_core() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-E3: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var paddle = FakePaddle.new()
	pool.paddle_ref = paddle
	_assert(pool.apply("magnet_core"), "TC-E3: apply ok")
	_assert(paddle.magnet_enabled, "TC-E3: magnet_enabled == true")


func _test_e4_stub_effects() -> void:
	# 桩效果（twin/stardust/phantom）：可调用、可断言、不崩溃（§3.1 桩决策）
	for id in ["twin", "stardust", "phantom"]:
		var pool = _make_pool()
		if pool == null:
			_assert(false, "TC-E4: upgrade_pool.gd script loaded")
			return
		pool._ready()
		_assert(pool.apply(id), "TC-E4: apply('%s') returns true" % id)
		_assert(pool.stub_activated.get(id, false), "TC-E4: stub_activated['%s'] == true" % id)


func _test_e5_signal_emit() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-E5: upgrade_pool.gd script loaded")
		return
	pool._ready()
	pool.upgrade_applied.connect(_on_upgrade_applied)
	_applied_events = []
	_assert(pool.apply("slow_time"), "TC-E5: apply ok")
	_assert(_applied_events.size() == 1 and _applied_events[0] == "slow_time", "TC-E5: upgrade_applied emitted exactly once with id")
	_applied_events = []
	_assert(not pool.apply("nonexistent_upgrade"), "TC-E5: unknown id → false")
	_assert(_applied_events.is_empty(), "TC-E5: no emit on failed apply")


# ── Scenario G: JSON 显示名兜底（#395 只读消费）──

func _test_g1_display_from_json() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-G1: upgrade_pool.gd script loaded")
		return
	pool._ready()
	# get_candidates(30)：去重上限 9 → 返回全量池，long_arm 必在
	var cards = pool.get_candidates(30)
	var found := false
	for c in cards:
		if c.id == "long_arm":
			var disp = c.display
			_assert(disp.get("name_working", "") == "长臂", "TC-G1: display.name_working from JSON")
			_assert(disp.get("short_phrase", "") == "够得着了", "TC-G1: display.short_phrase from JSON")
			_assert(typeof(disp.get("naming_candidates", null)) == TYPE_ARRAY, "TC-G1: naming_candidates array present")
			found = true
	_assert(found, "TC-G1: long_arm seen in candidates")


func _test_g2_display_missing_file() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-G2: upgrade_pool.gd script loaded")
		return
	pool._ready()
	pool._load_display_names("res://assets/content/does_not_exist.json")
	pool._load_display_names("res://assets/content/does_not_exist.json")
	var cards = pool.get_candidates(30)
	var saw_long_arm := false
	for c in cards:
		if c.id == "long_arm":
			saw_long_arm = true
			_assert(c.name == "长臂", "TC-G2: name falls back to working name")
			_assert(c.display.is_empty(), "TC-G2: display empty on missing file")
	_assert(saw_long_arm, "TC-G2: game continues — candidates still returned")
	_assert(pool._display_warn_count == 1, "TC-G2: push_warning at most once")


func _test_g3_display_partial_fields() -> void:
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-G3: upgrade_pool.gd script loaded")
		return
	pool._ready()
	var tmp_path := "user://test_upgrade_pool_partial.json"
	var f = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		_assert(false, "TC-G3: user:// writable")
		return
	f.store_string('{"schema":"upgrade-pool-content/v1","upgrades":[{"id":"long_arm","name_working":"长臂","short_phrase":"够得着了","naming_candidates":[]},{"id":"fireball"}]}')
	f.close()
	pool._load_display_names(tmp_path)
	var disp_la = pool._display.get("long_arm", {})
	_assert(disp_la.get("name_working", "") == "长臂", "TC-G3: complete entry uses JSON values")
	var disp_fb = pool._display.get("fireball", {})
	_assert(disp_fb.get("name_working", "") == "", "TC-G3: partial entry falls back (empty display fields)")
	_assert(disp_fb.get("short_phrase", "") == "", "TC-G3: partial entry short_phrase empty")


# ── Scenario H: upgrade_hooks 注册表（AC4，契约先行）──

func _test_h1_register_all() -> void:
	var hooks = load("res://gdscripts/brick_upgrade_hooks.gd")
	if hooks == null:
		_assert(false, "TC-H1: brick_upgrade_hooks.gd loaded")
		return
	var grid = FakeGrid.new()
	hooks.register_all(grid)
	_assert(grid.upgrade_hooks.has("open_hole"), "TC-H1: open_hole registered")
	_assert(grid.upgrade_hooks.has("blast_neighbors"), "TC-H1: blast_neighbors registered")
	_assert(grid.upgrade_hooks["open_hole"] is Callable, "TC-H1: registered value is Callable")


func _test_h2_apply_upgrade_hook_dispatch() -> void:
	var hooks = load("res://gdscripts/brick_upgrade_hooks.gd")
	if hooks == null:
		_assert(false, "TC-H2: brick_upgrade_hooks.gd loaded")
		return
	var grid = FakeGrid.new()
	hooks.register_all(grid)
	var ok = grid.apply_upgrade_hook("blast_neighbors", {"pos": Vector2(10.0, 20.0), "radius": 5.0})
	_assert(ok, "TC-H2: dispatch returns true")
	_assert(grid.blast_calls.size() == 1, "TC-H2: blast_neighbors called once")
	_assert(grid.blast_calls[0][0] == Vector2(10.0, 20.0) and grid.blast_calls[0][1] == 5.0, "TC-H2: pos/radius forwarded")
	_assert(not grid.apply_upgrade_hook("unknown_hook", {}), "TC-H2: unregistered id returns false")
	grid.apply_upgrade_hook("open_hole", {"count": 1})
	_assert(grid.open_hole_count == 1, "TC-H2: open_hole dispatched with count")


func _test_h3_grid_null_noop() -> void:
	# #384 未落地 → grid 为 null 时砖墙类效果 no-op 不崩
	var pool = _make_pool()
	if pool == null:
		_assert(false, "TC-H3: upgrade_pool.gd script loaded")
		return
	pool._ready()
	_assert(pool.apply("pre_hole"), "TC-H3: apply('pre_hole') returns true with null grid")
	_assert(pool.apply("fireball"), "TC-H3: apply('fireball') returns true with null ball+grid")
	_assert(pool.apply("battering_ram"), "TC-H3: apply('battering_ram') returns true with null grid")


# ── Scenario I: rng 可播种确定性 ──

func _test_i1_rng_seed_determinism() -> void:
	var pool_a = _make_pool()
	if pool_a == null:
		_assert(false, "TC-I1: upgrade_pool.gd script loaded")
		return
	pool_a.rng.seed = 424242
	pool_a._ready()
	var pool_b = _make_pool()
	pool_b.rng.seed = 424242
	pool_b._ready()
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 5:
		for c in pool_a.get_candidates(3):
			seq_a.append(c.id)
		for c in pool_b.get_candidates(3):
			seq_b.append(c.id)
	_assert(seq_a == seq_b, "TC-I1: same seed → identical candidate sequences")
	var different := false
	for s in [1, 2, 3, 999]:
		var pool_c = _make_pool()
		pool_c.rng.seed = s
		pool_c._ready()
		var seq_c: Array = []
		for i in 5:
			for c in pool_c.get_candidates(3):
				seq_c.append(c.id)
		if seq_c != seq_a:
			different = true
			break
	_assert(different, "TC-I1: different seed → different sequence")

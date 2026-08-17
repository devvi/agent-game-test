extends RefCounted
## 9 升级定义 — 单一事实源（#387 §3.1）。
## 机械层（content_ownership: mechanical）：id / 工作名 / 稀有度 / max_stacks /
## 效果回调。显示文案（name_working / short_phrase / naming_candidates）归 #395，
## 运行时由 UpgradePool 从 res://assets/content/upgrade_pool.json 只读覆盖
## （见 upgrade_pool.gd _load_display_names），此处为工作名兜底。
##
## 桩决策（§3.1）: twin / stardust / phantom 效果回调本期为可调用、可断言、
## 不崩溃的桩（写 UpgradePool.stub_activated 标记 + push_warning），完整实现
## 随 #384 落地后以独立小 PR 深化。6/9 效果（long_arm / fireball /
## battering_ram / magnet_core / slow_time / pre_hole）机械完整实现。
## #526 桩过滤决策: 3 桩经 is_stub 标记从候选池排除（玩家可选的升级必须全部
## 有可见反馈，PRD §2.2 情感误归因约束）；完整实现后置 false 回归候选池。
##
## 稀有度来源: docs/PLAN-rogue-pong.md §2.5（已确认 2026-08-13）。

const CONSTS = preload("res://gdscripts/constants.gd")
const _SELF = preload("res://gdscripts/upgrade_defs.gd")  # 自身脚本引用（规避 class_name 缓存问题）

enum Rarity { COMMON = 0, RARE = 1, LEGENDARY = 2 }

# 机械占位数值（taste 数值归 #395 / PLAN-rogue-pong §2.5 深化，非本 Issue 定稿）
const LONG_ARM_STEP: float = 0.3          # 挡板 +30%（对基数加算，两次 → +60%）
const FIREBALL_SPEED_MULT: float = 1.1    # 球速 +10%
const FIREBALL_RADIUS: float = 90.0       # 燃烧弹爆炸半径（占位）
const BATTERING_RAM_RADIUS: float = 120.0 # 破城锤冲击半径（占位）
const SLOW_TIME_SCALE: float = 0.0        # 缓时冻结球速
const SLOW_TIME_DURATION: float = 2.0     # 缓时持续 2s

# ── Debuff 数值（#543，taste 占位 #395 定稿；与 CONSTS.DEBUFF_* 单源对齐）──
const SHRINK_FACTOR: float = CONSTS.DEBUFF_SHRINK_FACTOR        # 缩板 ×0.7
const FREEZE_DURATION: float = CONSTS.DEBUFF_FREEZE_DURATION    # 冻结 1.5s
const SLOW_SCALE: float = CONSTS.DEBUFF_SLOW_SCALE              # 减速 ×0.75
const SLOW_DURATION: float = CONSTS.DEBUFF_SLOW_DURATION        # 持续 8s
const REVERSE_DURATION: float = CONSTS.DEBUFF_REVERSE_DURATION  # 方向反转 3s


static func definitions() -> Array:
	return [
		{
			"id": "long_arm",
			"name": "长臂",
			"rarity": Rarity.COMMON,
			"is_stub": false,
			"target": "self",
			"max_stacks": 3,
			"effect_desc": "挡板宽度 +30%（对基数加算，两次 → +60%）",
			"effect": Callable(_SELF, "_effect_long_arm"),
		},
		{
			"id": "fireball",
			"name": "燃烧弹",
			"rarity": Rarity.COMMON,
			"is_stub": false,
			"target": "self",
			"max_stacks": 3,
			"effect_desc": "球速 +10%，破砖烧碎相邻砖",
			"effect": Callable(_SELF, "_effect_fireball"),
		},
		{
			"id": "battering_ram",
			"name": "破城锤",
			"rarity": Rarity.COMMON,
			"is_stub": false,
			"target": "self",
			"max_stacks": 3,
			"effect_desc": "破砖冲击波，碎邻近砖",
			"effect": Callable(_SELF, "_effect_battering_ram"),
		},
		{
			"id": "magnet_core",
			"name": "磁心",
			"rarity": Rarity.RARE,
			"is_stub": false,
			"target": "self",
			"max_stacks": 2,
			"effect_desc": "挡板磁力吸球",
			"effect": Callable(_SELF, "_effect_magnet_core"),
		},
		{
			"id": "twin",
			"name": "双生",
			"rarity": Rarity.RARE,
			"is_stub": true,
			"max_stacks": 1,
			"effect_desc": "球分裂为二（桩：完整实现随 #384 落地后深化）",
			"effect": Callable(_SELF, "_effect_twin_stub"),
		},
		{
			"id": "slow_time",
			"name": "缓时",
			"rarity": Rarity.RARE,
			"is_stub": false,
			"target": "self",
			"max_stacks": 2,
			"effect_desc": "球速冻结 2 秒后恢复",
			"effect": Callable(_SELF, "_effect_slow_time"),
		},
		{
			"id": "pre_hole",
			"name": "预开洞",
			"rarity": Rarity.RARE,
			"is_stub": false,
			"target": "self",
			"max_stacks": 1,
			"effect_desc": "下波砖墙预开洞（经 BreakoutGrid upgrade_hooks）",
			"effect": Callable(_SELF, "_effect_pre_hole"),
		},
		{
			"id": "stardust",
			"name": "星尘",
			"rarity": Rarity.LEGENDARY,
			"is_stub": true,
			"max_stacks": 1,
			"effect_desc": "穿墙轨迹伤害（桩：完整实现独立小 PR 深化）",
			"effect": Callable(_SELF, "_effect_stardust_stub"),
		},
		{
			"id": "phantom",
			"name": "幻影",
			"rarity": Rarity.LEGENDARY,
			"is_stub": true,
			"max_stacks": 1,
			"effect_desc": "挡板残影多段判定（桩：完整实现独立小 PR 深化）",
			"effect": Callable(_SELF, "_effect_phantom_stub"),
		},
		# ── Debuff 卡 (#543 §3.6，target=opponent；数值/文案 taste 占位 #395 定稿) ──
		{
			"id": "shrink_opponent",
			"name": "压缩",
			"rarity": Rarity.COMMON,
			"is_stub": false,
			"target": "opponent",
			"max_stacks": 2,
			"effect_desc": "对手挡板宽度 -30%（对基数减算，占位）",
			"effect": Callable(_SELF, "_effect_shrink_opponent"),
		},
		{
			"id": "freeze_opponent",
			"name": "冻结",
			"rarity": Rarity.RARE,
			"is_stub": false,
			"target": "opponent",
			"max_stacks": 1,
			"effect_desc": "对手挡板冻结 1.5 秒（占位）",
			"effect": Callable(_SELF, "_effect_freeze_opponent"),
		},
		{
			"id": "slow_opponent",
			"name": "迟缓",
			"rarity": Rarity.RARE,
			"is_stub": false,
			"target": "opponent",
			"max_stacks": 1,
			"effect_desc": "对手挡板减速 25% 持续 8 秒（占位）",
			"effect": Callable(_SELF, "_effect_slow_opponent"),
		},
		{
			"id": "reverse_opponent",
			"name": "紊乱",
			"rarity": Rarity.RARE,
			"is_stub": false,
			"target": "opponent",
			"max_stacks": 1,
			"effect_desc": "对手左右方向反转 3 秒（占位）",
			"effect": Callable(_SELF, "_effect_reverse_opponent"),
		},
	]


static func by_id(id: String) -> Dictionary:
	for d in definitions():
		if d.id == id:
			return d
	return {}


# ── 效果回调（ctx = {ball, paddle, grid, params, pool}；#387 §3.2 _build_ctx）──
# 各回调显式判空：grid 类效果 no-op + 不崩；ball/paddle 类目标缺失时记录并跳过
# （DESIGN §6 失败路径 2）。

static func _effect_long_arm(ctx: Dictionary) -> void:
	var paddle = ctx.get("paddle")
	if paddle == null:
		push_warning("UpgradePool: long_arm skipped — paddle target missing")
		return
	if not paddle.has_method("set_paddle_width"):
		return
	var new_width: float = paddle.paddle_width + LONG_ARM_STEP * paddle.base_paddle_width
	paddle.set_paddle_width(new_width)


static func _effect_fireball(ctx: Dictionary) -> void:
	var ball = ctx.get("ball")
	if ball != null:
		ball.speed = min(ball.speed * FIREBALL_SPEED_MULT, ball.initial_speed * ball.max_speed_multiplier)
	var grid = ctx.get("grid")
	if grid != null and grid.has_method("apply_upgrade_hook"):
		var pos := Vector2.ZERO
		if ball != null:
			pos = ball.global_position
		grid.apply_upgrade_hook("blast_neighbors", {"pos": pos, "radius": FIREBALL_RADIUS})


static func _effect_battering_ram(ctx: Dictionary) -> void:
	var grid = ctx.get("grid")
	if grid == null or not grid.has_method("apply_upgrade_hook"):
		return
	var ball = ctx.get("ball")
	var pos := Vector2.ZERO
	if ball != null:
		pos = ball.global_position
	grid.apply_upgrade_hook("blast_neighbors", {"pos": pos, "radius": BATTERING_RAM_RADIUS})


static func _effect_magnet_core(ctx: Dictionary) -> void:
	var paddle = ctx.get("paddle")
	if paddle == null:
		push_warning("UpgradePool: magnet_core skipped — paddle target missing")
		return
	paddle.magnet_enabled = true


static func _effect_slow_time(ctx: Dictionary) -> void:
	var ball = ctx.get("ball")
	if ball == null or not ball.has_method("set_speed_scale_timed"):
		push_warning("UpgradePool: slow_time skipped — ball target missing")
		return
	ball.set_speed_scale_timed(SLOW_TIME_SCALE, SLOW_TIME_DURATION)


static func _effect_pre_hole(ctx: Dictionary) -> void:
	var grid = ctx.get("grid")
	if grid == null or not grid.has_method("apply_upgrade_hook"):
		return
	grid.apply_upgrade_hook("open_hole", {"count": 1})


# ── 桩效果（§3.1 桩决策）：可调用、可断言、不崩溃 ──
# 经 ctx["pool"]（apply() 注入）回写 stub_activated，避免 autoload 名解析
# （--script 模式下 class cache 为空，见 game-implement-agent skill pitfall）。

static func _effect_twin_stub(ctx: Dictionary) -> void:
	var pool = ctx.get("pool")
	if pool != null and pool.has_method("mark_stub_effect"):
		pool.mark_stub_effect("twin")


static func _effect_stardust_stub(ctx: Dictionary) -> void:
	var pool = ctx.get("pool")
	if pool != null and pool.has_method("mark_stub_effect"):
		pool.mark_stub_effect("stardust")


static func _effect_phantom_stub(ctx: Dictionary) -> void:
	var pool = ctx.get("pool")
	if pool != null and pool.has_method("mark_stub_effect"):
		pool.mark_stub_effect("phantom")


# ── Debuff 效果回调（#543 §3.6；target=opponent，目标判空 push_warning + no-op）──
# ctx["opponent_paddle"] 由 UpgradePool._build_ctx(player_index) 解析；单板/无匹配 →
# null → 不崩（#387 判空风格，D3）。

static func _effect_shrink_opponent(ctx: Dictionary) -> void:
	var opponent_paddle = ctx.get("opponent_paddle")
	if opponent_paddle == null or not opponent_paddle.has_method("set_paddle_width"):
		push_warning("UpgradePool: shrink_opponent skipped — opponent paddle missing")
		return
	opponent_paddle.set_paddle_width(opponent_paddle.paddle_width * SHRINK_FACTOR)


static func _effect_freeze_opponent(ctx: Dictionary) -> void:
	var opponent_paddle = ctx.get("opponent_paddle")
	if opponent_paddle == null or not opponent_paddle.has_method("set_frozen_timed"):
		push_warning("UpgradePool: freeze_opponent skipped — opponent paddle missing")
		return
	opponent_paddle.set_frozen_timed(FREEZE_DURATION)


static func _effect_slow_opponent(ctx: Dictionary) -> void:
	var opponent_paddle = ctx.get("opponent_paddle")
	if opponent_paddle == null or not opponent_paddle.has_method("set_speed_scale_timed"):
		push_warning("UpgradePool: slow_opponent skipped — opponent paddle missing")
		return
	opponent_paddle.set_speed_scale_timed(SLOW_SCALE, SLOW_DURATION)


static func _effect_reverse_opponent(ctx: Dictionary) -> void:
	var opponent_paddle = ctx.get("opponent_paddle")
	if opponent_paddle == null or not opponent_paddle.has_method("set_input_invert_timed"):
		push_warning("UpgradePool: reverse_opponent skipped — opponent paddle missing")
		return
	opponent_paddle.set_input_invert_timed(REVERSE_DURATION)

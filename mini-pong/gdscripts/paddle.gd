extends Area2D
## Player paddle for mini-pong — A/D + Arrow key input, horizontal movement, boundary clamp.
## AI mode: tracks ball X position with reaction delay, position error, and speed adjustment.
## 竖屏 (#383): 挡板横置、沿 X 移动；输入 paddle_left(A/←)/paddle_right(D/→)；AI 追踪球 X。

const CONSTS = preload("res://gdscripts/constants.gd")

const FALLBACK_VIEWPORT_X: float = float(CONSTS.SCREEN_WIDTH)

# ── Mode enum ──
enum Mode { PLAYER = 0, AI = 1 }

@export var mode: Mode = Mode.PLAYER

## #543: 0 = P1（底侧，默认，兼容既有场景/测试）；1 = P2（顶侧，2P）。
@export var player_index: int = 0

# ── 实例级手感参数 (#387 AC3: const → @export，默认值仍 = CONSTS，#367 定稿值不变) ──
@export var paddle_speed: float = CONSTS.PADDLE_SPEED
@export var paddle_width: float = CONSTS.PADDLE_WIDTH
@export var paddle_height: float = CONSTS.PADDLE_HEIGHT
var base_paddle_width: float = CONSTS.PADDLE_WIDTH  # _ready 捕获（长臂加算基准）

# ── 磁心 (#387，默认关；数值占位归 taste 域 #395) ──
@export var magnet_enabled: bool = false
@export var magnet_pull_radius: float = 180.0
@export var magnet_pull_strength: float = 600.0

# ── AI parameters (tunable in editor) ──
@export var ai_reaction_delay_min: float = CONSTS.AI_REACTION_DELAY_MIN
@export var ai_reaction_delay_max: float = CONSTS.AI_REACTION_DELAY_MAX
@export var ai_position_error: float = CONSTS.AI_POSITION_ERROR
@export var ai_speed_boost: float = CONSTS.AI_SPEED_BOOST
@export var ai_speed_slow: float = CONSTS.AI_SPEED_SLOW

# ── Freeze control (FSM #294) ──
var frozen: bool = false

func set_frozen(value: bool) -> void:
	frozen = value

# ── Debuff 定时状态 API (#543) ──
## set_frozen_timed: 重复施加取 max（防覆盖）；duration <= 0 视为解除（E2 归零语义）。
## 与 FSM 冻结判定式或关系（Spike 2 定稿）。
func set_frozen_timed(duration: float) -> void:
	if duration <= 0.0:
		_timed_freeze_remaining = 0.0
	else:
		_timed_freeze_remaining = max(_timed_freeze_remaining, duration)


func set_speed_scale_timed(scale: float, duration: float) -> void:
	_speed_scale = scale
	_speed_scale_remaining = duration


func set_input_invert_timed(duration: float) -> void:
	_input_invert_remaining = duration


## 判定式或关系: FSM 全局冻结优先，临时冻结计时独立走完，二者互不覆盖。
func is_effectively_frozen() -> bool:
	return frozen or _timed_freeze_remaining > 0.0

# ── InputMap 分键重建器 (#543 §3.3) ──
## 幂等重建：SINGLE 下 paddle_left={A,←}/paddle_right={D,→}（现状绑定集合）；
## LOCAL_2P 下 ←/→ 增量 erase 移入 p2_left/p2_right。重复开局无残留（事件级比对，B3）。
static func rebind_for_mode(mode: int) -> void:
	# 前置：4 个 2P action 恒存在（静态定义于 project.godot；has_action 兜底）
	_ensure_action(CONSTS.P1_CONFIRM_ACTION)
	_ensure_keycode(CONSTS.P1_CONFIRM_ACTION, KEY_E)
	_ensure_action(CONSTS.P1_LEFT_ACTION)
	_ensure_keycode(CONSTS.P1_LEFT_ACTION, KEY_A)
	_ensure_action(CONSTS.P1_RIGHT_ACTION)
	_ensure_keycode(CONSTS.P1_RIGHT_ACTION, KEY_D)
	_ensure_action(CONSTS.P2_CONFIRM_ACTION)
	_ensure_keycode(CONSTS.P2_CONFIRM_ACTION, KEY_SHIFT)
	_ensure_action(CONSTS.P2_LEFT_ACTION)
	_ensure_keycode(CONSTS.P2_LEFT_ACTION, KEY_LEFT)
	_ensure_action(CONSTS.P2_RIGHT_ACTION)
	_ensure_keycode(CONSTS.P2_RIGHT_ACTION, KEY_RIGHT)
	# paddle_left/paddle_right 基础键（A/D）恒在
	_ensure_action("paddle_left")
	_ensure_keycode("paddle_left", KEY_A)
	_ensure_action("paddle_right")
	_ensure_keycode("paddle_right", KEY_D)

	if mode == 1:   # LOCAL_2P
		_erase_keycode("paddle_left", KEY_LEFT)
		_erase_keycode("paddle_right", KEY_RIGHT)
		_ensure_keycode(CONSTS.P2_LEFT_ACTION, KEY_LEFT)
		_ensure_keycode(CONSTS.P2_RIGHT_ACTION, KEY_RIGHT)
	else:           # SINGLE（默认，逐字节回归）
		_ensure_keycode("paddle_left", KEY_LEFT)
		_ensure_keycode("paddle_right", KEY_RIGHT)
		_erase_keycode(CONSTS.P2_LEFT_ACTION, KEY_LEFT)
		_erase_keycode(CONSTS.P2_RIGHT_ACTION, KEY_RIGHT)


static func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


static func _ensure_keycode(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.keycode == keycode:
			return
	var key := InputEventKey.new()
	key.keycode = keycode
	InputMap.action_add_event(action, key)


static func _erase_keycode(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.keycode == keycode:
			InputMap.action_erase_event(action, ev)

# ── State ──
var min_x: float = 0.0
var max_x: float = 0.0

# ── 共享 shape 隔离 (#526) ──
## 幂等隔离标志：shape 已 duplicate 到实例私有。set_paddle_width 可能先于 _ready() 被调用
## （如 TC-F10），届时直接改写共享 sub_resource 会污染同场景其他实例（TC-F12 断言 120 失败）。
## 该标志保证无论调用顺序如何，只 duplicate 一次，绝不改写场景共享的 RectangleShape2D。
var _shape_isolated: bool = false

# ── AI state ──
var _ball_node: Node2D = null
var _ai_delay_timer: float = 0.0
var _ai_target_x: float = 0.0
var _ai_error_offset: float = 0.0

# ── Combo Speed Feedback (#504) ──
## 连击加速反馈：2s 窗口内玩家再次得分 → 板速 +20%（乘性叠加于 paddle_speed）。
## 数值默认接 CONSTS（#387 AC3 先例），编辑器可调参（taste 校准 #367 域零代码改动）。
@export var combo_window_seconds: float = CONSTS.COMBO_WINDOW_SECONDS
@export var combo_speed_bonus: float = CONSTS.COMBO_SPEED_BONUS

var _combo_timer: float = 0.0            # 剩余窗口秒数（delta 累计，确定性）
var _combo_active: bool = false          # 连击成立 → 板速 +20%
var _last_player_score: int = -1         # -1 = 尚未见过任何得分（首分判定 + 重开检测基准）

# ── Debuff 定时状态 (#543) ──
## 与 #387 slow_time 的 set_speed_scale_timed 同构的三套定时状态 + 一个即时状态
## （DESIGN 543 §3.4）。freeze/slow/reverse 由 opponent 卡回调施加。
var _timed_freeze_remaining: float = 0.0    # freeze_opponent 临时冻结剩余秒数
var _speed_scale: float = 1.0               # slow_opponent 速度倍率（默认 1.0）
var _speed_scale_remaining: float = 0.0     # 减速剩余秒数（归零 → _speed_scale 恢复 1.0）
var _input_invert_remaining: float = 0.0    # reverse_opponent 左右方向反转剩余秒数


func _ready() -> void:
	# InputMap binding — only for player mode; guard against duplicate bindings
	# 竖屏 (#383): paddle_left(A/←) / paddle_right(D/→)；旧 paddle_up/paddle_down 已删除
	# #543: player_index==1（P2 顶侧）改绑 p2_left/p2_right（←/→，分键隔离，AC3）
	if mode == Mode.PLAYER:
		if player_index == 1:
			if not InputMap.has_action("p2_left"):
				InputMap.add_action("p2_left")
				var ev_left = InputEventKey.new()
				ev_left.keycode = KEY_LEFT
				InputMap.action_add_event("p2_left", ev_left)
			if not InputMap.has_action("p2_right"):
				InputMap.add_action("p2_right")
				var ev_right = InputEventKey.new()
				ev_right.keycode = KEY_RIGHT
				InputMap.action_add_event("p2_right", ev_right)
		else:
			if not InputMap.has_action("paddle_left"):
				InputMap.add_action("paddle_left")
				var ev_a = InputEventKey.new()
				ev_a.keycode = KEY_A
				InputMap.action_add_event("paddle_left", ev_a)
				var ev_left = InputEventKey.new()
				ev_left.keycode = KEY_LEFT
				InputMap.action_add_event("paddle_left", ev_left)

			if not InputMap.has_action("paddle_right"):
				InputMap.add_action("paddle_right")
				var ev_d = InputEventKey.new()
				ev_d.keycode = KEY_D
				InputMap.action_add_event("paddle_right", ev_d)
				var ev_right = InputEventKey.new()
				ev_right.keycode = KEY_RIGHT
				InputMap.action_add_event("paddle_right", ev_right)

		# #504: 只读消费 score_changed（全 kind 事件源）；autoload 缺失/未接线 → 跳过（G10）
		if GameManager != null and GameManager.has_signal("score_changed"):
			GameManager.score_changed.connect(_on_score_changed)

	# Boundary calculation from viewport size (X 轴, #383)
	base_paddle_width = paddle_width

	# #526（research 复核 2026-08-17）: player_paddle.tscn 的 RectangleShape2D sub_resource
	# 未设 resource_local_to_scene，PlayerPaddle/AIPaddle 双实例共享同一 shape 对象 —
	# set_paddle_width 改 shape.size.x 会连带改 AI 挡板碰撞体。每实例 duplicate() 隔离，
	# 玩家升级不影响 AI 碰撞体（节点名优先，动态构造未命名 → 遍历 fallback，同下风格）。
	var cs = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		for child in get_children():
			if child is CollisionShape2D:
				cs = child
				break
	if cs != null and cs.shape is RectangleShape2D:
		cs.shape = cs.shape.duplicate()
		_shape_isolated = true

	_sync_visual()
	_recalc_bounds()

	# Register with paddles group for ball collision detection
	add_to_group("paddles")

	# Resolve ball reference (AI mode) + initialize delay timer
	_ball_node = _resolve_ball()
	if mode == Mode.AI and _ai_delay_timer <= 0.0:
		_ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)


## #504: 连击窗口判定。仅 PLAYER 模式；得分增量 > 0 才推进状态。
## #543: 按 player_index 选分数通道（P2 顶侧看 ai_score，C2 互不污染）。
func _on_score_changed(player_score: int, ai_score: int) -> void:
	if mode != Mode.PLAYER:
		return
	var my_score: int = ai_score if player_index == 1 else player_score
	# 重开检测（边界 6）: GameManager.reset() 清零 → score 回退 → 复位连击（含基准回退，
	# 使重开后首分按"首分语义"处理并重新起算窗口 — G8 要求）
	if _last_player_score >= 0 and my_score < _last_player_score:
		_combo_active = false
		_combo_timer = 0.0
		_last_player_score = -1
	# 玩家得分: 窗口内再次得分 → 连击成立；首分（0-1 分）→ 不加速但窗口起算（裁决 3）
	if my_score > _last_player_score:
		_combo_active = _combo_timer > 0.0
		_combo_timer = combo_window_seconds
	_last_player_score = my_score


func _process(delta: float) -> void:
	# ── 定时状态递减（#543，先于任何 early-return）──
	_timed_freeze_remaining = max(0.0, _timed_freeze_remaining - delta)
	if _speed_scale_remaining > 0.0:
		_speed_scale_remaining = max(0.0, _speed_scale_remaining - delta)
		if _speed_scale_remaining <= 0.0:
			_speed_scale = 1.0
	_input_invert_remaining = max(0.0, _input_invert_remaining - delta)

	if is_effectively_frozen():
		return
	if mode == Mode.AI:
		_ai_process(delta)
		_apply_magnet(delta)
		return

	# ── 连击计时（#504，仅 PLAYER；冻结已 early-return → 冻结期不衰减，裁决 1）──
	if _combo_timer > 0.0:
		_combo_timer = max(0.0, _combo_timer - delta)
		if _combo_timer <= 0.0:
			_combo_active = false    # 窗口过期 → 恢复基速

	# #543: 按 player_index 选 action 对（P2 顶侧读 p2_left/p2_right，分键隔离）
	var left_action: String = "paddle_left" if player_index == 0 else "p2_left"
	var right_action: String = "paddle_right" if player_index == 0 else "p2_right"

	# Read input — simultaneous left+right cancels to zero
	var left := Input.is_action_pressed(left_action)
	var right := Input.is_action_pressed(right_action)
	var move: float = 0.0
	if left and not right:
		move = -1.0
	elif right and not left:
		move = 1.0

	# #543: 方向反转（reverse_opponent，仅 PLAYER 模式有意义）
	if _input_invert_remaining > 0.0:
		move = -move

	# #504: 连击有效速度（乘性叠加，基值 paddle_speed 不动）
	var effective_speed: float = paddle_speed
	if _combo_active:
		effective_speed = paddle_speed * (1.0 + combo_speed_bonus)

	# #543: slow_opponent 减速（_speed_scale 默认 1.0）
	# Apply movement (frame-rate independent) and clamp
	position.x += move * effective_speed * _speed_scale * delta
	_apply_magnet(delta)
	position.x = clamp(position.x, min_x, max_x)


func _resolve_ball() -> Node2D:
	# Primary path: sibling node named "Ball" in parent
	var parent = get_parent()
	if parent != null and parent.has_node("Ball"):
		return parent.get_node("Ball")
	# Fallback: scene-tree search (resilient to hierarchy changes)
	var tree = get_tree() if is_inside_tree() else null
	if tree != null:
		var root = tree.root
		if root != null and root.has_node("Game/Ball"):
			return root.get_node("Game/Ball")
	return null


func _ai_process(delta: float) -> void:
	if _ball_node == null:
		return

	# Decrement delay timer; on expiry, update target with new error
	_ai_delay_timer -= delta
	if _ai_delay_timer <= 0.0:
		_ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)
		_ai_error_offset = randf_range(-ai_position_error, ai_position_error)
		_ai_target_x = _ball_node.global_position.x + _ai_error_offset

	# Distance-based speed adjustment
	var dist: float = abs(position.x - _ai_target_x)
	var threshold: float = ai_position_error * 2.0  # 48px
	var factor: float = ai_speed_boost if dist >= threshold else ai_speed_slow

	# Move toward target and clamp
	var move: float = sign(_ai_target_x - position.x)
	position.x += move * paddle_speed * factor * delta
	position.x = clamp(position.x, min_x, max_x)


## #526: 视觉同步 — ColorRect offsets ← paddle_width/paddle_height（单一事实源）。
## 场景硬编码（-60..60/-10..10）保留作初始值，_ready() 运行时覆盖（零 diff、零回归）。
## 动态/测试构造的 paddle 无 ColorRect → 判空 no-op（与 set_paddle_width 现有 fallback 同风格）。
func _sync_visual() -> void:
	var cr = get_node_or_null("ColorRect") as ColorRect
	if cr == null:
		return
	var half_w := paddle_width / 2.0
	var half_h := paddle_height / 2.0
	cr.offset_left = -half_w
	cr.offset_right = half_w
	cr.offset_top = -half_h
	cr.offset_bottom = half_h


## #387 AC3/AC5: 长臂升级入口 — 同步实例属性 + CollisionShape2D.size.x（球读
## shape.size.x → 下一帧即时感知），并重算边界 + clamp（DESIGN §4.2 伪代码）。
func set_paddle_width(w: float) -> void:
	paddle_width = w
	# 同步碰撞体（球读 shape.size.x → 即时感知）。节点名优先（场景惯例
	# "CollisionShape2D"），动态/测试构造的节点可能未命名 → 遍历 fallback。
	var cs = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		for child in get_children():
			if child is CollisionShape2D:
				cs = child
				break
	if cs != null and cs.shape is RectangleShape2D:
		# #526: 幂等隔离 guard — 本函数可能在 _ready() 之前被调用（TC-F10），此时
		# shape 仍是场景共享 sub_resource，直接改 size.x 会污染同场景其他实例。
		# 已隔离则跳过（幂等，绝不重复 duplicate），也绝不改写共享对象。
		if not _shape_isolated:
			cs.shape = cs.shape.duplicate()
			_shape_isolated = true
		cs.shape.size.x = w
	_recalc_bounds()
	# #526: 效果写入点补表现层 — 玩家下一帧看到变宽（碰撞即时生效 + 视觉同步）
	_sync_visual()


func _recalc_bounds() -> void:
	var viewport = get_viewport()
	var w := FALLBACK_VIEWPORT_X
	if viewport != null:
		var vs := viewport.get_visible_rect().size
		if vs.x > 0.0:
			w = vs.x
	var half_width := paddle_width / 2.0
	min_x = half_width
	max_x = w - half_width
	position.x = clamp(position.x, min_x, max_x)


## 磁心 (#387): 磁力拉球 — 球 X 在半径内时向球 X 逼近（数值占位归 taste 域）。
func _apply_magnet(delta: float) -> void:
	if not magnet_enabled or _ball_node == null:
		return
	if abs(_ball_node.global_position.x - position.x) <= magnet_pull_radius:
		position.x = move_toward(position.x, _ball_node.global_position.x, magnet_pull_strength * delta)
		position.x = clamp(position.x, min_x, max_x)

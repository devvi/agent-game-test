extends Area2D
## Player paddle for mini-pong — A/D + Arrow key input, horizontal movement, boundary clamp.
## AI mode: tracks ball X position with reaction delay, position error, and speed adjustment.
## 竖屏 (#383): 挡板横置、沿 X 移动；输入 paddle_left(A/←)/paddle_right(D/→)；AI 追踪球 X。

const CONSTS = preload("res://gdscripts/constants.gd")

const FALLBACK_VIEWPORT_X: float = float(CONSTS.SCREEN_WIDTH)

# ── Mode enum ──
enum Mode { PLAYER = 0, AI = 1 }

@export var mode: Mode = Mode.PLAYER

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

# ── State ──
var min_x: float = 0.0
var max_x: float = 0.0

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


func _ready() -> void:
	# InputMap binding — only for player mode; guard against duplicate bindings
	# 竖屏 (#383): paddle_left(A/←) / paddle_right(D/→)；旧 paddle_up/paddle_down 已删除
	if mode == Mode.PLAYER:
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
	_recalc_bounds()

	# Register with paddles group for ball collision detection
	add_to_group("paddles")

	# Resolve ball reference (AI mode) + initialize delay timer
	_ball_node = _resolve_ball()
	if mode == Mode.AI and _ai_delay_timer <= 0.0:
		_ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)


## #504: 连击窗口判定。仅 PLAYER 模式；玩家得分增量 > 0 才推进状态。
func _on_score_changed(player_score: int, _ai_score: int) -> void:
	if mode != Mode.PLAYER:
		return
	# 重开检测（边界 6）: GameManager.reset() 清零 → score 回退 → 复位连击（含基准回退，
	# 使重开后首分按"首分语义"处理并重新起算窗口 — G8 要求）
	if _last_player_score >= 0 and player_score < _last_player_score:
		_combo_active = false
		_combo_timer = 0.0
		_last_player_score = -1
	# 玩家得分: 窗口内再次得分 → 连击成立；首分（0-1 分）→ 不加速但窗口起算（裁决 3）
	if player_score > _last_player_score:
		_combo_active = _combo_timer > 0.0
		_combo_timer = combo_window_seconds
	_last_player_score = player_score


func _process(delta: float) -> void:
	if frozen:
		return
	if mode == Mode.AI:
		_ai_process(delta)
		_apply_magnet(delta)
		return

	# ── 连击计时（#504，仅 PLAYER；frozen 已 early-return → 冻结期不衰减，裁决 1）──
	if _combo_timer > 0.0:
		_combo_timer = max(0.0, _combo_timer - delta)
		if _combo_timer <= 0.0:
			_combo_active = false    # 窗口过期 → 恢复基速

	# Read input — simultaneous left+right cancels to zero
	var left := Input.is_action_pressed("paddle_left")
	var right := Input.is_action_pressed("paddle_right")
	var move: float = 0.0
	if left and not right:
		move = -1.0
	elif right and not left:
		move = 1.0

	# #504: 连击有效速度（乘性叠加，基值 paddle_speed 不动）
	var effective_speed: float = paddle_speed
	if _combo_active:
		effective_speed = paddle_speed * (1.0 + combo_speed_bonus)

	# Apply movement (frame-rate independent) and clamp
	position.x += move * effective_speed * delta
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
		cs.shape.size.x = w
	_recalc_bounds()


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

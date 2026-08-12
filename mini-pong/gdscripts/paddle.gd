extends Area2D
## Player paddle for mini-pong — A/D + Arrow key input, horizontal movement, boundary clamp.
## AI mode: tracks ball X position with reaction delay, position error, and speed adjustment.
## 竖屏 (#383): 挡板横置、沿 X 移动；输入 paddle_left(A/←)/paddle_right(D/→)；AI 追踪球 X。

const CONSTS = preload("res://gdscripts/constants.gd")

const SPEED: float = CONSTS.PADDLE_SPEED
const PADDLE_WIDTH: float = CONSTS.PADDLE_WIDTH
const PADDLE_HEIGHT: float = CONSTS.PADDLE_HEIGHT
const FALLBACK_VIEWPORT_X: float = float(CONSTS.SCREEN_WIDTH)

# ── Mode enum ──
enum Mode { PLAYER = 0, AI = 1 }

@export var mode: Mode = Mode.PLAYER

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

	# Boundary calculation from viewport size (X 轴, #383)
	var viewport = get_viewport()
	var w := FALLBACK_VIEWPORT_X
	if viewport != null:
		var vs := viewport.get_visible_rect().size
		if vs.x > 0.0:
			w = vs.x
	var half_width := PADDLE_WIDTH / 2.0
	min_x = half_width
	max_x = w - half_width

	# Clamp initial position (safety net)
	position.x = clamp(position.x, min_x, max_x)

	# Register with paddles group for ball collision detection
	add_to_group("paddles")

	# Resolve ball reference (AI mode) + initialize delay timer
	_ball_node = _resolve_ball()
	if mode == Mode.AI and _ai_delay_timer <= 0.0:
		_ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)


func _process(delta: float) -> void:
	if frozen:
		return
	if mode == Mode.AI:
		_ai_process(delta)
		return

	# Read input — simultaneous left+right cancels to zero
	var left := Input.is_action_pressed("paddle_left")
	var right := Input.is_action_pressed("paddle_right")
	var move: float = 0.0
	if left and not right:
		move = -1.0
	elif right and not left:
		move = 1.0

	# Apply movement (frame-rate independent) and clamp
	position.x += move * SPEED * delta
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
	position.x += move * SPEED * factor * delta
	position.x = clamp(position.x, min_x, max_x)

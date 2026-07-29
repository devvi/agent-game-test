extends Area2D
## Player paddle for mini-pong — WASD/Arrow key input, vertical movement, boundary clamp.
## AI mode: tracks ball Y position with reaction delay, position error, and speed adjustment.

const SPEED: float = 400.0
const PADDLE_WIDTH: float = 20.0
const PADDLE_HEIGHT: float = 120.0
const FALLBACK_VIEWPORT_Y: float = 720.0

# ── Mode enum ──
enum Mode { PLAYER = 0, AI = 1 }

@export var mode: Mode = Mode.PLAYER

# ── AI parameters (tunable in editor) ──
@export var ai_reaction_delay_min: float = 0.1   # 100ms
@export var ai_reaction_delay_max: float = 0.3   # 300ms
@export var ai_position_error: float = 20.0       # ±20px
@export var ai_speed_boost: float = 1.2           # +20% when trailing
@export var ai_speed_slow: float = 0.8            # -20% when ahead

# ── State ──
var min_y: float = 0.0
var max_y: float = 0.0

# ── AI state ──
var _ball_node: Node2D = null
var _ai_delay_timer: float = 0.0
var _ai_target_y: float = 0.0
var _ai_error_offset: float = 0.0


func _ready() -> void:
	# InputMap binding — only for player mode; guard against duplicate bindings
	if mode == Mode.PLAYER:
		if not InputMap.has_action("paddle_up"):
			InputMap.add_action("paddle_up")
			var ev_w = InputEventKey.new()
			ev_w.keycode = KEY_W
			InputMap.action_add_event("paddle_up", ev_w)
			var ev_up = InputEventKey.new()
			ev_up.keycode = KEY_UP
			InputMap.action_add_event("paddle_up", ev_up)

		if not InputMap.has_action("paddle_down"):
			InputMap.add_action("paddle_down")
			var ev_s = InputEventKey.new()
			ev_s.keycode = KEY_S
			InputMap.action_add_event("paddle_down", ev_s)
			var ev_down = InputEventKey.new()
			ev_down.keycode = KEY_DOWN
			InputMap.action_add_event("paddle_down", ev_down)

	# Boundary calculation from viewport size
	var viewport := get_viewport()
	var h := FALLBACK_VIEWPORT_Y
	if viewport != null:
		var vs := viewport.get_visible_rect().size
		if vs.y > 0.0:
			h = vs.y
	var half_height := PADDLE_HEIGHT / 2.0
	min_y = half_height
	max_y = h - half_height

	# Clamp initial position (safety net)
	position.y = clamp(position.y, min_y, max_y)

	# Register with paddles group for ball collision detection
	add_to_group("paddles")

	# Resolve ball reference (AI mode) + initialize delay timer
	_ball_node = _resolve_ball()
	if mode == Mode.AI and _ai_delay_timer <= 0.0:
		_ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)


func _process(delta: float) -> void:
	if mode == Mode.AI:
		_ai_process(delta)
		return

	# Read input — simultaneous up+down cancels to zero
	var up := Input.is_action_pressed("paddle_up")
	var down := Input.is_action_pressed("paddle_down")
	var move: float = 0.0
	if up and not down:
		move = -1.0
	elif down and not up:
		move = 1.0

	# Apply movement (frame-rate independent) and clamp
	position.y += move * SPEED * delta
	position.y = clamp(position.y, min_y, max_y)


func _resolve_ball() -> Node2D:
	# Primary path: sibling node named "Ball" in parent
	var parent := get_parent()
	if parent != null and parent.has_node("Ball"):
		return parent.get_node("Ball")
	# Fallback: scene-tree search (resilient to hierarchy changes)
	var tree := get_tree()
	if tree != null:
		var root := tree.root
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
		_ai_target_y = _ball_node.global_position.y + _ai_error_offset

	# Distance-based speed adjustment
	var dist: float = abs(position.y - _ai_target_y)
	var threshold: float = ai_position_error * 2.0  # 40px
	var factor: float = ai_speed_boost if dist >= threshold else ai_speed_slow

	# Move toward target and clamp
	var move: float = sign(_ai_target_y - position.y)
	position.y += move * SPEED * factor * delta
	position.y = clamp(position.y, min_y, max_y)

extends Area2D
## Player paddle for mini-pong — WASD/Arrow key input, vertical movement, boundary clamp.

const SPEED: float = 400.0
const PADDLE_WIDTH: float = 20.0
const PADDLE_HEIGHT: float = 120.0
const FALLBACK_VIEWPORT_Y: float = 720.0

var min_y: float = 0.0
var max_y: float = 0.0


func _ready() -> void:
	# InputMap binding — guard against duplicate bindings on re-instantiation
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


func _process(delta: float) -> void:
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

extends CharacterBody3D
class_name PlayerController

# ── Exports ──
@export var walk_speed: float = 2.5            # m/s — leisurely narrative pace
@export var look_sensitivity: float = 0.003     # radians per pixel
@export var interaction_range: float = 2.0      # meters — E-key proximity
@export var camera_height: float = 1.6          # meters — eye level
@export var camera_tilt: float = -0.087         # radians (~-5°) slight downward tilt
@export var look_vertical_clamp: float = 1.047  # radians (60°) — ±60° vertical look

# ── Nodes ──
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_area: Area3D = $InteractionArea

# ── State ──
var _dialogue_active: bool = false
var _mouse_dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _nearby_interactables: Array[Node] = []  # LIFO stack of nearby interactable nodes
var _fall_reset_position: Vector3 = Vector3.ZERO

# ── Signals ──
signal interaction_requested(target: Node)
signal dialogue_mode_changed(active: bool)


func _ready() -> void:
	add_to_group("player")
	camera.current = true
	head.rotation.x = camera_tilt  # slight downward tilt

	# Interaction area setup
	if interaction_area:
		interaction_area.body_entered.connect(_on_interaction_body_entered)
		interaction_area.body_exited.connect(_on_interaction_body_exited)

	# Set camera current and disable other cameras
	_disable_other_cameras()

	# Connect to dialogue runner for mode changes
	_connect_dialogue_signals()


func _disable_other_cameras() -> void:
	# Ensure this PlayerController's camera is the only active one
	for c in get_tree().get_nodes_in_group("Cameras"):
		if c != camera:
			c.current = false


func _connect_dialogue_signals() -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var dr := scene_root.get_node_or_null("CanvasLayer/DialoguePanel")
	if dr:
		if dr.has_signal("dialogue_started"):
			dr.dialogue_started.connect(_on_dialogue_started)
		if dr.has_signal("dialogue_ended"):
			dr.dialogue_ended.connect(_on_dialogue_ended)


# ── Input ──

func _input(event: InputEvent) -> void:
	# Mouse look: click-and-drag (button held)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _dialogue_active:
			_mouse_dragging = true
			_last_mouse_pos = event.global_position
		elif not event.pressed:
			_mouse_dragging = false

	if event is InputEventMouseMotion and _mouse_dragging and not _dialogue_active:
		var delta: Vector2 = event.global_position - _last_mouse_pos
		_last_mouse_pos = event.global_position
		_handle_mouse_look(delta)

	# E-key interaction (only when not in dialogue)
	if event.is_action_pressed("interact") and not _dialogue_active:
		_try_interact()

	# Dialogue mode: route E to dialogue_select
	if _dialogue_active and event.is_action_pressed("interact"):
		_route_to_dialogue_select()


func _handle_mouse_look(delta: Vector2) -> void:
	if not head:
		return
	# Yaw: rotate entire body (horizontal look)
	rotate_y(-delta.x * look_sensitivity)

	# Pitch: rotate head only (vertical look), clamped
	var pitch_delta: float = -delta.y * look_sensitivity
	head.rotation.x = clamp(
		head.rotation.x + pitch_delta,
		-look_vertical_clamp + camera_tilt,
		look_vertical_clamp + camera_tilt
	)


func _try_interact() -> void:
	if _nearby_interactables.is_empty():
		return
	# LIFO: interact with the most recent body_entered
	var target: Node = _nearby_interactables.back()
	if not is_instance_valid(target):
		_nearby_interactables.pop_back()
		_try_interact()  # recurse to next valid
		return
	interaction_requested.emit(target)


func _route_to_dialogue_select() -> void:
	# Only route E to dialogue if the dialogue runner is expecting input
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var dr := scene_root.get_node_or_null("CanvasLayer/DialoguePanel")
	if dr and dr.has_method("select_current") and dr.visible:
		dr.select_current()


# ── Physics ──

func _physics_process(delta: float) -> void:
	# Skip movement during dialogue
	if _dialogue_active:
		# Apply gentle braking if any residual velocity
		velocity = velocity.move_toward(Vector3.ZERO, walk_speed * delta)
		move_and_slide()
		return

	# WASD input relative to camera facing
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right",
		"move_forward", "move_backward"
	)

	# Project camera forward onto XZ plane (ignore pitch)
	var camera_basis: Basis = head.global_transform.basis
	var forward: Vector3 = -camera_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = camera_basis.x
	right.y = 0.0
	right = right.normalized()

	var direction: Vector3 = Vector3.ZERO
	direction += forward * -input_dir.y  # move_forward/backward
	direction += right * input_dir.x     # move_left/right
	direction = direction.normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * walk_speed
		velocity.z = direction.z * walk_speed
	else:
		# Deceleration
		velocity.x = move_toward(velocity.x, 0.0, walk_speed)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed)

	move_and_slide()


# ── Interaction Proximity ──

func _on_interaction_body_entered(body: Node) -> void:
	if body.is_in_group("interactable") and not _nearby_interactables.has(body):
		_nearby_interactables.append(body)


func _on_interaction_body_exited(body: Node) -> void:
	_nearby_interactables.erase(body)


# ── Dialogue Mode ──

func _on_dialogue_started(_dialogue_id: String) -> void:
	_dialogue_active = true
	dialogue_mode_changed.emit(true)


func _on_dialogue_ended() -> void:
	_dialogue_active = false
	dialogue_mode_changed.emit(false)


# ── Fall Recovery ──

func set_fall_reset_position(pos: Vector3) -> void:
	_fall_reset_position = pos


func _on_fall_detector_body_entered(body: Node) -> void:
	if body == self:
		global_position = _fall_reset_position
		velocity = Vector3.ZERO

extends CharacterBody3D
class_name PlayerController

# ── Exports ──
@export_range(0.5, 10.0, 0.1) var walk_speed: float = 2.5            # m/s — leisurely narrative pace
@export_range(0.001, 0.02, 0.0005) var look_sensitivity: float = 0.003     # radians per pixel
@export_range(0.5, 10.0, 0.1) var interaction_range: float = 2.0      # meters — E-key proximity
@export_range(0.5, 3.0, 0.1) var camera_height: float = 1.6          # meters — eye level
@export_range(-1.0, 1.0, 0.001) var camera_tilt: float = -0.087         # radians (~-5°) slight downward tilt
@export_range(0.174, 1.57, 0.01) var look_vertical_clamp: float = 1.047  # radians (60°) — ±60° vertical look

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


func _build_node_tree() -> void:
	# Build Head node (pitch rotation mount for camera)
	if not has_node("Head"):
		var head_node := Node3D.new()
		head_node.name = "Head"
		add_child(head_node)
		head_node.owner = self

	# Build Camera3D child of Head
	if not has_node("Head/Camera3D"):
		var cam := Camera3D.new()
		cam.name = "Camera3D"
		cam.position = Vector3(0, camera_height, 0)
		cam.current = true
		$Head.add_child(cam)
		cam.owner = $Head

	# Build InteractionArea (proximity trigger for E-key)
	if not has_node("InteractionArea"):
		var area := Area3D.new()
		area.name = "InteractionArea"
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = interaction_range
		shape.shape = sphere
		area.add_child(shape)
		shape.owner = area
		add_child(area)
		area.owner = self

	# Build FallReset area (detects player falling off world)
	if not has_node("FallReset"):
		var fall := Area3D.new()
		fall.name = "FallReset"
		var fall_shape := CollisionShape3D.new()
		fall_shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(1000, 0.5, 1000)  # Huge floor sensor
		fall_shape.shape = box
		fall_shape.position = Vector3(0, -100, 0)  # Below all walkable surfaces
		fall.add_child(fall_shape)
		fall_shape.owner = fall
		add_child(fall)
		fall.owner = self
		fall.body_entered.connect(_on_fall_detector_body_entered)


func _build_collision_shape() -> void:
	# Build CapsuleShape3D on the root CharacterBody3D
	if not has_node("PlayerCollisionShape"):
		var shape := CollisionShape3D.new()
		shape.name = "PlayerCollisionShape"
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.4
		shape.shape = capsule
		shape.position = Vector3(0, 0.7, 0)  # Half-height offset
		add_child(shape)
		shape.owner = self


func _ready() -> void:
	# Build node tree before accessing @onready vars
	_build_node_tree()
	_build_collision_shape()

	# Reassign @onready vars since they were set to null before nodes existed
	head = $Head
	camera = $Head/Camera3D
	interaction_area = $InteractionArea

	add_to_group("player")
	camera.current = true
	head.rotation.x = camera_tilt  # slight downward tilt

	# Verify required InputMap actions exist
	_verify_input_map()

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


func _verify_input_map() -> void:
	var actions := ["move_forward", "move_backward", "move_left", "move_right", "interact"]
	for action in actions:
		if not InputMap.has_action(action):
			push_warning("PlayerController: Input action '%s' not found in InputMap" % action)


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
	# Use clamped walk_speed for runtime safety (headless mode bypasses @export_range)
	var effective_speed: float = clamp(walk_speed, 0.5, 10.0)

	# Skip movement during dialogue
	if _dialogue_active:
		# Apply gentle braking if any residual velocity
		velocity = velocity.move_toward(Vector3.ZERO, effective_speed * delta)
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
		velocity.x = direction.x * effective_speed
		velocity.z = direction.z * effective_speed
	else:
		# Deceleration
		velocity.x = move_toward(velocity.x, 0.0, effective_speed)
		velocity.z = move_toward(velocity.z, 0.0, effective_speed)

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

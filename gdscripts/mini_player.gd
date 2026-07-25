extends CharacterBody3D

@export var walk_speed: float = 5.0

func _ready() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	var key_bindings = {
		"move_forward": KEY_W,
		"move_backward": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
	}

	for action_name in key_bindings:
		var event = InputEventKey.new()
		event.keycode = key_bindings[action_name]
		InputMap.action_add_event(action_name, event)

	var capsule = CapsuleShape3D.new()
	capsule.height = 2.0
	capsule.radius = 0.5

	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0, 1.0, 0)
	add_child(collision_shape)

func get_movement_vector() -> Vector3:
	var input_dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.z -= 1
	if Input.is_action_pressed("move_backward"):
		input_dir.z += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	return input_dir.normalized()

func _physics_process(delta: float) -> void:
	var input_vector = get_movement_vector()
	if input_vector != Vector3.ZERO:
		velocity.x = input_vector.x * walk_speed
		velocity.z = input_vector.z * walk_speed
	else:
		velocity.x = move_toward(velocity.x, 0, walk_speed)
		velocity.z = move_toward(velocity.z, 0, walk_speed)
	move_and_slide()

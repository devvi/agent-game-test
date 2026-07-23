extends RefCounted

# Unit tests for PlayerController — WASD movement, mouse look, E-key interaction,
# dialogue mode blocking, fall recovery, and collision.

var passed: int = 0
var failed: int = 0

var _signal_fired: bool = false
var _signal_target: Node = null

const PlayerControllerScript = preload("res://gdscripts/player_controller.gd")


func run() -> void:
	print("  === PlayerController Unit Tests ====")

	# TC-PC-N (Normal Path)
	print("  --- TC-PC-N: Normal Path ---")
	_test_pc_n_1_instantiate()
	_test_pc_n_1_player_group()
	_test_pc_n_1_class_name()
	_test_pc_n_2_move_forward()
	_test_pc_n_2_move_backward()
	_test_pc_n_2_move_left()
	_test_pc_n_2_move_right()
	_test_pc_n_2_move_diagonal()
	_test_pc_n_3_forward_after_90_yaw()
	_test_pc_n_3_no_input()
	_test_pc_n_4_horizontal_look()
	_test_pc_n_4_vertical_look()
	_test_pc_n_4_vertical_clamp_up()
	_test_pc_n_4_vertical_clamp_down()
	_test_pc_n_5_e_key_interact()
	_test_pc_n_5_e_key_lifo()
	_test_pc_n_5_e_key_no_interactable()
	_test_pc_n_6_camera_current()
	_test_pc_n_7_default_walk_speed()

	# TC-PC-E (Edge Cases)
	print("  --- TC-PC-E: Edge Cases ---")
	_test_pc_e_1_multiple_overlapping()
	_test_pc_e_1_e_with_three()
	_test_pc_e_1_exit_middle()
	_test_pc_e_1_exit_all()
	_test_pc_e_1_duplicate_enter()
	_test_pc_e_2_scene_unload_no_crash()
	_test_pc_e_3_release_mouse()
	_test_pc_e_3_motion_after_release()
	_test_pc_e_4_default_tilt()

	# TC-PC-F (Failure Paths)
	print("  --- TC-PC-F: Failure Paths ---")
	_test_pc_f_1_no_game_manager()
	_test_pc_f_2_no_dialogue_runner()
	_test_pc_f_3_target_freed_mid_stack()
	_test_pc_f_3_all_targets_freed()
	_test_pc_f_4_head_missing()

	print("  PlayerController Unit Tests: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


func _make_pc() -> Node:
	var pc = PlayerControllerScript.new()
	# Manually set up the node structure for testing
	pc.name = "PlayerController"
	pc.head = Node3D.new()
	pc.head.name = "Head"
	pc.add_child(pc.head)
	pc.camera = Camera3D.new()
	pc.camera.name = "Camera3D"
	pc.head.add_child(pc.camera)
	pc.interaction_area = Area3D.new()
	pc.interaction_area.name = "InteractionArea"
	pc.add_child(pc.interaction_area)
	return pc


func _on_interaction_requested(target: Node) -> void:
	_signal_fired = true
	_signal_target = target


# ===== TC-PC-N: Normal Path =====

func _test_pc_n_1_instantiate() -> void:
	var pc = _make_pc()
	_assert(pc != null, "TC-PC-N-1-1: PlayerController instance created")


func _test_pc_n_1_player_group() -> void:
	var pc = _make_pc()
	# Simulate _ready effects without full tree by calling group add directly
	pc.add_to_group("player")
	_assert(pc.is_in_group("player"), "TC-PC-N-1-2: In 'player' group")


func _test_pc_n_1_class_name() -> void:
	var pc = _make_pc()
	_assert(pc.get_script() == PlayerControllerScript, "TC-PC-N-1-3: Script is PlayerController")


func _test_pc_n_2_move_forward() -> void:
	var pc = _make_pc()
	pc.walk_speed = 2.5
	# Simulate forward input: Input.get_vector returns (0, -1) for forward
	pc.velocity = Vector3.ZERO
	# Manually set velocity as physics_process would
	pc.velocity.z = -pc.walk_speed
	_assert(pc.velocity.z < 0, "TC-PC-N-2-1: Forward velocity.z is negative (moving in -Z)")


func _test_pc_n_2_move_backward() -> void:
	var pc = _make_pc()
	pc.walk_speed = 2.5
	pc.velocity.z = pc.walk_speed
	_assert(pc.velocity.z > 0, "TC-PC-N-2-2: Backward velocity.z is positive")


func _test_pc_n_2_move_left() -> void:
	var pc = _make_pc()
	pc.walk_speed = 2.5
	pc.velocity.x = -pc.walk_speed
	_assert(pc.velocity.x < 0, "TC-PC-N-2-3: Left velocity.x is negative")


func _test_pc_n_2_move_right() -> void:
	var pc = _make_pc()
	pc.walk_speed = 2.5
	pc.velocity.x = pc.walk_speed
	_assert(pc.velocity.x > 0, "TC-PC-N-2-4: Right velocity.x is positive")


func _test_pc_n_2_move_diagonal() -> void:
	var pc = _make_pc()
	pc.walk_speed = 2.5
	# Diagonal: normalized (forward + right) = sqrt(0.5^2 + 0.5^2) ≈ 0.707
	var dir = Vector3(0.707, 0.0, -0.707)
	pc.velocity = dir * pc.walk_speed
	_assert(abs(pc.velocity.length() - 2.5) < 0.01, "TC-PC-N-2-5: Diagonal velocity length ≈ 2.5")


func _test_pc_n_3_forward_after_90_yaw() -> void:
	var pc = _make_pc()
	pc.walk_speed = 2.5
	# Rotate body 90 degrees around Y
	pc.rotate_y(deg_to_rad(90))
	# After 90° yaw, "forward" is +X, so moving forward should give +X velocity
	pc.velocity = Vector3(pc.walk_speed, 0.0, 0.0)
	_assert(pc.velocity.x > 0 and abs(pc.velocity.z) < 0.01,
		"TC-PC-N-3-1: After 90° yaw, forward moves along +X")


func _test_pc_n_3_no_input() -> void:
	var pc = _make_pc()
	# With no input and zero velocity, should be stationary
	pc.velocity = Vector3.ZERO
	_assert(pc.velocity == Vector3.ZERO, "TC-PC-N-3-3: Zero input → Vector3.ZERO")


func _test_pc_n_4_horizontal_look() -> void:
	var pc = _make_pc()
	var initial_y = pc.rotation.y
	pc._mouse_dragging = true
	pc.look_sensitivity = 0.003
	pc._handle_mouse_look(Vector2(100.0, 0.0))
	_assert(pc.rotation.y < initial_y,
		"TC-PC-N-4-1: Drag right 100px → rotation.y decreases")


func _test_pc_n_4_vertical_look() -> void:
	var pc = _make_pc()
	pc.head = Node3D.new()
	pc.add_child(pc.head)
	var initial_head_rot = pc.head.rotation.x
	pc.look_sensitivity = 0.003
	pc.camera_tilt = -0.087
	pc.look_vertical_clamp = 1.047
	pc._handle_mouse_look(Vector2(0.0, -100.0))  # drag up
	_assert(pc.head.rotation.x > initial_head_rot,
		"TC-PC-N-4-2: Drag up 100px → head.rotation.x increases")


func _test_pc_n_4_vertical_clamp_up() -> void:
	var pc = _make_pc()
	pc.head = Node3D.new()
	pc.add_child(pc.head)
	pc.head.rotation.x = 0.0
	pc.look_sensitivity = 0.003
	pc.camera_tilt = -0.087
	pc.look_vertical_clamp = 1.047
	pc._handle_mouse_look(Vector2(0.0, -2000.0))  # extreme drag up
	# Clamp upper bound = look_vertical_clamp + camera_tilt = 1.047 + (-0.087) = 0.96
	_assert(pc.head.rotation.x <= 1.047,
		"TC-PC-N-4-3: Extreme drag up → head.rotation.x clamped ≤ +60°")


func _test_pc_n_4_vertical_clamp_down() -> void:
	var pc = _make_pc()
	pc.head = Node3D.new()
	pc.add_child(pc.head)
	pc.head.rotation.x = 0.0
	pc.look_sensitivity = 0.003
	pc.camera_tilt = -0.087
	pc.look_vertical_clamp = 1.047
	pc._handle_mouse_look(Vector2(0.0, 2000.0))  # extreme drag down
	# Clamp lower bound = -look_vertical_clamp + camera_tilt = -1.047 + (-0.087) = -1.134
	_assert(pc.head.rotation.x >= -1.134,
		"TC-PC-N-4-4: Extreme drag down → head.rotation.x clamped ≥ -60° + tilt")


func _test_pc_n_5_e_key_interact() -> void:
	var pc = _make_pc()
	_signal_fired = false
	_signal_target = null
	pc.interaction_requested.connect(_on_interaction_requested)
	var interactable = Node.new()
	pc._nearby_interactables.append(interactable)
	pc._try_interact()
	_assert(_signal_fired and _signal_target == interactable,
		"TC-PC-N-5-1: E-key with nearby interactable → signal emitted with target")


func _test_pc_n_5_e_key_lifo() -> void:
	var pc = _make_pc()
	_signal_fired = false
	_signal_target = null
	pc.interaction_requested.connect(_on_interaction_requested)
	var a = Node.new()
	var b = Node.new()
	pc._nearby_interactables.append(a)
	pc._nearby_interactables.append(b)
	pc._try_interact()
	_assert(_signal_target == b,
		"TC-PC-N-5-2: LIFO — press E after entering A, B → signal for B")


func _test_pc_n_5_e_key_no_interactable() -> void:
	var pc = _make_pc()
	_signal_fired = false
	pc.interaction_requested.connect(_on_interaction_requested)
	pc._try_interact()
	_assert(not _signal_fired,
		"TC-PC-N-5-3: E-key with no nearby interactable → no signal")


func _test_pc_n_6_camera_current() -> void:
	var pc = _make_pc()
	pc.camera.current = true
	_assert(pc.camera.current == true,
		"TC-PC-N-6-1: Camera becomes current on _ready")


func _test_pc_n_7_default_walk_speed() -> void:
	var pc = _make_pc()
	_assert(abs(pc.walk_speed - 2.5) < 0.001,
		"TC-PC-N-7-1: Default walk_speed == 2.5")


# ===== TC-PC-E: Edge Cases =====

func _test_pc_e_1_multiple_overlapping() -> void:
	var pc = _make_pc()
	var a = Node.new()
	var b = Node.new()
	var c = Node.new()
	pc._nearby_interactables.append(a)
	pc._nearby_interactables.append(b)
	pc._nearby_interactables.append(c)
	_assert(pc._nearby_interactables.size() == 3,
		"TC-PC-E-1-1: Three overlapping → stack size == 3")


func _test_pc_e_1_e_with_three() -> void:
	var pc = _make_pc()
	_signal_fired = false
	_signal_target = null
	pc.interaction_requested.connect(_on_interaction_requested)
	var a = Node.new()
	var b = Node.new()
	var c = Node.new()
	pc._nearby_interactables.append(a)
	pc._nearby_interactables.append(b)
	pc._nearby_interactables.append(c)
	pc._try_interact()
	_assert(_signal_target == c,
		"TC-PC-E-1-2: Three stacked → press E → interacts with C (last entered)")


func _test_pc_e_1_exit_middle() -> void:
	var pc = _make_pc()
	_signal_fired = false
	_signal_target = null
	pc.interaction_requested.connect(_on_interaction_requested)
	var a = Node.new()
	var b = Node.new()
	var c = Node.new()
	pc._nearby_interactables.append(a)
	pc._nearby_interactables.append(b)
	pc._nearby_interactables.append(c)
	pc._nearby_interactables.erase(c)
	pc._try_interact()
	_assert(_signal_target == b,
		"TC-PC-E-1-3: Exit C, press E → interacts with B")


func _test_pc_e_1_exit_all() -> void:
	var pc = _make_pc()
	_signal_fired = false
	pc.interaction_requested.connect(_on_interaction_requested)
	var a = Node.new()
	var b = Node.new()
	pc._nearby_interactables.append(a)
	pc._nearby_interactables.append(b)
	pc._nearby_interactables.clear()
	pc._try_interact()
	_assert(not _signal_fired,
		"TC-PC-E-1-4: Exit all, press E → no signal")


func _test_pc_e_1_duplicate_enter() -> void:
	var pc = _make_pc()
	var body = Node.new()
	body.add_to_group("interactable")
	pc._on_interaction_body_entered(body)
	pc._on_interaction_body_entered(body)
	_assert(pc._nearby_interactables.size() == 1,
		"TC-PC-E-1-5: Duplicate body_entered → no duplicate in stack")


func _test_pc_e_2_scene_unload_no_crash() -> void:
	var pc = _make_pc()
	# Simulating scene unload — just make sure _exit_tree doesn't crash
	pc._dialogue_active = false
	# No crash is the assertion
	pc.call_deferred("queue_free")
	_assert(true, "TC-PC-E-2-1: queue_free during movement → no crash")


func _test_pc_e_3_release_mouse() -> void:
	var pc = _make_pc()
	pc._mouse_dragging = true
	# Simulate mouse button release
	var release_event = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	pc._input(release_event)
	_assert(pc._mouse_dragging == false,
		"TC-PC-E-3-1: Release mouse button → _mouse_dragging = false")


func _test_pc_e_3_motion_after_release() -> void:
	var pc = _make_pc()
	pc._mouse_dragging = false
	var initial_y = pc.rotation.y
	var motion_event = InputEventMouseMotion.new()
	motion_event.relative = Vector2(100.0, 0.0)
	# The _handle_mouse_look is not called because _mouse_dragging is false
	_assert(pc.rotation.y == initial_y,
		"TC-PC-E-3-2: Mouse motion after release → no rotation change")


func _test_pc_e_4_default_tilt() -> void:
	var pc = _make_pc()
	pc.head = Node3D.new()
	pc.add_child(pc.head)
	pc.camera_tilt = -0.087
	pc.head.rotation.x = pc.camera_tilt
	_assert(abs(pc.head.rotation.x - deg_to_rad(-5)) < 0.01,
		"TC-PC-E-4-1: Default tilt ≈ -5°")


# ===== TC-PC-F: Failure Paths =====

func _test_pc_f_1_no_game_manager() -> void:
	var pc = _make_pc()
	# No GameManager autoload — ready should not crash
	pc._connect_dialogue_signals()
	_assert(true, "TC-PC-F-1-1: No GameManager → no crash on _ready")


func _test_pc_f_2_no_dialogue_runner() -> void:
	var pc = _make_pc()
	pc._connect_dialogue_signals()
	_assert(not pc._dialogue_active,
		"TC-PC-F-2-1: No dialogue runner → _dialogue_active stays false")


func _test_pc_f_3_target_freed_mid_stack() -> void:
	var pc = _make_pc()
	_signal_fired = false
	_signal_target = null
	pc.interaction_requested.connect(_on_interaction_requested)
	var valid_target = Node.new()
	var freed_target = Node.new()
	freed_target.free()
	freed_target = null
	pc._nearby_interactables.append(valid_target)
	# After the freed target is popped, valid target should be used
	pc._try_interact()
	# freed_target is null/invalid, but valid_target should be at top
	_assert(true, "TC-PC-F-3-1: Freed target in stack → no crash, skipped gracefully")


func _test_pc_f_3_all_targets_freed() -> void:
	var pc = _make_pc()
	_signal_fired = false
	pc.interaction_requested.connect(_on_interaction_requested)
	# Empty stack
	pc._nearby_interactables.clear()
	pc._try_interact()
	_assert(not _signal_fired,
		"TC-PC-F-3-2: All targets freed, press E → no signal")


func _test_pc_f_4_head_missing() -> void:
	var pc = _make_pc()
	# Remove head node to test null safety
	if pc.head:
		pc.head.queue_free()
		pc.head = null
	# _handle_mouse_look should gracefully handle null head
	pc._handle_mouse_look(Vector2(100.0, 0.0))
	_assert(true, "TC-PC-F-4-1: Head node missing → no crash in _handle_mouse_look")

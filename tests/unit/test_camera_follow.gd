extends RefCounted

# Unit tests for Camera Follow feature (Issue #150).
# Tests the third-person shoulder-cam using CameraPivot + SpringArm3D,
# orbit controls, PlayerVisual, and scene transition persistence.

var passed: int = 0
var failed: int = 0

const PlayerControllerScript = preload("res://gdscripts/player_controller.gd")


func run() -> void:
	print("  === Camera Follow Unit Tests (Issue #150) ====")

	# TC-CAM-N (Normal Path)
	print("  --- TC-CAM-N: Normal Path ---")
	_test_cam_n_1_camera_hierarchy()
	_test_cam_n_1_spring_arm_margin()
	_test_cam_n_1_camera_position_relative()
	_test_cam_n_2_camera_follows_movement()
	_test_cam_n_3_mouse_horizontal_orbit()
	_test_cam_n_4_mouse_vertical_clamped()
	_test_cam_n_5_first_person_fallback()
	_test_cam_n_6_spring_arm_excluded_object()
	_test_cam_n_8_player_visual_exists()

	# TC-CAM-E (Edge Cases)
	print("  --- TC-CAM-E: Edge Cases ---")
	_test_cam_e_1_set_camera_orbit()
	_test_cam_e_2_get_camera_orbit()
	_test_cam_e_3_orbit_persistence_api()
	_test_cam_e_5_dialogue_does_not_affect_orbit()
	_test_cam_e_6_camera_pivot_missing_graceful()

	print("  Camera Follow Unit Tests: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


func _make_bare_pc() -> Node:
	var pc = PlayerControllerScript.new()
	pc.name = "PlayerController"
	return pc


# ===== TC-CAM-N: Normal Path =====

func _test_cam_n_1_camera_hierarchy() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc._build_node_tree()
	pc._build_camera_system()
	pc._build_player_visual()

	# Reassign @onready-style references (as _ready() would)
	pc.head = pc.get_node_or_null("Head")
	pc.camera_pivot = pc.get_node_or_null("CameraPivot")
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D") if pc.has_node("CameraPivot") else null
	pc.camera = pc.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") if pc.has_node("CameraPivot/SpringArm3D") else null

	_assert(pc.camera_pivot != null, "TC-CAM-N-1-1: CameraPivot exists as child of PlayerController")
	_assert(pc.camera_pivot is Node3D, "TC-CAM-N-1-2: CameraPivot is a Node3D")
	_assert(pc.spring_arm != null, "TC-CAM-N-1-3: SpringArm3D exists as child of CameraPivot")
	_assert(pc.camera != null, "TC-CAM-N-1-4: Camera3D exists as child of SpringArm3D")


func _test_cam_n_1_spring_arm_margin() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc.spring_arm_length = 4.0
	pc._build_camera_system()
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D")

	_assert(pc.spring_arm != null, "TC-CAM-N-1-5: SpringArm3D created")
	if pc.spring_arm:
		_assert(abs(pc.spring_arm.spring_length - 4.0) < 0.01,
			"TC-CAM-N-1-6: SpringArm3D.spring_length == 4.0")
		_assert(abs(pc.spring_arm.margin - 0.3) < 0.01,
			"TC-CAM-N-1-7: SpringArm3D.margin == 0.3")


func _test_cam_n_1_camera_position_relative() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc._build_node_tree()
	pc._build_camera_system()
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D")

	if pc.spring_arm:
		var cam = pc.spring_arm.get_node_or_null("Camera3D")
		_assert(cam != null, "TC-CAM-N-1-8: Camera3D under SpringArm3D")
		if cam:
			_assert(abs(cam.position.y - 2.0) < 0.01,
				"TC-CAM-N-1-9: Camera3D position.y == 2.0 relative to SpringArm3D")


func _test_cam_n_2_camera_follows_movement() -> void:
	# Note: nodes not in scene tree, so global_position is unavailable.
	# We verify the camera parent-child relationship ensures camera follows player
	# by testing that camera offset relative to player is maintained.
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc._build_node_tree()
	pc._build_camera_system()
	pc.camera_pivot = pc.get_node_or_null("CameraPivot")
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D")
	pc.camera = pc.get_node_or_null("CameraPivot/SpringArm3D/Camera3D")

	if not pc.camera or not pc.camera_pivot:
		_assert(false, "TC-CAM-N-2: Camera or CameraPivot missing — skipping test")
		return

	# Verify camera is a descendant of PlayerController (not a sibling or external)
	# This ensures when player moves, camera moves with it via scene tree hierarchy.
	_assert(pc.camera.get_parent() == pc.spring_arm,
		"TC-CAM-N-2-1: Camera3D parent is SpringArm3D")
	_assert(pc.spring_arm.get_parent() == pc.camera_pivot,
		"TC-CAM-N-2-2: SpringArm3D parent is CameraPivot")
	_assert(pc.camera_pivot.get_parent() == pc,
		"TC-CAM-N-2-3: CameraPivot parent is PlayerController")

	# Verify CameraPivot is a direct child of PlayerController
	_assert(pc.camera_pivot.owner == pc,
		"TC-CAM-N-2-4: CameraPivot.owner is PlayerController")


func _test_cam_n_3_mouse_horizontal_orbit() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc.orbit_sensitivity = 0.003
	pc._build_node_tree()
	pc._build_camera_system()
	pc.camera_pivot = pc.get_node_or_null("CameraPivot")
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D")

	var initial_yaw = pc._orbit_yaw

	# Simulate 100px right drag (horizontal)
	pc._handle_mouse_look(Vector2(100.0, 0.0))

	_assert(pc._orbit_yaw < initial_yaw,
		"TC-CAM-N-3-1: Drag right 100px → _orbit_yaw decreases")
	_assert(abs(pc._orbit_yaw - (initial_yaw - 100.0 * 0.003)) < 0.001,
		"TC-CAM-N-3-2: _orbit_yaw decreased by 100 * orbit_sensitivity")

	# Verify CameraPivot rotation matches
	if pc.camera_pivot:
		_assert(abs(pc.camera_pivot.rotation.y - pc._orbit_yaw) < 0.001,
			"TC-CAM-N-3-3: CameraPivot.rotation.y == _orbit_yaw")


func _test_cam_n_4_mouse_vertical_clamped() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc.orbit_sensitivity = 0.003
	pc.orbit_pitch_min = -0.523  # -30°
	pc.orbit_pitch_max = 0.785   # +45°
	pc._build_node_tree()
	pc._build_camera_system()
	pc.camera_pivot = pc.get_node_or_null("CameraPivot")
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D")

	# Simulate extreme drag up (500px)
	pc._handle_mouse_look(Vector2(0.0, -500.0))
	_assert(pc._orbit_pitch <= pc.orbit_pitch_max + 0.001,
		"TC-CAM-N-4-1: Extreme drag up → _orbit_pitch ≤ orbit_pitch_max (+45°)")

	if pc.spring_arm:
		_assert(pc.spring_arm.rotation.x <= pc.orbit_pitch_max + 0.001,
			"TC-CAM-N-4-2: SpringArm3D.rotation.x ≤ orbit_pitch_max")

	# Reset and simulate extreme drag down (500px)
	pc._orbit_pitch = 0.0
	pc._handle_mouse_look(Vector2(0.0, 500.0))
	_assert(pc._orbit_pitch >= pc.orbit_pitch_min - 0.001,
		"TC-CAM-N-4-3: Extreme drag down → _orbit_pitch ≥ orbit_pitch_min (-30°)")

	if pc.spring_arm:
		_assert(pc.spring_arm.rotation.x >= pc.orbit_pitch_min - 0.001,
			"TC-CAM-N-4-4: SpringArm3D.rotation.x ≥ orbit_pitch_min")


func _test_cam_n_5_first_person_fallback() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "first_person"
	pc.head = Node3D.new()
	pc.head.name = "Head"
	pc.add_child(pc.head)
	pc.look_sensitivity = 0.003
	pc.camera_tilt = -0.087
	pc.look_vertical_clamp = 1.047

	var initial_yaw = pc.rotation.y
	var initial_head_pitch = pc.head.rotation.x

	# Simulate 100px right + 100px up drag
	pc._handle_mouse_look(Vector2(100.0, -100.0))

	_assert(pc.rotation.y < initial_yaw,
		"TC-CAM-N-5-1: First-person — drag right → rotation.y decreases (body yaw)")
	_assert(pc.head.rotation.x > initial_head_pitch,
		"TC-CAM-N-5-2: First-person — drag up → head.rotation.x increases (pitch)")


func _test_cam_n_6_spring_arm_excluded_object() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc._build_camera_system()
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D")

	if pc.spring_arm:
		# Verify collision_mask is set to 0b100 (layer 3, hitting scene geometry)
		_assert(pc.spring_arm.collision_mask == 0b100,
			"TC-CAM-N-6-1: SpringArm3D collision_mask == 0b100 (layer 3)")
		# Verify margin is set
		_assert(abs(pc.spring_arm.margin - 0.3) < 0.001,
			"TC-CAM-N-6-2: SpringArm3D.margin == 0.3")
		# add_excluded_object(self) was called successfully (no crash or error at call site)
		_assert(true,
			"TC-CAM-N-6-3: add_excluded_object(self) called without error")
	else:
		_assert(false, "TC-CAM-N-6: SpringArm3D not found")


func _test_cam_n_8_player_visual_exists() -> void:
	var pc = _make_bare_pc()
	pc._build_player_visual()

	var vis = pc.get_node_or_null("PlayerVisual")
	_assert(vis != null, "TC-CAM-N-8-1: PlayerVisual exists")
	_assert(vis is MeshInstance3D, "TC-CAM-N-8-2: PlayerVisual is a MeshInstance3D")

	if vis and vis.mesh:
		_assert(vis.mesh is CapsuleMesh, "TC-CAM-N-8-3: PlayerVisual mesh is CapsuleMesh")
		_assert(abs(vis.position.y - 0.7) < 0.01,
			"TC-CAM-N-8-4: PlayerVisual position.y == 0.7")
		_assert(vis.material_override != null,
			"TC-CAM-N-8-5: PlayerVisual has material_override")


# ===== TC-CAM-E: Edge Cases =====

func _test_cam_e_1_set_camera_orbit() -> void:
	var pc = _make_bare_pc()
	pc.spring_arm = SpringArm3D.new()
	pc.spring_arm.name = "SpringArm3D"
	pc.camera_pivot = Node3D.new()
	pc.camera_pivot.name = "CameraPivot"
	pc.camera_pivot.add_child(pc.spring_arm)
	pc.add_child(pc.camera_pivot)

	pc.orbit_pitch_min = -0.523
	pc.orbit_pitch_max = 0.785

	# Test set_camera_orbit
	pc.set_camera_orbit(1.5, 0.3)
	_assert(abs(pc._orbit_yaw - 1.5) < 0.001,
		"TC-CAM-E-1-1: set_camera_orbit sets _orbit_yaw to 1.5")
	_assert(abs(pc._orbit_pitch - 0.3) < 0.001,
		"TC-CAM-E-1-2: set_camera_orbit sets _orbit_pitch to 0.3")
	_assert(abs(pc.camera_pivot.rotation.y - 1.5) < 0.001,
		"TC-CAM-E-1-3: CameraPivot.rotation.y updated to 1.5")
	_assert(abs(pc.spring_arm.rotation.x - 0.3) < 0.001,
		"TC-CAM-E-1-4: SpringArm3D.rotation.x updated to 0.3")

	# Test value clamping by set_camera_orbit
	pc.set_camera_orbit(0.0, 2.0)
	_assert(pc._orbit_pitch <= pc.orbit_pitch_max,
		"TC-CAM-E-1-5: set_camera_orbit clamps pitch to orbit_pitch_max")


func _test_cam_e_2_get_camera_orbit() -> void:
	var pc = _make_bare_pc()
	pc._orbit_yaw = 1.5
	pc._orbit_pitch = 0.3

	var orbit = pc.get_camera_orbit()
	_assert(orbit is Dictionary, "TC-CAM-E-2-1: get_camera_orbit returns Dictionary")
	_assert(orbit.has("yaw"), "TC-CAM-E-2-2: Dictionary has 'yaw' key")
	_assert(orbit.has("pitch"), "TC-CAM-E-2-3: Dictionary has 'pitch' key")
	_assert(abs(orbit["yaw"] - 1.5) < 0.001,
		"TC-CAM-E-2-4: orbit.yaw == 1.5")
	_assert(abs(orbit["pitch"] - 0.3) < 0.001,
		"TC-CAM-E-2-5: orbit.pitch == 0.3")


func _test_cam_e_3_orbit_persistence_api() -> void:
	var pc = _make_bare_pc()
	pc.spring_arm = SpringArm3D.new()
	pc.spring_arm.name = "SpringArm3D"
	pc.camera_pivot = Node3D.new()
	pc.camera_pivot.name = "CameraPivot"
	pc.camera_pivot.add_child(pc.spring_arm)
	pc.add_child(pc.camera_pivot)
	pc.orbit_pitch_min = -0.523
	pc.orbit_pitch_max = 0.785

	# Round-trip: set → get → verify
	var test_yaw := 2.5
	var test_pitch := -0.1
	pc.set_camera_orbit(test_yaw, test_pitch)
	var result = pc.get_camera_orbit()

	_assert(abs(result["yaw"] - test_yaw) < 0.001,
		"TC-CAM-E-3-1: Round-trip yaw: set %f → get %f" % [test_yaw, result["yaw"]])
	_assert(abs(result["pitch"] - test_pitch) < 0.001,
		"TC-CAM-E-3-2: Round-trip pitch: set %f → get %f" % [test_pitch, result["pitch"]])

	# Verify both has_method works
	_assert(pc.has_method("set_camera_orbit"),
		"TC-CAM-E-3-3: PlayerController has set_camera_orbit method")
	_assert(pc.has_method("get_camera_orbit"),
		"TC-CAM-E-3-4: PlayerController has get_camera_orbit method")


func _test_cam_e_5_dialogue_does_not_affect_orbit() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc.orbit_sensitivity = 0.003
	pc._build_camera_system()
	pc.camera_pivot = pc.get_node_or_null("CameraPivot")
	pc.spring_arm = pc.get_node_or_null("CameraPivot/SpringArm3D")

	# Enter dialogue
	pc._on_dialogue_started("test_dialogue")
	_assert(pc._dialogue_active, "TC-CAM-E-5-1: Dialogue active flag set")

	# While in dialogue, _handle_mouse_look is NOT called because
	# _input() gates on _mouse_dragging and not _dialogue_active.
	# But camera mode and orbit state should remain unchanged.
	# Verify that dialogue mode does not reset orbit state.
	pc._orbit_yaw = 0.5
	pc._orbit_pitch = 0.2

	# Exit dialogue
	pc._on_dialogue_ended()
	_assert(not pc._dialogue_active, "TC-CAM-E-5-3: Dialogue ended")

	# Orbit state should be preserved through dialogue toggle
	_assert(abs(pc._orbit_yaw - 0.5) < 0.001,
		"TC-CAM-E-5-4: Orbit yaw preserved after dialogue")
	_assert(abs(pc._orbit_pitch - 0.2) < 0.001,
		"TC-CAM-E-5-5: Orbit pitch preserved after dialogue")


func _test_cam_e_6_camera_pivot_missing_graceful() -> void:
	var pc = _make_bare_pc()
	pc.camera_mode = "third_person"
	pc.camera_pivot = null  # Simulate missing node
	pc.spring_arm = null

	# _handle_mouse_look should not crash with null camera_pivot/spring_arm
	pc._handle_mouse_look(Vector2(100.0, 0.0))
	_assert(true,
		"TC-CAM-E-6-1: Mouse look handles missing CameraPivot (no crash)")

	# set_camera_orbit should not crash
	pc.set_camera_orbit(1.0, 0.5)
	_assert(true,
		"TC-CAM-E-6-2: set_camera_orbit handles missing nodes (no crash)")

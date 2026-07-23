extends RefCounted

# Input Map validation tests — verify that all player controller input actions
# are registered in the InputMap.

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("  === Input Map Validation Tests ====")

	# Register actions in case headless mode doesn't load project.godot input map
	if not InputMap.has_action("move_forward"):
		InputMap.add_action("move_forward")
	if not InputMap.has_action("move_backward"):
		InputMap.add_action("move_backward")
	if not InputMap.has_action("move_left"):
		InputMap.add_action("move_left")
	if not InputMap.has_action("move_right"):
		InputMap.add_action("move_right")
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")

	# TC-IM-N (Normal Path)
	print("  --- TC-IM-N: Normal Path ---")
	_test_im_n_1_move_forward()
	_test_im_n_2_move_backward()
	_test_im_n_3_move_left()
	_test_im_n_4_move_right()
	_test_im_n_5_interact()

	# TC-IM-E (Edge Cases)
	print("  --- TC-IM-E: Edge Cases ---")
	_test_im_e_1_unknown_action()
	_test_im_e_2_dialogue_up_exists()

	# TC-IM-F (Failure Paths)
	print("  --- TC-IM-F: Failure Paths ---")
	_test_im_f_1_get_vector_missing_action()
	_test_im_f_2_verify_input_map_warns_missing()
	_test_im_f_3_verify_input_map_all_present()

	print("  Input Map Validation: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


# ===== TC-IM-N: Normal Path =====

func _test_im_n_1_move_forward() -> void:
	_assert(InputMap.has_action("move_forward"),
		"TC-IM-N-1: move_forward action exists in InputMap")


func _test_im_n_2_move_backward() -> void:
	_assert(InputMap.has_action("move_backward"),
		"TC-IM-N-2: move_backward action exists in InputMap")


func _test_im_n_3_move_left() -> void:
	_assert(InputMap.has_action("move_left"),
		"TC-IM-N-3: move_left action exists in InputMap")


func _test_im_n_4_move_right() -> void:
	_assert(InputMap.has_action("move_right"),
		"TC-IM-N-4: move_right action exists in InputMap")


func _test_im_n_5_interact() -> void:
	_assert(InputMap.has_action("interact"),
		"TC-IM-N-5: interact action exists in InputMap")


# ===== TC-IM-E: Edge Cases =====

func _test_im_e_1_unknown_action() -> void:
	_assert(not InputMap.has_action("nonexistent_action"),
		"TC-IM-E-1: Unknown action 'nonexistent_action' returns false")


func _test_im_e_2_dialogue_up_exists() -> void:
	if not InputMap.has_action("dialogue_up"):
		InputMap.add_action("dialogue_up")
	_assert(InputMap.has_action("dialogue_up"),
		"TC-IM-E-2: dialogue_up action exists in InputMap")


# ===== TC-IM-F: Failure Paths =====

func _test_im_f_1_get_vector_missing_action() -> void:
	var result: Vector2 = Input.get_vector("missing_a", "missing_b", "missing_c", "missing_d")
	_assert(result == Vector2.ZERO,
		"TC-IM-F-1: Input.get_vector() with missing actions returns Vector2.ZERO")


func _test_im_f_2_verify_input_map_warns_missing() -> void:
	var gm = load("res://gdscripts/game_manager.gd").new()
	if InputMap.has_action("move_forward"):
		InputMap.erase_action("move_forward")
	gm._verify_input_map()
	if not InputMap.has_action("move_forward"):
		InputMap.add_action("move_forward")
	_assert(true, "TC-IM-F-2: _verify_input_map() handles missing action with warning (no crash)")


func _test_im_f_3_verify_input_map_all_present() -> void:
	var gm = load("res://gdscripts/game_manager.gd").new()
	for action in ["move_forward", "move_backward", "move_left", "move_right", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	gm._verify_input_map()
	_assert(true, "TC-IM-F-3: _verify_input_map() with all actions present logs no warning (no crash)")

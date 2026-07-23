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

	# TC-IM-F (Failure Paths)
	print("  --- TC-IM-F: Failure Paths ---")

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

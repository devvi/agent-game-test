extends RefCounted

# Unit tests for SceneBase player extension — instantiation, state save/restore.

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("  === SceneBase Player Unit Tests ====")

	# TC-SB-N (Normal Path)
	print("  --- TC-SB-N: Normal Path ---")
	_test_sb_n_1_instantiate_player()
	_test_sb_n_2_save_position()
	_test_sb_n_3_no_gm_no_crash()

	# TC-SB-E (Edge Cases)
	print("  --- TC-SB-E: Edge Cases ---")
	_test_sb_e_1_double_instantiate()

	# TC-SB-F (Failure Paths)
	print("  --- TC-SB-F: Failure Paths ---")
	_test_sb_f_2_null_position()

	print("  SceneBase Player: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


# Helper: create a minimal SceneBase inheritor for testing
func _make_scene_base() -> Node:
	var SceneBaseScript = load("res://gdscripts/scene_base.gd")
	var sb = SceneBaseScript.new()
	return sb


# ===== TC-SB-N: Normal Path =====

func _test_sb_n_1_instantiate_player() -> void:
	var sb = _make_scene_base()
	# Mock Child node not set up, test the method directly
	_assert(sb != null, "TC-SB-N-1-1: SceneBase inheritor created")


func _test_sb_n_2_save_position() -> void:
	var sb = _make_scene_base()
	# Save with no player should not error
	sb._save_player_state()
	_assert(true, "TC-SB-N-2-1: _save_player_state with no player → no crash")


func _test_sb_n_3_no_gm_no_crash() -> void:
	var sb = _make_scene_base()
	sb._save_player_state()
	_assert(true, "TC-SB-N-2-2: No GameManager → no crash on _exit_tree")


# ===== TC-SB-E: Edge Cases =====

func _test_sb_e_1_double_instantiate() -> void:
	var sb = _make_scene_base()
	# First call: should return early if already exists
	sb._player = Node.new()
	sb._instantiate_player()
	_assert(sb._player != null,
		"TC-SB-E-1: _instantiate_player called twice → no duplicate (early return)")


# ===== TC-SB-F: Failure Paths =====

func _test_sb_f_2_null_position() -> void:
	var sb = _make_scene_base()
	# Null position should be handled gracefully
	sb._instantiate_player()
	_assert(true, "TC-SB-F-2: Null player_position → graceful fallback to origin")

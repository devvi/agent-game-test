extends RefCounted

# Unit tests for GameManager player state variables (Issue #142).
# Extended with autoload verification tests (Issue #153).

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("  === GameManager Player State Tests ====")

	# TC-GM-N (Normal Path)
	print("  --- TC-GM-N: Normal Path ---")
	_test_gm_n_1_vars_exist()
	_test_gm_n_2_set_position()
	_test_gm_n_2_set_rotation()

	# TC-GM-AL (Autoload Verification)
	print("  --- TC-GM-AL: Autoload Verification ---")
	_test_gm_al_1_verify_autoloads_tolerates_missing()
	_test_gm_al_2_verify_autoloads_no_crash()

	print("  GameManager Player State: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


func _make_gm() -> Node:
	var GameManagerScript = load("res://gdscripts/game_manager.gd")
	var gm = GameManagerScript.new()
	return gm


# ===== TC-GM-N: Normal Path =====

func _test_gm_n_1_vars_exist() -> void:
	var gm = _make_gm()
	_assert(gm.get("player_position") != null, "TC-GM-N-1-1: player_position accessible")
	_assert(gm.get("player_rotation") != null, "TC-GM-N-1-2: player_rotation accessible")
	_assert(gm.get("player_head_rotation") != null, "TC-GM-N-1-3: player_head_rotation accessible")


func _test_gm_n_2_set_position() -> void:
	var gm = _make_gm()
	gm.player_position = Vector3(1.0, 2.0, 3.0)
	_assert(gm.player_position == Vector3(1.0, 2.0, 3.0),
		"TC-GM-N-2-1: Set player_position to (1,2,3)")


func _test_gm_n_2_set_rotation() -> void:
	var gm = _make_gm()
	gm.player_rotation = Vector3(0.0, 1.57, 0.0)
	_assert(abs(gm.player_rotation.y - 1.57) < 0.01,
		"TC-GM-N-2-2: Set player_rotation.y ≈ 1.57")


# ===== TC-GM-AL: Autoload Verification =====

func _test_gm_al_1_verify_autoloads_tolerates_missing() -> void:
	var gm = _make_gm()
	# In headless mode, no autoloads are present. Verify no crash.
	gm._verify_autoloads()
	_assert(true, "TC-GM-AL-1: _verify_autoloads() tolerates missing autoloads (no crash)")


func _test_gm_al_2_verify_autoloads_no_crash() -> void:
	var gm = _make_gm()
	# Verify _verify_input_map() doesn't crash either
	gm._verify_input_map()
	_assert(true, "TC-GM-AL-2: _verify_input_map() does not crash in headless mode")

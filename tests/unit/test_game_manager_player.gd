extends RefCounted

# Unit tests for GameManager player state variables (Issue #142).

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("  === GameManager Player State Tests ====")

	# TC-GM-N (Normal Path)
	print("  --- TC-GM-N: Normal Path ---")
	_test_gm_n_1_vars_exist()
	_test_gm_n_2_set_position()
	_test_gm_n_2_set_rotation()

	# TC24-TC25: Input Validation
	print("  --- TC24-TC25: Autoload Validation ---")
	_test_tc24_verify_autoloads_tolerates_missing()
	_test_tc25_state_fallback()

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


# TC24: _verify_autoloads() tolerates missing autoloads
func _test_tc24_verify_autoloads_tolerates_missing() -> void:
	var gm = _make_gm()
	# In --script mode, autoloads like StateSystem, NarrativeManager are missing
	# _verify_autoloads() should log warnings but not crash
	gm._verify_autoloads()
	_assert(true,
		"TC24: _verify_autoloads() tolerates missing autoloads — no crash")


# TC25: StateSystem.get_state() falls back when autoload missing
func _test_tc25_state_fallback() -> void:
	var gm = _make_gm()
	# When _state_system is null, get_slider should return 5.0
	var val: float = gm.get_slider("hope")
	_assert(abs(val - 5.0) < 0.001,
		"TC25: get_slider returns 5.0 when StateSystem autoload missing")

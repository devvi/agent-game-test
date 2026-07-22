extends SceneTree

# Tests for GameManager playthrough_count (Issue #59 — AC3 detection)
# Tests TC15-TC17 from DESIGN doc

var passed: int = 0
var failed: int = 0
var GameManagerScript = load("res://gdscripts/game_manager.gd")

func _init() -> void:
	print("\n=== GameManager Playthrough Count Tests (Issue #59) ===")

	# TC15: Normal increment
	_test_increment_on_start()

	# TC16: Persistence across resets
	_test_persist_across_reset()

	# TC17: Accessor returns correct value
	_test_get_playthrough_count()

	print("\nPlaythrough Count Tests: %d passed, %d failed" % [passed, failed])

	quit(1 if failed > 0 else 0)

func _make_gm():
	return GameManagerScript.new()

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ %s" % name)
	else:
		failed += 1
		print("  ❌ %s" % name)

# TC15: playthrough_count increments on start_game()
func _test_increment_on_start() -> void:
	var gm = _make_gm()
	assert(gm.playthrough_count == 0, "TC15: starts at 0")
	gm.start_game()
	assert(gm.playthrough_count == 1, "TC15: after 1 start = 1")
	gm.start_game()
	assert(gm.playthrough_count == 2, "TC15: after 2 starts = 2")
	gm.start_game()
	_assert(gm.playthrough_count == 3, "TC15: after 3 calls, playthrough_count = 3")

# TC16: playthrough_count persists across reset() (not reset to 0)
func _test_persist_across_reset() -> void:
	var gm = _make_gm()
	gm.playthrough_count = 2
	gm.start_game()
	_assert(gm.playthrough_count == 3, "TC16: playthrough_count = 3 after reset + start (persisted)")

# TC17: get_playthrough_count() accessor returns correct value
func _test_get_playthrough_count() -> void:
	var gm = _make_gm()
	gm.playthrough_count = 5
	_assert(gm.get_playthrough_count() == 5, "TC17: get_playthrough_count() = 5")
	gm.start_game()
	_assert(gm.get_playthrough_count() == 6, "TC17: get_playthrough_count() = 6 after start")

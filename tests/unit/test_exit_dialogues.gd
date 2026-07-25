extends RefCounted

# Test: Exit Dialogue .dialogue File Validation — Issue #155
# Validates all exit .dialogue files exist and have expected structure.
# Runs via godot --headless --script tests/run_tests.gd

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Exit Dialogue Tests (Issue #155) ===")

	_test_file_exists("res://dialogues/office_door.dialogue")
	_test_file_exists("res://dialogues/lobby_exit.dialogue")
	_test_file_exists("res://dialogues/bridge_exit.dialogue")
	_test_file_exists("res://dialogues/underpass_exit.dialogue")
	_test_file_exists("res://dialogues/subway_ending.dialogue")

	_test_has_header("res://dialogues/office_door.dialogue", "using StateSystem")
	_test_has_header("res://dialogues/lobby_exit.dialogue", "using StateSystem")
	_test_has_header("res://dialogues/bridge_exit.dialogue", "using StateSystem")
	_test_has_header("res://dialogues/underpass_exit.dialogue", "using StateSystem")
	_test_has_header("res://dialogues/subway_ending.dialogue", "using StateSystem")

	_test_has_title("res://dialogues/office_door.dialogue", "~ door_leave")
	_test_has_title("res://dialogues/lobby_exit.dialogue", "~ lobby_exit_prompt")
	_test_has_title("res://dialogues/bridge_exit.dialogue", "~ bridge_exit_prompt")
	_test_has_title("res://dialogues/underpass_exit.dialogue", "~ underpass_exit_prompt")
	_test_has_title("res://dialogues/subway_ending.dialogue", "~ kw_final")
	_test_has_title("res://dialogues/subway_ending.dialogue", "~ tb_final")
	_test_has_title("res://dialogues/subway_ending.dialogue", "~ st_final")

	_test_scene_paths_exist()

	print("\n  Exit Dialogues: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  ❌ FAIL: %s" % name)


func _load_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	return text


func _test_file_exists(path: String) -> void:
	_assert(FileAccess.file_exists(path), "EX-1: File exists: %s" % path)


func _test_has_header(path: String, header: String) -> void:
	var text := _load_text(path)
	if text.is_empty():
		_assert(false, "EX-2: Could not read: %s" % path)
		return
	_assert(text.begins_with(header), "EX-2: %s starts with '%s'" % [path.get_file(), header])


func _test_has_title(path: String, title: String) -> void:
	var text := _load_text(path)
	if text.is_empty():
		_assert(false, "EX-3: Could not read: %s" % path)
		return
	var lines := text.split("\n")
	var found := false
	for line in lines:
		if line.strip_edges() == title:
			found = true
			break
	_assert(found, "EX-3: %s has title '%s'" % [path.get_file(), title])


func _test_scene_paths_exist() -> void:
	_assert(FileAccess.file_exists("res://scenes/end_credits.tscn"),
		"EX-4: end_credits.tscn exists")
	_assert(FileAccess.file_exists("res://scenes/lobby/lobby.tscn"),
		"EX-5: lobby.tscn exists")
	_assert(FileAccess.file_exists("res://scenes/store/convenience_store.tscn"),
		"EX-6: convenience_store.tscn exists")
	_assert(FileAccess.file_exists("res://scenes/underpass/underpass.tscn"),
		"EX-7: underpass.tscn exists")
	_assert(FileAccess.file_exists("res://scenes/subway_station/subway_station.tscn"),
		"EX-8: subway_station.tscn exists")

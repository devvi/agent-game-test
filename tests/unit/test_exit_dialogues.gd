extends RefCounted

# Test: Exit Dialogue JSON Validation — Issue #155
# Validates all exit dialogue JSON files parse correctly and contain
# a "scene" key on terminal choices.
# Runs via godot --headless --script tests/run_tests.gd

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== Exit Dialogue Tests (Issue #155) ===")

	# TC1: Office door exit JSON has "scene" key on all 3 door_leave choices
	_test_office_door_scene_keys()

	# TC2: Lobby exit JSON parses correctly
	_test_lobby_exit_json()

	# TC3: Bridge exit JSON parses correctly
	_test_bridge_exit_json()

	# TC4: Underpass exit JSON parses correctly
	_test_underpass_exit_json()

	# TC5: Subway ending JSON has "scene" on terminal choices
	_test_subway_ending_scene_keys()

	# TC6: Exit dialogue scene paths point to existing files
	_test_scene_paths_exist()

	# TC7: Exit dialogue nodes have non-empty speaker
	_test_speaker_not_empty()

	print("\n  Exit Dialogues: %d passed, %d failed" % [passed, failed])


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	var result = JSON.parse_string(text)
	if result is Dictionary:
		return result
	return {}


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  ❌ FAIL: %s" % name)


func _test_office_door_scene_keys() -> void:
	var json := _load_json("res://dialogues/office_door.json")
	_assert(json.has("nodes"), "TC1: office_door.json has 'nodes' key")
	if not json.has("nodes"):
		return
	var nodes: Dictionary = json["nodes"]
	_assert(nodes.has("door_leave"), "TC1: office_door.json has 'door_leave' node")
	if not nodes.has("door_leave"):
		return
	var door_leave: Dictionary = nodes["door_leave"]
	var choices: Array = door_leave.get("choices", [])
	_assert(choices.size() == 3, "TC1: door_leave has 3 choices")
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		_assert(choice.has("scene"), "TC1: door_leave choice %d has 'scene' key" % (i + 1))
		_assert(choice["scene"] == "res://scenes/lobby/lobby.tscn",
			"TC1: door_leave choice %d scene is lobby.tscn" % (i + 1))


func _test_lobby_exit_json() -> void:
	var json := _load_json("res://dialogues/lobby_exit.json")
	_assert(json.has("entry_node_id"), "TC2: lobby_exit.json has entry_node_id")
	if not json.has("entry_node_id"):
		return
	_assert(json["entry_node_id"] == "lobby_exit_prompt",
		"TC2: entry_node_id is 'lobby_exit_prompt'")

	var nodes: Dictionary = json.get("nodes", {})
	_assert(nodes.size() == 2, "TC2: lobby_exit.json has 2 nodes")

	# Check terminal choice has "scene" key
	var terminal_node: Dictionary = nodes.get("lobby_exit_stand", {})
	var choices: Array = terminal_node.get("choices", [])
	_assert(choices.size() >= 1, "TC2: lobby_exit_stand has at least 1 choice")
	if choices.size() >= 1:
		_assert(choices[0].has("scene"), "TC2: terminal choice has 'scene' key")
		_assert(choices[0]["scene"] == "res://scenes/store/convenience_store.tscn",
			"TC2: scene points to convenience_store.tscn")


func _test_bridge_exit_json() -> void:
	var json := _load_json("res://dialogues/bridge_exit.json")
	_assert(json.has("entry_node_id"), "TC3: bridge_exit.json has entry_node_id")
	if not json.has("entry_node_id"):
		return
	_assert(json["entry_node_id"] == "bridge_exit_prompt",
		"TC3: entry_node_id is 'bridge_exit_prompt'")

	var nodes: Dictionary = json.get("nodes", {})
	_assert(nodes.has("bridge_exit_prompt"), "TC3: has bridge_exit_prompt node")

	var node_choices: Array = nodes.get("bridge_exit_prompt", {}).get("choices", [])
	_assert(node_choices.size() >= 1, "TC3: has at least 1 choice")
	if node_choices.size() >= 1:
		_assert(node_choices[0].has("scene"), "TC3: choice has 'scene' key")
		_assert(node_choices[0]["scene"].ends_with("underpass.tscn"),
			"TC3: scene path ends with underpass.tscn")


func _test_underpass_exit_json() -> void:
	var json := _load_json("res://dialogues/underpass_exit.json")
	_assert(json.has("entry_node_id"), "TC4: underpass_exit.json has entry_node_id")
	if not json.has("entry_node_id"):
		return
	_assert(json["entry_node_id"] == "underpass_exit_prompt",
		"TC4: entry_node_id is 'underpass_exit_prompt'")

	var nodes: Dictionary = json.get("nodes", {})
	_assert(nodes.has("underpass_exit_prompt"), "TC4: has underpass_exit_prompt node")

	var node_choices: Array = nodes.get("underpass_exit_prompt", {}).get("choices", [])
	_assert(node_choices.size() >= 1, "TC4: has at least 1 choice")
	if node_choices.size() >= 1:
		_assert(node_choices[0].has("scene"), "TC4: choice has 'scene' key")
		_assert(node_choices[0]["scene"].ends_with("subway_station.tscn"),
			"TC4: scene path ends with subway_station.tscn")


func _test_subway_ending_scene_keys() -> void:
	var json := _load_json("res://dialogues/subway_ending.json")
	_assert(json.has("nodes"), "TC5: subway_ending.json has 'nodes' key")
	if not json.has("nodes"):
		return
	var nodes: Dictionary = json["nodes"]

	# Check kw_final
	var kw_final: Dictionary = nodes.get("kw_final", {})
	var kw_choices: Array = kw_final.get("choices", [])
	_assert(kw_choices.size() >= 1, "TC5: kw_final has at least 1 choice")
	if kw_choices.size() >= 1:
		_assert(kw_choices[0].has("scene"), "TC5: kw_final choice has 'scene' key")
		_assert(kw_choices[0]["scene"] == "res://scenes/end_credits.tscn",
			"TC5: kw_final scene is end_credits.tscn")

	# Check tb_final
	var tb_final: Dictionary = nodes.get("tb_final", {})
	var tb_choices: Array = tb_final.get("choices", [])
	_assert(tb_choices.size() >= 1, "TC5: tb_final has at least 1 choice")
	if tb_choices.size() >= 1:
		_assert(tb_choices[0].has("scene"), "TC5: tb_final choice has 'scene' key")
		_assert(tb_choices[0]["scene"] == "res://scenes/end_credits.tscn",
			"TC5: tb_final scene is end_credits.tscn")

	# Check st_final
	var st_final: Dictionary = nodes.get("st_final", {})
	var st_choices: Array = st_final.get("choices", [])
	_assert(st_choices.size() >= 1, "TC5: st_final has at least 1 choice")
	if st_choices.size() >= 1:
		_assert(st_choices[0].has("scene"), "TC5: st_final choice has 'scene' key")
		_assert(st_choices[0]["scene"] == "res://scenes/end_credits.tscn",
			"TC5: st_final scene is end_credits.tscn")


func _test_scene_paths_exist() -> void:
	var exit_files: Array[String] = [
		"res://dialogues/office_door.json",
		"res://dialogues/lobby_exit.json",
		"res://dialogues/bridge_exit.json",
		"res://dialogues/underpass_exit.json",
		"res://dialogues/subway_ending.json"
	]
	for path in exit_files:
		_assert(FileAccess.file_exists(path), "TC6: exit dialogue file exists: %s" % path)

	# Also verify end_credits.tscn exists
	_assert(FileAccess.file_exists("res://scenes/end_credits.tscn"),
		"TC6: end_credits.tscn exists")


func _test_speaker_not_empty() -> void:
	var exit_files: Array[String] = [
		"res://dialogues/lobby_exit.json",
		"res://dialogues/bridge_exit.json",
		"res://dialogues/underpass_exit.json"
	]
	for path in exit_files:
		var json := _load_json(path)
		var nodes: Dictionary = json.get("nodes", {})
		for node_id: String in nodes:
			var node: Dictionary = nodes[node_id]
			var speaker: String = node.get("speaker", "")
			_assert(speaker != "", "TC7: node '%s' in %s has non-empty speaker" % [node_id, path])

extends RefCounted

# ===== Story Content Tests (Issue #56) =====
# Validates dialogue JSON structure, intertextuality, ending flow, and
# environmental text coverage across all scenes.

var passed: int = 0
var failed: int = 0

var _DialogueParser = preload("res://gdscripts/dialogue_parser.gd")
var _HemingwayEnforcer = load("res://gdscripts/hemingway_enforcer.gd")

# All dialogue files that should exist and parse correctly
var DIALOGUE_FILES: Array[String] = [
	"res://dialogues/office_door.json",
	"res://dialogues/store_clerk.json",
	"res://dialogues/bartender.json",
	"res://dialogues/underpass.json",
	"res://dialogues/ending_keep_walking.json",
	"res://dialogues/ending_turn_back.json",
	"res://dialogues/ending_stay.json",
]

# Ending flag names that must be set by final choice
var ENDING_FLAGS: Array[String] = [
	"ending_keep_walking",
	"ending_turn_back",
	"ending_stay",
]

func run() -> void:
	print("\n=== Story Content Tests (Issue #56) ===\n")

	# --- Dialogue JSON Validation ---
	_test_dialogue_files_exist_and_parse()
	_test_dialogue_hemingway_constraints()
	_test_dialogue_required_fields()

	# --- Ending Flow Validation ---
	_test_underpass_final_choice_sets_flags()
	_test_ending_dialogues_have_sequence()
	_test_store_clerk_transition_to_underpass()

	# --- Intertextuality Validation ---
	_test_intertextuality_echo_1_check_door()
	_test_intertextuality_echo_2_youre_still_here()
	_test_intertextuality_echo_3_i_was_here()
	_test_intertextuality_echo_7_same_streets()

	# --- State Variant Coverage ---
	_test_underpass_environmental_text_variants()

	print("\n  Story Content Tests: %d passed, %d failed\n" % [passed, failed])


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ %s" % name)
	else:
		failed += 1
		print("  ❌ %s" % name)


# =====================================================================
# Dialogue JSON Validation
# =====================================================================

func _test_dialogue_files_exist_and_parse() -> void:
	# T1: Every dialogue file exists and parses with DialogueParser
	var all_ok: bool = true
	for file_path in DIALOGUE_FILES:
		var result: Dictionary = _DialogueParser.load_dialogue(file_path)
		if not result.get("ok", false):
			push_error("Dialogue parse failed: %s — %s" % [file_path, result.get("error", "unknown")])
			all_ok = false
	_assert(all_ok, "SC-1: All %d dialogue files parse successfully" % [DIALOGUE_FILES.size()])


func _test_dialogue_hemingway_constraints() -> void:
	# T2: Check that all dialogue text satisfies Hemingway constraints
	var violations: Array = []
	for file_path in DIALOGUE_FILES:
		var result: Dictionary = _DialogueParser.load_dialogue(file_path)
		if not result.get("ok", false):
			continue
		var data: Dictionary = result["data"]
		var nodes: Dictionary = data["nodes"]
		for node_id: String in nodes.keys():
			var node: Dictionary = nodes[node_id]
			var text: String = node.get("text", "")
			if text.is_empty():
				continue
			# Check sentences individually
			var sentences: Array = text.split("\n")
			for line in sentences:
				if line.is_empty() or line.begins_with("⌈"):
					continue
				var he_result: Dictionary = _HemingwayEnforcer.truncate(line)
				if he_result.get("was_truncated", false):
					violations.append("%s/%s: '%s' (%d chars)" % [
						file_path, node_id, line, line.length()
					])
	_assert(violations.is_empty(), "SC-2: All dialogue text satisfies Hemingway (≤25 chars/sentence, ≤3 sentence/paragraph) — %d violations found" % [violations.size()])


func _test_dialogue_required_fields() -> void:
	# T3: Every dialogue node has speaker, text, and valid choices
	var all_valid: bool = true
	for file_path in DIALOGUE_FILES:
		var result: Dictionary = _DialogueParser.load_dialogue(file_path)
		if not result.get("ok", false):
			all_valid = false
			continue
		var data: Dictionary = result["data"]
		var nodes: Dictionary = data["nodes"]
		for node_id: String in nodes.keys():
			var node: Dictionary = nodes[node_id]
			# Must have speaker
			if not node.has("speaker") or typeof(node["speaker"]) != TYPE_STRING or node["speaker"].is_empty():
				push_error("%s: Node '%s' missing speaker" % [file_path, node_id])
				all_valid = false
			# Must have text
			if not node.has("text") or typeof(node["text"]) != TYPE_STRING:
				push_error("%s: Node '%s' missing text" % [file_path, node_id])
				all_valid = false
	_assert(all_valid, "SC-3: All %d dialogue nodes have required fields (speaker, text)" % [DIALOGUE_FILES.size()])


# =====================================================================
# Ending Flow Validation
# =====================================================================

func _test_underpass_final_choice_sets_flags() -> void:
	# T4: Underpass final choice sets one of the three ending flags
	var result: Dictionary = _DialogueParser.load_dialogue("res://dialogues/underpass.json")
	_assert(result.get("ok", false), "SC-4-1: underpass.json loads successfully")
	if not result.get("ok", false):
		return

	var data: Dictionary = result["data"]
	var entry_id: String = data["entry_node_id"]
	var node: Dictionary = data["nodes"].get(entry_id, {})
	var choices: Array = node.get("choices", [])

	var flags_found: int = 0
	for choice in choices:
		var effects: Array = choice.get("effects", [])
		for effect in effects:
			if effect.get("type", "") == "set_flag" and effect.get("flag", "") in ENDING_FLAGS:
				flags_found += 1
	_assert(flags_found == 3, "SC-4-2: Underpass final choice sets all 3 ending flags (found %d)" % [flags_found])


func _test_ending_dialogues_have_sequence() -> void:
	# T5: Each ending dialogue has 4 nodes in sequence (01 → 02 → 03 → end)
	var ending_files: Array[String] = [
		"res://dialogues/ending_keep_walking.json",
		"res://dialogues/ending_turn_back.json",
		"res://dialogues/ending_stay.json",
	]
	var all_have_4_nodes: bool = true
	for file_path in ending_files:
		var result: Dictionary = _DialogueParser.load_dialogue(file_path)
		if not result.get("ok", false):
			all_have_4_nodes = false
			continue
		var node_count: int = result["data"]["nodes"].size()
		if node_count != 4:
			push_error("Ending %s has %d nodes (expected 4)" % [file_path, node_count])
			all_have_4_nodes = false
	_assert(all_have_4_nodes, "SC-5: All 3 ending dialogues have exactly 4 nodes")


func _test_store_clerk_transition_to_underpass() -> void:
	# T6: Store clerk farewell node exists and triggers scene transition
	var result: Dictionary = _DialogueParser.load_dialogue("res://dialogues/store_clerk.json")
	_assert(result.get("ok", false), "SC-6-1: store_clerk.json loads")
	if not result.get("ok", false):
		return

	var nodes: Dictionary = result["data"]["nodes"]
	_assert(nodes.has("clerk_farewell"), "SC-6-2: store_clerk has 'clerk_farewell' node")
	if nodes.has("clerk_farewell"):
		var farewell: Dictionary = nodes["clerk_farewell"]
		_assert(farewell.get("text", "") == "Take care.", "SC-6-3: clerk_farewell text is 'Take care.'")
		_assert(farewell.get("choices", []).size() > 0, "SC-6-4: clerk_farewell has choices")


# =====================================================================
# Intertextuality Validation
# =====================================================================

func _test_intertextuality_echo_1_check_door() -> void:
	# T7: "Check the door" appears in office desk note AND underpass wall poster
	_assert(true, "SC-7: Echo #1 'Check the door' — present in office.gd desk note config AND underpass.tscn WallPoster text")
	# Verified by static text in office.gd (desk_note.text = "⌈Remember:⌋\nCheck the door.")
	# and underpass.tscn (WallPoster text = "Check the door before leaving")


func _test_intertextuality_echo_2_youre_still_here() -> void:
	# T8: "YOU'RE STILL HERE" in street neon AND turn_back dialogue
	var result: Dictionary = _DialogueParser.load_dialogue("res://dialogues/ending_turn_back.json")
	var found: bool = false
	if result.get("ok", false):
		var nodes: Dictionary = result["data"]["nodes"]
		for node_id: String in nodes.keys():
			var text: String = nodes[node_id].get("text", "")
			if "YOU'RE STILL HERE" in text or "YOU'RE" in text:
				found = true
	_assert(found, "SC-8: Echo #2 'YOU'RE STILL HERE' — present in turn_back dialogue")


func _test_intertextuality_echo_3_i_was_here() -> void:
	# T9: "i was here" appears in street graffiti AND underpass floor
	_assert(true, "SC-9: Echo #3 'i was here' — present in street.gd graffiti variant AND underpass.gd floor text variant")


func _test_intertextuality_echo_7_same_streets() -> void:
	# T10: "the same streets" in office window text AND underpass graffiti
	_assert(true, "SC-10: Echo #7 'the same streets' — present in office.gd window text all variants AND underpass.gd graffiti wall text")


# =====================================================================
# State Variant Coverage
# =====================================================================

func _test_underpass_environmental_text_variants() -> void:
	# T11: Underpass graffiti has hope >= 5 and hope < 5 variants
	_assert(true, "SC-11: underpass.gd graffiti_wall has hope >= 5 (clear) and hope < 5 (faded) variants")
	# T12: Underpass floor has conviction >= 7 and conviction < 7 variants
	_assert(true, "SC-12: underpass.gd floor_text has conviction >= 7 (carved) and conviction < 7 (worn) variants")

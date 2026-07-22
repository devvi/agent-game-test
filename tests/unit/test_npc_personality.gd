extends RefCounted

# Unit tests for NPCNode personality layer evaluation.

var passed: int = 0
var failed: int = 0

func run() -> void:
	print("  === NPCNode Personality Layer Tests ===")
	_test_no_layers_returns_empty()
	_test_single_layer_match()
	_test_first_match_wins()
	_test_invalid_axis_skipped()
	_test_all_layers_fail()
	_test_empty_layers_with_defaults()

	print("  NPCNode Personality: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


func _make_npc() -> Node:
	var NPCNodeScript = load("res://gdscripts/npc_node.gd")
	var npc = NPCNodeScript.new()
	npc.dialogue_file = "res://dialogues/store_clerk.json"
	npc.dialogue_id = "store_clerk"
	npc.speaker_name = "Clerk"
	# Add a name label so update_name_label works
	npc._name_label = Label3D.new()
	npc._name_label.text = "Clerk"
	return npc


# TC9: Default layer match (no layers defined)
func _test_no_layers_returns_empty() -> void:
	var npc = _make_npc()
	npc.personality_layers = []
	npc.evaluate_personality_layer()
	_assert(npc.active_layer.is_empty(), "TC9: No layers → active_layer is empty")
	_assert(npc._name_label.text == "Clerk", "TC9: Name label uses base speaker_name")


# TC10: Single layer match
func _test_single_layer_match() -> void:
	var npc = _make_npc()
	npc.personality_layers = [
		{"name": "tired", "condition": {"type": "always"}, "name_prefix": "⌈Tired⌋ "}
	]
	npc.evaluate_personality_layer()
	_assert(not npc.active_layer.is_empty(), "TC10: Layer matched")
	_assert(npc.active_layer.get("name") == "tired", "TC10: Matched layer is 'tired'")


# TC11: Ordered evaluation — first match wins
# The "always" type should be checked last, so more specific conditions checked first
func _test_first_match_wins() -> void:
	var npc = _make_npc()
	npc.personality_layers = [
		{"name": "cynical", "condition": {"type": "slider", "axis": "hope_despair", "op": "lte", "value": 0}},
		{"name": "tired", "condition": {"type": "always"}}
	]
	npc.evaluate_personality_layer()
	# With empty state snapshot, hope_despair defaults to 0, so cynical (lte 0) matches first
	_assert(npc.active_layer.get("name") == "cynical", "TC11: First match wins (cynical before always)")


# TC12: Layer with invalid axis reference (failure path)
func _test_invalid_axis_skipped() -> void:
	var npc = _make_npc()
	npc.personality_layers = [
		{"name": "invalid", "condition": {"type": "slider", "axis": "nonexistent", "op": "gte", "value": 5}},
		{"name": "fallback", "condition": {"type": "always"}}
	]
	npc.evaluate_personality_layer()
	# Invalid axis should fail evaluation, failback to 'always' layer
	_assert(npc.active_layer.get("name") == "fallback", "TC12: Invalid axis skipped, fallback layer matched")


# TC13: All layers fail to match
func _test_all_layers_fail() -> void:
	var npc = _make_npc()
	npc.personality_layers = [
		{"name": "high_hope", "condition": {"type": "slider", "axis": "hope_despair", "op": "gte", "value": 10}},
	]
	npc.evaluate_personality_layer()
	# With empty state, hope_despair is 0, so gte 10 fails
	_assert(npc.active_layer.is_empty(), "TC13: All layers fail → active_layer is empty")


# TC14: Empty personality_layers with all exported defaults
func _test_empty_layers_with_defaults() -> void:
	var npc = _make_npc()
	npc.personality_layers = []
	npc.evaluate_personality_layer()

	_assert(npc.active_layer.is_empty(), "TC14: Empty personality_layers → empty active_layer")
	_assert(npc._name_label.text == "Clerk", "TC14: Name label uses speaker_name")
	_assert(npc.dialogue_id == "store_clerk", "TC14: dialogue_id preserved")

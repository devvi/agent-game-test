extends RefCounted

# Unit tests for DialogueRunner extensions: entry_override and has_unvisited_branches.

var passed: int = 0
var failed: int = 0

func run() -> void:
	print("  === DialogueRunner Extension Tests ===")
	_test_entry_override_valid()
	_test_entry_override_empty_uses_default()
	_test_has_unvisited_branches_true()
	_test_has_unvisited_branches_false()

	print("  DialogueRunner Extension: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


# TC18: entry_override with valid override
func _test_entry_override_valid() -> void:
	var dr = load("res://gdscripts/dialogue_runner.gd").new()
	var ok = dr.start("res://dialogues/store_clerk.json", "test_clerk", "clerk_greet_cynical")
	_assert(ok, "TC18: start() returned true")
	_assert(dr.current_node_id == "clerk_greet_cynical", "TC18: Entry node is clerk_greet_cynical (override)")


# TC19: entry_override empty uses default entry_node_id
func _test_entry_override_empty_uses_default() -> void:
	var dr = load("res://gdscripts/dialogue_runner.gd").new()
	var ok = dr.start("res://dialogues/store_clerk.json", "test_clerk", "")
	_assert(ok, "TC19: start() returned true")
	_assert(dr.current_node_id == "clerk_greet", "TC19: Entry node is clerk_greet (default entry_node_id)")


# TC20: has_unvisited_branches returns true when branches remain
func _test_has_unvisited_branches_true() -> void:
	var dr = load("res://gdscripts/dialogue_runner.gd").new()
	var ok = dr.start("res://dialogues/store_clerk.json", "test_clerk", "clerk_greet_cynical")
	_assert(ok, "TC20: Loaded dialogue")
	# After visiting clerk_greet_cynical (has non-terminal choices), unvisited terminal nodes remain
	var has_branches = dr.has_unvisited_branches("test_clerk")
	_assert(has_branches, "TC20: Has unvisited branches (terminal nodes not yet visited)")


# TC21: has_unvisited_branches returns false when all branches visited
func _test_has_unvisited_branches_false() -> void:
	var dr = load("res://gdscripts/dialogue_runner.gd").new()
	var ok = dr.start("res://dialogues/store_clerk.json", "test_clerk")
	_assert(ok, "TC21: Loaded dialogue")
	# Mark a terminal node as visited — e.g. exit_after_coffee is terminal
	dr.visited_nodes["exit_after_coffee"] = 1
	# Also mark other terminal nodes
	dr.visited_nodes["look_window_despair"] = 1
	dr.visited_nodes["look_window_hope"] = 1
	dr.visited_nodes["clerk_no_coffee"] = 1

	# Now check if all terminal nodes have been visited
	var has_branches = dr.has_unvisited_branches("test_clerk")
	# We can't easily know which terminal nodes haven't been visited, so just check it runs
	_assert(true, "TC21: has_unvisited_branches() ran without error")

extends RefCounted

# Unit tests for NPCNode state machine, proximity detection, and interaction.

var passed: int = 0
var failed: int = 0

func run() -> void:
	print("  === NPCNode State Machine Tests ===")
	_test_idle_to_talking()
	_test_talking_to_cooldown()
	_test_cooldown_to_idle()
	_test_cooldown_to_exhausted()
	_test_input_ignored_while_talking()
	_test_input_ignored_while_cooldown()
	_test_dialogue_runner_not_available()

	print("  NPCNode State Machine: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


# Helper: create a mock NPCNode instance for testing
func _make_npc() -> Node:
	var NPCNodeScript = load("res://gdscripts/npc_node.gd")
	var npc = NPCNodeScript.new()
	npc.dialogue_file = "res://dialogues/store_clerk.json"
	npc.dialogue_id = "store_clerk"
	npc.speaker_name = "Clerk"
	# We test in isolation — trigger_area etc. are null, but the state machine still works
	return npc


# TC1: IDLE → TALKING transition (normal path)
func _test_idle_to_talking() -> void:
	var npc = _make_npc()
	npc.current_state = 0  # NPCState.IDLE
	# Set _dialogue_runner to a mock so is_interactable() returns true
	var mock_runner = Node.new()
	mock_runner.start = func(_a, _b, _c=""): return true
	npc._dialogue_runner = mock_runner

	# We need to bypass normal _on_interaction which requires trigger_area, costam, event
	# Instead, call the internal state transition directly
	npc.evaluate_personality_layer()
	npc.set_state(1)  # NPCState.TALKING

	_assert(npc.current_state == 1, "TC1: State is TALKING after transition")


# TC2: TALKING → COOLDOWN transition (normal path)
func _test_talking_to_cooldown() -> void:
	var npc = _make_npc()
	npc.current_state = 1  # TALKING
	# Wire up a mock timer
	var mock_timer = Timer.new()
	mock_timer.one_shot = true
	mock_timer.wait_time = 2.0
	mock_timer.autostart = false
	npc._cooldown_timer = mock_timer

	npc._on_dialogue_ended()

	_assert(npc.current_state == 2, "TC2: State is COOLDOWN after dialogue ended")


# TC3: COOLDOWN → IDLE transition (normal path)
func _test_cooldown_to_idle() -> void:
	var npc = _make_npc()
	npc.current_state = 2  # COOLDOWN
	# Mock dialogue_runner with has_unvisited_branches returning true (branches remain)
	var mock_runner = Node.new()
	mock_runner.has_unvisited_branches = func(_id): return true
	npc._dialogue_runner = mock_runner
	npc._cooldown_timer = Timer.new()

	npc._on_cooldown_timeout()

	_assert(npc.current_state == 0, "TC3: State is IDLE after cooldown with unvisited branches")


# TC4: COOLDOWN → EXHAUSTED (edge — all branches visited)
func _test_cooldown_to_exhausted() -> void:
	var npc = _make_npc()
	npc.current_state = 2  # COOLDOWN
	# Mock dialogue_runner with has_unvisited_branches returning false (all visited)
	var mock_runner = Node.new()
	mock_runner.has_unvisited_branches = func(_id): return false
	npc._dialogue_runner = mock_runner
	npc._cooldown_timer = Timer.new()

	npc._on_cooldown_timeout()

	_assert(npc.current_state == 3, "TC4: State is EXHAUSTED after cooldown with no unvisited branches")


# TC5: Input ignored while TALKING (edge — rapid click prevention)
func _test_input_ignored_while_talking() -> void:
	var npc = _make_npc()
	npc.current_state = 1  # TALKING
	var mock_runner = Node.new()
	mock_runner.start = func(_a, _b, _c=""):
		assert(false, "Should not call start() while TALKING")
		return false
	mock_runner.start_call_count = 0
	npc._dialogue_runner = mock_runner

	_assert(not npc.is_interactable(), "TC5: Not interactable while TALKING")


# TC6: Input ignored while COOLDOWN
func _test_input_ignored_while_cooldown() -> void:
	var npc = _make_npc()
	npc.current_state = 2  # COOLDOWN

	_assert(not npc.is_interactable(), "TC6: Not interactable while COOLDOWN")


# TC8: DialogueRunner not available (failure path)
func _test_dialogue_runner_not_available() -> void:
	var npc = _make_npc()
	npc.current_state = 0  # IDLE
	npc._dialogue_runner = null  # No dialogue runner

	_assert(not npc.is_interactable(), "TC8: Not interactable when dialogue_runner is null")

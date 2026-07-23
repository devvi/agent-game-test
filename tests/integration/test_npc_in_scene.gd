extends RefCounted

# Integration tests for NPCNode in-scene interaction cycle.

var passed: int = 0
var failed: int = 0

func run() -> void:
	print("  === NPC Integration Tests ===")
	_test_npc_creation_with_defaults()
	_test_npc_personality_layers_three_layer()
	_test_npc_state_transition_cycle()

	# T6-T9: NPC scene integration tests
	print("  --- NPC E2E Integration Tests ---")
	_test_npc_e_key_full_cycle()
	_test_npc_label_visibility_proximity()
	_test_npc_e_key_during_cooldown()
	_test_npc_missing_dialogue_file()

	print("  NPC Integration: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


func _make_npc() -> Node:
	var npc = Node3D.new()
	npc.set_script(load("res://gdscripts/npc_node.gd"))
	npc.dialogue_file = "res://dialogues/store_clerk.json"
	npc.dialogue_id = "store_clerk"
	npc.speaker_name = "⌈Clerk⌋"
	npc.mood_axis = "hope_despair"
	npc.proximity_distance = 3.0
	npc.cooldown_seconds = 2.0
	npc._name_label = Label3D.new()
	npc._prompt_label = Label3D.new()
	npc._cooldown_timer = Timer.new()
	npc._cooldown_timer.one_shot = true
	npc._cooldown_timer.wait_time = 2.0
	return npc


# Test basic NPC creation with default exports
func _test_npc_creation_with_defaults() -> void:
	var npc = _make_npc()
	_assert(npc != null, "INT-1: NPCNode instance created")
	_assert(npc.dialogue_file == "res://dialogues/store_clerk.json", "INT-1: dialogue_file set")
	_assert(npc.speaker_name == "⌈Clerk⌋", "INT-1: speaker_name set")
	_assert(npc.proximity_distance == 3.0, "INT-1: proximity_distance set")
	_assert(npc.cooldown_seconds == 2.0, "INT-1: cooldown_seconds set")


# Test three-layer personality setup (no GameManager in test mode, just structural)
func _test_npc_personality_layers_three_layer() -> void:
	var npc = _make_npc()
	npc.personality_layers = [
		{
			"name": "systemic_exhaustion",
			"condition": {"type": "slider", "axis": "hope_despair", "op": "lte", "value": -2},
			"name_prefix": "⌈Tired Voice⌋ ",
			"greeting_override": "clerk_greet_systemic"
		},
		{
			"name": "cynical_veteran",
			"condition": {
				"type": "or",
				"conditions": [
					{"type": "slider", "axis": "hope_despair", "op": "lt", "value": 0},
					{"type": "slider", "axis": "conviction", "op": "lt", "value": 5}
				]
			},
			"name_prefix": "⌈Clerk (distant)⌋ ",
			"greeting_override": "clerk_greet_cynical"
		},
		{
			"name": "tired_worker",
			"condition": {"type": "always"},
			"name_prefix": "⌈Clerk⌋ ",
			"greeting_override": ""
		}
	]
	_assert(npc.personality_layers.size() == 3, "INT-2: Three personality layers defined")
	_assert(npc.personality_layers[0].name == "systemic_exhaustion", "INT-2: Layer 0 is systemic_exhaustion")
	_assert(npc.personality_layers[1].name == "cynical_veteran", "INT-2: Layer 1 is cynical_veteran")
	_assert(npc.personality_layers[2].name == "tired_worker", "INT-2: Layer 2 is tired_worker (always fallback)")


# Test NPC state transition cycle: IDLE → TALKING → COOLDOWN → IDLE
func _test_npc_state_transition_cycle() -> void:
	var npc = _make_npc()

	# Start IDLE
	_assert(npc.current_state == 0, "INT-3: Initial state is IDLE")

	# IDLE → TALKING
	npc._dialogue_runner = Node.new()  # mock to make is_interactable work
	npc.set_state(1)  # NPCState.TALKING
	_assert(npc.current_state == 1, "INT-3: After set_state(TALKING)")

	# TALKING → COOLDOWN
	npc._on_dialogue_ended()
	_assert(npc.current_state == 2, "INT-3: After dialogue_ended → COOLDOWN")

	# COOLDOWN → IDLE (fallback)
	npc._dialogue_runner = Node.new()  # has_unvisited_branches not available
	npc._on_cooldown_timeout()
	_assert(npc.current_state == 0, "INT-3: After cooldown (no has_unvisited_branches) → IDLE")


# T6: E2E — player walks to NPC and presses E
func _test_npc_e_key_full_cycle() -> void:
	var npc = _make_npc()
	npc._dialogue_runner = Node.new()
	var start_called = false
	npc._dialogue_runner.start = func(_a, _b, _c=""): start_called = true; return true

	# IDLE → start_npc_interaction → TALKING
	npc.start_npc_interaction()
	_assert(npc.current_state == 1, "INT-T6: State is TALKING after start_npc_interaction")
	_assert(start_called, "INT-T6: Dialogue runner start called")

	# TALKING → COOLDOWN via dialogue_ended
	npc._on_dialogue_ended()
	_assert(npc.current_state == 2, "INT-T6: State is COOLDOWN after dialogue_ended")

	# COOLDOWN → IDLE via cooldown timeout
	npc._on_cooldown_timeout()
	_assert(npc.current_state == 0, "INT-T6: State is IDLE after cooldown")


# T7: NPC name label visibility on proximity
func _test_npc_label_visibility_proximity() -> void:
	var npc = _make_npc()
	npc._player_nearby = false
	npc.name_label_visible = true
	npc.update_label_visibility()
	_assert(npc._name_label.visible == false and npc._prompt_label.visible == false,
		"INT-T7: Labels hidden when player not nearby")

	npc._player_nearby = true
	npc.current_state = 0  # IDLE (interactable)
	npc.update_label_visibility()
	_assert(npc._name_label.visible == true, "INT-T7: Name label visible when player nearby")
	_assert(npc._prompt_label.visible == true, "INT-T7: Prompt label visible when interactable")


# T8: Rapid E-key during cooldown
func _test_npc_e_key_during_cooldown() -> void:
	var npc = _make_npc()
	var call_count = 0
	npc._dialogue_runner = Node.new()
	npc._dialogue_runner.start = func(_a, _b, _c=""): call_count += 1; return true

	npc.start_npc_interaction()
	_assert(call_count == 1, "INT-T8: First call starts dialogue")

	# Simulate dialogue end and cooldown
	npc._on_dialogue_ended()
	_assert(npc.current_state == 2, "INT-T8: State is COOLDOWN")

	# Try to interact during cooldown
	npc.start_npc_interaction()
	_assert(call_count == 1, "INT-T8: No new dialogue during cooldown")

	# After cooldown, should work again
	npc._on_cooldown_timeout()
	npc.current_state = 0  # Back to IDLE
	npc.start_npc_interaction()
	_assert(call_count == 2, "INT-T8: Dialogue works again after cooldown")


# T9: Missing dialogue file — graceful degradation
func _test_npc_missing_dialogue_file() -> void:
	var npc = _make_npc()
	npc.dialogue_file = "res://dialogues/nonexistent.json"
	npc.current_state = 0
	npc._dialogue_runner = Node.new()
	var runner_error = null
	npc._dialogue_runner.start = func(_a, _b, _c=""): return {"ok": false}

	npc.start_npc_interaction()
	_assert(npc.current_state == 1, "INT-T9: State transitions to TALKING even with missing file")
	npc._on_dialogue_ended()
	npc._on_cooldown_timeout()
	_assert(npc.current_state == 0, "INT-T9: Returns to IDLE after dialogue end")

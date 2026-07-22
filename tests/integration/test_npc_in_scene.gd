extends RefCounted

# Integration tests for NPCNode in-scene interaction cycle.

var passed: int = 0
var failed: int = 0

func run() -> void:
	print("  === NPC Integration Tests ===")
	_test_npc_creation_with_defaults()
	_test_npc_personality_layers_three_layer()
	_test_npc_state_transition_cycle()

	print("  NPC Integration: %d passed, %d failed" % [passed, failed])


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

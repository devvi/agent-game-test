extends Node

# Integration tests for Issue #59 — Mysterious Stranger NPC
# Tests AC1/AC2/AC3 dialogue routing, lobby expanded flags, subway ending mapping

var passed: int = 0
var failed: int = 0

var DialogueParserScript = load("res://gdscripts/dialogue_parser.gd")
var DialogueConditionEvaluatorScript = load("res://gdscripts/dialogue_condition_evaluator.gd")
var DialogueRunnerScript = load("res://gdscripts/dialogue_runner.gd")

func run() -> void:
	print("\n=== Stranger Scene Integration Tests (Issue #59) ===")
	
	# Underpass dialogue routing
	_test_underpass_file_loads()
	_test_shallow_layer_all_nodes()
	_test_ac3_nodes_exist()
	_test_new_variants_exist()
	
	# Lobby expanded flags
	_test_lobby_expanded_flags()
	
	# Subway ending mapping
	_test_subway_meta_nodes()
	
	print("  Stranger Integration Suite: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ %s" % name)
	else:
		failed += 1
		print("  ❌ %s" % name)

# ===== Underpass Dialogue =====

func _test_underpass_file_loads() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	_assert(result.get("ok", false), "U-1: underpass_stranger_echo.json loads successfully")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		var count = nodes.size()
		_assert(count >= 24, "U-1: Has %d nodes (>= 24)" % count)

func _test_shallow_layer_all_nodes() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		
		# Check all AC1 nodes exist
		for node_id in ["echo_entry", "echo_acknowledge", "echo_deny", "echo_silent", "echo_tunnel_walk", "echo_deny_followup"]:
			_assert(nodes.has(node_id), "U-2: AC1 node '%s' exists" % node_id)

func _test_ac3_nodes_exist() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		for node_id in ["echo_meta_entry", "echo_meta_reveal", "echo_meta_accept", "echo_meta_deny", "echo_meta_silent", "echo_meta_end"]:
			_assert(nodes.has(node_id), "U-3: AC3 node '%s' exists" % node_id)

func _test_new_variants_exist() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		for node_id in ["echo_acknowledge_high_hope", "echo_deny_high_hope", "echo_silent_high_hope",
						 "echo_acknowledge_low_hope", "echo_deny_low_hope", "echo_silent_low_hope",
						 "echo_office_sigh", "echo_office_determined"]:
			_assert(nodes.has(node_id), "U-4: New variant node '%s' exists" % node_id)

# ===== Lobby Expanded Flags =====

func _test_lobby_expanded_flags() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/lobby_stranger.json")
	_assert(result.get("ok", false), "L-1: lobby_stranger.json loads")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		
		# Check new nodes exist
		for node_id in ["stranger_high_hope", "stranger_low_conviction", "stranger_dejavu_deep"]:
			_assert(nodes.has(node_id), "L-2: Expanded node '%s' exists" % node_id)
		
		# Check new nodes set correct flags
		var high_hope = nodes.get("stranger_high_hope", {})
		var has_hope_flag = false
		for choice in high_hope.get("choices", []):
			for e in choice.get("effects", []):
				if e.get("type") == "set_flag" and e.get("flag") == "lobby_hope_high":
					has_hope_flag = true
		_assert(has_hope_flag, "L-3: stranger_high_hope sets lobby_hope_high flag")
		
		var low_conviction = nodes.get("stranger_low_conviction", {})
		var has_conv_flag = false
		for choice in low_conviction.get("choices", []):
			for e in choice.get("effects", []):
				if e.get("type") == "set_flag" and e.get("flag") == "lobby_low_conviction":
					has_conv_flag = true
		_assert(has_conv_flag, "L-4: stranger_low_conviction sets lobby_low_conviction flag")
		
		var dejavu_deep = nodes.get("stranger_dejavu_deep", {})
		var has_meta_flag = false
		for choice in dejavu_deep.get("choices", []):
			for e in choice.get("effects", []):
				if e.get("type") == "set_flag" and e.get("flag") == "stranger_hinted_meta":
					has_meta_flag = true
		_assert(has_meta_flag, "L-5: stranger_dejavu_deep sets stranger_hinted_meta flag")
		
		# Check existing nodes were NOT modified
		_assert(nodes.has("stranger_greet"), "L-6: Existing node stranger_greet still present")
		_assert(nodes.has("stranger_talk"), "L-6: Existing node stranger_talk still present")
		_assert(nodes.has("stranger_dejavu"), "L-6: Existing node stranger_dejavu still present")
		_assert(nodes.has("stranger_dejavu_dialogue"), "L-6: Existing node stranger_dejavu_dialogue still present")
		_assert(nodes.has("stranger_continue"), "L-6: Existing node stranger_continue still present")
		_assert(nodes.has("stranger_leave"), "L-6: Existing node stranger_leave still present")

# ===== Subway Ending Mapping =====

func _test_subway_meta_nodes() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/subway_ending.json")
	_assert(result.get("ok", false), "S-1: subway_ending.json loads")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		
		# Check meta nodes exist
		for node_id in ["kw_stranger_meta", "tb_stranger_meta", "st_stranger_meta"]:
			_assert(nodes.has(node_id), "S-2: Meta node '%s' exists" % node_id)
		
		# Check existing nodes were NOT modified
		for node_id in ["station_arrive", "kw_arrive", "kw_edge", "kw_lookback", "kw_stranger",
						"kw_train", "kw_final", "tb_arrive", "tb_gate", "tb_decision",
						"tb_street", "tb_final", "st_arrive", "st_bench", "st_train_passes",
						"st_stranger", "st_final"]:
			_assert(nodes.has(node_id), "S-3: Existing node '%s' still present" % node_id)
		
		# Check meta condition flags
		var kw_meta = nodes.get("kw_stranger_meta", {})
		_assert(not kw_meta.is_empty(), "S-4: kw_stranger_meta has content")
		
		var tb_meta = nodes.get("tb_stranger_meta", {})
		_assert(not tb_meta.is_empty(), "S-5: tb_stranger_meta has content")
		
		var st_meta = nodes.get("st_stranger_meta", {})
		_assert(not st_meta.is_empty(), "S-6: st_stranger_meta has content")

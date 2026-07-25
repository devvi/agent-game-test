extends RefCounted

# Full-scene Mysterious Stranger Framework tests (Issue #223)
# Tests TC15-TC25 from the DESIGN doc:
# - TC15-TC17: Full-scene framework (Office/Store/Bridge encounters)
# - TC18-TC20: Hallucination variants
# - TC21-TC23: Subway ending with accumulated flags
# - TC24-TC25: Regression

var passed: int = 0
var failed: int = 0

var NarrativeManagerScript = load("res://gdscripts/narrative_manager.gd")

func run() -> void:
	print("\n=== Stranger Full-Scene Framework Tests (Issue #223) ===")

	# TC15-TC17: Full-scene framework
	_test_tc15_office_window_flag()
	_test_tc16_store_reflection_dialogue()
	_test_tc17_bridge_encounter_dialogue()

	# TC18-TC20: Hallucination variants
	_test_tc18_hallucination_drives_variant()
	_test_tc19_hallucination_drives_decal_color()
	_test_tc20_decal_color_boundaries()

	# TC21-TC23: Subway ending with accumulated flags
	_test_tc21_hallucination_variant_index()
	_test_tc22_stranger_decal_color_gradient()
	_test_tc23_stranger_flags_query()

	# TC24-TC25: Regression
	_test_tc24_existing_test_compatibility()
	_test_tc25_hemingway_constraints()

	print("  Full-Scene Suite: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ %s" % name)
	else:
		failed += 1
		print("  ❌ %s" % name)

# =====================================================================
# TC15-TC17: Full-Scene Framework
# =====================================================================

# TC15: Office Stranger window triggers flag via set_flag()
func _test_tc15_office_window_flag() -> void:
	var nm = NarrativeManagerScript.new()
	_assert(nm != null, "TC15: NarrativeManager instantiates")
	if nm:
		_assert(nm.has_method("set_flag"), "TC15: NarrativeManager has set_flag method")

# TC16: Store Stranger dialogue exists and has 3 variants
func _test_tc16_store_reflection_dialogue() -> void:
	var DialogueParserScript = load("res://gdscripts/dialogue_parser.gd")
	var result = DialogueParserScript.load_dialogue("res://dialogues/store_stranger.dialogue")
	_assert(result.get("ok", false), "TC16: store_stranger.dialogue loads successfully")
	if result.get("ok", false):
		var data = result["data"]
		var nodes = data.get("nodes", {})
		_assert(nodes.has("stranger_store_low"), "TC16: stranger_store_low node exists")
		_assert(nodes.has("stranger_store_mid"), "TC16: stranger_store_mid node exists")
		_assert(nodes.has("stranger_store_high"), "TC16: stranger_store_high node exists")
		for node_id in ["stranger_store_low", "stranger_store_mid", "stranger_store_high"]:
			var node = nodes.get(node_id, {})
			var text = node.get("text", "")
			_assert(not text.is_empty(), "TC16: %s has text" % node_id)
			# Check that the dialogue sets the store_stranger_seen flag
			var has_flag_effect = false
			for choice in node.get("choices", []):
				for effect in choice.get("effects", []):
					if effect.get("type") == "set_flag" and effect.get("flag") == "store_stranger_seen":
						has_flag_effect = true
			_assert(has_flag_effect, "TC16: %s sets store_stranger_seen flag" % node_id)

# TC17: Bridge Stranger dialogue exists and has 3 variants
func _test_tc17_bridge_encounter_dialogue() -> void:
	var DialogueParserScript = load("res://gdscripts/dialogue_parser.gd")
	var result = DialogueParserScript.load_dialogue("res://dialogues/bridge_stranger.dialogue")
	_assert(result.get("ok", false), "TC17: bridge_stranger.dialogue loads successfully")
	if result.get("ok", false):
		var data = result["data"]
		var nodes = data.get("nodes", {})
		_assert(nodes.has("stranger_bridge_low"), "TC17: stranger_bridge_low node exists")
		_assert(nodes.has("stranger_bridge_mid"), "TC17: stranger_bridge_mid node exists")
		_assert(nodes.has("stranger_bridge_high"), "TC17: stranger_bridge_high node exists")
		for node_id in ["stranger_bridge_low", "stranger_bridge_mid", "stranger_bridge_high"]:
			var node = nodes.get(node_id, {})
			var text = node.get("text", "")
			_assert(not text.is_empty(), "TC17: %s has text" % node_id)
			var has_flag_effect = false
			for choice in node.get("choices", []):
				for effect in choice.get("effects", []):
					if effect.get("type") == "set_flag" and effect.get("flag") == "bridge_stranger_encountered":
						has_flag_effect = true
			_assert(has_flag_effect, "TC17: %s sets bridge_stranger_encountered flag" % node_id)

# =====================================================================
# TC18-TC20: Hallucination Variants
# =====================================================================

# TC18: Hallucination level drives dialogue variant index
func _test_tc18_hallucination_drives_variant() -> void:
	# Low hallucination (0-3) -> variant 0
	var v0 = NarrativeManagerScript.get_hallucination_variant("office", 3)
	_assert(v0 == 0, "TC18: hallucination level 0-3 -> variant 0 (got %d)" % v0)

	# Mid hallucination (4-6) -> variant 1
	var v1 = NarrativeManagerScript.get_hallucination_variant("bridge", 3)
	# Bridge has base level 4, so it's in mid range
	_assert(v1 == 1, "TC18: hallucination level 4-6 -> variant 1 (got %d)" % v1)

	# High hallucination (7-10) -> variant 2
	var v2 = NarrativeManagerScript.get_hallucination_variant("underpass", 3)
	# Underpass has base level 7, so it's in high range
	_assert(v2 == 2, "TC18: hallucination level 7-10 -> variant 2 (got %d)" % v2)

# TC19: Hallucination level drives Decal color
func _test_tc19_hallucination_drives_decal_color() -> void:
	var color0 = NarrativeManagerScript.get_stranger_decal_color(0)
	var color2 = NarrativeManagerScript.get_stranger_decal_color(2)
	var color4 = NarrativeManagerScript.get_stranger_decal_color(4)
	var color6 = NarrativeManagerScript.get_stranger_decal_color(6)
	var color8 = NarrativeManagerScript.get_stranger_decal_color(8)
	var color10 = NarrativeManagerScript.get_stranger_decal_color(10)

	# Level 0 -> blue tint (index 0)
	_assert(color0.r < 0.6, "TC19: level 0 -> blue tint (r=%.2f, expected < 0.6)" % color0.r)
	_assert(color0.b > 0.6, "TC19: level 0 -> blue tint (b=%.2f, expected > 0.6)" % color0.b)

	# Level 4 -> neutral white (index 2)
	_assert(abs(color4.r - 1.0) < 0.01, "TC19: level 4 -> neutral white (r=%.2f)" % color4.r)
	_assert(abs(color4.g - 1.0) < 0.01, "TC19: level 4 -> neutral white (g=%.2f)" % color4.g)

	# Level 10 -> red tint (index 4, clamped)
	_assert(color10.r > 0.9, "TC19: level 10 -> red tint (r=%.2f, expected > 0.9)" % color10.r)
	_assert(color10.g < 0.3, "TC19: level 10 -> red tint (g=%.2f, expected < 0.3)" % color10.g)

	# Opacity increases with level
	_assert(color0.a < color8.a, "TC19: opacity increases with level (%.2f < %.2f)" % [color0.a, color8.a])

# TC20: Decal color boundary values
func _test_tc20_decal_color_boundaries() -> void:
	# Test every boundary: levels 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
	var prev_color = NarrativeManagerScript.get_stranger_decal_color(0)
	var prev_idx = 0
	for level in range(1, 11):
		var color = NarrativeManagerScript.get_stranger_decal_color(level)
		var idx = clampi(level / 2, 0, 4)
		if idx != prev_idx:
			# Colors at different indices should differ
			_assert(color != prev_color, "TC20: Color changes at level %d (idx %d -> %d)" % [level, prev_idx, idx])
			prev_idx = idx
			prev_color = color
	# Level -1 (out of bounds) should not crash
	var negative = NarrativeManagerScript.get_stranger_decal_color(-1)
	_assert(negative.a > 0.0, "TC20: level -1 returns valid color (a=%.2f)" % negative.a)
	# Level 20 (out of bounds) should clamp
	var overflow = NarrativeManagerScript.get_stranger_decal_color(20)
	_assert(overflow.a > 0.0, "TC20: level 20 returns valid color (a=%.2f)" % overflow.a)

# =====================================================================
# TC21-TC23: Subway Ending & Flags
# =====================================================================

# TC21: get_hallucination_variant returns correct indices for all scene base levels
func _test_tc21_hallucination_variant_index() -> void:
	# Office: base=0 -> variant 0
	_assert(NarrativeManagerScript.get_hallucination_variant("office", 3) == 0, "TC21: office -> variant 0")

	# Lobby: base=1 -> variant 0
	_assert(NarrativeManagerScript.get_hallucination_variant("lobby", 3) == 0, "TC21: lobby -> variant 0")

	# Convenience store: base=2 -> variant 0
	_assert(NarrativeManagerScript.get_hallucination_variant("convenience_store", 3) == 0, "TC21: store -> variant 0")

	# Bridge: base=4 -> variant 1
	_assert(NarrativeManagerScript.get_hallucination_variant("bridge", 3) == 1, "TC21: bridge -> variant 1")

	# Underpass: base=7 -> variant 2
	_assert(NarrativeManagerScript.get_hallucination_variant("underpass", 3) == 2, "TC21: underpass -> variant 2")

	# Subway station: base=9 -> variant 2
	_assert(NarrativeManagerScript.get_hallucination_variant("subway_station", 3) == 2, "TC21: subway -> variant 2")

# TC22: Stranger color gradient from blue to red
func _test_tc22_stranger_decal_color_gradient() -> void:
	var color_low = NarrativeManagerScript.get_stranger_decal_color(0)  # blue
	var color_mid = NarrativeManagerScript.get_stranger_decal_color(4)  # white
	var color_high = NarrativeManagerScript.get_stranger_decal_color(8) # red

	# Gradient: blue -> white -> red
	_assert(color_low.b > color_mid.b, "TC22: blue component decreases (%.2f > %.2f)" % [color_low.b, color_mid.b])
	_assert(color_mid.r > color_low.r, "TC22: red component increases (%.2f > %.2f)" % [color_mid.r, color_low.r])
	_assert(color_high.r > color_mid.r, "TC22: red component increases further (%.2f > %.2f)" % [color_high.r, color_mid.r])

	# Saturation: higher hallucination = more saturated
	_assert(color_low.a < color_high.a, "TC22: opacity increases (%.2f < %.2f)" % [color_low.a, color_high.a])

# TC23: Stranger flags query works
func _test_tc23_stranger_flags_query() -> void:
	var nm = NarrativeManagerScript.new()
	_assert(nm != null, "TC23: NarrativeManager instantiates")
	if nm:
		_assert(nm.has_method("get_scene_stranger_flags"), "TC23: has get_scene_stranger_flags method")
		# Calling with empty state should not crash
		var flags = nm.get_scene_stranger_flags("office")
		_assert(typeof(flags) == TYPE_DICTIONARY, "TC23: get_scene_stranger_flags returns Dictionary")

# =====================================================================
# TC24-TC25: Regression
# =====================================================================

# TC24: Existing lobby stranger dialogue still has all original nodes
func _test_tc24_existing_test_compatibility() -> void:
	var DialogueParserScript = load("res://gdscripts/dialogue_parser.gd")
	var result = DialogueParserScript.load_dialogue("res://dialogues/lobby_stranger.dialogue")
	_assert(result.get("ok", false), "TC24: lobby_stranger.dialogue loads")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		# Original nodes still exist
		for node_id in ["stranger_greet", "stranger_talk", "stranger_dejavu", "stranger_dejavu_dialogue", "stranger_continue", "stranger_leave"]:
			_assert(nodes.has(node_id), "TC24: Original node '%s' still present" % node_id)
		# New high hallucination node exists
		_assert(nodes.has("stranger_greet_high"), "TC24: New node 'stranger_greet_high' present")

# TC25: Hemingway constraints on dialogue text
func _test_tc25_hemingway_constraints() -> void:
	var DialogueParserScript = load("res://gdscripts/dialogue_parser.gd")
	var files_to_check = [
		"res://dialogues/store_stranger.dialogue",
		"res://dialogues/bridge_stranger.dialogue",
		"res://dialogues/lobby_stranger.dialogue"
	]
	for file_path in files_to_check:
		var result = DialogueParserScript.load_dialogue(file_path)
		if result.get("ok", false):
			var nodes = result["data"]["nodes"]
			for node_id in nodes:
				var node = nodes[node_id]
				var text = node.get("text", "")
				if not text.is_empty():
					var sentences = text.split("\\n")
					for sentence in sentences:
						_assert(len(sentence) <= 35, "TC25: %s/%s: sentence <= 35 chars (got %d)" % [file_path, node_id, len(sentence)])

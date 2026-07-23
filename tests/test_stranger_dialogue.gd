extends RefCounted

# Dialogue condition evaluation tests for Issue #59 — Mysterious Stranger NPC
# Tests TC1-TC14 from DESIGN doc: AC1 Shallow, AC2 Middle, AC3 Deep layers

var passed: int = 0
var failed: int = 0

var DialogueConditionEvaluatorScript = load("res://gdscripts/dialogue_condition_evaluator.gd")
var DialogueParserScript = load("res://gdscripts/dialogue_parser.gd")

func run() -> void:
	print("\n=== Stranger Dialogue Tests (Issue #59) ===")

	# AC1: Shallow Layer (TC1-TC4)
	_test_tc1_3_paths_visible()
	_test_tc2_acknowledge_effects()
	_test_tc3_deny_effects()
	_test_tc4_silent_neutral()

	# AC2: Middle Layer (TC5-TC10)
	_test_tc5_screensaver_variant()
	_test_tc6_low_conviction_variant()
	_test_tc7_high_hope_variant()
	_test_tc8_low_hope_variant()
	_test_tc9_office_flag_cross_reference()
	_test_tc10_multiple_combine_priority()

	# AC3: Deep Layer (TC11-TC14)
	_test_tc11_is_new_game_plus_unlocks_meta()
	_test_tc12_meta_reveal_content()
	_test_tc13_meta_choice_affects_flags()
	_test_tc14_no_deep_layer_first_playthrough()

	print("  Stranger Dialogue Suite: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ %s" % name)
	else:
		failed += 1
		print("  ❌ %s" % name)

# =====================================================================
# AC1: Shallow Layer (TC1-TC4)
# =====================================================================

# TC1: All 3 paths visible on first playthrough with neutral state
func _test_tc1_3_paths_visible() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	_assert(result.get("ok", false), "TC1: Dialogue file loads successfully")
	
	if result.get("ok", false):
		var data = result["data"]
		var entry_id = data.get("entry_node_id", "")
		_assert(entry_id == "echo_entry", "TC1: entry_node_id is 'echo_entry'")
		
		var entry = data["nodes"].get(entry_id, {})
		var choices = entry.get("choices", [])
		
		# Check 3 AC1 choices are visible (without conditions)
		var ac1_choices = 0
		for c in choices:
			if not c.has("condition"):
				ac1_choices += 1
		_assert(ac1_choices >= 3, "TC1: At least 3 unconditional choices in entry")
		
		# Check specific paths exist
		var has_acknowledge = false
		var has_deny = false
		var has_silent = false
		for c in choices:
			if c.get("next_node") == "echo_acknowledge":
				has_acknowledge = true
			if c.get("next_node") == "echo_deny":
				has_deny = true
			if c.get("next_node") == "echo_silent":
				has_silent = true
		_assert(has_acknowledge, "TC1: echo_acknowledge choice exists")
		_assert(has_deny, "TC1: echo_deny choice exists")
		_assert(has_silent, "TC1: echo_silent choice exists")

# TC2: Acknowledge path applies +stats
func _test_tc2_acknowledge_effects() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	_assert(result.get("ok", false), "TC2: Dialogue file loads")
	if result.get("ok", false):
		var data = result["data"]
		var ack_node = data["nodes"].get("echo_acknowledge", {})
		var choices = ack_node.get("choices", [])
		var has_effects = false
		for c in choices:
			var effects = c.get("effects", [])
			for e in effects:
				if e.get("type") == "slider_delta" and e.get("axis") == "hope":
					has_effects = true
		_assert(has_effects, "TC2: echo_acknowledge has slider_delta effects")

# TC3: Deny path applies -stats
func _test_tc3_deny_effects() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	_assert(result.get("ok", false), "TC3: Dialogue file loads")
	if result.get("ok", false):
		var data = result["data"]
		var deny_node = data["nodes"].get("echo_deny", {})
		var choices = deny_node.get("choices", [])
		var has_negative = false
		for c in choices:
			var effects = c.get("effects", [])
			for e in effects:
				if e.get("type") == "slider_delta" and e.get("delta", 0) < 0:
					has_negative = true
		_assert(has_negative, "TC3: echo_deny has negative slider_delta effects")

# TC4: Silent path is neutral
func _test_tc4_silent_neutral() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	_assert(result.get("ok", false), "TC4: Dialogue file loads")
	if result.get("ok", false):
		var data = result["data"]
		var silent_node = data["nodes"].get("echo_silent", {})
		var choices = silent_node.get("choices", [])
		var has_effects = false
		for c in choices:
			if not c.get("effects", []).is_empty():
				has_effects = true
		_assert(not has_effects, "TC4: echo_silent has no effects (neutral)")

# =====================================================================
# AC2: Middle Layer (TC5-TC10)
# =====================================================================

# TC5: screensaver_echo_heard variant exists and has condition
func _test_tc5_screensaver_variant() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if result.get("ok", false):
		var data = result["data"]
		var nodes = data["nodes"]
		# Check all 3 screensaver_echo variants exist with correct conditions
		for node_id in ["echo_acknowledge_echo", "echo_deny_echo", "echo_silent_echo"]:
			var node = nodes.get(node_id, {})
			var cond = node.get("condition", {})
			var is_screensaver = (cond.get("type") == "flag" and cond.get("flag") == "screensaver_echo_heard")
			_assert(is_screensaver, "TC5: %s has screensaver_echo_heard condition" % node_id)

# TC6: Low conviction variant shown (conviction <= 3)
func _test_tc6_low_conviction_variant() -> void:
	var state = {"sliders": {"conviction": 2.0, "hope": 5.0, "will": 5.0}, "flags": {}}
	var cond = {"type": "slider", "axis": "conviction", "op": "lte", "value": 3.0}
	var result = DialogueConditionEvaluatorScript.evaluate(cond, state)
	_assert(result == true, "TC6: conviction 2.0 <= 3.0 evaluates to true")

# TC7: High hope variant (hope >= 9)
func _test_tc7_high_hope_variant() -> void:
	var state = {"sliders": {"hope": 9.0, "conviction": 5.0, "will": 5.0}, "flags": {}}
	var cond = {"type": "or", "conditions": [
		{"type": "slider", "axis": "hope", "op": "gte", "value": 9},
		{"type": "flag", "flag": "underpass_hope_high", "value": true}
	]}
	var result = DialogueConditionEvaluatorScript.evaluate(cond, state)
	_assert(result == true, "TC7: hope=9.0 => high hope OR condition true via slider")
	
	# Also test via flag
	var state2 = {"sliders": {"hope": 5.0, "conviction": 5.0, "will": 5.0}, "flags": {"underpass_hope_high": true}}
	var result2 = DialogueConditionEvaluatorScript.evaluate(cond, state2)
	_assert(result2 == true, "TC7: underpass_hope_high flag => OR condition true via flag")
	
	# Test false case
	var state3 = {"sliders": {"hope": 5.0, "conviction": 5.0, "will": 5.0}, "flags": {}}
	var result3 = DialogueConditionEvaluatorScript.evaluate(cond, state3)
	_assert(result3 == false, "TC7: hope=5.0, no flag => condition false")

# TC8: Low hope variant (hope <= 2)
func _test_tc8_low_hope_variant() -> void:
	var state = {"sliders": {"hope": 1.0, "conviction": 5.0, "will": 5.0}, "flags": {}}
	var cond = {"type": "or", "conditions": [
		{"type": "slider", "axis": "hope", "op": "lte", "value": 2},
		{"type": "flag", "flag": "underpass_hope_low", "value": true}
	]}
	var result = DialogueConditionEvaluatorScript.evaluate(cond, state)
	_assert(result == true, "TC8: hope=1.0 => low hope OR condition true via slider")

# TC9: Office sigh flag triggers cross-reference
func _test_tc9_office_flag_cross_reference() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if result.get("ok", false):
		var data = result["data"]
		var nodes = data["nodes"]
		
		# Check echo_office_sigh exists with correct condition
		var sigh_node = nodes.get("echo_office_sigh", {})
		var sigh_cond = sigh_node.get("condition", {})
		_assert(sigh_cond.get("type") == "flag" and sigh_cond.get("flag") == "office_exit_sigh", "TC9: echo_office_sigh has office_exit_sigh condition")
		
		# Check echo_office_determined exists with correct condition
		var det_node = nodes.get("echo_office_determined", {})
		var det_cond = det_node.get("condition", {})
		_assert(det_cond.get("type") == "flag" and det_cond.get("flag") == "office_exit_determined", "TC9: echo_office_determined has office_exit_determined condition")

# TC10: Multiple conditions combine correctly
func _test_tc10_multiple_combine_priority() -> void:
	# Test OR condition evaluation
	var state = {"sliders": {"hope": 9.0, "conviction": 2.0, "will": 5.0}, "flags": {"screensaver_echo_heard": true}}
	
	# Screensaver condition
	var screen_cond = {"type": "flag", "flag": "screensaver_echo_heard", "value": true}
	var screen_result = DialogueConditionEvaluatorScript.evaluate(screen_cond, state)
	_assert(screen_result == true, "TC10: screensaver flag condition evaluates to true")
	
	# Low conviction condition
	var conv_cond = {"type": "slider", "axis": "conviction", "op": "lte", "value": 3.0}
	var conv_result = DialogueConditionEvaluatorScript.evaluate(conv_cond, state)
	_assert(conv_result == true, "TC10: low conviction condition also true")

# =====================================================================
# AC3: Deep Layer (TC11-TC14)
# =====================================================================

# TC11: is_new_game_plus flag unlocks meta entry
func _test_tc11_is_new_game_plus_unlocks_meta() -> void:
	var condition = {"type": "flag", "flag": "is_new_game_plus", "value": true}
	
	# With flag set
	var state_meta = {"sliders": {"hope": 5.0, "conviction": 5.0, "will": 5.0}, "flags": {"is_new_game_plus": true}}
	var result = DialogueConditionEvaluatorScript.evaluate(condition, state_meta)
	_assert(result == true, "TC11: is_new_game_plus flag set => condition true")
	
	# Verify the dialogue file has the meta choice
	var parse_result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if parse_result.get("ok", false):
		var entry = parse_result["data"]["nodes"].get("echo_entry", {})
		var choices = entry.get("choices", [])
		var has_meta_choice = false
		for c in choices:
			if c.get("next_node") == "echo_meta_entry":
				has_meta_choice = true
		_assert(has_meta_choice, "TC11: echo_meta_entry choice exists in echo_entry")
		
		# Verify meta entry node exists
		_assert(parse_result["data"]["nodes"].has("echo_meta_entry"), "TC11: echo_meta_entry node exists")

# TC12: Meta reveal node shows "I am you"
func _test_tc12_meta_reveal_content() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		var reveal_node = nodes.get("echo_meta_reveal", {})
		var text = reveal_node.get("text", "")
		_assert(not text.is_empty(), "TC12: echo_meta_reveal has text")
		_assert(text.find("我") >= 0 or text.find("你") >= 0, "TC12: echo_meta_reveal text relates to self/player")

# TC13: Meta choice affects ending flags
func _test_tc13_meta_choice_affects_flags() -> void:
	var result = DialogueParserScript.load_dialogue("res://dialogues/underpass_stranger_echo.json")
	if result.get("ok", false):
		var nodes = result["data"]["nodes"]
		
		# Check meta_accept sets stranger_revealed
		var accept = nodes.get("echo_meta_accept", {})
		var accept_choices = accept.get("choices", [])
		var has_revealed = false
		for c in accept_choices:
			for e in c.get("effects", []):
				if e.get("type") == "set_flag" and e.get("flag") == "stranger_revealed":
					has_revealed = true
		_assert(has_revealed, "TC13: echo_meta_accept sets stranger_revealed flag")
		
		# Check meta_accept has stat bonuses
		var has_positive_stats = false
		for c in accept_choices:
			for e in c.get("effects", []):
				if e.get("type") == "slider_delta" and e.get("delta", 0) > 0:
					has_positive_stats = true
		_assert(has_positive_stats, "TC13: echo_meta_accept has positive stat changes")

# TC14: No deep layer on first playthrough (playthrough_count = 1)
func _test_tc14_no_deep_layer_first_playthrough() -> void:
	var condition = {"type": "flag", "flag": "is_new_game_plus", "value": true}
	var state = {"sliders": {"hope": 5.0, "conviction": 5.0, "will": 5.0}, "flags": {}}
	var result = DialogueConditionEvaluatorScript.evaluate(condition, state)
	_assert(result == false, "TC14: is_new_game_plus not set => condition false (no meta on first playthrough)")

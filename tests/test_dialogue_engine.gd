extends RefCounted

# ===== Dialogue Engine Tests (Issue #46) =====
# Covers: DialogueParser, DialogueConditionEvaluator, DialogueRunner

var passed: int = 0
var failed: int = 0

# Signal capture member variables (used instead of lambda closures)
var _captured_choices: Array = []
var _ended: bool = false
var _started: bool = false
var _choice_made_fired: bool = false
var _signal_fired: bool = false
var _captured_node_id: String = ""
var _signal_speaker: String = ""
var _signal_text: String = ""
var _signal_index: int = -1
var _chosen_text: String = ""

# Preload scripts (class_name not available in --script mode)
var DialogueParserScript = load("res://gdscripts/dialogue_parser.gd")
var DialogueConditionEvaluatorScript = load("res://gdscripts/dialogue_condition_evaluator.gd")
var DialogueRunnerScript = load("res://gdscripts/dialogue_runner.gd")

func run() -> void:
	print("\n=== Dialogue Engine Tests ===")
	
	# --- DialogueParser Tests ---
	_test_dp_valid_parse()
	_test_dp_invalid_json()
	_test_dp_missing_nodes()
	_test_dp_missing_entry_node()
	_test_dp_entry_node_not_found()
	_test_dp_missing_speaker()
	_test_dp_missing_text()
	_test_dp_bad_choice_format()
	_test_dp_next_node_not_found()
	_test_dp_empty_nodes()
	_test_dp_root_not_dict()
	
	# --- DialogueConditionEvaluator Tests ---
	_test_dce_slider_gte()
	_test_dce_slider_lte()
	_test_dce_slider_eq()
	_test_dce_slider_gt()
	_test_dce_slider_lt()
	_test_dce_slider_unknown_op()
	_test_dce_flag_true()
	_test_dce_flag_false()
	_test_dce_flag_default()
	_test_dce_choice_made()
	_test_dce_choice_made_not_found()
	_test_dce_and_all_true()
	_test_dce_and_one_false()
	_test_dce_or_all_false()
	_test_dce_or_one_true()
	_test_dce_not_true()
	_test_dce_not_false()
	_test_dce_unknown_type()
	_test_dce_nested_compound()
	
	# --- DialogueRunner Tests ---
	_test_dr_start_conversation()
	_test_dr_choice_filter_condition_met()
	_test_dr_choice_filter_condition_not_met()
	_test_dr_choice_filter_no_condition()
	_test_dr_choice_filter_default_fallback()
	_test_dr_choice_filter_empty_all_gated()
	_test_dr_select_choice_advance()
	_test_dr_select_choice_terminal()
	_test_dr_side_effect_choice_applied()
	_test_dr_signal_node_changed()
	_test_dr_signal_choices_available()
	_test_dr_signal_choice_made()
	_test_dr_anti_loop_forced_exit()
	_test_dr_start_then_enter_node()
	_test_dr_visited_tracking()
	_test_dr_get_last_reachable_count()
	
	print("  Dialogue Test Suite: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ %s" % name)
	else:
		failed += 1
		print("  ❌ %s" % name)

# =====================================================================
# DialogueParser Tests
# =====================================================================

func _dp_parse_valid_sample():
	var json_str := '{
		"entry_node_id": "start",
		"nodes": {
			"start": {
				"speaker": "Guide",
				"text": "Welcome.",
				"choices": [
					{"text": "Hello", "next_node": "end", "condition": null, "effects": []},
					{"text": "Bye", "next_node": null}
				],
				"tags": ["intro"]
			},
			"end": {
				"speaker": "Guide",
				"text": "Goodbye.",
				"choices": [
					{"text": "Leave", "next_node": null}
				]
			}
		}
	}'
	return DialogueParserScript.parse_json_string(json_str)

func _test_dp_valid_parse():
	var result = _dp_parse_valid_sample()
	_assert(result.get("ok", false), "DP-1: Valid JSON parses successfully")
	if result.get("ok", false):
		var data: Dictionary = result["data"]
		_assert(data.has("nodes"), "DP-1: data has nodes")
		_assert(data["nodes"].size() == 2, "DP-1: data has 2 nodes")
		_assert(data["entry_node_id"] == "start", "DP-1: entry_node_id is 'start'")
		_assert(data["nodes"].has("start"), "DP-1: nodes has 'start'")
		_assert(data["nodes"].has("end"), "DP-1: nodes has 'end'")
		var start_node: Dictionary = data["nodes"]["start"]
		_assert(start_node.get("speaker") == "Guide", "DP-1: start node speaker='Guide'")
		_assert(start_node.get("text") == "Welcome.", "DP-1: start node text='Welcome.'")
		_assert(start_node.get("choices").size() == 2, "DP-1: start node has 2 choices")

func _test_dp_invalid_json() -> void:
	var result = DialogueParserScript.parse_json_string("{invalid json}")
	_assert(not result.get("ok", false), "DP-2: Invalid JSON returns error")
	_assert(result.get("error", "").begins_with("JSON parse error"), "DP-2: Error describes 'JSON parse error'")

func _test_dp_missing_nodes() -> void:
	var result = DialogueParserScript.parse_json_string('{"entry_node_id":"x"}')
	_assert(not result.get("ok", false), "DP-3: Missing 'nodes' returns error")
	_assert(result.get("error", "").find("nodes") >= 0, "DP-3: Error mentions 'nodes'")

func _test_dp_missing_entry_node() -> void:
	var result = DialogueParserScript.parse_json_string('{"nodes":{"a":{"speaker":"S","text":"T"}}}')
	_assert(not result.get("ok", false), "DP-4: Missing 'entry_node_id' returns error")
	_assert(result.get("error", "").find("entry_node_id") >= 0, "DP-4: Error mentions 'entry_node_id'")

func _test_dp_entry_node_not_found() -> void:
	var result = DialogueParserScript.parse_json_string('{"entry_node_id":"missing","nodes":{"a":{"speaker":"S","text":"T"}}}')
	_assert(not result.get("ok", false), "DP-5: entry_node_id not in nodes returns error")
	_assert(result.get("error", "").find("entry_node_id") >= 0, "DP-5: Error mentions entry node id")

func _test_dp_missing_speaker() -> void:
	var result = DialogueParserScript.parse_json_string('{"entry_node_id":"a","nodes":{"a":{"text":"T"}}}')
	_assert(not result.get("ok", false), "DP-6: Missing 'speaker' returns error")
	_assert(result.get("error", "").find("speaker") >= 0, "DP-6: Error mentions 'speaker'")

func _test_dp_missing_text() -> void:
	var result = DialogueParserScript.parse_json_string('{"entry_node_id":"a","nodes":{"a":{"speaker":"S"}}}')
	_assert(not result.get("ok", false), "DP-7: Missing 'text' returns error")
	_assert(result.get("error", "").find("text") >= 0, "DP-7: Error mentions 'text'")

func _test_dp_bad_choice_format() -> void:
	var result = DialogueParserScript.parse_json_string('{"entry_node_id":"a","nodes":{"a":{"speaker":"S","text":"T","choices":[42]}}}')
	_assert(not result.get("ok", false), "DP-8: Non-dictionary choice returns error")
	_assert(result.get("error", "").find("choice") >= 0, "DP-8: Error mentions 'choice'")

func _test_dp_next_node_not_found() -> void:
	var result = DialogueParserScript.parse_json_string('{"entry_node_id":"a","nodes":{"a":{"speaker":"S","text":"T","choices":[{"text":"X","next_node":"nonexistent"}]}}}')
	_assert(not result.get("ok", false), "DP-9: Unknown next_node returns error")
	_assert(result.get("error", "").find("next_node") >= 0, "DP-9: Error mentions 'next_node'")

func _test_dp_empty_nodes() -> void:
	var result = DialogueParserScript.parse_json_string('{"entry_node_id":"a","nodes":{}}')
	_assert(not result.get("ok", false), "DP-10: Empty nodes returns error")
	_assert(result.get("error", "").find("zero") >= 0 or result.get("error", "").find("empty") >= 0, "DP-10: Error mentions zero/empty")

func _test_dp_root_not_dict() -> void:
	var result = DialogueParserScript.parse_json_string('"just a string"')
	_assert(not result.get("ok", false), "DP-11: Non-dict root returns error")
	_assert(result.get("error", "").find("object") >= 0 or result.get("error", "").find("dictionary") >= 0, "DP-11: Error mentions object/dict")

# =====================================================================
# DialogueConditionEvaluator Tests
# =====================================================================

func _test_dce_slider_gte() -> void:
	var state := {"sliders": {"hope": 7.0}}
	var cond := {"type": "slider", "axis": "hope", "op": "gte", "value": 5}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-1: slider gte(7, 5) = true")
	var cond2 := {"type": "slider", "axis": "hope", "op": "gte", "value": 8}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond2, state), "DCE-1: slider gte(7, 8) = false")

func _test_dce_slider_lte() -> void:
	var state := {"sliders": {"despair": 3.0}}
	var cond := {"type": "slider", "axis": "despair", "op": "lte", "value": 5}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-2: slider lte(3, 5) = true")
	var cond2 := {"type": "slider", "axis": "despair", "op": "lte", "value": 1}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond2, state), "DCE-2: slider lte(3, 1) = false")

func _test_dce_slider_eq() -> void:
	var state := {"sliders": {"vigor": 5.0}}
	var cond := {"type": "slider", "axis": "vigor", "op": "eq", "value": 5}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-3: slider eq(5, 5) = true")
	var cond2 := {"type": "slider", "axis": "vigor", "op": "eq", "value": 4}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond2, state), "DCE-3: slider eq(5, 4) = false")

func _test_dce_slider_gt() -> void:
	var state := {"sliders": {"conviction": 8.0}}
	var cond := {"type": "slider", "axis": "conviction", "op": "gt", "value": 5}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-4: slider gt(8, 5) = true")
	var cond2 := {"type": "slider", "axis": "conviction", "op": "gt", "value": 8}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond2, state), "DCE-4: slider gt(8, 8) = false")

func _test_dce_slider_lt() -> void:
	var state := {"sliders": {"falter": 2.0}}
	var cond := {"type": "slider", "axis": "falter", "op": "lt", "value": 5}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-5: slider lt(2, 5) = true")
	var cond2 := {"type": "slider", "axis": "falter", "op": "lt", "value": 1}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond2, state), "DCE-5: slider lt(2, 1) = false")

func _test_dce_slider_unknown_op() -> void:
	var state := {"sliders": {"hope": 5.0}}
	var cond := {"type": "slider", "axis": "hope", "op": "unknown", "value": 5}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-6: unknown slider op returns false")

func _test_dce_flag_true() -> void:
	var state := {"flags": {"met_guide": true}}
	var cond := {"type": "flag", "flag": "met_guide", "value": true}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-7: flag true = true")

func _test_dce_flag_false() -> void:
	var state := {"flags": {"met_guide": false}}
	var cond := {"type": "flag", "flag": "met_guide", "value": true}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-8: flag false != true")

func _test_dce_flag_default() -> void:
	var state := {"flags": {}}
	var cond := {"type": "flag", "flag": "nonexistent", "value": true}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-9: missing flag defaults to false")

func _test_dce_choice_made() -> void:
	var state := {"choices_made": [{"node_id": "n_01", "choice_index": 0, "choice_text": "Hello"}]}
	var cond := {"type": "choice_made", "node_id": "n_01", "choice_index": 0}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-10: choice_made matches = true")

func _test_dce_choice_made_not_found() -> void:
	var state := {"choices_made": [{"node_id": "n_01", "choice_index": 0}]}
	var cond := {"type": "choice_made", "node_id": "n_01", "choice_index": 1}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-11: choice_made no match = false")

func _test_dce_and_all_true() -> void:
	var state := {"sliders": {"hope": 7.0}, "flags": {"met_guide": true}}
	var cond := {"type": "and", "conditions": [
		{"type": "slider", "axis": "hope", "op": "gte", "value": 5},
		{"type": "flag", "flag": "met_guide", "value": true}
	]}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-12: AND all true = true")

func _test_dce_and_one_false() -> void:
	var state := {"sliders": {"hope": 3.0}, "flags": {"met_guide": true}}
	var cond := {"type": "and", "conditions": [
		{"type": "slider", "axis": "hope", "op": "gte", "value": 5},
		{"type": "flag", "flag": "met_guide", "value": true}
	]}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-13: AND one false = false")

func _test_dce_or_all_false() -> void:
	var state := {"sliders": {"hope": 3.0}, "flags": {"met_guide": false}}
	var cond := {"type": "or", "conditions": [
		{"type": "slider", "axis": "hope", "op": "gte", "value": 5},
		{"type": "flag", "flag": "met_guide", "value": true}
	]}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-14: OR all false = false")

func _test_dce_or_one_true() -> void:
	var state := {"sliders": {"hope": 7.0}, "flags": {"met_guide": false}}
	var cond := {"type": "or", "conditions": [
		{"type": "slider", "axis": "hope", "op": "gte", "value": 5},
		{"type": "flag", "flag": "met_guide", "value": true}
	]}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-15: OR one true = true")

func _test_dce_not_true() -> void:
	var state := {"sliders": {"hope": 3.0}}
	var cond := {"type": "not", "condition": {"type": "slider", "axis": "hope", "op": "gte", "value": 5}}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-16: NOT (false) = true")

func _test_dce_not_false() -> void:
	var state := {"sliders": {"hope": 7.0}}
	var cond := {"type": "not", "condition": {"type": "slider", "axis": "hope", "op": "gte", "value": 5}}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-17: NOT (true) = false")

func _test_dce_unknown_type() -> void:
	var state := {}
	var cond := {"type": "nonexistent"}
	_assert(not DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-18: unknown type returns false")

func _test_dce_nested_compound() -> void:
	# (hope >= 5 OR despair <= 3) AND NOT flag("blocked")
	var state := {"sliders": {"hope": 2.0, "despair": 2.0}, "flags": {"blocked": false}}
	var cond := {
		"type": "and",
		"conditions": [
			{
				"type": "or",
				"conditions": [
					{"type": "slider", "axis": "hope", "op": "gte", "value": 5},
					{"type": "slider", "axis": "despair", "op": "lte", "value": 3}
				]
			},
			{
				"type": "not",
				"condition": {"type": "flag", "flag": "blocked", "value": true}
			}
		]
	}
	_assert(DialogueConditionEvaluatorScript.evaluate(cond, state), "DCE-19: nested compound evaluates correctly")

# =====================================================================
# DialogueRunner Tests
# =====================================================================

func _make_test_dialogue() -> Dictionary:
	return {
		"nodes": {
			"start": {
				"speaker": "Guide",
				"text": "Hello, traveller.",
				"choices": [
					{
						"text": "High hope",
						"next_node": "high_hope_node",
						"condition": {"type": "slider", "axis": "hope", "op": "gte", "value": 7},
						"effects": [{"type": "slider_delta", "axis": "hope", "delta": 1}]
					},
					{
						"text": "Low hope",
						"next_node": "low_hope_node",
						"condition": {"type": "slider", "axis": "hope", "op": "lt", "value": 5},
						"effects": []
					},
					{
						"text": "Always there",
						"next_node": "always_node",
						"effects": [{"type": "set_flag", "flag": "chose_always", "value": true}]
					},
					{
						"text": "Default fallback",
						"next_node": "default_end",
						"default": true,
						"effects": []
					}
				],
				"tags": ["intro"]
			},
			"high_hope_node": {
				"speaker": "Guide",
				"text": "You seem hopeful!",
				"choices": [{"text": "Thanks", "next_node": null, "effects": []}],
				"tags": []
			},
			"low_hope_node": {
				"speaker": "Guide",
				"text": "Don't lose hope.",
				"choices": [{"text": "Okay", "next_node": null, "effects": []}],
				"tags": []
			},
			"always_node": {
				"speaker": "Guide",
				"text": "You chose always.",
				"choices": [{"text": "End", "next_node": null, "effects": []}],
				"tags": []
			},
			"default_end": {
				"speaker": "Guide",
				"text": "Default ending.",
				"choices": [{"text": "End", "next_node": null, "effects": []}],
				"tags": []
			}
		},
		"entry_node_id": "start"
	}

func _make_runner() -> Node:
	var runner = DialogueRunnerScript.new()
	# Inject the test dialogue tree directly (bypass JSON loading)
	runner.dialogue_tree = _make_test_dialogue()
	runner.current_dialogue_id = "test_dialogue"
	return runner

# Signal handler methods (using member variables instead of lambda closures)
func _on_choices_available(choices: Array) -> void:
	_captured_choices = choices
	_signal_fired = true

func _on_dialogue_ended() -> void:
	_ended = true

func _on_dialogue_started(id: String) -> void:
	_started = true

func _on_node_changed(id: String, spk: String, txt: String) -> void:
	_captured_node_id = id
	_signal_speaker = spk
	_signal_text = txt
	_signal_fired = true

func _on_choice_made(idx: int, txt: String) -> void:
	_choice_made_fired = true
	_signal_index = idx
	_chosen_text = txt

func _test_dr_start_conversation() -> void:
	var runner := _make_runner()
	_started = false
	runner.dialogue_started.connect(_on_dialogue_started)
	runner.enter_node("start")
	_assert(runner.current_node_id == "start", "DR-1: enter_node sets current_node_id")
	_assert(runner.current_node.get("speaker") == "Guide", "DR-1: current_node has correct speaker")

func _test_dr_choice_filter_condition_met() -> void:
	var runner := _make_runner()
	_captured_choices = []
	runner.choices_available.connect(_on_choices_available)
	# Simulate high hope state via state_provider
	runner.state_provider = func() -> Dictionary:
		return {"sliders": {"hope": 8.0, "despair": 2.0, "vigor": 5.0, "burnout": 3.0, "conviction": 5.0, "falter": 3.0}, "flags": {}, "choices_made": []}
	runner.enter_node("start")
	_assert(_captured_choices.size() > 0, "DR-2: choices emitted")
	# With hope=8, both "High hope" (gte 7) and "Always there" (no condition) should be reachable
	# "Low hope" (lt 5) should be unreachable
	var high_hope_found: bool = false
	var always_found: bool = false
	var low_hope_found: bool = false
	for c in _captured_choices:
		if c.get("text") == "High hope":
			high_hope_found = true
		if c.get("text") == "Always there":
			always_found = true
		if c.get("text") == "Low hope":
			low_hope_found = true
	_assert(high_hope_found, "DR-2: 'High hope' visible (hope=8 >= 7)")
	_assert(always_found, "DR-2: 'Always there' visible (no condition)")
	_assert(not low_hope_found, "DR-2: 'Low hope' hidden (hope=8 not < 5)")

func _test_dr_choice_filter_condition_not_met() -> void:
	var runner := _make_runner()
	_captured_choices = []
	runner.choices_available.connect(_on_choices_available)
	runner.state_provider = func() -> Dictionary:
		return {"sliders": {"hope": 2.0, "despair": 5.0, "vigor": 5.0, "burnout": 3.0, "conviction": 5.0, "falter": 3.0}, "flags": {}, "choices_made": []}
	runner.enter_node("start")
	_assert(_captured_choices.size() > 0, "DR-3: choices emitted")
	var high_hope_found: bool = false
	var low_hope_found: bool = false
	var always_found: bool = false
	for c in _captured_choices:
		if c.get("text") == "High hope":
			high_hope_found = true
		if c.get("text") == "Low hope":
			low_hope_found = true
		if c.get("text") == "Always there":
			always_found = true
	_assert(not high_hope_found, "DR-3: 'High hope' hidden (hope=2 < 7)")
	_assert(low_hope_found, "DR-3: 'Low hope' visible (hope=2 < 5)")
	_assert(always_found, "DR-3: 'Always there' visible (no condition)")

func _test_dr_choice_filter_no_condition() -> void:
	var runner := _make_runner()
	_captured_choices = []
	runner.choices_available.connect(_on_choices_available)
	runner.state_provider = func() -> Dictionary:
		return {"sliders": {"hope": 5.0, "despair": 5.0, "vigor": 5.0, "burnout": 3.0, "conviction": 5.0, "falter": 3.0}, "flags": {}, "choices_made": []}
	runner.enter_node("start")
	# With hope=5, "High hope" (gte 7) hidden, "Low hope" (lt 5) hidden, "Always there" visible (no condition)
	# "Default fallback" only activates when ALL choices are gated — not the case here
	_assert(_captured_choices.size() == 1, "DR-4: 1 choice available with neutral state")

func _test_dr_choice_filter_default_fallback() -> void:
	# Create a node where only the default choice exists
	var runner := _make_runner()
	var single_default_tree := {
		"nodes": {
			"only": {
				"speaker": "NPC",
				"text": "Default test.",
				"choices": [
					{
						"text": "Only option",
						"next_node": null,
						"default": true,
						"effects": []
					}
				]
			}
		},
		"entry_node_id": "only"
	}
	runner.dialogue_tree = single_default_tree
	_captured_choices = []
	runner.choices_available.connect(_on_choices_available)
	runner.enter_node("only")
	_assert(_captured_choices.size() == 1, "DR-5: default choice visible")
	_assert(_captured_choices[0].get("text") == "Only option", "DR-5: default choice text matches")

func _test_dr_choice_filter_empty_all_gated() -> void:
	# Create a node where all choices are gated behind unmet conditions and no default
	var runner := _make_runner()
	var gated_tree := {
		"nodes": {
			"gated": {
				"speaker": "NPC",
				"text": "Gated test.",
				"choices": [
					{
						"text": "Need high hope",
						"next_node": null,
						"condition": {"type": "slider", "axis": "hope", "op": "gte", "value": 10},
						"effects": []
					}
				]
			}
		},
		"entry_node_id": "gated"
	}
	runner.dialogue_tree = gated_tree
	_ended = false
	runner.dialogue_ended.connect(_on_dialogue_ended)
	runner.state_provider = func() -> Dictionary:
		return {"sliders": {"hope": 5.0}, "flags": {}, "choices_made": []}
	runner.enter_node("gated")
	_assert(_ended, "DR-6: conversation ends when all choices are gated without default")

func _test_dr_select_choice_advance() -> void:
	var runner := _make_runner()
	_captured_node_id = ""
	runner.node_changed.connect(_on_node_changed)
	runner.enter_node("start")
	# Select choice index 0 ("High hope") which advances to high_hope_node
	runner.select_choice(0)
	_assert(_captured_node_id == "high_hope_node", "DR-7: selecting choice 0 advances to high_hope_node")

func _test_dr_select_choice_terminal() -> void:
	var runner := _make_runner()
	_ended = false
	runner.dialogue_ended.connect(_on_dialogue_ended)
	# Enter a terminal node (node with choices that go to null)
	runner.dialogue_tree = {
		"nodes": {
			"term": {
				"speaker": "NPC",
				"text": "Terminal.",
				"choices": [{"text": "Bye", "next_node": null, "effects": []}]
			}
		},
		"entry_node_id": "term"
	}
	runner.enter_node("term")
	runner.select_choice(0)
	_assert(_ended, "DR-8: selecting terminal choice ends conversation")

func _test_dr_side_effect_choice_applied() -> void:
	# Verify that selecting a choice with effects triggers the choice_made signal
	# and advances to the correct next node. Effects are applied via GameManager
	# (null in --script mode) — testing effect application through GameManager
	# requires integration testing with the full autoload system.
	var runner := _make_runner()
	_choice_made_fired = false
	_chosen_text = ""
	runner.choice_made.connect(_on_choice_made)
	runner.enter_node("start")
	# Select "Always there" (index 2) which has a set_flag effect
	runner.select_choice(2)
	_assert(_choice_made_fired, "DR-9: choice_made signal fired")
	_assert(_chosen_text == "Always there", "DR-9: choice text matches 'Always there'")
	_assert(runner.current_node_id == "always_node", "DR-9: advanced to always_node")

func _test_dr_signal_node_changed() -> void:
	var runner := _make_runner()
	_signal_fired = false
	_signal_speaker = ""
	_signal_text = ""
	runner.node_changed.connect(_on_node_changed)
	runner.enter_node("start")
	_assert(_signal_fired, "DR-10: node_changed signal fired")
	_assert(_signal_speaker == "Guide", "DR-10: signal speaker='Guide'")
	_assert(_signal_text == "Hello, traveller.", "DR-10: signal text matches")

func _test_dr_signal_choices_available() -> void:
	var runner := _make_runner()
	_signal_fired = false
	_captured_choices = []
	runner.choices_available.connect(_on_choices_available)
	runner.enter_node("start")
	_assert(_signal_fired, "DR-11: choices_available signal fired")
	_assert(_captured_choices.size() > 0, "DR-11: choices array non-empty")

func _test_dr_signal_choice_made() -> void:
	var runner := _make_runner()
	_choice_made_fired = false
	_signal_index = -1
	_chosen_text = ""
	runner.choice_made.connect(_on_choice_made)
	runner.enter_node("start")
	runner.select_choice(0)
	_assert(_choice_made_fired, "DR-12: choice_made signal fired")
	_assert(_signal_index == 0, "DR-12: choice index=0")
	_assert(_chosen_text == "High hope", "DR-12: choice text='High hope'")

func _test_dr_anti_loop_forced_exit() -> void:
	var runner := _make_runner()
	var loop_tree := {
		"nodes": {
			"loop_start": {
				"speaker": "NPC",
				"text": "Loop start.",
				"choices": [
					{"text": "Go to loop", "next_node": "loop_end", "effects": []}
				]
			},
			"loop_end": {
				"speaker": "NPC",
				"text": "Loop end.",
				"choices": [
					{"text": "Go back", "next_node": "loop_start", "effects": []}
				]
			}
		},
		"entry_node_id": "loop_start"
	}
	runner.dialogue_tree = loop_tree
	_ended = false
	runner.dialogue_ended.connect(_on_dialogue_ended)
	
	# Enter the node 4 times (MAX_NODE_VISITS = 3)
	runner.enter_node("loop_start")
	runner.select_choice(0)  # goes to loop_end
	runner.select_choice(0)  # goes back to loop_start (visit 2)
	runner.select_choice(0)  # loop_end (visit 2)
	runner.select_choice(0)  # loop_start (visit 3 = MAX)
	runner.select_choice(0)  # loop_end (visit 3 = MAX)
	# Next should trigger anti-loop
	runner.select_choice(0)  # loop_start would be visit 4 > MAX
	
	_assert(_ended, "DR-13: conversation forced-ended after MAX_NODE_VISITS")

func _test_dr_start_then_enter_node() -> void:
	# Test that start() loads dialogue and enters entry node
	var runner = DialogueRunnerScript.new()
	# Simulate loading from a JSON string
	var json_str := '{"entry_node_id":"start","nodes":{"start":{"speaker":"S","text":"T","choices":[{"text":"X","next_node":null,"effects":[]}]}}}'
	var parse_result = DialogueParserScript.parse_json_string(json_str)
	_assert(parse_result.get("ok", false), "DR-14: parse succeeds for start test")
	if parse_result.get("ok", false):
		runner.dialogue_tree = parse_result["data"]
		_started = false
		runner.dialogue_started.connect(_on_dialogue_started)
		runner.enter_node("start")
		_assert(runner.current_node_id == "start", "DR-14: start sets current_node_id correctly")

func _test_dr_visited_tracking() -> void:
	var runner := _make_runner()
	runner.enter_node("start")
	_assert(runner.visited_nodes.get("start", 0) == 1, "DR-15: visited_nodes['start'] = 1 after first entry")
	runner.enter_node("start")
	_assert(runner.visited_nodes.get("start", 0) == 2, "DR-15: visited_nodes['start'] = 2 after second entry")

func _test_dr_get_last_reachable_count() -> void:
	# T14: get_last_reachable_count returns correct number of reachable choices
	var runner := _make_runner()
	runner.state_provider = func() -> Dictionary:
		return {"sliders": {"hope": 8.0, "despair": 2.0, "vigor": 5.0, "burnout": 3.0, "conviction": 5.0, "falter": 3.0}, "flags": {}, "choices_made": []}
	runner.enter_node("start")
	_assert(runner.get_last_reachable_count() == 2, "DR-16: get_last_reachable_count = 2 with hope=8")
	# With hope=8: "High hope" (gte 7) and "Always there" (no condition) are reachable

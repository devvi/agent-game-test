extends Node
class_name DialogueRunner

signal dialogue_started(dialogue_id: String)
signal dialogue_ended()
signal node_changed(node_id: String, speaker: String, text: String)
signal choices_available(choices: Array)     # Array[Dictionary] — filtered, reachable choices
signal choice_made(choice_index: int, choice_text: String)

## Preload script dependencies (avoids class_name resolution issues in --script mode).
const _DialogueParser := preload("res://gdscripts/dialogue_parser.gd")
const _DialogueConditionEvaluator := preload("res://gdscripts/dialogue_condition_evaluator.gd")

## Maximum times a node can be visited before forced exit (anti-loop).
const MAX_NODE_VISITS: int = 3

## Optional callable for injecting custom state in tests.
## Takes no arguments, returns a Dictionary with "sliders"/"flags"/"choices_made" keys.
## If set, used by _build_state_snapshot instead of querying GameManager.
var state_provider: Callable = Callable()

var current_dialogue_id: String = ""
var current_node_id: String = ""
var current_node: Dictionary = {}
var dialogue_tree: Dictionary = {}   # result from DialogueParser
var visited_nodes: Dictionary = {}   # node_id → visit_count
var choices_made: Array = []         # [ {node_id, choice_index, choice_text}, ... ]
var _last_reachable_count: int = 0  # Track last reachable choice count for debug overlay

## Load a dialogue by its file path (lazy-load).
## Returns true on successful load, false on error.
func load_dialogue(file_path: String, dialogue_id: String = "") -> bool:
	var result := _DialogueParser.load_dialogue(file_path)
	if not result.get("ok", false):
		push_error("Dialogue load failed: ", result.get("error", "unknown"))
		return false
	dialogue_tree = result["data"]
	current_dialogue_id = dialogue_id
	visited_nodes.clear()
	choices_made.clear()
	return true


## Enter a node by ID. Evaluates conditions, presents choices.
func enter_node(node_id: String) -> void:
	if not dialogue_tree.has("nodes"):
		push_error("No dialogue tree loaded")
		_end_conversation()
		return

	var nodes: Dictionary = dialogue_tree["nodes"]
	if not nodes.has(node_id):
		push_error("Node not found: ", node_id)
		_end_conversation()
		return

	# Apply on_enter effects (if any)
	var node: Dictionary = nodes[node_id]
	if node.has("on_enter"):
		_apply_effects(node["on_enter"])

	# Track visits (anti-loop)
	var visits: int = visited_nodes.get(node_id, 0) + 1
	visited_nodes[node_id] = visits
	if visits > MAX_NODE_VISITS:
		push_warning("Node '%s' visited %d times — force ending conversation" % [node_id, visits])
		_end_conversation()
		return

	current_node_id = node_id
	current_node = node

	# Build GameState snapshot for condition evaluation
	var state := _build_state_snapshot()

	# Filter choices by condition
	var raw_choices: Array = node.get("choices", [])
	var reachable: Array = []
	var default_choice: Dictionary = {}

	for c in raw_choices:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		if c.get("default", false):
			default_choice = c
			continue
		if c.has("condition"):
			var cond: Variant = c["condition"]
			if typeof(cond) == TYPE_DICTIONARY and not cond.is_empty():
				if _DialogueConditionEvaluator.evaluate(cond, state):
					reachable.append(c)
			else:
				# null or empty condition means always available
				reachable.append(c)
		else:
			reachable.append(c)

	# Fallback: if no choices reachable and a default exists, use default
	if reachable.is_empty() and not default_choice.is_empty():
		reachable = [default_choice]
	elif reachable.is_empty():
		# No choices available at all — end conversation gracefully
		push_warning("Node '%s' has no reachable choices — ending conversation" % node_id)
		_end_conversation()
		return

	node_changed.emit(node_id, node.get("speaker", ""), node.get("text", ""))
	choices_available.emit(reachable)
	_last_reachable_count = reachable.size()


## Called when player selects a choice.
func select_choice(choice_index: int) -> void:
	var choices: Array = current_node.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		push_error("Choice index out of range: %d" % choice_index)
		return

	var choice: Dictionary = choices[choice_index]
	var choice_text: String = choice.get("text", "")

	# Record choice
	choices_made.append({
		"node_id": current_node_id,
		"choice_index": choice_index,
		"choice_text": choice_text
	})

	# Apply side effects
	if choice.has("effects"):
		_apply_effects(choice["effects"])

	choice_made.emit(choice_index, choice_text)

	# Advance to next node or end
	if choice.has("next_node") and choice["next_node"] != null and str(choice["next_node"]) != "":
		enter_node(choice["next_node"])
	else:
		_end_conversation()


## Start conversation from the entry node of a loaded dialogue.
func start(dialogue_file_path: String, dialogue_id: String = "", entry_override: String = "") -> bool:
	if not load_dialogue(dialogue_file_path, dialogue_id):
		return false
	dialogue_started.emit(current_dialogue_id)
	var entry: String = entry_override if not entry_override.is_empty() else dialogue_tree.get("entry_node_id", "")
	enter_node(entry)
	return true


## Check if any terminal nodes (choices all lead to null/empty next_node) remain unvisited.
func has_unvisited_branches(dialogue_id: String) -> bool:
	if dialogue_tree.is_empty() or not dialogue_tree.has("nodes"):
		return false
	var nodes: Dictionary = dialogue_tree["nodes"]
	if nodes.is_empty():
		return false
	for node_id: String in nodes:
		var node: Dictionary = nodes[node_id]
		var choices: Array = node.get("choices", [])
		if choices.is_empty():
			continue
		var all_terminal: bool = true
		for c in choices:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			if c.has("next_node") and c["next_node"] != null and str(c["next_node"]) != "":
				all_terminal = false
				break
		if all_terminal and visited_nodes.get(node_id, 0) == 0:
			return true
	return false


## Build a snapshot of the current GameState for condition evaluation.
func _build_state_snapshot() -> Dictionary:
	# If a state provider callable is set (test hook), use it
	if state_provider.is_valid():
		return state_provider.call()

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("get_slider") or not gm.has_method("has_flag"):
		# If GameManager doesn't have the API yet, return empty state
		return { "sliders": {}, "flags": {}, "choices_made": choices_made }
	var sliders := {}
	for axis in ["hope", "despair", "vigor", "burnout", "conviction", "falter", "hope_despair"]:
		sliders[axis] = gm.get_slider(axis)
	return {
		"sliders": sliders,
		"flags": gm.get_flags(),
		"choices_made": choices_made
	}


## Apply an array of Effect dicts in order.
func _apply_effects(effects: Array) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		push_warning("GameManager not found — effects not applied")
		return
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var etype: String = effect.get("type", "")
		match etype:
			"slider_delta":
				if gm.has_method("apply_slider_delta"):
					gm.apply_slider_delta(effect.get("axis", ""), float(effect.get("delta", 0)))
			"set_flag":
				if gm.has_method("set_flag"):
					gm.set_flag(effect.get("flag", ""), bool(effect.get("value", true)))
			"trigger_event":
				push_warning("trigger_event not yet implemented: %s" % effect.get("event", ""))
			"advance_clock":
				push_warning("advance_clock not yet implemented")
			"play_sound":
				var am := get_node_or_null("/root/AudioManager")
				if am and am.has_method("play_footstep"):
					var surface: String = effect.get("surface", "")
					if surface.is_empty():
						var scene_root := get_tree().current_scene
						var scene_id_val = scene_root.get("scene_id") if scene_root else null
						var scene_id: String = str(scene_id_val) if scene_id_val != null else ""
						surface = am.get_surface_for_scene(scene_id) if scene_id != "" else "office"
					am.play_footstep(surface)
			_:
				push_warning("Unknown effect type: '%s'" % etype)


func _end_conversation() -> void:
	current_node_id = ""
	current_node = {}
	dialogue_ended.emit()

## Return the number of reachable choices from the last enter_node() call.
## Used by dialogue_debug.gd and tests.
func get_last_reachable_count() -> int:
	return _last_reachable_count

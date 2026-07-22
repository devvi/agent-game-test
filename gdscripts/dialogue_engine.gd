extends Control

# DialogueEngine — State-aware dialogue branching system
# Loads dialogue data from resource files, filters branches by state preconditions
# Emits choice_made with effect dictionary for downstream state updates

signal dialogue_started(node_id: String)
signal dialogue_ended()
signal choice_made(choice_id: String, effect: Dictionary)

var current_node: Dictionary = {}
var dialogue_data

func start_dialogue(node_id: String) -> void:
	var resource_path = "res://resources/dialogue/%s.tres" % node_id
	if ResourceLoader.exists(resource_path):
		dialogue_data = load(resource_path)
	else:
		dialogue_data = null
		current_node = {}
		return

	current_node = dialogue_data.entry_node if dialogue_data else {}
	_display_node(current_node)

func _display_node(node: Dictionary) -> void:
	var visible_branches = _get_visible_branches(node)
	_render_choices(visible_branches)

func _get_visible_branches(node: Dictionary) -> Array:
	var state = _get_state()
	var visible_branches = []
	for branch in node.get("branches", []):
		if branch.has("condition") and branch.condition != null:
			if branch.condition.call(state):
				visible_branches.append(branch)
		else:
			visible_branches.append(branch)
	return visible_branches

func _get_state() -> Dictionary:
	var ss = get_node_or_null("/root/StateSystem")
	if ss and ss.has_method("get_state"):
		return ss.get_state()
	return {"hope": 5.0, "conviction": 5.0, "will": 5.0}

func _render_choices(branches: Array) -> void:
	pass  # Placeholder — UI rendering implemented in scene layer

func _on_choice_selected(choice_id: int) -> void:
	if not current_node or not current_node.has("branches"):
		return
	var branches = current_node.get("branches", [])
	if choice_id < 0 or choice_id >= branches.size():
		return
	var choice = branches[choice_id]
	if choice.has("effect") and not choice.effect.is_empty():
		var ss = get_node_or_null("/root/StateSystem")
		if ss and ss.has_method("apply_choice"):
			ss.apply_choice(choice.effect)
		choice_made.emit(choice.get("id", ""), choice.effect)
	if choice.has("next_id") and dialogue_data and dialogue_data.nodes.has(choice.next_id):
		current_node = dialogue_data.nodes[choice.next_id]
		_display_node(current_node)
	else:
		dialogue_ended.emit()

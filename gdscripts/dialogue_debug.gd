extends CanvasLayer
class_name DialogueDebug

## Dev-only debug overlay for dialogue engine.
## Toggle visibility with F12.
## Displays: current node ID, reachable/total choice count, GameState snapshot.

@onready var node_id_label: Label = $Panel/NodeIdLabel
@onready var choices_label: Label = $Panel/ChoicesLabel
@onready var state_label: Label = $Panel/StateLabel

var is_visible: bool = false


func _ready() -> void:
	hide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") or (event is InputEventKey and event.keycode == KEY_F12 and not event.echo and not event.is_echo()):
		is_visible = not is_visible
		visible = is_visible
		get_viewport().set_input_as_handled()


## Update debug display from a DialogueRunner instance.
func update_display(runner: Node) -> void:
	if not is_visible or not is_instance_valid(runner):
		return
	if runner.has_method("get_current_node_id"):
		node_id_label.text = "Node: " + runner.get_current_node_id()
	else:
		node_id_label.text = "Node: " + runner.current_node_id
	
	var reachable_count: int = 0
	var total_count: int = 0
	if runner.has("current_node") and typeof(runner.current_node) == TYPE_DICTIONARY:
		var choices: Array = runner.current_node.get("choices", [])
		total_count = choices.size()
	if runner.has_method("get_last_reachable_count"):
		reachable_count = runner.get_last_reachable_count()
	choices_label.text = "Choices: %d / %d reachable" % [reachable_count, total_count]
	
	# GameState snapshot
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		var sliders := {}
		for axis in ["hope", "despair", "vigor", "burnout", "conviction", "falter"]:
			if gm.has_method("get_slider"):
				sliders[axis] = gm.get_slider(axis)
		state_label.text = "State: " + str(sliders)
	else:
		state_label.text = "State: N/A"

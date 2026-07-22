class_name DialogueData extends Resource

@export var id: String
@export var entry_node_id: String
@export var nodes: Dictionary = {}

var entry_node:
	get:
		return nodes.get(entry_node_id, {})

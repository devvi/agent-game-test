extends RefCounted
class_name DialogueParser

## Parsed dialogue tree shape:
## {
##   "nodes": {
##     "node_id_01": { ... DialogueNode ... },
##     "node_id_02": { ... DialogueNode ... },
##   },
##   "entry_node_id": "node_id_01"
## }

## Validates and parses a JSON dialogue file at the given path.
## Returns { "ok": true, "data": tree } or { "ok": false, "error": "..." }
static func load_dialogue(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return { "ok": false, "error": "Failed to open file: " + file_path }
	var json_str := file.get_as_text()
	file.close()
	return parse_json_string(json_str)


## Parses a JSON string and validates the dialogue tree structure.
static func parse_json_string(json_str: String) -> Dictionary:
	var json := JSON.new()
	var parse_err := json.parse(json_str)
	if parse_err != OK:
		return { "ok": false, "error": "JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()] }
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return { "ok": false, "error": "Root must be a JSON object (dictionary)" }
	return _validate_and_index(data)


## Validates structure and builds node_id → node index.
## Checks for: duplicate IDs, missing entry_node, missing referents, required fields.
static func _validate_and_index(data: Dictionary) -> Dictionary:
	# Must have "nodes" dictionary
	if not data.has("nodes") or typeof(data["nodes"]) != TYPE_DICTIONARY:
		return { "ok": false, "error": "Missing or invalid 'nodes' dictionary" }
	var nodes: Dictionary = data["nodes"]
	if nodes.is_empty():
		return { "ok": false, "error": "Dialogue tree has zero nodes" }

	# Must have entry_node_id referencing an existing node
	if not data.has("entry_node_id"):
		return { "ok": false, "error": "Missing 'entry_node_id'" }
	var entry_id: String = str(data["entry_node_id"])
	if not nodes.has(entry_id):
		return { "ok": false, "error": "entry_node_id '%s' not found in nodes" % [entry_id] }

	# Validate each node
	for node_id: String in nodes.keys():
		var node: Variant = nodes[node_id]
		if typeof(node) != TYPE_DICTIONARY:
			return { "ok": false, "error": "Node '%s' must be a dictionary" % [node_id] }
		# Required: speaker, text
		if not node.has("speaker") or typeof(node["speaker"]) != TYPE_STRING:
			return { "ok": false, "error": "Node '%s' missing 'speaker' (string)" % [node_id] }
		if not node.has("text") or typeof(node["text"]) != TYPE_STRING:
			return { "ok": false, "error": "Node '%s' missing 'text' (string)" % [node_id] }
		# Choices (optional array)
		if node.has("choices") and typeof(node["choices"]) == TYPE_ARRAY:
			for i: int in range(len(node["choices"])):
				var choice: Variant = node["choices"][i]
				if typeof(choice) != TYPE_DICTIONARY:
					return { "ok": false, "error": "Node '%s' choice %d is not a dictionary" % [node_id, i] }
				# next_node must exist in nodes (unless terminal)
				if choice.has("next_node") and choice["next_node"] != null and str(choice["next_node"]) != "":
					if not nodes.has(choice["next_node"]):
						return { "ok": false, "error": "Node '%s' choice %d next_node '%s' not found in nodes" % [node_id, i, str(choice["next_node"])] }

	return { "ok": true, "data": { "nodes": nodes, "entry_node_id": entry_id } }

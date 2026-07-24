extends Node

## DMWrapper — Loads the godot_dialogue_manager lazily after all class_name
## registrations are complete. Registers itself as the DialogueManager singleton
## so consuming code can use `DialogueManager.get_next_dialogue_line(...)`.

var _dm: Node = null
var _loaded: bool = false


func _ready() -> void:
	# By the time _ready() fires, all scripts have been scanned and
	# class_name declarations are available. Load the real DM now.
	_load_dialogue_manager()


func _load_dialogue_manager() -> void:
	if _loaded:
		return
	_loaded = true

	var DMScript = load("res://addons/dialogue_manager/dialogue_manager.gd")
	if DMScript == null:
		push_error("DMWrapper: Failed to load dialogue_manager.gd")
		return

	_dm = DMScript.new()
	if _dm == null:
		push_error("DMWrapper: Failed to instantiate dialogue manager")
		return

	# Add to scene tree so _ready() fires on it
	add_child(_dm)

	# Register as the singleton so DialogueManager.X works everywhere
	if not Engine.has_singleton("DialogueManager"):
		Engine.register_singleton("DialogueManager", _dm)

	print("DMWrapper: DialogueManager loaded and registered.")


# Forward common DM methods so the wrapper can be used directly as an autoload.

func get_next_dialogue_line(resource, key := "", extra_game_states := [], mutation_behaviour := 0):
	if _dm == null:
		push_error("DMWrapper: DialogueManager not loaded")
		return null
	return await _dm.get_next_dialogue_line(resource, key, extra_game_states, mutation_behaviour)


func create_resource_from_text(text: String) -> Resource:
	if _dm == null:
		push_error("DMWrapper: DialogueManager not loaded")
		return null
	return _dm.create_resource_from_text(text)

extends Node
class_name SceneBase

# SceneBase — Base class for all scene scripts (Issue #45)
# Provides common behavior: fade-in, state-aware text config, dialogue state restoration.

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel

var scene_id: String = ""  # Override in subclass


func _ready() -> void:
	if scene_manager and scene_manager.has_method("fade_in"):
		scene_manager.fade_in()
	_configure_environmental_text()
	_configure_ambient_audio()
	_restore_dialogue_state()


## Override in subclass: configure all environmental text for this scene (state-aware).
func _configure_environmental_text() -> void:
	pass


## Override in subclass: configure ambient audio for this scene.
func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


## Restore dialogue state from GameManager's choices_history.
func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner and dialogue_runner.has_method("load_dialogue"):
		if "choices_history" in gm and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()


## Get state tier for a given axis.
func get_state_tier(axis: String) -> String:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if ss and ss.has_method("get_state_tier"):
		return ss.get_state_tier(axis)
	return "mid"


## Get current state dictionary.
func get_state() -> Dictionary:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if ss and ss.has_method("get_state"):
		return ss.get_state()
	return {"hope": 5.0, "conviction": 5.0, "will": 5.0}


## Start a dialogue via the dialogue runner.
func start_dialogue(file_path: String, dialogue_id: String) -> void:
	if dialogue_runner and dialogue_runner.has_method("start"):
		dialogue_runner.start(file_path, dialogue_id)

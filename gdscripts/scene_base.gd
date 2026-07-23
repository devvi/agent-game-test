extends Node
class_name SceneBase

# SceneBase — Base class for all scene scripts (Issue #45)
# Provides common behavior: fade-in, player instantiation, state-aware text config,
# dialogue state restoration, and player state persistence across scene transitions.

const PLAYER_CONTROLLER: GDScript = preload("res://gdscripts/player_controller.gd")

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel

var scene_id: String = ""  # Override in subclass
var _player: Node = null   # PlayerController instance (Issue #142)


func _ready() -> void:
	if scene_manager and scene_manager.has_method("fade_in"):
		scene_manager.fade_in()
	_instantiate_player()
	_configure_environmental_text()
	_configure_ambient_audio()
	_restore_dialogue_state()


func _exit_tree() -> void:
	_save_player_state()


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


# ── Player Controller (Issue #142) ──

## Instantiate PlayerController as a child of this scene root.
func _instantiate_player() -> void:
	if _player and is_instance_valid(_player):
		return  # Already exists
	_player = PLAYER_CONTROLLER.new()
	_player.name = "PlayerController"
	add_child(_player)

	# Restore position from GameManager
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		if "player_position" in gm:
			var saved_pos = gm.get("player_position")
			if saved_pos != null and saved_pos is Vector3:
				_player.global_position = saved_pos
		if "player_rotation" in gm:
			var saved_rot = gm.get("player_rotation")
			if saved_rot != null and saved_rot is Vector3:
				_player.global_rotation = saved_rot
		if "player_head_rotation" in gm:
			var saved_head_rot = gm.get("player_head_rotation")
			if saved_head_rot != null and saved_head_rot is float:
				var head := _player.get_node_or_null("Head")
				if head:
					head.rotation.x = saved_head_rot

	# Connect interaction_requested signal
	if _player.has_signal("interaction_requested"):
		_player.interaction_requested.connect(_on_player_interaction)

	# Set fall reset position to spawn point
	if _player.has_method("set_fall_reset_position"):
		_player.set_fall_reset_position(_get_player_spawn_position())


## Get the player spawn position. Default: SpawnPoint Marker3D or origin.
func _get_player_spawn_position() -> Vector3:
	var sp := get_node_or_null("SpawnPoint")
	if sp:
		return sp.global_position
	return Vector3.ZERO


## Handle player interaction with a target node (NPC or EKeyTrigger).
func _on_player_interaction(target: Node) -> void:
	if target.has_method("start_npc_interaction"):
		target.start_npc_interaction()
		return
	if target.has_method("start_dialogue"):
		target.start_dialogue()
		return
	push_warning("SceneBase._on_player_interaction: unhandled target '%s'" % target.name)


## Save player position/rotation to GameManager before scene unload.
func _save_player_state() -> void:
	if not _player or not is_instance_valid(_player):
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return
	gm.set("player_position", _player.global_position)
	gm.set("player_rotation", _player.global_rotation)
	var head := _player.get_node_or_null("Head")
	if head:
		gm.set("player_head_rotation", head.rotation.x)

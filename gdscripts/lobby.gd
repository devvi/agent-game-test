extends SceneBase
class_name LobbyScene

# Lobby scene — Security guard (small talk), Stranger (first meeting, critical choice), exit.
# Uses 5-state tone lookup for environmental text (Issue #154).
# Supports dynamic text updates when state changes mid-scene.

@onready var entrance_text: Node3D = $Environments/EntranceText
@onready var stranger_spotlight: Node3D = $Environments/StrangerSpotlight
@onready var guard_trigger: Area3D = $InteractionZones/SecurityGuardTrigger
@onready var stranger_trigger: Area3D = $InteractionZones/StrangerTrigger
@onready var exit_trigger: Area3D = $InteractionZones/ExitTrigger


func _ready() -> void:
	scene_id = "lobby"
	super._ready()
	if guard_trigger:
		guard_trigger.input_event.connect(_on_guard_trigger_input)
	if stranger_trigger:
		stranger_trigger.input_event.connect(_on_stranger_trigger_input)
	if exit_trigger:
		exit_trigger.input_event.connect(_on_exit_trigger_input)


func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


func _configure_environmental_text() -> void:
	var tone: String = _get_tone_for_scene(scene_id)
	_set_environment_text(tone)


## Handle dynamic tone updates from NarrativeManager (Issue #154).
func _on_narrative_tone_changed(scene_id_emitted: String, tone: String) -> void:
	super._on_narrative_tone_changed(scene_id_emitted, tone)
	if scene_id_emitted != scene_id:
		return
	_set_environment_text(tone)


## Set all lobby environment text based on 5-state tone.
func _set_environment_text(tone: String) -> void:
	match tone:
		"fear":
			entrance_text.text = "The lobby is cold.\nThe lights flicker as you pass."
			stranger_spotlight.text = "A figure stands in the shadow."
		"uneasy":
			entrance_text.text = "The lobby is quiet.\nToo quiet."
			stranger_spotlight.text = "A silhouette near the door.\nYou can't see their face."
		"neutral":
			entrance_text.text = "The lobby is quiet.\nPolished floors reflect the dim lights."
			stranger_spotlight.text = "A stranger stands near the entrance."
		"curious":
			entrance_text.text = "The lobby feels warm.\nThe marble floor glows softly."
			stranger_spotlight.text = "A stranger catches your eye.\nYou feel curious."
		"defiant":
			entrance_text.text = "Warm light spills across the marble floor.\nYou walk through."
			stranger_spotlight.text = "Someone catches your eye.\nYou nod."
		_:
			entrance_text.text = "The lobby is quiet.\nPolished floors reflect the dim lights."
			stranger_spotlight.text = "A stranger stands near the entrance."


func _on_guard_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_dialogue("res://dialogues/lobby_guard.json", "lobby_guard")


func _on_stranger_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_dialogue("res://dialogues/lobby_stranger.json", "lobby_stranger")


func _on_exit_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_dialogue("res://dialogues/lobby_exit.json", "lobby_exit")

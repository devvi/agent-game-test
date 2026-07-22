extends SceneBase
class_name LobbyScene

# Lobby scene — Security guard (small talk), Stranger (first meeting, critical choice), exit.

@onready var entrance_text: Node3D = $Environments/EntranceText
@onready var stranger_spotlight: Node3D = $Environments/StrangerSpotlight
@onready var guard_trigger: Area3D = $InteractionZones/SecurityGuardTrigger
@onready var stranger_trigger: Area3D = $InteractionZones/StrangerTrigger
@onready var exit_trigger: Area3D = $InteractionZones/ExitTrigger

var scene_id: String = "lobby"


func _ready() -> void:
	super._ready()
	if guard_trigger:
		guard_trigger.input_event.connect(_on_guard_trigger_input)
	if stranger_trigger:
		stranger_trigger.input_event.connect(_on_stranger_trigger_input)
	if exit_trigger:
		exit_trigger.input_event.connect(_on_exit_trigger_input)


func _configure_environmental_text() -> void:
	var tone := _get_tone()
	_set_environment_text(tone)


func _get_tone() -> String:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if not ss:
		return "neutral"
	var conviction_val: float = ss.get("conviction", 5.0)
	if conviction_val <= 3.0: return "fear"
	elif conviction_val >= 7.0: return "defiant"
	else: return "neutral"


func _set_environment_text(tone: String) -> void:
	match tone:
		"fear":
			entrance_text.text = "The lobby is cold.\nThe lights flicker as you pass."
			stranger_spotlight.text = "A figure stands in the shadow."
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
		var nm: Node = get_node_or_null("/root/NarrativeManager")
		if nm and nm.has_method("advance_scene"):
			nm.advance_scene()

extends Node

# Office scene script
# Configures environmental text from GameState and connects door trigger.

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var window_text: Node3D = $Environments/WindowText
@onready var door_trigger: Area3D = $InteractionZones/OfficeDoorTrigger


func _ready() -> void:
	# Fade in after scene load
	scene_manager.fade_in()

	# Configure environmental text from current state
	_configure_environmental_text()

	# Connect door trigger
	door_trigger.input_event.connect(_on_door_trigger_input)

	# Restore dialogue state if returning to office
	_restore_dialogue_state()


func _configure_environmental_text() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return

	var wv = preload("res://gdscripts/worldview_controller.gd").new()
	var tone: String = wv.get_tone_for_state({"hope": gm.get_slider("hope")})

	match tone:
		"hope":
			window_text.text = "The city glitters through the rain.\nTonight could be different.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"neutral":
			window_text.text = "Rain on the glass.\nAnother night at the office.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"despair":
			window_text.text = "The streetlights blur.\nOne more night. One more.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"


func _on_door_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_door_dialogue()


func _start_door_dialogue() -> void:
	dialogue_runner.start("res://dialogues/office_door.json", "office_door")


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if gm.has("choices_history") and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

extends Node

# Underpass scene script
# Configures environmental text from GameState (hope/conviction).
# Connects final choice trigger to DialogueRunner.
# Listens for ending flag after final choice and triggers EndingController.

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var ending_controller: Node = $EndingController
@onready var graffiti_wall: Node3D = $Graffiti_Wall
@onready var subway_sign: Node3D = $SubwaySign
@onready var floor_text: Node3D = $FloorText
@onready var wall_poster: Node3D = $WallPoster
@onready var final_choice_trigger: Area3D = $InteractionZones/FinalChoiceTrigger


func _ready() -> void:
	scene_manager.fade_in()
	_configure_environmental_text()
	final_choice_trigger.input_event.connect(_on_final_choice_input)
	dialogue_runner.dialogue_ended.connect(_on_dialogue_ended)
	_restore_dialogue_state()


func _configure_environmental_text() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return
	var hope: float = gm.get_slider("hope")
	var conviction: float = gm.get_slider("conviction")

	# Tunnel wall graffiti: hope-based visibility with intertextual echoes
	if hope >= 5.0:
		graffiti_wall.text = "the same streets / the same night"
		graffiti_wall.modulate = Color(0.8, 0.8, 0.9, 0.7)
	else:
		graffiti_wall.text = "el m... / t... s... st..."
		graffiti_wall.modulate = Color(0.5, 0.5, 0.5, 0.3)

	# Subway sign is static
	subway_sign.text = "NEXT TRAIN - Platform 3"
	subway_sign.modulate = Color(0.7, 0.7, 0.8, 0.9)

	# Floor text: conviction-based permanence with echo #3
	if conviction >= 7.0:
		floor_text.text = "i was here"
		floor_text.modulate = Color(0.6, 0.6, 0.6, 0.5)
	else:
		floor_text.text = "i w s here"
		floor_text.modulate = Color(0.4, 0.4, 0.4, 0.3)

	# Wall poster is static (echo #1 callback)
	wall_poster.text = "Check the door before leaving"
	wall_poster.modulate = Color(0.9, 0.85, 0.7, 0.5)


func _on_final_choice_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_final_dialogue()


func _start_final_dialogue() -> void:
	# Load underpass dialogue JSON directly
	dialogue_runner.start("res://dialogues/underpass.json", "underpass")


func _on_dialogue_ended() -> void:
	# Check which ending flag was set and start the appropriate ending sequence
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm or not gm.has_method("has_flag"):
		return

	if gm.has_flag("ending_keep_walking"):
		ending_controller.start_ending("ending_keep_walking")
	elif gm.has_flag("ending_turn_back"):
		ending_controller.start_ending("ending_turn_back")
	elif gm.has_flag("ending_stay"):
		ending_controller.start_ending("ending_stay")
	# If no ending flag is set, this was some other dialogue end — no action needed.


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if gm.has("choices_history") and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

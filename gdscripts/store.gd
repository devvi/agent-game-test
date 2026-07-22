extends Node

# Store scene script
# Configures OPEN sign text, triggers clerk dialogue.
# After clerk dialogue ends, transitions to underpass.tscn.

const UNDERPASS_SCENE: String = "res://scenes/underpass/underpass.tscn"

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var open_sign: Node3D = $Environments/OpenSign
@onready var clerk_trigger: Area3D = $InteractionZones/ClerkTrigger


func _ready() -> void:
	scene_manager.fade_in()
	_configure_environmental_text()
	clerk_trigger.input_event.connect(_on_clerk_trigger_input)
	dialogue_runner.dialogue_ended.connect(_on_clerk_dialogue_ended)
	_restore_dialogue_state()


func _configure_environmental_text() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return
	var hope: float = gm.get_slider("hope")
	var conviction: float = gm.get_slider("conviction")

	# Always show "OPEN"
	# Show Stranger foreshadowing subtitle if both hope >= 5 and conviction >= 4
	if hope >= 5.0 and conviction >= 4.0:
		open_sign.text = "OPEN\n⌈He was here tonight.⌋"
	else:
		open_sign.text = "OPEN"


func _on_clerk_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dialogue_runner.start("res://dialogues/store_clerk.json", "store_clerk")


func _on_clerk_dialogue_ended() -> void:
	# After clerk dialogue ends, transition to Underpass scene
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("set_flag"):
		gm.set_flag("completed_store", true)
	if scene_manager and scene_manager.has_method("trigger_scene_change"):
		scene_manager.trigger_scene_change(UNDERPASS_SCENE)


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if gm.has("choices_history") and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

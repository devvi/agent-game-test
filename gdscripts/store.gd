extends SceneBase
class_name StoreScene

# Store scene script
# Configures OPEN sign text, triggers store exit.
# Clerk interaction is handled by NPC.tscn (NPCNode) instance.

@onready var open_sign: Node3D = $Environments/OpenSign
@onready var exit_trigger: Area3D = $InteractionZones/StoreExitTrigger


func _ready() -> void:
	scene_id = "convenience_store"
	super._ready()
	if exit_trigger:
		exit_trigger.input_event.connect(_on_exit_trigger_input)


func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


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


func _on_exit_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dialogue_runner.start("res://dialogues/store_exit.json", "store_exit")


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if "choices_history" in gm and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

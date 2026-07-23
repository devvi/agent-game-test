extends SceneBase
class_name StreetScene

# Street scene script
# Configures neon, graffiti, and street sign text. Sets rain intensity.
# Connects store entrance trigger.

@onready var neon_sign: Node3D = $Environments/NeonSign
@onready var graffiti: Node3D = $Environments/Graffiti
@onready var street_sign: Node3D = $Environments/StreetSign
@onready var store_entrance: Area3D = $InteractionZones/StoreEntranceTrigger
@onready var test_npc_interact: Node = $InteractionZones/TestNPC/InteractionTrigger/EKeyTrigger


func _ready() -> void:
	scene_id = "street"
	super._ready()
	store_entrance.input_event.connect(_on_store_entrance_input)
	if test_npc_interact and test_npc_interact.has_signal("e_key_interacted"):
		test_npc_interact.e_key_interacted.connect(_on_test_npc_interact)


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

	# Neon sign: conviction-based glow
	if conviction >= 7.0:
		neon_sign.modulate = Color(1.0, 0.7, 0.2)  # warm amber
	elif conviction >= 4.0:
		neon_sign.modulate = Color(1.0, 0.6, 0.1)  # dim amber
	else:
		neon_sign.modulate = Color(0.8, 0.1, 0.1)  # dim red

	# Graffiti: hope-based visibility
	if hope >= 6.0:
		graffiti.text = "this too shall pass"
		graffiti.modulate = Color(1, 1, 1, 0.6)  # faded
	else:
		graffiti.text = "i was here"
		graffiti.modulate = Color(1, 1, 1, 0.3)  # partially scratched

	# Street sign is static
	street_sign.text = "ELM ST."


func _on_store_entrance_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dialogue_runner.start("res://dialogues/office_door.json", "store_entrance")


func _on_test_npc_interact() -> void:
	var npc_node: Node = $InteractionZones/TestNPC/NPC
	if npc_node and npc_node.has_method("start_npc_interaction"):
		npc_node.start_npc_interaction()


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if "choices_history" in gm and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

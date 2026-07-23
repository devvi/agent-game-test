extends SceneBase
class_name StreetScene

# Street scene script
# Configures neon, graffiti, and street sign text via 5-state tone lookup (Issue #154).
# Supports dynamic text updates when state changes mid-scene.

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
	var tone: String = _get_tone_for_scene(scene_id)
	_set_graffiti_text(tone)
	_set_neon_modulate(tone)

	# Street sign is static
	street_sign.text = "ELM ST."


## Handle dynamic tone updates from NarrativeManager (Issue #154).
func _on_narrative_tone_changed(scene_id_emitted: String, tone: String) -> void:
	super._on_narrative_tone_changed(scene_id_emitted, tone)
	if scene_id_emitted != scene_id:
		return
	_set_graffiti_text(tone)
	_set_neon_modulate(tone)


## Set graffiti text based on 5-state tone.
func _set_graffiti_text(tone: String) -> void:
	match tone:
		"despair":
			graffiti.text = "i was here"
			graffiti.modulate = Color(1, 1, 1, 0.3)
		"low":
			graffiti.text = "i was here"
			graffiti.modulate = Color(1, 1, 1, 0.4)
		"neutral":
			graffiti.text = "i was here"
			graffiti.modulate = Color(1, 1, 1, 0.5)
		"buoyant":
			graffiti.text = "this too shall pass"
			graffiti.modulate = Color(1, 1, 1, 0.6)
		"hope":
			graffiti.text = "this too shall pass"
			graffiti.modulate = Color(1, 1, 1, 0.8)
		_:
			graffiti.text = "i was here"
			graffiti.modulate = Color(1, 1, 1, 0.5)


## Set neon sign modulate color based on 5-state tone.
func _set_neon_modulate(tone: String) -> void:
	match tone:
		"despair":
			neon_sign.modulate = Color(0.5, 0.05, 0.05)  # dim red
		"low":
			neon_sign.modulate = Color(0.6, 0.1, 0.1)  # dull red
		"neutral":
			neon_sign.modulate = Color(1.0, 0.6, 0.1)  # dim amber
		"buoyant":
			neon_sign.modulate = Color(1.0, 0.7, 0.2)  # warm amber
		"hope":
			neon_sign.modulate = Color(1.0, 0.9, 0.3)  # bright gold
		_:
			neon_sign.modulate = Color(1.0, 0.6, 0.1)


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

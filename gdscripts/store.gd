extends SceneBase
class_name StoreScene

# Store scene script
# Configures OPEN sign text via 5-state tone lookup (Issue #154).
# Supports dynamic text updates when state changes mid-scene.
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
	var tone: String = _get_tone_for_scene(scene_id)
	_set_open_sign_text(tone)


## Handle dynamic tone updates from NarrativeManager (Issue #154).
func _on_narrative_tone_changed(scene_id_emitted: String, tone: String) -> void:
	super._on_narrative_tone_changed(scene_id_emitted, tone)
	if scene_id_emitted != scene_id:
		return
	_set_open_sign_text(tone)


## Set open sign text based on 5-state tone.
func _set_open_sign_text(tone: String) -> void:
	match tone:
		"cold":
			open_sign.text = "OPEN\n(24h)"
		"distant":
			open_sign.text = "OPEN\n⌈Hollow light.⌋"
		"neutral":
			open_sign.text = "OPEN"
		"warm":
			open_sign.text = "OPEN\n⌈He was here tonight.⌋"
		"glowing":
			open_sign.text = "OPEN\n⌈He was here. He left a light on.⌋"
		_:
			open_sign.text = "OPEN"


func _on_exit_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dialogue_runner.start("res://dialogues/store_exit.json", "store_exit")


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if "choices_history" in gm and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

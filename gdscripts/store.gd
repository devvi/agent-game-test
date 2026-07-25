extends SceneBase
class_name StoreScene

# Store scene script
# Configures OPEN sign text via 5-state tone lookup (Issue #154).
# Supports dynamic text updates when state changes mid-scene.
# Clerk interaction is handled by NPC.tscn (NPCNode) instance.

@onready var open_sign: Node3D = $Environments/OpenSign
@onready var exit_trigger: Area3D = $InteractionZones/StoreExitTrigger
@onready var store_stranger_trigger: Area3D = $InteractionZones/StoreStrangerTrigger
@onready var stranger_decal: Decal = $Environments/StrangerDecal if $Environments.has_node("StrangerDecal") else null


func _ready() -> void:
	scene_id = "convenience_store"
	super._ready()
	if exit_trigger:
		exit_trigger.input_event.connect(_on_exit_trigger_input)
	
	# Stranger store reflection trigger
	if store_stranger_trigger:
		store_stranger_trigger.input_event.connect(_on_store_stranger_trigger_input)
	
	# Update Stranger Decal color based on hallucination level
	call_deferred("_update_stranger_decal")


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
		_show_dialogue_balloon("res://dialogues/store_exit.dialogue", "store_exit")


## Handle store stranger reflection interaction.
func _on_store_stranger_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Choose dialogue variant based on hallucination level
		var nm: Node = get_node_or_null("/root/NarrativeManager")
		var ss: Node = get_node_or_null("/root/StateSystem")
		var variant_title: String = "stranger_store_low"
		if nm and nm.has_method("get_hallucination_level") and ss:
			var state: Dictionary = {"hope": ss.hope if ss else 5.0}
			var h_level: int = nm.get_hallucination_level(scene_id, state)
			if h_level >= 7:
				variant_title = "stranger_store_high"
			elif h_level >= 4:
				variant_title = "stranger_store_mid"
		start_dialogue("res://dialogues/store_stranger.dialogue", variant_title)


## Update Stranger Decal color based on current hallucination level.
func _update_stranger_decal() -> void:
	if not stranger_decal:
		return
	var nm: Node = get_node_or_null("/root/NarrativeManager")
	var ss: Node = get_node_or_null("/root/StateSystem")
	if nm and nm.has_method("get_hallucination_level") and ss:
		var state: Dictionary = {"hope": ss.hope if ss else 5.0}
		var h_level: int = nm.get_hallucination_level(scene_id, state)
		stranger_decal.modulate = nm.get_stranger_decal_color(h_level)


func _restore_dialogue_state() -> void:
	pass


# ── Navigation System (Issue #226) ──

## Override: display navigation hint via open sign text.
func _show_navigation_hint(text: String) -> void:
	if open_sign and is_instance_valid(open_sign):
		var saved_text: String = open_sign.text
		open_sign.text = text
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(open_sign):
			open_sign.text = saved_text


## Override: condition-triggered navigation text.
func _on_condition_text_updated(hint: String) -> void:
	if open_sign and is_instance_valid(open_sign):
		open_sign.text = hint
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(open_sign):
			_set_open_sign_text(_get_tone_for_scene(scene_id))

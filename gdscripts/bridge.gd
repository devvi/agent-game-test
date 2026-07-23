extends SceneBase
class_name BridgeScene

# Bridge scene — Railing (overlook), homeless (echo mirror), rain (pressure), low-conviction intrusive thought.
# Uses 5-state tone lookup for environmental text (Issue #154).
# Supports dynamic text updates when state changes mid-scene.

@onready var traffic_text: Node3D = $Environments/TrafficText
@onready var homeless_text: Node3D = $Environments/HomelessText
@onready var rain_bridge_text: Node3D = $Environments/RainBridgeText
@onready var railing_trigger: Area3D = $InteractionZones/RailingTrigger
@onready var homeless_trigger: Area3D = $InteractionZones/HomelessTrigger
@onready var exit_trigger: Area3D = $InteractionZones/BridgeExitTrigger


func _ready() -> void:
	scene_id = "bridge"
	super._ready()
	if railing_trigger:
		railing_trigger.input_event.connect(_on_railing_trigger_input)
	if homeless_trigger:
		homeless_trigger.input_event.connect(_on_homeless_trigger_input)
	if exit_trigger:
		exit_trigger.input_event.connect(_on_exit_trigger_input)

	# Check for low-conviction intrusive thought
	call_deferred("_check_intrusive_thought")


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


## Set all bridge environment text based on 5-state tone.
func _set_environment_text(tone: String) -> void:
	match tone:
		"tired":
			traffic_text.text = "The cars blur past.\nYou've seen them a thousand times."
			homeless_text.text = "A homeless person sits by the railing.\nThey don't look at you."
			rain_bridge_text.text = "The rain is heavier here.\nYour coat is soaked."
		"heavy":
			traffic_text.text = "Traffic crawls below.\nExhaust fumes rise through the rain."
			homeless_text.text = "A homeless person shivers under cardboard.\nYou look away."
			rain_bridge_text.text = "Sheets of rain.\nThe asphalt gleams like an oil spill."
		"neutral":
			traffic_text.text = "Traffic flows below the bridge.\nRed tail lights stretch into the distance."
			homeless_text.text = "A homeless person sits near the railing,\nwrapped in a dirty coat."
			rain_bridge_text.text = "Rain falls steadily.\nThe wind picks up."
		"hopeful":
			traffic_text.text = "The city moves beneath you.\nRed lights pulse like a heartbeat."
			homeless_text.text = "A homeless person looks up and nods.\nYou nod back."
			rain_bridge_text.text = "Rain drums on the asphalt.\nYou pull your coat tighter."
		"determined":
			traffic_text.text = "The city moves beneath you.\nYou're part of it."
			homeless_text.text = "A homeless person is humming a tune.\nIt sounds familiar."
			rain_bridge_text.text = "Rain drums on the asphalt.\nYou walk on."
		_:
			traffic_text.text = "Traffic flows below the bridge.\nRed tail lights stretch into the distance."
			homeless_text.text = "A homeless person sits near the railing,\nwrapped in a dirty coat."
			rain_bridge_text.text = "Rain falls steadily.\nThe wind picks up."


func _check_intrusive_thought() -> void:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if ss and (ss.conviction if ss else 5.0) <= 2.0:
		if rain_bridge_text:
			rain_bridge_text.text = "A voice in your head:\n'从这里跳下去就解脱了'\nYou grip the railing. You don't jump."
		# Synchronize with echo system — intrusive thought path also triggers screensaver echo
		var nm: Node = get_node_or_null("/root/NarrativeManager")
		if nm and nm.has_method("trigger_echo"):
			nm.trigger_echo("screensaver_echo")


func _on_railing_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Overlook the railing — state-aware flavor text
		var ss: Node = get_node_or_null("/root/StateSystem")
		var conviction_val: float = ss.conviction if ss else 5.0
		if conviction_val <= 3.0:
			traffic_text.text = "The drop is further than you remembered.\nYour stomach tightens."
		else:
			traffic_text.text = "The city lights stretch to the horizon.\nYou exhale."


func _on_homeless_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_dialogue("res://dialogues/bridge_homeless.json", "bridge_homeless")


func _on_exit_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_dialogue("res://dialogues/bridge_exit.json", "bridge_exit")

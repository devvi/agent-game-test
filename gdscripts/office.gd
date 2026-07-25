extends SceneBase
class_name OfficeScene

# Office scene script
# Configures environmental text from 5-state tone lookup (Issue #154).
# Supports dynamic text updates when state changes mid-scene.
# Screensaver and desktop text remain static (story elements, not env text).
# Stranger window reflection with hallucination-aware decal (Issue #223).

@onready var window_text: Node3D = $Environments/WindowText
@onready var screensaver_text: Node3D = $Environments/ScreensaverText
@onready var desktop_text: Node3D = $Environments/DesktopText
@onready var door_trigger: Area3D = $InteractionZones/OfficeDoorTrigger
@onready var window_trigger: Area3D = $InteractionZones/WindowTrigger
@onready var stranger_decal: Decal = $Environments/StrangerDecal if $Environments.has_node("StrangerDecal") else null


func _ready() -> void:
	scene_id = "office"
	super._ready()
	door_trigger.input_event.connect(_on_door_trigger_input)

	# Connect E-key interaction (Issue #142)
	var ekey := $InteractionZones/OfficeDoorTrigger/EKeyTrigger
	if ekey and ekey.has_signal("e_key_interacted"):
		if not ekey.e_key_interacted.is_connected(_start_door_dialogue):
			ekey.e_key_interacted.connect(_start_door_dialogue)

	# Stranger window trigger
	if window_trigger:
		window_trigger.input_event.connect(_on_window_trigger_input)

	# Update Stranger Decal color based on hallucination level
	call_deferred("_update_stranger_decal")


func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


func _configure_environmental_text() -> void:
	var tone: String = _get_tone_for_scene(scene_id)
	_set_window_text(tone)

	# Screensaver — source of echo 2 (screensaver_echo) — static
	screensaver_text.text = "你做游戏有什么用？"

	# Desktop — deadline display — static
	var ss: Node = get_node_or_null("/root/StateSystem")
	var day: int = 0
	if ss and ss.has_method("get"):
		day = int(ss.day) if "day" in ss else 0
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		day = int(gm.get_slider("day"))
	desktop_text.text = "Deadline: Day %d / 90" % day


## Handle dynamic tone updates from NarrativeManager (Issue #154).
func _on_narrative_tone_changed(scene_id_emitted: String, tone: String) -> void:
	super._on_narrative_tone_changed(scene_id_emitted, tone)
	if scene_id_emitted != scene_id:
		return
	_set_window_text(tone)


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


## Handle window interaction — flavor text and flag.
func _on_window_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var nm: Node = get_node_or_null("/root/NarrativeManager")
		if nm and nm.has_method("set_flag"):
			nm.set_flag("stranger_office_glimpsed", true)
		# Choose flavor text based on hallucination level
		var ss: Node = get_node_or_null("/root/StateSystem")
		var h_level: int = 0
		if nm and nm.has_method("get_hallucination_level") and ss:
			var state: Dictionary = {"hope": ss.hope if ss else 5.0}
			h_level = nm.get_hallucination_level(scene_id, state)
		match h_level:
			0, 1, 2:
				window_text.text = "A silhouette stands outside.\nRain coats their shoulders.\n⌈You look away.⌋"
			3, 4, 5:
				window_text.text = "A figure in the rain.\nThey're looking this way.\n⌈You don't know them.⌋"
			_:
				window_text.text = "The window reflects the room.\nYou see yourself.\nSomeone is standing behind you."


func _set_window_text(tone: String) -> void:
	match tone:
		"despair":
			window_text.text = "The streetlights blur.\nOne more night. One more.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"low":
			window_text.text = "The city is grey.\nSame rain. Same night.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"neutral":
			window_text.text = "Rain on the glass.\nAnother night at the office.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"buoyant":
			window_text.text = "Raindrops shimmer on the glass.\nThe city is wet and alive.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"hope":
			window_text.text = "The city glitters through the rain.\nTonight could be different.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		_:
			window_text.text = "Rain on the glass.\nAnother night at the office.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"


func _on_door_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_door_dialogue()


func _start_door_dialogue() -> void:
	_show_dialogue_balloon("res://dialogues/office_door.dialogue", "office_door")


func _restore_dialogue_state() -> void:
	pass


# ── Navigation System (Issue #226) ──

## Override: display navigation hint via environmental text node.
func _show_navigation_hint(text: String) -> void:
	if window_text and is_instance_valid(window_text):
		# Temporarily show hint text on window
		window_text.text = text
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(window_text):
			_set_window_text(_get_tone_for_scene(scene_id))


## Override: condition-triggered navigation text.
func _on_condition_text_updated(hint: String) -> void:
	if window_text and is_instance_valid(window_text):
		window_text.text = hint
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(window_text):
			_set_window_text(_get_tone_for_scene(scene_id))

extends SceneBase
class_name OfficeScene

# Office scene script
# Configures environmental text from 5-state tone lookup (Issue #154).
# Supports dynamic text updates when state changes mid-scene.
# Screensaver and desktop text remain static (story elements, not env text).

@onready var window_text: Node3D = $Environments/WindowText
@onready var screensaver_text: Node3D = $Environments/ScreensaverText
@onready var desktop_text: Node3D = $Environments/DesktopText
@onready var door_trigger: Area3D = $InteractionZones/OfficeDoorTrigger


func _ready() -> void:
	scene_id = "office"
	super._ready()
	door_trigger.input_event.connect(_on_door_trigger_input)


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


## Set window text for a 5-state tone.
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
	dialogue_runner.start("res://dialogues/office_door.json", "office_door")


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if "choices_history" in gm and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

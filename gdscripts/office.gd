extends SceneBase
class_name OfficeScene

# Office scene script
# Configures environmental text from GameState and connects door trigger.

@onready var window_text: Node3D = $Environments/WindowText
@onready var screensaver_text: Node3D = $Environments/ScreensaverText
@onready var desktop_text: Node3D = $Environments/DesktopText
@onready var door_trigger: Area3D = $InteractionZones/OfficeDoorTrigger

var scene_id: String = "office"


func _ready() -> void:
	super._ready()
	door_trigger.input_event.connect(_on_door_trigger_input)


func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


func _configure_environmental_text() -> void:
	var ss: Node = get_node_or_null("/root/StateSystem")
	var gm: Node = get_node_or_null("/root/GameManager")
	if not ss and not gm:
		return

	var hope_val: float = ss.get("hope", 5.0) if ss else (gm.get_slider("hope") if gm else 5.0)
	var tone: String = "neutral"
	if hope_val <= 3.0:
		tone = "despair"
	elif hope_val >= 7.0:
		tone = "hope"

	match tone:
		"hope":
			window_text.text = "The city glitters through the rain.\nTonight could be different.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"neutral":
			window_text.text = "Rain on the glass.\nAnother night at the office.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"
		"despair":
			window_text.text = "The streetlights blur.\nOne more night. One more.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"

	# Screensaver — source of echo 2 (screensaver_echo)
	screensaver_text.text = "你做游戏有什么用？"

	# Desktop — deadline display
	var day: int = 0
	if ss and ss.has_method("get"):
		day = int(ss.get("day", 0)) if ss.has("day") else 0
	elif gm:
		day = int(gm.get_slider("day"))
	desktop_text.text = "Deadline: Day %d / 90" % day


func _on_door_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_door_dialogue()


func _start_door_dialogue() -> void:
	dialogue_runner.start("res://dialogues/office_door.json", "office_door")


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if gm.has("choices_history") and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

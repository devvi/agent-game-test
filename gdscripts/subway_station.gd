extends SceneBase
class_name SubwayStationScene

# Subway Station — Final scene. Ticket gate, clock, Stranger farewell, 3 ending paths.

@onready var ticket_gate_text: Node3D = $Environments/TicketGateText
@onready var clock_text: Node3D = $Environments/ClockText
@onready var broadcast_text: Node3D = $Environments/BroadcastText
@onready var stranger_final_text: Node3D = $Environments/StrangerFinalText
@onready var gate_trigger: Area3D = $InteractionZones/TicketGateTrigger
@onready var turn_back_trigger: Area3D = $InteractionZones/TurnBackTrigger
@onready var bench_trigger: Area3D = $InteractionZones/BenchTrigger

var _ending: String = ""
var _ending_determined: bool = false


func _ready() -> void:
	scene_id = "subway_station"
	super._ready()
	if gate_trigger:
		gate_trigger.input_event.connect(_on_gate_trigger_input)
	if turn_back_trigger:
		turn_back_trigger.input_event.connect(_on_turn_back_trigger_input)
	if bench_trigger:
		bench_trigger.input_event.connect(_on_bench_trigger_input)
	
	call_deferred("_determine_ending")


func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


func _configure_environmental_text() -> void:
	var tone := _get_tone()
	_set_environment_text(tone)


func _get_tone() -> String:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if not ss:
		return "waiting"
	var state := ss.get_state()
	var hope_val: float = state.get("hope", 5.0)
	if hope_val >= 6.0:
		return "forward"
	elif ss.conviction if ss else 5.0 <= 3.0:
		return "backward"
	else:
		return "waiting"


func _set_environment_text(tone: String) -> void:
	match tone:
		"forward":
			ticket_gate_text.text = "The gate is open.\nYour ticket is ready."
			clock_text.text = "11:47 PM — Last train inbound."
			broadcast_text.text = "Next train: arriving."
		"backward":
			ticket_gate_text.text = "The gate reads 'CLOSED'.\nYou hesitate."
			clock_text.text = "11:47 PM — You still have time."
			broadcast_text.text = "Final boarding call."
		_:
			ticket_gate_text.text = "The ticket gate stands before you.\nOne way in. No way back."
			clock_text.text = "11:47 PM — The clock ticks."
			broadcast_text.text = "Please mind the gap."


func _determine_ending() -> void:
	if _ending_determined:
		return
	
	var nm: Node = get_node_or_null("/root/NarrativeManager")
	var ss: Node = get_node_or_null("/root/StateSystem")
	
	if nm and nm.has_method("determine_ending") and ss:
		_ending = nm.determine_ending(ss.get_state())
		_ending_determined = true
		_set_ending_text(_ending)
		nm.ending_determined.emit(_ending)
	else:
		# Fallback
		_ending = "stay"
		_ending_determined = true
		_set_ending_text(_ending)


func _set_ending_text(ending: String) -> void:
	match ending:
		"keep_walking":
			stranger_final_text.text = "The Stranger smiles.\n\"下次再见\" — then vanishes into the crowd."
			broadcast_text.text = "Train arriving. Please stand behind the yellow line."
		"turn_back":
			stranger_final_text.text = "The Stranger stands at the tunnel entrance.\n\"你确定？\" — the same pose as when you started."
			broadcast_text.text = "The exit door is still open."
		"stay":
			stranger_final_text.text = "The Stranger sits beside you.\nSilence. Then they stand and walk into the maintenance tunnel."
			broadcast_text.text = "The last train has departed."


func _on_gate_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Keep Walking path
		if _ending == "keep_walking" or _ending.is_empty():
			start_dialogue("res://dialogues/subway_ending.json", "subway_ending_walk")


func _on_turn_back_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Turn Back path
		if _ending == "turn_back" or _ending.is_empty():
			start_dialogue("res://dialogues/subway_ending.json", "subway_ending_turnback")


func _on_bench_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Stay path
		if _ending == "stay" or _ending.is_empty():
			start_dialogue("res://dialogues/subway_ending.json", "subway_ending_stay")

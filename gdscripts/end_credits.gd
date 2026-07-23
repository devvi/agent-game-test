extends Node3D
class_name EndCredits

# End-credits scene script.
# Reads ending flags set by subway_ending.json, displays
# appropriate title + epilogue, then returns to main.tscn.

@onready var scene_manager: Node = $SceneManager
@onready var title_label: Label3D = $TitleLabel
@onready var epilogue_label: Label3D = $EpilogueLabel
@onready var the_end_label: Label3D = $TheEndLabel

var _ending_id: String = ""


func _ready() -> void:
	_determine_ending()
	_set_epilogue()
	_fade_in()
	$ReturnTimer.start()
	title_label.visible = true
	epilogue_label.visible = true
	the_end_label.visible = true


func _determine_ending() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		_ending_id = "stay"
		return
	if gm.has_flag("ending_keep_walking"):
		_ending_id = "keep_walking"
	elif gm.has_flag("ending_turn_back"):
		_ending_id = "turn_back"
	elif gm.has_flag("ending_stay"):
		_ending_id = "stay"
	else:
		_ending_id = "stay"


func _set_epilogue() -> void:
	match _ending_id:
		"keep_walking":
			title_label.text = "Keep Walking"
			epilogue_label.text = "The train carries you forward.\nThe city fades behind the glass.\nYou don't look back."
		"turn_back":
			title_label.text = "Turn Back"
			epilogue_label.text = "The exit door clicks shut.\nThe streets are empty.\nYou walk home."
		"stay":
			title_label.text = "Stay"
			epilogue_label.text = "The platform hums.\nThe clock reads 11:48.\nYou're still here. That's okay."


func _fade_in() -> void:
	if scene_manager and scene_manager.has_method("fade_in"):
		scene_manager.fade_in()


func _on_return_timer_timeout() -> void:
	_return_to_start()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_return_to_start()


func _return_to_start() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("reset"):
		gm.reset()
	var ss: Node = get_node_or_null("/root/StateSystem")
	if ss and ss.has_method("reset"):
		ss.reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

class_name DialogueBalloon extends CanvasLayer

signal dialogue_ended()

@export var next_action: StringName = &"dialogue_select"
@export var skip_action: StringName = &"dialogue_skip"
@export var up_action: StringName = &"dialogue_up"
@export var down_action: StringName = &"dialogue_down"

@onready var balloon: Control = %Balloon
@onready var character_label: RichTextLabel = %CharacterLabel
@onready var dialogue_label: DialogueLabel = %DialogueLabel
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var dialogue_resource: DialogueResource
var temporary_game_states: Array = []
var is_waiting_for_input: bool = false
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			_apply_dialogue_line()
		else:
			_close()
	get:
		return dialogue_line

static var _current_balloon: DialogueBalloon = null


func _ready() -> void:
	if _current_balloon and is_instance_valid(_current_balloon):
		_current_balloon.queue_free()
	_current_balloon = self

	balloon.modulate = Color.TRANSPARENT
	balloon.show()

	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action


func _input(event: InputEvent) -> void:
	if dialogue_label.is_typing:
		if event.is_action_pressed(skip_action) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()):
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
		return

	if not is_waiting_for_input:
		return

	if dialogue_line and dialogue_line.responses.size() > 0:
		if event.is_action_pressed(up_action):
			get_viewport().set_input_as_handled()
			responses_menu._on_up()
		elif event.is_action_pressed(down_action):
			get_viewport().set_input_as_handled()
			responses_menu._on_down()
		elif event.is_action_pressed(next_action):
			get_viewport().set_input_as_handled()
			responses_menu._on_accept()
	elif dialogue_line and dialogue_line.responses.size() == 0:
		if event.is_action_pressed(next_action) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()):
			get_viewport().set_input_as_handled()
			_next_line(dialogue_line.next_id)


func start(resource: DialogueResource, title: String = "", extra_game_states: Array = []) -> void:
	dialogue_resource = resource
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	dialogue_line = await dialogue_resource.get_next_dialogue_line(title, temporary_game_states)
	animation_player.play("fade_in")


func _apply_dialogue_line() -> void:
	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL

	character_label.visible = not dialogue_line.character.is_empty()
	character_label.text = tr(dialogue_line.character, "dialogue")

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	balloon.show()
	dialogue_label.show()

	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time: float = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		_next_line(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


func _next_line(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


func _close() -> void:
	_current_balloon = null
	dialogue_ended.emit()
	if animation_player.has_animation("fade_out"):
		animation_player.play("fade_out")
		await animation_player.animation_finished
	queue_free()


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	_next_line(response.next_id)

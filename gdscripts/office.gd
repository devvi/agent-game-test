extends Node

# Office scene script
# Configures environmental text from GameState and connects door trigger.
# Uses 5-state hope/despair mapping for window text variants.

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var window_text: Node3D = $Environments/WindowText
@onready var desk_note: Node3D = $Environments/DeskNote
@onready var door_trigger: Area3D = $InteractionZones/OfficeDoorTrigger


func _ready() -> void:
	# Fade in after scene load
	scene_manager.fade_in()

	# Configure environmental text from current state
	_configure_environmental_text()

	# Connect door trigger
	door_trigger.input_event.connect(_on_door_trigger_input)

	# Restore dialogue state if returning to office
	_restore_dialogue_state()


func _configure_environmental_text() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return

	var hope_despair: float = gm.get_slider("hope_despair")
	var state_id: int = _hope_despair_to_state_id(hope_despair)

	var window_variants: Array = [
		"The streetlights blur.\nOne more night. One more.\n⌈Somewhere out there, someone walks\nthe same streets.⌋",                           # Despair
		"The rain streaks the glass.\nAnother long shift.\n⌈Somewhere out there, someone walks\nthe same streets.⌋",                                 # Low
		"Rain on the glass.\nAnother night at the office.\n⌈Somewhere out there, someone walks\nthe same streets.⌋",                                    # Neutral
		"The street glimmers through the rain.\nAlmost done for tonight.\n⌈Somewhere out there, someone walks\nthe same streets.⌋",                      # Buoyant
		"The city glitters through the rain.\nTonight could be different.\n⌈Somewhere out there, someone walks\nthe same streets.⌋"                       # Hope
	]

	window_text.text = get_variant(state_id, window_variants)

	# Desk note (static, intertextual echo #1)
	if desk_note:
		desk_note.text = "⌈Remember:⌋\nCheck the door."


func get_variant(state_id: int, variants: Array) -> String:
	var idx: int = clampi(state_id - 1, 0, variants.size() - 1)
	return variants[idx]


func _hope_despair_to_state_id(value: float) -> int:
	var boundaries: Array[float] = [-10.0, -6.0, -2.0, 1.0, 5.0, 10.0]
	for i in range(boundaries.size() - 1):
		if value >= boundaries[i] and value <= boundaries[i + 1]:
			return i + 1
	if value < -10.0:
		return 1
	return 5


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

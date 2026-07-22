extends Node

# Store scene script
# Configures OPEN sign text (5-state variants), triggers clerk dialogue.
# After clerk dialogue ends, transitions to underpass.tscn.

const UNDERPASS_SCENE: String = "res://scenes/underpass/underpass.tscn"

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var open_sign: Node3D = $Environments/OpenSign
@onready var clerk_trigger: Area3D = $InteractionZones/ClerkTrigger


func _ready() -> void:
	scene_manager.fade_in()
	_configure_environmental_text()
	clerk_trigger.input_event.connect(_on_clerk_trigger_input)
	dialogue_runner.dialogue_ended.connect(_on_clerk_dialogue_ended)
	_restore_dialogue_state()


func _configure_environmental_text() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return
	var hope_despair: float = gm.get_slider("hope_despair")
	var state_id: int = _hope_despair_to_state_id(hope_despair)
	var conviction: float = gm.get_slider("conviction")

	# OPEN sign with 5-state variants
	var sign_variants: Array = [
		"OPEN\n⌈The light buzzes. Empty inside.⌋",                      # Despair
		"OPEN\n⌈A single customer. Slouched at the counter.⌋",          # Low
		"OPEN\n⌈The fluorescent hum. The usual.⌋",                      # Neutral
		"OPEN\n⌈Warm light spills onto the wet pavement.⌋",             # Buoyant
		"OPEN\n⌈He was here tonight. / The clerk remembers.⌋"           # Hope
	]
	open_sign.text = get_variant(state_id, sign_variants)

	# Also show stranger foreshadowing if both hope_despair > 0 and conviction >= 4
	if hope_despair > 0.0 and conviction >= 4.0 and state_id >= 4:
		open_sign.text = "OPEN\n⌈He was here tonight.⌋\n⌈The clerk is waiting.⌋"


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


func _on_clerk_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dialogue_runner.start("res://dialogues/store_clerk.json", "store_clerk")


func _on_clerk_dialogue_ended() -> void:
	# After clerk dialogue ends, transition to Underpass scene
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("set_flag"):
		gm.set_flag("completed_store", true)
	if scene_manager and scene_manager.has_method("trigger_scene_change"):
		scene_manager.trigger_scene_change(UNDERPASS_SCENE)


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if gm.has("choices_history") and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

extends Node3D
class_name NPCNode

enum NPCState {
	IDLE = 0,
	TALKING = 1,
	COOLDOWN = 2,
	EXHAUSTED = 3,
	SPECIAL = 4,
}

@export var dialogue_file: String = ""
@export var dialogue_id: String = ""
@export var speaker_name: String = "NPC"
@export var mood_axis: String = "hope_despair"
@export_range(0.5, 20.0, 0.1) var proximity_distance: float = 3.0
@export_range(0.5, 60.0, 0.5) var cooldown_seconds: float = 2.0
@export var name_label_visible: bool = true
@export var interaction_prompt_text: String = "⌈Talk⌋"
@export var personality_layers: Array[Dictionary] = []
@export var label_offset: Vector3 = Vector3(0, 1.5, 0)

signal npc_interacted(npc_id: String)
signal dialogue_completed(npc_id: String)
signal npc_state_changed(state: int)

var current_state: int = NPCState.IDLE
var active_layer: Dictionary = {}
var _trigger_area: Area3D
var _name_label: Label3D
var _prompt_label: Label3D
var _cooldown_timer: Timer
var _player_nearby: bool = false
var _greeting_override: String = ""
var _feedback_area: InteractiveArea = null

const _DialogueConditionEvaluator := preload("res://gdscripts/dialogue_condition_evaluator.gd")


func _ready() -> void:
	_trigger_area = $InteractionTrigger as Area3D
	_name_label = $VisualName as Label3D
	_prompt_label = $InteractionPrompt as Label3D
	_cooldown_timer = $CooldownTimer as Timer

	if _trigger_area:
		_trigger_area.body_entered.connect(_on_body_entered)
		_trigger_area.body_exited.connect(_on_body_exited)
		_trigger_area.input_event.connect(_on_interaction)

		var shape_owners: Array[Node] = _trigger_area.find_children("*", "CollisionShape3D", false)
		if shape_owners.size() > 0:
			var shape := (shape_owners[0] as CollisionShape3D).shape as CylinderShape3D
			if shape:
				shape.radius = proximity_distance
				shape.height = proximity_distance * 2.0

	if _cooldown_timer:
		_cooldown_timer.timeout.connect(_on_cooldown_timeout)
		_cooldown_timer.one_shot = true
		_cooldown_timer.wait_time = cooldown_seconds

	if _name_label:
		_name_label.visible = false
		_name_label.text = speaker_name
	if _prompt_label:
		_prompt_label.visible = false
		_prompt_label.text = interaction_prompt_text

	# Create InteractiveArea child for visual feedback
	_feedback_area = InteractiveArea.new()
	_feedback_area.name = "NPCFeedback"
	_feedback_area.feedback_mode = InteractiveArea.FeedbackMode.BOTH
	_feedback_area.indicator_texture = preload("res://assets/textures/icon_interact.webp")
	_feedback_area.glow_color = Color(0.667, 1.0, 0.867, 0.5)  # Teal-white for NPCs
	_feedback_area.proximity_distance = proximity_distance
	add_child(_feedback_area)


func _find_parent_dialogue_runner() -> Node:
	var scene_root := get_tree().current_scene
	if scene_root:
		var layer := scene_root.get_node_or_null("DialogueBalloonLayer")
		if layer and layer.get_child_count() > 0:
			return layer.get_child(0)
	return null


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		update_label_visibility()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		_name_label.visible = false
		_prompt_label.visible = false


func _on_interaction(camera: Camera3D, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and is_interactable():
		if dialogue_file.is_empty() or dialogue_id.is_empty():
			push_warning("NPCNode._on_interaction: dialogue_file or dialogue_id is empty")
			return
		evaluate_personality_layer()
		set_state(NPCState.TALKING)
		update_name_label()
		_show_dm_balloon(dialogue_file, _greeting_override if not _greeting_override.is_empty() else dialogue_id)
		npc_interacted.emit(name)


func start_npc_interaction() -> void:
	if not is_interactable():
		return
	if dialogue_file.is_empty() or dialogue_id.is_empty():
		push_warning("NPCNode.start_npc_interaction: dialogue_file or dialogue_id is empty")
		return
	evaluate_personality_layer()
	set_state(NPCState.TALKING)
	update_name_label()
	_show_dm_balloon(dialogue_file, _greeting_override if not _greeting_override.is_empty() else dialogue_id)
	npc_interacted.emit(name)


func _show_dm_balloon(dialogue_path: String, title: String) -> void:
	if DialogueBalloon._current_balloon and is_instance_valid(DialogueBalloon._current_balloon):
		return
	var resource = load(dialogue_path)
	if resource == null:
		push_error("NPCNode: Could not load dialogue resource: ", dialogue_path)
		set_state(NPCState.IDLE)
		return
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var balloon_scene := preload("res://scenes/dialogue/dialogue_balloon.tscn")
	var balloon := balloon_scene.instantiate() as DialogueBalloon
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "DialogueBalloonLayer"
	scene_root.add_child(canvas_layer)
	canvas_layer.add_child(balloon)
	balloon.dialogue_ended.connect(_on_dialogue_ended)
	balloon.start(resource, title, [get_node_or_null("/root/StateSystem")])


func evaluate_personality_layer() -> void:
	var state := _build_state_snapshot()
	var fallback_layer: Dictionary = {}
	for layer in personality_layers:
		var condition = layer.get("condition", {})
		# "always" type or empty condition = fallback (evaluated last)
		if condition.is_empty() or condition.get("type", "") == "always":
			if fallback_layer.is_empty():
				fallback_layer = layer
			continue
		if _DialogueConditionEvaluator.evaluate(condition, state):
			active_layer = layer
			_greeting_override = layer.get("greeting_override", "")
			return
	# No conditional layer matched — use the always-type fallback if available
	if not fallback_layer.is_empty():
		active_layer = fallback_layer
		_greeting_override = fallback_layer.get("greeting_override", "")
	else:
		active_layer = {}
		_greeting_override = ""


func _build_state_snapshot() -> Dictionary:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return {"sliders": {}, "flags": {}}
	var sliders := {}
	for axis in ["hope", "despair", "vigor", "burnout", "conviction", "falter", "hope_despair"]:
		if gm.has_method("get_slider"):
			sliders[axis] = gm.get_slider(axis)
	return {
		"sliders": sliders,
		"flags": gm.get_flags() if gm.has_method("get_flags") else {},
	}


func set_state(new_state: int) -> void:
	current_state = new_state
	npc_state_changed.emit(current_state)
	update_label_visibility()
	# Gate visual feedback during non-IDLE states
	if _feedback_area:
		_feedback_area.is_interactable = current_state == NPCState.IDLE


func update_name_label() -> void:
	if not name_label_visible:
		return
	var prefix: String = active_layer.get("name_prefix", "")
	if prefix != "":
		_name_label.text = prefix + speaker_name
	else:
		_name_label.text = speaker_name


func update_label_visibility() -> void:
	_name_label.visible = _player_nearby and name_label_visible
	_prompt_label.visible = _player_nearby and is_interactable()


func is_interactable() -> bool:
	return current_state == NPCState.IDLE and not dialogue_file.is_empty()


func _on_dialogue_ended() -> void:
	dialogue_completed.emit(name)
	set_state(NPCState.COOLDOWN)
	if _cooldown_timer:
		_cooldown_timer.start()


func _on_cooldown_timeout() -> void:
	set_state(NPCState.IDLE)


func _exit_tree() -> void:
	if _trigger_area:
		if _trigger_area.body_entered.is_connected(_on_body_entered):
			_trigger_area.body_entered.disconnect(_on_body_entered)
		if _trigger_area.body_exited.is_connected(_on_body_exited):
			_trigger_area.body_exited.disconnect(_on_body_exited)
		if _trigger_area.input_event.is_connected(_on_interaction):
			_trigger_area.input_event.disconnect(_on_interaction)
	if _cooldown_timer:
		_cooldown_timer.timeout.disconnect(_on_cooldown_timeout)

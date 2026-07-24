extends Node3D

# Main — CRPG entry scene script
# Handles keyboard input, connects to GameState, and boots the first scene

@onready var scene_manager: Node = $SceneManager
@onready var world_label: Label3D = $WorldLabel
@onready var state_system: Node = get_node("/root/GameState")
@onready var status_bar: CanvasLayer = $StatusBar

var _dialogue_active: bool = false

func _ready() -> void:
	if state_system:
		state_system.state_changed.connect(_on_state_changed)
	world_label.text = "Hope: 100  Despair: 0"
	print("CRPG Main Scene ready.")

	# Connect status bar to state changes
	if state_system != null and status_bar != null:
		state_system.state_changed.connect(status_bar._on_state_changed)

	# Connect viewport size changes to UIConfig
	var ui_config := get_node_or_null("/root/UIConfig")
	if ui_config != null:
		get_tree().root.size_changed.connect(_on_viewport_size_changed)

	# Delegate to SceneManager to load the starting scene
	call_deferred("_load_starting_scene")


func _load_starting_scene() -> void:
	get_tree().change_scene_to_file("res://scenes/office/office.tscn")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		if state_system:
			state_system.apply_state(5, 0)
	elif event.is_action_pressed("ui_down"):
		if state_system:
			state_system.apply_state(-5, 0)
	elif event.is_action_pressed("ui_right"):
		if state_system:
			state_system.apply_state(0, -5)
	elif event.is_action_pressed("ui_left"):
		if state_system:
			state_system.apply_state(0, 5)
	elif event.is_action_pressed("ui_accept"):
		if state_system:
			state_system.reset()
	elif event.is_action_pressed("ui_cancel"):
		print("Pause requested (placeholder)")
	
	# ----- Dialogue Input Handling -----
	elif event.is_action_pressed("toggle_dialogue"):
		_trigger_test_dialogue()

func _on_state_changed(state: Dictionary) -> void:
	pass


func _trigger_test_dialogue() -> void:
	var resource = load("res://dialogues/bartender.dialogue")
	if resource == null:
		push_error("Main: Could not load test dialogue resource")
		return
	var balloon_scene := preload("res://scenes/dialogue/dialogue_balloon.tscn")
	var balloon := balloon_scene.instantiate() as DialogueBalloon
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "DialogueBalloonLayer"
	add_child(canvas_layer)
	canvas_layer.add_child(balloon)
	balloon.start(resource, "bartender", [get_node_or_null("/root/StateSystem")])


func _on_viewport_size_changed() -> void:
	var ui_config := get_node_or_null("/root/UIConfig")
	if ui_config != null and is_instance_valid(ui_config):
		ui_config.recalculate()

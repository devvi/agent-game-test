extends Node3D

# Main — CRPG entry scene script
# Handles keyboard input, connects to GameState, and boots the first scene

@onready var scene_manager: Node = $SceneManager
@onready var world_label: Label3D = $WorldLabel
@onready var state_system: Node = get_node("/root/GameState")
@onready var dialogue_runner: Node = $Dialogue/DialoguePanel
@onready var dialogue_debug: Node = $DialogueDebug
@onready var dialogue_display_3d = $Dialogue3D
@onready var status_bar: CanvasLayer = $StatusBar

var _dialogue_active: bool = false

func _ready() -> void:
	if state_system:
		state_system.state_changed.connect(_on_state_changed)
	world_label.text = "Hope: 100  Despair: 0"
	print("CRPG Main Scene ready.")
	
	# Hide dialogue panel initially
	if dialogue_runner != null:
		dialogue_runner.hide()
	
	# Connect dialogue signals
	if dialogue_runner != null and is_instance_valid(dialogue_runner):
		dialogue_runner.dialogue_started.connect(_on_dialogue_started)
		dialogue_runner.dialogue_ended.connect(_on_dialogue_ended)
		dialogue_runner.node_changed.connect(_on_node_changed)
		dialogue_runner.choices_available.connect(_on_choices_available)
	
	# Wire up dialogue display 3D to dialogue runner signals
	if dialogue_runner != null and is_instance_valid(dialogue_runner) and dialogue_display_3d != null and is_instance_valid(dialogue_display_3d):
		dialogue_runner.node_changed.connect(dialogue_display_3d.on_node_changed)
		dialogue_runner.choices_available.connect(dialogue_display_3d.on_choices_available)
		dialogue_runner.dialogue_ended.connect(dialogue_display_3d.on_dialogue_ended)

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
		# Trigger dialogue for testing (F9)
		if dialogue_runner != null:
			dialogue_runner.show()
			dialogue_runner.start("res://dialogues/bartender.json", "bartender")
			_dialogue_active = true
			if dialogue_display_3d != null:
				dialogue_display_3d.show_dialogue()
	
	elif _dialogue_active and event.is_action_pressed("dialogue_up"):
		if dialogue_display_3d != null and dialogue_display_3d.has_method("navigate_up"):
			dialogue_display_3d.navigate_up()
	
	elif _dialogue_active and event.is_action_pressed("dialogue_down"):
		if dialogue_display_3d != null and dialogue_display_3d.has_method("navigate_down"):
			dialogue_display_3d.navigate_down()
	
	elif _dialogue_active and event.is_action_pressed("dialogue_select"):
		if dialogue_display_3d != null and dialogue_runner != null:
			var focused: int = dialogue_display_3d.get_focused_choice_index()
			dialogue_runner.select_choice(focused)
	
	elif _dialogue_active and event.is_action_pressed("dialogue_skip"):
		# Skip typewriter animation (placeholder)
		pass
	
	# Digit keys for direct choice selection
	elif _dialogue_active:
		for digit in range(4):
			if event.is_action_pressed("digit_%d" % (digit + 1)):
				if dialogue_runner != null:
					dialogue_runner.select_choice(digit)

func _on_state_changed(state: Dictionary) -> void:
	# Status bar is updated via signal connection — world_label is deprecated
	pass

# ===== Dialogue Integration =====

func _on_dialogue_started(dialogue_id: String) -> void:
	print("Dialogue started: ", dialogue_id)

func _on_dialogue_ended() -> void:
	print("Dialogue ended")
	_dialogue_active = false
	if dialogue_runner != null and is_instance_valid(dialogue_runner):
		dialogue_runner.hide()

func _on_node_changed(node_id: String, speaker: String, text: String) -> void:
	print("[%s] %s: %s" % [node_id, speaker, text])
	# Update debug overlay
	if dialogue_debug != null and is_instance_valid(dialogue_debug):
		dialogue_debug.update_display(dialogue_runner)

func _on_choices_available(choices: Array) -> void:
	print("Choices available: ", choices.size())
	for i in range(choices.size()):
		print("  %d. %s" % [i + 1, choices[i].get("text", "")])


func _on_viewport_size_changed() -> void:
	var ui_config := get_node_or_null("/root/UIConfig")
	if ui_config != null and is_instance_valid(ui_config):
		ui_config.recalculate()

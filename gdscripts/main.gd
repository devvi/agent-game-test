extends Node3D

# Main — CRPG entry scene script
# Handles keyboard input and connects to GameState

@onready var world_label: Label3D = $WorldLabel
@onready var state_system: Node = get_node("/root/GameState")
@onready var dialogue_runner: Node = $Dialogue/DialoguePanel
@onready var dialogue_debug: Node = $DialogueDebug

func _ready() -> void:
	if state_system:
		state_system.state_changed.connect(_on_state_changed)
	world_label.text = "Hope: 100  Despair: 0"
	print("CRPG Main Scene ready.")
	
	# Hide dialogue panel initially
	if dialogue_runner != null:
		dialogue_runner.hide()
	
	# Connect dialogue signals
	if dialogue_runner != null:
		dialogue_runner.dialogue_started.connect(_on_dialogue_started)
		dialogue_runner.dialogue_ended.connect(_on_dialogue_ended)
		dialogue_runner.node_changed.connect(_on_node_changed)
		dialogue_runner.choices_available.connect(_on_choices_available)

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
	elif event.is_action_pressed("toggle_dialogue"):
		# Trigger dialogue for testing (F9)
		if dialogue_runner != null:
			dialogue_runner.show()
			dialogue_runner.start("res://dialogues/bartender.json", "bartender")

func _on_state_changed(state: Dictionary) -> void:
	world_label.text = "Hope: " + str(state["hope"]) + "  Despair: " + str(state["despair"])

# ===== Dialogue Integration =====

func _on_dialogue_started(dialogue_id: String) -> void:
	print("Dialogue started: ", dialogue_id)

func _on_dialogue_ended() -> void:
	print("Dialogue ended")
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

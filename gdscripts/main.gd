extends Node3D

# Main — CRPG entry scene script
# Handles keyboard input and connects to GameState

@onready var world_label: Label3D = $WorldLabel
@onready var state_system: Node = get_node("/root/GameState")

func _ready() -> void:
    if state_system:
        state_system.state_changed.connect(_on_state_changed)
    world_label.text = "Hope: 100  Despair: 0"
    print("CRPG Main Scene ready.")

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

func _on_state_changed(state: Dictionary) -> void:
    world_label.text = "Hope: " + str(state["hope"]) + "  Despair: " + str(state["despair"])

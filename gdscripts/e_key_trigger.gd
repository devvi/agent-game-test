extends Area3D
class_name EKeyTrigger

# EKeyTrigger — Drop-in Area3D child for E-key interaction.
# Place as a child of a scene's trigger Area3D and connect e_key_interacted
# to the existing handler (e.g., _start_door_dialogue()).

signal e_key_interacted()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("interactable")


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_signal("interaction_requested"):
		if not body.interaction_requested.is_connected(_on_player_interact):
			body.interaction_requested.connect(_on_player_interact)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player") and body.has_signal("interaction_requested"):
		if body.interaction_requested.is_connected(_on_player_interact):
			body.interaction_requested.disconnect(_on_player_interact)


func _on_player_interact(_target: Node) -> void:
	if is_instance_valid(self):
		e_key_interacted.emit()

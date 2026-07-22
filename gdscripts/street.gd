extends Node

# Street scene script
# Configures neon, graffiti, and street sign text. Sets rain intensity.
# Uses 5-state hope/despair mapping for environmental text variants.
# Connects store entrance trigger.

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var neon_sign: Node3D = $Environments/NeonSign
@onready var graffiti: Node3D = $Environments/Graffiti
@onready var street_sign: Node3D = $Environments/StreetSign
@onready var store_entrance: Area3D = $InteractionZones/StoreEntranceTrigger


func _ready() -> void:
	scene_manager.fade_in()
	_configure_environmental_text()
	store_entrance.input_event.connect(_on_store_entrance_input)
	_restore_dialogue_state()


func _configure_environmental_text() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return
	var hope_despair: float = gm.get_slider("hope_despair")
	var state_id: int = _hope_despair_to_state_id(hope_despair)
	var conviction: float = gm.get_slider("conviction")

	# Neon sign: conviction-based glow with hope_despair influence
	_neon_sign_update(neon_sign, state_id, conviction)

	# Graffiti: 5-state text variants
	var graffiti_variants: Array = [
		"nothing matters",           # Despair
		"why am i here",             # Low
		"i was here",                # Neutral
		"this too shall pass",       # Buoyant
		"we are still here"          # Hope
	]
	graffiti.text = get_variant(state_id, graffiti_variants)
	# Opacity increases with hope
	var alpha: float = 0.2 + (state_id - 1) * 0.15
	graffiti.modulate = Color(1, 1, 1, clampf(alpha, 0.2, 1.0))

	# Street sign is static
	street_sign.text = "ELM ST."


func _neon_sign_update(neon: Node3D, state_id: int, conviction: float) -> void:
	# Combine conviction (base glow) with hope/despair (tone)
	match state_id:
		1:  # Despair — dim red
			neon.modulate = Color(0.8, 0.1, 0.1)
		2:  # Low — dim red-orange
			neon.modulate = Color(0.9, 0.3, 0.1)
		3:  # Neutral — dim amber
			neon.modulate = Color(1.0, 0.6, 0.1)
		4:  # Buoyant — warm amber (with conviction boost)
			if conviction >= 7.0:
				neon.modulate = Color(1.0, 0.8, 0.3)
			else:
				neon.modulate = Color(1.0, 0.7, 0.2)
		5:  # Hope — bright gold
			neon.modulate = Color(1.0, 0.9, 0.4)
		_:
			neon.modulate = Color(1.0, 0.6, 0.1)


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


func _on_store_entrance_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dialogue_runner.start("res://dialogues/office_door.json", "store_entrance")


func _restore_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and dialogue_runner.choices_made.is_empty():
		if gm.has("choices_history") and not gm.choices_history.is_empty():
			dialogue_runner.choices_made = gm.choices_history.duplicate()

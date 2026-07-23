extends SceneBase
class_name UnderpassScene

# Underpass scene — Stranger (echo dialogue), graffiti wall (memory flashback), echo triggers.

@onready var graffiti_text: Node3D = $Environments/GraffitiText
@onready var echo_text: Node3D = $Environments/EchoText
@onready var underpass_light: Node3D = $Environments/UnderpassLight
@onready var graffiti_trigger: Area3D = $InteractionZones/GraffitiTrigger
@onready var stranger_echo_trigger: Area3D = $InteractionZones/StrangerEchoTrigger
@onready var exit_trigger: Area3D = $InteractionZones/UnderpassExitTrigger


func _ready() -> void:
	scene_id = "underpass"
	super._ready()
	if graffiti_trigger:
		graffiti_trigger.input_event.connect(_on_graffiti_trigger_input)
	if stranger_echo_trigger:
		stranger_echo_trigger.input_event.connect(_on_stranger_echo_trigger_input)
	if exit_trigger:
		exit_trigger.input_event.connect(_on_exit_trigger_input)
	
	# Check for echo triggers
	call_deferred("_check_echoes")
	# Check AC3 hidden text condition
	call_deferred("_check_hidden_text")


func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


func _configure_environmental_text() -> void:
	var tone := _get_tone()
	_set_environment_text(tone)


func _get_tone() -> String:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if not ss:
		return "neutral"
	var state := ss.get_state()
	var hope_val: float = state.get("hope", 5.0)
	var conviction_val: float = state.get("conviction", 5.0)
	if hope_val <= 4.0 and conviction_val <= 4.0:
		return "despair"
	elif hope_val >= 6.0 and conviction_val >= 6.0:
		return "resolute"
	else:
		return "neutral"


func _set_environment_text(tone: String) -> void:
	match tone:
		"despair":
			graffiti_text.text = "The walls are covered in faded tags.\nNone of them say anything you remember."
			underpass_light.text = "The flickering light casts long shadows."
		"resolute":
			graffiti_text.text = "Colorful tags cover the walls.\nSomeone wrote 'keep going' in red."
			underpass_light.text = "The tunnel is dim but clear.\nYou can see the other end."
		_:
			graffiti_text.text = "Graffiti covers the underpass walls.\nTags and faded messages."
			underpass_light.text = "A single fluorescent light buzzes overhead."


func _check_echoes() -> void:
	var nm: Node = get_node_or_null("/root/NarrativeManager")
	if nm and nm.has_method("trigger_echo"):
		# Trigger screensaver echo if not yet triggered
		if not nm.echo_flags.get("screensaver_echo", false):
			nm.trigger_echo("screensaver_echo")
		
		# Set echo text if echo was triggered
		if nm.echo_flags.get("rain_echo", false) or nm.echo_flags.get("screensaver_echo", false):
			if echo_text:
				if nm.echo_flags.get("rain_echo", false):
					echo_text.visible = true
				if nm.echo_flags.get("screensaver_echo", false):
					# Screensaver echo also shows here
					echo_text.text = "\"你做游戏有什么用？\"\nThe words echo in the tunnel."


## AC3 hidden text: When hope ≤ 2.0 AND conviction ≤ 2.0,
## reveal Stranger as a projection of the player's psyche.
func _check_hidden_text() -> void:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if not ss:
		return
	var hope_val: float = ss.hope if ss else 5.0
	var conviction_val: float = ss.conviction if ss else 5.0
	
	if hope_val <= 2.0 and conviction_val <= 2.0:
		if echo_text:
			echo_text.visible = true
			echo_text.text = "⌈你看到的不是别人——\n是你的影子。⌋\nThe stranger was never there."


func _on_graffiti_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Memory flashback — state-aware
		var ss: Node = get_node_or_null("/root/StateSystem")
		var hope_val: float = ss.hope if ss else 5.0
		if hope_val >= 6.0:
			graffiti_text.text = "A tag reads '2019'. You remember that year.\nThings were simpler."
		else:
			graffiti_text.text = "One tag is scratched out.\nYou can't read it. Doesn't matter."


func _on_stranger_echo_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Trigger the rain echo if not yet done
		var nm: Node = get_node_or_null("/root/NarrativeManager")
		if nm and nm.has_method("trigger_echo"):
			nm.trigger_echo("rain_echo")
		
		# AC3: Set is_new_game_plus flag for dialogue conditions (Issue #59)
		var gm: Node = get_node_or_null("/root/GameManager")
		if gm and gm.has_method("get_playthrough_count"):
			if gm.get_playthrough_count() >= 2:
				if nm and nm.has_method("set_flag"):
					nm.set_flag("is_new_game_plus", true)
		
		# Set extreme-state flags for AC2 dialogue variants
		var ss: Node = get_node_or_null("/root/StateSystem")
		if ss:
			var hope_val: float = ss.hope if ss else 5.0
			var conviction_val: float = ss.conviction if ss else 5.0
			if hope_val >= 9.0 and nm and nm.has_method("set_flag"):
				nm.set_flag("underpass_hope_high", true)
			if hope_val <= 2.0 and nm and nm.has_method("set_flag"):
				nm.set_flag("underpass_hope_low", true)
		
		start_dialogue("res://dialogues/underpass_stranger_echo.json", "underpass_stranger_echo")


func _on_exit_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var nm: Node = get_node_or_null("/root/NarrativeManager")
		if nm and nm.has_method("advance_scene"):
			nm.advance_scene()

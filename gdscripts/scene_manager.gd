extends Node

# SceneManager — Scene transition orchestrator
# Handles fade-to-black transitions triggered by dialogue choices.
# Lives in every scene as a child of the scene root.

signal transition_started(target_scene: String)
signal transition_completed()

## Prevents rapid scene-switching during fade animation
var transition_in_progress: bool = false

## The fade curtain CanvasLayer node
var _fade_curtain: CanvasLayer
var _fade_anim: AnimationPlayer


func _ready() -> void:
	_setup_fade_curtain()
	_connect_to_dialogue()


func _setup_fade_curtain() -> void:
	# Look for existing FadeCurtain in the current scene root
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	if scene_root.has_node("FadeCurtain"):
		_fade_curtain = scene_root.get_node("FadeCurtain")
	else:
		_fade_curtain = _create_fade_curtain()
		scene_root.add_child(_fade_curtain)
	_fade_anim = _fade_curtain.get_node("AnimationPlayer")


func _create_fade_curtain() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = "FadeCurtain"
	cl.layer = 128  # Above dialogue layer

	var rect := ColorRect.new()
	rect.name = "ColorRect"
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.modulate = Color(0, 0, 0, 0)  # Start transparent
	cl.add_child(rect)

	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	cl.add_child(anim)

	# Create fade_out animation
	var anim_out := Animation.new()
	anim_out.length = 0.5
	var track_out := anim_out.add_track(Animation.TYPE_VALUE)
	anim_out.track_set_path(track_out, "ColorRect:modulate")
	anim_out.track_insert_key(track_out, 0.0, Color(0, 0, 0, 0))
	anim_out.track_insert_key(track_out, 0.5, Color(0, 0, 0, 1))
	anim.add_animation("fade_out", anim_out)

	# Create fade_in animation (reverse of fade_out)
	var anim_in := Animation.new()
	anim_in.length = 0.5
	var track_in := anim_in.add_track(Animation.TYPE_VALUE)
	anim_in.track_set_path(track_in, "ColorRect:modulate")
	anim_in.track_insert_key(track_in, 0.0, Color(0, 0, 0, 1))
	anim_in.track_insert_key(track_in, 0.5, Color(0, 0, 0, 0))
	anim.add_animation("fade_in", anim_in)

	return cl


func _connect_to_dialogue() -> void:
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	var dr = scene_root.get_node_or_null("CanvasLayer/DialoguePanel")
	if dr and dr.has_signal("choice_made"):
		dr.choice_made.connect(_on_choice_made)


## Handle choices that trigger scene transitions.
## Scene transitions are encoded in choice metadata: { "scene": "res://..." }
func _on_choice_made(choice_index: int, choice_text: String) -> void:
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	var dr = scene_root.get_node_or_null("CanvasLayer/DialoguePanel")
	if not dr or not is_instance_valid(dr):
		return
	var current: Dictionary = dr.current_node
	var choices: Array = current.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var choice: Dictionary = choices[choice_index]
	if choice.has("scene") and choice["scene"] != null and str(choice["scene"]) != "":
		trigger_scene_change(choice["scene"])


## Trigger a scene change with fade transition.
## Persists dialogue state to GameManager before changing scenes.
func trigger_scene_change(target_scene: String, fade_duration: float = 0.5) -> void:
	if transition_in_progress:
		return
	transition_in_progress = true
	transition_started.emit(target_scene)

	var target_scene_id := target_scene.get_file().get_basename()
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("cross_fade_ambient"):
		am.cross_fade_ambient(target_scene_id)

	# Persist dialogue choices_made to GameManager
	_persist_dialogue_state()

	# Fade out
	_fade_anim.play("fade_out", -1, 1.0, false)
	await _fade_anim.animation_finished

	# Change scene
	var err: int = get_tree().change_scene_to_file(target_scene)
	if err != OK:
		push_error("SceneManager: Failed to change to scene: ", target_scene)
		transition_in_progress = false
		return

	# Fade-in is handled by the new scene's SceneManager


## Persist dialogue choices_made array to GameManager autoload.
func _persist_dialogue_state() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	var dr = scene_root.get_node_or_null("CanvasLayer/DialoguePanel")
	if gm and dr:
		gm.set("choices_history", dr.choices_made.duplicate())


## Called by the new scene after its _ready() to fade in.
func fade_in(fade_duration: float = 0.5) -> void:
	if not transition_in_progress:
		return
	_fade_anim.play("fade_in", -1, 1.0, false)
	await _fade_anim.animation_finished
	transition_in_progress = false
	transition_completed.emit()

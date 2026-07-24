extends Node
class_name NavFallback

# NavFallback — Handles player falling out of bounds or getting stuck in geometry.
# Attached as a child of each scene root. Works with the scene's SceneManager
# and PlayerController for fallback teleport to SpawnPoint.
#
# Detections:
#   - Height fall: player.global_position.y < -10.0
#   - Stuck in geometry: velocity.length() < 0.01 for 3s continuous (non-dialogue)
#   - Fallback loop protection: 3 consecutive fallbacks → force title_screen

const Constants = preload("res://gdscripts/constants.gd")

# References set by SceneBase._ready()
var _player: Node = null
var _spawn_point: Vector3 = Vector3.ZERO

# Internal state
var _stuck_timer: float = 0.0
var _is_fallbacking: bool = false
var _fallback_count: int = 0


func _ready() -> void:
	name = "NavFallback"


func _physics_process(delta: float) -> void:
	if _is_fallbacking or _player == null:
		return

	# Skip detection during dialogue
	var dialogue_active = false
	if _player.has_method("get"):
		dialogue_active = _player.get("_dialogue_active")
	if dialogue_active:
		_stuck_timer = 0.0
		return

	# 1. Height fall detection
	if _player.global_position.y < Constants.NAV_FALLBACK_Y_THRESHOLD:
		_trigger_fallback("fell")
		return

	# 2. Stuck detection (near-zero velocity for NAV_STUCK_DURATION seconds)
	var vel = _player.get("velocity")
	if vel != null and vel is Vector3 and vel.length() < Constants.NAV_STUCK_VELOCITY_THRESHOLD:
		_stuck_timer += delta
		if _stuck_timer >= Constants.NAV_STUCK_DURATION:
			_trigger_fallback("stuck")
	else:
		_stuck_timer = 0.0


## Set the player reference for fallback teleport.
func set_player(player_node: Node) -> void:
	_player = player_node


## Set the spawn point position for teleport destination.
func set_spawn_point(pos: Vector3) -> void:
	_spawn_point = pos


## Get the current fallback count.
func get_fallback_count() -> int:
	return _fallback_count


## Reset the fallback counter (called when player exits scene normally).
func reset_fallback_counter() -> void:
	_fallback_count = 0


## Trigger a fallback teleport for the given reason ("fell" or "stuck").
func _trigger_fallback(reason: String) -> void:
	_is_fallbacking = true
	_stuck_timer = 0.0

	var gm := get_node_or_null("/root/GameManager")
	if gm:
		# Increment fallback counter
		var fb_count: int = gm.get("fallback_count") + 1
		gm.set("fallback_count", fb_count)
		_fallback_count = fb_count

		# Fallback loop protection
		if fb_count >= Constants.NAV_FALLBACK_MAX:
			_force_title_screen(gm)
			return

	# Get SceneManager for fade
	var sm := get_parent().get_node_or_null("SceneManager")

	# Quick fade out
	if sm and sm.has_method("fade_in"):
		# Use the fade curtain directly
		var fade_curtain = _get_fade_curtain(sm)
		if fade_curtain:
			var color_rect = fade_curtain.get_node_or_null("ColorRect")
			if color_rect:
				color_rect.modulate = Color(0, 0, 0, 0)
				_animate_modulate(color_rect, Color(0, 0, 0, 1), Constants.NAV_FALLBACK_FADE_DURATION)

	await get_tree().create_timer(Constants.NAV_FALLBACK_FADE_DURATION).timeout

	# Teleport player to spawn point
	if _player:
		_player.global_position = _spawn_point
		if _player.has_method("set_velocity"):
			_player.set("velocity", Vector3.ZERO)
		elif "velocity" in _player:
			_player.set("velocity", Vector3.ZERO)

	# Show fallback feedback text
	_print_fallback_feedback(reason)

	# Quick fade in
	var sm2 := get_parent().get_node_or_null("SceneManager")
	if sm2:
		var fade_curtain = _get_fade_curtain(sm2)
		if fade_curtain:
			var color_rect = fade_curtain.get_node_or_null("ColorRect")
			if color_rect:
				_animate_modulate(color_rect, Color(0, 0, 0, 0), Constants.NAV_FALLBACK_FADE_DURATION)

	await get_tree().create_timer(Constants.NAV_FALLBACK_FADE_DURATION).timeout

	_is_fallbacking = false


## Force-load the title screen after max consecutive fallbacks.
func _force_title_screen(gm: Node) -> void:
	push_warning("NavFallback: Max consecutive fallbacks reached — forcing title screen")
	gm.reset()
	get_tree().change_scene_to_file(Constants.SCENE_TITLE)


## Get the fade curtain CanvasLayer from SceneManager.
func _get_fade_curtain(sm: Node):
	if sm.has_method("_setup_fade_curtain"):
		sm._setup_fade_curtain()
	if "get_node" in sm and sm.has_method("get_node"):
		return sm.get_node_or_null("FadeCurtain")
	# Fallback: search children
	for child in sm.get_children():
		if child is CanvasLayer and child.name == "FadeCurtain":
			return child
	return null


## Animate modulate from start to end over duration (simple tween).
func _animate_modulate(node: Node, target: Color, duration: float) -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(node, "modulate", target, duration)


## Print fallback feedback text (Hemingway-constrained).
func _print_fallback_feedback(reason: String) -> void:
	match reason:
		"fell":
			print("[NavFallback] …刚才有些恍惚？/ 我已经站在这里了。")
		"stuck":
			print("[NavFallback] ……/ 这路有点不对劲。/ 换一边走。")
		_:
			print("[NavFallback] 回到原点。")

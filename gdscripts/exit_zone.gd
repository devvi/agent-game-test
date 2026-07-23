extends Area3D
class_name ExitZone

# ExitZone — Reusable Area3D component for scene-to-scene transitions.
# Place at doorways / area boundaries. Supports AUTO (walk in → transition)
# and EKEY (walk in → press E → transition) modes.
#
# Usage: Add as a child of any scene root. Configure target_scene, spawn_point,
# and transition_mode. Optionally set prompt_text for EKEY mode.
#
# Node structure:
#   ExitZone (Area3D)
#     ├── CollisionShape3D (BoxShape3D — 0.5m 2m 3m)
#     └── PromptLabel (Label3D) — auto-created if prompt_text is set

const TRANSITION_MODE_AUTO := 0
const TRANSITION_MODE_EKEY := 1

## Path to destination .tscn file (e.g., "res://scenes/street/street.tscn")
@export var target_scene: String = ""
## Player spawn position in the destination scene's local space
@export var spawn_point: Vector3 = Vector3.ZERO
## AUTO=0: instant on body_entered. EKEY=1: player must press E.
@export var transition_mode: int = TRANSITION_MODE_AUTO
## Optional prompt text shown when player is inside zone (EKEY mode only)
@export var prompt_text: String = ""
## Seconds to ignore re-trigger after auto-trigger fires
@export var cooldown: float = 1.0

var _prompt_label: Label3D = null
var _cooldown_timer: Timer = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Defer monitoring for 0.5s to prevent spawn-inside-zone triggers
	monitoring = false
	await get_tree().create_timer(0.5).timeout
	monitoring = true

	_validate_config()

	# Create prompt label if text is provided
	if not prompt_text.is_empty():
		_prompt_label = Label3D.new()
		_prompt_label.name = "PromptLabel"
		_prompt_label.text = prompt_text
		_prompt_label.visible = false
		_prompt_label.position = Vector3(0, 2.5, 0)  # Above the zone
		add_child(_prompt_label)

	# Create cooldown timer for AUTO mode
	_cooldown_timer = Timer.new()
	_cooldown_timer.name = "CooldownTimer"
	_cooldown_timer.one_shot = true
	_cooldown_timer.wait_time = cooldown
	add_child(_cooldown_timer)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	# Skip if transition is already in progress
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.get("transition_in_progress"):
		return

	match transition_mode:
		TRANSITION_MODE_AUTO:
			_auto_transition()
		TRANSITION_MODE_EKEY:
			_show_prompt()
			if body.has_signal("interaction_requested"):
				if not body.interaction_requested.is_connected(_on_player_interact):
					body.interaction_requested.connect(_on_player_interact)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	_hide_prompt()
	if body.has_signal("interaction_requested"):
		if body.interaction_requested.is_connected(_on_player_interact):
			body.interaction_requested.disconnect(_on_player_interact)


func _on_player_interact(_target: Node) -> void:
	if not is_instance_valid(self):
		return
	_transition()


func _auto_transition() -> void:
	# Cooldown guard — prevents double-trigger on rapid re-entry
	if _cooldown_timer and _cooldown_timer.time_left > 0:
		return
	if _cooldown_timer:
		_cooldown_timer.start()
	_transition()


func _transition() -> void:
	if target_scene.is_empty():
		push_warning("ExitZone: target_scene is empty — cannot transition")
		return

	var sm := get_parent().get_node_or_null("SceneManager")
	if not sm or not sm.has_method("trigger_zone_transition"):
		push_error("ExitZone: SceneManager not found on parent — cannot transition")
		return

	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.set("target_spawn_point", spawn_point)

	sm.trigger_zone_transition(target_scene)


func _show_prompt() -> void:
	if _prompt_label:
		_prompt_label.visible = true


func _hide_prompt() -> void:
	if _prompt_label:
		_prompt_label.visible = false


func _validate_config() -> void:
	if not has_node("CollisionShape3D"):
		push_warning("ExitZone '%s': No CollisionShape3D child found. body_entered will never fire." % name)
	if target_scene.is_empty():
		push_warning("ExitZone '%s': target_scene is empty." % name)

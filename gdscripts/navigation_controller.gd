extends Node
class_name NavigationController

# NavigationController — Per-scene navigation orchestrator (Issue #226)
# Manages condition timers (stay >60s, wrong direction >30s), H-key hint routing,
# stuck detection, height fall detection, and nearest-exit scanning.
#
# Created by SceneBase._setup_navigation() during _ready().
# Runs as a child node of the scene root.

# ── Signals ──
signal navigation_hint_requested(text: String)      # H-key pressed → hint text to display
signal fallback_triggered(reason: String)            # "fell" or "stuck"
signal condition_text_updated(direction_hint: String) # Stay/wrong-dir triggered text

# ── H-Key Hint Text Templates ──
# Keyed by scene_id → tone_name → hint_text
const HINT_TEXT_TEMPLATES: Dictionary = {
	"office": {
		"despair":    "The door is ahead. / Go outside. / Nothing else.",
		"low":        "The door. / Still there. / Same as before.",
		"neutral":    "The door is ahead. / Go outside.",
		"buoyant":    "The door. / Outside is waiting. / Come on.",
		"hope":       "The door. / The city is waiting. / Let's go.",
	},
	"lobby": {
		"fear":       "Not that way. / Maybe stay.",
		"uneasy":     "Is this the right way? / Hard to tell.",
		"neutral":    "The stranger points. / That door.",
		"curious":    "That door. / See what's there.",
		"defiant":    "The stranger. / That door. / Keep walking.",
	},
	"convenience_store": {
		"cold":       "Back door glows. / Both ways go.",
		"distant":    "Doesn't matter. / Any direction.",
		"neutral":    "The back door glows. / Keep going.",
		"warm":       "Warm light ahead. / Keep walking.",
		"glowing":    "The light is warm. / Go toward it.",
	},
	"bridge": {
		"tired":      "One more span. / Then rest.",
		"heavy":      "The door is heavy. / Push through.",
		"neutral":    "The other side. / City lights ahead.",
		"hopeful":    "Light ahead. / Come see.",
		"determined": "This way. / No question.",
	},
	"underpass": {
		"despair":    "Keep going. / Nothing else to do.",
		"hollow":     "That way. / Or stay.",
		"neutral":    "The exit light. / Almost there.",
		"resolute":   "This way. / No question.",
		"transcendent": "The exit is there. / You know it.",
	},
	"subway_station": {
		"backward":   "Back. / That's the way.",
		"hesitant":   "Maybe here. / Maybe not.",
		"waiting":    "The bench is dry. / No rush.",
		"forward":    "The train is coming. / Get on.",
	},
}

const GENERIC_HINT: String = "The exit is nearby. / Look around."

# ── Stay/Wrong-Dir Warning Text (per scene) ──
const STAY_WARNING_TEXT: Dictionary = {
	"office":            "You've been here a while. / The door is still there.",
	"lobby":             "The lobby echoes. / You've been standing here.",
	"street":            "Rain keeps falling. / Stores are closed.",
	"convenience_store": "The hum of the cooler. / You've been browsing long.",
	"bridge":            "Wind picks up. / The bridge shakes slightly.",
	"underpass":         "Tunnel breathes. / Still.",
	"subway_station":    "The platform is empty. / Train hasn't come.",
}

const WRONG_DIR_WARNING_TEXT: Dictionary = {
	"office":            "The door is behind you. / Turn around.",
	"lobby":             "That's the wall. / The exit is the other way.",
	"street":            "Store is that way. / Or back the way you came.",
	"convenience_store": "Back door is behind. / Street exit ahead.",
	"bridge":            "City lights are that way. / Turn.",
	"underpass":         "Exit light is the other end. / Walk toward it.",
	"subway_station":    "Gate is behind you. / Platform ahead.",
}

const GENERIC_STAY_WARNING: String = "You've been here a while. / The exit is somewhere."
const GENERIC_WRONG_DIR_WARNING: String = "Maybe the other way. / Try turning around."

# ── State ──
var scene_id: String = ""
var _player: Node = null
var _spawn_point: Vector3 = Vector3.ZERO
var _stay_triggered: bool = false
var _wrong_dir_triggered: bool = false
var _hint_cooldown: float = 0.0
var _stuck_timer: float = 0.0
var _wrong_dir_timer: float = 0.0
var _stay_timer: float = 0.0
var _last_player_pos: Vector3 = Vector3.ZERO
var _is_fallbacking: bool = false
var _dialogue_active: bool = false
var _has_setup: bool = false

# ── Navigation Constants (mirrored from constants.gd) ──
const NAV_STAY_THRESHOLD: float = 60.0
const NAV_WRONG_DIR_THRESHOLD: float = 30.0
const NAV_STUCK_VELOCITY_THRESHOLD: float = 0.01
const NAV_STUCK_DURATION: float = 3.0
const NAV_HINT_COOLDOWN: float = 8.0
const NAV_HINT_DISPLAY_DURATION: float = 5.0
const NAV_FALLBACK_Y_THRESHOLD: float = -10.0
const NAV_EXIT_ZONE_SCAN_RADIUS: float = 10.0

# ── Public API ──

## Called by SceneBase._setup_navigation().
## Sets player reference, spawn point, resets all timers and one-shot flags.
func _setup(player: Node, spawn_point: Vector3) -> void:
	_player = player
	_spawn_point = spawn_point
	_clear_timers()
	_last_player_pos = player.global_position if player else Vector3.ZERO
	_has_setup = true
	_hint_cooldown = 0.0


## Reset all condition timers and one-shot flags. Called on scene setup and fallback.
func _clear_timers() -> void:
	_stay_timer = 0.0
	_wrong_dir_timer = 0.0
	_stuck_timer = 0.0
	_stay_triggered = false
	_wrong_dir_triggered = false


## Called by dialogue system to update dialogue active state.
## When dialogue is active, condition timers are paused and H-key is blocked.
func set_dialogue_active(active: bool) -> void:
	_dialogue_active = active


# ── Physics Process ──

func _physics_process(delta: float) -> void:
	if not _has_setup or not _player or not is_instance_valid(_player):
		return

	# Skip all checks during fallback or dialogue
	if _is_fallbacking or _dialogue_active:
		# Reset stuck/wrong_dir timers during dialogue (pause condition detection)
		_stuck_timer = 0.0
		_wrong_dir_timer = 0.0
		return

	# 1. Update stay timer
	_stay_timer += delta

	# 2. Calculate player velocity from position delta
	var current_pos: Vector3 = _player.global_position
	var velocity: Vector3 = (current_pos - _last_player_pos) / delta if delta > 0 else Vector3.ZERO
	var speed: float = velocity.length()

	# 3. Stuck detection
	if speed < NAV_STUCK_VELOCITY_THRESHOLD:
		_stuck_timer += delta
		if _stuck_timer >= NAV_STUCK_DURATION and not _is_fallbacking:
			_is_fallbacking = true
			fallback_triggered.emit("stuck")
			# _clear_timers will be called by SceneBase after fallback resolves
	else:
		_stuck_timer = 0.0

	# 4. Height fall detection
	if current_pos.y < NAV_FALLBACK_Y_THRESHOLD and not _is_fallbacking:
		_is_fallbacking = true
		fallback_triggered.emit("fell")

	# 5. Stay warning (>60s standing in place — player hasn't moved significantly)
	if _stay_timer >= NAV_STAY_THRESHOLD and not _stay_triggered:
		_stay_triggered = true
		condition_text_updated.emit(_get_stay_warning_text())

	# 6. Wrong direction detection (>30s not facing nearest exit)
	var facing_exit: bool = _check_facing_exit()
	if not facing_exit:
		_wrong_dir_timer += delta
		if _wrong_dir_timer >= NAV_WRONG_DIR_THRESHOLD and not _wrong_dir_triggered:
			_wrong_dir_triggered = true
			condition_text_updated.emit(_get_wrong_dir_text())
	else:
		# Reset wrong-dir timer when player corrects direction
		_wrong_dir_timer = 0.0
		_wrong_dir_triggered = false

	# 7. Hint cooldown
	if _hint_cooldown > 0:
		_hint_cooldown = max(0.0, _hint_cooldown - delta)

	# 8. Update last position
	_last_player_pos = current_pos


# ── H-Key Hint Handling ──

## Called when PlayerController.navigation_hint_requested signal is received.
func _handle_hint_key() -> void:
	if _hint_cooldown > 0:
		return  # Cooldown active
	if _dialogue_active:
		return  # Blocked during dialogue

	var hint_text: String = _get_hint_text()
	navigation_hint_requested.emit(hint_text)
	_hint_cooldown = NAV_HINT_COOLDOWN


## Get tone-aware hint text for the current scene and state.
func _get_hint_text() -> String:
	if scene_id.is_empty():
		return GENERIC_HINT

	# Get current tone from NarrativeManager
	var tone: String = _get_current_tone()
	var scene_hints: Dictionary = HINT_TEXT_TEMPLATES.get(scene_id, {})
	return scene_hints.get(tone, GENERIC_HINT)


## Query NarrativeManager for current scene tone.
func _get_current_tone() -> String:
	var nm := get_node_or_null("/root/NarrativeManager")
	if not nm or not nm.has_method("_calculate_tone_for_scene"):
		return "neutral"

	var ss := get_node_or_null("/root/StateSystem")
	if not ss or not ss.has_method("get_state"):
		return "neutral"

	var state: Dictionary = ss.get_state()
	var idx: int = nm.SCENE_ORDER.find(scene_id)
	if idx < 0:
		return "neutral"

	return nm._calculate_tone_for_scene(idx, state)


# ── Stay/Wrong-Dir Text ──

func _get_stay_warning_text() -> String:
	return STAY_WARNING_TEXT.get(scene_id, GENERIC_STAY_WARNING)


func _get_wrong_dir_text() -> String:
	return WRONG_DIR_WARNING_TEXT.get(scene_id, GENERIC_WRONG_DIR_WARNING)


# ── Exit Zone Detection ──

## Check if the player is facing toward the nearest ExitZone.
## Returns true if facing an ExitZone within scan radius.
func _check_facing_exit() -> bool:
	var exit_zone := _get_nearest_exit_zone()
	if not exit_zone or not is_instance_valid(exit_zone):
		return true  # No exit zones → assume correct direction (don't nag)

	var exit_pos: Vector3 = exit_zone.global_position
	var player_pos: Vector3 = _player.global_position
	var dist: float = player_pos.distance_to(exit_pos)

	if dist > NAV_EXIT_ZONE_SCAN_RADIUS:
		return false  # Too far from any exit

	# Check if player is facing toward the exit
	var to_exit: Vector3 = (exit_pos - player_pos).normalized()
	# Use the player's forward direction (CharacterBody3D -Z is forward)
	var player_basis: Basis = _player.global_transform.basis
	var forward: Vector3 = -player_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var dot: float = forward.dot(to_exit)
	return dot > 0.3  # Within ~72° of facing the exit


## Find the nearest ExitZone Area3D in the scene.
func _get_nearest_exit_zone() -> Node:
	var parent := get_parent()
	if not parent:
		return null

	var nearest_exit: Node = null
	var nearest_dist: float = INF

	var parent_pos: Vector3 = parent.global_position if parent.has_method(&"get_global_position") else (_player.global_position if _player else Vector3.ZERO)

	# Search scene for ExitZone nodes
	for child in parent.get_children():
		if _is_exit_zone(child):
			var exit_pos: Vector3 = child.global_position
			var dist: float = parent_pos.distance_to(exit_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_exit = child

	return nearest_exit


## Check if a node is an ExitZone by checking its script.
func _is_exit_zone(node: Node) -> bool:
	if not node.has_method(&"_transition") and not node.has_method(&"get_class_name"):
		# Try checking the node name pattern or script type
		pass
	# ExitZone nodes typically have these exported properties
	if node.has_method(&"_validate_config") or node.has_method(&"_on_body_entered"):
		return true
	# Check by node type
	if node.is_in_group(&"exit_zone") or node.name.begins_with("ExitZone"):
		return true
	return false

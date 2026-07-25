extends Node
class_name SceneBase

# SceneBase — Base class for all scene scripts (Issue #45)
# Provides common behavior: fade-in, player instantiation, state-aware text config,
# dialogue state restoration, and player state persistence across scene transitions.
#
# Extended for Issue #150: Camera orbit state save/restore for third-person camera.
# Extended for Issue #226: Navigation system — NavigationController wiring, H-key hints,
# condition-triggered environmental text, hallucination level updates, route progress.

const PLAYER_CONTROLLER: GDScript = preload("res://gdscripts/player_controller.gd")

@onready var scene_manager: Node = $SceneManager
@onready var navigation_controller: Node = $NavigationController

var scene_id: String = ""  # Override in subclass
var _player: Node = null   # PlayerController instance (Issue #142)

# Scene navigation (Issue #226)
@export var scene_title_chinese: String = ""       # Chinese scene name for overlay
@export var enable_navigation: bool = true          # Toggle navigation system per-scene
@export var scene_progress_total: int = 6           # Total scenes for progress calculation


func _ready() -> void:
	if scene_manager and scene_manager.has_method("fade_in"):
		scene_manager.fade_in()
	_instantiate_player()
	_configure_environmental_text()
	_configure_ambient_audio()
	_connect_state_signals()
	_setup_navigation()
	_update_hallucination_on_scene_entry()
	_update_route_progress()
	_restore_dialogue_state()

func _exit_tree() -> void:
	_save_player_state()


## Override in subclass: configure all environmental text for this scene (state-aware).
func _configure_environmental_text() -> void:
	pass


## Override in subclass: configure ambient audio for this scene.
func _configure_ambient_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("register_scene"):
		am.register_scene(scene_id)


## Connect to scene_text_changed signal for dynamic text updates (Issue #154).
## Subclasses can override to add custom signal connections.
func _connect_state_signals() -> void:
	var nm := get_node_or_null("/root/NarrativeManager")
	if nm and nm.has_signal("scene_text_changed"):
		nm.scene_text_changed.connect(_on_narrative_tone_changed)


## Handle scene_text_changed from NarrativeManager for dynamic text updates (Issue #154).
## Subclasses should override to apply new tone to scene-specific environmental text nodes.
func _on_narrative_tone_changed(scene_id_emmited: String, tone: String) -> void:
	if scene_id_emmited != scene_id:
		return
	# Default: no-op. Subclasses connect specific text nodes here.


## Get the tone string for the current scene and state.
## Queries NarrativeManager's per-scene tone table for 5-state.
## Returns a tone string like "despair", "low", "neutral", "buoyant", "hope".
func _get_tone_for_scene(scene_id_query: String) -> String:
	var nm := get_node_or_null("/root/NarrativeManager")
	if nm and nm.has_method("_calculate_tone_for_scene"):
		var ss: Node = get_node_or_null("/root/StateSystem")
		if ss and ss.has_method("get_state"):
			var state: Dictionary = ss.get_state()
			var scene_idx: int = nm.SCENE_ORDER.find(scene_id_query)
			if scene_idx >= 0:
				return nm._calculate_tone_for_scene(scene_idx, state)
	# Fallback: use WorldviewController for global tone
	var wv := get_node_or_null("/root/WorldviewController")
	if wv and wv.has_method("get_tone_for_state"):
		var ss: Node = get_node_or_null("/root/StateSystem")
		if ss and ss.has_method("get_state"):
			return wv.get_tone_for_state(ss.get_state())
	return "neutral"


## Get the tone string for a specific scene + state combination.
## Useful for previewing what text would look like at a given state.
func _get_tone_for_scene_state(scene_id_query: String, state_id: int) -> String:
	var nm := get_node_or_null("/root/NarrativeManager")
	if nm:
		var scene_idx: int = nm.SCENE_ORDER.find(scene_id_query)
		if scene_idx >= 0:
			var scene_tones: Dictionary = nm.SCENE_TONES.get(scene_idx, {})
			return scene_tones.get(state_id, "neutral")
	return "neutral"


## Get the current state ID (1-5) from StateSystem.
func _get_current_state_id() -> int:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if ss and ss.has_method("get_state_id"):
		return ss.get_state_id()
	# Fallback: derive from hope value
	if ss and ss.has_method("get_state"):
		var state: Dictionary = ss.get_state()
		var hope_val: float = state.get("hope", 5.0)
		return _hope_to_state_id(hope_val)
	return 3


## Convert hope (0-10) to discrete state ID (1-5).
static func _hope_to_state_id(hope: float) -> int:
	if hope <= 2.0:
		return 1
	elif hope <= 4.0:
		return 2
	elif hope <= 6.0:
		return 3
	elif hope <= 8.0:
		return 4
	else:
		return 5


## Restore dialogue state from GameManager's choices_history.
## Now uses DialogueManager pattern — state persistence handled by StateSystem.
func _restore_dialogue_state() -> void:
	pass


## Get state tier for a given axis.
func get_state_tier(axis: String) -> String:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if ss and ss.has_method("get_state_tier"):
		return ss.get_state_tier(axis)
	return "mid"


## Get current state dictionary.
func get_state() -> Dictionary:
	var ss: Node = get_node_or_null("/root/StateSystem")
	if ss and ss.has_method("get_state"):
		return ss.get_state()
	return {"hope": 5.0, "conviction": 5.0, "will": 5.0}


## Start a dialogue via the DialogueManager balloon.
func start_dialogue(file_path: String, dialogue_id: String) -> void:
	_show_dialogue_balloon(file_path, dialogue_id)


## Helper: Show a DialogueBalloon for the given .dialogue resource and title.
func _show_dialogue_balloon(resource_path: String, title: String) -> void:
	if DialogueBalloon._current_balloon and is_instance_valid(DialogueBalloon._current_balloon):
		return
	var resource = load(resource_path)
	if resource == null:
		push_error("SceneBase: Could not load dialogue resource: ", resource_path)
		return
	var balloon_scene := preload("res://scenes/dialogue/dialogue_balloon.tscn")
	var balloon := balloon_scene.instantiate() as DialogueBalloon
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "DialogueBalloonLayer"
	add_child(canvas_layer)
	canvas_layer.add_child(balloon)
	balloon.start(resource, title, [get_node_or_null("/root/StateSystem")])


# ── Player Controller (Issue #142) ──

## Instantiate PlayerController as a child of this scene root.
func _instantiate_player() -> void:
	if _player and is_instance_valid(_player):
		return  # Already exists
	_player = PLAYER_CONTROLLER.new()
	_player.name = "PlayerController"
	add_child(_player)

	# Restore position from GameManager
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		if "player_position" in gm:
			var saved_pos = gm.get("player_position")
			if saved_pos != null and saved_pos is Vector3:
				_player.global_position = saved_pos
		if "player_rotation" in gm:
			var saved_rot = gm.get("player_rotation")
			if saved_rot != null and saved_rot is Vector3:
				_player.global_rotation = saved_rot
		if "player_head_rotation" in gm:
			var saved_head_rot = gm.get("player_head_rotation")
			if saved_head_rot != null and saved_head_rot is float:
				var head := _player.get_node_or_null("Head")
				if head:
					head.rotation.x = saved_head_rot

		# Restore camera orbit state (Issue #150)
		if _player.has_method("set_camera_orbit"):
			var yaw: float = gm.camera_orbit_yaw if "camera_orbit_yaw" in gm else 0.0
			var pitch: float = gm.camera_orbit_pitch if "camera_orbit_pitch" in gm else -0.2
			_player.set_camera_orbit(yaw, pitch)

	# Connect interaction_requested signal
	if _player.has_signal("interaction_requested"):
		_player.interaction_requested.connect(_on_player_interaction)

	# Set fall reset position to spawn point
	if _player.has_method("set_fall_reset_position"):
		_player.set_fall_reset_position(_get_player_spawn_position())


## Get the player spawn position. Default: SpawnPoint Marker3D or origin.
func _get_player_spawn_position() -> Vector3:
	var sp := get_node_or_null("SpawnPoint")
	if sp:
		return sp.global_position
	return Vector3.ZERO


## Handle player interaction with a target node (NPC or EKeyTrigger).
func _on_player_interaction(target: Node) -> void:
	if target.has_method("start_npc_interaction"):
		target.start_npc_interaction()
		return
	if target.has_method("start_dialogue"):
		target.start_dialogue()
		return
	push_warning("SceneBase._on_player_interaction: unhandled target '%s'" % target.name)


## Save player position/rotation to GameManager before scene unload.
func _save_player_state() -> void:
	if not _player or not is_instance_valid(_player):
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if not gm:
		return
	gm.set("player_position", _player.global_position)
	gm.set("player_rotation", _player.global_rotation)
	var head := _player.get_node_or_null("Head")
	if head:
		gm.set("player_head_rotation", head.rotation.x)

	# Save camera orbit state (Issue #150)
	if _player.has_method("get_camera_orbit"):
		var orbit: Dictionary = _player.get_camera_orbit()
		gm.set("camera_orbit_yaw", orbit.get("yaw", 0.0))
		gm.set("camera_orbit_pitch", orbit.get("pitch", -0.2))

# ── Navigation System (Issue #226) ──

## Wire NavigationController for this scene.
## Creates NavigationController as a child node if not already present in TSCN.
## Connects signals: fallback_triggered, navigation_hint_requested, condition_text_updated.
func _setup_navigation() -> void:
	if not enable_navigation:
		return

	# Create NavigationController if not present in scene
	var nav := get_node_or_null("NavigationController")
	if not nav:
		nav = preload("res://gdscripts/navigation_controller.gd").new()
		nav.name = "NavigationController"
		add_child.call_deferred(nav)
		await get_tree().process_frame

	nav = get_node_or_null("NavigationController")
	if not nav or not nav.has_method("_setup"):
		return

	nav.scene_id = scene_id

	# Pass player reference and spawn point
	if _player and is_instance_valid(_player):
		nav._setup(_player, _get_player_spawn_position())

	# Connect NavigationController signals
	if nav.has_signal("fallback_triggered"):
		nav.fallback_triggered.connect(_on_player_fell)

	if nav.has_signal("navigation_hint_requested"):
		nav.navigation_hint_requested.connect(_show_navigation_hint)

	if nav.has_signal("condition_text_updated"):
		nav.condition_text_updated.connect(_on_condition_text_updated)

	# Connect PlayerController navigation_hint_requested to NavigationController
	if _player and is_instance_valid(_player) and _player.has_signal("navigation_hint_requested"):
		if nav.has_method("_handle_hint_key"):
			if not _player.navigation_hint_requested.is_connected(nav._handle_hint_key):
				_player.navigation_hint_requested.connect(nav._handle_hint_key)

	# Connect dialogue mode changes to NavigationController
	if _player and is_instance_valid(_player) and _player.has_signal("dialogue_mode_changed"):
		if nav.has_method("set_dialogue_active"):
			if not _player.dialogue_mode_changed.is_connected(nav.set_dialogue_active):
				_player.dialogue_mode_changed.connect(nav.set_dialogue_active)


## Display H-key navigation hint text.
## Override in subclasses for per-scene hint display (CanvasLayer, Label3D, etc.).
func _show_navigation_hint(text: String) -> void:
	print("[NavHint] ", text)


## Handle condition-triggered environmental text.
## Override in subclasses to update scene-specific text nodes with the hint text.
func _on_condition_text_updated(hint: String) -> void:
	pass


## Handle fallback triggered by NavigationController.
## Delegates to NavFallback for fade-out, teleport, fade-in sequence.
func _on_player_fell(reason: String) -> void:
	print("[NavFallback] Triggered: %s" % reason)
	var nf := get_node_or_null("NavFallback")
	if nf and nf.has_method("_trigger_fallback"):
		nf._trigger_fallback(reason)
		# Reset navigation controller timers after fallback
		var nav := get_node_or_null("NavigationController")
		if nav and nav.has_method("_clear_timers"):
			nav._clear_timers()
			nav.set("_is_fallbacking", false)


## Update hallucination level when entering a new scene.
## Calls NarrativeManager.get_hallucination_level() and emits signal.
func _update_hallucination_on_scene_entry() -> void:
	var nm := get_node_or_null("/root/NarrativeManager")
	var ss := get_node_or_null("/root/StateSystem")
	if nm and ss and ss.has_method("get_state"):
		var state: Dictionary = ss.get_state()
		if nm.has_method("get_hallucination_level"):
			var level: int = nm.get_hallucination_level(scene_id, state)
			nm.set("_hallucination_level", level)
			if nm.has_signal("hallucination_level_changed"):
				nm.hallucination_level_changed.emit(level)


## Update route progress when entering a new scene.
## Calculates current position in SCENE_ORDER and stores in GameManager.
func _update_route_progress() -> void:
	var nm := get_node_or_null("/root/NarrativeManager")
	if not nm:
		return
	var idx: int = nm.SCENE_ORDER.find(scene_id)
	if idx < 0:
		return
	var total: int = nm.SCENE_ORDER.size()
	var progress: float = float(idx + 1) / float(total)
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.set("route_progress", progress)
		gm.set("route_progress_text", "%d/%d" % [idx + 1, total])

	# Track visited scene
	if gm and gm.has_method("mark_scene_visited"):
		gm.mark_scene_visited(scene_id)
	if gm:
		gm.current_scene_id = scene_id

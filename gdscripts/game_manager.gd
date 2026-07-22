extends Node

# GameManager — 全局游戏状态管理
# 由 Autoload 自动加载
# Delegates slider operations to StateSystem for Issue #50

var game_started: bool = false

# Internal flag storage (Issue #50)
var _flags: Dictionary = {}

# Reference to StateSystem autoload
@onready var _state_system: Node = get_node_or_null("/root/StateSystem")

# Dialogue persistence across scene changes
var choices_history: Array = []   # [{node_id, choice_index, choice_text}, ...]
var dialogue_history: Array = []  # future: full dialogue traversal log

# --- Narrative Architecture (Issue #45) ---
var current_scene_id: String = "office"  # Current scene in the narrative path
var scene_visited: Dictionary = {}        # {scene_id: bool} — track visited scenes
var choices_made: int = 0                 # Total choices made this run

func _ready() -> void:
	print("Agent Game Test — Godot 4.7")
	print("GameManager initialized.")

func start_game() -> void:
	game_started = true
	print("Game started!")

# ===== Dialogue API =====

## Get current value of a slider axis.
## Delegates to StateSystem for known axes; returns 5.0 fallback for unknown axes.
func get_slider(axis: String) -> float:
	if _state_system == null:
		_state_system = get_node_or_null("/root/StateSystem")
	if _state_system == null:
		return 5.0
	match axis:
		"hope_despair":
			return _state_system.hope_despair
		"hope":
			return _state_system.hope
		"conviction":
			return _state_system.conviction
		"will":
			return _state_system.will
		_:
			return 5.0

## Check if a named flag is set.
func has_flag(flag_name: String) -> bool:
	return _flags.has(flag_name) and _flags[flag_name] == true

## Get all flags as a Dictionary.
func get_flags() -> Dictionary:
	return _flags.duplicate()

## Apply a slider delta (clamped to axis range).
## Delegates to StateSystem.apply_choice() for the given axis.
func apply_slider_delta(axis: String, delta: float) -> void:
	if _state_system == null:
		_state_system = get_node_or_null("/root/StateSystem")
	if _state_system == null or not _state_system.has_method("apply_choice"):
		return
	match axis:
		"hope_despair":
			_state_system.apply_choice({"hope_despair": delta})
		"hope":
			_state_system.apply_choice({"hope": delta})
		"conviction":
			_state_system.apply_choice({"conviction": delta})
		"will":
			_state_system.apply_choice({"will": delta})
		_:
			push_warning("GameManager.apply_slider_delta: unknown axis '%s'" % axis)

## Set a named flag.
func set_flag(flag_name: String, value: bool) -> void:
	_flags[flag_name] = value

# ===== Dialogue Persistence =====

## Save dialogue choices to persist across scene transitions.
func save_choices(choices: Array) -> void:
	choices_history = choices.duplicate()

## Get the next scene ID via NarrativeManager.
func get_next_scene_id() -> String:
	var nm: Node = get_node_or_null("/root/NarrativeManager")
	if nm and nm.has_method("get_next_scene"):
		return nm.get_next_scene(current_scene_id)
	return ""

## Track a scene as visited.
func mark_scene_visited(scene_id: String) -> void:
	scene_visited[scene_id] = true

## Check if a scene was visited.
func is_scene_visited(scene_id: String) -> bool:
	return scene_visited.get(scene_id, false)

## Restore previously saved choices.
func restore_choices() -> Array:
	return choices_history.duplicate()

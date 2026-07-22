extends Node

# GameManager — 全局游戏状态管理
# 由 Autoload 自动加载

var game_started: bool = false

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

## Get current value of a slider axis. Returns 5.0 (default) if axis unknown.
func get_slider(axis: String) -> float:
	return 5.0

## Check if a named flag is set.
func has_flag(flag_name: String) -> bool:
	return false

## Get all flags as a Dictionary.
func get_flags() -> Dictionary:
	return {}

## Apply a slider delta (clamped to [1, 10]).
func apply_slider_delta(axis: String, delta: float) -> void:
	pass

## Set a named flag.
func set_flag(flag_name: String, value: bool) -> void:
	pass

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

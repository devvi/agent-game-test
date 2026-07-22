extends Node

# GameManager - 全局游戏状态管理
# 由 Autoload 自动加载
# Delegates slider/flag queries to StateSystem for authoritative data.

var game_started: bool = false

# Dialogue persistence across scene changes
var choices_history: Array = []   # [{node_id, choice_index, choice_text}, ...]
var dialogue_history: Array = []  # future: full dialogue traversal log

# Flag storage for narrative state
var _flags: Dictionary = {}

# ===== Known Slider Axes =====
const AXIS_HOPE_DESPAIR: String = "hope_despair"
const AXIS_HOPE: String = "hope"
const AXIS_CONVICTION: String = "conviction"
const AXIS_WILL: String = "will"


func _ready() -> void:
	print("Agent Game Test - Godot 4.7")
	print("GameManager initialized.")

func start_game() -> void:
	game_started = true
	print("Game started!")


# ===== StateSystem Access =====

func _get_state_system():
	return get_node_or_null("/root/StateSystem")


# ===== Dialogue API =====

## Get current value of a slider axis.
## Delegates to StateSystem for "hope_despair", "hope", "conviction", "will".
## Returns 5.0 as fallback for unknown axes to maintain backward compatibility.
func get_slider(axis: String) -> float:
	var ss = _get_state_system()
	if not ss:
		return 5.0  # fallback if StateSystem not available

	match axis:
		AXIS_HOPE_DESPAIR:
			return ss.hope_despair
		AXIS_HOPE:
			return ss.hope
		AXIS_CONVICTION:
			return ss.conviction
		AXIS_WILL:
			return ss.will
		_:
			push_warning("GameManager.get_slider(): unknown axis '%s', returning 0.0" % axis)
			return 0.0


## Check if a named flag is set.
func has_flag(flag_name: String) -> bool:
	return _flags.has(flag_name) and _flags[flag_name] == true


## Get all flags as a Dictionary.
func get_flags() -> Dictionary:
	return _flags.duplicate()


## Apply a slider delta (clamped, with resistance).
## Delegates to StateSystem.apply_hope_despair_delta() for "hope_despair" axis.
## For other axes, applies directly to StateSystem.
func apply_slider_delta(axis: String, delta: float) -> void:
	var ss = _get_state_system()
	if not ss:
		return

	match axis:
		AXIS_HOPE_DESPAIR:
			ss.apply_hope_despair_delta(delta)
		AXIS_HOPE:
			# Apply as hope_despair delta (mapped)
			ss.apply_hope_despair_delta(delta * 2.0)
		AXIS_CONVICTION:
			ss.apply_choice({"conviction": delta})
		AXIS_WILL:
			ss.apply_choice({"will": delta})
		_:
			push_warning("GameManager.apply_slider_delta(): unknown axis '%s'" % axis)


## Set a named flag.
func set_flag(flag_name: String, value: bool) -> void:
	_flags[flag_name] = value


## Get list of all known slider axis names.
func get_slider_list() -> Array:
	return [AXIS_HOPE_DESPAIR, AXIS_HOPE, AXIS_CONVICTION, AXIS_WILL]


# ===== Dialogue Persistence =====

## Save dialogue choices to persist across scene transitions.
func save_choices(choices: Array) -> void:
	choices_history = choices.duplicate()

## Restore previously saved choices.
func restore_choices() -> Array:
	return choices_history.duplicate()

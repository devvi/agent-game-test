extends Node
class_name NarrativeManager

# NarrativeManager — Core narrative architecture controller (Issue #45)
# Manages scene sequence, ending determination, and echo system.
# Listens to StateSystem.state_changed for tone calculation.

# --- Signals ---
signal scene_text_changed(scene_id: String, tone: String)  # Scene text variant change
signal echo_triggered(echo_id: String, variant: int)        # Echo triggered
signal ending_determined(ending: String)                    # Ending decided

# --- Scene Sequence ---
const SCENE_ORDER: Array[String] = [
	"office", "lobby", "convenience_store",
	"bridge", "underpass", "subway_station"
]

const SCENE_PATHS: Dictionary = {
	"office": "res://scenes/office/office.tscn",
	"lobby": "res://scenes/lobby/lobby.tscn",
	"convenience_store": "res://scenes/store/convenience_store.tscn",
	"bridge": "res://scenes/bridge/bridge.tscn",
	"underpass": "res://scenes/underpass/underpass.tscn",
	"subway_station": "res://scenes/subway_station/subway_station.tscn"
}

# --- Ending Thresholds ---
const ENDING_KEEP_WALKING_HOPE: float = 6.0
const ENDING_KEEP_WALKING_WILL: float = 5.0
const ENDING_TURN_BACK_CONVICTION: float = 3.0
const ENDING_STAY_HOPE: float = 4.0
const ENDING_STAY_CONVICTION: float = 4.0
const ENDING_STAY_WILL: float = 4.0

# --- State ---
var current_scene_index: int = 0
var echo_flags: Dictionary = {}       # {echo_id: bool} — has been triggered
var echo_variants: Dictionary = {}    # {echo_id: int} — variant index

# --- Echo System References ---
@onready var _state_system: Node = get_node_or_null("/root/StateSystem")
@onready var _game_manager: Node = get_node_or_null("/root/GameManager")


func _ready() -> void:
	if _state_system and _state_system.has_signal("state_changed"):
		_state_system.state_changed.connect(_on_state_changed)


func _on_state_changed(state: Dictionary) -> void:
	var tone := _calculate_tone_for_scene(current_scene_index, state)
	scene_text_changed.emit(SCENE_ORDER[current_scene_index], tone)


## Calculate scene text tone based on state. Each scene responds differently.
func _calculate_tone_for_scene(scene_idx: int, state: Dictionary) -> String:
	var hope_val: float = state.get("hope", 5.0)
	var conviction_val: float = state.get("conviction", 5.0)
	var will_val: float = state.get("will", 5.0)

	match scene_idx:
		0:  # Office — hope-sensitive
			if hope_val <= 3.0: return "despair"
			elif hope_val >= 7.0: return "hope"
			else: return "neutral"
		1:  # Lobby — conviction-sensitive
			if conviction_val <= 3.0: return "fear"
			elif conviction_val >= 7.0: return "defiant"
			else: return "neutral"
		2:  # Convenience Store — hope-sensitive warmth
			if hope_val <= 3.0: return "cold"
			elif hope_val >= 7.0: return "warm"
			else: return "neutral"
		3:  # Bridge — will-sensitive
			if will_val <= 3.0: return "tired"
			elif will_val >= 7.0: return "determined"
			else: return "neutral"
		4:  # Underpass — composite state
			return _calculate_underpass_tone(state)
		5:  # Subway Station — ending tone
			return _calculate_station_tone(state)
		_:
			return "neutral"


func _calculate_underpass_tone(state: Dictionary) -> String:
	var hope_val: float = state.get("hope", 5.0)
	var conviction_val: float = state.get("conviction", 5.0)
	if hope_val <= 4.0 and conviction_val <= 4.0:
		return "despair"
	elif hope_val >= 6.0 and conviction_val >= 6.0:
		return "resolute"
	else:
		return "neutral"


func _calculate_station_tone(state: Dictionary) -> String:
	var hope_val: float = state.get("hope", 5.0)
	if hope_val >= ENDING_KEEP_WALKING_HOPE:
		return "forward"
	elif _state_system and _state_system.conviction <= ENDING_TURN_BACK_CONVICTION:
		return "backward"
	else:
		return "waiting"


## Trigger a narrative echo. Called by scene scripts at the right moment.
func trigger_echo(echo_id: String) -> void:
	if echo_flags.get(echo_id, false):
		return  # Already triggered
	echo_flags[echo_id] = true
	echo_variants[echo_id] = _calculate_echo_variant(echo_id)
	echo_triggered.emit(echo_id, echo_variants[echo_id])


## Calculate echo variant based on current state.
func _calculate_echo_variant(echo_id: String) -> int:
	match echo_id:
		"rain_echo":
			# 0=concerned (high hope), 1=neutral, 2=sarcastic/disappointed (low hope)
			var hope_val: float = _state_system.hope if _state_system else 5.0
			if hope_val >= 7.0: return 0
			elif hope_val <= 3.0: return 2
			else: return 1
		"screensaver_echo":
			# 0=defiant (high conviction), 1=self-deprecating (low)
			var conviction_val: float = _state_system.conviction if _state_system else 5.0
			if conviction_val >= 7.0: return 0
			else: return 1
		_:
			return 0


## Determine ending at subway station. Returns ending ID string.
func determine_ending(state: Dictionary) -> String:
	var hope_val: float = state.get("hope", 5.0)
	var conviction_val: float = state.get("conviction", 5.0)
	var will_val: float = state.get("will", 5.0)

	# Priority 1: Turn Back (very low conviction)
	if conviction_val <= ENDING_TURN_BACK_CONVICTION:
		return "turn_back"

	# Priority 2: Keep Walking (high hope + strong will)
	if hope_val >= ENDING_KEEP_WALKING_HOPE and will_val >= ENDING_KEEP_WALKING_WILL:
		return "keep_walking"

	# Priority 3: Stay (all low/average)
	if hope_val <= ENDING_STAY_HOPE and conviction_val <= ENDING_STAY_CONVICTION and will_val <= ENDING_STAY_WILL:
		return "stay"

	# Fallthrough → Stay
	return "stay"


## Advance to the next scene. Returns the next scene ID or empty string if at end.
func advance_scene() -> String:
	if current_scene_index >= SCENE_ORDER.size() - 1:
		return ""
	current_scene_index += 1
	var next_id: String = SCENE_ORDER[current_scene_index]
	if _game_manager:
		_game_manager.current_scene_id = next_id
	return next_id


## Get the next scene ID without advancing.
func get_next_scene(current_scene: String) -> String:
	var idx: int = SCENE_ORDER.find(current_scene)
	if idx == -1 or idx >= SCENE_ORDER.size() - 1:
		return ""
	return SCENE_ORDER[idx + 1]


## Reset narrative state for a new game.
func reset() -> void:
	current_scene_index = 0
	echo_flags.clear()
	echo_variants.clear()

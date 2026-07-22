extends Node

# NarrativeManager — Core narrative architecture controller (Issue #45 / #50)
# Manages scene sequence, ending determination, and echo system.
# Listens to StateSystem.state_changed for tone calculation.
# Expanded from 3-state to 5-state per-scene tones (Issue #50).

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

# --- 5-State Tone Tables (Issue #50) ---
# Per-scene tone for each state ID (1=Despair, 2=Low, 3=Neutral, 4=Buoyant, 5=Hope)
const SCENE_TONES: Dictionary = {
	0: {1: "despair", 2: "low", 3: "neutral", 4: "buoyant", 5: "hope"},       # Office
	1: {1: "fear", 2: "uneasy", 3: "neutral", 4: "curious", 5: "defiant"},    # Lobby
	2: {1: "cold", 2: "distant", 3: "neutral", 4: "warm", 5: "glowing"},      # Convenience Store
	3: {1: "tired", 2: "heavy", 3: "neutral", 4: "hopeful", 5: "determined"}, # Bridge
	4: {1: "despair", 2: "hollow", 3: "neutral", 4: "resolute", 5: "transcendent"}, # Underpass
	5: {1: "backward", 2: "hesitant", 3: "waiting", 4: "forward", 5: "forward"}      # Subway Station
}

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


## Convert hope (0–10) to discrete state ID (1–5) for per-scene tone lookup.
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


## Calculate scene text tone based on state using the 5-state per-scene table.
func _calculate_tone_for_scene(scene_idx: int, state: Dictionary) -> String:
	var hope_val: float = state.get("hope", 5.0)
	var state_id: int = _hope_to_state_id(hope_val)
	var scene_tones: Dictionary = SCENE_TONES.get(scene_idx, {})
	return scene_tones.get(state_id, "neutral")


## Trigger a narrative echo. Called by scene scripts at the right moment.
func trigger_echo(echo_id: String) -> void:
	if echo_flags.get(echo_id, false):
		return  # Already triggered
	echo_flags[echo_id] = true
	echo_variants[echo_id] = _calculate_echo_variant(echo_id)
	echo_triggered.emit(echo_id, echo_variants[echo_id])


## Calculate echo variant based on current state.
## Expanded to 5 variants (0-4) matching 5-state system (Issue #50).
## Mapping: state 5 (Hope) -> variant 0, 4->1, 3->2, 2->3, 1 (Despair) -> variant 4
func _calculate_echo_variant(echo_id: String) -> int:
	var hope_val: float = _state_system.hope if _state_system else 5.0
	var conviction_val: float = _state_system.conviction if _state_system else 5.0
	var state_id: int = _hope_to_state_id(hope_val)

	# Map state_id 1-5 to variant 4-0 (inverse: lower state = higher variant index)
	var variant_by_state: int = 4 - (state_id - 1)

	match echo_id:
		"rain_echo":
			return variant_by_state
		"screensaver_echo":
			return variant_by_state
		"clock_echo":
			return variant_by_state
		"door_echo":
			return variant_by_state
		"rain_variation_echo":
			return variant_by_state
		"stranger_echo":
			# Stranger echo also considers conviction; scale both to 5-state
			var cv_state_id: int = _conviction_to_state_id(conviction_val)
			var composite: int = (state_id + cv_state_id) / 2
			return 4 - (composite - 1)
		_:
			return 0


## Convert conviction (0–10) to a 5-state value for composite echo calculations.
static func _conviction_to_state_id(conviction: float) -> int:
	if conviction <= 2.0:
		return 1
	elif conviction <= 4.0:
		return 2
	elif conviction <= 6.0:
		return 3
	elif conviction <= 8.0:
		return 4
	else:
		return 5


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

	# Fallthrough -> Stay
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

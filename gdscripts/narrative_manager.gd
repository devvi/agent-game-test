extends Node

# NarrativeManager — Core narrative architecture controller (Issue #45 / #50)
# Manages scene sequence, ending determination, and echo system.
# Listens to StateSystem.state_changed for tone calculation.
# Expanded from 3-state to 5-state per-scene tones (Issue #50).

# --- Signals ---
signal scene_text_changed(scene_id: String, tone: String)  # Scene text variant change
signal echo_triggered(echo_id: String, variant: int)        # Echo triggered
signal ending_determined(ending: String)                    # Ending decided
signal hallucination_level_changed(new_level: int)          # Hallucination level changed
signal reality_flashback(flashback_scene: String, flashback_text: String)  # Flashback triggered

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

# --- Hallucination State (Issue #214) ---
var _hallucination_level: int = 0     # Current hallucination level (0-10)
var _b1_counts: Dictionary = {}       # {scene_id: {"total": int, "unreliable": int}}

# Hallucination constants (matching constants.gd)
const HALLUCINATION_MIN: int = 0
const HALLUCINATION_MAX: int = 10
const HALLUCINATION_BASE_LEVELS: Dictionary = {
	"office": 0,
	"lobby": 1,
	"convenience_store": 2,
	"bridge": 4,
	"underpass": 7,
	"subway_station": 9
}
const HALLUCINATION_HOPE_HIGH: float = 8.0
const HALLUCINATION_HOPE_LOW: float = 2.0
const FLASHBACK_MIN_LEVEL: int = 5
const B1_UNRELIABLE_RATIO_LOW: float = 0.3
const B1_UNRELIABLE_RATIO_HIGH: float = 0.7

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
	reset_b1_tracking()

## Set a narrative flag via GameManager.
## Used by scene scripts to set flags before dialogue starts.
func set_flag(flag_name: String, value: bool) -> void:
	if _game_manager and _game_manager.has_method("set_flag"):
		_game_manager.set_flag(flag_name, value)

# ===== Hallucination Level System (Issue #214) =====

## Calculate hallucination level for a scene (0-10).
## scene_id: scene key (e.g. "office", "lobby")
## state: dictionary with "hope" key
## base_level = scene position-based level
## state_modifier = -1 if hope >= 8, +1 if hope <= 2, else 0
static func get_hallucination_level(scene_id: String, state: Dictionary) -> int:
	var base_level: int = HALLUCINATION_BASE_LEVELS.get(scene_id, 0)
	var hope_val: float = state.get("hope", 5.0)
	var state_modifier: int = 0

	if hope_val >= 8.0:
		state_modifier = -1
	elif hope_val <= 2.0:
		state_modifier = 1

	return clampi(base_level + state_modifier, HALLUCINATION_MIN, HALLUCINATION_MAX)


## Get hallucination-to-visual parameter mapping for a given level.
## Returns {vignette, rain_density, light_flicker, text_drift, view_instability}
static func get_hallucination_params(level: int) -> Dictionary:
	var params: Dictionary = {
		"vignette": 0.0,
		"rain_density": 0.0,
		"light_flicker": 0.0,
		"text_drift": 0.0,
		"view_instability": 0.0
	}

	if level <= 0:
		pass  # All defaults
	elif level <= 2:
		params["vignette"] = 0.1 + level * 0.05
		params["rain_density"] = 0.1
	elif level <= 4:
		params["vignette"] = 0.2 + (level - 2) * 0.1
		params["rain_density"] = 0.2 + (level - 2) * 0.1
		params["light_flicker"] = (level - 2) * 0.15
	elif level <= 6:
		params["vignette"] = 0.4 + (level - 4) * 0.1
		params["rain_density"] = 0.4 + (level - 4) * 0.1
		params["light_flicker"] = 0.3 + (level - 4) * 0.1
		params["text_drift"] = (level - 4) * 0.1
	elif level <= 8:
		params["vignette"] = 0.6 + (level - 6) * 0.1
		params["rain_density"] = 0.6 + (level - 6) * 0.1
		params["light_flicker"] = 0.5 + (level - 6) * 0.1
		params["text_drift"] = 0.2 + (level - 6) * 0.15
		params["view_instability"] = 0.1 + (level - 6) * 0.1
	else:  # level 9-10
		params["vignette"] = 0.8
		params["rain_density"] = 0.9
		params["light_flicker"] = 0.8
		params["text_drift"] = 0.5
		params["view_instability"] = 0.4

	return params


## Trigger a reality flashback from another scene.
## Flashback is emitted as the reality_flashback signal.
func trigger_reality_flashback(current_scene_id: String) -> void:
	# Build list of other scenes that can be flashback sources
	var candidates: Array[String] = []
	for scene_id in SCENE_ORDER:
		if scene_id != current_scene_id:
			candidates.append(scene_id)

	if candidates.is_empty():
		return

	candidates.shuffle()
	var flashback_scene: String = candidates[0]
	var flashback_text: String = _generate_flashback_text(flashback_scene)
	reality_flashback.emit(flashback_scene, flashback_text)


## Generate flashback text for a target scene.
func _generate_flashback_text(scene_id: String) -> String:
	match scene_id:
		"office":
			return "The office door swings open. / The clock reads the same time."
		"lobby":
			return "The lobby stretches endlessly. / The stranger's umbrella drips."
		"convenience_store":
			return "The fluorescent hum returns. / Coffee cup still warm."
		"bridge":
			return "Rain on the bridge railing. / A moment from before."
		_:
			return "A memory surfaces. / The details blur at the edges."


# ===== B1 Constraint Runtime Tracking (Issue #214) =====

## Register a dialogue node for B1 tracking in a specific scene.
## is_reliable = true means the text is reliable (no ambiguity).
func check_b1_constraint(scene_id: String, text: String, is_reliable: bool) -> void:
	if not _b1_counts.has(scene_id):
		_b1_counts[scene_id] = {"total": 0, "unreliable": 0}
	_b1_counts[scene_id]["total"] += 1
	if not is_reliable:
		_b1_counts[scene_id]["unreliable"] += 1


## Get the unreliable narration ratio for a given scene (0.0-1.0).
## Returns 0.0 if no nodes registered for that scene.
func get_b1_ratio(scene_id: String) -> float:
	var counts: Dictionary = _b1_counts.get(scene_id, {"total": 0, "unreliable": 0})
	if counts["total"] == 0:
		return 0.0
	return float(counts["unreliable"]) / float(counts["total"])


## Check if the B1 unreliable ratio meets the threshold for a given
## hallucination level. Returns true if ratio >= threshold.
## Threshold: 0.30 for hallucination < 5, 0.70 for hallucination >= 5.
func check_b1_ratio_met(scene_id: String, hallucination_level: int) -> bool:
	var ratio: float = get_b1_ratio(scene_id)
	var threshold: float = B1_UNRELIABLE_RATIO_HIGH if hallucination_level >= 5 else B1_UNRELIABLE_RATIO_LOW
	return ratio >= threshold


# ===== Borgesian Rule Evaluation (Issue #214) =====

## Evaluate a Borgesian constraint rule against text at runtime.
## Primarily for creation-time validation, not runtime enforcement.
## rule_id: "B3" (no metanarrative) or "B6" (infinite/finite paradox)
## text: the text to evaluate
## Returns true if the text complies with the rule.
static func evaluate_borgesian_rule(rule_id: String, text: String) -> bool:
	var text_lower: String = text.to_lower()

	match rule_id:
		"B3":
			# B3: No metanarrative labels — no "hallucination", "illusion", "not real", "dream", "imagination"
			var banned: Array[String] = ["hallucination", "illusion", "not real", "dream", "imagination"]
			for word in banned:
				if text_lower.contains(word):
					return false
			return true

		"B6":
			# B6: Must contain both "infinite" concept and "finite" concept
			var infinite_words: Array[String] = ["infinite", "endless", "forever", "never"]
			var finite_words: Array[String] = ["finite", "limit", "end"]
			var has_infinite: bool = false
			var has_finite: bool = false

			for word in infinite_words:
				if text_lower.contains(word):
					has_infinite = true
					break
			for word in finite_words:
				if text_lower.contains(word):
					has_finite = true
					break

			return has_infinite and has_finite

		_:
			# Unknown rules pass by default
			return true


## Reset B1 tracking counters (e.g., on new game).
func reset_b1_tracking() -> void:
	_b1_counts.clear()

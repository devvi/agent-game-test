extends Node

# Constants — Threshold and priority constants for Theme-Mechanic Mapping Chain

# Scene Paths
const SCENE_OFFICE: String = "res://scenes/office/office.tscn"
const SCENE_STREET: String = "res://scenes/street/street.tscn"
const SCENE_STORE: String = "res://scenes/store/convenience_store.tscn"

# Fade Transition
const FADE_DURATION: float = 0.5

# Priority Tiers
const PRIORITY_P0: Array[String] = ["dialogue_check", "worldview_filter", "triaxis_slider"]
const PRIORITY_P1: Array[String] = ["rainy_night"]
const PRIORITY_P2: Array[String] = ["three_month_clock"]

# State Limits
const STATE_MIN: float = 0.0
const STATE_MAX: float = 10.0
const STATE_NEUTRAL: float = 5.0
const STATE_HIGH: float = 7.0
const STATE_LOW: float = 3.0

# Thresholds
const CONVICTION_SHELTER_THRESHOLD: float = 3.0
const HOPE_COLD_TONE_THRESHOLD: float = 3.0
const HOPE_WARM_TONE_THRESHOLD: float = 7.0
const DIALOGUE_MAX_DAYS_COST: int = 3
const CLOCK_DEADLINE_DAYS: int = 90

# Rain shelter threshold (intensity >= this triggers shelter)
const SHELTER_INTENSITY_THRESHOLD: float = 0.7

# --- Narrative Architecture Constants (Issue #45) ---

# Scene sequence
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

# Default scene
const SCENE_DEFAULT: String = "office"

# State tiers
const STATE_TIER_LOW: float = 3.0
const STATE_TIER_HIGH: float = 7.0

# State axis names
const AXIS_HOPE: String = "hope"
const AXIS_CONVICTION: String = "conviction"
const AXIS_WILL: String = "will"

# Ending thresholds
const ENDING_KEEP_WALKING_HOPE: float = 6.0
const ENDING_KEEP_WALKING_WILL: float = 5.0
const ENDING_TURN_BACK_CONVICTION: float = 3.0
const ENDING_STAY_HOPE: float = 4.0
const ENDING_STAY_CONVICTION: float = 4.0
const ENDING_STAY_WILL: float = 4.0

# Echo system
const ECHO_RAIN: String = "rain_echo"
const ECHO_SCREENSAVER: String = "screensaver_echo"
const ECHO_BROADCAST: String = "lobby_broadcast_echo"

# Dialogue file paths
const DIALOGUE_OFFICE_DOOR: String = "res://dialogues/office_door.json"
const DIALOGUE_LOBBY_STRANGER: String = "res://dialogues/lobby_stranger.json"
const DIALOGUE_LOBBY_GUARD: String = "res://dialogues/lobby_guard.json"
const DIALOGUE_STORE_CLERK: String = "res://dialogues/store_clerk.json"
const DIALOGUE_BRIDGE_HOMELESS: String = "res://dialogues/bridge_homeless.json"
const DIALOGUE_UNDERPASS_ECHO: String = "res://dialogues/underpass_stranger_echo.json"
const DIALOGUE_SUBWAY_ENDING: String = "res://dialogues/subway_ending.json"

# Narrative effects deltas (choice point effects)
const DELTA_RESPOND_STRANGER_HOPE: float = 0.5
const DELTA_RESPOND_STRANGER_CONVICTION: float = 0.5
const DELTA_IGNORE_STRANGER_HOPE: float = -0.5
const DELTA_IGNORE_STRANGER_CONVICTION: float = -0.5
const DELTA_BUY_COFFEE_WILL: float = 1.0
const DELTA_BUY_COFFEE_HOPE: float = 0.5
const DELTA_NO_COFFEE_WILL: float = -0.5
const DELTA_NO_COFFEE_HOPE: float = -0.5

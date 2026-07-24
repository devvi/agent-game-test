extends Node

# Constants — Threshold and priority constants for Theme-Mechanic Mapping Chain

# Scene Paths
const SCENE_OFFICE: String = "res://scenes/office/office.tscn"
const SCENE_STREET: String = "res://scenes/street/street.tscn"
const SCENE_STORE: String = "res://scenes/store/convenience_store.tscn"
const SCENE_BRIDGE: String = "res://scenes/bridge/bridge.tscn"
const SCENE_UNDERPASS: String = "res://scenes/underpass/underpass.tscn"

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
const ECHO_CLOCK: String = "clock_echo"
const ECHO_DOOR: String = "door_echo"
const ECHO_RAIN_VARIATION: String = "rain_variation_echo"
const ECHO_STRANGER: String = "stranger_echo"

# Dialogue file paths
const DIALOGUE_OFFICE_DOOR: String = "res://dialogues/office_door.dialogue"
const DIALOGUE_LOBBY_STRANGER: String = "res://dialogues/lobby_stranger.dialogue"
const DIALOGUE_LOBBY_GUARD: String = "res://dialogues/lobby_guard.dialogue"
const DIALOGUE_STORE_CLERK: String = "res://dialogues/store_clerk.dialogue"
const DIALOGUE_BRIDGE_HOMELESS: String = "res://dialogues/bridge_homeless.dialogue"
const DIALOGUE_UNDERPASS_ECHO: String = "res://dialogues/underpass_stranger_echo.dialogue"
const DIALOGUE_SUBWAY_ENDING: String = "res://dialogues/subway_ending.dialogue"
const DIALOGUE_NPC_TEST: String = "res://dialogues/npc_test.dialogue"

# Narrative effects deltas (choice point effects)
const DELTA_RESPOND_STRANGER_HOPE: float = 0.5
const DELTA_RESPOND_STRANGER_CONVICTION: float = 0.5
const DELTA_IGNORE_STRANGER_HOPE: float = -0.5
const DELTA_IGNORE_STRANGER_CONVICTION: float = -0.5
const DELTA_BUY_COFFEE_WILL: float = 1.0
const DELTA_BUY_COFFEE_HOPE: float = 0.5
const DELTA_NO_COFFEE_WILL: float = -0.5
const DELTA_NO_COFFEE_HOPE: float = -0.5

# Despair thresholds for AC3 hidden text
const DESPAIR_HOPE_THRESHOLD: float = 2.0
const DESPAIR_CONVICTION_THRESHOLD: float = 2.0

# --- Hallucination Level Constants (Issue #214) ---

# Hallucination level range
const HALLUCINATION_MIN: int = 0
const HALLUCINATION_MAX: int = 10

# Base hallucination level per scene (distance-based: office=0 → subway=9)
const HALLUCINATION_BASE_LEVELS: Dictionary = {
	"office": 0,
	"lobby": 1,
	"convenience_store": 2,
	"bridge": 4,
	"underpass": 7,
	"subway_station": 9
}

# State modifier thresholds
const HALLUCINATION_HOPE_HIGH: float = 8.0  # hope >= 8 → -1 modifier
const HALLUCINATION_HOPE_LOW: float = 2.0   # hope <= 2 → +1 modifier

# Route ID constants (matching state_system route_flag values)
const ROUTE_KEEP_WALKING: String = "keep_walking"
const ROUTE_TURN_BACK: String = "turn_back"
const ROUTE_STAY: String = "stay"
const VALID_ROUTES: Array[String] = ["keep_walking", "turn_back", "stay"]

# Flashback thresholds
const FLASHBACK_MIN_LEVEL: int = 5  # hallucination >= 5 enables flashbacks

# B1 constraint: unreliable narration ratio targets
const B1_UNRELIABLE_RATIO_LOW: float = 0.3   # hallucination < 5: ≥30% unreliable
const B1_UNRELIABLE_RATIO_HIGH: float = 0.7  # hallucination ≥ 5: ≥70% unreliable

# --- L3 Echo Table (Issue #214) ---
# Each echo: {id, source_scene, target_scene, condition, text_variants}
const ECHO_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "handprint_echo",
		"source_scene": "office",
		"target_scene": "bridge",
		"condition": "always",
		"description": "Office window handprint reappears on bridge railing"
	},
	{
		"id": "clock_loop_echo",
		"source_scene": "office",
		"target_scene": "subway_station",
		"condition": "route == turn_back",
		"description": "Office clock reading returns at subway station for Turn Back route"
	},
	{
		"id": "stranger_gaze_echo",
		"source_scene": "lobby",
		"target_scene": "underpass",
		"condition": "always",
		"description": "Stranger's lobby gaze echoes in underpass"
	},
	{
		"id": "rain_constancy_echo",
		"source_scene": "office",
		"target_scene": "bridge",
		"condition": "always",
		"description": "Rain sound constancy across scenes — never stops"
	},
	{
		"id": "door_threshold_echo",
		"source_scene": "office",
		"target_scene": "subway_station",
		"condition": "always",
		"description": "Office door threshold mirrors subway station gate"
	},
	{
		"id": "coffee_cold_echo",
		"source_scene": "convenience_store",
		"target_scene": "bridge",
		"condition": "hope <= 2",
		"description": "Cold coffee remembered on bridge in low-hope state"
	}
]

# --- NPC Framework Constants (Issue #54) ---

# NPC defaults
const NPC_DEFAULT_PROXIMITY: float = 3.0
const NPC_DEFAULT_COOLDOWN: float = 2.0
const NPC_LABEL_OFFSET: Vector3 = Vector3(0, 1.5, 0)

# Office exit flags (set by office_door.json, checked by clerk dialogue)
const FLAG_OFFICE_EXIT_SIGH: String = "office_exit_sigh"
const FLAG_OFFICE_EXIT_NEUTRAL: String = "office_exit_neutral"
const FLAG_OFFICE_EXIT_DETERMINED: String = "office_exit_determined"

# Expanded clerk dialogue file constant
const DIALOGUE_STORE_CLERK_EXPANDED: String = "res://dialogues/store_clerk.dialogue"

# --- Navigation System Constants (Issue #221) ---

# Navigation condition thresholds
const NAV_STAY_THRESHOLD: float = 60.0           # Seconds before stay-warning text triggers
const NAV_WRONG_DIR_THRESHOLD: float = 30.0      # Seconds before wrong-direction text triggers
const NAV_STUCK_VELOCITY_THRESHOLD: float = 0.01 # Max velocity (m/s) considered "stuck"
const NAV_STUCK_DURATION: float = 3.0            # Consecutive seconds stuck before fallback

# Hint system
const NAV_HINT_COOLDOWN: float = 8.0            # Seconds minimum between H-key hints
const NAV_HINT_DISPLAY_DURATION: float = 5.0    # Seconds hint text stays visible
const NAV_TITLE_DISPLAY_DURATION: float = 3.0   # Seconds scene title card stays visible

# Fallback system
const NAV_FALLBACK_Y_THRESHOLD: float = -10.0   # Y position below this triggers fallback
const NAV_FALLBACK_MAX: int = 3                 # Max consecutive fallbacks before title screen
const NAV_FALLBACK_FADE_DURATION: float = 0.3   # Quick fade duration for fallback teleport

# Title screen scene path
const SCENE_TITLE: String = "res://scenes/title_screen.tscn"

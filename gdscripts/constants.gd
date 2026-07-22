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

# ===== Hope/Despair Slider Constants (Issue #50) =====

# Slider range
const HOPE_DESPAIR_MIN: float = -10.0
const HOPE_DESPAIR_MAX: float = 10.0
const HOPE_DESPAIR_NEUTRAL: float = 0.0

# 5 discrete state IDs
const STATE_DESPAIR: int = 1
const STATE_LOW: int = 2
const STATE_NEUTRAL: int = 3
const STATE_BUOYANT: int = 4
const STATE_HOPE: int = 5

# State boundary upper bounds (each state i is (boundaries[i-1], boundaries[i]] except state 1 which includes -10)
# [-10, -6] = Despair, (-6, -2] = Low, (-2, 1] = Neutral, (1, 5] = Buoyant, (5, 10] = Hope
const STATE_BOUNDARIES: Array[float] = [-10.0, -6.0, -2.0, 1.0, 5.0, 10.0]

# Emotional resistance multipliers
const RESISTANCE_EXTREME: float = 0.5
const RESISTANCE_NORMAL: float = 1.0

# 5-state tone prefix strings
const STATE_TONES: Array[String] = ["despair", "low", "neutral", "buoyant", "hope"]

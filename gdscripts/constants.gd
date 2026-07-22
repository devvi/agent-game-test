extends Node

# Constants — Threshold and priority constants for Theme-Mechanic Mapping Chain

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

extends Node

# StateSystem — Tri-axis state manager with bipolar Hope/Despair slider
# Manages hope_despair (-10 to +10), conviction (0-10), and will (0-10)
# Broadcasts state_changed signal for downstream modules
# See: docs/DESIGN/50-state-world-feedback.md

signal state_changed(state: Dictionary)

# Bipolar axis bounds
const HOPE_DESPAIR_MIN: float = -10.0
const HOPE_DESPAIR_MAX: float = 10.0

# Emotional resistance multiplier at extremes
const RESISTANCE_MILD: float = 0.5

# Five discrete state ranges (upper bound inclusive)
const STATE_DESPAIR_MAX: float = -6.0
const STATE_LOW_MAX: float = -2.0
const STATE_NEUTRAL_MAX: float = 1.0
const STATE_BUOYANT_MAX: float = 5.0

# Bipolar axis: -10 to +10, initialized at 0.0 (Neutral)
var hope_despair: float = 0.0

# Derived hope (0–10) for backward compatibility
# Setting hope directly updates hope_despair via inverse mapping
var hope: float:
	get:
		return (hope_despair + 10.0) / 2.0
	set(value):
		hope_despair = value * 2.0 - 10.0

var conviction: float = 5.0
var will: float = 5.0

func apply_choice(effect: Dictionary) -> void:
	# Handle hope_despair delta with emotional resistance
	if effect.has("hope_despair"):
		var delta: float = float(effect["hope_despair"])
		var cur_state_id: int = get_state_id()
		var delta_sign: int = 1 if delta > 0 else -1
		var multiplier: float = _get_resistance_multiplier(cur_state_id, delta_sign)
		hope_despair = clamp(hope_despair + delta * multiplier, HOPE_DESPAIR_MIN, HOPE_DESPAIR_MAX)

	# Handle legacy hope delta (maps to hope_despair, coarser scale)
	# 0-10 hope delta -> 0-20 hope_despair delta (2x scale factor)
	if effect.has("hope"):
		var hope_delta: float = float(effect["hope"])
		hope_despair = clamp(hope_despair + hope_delta * 2.0, HOPE_DESPAIR_MIN, HOPE_DESPAIR_MAX)

	conviction = clamp(conviction + effect.get("conviction", 0.0), 0.0, 10.0)
	will = clamp(will + effect.get("will", 0.0), 0.0, 10.0)
	state_changed.emit(get_state())

func get_state() -> Dictionary:
	return {"hope": hope, "hope_despair": hope_despair, "conviction": conviction, "will": will}

func reset() -> void:
	hope_despair = 0.0
	conviction = 5.0
	will = 5.0
	state_changed.emit(get_state())

## Return discrete state ID (1–5) based on hope_despair value.
## Upper bound inclusive: state 1 = [-10.0, -6.0], state 2 = (-6.0, -2.0], etc.
## Returns 1=Despair, 2=Low, 3=Neutral, 4=Buoyant, 5=Hope.
func get_state_id() -> int:
	if hope_despair <= STATE_DESPAIR_MAX:
		return 1
	elif hope_despair <= STATE_LOW_MAX:
		return 2
	elif hope_despair <= STATE_NEUTRAL_MAX:
		return 3
	elif hope_despair <= STATE_BUOYANT_MAX:
		return 4
	else:
		return 5

## Get resistance multiplier for emotional inertia.
## At Despair (state 1): positive deltas x0.5 (harder to escape)
## At Hope (state 5): negative deltas x0.5 (harder to fall)
## All other states return x1.0 (normal application).
func _get_resistance_multiplier(state_id: int, delta_sign: int) -> float:
	if state_id == 1 and delta_sign > 0:
		return RESISTANCE_MILD
	elif state_id == 5 and delta_sign < 0:
		return RESISTANCE_MILD
	return 1.0

## Get state tier label for a given axis.
## Returns "low" (0-3), "mid" (4-6), or "high" (7-10).
func get_state_tier(axis: String) -> String:
	var value: float = _get_axis(axis)
	if value <= 3.0:
		return "low"
	elif value >= 7.0:
		return "high"
	else:
		return "mid"


func _get_axis(axis: String) -> float:
	match axis:
		"hope": return hope
		"conviction": return conviction
		"will": return will
		_: return 5.0

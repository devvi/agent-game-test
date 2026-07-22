extends Node

# StateSystem — Tri-axis state manager with Hope/Despair slider
# Manages hope (0–10, derived), conviction, will (0–10), and hope_despair (-10 to +10)
# hope_despair is the authoritative bipolar slider; hope is derived as (hope_despair + 10) / 2
# Broadcasts state_changed signal for downstream modules
#
# 5 discrete emotional states:
#   1 (Despair): -10 to -6
#   2 (Low):     -5 to -2
#   3 (Neutral): -1 to +1
#   4 (Buoyant):  +2 to +5
#   5 (Hope):    +6 to +10
#
# Boundary rule: upper bound is inclusive (<=). E.g. -6.0 -> State 1, -5.9 -> State 2.

signal state_changed(state: Dictionary)

# Exported resistance multipliers for designer tuning
@export var resistance_despair: float = 0.5  # x0.5 when escaping Despair
@export var resistance_hope: float = 0.5     # x0.5 when falling from Hope

var hope_despair: float = 0.0  # Bipolar slider: -10 (despair) to +10 (hope), 0 = neutral
var hope: float = 5.0          # Derived: (hope_despair + 10) / 2.0
var conviction: float = 5.0
var will: float = 5.0

# Mid-dialogue state queuing
var _dialogue_active: bool = false
var _pending_state: Dictionary = {}  # buffered state change during active dialogue
var _pending_emit: bool = false


func _set_hope_despair(value: float) -> void:
	hope_despair = clampf(value, -10.0, 10.0)
	hope = (hope_despair + 10.0) / 2.0


## Apply a choice effect dict. Accepts "hope_despair" for the bipolar slider,
## as well as "hope", "conviction", "will" for the tri-axis system.
## The "hope_despair" key takes priority over "hope" if both are present.
func apply_choice(effect: Dictionary) -> void:
	# Handle hope_despair delta (bipolar slider)
	if effect.has("hope_despair"):
		var effective_delta: float = effect["hope_despair"]
		effective_delta = _apply_resistance(effective_delta)
		_set_hope_despair(hope_despair + effective_delta)
	elif effect.has("hope"):
		# Map 0-10 hope delta to -10/+10 slider space
		var raw_delta: float = effect["hope"] * 2.0
		var effective_delta: float = _apply_resistance(raw_delta)
		_set_hope_despair(hope_despair + effective_delta)

	# Handle traditional tri-axis effects
	conviction = clampf(conviction + effect.get("conviction", 0.0), 0.0, 10.0)
	will = clampf(will + effect.get("will", 0.0), 0.0, 10.0)

	_emit_or_queue_state()


## Apply a delta directly to the hope_despair slider with resistance and clamping.
func apply_hope_despair_delta(delta: float) -> void:
	var effective_delta: float = _apply_resistance(delta)
	_set_hope_despair(hope_despair + effective_delta)
	_emit_or_queue_state()


## Get the 5-state ID (1-5) for the current hope_despair value.
func get_state_id() -> int:
	var boundaries: Array[float] = [-10.0, -6.0, -2.0, 1.0, 5.0, 10.0]
	for i in range(boundaries.size() - 1):
		if hope_despair >= boundaries[i] and hope_despair <= boundaries[i + 1]:
			return i + 1
	# Fallback (shouldn't reach here given clamp)
	if hope_despair < -10.0:
		return 1
	return 5


## Get the tone prefix string for the current state.
func get_state_tone() -> String:
	var tones: Array[String] = ["despair", "low", "neutral", "buoyant", "hope"]
	var idx: int = clampi(get_state_id() - 1, 0, tones.size() - 1)
	return tones[idx]


## Get the full state dictionary including the new hope_despair key.
func get_state() -> Dictionary:
	return {"hope_despair": hope_despair, "hope": hope, "conviction": conviction, "will": will}


func reset() -> void:
	_set_hope_despair(0.0)
	conviction = 5.0
	will = 5.0
	_emit_or_queue_state()


## Set dialogue active flag. When true, state changes are queued instead of emitted.
func set_dialogue_active(active: bool) -> void:
	_dialogue_active = active
	if not active and _pending_emit:
		# Flush buffered state change
		_pending_emit = false
		state_changed.emit(get_state())
		_pending_state = {}


## Apply resistance multiplier to a delta based on current state.
## When in Despair (state 1), upward deltas are reduced by resistance_despair.
## When in Hope (state 5), downward deltas are reduced by resistance_hope.
func _apply_resistance(delta: float) -> float:
	var state_id: int = get_state_id()

	# Moving toward hope in despair - reduced
	if state_id == 1 and delta > 0.0:
		return delta * resistance_despair

	# Moving toward despair in hope - reduced
	if state_id == 5 and delta < 0.0:
		return delta * resistance_hope

	return delta * 1.0


## Emit state_changed immediately, or queue if dialogue is active.
func _emit_or_queue_state() -> void:
	if _dialogue_active:
		_pending_emit = true
		_pending_state = get_state()
	else:
		state_changed.emit(get_state())

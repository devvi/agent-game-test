extends Node

# RainController — Maps hope_despair slider to rain intensity
# Higher hope = lower rain intensity (inverse relationship)
# 5 discrete rain levels mapped from 5 slider states
# Also retains conviction-based mapping for backward compatibility.
#
# Rain intensity per state:
#   State 1 (Despair): 1.0  — downpour
#   State 2 (Low):     0.75 — steady rain
#   State 3 (Neutral): 0.5  — light rain
#   State 4 (Buoyant): 0.25 — drizzle
#   State 5 (Hope):    0.0  — let-up

signal forced_shelter_triggered()

const RAIN_CHECK_INTERVAL: float = 30.0
const SHELTER_THRESHOLD: float = 7.0

# 5 discrete rain intensity levels mapped by state ID (1–5)
const RAIN_INTENSITY_LEVELS: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0]

var rain_intensity: float = 0.0


func _ready() -> void:
	var state_system = get_node_or_null("/root/StateSystem")
	if state_system:
		state_system.state_changed.connect(_on_state_changed)
	var timer := Timer.new()
	timer.wait_time = RAIN_CHECK_INTERVAL
	timer.timeout.connect(_check_rain)
	add_child(timer)
	timer.start()


func _on_state_changed(state: Dictionary) -> void:
	# Prefer hope_despair for rain mapping (5-state), fall back to conviction
	var hd: float = state.get("hope_despair", -1.0)
	if hd >= -9.0:
		# Map hope_despair to 5 rain levels
		var state_id: int = _hope_despair_to_state_id(hd)
		var idx: int = clampi(state_id - 1, 0, RAIN_INTENSITY_LEVELS.size() - 1)
		rain_intensity = RAIN_INTENSITY_LEVELS[idx]
	else:
		# Legacy: map from conviction (backward compatible)
		rain_intensity = clampf((10.0 - state.get("conviction", 5.0)) / 10.0, 0.0, 1.0)


func _hope_despair_to_state_id(value: float) -> int:
	var boundaries: Array[float] = [-10.0, -6.0, -2.0, 1.0, 5.0, 10.0]
	for i in range(boundaries.size() - 1):
		if value >= boundaries[i] and value <= boundaries[i + 1]:
			return i + 1
	if value < -10.0:
		return 1
	return 5


func _check_rain() -> void:
	if rain_intensity >= SHELTER_THRESHOLD / 10.0:
		forced_shelter_triggered.emit()


func get_intensity() -> float:
	return rain_intensity

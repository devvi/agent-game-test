extends Node

# RainController — Maps hope to rain intensity (inverse relationship)
# Re-mapped from conviction to hope for Issue #50.
# Higher rain intensity = lower hope.
# 5 intensity levels matching 5 slider states.
# Triggers forced shelter when rain intensity exceeds threshold.

signal forced_shelter_triggered()

const RAIN_CHECK_INTERVAL: float = 30.0
const SHELTER_THRESHOLD: float = 7.0

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
	# Rain intensity inversely proportional to hope: (10.0 - hope) / 10.0
	# Was conviction-based in Issue #42; now hope-based per Issue #50
	var hope_val: float = state.get("hope", 5.0)
	rain_intensity = clamp((10.0 - hope_val) / 10.0, 0.0, 1.0)

func _check_rain() -> void:
	if rain_intensity >= SHELTER_THRESHOLD / 10.0:
		forced_shelter_triggered.emit()

func get_intensity() -> float:
	return rain_intensity

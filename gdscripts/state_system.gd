extends Node

# StateSystem — Tri-axis state manager
# Manages hope, conviction, and will values (0–10, 5=neutral)
# Broadcasts state_changed signal for downstream modules

signal state_changed(state: Dictionary)

var hope: float = 5.0
var conviction: float = 5.0
var will: float = 5.0

func apply_choice(effect: Dictionary) -> void:
	hope = clamp(hope + effect.get("hope", 0.0), 0.0, 10.0)
	conviction = clamp(conviction + effect.get("conviction", 0.0), 0.0, 10.0)
	will = clamp(will + effect.get("will", 0.0), 0.0, 10.0)
	state_changed.emit(get_state())

func get_state() -> Dictionary:
	return {"hope": hope, "conviction": conviction, "will": will}

func reset() -> void:
	hope = 5.0
	conviction = 5.0
	will = 5.0
	state_changed.emit(get_state())

## Get state tier label for a given axis.
## Returns "low" (0-3), "mid" (4-6), or "high" (7-10).
func get_state_tier(axis: String) -> String:
	var value: float = get(axis, 5.0)
	if value <= 3.0:
		return "low"
	elif value >= 7.0:
		return "high"
	else:
		return "mid"

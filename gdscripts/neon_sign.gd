class_name NeonSign
extends "res://gdscripts/text_component_base.gd"

## NeonSign — Uses the 'conviction' axis for state determination.
## Overrides _calculate_state_id to derive state from conviction instead of hope.
## This makes neon signs reflect the player's conviction/belief,
## creating visual dissonance when conviction diverges from hope.

func _calculate_state_id(state: Dictionary) -> int:
	var conviction_val: float = state.get("conviction", 5.0)
	return _conviction_to_state_id(conviction_val)

## Map conviction (0-10) to state ID (1-5).
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

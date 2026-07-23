class_name LamppostText
extends "res://gdscripts/text_component_base.gd"

## LamppostText — Uses the 'will' axis for state determination.
## Overrides _calculate_state_id to derive state from will instead of hope.
## This makes lamppost text reflect the player's resolve/willpower,
## which can differ from their hope level, creating interesting dissonance.

func _calculate_state_id(state: Dictionary) -> int:
	var will_val: float = state.get("will", 5.0)
	return _will_to_state_id(will_val)

## Map will (0-10) to state ID (1-5).
static func _will_to_state_id(will: float) -> int:
	if will <= 2.0:
		return 1
	elif will <= 4.0:
		return 2
	elif will <= 6.0:
		return 3
	elif will <= 8.0:
		return 4
	else:
		return 5

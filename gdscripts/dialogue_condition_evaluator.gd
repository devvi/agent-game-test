extends RefCounted
class_name DialogueConditionEvaluator

## Supported condition types:
## - slider:  {"type": "slider", "axis": "hope", "op": "gte", "value": 5}
## - flag:    {"type": "flag", "flag": "met_bartender", "value": true}
## - choice_made: {"type": "choice_made", "node_id": "n_01", "choice_index": 0}
## - and:     {"type": "and", "conditions": [Cond, Cond, ...]}
## - or:      {"type": "or", "conditions": [Cond, Cond, ...]}
## - not:     {"type": "not", "condition": Cond}
##
## state is a Dictionary: { "sliders": {...}, "flags": {...}, "choices_made": [...] }

static func evaluate(condition: Dictionary, state: Dictionary) -> bool:
	var ctype: String = condition.get("type", "")
	match ctype:
		"slider":
			return _eval_slider(condition, state.get("sliders", {}))
		"flag":
			return _eval_flag(condition, state.get("flags", {}))
		"choice_made":
			return _eval_choice_made(condition, state.get("choices_made", []))
		"and":
			return _eval_and(condition, state)
		"or":
			return _eval_or(condition, state)
		"not":
			return _eval_not(condition, state)
		_:
			push_warning("Unknown condition type: '%s'" % ctype)
			return false


static func _eval_slider(cond: Dictionary, sliders: Dictionary) -> bool:
	var axis: String = cond.get("axis", "")
	var op: String = cond.get("op", "eq")
	var value: float = float(cond.get("value", 0))
	var current: float = float(sliders.get(axis, 0.0))
	match op:
		"gte": return current >= value
		"lte": return current <= value
		"gt":  return current > value
		"lt":  return current < value
		"eq":  return current == value
		_:
			push_warning("Unknown slider operator: '%s'" % op)
			return false


static func _eval_flag(cond: Dictionary, flags: Dictionary) -> bool:
	var flag_name: String = cond.get("flag", "")
	var expected: bool = bool(cond.get("value", true))
	return flags.get(flag_name, false) == expected


static func _eval_choice_made(cond: Dictionary, choices_made: Array) -> bool:
	var node_id: String = cond.get("node_id", "")
	var choice_idx: int = int(cond.get("choice_index", -1))
	for entry in choices_made:
		if typeof(entry) == TYPE_DICTIONARY:
			if entry.get("node_id") == node_id and entry.get("choice_index") == choice_idx:
				return true
	return false


static func _eval_and(cond: Dictionary, state: Dictionary) -> bool:
	var conditions: Array = cond.get("conditions", [])
	for c in conditions:
		if typeof(c) == TYPE_DICTIONARY:
			if not evaluate(c, state):
				return false
	return true


static func _eval_or(cond: Dictionary, state: Dictionary) -> bool:
	var conditions: Array = cond.get("conditions", [])
	for c in conditions:
		if typeof(c) == TYPE_DICTIONARY:
			if evaluate(c, state):
				return true
	return false


static func _eval_not(cond: Dictionary, state: Dictionary) -> bool:
	var inner: Variant = cond.get("condition", {})
	if typeof(inner) == TYPE_DICTIONARY:
		return not evaluate(inner, state)
	return false

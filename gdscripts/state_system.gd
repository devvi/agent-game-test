extends Node

# StateSystem — Tri-axis state manager with bipolar Hope/Despair slider
# Manages hope_despair (-10 to +10), conviction (0-10), and will (0-10)
# Provides flags system, choice history, and save/load serialization
# See: docs/DESIGN/47-gamestate-system.md

signal state_changed(state: Dictionary)
## Emitted on every apply_choice() / load_state_from_file() call.
## state dict contains: hope_despair, hope, conviction, will, state_id, flags, choice_count

signal state_id_changed(state_id: int)
## Emitted ONLY when the discrete state ID changes (not on every slider tick).

# ── Constants ──

# Bipolar axis bounds
const HOPE_DESPAIR_MIN: float = -10.0
const HOPE_DESPAIR_MAX: float = 10.0

# Emotional resistance multiplier at extremes
const RESISTANCE_MILD: float = 0.5

# Five discrete state ranges (upper bound inclusive) per DESIGN #47
const STATE_DESPAIR_MAX: float = -6.0
const STATE_LOW_MAX: float = -2.0
const STATE_NEUTRAL_MAX: float = 2.0
const STATE_BUOYANT_MAX: float = 6.0

# Choice history cap
const CHOICE_HISTORY_MAX: int = 200

# Save schema version
const SAVE_VERSION: int = 1

# ── Bipolar Slider ──

# Bipolar axis: -10 to +10, initialized at 0.0 (Neutral)
var hope_despair: float = 0.0:
	set(value):
		hope_despair = clamp(value, HOPE_DESPAIR_MIN, HOPE_DESPAIR_MAX)

# Derived hope (0–10) for backward compatibility
# Setting hope directly updates hope_despair via inverse mapping
var hope: float:
	get:
		return (hope_despair + 10.0) / 2.0
	set(value):
		hope_despair = value * 2.0 - 10.0

# Derived despair (0–10) — read-only mirror of hope
var despair: float:
	get:
		return 10.0 - hope

# ── Tri-axis (Existing) ──

var conviction: float = 5.0:
	set(value):
		conviction = clamp(value, 0.0, 10.0)
var will: float = 5.0:
	set(value):
		will = clamp(value, 0.0, 10.0)

# ── Flags ──

var _flags: Dictionary = {}

# ── Choice History ──

var _choice_history: Array[Dictionary] = []

# ===== Core API =====

func apply_choice(effect: Dictionary) -> void:
	var old_state_id: int = get_state_id()

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

	var new_state_id: int = get_state_id()
	var state_dict: Dictionary = get_state()
	state_changed.emit(state_dict)

	if old_state_id != new_state_id:
		state_id_changed.emit(new_state_id)

func get_state() -> Dictionary:
	return {
		"hope": hope,
		"despair": despair,
		"hope_despair": hope_despair,
		"conviction": conviction,
		"will": will,
		"state_id": get_state_id(),
		"flags": get_flags(),
		"choice_count": get_choice_count()
	}

func reset() -> void:
	hope_despair = 0.0
	conviction = 5.0
	will = 5.0
	_flags = {}
	_choice_history = []
	state_changed.emit(get_state())

# ===== State ID =====

## Return discrete state ID (1–5) based on hope_despair value.
## Upper bound inclusive: state 1 = [-10.0, -6.0], state 2 = (-6.0, -2.0],
## state 3 = (-2.0, +2.0], state 4 = (+2.0, +6.0], state 5 = (+6.0, +10.0]
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

# ===== Flags API =====

## Set a boolean flag. Creates the flag key if it doesn't exist.
func set_flag(name: String, value: bool) -> void:
	_flags[name] = value

## Check if a named flag is set (true). Returns false for unset flags.
func has_flag(name: String) -> bool:
	return _flags.get(name, false) == true

## Get all flags as a Dictionary copy.
func get_flags() -> Dictionary:
	return _flags.duplicate()

# ===== Choice History API =====

## Record a dialogue choice in history. Caps at 200 entries (oldest dropped).
func record_choice(node_id: String, choice_index: int, choice_text: String) -> void:
	var record: Dictionary = {
		"node_id": node_id,
		"choice_index": choice_index,
		"choice_text": choice_text,
		"timestamp": Time.get_ticks_msec()
	}
	_choice_history.append(record)
	while _choice_history.size() > CHOICE_HISTORY_MAX:
		_choice_history.pop_front()

## Get a copy of the full choice history array.
func get_choice_history() -> Array[Dictionary]:
	return _choice_history.duplicate()

## Get the number of choices made this session.
func get_choice_count() -> int:
	return _choice_history.size()

# ===== Save/Load =====

## Serialize all game state to a JSON file at the given path.
## Returns true on success, false on failure.
## Creates parent directories automatically.
func save_state_to_file(path: String) -> bool:
	var save_dict: Dictionary = _to_save_dict()
	var json_string: String = JSON.stringify(save_dict, "\t")

	var dir: DirAccess = DirAccess.open(path.get_base_dir())
	if dir == null:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("StateSystem.save_state_to_file: could not open '%s' for writing" % path)
		return false

	file.store_string(json_string)
	file.close()
	return true

## Deserialize game state from a JSON file.
## Validates version field (must match current version).
## Returns true on success, false on failure.
## Emits a single state_changed after full restore.
func load_state_from_file(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("StateSystem.load_state_from_file: file not found '%s'" % path)
		return false

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)
	if parse_result != OK:
		push_warning("StateSystem.load_state_from_file: corrupt JSON in '%s'" % path)
		return false

	var data: Dictionary = json.data
	if not data.has("version") or data["version"] != SAVE_VERSION:
		push_warning("StateSystem.load_state_from_file: version mismatch in '%s'" % path)
		return false

	_from_save_dict(data)
	state_changed.emit(get_state())
	return true

# ===== Internal Helpers =====

## Convert current state to a serializable Dictionary.
func _to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"hope_despair": hope_despair,
		"conviction": conviction,
		"will": will,
		"flags": _flags.duplicate(),
		"choice_history": _choice_history.duplicate()
	}

## Restore state from a Dictionary returned by _to_save_dict().
func _from_save_dict(data: Dictionary) -> void:
	hope_despair = float(data.get("hope_despair", 0.0))
	conviction = float(data.get("conviction", 5.0))
	will = float(data.get("will", 5.0))
	_flags = (data.get("flags", {})).duplicate()
	_choice_history.clear()
	for entry in data.get("choice_history", []):
		_choice_history.append(entry)

## Calculate state_id from hope_despair value using the 5-state mapping.
func _calculate_state_id(value: float) -> int:
	if value <= STATE_DESPAIR_MAX:
		return 1
	elif value <= STATE_LOW_MAX:
		return 2
	elif value <= STATE_NEUTRAL_MAX:
		return 3
	elif value <= STATE_BUOYANT_MAX:
		return 4
	else:
		return 5

## Get axis value by string name.
func _get_axis_value(axis: String) -> float:
	match axis:
		"hope_despair": return hope_despair
		"hope": return hope
		"despair": return despair
		"conviction": return conviction
		"will": return will
		_: return 5.0

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

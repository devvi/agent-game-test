extends RefCounted

# Unit tests for StatusBar (hope/despair status bar controller)
# Tests value mapping, layout, and colour interpolation.
# See: docs/DESIGN/53-ui-system.md

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== StatusBar Unit Tests (Issue #53) ===")

	_test_tc1_state_changed_maps_hope_despair()
	_test_tc2_state_changed_clamps_extremes()
	_test_tc3_state_changed_neutral_is_centre()
	_test_tc4_state_changed_missing_field_defaults()
	_test_tc5_hope_color_constant()
	_test_tc6_despair_color_constant()
	_test_tc7_color_lerp_at_neutral()
	_test_tc8_color_lerp_at_despair()
	_test_tc9_color_lerp_at_hope()
	_test_tc10_ratio_mapping_linearity()

	print("StatusBar Unit — Passed: ", passed, " Failed: ", failed)


func _make_status_bar():
	var sb = load("res://gdscripts/status_bar.gd").new()
	return sb


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_tc1_state_changed_maps_hope_despair() -> void:
	var sb = _make_status_bar()
	sb._on_state_changed({"hope_despair": 0.0})
	_assert(abs(sb._current_ratio - 0.5) < 0.001, "TC1-1: hope_despair=0 -> ratio=0.5 (neutral)")

	sb._on_state_changed({"hope_despair": 10.0})
	_assert(abs(sb._current_ratio - 1.0) < 0.001, "TC1-2: hope_despair=10 -> ratio=1.0 (max hope)")

	sb._on_state_changed({"hope_despair": -10.0})
	_assert(abs(sb._current_ratio - 0.0) < 0.001, "TC1-3: hope_despair=-10 -> ratio=0.0 (max despair)")


func _test_tc2_state_changed_clamps_extremes() -> void:
	var sb = _make_status_bar()
	sb._on_state_changed({"hope_despair": 15.0})
	_assert(abs(sb._current_ratio - 1.0) < 0.001, "TC2-1: hope_despair=15 -> clamped to ratio=1.0")

	sb._on_state_changed({"hope_despair": -15.0})
	_assert(abs(sb._current_ratio - 0.0) < 0.001, "TC2-2: hope_despair=-15 -> clamped to ratio=0.0")


func _test_tc3_state_changed_neutral_is_centre() -> void:
	var sb = _make_status_bar()
	sb._on_state_changed({"hope_despair": 0.0})
	_assert(abs(sb._current_ratio - 0.5) < 0.001, "TC3-1: hope_despair=0 -> ratio=0.5")

	# +1 and -1 should be symmetric around 0.5
	sb._on_state_changed({"hope_despair": 1.0})
	var ratio_plus1: float = sb._current_ratio
	sb._on_state_changed({"hope_despair": -1.0})
	var ratio_minus1: float = sb._current_ratio
	_assert(abs(ratio_plus1 + ratio_minus1 - 1.0) < 0.001, "TC3-2: +1 and -1 are symmetric around 0.5")


func _test_tc4_state_changed_missing_field_defaults() -> void:
	var sb = _make_status_bar()
	sb._on_state_changed({})
	_assert(abs(sb._current_ratio - 0.5) < 0.001, "TC4-1: empty state -> ratio=0.5 (default hope_despair=0)")

	sb._on_state_changed({"hope_despair": 5.0})
	sb._on_state_changed({"hope": 10.0})  # Wrong key name — should use hope_despair
	_assert(abs(sb._current_ratio - 0.5) < 0.001, "TC4-2: 'hope' key instead of 'hope_despair' uses default 0 -> ratio=0.5")


func _test_tc5_hope_color_constant() -> void:
	var sb = _make_status_bar()
	_assert(sb.HOPE_COLOR.to_html() == "ffb000", "TC5-1: HOPE_COLOR = #FFB000")


func _test_tc6_despair_color_constant() -> void:
	var sb = _make_status_bar()
	_assert(sb.DESPAIR_COLOR.to_html() == "2a2a4a", "TC6-1: DESPAIR_COLOR = #2A2A4A")


func _test_tc7_color_lerp_at_neutral() -> void:
	var sb = _make_status_bar()
	var neutral_color := sb.DESPAIR_COLOR.lerp(sb.HOPE_COLOR, 0.5)
	# Neutral should be a midpoint between dark blue and amber
	_assert(neutral_color.r > 0.3, "TC7-1: neutral colour has r > 0.3 (warm component)")
	_assert(neutral_color.b > neutral_color.r * 0.5, "TC7-2: neutral colour has b > r/2 (cool component)")


func _test_tc8_color_lerp_at_despair() -> void:
	var sb = _make_status_bar()
	# ratio=0.0 (max despair) → DESPAIR_COLOR (dark blue)
	var despair_color := sb.DESPAIR_COLOR.lerp(sb.HOPE_COLOR, 0.0)
	_assert(despair_color.to_html() == "2a2a4a", "TC8-1: ratio=0.0 gives DESPAIR_COLOR (#2A2A4A)")


func _test_tc9_color_lerp_at_hope() -> void:
	var sb = _make_status_bar()
	# ratio=1.0 (max hope) → HOPE_COLOR (amber)
	var hope_color := sb.DESPAIR_COLOR.lerp(sb.HOPE_COLOR, 1.0)
	_assert(hope_color.to_html() == "ffb000", "TC9-1: ratio=1.0 gives HOPE_COLOR (#FFB000)")


func _test_tc10_ratio_mapping_linearity() -> void:
	var sb = _make_status_bar()
	# The mapping from hope_despair -> ratio should be linear
	var ratios: Array[float] = []
	for val in range(-10, 11, 2):
		sb._on_state_changed({"hope_despair": float(val)})
		ratios.append(sb._current_ratio)
	# Check monotonic
	for i in range(1, ratios.size()):
		_assert(ratios[i] > ratios[i - 1], "TC10-%d: ratio increases monotonically (%.2f > %.2f)" % [i, ratios[i], ratios[i - 1]])

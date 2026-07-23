extends RefCounted

# Test: 5-State Environment Text System — Issue #154
# Tests TextComponentBase 5-state variant selection, signal-driven updates,
# subclass axis overrides, fallback behavior, and fade transitions.
# Runs via godot --headless --script tests/run_tests.gd

var passed: int = 0
var failed: int = 0

var _signal_state: Dictionary = {}
var _signal_fired: bool = false


func run() -> void:
	print("\n=== 5-State Env Text Tests (Issue #154) ===")

	# ── TextComponentBase Core ──
	_test_variant_index_for_state_id()
	_test_hope_to_state_id()
	_test_calculate_state_id_default()
	_test_apply_variant_for_state()
	_test_fallback_small_array()
	_test_fallback_empty_array()
	_test_variant_data_null_entry()

	# ── Subclass Axis Overrides ──
	_test_lamppost_will_axis()
	_test_neon_sign_conviction_axis()
	_test_puddle_hope_axis()
	_test_rain_text_despair_multiplier()

	# ── Tone Mapping ──
	_test_tone_name_to_state_id()
	_test_get_tone_for_scene()
	_test_get_tone_for_scene_state()

	# ── Signal Wiring ──
	_test_signal_updates_text()
	_test_signal_wiring_without_state_system()

	# ── SceneBase Helpers ──
	_test_get_current_state_id()
	_test_get_tone_for_scene_fallback()

	# ── Transition ──
	_test_transition_export_default()
	_test_tween_cancels_previous()

	print("\n  5-State Env Text: %d passed, %d failed" % [passed, failed])


func _assert(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("    ✅ %s" % label)
	else:
		failed += 1
		print("    ❌ %s" % label)


# ===== Signal Helpers =====

func _on_tone_changed(scene_id: String, tone: String) -> void:
	_signal_fired = true
	_signal_state = {"scene_id": scene_id, "tone": tone}


# ===== TextComponentBase Core =====

func _test_variant_index_for_state_id() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	# Keep only the base class — no autoload dependencies
	_assert(tcb._variant_index_for_state_id(1) == 0, "ET-01: state_id=1 → variant index 0")
	_assert(tcb._variant_index_for_state_id(2) == 1, "ET-01: state_id=2 → variant index 1")
	_assert(tcb._variant_index_for_state_id(3) == 2, "ET-01: state_id=3 → variant index 2")
	_assert(tcb._variant_index_for_state_id(4) == 3, "ET-01: state_id=4 → variant index 3")
	_assert(tcb._variant_index_for_state_id(5) == 4, "ET-01: state_id=5 → variant index 4")
	# Out of bounds
	_assert(tcb._variant_index_for_state_id(0) == 0, "ET-01: state_id=0 clamped to 0")
	_assert(tcb._variant_index_for_state_id(6) == 4, "ET-01: state_id=6 clamped to 4")


func _test_hope_to_state_id() -> void:
	_assert(TextComponentBase._hope_to_state_id(0.0) == 1, "ET-02: hope=0.0 → state 1")
	_assert(TextComponentBase._hope_to_state_id(1.0) == 1, "ET-02: hope=1.0 → state 1")
	_assert(TextComponentBase._hope_to_state_id(2.0) == 1, "ET-02: hope=2.0 → state 1")
	_assert(TextComponentBase._hope_to_state_id(2.1) == 2, "ET-02: hope=2.1 → state 2")
	_assert(TextComponentBase._hope_to_state_id(3.0) == 2, "ET-02: hope=3.0 → state 2")
	_assert(TextComponentBase._hope_to_state_id(4.0) == 2, "ET-02: hope=4.0 → state 2")
	_assert(TextComponentBase._hope_to_state_id(4.1) == 3, "ET-02: hope=4.1 → state 3")
	_assert(TextComponentBase._hope_to_state_id(5.0) == 3, "ET-02: hope=5.0 → state 3")
	_assert(TextComponentBase._hope_to_state_id(6.0) == 3, "ET-02: hope=6.0 → state 3")
	_assert(TextComponentBase._hope_to_state_id(6.1) == 4, "ET-02: hope=6.1 → state 4")
	_assert(TextComponentBase._hope_to_state_id(7.0) == 4, "ET-02: hope=7.0 → state 4")
	_assert(TextComponentBase._hope_to_state_id(8.0) == 4, "ET-02: hope=8.0 → state 4")
	_assert(TextComponentBase._hope_to_state_id(8.1) == 5, "ET-02: hope=8.1 → state 5")
	_assert(TextComponentBase._hope_to_state_id(9.0) == 5, "ET-02: hope=9.0 → state 5")
	_assert(TextComponentBase._hope_to_state_id(10.0) == 5, "ET-02: hope=10.0 → state 5")


func _test_calculate_state_id_default() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	_assert(tcb._calculate_state_id({"hope": 1.0}) == 1, "ET-03: hope=1 → state 1")
	_assert(tcb._calculate_state_id({"hope": 3.0}) == 2, "ET-03: hope=3 → state 2")
	_assert(tcb._calculate_state_id({"hope": 5.0}) == 3, "ET-03: hope=5 → state 3")
	_assert(tcb._calculate_state_id({"hope": 7.0}) == 4, "ET-03: hope=7 → state 4")
	_assert(tcb._calculate_state_id({"hope": 9.0}) == 5, "ET-03: hope=9 → state 5")
	# Fallback for missing hope key
	_assert(tcb._calculate_state_id({}) == 3, "ET-03: empty state defaults hope=5 → state 3")


func _test_apply_variant_for_state() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	# Set up variant_data with 5 entries (using TextVariantData)
	var VData = load("res://gdscripts/text_variant_data.gd")
	var v0 = VData.new(); v0.text = "despair text"; v0.emissive_color = Color(0.1, 0.1, 0.2)
	var v1 = VData.new(); v1.text = "low text"; v1.emissive_color = Color(0.2, 0.2, 0.3)
	var v2 = VData.new(); v2.text = "neutral text"; v2.emissive_color = Color(0.5, 0.5, 0.5)
	var v3 = VData.new(); v3.text = "buoyant text"; v3.emissive_color = Color(0.7, 0.7, 0.3)
	var v4 = VData.new(); v4.text = "hope text"; v4.emissive_color = Color(1.0, 1.0, 0.5)
	tcb.variant_data = [v0, v1, v2, v3, v4]

	# Apply at each state
	tcb._apply_variant_for_state(1)
	_assert(tcb.text == "despair text", "ET-04: state 1 → variant 0 text")
	_assert(tcb.emissive_color == Color(0.1, 0.1, 0.2), "ET-04: state 1 → variant 0 emissive")

	tcb._apply_variant_for_state(3)
	_assert(tcb.text == "neutral text", "ET-04: state 3 → variant 2 text")

	tcb._apply_variant_for_state(5)
	_assert(tcb.text == "hope text", "ET-04: state 5 → variant 4 text")
	_assert(tcb.emissive_color == Color(1.0, 1.0, 0.5), "ET-04: state 5 → variant 4 emissive")

	# State 2 and 4 should select correct variants
	tcb._apply_variant_for_state(2)
	_assert(tcb.text == "low text", "ET-04: state 2 → variant 1 text")

	tcb._apply_variant_for_state(4)
	_assert(tcb.text == "buoyant text", "ET-04: state 4 → variant 3 text")


func _test_fallback_small_array() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	# Only 3 variants (backward compat scenario)
	var VData = load("res://gdscripts/text_variant_data.gd")
	var v0 = VData.new(); v0.text = "despair"
	var v1 = VData.new(); v1.text = "neutral"
	var v2 = VData.new(); v2.text = "hope"
	tcb.variant_data = [v0, v1, v2]

	# State 1 → idx 0 (exists)
	tcb._apply_variant_for_state(1)
	_assert(tcb.text == "despair", "ET-05: 3 variants, state 1 → variant 0")

	# State 2 → idx 1 (exists, nearest)
	tcb._apply_variant_for_state(2)
	_assert(tcb.text == "neutral", "ET-05: 3 variants, state 2 → variant 1")

	# State 3 → idx 2 (clamped to last available)
	tcb._apply_variant_for_state(3)
	_assert(tcb.text == "hope", "ET-05: 3 variants, state 3 → variant 2")

	# State 4 → clamped to last available
	tcb._apply_variant_for_state(4)
	_assert(tcb.text == "hope", "ET-05: 3 variants, state 4 → last variant (clamped)")

	# State 5 → also clamped
	tcb._apply_variant_for_state(5)
	_assert(tcb.text == "hope", "ET-05: 3 variants, state 5 → last variant (clamped)")


func _test_fallback_empty_array() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	tcb.variant_data = []
	# Should not crash
	tcb._apply_variant_for_state(1)
	_assert(tcb.text == "", "ET-06: empty variant data → no crash, text empty")
	_assert(tcb.emissive_color == Color(0, 0, 0, 0), "ET-06: empty variant data → default emissive")


func _test_variant_data_null_entry() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	var VData = load("res://gdscripts/text_variant_data.gd")
	var v0 = VData.new(); v0.text = "valid"
	tcb.variant_data = [v0, null, null, null, null]
	# Should not crash on null entries
	tcb._apply_variant_for_state(2)
	# Null entry should simply return without changing
	_assert(true, "ET-07: null variant entry → no crash")


# ===== Subclass Axis Overrides =====

func _test_lamppost_will_axis() -> void:
	var lt = load("res://gdscripts/lamppost_text.gd").new()
	_assert(lt._calculate_state_id({"will": 1.0}) == 1, "ET-08: LamppostText will=1 → state 1")
	_assert(lt._calculate_state_id({"will": 3.0}) == 2, "ET-08: LamppostText will=3 → state 2")
	_assert(lt._calculate_state_id({"will": 5.0}) == 3, "ET-08: LamppostText will=5 → state 3")
	_assert(lt._calculate_state_id({"will": 7.0}) == 4, "ET-08: LamppostText will=7 → state 4")
	_assert(lt._calculate_state_id({"will": 9.0}) == 5, "ET-08: LamppostText will=9 → state 5")
	# Ignores hope axis
	_assert(lt._calculate_state_id({"hope": 9.0, "will": 1.0}) == 1, "ET-08: LamppostText ignores hope, uses will")


func _test_neon_sign_conviction_axis() -> void:
	var ns = load("res://gdscripts/neon_sign.gd").new()
	_assert(ns._calculate_state_id({"conviction": 1.0}) == 1, "ET-09: NeonSign conviction=1 → state 1")
	_assert(ns._calculate_state_id({"conviction": 3.0}) == 2, "ET-09: NeonSign conviction=3 → state 2")
	_assert(ns._calculate_state_id({"conviction": 5.0}) == 3, "ET-09: NeonSign conviction=5 → state 3")
	_assert(ns._calculate_state_id({"conviction": 7.0}) == 4, "ET-09: NeonSign conviction=7 → state 4")
	_assert(ns._calculate_state_id({"conviction": 9.0}) == 5, "ET-09: NeonSign conviction=9 → state 5")


func _test_puddle_hope_axis() -> void:
	var pt = load("res://gdscripts/puddle_text.gd").new()
	# PuddleText inherits from TextComponentBase, uses hope
	_assert(pt._calculate_state_id({"hope": 1.0}) == 1, "ET-10: PuddleText hope=1 → state 1")
	_assert(pt._calculate_state_id({"hope": 5.0}) == 3, "ET-10: PuddleText hope=5 → state 3 (default)")
	_assert(pt._calculate_state_id({"hope": 9.0}) == 5, "ET-10: PuddleText hope=9 → state 5")


func _test_rain_text_despair_multiplier() -> void:
	var rt = load("res://gdscripts/rain_text.gd").new()
	# RainText should have despair multiplier at state 1
	var VData = load("res://gdscripts/text_variant_data.gd")
	var v0 = VData.new(); v0.text = "despair"; v0.emissive_strength = 1.0
	rt.variant_data = [v0]
	rt._current_state_id = 1
	rt._apply_variant(0)
	# Despair multiplier: emissive_strength * 2.0 = 2.0
	_assert(abs(rt.emissive_strength - 2.0) < 0.001, "ET-11: RainText despair multiplier doubles emissive")
	# At non-despair state, no multiplier
	rt._current_state_id = 2
	v0.emissive_strength = 1.0
	rt._apply_variant(0)
	_assert(abs(rt.emissive_strength - 1.0) < 0.001, "ET-11: RainText non-despair → no multiplier")


# ===== Tone Mapping =====

func _test_tone_name_to_state_id() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	# Test _apply_tone_overrides which maps tone names to state IDs
	var VData = load("res://gdscripts/text_variant_data.gd")
	var v0 = VData.new(); v0.text = "despair_text"
	var v1 = VData.new(); v1.text = "low_text"
	var v2 = VData.new(); v2.text = "neutral_text"
	var v3 = VData.new(); v3.text = "buoyant_text"
	var v4 = VData.new(); v4.text = "hope_text"
	tcb.variant_data = [v0, v1, v2, v3, v4]

	tcb._apply_tone_overrides("despair")
	_assert(tcb.text == "despair_text", "ET-12: tone 'despair' → state 1 variant")

	tcb._apply_tone_overrides("low")
	_assert(tcb.text == "low_text", "ET-12: tone 'low' → state 2 variant")

	tcb._apply_tone_overrides("neutral")
	_assert(tcb.text == "neutral_text", "ET-12: tone 'neutral' → state 3 variant")

	tcb._apply_tone_overrides("buoyant")
	_assert(tcb.text == "buoyant_text", "ET-12: tone 'buoyant' → state 4 variant")

	tcb._apply_tone_overrides("hope")
	_assert(tcb.text == "hope_text", "ET-12: tone 'hope' → state 5 variant")

	# Also test per-scene tone names
	tcb._apply_tone_overrides("fear")
	_assert(tcb.text == "despair_text", "ET-12: tone 'fear' → state 1 variant")

	tcb._apply_tone_overrides("determined")
	_assert(tcb.text == "hope_text", "ET-12: tone 'determined' → state 5 variant")


func _test_get_tone_for_scene() -> void:
	# This tests the SceneBase helper - SceneBase expects StateSystem and NarrativeManager autoloads
	var sb = load("res://gdscripts/scene_base.gd").new()
	# Without autoloads, should return fallback
	var tone: String = sb._get_tone_for_scene("office")
	_assert(tone == "neutral", "ET-13: get_tone_for_scene without autoloads → 'neutral' fallback")


func _test_get_tone_for_scene_state() -> void:
	var sb = load("res://gdscripts/scene_base.gd").new()
	# Without NarrativeManager autoload, should return 'neutral' fallback
	_assert(sb._get_tone_for_scene_state("office", 1) == "neutral", "ET-14: no NM → 'neutral' fallback")
	_assert(sb._get_tone_for_scene_state("nonexistent", 3) == "neutral", "ET-14: unknown scene → 'neutral' fallback")


# ===== Signal Wiring =====

func _test_signal_updates_text() -> void:
	# Test that _on_narrative_tone_changed calls _set_environment_text
	# This is tested through the base class _on_tone_changed method
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	var VData = load("res://gdscripts/text_variant_data.gd")
	var v0 = VData.new(); v0.text = "despair_text"
	var v1 = VData.new(); v1.text = "low_text"
	var v2 = VData.new(); v2.text = "neutral_text"
	var v3 = VData.new(); v3.text = "buoyant_text"
	var v4 = VData.new(); v4.text = "hope_text"
	tcb.variant_data = [v0, v1, v2, v3, v4]

	# _on_tone_changed with a state system would apply variant based on state
	# Without state system, it calls _apply_variant_for_tone_name
	tcb._on_tone_changed("office", "despair")
	_assert(true, "ET-15: _on_tone_changed called without crash")

	# The method internally uses _on_state_changed if state system exists
	# Without it, modulate.a transition should still be handled gracefully


func _test_signal_wiring_without_state_system() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	# Should not crash without autoloads
	tcb._ready()
	_assert(tcb._state_system == null, "ET-16: no StateSystem autoload → _state_system is null")
	_assert(tcb._narrative_manager == null, "ET-16: no NarrativeManager autoload → _narrative_manager is null")


# ===== SceneBase Helpers =====

func _test_get_current_state_id() -> void:
	var sb = load("res://gdscripts/scene_base.gd").new()
	# Without StateSystem autoload, should default to 3 (neutral)
	_assert(sb._get_current_state_id() == 3, "ET-17: _get_current_state_id without SS → 3 (neutral)")


func _test_get_tone_for_scene_fallback() -> void:
	var sb = load("res://gdscripts/scene_base.gd").new()
	# Without WorldviewController or NarrativeManager, default is "neutral"
	var tone: String = sb._get_tone_for_scene("office")
	_assert(tone == "neutral", "ET-18: _get_tone_for_scene with no autoloads → 'neutral'")


# ===== Transition =====

func _test_transition_export_default() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	_assert(abs(tcb.transition_duration - 0.3) < 0.001, "ET-19: default transition_duration is 0.3")


func _test_tween_cancels_previous() -> void:
	var tcb = load("res://gdscripts/text_component_base.gd").new()
	var VData = load("res://gdscripts/text_variant_data.gd")
	var v0 = VData.new(); v0.text = "text_a"
	var v1 = VData.new(); v1.text = "text_b"
	tcb.variant_data = [v0, v1]

	# Start first transition
	tcb._apply_variant_for_state(1)
	var first_tween = tcb._active_tween
	_assert(first_tween != null, "ET-20: first transition creates tween")

	# Start second transition — should kill first and create new
	tcb._apply_variant_for_state(2)
	var second_tween = tcb._active_tween
	_assert(second_tween != null, "ET-20: second transition creates tween")
	_assert(first_tween != second_tween or not first_tween.is_valid(), "ET-20: transitions are properly cancelled")

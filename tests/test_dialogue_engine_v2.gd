extends RefCounted

# ===== Dialogue Engine Tests — Runtime + Visual (Issue #52) =====
# Covers: HemingwayEnforcer truncation
# Note: DialogueDisplay3D tests require a scene tree and Label3D nodes,
# so they can only run in Godot editor, not --script mode.

var passed: int = 0
var failed: int = 0

var _HemingwayEnforcerScript = load("res://gdscripts/hemingway_enforcer.gd")

func run() -> void:
	print("\n=== Dialogue Engine v2 Tests (Issue #52) ===")
	
	# --- HemingwayEnforcer Tests ---
	_test_he_display_text()
	_test_he_many_sentences()
	_test_he_long_sentence()
	_test_he_empty_text()
	_test_he_null_text()
	
	# --- DialogueRunner extension Tests (in existing test_dialogue_engine.gd) ---
	# get_last_reachable_count() test is added to the main dialogue test file
	# since it's part of the DialogueRunner test suite
	
	print("  Dialogue Engine v2 Tests: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ %s" % name)
	else:
		failed += 1
		print("  ❌ %s" % name)

# =====================================================================
# HemingwayEnforcer Tests
# =====================================================================

func _test_he_display_text() -> void:
	# T1: Display text from dialogue node — basic truncation preserves short text
	var result: Dictionary = _HemingwayEnforcerScript.truncate("You again.")
	_assert(result["truncated_text"] == "You again.", "HE-1: Short text preserved")
	_assert(not result["was_truncated"], "HE-1: was_truncated=false for short text")
	_assert(result["original_text"] == "You again.", "HE-1: original_text preserved")
	_assert(result["original_sentence_count"] == 1, "HE-1: sentence count = 1")
	_assert(result["original_max_sentence_length"] == 9, "HE-1: max sentence length = 9")

func _test_he_many_sentences() -> void:
	# T4: >3 sentences truncated
	var input := "First. Second. Third. Fourth."
	var result: Dictionary = _HemingwayEnforcerScript.truncate(input)
	_assert(result["truncated_text"] == "First. Second. Third.…", "HE-4: >3 sentences truncated")
	_assert(result["was_truncated"], "HE-4: was_truncated=true")
	_assert(result["original_sentence_count"] == 4, "HE-4: original sentence count = 4")

func _test_he_long_sentence() -> void:
	# T5: Sentence >25 chars truncated at word boundary
	var input := "This is a very long sentence that exceeds the twenty-five character limit."
	var result: Dictionary = _HemingwayEnforcerScript.truncate(input)
	_assert(result["truncated_text"].length() <= 28, "HE-5: truncated ≤ 28 chars (25 + \"…\")")
	_assert(result["was_truncated"], "HE-5: was_truncated=true")
	_assert(result["original_sentence_count"] == 1, "HE-5: sentence count = 1")

func _test_he_empty_text() -> void:
	# T6: Empty text
	var result: Dictionary = _HemingwayEnforcerScript.truncate("")
	_assert(result["truncated_text"] == "", "HE-6: empty text preserved")
	_assert(not result["was_truncated"], "HE-6: was_truncated=false")
	_assert(result["original_sentence_count"] == 0, "HE-6: sentence count = 0")

func _test_he_null_text() -> void:
	# T11: null/non-string input
	var result: Dictionary = _HemingwayEnforcerScript.truncate(null)
	_assert(result["truncated_text"] == "", "HE-11: null returns empty text safely")
	_assert(not result["was_truncated"], "HE-11: was_truncated=false for null")

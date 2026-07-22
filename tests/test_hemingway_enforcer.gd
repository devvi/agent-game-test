extends RefCounted

# Hemingway Enforcer Test Suite (Issue #51)
# Covers: domain-aware limits, CJK delimiters, edge cases, failure paths

var passed: int = 0
var failed: int = 0
var _Enforcer = load("res://gdscripts/hemingway_enforcer.gd")

func run() -> void:
	print("\n=== Hemingway Enforcer Tests (Issue #51) ===")

	# Normal Path Tests
	_test_t1_english_dialogue_short()
	_test_t2_english_narration_3_sentences()
	_test_t3_narration_with_newlines()
	_test_t4_cjk_dialogue_short()
	_test_t5_cjk_narration_two_sentences()
	_test_t6_choice_text_short()
	_test_t7_signage_short()
	_test_t8_echo_variant()

	# Boundary / Edge Case Tests
	_test_t9_over_3_sentences_narration()
	_test_t10_over_1_sentence_dialogue()
	_test_t11_sentence_over_25_chars()
	_test_t12_both_violations()
	_test_t13_cjk_over_25_chars()
	_test_t14_single_word_over_25_chars()
	_test_t15_empty_string()
	_test_t16_ellipsis_only_text()
	_test_t17_newlines_at_boundaries()
	_test_t18_consecutive_punctuation()
	_test_t19_cjk_ellipsis_not_delimiter()

	# Failure Path Tests
	_test_t20_null_input()
	_test_t21_integer_input()
	_test_t22_invalid_domain()

	# Regression tests (existing behavior preserved)
	_test_r1_basic_truncation()
	_test_r2_empty_text()
	_test_r3_non_string_types()

	print("  Hemingway Enforcer Tests: %d passed, %d failed" % [passed, failed])

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  %s %s" % ["✅", name])
	else:
		failed += 1
		print("  %s %s" % ["❌", name])

# ===== Normal Path Tests =====

func _test_t1_english_dialogue_short() -> void:
	var result = _Enforcer.truncate("Same as usual.", "dialogue")
	_assert(not result["was_truncated"], "T1: English dialogue short - not truncated")
	_assert(result["truncated_text"] == "Same as usual.", "T1: text preserved")
	_assert(result["domain_used"] == "dialogue", "T1: domain_used = dialogue")

func _test_t2_english_narration_3_sentences() -> void:
	var result = _Enforcer.truncate("The station is empty. The clock reads 11:47 PM. A train hums below.", "narration")
	_assert(not result["was_truncated"], "T2: 3 sentences narration - not truncated")
	_assert(result["original_sentence_count"] == 3, "T2: 3 sentences detected")

func _test_t3_narration_with_newlines() -> void:
	var result = _Enforcer.truncate("The rain falls.\nIt never stops.\nYou watch.", "narration")
	_assert(not result["was_truncated"], "T3: narration with newlines - not truncated")
	_assert(result["original_sentence_count"] == 3, "T3: 3 sentences across newlines")

func _test_t4_cjk_dialogue_short() -> void:
	var result = _Enforcer.truncate("又一个加班的？", "dialogue")
	_assert(not result["was_truncated"], "T4: CJK dialogue short - not truncated")
	_assert(result["truncated_text"] == "又一个加班的？", "T4: CJK text preserved")

func _test_t5_cjk_narration_two_sentences() -> void:
	var result = _Enforcer.truncate("这条路我走过很多次。今晚不太一样。", "narration")
	_assert(not result["was_truncated"], "T5: CJK 2 sentences - not truncated")
	_assert(result["original_sentence_count"] == 2, "T5: 2 CJK sentences")

func _test_t6_choice_text_short() -> void:
	var result = _Enforcer.truncate("Look back at the city.", "choice_text")
	_assert(not result["was_truncated"], "T6: choice text short - not truncated")
	_assert(result["truncated_text"] == "Look back at the city.", "T6: text preserved")
	_assert(result["domain_used"] == "choice_text", "T6: domain_used = choice_text")

func _test_t7_signage_short() -> void:
	var result = _Enforcer.truncate("Open 24 Hours", "signage")
	_assert(not result["was_truncated"], "T7: signage short - not truncated")
	_assert(result["domain_used"] == "signage", "T7: domain_used = signage")

func _test_t8_echo_variant() -> void:
	var result = _Enforcer.truncate("下雨的声音……", "echo_variant")
	_assert(not result["was_truncated"], "T8: echo variant - not truncated")
	_assert(result["domain_used"] == "echo_variant", "T8: domain_used = echo_variant")

# ===== Boundary / Edge Case Tests =====

func _test_t9_over_3_sentences_narration() -> void:
	var result = _Enforcer.truncate("First. Second. Third. Fourth.", "narration")
	_assert(result["was_truncated"], "T9: >3 sentences truncated")
	_assert(result["truncated_text"] == "First. Second. Third…", "T9: first 3 kept")

func _test_t10_over_1_sentence_dialogue() -> void:
	var result = _Enforcer.truncate("Hello. World.", "dialogue")
	_assert(result["was_truncated"], "T10: >1 sentence dialogue truncated")
	_assert(result["truncated_text"] == "Hello…", "T10: first sentence kept + ellipsis")

func _test_t11_sentence_over_25_chars() -> void:
	var result = _Enforcer.truncate("This is a very long sentence that exceeds the limit.", "narration")
	_assert(result["was_truncated"], "T11: long sentence truncated")
	_assert(result["truncated_text"].length() <= 28, "T11: truncated ≤ 28 chars")

func _test_t12_both_violations() -> void:
	var result = _Enforcer.truncate("First long sentence that goes on and on. Second. Third. Fourth long one too.", "narration")
	_assert(result["was_truncated"], "T12: both violations truncated")
	_assert(result["truncated_sentence_count"] <= 3, "T12: ≤ 3 sentences after truncation")

func _test_t13_cjk_over_25_chars() -> void:
	var result = _Enforcer.truncate("这是一个非常长的中文句子完全超过了二十五个字符的限制。", "narration")
	_assert(result["was_truncated"], "T13: CJK long sentence truncated")
	_assert(result["truncated_text"].length() <= 28, "T13: truncated ≤ 28 chars")
	_assert(result["truncated_text"].ends_with("…"), "T13: ends with ellipsis")

func _test_t14_single_word_over_25_chars() -> void:
	var result = _Enforcer.truncate("Supercalifragilisticexpialidocious", "narration")
	_assert(result["was_truncated"], "T14: long word truncated")
	_assert(result["truncated_text"].length() <= 28, "T14: truncated ≤ 28 chars")

func _test_t15_empty_string() -> void:
	var result = _Enforcer.truncate("", "narration")
	_assert(not result["was_truncated"], "T15: empty not truncated")
	_assert(result["truncated_text"] == "", "T15: empty text preserved")

func _test_t16_ellipsis_only_text() -> void:
	var result = _Enforcer.truncate("……好。那就走吧。", "narration")
	_assert(result["original_sentence_count"] == 2, "T16: 2 sentences with ellipsis")

func _test_t17_newlines_at_boundaries() -> void:
	var result = _Enforcer.truncate("\nThe clock ticks.\n", "narration")
	_assert(not result["was_truncated"], "T17: newline boundaries - not truncated")
	_assert(result["truncated_text"] == "The clock ticks.", "T17: newlines stripped, text clean")

func _test_t18_consecutive_punctuation() -> void:
	var result = _Enforcer.truncate("Hello... World?", "narration")
	_assert(result["original_sentence_count"] == 2, "T18: 2 sentences, ... not delimiter")

func _test_t19_cjk_ellipsis_not_delimiter() -> void:
	var result = _Enforcer.truncate("……", "narration")
	_assert(result["original_sentence_count"] == 1, "T19: CJK ellipsis is 1 sentence")
	_assert(not result["was_truncated"], "T19: CJK ellipsis not truncated")

# ===== Failure Path Tests =====

func _test_t20_null_input() -> void:
	var result = _Enforcer.truncate(null, "narration")
	_assert(not result["was_truncated"], "T20: null not truncated")
	_assert(result["truncated_text"] == "", "T20: null returns empty")

func _test_t21_integer_input() -> void:
	var result = _Enforcer.truncate(42, "narration")
	_assert(not result["was_truncated"], "T21: int not truncated")
	_assert(result["truncated_text"] == "", "T21: int returns empty")

func _test_t22_invalid_domain() -> void:
	var result = _Enforcer.truncate("Hello.", "invalid_domain")
	_assert(result["domain_used"] == "invalid_domain" or result["domain_used"] == "narration", "T22: handles invalid domain gracefully")
	_assert(not result["was_truncated"], "T22: text not truncated with fallback")

# ===== Regression Tests =====

func _test_r1_basic_truncation() -> void:
	var result = _Enforcer.truncate("You again.")
	_assert(result["truncated_text"] == "You again.", "R1: short text preserved (default domain)")
	_assert(not result["was_truncated"], "R1: not truncated")
	var result2 = _Enforcer.truncate("First. Second. Third. Fourth.")
	_assert(result2["was_truncated"], "R1: >3 sentences with default domain truncated")

func _test_r2_empty_text() -> void:
	var result = _Enforcer.truncate("")
	_assert(result["truncated_text"] == "", "R2: empty text preserved")
	_assert(not result["was_truncated"], "R2: not truncated")

func _test_r3_non_string_types() -> void:
	var result = _Enforcer.truncate(null)
	_assert(not result["was_truncated"], "R3: null safe")
	result = _Enforcer.truncate(42)
	_assert(not result["was_truncated"], "R3: int safe")
	result = _Enforcer.truncate([])
	_assert(not result["was_truncated"], "R3: array safe")

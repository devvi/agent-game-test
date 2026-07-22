#!/usr/bin/env python3
"""Test parity between Python validator and GDScript HemingwayEnforcer.

Run: python -m pytest tests/test_validator_parity.py -v
Or:  python tests/test_validator_parity.py
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from scripts.validate_hemingway import (
    split_sentences,
    truncate_sentence,
    validate_text,
    RULES,
    _apply_truncation,
    has_cjk,
)


def test_split_sentences_english():
    cases = [
        ("Hello world.", ["Hello world."]),
        ("First. Second. Third.", ["First.", "Second.", "Third."]),
        ("Hello... World?", ["Hello...", "World?"]),
        ("One sentence", ["One sentence"]),
        ("", []),
        ("  ", []),
        ("Line 1.\nLine 2.\nLine 3.", ["Line 1.", "Line 2.", "Line 3."]),
        ("Hello. World.", ["Hello.", "World."]),
        ("A! B? C.", ["A!", "B?", "C."]),
        ("Trailing...", ["Trailing..."]),
    ]
    for text, expected in cases:
        result = split_sentences(text)
        assert result == expected, (
            f"FAIL: split_sentences({text!r}) = {result!r}, expected {expected!r}"
        )
    print(f"  P1: {len(cases)} English split cases pass")


def test_split_sentences_cjk():
    cases = [
        ("又一个加班的？", ["又一个加班的？"]),
        ("这条路我走过很多次。今晚不太一样。", ["这条路我走过很多次。", "今晚不太一样。"]),
        ("……好。那就走吧。", ["……好。", "那就走吧。"]),
        ("你好！再见？", ["你好！", "再见？"]),
        ("雨这么大，你不会想走太远的。", ["雨这么大，你不会想走太远的。"]),
        ("", []),
        ("……", ["……"]),
        ("第一句。第二句！第三句？", ["第一句。", "第二句！", "第三句？"]),
    ]
    for text, expected in cases:
        result = split_sentences(text)
        assert result == expected, (
            f"FAIL: split_sentences({text!r}) = {result!r}, expected {expected!r}"
        )
    print(f"  P2: {len(cases)} CJK split cases pass")


def test_truncate_sentence():
    assert truncate_sentence("Hello.", 25) == "Hello."
    result = truncate_sentence("This is a very long sentence that exceeds the limit.", 25)
    assert len(result) <= 28, f"Result too long: {result} ({len(result)} chars)"
    assert result.endswith("…"), f"Should end with ellipsis: {result}"
    result = truncate_sentence("这是一个非常长的中文句子完全超过了二十五个字符的限制。", 25)
    assert len(result) <= 28, f"Result too long: {result} ({len(result)} chars)"
    assert result.endswith("…"), f"Should end with ellipsis: {result}"
    result = truncate_sentence("Supercalifragilisticexpialidocious", 25)
    assert len(result) <= 28, f"Result too long: {result}"
    assert result.endswith("…"), f"Should end with ellipsis: {result}"
    print("  Truncate sentence: all cases pass")


def test_domain_limits():
    assert RULES["narration"]["max_sentences"] == 3
    assert RULES["narration"]["max_chars"] == 25
    assert RULES["dialogue"]["max_sentences"] == 1
    assert RULES["dialogue"]["max_chars"] == 25
    assert RULES["signage"]["max_sentences"] == 1
    assert RULES["signage"]["max_chars"] == 15
    assert RULES["choice_text"]["max_sentences"] == 1
    assert RULES["choice_text"]["max_chars"] == 30
    assert RULES["echo_variant"]["max_sentences"] == 1
    assert RULES["echo_variant"]["max_chars"] == 25
    print("  P3: Domain limits match GDScript constants")


def test_validate_clean_text():
    result = validate_text("Same as usual.", "dialogue")
    assert result == {}, f"Clean text should not produce violations: {result}"
    result = validate_text(
        "The station is empty. The clock reads 11:47 PM. A train hums below.",
        "narration",
    )
    assert result == {}, f"Clean narration should not produce violations: {result}"
    result = validate_text("又一个加班的？", "dialogue")
    assert result == {}, f"Clean CJK should not produce violations: {result}"
    print("  Clean text validation: all pass")


def test_validate_violations():
    result = validate_text("Hello. World.", "dialogue")
    assert result != {}, "Should detect violation"
    assert any(v["type"] == "sentence_count" for v in result["violations"])
    result = validate_text(
        "This is a very long sentence that exceeds the limit entirely.", "narration",
    )
    assert result != {}, "Should detect char violation"
    assert any(v["type"] == "char_count" for v in result["violations"])
    result = validate_text("A. B. C. D. E.", "narration")
    assert result != {}, "Should detect sentence count violation"
    assert any(v["type"] == "sentence_count" for v in result["violations"])
    print("  Violation detection: all pass")


def test_apply_truncation():
    result = _apply_truncation("First. Second. Third. Fourth.", "narration")
    assert result == "First. Second. Third…", f"Unexpected: {result}"
    result = _apply_truncation("Hello. World.", "dialogue")
    assert result == "Hello…", f"Unexpected: {result}"
    result = _apply_truncation(
        "This is a very long sentence that exceeds the limit.", "narration",
    )
    assert len(result) <= 28, f"Result too long: {result}"
    assert result.endswith("…"), f"Should end with ellipsis: {result}"
    print("  Truncation application: all pass")


def test_has_cjk():
    assert has_cjk("又一个加班的？")
    assert has_cjk("你好世界")
    assert not has_cjk("Hello world.")
    assert not has_cjk("")
    assert not has_cjk("12345")
    print("  CJK detection: all pass")


def test_empty_and_edge():
    result = validate_text("", "narration")
    assert result == {}, f"Empty text should not violate: {result}"
    result = validate_text("   ", "narration")
    result = validate_text("…", "narration")
    assert result == {}, f"Ellipsis should not violate: {result}"
    print("  Edge cases: all pass")


if __name__ == "__main__":
    test_split_sentences_english()
    test_split_sentences_cjk()
    test_truncate_sentence()
    test_domain_limits()
    test_validate_clean_text()
    test_validate_violations()
    test_apply_truncation()
    test_has_cjk()
    test_empty_and_edge()
    print("\nAll parity tests passed!")

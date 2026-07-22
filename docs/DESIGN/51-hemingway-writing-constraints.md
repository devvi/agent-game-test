# DESIGN: #51 — Hemingway Writing Constraints

> Parent Issue: #51
> Agent: plan-agent
> Date: 2026-07-23
> Depth: standard

---

## 1. Architecture Overview

### Core Idea

A two-layer enforcement system for Hemingway-style writing constraints (short sentences, poetic economy). **Runtime layer** extends the existing `HemingwayEnforcer.gd` with domain-aware limits and CJK sentence delimiters. **Authoring layer** adds a Python CLI validator (`scripts/validate_hemingway.py`) that catches violations before they reach the repo. Together they cover the full pipeline: write → validate (pre-commit/CI) → load → display (runtime truncation).

This implements **Approach A** from the PRD (Extended Enforcer + Python Validator), recommended for its full pipeline coverage, domain-aware limits, CJK support, and lightweight CI integration.

### Data Flow

```
Authoring Pipeline (Pre-Commit / CI)
=====================================
Dialogue JSON / GDScript file
    │
    ▼
scripts/validate_hemingway.py  ←── CI (on push) or pre-commit hook
    │
    ├──► scripts/validate_text.py (shared text extraction)
    │
    ├──► Reports violations: file, line, column, sentence index, char count
    ├──► Exit code: 0 = clean, 1 = violations found
    ├──► --fix: auto-truncate violations in-place (append "…")
    ├──► --report: generate markdown report at specified path
    └──► Output suppression per domain (--domain flag for non-dialogue files)


Runtime Pipeline (In-Game)
==========================
Text source (dialogue JSON / scene script / LoFiText3D assignment)
    │
    ▼
HemingwayEnforcer.truncate(text, domain="narration")
    │
    ├──► domain parameter → selects limits from DOMAIN_LIMITS table
    ├──► _split_sentences() — recognizes English (.!?) + CJK (。！？) delimiters
    ├──► Sentence limit applies first (>N sentences → keep first N, append "…")
    ├──► Char limit applies per sentence (>M chars → word-boundary trim + "…")
    ├──► CJK: character-level truncation at limit (no word boundaries in CJK)
    ├──► debug_mode: push_warning() with full violation detail
    │
    └──► Returns {truncated_text, original_text, was_truncated,
                    original_sentence_count, original_max_sentence_length,
                    domain_used}

Display Controller (DialogueDisplay3D / scene script)
    │
    ├──► Assigns result.truncated_text → label.text
    ├──► If was_truncated AND godot debug overlay: shows warning
    ├──► Stores original text in label metadata for debug inspection
    └──► Subtle color shift on truncated text (configurable)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Enforcement architecture | Two-layer (runtime + authoring) | Runtime handles display; authoring prevents violations from entering repo. Neither alone is sufficient |
| Domain approach | Single `truncate()` with `domain` param | Extends existing API cleanly. No new classes. Domain table is a single const dict |
| CJK sentence delimiters | Extend `_split_sentences()` with `。！？` | GDScript `String.length()` counts Unicode code points. Zero additional cost |
| Python for authoring validator | Standalone `scripts/validate_hemingway.py` | Lightweight (<10ms per file), no Godot dependency, runs in CI without headless Godot |
| Sentence-split duplication | Documented algorithm, cross-verified with tests | Both GDScript and Python implement same algorithm. Test suite ensures parity |
| `--fix` flag | In-place truncation with "…" suffix | Batch-fixes violations without manual edit. Reversible via git checkout |
| Narration `\n` handling | `\n` is display formatting, NOT sentence boundary | Matches actual text structure (Haiku 3-line blocks) |
| Signage 15-char limit | Pixel font readability constraint | 8×8 bitmap font at default 3D scale makes >15 glyphs illegible |
| Dialogue char limit | **25 chars** (strict Hemingway) | Majority of existing dialogue already compliant. `bartender.json`'s 33-char line is the exception and should be revised |
| Debug truncation indicator | `push_warning()` in editor + metadata storage | Non-intrusive. Can be extended to visual indicator later |

---

## 2. Runtime Layer Changes (GDScript Enforcer)

> Files: `gdscripts/hemingway_enforcer.gd`
> Nature: **Extension** of existing 98-line static utility

### Domain Limits Table

```gdscript
const DOMAIN_LIMITS := {
    "narration":    {"max_sentences": 3, "max_chars": 25},
    "dialogue":     {"max_sentences": 1, "max_chars": 25},
    "signage":      {"max_sentences": 1, "max_chars": 15},
    "choice_text":  {"max_sentences": 1, "max_chars": 30},
    "echo_variant": {"max_sentences": 1, "max_chars": 25},
}
```

### Modified API

```gdscript
# Current (no domain, no CJK):
static func truncate(text: Variant) -> Dictionary

# Proposed (domain-aware, CJK-aware):
static func truncate(text: Variant, domain: String = "narration") -> Dictionary
```

### Internal Changes

1. **`truncate()` signature** — add optional `domain` parameter, default `"narration"`. Returns new field `"domain_used"` in the result dictionary.

2. **`_split_sentences()`** — extend delimiter set:
   - Current: `".!?"`
   - Proposed: `".!?。！？"`
   - Chinese ellipsis `…` (U+2026) is NOT a sentence delimiter

3. **`_truncate_sentence()`** — add CJK-aware fallback:
   - If no word boundary found within limit and sentence contains CJK characters, truncate at character `max_chars` exactly (no word-boundary search)
   - CJK detection heuristic: check for Unicode range `\u4E00-\u9FFF` (CJK Unified Ideographs)

4. **Debug warning** — when `Engine.is_editor_hint()` or debug flag is set:
   ```gdscript
   if result["was_truncated"] and Engine.is_editor_hint():
       push_warning("[Hemingway] Truncated [%s]: \"%s\" → \"%s\" (%d→%d sentences, max %d→%d chars)" % [
           domain,
           result["original_text"],
           result["truncated_text"],
           result["original_sentence_count"],
           result.get("truncated_sentence_count", 0),
           result["original_max_sentence_length"],
           trunc...  # truncated max sentence length
       ])
   ```

5. **Return dict extension** — add `"domain_used"` and `"truncated_sentence_count"` fields.

### Constants Changes

Add to existing constants or to the enforcer file:
```gdscript
const CJK_SENTENCE_ENDS := "。！？"
const COMBINED_SENTENCE_ENDS := ".!?" + CJK_SENTENCE_ENDS
const CJK_UNICODE_RANGE_START := 0x4E00
const CJK_UNICODE_RANGE_END := 0x9FFF
```

### No Changes To

- `DialogueDisplay3D` — already calls `HemingwayEnforcer.truncate()` before setting text. Only needs `domain` argument plumbing
- `DialogueRunner` — no runtime changes
- `DialogueParser` — no schema changes
- `project.godot` — no input or autoload changes

---

## 3. Authoring Layer Changes (Python Validator)

> Files:
>   - `scripts/validate_hemingway.py` (NEW) — CLI entry point
>   - `scripts/validate_text.py` (NEW) — shared text extraction library
> Nature: **New** Python scripts, ~200 lines total

### Architecture

```
validate_hemingway.py (CLI)
    │
    ├── argparse: --report, --fix, --domain, positional file args
    ├── Iterates files: if none given, auto-discover dialogues/*.json + gdscripts/*.gd
    │
    ├── For each file:
    │   ├── validate_text.extract_texts(file_path) → list of (text, line, col, domain_hint)
    │   │   ├── .json: parse JSON, walk all "text" fields (dialogue + choice)
    │   │   └── .gd: regex for text = "..." and .text = "..." assignments
    │   │
    │   ├── For each extracted text:
    │   │   ├── validate against domain limits (same constants as enforcer)
    │   │   ├── sentence split logic (mirrors GDScript _split_sentences)
    │   │   └── collect violations: (file, line, col, sentence_idx, char_count, limit)
    │   │
    │   └── If --fix: apply truncation and rewrite file
    │
    ├── Print violations to stdout
    ├── Optional: --report generates markdown summary
    └── Exit code: 0 = all clean, 1 = violations found
```

### Sentence Split Algorithm (Must Mirror GDScript) (Python)

```python
SENTENCE_ENDS = {".", "!", "?"}
CJK_ENDS = {"。", "！", "？"}
ALL_ENDS = SENTENCE_ENDS | CJK_ENDS

def split_sentences(text: str) -> list[str]:
    """Must produce identical results to GDScript _split_sentences()."""
    sentences = []
    current = ""
    i = 0
    while i < len(text):
        current += text[i]
        ch = text[i]
        if ch in ALL_ENDS:
            # End-of-sentence check: next char is space, newline, tab, or EOS
            if i + 1 >= len(text) or text[i + 1] in (' ', '\n', '\t'):
                sentences.append(current.strip())
                current = ""
                # Skip trailing space
                if i + 1 < len(text) and text[i + 1] == ' ':
                    i += 1
        i += 1
    if current.strip():
        sentences.append(current.strip())
    return sentences
```

### CLI Interface

```bash
# Validate all dialogue + GDScript files
python scripts/validate_hemingway.py

# Validate specific file(s)
python scripts/validate_hemingway.py dialogues/bartender.json

# Generate markdown report
python scripts/validate_hemingway.py --report hemingway-review.md

# Auto-fix violations in-place
python scripts/validate_hemingway.py --fix

# Domain override (for non-dialogue files)
python scripts/validate_hemingway.py --domain narration gdscripts/subway_station.gd
```

### Pre-Commit Hook (Optional)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: hemingway-validate
        name: Hemingway Writing Constraint Validation
        entry: python scripts/validate_hemingway.py
        language: system
        files: 'dialogues/.*\.json|gdscripts/.*\.gd'
```

### CI Integration (Optional)

```yaml
# In .github/workflows/validate.yml or added to existing workflow step:
- name: Hemingway constraint check
  run: python scripts/validate_hemingway.py
```

---

## 4. Constraint Rules (Definitive Reference)

### Rule Definitions

| # | Rule | Detail |
|---|------|--------|
| R1 | **Sentence Limit** | Max 3 sentences per text segment (for narration). Dialogue/signage/choice_text max 1 |
| R2 | **Char Limit** | Max N characters per sentence (code points). Domain-specific: narration=25, dialogue=25, signage=15, choice_text=30, echo_variant=25 |
| R3 | **Sentence Delimiters** — English | `. ! ?` followed by space, newline, tab, or end-of-string |
| R4 | **Sentence Delimiters** — CJK | `。！？` — same rules. Ellipsis `…` (U+2026) is NOT a delimiter |
| R5 | **Paragraph = Text Segment** | A single dialogue `"text"` field, or a single GDScript string assignment |
| R6 | **Display Breaks** | `\n` is display formatting, NOT a sentence boundary. Only sentence-ending punctuation triggers splits |
| R7 | **Truncation Priority** | Sentence-limit applied first (keep first N, append "…"), then char-limit per sentence |
| R8 | **CJK Truncation** | No word-boundary search in CJK text. Truncate at exact char limit + "…" |
| R9 | **Ellipsis Preservation** | Existing `…` (U+2026) in source text is preserved. Truncation always appends `…` (U+2026) |

### Validation Examples

| Text | Domain | Sentences | Result |
|------|--------|-----------|--------|
| `"You again. Same as usual?"` | dialogue | 2 | ❌ — 2 sentences, dialogue limit=1 |
| `"You again. Same as usual?"` | narration | 2 | ✅ — ≤3 sentences, each ≤25 chars |
| `"The station is empty.\nThe clock reads 11:47 PM.\nA train hums below."` | narration | 3 | ✅ — \n is display break, 3 sentences |
| `"One glass of warm sake, coming up."` | dialogue | 1, 33 chars | ❌ — 33 > 25 char limit |
| `"Sake. One glass."` | dialogue | 2 | ❌ — 2 sentences, dialogue limit=1 |
| `"又一个加班的？"` | dialogue | 1, 6 chars | ✅ |
| `"……你说得对。不关我的事。"` | narration | 2, 8+5 chars | ✅ — … is not a delimiter, `。` is |

### Edge Case Handling

| Case | Behavior |
|------|----------|
| Empty string `""` | Returns empty, `was_truncated=false` |
| Whitespace-only `"   "` | Treated as 1 sentence. If ≤ limit, passes |
| Ellipsis-only `"…"` | 1 sentence. Not split on `…` |
| Consecutive delimiters `"Hello... World?"` | "Hello..." (1st), "World?" (2nd). Ellipsis dots not delimiters |
| Emoji `"🔥🔥🔥"` | 3 Unicode code points (1 per emoji). GDScript String.length() counts correctly |
| CJK no delimiters | Treated as 1 sentence. Truncated at char limit |
| Single word >25 chars | Truncate at char 25, append "…" |
| `\n` at start/end | Strip from edges in sentence split |
| Non-string input | TypeError — return empty result with `was_truncated=false` |

### Domain Rule Summary

| Domain | Max Sentences | Max Chars/Sentence | Rationale |
|--------|---------------|--------------------|-----------|
| `narration` | 3 | 25 | 3-line Haiku structure dominant; \n is display formatting |
| `dialogue` | 1 | 25 | Spoken NPC lines: one breath per utterance |
| `signage` | 1 | 15 | 8×8 pixel font at default scale illegible above ~15 glyphs |
| `choice_text` | 1 | 30 | "(A) " prefix (4 chars) + room for context-setting |
| `echo_variant` | 1 | 25 | Echo system text follows dialogue limits — single utterance |

---

## 5. Data Layer Changes

> No schema or save-data changes. All changes are code-level.

### Constants

```gdscript
# gdscripts/hemingway_enforcer.gd additions:
const DOMAIN_LIMITS := { ... }  # See §2
const CJK_SENTENCE_ENDS := "。！？"
const COMBINED_SENTENCE_ENDS := ".!?" + CJK_SENTENCE_ENDS
const CJK_UNICODE_RANGE_START := 0x4E00
const CJK_UNICODE_RANGE_END := 0x9FFF
```

### Existing Dialogue Audit

| File | Domain | Violations | Action |
|------|--------|------------|--------|
| `bartender.json` | dialogue | 1 — "One glass of warm sake, coming up." (33 chars) | Revise text or verify domain override |
| `lobby_stranger.json` | dialogue | None | No change |
| `lobby_guard.json` | dialogue | Not audited | Validate post-merge |
| `store_clerk.json` | dialogue | Not audited | Validate post-merge |
| `bridge_homeless.json` | dialogue | Not audited | Validate post-merge |
| `underpass_stranger_echo.json` | echo_variant | None | No change |
| `subway_ending.json` | narration | None | No change |
| `store_exit.json` | dialogue | Not audited | Validate post-merge |
| `office_door.json` | dialogue | Not audited | Validate post-merge |

### Dialogue JSON Per-Node Domain Override (Optional)

```json
{
  "id": "bartender_warm_sake",
  "speaker": "Bartender",
  "text": "One glass of warm sake, coming up.",
  "domain": "dialogue",
  "choices": [...]
}
```

The Python validator respects `"domain"` key if present in the JSON node. If absent, defaults based on context:
- Files in `dialogues/` — detected as dialogue domain via filename heuristics or explicit `--domain` flag
- Files in `gdscripts/` — default to narration unless annotated

---

## 6. Render / Visual Layer Changes

> Minimal — the enforcer returns pre-truncated text; the display layer already consumes it.

### Truncation Visual Indicator (Godot Editor Debug)

When `was_truncated` is true and `Engine.is_editor_hint()`:
- `push_warning()` with full violation metadata
- Stored in label metadata: `label.set_meta("hemingway_truncated", true)` and `label.set_meta("hemingway_original", original_text)`

### Future (Low Priority) — In-Game Debug Overlay

- F12 debug console: show warning count for truncated texts
- Toggle visual indicator: subtle emissive color shift on truncated `LoFiText3D` nodes

---

## 7. Test Layer Changes

> Tests describe WHAT each test validates — they are NOT runnable test files.

### Test Structure

| File | Type | Scope |
|------|------|-------|
| `tests/test_hemingway_enforcer.gd` (NEW) | GDScript (`--script`) | Full enforcer test suite: CJK, domain-aware, edge cases |
| `tests/test_validator_parity.py` (NEW) | Python unittest | Verify Python validator produces identical results to GDScript for canonical test strings |

### Normal Path Tests

| # | Test | Scenario | Input | Expected Behavior | Verification |
|---|------|----------|-------|-------------------|-------------|
| T1 | English dialogue — single sentence ≤25 chars | `truncate("Same as usual.", "dialogue")` | 1 sentence, 14 chars | No truncation. Returns same text | `was_truncated=false`, `truncated_text == "Same as usual."` |
| T2 | English narration — 3 sentences, all ≤25 chars | `truncate("The station is empty. The clock reads 11:47 PM. A train hums below.", "narration")` | 3 sentences, each ≤22 chars | No truncation. All 3 sentences preserved | `was_truncated=false`, `truncated_text contains all 3 sentences` |
| T3 | English narration — 2 sentences with `\n` display breaks | `truncate("The rain falls.\nIt never stops.\nYou watch.", "narration")` | 3 sentences across `\n` | Recognizes 3 sentence boundaries (`.`) despite `\n` | `original_sentence_count==3`, `was_truncated=false` |
| T4 | CJK dialogue — single sentence ≤25 chars | `truncate("又一个加班的？", "dialogue")` | 1 sentence, 6 CJK chars, ends with `？` | No truncation. `？` recognized as delimiter | `was_truncated=false`, `truncated_text == "又一个加班的？"` |
| T5 | CJK narration — 2 sentences with `。` delimiter | `truncate("这条路我走过很多次。今晚不太一样。", "narration")` | 2 sentences separated by `。` | Correctly splits on `。`. No truncation | `original_sentence_count==2`, `was_truncated=false` |
| T6 | Choice text — single sentence ≤30 chars with prefix room | `truncate("Look back at the city.", "choice_text")` | 24 chars, 1 sentence | No truncation. 30-char limit gives headroom | `was_truncated=false`, `truncated_text preserved` |
| T7 | Signage — ≤15 chars | `truncate("Open 24 Hours", "signage")` | 12 chars, 1 sentence | No truncation | `was_truncated=false` |
| T8 | Echo variant — ≤25 chars | `truncate("下雨的声音……", "echo_variant")` | 8 chars, 1 sentence with ellipsis | No truncation. `…` preserved | `was_truncated=false`, text unchanged |

### Boundary / Edge Case Tests (≥6)

| # | Test | Scenario | Input | Expected Behavior | Verification |
|---|------|----------|-------|-------------------|-------------|
| T9 | >3 sentences (narration) | `truncate("First. Second. Third. Fourth.", "narration")` | 4 sentences | Keep first 3. Replace last with "…" | `was_truncated=true`, `truncated_text == "First. Second. Third.…"` |
| T10 | >1 sentence (dialogue) | `truncate("Hello. World.", "dialogue")` | 2 sentences, dialogue limit=1 | Keep first sentence only, append "…" | `was_truncated=true`, `truncated_text == "Hello.…"` |
| T11 | Single sentence >25 chars (narration) | `truncate("This is a very long sentence that exceeds the limit.", "narration")` | 53 chars, 1 sentence | Truncate at word boundary within 25 chars, append "…" | `truncated_text.length() <= 28`, ends with "…" |
| T12 | Both violations: >3 sentences AND per-sentence >25 chars | `truncate("First long sentence that goes on and on. Second. Third. Fourth long one too.", "narration")` | 4 sentences, some >25 chars | Sentence-limit first (keep 3, replace 4th with "…"), then char-limit on each | `was_truncated=true`, first sentence truncated at word boundary, 3 total |
| T13 | CJK sentence >25 chars (no word boundaries) | `truncate("这是一个非常长的中文句子完全超过了二十五个字符的限制。", "narration")` | ~30 CJK characters, 1 sentence | Truncate at character 25, append "…". No word-boundary search | `was_truncated=true`, `truncated_text.length() <= 28`, ends with "…" |
| T14 | Single word >25 chars (rare) | `truncate("Supercalifragilisticexpialidocious", "narration")` | 34 chars, no spaces | Truncate at char 25, append "…". No word boundary found | `was_truncated=true`, `truncated_text == "Supercalifragilistic…"` |
| T15 | Empty string | `truncate("", "narration")` | Empty | Returns empty, no truncation | `was_truncated=false`, `truncated_text == ""` |
| T16 | Ellipsis-only text | `truncate("……好。那就走吧。", "narration")` | Ellipsis + 2 sentences | Ellipsis `…` NOT treated as delimiter. `。` splits correctly | `sentence_count==2`, `truncated_text preserved` |
| T17 | `\n` at text boundaries | `truncate("\nThe clock ticks.\n", "narration")` | Leading/trailing newlines | `strip_edges()` removes them. Valid text preserved | `was_truncated=false`, text clean |
| T18 | Consecutive sentence-ending punctuation | `truncate("Hello... World?", "narration")` | "Hello..." and " World?" | First `.` in `...` followed by `.` (not space), so no split. "Hello..." is 1 sentence. Then space → "World?" | 2 sentences, `truncated_text == "Hello... World?"` |
| T19 | CJK ellipsis NOT delimiter | `truncate("……", "narration")` | CJK ellipsis only | 1 sentence. `…` (U+2026) never triggers sentence boundary | `sentence_count==1`, `was_truncated=false` |

### Failure Path Tests (≥3)

| # | Test | Scenario | Input | Expected Behavior | Verification |
|---|------|----------|-------|-------------------|-------------|
| T20 | Non-string input (null) | `truncate(null, "narration")` | null | Returns empty result, no crash | `was_truncated=false`, `truncated_text == ""` |
| T21 | Non-string input (integer) | `truncate(42, "narration")` | int | Type check catches it. Returns empty | `was_truncated=false`, `truncated_text == ""` |
| T22 | Invalid domain string | `truncate("Hello.", "invalid_domain")` | Unknown domain | Falls back to "narration" limits. Warnings logged | `domain_used == "narration"`, text validated against narration limits |
| T23 | Unclosed string in GDScript (Python validator) | GDScript with `text = "unclosed` | Unclosed quote in source | Reports parse error, skips file, continues to next | Exit code 1, error message includes file path |
| T24 | Malformed JSON (Python validator) | JSON with trailing comma | Parse error | Reports syntax error, skips file, continues | Exit code 1, error includes line number |

### Regression Tests (Existing)

| # | Test | Scenario | Input | Expected Behavior |
|---|------|----------|-------|-------------------|
| R1 | Existing test_basic_truncation from `test_dialogue_engine_v2.gd` | 3 sentence + 4 sentence cases | Various | Must still pass after enforcer extension. Domain defaults to "narration" |
| R2 | Existing test_empty_text | Empty string | `""` | Must still return empty |
| R3 | Existing test_non_string_types | null, int, array | Various | Must still return empty safely |

### Python Validator Parity Tests

| # | Test | Scenario | What It Validates |
|---|------|----------|-------------------|
| P1 | Sentence-split parity | Canonical set of 10 English strings | Python `split_sentences()` produces identical output to GDScript `_split_sentences()` |
| P2 | CJK sentence-split parity | Canonical set of 10 Chinese strings | Same verification for CJK delimiters |
| P3 | Domain limit parity | All 5 domains × 3 test strings each | Python and GDScript produce identical `was_truncated` and `truncated_text` |
| P4 | `--fix` produces valid JSON | Fix `bartender.json` violation | After `--fix`, file is still valid JSON and text is truncated |
| P5 | Exit code on clean repo | All currently compliant files | Exit code 0 |
| P6 | Exit code on violation | File with known violations | Exit code 1 |

### Test Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Sentence splitting (English) | T1–T3 | T9, T10, T14, T18 | T20–T22 |
| Sentence splitting (CJK) | T4–T5 | T13, T16, T19 | T23–T24 |
| Char limit enforcement | T1, T7, T8 | T11, T12, T14 | T20–T22 |
| Domain-aware limits | T1–T8 (all domains) | T9–T19 (domain cross-checks) | T22 |
| Debug warning system | — | Push-warning fires on truncation | No false warnings on clean text |
| Truncation priority | — | T12 (sentence before char) | — |
| `\n` handling | T3 | T17 | — |
| CI/CLI integration | P1–P6 | — | Config error handling |
| Pre-commit hook | — | No-op on clean files | Fails on violation (correctly) |
| Python-GDScript parity | P1–P3 | P4, P5 | P6 |

---

## 8. Files Changed (per-layer summary)

### Runtime Layer (GDScript)

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/hemingway_enforcer.gd` | Extend `truncate()` with domain param; add CJK delimiters to `_split_sentences()`; add CJK-aware truncation in `_truncate_sentence()`; add debug warning; add DOMAIN_LIMITS const | ±40 |
| `gdscripts/dialogue_display_3d.gd` | Pass `domain` argument in `on_node_changed()` call to `truncate()`; plumb domain from dialogue node metadata | ±5 |

### Authoring Layer (Python)

| File | Change | Est. Lines |
|------|--------|-----------|
| `scripts/validate_hemingway.py` | NEW — CLI validator with --fix, --report, --domain flags | +120 |
| `scripts/validate_text.py` | NEW — shared text extraction from JSON + GDScript | +60 |
| `.pre-commit-config.yaml` | NEW — optional pre-commit hook definition | +10 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/test_hemingway_enforcer.gd` | NEW — dedicated test suite (normal, edge, failure, domain) | +150 |
| `tests/test_validator_parity.py` | NEW — Python unittest for GDScript parity | +80 |

### Documentation

| File | Change | Est. Lines |
|------|--------|-----------|
| `docs/DESIGN/51-hemingway-writing-constraints.md` | NEW — this document | +500 |
| `docs/TASKS/51-hemingway-writing-constraints.md` | NEW — tasks doc (next phase) | +80 |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | Update §1.3 with concrete constraint numbers | ±5 |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | Add constraint section | +20 |

**Total estimated: ~550 lines** (excluding docs)

---

## 9. Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Dialogue char limit | **25 chars (strict)** | Existing dialogue is almost entirely compliant. The single 33-char `bartender.json` line should be revised. Strict Hemingway, not pragmatic padding |
| Signage limit (15 chars) | Provisional — adjustable | May need increase after playtesting with 8×8 pixel font. Single-line config change |
| CJK sentence ends | `。！？` only | Excludes `…` (ellipsis), `——` (em dash), `、` (enumerative comma). These are not sentence-ending punctuation in Chinese |
| Domain detection for dialogue JSON files | Automatic via filename | Files under `dialogues/` default to `dialogue` domain; `gdscripts/` default to `narration`. Per-node `"domain"` key can override |
| Python-GDScript parity verification | Dedicated test suite (`test_validator_parity.py`) | Ensures two implementations stay in sync. Compare against canonical string set |
| `--fix` behavior | In-place modification with "…" suffix | Simplest. Writer can always `git checkout` to revert |
| Pre-commit hook | Optional, not default | CI check is sufficient. Pre-commit adds friction for first-time setup |
| CI step for Hemingway check | Add to existing workflow | No separate workflow needed. Single `run:` step in existing CI |
| Debug indicator color shift | Deferred | `push_warning()` in editor mode is sufficient. Visual indicator is low-priority nice-to-have |
| `DialogueDisplay3D` domain plumbing | From JSON node's `domain` field → `truncate()` call | Minimal change. Domain flows: JSON → parser → runner → display → enforcer |

---

## 10. Verification Checklist

- [ ] `HemingwayEnforcer.truncate(text, "narration")` handles 3-sentence limit correctly
- [ ] `HemingwayEnforcer.truncate(text, "narration")` handles 25-char per-sentence limit correctly
- [ ] Domain-aware limits: each of 5 domains (narration, dialogue, signage, choice_text, echo_variant) enforces correct max_sentences and max_chars
- [ ] CJK sentence delimiters `。！？` are correctly recognized as sentence boundaries
- [ ] CJK ellipsis `…` is NOT treated as a sentence delimiter
- [ ] CJK text without delimiters is treated as 1 sentence
- [ ] CJK truncation falls back to character-level truncation (no word-boundary search)
- [ ] Empty text returns empty with `was_truncated=false`
- [ ] Null/non-string input returns empty safely, no crash
- [ ] Invalid domain falls back to `"narration"`
- [ ] Sentence-limit applied BEFORE char-limit (truncation priority)
- [ ] `\n` is NOT treated as a sentence boundary in any domain
- [ ] Debug `push_warning()` fires when `was_truncated=true` and `Engine.is_editor_hint()`
- [ ] `scripts/validate_hemingway.py` exits with 0 on clean files
- [ ] `scripts/validate_hemingway.py` exits with 1 on violations
- [ ] `--fix` produces valid, truncated output
- [ ] `--report` generates markdown file at specified path
- [ ] Python `split_sentences()` matches GDScript `_split_sentences()` for all canonical test strings
- [ ] Existing `test_dialogue_engine_v2.gd` tests still pass (regression)
- [ ] `DialogueDisplay3D` passes domain parameter correctly when calling `truncate()`
- [ ] `bartender.json` 33-char line is either revised or domain-annotated
- [ ] All 9 dialogue JSON files pass Hemingway validation after any fixes
- [ ] No changes to `DialogueRunner`, `DialogueParser`, or `project.godot`

---

## 11. Open Questions for Implement Phase

1. **Dialogue domain limit (25 vs. 30):** The PRD flags `bartender.json: "One glass of warm sake, coming up."` as a 33-char violation. Decision: **revise the text** to fit 25 chars (e.g., `"Sake. One glass."`) rather than relaxing the limit. Implementer should confirm.

2. **Signage limit adjustment:** 15 chars is provisional. The implementer should verify with the actual 8×8 pixel font in-engine that 15 glyphs fit legibly in the target `LoFiText3D` node size. If text clips, raise to 18. Document the final value in the enforcer's DOMAIN_LIMITS.

3. **Per-node domain override in JSON:** Is `"domain"` a new top-level key in dialogue nodes, or derived from file context? Design assumes filename heuristics + optional per-node key. Implementer should confirm with existing dialogue parsing pipeline.

4. **Automatic file discovery for validator:** Should `validate_hemingway.py` (with no args) scan ALL `dialogues/*.json` and `gdscripts/*.gd`, or only files that differ from `main`? Design assumes full scan (simpler). Implementer can add `--changed-only` flag if performance is a concern.

5. **Python sentence-split test strings:** Where should the canonical test string set live? Design proposes inline in `test_validator_parity.py`. A shared JSON fixture file in `tests/fixtures/` would be cleaner.

6. **Should `--fix` truncate at word boundaries or hard-char boundaries in English?** Design: word boundary (same as GDScript enforcer). This is the correct behavior for English and mirrors runtime truncation.

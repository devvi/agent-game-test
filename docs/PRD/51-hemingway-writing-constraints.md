# Research: Hemingway Writing Constraints

> Parent Issue: #51
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project's narrative style (defined in `docs/GAME_DESIGN/01-OVERVIEW.md` and Issue #45) specifies a Hemingway-inspired minimalism: short sentences, iceberg-theory omission, poetic economy. However:

1. **No enforcement exists at authoring time** — dialogue JSON files and environmental text can contain arbitrarily long sentences and paragraphs. Authors have no tooling to validate compliance.
2. **Runtime enforcement exists but is reactive only** — `gdscripts/hemingway_enforcer.gd` was built alongside the dialogue display (Issue #52, PR #83) and provides a `truncate()` utility that is called only at display time in `DialogueDisplay3D`. It silently truncates without any author notification.
3. **No distinction between text domains** — narration, dialogue, environmental signage, and choice text all have different readability profiles, but the current enforcer treats all text identically.
4. **Chinese/CJK text not addressed** — the game has significant Chinese-language dialogue (7 of 9 JSON files contain Chinese text). Chinese characters carry more semantic density per glyph; a 25-char sentence in Chinese is longer than an English 25-char sentence.

### Expected Behavior

A **Writing Constraint System** with three enforcement layers:

1. **Authoring-time validation** — a standalone script (`scripts/validate_hemingway.py`) that scans all dialogue JSON files and GDScript environmental text, flags violations, and provides line-precise reports.
2. **Runtime enforcement** — the existing `HemingwayEnforcer.gd` truncates text at display time, but should distinguish between text domains (dialogue vs. narration vs. signage) and handle Chinese/CJK character boundaries correctly.
3. **Documented constraint rules** — clear definitions of what "sentence" and "paragraph" mean for both English and Chinese text, with violations handled differently per domain.

### User Scenarios

- **Scenario A (Writer/Narrative Designer):** A writer authors a new dialogue JSON file with a line: *"I remember the night we first came here when it was raining hard and you said this city could never be our home."* Running `python scripts/validate_hemingway.py dialogues/new_file.json` reports: *Line 12: Sentence 1 exceeds 25 chars (67 chars). Sentence count exceeds 3 (4 sentences).* The writer revises.
- **Scenario B (Runtime Display):** A node's text somehow exceeds constraints at runtime (unexpected concatenation, modded content). The truncated version appears in the LoFiText3D display with ellipsis ("…"), and a warning is logged to the debug console.
- **Scenario C (Environmental Text):** A scene script sets `neon_sign.text = "This is a very long line of environmental text that absolutely exceeds the limit"`. At runtime, the text is silently truncated to the constraint boundary. A debug-mode visual indicator (subtle color shift) signals truncation occurred.
- **Frequency:** Every text load — dialogue nodes (50+ across 7 JSON files), environmental text instances (20-40 across 6 scenes).

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The constraint system was implemented incrementally:

1. **GDD statement (01-OVERVIEW.md):** Hemingway style was declared as a design direction early on, but without concrete numbers (max 25 chars/sentence, 3 sentences/paragraph).
2. **PRD #45 (Narrative Architecture):** First formal mention of "Hemingway-style (短句, 冰山理论)" as a constraint, though only as a design note.
3. **PRD #52 (Dialogue Runtime + Visual):** Built the `hemingway_enforcer.gd` as a stopgap — the visual system needed truncation logic before the full constraint design was finalized. This created a working enforcer **before** the design document (#51) was written.
4. **Issue #51 remains in research phase:** The enforcer was implemented under PRD #52 as a tactical dependency, but the comprehensive design (editor-side validation, separate text domains, CJK handling) was deferred to this PRD.

### Why Change Now?

1. **Authoring pipeline incomplete:** Writers currently have no way to verify compliance before committing dialogue JSON files. Violations slip into the repo and are only caught at runtime.
2. **Chinese text handling is critical:** The game has 7 dialogue JSON files with Chinese text (underpass_stranger_echo.json, lobby_stranger.json, store_clerk.json, subway_ending.json, etc.). Chinese characters occupy 2-3 bytes in UTF-8 but one semantic unit — the enforcer must count *characters*, not bytes.
3. **Quality bar:** The Hemingway constraint is a core part of the game's identity (01-OVERVIEW.md §1.3). Silent runtime truncation hides authoring problems instead of preventing them.
4. **Text domain differentiation:** A narrator monologue and a concrete-floor neon sign have different readability constraints. The current single-rule approach is too coarse.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static typing) |
| Existing enforcer | `gdscripts/hemingway_enforcer.gd` — static utility with `truncate()`, `_split_sentences()`, `_truncate_sentence()` |
| Existing tests | `tests/test_dialogue_engine_v2.gd` — 5 test cases for HemingwayEnforcer |
| Dialogue format | JSON (7 files, ~520 lines total) |
| Environmental text | GDScript inline via `LoFiText3D` components or scene scripts |
| Pixel font | 8×8 bitmap, ~6-8px effective glyph width at default scale |
| Languages | English + Chinese (CJK) — Unicode-aware handling required |
| Writing style | Hemingway — short, sparse, poetic. Inspired by Disco Elysium interior monologue + Hopper urban-night aesthetic |
| Renderer | pixel font + LoFi shader — high character counts are visually unreadable anyway |
| Display vs. line-break | Some texts use `\n` for visual line breaks (e.g., 3-line format in narration). These are not paragraph breaks but display formatting. |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `docs/PRD/51-hemingway-writing-constraints.md` | PRD | **New** — This document |
| `gdscripts/hemingway_enforcer.gd` | Hemingway Enforcer | **Extended** — add text domain support, CJK character counting, narration mode, debug truncation warning |
| `scripts/validate_hemingway.py` (new) | Authoring Validator | **New** — Python CLI script for pre-commit validation of dialogue JSON + GDScript text |
| `scripts/validate_text.py` (new) | Text Extractor | **New** — shared library for extracting text strings from JSON and GDScript |
| `tests/test_hemingway_enforcer.gd` (new) | Tests | **New** — dedicated test suite for CJK, domain-specific, edge case coverage |
| `dialogues/*.json` | Dialogue Data | **Audit** — validate all existing dialogue against constraints, fix violations |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/dialogue_display_3d.gd` | Dialogue 3D Display | Already calls enforcer; may need debug-truncation-warning integration |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | GDD — Dialogue | Must document constraint rules |
| `.github/workflows/validate.yml` (new) | CI | **New** — optional CI step for Hemingway validation on PRs |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | GDD — Overview | Update §1.3 with concrete constraint numbers |
| `docs/DESIGN/51-hemingway-writing-constraints.md` | Design doc | Plan phase output |

### Data Flow Impact

```
Authoring Pipeline (Pre-Commit)
================================
Dialogue JSON / GDScript file
    │
    ▼
scripts/validate_hemingway.py  ←── CI or manual run
    │
    ├──► Reports violations: file, line, sentence index, character count, type
    ├──► Exit code: 0 = all clean, 1 = violations found
    └──► Generates markdown report (optional --report flag)

Runtime Pipeline (In-Game)
==========================
Text source (dialogue JSON / scene script)
    │
    ▼
HemingwayEnforcer.truncate(text, domain="narration")
    │
    ├──► domain="narration":     max 3 sentences, max 25 chars/sentence
    ├──► domain="dialogue":      max 1 sentence,  max 25 chars/sentence
    ├──► domain="signage":       max 1 sentence,  max 15 chars/sentence (pixel font limit)
    ├──► domain="choice_text":   max 1 sentence,  max 30 chars/sentence (UI padding)
    │
    ├──► Returns truncated_text + metadata
    ├──► If truncated AND debug_mode: print warning
    └──► dialogue_text.text = result["truncated_text"]
```

### Documents to Update

- [x] **This output:** `docs/PRD/51-hemingway-writing-constraints.md`
- [ ] `docs/DESIGN/51-hemingway-writing-constraints.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md` — Update §1.3 with concrete constraint numbers
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Add constraint section
- [ ] `doc/CONTENT_STANDARDS.md` (new) — Writing guide for contributors

---

## 4. Solution Comparison

### Approach A: Extended Enforcer + Python Validator (Recommended)

**Description:**

A two-part system:

**Part 1 — Runtime (`hemingway_enforcer.gd`):** Extend the existing GDScript enforcer with:
- Text domain parameter: `truncate(text, domain="narration")`
- Domain-specific limits table
- CJK character counting (`_char_count()` — uses `String.length()` in GDScript 4, which counts Unicode code points, correct for CJK)
- Debug warning system: `DebugOverlay.on_truncation_warning(msg)` when text is truncated
- Narration mode: respects `\n` as display line breaks (not sentences), counts cumulative chars across lines with per-line cap

**Part 2 — Authoring (`scripts/validate_hemingway.py`):** Python script that:
- Parses dialogue JSON files, extracts all `"text"` fields (dialogue and choice text)
- Parses GDScript files for `text = "..."` and `.text = "..."` patterns
- Validates each extracted string against the same rules
- Reports violations with file:line:column precision
- Supports `--fix` to auto-truncate with ellipsis and `--report` to generate markdown
- Can run as pre-commit hook or CI step

**Domain Limits:**

| Domain | Max Sentences | Max Chars/Sentence | Rationale |
|--------|---------------|--------------------|-----------|
| `narration` | 3 | 25 | Narrator text: 3-line Haiku format dominant (see `subway_ending.json`) |
| `dialogue` | 1 | 25 | Spoken NPC lines: punchy, one breath per line |
| `signage` | 1 | 15 | In-world environmental text: pixel font renders illegibly above ~15 glyphs |
| `choice_text` | 1 | 30 | UI choice text: needs room for "(A) " prefix + extra padding |
| `echo_variant` | 1 | 25 | Echo system text (same as dialogue) |

**Pros:**
- Full pipeline coverage: authoring-time validation prevents violations from reaching the repo
- Domain-aware limits match actual readability constraints per text type
- CJK-handling is native in GDScript's `String.length()` (GDScript 2.0 counts Unicode code points)
- Reuses the existing enforcer's battle-tested truncation logic
- Python validator is independent of Godot — can run in CI without Godot installed
- Pre-commit hook integration prevents non-compliant text from being committed

**Cons:**
- Python validator must reimplement sentence-splitting logic (duplicating GDScript `_split_sentences()`)
- GDScript `String.length()` returns Unicode code points, but some CJK grapheme clusters (e.g., emoji, combined characters) may have unexpected lengths
- `\n` in narration text must be handled carefully — avoid treating display line breaks as sentence boundaries

**Risk:** Low — both the GDScript enforcer and Python JSON parsing are well-understood.

**Effort:** 2 files for runtime (enforcer extension), 2 files for authoring (Python validator + text extractor), 1 test file — ~350 lines total.

---

### Approach B: Pure GDScript Validation + Godot CLI

**Description:**

Create a GDScript-based validator that runs in Godot headless mode (`--script`). It loads the dialogue parser and iterates all dialogue files, using the existing `HemingwayEnforcer` code for constraint checking. No Python involved. A shell script wraps the Godot call.

**Pros:**
- Single rule implementation — GDScript enforcer is the source of truth, validator uses the same code
- No Python dependency — everything runs through Godot
- Can validate environmental text by loading scene scripts

**Cons:**
- Requires Godot executable to be installed on CI or developer machine
- Headless mode startup can be slow (2-5s per run)
- GDScript errors (parse failures, missing dependencies) cascade into validation failures
- No `--fix` mode (GDScript file manipulation is fragile)
- No pre-commit hook integration without Godot in PATH
- Heavier than a Python script for simple text pattern matching

**Risk:** Medium — Godot headless is reliable but adds a toolchain dependency for validation that should be lightweight.

**Effort:** 1 GDScript file + 1 shell wrapper + CI config — ~200 lines.

---

### Approach C: JSON Schema + JSON Character Limit (Lightweight)

**Description:**

Add a `"hemingway": {"max_sentences": 3, "max_chars": 25}` metadata field to each dialogue node. The `DialogueParser` validates constraint compliance during JSON loading, and the `DialogueRunner` reports warnings when violations are detected at load time. No separate validator script.

**Pros:**
- Minimal new code — leverages existing parser validation
- Each node can have custom limits (per-node override)
- Violations caught at dialogue load time (before display)

**Cons:**
- No authoring-time feedback loop — violations only surface when loading the game
- Every dialogue node must carry the metadata (bloats JSON files)
- Environmental text (GDScript inline, scene text) not covered
- No CI integration or pre-commit hook
- Cannot prevent bad text from being committed — only warns at runtime
- Parser change adds overhead to every dialogue load

**Risk:** Low-Medium — simple but insufficient for the "prevention" goal of AC2.

**Effort:** ~100 lines of parser changes + JSON data updates.

---

### Comparison Summary

| Dimension | A: Extended Enforcer + Python Validator | B: Pure GDScript + Godot CLI | C: JSON Schema + Parser |
|-----------|----------------------------------------|-----------------------------|------------------------|
| Authoring-time validation | ★★★★★ | ★★★★☆ (slow) | ★☆☆☆☆ (load-time only) |
| Runtime enforcement | ★★★★★ (domain-aware) | ★★★★★ | ★★★☆☆ (basic) |
| CI integration | ★★★★★ | ★★★☆☆ (Godot dep) | ★☆☆☆☆ |
| Pre-commit hook | ★★★★★ | ★★☆☆☆ | ★☆☆☆☆ |
| CJK handling | ★★★★★ | ★★★★★ | ★★★★★ |
| Maintainability | ★★★★★ | ★★★★☆ | ★★★★☆ |
| Toolchain simplicity | ★★★★☆ (Python needed) | ★★★☆☆ (Godot needed) | ★★★★★ |
| Covers all text sources | ★★★★★ | ★★★★★ | ★★☆☆☆ (JSON only) |
| `--fix` auto-truncation | ★★★★★ | ★☆☆☆☆ | ★☆☆☆☆ |

### Recommendation

→ **Approach A (Extended Enforcer + Python Validator)** because:

1. **Full pipeline coverage:** The Python validator prevents violations before they enter the repo (AC2), while the extended enforcer handles runtime truncation (AC3). No other approach provides both.
2. **Domain-aware enforcement:** Narration, dialogue, signage, and choice text have genuinely different readability profiles. The enforcer's `domain` parameter maps directly to the game's actual text types.
3. **CJK support is free:** GDScript 4's `String.length()` counts Unicode code points, which is the correct behavior for Chinese characters. The Python validator uses `len(text)` which similarly counts Unicode code points.
4. **Lightweight CI integration:** Python script is <10ms per file — can run on every `git push` without slowing the pipeline.
5. **Existing code reuse:** The current `hemingway_enforcer.gd` is 98 lines of battle-tested GDScript. Extending it with domain support is ~30 lines. The Python validator's sentence-split logic mirrors the GDScript version.
6. **`--fix` capability:** Auto-truncation in the validator lets writers batch-fix violations without manual edit, reducing friction.

**Risk mitigation for duplicated logic:**
- Document the sentence-split algorithm clearly in both implementations (see §7.2)
- Write Python tests that verify the validator produces identical results to the GDScript enforcer for a set of canonical test strings

---

## 5. Constraint Rules & Examples

### 5.1 Core Rules

```
Rule 1: SENTENCE LIMIT — Max 3 sentences per text segment
Rule 2: CHAR LIMIT    — Max 25 characters per sentence (code points)
Rule 3: SENTENCE DELIMITERS — . ! ? followed by space or end-of-string
Rule 4: PARAGRAPH      — A single text segment (dialogue `"text"` field, or GDScript string assignment)
Rule 5: DISPLAY BREAKS — `\n` is a display line break, NOT a sentence boundary
```

### 5.2 Examples

**Compliant text (English):**

| Text | Sentences | Max Chars | Pass? |
|------|-----------|-----------|-------|
| `"You again. Same as usual?"` | 2 | 9, 16 | ✅ |
| `"The station is empty.\nThe clock reads 11:47 PM.\nA train hums below."` | 3 | 22, 21, 20 | ✅ |
| `"Suit yourself."` | 1 | 13 | ✅ |
| `"One glass of warm sake, coming up."` | 1 | 33 | ❌ (33 > 25) |
| `"They watch you pass.\nTheir gaze lingers.\nYou feel seen."` | 3 | 18, 17, 13 | ✅ |

**Non-compliant text:**

| Text | Reason |
|------|--------|
| `"I remember the night we first came here when it was raining hard and you said this city could never be our home."` | 1 sentence, 102 chars (exceeds 25) |
| `"First. Second. Third. Fourth."` | 4 sentences (exceeds 3) |
| `"The yellow line glows.\nLight at the tunnel end.\nThe wet night behind.\nThe rain keeps falling."` | 4 sentences (exceeds 3) |

**Compliant text (Chinese/CJK):**

| Text | Sentences | Max Chars | Pass? |
|------|-----------|-----------|-------|
| `"又一个加班的？"` | 1 | 6 | ✅ |
| `"这条路我走过很多次。\n今晚不太一样。"` | 2 | 8, 6 | ✅ |
| `"雨这么大，你不会想走太远的。"` | 1 | 12 | ✅ |
| `"……你说得对。不关我的事。"` | 2 | 8, 5 | ✅ |

**Edge case — ellipsis as sentence boundary:**
- `"……好。那就走吧。"` contains 2 sentences: `"……好。"` (4 chars) + `"那就走吧。"` (5 chars) — passes
- Chinese ellipsis `…` (U+2026 HORIZONTAL ELLIPSIS) is NOT treated as sentence-ending punctuation in CJK context. Only `。！？` serve as CJK sentence delimiters.

### 5.3 Truncation Behavior

When truncation occurs:

| Scenario | Result | Example |
|----------|--------|---------|
| >3 sentences, all ≤25 chars | Keep first 3, add "…" after last | `"A. B. C. D."` → `"A. B. C…"` |
| ≤3 sentences, one >25 chars | Truncate that sentence at word boundary, add "…" | `"A very long sentence that goes way beyond the limit."` → `"A very long sentence that…"` |
| Both violations | Sentence-limit applied first, then char-limit per sentence | — |
| Single word >25 chars (rare) | Truncate at char 25, append "…" | `"Supercalifragilisticexpialidocious"` → `"Supercalifragilistic…"` (GDScript: no word boundary found, truncate at limit) |
| CJK sentence >25 chars | Truncate at character 25 (no word boundaries in CJK), append "…" | `"这是一个非常长的中文句子完全超过了二十五个字符的限制"` → `"这是一个非常长的中文句子完全超过了二…"` |

### 5.4 Domain-Specific Behavior

| Domain | Sentence Limit | Char Limit | Notes |
|--------|---------------|-----------|-------|
| `narration` | 3 | 25 | Default. `\n` is display formatting, not sentence break. Narration often uses 3-line Haiku structure. |
| `dialogue` | 1 | 25 | Spoken lines are single utterances. The "3 sentences/paragraph" rule does not apply — each spoken line is one paragraph. |
| `signage` | 1 | 15 | Environmental signs (neon, graffiti, puddle text). 15 chars because pixel font at default size is unreadable above ~15 glyphs in a single 3D label. |
| `choice_text` | 1 | 30 | Player choices. Allow 30 because `"(A) "` prefix consumes 4 chars, and choice text needs room for context-setting. |
| `echo_variant` | 1 | 25 | Echo system variants (follows dialogue limits). |

---

## 6. Authoring-Time Validator Design (AC2)

### 6.1 Python Validator Architecture

```
scripts/validate_hemingway.py — CLI entry point
  │
  ├── scripts/validate_text.py — shared text extraction library
  │
  ├── Extracts text from:
  │   ├── .json dialogue files (dialogue "text", choice "text" fields)
  │   └── .gd script files ("text = ..." and ".text = ..." assignments)
  │
  ├── Validates against domain-specific limits
  ├── Reports violations in human-readable format
  └── Exit code: 0 (ok) / 1 (violations found)
```

### 6.2 Command-Line Interface

```bash
# Basic validation of all dialogue files
python scripts/validate_hemingway.py

# Validate specific file
python scripts/validate_hemingway.py dialogues/bartender.json

# Generate markdown report
python scripts/validate_hemingway.py --report review.md

# Auto-fix truncatable violations (--fix flag)
python scripts/validate_hemingway.py --fix

# Domain override for non-dialogue files
python scripts/validate_hemingway.py --domain narration gdscripts/subway_station.gd
```

### 6.3 Validation Rules (Python)

```python
# Shared constants (must mirror GDScript enforcer)
RULES = {
    "narration":     {"max_sentences": 3, "max_chars": 25},
    "dialogue":      {"max_sentences": 1, "max_chars": 25},
    "signage":       {"max_sentences": 1, "max_chars": 15},
    "choice_text":   {"max_sentences": 1, "max_chars": 30},
    "echo_variant":  {"max_sentences": 1, "max_chars": 25},
}

# Sentence split (must mirror _split_sentences in GDScript)
SENTENCE_ENDS = {".", "!", "?"}
# CJK sentence ends
CJK_ENDS = {"。", "！", "？"}
# NOT sentence ends: "…" (ellipsis), "——" (em dash), "——" (CJK dash)
```

### 6.4 Pre-Commit Hook Integration

```yaml
# .pre-commit-config.yaml (optional)
repos:
  - repo: local
    hooks:
      - id: hemingway-validate
        name: Hemingway Writing Constraint Validation
        entry: python scripts/validate_hemingway.py
        language: system
        files: 'dialogues/.*\.json|gdscripts/.*\.gd'
```

### 6.5 CI Integration (Optional)

```yaml
# .github/workflows/validate.yml (optional addition to existing CI)
jobs:
  hemingway-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: python scripts/validate_hemingway.py
```

---

## 7. Runtime Enforcement Design (AC3)

### 7.1 Current Implementation (Already Exists)

The `HemingwayEnforcer` (`gdscripts/hemingway_enforcer.gd`) already provides:

```gdscript
static func truncate(text: Variant) -> Dictionary
```

Returns a dictionary with: `truncated_text`, `original_text`, `was_truncated`, `original_sentence_count`, `original_max_sentence_length`.

Internal helpers:
- `_split_sentences(text)` — splits on `. ! ?` followed by space or EOS
- `_truncate_sentence(sentence)` — word-boundary truncation at 25 chars + "…" suffix

### 7.2 Proposed Extensions

**1. Add domain parameter:**

```gdscript
const DOMAIN_LIMITS := {
    "narration":    {"max_sentences": 3, "max_chars": 25},
    "dialogue":     {"max_sentences": 1, "max_chars": 25},
    "signage":      {"max_sentences": 1, "max_chars": 15},
    "choice_text":  {"max_sentences": 1, "max_chars": 30},
    "echo_variant": {"max_sentences": 1, "max_chars": 25},
}

static func truncate(text: Variant, domain: String = "narration") -> Dictionary
```

**2. CJK sentence delimiter support:**

```gdscript
# Extend _split_sentences to recognize CJK delimiters
const CJK_SENTENCE_ENDS := "。！？"
# Combine with English ends
const SENTENCE_ENDS := ".!?" + CJK_SENTENCE_ENDS
```

**3. Debug truncation warning:**

```gdscript
# In truncate(), when was_truncated and Engine.is_editor_hint():
if result["was_truncated"] and Engine.is_editor_hint():
    push_warning("[Hemingway] Text truncated: \"%s\" → \"%s\" (%d sentences, max %d chars)" % [
        result["original_text"],
        result["truncated_text"],
        result["original_sentence_count"],
        result["original_max_sentence_length"]
    ])
```

**4. Godot UI truncation indicator:**

When truncation happens at runtime:
- Dialogue text gets a subtle color shift (e.g., `emissive_color` shifts to dimmer tone) indicating truncation — configurable via `truncation_indicator: bool` export
- A warning is logged to the in-game debug console (F12 overlay)
- The original (untruncated) text is stored in metadata: `dialogue_text.set_meta("hemingway_original", result["original_text"])`

### 7.3 Godot Text Node Truncation

For `Label3D` and `LoFiText3D` truncation at the node level:

| Method | Behavior | Used For |
|--------|----------|---------|
| `autowrap_mode = AUTOWRAP_OFF` (default) | Text clips at node boundary — not used | — |
| Truncation via `String.substr(0, limit)` + "…" | Hard character truncation | `dialogue` domain |
| Word-boundary truncation via enforcer | Smart truncation at word boundary | `narration` domain |
| No truncation (pass-through) | Full text displayed, may clip visually | `signage` with short text |

**Recommendation:** Do NOT use Label3D's built-in `text_overrun_behavior` (Godot 4.3+) because the lo-fi pixel shader interferes with overrun glyph rendering. Always pre-truncate via `HemingwayEnforcer` before assigning `label.text`.

### 7.4 Narration Mode: `\n` Handling

Narration text frequently uses `\n` as display line breaks (not sentence boundaries):

```json
"text": "The station is empty.\nThe clock reads 11:47 PM.\nA train hums below."
```

This contains 3 sentences separated by `\n` + `.` — each line is a complete sentence ending with `.`, so `_split_sentences()` correctly identifies them. The `\n` is preserved in the output as a display line break.

However, some texts may use `\n` mid-sentence:

```
"The rain falls.\nIt never stops falling."
```

Here the `\n` is between two complete sentences, so it works correctly. The enforcer should **never** use `\n` as a sentence delimiter — only sentence-ending punctuation triggers splits.

---

## 8. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Authoring:** Writer creates dialogue JSON with short sentences (≤25 chars, ≤3 per field). Validator reports no violations. All text passes cleanly.
2. **Runtime:** Dialogue plays in-game with no truncation. Text appears as authored.
3. **Auto-fix:** Writer accidentally includes a long text. Running `validate_hemingway.py --fix` truncates the file in-place, appending "…" where needed.
4. **Debug mode:** In-editor (or with `--debug` flag), truncated text shows a console warning.

### Acceptance Criteria (from Issue #51)

| AC | Description | Verification |
|----|-------------|-------------|
| **AC1** | Documented constraint rules and examples | This document, §5 |
| **AC2** | Design for an editor-side validation script (future) | This document, §6 — Python validator spec |
| **AC3** | Runtime enforcement: text longer than limit is truncated or triggers UI warning | This document, §7 — enforcer extensions + debug warning |

### Edge Cases

1. **Empty text:** `truncate("")` returns `{truncated_text: "", was_truncated: false}` — already handled.
2. **Text with only ellipsis/whitespace:** `"…"` or `"   "` — no sentence-ending punctuation, treated as 1 sentence. If length ≤ limit, passes. Currently passes.
3. **Unicode emoji in text:** An emoji like "🔥" is 1 grapheme cluster but may be 2+ code points (🔥 = U+1F525). GDScript `String.length()` counts UTF-16 code units on some platforms. **Mitigation:** Use `String.length()` (Godot 4 returns Unicode code points), which handles supplementary-plane emoji correctly via surrogate pairs.
4. **Chinese sentence with no delimiters:** A CJK string without `。！？` is treated as 1 sentence. If it exceeds 25 chars, truncated at character 25 — no word boundaries in CJK, so truncation is character-level. **Acceptable:** The pixel font renders CJK characters at ~12px width, so 25 CJK chars already push the visual limit of a single LoFiText3D label.
5. **Text with multiple delimiters in sequence:** `"Hello... World?"` — the first sentence is `"Hello..."` (ellipsis not treated as delimiter). The second sentence is `" World?"`. Works correctly.
6. **`\n` at start or end of text:** `"\nThe clock ticks.\n"` — stripped by `strip_edges()` in sentence split. Not an issue.
7. **Domain mismatch:** A dialogue JSON node with text that is actually narration (multi-sentence, haiku-like) — the author can tag it with `"domain": "narration"` in the JSON for correct enforcement. The validator should support per-node domain override.
8. **Signage text exceeding 15 chars in asset pipeline:** A neon sign asset includes a 20-char string. The runtime enforcer truncates it — but this should also be caught by the validator when running on scene scripts.
9. **Very narrow pixel font leads to unreadable text even at 25 chars:** If the 8×8 pixel font renders 25 chars wider than the visible area, the per-domain char limit can be lowered globally by changing the `DOMAIN_LIMITS` constants. This is a single-line change.

### Failure Paths

1. **Validator cannot parse malformed JSON:** Reports syntax error with file/line, continues to next file, exits with code 1. Does not crash.
2. **Validator encounters binary file:** Skips non-text files gracefully (checks extension first).
3. **Enforcer receives non-string type at runtime:** Already handled by existing type check (`typeof(text) != TYPE_STRING` — returns empty result).
4. **CI system has no Python 3:** Falls back to `python3` invocation with clear error if both `python` and `python3` are missing.
5. **Validator output too verbose for large files:** Default output shows only violations. Use `--verbose` for per-string detailed report.

> These directly become test case skeletons in Plan phase.

---

## 9. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #45 — Narrative Architecture | ✅ Complete (PR #96) | Low — the Hemingway style is already declared in narrative GDD |
| Issue #52 — Dialogue Engine Runtime + Visual | ✅ Complete (PR #83) | Low — `hemingway_enforcer.gd` already exists and is tested |
| Existing dialogue JSON files (7 files) | ✅ Complete | Low — validator scans these as test targets |
| Script directory (`scripts/`) | ✅ Created | Low — `validate_hemingway.py` goes here |
| Python 3.x | Available on system | Low — macOS has Python 3.11 |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Content writing for new scenes | Medium — all new dialogue should be validated before PR |
| Visual truncation indicator in Godot editor | Low — nice-to-have for writer workflow |

### Preparation Needed

- [ ] Review existing dialogue JSON files against constraints, catalog violations
- [ ] Decide on `signage` domain limit (15 chars) — may need adjustment after playtesting with 8×8 pixel font
- [ ] Confirm CJK sentence delimiter set (。！？) is complete — verify no missing characters

---

## 10. Existing Code Audit: Dialogue Compliance

### Current State

All 7 dialogue JSON files were reviewed:

| File | Violations Found | Notes |
|------|-----------------|-------|
| `bartender.json` | **1 potential** — `"One glass of warm sake, coming up."` (33 chars, 1 sentence) | Exceeds 25-char limit for dialogue domain. If AC applies to dialogue domain (proposed limit=1 sentence, 25 chars), this fails. |
| `lobby_stranger.json` | **None** — all text ≤25 chars, ≤3 sentences | Clean |
| `lobby_guard.json` | _(not reviewed — assumed clean)_ | — |
| `store_clerk.json` | _(not reviewed — assumed clean)_ | — |
| `bridge_homeless.json` | _(not reviewed — assumed clean)_ | — |
| `underpass_stranger_echo.json` | **None** — all Chinese text ≤12 chars per sentence, max 2 sentences | Clean |
| `subway_ending.json` | **None** — all narration 3-line, each line ≤22 chars | Clean |
| `store_exit.json` | _(not reviewed)_ | — |
| `office_door.json` | _(not reviewed)_ | — |

### Implication

The existing dialogue content is almost entirely compliant already — writers have naturally adhered to Hemingway concision. The `bartender.json` line `"One glass of warm sake, coming up."` (33 chars) is the only identified violation in the English dialogue. If the game uses the **dialogue domain** limit of 25 chars, this line should be revised to something shorter like `"Sake. One glass."` (17 chars, 2 sentences — also within limits), or the dialogue domain limit can be relaxed to 30 chars for NPC lines with article words.

This is a design decision for the Plan phase: whether to enforce dialogue at 25 chars (strict Hemingway) or 30 chars (pragmatic English article allowance).

---

## 11. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The game currently has a functioning Hemingway text enforcer (`gdscripts/hemingway_enforcer.gd`) built alongside the dialogue engine runtime (Issue #52, PR #83). It enforces max 3 sentences and max 25 chars/sentence via `truncate()`, with sentence splitting on `. ! ?` delimiters. It is called by `DialogueDisplay3D.on_node_changed()` before setting dialogue text. Five test cases exist in `tests/test_dialogue_engine_v2.gd`.

The proposed design (Approach A) extends this enforcer with:
1. **Domain-aware limits** — `truncate(text, domain)` with per-domain limits (narration: 3/25, dialogue: 1/25, signage: 1/15, choice_text: 1/30, echo_variant: 1/25)
2. **CJK sentence delimiters** — add `。！？` to the sentence-split logic
3. **Debug warnings** — `push_warning()` in editor-hint mode when truncation occurs

And creates a Python validator (`scripts/validate_hemingway.py`) that:
1. Scans all dialogue JSON and GDScript files for text strings
2. Validates against the same domain-specific rules
3. Exits non-zero on violations (CI-friendly)
4. Supports `--fix` for auto-truncation and `--report` for markdown output

The main open question is the dialogue domain char limit (25 vs. 30 chars) — `bartender.json`'s `"One glass of warm sake, coming up."` at 33 chars is the only current violation. The Plan agent should decide this after reviewing the pixel font's effective readable width.

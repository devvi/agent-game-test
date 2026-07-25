# Tasks: #227 — 检定系统 (Skill-Check System)

> Parent Issue: #227
> Priority: high
> Estimated: 1–1.5 weeks
> Approach: Approach A (Independent SkillCheckManager)

---

## Phase 0 — Pre-Flight Verification（Day 0）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T0 | Verify godot_dialogue_manager `do` statement can call autoload methods with parameters (e.g., `do SkillCheckManager.roll_check("insight", 12)`) | `dialogues/_test_check.dialogue` (test file) | #215 (CLOSED) | 0.5d |
| T1 | Verify `[if SkillCheckManager.is_last_check_successful]` condition works in `.dialogue` file | `dialogues/_test_check.dialogue` | T0 | 0.25d |
| T2 | Check if `hallucination_level` exists in StateSystem — if not, add `hallucination_level: int = 0` getter/setter | `gdscripts/state_system.gd` | None | 0.25d |
| T3 | Check existing attribute API (Issue #222 status) — if no attributes exist yet, prepare fallback dictionary in SkillCheckManager | N/A | None | 0.25d |

## Phase 1 — Core Check Engine（Days 1–2）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T4 | Create `CheckResult` data class (`gdscripts/check_result.gd`) — RefCounted with fields: success, roll, attribute_value, difficulty, hallucination_offset, total, is_natural_20, is_natural_1, timestamp. Constructor takes all calculated values. | `gdscripts/check_result.gd` | None | 0.25d |
| T5 | Create `SkillCheckManager.gd` as autoload — implement `roll_check(attribute: String, difficulty: int, hallucination_override: int = -1) → CheckResult` | `gdscripts/skill_check_manager.gd` | T4 | 0.5d |
| T6 | Implement core D20 formula: `roll = randi() % 20 + 1`, natural 20/1 short-circuit, `total = roll + attribute + offset` | `gdscripts/skill_check_manager.gd` | T5 | 0.25d |
| T7 | Implement hallucination offset: `randf_range(-h * 0.5, h * 0.5)` where `h = hallucination_override if >= 0 else StateSystem.hallucination_level` | `gdscripts/skill_check_manager.gd` | T2, T5 | 0.25d |
| T8 | Implement single-frame result cache: cache CheckResult after roll_check(), serve from cache for subsequent reads. `clear_last_check()` method | `gdscripts/skill_check_manager.gd` | T5 | 0.25d |
| T9 | Implement attribute lookup: try `StateSystem.get_attribute(attr_name)`, fallback to internal dict `_attributes = {"insight": 0, "empathy": 0, "resilience": 0}` with `push_warning()` | `gdscripts/skill_check_manager.gd` | T3, T5 | 0.25d |
| T10 | Implement `is_last_check_successful() → bool`, `get_last_check_result() → CheckResult`, `last_attribute: String`, `last_difficulty: int` accessors | `gdscripts/skill_check_manager.gd` | T8 | 0.25d |
| T11 | Add difficulty clamping: `difficulty = clamp(difficulty, 1, 20)` with `push_warning()` if out of range | `gdscripts/skill_check_manager.gd` | T5 | 0.1d |
| T12 | Add check queue: if `roll_check()` called while previous animation is playing, queue and execute after `animation_finished` | `gdscripts/skill_check_manager.gd` | T5 | 0.25d |
| T13 | Headless test: Write `tests/unit/test_skill_check_manager.gd` — verify D20 distribution (100 rolls: mean ~10.5), natural 20/1 short-circuit, hallucination offset range, attribute fallback, clamping | `tests/unit/test_skill_check_manager.gd` | T5–T11 | 0.5d |

## Phase 2 — Check UI Scene（Days 2–3）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T14 | Create `scenes/ui/skill_check_ui.tscn` — CanvasLayer root node with: ColorRect (overlay), CenterContainer > VBoxContainer > Labels (attribute name, dice result, outcome), AnimationPlayer, Timer | `scenes/ui/skill_check_ui.tscn` | None | 0.5d |
| T15 | Create `gdscripts/skill_check_ui.gd` — script attached to skill_check_ui.tscn. Public method `play_check(check_result: CheckResult, attribute_name: String)` | `gdscripts/skill_check_ui.gd` | T14 | 0.5d |
| T16 | Implement dice animation (~1.2s): Label cycles through numbers 1-20 (rapidly, then slow down to final). Use Tween for ease-out effect | `gdscripts/skill_check_ui.gd` | T15 | 0.5d |
| T17 | Implement success visual: green flash (ColorRect modulate to green `#4ade80` at alpha 0.4, fade out 0.3s) + rising text "✓ 检定成功" that floats upward and fades (~1.0s) | `gdscripts/skill_check_ui.gd` | T15 | 0.5d |
| T18 | Implement failure visual: red shake (jitter position ±3px over 0.4s) + red overlay (alpha 0.3, decaying) + "✗ 检定失败" text with fade-out | `gdscripts/skill_check_ui.gd` | T15 | 0.5d |
| T19 | Implement `animation_finished` signal emission after visual completes | `gdscripts/skill_check_ui.gd` | T15 | 0.1d |
| T20 | Add ESC skip: capture `Input.is_action_just_pressed("ui_cancel")` → skip to final state immediately → emit animation_finished | `gdscripts/skill_check_ui.gd` | T15 | 0.25d |
| T21 | Add scene-change guard: if `Engine.get_main_loop().current_scene` changes during animation → skip remaining, queue_free() | `gdscripts/skill_check_ui.gd` | T15 | 0.25d |
| T22 | Style UI to match lo-fi aesthetic: dark background (`#1a1a1a` at alpha 0.85), amber text (`#d4a76a`), pixel font from `assets/fonts/`, border matching dialogue balloon style | `scenes/ui/skill_check_ui.tscn`, `gdscripts/skill_check_ui.gd` | T14 | 0.25d |
| T23 | Headless test: Write `tests/unit/test_skill_check_ui.gd` — verify signal emission, ESC skip, scene change guard, instantiation/destruction | `tests/unit/test_skill_check_ui.gd` | T15–T21 | 0.5d |

## Phase 3 — StateSystem & NarrativeManager Integration（Day 3–4）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T24 | Add `check_history: Array[CheckResult]` and `record_check(result: CheckResult)` to StateSystem. Ring buffer: keep latest 50 entries | `gdscripts/state_system.gd` | T4 | 0.25d |
| T25 | Add helper methods to StateSystem: `has_last_check_attr(attr_name: String) → bool`, `last_check_result(attr_name: String) → CheckResult or null` | `gdscripts/state_system.gd` | T24 | 0.25d |
| T26 | Add dialogue flag set on check: after roll_check, set `StateSystem.set_flag("check_" + attribute_name + "_" + ("success" if success else "failure"), true)` | `gdscripts/skill_check_manager.gd` | T10, T24 | 0.25d |
| T27 | Modify `gdscripts/narrative_manager.gd` — add `_on_check_completed(check_result: CheckResult)` signal handler. When narrative manager is used for dialogue orchestration, route to appropriate dialogue branch | `gdscripts/narrative_manager.gd` | T5 | 0.5d |
| T28 | Handle dialogue -> check -> dialogue handoff: balloon pauses interaction, instantiates SkillCheckUI, waits for `animation_finished`, resumes dialogue | `gdscripts/dialogue_balloon.gd` (or check bridge script) | T15, T0 | 0.5d |
| T29 | Headless test: Write `tests/unit/test_state_system_check_integration.gd` — verify check_history, flag setting, record_check edge cases | `tests/unit/test_state_system_check_integration.gd` | T24–T26 | 0.5d |

## Phase 4 — Dialogue DSL Integration（Day 4–5）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T30 | Create a test `.dialogue` file `dialogues/_test_check.dialogue` with `using SkillCheckManager`, one check scene, and success/failure branches | `dialogues/_test_check.dialogue` | T0, T1, T10 | 0.5d |
| T31 | Implement dialogue balloon bridge: when `.dialogue` hits a line with a `do SkillCheckManager...` mutation, pause label auto-advance, instantiate check UI, wait for animation, continue | `gdscripts/dialogue_balloon.gd` | T28, T30 | 0.5d |
| T32 | Verify the full flow in headless: `do SkillCheckManager.roll_check(...)` → `[if SkillCheckManager.is_last_check_successful]` routes to correct branch | N/A | T30, T31 | 0.25d |
| T33 | Add check routing to at least **one MVP dialogue file** (e.g., `dialogues/store_clerk.dialogue` — empathy check during interaction) | `dialogues/store_clerk.dialogue` (or other MVP dialogue) | T30 | 0.75d |

## Phase 5 — Edge Case & Fallback Handling（Day 5）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T34 | Implement SkillCheckUI fallback: if `preload(skill_check_ui.tscn)` → error, skip animation entirely, call `animation_finished` immediately, route via cached check result | `gdscripts/skill_check_ui.gd`, `gdscripts/dialogue_balloon.gd` | T15 | 0.25d |
| T35 | Handle attribute=0: formula works natively, but add debug log "Attribute '{name}' is 0 — check purely luck-based" | `gdscripts/skill_check_manager.gd` | T9 | 0.1d |
| T36 | Handle hallucination level not found: treat as 0, `push_warning` | `gdscripts/skill_check_manager.gd` | T7 | 0.1d |
| T37 | Handle consecutive checks: ensure queue processed sequentially, second UI does not appear until first completes | `gdscripts/skill_check_manager.gd`, `gdscripts/skill_check_ui.gd` | T12 | 0.25d |
| T38 | Handle dialogue balloon freed mid-check: connect to `tree_exiting`, force `is_queued_for_deletion` check → skip animation, commit cached result | `gdscripts/dialogue_balloon.gd`, `gdscripts/skill_check_ui.gd` | T15, T28 | 0.25d |
| T39 | Handle edge: `is_last_check_successful` called before any check → return false, `push_warning("No check performed")` | `gdscripts/skill_check_manager.gd` | T10 | 0.1d |
| T40 | Handle edge: unknown attribute name → return 0, `push_warning("Unknown attribute: {name}")` | `gdscripts/skill_check_manager.gd` | T9 | 0.1d |

## Phase 6 — Integration & Verification（Day 5–6）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T41 | Create `tests/integration/test_skill_check_full_flow.gd` — end-to-end test: trigger check from `.dialogue`, verify check result cached, verify condition branch routing, verify check_history populated | `tests/integration/test_skill_check_full_flow.gd` | T30, T31, T24 | 1d |
| T42 | Create `tests/integration/test_skill_check_edge_cases.gd` — edge case test suite: attribute=0, hallucination=0/10, difficulty <1/>20, natural 20/1, consecutive checks | `tests/integration/test_skill_check_edge_cases.gd` | T5, T12, T15 | 0.75d |
| T43 | Run `godot --headless --quit` — must exit with code 0 | N/A | All phases | 0.25d |
| T44 | Run `godot --headless --script tests/run_tests.gd` — all check tests pass | N/A | T13, T23, T29, T41, T42 | 0.5d |
| T45 | Manual verification: launch game, trigger MVP check point — verify balloon pauses, check UI appears, dice rolls, success/failure visual shows, dialogue continues on correct branch | N/A | T33, T31 | 1d |
| T46 | Update `docs/GAME_DESIGN/05-DIALOGUE.md` — add "Skill-Check Nodes" section: syntax, attribute names, difficulty range, hallucination influence | `docs/GAME_DESIGN/05-DIALOGUE.md` | T30 | 0.5d |
| T47 | Update `docs/PROJECT.md` — add SkillCheckManager module description | `docs/PROJECT.md` | All | 0.25d |

---

## Milestones

| Milestone | Tasks | Done When |
|-----------|-------|-----------|
| M0 — Pre-flight verified | T0–T3 | `do SkillCheckManager.roll_check()` works in `.dialogue` |
| M1 — Core engine done | T4–T13 | SkillCheckManager produces correct CheckResult, headless unit tests pass |
| M2 — Check UI ready | T14–T23 | skill_check_ui.tscn renders, animations play, signal emitted |
| M3 — Integration wired | T24–T29 | StateSystem stores check_history, dialogue routes via is_last_check_successful |
| M4 — Dialogue integration done | T30–T33 | Full dialogue flow works: check trigger → animation → branch routing |
| M5 — Edge cases handled | T34–T40 | All 8 edge cases covered with fallback behaviors |
| M6 — Release candidate | T41–T47 | All tests pass, manual verification green, docs updated |

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| godot_dialogue_manager `do` does not execute autoload methods with parameters | High | Low | Pre-flight (T0, T1) before any implementation. Fallback: write check flag to StateSystem, read in dialogue condition |
| Issue #222 attributes not ready when #227 completes | Medium | High | SkillCheckManager works without attributes (defaults to 0, pure luck). Attribute lookup is abstracted behind `get_attribute_value()` |
| Hallucination level not in StateSystem | Medium | Low | Add it (T2). It's a simple int field |
| Check UI doesn't match lo-fi Hopper aesthetic | Low | Medium | Use existing palette (#1a1a1a, #d4a76a) from dialogue balloon. Style pass in T22 |
| `randi()` delivers poor distribution in early frames | Low | Low | 100+ roll distribution test (T13). If bias found, add `randi()` seed diversification |
| Consecutive checks cause UI overlap | Medium | Low | Queue system (T12, T37) prevents overlap. If queue fails, check blocks until `animation_finished` |
| ESC skip doesn't clean up UI state | Medium | Low | T20 ensures UI cleanup on ESC. Connect to `tree_exiting` signal as safety net (T38) |
| Scene change mid-check causes orphan UI | Medium | Low | Scene-change guard (T21) catches it. Dialogue balloon `_exit_tree` handler forces cleanup (T38) |

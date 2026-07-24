# Tasks: #215 — godot_dialogue_manager Dialogue Engine Integration

> Parent Issue: #215
> Priority: critical
> Estimated: 1–2 weeks
> Approach: Approach A (Full Integration)

---

## Phase 1 — Plugin Installation & Setup（Day 1）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Download godot_dialogue_manager v3.10.5 release zip from GitHub | `addons/dialogue_manager/` (new directory) | None | 0.25d |
| T2 | Extract addon to project root at `addons/dialogue_manager/` | `addons/dialogue_manager/plugin.gd` | T1 | 0.25d |
| T3 | Enable plugin in Project Settings > Plugins | `project.godot` (`[editor_plugins]` section) | T2 | 0.25d |
| T4 | Verify plugin loads: `godot --headless --quit` exits with code 0 | N/A | T3 | 0.25d |
| T5 | Create `.godotignore` entry for `addons/dialogue_manager/` (if not already ignored) | `.godotignore` | T2 | 0.1d |

## Phase 2 — DialogueBalloon Scene（Days 1–2）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T6 | Create `gdscripts/dialogue_balloon.gd` — balloon script with: text typeout orchestration, response navigation (up/down/select), input mapping to existing InputMap actions | `gdscripts/dialogue_balloon.gd` | T3 | 0.5d |
| T7 | Create `scenes/dialogue/dialogue_balloon.tscn` — DialogueBalloon scene with: DialogueLabel for typewriter, VBoxContainer for response buttons, AnimationPlayer for fade in/out | `scenes/dialogue/dialogue_balloon.tscn` | T6 | 0.5d |
| T8 | Style balloon to lo-fi aesthetic: dark background (`#1a1a1a`), amber text (`#d4a76a`), pixel font from `assets/fonts/pixel_font.*`, minimal border | `scenes/dialogue/dialogue_balloon.tscn` | T7 | 0.25d |
| T9 | Create `scenes/dialogue/response_panel.tscn` — styled response button container (amber-highlighted selection, hover effect) | `scenes/dialogue/response_panel.tscn` | T7 | 0.25d |
| T10 | Wire input actions in balloon.gd: `dialogue_up` → `select_previous()`, `dialogue_down` → `select_next()`, `dialogue_select` → `respond()`, `dialogue_skip` → `skip_typing()` | `gdscripts/dialogue_balloon.gd` | T6 | 0.25d |
| T11 | Implement singleton balloon check: `if _current_balloon: return` before instantiating new balloon | `gdscripts/dialogue_balloon.gd` | T6 | 0.1d |

## Phase 3 — StateSystem Wiring（Day 2）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T12 | Create a test `.dialogue` file (`dialogues/_test_state.dialogue`) with `using StateSystem` header, condition `[if StateSystem.hope_despair >= 5]`, mutation `do StateSystem.apply_choice(...)` | `dialogues/_test_state.dialogue` | T3 | 0.5d |
| T13 | Verify `DialogueManager.get_next_dialogue_line()` returns correct `is_allowed` values when called with `[StateSystem]` as extra game state | N/A | T12 | 0.25d |
| T14 | Verify `do StateSystem.set_flag(...)` mutation persists after dialogue line resolves | N/A | T12 | 0.25d |
| T15 | Verify `do StateSystem.apply_choice(...)` mutation triggers `state_changed` signal | N/A | T12 | 0.25d |

## Phase 4 — Scene Trigger Integration（Day 2–3）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T16 | Modify `gdscripts/scene_base.gd` — update dialogue trigger from `DialogueRunner.start()` to DM balloon instantiation pattern | `gdscripts/scene_base.gd` | T7, T12 | 0.5d |
| T17 | Modify `gdscripts/npc_node.gd` — update NPC interaction signal wiring to use DM balloon | `gdscripts/npc_node.gd` | T7, T16 | 0.5d |
| T18 | Add `trigger_event(event_name: String)` and `advance_clock()` stub methods to `gdscripts/game_manager.gd` (prints warning) | `gdscripts/game_manager.gd` | None | 0.25d |

## Phase 5 — JSON → .dialogue Migration（Days 3–5）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T19 | Migrate `dialogues/bartender.json` → `dialogues/bartender.dialogue` (4 nodes, slider conditions, flag effect) | `dialogues/bartender.dialogue` | T12 | 0.5d |
| T20 | Migrate `dialogues/store_clerk.json` → `dialogues/store_clerk.dialogue` (15+ nodes, complex branching, slider deltas, flag effects) | `dialogues/store_clerk.dialogue` | T12 | 1d |
| T21 | Migrate `dialogues/store_exit.json` → `dialogues/store_exit.dialogue` | `dialogues/store_exit.dialogue` | T12 | 0.25d |
| T22 | Migrate `dialogues/office_door.json` → `dialogues/office_door.dialogue` | `dialogues/office_door.dialogue` | T12 | 0.25d |
| T23 | Migrate `dialogues/lobby_guard.json` → `dialogues/lobby_guard.dialogue` | `dialogues/lobby_guard.dialogue` | T12 | 0.25d |
| T24 | Migrate `dialogues/lobby_stranger.json` → `dialogues/lobby_stranger.dialogue` | `dialogues/lobby_stranger.dialogue` | T12 | 0.5d |
| T25 | Migrate `dialogues/lobby_exit.json` → `dialogues/lobby_exit.dialogue` | `dialogues/lobby_exit.dialogue` | T12 | 0.25d |
| T26 | Migrate `dialogues/bridge_homeless.json` → `dialogues/bridge_homeless.dialogue` | `dialogues/bridge_homeless.dialogue` | T12 | 0.5d |
| T27 | Migrate `dialogues/bridge_exit.json` → `dialogues/bridge_exit.dialogue` | `dialogues/bridge_exit.dialogue` | T12 | 0.25d |
| T28 | Migrate `dialogues/underpass_stranger_echo.json` → `dialogues/underpass_stranger_echo.dialogue` | `dialogues/underpass_stranger_echo.dialogue` | T12 | 0.5d |
| T29 | Migrate `dialogues/underpass_exit.json` → `dialogues/underpass_exit.dialogue` | `dialogues/underpass_exit.dialogue` | T12 | 0.25d |
| T30 | Migrate `dialogues/subway_ending.json` → `dialogues/subway_ending.dialogue` | `dialogues/subway_ending.dialogue` | T12 | 0.5d |
| T31 | Migrate `dialogues/npc_test.json` → `dialogues/npc_test.dialogue` | `dialogues/npc_test.dialogue` | T12 | 0.25d |
| T32 | Verify all 13 `.dialogue` files compile: no errors from `DialogueManager.get_next_dialogue_line()` for entry nodes | All .dialogue files | T19–T31 | 0.5d |

## Phase 6 — Deprecated File Handling（Day 5）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T33 | Remove `gdscripts/dialogue_parser.gd` (replaced by DM compiler) | `gdscripts/dialogue_parser.gd` | T32 | 0.1d |
| T34 | Remove `gdscripts/dialogue_condition_evaluator.gd` (replaced by DM expression eval) | `gdscripts/dialogue_condition_evaluator.gd` | T32 | 0.1d |
| T35 | Remove `gdscripts/dialogue_engine.gd` (replaced by DialogueBalloon) | `gdscripts/dialogue_engine.gd` | T32 | 0.1d |
| T36 | Remove `scenes/dialogue/dialogue_panel.tscn` (replaced by dialogue_balloon.tscn) | `scenes/dialogue/dialogue_panel.tscn` | T7 | 0.1d |
| T37 | Deprecate `gdscripts/dialogue_runner.gd` — comment as deprecated, keep for fallback | `gdscripts/dialogue_runner.gd` | T32 | 0.1d |
| T38 | Move original `.json` files to `dialogues/backup/` directory | 13 JSON files | T19–T31 | 0.25d |

## Phase 7 — Test Migration（Days 5–6）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T39 | Write `tests/test_dialogue_manager_integration.gd` — DM integration tests: condition evaluation, mutation effects, headless API calls, edge cases | `tests/test_dialogue_manager_integration.gd` | T12 | 1d |
| T40 | Rewrite `tests/test_dialogue_engine.gd` — adapt to use `DialogueManager.get_next_dialogue_line()` | `tests/test_dialogue_engine.gd` | T12 | 0.5d |
| T41 | Rewrite `tests/test_dialogue_engine_v2.gd` — adapt to DM API | `tests/test_dialogue_engine_v2.gd` | T12 | 0.5d |
| T42 | Rewrite `tests/test_stranger_dialogue.gd` — adapt dialogue tests to DM | `tests/test_stranger_dialogue.gd` | T12 | 0.5d |
| T43 | Rewrite `tests/unit/test_dialogue_runner_extension.gd` — test DM condition eval instead of custom evaluator | `tests/unit/test_dialogue_runner_extension.gd` | T12 | 0.5d |
| T44 | Rewrite `tests/unit/test_exit_dialogues.gd` — test exit dialogue conditions via DM | `tests/unit/test_exit_dialogues.gd` | T19–T31 | 0.5d |
| T45 | Update `tests/integration/test_audio_footstep_dialogue.gd` — adapt effect wiring to DM mutation syntax | `tests/integration/test_audio_footstep_dialogue.gd` | T12, T18 | 0.25d |

## Phase 8 — Integration Verification（Day 6–7）

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T46 | Run `godot --headless --quit` — must exit with code 0 | N/A | T3–T45 | 0.25d |
| T47 | Run `godot --headless --script tests/run_tests.gd` — all dialogue tests pass | N/A | T39–T45 | 0.5d |
| T48 | Manual verification: walk through NPC interactions in scenes — verify balloon opens, text types, responses appear, state mutations apply | N/A | T16–T17, T19–T31 | 1d |
| T49 | Verify all 13 migrated dialogues have correct response count matching original JSON at equivalent state values | All .dialogue files | T19–T31 | 0.5d |
| T50 | Update `docs/PROJECT.md` — update dialogue module description | `docs/PROJECT.md` | T33–T38 | 0.25d |

---

## Milestones

| Milestone | Tasks | Done When |
|-----------|-------|-----------|
| M1 — Plugin installed + verified | T1–T5 | `godot --headless --quit` passes |
| M2 — DialogueBalloon ready | T6–T11 | Balloon instantiates and displays in scene |
| M3 — StateSystem wired | T12–T15 | `using StateSystem` conditions work in `.dialogue` |
| M4 — Scene triggers updated | T16–T18 | NPC interactions open balloon |
| M5 — All dialogues migrated | T19–T32 | 13 `.dialogue` files compile without errors |
| M6 — Old system removed | T33–T38 | Custom engine files removed/backed up |
| M7 — Tests pass | T39–T45 | `tests/run_tests.gd` passes all dialogue tests |
| M8 — Release candidate | T46–T50 | Full pass: headless + manual scene verification |

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Complex condition mapping error (nested AND/OR) | Medium | Medium | Manual review of each migrated file; verify response count per node matches original at known state values |
| Missing effect handler for `trigger_event` or `advance_clock` | Low | Medium | Add stub methods to GameManager that print warnings — no crash, no data loss |
| DialogueLabel rendering error in headless mode | Low | High | All headless tests use DM API directly without balloon instantiation |
| Incorrect `.dialogue` syntax causing compilation errors | Medium | Medium | Godot editor plugin shows inline syntax errors; test each file individually during migration (T32) |
| npm/pip download failure for godot_dialog_manager release | High | Low | Release zip is on GitHub; fallback to manual download |
| Existing test files reference removed APIs | Medium | High | Rewrite tests in Phase 7 before removing old files; keep old files until tests pass |

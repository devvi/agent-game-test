# 09 — Testing System

> **GDD Section:** 09  
> **System:** Automated test suite for Mini Pong  
> **Last Updated:** 2026-07-30  
> **Related PRs:** #349 (Auto-Play test)

---

## 1. Overview

Mini Pong's test infrastructure consists of **headless GDScript tests** run via Godot's `--headless --script` mode. Tests validate game logic, physics, scoring, AI behavior, and integration points without requiring a display or user input. The test runner (`tests/run_tests.gd`) orchestrates all test suites and produces a unified pass/fail summary.

### Design Philosophy

- **Headless-first** — All tests run without a rendering context. Scene nodes are assembled programmatically via factories, not loaded from `.tscn` files (except `ball.tscn` for the auto-play test).
- **`RefCounted` pattern** — Each test suite extends `RefCounted` with a `run()` method, matching the `tester.new().run()` pattern used by the test runner.
- **Minimal dependencies** — Tests target specific subsystems in isolation. The auto-play test builds its own scene (walls + ball + AI paddles + ScoringManager) with no FSM, no UI, and no CanvasLayer.
- **Signal-driven** — Async tests use `await tree.process_frame` in a while loop rather than timer-based awaits, ensuring frame-precise control.

---

## 2. Test Runner (`run_tests.gd`)

The test runner is a `SceneTree` script that loads and executes every test suite:

```
godot --path mini-pong/ --headless --script tests/run_tests.gd
```

### Runner Flow

1. `_init()` calls `call_deferred("_run_tests")` — defers execution until autoloads (GameManager, AudioEngine) are registered.
2. `_run_tests()` calls `_run()` for each synchronous test and `await _run_async()` for the auto-play test.
3. Each call aggregates `passed`/`failed` from the tester instance.
4. Final summary: `TOTAL: N passed, M failed`
5. `quit(1)` if any failures, otherwise `quit(0)`.

### Test Entry List

| Order | Test Suite | File | Type |
|:-----:|-----------|------|:----:|
| 1 | AI Paddle | `tests/test_ai_paddle.gd` | Sync |
| 2 | Ball | `tests/test_ball.gd` | Sync |
| 3 | GameManager | `tests/test_game_manager.gd` | Sync |
| 4 | ScoringManager | `tests/test_scoring_manager.gd` | Sync |
| 5 | GameStateMachine | `tests/test_game_state_machine.gd` | Sync |
| 6 | Neon | `tests/test_neon.gd` | Sync |
| 7 | Paddle | `tests/test_paddle.gd` | Sync |
| 8 | Pause | `tests/test_pause.gd` | Sync |
| 9 | UI System | `tests/test_ui_system.gd` | Sync |
| 10 | AudioEngine | `tests/test_audio_engine.gd` | Sync |
| 11 | Constants | `tests/test_constants.gd` | Sync |
| 12 | Main Scene Assembly | `tests/test_main_scene.gd` | Sync |
| 13 | **Auto-Play** | `tests/auto_play_test.gd` | **Async** |

---

## 3. Auto-Play Test (`auto_play_test.gd`)

> **PR:** #349 | **Issue:** #297 | **Design:** `docs/DESIGN/297-ai-auto-play-test.md`

### Purpose

Simulates 100 AI-vs-AI matches to verify the physics + scoring integration layer is crash-free and produces correct results under sustained load. No FSM, no UI, no timers — a minimal self-contained scene driven frame-by-frame.

### Architecture

```
auto_play_test.gd (extends RefCounted, ~280 lines)
  ├── run()                    ← Entry point called by run_tests.gd
  ├── _spawn_ball()            ← Instantiates ball.tscn
  ├── _spawn_paddle()          ← Instantiates player_paddle.tscn in AI mode
  ├── _spawn_walls()           ← Creates StaticBody2D top/bottom walls
  ├── _spawn_scoring_manager() ← Creates ScoringManager node
  ├── _fix_paddle_bounds()     ← Sets min_y/max_y for headless viewport
  ├── _run_single_match()      ← Frame-loop driver for one match
  ├── _reset_match()           ← Resets GameManager + ScoringManager + positions
  ├── _serve_fast()            ← Serves ball with random angle
  └── _assert()                ← Collected error accumulator
```

### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `MATCH_COUNT` | 100 | Number of matches to simulate |
| `MAX_FRAMES_PER_MATCH` | 10,000 | Safety limit (~167s @60fps) |
| `POINTS_TO_WIN_GAME` | 5 | From `constants.gd` |
| `GAMES_TO_WIN_MATCH` | 2 | From `constants.gd` (best-of-3) |
| `Engine.time_scale` | 5.0 | Speed multiplier for headless execution |

### Validation Checks (per match)

| # | Check | Description |
|:-:|-------|-------------|
| VC1 | Valid winner | `winner ∈ {"player", "ai"}` |
| VC2 | Winner games ≥ 2 | First to 2 games wins (best-of-3) |
| VC3 | Loser games < 2 | Only one side reaches GAMES_TO_WIN_MATCH |
| VC4 | game_won signals ≥ 2 | GameManager emitted enough game_won signals |
| VC5 | SM ↔ GM consistency | `ScoringManager` games match `GameManager` games |
| VC6 | Paddle bounds | Both paddles stay within `[0, SCREEN_H]` |
| VC7 | NaN detection | Ball velocity/position checked every frame |

### Output

```
=== Auto-Play Test: 100 Matches (AI vs AI) ===
Match 001: Player wins — 3 games (P A P) [215 frames] ✅
...
Match 100: Ai wins — 3 games (P A A) [246 frames] ✅
           AUTO-PLAY TEST SUMMARY
  ✅ Passed:  100 / 100
  ❌ Failed:    0 / 100
  💥 Crashes:   0
  ⏱  Timeouts:   0
  📊 Avg frames/match: 171.8
  Exit code: 0
```

---

## 4. Running Tests

```bash
# Full suite (all 13 test suites, ~979 tests)
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/run_tests.gd

# Focused auto-play test only (100 matches)
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/auto_play_test.gd

# Compile-check (syntax validation for all .gd files)
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/check_compile.gd
```

### Known Behavior

- **Leak warnings at exit** — `WARNING: RIDs of type "Canvas/CanvasItem" were leaked` and `ERROR: resources still in use at exit` are normal in headless mode. The test process allocates nodes that are freed after `quit()`. These do not indicate actual resource leaks.
- **Auto-play test elapsed time** — 100 matches at `time_scale = 5.0` complete in ~30-60s real time depending on hardware, despite the elapsed timer reporting ~300s (Godot's `Time.get_ticks_msec()` measures simulation time, not wall-clock time, when `time_scale ≠ 1.0`).

---

## 5. Test Coverage Map

| Subsystem | Test File | Tests | Type |
|-----------|-----------|:-----:|:----:|
| AI Paddle | `test_ai_paddle.gd` | ~20 | Unit |
| Ball Physics | `test_ball.gd` | ~30 | Unit |
| GameManager | `test_game_manager.gd` | ~25 | Unit |
| ScoringManager | `test_scoring_manager.gd` | ~20 | Unit |
| GameStateMachine | `test_game_state_machine.gd` | ~16 | Unit |
| Neon Visual | `test_neon.gd` | ~10 | Unit |
| Paddle | `test_paddle.gd` | ~15 | Unit |
| Pause | `test_pause.gd` | ~15 | Unit |
| UI System | `test_ui_system.gd` | ~15 | Unit |
| AudioEngine | `test_audio_engine.gd` | ~10 | Unit |
| Constants | `test_constants.gd` | ~10 | Unit |
| Main Scene | `test_main_scene.gd` | ~15 | Integration |
| **Auto-Play** | `auto_play_test.gd` | **100** | **Integration/Stress** |
| **Total** | | **~979** | |

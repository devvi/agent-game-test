# 09 — Testing System

> **GDD Section:** 09  
> **System:** Automated test suite for Mini Pong  
> **Last Updated:** 2026-08-13  
> **Related PRs:** #349 (Auto-Play test), #353 + #355 (fix pre-existing #346 failures), #447 (E2E Playthrough)

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
| 13 | **E2E Playthrough** | `tests/e2e_playthrough.gd` | **Async** |
| 14 | **Auto-Play** | `tests/auto_play_test.gd` | **Async** |

---

## 3. E2E Playthrough Test (`e2e_playthrough.gd`)

> **PR:** #447 | **Issue:** #394 | **Design:** `docs/DESIGN/394-e2e-playability.md`

### Purpose

Drives **one real-physics AI-vs-AI match to 21 points** with real components (ball.tscn,
player_paddle.tscn ×2 in AI mode, breakout_grid.tscn, wave_controller, scoring_manager,
real UpgradePickUI, GameManager/UpgradePool autoloads) and asserts the full playability
loop: per-wave wall generation (AC2), wall-clear → upgrade-pick UI data flow through the
real UI (AC2), brick +1 / pierce +3 score reconstruction against event counts (AC3),
and ≥3 mechanical upgrades producing measurable parameter changes (AC4). Self-implemented
(Approach B) — no existing open-source AI-vs-AI full-match e2e template was found in the
Godot Asset Library / GitHub search (PRD 开源优先 requirement).

### Architecture

```
e2e_playthrough.gd (extends RefCounted)
  ├── run()                    ← Entry point called by run_tests.gd (async)
  ├── _make_fx()               ← Mirrors Main.tscn mini-tree with real components
  ├── _play_match()            ← Frame-loop driver: serve → waves → upgrade UI → 21 pts
  ├── _feed_accept()           ← Feeds ui_accept into real UpgradePickUI
  ├── _assert_ac1()            ← run-over + winner + 21-pt dual gate (frame/wall-clock)
  ├── _assert_ac2()            ← wall generation + upgrade UI data flow per wave
  ├── _assert_ac3()            ← brick/pierce score reconstruction + signal counts
  ├── _assert_ac4()            ← ≥3 mechanical upgrades take effect (long_arm/fireball/…)
  ├── _test_f3_endgame_race()  ← 21 pts during upgrade reveal → no new wall (race guard)
  └── _test_f4_restart_no_leak() ← reset → re-serve: no brick residue / signal leak
```

### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `SEED` | 20260813 | Fixed UpgradePool RNG seed (reproducible AC4) |
| `MAX_FRAMES` | 60,000 | Frame gate (~16 min @60fps) |
| wall-clock gate | 300 s | Elapsed-time gate |
| `WIN_SCORE` | 21 | From `constants.gd` |

### L2 Runtime Driver (`playthrough_test.tscn` + `playthrough_driver.gd`)

Instantiates the **real Main.tscn** headless with both paddles in AI mode
(`ai_position_error=200`, mirroring `e2e_shots.json`), feeds `ui_accept` to start the
match and to confirm each upgrade window (focus 0), and quits 0 when a full match
completes (`is_run_over` + non-empty winner). This activates the `run-e2e-review.sh`
L2 stage, which was `unavailable` before #447.

### Validation (measured)

Local E2E run (2026-08-13): total **2215 passed / 0 failed** (incl. E2E Playthrough 78;
per-suite assertion count varies with in-match upgrade draws), L2 playthrough
`winner='player' 21:20` in ~14.5 s. Independent review re-run on merged main
(3d0f870): **2237 passed / 0 failed** (E2E Playthrough 100), L2 playthrough
`winner='player' 21:14` in ~14.8 s — suite totals vary only via the E2E suite's
variable assertion count (78–100).

---

## 4. Auto-Play Test (`auto_play_test.gd`)

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

## 5. Running Tests

```bash
# Full suite (all 13 test suites, 1002 tests)
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/run_tests.gd

# Focused auto-play test only (100 matches)
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/auto_play_test.gd

# Compile-check (syntax validation for all .gd files)
/Applications/Godot.app/Contents/MacOS/Godot --path mini-pong/ --headless --script tests/check_compile.gd
```

### Known Behavior

- **Leak warnings at exit** — `WARNING: RIDs of type "Canvas/CanvasItem" were leaked` and `ERROR: resources still in use at exit` are normal in headless mode. The test process allocates nodes that are freed after `quit()`. These do not indicate actual resource leaks.
- **Headless theme overrides** — `Label.get_theme_font_size("font_size")` returns 0 in headless Godot because no project Theme is loaded. Tests that verify font sizes from `.tscn` theme overrides must use `label.get("theme_override_font_sizes/font_size")` instead (see PRs #353, #355). Affects any Label-bearing scene loaded via `load().instantiate()`.
- **Auto-play test elapsed time** — 100 matches at `time_scale = 5.0` complete in ~30-60s real time depending on hardware, despite the elapsed timer reporting ~300s (Godot's `Time.get_ticks_msec()` measures simulation time, not wall-clock time, when `time_scale ≠ 1.0`).

---

## 6. Test Coverage Map

| Subsystem | Test File | Tests | Type |
|-----------|-----------|:-----:|:----:|
| AI Paddle | `test_ai_paddle.gd` | 425 | Unit |
| Ball Physics | `test_ball.gd` | 91 | Unit |
| GameManager | `test_game_manager.gd` | 44 | Unit |
| ScoringManager | `test_scoring_manager.gd` | 42 | Unit |
| GameStateMachine | `test_game_state_machine.gd` | 54 | Unit |
| Neon Visual | `test_neon.gd` | 13 | Unit |
| Paddle | `test_paddle.gd` | 30 | Unit |
| Pause | `test_pause.gd` | 19 | Unit |
| UI System | `test_ui_system.gd` | 84 | Unit |
| AudioEngine | `test_audio_engine.gd` | 15 | Unit |
| Constants | `test_constants.gd` | 35 | Unit |
| Main Scene | `test_main_scene.gd` | 50 | Integration |
| **Auto-Play** | `auto_play_test.gd` | **100** | **Integration/Stress** |
| **Total** | | **1002** | |


---

## 7. Local E2E Review Harness (`run-e2e-review.sh`)

> **PR:** #377 | **Issue:** #372 | **Design:** `docs/DESIGN/372-e2e-harness-fixes.md`

Beyond the headless unit suite, the pipeline runs a **local E2E verification** of every implement PR before merge: an isolated worktree of the PR branch is tested end-to-end with real rendering, and the evidence is posted back to the PR. It exists because CI green alone does not prove the game *looks right and plays* — `--headless` cannot produce screenshots (dummy driver = zero pixels), so the harness drives the real display driver (brief window flash, acceptable for low-frequency review).

### Design Philosophy

- **Worktree isolation** — every run checks the PR branch out into `/tmp/wt-impl-<N>`; the main working tree is never touched (kills the checkout/stash pitfall family). The worktree is force-removed on exit via trap, *before* `gh pr merge --delete-branch` (an open worktree blocks branch deletion).
- **Real-render evidence with anti-spoof** — screenshots are captured from a live game window and asserted to be genuine frames (not flat color / not black / not frozen), so a "L3 pass" means the game actually rendered distinct, themed frames.
- **Degrade, don't crash** — every external dependency (gist upload, network, `gh`) has a graceful fallback; the evidence comment is always posted even when image embedding fails.
- **Testability injection** — `RUNNER_GODOT`, `E2E_WORKTREE_ROOT`, `E2E_BRANCH`, `E2E_GH_REPO`, `E2E_DIFF_FILES`, `E2E_PLAN_PATH` env overrides let the pipeline test suite (`tests/pipeline/test_e2e_runner.py`) exercise the full runner with a fake `godot` and fake `gh` — no network, no real engine.

### Phases (P0–P8)

| Phase | Purpose |
|-------|---------|
| P0 | Pre-flight: godot present, caffeinate held (system sleep = frozen capture), branch fetched |
| P1 | Worktree add (isolated checkout of the impl branch) |
| P2–P4 | Logic layers: L0 compile → L1 unit logic → L2 runtime scene |
| P5 | Visual layer: resolve shot plan from PR diff → real-render capture → 4-fold anti-spoof assertions |
| P6 | Evidence: build markdown comment with embedded screenshots, post to PR |
| P7 | Summary JSON + overall exit code (0 pass / 1 layer failure / 2 pre-flight) |
| P8 | Cleanup: worktree removed via EXIT trap |

### Layer Ladder

| Layer | Script | Pass Criterion |
|-------|--------|----------------|
| L0 Compile | `tests/check_compile.gd` | all `.gd` files load, 0 failures |
| L1 Logic | `tests/run_tests.gd` | `TOTAL: N passed, 0 failed` (1054 tests) |
| L2 Runtime | `tests/playthrough_test.tscn` | optional — missing file = warn-only (exit 2), not a failure |
| L3 Visual | `e2e_capture.gd` + `analyze_bmp.py` | every shot passes all 4 anti-spoof assertions |

Only a hard failure (exit 1) makes the run red; unavailable layers warn only.

### 4-Fold Anti-Spoof Assertions (`analyze_bmp.py`)

| # | Assertion | Default Threshold | Catches |
|:-:|-----------|-------------------|---------|
| 1 | Non-black | black pixel ratio ≤ 50% | black/blank frame |
| 2 | Color count | ≥ 3 distinct color buckets | flat-color frame (scene didn't load) |
| 3 | Theme color | theme hex present within tol 32 | wrong scene / missing UI |
| 4 | Frame diff (dual-channel OR) | mean Δluma ≥ 5.0 **OR** changed-pixel ratio ≥ 0.5% | frozen frame |

**Frozen heuristic is dual-channel (#372):** the old single metric (mean Δluma) is diluted by neon dark backgrounds — large near-black areas keep the average tiny while a significant share of pixels genuinely change (#371 real frames: Δluma = 0.5 < 5.0 but 1.115% of pixels changed). The ratio channel counts sampled pixels whose per-pixel |Δluma| exceeds `--pixel-delta` (default 20) and passes when `changed / total ≥ --diff-ratio` (runner uses `0.005`, i.e. 0.5% — 2× margin over the observed 1.1%). The runner passes both channels (`--min-delta 5.0 --diff-ratio 0.005`); omitting `--diff-ratio` restores pure mean-Δluma behavior (backward compatible).

### Shot Plan & Deadlines (`e2e_shots.json` + `e2e_capture.gd`)

The game authors its own shot plan (`mini-pong/e2e_shots.json`); the runner resolves groups whose `match` regexes hit PR diff files, producing a flat plan:

```json
{ "name": "03_gameover", "state": "GAME_OVER", "settle_frames": 10, "deadline_s": 300 }
```

| Constant | Default | Meaning |
|----------|---------|---------|
| `max_wall_seconds` | 120 | global per-run wall clock |
| `deadline_s` (per shot) | absent → global | that shot's own deadline; loop runs until the **max pending deadline**, so a long-deadline shot extends the run |

Rationale: a 5-point AI-vs-AI match can exceed 120 s, so `03_gameover` gets its own 300 s deadline while `01_title`/`02_midgame` fall back to the global. Missing field = global (backward compatible); the shot's own deadline is also enforced inside settle-waiting, so an unready shot fails fast instead of hanging the run.

### P6 Evidence Channel (gist raw URL)

GitHub REST has **no comment-attachment endpoint** (verified against the official OpenAPI). Screenshots are uploaded via the only official REST channel — `gh gist create --public` — and embedded as `![name](https://gist.githubusercontent.com/<user>/<gist_id>/raw/<file>)`. Failure modes degrade gracefully:

| Failure | Behavior |
|---------|----------|
| gist creation/URL parse fails | fall back to local-path text (`_upload failed — see /tmp/e2e-<N>/shots/...`), comment still posts |
| token lacks `gist` scope | same fallback (known env limitation, follow-up: web-upload endpoint with real token or gist base64) |

### Failure Taxonomy (design-agreed)

| Class | Meaning | Path |
|-------|---------|------|
| A | harness/infra broke (black shots, timeout, worktree) | fix harness or degrade L3; no self-correct cycle |
| B | pre-existing (reproduces on main) | mark `status/blocked`, fix via separate issue |
| C | spec/aesthetic (runs but wrong look) | REQUEST_CHANGES + evidence → human verdict |
| D | code defect (crash/physics/loop) | local convergence loop, max 2 rounds, then escalate |

Pipeline coverage: 118 cases in `tests/pipeline/` (baseline 104 + 14 for #372) — runner end-to-end with fake godot/gh, analyzer dual-channel regressions, deadline passthrough lock.

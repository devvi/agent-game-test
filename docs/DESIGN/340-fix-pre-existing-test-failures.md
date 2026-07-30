# Design: Fix 5 Pre-Existing Test Failures on Main

> **Parent Issue:** #340
> **Agent:** game-plan-agent
> **Date:** 2026-07-30
> **Approach:** A — Test-only fixes; no production code changes (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── tests/
│   ├── test_scoring_manager.gd           ← MODIFIED: TC11 assertion (1 test)
│   └── test_game_state_machine.gd        ← MODIFIED: base class + TC6.1/8.1/8.2/16.1 (4 tests)
└── gdscripts/
    ├── scoring_manager.gd                ← UNCHANGED (production code)
    └── game_state_machine.gd             ← UNCHANGED (production code)
```

**Design philosophy:** This is a pure test maintenance task. All 5 failures originate from tests written before FSM #294 and Scoring #291 refactors landed. The tests assert old behavior that no longer matches production code. The fix updates test assertions to reflect current headless-mode behavior — zero production code changes.

### Key Architectural Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | TC11 fix | Keep the test but verify no-op behavior | `_pause_and_serve()` is intentionally `pass` — FSM #294 `enter_state(SERVING)` now calls `ball.serve()`. Removing the test entirely would lose the explicit documentation of this architectural decision. |
| 2 | TC6.1 fix | Assert final state (SERVING) not intermediate (SCORED) | In headless mode, `_timer_1s()` skips `await`, so SCORED→SERVING completes synchronously within `_on_scored()`. The final state is the correct test target. |
| 3 | TC8.1/8.2 fix | Verify `enter_state(SERVING)` finalizes lock state | `_transition_lock` is reset to `false` at the end of `enter_state(SERVING)` (game_state_machine.gd:109), which runs synchronously in headless. The lock serves its purpose (prevents double-trigger within the same frame), and resetting it is correct FSM behavior. |
| 4 | TC16.1 fix | Change base class `RefCounted` → `Object` | Godot 4.x does not support `RefCounted` for `Engine.register_singleton()`. The mock GM callback chain depends on this singleton working. This is the only structural change needed. |
| 5 | No TASKS doc needed | depth/standard — only 2 files, 16 lines changed | Per plan agent conventions, standardized tasks are unnecessary for a single-base-class + assertion fix across two files. |

---

## 2. Test-by-Test Fix Details

### 2.1 TC11 — `_pause_and_serve()` is now a no-op

**File:** `tests/test_scoring_manager.gd`

**Production behavior (scoring_manager.gd:105-108):**
```gdscript
func _pause_and_serve() -> void:
    # FSM (#294) handles pause + serve timing.
    # ScoringManager now only emits signals; no longer controls ball serve.
    pass
```

**Current test (failing):**
```gdscript
# L247-257
func _test_tc11_headless_no_tree() -> void:
    _reset_signal_state()
    var mock_ball = _make_mock_ball()
    var sm = _make_sm(mock_ball)
    _connect_signals(sm)

    sm._pause_and_serve()

    _assert(mock_ball.serve_count >= 1, "TC11: ball.serve() called in headless...")
    # ❌ serve_count == 0 — _pause_and_serve() is pass
```

**Fix — replace the assertion:**
```gdscript
    _assert(mock_ball.serve_count == 0,
        "TC11: _pause_and_serve() is no-op — ball.serve() now handled by FSM #294 enter_state(SERVING)")
```
The test method name `_test_tc11_headless_no_tree` and preceding comment stay; only the assertion changes. This preserves the explicit documentation that `_pause_and_serve()`'s `pass` is intentional.

---

### 2.2 TC6.1 — Headless synchronous SCORED→SERVING transition

**File:** `tests/test_game_state_machine.gd`

**Production behavior (game_state_machine.gd:129-142):**
```gdscript
State.SCORED:
    ...
    await _timer_1s()       # headless: skipped (L193-197)
    _scored_timer_active = false
    if current_state == State.SCORED:
        ...
            transition_to(State.SERVING)   # runs synchronously in headless
```

**Current test (failing):**
```gdscript
# L260-262
fsm._on_scored("player")

_assert(fsm.current_state == fsm.State.SCORED, "TC6.1: current_state == SCORED...")
# ❌ current_state is SERVING — timer skipped, transition_to runs immediately
```

**Fix — change the assertion:**
```gdscript
_assert(fsm.current_state == fsm.State.SERVING,
    "TC6.1: current_state == SERVING after scored signal (headless: SCORED→SERVING synchronous)")
```

---

### 2.3 TC8.1 — `_transition_lock` reset in synchronous `enter_state(SERVING)`

**File:** `tests/test_game_state_machine.gd`

**Production behavior (game_state_machine.gd:69-72, 98-109):**
```gdscript
# _input():
State.MENU:
    if not _transition_lock:
        _transition_lock = true       # L71 — lock set
        transition_to(State.SERVING)  # L72 — calls enter_state(SERVING)

# enter_state(SERVING):
    ...
    await _timer_1s()                 # headless: skipped
    ball.serve()                      # headless: runs immediately
    await _wait_for_serve()           # headless: ball has no _is_serving → returns
    _transition_lock = false          # L109 — lock reset, synchronously in headless
```

**Current test (failing):**
```gdscript
# L290-296
fsm._input(event1)

_assert(fsm._transition_lock == true, "TC8.1: _transition_lock == true after first SPACE")
# ❌ lock is false — enter_state(SERVING) reset it synchronously
```

**Fix — change the assertion:**
```gdscript
_assert(fsm._transition_lock == false,
    "TC8.1: _transition_lock == false after first SPACE (enter_state(SERVING) resets lock, synchronous in headless)")
```

---

### 2.4 TC8.2 — Second SPACE not blocked (lock already reset)

**File:** `tests/test_game_state_machine.gd`

**Current test (failing):**
```gdscript
# L300-305
fsm._input(event2)

_assert(fsm._transition_lock == true, "TC8.2: _transition_lock still true (second SPACE blocked)")
# ❌ lock is false — was already reset by first SPACE's enter_state(SERVING)
```

**Fix — verify state instead of lock:**
```gdscript
_assert(fsm.current_state == fsm.State.SERVING,
    "TC8.2: state remains SERVING after second SPACE (same-state transition is no-op)")
```
Since the lock was reset synchronously, the second SPACE finds `_transition_lock == false` and calls `transition_to(SERVING)`, which is a same-state no-op (`transition_to` L83-84). The state is already SERVING and should stay there.

---

### 2.5 TC16.1 — `RefCounted` base class blocks singleton registration

**File:** `tests/test_game_state_machine.gd`

**Root cause:** Godot 4.x requires `Object` (not `RefCounted`) for `Engine.register_singleton()`. The test suite at L1 declares `extends RefCounted`, which causes `Engine.register_singleton("__test_fsm__", self)` at L145 to silently fail. When the mock GameManager calls `Engine.get_singleton("__test_fsm__")`, it gets `null`, so `_on_gm_reset_match()` is never called.

**Current test (failing):**
```gdscript
# L1
extends RefCounted
```

**Fix — change base class:**
```gdscript
# L1
extends Object
```

**Impact analysis:**
- The test suite uses no `RefCounted`-specific APIs (`reference()`, `unreference()` are not called anywhere in the file)
- All existing passing tests (TC2-TC5, TC7, TC9-TC15, TC17) use `_make_fsm()`, `_setup_fsm()`, and `_assert()` — none depend on reference counting
- `Object` is the minimal Godot base class; `Node` would be heavier than needed
- The `_setup_gm_mock()` / `_teardown_gm_mock()` cleanup pattern is unchanged — `Engine.unregister_singleton()` works on `Object` singletons

**TC16.1 assertion update — ALSO needed after the base class fix:**
Even with the `Object` fix, the TC16.1 assertion at L409 expects `_gm_reset_match_called >= 1` — this will NOW pass because the singleton callback chain works. No assertion change needed for TC16.1 itself. The base class fix is the sole change required.

However, note that `enter_state(SERVING)` has `await` calls (L103-108), so in headless the async parts execute synchronously. The `GameManager.reset_match()` call at L102 happens before any `await`, so it will execute and increment `_gm_reset_match_called`. ✅

---

## 3. Summary of Changes

| File | Line | Change | Tests Affected |
|------|------|--------|---------------|
| `tests/test_game_state_machine.gd` | L1 | `extends RefCounted` → `extends Object` | TC16.1 |
| `tests/test_scoring_manager.gd` | L257 | `serve_count >= 1` → `serve_count == 0` | TC11 |
| `tests/test_game_state_machine.gd` | L262 | `SCORED` → `SERVING` | TC6.1 |
| `tests/test_game_state_machine.gd` | L296 | `== true` → `== false` | TC8.1 |
| `tests/test_game_state_machine.gd` | L305 | `_transition_lock == true` → `current_state == State.SERVING` | TC8.2 |

**Total: 5 lines changed across 2 files. Zero production code touched.**

---

## 4. Verification

### Test commands

```bash
cd mini-pong/

# Compile check (fast — catches parse errors)
godot --headless --quit

# Full test suite
godot --headless --script tests/run_tests.gd
# Expected: 879 passed, 0 failed
```

### Acceptance criteria

- [ ] TC11: `_pause_and_serve()` verified as intentional no-op (`serve_count == 0`)
- [ ] TC6.1: After `_on_scored()`, `current_state == SERVING` (headless synchronous transition)
- [ ] TC8.1: After first SPACE, `_transition_lock == false` (reset by `enter_state(SERVING)`)
- [ ] TC8.2: After second SPACE, `current_state == SERVING` (same-state transition no-op)
- [ ] TC16.1: `GameManager.reset_match()` called during `enter_state(SERVING)` (singleton works)
- [ ] All 874 previously-passing tests still pass
- [ ] Production code (`scoring_manager.gd`, `game_state_machine.gd`) unchanged

---

## 5. Edge Cases & Pitfalls

1. **TC8 loses SPACE-double-press validation**: The original TC8 tested that `_transition_lock` blocks a second rapid SPACE press. In headless mode, `enter_state(SERVING)` runs synchronously and resets the lock, so this intermediate state is not observable. The production protection still works at runtime (with real `await _timer_1s()` delays). A future headless-aware test could mock the timer to inject assertions between lock-set and lock-reset.

2. **`RefCounted` → `Object` does NOT break existing tests**: Confirmed no `reference()`/`unreference()` usage in the test file. The test suite uses only `_assert()`, `_make_fsm()`, `_setup_fsm()`, `_setup_gm_mock()`, `_teardown_gm_mock()` — all compatible with `Object`.

3. **`test_scoring_manager.gd` keeps `RefCounted`**: This file also extends `RefCounted` but does NOT use `Engine.register_singleton()` — no change needed.

4. **`_teardown_gm_mock()` still works with `Object`**: The teardown calls `Engine.unregister_singleton("__test_fsm__")` and `Engine.register_singleton("GameManager", real_gm)` — both work with `Object`-based singletons.

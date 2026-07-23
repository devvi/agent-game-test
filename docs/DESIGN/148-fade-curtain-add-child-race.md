# Design: #148 — SceneManager Fade Curtain — Fix add_child race condition (Bug)

> Parent Issue: #148
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Problem

The `fade_in()` method on the destination scene's `SceneManager` never plays its animation. The root cause is the `transition_in_progress` guard at line 146:

```gdscript
func fade_in(fade_duration: float = 0.5) -> void:
    if not transition_in_progress:
        return  # ← Always returns on fresh SceneManager instance
```

When `change_scene_to_file()` replaces the scene tree, the new scene gets a brand-new `SceneManager` instance. That instance's `transition_in_progress` is always `false` (the default), so every call to `fade_in()` from `SceneBase._ready()` is silently discarded. The visual result: player sees black → immediate scene cut with no fade-in.

### Solution (Approach C — via PRD recommendation)

Propagate the `transition_in_progress` flag across scene changes by storing it in the `GameManager` autoload — the same autoload already used by `_persist_dialogue_state()` at line 134-141.

**Three changes:**

| # | File | What | Why |
|---|------|------|-----|
| 1 | `scene_manager.gd` `trigger_scene_change()` | Set `GameManager.transition_in_progress = true` before calling `change_scene_to_file()` | Passes the flag to the next scene across tree replacement |
| 2 | `scene_manager.gd` `_ready()` | Read `GameManager.transition_in_progress` into local `transition_in_progress` | The new instance picks up the flag before `fade_in()` is called |
| 3 | `scene_manager.gd` `fade_in()` | After animation completes, set `GameManager.transition_in_progress = false` | Clears the flag so subsequent `fade_in()` calls on non-transition paths are guarded correctly |

No changes to `GameManager.gd` are required — it already supports dynamic properties via GDScript's dynamic dispatch (`set("transition_in_progress", value)` / `get("transition_in_progress")`) since it's a plain `Node` with no declared variable named `transition_in_progress`, which means GDScript will create a dynamic property on first write.

### Data Flow (Fixed)

```
Main scene:
  trigger_scene_change(target)
    → transition_in_progress = true         [local instance]
    → GameManager.transition_in_progress = true [NEW — persists across tree swap]
    → _fade_anim.play("fade_out")
    → await animation_finished
    → change_scene_to_file(target)           [scene tree replaced]

New scene:
  SceneManager._ready()
    → _setup_fade_curtain()                   [creates/finds FadeCurtain]
    → transition_in_progress = GameManager.transition_in_progress  [NEW — reads flag]
  SceneBase._ready()
    → scene_manager.fade_in()
      → if not transition_in_progress: return  [NOW true → proceeds]
      → _fade_anim.play("fade_in")
      → await animation_finished
      → transition_in_progress = false
      → GameManager.transition_in_progress = false  [NEW — clears flag]
      → transition_completed.emit()
```

---

## 2. File-by-File Analysis

### 2.1 `gdscripts/scene_manager.gd` — SceneManager (directly affected)

**Current state:** 151 lines. Manages fade transitions for scene changes. Has a `transition_in_progress` bool (line 11), `_setup_fade_curtain()` (line 23), `_create_fade_curtain()` (line 36), `_connect_to_dialogue()` (line 76), `_on_choice_made()` (line 87), `trigger_scene_change()` (line 105), `_persist_dialogue_state()` (line 134), and `fade_in()` (line 145).

**Changes needed:**

**Change A — `trigger_scene_change()` (after line 108, after `transition_in_progress = true`):**
```gdscript
# Propagate transition flag across scene tree replacement
var gm := get_node_or_null("/root/GameManager")
if gm:
    gm.set("transition_in_progress", true)
```

**Change B — `_ready()` (after line 19, after `_setup_fade_curtain()`):**
```gdscript
# Pick up transition flag from GameManager (set by previous scene)
var gm := get_node_or_null("/root/GameManager")
if gm and gm.get("transition_in_progress", false):
    transition_in_progress = gm.transition_in_progress
```

**Change C — `fade_in()` (after line 150, after `transition_in_progress = false`):**
```gdscript
# Clear the autoload flag
var gm := get_node_or_null("/root/GameManager")
if gm:
    gm.set("transition_in_progress", false)
```

**Error handling:** All GameManager accesses use `get_node_or_null()` — if GameManager is absent (testing), the code paths degrade gracefully: no flag propagation (fade-in skips), no flag clearing (stale but harmless since GameManager is present in production).

### 2.2 `gdscripts/game_manager.gd` — GameManager (indirectly affected)

**Current state:** 148 lines. Autoload registered at `/root/GameManager`. Already stores `choices_history`, `player_position`, `player_rotation`, `scene_visited`, etc. across scene transitions.

**No changes needed.** GDScript allows writing to undeclared properties on `Node`-derived classes — `gm.set("transition_in_progress", value)` works at runtime without any declaration in `game_manager.gd`. This is the same pattern already used at line 141 (`gm.set("choices_history", ...)`) where `choices_history` is a declared variable (line 17), but the property-writing pattern is identical.

### 2.3 `gdscripts/scene_base.gd` — SceneBase (indirectly affected)

**Current state:** 139 lines. Calls `scene_manager.fade_in()` in `_ready()` at line 18-19. No changes needed — the fix is transparent to SceneBase. Its `_ready()` already calls `fade_in()` and the guard in SceneManager now correctly decides whether to play the animation.

### 2.4 Scene scripts extending SceneBase (indirectly affected)

| Script | Scene | Pre-existing FadeCurtain? |
|--------|-------|--------------------------|
| `office.gd` | `office.tscn` | No (programmatic) |
| `lobby.gd` | `lobby.tscn` | No (programmatic) |
| `subway_station.gd` | `subway_station.tscn` | No (programmatic) |
| `street.gd` | `street.tscn` | Yes (TSCN-defined) |
| `bridge.gd` | `bridge.tscn` | Yes (TSCN-defined) |
| `underpass.gd` | `underpass.tscn` | Yes (TSCN-defined) |
| `convenience_store.gd` | `convenience_store.tscn` | Yes (TSCN-defined) |
| `main.gd` | `main.tscn` | No (but no SceneBase extension) |

No changes to any scene script or TSCN file. All 8 scenes benefit transparently.

---

## 3. Component Interaction

### Sequence Diagram

```
DialoguePanel  SceneManager(old)  GameManager  AnimationPlayer  SceneTree  SceneManager(new)  SceneBase
    │                │                │              │              │            │                │
    │ choice_made    │                │              │              │            │                │
    │───────────────►│                │              │              │            │                │
    │                │  transition_in_progress=true  │              │            │                │
    │                │───────────────►               │              │            │                │
    │                │  gm.set("transition_in_progress",true)       │            │                │
    │                │───────────────►               │              │            │                │
    │                │  play("fade_out")             │              │            │                │
    │                │──────────────────────────────►│              │            │                │
    │                │  await animation_finished      │              │            │                │
    │                │◄──────────────────────────────│              │            │                │
    │                │  change_scene_to_file()        │              │            │                │
    │                │─────────────────────────────────────────────►│            │                │
    │                │                                │              │            │                │
    │                │  [OLD SceneManager destroyed]   │              │  [tree replaced]           │
    │                │                                │              │            │                │
    │                │                                │              │   _ready() │                │
    │                │                                │              │◄───────────│                │
    │                │                                │              │   _setup_fade_curtain()     │
    │                │                                │              │────────────►                │
    │                │                                │              │   read gm.transition_in_progress=true  │
    │                │                                │◄─────────────│            │                │
    │                │                                │              │   transition_in_progress=true│
    │                │                                │              │            │                │
    │                │                                │              │            │   _ready()      │
    │                │                                │              │            │◄───────────────│
    │                │                                │              │            │  fade_in()      │
    │                │                                │              │            │────────────────►│
    │                │                                │              │            │  play("fade_in")│
    │                │                                │              │            │────────────────►│
    │                │                                │              │            │  await done     │
    │                │                                │              │            │◄────────────────│
    │                │                                │              │            │  transition_in_progress=false  │
    │                │                                │              │            │  gm.set("transition_in_progress",false)  │
    │                │                                │◄─────────────│            │                │
```

### Autoload Dependency Graph

```
GameManager (autoload)  ←──  SceneManager (reads/writes transition_in_progress)
    ↑
    └── SceneBase (reads choices_history — unchanged)
    └── DialoguePanel (reads choices_history — unchanged)
```

`GameManager` already has write access from `SceneManager` via `_persist_dialogue_state()`. Adding read/write of `transition_in_progress` creates no new coupling beyond what already exists.

---

## 4. Verification Criteria

Each criterion below has an embedded test case description (format: **TC-XXX**).

### Normal Path

**TC-001 — Dialogue-triggered scene transition plays fade-in on destination**
1. Start game from `main.tscn`.
2. Navigate to a scene with a dialogue choice that has `"scene"` metadata (e.g., `office` → `street`).
3. Select the scene-transition choice.
4. **Verify:** Fade-out plays (screen → black). New scene loads. Fade-in plays (black → scene). `transition_in_progress` is `false` after fade-in completes (check via breakpoint or print).
5. **GDScript test (headless):** Mock a `SceneManager` with a fake `GameManager` autoload. Call `trigger_scene_change("res://scenes/street/street.tscn")`, then simulate scene tree replacement and call `_ready()` + `fade_in()` on a new instance. Assert that `fade_in()` plays the animation (i.e., does not return early).

**TC-002 — Game launch (main → office) skips fade-in correctly**
1. Launch game (or simulate `change_scene_to_file("res://scenes/office/office.tscn")` from `main.tscn`).
2. **Verify:** No fade-in animation plays. Scene appears immediately. `transition_in_progress` is `false` throughout (no stale state).
3. **GDScript test (headless):** Create fresh `SceneManager` instance with no prior `GameManager.transition_in_progress`. Call `fade_in()`. Assert that `fade_in()` returns immediately (guard triggers correctly).

**TC-003 — GameManager flag is set before change_scene_to_file**
1. Inspect `trigger_scene_change()` code — confirm `gm.set("transition_in_progress", true)` appears **before** `change_scene_to_file()` (not after, where it would be too late).
2. **Code review:** Static assertion — line order check.

### Edge Cases

**TC-004 — Double scene trigger (rapid clicks)**
1. Start a scene transition via dialogue choice.
2. Rapidly click another scene-transition choice during fade-out.
3. **Verify:** Second `trigger_scene_change()` returns immediately (line 106-107: `if transition_in_progress: return`). Only the first transition completes. No duplicate `change_scene_to_file()` calls.
4. **GDScript test (headless):** Call `trigger_scene_change()` twice in succession. Assert that the animation player is only started once (check `play()` call count via mock).

**TC-005 — Destination with no pre-existing FadeCurtain (office, lobby, subway_station)**
1. Trigger scene change to `office.tscn`, `lobby.tscn`, or `subway_station.tscn`.
2. **Verify:** `_setup_fade_curtain()` enters the `else` branch (line 30-32). `call_deferred(add_child(...))` is invoked. `_fade_anim` is set synchronously at line 33. Fade-in plays correctly on the programmatic curtain.
3. **GDScript test (headless):** Create `SceneManager` in a scene without a pre-existing `FadeCurtain` node. Call `_setup_fade_curtain()`. Verify `_fade_curtain` is not null and `_fade_anim` is not null.

**TC-006 — Destination with pre-existing FadeCurtain (street, bridge, underpass, convenience_store)**
1. Trigger scene change to `street.tscn`, `bridge.tscn`, `underpass.tscn`, or `convenience_store.tscn`.
2. **Verify:** `_setup_fade_curtain()` enters the `if` branch (line 28-29: `has_node("FadeCurtain")`). Existing TSCN node is reused. Fade-in plays correctly.
3. **GDScript test (headless):** Create `SceneManager` in a scene with a pre-existing `FadeCurtain` node (mocked). Call `_setup_fade_curtain()`. Verify `_fade_curtain` references the existing node (not a new one).

**TC-007 — Failed scene change (change_scene_to_file returns error)**
1. Call `trigger_scene_change("res://nonexistent_scene.tscn")`.
2. **Verify:** Line 125-128 catches error `!= OK`. `transition_in_progress` resets to `false`. `GameManager.transition_in_progress` is NOT set to true (we only set it before the call, but if it was set, it stays `true` — edge: we should also clear it on error path).
3. **Design note:** The `gm.set("transition_in_progress", true)` in `trigger_scene_change()` is called before the `change_scene_to_file()` call. If the scene change fails, we should clear both the local flag AND the autoload flag. The existing error handler (line 127: `transition_in_progress = false`) should also clear `GameManager.transition_in_progress`.
4. **GDScript test (headless):** Pass an invalid path to `trigger_scene_change()`. Assert that both `transition_in_progress` and `GameManager.transition_in_progress` are `false` after the error return.

**TC-008 — GameManager unavailable (rare, e.g., headless test without autoloads)**
1. Simulate `SceneManager` in an environment where `/root/GameManager` does not exist.
2. **Verify:** `get_node_or_null("/root/GameManager")` returns `null`. All three access points (`trigger_scene_change()`, `_ready()`, `fade_in()`) skip gracefully. `transition_in_progress` defaults to `false`. Fade-in returns immediately (graceful degradation).
3. **GDScript test (headless):** Create `SceneManager` in an isolated tree with no `GameManager` autoload. Call `trigger_scene_change()`. Assert no errors, no crashes.

**TC-009 — Multi-scene traversal (A → B → C)**
1. Trigger scene change from A → B. Wait for fade-in to complete.
2. Immediately trigger scene change from B → C.
3. **Verify:** First transition completes fully. Second transition starts fresh. `GameManager.transition_in_progress` is overwritten per-transition (correct — only the most recent transition matters). No stale flag from transition A → B leaks into B → C.
4. **Manual test:** Walk through `office → street → bridge` in the game. Each transition should have a smooth fade-out + fade-in.

### Failure Paths

**TC-010 — fade_in() called without prior transition (defensive)**
1. Call `fade_in()` on a SceneManager that was never preceded by `trigger_scene_change()`.
2. **Verify:** `transition_in_progress` is `false` (either local default or GameManager default). Guard triggers. `fade_in()` returns immediately. No spurious fade-in animation plays.
3. **GDScript test (headless):** Create fresh SceneManager. Call `fade_in()`. Assert no animation is played.

---

## 5. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| GameManager dynamic property fails silently | Very Low | Low | GDScript dynamic property dispatch on `Node` subclasses is well-tested; existing `choices_history` (declared var) uses `set()` pattern but dynamic props work identically |
| `_ready()` runs `_setup_fade_curtain()` before reading GameManager flag | Low | Low — flag is read after curtain setup, so `_fade_anim` exists | Sequence is: `_ready()` → `_setup_fade_curtain()` → read GM flag → `fade_in()` from SceneBase. `_fade_anim` is always set before `fade_in()` is called. |
| `change_scene_to_file()` fails — stale flag remains in GameManager | Medium | Medium | Added mitigation: clear `GameManager.transition_in_progress` in the error handler (see TC-007) |
| Multiple SceneManager instances in same tree (should not exist by design) | Low | Low | Each scene has exactly one `SceneManager` child (attached by scene convention). No code path creates additional instances. |
| Timing: `call_deferred` add_child vs synchronous fade_in | Very Low | Low | `_fade_anim` is set synchronously at line 33 (before `call_deferred` returns). Even though the `ColorRect` isn't in the tree yet, the AnimationPlayer reference is valid and animations play correctly on scheduled nodes. |

### Risk Summary

**Overall risk: Very Low.** The fix is 3 small additions (≈6 lines total) to `scene_manager.gd` with no architectural changes, no new dependencies, no TSCN modifications, and the same error-handling pattern already established in the codebase.

---

## 6. Migration Path

### Deploy Plan

1. **Implement** the 3 changes in `scene_manager.gd` (total ≈6 lines of new code).
2. **Verify manually:** Run the game, trigger a scene transition via dialogue. Confirm fade-in plays on destination.
3. **Verify all 8 scenes:** At minimum, test office→street (both with and without pre-existing FadeCurtain) and street→bridge (both with pre-existing FadeCurtain).
4. **Merge** via squash-merge to main.

### Rollback

Revert the commit. The previous state (commit `3a7242c`, PR #141, Issue #138) works correctly for the `add_child` race condition — only fade-in is missing. Rollback restores the pre-fix behavior.

### No TASKS doc required

This is a bug fix with depth/light. The 3 changes are small and co-located in a single file. No additional task breakdown is needed.

---

## 7. Recurrence Prevention

### How Did This Bug Happen?

1. **Issue #138** (the original `add_child` race condition fix) added `call_deferred()` to `add_child()`, but did not consider the downstream effect on the `transition_in_progress` guard across scene tree replacement.
2. The `transition_in_progress` guard was designed as a per-instance variable in a system where `SceneManager` instances do **not** survive `change_scene_to_file()`, making the guard always fail on the destination scene.
3. No automated test caught the missing fade-in because the issue manifests as a **visual gap** (no UI error, no crash, no console warning).

### Preventive Measures

| Measure | When | Who |
|---------|------|-----|
| **Add GDScript headless test** for `fade_in()` guard + GameManager flag propagation | This PR | plan-agent |
| **Code review checklist item for transition guards:** Verify that any state guard that survives `change_scene_to_file()` is propagated via autoload, not an instance variable | Going forward | All reviewers |
| **Visual regression script:** Add a simple `print()` statement after `fade_in()` animation completes (or emits `transition_completed`) so CI headless tests can assert the event fires | This PR (implement phase) | implement-agent |
| **Document in REFERENCE:** Scene transition flow diagram showing the complete fade-out → tree replacement → fade-in lifecycle, with the autoload propagation path | This PR | plan-agent |

### Second-Order Effects

With this fix, the full fade-out + fade-in lifecycle works correctly. Future changes to the transition system (e.g., loading screens, cross-fades, preload-on-fade-out) should extend the `GameManager` property pattern rather than adding new mechanisms.

**Watch for:** If `GameManager` ever refactors to a static class or `RefCounted` (which does not support dynamic property dispatch), the `set()` calls will need to reference declared properties. This is a low-risk concern — `GameManager` is a stable autoload and unlikely to change its type.

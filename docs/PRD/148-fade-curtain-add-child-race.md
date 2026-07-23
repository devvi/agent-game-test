# Research: SceneManager Fade Curtain — Fix add_child race condition

> Parent Issue: #148
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The `add_child` race condition in `scene_manager.gd:32` was previously addressed in commit `3a7242c` (PR #141 for Issue #138) by replacing `scene_root.add_child(_fade_curtain)` with `scene_root.add_child.call_deferred(_fade_curtain)`. The "Parent node is busy setting up children" error no longer appears on game launch.

However, two issues remain:

1. **`fade_in()` never plays after scene transitions** — The `transition_in_progress` guard in `fade_in()` (line 146) checks a variable that is always `false` on the new scene's `SceneManager` instance. When `change_scene_to_file()` replaces the entire scene tree, the new `SceneManager` starts fresh with `transition_in_progress = false`. `SceneBase._ready()` calls `scene_manager.fade_in()`, but the guard returns immediately, so no fade-in animation ever plays on the destination scene.

2. **3 scenes have no pre-existing FadeCurtain** — After the `#138` fix, `office.tscn` no longer has a hardcoded `FadeCurtain`. Additionally, `lobby.tscn` and `subway_station.tscn` never had one. These 3 scenes rely entirely on the programmatic creation path. The `call_deferred()` approach works correctly for avoiding the add_child race, but the resulting `ColorRect.modulate` starts at `Color(0,0,0,0)` (transparent), matching the TSCN-defined curtains.

### Expected Behavior

- Fade-out → scene-change → fade-in should produce a smooth visual transition: old scene → black → new scene fades in.
- No errors on game launch or during scene transitions.
- All 8 scenes with `SceneManager` work correctly regardless of whether they have a pre-existing `FadeCurtain`.

### User Scenarios

- **Scenario A — Dialogue-triggered scene transition:** Player selects a choice that triggers `trigger_scene_change()`. Fade-out plays. New scene loads but has no fade-in, causing an abrupt cut from black to scene.
- **Scenario B — Game launch:** `main.tscn` loads, immediately delegates to `office.tscn` via `call_deferred`. Office loads with no FadeCurtain pre-existing. Fade-in is not expected here (no transition in progress), so the guard is correct.
- **Scenario C — Multi-scene traversal:** Player moves between scenes with and without pre-existing `FadeCurtain` (e.g., `office → street → bridge → subway_station`). Each transition should have a consistent fade-in.
- **Frequency:** Every scene transition (relevant to all 7 non-main scenes).

---

## 2. Root Cause Analysis (Bug)

### Why Does Current Behavior Exist?

**For the add_child race (already fixed in 3a7242c):** `_setup_fade_curtain()` was called from `_ready()` (line 19), and `add_child(_fade_curtain)` was called directly. Godot 4's scene tree prevents `add_child()` while a node is in the middle of its `_ready()` callbacks. Fixed with `call_deferred()`.

**For the fade-in never playing (`transition_in_progress` guard):** The `fade_in()` function has a guard `if not transition_in_progress: return` (line 146-147). This guard was designed to prevent spurious fade-ins when `fade_in()` is called without a prior `trigger_scene_change()`. However, when a scene transition occurs, the old scene's `SceneManager` sets `transition_in_progress = true`, but the new scene gets a **fresh** `SceneManager` instance (via `change_scene_to_file()`). The fresh instance has `transition_in_progress = false`, so the guard always prevents fade-in on the target scene.

**For scenes without pre-existing FadeCurtain:** The `#138` fix removed the hardcoded `FadeCurtain` from `office.tscn` (B4). `lobby.tscn` and `subway_station.tscn` were created without one. The programmatic creation path (`_create_fade_curtain()`) works correctly, but these scenes are entirely dependent on the call_deferred path. The `_fade_anim` reference is captured synchronously (line 33, after `_create_fade_curtain` adds AnimationPlayer as a child), so `fade_in()` can still access `_fade_anim`.

### Why Change Now?

- The visual transition between scenes is broken — no fade-in plays on the destination scene.
- The `transition_in_progress` guard was never updated to account for the fresh-SceneManager-instance behavior after `change_scene_to_file()`.
- Acceptance criterion "#2: Fade curtain appears correctly when scene transitions trigger" is not fully met.

### Previous Constraints

- `change_scene_to_file()` replaces the entire scene tree — no state can be carried across in `SceneManager` instance variables.
- The `call_deferred()` pattern is correct and must be preserved.
- The pre-existing `FadeCurtain` TSCN nodes in `bridge.tscn`, `street.tscn`, `underpass.tscn`, and `convenience_store.tscn` work correctly and should not be changed.

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/scene_manager.gd` | SceneManager | `fade_in()` guard logic; possible `transition_in_progress` propagation to new scene |
| `gdscripts/scene_base.gd` | SceneBase | Call timing of `fade_in()` in `_ready()` |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/office.gd` | OfficeScene | Extends SceneBase; calls `_ready()` → `fade_in()` |
| `gdscripts/lobby.gd` | LobbyScene | Same pattern as office (no pre-existing FadeCurtain) |
| `gdscripts/subway_station.gd` | SubwayStation | Same pattern as office (no pre-existing FadeCurtain) |
| `scenes/street/street.tscn` | Street scene | Pre-existing FadeCurtain TSCN node (used directly, no call_deferred) |
| `scenes/bridge/bridge.tscn` | Bridge scene | Pre-existing FadeCurtain TSCN node |
| `scenes/underpass/underpass.tscn` | Underpass scene | Pre-existing FadeCurtain TSCN node |
| `scenes/store/convenience_store.tscn` | Store scene | Pre-existing FadeCurtain TSCN node |

### Data Flow Impact

**Current flow (broken fade-in):**
```
trigger_scene_change(target)
  → transition_in_progress = true  [OLD SceneManager]
  → _fade_anim.play("fade_out")     [OLD FadeCurtain]
  → await animation_finished
  → change_scene_to_file(target)    [Scene tree replaced]
  → NEW SceneManager._ready()
    → _setup_fade_curtain()         [FadeCurtain created via call_deferred or found via has_node]
    → _fade_anim set (synchronously)
  → SceneBase._ready()
    → scene_manager.fade_in()
      → transition_in_progress = false  [NEW instance] → RETURNS EARLY
  → ✗ No fade-in animation plays
```

**Expected flow:**
```
trigger_scene_change(target)
  → transition_in_progress = true  [OLD SceneManager]
  → _fade_anim.play("fade_out")     [OLD FadeCurtain]
  → await animation_finished
  → change_scene_to_file(target)
  → NEW SceneManager._ready() with transition_in_progress = true
    → _setup_fade_curtain()
    → _fade_anim set
  → SceneBase._ready()
    → scene_manager.fade_in()
      → transition_in_progress = true
      → _fade_anim.play("fade_in")
      → await animation_finished
      → transition_in_progress = false
  → ✓ Fade-in animation plays on new scene
```

### Documents to Update
- [ ] `docs/DESIGN/` — New DESIGN doc for this fix
- [ ] `docs/REFERENCE/` — Scene transition flow docs
- [ ] `README.md`
- [ ] Other: `docs/PRD/148-fade-curtain-add-child-race.md` (this document)

---

## 4. Solution Comparison

### Approach A: Propagate `transition_in_progress` via autoload / global state

- **Description:** Store the `transition_in_progress` flag in a shared autoload (e.g., `GameManager` or a dedicated `SceneTransition` autoload) instead of on the `SceneManager` instance. The new scene's `SceneManager` reads the flag from the autoload in `_ready()`.
- **Pros:**
  - Survives scene tree replacement (autoloads persist across `change_scene_to_file()`)
  - Clean separation of transition state from per-scene state
  - Scales to additional transition types (loading screens, preloads)
- **Cons:**
  - Introduces coupling between SceneManager and an autoload
  - Requires changes in both `trigger_scene_change()` and `fade_in()`
  - Additional ceremony for a single boolean flag
- **Risk:** Low — autoload pattern is idiomatic in Godot and well-tested in this project (AudioManager, GameManager, StateSystem)
- **Effort:** 30 min

### Approach B: Remove the `transition_in_progress` guard and use signal-driven fade-in

- **Description:** Remove the `if not transition_in_progress: return` guard from `fade_in()`. Instead, emit a signal from `trigger_scene_change()` that the new scene's `SceneManager` can connect to. Since signals don't survive `change_scene_to_file()`, use the autoload approach for the signal as well (e.g., `SceneBridge` autoload that emits `transition_ongoing`).
- **Pros:**
  - More idiomatic Godot (signal-based)
  - Easier to extend (different animation types per signal)
- **Cons:**
  - Still needs an autoload (same coupling as Approach A)
  - Signal wiring in `_ready()` is fragile with call_deferred patterns
  - Over-engineered for a single boolean flag
- **Risk:** Medium — signal timing could be tricky across scene boundaries
- **Effort:** 1 hour

### Approach C: Set `transition_in_progress` before `change_scene_to_file()` and have the new scene's `_ready()` pick it up

- **Description:** Before calling `change_scene_to_file()`, store `transition_in_progress` in `GameManager` (an existing autoload). In `SceneManager._ready()`, check `GameManager.transition_in_progress` and use that to override the local instance variable. After `fade_in()` completes, clear the flag in `GameManager`.
- **Pros:**
  - Minimal change to existing code (~3-5 lines total)
  - Uses existing `GameManager` autoload (no new dependency)
  - `fade_in()` method signature stays the same
- **Cons:**
  - Couples SceneManager to GameManager (though SceneManager already accesses GameManager in `_persist_dialogue_state()`)
  - Need to ensure `GameManager` has a settable property for this flag
- **Risk:** 🟢 Low — `GameManager` already persists `choices_history` across scene changes; same pattern
- **Effort:** 30 min

### Recommendation
→ **Approach C** because: Minimal code change, uses existing `GameManager` autoload (already referenced in `_persist_dialogue_state()`), and the same pattern (setting a flag before `change_scene_to_file()`, reading it in the new scene's `_ready()`) is already established with `choices_history`. No new dependencies or architectural changes needed.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. Player triggers scene change (dialogue choice with `"scene"` metadata) → fade-out plays → scene changes → fade-in plays on new scene → `transition_in_progress` resets to false.
2. Game launch (`main.tscn` → `office.tscn`) → no transition in progress → `fade_in()` returns immediately (correct — no fade effect on first load).

### Edge Cases

1. **Double scene trigger:** Player rapidly triggers two scene changes. First `trigger_scene_change()` sets `transition_in_progress = true` and returns early for the second call. Fade-out + change + fade-in complete normally.
2. **Scene without pre-existing FadeCurtain:** `office.tscn`, `lobby.tscn`, or `subway_station.tscn` as the destination. Programmatic `FadeCurtain` created via `call_deferred()`. `_fade_anim` already captured synchronously. `fade_in()` plays correctly on the programmatic curtain.
3. **Scene with pre-existing FadeCurtain:** `street.tscn`, `bridge.tscn`, `underpass.tscn`, or `convenience_store.tscn` as the destination. TSCN-defined FadeCurtain used directly. `fade_in()` plays correctly.
4. **Failed scene change:** `change_scene_to_file()` returns an error code. `transition_in_progress` resets to false on the old scene. No stale state.
5. **Multiple rapid transitions with fast travel:** Going from scene A → B → C quickly. Each transition should be independent. The flag in GameManager is overwritten per-transition, which is correct (only the most recent transition matters).

### Failure Paths

1. **GameManager unavailable:** If `GameManager` autoload is not present (rare, only during testing), `transition_in_progress` defaults to `false`. `fade_in()` returns early (graceful degradation — scene still works, just no fade-in effect).
2. **GameManager property not writable:** If `GameManager` doesn't expose a writable `transition_in_progress` property, the set fails silently. Fall back to `transition_in_progress = false` (same graceful degradation).

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| `GameManager` autoload (`/root/GameManager`) | Stable | Low |
| `scene_manager.gd` `_persist_dialogue_state` (existing GameManager access pattern) | Stable | Low |
| Previous fix #138 (commit `3a7242c`) | Merged | None |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Visual polish / transition effects (loading screens, cross-fades) | Low |
| Preloading next scene during fade-out | Low |

### Preparation Needed
- [ ] Verify that `GameManager` autoload has a settable property for transition state (or add one)
- [ ] Verify that `SceneManager._ready()` runs before `SceneBase._ready()` (confirmed — child node `_ready()` fires before parent's `_ready()` in Godot 4)

---

## 7. Spike / Experiment (Optional — depth/deep only)

> Not required for depth/light.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The SceneManager system currently works for fade-out transitions but fails to play fade-in on destination scenes. The root cause is a `transition_in_progress` guard in `fade_in()` that checks an instance variable always set to `false` on new `SceneManager` instances after `change_scene_to_file()`.

**Key facts for the implementing agent:**
- **8 scenes** have SceneManager instances: `main`, `office`, `bridge`, `street`, `underpass`, `convenience_store`, `lobby`, `subway_station`
- **4 scenes** have hardcoded FadeCurtain in their TSCN: `bridge`, `street`, `underpass`, `convenience_store` — `has_node("FadeCurtain")` returns `true`, no `call_deferred` needed
- **3 scenes** (plus `main`) have no hardcoded FadeCurtain: `office`, `lobby`, `subway_station` — programmatic creation via `call_deferred`
- **`_fade_anim` is always set synchronously** (line 33) — even for programmatic curtains, AnimationPlayer is added to CanvasLayer before `call_deferred` is called
- **`GameManager` autoload** already stores `choices_history` across scene transitions; same pattern should be used for `transition_in_progress`

**Thing to watch out for:** The `_fade_anim.play("fade_in", ...)` call on line 148 uses speed scale `1.0` and `from_end=false`. For programmatic curtains where ColorRect starts at `modulate.a = 0` (transparent), the fade-in animation (keys: 0→Color(0,0,0,1), 0.5→Color(0,0,0,0)) would briefly flash black before fading transparent. This is correct behavior — the screen should already be black from the preceding fade-out, so the first keyframe is a no-op. Verify in testing.

# Design: Ambient Sound — Rain loop + footsteps

> Parent Issue: #157
> Agent: plan-agent
> Date: 2026-07-23

---

## 1. Architecture Overview

### Core Idea

Add movement-triggered footstep sounds to the existing PlayerController, reusing AudioManager's existing footstep API (`play_footstep()`, `get_surface_for_scene()`). The rain ambient loop is already implemented — this issue closes the remaining gap by making footsteps play when the player walks.

### Data Flow

```ascii
PlayerController._physics_process(delta)
    │
    ├── direction = WASD vector (from Input.get_vector)
    │
    ├── if direction != Vector3.ZERO and _dialogue_active == false:
    │     └── _footstep_accumulator += delta
    │     └── if _footstep_accumulator >= FOOTSTEP_INTERVAL:
    │           ├── surface = AudioManager.get_surface_for_scene(scene_id)
    │           ├── AudioManager.play_footstep(surface)
    │           └── _footstep_accumulator = 0.0
    │
    └── if direction == Vector3.ZERO:
          └── _footstep_accumulator = 0.0   (reset on stop)

AudioManager (unchanged)
    ├── play_footstep(surface_type) — cooldown (0.3s), stream selection, playback
    ├── get_surface_for_scene(scene_id) → mapping: 7 scenes → 3 surfaces
    └── FOOTSTEP_COOLDOWN applies to ALL callers (dialogue + movement)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where to add footstep trigger | `PlayerController._physics_process()` | PlayerController already has movement detection; no new nodes/autoloads needed |
| Timing mechanism | Scalar accumulator (`_footstep_accumulator: float`) | Lighter than a Timer node; resets on stop to prevent phantom footsteps |
| Footstep interval | `0.5s` | Matches 2.5 m/s walk speed (~1.25 m/step) — tunes during implement |
| Scene ID source | `get_tree().current_scene.name` | No new coupling; scene root name matches `SCENE_TO_SURFACE` keys |
| Surface API | `AudioManager.get_surface_for_scene(scene_id)` | Already exists; returns `"office"` fallback for unknown scenes |
| Dialogue suppression | Already handled — `_dialogue_active == true` skips `_physics_process` movement block entirely | No additional logic needed |
| Cooldown sharing | Movement footsteps go through AudioManager's `FOOTSTEP_COOLDOWN` (0.3s) | Shared cooldown prevents rapid double-triggers between dialogue and movement |
| Existing tests | Append to `tests/unit/test_player_controller.gd` | Follows existing test pattern; no new test file needed |

---

## 2. PlayerController Layer 变更

> gdscripts/player_controller.gd — Add movement-triggered footstep integration.

### New Constants & Variables

```gdscript
const FOOTSTEP_INTERVAL: float = 0.5       # seconds between movement footsteps
const FOOTSTEP_ACCEL: float = 2.0           # multiplier when running (not used yet, reserved)
var _footstep_accumulator: float = 0.0      # elapsed time since last footstep
```

### _physics_process() 修改

Add footstep trigger logic after movement direction is computed (after line 239, before `velocity` assignment):

```
In _physics_process(), after direction is computed:

if direction != Vector3.ZERO and not _dialogue_active:
    _footstep_accumulator += delta
    if _footstep_accumulator >= FOOTSTEP_INTERVAL:
        _trigger_footstep()
        _footstep_accumulator = 0.0
else:
    # Reset accumulator when stationary or in dialogue
    _footstep_accumulator = 0.0
```

### New Method: _trigger_footstep()

```gdscript
func _trigger_footstep() -> void:
    var am := get_node_or_null("/root/AudioManager")
    if not am or not am.has_method("play_footstep"):
        return
    var scene_id: String = ""
    var scene_root := get_tree().current_scene
    if scene_root:
        scene_id = scene_root.name
    var surface: String = am.get_surface_for_scene(scene_id)
    am.play_footstep(surface)
```

### Data Flow Impact

- **Input:** `_physics_process()` detects `direction != Vector3.ZERO` (same condition used for velocity)
- **Timing:** Accumulator-based pacing at `FOOTSTEP_INTERVAL = 0.5s`
- **Surface:** Inferred from current scene name via `AudioManager.get_surface_for_scene()`
- **Output:** `AudioManager.play_footstep(surface)` — same method dialogue uses
- **Cooldown:** AudioManager's `FOOTSTEP_COOLDOWN = 0.3s` applies globally, preventing double-fire between dialogue-played and movement-played footsteps

### Edge Cases Handled

1. **First-frame footstep:** Player taps W briefly — accumulator reaches threshold → one footstep plays. If released before next interval, no more.
2. **Idle → move rapid cycling:** Accumulator resets to 0.0 on stop. On next move, accumulator starts from 0.0, so first footstep plays after `FOOTSTEP_INTERVAL` seconds.
3. **Dialogue mode:** `_dialogue_active == true` → `_physics_process` skips to line 215-219 (braking). The `else` branch resets `_footstep_accumulator = 0.0`.
4. **Scene transition mid-step:** Timer not bound to scene — accumulator resets on stop naturally. When movement resumes in new scene, `_trigger_footstep()` queries `get_tree().current_scene.name` for the new scene.
5. **No AudioManager:** `get_node_or_null("/root/AudioManager")` returns null → footstep silently skipped.

---

## 3. AudioManager Layer 变更

> No changes needed. AudioManager already provides:
> - `play_footstep(surface_type: String)` — plays footstep with cooldown
> - `get_surface_for_scene(scene_id: String) → String` — surface lookup
> - `FOOTSTEP_COOLDOWN = 0.3` — shared cooldown
> - `SCENE_TO_SURFACE` — 7 scenes → 3 surfaces mapping

---

## 4. Test Layer 变更

> Test file: `tests/unit/test_player_controller.gd` — append new test cases.
> Test file: `tests/unit/test_audio_manager.gd` — optionally verify cooldown sharing.

### Test Structure

- Append footstep test cases to existing `tests/unit/test_player_controller.gd`
- Follow existing naming convention: `_test_pc_n_*` (Normal), `_test_pc_e_*` (Edge), `_test_pc_f_*` (Failure)
- Use existing `_make_pc()` test helper which creates a PlayerController with Head, Camera3D, and InteractionArea

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Movement footstep trigger | ✅ (3 tests) | ✅ (3 tests) | ✅ (2 tests) |
| Footstep pacing/timing | ✅ (2 tests) | ✅ (1 test) | — |
| Surface detection | ✅ (1 test) | ✅ (1 test) | ✅ (1 test) |
| Dialogue mode suppression | ✅ (1 test) | ✅ (1 test) | — |

### Test Case Descriptions (Implement agent to write runnable GDScript)

#### TC-FS-N: Normal Path — Footstep Trigger

| ID | Name | Description | Verification |
|----|------|-------------|--------------|
| TC-FS-N-1 | Movement triggers footstep | Create PlayerController. Simulate movement direction != Vector3.ZERO. After `_footstep_accumulator >= FOOTSTEP_INTERVAL`, `_trigger_footstep()` is called. | Mock AudioManager and verify `play_footstep()` is called with a surface string. |
| TC-FS-N-2 | Footstep interval pacing | Set `_footstep_accumulator` just below threshold. Advance delta to cross threshold. Verify footstep plays. Advance delta again less than interval. Verify no second footstep. | Footstep plays at correct interval; no rapid-fire. |
| TC-FS-N-3 | Stationary produces no footsteps | Set direction = Vector3.ZERO. Call `_physics_process` multiple times. Verify no footstep calls. | Zero movement = zero footsteps. |
| TC-FS-N-4 | Surface inferred from scene name | Set `get_tree().current_scene.name = "street"`. Move. Verify `AudioManager.get_surface_for_scene("street")` is called. | Surface mapping functions correctly. |

#### TC-FS-E: Edge Cases — Footstep Pacing & Suppression

| ID | Name | Description | Verification |
|----|------|-------------|--------------|
| TC-FS-E-1 | Accumulator resets on stop | Move (accumulator increases). Stop moving. Accumulator resets to 0.0. Move again — first footstep takes full interval. | No "free" footsteps after stop. |
| TC-FS-E-2 | Dialogue mode suppresses footsteps | Set `_dialogue_active = true`. Move. Accumulator stays 0.0. No footstep calls. | Silent during dialogue. |
| TC-FS-E-3 | Idle → move rapid cycling | Alternate ZERO and non-ZERO direction rapidly. Each movement burst triggers at most one footstep after interval. | No rapid-fire on key taps. |

#### TC-FS-F: Failure Paths — Graceful Degradation

| ID | Name | Description | Verification |
|----|------|-------------|--------------|
| TC-FS-F-1 | No AudioManager autoload | Remove AudioManager from scene tree (`get_node_or_null` returns null). Move. No crash, no error, silent movement. | Graceful null-guard. |
| TC-FS-F-2 | Unknown scene ID | Set scene name to "unknown_scene". Move. `get_surface_for_scene` returns "office" (fallback). Footstep plays with office surface. | Graceful fallback surface. |

#### TC-FS-I: Integration — AudioManager Cooldown Sharing

| ID | Name | Description | Verification |
|----|------|-------------|--------------|
| TC-FS-I-1 | Movement + dialogue share cooldown | Play dialogue footstep, then immediately trigger movement footstep. AudioManager's FOOTSTEP_COOLDOWN blocks the second. Both call `play_footstep()` but cooldown enforces spacing. | Shared cooldown prevents double-fire. |

---

## 5. Files Changed

### Engine Layer (GDScript)

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/player_controller.gd` | Add `FOOTSTEP_INTERVAL` const, `_footstep_accumulator` var, footstep trigger in `_physics_process()`, `_trigger_footstep()` method | +35 |

### Audio Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/audio_manager.gd` | No changes needed | ±0 |

### Test Layer

| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/unit/test_player_controller.gd` | Append footstep test cases (TC-FS-N, TC-FS-E, TC-FS-F) | +80–100 |

---

## 6. Verification Checklist

- [ ] AC1 (rain loop): Already satisfied — no verification needed
- [ ] AC2 (footsteps on movement): PlayerController plays footsteps at 0.5s intervals when WASD direction != Vector3.ZERO
- [ ] AC3 (volume modulation): Already satisfied — no verification needed
- [ ] Dialogue mode: No movement footsteps play during `_dialogue_active == true`
- [ ] Surface detection: Footstep surface matches current scene via `AudioManager.get_surface_for_scene()`
- [ ] No AudioManager: Graceful null-guard — no crash, silent movement
- [ ] Test coverage: All TC-FS-N (4), TC-FS-E (3), TC-FS-F (2), TC-FS-I (1) test cases pass
- [ ] No regression on existing features: All pre-existing tests still pass
- [ ] Blocking dependency: Issue #149 (Player Character in scenes) must be merged before implement phase can be verified end-to-end

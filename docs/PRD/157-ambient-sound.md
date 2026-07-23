# Research: [Feature] Ambient Sound — Rain loop + footsteps

> Parent Issue: #157
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The game already has a fully implemented **Sound System** (Issue #48), which provides:

1. **Continuous rain ambient loop** — `rain_loop.wav` plays via `AudioManager` autoload from game start. Rain intensity modulates based on hope/conviction slider via `StateSystem`. Rain heavy variant (`rain_heavy.wav`) blends in at high despair.
2. **Distant city hum** — `city_hum.wav` plays as a low ambient drone.
3. **Dialogue-triggered footstep sounds** — The `DialogueRunner._apply_effects()` method supports `"play_sound"` effect type (lines 217–226), which calls `AudioManager.play_footstep(surface_type)`. The surface type is determined by the current scene via `SCENE_TO_SURFACE` mapping. When no surface is specified, the scene ID is inferred from `get_tree().current_scene.scene_id`.
4. **State modulation** — Hope/conviction modulates rain intensity (`0.0–1.0`), despair modulates volume, pitch, and distortion effects.
5. **Per-scene bus profiles** — Indoor, outdoor, and underpass profiles with reverb/low-pass filter effects.
6. **Scene transition cross-fade** — `AudioManager.cross_fade_ambient()` tweens volume levels on scene change.

**However, issue #157's core requirement is NOT yet met:**

- **Player-movement-triggered footsteps do not exist.** Footsteps are currently only triggered by dialogue `"play_sound"` effects, not by WASD player movement.
- **PlayerController** (`gdscripts/player_controller.gd`) — the WASD movement controller from Issue #142 — is implemented and merged, but it has **zero audio integration**. It neither plays footsteps nor connects to AudioManager.
- **Rain plays continuously** ✅ — this AC is already satisfied.
- **Volume responds to hope/despair slider** ✅ — this AC is already satisfied.
- **Spatial audio for footsteps** — AudioStreamPlayer2D with positional audio is set up (`_footstep_player` is an `AudioStreamPlayer2D`), but no in-world spatial positioning is applied for movement-triggered footsteps.

### Gap Analysis: What #48 Delivered vs. What #157 Needs

| Requirement | #48 Status | #157 Status |
|-------------|-----------|-------------|
| Continuous rain ambient loop | ✅ Implemented | ✅ Already met |
| Footstep sounds (dialogue-triggered) | ✅ Implemented | ✅ Already met |
| Footstep sounds (movement-triggered) | ❌ Not in scope | ❌ **GAP** — needs implementation |
| State slider modulation of audio | ✅ Implemented | ✅ Already met |
| Per-scene acoustic profiles | ✅ Implemented | ✅ Already met |
| Scene transition cross-fade | ✅ Implemented | ✅ Already met |
| Underpass reverb/low-pass | ✅ Implemented | ✅ Already met |
| Spatial audio for movement footsteps | N/A | ❌ **GAP** — needs integration with player position |

### User Scenarios

- **Scenario A (Movement footsteps):** Player presses W to walk forward. Each step triggers a footstep sound via AudioManager. Surface type is determined by the current scene (office → hard floor, street → wet pavement, underpass → echoing concrete). Footstep rate matches walk speed.
- **Scenario B (Footstep cooldown respects movement):** Player walks rapidly — footsteps play at the rate determined by `FOOTSTEP_COOLDOWN` (0.3s minimum), not at every physics frame. Player stops moving → footsteps stop within one cooldown cycle.
- **Scenario C (Spatial audio):** Footstep audio plays at the player's world position via AudioStreamPlayer2D, providing positional audio relative to the camera (which is first-person at eye level).
- **Scenario D (Dialogue mode suppression):** During dialogue (`_dialogue_active == true`), feet are not walking (WASD is paused), so no movement footsteps play. Audio state modulation from sliders continues unaffected.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally. The Sound System (Issue #48) was scoped to **dialogue-triggered** audio events because the dialogue engine was the active narrative system at the time. The Player Controller (Issue #142) was implemented later as a separate feature, and its scope was WASD movement + E-key interaction — **audio integration was explicitly deferred** to this issue (#157).

From PRD #142 (Section 6 — "Blocks"):
> **Player footstep audio (Linked to Issue #48 Sound System) | P2**

This confirms that movement-triggered footsteps were always intended as a follow-up once both the Sound System AND Player Controller were merged.

### Why Change Now?

1. **Both prerequisite systems are merged**: AudioManager (autoload) + PlayerController (CharacterBody3D with WASD) exist and are functional.
2. **Movement-triggered footsteps deliver atmosphere**: The "walking through a rainy city at night" premise is incomplete without footstep audio tied to player movement.
3. **Surface-type differentiation already exists**: AudioManager's `SCENE_TO_SURFACE` mapping and `play_footstep(surface_type)` API are ready — they just need a movement trigger.
4. **Low implementation risk**: Adding movement-triggered footsteps is a small (~30 line) additive change to PlayerController. AudioManager already does footstep cooldown, surface mapping, and stream selection.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| Sound system | `AudioManager` autoload with `AudioStreamPlayer2D` players, bus effects, state modulation |
| Footstep API | `AudioManager.play_footstep(surface_type: String)` — cooldown (0.3s), surface-based stream selection |
| Player | `PlayerController` (CharacterBody3D) with WASD movement, click-drag mouse look, E-key interaction |
| Surfaces | 3 types: `"office"` (hard floor), `"street"` (wet pavement), `"underpass"` (echoing concrete) |
| Scene-surface mapping | `SCENE_TO_SURFACE` — 7 scenes mapped to 3 surface types |
| State system | Tri-axis via `StateSystem` (hope, conviction, will 0–10) |
| Dialogue mode | WASD pauses during `_dialogue_active == true` |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/player_controller.gd` | PlayerController | **Modify** — Add footstep trigger in `_physics_process()` when direction != Vector3.ZERO, with timer-based pacing. Get surface via AudioManager. |
| `gdscripts/audio_manager.gd` | AudioManager | **No change needed** — `play_footstep()`, cooldown, surface mapping, and `get_surface_for_scene()` already exist. |

### Indirectly Affected Modules

| File | Why Affected |
|-------------|-------------|
| `docs/DESIGN/142-player-controller.md` | May need update to document audio integration |
| `docs/DESIGN/48-sound-system.md` | May need update to document movement-triggered audio |
| `tests/unit/test_player_controller.gd` | Add tests for movement-triggered footstep behavior |

### Data Flow Impact

**Current flow (dialogue-triggered footsteps only):**
```
Dialogue choice → effects: [{type: "play_sound", surface: "street"}]
    → DialogueRunner._apply_effects() → AudioManager.play_footstep("street")
        → footstep_player.stream = preloaded[stream]
        → footstep_player.play()
        → footstep_played.emit("street")
```

**Proposed flow (movement-triggered + dialogue-triggered):**
```
PlayerController._physics_process(delta)
    │
    ├── direction = WASD vector (normalized)
    ├── if direction != Vector3.ZERO and _footstep_timer.time_left == 0:
    │     └── AudioManager.play_footstep(surface)
    │     └── _footstep_timer.start(FOOTSTEP_INTERVAL)
    └── if direction == Vector3.ZERO:
          └── _footstep_timer.stop()

DialogueRunner (existing, unchanged):
    effects: [{type: "play_sound", ...}] → AudioManager.play_footstep()
```

**Both paths coexist.** The AudioManager's `FOOTSTEP_COOLDOWN` (0.3s) is shared — dialogue-triggered and movement-triggered footsteps share the same cooldown, preventing double-triggering.

### Cross-System Interaction

```
PlayerController
    ├── Gets surface from AudioManager.get_surface_for_scene()
    ├── Calls AudioManager.play_footstep(surface)
    └── pausing input → signals → footstep timer stops (movement paused)

AudioManager (existing)
    ├── FOOTSTEP_COOLDOWN applies to ALL callers (dialogue AND movement)
    └── Surface mapping handles scene transitions automatically
```

### Documents to Create/Update

- [ ] `docs/PRD/157-ambient-sound.md` (this document)
- [ ] `docs/DESIGN/157-ambient-sound.md` — Plan phase artifact
- [ ] `docs/TASKS/157-ambient-sound.md` — Plan phase artifact

---

## 4. Solution Comparison

### Approach A: Movement Trigger in PlayerController (Recommended)

**Description:** Add a `Timer`-paced footstep trigger in `PlayerController._physics_process()`. When the player moves (direction != Vector3.ZERO) and the footstep timer expires, call `AudioManager.play_footstep(surface)`.

**Implementation sketch:**
```gdscript
# player_controller.gd additions
const FOOTSTEP_INTERVAL: float = 0.5  # seconds between movement footsteps
var _footstep_timer: float = 0.0

func _physics_process(delta: float) -> void:
    # ... existing code ...
    if direction != Vector3.ZERO and not _dialogue_active:
        _footstep_timer -= delta
        if _footstep_timer <= 0.0:
            _trigger_footstep()
            _footstep_timer = FOOTSTEP_INTERVAL
    else:
        _footstep_timer = 0.0  # reset on stop

func _trigger_footstep() -> void:
    var am := get_node_or_null("/root/AudioManager")
    if am and am.has_method("get_surface_for_scene"):
        var surface: String = am.get_surface_for_scene(_current_scene_id)
        am.play_footstep(surface)
```

**Pros:**
- Minimal code change (~25 lines)
- PlayerController already has movement detection logic
- Shared cooldown with dialogue footsteps via AudioManager
- No new nodes or signals needed
- Works across all scenes automatically (surface inferred from scene)

**Cons:**
- PlayerController needs a `_current_scene_id` reference (or infers from scene root)
- Footstep interval is hardcoded; not yet tied to walk speed

**Risk:** Low — additive change to existing PlayerController, no architectural changes

**Effort:** Small (~1 hour)

### Approach B: Dedicated AudioFootstepManager

**Description:** Create a new `AudioFootstepManager` autoload or child node that listens for player movement. PlayerController emits a `movement_changed(is_moving: bool)` signal. The footstep manager handles timing, surface detection, and cooldown logic.

**Implementation sketch:**
```gdscript
# audio_footstep_manager.gd — new autoload
extends Node
signal movement_state_changed(is_moving: bool)

var _footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.5

func _process(delta: float) -> void:
    if not _is_moving:
        return
    _footstep_timer -= delta
    if _footstep_timer <= 0.0:
        _play_footstep()
        _footstep_timer = FOOTSTEP_INTERVAL

func _play_footstep() -> void:
    var am := get_node_or_null("/root/AudioManager")
    if am:
        am.play_footstep(...)
```

**Pros:**
- Decoupled from PlayerController — cleaner separation of concerns
- Easier to test independently
- Could support multiple movement sources (future NPCs)

**Cons:**
- New file + new autoload registration
- Need to connect PlayerController ↔ FootstepManager signals
- Over-engineered for a single-player, single-controller game
- More complexity than needed

**Risk:** Low (standard Godot pattern), but unnecessary

**Effort:** Small-Medium (~2 hours)

### Approach C: Dialogue-only (No Change)

**Description:** Do nothing. Rely on existing dialogue-triggered footsteps only. Player movement produces no audio.

**Pros:**
- Zero effort
- No risk of regression

**Cons:**
- Issue #157's core requirement is unmet
- Player movement is silent — breaks immersion
- The "walking through a rainy city" premise is audio-incomplete

**Risk:** Low (nothing breaks), but feature requirement is rejected

**Effort:** Zero

### Recommendation

→ **Approach A (Movement Trigger in PlayerController)** because:
1. Smallest code change — ~25 lines additive, no new files
2. PlayerController already has the movement detection (direction != Vector3.ZERO in `_physics_process`)
3. AudioManager already provides the full footstep API (cooldown, surface mapping, stream selection)
4. No new autoloads or nodes needed — keeps the architecture simple
5. Both dialogue-triggered AND movement-triggered footsteps share AudioManager's cooldown
6. Surface detection is automatic via `AudioManager.get_surface_for_scene()`

---

## 5. Boundary Conditions & Acceptance Criteria

### Acceptance Criteria (from Issue #157)

- [ ] **AC1:** Continuous rain ambient plays on game start.
  - ✅ Already satisfied by existing AudioManager autoload (Issue #48).
  - **Verification:** `audio_manager.gd` line 140-149 `_start_ambient_loops()` plays `rain_loop.wav` and `city_hum.wav` on `_ready()`. AudioManager is registered as autoload in `project.godot:25`.

- [ ] **AC2:** Footstep sounds trigger on player movement.
  - ❌ **GAP** — Requires PlayerController modification (Approach A).
  - **Verification:** Start game in any scene. Press W to walk. Footstep audio plays at ~0.5s intervals while moving. Footsteps stop when W is released.

- [ ] **AC3:** Sound volume responds to hope/despair slider.
  - ✅ Already satisfied by existing state modulation (Issue #48).
  - **Verification:** `audio_manager.gd` line 276-290 `_on_state_changed()` modulates rain volume, pitch, and distortion based on conviction/despair.

### Normal Path

1. Player starts game in office → rain loop plays continuously (existing)
2. Player presses W to walk forward → footsteps play at walking pace, surface = "office"
3. Player moves into lobby via dialogue → scene transitions, rain cross-fades, footsteps now play surface = "office" (lobby maps to office surface)
4. Player transitions to street → surface changes to "street" (wet pavement footsteps)
5. Player transitions to underpass → surface changes to "underpass" (echoing concrete footsteps)
6. Player's hope slider changes → rain volume/pitch modulates (existing)

### Edge Cases

1. **Footstep on first frame of movement:** Player taps W for 50ms — only ONE footstep should play (no rapid-fire). The `FOOTSTEP_INTERVAL` timer ensures minimum spacing.
2. **Idle → move → idle → move rapid cycling:** Player taps W repeatedly. Each tap should trigger at most one footstep, respecting both PlayerController's timer AND AudioManager's FOOTSTEP_COOLDOWN.
3. **Dialogue mode active:** WASD is paused during dialogue → no movement footsteps. Dialogue-triggered footsteps still play via `play_sound` effects.
4. **Scene transition mid-step:** Player is walking when dialogue triggers scene change. Footstep timer resets. On new scene load, movement resumes with the new scene's surface type.
5. **No AudioManager available:** If AudioManager autoload is missing (edge case during development), `_trigger_footstep()` silently skips via null check guard.

### Failure Paths

1. **AudioManager not loaded:** PlayerController calls `get_node_or_null("/root/AudioManager")` → returns null → no footstep plays. Graceful degradation (silent movement).
2. **Surface for scene not found:** `AudioManager.get_surface_for_scene()` returns `"office"` (fallback from `SCENE_TO_SURFACE`). Footsteps play with office surface audio. Graceful.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| AudioManager autoload with `play_footstep()` API | ✅ Complete (Issue #48) | Low |
| PlayerController WASD movement in `_physics_process()` | ✅ Complete (Issue #142) | Low |
| Audio assets: footstep_office.wav, footstep_street.wav, footstep_underpass.wav | ✅ Present in `assets/audio/` | Low |
| `SCENE_TO_SURFACE` mapping in AudioManager | ✅ Complete | Low |
| FOOTSTEP_COOLDOWN in AudioManager (0.3s) | ✅ Complete | Low |
| **Player Character / CharacterBody3D in scenes** (#149) | ❌ **OPEN** | **High** — Without player character instances in scenes, movement footsteps have no trigger context |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Player character spawn point integration (#149) | P0 — prerequisite for movement footsteps |
| Footstep audio asset refinement (if placeholder wavs get replaced) | P2 |

### Critical Dependency Note

Issue #149 (Player Character — CharacterBody3D + Controller) is marked as OPEN and is listed as a prerequisite for #157. However, the `PlayerController.gd` script (WASD movement, mouse look, interaction) was already implemented and merged via Issue #142. The gap appears to be **placing PlayerController instances in scenes** (main.tscn or per-scene spawn points) — without a player body in the scene tree, there is no node to run `_physics_process()` and no player to move. The movement-triggered footstep feature **cannot be verified without #149's completion.**

### Preparation Needed

- [ ] #149 must be merged before #157 implement phase can be verified
- [ ] Confirm PlayerController has access to `_current_scene_id` or scene identification at `_physics_process()` time
- [ ] Agree on footstep interval: `0.5s` recommended (matches 2.5 m/s walk speed, one step per ~1.25m)

---

## 7. Spike / Experiment (Optional — depth/standard only)

> Skipped per `depth/standard` label. The recommended approach (Movement Trigger in PlayerController) follows established patterns with low technical risk. The only uncertainty is the precise footstep interval that sounds natural at `walk_speed = 2.5 m/s`, which can be tuned during implementation.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

### Current State Summary

The **Sound System** (Issue #48) and **Player Controller** (Issue #142) are both fully implemented and merged. The existing codebase has:

- `AudioManager` autoload with rain loop, city hum, dialogue-triggered footstep sounds, state modulation (conviction/despair → volume/pitch/distortion), per-scene bus profiles (indoor/outdoor/underpass), and scene transition cross-fade. All audio assets (`rain_loop.wav`, `rain_heavy.wav`, `city_hum.wav`, `footstep_office.wav`, `footstep_street.wav`, `footstep_underpass.wav`) are present in `assets/audio/`.
- `PlayerController` (CharacterBody3D) with WASD movement at 2.5 m/s, click-drag mouse look, E-key interaction, dialogue mode suppression. No audio integration.
- `DialogueRunner` with `play_sound` effect type already wired to `AudioManager.play_footstep(surface_type)`.

**What this issue (#157) adds:** ~25 lines in `PlayerController._physics_process()` to trigger `AudioManager.play_footstep()` when the player is moving, paced by a timer at ~0.5s intervals. Precisely:

1. Add `const FOOTSTEP_INTERVAL: float = 0.5` and `var _footstep_timer: float = 0.0` to PlayerController
2. In `_physics_process()`, when `direction != Vector3.ZERO` and `_footstep_timer <= 0.0` and `not _dialogue_active`: call AudioManager, reset timer
3. In `_physics_process()`, when `direction == Vector3.ZERO`: reset `_footstep_timer = 0.0`
4. Null-guard all AudioManager calls (`get_node_or_null`)
5. Get surface via `AudioManager.get_surface_for_scene(scene_id)` — infer scene_id from current scene root or store as PlayerController state

**Test plan (implement phase):**
- Unit test: movement triggers footstep after FOOTSTEP_INTERVAL
- Unit test: stopped movement resets timer
- Unit test: dialogue mode suppresses movement footsteps
- Unit test: surface inferred correctly from scene
- Integration test: rapid W-tap produces spaced footsteps (respects cooldown + timer)

**Blocking dependency:** Issue #149 (Player Character — CharacterBody3D + Controller) is **OPEN** and is listed as a prerequisite. The `PlayerController.gd` script exists from #142, but #149 is about placing/integrating it into scenes. Movement-triggered footsteps cannot be verified without a player body in the scene tree.

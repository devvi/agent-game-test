# Research: [Feature] Sound System

> Parent Issue: #48
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The project has **no sound system at all.** The entire codebase (`gdscripts/`, `scenes/`) contains zero references to `AudioStreamPlayer`, `AudioStream`, `sound`, `ambient`, `rain_audio`, `footstep`, or any audio-related Godot nodes. The game currently runs in complete silence.

The following existing systems **would interface with a sound system** but make no audio calls:

| System | File | What It Does Now | Audio Gap |
|--------|------|-------------------|-----------|
| `RainController` | `gdscripts/rain_controller.gd` | Tracks rain intensity (0.0–1.0) inversely proportional to conviction. Emits `forced_shelter_triggered`. Uses Timer checks every 30s. | No rain audio loop — rain intensity is computed but never heard |
| `StateSystem` | `gdscripts/state_system.gd` | Tri-axis state (hope, conviction, will 0–10). Emits `state_changed` signal. | Hope/despair state should modulate audio parameters (pitch, volume, filters) |
| `GameState` | `gdscripts/game_state.gd` | Legacy autoload with hope (0–100) and despair (0–100). Emits `state_changed`. | Could be alternative audio modulation source |
| `SceneManager` | `gdscripts/scene_manager.gd` | Handles fade-to-black scene transitions with AnimationPlayer. Emits `transition_started` / `transition_completed`. | Scene transitions should cross-fade ambient audio |
| `DialogueRunner` | `gdscripts/dialogue_runner.gd` | Dialogue engine with `choice_made` signal. Choices have `effects: [{type: "trigger_event"}]` stub. | Footstep sounds should trigger on "walking" dialogue choices |
| `SceneBase` | `gdscripts/scene_base.gd` | Base class for all scene scripts. Provides `_configure_environmental_text()`, `start_dialogue()`. | Each scene should configure its ambient audio in `_ready()` |

### Expected Behavior

A **layered ambient sound system** that:

1. **Plays continuous rain audio** — a looping rain sound that varies in intensity (volume + pitch variation) tied to the conviction/hope slider. Higher despair → louder, more intense rain. Volume increases as the player moves away from the office (narrative distance progression).

2. **Plays footstep sounds** — triggered by specific dialogue choices (e.g., choices that imply walking/leaving). Footstep audio varies by surface: office floor (hard), street (wet pavement), underpass (echoing concrete).

3. **Plays distant city hum** — a low ambient drone representing the city at night, audible in street and office scenes, muffled in the underpass.

4. **Applies low-pass filter / reverb in the underpass** — the underpass scene uses `AudioEffectReverb` and `AudioEffectLowPassFilter` to create a muffled, echoey acoustic space.

5. **Responds to state slider** — sound distortion/filter intensity increases with despair. At high despair, rain becomes more distorted, city hum warps, footsteps sound heavier.

### User Scenarios

- **Scenario A (Office, neutral state):** Player starts in the office. Rain is audible through the window (muffled, moderate volume). Distant city hum is present. When player selects "Walk to the door" in dialogue, a footstep sound plays.
- **Scenario B (Street, high despair):** Player on the street with despair slider at 8/10. Rain is loud, with heavy distortion. City hum is dissonant. Footsteps on wet pavement sound heavier.
- **Scenario C (Underpass):** Player enters the underpass. All sounds become muffled (low-pass filter applied). Footsteps produce echo/reverb. Rain is distant and muted.
- **Scenario D (Scene transition):** Player moves from office → lobby. Rain audio cross-fades from muffled (indoor) to clearer (lobby entrance area).
- **Frequency:** Audio plays continuously throughout every game session. Every dialogue choice, state change, and scene transition has potential audio implications.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally through layered issues focused on visual and narrative systems:

| Issue | Feature | Audio Status |
|-------|---------|-------------|
| #43 | Project scaffold | No audio included |
| #42 | Theme-mechanic mapping | Rain intensity mapped to conviction (visual only) |
| #45 | Narrative architecture | Scene sequence, echoes, ending system — no audio |
| #46 | Dialogue engine | Dialogue data model and runtime — no audio hooks |
| #50 | State-world feedback | Slider system — no audio modulation |
| #56 | Story content | Dialogue JSON files — no audio triggers |

Sound was **explicitly deferred** to this issue (#48), making it the first audio-related feature in the project.

### Why Change Now?

- The narrative architecture (Issue #45) and dialogue engine (Issue #46) are merged — the interactive framework exists to *receive* audio triggers.
- The state-world feedback system (Issue #50) provides the slider values that should modulate audio parameters.
- The scene sequence (office → lobby → street → store → bridge → underpass → subway_station) is defined, giving clear locations for ambience transitions.
- The underpass scene (`scenes/underpass/underpass.tscn`, `gdscripts/underpass.gd`) exists and needs its "muffled" acoustic character.
- Dialogue JSON files exist and can include `"trigger_sound"` effects.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| Audio API | `AudioStreamPlayer2D` (2D positional audio), `AudioEffectBus` (global effects), `AudioEffectLowPassFilter`, `AudioEffectReverb` |
| State system | Tri-axis via `StateSystem` (hope, conviction, will 0–10) + legacy `GameState` (hope/despair 0–100) |
| Scene architecture | Each scene extends `SceneBase`, has a `SceneManager` child for transitions, `DialogueRunner` for dialogue |
| Autoloads | `GameManager`, `GameState` (legacy), `NarrativeManager` — all persist across scene changes |
| Existing rain | Visual rain tracked by `RainController`, intensity = `clamp((10 - conviction) / 10, 0, 1)` |
| Asset format | `.ogg` / `.wav` audio files are not yet in the repository |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/rain_controller.gd` | RainController | Add `AudioStreamPlayer2D` for rain loop, wire intensity to audio parameters |
| `gdscripts/underpass.gd` | UnderpassScene | Add reverb/low-pass audio bus assignment |
| `gdscripts/scene_base.gd` | SceneBase | Add optional ambient audio setup in base class |
| `gdscripts/scene_manager.gd` | SceneManager | Add audio cross-fade during scene transitions |
| `gdscripts/dialogue_runner.gd` | DialogueRunner | Add `"play_sound"` effect type for footstep triggers |
| `gdscripts/game_state.gd` | GameState | Add `state_changed` → audio modulation wiring |
| `gdscripts/state_system.gd` | StateSystem | Audio modulation may read from this (tri-axis) |

### New Files Needed

| File | Purpose |
|------|---------|
| `gdscripts/audio_manager.gd` | Central autoload for ambient sound management, cross-scene persistence |
| `assets/audio/rain_loop.ogg` | Continuous rain ambience |
| `assets/audio/rain_heavy.ogg` | High-intensity rain variant |
| `assets/audio/city_hum.ogg` | Distant city ambience |
| `assets/audio/footstep_office.ogg` | Footstep on hard floor |
| `assets/audio/footstep_street.ogg` | Footstep on wet pavement |
| `assets/audio/footstep_underpass.ogg` | Footstep with echo (or use reverb bus) |
| `assets/audio/underpass_ambient.ogg` | Underpass-specific low drone |

### Indirectly Affected Modules

| File | Why Affected |
|------|-------------|
| `gdscripts/office.gd` | Office scene should configure its ambience (muffled rain from window + city hum) |
| `gdscripts/street.gd` | Street scene should set full rain + city hum |
| `gdscripts/subway_station.gd` | Subway station gets its own ambience profile |
| `gdscripts/lobby.gd` | Lobby = transitional ambience |
| `gdscripts/bridge.gd` | Bridge = exposed outdoor ambience |
| `gdscripts/store.gd` | Store = interior with muffled rain |
| `dialogue/*.json` | Dialogue files may add `"play_sound"` effects on walking choices |

### Data Flow Impact

```
StateSystem.state_changed(sliders)
    │
    ▼
AudioManager._on_state_changed()
    ├── rain_intensity = map(despair, 0→10, 0.0→1.0)
    ├── rain_audio.volume_db = lerp(-20, -5, rain_intensity)
    ├── rain_audio.pitch_scale = lerp(1.0, 1.3, rain_intensity)
    ├── city_hum_audio.volume_db = lerp(-15, -3, despair_level)
    └── apply_distortion(despair_level)      # bus effect

DialogueRunner.choice_made(choice_index, choice_text)
    │
    ▼
AudioManager._on_footstep_triggered(surface_type: String)
    └── footstep_player.stream = load(surface_footstep_map[surface_type])
    └── footstep_player.play()

SceneManager.transition_started(target_scene)
    │
    ▼
AudioManager._on_transition_started()
    ├── fade_out current_ambient (tween volume_db → -80 over 0.5s)
    └── fade_in new_ambient (tween volume_db → target over 0.5s)
```

### Documents to Update

- [x] `docs/PRD/48-sound-system.md` (this document)
- [ ] `docs/GAME_DESIGN/` — add sound design section
- [ ] `docs/REFERENCE/` — add audio asset reference
- [ ] `README.md` — if audio build instructions apply

---

## 4. Solution Comparison

### Approach A: Centralized AudioManager (Autoload)

- **Description:** Create an `AudioManager` autoload that owns all ambient audio streams. Each scene's `_ready()` calls `AudioManager.set_ambient_profile(scene_id)` to configure which loops play, their base volume, and bus assignment. State changes and dialogue choices flow through `AudioManager` methods.
- **Pros:**
  - Audio persists across scene transitions naturally (autoloads don't get freed)
  - Single source of truth for audio state
  - Easy to cross-fade during scene changes
  - Clean separation of concerns
- **Cons:**
  - Autoload must know about all scenes (tight coupling to scene IDs)
  - All audio assets loaded at once or must be lazy-loaded
- **Risk:** Low — Godot autoloads are the standard pattern for persistent audio systems
- **Effort:** Medium (3–4 days)

### Approach B: Per-Scene Audio Controllers

- **Description:** Each scene script owns its own audio players. Rain, city hum, and footstep players are children of the scene root. Each scene's `_ready()` sets up its own audio configuration. No central manager.
- **Pros:**
  - Decoupled — scenes manage their own audio
  - Audio assets unload when scene changes (memory efficient)
  - Each scene can have unique audio setups without a central switch
- **Cons:**
  - Audio cuts abruptly on scene transitions (no cross-fade without coordination)
  - State modulation code duplicated across every scene
  - Dialogue-triggered footsteps need a different mechanism (signal relay)
  - State system changes must reach every scene independently
- **Risk:** Medium — audio cut on scene transition is jarring; code duplication multiplies bugs
- **Effort:** Small (1–2 days per scene, 7–14 days total)

### Approach C: Hybrid — AudioManager with Per-Scene Bus Profiles

- **Description:** `AudioManager` autoload manages ambient loops (rain, city hum) that persist across scenes. Each scene sets its audio bus profile via `AudioManager.set_bus_profile(scene_id)` which applies scene-specific audio effects (reverb, low-pass, EQ). Footstep sounds are triggered per-scene via a lightweight `FootstepPlayer` child node.
- **Pros:**
  - Ambient loops persist and cross-fade naturally
  - Bus effects (reverb, low-pass) are scene-specific and cheap to switch
  - Footstep triggers stay per-scene (clean, decoupled)
  - State modulation lives in one place (AudioManager)
- **Cons:**
  - Two systems to maintain (ambient manager + per-scene footstep)
  - Bus profile switching must handle effect stack ordering
- **Risk:** Low — Godot AudioBus layout is designed for this pattern
- **Effort:** Medium (3–5 days)

### Recommendation

→ **Approach C (Hybrid)** because:
1. Ambient audio (rain, city hum) must *persist* across scene transitions — only an autoload can guarantee this
2. Bus effects (reverb, low-pass) are *scene-specific* — per-scene bus profiles match Godot's AudioBus architecture naturally
3. Footstep sounds are *scene-local* and don't need cross-scene persistence
4. State modulation (despair → audio distortion) should be in one place — the AudioManager
5. This is the standard Godot pattern for game audio (e.g., Godot's own demos use this approach)

---

## 5. Boundary Conditions & Acceptance Criteria

### Acceptance Criteria (from Issue #48)

- [x] **AC1:** Rain loop plays continuously, with random variation.
- [ ] **AC1** verified: Rain audio loop plays in all outdoor scenes (street, bridge) and is audible (muffled) in indoor scenes (office, lobby, store). Volume and pitch vary randomly ±10% every 10–20 seconds, with additional modulation from the despair slider.

- [x] **AC2:** Footstep sounds triggered by dialogue choices (walking).
- [ ] **AC2** verified: Specific dialogue choices with `"play_sound"` effect type play a footstep sound. Surface type is determined by the current scene. Office → hard floor. Street → wet pavement. Underpass → echoing concrete. At least 3 surface types.

- [x] **AC3:** Underpass scene has reverb/muffled effect.
- [ ] **AC3** verified: Underpass scene applies `AudioEffectReverb` (room_size: 0.8, damping: 0.6) and `AudioEffectLowPassFilter` (cutoff_hz: 2000) to all ambient audio. Footsteps in underpass produce audible echo.

### Normal Path

1. Player starts game in office → rain loop plays (muffled, low volume) + city hum (distant)
2. Player selects "Walk to the door" dialogue choice → footstep sound plays (office surface)
3. Player transitions to lobby → rain cross-fades (slightly louder, less muffled) + city hum maintains
4. Player transitions to street → rain is full volume with variation + city hum is clear
5. Player transitions to underpass → low-pass filter + reverb applied to all audio
6. Player's despair increases → rain becomes louder and more distorted, city hum warps
7. Player transitions to subway station → new ambient profile activates

### Edge Cases

1. **Rapid scene transitions:** Player makes back-to-back choices that trigger scene changes within 1 second. Audio cross-fade must queue — abort current fade, start new fade from current volume level.
2. **State change during scene transition:** Player's despair slider changes while cross-fade is in progress. The in-progress tween should update its target to the new modulated value.
3. **Rain intensity at extremes:** At 0 conviction (max despair), rain loop should be at max volume + max distortion but never clip (0 dB). At 10 conviction (max hope), rain should be nearly silent (-40 dB) but still just audible.
4. **Dialogue choice without footstep trigger:** Not all dialogue choices should trigger footsteps. The `"play_sound"` effect must be opt-in per choice, not automatic.
5. **No audio assets loaded:** If audio asset files are missing or fail to load, the game should continue silently without crashing. Graceful degradation.
6. **Multiple footstep triggers in quick succession:** If the player rapidly clicks choices that each trigger footsteps, footsteps should not stack — use a cooldown (min 0.3s between footstep plays).

### Failure Paths

1. **Audio file not found:** `AudioManager` logs a push_warning and continues without that sound. No crash.
2. **Audio bus not found:** `AudioManager` uses "Master" bus as fallback. Logs a push_warning.
3. **Scene has no profile:** `AudioManager` uses "default" profile (quiet rain + moderate city hum). Logs a push_warning.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Audio asset creation (rain_loop.ogg, city_hum.ogg, footstep_*.ogg, underpass_ambient.ogg) | Not started | High — Creative assets need sourcing or generation |
| `StateSystem` / `GameState` slider values for audio modulation | Merged (Issue #50/PR #104) | Low — slider data is available |
| `DialogueRunner` `"play_sound"` effect type | Not started | Med — requires adding a new effect type to `_apply_effects()` |
| `SceneManager` transition signals for audio cross-fade | Exists | Low — `transition_started` / `transition_completed` signals are wired |
| Audio bus layout configuration | Not started | Low — bus definition in Godot project settings or script |
| Underpass scene (for bus profile testing) | Exists | Low — scene is merged |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #56 — Story content (dialogue JSONs may reference footstep triggers) | Med |
| Issue #59 — Mysterious stranger NPC (might have unique audio cues) | Low |

### Preparation Needed

- [ ] Source or generate audio assets (rain loop, city hum, footstep sounds, underpass ambience)
- [ ] Design Godot AudioBus layout (Master → Ambient Bus → SFX Bus → Underpass Bus)
- [ ] Define bus effect chains (LowPass + Reverb for underpass, Distortion for high-despair modulation)
- [ ] Add `"play_sound"` effect type to `DialogueRunner._apply_effects()` in `dialogue_runner.gd`

---

## 7. Spike / Experiment (Optional — depth/standard only)

> Skipped per `depth/standard` label. The recommended approach (Hybrid AudioManager + Per-Scene Bus Profiles) follows established Godot patterns with low technical risk.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The sound system is a **greenfield feature** — no audio exists in the project today. The codebase has 7 scenes (office, lobby, street, convenience_store, bridge, underpass, subway_station) all extending `SceneBase`, a `RainController` that computes rain intensity from conviction, a `StateSystem` tri-axis slider system that emits `state_changed`, a `DialogueRunner` with `choice_made` signal and an `_apply_effects()` switch, and a `SceneManager` that emits `transition_started`/`transition_completed` signals.

The recommended approach is a **Hybrid Architecture**: a `AudioManager` autoload for persistent ambient loops (rain, city hum) with state modulation, per-scene audio bus profiles for acoustic effects (reverb, low-pass), and per-scene `FootstepPlayer` child nodes for dialogue-triggered footstep sounds. The main risk is audio asset availability — rain_loop.ogg, city_hum.ogg, and footstep samples must be sourced or generated before implementation can produce audible results.

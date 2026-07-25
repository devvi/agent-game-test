# Research: [Feature] 音效与背景音乐系统 (Sound & Background Music System)

> Parent Issue: #219
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

The project already has a mature **ambient sound system** delivered by Issues #48 and #157:

1. **Continuous rain ambient loop** — `rain_loop.wav` plays via `AudioManager` autoload from game start. Rain intensity modulates based on conviction (hope/despair) via `StateSystem`. A heavy rain variant (`rain_heavy.wav`) blends in at high despair.
2. **Distant city hum** — `city_hum.wav` plays as a low ambient drone, volume modulated by despair and narrative distance.
3. **Dialogue-triggered footstep sounds** — `DialogueRunner._apply_effects()` supports `"play_sound"` effect type, calling `AudioManager.play_footstep(surface_type)`.
4. **Movement-triggered footsteps** — `PlayerController._physics_process()` triggers footsteps via timer-based pacing at `FOOTSTEP_INTERVAL = 0.5s`, reusing AudioManager's API.
5. **State modulation** — Hope/conviction modulates rain intensity (`0.0–1.0`), despair modulates volume, pitch, and distortion effects on the Master bus.
6. **Per-scene bus profiles** — Indoor (LowPass 4kHz), Outdoor (no effects), Underpass (Reverb + LowPass 2kHz) bus profiles switch via `AudioManager.set_bus_profile()`.
7. **Scene transition cross-fade** — `AudioManager.cross_fade_ambient()` tweens volume levels on scene change.
8. **Hallucination system (visual only)** — `NarrativeManager` computes hallucination level (0–10) per scene with visual params (`vignette`, `rain_density`, `light_flicker`, `text_drift`, `view_instability`). **No audio integration** — hallucination does not affect audio at all.
9. **No background music (BGM)** — Zero music infrastructure exists. No `AudioStreamPlayer` for music, no music assets, no music-related code.

**Existing audio assets** in `assets/audio/`:
| File | Purpose |
|------|---------|
| `rain_loop.wav` | Continuous rain ambience (10-30s loop) |
| `rain_heavy.wav` | High-intensity rain variant |
| `city_hum.wav` | Distant city ambient drone |
| `footstep_office.wav` | Footstep on hard floor |
| `footstep_street.wav` | Footstep on wet pavement |
| `footstep_underpass.wav` | Footstep with echo |
| `underpass_ambient.wav` | Underpass-specific low drone |

**Audio Bus Layout** (`default_bus_layout.tres`):
| Bus | Effects |
|-----|---------|
| Master | AudioEffectDistortion (default bypassed) |
| AmbientBus | None |
| SFXBus | None |
| IndoorBus | AudioEffectLowPassFilter (cutoff_hz: 4000) |
| UnderpassBus | AudioEffectReverb (room_size: 0.8, damping: 0.6) + AudioEffectLowPassFilter (cutoff_hz: 2000) |

### What Issue #219 Requires (NOT Yet Met)

| # | Requirement | Current Status | Gap |
|---|-------------|---------------|------|
| 1 | **持续暴雨环境音 (3D spatial audio, varies per scene)** | Rain plays via `AudioStreamPlayer2D` (not 3D). Heavy rain blends at high despair. Spatial audio is 2D only. | **GAP** — Need 3D spatial positioning for rain; heavy rain needs better per-scene variation; subway rumble sound missing |
| 2 | **城市环境音 (distant traffic, subway rumble)** | `city_hum.wav` is a generic drone. No specific traffic sounds, no subway rumble. | **GAP** — Needs dedicated traffic/subway audio streams and per-scene activation |
| 3 | **NPC对话触发时背景音乐微妙变化** | No background music system exists. | **GAP** — Greenfield: needs BGM system, music assets, NPC dialogue→BGM triggers |
| 4 | **幻觉等级≥5时音效失真/扭曲** | Despair-based distortion exists in AudioManager. Hallucination level is computed in NarrativeManager but has **no audio hook**. | **GAP** — Need hallucination→audio effects wiring (low-pass filter, reverb, delay at level ≥ 5) |
| 5 | **结局音乐** | No music system, no ending music assets. | **GAP** — Needs ending music stream and trigger integration |

### User Scenarios

- **Scenario A (3D heavy rain):** Player starts in office — rain is heard as distant through walls (spatialized 3D audio with obstruction simulation). On the street, rain is overhead — full 3D spatial presence. In the underpass, rain is muffled and spatially displaced (heard from entrance).
- **Scenario B (City ambience):** Player on the street hears distant traffic rumble from the bridge direction and a periodic subway tremor from below. In the lobby, traffic is muffled but subway tremor is felt. In the underpass, the subway rumble is close and resonant.
- **Scenario C (NPC→BGM change):** Player approaches the Stranger NPC. A subtle, melancholic piano motif fades in. When dialogue starts, the BGM volume lowers (ducking) while a counter-melody adds tension. After dialogue ends, BGM fades back to ambient state.
- **Scenario D (Hallucination audio):** Player's hallucination level reaches 5 in the underpass. The rain audio begins to phase/wobble (low-frequency oscillation), footsteps echo unnaturally (additional reverb), and the city hum becomes dissonant. At level 7+, audio dropout/glitch effects occur.
- **Scenario E (Ending music):** Player triggers the subway ending. A full cinematic music piece plays over the credits scene, matching the ending type (keep_walking = hopeful/forward, turn_back = melancholy, stay = ambient/ambiguous).

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project was built incrementally:

1. **Issue #48 (Sound System)** — Scoped to ambient audio (rain, city hum) and dialogue-triggered footsteps. Music was explicitly out of scope.
2. **Issue #157 (Ambient Sound)** — Added movement-triggered footsteps. Scoped to closing the footstep gap.
3. **Issue #214 (Hallucination / Borgesian Rules)** — Implemented hallucination level computation and visual parameters. Audio effects were deferred — only visual/UI hallucination effects were implemented.

The prerequisites for #219 require:
- **#213 (Rainy Night Prometheus scaffold)** — The sub-project structure that this feature targets
- The hallucination system (#214) must be merged to provide hallucination level data
- The AudioManager (#48) provides the audio infrastructure to extend

### Why Change Now?

1. **All prerequisite systems are merged** — AudioManager, StateSystem, NarrativeManager (hallucination), PlayerController, SceneManager all exist.
2. **Atmospheric narrative demands music** — The "rainy night at the edge of reality" premise is incomplete without music that reacts to NPC encounters and narrative state.
3. **Hallucination is currently only visual** — The dissociation effect is only half-implemented without audio distortion. Hallucination level ≥ 5 should feel like reality is breaking down *auditorily* too.
4. **Ending impact requires music** — The 3 ending paths (keep_walking, turn_back, stay) need musical identity to make the conclusion emotionally resonant.
5. **3D spatial audio technology is available** — `AudioStreamPlayer3D` in Godot 4.7 supports positional audio with attenuation, which the current 2D-based system doesn't use.

### Previous Constraints & Design Decisions

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static types) |
| Sound system | `AudioManager` autoload with `AudioStreamPlayer2D` players |
| Audio API | `AudioStreamPlayer2D` (2D), `AudioStreamPlayer3D` (available but unused), `AudioEffectBus` effects |
| State system | Tri-axis via `StateSystem` (hope/despair, conviction, will 0–10) |
| Hallucination | `NarrativeManager` computes level 0–10 per scene with visual params |
| Bus layout | Master + AmbientBus + SFXBus + IndoorBus + UnderpassBus |
| Dialogue engine | Godot Dialogue Manager (`DialogueBalloon`) with `play_sound` effect type |
| Scenes | 7 scenes (office, lobby, street, convenience_store, bridge, underpass, subway_station) |
| Ending system | 3 endings (keep_walking, turn_back, stay) determined by `NarrativeManager.determine_ending()` |
| NPC system | `NPCNode` with `npc_interacted` / `dialogue_completed` signals |
| Audio assets | 7 WAV files, no OGG, no music assets |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change | Est. Lines |
|------|--------|------------------|-----------|
| `gdscripts/audio_manager.gd` | AudioManager | **Major** — Add BGM player with fade/ducking; add 3D rain/city spatial audio; add hallucination→audio wiring; add subway rumble layer; add ending music trigger | +200 |
| `gdscripts/narrative_manager.gd` | NarrativeManager | **Modify** — Emit `hallucination_level_changed` signal for audio wiring (signal exists, may need refinement) | +10 |
| `gdscripts/npc_node.gd` | NPCNode | **Modify** — Emit `npc_dialogue_started` / `npc_dialogue_ended` signals for BGM ducking | +15 |
| `default_bus_layout.tres` | Bus Layout | **Modify** — Add MusicBus, HallucinationFXBus, add delay/chorus/flanger effects | ±15 |

### New Files Needed

| File | Purpose |
|------|---------|
| `gdscripts/bgm_manager.gd` (optional — could merge into AudioManager) | Background music management, track queue, cross-fade, ducking |
| `assets/audio/ambient_music.ogg` | Generic ambient BGM layer (continuous drone-tone bed) |
| `assets/audio/npc_stranger_music.ogg` | Stranger NPC encounter BGM motif |
| `assets/audio/npc_guard_music.ogg` | Guard NPC encounter BGM motif |
| `assets/audio/npc_clerk_music.ogg` | Clerk NPC encounter BGM motif |
| `assets/audio/npc_homeless_music.ogg` | Homeless NPC encounter BGM motif |
| `assets/audio/ending_keep_walking.ogg` | Keep Walking ending music |
| `assets/audio/ending_turn_back.ogg` | Turn Back ending music |
| `assets/audio/ending_stay.ogg` | Stay ending music |
| `assets/audio/traffic_rumble.ogg` | Distant traffic ambient loop |
| `assets/audio/subway_rumble.ogg` | Subway train rumble loop |
| `assets/audio/subway_rumble_close.ogg` | Close subway rumble (underpass variant) |

### Indirectly Affected Modules

| File | Why Affected |
|------|-------------|
| `gdscripts/player_controller.gd` | May need 3D audio listener position sync |
| `gdscripts/scene_base.gd` | May need `_configure_bgm()` virtual method |
| `gdscripts/subway_station.gd` | Wire ending scene → trigger ending music in AudioManager |
| `gdscripts/end_credits.gd` (if exists) | Play ending music during credits |
| `dialogue/*.dialogue` | May add `"play_music"` effect types for subtle triggers |
| `tests/unit/test_audio_manager.gd` | Add tests for BGM, hallucination audio, 3D spatial |
| `tests/integration/test_audio_state_modulation.gd` | Update for hallucination-based modulation |

### Data Flow Impact

#### Current State Modulation Flow (for reference)

```
StateSystem.state_changed(state)
    → AudioManager._on_state_changed(state)
        ├── rain_intensity = clamp((10 - conviction) / 10, 0, 1)
        ├── despair_norm → rain_volume, rain_pitch, hum_volume
        └── despair_norm > 0.5 → enable Master Distortion
```

#### Proposed: Hallucination → Audio Distortion Flow

```
NarrativeManager.hallucination_level_changed(level: int)
    │
    ▼
AudioManager._on_hallucination_level_changed(level)
    ├── if level < 5: disable all hallucination effects
    ├── if level >= 5:
    │     ├── enable AudioEffectLowPassFilter (cutoff varies: 3000→500 Hz as level rises)
    │     ├── enable AudioEffectReverb (intensity proportional to level)
    │     ├── enable AudioEffectDelay (slapback echo, level 7+)
    │     ├── rain_player.pitch_scale → oscillate (±0.1 at 0.5 Hz LFO)
    │     └── city_hum_player.pitch_scale → warble
    └── if level >= 8: intermittent audio dropout (volume → -80 dB for 100ms bursts)
```

#### Proposed: NPC Dialogue → BGM Flow

```
Player approaches NPC
    │
    ├── NPCNode detects proximity (body_entered / get_tree timer)
    │
    ├── NPCNode.npc_dialogue_started(speaker_name)
    │     │
    │     ▼
    │   AudioManager.trigger_bgm_motif(npc_id: String)
    │     ├── fade_in motif track (2s cross-fade)
    │     ├── duck ambient volume (-6 dB)
    │     └── set BGM state to "npc_active"
    │
    ├── Dialogue started (DialogueBalloon opens)
    │     │
    │     ▼
    │   AudioManager.set_bgm_ducking(true)
    │     ├── tween BGM volume → -8 dB (dialogue ducking)
    │     └── tween ambient → -3 dB
    │
    └── Dialogue ended
          │
          ▼
        AudioManager.set_bgm_ducking(false)
          ├── tween BGM volume → 0 dB
          └── tween ambient → normal
          └── after 5s: fade_out BGM motif (return to ambient bed)
```

#### Proposed: Ending Music Flow

```
Player selects ending choice in subway_ending dialogue
    │
    ├── Dialogue choice has effect: {type: "trigger_event", event: "ending_music"}
    │     │
    │     ▼
    │   AudioManager.set_ending_music(ending_id: String)
    │     ├── cross_fade_to(ending_keep_walking.ogg or ending_turn_back.ogg or ending_stay.ogg)
    │     └── fade_out ambient rain (2s)
    │
    └── Scene transition to end_credits
          │
          ▼
        AudioManager (persists via autoload) → ending music continues
          └── On credits complete → fade_out ending music (2s) → reset
```

### Documents to Create/Update

- [x] `docs/PRD/219-sound-and-bgm-system.md` (this document)
- [ ] `docs/DESIGN/219-sound-and-bgm-system.md` — Plan phase artifact
- [ ] `docs/GAME_DESIGN/` — Audio extended design section

---

## 4. Solution Comparison

### Approach A: Extend Existing AudioManager (Recommended)

**Description:** Add all #219 features directly into the existing `AudioManager` autoload. No new autoloads. BGM tracks are managed as additional `AudioStreamPlayer*` children. Hallucination audio uses existing bus system plus new effect slots. NPC→BGM integration uses existing signal infrastructure.

**Architecture sketch:**
```gdscript
# Additions to AudioManager

# ── BGM Layer ──
var _bgm_player: AudioStreamPlayer       # Main music track
var _motif_player: AudioStreamPlayer     # NPC encounter motif (overlay)
var _ending_bgm_player: AudioStreamPlayer

const BGM_DUCK_DB: float = -8.0
const BGM_CROSSFADE_TIME: float = 2.0
var _bgm_state: String = "ambient"  # "ambient", "npc_active", "ending"

# ── 3D Spatial Audio ──
var _rain_3d_player: AudioStreamPlayer3D
var _city_3d_player: AudioStreamPlayer3D
var _subway_player: AudioStreamPlayer3D

# ── Hallucination Audio ──
var _hallucination_level: int = 0
var _hallucination_timer: Timer          # LFO modulation timer

# ── Signals to connect ──
func _connect_npc_signals() -> void:
    # Connect to all NPCNode instances via group "npcs"
    for npc in get_tree().get_nodes_in_group("npcs"):
        if npc.has_signal("npc_dialogue_started"):
            npc.dialogue_started.connect(_on_npc_dialogue_started)
        if npc.has_signal("dialogue_completed"):
            npc.dialogue_completed.connect(_on_npc_dialogue_ended)

func _connect_hallucination_signals() -> void:
    var nm := get_node_or_null("/root/NarrativeManager")
    if nm and nm.has_signal("hallucination_level_changed"):
        nm.hallucination_level_changed.connect(_on_hallucination_level_changed)
```

**Implementation sub-components:**

| Sub-feature | Implementation Pattern |
|-------------|----------------------|
| 3D rain spatial | New `AudioStreamPlayer3D` child, positioned at scene origin. Scene scripts set listener position relative to rain source. Add rain obstruction logic (indoor = low-pass attenuate). |
| BGM system | `_bgm_player` (ambient bed) + `_motif_player` (NPC overlay). Both use new `MusicBus`. Cross-fade via Tween. Ducking via volume automation. |
| Subway rumble | New `AudioStreamPlayer3D` attached to AudioManager. Scene `register_scene()` enables/disables based on profile. Underpass variant has close proximity. |
| NPC→BGM triggers | NPCNode emits signals. AudioManager receives, fades in motif, sets ducking, auto-fades out after dialogue ends + timeout. |
| Hallucination audio | `_on_hallucination_level_changed(level)` added to AudioManager. Level ≥ 5 enables effect stack on a `HallucinationFXBus` (low-pass + reverb + delay). LFO timer modulates pitch/volume of rain and hum. |
| Ending music | `set_ending_music(ending_id)` method. Cross-fades rain/bgm to ending track. CinemaBus for final audio. |

**Pros:**
- Single autoload — audio state is centralized, no coordination between managers
- Existing infrastructure reused (bus system, cross-fade tween patterns, scene registration)
- NPC signal integration follows existing pattern (AudioManager already connects to StateSystem)
- BGM ducking is straightforward volume tweening
- Hallucination audio integrates directly with existing distortion effect

**Cons:**
- AudioManager grows significantly (~200+ lines)
- BGM motif management may be cleaner as a separate BgmManager
- 3D spatial audio may conflict with existing 2D player positions

**Risk:** Low-Medium — This is additive on a well-tested autoload. Main risk is 3D listener positioning.

**Effort:** Medium (5–8 days)

### Approach B: Dedicated BgmManager + Extended AudioManager

**Description:** Split BGM/music concerns into a new `BgmManager` autoload. AudioManager keeps ambient/3D/hallucination. BgmManager handles music tracks, NPC motif queue, ducking, and ending music. Both are autoloads that coordinate via signals and shared bus assignments.

**Architecture sketch:**
```
AudioManager (keeps existing)
    ├── ambient layer (rain, city hum, subway rumble)
    ├── SFX (footsteps)
    ├── bus profile switching
    ├── state modulation (conviction/despair)
    ├── hallucination audio effects
    └── 3D spatial positioning

BgmManager (new autoload)
    ├── _ambient_bed: AudioStreamPlayer
    ├── _motif_player: AudioStreamPlayer (NPC encounters)
    ├── _ending_player: AudioStreamPlayer
    ├── track queue with cross-fade
    ├── NPC signal connections
    ├── dialogue ducking automation
    └── ending music trigger
```

**Pros:**
- Separation of concerns — BGM logic is self-contained
- AudioManager doesn't grow unboundedly
- Easier to test BGM independently
- Can develop BGM manager without risking ambient/rain regression

**Cons:**
- Two autoloads need to coordinate (bus access, volume levels)
- More files, more initialization ordering concerns
- NPC→BGM requires connecting across two managers
- Ending music needs AudioManager cross-fade coordination (or sequenced handoff)

**Risk:** Low but unnecessary complexity for the project size (7 scenes, 4 NPCs)

**Effort:** Medium (6–9 days)

### Approach C: Minimal — Audio as Effects Only (No BGM)

**Description:** Implement only hallucination audio distortion and 3D spatial rain/city enhancement. Skip all music (BGM system, NPC→BGM, and ending music). The existing ambient system covers atmospheric needs.

**Pros:**
- Significantly less work (~2–3 days)
- No music assets needed
- Hallucination audio is the highest-impact change for immersion

**Cons:**
- Issue #219's ACs for NPC BGM and ending music are completely unmet
- Game lacks emotional audio arc (no narrative music)
- The "微妙变化" (subtle shifts) in BGM during NPC encounters is core to narrative feel

**Risk:** Low effort but feature-incomplete.

**Effort:** Small (2–3 days)

### Recommendation

→ **Approach A (Extend Existing AudioManager)** because:
1. Single autoload keeps audio state coherent — all audio management in one place
2. The project has only 7 scenes and 4 NPCs — a dedicated BgmManager is over-engineering
3. Existing patterns (signal connection, tween cross-fade, bus switching) directly apply to all new features
4. AudioManager is already a mature, well-tested autoload with 346 lines — adding ~200 lines is proportional
5. 3D spatial audio extends naturally from 2D by adding `AudioStreamPlayer3D` children alongside existing players
6. NPC→BGM connection uses the same signal pattern as `StateSystem.state_changed` → `_on_state_changed`

---

## 5. Boundary Conditions & Acceptance Criteria

### Acceptance Criteria (from Issue #219)

- [ ] **AC1: 持续暴雨环境音（3D空间音频，随场景变化）**
  - [ ] Rain uses `AudioStreamPlayer3D` with spatial attenuation (not 2D)
  - [ ] Heavy rain (`rain_heavy.wav`) plays with higher weight in outdoor scenes (street, bridge) and late-game scenes (underpass, subway)
  - [ ] Rain intensity varies by scene: indoor scenes (office, lobby, store) have lower volume + low-pass muffling; outdoor scenes have full spatial presence
  - [ ] Player can perceive rain directionality (e.g., rain on bridge comes from above-front; rain in underpass is heard from entrance behind)
  - **Verification:** Enable 3D audio, walk through each scene. Rain has positional presence relative to player. Outdoor scenes have full stereo/spatial rain. Indoor rain is muffled.

- [ ] **AC2: 城市环境音（远处车流、地铁轰鸣）**
  - [ ] Distant traffic rumble (`traffic_rumble.wav`) plays on street, bridge, and lobby (muffled)
  - [ ] Subway rumble (`subway_rumble.wav`) plays periodic low-frequency pulses in underpass and subway station
  - [ ] Subway rumble has close proximity variant in underpass (resonant, loud)
  - [ ] All city ambience is spatialized 3D
  - **Verification:** Stand on street — distant traffic heard. Enter underpass — subway rumble is loud and resonant. Exit to subway station — subway rumble is distant but present.

- [ ] **AC3: NPC对话触发时背景音乐微妙变化**
  - [ ] Ambient BGM bed plays continuously (subtle drone/pad — not silence between NPC encounters)
  - [ ] When player approaches an NPC, a unique BGM motif fades in over 2 seconds
  - [ ] During dialogue, BGM volume ducks by -6 to -8 dB (dialogue ducking)
  - [ ] After dialogue ends, BGM motif stays for 5 seconds then cross-fades back to ambient bed
  - [ ] Each NPC has a distinct motif (Stranger = melancholic piano, Guard = low brass, Clerk = warm synth, Homeless = lonely guitar)
  - **Verification:** Walk near each NPC → unique BGM motif plays. Start dialogue → volume ducks. End dialogue → motif fades after 5s.

- [ ] **AC4: 幻觉等级≥5时音效失真/扭曲（低通滤波/混响/延迟）**
  - [ ] At hallucination level 5-6: rain/city hum gain additional low-pass filter (cutoff ~3000 Hz → slides to 1500 Hz) + subtle reverb
  - [ ] At hallucination level 7-8: pitch oscillation applied to rain (LFO ±0.1 at 0.5 Hz), slapback delay on ambient
  - [ ] At hallucination level 9-10: intermittent audio dropout (50-100ms silence bursts every 3-5s), extreme distortion, phaser/flanger
  - [ ] Hallucination audio effects are additive on top of existing despair-based modulation
  - [ ] When hallucination level drops below 5, effects fade out over 1 second
  - **Verification:** Set `hallucination_level = 5` in NarrativeManager. Rain becomes muffled + reverby. Set to 8 → pitch wobbles, delay echoes. Set to 10 → audio dropouts.

- [ ] **AC5: 结局音乐**
  - [ ] Each ending path has a unique music track (keep_walking = hopeful orchestral, turn_back = melancholy piano, stay = ambiguous ambient)
  - [ ] Ending music starts as the ending dialogue concludes and the scene transitions to credits
  - [ ] Music plays through the full credits display without looping (one-shot)
  - [ ] Music fades out when returning to menu / new game
  - **Verification:** Complete each of the 3 ending paths → corresponding music plays over credits. Fades gracefully on return.

### Normal Path

1. Player starts game in office → ambient BGM bed plays (subtle drone) + 3D rain (muffled, distant) + city hum (distant)
2. Player walks to lobby → rain spatializes (partially obstructed by building geometry), BGM continues ambient
3. Player approaches guard NPC → guard BGM motif (low brass) fades in over 2s
4. Player initiates dialogue with guard → BGM ducks -6dB, ambient ducked -3dB
5. Dialogue ends → BGM motif holds for 5s then cross-fades back to ambient bed
6. Player proceeds through scenes (store, bridge, underpass) → each NPC encounter triggers unique BGM motif
7. Hallucination level reaches 5 in underpass → rain audio distorts (low-pass + reverb added), city hum warbles
8. Player reaches subway station → ending determined → ending music plays
9. Credits scene plays with continuing ending music → music fades on return to menu

### Edge Cases

1. **Rapid NPC approach/leave:** Player walks past an NPC within 2 seconds. BGM motif starts fading in but player is already out of range. Fade should be cancelled and reversed in the same tween — no audio pop or cut.
2. **Two NPCs in proximity:** Player stands between guard and clerk (both in lobby). Only ONE BGM motif should play (prioritize closest or most recent). AudioManager tracks `_active_npc_id` to prevent motif overlap.
3. **Hallucination change during dialogue:** Player's hallucination level crosses 5 while in the middle of NPC dialogue. Audio effects should blend in smoothly (1s tween), not pop.
4. **Scene transition during hallucination:** Player transitions from underpass (hallucination 7) to subway station (hallucination 9). Effect intensity should smooth-transition (re-target existing tweens).
5. **Ending triggered while NPC nearby:** Player starts ending dialogue while near an NPC. Ending music should take priority — fade out BGM motif, fade in ending music.
6. **No BGM assets loaded:** If music files are missing, game continues silently (ambient-only). Graceful degradation.
7. **Rapid scene transitions:** Back-to-back scene changes should abort in-progress BGM fades and start new ones.

### Failure Paths

1. **Missing BGM asset file:** AudioManager logs push_warning, continues without BGM. Ambient audio still plays.
2. **Missing 3D audio asset:** Falls back to 2D AudioStreamPlayer2D for rain.
3. **NarrativeManager autoload not found:** Hallucination audio effects are skipped. `get_node_or_null("/root/NarrativeManager")` returns null.
4. **BGM bus not found:** Falls back to Master bus. Logs push_warning.
5. **NPC node has no `dialogue_completed` signal:** AudioManager's motif fade-out timer triggers based on timeout (5s after last signal). Graceful.
6. **Bus effect index mismatch:** Effect indices are looked up dynamically by type (same pattern as `_find_bus_indices()` in AudioManager).

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #213 — Rainy Night Prometheus project scaffold | ✅ Closed | Prerequisite project structure |
| #48 — Sound System (AudioManager autoload) | ✅ Merged | Foundation audio infrastructure |
| #157 — Ambient Sound (movement footsteps) | ✅ Merged | AudioManager maturity |
| #214 — Hallucination / Borgesian Rules | ✅ Merged (check) | Hallucination level computation and signal |
| NPC system (#54, #59, #152) | ✅ Merged | NPCNode with signal infrastructure |
| Ending system (#56, #155) | ✅ Merged | Ending determination and credits scene |
| StateSystem tri-axis | ✅ Merged | State-based audio modulation |
| Audio assets: rain, city hum, footsteps | ✅ Present in assets/audio/ | Existing sound layers |
| Music assets (BGM motifs, ending tracks) | ❌ Need creation | **High** — All music requires composition or sourcing |
| 3D audio assets (traffic rumble, subway rumble) | ❌ Need creation | **Medium** — New ambient layers needed |

### Blocks

| Future Work | Priority |
|-------------|----------|
| All further audio refinement | P1 — After BGM motifs are in place |
| Voice-over / narration | P3 — If ever scoped |
| Dynamic music system (adaptive layers) | P3 — Future enhancement |

### Preparation Needed

- [ ] Source/compose BGM assets: ambient bed, 4 NPC motifs, 3 ending tracks
- [ ] Source/compose 3D ambient assets: traffic rumble, subway rumble (near + far variants)
- [ ] Design new audio buses: MusicBus, HallucinationFXBus, CinemaBus (for ending)
- [ ] Update AudioManager with 3D player (AudioStreamPlayer3D) alongside existing 2D players
- [ ] Add NPC group registration (ensure all NPCNode instances are in group "npcs")
- [ ] Wire `hallucination_level_changed` signal from NarrativeManager (signal exists but may need emission timing refinement)
- [ ] Decide BGM ducking levels: -6 dB (dialogue), -3 dB (ambient), -8 dB (BGM)
- [ ] Agree on hallucination→audio mapping parameters (cutoff frequencies, reverb mix, LFO rate)

---

## 7. Spike / Experiment (Optional — depth/standard only)

> Skipped per `depth/standard` label. The recommend approach (Extend AudioManager) follows established patterns. The main uncertainty is the quality/styling of music assets, which is a creative rather than technical risk. AudioManager extension follows the same tween/bus pattern used for cross-fade and state modulation.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

### Current State Summary

The existing codebase has a mature ambient sound system built from Issues #48 and #157:

**AudioManager autoload** (`gdscripts/audio_manager.gd`, 346 lines):
- Rain loop (`rain_loop.wav`) + heavy rain variant (`rain_heavy.wav`), modulated by conviction/distance
- City hum (`city_hum.wav`), modulated by despair
- Dialogue-triggered footstep sounds via `play_sound` effect type
- Movement-triggered footsteps in `PlayerController._physics_process()`
- State modulation: conviction → rain intensity, despair → volume/pitch/distortion
- Per-scene bus profiles: indoor (LowPass 4kHz), outdoor (none), underpass (Reverb + LowPass 2kHz)
- Scene transition cross-fade via Tween
- Bus layout: Master (Distortion), AmbientBus, SFXBus, IndoorBus, UnderpassBus

**What this issue (#219) adds:**

| Feature | Implementation Strategy |
|---------|----------------------|
| 3D spatial rain/city ambience | Add `AudioStreamPlayer3D` children to AudioManager. 2D players remain as fallback. Scene position sync via listener. |
| Traffic + subway rumble | New `AudioStreamPlayer3D` for traffic_rumble.wav and subway_rumble.wav. Activated per-scene via `register_scene()` profile. |
| BGM system (ambient bed + NPC motifs) | `_bgm_player` + `_motif_player` as `AudioStreamPlayer` children (non-spatial). Uses new `MusicBus`. Cross-fade via `create_tween()`. |
| NPC→BGM ducking | Connect to NPCNode signals. `_active_npc_id` state. Motif fade-in, dialogue ducking, auto-fade-out after 5s timeout. |
| Hallucination audio effects | `_on_hallucination_level_changed(level)` method. Level ≥ 5: enable `HallucinationFXBus` chain. LFO timer modulates rain pitch. |
| Ending music | `set_ending_music(ending_id)` → cross-fade to track. CinemaBus for final audio. Fade out on menu return. |

### Implementation Priority Order

1. **AudioManager extension:** Add BGM player, 3D players, new API methods (foundation for everything else)
2. **Bus layout update:** Add MusicBus, HallucinationFXBus, CinemaBus with effect chains
3. **3D spatial rain + city hum:** Convert rain/hum from AudioStreamPlayer2D → AudioStreamPlayer3D
4. **Traffic + subway rumble:** Source assets, add players, wire per-scene profiles
5. **Hallucination audio:** Wire `hallucination_level_changed` signal, implement effect mapping
6. **BGM system:** Source ambient bed asset, implement continuous playback with per-scene variation
7. **NPC→BGM integration:** Source 4 motif assets, wire NPCNode signals, implement ducking
8. **Ending music:** Source 3 ending tracks, wire ending dialogue `trigger_event` → AudioManager
9. **Testing:** Verify each AC independently; test cross-feature interactions (hallucination + NPC + ending)

### Risk Summary

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Music assets unavailable (creative bottleneck) | High | High | Start asset sourcing immediately; use placeholder tones for dev testing |
| 3D spatial audio conflicts with 2D player transform | Low | Medium | AudioManager attaches 3D players to scene root; position sync in `_process` |
| Hallucination effect stack overwhelms audio hardware | Low | Low | Limit concurrent effects; use bus-level wet/dry mix, not per-player effects |
| NPC→BGM motif overlap (two NPCs near each other) | Medium | Medium | `_active_npc_id` guard; queue secondary motif for 1-at-a-time playback |
| Dialogue ducking conflicts with hallucination effects | Low | Low | Ducking is volume-based; hallucination is effect-based. Independent layers. |
| BGM cross-fade pop due to tween re-targeting | Low | Low | Use `tween.kill()` + `create_tween()` pattern (already proven in cross_fade_ambient) |

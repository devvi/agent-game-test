# Tasks: #48 — Sound System（音效系统）

> Parent Issue: #48
> Priority: medium
> Estimated: 3-5 days
> Prerequisite: #45, #50 (merged), #46 (merged), #55 (merged)
> Design Reference: `docs/DESIGN/48-sound-system.md`

---

## Task Breakdown

### Phase 1 — Audio Infrastructure (P0)

**Rationale:** The AudioManager autoload and bus layout are the foundation everything else depends on. Build and test these first.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Create AudioBus layout with 5 buses (Master, AmbientBus, SFXBus, IndoorBus, UnderpassBus) and effect chains | `default_bus_layout.tres` | None | 0.5d |
| T2 | Create `AudioManager` autoload with rain + city hum players, footstep player, scene registration API | `gdscripts/audio_manager.gd` | T1 | 1.0d |
| T3 | Implement state modulation logic: `_on_state_changed()`, despair→distortion mapping | `gdscripts/audio_manager.gd` | T2 | 0.5d |
| T4 | Implement cross-fade logic: `cross_fade_ambient()` with Tween | `gdscripts/audio_manager.gd` | T2 | 0.5d |
| T5 | Implement footstep cooldown and surface mapping | `gdscripts/audio_manager.gd` | T2 | 0.25d |

#### T1 Details — Bus Layout

Create `default_bus_layout.tres`:

```gdscript
# Bus structure:
# 0: Master
#    └─ AudioEffectDistortion (bypass: true, controlled by despair)
# 1: AmbientBus → Master
#    (rain_loop, rain_heavy, city_hum play here)
# 2: SFXBus → Master
#    (footsteps play here)
# 3: IndoorBus → Master
#    └─ AudioEffectLowPassFilter (cutoff_hz: 4000, bypass: true)
# 4: UnderpassBus → Master
#    ├─ AudioEffectReverb (room_size: 0.8, damping: 0.6)
#    └─ AudioEffectLowPassFilter (cutoff_hz: 2000)
```

**Validation:** Load in Godot editor, verify all 5 buses exist with correct effect chains.

#### T2 Details — AudioManager.gd Core

- `extends Node`, `class_name AudioManager`
- Register as autoload in Project Settings with name "AudioManager"
- Preload all 7 audio streams on `_ready()`
- Create 3 `AudioStreamPlayer2D` (rain, city_hum, footstep) as children
- `register_scene(scene_id)` → set bus profile + distance factor
- `set_bus_profile(profile)` → switch audio bus assignment
- `play_footstep(surface)` → cooldown check, select stream, play
- `cross_fade_ambient(target, duration)` → tween volume_db

**Validation:** Unit test TC1-TC5 pass.

#### T3 Details — State Modulation

- Connect to `StateSystem.state_changed` on `_ready()`
- Formula: `rain_intensity = clamp((10 - conviction) / 10, 0, 1)`
- `despair_normalized = clamp(despair / 10, 0, 1)` (for `GameState`, divide by 100)
- `rain.volume_db = lerp(-24, -6, intensity * distance_factor)`
- `rain.pitch_scale = lerp(1.0, 1.3, intensity)`
- `city_hum.volume_db = lerp(-20, -8, despair_normalized)`
- Enable/disable Distortion effect based on despair threshold (> 0.5)

**Validation:** Unit test TC2-TC3 pass.

### Phase 2 — Audio Assets (P1)

**Rationale:** Audio assets can be sourced/generated in parallel with infrastructure. Creative assets need time and iteration.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T6 | Source or generate `rain_loop.ogg` (10-30s seamless loop, mono 22050Hz) | `assets/audio/rain_loop.ogg` | None | 0.5d |
| T7 | Source or generate `rain_heavy.ogg` (heavier rain variant) | `assets/audio/rain_heavy.ogg` | T6 | 0.25d |
| T8 | Source or generate `city_hum.ogg` (low city drone) | `assets/audio/city_hum.ogg` | None | 0.5d |
| T9 | Source or generate 3 footstep sounds | `assets/audio/footstep_office.ogg`, `assets/audio/footstep_street.ogg`, `assets/audio/footstep_underpass.ogg` | None | 0.5d |
| T10 | Source or generate `underpass_ambient.ogg` | `assets/audio/underpass_ambient.ogg` | None | 0.25d |

#### T6-T10 Details — Audio Asset Sourcing

**Open source recommendations:**
- `rain_loop.ogg`: [freesound.org](https://freesound.org) search "rain loop" CC0
- `city_hum.ogg`: [freesound.org](https://freesound.org) search "city ambient drone"
- Footsteps: [soniss.com GDC bundles](https://soniss.com/gdc-bundle/) (royalty-free)
- Fallback: Generate with sfxr/bfxr or Audacity synthesis

**Validation:** Each file loads in Godot without error. All loops are seamless (no click at loop point).

### Phase 3 — Scene Integration (P0)

**Rationale:** Each scene must configure its ambient audio and bus profile. This is where the AudioManager gets wired to the existing scene graph.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T11 | Add `_configure_ambient_audio()` virtual method to `SceneBase`, call it from `_ready()` | `gdscripts/scene_base.gd` | T2 | 0.25d |
| T12 | Wire SceneManager's `transition_started` to AudioManager cross-fade | `gdscripts/scene_manager.gd` | T2, T4 | 0.25d |
| T13 | Implement underpass ambience: bus profile, distance factor | `gdscripts/underpass.gd` | T11 | 0.25d |
| T14 | Implement office ambience: indoor bus profile, min distance factor | `gdscripts/office.gd` | T11 | 0.25d |
| T15 | Convert street.gd to extend SceneBase; implement outdoor ambience | `gdscripts/street.gd` | T11 | 0.25d |
| T16 | Implement bridge ambience (outdoor bus, high distance factor) | `gdscripts/bridge.gd` | T11 | 0.25d |
| T17 | Implement lobby ambience (indoor bus profile) | `gdscripts/lobby.gd` | T11 | 0.25d |
| T18 | Implement store ambience (indoor bus profile) | `gdscripts/store.gd` | T11 | 0.25d |
| T19 | Implement subway station ambience (indoor, max distance factor) | `gdscripts/subway_station.gd` | T11 | 0.25d |

#### T11 Details — SceneBase `_configure_ambient_audio()`

```gdscript
# In SceneBase._ready(), after _configure_environmental_text():
_configure_ambient_audio()

# New virtual method:
func _configure_ambient_audio() -> void:
    var am := get_node_or_null("/root/AudioManager")
    if am and am.has_method("register_scene"):
        am.register_scene(scene_id)
```

**Validation:** Each scene's `_ready()` calls `_configure_ambient_audio()` correctly.

### Phase 4 — Dialogue Integration (P1)

**Rationale:** Dialogue-triggered footsteps require changes to `DialogueRunner._apply_effects()`. Lower priority than ambient audio.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T20 | Add `"play_sound"` effect type to `DialogueRunner._apply_effects()` | `gdscripts/dialogue_runner.gd` | T2, T5 | 0.25d |

#### T20 Details — play_sound Effect

```gdscript
# In dialogue_runner.gd, match block:
"play_sound":
    var am := get_node_or_null("/root/AudioManager")
    if am and am.has_method("play_footstep"):
        var surface: String = effect.get("surface", "")
        if surface.is_empty():
            # Infer from current scene — AudioManager handles mapping
            surface = am.get_surface_for_scene(get_scene_id())
        am.play_footstep(surface)
```

**Dialogue JSON example:**
```json
{
  "id": "walk_to_door",
  "text": "Walk to the door.",
  "effects": [{ "type": "play_sound", "surface": "office" }],
  "next_node": "lobby_arrival"
}
```

**Validation:** Integration test TC9-TC11 pass.

### Phase 5 — Testing & Polish (P1)

**Rationale:** Test all paths, edge cases, and failure modes. Polish timing and feel.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T21 | Write unit test `test_audio_manager.gd` (TC1-TC6) | `tests/unit/test_audio_manager.gd` | T2 | 0.5d |
| T22 | Write integration test `test_audio_state_modulation.gd` (TC2-TC3, TC13-TC14) | `tests/integration/test_audio_state_modulation.gd` | T3 | 0.5d |
| T23 | Write integration test `test_audio_scene_transition.gd` (TC7-TC8) | `tests/integration/test_audio_scene_transition.gd` | T4, T12 | 0.5d |
| T24 | Write integration test `test_audio_footstep_dialogue.gd` (TC9-TC11) | `tests/integration/test_audio_footstep_dialogue.gd` | T20 | 0.5d |
| T25 | Run all tests, fix failures, verify no regression | All test files | T21-T24 | 0.5d |

---

## Dependency Graph

```
Phase 1 — Audio Infrastructure
├─ T1 (bus layout) ──────┐
├─ T2 (AudioManager) ←───┤
├─ T3 (state modulation) ← T2
├─ T4 (cross-fade) ←──── T2
└─ T5 (footstep) ←────── T2
                            │
Phase 2 — Audio Assets     │
├─ T6 (rain_loop.ogg) ─────┤
├─ T7 (rain_heavy.ogg) ← T6│
├─ T8 (city_hum.ogg) ──────┤
├─ T9 (footsteps) ─────────┤
└─ T10 (underpass_ambient) ┘
                            │
Phase 3 — Scene Integration
├─ T11 (SceneBase) ←─ T2   │
├─ T12 (SceneManager) ← T2,T4
├─ T13 (underpass) ←─ T11  │
├─ T14 (office) ←─── T11   │
├─ T15 (street) ←─── T11   │
├─ T16 (bridge) ←─── T11   │
├─ T17 (lobby) ←─── T11    │
├─ T18 (store) ←─── T11    │
└─ T19 (subway) ←── T11    │
                            │
Phase 4 — Dialogue          │
└─ T20 (play_sound) ← T2,T5│
                            │
Phase 5 — Testing           │
├─ T21 (unit test) ←── T2  │
├─ T22 (state test) ←─ T3  │
├─ T23 (transition) ← T4,T12
├─ T24 (footstep) ←─ T20   │
└─ T25 (regression) ← all  │
                            │
All done ───────────────────┘
```

## Summary: Changed Files

| File | Type | Est. Lines |
|------|------|-----------|
| `gdscripts/audio_manager.gd` | **New** | +250 |
| `default_bus_layout.tres` | **New** | +30 |
| `assets/audio/rain_loop.ogg` | **New** | N/A |
| `assets/audio/rain_heavy.ogg` | **New** | N/A |
| `assets/audio/city_hum.ogg` | **New** | N/A |
| `assets/audio/footstep_office.ogg` | **New** | N/A |
| `assets/audio/footstep_street.ogg` | **New** | N/A |
| `assets/audio/footstep_underpass.ogg` | **New** | N/A |
| `assets/audio/underpass_ambient.ogg` | **New** | N/A |
| `gdscripts/scene_base.gd` | Modify | +15 |
| `gdscripts/scene_manager.gd` | Modify | +5 |
| `gdscripts/dialogue_runner.gd` | Modify | +10 |
| `gdscripts/underpass.gd` | Modify | +8 |
| `gdscripts/office.gd` | Modify | +5 |
| `gdscripts/street.gd` | Modify | +8 |
| `gdscripts/bridge.gd` | Modify | +5 |
| `gdscripts/lobby.gd` | Modify | +5 |
| `gdscripts/store.gd` | Modify | +5 |
| `gdscripts/subway_station.gd` | Modify | +5 |
| `tests/unit/test_audio_manager.gd` | **New** | +80 |
| `tests/integration/test_audio_state_modulation.gd` | **New** | +60 |
| `tests/integration/test_audio_scene_transition.gd` | **New** | +60 |
| `tests/integration/test_audio_footstep_dialogue.gd` | **New** | +50 |

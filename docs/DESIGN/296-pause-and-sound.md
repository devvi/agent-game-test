# Design: 暂停与音效 — Pause & Sound

> **Parent Issue:** #296
> **Agent:** game-plan-agent (cron-poller inline, depth/light)
> **Date:** 2026-07-30
> **Approach:** A — FSM-Embedded Pause + Signal-Driven Autoload AudioEngine (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                         ← MODIFIED: +AudioEngine autoload, +pause InputMap
├── gdscripts/
│   ├── game_state_machine.gd             ← MODIFIED: +PAUSED state, Escape input, PauseOverlay ref
│   ├── pause_overlay.gd                  ← NEW: CanvasLayer script (~40 lines)
│   ├── audio_engine.gd                   ← NEW: Autoload (~80 lines)
│   ├── paddle.gd                         ← unchanged (frozen flag + set_frozen() already exist for pause)
│   ├── ball.gd                           ← unchanged (delta <= 0.0 guard already handles pause)
│   └── scoring_manager.gd                ← unchanged (already emits scored/match_over signals)
├── scenes/
│   └── game.tscn                         ← MODIFIED: +PauseOverlay CanvasLayer node
└── tests/
    ├── test_pause.gd                     ← NEW: Pause state transition tests
    └── test_audio_engine.gd              ← NEW: Audio synthesis unit tests
```

**Design philosophy:** Both features are additive — pause extends the existing 5-state FSM with a 6th `PAUSED` state; audio is a new autoload that listens to existing signals and synthesizes sounds. Neither feature requires architectural restructuring. The FSM's `match` dispatch pattern and `_transition_lock` mechanism are directly reusable for pause. The existing `GameManager` autoload pattern is reused for `AudioEngine`.

### Key Architectural Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | PAUSED state location | Add to existing `enum State` in `game_state_machine.gd` | FSM already owns paddle freeze, ball lifecycle, UI visibility — natural extension |
| 2 | Pause input | `Input.is_action_just_pressed("ui_cancel")` in FSM's `_input()` | `ui_cancel` is Godot's built-in action bound to Escape — no InputMap pollution needed |
| 3 | AudioEngine location | Autoload singleton (`project.godot` `[autoload]`) | Follows `GameManager` pattern — accessible from any script via `AudioEngine.play_*()` |
| 4 | Audio synthesis | `AudioStreamGenerator` + `push_frame()` with `PackedVector2Array` waveforms | Zero external files, Godot 4.x built-in API |
| 5 | Sound triggers | Ball/Paddle call `AudioEngine.play_*()` directly in collision handlers | Simple, minimal; ScoringManager signals connect in AudioEngine's `_ready()` |
| 6 | Pause → Audio | On PAUSED enter: stop AudioStreamGenerator; on exit: resume | Keeps audio state consistent with game state |

### State Transition Diagram (extended)

```
                                                [Escape]
                                                  ↕
     MENU ──[SPACE]──► SERVING ──[1s]──► PLAYING ⇌ PAUSED
       ▲                                    │
       │                          [scored]  │
       │                                    ▼
       │                         SCORED ──[1s]──┐
       │                           │            │
       │              [match_over] │ [no win]──┘
       │                           ▼
       └──────────[SPACE]──── GAME_OVER
```

New states for #296:

| State | UI Visible | Input Active | Ball Moving | Paddle Moving | Audio |
|-------|-----------|-------------|-------------|---------------|-------|
| `PAUSED` | PauseOverlay | Escape only | No | No (`frozen=true`) | Paused |

---

## 2. New Components — Detailed Design

### 2.1 `pause_overlay.gd`

- **File:** `mini-pong/gdscripts/pause_overlay.gd`
- **Type:** CanvasLayer script (`extends CanvasLayer`)
- **Line estimate:** ~40 lines

```gdscript
extends CanvasLayer
## PauseOverlay — semi-transparent mask + "暂停" label, shown during PAUSED state.
## Follows the CanvasLayer + ColorRect + Label pattern from StartMenu/GameOverScreen (#292).

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label

func _ready() -> void:
    hide()

func show_overlay() -> void:
    visible = true

func hide_overlay() -> void:
    visible = false
```

**TSCN structure (added to `game.tscn`):**

```
PauseOverlay (CanvasLayer, layer=10)
├── ColorRect (full-screen, modulate=Color(0,0,0,0.6))
└── Label (center, text="暂停", font_size=48, modulate=Color.WHITE)
```

Follows the proven pattern from `StartMenu` (#292): CanvasLayer with high layer index (above GameHUD), ColorRect for dimming, Label for text.

### 2.2 `audio_engine.gd`

- **File:** `mini-pong/gdscripts/audio_engine.gd`
- **Type:** Autoload (`extends Node`)
- **Line estimate:** ~80 lines

```gdscript
extends Node
## AudioEngine — autoload for real-time audio synthesis via AudioStreamGenerator.
## 4 sound effects: paddle_hit, wall_bounce, score, game_over.
## All synthesis uses sin waves with attack/decay envelopes.
## Gracefully degrades when AudioServer is unavailable (headless mode).

const SAMPLE_RATE := 44100

var _playback: AudioStreamGeneratorPlayback = null
var _enabled: bool = false


func _ready() -> void:
    # Guard: AudioServer unavailable in headless mode
    if not AudioServer:
        push_warning("AudioEngine: AudioServer unavailable — audio disabled")
        return

    # Signal connections for event-driven sounds
    if is_instance_valid(GameManager):
        if GameManager.has_signal("scored"):
            GameManager.scored.connect(_on_scored)
        if GameManager.has_signal("match_over"):
            GameManager.match_over.connect(_on_match_over)

    _setup_generator()
    _enabled = true


func _setup_generator() -> void:
    var generator := AudioStreamGenerator.new()
    generator.mix_rate = SAMPLE_RATE
    generator.buffer_length = 0.5  # 500ms buffer, enough for all sound effects
    AudioServer.add_stream_to_bus(generator)
    add_child(generator)
    generator.play()
    _playback = generator.get_playback()
    # Pause until first sound plays — saves CPU by not filling silence
    generator.stream_paused = true


## ── Public API ──

func play_paddle_hit() -> void:
    """High-frequency short blip (~200Hz, 50ms, fast decay)."""
    _play_tone(200.0, 0.05, 0.8)


func play_wall_bounce() -> void:
    """Low-frequency thud (~100Hz, 120ms, slow decay)."""
    _play_tone(100.0, 0.12, 0.6)


func play_score() -> void:
    """3-note ascending arpeggio: C5→E5→G5, 80ms each."""
    _play_tone(523.25, 0.08, 0.7)  # C5
    _play_tone(659.25, 0.08, 0.7)  # E5
    _play_tone(783.99, 0.08, 0.7)  # G5


func play_game_over() -> void:
    """Long fade-out tone (~440Hz, 1s, linear decay)."""
    _play_tone(440.0, 1.0, 0.5, true)


## ── Internal ──

func _play_tone(freq: float, duration: float, volume: float, fade_out: bool = false) -> void:
    if not _enabled or not _playback:
        return

    var samples := int(SAMPLE_RATE * duration)
    var stream := AudioStreamGeneratorPlayback.new() if false else _playback  # type hint placeholder
    var frame: Vector2

    # Resume the stream for this sound
    if has_node("AudioStreamGenerator"):
        get_node("AudioStreamGenerator").stream_paused = false

    for i in range(samples):
        var t := float(i) / SAMPLE_RATE
        var envelope := volume
        if fade_out:
            envelope = volume * (1.0 - t / duration)  # linear fade
        else:
            # Fast decay envelope: attack first 10%, sustain middle, decay last 30%
            if t < duration * 0.05:
                envelope = volume * (t / (duration * 0.05))  # attack
            elif t > duration * 0.7:
                envelope = volume * (1.0 - (t - duration * 0.7) / (duration * 0.3))  # decay

        var sample_val := envelope * sin(2.0 * PI * freq * t)
        frame = Vector2(sample_val, sample_val)
        _playback.push_frame(frame)

    # Pause stream after sound completes (silence = no CPU)
    if has_node("AudioStreamGenerator"):
        get_node("AudioStreamGenerator").stream_paused = true


func pause_stream() -> void:
    if not _enabled:
        return
    if has_node("AudioStreamGenerator"):
        get_node("AudioStreamGenerator").stream_paused = true


func resume_stream() -> void:
    pass  # Stream auto-resumes on next play_tone() call; no-op here


## ── Signal Handlers ──

func _on_scored(_winner: String) -> void:
    play_score()


func _on_match_over(_winner: String) -> void:
    play_game_over()
```

**Paddle/Ball trigger pattern** — in `paddle.gd` collision handler and `ball.gd` wall collision:

```gdscript
# In paddle.gd, after detecting a paddle hit:
if is_instance_valid(AudioEngine):
    AudioEngine.play_paddle_hit()

# In ball.gd, after detecting a wall bounce:
if is_instance_valid(AudioEngine):
    AudioEngine.play_wall_bounce()
```

---

## 3. Existing Component Modifications

### 3.1 New Files

| File | Type | Purpose |
|------|------|---------|
| `mini-pong/gdscripts/pause_overlay.gd` | GDScript | Pause UI overlay logic |
| `mini-pong/gdscripts/audio_engine.gd` | GDScript | Audio synthesis autoload |
| `mini-pong/tests/test_pause.gd` | GDScript | Pause state transition tests |
| `mini-pong/tests/test_audio_engine.gd` | GDScript | Audio synthesis unit tests |

### 3.2 Modified Files

| File | Change | Why | Est. Δ |
|------|--------|-----|--------|
| `mini-pong/gdscripts/game_state_machine.gd` | Add `PAUSED` to `enum State`; add Escape handling in `_input()`; add `@onready var pause_overlay`; add `enter_state(PAUSED)` / `exit_state(PAUSED)` blocks | FSM extension for pause | +25 lines |
| `mini-pong/scenes/game.tscn` | Add `PauseOverlay` CanvasLayer node with ext_resource + ColorRect + Label children; add `@export` node_path for FSM | Scene composition | +12 lines |
| `mini-pong/project.godot` | Add `AudioEngine` to `[autoload]` section; add `pause` InputMap action bound to Escape | Autoload + input registration | +4 lines |
| `mini-pong/gdscripts/paddle.gd` | Add `AudioEngine.play_paddle_hit()` call in collision handler | Sound trigger | +3 lines |
| `mini-pong/gdscripts/ball.gd` | Add `AudioEngine.play_wall_bounce()` call in wall collision handler | Sound trigger | +3 lines |

### 3.3 `game_state_machine.gd` Specific Changes

**Enum addition:**
```gdscript
enum State {
    MENU,
    SERVING,
    PLAYING,
    PAUSED,    # ← NEW
    SCORED,
    GAME_OVER
}
```

**New @onready reference:**
```gdscript
@onready var pause_overlay: CanvasLayer = $"../PauseOverlay"
```

**`_input()` addition** — add Escape handling BEFORE the `ui_accept` check:
```gdscript
func _input(event: InputEvent) -> void:
    # Pause toggle: Escape toggles PLAYING ↔ PAUSED
    if event.is_action_pressed("ui_cancel"):
        match current_state:
            State.PLAYING:
                transition_to(State.PAUSED)
            State.PAUSED:
                transition_to(State.PLAYING)
        return  # consume event, don't fall through to ui_accept

    if not event.is_action_pressed("ui_accept"):
        return
    # ... existing ui_accept handling unchanged ...
```

**`enter_state()` additions:**
```gdscript
State.PAUSED:
    _set_ui("pause")
    _freeze_paddles(true)
    if pause_overlay and pause_overlay.has_method("show_overlay"):
        pause_overlay.show_overlay()
    if is_instance_valid(AudioEngine):
        AudioEngine.pause_stream()

State.PLAYING:
    _set_ui("hud")
    _freeze_paddles(false)
    if pause_overlay and pause_overlay.has_method("hide_overlay"):
        pause_overlay.hide_overlay()
    if is_instance_valid(AudioEngine):
        AudioEngine.resume_stream()
```

**`_set_ui()` addition:**
```gdscript
if pause_overlay:
    pause_overlay.visible = (layer == "pause")
```

---

## 4. Data Flow

### 4.1 Pause Flow

```
Escape Key Press (PLAYING state)
  → FSM._input() detects ui_cancel
  → transition_to(PAUSED)
    → exit_state(PLAYING): nothing to clean up
    → enter_state(PAUSED):
        → _set_ui("pause")      → PauseOverlay visible; StartMenu/GameHUD/GameOverScreen hidden
        → _freeze_paddles(true) → paddle.set_frozen(true)
        → pause_overlay.show_overlay()
        → AudioEngine.pause_stream()
    → Ball: delta guard catches: _process() returns early when delta ≈ 0
    → Paddles: _process() returns early when frozen=true

Escape Key Press (PAUSED state)
  → FSM._input() detects ui_cancel
  → transition_to(PLAYING)
    → exit_state(PAUSED): nothing to clean up
    → enter_state(PLAYING):
        → _set_ui("hud")        → GameHUD visible; PauseOverlay hidden
        → _freeze_paddles(false)
        → pause_overlay.hide_overlay()
        → AudioEngine.resume_stream()
    → Ball/Paddles resume processing normally
```

### 4.2 Audio Flow

```
paddle.gd: collision detected → AudioEngine.play_paddle_hit()
ball.gd: wall bounce detected → AudioEngine.play_wall_bounce()
ScoringManager.scored signal  → AudioEngine._on_scored()   → play_score()  (C5→E5→G5)
GameManager.match_over signal → AudioEngine._on_match_over() → play_game_over() (440Hz fade)

Each play_*():
  → _play_tone(freq, duration, volume)
    → Generate sin wave samples with envelope
    → push_frame() to AudioStreamGeneratorPlayback
    → Pause stream after sound completes (CPU save)
```

---

## 5. Edge Cases & Error Handling

| # | Edge Case | Mitigation |
|---|-----------|------------|
| 1 | **Rapid Escape double-press** | FSM's `_transition_lock` mechanism blocks re-transition; PAUSED/PLAYING transitions are lock-free (instant toggle, no await) so double-press is harmless — second press toggles from PAUSED back to PLAYING immediately |
| 2 | **Escape in non-PLAYING state** | `_input()` only matches `PLAYING` or `PAUSED`; MENU/SERVING/SCORED/GAME_OVER produce no effect |
| 3 | **match_over during PAUSED** | Cannot happen — ball._process() is frozen in PAUSED, so scoring cannot occur |
| 4 | **AudioEngine in headless mode** | `_ready()` checks `AudioServer` availability; `_enabled` stays false; all `play_*()` methods no-op when `_enabled == false` |
| 5 | **Score sound during paddle hit** | Score sound is 3 sequential tones (240ms total); paddle hit is 50ms. They don't interleave because `_play_tone()` is synchronous — each `push_frame()` call blocks until the buffer is filled for that tone. Concurrent sounds require future enhancement (mixing). |
| 6 | **PauseOverlay node missing from game.tscn** | FSM uses `pause_overlay.has_method("show_overlay")` check — if null, pause still freezes game, just no visual overlay |
| 7 | **AudioStreamGenerator creation failure** | `_setup_generator()` failure is caught by the `_enabled` gate — all subsequent `play_*()` calls are no-ops |
| 8 | **`ui_cancel` not in InputMap** | `ui_cancel` is a Godot built-in action (always bound to Escape by default) — no manual InputMap entry needed. Escape works out of the box. |

---

## 6. Integration Points

| Integration | Component | How |
|-------------|-----------|-----|
| FSM → PauseOverlay | `game_state_machine.gd` | `@onready var pause_overlay`, calls `show_overlay()`/`hide_overlay()` |
| FSM → AudioEngine | `game_state_machine.gd` | `AudioEngine.pause_stream()`/`resume_stream()` in enter_state |
| FSM → Paddles | `game_state_machine.gd` | Existing `_freeze_paddles()` method — no change needed |
| ScoringManager → AudioEngine | `audio_engine.gd` | Connects to `GameManager.scored` signal in `_ready()` |
| GameManager → AudioEngine | `audio_engine.gd` | Connects to `GameManager.match_over` signal in `_ready()` |
| Paddle → AudioEngine | `paddle.gd` | Direct call `AudioEngine.play_paddle_hit()` in collision handler |
| Ball → AudioEngine | `ball.gd` | Direct call `AudioEngine.play_wall_bounce()` in wall bounce handler |

---

## 7. Test Case Descriptions

### Test Suite: `test_pause.gd`

**Scenario A: Pause toggle**

- **TC1: Escape pauses game from PLAYING** — Start game in PLAYING state, press Escape → assert `current_state == PAUSED`, assert `PauseOverlay.visible == true`, assert paddles are frozen
- **TC2: Escape resumes game from PAUSED** — From PAUSED state, press Escape → assert `current_state == PLAYING`, assert `PauseOverlay.visible == false`, assert paddles unfrozen
- **TC3: Escape in MENU has no effect** — In MENU state, press Escape → assert `current_state == MENU`
- **TC4: Escape in GAME_OVER has no effect** — In GAME_OVER state, press Escape → assert `current_state == GAME_OVER`

**Scenario B: State consistency**

- **TC5: Ball frozen during pause** — Enter PAUSED, advance a few frames → assert ball position unchanged
- **TC6: Paddle frozen during pause** — Enter PAUSED, simulate paddle input → assert paddle position unchanged
- **TC7: Scoring impossible during pause** — Enter PAUSED, simulate ball reaching scoring zone → assert no score event

### Test Suite: `test_audio_engine.gd`

**Scenario C: Audio synthesis**

- **TC8: paddle_hit produces frames** — Call `play_paddle_hit()`, check `_playback.get_frames_available() < buffer_length` (frames were consumed)
- **TC9: wall_bounce produces lower frequency** — Call `play_wall_bounce()`, verify frequency ~100Hz (lower than paddle_hit 200Hz)
- **TC10: score produces 3-note pattern** — Call `play_score()`, verify 3 distinct tone segments (C5, E5, G5 frequencies)
- **TC11: game_over produces fade-out** — Call `play_game_over()`, verify final sample amplitude ≈ 0 (fully decayed)

**Scenario D: Error handling**

- **TC12: Headless no-op** — With `_enabled = false` (simulating headless), call `play_paddle_hit()` → no crash, no error
- **TC13: AudioEngine null safety** — Call `AudioEngine.play_paddle_hit()` when AudioEngine is not an autoload → no crash (guarded by `is_instance_valid` in calling code)

---

## 8. Implementation Order

| Phase | Priority | Components | Est. Lines |
|:-----:|:--------:|-----------|:----------:|
| 1 | P0 | Pause system: PAUSED state in FSM, PauseOverlay, game.tscn, project.godot InputMap | ~40 |
| 2 | P0 | Audio system: AudioEngine autoload, 4 synthesis methods, signal connections | ~80 |
| 3 | P0 | Sound triggers: paddle.gd + ball.gd collision callbacks | ~6 |
| 4 | P1 | Tests: test_pause.gd (7 tests) + test_audio_engine.gd (6 tests) | ~120 |

**Total estimate:** ~250 lines of new code + ~120 lines of tests = ~370 lines.

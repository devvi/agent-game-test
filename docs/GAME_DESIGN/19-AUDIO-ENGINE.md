# Audio Engine — Real-Time Synthesis

> Reference: ../DESIGN/296-pause-and-sound.md
> Parent Issue: #296

## Overview

AudioEngine is an **autoload singleton** that synthesizes sound effects in real time
using Godot 4.x's `AudioStreamGenerator`. It produces four distinct sounds triggered
by gameplay events — no external audio files required.

## Architecture

```
AudioEngine (autoload, extends Node)
├── _ready(): guard AudioServer availability, connect to GameManager signals
├── _setup_generator(): create AudioStreamPlayer + AudioStreamGenerator pipeline
├── play_paddle_hit(): 200Hz, 50ms, fast decay
├── play_wall_bounce(): 100Hz, 120ms, slow decay
├── play_score(): C5→E5→G5 arpeggio, 80ms each
├── play_game_over(): 440Hz, 1s, linear fade-out
├── pause_stream(): pause AudioStreamGenerator
└── resume_stream(): no-op (auto-resumes on next play_*() call)
```

## Sound Design

| Sound | Trigger | Frequency | Duration | Envelope |
|-------|---------|-----------|----------|----------|
| `paddle_hit` | Ball hits paddle (`_on_area_entered`) | 200 Hz | 50 ms | Attack 5%, decay 30% |
| `wall_bounce` | Ball hits wall (`_on_body_entered`) | 100 Hz | 120 ms | Attack 5%, decay 30% |
| `score` | ScoringManager.scored signal | C5(523)→E5(659)→G5(784) | 3×80 ms | Attack 5%, decay 30% |
| `game_over` | GameManager.match_over signal | 440 Hz | 1000 ms | Linear fade-out |

## Synthesis Pipeline

```
AudioStreamGenerator (44100 Hz, 0.5s buffer)
    → AudioStreamPlayer (wraps generator for tree membership)
        → player.get_stream_playback() → AudioStreamGeneratorPlayback
            → push_frame(Vector2(sample, sample)) per sample
```

### Key Implementation Details

- **Sample rate**: 44,100 Hz (CD quality)
- **Buffer**: 0.5 seconds — enough for the longest sound (game_over = 1s, but buffer drains as frames push)
- **Player wrapper**: AudioStreamPlayer (`player.play()`) wraps the generator because `AudioServer.add_stream_to_bus()` does not exist in Godot 4.x. Access playback via `player.get_stream_playback()`.
- **Stream pausing**: `player.stream_paused = true` after each sound completes — saves CPU by not filling silence between sounds. Auto-resumes on next `play_*()` call.
- **Waveform**: `sin(2πft)` with per-sample envelope multiplication

### Envelope Shapes

**Fast decay** (paddle_hit, wall_bounce, score):
```
Attack (0% → 5%): volume * (t / (duration * 0.05))
Sustain (5% → 70%): volume (full)
Decay (70% → 100%): volume * (1 - (t - d*0.7) / (d*0.3))
```

**Linear fade-out** (game_over):
```
envelope = volume * (1.0 - t / duration)
```

## Signal Integration

AudioEngine connects to GameManager signals in `_ready()`:

| Signal | Handler | Sound |
|--------|---------|-------|
| `GameManager.scored(winner)` | `_on_scored()` | `play_score()` |
| `GameManager.match_over(winner)` | `_on_match_over()` | `play_game_over()` |

Direct triggers (from ball.gd):
- `AudioEngine.play_paddle_hit()` — called in `_on_area_entered()` when area is in group "paddles"
- `AudioEngine.play_wall_bounce()` — called in `_on_body_entered()` when body is in group "walls"

## Headless Mode

AudioEngine gracefully degrades when the AudioServer is unavailable (headless CI):

- `_ready()`: detects `not AudioServer` → `push_warning`, returns early
- `_play_tone()`: checks `not _enabled or not _playback` → returns immediately (no-op)
- Production code guards: `if is_instance_valid(AudioEngine): AudioEngine.play_*()`

## Test Coverage

| Test | Description |
|------|-------------|
| TC8 | `play_paddle_hit()` produces ~2205 frames (50ms × 44100 Hz) |
| TC9 | `play_wall_bounce()` has lower frequency (fewer zero crossings) than `play_paddle_hit()` |
| TC10 | `play_score()` produces ~10584 frames across 3 segments with distinct frequencies |
| TC11 | `play_game_over()` fades to ~0 amplitude at final sample |
| TC12 | All `play_*()` methods no-op safely when `_enabled = false` |
| TC13 | `is_instance_valid(null)` returns false — null-safety pattern verified |

Test file: `mini-pong/tests/test_audio_engine.gd` (245 lines, 6 tests, 15 assertions)

Tests use a mock playback injector: inject a `RefCounted` object with `push_frame()` that
captures frames into an array, verify frame count, frequency via zero-crossing analysis,
and fade-out via final-sample amplitude.

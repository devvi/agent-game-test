# L0 Rain Curtain — 动态雨幕 (Dynamic Rain Curtain)

> Reference: ../DESIGN/389-dynamic-rain-curtain.md · PRD ../PRD/389-dynamic-rain-curtain.md
> Merged: #416 (2026-08-13) · Issue #389

## Overview

The rain curtain is the **L0 atmosphere layer** of PONG://NEON — a full-screen
GPUParticles2D rain that doubles as an **emotion dashboard**. Rain intensity is a
live formula of game state (ball speed, score tension, wave factor, event pulses,
breathing windows), so the weather *is* the mood: calm drizzle on the menu, heavier
rain as rallies heat up, spikes on dramatic events.

Design constraints (from #389 PRD research):

1. **Modulate, never re-seed** — runtime changes to `amount` restart the particle
   system and cause visible popping (godot-weather-2D finding, PRD §1.5). Intensity
   is expressed via velocity / scale / alpha modulation only. **`amount` is frozen
   at 400 and is off-limits to all future issues.**
2. **Zero intrusion** — the curtain only *reads* public properties
   (`ball.speed`, `GameManager` scores). The physics/signal chain
   (`game_state_machine.gd`, `scoring_manager.gd`, `ball.gd`) is untouched.
3. **Contract API is the only write path** — future systems (#384/#385/#386/#388)
   drive the rain through `set_wave_factor()` / `trigger_event_pulse()` /
   `set_breathing()`, never by editing particle properties directly.

## Architecture

```
Game (Node2D)
└── AtmosphereLayer (CanvasLayer, layer = 0)      # L0, below world layer=1 & PauseOverlay layer=10
    └── RainCurtain (rain_curtain.tscn)           # GPUParticles2D + rain_curtain.gd
```

- **Layer 0** is the lowest CanvasLayer — rain never covers walls/ball/paddles/UI.
- **FSM-independent** — the curtain runs on its own; MENU shows light drizzle (0.3),
  PLAYING follows the formula, PAUSED keeps emitting (natural decay).

## Rain Formula (single source of truth: `constants.gd` RAIN_* group)

```
target_rain = clamp(
    RAIN_BASE(0.3)
  + speed factor:   (speed − 330) / (627 − 330) × RAIN_SPEED_FACTOR_MAX(0.3)   # 0 → +0.3
  + wave factor:    wave_index × RAIN_WAVE_STEP(0.1)                            # contract, default 0
  + tension:        |Δscore| ≤ RAIN_TENSION_THRESHOLD(2) ? RAIN_TENSION_BONUS(0.2) : 0
  + event pulse:    _pulse_current (exponential decay to 0, ~1.5s)              # contract, default 0
  − breathing:      RAIN_BREATHING_DROP(0.15) if breathing window active        # contract, default false
, RAIN_MIN(0.1), RAIN_MAX(1.0))
```

| Constant | Value | Meaning |
|----------|:-----:|---------|
| `RAIN_BASE` | 0.3 | Baseline drizzle (menu / calm) |
| `RAIN_MIN` / `RAIN_MAX` | 0.1 / 1.0 | The **only** clamp boundaries (test-pinned) |
| `RAIN_SMOOTH_TAU` | 0.15 s | Exponential smoothing time constant |
| `RAIN_SPEED_FACTOR_MAX` | 0.3 | Full ball-speed ramp contribution |
| `RAIN_TENSION_THRESHOLD` | 2 | Score gap ≤ 2 (incl. 0-0) counts as tense |
| `RAIN_TENSION_BONUS` | 0.2 | Tension contribution when threshold met |
| `RAIN_WAVE_STEP` | 0.1 | Per-wave factor step |
| `RAIN_PULSE_PIERCE` | 0.4 | Pierce-event pulse amount (future #385) |
| `RAIN_BREATHING_DROP` | 0.15 | Breathing-window reduction |

Edge cases: serve moment (speed=330) → factor 0 → rain = base; top speed (~627) →
+0.3 → 0.6; NaN speed (#287 precedent) → treated as 0, falls back to base without
polluting the smooth state; clamp floor 0.1 guards base − breathing < 0.

## Smooth Transitions (AC4)

```
current += (target_rain − current) × (1 − exp(−delta / RAIN_SMOOTH_TAU))
```

τ = 0.15 s ⇒ ≥95% convergence within 0.5 s (1−e^(−0.5/0.15) ≈ 96.4%), no single-frame
jump > 20%. `emitting = rain > 0.05` stops particle emission near zero (waste guard).

## Particle Modulation (how intensity is expressed)

| Parameter | Modulation |
|-----------|-----------|
| `initial_velocity_min/max` | fall speed × (0.6 + 0.8 × rain) |
| `scale_min/max` | droplet size × (0.5 + 0.7 × rain) |
| `color` / `color_ramp` alpha | opacity (fainter in light rain; restrained blue-white per #289) |
| `emitting` | `rain > 0.05` |

Scene params: emission rect width 720 (full portrait width), gravity +Y (vertical
fall, same axis as attack), preprocess 2.0 s warm-up (no pop-in), drops die past the
bottom edge. Texture: `assets/rain_drop.png` (3×14 translucent white vertical
stripes, headless-safe import).

## Contract API (future issues' only write path)

| API | Semantics | Source | Default |
|-----|-----------|--------|:-------:|
| `set_wave_factor(wave_index: int)` | wave factor = index × +0.1 | #386 wave loop | 0 |
| `trigger_event_pulse(amount: float)` | pulse then ~1.5 s monotonic decay | #384/#385/#386 | 0 |
| `set_breathing(active: bool)` | breathing window −0.15 | #388 upgrade UI | false |
| `set_intensity(value: float)` | debug: set target directly (bypasses formula) | — | — |

Current gameplay (no waves/bricks/upgrades yet) yields rain ∈ [0.3, 0.8] — playable
with no errors. **No future issue may write `amount` directly** (pop-in regression).

## Tunables (taste-draft window)

`@export base_intensity` (default 0.3, AC1) and `@export smooth_tau` (0.15) are
inspector-adjustable; the intensity curve shape is a taste-draft candidate left for
human finalization — does not block this issue.

## Testing

`tests/test_rain.gd` — 48 cases: clamp dual boundaries / formula monotonicity /
tension equality edge / smooth no-jump ≤20% / 0.5 s convergence 95%+ / event pulse
1.5 s monotonic decay / contract defaults / NaN guard / resource integrity.
E2E: `e2e_shots.json` loop archetype hits `rain_curtain.gd`; 01_title/02_midgame/
03_gameover screenshots carry the curtain through 4-fold anti-fake assertions.

# Background Neon Breath — 背景霓虹呼吸

> Reference: ../DESIGN/449-bg-neon-breath.md · PRD ../PRD/449-bg-neon-breath.md
> Merged: #457 (2026-08-13) · Issue #449

## Overview

The background neon breath is the **second L0 atmosphere element** of PONG://NEON
(sibling of the rain curtain, #389). Where the rain curtain is an *event-driven
emotion dashboard*, the background breath is a **constant, state-independent
baseline** — a full-screen ColorRect whose opacity slowly breathes in a 4-second
sine cycle, amplified by the existing WorldEnvironment glow(0.6)/bloom(0.8) into a
soft halo pulse. The background is no longer dead: the scene "breathes" even in
MENU/PAUSED, while dramatic event-driven variation stays the rain curtain's job.

Design constraints (from #449 DESIGN):

1. **Formula is the contract** — `compute_alpha(t)` is a static pure function
   (headless-assertable). Period/base/amplitude/tint all live in the `BG_PULSE_*`
   constants group; `period <= 0` returns `base` (division-by-zero NaN guard,
   precedent #287/#389).
2. **Restraint** — alpha in [0.01, 0.15] (base 0.08 ± amplitude 0.07), peak ≤15%,
   same order of magnitude as the PLAN vignette ≤10%. Slow constant sine, no
   game-event mutation. Taste values (peak opacity / tint) converge in
   `BG_PULSE_*` constants for human finalization — zero code change to tune.
3. **Zero intrusion / additive** — Main.tscn existing nodes untouched; only one
   new ColorRect child + one ext_resource. constants.gd only *appends* a new
   section; existing sections byte-identical.
4. **Layer discipline** — mounted as the **first child** of `AtmosphereLayer`
   (layer=0, lowest CanvasLayer), declared *before* RainCurtain = same-layer
   bottom-most. Structurally below world L1 / UI L3; no new CanvasLayer.
5. **FSM-independent** (rain-curtain discipline) — breathes through
   MENU/PLAYING/PAUSED/SCORED/GAME_OVER with no state logic, no signals, no
   external write entry.

## Architecture

```
Game (Node2D)
└── AtmosphereLayer (CanvasLayer, layer = 0)      # L0, below world layer=1 & PauseOverlay layer=10
    ├── BgPulse (ColorRect, bg_pulse.gd)          # 首子节点 = 同层最底，先绘制
    └── RainCurtain (rain_curtain.tscn)           # 既有，零改动
```

- **Draw order** (same layer, declaration order): BgPulse → RainCurtain → L1
  world → L2 feedback → L3 UI. BgPulse never covers the ball/walls/paddles/UI.
- **Passive glow amplification** — `world_environment.tscn` (unchanged) provides
  glow_enabled + glow_intensity 0.6 + glow_bloom 0.8; the 2D ColorRect alpha
  variation is bloomed into the visible "breathing halo".

## Formula (single source of truth: `constants.gd` BG_PULSE_* group)

```gdscript
compute_alpha(t, period, base, amplitude) = clamp(base + amplitude·sin(TAU·t/period), 0, 1)
period <= 0 → return base   # NaN/div-zero guard
```

| Constant | Value | Meaning |
|----------|:-----:|---------|
| `BG_PULSE_PERIOD` | 4.0 s | Breathing cycle (~4s default, configurable) |
| `BG_PULSE_BASE_ALPHA` | 0.08 | Baseline opacity (t=0 / t=2s) |
| `BG_PULSE_AMPLITUDE` | 0.07 | Sine amplitude → alpha in [0.01, 0.15] |
| `BG_PULSE_TINT` | Color(0.29, 0.56, 0.85) | Neon blue family, same family as PLAYER_NEON_BLUE #4a90d9 |

Alpha phase table (t in [0, 4s)):

| t (s) | sin(TAU·t/4) | alpha |
|:-----:|:------------:|:-----:|
| 0.0 | 0 | 0.08 (baseline) |
| 1.0 | +1 | 0.15 (peak) |
| 2.0 | 0 | 0.08 (baseline) |
| 3.0 | −1 | 0.01 (valley) |
| 4.0 | 0 | 0.08 (cycle closes) |

## Runtime Behavior

- `_process(delta)` accumulates `_t` and writes `color.a` each frame; RGB stays
  at `BG_PULSE_TINT`. Scene reload resets `_t` to 0 → starts at baseline, no
  visible jump (max half-cycle delta 0.07).
- Cost: one Control + one sine per frame — negligible.
- Headless: `_process` ticks, ColorRect not rendered → no script error; the pure
  function is the assertable surface (DESIGN §7 Scenario B boundary cases).
- Edge cases: `period <= 0` → constant baseline (safe degradation); alpha clamp
  guards [0, 1]; taste over-brightness risk mitigated by amplitude narrowing
  (constant-level fix, no code change).

## Contract

| Item | Contract |
|------|----------|
| Signals | **None** — FSM-independent, no signal chain |
| Write path | Only `color.a` via `_process`; no external write entry |
| Read path | `constants.gd` BG_PULSE_* (period/base/amplitude/tint) |
| Taste handoff | Peak opacity / tint → human finalization via constants (tune = zero code) |

## Testing

- No new test files (AC5 file-domain red line) — acceptance = full existing suite
  green (baseline 2214, no regression) + pure-function boundary hand checks
  (DESIGN §7 Scenario B1–B5) + E2E loop screenshots.
- E2E: `e2e_shots.json` loop archetype matches `gdscripts/*.gd` + `scenes/*.tscn`
  → BgPulse changes always exercise L3. 01_title / 02_midgame screenshots carry
  the breathing background through 4-fold anti-fake assertions (non-black / color
  count / theme #4a90d9 / frame-diff); tint same-family as theme → color-count
  assertion stays stable.

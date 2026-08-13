# L0 Rain Curtain — 动态雨幕 (Dynamic Rain Curtain)

> Reference: ../DESIGN/389-dynamic-rain-curtain.md · PRD ../PRD/389-dynamic-rain-curtain.md
> Merged: #416 (2026-08-13) · Issue #389 · Fix: #472 (2026-08-13) · Issue #465

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

`tests/test_rain.gd` — 70 cases: clamp dual boundaries / formula monotonicity /
tension equality edge / smooth no-jump ≤20% / 0.5 s convergence 95%+ / event pulse
1.5 s monotonic decay / contract defaults / NaN guard / resource integrity.
E2E: `e2e_shots.json` loop archetype hits `rain_curtain.gd`; 01_title/02_midgame/
03_gameover screenshots carry the curtain through 4-fold anti-fake assertions.

## #465 修复：全屏均匀雨滴分布 (2026-08-13, merged #472)

> 漏水点根因 = D1（`visibility_rect` 缺省 → Godot 默认局部 `Rect2(-100,-100,200,200)` 剔除发射区边缘粒子）
> + D2（`emission_rect_extents=Vector2(360,8)` 半宽语义 → 发射区仅 16px 高顶部窄带）。
> 修复为**纯静态配置修正 + 基值对齐**：零新节点/脚本/依赖，#389 调制契约（禁写 `amount`、公式引擎、契约 API）零改动。

### 发射几何（rain_curtain.tscn）

| 参数 | 修复前 (#389) | 修复后 (#465) | 语义 |
|------|--------------|--------------|------|
| `Particles.position` | `(360, -20)` | `(360, 640)` | 节点居中 → 局部坐标与屏幕对齐（注释绑定 position↔visibility_rect） |
| `emission_rect_extents` | `(360, 8)` | `(360, 640)` | 半宽语义 → 全屏 720×1280 发射区 |
| `visibility_rect` | 缺省 `(-100,-100,200,200)` | `(-360,-640,720,1280)` | 全屏可视窗口（D1 剔除修复核心） |
| `amount` | 400 | 600 | 规范带 400–800 中值（静态配置，仍禁运行时写入） |
| `spread` | 6.0 | 8.0 | 斜落方向一致（∈[6,10]） |
| `initial_velocity_min/max` | 700/900 | 800/1200 | 基值对齐规范带 |
| `scale_min/max` | 0.7/1.3 | 0.5/1.2 | 基值对齐规范带 |
| `color` alpha | 0.45 | 0.225 | 基值对齐（运行时被公式覆盖） |

### 基值常量（rain_curtain.gd）

- `BASE_VELOCITY_MIN/MAX` 800/1200、`BASE_SCALE_MIN/MAX` 0.5/1.2
- alpha 公式 `tint.a = 0.15 + 0.25 * r`：默认雨 r=0.3 → 0.225、风暴 r=1.0 → 0.40，全带 ∈ [0.2, 0.4]
- `amount` 红线保持：gd 无任何 `amount =` 写入（TC-B4 钉死）

### 测试新增（test_rain.gd，48 → 70 cases）

- **TC-A1–A7**：tscn 静态配置断言（position / emission rect / visibility_rect / amount / spread / 速度 / scale / alpha 带）
- **TC-B1–B4**：gd 基值常量 + alpha 公式行为（r=0.3→0.225、r=1.0→0.40）+ amount 红线回归

E2E 验证（本地 review, 2026-08-13）：L1 全量 2254 passed 0 failed；02_midgame 真实渲染截图 4 重反伪造断言通过（雨幕在 PLAYING 状态全屏渲染）。

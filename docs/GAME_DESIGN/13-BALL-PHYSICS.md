# Ball Physics & Collision

> Reference: ../DESIGN/287-ball-physics.md

## Overview

The ball is a self-contained Area2D component that manages its own velocity, collision responses,
speed escalation, scoring signals, and serve logic. Movement is handled via manual `_process(delta)`
position updates — no physics engine involvement — providing deterministic, arcade-style linear motion
with precise control over bounce angles.

The ball operates with zero autoload dependencies beyond Godot built-in APIs. It connects to
walls via `body_entered`, paddles via `area_entered`, and emits `score(side: int)` on boundary exit.

## Node Tree

```
Area2D (Ball, ball.gd)
├── ColorRect (20×20, white)
└── CollisionShape2D (CircleShape2D, radius=10)
```

## Core Constants

```gdscript
const INITIAL_SPEED: float = 300.0           # Pixels per second at serve
const MAX_SPEED_MULTIPLIER: float = 2.0      # Speed cap: 600 px/s
const SPEED_INCREMENT: float = 1.05          # +5% per paddle hit
const MAX_BOUNCE_ANGLE: float = 60.0         # Degrees — max rebound angle
const SERVE_ANGLE_RANGE: float = 45.0        # Degrees — random serve spread
const BOUNCE_COOLDOWN_FRAMES: int = 2        # Frames to suppress duplicate collisions
const SERVE_DELAY: float = 0.5               # Seconds pause before serve launch
const BALL_RADIUS: float = 10.0              # Radius for collision margins
const FALLBACK_SCREEN_WIDTH: float = 1280.0  # Headless fallback
const FALLBACK_SCREEN_HEIGHT: float = 720.0  # Headless fallback
```

## Key Systems

### Wall Bounce

| Parameter | Value |
|-----------|-------|
| Trigger | `body_entered` with `is_in_group("walls")` |
| Response | `velocity.y *= -1.0` |
| Cooldown | 2 frames (prevents double-bounce on corners) |
| X velocity | Unchanged (preserves horizontal trajectory) |
| Speed | Unchanged (only paddle hits escalate speed) |

### Paddle Collision — Bounce Angle

| Parameter | Value |
|-----------|-------|
| Trigger | `area_entered` with `is_in_group("paddles")` |
| Impact calculation | `(ball.y - paddle.y) / (paddle_height / 2)` → clamped to [-1, +1] |
| Angle mapping | `impact_offset × 60°` → angle range [-60°, +60°] |
| Center hit | impact_offset ≈ 0 → near-horizontal rebound |
| Edge hit | impact_offset ≈ ±1 → steep 60° angle |

### Speed Escalation

| Parameter | Value |
|-----------|-------|
| Per-hit multiplier | `speed *= 1.05` (+5%) |
| Cap | `INITIAL_SPEED × 2.0` = 600 px/s |
| Reset | Returns to `INITIAL_SPEED` on serve after scoring |

### Scoring

| Event | Signal | Meaning |
|-------|--------|---------|
| Ball exits right | `score(0)` | Left player scored |
| Ball exits left | `score(1)` | Right player scored |

After scoring, the ball automatically serves from center after a 0.5s delay.

### Serve

| Parameter | Value |
|-----------|-------|
| Position | Center of screen: `(screen_width/2, screen_height/2)` |
| Direction | Random: left (-1) or right (+1), 50/50 |
| Angle | Random within ±45° from horizontal |
| Speed | Reset to `initial_speed` (300 px/s) |
| Delay | 0.5s pause before launch (via `await create_timer`) |

## Data Flow

```
_ready()
  ├── Read viewport dimensions (fallback: 1280×720)
  ├── Validate CollisionShape2D shape (push_error if null)
  ├── Connect body_entered → _on_body_entered
  ├── Connect area_entered → _on_area_entered
  └── serve() → first launch

_process(delta) — every frame
  ├── Skip if _is_serving or abnormal delta
  ├── NaN guard: reset velocity if NaN detected
  ├── Decrement bounce cooldown
  ├── Normalize + move: velocity = velocity.normalized() * speed; position += velocity * delta
  ├── Y boundary safety net: clamp + bounce
  └── X boundary: emit score(side) + serve()

_on_body_entered(body) — wall collision
  ├── Skip if cooldown active
  └── velocity.y *= -1; set cooldown

_on_area_entered(area) — paddle collision
  ├── Skip if cooldown active or not in "paddles" group
  ├── Calculate impact_offset from paddle height
  ├── Compute bounce angle, reverse X direction
  ├── Apply speed escalation (cap at 2×)
  ├── Set cooldown
  └── Anti-stick push: nudge ball away from paddle
```

## Edge Cases

| # | Case | Behavior |
|---|------|----------|
| 1 | Ball hits wall+paddle same frame | 2-frame cooldown suppresses duplicate |
| 2 | Ball velocity becomes NaN | Detected in _process, reset to `Vector2.RIGHT * speed` |
| 3 | Delta > 0.1 or ≤ 0 | Skipped frame — prevents teleport on frame spikes |
| 4 | Viewport unavailable (headless) | Falls back to 1280×720 |
| 5 | serve() called during serve | `_is_serving` gate prevents double-serve |
| 6 | CollisionShape2D shape is null | push_error logged, no crash |
| 7 | Paddle has no CollisionShape2D | Falls back to default paddle height 120.0 |
| 8 | Signal connect in test context | Tests bypass `_ready()` and call collision handlers directly |

## Integration Points

| System | How |
|--------|-----|
| Player paddle (#288) | Ball `area_entered` reads paddle group + height for angle calc |
| Walls (game.tscn) | Ball `body_entered` checks `is_in_group("walls")` for Y-bounce |
| Scoring (#291) | Ball emits `score(side: int)`, 0=left scores, 1=right scores |
| Neon visuals (#289) | `ball_trail.gd` duck-types `parent.get("velocity")` — works with Area2D |
| Main scene | `game.tscn` instances `ball.tscn` at position (640, 360) |

## Test Coverage

The test suite (`tests/test_ball.gd`, 461 lines, 35+ test cases) covers:

| Scenario | Tests | Description |
|----------|-------|-------------|
| A: Scene integrity | 4 | ball.tscn + game.tscn node hierarchy, shapes, project.godot main_scene |
| B: Wall bounce | 4 | Y reversal, X unchanged, speed unchanged, cooldown |
| C: Paddle collision | 4 | Center/edge angle variation, X reversal on both directions |
| D: Speed escalation | 3 | +5% per hit, 2× cap, reset on serve |
| E: Scoring | 2 | Right boundary → score(0), left boundary → score(1) |
| F: Serve | 3 | Center position, random direction 50/50, angle within ±45° |
| G: Headless compile | 1 | NaN guard resets velocity |
| H: Cooldown | 2 | Duplicate suppression, expiry and re-arm |

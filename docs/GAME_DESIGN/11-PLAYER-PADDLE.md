# Player Paddle & Input

> Reference: ../DESIGN/288-player-paddle.md

## Overview

The player paddle is a self-contained Area2D component with code-based InputMap bindings,
vertical movement, and boundary clamping. It can be dropped into any scene and works immediately
with zero external dependencies beyond Godot built-in APIs.

## Node Tree

```
Area2D (PlayerPaddle, paddle.gd)
├── ColorRect (20×120, white)
└── CollisionShape2D (RectangleShape2D, 20×120)
```

## Core Constants

```gdscript
const SPEED: float = 400.0              # Pixels per second
const PADDLE_WIDTH: float = 20.0        # ColorRect width
const PADDLE_HEIGHT: float = 120.0      # ColorRect height
const FALLBACK_VIEWPORT_Y: float = 720.0 # Headless fallback
```

## InputMap Bindings

| Action | Keys | Purpose |
|--------|------|---------|
| `paddle_up` | W, ↑ | Move paddle upward |
| `paddle_down` | S, ↓ | Move paddle downward |

Bindings are created in `_ready()` with `has_action()` guard to prevent duplicates on re-instantiation.

## Movement & Clamping

Per-frame in `_process(delta)`:
1. Read `Input.is_action_pressed("paddle_up")` and `("paddle_down")`
2. Compute direction: up-only → -1, down-only → +1, both → 0, neither → 0
3. Apply: `position.y += move * SPEED * delta`
4. Clamp: `position.y = clamp(position.y, min_y, max_y)`

Boundaries calculated from viewport height: `min_y = half_height`, `max_y = viewport_height - half_height`.
Falls back to 720px if viewport unavailable (headless mode).

## Data Flow

```
_ready()
  ├── InputMap binding (guarded)
  ├── Boundary calculation (viewport or fallback)
  └── Initial position clamp

_process(delta) — every frame
  ├── Read input
  ├── Compute move direction
  ├── Apply speed * delta
  └── Clamp to [min_y, max_y]
```

## Edge Cases

| # | Case | Behavior |
|---|------|----------|
| 1 | W+S or ↑+↓ simultaneously | move = 0.0 (cancel) |
| 2 | Window resize mid-game | Boundaries from _ready() — static for MVP |
| 3 | Position outside bounds at start | _ready() clamps |
| 4 | Very low FPS (delta > 1.0) | clamp() runs after move — always in bounds |
| 5 | Scene instantiated twice | has_action() guard skips duplicate binding |
| 6 | Headless mode (zero viewport) | FALLBACK_VIEWPORT_Y = 720.0 |

## Integration Points

| System | How |
|--------|-----|
| Ball collision (#290) | Area2D body_entered signal — paddle is passive, no code needed |
| Main scene (#295) | Instance `player_paddle.tscn` in main scene |
| Visual (#289) | ColorRect color → ShaderMaterial neon glow |
| AI paddle (future) | Reuse `.tscn` structure with different script |

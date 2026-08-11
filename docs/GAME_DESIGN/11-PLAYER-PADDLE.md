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

> **Constants migration (#295):** Paddle constants are now sourced from `gdscripts/constants.gd`
> (`class_name GameConstants`). `paddle.gd` references `CONSTS.PADDLE_SPEED`, `CONSTS.PADDLE_WIDTH`,
> and `CONSTS.PADDLE_HEIGHT` instead of local `const` declarations.

```gdscript
# Pre-migration (for reference):
const SPEED: float = 400.0              # → GameConstants.PADDLE_SPEED
const PADDLE_WIDTH: float = 20.0        # → GameConstants.PADDLE_WIDTH
const PADDLE_HEIGHT: float = 120.0      # → GameConstants.PADDLE_HEIGHT
const FALLBACK_VIEWPORT_Y: float = 720.0 # Headless fallback (local only)
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
| AI paddle (#290) | Same `.tscn` with `mode = Mode.AI` override in Main.tscn |

---

## AI Opponent Mode

> Reference: ../DESIGN/290-ai-opponent.md

### Overview

The paddle supports an AI mode that tracks the ball's Y position with randomized reaction delay
and position error, plus distance-based speed adjustment for human-like play. Two paddles —
one player-controlled, one AI — coexist in `game.tscn`, both registered in the `paddles` group
for collision detection.

### Mode Enum

```gdscript
enum Mode { PLAYER = 0, AI = 1 }
@export var mode: Mode = Mode.PLAYER
```

### AI Parameters (Tunable)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ai_reaction_delay_min` | float | 0.15 | Min reaction delay (seconds)（#367 草稿） |
| `ai_reaction_delay_max` | float | 0.4 | Max reaction delay (seconds)（#367 草稿） |
| `ai_position_error` | float | 24.0 | ±error range (pixels)（#367 草稿） |
| `ai_speed_boost` | float | 1.25 | Speed multiplier when trailing (dist ≥ 48)（#367 草稿） |
| `ai_speed_slow` | float | 0.75 | Speed multiplier when ahead (dist < 48)（#367 草稿） |

All `@export` — tunable in editor for difficulty adjustment.

> **手感校准草稿（#367）**：上表默认值为 taste-draft 草稿值（来源 `constants.gd`，带 `# DRAFT` 注释）。
> 速度切换阈值 = `ai_position_error × 2`（草稿 24 → 48px）。候补值与情感断言见 `docs/TASTE.md`；定稿后更新本表。

### AI Processing Flow (per frame)

```
_ai_process(delta):
  1. Guard: if _ball_node == null → early return (no crash)
  2. Delay timer: _ai_delay_timer -= delta
     if timer ≤ 0:
       timer = randf_range(0.15, 0.4)   # new delay window（#367 草稿）
       error = randf_range(-24, 24)      # position error（#367 草稿）
       target = ball.y + error
  3. Speed adjustment:
     dist = |position.y - target|
     factor = 1.25 if dist ≥ 48 else 0.75   # 阈值 = ai_position_error × 2（#367 草稿）
  4. Move: position.y += sign(target - y) * SPEED * factor * delta
  5. Clamp: position.y = clamp(y, min_y, max_y)
```

### Ball Resolution

```gdscript
func _resolve_ball() -> Node2D:
    # Primary: sibling "Ball" in parent
    # Fallback: scene-tree "Game/Ball" path
    # Returns: Node2D or null (graceful)
```

Two-stage lookup handles both `game.tscn` hierarchy and headless test context.

### AI State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_ball_node` | Node2D | Cached ball reference |
| `_ai_delay_timer` | float | Remaining delay before next target update |
| `_ai_target_y` | float | Stale target Y (updated on delay expiry) |
| `_ai_error_offset` | float | Last applied position error |

### Edge Cases

| # | Case | Behavior |
|---|------|----------|
| 1 | Ball node missing | `_ai_process()` early-returns; paddle stays still |
| 2 | Ball at extreme Y | Target calculated but clamp bounds enforced |
| 3 | Frame spike (delta > 0.1) | Speed × delta may jump, but clamp catches it |
| 4 | Distance = 40px (threshold) | Speed boost applied (`dist >= threshold`) |
| 5 | Two AI paddles | Each tracks own `_ai_target_y` independently |
| 6 | Headless mode | `_resolve_ball()` fallback + `_ball_node` null-guard |

### Player Backward Compatibility

When `mode == Mode.PLAYER`:
- `_process()` skips AI dispatch, runs original input logic unchanged
- InputMap binding guard (`if mode == Mode.PLAYER`) prevents unnecessary actions in AI mode

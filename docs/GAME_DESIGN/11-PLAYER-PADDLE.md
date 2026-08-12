# Player Paddle & Input

> Reference: ../DESIGN/288-player-paddle.md

## Overview

The player paddle is a self-contained Area2D component with code-based InputMap bindings,
vertical movement, and boundary clamping. It can be dropped into any scene and works immediately
with zero external dependencies beyond Godot built-in APIs.

## 竖屏轴交换（#383, 2026-08-13）

> **轴交换+竖屏（P0 前置）**：Mini Pong 由横屏 1280×720（左右对打）切换为 **竖屏 720×1280（上下对打）**。
> 本 PR 为机械坐标轴交换（`content_ownership: mechanical`），手感数值（#367 定稿）不变。
> 语义：paddle 上下分列、沿 X 移动；球沿 Y 垂直对打、上下出界得分；左右墙反弹。
> 以下各章节的横屏描述（paddle_up/down、Y 轴移动）已被本节取代，竖屏语义以本节为准。

### 设计决策

- **竖屏对打语义**：Rogue Pong 攻城战 P0 前置 —— 垂直攻防主运动轴是 Y，砖墙横跨 720px、攻防纵深 1280px，后续 feature 直接建立在本竖屏坐标系上（「坐标只改一遍」，DESIGN §1）。
- **机械映射、语义唯一**：每个轴交换点只有一种正确改法（DESIGN §3 总表）；FSM/scoring 信号链零改动。
- **一次改完**：无 `PORTRAIT` 开关、无根节点旋转；横屏能力丢弃（DESIGN §9）。

### 常量（constants.gd）

| 常量 | 值 | 语义 |
|------|-----|------|
| `SCREEN_WIDTH` | 720 | 竖屏宽 |
| `SCREEN_HEIGHT` | 1280 | 竖屏高 |
| `PADDLE_WIDTH` | 120.0 | 横向长度（挡板横置） |
| `PADDLE_HEIGHT` | 20.0 | 纵向厚度 |
| `FALLBACK_VIEWPORT_X` | 720.0 | headless 回退（原 `FALLBACK_VIEWPORT_Y`） |

### 输入与移动

| 动作 | 键 | 语义 |
|------|-----|------|
| `paddle_left` | A, ← | 沿 X 左移 |
| `paddle_right` | D, → | 沿 X 右移 |

- 旧动作 `paddle_up` / `paddle_down`（W/S/↑/↓）**已从 paddle.gd 删除**（test_paddle TC-A1 断言动作不存在）。
- 每帧：`position.x += move * SPEED * delta`，夹取 `min_x / max_x`。
- 边界：`min_x = PADDLE_WIDTH/2 = 60`，`max_x = SCREEN_WIDTH − 60 = 660`（启动时 `_ready()` 同样夹取）。

### AI 追踪（沿 X）

- 目标：`_ai_target_x = ball.global_position.x + _ai_error_offset`。
- 距离：`dist = |position.x − _ai_target_x|`；延迟/误差/速度阈值公式不变（#367 草稿值）。
- 移动：`position.x += sign(_ai_target_x − position.x) * SPEED * factor * delta`，夹取同玩家。

### 数据流

```
_ready()
  ├── InputMap 绑定 paddle_left / paddle_right（has_action 防重）
  ├── 边界计算（viewport 宽 720 或 FALLBACK_VIEWPORT_X）
  └── 初始位置夹取 position.x = clamp(x, 60, 660)

_process(delta) — 每帧
  ├── 读输入（left/right，同时按 → 0）
  ├── position.x += move * SPEED * delta
  └── clamp(position.x, min_x, max_x)
```

## 竖屏轴交换（#383, 2026-08-13）

> 本节为**当前设计**；下方旧节（InputMap Bindings / Movement & Clamping / AI Opponent Mode 处理流程）为 #383 之前的横屏语义，仅作历史参考。
> 契约来源：`docs/DESIGN/383-axis-swap-portrait.md`。手感数值（#367 定稿）不变，仅轴语义与输入映射变更。

| 维度 | 竖屏（当前） | 横屏（#383 前） |
|------|-------------|----------------|
| 输入动作 | `paddle_left`(A/←) + `paddle_right`(D/→)；`paddle_up`/`paddle_down` 已删除（test_paddle 断言动作不存在） | W/S/↑/↓ |
| 移动轴 | X：`position.x += move * SPEED * delta` | Y |
| 边界夹取 | `min_x = PADDLE_WIDTH/2 = 60`、`max_x = 720 − 60 = 660`（启动时 clamp 初始位置） | min_y / max_y |
| 挡板尺寸 | 120 长 × 20 厚（`PADDLE_WIDTH=120` 横向长度、`PADDLE_HEIGHT=20` 纵向厚度） | 20×120 竖置 |
| 场景位置 | 玩家 (360,1240)、AI (360,40) mode=1 | (50,360) / (1230,360) |
| AI 追踪 | `_ai_target_x = ball.global_position.x + _ai_error_offset`；`dist = |position.x − _ai_target_x|`；延迟/误差/速度阈值公式不变（阈值 = `ai_position_error×2` = 48px） | 追踪球 Y |
| Headless fallback | `FALLBACK_VIEWPORT_X = CONSTS.SCREEN_WIDTH = 720` | FALLBACK_VIEWPORT_Y = 720 |

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

# Ball Physics & Collision

> Reference: ../DESIGN/287-ball-physics.md

## Overview

The ball is a self-contained Area2D component that manages its own velocity, collision responses,
speed escalation, scoring signals, and serve logic. Movement is handled via manual `_process(delta)`
position updates — no physics engine involvement — providing deterministic, arcade-style linear motion
with precise control over bounce angles.

The ball operates with zero autoload dependencies beyond Godot built-in APIs. It connects to
walls via `body_entered`, paddles via `area_entered`, and emits `score(side: int)` on boundary exit.

## 竖屏轴交换（#383, 2026-08-13）

> 本节为**当前设计**；下方旧节（Wall Bounce / Scoring / Serve / Data Flow / Edge Cases / Integration Points）为 #383 之前的横屏语义，仅作历史参考。
> 契约来源：`docs/DESIGN/383-axis-swap-portrait.md`。纯机械映射、无 taste 分支；手感数值（#367 定稿 11 参数）不变；`game_state_machine.gd` / `scoring_manager.gd` 零改动。

| 语义维度 | 竖屏（当前） | 横屏（#383 前） |
|---------|-------------|----------------|
| 画幅 | **720×1280** | 1280×720 |
| 对打主轴 | Y（上下对打，竖屏攻防纵深） | X（左右对打） |
| 发球 | `velocity = Vector2(sin θ, cos θ·dir) * speed`，θ∈±30°、dir=±1 随机 | 水平 `(cos θ·dir, sin θ)` |
| 得分边界 | `y < -R` → `score.emit(0)`（player 穿 AI 底线）；`y > SCREEN_HEIGHT+R` → `score.emit(1)`（ai 穿玩家底线） | X 左右出界 |
| 墙反弹 | 左右墙 `velocity.x *= -1`（group "walls"：LeftWall/RightWall 竖墙） | 上下墙 Y 反转 |
| paddle 反弹 | offset = `(ball.x − paddle.x) / (shape.size.x / 2)`（长度读 X=120）；方向 `-sign(velocity.y)` | offset 沿 Y、读 `size.y` |
| 反卡位 | `position.y += sign(velocity.y) * push_dist`（沿主轴 Y 推离） | X 方向推离 |
| NaN 防护 | 重置 `Vector2.DOWN * speed` | `Vector2.RIGHT * speed` |
| ScoreZone 接线 | ScoreZoneTop(360,0) → emit(0)=player；ScoreZoneBottom(360,1280) → emit(1)=ai | 左右竖区 |

### 数据流差异（#383 后）

```
_process(delta)
  ├── X boundary safety net: clamp + 反弹（左右墙）
  └── Y boundary: emit score(side) + serve()（上下得分区）
```

Headless fallback 随画幅更新：`FALLBACK_SCREEN_WIDTH=720`、`FALLBACK_SCREEN_HEIGHT=1280`（均取 `CONSTS.SCREEN_*`）。

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

> **Constants migration (#295):** All ball physics constants are now sourced from `gdscripts/constants.gd`
> (`class_name GameConstants`). `ball.gd` references `CONSTS.BALL_INITIAL_SPEED` etc. instead
> of local `const` declarations. Headless fallback values remain as inline fallbacks for test contexts.

## HUD 消费（#448）

`ball.speed` 是公开只读标量（不乘 `speed_scale`；缓时/冻结期间显示保持当前标量 = 已知行为，显示语义字面执行）。速度变化点（paddle 反弹 +5%、发球重置 300）全部位于 ball.gd，无 `speed_changed` 信号可订阅，故 GameHUD 以 10Hz Timer 轻量轮询读取并显示 `round(speed)`（单位 px/s，见 GDD 16-UI-SYSTEM）。

## 手感校准草稿（taste-draft #367）

> 机制稳定、数值会变：本节记录手感校准的**机制**与当前草稿值；候补值、影响说明、情感断言以 `docs/TASTE.md` 为单一事实源（用户定稿后回写 TASTE.md §4，GDD 数值随定稿更新）。

| 项 | 说明 |
|----|------|
| 参数范围 | 11 个手感参数（球速 4 + 反弹角 1 + 操控 1 + AI 5）集中在 `gdscripts/constants.gd`，机械常量（SCREEN/VERSION/RADIUS/SCORING/COLORS）不动 |
| 草稿标注 | 每条带 `# DRAFT` 注释（该值影响什么 + 2–3 候补值 + 情感断言），`grep -c "# DRAFT"` == 11 |
| 消费链 | `CONSTS → ball.gd / paddle.gd @export 默认值`（Main.tscn 无导出覆盖）→ 改常量即改手感 |
| 校准接口 | `docs/TASTE.md`：候补值表（§1）+ 试玩剧本（§2，自动对打 + 手动一局）+ 情感断言清单（§3） |
| 红线 | 单次 rally 球速跳变 ≤ 20%（草稿 `BALL_SPEED_INCREMENT=1.07` → +7%）；AI 追击速度（`AI_SPEED_BOOST`）不属红线范围 |
| 状态 | 草稿已 merge（#371），父 Issue #367 保持 open（`status/human-review` + assigned devvi）等用户定稿 |

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
| Angle mapping | `impact_offset × 55°` → angle range [-55°, +55°]（#367 草稿值） |
| Center hit | impact_offset ≈ 0 → near-horizontal rebound |
| Edge hit | impact_offset ≈ ±1 → steep 60° angle |

### Speed Escalation

| Parameter | Value |
|-----------|-------|
| Per-hit multiplier | `speed *= 1.07` (+7%，#367 草稿值) |
| Cap | `INITIAL_SPEED × 1.9` ≈ 627 px/s（#367 草稿值） |
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
| Angle | Random within ±30° from horizontal（#367 草稿值 `BALL_SERVE_ANGLE_RANGE`） |
| Speed | Reset to `initial_speed`（草稿 330 px/s，#367） |
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
| Walls (Main.tscn) | Ball `body_entered` checks `is_in_group("walls")` for Y-bounce |
| Scoring (#291) | Ball emits `score(side: int)`, 0=left scores, 1=right scores. Also detected by ScoreZone Area2D body_entered (#295). |
| Neon visuals (#289) | `ball_trail.gd` duck-types `parent.get("velocity")` — works with Area2D |
| Main scene | `Main.tscn` instances `ball.tscn` at position (640, 360) |

## Test Coverage

The test suite (`tests/test_ball.gd`, 461 lines, 35+ test cases) covers:

| Scenario | Tests | Description |
|----------|-------|-------------|
| A: Scene integrity | 4 | ball.tscn + Main.tscn node hierarchy, shapes, project.godot main_scene |
| B: Wall bounce | 4 | Y reversal, X unchanged, speed unchanged, cooldown |
| C: Paddle collision | 4 | Center/edge angle variation, X reversal on both directions |
| D: Speed escalation | 3 | +5% per hit, 2× cap, reset on serve |
| E: Scoring | 2 | Right boundary → score(0), left boundary → score(1) |
| F: Serve | 3 | Center position, random direction 50/50, angle within ±45° |
| G: Headless compile | 1 | NaN guard resets velocity |
| H: Cooldown | 2 | Duplicate suppression, expiry and re-arm |

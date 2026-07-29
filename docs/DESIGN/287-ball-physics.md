# Design: 球物理与碰撞 — Ball Physics & Collision

> **Parent Issue:** #287
> **Agent:** game-plan-agent
> **Date:** 2026-07-29
> **Approach:** A — 自包含 `ball.gd` Area2D + 手动 `_process` (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                    ← MODIFIED: set run/main_scene="res://scenes/game.tscn"
├── scenes/
│   ├── world_environment.tscn       ← unchanged
│   ├── player_paddle.tscn           ← unchanged (player paddle, Area2D, 20×120)
│   ├── ball.tscn                    ← NEW: Area2D root + CollisionShape2D + ColorRect
│   └── game.tscn                    ← NEW: arena scene — walls + ball + paddle instances
├── gdscripts/
│   ├── paddle.gd                    ← unchanged (WASD input, boundary clamp)
│   ├── ball.gd                      ← NEW: physics, collision, scoring, serve
│   ├── ball_trail.gd                ← PATCH: update to read velocity from Area2D ball
│   ├── score_flash.gd               ← unchanged (to be wired by future scoring issue)
│   └── neon_glow.gdshader           ← unchanged (shader for glow effects)
└── assets/                          ← unused
```

**Design philosophy:** The ball is a self-contained Area2D that manages its own velocity, collision responses, and scoring signals. Like the paddle, it is a drop-in scene component — no autoload dependencies beyond Godot built-in APIs. Manual `_process(delta)` position updates provide deterministic, arcade-style linear motion with precise control over bounce angles and speed escalation.

**Why Approach A is confirmed:** The PRD's recommended Approach A is adopted without changes. Godot's RigidBody2D physics engine cannot implement "angle varies by hit position on the paddle" — that's a custom collision-response algorithm that requires manual velocity control. A PhysicsManager autoload (Approach B) adds indirection without benefit since Pong has only one moving object.

### Existing Component Compatibility

| Component | Issue | Design Resolution |
|-----------|-------|-------------------|
| `ball_trail.gd` references `CharacterBody2D` parent | Ball is `Area2D`, not `CharacterBody2D` | Patch `ball_trail.gd` — read ball's velocity from a custom `velocity` member via duck-typing (`parent.get("velocity")`) instead of typed cast |
| `paddle.gd` runs `_process` updates | Ball `area_entered` collision requires Godot's signal system to fire | No conflict — `_process` and signal callbacks run on the same thread; collisions trigger between frames |
| `score_flash.gd` expects `score_changed(side: String)` | Ball emits `score(side: int)` | Design mismatch deferred to scoring system issue (#291). Ball's `score(int)` signal is canonical for this phase. |

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Movement method | `position += velocity * delta` | Deterministic, arcade-style — no physics engine involvement |
| Collision detection | `area_entered` + `body_entered` signals | Uses Godot's built-in spatial queries; paddle is `Area2D`, walls are `StaticBody2D` |
| Continuous CD | `move_and_collide()` wrapper or sub-step sampling | Prevents high-speed ball (2x max) from tunneling through thin walls |
| Speed escalation | `speed = min(speed * 1.05, INITIAL_SPEED * 2.0)` | Simple multiply-then-clamp; no state machine needed |
| Bounce angle mapping | `impact_offset → [-1, 1] → angle ∈ [-60°, +60°]` | Linear mapping from hit position to angle; center hit = horizontal rebound |
| Serve randomness | `randf_range(-45°, 45°)` + `[-1, 1].pick_random()` | Angle within ±45° from horizontal, direction randomly left or right |
| Score signal | `signal score(side: int)` where 0=left, 1=right | Int enum avoids string parsing; matches future scoring system's expected contract |

---

## 2. New Components — Detailed Design

### 2.1 `ball.gd`

- **File:** `mini-pong/gdscripts/ball.gd`
- **Attached to:** Area2D root node of `ball.tscn`
- **Line estimate:** ~120 lines

#### Constants

```gdscript
const INITIAL_SPEED: float = 300.0        # Pixels per second at serve
const MAX_SPEED_MULTIPLIER: float = 2.0   # Speed cap: INITIAL_SPEED * 2.0
const SPEED_INCREMENT: float = 1.05       # +5% per paddle hit
const MAX_BOUNCE_ANGLE: float = 60.0      # Degrees — max rebound angle from paddle center
const SERVE_ANGLE_RANGE: float = 45.0     # Degrees — random serve angle ±45° from horizontal
const FALLBACK_SCREEN_WIDTH: float = 1280.0   # Default arena width (for headless)
const FALLBACK_SCREEN_HEIGHT: float = 720.0   # Default arena height (matches paddle fallback)
const BOUNCE_COOLDOWN_FRAMES: int = 2     # Frames to ignore duplicate collisions
const SERVE_DELAY: float = 0.5            # Seconds pause before ball starts moving after serve
const BALL_RADIUS: float = 10.0           # Radius of ball for collision margin calculations
```

#### Exported Variables (tunable in editor)

```gdscript
@export var initial_speed: float = INITIAL_SPEED
@export var max_speed_multiplier: float = MAX_SPEED_MULTIPLIER
@export var speed_increment: float = SPEED_INCREMENT
@export var max_bounce_angle: float = MAX_BOUNCE_ANGLE
@export var serve_angle_range: float = SERVE_ANGLE_RANGE
```

#### Signals

```gdscript
signal score(side: int)
# side: 0 = 左方得分（球从右侧出界）, 1 = 右方得分（球从左侧出界）
```

#### State

```gdscript
var velocity: Vector2 = Vector2.ZERO    # Current velocity (pixels/sec)
var speed: float = INITIAL_SPEED        # Current speed scalar
var screen_width: float = 0.0           # Detected viewport width
var screen_height: float = 0.0          # Detected viewport height
var _bounce_cooldown: int = 0           # Frames remaining in cooldown
var _is_serving: bool = false           # True during serve delay
```

#### Key Methods

**`_ready()` — Initialize + serve:**
```
1. Read viewport dimensions:
   a. viewport = get_viewport()
   b. screen_width = viewport_size.x > 0 ? viewport_size.x : FALLBACK_SCREEN_WIDTH
   c. screen_height = viewport_size.y > 0 ? viewport_size.y : FALLBACK_SCREEN_HEIGHT

2. Validate CollisionShape2D:
   a. Assert collision_shape.shape != null → push_error if null

3. Connect collision signals:
   a. body_entered.connect(_on_body_entered)
   b. area_entered.connect(_on_area_entered)

4. Call serve()
```

**`serve()` — Reset ball to center + launch:**
```
1. position = Vector2(screen_width / 2.0, screen_height / 2.0)
2. speed = initial_speed (reset to base on each serve)
3. velocity = Vector2.ZERO
4. _bounce_cooldown = 0
5. _is_serving = true

6. After SERVE_DELAY seconds (via await get_tree().create_timer):
   a. angle = randf_range(-serve_angle_range, serve_angle_range)  # Radians
   b. direction = [-1.0, 1.0].pick_random()  # Random left or right
   c. velocity = Vector2(cos(angle) * direction, sin(angle)) * speed
   d. _is_serving = false
```

**`_process(delta)` — Per-frame movement + boundary check:**
```
1. If _is_serving: return early

2. Guard delta:
   a. If delta <= 0.0 or delta > 0.1: return (pause / frame spike protection)

3. Guard velocity:
   a. If is_nan(velocity.x) or is_nan(velocity.y):
        velocity = Vector2.RIGHT * speed  (fallback to rightward motion)
        push_warning("ball.gd: NaN velocity detected, resetting")

4. Decrement _bounce_cooldown if > 0

5. Move ball:
   a. velocity = velocity.normalized() * speed  (re-normalize to prevent drift)
   b. position += velocity * delta

6. Check Y boundary (safety net):
   a. If position.y < -BALL_RADIUS:
        position.y = -BALL_RADIUS
        velocity.y = abs(velocity.y)  (force downward)
   b. If position.y > screen_height + BALL_RADIUS:
        position.y = screen_height + BALL_RADIUS
        velocity.y = -abs(velocity.y)  (force upward)

7. Check X boundary (score):
   a. If position.x < -BALL_RADIUS:
        emit score(1)  # Right player scores (ball exited left)
        serve()
   b. If position.x > screen_width + BALL_RADIUS:
        emit score(0)  # Left player scores (ball exited right)
        serve()
```

**`_on_body_entered(body: Node2D)` — Wall collision:**
```
1. If _bounce_cooldown > 0: return

2. If body is in group "walls" (or check by type name):
   a. velocity.y *= -1.0  (Y reversal only)
   b. _bounce_cooldown = BOUNCE_COOLDOWN_FRAMES
```

**`_on_area_entered(area: Area2D)` — Paddle collision:**
```
1. If _bounce_cooldown > 0: return

2. Check if area is a paddle (by name prefix "Paddle" or group "paddles"):
   a. paddle_center_y = area.global_position.y
   b. paddle_height = 120.0  (match paddle.gd PADDLE_HEIGHT, or read from area if available)
   c. impact_offset = (global_position.y - paddle_center_y) / (paddle_height / 2.0)
   d. impact_offset = clamp(impact_offset, -1.0, 1.0)

3. Calculate bounce angle:
   a. bounce_angle_deg = impact_offset * max_bounce_angle
   b. bounce_angle_rad = deg_to_rad(bounce_angle_deg)

4. Determine horizontal direction:
   a. direction = -sign(velocity.x)  (reverse horizontal direction)
      or: direction = 1.0 if ball was moving left (hitting left paddle),
           direction = -1.0 if ball was moving right (hitting right paddle)

5. Apply new velocity:
   a. velocity = Vector2(cos(bounce_angle_rad) * direction, sin(bounce_angle_rad))
   b. velocity = velocity.normalized()

6. Speed escalation:
   a. speed = min(speed * speed_increment, initial_speed * max_speed_multiplier)

7. Apply speed + cooldown:
   a. velocity *= speed
   b. _bounce_cooldown = BOUNCE_COOLDOWN_FRAMES

8. Push ball slightly away from paddle to prevent re-trigger:
   a. position.x += sign(velocity.x) * (BALL_RADIUS + PADDLE_WIDTH/2 + 2.0)
```

#### Integration notes

- **Paddle height:** The paddle's `PADDLE_HEIGHT = 120.0` is a constant in `paddle.gd`. The ball needs to know this value. Options: (a) hardcode 120.0 to match, (b) read from area's CollisionShape2D.shape.size.y, or (c) export a `paddle_height` variable. Approach (b) is most robust.
- **Paddle identification:** Use `area.is_in_group("paddles")` — requires paddles to call `add_to_group("paddles")` in `_ready()`. This is added as a modification to `paddle.gd`.
- **Wall identification:** Use `body.is_in_group("walls")` — game.tscn adds walls to `"walls"` group.
- **Cooldown mechanism:** Prevents `body_entered`/`area_entered` from firing multiple times on the same collision due to overlapping collision shapes. A simple frame counter (not time-based) is sufficient since collision signals fire on the main thread between frames.

### 2.2 `ball.tscn`

- **File:** `mini-pong/scenes/ball.tscn`
- **Format:** Godot 4.x text format (`format=3`)

#### Node structure (TSCN)

```ini
[gd_scene format=3]

[ext_resource type="Script" path="res://gdscripts/ball.gd" id="1_ball"]

[sub_resource type="CircleShape2D" id="circle_ball"]
radius = 10.0

[node name="Ball" type="Area2D"]
collision_layer = 4
collision_mask = 3
script = ExtResource("1_ball")

[node name="ColorRect" type="ColorRect" parent="."]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(1, 1, 1, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("circle_ball")
```

#### Collision Layer Design

| Layer | Purpose | Node(s) |
|:-----:|---------|---------|
| 1 | Walls | StaticBody2D (top/bottom) |
| 2 | Ball | Area2D (ball) — **collision_layer only** (other things detect it) |
| 3 | Paddles | Area2D (player, AI) |
| 4 | Boundaries | (reserved for future) |

**Ball collision_mask = 3** (layers 1 + 2) → detects walls and paddles.
**Ball collision_layer = 4** (layer 3) → paddles can detect the ball.

#### Key design decisions

| Decision | Value | Reason |
|----------|-------|--------|
| Root type | `Area2D` | Collision detection without physics simulation |
| Collision shape | `CircleShape2D`, radius=10.0 | Matches ball visual; circular collision is simpler than rectangular for bouncing |
| ColorRect offsets | centered on Area2D origin | `(-10, -10)` to `(10, 10)` = 20×20 centered |
| ColorRect color | `Color(1, 1, 1, 1)` white | Placeholder; neon visual system (#289) will override via shader |
| No load_steps | Omitted (Godot auto-counts) | Simpler maintenance; eliminates load_steps mismatch bugs |

### 2.3 `game.tscn`

- **File:** `mini-pong/scenes/game.tscn`
- **Format:** Godot 4.x text format (`format=3`)

#### Node structure (TSCN)

```ini
[gd_scene format=3]

[ext_resource type="PackedScene" path="res://scenes/ball.tscn" id="1_ball"]
[ext_resource type="PackedScene" path="res://scenes/player_paddle.tscn" id="2_player_paddle"]

[sub_resource type="RectangleShape2D" id="rect_wall_top"]
size = Vector2(1280, 10)

[sub_resource type="RectangleShape2D" id="rect_wall_bottom"]
size = Vector2(1280, 10)

[node name="Game" type="Node2D"]

[node name="TopWall" type="StaticBody2D" parent="." groups=["walls"]]
position = Vector2(640, 5)

[node name="CollisionShape2D" type="CollisionShape2D" parent="TopWall"]
shape = SubResource("rect_wall_top")

[node name="BottomWall" type="StaticBody2D" parent="." groups=["walls"]]
position = Vector2(640, 715)

[node name="CollisionShape2D" type="CollisionShape2D" parent="BottomWall"]
shape = SubResource("rect_wall_bottom")

[node name="Ball" parent="." instance=ExtResource("1_ball")]
position = Vector2(640, 360)

[node name="PlayerPaddle" parent="." instance=ExtResource("2_player_paddle")]
position = Vector2(50, 360)

; AI paddle slot (reserved for future issue)
; [node name="AIPaddle" parent="." instance=ExtResource("3_ai_paddle")]
; position = Vector2(1230, 360)
```

#### Arena Layout

```
(0, 0) ────────────────────────────────────────────── (1280, 0)
│                                                       │
│   TopWall (1280×10, y=5)                              │
│                                                       │
│   PlayerPaddle (x=50, y=360)     Ball (center)        │
│   [│]                            (●)                  │
│   [│]                                                 │
│   [│]                                                 │
│                                                       │
│   BottomWall (1280×10, y=715)                         │
│                                                       │
(0, 720) ────────────────────────────────────────────── (1280, 720)
```

#### Key design decisions

| Decision | Value | Reason |
|----------|-------|--------|
| Wall thickness | 10px | Thin enough to not interfere visually, thick enough for reliable collision |
| Wall type | `StaticBody2D` | Fixed position; ball detects via `body_entered` |
| Wall grouping | `groups=["walls"]` | Enables ball to identify walls without type-string matching |
| Player paddle position | x=50 (left side) | 50px inset from left edge |
| AI paddle position | x=1230 (right side) | 50px inset from right edge; reserved for future issue |
| Ball initial position | center (640, 360) | Matches `serve()` default |
| Root type | `Node2D` | Simple container; no logic attached |

### 2.4 `ball_trail.gd` — Patch

- **File:** `mini-pong/gdscripts/ball_trail.gd`
- **Change:** Replace `CharacterBody2D` cast with duck-typed velocity access

#### Current code (lines 25-26):
```gdscript
var parent_body: CharacterBody2D = get_parent() as CharacterBody2D
```

#### Patched code:
```gdscript
# Ball is Area2D, not CharacterBody2D — read velocity via duck-typing
var parent := get_parent()
var parent_velocity: Vector2 = parent.get("velocity") if parent else Vector2.ZERO
```

#### Velocity reading (line 29):
```gdscript
# Before: var speed: float = parent_body.velocity.length()
# After:
var speed: float = parent_velocity.length()
```

No other changes needed — the rest of the script uses `speed` for particle emission control.

### 2.5 `paddle.gd` — Minor Addition

- **File:** `mini-pong/gdscripts/paddle.gd`
- **Change:** Add `add_to_group("paddles")` in `_ready()`

Add after line 45 (after initial position clamp):
```gdscript
add_to_group("paddles")
```

This enables the ball's `_on_area_entered()` to identify paddles without string-matching on node names.

---

## 3. Existing Component Modifications

| File | Change | Why |
|------|--------|-----|
| `mini-pong/project.godot` | Set `run/main_scene="res://scenes/game.tscn"` | CI validation (`--headless --quit`) needs a main scene to load; game.tscn is the arena |
| `mini-pong/gdscripts/ball_trail.gd` | Replace `CharacterBody2D` cast with `get("velocity")` | Ball is `Area2D`, not `CharacterBody2D` — trail must work with either type |
| `mini-pong/gdscripts/paddle.gd` | Add `add_to_group("paddles")` in `_ready()` | Enables ball's `area_entered` to identify paddle collisions by group |

### File Manifest

| File | Type | Action | Est. Lines |
|------|------|--------|:----------:|
| `mini-pong/gdscripts/ball.gd` | GDScript | **CREATE** | +120 |
| `mini-pong/scenes/ball.tscn` | Godot Scene | **CREATE** | +25 |
| `mini-pong/scenes/game.tscn` | Godot Scene | **CREATE** | +45 |
| `mini-pong/project.godot` | Config | **MODIFY** | 1 line |
| `mini-pong/gdscripts/ball_trail.gd` | GDScript | **MODIFY** | ~3 lines |
| `mini-pong/gdscripts/paddle.gd` | GDScript | **MODIFY** | +1 line |

---

## 4. Data Flow

### Flow 1: Serve → Movement → Wall Bounce → Score (happy path)

```
Game loads → ball.tscn instantiated at center
  │
  ▼
_ready() → connect signals → serve()
  │
  ▼
serve() → reset position to center (640, 360)
  │
  ├── speed = initial_speed (300 px/s)
  ├── await 0.5s delay
  ├── angle = randf_range(-45°, 45°)
  ├── direction = [-1, 1].pick_random()
  └── velocity = Vector2(cos(angle)*dir, sin(angle)) * speed
  │
  ▼
_process(delta) loop
  │
  ├── position += velocity * delta
  │
  ├── [HIT TopWall] → body_entered fires
  │   ├── velocity.y *= -1.0
  │   └── _bounce_cooldown = 2
  │
  ├── [HIT BottomWall] → body_entered fires
  │   ├── velocity.y *= -1.0
  │   └── _bounce_cooldown = 2
  │
  └── [EXIT right boundary] → position.x > 1280
      ├── emit score(0)  # Left player scores
      └── serve() → reset cycle
```

### Flow 2: Paddle Collision → Angle + Speed Change

```
_process loop → ball moving right → hits player paddle
  │
  ▼
area_entered(area) fires
  │
  ├── Guard: _bounce_cooldown > 0? → return
  ├── Verify: area.is_in_group("paddles")? → yes
  │
  ├── Read paddle height:
  │   └── area.get_node("CollisionShape2D").shape.size.y → 120.0
  │
  ├── Calculate impact_offset:
  │   impact_offset = (ball.y - paddle.y) / (120.0 / 2.0)
  │   impact_offset = clamp(impact_offset, -1.0, 1.0)
  │
  │   Example: ball at y=340, paddle center at y=360
  │   → impact_offset = (340-360)/60 = -0.33 (above center)
  │   → bounce_angle = -0.33 * 60° = -20° (upward)
  │
  ├── Apply new velocity:
  │   direction = -sign(old_velocity.x)  # Reverse horizontal
  │   velocity = Vector2(cos(-20°) * dir, sin(-20°))
  │
  ├── Speed escalation:
  │   speed = min(speed * 1.05, initial_speed * 2.0)
  │   velocity *= speed
  │
  ├── Anti-stick:
  │   position.x += sign(velocity.x) * (10 + 10 + 2)
  │   (ball radius + paddle half-width + margin)
  │
  └── _bounce_cooldown = 2
```

### Flow 3: NaN Velocity Recovery

```
_process(delta)
  │
  ├── is_nan(velocity.x)?
  │   ├── velocity = Vector2.RIGHT * speed  (safe default)
  │   └── push_warning("NaN velocity detected")
  │
  └── Continue normal _process
```

### Flow 4: Cooldown Gate (Prevent Double-Bounce)

```
Frame N: ball hits paddle
  ├── area_entered fires → processes collision
  ├── _bounce_cooldown = 2
  └── ball pushed away from paddle

Frame N+1:
  ├── _bounce_cooldown = 1
  └── If overlapping paddle collision shape still → area_entered fires → GUARD: return

Frame N+2:
  ├── _bounce_cooldown = 0
  └── Ball now clear of paddle → no further collision until next hit
```

---

## 5. Edge Cases & Error Handling

| # | Edge Case | Mitigation |
|---|-----------|------------|
| 1 | **Ball tunnels through thin wall at 2x speed** | The ball radius is 10px and wall thickness is 10px. At max speed (600 px/s) and 60 FPS, the ball moves 10px/frame — equal to the wall thickness. Tunneling is unlikely but possible at lower FPS. Mitigation: `_process` guards `delta > 0.1` (prevents single-frame jumps > 60px). For future: sub-step sampling if issues arise. |
| 2 | **`body_entered` / `area_entered` fires multiple times per collision** | `_bounce_cooldown` (2 frames) suppresses duplicate signals. Combined with anti-stick position push. |
| 3 | **NaN velocity from edge-case collision math** | `_process` checks `is_nan(velocity.x)` and `is_nan(velocity.y)` every frame; resets to `Vector2.RIGHT * speed` with warning. |
| 4 | **`impact_offset` out of range** | `clamp(impact_offset, -1.0, 1.0)` prevents angles beyond ±max_bounce_angle. |
| 5 | **Serve direction too vertical** | `randf_range(-45°, 45°)` keeps serve within ±45° of horizontal. Ball will always move predominantly horizontally. |
| 6 | **Ball spawns inside a collision body** | `serve()` positions ball at arena center (640, 360) — far from any wall or paddle. SERVE_DELAY (0.5s) gives paddles time to move away. |
| 7 | **delta = 0 or very large** (pause / frame spike) | `_process` guards: `if delta <= 0.0 or delta > 0.1: return`. Skips movement for abnormal frames. |
| 8 | **Paddle height not readable from CollisionShape2D** | Hardcoded fallback to `120.0` matches `paddle.gd`'s `PADDLE_HEIGHT` constant. Robust `get_node_or_null` pattern guards against null. |
| 9 | **Ball overlaps both a wall and a paddle in same frame** | Signal order is non-deterministic. Priority: paddle collision is more gameplay-significant. The `_on_area_entered` handler runs independently; if it succeeds (sets cooldown), the subsequent `_on_body_entered` for the wall is suppressed by the cooldown gate. |
| 10 | **Headless mode — no viewport dimensions** | `FALLBACK_SCREEN_WIDTH=1280.0`, `FALLBACK_SCREEN_HEIGHT=720.0` hardcoded defaults. Matches paddle's fallback pattern. |

---

## 6. Test Case Descriptions

### Scenario A: Scene integrity

- **TC-A1 — Ball node hierarchy:** Load `ball.tscn` → verify root is `Area2D` with children `ColorRect` and `CollisionShape2D`. Precondition: scene file exists.
- **TC-A2 — CollisionShape2D non-null:** Instantiate ball scene → verify `$CollisionShape2D.shape` is a `CircleShape2D` with radius=10.0.
- **TC-A3 — Game scene hierarchy:** Load `game.tscn` → verify `TopWall`, `BottomWall` exist as `StaticBody2D` in group `"walls"`. Verify `Ball` and `PlayerPaddle` instance nodes exist.
- **TC-A4 — project.godot main_scene:** Verify `run/main_scene` is set to `"res://scenes/game.tscn"`.

### Scenario B: Wall bounce (Y-reversal)

- **TC-B1 — Top wall bounce:** Ball moving upward (velocity.y < 0) approaches y=5 → verify `velocity.y` becomes positive after collision (Y-reversed).
- **TC-B2 — Bottom wall bounce:** Ball moving downward (velocity.y > 0) approaches y=715 → verify `velocity.y` becomes negative after collision.
- **TC-B3 — X velocity unchanged:** After top/bottom wall bounce → verify `velocity.x` unchanged (only Y reversed).
- **TC-B4 — Speed unchanged after wall bounce:** After wall bounce, speed scalar is the same as before the bounce.

### Scenario C: Paddle collision — angle variation

- **TC-C1 — Center hit:** Ball hits paddle at center (impact_offset ≈ 0) → bounce angle ≈ 0° (nearly horizontal rebound).
- **TC-C2 — Top-edge hit:** Ball hits paddle near top (impact_offset ≈ -1.0) → bounce angle ≈ -60° (steep upward).
- **TC-C3 — Bottom-edge hit:** Ball hits paddle near bottom (impact_offset ≈ +1.0) → bounce angle ≈ +60° (steep downward).
- **TC-C4 — X-direction reversed:** After any paddle hit → verify `velocity.x` sign is opposite of pre-collision.

### Scenario D: Speed escalation

- **TC-D1 — Speed +5% per hit:** Hit paddle → verify `speed_new ≈ speed_old * 1.05`.
- **TC-D2 — Speed cap at 2x:** Hit paddle repeatedly until speed reaches initial_speed * 2.0 → verify next hit does not increase speed beyond cap.
- **TC-D3 — Speed reset on serve:** After speed escalation, ball exits boundary → serve() resets speed to initial_speed.

### Scenario E: Scoring

- **TC-E1 — Right boundary exit:** Ball moves right, crosses x > 1280 → verify `score(0)` signal emitted (left scores).
- **TC-E2 — Left boundary exit:** Ball moves left, crosses x < 0 → verify `score(1)` signal emitted (right scores).
- **TC-E3 — Serve after score:** After score signal, verify ball position resets to center and new serve launches.

### Scenario F: Serve

- **TC-F1 — Serve from center:** After `serve()` → verify `position == Vector2(640, 360)`.
- **TC-F2 — Random direction:** Call `serve()` 20 times → verify roughly equal left/right split (±2 stddev from 10 each).
- **TC-F3 — Serve angle range:** After serve → verify `abs(atan2(velocity.y, abs(velocity.x))) ≤ 45°`.
- **TC-F4 — Serve delay:** After `serve()` called → verify ball does not move for 0.5s, then moves.

### Scenario G: Headless compilation

- **TC-G1 — Zero exit code:** Run `godot --path mini-pong/ --headless --quit` → exit code 0.
- **TC-G2 — No script errors:** Verify output does not contain "SCRIPT ERROR" or "Parse Error".
- **TC-G3 — NaN guard:** Force velocity to NaN → verify warning emitted and velocity reset to safe value.

### Scenario H: Cooldown mechanism

- **TC-H1 — Duplicate suppression:** Trigger collision, then trigger same collision type within 2 frames → verify second event is ignored.
- **TC-H2 — Cooldown expiration:** Trigger collision, wait 3 frames, trigger again → verify second event is processed.

---

## 7. Implementation Notes

1. **Godot 4.x API specifics:**
   - `randf_range()` returns radians when used with `cos()`/`sin()` — use `deg_to_rad()` for angle calculations
   - `is_nan()` is a global function (not `Vector2.is_nan()`)
   - `clamp()` is a global function, takes `(value, min, max)` → returns clamped value
   - `Array.pick_random()` available on Godot 4.x

2. **TSCN collision layer encoding:**
   - `collision_layer = 4` → bit 2 set (1 << 2 = 4)
   - `collision_mask = 3` → bits 0 and 1 set (1 << 0 + 1 << 1 = 3)
   - Walls use layer 1 (no mask needed — they don't detect anything)
   - Paddles use layer 2, mask includes layer 3 (to detect ball)

3. **Signal connection in `_ready()`:**
   ```gdscript
   body_entered.connect(_on_body_entered)
   area_entered.connect(_on_area_entered)
   ```
   Use `connect()` rather than editor signal connections — ball.tscn has no editor UI to configure signals.

4. **Anti-stick position push:** After paddle collision, push the ball `sign(velocity.x) * 22.0` pixels. This is ball_radius (10) + paddle_half_width (10) + margin (2). The 2px margin ensures the collision shape no longer overlaps on the next frame.

5. **Re-normalization in `_process`:** `velocity = velocity.normalized() * speed` ensures the velocity magnitude always matches `speed`. Without this, floating-point drift can cause the ball to gradually speed up or slow down over many bounces.

6. **`await` in `serve()`:** `_is_serving` flag + `await get_tree().create_timer(SERVE_DELAY).timeout` is the correct non-blocking pattern. Do NOT use `OS.delay_msec()` (blocks main thread).

7. **ball_trail.gd compatibility:** The trail script currently assumes the parent has a `.velocity` property (CharacterBody2D). After patching, it reads `parent.get("velocity")` which works for both CharacterBody2D (native property) and our Area2D + ball.gd (custom member var). This preserves backward compatibility.

8. **CI compatibility:** The existing CI step `godot --path mini-pong/ --headless --quit` will validate the new files. After setting `run/main_scene`, `_ready()` will fire on all nodes, signaling the full startup path.

---

## 8. Verification Checklist

- [ ] `ball.tscn` loads without parse errors
- [ ] `game.tscn` loads without parse errors
- [ ] `ball.gd` compiles without script errors
- [ ] Wall bounce: `velocity.y *= -1` on body_entered
- [ ] Paddle angle: impact_offset maps to correct bounce angle
- [ ] Speed escalation: +5% per hit, capped at 2x
- [ ] Score signal: emitted on left/right boundary exit
- [ ] Serve: center position, random direction within ±45°
- [ ] Cooldown: no double-bounce within 2 frames
- [ ] NaN guard: velocity reset on NaN detection
- [ ] `godot --headless --quit` exit code 0

# DESIGN: 玩家挡板与输入 — Player Paddle & Input

> **Parent Issue:** #288
> **Agent:** game-plan-agent
> **Date:** 2026-07-29
> **Approach:** A — 场景化 Area2D + 代码 InputMap (PRD recommendation, confirmed)

---

## 1. Architecture Overview

```
mini-pong/
├── project.godot                    ← unchanged (no [input] section)
├── scenes/
│   ├── world_environment.tscn       ← unchanged (glow 0.6)
│   └── player_paddle.tscn          ← NEW: Area2D root + ColorRect + CollisionShape2D
├── gdscripts/
│   └── paddle.gd                    ← NEW: movement, InputMap binding, clamp
├── assets/                          ← unused
└── tests/                           ← unused

Node tree (player_paddle.tscn):
Area2D (root, paddle.gd attached)
├── ColorRect (visual, 20×120, white)
└── CollisionShape2D (shape=RectangleShape2D, size=20×120)
```

**Design philosophy:** The paddle is an independent, self-contained scene component. It owns its InputMap bindings, movement logic, and boundary clamping — no external dependencies beyond Godot built-in APIs. The paddle can be dropped into any scene and works immediately.

**Why Approach A:** The PRD's recommended Approach A is confirmed. Scene-based encapsulation (`.tscn` + `.gd`) matches Godot 4.x best practices and enables editor preview. Code-based InputMap binding avoids `project.godot` ConfigFile parsing bugs. The feature is a greenfield addition — zero modified files, zero interference with the existing scaffold.

---

## 2. New Components — Detailed Design

### 2.1 `paddle.gd`

- **File:** `mini-pong/gdscripts/paddle.gd`
- **Attached to:** Area2D root node of `player_paddle.tscn`
- **Line estimate:** ~45 lines

#### Constants

```gdscript
const SPEED: float = 400.0           # Pixels per second, multiplied by delta
const PADDLE_WIDTH: float = 20.0     # Match ColorRect size
const PADDLE_HEIGHT: float = 120.0   # Match ColorRect size
const FALLBACK_VIEWPORT_Y: float = 720.0  # Default viewport height if headless
```

#### State

```gdscript
var min_y: float = 0.0   # Top clamp boundary (half_height)
var max_y: float = 0.0   # Bottom clamp boundary (viewport.y - half_height)
```

#### Signals

None emitted. The paddle is purely input-driven — no external communication needed for this phase.

#### Key Methods

**`_ready()`** — InputMap binding + boundary calculation:

```
1. InputMap binding (guard with has_action to prevent duplicates):
   a. If not has_action("paddle_up"):
        - add_action("paddle_up")
        - Create InputEventKey for KEY_W → action_add_event("paddle_up", event)
        - Create InputEventKey for KEY_UP → action_add_event("paddle_up", event)
   b. If not has_action("paddle_down"):
        - add_action("paddle_down")
        - Create InputEventKey for KEY_S → action_add_event("paddle_down", event)
        - Create InputEventKey for KEY_DOWN → action_add_event("paddle_down", event)

2. Boundary calculation:
   a. Get viewport_size from get_viewport().get_visible_rect().size
   b. If viewport_size.y == 0 (headless fallback), use FALLBACK_VIEWPORT_Y
   c. Set half_height = PADDLE_HEIGHT / 2.0
   d. Set min_y = half_height
   e. Set max_y = viewport_size.y - half_height

3. Clamp initial position: position.y = clamp(position.y, min_y, max_y)
```

**`_process(delta)`** — Per-frame movement + clamp:

```
1. Read input:
   a. up = Input.is_action_pressed("paddle_up")
   b. down = Input.is_action_pressed("paddle_down")

2. Calculate movement (simultaneous up+down cancels to zero):
   a. move = 0.0
   b. if up and not down:   move = -1.0
   c. if down and not up:   move = +1.0
   d. if up and down:       move = 0.0

3. Apply movement:
   position.y += move * SPEED * delta

4. Clamp:
   position.y = clamp(position.y, min_y, max_y)
```

#### Integration notes

- **No autoload dependency** — uses only `Input`, `InputMap`, `get_viewport()`
- **No signal connections** — self-contained
- **Concurrency-safe** — `has_action()` guard prevents duplicate InputMap entries if scene is re-instantiated
- **Headless-safe** — fallback viewport height prevents zero-division/null crashes when `get_viewport().get_visible_rect().size` returns (0,0)

### 2.2 `player_paddle.tscn`

- **File:** `mini-pong/scenes/player_paddle.tscn`
- **Format:** Godot 4.x text format (`format=3`)
- **UID:** Assign a unique `uid://` at creation time (Godot generates this)

#### Node structure (TSCN pseudocode)

```ini
[gd_scene load_steps=3 format=3 uid="uid://<generated>"]

[ext_resource type="Script" path="res://gdscripts/paddle.gd" id="1_paddle"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_xxxxx"]
size = Vector2(20, 120)

[node name="PlayerPaddle" type="Area2D"]
script = ExtResource("1_paddle")

[node name="ColorRect" type="ColorRect" parent="."]
offset_left = -10.0
offset_top = -60.0
offset_right = 10.0
offset_bottom = 60.0
color = Color(1, 1, 1, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_xxxxx")
```

#### Key design decisions

| Decision | Value | Reason |
|----------|-------|--------|
| Root type | `Area2D` | Collision detection without physics simulation |
| ColorRect offsets | centered on Area2D origin | `(-10, -60)` to `(10, 60)` = 20×120 around origin |
| ColorRect color | `Color(1, 1, 1, 1)` white | Placeholder; visual system (#291) will override |
| CollisionShape2D shape | `RectangleShape2D` size=(20, 120) | Exact match to ColorRect for precise collision |
| Node name | `PlayerPaddle` | PascalCase, distinct from future AI paddle |

---

## 3. Data Flow

### Flow 1: Normal movement (happy path)

```
Scene loads
  │
  ▼
_ready() fires
  ├── InputMap: paddle_up bound (W, ↑), paddle_down bound (S, ↓)
  ├── Boundary: min_y = half_height, max_y = viewport_height - half_height
  └── Initial clamp: position.y ∈ [min_y, max_y]
  │
  ▼
_process(delta) loop (every frame)
  ├── Read: Input.is_action_pressed("paddle_up") → bool
  ├── Read: Input.is_action_pressed("paddle_down") → bool
  ├── Compute: move = (up, !down) ? -1 : (!up, down) ? +1 : 0
  ├── Apply: position.y += move * SPEED * delta
  └── Clamp: position.y = clamp(position.y, min_y, max_y)
  │
  ▼
Repeat _process(delta) every frame
```

### Flow 2: Simultaneous up + down (cancel)

```
_process(delta)
  ├── Input.is_action_pressed("paddle_up")   → true
  ├── Input.is_action_pressed("paddle_down") → true
  ├── move = 0.0 (both pressed → cancel)
  └── position unchanged
```

### Flow 3: Headless mode (no viewport)

```
_ready()
  ├── get_viewport().get_visible_rect().size → (0, 0)
  ├── Fallback: viewport_size.y = 720.0
  ├── min_y = 60.0, max_y = 660.0
  └── Clamp applies even without visible viewport
```

### Flow 4: Duplicate scene instantiation

```
Second PlayerPaddle instance _ready()
  ├── InputMap.has_action("paddle_up")   → true → skip binding
  ├── InputMap.has_action("paddle_down") → true → skip binding
  └── Only recalibrates boundary + clamp (safe)
```

---

## 4. Edge Cases & Error Handling

| # | Edge Case | Mitigation |
|---|-----------|------------|
| 1 | Simultaneous W+S (or ↑+↓) | Move = 0.0 — forces cancel, no drift |
| 2 | Window resize mid-game | `_ready()` captures viewport once at startup; boundaries don't update dynamically. This is acceptable for MVP — the game window is not intended to resize during play. Future: move boundary calc to `_process` if dynamic resize is needed. |
| 3 | Paddle initial position outside bounds | `_ready()` clamps position.y to [min_y, max_y] after calculation |
| 4 | Extremely low FPS (delta > 1.0) | `clamp()` runs after position update — final position always within bounds regardless of delta magnitude |
| 5 | Scene instantiated twice (dup InputMap) | `has_action()` guard in `_ready()` skips binding if actions already exist |
| 6 | Headless mode: `get_viewport()` returns zero rect | `FALLBACK_VIEWPORT_Y = 720.0` — safe defaults for CI compilation tests |
| 7 | InputMap action name collision (another system uses "paddle_up") | `has_action()` would skip binding — the other system's keys are used instead. Low risk: "paddle_up"/"paddle_down" are project-unique names. |
| 8 | CollisionShape2D shape is null in TSCN | Design specifies non-null `RectangleShape2D` — validation via `--headless --quit` will catch this at build time |

---

## 5. Integration Points

| Integration | Component | How |
|-------------|-----------|-----|
| Ball collision (#290) | Area2D body_entered signal | Ball (Area2D) detects `area_entered` with paddle — paddle is passive, no code needed |
| Main scene assembly (#295) | Instance `player_paddle.tscn` | `main.tscn` or controller script instantiates `res://scenes/player_paddle.tscn` |
| Visual system (#291) | ColorRect color | Replace `Color(1, 1, 1, 1)` with neon theme color — no script change needed |
| AI paddle (#289) | Same `.tscn` + different `.gd` | AI paddle can reuse the scene structure with a different script override |

---

## 6. Test Case Descriptions

### Scenario A: InputMap binding

- **TC-A1 — Actions created:** Load scene → verify `InputMap.has_action("paddle_up")` and `InputMap.has_action("paddle_down")` return true. Precondition: fresh Godot instance without prior binding.
- **TC-A2 — Key bindings:** Verify `InputMap.action_get_events("paddle_up")` contains KEY_W and KEY_UP. Verify `InputMap.action_get_events("paddle_down")` contains KEY_S and KEY_DOWN.
- **TC-A3 — No duplicate on re-instantiate:** Instantiate scene twice → verify actions are still bound exactly once (no duplicates, no crash).

### Scenario B: Movement

- **TC-B1 — Up movement:** Simulate `paddle_up` pressed → verify `position.y` decreases by `SPEED * delta` per frame. Rate is constant (no acceleration).
- **TC-B2 — Down movement:** Simulate `paddle_down` pressed → verify `position.y` increases by `SPEED * delta` per frame.
- **TC-B3 — Simultaneous cancel:** Simulate both `paddle_up` and `paddle_down` pressed → verify `position.y` does not change.
- **TC-B4 — No input:** No keys pressed → verify `position.y` does not change.

### Scenario C: Boundary clamping

- **TC-C1 — Top clamp:** Set position.y = -1000, run `_process(0.016)` with `paddle_up` pressed → verify `position.y = min_y` (half_height).
- **TC-C2 — Bottom clamp:** Set position.y = 2000, run `_process(0.016)` with `paddle_down` pressed → verify `position.y = max_y` (viewport.y - half_height).
- **TC-C3 — Clamp at startup:** Set initial position outside bounds → verify `_ready()` clamps position into range.

### Scenario D: Headless compilation

- **TC-D1 — Zero exit code:** Run `godot --path mini-pong/ --headless --quit` → exit code 0.
- **TC-D2 — No script errors:** Verify output does not contain "SCRIPT ERROR" or "Parse Error".

### Scenario E: Scene integrity

- **TC-E1 — Node hierarchy:** Verify `player_paddle.tscn` root is `Area2D` with two children: `ColorRect` and `CollisionShape2D`.
- **TC-E2 — CollisionShape2D non-null:** Verify `CollisionShape2D.shape` is a `RectangleShape2D` with non-zero size.
- **TC-E3 — Script attachment:** Verify Area2D root has `paddle.gd` attached as script.

---

## 7. File Manifest

| File | Type | Action |
|------|------|--------|
| `mini-pong/gdscripts/paddle.gd` | GDScript | **CREATE** |
| `mini-pong/scenes/player_paddle.tscn` | Godot Scene | **CREATE** |

No existing files are modified. No files are removed.

---

## 8. Implementation Notes

1. **Godot 4.x API specifics:**
   - `InputMap.add_action("paddle_up")` — no return value
   - `InputMap.action_add_event("paddle_up", event)` — the event must be an `InputEventKey` with `keycode` set
   - `InputMap.has_action("paddle_up")` — returns `bool`
   - `Input.is_action_pressed("paddle_up")` — returns `bool` (works in `_process`)

2. **InputEventKey construction:**
   ```gdscript
   var event = InputEventKey.new()
   event.keycode = KEY_W
   InputMap.action_add_event("paddle_up", event)
   ```

3. **TSCN resource references:** Use `[ext_resource]` for the script and `[sub_resource]` for the RectangleShape2D. Godot's `format=3` text format requires this pattern.

4. **offset_* in ColorRect:** These are relative to the parent Area2D origin. `(-10, -60)` to `(10, 60)` centers the 20×120 rectangle on the Area2D position.

5. **No `[input]` section in project.godot** — this is by design. The scaffold (#301) ships without one, and we don't add one now.

6. **CI compatibility:** The existing CI step `godot --path mini-pong/ --headless --quit` will validate the new files without modification.

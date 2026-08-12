# DESIGN: [Feature] 砖墙系统 (BreakoutGrid)

> **Parent Issue:** #384
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — 每砖 = StaticBody2D（group `bricks`、layer 2）+ `ball.gd` 新增 bricks 分支（确认 PRD §4 推荐；零层/掩码配置，球 mask=3 已含 layer 2）
> **Reference PRD:** docs/PRD/384-breakout-grid-brick-wall.md（research PR #411，已合并）
> **所有权:** `content_ownership: mechanical`（程序化生成 + 碰撞 + 信号，无 taste 决策；波次数值/配色归 taste-draft Issue）
> **深度:** depth/standard —— 仅产出 DESIGN 文档；不产出 TASKS 文档；测试仅描述不写代码

---

## 1. 概述

Mini Pong（720×1280 竖屏，PR #409 后）**不存在任何可破坏地形**：球只与左右墙（StaticBody2D layer 1，X 反弹）和上下挡板（Area2D layer 1，角度反弹）交互。本设计引入 **BreakoutGrid 砖墙系统**：程序化生成横跨 720px 的砖墙（留缝/错位/缺口布局），球碰砖 → 砖原子销毁 + dominant-axis 反弹，并通过 `brick_destroyed` / `wall_cleared` 两个信号为下游 #385（双得分制）/ #386（波次循环）提供契约。

**Plan 阶段边界**：本阶段只产出本文档，不碰任何 `.gd` / `.tscn` 文件 —— 下列全部内容为 implement agent 的契约。**Main.tscn 接线不在本 Issue**（归 #393，见 §9 边界）。

### 关键事实（plan agent 已对照源码核实）

- `mini-pong/scenes/ball.tscn`：`collision_layer = 4`（bit 3）、`collision_mask = 3`（bit 1 + bit 2）—— **layer 2 空闲且已在球 mask 内**
- `Main.tscn` LeftWall/RightWall：StaticBody2D、默认 layer 1、group `walls`；球 `body_entered` 触发
- `player_paddle.tscn`：Area2D、默认 layer 1；球 `area_entered` 触发（paddles 分支）
- **结论**：砖放 **layer 2**（bit 2）→ 球对砖的 `body_entered` **零配置生效**，`ball.tscn` / `project.godot` 无需任何改动

### 设计哲学

1. **机械映射、契约源头**：生成算法/碰撞规则/信号契约为纯机械实现；波次厚度数值、配色、砖硬度等 taste 内容严格排除（归 taste-draft Issue）
2. **最小触碰面**：`ball.gd` 仅新增一个 `bricks` 分支（~10 行），walls/paddles 分支、FSM、scoring 信号链零改动（#287 测试兜底回归）
3. **缺口 = 无节点**：HOLES 洞位不实例化砖 → 天然无碰撞体（AC3），无额外穿透逻辑
4. **信号驱动、球自管运动**：遵循 #287/#295 既定架构 —— 不做 Approach B（砖侧写 `ball.velocity` 破坏状态封装）、不做 Approach C（每帧轮询反模式）
5. **测试即验收**：新测试注册进 `run_tests.gd`；`godot --headless --script tests/run_tests.gd` 全绿（本 PR 只描述，implement 写代码）

---

## 2. 现状核实（plan agent 已对照源码确认）

| 文件 | 现状（已核实） | 与 #384 的差距 |
|------|---------------|---------------|
| `mini-pong/scenes/ball.tscn` | `collision_layer=4`、`collision_mask=3` | ✅ 第 2 层空闲且已在 mask 内 —— 零改动 |
| `mini-pong/gdscripts/ball.gd` | `_on_body_entered` 只处理 `walls` 组；`_on_area_entered` 只处理 `paddles` 组；`_bounce_cooldown=2` 帧 | ❌ 无 `bricks` 分支 |
| `mini-pong/gdscripts/constants.gd` | SCREEN 720/1280、球/挡板/AI/Scoring/Colors 常量组（#295 单一事实源） | ❌ 无砖墙常量组 |
| `mini-pong/scenes/Main.tscn` | LeftWall/RightWall（StaticBody2D layer 1, group `walls`）、ScoreZoneTop/Bottom、Ball、双挡板 | ❌ 无 BreakoutGrid 节点（接线归 #393，本 Issue 不改） |
| `mini-pong/assets/neon_glow_material.tres` | 霓虹材质存在 | ✅ 砖视觉复用 |
| `mini-pong/tests/run_tests.gd` | 注册 14 个测试套件 | ❌ 未注册砖墙测试 |
| `mini-pong/tests/test_ball.gd` | 墙反弹/挡板反弹/得分/发球用例（竖屏重写 #383） | ❌ 无砖块反弹用例 |

**防隧穿约束（#367 定稿手感）：** 球速上限 `initial_speed 330 × max_multiplier 1.9 ≈ 627 px/s` → 60fps 下单帧位移 ≈ 10.5px → **砖块最小边长 ≥ 14px**（`BRICK_MIN_DIM`，生成时 clamp）。

---

## 3. 架构与数据流（核心契约）

### 3.1 碰撞层/掩码分配（不变式）

| 对象 | 类型 | Layer | Mask | 说明 |
|------|------|:-----:|:----:|------|
| 墙 LeftWall/RightWall | StaticBody2D | 1 | 默认 | 已有，不动 |
| 挡板 | Area2D | 1 | 默认 | 已有，不动 |
| **砖 Brick** | **StaticBody2D** | **2** | **0** | 新增；mask=0（砖不需探测任何东西，只被球探测） |
| 球 Ball | Area2D | 3 | 3（bit1+2） | 已有，**不改**（mask 已含 layer 2） |
| 得分区 | Area2D | 默认 | 4（只听球 layer 3） | 已有，不动 |

### 3.2 数据流

```
Ball._on_body_entered(brick: StaticBody2D)   [球 mask=3 ∩ 砖 layer=2 → 触发]
    │  if not brick.is_in_group("bricks"): return
    │  if _bounce_cooldown > 0: return            [复用 #287 机制]
    ├── 反弹: dominant-axis flip —— |vx| ≥ |vy| → vx = -vx；否则 vy = -vy
    │         + _bounce_cooldown = BOUNCE_COOLDOWN_FRAMES(2)
    ├── brick.destroy()                          [原子：同 handler 内，先标记后反弹]
    │       └──► grid._on_brick_destroyed(brick) [grid 引用在实例化时注入]
    │               ├── destroyed 集合去重（按砖对象身份，幂等）
    │               ├── remaining_bricks -= 1
    │               ├── brick_destroyed.emit(brick, brick.global_position) ──► #385 拆砖分
    │               └── if remaining_bricks == 0 and not _wall_cleared_emitted:
    │                       _wall_cleared_emitted = true
    │                       wall_cleared.emit() ──► #386 波次重置 → generate_wave(更厚参数)
    │       └──► brick.queue_free()              [延迟帧释放，grid 回调先 is_instance_valid]
    └── 缺口/留缝位置: 无砖实例 → 无碰撞体 → 球直飞 ──► #385 穿墙分(3分)路径
```

### 3.3 反弹规则（AC2，Breakout 标准）

dominant-axis flip：比较反弹前的 `velocity` 分量绝对值 —— `|vx| ≥ |vy|` 翻 X，否则翻 Y。与 #287 信号式碰撞（无法线信息）兼容；不引入法线反射（需 move_and_collide 重构，代价高，PRD §7 实验 3 已否决）。

### 3.4 信号契约（仅定义，不实现消费方）

| 信号 | 签名 | 消费者 | 语义 |
|------|------|--------|------|
| `brick_destroyed` | `(brick: Node2D, pos: Vector2)` | #385 拆砖分（最后触球方） | 每块砖销毁时发一次 |
| `wall_cleared` | `()` | #386 波次重置 | 整墙打空**只发一次**（`_wall_cleared_emitted` 守卫，`generate_wave()` 重置） |

---

## 4. 组件清单（implement 契约）

### 4.1 新建文件

#### `mini-pong/gdscripts/brick.gd`（单砖）
- `extends StaticBody2D`；`_ready()`：`add_to_group("bricks")`、`collision_layer = 2`、`collision_mask = 0`
- `var grid: Node` —— 实例化时由 BreakoutGrid 注入（`get_node` 或直接引用）
- `var _destroyed: bool = false`
- `func destroy() -> void`：幂等（`_destroyed` 守卫）→ 通知 `grid._on_brick_destroyed(self)`（`is_instance_valid` 检查）→ `queue_free()`

#### `mini-pong/gdscripts/breakout_grid.gd`（网格管理器）
- `extends Node2D`；`class_name BreakoutGrid`
- **@export 参数（AC5 集中配置）**：`brick_size: Vector2 = CONSTS.BRICK_SIZE`、`brick_gap: float = CONSTS.BRICK_GAP`、`layout: BrickLayout = BrickLayout.GAPS`、`rows: int = 3`（默认厚度为机械占位，波次数值归 taste-draft）、`hole_count: int = 2`、`hole_seed: int = -1`、`wall_y: float = CONSTS.GRID_WALL_Y`、`brick_scene: PackedScene`（默认 `res://scenes/brick.tscn`）
- `enum BrickLayout { GAPS, OFFSET, HOLES, MIXED }`
- **状态**：`var remaining_bricks: int = 0`（只读语义）、`var _wall_cleared_emitted: bool = false`、`var _destroyed: Dictionary`（按砖对象身份去重，勿用位置/索引）
- **信号**：`signal brick_destroyed(brick: Node2D, pos: Vector2)`、`signal wall_cleared()`
- **API**：
  - `func generate_wave(thickness: int, layout: BrickLayout, seed: int) -> void`：先 `clear_wall()`；`rows = thickness`；`seed < 0` 随机（`seed()` 播种）；按 §4.3 布局算法实例化砖；重置计数/守卫/集合
  - `func clear_wall() -> void`：快照遍历 `queue_free()` 全部旧砖 + 重置计数/守卫/集合（防旧信号泄漏）
  - `func _on_brick_destroyed(brick: Node2D) -> void`：去重 → 递减 → emit 两信号（§3.2）
- **生成约束**：`brick_size` 两轴均 `max(size, BRICK_MIN_DIM)` clamp（防隧穿）；砖 X 铺满：首砖 x ≥ 砖宽/2，末砖 x ≤ 720 − 砖宽/2

#### `mini-pong/scenes/brick.tscn`
- StaticBody2D（根，挂 `brick.gd`）+ ColorRect（尺寸 = 砖尺寸，材质复用 `assets/neon_glow_material.tres`）+ CollisionShape2D（RectangleShape2D，尺寸 = 砖尺寸）

#### `mini-pong/scenes/breakout_grid.tscn`
- 根 Node2D + `breakout_grid.gd`；独立可实例化（供测试与 #393 接线）；不加入 Main.tscn

#### `mini-pong/tests/test_breakout_grid.gd`（implement 阶段）
- 见 §6 测试契约

### 4.2 修改文件

| 文件 | 改动 |
|------|------|
| `mini-pong/gdscripts/constants.gd` | 新增「── Brick Wall (#384) ──」常量组：`BRICK_SIZE: Vector2 = Vector2(64.0, 24.0)`、`BRICK_GAP: float = 4.0`、`GRID_WALL_Y: float = 640.0`（球发球位/墙默认 Y）、`BRICK_MIN_DIM: float = 14.0`（防隧穿下限） |
| `mini-pong/gdscripts/ball.gd` | `_on_body_entered` 新增 `bricks` 分支（~10 行）：`if body.is_in_group("bricks")` → dominant-axis 翻转 velocity → `_bounce_cooldown = BOUNCE_COOLDOWN_FRAMES` → `body.destroy()` → return。**不调用音频**（play_brick_break 归 #392，保持触碰面最小） |
| `mini-pong/tests/run_tests.gd` | 注册 `res://tests/test_breakout_grid.gd`（"Breakout Grid"） |
| `mini-pong/tests/test_ball.gd` | 新增砖块反弹用例（见 §6） |

### 4.3 布局算法（AC1）

统一先算行列网格：`cols = floor(SCREEN_WIDTH / (brick_size.x + brick_gap))`（720px 铺满，余量左右居中），行数 = `thickness`，墙垂直居中于 `wall_y`。

| 布局 | 算法 | 预期砖数（默认参数下） |
|------|------|----------------------|
| `GAPS`（留缝） | 每行按固定列间隔跳过砖（如每 5 列留 1 缝）；行内无错位 | cols × rows − 缝隙数 |
| `OFFSET`（错位） | 奇数行 X 偏移 `(brick_size.x + brick_gap) / 2`（标准 Breakout 砖纹），边缘砖 clamp 回 [砖宽/2, 720−砖宽/2] | 同 GAPS 基数（行可能少 1 块） |
| `HOLES`（缺口） | 用 `hole_seed` 随机选 `hole_count` 个**柱位**（列），该列全部行不实例化砖 → 形成竖向通道（穿墙得分路径，AC3） | cols × rows − hole_count × rows |
| `MIXED` | GAPS + OFFSET + HOLES 组合 | 依组合规则 |

### 4.4 不动文件（明确排除）

`ball.tscn`、`project.godot`、`player_paddle.tscn`、`Main.tscn`（接线归 #393）、`game_state_machine.gd`、`scoring_manager.gd`、`game_hud.gd`、`audio_engine.gd`（play_brick_break 归 #392）、`e2e_shots.json`。

---

## 5. 测试契约（仅描述，implement 依此写代码）

> 本 PR 不写 runnable 测试文件；以下为 implement 阶段的规格。

### 5.1 `tests/test_breakout_grid.gd`（新套件）

| 测试组 | 用例描述 |
|--------|---------|
| 布局 | GAPS/OFFSET/HOLES/MIXED 各自砖数断言；X 铺满断言（首砖 x ≥ 砖宽/2、末砖 x ≤ 720 − 砖宽/2）；OFFSET 奇数行偏移 = `(砖宽+缝)/2`；HOLES 洞位（柱位×行）**无砖节点** |
| 生成 API | `generate_wave(thickness, layout, seed)`：`rows == thickness`；`seed` 相同 → 布局相同（可复现）；`seed < 0` → 不抛错 |
| 信号 | 逐砖 `destroy()` → 每次发 `brick_destroyed(brick, pos)` 且 pos 正确；全部打空 → `wall_cleared` **恰好一次** |
| 缺口（AC3） | 沿 HOLES 洞轴心放置球并移动 → 无反弹、无砖碎（洞位无碰撞体） |
| 再生（失败路径覆盖） | `generate_wave()` 后旧砖全部清空、`remaining_bricks`/`_wall_cleared_emitted` 重置；打空 → 再生 → 再打空 → `wall_cleared` 恰好两次（每次新墙一次） |
| 幂等 | 同一砖 `destroy()` 两次 → 计数只减一、`brick_destroyed` 只发一次 |
| 常量 | `BRICK_MIN_DIM ≥ 14`；默认 `brick_size` 两轴 ≥ 14 |

### 5.2 `tests/test_ball.gd` 新增用例

| 用例 | 描述 |
|------|------|
| 侧击翻 X | 砖在球正前方，`velocity=(300, 0)` → 反弹后 `vx` 翻转、`vy` 不变 |
| 顶/底击翻 Y | `velocity=(0, 300)` → 反弹后 `vy` 翻转、`vx` 不变 |
| 砖被移除 | 撞砖后砖 `_destroyed == true` 且已 `queue_free`；grid 计数减一 |
| 既有回归 | walls/paddles 分支行为不变（现有用例全绿） |

### 5.3 `tests/run_tests.gd`
- 注册 `_run("res://tests/test_breakout_grid.gd", "Breakout Grid")`（置于 test_ball 之后）。

---

## 6. 边界条件与失败路径（implement 必须遵守）

1. **砖角双砖同时接触** — 球对角砸在两砖接缝：`_bounce_cooldown=2` 帧序列化，只反弹一次；每砖 `destroy()` 幂等（已销毁砖不重复计数）
2. **最后一砖打空（含同帧双砖）** — 同帧两砖同碎：按砖对象身份去重（`_destroyed` 字典），`remaining_bricks` 精确归零，`wall_cleared` 只发一次
3. **高速隧穿（球速上限 627px/s ≈ 10.5px/帧）** — `brick_size` 生成时 clamp ≥ `BRICK_MIN_DIM(14px)`，单帧位移 < 砖最小边长 → 不隧穿
4. **OFFSET 错位行侧边命中** — 球擦到上一行砖侧棱：dominant-axis 自动翻 X（侧击），符合 Breakout 直觉
5. **缺口穿行** — 洞位无碰撞体：无反弹、无砖碎，直飞对方底线（#385 穿墙分路径）
6. **发球/暂停态** — `_is_serving` 球静止；`PAUSED` 态 `_process` 停更 → 无接触可能，砖无反应
7. **波次再生（#386 调用）** — `generate_wave()` 先 `clear_wall()`（快照遍历 `queue_free` 全部旧砖 + 重置计数/守卫/集合），旧信号不泄漏到新墙
8. **球撞墙同帧撞砖** — cooldown 串行化：先到者先处理，cooldown 期间的第二次接触被忽略（复用 #287 机制）

**失败路径（≥4）**：
1. **wall_cleared 重复发出** — `_wall_cleared_emitted` 守卫置位后不再发；`generate_wave()` 必须重置（测试：打空→再生→再打空，恰好两次）
2. **幽灵反弹（砖未碎但球反弹）** — 反弹与 `destroy()` 在同一 handler 原子执行：先标记已销毁再改球速度；异常路径（`is_instance_valid` 失败）不执行反弹
3. **网格销毁期空引用** — 砖 `queue_free` 延迟帧释放，grid 回调先 `is_instance_valid(brick)`；`clear_wall()` 遍历前快照列表
4. **计数漂移** — `remaining_bricks` 只由 `_on_brick_destroyed` 单一入口递减（不从场景树扫描推导），防止重复/漏减

---

## 7. 验收标准映射（Issue #384 AC）

| AC | 验收标准 | 设计覆盖 |
|----|---------|---------|
| AC1 | 每波可生成至少 1 面横跨屏幕的砖墙，布局含留缝/错位/缺口 | §4.3 布局算法 + §5.1 布局/铺满断言 |
| AC2 | 球与砖块碰撞后砖块移除并反弹，反弹方向符合物理规则 | §3.3 dominant-axis + §3.2 原子销毁 + §5.2 反弹用例 |
| AC3 | 洞口/缺口区域无碰撞体，球可自由穿过 | HOLES 洞位不实例化砖 + §5.1 缺口直穿用例 |
| AC4 | 砖墙打空后只发出一次 wall_cleared 信号 | §3.4 守卫 + §5.1 恰好一次用例 + 失败路径 1 |
| AC5 | 生成参数集中在 BreakoutGrid 配置，可驱动波次厚度/形状 | §4.1 @export 参数 + `generate_wave(thickness, layout, seed)` API |

---

## 8. 验证步骤（implement 执行顺序）

1. `constants.gd`（砖墙常量组）→ 2. `brick.gd` + `brick.tscn` → 3. `breakout_grid.gd` + `breakout_grid.tscn` → 4. `ball.gd` bricks 分支 → 5. `run_tests.gd` 注册 + `test_breakout_grid.gd` + `test_ball.gd` 用例 → 6. 本地验证：
   - `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含既有 14 套件回归）
   - `godot --path mini-pong/ --headless --quit` 编译通过
   - `ball.tscn` / `project.godot` / `Main.tscn` git diff 为空（层配置与接线零改动证据）

---

## 9. 不做的事与范围边界（明确排除）

- ❌ **Main.tscn 接线** — `breakout_grid.tscn` 实例化进主场景、`brick_destroyed`→#385、`wall_cleared`→#386 全部归 **#393**（本 Issue 只交付独立可实例化场景 + 隔离测试）
- ❌ 拆砖计分（#385）、波次循环/递增（#386）
- ❌ 波次厚度数值、砖配色、砖硬度等 taste 内容（taste-draft Issue；默认 rows=3 仅为机械占位）
- ❌ 音效 `play_brick_break`（可选 Stretch，并入 #392；ball.gd 分支不调用音频）
- ❌ 修改 `ball.tscn` / `project.godot` 的层/掩码配置（layer 2 已天然覆盖）
- ❌ 引入任何第三方资产（开源优先调研结论：无可复用插件，§PRD 1.4）
- ❌ 写 runnable 测试文件于本 PR（测试归 implement PR）

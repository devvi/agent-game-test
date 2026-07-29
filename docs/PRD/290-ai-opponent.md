# PRD: [Feature] AI 对手 — AI Opponent

> **Issue:** #290
> **标签:** enhancement, workflow/research, depth/standard, priority/high, version/mvp, estimate/medium
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #301 (Scaffold — CLOSED), #287 (Ball Physics — CLOSED)

---

## 1. 问题定义

### 当前状态

Mini Pong 项目已有完整的游戏基础设施：

| 系统 | 状态 | 详情 |
|------|:----:|------|
| 项目骨架（#301） | ✅ CLOSED | `mini-pong/` 子项目，Forward+ 渲染器，glow/bloom 开启 |
| 球物理（#287） | ✅ CLOSED | `ball.gd` (180行)：手动 `_process` 运动、墙壁反弹、挡板碰撞（按 `paddles` group 检测）、速度递增（+5%/hit, cap 2x）、发球 |
| 玩家挡板（#288） | ✅ CLOSED | `paddle.gd` (63行)：WASD/方向键输入、`_process` 移动、屏幕边界 clamp、`paddles` group 注册 |
| 游戏主场景 | ✅ 存在 | `game.tscn`：TopWall + BottomWall + Ball + PlayerPaddle（x=50, 左侧） |
| AI 对手 | ❌ 不存在 | 游戏场景无对手挡板、无 AI 脚本、无球追踪逻辑 |

**当前 `game.tscn` 节点结构：**
```
Game (Node2D)
├── TopWall (StaticBody2D, groups=["walls"])
├── BottomWall (StaticBody2D, groups=["walls"])
├── Ball (instance of ball.tscn, pos 640,360)
└── PlayerPaddle (instance of player_paddle.tscn, pos 50,360)
```

**当前 `paddle.gd` 仅为玩家输入设计：** 在 `_process()` 中读取 `Input.is_action_pressed("paddle_up/down")`，无 AI 模式、无球追踪逻辑、无速度动态调整。

**球与挡板碰撞机制（`ball.gd` `_on_area_entered`）：** 通过 `area.is_in_group("paddles")` 检测 — AI 挡板只需加入 `paddles` group 即可被球识别，无需修改 `ball.gd`。

### 预期行为

1. **AI 挡板追踪球的 Y 位置：** AI 挡板每帧读取球的 `global_position.y`，向球的 Y 坐标移动
2. **100–300ms 随机反应延迟：** AI 不是在每帧即时反应，而是使用一个随机延迟窗口（100–300ms），在此窗口内使用旧的目标位置，到期后更新目标
3. **±20px 随机位置误差：** AI 追踪的目标 Y 位置叠加 ±20px 的随机偏移，模拟人类的不精确性
4. **速度动态调整：** AI 落后球时（挡板 Y 离球更远）移动速度 +20%；AI 领先球时（挡板已接近球）速度 -20%，给玩家得分机会
5. **不超出屏幕边界：** 与玩家挡板相同的 Y 轴 clamp 逻辑
6. **`--headless --quit` 无脚本错误：** AI 脚本在无球节点、无 viewport 等 headless 环境下不崩溃

### 用户场景

| # | 场景 | 频率 |
|---|------|------|
| A | **AI 追踪球：** 球在场景中移动，AI 挡板平滑追踪球的 Y 位置，不会完美接住每一个球 | 每帧 |
| B | **反应延迟：** AI 有时追球稍慢（延迟窗口未到期时仍向旧目标移动），模拟人类反应时间 | 持续 |
| C | **位置误差：** AI 挡板停在离球 ±20px 的位置，球擦边反弹，制造紧张感 | 每次接球 |
| D | **加速追球：** 当 AI 落后较多（挡板离球远），速度提升 20%，快速回防 | 落后时 |
| E | **减速让球：** 当 AI 已接近球，速度降低 20%，给玩家可乘之机 | 领先时 |
| F | **边界安全：** AI 挡板不会移出屏幕，即使球的 Y 位置超出边界 | 边界附近 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| AI 挡板脚本（追踪、延迟、误差、速度调整） | AI 难度等级选择（easy/normal/hard） |
| AI 挡板场景文件（或复用 player_paddle.tscn） | AI 挡板视觉差异化（颜色/纹理） |
| 球节点引用（查找或注入） | 学习型 AI（强化学习/自适应） |
| 屏幕边界 clamp（复用 paddle.gd 逻辑） | 多人模式/双人模式 |
| headless 编译验证 | 运行时帧率无关的延迟精度（用帧计数足够） |

> **Scope deconfliction:** 本 PRD 是 Mini Pong 第六个功能 PRD。PRD #288 覆盖了玩家挡板的输入处理和碰撞就绪，本 PRD 在此基础上添加 AI 控制层——**不重新分析挡板的节点结构、InputMap 绑定或边界 clamp 逻辑**。PRD #287 覆盖了球的物理和碰撞检测，本 PRD 依赖 `paddles` group 机制但不修改 `ball.gd`。PRD #289 覆盖了霓虹视觉系统——AI 挡板视觉由 #289 在后续处理。

---

## 2. 设计意图

### 为什么是现在

Pong 游戏的乐趣取决于对手质量。`game.tscn` 已有玩家挡板和球，但缺失对手意味着游戏不可玩——球飞向右侧时无人接球，直接飞出边界得分。AI 对手是 Pong 游戏从"测试场景"到"可玩游戏"的关键一步。

> **设计哲学（来自 Issue 正文）：** AI 决定游戏是否好玩。完美追踪不可玩，太笨也无聊。延迟 + 误差 + 动态难度是 Pong AI 的经典模式。

该问题标记 `priority/high`、`version/mvp`——AI 对手是 MVP 的核心组件，无它游戏不可玩。

### 设计原则

1. **最小侵入：** AI 逻辑不应修改 `ball.gd`（球物理）或 `game.tscn` 的现有节点。AI 挡板通过现有的 `paddles` group 机制被球识别。
2. **参数化可调：** 所有 AI 行为参数（延迟范围、误差范围、速度比例）通过 `@export` 暴露，可在编辑器中调整平衡性而无需改代码。
3. **确定性随机：** 使用 `randf_range()` + `randi()`（Godot 内置 PRNG），replay 友好（相同 seed 产生相同行为）。
4. **帧率无关：** 延迟计时使用 `delta` 累加器（非帧计数），速度调整使用 `delta` 乘法。
5. **与玩家挡板共享基础逻辑：** AI 挡板与玩家挡板使用相同的 Area2D + CollisionShape2D + `paddles` group 结构，确保球碰撞检测一致。

### 先前约束

| 约束 | 来源 | 影响 |
|------|------|------|
| `game.tscn` 左侧已有 PlayerPaddle（x=50） | #288 实施 | AI 挡板放置在右侧（x≈1230），镜像布局 |
| 球通过 `area.is_in_group("paddles")` 检测挡板 | #287 实施 | AI 挡板必须加入 `paddles` group |
| 球在 `game.tscn` 中名为 `"Ball"` | game.tscn | AI 可通过 `get_node("../Ball")` 或 `get_parent().get_node("Ball")` 查找球 |
| `paddle.gd` 当前仅含玩家输入逻辑 | #288 实施 | 需扩展 `paddle.gd` 支持 AI 模式，或创建独立的 `ai_paddle.gd` |
| 屏幕边界 clamp 逻辑已在 `paddle.gd` 实现 | #288 实施 | AI 挡板复用相同的 `min_y`/`max_y` 计算和 `clamp()` |
| Godot 4.x headless 模式 | CI pipeline | AI 脚本不能依赖 viewport（headless 无 window），不能包含编译错误 |
| `project.godot` 无 `[input]` 段 | #288 设计决策 | AI 挡板不依赖 InputMap — 无冲突 |

---

## 3. 影响分析

### 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/paddle.gd` | 挡板脚本 | **修改** — 添加 AI 模式（`@export var mode: int`）、球追踪逻辑、延迟/误差/速度调整 |
| `mini-pong/scenes/game.tscn` | 游戏主场景 | **修改** — 添加 AI 挡板实例节点（或新场景文件的实例） |
| `mini-pong/scenes/player_paddle.tscn` | 玩家挡板场景 | **不变** — 使用现有场景；若用新模式则复用，若用新场景则不变 |

### 新文件

| 文件 | 用途 | 行数估计 |
|------|------|---------|
| `mini-pong/scenes/ai_paddle.tscn` | AI 挡板场景（可选，取决于方案） | ~20 行（同 player_paddle.tscn 结构） |
| `mini-pong/tests/test_ai_paddle.gd` | AI 挡板测试套件 | ~200 行 |

### 间接影响模块

| 文件 | 模块 | 影响 |
|------|------|------|
| `mini-pong/gdscripts/ball.gd` | 球物理 | **无变更** — AI 挡板加入 `paddles` group 后自动参与碰撞检测 |
| `mini-pong/gdscripts/ball_trail.gd` | 球拖尾效果 | **无变更** |
| `mini-pong/gdscripts/score_flash.gd` | 得分闪烁 | **无变更** — 已预留 `"ai"` 得分颜色（`#ff3355`） |

### 数据流影响

```
当前流程：
  玩家输入（WASD/箭头键）
    → Input.is_action_pressed()
    → paddle.gd._process() 计算 move
    → position.y += move * SPEED * delta
    → clamp(position.y, min_y, max_y)

添加 AI 后：
  ball.global_position.y
    → ai_paddle 读取（含延迟窗口 + 随机误差）
    → 计算目标 Y = ball.y + random_offset(±20px)
    → 计算距离 = |position.y - target_y|
    → 速度系数 = 距离 > 阈值 ? 1.2 : 0.8
    → position.y += sign(target_y - position.y) * SPEED * speed_factor * delta
    → clamp(position.y, min_y, max_y)  ← 复用现有边界逻辑
```

### 文档更新

- [x] `docs/PRD/290-ai-opponent.md` — 本 PRD（新建）
- [ ] `docs/DESIGN/290-ai-opponent.md` — 设计文档（计划阶段产出）
- [ ] `docs/TASKS/290-ai-opponent.md` — 任务分解（实施阶段产出）

---

## 4. 方案比较

### Approach A：扩展 `paddle.gd` 添加 AI 模式（推荐）

**描述：** 在现有 `paddle.gd` 末尾追加 AI 模式代码。通过 `@export var mode: int`（0=PLAYER, 1=AI）切换行为。AI 模式下 `_process()` 跳过输入读取，执行球追踪逻辑。AI 挡板实例使用现有的 `player_paddle.tscn` 场景（mode 设为 AI），或在 `game.tscn` 中直接创建第二个实例并配置 mode。

**节点查找：** AI 挡板在 `_ready()` 中通过 `get_parent().get_node("Ball")` 获取球引用。若找不到（headless 测试），gracefully degrade（不崩溃）。

**核心算法（伪代码）：**
```gdscript
# AI 参数（@export）
@export var ai_reaction_delay_min: float = 0.1   # 100ms
@export var ai_reaction_delay_max: float = 0.3   # 300ms
@export var ai_position_error: float = 20.0       # ±20px
@export var ai_speed_boost: float = 1.2           # +20%
@export var ai_speed_slow: float = 0.8            # -20%

# AI 状态
var _ai_delay_timer: float = 0.0
var _ai_target_y: float = 0.0
var _ai_error_offset: float = 0.0

func _ai_process(delta: float) -> void:
    if ball_node == null:
        return
    _ai_delay_timer -= delta
    if _ai_delay_timer <= 0.0:
        _ai_delay_timer = randf_range(ai_reaction_delay_min, ai_reaction_delay_max)
        _ai_error_offset = randf_range(-ai_position_error, ai_position_error)
        _ai_target_y = ball_node.global_position.y + _ai_error_offset
    # 计算距离 → 速度系数
    var dist := abs(position.y - _ai_target_y)
    var factor := ai_speed_slow if dist < ai_position_error * 2 else ai_speed_boost
    var move := sign(_ai_target_y - position.y)
    position.y += move * SPEED * factor * delta
    position.y = clamp(position.y, min_y, max_y)
```

| 优点 | 缺点 |
|------|------|
| 零场景文件重复 — 复用 `player_paddle.tscn` | `paddle.gd` 职责混合（Player + AI），文件长度增加 ~50 行 |
| 边界 clamp 逻辑不重复 | `@export` 参数在 Player 模式下无意义但可见 |
| `paddles` group 注册已在 `_ready()` 中实现 | |
| 测试可以创建 `mode=MODE_AI` 的 paddle 实例 | |
| 最小的文件变更数（仅修改 paddle.gd + game.tscn） | |

**风险：** 低
**工作量：** 0.5–1 天（修改 `paddle.gd`、更新 `game.tscn`、编写测试）

---

### Approach B：独立 `ai_paddle.gd` + 新场景文件

**描述：** 创建全新的 `ai_paddle.gd` 脚本和 `ai_paddle.tscn` 场景文件。AI 脚本完全独立，不修改 `paddle.gd`。节点结构与 `player_paddle.tscn` 相同（Area2D + ColorRect + CollisionShape2D），但脚本逻辑仅为 AI 追踪。

```gdscript
# ai_paddle.gd — 独立文件
extends Area2D

const SPEED: float = 400.0
# ... AI 参数和逻辑完全独立 ...

func _ready() -> void:
    add_to_group("paddles")
    # 边界计算（与 paddle.gd 相同的逻辑）
    # 查找球节点
```

| 优点 | 缺点 |
|------|------|
| 关注点分离 — Player 和 AI 逻辑完全独立 | 边界计算逻辑重复（paddle.gd 的 `_ready()` 约 20 行） |
| `paddle.gd` 零修改 — 零回归风险 | 两个 `.tscn` 文件维护同样的节点结构 |
| 每个脚本的 `@export` 参数语义清晰 | 未来若修改挡板公共行为（如碰撞形状变化），需同步两个文件 |
| 测试完全独立 | 总文件数增加：`ai_paddle.gd` + `ai_paddle.tscn` |

**风险：** 低
**工作量：** 0.5–1 天（创建 `ai_paddle.gd`、`ai_paddle.tscn`、测试）

---

### Approach C：独立 `ai_controller.gd` 驱动现有 paddle

**描述：** 创建一个不继承 Area2D 的 `ai_controller.gd`（纯 Node/RefCounted），在 `game.tscn` 中作为独立节点。它持有对 AI 挡板 Area2D 和球 Ball 的引用，在 `_process()` 中计算目标位置并直接设置 `paddle.position.y`。挡板自身的 `paddle.gd._process()` 被禁用（通过 flag 或移除脚本）。

```gdscript
# ai_controller.gd — 纯控制器
extends Node

@export var paddle: Area2D
@export var ball: Area2D
# ... AI 参数和逻辑 ...

func _process(delta: float) -> void:
    if paddle == null or ball == null:
        return
    # 计算目标位置 → paddle.position.y = ...
    paddle.position.y = clamp(paddle.position.y, min_y, max_y)
```

| 优点 | 缺点 |
|------|------|
| AI 逻辑与挡板节点完全解耦 | 需要禁用/移除 paddle.gd 的 `_process()`——破坏现有脚本 |
| 控制器可复用（未来可驱动任何 Area2D） | `paddle.gd` 的 `_process()` 仍在运行，可能与 AI 控制器冲突（同帧双写 position.y） |
| 可 unit-test 控制器独立于场景 | 架构不自然 — Godot 习惯于节点自包含逻辑 |
| | `paddle.gd` 的边界 clamp 不在控制器中，需额外处理 |

**风险：** 中 — `paddle.gd._process()` 和 AI 控制器的写入冲突风险
**工作量：** 1–1.5 天

---

### 推荐：Approach A — 扩展 `paddle.gd`

**理由：**

1. **最少文件变更：** 仅修改 2 个文件（`paddle.gd` + `game.tscn`），不引入新场景文件。项目当前仅 4 个 GD 脚本，保持简洁。
2. **复用现有基础设施：** `paddle.gd` 的边界 clamp、`paddles` group 注册、CollisionShape2D 结构全部复用，零重复代码。
3. **`@export` 参数在 Player 模式下无意义的缺点可接受：** 这是 Godot 社区常见模式（如 `CharacterBody2D` 的 `motion_mode`），清晰命名即可区分（`ai_*` 前缀）。
4. **测试友好：** 测试代码直接创建 `Area2D` + `paddle.gd` + `mode=MODE_AI`，无需额外场景加载。
5. **与现有 PRD 模式一致：** PRD #288 的 DESIGN 将 paddle.gd 设计为自包含的挡板组件——扩展模式枚举是该设计的自然演进。

---

## 5. 边界条件与验收标准

### 验收标准

- [x] **AC1: AI 追踪球的 Y 位置** — AI 挡板的 `_process()` 读取 `ball.global_position.y` 并向其移动
  - 球向上移动 → AI 挡板向上移动
  - 球向下移动 → AI 挡板向下移动
  - 球静止（serve 期间） → AI 挡板停在当前位置

- [x] **AC2: 100–300ms 随机反应延迟** — AI 不是每帧更新目标，而是在延迟窗口到期时才更新
  - 延迟值在 100–300ms 范围内随机
  - 延迟窗口内，AI 向旧目标位置移动（非最新球位置）
  - 延迟到期后，重新随机选择延迟值并更新目标
  - 验证：通过多次测试运行确认延迟值在 [0.1, 0.3] 秒范围内

- [x] **AC3: ±20px 随机位置误差** — AI 追踪的目标 Y 叠加随机偏移
  - 每次更新目标时生成新的随机偏移 `randf_range(-20, 20)`
  - 偏移叠加到球的 Y 坐标上：`target_y = ball.y + error`
  - 验证：多次测试确认实际停止位置与球的 Y 差异在 ±20px 内

- [x] **AC4: 落后时加速 20%，领先时减速 20%** — 速度根据距离动态调整
  - 距离 = `abs(paddle.y - target_y)`
  - 距离 ≥ 阈值（40px，即误差范围 × 2）：速度系数 = 1.2
  - 距离 < 阈值：速度系数 = 0.8
  - 验证：通过测试确认 `position.y` 的增量在不同距离下比例正确

- [x] **AC5: 不超出屏幕边界** — AI 挡板 Y 坐标始终在 `[min_y, max_y]` 内
  - 复用 `paddle.gd` 现有的 `clamp(position.y, min_y, max_y)`
  - 即使目标 Y 超出屏幕（球击到极上/下角），AI 挡板不会越界
  - 验证：设置 `target_y = -9999` 确认挡板 clamp 在 `min_y`

- [x] **AC6: `--headless --quit` 无脚本错误** — headless 模式下编译和运行无 error
  - `godot --path mini-pong/ --headless --quit` 退出码 = 0
  - 无 `push_error()` 调用、无脚本解析错误
  - 球节点查找失败时 graceful degradation（不崩溃）

### 边界情况

1. **球不存在：** `game.tscn` 中球节点被移除或重命名 → AI 挡板不崩溃，停在原位不动
2. **球位置极端值：** 球 Y 坐标超出屏幕（bug 情况） → AI 目标 Y 可能超出边界，但挡板 clamp 确保不越界
3. **延迟为 0：** `randf_range(0.1, 0.3)` 可产生接近 0.1 的值 → 确认 `_ai_delay_timer` 在 `_ready()` 中初始化为正数
4. **极低帧率：** `delta` 很大（如 0.5s 卡顿） → AI 可能"跳帧"，但位置仍被 clamp 保护。速度调整 delta-based 确保位移不过量
5. **速度系数边界：** 距离恰好等于阈值（40px） → 定义明确行为（如 `>=` 使用加速，`<` 使用减速）
6. **headless 无 viewport：** `get_viewport()` 返回 null → `min_y`/`max_y` fallback 使用 FALLBACK_VIEWPORT_Y（720px，已在 paddle.gd 定义）
7. **多球场景（未来）：** 当前场景只有 1 个球，AI 通过节点名 `"Ball"` 查找。若未来有多球，需改为 group 查找或 `@export` 注入
8. **速度系数累积：** 连续多帧加速/减速不会累积（每帧重新计算系数，非叠加状态）

### 失败路径

1. **球节点查找失败 + 无 fallback：** AI 挡板不崩溃，`_ai_process()` 在 `ball_node == null` 时 early return
2. **`@export` 参数被设为非法值：** 负延迟 → 使用 `abs()` 或 clamp；零误差 → 行为正确但不有趣（允许，编辑器责任）
3. **`mode` 被误设为无效值：** 默认 fallback 到 `MODE_PLAYER`（保持不变行为）

---

## 6. 依赖与阻塞

### 依赖项

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #301 — 项目骨架 | ✅ CLOSED | 无 | `mini-pong/` 子项目、project.godot、WorldEnvironment 已就绪 |
| #287 — 球物理与碰撞 | ✅ CLOSED | 无 | `ball.gd` 已实现，`paddles` group 碰撞检测已就绪 |
| #288 — 玩家挡板 | ✅ CLOSED | 无 | `paddle.gd` 边界 clamp、`paddles` group 注册可复用 |

**依赖链：**
```
#301 (Scaffold)
  ├──► #287 (Ball Physics)
  │       └──► #290 (AI Opponent) ◄── 本 Issue
  └──► #288 (Player Paddle)
          └──► #290 (AI Opponent) ◄── 本 Issue
```

### 阻塞项

| 未来工作 | 优先级 | 说明 |
|---------|:------:|------|
| AI 难度等级（easy/normal/hard） | P2 | 通过调整 `ai_reaction_delay_*`、`ai_position_error`、`ai_speed_*` 参数实现 |
| AI 挡板霓虹视觉 | P2 | 由 #289 视觉系统覆盖 — AI 挡板颜色可能不同于玩家 |
| 双人模式 | P3 | 第二个玩家替代 AI（无需 AI 逻辑） |

### 准备就绪检查

- [x] `mini-pong/` 子项目可编译（`godot --headless --quit` 退出码 0）
- [x] `ball.gd` 的 `paddles` group 机制已验证（test_ball.gd 通过）
- [x] `paddle.gd` 的边界 clamp 逻辑已验证（test_paddle.gd 通过）
- [x] `game.tscn` 有明确的球节点（`name="Ball"`）可供 AI 查找

---

## 7. Spike / Experiment

*Skipped per `depth/standard` label.*

---

## 8. Continuation Context

### 系统状态

AI 对手 PRD 在现有基础设施之上设计：球物理（#287）和玩家挡板（#288）已完成并测试通过。`game.tscn` 当前只有左侧 PlayerPaddle — 添加右侧 AI 挡板即可使游戏可玩。

### 主要风险

1. **球查找可靠性：** 当前方案通过 `get_parent().get_node("Ball")` 查找球节点。若 `game.tscn` 重构（如将球移到子节点），查找会失败。推荐实施方案中增加 `@export var ball_node: Node2D` 作为备用注入路径。
2. **AI 平衡性：** 参数（延迟、误差、速度系数）的默认值是初步估计。实际游戏测试后才能确定"有趣但不无敌"的参数组合。建议所有参数 `@export` 以支持快速迭代。

### Plan Agent 下一步

1. 确认选用 Approach A（扩展 `paddle.gd`）或 Approach B（独立 `ai_paddle.gd`）
2. 设计 AI 挡板的 `@export` 参数接口和默认值
3. 设计 `game.tscn` 中 AI 挡板的位置（右侧，x≈1230）和模式配置
4. 设计测试策略：
   - **延迟行为测试：** 多次 `_process()` 调用验证目标只在延迟到期后更新
   - **误差测试：** 验证 `_ai_error_offset` 在 ±20px 范围内
   - **速度系数测试：** 设置不同距离验证 1.2x / 0.8x 生效
   - **边界测试：** 极端目标 Y 值验证 clamp 生效
   - **headless 测试：** 确认无 viewport / 无球的 graceful degradation

### 文件清单

| 文件 | 动作 | 估计 |
|------|:----:|------|
| `mini-pong/gdscripts/paddle.gd` | 修改（+~50 行 AI 逻辑） | 若选 Approach A |
| `mini-pong/scenes/game.tscn` | 修改（+1 AI 挡板实例） | 必须 |
| `mini-pong/scenes/ai_paddle.tscn` | 新建（~20 行） | 若选 Approach B |
| `mini-pong/tests/test_ai_paddle.gd` | 新建（~200 行） | 必须 |

### 暴露给后续 Issue 的参数接口

若后续 Issue 需要动态调整 AI 难度（如根据得分差），AI 挡板的 `@export` 参数必须可读写：

| 参数 | 类型 | 外部可写 | 说明 |
|------|------|:------:|------|
| `mode` | int | ✅ | 0=PLAYER, 1=AI |
| `ai_reaction_delay_min` | float | ✅ | 最小反应延迟（秒） |
| `ai_reaction_delay_max` | float | ✅ | 最大反应延迟（秒） |
| `ai_position_error` | float | ✅ | 位置误差范围（px） |
| `ai_speed_boost` | float | ✅ | 落后加速系数 |
| `ai_speed_slow` | float | ✅ | 领先减速系数 |

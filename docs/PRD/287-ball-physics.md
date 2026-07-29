# PRD: [Feature] 球物理与碰撞 — Ball Physics & Collision

> **Issue:** #287
> **标签:** enhancement, workflow/research, depth/standard, priority/critical, version/mvp, estimate/medium
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #301 (CLOSED — scaffold)

---

## 1. 问题定义

### 当前状态

Mini Pong 子项目 (#301 scaffold) 已完成基本骨架搭建：

| 项目 | 状态 |
|------|:----:|
| `mini-pong/project.godot` (Forward+, glow) | ✅ 已创建 |
| `mini-pong/scenes/world_environment.tscn` | ✅ 已创建 |
| `mini-pong/gdscripts/` | 🟡 空目录 |
| `mini-pong/scenes/` (除 environment 外) | 🟡 空目录 |
| 球物理系统 | ❌ 不存在 |
| 墙壁/挡板场景 | ❌ 不存在 |
| 计分系统 | ❌ 不存在 |

目前 `godot --path mini-pong/ --headless --quit` 因无 main scene 而超时终止（`Error: Can't run project: no main scene defined`），这是 scaffold 阶段的预期行为——Issue #287 是实现第一个游戏功能模块，开始填充 `mini-pong/gdscripts/` 和 `mini-pong/scenes/`。

### 预期行为

实现 Pong 游戏的核心——球的物理行为：

1. **节点结构：** `Area2D` + `CollisionShape2D`（shape 不为空），使用 Sprite2D 或 ColorRect 可视化
2. **运动方式：** 手动 `_process(delta)` 更新位置（非 Godot 物理引擎 `_physics_process`），实现街机风格的线性匀速运动
3. **墙壁反弹：** 球撞击上下墙壁（StaticBody2D）时，Y 方向速度反转，实现完美反弹
4. **挡板反弹：** 球撞击左右挡板（Area2D 或 StaticBody2D）时，根据撞击位置计算反弹角度——撞击点离挡板中心越远，反弹角度越陡（水平分量越大）
5. **速度递增：** 每次击中挡板后速度 +5%，上限为初始速度的 2x
6. **发球：** 球从场景中心出发，方向随机（左右 ±45° 范围内）
7. **得分事件：** 球飞出左右边界时触发 `score` 信号，携带获胜方信息
8. **编译验证：** `godot --path mini-pong/ --headless --quit` 无脚本错误

### 用户场景

| # | 场景 | 频率 |
|---|------|------|
| A | **回合发球：** 每回合开始，球从中心发出，方向随机偏向左或右，玩家/对手准备接球 | 每回合 |
| B | **墙壁反弹：** 球击中上/下墙，Y 方向反转继续运动，角度不变 | 频繁（>5次/回合） |
| C | **挡板接球：** 玩家移动挡板接到球，球根据撞击位置以不同角度反弹回对方场地 | 频繁（>3次/回合） |
| D | **速度递增：** 长时间回合中，球速逐渐加快至 2x 上限，增加紧张感 | 长回合中 |
| E | **得分：** 球飞出对方边界，己方得分，球重置到中心准备下一回合 | 每回合结束 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| `ball.gd` 脚本（Area2D 运动、碰撞、发球） | 挡板移动脚本（后续 Issue） |
| `ball.tscn` 场景文件 | AI 对手逻辑（后续 Issue） |
| 墙壁场景（StaticBody2D） | 计分系统 UI（后续 Issue） |
| `score(side)` 信号定义 | 游戏结束/胜利条件（后续 Issue） |
| 速度递增逻辑（+5%/hit, cap 2x） | 音效/视觉特效 |
| 手动 `_process` 运动更新 | `_physics_process` / Godot 物理引擎 |

---

## 2. 设计意图

### 为什么是现在

这是 Mini Pong 项目的**第一个游戏功能模块**。Pong 的全部乐趣集中在球的物理行为上——反弹角度、速度变化、预测轨迹。没有球物理，就没有游戏。#301 的 scaffold 提供了项目骨架，但 `mini-pong/gdscripts/` 和 `mini-pong/scenes/` 仍然为空。#287 是填充这些目录的第一个 Issue。

### 为什么手动 _process

经典街机 Pong 使用基于帧的线性运动，而非基于物理引擎的加速度/质量模拟。手动 `_process(delta)` 更新提供：

1. **精确控制：** 速度、角度、碰撞完全由代码决定，无物理引擎的浮点累积误差
2. **确定性：** 相同输入产生相同结果，适合回放和调试
3. **街机手感：** 即时响应，无惯性/阻尼，与经典 Pong 体验一致
4. **简单性：** Pong 的碰撞模型极为简单（矩形反弹 + 角度映射），不需要 `RigidBody2D` 的重量级物理

### 设计原则

1. **自包含：** 球脚本管理自身的运动、碰撞检测、速度递增——不依赖外部 Manager
2. **信号驱动：** 得分事件通过 `signal score(side: int)` 发出，解耦球物理与计分系统
3. **可调参数：** 初始速度、最大速度倍数、速度增量、发球角度范围均为 `@export` 变量，方便调试平衡
4. **边界安全：** 处理球飞出边界、NaN 速度、多帧穿透等边缘情况

### 先前约束

- `mini-pong/project.godot` 使用 2D Forward+ 渲染器——Pong 是纯 2D 游戏，Forward+ 仅影响视觉特效（glow），不影响 2D 物理
- Scaffold 阶段未定义任何 `input_map` 或 `autoload`——球物理是自包含模块
- `run/main_scene` 当前为空——球场景可作为临时 main scene 用于测试，或后续由游戏主场景加载

---

## 3. 影响分析

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/gdscripts/ball.gd` | GDScript | Area2D 球物理：运动、碰撞检测、反弹计算、速度管理、发球 |
| `mini-pong/scenes/ball.tscn` | Godot 场景 | Area2D 根节点 + CollisionShape2D + Sprite2D/ColorRect 可视化 |
| `mini-pong/scenes/wall.tscn` | Godot 场景 | StaticBody2D + CollisionShape2D 上下墙壁（或直接在 game scene 中创建） |
| `mini-pong/scenes/game.tscn` | Godot 场景 | 游戏主场景：包含球、墙壁、挡板（为后续 Issue 预留节点） |

### 修改文件

| 文件 | 修改内容 |
|------|---------|
| `mini-pong/project.godot` | 设置 `run/main_scene="res://scenes/game.tscn"` 以支持 headless 直接运行 |

### 间接影响模块（后续 Issue 将依赖）

| 模块 | 影响 |
|------|------|
| 挡板脚本 (`paddle.gd`) | 需要在 `body_entered` 信号中区分球与其他物体，与球的碰撞处理配合 |
| 计分系统 (`score_manager.gd`) | 需要连接球的 `score` 信号 |
| AI 对手 | 需要读取球的位置/速度来预测轨迹 |
| 主场景 (`game.tscn`) | 需要实例化 Ball 场景并放置在合适位置 |

### 数据流

```
Game Scene
  │
  ├──► Ball (Area2D)
  │       │
  │       ├── _process(delta)
  │       │     └── position += velocity * delta
  │       │
  │       ├── area_entered / body_entered
  │       │     ├──► Top/Bottom Wall → velocity.y *= -1
  │       │     └──► Left/Right Paddle
  │       │           ├──► Calculate impact offset
  │       │           ├──► Map offset to angle
  │       │           ├──► Apply new velocity
  │       │           └──► speed = min(speed * 1.05, max_speed)
  │       │
  │       └── _process boundary check
  │             ├──► Left boundary → emit score(RIGHT_SIDE)
  │             └──► Right boundary → emit score(LEFT_SIDE)
  │
  ├──► Top Wall (StaticBody2D)
  ├──► Bottom Wall (StaticBody2D)
  ├──► Left Paddle (Area2D) ← 后续 Issue
  └──► Right Paddle (Area2D) ← 后续 Issue
```

### 文档更新

- 无需更新现有文档——这是 Mini Pong 的第一个功能模块

---

## 4. 方案对比

### 方案 A：自包含 `ball.gd` Area2D + 手动 _process（推荐）

Area2D 脚本自管理所有物理逻辑。使用 `_process(delta)` 逐帧移动球，通过 `area_entered`/`body_entered` 信号检测碰撞，手动计算反弹。

**反弹角度计算（挡板）：**

```gdscript
# 撞击点偏移量：-1.0（顶部）到 +1.0（底部）
var impact_offset = (ball_pos.y - paddle_center.y) / (paddle_height / 2.0)
impact_offset = clamp(impact_offset, -1.0, 1.0)

# 映射到反弹角度：-60° 到 +60°（或可配置范围）
var max_angle = deg_to_rad(60.0)
var bounce_angle = impact_offset * max_angle

# 新速度方向
var direction = 1 if ball was moving left else -1
velocity = Vector2(cos(bounce_angle) * direction, sin(bounce_angle)) * speed
```

| 优点 | 缺点 |
|------|------|
| 完全控制运动行为，无物理引擎副作用 | 需手动处理碰撞检测的所有边缘情况 |
| 代码集中在一个文件中，易于理解和调试 | 碰撞检测依赖于 Godot 信号系统 |
| 符合街机风格——线性运动，精确帧步进 | 高速球可能穿透薄碰撞体（需补充射线检测或 CCD） |
| `@export` 参数易于调优 | |

**风险：** 低
**工作量：** 1-2 天（单文件脚本 + 场景搭建 + 测试场景）

---

### 方案 B：Ball Area2D + PhysicsManager Autoload

将碰撞计算逻辑分离到 `PhysicsManager` autoload，球脚本仅负责位置更新和信号发射。

| 优点 | 缺点 |
|------|------|
| 碰撞表现与运动逻辑分离，可复用 | 引入额外的全局依赖，增加复杂度 |
| 便于后续添加音效/粒子等碰撞反馈 | Ball 需要访问 Manager 的单例引用 |
| Autoload 可管理全局物理参数 | Pong 仅有一个运动物体——分离过度 |
| | 计分信号仍需从 Ball 发出，Manager 职责模糊 |

**风险：** 低-中（过度设计）
**工作量：** 2-3 天

---

### 方案 C：RigidBody2D + Godot 物理引擎

使用 Godot 内置的 `RigidBody2D` 和 `PhysicsMaterial`，依靠物理引擎处理运动、碰撞和反弹。

| 优点 | 缺点 |
|------|------|
| 碰撞检测由引擎处理 | 无法实现"根据撞击位置变化角度"——RigidBody 反弹角度由物理材质 + 速度决定，不对应 Pong 的设计需求 |
| 代码量最少 | 速度管理（+5%/hit）需覆盖物理引擎的速度计算 |
| | 确定性差——物理引擎有浮点累积误差 |
| | 街机手感丢失——有惯性/角动量等不需要的物理属性 |
| | 发球随机方向难以精确控制 |

**风险：** 高（不符合设计需求）
**工作量：** 1 天（但需要大量调整以匹配 Pong 行为）

---

### 推荐：方案 A

对于 Pong 的球物理，自包含 `ball.gd` + 手动 `_process` 是最佳选择：

1. **需求匹配：** 只有手动 `_process` 能实现"撞击挡板位置决定反弹角度"这一核心需求。方案 C 的 RigidBody 反弹由物理材质决定，无法根据 Y 轴偏移映射角度
2. **街机风格：** 手动位置更新提供精确、确定性的运动，匹配经典 Pong 的手感
3. **最小复杂度：** 单文件脚本，无额外依赖。Pong 只有一个运动物体，不需要 Manager 抽象层
4. **可测试性：** 直接 `@export` 参数（速度、角度范围、增速比例），Godot headless 模式可直接运行验证

### 关键实现细节（方案 A）

#### 碰撞检测策略

| 碰撞对象 | 节点类型 | 检测方式 | 处理 |
|---------|---------|---------|------|
| 上/下墙壁 | StaticBody2D | `body_entered` 信号 | `velocity.y *= -1` |
| 左/右挡板 | Area2D | `area_entered` 信号 | 计算撞击偏移 → 映射角度 → 设置新速度 |
| 左/右边界 | 无节点（_process 坐标检测） | `position.x < -threshold` / `> screen_width + threshold` | 发射 `score()` 信号 + 重置发球 |

#### 速度管理

```
初始速度:    INITIAL_SPEED (e.g., 300 px/s)
每次挡板击中: speed *= 1.05
最大速度:    INITIAL_SPEED * 2.0
发球重置:    speed = INITIAL_SPEED
```

#### 发球逻辑

```
serve():
  position = Vector2(screen_center_x, screen_center_y)
  var angle = randf_range(-45°, 45°)  # 上半/下半随机
  var direction = [-1, 1].pick_random()  # 左方或右方
  velocity = Vector2(cos(angle) * direction, sin(angle)) * INITIAL_SPEED
```

---

## 5. 边界条件与验收标准

### 验收标准

- [x] **AC1: Area2D 球有 CollisionShape2D（shape 不为空）** — 球场景的 Area2D 子节点包含有效的 CollisionShape2D 及 RectangleShape2D/CircleShape2D
- [x] **AC2: 撞上下墙 Y 方向完美反弹** — `body_entered` 信号检测到 StaticBody2D（墙壁组），`velocity.y *= -1`，不改变 X 分量
- [x] **AC3: 撞左右挡板反弹角度随撞击位置变化** — `area_entered` 信号检测挡板 Area2D，计算撞击 Y 偏移，映射到反弹角度（中心=水平反弹，边缘=±60° 反弹），X 方向取反
- [x] **AC4: 每次击挡板速度 +5%，上限 2x** — 在挡板碰撞处理中 `speed = min(speed * 1.05, INITIAL_SPEED * 2.0)`
- [x] **AC5: 球出左右边界触发得分事件** — `_process` 中检测 `position.x < 0` 或 `> screen_width`，发射 `signal score(side: int)`，然后调用 `serve()` 重置
- [x] **AC6: --headless --quit 无脚本错误** — `godot --path mini-pong/ --headless --quit` 退出码 0，无解析/运行时错误

### 边缘情况

1. **球卡在碰撞体内：** 反弹后确保球朝远离碰撞体的方向移动至少 1 帧距离，防止重复触发 `body_entered`/`area_entered` 导致球震荡或穿出
2. **高速球穿透薄墙壁：** 当球速极高时（2x 上限），一帧内位移可能超过墙壁厚度。使用 `move_and_collide()` 或逐段射线检测替代直接 `position += velocity`
3. **NaN 速度：** 意外除零或非法碰撞计算可能导致 `velocity` 为 NaN——每个 `_process` 帧开头检查 `is_nan(velocity.x)`，检测到时重置为默认方向
4. **极端角度反弹：** `impact_offset` 钳制到 `[-1, 1]` 范围（通过 `clamp`），防止球以接近垂直的角度反弹导致回合过长
5. **多物体同时碰撞：** 单帧内球可能同时碰到墙壁和挡板——优先处理挡板碰撞（游戏性相关），忽略墙壁信号（或延迟一帧再处理）
6. **发球方向：** `randf_range(-45°, 45°)` 确保发球不是完全水平，避免球在上下墙之间无限水平反弹
7. **发球时球已在碰撞体内：** `serve()` 在设置新位置后应延迟 0.5s 再开始运动，或确保发球位置远离所有碰撞体
8. **delta 为 0 或极大值：** 检查 `delta > 0 && delta < 0.1`（防止暂停/帧卡顿导致的异常位移）

### 失败路径

1. **CollisionShape2D 未设置 shape：** 球不触发任何碰撞信号，直接飞出边界——应在 `_ready()` 中断言 `$CollisionShape2D.shape != null`
2. **墙壁缺失：** 球飞出上下边界——应在 `_process` 中额外检测 Y 边界并反转，作为墙壁碰撞的兜底
3. **挡板碰撞检测失败：** 球穿过挡板——确保 `move_and_collide()` 使用而非直接位置加法（防止穿透），或使用 `continuous_cd = CD_RAY` 模式

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|------|
| #301 项目骨架 | ✅ CLOSED — scaffold 已完成 | 无 |
| `mini-pong/gdscripts/` 目录 | ✅ 已创建（空） | 无 |
| `mini-pong/scenes/` 目录 | ✅ 已创建（含 environment） | 无 |
| godot CLI 可用 | ✅ 已验证（4.x） | 无 |

### 阻塞（后续 Issue）

| 后续工作 | 优先级 | 关系 |
|---------|:------:|------|
| 挡板控制（玩家 WASD / AI） | critical | 球反弹需要挡板 `area_entered` 信号——挡板必须先创建 |
| 计分系统 UI | critical | 依赖 `ball.score` 信号 |
| AI 对手 | high | 需要球位置/速度用于预测 |
| 音效 | medium | 依赖球的碰撞事件 |
| 粒子特效 | low | 依赖球的碰撞事件 |

> **⚠️ 注意：** #287 的球脚本可以在没有挡板的情况下测试——墙壁反弹和边界检测可独立验证。挡板碰撞测试需要先创建挡板场景。

### 依赖链

```
#301 (scaffold) ──► #287 (ball physics) ──► Paddle Control ──► Scoring ──► AI
                              │
                              └──► 可先测试墙壁反弹 + 边界得分
```

### 准备事项

- [x] `mini-pong/gdscripts/` 目录已创建
- [x] `mini-pong/scenes/` 目录已创建
- [x] Godot 4.x CLI 可用
- [ ] `mini-pong/project.godot` 需设置 `run/main_scene` 指向测试/游戏场景

---

## 7. Spike / 实验

> 跳过：按 `depth/standard` 标签，本节可选。球物理的三种方案比较已在 Section 4 中充分覆盖。如果后续发现边缘情况（如高速穿透），可在 Plan 阶段增加射线检测实验。

---

## 8. 延续上下文（Plan Agent 交接）

### 当前系统状态

- `mini-pong/` 为独立 Godot 4.x 2D Forward+ 项目，glow 已开启
- `mini-pong/gdscripts/`、`mini-pong/scenes/` 为空（待 #287 填充第一个功能模块）
- `mini-pong/project.godot` 的 `run/main_scene` 为空——需设为 game.tscn
- 未设定任何 `input_map` 或 `autoload`
- `godot --path mini-pong/ --headless --quit` 当前因无 main scene 而超时（非阻塞性错误）

### 实施注意事项

1. **文件位置：** 所有 .gd 文件放在 `mini-pong/gdscripts/`，所有 .tscn 放在 `mini-pong/scenes/`
2. **碰撞层设置：** 使用 Godot 2D 碰撞层区分墙壁（layer 1）、球（layer 2）、挡板（layer 3）。球的 `collision_mask` 应包含 layer 1 + layer 3
3. **推荐节点结构（ball.tscn）：**
   ```
   Area2D (ball)
   ├── CollisionShape2D (CircleShape2D, radius ~10px)
   ├── Sprite2D 或 ColorRect (50×50 or 20×20)
   └── (可选) PointLight2D 用于 glow 效果
   ```
4. **信号定义：**
   ```gdscript
   signal score(side: int)
   # side: 0 = 左方得分（球从右侧出界）, 1 = 右方得分（球从左侧出界）
   ```
5. **推荐墙壁方案：** 在 game.tscn 中直接添加两个 `StaticBody2D` 节点（带 `CollisionShape2D`），而非独立场景文件——Pong 的上下墙是固定的
6. **验证方法：**
   ```bash
   # 创建 game.tscn 包含球+墙壁后
   godot --path mini-pong/ --headless --quit
   echo "Exit: $?"
   ```
7. **CCD（连续碰撞检测）：** 如果 2x 速度下出现穿透，将 `Area2D` 的 `collision_layer` 与 `move_and_collide()` 结合使用，或在 `_process` 中执行分段检测

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| 高速穿透薄碰撞体 | 中 | 高（球穿过墙/挡板） | 使用 `move_and_collide()` 或 2x 采样步 |
| `body_entered` 重复触发 | 中 | 中（球震荡/飞出） | 反弹后确保速度方向远离碰撞体，加冷却帧 |
| 发球方向过于垂直 | 低 | 低（回合过长） | ±45° 角度限制 |
| `randf_range` 非确定性（multiplayer） | 低 | 低 | 当前为本地单人 Pong，非问题 |

### 下一步

Plan Agent 将基于此 PRD 创建 `docs/DESIGN/287-ball-physics.md`，详细指定：
- `ball.gd` 的完整 API（导出变量、信号、公共方法）
- `ball.tscn` 和 `game.tscn` 的节点结构
- 碰撞层/掩码矩阵
- 反弹角度映射的精确公式
- 速度管理的状态机
- 测试场景结构（墙壁反弹测试 + 边界得分测试）

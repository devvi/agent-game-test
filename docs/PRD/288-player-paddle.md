# PRD: [Feature] 玩家挡板与输入

> **Issue:** #288
> **标签:** enhancement, workflow/research, depth/light, priority/critical, version/mvp, estimate/small
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #301 (Scaffold — 已完成)

---

## 1. 问题定义

### 当前状态

`mini-pong/` 子项目已通过 #301 完成基础脚手架：独立 `project.godot`（2D Forward+ 渲染器，glow/bloom 开启）、`world_environment.tscn` 场景、以及 `gdscripts/`、`scenes/`、`assets/`、`tests/` 标准子目录。但当前状态是项目骨架——没有任何游戏逻辑代码，`gdscripts/` 目录完全为空。

| 系统 | 当前状态 | 缺失 |
|------|---------|------|
| 玩家输入 | 无 — `project.godot` 无 `[input]` 段，无 InputMap 绑定 | 完整的输入处理管线 |
| 玩家挡板 | 无 — 无场景文件、无脚本、无视觉 | Area2D + ColorRect + 脚本 |
| 屏幕边界 | 无 — 无边界定义 | clamp 逻辑 |
| 编译验证 | CI 验证骨架可编译 | 添加游戏代码后仍需通过编译 |

### 预期行为

创建玩家控制的 Pong 挡板，具备以下行为：

1. **视觉呈现：** `Area2D` 节点 + `ColorRect` 子节点作为视觉，尺寸为窄长方形（如 20×120 像素），颜色暂定为白色/霓虹蓝（视觉风格由 #6 统一处理）
2. **输入响应：** WASD（W/S）和方向键（↑/↓）控制挡板上下移动，移动速度恒定
3. **屏幕限制：** 挡板 Y 坐标 clamp 在屏幕上下边界内（顶部边界 + 挡板半高，底部边界 - 挡板半高）
4. **InputMap 绑定：** 通过 GDScript 代码在 `_ready()` 中动态创建 `paddle_up` 和 `paddle_down` 两个 action，绑定 W、↑ 到 `paddle_up`，S、↓ 到 `paddle_down`
5. **碰撞检测就绪：** `Area2D` 必须包含非空的 `CollisionShape2D`（RectangleShape2D），为后续球碰撞检测做准备
6. **编译验证：** `godot --path mini-pong/ --headless --quit` 退出码为 0，无脚本错误

### 用户场景

1. **玩家移动挡板：** 游戏运行中，玩家按 W 或 ↑ → 挡板向上移动；按 S 或 ↓ → 挡板向下移动。松开按键 → 挡板停止。
2. **边界保护：** 玩家持续按住 ↑ → 挡板移动到屏幕顶部后停止，不会移出屏幕。同理底部边界。
3. **速度一致性：** 每次按同方向键，挡板移动速度完全相同（恒定速度，无加速度）。
4. **未来集成：** 挡板场景/脚本作为独立组件，可在主场景中直接实例化。

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 玩家挡板场景（Area2D + ColorRect） | AI 对手挡板（Issue #289） |
| WASD + 方向键输入处理 | 键位自定义/重映射 |
| InputMap 代码绑定（paddle_up/down） | project.godot 文件中的 InputMap 声明 |
| 屏幕边界 clamp | 球碰撞检测逻辑（Issue #290） |
| CollisionShape2D（RectangleShape2D） | 视觉效果/霓虹配色（Issue #291） |
| headless 编译验证 | 运行时输入测试 |

---

## 2. 设计意图

### 为什么是现在

#301 完成了 Mini Pong 的项目骨架，提供了可编译的空项目。玩家挡板是紧随其后的第一个游戏逻辑功能——它是玩家唯一直接控制的物体，也是 Pong 游戏体验的核心入口。在脚手架之上立即实现输入系统，可以验证：

- `mini-pong/` 子项目能否正常加载和运行 GDScript
- 代码绑定的 InputMap 方案是否正确（避免 project.godot 解析 bug）
- headless 编译流程是否在添加脚本后仍然可用

### 设计原则

1. **代码绑定 InputMap：** 不在 `project.godot` 中声明 `[input]` 段。使用 `InputMap.add_action()` + `InputMap.action_add_event()` 在 `_ready()` 中动态创建。这避免了 project.godot ConfigFile 解析 bug，也是 Godot 4.x 推荐的运行时绑定模式。
2. **最小依赖：** 挡板是独立组件，只依赖 Godot 内置 API（Input、InputMap、Area2D）。不依赖 autoload、不依赖其他脚本、不依赖外部数据。
3. **纯 `_process` 驱动：** 每帧检测输入状态 → 更新位置 → clamp 边界。不使用 `_physics_process`，因为挡板不需要物理模拟。
4. **场景化封装：** 挡板作为独立 `.tscn` 场景文件，可在主场景中直接拖入实例化。脚本 `paddle.gd` 挂载在 Area2D 根节点上。

### 先前约束

| 约束 | 来源 | 影响 |
|------|------|------|
| 项目不存在 `[input]` 段 | #301 脚手架（最小 project.godot） | 必须代码绑定 InputMap — 这恰好符合本 Issue 要求 |
| `run/main_scene=""` | #301 脚手架 | 挡板场景暂不设为主场景 — 由后续 Integration Issue 处理 |
| Forward+ 渲染器 + glow | #301 脚手架 | 挡板视觉（ColorRect 颜色）后续由视觉系统统一处理 |
| Godot 4.x headless 模式 | CI pipeline | 脚本不能有编译时错误（`@export` 类型、语法错误等） |

---

## 3. 影响分析

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/scenes/player_paddle.tscn` | Godot 场景 | 玩家挡板场景（Area2D 根 + ColorRect 视觉 + CollisionShape2D） |
| `mini-pong/gdscripts/paddle.gd` | GDScript | 挡板移动、InputMap 绑定、边界 clamp 逻辑 |

### 修改文件

无。这是全新功能的首次提交，不影响现有文件。

### 数据流

```
键盘输入 (W/S/↑/↓)
    │
    ▼
paddle.gd:_ready()
    ├── InputMap.add_action("paddle_up")
    │   ├── 绑定键: KEY_W
    │   └── 绑定键: KEY_UP
    └── InputMap.add_action("paddle_down")
        ├── 绑定键: KEY_S
        └── 绑定键: KEY_DOWN
    │
    ▼
paddle.gd:_process(delta)
    ├── Input.is_action_pressed("paddle_up")   → position.y -= speed * delta
    ├── Input.is_action_pressed("paddle_down") → position.y += speed * delta
    └── position.y = clamp(position.y, min_y, max_y)
```

### 文档更新

无需更新现有文档 — 这是 Mini Pong 的第一个游戏逻辑功能。

---

## 4. 方案对比

| 方案 | 描述 | 优点 | 缺点 | 风险 | 工作量 |
|------|------|------|------|------|--------|
| **A：场景化 Area2D + 代码 InputMap（推荐）** | 独立 `.tscn` 场景：Area2D 根节点 + ColorRect + CollisionShape2D(RectangleShape2D)。`paddle.gd` 在 `_ready()` 中绑定 InputMap，`_process()` 中处理移动和 clamp。 | 独立组件，可拖入主场景；代码绑定 InputMap 避免 project.godot 解析 bug；Godot 4.x 标准模式 | 需要两份文件（tscn + gd）；后续集成需引用场景路径 | 低 | 小（~60 行 GDScript） |
| **B：纯脚本动态创建** | 不创建 .tscn 文件，在 `paddle.gd` 的 `_ready()` 中用 `new()` + `add_child()` 动态创建 Area2D、ColorRect、CollisionShape2D。 | 单文件方案，无 tscn 依赖 | 节点树难以在编辑器中预览；调试不便；与 Godot 场景化设计理念相悖 | 中 | 小（~90 行 GDScript） |
| **C：CharacterBody2D 物理驱动** | 使用 CharacterBody2D + `move_and_slide()`，InputMap 绑定在 project.godot 中声明。 | 物理引擎处理碰撞；move_and_slide 自动处理边界 | project.godot InputMap 声明有解析 bug 风险；CharacterBody2D 对简单挡板过度设计；Pong 不需要物理模拟 | 高 | 中 |

### 推荐：方案 A

对于 Mini Pong 玩家挡板，方案 A 是最佳选择：

1. **场景化组件**符合 Godot 4.x 最佳实践 — 挡板可在编辑器中预览和调整
2. **代码绑定 InputMap** 避免 project.godot 解析 bug，也是 Issue 的明确要求
3. **Area2D 而非 CharacterBody2D** — Pong 挡板不需要物理引擎（无重力、无摩擦力），`_process` 中手动移动更简单直接
4. **RectangleShape2D** 精确匹配挡板的矩形轮廓，为后续球碰撞检测做好准备
5. 方案 B 的动态创建会失去编辑器预览能力；方案 C 的 project.godot InputMap 方案违反 Issue 要求

---

## 5. 边界条件与验收标准

### 正常路径

1. 场景加载 → `_ready()` 绑定 InputMap → `paddle_up` 绑定 W 和 ↑，`paddle_down` 绑定 S 和 ↓
2. 按 W 或 ↑ → 挡板每帧向上移动 `speed * delta` 像素
3. 按 S 或 ↓ → 挡板每帧向下移动 `speed * delta` 像素
4. 同时按 W 和 S → 两个方向抵消，挡板静止
5. 挡板到达屏幕顶部 → `clamp()` 阻止继续向上
6. 挡板到达屏幕底部 → `clamp()` 阻止继续向下

### 验收标准

- [ ] **AC1: W/↑ 向上移动** — 按下 W 或 ↑ 键，挡板持续向上移动，速度恒定（如 400 px/s）
- [ ] **AC2: S/↓ 向下移动** — 按下 S 或 ↓ 键，挡板持续向下移动，速度恒定
- [ ] **AC3: 边界 clamp** — 挡板中心 Y 坐标不超过 `[paddle_half_height, viewport_height - paddle_half_height]`
- [ ] **AC4: InputMap 代码绑定** — `_ready()` 中使用 `InputMap.add_action()` 和 `InputMap.action_add_event()`，不在 project.godot 中声明
- [ ] **AC5: CollisionShape2D 非空** — `player_paddle.tscn` 中 Area2D 包含 CollisionShape2D 子节点，shape 设为 RectangleShape2D（非空）
- [ ] **AC6: headless 编译** — `godot --path mini-pong/ --headless --quit` 退出码为 0，无 `SCRIPT ERROR`

### 边缘情况

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | 同时按下 W 和 S（或 ↑ 和 ↓） | 两个方向输入抵消，挡板静止不动 |
| 2 | 窗口缩放后 | 在 `_ready()` 中获取 `get_viewport().get_visible_rect().size`，边界 clamp 使用动态值 |
| 3 | 挡板初始位置不在屏幕内 | 启动时 clamp 到合法范围内 |
| 4 | 帧率极低（delta 巨大） | `speed * delta` 可能跳过边界 → 使用 `clamp()` 确保最终位置总在范围内 |
| 5 | 多次调用 `add_action`（重复初始化） | `InputMap.has_action()` 检查，避免重复添加（如果场景被多次实例化） |

### 失败路径

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | InputMap action 名冲突 | `has_action()` 跳过已存在的 action，不抛异常 |
| 2 | CollisionShape2D shape 为 null | Godot 编辑器会显示警告；headless 模式可能产生错误 — 确保 tscn 中 shape 资源完整 |
| 3 | 同一键绑定到多个 action | Godot 允许同一键触发多个 action — 不处理（按设计，paddle_up 和 paddle_down 不共享键） |

---

## 6. 依赖与阻碍

### 依赖关系

```
#301 (Scaffold — 已完成 ✅)
    │
    ▼
#288 (玩家挡板与输入 — 本 Issue)
    │
    ├──► #290 (球物理与碰撞 — 依赖挡板存在)
    └──► #295 (主场景组装 — 依赖挡板场景)
```

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #301 Scaffold | ✅ 已完成 | 低 | `mini-pong/` 目录结构、project.godot 已就绪 |
| Godot 4.7 headless | ✅ 可用 | 低 | CI 中已验证 `godot --headless --quit` 可运行 |

### 被阻碍

| 后续工作 | 优先级 | 说明 |
|---------|:------:|------|
| #290 球物理与碰撞 | critical | 球需要检测与挡板 Area2D 的碰撞 |
| #295 主场景组装 | high | 主场景需要实例化挡板并连接信号 |

### 准备清单

- [x] `mini-pong/` 目录结构已创建（#301）
- [x] `mini-pong/gdscripts/` 目录存在且为空
- [x] `mini-pong/scenes/` 目录存在（含 world_environment.tscn）
- [x] `godot --path mini-pong/ --headless --quit` 当前可通过

---

## 8. 延续上下文（Plan Agent 交接）

### 当前系统状态

- `mini-pong/` 子项目已通过 #301 完成脚手架：`project.godot`（2D Forward+，glow）、`scenes/world_environment.tscn`（glow 0.6）、空 `gdscripts/`、空 `assets/`、空 `tests/`
- `project.godot` 无 `[input]` 段 — 所有 InputMap 绑定通过代码完成
- `run/main_scene=""` — 暂未设置主场景
- 默认分支为 `main`

### 实施注意事项

1. **InputMap 绑定模式：** 使用 `InputMap.add_action("paddle_up")` + `InputMap.action_add_event("paddle_up", event)` 模式。先用 `InputMap.has_action()` 检查避免重复。参考 Godot 4.x 文档：`InputEventKey` 的 `keycode` 设置键值。
2. **TSCN 场景结构：**
   ```
   Area2D (root, paddle.gd 挂载)
   ├── ColorRect (视觉，尺寸 20×120)
   └── CollisionShape2D (shape=RectangleShape2D，尺寸匹配 ColorRect)
   ```
3. **移动速度常量：** `const SPEED = 400.0` (pixels/second) — 在 `_process(delta)` 中乘以 delta。
4. **边界计算：** 在 `_ready()` 中：
   ```gdscript
   var viewport_size = get_viewport().get_visible_rect().size
   var half_height = collision_shape.shape.size.y / 2.0
   min_y = half_height
   max_y = viewport_size.y - half_height
   ```
5. **TSCN 格式：** 使用 Godot 4.x 文本格式（`format=3`）。`CollisionShape2D` 的 `shape` 引用 `SubResource("RectangleShape2D")` 并设置 `size`。
6. **验证方法：**
   ```bash
   godot --path mini-pong/ --headless --quit
   echo "Exit: $?"
   ```

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|:------:|:----:|---------|
| TSCN 中 CollisionShape2D shape 资源格式错误 | 中 | 高（headless 编译失败） | 先手动创建空场景验证格式，再填充参数 |
| InputMap action 名称与其他系统冲突 | 低 | 中 | 使用 `has_action()` 检查；`paddle_up/down` 命名唯一性高 |
| `get_viewport()` 在 headless 模式返回 null | 低 | 高（脚本崩溃） | 如果 viewport 不可用，使用默认边界值（如 720p）作为回退 |
| 挡板速度在不同帧率下不一致 | 低 | 低 | 使用 `delta` 乘算确保帧率无关 |

### 设计决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 节点类型 | Area2D | 需要碰撞检测但不需物理模拟 |
| 移动驱动 | `_process` | 输入响应比物理步骤更合适 |
| InputMap 位置 | 代码 | 避免 project.godot ConfigFile 解析 bug |
| 边界来源 | 动态（viewport） | 支持窗口缩放 |
| 场景 vs 纯脚本 | 独立 .tscn | 编辑器预览 + Godot 最佳实践 |

### 下一步

Plan Agent 将使用此 PRD 创建 DESIGN 文档，详细描述 `player_paddle.tscn` 和 `paddle.gd` 的具体实现。Implement Agent 将创建两个文件并验证 `godot --headless --quit` 通过。

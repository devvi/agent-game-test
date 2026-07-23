# 08 — 玩家控制器 (Player Controller)

> 首次记录：2026-07-23 (Issue #142)
> 更新：2026-07-24 (Issue #156 — ExitZone 区域传送组件)
> 更新：2026-07-24 (Issue #150 — 第三人称轨道相机系统)
> 更新日志：[INDEX](INDEX.md)

---

## 1. 概述

玩家控制器为这款叙事步行模拟器提供 WASD 移动、点击拖拽鼠标视角、以及 E 键交互三种核心操作。控制器是**每场景实例化**的 CharacterBody3D，由 SceneBase._ready() 在场景加载时创建，随场景卸载而销毁。位置/旋转通过 GameManager 的三个变量 (`player_position`, `player_rotation`, `player_head_rotation`) 在场景切换间持久化。

### 核心约束

- **叙事步行模拟器，非动作游戏** — 不跳跃、不冲刺、不蹲伏
- **行走速度：2.5 m/s** — 悠闲的叙事节奏
- **鼠标不是指针捕获模式** — 点击拖拽看视角，光标保留（用于现有 UI 交互）

---

## 2. 移动系统 (WASD)

### 输入动作

| 动作 (Action) | 键位 | 功能 |
|---------------|------|------|
| `move_forward` | W / ↑ | 沿相机朝向向前 |
| `move_backward` | S / ↓ | 沿相机反方向向后 |
| `move_left` | A / ← | 向左平移 (strafe) |
| `move_right` | D / → | 向右平移 (strafe) |

### 移动逻辑

在 `_physics_process(delta)` 中执行：

1. 通过 `Input.get_vector()` 读取四方向输入
2. 将输入向量转换为相对**相机朝向**的世界空间方向（忽略俯仰）
3. 归一化后乘以 `walk_speed = 2.5` 得到 velocity
4. 无输入时通过 `move_toward()` 平滑减速
5. `move_and_slide()` 完成碰撞解析

### 对话模式（移动暂停）

- 当 `_dialogue_active == true`：WASD 被跳过，只应用刹车
- 刹车使用 `velocity.move_toward(Vector3.ZERO, walk_speed * delta)`，实现轻柔停止

---

## 3. 视角系统 (鼠标拖拽)

### 实现方式

鼠标视角使用**点击拖拽**而非指针捕获模式：

- 左键按下且不在对话中 → 进入拖拽模式 (`_mouse_dragging = true`)
- 左键释放 → 退出拖拽
- 拖拽期间移动 → 计算像素偏移量并应用旋转

### 两种相机模式

PlayerController 支持两种相机模式，通过 `camera_mode` 导出变量切换：

| 模式 | 默认 | 说明 |
|------|------|------|
| `third_person` | ✅ 默认 | 第三人称肩后视角，相机围绕角色旋转 |
| `first_person` | | 第一人称视角，兼容旧行为 |

### 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `look_sensitivity` | 0.003 | 每像素旋转弧度（第一人称） |
| `look_vertical_clamp` | 1.047 rad (60°) | 第一人称垂直视角限制 |
| `camera_tilt` | -0.087 rad (~-5°) | 轻微向下倾斜，增强沉浸感 |
| `orbit_sensitivity` | 0.003 | 每像素轨道旋转弧度 |
| `orbit_pitch_min` | -0.523 rad (-30°) | 第三人称俯仰下限 |
| `orbit_pitch_max` | 0.785 rad (+45°) | 第三人称俯仰上限 |
| `spring_arm_length` | 4.0 m | 第三人称相机最大臂长 |
| `camera_height` | 2.0 m | 第三人称相机Y偏移 |

### 第三人称轨道控制

**偏航 (Yaw)**：鼠标水平拖拽 → 旋转 `CameraPivot` 绕 Y 轴 → 相机围绕角色水平旋转
**俯仰 (Pitch)**：鼠标垂直拖拽 → 旋转 `SpringArm3D` 绕 X 轴 → 相机垂直倾斜，clamp 在 [-30°, +45°]

```gdscript
func _handle_mouse_look(delta: Vector2) -> void:
    if camera_mode == "third_person":
        _orbit_yaw -= delta.x * orbit_sensitivity
        _orbit_pitch -= delta.y * orbit_sensitivity
        _orbit_pitch = clamp(_orbit_pitch, orbit_pitch_min, orbit_pitch_max)
        camera_pivot.rotation.y = _orbit_yaw
        spring_arm.rotation.x = _orbit_pitch
    else:
        # 第一人称：旋转整个身体（偏航）+ 仅头部旋转（俯仰）
        rotate_y(-delta.x * look_sensitivity)
        head.rotation.x = clamp(
            head.rotation.x - delta.y * look_sensitivity,
            -look_vertical_clamp + camera_tilt,
            look_vertical_clamp + camera_tilt
        )
```

### SpringArm3D 碰撞解析

使用 Godot 4.7.1 内置的 `SpringArm3D` 节点处理相机碰撞：

- **射线起点**：CameraPivot 位置（角色中心）
- **臂长**：4.0m（默认肩后偏移）
- **碰撞掩码**：`0b100`（层 3）— 仅碰撞场景几何体（层 2）
- **排除对象**：`add_excluded_object(self)` — 不碰撞玩家身体
- **自动缩短**：被阻挡时 SpringArm3D 自动缩短至碰撞点前方 0.3m
- **自动恢复**：障碍移除后弹簧臂自动延伸回全长

### 相机结构

```
PlayerController (CharacterBody3D)
    ├── Head (Node3D)               ← 可选的，第一人称残保留，不再驱动相机
    ├── CameraPivot (Node3D)        ← [新增] 轨道偏航旋转节点
    │   └── SpringArm3D             ← [新增] 碰撞感知的弹簧臂，length=4.0m, margin=0.3m
    │       └── Camera3D            ← 位置 (0, 2.0, 0)，相对于 SpringArm3D 末端
    ├── PlayerCollisionShape (CollisionShape3D)  ← CapsuleShape3D, position.y=0.7
    ├── PlayerVisual (MeshInstance3D)  ← [新增] 占位胶囊网格，第三人称相机可见
    ├── InteractionArea (Area3D)                 ← SphereShape3D, radius=2m
    └── FallReset (Area3D)                       ← BoxShape3D 1000×0.5×1000 at y=-100
```

### 玩家视觉占位网格

第三人称相机需要帧内可见的玩家角色。`_build_player_visual()` 创建发光的胶囊体 MeshInstance3D：

```gdscript
var capsule := CapsuleMesh.new()
capsule.radius = 0.3
capsule.height = 1.4
mesh_instance.mesh = capsule
mesh_instance.position = Vector3(0, 0.7, 0)

var mat := StandardMaterial3D.new()
mat.albedo_color = Color(0.3, 0.5, 1.0)  # 柔和蓝色
mat.emission_enabled = true
mat.emission = Color(0.1, 0.2, 0.8)
```

### 程序化节点树构建 (#149 + #150)

PlayerController 使用 `PlayerControllerScript.new()` 实例化（无 .tscn 场景文件），因此子节点在 `_ready()` 中通过 `_build_node_tree()`、`_build_collision_shape()`、`_build_camera_system()` 和 `_build_player_visual()` 程序化创建。关键逻辑：

- **守卫模式**：`if not has_node("X"): create` — 向后兼容手动预创建子节点的测试
- **@onready 重赋值**：创建节点后重新赋值 `head = $Head`, `camera_pivot = $CameraPivot` 等变量
- **幂等性**：`_ready()` 可多次调用而不产生重复节点
- **相机迁移**：`_build_camera_system()` 检测已有的 Head/Camera3D 并将其 reparent 到 CameraPivot/SpringArm3D 下

### 轨道状态持久化 (#150)

相机轨道偏航/俯仰角在场景切换时通过 GameManager 持久化：

- **保存**（SceneBase._exit_tree → _save_player_state）：调用 `_player.get_camera_orbit()` → 存入 `GameManager.camera_orbit_yaw` 和 `camera_orbit_pitch`
- **恢复**（SceneBase._ready → _instantiate_player）：从 `GameManager` 读取 → 调用 `_player.set_camera_orbit(yaw, pitch)`

---

## 4. 交互系统 (E 键)

### 交互检测

- PlayerController 自带 `InteractionArea` (Area3D, SphereShape3D, 半径 2m)
- 当其他节点进入交互区域且属于 `"interactable"` 组 → 压入 LIFO 栈
- 当节点离开交互区域 → 从栈中移除

### E 键行为

| 状态 | E 键行为 |
|------|----------|
| 不在对话中 + 栈非空 | 发出 `interaction_requested` 信号（目标为栈顶节点） |
| 不在对话中 + 栈为空 | 静默无反馈 |
| 对话中 | 调用 `dialogue_select`（E 作为额外的选择确认键） |

### 交互栈 (LIFO)

当玩家同时接近多个可交互对象时，最近进入的优先级最高：

```
玩家接近 NPC A  → [A]
玩家接近 NPC B  → [A, B]  (B 在栈顶)
按 E            → 与 B 交互
远离 B          → [A]
按 E            → 与 A 交互
```

### 失败路径处理

- 目标节点在栈中但已被释放 → `is_instance_valid()` 检测 → 跳过，递归取下一个
- 所有目标已被释放 → 按 E 静默无反馈

---

## 5. EKeyTrigger 组件

`EKeyTrigger` (gdscripts/e_key_trigger.gd) 是一个 Drop-in Area3D 组件，为现有场景触发器添加 E 键交互能力：

- 自动加入 `"interactable"` 组
- 检测到 Player 进入时，连接 PlayerController 的 `interaction_requested` 信号
- 当信号触发 → 发出自身的 `e_key_interacted` 信号
- 场景脚本连接此信号到已有的处理函数（如 `_start_door_dialogue()`）

### 信号防护

- `is_connected()` 检查防止重复连接
- `is_instance_valid()` 检查防止失效触发

---

## 6. 场景过渡持久化

### 保存时机

当场景卸载时，SceneBase._exit_tree() → `_save_player_state()`：

1. 检查 `_player` 是否有效
2. 检查 `/root/GameManager` 是否存在
3. 保存 `player_position`（global_position）
4. 保存 `player_rotation`（global_rotation）
5. 保存 `player_head_rotation`（Head.rotation.x）

### 恢复时机

当场景加载时，SceneBase._ready() → `_instantiate_player()`：

1. 防止重复实例化（检查 `is_instance_valid(_player)`）
2. 实例化 PlayerController
3. 从 GameManager 读取并恢复位置/旋转/头部俯仰
4. 连接 `interaction_requested` 信号
5. 设置掉落重置位置为 SpawnPoint

### 首次加载

首次进入游戏（无持久化状态）：
- `player_position` 默认为 `Vector3.ZERO` → 使用 SpawnPoint 标记位置
- 场景若无 SpawnPoint → 原点 `(0, 0, 0)`

### 区域传送 (Zone Transition, Issue #156)

**ExitZone 组件** (`gdscripts/exit_zone.gd`) 是放置在场景出口的 Area3D 组件，当玩家走入区域时自动触发场景切换。提供了两种传送模式：

| 模式 | 触发方式 | 适用场景 |
|------|----------|----------|
| AUTO (默认) | 玩家走入 CollisionShape3D → 自动淡出 → 切换场景 | 单向出口、走廊、门框 |
| EKEY | 玩家走入 → 显示提示标签 → 按 E 键 → 切换场景 | 需要玩家确认的出口、对话触发点 |

**传送流程：**
- ExitZone 检测到玩家进入 → 检查 `GameManager.transition_in_progress` 防止重复触发
- AUTO 模式：1 秒冷却定时器防止物理引擎重复碰撞误触发
- EKEY 模式：离开区域时自动断开信号连接，防止场景外误触
- 最后通过 SceneManager 的淡入/淡出管线完成场景切换

**Spawn Point 定向传送到目标场景：**
- ExitZone 将 `GameManager.target_spawn_point` 设为目标坐标
- 目标场景的 SceneBase._instantiate_player() 优先读取此值
- 读取后立刻清零，防止后续对话切换误用
- 无 target_spawn_point 时回退到 SpawnPoint Marker3D 或原点

**故障保护：**
| 故障场景 | 防护措施 |
|----------|----------|
| SceneManager 缺失 | `get_node_or_null()` + `has_method()` 双重检查 → push_error |
| GameManager 缺失 | `get_node_or_null()` 跳过 → 使用 SpawnPoint 回退位 |
| 空 `target_scene` | `_transition()` 检查 `is_empty()` → push_warning |
| 无 CollisionShape3D | `_validate_config()` 推警告 |
| 物体进入（非玩家） | `is_in_group("player")` 过滤 → 忽略 NPC/道具 |

---

## 7. 碰撞配置

### 碰撞体

#149 为 PlayerController 添加了程序化创建的 CapsuleShape3D：

| 参数 | 值 | 说明 |
|------|-----|------|
| `radius` | 0.3 | 胶囊体半径 (m) |
| `height` | 1.4 | 胶囊体高度 (m) |
| `shape.position.y` | 0.7 | 半高偏移，使底部平贴地面 |

节点名：`PlayerCollisionShape`（`has_node("PlayerCollisionShape")` 守卫）。

### 碰撞层与掩码

| 层 (Layer) | 用途 | 碰撞掩码 |
|------------|------|----------|
| 1 (Default) | PlayerController 身体 | 碰撞 2 |
| 2 (Scene Geometry) | 墙壁、地板 StaticBody3D | 碰撞 1 |
| 3 (Interaction Trigger) | 交互触发 Area3D | 检测 1 |

---

## 8. 输入验证 (Issue #153)

### @export_range 约束

所有 PlayerController 的可调节参数使用 `@export_range` 在 Godot 编辑器中提供可视化的滑动条约束，防止在场景编辑器中误输入不合理值：

| 参数 | 默认值 | 范围 | 步长 | 说明 |
|------|--------|------|------|------|
| `walk_speed` | 2.5 | [0.5 — 10.0] | 0.1 | 叙事步行速度 (m/s) |
| `look_sensitivity` | 0.003 | [0.001 — 0.02] | 0.0005 | 每像素旋转弧度 |
| `interaction_range` | 2.0 | [0.5 — 10.0] | 0.1 | E 键交互探测半径 (m) |
| `camera_height` | 1.6 | [0.5 — 3.0] | 0.1 | 视线高度 (m) |
| `camera_tilt` | -0.087 | [-1.0 — 1.0] | 0.001 | 默认俯仰角 (rad) |
| `look_vertical_clamp` | 1.047 | [0.174 — 1.57] | 0.01 | 垂直视角 ± 限制 (rad) |
| `spring_arm_length` | 4.0 | [1.0 — 10.0] | 0.5 | 第三人称相机臂长 (m) |
| `orbit_pitch_min` | -0.523 | [-1.0 — 0.0] | 0.01 | 第三人称俯仰下限 (rad) |
| `orbit_pitch_max` | 0.785 | [0.0 — 1.57] | 0.01 | 第三人称俯仰上限 (rad) |

### 运行时钳位 (Runtime Clamping)

`@export_range` 仅在 Godot 编辑器中有效。在 `--headless --script` 测试模式下，脚本直接创建实例，不经过编辑器约束。因此 `_physics_process()` 中使用 `clamp(walk_speed, 0.5, 10.0)` 进行运行时钳位：

```gdscript
var effective_speed: float = clamp(walk_speed, 0.5, 10.0)
velocity.x = direction.x * effective_speed
velocity.z = direction.z * effective_speed
```

### 启动时输入映射验证

`PlayerController._ready()` 调用 `_verify_input_map()` 检查输入动作是否在 InputMap 中注册：

| 动作 (Action) | 用途 |
|---------------|------|
| `move_forward` | 向前移动 |
| `move_backward` | 向后移动 |
| `move_left` | 向左平移 |
| `move_right` | 向右平移 |
| `interact` | E 键交互 |

缺失动作通过 `push_warning()` 报告，不阻断游戏启动 — 设计上允许缺少部分输入动作时仍可运行（例如缺少 `interact` 不会影响移动），但会在日志中清晰指出。

---

## 9. 故障恢复

### 掉落世界重置

- PlayerController 自带 `FallReset` Area3D（巨大 BoxShape3D 在 y = -10）
- 检测到自身掉落 → 重置到 `_fall_reset_position`（设为 SpawnPoint 位置）
- 速度归零

### 故障保护

| 故障场景 | 防护措施 |
|----------|----------|
| GameManager 缺失 | `get_node_or_null()` → 跳过保存/恢复 |
| 对话运行器缺失 | `has_signal()` 检查 → 跳过连接 |
| 目标节点无效 | `is_instance_valid()` 递归跳过 |
| Head 节点缺失 | `get_node_or_null()` → 跳过俯仰 |
| 重复实例化 | `is_instance_valid(_player)` 提前返回 |
| 两个 Camera 冲突 | `_disable_other_cameras()` 强制唯一 current |

---

## 10. 脚步音频 (#157)

### 10.1 移动触发

PlayerController 在 `_physics_process()` 中，当 WASD 方向向量非零且不在对话模式时，通过积累器 (0.5s 间隔) 触发 `_trigger_footstep()`：

| 参数 | 值 | 说明 |
|------|-----|------|
| `FOOTSTEP_INTERVAL` | 0.5s | 移动脚步间隔 |
| `_footstep_accumulator` | float | 累计帧时间，达阈值触发后归零 |
| 对话抑制 | 条件块 `not _dialogue_active` | 对话中静默，积累器归零 |

### 10.2 表面推断

`_trigger_footstep()` 通过 `AudioManager` 查询当前场景的表面类型：

```gdscript
var scene_id := get_tree().current_scene.name if get_tree().current_scene else ""
var surface := am.get_surface_for_scene(scene_id)
am.play_footstep(surface)
```

- 无 AudioManager 时静默降级 (`get_node_or_null` + `has_method` 守卫)
- 未知场景 ID 返回 `\"office\"` 默认表面
- 复用 AudioManager 的 `FOOTSTEP_COOLDOWN (0.3s)` 全局冷却

### 10.3 测试覆盖 (TC-FS)

| 类型 | 用例数 | 覆盖场景 |
|------|--------|----------|
| Normal | 4 | 脚步间隔、静止无脚步、表面推断 |
| Edge | 3 | 积累器归零、对话抑制、空转循环 |
| Failure | 3 | 无 AudioManager、未知场景、表面回退 |

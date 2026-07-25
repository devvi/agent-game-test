# PRD: Mini Walker 3D场景（地板+墙壁）

> **Issue:** #270
> **标签:** enhancement, workflow/research, depth/light, priority/high, estimate/small, version/mvp
> **Agent:** game-research-agent
> **日期:** 2026-07-26

---

## 1. 问题定义

### 当前状态

项目 `agent-game-test` 目前是一个干净的 workflow 框架骨架，没有任何实际的游戏代码、场景或资源文件。Mini Walker 项目尚未开始，没有可运行的 3D 世界。

- `project.godot` 中存在最小配置（引擎名、渲染器设为 gl_compatibility）
- 没有 `scenes/` 目录——没有任何场景文件
- 没有 `gdscripts/` 目录——没有任何 GDScript 文件
- `run/main_scene` 为空——项目没有任何主场景

### 预期行为

Mini Walker 项目的第一个可交付物是一个基础 3D 场景，包含：

- 一个地板（StaticBody3D + CollisionShape3D），角色可以站立
- 四面墙壁（StaticBody3D + CollisionShape3D），封闭空间边界
- 场景结构清晰，节点层次分明
- 场景能在 Godot headless 模式下加载无错误

### 用户场景

1. **开发启动：** 开发者在 Godot 4.7 中打开项目 → 打开 `mini_world.tscn` → 看到地板和四面墙壁组成的封闭 3D 空间
2. **CI 验证：** CI 容器运行 `godot --headless --check-only` → 场景通过引擎验证无错误
3. **后续扩展基础：** Plan/Implement 阶段以此为起点，添加角色控制器、灯光和更多 3D 元素

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 地板（StaticBody3D + BoxShape3D） | 角色/玩家控制器 |
| 四面墙壁（StaticBody3D + BoxShape3D） | 光照和灯光系统 |
| 基础 GDScript 脚本（mini_world.gd） | 材质和纹理 |
| Godot headless 兼容性 | 碰撞层和物理掩码配置 |
| 干净的节点层次结构 | UI/HUD 元素 |
| | 场景过渡和加载系统 |

---

## 2. 设计意图

### 为什么是现在

Mini Walker 是一个全新的项目。#270 是整个游戏的第一个 Issue，定义了基础 3D 空间。没有这个场景，后续所有开发（角色控制、物理、交互、AI）都无从展开。

### 设计原则

1. **最小可行场景：** 该场景仅提供封闭空间所需的几何体。不添加光照、材质、纹理或其他装饰性元素——这些由后续 Issue 处理。
2. **引擎兼容性：** 使用 `gl_compatibility` 渲染方法（已在 project.godot 中配置）。必须在 Godot headless 模式下无错误加载。
3. **命名一致性：** 遵循 Godot 4.x 最佳实践——节点名使用 PascalCase，文件使用 snake_case。
4. **可扩展性：** 场景结构应便于未来添加子节点（角色出生点、灯光、触发器、装饰物）。

### 先前约束

- `project.godot` 已将 `rendering_method` 设为 `gl_compatibility`——场景不能依赖仅 Forward+ 可用的功能（SSAO、阴影、高级光照）
- 这是 MVP 版本的一部分——场景必须保持最小规模和简单性

---

## 3. 影响分析

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `scenes/mini_world.tscn` | Godot 场景 | 包含地板和墙壁的 3D 世界场景 |
| `gdscripts/mini_world.gd` | GDScript | 为 `mini_world.tscn` 场景根节点附加的脚本 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `project.godot` | 将 `run/main_scene` 设为 `"res://scenes/mini_world.tscn"`，将 `gdscripts/` 添加到导入路径（如需要） |

### 数据流

```
MiniWorld（Node3D） ─── 根节点（附加 mini_world.gd）
├── Floor（StaticBody3D） ─── 地板碰撞体
│   └── CollisionShape3D ─── shape = BoxShape3D
├── Wall_North（StaticBody3D） ─── 北墙碰撞体
│   └── CollisionShape3D ─── shape = BoxShape3D
├── Wall_South（StaticBody3D） ─── 南墙碰撞体
│   └── CollisionShape3D ─── shape = BoxShape3D
├── Wall_East（StaticBody3D） ─── 东墙碰撞体
│   └── CollisionShape3D ─── shape = BoxShape3D
└── Wall_West（StaticBody3D） ─── 西墙碰撞体
    └── CollisionShape3D ─── shape = BoxShape3D
```

### 文档更新

- 无需更新现有文档——这是项目的第一个特性

---

## 4. 方案对比

| 方案 | 描述 | 优点 | 缺点 | 难度 |
|------|------|------|------|------|
| **A：内联物理节点（推荐）** | 在 TSCN 文件内直接使用 `[sub_resource]` 添加 StaticBody3D + CollisionShape3D | 零外部依赖，单一文件，易于理解，最易于 headless 验证 | TSCN 文件稍长 | 低 |
| **B：从 PackedScene 实例化** | 创建独立的 floor.tscn / wall.tscn，在 mini_world.tscn 中实例化 | 组件可复用，地板/墙壁可单独编辑 | 过多文件（每个简单几何体一个场景），无需复用 | 低 |
| **C：全代码生成** | 在 `_ready()` 中用 GDScript `BoxShape3D.new()` 和 `StaticBody3D.new()` 创建 | 灵活，参数可配置 | 编辑器不可见，不能可视化编辑，违反预期场景结构 | 中 |

### 推荐：方案 A

对于 MVP 场景，内联物理节点是最简洁的方法：

- 将 BoxShape3D 定义为 `[sub_resource]`，在 StaticBody3D 的 CollisionShape3D 子节点中引用
- 在 `mini_world.gd` 中添加 `extends Node3D` 作为场景根
- 脚本当前只需声明 `extends Node3D`——未来将添加设置逻辑

### 场景尺寸建议

| 元素 | 尺寸 | 位置 | 说明 |
|------|------|------|------|
| 地板 | 10×0.2×10 | (0, -0.1, 0) | 顶部表面在 y=0 处平整 |
| 墙壁 | 10×3×0.2 | 见下方 | 内高 2.9 单位 |

**墙壁位置：**
- 北墙：(0, 1.5, -5) — Z 负向
- 南墙：(0, 1.5, 5) — Z 正向
- 东墙：(5, 1.5, 0) — X 正向
- 西墙：(-5, 1.5, 0) — X 负向

---

## 5. 边界条件与验收标准

### 正常路径

1. 使用 `scenes/mini_world.tscn` 创建新场景
2. 场景根类型为 `Node3D`，附加 `gdscripts/mini_world.gd`
3. 包含 5 个 StaticBody3D 子节点：1 个地板 + 4 面墙壁
4. 每个 StaticBody3D 都有一个 CollisionShape3D 子节点
5. `CollisionShape3D.shape` 引用 BoxShape3D SubResource
6. 场景在 `project.godot` 中注册为主场景：`run/main_scene="res://scenes/mini_world.tscn"`
7. `godot --headless --check-only` 通过
8. `godot --headless` 加载场景时不产生错误

### 边缘情况

| 场景 | 预期行为 |
|------|---------|
| 从脚本加载场景 | `ResourceLoader.load("res://scenes/mini_world.tscn")` 返回有效 PackedScene |
| 在 headless 模式下实例化 | `PackedScene.instantiate()` 成功，节点树包含所有 5 个 StaticBody3D |
| 无子场景依赖 | 场景仅依赖内置资源——无 ext_resource 引用 |
| load_steps 计数 | `load_steps` 准确，匹配 sub_resource + node 数量 |

### 失败路径

| 失败场景 | 错误表现 | 根因 |
|---------|---------|------|
| load_steps 不匹配 | 解析错误 | 添加 sub_resource 后忘记更新 `load_steps` |
| Color() 使用 3 参数 | 解析错误 | TSCN 格式中 Color() 需要 4 个参数（RGBA） |
| sub_resource 在 [node] 之后 | 解析错误 | 所有 `[sub_resource]` 块必须出现在第一个 `[node]` 之前 |
| 缺少 CollisionShape3D.shape | 运行时 `Null instance` 错误 | 子节点未设置 shape 属性 |

### 验收标准

- [ ] `scenes/mini_world.tscn` 存在且内容有效
- [ ] 场景包含 1 个 StaticBody3D 地板 + CollisionShape3D（BoxShape3D）
- [ ] 场景包含 4 面墙壁（每个 StaticBody3D + CollisionShape3D）
- [ ] `godot --headless --check-only` 退出码为 0
- [ ] 场景在 Godot headless 模式下加载无错误

---

## 8. 延续上下文（Plan Agent 交接）

### 当前系统状态

- `project.godot` 是默认工作流框架骨架，未注册主场景
- 项目根目录下没有 `scenes/` 或 `gdscripts/` 目录
- `rendering_method` 设为 `gl_compatibility`

### 实施注意事项

1. **TSCN 格式要求：** 创建 `.tscn` 文件时使用 `format=3` 文本格式。使用内联 `[sub_resource type="BoxShape3D" id="..."]` 定义碰撞形状——不要引用外部资源。
2. **load_steps 管理：** `[gd_scene load_steps=N]` 必须等于 sub_resource 块的数量（+ 任何 ext_resource，此场景无）。对于 5 个形状，`load_steps=6`（1 个 gd_scene 头 + 5 个 sub_resource）。
3. **形状标识符：** 每个 BoxShape3D 使用唯一的 SubResource 标识符（如 `BoxShape_floor`、`BoxShape_wall_north`），避免名称冲突。
4. **物理配置：** StaticBody3D 使用默认物理属性——无需设置层/掩码/重量。碰撞体按中心位置排列。
5. **GDScript：** `mini_world.gd` 最小脚本—`extends Node3D` 加一个空 `_ready()` 函数。未来将在此处添加玩家生成、世界初始化等逻辑。
6. **Headless 验证：** 创建后运行：
   ```bash
   cd /path/to/project
   godot --headless --check-only
   echo "Exit: $?"
   ```

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| TSCN 格式错误导致解析失败 | 中 | 高（场景无法加载） | 实施后立即用 headless 模式验证 |
| load_steps 忘记更新 | 高 | 高 | 计数 sub_resource 块，在头中精确设置 |
| 碰撞体位置/尺寸不对齐 | 低 | 中（地板/墙壁之间有空隙） | 壁厚 0.2，确保角落完美相交 |
| Godot 版本差异 | 低 | 中 | 确认 Godot 4.7 兼容性，使用基本节点类型 |

### 下一步

Plan Agent 将使用此 PRD 创建包含详细节点结构、TSCN 代码段和测试案例描述的 DESIGN 文档。Implement Agent 将创建实际的 `mini_world.tscn` 和 `mini_world.gd` 文件。

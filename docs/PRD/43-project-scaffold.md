# Research: Project Scaffold — CRPG 基础框架

> Parent Issue: #43
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

当前项目仅有最基础的 Hello World 骨架：

- `main.gd` — 输出 "Hello World"，挂在一个简单的 Label 节点上
- `game_manager.gd` — 一个简单的 Autoload，只有 `game_started` 布尔变量
- `main.tscn` — 包含一个 Label，显示 "Hello, Godot!"
- 无 3D 场景、无输入处理、无对话引擎占位、无 UI 框架

### Expected Behavior

建立一个符合 **CRPG 基础框架** 的 Godot 4.7.1 项目，具备：

- 合理的场景树结构（3D 根场景 + UI 层分离）
- Autoload 单例体系：GameState（希望/绝望系统），预留对话引擎、UI 管理等插槽
- 输入处理（键盘响应）
- 基本的 3D 测试场景（显示 3D 文字标签并响应键盘输入）
- 遵循 macOS/Linux 的最佳实践

### User Scenarios

- **Scenario A（开发起点）：** 开发者需要加载项目后立即看到可运行的 3D 场景，确认引擎和环境配置正确
- **Scenario B（功能地基）：** 后续所有功能（对话系统、UI、角色控制）都依赖本脚手架的基础架构
- **Frequency:** 一次搭建，长期使用。脚手架完成后所有后续 Issue 在此基础上增量开发

---

## 2. Design Intent

### Why Does Current Behavior Exist?

项目还处于初始状态，尚未搭建任何框架。当前的 Hello World 仅用于验证 Godot 引擎和 CI 环境是否正常。

### Why Change Now?

这是系统开发的第一个功能 Issue — 所有后续功能都依赖此基础架构。需要立即建立：

1. 场景树结构和代码组织规范
2. 全局状态管理（GameState 单例）
3. 输入处理管道
4. 对话引擎和 UI 的占位/插槽

### Previous Constraints

- **引擎版本：** Godot 4.7.1（GDScript 2.0，静态类型）
- **平台要求：** macOS / Linux 双平台兼容
- **代码规范：** 已定义于 `docs/GAME_DESIGN/03-GODOT-SETUP.md`
  - 静态类型 GDScript (`@export var`, `func foo() -> void`)
  - `snake_case` 文件名，`PascalCase` 节点名
  - Autoload 使用 `PascalCase`（如 `GameState`, `DialogueEngine`）
- **目录结构：** `gdscripts/` → 源码，`scenes/` → .tscn 文件，`assets/` → 资源

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/game_state.gd` | GameState | **新建** — Autoload 单例，包含 hope/despair 变量和信号 |
| `gdscripts/input_handler.gd` | Input | **新建** — 输入处理脚本 |
| `gdscripts/dialogue_engine.gd` | Dialogue | **新建** — 占位脚本（空实现，预留接口） |
| `gdscripts/ui_manager.gd` | UI | **新建** — 占位脚本（空实现，预留接口） |
| `scenes/main_scene.tscn` | Scene | **新建** — 3D 根场景，包含 3D 文字标签和输入响应 |
| `project.godot` | Config | **修改** — 添加 Autoload 注册、输入映射 |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/game_manager.gd` | GameManager | 可能需要与新 GameState 整合或重构 |
| `gdscripts/main.gd` | Main | 现有入口脚本需要适配新框架 |
| `scenes/main.tscn` | Scene | 现有 2D 场景保留或整合 |

### Data Flow Impact

- **GameState** 作为全局单例，所有系统通过它访问 hope/despair 值
- **InputHandler** 捕获键盘事件，转换为游戏动作（如 UI 导航、测试场景交互）
- **DialogueEngine**（占位）预留信号接口，后续对话系统接入
- **UIManager**（占位）预留 CanvasLayer 层，后续 UI 组件挂载

### Documents to Update

- [ ] `docs/GAME_DESIGN/03-GODOT-SETUP.md` — 更新项目结构文档，补充 Autoload 列表和场景树规范
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md` — 更新游戏概述，记录脚手架已完成
- [ ] `README.md` — 更新项目说明

---

## 4. Solution Comparison

### Approach A: 紧耦合单 Autoload

- **Description:** 只创建一个 `GameState` Autoload，将所有全局状态（hope/despair、对话状态、UI 状态）放在一个文件里。对话和 UI 作为 GameState 的内部方法或子模块
- **Pros:**
  - 文件少，简单直接
  - 上手快，适合小项目
- **Cons:**
  - 违背单一职责原则
  - 后续对话/UI系统复杂化后，GameState 会膨胀成 God Class
  - 不利于多人并行开发
- **Risk:** Medium — 短期可行，长期重构成本高
- **Effort:** 小（~30 分钟）

### Approach B: 模块化多 Autoload（推荐）

- **Description:** 建立 4 个 Autoload 单例体系：
  1. `GameState` — 核心游戏状态（hope/despair + 信号），作为全局状态中心
  2. `DialogueEngine` — 对话引擎占位，预留 `start_dialogue()`, `end_dialogue()` 信号接口
  3. `UIManager` — UI 管理占位，预留 CanvasLayer 层
  4. `InputHandler` — 集中式输入处理
- **Pros:**
  - 清晰的责任边界
  - 每个单例可独立测试和迭代
  - 后续功能可无侵入地接入预留接口
  - 符合 Godot Autoload 最佳实践
- **Cons:**
  - 初始文件数稍多
  - 需要设计好跨 Autoload 通信机制
- **Risk:** Low — 标准模式，行业验证
- **Effort:** 中（~1 小时）

### Approach C: 无 Autoload + 依赖注入

- **Description:** 不使用 Autoload，而是通过场景树手动传递 GameState 引用（依赖注入模式）
- **Pros:**
  - 更好的测试隔离性
  - 不受全局状态隐式依赖困扰
- **Cons:**
  - 脚手架阶段过度设计
  - 手动传递引用增加样板代码
  - 与 Godot 生态常见实践不符
- **Risk:** Low（技术上可行）但 Effort 高
- **Effort:** 大（~2 小时）

### Recommendation

→ **Approach B** 因为：

- 模块化设计为后续所有功能提供了清晰的扩展点
- 符合 `docs/GAME_DESIGN/03-GODOT-SETUP.md` 中 "Autoload 用 PascalCase" 的规范
- 对话引擎和 UI 的占位脚本让后续 Issue 可以直接基于预留接口工作，无需重构
- 是 CRPG 框架项目中经过验证的标准模式

---

## 5. Boundary Conditions & Acceptance Criteria

### 验收条件（来自 Issue #43）

- [ ] **AC1:** Project opens without errors on Godot 4.7.1
- [ ] **AC2:** Autoload `GameState.gd` with basic hope/despair variable and signal
- [ ] **AC3:** Default scene displays a 3D text label and responds to keyboard input

### Normal Path

1. 打开 Godot 4.7.1 → 导入项目 → 无错误
2. 运行默认场景 → 显示 3D 文字标签（如 "CRPG" 或 "Press SPACE to start"）
3. 按下键盘（如 SPACE / Enter）→ 文字变化或打印日志，证明输入处理正常工作
4. 在代码中访问 `GameState.hope` 和 `GameState.despair` → 有类型定义，可读写
5. `GameState` 发出 hope/despair 变化信号 → 其他系统可连接

### Edge Cases

1. **Godot 版本不匹配：** 项目用 4.7.1 特有 API → 低版本打开会报错。确保只用 4.7.x 兼容 API
2. **平台路径差异：** macOS 文件系统不区分大小写 vs Linux 区分 → 确保 import 路径大小写一致
3. **3D 渲染兼容：** macOS (Metal) vs Linux (Vulkan) → 使用标准 3D 节点，避免平台特定渲染特性
4. **键盘布局差异：** 不同键盘的键位映射 → 使用 `KEY_*` 常量而非硬编码字符

### Failure Paths

1. **Autoload 循环依赖：** 两个 Autoload 互相引用 → Godot 启动崩溃。设计时确保依赖方向单向（GameState → 其他，其他不反向依赖 GameState）
2. **3D 场景无默认光照：** 只有 3D 文字标签但没有光源 → 文字不可见。确保添加 `DirectionalLight3D` 或 `OmniLight3D`

> 以上直接成为 Plan 阶段的测试用例骨架。

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Godot 4.7.1 引擎 | 已安装 | Low |
| 项目目录结构（`gdscripts/`, `scenes/`, `assets/`） | 已存在 | Low |
| 现有 `project.godot` 配置 | 存在但需修改 | Low |

### Blocks

| Future Work | Priority |
|-------------|----------|
| 对话系统（Dialogue System） | 高 |
| UI 系统（HUD, 菜单） | 高 |
| 玩家控制器（Player Controller） | 高 |
| 状态机（State Machine） | 中 |
| 其他所有 CRPG 功能 | 依赖此基础设施 |

### Preparation Needed

- [ ] 确认本地 Godot 4.7.1 可正常运行
- [ ] 确认 `project.godot` 配置了正确的渲染器（Forward+ / Mobile / Compatibility）
- [ ] 确认 `project.godot` 已配置输入映射（Input Map）用于键盘输入

---

## 7. Spike / Experiment (Optional)

> depth/standard — 本节可选。本 Issue 为基础设施搭建，设计意图明确，无需 spike。

---

## 8. Continuation Context

> *本节是 activeForm 向下一 agent（plan → implement）的交接。*

当前项目状态：`main` 分支上有最小 Hello World 项目（`main.gd` + `game_manager.gd` + `main.tscn`）。`game_manager.gd` 已注册为 Autoload，但状态管理非常基础（仅 `game_started: bool`）。

推荐的 Approach B 将建立 4 个 Autoload：
- `GameState` — 核心 hope/despair 系统，带 `hope_changed` 和 `despair_changed` 信号
- `DialogueEngine` — Autoload 占位，预留空方法
- `UIManager` — Autoload 占位，创建 CanvasLayer 根节点
- `InputHandler` — 集中式键盘输入，连接到 GameState

新默认场景 `scenes/main_scene.tscn` 将是一个 3D 场景，包含：
- `Node3D` 根节点
- `Label3D` 子节点显示文字
- `DirectionalLight3D` 确保可见
- 连接 `InputHandler` 信号响应键盘

现有 2D `main.tscn` 和 `main.gd` 保留不动或整合到新框架中。主要风险是 Autoload 间的加载顺序 — `GameState` 必须在其他 Autoload 之前加载，因为 `DialogueEngine` 和 `UIManager` 依赖 `GameState` 的状态。

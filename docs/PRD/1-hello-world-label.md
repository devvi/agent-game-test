# Research: 在屏幕上显示Hello World的Label

> Parent Issue: #1
> Agent: game-research-agent
> Date: 2026-07-20

---

## 1. Problem Definition

### Current Behavior
游戏目前启动后，`scenes/main.tscn` 中有一个静态的 Label 显示 "Hello, Godot!"，由场景文件直接设置。`gdscripts/main.gd` 仅打印 "Main scene ready."。没有 GDScript 动态控制文字显示的逻辑。

### Expected Behavior
游戏启动后，主屏幕上应显示醒目的 "Hello World" 文字，通过 GDScript 在 `_ready()` 中动态设置 Label 的 `text` 属性。文字应居中显示，字体大小适中。

### User Scenarios
- **Scenario A:** 玩家启动游戏，立即看到 "Hello World" 欢迎语
- **Scenario B:** 开发者查看代码，能理解 Label 的文字如何通过 GDScript 控制和修改
- **Frequency:** 每次启动都显示

---

## 2. Design Intent (Feature)

### Why Do We Need This?
作为项目的第一个功能，验证完整的 agent workflow（research → plan → implement → review）在 Godot 4.7 项目上能端到端跑通。同时建立一个简单但完整的"GDScript 控制 UI"模式，为后续功能（如分数显示、菜单等）奠定基础。

### Why Change Now?
这是项目起点，需要从静态场景过渡到代码驱动的 UI 交互。

### Previous Constraints
- 项目使用的是 Godot 4.7 / GDScript 2.0
- Label 节点已在 `scenes/main.tscn` 中存在
- Autoload `GameManager` 已注册但尚未被使用

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/main.gd` | Main scene script | Add dynamic Label text control |
| `scenes/main.tscn` | Main scene | Minor adjustment (optional) |
| `tests/run_tests.gd` | Test runner | Add Hello World related test |

### Indirectly Affected Modules
| File | Module | Why Affected |
|------|--------|--------------|
| None | - | This is a self-contained feature |

### Data Flow Impact
- `GameManager` (autoload) → `Main.gd` reads game state → sets `Label.text`
- 非常简单的单向数据流

### Documents to Update
- [x] `docs/PRD/1-hello-world-label.md` (本文档)
- [ ] `docs/DESIGN/1-hello-world-label.md` (Plan 阶段创建)

---

## 4. Solution Comparison

### Approach A: Direct GDScript Label Assignment
- **Description:** 在 `main.gd` 的 `_ready()` 中通过 `$Label.text = "Hello World"` 直接设置文字
- **Pros:** 最简单，一行代码，零复杂度
- **Cons:** 没有抽象层，扩展性差
- **Risk:** Low — Godot 标准做法
- **Effort:** ~5 行代码

### Approach B: GameManager-Driven Label
- **Description:** 通过 Autoload `GameManager` 发射信号，`main.gd` 连接信号并更新 Label
- **Pros:** 遵循 MVC 模式，易于扩展到显示分数/生命值等
- **Cons:** 对于 Hello World 来说过度工程化
- **Risk:** Low — 但增加了不必要的复杂度
- **Effort:** ~20 行代码

### Approach C: 自定义 UI 场景
- **Description:** 创建独立的 UI 场景 `scenes/hello_world.tscn`，用 Control 节点布局
- **Pros:** 最灵活，UI 与游戏逻辑完全解耦
- **Cons:** 对 Hello World 来说太过复杂
- **Risk:** Low — 但增加文件数量
- **Effort:** ~3 个文件

### Recommendation
→ **Approach A** because: 这是项目的起点功能，目的是验证 workflow 而非构建复杂系统。直接 GDScript 赋值满足所有验收标准，且为后续扩展留下了清晰的扩展点（只需要将 `$Label.text = xxx` 替换为更复杂的 UI 逻辑）。

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path
1. 游戏启动 → `Main.gd._ready()` 被调用
2. `$Label.text = "Hello World"` 执行
3. 屏幕中央显示 "Hello World"（水平居中，字体大小 32+）

### Edge Cases
1. **Label 不存在:** 如果场景中没有 Label 节点，`$Label` 会返回 null，调用 `.text` 会报错。但当前场景已有 Label，且 Plan 阶段不会删除它。
2. **多语言支持:** 当前仅显示英文 "Hello World"；后续可扩展。
3. **游戏窗口缩放:** Label 水平对齐为 `horizontal_alignment = 1`（中心），窗口缩放时文字仍居中。

### Failure Paths
1. **场景加载失败:** `main.tscn` 无法加载时，Godot 会在编辑器中报错，运行时无显示。这不在本 Issue 范围内。

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On
| Dependency | Status | Risk |
|------------|--------|------|
| Godot 4.7 场景系统 | Stable | Low |
| GDScript 2.0 Label API | Stable | Low |

### Blocks
| Future Work | Priority |
|-------------|----------|
| 分数/状态显示 UI | Medium |
| 游戏菜单系统 | Low |

### Preparation Needed
- [x] 现有 `scenes/main.tscn` 已包含 Label 节点

---

## 7. Continuation Context

This is the starting feature for the agent-game-test Godot project. The main scene (`scenes/main.tscn`) already contains a Label node showing "Hello, Godot!" from the scene file directly. The game autoload (`gdscripts/game_manager.gd`) is registered but unused.

The proposed approach (Approach A) builds on the existing scene structure: `main.gd` will access the Label node via the `$Label` shorthand and set its `text` property in `_ready()`. This is the simplest GDScript pattern for UI text control and establishes a clear pattern for future UI features.

The main risk is minimal — the Label node already exists in the scene with proper positioning (horizontal_alignment = 1, centered). The implement phase will change approximately 1 file (main.gd, +2-3 lines) and add 1 test case in `tests/run_tests.gd`.

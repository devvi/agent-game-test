# 03. Godot 项目设置

> Godot 4.7.1 配置和项目约定。

## 3.1 项目结构

```
gdscripts/      → GDScript 源码
scenes/         → .tscn 场景文件
assets/         → 资源文件（导入到 .godot/）
tests/          → GDScript 单元测试
exports/        → 构建产物输出目录
```

## 3.2 代码规范

- 使用 **静态类型 GDScript** (`var x: int`, `func foo() -> void`)
- 文件名用 snake_case
- 节点路径用 PascalCase (Main, GameUI, WorldLabel)
- Autoload 用 PascalCase (GameManager, GameState)

## 3.3 测试

- 使用 Godot 内置的 SceneTree 测试框架 (`extends SceneTree`)
- 测试文件放在 `tests/` 目录
- CI 通过 `godot --headless --script tests/run_tests.gd` 执行
- 新 feature 的测试在 `run_tests.gd` 中集成，同时提供独立 `test_*.gd` 文件

## 3.4 Autoload 体系

| Singleton | 文件 | 职责 |
|-----------|------|------|
| GameManager | `gdscripts/game_manager.gd` | 生命周期/游戏流程管理，初始化 banner 输出 |
| GameState | `gdscripts/game_state.gd` | CRPG 核心状态管理：hope (0-100)、despair (0-100)，信号驱动变更通知 |

**加载顺序：** GameManager → GameState。GameState 通过 `state_changed(state: Dictionary)` 信号广播状态变化。

### GameState API

```gdscript
signal state_changed(state: Dictionary)   # 状态变更时触发
func apply_state(delta_hope: int, delta_despair: int) -> void  # 应用增量（自动 clamp 至 [0,100]）
func get_state() -> Dictionary             # 返回 {hope, despair}
func reset() -> void                       # 重置为 hope=100, despair=0
```

## 3.5 场景体系

入口场景 `scenes/main.tscn` 使用 3D 层级结构：

```
Main (Node3D)                ← 3D 场景根节点
├─ WorldLabel (Label3D)      ← 3D 文本，绑定 GameState，响应键盘输入
├─ Camera3D                  ← 透视相机，位置 (0, 2, 5)
├─ UI (CanvasLayer)          ← HUD/UI 覆盖层
│  └─ Overlay (Control)      ← 占位节点 — 供下游 HUD 系统使用
└─ Dialogue (CanvasLayer)    ← 对话覆盖层（渲染在 UI 之上）
   └─ Panel (Control)        ← 占位节点 — 供下游对话引擎使用
```

**CanvasLayer 职责划分：** UI 层渲染在 3D 世界之上，Dialogue 层渲染在 UI 之上，确保对话面板不会被 HUD 遮挡。

## 3.6 输入映射

使用 Godot 内置的 `ui_*` 输入动作，无需自定义输入映射：

| 动作 | 按键 | 效果 |
|------|------|------|
| `ui_up` | ↑ / W | hope += 5 |
| `ui_down` | ↓ / S | hope -= 5 |
| `ui_right` | → / D | despair -= 5 |
| `ui_left` | ← / A | despair += 5 |
| `ui_accept` | Enter / Space | 重置 GameState 为默认值 |
| `ui_cancel` | Esc | 输出暂停占位消息 |

输入在 `main.gd._input()` 中处理，通过 `is_action_pressed()` 检测。

## 3.7 导出预设

| 预设 | 平台 | 输出路径 |
|------|------|---------|
| preset.0 | Linux/X11 | `exports/agent-game-test-linux.x86_64` |
| preset.1 | macOS | `exports/agent-game-test-macos.zip` |

两个预设均使用 BPTC/S3TC/ETC1/ETC2 纹理压缩打包。

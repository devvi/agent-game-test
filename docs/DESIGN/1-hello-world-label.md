# Design: #1 — 在屏幕上显示Hello World的Label

> Parent Issue: #1
> Agent: plan-agent
> Date: 2026-07-20

---

## 1. Architecture Overview

### Core Idea
在 `gdscripts/main.gd` 的 `_ready()` 中通过 `$Label.text = "Hello World"` 动态设置 Label 文字。这是最简洁的 GDScript UI 控制模式。

### Data Flow
```
Godot Engine
  │
  ├─ scene/main.tscn 加载
  │   └─ 包含 Label 节点（已存在，水平居中）
  │
  ├─ gdscripts/main.gd._ready() 被调用
  │   └─ $Label.text = "Hello World"
  │
  └─ 屏幕显示 "Hello World"
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Label 控制方式 | `$Label` 直接引用 | 场景中 Label 是 Main 的直接子节点，`$Label` 是 Godot 标准做法 |
| 文字设置时机 | `_ready()` | Godot 生命周期中节点树就绪后最安全 |
| 文字内容 | "Hello World" | 符合 Issue 要求，清晰验证功能 |

---

## 2. Node / Scene Tree Layer 变更

**无结构性变更。** 现有的 `scenes/main.tscn` 已有 Label 节点作为 Main 的子节点，结构保持不变。

当前节点树：
```
Main (Node)
 └── Label (Label)  ← 已有，持水平居中设置
```

---

## 3. GDScript / Logic Layer 变更

### `gdscripts/main.gd` — 主场景脚本

**当前内容：**
```gdscript
extends Node

func _ready() -> void:
    print("Main scene ready.")
```

**修改后：**
```gdscript
extends Node

func _ready() -> void:
    $Label.text = "Hello World"
    print("Main scene ready.")
```

变更：
- 在 `_ready()` 开头添加 `$Label.text = "Hello World"`（+1 行）
- `$Label` 引用场景中 Label 节点（GDScript 2.0 `get_node("Label")` 的简写）
- 不影响已有的 `print()` 调用

---

## 4. Resource / Config Layer 变更

**无变更。** `project.godot` 中的 Autoload `GameManager` 继续保持注册状态但不使用。Label 的字体和颜色使用 Godot 默认主题。

---

## 5. Asset / Visual Layer 变更

**无变更。** 现有的 Label 节点已在 `scenes/main.tscn` 中设置了：
- `offset_left/top/right/bottom`: 居中定位
- `theme_override_font_sizes/font_size = 32`
- `horizontal_alignment = 1`（中心对齐）

---

## 6. Input / UI Layer 变更

**无变更。** 无新用户输入处理。

---

## 7. Test Layer 变更

### Test Structure
在 `tests/run_tests.gd` 中新增 2 个测试用例，验证 GDScript 层面 Label 控制逻辑。

**注意：** 由于 Godot `--script` 模式下没有 SceneTree，无法实例化场景来测试 `$Label` 的实际赋值。测试将验证：
1. `main.gd` 脚本可以正确加载（语法验证）
2. 简单的字符串赋值模式可正常工作

### Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| Label 文字设置 | ✅ | ✅ | ✅ |

### 测试用例描述

| # | 场景 | 输入/设置 | 预期行为 | 验证条件 |
|---|------|-----------|---------|---------|
| 1 | 正常路径 | 创建 Label 实例，设置 text 属性 | 文字正确设置 | `assert(label.text == "Hello World")` |
| 2 | 边界条件 | Label 文字为空字符串 | 不报错 | `assert(label.text == "")` |
| 3 | 边界条件 | 设置超长文字 | 不报错 | `assert(len(label.text) > 0)` |

---

## 8. Files Changed（按層匯總）

### GDScript Layer
| File | Change | Est. Lines |
|------|--------|-----------|
| `gdscripts/main.gd` | Add `$Label.text = "Hello World"` in `_ready()` | +1 |

### Test Layer
| File | Change | Est. Lines |
|------|--------|-----------|
| `tests/run_tests.gd` | Add Label text test cases | +15 |

---

## 9. Verification Checklist

- [ ] `gdscripts/main.gd` 在 `_ready()` 中设置 `$Label.text = "Hello World"`
- [ ] `godot --headless --script tests/run_tests.gd` 全部通过
- [ ] 场景中的 Label 节点保持不变
- [ ] 游戏启动后屏幕中央显示 "Hello World"
- [ ] 无回归问题

# GDD — Agent Game Test (Godot 4.7)
# 游戏设计文档索引

## 目录

| 章节 | 说明 |
|------|------|
| [01-OVERVIEW](01-OVERVIEW.md) | 游戏概述、核心玩法、设计目标 |
| [02-WORKFLOW](02-WORKFLOW.md) | Agent 工作流设计 — 开发 pipeline |
| [03-GODOT-SETUP](03-GODOT-SETUP.md) | Godot 引擎配置、场景管理、代码规范 |
| [04-RENDERING](04-RENDERING.md) | Lo-Fi 3D Text 渲染系统 — 着色器、Label3D、像素风字体 |

---

### 维护规则

- **初次建立：** 手动从代码中提取，一次写完初版
- **增量更新：** Review agent 在每次 implement PR merge 后自动写入
- **不写入 GDD 的内容：** 代码 diff、测试用例、实施阶段
- **写作风格：** 叙事体、层次编号、代码块放定义、表格放参数、段落讲意图

# 02. Agent Workflow

> 基于 Perfect Dev Agent Workflow 框架，适配 Godot 4.7 引擎。

## 2.1 Pipeline

```
Issue → Research (PRD) → Plan (DESIGN) → Implement (GDScript + Tests) → CI → Review → Merge → Release
```

## 2.2 开发环境

| 组件 | 版本 | 说明 |
|------|------|------|
| Godot | 4.7.1 | 游戏引擎 |
| GDScript | 2.0 | 静态类型 GDScript |
| Hermes Agent | latest | Agent 运行时 |
| OpenCode Serve | latest | LLM 代码生成 |

## 2.3 开发工具增强

| 工具 | 安装方式 | 用途 |
|------|---------|------|
| **opencode-godot-lsp** | `npm install -g opencode-godot-lsp` | GDScript LSP 桥接 — 自动补全、跳转定义、实时诊断 |
| **GodotPrompter** | OpenCode 插件 + Hermes skill symlink | 54 个 Godot 4.x 技能（状态机、玩家控制器、物理等） |

两者都是 OpenCode 层面的增强：
- LSP bridge 在编辑 GDScript 时提供 IDE 级智能
- GodotPrompter 在 AI 生成代码时注入 Godot 最佳实践

### GodotPrompter 技能列表

Hermes 可加载的社区技能（`skill_view('community:godot-xxx')`）：

| 类别 | 技能 |
|------|------|
| 核心 | `godot-project-setup`, `godot-code-review`, `godot-debugging`, `godot-testing` |
| 架构 | `godot-state-machine`, `godot-event-bus`, `godot-component-system`, `godot-resource-pattern` |
| 玩法 | `godot-player-controller`, `godot-ai-navigation`, `godot-inventory-system`, `godot-ability-system` |
| 渲染 | `godot-2d-essentials`, `godot-3d-essentials`, `godot-particles-vfx`, `godot-shader-basics` |
| 网络 | `godot-multiplayer-basics`, `godot-multiplayer-sync`, `godot-dedicated-server` |
| 进阶 | `godot-gdextension`, `godot-multithreading`, `godot-mobile-development` |

### Game-to-Issues

把一句游戏开发命令拆解为结构化的 GitHub Issues，审阅后批量创建。详见 `agents/skills/game-to-issues/SKILL.md`。

## 2.4 CI/CD

- 使用 GitHub Actions 运行 Godot headless 测试
- 合并到 main 后自动构建导出
- 发布到 GitHub Releases

# Agent Game Test

> 基于 **Perfect Dev Agent Workflow** 框架 + **Godot 4.7** 的游戏开发自动化测试项目。

## 快速开始

```bash
# 1. 确保 Godot 4.7 已安装
godot --version

# 2. 打开项目
godot scenes/main.tscn

# 3. 提一个 Feature Issue → workflow 自动开始开发
```

## 项目结构

```
├── project.godot           # Godot 项目配置
├── gdscripts/              # GDScript 源码
├── scenes/                 # Godot 场景
├── assets/                 # 资源文件
├── tests/                  # GDScript 测试
├── game-env/manifest.yaml  # 引擎配置
├── .github/workflows/      # CI/CD
└── docs/GAME_DESIGN/       # 游戏设计文档
```

## 技术栈

| 组件 | 版本 |
|------|------|
| Godot | 4.7 |
| GDScript | 2.0 |
| GitHub Actions | CI/CD |
| Hermes Agent | Workflow orchestration |
| OpenCode Serve | AI code generation |

## Workflow 状态

[![Workflow](https://github.com/devvi/agent-game-test/actions/workflows/opencode-review.yml/badge.svg)](https://github.com/devvi/agent-game-test/actions)

---

*Auto-initialized by Hermes Agent on 2026-07-19.*

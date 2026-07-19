# Perfect Dev Agent Workflow — Godot Edition

> 基于 **Perfect Dev Agent Workflow** 框架，使用 **Godot 4.7** 引擎的游戏开发自动化工作流。

## 项目结构

```
├── project.godot           # Godot 项目文件
├── AGENTS.md               # 本文档
├── game-env/
│   └── manifest.yaml       # 游戏环境配置 (Godot)
├── framework/              # 可复用框架代码
│   ├── ARCHITECTURE.md
│   ├── quickstart.md
│   ├── cicd/               # CI/CD 模板
│   └── templates/          # 文档模板
├── gdscripts/              # GDScript 游戏源码
├── scenes/                 # Godot 场景文件 (.tscn)
├── assets/                 # 资源文件 (图片、音效等)
├── tests/                  # 测试 (GDScript)
├── agents/
│   └── skills/             # Agent skill 文件
├── scripts/                # Workflow 确定性脚本
├── .github/
│   ├── ISSUE_TEMPLATE/     # Issue 模板
│   └── workflows/          # GitHub Actions
└── docs/
    └── GAME_DESIGN/        # 游戏设计文档
```

## Workflow 流程

```
┌─ 提 Issue ────────────────────────────────────────────────┐
│  research agent → PRD → PR → 自动合并                      │
│  plan agent → 架构设计 + 测试描述 → PR → 自动合并           │
│  implement agent → OpenCode GDScript 实现 → PR → CI → review → 合并 │
└─────────────────────────────────────────────────────────┘
```

## 标签

| Label | 阶段 | 说明 |
|-------|------|------|
| `workflow/available` | Available | Issue 等待处理 |
| `workflow/research` | Research | research agent 进行中 |
| `workflow/plan` | Plan | plan agent 进行中 |
| `workflow/implement` | Implement | implement agent 进行中 |
| `workflow/self-correct` | Fixing | CI 失败，自愈中 |
| `status/done` | Done | Issue 关闭 |

## Tech Stack

| 组件 | 用途 |
|------|------|
| Godot 4.7 | 游戏引擎 + GDScript |
| Hermes Agent | Agent 运行时 + 事件路由 |
| OpenCode Serve | LLM 代码生成引擎 |
| GitHub Issues | 任务队列 |
| GitHub Actions | CI/CD |
| GitHub Releases | 部署 |

## 快速开始

1. 确保 Godot 4.7 已安装: `godot --version`
2. 提一个 Feature Issue → workflow 自动开始
3. 或直接编辑 `gdscripts/` 和 `scenes/` 手动开发

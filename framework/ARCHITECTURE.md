# framework/ARCHITECTURE.md — Godot Edition

> 基于 Perfect Dev Agent Workflow 架构，适配 Godot 4.7。
> 详见主仓库: https://github.com/devvi/perfect-dev-agent-workflow

## 系统概述

本框架将游戏开发分解为四个 agent 阶段：
1. **Research** — 研究、PRD 生成
2. **Plan** — 架构设计、测试描述
3. **Implement** — GDScript 代码生成 (OpenCode)
4. **Review** — 代码审查、合并决策

## Godot 适配

- **源码结构**: `gdscripts/` + `scenes/` (GDScript + Godot scenes)
- **测试**: Godot headless 模式运行 `tests/run_tests.gd`
- **CI**: `chickensoft-games/setup-godot@v2` action
- **部署**: GitHub Releases (GitHub-hosted export)

## 局限性

- Godot headless 不支持所有渲染功能
- 需要手动配置 export preset
- OpenCode 生成 GDScript 的质量取决于模型能力

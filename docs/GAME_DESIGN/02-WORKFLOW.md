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

## 2.3 CI/CD

- 使用 GitHub Actions 运行 Godot headless 测试
- 合并到 main 后自动构建导出
- 发布到 GitHub Releases

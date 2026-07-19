# 03. Godot 项目设置

> Godot 4.7.1 配置和项目约定。

## 3.1 项目结构

```
gdscripts/      → GDScript 源码
scenes/         → .tscn 场景文件
assets/         → 资源文件（导入到 .godot/）
tests/          → GDScript 单元测试
```

## 3.2 代码规范

- 使用 **静态类型 GDScript** (`var x: int`, `func foo() -> void`)
- 文件名用 snake_case
- 节点路径用 PascalCase (Main, GameUI)
- Autoload 用 PascalCase (GameManager, AudioManager)

## 3.3 测试

- 使用 Godot 内置的 GDScriptUnitTest
- 或集成 GUT (Godot Unit Testing) 框架
- 测试文件放在 `tests/` 目录

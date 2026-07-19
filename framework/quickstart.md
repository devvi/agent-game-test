# Quickstart — Godot Edition

> Godot 4.7 + Agent Workflow 30 分钟上手。

## Step 1: 配置项目

```bash
# 确保 Godot 已安装
godot --version

# 打开项目进行首次编辑（会生成 .godot/ 目录）
godot scenes/main.tscn
```

## Step 2: 设置 GitHub + Hermes

详见主仓库: https://github.com/devvi/perfect-dev-agent-workflow

## Step 3: 提 Issue

用模板创建 Feature Issue → workflow 自动开始。

## GDScript 风格指南

```gdscript
# Godot 4 GDScript 规范:
# 1. 使用静态类型
var health: int = 100

# 2. 函数标注返回类型
func take_damage(amount: int) -> void:
    health -= amount

# 3. 使用 @onready 和 @export
@export var speed: float = 300.0
@onready var sprite: Sprite2D = $Sprite2D
```

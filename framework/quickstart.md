# Quickstart — Godot Edition

> Godot 4.7 + Agent Workflow 30 分钟上手。仓库: https://github.com/devvi/agent-game-test

## Step 1: 配置项目

```bash
# 确保 Godot 已安装
godot --version

# 打开当前游戏（mini-pong）进行首次编辑（会生成 .godot/ 目录）
godot --path mini-pong/
```

## Step 2: 提 Issue 跑 workflow

用 `feature-request.yml` 模板创建 Issue → workflow 自动开始：

```
research agent → PRD → 自动合并 → plan agent → DESIGN → 自动合并
→ implement agent → 代码 + 测试 → CI → review agent（本地 E2E + 截图）→ merge
```

控制命令：`/workflow status|pause|resume|hours ...`（或自然语言"暂停 workflow"）。

## Step 3: 本地 E2E 验证（review agent 的截图证据）

```bash
scripts/run-e2e-review.sh <PR_NUM>     # worktree + L0-L3 + 真实渲染截图 + 证据 comment
```

- 游戏自持 shot plan: `mini-pong/e2e_shots.json`（截图剧本：状态机驱动 + press 注入 + assert_text）
- 4 重防伪断言: 非黑 / 色数 / 主题色 / 帧间差异（`scripts/e2e/analyze_bmp.py`）
- 截图通道: Godot 进程内截图（显示睡眠时系统截图全黑, 实测）

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

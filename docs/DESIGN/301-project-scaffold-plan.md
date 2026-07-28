# DESIGN: Mini Pong Project Scaffold

> **Issue:** #301
> **Phase:** Plan
> **日期:** 2026-07-28
> **状态:** Draft → Implement

---

## 1. 概述

在 `agent-game-test` 根项目下创建 `mini-pong/` 独立子项目骨架。Mini Pong 使用独立的 `project.godot` 配置（2D Forward+ 渲染器，glow/bloom 开启），包含标准子目录结构、WorldEnvironment 场景，以及 CI 编译验证步骤。

## 2. 目录结构

```
agent-game-test/
├── mini-pong/
│   ├── project.godot               ← 独立配置 (2D Forward+, glow/bloom)
│   ├── scenes/
│   │   └── world_environment.tscn  ← WorldEnvironment (glow 强度 0.6)
│   ├── gdscripts/                  ← (空，后续填充)
│   ├── assets/                     ← (空，后续填充)
│   └── tests/                      ← (空，后续填充)
└── .github/workflows/
    └── opencode-review.yml         ← + Mini Pong 编译步骤
```

## 3. 文件规范

### 3.1 `mini-pong/project.godot`

使用 Godot 4.x ConfigFile 文本格式（`[section]`/`key=value`）：

```ini
[application]
config/name="Mini Pong"
config/description="A classic Pong game implementation"
run/main_scene=""

[rendering]
renderer/rendering_method="forward_plus"
environment/glow_enabled=true
```

- **renderer/rendering_method**: `forward_plus`（区别于根项目的 `gl_compatibility`）
- **environment/glow_enabled**: `true`（启用 glow/bloom 效果）
- **run/main_scene**: 空字符串（后续 Issue 设置）

### 3.2 `mini-pong/scenes/world_environment.tscn`

使用 Godot 4.x TSCN 文本格式（`format=3`）：

- 根节点: `WorldEnvironment` (type: `WorldEnvironment`)
- 环境资源: 内联 `[sub_resource type="Environment"]`
- **glow_enabled**: `true`
- **glow_intensity**: `0.6`

### 3.3 CI 步骤

在 `opencode-review.yml` 的 `Validate sub-project scaffold` 步骤之后添加 `Validate Mini Pong scaffold` 步骤：

```yaml
- name: Validate Mini Pong scaffold
  id: mini-pong
  run: |
    if [ -d mini-pong ]; then
      godot --path mini-pong/ --headless --quit > mini-pong-output.log 2>&1
      echo "exit_code=$?" >> $GITHUB_OUTPUT
    else
      echo "SKIP: mini-pong/ not found"
      echo "exit_code=0" >> $GITHUB_OUTPUT
    fi
  continue-on-error: true
```

更新 test gate 条件，加入 `steps.mini-pong.outputs.exit_code`。

## 4. 验收标准

- [ ] `mini-pong/` 目录存在
- [ ] `mini-pong/project.godot` 存在，配置使用 2D Forward+ 渲染器，glow/bloom 开启
- [ ] `mini-pong/scenes/`、`mini-pong/gdscripts/`、`mini-pong/assets/`、`mini-pong/tests/` 目录存在
- [ ] `mini-pong/scenes/world_environment.tscn` 存在，glow 强度 0.6
- [ ] CI 中增加了 `godot --path mini-pong/ --headless --quit` 步骤
- [ ] `godot --path mini-pong/ --headless --quit` 退出码为 0

## 5. 实施步骤

1. `mkdir -p mini-pong/{scenes,gdscripts,assets,tests}`
2. 创建 `mini-pong/project.godot`
3. 创建 `mini-pong/scenes/world_environment.tscn`
4. 在 `opencode-review.yml` 中添加 Mini Pong 验证步骤
5. 提交到分支 `plan/301-project-scaffold`
6. 创建 PR → 自动合并

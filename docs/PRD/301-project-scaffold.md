# PRD: [Scaffold] 项目骨架 — 目录结构与 CI

> **Issue:** #301
> **标签:** enhancement, workflow/research, depth/light, priority/critical, version/mvp, estimate/small
> **Agent:** game-research-agent
> **日期:** 2026-07-28

---

## 1. 问题定义

### 当前状态

项目 `agent-game-test` 的根目录下已有一个 `project.godot`（2D, gl_compatibility 渲染器），以及若干顶层目录（`scenes/`, `gdscripts/`）。但所有文件都属于根项目（贪吃蛇/Metroidvania Snake 实验）。Mini Pong 作为独立子项目还未存在。

- 没有 `mini-pong/` 目录结构
- 没有针对 Mini Pong 的独立 `project.godot` 配置（2D Forward+ 渲染器，glow/bloom 开启）
- 没有 Mini Pong 专用的 `scenes/`、`gdscripts/`、`assets/`、`tests/` 子目录
- 没有 `world_environment.tscn` 环境场景（glow 强度 0.6）
- CI workflow（`opencode-review.yml`）已有 `rainy-night-prometheus` 子项目验证，但缺少 Mini Pong 编译步骤

### 预期行为

在项目根目录下创建 `mini-pong/`，作为 Mini Pong 游戏的独立子项目：

- `mini-pong/project.godot`：2D Forward+ 渲染器，开启 glow/bloom
- `mini-pong/scenes/`、`mini-pong/gdscripts/`、`mini-pong/assets/`、`mini-pong/tests/` 标准子目录
- `mini-pong/scenes/world_environment.tscn`：WorldEnvironment 场景，glow 强度 0.6
- CI 中增加 `godot --path mini-pong/ --headless --quit` 编译验证步骤

### 用户场景

1. **开发启动：** 开发者在 Godot 4.7 中打开 `mini-pong/project.godot` → 看到已配置 2D Forward+ 渲染和 glow/bloom 的项目 → 立即开始 Pong 开发
2. **CI 验证：** 每次 PR 提交 → CI 运行 `godot --path mini-pong/ --headless --quit` → 验证 Mini Pong 项目编译无错误
3. **后续扩展基础：** Plan/Implement 阶段以 `mini-pong/` 为根目录，添加 Pong 游戏的具体场景、脚本和资源

### 范围边界

| 包括 | 不包括 |
|------|--------|
| `mini-pong/` 目录结构创建 | Mini Pong 游戏逻辑代码 |
| `mini-pong/project.godot` 配置（2D Forward+, glow） | 任何游戏功能实现 |
| `mini-pong/scenes/world_environment.tscn` | 其他场景文件 |
| 标准子目录（scenes/, gdscripts/, assets/, tests/） | 资源文件（图片、字体、音频） |
| CI workflow 中 Mini Pong 编译检查步骤 | 测试文件或测试运行器 |

---

## 2. 设计意图

### 为什么是现在

Mini Pong 是整个项目中的独立游戏子项目。#301 是 Mini Pong 的起点——定义项目骨架。没有此骨架，后续所有 Mini Pong 功能（球拍控制、球物理、计分、AI 对手）都无处安放。同时，这是一个基础架构 Issue，需要优先完成以支持并行开发。

### 设计原则

1. **独立子项目：** `mini-pong/` 拥有独立的 `project.godot`，不依赖根项目的配置。这允许 Mini Pong 使用 2D Forward+ 渲染器（根项目使用 gl_compatibility）。
2. **最小可用骨架：** 仅创建目录结构和最小配置。不填充任何功能代码或资源——这些由后续 Issue 处理。
3. **CI 覆盖：** 骨架创建完成后立即加入 CI 验证，确保 `mini-pong/` 在所有后续开发中保持可编译状态。
4. **标准化布局：** 遵循 Godot 项目最佳实践——`scenes/` 存放场景文件，`gdscripts/` 存放脚本，`assets/` 存放资源，`tests/` 存放测试。

### 先前约束

- 根项目的 `project.godot` 使用 `gl_compatibility` 渲染器——Mini Pong 独立于根项目，可以使用 `forward_plus`
- `opencode-review.yml` 已针对特定分支模式（`impl/`）筛选——Mini Pong 步骤不应更改此逻辑
- Mini Pong 是 MVP 版本的一部分——骨架应保持最小

---

## 3. 影响分析

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/project.godot` | Godot 配置 | Mini Pong 独立项目配置（2D Forward+, glow/bloom） |
| `mini-pong/scenes/world_environment.tscn` | Godot 场景 | WorldEnvironment 节点，glow 强度 0.6 |
| `mini-pong/scenes/` | 目录 | 场景文件存放 |
| `mini-pong/gdscripts/` | 目录 | GDScript 文件存放 |
| `mini-pong/assets/` | 目录 | 资源文件存放 |
| `mini-pong/tests/` | 目录 | 测试文件存放 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `.github/workflows/opencode-review.yml` | 在 `Validate sub-project scaffold` 步骤后（或在适当位置），增加 `godot --path mini-pong/ --headless --quit` 编译验证步骤 |

### 数据流

```
agent-game-test/
├── mini-pong/
│   ├── project.godot          ← 独立配置 (2D Forward+, glow/bloom)
│   ├── scenes/
│   │   └── world_environment.tscn  ← WorldEnvironment (glow 0.6)
│   ├── gdscripts/             ← (空，后续填充)
│   ├── assets/                ← (空，后续填充)
│   └── tests/                 ← (空，后续填充)
└── .github/workflows/
    └── opencode-review.yml    ← + Mini Pong 编译步骤
```

### 文档更新

- 无需更新现有文档——这是 Mini Pong 子项目的第一个脚手架

---

## 4. 方案对比

| 方案 | 描述 | 优点 | 缺点 | 难度 |
|------|------|------|------|------|
| **A：独立子项目目录（推荐）** | 在根下创建 `mini-pong/`，包含独立 `project.godot` 和子目录 | 完全隔离，独立渲染配置，CI 可单独验证 | 需要维护两份 project.godot | 低 |
| **B：根项目内部分组** | 在根 `scenes/` 和 `gdscripts/` 下创建 `mini_pong/` 子目录 | 单一 project.godot，统一管理 | 渲染配置冲突（根用 gl_compatibility，Pong 需要 Forward+），目录混乱 | 中 |
| **C：独立 Git 仓库** | 新建 `devvi/mini-pong` 仓库 | 完全解耦 | 跨仓库 CI/CD 复杂，项目协调成本高 | 高 |

### 推荐：方案 A

对于 Mini Pong 骨架，独立子项目目录是最合理的选择：

- 使用独立的 `project.godot`，可以选择 `forward_plus` 渲染器和 glow/bloom 效果，不受根项目约束
- `world_environment.tscn` 直接在 `mini-pong/scenes/` 中创建，属于 Mini Pong 项目
- CI 中使用 `godot --path mini-pong/ --headless --quit` 对子项目进行独立编译验证
- 新增的 CI 步骤不应改变现有 `impl/` 分支筛选逻辑——作为无条件步骤执行（当 `mini-pong/` 目录存在时）

### project.godot 配置建议

```ini
[application]
config/name="Mini Pong"
config/description="A classic Pong game implementation"
run/main_scene=""

[rendering]
renderer/rendering_method="forward_plus"
; 开启 glow/bloom 效果
environment/glow_enabled=true
```

---

## 5. 边界条件与验收标准

### 正常路径

1. `mini-pong/` 目录存在，包含 `project.godot`
2. `project.godot` 配置使用 `forward_plus` 渲染器，glow/bloom 开启
3. `mini-pong/scenes/`、`gdscripts/`、`assets/`、`tests/` 子目录存在
4. `mini-pong/scenes/world_environment.tscn` 存在
5. `world_environment.tscn` 包含 `WorldEnvironment` 节点，`Glow` 强度 0.6
6. CI workflow 包含 `godot --path mini-pong/ --headless --quit` 步骤
7. `godot --path mini-pong/ --headless --quit` 退出码为 0（无编译错误）

### 边缘情况

| 场景 | 预期行为 |
|------|---------|
| `mini-pong/` 目录不存在（尚未 checkout） | CI 步骤跳过，不报错 |
| `mini-pong/project.godot` 缺少渲染设置 | Godot 使用默认 Forward+ 渲染，glow 不生效 |
| world_environment.tscn 缺少 Glow 设置 | 场景加载成功但无 glow 效果——不应导致编译错误 |

### 验收标准

- [ ] `mini-pong/` 目录存在
- [ ] `mini-pong/project.godot` 存在，配置使用 2D Forward+ 渲染器，glow/bloom 开启
- [ ] `mini-pong/scenes/`、`mini-pong/gdscripts/`、`mini-pong/assets/`、`mini-pong/tests/` 目录存在
- [ ] `mini-pong/scenes/world_environment.tscn` 存在，glow 强度 0.6
- [ ] CI 中增加了 `godot --path mini-pong/ --headless --quit` 步骤
- [ ] `godot --path mini-pong/ --headless --quit` 退出码为 0

---

## 8. 延续上下文（Plan Agent 交接）

### 当前系统状态

- 根项目 `project.godot` 使用 `gl_compatibility` 渲染器，注册为 "Agent Game Test Workflow"
- 根项目已有 `scenes/`、`gdscripts/` 目录（属于贪吃蛇实验项目）
- `opencode-review.yml` 已包含 `rainy-night-prometheus` 子项目验证步骤
- 根项目 branch 为 `main`（非 `master`）

### 实施注意事项

1. **project.godot 格式：** 使用 Godot 4.x ConfigFile 格式（`[section]\nkey=value`），不使用 JSON。关键配置：`[application] config/name`、`[rendering] renderer/rendering_method`、`environment/glow_enabled`。
2. **world_environment.tscn：** 使用 Godot TSCN 文本格式（`format=3`）。根节点为 `WorldEnvironment`，在 `environment` 属性中设置 `Glow` 资源，`glow_intensity=0.6`。
3. **CI 步骤位置：** 新的 Mini Pong 步骤应放在 `Validate sub-project scaffold` 步骤之后，采用类似的 `if: ||` 跳过逻辑。参考现有 `rainy-night-prometheus` 步骤的模式。
4. **目录创建：** `mkdir -p mini-pong/{scenes,gdscripts,assets,tests}` 语法可一次创建所有子目录。
5. **验证方法：**
   ```bash
   cd /path/to/project
   godot --path mini-pong/ --headless --quit
   echo "Exit: $?"
   ```

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| project.godot 配置键名错误 | 中 | 高（glow 不生效） | 创建后用 Godot 编辑器打开验证配置是否正确加载 |
| world_environment.tscn 格式错误 | 中 | 高（场景无法加载） | 创建后立即用 headless 模式验证 |
| CI 步骤顺序导致错误 | 低 | 中 | 复用现有步骤的 `if: -d` 检查和 `continue-on-error` 模式 |
| 根项目与子项目 project.godot 混淆 | 低 | 低 | `mini-pong/` 独立性确保隔离 |

### 下一步

Plan Agent 将使用此 PRD 创建包含详细项目配置、TSCN 代码段和 CI 步骤描述的 DESIGN 文档。Implement Agent 将创建实际的 `mini-pong/` 目录结构、`project.godot`、`world_environment.tscn` 和 CI 修改。

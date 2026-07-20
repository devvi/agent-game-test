# Research: 项目脚手架 — Godot 4.7 CRPG框架

> Parent Issue: #6
> Agent: game-research-agent
> Date: 2026-07-21

---

## 1. Problem Definition

### Current Behavior
项目目前存在一个基础的 Godot 4.7 工程配置，包含：
- `project.godot`：forward_plus 渲染器、1920×1080 窗口、GameManager autoload
- `export_presets.cfg`：仅 Linux/X11 导出预设
- `gdscripts/main.gd`：简单的 Hello World Label 设置
- `gdscripts/game_manager.gd`：基础 Autoload（打印 + game_started 状态）
- `scenes/main.tscn`：包含一个 Label 节点的根 Node
- `tests/run_tests.gd`：3 个基础 Label 单元测试
- **缺失**：输入映射、音频总线、GitHub Actions CI、macOS 导出、CRPG 优化配置

### Expected Behavior
项目脚手架应达到 CRPG 开发就绪状态：
- `project.godot` 包含 CRPG 优化的渲染器设置（禁用物理引擎、启用 2D 批处理）、完整输入映射、音频总线定义
- `scenes/main.tscn` 作为入口场景，结构清晰（根 Node->Control/UI 层、Audio/背景层）
- `export_presets.cfg` 包含 macOS 和 Linux 导出配置
- `.github/workflows/` 包含 CI 工作流，自动运行 `godot --headless --script tests/run_tests.gd`
- 全局 Theme 基础结构就绪

### User Scenarios
- **Scenario A（开发者）：** Clone 项目后，直接用 Godot 4.7.1 打开，所有输入映射已配好，打开即可开发
- **Scenario B（CI/CD）：** 每次 Push/PR 自动运行测试，验证项目完整性
- **Scenario C（构建）：** 通过脚本一键导出 macOS / Linux 构建
- **Frequency：** 每次开发、每次 CI 运行、每次构建发布

---

## 2. Design Intent (Feature)

### Why Do We Need This?
CRPG（Computer Role-Playing Game）对 Godot 引擎配置有特殊要求：
1. **不需要物理引擎**：CRPG 是对话/UI/探索驱动的，物理碰撞计算浪费性能，应禁用或最小化
2. **AudioBus 分层**：需要环境音（雨声/脚步声）、语音（对话）、音乐（BGM）三个独立音频层，各自可控音量
3. **Control 多层 UI**：对话界面、状态面板、菜单、地图等需要多层 Control 节点管理
4. **Theme 全局风格**：暗黑都市主题需要全局一致的字体、颜色、样式

当前的基础配置仅满足"项目能打开"，远未达到 CRPG 开发就绪。

### Why Change Now?
这是项目开发的**第一步基础设施**。所有后续功能（对话系统、UI、音频）都依赖这个脚手架的质量。如果不先搭建好，后续每个功能都需要反复修改底层配置，造成技术债务。

### Previous Constraints
- 项目指定 Godot **4.7.1** 版本（`game-env/manifest.yaml`），所有配置必须兼容此版本
- 默认分支为 `main`（不是 `master`）
- 已有 `GameManager` Autoload 注册，不能删除或破坏其接口
- 已有 `tests/run_tests.gd` 测试框架，CI 必须与之兼容

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `project.godot` | 项目配置 | 新增 CRPG 优化配置、输入映射、音频总线 |
| `export_presets.cfg` | 导出配置 | 新增 macOS 预设，优化 Linux 预设 |
| `.github/workflows/ci.yml` | CI/CD | 新建 — Godot headless 测试工作流 |
| `scenes/main.tscn` | 入口场景 | 重新组织为 CRPG 友好的场景结构 |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/main.gd` | 主场景脚本 | 需要重写以匹配新的场景结构 |
| `gdscripts/game_manager.gd` | 全局管理器 | 可能需要扩展以支持 CRPG 状态管理 |
| `tests/run_tests.gd` | 测试框架 | CI 验证时需要与之兼容 |

### Data Flow Impact
```
Godot Engine startup
    → project.godot 加载配置（渲染器、输入映射、音频总线）
    → Autoload GameManager 初始化
    → scenes/main.tscn 加载
    → main.gd._ready() 初始化 UI/音频
    → 等待玩家输入（映射好的按键）
    → 通过输入映射触发游戏逻辑
```

### Documents to Update
- [x] `docs/PRD/6-project-scaffold.md`（本文档）
- [ ] `docs/DESIGN/6-project-scaffold.md`（Plan 阶段创建）
- [ ] `docs/GAME_DESIGN/03-GODOT-SETUP.md`（后续更新）

---

## 4. Solution Comparison

### Approach A: 最小改动增量式搭建
- **Description：** 在现有配置基础上逐步添加 CRPG 所需配置：修改 `project.godot` 添加输入映射和音频总线，新建 `.github/workflows/ci.yml`，补充 `export_presets.cfg` 的 macOS 预设，调整 `main.tscn` 结构。
- **Pros：** 
  - 保留现有代码兼容性
  - 改动增量小，易于 review
  - 可以分步提交
- **Cons：** 
  - `project.godot` 部分配置（如 physics/2d）需要手动添加 Godot 引擎支持的所有字段，工作量不小
- **Risk：** Low — Godot 4.7 标准配置方式
- **Effort：** ~5 个文件，约 100-150 行配置

### Approach B: 从零重建完整脚手架
- **Description：** 删除现有 `project.godot`，用 Godot 4.7.1 编辑器从头创建项目，然后手动移植现有 `gdscripts/` 和 `scenes/`。
- **Pros：** 
  - 配置最纯净，无残留字段
  - 编辑器自动生成所有默认值
- **Cons：** 
  - 破坏现有代码兼容性
  - 需要重新配置 Autoload
  - 可能引入编辑器版本差异
- **Risk：** Medium — 现有代码可能在新项目中不兼容
- **Effort：** ~30 分钟手动操作 + 调试

### Approach C: Godot 4.7 插件自动化脚手架
- **Description：** 开发一个 Godot 编辑器插件，通过 GUI 界面一键配置 CRPG 脚手架（输入映射、音频总线、导出预设）。
- **Pros：** 
  - 可复用，未来项目也能用
  - 提供 GUI 交互体验
- **Cons：** 
  - 对本项目来说过度工程化
  - 插件开发和调试时间远超手动配置
- **Risk：** High — 插件开发周期长，且可能不兼容不同 Godot 版本
- **Effort：** ~3-5 天

### Recommendation
→ **Approach A** because：这是基础设施搭建，目标是快速建立可工作的 CRPG 脚手架，而非构建可复用的工具链。增量修改保留现有代码完整性，review 成本最低，验收条件明确。后续其他功能可以直接在这个脚手架上开发。

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path
1. `project.godot` 配置 CRPG 优化参数
2. 输入映射完整配置（Space / 方向键 / Tab / Enter / Esc）
3. 音频总线至少 3 条（环境音/语音/音乐）
4. `.github/workflows/ci.yml` 新建并正常运行
5. `export_presets.cfg` 包含 macOS + Linux 两个预设
6. `scenes/main.tscn` 结构优化为 CRPG 友好布局
7. Godot 4.7.1 打开项目 → 主场景启动 → 无报错

### Edge Cases
1. **Godot 4.7.1 未安装：** CI 需要通过 GitHub Actions 的 `actions/setup-godot` 安装指定版本
2. **输入映射冲突：** 确保 Enter（确认）和 Esc（暂停）不会与 macOS 系统快捷键冲突（如 Cmd+Q）
3. **多显示器和分辨率：** `project.godot` 中配置 `allow_hidpi=true`，`window/dpi/allow_hidpi=true` 已存在
4. **CI 在 PR 触发：** CI 应配置为 push 和 pull_request 都触发，目标分支为 main

### Failure Paths
1. **Godot headless 不可用：** GitHub Actions runner 上 Godot 未正确安装 → workflow 应设置失败提示
2. **export_presets 路径错误：** 导出路径 `exports/` 目录不存在 → 应该在 CI 中先创建目录
3. **音频总线配置被编辑器覆盖：** 如果通过编辑器重新打开项目保存，音频总线可能被编辑器默认值覆盖 → 需要在 `project.godot` 中显式配置总线

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Godot 4.7.1 engine | Stable | Low — 已有 manifest.yaml 确认 |
| GitHub Actions runners | Available | Low — 公共仓库免费额度足够 |
| GitHub Token | Set | Low — GH_TOKEN 已在环境变量中 |

### Blocks

| Future Work | Priority |
|-------------|----------|
| 对话系统 (UI Control + 输入映射) | P0 — 本 Issue 完成后才能开始 |
| 音频系统 (AudioBus 分层) | P0 — 需要音频总线基础设施 |
| UI 系统 (Theme + 布局) | P0 — 需要 Control 多层 UI 骨架 |
| 场景切换 | P0 — 需要 main.tscn 作为入口 |

### Preparation Needed
- [ ] 确认 Godot 4.7.1 可执行文件路径（在 GitHub Actions runner 上）
- [ ] 确认 `assets/icon.png` 存在（项目已有）
- [ ] 测试 `tests/run_tests.gd` 在 Godot headless 模式下能否正常退出

---

## 7. Spike / Experiment (Optional — depth/deep only)

### Question to Answer
使用深度/deep 标签的深度研究：Godot 4.7.1 中，通过 `project.godot` 手动配置音频总线的最佳实践是什么？编辑器 UI 生成的 `[audio]` 和 `[bus]` 格式能否在纯文本中手写？

### Method
1. 查阅 Godot 4.7 官方文档关于 `project.godot` 中音频总线的配置格式
2. 检查社区/示例项目中音频总线的 `project.godot` 片段
3. 验证手写音频总线配置在 Godot 4.7.1 中是否可以正确加载

### Result
Godot 4.7 的 `project.godot` 文件中，音频总线配置格式为：
```ini
[audio]
default_bus_layout="res://default_bus_layout.tbr"

# 或者直接在 project.godot 中配置总线（不推荐）
# 推荐方式：使用 .tbr 文件 + 编辑器 UI 配置
```

但实际上，对于音频总线布局，Godot 4.7 使用 `default_bus_layout.tbr` 文件（二进制格式，不可手写）。因此最佳实践是：在 Godot 编辑器中配置音频总线 → 保存到 `default_bus_layout.tbr` → 提交到 Git。但也可以通过 `project.godot` 在 `[audio]` 部分引用已存在的布局文件。

**结论：** 音频总线应在 Godot 编辑器中通过 Audio > Bus Layouts 配置，保存为 `default_bus_layout.tbr`。如果手写困难，可以在 `project.godot` 中设置 `[audio]` 引用，然后在实现阶段通过编辑器或脚本创建总线布局。

### Impact on Approach
→ 音频总线的实现方式调整为：Plan/Implement 阶段需要在 Godot 编辑器打开项目 → 配置 Audio Bus Layout（添加 2 条额外总线，命名 Environment/Voice/Music）→ 保存。这无法通过纯文本配置文件完成，需要在实现 Issue 时直接操作 Godot 编辑器。PRD 阶段不做具体 `.tbr` 文件内容假设。

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The Godot 4.7 project scaffold currently has a basic setup at minimal state (config present, main scene exists, autoload registered). The existing `project.godot` uses `forward_plus` renderer, `main.tscn` as entry scene, and `GameManager` as autoload. `export_presets.cfg` currently only has one Linux/X11 preset. No `.github/` directory exists yet. No audio bus configuration is present. No input map entries are configured.

The proposed approach (Approach A) builds on the existing project files: modify `project.godot` to add CRPG-optimized rendering settings (disable physics 2d/3d processing, optimize for 2D UI), input map entries (Space, Arrow Keys, Tab, Enter, Esc), and reference an audio bus layout; create `.github/workflows/ci.yml` for headless testing; add macOS export preset to `export_presets.cfg`; restructure `main.tscn` with proper CRPG-ready node hierarchy (Node root → Control/UI layer + background layer).

The main risk is the audio bus format — `default_bus_layout.tbr` is binary and cannot be hand-crafted in this PRD. The implement phase will need to either (a) open Godot editor to create the bus layout, or (b) use a script to generate it. The CI workflow is straightforward using `nokitaka/setup-godot@v1` or `actions/setup-godot@v1` action. Export presets for macOS require the `macos` template which must be installed in the Godot installation.

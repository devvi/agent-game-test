# Research: 雨夜普罗摩茨项目骨架创建

> Parent Issue: #213
> Agent: game-research-agent
> Date: 2026-07-24

---

## 1. Problem Definition

### Current Behavior

当前 `agent-game-test` 仓库中只存在一个 Godot 4.7.1 项目（`urban-night-walker`，即都市夜行者），位于仓库根目录。雨夜普罗摩茨（Rainy Night Prometheus）尚未创建任何项目骨架。

现有 `urban-night-walker` 项目包含完整的 CRPG 基础设施：
- `project.godot`：forward_plus 渲染器、1920×1080 窗口、完整的 autoload 链（StateSystem、GameManager、NarrativeManager、AudioManager、GameState、UIConfig）
- `gdscripts/`：45 个脚本，包含对话引擎（dialogue_runner、dialogue_parser）、状态系统（state_system）、场景管理（scene_manager、scene_base）、常量定义（constants）等核心模块
- `scenes/`：20 个场景文件，覆盖主场景、UI、组件、场景走廊等
- `dialogues/`：13 个 JSON 对话文件
- `tests/`：37 个测试脚本
- `assets/`：材质、字体、音频等资源

雨夜普罗摩茨需要**独立于** urban-night-walker 的项目目录，但**复用** urban-night-walker 的核心脚本作为 symlink，避免代码重复。

### Expected Behavior

在 `agent-game-test/rainy-night-prometheus/` 下创建独立子项目，包含：
- **独立 `project.godot`**：配置为 Forward+ 渲染器，使用雨夜普罗摩茨专有的项目名称和主场景
- **核心脚本 symlink**：通过符号链接复用 urban-night-walker 的 6 个核心脚本（dialogue_runner、dialogue_parser、state_system、scene_manager、scene_base、constants）
- **完整目录结构**：scenes/、gdscripts/、dialogues/（含 json/）、assets/materials/、assets/audio/、tests/
- **可编译验证**：`godot --headless --quit` 执行无编译错误

### User Scenarios

- **Scenario A（雨夜普罗摩茨开发者）：** Clone 仓库后，直接进入 `rainy-night-prometheus/` 目录，用 Godot 4.7.1 打开该子项目，立即开始开发，无需手动配置任何基础设施
- **Scenario B（雨夜普罗摩茨内容创作者）：** 在 `dialogues/json/` 下创建对话 JSON 文件，核心脚本通过 symlink 自动同步 urban-night-walker 的最新更新
- **Scenario C（跨项目维护者）：** 修改 urban-night-walker 的核心脚本后，雨夜普罗摩茨通过 symlink 自动继承变更，无需手动同步
- **Frequency：** 每次开发会话、每次 CI 运行、每次跨项目核心脚本更新

---

## 2. Design Intent (Feature)

### Why Do We Need This?

雨夜普罗摩茨作为 `agent-game-test` 仓库中的第二个独立 Godot 项目，需要：
1. **项目隔离**：独立的 `project.godot` 允许配置专属于雨夜普罗摩茨的项目设置（主场景、autoload、输入映射、项目名称等），不与 urban-night-walker 冲突
2. **代码复用**：雨夜普罗摩茨与 urban-night-walker 共享相同的底层 CRPG 基础设施（对话引擎、状态系统、场景管理）。直接通过 symlink 复用这些脚本，避免复制粘贴导致的代码漂移
3. **独立演进**：雨夜普罗摩茨的场景、对话内容、UI 主题、视觉特效与 urban-night-walker 完全不同，需要独立的目录结构来存放这些专属资产
4. **可验证性**：独立的 `project.godot` 允许 CI 对雨夜普罗摩茨单独运行 `--headless --quit` 验证，不依赖 urban-night-walker 的配置

### Why Change Now?

这是雨夜普罗摩茨项目的**首个 Issue**（Issue #1 of rainy-night-prometheus）。所有后续功能——对话引擎集成、视觉氛围系统、场景骨架、NPC 框架——都依赖一个正确配置的项目骨架。没有这个脚手架，后续每个功能 Issue 都需要处理底层配置问题。

### Previous Constraints

- 项目引擎：Godot **4.7.1**（`game-env/manifest.yaml`），所有配置必须兼容此版本
- 雨夜普罗摩茨使用 **Forward+** 渲染器（与 urban-night-walker 一致）
- 核心脚本通过 **symlink**（符号链接）复用，而非拷贝，以确保 urban-night-walker 的更新自动反映在雨夜普罗摩茨中
- symlink 目标路径必须使用相对路径（`../gdscripts/xxx.gd`），确保仓库在不同开发环境下路径一致
- 现有 `urban-night-walker` 的 `project.godot` 中 autoload 引用 `res://gdscripts/` 路径，symlink 后的脚本在雨夜普罗摩茨中通过 `res://gdscripts/` 访问

---

## 3. Impact Analysis

### Directly Affected Modules

| 文件/目录 | 模块 | 变更性质 |
|-----------|------|----------|
| `rainy-night-prometheus/` | 项目根目录 | 新建 — 整个项目目录 |
| `rainy-night-prometheus/project.godot` | 项目配置 | 新建 — 雨夜普罗摩茨专有配置 |
| `rainy-night-prometheus/gdscripts/` | 脚本目录 | 新建 — 包含指向 urban-night-walker 的 symlink |
| `rainy-night-prometheus/scenes/` | 场景目录 | 新建 — 空场景目录结构 |
| `rainy-night-prometheus/dialogues/json/` | 对话目录 | 新建 — 对话 JSON 存放位置 |
| `rainy-night-prometheus/assets/materials/` | 材质资源 | 新建 — 空材质目录 |
| `rainy-night-prometheus/assets/audio/` | 音频资源 | 新建 — 空音频目录 |
| `rainy-night-prometheus/tests/` | 测试目录 | 新建 — 空测试目录 |

### Indirectly Affected Modules

| 文件/模块 | 为什么受影响 |
|-----------|-------------|
| `gdscripts/dialogue_runner.gd` | 被 symlink 引用，修改时影响两个项目 |
| `gdscripts/dialogue_parser.gd` | 同上 |
| `gdscripts/state_system.gd` | 同上 |
| `gdscripts/scene_manager.gd` | 同上 |
| `gdscripts/scene_base.gd` | 同上 |
| `gdscripts/constants.gd` | 同上 |
| `scripts/stage-gate.py` | 可能需要在 CI 中处理多项目目录结构 |

### Data Flow Impact

```
Git Clone / Pull
    → 仓库包含 rainy-night-prometheus/ 目录
    → symlink 在 macOS/Linux 上自动解析（需在 Windows 上配置 git symlink 支持）
    → Godot 4.7.1 打开 rainy-night-prometheus/project.godot
    → project.godot 加载 autoload（通过 res://gdscripts/ 引用 symlink 脚本）
    → 引擎解析 symlink → 实际加载 urban-night-walker 的脚本文件
    → 场景系统加载 scenes/ 下的场景文件
    → 开发者可在 rainy-night-prometheus/ 内独立工作
```

### Documents to Update

- [x] `docs/PRD/213-rainy-night-prometheus-scaffold.md`（本文档）
- [ ] `docs/DESIGN/213-rainy-night-prometheus-scaffold.md`（Plan 阶段创建）
- [ ] `rainy-night-prometheus/README.md`（项目独立的说明文档）

---

## 4. Solution Comparison

### Approach A: Symlink 复用 + 手动创建目录结构（推荐）

- **Description：** 在 `rainy-night-prometheus/` 下手动创建目录结构（`scenes/`, `gdscripts/`, `dialogues/json/`, `assets/materials/`, `assets/audio/`, `tests/`），在 `gdscripts/` 下创建指向 `../gdscripts/xxx.gd` 的 symlink，手动创建独立的 `project.godot`，参照 urban-night-walker 的配置模板。
- **Pros：**
  - 目录结构精确可控，每个目录的用途明确
  - symlink 使用相对路径，跨平台兼容（macOS/Linux 原生支持）
  - `project.godot` 可以精确配置雨夜普罗摩茨专属设置
  - 提交后仓库体积增量极小（symlink 仅几字节）
- **Cons：**
  - 手动创建目录和 symlink 需要写脚本或手动操作
  - Windows 上 git symlink 需要额外配置（`core.symlinks=true`）
  - autoload 路径需要确保 symlink 被正确解析到 `res://gdscripts/`
- **Risk：** Low — Godot 4.7 的标准项目创建方式
- **Effort：** ~10 个目录 + 6 个 symlink + 1 个 project.godot，约 50 行配置

### Approach B: 脚手架自动化脚本

- **Description：** 编写一个 `scripts/scaffold-rainy-night-prometheus.sh` 或 `.py` 脚本，自动创建目录结构、symlink 和 `project.godot`。开发者运行一次脚本即可。
- **Pros：**
  - 可重复执行，确保结果一致性
  - 未来创建其他子项目时可复用
  - 自动处理 symlink 相对路径计算
- **Cons：**
  - 过度工程化 — 本 Issue 仅创建一次项目骨架
  - 脚本本身需要维护，增加了仓库复杂度
  - symlink 的 Godot `res://` 路径解析可能在脚本中难以模拟
- **Risk：** Low-Medium — 脚本编写简单，但增加了不必要的维护负担
- **Effort：** 脚本 ~30 行 + 验证

### Approach C: Git Subtree/Submodule 方案

- **Description：** 将 urban-night-walker 的核心脚本提取为独立的 Git 子模块或 subtree，雨夜普罗摩茨通过子模块引用。
- **Pros：**
  - 版本控制明确，核心脚本的变更可独立管理
  - 不依赖 symlink，Windows 兼容性好
- **Cons：**
  - 操作复杂度高：子模块需要额外的 `git submodule update --init` 步骤
  - 对开发者不友好：Clone 后需要额外命令才能正常工作
  - 核心脚本的修改需要先提交到子模块仓库，工作流繁琐
  - 对本项目来说严重过度工程化
- **Risk：** Medium — 子模块工作流复杂，容易出错
- **Effort：** ~1 小时设置 + 持续维护负担

### Recommendation

→ **Approach A** because：雨夜普罗摩茨项目骨架是一次性创建的基础设施。手动创建目录结构 + symlink 的方式最直接、最透明，仓库增量最小，review 成本最低。symlink 使用相对路径（`../gdscripts/xxx.gd`），在 macOS/Linux 开发环境中完美工作。后续开发者 clone 后立即可用，无需额外步骤。

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. `rainy-night-prometheus/` 目录存在于仓库根目录
2. `rainy-night-prometheus/project.godot` 文件存在，包含：
   - 项目名称 "Rainy Night Prometheus"
   - 渲染器 `renderer/rendering_method="forward_plus"`
   - 基础窗口配置（1920×1080）
3. `rainy-night-prometheus/gdscripts/` 目录包含以下 symlink（指向 `../gdscripts/`）：
   - `dialogue_runner.gd` → `../gdscripts/dialogue_runner.gd`
   - `dialogue_parser.gd` → `../gdscripts/dialogue_parser.gd`
   - `state_system.gd` → `../gdscripts/state_system.gd`
   - `scene_manager.gd` → `../gdscripts/scene_manager.gd`
   - `scene_base.gd` → `../gdscripts/scene_base.gd`
   - `constants.gd` → `../gdscripts/constants.gd`
4. 目录结构完整：
   - `rainy-night-prometheus/scenes/`
   - `rainy-night-prometheus/gdscripts/`
   - `rainy-night-prometheus/dialogues/json/`
   - `rainy-night-prometheus/assets/materials/`
   - `rainy-night-prometheus/assets/audio/`
   - `rainy-night-prometheus/tests/`
5. `rainy-night-prometheus/assets/icon.png`（项目图标，从根目录 `assets/icon.png` 拷贝或 symlink）
6. `godot --headless --quit` 在 rainy-night-prometheus/ 目录下执行无编译错误

### Edge Cases

1. **symlink 在 Windows 上不工作：** Windows 上的 Git 默认禁用 `core.symlinks` → 需要在仓库根目录添加 `.gitattributes` 文件，确保 symlink 文件被正确检出。备选方案：当 symlink 不可用时，提供 fallback 说明
2. **symlink 目标路径错误：** 如果 `../gdscripts/xxx.gd` 路径指向不存在的位置，Godot 加载 autoload 时会报错 → 必须在创建后验证每个 symlink 的目标可达
3. **autoload 路径冲突：** rain-night-prometheus 的 autoload 名称可能与 urban-night-walker 不同 → 需要在 `project.godot` 中使用雨夜普罗摩茨专有的 autoload 名称
4. **Git symlink 存储限制：** Git 存储 symlink 的方式是按文件类型存储，加了 `core.symlinks` 配置后，Windows 用户仍可能遇到问题 → `.gitattributes` 中应显式声明 symlink 文件
5. **多 `project.godot` 文件：** Godot 编辑器打开子项目时，可能误打开根目录的 `project.godot` → 需要明确文档说明：打开雨夜普罗摩茨时选择 `rainy-night-prometheus/project.godot`

### Failure Paths

1. **`project.godot` 配置错误导致 Godot 无法加载：** `godot --headless --quit` 报告错误 → 需要逐行检查 `project.godot` 的语法和配置项是否有效
2. **symlink 未被 Git 追踪：** 如果创建 symlink 时未提交，Git 可能将其视为普通空文件 → 需要 `git add` 时确认 symlink 被正确追踪（`git ls-files -s` 显示 `120000` 模式）
3. **目录结构不完整导致后续 Issue 失败：** 如果某个子目录缺失，依赖它的后续 Issue 会失败 → 验收条件中应逐目录验证

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| 依赖 | 状态 | 风险 |
|------|------|------|
| Godot 4.7.1 引擎 | Stable | Low — 已在 `game-env/manifest.yaml` 确认 |
| urban-night-walker 核心脚本 | Stable | Low — 6 个目标脚本均已存在且稳定 |
| Git symlink 支持 | Available | Low — macOS/Linux 原生支持 |
| `scripts/stage-gate.py` | Stable | Low — 用于 PR 合入门禁 |

### Blocks

| 未来工作 | 优先级 |
|----------|--------|
| 叙事架构设计（#214） | P0 — 依赖项目目录存在 |
| 集成 godot_dialogue_manager（#215） | P0 — 依赖 project.godot autoload 配置 |
| 基础视觉氛围系统（#217） | P0 — 依赖 assets/materials/ 目录 |
| 路线场景骨架（#228, #229） | P0 — 依赖 scenes/ 目录 |
| Godot Minimal Theme 集成（#216） | P0 — 依赖 project.godot 主题配置 |

### Preparation Needed

- [ ] 确认 Godot 4.7.1 可以打开子目录下的 `project.godot`（`godot --path rainy-night-prometheus/ --headless --quit`）
- [ ] 验证 symlink 相对路径在 Git 中的正确存储方式
- [ ] 确认 `.gitattributes` 中是否需要添加 symlink 相关配置

---

## 7. Spike / Experiment（depth/deep — 至少 3 个实验）

### 实验 1：Godot 子目录 `project.godot` 加载验证

**待回答问题：** Godot 4.7.1 能否正确加载仓库子目录中的 `project.godot`？`res://` 路径会解析为子目录的根还是仓库根？

**方法：**
1. 在 `rainy-night-prometheus/` 下创建最小 `project.godot`（仅基础配置 + 一个 Label 节点场景）
2. 使用 `godot --path rainy-night-prometheus/ --headless --quit` 运行
3. 观察 `res://` 路径解析结果

**预期结果：**
Godot 4.7.1 的 `--path` 参数支持指定子目录为项目根。`res://` 会解析为子目录的根（即 `rainy-night-prometheus/`）。因此 symlink 相对路径需要从 `rainy-night-prometheus/gdscripts/` 指向 `../gdscripts/`（向上到仓库根再进 `gdscripts/`）。

**影响：**
→ 验证通过则可以放心使用 `--path rainy-night-prometheus/` 的方式在 CI 中验证子项目。

---

### 实验 2：Symlink 跨目录 autoload 解析验证

**待回答问题：** 当 `project.godot` 声明 `[autoload] StateSystem="*res://gdscripts/state_system.gd"`，而 `gdscripts/state_system.gd` 是一个指向 `../gdscripts/state_system.gd` 的 symlink 时，Godot 能否正确解析并加载该 autoload？

**方法：**
1. 在 `rainy-night-prometheus/gdscripts/` 下创建 symlink：`ln -s ../../gdscripts/state_system.gd state_system.gd`
2. 在 `rainy-night-prometheus/project.godot` 中注册 `[autoload] StateSystem="*res://gdscripts/state_system.gd"`
3. 运行 `godot --path rainy-night-prometheus/ --headless --quit --script some_minimal_script.gd`，观察 StateSystem 是否成功初始化

**预期结果：**
Godot 通过 `res://` 加载文件时，会跟随文件系统的 symlink 解析到实际文件。只要 symlink 目标路径在文件系统中可访问，Godot 就能正确加载。关键点是 symlink 的**相对路径**必须从 `rainy-night-prometheus/gdscripts/` 计算，而不是从仓库根。

**影响：**
→ 验证通过则确认 symlink 方案可行。如果失败，备选方案为拷贝脚本（添加注释说明来源）。

---

### 实验 3：Git symlink 存储与跨平台检出验证

**待回答问题：** Git 如何存储 symlink？在不同平台上如何检出？`.gitattributes` 如何配置确保跨平台一致性？

**方法：**
1. 创建一个测试 symlink：`ln -s ../../gdscripts/test.gd test.gd`
2. `git add test.gd && git commit -m "test symlink"`
3. 检查 Git 如何存储：`git ls-files -s test.gd`
4. 克隆仓库到另一台机器，观察 symlink 是否保持

**预期结果：**
- Git 将 symlink 存储为 `120000` 模式（而非普通文件的 `100644`）
- 在 macOS/Linux 上 `git clone` 后 symlink 自动恢复
- Windows 上需要 `core.symlinks=true`，Git for Windows 从 2.x 版本开始支持
- `.gitattributes` 中不需要显式声明 symlink，但可以添加说明

**影响：**
→ 确认 symlink 方案在团队开发环境中可行。如果 Windows 兼容性是必须的，应考虑为 Windows 开发者提供 fallback 脚本。

---

### 实验 4：project.godot 最小可工作配置验证

**待回答问题：** 对于只有 symlink 脚本、没有场景文件的项目骨架，`project.godot` 需要包含哪些最小配置才能通过 `--headless --quit` 验证？

**方法：**
1. 创建一个极简 `project.godot`，仅包含：
   ```ini
   [application]
   config/name="Rainy Night Prometheus"
   config/features=PackedStringArray("4.7")
   
   [rendering]
   renderer/rendering_method="forward_plus"
   ```
2. 运行 `godot --path rainy-night-prometheus/ --headless --quit`，观察是否报错
3. 逐步添加 autoload symlink 注册，每次验证

**预期结果：**
Godot 可以打开没有主场景的项目进行 headless 编译验证。`--quit` 会在没有场景的情况下正常退出。autoload symlink 注册后，引擎会在启动时自动加载这些脚本，验证其语法和依赖关系。

**影响：**
→ 确认验收条件中 `--headless --quit 无编译错误` 的验证方法，以及 `project.godot` 的最小配置边界。

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The `agent-game-test` repository currently has one Godot 4.7.1 project at the root (`urban-night-walker`). The project uses `forward_plus` renderer, 1920×1080 window, and has 45 gdscripts, 20 scenes, and a full CRPG infrastructure including dialogue engine, state system, scene manager, and game state autoloads.

The proposed scaffold creates `rainy-night-prometheus/` as a second independent project that reuses 6 core gdscripts from `urban-night-walker` via symlinks: `dialogue_runner.gd`, `dialogue_parser.gd`, `state_system.gd`, `scene_manager.gd`, `scene_base.gd`, and `constants.gd`. The directory structure includes `scenes/`, `gdscripts/`, `dialogues/json/`, `assets/materials/`, `assets/audio/`, and `tests/`.

The main technical risk is symlink resolution across the parent directory — the symlinks in `rainy-night-prometheus/gdscripts/` must use relative paths (`../gdscripts/xxx.gd`) that resolve correctly relative to the symlink file's directory, not the project root. Godot's `res://` path resolution follows filesystem symlinks, so this should work. Windows compatibility for git symlinks is a secondary concern — `.gitattributes` configuration may be needed.

The Plan phase should: (1) verify godot `--path` flag works for subdirectory projects, (2) create all directories, (3) create symlinks, (4) create `project.godot` with autoload registrations, (5) run `godot --headless --quit` to validate, and (6) verify symlinks are properly tracked by git.

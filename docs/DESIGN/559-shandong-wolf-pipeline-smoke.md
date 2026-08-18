# Design: [Test] shandong-wolf 管线冒烟验证 — Main.tscn 标题场景 + 解耦配置回归

> **Parent Issue:** #559
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4 推荐 —— **方案 A**（纯场景静态标题，零脚本：1 个新 tscn + project.godot 一行），确认采纳；**方案 B**（`main_title.gd` 标题/版本参数化 + 0.5s 淡入）显式延后为后续视觉 issue 的可选扩展，不在本 issue 落地
> **Reference PRD:** `docs/PRD/559-shandong-wolf-pipeline-smoke.md`（research PR #560 已合并 2026-08-19）
> **所有权:** `content_ownership: mechanical`（标题场景 = 管线冒烟验证物，无品味裁决）
> **深度:** light（issue 无 depth/ 标签 → 按 light 处理）—— 只产出 DESIGN 文档，**不产 TASKS 文档**；测试仅描述不写代码（plan 阶段红线）
> **红线:** 只动 `shandong-wolf/`（新建 `scenes/Main.tscn`、改 `project.godot` 一行、可选 `e2e_shots.json`）；**绝不触碰** `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`

---

## 1. 架构总览

**问题本质是「骨架工程无主场景」而非逻辑缺陷。** `shandong-wolf/` 为 2026-08-18 新游戏 scaffold 产物：`project.godot` 已设 `config/name="山东抗日之狼"` 与 1280x720 窗口，但 `run/main_scene=""` 为空 → `godot --path shandong-wolf/` 启动无场景可实例化，管线冒烟只能验证「工程可加载」，无法验证「渲染出可见内容」。本 issue 的最小交付 = 一个**启动即默认显示标题『山东抗日之狼』+ 版本标签 v0.1.0** 的 `Main.tscn`，作为 P3 解耦配置（75a057a：manifest `game.active` 全链路参数化）在真实管线中的第一个落地验证物。

**设计哲学：最小冒烟语义 + 克制纪律。** 标题场景只做「能跑」的验证物（Obsidian《独立游戏开发讨论》§四：*核心系统做完、一轮游戏能跑就立住了*）：一个大标题 + 一个版本标签，不堆副文案、不做入场动画、不做交互引导（Obsidian 教程设计原则：*需求涌现时再给信息*；brief 文字质感：短句、克制、乡土）。版本号 v0.1.0 骨架期硬编码在 tscn 内可接受——`gdscripts/` 为空，为单值引入脚本层是本末倒置（方案 B 延后的核心理由）。

```
                    ★ Issue #559 本设计（shandong-wolf 首个落地物）
┌───────────────────────────────────────────────────────────────────────────┐
│ shandong-wolf/scenes/Main.tscn（新建，gd_scene format=3）                    │
│   Main (Node2D, 根)                                                        │
│   └── CanvasLayer (layer=1)                                                │
│       └── CenterContainer (全屏锚点 anchors_preset=15)                      │
│           └── VBoxContainer (alignment=1 居中)                              │
│               └── TitleLabel   「山东抗日之狼」 font_size=64 居中             │
│       └── VersionLabel (左下锚点 anchors_preset=2)  「v0.1.0」 font_size=16  │
└───────────────────────────────────┬───────────────────────────────────────┘
                                    │ project.godot 一行（修改，必改）
                    run/main_scene = "res://scenes/Main.tscn"   ← 当前为空
                                    ▼
              godot --path shandong-wolf/（无参数启动）
                    ├── CI smoke（--headless --quit 退出码 0）
                    └── review E2E 截图（首帧即含标题，非灰屏）  ← AC5 证据
```

**与 PRD 方案裁决的一致性：** PRD §4 推荐方案 A（零脚本纯 tscn）并否决方案 C（移植 mini-pong StartMenu 完整结构——明显过度 + 违反解耦验证初衷）。本设计确认采纳方案 A；方案 B 的入场淡入被 PRD 明确标注为「后续视觉 issue 的可选扩展」，本设计一致延后。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实 main 源码） | 与 #559 的差距 |
|------|----------------------------------------------------------|---------------|
| `shandong-wolf/project.godot` | ✅ name=山东抗日之狼、1280x720、stretch canvas_items 已设；**`run/main_scene=""` 为空** | ❌ 需补一行指向 Main.tscn |
| `shandong-wolf/scenes/` | ⚠️ 仅 `.gitkeep`，无任何 tscn | ❌ 新建 Main.tscn |
| `shandong-wolf/gdscripts/` | ⚠️ 仅 `.gitkeep`（方案 A 不需要脚本） | 无（方案 B 才需要） |
| `shandong-wolf/tests/run_tests.gd` | ✅ 占位「skeleton — no tests yet」，退出码 0 | 无（AC 未要求，**不改**） |
| `shandong-wolf/tests/smoke_test.gd` | ✅ 占位「SMOKE OK: shandong-wolf skeleton loads」 | 无（**不改**） |
| `shandong-wolf/tests/check_compile.gd` | ✅ 遍历 gdscripts/ + tests/ 逐个 load 校验 | 无（**不改**） |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位：`states: {}`、`state_node: ""` | 可选补 `01_title` shot（§4.2） |
| `mini-pong/scenes/Main.tscn` StartMenu 段 | ✅ 参考实现（TitleLabel font_size 64 + VersionLabel font_size 16 左下锚点） | 仅作结构模式参考，**不复制代码** |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| `shandong-wolf/project.godot` 的 `run/main_scene=""` 为空 | ✅ 属实（`[application]` 段 `run/main_scene=""`） | 改一行：`run/main_scene="res://scenes/Main.tscn"` |
| scenes/gdscripts/assets 全空（仅 .gitkeep） | ✅ 属实 | 方案 A 无需脚本/资产，只建 Main.tscn |
| `config/name="山东抗日之狼"`、窗口 1280x720、stretch canvas_items 已设 | ✅ 属实 | 继承，零改动 |
| mini-pong Main.tscn 的 TitleLabel/VersionLabel 结构可参考 | ✅ 属实（StartMenu/CanvasLayer → CenterContainer → VBoxContainer → TitleLabel；VersionLabel 独立于 CenterContainer、anchors_preset=2 左下） | 取「TitleLabel 居中大字号 + VersionLabel 左下小字号」模式，节点名/结构按 shandong-wolf 最小化重写 |
| Godot 4.7 默认字体含 CJK（mini-pong 已有中文 Label 先例） | ✅ 属实（mini-pong Main.tscn 中「单人模式（AI 对战）」「暂停」等中文 Label 正常渲染） | 标题用默认字体，不引外部字体 |
| `e2e_shots.json` 为占位（states 空、state_node 空） | ✅ 属实 | 可选补 `01_title` shot（§4.2），不补则 review 默认截图兜底 |

---

## 2. 新组件详细设计

### 2.1 `shandong-wolf/scenes/Main.tscn`（新建，唯一新文件）

- **文件:** `shandong-wolf/scenes/Main.tscn`
- **格式:** `gd_scene format=3`（Godot 4.x 标准文本格式），`[node]` 声明式，零脚本、零 ext_resource
- **节点结构:**

```
Main (Node2D)                                   ← 根节点，无脚本
└── CanvasLayer (layer = 1)
    ├── CenterContainer (anchors_preset = 15 全屏, grow_h 2, grow_v 2)
    │   └── VBoxContainer (alignment = 1 垂直居中)
    │       └── TitleLabel (Label)
    │             text = "山东抗日之狼"
    │             horizontal_alignment = 1 (居中)
    │             theme_override_font_sizes/font_size = 64
    └── VersionLabel (Label, anchors_preset = 2 左下)
          text = "v0.1.0"
          anchors: anchor_top = 1.0, anchor_bottom = 1.0
          offsets: left 16 / top -36 / right 400 / bottom -12 (左下角内边距)
          theme_override_font_sizes/font_size = 16
          modulate = Color(1, 1, 1, 0.6)   ← 低调（克制纪律：版本标签不抢戏）
```

- **关键属性表:**

| 节点 | 类型 | 关键属性 | 设计理由 |
|------|------|---------|---------|
| Main | Node2D | 根节点 | 与 mini-pong 根节点类型一致（Node2D），为后续游戏内容留挂载点 |
| CanvasLayer | CanvasLayer | layer=1 | UI 层独立于世界坐标；标题是纯 UI，无世界内容 |
| CenterContainer | CenterContainer | anchors_preset=15 | 全屏居中容器，窗口 resize 时自动保持居中 |
| VBoxContainer | VBoxContainer | alignment=1 | 垂直居中排列（当前仅一个子项，为后续副标题/提示行留扩展位） |
| TitleLabel | Label | text=山东抗日之狼, font_size=64, h_align=1 | 主标题，启动即默认可见（AC5：E2E 截图不依赖按键/状态机） |
| VersionLabel | Label | text=v0.1.0, font_size=16, anchors_preset=2, modulate alpha=0.6 | 版本标签，左下角低调呈现（Obsidian「克制」反例约束：不抢戏） |

- **信号/状态/方法:** 无（零脚本节点树，无信号、无状态、无方法）
- **集成说明:** 被 `project.godot` 的 `run/main_scene` 引用；无其他外部引用。E2E 截图通过节点路径 `Main/CanvasLayer/...` 定位断言目标（§4.2）。

### 2.2 （方案 B 延后项，本 issue 不落地）

`shandong-wolf/gdscripts/main_title.gd`（@export title_text/version_text + 0.5s modulate 淡入）—— 仅当后续视觉 issue 需要参数化/入场动画时再建，本 issue 明确不做（克制纪律 + 零脚本零风险，PRD §4 方案 B 缺点的核心理由）。

---

## 3. 既有组件修改

| 文件 | 变更 | 性质 | 为什么 |
|------|------|:----:|--------|
| `shandong-wolf/project.godot` | `run/main_scene=""` → `run/main_scene="res://scenes/Main.tscn"`（一行） | 修改（必需） | 无主场景则启动无可渲染内容，管线冒烟无法验证「渲染出可见标题」（AC5 前提） |
| `shandong-wolf/e2e_shots.json` | 可选：补 `01_title` shot（§4.2 给出完整设计） | 修改（可选，建议） | 使 L3 视觉断言自动化（版本标签 assert_text）；不补则 review 以默认截图兜底（PRD §5.2 边界 #5） |

**明确不改动（红线 + AC 边界）：**

| 文件 | 为什么不改 |
|------|-----------|
| `shandong-wolf/tests/*.gd`（run_tests/smoke_test/check_compile） | 占位测试保持全绿（AC 未要求改动）；CI 三命令（check_compile/run_tests/smoke_test）必须继续通过 |
| `mini-pong/` 任何文件 | 红线：diff 只落 shandong-wolf/（AC3）；mini-pong Main.tscn 仅作结构参考，不复制代码（PRD §4 方案 C 否决理由） |
| `game-env/manifest.yaml` | P3 已参数化（75a057a），本 issue 只**验证**消费方跟随，不改单一事实源（PRD §1.4 范围边界） |
| `.github/workflows/`（opencode-review.yml） | CI 已 manifest 参数化（L44-50 已核实），零改动（PRD §3.3） |
| `docs/GAME_DESIGN/shandong-wolf/` | review agent 在首个 implement PR merge 后按 INDEX.md 约定填充（AC6），plan 阶段不写 GDD |

---

## 4. 数据流

### 4.1 流程 1：正常路径（启动链）

```
godot --path shandong-wolf/（无参数）
  │
  ▼
project.godot 读取 run/main_scene = "res://scenes/Main.tscn"   ← 本次必改（当前为空）
  │
  ▼
Main.tscn 实例化（根节点 Main）
  ├── CanvasLayer/CenterContainer/VBoxContainer/TitleLabel
  │     └─ 居中渲染「山东抗日之狼」（font_size 64）    ← 启动首帧即可见
  └── CanvasLayer/VersionLabel
        └─ 左下渲染「v0.1.0」（font_size 16, alpha 0.6）
  │
  ▼
CI L2（check_compile / run_tests / smoke_test）→ 退出码 0，全绿
  │
  ▼
review E2E 截图（首帧）→ 图中可见标题，非默认灰屏    ← AC5 证据链
```

### 4.2 流程 2：E2E 视觉断言（可选 `01_title` shot）

```
run-e2e-review.sh 捕获默认首帧
  │
  ▼
01_title shot（若补入 e2e_shots.json）:
  - state: ""（无状态机，标题常显）
  - theme_absent: 默认灰背景（无 theme 时 Godot 默认灰底，断言背景非主题色即可区分渲染成功）
  - assert_text: 版本标签节点路径 → "v0.1.0"（文本断言，验证标题场景真实加载而非空场景）
  │
  ▼
截图含「山东抗日之狼」标题 + 版本标签 → 冒烟通过（非灰屏证据）
```

### 4.3 流程 3：失败路径（run/main_scene 配置错误）

```
project.godot run/main_scene 路径写错（如 res://scenes/Mainn.tscn）
  │
  ▼
godot --path shandong-wolf/ --headless --quit
  → 报错 "Cannot open file 'res://scenes/Mainn.tscn'"
  → 非零退出码 → CI 失败 → implement 修复路径
  （PRD §5.2 边界 #4：本地必跑该命令，路径错误直接暴露）
```

---

## 5. 边界情况与错误处理

| # | 边界场景 | 缓解措施 |
|---|---------|---------|
| 1 | E2E 截图发生在启动早期（标题未渲染完成） | 方案 A 零动画 → 标题**首帧即默认可见**；截图 settle_frames ≥ 10（仿 mini-pong `01_title` shot 惯例），双保险 |
| 2 | headless 模式（CI）下 Label 渲染 | headless 仍完整实例化场景树；`--headless --quit` 退出码 0 验证加载链，渲染正确性由 review E2E 截图裁决（PRD §5.2 边界 #2） |
| 3 | 中文字体缺失导致标题豆腐块 | Godot 4.x 内置默认字体含 CJK（mini-pong 中文 Label 先例已核实）；若截图发现缺字 → 引入程序化位图字体（generate_pixel_font.py 已有），列为 review 期修复项（PRD §5.2 边界 #3） |
| 4 | `run/main_scene` 路径写错 | implement 后本地必跑 `godot --path shandong-wolf/ --headless --quit`；路径错误报 `Cannot open file` 直接失败（§4.3 流程 3） |
| 5 | e2e_shots.json 仍为占位（states 空）导致 review 无 shot 可跑 | 本设计给出 `01_title` shot 完整设计（§4.2，state "" 兼容无状态机场景）；不补则 review agent 用 run-e2e-review.sh 默认捕获兜底（PRD §5.2 边界 #5） |
| 6 | 窗口 1280x720 下标题字号溢出 | 「山东抗日之狼」6 字 × font_size 64 ≈ 384px < 1280 宽；CenterContainer 居中自适应；版式验收以 E2E 截图为准（PRD §5.2 边界 #6） |
| 7 | 并发 agent 污染 worktree / 误改其他游戏 | worktree-commit.sh 白名单 add（只 add 本 issue 文件）；stage-gate + review diff 检查拦截 mini-pong/ 或 manifest 改动（PRD §5.3 失败路径 #1） |
| 8 | implement 误改占位测试导致 CI 红 | 红线明确 tests/ 三文件不改（§3 不改动表）；若 CI 红先查 diff 是否越界，而非修测试 |
| 9 | 版本标签文字与项目版本不一致（后续版本迭代） | v0.1.0 骨架期硬编码可接受（PRD §1.4）；后续引入 constants.gd 时迁移（方案 B 延后项），本 issue 不处理 |

---

## 6. 集成点（AC 映射）

> **状态约定：** ⬜ = pending（文档约定，待 implement 落地）；✅ = connected（implement agent 落地后更新，review agent 验证）。

| 集成 | 本设计组件 | 验证方 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| AC1: SPAWN 携带 game=shandong-wolf | —（零改动） | dispatcher/event-processor | event-processor.py 从 manifest `game.active` 读 ACTIVE_GAME（已核实 L1059），输出可查 | ✅ 已生效 |
| AC2: research 侦查全 $GAME_DIR | —（零改动） | 本 PRD/DESIGN 自查 | 全部代码路径前缀 `shandong-wolf/`；`grep -rn "mini-pong" docs/PRD/559-*.md` 仅命中参考说明 | ✅ 已满足 |
| AC3: implement diff 只落 shandong-wolf/ | Main.tscn + project.godot（+ 可选 e2e_shots.json） | stage-gate + review | worktree-commit.sh 白名单 add；review diff 检查 | ⬜ pending |
| AC4: CI 日志 GAME_DIR=shandong-wolf | —（零改动） | CI | opencode-review.yml L44-50 已 manifest 参数化（已核实），implement PR 合入后日志含 `active game: shandong-wolf (dir: shandong-wolf)` | ⬜ pending（随 implement 生效） |
| AC5: review E2E 截图可见标题 | TitleLabel 启动即默认可见 | review | 首帧截图含「山东抗日之狼」，非灰屏；截图前无需按键 | ⬜ pending |
| AC6: post-merge GDD 写入分目录 | —（零改动） | review | review agent merge 后写 `docs/GAME_DESIGN/shandong-wolf/`（INDEX.md 已就位） | ⬜ pending |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | 新建 `shandong-wolf/scenes/Main.tscn` + 改 `shandong-wolf/project.godot` 一行 | 0.5 天内（含本地验证） |
| Phase 2 | P1（可选） | 补 `shandong-wolf/e2e_shots.json` 的 `01_title` shot | 0.5 天内 |

**Phase 1 验收命令（implement agent 本地必跑）：**
1. `godot --path shandong-wolf/ --headless --quit` → 退出码 0（主场景可解析加载）
2. `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` → 全绿
3. `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` → 全绿
4. `godot --path shandong-wolf/ --headless --script tests/smoke_test.gd` → 全绿
5. （有图形环境时）`godot --path shandong-wolf/` 启动截图 → 可见标题（AC5 本地预检）

**提交纪律（红线，PRD §8）：** 只 add `shandong-wolf/` 下文件；commit message 形如 `feat(shandong-wolf): add Main.tscn title scene for #559`；PR body 用 `Parent #559`（无冒号，workflow-chain.yml 依赖）。

---

## 8. 测试用例描述

> **注意：** 以下为测试**场景描述**，不写可运行测试代码（plan 阶段红线）。implement agent 依此实现；占位测试文件（run_tests/smoke_test/check_compile）本 issue 不改。

### 场景 A：主场景加载链（CI smoke 等价）
- **Test A1 — headless 启动退出码**：`godot --path shandong-wolf/ --headless --quit`。前置：Main.tscn 已建、`run/main_scene` 已指向。预期：退出码 0，无 `Cannot open file` 报错。
- **Test A2 — run/main_scene 指向正确**：检查 `project.godot` `[application]` 段 `run/main_scene="res://scenes/Main.tscn"` 且文件存在于 `shandong-wolf/scenes/`。预期：路径解析成功（A1 已隐式覆盖，此处为显式配置断言）。

### 场景 B：CI 三命令回归（不破坏骨架占位测试）
- **Test B1 — check_compile 全绿**：`godot --path shandong-wolf/ --headless --script tests/check_compile.gd`。前置：无 .gd 改动（方案 A 零脚本）。预期：遍历 gdscripts/ + tests/ 全部 load 成功，退出码 0。
- **Test B2 — run_tests 全绿**：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd`。预期：占位测试退出码 0（「skeleton — no tests yet」不报错）。
- **Test B3 — smoke_test 全绿**：`godot --path shandong-wolf/ --headless --script tests/smoke_test.gd`。预期：输出 `SMOKE OK: shandong-wolf skeleton loads`，退出码 0。

### 场景 C：E2E 视觉冒烟（AC5 证据，review 阶段）
- **Test C1 — 启动首帧非灰屏**：review E2E 截图（settle_frames ≥ 10，无需按键）。前置：游戏启动至主场景。预期：截图可见「山东抗日之狼」大标题，非默认灰屏/黑屏。
- **Test C2 — 版本标签可见**：截图左下角可见 `v0.1.0` 版本标签（font_size 16，低调呈现）。预期：文本正确渲染，无豆腐块。

### 场景 D：e2e_shots.json 视觉断言（可选，若 implement 补 `01_title` shot）
- **Test D1 — assert_text 版本标签**：`01_title` shot 配置 `assert_text` 指向 VersionLabel 节点路径，期望文本 `v0.1.0`。前置：shot 配置生效。预期：L3 断言通过（自动验证标题场景真实加载，而非空场景截图）。
- **Test D2 — theme_absent 背景断言**：shot 配置 `theme_absent`（默认灰背景色）。预期：截图背景与默认灰底一致，无意外主题色（区分渲染成功与空场景）。

### 场景 E：红线与解耦回归（AC2/AC3/AC4 验证，review 阶段）
- **Test E1 — diff 范围检查**：implement PR 的 diff 只落在 `shandong-wolf/` 下（Main.tscn 新建、project.godot 一行、可选 e2e_shots.json）。前置：PR 已开。预期：`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/` 零改动。
- **Test E2 — 无 mini-pong 写死**：`grep -rn "mini-pong" docs/PRD/559-*.md docs/DESIGN/559-*.md`。预期：仅命中参考说明（「mini-pong 仅作结构参考」），不命中任何代码路径。
- **Test E3 — CI 日志 GAME_DIR**：implement PR 合入后查看 CI 日志。预期：出现 `active game: shandong-wolf (dir: shandong-wolf)`，compile/test/smoke 均对 `shandong-wolf/` 执行。

### 场景 F：字体与版式（review 兜底）
- **Test F1 — CJK 渲染无豆腐块**：截图放大检查标题「山东抗日之狼」与版本标签。预期：全部字符正常渲染（Godot 内置默认字体含 CJK，先例：mini-pong 中文 Label）。
- **Test F2 — 标题不溢出**：1280x720 窗口下标题居中且完整显示。预期：6 字 × 64px ≈ 384px < 1280px，无截断/溢出。

---

## 9. 风险与缓解

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| implement 误改 mini-pong/ 或 manifest（AC3 红线） | 中 | worktree-commit.sh 白名单 add + stage-gate + review diff 检查（Test E1）；PRD §8 红线明示 |
| 中文字体缺字（豆腐块） | 低 | 内置默认字体含 CJK（先例已核实）；截图裁决，缺字则引入程序化位图字体（Test F1） |
| E2E 占位 shot 计划导致视觉断言缺失 | 低 | 本设计给出 `01_title` shot 完整设计；最坏情况 review 手动截图兜底（Test D1/D2 可选） |
| CI 上 GAME_DIR 解析异常（P3 回归） | 低 | opencode-review.yml 已参数化（已核实 L44-50）；若日志仍显示 mini-pong 则回查 manifest，属 P3 回归另立 issue（Test E3） |
| run/main_scene 路径写错 | 低 | implement 本地必跑 headless 启动命令，路径错误直接报 `Cannot open file`（Test A1） |
| 方案 B 诉求（参数化/淡入）被误带入本 issue | 低 | 本设计 §2.2 明确延后；版本号骨架期硬编码可接受（PRD §1.4） |

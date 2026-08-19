# Design: [Test] 结论文件骨架机制回归 — review 全链路 (P2 3738e82)

> **Parent Issue:** #563
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4.1 推荐 —— **方案 A**（Main.tscn 静态 SubtitleLabel 节点，~6 行 tscn），确认采纳；方案 B（GDScript 运行时创建）、方案 C（主题化副标题）显式否决
> **Reference PRD:** `docs/PRD/563-conclusion-skeleton-regression.md`（research PR #564 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/559-shandong-wolf-pipeline-smoke.md`（#562 实现的标题场景，本设计在其 VBoxContainer 内追加一个节点）
> **所有权:** `content_ownership: mechanical`（副标题 = 管线冒烟验证物，文案用 issue 指定文本『雪夜 · 大刀 · 山东村』，无品味裁决空间）
> **深度:** light（issue 无 depth/ 标签 → 按 light 处理）—— 只产出 DESIGN 文档，**不产 TASKS 文档**；测试仅描述不写代码（plan 阶段红线）
> **红线:** 只动 `shandong-wolf/scenes/Main.tscn`（+ 可选 `shandong-wolf/e2e_shots.json`）；**绝不触碰** `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`agents/skills/`（管线脚本是本次回归的**验证对象**，不是改动对象）

---

## 1. 架构总览

**本 issue 是测试 issue，交付物分两层：场景侧一个最小可见的副标题 Label + 管线侧一次真实全链路回归**（research→plan→implement→CI→E2E→review）。AC1–AC5 是**管线自身行为的验证项**，由本次 issue 走完全链路来实证；implement 的唯一代码交付物是 AC6 的副标题 Label。任何阶段都不得为「让骨架机制看起来生效」而修改 event-processor/watchdog/review skill 代码（PRD §1.2 注、§4.2 边界声明）。

**设计哲学：最小冒烟语义 + 克制纪律（延续 #559 同一哲学）。** 副标题是驱动管线走一遍的机械冒烟物——「视觉可见但 diff 极小」（issue body 原文）：在 #562 已落地的 `Main.tscn` VBoxContainer 内、TitleLabel 之后追加一个静态 Label 节点即完成场景侧交付。零脚本、零资源、零动画，启动首帧即可见（E2E 截图不依赖按键/状态机）。文案『雪夜 · 大刀 · 山东村』= 游戏原名「雪夜大刀」（brief §1）＋ 场景「山东村」的主题浓缩，由 issue 指定，无品味裁决。

```
                    ★ Issue #563 本设计（shandong-wolf 最小 diff + 管线回归载体）
┌───────────────────────────────────────────────────────────────────────────┐
│ shandong-wolf/scenes/Main.tscn（修改，唯一代码改动，#562 已存在结构）          │
│   Main (Node2D)                                                             │
│   └── CanvasLayer (layer=1)                                                 │
│       ├── CenterContainer (全屏锚点 anchors_preset=15)                       │
│       │   └── VBoxContainer (alignment=1 居中)                               │
│       │       ├── TitleLabel    「山东抗日之狼」 font_size=64 居中（已有）       │
│       │       └── SubtitleLabel 「雪夜 · 大刀 · 山东村」 font_size=28 居中     │
│       │                        modulate=Color(1,1,1,0.8)   ← 本次追加        │
│       └── VersionLabel (左下锚点 anchors_preset=2)  「v0.1.0」（已有，不动）    │
└───────────────────────────────────┬───────────────────────────────────────┘
                                    │ 零管线改动（AC1–AC5 由本次 issue 自身走完验证）
                                    ▼
    implement PR 合入 → CI 绿 → E2E 截图含副标题 → review agent 读骨架填 verdict
    → review_followup 自动 merge → 结论文件删除 + e2e-state=reviewed + watchdog 无告警
    （3738e82 P2 骨架机制：骨架预生成 → 受控字段 → 脚本消费，本次全链路实证）
```

**与 PRD 方案裁决的一致性：** PRD §4.1 推荐方案 A（Main.tscn 静态 Label 节点），否决方案 B（GDScript 运行时创建——多一个脚本文件违反「diff 极小」，且引入脚本加载失败面）与方案 C（主题化——超出测试 issue 范围，引入品味裁决与 mechanical 所有权冲突）。本设计确认采纳方案 A；§2.2 明确方案 B/C 的延后边界。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实 origin/main） | 与 #563 的差距 |
|------|--------------------------------------------------------------|---------------|
| `shandong-wolf/scenes/Main.tscn` | ✅ #562 已落地：Main/CanvasLayer/CenterContainer/VBoxContainer/TitleLabel（64px 居中）+ VersionLabel（左下，16px, alpha 0.6） | ❌ VBoxContainer 内缺副标题节点 |
| `shandong-wolf/project.godot` | ✅ `run/main_scene="res://scenes/Main.tscn"` 已指向（#562 修复） | 无（**不改**） |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位：`states: {}`、`state_node: ""` | 可选补 `01_title` shot（§4.2） |
| `scripts/event-processor.py:2283` `_ensure_conclusion_skeleton(pr)` | ✅ 3738e82 已实现：SPAWN review 前预生成 `~/.hermes/review-conclusions/<PR>.json`（verdict=null，幂等不覆盖） | 无（**验证对象，不改**） |
| `scripts/workflow-watchdog.py:103` `check_conclusion_stale` | ✅ 3738e82 已实现：verdict 归一化（split `/|,|，|;|；` 取第一段 + lowercase）后不在规范集 → 立即 `review-verdict-invalid` 告警 | 无（**验证对象，不改**） |
| `agents/skills/game-review-agent/SKILL.md` | ✅ 3738e82 已改写：读骨架 → 只填 verdict/class/evidence/parent_issue/fix_issue → python 自检 | 无（**验证对象，不改**） |
| `shandong-wolf/tests/`（run_tests/smoke_test/check_compile） | ✅ 占位测试全绿 | 无（AC 未要求，**不改**） |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| Main.tscn 已有 Main → CanvasLayer → CenterContainer → VBoxContainer → TitleLabel「山东抗日之狼」64px；VersionLabel v0.1.0 左下 | ✅ 属实（origin/main 逐节点核实） | 在 VBoxContainer 内 TitleLabel 后追加 SubtitleLabel |
| 副标题插入位点为 VBoxContainer（TitleLabel 之后） | ✅ VBoxContainer alignment=1 垂直居中，追加节点自动排在 TitleLabel 下方 | 追加为 VBoxContainer 第三个子节点（与 TitleLabel 同容器，自动继承居中） |
| 副标题 font_size 28、居中、modulate alpha 0.8 | ✅ PRD §4.1 给出完整节点草案 | 采纳 PRD 节点草案（§2.1），仅补 uid 约定说明 |
| `run/main_scene` 已指向 Main.tscn（#562） | ✅ 属实（`[application]` 段） | 零改动，场景加载链继承 |
| e2e_shots.json 为占位（states 空、state_node 空） | ✅ 属实 | 可选补 `01_title` shot（§4.2），不补则 review 默认截图兜底 |
| 管线脚本（event-processor/watchdog/review skill）是验证对象 | ✅ 3738e82 实现已 merged、单元测试 +4 全绿，但无真实全链路实证 | 本次 issue 走完全链路即回归验证；**任何阶段不得改动这些文件** |

---

## 2. 新组件详细设计

### 2.1 `SubtitleLabel` 节点（Main.tscn 内新增，唯一新组件）

- **文件:** `shandong-wolf/scenes/Main.tscn`（修改，非新建文件）
- **节点结构（追加后）：**

```
CanvasLayer/CenterContainer/VBoxContainer
├── TitleLabel    (Label, 已有)
└── SubtitleLabel (Label, 新增)   ← parent="CanvasLayer/CenterContainer/VBoxContainer"
```

- **节点声明（tscn 追加 ~6 行，直接采用 PRD §4.1 草案）：**

```
[node name="SubtitleLabel" type="Label" parent="CanvasLayer/CenterContainer/VBoxContainer"]
text = "雪夜 · 大刀 · 山东村"
theme_override_font_sizes/font_size = 28
horizontal_alignment = 1
modulate = Color(1, 1, 1, 0.8)
```

- **关键属性表：**

| 属性 | 值 | 设计理由 |
|------|-----|---------|
| `text` | `雪夜 · 大刀 · 山东村` | issue 指定文案：游戏原名「雪夜大刀」＋ 场景「山东村」主题浓缩；mechanical 所有权，无品味裁决 |
| `theme_override_font_sizes/font_size` | 28 | 介于主标题（64）与版本标签（16）之间的副标题层级；9 字（含「·」）≈ 252px << 1280 宽，无溢出（PRD §5.2 边界 #4） |
| `horizontal_alignment` | 1（居中） | 与 TitleLabel 一致，VBoxContainer alignment=1 垂直居中下水平亦居中 |
| `modulate` | `Color(1, 1, 1, 0.8)` | 副标题质感：比主标题略低调，不抢戏（延续 #559 克制纪律；VersionLabel 亦用 alpha 0.6 同族手法） |

- **信号/状态/方法:** 无（纯静态 Label 节点，零脚本）
- **集成说明:** 无外部引用；E2E 断言通过节点路径 `CanvasLayer/CenterContainer/VBoxContainer/SubtitleLabel` 定位（§4.2 可选 shot 的 assert_text 目标；review 默认截图直接目视验证）。启动即默认可见（无动画 → 首帧命中 AC6）。

### 2.2 （方案 B/C 延后项，本 issue 不落地）

- **方案 B**（`shandong-wolf/gdscripts/main_title.gd` 运行时创建副标题）：文案参数化/入场动画留待后续视觉 issue；测试 issue 不需要动态能力，且多一个脚本文件 = 多一个 CI 编译/加载失败面（PRD §4.1 方案 B Cons）。
- **方案 C**（主题化：自定义字体/描边/淡入）：超出测试 issue 范围，引入品味裁决与 `content_ownership: mechanical` 冲突（PRD §4.1 方案 C Cons）。

---

## 3. 既有组件修改

| 文件 | 变更 | 性质 | 为什么 |
|------|------|:----:|--------|
| `shandong-wolf/scenes/Main.tscn` | VBoxContainer 内 TitleLabel 后追加 SubtitleLabel 节点（§2.1，~6 行 tscn） | 修改（唯一代码改动） | AC6 交付物：副标题启动即默认可见；diff 极小（issue body 明示「视觉可见但 diff 极小」） |
| `shandong-wolf/e2e_shots.json` | 可选：补 `01_title` shot（§4.2 给出完整设计） | 修改（可选，建议） | 使 AC6 的 L3 视觉断言自动化（assert_text 副标题）；不补则 review 以默认截图兜底（PRD §5.2 边界 #5） |

**明确不改动（红线 + AC 边界）：**

| 文件 | 为什么不改 |
|------|-----------|
| `scripts/event-processor.py`、`scripts/workflow-watchdog.py`、`agents/skills/game-review-agent/SKILL.md` | **验证对象，不是改动对象**（PRD §1.2 注、§4.2 边界声明）：AC1–AC5 由本次 issue 自身走完管线实证；若回归发现机制缺陷 → status/blocked 或后续修复 issue，不在本 issue diff 内硬解 |
| `shandong-wolf/tests/*.gd`（run_tests/smoke_test/check_compile） | 占位测试保持全绿（AC 未要求改动）；CI 三命令必须继续通过 |
| `shandong-wolf/project.godot` | #562 已设 `run/main_scene`，零改动 |
| `shandong-wolf/gdscripts/` | 方案 A 零脚本，不新建任何 .gd |
| `mini-pong/` 任何文件 | 红线：diff 只落 `shandong-wolf/`；mini-pong 仅作结构模式参考（VBox 堆叠 Label 先例） |
| `game-env/manifest.yaml` | 单一事实源（game.active: shandong-wolf 已生效），本 issue 只**消费**不修改 |
| `.github/workflows/` | CI 已 manifest 参数化，零改动 |
| `docs/GAME_DESIGN/shandong-wolf/` | review agent post-merge 按 INDEX.md 约定填充，plan 阶段不写 GDD |

---

## 4. 数据流

### 4.1 流程 1：正常路径（启动链 + AC6 场景加载断言）

```
godot --path shandong-wolf/ --headless --quit
  │
  ▼
project.godot 读取 run/main_scene = "res://scenes/Main.tscn"（#562 已设）
  │
  ▼
Main.tscn 实例化
  ├── CanvasLayer/CenterContainer/VBoxContainer/TitleLabel「山东抗日之狼」64px
  ├── CanvasLayer/CenterContainer/VBoxContainer/SubtitleLabel「雪夜 · 大刀 · 山东村」28px alpha 0.8  ← 本次新增
  └── CanvasLayer/VersionLabel「v0.1.0」16px alpha 0.6（左下）
  │
  ▼
退出码 0（主场景可解析加载，无 Cannot open file）→ CI L2 全绿
  │
  ▼
review E2E 截图（首帧）→ 可见主标题 + 副标题，非灰屏 → AC6 证据
```

### 4.2 流程 2：E2E 视觉断言（可选 `01_title` shot，AC6 自动化）

```
run-e2e-review.sh 捕获默认首帧
  │
  ▼
01_title shot（若补入 e2e_shots.json）:
  - state: ""（无状态机，标题常显）
  - assert_text: 节点路径 CanvasLayer/CenterContainer/VBoxContainer/SubtitleLabel → "雪夜 · 大刀 · 山东村"
  │
  ▼
L3 断言通过 → 副标题真实加载（而非空场景截图）→ AC6 自动化证据
（不补则 review 默认截图目视验证，PRD §5.2 边界 #5）
```

### 4.3 流程 3：管线骨架机制回归（AC1–AC5，本次 issue 的验证本体）

```
implement PR 合入 → CI 绿 → E2E 完成
  │
  ▼
event-processor SPAWN review
  └─ _ensure_conclusion_skeleton(pr)  ← 3738e82 P2: 预生成 ~/.hermes/review-conclusions/<PR>.json
       （pr / verdict=null / class=null / parent_issue=null / fix_issue=null / evidence=""；幂等不覆盖）   ← AC2
  │
  ▼
review agent 读骨架 → 只填受控字段（verdict/class/evidence/parent_issue/fix_issue）
  → verdict ∈ {approved, blocked, self_correct, request_changes}（四值之一）→ python 自检通过   ← AC3
  │
  ▼
watchdog check_conclusion_stale → verdict 归一化（复合值 'approve / merge' 取第一段 → 'approve' 合法）   ← AC4 归一化点
  │
  ▼
review_followup（event-processor）
  ├── approved → 自动 merge（不人工介入；LLM 不 merge）   ← AC4
  ├── blocked → +status/blocked + fix issue 创建/去重
  └── 消费后删除结论文件 + e2e-state=reviewed             ← AC5
      watchdog 无 review-verdict-unknown/invalid 告警     ← AC5
```

### 4.4 流程 4：失败路径（骨架机制回归失败）

```
review 阶段第一步 cat ~/.hermes/review-conclusions/<PR>.json
  ├── 文件不存在（SPAWN 未预生成）→ 机制回归失败项：按 review skill 兜底补写合法 JSON + 上报（PRD §5.2 边界 #8）
  ├── verdict 非规范自由文本 → watchdog 归一化后仍非法 → 立即 review-verdict-invalid 告警（3738e82 出口，不等 60min）→ 人工修正/重写（PRD §5.3 失败路径 #2）
  └── verdict=approved 但自动 merge 未触发 → 结论文件滞留 → watchdog 60min 滞留告警 → 人工排查（PRD §5.3 失败路径 #3）
```

---

## 5. 边界情况与错误处理

| # | 边界场景 | 缓解措施 |
|---|---------|---------|
| 1 | E2E 截图发生在启动早期（副标题未渲染） | 方案 A 零动画 → 副标题**首帧即默认可见**；截图 settle_frames ≥ 10（仿 #559 惯例），双保险（PRD §5.2 边界 #1） |
| 2 | headless 模式（CI）下 Label 渲染 | headless 仍完整实例化场景树；`--headless --quit` 退出码 0 验证加载链，渲染正确性由 review E2E 截图裁决（PRD §5.2 边界 #2） |
| 3 | 中文字体缺失导致副标题豆腐块 | Godot 4.x 内置默认字体含 CJK（mini-pong 中文 Label 先例已核实）；若截图发现缺字 → 引入程序化位图字体（generate_pixel_font.py 已有），列为 review 期修复项（PRD §5.2 边界 #3） |
| 4 | 副标题（含「·」9 字符）溢出 VBox 宽度 | font_size 28 居中 ≈ 9 字 × 28px ≈ 252px << 1280 宽，无溢出；版式以 E2E 截图为准（PRD §5.2 边界 #4） |
| 5 | e2e_shots.json 仍为占位（states 空）导致 review 无 shot 可跑 | 本设计给出 `01_title` shot 完整设计（§4.2，state "" 兼容无状态机场景）；不补则 review agent 用默认捕获兜底（PRD §5.2 边界 #5） |
| 6 | 结论文件骨架已存在（重审场景） | `_ensure_conclusion_skeleton` 幂等不覆盖；review agent 直接读既有骨架（PRD §5.2 边界 #6） |
| 7 | 骨架文件意外缺失（event-processor 未预生成） | review skill 兜底：按字段补写合法 JSON；同时标记机制回归失败项（PRD §5.2 边界 #8） |
| 8 | review agent 写非规范 verdict（自由文本/复合值） | watchdog 归一化（split 取第一段 + lowercase）后仍非法 → 立即 `review-verdict-invalid` 告警；复合值 'approve / merge' 归一化为合法 'approve' → 自动 merge（AC4 回归验证点，PRD §5.3 失败路径 #2） |
| 9 | 自动 merge 未触发（review_followup 未消费） | 结论文件滞留 → watchdog 60min 滞留告警；人工介入排查；验证 AC4 失败即机制回归失败（PRD §5.3 失败路径 #3） |
| 10 | 并发 agent 污染 worktree / 误改其他游戏 | worktree-commit.sh 白名单 add（只 add 本 issue 文件）；stage-gate + review diff 检查拦截 mini-pong/、manifest、pipeline 脚本改动（PRD §5.3 失败路径 #1） |
| 11 | implement 误改占位测试导致 CI 红 | 红线明确 tests/ 三文件不改（§3 不改动表）；若 CI 红先查 diff 是否越界，而非修测试 |
| 12 | 回归中发现骨架机制本身缺陷 | 走 status/blocked 或后续修复 issue，**不在本 issue diff 内硬解**（PRD §4.2 边界声明、§8 主要风险 ③） |

---

## 6. 集成点（AC 映射）

> **状态约定：** ⬜ = pending（文档约定，待 implement 落地）；✅ = connected（implement agent 落地后更新，review agent 验证）。AC1–AC5 为管线自身行为，由本次 issue 走完全链路实证，implement 阶段不产生代码改动。

| 集成 | 本设计组件 | 验证方 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| AC1: SPAWN 指令携带 game=shandong-wolf（回归） | —（零改动） | dispatcher/event-processor | event-processor.py 从 manifest `game.active` 读 ACTIVE_GAME（#559 已核实），本次 issue 全程在 shandong-wolf 上下文执行即回归验证 | ⬜ pending（随 implement 生效） |
| AC2: 结论文件骨架预生成（verdict=null 已存在） | —（零改动） | review agent | SPAWN review 时 `_ensure_conclusion_skeleton` 预生成；review 第一步验证骨架存在性 | ⬜ pending（review 阶段验证） |
| AC3: review agent 读骨架填规范 verdict + 自检 | —（零改动） | review agent | review skill 已固化「读骨架 → 填受控字段 → python 自检」（3738e82） | ⬜ pending（review 阶段验证） |
| AC4: review_followup 消费结论 → 自动 merge | —（零改动） | event-processor | verdict=approved → 自动 merge；复合值归一化（'approve / merge' → 'approve'）仍合法 | ⬜ pending（review 阶段验证） |
| AC5: 消费后删除 + e2e-state=reviewed + watchdog 无告警 | —（零改动） | event-processor / watchdog | 消费即删（幂等）；watchdog 无 `review-verdict-unknown/invalid` 告警 | ⬜ pending（review 阶段验证） |
| AC6: 副标题 Label 在 Main.tscn 可见 | SubtitleLabel（§2.1） | implement / review | 场景加载断言（headless 退出码 0）+ E2E 截图含副标题（非灰屏/非豆腐块） | ⬜ pending |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | `shandong-wolf/scenes/Main.tscn` 追加 SubtitleLabel 节点（~6 行 tscn） | 0.5 天内（含本地验证） |
| Phase 2 | P1（可选） | 补 `shandong-wolf/e2e_shots.json` 的 `01_title` shot | 0.5 天内 |

**Phase 1 验收命令（implement agent 本地必跑）：**
1. `godot --path shandong-wolf/ --headless --quit` → 退出码 0（主场景可解析加载）
2. `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` → 全绿
3. `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` → 全绿
4. `godot --path shandong-wolf/ --headless --script tests/smoke_test.gd` → 全绿
5. （有图形环境时）`godot --path shandong-wolf/` 启动截图 → 可见主标题 + 副标题（AC6 本地预检）

**提交纪律（红线，PRD §8）：** 只 add `shandong-wolf/` 下文件（Main.tscn + 可选 e2e_shots.json）；commit message 形如 `feat(shandong-wolf): add subtitle label for #563`；PR body 用 `Parent #563`（无冒号，workflow-chain.yml 依赖）。

---

## 8. 测试用例描述

> **注意：** 以下为测试**场景描述**，不写可运行测试代码（plan 阶段红线）。implement agent 依此实现；占位测试文件（run_tests/smoke_test/check_compile）本 issue 不改。AC1–AC5 的验证动作在 review 阶段执行并如实记录，不得为通过而改 pipeline 代码。

### 场景 A：主场景加载链（CI smoke 等价，AC6 前置）
- **Test A1 — headless 启动退出码**：`godot --path shandong-wolf/ --headless --quit`。前置：SubtitleLabel 已追加。预期：退出码 0，无 `Cannot open file` / 脚本解析报错。
- **Test A2 — tscn 结构断言**：检查 `Main.tscn` 中 SubtitleLabel 节点存在且 `parent="CanvasLayer/CenterContainer/VBoxContainer"`，位于 TitleLabel 之后。预期：节点路径解析成功（A1 已隐式覆盖，此处为显式结构断言）。

### 场景 B：CI 三命令回归（不破坏骨架占位测试）
- **Test B1 — check_compile 全绿**：`godot --path shandong-wolf/ --headless --script tests/check_compile.gd`。前置：无 .gd 改动（方案 A 零脚本）。预期：遍历 gdscripts/ + tests/ 全部 load 成功，退出码 0。
- **Test B2 — run_tests 全绿**：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd`。预期：占位测试退出码 0。
- **Test B3 — smoke_test 全绿**：`godot --path shandong-wolf/ --headless --script tests/smoke_test.gd`。预期：输出 `SMOKE OK: shandong-wolf skeleton loads`，退出码 0。

### 场景 C：E2E 视觉冒烟（AC6 证据，review 阶段）
- **Test C1 — 启动首帧可见副标题**：review E2E 截图（settle_frames ≥ 10，无需按键）。前置：游戏启动至主场景。预期：截图可见主标题「山东抗日之狼」下方副标题「雪夜 · 大刀 · 山东村」，非灰屏/黑屏。
- **Test C2 — 副标题层级与质感**：截图检查副标题（font_size 28、alpha 0.8、居中）位于主标题与版本标签之间的视觉层级。预期：副标题比主标题低调（alpha 0.8）、比版本标签醒目，无文字截断。

### 场景 D：e2e_shots.json 视觉断言（可选，若 implement 补 `01_title` shot）
- **Test D1 — assert_text 副标题**：`01_title` shot 配置 `assert_text` 指向 `CanvasLayer/CenterContainer/VBoxContainer/SubtitleLabel`，期望文本 `雪夜 · 大刀 · 山东村`。前置：shot 配置生效。预期：L3 断言通过（自动验证副标题真实加载）。
- **Test D2 — theme_absent 背景断言**：shot 配置 `theme_absent`（默认灰背景色）。预期：截图背景与默认灰底一致，无意外主题色（区分渲染成功与空场景）。

### 场景 E：管线骨架机制回归（AC1–AC5，review 阶段如实记录）
- **Test E1 — AC1 SPAWN 上下文**：implement PR 的 SPAWN 指令/CI 日志。预期：携带 `game=shandong-wolf`（或日志含 `active game: shandong-wolf (dir: shandong-wolf)`），无 mini-pong 上下文泄漏。
- **Test E2 — AC2 骨架预生成**：review 阶段第一步 `cat ~/.hermes/review-conclusions/<PR>.json`。预期：文件已存在且 `verdict: null`（SPAWN review 时预生成）；不存在即机制回归失败，按 review skill 兜底补写并上报。
- **Test E3 — AC3 受控字段 + 自检**：review agent 只填 verdict/class/evidence/parent_issue/fix_issue，verdict ∈ {approved, blocked, self_correct, request_changes}。预期：写后 `python3 -c "import json; json.load(...)"` 自检通过。
- **Test E4 — AC4 自动 merge（含复合值归一化）**：verdict=approved 后不人工介入。预期：`review_followup` 消费结论自动 merge；即使写 'approve / merge' 复合值，归一化取第一段（'approve'）仍合法 → merge。
- **Test E5 — AC5 消费后清理**：merge 后 `ls ~/.hermes/review-conclusions/`。预期：无该 PR 文件；`~/.hermes/e2e-state/<PR>.json` status=reviewed；watchdog 日志无 `review-verdict-unknown/invalid` 告警。

### 场景 F：红线与解耦回归（review 阶段）
- **Test F1 — diff 范围检查**：implement PR 的 diff 只落在 `shandong-wolf/` 下（Main.tscn 修改、可选 e2e_shots.json）。前置：PR 已开。预期：`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`agents/skills/` 零改动。
- **Test F2 — 无 mini-pong 写死**：`grep -rn "mini-pong" docs/PRD/563-*.md docs/DESIGN/563-*.md`。预期：仅命中参考说明（「mini-pong 仅作结构模式参考」），不命中任何代码路径。
- **Test F3 — 管线脚本零改动**：`git diff origin/main -- scripts/ agents/skills/`（implement PR 合并前）。预期：空 diff（验证对象未被误改）。

### 场景 G：字体与版式（review 兜底）
- **Test G1 — CJK 渲染无豆腐块**：截图放大检查副标题「雪夜 · 大刀 · 山东村」。预期：全部字符正常渲染（含「·」分隔符；Godot 内置默认字体含 CJK，先例：mini-pong 中文 Label）。
- **Test G2 — 副标题不溢出**：1280x720 窗口下副标题居中且完整显示。预期：9 字 × 28px ≈ 252px < 1280px，无截断/溢出。

---

## 9. 风险与缓解

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| implement 误改 mini-pong/、manifest 或 pipeline 脚本（AC 红线） | 中 | worktree-commit.sh 白名单 add + stage-gate + review diff 检查（Test F1/F3）；PRD §8 红线明示 |
| 中文字体缺字（豆腐块） | 低 | 内置默认字体含 CJK（先例已核实）；截图裁决，缺字则引入程序化位图字体（Test G1） |
| E2E 占位 shot 计划导致视觉断言缺失 | 低 | 本设计给出 `01_title` shot 完整设计；最坏情况 review 手动截图兜底（Test D1/D2 可选） |
| 骨架机制回归失败（AC2/AC4/AC5 不满足） | 中 | 如实记录为回归失败项（Test E2/E4/E5）→ status/blocked 或后续修复 issue；**不在本 issue diff 内硬解**（§5 #12） |
| review agent 写非规范 verdict（自由文本/复合值） | 低 | watchdog 归一化（复合值取第一段）+ 非法即告警（3738e82 出口）；复合值合法化路径即 AC4 回归验证点（Test E4） |
| 自动 merge 未触发（review_followup 未消费） | 低 | 结论文件滞留 → watchdog 60min 滞留告警 → 人工排查（Test E5） |
| 副标题文案/版式被误判为品味问题 | 低 | mechanical 所有权：文案由 issue 指定，无品味裁决空间；版式以 E2E 截图为准（§2.1） |
| 方案 B/C 诉求被误带入本 issue | 低 | §2.2 明确延后；静态 Label 是唯一实现（PRD §4.1 方案裁决） |

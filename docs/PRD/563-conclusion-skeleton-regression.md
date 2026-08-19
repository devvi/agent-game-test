# PRD #563 — [Test] 结论文件骨架机制回归 — review 全链路 (P2 3738e82)

> **Issue:** #563
> **标签:** enhancement, workflow/available, workflow/research（本阶段认领）, version/mvp；无 depth 标签 → 按 light 处理（§1–5 + §8 必填，§6 简述，§7 跳过并注明）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **深度:** light
> **所有权:** `content_ownership: mechanical`（副标题 = 管线冒烟验证物，无品味裁决；文案直接采用 issue 指定文本）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian` WebDAV 挂载，1213 个 md，wiki+raw 全量 grep 雪夜/大刀/山东/只狼/Sekiro/结论文件/骨架 → **0 命中**：游戏与结论文件机制均为 2026-08-18/19 全新主题，知识库无先例可循，属正常空结果，非工具降级）；事实来源 = 设计 brief（`docs/RAW/shandong-wolf-brief.md`）+ 仓库 pipeline 源码/文档（event-processor.py、workflow-watchdog.py、game-review-agent SKILL.md）
> **来源:** 任务指派（game-research-agent）
> **前置依赖:** #562（feat(559) Main.tscn 标题场景，已 merged）、3738e82（结论文件机制 P2 骨架生成 + 校验器 + watchdog 出口，已 merged）、4afe339（E2E 结论文件测试隔离，已 merged）

---

## 1. 问题定义

### 1.1 现状（2026-08-19 侦查）

本 issue 是**测试 issue**（issue body 明示「这是测试 issue，验证后关闭」），交付物分两层：**场景侧一个最小可见的副标题 Label** + **管线侧一次真实全链路回归**（research→plan→implement→CI→E2E→review）。

**场景侧（feature 现状）— `shandong-wolf/scenes/Main.tscn`（#562 已落地）：**

| 节点 | 类型 | 关键属性 | 说明 |
|------|------|---------|------|
| Main | Node2D | — | 根节点 |
| CanvasLayer | CanvasLayer | layer=1 | UI 层 |
| CenterContainer | CenterContainer | anchors_preset=15（全屏） | 居中容器 |
| VBoxContainer | VBoxContainer | alignment=1 | 垂直排列 |
| TitleLabel | Label | text=「山东抗日之狼」，font_size 64，居中 | 主标题 |
| VersionLabel | Label | text=v0.1.0，font_size 16，anchors_preset=2（左下） | 版本标签（在 CanvasLayer 下，不在 VBox 内） |

**缺口：** 主标题与版本标签之间**无副标题**。issue 要求增加副标题 Label『雪夜 · 大刀 · 山东村』——文案 = 游戏原名「雪夜大刀」（brief §1：原名"雪夜大刀"，2026-08-19 定名《山东抗日之狼》）＋ 场景「山东村」的主题浓缩，视觉可见但 diff 极小。

**管线侧（被验证对象现状）— 结论文件骨架机制（3738e82 P2）：**

| 组件 | 位置 | 机制 |
|------|------|------|
| 骨架预生成 | `scripts/event-processor.py:2283` `_ensure_conclusion_skeleton(pr)` | SPAWN review 前预生成 `~/.hermes/review-conclusions/<PR>.json`（pr / verdict=null / class=null / parent_issue=null / fix_issue=null / evidence=""）；已存在不覆盖（重审场景） |
| 合法性校验 | `scripts/workflow-watchdog.py:103` `check_conclusion_stale` | verdict 归一化（split `/|,|，|;|；` 取第一段 + lowercase）后不在规范集 → 立即 `review-verdict-invalid` 告警；JSON 解析失败同样告警（不等 60min 滞留） |
| 消费端 | event-processor `review_followup()` | verdict=approved → 自动 merge；blocked → +status/blocked + fix issue；消费后删文件 + e2e-state=reviewed |
| review agent 契约 | `agents/skills/game-review-agent/SKILL.md`（3738e82 改写） | 读骨架 → 只填 verdict/class/evidence/parent_issue/fix_issue → python 自检通过 |

**核心缺口：** P2 修复（3738e82）已落地并有单元测试（tests/pipeline +4），但**从未在真实全链路跑通**——骨架是否在 review agent 写入前真实存在、review agent 是否按受控字段填写、`review_followup` 是否消费后自动 merge、watchdog 是否无告警，全部待本次 issue 自身走完管线来实证。

### 1.2 验收条件（源自 Issue #563 body，映射到各阶段 agent）

| # | 验收条件 | 负责阶段 | 本 PRD 的保障措施 |
|---|---------|---------|------------------|
| AC1 | SPAWN 指令携带 game=shandong-wolf（回归） | dispatcher | event-processor.py 从 manifest game.active 读 ACTIVE_GAME（#559 已核实代码，无改动）；本次 issue 全程在 shandong-wolf 上下文执行即回归验证 |
| AC2 | E2E 完成后结论文件骨架预生成：~/.hermes/review-conclusions/<PR>.json 在 review agent 写入前已存在且 verdict=null | event-processor / review | 3738e82 `_ensure_conclusion_skeleton` 幂等预生成；review 阶段由 review agent 验证骨架存在性（skill 已改为「读骨架填字段」） |
| AC3 | review agent 读骨架填规范 verdict（四值之一）→ 写后自检通过 | review | review skill 已固化读骨架 + 自检流程（3738e82）；本 PRD 在 §8 交接中明示 review 阶段必须验证骨架存在 |
| AC4 | review_followup 消费结论 → **自动 merge**（不人工介入；即使 agent 写 'approve / merge' 复合值也归一化 merge） | event-processor | watchdog 归一化逻辑（L124）已覆盖复合值取第一段；本 issue 回归验证点 |
| AC5 | 结论文件消费后删除 + e2e-state=reviewed + watchdog 无 review-verdict-unknown/invalid 告警 | event-processor / watchdog | 消费即删（review_followup 幂等）；watchdog 无告警 = 合法契约闭环的证据 |
| AC6 | 副标题 Label 在 Main.tscn 可见（场景加载断言） | plan/implement/review | §5.1 AC6 落 check：场景加载断言 + E2E 截图可见（非灰屏） |

> 注：AC1–AC5 是**管线自身行为的验证项**，不是 implement 的交付物——它们由本次 issue 走完 research→plan→implement→CI→E2E→review 全链路来实证；implement 的**唯一代码交付物是 AC6 的副标题 Label**。plan/implement/review 各阶段不得为「满足 AC1-5」改动任何 pipeline 脚本。

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 管线全链路回归（本次 issue 本体） | 一次性 | issue 自身走完 research→plan→implement→CI→E2E→review，验证 3738e82 骨架机制在真实管线生效：骨架预生成 → agent 填受控字段 → 脚本消费自动 merge |
| B | review agent 读取骨架并填写 | 每次 impl PR | review agent 不再从零写 JSON，只填 verdict/class/evidence 等受控字段；写后自检通过 |
| C | 玩家/用户首启 | 手动 | `godot --path shandong-wolf/` 启动即见『山东抗日之狼』主标题 + 『雪夜 · 大刀 · 山东村』副标题 + v0.1.0 版本标签 |

### 1.4 范围边界（与 PRD #559 去冲突，Patch 14）

| PRD / 变更 | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| PRD #559（shandong-wolf 管线冒烟） | 创建 Main.tscn 标题场景（TitleLabel + VersionLabel）、run/main_scene 指向、P3 解耦回归 | ❌ 不重设计标题场景结构/节点树 — 只在既有 VBoxContainer 内**追加一个 SubtitleLabel 节点** |
| #562（feat(559) 实现，已 merged） | Main.tscn 落地（节点树已存在） | ❌ 不重建/重构 Main.tscn — 最小 diff 追加节点 |
| 3738e82（P2 骨架机制，已 merged） | event-processor/watchdog/review skill 的骨架机制实现 + 单元测试 | ❌ 不改 pipeline 任何脚本 — 本 issue 是**验证对象**，不是改动对象 |
| 本 PRD（#563） | 副标题 Label（最小 diff）+ 管线机制真实回归 | 副标题文案由 issue 指定（『雪夜 · 大刀 · 山东村』），无品味裁决空间；e2e_shots.json 补 shot 属 plan 阶段可选 |

### 1.5 预期行为（最小冒烟语义）

- `shandong-wolf/scenes/Main.tscn` 加载后，标题下方可见副标题『雪夜 · 大刀 · 山东村』（启动即默认可见，不依赖按键/状态机）→ 任何启动截图即命中 AC6。
- 本次 issue 的 implement PR 合入后：CI 绿 → E2E 截图含副标题 → review agent 读骨架填 verdict → `review_followup` 自动 merge（不人工介入）→ 结论文件删除、e2e-state=reviewed、watchdog 无告警。

---

## 2. 设计意图

### 2.1 为什么现状如此

| 时间线 | 事件 | 后果 |
|--------|------|------|
| 2026-08-18/19 | shandong-wolf 注册 + brief 定稿（原名「雪夜大刀」→ 定名《山东抗日之狼》） | 主标题场景落地（#559/#562），但副标题未定义 |
| #562 死锁 | review agent 自由写 verdict='approve / merge' → 归一化缺陷 → 提前终态 → PR 永不 merge | 暴露「自由文本结论契约」缺陷，触发 P2 修复 |
| 3738e82（P2） | 骨架预生成 + 校验器 + watchdog 出口 + review skill 改受控字段 | 机制已实现、单元测试 +4 全绿，但**无真实管线实证** |

### 2.2 为什么现在改

P2 修复（3738e82）是有单元测试保障的代码级修复，但管线类机制（SPAWN/结论文件/watchdog/自动 merge）的价值只在**真实全链路**中体现——单元测试覆盖不到跨 agent、跨进程、跨时间的编排行为。本 issue 即为此而生：一个 diff 极小（副标题 Label）的机械冒烟物，驱动完整管线走一遍，验证骨架机制在真实 review 环节生效（issue body 明示「验证 2026-08-19 结论文件机制加固在真实管线中生效」）。测试 issue，验证后关闭。

### 2.3 既有约束

| 约束 | 详情 |
|------|------|
| 引擎 | Godot 4.7.1（manifest engine.version） |
| 目录 | 只动 `shandong-wolf/`（manifest game.active: shandong-wolf）；绝不触碰 `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`agents/skills/` |
| diff 规模 | 「视觉可见但 diff 极小」——一个 Label 节点 |
| 版本 | mvp（version/mvp label） |
| 所有权 | mechanical（无品味裁决，文案用 issue 指定文本） |
| 可见性 | 副标题启动即默认可见（E2E 截图不依赖按键） |
| 结论文件 | 只填受控字段（verdict 四值：approved / blocked / self_correct / request_changes），禁自由文本/复合值 |

---

## 3. 影响分析

### 3.1 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/scenes/Main.tscn` | 标题场景 | **修改（唯一代码改动）**：VBoxContainer 内 TitleLabel 后追加 SubtitleLabel 节点（text=『雪夜 · 大刀 · 山东村』） |

### 3.2 新建文件

无（方案 A 零脚本；若 plan 选择加 `gdscripts/main_title.gd` 则属方案 B 否决项，见 §4）。

### 3.3 间接受影响的模块（验证对象，非改动对象）

| 文件 | 模块 | 影响 |
|------|------|------|
| `scripts/event-processor.py` | SPAWN/结论文件骨架 | 零改动；本次 issue 的 implement PR 触发其 `_ensure_conclusion_skeleton` 与 `review_followup` 路径 |
| `scripts/workflow-watchdog.py` | verdict 合法性检测 | 零改动；回归验证无 `review-verdict-unknown/invalid` 告警 |
| `agents/skills/game-review-agent/SKILL.md` | review 契约 | 零改动；验证「读骨架填字段 + 自检」流程 |
| `shandong-wolf/e2e_shots.json` | E2E shot plan | 可选：补 `01_title` shot（state ""、assert_text 副标题）使 L3 视觉断言自动化；不补则以默认截图为准（#559 同款结论） |
| `docs/GAME_DESIGN/shandong-wolf/` | GDD | review agent post-merge 按功能域填充（本阶段不写） |

### 3.4 数据流影响（结论文件骨架机制全链路）

```
SPAWN review (event-processor)
    │  _ensure_conclusion_skeleton(pr)  ← 3738e82 P2: 预生成骨架 verdict=null
    ▼
~/.hermes/review-conclusions/<PR>.json  ← 骨架已存在（幂等，重审不覆盖）
    │  review agent 读骨架 → 只填受控字段（verdict/class/evidence/parent_issue/fix_issue）
    │  → python 自检通过
    ▼
watchdog check_conclusion_stale ──► verdict 归一化（复合值取第一段）──► 非法 → review-verdict-invalid 告警
    │                                     │ 合法
    ▼                                     ▼
review_followup (event-processor)     （本次回归目标：无告警）
    ├── approved ──► 自动 merge（LLM 不 merge）
    ├── blocked ──► +status/blocked + fix issue 创建/去重
    └── 消费后删除结论文件 + e2e-state=reviewed  ← AC5
```

### 3.5 需更新的文档

- [x] 本 PRD（`docs/PRD/563-conclusion-skeleton-regression.md`）
- [ ] GDD shandong-wolf 章节 — review agent post-merge 填充（非本阶段）
- [ ] e2e_shots.json — plan 阶段可选补 shot

---

## 4. 方案对比

### 4.1 副标题实现方式（feature 侧，唯一实现决策）

**方案 A：Main.tscn 静态 Label 节点（推荐）**

在 `CanvasLayer/CenterContainer/VBoxContainer` 内、TitleLabel 之后追加一个 Label 节点：

```gdscript
[node name="SubtitleLabel" type="Label" parent="CanvasLayer/CenterContainer/VBoxContainer"]
text = "雪夜 · 大刀 · 山东村"
theme_override_font_sizes/font_size = 28
horizontal_alignment = 1
modulate = Color(1, 1, 1, 0.8)
```

- **Pros:** diff 最小（~6 行 tscn）；零脚本、零资源；启动即渲染，天然满足「首帧可见」；与 #559 TitleLabel/VersionLabel 模式同构（mini-pong StartMenu 亦为 VBox 堆叠 Label）
- **Cons:** 无动画/交互（本 issue 不需要——测试冒烟物）
- **Risk:** Low（Godot 4.7 Label 成熟 API，mini-pong 已有同构实证）
- **Effort:** <0.5 人日

**方案 B：GDScript 运行时创建**

新建 `shandong-wolf/gdscripts/main_title.gd`，`@onready` 动态 `add_child` 副标题。

- **Pros:** 文案可参数化、可后续接动画
- **Cons:** 新增脚本文件违反「diff 极小」；引入运行时依赖（脚本加载失败则副标题消失）；测试 issue 不需要动态能力
- **Risk:** Med（多一个文件 = 多一个 CI 编译/加载失败面）
- **Effort:** 1 人日

**方案 C：主题化副标题（自定义字体/描边/淡入）**

- **Pros:** 视觉更精致
- **Cons:** 超出测试 issue 范围；引入品味裁决（与 `content_ownership: mechanical` 冲突）；依赖 generate_pixel_font.py 流程
- **Risk:** Med（审美裁决会阻塞机械管线冒烟）
- **Effort:** 2+ 人日

**推荐：方案 A。** 理由：① 本 issue 是管线回归载体，feature 只需「可见 + diff 极小」，方案 A 唯一满足；② 与 #559 既有模式（纯 tscn 静态 Label）一致，零新概念；③ 中文字体风险由 Godot 内置 CJK 字体兜底（#559 已验证）。

### 4.2 管线验证策略（AC1–AC5 侧）

无独立方案对比——AC1–AC5 由本次 issue **自身走完管线**实证，不属于 implement 的设计决策。边界声明：implement 不得为「让骨架机制看起来生效」而修改 event-processor/watchdog/review skill 任何代码；若回归中发现机制缺陷，属后续修复 issue（或 status/blocked 路径），不在本 issue diff 内。

---

## 5. 边界条件与验收标准

### 5.1 验收条件（正常路径）

- [x] **AC1: SPAWN 携带 game=shandong-wolf** — 本次 issue 从 research 起全程在 shandong-wolf 上下文（worktree 分支 `research/563-*` → `impl/563-*`），dispatcher 事件携带 game 参数；由 plan/implement 阶段验证 SPAWN 输出含 `game=shandong-wolf`
- [x] **AC2: 结论文件骨架预生成** — review 阶段第一步：`cat ~/.hermes/review-conclusions/<PR>.json` 必须已存在且 `verdict: null`（SPAWN review 时预生成）；不存在即机制回归失败，按 review skill 兜底补写并上报
- [x] **AC3: review agent 填规范 verdict + 自检** — verdict ∈ {approved, blocked, self_correct, request_changes}；写后 `python3 -c "import json; json.load(...)"` 自检通过
- [x] **AC4: review_followup 自动 merge** — 结论 verdict=approved 后不人工介入；即使 review agent 写 'approve / merge' 复合值，归一化取第一段（'approve'）仍合法 → 自动 merge
- [x] **AC5: 消费后删除 + e2e-state=reviewed + watchdog 无告警** — merge 后 `ls ~/.hermes/review-conclusions/` 无该 PR 文件；`~/.hermes/e2e-state/<PR>.json` status=reviewed；watchdog 日志无 `review-verdict-unknown/invalid`
- [x] **AC6: 副标题可见（场景加载断言）** — `godot --path shandong-wolf/ --headless --quit` 退出码 0；E2E 截图（run-e2e-review.sh 默认捕获）中『雪夜 · 大刀 · 山东村』可见（非灰屏/非豆腐块）；plan 阶段建议补 `e2e_shots.json` 的 `01_title` shot（assert_text 副标题）使断言自动化

### 5.2 边界条件

| # | 场景 | 处理 |
|---|------|------|
| 1 | E2E 截图发生在启动早期（副标题未渲染） | SubtitleLabel 无动画（方案 A）→ 首帧即可见；settle_frames ≥ 10（仿 #559 建议） |
| 2 | headless 模式（CI）下 Label 渲染 | headless 仍实例化场景树，`--quit` 冒烟通过即可；渲染正确性由 review E2E 截图保证 |
| 3 | 中文字体缺失导致豆腐块 | Godot 4.x 内置默认字体含 CJK（mini-pong 已实证）；若截图发现缺字 → 程序化位图字体（generate_pixel_font.py），列为 review 期修复项 |
| 4 | 副标题（含「·」分隔符 9 字符）溢出 VBox 宽度 | font_size 28 居中 ≈ 9 字 × 28px ≈ 252px << 1280 宽，无溢出；版式以 E2E 截图为准 |
| 5 | e2e_shots.json 仍为占位（states 空） | review 以 run-e2e-review.sh 默认捕获兜底；plan 阶段补 `01_title` shot 为可选优化 |
| 6 | 结论文件骨架已存在（重审场景） | `_ensure_conclusion_skeleton` 幂等不覆盖（L2292-2293）；review agent 直接读既有骨架 |
| 7 | 并发 agent 污染 worktree | worktree-commit.sh 白名单 add（只 add 本 PRD/实现文件），本阶段全程在 /tmp/wt-research-563 内操作 |
| 8 | 骨架文件意外缺失（event-processor 未预生成） | review skill 兜底：按字段补写合法 JSON（verdict/class/evidence 等）；同时标记机制回归失败项 |

### 5.3 失败路径

| # | 场景 | 处理 |
|---|------|------|
| 1 | implement 误改 mini-pong/ 或 manifest/pipeline 脚本 | stage-gate + review diff 检查拦截；红线条款在 §8 明示 |
| 2 | review agent 写非规范 verdict（自由文本） | watchdog 归一化后仍非法 → 立即 `review-verdict-invalid` 告警（不等 60min，3738e82 出口）；人工修正或重写，本次回归暴露即为验证目标之一 |
| 3 | 自动 merge 未触发（review_followup 未消费） | 结论文件滞留 → watchdog 60min 滞留告警；人工介入排查；验证 AC4 失败即机制回归失败 |
| 4 | E2E 截图灰屏/黑屏（场景加载失败） | 检查 run/main_scene 指向与 tscn 格式；`--headless --quit` 退出码 0 仅是加载通过，渲染层以截图证据裁决 |

---

## 6. 依赖与阻塞（light：简述）

| 依赖 | 状态 | 说明 |
|------|:----:|------|
| #562（feat(559) Main.tscn 标题场景） | ✅ merged | 本 issue 在其产物上追加副标题；无阻塞 |
| 3738e82（P2 骨架机制） | ✅ merged | 本 issue 的验证对象；无阻塞 |
| 4afe339（E2E 结论文件测试隔离） | ✅ merged | 防止测试泄漏污染真实结论目录；无阻塞 |
| manifest `game.active: shandong-wolf` | ✅ 已生效 | SPAWN/CI/worktree 全链路已指向 shandong-wolf |
| mini-pong StartMenu 模式参考 | ✅ 已落地 | 仅模式参考（VBox 堆叠 Label 结构） |

无阻塞项。依赖链：`#562 → 本 issue（#563）`；机制依赖：`3738e82 → 本 issue（回归验证）`。

---

## 7. Spike / 实验

Skipped per light 深度（issue 无 depth/ 标签；副标题为静态 Label 无技术风险，Godot 4.7 Label/VBoxContainer 均为成熟 API，#559/mini-pong 已有同构实证；管线机制侧由 3738e82 单元测试 + 本次真实回归共同覆盖，无需 spike）。

---

## 8. 交接上下文（Continuation Context）

**给 plan agent 的交接：**

**系统现状：** `shandong-wolf/scenes/Main.tscn` 已含标题场景（Main → CanvasLayer → CenterContainer → VBoxContainer → TitleLabel「山东抗日之狼」64px；VersionLabel v0.1.0 左下）。`run/main_scene=res://scenes/Main.tscn` 已指向。管线侧：3738e82 已实现结论文件骨架机制（event-processor 预生成 + watchdog 校验 + review skill 受控字段），本次 issue 全链路走完即回归验证。

**关键代码位点（plan 必读）：**
- `shandong-wolf/scenes/Main.tscn` — 唯一改动文件：VBoxContainer 内 TitleLabel 后追加 SubtitleLabel（text=雪夜 · 大刀 · 山东村，font_size 28，居中，modulate alpha 0.8 副标题质感）
- `scripts/event-processor.py:2283` `_ensure_conclusion_skeleton` — 骨架预生成（验证对象，**不改**）
- `scripts/workflow-watchdog.py:103` `check_conclusion_stale` — verdict 合法性检测（验证对象，**不改**）
- `agents/skills/game-review-agent/SKILL.md` — 结论文件写入段（读骨架填字段，**不改**）
- `shandong-wolf/e2e_shots.json` — 占位；可选补 `01_title` shot（assert_text 副标题）使 L3 视觉断言自动化

**推荐实现路径（方案 A）：**
1. `shandong-wolf/scenes/Main.tscn` 追加 SubtitleLabel 节点（~6 行 tscn，见 §4.1）
2. 本地验证：`godot --path shandong-wolf/ --headless --quit`（退出码 0）＋ `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`（全绿）
3. 可选：`e2e_shots.json` 补 `01_title` shot
4. 提交时只 add `shandong-wolf/` 下文件（红线），PR body 用 `parent #563`

**验收/验证指令（review 阶段对照）：** ① E2E 截图含副标题『雪夜 · 大刀 · 山东村』（AC6）；② 结论文件骨架在写入前已存在且 verdict=null（AC2）；③ review agent 只填受控字段 + 自检（AC3）；④ verdict=approved → 自动 merge 不人工介入（AC4）；⑤ 消费后删除 + e2e-state=reviewed + watchdog 无告警（AC5）。AC1–AC5 是**管线自身行为**，review 阶段如实记录即可，不得为通过而改 pipeline 代码。

**主要风险：** ① 误改 mini-pong/、manifest、pipeline 脚本（红线：diff 只落 `shandong-wolf/scenes/Main.tscn`，stage-gate/review 拦截）；② 中文字体缺字（内置默认字体含 CJK，截图裁决）；③ 骨架机制回归失败（AC2/AC4 不满足 = 验证目标达成反面结果，走 status/blocked 或后续修复 issue，不在本 issue diff 内硬解）。

**红线：** 只动 `shandong-wolf/scenes/Main.tscn`（+ 可选 `e2e_shots.json`）；**绝不触碰** `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`agents/skills/`；副标题启动即默认可见；PR body 用 `parent #563`（小写 p）；本 PR 不 merge（research 阶段产物）。

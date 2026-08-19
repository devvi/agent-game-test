# Design: [Test] post-merge 阶段回归 — GDD 落盘 + docs PR 自动合并 (08-19)

> **Parent Issue:** #567
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4.2 推荐 —— **方案 A**（纯 tscn 声明式 Label 节点，CanvasLayer 直属，~10 行 tscn），确认采纳；方案 B（探针 .gd 脚本 + @export 配置）、方案 C（自定义 Theme/字体资产）显式否决
> **Reference PRD:** `docs/PRD/567-post-merge-probe.md`（research PR #568 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/563-conclusion-skeleton-regression.md`（同类测试 issue：静态 Label + 管线全链路回归，本设计镜像其结构）；`docs/DESIGN/559-shandong-wolf-pipeline-smoke.md`（Main.tscn 场景结构，#562 落地）
> **所有权:** `content_ownership: mechanical`（探针 = 管线冒烟验证物，文案用 issue 指定文本『post-merge probe』，无品味裁决空间）
> **深度:** light（issue 无 depth/ 标签 → 按 light 处理）—— 只产出 DESIGN 文档，**不产 TASKS 文档**；测试仅描述不写代码（plan 阶段红线）
> **红线:** 只动 `shandong-wolf/scenes/Main.tscn`（+ 可选 `shandong-wolf/e2e_shots.json`）；**绝不触碰** `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`agents/skills/`（管线脚本是本次回归的**验证对象**，不是改动对象）、`docs/GAME_DESIGN/`（GDD 是 post-merge agent 职责，AC4/AC6）

---

## 1. 架构总览

**本 issue 是测试 issue，交付物分两层：场景侧一个最小可见的右下角探针 Label + 管线侧一次真实 post-merge 全链路回归**（research→plan→implement→CI→E2E→review→**merge→post-merge**）。AC1–AC8 是**管线自身行为的验证项**，由本次 issue 走完全链路来实证（eabb294 的 post-merge 机制已有 216 项单元测试覆盖，但从未在真实全链路跑通——`docs/gdd-<PR>` PR 是否真被 stalled scan 自动 merge、GDD 是否真落盘 main、post-merge-state 是否真置 done，全部待本次 issue 自身走完管线来实证）；implement 的唯一代码交付物是 **AC9 的探针 Label**。任何阶段都不得为「让 post-merge 机制看起来生效」而修改 event-processor/watchdog/post-merge skill 代码（PRD §1.2 注、§1.4 范围边界、§4.3 管线侧无方案选择）。

**设计哲学：最小冒烟语义 + 克制纪律（延续 #559/#563 同一哲学）。** 探针是驱动管线走一遍的机械冒烟物——「视觉可见但 diff 极小」（issue body 原文）：在 #562 已落地的 `Main.tscn` CanvasLayer 下、与 VersionLabel 同级追加一个静态 Label 节点即完成场景侧交付。零脚本、零资源、零动画，启动首帧即可见（E2E 截图不依赖按键/状态机）。文案『post-merge probe』= issue 指定 ASCII 文本，Godot 内置默认字体零压力渲染，无品味裁决。

```
                    ★ Issue #567 本设计（shandong-wolf 最小 diff + post-merge 管线回归载体）
┌───────────────────────────────────────────────────────────────────────────┐
│ shandong-wolf/scenes/Main.tscn（修改，唯一代码改动，#562 已存在结构）          │
│   Main (Node2D)                                                             │
│   └── CanvasLayer (layer=1)                                                 │
│       ├── CenterContainer (全屏锚点 anchors_preset=15)                       │
│       │   └── VBoxContainer (alignment=1 居中)                               │
│       │       ├── TitleLabel    「山东抗日之狼」 font_size=64 居中（已有）       │
│       │       └── SubtitleLabel 「雪夜 · 大刀 · 山东村」 font_size=28（#563 已有）│
│       ├── VersionLabel (左下 anchors_preset=2)  「v0.1.0」（已有，不动）        │
│       └── PostMergeProbeLabel (右下 anchors_preset=3) 「post-merge probe」     │
│                             font_size=16, alpha 0.6   ← 本次追加              │
└───────────────────────────────────┬───────────────────────────────────────┘
                                    │ 零管线改动（AC1–AC8 由本次 issue 自身走完验证）
                                    ▼
    implement PR 合入 → CI 绿 → review_followup 自动 merge（AC2）
    → ~/.hermes/post-merge-state/<PR>.json {status:pending}（AC3）
    → SPAWN: post-merge one-shot → post-merge agent 写 GDD
    → docs/gdd-<PR> 分支 + PR（AC4）→ stalled scan 自动 merge（AC5）
    → GDD 首章节 + INDEX 更新落盘 main（AC6）→ status=done（AC7）
    → watchdog 全程无 post-merge-stuck 告警（AC8）
    （eabb294 机制：merge 归脚本层，LLM 只写 GDD 内容）
```

**与 PRD 方案裁决的一致性：** PRD §4.2 推荐方案 A（CanvasLayer 直属声明式 Label 节点），否决方案 B（探针 .gd 脚本——新增文件违反最小 diff，冒烟验证物不需要逻辑，为验证物引入代码面 = 本末倒置，CI L0/L1 多一个编译/测试对象）与方案 C（自定义 Theme/字体——新增资产 + import 缓存噪音，探针是英文文本默认字体零压力，与开源优先调研结论「无成熟必要资产」相悖）。本设计确认采纳方案 A；§2.2 明确方案 B/C 的延后边界。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实 origin/main） | 与 #567 的差距 |
|------|--------------------------------------------------------------|---------------|
| `shandong-wolf/scenes/Main.tscn` | ✅ #562/#563 已落地：Main/CanvasLayer/CenterContainer/VBoxContainer/TitleLabel（64px）+ SubtitleLabel（28px, α0.8）+ VersionLabel（左下 anchors_preset=2, 16px, α0.6） | ❌ CanvasLayer 下缺右下角探针节点 |
| `shandong-wolf/project.godot` | ✅ `run/main_scene="res://scenes/Main.tscn"` 已指向（#562 修复） | 无（**不改**） |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位：`states: {}`、`state_node: ""`、`groups: {}` | 可选补 `01_title` shot（§4.2） |
| `docs/GAME_DESIGN/shandong-wolf/INDEX.md` | ⚠️ 占位「待填充」（review agent 备注为填充方，2026-08-19 起分游戏目录） | 无（**post-merge agent 职责**，AC4/AC6 验证项，implement 不得代写） |
| `scripts/event-processor.py`（review_followup / `post_merge_emitter` L2003+ / `_quick_stalled_scan` L1595+） | ✅ eabb294 已实现：merge 成功 → `~/.hermes/post-merge-state/<PR>.json` {status:pending} → 同 tick `SPAWN: post-merge`（emitted_at 防重发 one-shot）；`docs/` 前缀 PR mergeable → `STALLED: merge-pr` 自动 merge | 无（**验证对象，不改**） |
| `scripts/workflow-watchdog.py` | ✅ eabb294 已实现：pending + emitted_at 超 45min → `post-merge-stuck` 告警（GDD 悬空终局兜底，不静默） | 无（**验证对象，不改**） |
| `agents/skills/game-post-merge-agent/SKILL.md` | ✅ eabb294 已实现：worktree 隔离写 GDD/PROJECT.md → `docs/gdd-<N>` 分支 + PR → 轮询 MERGED → status=done；白名单 add（只含 `docs/GAME_DESIGN/` + `docs/PROJECT.md`） | 无（**验证对象，不改**） |
| `shandong-wolf/tests/`（run_tests/smoke_test/check_compile） | ✅ 占位测试全绿 | 无（AC 未要求，**不改**） |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| Main.tscn 已有 Main → CanvasLayer → CenterContainer → VBoxContainer → TitleLabel/SubtitleLabel；VersionLabel v0.1.0 左下 anchors_preset=2（offset_left=16, offset_top=-36, offset_right=400, offset_bottom=-12, grow_vertical=0） | ✅ 属实（origin/main 逐节点核实） | 在 CanvasLayer 下、VersionLabel 之后追加 PostMergeProbeLabel，anchors_preset=3 右下，offset 镜像 VersionLabel |
| 探针挂载层级为 CanvasLayer 直属（与 VersionLabel 同级），**不进 CenterContainer/VBox** | ✅ CanvasLayer 现有直属子节点 = CenterContainer + VersionLabel | 追加为 CanvasLayer 第三个直属子节点；不进 VBox 避免触发自动排列连锁 diff |
| 探针规格：anchors_preset=3、offset_left=-400 / offset_top=-36 / offset_right=-16 / offset_bottom=-12、grow_horizontal=0 / grow_vertical=0、text『post-merge probe』、font_size=16、modulate α0.6 | ✅ PRD §8.2 给出完整节点草案 | 采纳 PRD 节点草案（§2.1），offset 与 VersionLabel 严格镜像（16↔-16、400↔-400）——1280x720 下无重叠（VersionLabel 右缘 400 < 探针左缘 880） |
| e2e_shots.json 为占位（states 空、groups 空） | ✅ 属实 | 可选补 `01_title` shot（§4.2），不补则 review 默认截图兜底 |
| 管线脚本（event-processor/watchdog/post-merge skill）是验证对象，AC1–AC8 是验证项不是交付物 | ✅ eabb294/0f18c45 实现已 merged、216 项单测全绿，但无真实全链路实证 | 本次 issue 走完全链路即回归验证；**任何阶段不得改动这些文件**（PRD §1.4 范围边界） |
| `docs/GAME_DESIGN/shandong-wolf/INDEX.md` 为占位「待填充」，是 post-merge 填充对象 | ✅ 属实（INDEX.md 含「待填充」表项 + 占位说明） | plan/implement 不得代写；AC6 以回归前后 INDEX 变化为判据 |

---

## 2. 新组件详细设计

### 2.1 `PostMergeProbeLabel` 节点（Main.tscn 内新增，唯一新组件）

- **文件:** `shandong-wolf/scenes/Main.tscn`（修改，非新建文件）
- **节点结构（追加后）：**

```
CanvasLayer
├── CenterContainer（已有，不动）
│   └── VBoxContainer（已有，不动）
│       ├── TitleLabel（已有，不动）
│       └── SubtitleLabel（已有，不动）
├── VersionLabel（已有，不动）
└── PostMergeProbeLabel (Label, 新增)   ← parent="CanvasLayer"
```

- **完整 tscn 节点草案（implement agent 依此落位，字段逐项固化，硬约束为 node 名 / text / anchors_preset=3 / CanvasLayer 直属）：**

```gdscript
[node name="PostMergeProbeLabel" type="Label" parent="CanvasLayer"]
uid = "uid://..."                        # implement 时补唯一 uid（Godot 4.7 编辑器保存自动生成；手写须全仓库唯一）
anchors_preset = 3                       # 右下角（镜像 VersionLabel 的左下 anchors_preset=2）
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -400.0                     # 镜像 VersionLabel offset_right=400（对称宽度 384px）
offset_top = -36.0                       # 与 VersionLabel 一致
offset_right = -16.0                     # 镜像 VersionLabel offset_left=16（右缘距屏 16px）
offset_bottom = -12.0                    # 与 VersionLabel 一致（下缘距屏 12px）
grow_horizontal = 0                      # GROW_DIRECTION_BEGIN（锚在右下，向左生长，与镜像语义一致）
grow_vertical = 0                        # GROW_DIRECTION_BEGIN（向上生长，同 VersionLabel）
text = "post-merge probe"                # 精确匹配（含空格，无引号），AC9 断言硬约束
theme_override_font_sizes/font_size = 16 # 与 VersionLabel 一致
modulate = Color(1, 1, 1, 0.6)           # 视觉可见但克制（同 VersionLabel α0.6）
```

- **信号/状态属性/方法:** 无——纯声明式节点，零脚本、零信号、零方法（方案 A 的本质：无代码路径，CI 编译风险趋零）。
- **集成说明:** 启动链继承 `run/main_scene` 指向（#562 已就位），无需任何接线；E2E 断言按 node path `CanvasLayer/PostMergeProbeLabel` 寻址（§8 场景 C/D）。

### 2.2 （方案 B/C 延后项，本 issue 不落地）

| 延后项 | 来源 | 延后理由 | 落地条件 |
|--------|------|---------|---------|
| 探针 .gd 脚本（参数化文本/位置） | PRD §4.2 方案 B | 冒烟验证物不需要逻辑；新增脚本面违反「diff 极小」；为验证物引入代码面 = 本末倒置 | 未来探针需动态能力（如显示 merge commit hash）时再评估 |
| 自定义 Theme/字体资产 | PRD §4.2 方案 C | 探针为 ASCII 文本，Godot 内置默认字体零压力；新增资产 + import 缓存噪音违反「零资产骨架期」 | 游戏本体 UI 需要定制视觉时另行立项（不属本测试 issue） |

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `shandong-wolf/scenes/Main.tscn` | CanvasLayer 下追加 PostMergeProbeLabel 节点（§2.1 草案）；**现有节点（Main/CanvasLayer/CenterContainer/VBoxContainer/TitleLabel/SubtitleLabel/VersionLabel）零改动** | AC9 唯一代码交付物；最小 diff 冒烟 |

### 3.2 新建文件

无。不引入 .gd 脚本、.tres/.theme 资源、字体资产（PRD §4.1 开源优先调研结论：Godot 内置默认主题即成熟方案）。

### 3.3 不改动表（红线 + 解耦）

| 文件/目录 | 为什么不动 |
|-----------|-----------|
| `shandong-wolf/project.godot` | `run/main_scene` 已就位（#562），改一行即引入无谓 diff |
| `shandong-wolf/tests/`（run_tests/smoke_test/check_compile） | 占位测试全绿；探针是场景节点无脚本逻辑，AC 未要求新增测试 |
| `scripts/`、`.github/workflows/`、`agents/skills/` | **post-merge 机制的验证对象**（eabb294/0f18c45 已实现），本 issue 只回归不修改（PRD §1.4 范围边界 + §8.3 红线 ①） |
| `game-env/manifest.yaml` | `game.active: shandong-wolf` 已就位，单一事实源不可动 |
| `mini-pong/` | 非活动游戏，零触碰（manifest game.active 已切 shandong-wolf） |
| `docs/GAME_DESIGN/shandong-wolf/`、`docs/PROJECT.md` | **post-merge agent 职责**（AC4/AC6）；implement 代写 = 职责越界 + diff 白名单破坏（PRD §8.3 红线 ③） |

### 3.4 受影响测试文件

无——`tests/` 三文件保持现状；AC9 的验证靠场景加载断言（headless 退出码）+ E2E 截图，不新增/改写任何测试脚本（PRD §8.4）。

---

## 4. 数据流

### 4.1 流程 1：正常路径（启动链 + AC9 场景加载断言）

```
godot --path shandong-wolf/（无参数启动，run/main_scene 指向 Main.tscn）
  → Main.tscn 实例化：Main(Node2D) → CanvasLayer(layer=1)
      ├── CenterContainer 居中 → VBoxContainer → TitleLabel/SubtitleLabel（首帧可见）
      ├── VersionLabel（左下 v0.1.0，首帧可见）
      └── PostMergeProbeLabel（右下『post-merge probe』，首帧可见）  ← AC9
  → --headless --quit 退出码 0（场景可解析加载，无脚本报错）
  → review E2E 截图：右下角可见探针文本（非灰屏/黑屏）
```

### 4.2 流程 2：E2E 视觉断言（可选 `01_title` shot，AC9 自动化）

```
shandong-wolf/e2e_shots.json 补 01_title shot（若 implement 选择补）：
  groups.loop.match = ["gdscripts/.*\.gd", "scenes/.*\.tscn", "project\.godot"]
    （本 PR 改 Main.tscn 必然命中 → L3 视觉层被执行）
  shots[0] = {
    name: "01_title", state: "", theme_absent: 默认灰底,
    settle_frames: 10,
    assert_text: [
      { node: "CanvasLayer/PostMergeProbeLabel", prop: "text",
        equals: "post-merge probe" }        ← 精确匹配，node path 定位（PRD §5.2 边界 #8：多文本场景不得模糊匹配）
    ]
  }
  → L3 断言通过 = 探针真实加载且文本精确（AC9 自动化证据）
```

### 4.3 流程 3：post-merge 管线回归（AC1–AC8，本次 issue 的验证本体）

```
impl PR merged（review_followup/_try_merge 消费 approved 结论）
  │ 创建 ~/.hermes/post-merge-state/<PR>.json {status: pending}        ← AC3
  ▼
post_merge_emitter（每 tick 扫描，event-processor.py L2003+）
  ├── pending + 无 emitted_at ──► SPAWN: post-merge（one-shot，emitted_at 标记防重发）
  │                                   │
  │                                   ▼
  │                        post-merge agent（worktree 隔离）
  │                           ├── 写 docs/GAME_DESIGN/shandong-wolf/ 章节 + PROJECT.md
  │                           │    （白名单 add：只含 GDD 目录 + PROJECT.md）        ← AC4
  │                           └── docs/gdd-<PR> 分支 + PR（Parent #<PR>）
  │                                   │
  │                                   ▼
  │                        _quick_stalled_scan（docs/ 前缀 → mergeable）
  │                                   │
  │                                   ▼
  │                        STALLED: merge-pr 自动 merge（脚本层，LLM 不 merge）   ← AC5
  │                                   │
  │                                   ▼
  └── agent 轮询 docs PR MERGED ──► status=done ◄── GDD 落盘 origin/main
                                         │                              ← AC6/AC7
                                         ▼
              watchdog: 45min 无 done → post-merge-stuck 告警（本次应不触发，AC8）
```

### 4.4 流程 4：失败路径（post-merge 回归失败）

```
post-merge-state/<PR>.json
  ├── 文件未出现（merge 后无 pending）→ AC3 失败：检查 review_followup/_try_merge 是否真执行 merge、状态文件路径
  ├── pending 但 SPAWN 重发（emitted_at 缺失/状态机异常）→ one-shot 语义破坏 → 事件日志核对 emitted_at 唯一性
  ├── docs PR 卡住未 merge → stalled scan 45min 窗口 → post-merge-stuck 告警（AC8 失败信号）→ 人工介入调查脚本层
  ├── docs PR diff 越界（混入代码/其他目录）→ 白名单红线破坏 → docs PR 不得 merge，人工/脚本发现（AC4 失败）
  └── docs PR merged 但 status 未置 done → agent 轮询异常 → watchdog 兜底告警；人工核验 GDD 是否已落盘
  所有失败项：如实记录为回归失败（PRD §5.3），走 status/blocked 或后续修复 issue，**不在本 issue diff 内硬解**
```

---

## 5. 边界情况与错误处理

| # | 边界场景 | 缓解措施 |
|---|---------|---------|
| 1 | 探针节点名漂移（改名/拼写错） | node 名 `PostMergeProbeLabel` 为 AC9 硬约束（issue 指定命名，E2E/断言按名寻址）；implement 阶段逐字符核对（PRD §5.2 边界 #1） |
| 2 | 探针 text 漂移（翻译/改文案/丢空格） | text 必须精确等于 `post-merge probe`（含空格，无引号）；AC9 断言精确匹配，中文翻译即失败（PRD §5.2 边界 #2） |
| 3 | 探针位置错误（误入 VBox/锚点错） | 挂载层级硬约束 CanvasLayer 直属（不进 CenterContainer/VBox，避免连锁 diff）；anchors_preset=3 + offset 逐字段核对（PRD §5.2 边界 #4/#5） |
| 4 | 探针与 VersionLabel 重叠 | 右下（anchors_preset=3, 右缘 -16）vs 左下（anchors_preset=2, 左缘 16）：1280x720 下 VersionLabel 右缘 400 < 探针左缘 880，无重叠；**不得挪动 VersionLabel**（PRD §5.2 边界 #4） |
| 5 | E2E 截图发生在启动早期（探针未渲染） | 方案 A 零动画 → 探针**首帧即默认可见**；截图 settle_frames ≥ 10（仿 #559/#563 惯例），双保险 |
| 6 | e2e_shots.json 仍为占位（states/groups 空）导致 review 无 shot 可跑 | 本设计给出 `01_title` shot 完整设计（§4.2，state "" 兼容无状态机场景）；不补则 review agent 默认捕获兜底（PRD §5.2 边界 #8） |
| 7 | headless 模式（CI）下 Label 渲染 | headless 仍完整实例化场景树；`--headless --quit` 退出码 0 验证加载链，渲染正确性由 review E2E 截图裁决 |
| 8 | E2E 多文本场景（标题/副标题/版本/探针同时命中） | 断言必须按 node path（`CanvasLayer/PostMergeProbeLabel`）定位，不得用「任意文本包含」模糊匹配（PRD §5.2 边界 #8） |
| 9 | docs PR diff 越界（混入代码/其他目录文件） | post-merge agent 白名单 add 红线被破坏 → docs PR 不得 merge；review 证据阶段核对 diff 白名单（AC4，PRD §5.3 失败路径 #1） |
| 10 | post-merge SPAWN 重发 / docs PR 卡住 / status 未置 done | 观察 emitted_at 唯一性 + watchdog 45min `post-merge-stuck` 告警兜底（AC8 失败信号）→ 人工介入脚本层排查（PRD §5.3 失败路径 #2/#3） |
| 11 | implement 误改 pipeline 脚本/工作流/manifest | worktree-commit.sh 白名单 add + stage-gate + review diff 检查拦截（§8 场景 F）；CI 的 pipeline-tests 亦会拦截（0f18c45 后 CI 已能跑 pipeline 测试） |
| 12 | 回归中发现 post-merge 机制本身缺陷 | 走 status/blocked 或后续修复 issue，**不在本 issue diff 内硬解**（PRD §4.3、§8.5 主要风险 ③） |

---

## 6. 集成点（AC 映射）

> **状态约定：** ⬜ = pending（文档约定，待 implement 落地）；✅ = connected（implement agent 落地后更新，review agent 验证）。AC1–AC8 为管线自身行为，由本次 issue 走完全链路实证，implement 阶段不产生代码改动。

| 集成 | 本设计组件 | 验证方 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| AC1: 三层 CI 全过（L0 编译 / L1 逻辑 / L2 运行时） | —（零改动） | CI | implement PR 的 opencode-review.yml 三个 job 全绿；本 issue 只改场景节点无脚本 → L0 无新增编译面 | ⬜ pending（随 implement 生效） |
| AC2: review_followup 消费结论 → 自动 merge（无人工介入） | —（零改动） | event-processor | verdict=approved → 自动 merge（#563 已实证同链路；本次回归点再验证一次） | ⬜ pending（review 阶段验证） |
| AC3: post-merge-state pending + 同 tick SPAWN: post-merge（one-shot） | —（零改动） | event-processor | merge 后 `~/.hermes/post-merge-state/<PR>.json` 出现且 status=pending；emitted_at 唯一（不重发） | ⬜ pending（merge 后验证） |
| AC4: post-merge agent 创建 docs/gdd-<PR> 分支 + PR，diff 白名单 | —（零改动） | post-merge agent | skill 白名单 add（只含 `docs/GAME_DESIGN/shandong-wolf/` + `docs/PROJECT.md`）；review 核对 diff 范围 | ⬜ pending（merge 后验证） |
| AC5: stalled scan 自动 merge docs PR（无人工介入） | —（零改动） | event-processor | `_quick_stalled_scan` docs/ 前缀 + mergeable → `STALLED: merge-pr` 自动 merge（L1626-1635 已核实） | ⬜ pending（merge 后验证） |
| AC6: shandong-wolf GDD 首个章节 + 子目录 INDEX.md 更新 | —（零改动） | post-merge agent | `docs/GAME_DESIGN/shandong-wolf/` 出现 01-OVERVIEW 或对应功能域章节；INDEX.md 不再是占位「待填充」 | ⬜ pending（merge 后验证） |
| AC7: post-merge-state status=done（docs PR MERGED 后） | —（零改动） | post-merge agent | 轮询 docs PR merged → 写 status=done | ⬜ pending（merge 后验证） |
| AC8: 全程无 post-merge-stuck 告警（watchdog 45min 兜底未触发） | —（零改动） | watchdog | AC3→AC7 在 45min 窗口内完成；监控日志无 `post-merge-stuck` | ⬜ pending（merge 后验证） |
| AC9: PostMergeProbeLabel 在 Main.tscn 可见（text 精确匹配『post-merge probe』） | PostMergeProbeLabel（§2.1） | implement / review | 场景加载断言（headless 退出码 0）+ node path 寻址 text 精确匹配 + E2E 截图右下角可见 | ⬜ pending |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | `shandong-wolf/scenes/Main.tscn` 追加 PostMergeProbeLabel 节点（§2.1 草案，~10 行 tscn） | 0.5 天内（含本地验证） |
| Phase 2 | P1（可选） | 补 `shandong-wolf/e2e_shots.json` 的 `01_title` shot（§4.2） | 0.5 天内 |

**Phase 1 验收命令（implement agent 本地必跑）：**
1. `godot --path shandong-wolf/ --headless --quit` → 退出码 0（主场景可解析加载，含新节点）
2. `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` → 全绿
3. `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` → 全绿
4. `godot --path shandong-wolf/ --headless --script tests/smoke_test.gd` → 全绿
5. （有图形环境时）`godot --path shandong-wolf/` 启动截图 → 右下角可见『post-merge probe』（AC9 本地预检）

**提交纪律（红线，PRD §8）：** 只 add `shandong-wolf/` 下文件（Main.tscn + 可选 e2e_shots.json）；commit message 形如 `feat(shandong-wolf): add post-merge probe label for #567`；PR body 用 `Parent #567`（无冒号，workflow-chain.yml 依赖）。**不写 Closes #567**（issue 需保持打开走完 post-merge 回归后由 operator 关闭）。

---

## 8. 测试用例描述

> **注意：** 以下为测试**场景描述**，不写可运行测试代码（plan 阶段红线）。implement agent 依此实现；占位测试文件（run_tests/smoke_test/check_compile）本 issue 不改。AC1–AC8 的验证动作在 merge 后的 post-merge 阶段执行并如实记录，不得为通过而改 pipeline 代码。

### 场景 A：主场景加载链（CI smoke 等价，AC9 前置）
- **Test A1 — headless 启动退出码**：`godot --path shandong-wolf/ --headless --quit`。前置：PostMergeProbeLabel 已追加。预期：退出码 0，无 `Cannot open file` / 节点解析报错。
- **Test A2 — tscn 结构断言**：检查 `Main.tscn` 中 PostMergeProbeLabel 节点存在且 `parent="CanvasLayer"`，位于 VersionLabel 之后（CanvasLayer 第三个直属子节点）。预期：节点路径解析成功（A1 已隐式覆盖，此处为显式结构断言）。

### 场景 B：CI 三命令回归（不破坏骨架占位测试）
- **Test B1 — check_compile 全绿**：`godot --path shandong-wolf/ --headless --script tests/check_compile.gd`。前置：无 .gd 改动（方案 A 零脚本）。预期：遍历 gdscripts/ + tests/ 全部 load 成功，退出码 0。
- **Test B2 — run_tests 全绿**：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd`。预期：占位测试退出码 0。
- **Test B3 — smoke_test 全绿**：`godot --path shandong-wolf/ --headless --script tests/smoke_test.gd`。预期：输出 `SMOKE OK: shandong-wolf skeleton loads`，退出码 0。

### 场景 C：E2E 视觉冒烟（AC9 证据，review 阶段）
- **Test C1 — 启动首帧可见探针**：review E2E 截图（settle_frames ≥ 10，无需按键）。前置：游戏启动至主场景。预期：截图右下角可见『post-merge probe』，非灰屏/黑屏；与左下 v0.1.0 对称分布。
- **Test C2 — 探针位置与层级**：截图检查探针位于右下角（右缘距屏 ~16px、下缘距屏 ~12px），视觉层级与 VersionLabel 对称、克制（font_size 16、alpha 0.6）。预期：不挤占标题区，不与 VersionLabel 重叠。

### 场景 D：e2e_shots.json 视觉断言（可选，若 implement 补 `01_title` shot）
- **Test D1 — assert_text 探针**：`01_title` shot 配置 `assert_text` 指向 `CanvasLayer/PostMergeProbeLabel`，期望文本 `post-merge probe`（equals 精确匹配，node path 定位）。前置：shot 配置生效。预期：L3 断言通过（自动验证探针真实加载 + 文本精确）。
- **Test D2 — theme_absent 背景断言**：shot 配置 `theme_absent`（默认灰背景色）。预期：截图背景与默认灰底一致，无意外主题色（区分渲染成功与空场景）。

### 场景 E：post-merge 管线回归（AC1–AC8，merge 后阶段如实记录）
- **Test E1 — AC1 CI 三层全绿**：implement PR 的 L0/L1/L2 三个 job。预期：全绿；本 issue 无脚本改动 → L0 无新增编译面。
- **Test E2 — AC2 自动 merge**：review 结论 verdict=approved 后不人工介入。预期：`review_followup` 消费结论自动 merge（#563 同链路再验证一次）。
- **Test E3 — AC3 pending + one-shot SPAWN**：merge 后 `cat ~/.hermes/post-merge-state/<PR>.json`。预期：文件存在且 `status: pending`；同 tick 发射 `SPAWN: post-merge` 且 emitted_at 唯一（不重发）。
- **Test E4 — AC4 docs PR 分支 + diff 白名单**：post-merge agent 运行后 `gh pr list --search "docs/gdd in:headRefName"`。预期：存在 docs/gdd-<PR> 分支 PR；diff 只含 `docs/GAME_DESIGN/shandong-wolf/` + `docs/PROJECT.md`，无代码文件混入。
- **Test E5 — AC5 stalled scan 自动 merge**：docs PR 创建后不人工介入。预期：`_quick_stalled_scan` 识别 docs/ 前缀 + mergeable → `STALLED: merge-pr` 自动 merge；main 无直接 push 记录。
- **Test E6 — AC6 GDD 落盘**：docs PR merged 后检查 `docs/GAME_DESIGN/shandong-wolf/`。预期：出现首个章节（01-OVERVIEW 或对应功能域）；INDEX.md 不再是占位「待填充」。
- **Test E7 — AC7 status=done**：docs PR MERGED 后 `cat ~/.hermes/post-merge-state/<PR>.json`。预期：`status: done`。
- **Test E8 — AC8 无 watchdog 告警**：监控日志 grep post-merge-stuck。预期：全程无 `post-merge-stuck` 告警（AC3→AC7 在 45min 窗口内完成）。

### 场景 F：红线与解耦回归（review 阶段）
- **Test F1 — diff 范围检查**：implement PR 的 diff 只落在 `shandong-wolf/` 下（Main.tscn 修改、可选 e2e_shots.json）。前置：PR 已开。预期：`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`agents/skills/`、`docs/GAME_DESIGN/`、`docs/PROJECT.md` 零改动。
- **Test F2 — 无 mini-pong 写死**：`grep -rn "mini-pong" docs/PRD/567-*.md docs/DESIGN/567-*.md`。预期：仅命中参考说明（「mini-pong 仅作结构模式参考」），不命中任何代码路径。
- **Test F3 — 管线脚本零改动**：`git diff origin/main -- scripts/ agents/skills/ .github/`（implement PR 合并前）。预期：空 diff（验证对象未被误改）。

### 场景 G：UI 布局与可见性（review 兜底）
- **Test G1 — 右下角定位精确**：截图放大检查探针位置。预期：右下角（右缘 ~16px、下缘 ~12px），与左下 VersionLabel 严格镜像（offset_left=-400 ↔ offset_right=400、offset_right=-16 ↔ offset_left=16），无重叠。
- **Test G2 — 文本渲染完整**：截图检查『post-merge probe』全部字符正常渲染。预期：ASCII 文本 + 内置默认字体零压力，无截断/豆腐块（Godot 4.x 默认字体含 ASCII 全字符，先例：VersionLabel 渲染正常）。
- **Test G3 — 视觉克制**：探针 font_size 16、alpha 0.6。预期：可见但不喧宾夺主，不遮挡标题/版本标签。

---

## 9. 风险与缓解

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| implement 误改 mini-pong/、manifest、pipeline 脚本或 GDD（红线） | 中 | worktree-commit.sh 白名单 add + stage-gate + review diff 检查（Test F1/F3）；PRD §8.3 红线明示 |
| 节点规格漂移（改名/改 text/换位置/误入 VBox） | 中 | §2.1 草案逐字段固化（node 名 / text / anchors_preset=3 / CanvasLayer 直属为硬约束）；AC9 断言 node path + 精确文本双保险（Test A2/C1） |
| post-merge 管线回归失败（AC3–AC8 不满足） | 中 | 如实记录为回归失败项（Test E3–E8）→ status/blocked 或后续修复 issue；**不在本 issue diff 内硬解**（§5 #12）；watchdog 45min 告警兜底 |
| docs PR diff 越界（白名单红线破坏） | 中 | review 证据阶段核对 diff 白名单（AC4，Test E4）；越界 PR 不得 merge |
| E2E 占位 shot 计划导致视觉断言缺失 | 低 | 本设计给出 `01_title` shot 完整设计；最坏情况 review 手动截图兜底（Test D1/D2 可选） |
| 探针文案/版式被误判为品味问题 | 低 | mechanical 所有权：文案由 issue 指定，无品味裁决空间；版式以 E2E 截图为准（§2.1） |
| 方案 B/C 诉求被误带入本 issue | 低 | §2.2 明确延后；声明式 Label 是唯一实现（PRD §4.2 方案裁决） |
| 探针与 VersionLabel 视觉重叠 | 低 | 几何验证：1280x720 下 VersionLabel 右缘 400 < 探针左缘 880，无重叠；截图裁决（Test G1） |

# PRD #567 — [Test] post-merge 阶段回归 — GDD 落盘 + docs PR 自动合并 (08-19)

> **Issue:** #567
> **标签:** enhancement, version/mvp, workflow/available→workflow/research（本阶段认领）；无 depth 标签 → 按 light 处理（§1–5 + §8 必填，§6 简述，§7 跳过并注明）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **深度:** light
> **所有权:** `content_ownership: mechanical`（探针 Label = 管线冒烟验证物，无品味裁决；文案直接采用 issue 指定文本『post-merge probe』）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** ① Obsidian 知识库已搜索（`/Volumes/Obsidian` raw+wiki 全量 grep post-merge/探针/probe/山东 → **0 命中**：post-merge 阶段 2026-08-19 刚落地、山东抗日之狼为 2026-08-18 新游戏，知识库无先例，属正常空结果，非工具降级）；② 开源优先搜索（Godot Asset Library + GitHub，实查结果见 §4.1）；③ 仓库 pipeline 源码/文档（event-processor.py `post_merge_emitter`/`_quick_stalled_scan`、workflow-watchdog.py、workflow-chain.yml、game-post-merge-agent skill）
> **来源:** 任务指派（game-research-agent）
> **前置依赖:** eabb294（post-merge 阶段落地：merge 事件绑定 GDD 更新，#562/#566 缺口修复，已 merged，含 9+2+4=15 项新测试）、0f18c45（MANIFEST_PATH 去 macOS 硬编码，pipeline-tests CI 全红修复，已 merged）、#563（结论文件骨架机制回归，同类测试 issue，已 closed）、#559/#562（shandong-wolf Main.tscn 标题场景已落地，已 merged）

---

## 1. 问题定义

### 1.1 现状（2026-08-19 侦查）

本 issue 是**测试 issue**（issue body 明示「这是测试 issue，验证后关闭」），交付物分两层：**场景侧一个最小可见的右下角探针 Label** + **管线侧一次真实 post-merge 全链路回归**（research→plan→implement→CI→E2E→review→**merge→post-merge**）。

**场景侧（feature 现状）— `shandong-wolf/scenes/Main.tscn`（#559/#562/#563 已落地）：**

| 节点 | 类型 | 关键属性 | 位置 |
|------|------|---------|------|
| Main | Node2D | — | 根节点 |
| CanvasLayer | CanvasLayer | layer=1 | UI 层 |
| CenterContainer | CenterContainer | anchors_preset=15（全屏） | 居中容器 |
| VBoxContainer | VBoxContainer | alignment=1 | 垂直排列 |
| TitleLabel | Label | text=『山东抗日之狼』，font_size 64 | 居中 |
| SubtitleLabel | Label | text=『雪夜 · 大刀 · 山东村』，font_size 28，alpha 0.8（#563 落地） | 居中 |
| VersionLabel | Label | text=v0.1.0，font_size 16，anchors_preset=2（左下） | 左下（CanvasLayer 直属，不在 VBox 内） |

**缺口：** 右下角无任何 UI 元素，无 `PostMergeProbeLabel`。issue 要求追加一个**右下角探针 Label**（node 名 `PostMergeProbeLabel`，文本『post-merge probe』，视觉可见但 diff 极小）。

**管线侧（被验证对象现状）— post-merge 阶段（eabb294/0f18c45，2026-08-19 落地）：**

| 组件 | 位置 | 机制 |
|------|------|------|
| post-merge state | `~/.hermes/post-merge-state/<PR>.json` | `review_followup`/`_try_merge` 成功 merge 后创建 `{status: pending}` |
| post_merge_emitter | `scripts/event-processor.py:2003+` | 每 tick 扫描 pending + 无 emitted_at → `SPAWN: post-merge`（one-shot，emitted_at 标记防重发，镜像 review 一次性语义） |
| post-merge agent | game-post-merge-agent skill | worktree 隔离写 GDD/PROJECT.md → `docs/gdd-<N>` 分支 + PR → 轮询 MERGED → `status=done`；白名单 add |
| stalled scan | `scripts/event-processor.py` `_quick_stalled_scan`（L1626-1635） | `docs/` 前缀分支 → `STALLED: merge-pr` 自动合并（merge 归脚本层，post-merge agent 绝不自己 merge） |
| watchdog | `scripts/workflow-watchdog.py` | pending + emitted_at 超 45min → `post-merge-stuck` 告警（GDD 悬空终局兜底，不静默） |
| workflow-chain | `.github/workflows/workflow-chain.yml` | PR merged → 自动推进 parent issue 的 workflow label（research→plan→implement） |

**核心缺口：** eabb294 已实现并有 216 项单元测试全量通过（含 9 post-merge state/emitter + 2 stalled docs PR + 4 watchdog post-merge-stuck），但**从未在真实全链路跑通**——`docs/gdd-<PR>` PR 是否真被 stalled scan 自动 merge、GDD 是否真落盘 main、post-merge-state 是否真置 done、watchdog 是否无告警，全部待本次 issue 自身走完管线来实证。这是回归测试 issue 的本质。

### 1.2 验收条件（源自 Issue #567 body，映射到各阶段 agent）

| # | 验收条件 | 负责阶段 | 本 PRD 的保障措施 |
|---|---------|---------|------------------|
| AC1 | 三层 CI 全过（L0 编译 / L1 逻辑 / L2 运行时） | CI | implement PR 合入后 opencode-review.yml 自动跑三层；本 issue 只改场景节点，无脚本 → 编译风险趋零 |
| AC2 | review_followup 消费结论 → **自动 merge**（无人工介入） | event-processor | #563 已实证 review_followup 自动 merge 路径；本次回归点（同链路再验证一次） |
| AC3 | merge 后 `~/.hermes/post-merge-state/<PR>.json` 出现（status=pending）→ 同 tick 发射 SPAWN: post-merge（one-shot，不重发） | event-processor | `post_merge_emitter` 源码已核实（L1953-1956 同 tick 扫描）；本次 issue 的 implement PR 即触发对象 |
| AC4 | post-merge agent 运行：创建 docs/gdd-<PR> 分支 + PR，diff 只含 docs/GAME_DESIGN/shandong-wolf/ + docs/PROJECT.md（白名单红线） | post-merge agent | skill 白名单 add 契约；本 PRD §8 明示 implement 不写 GDD（职责分离，杜绝 diff 混入代码） |
| AC5 | stalled scan 自动 merge docs PR（无人工介入，main 只进 PR） | event-processor | `_quick_stalled_scan` docs/ 前缀自动 merge 已核实（L1626-1635） |
| AC6 | shandong-wolf GDD 出现首个章节（01-OVERVIEW 或对应功能域）+ 子目录 INDEX.md 更新 | post-merge agent | 现状 = `docs/GAME_DESIGN/shandong-wolf/INDEX.md` 占位「待填充」→ 回归前后对比即验证 |
| AC7 | post-merge-state 标记 status=done（docs PR MERGED 后） | post-merge agent | skill 契约：轮询 docs PR merged → 写 done；watchdog 兜底未触发即闭环证据 |
| AC8 | 全程无 post-merge-stuck 告警（watchdog 45min 兜底未触发） | watchdog | AC7 的配套验证：done 出现且无告警 = 全链路按时完成 |
| AC9 | PostMergeProbeLabel 在 Main.tscn 可见（场景加载断言：text 精确匹配『post-merge probe』） | plan/implement/review | §5.1 AC9 check：节点规格精确落位 + E2E 截图可见（非灰屏） |

> 注：AC1–AC8 是**管线自身行为的验证项**，不是 implement 的交付物——它们由本次 issue 走完 research→plan→implement→CI→E2E→review→merge→post-merge 全链路来实证；implement 的**唯一代码交付物是 AC9 的探针 Label**。plan/implement/review 各阶段不得为「满足 AC1-8」改动任何 pipeline 脚本。

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 管线 post-merge 阶段回归（本次 issue 本体） | 一次性 | issue 走完 research→plan→implement→CI→E2E→review→merge→post-merge 全链路，实证 eabb294 机制：pending → SPAWN one-shot → docs PR → stalled scan 自动 merge → status=done |
| B | 每个 implement PR merge 后的 GDD 更新 | 每次 merge | merge 事件自动绑定 GDD 更新：post-merge agent 写 GDD/PROJECT.md → docs/ PR 自动合入，GDD 不再是无主责任（#562/#566 缺口修复的日常形态） |
| C | 玩家/用户首启 | 手动 | `godot --path shandong-wolf/` 启动即见标题/副标题/版本标签，右下角可见『post-merge probe』探针（验证物，非游戏内容） |

### 1.4 范围边界（与既有 PRD 去冲突，Patch 14）

| PRD / 变更 | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| PRD #563（结论文件骨架回归，已 closed） | review 全链路回归 + 副标题 Label（SubtitleLabel） | ❌ 不重设计标题/副标题结构 — 只在 CanvasLayer 下与 VersionLabel 同级**追加一个探针 Label 节点** |
| PRD #559 / #562（shandong-wolf 标题场景，已 merged） | Main.tscn 节点树 + run/main_scene 指向 | ❌ 不重建/重构 Main.tscn — 最小 diff 追加节点，不碰 CenterContainer/VBox |
| eabb294 / 0f18c45（post-merge 落地，已 merged） | event-processor/watchdog/skill 的 post-merge 机制实现 + 测试 | ❌ 不改 pipeline 任何脚本/工作流/skill — 本 issue 是**验证对象**，不是改动对象 |
| 本 PRD（#567） | 右下角探针 Label（最小 diff）+ post-merge 全链路真实回归 | 探针文案由 issue 指定（『post-merge probe』），无品味裁决空间；GDD 章节内容归 post-merge agent（AC4/AC6） |

### 1.5 预期行为（最小冒烟语义）

- `shandong-wolf/scenes/Main.tscn` 加载后，**右下角默认可见**『post-merge probe』（启动即显示，不依赖按键/状态机）→ 任何启动截图即命中 AC9。
- 本次 issue 的 implement PR 合入后：CI 绿 → review agent 填结论 → `review_followup` 自动 merge（AC2）→ `post-merge-state/<PR>.json` pending（AC3）→ SPAWN: post-merge one-shot → post-merge agent 写 GDD 走 `docs/gdd-<PR>` PR（AC4）→ stalled scan 自动 merge（AC5）→ GDD 首章节 + INDEX 更新落盘 main（AC6）→ status=done（AC7）→ watchdog 全程无告警（AC8）。

---

## 2. 设计意图

### 2.1 为什么现状如此（时间线）

| 事件 | 内容 | 后果 |
|------|------|------|
| 方案 X（merge 脚本化） | review agent 写结论文件即结束会话，merge 由脚本层 `review_followup` 执行 | review 会话内 post-merge GDD 更新物理不可达 |
| #562/#566 实测 | GDD 更新成无主责任：review 不写、后续无人认领 | 用户拍板：GDD 走 docs/ PR，绝不直接 push main |
| eabb294（2026-08-19） | merge 事件 → post-merge 任务状态 → SPAWN: post-merge（one-shot）→ post-merge agent → docs PR → stalled scan 自动 merge | 触发归脚本（确定性），写作归 LLM（GDD 内容）——符合「LLM 只做判定，机械归脚本」铁律 |
| 0f18c45（2026-08-19） | MANIFEST_PATH 摆脱 macOS 硬编码 | pipeline-tests CI 全红修复 → 回归验证的前置条件就绪 |

### 2.2 为什么现在改

eabb294/0f18c45 当日落地（2026-08-19），已有单元测试覆盖（216 项全过），但**无真实全链路实证**——「脚本层自动 merge docs PR」这类跨进程行为无法被单测覆盖，只能由一次真实 issue 走完整管线来验证。#567 即为此回归载体；同时探针 Label 是骨架期最小 UI 改动，实现成本趋零，适合作为冒烟物。

### 2.3 既有约束（本 PRD 继承，全链路红线）

| 约束 | 详情 |
|------|------|
| merge 归脚本层 | post-merge agent 绝不自己 merge docs PR（stalled scan 负责） |
| GDD 走 docs PR | 绝不直接 push main；diff 白名单 = docs/GAME_DESIGN/shandong-wolf/ + docs/PROJECT.md |
| one-shot 不重发 | post-merge SPAWN 带 emitted_at 标记，镜像 review 一次性语义 |
| watchdog 兜底 | post-merge-stuck 45min 告警，GDD 悬空不静默 |
| 主场景已定 | `run/main_scene="res://scenes/Main.tscn"`，探针挂载此场景 |
| 游戏切换参数化 | manifest `game.active` 单一事实源；全部路径用 `shandong-wolf/` 前缀 |

---

## 3. 影响分析

### 3.1 直接影响的模块（唯一代码交付物）

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/scenes/Main.tscn` | 主场景 UI | 追加 1 个 Label 节点（PostMergeProbeLabel，CanvasLayer 直属，与 VersionLabel 同级，anchors_preset=3 右下角） |

### 3.2 新建文件

无。不引入 .gd 脚本、.tres/.theme 资源、字体资产（开源优先调研结论见 §4.1，Godot 默认主题即成熟方案）。

### 3.3 间接影响的模块（被验证对象，零改动）

| 模块 | 影响方式 |
|------|---------|
| `scripts/event-processor.py`（review_followup / post_merge_emitter / _quick_stalled_scan） | 被本次 issue 的 implement PR merge 事件触发，回归验证其行为（AC2/AC3/AC5） |
| `scripts/workflow-watchdog.py` | 观察对象：全程无 post-merge-stuck 告警（AC8） |
| `.github/workflows/workflow-chain.yml` | 观察对象：docs PR merge 后 issue label 自动推进 |
| `agents/skills/game-post-merge-agent/` | 被 SPAWN 调用的执行体（AC4/AC6/AC7） |
| `docs/GAME_DESIGN/shandong-wolf/` | 被 post-merge agent 填充（AC6）——不是 implement 交付物 |

### 3.4 数据流（post-merge 全链路，本次回归的验证路径）

```
impl PR merged (review_followup/_try_merge)
    │ 创建 ~/.hermes/post-merge-state/<PR>.json {status: pending}      ← AC3
    ▼
post_merge_emitter (每 tick 扫描)
    ├── pending + 无 emitted_at ──► SPAWN: post-merge (one-shot, emitted_at 标记)
    │                                   │
    │                                   ▼
    │                        post-merge agent (worktree 隔离)
    │                           ├── 写 GDD 章节 + PROJECT.md (白名单 add)
    │                           └── docs/gdd-<PR> 分支 + PR             ← AC4
    │                                   │
    │                                   ▼
    │                        _quick_stalled_scan (docs/ 前缀)
    │                                   │
    │                                   ▼
    │                        STALLED: merge-pr 自动 merge（脚本层）     ← AC5
    │                                   │
    │                                   ▼
    └── agent 轮询 docs PR MERGED ──► status=done ◄── GDD 落盘 origin/main
                                         │                              ← AC6/AC7
                                         ▼
                              watchdog: 45min 无 done → post-merge-stuck 告警（本次应不触发，AC8）
```

### 3.5 需更新的文档

- [x] `docs/PRD/567-post-merge-probe.md`（本 PRD，本阶段交付物）
- [ ] `docs/GAME_DESIGN/shandong-wolf/`（**post-merge agent 职责**，AC6 验证项；implement 不得代写）
- [ ] `docs/PROJECT.md`（**post-merge agent 职责**，AC4 白名单项；implement 不得代写）

---

## 4. 方案对比

### 4.1 开源优先调研结果（2026-08-19 实查，issue 🔍 要求）

| 来源 | 查询 | 结果 | 结论 |
|------|------|------|------|
| Godot Asset Library | filter=label | 0 命中 | 无直接适用的 Label 样式资产 |
| Godot Asset Library | filter=font | 1 命中：FontAwesome Icons（Godot 2.1，2017，社区级） | 图标字体 + 旧版引擎，不适用 |
| Godot Asset Library | filter=ui theme | 0 命中 | 无 |
| GitHub 仓库搜索 | godot ui theme | kiri-soft/Godot-UI-Themes（0⭐）、Sublittoral-Games/Godot-UI-Tool（0⭐） | 无星未验证，无成熟方案 |
| GitHub 仓库搜索 | godot label | antzGames/Godot-4.4-vs-4.5-label-tests（3⭐，测试仓库）等 | 无成熟 Label 样式/字体方案 |
| 仓库内先例 | mini-pong 全站 `scenes/*.tscn` | 全站 Label 用 `theme_override_font_sizes/font_size` 直接覆盖，零自定义字体/Theme 资源 | Godot 内置默认主题（ThemeDB）即本项目已验证的成熟方案 |

**结论：** 开源生态无针对「探针 Label」的成熟可复用资产；Godot 4.7 内置默认主题开箱即用（Label 零配置可渲染），且探针文本是 ASCII『post-merge probe』，默认字体渲染无压力 → 不引入任何外部资产，符合「diff 极小 + 零资产骨架期」双重要求。

### 4.2 场景侧实现方案

**方案 A：纯 tscn 声明式节点（推荐）**

CanvasLayer 直属追加一个 Label 节点：`anchors_preset=3`（右下角）、`text="post-merge probe"`、`theme_override_font_sizes/font_size=16`、`modulate=Color(1,1,1,0.6)`，offset 镜像 VersionLabel（左下→右下）。

- Pros：diff 最小（1 节点约 10 行 tscn）；零新文件；AC9 断言直读 text 属性；与 VersionLabel 同模式，评审零认知成本
- Cons：无动态能力（冒烟物不需要）
- Risk：**Low**（纯声明式，无代码路径）
- Effort：<0.5 天（场景编辑级改动）

**方案 B：探针 .gd 脚本 + @export 配置**

新建 `gdscripts/post_merge_probe.gd`，Label 挂脚本控制文本/位置。

- Pros：可参数化、可复用
- Cons：新增文件违反最小 diff；冒烟验证物不需要逻辑；为验证物引入代码面 = 本末倒置
- Risk：Med（新增脚本面，CI L0/L1 多一个编译/测试对象）
- Effort：1 天

**方案 C：引入自定义 Theme/字体资产（如开源中文字体子集）**

- Pros：中文渲染更精致（若未来 UI 需要）
- Cons：新增字体/Theme 资源文件 + .godot import 缓存噪音；探针是英文文本，默认字体零压力；违反「零资产骨架期」约定；与开源优先调研结论（无成熟必要资产）相悖
- Risk：Med（资产管线 + import 噪音）
- Effort：1-2 天

### 4.3 管线侧方案

**无方案选择**——post-merge 机制已由 eabb294 实现并测试，本 issue 只回归验证（AC1-AC8），不提供也不评估替代实现。任何「改 pipeline 实现」的提议都超出本 issue 范围（见 §1.4 范围边界）。

### 4.4 推荐

**方案 A**，理由：
1. 满足 issue 核心约束「视觉可见但 diff 极小」——唯一交付物是一个声明式节点；
2. 与 VersionLabel 既有模式（CanvasLayer 直属 + anchors_preset + theme_override）完全同构，零新模式；
3. 不引入资产/脚本 → AC1（三层 CI）风险最低，AC9（text 精确匹配断言）最直接。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单，源自 Issue #567 body）

- [x] **AC1: 三层 CI 全过** — implement PR 的 L0 编译 / L1 逻辑 / L2 运行时全部通过
  - 验证条件：opencode-review.yml 三个 job 全绿；场景改动不含脚本 → L0 无新增编译面
- [x] **AC2: review_followup 消费结论 → 自动 merge（无人工介入）**
  - 验证条件：implement PR 的 review 结论文件被脚本消费并 merge；无人工操作记录
- [x] **AC3: post-merge-state pending + 同 tick SPAWN: post-merge（one-shot，不重发）**
  - 验证条件：`~/.hermes/post-merge-state/<PR>.json` 出现且 status=pending；SPAWN 指令只发射一次（emitted_at 唯一）
- [x] **AC4: post-merge agent 创建 docs/gdd-<PR> 分支 + PR，diff 白名单**
  - 验证条件：docs PR 的 diff 只含 `docs/GAME_DESIGN/shandong-wolf/` + `docs/PROJECT.md`；无代码文件混入
- [x] **AC5: stalled scan 自动 merge docs PR（无人工介入，main 只进 PR）**
  - 验证条件：docs PR 被脚本自动 merge；main 无直接 push 记录
- [x] **AC6: shandong-wolf GDD 首个章节 + 子目录 INDEX.md 更新**
  - 验证条件：`docs/GAME_DESIGN/shandong-wolf/` 出现 01-OVERVIEW 或对应功能域章节；INDEX.md 不再是占位「待填充」
- [x] **AC7: post-merge-state status=done（docs PR MERGED 后）**
  - 验证条件：`~/.hermes/post-merge-state/<PR>.json` 的 status=done
- [x] **AC8: 全程无 post-merge-stuck 告警（watchdog 45min 兜底未触发）**
  - 验证条件：监控日志无 post-merge-stuck；AC3→AC7 链路在 45min 窗口内完成
- [x] **AC9: PostMergeProbeLabel 在 Main.tscn 可见（text 精确匹配『post-merge probe』）**
  - 验证条件：场景加载断言 node path 命中 PostMergeProbeLabel 且 text 精确等于 `post-merge probe`；E2E 截图右下角可见该文本（非灰屏）

### 5.2 边界情况

1. **节点名必须精确** `PostMergeProbeLabel`——issue 指定命名，E2E/断言可能按名寻址；改名即 AC9 失败
2. **text 必须精确** `post-merge probe`——AC9 断言精确匹配（含空格，无引号）；不得用中文翻译或改文案
3. **右下角定位**：`anchors_preset=3` + 负 offset（镜像 VersionLabel 的左下 anchors_preset=2 为右下）；offset_left=-400 / offset_top=-36 / offset_right=-16 / offset_bottom=-12（参考 VersionLabel 尺寸反向镜像）；grow_horizontal=0 / grow_vertical=0
4. **不挤占 VersionLabel**：探针在右下（anchors_preset=3），VersionLabel 在左下（anchors_preset=2），1280x720 下无重叠；不得挪动 VersionLabel
5. **挂载层级**：CanvasLayer 直属（与 VersionLabel 同级），**不进 CenterContainer/VBox**——避免改变居中布局或引发 VBox 自动排列连锁 diff
6. **视觉可见但克制**：font_size=16 与 VersionLabel 一致；modulate alpha≈0.6-0.8 保证可见且不喧宾夺主（E2E 截图判据：文本与背景可区分，非纯黑/纯灰屏）
7. **无 depth 标签** → light 深度：§7 Spike 跳过并注明（本条即注）；plan agent 不得要求补 spike
8. **E2E 多文本场景**：截图可能同时命中标题/副标题/版本/探针多段文本，断言必须按 node path（`CanvasLayer/PostMergeProbeLabel`）定位，不得用「任意文本包含」模糊匹配

### 5.3 失败路径

1. **docs PR diff 越界**（混入代码/其他目录文件）→ post-merge agent 白名单 add 红线被破坏 → 人工/脚本发现，docs PR 不得 merge；应对：review 证据阶段核对 diff 白名单（AC4）
2. **post-merge SPAWN 重发**（emitted_at 缺失/状态机异常）→ 违反 one-shot 语义 → 观察 emitted_at 唯一性；watchdog/事件日志兜底
3. **docs PR 卡住未 merge** → stalled scan 45min 窗口 + post-merge-stuck 告警（AC8 失败信号）→ 人工介入调查脚本层；本次应不触发
4. **implement PR 意外改动 pipeline 脚本/工作流** → review 阶段拒绝合入（§8 红线 ①）；CI 的 pipeline-tests 亦会拦截（0f18c45 后 CI 已能跑 pipeline 测试）
5. **AC9 断言失败**（text/位置不符）→ implement 自测 + review E2E 截图双保险；回归验证物不允许带病合入

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| eabb294（post-merge 机制落地，含 15 项新测试） | merged | Low |
| 0f18c45（CI MANIFEST_PATH 修复） | merged | Low |
| #563（结论文件机制回归：review_followup 自动 merge 已实证） | closed | Low |
| #559/#562（Main.tscn 标题场景落地） | merged | Low |
| `docs/GAME_DESIGN/shandong-wolf/INDEX.md`（占位待填充） | 存在（占位） | Low（post-merge agent 填充目标，非 implement 依赖） |

### 6.2 依赖链

```
#559 (Main.tscn 标题) → #562 (feat 实现) → #563 (结论文件回归)
        │                                        │
        └──────────────┬─────────────────────────┘
                       ▼
        eabb294 + 0f18c45 (post-merge 阶段落地, 2026-08-19)
                       │
                       ▼
              本 issue #567（回归验证载体，走完整管线）
                       │
                       ▼
        下游: workflow-chain 自动推进 → plan → implement → review → post-merge
```

### 6.3 阻塞与准备

- 阻塞：无。
- 准备事项：无（无需新工具/资产/密钥；`gh` 已认证、worktree 脚本就绪）。

---

## 7. Spike / 实验

**Skipped per light 深度**（issue 无 `depth/` 标签 → 按 light 处理：§1–5 + §8 必填，§7 可跳过）。

补充说明：探针 Label 是 Godot 内建 Label 的声明式实例化，仓库 mini-pong 已多次使用 `theme_override_font_sizes` 模式（见 §4.1 先例），无新技术风险；管线侧是**回归验证对象**而非新设计（eabb294 已实现 + 216 测试），无需 spike 实验。若 plan 阶段仍想验证，唯一可选项是「本地 `godot --path shandong-wolf/ --quit` 加载探针场景」的冒烟确认，属实现阶段常规自测，不构成 spike。

---

## 8. 交接上下文（Continuation Context）

**给 plan agent 的交接摘要：**

### 8.1 系统状态（2026-08-19）

- `shandong-wolf/scenes/Main.tscn`：已有 TitleLabel（64）/ SubtitleLabel（28, α0.8）/ VersionLabel（16, 左下 anchors_preset=2）；`run/main_scene` 已指向本场景
- `docs/GAME_DESIGN/shandong-wolf/INDEX.md`：占位「待填充」——**post-merge agent 的填充对象**，plan/implement 不得代写
- post-merge 管线（eabb294）：merge → pending → SPAWN one-shot → docs PR → stalled scan 自动 merge → done；本次 issue 走完即回归实证

### 8.2 交付物唯一性（implement 阶段唯一任务）

只改 `shandong-wolf/scenes/Main.tscn`，追加 **1 个节点**：

```gdscript
[node name="PostMergeProbeLabel" type="Label" parent="CanvasLayer"]
anchors_preset = 3                      # 右下角（镜像 VersionLabel 的左下）
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -400.0                    # 参考 VersionLabel 尺寸反向镜像
offset_top = -36.0
offset_right = -16.0
offset_bottom = -12.0
grow_horizontal = 0
grow_vertical = 0
text = "post-merge probe"               # 精确匹配，AC9 断言
theme_override_font_sizes/font_size = 16
modulate = Color(1, 1, 1, 0.6)
```

（plan agent 可微调 offset 尺寸，但 node 名 / text / 右下角 anchors_preset=3 为硬约束。）

### 8.3 红线（plan/implement 必须遵守）

1. **绝不改 pipeline**：`scripts/`、`.github/workflows/`、`agents/skills/` 零改动（AC1-8 是验证项，不是交付物）
2. **绝不碰 `mini-pong/`**（manifest game.active 已切 shandong-wolf）
3. **不写 GDD / PROJECT.md**：post-merge agent 职责（AC4/AC6），implement 代写 = 职责越界 + diff 白名单破坏
4. **不新增资产**：无字体/Theme/图片资源（§4.1 开源优先结论）
5. **不改 `project.godot`**：run/main_scene 已就位

### 8.4 测试与验证

- 单元测试/冒烟测试**无需新增**：探针是场景节点，无脚本逻辑；`tests/run_tests.gd` 保持现状
- AC9 实证方式：场景加载断言（node path + text 精确匹配）+ review E2E 截图右下角可见
- `e2e_shots.json` 补 shot 为 **plan 阶段可选**（若现有 shot plan 已覆盖主场景启动画面，可不加）
- 本地自测：`godot --path shandong-wolf/ --quit` 应无场景解析错误

### 8.5 主要风险

- **过度实现**（implement 给探针加脚本/动画/资产）→ 违反最小 diff 与零资产约束；plan 阶段 DESIGN 应明确「声明式节点，无脚本」
- **节点规格漂移**（改名/改 text/换位置）→ AC9 断言失败；DESIGN 需逐字段固化 §8.2 规格
- **管线 AC1-8 失败**：本 PRD 已给出每项对应的机制出处（§1.2 表），plan/implement/review 各阶段按表核验，失败即按失败路径（§5.3）处理，不得静默吞掉

### 8.6 下一步（本 PR merge 后）

1. workflow-chain 自动推进 #567 → `workflow/plan` → plan agent 产出 DESIGN
2. implement PR 合入 → CI → review → merge → **post-merge 阶段回归开始**（AC3-AC8 验证窗口）
3. 验证完成后 #567 关闭（issue body 明示「验证后关闭」）

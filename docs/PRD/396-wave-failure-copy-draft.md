# PRD: [Content] 波次副句与失败短句 (B5)

> **Issue:** #396
> **标签:** content, enhancement, version/full, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 跳过）
> **所有权:** `content_ownership: taste-draft`（人机共做 v4 — B5 失败表达领域；agent 提供候选清单（≥3 选 1 + 适用语境）而非直接定稿；草稿达标即 merge，PR 用 `parent #396` 不写 Closes；review agent 打 `status/human-review` + assign 用户定稿）
> **taste 方向来源:** PONG://21 攻城战肉鸽方案（docs/PLAN-rogue-pong.md，2026-08-13 用户拍板）+ Obsidian 知识库检索（海明威冰山理论 / 沉默作为叙事策略 / 失败即叙事）+ 项目品味档案（docs/TASTE.md）

---

## 0. 研究复核记录（Research Re-verification，2026-08-13）

> 本 PRD 经 #400 合并进 main（2026-08-13 01:45）。研究阶段复核时管线状态已推进到 **implement 阶段**，
> 本文件仍为权威 PRD（DESIGN #406 明确引用：`docs/PRD/396-wave-failure-copy-draft.md`（#400 merged，main 上权威 PRD））。

| 阶段 | 状态 | 证据 |
|------|------|------|
| research | ✅ merged | #399（平行 PRD `396-wave-subtitles-failure-lines.md`）+ #400（本 PRD） |
| plan | ✅ merged | #404（PLAN）+ #406（DESIGN `396-wave-subtitles-failure-lines.md`） |
| implement | 🔄 进行中 | #407 open（`impl/396-wave-failure-text`，已按 DESIGN §2 落地 `mini-pong/content/wave_failure_text.json`，待 review） |

### 复核发现：content 资源路径约定分歧

- **#395（已 merge #405）**：`mini-pong/assets/content/upgrade_pool.json` —— 首个 content 资源先例，落在 `assets/content/` 下
- **#396（本 PRD / DESIGN #406 / impl #407）**：`mini-pong/content/wave_failure_text.json` —— 落在 `content/` 下
- 两处均为「独立 content 资源」，但目录约定不一致（`assets/content/` vs `content/`）。

**建议（research 视角，不阻塞 #407）**：#407 已按 DESIGN 落地 `content/`，保持现状即可 merge；
目录约定统一（`assets/content/` 与 `content/` 二选一）留待后续 content Issue 或一次性约定收口 Issue
处理，不在本 PRD 改路径 —— 避免与已 merged DESIGN #406 冲突。

### 复核结论

本 PRD 核心内容（候选清单 4 副句 × 4 短句、schema `wave-failure-text/v1`、taste 方向）**无需修改**：
候选文本与 DESIGN §2 及 impl #407 落地一致。本次复核仅补记管线状态与路径约定分歧，供 review / 后续 Issue 参考。

---

## 1. 问题定义

### 当前状态

PONG://21 攻城战肉鸽（垂直布局 + 砖墙 + 21 分制 + 升级池）的机械管线已预留两个**内容插槽**，但文案为空：

| 插槽 | 消费方（机械 Issue） | 插槽现状 | 缺失 |
|------|---------------------|---------|------|
| 波次副句（波次转场大字「第 N 道墙」+ 副句，2s 淡入-停留-淡出） | #390 波次转场（`副句内容从统一文本配置读取`） | ✅ UI/转场机械结构预留 | ❌ 无任何候选文案 |
| 失败短句（失败屏短句 + run 数据：波次/拆砖/穿墙） | #391 失败屏（`短句从配置读取且无 emoji/夸张语气`） | ✅ 失败屏机械结构预留 | ❌ 无任何候选文案 |
| 统一文本配置（content 资源） | #390/#391 均从配置读取 | ❌ 不存在 | **需新建**（Issue 验收条件指定的独立 content 资源文件） |
| `mini-pong/gdscripts/constants.gd` | 现有单一事实源（A1 手感 11 参数） | ✅ 存在 | —（文案**不**进 constants.gd，属内容层） |

波次/失败系统的**机械语义**已由 PONG://21 方案确认（docs/PLAN-rogue-pong.md §2）：波次递增（每波墙更厚 + AI 更强，`+0.1/波` 雨量因子）、21 分制胜负判定、`失败即叙事`（失败 = 叙事生产，非惩罚）、`克制优先`（失败屏不堆特效）。B5 领域判定（taste-ownership-domains.md）：T1 主观性 ✅（两个专家对"哪句更好"答案不同）/ T2 不可断言 ✅（无法 `assert text == "..."` 验证"好"）/ T3 语境 ✅（同样的句子换到别的游戏不成立）→ **人机共做领域**，agent 出候选清单，人做最终裁决。

### 预期行为（验收条件，源自 Issue #396）

1. **波次副句 ≥3 条候选，每条 ≤15 字**
2. **失败短句 ≥3 条候选，每条 ≤10 字**
3. **全部为海明威式短句**：无形容词堆砌、无感叹号
4. **每条注明适用语境**（第几波 / 失败 severity）
5. **文案放入独立 content 资源文件**，不作为注释散落代码

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 波次转场（#390） | 每波一次 | 转场大字「第 N 道墙」下方出现副句——给每波一个"呼吸点与仪式感"（#390 context），副句必须克制、不喧宾夺主 |
| B | 失败屏（#391） | 每次失败 | 短句 + run 数据（波次/拆砖/穿墙）——"失败提供信息与氛围，而不是惩罚性界面"；短句值得截图（PLAN DoD：`失败时那条短句值得截图`） |
| C | 用户定稿（v4 队列） | 每次草稿 merge 后 | GitHub Assigned to me 攒批处理：打开 Issue → 从候选表选 1 / 微调 → push 定稿 → close |
| D | implement agent 填草稿 | 本管线一次 | 按本 PRD §4.2 候选表写入 content 资源（JSON，`draft: true` + 推荐标记），机械零改动 |
| E | review agent 定稿就绪检查 | 每次实现 PR | 结构完整（候选 ≥3 × 字限 × 语境齐全）+ taste 方向对齐（海明威式/无感叹号/无形容词堆砌） |

### 技术约束（继承自 Issue #396 + PONG://21 方案）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 project.godot）；**竖屏 720×1280**（P0 轴交换后，PONG://21 §4.1） |
| 领域判定 | B5 失败表达：T1/T2/T3 全通过 → 人机共做；候选清单（2-3 选 1 + 失败事件表）为 B5 校准接口 |
| 审美坐标 | 雨夜竞技场（动态雨量 = 情绪仪表盘：波次因子 +0.1/波、失败脉冲 → 1.0）+ 霓虹描边 UI + **克制优先**（PLAN §3.2/§3.3） |
| 风格红线 | 海明威式冰山理论（八分之一在水面）；**无形容词堆砌**（单修饰词上限）、**无感叹号**、无 emoji、无网络梗 |
| 文本密度锚点 | Obsidian：Papers Please 极简文字 × 最大文本密度；空洞骑士对话极简主义（叙事负空间） |
| 所有权 | taste-draft：PR 用 `parent #396`（小写 p）不写 Closes；草稿达标即 merge，不等人定稿 |
| 产出边界 | 只新建 content 资源文件（+ 本 PRD）；**不修改任何运行时行为**（gdscripts/scenes/tests/E2E 均不动）；文案不散落代码注释 |

---

## 2. 设计意图

### 为什么现在做

这是 v4 人机共做队列的 **B5 失败表达** 内容 Issue。taste-ownership-domains.md 将 B5 列为 **P0 优先**（"失败即叙事是核心机制"），且明确指出 B5 是**最容易被 agent 写错的领域**——默认"失败=惩罚"，而本项目的品味是"失败=叙事生产"。本 Issue 的上下文也声明：`内容插槽与 UI 已预留，本任务只决定最终文案`——机械部分（#390 转场 / #391 失败屏）不依赖本 Issue 的文案内容，只依赖 content 资源配置的**存在**。管线语义：agent 生成带 taste 方向的候选清单草稿 → **草稿达标即 merge**（结构可用）→ assign 用户定稿（显式队列，不阻塞下游机械 Issue #390/#391）。

### 审美坐标与 taste 方向（研究关键发现）

PONG://21 方案注入的审美坐标：**雨夜竞技场**（雨 = 情绪仪表盘：`rain = base(0.3) + 球速因子 + 波次因子(+0.1/波) + 紧张因子(比分差≤2 → +0.2) + 事件脉冲(穿墙+0.4 / 失败→1.0)`）+ **霓虹描边 UI** + **克制优先**（"动效不弹跳不花哨"）。**文案方向**：副句与失败短句必须与"雨"的世界观同构——短、静、留白，让雨替玩家说出情绪。

Obsidian 知识库检索（`/Volumes/Obsidian/Knowledge Ocean/wiki/`，本机已挂载）找到的可迁移设计语言：

| 笔记 | 可迁移到本 Issue 的设计语言 |
|------|---------------------------|
| `Papers Please—官僚机制作为悲剧结构.md` | **海明威式冰山理论**：`极简文字 × 最大文本密度`——"八分之一在水面上，八分之七在水下"→ 每条文案 ≤15/≤10 字，信息密度最大化，情绪留在水面下 |
| `空洞骑士—沉默作为叙事策略.md` | **沉默的建筑学**："少即是多"；NPC 对话极简主义 = 叙事的负空间 → 失败短句不说教、不惩罚、不鼓励，只陈述事实（雨还在下） |
| `体验引擎-glossary.md` | **Challenge（挑战）** = 紧张感与精通的潜力 → 波次副句承担张力标记（墙更厚 / 雨更大），让玩家"看见"难度曲线 |
| `90年代地摊文艺.md` | 街机文化的粗粝、直接——克制 ≠ 寡淡：短句仍要有"击打感"（动词驱动：拆/挡/停） |
| `Before Your Eyes—眨眼机制作为叙事节奏.md` | 节奏即叙事 → 副句随波次换挡：开局平静 → 中段加压 → 后期紧张 → 决胜决绝 |

**taste 方向综合（本 PRD 的注入方向）**：

1. **海明威式**：主谓宾短句、具体名词（雨/墙/心跳）、动词驱动；删形容词、删副词、删感叹号。
2. **雨是情绪载体**：副句与失败短句尽量与"雨/墙"意象同构（雨势 = 压力表，墙 = 进程表），不另起炉灶。
3. **失败 = 叙事生产**（B5 核心品味）：失败短句不惩罚（无"你输了/太弱了"）、不空洞鼓励（无"下次一定"），而是让失败**留下痕迹**（雨记住了这一局）或**保持世界的漠然**（雨还在下）。
4. **语境绑定**：每条候选标注适用波次区间 / 失败 severity，让用户定稿时有对照物（2-3 选 1）。

### 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 只新建 `mini-pong/content/wave_failure_text.json`（+ 本 PRD）；**不碰 `mini-pong/` 任何运行时文件** |
| 引擎版本 | Godot 4.7.1，`config/features=PackedStringArray("4.7")` |
| 竖屏 | 720×1280（P0 轴交换已确认）；副句 ≤15 字、失败短句 ≤10 字均按竖屏单行可读性设计 |
| 消费方协议 | #390/#391 从"统一文本配置"读取 → content 资源必须是**运行时可加载**的独立文件（JSON，非 docs 文档） |
| 文案语言 | 中文（游戏文案语境为中文，UI 已有英文保留项 YOU WIN! / AI WINS! 属 MVP 旧版，PONG://21 失败屏/转场文案为中文） |
| 测试基线 | #346 修复后全绿；纯内容文件改动不触发任何测试差异 |
| E2E | `e2e_shots.json` 断言不涉及波次转场/失败屏文案（新插槽），无影响 |
| 品味档案 | docs/TASTE.md v1（#367 手感定稿）——B5 文案定稿差异后续回写其"风格特征"节 |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/content/wave_failure_text.json` | B5 内容资源（波次副句 + 失败短句候选清单） | **新增**：独立 content 资源，`draft: true` + 候选表 + 适用语境 + 情感断言 + 推荐标记 |

### 新增文件

| 文件 | 用途 |
|------|------|
| `mini-pong/content/wave_failure_text.json` | B5 校准接口（失败事件表 + 候补清单）：波次副句 ≥3 候选（≤15 字/条 × 适用波次）+ 失败短句 ≥3 候选（≤10 字/条 × 失败 severity）+ 情感断言 + 推荐标记；`draft: true` 顶层标记；#390/#391 运行时从此文件读取 |
| `docs/PRD/396-wave-failure-copy-draft.md` | 本 PRD（research 产出） |

### 间接影响

| 模块 | 影响 |
|------|------|
| `mini-pong/gdscripts/*.gd` / `scenes/*.tscn` | **零改动** —— 文案不散落代码注释（AC5），机械插槽由 #390/#391 实现 |
| `mini-pong/gdscripts/constants.gd` | **零改动** —— 文案不进代码常量层（与 A1 数值单一事实源职责分离） |
| `docs/TASTE.md` | 不改（本次草稿不落 TASTE.md；用户定稿后由 review agent 把 B5 风格特征回写） |
| `mini-pong/tests/*.gd` / `e2e_shots.json` | **零改动** —— 纯内容文件，无运行时差异 |

### 数据流

```
候选清单（§4.2：波次副句 ≥3 × ≤15字 × 语境 + 失败短句 ≥3 × ≤10字 × severity）
    │
    ▼
mini-pong/content/wave_failure_text.json（draft: true + 推荐标记）← B5 校准接口
    │  （review 定稿就绪检查 → merge → status/human-review + assign 用户）
    │  （#390 波次转场 / #391 失败屏 运行时从本文件读取）
    ▼
用户定稿（Assigned to me 队列）：选 1 / 微调 → push → close
    │
    ▼
定稿差异回写 docs/TASTE.md（B5 风格特征：如"删形容词、雨意象"）→ 下次草稿朝此方向
```

---

## 4. 方案对比

### 4.1 内容资源载体（AC5：独立 content 资源，不散落代码）

**Approach A：`mini-pong/content/wave_failure_text.json` 独立 JSON（推荐）**

新建 `mini-pong/content/` 目录，单一 JSON 文件承载波次副句 + 失败短句两组候选。

- Pros：**运行时可加载**（#390/#391 用 `FileAccess.get_file_as_string()` + `JSON.parse_string()` 直接读取，满足"从统一文本配置读取"）；AC5 字面要求（独立 content 资源）；JSON 天然结构化（候选 × 语境 × 情感断言）；不碰任何 .gd 文件
- Cons：需新建 content/ 目录（Godot 自动导入，无额外配置）
- Risk: Low ／ Effort: 0.5 天

**Approach B：GDScript 常量字典（content_text.gd）**

在 gdscripts/ 新建一个只含 `const WAVE_SUBTITLES = {...}` 的内容脚本。

- Pros：类型安全、无需解析
- Cons：**违反 AC5 精神**（"不作为注释散落代码"——.gd 常量即代码层）；文案与逻辑混在同一目录；用户定稿需改代码文件
- Risk: Med ／ Effort: 0.5 天

**Approach C：docs/ 下 Markdown（如 docs/WAVE_FAILURE_TEXT.md）**

照搬 #378 docs/NAMING.md 的文档模式。

- Pros：与 #378 命名档案模式一致
- Cons：**docs/ 不在 `res://` 内**（`res://` = `mini-pong/`），#390/#391 无法运行时读取——违反消费方协议（"从统一文本配置读取"）；文案与运行时脱节
- Risk: High ／ Effort: 0.5 天

**结论：选 A。** B5 文案与 B2 命名（docs/NAMING.md）不同——命名是元信息（玩家第一眼），文案是**运行时消费内容**（每波/每次失败都要显示），必须落在 `res://` 内可加载的 JSON。JSON 无注释语法，`# DRAFT` 语义用顶层 `"draft": true` + 每候选 `"recommended": true` 标记表达。

### 4.2 候选清单（核心交付：波次副句 4 候选 × 失败短句 4 候选）

> 依据：PONG://21 审美坐标（雨夜竞技场 + 克制优先）+ Obsidian 设计语言（§2）+ B5 品味（失败=叙事生产）。**这些是 research 建议，implement 原样填入 content JSON，用户做最终裁决（≥3 选 1）。**

#### 4.2.1 波次副句（波次转场「第 N 道墙」下方，≤15 字）

| # | 候选副句 | 字数 | 适用语境（第几波） | 情感断言（体验引擎） | 设计说明 |
|---|---------|:---:|-------------------|---------------------|---------|
| 1 | **雨声盖过心跳** ⭐推荐 | 6 | 波 1-2（开局/教学薄墙） | 仪式感的平静——开局"呼吸点"，雨声替代心跳，张力尚未升起 | 开局副句只做氛围铺垫，不预告难度；动词"盖过"给短句击打感 |
| 2 | **每一道墙都更厚** | 7 | 波 3-5（中段加压） | 递增的压迫——Challenge 可视化，玩家"看见"难度曲线（PLAN：墙厚/密度递增） | 陈述事实，不加感叹；"更厚"是单修饰词，符合无形容词堆砌红线 |
| 3 | **雨越下越大** | 5 | 波 6+（后期高压） | 渐强的紧张——雨量因子 +0.1/波 的文案化，压力表读数 | 与雨量系统同构（rain = f(波次)）；零形容词，纯陈述 |
| 4 | **拆到墙倒为止** | 6 | 决胜波（比分接近 21） | 冷静的决心——不呐喊的决绝，动词"拆"驱动 | 决胜句不放狠话、不加感叹号；"为止"收束，海明威式 |

#### 4.2.2 失败短句（失败屏，≤10 字）

| # | 候选短句 | 字数 | 适用语境（失败 severity） | 情感断言（体验引擎） | 设计说明 |
|---|---------|:---:|--------------------------|---------------------|---------|
| 1 | **雨还在下** ⭐推荐 | 4 | 早败（波 1-2 教学波即败） | 世界的漠然——失败不惩罚、不鼓励，世界照常运转（空洞骑士式沉默） | B5 核心品味"失败=叙事生产"的最纯形态；雨替玩家承担情绪 |
| 2 | **雨记住了这一局** | 7 | 中败（波 3-5，有实质 run 数据） | 失败被铭记——拆砖/穿墙数据随雨留存，run 有痕迹 | 与失败屏 run 数据（波次/拆砖/穿墙）呼应：数据即记忆 |
| 3 | **就差一道墙** | 5 | 晚败/惜败（波 6+ 或比分接近 21） | 克制的遗憾——极乐迪斯科式文学时刻："你无法让金尊重你"的同类语法 | 只差一线的悔意，用"墙"（进程表）量化；零形容词 |
| 4 | **墙还在，雨未停** | 7 | 通用兜底（任意波次） | 无声的坚韧——不煽情的中立陈述，可作默认短句 | 双意象并列（进程仍在 + 压力未消）；逗号制造留白 |

> 全部候选通过海明威校验：无感叹号、无形容词堆砌（每句修饰词 ≤1）、无 emoji、无网络梗、无"你输了/太弱了"惩罚性措辞、无"下次一定"式空洞鼓励。字数均低于 AC 上限（副句 ≤15 / 短句 ≤10）。

### 4.3 内容资源 JSON 结构

**Approach A：单一 JSON 双组（推荐）**

```json
{
  "schema": "wave-failure-text/v1",
  "draft": true,
  "wave_subtitles": [
    { "id": "ws1", "text": "雨声盖过心跳", "context": "波 1-2（开局）", "emotion": "仪式感的平静", "recommended": true }
  ],
  "failure_phrases": [
    { "id": "fp1", "text": "雨还在下", "context": "早败（波 1-2）", "emotion": "世界的漠然", "recommended": true }
  ]
}
```

- Pros：一个文件覆盖两个插槽（#390 读 `wave_subtitles`、#391 读 `failure_phrases`）；字段即 B5 校准接口（失败事件表 + 候补清单）；`draft: true` 顶层标记 = JSON 世界的 `# DRAFT`
- Cons：无（单一事实源，职责清晰）
- Risk: Low ／ Effort: 0.5 天

**Approach B：两个 JSON 分文件（wave.json + failure.json）**

- Pros：插槽物理隔离
- Cons：两个文件两处维护；#390/#391 各读一个文件，无共享 schema 收益
- Risk: Low ／ Effort: 0.5 天

**推荐 A：** 单一文件 + 双组，schema 版本化（`wave-failure-text/v1`），字段名与 #390/#391 读取点一一对应（`wave_subtitles[].text` / `failure_phrases[].text`）。

### 推荐与理由

**4.1 选 A（content JSON）+ 4.2 波次副句候选 1「雨声盖过心跳」/ 失败短句候选 1「雨还在下」为主推荐 + 4.3 选 A（单一 JSON 双组）**：

1. **B5 协议对齐**：taste-ownership-domains.md 规定失败文本 → 候补清单（2-3 选 1）+ 失败事件表 —— §4.2 恰好是 ≥3 候选 × 适用语境的完整清单；
2. **AC 全命中**：≥3 候选 ✅（各 4 条）/ ≤15 与 ≤10 字 ✅ / 海明威式无感叹号无形容词堆砌 ✅ / 适用语境 ✅（波次区间 + severity）/ 独立 content 资源 ✅（JSON，非代码注释）；
3. **消费方协议**：#390「副句从统一文本配置读取」+#391「短句从配置读取」→ 只有 `res://` 内 JSON（4.1-A）满足运行时读取，docs/ 文档（4.1-C）不满足；
4. **品味方向**：主推候选均以"雨"为情绪载体（与雨量系统同构），失败短句「雨还在下」是"失败=叙事生产"的最纯表达（世界漠然 ≠ 惩罚），符合 B5 领域最易写错点的反向校准；
5. **语境绑定**：4 条副句 × 波次区间 + 4 条短句 × severity，用户定稿有完整对照物，可 2-3 选 1 或跨候选混搭。

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 5 条 AC）

- [x] **AC1: 波次副句 ≥3 条候选，每条 ≤15 字** — §4.2.1 提供 4 条（6/7/5/6 字）
  - 验证：implement 后 `python3 -c "import json; d=json.load(open('mini-pong/content/wave_failure_text.json')); assert len(d['wave_subtitles'])>=3 and all(len(s['text'])<=15 for s in d['wave_subtitles'])"`
- [x] **AC2: 失败短句 ≥3 条候选，每条 ≤10 字** — §4.2.2 提供 4 条（4/7/5/7 字）
  - 验证：同上断言 `len(d['failure_phrases'])>=3 and all(len(f['text'])<=10 for f in d['failure_phrases'])`
- [x] **AC3: 海明威式短句，无形容词堆砌和感叹号** — 全部候选修饰词 ≤1、无 `！`/`!`、无 emoji
  - 验证：`grep -c '[！!]' mini-pong/content/wave_failure_text.json` 为 0；review agent 逐条人工比对（T2 不可断言，机器只能查感叹号，形容词堆砌靠人）
- [x] **AC4: 每条注明适用语境（第几波/失败 severity）** — 每候选含 `context` 字段（波次区间 / severity 分级）
  - 验证：`python3 -c "import json; d=json.load(open('mini-pong/content/wave_failure_text.json')); assert all('context' in x for x in d['wave_subtitles']+d['failure_phrases'])"`
- [x] **AC5: 文案放入独立 content 资源，不作为注释散落代码** — 单一 JSON 文件；`grep -rn "雨还在下\|雨声盖过心跳" mini-pong/gdscripts/ mini-pong/scenes/` 为空
  - 验证：content 文件存在；`mini-pong/gdscripts/`、`mini-pong/scenes/` 内无任何候选文案字符串

### 边界条件

1. **文案不进代码层**：`constants.gd` / gdscripts / scenes / tests 零改动；文案只在 `mini-pong/content/wave_failure_text.json`（AC5 字面要求）。
2. **机械插槽不越权**：本 Issue 只产出文案候选，**不实现**转场/失败屏的读取逻辑（#390/#391 的机械职责）；content JSON 的 schema 字段名与 #390/#391 读取点对齐即可。
3. **风格红线**：无感叹号（含全角 `！`）、无形容词堆砌（修饰词 ≤1）、无 emoji、无网络梗、无惩罚性措辞（"你输了/太弱"）、无空洞鼓励（"下次一定"）。任何候选超出即视为违反 AC3。
4. **字限硬约束**：副句 ≤15 字、失败短句 ≤10 字（含标点）；超出即违反 AC1/AC2。
5. **draft 语义**：JSON 顶层 `"draft": true` = `# DRAFT` 标记（JSON 无注释语法）；用户定稿后由用户移除 draft 标记或由 review agent 在定稿 PR 中处理。
6. **推荐标记不越权**：`"recommended": true` 是 research 建议，用户可改选任何候选（含跨组混搭：副句选 3 + 短句选 1）。
7. **TASTE.md 语义**：B5 文案定稿差异回写 docs/TASTE.md"风格特征"节（如"删形容词、雨意象"），但本次草稿不写 TASTE.md。
8. **E2E 正交**：波次转场/失败屏为 PONG://21 新插槽，`e2e_shots.json` 现有断言不涉及，互不影响。

### 失败路径

1. **implement 误改运行时**（改 gdscripts/scenes 凑"生效"）→ 违反 AC5/边界 1。缓解：PRD §5 边界 1 明示，review agent 用 AC5 的 grep 检查卡口。
2. **候选缺要素**（缺语境或缺情感断言或缺推荐标记）→ 用户无法对照定稿。缓解：review agent 按 §4.2 表结构逐条核对（text/context/emotion/recommended 四字段）。
3. **字限超限 / 感叹号残留** → 违反 AC1/AC2/AC3。缓解：implement 用 §5 AC1-AC3 的 python/grep 验证命令自检。
4. **文案写进 .gd 注释** → 违反 AC5 精神。缓解：边界 1 grep 检查（gdscripts/ 内无候选字符串）。
5. **JSON 结构不符**（字段名与 #390/#391 读取点不一致）→ 消费方读不到。缓解：§4.3 schema 版本化（`wave-failure-text/v1`），implement 原样落地，review 核对字段名。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| PONG://21 方案（docs/PLAN-rogue-pong.md，2026-08-13 用户拍板） | ✅ 已确认 | 无（审美坐标与插槽语义来源） |
| #390 波次转场（消费方：副句从统一文本配置读取） | 📋 管线待办（本 Issue 不依赖其实现） | 低（本 Issue 只产内容；schema 对齐即可） |
| #391 失败屏（消费方：短句从配置读取） | 📋 管线待办（同上） | 低 |
| #395 升级池文案定稿（B2/B5 兄弟 Issue，独立 content 资源） | 📋 管线待办 | 低（不同插槽：升级池 vs 波次/失败；各自独立 JSON，无冲突） |
| taste-ownership-domains.md（B5 失败表达协议：候补清单 + 失败事件表） | ✅ 项目内参考 | 无 |
| docs/TASTE.md（品味档案 v1：#367 手感定稿） | ✅ 存在 | 无（本次草稿不回写，定稿后回写） |

```
PONG://21 方案（雨夜竞技场 + 克制优先）──┐
#395 升级池文案（兄弟 B2/B5，独立 JSON）──┼──► #396（本 Issue，波次/失败文案候选草稿）
#390 波次转场 / #391 失败屏（消费方）─────┘        │
                                                   ▼
              mini-pong/content/wave_failure_text.json ──► 用户定稿（Assigned to me 队列）
```

**无阻塞。** v4 语义：本 Issue 是 human Issue（taste-draft，B5 失败表达），**不进依赖链** —— 草稿 merge 即满足下游消费方（#390/#391 可运行时读取 content JSON 的存在），下游机械 Issue 不等用户定稿。

---

## 7. Spike / 实验

Skipped per `depth/standard`（Issue 无 depth 标签，按 standard 处理；Section 7 仅 `depth/deep` 必填）。文案候选不需要实验——候选清单本身就是交付物（B5 协议：agent 给候选，人做最终裁决）；文案对运行时零影响，无可验证的机械行为。

---

## 8. 延续上下文（Continuation Context）

**给 plan agent 的手递**（plan agent 产出 DESIGN 时直接采用，无需重扫源码）：

**系统状态**：PONG://21 攻城战肉鸽方案已确认（2026-08-13，docs/PLAN-rogue-pong.md）；波次转场（#390：大字「第 N 道墙」+ 副句，2s 淡入-停留-淡出，副句从统一文本配置读取）与失败屏（#391：短句 + run 数据 波次/拆砖/穿墙，短句从配置读取且无 emoji/夸张语气）为机械插槽，**内容为空**；`mini-pong/` 无任何 content 资源目录（需新建 `mini-pong/content/`）；竖屏 720×1280（P0 轴交换已确认）；审美坐标 = 雨夜竞技场（雨量 = 情绪仪表盘）+ 霓虹描边 UI + 克制优先。B5 品味方向：失败 = 叙事生产（非惩罚）、海明威式冰山（无形容词堆砌/无感叹号）、雨/墙意象同构。

> **2026-08-13 复核更新（见 §0）**：本段「内容为空 / 无 content 资源目录」描述已过时 —— main 已有 #405 落地的 `mini-pong/assets/content/upgrade_pool.json`（#395）；#396 的 content 资源由 open PR #407 按 DESIGN §2 落地于 `mini-pong/content/wave_failure_text.json`。实施阶段以 DESIGN #406 为准，路径约定分歧见 §0。

**主风险**：
1. implement 误改运行时文件（gdscripts/scenes）凑"生效"→ 违反 AC5（§5 失败路径 1）
2. 候选缺要素（语境/情感断言/推荐标记）→ 用户无法对照定稿（§5 失败路径 2）
3. 定稿流程混淆：本 Issue 是文案草稿，**不 close**——定稿由用户完成（选 1 / 微调 → push → close）；PR 用 `parent #396` 不写 Closes

**下一步（plan → implement）**：
1. DESIGN 引用本 PRD §4.2 候选清单（4 副句 × 4 短句 × 适用语境 × 情感断言）与 §4.3 JSON schema（`wave-failure-text/v1`，字段：id/text/context/emotion/recommended），明确 `mini-pong/content/wave_failure_text.json` 结构
2. implement 只新建 `mini-pong/content/wave_failure_text.json`：顶层 `"draft": true` + `wave_subtitles[]`（≥3，≤15 字，含推荐标记）+ `failure_phrases[]`（≥3，≤10 字，含推荐标记）；**机械部分零改动**；按 §5 AC1-AC5 验证命令自检
3. review agent：定稿就绪检查（结构完整 + taste 对齐：海明威式/无感叹号/无形容词堆砌 + 机械无文案残留 + diff 仅 content JSON）→ merge（PR 用 `parent #396`）→ 打 `status/human-review` + assign 用户（workflow-chain.yml 自动）
4. 用户定稿：从 §4.2 选 1（或微调）→ push → close；差异回写 docs/TASTE.md 风格特征节 —— 下次同类 B5 文案草稿的方向来源
5. 消费方衔接：DESIGN 阶段确认 #390（波次转场）读 `wave_subtitles[].text`、#391（失败屏）读 `failure_phrases[].text`，字段名与本 PRD §4.3 schema 一致

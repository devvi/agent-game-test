# PRD: [Content] 波次副句与失败短句 — 候选清单草稿 (B5)

> **Issue:** #396
> **标签:** enhancement, content, version/full, workflow/available, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/light（RAW JSON 标注 light；GitHub Issue 无 depth 标签，按 #395/#378 惯例处理：Section 1–6 + 8 完整，Section 7 跳过）
> **所有权:** `content_ownership: taste-draft`（人机共做 v4 — B5 失败表达领域；agent 生成带 taste 方向的候选草稿：2-3 选 1 + 语境说明；草稿达标即 merge，PR 用 `parent #396` 不写 Closes；review agent 打 `status/human-review` + assign 用户定稿）
> **taste 方向来源:** Issue 审美坐标（雨夜竞技场，PLAN-rogue-pong §3 已确认）+ 霓虹赛博视觉（#289 落地）+ 项目品味档案（docs/TASTE.md v1，来自 #367）+ Obsidian 知识库检索

---

## 1. 问题定义

### 当前状态

Rogue Pong 的**波次节奏与失败表达文案完全空白**：机械层与 UI 插槽已预留（#390 波次转场、#391 失败屏均为 OPEN），但**没有任何副句/短句的 content 资源**。PLAN-rogue-pong §3.3 只写了占位描述（波次转场 = 大字「第三道墙」+ 海明威式副句 2s；失败屏 = 短句为主 + run 数据），具体文案待本 Issue 产出。B5 领域是 taste-ownership-domains.md 明示的**最容易被 agent 写错**的领域——默认"失败=惩罚"，而项目品味是"失败=叙事生产"（极乐迪斯科式失败生产文学时刻），本 Issue 的全部文案必须执行这条 taste 方向。

| 系统 | 当前状态 | 缺失 |
|------|---------|------|
| Issue #390（波次转场，OPEN） | ✅ 定义转场行为：大字「第 N 道墙」+ 副句、2s 淡入/停留/淡出、暂停、副句从统一文本配置读取（AC5） | ❌ 副句数据源未定义、无候选文案 |
| Issue #391（失败屏，OPEN） | ✅ 定义失败屏行为：短句 + run 数据（波次/拆砖/穿墙）、短句从配置读取且无 emoji/夸张语气 | ❌ 短句数据源未定义、无候选文案 |
| `docs/PLAN-rogue-pong.md` §3.3 | ✅ 确认 UI 形态（波次转场/失败屏）与克制优先 | ❌ 无具体文案（只示例「第三道墙」） |
| `docs/PLAN-rogue-pong.md` §3.2 | ✅ 雨幕情绪仪表盘：波失败 → rain 1.0（宣泄） | — 副句/短句应与之呼应（失败不是惩罚，是宣泄） |
| `mini-pong/assets/` | ✅ 已有 neon_glow_material.tres / particle_material.tres / gradient_neon.tres | ❌ 无 content 目录、无文案资源文件 |
| `mini-pong/gdscripts/` | ✅ 运行时逻辑（ball/paddle/constants…） | ❌ 无任何副句/短句硬编码（好事——AC5 要求零硬编码） |
| `mini-pong/assets/content/upgrade_pool.json` | ⏳ #395 草稿已 merge（升级池文案，B2/B5 同簇） | — 本 Issue 与其并列独立资源，互不覆盖（见 §6 去冲突） |
| `docs/TASTE.md` v1（#367 产出） | ✅ 手感定稿 + 风格方向（"删形容词、短句"） | — 本 Issue 只引用，不写入 |

### 预期行为（验收条件，源自 Issue #396）

1. **至少 3 条波次副句候选，每条 ≤15 字** —— 波次转场「第 N 道墙」下方的一行克制副句
2. **至少 3 条失败短句候选，每条 ≤10 字** —— 失败屏的主文案
3. **全部为海明威式短句，无形容词堆砌和感叹号** —— 克制红线（TASTE.md v1 + PLAN §3.3）
4. **每条注明适用语境（第几波/失败 severity）** —— 文案不是一刀切，按波次区间/失败程度分级
5. **文案放入 content 资源配置，不作为注释散落代码** —— 数据与逻辑分离（与 #395 同协议）

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 波次转场 | 每波一次（2s） | 大字「第三道墙」下方一行副句（≤15 字），给玩家一个呼吸点；副句随波次推进换档（教学波/常规波/高压波） |
| B | 失败屏 | 每次 run 结束 | 一行短句（≤10 字）+ run 数据；短句按失败 severity 分级——**失败是叙事生产不是惩罚**（§2 taste 方向），玩家重开前被一句话击中 |
| C | 用户定稿（v4 队列） | 每次草稿 merge 后 | GitHub Assigned to me 攒批：打开 Issue → 对照候选表选句/微调 → push 定稿 → close |
| D | implement agent 填草稿 | 本管线一次 | 按本 PRD §4.4 候选表 + §4.1 JSON schema 写入 `mini-pong/assets/content/wave_failure_lines.json`（`draft:true` + 候选 + 语境），机械零改动 |
| E | review agent 定稿就绪检查 | 每次实现 PR | 结构完整（≥3 波次副句 + ≥3 失败短句 + 语境齐全）+ taste 方向对齐（对照 §2 逐项比对）+ 机械部分无 DRAFT 残留 |

### 技术约束（继承自 Issue #396）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`；Rogue Pong 改造后 720×1280 竖屏，见 PLAN-rogue-pong §4.1） |
| 领域判定 | B5 失败表达：T1 主观性 ✅（两个专家对"哪句更好"答案不同）/ T2 不可断言 ✅（无法 `assert 短句 == "..."` 验证"好"）/ T3 语境 ✅（同样的句子换到别的游戏不成立）→ 人机共做领域 |
| 风格 | 雨夜竞技场（PLAN-rogue-pong §3：雨幕粒子 + 城市光晕 + 暗角 + 霓虹描边 UI，**克制优先**）+ 街机爽感（#367 TASTE.md v1：删形容词、短句）+ **失败=叙事生产**（B5 核心，§2） |
| 文案红线 | 波次副句 ≤15 字、失败短句 ≤10 字；无网络梗/emoji/感叹号；海明威式（名词+动词，无形容词堆砌） |
| 所有权 | taste-draft：PR 用 `parent #396`（小写 p）不写 Closes；草稿达标即 merge，不等人定稿，不进依赖链 |
| 产出边界 | 只新建 content 资源文件（+ 本 PRD）；**不修改任何运行时逻辑**（#390/#391 未实现前无消费方，文案先行落地为纯数据） |
| 开源优先 | Issue 上下文要求先搜 Godot Asset Library / GitHub 社区再动手——**文案类任务无第三方资产可复用**（Godot 原生 `FileAccess` + `JSON.parse_string()` 加载即可，零依赖），调研结论见 §4.1 |

---

## 2. 设计意图

### 为什么现在做

这是 v4 人机共做队列的 **B5 失败表达** 内容 Issue。波次循环（#386）是 Rogue Pong 的核心节奏骨架，波次转场（#390）与失败屏（#391）是它的两个**文案插槽**——但 taste-ownership-domains.md 明示：B5 是最容易被 agent 写错的领域，**默认"失败=惩罚"，而品味是"失败=叙事生产"**。本 Issue 在机械层排队期间把文案先行落地为独立 content 资源，草稿达标即 merge，assign 用户定稿，不阻塞下游机械 Issue。

### 审美坐标与 taste 方向（研究关键发现）

Issue 注入的审美坐标：**雨夜竞技场**（PLAN-rogue-pong §3 —— 雨幕是情绪仪表盘：平静 0.3 → 胶着 0.7 → 爆发 0.9 → **波失败 1.0 宣泄**；暗底霓虹 #289：#0a0a12 背景 + 玩家蓝 #4a90d9 + AI 红 #ff3355）+ **街机爽感**（#367 手感：利落击打、直接不绕弯、可控性优先）+ **B5 失败即叙事**。

**Obsidian 知识库检索**（`/Volumes/Obsidian/Knowledge Ocean/wiki/`，本机已挂载）找到的可迁移设计语言：

| 笔记 | 可迁移到本 Issue 的设计语言 |
|------|---------------------------|
| `极乐迪斯科—概率机制作为叙事语法.md` §5 | **失败生产文学时刻**：红色检定失败时游戏写出"你无法让金尊重你"——这句不会在成功时出现。→ **失败短句 = 成功时永远不出现的句子**；它记录"你失去了什么"，而非"你做错了什么"。§5.1 "失败前行 (Failing Forward)"：失败打开另一条路径而非惩罚 → 短句应暗示"墙记住了你，但你带走了数据"，而不是"你输了" |
| `体验引擎-patterns.md` §多级成败 | 创建**多级成功和失败**（评分系统、分级评判、不会结束游戏的局部失败）→ **失败 severity 分级**是叙事分层而非惩罚分级：早期失败 = 轻描淡写（路还长），后期失败 = 浓墨重彩（墙记住你了） |
| `空洞骑士—沉默作为叙事策略.md` | 克制 = 叙事的负空间："说出的部分远少于未说出的" → **短句越短越有力**：波次副句 5-9 字为佳（≤15 红线）、失败短句 4-8 字为佳（≤10 红线）；留白本身就是雨夜氛围 |
| `Papers Please—官僚机制作为悲剧结构.md`（#367 已引用） | 海明威式冰山理论 = 文本密度标准 → 每句只留"水面上的八分之一"，情绪藏在字下 |
| `This War of Mine—生存机制作为道德叙事.md` | 日记/内心反应文本记录事件的情感而非事实 → 失败短句记录**情感残留**（"雨还在下"）而非事实（"你第 4 波失败"）——事实交给 run 数据展示 |
| `90年代地摊文艺.md`（#378 已引用） | 街机文化的粗粝、直接——**反例约束**：避免过度文艺化（长句/生僻词/为了文艺而文艺） |

**taste 方向综合（本 PRD 的注入方向，即 content 资源初版的方向）**：

1. **失败 = 叙事生产，不是惩罚**：短句永远不说"你输了/太弱/重来"（惩罚性）；说"你失去了什么/墙记住了什么"（叙事性）。这是 B5 与默认写法的分水岭。
2. **克制短句**：波次副句 5-9 字为主（≤15 红线）、失败短句 4-8 字为主（≤10 红线），名词+动词，无形容词堆砌、无感叹号——像雨夜墙上的霓虹灯牌，一句即止。
3. **语境分级**：波次副句按教学波/常规波/高压波换档；失败短句按 severity（轻/中/重）分级——不是一刀切的一句话。
4. **雨夜意象渗透**：雨、夜、墙、影、灯等竞技场意象词优先，但**意象服务于克制**，不堆砌修辞；事实数据（波次/拆砖/穿墙）交给 run 数据区展示，短句只负责情感残留。
5. **与 #395 同簇不同界**：#395 管升级池（9 升级短句+命名），本 Issue 管波次/失败节奏文案——两套独立资源、独立定稿（§6 去冲突）。

### 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 只新建 `mini-pong/assets/content/wave_failure_lines.json`（+ 本 PRD）；**不碰 `mini-pong/gdscripts/` 任何运行时文件** |
| 引擎版本 | Godot 4.7.1，`config/features=PackedStringArray("4.7")` |
| 消费方 | #390 波次转场（副句，AC5"副句从统一文本配置读取"）/ #391 失败屏（短句，AC"短句从配置读取且无 emoji/夸张语气"）—— 本 PRD 只定义**文案数据契约**（JSON schema），机械接入由 #390/#391 负责 |
| 文案语言 | 中文（Issue 明示；波次转场/失败屏为中文语境，与游戏内既有英文 UI（YOU WIN!）不同层——新 UI 层 #390/#391 按中文渲染） |
| 测试基线 | 当前 main 全绿；纯数据文件不触发任何测试差异（#390/#391 未落地前无消费方读取） |
| E2E | `e2e_shots.json` 现有 shot 均不涉及波次转场/失败屏文本 —— 无影响 |
| 品味档案 | docs/TASTE.md 不改（本次草稿不落 TASTE.md；用户定稿后由 review agent 把风格特征回写） |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/assets/content/wave_failure_lines.json` | 波次/失败节奏文案资源（B5 校准接口 = 候选清单 + 语境注释） | **新增**：波次副句 ≥3 条 + 失败短句 ≥3 条 ×（候选 + 语境 + `draft`） |

### 新增文件

| 文件 | 用途 |
|------|------|
| `mini-pong/assets/content/wave_failure_lines.json` | 波次副句与失败短句草稿单一资源：`schema: "wave-failure-content/v1"` + `draft: true` + `wave_quips[]`（≥3）+ `failure_lines[]`（≥3）（详见 §4.1 schema 与 §4.4 候选表）；用户定稿差异直接改此文件 |

### 间接影响

| 模块 | 影响 |
|------|------|
| `mini-pong/gdscripts/*.gd`（#390/#391 待建） | **零改动**（本 Issue 不实现机械层）；未来由 #390/#391 读取本 JSON |
| `mini-pong/assets/content/upgrade_pool.json`（#395 已 merge） | **零改动** —— 独立资源、独立 schema、独立定稿队列（见 §6 去冲突） |
| `scenes/`（#390 波次转场 / #391 失败屏 待建） | **零改动**（本 Issue 不碰 UI）；未来由 #390/#391 渲染本 JSON 字段 |
| `e2e_shots.json` / `run-e2e-review.sh` | **零改动** —— 无波次/失败文本断言 |
| `docs/PLAN-rogue-pong.md` / `docs/TASTE.md` | 不改（见 §6 去冲突；定稿差异由 review agent 回写 TASTE.md） |

### 数据流

```
docs/PLAN-rogue-pong.md §3.3（波次转场/失败屏 UI 形态确认稿）
    │
    ▼
mini-pong/assets/content/wave_failure_lines.json（本 Issue：draft 草稿 + 候选 + 语境）
    │  （review 定稿就绪检查 → merge → status/human-review + assign 用户）
    ▼
用户定稿（Assigned to me 队列）：改 JSON 短句/选句 → push → close
    │
    ▼
#390 波次转场 / #391 失败屏 读取 JSON → 渲染（机械层，不在本 Issue）
    │
    ▼
定稿差异回写 docs/TASTE.md（风格特征：如"失败短句 4-8 字、叙事残留非惩罚、语境分级"）→ 下次草稿朝此方向
```

### 文档更新清单

- [x] `docs/PRD/396-wave-quips-failure-lines.md`（本文件）
- [ ] `mini-pong/assets/content/wave_failure_lines.json`（implement 阶段按 §4.1 schema + §4.4 候选表落地）

---

## 4. 方案对比

### 4.1 内容资源载体

**Approach A：JSON 资源文件（推荐，与 #395 同协议）**

新建 `mini-pong/assets/content/wave_failure_lines.json`，Godot 原生加载：`FileAccess.get_file_as_string("res://assets/content/wave_failure_lines.json")` + `JSON.parse_string()`（零第三方依赖，headless/CI 安全）。

```json
{
  "schema": "wave-failure-content/v1",
  "draft": true,
  "wave_quips": [
    {
      "id": "wave_1",
      "text": "第一道墙，热身",
      "text_draft": true,
      "context": "波 1（教学薄墙）—— 转场副句位，≤15 字"
    }
  ],
  "failure_lines": [
    {
      "id": "fail_light",
      "text": "雨还在下",
      "text_draft": true,
      "severity": "light",
      "context": "早期失败（波 1-2）—— 失败屏主文案位，≤10 字；轻描淡写，路还长"
    }
  ]
}
```

- Pros：纯数据（AC5 字面满足）；JSON 人类可编辑（用户定稿直接改文件，GitHub Web UI 即可）；与 #395 upgrade_pool.json 同协议（消费方加载方式一致）；schema 版本化便于 #390/#391 接入
- Cons：JSON 无注释 —— `#DRAFT` 用 `"draft": true` 字段表达（机器可断言，等价于 #DRAFT 标注）
- Risk: Low ／ Effort: 0.5 天

**Approach B：Godot Resource（.tres + 自定义 class）**

定义 `WaveContent` 资源类 + `.tres` 实例。

- Pros：类型安全，Godot 原生 Inspector 可编辑
- Cons：**用户定稿成本高**（需 Godot 编辑器打开，无法在 GitHub Web UI 直接改）；需新增 class 脚本（跨入机械层，超出纯数据边界）；.uid 文件噪音；与 #395 JSON 协议分叉
- Risk: Med ／ Effort: 1 天

**Approach C：GDScript 常量字典（content.gd）**

新建 `mini-pong/gdscripts/content_wave.gd` 暴露 `const WAVE_QUIPS = {...}`。

- Pros：Godot 直接引用，零加载代码
- Cons：**违反 AC5 精神**（文案硬编码在逻辑节点同目录的脚本文件里，不满足"独立 content 资源"）；用户定稿需改 GDScript（语法敏感）；与 #395 的 JSON 协议分叉
- Risk: High ／ Effort: 0.5 天

### 4.2 波次副句策略

**Approach A：随波换档的克制副句（推荐）**

副句按波次区间分级：波 1（教学薄墙）＝引导句 → 波 2-4（常规）＝氛围句 → 波 5+（高压）＝压迫句。每档 1 条候选（共 ≥3 条，满足 AC1），5-9 字为主。

- Pros：满足 AC4（每条注明适用语境——第几波）；呼应雨幕仪表盘（波次因子 +0.1/波，PLAN §3.2）；给玩家"节奏在推进"的体感
- Cons：档位边界（第几波算高压）需 implement 在配置里按 wave_index 映射（机械层 #390 的事，本 Issue 只给语境标注）
- Risk: Low ／ Effort: 0.5 天

**Approach B：全波次同一条副句**

不分档，一条副句用到底。

- Pros：实现最简单
- Cons：**违反 AC4**（每条注明适用语境——单条无语境可言）；第 1 波和第 8 波同一句话，仪式感塌缩；浪费"语境分级"的叙事机会
- Risk: Med ／ Effort: 0 天

**Approach C：每波独有副句**

每个 wave_index 一条（波 1/2/3/4/5…各不同）。

- Pros：最精细
- Cons：**超出 AC1 规模**（AC 只要求 ≥3 条）；无法预知玩家能打到第几波（文案可能永远用不上）；维护成本高
- Risk: Med ／ Effort: 1 天

### 4.3 失败短句策略

**Approach A：按 severity 分级的叙事残留句（推荐）**

短句按失败 severity 分级（轻 = 波 1-2 早期失败 / 中 = 波 3-5 / 重 = 波 6+ 后期失败），每级 1 条候选（共 ≥3 条，满足 AC2）。**叙事生产而非惩罚**：记录"你失去了什么/墙记住了什么"，事实数据（波次/拆砖/穿墙）交给 run 数据区。

- Pros：满足 AC4（失败 severity 语境）；执行 B5 核心 taste 方向（失败=叙事生产，极乐迪斯科"你无法让金尊重你"式）；轻/中/重三档覆盖玩家实际失败分布
- Cons：severity 档位映射（第几波算重）需 implement 在配置里按 wave_index 映射（机械层 #391 的事，本 Issue 只给语境标注）
- Risk: Low ／ Effort: 0.5 天

**Approach B：惩罚性短句**

"你输了/太弱了/再试一次"式。

- Pros：零 taste 风险（最保险的"正常"写法）
- Cons：**正面违背 B5 领域品味**（taste-ownership-domains.md 明示：默认"失败=惩罚"是 agent 最容易写错的；品味是"失败=叙事生产"）；与雨夜氛围冲突；玩家重开意愿下降
- Risk: High ／ Effort: 0.5 天

**Approach C：纯信息短句**

"第 4 波失败，拆砖 12"式——把 run 数据搬进文案。

- Pros：信息最准
- Cons：**与 #391 设计重复**（run 数据已有专门区域展示）；浪费短句位的叙事功能；无情感残留
- Risk: Med ／ Effort: 0.5 天

### 4.4 候选文案集合（核心交付：≥3 波次副句 + ≥3 失败短句，均带语境）

> 依据：Issue 审美坐标（雨夜竞技场 + 克制）+ Obsidian 设计语言（§2：失败生产文学时刻 / 多级成败 / 负空间 / 冰山理论）+ PLAN-rogue-pong §3（雨幕仪表盘、克制优先）+ TASTE.md 风格方向（删形容词、短句）。**这些是 research 建议草稿，implement 原样填入 wave_failure_lines.json，用户做最终裁决（每项 2-3 选 1）。**

**波次副句候选（≤15 字，推荐加粗）：**

| # | 语境（第几波） | 副句草稿（字数） | 设计理由 |
|---|--------------|---------|---------|
| 1 | 波 1（教学薄墙） | **第一道墙，热身**（7字） | 引导句：给新玩家"这是练习"的暗示，降低第一波压迫感；海明威式名词+动词 |
| 2 | 波 2-4（常规） | **雨势渐密**（4字） | 氛围句：呼应雨幕仪表盘（波次因子 +0.1/波）；零形容词堆砌，纯意象推进 |
| 3 | 波 5+（高压） | **墙越来越厚**（5字） | 压迫句：直接说难度在爬升，不绕弯（街机爽感）；"厚"是事实不是修辞 |
| 4（候补） | 波 5+（高压） | 夜在加深（4字） | 同档候补：雨夜意象更浓，但更文艺——用户 2 选 1 |

**失败短句候选（≤10 字，推荐加粗）：**

| # | 语境（severity） | 短句草稿（字数） | 设计理由 |
|---|----------------|---------|---------|
| 1 | 轻（波 1-2 早期失败） | **雨还在下**（4字） | 轻描淡写：早期失败不配浓墨重彩；"雨还在下"= 世界照常，路还长（失败前行 Failing Forward） |
| 2 | 中（波 3-5） | **墙记住了你**（5字） | 叙事残留：你失去了什么——你打过的墙记住了你；把 run 数据（拆砖数）的情感化表达留给玩家脑补 |
| 3 | 重（波 6+ 后期失败） | **夜最深的时候**（6字） | 浓墨重彩：后期失败的文学时刻；呼应雨幕 1.0 宣泄档；暗示"就差一点"的遗憾而非"你不行" |
| 4（候补） | 重（波 6+） | 雨把比分冲走了（7字） | 同档候补：更直白地把"失败"归因于雨（世界），而非归因于玩家（惩罚）；用户 2 选 1 |

**推荐与理由：**

**4.1 选 A（JSON）+ 4.2 选 A（随波换档）+ 4.3 选 A（severity 分级叙事残留句）**：

1. **AC5 字面满足**：只有 4.1-A 是"独立 content 资源文件"且零运行时改动——B 需新增资源类脚本（跨机械层），C 硬编码在脚本（违反 AC5 精神）；
2. **与 #395 同协议**：升级池文案已用 JSON（upgrade_pool.json），消费方加载方式一致，用户定稿流程一致（v4 队列零学习成本）；
3. **AC4 语境分级落地**：4.2-A 按波次区间、4.3-A 按 severity 分级——每条候选都带语境，恰好满足 AC4（"每条注明适用语境"）；B/C 方案要么无语境要么过度；
4. **B5 taste 方向执行**：4.3-A 的"叙事残留句"（"墙记住了你"）正面执行"失败=叙事生产"——记录失去而非惩罚；B 的惩罚性短句是 taste-ownership-domains.md 点名的常见错误；
5. **可校验**：短句长度（副句 ≤15 / 短句 ≤10）、无感叹号/emoji、候选数（≥3）、语境字段齐全——全部可写成脚本断言（review agent 定稿就绪检查用）。

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 5 条 AC）

- [x] **AC1: 至少 3 条波次副句候选，每条 ≤15 字** — §4.4 候选表 4 条（3 正式 + 1 候补）全齐，implement 填入 JSON `wave_quips[].text`
  - 验证：`python3 -c "import json; d=json.load(open('mini-pong/assets/content/wave_failure_lines.json')); assert len(d['wave_quips'])>=3; assert all(len(q['text'])<=15 for q in d['wave_quips'])"`
- [x] **AC2: 至少 3 条失败短句候选，每条 ≤10 字** — §4.4 候选表 4 条（3 正式 + 1 候补）全齐，implement 填入 JSON `failure_lines[].text`
  - 验证：同上脚本断言 `len(d['failure_lines'])>=3` 且 `all(len(l['text'])<=10 for l in d['failure_lines'])`
- [x] **AC3: 全部海明威式短句，无形容词堆砌和感叹号** — §4.4 草稿已合规（名词+动词、无 `！`、无 emoji、无"太弱/你输了"式惩罚语）
  - 验证：`grep -E '[！!]|[😀-🙏]' mini-pong/assets/content/wave_failure_lines.json` 为空（扩展校验可加 validate_hemingway 风格检查）
- [x] **AC4: 每条注明适用语境（第几波/失败 severity）** — 每条候选的 `context` 字段标注波次区间或 severity 档位
  - 验证：脚本断言每条均有非空 `context`；波次副句 context 含"波"，失败短句含 severity 字段
- [x] **AC5: 文案放入 content 资源配置** — 唯一文案载体 `mini-pong/assets/content/wave_failure_lines.json`
  - 验证：`git diff main...HEAD --stat` 仅含 `docs/PRD/396-*.md` 与 `mini-pong/assets/content/wave_failure_lines.json`；`grep -rn "雨还在下\|墙记住了你" mini-pong/gdscripts/` 为空

### 边界条件

1. **机械零改动**：本 Issue 只落 JSON 数据；#390/#391 未实现前不得在 gdscripts/ 写任何读取代码（消费方接入属 #390/#391 scope）。
2. **长度红线**：波次副句 ≤15 字、失败短句 ≤10 字（中文按字符计）；超长即视为违反 AC1/AC2 与克制方向。
3. **语境字段契约**：波次副句的 `context` 标注"波 N"或"波 N-M"区间；失败短句带 `severity`（`light`/`medium`/`heavy`）——#390/#391 按 wave_index 映射到档位（映射逻辑属机械层）。
4. **语言边界**：副句/短句为中文（Issue 明示）；游戏内既有英文 UI（YOU WIN! 等）不在本 Issue 范围，不得顺手中文化。
5. **draft 语义**：`draft: true` 是草稿标记；用户定稿时改为 `false` 或删除并 close —— review agent 用该字段区分草稿/定稿。
6. **无梗无感叹号**：网络梗、emoji、感叹号三类全禁——候补句同样适用；**惩罚性词汇**（你输了/太弱/重来）同样全禁（B5 红线）。
7. **与 #395 不串资源**：本资源只装波次副句 + 失败短句；升级短句/命名候选归 upgrade_pool.json（#395）——review agent 检查两文件互不越界。

### 失败路径

1. **implement 误改运行时**（在 gdscripts/ 写读取代码或把文案硬编码进 #390/#391 逻辑）→ 违反 AC5/边界 1。缓解：PRD §3/§5 明示，review agent 用 AC5 的 diff 检查卡口。
2. **候选缺要素**（缺条数/缺语境/缺 severity）→ 违反 AC1-AC4，用户无法对照定稿。缓解：review agent 按 AC1-AC4 逐条脚本断言。
3. **短句超长/形容词堆砌/带感叹号/惩罚性措辞** → 违反 AC1-AC3 与克制方向、B5 红线。缓解：review agent 对照边界 2/6 校验 + validate_hemingway 域规则。
4. **把升级文案混入本资源** → scope 越界（与 #395 冲突）。缓解：§6 去冲突表明示边界，review agent 检查 JSON 只含 wave_quips + failure_lines 两组条目。
5. **语境档位与 #390/#391 映射不一致**（如 severity 用词不同）→ 机械层匹配失败。缓解：边界 3 定义 `light/medium/heavy` 契约，implement 对照本 PRD 填写。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| PLAN-rogue-pong.md §3.3（波次转场/失败屏 UI 形态，2026-08-13 确认稿） | ✅ 已确认 | 无 |
| #289 霓虹赛博视觉（审美坐标：#0a0a12 + 蓝/红/紫霓虹） | ✅ CLOSED | 无 |
| #367 手感校准草稿（TASTE.md v1：删形容词、短句） | ✅ 定稿 | 无 |
| #395 升级池文案草稿（同簇 B5，独立资源协议先例） | ✅ 已 merge | 无 —— 两资源互不依赖，仅协议对齐 |
| #390 波次转场（消费方，副句读取） | ⏳ OPEN | 低 —— 消费方接入在 #390 scope，本 Issue 不阻塞 |
| #391 失败屏（消费方，短句读取） | ⏳ OPEN | 低 —— 消费方接入在 #391 scope，本 Issue 不阻塞 |

```
#289 霓虹赛博 ──────────┐
#367 手感（TASTE.md v1）──┼──► #396（本 Issue，波次/失败文案草稿）
#395 升级池文案（同簇先例）─┘        │
                                    ▼
        mini-pong/assets/content/wave_failure_lines.json ──► #390 波次转场（副句）
                                    │                        └─► #391 失败屏（短句）
                                    ▼
                      用户定稿（Assigned to me 队列）→ close 定稿
```

**Scope 去冲突表**（Patch 14：重叠检测结果）：

| 现有 PRD/文档 | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #395 PRD + upgrade_pool.json | 9 升级短句 + 命名候选（B2/B5，升级卡文案） | ❌ 不含升级文案——边界：本资源只装波次副句 + 失败短句，升级文案归 #395 资源 |
| #378 PRD + docs/NAMING.md | 游戏正式命名（B2，标题/副标题候选） | ❌ 不重做游戏名——只沿用其命名风格（短、直接、霓虹词缀） |
| #367 PRD + docs/TASTE.md v1 | A1 手感参数定稿 | ❌ 不碰手感值——只引用其风格方向（删形容词、短句） |
| #390（机械） | 波次转场行为（大字/2s/暂停/配置读取） | ❌ 不设计转场机制——只提供副句文案数据契约 |
| #391（机械） | 失败屏行为（短句 + run 数据/暂停/重开） | ❌ 不设计失败屏机制——只提供短句文案数据契约 |

**无阻塞。** v4 语义：本 Issue 是 human Issue（taste-draft，B5），**不进依赖链** —— 草稿 merge 即满足下游依赖，下游机械 Issue（#390/#391）不等用户定稿。

---

## 7. Spike / 实验

Skipped per depth/light（Issue 无 depth 标签，RAW JSON 标注 light；Section 7 仅 `depth/deep` 必填）。文案任务不需要实验——候选清单本身就是交付物（B5 协议：agent 给候选，人做最终裁决）；文案对运行时零影响，无可验证的机械行为。

---

## 8. 延续上下文（Continuation Context）

**给 plan agent 的手递**（plan agent 产出 DESIGN 时直接采用，无需重扫源码）：

**系统状态**：波次/失败节奏文案完全空白——#390 波次转场（大字「第 N 道墙」+ 副句，副句从配置读取）与 #391 失败屏（短句 + run 数据，短句从配置读取且无 emoji/夸张语气）均为 OPEN；`mini-pong/assets/content/` 目录不存在（需新建；#395 的 upgrade_pool.json 也在该目录）；`mini-pong/assets/` 已有 3 个视觉 .tres；消费方 #390/#391 机械接入不在本 Issue。审美坐标：雨夜竞技场（PLAN-rogue-pong §3：雨幕粒子/城市光晕/暗角/霓虹描边 UI，克制优先；雨幕仪表盘：波失败 → rain 1.0 宣泄）+ 霓虹赛博（#289）+ 街机爽感（#367 TASTE.md v1：删形容词、短句）。

**主风险**：
1. implement 误改运行时文件或在 gdscripts/ 写消费代码 → 违反 AC5/边界 1（§5 失败路径 1）
2. 候选缺要素（条数/语境/severity）→ 用户无法对照定稿（§5 失败路径 2）
3. 惩罚性措辞（你输了/太弱）混入 → 违反 B5 核心 taste 方向（§5 失败路径 3）
4. 与 #395 资源串扰 → 升级文案/波次文案混装（§5 失败路径 4）
5. 定稿流程混淆：本 Issue 是文案草稿，**不 close** —— 草稿 merge 后由 workflow-chain 打 `status/human-review` + assign 用户，用户改 JSON + close 即定稿

**下一步（plan → implement）**：
1. DESIGN 引用本 PRD §4.1 JSON schema（`wave-failure-content/v1`：wave_quips[] × {id/text/text_draft/context} + failure_lines[] × {id/text/text_draft/severity/context}）+ §4.4 候选表（4 波次副句 + 4 失败短句，含候补与推荐）
2. implement 只新建 `mini-pong/assets/content/wave_failure_lines.json`：≥3 波次副句 + ≥3 失败短句 ×（text + `draft:true` + 语境/severity）；**机械部分零改动**
3. review agent：定稿就绪检查（JSON schema 合法 + 条数/长度/语境齐全 + 无惩罚性措辞 + 无感叹号/emoji + 机械无 DRAFT 残留 + diff 仅数据文件）→ merge（PR 用 `parent #396`）→ `status/human-review` + assign 用户（workflow-chain.yml 自动）
4. 用户定稿：改 JSON 短句/选句（或微调）→ push → close；差异回写 docs/TASTE.md 风格特征节（如"失败短句 4-8 字、叙事残留非惩罚、语境分级"）——下次同类文案草稿的方向来源

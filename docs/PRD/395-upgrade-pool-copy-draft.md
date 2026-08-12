# PRD: [Content] 升级池文案定稿 — 9 升级短句与命名候选 (B2/B5)

> **Issue:** #395
> **标签:** enhancement, content, version/mvp, workflow/available, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/light（RAW JSON 标注 light；GitHub Issue 无 depth 标签，按 #378 惯例处理：Section 1–6 + 8 完整，Section 7 跳过）
> **所有权:** `content_ownership: taste-draft`（人机共做 v4 — B2 命名/文案 + B5 失败表达领域；agent 生成带 taste 方向的草稿：短句 + 命名候选（2-3 选 1 + 推荐）；草稿达标即 merge，PR 用 `parent #395` 不写 Closes；review agent 打 `status/human-review` + assign 用户定稿）
> **taste 方向来源:** Issue 审美坐标（雨夜竞技场，PLAN-rogue-pong §3 已确认）+ 霓虹赛博视觉（#289 落地）+ 项目品味档案（docs/TASTE.md v1，来自 #367）+ Obsidian 知识库检索

---

## 1. 问题定义

### 当前状态

升级池是波次成长的核心（每波 3 选 1），其**机械骨架已规划但未实现**（#387 升级池架构，OPEN），**面向玩家的文案完全空白**：9 个升级目前只有机械工作名（长臂/燃烧弹/破城锤/磁心/双生/缓时/预开洞/星尘/幻影，出自 #387 功能描述与 `docs/PLAN-rogue-pong.md` §2.5 确认稿），没有任何「升级卡短句 + 命名候选 + 情感断言」的 content 资源。3 选 1 升级 UI（#388，OPEN）是文案的直接消费方，但文案数据源尚未定义。

| 系统 | 当前状态 | 缺失 |
|------|---------|------|
| `docs/PLAN-rogue-pong.md` §2.5 | ✅ 9 升级清单（名称/稀有度/效果/情感断言草案/价值极）+ 2 条示例短句（"长臂: 够得着了" / "双生: 分身"） | ❌ 非正式草稿，未落地为资源 |
| Issue #387（升级池架构） | ✅ 定义 9 升级 id/名称/稀有度/效果回调 + `UpgradePool.get_candidates(3)`/`apply()` 接口 | ❌ 无文案字段（短句/命名候选/情绪断言） |
| Issue #388（3 选 1 升级 UI） | ✅ 三张霓虹卡片展示候选、选择后 reveal 稀有度 | ❌ 卡片短句与命名数据来源未定义 |
| `mini-pong/assets/` | ✅ 已有 neon_glow_material.tres / particle_material.tres / gradient_neon.tres（视觉资源） | ❌ 无 content 目录、无文案资源文件 |
| `mini-pong/gdscripts/` | ✅ 运行时逻辑（ball/paddle/constants…） | ❌ 无任何升级文案硬编码（好事——AC5 要求零硬编码） |
| `docs/NAMING.md`（#378 产出） | ✅ 游戏正式命名档案（B2 校准接口） | — 与升级池文案不同 scope（见 §6 去冲突） |
| `docs/TASTE.md` v1（#367 产出） | ✅ 手感定稿 + 风格方向（"删形容词、短句"） | — 本 Issue 只引用，不写入 |

### 预期行为（验收条件，源自 Issue #395）

1. **9 个升级各有 1 条中文短句（≤12 字）** —— 升级卡上的克制短句，一格一行
2. **每个升级至少 2 个命名候选，并标注推荐项** —— B2 命名协议：候选清单（2-3 选 1）+ 推荐
3. **每条含 #DRAFT 与情绪断言（如愤怒/好奇/克制）** —— 草稿标记 + 体验引擎情感断言
4. **文案不使用网络梗、emoji、感叹号** —— 海明威式克制红线
5. **所有文案放入独立 content 资源文件，不硬编码在逻辑节点** —— 数据与逻辑分离

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家 3 选 1 | 每波一次 | 三张霓虹卡各显一行短句 + 名称；短句在 1 秒内传达升级的"味道"（安全感/破坏欲/掌控感…），玩家凭情感而非数值决策（情感误归因） |
| B | 用户定稿（v4 队列） | 每次草稿 merge 后 | GitHub Assigned to me 攒批：打开 Issue → 对照候选表选名/改短句 → push 定稿 → close |
| C | implement agent 填草稿 | 本管线一次 | 按本 PRD §4.4 候选表 + §4.1 JSON schema 写入 `mini-pong/assets/content/upgrade_pool.json`（`draft:true` + 候选 + 推荐 + 情绪断言），机械零改动 |
| D | review agent 定稿就绪检查 | 每次实现 PR | 结构完整（9 升级 × 短句/候选/推荐/情绪断言齐全）+ taste 方向对齐（对照 §2 方向逐项比对）+ 机械部分无 DRAFT 残留 |
| E | #387/#388 消费方 | 实现后 | `UpgradePool.get_candidates(3)` 返回升级定义，UI 卡从 content 资源取短句与名称渲染 |

### 技术约束（继承自 Issue #395）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`；Rogue Pong 改造后 720×1280 竖屏，见 PLAN-rogue-pong §4.1） |
| 领域判定 | B2 命名/文案（T1✅ T2✅ T3✅）+ B5 失败表达 —— 人机共做领域；agent 给候选清单（2-3 选 1 + 推荐），人定稿 |
| 风格 | 雨夜竞技场（PLAN-rogue-pong §3 已确认：雨幕粒子 + 城市光晕 + 暗角 + 霓虹描边 UI，**克制优先**）+ 街机爽感（#367 TASTE.md v1：删形容词、短句） |
| 文案红线 | 中文短句 ≤12 字；无网络梗/emoji/感叹号；海明威式（名词+动词，无形容词堆砌） |
| 所有权 | taste-draft：PR 用 `parent #395`（小写 p）不写 Closes；草稿达标即 merge，不等人定稿，不进依赖链 |
| 产出边界 | 只新建 content 资源文件（+ 本 PRD）；**不修改任何运行时逻辑**（#387 未实现前无消费方，文案先行落地为纯数据） |
| 开源优先 | Issue 上下文要求先搜 Godot Asset Library / GitHub 社区再动手——**文案类任务无第三方资产可复用**（Godot 原生 `FileAccess` + `JSON.parse_string()` 加载即可，零依赖），调研结论见 §4.1 |

---

## 2. 设计意图

### 为什么现在做

这是 v4 人机共做队列的 **B2+B5 内容 Issue**。升级池是 Rogue Pong 每波成长的核心交互（3 选 1 卡片，PLAN-rogue-pong §2.5 确认），机械层（#387）与 UI 层（#388）都已排队，**文案是卡片的第一印象**——一行短句决定玩家"这波选哪个"的情绪。按 taste-ownership-domains.md，B2 命名协议 = 候选清单（2-3 选 1 + 推荐 + 语境说明）而非 agent 直接定稿；B5 失败表达 = 候补文本（2-3 选 1）。本 Issue 产出 = 「9 升级文案草稿 + 语境注释」落进独立 content 资源，草稿达标即 merge，assign 用户定稿，不阻塞下游机械 Issue。

### 审美坐标与 taste 方向（研究关键发现）

Issue 注入的审美坐标：**雨夜竞技场**（PLAN-rogue-pong §3 已确认 —— 动态雨量是情绪仪表盘：平静 0.3 → 胶着 0.7 → 爆发 0.9 脉冲 → 失败 1.0；暗底霓虹 #289：#0a0a12 背景 + 玩家蓝 #4a90d9 + AI 红 #ff3355 + 拖尾紫 #8833ff）+ **街机爽感**（#367 手感：利落击打、直接不绕弯、可控性优先）。

**Obsidian 知识库检索**（`/Volumes/Obsidian/Knowledge Ocean/wiki/`，本机已挂载）找到的可迁移设计语言：

| 笔记 | 可迁移到本 Issue 的设计语言 |
|------|---------------------------|
| `体验引擎-patterns.md` §情感误归因 | 玩家把情绪归因于最显眼的诱因 → **升级卡短句必须是最显眼的情绪诱因**：短句 1 秒注入该升级的情感（安全感/破坏欲/掌控感），把"我打得好"转移到"我选得好" |
| `体验引擎-glossary.md` | 情感源于**人类价值在两极端间变化**（安全/危险、破坏/受阻、秩序/混沌、支配/服从…）→ 短句应点出价值极的**移动方向**（"够得着了"= 向安全移动），而非描述数值 |
| `空洞骑士—沉默作为叙事策略.md` | 克制 = 叙事的负空间："说出的部分远少于未说出的" → **短句越短越有力**：4-6 字为佳，12 字是上限红线；留白本身就是雨夜氛围 |
| `赛博增殖：网球与绒毛.md` | 霓虹在暗底上"增殖/蔓延"意象（星尘轨迹伤害、双生分裂）可作命名/短句的意象词源 |
| `90年代地摊文艺.md`（#378 已引用） | 街机文化的粗粝、直接——**反例约束**：避免过度文艺化（长名/生僻词/为了文艺而文艺） |
| `docs/TASTE.md` v1（#367 定稿） | 风格方向："删形容词、短句" → 本次短句全部执行此方向 |

**taste 方向综合（本 PRD 的注入方向，即 content 资源初版的方向）**：

1. **克制短句**：每升级 1 行中文短句，4-6 字为主（≤12 字红线），名词+动词，无形容词堆砌、无感叹号——像雨夜墙上的霓虹灯牌，一句即止。
2. **点出价值极移动**：短句落在该升级的"价值极"上（§2.5 情感断言/价值极表），说"手感变化"不说"数值变化"——"够得着了"（安全）而非"挡板 +30%"。
3. **命名沿用工作名 + 候补**：机械工作名（长臂/燃烧弹/…）作为推荐候选（跨文档一致、可发现性），另给 1-2 个同味候选（意象同源、更雨夜/更霓虹），用户 2-3 选 1。
4. **雨夜意象渗透**：短句/候补命名优先取雨、夜、霓虹、墙、洞、影、星、火等竞技场意象词，但**不做作**——意象服务于克制，不堆砌修辞。

### 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 只新建 `mini-pong/assets/content/upgrade_pool.json`（+ 本 PRD）；**不碰 `mini-pong/gdscripts/` 任何运行时文件** |
| 引擎版本 | Godot 4.7.1，`config/features=PackedStringArray("4.7")` |
| 消费方 | #387 UpgradePool / #388 3 选 1 UI —— 本 PRD 只定义**文案数据契约**（JSON schema），机械接入由 #387/#388 负责 |
| 文案语言 | 中文（Issue 明示"中文短句"）；升级卡 UI 为中文语境（与游戏内既有英文 UI 不同 —— 新 UI 层 #388 按中文渲染） |
| 测试基线 | 当前 main 全绿；纯数据文件不触发任何测试差异（#387 未落地前无消费方读取） |
| E2E | `e2e_shots.json` 现有 shot 均不涉及升级卡文本 —— 无影响 |
| 品味档案 | docs/TASTE.md 不改（本次草稿不落 TASTE.md；用户定稿后由 review agent 把风格特征回写） |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/assets/content/upgrade_pool.json` | 升级池文案资源（B2+B5 校准接口 = 命名表 + 语境注释） | **新增**：9 升级 ×（短句 + 命名候选 2-3 + 推荐标记 + `draft` + 情绪断言 + 稀有度 + 语境注释） |

### 新增文件

| 文件 | 用途 |
|------|------|
| `mini-pong/assets/content/upgrade_pool.json` | 9 升级文案草稿单一资源：`schema: "upgrade-pool-content/v1"` + `draft: true` + 9 条升级条目（详见 §4.1 schema 与 §4.4 候选表）；用户定稿差异直接改此文件 |

### 间接影响

| 模块 | 影响 |
|------|------|
| `mini-pong/gdscripts/upgrade_pool.gd`（#387 待建） | **零改动**（本 Issue 不实现机械层）；未来由 #387 读取本 JSON |
| `mini-pong/gdscripts/*.gd` / `tests/*.gd` | **零改动** —— 文案与运行时逻辑无耦合（AC5 硬性要求） |
| `scenes/`（#388 升级卡 UI 待建） | **零改动**（本 Issue 不碰 UI）；未来由 #388 渲染本 JSON 字段 |
| `e2e_shots.json` / `run-e2e-review.sh` | **零改动** —— 无升级卡文本断言 |
| `docs/NAMING.md` / `docs/TASTE.md` | 不改（见 §6 去冲突；定稿差异由 review agent 回写 TASTE.md） |

### 数据流

```
docs/PLAN-rogue-pong.md §2.5（9 升级清单/情感断言/价值极）
    │
    ▼
mini-pong/assets/content/upgrade_pool.json（本 Issue：draft 草稿 + 候选 + 推荐 + 情绪断言）
    │  （review 定稿就绪检查 → merge → status/human-review + assign 用户）
    ▼
用户定稿（Assigned to me 队列）：改 JSON 短句/选命名 → push → close
    │
    ▼
#387 UpgradePool / #388 3选1 UI 读取 JSON → 卡片渲染（机械层，不在本 Issue）
    │
    ▼
定稿差异回写 docs/TASTE.md（风格特征：如"升级文案 4-6 字、点价值极、雨夜意象"）→ 下次草稿朝此方向
```

### 文档更新清单

- [x] `docs/PRD/395-upgrade-pool-copy-draft.md`（本文件）
- [ ] `mini-pong/assets/content/upgrade_pool.json`（implement 阶段按 §4.1 schema + §4.4 候选表落地）

---

## 4. 方案对比

### 4.1 内容资源载体

**Approach A：JSON 资源文件（推荐）**

新建 `mini-pong/assets/content/upgrade_pool.json`，Godot 原生加载：`FileAccess.get_file_as_string("res://assets/content/upgrade_pool.json")` + `JSON.parse_string()`（零第三方依赖，headless/CI 安全）。

```json
{
  "schema": "upgrade-pool-content/v1",
  "draft": true,
  "upgrades": [
    {
      "id": "long_arm",
      "name_working": "长臂",
      "rarity": "common",
      "short_phrase": "够得着了",
      "phrase_draft": true,
      "emotion": "安全感",
      "emotion_assertion": "价值极 安全/危险 → 向安全移动：\"够得着了\"",
      "naming_candidates": [
        { "name": "长臂", "recommended": true,  "note": "沿用 #387 工作名，跨文档一致" },
        { "name": "伸臂", "recommended": false, "note": "动作感更强" }
      ],
      "context": "升级卡短句位，≤12 字；稀有度由 #387 定义"
    }
  ]
}
```

- Pros：纯数据（AC5 字面满足）；JSON 人类可编辑（用户定稿直接改文件）；可被 python 脚本校验（项目已有 validate_hemingway.py 处理 JSON 的先例）；schema 版本化便于 #387/#388 接入
- Cons：JSON 无注释 —— `#DRAFT` 用 `"draft": true` 字段表达（机器可断言，等价于 #DRAFT 标注）
- Risk: Low ／ Effort: 0.5 天

**Approach B：Godot Resource（.tres + 自定义 class）**

定义 `UpgradeContent` 资源类 + `.tres` 实例。

- Pros：类型安全，Godot 原生 Inspector 可编辑
- Cons：**用户定稿成本高**（需 Godot 编辑器打开，无法像 JSON 一样在 GitHub Web UI 直接改）；需新增 class 脚本（跨入机械层，超出纯数据边界）；.uid 文件噪音
- Risk: Med ／ Effort: 1 天

**Approach C：GDScript 常量字典（content.gd）**

新建 `mini-pong/gdscripts/content_upgrade.gd` 暴露 `const UPGRADE_CONTENT = {...}`。

- Pros：Godot 直接引用，零加载代码
- Cons：**违反 AC5 精神**（文案硬编码在逻辑节点同目录的脚本文件里，不满足"独立 content 资源"）；用户定稿需改 GDScript（语法敏感）
- Risk: High ／ Effort: 0.5 天

### 4.2 文案风格策略

**Approach A：雨夜克制短句（推荐）**

4-6 字为主（≤12 字红线），名词+动词，点价值极移动，雨/夜/墙/影意象渗透但不堆砌（§2 taste 方向 1/2/4）。

- Pros：贴合雨夜竞技场审美坐标（克制优先）；海明威式可机械校验（validate_hemingway 域规则可复用）；"短句即留白"（空洞骑士负空间策略）
- Cons：对 implement 的 taste 要求高（短 ≠ 好写）
- Risk: Low ／ Effort: 0.5 天

**Approach B：霓虹张扬短句**

带电、赛博、多修饰（"霓虹撕裂暗夜"式）。

- Pros：视觉冲击强
- Cons：**违反克制优先**（PLAN §3.3 明示）；形容词堆砌违反 TASTE.md 方向；与 12 字红线冲突风险
- Risk: Med ／ Effort: 0.5 天

**Approach C：中性功能描述**

"挡板范围 +30%"式。

- Pros：信息最准，零 taste 风险
- Cons：**违背情感误归因设计**（PLAN §2.5 明确要"把打得好归因到选得好"，纯数值短句无法触发）；浪费 3 选 1 的情绪决策位
- Risk: Med ／ Effort: 0.5 天

### 4.3 命名候选协议

**Approach A：工作名 + 1-2 同味候补（推荐）**

每升级 3 个命名候选 = 机械工作名（推荐，跨文档一致）+ 2 个同味意象候选；推荐项标注 `recommended: true`。

- Pros：满足 AC2（≥2 候选 + 推荐项）；工作名兜底保证 #387/#388 机械引用不漂移；用户有对照物（B2 协议）
- Cons：工作名可能不够"雨夜"——靠候补补齐意象
- Risk: Low ／ Effort: 0.5 天

**Approach B：全候补无工作名**

命名与 #387 工作名完全解耦，全新建名。

- Pros：意象自由度高
- Cons：**机械引用漂移风险**（#387 的 id/名称与 UI 显示名不一致）；用户需同时对齐两处
- Risk: Med ／ Effort: 0.5 天

**Approach C：仅 1 个候选**

每升级只给 1 个名字。

- Pros：最快
- Cons：**违反 AC2**（≥2 候选）；用户无选择空间，违背 B2 候选清单协议
- Risk: High ／ Effort: 0 天

### 4.4 候选文案集合（核心交付：9 升级 × 短句 + 命名候选）

> 依据：Issue 审美坐标（雨夜竞技场 + 克制）+ Obsidian 设计语言（§2）+ PLAN-rogue-pong §2.5 情感断言/价值极 + TASTE.md 风格方向（删形容词、短句）。**这些是 research 建议草稿，implement 原样填入 upgrade_pool.json，用户做最终裁决（每项 2-3 选 1）。**

| # | 升级 (id) | 稀有度 | 效果（#387） | 短句草稿（≤12字） | 命名候选（推荐加粗） | 情绪断言（体验引擎） |
|---|-----------|:---:|------|---------|---------|---------|
| 1 | 长臂 (long_arm) | 普通 | 挡板 +30% | **够得着了**（4字） | **长臂** ／ 伸臂 ／ 延展 | 安全感 —— 价值极 安全/危险 向安全移动："够得着了" |
| 2 | 燃烧弹 (fireball) | 普通 | 球速 +10%，破砖烧碎相邻 2 块 | **火过留洞**（4字） | **燃烧弹** ／ 火流星 ／ 余烬弹 | 破坏欲 —— 价值极 破坏/受阻 向破坏移动："火过留洞" |
| 3 | 破城锤 (battering_ram) | 普通 | 破砖冲击波，碎邻近砖 | **一锤碎一片**（5字） | **破城锤** ／ 震击 ／ 夯 | 暴力释放 —— 一击碎一片的畅快 |
| 4 | 磁心 (magnet_core) | 稀有 | 挡板磁力吸球 | **球听你的**（4字） | **磁心** ／ 引力核心 ／ 磁握 | 掌控感 —— 价值极 技能/无能 向技能移动："球听你的" |
| 5 | 双生 (twin) | 稀有 | 球分裂为 2 | **一球变两球**（5字） | **双生** ／ 分裂 ／ 双子 | 兴奋 —— 价值极 秩序/混沌：场面失控但归你 |
| 6 | 缓时 (slow_time) | 稀有 | 球速冻结 2s | **时间让路**（4字） | **缓时** ／ 凝时 ／ 冻结 | 时间主宰 —— 价值极 快/慢：世界等你 |
| 7 | 预开洞 (pre_hole) | 稀有 | 开局自动在墙上开一洞 | **洞先开好**（4字） | **预开洞** ／ 先行 ／ 破晓 | 先手优势 —— 价值极 主动/被动：棋高一着 |
| 8 | 星尘 (stardust) | 传说 | 穿墙后留 2s 轨迹伤害 | **所过之处留痕**（6字） | **星尘** ／ 星轨 ／ 余辉 | 支配感 —— 价值极 支配/服从：全场都是你的痕迹 |
| 9 | 幻影 (phantom) | 传说 | 挡板残影多段判定 | **快得看不清**（5字） | **幻影** ／ 残像 ／ 影先行 | 敏捷快感 —— 价值极 敏捷/笨拙：快得看不清 |

### 推荐与理由

**4.1 选 A（JSON）+ 4.2 选 A（雨夜克制短句）+ 4.3 选 A（工作名 + 候补）**：

1. **AC5 字面满足**：只有 4.1-A 是"独立 content 资源文件"且零运行时改动——B 需新增资源类脚本（跨机械层），C 硬编码在脚本（违反 AC5 精神）；
2. **用户定稿零门槛**（v4 队列核心）：JSON 可直接在 GitHub Web UI 编辑（用户定稿 = 改 JSON 字段 + close），B 需要 Godot 编辑器；
3. **情感误归因落地**：4.2-A 的短句点价值极移动方向（"够得着了"= 向安全移动），恰好执行 PLAN §2.5 的"把打得好归因到选得好"；C 的纯数值短句做不到；
4. **机械一致性**：4.3-A 以工作名为推荐候选兜底，保证 #387 的 id/名称与 UI 显示名不漂移，候补负责雨夜意象；
5. **可校验**：短句长度（≤12 字）、无感叹号/emoji、候选数（≥2）、推荐标记齐全——全部可写成脚本断言（review agent 定稿就绪检查用）。

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 5 条 AC）

- [x] **AC1: 9 个升级各有 1 条中文短句（≤12 字）** — §4.4 候选表 9 条全齐，implement 填入 JSON `short_phrase` 字段
  - 验证：`python3 -c "import json; d=json.load(open('mini-pong/assets/content/upgrade_pool.json')); assert len(d['upgrades'])==9; assert all(len(u['short_phrase'])<=12 for u in d['upgrades'])"`
- [x] **AC2: 每个升级至少 2 个命名候选，并标注推荐项** — `naming_candidates` ≥2 且恰 1 个 `recommended: true`
  - 验证：同上脚本断言 `len(u['naming_candidates'])>=2` 且 `sum(c['recommended'] for c in u['naming_candidates'])==1`
- [x] **AC3: 每条含 #DRAFT 与情绪断言** — 顶层 `draft: true` + 每升级 `phrase_draft: true`（等价 #DRAFT 标注）；`emotion`/`emotion_assertion` 字段全齐
  - 验证：`d['draft'] is True` 且 9 条均有 `emotion_assertion`
- [x] **AC4: 文案不使用网络梗、emoji、感叹号** — §4.4 草稿已合规（无梗/无 emoji/无 `！`）
  - 验证：`grep -E '[！!]|[😀-🙏]' mini-pong/assets/content/upgrade_pool.json` 为空（扩展校验可加 validate_hemingway 风格检查）
- [x] **AC5: 所有文案放入独立 content 资源文件** — 唯一文案载体 `mini-pong/assets/content/upgrade_pool.json`
  - 验证：`git diff main...HEAD --stat` 仅含 `docs/PRD/395-*.md` 与 `mini-pong/assets/content/upgrade_pool.json`；`grep -rn "够得着了\|火过留洞" mini-pong/gdscripts/` 为空

### 边界条件

1. **机械零改动**：本 Issue 只落 JSON 数据；#387/#388 未实现前不得在 gdscripts/ 写任何读取代码（消费方接入属 #387/#388 scope）。
2. **id 契约**：JSON 的 `id` 必须与 #387 升级定义一致（long_arm/fireball/battering_ram/magnet_core/twin/slow_time/pre_hole/stardust/phantom 及 3 个稀有度 `common/rare/legendary`）——机械层直接按 id 匹配文案。
3. **短句长度红线**：≤12 字（中文按字符计）；超长即视为违反 AC1 与情感断言（克制优先）。
4. **语言边界**：短句与命名候选为中文（Issue 明示）；游戏内既有英文 UI（YOU WIN! 等）不在本 Issue 范围，不得顺手中文化。
5. **draft 语义**：`draft: true` 是草稿标记；用户定稿时将其改为 `false` 或删除并 close —— review agent 用该字段区分草稿/定稿。
6. **无梗无感叹号**：网络梗（梗会过期）、emoji（渲染不一致）、感叹号（破坏克制）三类词全禁——候补命名同样适用。
7. **命名不漂移**：推荐候选 = #387 工作名（跨文档一致）；若用户选了候补名，定稿时同步告知 #387 机械层更新显示名（避免 UI 名与文档名分叉）。

### 失败路径

1. **implement 误改运行时**（在 gdscripts/ 写读取代码或把文案硬编码进 #387/#388 逻辑）→ 违反 AC5/边界 1。缓解：PRD §3/§5 明示，review agent 用 AC5 的 diff 检查卡口。
2. **候选缺要素**（缺短句/缺候选数/缺推荐标记/缺情绪断言）→ 违反 AC1-AC3，用户无法对照定稿。缓解：review agent 按 AC1-AC3 逐条脚本断言。
3. **短句超长/形容词堆砌/带感叹号** → 违反 AC1/AC4 与克制方向。缓解：review agent 对照边界 3/6 校验 + validate_hemingway 域规则。
4. **id 与 #387 不一致** → 机械层匹配失败，卡片显示空文案。缓解：implement 对照 #387 功能描述核对 id 清单（§5 边界 2 明示）。
5. **把游戏名/波次文案混入本资源** → scope 越界（与 #378/#396 冲突）。缓解：§6 去冲突表明示边界，review agent 检查 JSON 只含 9 升级条目。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| PLAN-rogue-pong.md §2.5（9 升级清单/情感断言/价值极，2026-08-13 用户确认） | ✅ 已确认 | 无 |
| #289 霓虹赛博视觉（审美坐标：#0a0a12 + 蓝/红/紫霓虹） | ✅ CLOSED | 无 |
| #367 手感校准草稿（TASTE.md v1：删形容词、短句） | ✅ 定稿 | 无 |
| #378 命名定稿（NAMING.md：PONG://NEON，命名风格先例） | ✅ 定稿 | 无 |
| #387 升级池架构（机械层，id/稀有度契约来源） | ⏳ OPEN | 中 —— 本 PRD 只按 #387 功能描述定义 id 契约；若 #387 实现时改 id，需同步本 JSON |
| #388 3 选 1 升级 UI（消费方） | ⏳ OPEN | 低 —— 消费方接入在 #388 scope，本 Issue 不阻塞 |

```
#289 霓虹赛博 ──────────┐
#367 手感（TASTE.md v1）──┼──► #395（本 Issue，升级池文案草稿）
#378 命名（NAMING.md）───┘        │
                                  ▼
              mini-pong/assets/content/upgrade_pool.json ──► #388 3选1 UI 卡片渲染
                                  │（#387 UpgradePool 按 id 匹配文案）
                                  ▼
                    用户定稿（Assigned to me 队列）→ close 定稿
```

**Scope 去冲突表**（Patch 14：重叠检测结果）：

| 现有 PRD/文档 | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #378 PRD + docs/NAMING.md | 游戏正式命名（B2，标题/副标题候选） | ❌ 不重做游戏名——只沿用其命名风格（短、直接、霓虹词缀） |
| #396（同簇 B5，未开工） | 波次副句与失败短句 | ❌ 不含波次/失败文案——边界：本资源只装 9 升级条目，波次/失败文案归 #396 独立资源 |
| #367 PRD + docs/TASTE.md v1 | A1 手感参数定稿 | ❌ 不碰手感值——只引用其风格方向（删形容词、短句） |
| #387（机械） | 升级池架构（id/权重/接口） | ❌ 不设计机械结构——只定义文案数据契约（JSON schema + id 对齐） |

**无阻塞。** v4 语义：本 Issue 是 human Issue（taste-draft，B2+B5），**不进依赖链** —— 草稿 merge 即满足下游依赖，下游机械 Issue（#387/#388）不等用户定稿。

---

## 7. Spike / 实验

Skipped per depth/light（Issue 无 depth 标签，RAW JSON 标注 light；Section 7 仅 `depth/deep` 必填）。文案任务不需要实验——候选清单本身就是交付物（B2/B5 协议：agent 给候选，人做最终裁决）；文案对运行时零影响，无可验证的机械行为。

---

## 8. 延续上下文（Continuation Context）

**给 plan agent 的手递**（plan agent 产出 DESIGN 时直接采用，无需重扫源码）：

**系统状态**：升级池文案完全空白——9 升级仅有机械工作名（#387 功能描述 + PLAN-rogue-pong §2.5 确认稿）；`mini-pong/assets/content/` 目录不存在（需新建）；`mini-pong/assets/` 已有 3 个视觉 .tres（neon_glow_material / particle_material / gradient_neon）；消费方 #387（UpgradePool）与 #388（3 选 1 UI）均为 OPEN，本 Issue 文案先行落地为纯数据。审美坐标：雨夜竞技场（PLAN-rogue-pong §3：雨幕粒子/城市光晕/暗角/霓虹描边 UI，克制优先）+ 霓虹赛博（#289）+ 街机爽感（#367 TASTE.md v1：删形容词、短句）。

**主风险**：
1. implement 误改运行时文件或在 gdscripts/ 写消费代码 → 违反 AC5/边界 1（§5 失败路径 1）
2. 候选缺要素（短句/候选数/推荐/情绪断言）→ 用户无法对照定稿（§5 失败路径 2）
3. id 与 #387 机械定义不一致 → 卡片显示空文案（§5 失败路径 4）
4. 定稿流程混淆：本 Issue 是文案草稿，**不 close** —— 草稿 merge 后由 workflow-chain 打 `status/human-review` + assign 用户，用户改 JSON + close 即定稿

**下一步（plan → implement）**：
1. DESIGN 引用本 PRD §4.1 JSON schema（`upgrade-pool-content/v1`：id/name_working/rarity/short_phrase/phrase_draft/emotion/emotion_assertion/naming_candidates/context）+ §4.4 候选表（9 升级 × 短句 + 3 命名候选 + 推荐 + 情绪断言）
2. implement 只新建 `mini-pong/assets/content/upgrade_pool.json`：9 条目 ×（短句 + 候选 + `draft:true` + 情绪断言 + 语境注释）；**机械部分零改动**
3. review agent：定稿就绪检查（JSON schema 合法 + 9 条全要素 + taste 方向对齐 + 机械无 DRAFT 残留 + diff 仅数据文件）→ merge（PR 用 `parent #395`）→ `status/human-review` + assign 用户（workflow-chain.yml 自动）
4. 用户定稿：改 JSON 短句/选命名（或微调）→ push → close；差异回写 docs/TASTE.md 风格特征节（如"升级文案 4-6 字、点价值极、雨夜意象"）——下次同类文案草稿的方向来源

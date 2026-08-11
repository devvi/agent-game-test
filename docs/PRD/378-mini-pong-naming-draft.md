# PRD: [Content] Mini Pong 正式命名草稿 — 标题/副标题候选 (B2)

> **Issue:** #378
> **标签:** enhancement, content, version/mvp, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-11
> **深度:** depth/standard（Issue 无 depth 标签，按 #358 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 跳过）
> **所有权:** `content_ownership: taste-draft`（人机共做 v4 — B2 命名/文案领域；agent 给候选清单（5 选 1 + 语境说明）而非直接定名；草稿达标即 merge，PR 用 `parent #378` 不写 Closes；review agent 打 `status/human-review` + assign 用户定稿）
> **taste 方向来源:** Issue 审美坐标（#289 落地）+ Obsidian 知识库检索 + 项目品味档案（docs/TASTE.md 初版，来自 #367）

---

## 1. 问题定义

### 当前状态

Mini Pong 目前只有**开发代号** "Mini Pong"（`project.godot config/name`、标题画面 TitleLabel、GDD、docs 全仓一致使用），**没有任何正式游戏名、没有副标题候选、没有命名文档**。game-to-issues 分解 JSON 的 meta 曾用过非正式中文名「Mini Pong — 霓虹赛博乒乓球」，但从未落地为正式命名。命名是玩家第一秒看到的"味道"（taste-ownership-domains.md B2：成本最低、收益最高的人机接口），当前处于完全空白状态。

| 系统 | 当前状态 | 缺失 |
|------|---------|------|
| `mini-pong/project.godot` | ✅ `config/name="Mini Pong"`、`config/description="A classic Pong game implementation"` | ❌ 无正式名（开发代号即全仓唯一名） |
| `mini-pong/scenes/ui_start_menu.tscn` | ✅ TitleLabel `text = "Mini Pong"`（64px，霓虹脉冲动画） | ❌ 无正式名/副标题位 |
| `mini-pong/gdscripts/constants.gd` | ✅ `GAME_VERSION = "v1.0.0"`（#358 引入，标题画面左下角显示） | — |
| `mini-pong/gdscripts/game_over_screen.gd` | ✅ `TEXT_PLAYER_WIN="YOU WIN!"` / `TEXT_AI_WIN="AI WINS!"`（全英文 UI 语境） | — |
| `docs/GAME_DESIGN/`（INDEX + 12 篇 GDD） | ✅ 全仓文档统一用 "Mini Pong" | ❌ 无命名决策记录 |
| `docs/RAW/game-to-issues-mini-pong.json` | ✅ meta title 曾用「Mini Pong — 霓虹赛博乒乓球」（非正式） | ❌ 未落地 |
| `docs/NAMING.md` | ❌ 不存在 | **需新建**（Issue 验收条件指定的单一文件） |
| 候选名/副标题候选 | ❌ 不存在 | 需 3-5 候选 + 1 推荐 + 每候选 2-3 候补副标题 |

### 预期行为（验收条件，源自 Issue #378）

1. **候选名集中在 `docs/NAMING.md` 单一文件**，agent 填值带 `# DRAFT` 注释 + "为什么这个名字" + 2-3 个候补（副标题候选）
2. **每个候选名附情感断言**（体验引擎：它试图触发什么情感——如"利落/直接/爽快"）
3. **机械部分（架构/管线/测试）无 `# DRAFT` 残留**
4. **不修改任何游戏运行时行为**（纯文档草稿）

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家第一眼 | 每次曝光（商店页/启动画面） | 名字让玩家第一眼感到"这是个爽快的街机游戏"，而非"这是个怀旧克隆" |
| B | 用户定稿（v4 队列） | 每次草稿 merge 后 | GitHub Assigned to me 攒批处理：打开 Issue → 对照候选表选名/微调 → push 定稿 → close |
| C | implement agent 填草稿 | 本管线一次 | 按本 PRD §4.2 候选表写入 docs/NAMING.md（`# DRAFT` + 为什么 + 候补 + 情感断言），机械零改动 |
| D | review agent 定稿就绪检查 | 每次实现 PR | 结构完整（候选表齐全）+ taste 方向对齐（对照审美坐标逐项比对）；机械部分无 `# DRAFT` 残留 |
| E | CI/测试 | 每次提交 | 纯文档改动 → `run_tests.gd` 全绿不受影响（不触发任何运行时差异） |

### 技术约束（继承自 Issue #378）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，1280×720 固定窗口） |
| 领域判定 | B2 命名/文案：T1 主观性 ✅（两个专家对"哪个名字好"答案不同）/ T2 不可断言 ✅（无法 `assert title == "..."` 验证"好"）/ T3 语境 ✅（同样的名字换到别的游戏不成立）→ 人机共做领域 |
| 审美坐标 | 霓虹赛博（#289 落地：暗底 #0a0a12 + 高饱和 #4a90d9 玩家蓝 / #ff3355 AI 红 / #8833ff 拖尾紫 + glow bloom）+ 街机爽感（利落/直接不绕弯，#367 手感草稿已注入：330 px/s 开局、+7%/拍加压、可控性优先） |
| 情感断言 | 名字应让玩家第一眼感到"这是个爽快的街机游戏"，而非"这是个怀旧克隆" |
| 所有权 | taste-draft：PR 用 `parent #378`（小写 p）不写 Closes；草稿达标即 merge，不等人定稿 |
| 产出边界 | 纯文档草稿：只建 docs/NAMING.md，**不修改任何运行时行为**（project.godot / TitleLabel / 测试 / E2E 均不动） |

---

## 2. 设计意图

### 为什么现在做

这是 v4 人机共做队列的 **B2 命名** 内容 Issue。命名是"玩家第一秒看到的你的味道"——taste-ownership-domains.md 明确标注 B2 为 P1 优先（零成本，候选清单机制，收益最大），且**命名协议 = 候选清单（5 选 1 + 语境说明）而非 agent 直接定名**。管线语义：agent 生成带 taste 方向的命名草稿 → **草稿达标即 merge**（结构可用）→ assign 用户定稿（显式队列，不阻塞下游机械 Issue）。本 Issue 的产出物是"命名草稿 + 语境注释"，不是最终定名。

### 审美坐标与 taste 方向（研究关键发现）

Issue 注入的审美坐标：**霓虹赛博视觉**（#289 落地：#0a0a12 暗底、蓝/红/紫高饱和霓虹、glow/bloom 0.6–0.8、球拖尾粒子）+ **街机爽感**（利落击打、直接不绕弯——#367 手感草稿：开局 330 px/s、每拍 +7% 加压、可控性优先）。**命名方向**：名字要像一记利落的击打——短、直接、带电；同时用"霓虹/赛博"语汇与"Pong"的怀旧认知做对冲，让"爽快的街机游戏"压过"怀旧克隆"的第一印象。

Obsidian 知识库检索（`/Volumes/Obsidian/Knowledge Ocean/wiki/`，本机已挂载）找到的可迁移设计语言：

| 笔记 | 可迁移到本 Issue 的设计语言 |
|------|---------------------------|
| `体验引擎-patterns.md` §6 标签化（Labeling） | 命名 = 情感标签：给"单位起名、赋予性格特质、创建叙事上下文"（Medieval: Total War 用性格特质替代统计数字）→ **游戏名是游戏的第一情感标签**：候选名必须能在 1 秒内注入"爽快/带电/霓虹"的情感，而非"经典复刻" |
| `体验引擎-glossary.md` | **Challenge（挑战）** = 对玩家技能的考验，产生**紧张感和精通的潜力** → 副标题中的"对决（Duel）/对拍（Rally）"词汇触发竞技张力（玩家 vs AI，5 分定胜负） |
| `赛博增殖：网球与绒毛.md` | 网球游戏 + AI 自主增殖的隐喻——霓虹在暗底上"增殖/蔓延"的意象可作副标题词源灵感（如"霓虹增殖"）；风险：过于隐晦，仅作方向参考 |
| `90年代地摊文艺.md` | 街机文化的粗粝、直接、混杂——"利落/直接"的文化锚点；**反例约束**：命名避免过度文艺化（不要"为了文艺而文艺"的长名/生僻词） |
| `CUSGA 2026 游戏评选笔记.md` | 评审级体验要素（#367 已引用）——命名是商店页/启动画面的第一评审印象，值得人机共做 |

**taste 方向综合（本 PRD 的注入方向，即 docs/NAMING.md 初版的方向）**：

1. **利落直接**：候选名 ≤ 3 个词、单音节/双音节优先、无生僻词——像一记击打，不像一段散文。
2. **霓虹赛博对冲怀旧**：保留 "Pong" 玩法认知没问题，但必须用霓虹/赛博语汇（NEON / CYBER / VOLT / DUEL / ://）把它从"怀旧克隆"拉进"赛博街机"语境。
3. **副标题承载原创性**：主标题负责"秒懂玩法"，副标题负责"不是克隆"——每个候选配 2-3 个副标题候补（中英双语）。
4. **竞技张力**：副标题词汇向"对决/对拍/回合（Duel/Rally）"倾斜——玩家 vs AI、5 分定胜负、每一拍都更紧迫（#367 手感）。

### 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 只新建 `docs/NAMING.md`（+ 本 PRD）；**不碰 `mini-pong/` 任何运行时文件** |
| 引擎版本 | Godot 4.7.1，`config/features=PackedStringArray("4.7")` |
| 开发代号 | "Mini Pong" 保留为机械标识符（project.godot config/name / GDD / docs）——**不标 DRAFT、不改**；正式名定稿后由用户在实施阶段替换 |
| UI 语境 | 全英文 UI（YOU WIN! / AI WINS! / SPACE），1280×720 街机屏显 → 主推英文名，中文名作副标题候补 |
| 测试基线 | #346 修复后全绿；纯文档改动不触发任何测试差异 |
| E2E | `e2e_shots.json` 01_title 仅断言 VersionLabel 含 `v1.0.0`——不涉及标题文本，无影响 |
| 品味档案 | docs/TASTE.md 初版（#367）——命名定稿差异后续回写其"风格特征"节 |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `docs/NAMING.md` | 命名档案（B2 校准接口 = 命名表 + 语境注释） | **新增**：候选名表（名称 × 副标题候补 × 为什么 × 情感断言 × 语境注释）+ 定稿占位，全部带 `# DRAFT` |

### 新增文件

| 文件 | 用途 |
|------|------|
| `docs/NAMING.md` | 正式命名草稿单一文件：3-5 候选名 × 每候选 2-3 副标题候补 × 为什么 × 情感断言（v4 B2 的"命名表 + 语境注释"校准接口；用户定稿差异后续回写） |

### 间接影响

| 模块 | 影响 |
|------|------|
| `mini-pong/project.godot` | **零改动** —— `config/name="Mini Pong"` 是机械标识符，正式名定稿后由用户替换 |
| `mini-pong/scenes/ui_start_menu.tscn` / `start_menu.gd` | **零改动** —— TitleLabel 文本不动（用户定稿阶段处理） |
| `mini-pong/gdscripts/*.gd` / `tests/*.gd` | **零改动** —— 命名与运行时逻辑无耦合 |
| `e2e_shots.json` / `run-e2e-review.sh` | **零改动** —— 01_title 断言 VersionLabel，与标题文本正交 |
| `docs/TASTE.md` | 不改（本次草稿不落 TASTE.md；用户定稿后由 review agent 把命名风格特征回写） |
| GDD | 不改（GDD 记录机制，不记录命名过程值） |

### 数据流

```
候选名集合（§4.2：5 候选 × 2-3 副标题候补 × 为什么 × 情感断言）
    │
    ▼
docs/NAMING.md（# DRAFT 草稿表 + 语境注释 + 定稿占位）← B2 校准接口
    │  （review 定稿就绪检查 → merge → status/human-review + assign 用户）
    ▼
用户定稿（Assigned to me 队列）：选名 → 替换 project.godot config/name + TitleLabel → close
    │
    ▼
定稿差异回写 docs/TASTE.md（命名风格特征：如"短、直接、霓虹词缀"）→ 下次草稿朝此方向
```

---

## 4. 方案对比

### 4.1 命名方向策略

**Approach A：霓虹词缀 + Pong 认知（推荐）**

主标题保留 "PONG"（玩法秒懂），用霓虹/赛博词缀（NEON / CYBER / :// / DUEL）把它拽进赛博街机语境，副标题承载原创性。

- Pros：第一眼"秒懂玩法"（街机爽感 = 直接不绕弯）；"不是克隆"由视觉词缀 + 副标题完成；可发现性最好（商店搜索 "pong" 可命中）
- Cons：主标题仍含 "Pong"，怀旧克隆风险需副标题对冲
- Risk: Low ／ Effort: 0.5 天

**Approach B：纯原创造词（不出现 Pong）**

如 VOLT RALLY——完全摆脱克隆感，但玩法传达依赖副标题。

- Pros：原创性最强，"不是怀旧克隆"天然成立
- Cons：**违背"直接不绕弯"**——不玩 Pong 的玩家第一眼猜不出玩法；商店可发现性差
- Risk: Med ／ Effort: 0.5 天

**Approach C：中文名/双语并列**

如「霓虹乒乓球」——中文语境亲切，但与全英文 UI（YOU WIN! / AI WINS! / SPACE）和 1280×720 街机屏显语境冲突。

- Pros：中文市场亲和力
- Cons：与游戏内全英文 UI 语境不一致；双名并列稀释记忆点
- Risk: Med ／ Effort: 0.5 天

### 4.2 候选名集合（核心交付：5 候选 × 副标题 2-3 候补）

> 依据：Issue 审美坐标（霓虹赛博 + 街机爽感）+ Obsidian 设计语言（§2）+ 反例约束（避免"怀旧克隆"、避免过度文艺）。**这些是 research 建议，implement 原样填入 docs/NAMING.md，用户做最终裁决（5 选 1）。**

| # | 候选名 | 为什么这个名字 | 副标题候补（2-3 个） | 情感断言（体验引擎） |
|---|--------|--------------|-------------------|-------------------|
| 1 | **PONG://NEON** ⭐推荐 | 一记利落的赛博击打：`PONG` = 玩法秒懂；`://` = 协议符号，1 秒把游戏拉进"霓虹赛博"语境；`NEON` = #289 视觉语汇直译。三个元素 9 个字符内全部命中"爽快街机 + 不是克隆" | ① PONG://NEON — 霓虹协议<br>② PONG://NEON — 高速对拍<br>③ PONG://NEON — VOLT DUEL | 带电的邀请——"这是一个协议，你被邀请进入"；利落、直接、赛博 |
| 2 | **NEON PONG** | 最直白的霓虹对冲：玩法认知 + 视觉语汇并列，读起来就是"霓虹赛博乒乓球"的英文版（与 game-to-issues meta 非正式名一致）；零理解成本 | ① NEON PONG — CYBER RALLY<br>② NEON PONG — 霓虹回响<br>③ NEON PONG — 暗夜对拍 | 熟悉的爽快——"你认识的 Pong，但带电了"；克隆感由副标题对冲 |
| 3 | **VOLT RALLY** | 纯原创：`VOLT`（伏特/电压）= 霓虹电光 + 高速；`RALLY`（对拍）= 乒乓球回合术语 + 街机竞技。完全摆脱"Pong 克隆"标签 | ① VOLT RALLY — NEON PONG<br>② VOLT RALLY — 高压对打<br>③ VOLT RALLY — 霓虹回合 | 高压带电——"每一拍都带电"；原创、利落、竞技张力 |
| 4 | **NEON DUEL** | `DUEL` = 1v1 对决（玩家 vs AI、5 分定胜负的格斗式命名）；双词双音节，街机投币口气质 | ① NEON DUEL — PONG<br>② NEON DUEL — 霓虹对决<br>③ NEON DUEL — 一球定音 | 对决的紧张感——"你和机器，五球定输赢"；Challenge 张力（体验引擎-glossary） |
| 5 | **CYBER PONG** | 最保守稳妥：赛博 + Pong 字面组合，与审美坐标词汇（赛博/霓虹）一字不差；中文语境"赛博乒乓球"自然对应 | ① CYBER PONG — 霓虹之夜<br>② CYBER PONG — 赛博对拍<br>③ CYBER PONG — 暗夜霓虹 | 熟悉世界的陌生化——"赛博世界的乒乓球"；传达最准、原创性最低 |

### 4.3 命名表载体（docs/NAMING.md 结构）

**Approach A：docs/NAMING.md 单一文件（推荐）**

新建 `docs/NAMING.md`：候选名表（名称 × 副标题候补 × 为什么 × 情感断言 × 语境注释）+ `# DRAFT` 标记 + 定稿占位（用户定稿差异回写处）。

- Pros：AC1 字面要求（"候选名集中在 docs/NAMING.md 单一文件"）；B2 校准接口（命名表 + 语境注释）一次落地；用户定稿的对照物与反馈记录点同文件
- Cons：无（命名文档天然单文件）
- Risk: Low ／ Effort: 0.5 天

**Approach B：候选名写进 TASTE.md**

并入品味档案。

- Pros：少一个文件
- Cons：**违反 AC1**（验收条件点名 docs/NAMING.md 单一文件）；命名表与手感表职责混淆
- Risk: Med ／ Effort: 0.5 天

**Approach C：只给候选不给语境**

候选名列表 + 一句话推荐，无"为什么"、无候补、无情感断言。

- Pros：最快
- Cons：**违反 AC1/AC2**（缺"为什么这个名字"与 2-3 候补、缺情感断言）；用户无对照物，定稿靠感觉
- Risk: High ／ Effort: 0 天

### 推荐与理由

**4.1 选 A（霓虹词缀 + Pong 认知）+ 4.2 候选 1「PONG://NEON」为主推荐 + 4.3 选 A（docs/NAMING.md 单一文件）**：

1. **情感断言对齐**：Issue 断言"第一眼感到'爽快的街机游戏'而非'怀旧克隆'"——`PONG://NEON` 的 `://` 协议符号是 1 秒内的赛博语境切换器，比纯文字词缀（NEON/CYBER）更利落、更不绕弯（街机爽感关键词）；
2. **AC1 字面要求**命名表集中在 docs/NAMING.md —— 只有 4.3-A 满足；
3. **B2 协议**（taste-ownership-domains.md）：agent 给候选清单（5 选 1 + 语境说明）而非直接定名 —— §4.2 恰好是 5 候选 × 副标题候补 × 语境注释的完整清单；
4. **可发现性与原创性平衡**：主标题保留 "PONG" 命中商店搜索，副标题（霓虹协议/高速对拍/VOLT DUEL）完成原创性对冲——比纯原创（VOLT RALLY）风险低，比纯保守（CYBER PONG）更有记忆点；
5. **候选 2「NEON PONG」为稳妥备选**：与 game-to-issues 既有非正式名一致，若用户偏好"最直白"，零迁移成本。

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 4 条 AC）

- [x] **AC1: 候选名集中在 docs/NAMING.md 单一文件** — 5 个候选名（§4.2），每个带 `# DRAFT` 注释 + "为什么这个名字" + 2-3 个副标题候补
  - 验证：`docs/NAMING.md` 存在；`grep -c "# DRAFT" docs/NAMING.md` ≥ 5；抽查 3 条"为什么 + 候补"齐全
- [x] **AC2: 每个候选名附情感断言** — 每条含"情感断言"字段（体验引擎词汇：利落/直接/爽快/带电/紧张）
  - 验证：`grep -c "情感断言" docs/NAMING.md` ≥ 5
- [x] **AC3: 机械部分无 `# DRAFT` 残留** — 除 docs/NAMING.md（文档层）外，无任何 `# DRAFT`
  - 验证：`grep -rn "# DRAFT" mini-pong/` 为空
- [x] **AC4: 不修改任何游戏运行时行为** — 纯文档草稿
  - 验证：`git diff main...HEAD --stat` 仅含 docs/PRD/ 与 docs/NAMING.md；`project.godot` / `ui_start_menu.tscn` / `*.gd` / `tests/` / `e2e_shots.json` 零改动

### 边界条件

1. **开发代号保留**：`project.godot config/name="Mini Pong"` 是机械标识符，本次**不标 DRAFT、不改**；正式名定稿后由用户在实施阶段替换（改名属运行时变更，超出本 Issue 纯文档边界）。
2. **命名不改运行时**：TitleLabel / game_over 文案 / HUD 文本均不动——用户定稿阶段统一处理，避免草稿阶段引入半成品 UI 文本。
3. **候选名可读性红线**：≤ 3 词、无生僻词、无超过 12 字符的主标题（1280×720 屏显 + 街机利落感）；任何候选超出即视为违反情感断言。
4. **中英双语语境**：UI 全英文（YOU WIN! / AI WINS! / SPACE）→ 主标题英文为主，中文作副标题候补；避免中英双主名并列稀释记忆点。
5. **"不是克隆"对冲责任**：主标题含 "PONG" 的候选（1/2/5），其原创性对冲由副标题承担——副标题不得缺失或空泛。
6. **E2E 正交**：`e2e_shots.json` 01_title 仅断言 VersionLabel 含 `v1.0.0`，与标题文本无关——不要为了截图改命名，也不要为命名改 E2E。
7. **TASTE.md 语义**：命名定稿差异回写 docs/TASTE.md 的"风格特征"节（如"短、直接、霓虹词缀"），但本次草稿不写 TASTE.md——保持命名档案单一文件。

### 失败路径

1. **implement 误改运行时**（改 project.godot / TitleLabel 凑"正式名"）→ 违反 AC4。缓解：PRD §5 边界 1/2 明示，review agent 用 AC4 的 diff 检查卡口。
2. **候选名缺要素**（缺"为什么"或缺候补或缺情感断言）→ 违反 AC1/AC2，用户无法对照定稿。缓解：review agent 按 AC1/AC2 逐条检查。
3. **docs/NAMING.md 缺失或结构不全** → AC1 不满足。缓解：implement 按 §4.2 表结构原样落地，review agent 核对表头六要素（名称/副标题候补/为什么/情感断言/语境/定稿占位）。
4. **主标题超长/生僻词** → 违反边界 3 可读性红线。缓解：review agent 对照边界 3 逐候选校验。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| #289 霓虹赛博视觉（审美坐标来源：#0a0a12 暗底 + 高饱和霓虹） | ✅ CLOSED | 无 |
| #367 手感校准草稿（街机爽感方向：利落击打/直接不绕弯） | ✅ MERGED（草稿） | 无 |
| #358 版本号显示（GAME_VERSION v1.0.0，标题画面左下角） | ✅ CLOSED | 无 |
| taste-ownership-domains.md（B2 命名协议：候选清单 5 选 1） | ✅ 项目内参考 | 无 |

```
#289 霓虹赛博视觉 ──┐
#367 手感草稿（街机爽感）──┼──► #378（本 Issue，命名草稿 + 校准接口）
#358 版本号显示 ───────┘        │
                                ▼
                    docs/NAMING.md（命名档案初版）──► 用户定稿（Assigned to me 队列）
```

**无阻塞。** v4 语义：本 Issue 是 human Issue（taste-draft，B2 命名），**不进依赖链** —— 草稿 merge 即满足下游依赖，下游机械 Issue 不等用户定稿。

---

## 7. Spike / 实验

Skipped per `depth/standard`（Issue 无 depth 标签，按 standard 处理；Section 7 仅 `depth/deep` 必填）。命名不需要实验——候选清单本身就是交付物（B2 协议：agent 给候选，人做最终裁决）；命名对运行时零影响，无可验证的机械行为。

---

## 8. 延续上下文（Continuation Context）

**给 plan agent 的手递**（plan agent 产出 DESIGN 时直接采用，无需重扫源码）：

**系统状态**：命名现状 = 开发代号 "Mini Pong" 全仓唯一（project.godot config/name、TitleLabel、GDD、docs 一致）；`docs/NAMING.md` 尚不存在（需新建）；非正式中文名「霓虹赛博乒乓球」仅存在于 docs/RAW/game-to-issues-mini-pong.json meta；`GAME_VERSION=v1.0.0`（#358）已显示于标题画面左下角。审美坐标：霓虹赛博（#289）+ 街机爽感（#367 手感草稿已注入 constants.gd）。

**主风险**：
1. implement 误改运行时文件（project.godot / TitleLabel）→ 违反 AC4（§5 失败路径 1）
2. 候选名缺要素（为什么/候补/情感断言）→ 用户无法对照定稿（§5 失败路径 2）
3. 定稿流程混淆：本 Issue 是命名草稿，**不 close**——定稿由用户完成（选名 → 改 project.godot + TitleLabel → close）

**下一步（plan → implement）**：
1. DESIGN 引用本 PRD §4.2 候选名集合（5 候选 × 副标题候补 × 为什么 × 情感断言），明确 docs/NAMING.md 表结构
2. implement 只新建 `docs/NAMING.md`：候选名表 + `# DRAFT` + 为什么 + 2-3 副标题候补 + 情感断言 + 语境注释 + 定稿占位；**机械部分零改动**
3. review agent：定稿就绪检查（表结构完整 + taste 方向对齐 + 机械无 DRAFT 残留 + diff 仅文档）→ merge（PR 用 `parent #378`）→ 打 `status/human-review` + assign 用户（workflow-chain.yml 自动）
4. 用户定稿：从 §4.2 选名（或微调）→ 替换 `project.godot config/name` + `ui_start_menu.tscn` TitleLabel → push → close；差异回写 docs/TASTE.md 风格特征节 —— 下次同类命名草稿的方向来源

# DESIGN: [Content] Mini Pong 正式命名草稿 — 标题/副标题候选 (B2)

> **Parent Issue:** #378
> **Agent:** game-plan-agent
> **Date:** 2026-08-11
> **Approach:** A + A + A（PRD §4.1-A 霓虹词缀 + Pong 认知；§4.2 候选 1「PONG://NEON」为主推荐；§4.3-A `docs/NAMING.md` 单一文件）— 确认 PRD 推荐，无分歧
> **Reference PRD:** docs/PRD/378-mini-pong-naming-draft.md
> **所有权:** `content_ownership: taste-draft`（人机共做 v4）— 草稿达标即 merge；PR body 用 `Parent #378`（不写 Closes）；merge 后由 workflow-chain 打 `status/human-review` + assign 用户定稿
> **深度:** depth/standard — 单文件纯文档改动，无 TASKS doc

---

## 1. 概述

本 Issue 是 B2「命名/文案」的 taste-draft 内容 Issue —— **实现即命名草稿**。当前 Mini Pong 只有开发代号「Mini Pong」（`mini-pong/project.godot config/name`、`ui_start_menu.tscn` TitleLabel、GDD、docs 全仓一致），没有任何正式名、副标题候选、命名文档（均已核实）。本设计把 PRD §4.2 的候选名集合固化为 implement 的**唯一契约**：新建 `docs/NAMING.md`，含 **5 候选 × 每候选 2-3 副标题候补 × 为什么 × 情感断言 × 语境注释**，全部带 `# DRAFT` 标记 + 定稿占位；机械部分（`project.godot` / TitleLabel / 测试 / E2E）**零改动**（AC4）。

**消费链（已核实）：**

```
候选名集合（PRD §4.2：5 候选 × 2-3 副标题候补 × 为什么 × 情感断言）
    │
    ▼
docs/NAMING.md（# DRAFT 草稿表 + 语境注释 + 定稿占位）← B2 校准接口（命名表 + 语境注释）
    │  （review 定稿就绪检查 → merge → workflow-chain 打 status/human-review + assign 用户）
    ▼
用户定稿（Assigned to me 队列）：选名/微调 → 替换 project.godot config/name + TitleLabel → close
    │
    ▼
定稿差异回写 docs/TASTE.md 风格特征节（如"短、直接、霓虹词缀"）→ 下次同类命名草稿朝此方向
```

**Plan 阶段边界**：本阶段只产出本文档（`docs/DESIGN/378-*.md`），**不写 `docs/NAMING.md` 本身**、不碰任何 `.gd` / `.tscn` / 测试文件 —— 下列所有内容清单是给 implement agent 的契约。

---

## 2. 候选名集合（核心契约）

> 来源：PRD §4.2（research 建议）。implement **必须**按此表原样填入 `docs/NAMING.md`，可微调但不得违反 §6 边界 3（≤3 词 / 主标题 ≤12 字符 / 无生僻词）与要素齐全（为什么 / 候补 / 情感断言）要求。

| # | 候选名 | 为什么这个名字 | 副标题候补（2-3 个） | 情感断言（体验引擎） |
|---|--------|--------------|-------------------|-------------------|
| 1 | **PONG://NEON** ⭐推荐 | 一记利落的赛博击打：`PONG` = 玩法秒懂；`://` = 协议符号，1 秒把游戏拉进"霓虹赛博"语境；`NEON` = #289 视觉语汇直译。三个元素 9 个字符内全部命中"爽快街机 + 不是克隆" | ① PONG://NEON — 霓虹协议<br>② PONG://NEON — 高速对拍<br>③ PONG://NEON — VOLT DUEL | 带电的邀请——"这是一个协议，你被邀请进入"；利落、直接、赛博 |
| 2 | **NEON PONG** | 最直白的霓虹对冲：玩法认知 + 视觉语汇并列，读起来就是"霓虹赛博乒乓球"的英文版（与 game-to-issues meta 非正式名「Mini Pong — 霓虹赛博乒乓球」一致）；零理解成本 | ① NEON PONG — CYBER RALLY<br>② NEON PONG — 霓虹回响<br>③ NEON PONG — 暗夜对拍 | 熟悉的爽快——"你认识的 Pong，但带电了"；克隆感由副标题对冲 |
| 3 | **VOLT RALLY** | 纯原创：`VOLT`（伏特/电压）= 霓虹电光 + 高速；`RALLY`（对拍）= 乒乓球回合术语 + 街机竞技。完全摆脱"Pong 克隆"标签 | ① VOLT RALLY — NEON PONG<br>② VOLT RALLY — 高压对打<br>③ VOLT RALLY — 霓虹回合 | 高压带电——"每一拍都带电"；原创、利落、竞技张力 |
| 4 | **NEON DUEL** | `DUEL` = 1v1 对决（玩家 vs AI、5 分定胜负的格斗式命名）；双词双音节，街机投币口气质 | ① NEON DUEL — PONG<br>② NEON DUEL — 霓虹对决<br>③ NEON DUEL — 一球定音 | 对决的紧张感——"你和机器，五球定输赢"；Challenge 张力（体验引擎-glossary） |
| 5 | **CYBER PONG** | 最保守稳妥：赛博 + Pong 字面组合，与审美坐标词汇（赛博/霓虹）一字不差；中文语境"赛博乒乓球"自然对应 | ① CYBER PONG — 霓虹之夜<br>② CYBER PONG — 赛博对拍<br>③ CYBER PONG — 暗夜霓虹 | 熟悉世界的陌生化——"赛博世界的乒乓球"；传达最准、原创性最低 |

**推荐（PRD §4.2 结论，implement 原样写入 docs/NAMING.md）：** 主推荐 **候选 1「PONG://NEON」**（`://` 协议符号是 1 秒内赛博语境切换器，比纯文字词缀更利落）；稳妥备选 **候选 2「NEON PONG」**（与既有非正式名一致，零迁移成本）。

### docs/NAMING.md 条目格式模板（implement 按此写，每条候选 6 行）

```markdown
### 候选 1：PONG://NEON ⭐推荐
<!-- # DRAFT 草稿值，待用户定稿 -->
- **为什么这个名字**: 一记利落的赛博击打：PONG = 玩法秒懂；:// = 协议符号；NEON = #289 视觉语汇直译
- **副标题候补**: ① 霓虹协议 ② 高速对拍 ③ VOLT DUEL
- **情感断言**: 带电的邀请——"这是一个协议，你被邀请进入"；利落、直接、赛博
- **语境注释**: 主标题 9 字符 ≤ 12 字符红线；含 "PONG" → 原创性对冲由副标题承担
```

---

## 3. 组件修改清单

### 3.1 新增：`docs/NAMING.md`（命名档案单一文件，结构见 §4）

### 3.2 不改的文件（明确排除）

| 文件 | 原因 |
|------|------|
| `mini-pong/project.godot` | `config/name="Mini Pong"` 是机械标识符（开发代号），**不标 DRAFT、不改**；正式名定稿后由用户替换 |
| `mini-pong/scenes/ui_start_menu.tscn` / `start_menu.gd` | TitleLabel 文本不动——用户定稿阶段统一处理，避免草稿阶段引入半成品 UI 文本 |
| `mini-pong/gdscripts/*.gd` / `tests/*.gd` | 命名与运行时逻辑无耦合；机械部分禁止 `# DRAFT` 残留 |
| `mini-pong/e2e_shots.json` / `run-e2e-review.sh` | 01_title 仅断言 VersionLabel 含 `v1.0.0`，与标题文本正交——不为命名改 E2E，也不为 E2E 改命名 |
| `docs/TASTE.md` | 本次草稿不写 TASTE.md（保持命名档案单一文件）；定稿差异由 review agent 在用户定稿后回写其风格特征节 |
| `docs/GAME_DESIGN/`（GDD） | GDD 记录机制不记录命名过程值；正式名定稿后按需更新 |

### 3.3 PRD 断言核验（PRD Assertion vs Actual Codebase vs Design Resolution）

> plan agent 对 PRD §1/§3 断言逐条核实源码后的结果表。全部 ✅ 无 gap —— 本 Issue 纯文档，无 PRD 漏报项。

| PRD 断言 | 实际代码核验（2026-08-11） | 设计决议 |
|----------|---------------------------|---------|
| `project.godot config/name="Mini Pong"`、`config/description="A classic Pong game implementation"` | ✅ 核实 `mini-pong/project.godot` L13-14 | 机械标识符，零改动（§3.2） |
| TitleLabel `text = "Mini Pong"`（64px 霓虹脉冲） | ✅ 核实 `ui_start_menu.tscn` L20-21（TitleLabel + text），L41 `v1.0.0`（#358） | 零改动；命名草稿与标题显示正交 |
| `docs/NAMING.md` 不存在（需新建） | ✅ 核实：不存在 | §4 新建（implement 契约） |
| RAW meta 曾用非正式名「Mini Pong — 霓虹赛博乒乓球」 | ✅ 核实 `docs/RAW/game-to-issues-mini-pong.json` meta title | 与候选 2「NEON PONG」语义一致，作为备选锚点写入语境注释 |
| `docs/TASTE.md` 初版存在（#367 产出，含候补值表/试玩剧本/情感断言/定稿占位） | ✅ 核实：存在，§4 定稿记录为占位 | 命名定稿差异后续回写其风格特征节（本 PR 不写 TASTE.md） |

---

## 4. docs/NAMING.md 结构（校准接口：命名表 + 语境注释）

> 初版语义 = **草稿表 + 语境注释**（B2 校准接口），不是"定稿记录"；文件头须注明，与 v4 的"定稿差异回写"语义区分（PRD §5 边界 7）。

```markdown
# NAMING.md — Mini Pong 正式命名草稿（# DRAFT，待用户定稿）

> 状态：# DRAFT 草稿（agent 生成，带 taste 方向）
> 来源：Issue #378（B2 命名/文案，人机共做 v4）— 审美坐标：霓虹赛博（#289 落地：#0a0a12 暗底 + 高饱和）+ 街机爽感（#367：#330 px/s 开局、+7%/拍加压、可控性优先）
> 语义：候选清单（5 选 1）+ 语境注释。用户定稿后差异回写 docs/TASTE.md 风格特征节。

## 1. 候选名表（5 选 1）
<!-- 表头六要素：# | 候选名 | 为什么这个名字 | 副标题候补（2-3） | 情感断言 | 语境注释 -->
（= 本文档 §2 表原样填入；每条候选带 # DRAFT 注释）

## 2. 推荐与理由
- 主推荐：候选 1「PONG://NEON」+ 理由（:// 协议符号 = 1 秒赛博语境切换器；9 字符 ≤ 12 红线）
- 稳妥备选：候选 2「NEON PONG」+ 理由（与既有非正式名一致，零迁移成本）

## 3. 命名约束（红线）
- ≤ 3 词、主标题 ≤ 12 字符、无生僻词（1280×720 屏显 + 街机利落感）
- 主标题英文为主（全英文 UI 语境：YOU WIN! / AI WINS! / SPACE）；中文仅作副标题候补
- 含 "PONG" 的候选（1/2/5）：原创性对冲由副标题承担——副标题不得缺失或空泛

## 4. 定稿占位（用户定稿记录处，本次不填）
- 用户操作：选名/微调 → 替换 project.godot config/name + ui_start_menu.tscn TitleLabel → push → close
- 回写：差异记录进 docs/TASTE.md 风格特征节（如"短、直接、霓虹词缀"）
```

---

## 5. 数据流

**Flow 1 — 正常路径（草稿落地）**：
1. implement 新建 `docs/NAMING.md`（§4 结构，§2 候选表原样填入，全部带 `# DRAFT`）
2. review agent 定稿就绪检查：表结构完整（六要素）+ taste 方向对齐（对照审美坐标逐项比对）+ 机械部分无 `# DRAFT` 残留 + diff 仅文档 → 通过
3. 草稿 PR merge（PR body `Parent #378`）→ workflow-chain 识别 taste-draft → 打 `status/human-review` + assign 用户（Issue 保持 open，不 close）

**Flow 2 — 用户定稿路径（v4 队列，非本 PR 范围）**：用户打开 Issue（Assigned to me）→ 对照 §2 候选表选名/微调 → 替换 `project.godot config/name` + TitleLabel → push → close 即定稿 → 差异回写 TASTE.md 风格特征节。

**Flow 3 — 失败路径（草稿不达标）**：候选缺要素（缺为什么/候补/情感断言）或机械部分出现 `# DRAFT` 残留 → review 打回重写，不 assign 用户（不把烂活丢给人，v4 语义）。

---

## 6. 边界条件与错误处理

| # | 边界/风险 | 缓解 |
|---|-----------|------|
| 1 | **implement 误改运行时**（改 project.godot / TitleLabel 凑"正式名"）→ 违反 AC4 | §3.2 明确排除清单；review 以 `git diff main...HEAD --stat` 仅含 docs/ 为卡口 |
| 2 | **候选名缺要素**（缺"为什么"或缺候补或缺情感断言）→ 违反 AC1/AC2，用户无法对照定稿 | review 按 AC1/AC2 逐条检查（§9 Scenario A/B） |
| 3 | **docs/NAMING.md 缺失或结构不全** → AC1 不满足 | implement 按 §4 结构落地；review 核对表头六要素（名称/副标题候补/为什么/情感断言/语境/定稿占位） |
| 4 | **主标题超长/生僻词** → 违反边界 3 可读性红线（≤3 词 / ≤12 字符） | review 对照 §4 命名约束逐候选校验（§9 Scenario D） |
| 5 | **开发代号被误标 DRAFT**：`config/name="Mini Pong"` 是机械标识符 | §3.2 明确"不标 DRAFT、不改"；`grep -rn "# DRAFT" mini-pong/` 必须为空 |
| 6 | **副标题空泛/缺失** → 含 "PONG" 候选（1/2/5）原创性对冲失效 | 每候选副标题 2-3 个且非空泛；review 逐条核对 |
| 7 | **中英双主名并列** → 稀释记忆点；中文主名与全英文 UI 语境冲突 | 主标题英文为主，中文仅作副标题候补（§4 命名约束） |
| 8 | **E2E 正交被破坏**：为命名改 e2e_shots.json 或为截图改命名 | e2e_shots.json 01_title 只断言 VersionLabel，与标题文本无关——两边都不动 |
| 9 | **TASTE.md 语义混淆**：本次草稿误写 TASTE.md | 命名档案单一文件（docs/NAMING.md）；TASTE.md 仅定稿后回写风格特征节 |
| 10 | **定稿流程混淆**：草稿 merge 后误 close Issue | 草稿 merge ≠ 定稿——workflow-chain 只打 `status/human-review` + assign，不 close；close 由用户定稿时执行 |

---

## 7. 集成点

> **Status 约定：** ⬜ = pending；✅ = 已存在/已连接。implement agent 完成命名草稿后更新本表。

| 集成 | 本组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 命名草稿 | `docs/NAMING.md` | 用户定稿（Assigned to me 队列） | 候选表（5 选 1）+ 语境注释 + 定稿占位（B2 校准接口） | ⬜ 待 implement 新建 |
| 机械标识符 | "Mini Pong" | `project.godot config/name` + TitleLabel | 用户定稿阶段替换（本 PR 零改动） | ✅ 保持现状 |
| 品味档案 | `docs/NAMING.md` 草稿 | `docs/TASTE.md` 风格特征节 | 定稿差异回写（用户 close 后 review agent 执行） | ⬜ 待定稿 |
| 下游机械 Issue | 命名草稿 | 依赖链 | 草稿 merge 即依赖满足（human Issue 不进依赖链，v4） | ⬜ 待 merge |
| workflow label | plan PR（`plan/378-*`） | Issue #378 | workflow-chain.yml：plan merge → `workflow/implement`；implement merge → `status/human-review` + assign | ⬜ 待 merge |

---

## 8. 实施阶段

| 阶段 | 优先级 | 内容 | 估算 |
|:-----|:------:|------|:----:|
| Phase 1 | P0 | 新建 `docs/NAMING.md`：§4 结构 + §2 候选表原样填入（5 候选 × 副标题候补 × 为什么 × 情感断言 × 语境注释 + `# DRAFT` + 推荐 + 定稿占位） | 0.5 天 |
| Phase 2 | P0 | 验证：`grep -c "# DRAFT" docs/NAMING.md` ≥ 5、`grep -rn "# DRAFT" mini-pong/` 为空、`git diff main...HEAD --stat` 仅含 docs/、`godot --path mini-pong/ --headless --quit` 回归通过 | 0.25 天 |

单次提交完成（PRD §8 下一步 2：只新建 docs/NAMING.md，机械部分零改动）。

---

## 9. 测试用例描述（仅描述，不写代码）

> B2 领域 T2 不可断言（无法 `assert title == "..."` 验证"好"）——下列测试 = **结构校验（grep/diff，可机械执行）+ taste 对齐（review 人工比对）**。implement agent 不写测试文件；review agent 以本清单为定稿就绪检查卡口。

### Scenario A：候选表结构完整（AC1）
- **Test A1**：`docs/NAMING.md` 存在且非空。前置：implement 已新建。期望：文件存在。
- **Test A2**：`grep -c "# DRAFT" docs/NAMING.md` ≥ 5（每条候选 1 个 + 文件头状态标记）。期望：≥ 5。
- **Test A3**：候选表含 5 个候选名，表头六要素齐全（# / 候选名 / 为什么这个名字 / 副标题候补 / 情感断言 / 语境注释）；抽查 3 条"为什么 + 候补"齐全。期望：六要素齐全，无空单元格。
- **Test A4**：每候选副标题候补 2-3 个（`副标题候补` 列条目数 ∈ [2,3]）。期望：全部满足。
- **Test A5**：推荐字段存在（主推荐 1 个 + 备选 1 个，附理由）。期望：推荐与理由齐全。

### Scenario B：情感断言（AC2）
- **Test B1**：`grep -c "情感断言" docs/NAMING.md` ≥ 5（每条候选 1 个）。期望：≥ 5。
- **Test B2**：每条情感断言含体验引擎词汇（利落 / 直接 / 爽快 / 带电 / 紧张 至少其一），且与审美坐标（霓虹赛博 + 街机爽感）方向一致。期望：5 条全部通过（review 人工比对）。

### Scenario C：机械完整性（AC3/AC4）
- **Test C1**：`grep -rn "# DRAFT" mini-pong/` 为空（机械部分无 DRAFT 残留）。期望：空。
- **Test C2**：`git diff main...HEAD --stat` 仅含 `docs/` 下文件（`docs/PRD/` + `docs/NAMING.md`，不含 mini-pong/）。期望：无 mini-pong/ 改动。
- **Test C3**：`project.godot` / `ui_start_menu.tscn` / `*.gd` / `tests/` / `e2e_shots.json` 零改动。期望：零改动。
- **Test C4**：`godot --path mini-pong/ --headless --quit` 退出码 0、无脚本错误（纯文档改动回归验证，证明运行时未被动）。期望：退出码 0。

### Scenario D：可读性红线（边界 3/4/6/7）
- **Test D1**：每个主标题 ≤ 3 词、≤ 12 字符、无生僻词。期望：5 候选全部满足（PONG://NEON=9 字符 ✓）。
- **Test D2**：主标题英文为主，中文仅出现在副标题候补中。期望：无中文主标题。
- **Test D3**：含 "PONG" 的候选（1/2/5）副标题均非空泛（非"PONG 2"这类占位）。期望：对冲有效。

### Scenario E：taste 方向对齐（review 定稿就绪检查，人工）
- **Test E1**：对照审美坐标逐项比对——霓虹/赛博语汇命中（NEON / CYBER / VOLT / :// / DUEL 至少出现于 3 个候选）、街机爽感（利落直接）方向一致。期望：通过。
- **Test E2**：情感断言与 docs/TASTE.md 现有风格特征方向无冲突（#367 手感：利落击打 / 直接不绕弯）。期望：一致。

---

## 10. 验收标准映射（Issue 4 条 AC）

| AC | 本设计对应 | 验证方式 |
|----|-----------|---------|
| AC1 候选名集中在 docs/NAMING.md 单一文件，agent 填值带 `# DRAFT` 注释 + "为什么这个名字" + 2-3 个候补 | §2 候选表 + §4 结构 | Test A1–A5 |
| AC2 每个候选名附情感断言（体验引擎：利落/直接/爽快） | §2 表"情感断言"列 + §4 条目模板 | Test B1–B2 |
| AC3 机械部分（架构/管线/测试）无 `# DRAFT` 残留 | §3.2 排除清单 + §6 边界 5 | Test C1 |
| AC4 不修改任何游戏运行时行为（纯文档草稿） | §3.2 + §6 边界 1 | Test C2–C4 |

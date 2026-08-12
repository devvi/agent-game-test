# DESIGN: [Content] 波次副句与失败短句 (B5) — 候选清单草稿

> **Parent Issue:** #396
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A + A + A（PRD §4.1-A `mini-pong/content/wave_failure_text.json` 独立 JSON + §4.2 波次副句候选 1「雨声盖过心跳」/ 失败短句候选 1「雨还在下」为主推荐 + §4.3-A 单一 JSON 双组）— 确认 PRD 推荐，无分歧
> **Reference PRD:** docs/PRD/396-wave-failure-copy-draft.md（#400 merged，main 上权威 PRD）
> **所有权:** `content_ownership: taste-draft`（人机共做 v4 — B5 失败表达）— 草稿达标即 merge；PR body 用 `Parent #396`（不写 Closes）；merge 后由 workflow-chain 打 `status/human-review` + assign 用户定稿
> **深度:** depth/standard（Issue 无 depth 标签，按 #358 惯例按 standard 处理）— 单 JSON 内容文件改动，无 TASKS doc

---

## 1. 概述

本 Issue 是 B5「失败表达」的 taste-draft 内容 Issue —— **实现即内容草稿**。PONG://21 攻城战肉鸽（竖屏 720×1280，Godot 4.7.1）的机械管线已由 #390（波次转场：大字「第 N 道墙」+ 副句，2s 淡入-停留-淡出，副句从统一文本配置读取）与 #391（失败屏：短句 + run 数据 波次/拆砖/穿墙，短句从配置读取且无 emoji/夸张语气）预留两个**内容插槽**，但 `mini-pong/content/` 目录与任何文本配置资源**均不存在**（已核实：`mini-pong/` 下仅有 assets/gdscripts/scenes/tests/project.godot/e2e_shots.json）。本设计把 PRD §4.2 的候选清单固化为 implement 的**唯一契约**：新建 `mini-pong/content/wave_failure_text.json`，含 **波次副句 4 候选（≤15 字）× 失败短句 4 候选（≤10 字）× 适用语境 × 情感断言 × 推荐标记**，顶层 `"draft": true`；机械部分（gdscripts/scenes/tests/E2E）**零改动**（AC5）。

**消费链（已核实）：**

```
候选清单（PRD §4.2：波次副句 4 × ≤15 字 × 语境 + 失败短句 4 × ≤10 字 × severity）
    │
    ▼
mini-pong/content/wave_failure_text.json（draft: true + 推荐标记）← B5 校准接口
    │  （review 定稿就绪检查 → merge → workflow-chain 打 status/human-review + assign 用户）
    │  （#390 波次转场 / #391 失败屏 运行时从本文件读取）
    ▼
用户定稿（Assigned to me 队列）：选 1 / 微调 → push → close
    │
    ▼
定稿差异回写 docs/TASTE.md（B5 风格特征：删形容词、雨意象）→ 下次草稿朝此方向
```

**Plan 阶段边界**：本阶段只产出本文档（`docs/DESIGN/396-*.md`），**不写 `mini-pong/content/wave_failure_text.json` 本身**、不碰任何 `.gd` / `.tscn` / 测试文件 —— 下列所有内容清单是给 implement agent 的契约。

---

## 2. 候选清单（核心契约）

> 来源：PRD §4.2（research 建议）。implement **必须**按此表原样填入 `mini-pong/content/wave_failure_text.json`，可微调但不得违反 §6 边界 3/4（字数红线：副句 ≤15 / 短句 ≤10，含标点）与要素齐全（text/context/emotion/recommended 四字段）要求。

### 2.1 波次副句（波次转场「第 N 道墙」下方，≤15 字）

| # | 候选副句 | 字数 | 适用语境（第几波） | 情感断言（体验引擎） | 设计说明 |
|---|---------|:---:|-------------------|---------------------|---------|
| 1 | **雨声盖过心跳** ⭐推荐 | 6 | 波 1-2（开局/教学薄墙） | 仪式感的平静——开局"呼吸点"，雨声替代心跳，张力尚未升起 | 开局副句只做氛围铺垫，不预告难度；动词"盖过"给短句击打感 |
| 2 | **每一道墙都更厚** | 7 | 波 3-5（中段加压） | 递增的压迫——Challenge 可视化，玩家"看见"难度曲线 | 陈述事实，不加感叹；"更厚"是单修饰词，符合无形容词堆砌红线 |
| 3 | **雨越下越大** | 5 | 波 6+（后期高压） | 渐强的紧张——雨量因子 +0.1/波 的文案化，压力表读数 | 与雨量系统同构（rain = f(波次)）；零形容词，纯陈述 |
| 4 | **拆到墙倒为止** | 6 | 决胜波（比分接近 21） | 冷静的决心——不呐喊的决绝，动词"拆"驱动 | 决胜句不放狠话、不加感叹号；"为止"收束，海明威式 |

### 2.2 失败短句（失败屏，≤10 字）

| # | 候选短句 | 字数 | 适用语境（失败 severity） | 情感断言（体验引擎） | 设计说明 |
|---|---------|:---:|--------------------------|---------------------|---------|
| 1 | **雨还在下** ⭐推荐 | 4 | 早败（波 1-2 教学波即败） | 世界的漠然——失败不惩罚、不鼓励，世界照常运转（空洞骑士式沉默） | B5 核心品味"失败=叙事生产"的最纯形态；雨替玩家承担情绪 |
| 2 | **雨记住了这一局** | 7 | 中败（波 3-5，有实质 run 数据） | 失败被铭记——拆砖/穿墙数据随雨留存，run 有痕迹 | 与失败屏 run 数据（波次/拆砖/穿墙）呼应：数据即记忆 |
| 3 | **就差一道墙** | 5 | 晚败/惜败（波 6+ 或比分接近 21） | 克制的遗憾——极乐迪斯科式文学时刻："你无法让金尊重你"的同类语法 | 只差一线的悔意，用"墙"（进程表）量化；零形容词 |
| 4 | **墙还在，雨未停** | 7 | 通用兜底（任意波次） | 无声的坚韧——不煽情的中立陈述，可作默认短句 | 双意象并列（进程仍在 + 压力未消）；逗号制造留白 |

**推荐（PRD §4.2 结论，implement 原样写入 JSON）：** 主推荐 **副句候选 1「雨声盖过心跳」+ 短句候选 1「雨还在下」**（`recommended: true`）；用户定稿时可改选任何候选（含跨组混搭）。

> 全部候选通过海明威校验：无感叹号（含全角 `！`）、无形容词堆砌（每句修饰词 ≤1）、无 emoji、无网络梗、无"你输了/太弱了"惩罚性措辞、无"下次一定"式空洞鼓励。字数均低于 AC 上限（副句 ≤15 / 短句 ≤10）。

---

## 3. 组件修改清单

### 3.1 新增：`mini-pong/content/wave_failure_text.json`（B5 内容资源单一文件，结构见 §4）

### 3.2 不改的文件（明确排除）

| 文件 | 原因 |
|------|------|
| `mini-pong/gdscripts/*.gd`（含 `constants.gd`） | 文案不进代码层/常量层（AC5 + 与 A1 数值单一事实源职责分离）；机械插槽由 #390/#391 实现 |
| `mini-pong/scenes/*.tscn` | 转场/失败屏 UI 属于 #390/#391，本 Issue 零改动 |
| `mini-pong/tests/*.gd` / `e2e_shots.json` | 纯内容文件，无运行时差异；`e2e_shots.json` 断言不涉及新插槽 |
| `docs/TASTE.md` | 本次草稿不写 TASTE.md；定稿差异由 review agent 在用户定稿后回写其风格特征节 |
| `mini-pong/project.godot` | 引擎配置零改动 |

### 3.3 PRD 断言核验（PRD Assertion vs Actual Codebase vs Design Resolution）

> plan agent 对 PRD §1/§3 断言逐条核实源码后的结果表。全部 ✅ 无 gap。

| PRD 断言 | 实际代码核验（2026-08-13） | 设计决议 |
|----------|---------------------------|---------|
| `mini-pong/content/` 目录与内容资源不存在（需新建） | ✅ 核实：`ls mini-pong/content` → No such file；`mini-pong/` 下无任何 JSON 文本配置（`e2e_shots.json` 是 E2E 截图断言，非内容资源） | §4 新建（implement 契约） |
| `mini-pong/` 自有 project.godot，Godot 4.7.1 | ✅ 核实：`config/features=PackedStringArray("4.7")`，`config/name="PONG://NEON"`（#378 定稿已生效） | 引擎配置零改动（§3.2） |
| #390 波次转场读 `wave_subtitles`、#391 失败屏读 `failure_phrases` | ✅ 设计对齐：schema 字段名与消费方读取点一一对应（§4） | 字段名以 PRD §4.3 schema 为准 |
| 消费方协议：content 资源必须是运行时可加载的独立文件（JSON） | ✅ 核实：`res://` = `mini-pong/`；JSON 用 `FileAccess.get_file_as_string()` + `JSON.parse_string()`（Godot 4.7 内置，项目已有 `e2e_shots.json` JSON 先例） | 独立 JSON 文件，非 docs 文档 |

---

## 4. `mini-pong/content/wave_failure_text.json` 结构（校准接口：候选表 + 语境 + 情感断言）

> 来源：PRD §4.3 schema（`wave-failure-text/v1`）。**这是 implement 的唯一契约**——字段名与 #390（`wave_subtitles`）/ #391（`failure_phrases`）读取点一一对应，implement 原样落地，review 核对字段名（§6 边界 5）。

```json
{
  "schema": "wave-failure-text/v1",
  "draft": true,
  "wave_subtitles": [
    { "id": "ws1", "text": "雨声盖过心跳", "context": "波 1-2（开局）", "emotion": "仪式感的平静", "recommended": true },
    { "id": "ws2", "text": "每一道墙都更厚", "context": "波 3-5（中段加压）", "emotion": "递增的压迫", "recommended": false },
    { "id": "ws3", "text": "雨越下越大", "context": "波 6+（后期高压）", "emotion": "渐强的紧张", "recommended": false },
    { "id": "ws4", "text": "拆到墙倒为止", "context": "决胜波（比分接近 21）", "emotion": "冷静的决心", "recommended": false }
  ],
  "failure_phrases": [
    { "id": "fp1", "text": "雨还在下", "context": "早败（波 1-2）", "emotion": "世界的漠然", "recommended": true },
    { "id": "fp2", "text": "雨记住了这一局", "context": "中败（波 3-5）", "emotion": "失败被铭记", "recommended": false },
    { "id": "fp3", "text": "就差一道墙", "context": "晚败/惜败（波 6+ 或接近 21）", "emotion": "克制的遗憾", "recommended": false },
    { "id": "fp4", "text": "墙还在，雨未停", "context": "通用兜底（任意波次）", "emotion": "无声的坚韧", "recommended": false }
  ]
}
```

**字段语义：**

| 字段 | 语义 |
|------|------|
| `schema` | 版本化标识 `wave-failure-text/v1`——#390/#391 读取时校验版本，防 schema 漂移 |
| `draft` | 顶层 `true` = JSON 世界的 `# DRAFT` 标记（JSON 无注释语法）；用户定稿后由用户移除或置 false |
| `wave_subtitles[]` | 波次副句候选组（≥3，每条 ≤15 字）；`id` = 稳定标识（ws1-ws4）；`text` = 候选文案；`context` = 适用波次区间（#390 按 wave_index 分档选句）；`emotion` = 情感断言；`recommended` = research 建议标记（用户可改选） |
| `failure_phrases[]` | 失败短句候选组（≥3，每条 ≤10 字）；`context` = 失败 severity 分档（#391 按 run 数据分档选句） |

---

## 5. 数据流

**Flow 1 — 正常路径（草稿落地）**：
1. implement 新建 `mini-pong/content/wave_failure_text.json`（§4 结构，§2 候选表原样填入，`draft: true` + 推荐标记）
2. review agent 定稿就绪检查：结构完整（候选 ≥3 × 字限 × context/emotion/recommended 四字段齐全）+ taste 方向对齐（海明威式/无感叹号/无形容词堆砌）+ 机械部分无文案残留 + diff 仅 content JSON → 通过
3. 草稿 PR merge（PR body `Parent #396`）→ workflow-chain 识别 taste-draft → 打 `status/human-review` + assign 用户（Issue 保持 open，不 close）

**Flow 2 — 用户定稿路径（v4 队列，非本 PR 范围）**：用户打开 Issue（Assigned to me）→ 对照 §2 候选表选 1 / 微调 → push → close 即定稿 → 差异回写 TASTE.md 风格特征节。

**Flow 3 — 失败路径（草稿不达标）**：候选缺要素（缺 context/emotion/recommended）或字限超限或感叹号残留或机械部分出现文案 → review 打回重写，不 assign 用户（不把烂活丢给人，v4 语义）。

---

## 6. 边界条件与错误处理

| # | 边界/风险 | 缓解 |
|---|-----------|------|
| 1 | **implement 误改运行时**（改 gdscripts/scenes 凑"生效"）→ 违反 AC5 | §3.2 明确排除清单；review 以 `git diff main...HEAD --stat` 仅含 `mini-pong/content/` + `docs/` 为卡口 |
| 2 | **候选缺要素**（缺 context 或缺 emotion 或缺 recommended）→ 用户无法对照定稿 | review 按 §2 表结构逐条核对（text/context/emotion/recommended 四字段） |
| 3 | **字限超限**（副句 >15 / 短句 >10，含标点）→ 违反 AC1/AC2 | implement 用 §9 Scenario A/B 的 python 验证命令自检；review 复核 |
| 4 | **感叹号/惩罚性措辞残留**（`！`/`!`/「你输了」「下次一定」）→ 违反 AC3 | `grep -c '[！!]'` 为 0；review 人工比对 taste 方向（T2 不可断言，形容词堆砌靠人） |
| 5 | **JSON 结构不符**（字段名与 #390/#391 读取点不一致）→ 消费方读不到 | §4 schema 版本化（`wave-failure-text/v1`），implement 原样落地，review 核对字段名 |
| 6 | **文案写进 .gd 注释/常量** → 违反 AC5 精神 | 边界 1 grep 检查（gdscripts/ 内无候选字符串） |
| 7 | **定稿流程混淆**：草稿 merge 后误 close Issue | 草稿 merge ≠ 定稿——workflow-chain 只打 `status/human-review` + assign，不 close；close 由用户定稿时执行（PR 用 `Parent #396` 不写 Closes） |
| 8 | **E2E 正交被破坏**：为文案改 e2e_shots.json 或为截图改文案 | 波次转场/失败屏为 PONG://21 新插槽，`e2e_shots.json` 现有断言不涉及——两边都不动 |

---

## 7. 集成点

> **Status 约定：** ⬜ = pending；✅ = 已存在/已连接。implement agent 完成内容草稿后更新本表。

| 集成 | 本组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 内容草稿 | `mini-pong/content/wave_failure_text.json` | 用户定稿（Assigned to me 队列） | 候选清单（4+4 候选 × 语境 × 情感断言 × 推荐标记）+ `draft: true`（B5 校准接口） | ⬜ 待 implement 新建 |
| 消费方 #390 波次转场 | `wave_subtitles[]` | 波次转场副句（从统一文本配置读取） | 按 wave_index 分档读 `text`（#390 实现时接入，本 PR 零改动） | ⬜ 待 #390 |
| 消费方 #391 失败屏 | `failure_phrases[]` | 失败屏短句（从配置读取） | 按 run 数据 severity 分档读 `text`（#391 实现时接入，本 PR 零改动） | ⬜ 待 #391 |
| 品味档案 | 内容草稿 | `docs/TASTE.md` 风格特征节 | 定稿差异回写（用户 close 后 review agent 执行） | ⬜ 待定稿 |
| workflow label | plan PR（`plan/396-*`） | Issue #396 | workflow-chain.yml：plan merge → `workflow/implement`；implement merge → `status/human-review` + assign | ⬜ 待 merge |

---

## 8. 实施阶段

| 阶段 | 优先级 | 内容 | 估算 |
|:-----|:------:|------|:----:|
| Phase 1 | P0 | 新建 `mini-pong/content/wave_failure_text.json`：§4 结构 + §2 候选表原样填入（4 副句 + 4 短句 × context/emotion/recommended + `draft: true` + schema 版本化） | 0.25 天 |
| Phase 2 | P0 | 验证：§9 Scenario A/B 的 python/grep 断言、`grep -rn "雨还在下\|雨声盖过心跳" mini-pong/gdscripts/ mini-pong/scenes/` 为空、`git diff main...HEAD --stat` 仅含 content JSON、`godot --path mini-pong/ --headless --quit` 回归通过 | 0.25 天 |

单次提交完成（PRD §8 下一步 2：只新建 `mini-pong/content/wave_failure_text.json`，机械部分零改动）。

---

## 9. 测试用例描述（仅描述，不写代码）

> B5 领域 T2 不可断言（无法 `assert text == "..."` 验证"好"）——下列测试 = **结构校验（python/grep，可机械执行）+ taste 对齐（review 人工比对）**。implement agent 不写测试文件；review agent 以本清单为定稿就绪检查卡口。

### Scenario A：波次副句候选（AC1）
- **Test A1**：`mini-pong/content/wave_failure_text.json` 存在且可被 `json.load` 解析。前置：implement 已新建。期望：解析成功。
- **Test A2**：`len(d['wave_subtitles']) >= 3`。期望：≥ 3（交付 4 条）。
- **Test A3**：每条 `len(s['text']) <= 15`。期望：全部 ≤ 15（最长 7 字）。
- **Test A4**：每条含 `id`/`text`/`context`/`emotion`/`recommended` 五字段。期望：四要素齐全（§6 边界 2）。

### Scenario B：失败短句候选（AC2）
- **Test B1**：`len(d['failure_phrases']) >= 3`。期望：≥ 3（交付 4 条）。
- **Test B2**：每条 `len(f['text']) <= 10`。期望：全部 ≤ 10（最长 7 字）。
- **Test B3**：每条含 `id`/`text`/`context`/`emotion`/`recommended` 五字段。期望：四要素齐全。

### Scenario C：海明威式红线（AC3）
- **Test C1**：`grep -c '[！!]' mini-pong/content/wave_failure_text.json` 为 0。期望：0。
- **Test C2**：无 emoji/网络梗（review 人工比对）。期望：通过。
- **Test C3**：taste 方向对齐——对照 PRD §2（海明威式/雨意象/失败=叙事生产）逐条比对，无"你输了/太弱了"惩罚性措辞、无"下次一定"式空洞鼓励。期望：4+4 条全部通过（review 人工比对）。

### Scenario D：机械完整性（AC4/AC5）
- **Test D1**：`grep -rn "雨还在下\|雨声盖过心跳" mini-pong/gdscripts/ mini-pong/scenes/` 为空（文案不散落代码）。期望：空。
- **Test D2**：`git diff main...HEAD --stat` 仅含 `mini-pong/content/wave_failure_text.json`（+ 本 PRD/DESIGN 的 docs/ 文件），无 `mini-pong/gdscripts/`、`scenes/`、`tests/`、`e2e_shots.json` 改动。期望：无运行时文件改动。
- **Test D3**：`godot --path mini-pong/ --headless --quit` 退出码 0、无脚本错误（纯内容文件改动回归验证，证明运行时未被动）。期望：退出码 0。

### Scenario E：schema 契约（消费方协议）
- **Test E1**：顶层 `"schema": "wave-failure-text/v1"` 存在。期望：存在。
- **Test E2**：顶层 `"draft": true` 存在。期望：存在。
- **Test E3**：`wave_subtitles` / `failure_phrases` 字段名与 PRD §4.3 一致（#390 读 `wave_subtitles[].text`、#391 读 `failure_phrases[].text`）。期望：字段名完全一致。

---

## 10. 验收标准映射（Issue 5 条 AC）

| AC | 本设计对应 | 验证方式 |
|----|-----------|---------|
| AC1 波次副句 ≥3 条候选，每条 ≤15 字 | §2.1 候选表（4 条，6/7/5/6 字）+ §4 `wave_subtitles[]` | Test A1–A4 |
| AC2 失败短句 ≥3 条候选，每条 ≤10 字 | §2.2 候选表（4 条，4/7/5/7 字）+ §4 `failure_phrases[]` | Test B1–B3 |
| AC3 海明威式短句，无形容词堆砌和感叹号 | §2 全部候选（修饰词 ≤1、无 `！`/`!`、无 emoji）+ §6 边界 4 | Test C1–C3 |
| AC4 每条注明适用语境（第几波/失败 severity） | §2 `context` 列 + §4 `context` 字段（波次区间 / severity 分级） | Test A4/B3 中 context 校验 |
| AC5 文案放入独立 content 资源，不作为注释散落代码 | §3.1 新增 `mini-pong/content/wave_failure_text.json` + §3.2 排除清单 | Test D1–D3 |

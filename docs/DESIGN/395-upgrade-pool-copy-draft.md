# DESIGN: [Content] 升级池文案定稿 — 9 升级短句与命名候选 (B2/B5)

> **Parent Issue:** #395
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A + A + A（PRD §4.1-A JSON 资源文件 + §4.2-A 雨夜克制短句 + §4.3-A 工作名 + 同味候补）— 确认 PRD 推荐，无分歧
> **Reference PRD:** docs/PRD/395-upgrade-pool-copy-draft.md
> **所有权:** `content_ownership: taste-draft`（人机共做 v4）— 草稿达标即 merge；PR body 用 `Parent #395`（不写 Closes）；merge 后由 workflow-chain 打 `status/human-review` + assign 用户定稿
> **深度:** depth/light — 纯数据文件（1 个 JSON）改动，无 TASKS doc

---

## 1. 概述

本 Issue 是 B2「命名/文案」+ B5「失败表达」的 taste-draft 内容 Issue —— **实现即文案草稿落地**。当前升级池 9 个升级（长臂/燃烧弹/破城锤/磁心/双生/缓时/预开洞/星尘/幻影）只有机械工作名（出自 #387 功能描述与 `docs/PLAN-rogue-pong.md` §2.5 确认稿），**没有任何面向玩家的文案资源**（已核实：`mini-pong/assets/content/` 目录不存在）。本设计把 PRD §4.1 的 JSON schema 与 §4.4 的候选表固化为 implement 的**唯一契约**：新建 `mini-pong/assets/content/upgrade_pool.json`，含 **9 升级 ×（短句 + 3 命名候选 + 推荐标记 + `draft:true` + 情绪断言 + 语境注释）**；机械部分（`gdscripts/` / `scenes/` / 测试 / E2E）**零改动**（AC5 + 边界 1）。

**消费链（已核实）：**

```
docs/PLAN-rogue-pong.md §2.5（9 升级清单/情感断言/价值极）
    │
    ▼
mini-pong/assets/content/upgrade_pool.json（本 Issue：draft 草稿 + 候选 + 推荐 + 情绪断言）← B2/B5 校准接口
    │  （review 定稿就绪检查 → merge → workflow-chain 打 status/human-review + assign 用户）
    ▼
用户定稿（Assigned to me 队列）：改 JSON 短句/选命名 → push → close
    │
    ▼
#387 UpgradePool / #388 3选1 UI 读取 JSON → 卡片渲染（机械层，不在本 Issue）
    │
    ▼
定稿差异回写 docs/TASTE.md 风格特征节 → 下次同类文案草稿朝此方向
```

**Plan 阶段边界**：本阶段只产出本文档（`docs/DESIGN/395-*.md`），**不写 `upgrade_pool.json` 本身**、不碰任何 `.gd` / `.tscn` / 测试文件 —— 下列所有内容清单是给 implement agent 的契约。

---

## 2. 核心契约：JSON schema 与候选文案集合

> 来源：PRD §4.1（schema）+ §4.4（候选表，research 建议草稿）。implement **必须**按此表原样填入 `upgrade_pool.json`（可微调但不得违反 §6 边界：短句 ≤12 字 / 无梗无 emoji 无感叹号 / 候选 ≥2 且恰 1 推荐 / id 与 #387 一致）。

### 2.1 JSON schema（`upgrade-pool-content/v1`，PRD §4.1-A）

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

- 顶层 `draft: true` + 每升级 `phrase_draft: true` = `#DRAFT` 标注（机器可断言，等价注释）
- `rarity` 枚举：`common` / `rare` / `legendary`（与 #387 一致）

### 2.2 候选文案集合（9 升级，PRD §4.4 原样）

| # | 升级 (id) | 稀有度 | 短句草稿（≤12字） | 命名候选（推荐加粗） | 情绪断言 |
|---|-----------|:---:|---------|---------|---------|
| 1 | 长臂 (long_arm) | 普通 | **够得着了**（4字） | **长臂** ／ 伸臂 ／ 延展 | 安全感 —— 价值极 安全/危险 向安全移动 |
| 2 | 燃烧弹 (fireball) | 普通 | **火过留洞**（4字） | **燃烧弹** ／ 火流星 ／ 余烬弹 | 破坏欲 —— 价值极 破坏/受阻 向破坏移动 |
| 3 | 破城锤 (battering_ram) | 普通 | **一锤碎一片**（5字） | **破城锤** ／ 震击 ／ 夯 | 暴力释放 —— 一击碎一片的畅快 |
| 4 | 磁心 (magnet_core) | 稀有 | **球听你的**（4字） | **磁心** ／ 引力核心 ／ 磁握 | 掌控感 —— 价值极 技能/无能 向技能移动 |
| 5 | 双生 (twin) | 稀有 | **一球变两球**（5字） | **双生** ／ 分裂 ／ 双子 | 兴奋 —— 价值极 秩序/混沌：场面失控但归你 |
| 6 | 缓时 (slow_time) | 稀有 | **时间让路**（4字） | **缓时** ／ 凝时 ／ 冻结 | 时间主宰 —— 价值极 快/慢：世界等你 |
| 7 | 预开洞 (pre_hole) | 稀有 | **洞先开好**（4字） | **预开洞** ／ 先行 ／ 破晓 | 先手优势 —— 价值极 主动/被动：棋高一着 |
| 8 | 星尘 (stardust) | 传说 | **所过之处留痕**（6字） | **星尘** ／ 星轨 ／ 余辉 | 支配感 —— 价值极 支配/服从：全场都是你的痕迹 |
| 9 | 幻影 (phantom) | 传说 | **快得看不清**（5字） | **幻影** ／ 残像 ／ 影先行 | 敏捷快感 —— 价值极 敏捷/笨拙：快得看不清 |

**推荐（PRD §4.1/4.2/4.3 结论，implement 原样写入 JSON）：** 载体选 JSON（4.1-A）+ 雨夜克制短句（4.2-A）+ 工作名 + 同味候补（4.3-A）。每升级 `naming_candidates` 恰 1 个 `recommended: true`（= 机械工作名，跨文档一致兜底）。

---

## 3. 组件修改清单

### 3.1 新增：`mini-pong/assets/content/upgrade_pool.json`（唯一文案载体，结构见 §4）

### 3.2 不改的文件（明确排除）

| 文件 | 原因 |
|------|------|
| `mini-pong/gdscripts/*.gd` / `tests/*.gd` | 文案与运行时逻辑零耦合（AC5 硬性要求）；#387 未实现前禁止写任何读取代码（边界 1） |
| `mini-pong/scenes/`（#388 升级卡 UI 待建） | 本 Issue 不碰 UI；渲染由 #388 负责 |
| `mini-pong/e2e_shots.json` / `run-e2e-review.sh` | 现有 shot 均不涉及升级卡文本，无影响 |
| `docs/NAMING.md` / `docs/TASTE.md` | 本次草稿不写（§6 去冲突：命名档案 scope 不同；定稿差异由 review agent 回写 TASTE.md） |
| `mini-pong/project.godot` | 引擎配置零改动（纯数据文件不触发） |

### 3.3 PRD 断言核验（PRD Assertion vs Actual Codebase vs Design Resolution）

> plan agent 对 PRD §1/§3 断言逐条核实源码后的结果表。全部 ✅ 无 gap —— 本 Issue 纯数据文件，无 PRD 漏报项。

| PRD 断言 | 实际代码核验（2026-08-13） | 设计决议 |
|----------|---------------------------|---------|
| `mini-pong/assets/content/` 目录不存在（需新建） | ✅ 核实：`mini-pong/assets/` 仅有 3 个视觉 .tres（neon_glow_material / particle_material / gradient_neon），无 content/ | §4 新建目录 + JSON（implement 契约） |
| 9 升级仅有机械工作名，无文案字段 | ✅ 核实：`mini-pong/gdscripts/` 无任何升级文案硬编码（constants.gd 无升级池定义——#387 未实现） | 文案数据契约独立落地，机械零改动 |
| 消费方 #387（UpgradePool）/ #388（3 选 1 UI）均为 OPEN | ✅ 核实 Issue 状态 | 本 Issue 只定义数据契约，接入归 #387/#388 scope |
| 短句红线：≤12 字 / 无梗 / 无 emoji / 无感叹号 | ✅ 核实 §4.4 草稿：9 条短句 4-6 字，无违规字符 | implement 原样填入；review 按 §9 Scenario D 校验 |

---

## 4. upgrade_pool.json 结构（校准接口：文案数据契约）

> 初版语义 = **草稿表 + 语境注释**（B2/B5 校准接口），不是"定稿记录"；`draft: true` 字段区分草稿/定稿（PRD §5 边界 5）。

```jsonc
// mini-pong/assets/content/upgrade_pool.json（JSON 无注释，此块仅为 implement 说明）
{
  "schema": "upgrade-pool-content/v1",
  "draft": true,                                // 顶层草稿标记（= #DRAFT）
  "upgrades": [                                  // 恰 9 条，id 与 #387 一致
    // 每条：id / name_working / rarity / short_phrase / phrase_draft:true /
    //       emotion / emotion_assertion / naming_candidates(≥2，恰 1 recommended:true) / context
    // §2.2 表 9 行原样填入
  ]
}
```

- **id 契约（边界 2）**：`long_arm / fireball / battering_ram / magnet_core / twin / slow_time / pre_hole / stardust / phantom`
- **稀有度枚举**：`common / rare / legendary`
- **用户定稿路径**：改 `short_phrase` / 选 `naming_candidates` / 将 `draft` 与 `phrase_draft` 置 false 或删除 → push → close

---

## 5. 数据流

**Flow 1 — 正常路径（草稿落地）**：
1. implement 新建 `mini-pong/assets/content/upgrade_pool.json`（§4 结构，§2.2 候选表原样填入，`draft:true` + `phrase_draft:true`）
2. review agent 定稿就绪检查：JSON schema 合法（`JSON.parse_string` 可解析）+ 9 条全要素（短句/候选/推荐/情绪断言）+ taste 方向对齐（对照 §2 方向逐项比对）+ 机械无 DRAFT 残留 + diff 仅数据文件 → 通过
3. 草稿 PR merge（PR body `Parent #395`）→ workflow-chain 识别 taste-draft → 打 `status/human-review` + assign 用户（Issue 保持 open，不 close）

**Flow 2 — 用户定稿路径（v4 队列，非本 PR 范围）**：用户打开 Issue（Assigned to me）→ 对照候选表选名/改短句（GitHub Web UI 直接编辑 JSON）→ push → close 即定稿 → 差异回写 TASTE.md 风格特征节（如"升级文案 4-6 字、点价值极、雨夜意象"）。

**Flow 3 — 失败路径（草稿不达标）**：JSON 缺要素（缺短句/候选/推荐/情绪断言）或机械部分出现改动 → review 打回重写，不 assign 用户（不把烂活丢给人，v4 语义）。

---

## 6. 边界条件与错误处理

| # | 边界/风险 | 缓解 |
|---|-----------|------|
| 1 | **implement 误改运行时**（在 gdscripts/ 写读取代码或把文案硬编码进逻辑）→ 违反 AC5/边界 1 | §3.2 明确排除清单；review 以 `git diff main...HEAD --stat` 仅含 `docs/PRD/` 与 `mini-pong/assets/content/upgrade_pool.json` 为卡口 |
| 2 | **id 与 #387 不一致** → 机械层匹配失败，卡片显示空文案 | implement 对照 §4 id 契约逐条核对（9 id + 3 稀有度枚举） |
| 3 | **候选缺要素**（缺短句/缺候选数/缺推荐标记/缺情绪断言）→ 用户无法对照定稿 | review 按 AC1-AC3 逐条脚本断言（§9 Scenario A/B） |
| 4 | **短句超长/形容词堆砌/带感叹号** → 违反 AC1/AC4 与克制方向 | review 对照 §2.2 表逐条校验（≤12 字）+ validate_hemingway 域规则（§9 Scenario D） |
| 5 | **把游戏名/波次文案混入本资源** → scope 越界（与 #378/#396 冲突） | §6 去冲突：本 JSON 只装 9 升级条目；波次/失败文案归 #396 独立资源 |
| 6 | **`draft` 语义混淆**：草稿 merge 后误 close Issue | 草稿 merge ≠ 定稿——workflow-chain 只打 `status/human-review` + assign，不 close；close 由用户定稿时执行 |
| 7 | **JSON 语法错误** → 未来 #387/#388 无法解析 | implement 落地后立即用 `python3 -m json.tool` / Godot `JSON.parse_string` 校验（§9 Scenario C） |

---

## 7. 集成点

> **Status 约定：** ⬜ = pending；✅ = 已存在/已连接。implement agent 完成文案草稿后更新本表。

| 集成 | 本组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 文案草稿 | `mini-pong/assets/content/upgrade_pool.json` | 用户定稿（Assigned to me 队列） | 9 升级 × 短句 + 候选 + 推荐 + 情绪断言（B2/B5 校准接口） | ⬜ 待 implement 新建 |
| 机械层 | `upgrade_pool.json` | #387 UpgradePool | 按 id 匹配文案（机械接入在 #387 scope，本 Issue 零改动） | ✅ 保持现状 |
| UI 层 | `upgrade_pool.json` | #388 3 选 1 升级卡 | 卡片从 JSON 取短句与名称渲染（接入在 #388 scope） | ✅ 保持现状 |
| 品味档案 | `upgrade_pool.json` 草稿 | `docs/TASTE.md` 风格特征节 | 定稿差异回写（用户 close 后 review agent 执行） | ⬜ 待定稿 |
| workflow label | plan PR（`plan/395-*`） | Issue #395 | workflow-chain.yml：plan merge → `workflow/implement`；implement merge → `status/human-review` + assign | ⬜ 待 merge |

---

## 8. 实施阶段

| 阶段 | 优先级 | 内容 | 估算 |
|:-----|:------:|------|:----:|
| Phase 1 | P0 | 新建 `mini-pong/assets/content/upgrade_pool.json`：§4 结构 + §2.2 候选表原样填入（9 升级 × 短句 + 3 候选 + 推荐 + `draft:true` + 情绪断言 + 语境注释） | 0.5 天 |
| Phase 2 | P0 | 验证：`python3 -m json.tool` 可解析、AC1-AC3 脚本断言通过、`git diff main...HEAD --stat` 仅含 `docs/PRD/` 与 `upgrade_pool.json`、`godot --path mini-pong/ --headless --quit` 回归通过 | 0.25 天 |

单次提交完成（PRD §8 下一步 2：只新建 `upgrade_pool.json`，机械部分零改动）。

---

## 9. 测试用例描述（仅描述，不写代码）

> B2/B5 领域 T2 不可断言（无法 `assert short_phrase == "..."` 验证"好"）——下列测试 = **结构校验（python 脚本/grep/diff，可机械执行）+ taste 对齐（review 人工比对）**。implement agent 不写测试文件；review agent 以本清单为定稿就绪检查卡口。PRD §5 已给出可执行验证命令，此处为描述版。

### Scenario A：JSON 结构完整（AC1/AC2/AC3）
- **Test A1**：`mini-pong/assets/content/upgrade_pool.json` 存在且可被 `json.load` 解析。期望：解析成功。
- **Test A2**：`len(d['upgrades']) == 9` 且 id 集合 = `{long_arm, fireball, battering_ram, magnet_core, twin, slow_time, pre_hole, stardust, phantom}`。期望：9 条全齐。
- **Test A3**：每条含 `short_phrase` / `emotion_assertion` / `naming_candidates` / `context` 字段。期望：无缺失字段。
- **Test A4**：每条 `len(short_phrase) <= 12`（中文按字符计）。期望：9 条全部满足（实际 4-6 字）。
- **Test A5**：每条 `len(naming_candidates) >= 2` 且 `sum(c['recommended'] for c in naming_candidates) == 1`。期望：全部满足。
- **Test A6**：顶层 `d['draft'] is True` 且每条 `phrase_draft is True`（= #DRAFT 标注）。期望：全部满足。

### Scenario B：情绪断言（AC3）
- **Test B1**：每条 `emotion` 非空且 `emotion_assertion` 含"价值极"或体验引擎词汇（安全感/破坏欲/掌控感/兴奋/支配感/敏捷快感 至少其一）。期望：9 条全部通过。
- **Test B2**：情绪断言与审美坐标（雨夜竞技场 + 克制优先）方向一致，无张扬/数值化断言。期望：9 条全部通过（review 人工比对）。

### Scenario C：机械完整性（AC4/AC5）
- **Test C1**：`grep -rn "够得着了\|火过留洞" mini-pong/gdscripts/` 为空（文案未硬编码进逻辑）。期望：空。
- **Test C2**：`git diff main...HEAD --stat` 仅含 `docs/PRD/395-*.md` 与 `mini-pong/assets/content/upgrade_pool.json`。期望：无 mini-pong/gdscripts/ 或 scenes/ 改动。
- **Test C3**：`godot --path mini-pong/ --headless --quit` 退出码 0（纯数据文件回归验证，证明运行时未被动）。期望：退出码 0。

### Scenario D：文案红线（边界 3/4，AC4）
- **Test D1**：`grep -E '[！!]|[😀-🙏]' mini-pong/assets/content/upgrade_pool.json` 为空（无感叹号/emoji）。期望：空。
- **Test D2**：短句/候选无网络梗、无形容词堆砌（对照 §2.2 表逐条比对）。期望：9 条全部通过（review 人工比对）。

### Scenario E：taste 方向对齐（review 定稿就绪检查，人工）
- **Test E1**：短句点价值极移动（安全感/破坏欲/掌控感…），说"手感变化"不说"数值变化"。期望：9 条全部通过。
- **Test E2**：雨夜意象渗透但不堆砌（雨/夜/霓虹/墙/洞/影/星/火 至少出现于部分短句/候选，且不做作）。期望：通过。

---

## 10. 验收标准映射（Issue 5 条 AC）

| AC | 本设计对应 | 验证方式 |
|----|-----------|---------|
| AC1 9 个升级各有 1 条中文短句（≤12 字） | §2.2 表 + §4 JSON 结构 | Test A2/A4 |
| AC2 每个升级至少 2 个命名候选，并标注推荐项 | §2.2 表"命名候选"列 + §4 schema | Test A5 |
| AC3 每条含 #DRAFT 与情绪断言 | §4 `draft:true` + `phrase_draft:true` + `emotion_assertion` | Test A3/A6 + B1 |
| AC4 文案不使用网络梗、emoji、感叹号 | §2.2 草稿 + §6 边界 4 | Test D1/D2 |
| AC5 所有文案放入独立 content 资源文件，不硬编码在逻辑节点 | §3.1 + §3.2 排除清单 | Test C1/C2 |

# 21 — Wave Failure Text（波次副句与失败短句）

> 草稿态单一事实源：`mini-pong/content/wave_failure_text.json`（`draft: true`，schema `wave-failure-text/v1`）。
> 本 GDD 章节记录**持久设计决策**（红线约束、数据流、schema 契约、审美锚点），不记录候选文案值
> （草稿值见 content JSON，用户定稿后可能变化；定稿差异回写 `docs/TASTE.md`）。
> 来源：Issue #396（B5 失败表达，人机共做 v4 taste-draft，2026-08-13，PR #407）。

## 1. 内容红线（海明威式克制短句）

| 约束 | 值 | 理由 |
|------|-----|------|
| 波次副句字数 | ≤ 15 字（含标点） | 波次转场「第 N 道墙」下方副句，屏显可读性 |
| 失败短句字数 | ≤ 10 字（含标点） | 失败屏短句，克制不喧宾夺主 |
| 感叹号 | 禁止（含全角 `！`） | 海明威式红线——失败不呐喊 |
| 形容词堆砌 | 每句修饰词 ≤ 1 | 陈述事实优先，不加渲染 |
| 惩罚性/空洞措辞 | 禁止（「你输了」「太弱了」「下次一定」） | 失败=叙事生产，不惩罚不敷衍鼓励 |
| emoji / 网络梗 | 禁止 | 保持文本密度与街机语境 |

## 2. 数据流（候选草稿 → 定稿 → 运行时消费）

```
PRD §4.2 候选清单（副句 4 × ≤15 字 × 语境 + 短句 4 × ≤10 字 × severity，各带情感断言 + 推荐标记）
    │
    ▼
mini-pong/content/wave_failure_text.json（schema wave-failure-text/v1 + draft: true + recommended）← B5 校准接口
    │  review 定稿就绪检查（结构 + taste 对齐）→ merge（草稿不关闭 Issue，PR 用 Parent #N）
    ▼
用户定稿（status/human-review 队列，Assigned to me）：选 1 / 微调 → close Issue
    │
    ▼
运行时消费：#390 波次转场读 wave_subtitles[].text（按 wave_index 分档）
              #391 失败屏读 failure_phrases[].text（按 run 数据 severity 分档）
    │
    ▼
定稿差异回写 docs/TASTE.md 风格特征节（B5 行：删形容词、雨意象）→ 下次草稿朝此方向
```

> 流程状态：**草稿已合并（2026-08-13，PR #407），待用户定稿**（Issue #396 open，`status/human-review`）。
> 机械插槽（波次转场 UI / 失败屏 UI）由 #390/#391 实现，本数据流不依赖草稿文案值。

## 3. schema 契约（消费方协议，wave-failure-text/v1）

```json
{
  "schema": "wave-failure-text/v1",
  "draft": true,
  "wave_subtitles":  [ { "id", "text", "context", "emotion", "recommended" } ],
  "failure_phrases": [ { "id", "text", "context", "emotion", "recommended" } ]
}
```

| 字段 | 语义 | 消费方 |
|------|------|--------|
| `schema` | 版本化契约（`wave-failure-text/v1`） | review / 校验器 |
| `draft` | `true` = 草稿态（JSON 无注释语法的 `# DRAFT` 标记） | review / 定稿流程 |
| `wave_subtitles[]` | 波次副句候选组（≥3 条）；`context` = 适用波次区间 | #390 波次转场按 wave_index 分档读 `text` |
| `failure_phrases[]` | 失败短句候选组（≥3 条）；`context` = 失败 severity 分档 | #391 失败屏按 run 数据分档读 `text` |
| `id` | 稳定标识（ws1-4 / fp1-4），定稿后不变 | 跨版本追踪 |
| `recommended` | research 建议标记（每组 1 条 `true`），用户可改选 | 定稿决策辅助 |

## 4. 审美坐标锚点（B5 失败表达）

| 坐标 | 来源 | 对文案的要求 |
|------|------|-------------|
| 失败=叙事生产 | B5 领域（#396 PRD） | 失败句不惩罚不鼓励，让世界照常运转（空洞骑士式沉默） |
| 雨意象 | #396 PRD §2（雨量系统 = f(波次) 同构） | 副句/短句以「雨」为统一意象载体，与雨量机制互文 |
| 文学性克制 | 极乐迪斯科式语法（#396 PRD） | 「就差一道墙」式只差一线的悔意，用进程量化，零形容词 |
| 街机利落感 | #289 / #367（TASTE.md §1） | 短句有击打感（动词驱动：「盖过」「拆到」），不绕弯 |

## 5. 文件所有权

| 文件 | 职责 | 谁写 |
|------|------|------|
| `mini-pong/content/wave_failure_text.json` | 草稿候选清单单一事实源（draft: true + recommended） | agent 起草，用户定稿 |
| #390 波次转场（`wave_subtitles[].text`） | 运行时消费：按 wave_index 分档 | 待 #390 实现 |
| #391 失败屏（`failure_phrases[].text`） | 运行时消费：按 severity 分档 | 待 #391 实现 |
| `docs/TASTE.md` 风格特征节 | 定稿差异回写（反馈闭环） | 用户定稿后回写 |
| 本 GDD 章节 | 持久红线/数据流/schema 契约 | review agent（post-merge） |

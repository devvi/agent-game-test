# GDD Orphan — Post-Merge Gap After 方案 X (2026-08-19, #562/#566)

> ✅ **已修复（2026-08-19 当天）**：用户拍板"走 docs PR"→ post-merge 阶段落地
> （eabb294/0f18c45/cab7123）——merge 事件 → `SPAWN: post-merge` → game-post-merge-agent
> 写 GDD/PROJECT.md → `docs/gdd-<N>` 分支 PR → stalled scan 自动 merge → status=done。
> **#567 全链路实证通过**（research#568→plan#569→impl#570→merge→SPAWN→docs#571→GDD
> 落盘→done→issue 自动关闭）。机制细节见 `game-post-merge-agent` skill + ARCHITECTURE.md
> 「Post-Merge 阶段」章节。以下为当时的证据链（历史记录，保留备查）。

> 症状：PR merge 后 `docs/GAME_DESIGN/<GAME_DIR>/` 没有新章节。用户问"gdd为什么没写？"。
> 根因不是 review agent 偷懒——是架构变更后责任掉进空洞。本文件是完整证据链 + 诊断方法。

## 时间线（shandong-wolf，2026-08-19）

| 时刻 | 事件 |
|------|------|
| 01:28 | commit 75a057a 创建 `docs/GAME_DESIGN/shandong-wolf/INDEX.md` 空壳，注明"首个 implement PR merge 后填充章节" |
| 02:22 | #562 review agent 派发（deleg_xxx，E2E failed 触发的 review） |
| 02:25 | #562 结论写完：`verdict=APPROVE/MERGE`（复合值 → 触发 verdict 归一化死锁，4d0183c 修复） |
| 10:54 | #562 merged（`_try_merge` 脚本层，滞后 8.5h） |
| 11:54 | #563 测试：566.json 骨架预生成（verdict=null，P2 生效）；review agent 派发（deleg_7d2e591a） |
| 11:57 | #566 review agent 结束（18 API calls，exit=completed），结论 approved + PR comment |
| 11:58-12:01 | `_try_merge` merge #566（一次假阴性后自愈） |
| 之后 | **两个 PR 都没有 GDD 更新；无任何告警** |

## 证据链

### 1. #566 review agent 干得完整但范围止于结论文件
deleg_7d2e591a（会话 20260819_115424_fc361d，18 calls）summary："做了什么：加载 game-review-agent skill 并按协议走完：PR 状态 → CI → E2E → 代码审查 → DESIGN 对照 → **结论文件 → PR comment**"。
清单里没有 GDD——派发 goal 明说"本任务只审查并写结论，不 merge"，post-merge 被合理视为范围外。

### 2. #562 review agent 明确 handoff，但目标没有这一步
#562 结论原文："由 operator/父代理执行 `gh pr merge 562 --squash --delete-branch`, 随后按 skill 走 post-merge 流程（GDD 写 docs/GAME_DESIGN/shandong-wolf/ + PROJECT.md + 通知 + board sync）"。
父代理（cron LLM）只执行脚本指令（SPAWN/STALLED/BLOCKED/FOLLOWUP），**没有 GDD 步骤** → handoff 掉进空洞。

### 3. 脚本层零 GDD
```bash
grep -n "GDD\|GAME_DESIGN\|gdd" scripts/event-processor.py scripts/workflow-dispatcher.py  # 零命中
```
`review_followup` 只做：approved→`_try_merge`；blocked→label+fix issue；未知 verdict→保留文件告警。无 GDD/PROJECT.md/Feishu/board。

### 4. 无监控
watchdog 只看 review-stuck / verdict-unknown；`e2e-state=reviewed` 把 PR 标记终态 → 管线认为已完整处理。GDD 缺失静默。

## 根因链

```
方案 X (2026-08-17): merge 从 review agent 移到脚本层 (review_followup/_try_merge)
  → review 会话终止点 = 写结论文件 (exit_reason=completed)
  → merge 发生在 review 会话结束后的下一个 cron tick
  → review 会话期间 PR 尚未 merge，"post-merge GDD" 物理上不可执行
  → merge 后无机制再唤醒 agent 写 GDD
  → skill 的 Post-Merge 章节 = 死代码；GDD 更新 = 无主责任 (orphan)
```

旧设计：review agent 同一会话 `gh pr merge` → 立刻写 GDD（原子绑定）。方案 X 拆开后没把 GDD 绑定到新的事件链上。

## 修复方向（设计，待用户拍板）

**把 post-merge 责任绑定到 merge 事件**：`_try_merge` 成功（approved→merged）后 emit `SPAWN: gdd-update,pr=N` → cron LLM delegate 轻量 GDD updater agent（读 DESIGN + merge 后 main → 写 GDD/PROJECT.md → Feishu → board sync）。
- GDD 写作归 LLM（判断+叙事），触发归脚本（确定性）——符合"LLM 只做判定，机械归脚本"铁律
- 不依赖 review 会话"记得做"；review 会话的职责收敛为纯判定

否决的方案：
- review agent 写结论前"预写 GDD"（基于 PR diff 而非 merge 后 main 状态；与 taste-draft 定稿语义冲突）
- 人工盯（违背"机械操作永不做 worker"）

## 诊断方法：delegated agent 取证

回答"为什么 X 没做"时，**读 `~/.hermes/state.db` 的 `async_delegations` 表**——`result_json` 含完整 summary（做了什么/产出/发现）+ `api_calls` + `tool_trace`，比 messages 表完整：

```bash
# 1. 找 review 会话的 delegation 记录（按 delegation_id 或时间窗）
sqlite3 -header ~/.hermes/state.db "SELECT delegation_id, state, datetime(dispatched_at,'unixepoch','localtime'), datetime(completed_at,'unixepoch','localtime'), substr(result_json,1,300) FROM async_delegations WHERE dispatched_at > strftime('%s','2026-08-19 11:53:00') ORDER BY dispatched_at;"

# 2. 看子代理会话（messages 表可能只有开头几条——会话记录可能不完整，以 result_json 为准）
sqlite3 -header ~/.hermes/state.db "SELECT id, source, end_reason, tool_call_count, datetime(started_at,'unixepoch','localtime') FROM sessions WHERE source='subagent' ORDER BY started_at DESC LIMIT 5;"

# 3. 对照: git log docs/GAME_DESIGN/ 的最近提交 vs PR mergedAt
git log --oneline -10 -- docs/GAME_DESIGN/
gh pr view <N> --json mergedAt --jq '.mergedAt'
```

⚠️ 注意：`gh pr view --json comments` 只返回 issue-style comments，**不含 review comments**——查 review comment 用 `--json reviews`（state=COMMENTED/APPROVED）。

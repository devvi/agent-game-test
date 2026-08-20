# Workflow 开发蓝图（Roadmap）

> 记录**待全局设计/开发**的鲁棒性专项队列。现状问题记录在 `framework/ARCHITECTURE.md`「已知限制」；
> 本文件是"要动手做"的队列——每项先记录证据与影响（不急着修），**全局设计评审通过后再开发**。
>
> 状态流转：`待设计` → `设计中` → `已落地`。每个专项独立评审，不批量开工。

---

## 专项队列

### R1. API 超时鲁棒性（2026-08-19 列入，状态：待设计）

**为什么列入**：cron LLM 调用 API 超时是 workflow 面临的主要鲁棒性问题之一——SPAWN 指令被吞后管线静默卡死，需要人工恢复。

**现象**：
- cron 会话 `TimeoutError: Cron job 'godot-workflow-poller' idle for 301s (limit 300s) — last activity: waiting for non-streaming API response`
- SPAWN 已输出到会话 prompt，但 LLM 会话被强杀 → delegate 未执行 → 指令丢失

**证据**（2026-08-19 实弹）：
- 11:15 / 11:22 cron 会话超时，`#563` research SPAWN 两次被吞
- 当天 4 次 cron 会话超时（`grep -l TimeoutError ~/.hermes/cron/output/83fee8577195/*.md | wc -l` = 4）
- API 瞬时故障（探测 200/0.05s）→ 无法预判，只能事后恢复

**影响链**：
```
cron LLM API 超时（>300s idle）→ 会话强杀 → SPAWN 收到未执行
→ spawn gate 已写（TTL 90min）→ 管线静默卡死
→ 人工删 gate（~/.hermes/.spawned-state.json 删条目）→ cron 重试
```

**现状缓解**（治标，已存在）：
- SPAWN 吞没恢复 = 删 spawned gate 条目（记忆/运维操作）
- workflow-watchdog silent-spawn 检测（告警，不自动恢复）
- 手动跑 event-processor 会消耗 gate（**运维红线**：创建 issue 后不得手动跑/手动推进，让 workflow 自动跑——2026-08-19 用户明确）

**设计方向（待评审，不在此实现）**：
1. **LLM 调用层超时重试/退避**：非流式超时 → 指数退避重试 N 次；或切换流式
2. **SPAWN 持久化 + ACK 确认**：cron 执行 SPAWN 后回写 ACK；未 ACK 的 SPAWN 由 event-processor/watchdog 自动重发（替代"删 gate"人工恢复）
3. **执行与调度状态解耦**：gate 写入时机从"SPAWN 输出"改为"SPAWN 已执行/已 ACK"（当前 SPAWN 输出即写 gate，执行失败也锁 90min）
4. **降级路径**：API 持续不健康 → 自动暂停调度（如 BLOCKED 告警）而非反复吞指令

**验收设想（设计时确认）**：任何一次 LLM 调用失败都不丢失 SPAWN；管线最长恢复时间从"人工发现+删 gate"降到"自动 <1 tick"。

---

### R2. 同 tick skip+SPAWN 并存 → cron LLM 歧义吞 SPAWN（2026-08-20 列入，状态：待设计）

**为什么列入**：R1 是"LLM 调用失败"吞 SPAWN；R2 是"LLM 正常但指令自相矛盾"吞 SPAWN——同一 tick 内 `[DEV] skip ... gate-ttl` 与 `SPAWN: ...` 并存，LLM 解读为"已被 gate 跳过"而回复 [SILENT]。

**现象**：
```
[DEV] spawn issue=579 stage=research source=available-rescan   ← 路径 A 通过（gate 记录+label 推进）
[DEV] skip issue=579 stage=research reason=gate-ttl ttl_left=5393  ← 路径 B 再次调用 gate → skip
SPAWN: research,issue=579,label=workflow/research,game=shandong-wolf
```
cron LLM 看到 skip 行 → 判定 SPAWN 无效 → `[SILENT]`，无 delegate。

**根因**：同一 tick 内多个路径（preprocess 事件路径 / backlog-promotion / available-rescan）先后调用 `_spawn_gate(issue, stage)`——第一个通过并输出 SPAWN，后续调用因 gate 刚写入而打印 skip。skip 日志与 SPAWN 并存进入 LLM prompt。

**证据**（2026-08-20 实弹）：#579 在 13:12:28 tick 输出上述三行 → cron session `cron_..._131130` 回复 [SILENT] → research agent 未启动（后续手动 delegate 解卡）。

**影响链**（比 R1 更糟）：
```
同 tick skip+SPAWN 并存 → LLM 歧义 [SILENT]
→ SPAWN 未执行 + label 已推进 (available→research)
→ available-rescan 不再认该 issue（只扫 available label）
→ 删 gate 也无法恢复（label 已推进）→ 需改 label 回 available + 删 gate 双操作
```

**设计方向（待评审）**：
1. **tick 级 spawn 去重日志**：本 tick 已为 (issue, stage) 输出 SPAWN → 后续 `_spawn_gate` 调用静默（不打印 skip）
2. **label 推进时机后移**：SPAWN 输出时仅记录 gate，label 推进改为"agent 确认启动/ACK"后（需跨进程确认，R1 方向 2/3 配套）
3. **research-rescan 兜底**：`workflow/research` label + 无 research PR + gate 过期 → 自动重发（与 available-rescan 并列）——让任何吞没路径都自愈

---

### R3. blocked 半解除 + e2e reviewed 终态 → 静默死角（2026-08-20 列入，状态：待设计）

**为什么列入**：fix issue merge 后 PR 的 `status/blocked` 被移除，但 parent issue 的残留；同时 e2e-state 终态 `reviewed`（旧 sha）让 stalled scan 永远静默、分支 stale 无人 update → issue 卡死且无任何机制恢复。

**现象**（#582/#613 实弹）：
```
15:44  review 判 B 类 → PR #613 + issue #582 打 status/blocked → fix issue #624
17:42  fix PR #629 merge → 17:58 PR #613 的 blocked 被移除 ✓
      但 issue #582 的 status/blocked 残留 ✗（无人清理）
      e2e-state/613.json = {status: reviewed, sha: 旧} → stalled scan 对 #613 静默
      #613 分支 stale（不含 fix）→ CI 不重跑 → fresh_ci 不触发 → 新 review 轮永不开始
```

**影响**：issue 永远卡 `workflow/implement + status/blocked`；恢复需人工三连（移除 issue blocked + update-branch + 重置 e2e-state）。

**设计方向（待评审）**：
1. **blocked 解除双向清理**：unblock 逻辑同时移除 PR 与 parent issue 的 `status/blocked`
2. **e2e reviewed 终态失效检测**：分支 head 变化（新 commit / update-branch）→ reviewed 终态自动重置（fresh_ci 已覆盖事件路径，需补"状态对比"兜底：e2e-state 记录 sha，发现 head ≠ sha 且非 running → 重置 absent）
3. **stale impl PR 自动 update-branch**：stalled scan 检测 impl PR head 落后 main（mergeable 或 API 对比）→ 自动 `gh pr update-branch`（或发 STALLED: update-branch 指令）

---

## 观察区（候选，未正式列入）

- webhook 链路 5 故障点（ngrok→gateway→route script）——已有 reconcile_check_runs 兜底
- 单机依赖（本地 E2E 依赖 Mac mini 在线 + UURemote）——记录于 ARCHITECTURE 已知限制
- 多仓库 pending 事件（Patch 54）——单仓库假设

---

*维护规则：新专项 = 附证据与影响链，标注"待设计"；全局设计评审通过后移入开发。*

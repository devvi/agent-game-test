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

**证据**（2026-08-20 实弹）：
- #579 在 13:12:28 tick 输出上述三行 → cron session `cron_..._131130` 回复 [SILENT] → research agent 未启动（后续手动 delegate 解卡）。
- #583 同日 14:17:37 同款 skip+SPAWN 并存（backlog-promotion 路径 + webhook 路径先后调 gate）→ 叠加 R6 provider 故障 → SPAWN 吞没后卡 `workflow/research`（2026-08-20 恢复实录，见 R6）。

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

### R4. Cron LLM 深挖阻塞 poller（2026-08-20 列入，状态：待设计）

**为什么列入**：cron session（deepseek-v4-flash）收到指令后深挖源码/调查 10-17 分钟，期间 scheduler 对同一 job 串行（`already running — skipping`）→ 所有 tick 停摆，SPAWN/E2E 收割全延迟。

**现象**：
- 00:44:05 session 处理 `STALLED: check-self-correct pr=627` → 深挖 17 分钟（01:01:04 结束），期间 tick 全 skip
- 13:58:29 session 同款深挖 7 分钟（读 #613 分支 commits + reconcile 源码）后才 delegate review

**证据**：scheduler 日志 `Job 'godot-workflow-poller' already running — skipping`（00:47-01:00 连续 8 次；13:59-14:00 连续 2 次）。

**影响**：tick 停摆期间：E2E 收割延迟、SPAWN 延迟、watchdog 告警误报（626 verdict null 与 cron 阻塞叠加）。

**设计方向（待评审）**：
1. **cron prompt 强化**：指令执行加"单指令 ≤N 次工具调用 / ≤5 分钟"约束，超限直接按 skill 协议的最小动作收尾（delegate 或写文件）
2. **scheduler 并行**：同 job 前一个 session 超时（>10min）→ 允许下一个 tick 并行（spawn gate 已有防重）
3. **模型路由**：poller 用更快/更听话的模型（如 flash 换 non-reasoning 短模型），深挖型调查归 watchdog 人工

---

### R5. research/plan PR 写 "Closes #N" → issue 误关且 reopen 无效（2026-08-20 列入，状态：待设计）

**为什么列入**：research/plan 阶段 PR body 含 `Closes #N` → merge 时 GitHub 原生 close issue → 后续阶段（plan/implement）无法 spawn（picker 只认 open）→ 且 **reopen 无效**：GitHub 对 merged PR 的 "Closes" 引用在 issue reopen 后确定性重新应用（实测 3 次，9-15 秒内 re-close）。

**现象**：
```
PR #641（research/579）body: "parent #579" + "Closes #579"
→ merge（05:24:48Z）→ GitHub 原生 close #579（05:24:50Z）
→ 任何 reopen（3 次实测：13:55/14:10/14:18）→ 9-15 秒后被 GitHub re-close
   （伴随 main 分支 push 事件重放：sync job queued, head=#641 merge commit）
```

**根因**：`game-research-agent` 认为 "Body 含 parent #N + Closes #N（符合项目大小写约定）" 是正确做法——**错误**：research/plan 阶段不该 close（只有 implement 完成/status/done 才 close）。Closes 语义与 workflow-chain 的 label 推进机制冲突。

**影响**：#579 全阶段需手动 spawn（plan/implement）；任何 research/plan PR 误写 Closes 都会制造同类断链。

**设计方向（待评审）**：
1. **skill 红线**：`game-research-agent` / `game-plan-agent` PR body 禁止 `Closes/Fixes/Resolves #N`，只允许 `Parent #N`（关闭语义归 workflow-chain/status-done）
2. **stage-gate.py 校验**：research/plan PR body 含 Closes 关键词 → 自动移除 + 告警
3. **watchdog 检测**：`workflow/plan`/`workflow/implement` label + issue closed = 异常状态 → 告警（防静默断链）

---

### R6. 模型 provider 配置事故 → poller 连续失败 → SPAWN/post-merge 吞没（2026-08-20 列入，状态：待设计）

**为什么列入**：临时切换默认模型/provider（如 GLM key 试验）期间，poller 的 LLM 调用连续失败（400 modelCode 不存在 / 429 余额不足）→ cron job 反复 failed → 已发出的 SPAWN 无人执行。research 阶段 issue 卡死（`workflow/research` 无 rescan 兜底，同 R2 方向 3），post-merge one-shot 丢失（pending+emitted_at 不重发，仅 watchdog 告警）。**与 R1（API 超时）/R2（LLM 歧义）触发源不同：这是配置事故，失败是确定性的、持续的。**

**现象**（2026-08-20 实弹 #583/#613）：
```
14:13  用户给 GLM key 设为默认 → model.base_url 切 api.z.ai, model 仍是 deepseek-v4-flash
14:17:37  SPAWN research #583 (backlog-promotion) + 14:17:42 post-merge #613 同时发出
14:17-14:25  poller 连续失败: HTTP 400 modelCode does not exist (z.ai 网关不认 deepseek model code)
14:29  短暂切 glm-5.3 @ open.bigmodel.cn → HTTP 429 余额不足 → credential pool 耗尽
14:31  配置恢复 coconut (glm-key-expiry-switchback.sh), 但 SPAWN 已被吞:
       #583 卡 workflow/research — available-rescan 只扫 workflow/available → 无恢复路径
       #613 post-merge pending+emitted_at — one-shot 已消费 → 不重发
15:07/16:07  watchdog post-merge-stuck 告警 2 次 (只告警, 不自动恢复)
16:55  人工解卡: #583 label→workflow/available (触发 available-rescan + dead_spawn_recovery)
       + 清 613.json emitted_at (触发 post_merge_emitter 重发) → 恢复
```

**根因**：
1. **cron job 配置跟随全局**：poller 的 provider/model 未 pin（受 model.default / base_url 全局切换影响），配置事故直接打穿调度层
2. **无失败熔断**：连续 400/429 无告警无暂停，SPAWN 在故障窗口内持续被吞
3. **workflow/research 无恢复兜底**（同 R2 方向 3，第二次实证）：label 已推进 → available-rescan 不认
4. **post-merge 无自动重发**：pending+emitted_at 的 one-shot 语义无超时重置，只能人工清

**设计方向（待评审）**：
1. **cron job 配置 pin**：poller 的 model/provider 固定 `custom:coco`（deepseek-v4-flash），不受全局 model.default/base_url 切换影响（job 创建时已记录 provider，但需验证是否真正 pin 生效）
2. **失败熔断**：cron job 连续 N 次 LLM 失败（400/429/超时）→ Feishu 告警 + 自动暂停调度（防 SPAWN 反复被吞），配置恢复后 `/workflow resume`
3. **research-rescan 兜底**（并入 R2 方向 3）：`workflow/research` + 无 research PR + gate 过期 → 自动重发，覆盖所有"SPAWN 未执行"吞没路径
4. **post-merge 超时重置**：pending+emitted_at 超时（如 2×POST_MERGE_TIMEOUT）→ 自动重置 emitted_at 重发（或 watchdog 直接重置并告警）

---

### R7. SPAWN 输出后 cron session 未启动（系统资源耗尽）→ 指令永久丢失（2026-08-21 列入，状态：待设计）

**为什么列入**：R1 是"LLM 调用失败"、R2 是"LLM 歧义"、R6 是"provider 故障"吞 SPAWN——本次是**第四变体：SPAWN 输出后消费它的 cron session 因系统资源耗尽从未启动**。SPAWN 一次性无 ACK，丢失后无任何自愈路径，8.5 小时死等。

**现象**（2026-08-21 实弹）：
```
01:13-01:25   #661 implement + 用户 feishu 会话 + cron 多 session 并行 → FD/资源压力
01:22:19-27  [Errno 24] Too many open files（webhook 脚本执行失败 ×7）
01:22:29     socket.accept() out of system resource（asyncio 资源耗尽）
01:22:44     event-processor 输出 SPAWN: research,issue=681/682/683（spawn gate 写入）
             → 01:22 tick 的 cron LLM session 启动失败（资源耗尽）→ SPAWN 未消费
01:23:56     资源恢复，下个 cron session 启动 → 脚本输出已无 SPAWN（一次性不重发）
             → 返回 [SILENT] → 681/682/683 卡 workflow/research 死等 8.5 小时
```

**根因**：
1. **SPAWN 一次性 + 无 ACK/重试**：event-processor 输出 SPAWN 即写入 spawn gate——消费它的 session 未启动/崩溃 → 指令永久丢失（后续 tick 不重发）
2. **资源耗尽无保护**：多 session 并行（implement + 用户会话 + cron）→ FD 耗尽 → cron session 启动静默失败（仅 agent.log 有 ERROR 记录，无告警）
3. **stalled scan 盲区**：只查"PR merge 卡住"（merge-pr），不查"SPAWN 输出后无 agent 启动"

**影响链**：
```
资源耗尽 → cron session 未启动 → SPAWN 未消费 → label 已推进 research
→ available-rescan 不认（非 available）→ 死等 8.5h
→ 人工恢复：移回 backlog + 重新 pick（第三次人工解卡，前两次见 R2/R6）
```

**设计方向（待评审）**（与 R2 方向 3 合并为通用解）：
1. **SPAWN 消费 ACK + 超时重发**：SPAWN 输出落盘（指令队列）→ 消费（delegation 创建）后标记 → 超时（如 5min）未 ACK → 自动重发（cron 或 watchdog）
2. **research-rescan 兜底**（R2 方向 3，第三次实证）：`workflow/research` + 无 research PR + gate 过期 → 自动重发
3. **资源耗尽熔断**：watchdog 检测 FD/内存水位 → Feishu 告警 + 暂停 cron（防 session 启动失败窗口期吞指令）
4. **恢复工具化**：人工恢复操作（issue 移回 backlog 触发重新 pick）封装为脚本/命令，降低手工操作风险

**本次恢复实录**（2026-08-21 11:00）：681/682/683 移回 workflow/backlog → picker 重新 pick（backlog-promotion）→ SPAWN 重发（11:00:51）→ cron session 正常消费（API 98.4s 慢但成功）→ research agent 启动。恢复链路本身工作正常，缺口在"检测 + 自动重发"。

---

## 观察区（候选，未正式列入）

- webhook 链路 5 故障点（ngrok→gateway→route script）——已有 reconcile_check_runs 兜底
- 单机依赖（本地 E2E 依赖 Mac mini 在线 + UURemote）——记录于 ARCHITECTURE 已知限制
- 多仓库 pending 事件（Patch 54）——单仓库假设

---

*维护规则：新专项 = 附证据与影响链，标注"待设计"；全局设计评审通过后移入开发。*

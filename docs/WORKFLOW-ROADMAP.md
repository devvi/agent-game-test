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

## 观察区（候选，未正式列入）

- webhook 链路 5 故障点（ngrok→gateway→route script）——已有 reconcile_check_runs 兜底
- 单机依赖（本地 E2E 依赖 Mac mini 在线 + UURemote）——记录于 ARCHITECTURE 已知限制
- 多仓库 pending 事件（Patch 54）——单仓库假设

---

*维护规则：新专项 = 附证据与影响链，标注"待设计"；全局设计评审通过后移入开发。*

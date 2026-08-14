# Kanban 重构基线快照 (2026-08-14 17:11)

## 目的
记录 kanban 迁移开始时的 pipeline 状态,用于验证迁移后行为不变。

## 当前 pipeline 状态(自动流动中)
| Issue | 状态 | 说明 |
|-------|------|------|
| #466 | OPEN + workflow/implement | 目标 issue(视觉回归 E2E) |
| #475 | OPEN + workflow/implement | #466 的 impl PR,E2E PASS,review 待触发 |
| #480 | OPEN + workflow/implement | runner fix issue(research #483 + plan #484 已 merge) |

## 当前架构(待替换)
```
GitHub webhook → workflow-dispatcher.py → pending 文件
cron tick → event-processor.py(脚本) → SPAWN/STALLED 文本
  → cron LLM(读文本 → delegate_task)→ subagent
```

## 已知脆弱点(kanban 将替代)
1. SPAWN 文本被 cron 吞 → gate 锁 1h → dead-spawn recovery/resend 补丁
2. cron 串行,tick 5-12 分钟
3. async_delegation 完成通知路由丢失
4. 50-call 截断漏收尾(结论文件补丁)
5. worktree 残留孤儿

## 测试基线
tests/pipeline: 158 tests OK

## 迁移目标
```
event-processor(脚本,判定逻辑保留)→ kanban create(task)
→ kanban dispatcher(确定性)→ Popen hermes chat -q worker
→ worker 加载 game-*-agent skill → 完成 → kanban complete
```

## 不可干预红线
迁移期间不手动 spawn/delegate/merge,让 pipeline 自然跑。

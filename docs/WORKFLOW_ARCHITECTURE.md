# Workflow 系统流程图

## 1. 顶层架构

```
                   ┌──────────────────────┐
                   │     用户提交 Issue     │
                   │  (workflow/backlog)    │
                   └──────────┬───────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │    Cron: godot-workflow-poller  │
              │    (every 1 minute)             │
              └───────────────┬───────────────┘
                              │
              ┌───────────────▼───────────────┐
              │   Phase 1: event-processor.py  │
              │   （确定性脚本，5-15秒）         │
              │                              │
              │   ① 读取 pending.json         │
              │   ② reconcile（缓存）         │
              │   ③ picker (backlog→research) │
              │   ④ preprocess（去重/排序）    │
              │   ⑤ 输出 SPAWN 指令            │
              └───────────────┬───────────────┘
                              │ stdout
                              ▼
              ┌───────────────────────────────┐
              │   Phase 2: LLM Agent           │
              │   （dev-workflow-dispatcher）   │
              │                              │
              │   读取 SPAWN 指令              │
              │   delegate_task → Phase Agent  │
              └───────────────────────────────┘
```

## 2. 事件流（Event Flow）

```
GitHub Event ───→ Webhook ───→ Gateway (:8644)
                                   │
                                   ▼
                         route-script.py
                         (thin, 5ms)
                                   │
                                   ▼
                         pending.json
                         (累积事件)
                                   │
                          (cron 1min)
                                   ▼
                    event-processor.py
                          │
                    ┌─────┴──────┐
                    │            │
                    ▼            ▼
                P1/SPAWN      [NO_ACTIONABLE]
                (LLM 消费)     (stalled scan)
```

## 3. Issue 生命周期

```
workflow/backlog
       │
       │ pick_next_issue()（cron 自动）
       ▼
workflow/research
       │
       │ delegate_task → research agent
       │   → 读 Issue → 探索代码/Obsidian → 写 PRD → research/ PR
       │   → CI → review agent → merge → workflow-chain 推进
       ▼
workflow/plan
       │
       │ delegate_task → plan agent
       │   → 读 PRD → 写 DESIGN → plan/ PR
       │   → CI → review agent → merge → workflow-chain 推进
       ▼
workflow/implement
       │
       │ delegate_task → implement agent (OpenCode)
       │   → 读 DESIGN + 代码 → 实现 → impl/ PR
       │   → CI → check_run.completed ──→ review agent
       │                                    │
       │                          ┌─────────┴─────────┐
       │                          │                   │
       │                     审查通过               审查拒绝
       │                          │                   │
       │              ┌───────────┴─────────┐         │
       │              │                     │         │
       │         mechanical            taste-draft   workflow/self-correct
       │              │                     │         │
       ▼              ▼                     ▼
    gh pr merge    status/done       草稿 merge（PR 用 Parent #N 不写 Closes）
    (合并到 main)                      → assign 用户 + status/human-review
       │                                 → 用户 close = 定稿（不进依赖链）
       │ workflow-chain.yml（PR closed 事件触发）
       ▼
  status/done + close issue
```

## 4. 组件依赖

```
┌──────────────────────────────────────────────────────────┐
│                 Hermes Agent 内部                          │
│                                                          │
│  cronjob (godot-workflow-poller)                          │
│    ├── script: event-processor.py                        │
│    │   ├── gh() cache + TTL (30s)                        │
│    │   ├── _ensure_issues_cache() (全量缓存)              │
│    │   ├── pick_next_issue() → SPAWN                     │
│    │   ├── preprocess() → P1/P2                          │
│    │   └── reconcile() (crash recovery)                  │
│    └── LLM: dev-workflow-dispatcher skill                 │
│        ├── 消费 SPAWN → delegate_task                    │
│        └── stalled scan（空闲时兜底检查）                  │
│                                                          │
│  cronjob (webhook-sync)                                   │
│    └── 每15分钟同步 ngrok URL 到 GitHub webhook 配置      │
│                                                          │
│  cronjob (workflow-silent-spawn-watchdog)                 │
│    └── 每5分钟沉默 SPAWN 检测 → Feishu 告警 (no-agent)   │
│                                                          │
│  gateway (:8644)                                         │
│    └── 接收 webhook → route-script → pending.json        │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│                 GitHub 外部                                │
│                                                          │
│  GitHub Issues（label 驱动）                               │
│  GitHub Actions（CI/CD）                                  │
│    ├── opencode-review.yml（Godot 编译+测试）             │
│    └── workflow-chain.yml（PR merge → label 推进+close）  │
│  OpenCode Serve (:18765)                                 │
│    └── implement agent 的代码生成引擎                     │
└──────────────────────────────────────────────────────────┘
```

## 5. 关键的确定性规则

```
1. event-processor.py 不做任何 git 操作
   （不创建 branch，不写文件，不 commit，不 merge）

2. event-processor.py 只读 GitHub API（通过 gh() 缓存）
   + 写 pending.json（atomic write）
   + 输出 SPAWN 指令到 stdout

3. Agent 层（research/plan/implement/review）
   全权负责 git 操作和代码生成
   
4. Review agent 是合入前的最后一道关卡
   - 必须审查 PR 内容
   - 必须留 review comment
   - 只有 review agent 可以 merge impl/* PR

5. workflow-chain.yml 是合入后的 label 推进
   - 不审内容
   - 只根据 PR branch 前缀推进 Issue label
   - PR→research→plan→implement→status/done
```

## 6. 失败路径

```
┌─ SPAWN 未被消费 ───────────────────────────────────────┐
│  原因: LLM 超时 / token 耗尽 / delegate_task 失败        │
│  解决: 修 LLM 消费路径（delegate_task/model/provider）    │
│  禁止: ❌ 绕过 LLM 写死模板（我之前的错误）              │
└─────────────────────────────────────────────────────────┘

┌─ CI check_run.completed 未被处理 ──────────────────────┐
│  原因: webhook 丢失 / pending 未写入 / 窗口关闭          │
│  解决: 检查 webhook 历史 / gateway 日志 / cron 输出      │
└─────────────────────────────────────────────────────────┘

┌─ PR 冲突 ──────────────────────────────────────────────┐
│  stalled scan 兜底: merge main → resolve → push        │
│  阈值: ≤5 文件自动 / >10 升报                           │
└─────────────────────────────────────────────────────────┘

┌─ Agent 失控（任意代码/改 CI） ──────────────────────────┐
│  检测: review agent 必须 catch                         │
│  补救: revert PR → 修复 agent prompt                   │
└─────────────────────────────────────────────────────────┘
```

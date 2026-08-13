# 执行版：Workflow 事件驱动恢复（方案4 v2）

> **状态：** 待实施（等 #394 跑完后开工）
> **唯一执行依据：** 2026-08-13 会话的设计讨论 + 本文件。实施 job 严格按本文件执行，不自行发挥。
> **背景：** reconcile() 是"合成事件发生器"，把 GitHub 状态伪造为 webhook 事件塞进 pending 队列，无天然去重键，导致 2026-07-23 至今反复出 bug（2026-08-13 #393 单 issue 30 分钟 15 条 SPAWN）。方案4 v2 = 恢复事件驱动：调度器顺带直发 research、删除 reconcile 注入、stalled scan 上 gate 并感知 self-correct。

## 一、目标

1. **pending list 恢复为唯一事件主路径**（webhook 加速器，O(events)）
2. **删除 reconcile() 合成事件注入** + seen-state + 1h 重注入 + tick-gap 重置（整类"消费 vs 再生"冲突消失）
3. **调度器顺带直发 research**（promote 时 + 每 tick available 重扫，0 额外 API，复用缓存遍历）
4. **stalled scan 上 gate + self-correct 感知**（修 3b59ede 暴露的无 gate 每 tick review 重发隐患）
5. 全部 SPAWN/STALLED 行统一走 main() 的 lines 管道（槽位 cap + audit），不再 print 直出

## 二、变更清单

### 1. scripts/event-processor.py

#### 1.1 pick_next_issue() — 直发 research + available 重扫 + 返回行

- 函数签名改为**返回 list[str]**（SPAWN 行），不再 print。内部收集到 `spawn_lines`。
- promote 成功（`r1`/`r2` 均非空）后追加：
  ```python
  if _spawn_gate(n, "research"):
      spawn_lines.append(f"SPAWN: research,issue={n},label=workflow/research")
  ```
- 现有遍历循环（workflow/plan、workflow/implement → SPAWN）保留，逻辑不变，行 append 到 `spawn_lines`。
- **新增分支**（available 重扫，死 agent 恢复的确定性兜底）：
  ```python
  elif "workflow/available" in labels:
      if not _pr_exists_for_issue("research", n) and _spawn_gate(n, "research"):
          spawn_lines.append(f"SPAWN: research,issue={n},label=workflow/research")
  ```
- **删除注释**：`# Do NOT output SPAWN here — let webhook → pending → preprocess handle it`（2026-07-23 原罪：自我产生的状态变化绕道 webhook 回声）。
- `_pr_exists_for_issue`（3b59ede 已改为确定性客户端匹配）复用，不新增 API。

#### 1.2 删除 reconcile() 合成事件注入

删除以下（连同注释块）：
- `reconcile()` 函数
- `RECONCILE_LABEL_STATE_FILE` / `RECONCILE_REINJECT_AGE` / `RECONCILE_TICK_GAP_RESET`
- `_read_reconcile_label_state()` / `_write_reconcile_label_state()`

main() 中的调用点：
- 每 tick 的 `reconcile()` 调用 → 删除
- 窗口入口块（`was_outside`）：保留 `health_check()` + `pick_next_issue()`，删除 `reconcile()`

**保留**：`reconcile_check_runs()`（P3b，pr+sha 身份化对账，从未出过错）及其 state 文件、5-tick 节奏。

#### 1.3 _quick_stalled_scan() — gate + self-correct 感知

impl/* PR 分支改为：
```python
elif branch.startswith("impl/"):
    if "status/blocked" in labels:
        if _spawn_gate(pr_num, "unblock"):
            cmds.append(f"STALLED: check-unblock,pr={pr_num},branch={branch}")
    else:
        # self-correct 感知：parent 已被 review agent 打 workflow/self-correct
        # （本地 e2e 失败，CI 绿）→ 直达 self-correct，不再多跑一轮 review
        parent = _extract_parent_issue(pr_num)  # 复用 PR body 解析（无则 None）
        if parent:
            p_labels = _current_issue_labels(parent)  # 复用缓存/防御性
            if "workflow/self-correct" in p_labels:
                if _spawn_gate(pr_num, "self-correct"):
                    cmds.append(f"STALLED: check-self-correct,pr={pr_num},branch={branch}")
                continue
        if _spawn_gate(pr_num, "review"):
            cmds.append(f"STALLED: check-review,pr={pr_num},branch={branch}")
```
- parent 解析失败/无标签信息 → 保守走 review 分支（现有行为）。
- gate 是唯一去重：同一 PR 的 review/self-correct 每 TTL 只发一次。

#### 1.4 main() — 统一 lines 管道

- 顶部：`picker_lines = pick_next_issue()` → `lines = preprocess() + picker_lines` → 排序（SPAWN 在前，复用现有 sort）→ cap → audit → print。
- 底部 no-lines 分支：`picker_lines2 = pick_next_issue()`；`stalled = _quick_stalled_scan()`；输出合并（picker 行 + stalled 行，空则 [SILENT]）。
- `if any("status/done" in l ...)` 触发的第二次 picker 调用：同样收集行并入输出。

### 2. cron prompt（godot-workflow-poller, job 83fee8577195）

在 STALLED 指令区新增一行（**已在实施前由主会话更新，实施 job 无需动 cronjob**）：
```
STALLED: check-self-correct,pr=N → delegate_task self-correct,issue=<PR body Parent #N>,pr=N（review agent 本地 e2e 失败、parent 已打 workflow/self-correct；CI 可能全绿）
```

### 3. tests/pipeline/

- **删除**：`test_reconcile_injects_label_event_once`
- **新增**：
  - `test_picker_promote_emits_research_spawn` — promote 成功后直发 SPAWN: research，gate 记录
  - `test_picker_rescans_available_after_ttl` — available + 无 PR + gate 过期 → 重发（死 agent 恢复）
  - `test_picker_direct_and_webhook_echo_single_spawn` — 直发与 webhook 回声共用 gate，只发一次
  - `test_stalled_scan_gated` — 同一 impl PR 连续两次扫描只发一次 STALLED
  - `test_stalled_scan_self_correct_aware` — parent 有 workflow/self-correct → STALLED: check-self-correct（不发 check-review）
- 全量跑：`python3 -m unittest discover -s tests/pipeline`（预期 ~130 全绿）
- 测试约束：mock gh/subprocess，无网络；`_SPAWN_STATE_FILE` / `_GH_CACHE` 必须隔离（复用现有 helper 模式）

### 4. 文档

- `framework/ARCHITECTURE.md`：更新"webhook 链路 5 个故障点"的兜底描述：
  - label 事件丢失 → 调度器状态检测（available→research）+ stalled scan（self-correct）
  - check_run 丢失 → reconcile_check_runs（pr+sha）
  - 删除 reconcile() 相关描述
- `agents/skills/dev-workflow-dispatcher/SKILL.md`：reconcile 段改为"已删除（2026-08-13），替代机制：picker 直发 + stalled scan gate + self-correct 感知"

## 三、验证步骤

1. `python3 -m unittest discover -s tests/pipeline` 全绿（失败修到绿，最多 2 轮；仍失败则中止并报告，**不提交坏代码**）
2. `./scripts/sync-to-hermes.sh` + `cmp scripts/event-processor.py ~/.hermes/scripts/event-processor.py`
3. 干跑（只读，mock 输出）：`python3 -c` 调用 `pick_next_issue()` 与 `_quick_stalled_scan()` 确认输出形态
4. commit + push（message 固定：`fix(workflow): event-driven restore — picker direct research + delete reconcile + gated stalled scan`）
5. 若 push 被拒（main 前进）：`git pull --rebase origin main` 后重推

## 四、回滚

- `git revert <commit>` + `./scripts/sync-to-hermes.sh`（脚本与仓库必须同步）
- 回滚后监控一个完整 tick：audit 应回到 SPAWN 单发行为

## 五、遗留（本方案明确不做）

- workflow-chain.yml Action 自身失败（label 未推进）是另一故障类，不在本方案范围
- reconcile_check_runs 的 5-tick 节奏与 gate TTL 的关系：保持现状

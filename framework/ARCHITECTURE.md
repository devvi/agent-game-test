# framework/ARCHITECTURE.md — Godot Edition (Single Source of Truth)

> **本文档是 workflow 架构的单一事实源。** 所有 agent skill 中的架构描述必须与本文一致。
> 项目仓库: https://github.com/devvi/agent-game-test · 默认分支: **`main`**（不是 master）
> 最后更新: 2026-08-10（e2e 验证体系 + 金丝雀 #358 修复收敛）

## 系统概述

将游戏开发分解为五个 agent 阶段，由 GitHub 事件驱动 + cron 轮询兜底：

1. **Research** — 研究、PRD 生成（`docs/PRD/`）
2. **Plan** — 架构设计、测试用例描述（`docs/DESIGN/` + 可选 `docs/TASKS/`）
3. **Implement** — GDScript 代码生成（OpenCode，`impl/` 分支）
4. **Review** — 代码审查、合并决策（CI 成功后 pre-merge 触发，**不在 label 链中**）
5. **Self-correct** — CI 失败诊断修复（`workflow/self-correct` label）

## 运行时架构（2026-08-15 修订: 回滚 kanban, 恢复 SPAWN 文本 + cron LLM + devlog）

```
GitHub Event → Gateway webhook (:8644)
  → workflow-dispatcher.py (thin route script — 只写 pending 文件, 不做 gh/git)
  → ~/.hermes/workflow-pending.json (~0.3KB/event, 不含 payload)
  → cron tick (godot-workflow-poller, every 1m, script=event-processor.py)
      event-processor.py (确定性 Python, 无 LLM):
        - 分组/去重/排序 → 判定 (SPAWN/STALLED/BLOCKED/E2E/FOLLOWUP)
        - 输出指令文本 (SPAWN: research/plan/implement/review/self-correct)
        - 确定性操作 (merge-pr/check-unblock) → STALLED 指令 (cron LLM 执行)
        - 依赖解析、槽位上限、stalled scan 信号
        - devlog: 每个 action 写 JSONL (spawn/skip/verdict/merge/error)
  → cron LLM (godot-workflow-poller prompt):
        - 读 SPAWN → delegate_task 生成 agent
        - 读 STALLED → 执行 gh 命令 (merge/unblock)
        - devlog 全程记录 (可观测, 不靠猜)
```

**关键原则（2026-08-15 重构失败教训后）：**
- **确定性操作脚本化**（merge/unblock/E2E orchestration/review 收尾 → event-processor 或脚本层）
- **LLM 只做判定型工作**（research PRD/plan DESIGN/implement 代码/review 结论）
- **可观测性优先**：devlog JSONL（~/.hermes/workflow-events.jsonl）记录每个 action，
  诊断不再靠时间线重建/grep 推断
- **2026-08-14 kanban 重构已回滚**（157 个 review 循环 task 失控）；
  回滚保留：opencode 强制、dead-spawn recovery、E2E orchestrator、
  review 结论文件、workflow-chain blocked 防呆

## Worktree 生命周期（2026-08-15 设计变更）

```
implement agent:  建 worktree (wt-implement-<N>) → 干活 → PR → 【保留】
E2E runner:       优先复用该分支已有 worktree (git worktree list 查找)
                  → L0/L1/L2 验证 (视觉已砍) → 自建的才删 (WT_OWNED)
review agent:     merge 前删 worktree (open worktree blocks branch delete)
```

**冲突根源消除**：implement 不再删 worktree,E2E 复用而非新建 — 不再有
`fatal: already checked out` 冲突。infra-error 重试（5 分钟退避）保留为兜底。

## 组件清单

| 组件 | 位置 | 职责 |
|------|------|------|
| `workflow-dispatcher.py` | `scripts/` + `~/.hermes/scripts/` | webhook 接收, 写 pending 文件 (thin) |
| `event-processor.py` | 同上 | 调度核心：分组/去重/排序/SPAWN-STALLED 指令/脚本化 merge+unblock/依赖/槽位/check-run 对账(P3b)/E2E 编排/devlog |
| `event_processor_lib.py` | 同上 | 纯逻辑核心（2026-07-31 拆分）：优先级、时间窗口、依赖解析、配置合并、成本治理(P4b) |
| `stage-gate.py` | 同上 | PR 创建后验证 label/branch/body, 自动修复 |
| `workflow-watchdog.py` | 同上 | 沉默 SPAWN 检测（no-agent cron every 5m, P2）|
| `workflow-metrics.py` | 同上 | PM 指标视图：吞吐/SPAWN 分布/健康度（P4c）|
| `run-e2e-review.sh` | `scripts/` | 本地 E2E 主 runner（P0-P8: worktree/L0-L3/证据/清理; P6 截图经 gist raw 上传嵌入 PR comment, 2026-07-31）|
| `e2e/analyze_bmp.py` | `scripts/` | PNG 原生 4 重防伪断言（非黑/色数/主题色/帧间差异——全帧平均Δluma 或 变化像素占比, 纯 stdlib）|
| `e2e/resolve_plan.py` | `scripts/` | diff→shot plan 原型选择（loop/journey/walkthrough/visual/system）|
| `framework/templates/e2e_capture.gd` | 模板 | 截图驱动 SceneTree 脚本（状态机轮询 + press 注入 + assert_text + per-shot deadline, 进程内截图）|
| `framework/templates/e2e_shots.json` | 模板 | shot plan 模板（游戏自持 `mini-pong/e2e_shots.json`）|
| `new-game-scaffold.sh` | `scripts/` | 新游戏项目脚手架（P4a）|
| `sync-to-hermes.sh` | `scripts/` | 同步脚本到 `~/.hermes/scripts/`（改脚本后必跑）|
| `workflow-config.json` | `~/.hermes/` | 启停 + 工作时段 + preset |
| `game-env/manifest.yaml` | 项目根 | 项目配置单一来源：repo/engine/branch/槽位（P3）|
| cron `godot-workflow-poller` | Hermes cron | every 1m, deliver=local, 脚本阶段 + LLM 执行 SPAWN/STALLED 指令 |
| cron `workflow-silent-spawn-watchdog` | Hermes cron | every 5m, no-agent, 沉默 SPAWN → Feishu |
| `~/.hermes/workflow-events.jsonl` | 状态 | devlog: 每个 action 一行 JSON（spawn/skip/verdict/merge/error, 5MB rotation×3）|
| `~/.hermes/review-conclusions/` | 状态 | review 结论文件（脚本收尾层读取）|
| `~/.hermes/e2e-state/` | 状态 | E2E orchestrator 状态机（running/done/failed）|

## 并发模型（2026-07-29 修订）

- `MAX_CONCURRENT_ISSUES=4`（picker 同时推进的 issue 数）
- `MAX_PHASE_SLOTS=4`（research/plan/implement 同时运行的 phase agent 上限）
- **Review/self-correct 不计入槽位（reserved slots），始终放行**
- **分布式锁 (workflow/lock-*) 已于 2026-07-29 删除** —— 并发由槽位 + pre-spawn 重复检查控制。任何 skill/代码不得重新引入 label 锁。
- 池满 → `[SKIP: pool full, retry next tick]`，绝不回退同步执行

## Label 状态机

| Label | 阶段 | 触发 |
|-------|------|------|
| `workflow/backlog` | 待排期 | issue 模板默认 |
| `workflow/available` | 已选取 | picker（依赖满足后自动推进）|
| `workflow/research` | 研究中 | available → research |
| `workflow/plan` | 设计中 | research PR merge 后 |
| `workflow/implement` | 实现中 | plan PR merge 后 |
| `workflow/self-correct` | 修复中 | CI failure |
| `status/done` | 完成 | implement PR merge 后 issue 关闭 |
| `status/blocked` | 阻塞 | review 发现 pre-existing 失败 |
| `status/human-review` | 待定稿（v4 队列） | taste-draft 草稿 merge 后 review agent 打标 + assign 用户 |

**Review 无 label** —— 由 `check_run.completed` (CI success) 触发，pre-merge。`workflow-chain.yml` 在 PR merge 后自动推进 label。

### 人机共做 v4 队列（2026-08-11）

**核心：workflow 不该等用户。** taste-draft Issue（content_ownership: taste-draft，品味内容：
数值/剧情/命名/失败文本/视觉）走队列模式：

```
implement 生成带 taste 方向的草稿（TASTE.md + 审美坐标 + Obsidian 注入）
  → review agent 定稿就绪检查（结构完整 + taste 对齐 + 校准接口三件套）
  → 不达标 → 打回重写，不 assign（不把烂活丢给人）
  → 达标 → 草稿 merge（PR 用 Parent #N 不写 Closes，Issue 保持 open）
  → assign 用户 + status/human-review label + Feishu 通知
  → 下游机械 Issue 立即继续（human-review 依赖视为已满足，不进依赖链）
  → 用户看 Assigned to me 攒批 → 微调 → push → close 即定稿
  → 差异记录进 docs/TASTE.md（品味档案）→ 下次草稿自动朝该方向
```

依赖语义（`_has_unresolved_dependencies`）：依赖 Issue 带 `status/human-review`
（草稿已 merge）→ 视为**依赖满足**，下游不等人的定稿速度。

## 事件 → SPAWN 指令表

event-processor.py 的输出格式（cron LLM 唯一输入）：

```
SPAWN: self-correct,issue=N,pr=N,branch=impl/xxx,conclusion=failure
SPAWN: self-correct,issue=N,pr=N,branch=impl/xxx,source=local-e2e
SPAWN: review,issue=N,pr=N,branch=impl/xxx,conclusion=success
SPAWN: research,issue=N,label=workflow/available|research
SPAWN: plan,issue=N,label=workflow/plan
SPAWN: implement,issue=N,label=workflow/implement
STALLED: merge-pr,pr=N,branch=research|plan/xxx      ← 非 impl PR CI 完成
BLOCKED: issue=N,depends-on=#M(full),...
[NO_ACTIONABLE_EVENTS: run stalled scan]
```

LLM 收到 SPAWN 必须执行（delegate_task），不得自行改写。stalled scan 覆盖：挂起 PR、未推进 label、未启动 phase、blocked PR 解锁（main 绿 → 移除 blocked → update-branch → 重新 CI）。

**2026-08-13 修复（A+B，cron 181544 4 分钟 tick 阻塞后续 SPAWN 的根因）：**
- **A. 非 impl 分支的 check_run.completed 不再输出 P1**。research/plan PR 的 CI 完成语义是"前置阶段 PR 就绪"，推进动作是 merge（workflow-chain 在 merge 后才推进 label）——不是让 cron LLM 调查。旧行为把事件输出成 `P1:` 让 LLM"决策"，cron 花了 4 分钟复查一个已完成/已推进的事件，期间 1-min tick 全被 `already running` 跳过，implement SPAWN 延迟 ~5 分钟。现在：
  - `conclusion=success` + research/plan 前缀 → `STALLED: merge-pr,pr=N`（确定性指令，与 stalled scan 同格式，LLM 一条 gh 命令执行完）
  - 其余情况（非 research/plan 前缀、非 success）→ 静默消费 + `audit(check_run.dropped)`，stalled scan 兜底
  - impl/* 分支的 self-correct/review SPAWN 路径**不变**
- **B. cron tick 90s 超时**：`HERMES_CRON_TIMEOUT=90`（~/.hermes/.env，scheduler 每 tick 重读，无需重启）。Hermes cron 的该值是 **inactivity 上限**（非墙钟）：tick 静默 >90s 即中断，下一个 1-min tick 可运行。terminal 长命令 / API 流 / delegate heartbeat 都会刷新 activity tracker，合法慢命令不被误杀。配合 A 后 tick 只剩 SPAWN/STALLED 直执行，天然短。

**2026-08-10 修复（金丝雀 #358）:**
- **SPAWN 一次性消费**: 输出 SPAWN 的事件立即从 pending 移除——否则每 tick 重发导致重复 delegate（曾 3 个并发 research agent / 2 个并发 plan agent）
- **spawn gate**: picker 对 plan/implement 的 SPAWN 按 (issue, stage) 去重, TTL 30 分钟（agent 死亡后过期恢复）
- **GH_REPO 进程级注入**（manifest project.repo）: cron 引擎以 `cwd=~/.hermes/scripts/` 跑脚本, gh 靠 cwd 探测 repo 会全失败 → 卡死
- **idle fast path 写 audit**: `[SILENT]` 快速路径也记录 audit（watchdog 盲区）
- **local-e2e source**: `workflow/self-correct` label + 无 pending CI failure → SPAWN 带 `source=local-e2e`（本地 e2e 失败的唯一入口）

## CI 三层门禁（Godot 4.7.1）

| 层 | 内容 | 位置 |
|----|------|------|
| L0 | 编译检查（`--check-only` 所有 .gd） | `opencode-review.yml` |
| L1 | 静态 smoke test | `tests/smoke_test.gd` |
| L2 | 运行时 playthrough（完整物理帧） | `tests/run_tests.gd` |

**2026-07-31 加固（D2）:** 每个测试 step 输出 `TEST_RAN=true`；Test gate 要求至少一个真实测试执行过 —— **SKIP 不再等于绿色**。任何 step 文件缺失（SKIP 分支）会导致 gate 失败。

## 本地验证层（2026-08-15 修订: 砍 L3 视觉, 保留 L0-L2）

**2026-08-15 决策: L3 视觉层已砍。** deepseek 无多模态, 截图断言价值低
且复杂度高（截图通道/防伪断言/orchestrator 反复出问题）。E2E 只剩
**L0 编译 / L1 逻辑 / L2 运行时**（确定性、快、无截图复杂度）:

```
run-e2e-review.sh <PR_NUM> --skip-visual  →  P0 防休眠 → P1 worktree(复用 implement 的)
                                              → L0 编译 → L1 逻辑 → L2 运行时
                                              → summary.json → trap 清理(只删自建 worktree)
```

- **worktree**: 优先复用 implement agent 保留的 worktree（git worktree list 查找）,
  避免 `fatal: already checked out` 冲突; 自建的才删（WT_OWNED）
- **L3 保留机制**: `--with-visual` 可显式开启（代码未删, 默认跳过）
- **失败协议**: A 基建(infra-error 自动重试 5 分钟退避) / B pre-existing / C 审美(人工) / D 代码缺陷(本地收敛循环)
- **E2E orchestrator**: event-processor 后台编排 runner, 状态可知（devlog 记录 done/failed/infra-error）

### E2E 编排（2026-08-14 方案②: 脚本化前置 + 状态可知）

review agent 的 50-call 预算**不**花在跑 harness 上——event-processor 把 E2E runner 编排为后台脚本（0 LLM calls）, agent 只解读结果:

```
CI 绿(impl PR) → e2e_orchestrator():
  state 机(存 ~/.hermes/e2e-state/<pr>.json):
    absent        → 后台启动 run-e2e-review.sh --no-comment, 写 running
    running+alive → 每 tick 输出 "E2E: pr=N still running (Xm)"  ← 状态可知
    running+dead  → 读 summary.json → done / failed
    done          → SPAWN: review,e2e_summary=<path>  (agent 只解读)
    failed        → 走 self-correct 路径
```

- **状态可知**: 大项目 E2E 跑很久时, 每 tick 输出进度, 不会像卡死（watchdog 不误报）
- **review agent 预算**从 ~50 降到 ~10 calls（判断 + 结论 + 写结论文件）
- 触发点: `check_run.completed`(impl 分支) + stalled scan 两条路径
- review skill: 收到 `e2e_summary` 时不重跑 runner, 直接 `cat summary.json` + 截图

### Review 结论脚本收尾（2026-08-14 方案①: 结论文件 + 脚本层）

review agent 可能超额度漏掉 label/评论/fix-issue（#466/#475 各发生一次）。**结论不靠 agent 记得, 靠脚本层兜底**:

```
review agent 最后一个动作: 写 ~/.hermes/review-conclusions/<pr>.json
  {"pr", "verdict": blocked|approved|..., "class": A|B|C|D,
   "parent_issue", "fix_issue": {title, failures}, "evidence"}

event-processor 每 tick: review_followup()
  verdict=blocked → status/blocked 加到 PR + parent(幂等)
  fix_issue       → 自动创建(fset hash dedup, 查重不重复建)
  评论            → 贴结论评论(含证据)
  处理后删文件(幂等, 失败可重试)
```

即使 agent 只写出文件就超额度, 收尾也必然执行。手动补 label 从此不需要。

### Dead-Spawn Recovery（2026-08-14）

SPAWN 指令发出后若 cron LLM 执行时超时（`TimeoutError: idle >90s`, #476 实测）, gate 会锁死 1 小时。`_dead_spawn_recovery()`: gate 记录超过 TTL/2 且 issue 仍无 PR → 允许绕过 gate 重发（PR-exists 是真去重）。plan/implement 两阶段接入。

### Blocked + Self-Correct 共存（2026-08-14）

同一 PR 可同时 blocked（B 类 pre-existing）和 self-correct（D 类 code defect）——stalled scan 对 blocked PR 检查 parent 的 `workflow/self-correct` label, 两个指令都 emit（旧逻辑 blocked 优先压死 self-correct）。

### Unblock 条件修正（2026-08-14）

check-unblock 不再用 godot 逻辑测试判断（视觉 block 时逻辑测试全绿会误解锁）——改为: 找 fix issue（`gh issue list "pre-existing"`）→ 未合并则 ⏳ 等待; 已合并 → 删 PR+parent 的 blocked → update-branch。

**流水线自身测试（D3）:** `tests/pipeline/`（157 用例）覆盖 event-processor 纯函数 + e2e 断言/runner/resolve/manifest。CI job `pipeline-tests.yml` 在 `scripts/` 或 `.github/workflows/` 变更时强制运行。**改流水线代码必须先过这个套件。**

## Git 约定

- 默认分支: `main`（任何 skill 提到 master 都是过时的）
- phase 分支前缀: `research/` `plan/` `impl/`（不是 implement/）
- 每个 phase PR 必须从 `main` 分支，body 必须含 `Parent #N`（无冒号）或 `Closes #N`
- 分支隔离: 绝不从其他 issue 的分支分支
- 合并策略: research/plan 自动 merge；**impl/ 必须 review agent 批准后 merge**（implement agent 的 SKILL.md 不含任何 merge 指令）

## 游戏项目结构

```
agent-game-test/
├── project.godot          ← 根 Godot 项目（旧实验, 保持）
├── mini-pong/             ← 当前主游戏（自己的 project.godot + gdscripts/ + scenes/ + tests/）
├── gdscripts/ scenes/     ← 根项目代码
├── tests/                 ← 根项目测试 + tests/pipeline/（流水线 Python 测试）
├── docs/                  ← Issue 级 PRD/DESIGN/TASKS + GAME_DESIGN/ (GDD)
├── .github/workflows/     ← runtime CI (GitHub 要求位置)
└── framework/             ← 本框架文档 (只读参考)
```

## 已知限制

- Godot headless 不支持所有渲染功能
- 需要手动配置 export preset
- OpenCode 生成 GDScript 质量取决于模型能力
- 多仓库 pending 事件（Patch 54）尚未支持 —— 单仓库假设, P3 manifest 参数化解决
- webhook 链路（ngrok→gateway→route script）5 个故障点 —— 调度器状态检测兜底：label 事件丢失 → picker 直发/available 重扫（research）+ stalled scan（self-correct 感知）；check_run 丢失 → reconcile_check_runs（pr+sha 身份化对账）。reconcile() 合成事件注入已删除（2026-08-13）
- **L3 视觉层已砍（2026-08-15）**: deepseek 无多模态, 截图断言价值低; `--with-visual` 保留机制可显式开启
- **单机依赖**: 本地 e2e 依赖 Mac mini 在线 + UURemote 防系统睡眠（外部依赖, 不在仓库内）
- **runner 安全边界**: worktree 隔离防主工作区污染, 但不防恶意 GDScript 读主机文件——只对可信贡献者运行

## 知识资产索引（P1-5 收敛后）

| Skill | 状态 |
|-------|------|
| `dev-workflow-dispatcher`（repo 内, symlink）| **权威调度 skill**，cron 加载 |
| `dev-pipeline-automation`（框架级）| 通用流水线模式参考（与 dispatcher 部分重叠）|
| `godot-headless-testing` | **headless 测试唯一入口**（absorbed patterns+runner）|
| `game-research/plan/implement/review-agent` | 各阶段 agent 技能 |
| `game-to-issues` | Issue 分解（upstream）|
| `workflow-lock-label-handling` | **已删除机制的史档**（历史参考）|
| `dev-workflow-dispatcher-patches` | **已归档**（2026-07-31 全部应用）|

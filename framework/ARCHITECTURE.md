# framework/ARCHITECTURE.md — Godot Edition (Single Source of Truth)

> **本文档是 workflow 架构的单一事实源。** 所有 agent skill 中的架构描述必须与本文一致。
> 项目仓库: https://github.com/devvi/agent-game-test · 默认分支: **`main`**（不是 master）
> 最后更新: 2026-07-31（P1-5 知识收敛）

## 系统概述

将游戏开发分解为五个 agent 阶段，由 GitHub 事件驱动 + cron 轮询兜底：

1. **Research** — 研究、PRD 生成（`docs/PRD/`）
2. **Plan** — 架构设计、测试用例描述（`docs/DESIGN/` + 可选 `docs/TASKS/`）
3. **Implement** — GDScript 代码生成（OpenCode，`impl/` 分支）
4. **Review** — 代码审查、合并决策（CI 成功后 pre-merge 触发，**不在 label 链中**）
5. **Self-correct** — CI 失败诊断修复（`workflow/self-correct` label）

## 运行时架构（五层）

```
GitHub Event → Gateway webhook (:8644)
  → workflow-dispatcher.py (thin route script — 只写 pending 文件, 不做 gh/git)
  → ~/.hermes/workflow-pending.json (~0.3KB/event, 不含 payload)
  → cron tick (godot-workflow-poller, every 1m, script=event-processor.py)
      Phase 1: event-processor.py (确定性 Python, 无 LLM)
        - 分组/去重/排序 → 输出 SPAWN 指令 (P1 check_run > P2 labeled)
        - 依赖解析、槽位上限、stalled scan 信号
      Phase 2: cron LLM (terminal + delegation toolsets)
        - 读取 SPAWN → delegate_task 生成 phase agent
        - 空闲 → [SILENT]（零 token 消耗）
```

**关键原则：确定性逻辑在 Python，决策逻辑在 LLM。** 脚本做数据加工（0% 幻觉率），LLM 做 GitHub 状态验证和分支决策。

## 组件清单

| 组件 | 位置 | 职责 |
|------|------|------|
| `workflow-dispatcher.py` | `scripts/` + `~/.hermes/scripts/` | webhook 接收, 写 pending 文件 (thin) |
| `event-processor.py` | 同上 | 调度核心：分组/去重/排序/SPAWN/依赖/槽位 |
| `event_processor_lib.py` | 同上 | 纯逻辑核心（2026-07-31 拆分）：优先级、时间窗口、依赖解析、配置合并 |
| `stage-gate.py` | 同上 | PR 创建后验证 label/branch/body, 自动修复 |
| `sync-to-hermes.sh` | `scripts/` | 同步脚本到 `~/.hermes/scripts/`（改脚本后必跑） |
| `workflow-config.json` | `~/.hermes/` | 启停 + 工作时段 + preset |
| cron `godot-workflow-poller` | Hermes cron | every 1m, deliver=local, 脚本 + LLM 两阶段 |

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

**Review 无 label** —— 由 `check_run.completed` (CI success) 触发，pre-merge。`workflow-chain.yml` 在 PR merge 后自动推进 label。

## 事件 → SPAWN 指令表

event-processor.py 的输出格式（cron LLM 唯一输入）：

```
SPAWN: self-correct,issue=N,pr=N,branch=impl/xxx,conclusion=failure
SPAWN: review,issue=N,pr=N,branch=impl/xxx,conclusion=success
SPAWN: research,issue=N,label=workflow/available|research
SPAWN: plan,issue=N,label=workflow/plan
SPAWN: implement,issue=N,label=workflow/implement
BLOCKED: issue=N,depends-on=#M(full),...
[NO_ACTIONABLE_EVENTS: run stalled scan]
```

LLM 收到 SPAWN 必须执行（delegate_task），不得自行改写。stalled scan 覆盖：挂起 PR、未推进 label、未启动 phase、blocked PR 解锁（main 绿 → 移除 blocked → update-branch → 重新 CI）。

## CI 三层门禁（Godot 4.7.1）

| 层 | 内容 | 位置 |
|----|------|------|
| L0 | 编译检查（`--check-only` 所有 .gd） | `opencode-review.yml` |
| L1 | 静态 smoke test | `tests/smoke_test.gd` |
| L2 | 运行时 playthrough（完整物理帧） | `tests/run_tests.gd` |

**2026-07-31 加固（D2）:** 每个测试 step 输出 `TEST_RAN=true`；Test gate 要求至少一个真实测试执行过 —— **SKIP 不再等于绿色**。任何 step 文件缺失（SKIP 分支）会导致 gate 失败。

**流水线自身测试（D3）:** `tests/pipeline/test_event_processor.py`（37 用例）覆盖 event-processor 纯函数。CI job `pipeline-tests.yml` 在 `scripts/` 或 `.github/workflows/` 变更时强制运行。**改流水线代码必须先过这个套件。**

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
- webhook 链路（ngrok→gateway→route script）5 个故障点 —— stalled scan 是兜底, P3 轮询对账补强

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

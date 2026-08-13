# 分支隔离与同步方案 — worktree 全阶段隔离 + 提交前 merge main

> 状态: **已确认** (2026-08-13 用户拍板)
> 根因: 多 agent 并发共用主工作区 → 互相污染 (PR 混入其他 issue 内容)
> 证据: #440 混入 #387 DESIGN, #439 混入 #385 DESIGN, #428 混入 #389 DESIGN; sibling stash 全家桶

---

## 1. 问题

| 症状 | 根因 |
|------|------|
| implement PR 混入其他 issue 的文件 (#440→#387, #439→#385) | 所有阶段 agent 在主工作区开发, 并发槽位 4 → 互相覆盖 |
| "sibling stash" 全家桶 (6+ 个 stash 带 sibling 字样) | agent 互相抢救对方未提交的改动 |
| 测试测旧代码 (#447 时 BreakoutGrid 未接线) | CI 测 head commit, 分支未包含 main 最新组件 |
| 大量 branch-collision pitfalls (research/plan skill 里) | 分支切换 + 脏工作区 + 并行 push 冲突 |

**本质**: 缺少物理隔离 + 同步时机错误。

---

## 2. 方案(用户确认)

### 2.1 全阶段 worktree 隔离

research / plan / implement 三个阶段全部在独立 worktree 开发:

```
/tmp/wt-research-<N>   ← research agent (写 PRD)
/tmp/wt-plan-<N>       ← plan agent (写 DESIGN/TASKS)
/tmp/wt-impl-<N>       ← implement agent (写代码/测试)
```

- 每个 worktree 基于最新 `origin/main`, 独立分支 `research/<N>-<slug>` / `plan/...` / `impl/...`
- **主工作区零污染** — 只有 Hermes 主 agent 和脚本维护用
- review agent 的 E2E 已用 worktree (run-e2e-review.sh), 模式对称

### 2.2 提交前 merge main(程序员工作流)

**时机: 开发完成后、commit/push 之前** — 不是开始:

```
worktree 创建 (基于 main 当前) → 开发 → 提交前: git merge origin/main
  → 自动合并 → commit → push → PR (内容 = 最新 main + 我的改动)
```

理由:
- 开始 merge: 开发期间 main 又前进, 提交时仍是旧基线, CI 测旧代码 (问题未解决)
- 提交前 merge: PR 内容即最终形态, CI 测的就是要合的东西
- 依赖链 DAG 保证"开始时不 merge"安全 (前置已满足, 本 issue 开发不受影响)

### 2.3 冲突分级处理(用户确认: 尝试自动 merge)

```
git merge origin/main
  ├── 自动合并成功 (git 处理不冲突区域) → 继续 ✅
  ├── 真冲突 (≤2 文件) → 尝试 merge --continue / commit --no-edit
  │     └── 成功 → ✅ ; 失败 → abort + 报告调度层
  └── 冲突文件 >2 或非冲突错误 → abort + 报告 (不硬解)
```

- **自动 merge 是常态** (不同 issue 改不同文件/区域, git 能自动合并 90%+)
- 暴力 `git checkout --theirs/--ours` 禁用 (会丢改动)
- abort 后: 报告 event-processor → 标记 blocked/重排

---

## 3. 实现

### 3.1 共享脚本 (已落地)

| 脚本 | 职责 |
|------|------|
| `scripts/worktree-setup.sh <phase> <issue> <slug> [--pre-merge]` | 创建 worktree + 分支 (基于 origin/main), 幂等复用 |
| `scripts/worktree-commit.sh <issue> <message> [files...]` | 提交前 merge main + 冲突分级 + 白名单 add + 编译验证 + push |

### 3.2 Skill 改造 (三个阶段 agent)

每个 skill 的 git 操作段替换为:
1. `./scripts/worktree-setup.sh <phase> <N> <slug>` → 得 worktree 路径
2. 在 worktree 内开发 (write_file / terminal 用绝对路径)
3. 完成 → `./scripts/worktree-commit.sh <N> "<msg>" <files...>` (提交前 merge main)
4. PR 创建 (worktree 内 gh pr create)
5. 清理: `git worktree remove /tmp/wt-<phase>-<N> --force`

### 3.3 红线

- **绝不 `git add .`** (白名单 add, worktree-commit.sh 强制)
- **绝不 `git stash`** (worktree 隔离后不需要; stash 是污染时代的遗产)
- 主工作区留给 Hermes 主 agent, 阶段 agent 只碰自己的 worktree

---

## 4. 验证

| 验证 | 结果 |
|------|:----:|
| worktree 创建 (implement 999 实测) | ✅ |
| 主工作区改动不污染 worktree | ✅ |
| worktree 提交不影响主工作区 | ✅ |
| worktree 清理 + 分支删除 | ✅ |
| 冲突分级逻辑 (脚本内) | 待真实冲突验证 |

---

## 5. 后续

- [ ] 更新三个 skill (research/plan/implement) git 操作段
- [ ] AGENTS.md 架构文档更新
- [ ] 真实 pipeline 跑一轮验证 (下个 issue 走 worktree 流程)
- [ ] 冲突分级在真实冲突场景验证

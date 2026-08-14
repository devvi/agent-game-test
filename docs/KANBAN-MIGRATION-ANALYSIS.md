# Kanban 重构中期分析 — 停止点 (2026-08-14 18:45)

## 为什么停止
边重构边跑产生了大量非目标情况(不断 block / 新 fix issue / 多 agent 并行),
干扰重构本身。停止 workflow + 冻结 kanban,分析后继续。

## 当前 issue 图谱(停止时)
```
#466 [Test] 视觉回归 E2E (目标)
  ├─ status/blocked: 被 pre-existing 缺陷阻塞
  ├─ workflow/self-correct: 自身代码缺陷修复中
  └─ PR #475 (impl/466-e2e-visual-regression): L3 视觉断言实现

#480 Fix e2e runner (worktree ownership + P5 plan source)
  ├─ workflow/implement
  └─ PR #486 (impl/480-e2e-runner-fix) OPEN

#485 Fix BgPulse 背景桶泄漏 (fix #466 的 L3 断言)
  ├─ workflow/implement
  ├─ 由 unblock worker t_a224053b 实测发现并创建
  └─ 是 #475 的新 blocker (fset: ecb41bc8)
```

## "无限循环"的机制分析

### 循环链 1:pre-existing → fix issue → 新 pre-existing
```
review 发现 L3 失败 → 分类 B (pre-existing) → 建 fix issue
→ fix issue 修完 merge → unblock → review 重跑
→ 发现【另一个】pre-existing (BgPulse 相位) → 又建 fix issue #485
→ 潜在: #485 修完 → review 再发现下一个
```
**根因:main 上有多个累积的视觉/测试缺陷,每次 review 只暴露一个,修一个露一个。**

### 循环链 2:review 的判定标准在变(最危险)
```
review worker A: L3 rain coverage 16.7% < 60% → class C (审美, 需人工)
review worker B: BgPulse 相位 → class B (pre-existing) → 建 #485
unblock worker:  三色 dist 0.0 → BgPulse 桶泄漏 → 指向 #485
```
**同一 PR 被多个 worker 用不同标准判定 → 结论互相覆盖 → block/unblock 抖动。**

### 循环链 3:多 worker 并行同一 PR
```
bridge 去重 bug (跨 tick 重复 + 并发竞态) → 8 个并行 worker 处理 #475
→ 各自建 fix issue / 打 label / 写结论 → 状态互相踩踏
→ 我 block 了重复的,但 worker 的副作用 (fix issue) 已产生
```

## 三个深层问题

### 问题 A:review 判定没有"单一权威"
多个 worker (review/unblock/self-correct) 都能对 #475 判定和建 fix issue,
没有仲裁。原设计里 review agent 是唯一判定者,kanban 迁移后 unblock worker
也建 fix issue (t_a224053b 建了 #485),职责重叠。

### 问题 B:pre-existing 的暴露是"串行挤牙膏"
每次 review 只发现一个 pre-existing,修完再发现下一个。应该:
- 一次 review 系统性列出**所有** pre-existing (一个 fix issue 装全部)
- 或: review 失败时先跑"main 基线验证",把 main 自身的所有缺陷一次性暴露

### 问题 C:worker 并行度失控
kanban 默认并发 spawn,没有"每 issue 一个 worker"的约束。
应该: 同一 issue 的 task 用 --parent 依赖链串行,不同 issue 才并行。

## 重构决策 (暂停后的修正方向)

1. **冻结期**:workflow 暂停,kanban 全 block,worker 全杀。完成重构前不恢复。
2. **修 bridge 并发**:已加 flock。补 task 状态感知 (done 允许重发)。
3. **review 单一权威**:只有 review worker 能建 fix issue / 判定 class。
   unblock worker 只做"查 fix issue 状态 + 更新 label",不判定。
4. **pre-existing 批量暴露**:review 失败时,先跑 main 基线 L3,
   把 main 所有缺陷一次列出 (一个 fix issue, fset 全包含)。
5. **worker 串行化**:同 issue 的 stage 用 kanban --parent 链。
6. **恢复策略**:重构完成 + 测试过 → 恢复 workflow → 让 pipeline 从
   当前图谱继续 (#466/#480/#485),观察是否还循环。

## 恢复后的预期
#480 (runner) → merge → #485 (BgPulse) → merge → #466 unblock → review
→ 若还有 pre-existing → 单 fix issue 批量 → 收敛。
循环的终止条件: main 的 L3 基线全绿 (fix issue 全部 merge)。

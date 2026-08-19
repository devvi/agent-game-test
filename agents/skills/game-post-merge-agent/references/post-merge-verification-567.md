# Post-Merge 阶段实测验证 — #567 (2026-08-19)

首次真机端到端验证（测试 issue #567，载体 = Main.tscn 加 PostMergeProbeLabel）。
全链路零人工介入，100% 成功。证据与教训：

## 时间线（本地时区）

```
12:44  gh issue create #567 (workflow/available)
12:51  tick 发射 SPAWN: research,issue=567,game=shandong-wolf（available-rescan,
       spawn=1; 同 tick 重复尝试被 gate-ttl 防重挡掉 — 正常防重, 不是故障）
12:53  cron LLM delegate → research 子代理
12:56  #568 research PRD → stalled scan 自动 merge
13:34  #569 plan DESIGN → 自动 merge
13:41  #570 implement (impl/567-post-merge-probe) → review_followup 自动 merge
13:43  E2E 启动 (e2e-state/570.json, started_at)
13:46  E2E done → 结论骨架预生成 + SPAWN: review 发射 (emitted_at)
13:52  review agent 填 approved → review_followup 消费 → merge 已完成 +
       _ensure_post_merge_state(570, 567) + SPAWN: post-merge 发射 (one-shot)
13:54  #571 docs/gdd-570 PR → _quick_stalled_scan 自动 merge (docs/ 前缀)
       post-merge agent 轮询到 MERGED → 写 status=done
```

## 终态证据

- `~/.hermes/post-merge-state/570.json`:
  `status=done, docs_pr=571, gdd_chapters=[01-OVERVIEW.md 新增, INDEX.md 填充]`
  （agent 自发把 gdd_chapters 写进状态文件 — 已升级为 skill 标准步骤）
- #571 diff 白名单干净: `docs/GAME_DESIGN/shandong-wolf/01-OVERVIEW.md`
  + `INDEX.md` + `docs/PROJECT.md`
- GDD 落盘 main: 01-OVERVIEW.md（总览/场景骨架/探针 Label）+ INDEX.md 表格更新
- #567 → 自动 CLOSED + status/done

## 验证点对照（issue AC 全部通过）

| AC | 结果 |
|----|------|
| 三层 CI 全过 | ✅ |
| review_followup 自动 merge | ✅ |
| post-merge-state pending → SPAWN: post-merge one-shot | ✅ 无重发 |
| docs/gdd-N PR 白名单 diff | ✅ |
| stalled scan 自动 merge docs PR | ✅ |
| GDD 章节 + INDEX.md 落盘 | ✅ |
| status=done (docs PR MERGED 后) | ✅ |
| 无 post-merge-stuck 告警 | ✅ |

## 过程中发现并修复的问题（跨阶段, 非 post-merge 自身缺陷）

1. **P2 骨架 verdict=null 误报**（watchdog/event-processor, cab7123 修复）:
   骨架生成 (13:46) 到 review agent 填值 (13:52) 之间有 ~6 分钟合法窗口,
   旧 watchdog 把 verdict=null 归一化成 "none" 当自由文本 → 刷 Feishu 告警。
   修复: verdict is None → 新鲜(<20min) 静默; 滞留>20min → "骨架未填" 告警。
   教训: **加"预生成"机制时, 必须同步更新所有校验器认识其合法中间态**。

2. **测试泄漏 475/562.json**（TestReviewFollowup 未 patch POST_MERGE_STATE_DIR）:
   approved 结论测试跑 review_followup → _ensure_post_merge_state 写真实目录。
   4afe339 同类。修复: setUp 补 patch。教训: **event-processor 新增状态目录后,
   grep 所有调用 review_followup/main() 的测试类, 逐个 patch 新目录**。

3. **MANIFEST_PATH 硬编码 macOS 路径**（0f18c45 修复）: pipeline-tests CI (ubuntu)
   读不到 ~/workspace/agent-game-test → ACTIVE_GAME 永远 mini-pong → game= 断言
   连红 6 次。E2E_RUNNER 08-17 同类。修复: __file__ → cwd → 硬编码兜底 推导。
   教训: **scripts/ 里的路径必须从 __file__/cwd 推导, 不能依赖本机 HOME**。

## 监控模式（全程测试监控, 可复用）

no_agent cron + 状态脚本（post-merge-test-monitor.py 模式）:
- 粗粒度状态 (label 链/PR 状态/post-merge-state/GDD 章节/docs PR) 变化才输出
  (md5 hash 比较), 无变化静默 — 不刷屏
- 卡住 (pending+emitted>45min) 无条件输出告警 — 不漏报
- every 15m, deliver origin（测试期间播报到群）
- 测试完成后删 cron（一次性工具）

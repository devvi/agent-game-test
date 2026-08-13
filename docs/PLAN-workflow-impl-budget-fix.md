# Workflow 修复方案 — implement/review 预算截断 + OpenCode 未强制

> 状态: 待审阅 (2026-08-13)
> 触发: #466 implement agent 50-call 截断, worktree 残留未提交改动, pipeline 无恢复机制

## 背景与证据

| 事实 | 证据 |
|------|------|
| implement 应走 OpenCode | skill §171 "OpenCode Workflow"; cron delegate 指令含 "OpenCode layered implementation" |
| **实际未走 OpenCode** | #466 agent 214330: 64×terminal + 3×process, 无 opencode 调用, 退化为手写 |
| 50-call 预算截断 | config.yaml `delegation.max_iterations: 50`; 历史 9 次 max_iterations_reached |
| 截断后无恢复 | #466 worktree 残留 `M rain_curtain.tscn`, stalled scan 全 [SILENT], 卡死 implement |
| 残留改动本身有效 | rain_curtain.tscn: emission_shape 1(SPHERE, API 已移除)→ 3(BOX) — 漏水点真根因 |

## 根因链

```
implement agent 手写代码 (未用 OpenCode)
  → 手写 + 测试循环烧 call 预算 (OpenCode 一次调用不占 agent call)
  → 50-call 截断 (max_iterations_reached)
  → worktree 残留未提交改动
  → stalled scan 不识别"worktree 脏 + 无 PR" → 无恢复 → 卡死
```

## 修复方案 (三层)

### 方案 A: 强制 OpenCode 为 implement 唯一路径 (根因修复)

**改 `agents/skills/game-implement-agent/SKILL.md`:**
- OpenCode 从 "Recommended" 改为 "**MANDATORY**" — 手写 fallback 仅限 OpenCode 服务不可达(HTTP 非 200)
- 手写 fallback 必须满足: ① PR body 注明 "fallback: OpenCode unreachable" ② 只写 DESIGN 已详述的文件
- 新增检查项: 提交前确认代码由 OpenCode 生成(或 fallback 已声明)

**效果:** OpenCode 调用是一次性外部进程(opencode run), 不消耗 agent 的 call 预算 → agent 只需 5-10 call (调 OpenCode + 验证 + 提交) → 50-call 预算充足, 截断问题自然消失。

### 方案 B: 预算提升 (缓解)

**改 `~/.hermes/config.yaml`:**
```yaml
delegation:
  max_iterations: 80   # 50 → 80
```
- 给 implement/review 更多余量(特别是 review 的完整 E2E 流程)
- 副作用: 失败的 agent 烧更多 token — 需配合 C

### 方案 C: 截断检测 + 恢复 (兜底)

**改 `scripts/event-processor.py` 的 stalled scan:**
新增检测: implement 阶段 issue + 存在 `impl/N` worktree + worktree 有未提交改动 + 无 impl PR
→ 输出 `STALLED: impl-resume,issue=N` → cron 重新 spawn implement agent(带 worktree 上下文)

**改 worktree-setup.sh:** 幂等重入 — 已存在的 worktree 复用而非重建(保留未提交改动)

## 建议组合

**A(强制 OpenCode)+ C(截断恢复)** — A 治本(减少截断), C 兜底(万一仍截断能自愈)。B 可选(如果 A 后仍频繁截断再加)。

## 当前 #466 处理

按红线不手动干预。若方案 C 落地, stalled scan 会自动检测 #466 的残留 worktree 并重 spawn implement agent(复用未提交的 rain_curtain.tscn 改动)。

## 验证方式

修复后跑一个新 implement issue:
1. audit 显示 implement agent 调用了 opencode(日志有 opencode run 痕迹)
2. agent 用 <15 call 完成(不截断)
3. 若人为制造截断(临时改回 50), stalled scan 输出 impl-resume 并自动重 spawn

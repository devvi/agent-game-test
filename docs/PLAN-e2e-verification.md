# E2E 本地验证方案(执行版)

> 精简自 `docs/PLAN-e2e-verification-v2.md`(全量讨论记录)。本文是执行版。

## 要解决什么

review agent 在本地验证 impl PR,产出"游戏真的长这样、真的能玩"的证据,贴到 PR 上。
三个关键事实决定了做法:
- **worktree 隔离** — 不再切分支/stash(7 个 pitfall 家族),每 PR 一个独立目录
- **真实渲染截图** — 系统截图在显示睡眠时 100% 黑(已实测),必须用 Godot 进程内截图
- **失败要能收敛** — 本地 bug 只有本地能验证,不能塞进 CI 判据(会死循环)

## 设计原则(一句话版)

1. 验证方式 = 制作人直觉的有界自动化(玩法→玩一局,内容→跑一遍)
2. 检测和验证必须在同一闭环(本地 bug 用本地判据)
3. 机器管结构/呈现,人管味道
4. 框架管机器,游戏管剧本(shot plan 游戏自己写)
5. 循环必须收敛或升级(2 轮本地失败→人工)
6. 黑图永不贴 PR(4 重防伪断言)

## 验证原型

| 原型 | 适用 issue | 做法 |
|------|-----------|------|
| loop | 玩法系统 | 一局三帧: title / 对打中段 / 终局 |
| journey | 内容/叙事 | **完整跑一遍**: 沿途截图 + 对话转写 + 状态轨迹 |
| walkthrough | 单场景内容 | 跳转触发 + 文本 fidelity 断言(屏幕字 == 数据字) |
| visual | 特效/HUD | 特定效果定帧 |
| scaffold | 新项目 | 每场景一帧 |

→ diff 自动选原型: 纯内容默认 journey,其余默认 loop

## 核心机制

1. **worktree 隔离**: 每 PR 一个 `/tmp/wt-impl-N`,trap 自动清理;merge 前必删(否则 `--delete-branch` 失败)
2. **截图**: 非 headless + 进程内 `get_image()`;状态机驱动时机;基线 3 帧,scope 每项 +1,上限 5;≤120s/组
3. **断言 4 重**: 非黑 / 色数 / 主题色 / 帧间差异(防冻屏)
4. **证据上贴**: 截图 + 测试摘要 → user-attachments 上传 → `gh pr comment`(gist 兜底;REST 无附件端点,已查证)
5. **失败处理**: 分类(A 基建 / B 已有 / C 审美 / D 代码)
   - A: 修 harness 或降级,不计 cycle
   - B: status/blocked + fix issue(现有路径)
   - C: REQUEST_CHANGES + 证据 → 人工拍板
   - D: **本地收敛循环** — review 打 label → event-processor 新规则 SPAWN → self-correct 在 worktree 修 → review 重跑本地 e2e(收敛判据)→ 2 轮上限 → 人工 + 证据包
6. **内容验收 3 层**: L1 结构(机器,含海明威校验)/ L3 呈现(截图 + fidelity)/ L4 味道(人拍板)

## 交付物

| 文件 | 职责 |
|------|------|
| `scripts/run-e2e-review.sh` | 主 runner(P0 预检 → worktree → L0-L3 → 证据 → 清理) |
| `framework/templates/e2e_capture.gd` + `e2e_shots.json` | 截图模板 + shot plan(游戏自持剧本) |
| `scripts/e2e/analyze_bmp.py` | 4 重像素断言(纯 stdlib) |
| event-processor 补丁 | label → `SPAWN: self-correct,source=local-e2e`(+1 测试) |
| `tests/pipeline/` +3 测试 | runner / 断言 / SPAWN 规则 |
| game-review-agent skill | 本地验证改调 runner,失败协议入 skill |

## 实施顺序

1. **机器层**: 断言 + 模板 + runner + 全部单测 → 本地全绿
2. **mini-pong 实弹**: 3 帧跑通 + 断言 + 证据上贴实测(锁定端点)
3. **失败协议**: event-processor 补丁 + 测试 + skill 更新
4. **叙事试点**: journey/walkthrough 在叙事游戏跑一遍
5. **收敛**: ARCHITECTURE.md + skill 同步 → CI 绿 → 合入

## 待定(6 个,已给倾向)

| # | 问题 | 倾向 |
|---|------|------|
| 1 | 帧间差异阈值 | 先收真实样本再定 |
| 2 | journey 超时(120s) | 硬失败(剧本自声明) |
| 3 | C 类审美升级 | 带默认建议,但 merge 必须人工确认 |
| 4 | D 类根因提示 | 给观察,不给方案 |
| 5 | 截图回流审美库 | 升级时人工勾选 |
| 6 | journey 路径数 | 默认 1 条(中性),发布级 3 条 |

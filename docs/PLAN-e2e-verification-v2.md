# E2E 本地验证方案 v2 — 综合讨论结论 (2026-07-31)

> 本方案取代 `docs/PLAN-e2e-modification.md`(v1)。v1 解决了"worktree 隔离 + 截图通道",
> v2 在此基础上收敛了六轮讨论: 失败处理协议、验证原型、内容型 issue 验收、制作人直觉原则。
> 所有机制事实均已实测/查证: 显示睡眠下系统截图 100% 黑、Godot 进程内截图 21/21 帧真实、
> GitHub REST API 无评论附件端点、event-processor 只认 check_run 触发 self-correct。

## 0. 设计原则 (讨论沉淀, 每条来自具体论证)

| # | 原则 | 来源 |
|---|------|------|
| P1 | **验证方式 = 制作人验证该 issue 直觉方式的有界自动化** | "我会全部跑一遍游戏" |
| P2 | **检测 bug 的闭环必须等于验证 bug 的闭环** (收敛判据本地化) | 本地失败不能进 CI 判据的死循环论证 |
| P3 | **机器管结构/呈现, 人管味道** | 内容 issue 三层验收 |
| P4 | **框架管机器, 游戏管剧本** (shot plan 游戏自持) | 泛化讨论 |
| P5 | **确定性规则 > 启发式兜底** (stalled scan 只做最后防线) | 事件流完整性讨论 |
| P6 | **证据可审计, 防伪 4 重断言** (黑图永不贴 PR) | 截图实证 |
| P7 | **循环必须收敛或升级** (2 轮本地失败 → 人工) | 成本治理讨论 |
| P8 | **pipeline bugs must be caught by tests** | 仓库纪律 |

## 1. 架构总览: 四层验证 + 原型选择

```
四层验证模型:
  L0 编译      headless, CI+本地         check_compile.gd
  L1 逻辑      headless, CI+本地         run_tests.gd (含 auto_play) + 内容结构校验
  L2 运行时    headless, CI+本地         playthrough_test.tscn (全引擎物理帧)
  L3 视觉证据  ★本地真实渲染 (worktree)  archetype 驱动截图 + 断言   ← 新增
  L4 味道      人/制作人                  journey 证据包 + 人工确认   ← 新增

原型 (archetype) = 制作人验证直觉的自动化剧本:
  loop      玩法系统 issue       → 玩一局:  title/midgame/terminal 三帧
  journey   内容/叙事 issue      → 全部跑一遍: 完整 playthrough + 沿途证据
  walkthrough 单场景内容 issue   → 跳转走查: 触发→选项→效果→收尾 + fidelity
  visual    特效/shader/HUD      → 盯着看: 特定效果定帧
  scaffold  新项目/组装 issue    → 每个场景逛一遍: boot + 逐场景一帧
  system    物理/输入/碰撞       → 无截图, L1/L2 为主, loop 做回归

选择: gh pr diff --name-only ∩ shot plan 的 group.match 正则 → 激活对应组
      默认回退 loop; 纯内容 diff 默认 journey (保守原则: 拿不准走更深的)
```

## 2. 核心组件

| 文件 | 职责 | 测试 |
|------|------|------|
| `scripts/run-e2e-review.sh` | 主 runner, P0-P8 | test_e2e_runner.py (RUNNER_GODOT 注入) |
| `framework/templates/e2e_capture.gd` | 截图脚本模板 (状态机轮询, 零侵入) | 真机校准 |
| `framework/templates/e2e_shots.json` | shot plan 模板 (游戏自持) | schema 校验 |
| `scripts/e2e/analyze_bmp.py` | 4 重防伪断言 (纯 stdlib) | test_analyze_bmp.py |
| `scripts/e2e/transcript_dump.gd` | journey 对话转写 + 状态轨迹 dump | 真机校准 |
| `tests/pipeline/test_e2e_runner.py` | runner 工作流单测 | pipeline-tests.yml |
| `tests/pipeline/test_e2e_analyze.py` | 像素断言单测 | 同上 |
| `tests/pipeline/test_local_e2e_spawn.py` | event-processor label→SPAWN 规则 | 同上 |

## 3. run-e2e-review.sh 阶段 (P0-P8)

```
P0 pre-flight    caffeinate 电源守卫 / godot 存在 / worktree 无冲突 / 分支 fetch
                 并发单例锁 .e2e-<N>.lock (mkdir 原子 + PID 存活校验, stale 回收)
P1 worktree      git worktree add /tmp/wt-impl-<N> <impl-branch>   (主工作区零接触)
P2 L0 编译       --headless --script tests/check_compile.gd
P3 L1 逻辑       --headless --script tests/run_tests.gd
                 内容型 issue 追加: schema + 海明威 + 完整性 + 引用有效 (headless)
P4 L2 运行时     --headless tests/playthrough_test.tscn
P5 L3 视觉       archetype 驱动 (真实渲染, 非 headless, ≤120s/组):
                   loop      3 基线帧 + scope 帧
                   journey   完整 playthrough + 沿途帧 + 对话转写 + 状态轨迹
                   walkthrough 跳转触发 + fidelity 断言
                   visual    特效定帧
                 每帧过 4 重断言: 非黑 / 色数 / 主题色 / 帧间差异
P6 证据上贴      user-attachments 上传 (实测无 REST 端点, 用 web 上传链路)
                 → gh pr comment: 截图 + 转写 + 测试摘要; gist raw 为 fallback
P7 汇总          summary.json {layers, shots, classification} + 退出码
                 + workflow-audit.jsonl + 飞书通知 (🔴/✅)
P8 cleanup       trap EXIT 归属校验清理 (只删本实例创建的 worktree)
                 --keep 保留 WT 但仍释放锁 (merge --delete-branch 不被阻塞)

退出码: 0=全过  1=某层失败  2=pre-flight 失败  3=L3 降级 (逻辑层仍门禁)
```

## 4. shot plan 规范 (P4: 游戏管剧本)

```json
{
  "game": "mini-pong",
  "default_archetype": "loop",
  "state_node": "/root/Main/GameStateMachine",
  "state_property": "current_state",
  "theme_color": "4a90d9",
  "max_wall_seconds": 120,
  "autoplay": {
    "mode": "ai",                       // 或 "path": "neutral" (叙事游戏走剧本路径)
    "tweaks": [{"node": "/root/Main/AIPaddle", "prop": "ai_position_error", "value": 60}]
  },
  "groups": {
    "loop": {
      "match": ["gdscripts/game*.gd", "scenes/Main.tscn", "gdscripts/*.gd"],
      "shots": [
        {"name": "01_title",    "state": "MENU",     "settle_frames": 10},
        {"name": "02_midgame",  "state": "PLAYING",  "min_score_total": 1, "settle_frames": 5},
        {"name": "03_gameover", "state": "GAME_OVER", "settle_frames": 10}
      ]
    },
    "journey": {
      "match": ["dialogue/*.json", "gdscripts/narrative*.gd", "scenes/scene*.tscn"],
      "mode": "journey",
      "path": "neutral",
      "shots": [{"name": "j_open", "state": "SCENE_1", ...}, {"name": "j_ending", ...}],
      "transcript": true,
      "state_trajectory": true
    },
    "content_scene2": {
      "match": ["dialogue/scene2.json", "scenes/scene2.tscn"],
      "mode": "walkthrough",
      "fidelity": {"source": "dialogue/scene2.json"},
      "shots": [{"name": "c_open", "state": "SCENE_2", "trigger": "d2_open"}, ...]
    }
  }
}
```

**截图时机规则 (v1 讨论定稿):**
- 状态机驱动优先 (轮询 `state_node.state_property`, 帧数兜底 `at_frame`)
- 基线 3 帧: 起/中/终; 中帧必须带"游戏在动"证据 (`min_score_total: 1` 或位置变化)
- scope 帧: diff 触达的视觉项每项 +1; **总上限 5** (超过 = PR 过大, 本身就是 review finding)
- 每次截前后 settle_frames 稳定, 防半帧/淡入帧

**4 重防伪断言 (P6):** ①非黑 (avg 亮度) ②色数 ≥K ③主题色存在 (声明时) ④相邻帧 luminance delta 超阈值 (防冻屏/单帧循环)。全黑 = 捕获失败 = fail-fast, 黑图永不贴 PR。

**fidelity 断言 (内容型核心):** 进程内读对话 runner 当前节点 `Label.text`, 与 JSON 节点文本逐字相等 + 无占位符 (TODO/lorem/空说话人)。不需要 OCR。

**journey 三合一证据包:** ①沿途截图 (5-8 帧) ②对话全文转写 (玩一遍的文本等价物) ③状态轨迹 (回声/结局逻辑审计)。证据包默认递人工确认 (内容即审美, P3)。

## 5. 失败处理协议 (v2 核心新增, 六轮讨论定稿)

### 5.1 分类决策树 (证据先行)

```
本地 e2e 失败 (review session 内部)
  ├─ 0. 重试 1 次 (活机 flaky 保护)
  ├─ 1. 分类:
  │    A. 基建失败 (截图黑/超时/worktree 挂)  → 修 harness 或降级 L3 → infra issue
  │       不计 cycle, 不 block 逻辑层
  │    B. pre-existing (main 同样失败)        → status/blocked + fix issue (现有路径)
  │    C. 规格/审美偏差 (跑得起来但不对)      → REQUEST_CHANGES + 证据 → 人工拍板
  │    D. 代码缺陷 (崩溃/物理坏/循环挂)       → 本地收敛循环 ↓
  └─ 2. 本地收敛循环 (判据 = 本地 e2e, 不是 CI):
        review: 打 workflow/self-correct + 证据 comment (截图/日志/疑似根因)
        → event-processor 新规则 → SPAWN: self-correct,source=local-e2e
        → self-correct agent: 在 worktree 里修, 用 run-e2e-review.sh 自验
        → push → CI 绿 (仅回归保护)
        → check_run(success) → review 重新 spawn → 重跑本地 e2e ← 收敛判据
        → 绿 → merge; 红 → 下一轮
        → 2 轮上限 → 停止, 飞书升级人工 + 完整证据包 (三视角会诊)
```

### 5.2 为什么不能直接"继续 self-correct" (P2)

`SPAWN: self-correct` 只由 `check_run.completed(failure)` 触发; 本地 e2e 失败时 CI 是绿的
(绿了才会 spawn review) → 无事件。若强行走 CI 判据: self-correct 修 → push → CI 还是绿的
(CI 抓不到本地/真实渲染 bug) → review 再 spawn → 本地又红 → 无限循环, 永不收敛, 每轮烧全价成本。
**修复和验证必须在同一证据域。**

### 5.3 event-processor 最小补丁 (P5)

纯逻辑新规则 (event_processor_lib.py + 1 测试用例):
> 检测到 `workflow/self-correct` label 且该 issue 无 pending check_run(failure) 时,
> 输出 `SPAWN: self-correct,issue=N,pr=N,source=local-e2e`。

这个补丁同时修好现有盲区: review REQUEST_CHANGES 后流水线无确定性事件把 implement 拉回来
(现在靠 stalled scan 启发式, 模糊)。确定性规则 > 启发式兜底 (P5)。

### 5.4 成本治理 (P7)

- 本地 e2e cycle 复用现有 `count_self_correct_cycles` (🔄 marker) + `SELF_CORRECT_THRESHOLD=3`
- 本地上限 2 轮 (深层问题自动修复成功率低, 第 3 次接触必须是人工)
- A 类 (基建) 不计 cycle, 生成独立 infra issue 跟踪
- D 类证据 comment 附"疑似根因" (基于截图/日志的具体观察), 不给"怎么改" (防带偏)

### 5.5 可观测性

- 每次本地 e2e 结果写 `workflow-audit.jsonl` (watchdog + dashboard 已在读) + 飞书:
  `🔴 #N → 本地 e2e 失败 [分类:D, 第1/2轮]` — 修复全局视图的"review 为何耗时"盲区
- review 评论附 e2e 摘要 (结果可审计, 永不静默)

## 6. 内容型 issue 验收矩阵 (v2 泛化核心)

| 验收层 | 机制 | 谁执行 | 验什么 |
|--------|------|--------|--------|
| L1 结构 | schema + 完整性 + 海明威 + 引用有效 | 机器 headless | 内容填全、写对、格式合法 |
| L3 呈现 | walkthrough/journey 截图 + fidelity 断言 | 机器 L3 | 内容真的渲染进游戏、逐字一致 |
| L4 味道 | 读转写 + 看截图 + 制作人拍板 | 人 | 节奏、氛围、回声、对不对味 |

**深度阶梯 (diff scope 驱动):**
```
1 文件/错别字级      → L1 足够
单场景对话          → walkthrough
多场景/回声/结局    → journey (内容 issue 默认档, 保守)
重大里程碑/发布     → 3-tester 多路径 playtest (godot-playtest-protocol)
```

## 7. 依赖约束 (C5.5 组装 issue 强制项)

1. **autoplay 入口**: 玩法游戏 = AI 模式 (mini-pong 已有 paddle.mode); 叙事游戏 = 完整路径驱动
   (playtest protocol 的 tester paths 即现成剧本) + 对话自动推进 + **scene-jump/调试传送**
2. **shot plan**: 组装 issue 必须产出并提交 e2e_shots.json (框架不猜剧本)
3. **海明威约束**: 已在 `scripts/validate_hemingway.py` + GDScript DOMAIN_LIMITS 双端, 内容 PR 必过
4. 无 autoplay 的游戏: 内容原型退化 → 只验 L1 + 文本审阅, 或 playtest-protocol computer_use 走查

## 8. 实施顺序 (分阶段, 每阶段可独立验证)

```
Phase 1  机器层: analyze_bmp.py + capture 模板 + shots.json + runner + 全部单测 → 本地 61+ 全绿
Phase 2  mini-pong 实弹: 3 帧截图跑通 + 4 重断言 + 证据上贴实测 (锁定 user-attachments) 
Phase 3  失败协议: event-processor 补丁 + 单测 + review-agent skill 更新
Phase 4  内容原型: journey/walkthrough 在叙事游戏试点 (rainy-night-prometheus 或下一叙事 issue)
Phase 5  文档收敛: ARCHITECTURE.md + skill 同步 + 全量 CI 绿 → 合入
```

## 9. 开放问题 (待讨论)

| # | 问题 | 我的倾向 |
|---|------|----------|
| 1 | 帧间差异阈值 | 先收集真实样本再定参数 (数据优先) |
| 2 | journey 120s 超时: 硬失败 vs partial-loop 警告 | 硬失败 (剧本自声明, 到不了就是 bug) |
| 3 | C 类 (审美) 升级: 必人工 vs 带默认建议 | 带默认建议 (基于审美库), 但 merge 必须人工确认 |
| 4 | D 类 review 给不给"疑似根因" | 给观察, 不给方案 (防带偏) |
| 5 | 截图回流 Obsidian 审美库 | 升级人工时由制作人勾选, 其余留 PR 索引 |
| 6 | journey 的 tester 路径数量 | 默认 1 条 (中性), 发布级才 3 条 |

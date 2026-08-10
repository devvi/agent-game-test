# Perfect Dev Agent Workflow

> **两部分结构：** 这个项目是一个 **可复用的游戏开发 agent 框架**（`framework/`），当前实验游戏是 **mini-pong**（`mini-pong/`，Godot 4.7.1）。
> 架构单一事实源: `framework/ARCHITECTURE.md`。

## 框架 (framework/)

面向有经验的游戏制作人，把设计经验自动化为可重复的 agent 流程。

```
┌─ 你提 Issue ────────────────────────────────────────────────────┐
│  research agent → Obsidian 知识搜索 → PRD → PR → 自动合并        │
│  plan agent → 架构设计 + 测试描述 → PR → 自动合并                │
│  implement agent → OpenCode 分层实现 → PR → CI → review → merge  │
│  review agent → 本地 E2E (worktree + 真实渲染截图) → 证据上贴     │
└─────────────────────────────────────────────────────────────────┘
```

详见：
- `framework/ARCHITECTURE.md` — 系统架构、设计决策、已知限制（**单一事实源**）
- `framework/quickstart.md` — 游戏制作人 30 分钟上手
- `framework/templates/` — 模板文件副本（含 `e2e_capture.gd` 截图模板）
- `docs/PLAN-e2e-verification.md` — 本地 E2E 验证执行版方案

## 当前游戏 (mini-pong/)

所有关于游戏本身的代码、测试、文档都在 `mini-pong/`：
- `mini-pong/gdscripts/` — 游戏源码
- `mini-pong/tests/` — GDScript 测试（run_tests.gd 入口）
- `mini-pong/e2e_shots.json` — 游戏自持的 E2E shot plan（L3 视觉验证剧本）
- `mini-pong/project.godot` — 独立 Godot 项目（1280x720, resizable=false）

## Workflow Labels

| Label | Stage | 说明 |
|-------|-------|------|
| `workflow/available` | Available | Issue 创建后，等待处理 |
| `workflow/research` | Research | research agent 进行中 |
| `workflow/plan` | Plan | plan agent 进行中 |
| `workflow/implement` | Implement | implement agent 进行中 |
| `workflow/self-correct` | Fixing | CI 失败，自愈中 |
| `status/done` | Done | Issue 关闭 |

**Review 不在 label 链中。** Review agent 在 `check_run.completed` (CI 成功) 后、merge 前被调用。审核通过则 agent 直接 merge PR。详见 `game-review-agent` skill。

## Tech Stack

| 组件 | 用途 |
|------|------|
| Hermes Agent | Agent 运行时 + 事件路由 + cron |
| Godot 4.7.1 | 游戏引擎（CI 编译/测试/本地真实渲染截图） |
| OpenCode Serve | LLM 代码生成引擎（implement agent） |
| GitHub Issues | 任务队列 + 状态管理 |
| GitHub Actions | CI/CD 执行环境 |
| Obsidian | 知识库（设计笔记） |

## 游戏设计文档（GDD）

Workflow 持续产出 Issue 级的 PRD / DESIGN / TASKS，那是"用完即走"的碎片化知识。

**GDD（Game Design Document）** 是自动沉淀的统一入口——把所有系统的设计知识收敛到一处，结构化为分层文档。

```
docs/GAME_DESIGN/
├── INDEX.md          ← 目录 + 每章概要
├── 01-OVERVIEW.md    ← 游戏概述
├── 02-MOVEMENT.md    ← 移动与碰撞
├── 03-COMBAT.md      ← 战斗系统
├── ...
```

- **初版：** 手动从代码提取一次写完
- **增量更新：** Review agent 在每个 implement PR merge 后，读取 DESIGN doc 的架构决策/常量/数据流，写入对应 GDD 章节
- **不写入 GDD 的：** 代码 diff、测试用例、实施阶段——留在 PRD/DESIGN 中
- **约定文件：** `framework/templates/GDD_TEMPLATE.md`

GDD 的写作风格遵循"人读得懂，LLM 查得到"的原则：叙事体、层次编号、代码块放定义、表格放参数、段落讲意图。

详见 `docs/GAME_DESIGN/INDEX.md` 的维护规则。

## 本地 E2E 验证体系（2026-07-31 Phase 1 + 2026-08-10 实弹）

Review agent 在本地验证 implement PR，产出**真实渲染截图**作为 merge 证据：

```
PR → run-e2e-review.sh <PR_NUM>
  P0 pre-flight (caffeinate 防休眠)
  P1 worktree 隔离 (/tmp/wt-impl-<N>, 主工作区零污染)
  P2 L0 编译 → P3 L1 逻辑测试 → P4 L2 运行时
  P5 L3 视觉: e2e_capture.gd 真实渲染截图 + analyze_bmp.py 4 重防伪断言
      (非黑 / 色数 / 主题色 / 帧间差异) + assert_text 文本断言
  P6 证据 comment 到 PR → P7 summary.json → P8 worktree 清理 (trap)
```

- **截图通道**: Godot 进程内 `get_image().save_png()`（显示睡眠时系统截图 100% 纯黑，实测）
- **shot plan**: 游戏自持 `e2e_shots.json`（"框架管机器，游戏管剧本"），diff 驱动原型选择
- **失败协议**: A 基建(降级需证据) / B pre-existing / C 审美(人工) / D 代码缺陷(本地收敛循环，2 轮上限)

## Workflow 资产

框架的核心逻辑在 `agents/skills/` 下（版本控制），运行时通过 symlink 加载到 Hermes。

### Agent Skills

| Skill | 职责 | 位置 |
|-------|------|------|
| `game-research-agent` | Issue → PRD（含 Obsidian 搜索） | `agents/skills/game-research-agent/` |
| `game-plan-agent` | PRD → DESIGN（含测试用例描述，不写可运行测试文件） | `agents/skills/game-plan-agent/` |
| `game-implement-agent` | DESIGN → 代码 + 测试文件（OpenCode 分层实现） | `agents/skills/game-implement-agent/` |
| `game-review-agent` | 代码审查 + 本地 E2E + 合并决策 + post-merge GDD 更新 | `agents/skills/game-review-agent/` |
| `dev-workflow-dispatcher` | 事件调度 + 规则 | `agents/skills/dev-workflow-dispatcher/` |

### 确定性脚本 (`scripts/`)

Python 脚本在 cron tick 的 LLM 阶段之前运行，做纯数据加工：

| 脚本 | 职责 | 触发 |
|------|------|------|
| `event-processor.py` | 读取 pending 事件，分组/去重/排序，输出 SPAWN 指令（一次性消费，spawn gate 去重） | 每次 cron tick |
| `event_processor_lib.py` | 纯逻辑核心：优先级、时间窗口、依赖解析、配置合并 | 被 event-processor 引用 |
| `stage-gate.py` | PR 创建后验证 label/branch/body，自动修复 | 每个 phase agent 创建 PR 后 |
| `workflow-dispatcher.py` | 接收 webhook payload，写入 pending 文件（thin，不做 gh/git） | 每个 webhook 事件 |
| `workflow-watchdog.py` | 沉默 SPAWN 检测 + Feishu 告警 | cron every 5m (no-agent) |
| `run-e2e-review.sh` | 本地 E2E 主 runner（P0-P8，worktree + 截图 + 证据） | review agent 手动/自动调用 |
| `e2e/analyze_bmp.py` | PNG 4 重防伪断言（纯 stdlib） | runner L3 |
| `e2e/resolve_plan.py` | diff → 原型选择（loop/journey/walkthrough/visual） | runner P5 |
| `sync-to-hermes.sh` | 修改脚本后将项目副本同步到 `~/.hermes/scripts/` | 手动运行 |

> **改脚本的流程：** 改 `scripts/` 下的文件 → `./scripts/sync-to-hermes.sh` → commit + push。

## 配置与项目参数

- `~/.hermes/workflow-config.json` — 启停 + 工作时段 + preset（`best-deepseek` 多窗口 `[[0,9],[12,14],[18,24]]`）
- `game-env/manifest.yaml` — 项目配置单一来源（repo/engine/branch/槽位），**已入库**（P0，2026-07-31）

## Workflow 控制

通过 slash 命令或自然语言控制 workflow 运行状态：

| 命令 | 效果 |
|------|------|
| `/workflow status` | 查看状态：是否启用、预设、时间段、当前是否在工作时段 + **Webhook 连通性检查**（GitHub ping → 200） |
| `/workflow pause` | 暂停：event-processor 输出空 → 无 LLM 调用，事件累积 |
| `/workflow resume` | 恢复：启用 daytime 预设，下个 tick 正常处理 |
| `/workflow hours always` | 全天无限制 |
| `/workflow hours 9 23` | 自定义时间段 |

> **slash 命令不可用时：** gateway 重启前 /workflow 不会生效。用自然语言代替，如"暂停 workflow"、"workflow 什么状态"。
>
> **原理：** `scripts/event-processor.py` 每分钟读取 `~/.hermes/workflow-config.json`，判断是否在工作时间 + 是否启用。配置更改后下一个 cron tick 自动生效。
>
> **自动健康检查：** 每次进入工作时段时，`event-processor.py` 自动运行 `health_check()`，输出 `[HEALTH] gateway=200 ngrok=UP webhook=OK`。如果 webhook 不通，会在 stderr 打印告警。

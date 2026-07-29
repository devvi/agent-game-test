# PRD: [Feature] GameManager 全局状态

> **Issue:** #293
> **标签:** enhancement, workflow/research, depth/light, priority/high, version/mvp, estimate/small
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #301 (scaffold — CLOSED ✅), #291 (scoring system — CLOSED ✅)

---

## 1. 问题定义

### 当前状态

#291 的 ScoringManager 已经实现了计分逻辑——包括分数跟踪（`player_score`/`ai_score`）、局数管理（`player_games`/`ai_games`）、胜负判断（5分/2局）和信号链（`scored`→`game_won`→`match_over`）。但它有两个架构局限：

| 局限 | 细节 | 影响 |
|------|------|------|
| **场景级挂载** | ScoringManager 是 `game.tscn` 上的普通 Node，不是 autoload | 只能在 game 场景内访问；HUD、菜单、结束画面等跨场景组件无法直接读取状态 |
| **无全局 API** | 无 `reset_game()`、`reset_match()`、`get_winner()` 方法 | 无法从外部重置比赛或查询获胜者——状态完全封装在计分流程内部 |
| **信号命名差异** | 当前信号为 `scored(winner)`，issue 要求 `score_changed` | UI 连接点命名不一致 |
| **变量命名差异** | 当前用 `player_games`/`ai_games`，issue 要求 `player_games_won`/`ai_games_won` | 与 issue 规范略有偏差 |
| **无 autoload 注册** | `mini-pong/project.godot` 当前无任何 autoload 配置 | 无法全局访问 |

**当前信号流（完整但不可全局访问）：**

```
Ball._process() → ball.score(side: int)
    │
    ▼
ScoringManager._on_ball_score(side)
    ├── scored(winner)          ← 仅场景内可达
    ├── game_won(winner)        ← 仅场景内可达
    └── match_over(winner)      ← 仅场景内可达
```

### 预期行为

1. **autoload 注册：** 在 `mini-pong/project.godot` 中注册 GameManager 为 autoload 单例，全局可访问 `GameManager.player_score` 等
2. **全局状态管理：** 管理 `player_score`、`ai_score`、`player_games_won`、`ai_games_won`，作为计分状态的权威来源
3. **全局 API：** 提供 `reset_game()`（重置当局分数）、`reset_match()`（重置比赛状态）、`get_winner() -> String`（返回当前胜者或空字符串）
4. **信号层：** `score_changed(winner, p_score, a_score)`（每次得分）、`game_won(winner)`（每局结束）、`match_over(winner)`（比赛结束）
5. **编译验证：** `godot --path mini-pong/ --headless --quit` 无脚本错误

### 用户场景

| # | 场景 | 频率 |
|---|------|------|
| A | **UI 跨场景读取分数：** HUD（场景内）和结束画面（场景外）都能通过 `GameManager.player_score` 获取当前比分 | 持续 |
| B | **菜单重启比赛：** 用户在结束画面按 SPACE → 调用 `GameManager.reset_match()` 重置所有状态并重新开始 | 每场比赛结束 |
| C | **查询获胜者：** 结束画面调用 `GameManager.get_winner()` 显示 "Player Wins!" 或 "AI Wins!" | 每场比赛结束 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| GameManager autoload 脚本 + project.godot 注册 | UI 渲染（HUD、结束画面 — #292 后续） |
| `reset_game()`、`reset_match()`、`get_winner()` API | 得分暂停/发球逻辑（属于 ScoringManager — #291） |
| `score_changed`、`game_won`、`match_over` 信号 | 球物理信号发射（ball.gd — #287） |
| ScoringManager 适配：状态更新委托给 GameManager | 状态机编排（menu→playing→game_over — #294） |
| headless 编译验证 | 主场景组装（#295） |

### 范围边界 vs 重叠 PRD

| PRD | Covers | NOT covered (left to this PRD) |
|-----|--------|--------------------------------|
| #291 计分系统 | ScoringManager 的计分逻辑、暂停发球、信号层次 | ❌ 全局可访问性 — #291 的 ScoringManager 是场景级 Node，状态对外不可见。本 PRD 提供 autoload 全局访问层 |
| #287 球物理 | `ball.score(side)` 信号发射 | ❌ 全局状态管理 — #287 仅发射物理事件 |

---

## 2. 设计意图

### 为什么是现在

#291 的计分逻辑已完整实现并通过测试，但它将状态锁在场景内部。后续 features（HUD #292、结束画面、菜单重启 #294、主场景组装 #295）都需要跨场景访问计分状态。如果在每个后续 feature 中都通过场景树路径（`get_node("/root/Game/ScoringManager")`）访问状态，会导致紧耦合和脆弱的引用链。

从 #291 PRD 的架构决策：

> "autoload reserved for #293 GameManager" — PRD #291 §2.1

> "ScoringManager 是挂在 game.tscn 上的普通 Node（非 autoload），通过 @onready 引用 Ball 节点。这避免了 autoload 的全局状态耦合——autoload 封装留给 #293" — PRD #291 §2.2

#293 就是要填补这个刻意留下的架构空缺：将计分状态从场景级提升到全局级。

### 设计原则

1. **GameManager 为权威状态源：** 所有状态（分数、局数、比赛状态）以 GameManager 为准。ScoringManager 不再维护独立副本——它调用 GameManager 的方法更新状态
2. **最小破坏性变更：** ScoringManager 的计分逻辑和发球暂停逻辑保持不变。仅将其状态更新（`player_score += 1` 等）委托给 `GameManager.add_score(winner)`
3. **信号层次清晰：** GameManager 发射的 `score_changed` 携带完整上下文（winner + 双方分数），消费者无需再查询状态
4. **autoload 天然单例：** Godot 的 autoload 机制保证全局唯一实例，无需手动实现单例模式
5. **headless 兼容：** autoload 在 `--headless` 下正常工作——`get_tree()` 仍然有效（autoload 挂在 root 下）

### 先前约束

| 约束 | 来源 | 影响 |
|------|------|------|
| ScoringManager 为场景级 Node | #291 DESIGN | GameManager 不能直接替代 ScoringManager——需要适配 ScoringManager 使其委托状态给 GameManager |
| `ball.score(side: int)` 信号签名固定 | #287 ball.gd | GameManager 不直接连接 ball.score——通过 ScoringManager 间接接收 |
| `scored`/`game_won`/`match_over` 信号已存在 | #291 ScoringManager | GameManager 的 `score_changed` 是新增信号，不替代 ScoringManager 的现有信号 |
| autoload 名字为 "GameManager" | issue #293 标题 | autoload 注册名必须为 `GameManager`，全局访问路径 `/root/GameManager` |
| 常量 5/2 | issue #293 body + #291 | `POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2` 保持不变 |
| 默认分支为 `main` | 项目约定 | PR 分支名 `research/293-gamemanager-global-state`，PR 目标 `main` |

---

## 3. 影响分析

### 直接修改文件

| 文件 | 模块 | 变更性质 |
|------|------|----------|
| `mini-pong/project.godot` | autoload 注册 | **新增** `[autoload]` 段，注册 `GameManager` |
| `mini-pong/gdscripts/game_manager.gd` | GameManager autoload | **新增** 全局状态管理脚本 |
| `mini-pong/gdscripts/scoring_manager.gd` | ScoringManager | **修改** 状态更新委托给 GameManager |

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/gdscripts/game_manager.gd` | GDScript autoload | GameManager 全局单例：状态管理、API、信号 |

### 间接影响模块（不修改源码，仅信号消费方变化）

| 模块 | 影响 |
|------|------|
| `score_flash.gd` | 当前连接 `ScoringManager.scored`——在 GameManager 引入后，可选择连接 `GameManager.score_changed` 获得更丰富上下文（双方分数） |
| 后续 HUD (#292) | 直接连接 `GameManager.score_changed` 和 `GameManager.match_over` |
| 后续状态机 (#294) | 调用 `GameManager.reset_match()` 和 `GameManager.get_winner()` |
| `test_scoring_manager.gd` | 测试需适配——添加 GameManager 状态验证断言 |

### 数据流（变更后）

```
Ball._process()
    │ ball.score(side: int)
    ▼
ScoringManager._on_ball_score(side)
    │
    ├──► GameManager.add_score(winner)        ← 状态委托（新）
    │       ├── player_score += 1
    │       ├── emit score_changed(winner, p, a) ← 新增信号
    │       ├── Check 5 → emit game_won(winner)
    │       └── Check 2 → emit match_over(winner)
    │
    ├── emit scored(winner)                   ← 保留（向后兼容 score_flash）
    │
    └── await _pause_and_serve() → ball.serve()
```

### 文档更新

- [ ] `docs/GAME_DESIGN/14-SCORING-SYSTEM.md` — 添加 GameManager autoload 引用
- [ ] `docs/GAME_DESIGN/INDEX.md` — 添加 #293 条目

---

## 4. 方案对比

### 方案 A：GameManager 作为权威状态源（推荐）

GameManager 注册为 autoload，拥有所有计分状态（`player_score`、`ai_score`、`player_games_won`、`ai_games_won`）。ScoringManager 通过调用 `GameManager.add_score(winner)` 委托状态更新。GameManager 提供 `reset_game()`、`reset_match()`、`get_winner()` API 并发射 `score_changed`/`game_won`/`match_over` 信号。

**架构：**

```
┌─────────────────────────────────────────┐
│ GameManager (autoload, /root/GameManager)│
│ ─────────────────────────────────────── │
│ var player_score: int = 0               │
│ var ai_score: int = 0                   │
│ var player_games_won: int = 0           │
│ var ai_games_won: int = 0               │
│                                         │
│ signal score_changed(winner, p, a)       │
│ signal game_won(winner)                  │
│ signal match_over(winner)                │
│                                         │
│ func add_score(winner) → void           │
│ func reset_game() → void                │
│ func reset_match() → void               │
│ func get_winner() → String              │
└─────────────────────────────────────────┘
         ▲                       │
         │ add_score(winner)     │ signals
         │                       ▼
┌────────────────────┐    ┌──────────────┐
│ ScoringManager     │    │ HUD / End    │
│ (scene Node)       │    │ Screen / UI  │
│ ────────────────── │    │ (future #292)│
│ ball.score →       │    └──────────────┘
│   _on_ball_score() │
│   → GM.add_score() │
│   → pause + serve  │
└────────────────────┘
```

| 优点 | 缺点 |
|------|------|
| 状态单源——GameManager 是唯一真相源，无同步问题 | 需修改 ScoringManager 的状态更新逻辑（约 5 行变更） |
| 全局可访问——任意脚本通过 `GameManager.player_score` 读取 | ScoringManager 测试需要适配新增的 GameManager 依赖 |
| API 清晰——`reset_game()`/`reset_match()`/`get_winner()` 语义明确 | 引入 autoload 后 ScoringManager 测试必须实例化 GameManager |
| 信号完整——`score_changed` 携带双方分数，消费者无需二次查询 | |
| 最小破坏——ScoringManager 的暂停/发球逻辑完全保留 | |

**风险：** 低
**工作量：** 小（~70 行 game_manager.gd + ~5 行 scoring_manager.gd 修改 + project.godot 1 行）

---

### 方案 B：GameManager 作为只读观察者

GameManager 注册为 autoload，但不拥有状态——它通过连接 ScoringManager 的信号被动镜像状态。`reset_game()`/`reset_match()` 通过场景树引用直接操作 ScoringManager 的内部变量。

| 优点 | 缺点 |
|------|------|
| ScoringManager 零改动 | 状态双副本——ScoringManager 和 GameManager 各有一份，同步依赖信号传递的时序 |
| 纯增量——不碰已有代码 | autoload `_ready()` 早于场景 `_ready()`——ScoringManager 节点尚不存在，无法连接信号 |
| | `reset_game()` 需通过 `get_node("/root/Game/ScoringManager")` 操作私有变量——破坏封装 |
| | 信号命名不一致——ScoringManager 用 `scored`，GameManager 用 `score_changed`，形成冗余层 |
| | headless 测试中无场景树，GameManager 无法找到 ScoringManager |

**风险：** 高（时序依赖 + 双副本同步）
**工作量：** 中

---

### 方案 C：GameManager 替代 ScoringManager（激进重构）

将 ScoringManager 的全部逻辑（计分、暂停、发球）移入 GameManager autoload。ScoringManager 被完全移除。

| 优点 | 缺点 |
|------|------|
| 极简——唯一 autoload，无协作开销 | 大量破坏性变更——ScoringManager 的 112 行逻辑需重写和重新测试 |
| 无状态同步问题 | autoload 的 `_ready()` 在场景前运行——无法通过 `@onready var ball` 引用 Ball |
| | ball 引用需动态查找（`get_tree().get_first_node_in_group("ball")`），增加脆弱性 |
| | 发球逻辑（`ball.serve()`）从场景级移到全局级——违反关注点分离 |
| | ScoringManager 的现有测试（14 个测试用例）全部作废 |
| | #291 PRD 明确选择了 Scene Node 架构——推翻已合并的架构决策 |

**风险：** 高（大规模重构 + 测试重写）
**工作量：** 大（~150 行重写 + 14 个测试用例重写）

---

### 推荐：方案 A

**理由：**

1. **与 #291 的架构设计一致：** #291 PRD 和 DESIGN 均明确将 autoload 角色留给 #293。方案 A 是这一设计的自然延续——GameManager 增加全局访问层，ScoringManager 保留场景级逻辑
2. **状态单源：** 不存在双副本同步问题。GameManager 是唯一的数据源
3. **最小破坏性变更：** ScoringManager 仅需将 5 行状态更新（`player_score += 1`、`ai_score += 1`、分数重置、局数递增、`_is_match_over` 设置）替换为 GameManager 调用
4. **测试适配成本低：** 现有 14 个测试用例中，GameManager 作为 autoload 可通过 `Engine.get_main_loop().root.get_node("GameManager")` 访问——无需 mock
5. **方案 B 的时序问题不可解：** autoload `_ready()` 必然先于场景实例化——无法可靠连接 ScoringManager 信号
6. **方案 C 破坏性过大：** 推翻已测试的 #291 架构，且违反 autoload 不应管理场景级关注点（ball.serve()、暂停 timer）的原则

---

## 5. 边界条件与验收标准

### 验收标准（映射自 issue body）

- [x] **AC1: autoload 注册** — `mini-pong/project.godot` 中 `[autoload]` 段注册 `GameManager`，游戏启动后可通过 `/root/GameManager` 访问。验证：`godot --headless --quit` 不报错
- [x] **AC2: 全局状态管理** — `GameManager.player_score`、`GameManager.ai_score`、`GameManager.player_games_won`、`GameManager.ai_games_won` 全局可读写
- [x] **AC3: reset_game() API** — 调用 `GameManager.reset_game()` 将 `player_score` 和 `ai_score` 重置为 0，不改变局数
- [x] **AC4: reset_match() API** — 调用 `GameManager.reset_match()` 重置所有状态为初始值（4 个变量均为 0）
- [x] **AC5: get_winner() API** — 返回当前比赛胜者（`"player"` / `"ai"` / `""`），语义正确
- [x] **AC6: score_changed 信号** — 每次得分时发射 `score_changed(winner: String, player_score: int, ai_score: int)`
- [x] **AC7: game_won 信号** — 任意一方达到 5 分时发射 `game_won(winner: String)`
- [x] **AC8: match_over 信号** — 任意一方先赢 2 局时发射 `match_over(winner: String)`
- [x] **AC9: headless 编译** — `godot --path mini-pong/ --headless --quit` 退出码 0，无 SCRIPT ERROR

### 边界条件

1. **快速连续进球（信号风暴）：** 在 `_is_match_over` 已为 true 时，连续发射多个 `ball.score` 事件——GameManager 的 `_match_over` 守卫应阻止后续分数更新
2. **reset_game 在比赛中间调用：** 当局分数 3-2 时调用 `reset_game()`——分数重置为 0-0，局数不变
3. **reset_match 在比赛中间调用：** 某一方已赢 1 局时调用 `reset_match()`——所有状态归零，包括局数
4. **get_winner 在比赛中途调用：** 当前 1-0（无人赢 2 局）→ `get_winner()` 返回 `""`
5. **get_winner 在 ai_games_won=2 时调用：** 返回 `"ai"`；在 `player_games_won=2` 时返回 `"player"`
6. **双方同时达到 5 分（不可能但防御性处理）：** player_score 先检查 → 若 player>=5 则 player 赢，不检查 ai。Pong 中不可能同时达到（每次只有一个边界事件）
7. **score_changed 信号参数正确性：** 发射时 `player_score` 和 `ai_score` 参数反映的是递增后的值（不是递增前）
8. **headless 下 autoload 就绪：** `--headless --quit` 下 autoload 的 `_ready()` 正常执行，不依赖场景树节点

### 失败路径

1. **autoload 路径拼写错误：** `project.godot` 中 autoload 路径指向不存在的文件 → Godot 启动时报错，退出码非 0
2. **ScoringManager 在 GameManager 未就绪时调用 add_score：** 如果 GameManager 因 autoload 加载失败而不可用 → `push_error` + 计分静默失败。需在 `_ready()` 中验证 `GameManager != null`
3. **双 autoload 名称冲突：** 如果 project.godot 中已存在同名 autoload → Godot 启动报错

---

## 6. 依赖与阻塞

### 前置依赖

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #301 项目骨架 — 目录结构与 CI | ✅ CLOSED (status/done) | 无 — 目录结构已就绪 |
| #291 计分系统 — ScoringManager | ✅ CLOSED (status/done) | 无 — 计分逻辑已实现并通过测试 |

### 依赖链

```
#287 (球物理) ──► #291 (计分系统) ──► #293 (GameManager autoload — 本 Issue)
                                              │
                                              ▼
                                     #292 (#294, #295) 后续 UI/状态机
```

### 阻塞

| 后续工作 | 优先级 | 依赖本 Issue 的内容 |
|----------|:------:|-------------------|
| #292 UI 系统 (HUD) | high | `GameManager.score_changed` + `GameManager.player_score` |
| #294 状态机 | high | `GameManager.reset_match()` + `GameManager.get_winner()` + `GameManager.match_over` |
| #295 主场景组装 | high | GameManager autoload 就绪 |

### 前置准备

- [x] ScoringManager 已实现并测试通过（14 test cases passing）
- [x] `mini-pong/project.godot` 已存在，可直接添加 autoload 段
- [x] `mini-pong/tests/run_tests.gd` 支持 headless 测试框架

---

## 7. Spike / 实验

Skipped per `depth/light` label.

---

## 8. Continuation Context

### Handoff Summary

This PRD defines the GameManager autoload singleton for the Mini Pong project. The research confirmed that:

- **ScoringManager** (#291) already manages all score/game/match state as a scene Node, with 112 lines of tested GDScript
- **No autoload exists** anywhere in the project — `mini-pong/project.godot` has no `[autoload]` section
- **The architecture was designed for this split**: #291 intentionally left the autoload role for #293

The recommended approach (Approach A) creates GameManager as the authoritative state owner and minimally adapts ScoringManager to delegate state updates. This preserves all existing test coverage and scoring logic while adding the global API the downstream UI (#292) and state machine (#294) features require.

### Key Files for Plan Agent

| File | Status | Direction |
|------|:------:|-----------|
| `mini-pong/gdscripts/game_manager.gd` | → NEW | ~70 lines: autoload with state vars, signals, API methods |
| `mini-pong/project.godot` | → MODIFY | Add `[autoload]` section: `GameManager="*res://gdscripts/game_manager.gd"` |
| `mini-pong/gdscripts/scoring_manager.gd` | → MODIFY | 5-line change: delegate `player_score+=1`, `ai_score+=1`, score reset, game increment, `_is_match_over` set to `GameManager` method calls |
| `mini-pong/tests/test_scoring_manager.gd` | → MODIFY | Add GameManager autoload access + state assertions for `reset_game()`/`reset_match()`/`get_winner()` |

### Primary Risks

1. **ScoringManager test adaptation** — tests currently mock ball and manually set `sm.player_score`. After delegation, they need to assert against `GameManager` state. Godot 4 autoloads in headless are accessible via `Engine.get_main_loop().root.get_node("GameManager")`
2. **Signal naming consistency** — GameManager's `score_changed` vs ScoringManager's `scored`. The plan agent should decide: (a) keep both for backward compatibility, or (b) remove `scored` from ScoringManager and have consumers use `GameManager.score_changed` directly
3. **Autoload registration syntax** — Godot 4 autoload format in `project.godot`: `GameManager="*res://gdscripts/game_manager.gd"` (the `*` prefix indicates autoload singleton)

### Verified

- `godot --path mini-pong/ --headless --quit` currently exits 0 (verified by CI pipeline)
- ScoringManager test suite passes 14/14 tests
- No naming collisions with existing autoloads (project has none)

# PRD: [Feature] 计分系统 — Scoring System

> **Issue:** #291
> **标签:** enhancement, workflow/research, depth/light, priority/high, version/mvp, estimate/small
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #287 (ball physics — CLOSED ✅)

---

## 1. 问题定义

### 当前状态

Mini Pong 子项目的球物理系统（#287）已完成。现有基础设施：

| 组件 | 状态 | 细节 |
|------|:----:|------|
| `ball.gd` | ✅ | Area2D 球物理：手动 `_process` 运动、墙壁反弹、挡板碰撞、边界检测、`signal score(side: int)` |
| `ball.gd` 的 `score` 信号 | ✅ | 已定义并发射——球出右边界 → `score(0)`，球出左边界 → `score(1)` |
| `game.tscn` | ✅ | 含 TopWall, BottomWall, Ball, PlayerPaddle |
| `score_flash.gd` | ✅ | 已有闪烁控制器，等待计分系统连接（注释中标注 "to be wired by future scoring system issue"） |
| 计分逻辑 | ❌ | 无 `score` 信号监听者——球得分后无任何分数跟踪、无暂停发球、无胜负判断 |
| 局/比赛管理 | ❌ | 无 "5 分一局，先赢 2 局者胜" 逻辑 |
| 得分后暂停 | ❌ | 球出界后立即 `serve()` 重置，无 1 秒暂停 |
| `scored` / `match_over` 信号 | ❌ | 不存在——UI 和后续系统无得分通知 |
| AI 挡板 | ❌ | 未创建（#290 — 状态未知） |

**当前信号流（不完整）：**

```
Ball._process()
  ├── position.x < 0  → score.emit(1)  → ??? (无人监听)
  └── position.x > 1280 → score.emit(0) → ??? (无人监听)
```

### 预期行为

构建计分系统作为 `ball.gd` 的 `score` 信号消费者：

1. **监听球得分事件：** Connect 到 `ball.score` 信号。`score(0)` = 左方得分（玩家得分，球从右侧出界）；`score(1)` = 右方得分（AI 得分，球从左侧出界）
2. **分数跟踪：** 维护 `player_score` 和 `ai_score`。每得一分递增对应分数
3. **局胜负判断：** 任意一方先达到 5 分即赢得当前局。自动重置当局分数
4. **比赛胜负判断：** 先赢 2 局者赢得比赛。emit `match_over(winner)`
5. **得分后暂停：** 每次得分后，冻结游戏 1 秒（`await get_tree().create_timer(1.0).timeout`），然后触发 `serve()`
6. **信号链完整：** `scored` 信号（通知 UI 更新分数和闪烁）→ `match_over` 信号（通知 UI 显示结束画面）
7. **编译验证：** `godot --path mini-pong/ --headless --quit` 无脚本错误

### 用户场景

| # | 场景 | 频率 |
|---|------|------|
| A | **回合得分：** 球飞出右边界 → 玩家得分，HUD 更新分数，画面闪烁蓝光，1 秒后重新发球 | 每回合结束 |
| B | **AI 得分：** 球飞出左边界 → AI 得分，HUD 更新分数，画面闪烁红光，1 秒后重新发球 | 每回合结束 |
| C | **局胜利：** 某方先达到 5 分 → `game_won` 信号，局数递增，当局分数重置 | 每局结束 |
| D | **比赛结束：** 某方先赢 2 局 → `match_over(winner)` 信号，通知 UI 系统显示结束画面 | 每场比赛结束 |
| E | **发球暂停：** 得分后画面暂停 1 秒（球静止在中心），玩家有时间看清分数变化 | 每次得分后 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| `scoring_manager.gd` — 监听 `ball.score` 并管理分数/局/比赛 | UI 渲染（HUD 文字、结束画面 — #292） |
| `scored(winner: String)` 信号 | GameManager autoload（#293 — 全局状态单例） |
| `match_over(winner: String)` 信号 | 游戏状态机（menu→playing→game_over — #294） |
| "5 分一局，先赢 2 局者胜" 逻辑 | AI 对手挡板（#290） |
| 得分后 1 秒暂停 + 重新发球 | 音效（#296） |
| `game_won(winner)` 信号（局胜利中间信号） | SPACE 重启逻辑（#294） |
| 与 `score_flash.gd` 的信号连接 | 主场景组装（#295） |

### 范围边界 vs 重叠 PRD

| PRD | Covers | NOT covered (left to this PRD) |
|-----|--------|--------------------------------|
| #287 球物理 | `ball.gd` 的 `score(side)` 信号发射 | ❌ 信号的消费者——#287 仅发射信号，不跟踪分数 |
| #293 GameManager autoload | 全局状态管理、`reset_game()`/`reset_match()`/`get_winner()` API | ❌ #291 的计分逻辑可独立运行，不依赖 autoload；#293 将在 #291 基础上封装全局 API |
| #289 霓虹视觉 | `score_flash.gd` 闪烁控制器 | ❌ 闪烁的触发连接——`score_flash.gd` 注释明确标注 "to be wired by future scoring system issue" |

**本 PRD 是计分系统的核心逻辑层**——它连接球物理的信号发射与 UI/GameManager 的信号消费。它不负责 UI 渲染（#292）、全局状态管理 API（#293）、或状态机编排（#294）。

---

## 2. 设计意图

### 为什么是现在

#287 的球物理已完整实现 `score(side)` 信号发射——球每次出边界都会 emit score 事件。但当前**无人监听此信号**，分数事件被静默丢弃。计分系统是连接物理层（ball.gd）与表现层（UI、音效、闪光）的关键中间件。

从 `game-to-issues-mini-pong.json` 的设计上下文：

> "得分是连接物理、UI、音效的核心事件。信号链必须完整。"

当前的信号链断裂点恰好在 `ball.score` → ??? 这一段。#291 填补这个空白。

### 设计原则

1. **信号驱动：** 计分逻辑完全由 `ball.score(side)` 信号触发。不做轮询、不做主动检查。这是事件驱动架构的标准模式
2. **自包含节点：** ScoringManager 是挂在 `game.tscn` 上的普通 Node（非 autoload），通过 `@onready` 引用 Ball 节点。这避免了 autoload 的全局状态耦合——autoload 封装留给 #293
3. **最小依赖：** 只依赖 `ball.gd` 的信号接口（`score` 信号 + `serve()` 方法）。不依赖 UI 系统、音效系统、或状态机
4. **清晰的信号层次：**
   ```
   ball.score(side)         ← 物理层（已实现）
        │
   ScoringManager            ← 计分层（本 Issue）
        │
        ├── scored(winner)   ← 通知 UI 更新分数
        ├── game_won(winner)  ← 通知局胜利
        └── match_over(winner) ← 通知比赛结束
   ```
5. **暂停行为一致：** 得分后 1 秒暂停通过 `await get_tree().create_timer(1.0).timeout` 实现，然后调用 `ball.serve()`。这与 `ball.gd` 的发球延迟（0.5s `SERVE_DELAY`）组合后总暂停为 1.5s

### 先前约束

| 约束 | 来源 | 影响 |
|------|------|------|
| `ball.score` 信号签名: `score(side: int)` | #287 ball.gd | side=0 为左方得分（玩家），side=1 为右方得分（AI） |
| `ball.serve()` 方法自带 0.5s 发球延迟 | #287 ball.gd | 计分系统暂停 1s + 发球延迟 0.5s = 总计 1.5s 间隔 |
| `ball._is_serving` 标志阻止 `_process` 运动 | #287 ball.gd | 得分后 `_is_serving=true` 自然冻结球——不需要额外冻结逻辑 |
| `game.tscn` 已含 Ball、PlayerPaddle、墙壁 | #287+#288 实现 | ScoringManager 可直接 `@onready var ball = $Ball` |
| 默认分支为 `main` | 项目约定 | PR 分支名 `research/291-scoring-system`，PR 目标 `main` |

---

## 3. 影响分析

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/gdscripts/scoring_manager.gd` | GDScript | 计分系统：监听 `ball.score`，管理分数/局/比赛，发射 `scored`/`match_over` 信号 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `mini-pong/scenes/game.tscn` | 添加 `ScoringManager` Node，挂载 `scoring_manager.gd` 脚本 |

### 间接影响模块（仅信号连接，不修改源码）

| 模块 | 影响 |
|------|------|
| `score_flash.gd` | `scoring_manager.scored.connect(score_flash._on_score_changed)` — 已有回调方法，仅需连接信号 |
| `ball.gd` | 无修改——`ScoringManager.connect("score", ...)` 是外部连接 |
| 后续 UI 系统 (#292) | 连接 `scored` 更新 HUD，连接 `match_over` 显示结束画面 |
| 后续 GameManager (#293) | 封装计分 API，但 #291 的计分逻辑独立运作 |

### 数据流

```
Ball (Area2D) — score(side: int) signal
    │
    ▼
ScoringManager (Node) — _on_ball_score(side)
    │
    ├── 识别得分方: side=0 → "player", side=1 → "ai"
    ├── 递增分数
    ├── emit scored(winner: String)         ← UI 更新 + 闪烁
    │
    ├── 检查局胜负: score >= 5?
    │   ├── YES → emit game_won(winner)     ← 局胜利通知
    │   │        reset scores to 0
    │   │        increment games_won
    │   │
    │   │        检查比赛胜负: games_won >= 2?
    │   │        ├── YES → emit match_over(winner)  ← 比赛结束通知
    │   │        └── NO  → continue
    │   │
    │   └── NO → continue
    │
    └── 暂停 1 秒 → ball.serve()            ← 重新发球
```

### 文档更新

- 无需更新现有文档

---

## 4. 方案对比

### 方案 A：ScoringManager Node + 信号连接（推荐）

在 `game.tscn` 中添加 `ScoringManager` Node，挂载 `scoring_manager.gd`。脚本在 `_ready()` 中连接到 `ball.score` 信号，管理所有计分逻辑。

```
game.tscn 节点树（变更后）:
Game (Node2D)
├── TopWall
├── BottomWall
├── Ball
├── PlayerPaddle
└── ScoringManager (Node)        ← 新增
```

**ScoringManager 核心逻辑：**

```gdscript
extends Node

signal scored(winner: String)       # "player" | "ai"
signal game_won(winner: String)     # "player" | "ai"
signal match_over(winner: String)   # "player" | "ai"

const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

@onready var ball: Area2D = $"../Ball"

var player_score: int = 0
var ai_score: int = 0
var player_games: int = 0
var ai_games: int = 0


func _ready() -> void:
    ball.score.connect(_on_ball_score)


func _on_ball_score(side: int) -> void:
    var winner := "ai" if side == 1 else "player"
    
    # Increment score
    match winner:
        "player": player_score += 1
        "ai":     ai_score += 1
    
    scored.emit(winner)
    
    # Check game win
    if player_score >= POINTS_TO_WIN_GAME:
        _win_game("player")
    elif ai_score >= POINTS_TO_WIN_GAME:
        _win_game("ai")
    else:
        # Pause then serve
        await _pause_and_serve()


func _win_game(winner: String) -> void:
    game_won.emit(winner)
    match winner:
        "player": player_games += 1
        "ai":     ai_games += 1
    player_score = 0
    ai_score = 0
    
    # Check match win
    if player_games >= GAMES_TO_WIN_MATCH:
        match_over.emit("player")
        return
    elif ai_games >= GAMES_TO_WIN_MATCH:
        match_over.emit("ai")
        return
    
    await _pause_and_serve()


func _pause_and_serve() -> void:
    var tree := get_tree()
    if tree:
        await tree.create_timer(1.0).timeout
    ball.serve()
```

| 优点 | 缺点 |
|------|------|
| 自包含——单一文件实现完整计分逻辑 | 需修改 `game.tscn` 添加节点 |
| 信号层次清晰——ball.score → scored → match_over | 通过 `$"../Ball"` 引用 Ball（依赖场景树布局） |
| 符合 Godot 场景化设计——ScoringManager 是独立可替换组件 | `await` 在 headless test 中需特殊处理（无 tree context） |
| 无全局状态——不被 autoload 污染 | |
| `@export` 可调参数（POINTS_TO_WIN_GAME, GAMES_TO_WIN_MATCH）便于平衡调整 | |

**风险：** 低
**工作量：** 小（~80 行 GDScript + game.tscn 添加一个 Node）

---

### 方案 B：Autoload ScoringManager

将 ScoringManager 注册为 autoload（在 `project.godot` 中），全局单例管理分数。

| 优点 | 缺点 |
|------|------|
| 任何脚本可直接访问 `ScoringManager.player_score` | 与 #293 GameManager autoload 职责重叠——两个 autoload 管理同一数据 |
| 不需要场景树引用 Ball | autoload 的 `_ready()` 时机不确定——可能在 Ball 实例化之前 |
| | 违反 #291 是"计分系统"而非"全局状态管理器"的职责边界 |
| | autoload 注册需修改 `project.godot`（增加 CI 风险） |

**风险：** 中（职责重叠 + autoload 注册复杂性）
**工作量：** 中

---

### 方案 C：扩展 `ball.gd` 内联计分逻辑

在 `ball.gd` 的 `_process()` 中直接添加计分变量和胜负判断。

| 优点 | 缺点 |
|------|------|
| 零新文件 | 违反单一职责原则——ball 管理物理 + 计分 + 比赛状态 |
| 无信号连接 | `match_over` 信号定义在 ball 上不合理（ball 不拥有"比赛"概念） |
| | 修改 `ball.gd` 增加回归风险（#287 已通过测试） |
| | ball 不应知道 "5 分一局" 这种高层规则 |

**风险：** 高（破坏现有物理逻辑的清晰边界）
**工作量：** 小（但技术债务高）

---

### 推荐：方案 A

对于 Mini Pong 计分系统，方案 A 是最佳选择：

1. **职责清晰：** ScoringManager 拥有计分和比赛规则，ball 拥有物理行为。符合单一职责原则
2. **信号链完整：** `ball.score → ScoringManager → scored/match_over`，清晰的三层信号架构
3. **与 #293 不冲突：** #293 的 GameManager autoload 可以在方案 A 基础上封装（读取 `player_score` 等状态），而非替代它
4. **可测试性：** ScoringManager 可以独立实例化，手动触发 `_on_ball_score(0)` 验证分数跟踪、局胜负、比赛胜负
5. **最小修改面：** 仅新增一个文件 + game.tscn 一行节点声明

---

## 5. 边界条件与验收标准

### 验收标准

- [ ] **AC1: 球出左边界 → AI 得分** — 球飞出左边界（`position.x < -BALL_RADIUS`）→ `ball.score(1)` → ScoringManager `ai_score += 1` → `scored("ai")` 信号
- [ ] **AC2: 球出右边界 → 玩家得分** — 球飞出右边界（`position.x > screen_width + BALL_RADIUS`）→ `ball.score(0)` → ScoringManager `player_score += 1` → `scored("player")` 信号
- [ ] **AC3: 5 分一局，先赢 2 局者胜** — 某方先达到 5 分 → `game_won(winner)` 信号 + 分数重置 + 局数递增。某方先达到 2 局 → `match_over(winner)` 信号
- [ ] **AC4: 得分后暂停 1 秒再发球** — `_on_ball_score()` → `await 1.0s` → `ball.serve()`（ball 自身有 0.5s 发球延迟，总计 ~1.5s）
- [ ] **AC5: scored(winner) 和 match_over(winner) 信号** — `scored` 信号在每次得分后立即发射，`match_over` 信号在比赛结束时发射。参数为 `"player"` 或 `"ai"` String
- [ ] **AC6: --headless --quit 无脚本错误** — `godot --path mini-pong/ --headless --quit` 退出码 0，无 SCRIPT ERROR

### 边缘情况

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | 比赛结束后球继续出界 | `match_over` 发射后不再处理 `ball.score` 信号——添加 `_match_over: bool` 标志阻止进一步计分 |
| 2 | 同时达到 5 分（不可能但防御） | 先检查 player 再检查 ai——顺序决定优先级。Pong 中不可能同时 5 分（每次只有一方得分） |
| 3 | `ball.serve()` 在暂停期间被重复调用 | `ball._is_serving` 标志阻止重复发球——`serve()` 设置 `_is_serving=true`，`_process` 跳过运动 |
| 4 | headless 模式下 `await timer` 失效 | 在 `_pause_and_serve()` 中检查 `get_tree()` 是否为 null→ 直接调用 `ball.serve()` 跳过等待 |
| 5 | 得分后立即再次得分（球在边界附近震荡） | `ball.serve()` 将球重置到中心（`_is_serving=true`），发球前球不运动，不存在震荡 |
| 6 | 局胜利后发球方向 | 局胜利后仍随机发球方向（与正常回合相同），不做特殊处理 |
| 7 | `player_score` 未重置导致下一局起始非 0 | `_win_game()` 中显式 `player_score = 0; ai_score = 0` |
| 8 | 多次快速得分（headless 模拟） | `_pause_and_serve()` 的 `await` 确保 1s 间隔——快速连续 `_process` 帧不会突破 |

### 失败路径

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | Ball 节点不存在（game.tscn 中缺少 Ball） | `@onready var ball` 为 null → `_ready()` 中断言 `assert(ball != null)` |
| 2 | `ball.score` 信号发射但 ScoringManager `_ready()` 尚未执行 | Godot 场景树 `_ready()` 顺序：子节点优先。ScoringManager 添加在 Ball 之后 → `ready()` 在 Ball 之后执行。需在 `_ready()` 连接信号前确保 Ball 已就绪 |
| 3 | `match_over` 后 UI 未连接（无监听者） | 信号发射无副作用——只是事件丢失。不导致崩溃 |

---

## 6. 依赖与阻塞

> ℹ️ 本节可选（`depth/light`），但因 #291 有明确的依赖链，列入以供 Plan Agent 参考。

### 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|------|
| #287 球物理与碰撞 | ✅ CLOSED — ball.gd 已实现 `score(side)` 信号 + `serve()` 方法 | 无 |
| #301 项目骨架 | ✅ CLOSED — mini-pong/ 目录结构、project.godot 已就绪 | 无 |
| Ball 场景存在于 game.tscn | ✅ — game.tscn 含 Ball 实例 | 无 |

### 阻塞（后续 Issue）

| 后续工作 | 优先级 | 关系 |
|---------|:------:|------|
| #292 UI 系统（HUD + 菜单 + 结束画面） | critical | 依赖 `scored` 和 `match_over` 信号 |
| #293 GameManager autoload | high | 封装 #291 计分逻辑为全局 API |
| #294 游戏状态管理 | high | 状态机中的 `scored` 和 `game_over` 状态由 `scored`/`match_over` 触发 |
| #296 音效 | medium | 依赖得分事件触发音效 |

### 依赖链

```
#287 (ball physics, signal: score) ──► #291 (scoring system)
                                          │
                                          ├──► #292 (UI: HUD display)
                                          ├──► #293 (GameManager autoload)
                                          ├──► #294 (Game state machine)
                                          └──► #296 (Sound effects)
```

---

## 8. 延续上下文（Plan Agent 交接）

### 当前系统状态

- `mini-pong/gdscripts/ball.gd` — Area2D 球物理，`signal score(side: int)` 已定义并发射（L25-26, L121-126），`serve()` 含 0.5s 发球延迟（L62-88）
- `mini-pong/gdscripts/score_flash.gd` — 闪烁控制器已实现 `flash(color)` 和 `_on_score_changed(scoring_side)` 回调方法（L43-48），等待信号连接
- `mini-pong/scenes/game.tscn` — 含 TopWall, BottomWall, Ball, PlayerPaddle 节点。未含 AI Paddle 或 ScoringManager
- `mini-pong/project.godot` — `run/main_scene="res://scenes/game.tscn"`，无 autoload
- `mini-pong/tests/test_ball.gd` — 球物理测试（22 个测试），含 `_test_score_right_e1()` 和 `_test_score_left_e2()` 验证 score 信号发射
- `mini-pong/tests/run_tests.gd` — 加载 test_ball, test_paddle, test_neon

### 实施注意事项

1. **文件位置：** `scoring_manager.gd` 放在 `mini-pong/gdscripts/`，脚本挂载到 `game.tscn` 的新 Node 上

2. **game.tscn 节点变更：**
   ```
   [node name="ScoringManager" type="Node" parent="."]
   script = ExtResource("3_scoring_manager")
   ```
   需要新增 `[ext_resource]` 条目引用 `scoring_manager.gd`

3. **信号签名（与后续系统兼容）：**
   ```gdscript
   signal scored(winner: String)       # "player" | "ai"
   signal game_won(winner: String)     # "player" | "ai"
   signal match_over(winner: String)   # "player" | "ai"
   ```
   使用 String 而非 int——与 `score_flash.gd` 的 `_on_score_changed(scoring_side: String)` 参数类型一致（L43）

4. **Ball 引用模式：**
   ```gdscript
   @onready var ball: Area2D = $"../Ball"
   ```
   因为 ScoringManager 和 Ball 是 game.tscn 的平级子节点

5. **headless 兼容：** `_pause_and_serve()` 中检查 `get_tree()`：
   ```gdscript
   func _pause_and_serve() -> void:
       var tree := get_tree()
       if tree:
           await tree.create_timer(1.0).timeout
       ball.serve()
   ```
   这与 `ball.gd` 的 `serve()` 中 headless 处理模式一致（L71-79）

6. **比赛结束保护：**
   ```gdscript
   var _is_match_over: bool = false
   
   func _on_ball_score(side: int) -> void:
       if _is_match_over:
           return
       # ... scoring logic
   
   func _win_game(winner: String) -> void:
       # ...
       if player_games >= GAMES_TO_WIN_MATCH or ai_games >= GAMES_TO_WIN_MATCH:
           _is_match_over = true
           match_over.emit(...)
   ```

7. **验证方法：**
   ```bash
   # 编译验证
   godot --path mini-pong/ --headless --quit
   echo "Exit: $?"
   
   # 测试验证（需在 run_tests.gd 中添加 test_scoring.gd）
   godot --path mini-pong/ --headless --script tests/run_tests.gd
   ```

8. **测试文件建议（非本 PRD 必需）：**
   创建 `mini-pong/tests/test_scoring.gd`，测试：
   - TC-S1: `_on_ball_score(0)` → player_score 递增
   - TC-S2: `_on_ball_score(1)` → ai_score 递增
   - TC-S3: 5 分触发 `game_won` → 分数重置
   - TC-S4: 2 局触发 `match_over` → `_is_match_over` 为 true
   - TC-S5: `match_over` 后额外 score 信号被忽略
   - TC-S6: `scored` 信号参数为 "player"/"ai" String

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|:------:|:----:|---------|
| `_ready()` 顺序：Ball 未就绪时 ScoringManager 连接信号 | 低 | 高（信号未连接） | Godot 场景树 `_ready()` 顺序：子节点优先，平级节点按 TSCN 声明顺序。ScoringManager 声明在 Ball 之后即可 |
| headless 模式下 `await` 行为异常 | 低 | 中（暂停逻辑不工作） | 检查 `get_tree()` 是否为 null，跳过 timer |
| `match_over` 后 UI 未连接导致事件丢失 | 中 | 低（功能上不影响后续运行） | 在信号文档中注明必须连接 |
| game.tscn 修改冲突（与 #290 AI paddle 并发修改） | 中 | 中（git 合并冲突） | ScoringManager 节点独立——与 AI paddle 节点不冲突，TSCN merge 友好 |

### 设计决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 架构模式 | Node（非 autoload） | 计分逻辑是场景级关注点，autoload 留给 #293 GameManager |
| 信号参数类型 | `String` ("player"/"ai") | 与 `score_flash.gd` 的现有回调匹配 |
| 暂停实现 | `await get_tree().create_timer(1.0).timeout` | 简单，与 ball.gd 的 serve delay 模式一致 |
| 局数/比赛数 | 硬编码常量 `POINTS_TO_WIN_GAME=5` `GAMES_TO_WIN_MATCH=2` | Issue 明确要求，后续可改为 `@export` |
| Ball 引用方式 | `@onready var ball = $"../Ball"` | 简单直接，场景树相对路径 |

### 下一步

Plan Agent 将基于此 PRD 创建 `docs/DESIGN/291-scoring-system.md`，详细指定：
- `scoring_manager.gd` 完整 API（信号、变量、方法）
- `game.tscn` 的节点变更（TSCN 代码段）
- 信号连接规范（ScoringManager ↔ score_flash）
- 状态转换图（得分 → 局胜 → 比赛结束）
- 测试用例规格（TC-S1 至 TC-S6）

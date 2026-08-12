# DESIGN: [Feature] 双得分制 (Dual Scoring System)

> **Parent Issue:** #385
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — ScoringManager 集中消费 + GameManager 扩展（确认 PRD §4 推荐；不动信号链分层，穿墙分复用现有出界得分路径）
> **Reference PRD:** docs/PRD/385-dual-scoring.md（research PR #417，已合并）
> **所有权:** `content_ownership: mechanical`（分值/计数/终局判定为机械规则；HUD 双区视觉与结算文案归 #392/#393）
> **深度:** depth/standard —— 仅产出 DESIGN 文档；不产出 TASKS 文档；测试仅描述不写代码

---

## 1. 概述

Mini Pong（720×1280 竖屏，#383 后）当前只有**单一得分路径**：球出界 → `ball.score(side)` → ScoringManager → `GameManager.add_score(winner)` 每次 +1 分，5 分一局、2 局一场（constants.gd:76-77）。本设计引入**双得分制**：拆砖 +1 分（归最后触球方）、穿墙（出界） +3 分（归攻击方）、任意一方先到 **21 分**终局，并让 GameManager 提供拆砖数/穿墙数查询接口（AC5，供 #391 失败屏 / #390 波次转场消费）。

**Plan 阶段边界**：本阶段只产出本文档，不碰任何 `.gd` / `.tscn` 文件 —— 下列全部内容为 implement agent 的契约。**Main.tscn 接线不在本 Issue**（归 #393，见 §10 边界）。

### 设计哲学

1. **机械映射、单一权威**：分值/阈值/终局判定是纯机械规则。**终局判定唯一权威 = GameManager**（AC3 原文要求"GameManager 进入终局状态"；源码已核实 FSM/GameOverScreen 只监听 `GameManager.match_over`、HUD 只监听 `GameManager.score_changed`）—— ScoringManager 不再本地发射 game_won/match_over，避免双权威重复发射
2. **计分入口单一**：ScoringManager 是场景内唯一信号消费方（出界 + 拆砖），GameManager 只做数据记账与终局判定 → AC4 防重天然成立
3. **scored 信号语义边界（关键决策 D2）**：`scored` 只表示"回合结束、需要重新发球"。源码已核实 `FSM._on_scored → SCORED → 1s 后 serve`（game_state_machine.gd:171-175）—— **拆砖计分是回合中事件，绝不发射 `scored`**；只有穿墙出界（回合结束）才发射
4. **零新增物理检测**：竖屏下砖墙横跨 720px、左右墙封死 X 轴，出界必经砖墙平面（#384 事实核查 + PRD §7 实验 1）→ 穿墙分 = 现有出界得分路径分值 1→3
5. **最小触碰面**：ball.gd 仅加 `last_toucher`（~5 行）；scoring_manager.gd 只扩展消费逻辑；HUD/FSM/GameOverScreen/Main.tscn 零改动

---

## 2. 现状核实（plan agent 已对照源码确认）

| 文件 | 现状（已核实） | 与 #385 的差距 |
|------|---------------|---------------|
| `mini-pong/gdscripts/constants.gd` | `POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2`（#295 单一事实源） | ❌ 无 `POINTS_BRICK`/`POINTS_WALL_PASS`；阈值 5/2 需改 21/1 |
| `mini-pong/gdscripts/game_manager.gd` | `add_score(winner)` 固定 +1；`_check_game_win()` 5 分触发 `_win_game`；`game_won`/`match_over` 信号；FSM/GameOverScreen/HUD 均监听**本节点**信号 | ❌ 无分值参数；无拆砖/穿墙计数与查询接口（AC5）；阈值 5→21（AC3） |
| `mini-pong/gdscripts/scoring_manager.gd` | 消费 `ball.score(side)` → side 映射 winner → 本地镜像 +1 → `scored.emit` → `GameManager.add_score(winner)` → 本地 `_win_game` 终局检查（其 game_won/match_over **场景内无消费者**，已核实 Main.tscn/FSM 均未连接） | ❌ 不消费 `brick_destroyed`（AC1）；分值无 3 分语义（AC2）；本地终局检查与 GameManager 双权威需收敛（D1） |
| `mini-pong/gdscripts/ball.gd` | `_on_area_entered` paddles 分支处理反弹；`serve()` 随机方向发球；`_scored_this_frame` 同帧防双触发（#295） | ❌ 无 `last_toucher`（AC1 归属前提） |
| `mini-pong/gdscripts/paddle.gd` | `enum Mode { PLAYER=0, AI=1 }` + `@export var mode`；Main.tscn PlayerPaddle mode=0、AIPaddle mode=1（#383 已核实） | ✅ 零改动 —— ball 借 `area.mode` 判定最后触球方 |
| `mini-pong/scenes/Main.tscn` | 无 BreakoutGrid 节点 | ✅ 本 Issue 不改（#393 接线；`get_node_or_null` best-effort 连接） |
| `mini-pong/gdscripts/breakout_grid.gd` | **不在 main**（#384 仅 PRD/DESIGN 合并，实现未落地 —— 2026-08-13 核实） | ⚠️ `brick_destroyed(brick, pos)` 契约以 docs/DESIGN/384 §3.4 为准；implement 前需确认 #384 落地（PRD §6 风险，Med-High） |
| `mini-pong/tests/test_constants.gd` | TC6-18/19 断言 `POINTS_TO_WIN_GAME==5`、`GAMES_TO_WIN_MATCH==2` | ❌ 断言需更新 + 新增双得分常量断言 |
| `mini-pong/tests/test_game_manager.gd` | 15 用例：+1 计分、5 分 game_won、2 局 match_over（TC6 等） | ❌ 阈值用例改 21/1；新增计数/查询/重置用例 |
| `mini-pong/tests/test_scoring_manager.gd` | 42 用例：side→winner、5 分制本地终局、post-match guard（文件内硬编码 `POINTS_TO_WIN_GAME=5`/`GAMES_TO_WIN_MATCH=2`） | ❌ 终局用例改断言 GameManager 信号；分值断言 1→3；新增 brick_destroyed 消费/防重用例 |
| `mini-pong/tests/test_integration_fsm.gd` | 用 `GameManager.add_score()` 驱动 FSM | ⚠️ add_score 兼容别名保留则编译兼容；5 分不再触发 game_won 的语义变化需核对（见 §7.4） |
| `mini-pong/tests/run_tests.gd` | 注册 14 套件（+auto_play） | ❌ 若新建 test_dual_scoring.gd 需注册 |

---

## 3. 架构与数据流（核心契约）

### 3.1 关键决策 D1 — 终局判定单一权威 = GameManager

| 断言 | 源码事实 | 设计裁决 |
|------|---------|---------|
| PRD 数据流：`GameManager.add_points` 达 21 分 → `game_won` + `match_over` | FSM 连 `GameManager.match_over`（game_state_machine.gd:47-50）；GameOverScreen 连 `GameManager.match_over`（game_over_screen.gd:31-34）；HUD 连 `GameManager.score_changed`（game_hud.gd:16-20）；ScoringManager 的 game_won/match_over **无任何消费者** | **终局判定与 game_won/match_over 发射全部收敛到 GameManager**；ScoringManager 移除本地 `_win_game` 检查路径（其 `player_games`/`ai_games` 计数随之移除），`_is_match_over` 守卫改为监听 `GameManager.match_over` 置位 |

**为什么收敛**：双权威（ScoringManager 本地 + GameManager）在 21 分制下必然同时触发，产生两套 `game_won`/`match_over` 发射；消费方只连 GameManager，保留 ScoringManager 本地检查是死代码且引入镜像计分漂移风险。收敛后行为不变（消费链只认 GameManager 信号），但消灭重复发射与状态漂移。

### 3.2 关键决策 D2 — `scored` 只用于回合结束得分

`FSM._on_scored(winner) → transition_to(SCORED) → 冻结挡板 → 1s 后 serve`（game_state_machine.gd:171-175、enter_state SCORED）。因此：

- **穿墙出界（回合结束）** → 发射 `scored` → FSM SCORED → serve（现有链路）
- **拆砖（回合继续）** → **不发射 `scored`** → 球继续飞行，仅 `score_changed` 更新 HUD（AC1）

若拆砖误发 `scored`，FSM 会在回合中冻结挡板并重新发球 —— 这是本设计最重要的防错约束，测试契约 §7.3 必须有对应用例。

### 3.3 拆砖分数据流（AC1/AC5）

```
BreakoutGrid.brick_destroyed(brick, pos)          [#384 契约 §3.4；Main.tscn 接线归 #393]
    │  ScoringManager._ready() get_node_or_null("../BreakoutGrid") best-effort 连接
    ▼
ScoringManager._on_brick_destroyed(brick, pos)
    │  if _is_match_over: return                    [终局后忽略，AC3 边界]
    │  winner = ball.last_toucher                  [ball 按 paddle.mode 维护，§4.2]
    │      └ 空值兜底: 按发球方向（vy<0→player，否则 ai）+ push_warning
    ├── 本地镜像 player_score/ai_score += POINTS_BRICK(1)
    ├── GameManager.add_brick(winner)              [拆砖计数 + add_points(winner, 1)]
    │       ├── player_bricks/ai_bricks += 1       ──► AC5 get_bricks_destroyed(side)
    │       ├── score_changed.emit(p, a) ──► HUD 总分更新 [AC1 ✓，回合继续，不发 scored]
    │       └── _check_game_win(): 21 分 → game_won + match_over [AC3 ✓]
    └── （不发射 scored —— D2）
```

### 3.4 穿墙分数据流（AC2/AC5）

```
Ball._process Y 出界 → score.emit(side)            [现有链路，#295；_scored_this_frame 防同帧双触发]
    ▼
ScoringManager._on_ball_score(side)
    │  if _is_match_over: return
    │  winner = side 映射（0→player、1→ai，现有逻辑不变）
    ├── 本地镜像 += POINTS_WALL_PASS(3)
    ├── scored.emit(winner)                        [回合结束 → FSM SCORED → serve，现有链路]
    └── GameManager.add_wall_pass(winner)          [穿墙计数 + add_points(winner, 3)]
            ├── player_wall_passes/ai_wall_passes += 1  ──► AC5 get_wall_passes(side)
            ├── score_changed.emit(p, a) ──► HUD
            └── _check_game_win(): 21 分 → game_won + match_over [AC3 ✓]
                    │
                    ▼
            FSM._on_match_over → GAME_OVER（现有链路零改动）＋ GameOverScreen 展示（#391 后续消费查询接口）
```

### 3.5 AC4 同帧防重数据流

```
同一帧内：
  拆砖事件 → BreakoutGrid._destroyed 按砖身份去重 → 每砖 brick_destroyed 恰好一次
           → ScoringManager 恰好 add_brick(1) 一次                    [拆砖不重复]
  出界事件 → ball._scored_this_frame 守卫 → score(side) 恰好一次
           → ScoringManager 恰好 add_wall_pass(3) 一次                [穿墙不重复]
  拆砖 + 穿墙同帧（球碎砖后同帧出界）：两笔独立计分各一次，互不抑制
  ScoringManager 侧不加第二道守卫（保持单一来源，PRD §8 交接点明令）
```

---

## 4. 组件设计（implement 契约）

### 4.1 `mini-pong/gdscripts/constants.gd`（Modified）

「── Scoring ──」组修改（#295 单一事实源，注释保留手感定稿说明）：

```gdscript
# ── Scoring ──
const POINTS_BRICK: int = 1        # 拆砖分（最后触球方）—— #385
const POINTS_WALL_PASS: int = 3    # 穿墙分（出界得分方，竖屏出界=穿墙）—— #385
const POINTS_TO_WIN_GAME: int = 21 # 5 → 21：21 分制终局（PLAN-rogue-pong §2.4）—— #385
const GAMES_TO_WIN_MATCH: int = 1  # 2 → 1：单局终局，保留 match_over 作终局信号载体（PRD §4 子决策）
```

### 4.2 `mini-pong/gdscripts/ball.gd`（Modified，~5 行）

```gdscript
# ── State（新增）──
var last_toucher: String = ""   # "" | "player" | "ai" —— 最后触球方（#385 拆砖分归属）

# serve() 内：发球方向确定后初始化（PRD §5 边界 1 约定：向上→player、向下→ai）
last_toucher = "player" if velocity.y < 0 else "ai"

# _on_area_entered() paddles 分支内（cooldown 守卫之后、反弹逻辑处）：
# paddle.Mode.PLAYER=0 / AI=1（#383 已核实 Main.tscn 配置，零新增配置）
last_toucher = "player" if area.mode == 0 else "ai"
```

- 不动 walls/paddles 既有分支逻辑、不动 `_scored_this_frame`、不动层/掩码
- `last_toucher` 每次 `serve()` 重置（发球即新一轮归属起点）

### 4.3 `mini-pong/gdscripts/game_manager.gd`（Modified）

```gdscript
# ── State（新增）──
var player_bricks: int = 0        # 拆砖计数（AC5）
var ai_bricks: int = 0
var player_wall_passes: int = 0   # 穿墙计数（AC5）
var ai_wall_passes: int = 0

# ── API（新增）──
func add_brick(winner: String) -> void:        # 拆砖：计数 + 1 分 + 终局判定
    match winner:
        "player": player_bricks += 1
        "ai":     ai_bricks += 1
        _:        return
    add_points(winner, POINTS_BRICK)

func add_wall_pass(winner: String) -> void:    # 穿墙：计数 + 3 分 + 终局判定
    match winner:
        "player": player_wall_passes += 1
        "ai":     ai_wall_passes += 1
        _:        return
    add_points(winner, POINTS_WALL_PASS)

func add_points(winner: String, points: int) -> void:   # 通用记账（终局判定唯一权威，D1）
    match winner:
        "player": player_score += points
        "ai":     ai_score += points
        _:        return
    score_changed.emit(player_score, ai_score)
    _check_game_win()

func add_score(winner: String) -> void:   # 兼容别名（既有调用/测试），等价 add_points(winner, 1)
    add_points(winner, 1)

func get_bricks_destroyed(side: String) -> int:   # AC5 查询接口
    match side:
        "player": return player_bricks
        "ai":     return ai_bricks
    return 0

func get_wall_passes(side: String) -> int:        # AC5 查询接口
    match side:
        "player": return player_wall_passes
        "ai":     return ai_wall_passes
    return 0

# reset_game() / reset_match()：原有重置逻辑 + 四计数归零（PRD §5 失败路径 4）
```

- `_check_game_win()` / `_win_game()` **逻辑不变**：阈值自动取 `POINTS_TO_WIN_GAME=21`；`GAMES_TO_WIN_MATCH=1` → 21 分即 `match_over.emit(winner)`（FSM/GameOverScreen 现有监听零改动）
- `add_score` 别名保留以兼容 `test_integration_fsm.gd` 等既有调用（PRD §3：兼容调用）

### 4.4 `mini-pong/gdscripts/scoring_manager.gd`（Modified）

```gdscript
# ── Node References（新增）──
@onready var breakout_grid: Node = get_node_or_null("../BreakoutGrid")

# _ready() 新增（best-effort，与 ScoreFlash 模式同构；#393 落地后自动生效）：
if breakout_grid != null and breakout_grid.has_signal("brick_destroyed"):
    breakout_grid.brick_destroyed.connect(_on_brick_destroyed)
if is_instance_valid(GameManager) and GameManager.has_signal("match_over"):
    GameManager.match_over.connect(func(_w): _is_match_over = true)   # D1：终局守卫

func _on_ball_score(side: int) -> void:   # 修改：分值 1→3，终局判定委托 GameManager
    if _is_match_over: return
    var winner: String = "ai" if side == 1 else "player"
    match winner:                          # 本地镜像（scored 簿记，测试兼容）
        "player": player_score += POINTS_WALL_PASS
        "ai":     ai_score += POINTS_WALL_PASS
    scored.emit(winner)                    # 回合结束 → FSM SCORED → serve（现有链路）
    GameManager.add_wall_pass(winner)      # 穿墙计数 + 3 分 + 终局判定（AC2/AC3/AC5）

func _on_brick_destroyed(brick: Node2D, pos: Vector2) -> void:   # 新增
    if _is_match_over: return              # 终局后忽略（AC3 边界）
    var winner: String = _resolve_brick_winner()
    match winner:                          # 本地镜像
        "player": player_score += POINTS_BRICK
        "ai":     ai_score += POINTS_BRICK
    GameManager.add_brick(winner)          # 拆砖计数 + 1 分 + 终局判定（AC1/AC5）
    # 不发射 scored —— 拆砖是回合中事件（D2，防 FSM 误触发重新发球）

func _resolve_brick_winner() -> String:    # 新增：拆砖归属
    if is_instance_valid(ball) and ball.last_toucher != "":
        return ball.last_toucher
    # 兜底（PRD §5 边界 1）：按发球方向归属攻击方（vy<0 向上=player）
    if is_instance_valid(ball):
        push_warning("ScoringManager: last_toucher empty, fallback by serve direction")
        return "player" if ball.velocity.y < 0 else "ai"
    return "player"
```

- **移除**：本地 `_win_game` 检查路径与 `player_games`/`ai_games` 计数（D1，终局判定收敛 GameManager）
- **保留**：`_is_match_over` 守卫（改为 GameManager.match_over 置位）、side→winner 映射、`scored` 发射、pause-then-serve 协作（FSM 侧）、`ball`/`score_flash` 引用
- `POINTS_TO_WIN_GAME`/`GAMES_TO_WIN_MATCH` 本地 const 引用（第 17-18 行）随终局检查移除而删除

### 4.5 不动文件（明确排除）

`Main.tscn`（接线归 #393）、`game_state_machine.gd`、`game_hud.gd`（已监听 score_changed，AC1"更新 HUD"自动满足）、`game_over_screen.gd`、`paddle.gd`、`ball.tscn`、`project.godot`、`audio_engine.gd`（play_brick_break 归 #392）。

---

## 5. 集成点（Integration Points）

> **状态约定：** ⬜ = 待接线（本 Issue 交付消费逻辑，场景接线归 #393）；✅ = 已接线/已核实。implement agent 在接线时更新状态。

| 集成 | 我方组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| `BreakoutGrid.brick_destroyed(brick, pos)` → `ScoringManager._on_brick_destroyed` | ScoringManager（消费逻辑本 Issue 交付） | #384 契约 / #393 场景接线 | 信号连接；`get_node_or_null("../BreakoutGrid")` best-effort，场景内正式接线归 #393 | ⬜ 待 #393（#384 实现落地前无事件源） |
| `GameManager.score_changed` → HUD 总分 | GameManager | #292（已接线） | 现有信号链，拆砖/穿墙分自动更新总分 | ✅ 已接线（源码核实 game_hud.gd:16-20） |
| `GameManager.match_over` → FSM GAME_OVER / GameOverScreen | GameManager（终局单一权威，D1） | #294/#292（已接线） | 现有信号链，21 分终局复用，零改动 | ✅ 已接线（源码核实） |
| `get_bricks_destroyed(side)` / `get_wall_passes(side)` → 结算/失败屏 | GameManager | #391 失败屏 / #390 波次转场 | 查询接口（AC5），UI 消费归 #391 | ⬜ 待 #391 消费 |

---

## 6. 边界条件与失败路径（implement 必须遵守）

1. **发球后未碰挡板先拆砖** — `serve()` 按发球方向初始化 `last_toucher`（向上→"player"、向下→"ai"），拆砖分有归属；`_resolve_brick_winner()` 对空值兜底（按发球方向）+ `push_warning`（PRD §5 边界 1）
2. **球碎砖后同帧出界（拆砖+穿墙同帧）** — 两笔独立计分各一次（AC4）；`score.emit` 后 `serve()` 重置 `last_toucher` 按新发球方向
3. **同帧双砖同碎** — #384 契约按砖身份去重（`_destroyed` 字典），`brick_destroyed` 每砖一次 → `add_brick` 每砖一次
4. **砖墙打空（wall_cleared）** — 本 Issue 不消费 `wall_cleared`（归 #386）；墙空后球直飞出界仍按穿墙 3 分（MVP 语义）
5. **21 分制局/场语义** — `GAMES_TO_WIN_MATCH=1`：21 分即 `match_over`；`player_games_won` 变 0/1 二元；`get_winner()` 逻辑不变；不在本 Issue 删除 games 概念（PRD §4 子决策）
6. **Main.tscn 无 BreakoutGrid（#393 未接线时）** — `get_node_or_null("../BreakoutGrid")` 返回 null → 静默跳过拆砖连接；穿墙分/经典计分不受影响（test_main_scene 回归）
7. **#384 实现未落地** — `breakout_grid.gd` 不在 main（2026-08-13 核实）：implement 先 `ls mini-pong/gdscripts/breakout_grid.gd` 确认；若缺失，用隔离测试模拟 `brick_destroyed` 信号验证计分逻辑，场景接线仍归 #393（PRD §6 前置检查）
8. **post-match guard** — 21 分终局后 `_is_match_over`（GameManager.match_over 置位）抑制后续 `score`/`brick_destroyed` 计分；`_on_brick_destroyed` 与 `_on_ball_score` 两个入口都检查（PRD §5 边界 8）
9. **终局重复发射防护** — D1 单一权威：仅 GameManager 发射 `game_won`/`match_over`；ScoringManager 不发射（其信号无消费者，双发射是死代码 + 漂移源）
10. **拆砖误发 scored（D2 防错）** — 拆砖路径绝不发射 `scored`，否则 FSM 回合中冻结挡板并重新发球；测试契约 §7.3 必须覆盖

**失败路径（≥3）**：
1. **拆砖分归属错误（last_toucher 为空/过期）** — `serve()` 重置时序遗漏 → 兜底按发球方向 + push_warning；测试覆盖发球直拆砖
2. **计分重复** — 依赖 #384 砖身份去重 + `_scored_this_frame`；ScoringManager 不加第二道守卫（单一来源）；测试覆盖同砖两次 destroy / 同帧双出界
3. **21 分阈值竞态** — 每帧最多一次 score 事件，`_check_game_win` 用 `elif` 只判一个 winner（现有实现，回归确认）
4. **reset 后计数残留** — `reset_game()`/`reset_match()` 必须同时重置四计数，否则结算/失败屏读到旧 run 数据；测试覆盖 reset 后全部归零

---

## 7. 测试契约（仅描述，implement 依此写代码）

> 本 PR 不写 runnable 测试文件；以下为 implement 阶段的规格。新增用例注册进 `run_tests.gd`。

### 7.1 `tests/test_constants.gd`（更新）

| 用例 | 描述 |
|------|------|
| TC6-18 更新 | `POINTS_TO_WIN_GAME == 21`（原 5） |
| TC6-19 更新 | `GAMES_TO_WIN_MATCH == 1`（原 2） |
| 新增 | `POINTS_BRICK == 1`、`POINTS_WALL_PASS == 3` |

### 7.2 `tests/test_game_manager.gd`（更新 + 新增）

| 测试组 | 用例描述 |
|--------|---------|
| add_points 分值 | `add_points("player", 3)` → player_score +3；`add_points("ai", 1)` → ai_score +1；invalid winner 无变化无信号 |
| add_score 兼容 | `add_score("player")` 等价 `add_points("player", 1)`（既有 TC3/TC4/TC5 保留） |
| 21 分终局（AC3） | 20→21：`add_points` 到 21 → `game_won` + `match_over` 各一次；`_win_game` 后分数清零、games_won=1；21 后 `add_points` 仍记账（GameManager 层不设 guard，场景层由 ScoringManager `_is_match_over` 拦截 —— 契约注明） |
| 既有 5 分用例更新 | TC6（5 分 game_won）→ 21 分触发；TC8 等 2 局 match_over 用例 → `GAMES_TO_WIN_MATCH=1` 语义（1 局即 match_over） |
| 拆砖计数（AC5） | `add_brick("player")` → player_bricks=1、player_score+1、score_changed 发射；`add_brick("ai")` 同理 |
| 穿墙计数（AC5） | `add_wall_pass("player")` → player_wall_passes=1、player_score+3；`add_wall_pass("ai")` 同理 |
| 查询接口 | `get_bricks_destroyed("player"/"ai")` / `get_wall_passes(...)` 返回值正确；未知 side 返回 0 |
| reset | `reset_game()` 与 `reset_match()` 后四计数全部归零、分数归零（失败路径 4） |

### 7.3 `tests/test_scoring_manager.gd`（更新 + 新增；文件内硬编码常量改为引用 CONSTS）

| 测试组 | 用例描述 |
|--------|---------|
| 穿墙 3 分（AC2） | `_on_ball_score(0)` → GameManager.player_score +3（原 +1 断言更新）；`_on_ball_score(1)` → ai +3；本地镜像 +3 |
| 拆砖消费（AC1） | 模拟 `_on_brick_destroyed(brick, pos)`：ball.last_toucher="player" → GameManager.player_score+1、player_bricks=1；last_toucher="ai" 同理 |
| 拆砖归属兜底 | last_toucher="" → 按 ball.velocity.y 方向兜底（vy<0→player）+ push_warning |
| **拆砖不发 scored（D2）** | `_on_brick_destroyed` 后 scored 信号**未发射**；`_on_ball_score` 后 scored **发射**（防 FSM 误触发重新发球） |
| 21 分终局委托（D1） | 拆砖/穿墙累计到 21 → 断言 **GameManager** 发射 `game_won`/`match_over`；ScoringManager 自身不发射该两信号 |
| post-match guard | `GameManager.match_over` 触发后，再 `_on_ball_score`/`_on_brick_destroyed` 均被忽略（分数不变） |
| 同帧防重（AC4） | 同帧两次 `_on_ball_score` → 只计一次（上游 `_scored_this_frame` 语义）；同砖两次 `_on_brick_destroyed` → 只计一次（#384 去重契约语义）；拆砖+穿墙同帧 → +1 与 +3 各一次 |
| 既有用例更新 | 原 5 分制/2 局制本地终局用例 → 改为断言 GameManager 信号或删除（本地 `_win_game` 已移除） |
| 无 BreakoutGrid 容错 | 场景无 `../BreakoutGrid` 节点 → `_ready()` 不崩、经典计分正常（回归） |

### 7.4 回归套件

| 套件 | 关注点 |
|------|--------|
| `tests/test_integration_fsm.gd` | 用 `add_score` 驱动 FSM 的用例：编译兼容（别名保留）；**语义变化核对** —— 5 分不再触发 game_won（阈值 21），若有断言 5 分终局的用例需改为 21 分 |
| `tests/test_main_scene.gd` | Main.tscn 无 BreakoutGrid 时 ScoringManager 不崩（get_node_or_null 静默跳过） |
| `tests/auto_play_test.gd` | 动态读常量，自动适配 21/1；跑通确认（一局终局节奏） |

### 7.5 可选新套件 `tests/test_dual_scoring.gd`（集成级）

如新建则注册进 `run_tests.gd`（置于 test_scoring_manager 之后）：拆砖+1 与穿墙+3 混合累计到 21 → GameManager 终局；查询接口在混合场景下的计数正确性；reset 后全归零。**也可并入 test_scoring_manager.gd，二选一，不重复。**

---

## 8. 验收标准映射（Issue #385 AC）

| AC | 验收标准 | 设计覆盖 |
|----|---------|---------|
| AC1 | 拆掉一块砖给最后触球方 +1 分，并更新 HUD | §3.3 拆砖流（last_toucher → add_brick 1 分 → score_changed → HUD 已监听）；§7.3 拆砖消费用例 |
| AC2 | 球未被接住从上/下出界且穿越砖墙时，给得分方 +3 分 | §3.4 穿墙流（出界路径分值 1→3 = POINTS_WALL_PASS）；§7.3 穿墙 3 分用例 |
| AC3 | 任意一方达到 21 分时 GameManager 进入终局状态 | §3.1 D1 + §4.3（POINTS_TO_WIN_GAME=21、GAMES_TO_WIN_MATCH=1 → game_won+match_over）；§7.2 21 分终局用例 |
| AC4 | 同一帧的拆砖/穿墙不会重复计分 | §3.5 防重流（#384 砖身份去重 + `_scored_this_frame`，单一计分入口不加第二道守卫）；§7.3 同帧防重用例 |
| AC5 | GameManager 可查询每方拆砖数、穿墙数，供结算/失败屏使用 | §4.3 四计数 + `get_bricks_destroyed(side)`/`get_wall_passes(side)` + reset 归零；§7.2 计数/查询/reset 用例；§5 集成点（#391 消费） |

---

## 9. 实施顺序与验证步骤（implement 执行顺序）

1. `constants.gd`：双得分常量组 + 阈值 21/1（#295 单一事实源先行）
2. `ball.gd`：`last_toucher` + paddles 分支记录 + `serve()` 方向初始化（~5 行）
3. `game_manager.gd`：`add_points`/`add_brick`/`add_wall_pass`/`add_score` 别名 + 四计数 + 查询接口 + reset 重置（`_check_game_win` 逻辑不变）
4. `scoring_manager.gd`：`_on_ball_score` 分值 3 + 新增 `_on_brick_destroyed` + `_ready()` 连接 brick_destroyed 与 GameManager.match_over + 移除本地终局检查（D1）
5. 测试：test_constants / test_game_manager / test_scoring_manager 更新 + 新增（§7）；可选 test_dual_scoring.gd；`run_tests.gd` 注册
6. 本地验证：
   - `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含既有 14 套件回归）
   - `godot --path mini-pong/ --headless --quit` 编译通过
   - `git diff` 确认 Main.tscn / game_state_machine.gd / game_hud.gd / game_over_screen.gd / paddle.gd 零改动
   - 前置检查：`ls mini-pong/gdscripts/breakout_grid.gd`（#384 落地状态；缺失则按 §6 边界 7 处理）

---

## 10. 不做的事与范围边界（明确排除）

- ❌ **Main.tscn 接线** — BreakoutGrid 实例化、`brick_destroyed` 场景内正式接线归 **#393**（本 Issue 交付 `get_node_or_null` best-effort 连接 + 隔离测试）
- ❌ 波次循环/`wall_cleared` 消费（#386）、HUD 拆砖/穿墙双区视觉（#392）、结算/失败屏 UI（#391）
- ❌ 删除 games 概念（保留 `GAMES_TO_WIN_MATCH=1`；删除涉及 #291 测试重构，收益趋零）
- ❌ 穿墙逐帧检测（竖屏出界=穿墙的事实核查已定，PRD §7 实验 1）
- ❌ 音效 `play_brick_break`（#392）、`brick.gd`/`breakout_grid.gd` 实现（#384）
- ❌ 修改 FSM / HUD / GameOverScreen / paddle.gd / ball.tscn / project.godot
- ❌ 引入任何第三方资产（PRD §1.4 开源优先结论：无可复用计分插件，第一方实现）
- ❌ 写 runnable 测试文件于本 PR（测试归 implement PR）

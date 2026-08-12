# DESIGN: [Feature] 双得分制 (Dual Scoring)

> **Parent Issue:** #385
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — GameManager 扩展为双得分状态持有者 + 场景侧 ScoringManager 消费事件（确认 PRD §4 推荐，无偏离）
> **Reference PRD:** docs/PRD/385-dual-scoring-system.md（research PR #418，已合并）
> **所有权:** `content_ownership: mechanical`（计分状态/规则/信号为纯机械实现；分值 1/3/21 已由 PLAN-rogue-pong §2.2/§2.4 用户拍板，无 taste 决策）
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384 惯例按 standard 处理）—— 产出 DESIGN + TASKS（影响文件 ≥10，满足 standard 阈值）；**测试仅描述，不写可运行测试代码**
> **Plan 阶段边界:** 本阶段只产出本文档与 `docs/TASKS/385-dual-scoring-system.md`，不碰任何 `.gd` / `.tscn` / `project.godot` 文件 —— 下列全部内容为 implement agent 的契约。

---

## 1. 概述

Mini Pong（720×1280 竖屏，PR #409 后）目前是经典 Pong 计分：球上/下出界 → `ball.score(side)` → ScoringManager +1 → 5 分赢局、2 局赢比赛（#291/#293/#295）。本设计将计分制替换为 **Rogue Pong 双得分制**（PLAN-rogue-pong §2.2/§2.4）：

- **拆砖分**：消费 #384 的 `brick_destroyed(brick, pos)` 信号，给最后触球方 +1 分（AC1）
- **穿墙分**：球穿越墙带后从上/下出界且未被接住，给得分方 +3 分（AC2）
- **终局**：任一方总分（拆砖 + 穿墙 + 出界）先到 21 → GameManager 进入终局状态，发 `match_over`（AC3）
- **同帧去重**：复用 #295 `_scored_this_frame` 帧守卫模式，同帧砖碎 + 出界只计拆砖分（AC4）
- **查询 API**：`get_brick_count(side)` / `get_pierce_count(side)` 供结算/失败屏使用（AC5）

### 设计哲学

1. **Approach A 确认**：延续 #293「场景节点判事件、GameManager 持全局状态」分工 —— 事件判定（拆砖归属、穿墙与否）留在场景侧 ScoringManager/ball，GameManager 只做状态持有 + 终局判定 + 查询 API。不新建 autoload（否决 Approach B），不把计分写进 ball（否决 Approach C，与 #384 已否决的「球侧写状态」反模式同构）。
2. **最小触碰面**：`ball.gd` 仅新增 2 个状态字段 + 判定逻辑（~15 行）；walls/paddles 分支行为不变（#287 测试兜底回归）；FSM 仅改 SCORED 状态的一个判定分支。
3. **容错消费 #384**：`brick_destroyed` 消费方用 `get_node_or_null` 容错引用 BreakoutGrid（同 ScoringManager 对 ScoreFlash 的既有模式）——#384 实现未落地、#393 未接线时游戏不崩、不阻塞。
4. **常量单一事实源**：分值/阈值全部进 `constants.gd`（#295 约束），不散落硬编码。
5. **测试即验收**：测试用例描述见 §9；implement agent 写 `test_dual_scoring.gd` 并注册进 `run_tests.gd`；`godot --headless --script tests/run_tests.gd` 全绿。

### 1.1 关键事实（plan agent 已对照源码核实）

| 事实 | 核实结果 |
|------|---------|
| Main.tscn 节点名 | `PlayerPaddle` / `AIPaddle`（同一 paddle.tscn 实例）→ `last_toucher` 可按 `area.name` 判定，**paddle.gd 无需改动**（PRD §7 实验 2 确认） |
| FSM 终局入口 | `game_state_machine.gd` 已直连 `GameManager.match_over`（`_on_match_over` → GAME_OVER）→ 21 分终局复用既有信号名与路径，零新接线 |
| #384 信号契约 | `brick_destroyed(brick: Node2D, pos: Vector2)`（每砖销毁一次）；`wall_cleared()` 归 #386，本 Issue **不消费** |
| #384 实现状态 | **未落地**：`git ls-tree origin/main mini-pong/gdscripts/` 无 `breakout_grid.gd`/`brick.gd` → 拆砖分消费方必须容错连接 + 隔离测试先行 |
| #384 常量 | `GRID_WALL_Y=640`、`BRICK_SIZE=(64,24)`（DESIGN #414 定义，**尚未进 constants.gd**）→ 本 Issue 自带墙带判定常量组，见 §2.1 |
| 帧守卫 | `ball._scored_this_frame`（#295）每帧开头复位、`serve()` 复位点明确 → AC4 同模式扩展 |
| side 语义（#383） | side 0 = player 得分（顶部出界）、side 1 = ai 得分（底部出界）；穿墙分归属 = 出界得分方（攻击方） |

### 1.2 与 PRD 的差异决策（plan 定稿，PRD §8 交接点 2/4 待决项）

| PRD 待决项 | 本设计定稿 | 理由 |
|-----------|-----------|------|
| `POINTS_TO_WIN_GAME` 改名策略 | **新增 `WIN_SCORE=21`，废弃 `POINTS_TO_WIN_GAME=5` 与 `GAMES_TO_WIN_MATCH=2`**（保留声明但注释「弃用」） | 21 分制下「局/比赛」分层消亡；保留旧常量名改值会误导阅读（5 分制语义残留）；新名表达 run 级终局语义 |
| `last_toucher` 区分方式 | **按节点名 `PlayerPaddle`/`AIPaddle` 判定**，paddle.gd 不改 | PRD §7 实验 2：group `paddles` 无 player/ai 区分，节点名已存在且唯一；新增 group 需改 paddle.gd + 测试，收益为零 |
| 墙带判定常量 | **本 Issue 自带 `GRID_WALL_Y=640`（与 #414 同值）与 `WALL_BAND_HALF_HEIGHT=22.0`**（= BRICK_SIZE.y/2 + BALL_RADIUS = 12+10） | #384 实现未落地，跨 Issue 常量引用会造成解析失败；#393 组装时统一对齐（见 §7） |
| HUD 改动 | **game_hud.gd 不改代码** —— AC1 的「更新 HUD」由既有 `score_changed` → 总分联动满足；拆砖/穿墙细分 UI 归 #390/#392 | PRD §3 明确「总分联动已具备；双区细分 UI 归 #390/#392」 |

---

## 2. 现有组件修改 — 详细设计

### 2.1 `mini-pong/gdscripts/constants.gd`（修改）

新增「── Dual Scoring (#385) ──」常量组（置于 Scoring 区之后）：

```gdscript
# ── Dual Scoring (#385) ──
# 双得分制 (PLAN-rogue-pong §2.2/§2.4, 用户 2026-08-13 拍板, mechanical)
const BRICK_SCORE: int = 1        # 拆砖分：最后触球方 +1
const PIERCE_SCORE: int = 3       # 穿墙分：穿越墙带后出界未被接住 +3
const WIN_SCORE: int = 21         # 终局分：任一方总分先到 21 获胜（取代 5 分/2 局制）
const GRID_WALL_Y: float = 640.0  # 砖墙中线 Y（与 #384 DESIGN #414 同值；#393 组装时统一对齐）
const WALL_BAND_HALF_HEIGHT: float = 22.0  # 墙带判定半高 = BRICK_SIZE.y/2(12) + BALL_RADIUS(10)，防高速球单帧漏判
```

同时：
- `POINTS_TO_WIN_GAME` / `GAMES_TO_WIN_MATCH` 保留声明，注释标记 `# 弃用 (#385): 21 分制无局/比赛分层`，**不被任何代码引用**
- 不删除旧常量（避免测试加载错误），但实现 agent 必须把 `game_manager.gd`/`scoring_manager.gd` 中对它们的引用全部移除

### 2.2 `mini-pong/gdscripts/game_manager.gd`（修改 — 核心状态持有者）

**职责**：纯数据持有 + 终局判定 + 查询 API。**移除** 局/比赛分层逻辑（`player_games_won`/`ai_games_won`/`get_winner()`/`_win_game()`/`_check_game_win()`/`game_won` 发射）。

```gdscript
const CONSTS = preload("res://gdscripts/constants.gd")
const WIN_SCORE: int = CONSTS.WIN_SCORE

# ── Signals ──
signal score_changed(player_score: int, ai_score: int)
signal match_over(winner: String)     # "player" | "ai" — 21 分终局（复用既有信号名，FSM/结算屏零新接线）
# game_won 信号删除（21 分制无「局」概念；HUD/FSM/结算屏均不消费）

# ── State ──
var player_score: int = 0
var ai_score: int = 0
var player_brick_count: int = 0
var ai_brick_count: int = 0
var player_pierce_count: int = 0
var ai_pierce_count: int = 0
var _is_run_over: bool = false        # 终局守卫（防终局后事件泄漏）

# ── API ──
func add_score(winner: String, amount: int = 1, kind: String = "boundary") -> void:
    # kind: "boundary" | "brick" | "pierce"
    if _is_run_over:
        return                       # 终局后直接 return（失败路径 2）
    if amount <= 0:
        return
    match winner:
        "player":
            player_score += amount
            _bump_count("player", kind)
        "ai":
            ai_score += amount
            _bump_count("ai", kind)
        _:
            return                   # 非法 winner：无状态变更、无信号（保持 TC5 语义）
    score_changed.emit(player_score, ai_score)
    _check_run_end()

func get_brick_count(side: String) -> int:    # AC5
    return player_brick_count if side == "player" else ai_brick_count

func get_pierce_count(side: String) -> int:   # AC5
    return player_pierce_count if side == "player" else ai_pierce_count

func is_run_over() -> bool:
    return _is_run_over

func reset_match() -> void:
    player_score = 0
    ai_score = 0
    player_brick_count = 0
    ai_brick_count = 0
    player_pierce_count = 0
    ai_pierce_count = 0
    _is_run_over = false

# ── Internal ──
func _bump_count(side: String, kind: String) -> void:
    match kind:
        "brick":
            if side == "player": player_brick_count += 1
            else: ai_brick_count += 1
        "pierce":
            if side == "player": player_pierce_count += 1
            else: ai_pierce_count += 1
        _:
            pass                     # "boundary" 不计数（出界分不是 run 统计项）

func _check_run_end() -> void:       # AC3：先到 21 者赢；单次事件只给一方加分，不存在同帧双方到 21
    if player_score >= WIN_SCORE:
        _is_run_over = true
        match_over.emit("player")
    elif ai_score >= WIN_SCORE:
        _is_run_over = true
        match_over.emit("ai")
```

**移除项**（implement agent 删除）：`POINTS_TO_WIN_GAME`/`GAMES_TO_WIN_MATCH` 常量引用、`player_games_won`/`ai_games_won`、`game_won` 信号、`add_score(winner)` 旧签名（新签名带默认参数，兼容单参调用但不推荐）、`get_winner()`、`reset_game()`（`reset_match()` 已覆盖，可删除或保留为 reset_match 别名——**设计：删除**，FSM 只调用 `reset_match()`）。

### 2.3 `mini-pong/gdscripts/scoring_manager.gd`（修改 — 场景侧事件消费）

**职责**：消费 `ball.score(side)` 与 `BreakoutGrid.brick_destroyed`，判定归属/分值/类型 → 调用 `GameManager.add_score(winner, amount, kind)`。**移除**本地局/比赛追踪（`player_score`/`player_games`/`_win_game`/`game_won`/`match_over` 信号发射）——终局判定唯一权威在 GameManager，FSM 已直连 `GameManager.match_over`。

```gdscript
const CONSTS = preload("res://gdscripts/constants.gd")
const BRICK_SCORE: int = CONSTS.BRICK_SCORE
const PIERCE_SCORE: int = CONSTS.PIERCE_SCORE

# ── Signals ──
signal scored(winner: String)   # 仅出界分（普通/穿墙）触发 → FSM SCORED 暂停流；拆砖分不触发（比赛继续）

# ── Node References ──
@onready var ball: Area2D = $"../Ball"
@onready var score_flash: Node = get_node_or_null("../ScoreFlash")
@onready var breakout_grid: Node = get_node_or_null("../BreakoutGrid")   # #384 容错：#393 接线前为 null

func _ready() -> void:
    if ball == null:
        push_error("ScoringManager: Ball node not found — scoring disabled")
        return
    ball.score.connect(_on_ball_score)
    if score_flash != null and score_flash.has_method("_on_score_changed"):
        scored.connect(score_flash._on_score_changed)
    # #384 容错连接：grid 不存在/信号未实现 → 跳过并警告一次，不崩（失败路径 1）
    if breakout_grid != null and breakout_grid.has_signal("brick_destroyed"):
        breakout_grid.brick_destroyed.connect(_on_brick_destroyed)
    else:
        push_warning("ScoringManager: BreakoutGrid 未接线（#393 前）— 拆砖分暂不可用")

func _on_ball_score(side: int) -> void:
    if is_instance_valid(GameManager) and GameManager.is_run_over():
        return                       # 终局守卫（失败路径 2）
    var winner: String = "ai" if side == 1 else "player"
    # 穿墙判定：ball 已穿越墙带 → 3 分（AC2）；否则普通出界 1 分兜底（无墙时期游戏不坏，边界 3）
    var crossed: bool = ball != null and bool(ball.get("_crossed_wall"))
    var amount: int = PIERCE_SCORE if crossed else 1
    var kind: String = "pierce" if crossed else "boundary"
    GameManager.add_score(winner, amount, kind)
    scored.emit(winner)              # 出界分走 SCORED → 重发球流（边界 8）

func _on_brick_destroyed(brick: Node2D, pos: Vector2) -> void:
    if is_instance_valid(GameManager) and GameManager.is_run_over():
        return
    if ball == null:
        return
    var toucher: String = ball.get("last_toucher")
    if toucher == "" or toucher == null:
        return                       # 发球直撞砖：无归属，不计拆砖分（边界 2）；砖仍碎/反弹（#384 行为不变）
    GameManager.add_score(toucher, BRICK_SCORE, "brick")
    # 不 emit scored —— 拆砖不触发 FSM SCORED，比赛继续（边界 8）
```

**移除项**：`player_score`/`ai_score`/`player_games`/`ai_games`/`_is_match_over`、`_win_game()`、`game_won`/`match_over` 信号、`POINTS_TO_WIN_GAME`/`GAMES_TO_WIN_MATCH` 引用、`_pause_and_serve()`（FSM #294 已接管发球时机，原为 no-op）。

### 2.4 `mini-pong/gdscripts/ball.gd`（修改 — 归属与穿越状态）

**职责**：追踪 `last_toucher`（最后触球方）与 `_crossed_wall`（本 rally 是否穿越墙带）。walls/paddles 分支的既有行为（反弹数学、加速、音效、反卡位）**零改动**。

```gdscript
# ── 新增状态（State 区）──
var last_toucher: String = ""       # "player" | "ai" | ""（发球后未触任何挡板）
var _crossed_wall: bool = false     # 本 rally 是否穿越过墙带（穿墙分判定依据）

# ── serve() 内新增复位（既有复位之后）──
last_toucher = ""
_crossed_wall = false

# ── _process() 内、position 更新之后、X/Y 边界判定之前 ──
if not _crossed_wall:
    var wall_y: float = CONSTS.GRID_WALL_Y
    if abs(position.y - wall_y) <= CONSTS.WALL_BAND_HALF_HEIGHT:
        _crossed_wall = true        # 置位即保持（本 rally 内不再复位，直到触球/发球）

# ── _on_area_entered() paddles 分支内、读取 paddle_length 之前 ──
match area.name:
    "PlayerPaddle":
        last_toucher = "player"
    "AIPaddle":
        last_toucher = "ai"
    _:
        last_toucher = ""
_crossed_wall = false               # 触球复位：穿墙分只在「穿越后未被接住」时成立（失败路径 4）
```

**设计要点**：
- `_crossed_wall` 用「跨入墙带即置位、触球/发球复位」而非「跨出墙带」判定 —— 高速球（627px/s ≈ 10.5px/帧）单帧穿越墙带时防漏判（边界 7）；墙带带宽 `wall_y ± 22px` 覆盖 BRICK_SIZE.y/2 + BALL_RADIUS。
- 触球复位放在 `_on_area_entered` paddles 分支开头（早于反弹计算），保证 `last_toucher` 与 `_crossed_wall` 在同一事件内原子更新。
- 无墙时期（#384 未落地）：`_crossed_wall` 仍可能因球经过 y≈640 区域而置位，但出界时**只有真正穿越过墙带**才置位 —— 球从中心发球位（y=640 即墙带内！）发球时会立即置位。**⚠️ 关键边界**：发球位置 `position = (screen_width/2, screen_height/2)` = (360, 640) 恰好落在墙带内 → 发球后 `_crossed_wall` 立即为 true，但 `serve()` 已复位且发球后球先离开墙带（向下/上移动）——置位只发生在「球在带内」的帧。若发球方向随机导致球先横向移动仍处带内，会误置位。**设计修正**：`_crossed_wall` 置位条件改为「球**从带外进入带内**」的边沿触发：记录上一帧 `_was_in_wall_band`，仅在 `not _was_in_wall_band and in_band` 时置位。实现 agent 按此语义实现（§5 边界 7 用例覆盖）。

### 2.5 `mini-pong/gdscripts/game_state_machine.gd`（修改 — SCORED 判定）

`enter_state(State.SCORED)` 中 1 秒计时后的判定分支替换：

```gdscript
# 旧：GameManager.get_winner() != "" → GAME_OVER（局/比赛制，已废弃）
# 新：21 分终局判定直达 GAME_OVER（AC3）
if current_state == State.SCORED:
    if is_instance_valid(GameManager) and GameManager.has_method("is_run_over") and GameManager.is_run_over():
        transition_to(State.GAME_OVER)
    else:
        transition_to(State.SERVING)
```

其余状态（MENU/SERVING/PLAYING/PAUSED/GAME_OVER）与 `_on_scored`/`_on_match_over` handler **零改动**。

### 2.6 `mini-pong/gdscripts/game_hud.gd`（不改代码）

AC1「拆砖后更新 HUD」由既有链路满足：`GameManager.score_changed` → `_on_score_changed` → 总分 Label 更新（拆砖分经 `add_score` 同样触发 `score_changed`）。拆砖/穿墙双区细分 UI 归 #390/#392（PRD §3 已界定）。

### 2.7 `mini-pong/gdscripts/game_over_screen.gd`（修改 — 最小）

`_on_match_over(winner)` 内、winner 文本设置之后追加 run 统计读取（布局归 #391，本 Issue 只保证数据路径）：

```gdscript
# _on_match_over() 内（winner 匹配分支之后）：
if is_instance_valid(GameManager) and GameManager.has_method("get_brick_count"):
    var stats := "拆砖  P:%d/A:%d   穿墙  P:%d/A:%d" % [
        GameManager.get_brick_count("player"), GameManager.get_brick_count("ai"),
        GameManager.get_pierce_count("player"), GameManager.get_pierce_count("ai"),
    ]
    var stats_label: Label = get_node_or_null("CenterContainer/VBoxContainer/RunStatsLabel")
    if stats_label:
        stats_label.text = stats   # 节点不存在则跳过（get_node_or_null 容错，场景布局归 #391）
```

### 2.8 `mini-pong/gdscripts/paddle.gd`（不改）

`last_toucher` 按 `area.name` 判定（§1.2 定稿），双挡板已加入 `paddles` group 且节点名唯一，无需新增 player/ai 组。

### 2.9 受影响测试文件（implement agent 改造清单）

| 文件 | 改动性质 |
|------|---------|
| `mini-pong/tests/test_game_manager.gd` | **重写**：移除 5 分/2 局断言（TC6/TC8/TC9/TC13-15）；改为 `add_score(winner, amount, kind)` 签名、计数状态、21 分终局恰好一次、`is_run_over()`、查询 API、`reset_match()` |
| `mini-pong/tests/test_scoring_manager.gd` | **重写**：移除局/比赛断言（TC3/TC4/TC6）；改为出界分 3/1 路由、`brick_destroyed` 消费（含空触球者）、拆砖不触发 `scored`、终局守卫 |
| `mini-pong/tests/test_ball.gd` | **扩展**：新增 `last_toucher`（按节点名、serve 复位、空值）与 `_crossed_wall`（带边沿置位、触球/发球复位、发球位不误置位）用例；既有 walls/paddles 用例不回归 |
| `mini-pong/tests/test_constants.gd` | **扩展**：新增 `BRICK_SCORE=1`/`PIERCE_SCORE=3`/`WIN_SCORE=21`/`GRID_WALL_Y=640`/`WALL_BAND_HALF_HEIGHT=22.0` 断言 |
| `mini-pong/tests/test_game_state_machine.gd` / `test_integration_fsm.gd` | **适配**：SCORED 判定路径改为 `is_run_over()`（若有相关断言） |
| `mini-pong/tests/run_tests.gd` | **注册**：新增 `_run("res://tests/test_dual_scoring.gd", "Dual Scoring")` |

---

## 3. 新建文件（实现期）

| 文件 | 内容 |
|------|------|
| `mini-pong/tests/test_dual_scoring.gd` | 双得分制测试套件（§9 场景 A–I 的可运行实现；extends RefCounted，注册进 run_tests.gd） |

> Plan 阶段**不创建**该文件 —— 测试描述见 §9，代码由 implement agent 编写。

---

## 4. 数据流

### Flow 1: 拆砖得分（AC1）

```
BreakoutGrid.brick_destroyed(brick, pos)          [来自 #384 实现；未接线时为容错跳过]
    │
    ▼
ScoringManager._on_brick_destroyed(brick, pos)
    ├── GameManager.is_run_over()? → return（终局守卫）
    ├── ball.last_toucher == ""? → return（无归属，边界 2）
    └── GameManager.add_score(toucher, 1, "brick")
            ├── player_brick_count/ai_brick_count += 1        (AC5 可查询)
            ├── score_changed.emit(player_score, ai_score) ──► GameHUD 总分更新 (AC1)
            └── _check_run_end(): 任一 ≥ 21 → match_over.emit(winner) (AC3)
    （不 emit ScoringManager.scored → FSM 不暂停，比赛继续，边界 8）
```

### Flow 2: 穿墙得分（AC2）

```
Ball._process(): position 跨入墙带（带外→带内边沿）→ _crossed_wall = true
    │
    ▼（球继续飞行，未被对方挡板接住）
Ball 出界（Y 越界）→ score.emit(side)  [既有信号，side 0=player 得分/1=ai 得分]
    │
    ▼
ScoringManager._on_ball_score(side)
    ├── ball._crossed_wall == true → add_score(winner, 3, "pierce")
    │       ├── player_pierce_count/ai_pierce_count += 1
    │       ├── score_changed.emit ──► HUD
    │       └── _check_run_end(): ≥21 → match_over (AC3)
    └── scored.emit(winner) ──► FSM SCORED（暂停 1s → 重发球；终局则 GAME_OVER）
```

### Flow 3: 普通出界兜底（无墙时期 / 未穿越墙带）

```
Ball 出界 → score.emit(side) → ScoringManager._on_ball_score(side)
    └── ball._crossed_wall == false → add_score(winner, 1, "boundary")   [既有 1 分语义兜底]
            ├── score_changed.emit ──► HUD
            └── scored.emit(winner) ──► FSM SCORED
    （#384 未接线/未穿越墙带时游戏行为与现状一致，不坏 —— 边界 3）
```

### Flow 4: 21 分终局（AC3）

```
任意 add_score 调用后 → _check_run_end()
    ├── player_score ≥ 21 → _is_run_over = true → match_over.emit("player")
    │       ├──► FSM._on_match_over → State.GAME_OVER（既有连接）
    │       └──► GameOverScreen._on_match_over → 读 get_brick_count/get_pierce_count 显示统计（AC5）
    └── 此后所有 add_score/_on_ball_score/_on_brick_destroyed 被 is_run_over() 守卫拦截（失败路径 2）
```

### Flow 5: 同帧拆砖 + 出界去重（AC4）

```
同一帧：brick_destroyed 先到 → add_score(toucher, 1, "brick")（计拆砖分）
    │
    ▼ 同帧稍后：ball 出界 → _on_ball_score(side)
    ├── ball._crossed_wall == true？—— 若该帧砖碎于墙带内且球已穿越 → 会再计 3 分！
    └── 去重设计：ball._scored_this_frame 语义扩展 ——
            ScoringManager 侧维护 _brick_destroyed_this_frame: bool
            _on_brick_destroyed 置位；_process 帧首复位（或由 ball 帧事件驱动）
            _on_ball_score 开头检查：若 _brick_destroyed_this_frame → 只计拆砖分，跳过出界分
```

> **AC4 实现裁定**：帧守卫放在 ScoringManager 侧（`_brick_destroyed_this_frame`，帧首由 `ball.score` 处理前复位）比放 ball 侧更贴近事件源。实现 agent 采用：`_on_brick_destroyed` 置位 → `_on_ball_score` 检查并复位。规则：**同帧砖碎 + 出界 → 只计拆砖分**（该帧出界不计 3 分）；不同帧各自计分（打穿推进，PLAN §2.4「都计入」）。

---

## 5. 边界条件与失败路径

### 边界条件（≥5）

| # | 边界场景 | 处理 |
|---|---------|------|
| 1 | **同帧拆砖 + 出界**（AC4 核心） | `_brick_destroyed_this_frame` 帧守卫：同帧只计拆砖分；不同帧各自计分 |
| 2 | **最后触球者为空**（发球直撞砖） | `last_toucher == ""` → 不计拆砖分；砖仍碎/反弹（#384 行为不变），防随机发球送分 |
| 3 | **球出界但未穿越墙带**（无墙时期兜底） | 出界按普通 1 分（`kind="boundary"`）；#385 先于 #393 落地时游戏不坏 |
| 4 | **发球/暂停期** | `_is_serving`/PAUSED 时球不动：无碰撞/出界/计分；`serve()` 复位 `last_toucher`/`_crossed_wall` |
| 5 | **双挡板同 group（paddles）** | 按节点名 `PlayerPaddle`/`AIPaddle` 判定（§1.2），paddle.gd 不改 |
| 6 | **21 分同时达到** | 单次事件只给一方加分 → 不存在同帧双方到 21；`_check_run_end` 每次 `add_score` 后同步执行，先到先赢 |
| 7 | **墙带判定带宽 / 发球位误置位** | 带宽 `wall_y ± 22px`（防高速球漏判）；**边沿触发**（带外→带内才置位）防发球位（y=640 恰在带内）误置位 |
| 8 | **拆砖不暂停** | 拆砖不触发 FSM SCORED；只有出界（穿墙/普通）走 SCORED → 重发球 |

### 失败路径（≥3）

| # | 失败场景 | 处理 |
|---|---------|------|
| 1 | `brick_destroyed` 消费方引用空节点（#393 前） | `get_node_or_null("../BreakoutGrid")` → null 时跳过连接，`push_warning` 一次，不崩 |
| 2 | 终局后事件泄漏（球仍在飞/砖仍碎） | `GameManager.is_run_over()` 守卫：终局后 `add_score`/`_on_ball_score`/`_on_brick_destroyed` 直接 return |
| 3 | 拆砖分重复计入（同帧多砖碎 / #384 实现偏差） | #384 grid 已按砖对象身份去重；消费方按帧守卫（边界 1）二次防护 |
| 4 | 穿越标记残留（触砖反弹回本侧再出界误判 3 分） | `_crossed_wall` 在挡板触球/发球时复位；测试覆盖「触砖反弹出界」断言 1 分 |

---

## 6. 每场景配置

本 Issue **不修改任何 `.tscn`**。未来 #393 组装时的配置清单（供参考，非本 Issue 交付）：

| 场景 | 配置 | 归属 |
|------|------|------|
| `mini-pong/scenes/Main.tscn` | 实例化 `breakout_grid.tscn`（节点名 `BreakoutGrid`，ScoringManager 的 `get_node_or_null("../BreakoutGrid")` 依赖此名）；位置对齐 `GRID_WALL_Y` | #393 |
| `mini-pong/scenes/game_over_screen.tscn`（若有） | 新增 `RunStatsLabel`（§2.7 容错读取） | #391 |

---

## 7. 集成点

> 状态约定：⬜ = pending（实现 agent 接线后更新）；✅ = 已存在/已连接。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| `BreakoutGrid.brick_destroyed(brick, pos)` → 拆砖分 | ScoringManager._on_brick_destroyed | #384 → 本 Issue 消费 | signal connect（`get_node_or_null` 容错，节点名 `../BreakoutGrid`） | ⬜ pending |
| `wall_cleared()` | —（**不消费**） | #386 | 明确不连接（砖墙打空不终局，比赛继续到 21 分） | — |
| `GameManager.match_over` → FSM GAME_OVER | GameStateMachine._on_match_over | 本 Issue 内部 | 既有连接（零改动） | ✅ 已存在 |
| `score_changed` → HUD 总分 | GameHUD._on_score_changed | 本 Issue 内部 | 既有连接（拆砖/穿墙分同样触发，AC1 满足） | ✅ 已存在 |
| `GameManager` 查询 API → 结算统计 | GameOverScreen._on_match_over | #391 失败屏 | `get_brick_count`/`get_pierce_count` 读取（本 Issue 保证数据路径；布局归 #391） | ⬜ pending |
| 墙带常量对齐 | constants.gd `GRID_WALL_Y`/`WALL_BAND_HALF_HEIGHT` | #393 组装 | #384 落地后统一对齐（本 Issue 自带同值常量，见 §1.2） | ⬜ pending |

---

## 8. 实施阶段

| Phase | 优先级 | 组件 | 估算 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | `constants.gd` 常量组 + `game_manager.gd` 状态/终局/查询 API | 0.5 天 |
| Phase 2 | P0 | `ball.gd` `last_toucher`/`_crossed_wall`（边沿触发 + 复位） | 0.5 天 |
| Phase 3 | P0 | `scoring_manager.gd` 事件消费重构（拆砖/穿墙/兜底 + 容错连接 + 帧守卫） | 0.5 天 |
| Phase 4 | P1 | `game_state_machine.gd` SCORED 判定 + `game_over_screen.gd` 统计读取 | 0.5 天 |
| Phase 5 | P0 | 测试改造（test_game_manager/test_scoring_manager/test_ball/test_constants/run_tests）+ 新建 `test_dual_scoring.gd`，`godot --headless` 全绿 | 1 天 |

依赖顺序：Phase 1 → 2 → 3（核心链路）→ 5（验收）；Phase 4 可与 5 并行。

---

## 9. 测试用例描述

> 仅描述场景与断言，不写可运行代码。implement agent 按此实现 `test_dual_scoring.gd` 并改造既有套件（§2.9）。所有测试在 `godot --headless --script tests/run_tests.gd` 下运行。

### Scenario A: 拆砖分归属（AC1）
- **Test A-1 玩家触球拆砖**：预置 `ball.last_toucher = "player"` → 模拟 `ScoringManager._on_brick_destroyed(brick, pos)`（或直接调用 GameManager 路径）→ 断言 `player_score == 1`、`player_brick_count == 1`、`score_changed` 恰好一次且参数 [1, 0]。
- **Test A-2 AI 触球拆砖**：`last_toucher = "ai"` → 断言 `ai_score == 1`、`ai_brick_count == 1`，player 侧不变。
- **Test A-3 空触球者不计分**：`last_toucher = ""` → `_on_brick_destroyed` 后分数/计数全为 0、无 `score_changed`（边界 2）。
- **Test A-4 拆砖不触发 scored**：`_on_brick_destroyed` 后断言 ScoringManager `scored` 信号计数为 0（边界 8，不暂停比赛）。
- **Test A-5 多砖累计**：连续 3 次拆砖（同一触球方）→ 分数 +3、计数 +3、`score_changed` 3 次。

### Scenario B: 穿墙 3 分（AC2）
- **Test B-1 穿越后顶部出界**：`ball._crossed_wall = true` → `_on_ball_score(0)` → 断言 `player_score == 3`、`player_pierce_count == 1`、`scored` 触发（走 SCORED 流）。
- **Test B-2 穿越后底部出界**：`_crossed_wall = true` → `_on_ball_score(1)` → `ai_score == 3`、`ai_pierce_count == 1`。
- **Test B-3 未穿越出界兜底 1 分**：`_crossed_wall = false` → `_on_ball_score(0)` → `player_score == 1`、`pierce_count == 0`、`kind` 走 boundary（边界 3）。
- **Test B-4 拆砖 + 穿墙都计入**：先拆砖 +1 再穿墙 +3（不同帧）→ 总分 +4、两类计数各 1（打穿推进，PLAN §2.4）。

### Scenario C: 21 分终局（AC3）
- **Test C-1 恰好 21 分终局**：`add_score` 累计到 21（如 20 分 + 拆砖 1 分）→ `match_over` 恰好一次、winner 正确、`is_run_over() == true`。
- **Test C-2 终局后分数冻结**：终局后再次 `add_score`/`_on_ball_score`/`_on_brick_destroyed` → 分数/计数不变、无新信号（失败路径 2）。
- **Test C-3 20 分不终局**：20 分时无 `match_over`、`is_run_over() == false`。
- **Test C-4 AI 先到 21**：ai 侧累计 21 → `match_over("ai")` 恰好一次。
- **Test C-5 reset_match 重置终局**：终局后 `reset_match()` → 全部状态归零、`is_run_over() == false`，可重新开局。

### Scenario D: 同帧去重（AC4）
- **Test D-1 同帧拆砖 + 出界只计拆砖**：同帧先 `_on_brick_destroyed`（+1）后 `_on_ball_score`（穿越墙带，应 +3）→ 断言总分只 +1（拆砖）、无 +3（边界 1）。
- **Test D-2 不同帧各自计分**：拆砖帧后下一帧出界 → +1 +3 都计入。
- **Test D-3 帧守卫复位**：下一帧（无砖碎）出界 → 正常计出界分（守卫已复位）。

### Scenario E: 查询 API（AC5）
- **Test E-1 计数一致性**：混入拆砖/穿墙事件后，`get_brick_count("player"/"ai")`、`get_pierce_count("player"/"ai")` 与内部状态一致。
- **Test E-2 初始为零**：fresh GameManager 四个查询全为 0。
- **Test E-3 结算屏读取路径**：`_on_match_over` 后 GameOverScreen handler 能读取到统计（数据路径断言，布局不测）。

### Scenario F: ball 状态生命周期
- **Test F-1 触球记录归属**：`_on_area_entered` 传入 name=`PlayerPaddle`/`AIPaddle` 的 mock area → `last_toucher` 正确；未知名 → `""`。
- **Test F-2 serve 复位**：`serve()` 后 `last_toucher == ""`、`_crossed_wall == false`。
- **Test F-3 墙带边沿置位**：球位置从带外（y=600）移入带内（y=630）→ `_crossed_wall == true`；停留在带内不重复置位（已 true）。
- **Test F-4 发球位不误置位**：发球位置 (360, 640) 初始在带内，但 `serve()` 已复位且球离开带内前不置位（边沿触发语义，边界 7）。
- **Test F-5 触球复位穿越标记**：`_crossed_wall == true` 时挡板触球 → 复位为 false（失败路径 4）。
- **Test F-6 触砖反弹出界计 1 分**：`_crossed_wall == false` 出界 → 1 分（触砖反弹路径不误判 3 分）。

### Scenario G: 既有套件回归迁移
- **Test G-1** `test_game_manager.gd`：5 分/2 局断言全部移除，`add_score` 新签名（单参调用仍 +1 boundary）、TC5 非法 winner 语义保留。
- **Test G-2** `test_scoring_manager.gd`：`_on_ball_score` 3/1 路由、`brick_destroyed` 消费、终局守卫（`GameManager.is_run_over()` 返回 true 时事件被忽略）。
- **Test G-3** `test_ball.gd` 既有 walls/paddles 用例零回归（反弹数学/加速/反卡位不变）。
- **Test G-4** `test_constants.gd` 新增 §2.1 五个常量断言。

### Scenario H: 失败路径
- **Test H-1 容错连接**：无 BreakoutGrid 节点时 ScoringManager `_ready()` 不崩、`push_warning` 一次、其余计分正常（失败路径 1）。
- **Test H-2 容错后接线生效**：存在带 `brick_destroyed` 信号的 mock grid 时连接成功、事件被消费。
- **Test H-3 终局后事件忽略**：`is_run_over() == true` 时 `_on_ball_score`/`_on_brick_destroyed` 直接 return（失败路径 2）。

### Scenario I: FSM 集成
- **Test I-1 SCORED → GAME_OVER**：`GameManager.is_run_over() == true` 时 SCORED 计时结束 → GAME_OVER。
- **Test I-2 SCORED → SERVING**：未终局时 SCORED 计时结束 → SERVING（重发球）。
- **Test I-3 拆砖不触发 SCORED**：拆砖分后 FSM 状态不离开 PLAYING（边界 8，由 ScoringManager 不 emit `scored` 保证）。

---

## 附录 A: 与 PRD 的差异记录

| PRD 表述 | 本设计 | 原因 |
|---------|--------|------|
| `add_score(winner, amount, kind)`（PRD §3） | 采纳，`amount=1`/`kind="boundary"` 默认参数 | 兼容既有单参调用点（FSM/HUD 不直接调用） |
| `_is_run_over` 守卫（PRD §5 失败路径 2） | 放 GameManager + ScoringManager 双处检查（后者读 `GameManager.is_run_over()`） | 单一权威源，避免双标志漂移 |
| HUD 拆砖/穿墙小计（PRD §3 可选） | **不做**，game_hud.gd 零改动 | 总分联动已满足 AC1；细分 UI 归 #390/#392（PRD §1.5 范围边界） |
| ScoringManager `match_over` 信号（现有） | **删除**（FSM 已直连 GameManager.match_over） | 消除双终局信号源 |
| `test_dual_scoring.gd`（PRD §3 新建文件） | 采纳，测试描述见 §9 | 隔离测试先行，不依赖 #384 落地 |

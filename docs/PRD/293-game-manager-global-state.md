# PRD: [Feature] GameManager 全局状态 — Global State Singleton

> **Issue:** #293
> **标签:** enhancement, workflow/research, depth/light, priority/high, version/mvp, estimate/small
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #301 (Scaffold — CLOSED ✅), #291 (Scoring System — CLOSED ✅)

---

## 1. 问题定义

### 当前状态

Mini Pong 子项目的计分系统（#291）已通过 `ScoringManager`（`scoring_manager.gd`，112 行）实现完整的事件驱动计分逻辑：

| 组件 | 状态 | 细节 |
|------|:----:|------|
| `ScoringManager`（Node） | ✅ | `game.tscn` 场景级 Node：管理 `player_score`、`ai_score`、`player_games`、`ai_games`，信号 `scored`/`game_won`/`match_over` |
| `scoring_manager.gd` | ✅ | 112 行：常量 `POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2`；状态变量 `player_score`、`ai_score`、`player_games`、`ai_games`；`reset_game()` 内联在 `_win_game()` 中（分数归零） |
| `project.godot` autoload | ❌ | 无 `[autoload]` 段——当前无任何 autoload 注册 |
| 全局可访问的分数查询 | ❌ | 其他脚本需通过 `get_node("../ScoringManager")` 或信号连接访问分数——无 `GameManager.player_score` 全局路径 |
| `reset_match()` API | ❌ | 不存在——比赛重置（局数归零）需手动操作各变量 |
| `get_winner()` API | ❌ | 不存在——需自行检查 `ai_games >= 2` / `player_games >= 2` |

**当前 ScoringManager 状态（全部内联在场景节点中）：**

```
game.tscn
  ├── ScoringManager (Node, scoring_manager.gd)
  │     ├── player_score: int = 0
  │     ├── ai_score: int = 0
  │     ├── player_games: int = 0
  │     ├── ai_games: int = 0
  │     ├── signal scored(winner)
  │     ├── signal game_won(winner)
  │     └── signal match_over(winner)
```

**问题：**
- 计分状态绑定在 `game.tscn` 场景节点中——主场景被替换（如回到菜单再进入游戏）时状态丢失
- 任何外部系统（UI、状态机、测试）需通过树遍历 `get_node()` 或信号连接访问分数——无全局入口
- 无 `reset_match()` / `get_winner()` 便捷 API——每个消费者需自行实现重复逻辑
- 后续 Issue #294（状态机）、#292（UI）、#295（主场景组装）都需要统一的全局状态源

### 预期行为

创建 `GameManager` autoload 单例脚本，作为 Mini Pong 全局状态的唯一权威来源：

1. **Autoload 注册：** 在 `mini-pong/project.godot` 中注册 `GameManager` 为 autoload，路径 `res://gdscripts/game_manager.gd`，全局可通过 `GameManager.player_score` 访问
2. **状态管理：** 维护 `player_score`、`ai_score`、`player_games_won`、`ai_games_won` 四个核心变量
3. **配置常量：** `points_to_win_game=5`、`games_to_win_match=2` 硬编码（与 ScoringManager 保持一致）
4. **API 方法：**
   - `reset_game()` — 当局分数归零（player_score=0, ai_score=0）
   - `reset_match()` — 比赛重置（所有分数和局数归零）
   - `get_winner() -> String` — 返回当前胜者（`"player"` / `"ai"` / `""` 未决出）
5. **信号：**
   - `score_changed(player_score: int, ai_score: int)` — 每次得分后发射
   - `game_won(winner: String)` — 当局结束时发射
   - `match_over(winner: String)` — 比赛结束时发射
6. **编译验证：** `godot --path mini-pong/ --headless --quit` 无脚本错误

### 用户场景

| # | 场景 | 频率 |
|---|------|------|
| A | **全局分数查询：** UI HUD 脚本 `_process()` 中读取 `GameManager.player_score` 和 `GameManager.ai_score` 更新显示 | 每帧 |
| B | **信号驱动 UI 更新：** `GameManager.score_changed.connect(ui._on_score_changed)`——得分时 UI 自动刷新，无需轮询 | 每次得分 |
| C | **状态机判断胜负：** 状态机调用 `GameManager.get_winner()` 判断比赛是否结束 → 切换到 `game_over` 状态 | 每局/比赛结束 |
| D | **重新开始比赛：** 玩家在结束画面按 SPACE → 调用 `GameManager.reset_match()` → 所有状态归零 → 重新发球 | 每次重新开始 |
| E | **测试验证：** headless 测试中直接 `GameManager.add_score("player")` → 验证 `player_score==1` → `GameManager.reset_match()` → 验证所有值为 0 | 测试场景 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| `game_manager.gd` autoload 脚本 | ScoringManager 重构（#291 代码无需修改——GameManager 作为新层叠加） |
| `project.godot` 的 `[autoload]` 段 | 计分逻辑本身（球出界→得分判断已在 ScoringManager 中实现） |
| `reset_game()` / `reset_match()` / `get_winner()` API | 状态机逻辑（#294） |
| `score_changed` / `game_won` / `match_over` 信号 | UI 渲染（#292） |
| 四个核心状态变量 + 两个配置常量 | 主场景组装中的信号连线（#295） |
| `--headless --quit` 编译验证 | ScoringManager ↔ GameManager 的集成连线（属于 #295 集成 Issue） |

### 范围边界 vs 重叠 PRD

| PRD | Covers | NOT covered (left to this PRD) |
|-----|--------|--------------------------------|
| #291 计分系统 | `ScoringManager` Node：计分逻辑、`_on_ball_score()`、暂停-发球流程 | ❌ 全局可访问性——ScoringManager 是场景级 Node，#293 将其提升为 autoload 的全局 API |
| #301 项目骨架 | `mini-pong/project.godot` 基础配置（2D Forward+，glow） | ❌ `[autoload]` 段——骨架只创建最小 project.godot，不含 autoload |

**本 PRD 是游戏全局状态的 autoload 接入层**——它提供全局命名空间下统一的分数读写 API，不重复 ScoringManager 的计分逻辑。ScoringManager 的计分判断（球出界→`_on_ball_score()`→分数递增→局/比赛检查）保持不变；GameManager 作为状态"店面"供所有外部消费者（UI、状态机、测试）使用。

---

## 2. 设计意图

### 为什么是现在

#291 的 ScoringManager 已完整实现计分逻辑——球每次得分、每局结束、比赛结束均有对应的状态变更和信号发射。但这些状态绑定在 `game.tscn` 的单个 Node 上：

- **场景切换即丢失：** 后续 #294 状态机会在 `menu` → `playing` → `game_over` → `menu` 之间切换。如果 ScoringManager 随 `game.tscn` 的 `queue_free()` 销毁，分数和局数全部丢失
- **紧耦合访问：** UI（#292）需通过 `get_tree().root.get_node("Game/ScoringManager")` 或预先连接的信号才能获取分数——任何脚本都得"知道" ScoringManager 在场景树的哪个位置
- **无便捷重置 API：** 测试脚本（#297 的 100 回合自动对打）需要频繁重置比赛状态——无 `GameManager.reset_match()` 意味着每个测试都要手动清零四个变量

> **设计上下文（来自 game-to-issues-mini-pong.json #9）：** 「全局状态集中管理。Godot autoload 天然单例。」

GameManager 不是替代 ScoringManager——它是**在计分逻辑之上提供全局访问层**。这是 Godot 4.x autoload 的标准用途：将需要跨场景持久化、全局可访问的状态提升到 autoload。

### 设计原则

1. **单一数据源（Single Source of Truth）：** GameManager 是分数和局数的权威持有者。ScoringManager 后续可通过 `GameManager.add_score()` 更新状态，而非维护内部副本
2. **纯数据 + 信号：** GameManager 不包含游戏逻辑（不判断球出界、不处理暂停、不发球）。它只做状态存储 + 变更信号发射。逻辑仍在 ScoringManager 中
3. **最小 autoload 表面积：** 只暴露四个状态变量 + 三个 API 方法 + 三个信号。不处理输入、场景加载、UI 渲染
4. **Godot 4.x autoload 惯例：** 脚本 `extends Node`，在 `project.godot` 的 `[autoload]` 段以名称 `GameManager` 注册（首字母大写 PascalCase 命名，与 Godot 编辑器 autoload 面板惯例一致）
5. **与 ScoringManager 兼容：** 常量值（`POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2`）与 ScoringManager 保持一致。信号名称（`game_won`、`match_over`）与 ScoringManager 对齐，便于 #295 集成时桥接

### 先前约束

| 约束 | 来源 | 影响 |
|------|------|------|
| `mini-pong/project.godot` 无 `[autoload]` 段 | #301 骨架（最小 project.godot） | 本 Issue 需首次添加 `[autoload]`，是项目的第一个 autoload |
| `ScoringManager` 常量: `POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2` | #291 scoring_manager.gd L16-17 | GameManager 使用相同的常量值，确保一致性 |
| `ScoringManager` 信号: `scored(winner)` / `game_won(winner)` / `match_over(winner)` | #291 scoring_manager.gd L20-22 | GameManager 的信号名称 `game_won` / `match_over` 对齐；`score_changed` 是新增（携带具体分数值，不同于 `scored` 只带 winner） |
| ScoringManager 状态变量: `player_score`、`ai_score`、`player_games`、`ai_games` | #291 scoring_manager.gd L25-28 | GameManager 的变量命名对齐（`player_games_won` / `ai_games_won` 语义更清晰） |
| 默认分支为 `main` | 项目约定 | PR 目标 `main` |
| Godot 4.7.1 autoload 机制 | Godot 引擎 | autoload 脚本 `extends Node`，`_ready()` 在场景树根节点就绪后调用，全局可访问 |
| `godot --headless --quit` 编译验证 | CI pipeline | 新增 autoload 脚本不能有解析错误 |

---

## 3. 影响分析

### 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/gdscripts/game_manager.gd` | GDScript | GameManager autoload 脚本：状态变量、API 方法、信号定义 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `mini-pong/project.godot` | 新增 `[autoload]` 段，注册 `GameManager` → `res://gdscripts/game_manager.gd` |

### 间接影响模块（不修改源码）

| 模块 | 影响 |
|------|------|
| `ScoringManager`（#291） | 当前无需修改——ScoringManager 独立运作。后续 #295 集成时需桥接：`scored.connect(GameManager._on_scored)` |
| UI 系统（#292） | 后续可通过 `GameManager.player_score` 直接读取分数（替代 `get_node("../ScoringManager").player_score`） |
| 状态机（#294） | 后续可调用 `GameManager.get_winner()` 判断比赛是否结束 |
| 100 回合测试（#297） | 后续可调用 `GameManager.reset_match()` 快速重置状态 |
| 主场景组装（#295） | 后续负责 ScoringManager ↔ GameManager 的信号桥接 |
| 现有 `ball.gd`、`paddle.gd`、`ball_trail.gd`、`score_flash.gd` | 无影响——这些模块不读取计分状态 |

### 数据流

```
当前:
  Ball.score(side)
    → ScoringManager._on_ball_score()
        → 内部更新 player_score, ai_score, player_games, ai_games
        → 发射 scored / game_won / match_over
    → UI / 测试需通过 get_node() 访问 ScoringManager 变量

添加 GameManager 后 (autoload):
  GameManager (全局单例)
    ├── player_score, ai_score, player_games_won, ai_games_won
    ├── add_score(winner)      ← ScoringManager 调用（#295 集成）
    ├── reset_game()           ← 状态机 / 测试调用
    ├── reset_match()          ← 状态机 / 测试调用
    ├── get_winner() -> String ← UI / 状态机 / 测试调用
    └── 信号: score_changed, game_won, match_over
         ↓
    UI (#292) / 状态机 (#294) / 测试 (#297) 直接连接
```

### 文档更新

- 无需更新现有文档

---

## 4. 方案对比

### 方案 A：独立 autoload GameManager + ScoringManager 桥接（推荐）

创建 `game_manager.gd` 作为 autoload，持有权威状态。ScoringManager 暂不修改——在后续 #295 集成 PR 中通过信号桥接：`ScoringManager.scored.connect(GameManager._on_scored)`。GameManager 提供 `add_score(winner)` 方法供 ScoringManager 调用。

**GameManager 核心结构：**

```gdscript
# game_manager.gd — autoload singleton
extends Node

# ── Configuration ──
const POINTS_TO_WIN_GAME: int = 5
const GAMES_TO_WIN_MATCH: int = 2

# ── Signals ──
signal score_changed(player_score: int, ai_score: int)
signal game_won(winner: String)
signal match_over(winner: String)

# ── State ──
var player_score: int = 0
var ai_score: int = 0
var player_games_won: int = 0
var ai_games_won: int = 0

# ── API ──
func add_score(winner: String) -> void:
    match winner:
        "player": player_score += 1
        "ai":     ai_score += 1
    score_changed.emit(player_score, ai_score)
    _check_game_win()

func reset_game() -> void:
    player_score = 0
    ai_score = 0

func reset_match() -> void:
    player_score = 0
    ai_score = 0
    player_games_won = 0
    ai_games_won = 0

func get_winner() -> String:
    if player_games_won >= GAMES_TO_WIN_MATCH:
        return "player"
    if ai_games_won >= GAMES_TO_WIN_MATCH:
        return "ai"
    return ""

func _check_game_win() -> void:
    if player_score >= POINTS_TO_WIN_GAME:
        _win_game("player")
    elif ai_score >= POINTS_TO_WIN_GAME:
        _win_game("ai")

func _win_game(winner: String) -> void:
    game_won.emit(winner)
    match winner:
        "player": player_games_won += 1
        "ai":     ai_games_won += 1
    player_score = 0
    ai_score = 0
    if player_games_won >= GAMES_TO_WIN_MATCH or ai_games_won >= GAMES_TO_WIN_MATCH:
        match_over.emit(winner)
```

| 优点 | 缺点 |
|------|------|
| 最小侵入——创建 1 个新文件 + project.godot 2 行配置 | 当前 ScoringManager 和 GameManager 各自持有状态副本（临时——#295 集成后统一） |
| Godot 标准 autoload 模式——任何脚本直接 `GameManager.player_score` | 需要 #295 集成步骤桥接 ScoringManager → GameManager |
| 完整的全局 API——`reset_game()` / `reset_match()` / `get_winner()` 填补 ScoringManager 的功能空白 | 计分逻辑在 GameManager 中有部分重复（`_check_game_win()` / `_win_game()`） |
| 信号携带具体值——`score_changed(player_score, ai_score)` 让消费者无需再次读取状态 | |
| `--headless --quit` 编译友好——autoload 在 headless 模式下正常加载 | |

**风险：** 低
**工作量：** 小（~60 行 GDScript + project.godot 2 行）

---

### 方案 B：ScoringManager 提升为 autoload

将现有的 `scoring_manager.gd` 直接注册为 autoload，移除 `game.tscn` 中的 ScoringManager 节点。autoload 的 `_ready()` 中通过场景树查找 Ball 节点。

| 优点 | 缺点 |
|------|------|
| 零新文件 | `scoring_manager.gd` 的 `_ready()` 依赖 `$\"../Ball\"` 路径——autoload 的 `_ready()` 时机不确定，Ball 可能尚未实例化 |
| 不重复计分逻辑 | `@onready var ball = $\"../Ball\"` 在 autoload 中无效（autoload 不在 game.tscn 树中） |
| | ScoringManager 管理计分逻辑 + 全局状态——违反单一职责 |
| | 修改 `scoring_manager.gd` 增加 #291 回归风险 |
| | 移除 `game.tscn` 中的 ScoringManager 节点——破坏现有场景结构 |

**风险：** 中（autoload 生命周期问题 + 破坏现有场景）
**工作量：** 中

---

### 方案 C：GameManager 纯代理——从 ScoringManager 读取状态

GameManager 作为 autoload，但不持有自身状态。所有 `player_score` 等 getter 实际读取场景中的 `ScoringManager` 节点状态。

```gdscript
func _get_sm():
    var tree := get_tree()
    if tree and tree.root:
        return tree.root.get_node_or_null("Game/ScoringManager")
    return null

var player_score: int:
    get: return _get_sm().player_score if _get_sm() else 0
```

| 优点 | 缺点 |
|------|------|
| 零状态重复——GameManager 纯代理 | 强依赖场景树布局——`"Game/ScoringManager"` 路径变化即崩溃 |
| ScoringManager 保持唯一权威 | 无法使用 `setget` 写回（需额外 setter 逻辑） |
| | autoload 不能 emit 信号用于 UI（信号源应是 GameManager 自身，而非代理） |
| | `reset_match()` 需要调用 ScoringManager 方法——但 ScoringManager 当前无此方法 |
| | headless 测试时 ScoringManager 可能不存在——getter 返回 0 掩盖真实错误 |

**风险：** 高（强场景树耦合 + headless 不可靠）
**工作量：** 小（但技术债务高）

---

### 推荐：方案 A — 独立 autoload GameManager

对 Mini Pong 的全局状态管理，方案 A 是最佳选择：

1. **Godot autoload 标准模式：** `extends Node` → `project.godot [autoload]` 注册 → 全局命名空间可访问。这是 Godot 4.x 文档推荐的全局单例模式
2. **职责分离：** ScoringManager 负责计分**逻辑**（何时得分、暂停、发球），GameManager 负责状态**存储和访问**（分数值、局数、重置 API）。两者各司其职
3. **ScoringManager 不变：** 不需要修改 `scoring_manager.gd`——避免 #291 回归风险。GameManager 作为新层叠加，#295 集成时桥接
4. **完整的全局 API：** `reset_game()` / `reset_match()` / `get_winner()` 三个方法填补了 ScoringManager 的功能空白，直接供 UI、状态机、测试使用
5. **信号更丰富：** `score_changed(p_score, ai_score)` 携带具体分数值——UI 不需要再次查询状态即可更新显示

---

## 5. 边界条件与验收标准

### 验收标准

- [ ] **AC1: autoload 注册，全局可访问** — `mini-pong/project.godot` 含 `[autoload]` 段，`GameManager="*res://gdscripts/game_manager.gd"`。任何脚本可通过 `GameManager.player_score` 读写（无需 `get_node()`）
- [ ] **AC2: 管理双方分数和局数** — 四个变量 `player_score`、`ai_score`、`player_games_won`、`ai_games_won` 初始值为 0，外部脚本可直接读写
- [ ] **AC3: `reset_game()` 仅重置当局分数** — 调用后 `player_score=0, ai_score=0`，`player_games_won` 和 `ai_games_won` 保持不变
- [ ] **AC4: `reset_match()` 重置全部状态** — 调用后四个变量均为 0
- [ ] **AC5: `get_winner()` 返回正确胜者** — `player_games_won >= 2` → 返回 `"player"`；`ai_games_won >= 2` → 返回 `"ai"`；否则返回 `""`（空字符串）
- [ ] **AC6: `add_score(winner)` 递增分数并检查胜负** — 调用 `add_score("player")` → `player_score += 1` → emit `score_changed(player_score, ai_score)` → 达到 5 分时 emit `game_won` → 达到 2 局时 emit `match_over`
- [ ] **AC7: `score_changed` 信号** — 每次 `add_score()` 调用后发射，携带当前的 `(player_score, ai_score)` 值
- [ ] **AC8: `game_won` 信号** — 任意一方达到 `POINTS_TO_WIN_GAME=5` 分时发射，参数为 `"player"` 或 `"ai"`
- [ ] **AC9: `match_over` 信号** — 任意一方达到 `GAMES_TO_WIN_MATCH=2` 局时发射，参数为 `"player"` 或 `"ai"`
- [ ] **AC10: `--headless --quit` 无脚本错误** — `godot --path mini-pong/ --headless --quit` 退出码 0，无 SCRIPT ERROR

### 边缘情况

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | `add_score()` 在 `match_over` 之后调用 | 不阻止——状态机/测试可能在比赛结束后仍调用。`player_score` 继续递增，但不触发新的 `match_over`（因为 `_check_game_win()` 中 `player_score >= 5` 会再次触发 `game_won` 和局数递增——这是调用方的责任，GameManager 不做保护） |
| 2 | `add_score()` 传入非法 winner 值 | `match winner` 的 `"player"` / `"ai"` 分支不匹配 → 分数不变。可考虑添加 `push_warning()` |
| 3 | 同一方连续达到 5 分多次（`add_score` 被重复调用） | 每次达到 5 分都触发 `_win_game()` → `game_won` 信号 + 局数递增 + 分数归零。调用方应确保只在球得分时调用一次 |
| 4 | `get_winner()` 在双方都 < 2 局时调用 | 返回 `""`（空字符串）——消费者可检查 `result != ""` 判断比赛是否结束 |
| 5 | `reset_game()` 在比赛未开始时调用 | 正常执行——将分数归零（不影响局数） |
| 6 | `reset_match()` 在比赛进行中调用 | 正常执行——所有状态归零。不阻止、不警告——这是合法的"强制重置"操作 |
| 7 | 多个脚本同时读写 `player_score` | GDScript 单线程——无竞态条件。但外部直接写 `GameManager.player_score = 999` 可能破坏计分逻辑——这是 API 使用约定问题，非技术防护 |
| 8 | autoload `_ready()` 在 Ball 就绪前执行 | GameManager 不引用任何场景节点——无生命周期依赖。`_ready()` 可为空 |

### 失败路径

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | `project.godot` 的 `[autoload]` 路径错误 | Godot 启动时报错 "Can't load autoload script"——headless 编译失败 |
| 2 | `game_manager.gd` 语法错误 | 脚本解析失败 → `--headless --quit` 非零退出码 |
| 3 | 信号无监听者 | Godot 4.x 信号发射无副作用——只是事件丢失，不导致崩溃 |

---

## 6. 依赖与阻塞

> ℹ️ 本节可选（`depth/light`），但因 #293 有明确的依赖链，列入以供 Plan Agent 参考。

### 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|------|
| #301 项目骨架 | ✅ CLOSED — `mini-pong/` 子项目、project.godot 已就绪 | 无 |
| #291 计分系统 | ✅ CLOSED — `ScoringManager` 计分逻辑已实现，常量值已知 | 无 |

### 阻塞（后续 Issue）

| 后续工作 | 优先级 | 关系 |
|---------|:------:|------|
| #295 主场景组装 | critical | 负责 ScoringManager ↔ GameManager 信号桥接（`ScoringManager.scored.connect(GameManager._on_scored)`） |
| #292 UI 系统 | high | 通过 `GameManager.score_changed` 信号更新 HUD |
| #294 游戏状态管理 | high | 状态机调用 `GameManager.get_winner()` / `reset_match()` |

### 依赖链

```
#301 (Scaffold) ──► #291 (ScoringManager) ──► #293 (GameManager autoload)
                                                   │
                                                   ├──► #292 (UI)
                                                   ├──► #294 (State machine)
                                                   └──► #295 (Integration)
```

---

## 8. 延续上下文（Plan Agent 交接）

### 当前系统状态

- `mini-pong/project.godot` — 当前无 `[autoload]` 段。需新增 `[autoload]` section，注册 `GameManager="*res://gdscripts/game_manager.gd"`
- `mini-pong/gdscripts/scoring_manager.gd` — 112 行，管理 `player_score`、`ai_score`、`player_games`、`ai_games`，信号 `scored`/`game_won`/`match_over`。**本次不修改**——后续 #295 集成
- `mini-pong/scenes/game.tscn` — 含 TopWall, BottomWall, Ball, PlayerPaddle, AIPaddle, ScoringManager。**本次不修改**
- `mini-pong/gdscripts/` — 现有 5 个脚本：ball.gd, paddle.gd, scoring_manager.gd, score_flash.gd, ball_trail.gd。新增第 6 个：`game_manager.gd`

### 实施注意事项

1. **文件位置：** `game_manager.gd` 放在 `mini-pong/gdscripts/`，与其他脚本同级

2. **project.godot autoload 格式：**

   Godot 4.x ConfigFile 格式在 `[autoload]` 段使用 `名称="*路径"` 语法（注意 `*` 前缀表示全局单例）：
   ```ini
   [autoload]
   GameManager="*res://gdscripts/game_manager.gd"
   ```
   参考 Godot 4.x 文档：autoload 脚本路径使用 `res://` 前缀。`*` 表示该 autoload 是全局可访问的单例（`*` 前缀在 Godot 4.x 中为可选但推荐）。

3. **脚本签名：**
   ```gdscript
   extends Node
   ```
   不需要 `class_name`——autoload 的名称由 `project.godot` 的键名决定（`GameManager`）

4. **`add_score()` 的信号发射顺序：**
   ```
   add_score("player")
     → player_score += 1
     → score_changed.emit(player_score, ai_score)    # 1st
     → _check_game_win()
       → if 5 pts: game_won.emit("player")            # 2nd
       → if 2 games: match_over.emit("player")        # 3rd
   ```
   信号顺序重要——UI 应先更新分数，再处理局/比赛结束动画

5. **常量对齐：** `POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2` 与 ScoringManager 保持一致。未来如需调整，两处需同步修改（或提取到独立 constants 脚本）

6. **验证方法：**
   ```bash
   # 编译验证 — autoload 脚本解析 + project.godot 加载
   godot --path mini-pong/ --headless --quit
   echo "Exit: $?"

   # 验证 autoload 注册成功 — 运行简单测试脚本
   cat > /tmp/test_gm.gd << 'EOF'
   extends Node
   func _ready():
       assert(GameManager != null, "GameManager autoload not found")
       assert(GameManager.player_score == 0)
       assert(GameManager.ai_score == 0)
       GameManager.add_score("player")
       assert(GameManager.player_score == 1)
       GameManager.reset_match()
       assert(GameManager.player_score == 0)
       assert(GameManager.get_winner() == "")
       print("ALL GAMEMANAGER TESTS PASSED")
       get_tree().quit(0)
   EOF
   godot --path mini-pong/ --headless --script /tmp/test_gm.gd
   ```

7. **外部直接写状态的支持：**
   GameManager 的 `var player_score: int = 0` 是可公开读写的——外部脚本可以直接 `GameManager.player_score = 10`。这是设计意图（灵活性 > 封装性），但 #295 集成时应通过 `add_score()` 而非直接赋值

8. **headless 兼容：** GameManager 不引用任何场景节点、不使用 `@onready`、不访问 `get_viewport()`——headless 模式下完全兼容

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|:------:|:----:|---------|
| `project.godot` autoload 格式错误 | 低 | 高（Godot 无法启动） | 使用已知正确格式 `名称="*res://路径"`；创建后立即 headless 验证 |
| autoload 名称与现有全局冲突 | 低 | 中 | `GameManager` 命名唯一——当前项目无同名的 class_name 或 autoload。`_ready()` 中可调用 `assert(get_tree().root.has_node("GameManager"))` 验证 |
| ScoringManager 与 GameManager 的 `_win_game()` 逻辑重复 | 中 | 低（功能上正确但需维护两处） | 当前阶段可接受——#295 集成后 ScoringManager 可选改为调用 GameManager |
| 外部直接写 `player_score` 绕过 `add_score()` 的信号发射 | 中 | 中（分数静默修改，UI 不更新） | 约定优于强制——文档注明使用 `add_score()` 更新分数。后续可通过 setget 添加写保护 |

### 设计决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 架构模式 | 独立 autoload（非 ScoringManager 提升） | 职责分离：GameManager = 状态存储，ScoringManager = 计分逻辑 |
| 变量命名 | `player_games_won` / `ai_games_won` | 语义更清晰——区别于 ScoringManager 的 `player_games` / `ai_games` |
| `get_winner()` 返回值 | `"player"` / `"ai"` / `""` | 与 ScoringManager 信号参数格式一致；空字符串表示"未决出" |
| 状态可读写 | `var` 而非 setget 保护 | 灵活优先——测试和调试可直接赋值；生产代码通过 `add_score()` |
| autoload 名称 | `GameManager`（PascalCase） | Godot 编辑器 autoload 面板默认大写首字母 |
| autoload 路径前缀 | `*` 星号 | Godot 4.x 全局单例惯例；省略星号也可工作但编辑器不显示单例标记 |

### 下一步

Plan Agent 将基于此 PRD 创建 `docs/DESIGN/293-game-manager-global-state.md`，详细指定：
- `game_manager.gd` 完整 API（所有变量、方法、信号的签名和文档注释）
- `project.godot` 的 `[autoload]` 段精确格式
- 与 ScoringManager 的状态对照表（哪些变量对应，哪些是新增）
- #295 集成时的信号桥接规范（`ScoringManager.scored → GameManager.add_score`）

Implement Agent 将：
1. 创建 `mini-pong/gdscripts/game_manager.gd`（~55-65 行）
2. 修改 `mini-pong/project.godot`（新增 `[autoload]` 段）
3. 运行 `godot --path mini-pong/ --headless --quit` 验证编译通过
4. （可选）运行 headless 测试脚本验证 autoload 注册和 API 正确性

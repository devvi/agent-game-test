# PRD: [Integration] 主场景组装 — Main Scene Assembly

> **Issue:** #295
> **标签:** enhancement, workflow/research, depth/standard, priority/high, version/mvp, estimate/medium
> **Agent:** game-research-agent
> **日期:** 2026-07-30
> **前置依赖:** #287, #288, #290, #291, #289, #292, #294, #293

---

## 1. 问题定义

### 当前状态

Mini Pong 的所有独立组件（#287–#294）已全部实现并通过测试。`game.tscn` 在历次实现中逐步累积了组件实例，当前已包含大部分所需节点，但存在以下缺口：

| 组件 | Issue # | 当前状态 | 缺失 |
|------|---------|:-------:|------|
| Ball (Area2D) | #287 | ✅ 已实例化 | — |
| PlayerPaddle (Area2D, mode=PLAYER) | #288 | ✅ 已实例化 | — |
| AIPaddle (Area2D, mode=AI) | #290 | ✅ 已实例化 | — |
| TopWall (StaticBody2D) | #287 | ✅ 内联 sub_resource | — |
| BottomWall (StaticBody2D) | #287 | ✅ 内联 sub_resource | — |
| ScoringManager (Node) | #291 | ✅ 已实例化 | — |
| GameStateMachine (Node) | #294 | ✅ 已实例化 | — |
| StartMenu (CanvasLayer) | #292 | ✅ 已实例化 | — |
| GameHUD (CanvasLayer) | #292 | ✅ 已实例化 | — |
| GameOverScreen (CanvasLayer) | #292 | ✅ 已实例化 | — |
| **WorldEnvironment** | #289 | ❌ 未实例化 | `world_environment.tscn` 存在但未在 game.tscn 中实例化 |
| **ScoreZones (左/右)** | — | ❌ 不存在 | 球通过 `_process()` 中 X 坐标检测得分，无显式 ScoreZone 节点 |
| **全局常量文件** | — | ❌ 分散 | 常量分散在 4 个脚本中：`ball.gd`（球物理）、`paddle.gd`（AI 参数）、`game_manager.gd`（计分阈值）、`scoring_manager.gd`（**与 GameManager 重复定义**） |
| **ScoreFlash 节点** | #289 | ❌ 未实例化 | `score_flash.gd` 存在（48 行），但 game.tscn 中无 ScoreFlash 节点 |
| **场景文件命名** | — | 🟡 `game.tscn` | Issue 要求 `Main.tscn` — 需重命名 |

**当前 game.tscn 节点结构（140 行）：**

```
Game (Node2D)
├── TopWall (StaticBody2D, groups=["walls"])
│   └── CollisionShape2D (RectangleShape2D, 1280×10)
├── BottomWall (StaticBody2D, groups=["walls"])
│   └── CollisionShape2D (RectangleShape2D, 1280×10)
├── Ball (instance of ball.tscn)
├── PlayerPaddle (instance of player_paddle.tscn, x=50, mode=PLAYER)
├── AIPaddle (instance of player_paddle.tscn, x=1230, mode=1=AI)
├── ScoringManager (Node, scoring_manager.gd)
├── GameStateMachine (Node, game_state_machine.gd)
│   └── NodePath exports → StartMenu, GameHUD, GameOverScreen, Ball, PlayerPaddle, AIPaddle, ScoringManager
├── StartMenu (CanvasLayer, layer=1, visible=true)
├── GameHUD (CanvasLayer, layer=0, visible=false)
└── GameOverScreen (CanvasLayer, layer=1, visible=false)
```

**当前信号链路（大部分已连接）：**

```
Ball.score(side: int)
    │
    ▼
ScoringManager._on_ball_score(side)
    ├── scored(winner) ──────► GameStateMachine._on_scored() → SCORED 状态
    ├── scored(winner) ──────► ScoreFlash._on_score_changed()  ← ✅ connected in _ready()
    └── GameManager.add_score(winner)
            │
            ├── score_changed(p,a) ──► GameHUD._on_score_changed()  ← ✅ connected
            ├── game_won(winner)    ──► (无人监听)
            └── match_over(winner)  ──► GameStateMachine._on_match_over()  ← ✅ connected
                                    ──► GameOverScreen._on_match_over()    ← ✅ connected
```

**已发现的具体问题：**

1. **WorldEnvironment 缺失：** `world_environment.tscn` 定义了 `glow_intensity=0.6` 和 `glow_bloom=0.8`，但 project.godot 仅设置了 `glow_enabled=true` 和 `default_clear_color`，缺少 bloom 阈值。没有 WorldEnvironment 节点实例时，glow 使用引擎默认值而非设计值。

2. **常量重复定义：** `scoring_manager.gd` 和 `game_manager.gd` 都定义了 `POINTS_TO_WIN_GAME=5` 和 `GAMES_TO_WIN_MATCH=2`。如果调参需要改两处，容易不同步。

3. **ScoreZones 缺失：** 当前球的得分检测完全依赖 `ball.gd:120-126` 中的硬编码 X 边界判断 `position.x < -BALL_RADIUS` 和 `position.x > screen_width + BALL_RADIUS`。显式 ScoreZone 节点提供更好的编辑器可视化、碰撞层级分离、以及未来扩展性（如不对称边界）。

4. **ScoreFlash 场景缺失：** `score_flash.gd` 已实现并在 `scoring_manager.gd:46` 中通过 duck-typing 连接信号，但 game.tscn 中无 ScoreFlash 节点，导致得分闪烁效果不生效。

5. **场景文件名：** 当前为 `game.tscn`，Issue 要求 `Main.tscn`。需要评估重命名的影响范围（project.godot `run/main_scene`、所有测试引用、DESIGN 文档）。

6. **球/球拍颜色未应用霓虹材质：** GDD 指定玩家蓝 `#4a90d9`、AI 红 `#ff3355`，球白色，但 `.tscn` 场景文件中 ColorRect 的 `color` 仍为 `Color(1,1,1,1)`（白色）。PRD #289 预期的 ShaderMaterial 外发光也未在场景树中应用。

### 预期行为

1. **Main.tscn 场景树完整：** 包含 Issue 指定的全部 12 类节点（Ball、PlayerPaddle、AIPaddle、Walls×2、ScoreZones×2、WorldEnvironment、CanvasLayer/UI×3、GameStateMachine、GameManager autoload）
2. **信号链路验证并修复：** 审核所有信号连接，补全断裂链路（ScoreFlash 实例化、game_won 消费者）
3. **全局常量统一配置：** 提取分散在 4 个脚本中的常量到单一 `constants.gd` 文件，消除重复定义
4. **菜单→对打→得分→局胜→结束→重开链路正常：** 端到端场景流验证
5. **编译验证：** `godot --path mini-pong/ --headless --quit` 无脚本错误
6. **霓虹视觉生效：** WorldEnvironment glow、ball trail、score flash 在运行时可观测

### 范围边界 vs 重叠 PRD

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #287 (Ball Physics) | 球物理：Area2D + manual `_process` 运动、墙壁/挡板碰撞、发球 | ❌ 不修改 ball.gd 逻辑 — 只编排其在场景中的位置和信号连接 |
| #288 (Player Paddle) | 玩家挡板：WASD 输入、移动、边界 clamp | ❌ 不修改 paddle.gd 逻辑 |
| #290 (AI Opponent) | AI 行为：球追踪、反应延迟、速度调整 | ❌ AI 参数不从本 PRD 引入 — 已在 paddle.gd 中 @export |
| #291 (Scoring System) | 计分逻辑：score → scored/game_won/match_over 信号链 | ❌ 不修改 scoring_manager.gd — 只确保信号消费者存在 |
| #289 (Neon Visual) | 视觉系统：glow shader、ball trail、score flash、颜色约定 | ❌ 不复现 ShaderMaterial 开发 — 只实例化 WorldEnvironment 和 ScoreFlash |
| #292 (UI System) | UI 三层：StartMenu、GameHUD、GameOverScreen | ❌ 不修改 UI 脚本 — CanvasLayer 已在 scene tree 中 |
| #293 (GameManager) | 全局状态：autoload 单例、分数/信号 API | ❌ 不修改 game_manager.gd — 只消除与 ScoringManager 的常量重复 |
| #294 (Game State Machine) | 5-state FSM：MENU → SERVING → PLAYING → SCORED → GAME_OVER | ❌ 不修改 game_state_machine.gd — NodePath 已在 game.tscn 中配置 |

**本 PRD 独占范围：** 场景文件本身（节点树结构、NodePath 配置、ext_resource 引用）、WorldEnvironment 实例化、ScoreZone 节点创建、全局常量文件 `constants.gd` 提取、信号链路完整性审核与修复、引用的批量更新（project.godot、测试文件、DESIGN 文档）。

### 用户场景

| # | 场景 | 频率 |
|---|------|------|
| A | 启动游戏 → Main.tscn 加载 → StartMenu 可见，WorldEnvironment 背景生效 | 每次启动 |
| B | 按 SPACE → 进入 SERVING → 1 秒后发球 → PLAYING | 每局 |
| C | 对打中球出界 → ScoreFlash 闪烁 → 分数更新 → 1 秒暂停 → 重新发球 | 每分 |
| D | 一方 5 分 → game_won → 继续下一局 | 每局 |
| E | 一方 2 局 → match_over → GameOverScreen 显示胜者 | 每场比赛 |
| F | 比赛结束按 SPACE → 回到 MENU，分数重置 | 每场比赛结束 |

---

## 2. 设计意图

### 为什么当前状态存在

| Issue | 贡献的状态 | 说明 |
|-------|----------|------|
| #287 | game.tscn 创建 + Ball/Walls 实例化 | 球物理开发时需要一个容器场景来测试碰撞 |
| #288 | PlayerPaddle 实例化 | 玩家输入测试需要 paddles group |
| #290 | AIPaddle 实例化（复用 player_paddle.tscn, mode=1） | AI 行为测试需要对手 paddle |
| #291 | ScoringManager Node 实例化 | 计分需要 ball.score 信号的消费者 |
| #292 | 3 个 CanvasLayer 节点（内联创建，非 ext_resource instance） | UI 脚本需要 CanvasLayer 容器 — 直接在 game.tscn 中构建了 UI 节点树 |
| #294 | GameStateMachine Node + NodePath exports | FSM 需要所有子系统的引用 |
| #289 | WorldEnvironment.tscn 和 score_flash.gd 创建，但未接入 game.tscn | 视觉系统作为独立资源开发，等待集成步骤 |
| — | 常量分散定义 | 各组件独立开发时自行定义所需常量 |

### 为什么现在变更

所有 8 个前置 Issue 已 CLOSED，组件开发阶段结束。这是 MVP 的最后一个 Integration Issue — 将独立组件组装为可运行的完整游戏。变更点：

1. **WorldEnvironment 连接：** 视觉系统（#289）的资源已就绪，但从未接入场景树。这是使游戏"看起来像设计稿"的最后一步。
2. **ScoreZones 显式化：** #287 的 `_process` X 边界检测是一个开发期的快速实现。显式 ScoreZone Area2D 节点提供更好的关注点分离（球负责运动，Zone 负责得分）和编辑器可视化。
3. **常量去重：** ScoringManager 和 GameManager 各自维护了相同的计分阈值常量，存在不同步风险。
4. **ScoreFlash 实例化：** score_flash.gd 已实现但无宿主节点，得分闪烁效果完全不可见。
5. **命名规范化：** 根据架构惯例，主场景命名为 `Main.tscn` 而非 `game.tscn`。

### 前置约束

| 约束 | 详情 |
|------|------|
| 引擎版本 | Godot 4.7.x（Forward+ 渲染器） |
| 子项目路径 | `mini-pong/` |
| 场景类型 | 2D（Node2D root） |
| Viewport | 1280×720，无窗口缩放 |
| 无新功能 | 本 Issue 只做胶水代码 — 不添加任何新游戏逻辑 |
| Autoload | GameManager 已注册为 autoload（`project.godot:16`） |
| 颜色约定 | 玩家蓝 #4a90d9，AI 红 #ff3355，背景 #0a0a12（来自 #289） |
| 组件独立性 | 各 .tscn 场景保持独立，通过 ext_resource 引用而非内联 |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/scenes/game.tscn` → `Main.tscn` | 主场景 | **RENAME + MODIFY** — 添加 WorldEnvironment、ScoreZones、ScoreFlash 节点；调整 ext_resource ID 映射 |
| `mini-pong/project.godot` | 项目配置 | **MODIFY** — `run/main_scene` 从 `game.tscn` 改为 `Main.tscn` |
| `mini-pong/gdscripts/constants.gd` | 全局常量（新） | **CREATE** — 提取分散的常量（屏幕尺寸、球物理、挡板参数、计分阈值、AI 参数、颜色值） |

### 新增文件

| 文件 | 类型 | 内容 |
|------|------|------|
| `mini-pong/scenes/Main.tscn` | Godot Scene | 重命名自 `game.tscn`，添加 WorldEnvironment/ScoreZones/ScoreFlash |
| `mini-pong/gdscripts/constants.gd` | GDScript (class_name) | 集中定义所有全局常量，使用 `class_name GameConstants` |

### 间接影响模块

| 文件 | 影响 | 处理方式 |
|------|------|---------|
| `mini-pong/scenes/game.tscn` | 重命名后删除 | `git mv` 或删除后创建 Main.tscn |
| `mini-pong/tests/test_ball.gd:119,139` | 硬编码 `game.tscn` 路径 | 更新为 `Main.tscn` |
| `mini-pong/tests/test_ui_system.gd:419-427` | 硬编码 `game.tscn` 路径 | 更新为 `Main.tscn` |
| `mini-pong/tests/test_game_state_machine.gd` | 可能引用 game.tscn | 审核并更新路径 |
| `mini-pong/gdscripts/game_state_machine.gd:23,194` | 注释中提到 game.tscn | 更新注释 |
| `mini-pong/gdscripts/scoring_manager.gd` | `POINTS_TO_WIN_GAME`/`GAMES_TO_WIN_MATCH` → 改用 `GameConstants` | 常量引用改为 `GameConstants.POINTS_TO_WIN_GAME` |
| `mini-pong/gdscripts/game_manager.gd` | 同上 | 常量引用改为 `GameConstants` |
| `mini-pong/gdscripts/ball.gd` | 球物理常量 → `GameConstants` | 迁移至 constants.gd，ball.gd 引用 `GameConstants.BALL_INITIAL_SPEED` 等 |
| `mini-pong/gdscripts/paddle.gd` | 挡板/AI 常量 → `GameConstants` | 迁移至 constants.gd，paddle.gd 引用 `GameConstants.PADDLE_SPEED` 等 |
| `docs/GAME_DESIGN/10–17` | 可能引用 `game.tscn` | 批注为已重命名为 `Main.tscn` |
| `docs/DESIGN/287–294` | 可能引用 `game.tscn` | 设计文档保留原样（历史记录），但当前 PRD 注明重命名 |

### 数据流影响

**当前信号流（已有链路 — 加粗为已验证连接）：**

```
Ball._process() X 边界检测
    │
    ├── score(0 or 1) ────► ScoringManager._on_ball_score(side)
    │                           │
    │                           ├── scored(winner) ───► GameStateMachine._on_scored()  ← ✅
    │                           │                       PLAYING → SCORED
    │                           │
    │                           ├── scored(winner) ───► ScoreFlash._on_score_changed() ← ✅ connected
    │                           │                       ⚠️ ScoreFlash Node 不存在！
    │                           │
    │                           └── GameManager.add_score(winner)
    │                                   │
    │                                   ├── score_changed(p,a) ──► GameHUD._on_score_changed()  ← ✅
    │                                   ├── game_won(winner)  ──► ⚠️ 无人监听
    │                                   └── match_over(winner) ──► GameStateMachine._on_match_over() ← ✅
    │                                                           ──► GameOverScreen._on_match_over()  ← ✅
    │
    └── ⚠️ 硬编码 X 坐标判断得分 → 计划迁移至 ScoreZone Area2D body_entered
```

**修复后的信号流（目标状态）：**

```
ScoreZoneRight Area2D
    ├── body_entered(Ball) → score.emit(1)  (right zone = AI scores)
    │
ScoreZoneLeft Area2D
    ├── body_entered(Ball) → score.emit(0)  (left zone = player scores)
    │
    ▼
ScoringManager._on_ball_score(side)
    │
    ├── scored(winner) ───► GameStateMachine._on_scored()
    │                       PLAYING → SCORED
    │
    ├── scored(winner) ───► ScoreFlash._on_score_changed()  ← ✅ 节点存在后实际生效
    │
    └── GameManager.add_score(winner)
            │
            ├── score_changed(p,a) ──► GameHUD._on_score_changed()  ← ✅
            ├── game_won(winner)  ──► ⚠️ 可选：后期 UI 增强（如"Player Wins Game 1!"公告）
            └── match_over(winner) ──► GameStateMachine._on_match_over()  ← ✅
                                    ──► GameOverScreen._on_match_over()   ← ✅
```

### 文档更新清单

- [x] `mini-pong/project.godot` — `run/main_scene` 更新
- [x] `mini-pong/tests/test_ball.gd` — `game.tscn` → `Main.tscn`
- [x] `mini-pong/tests/test_ui_system.gd` — `game.tscn` → `Main.tscn`
- [x] `mini-pong/gdscripts/game_state_machine.gd` — 注释更新
- [ ] `docs/GAME_DESIGN/` — 批注重命名（可选，非阻塞）

---

## 4. 方案比较

### 方案 A：增量修复（推荐）

**描述：** 在现有 `game.tscn` 基础上增量添加缺失节点（WorldEnvironment、ScoreZones、ScoreFlash），重命名为 `Main.tscn`，创建 `constants.gd` 文件并逐步迁移引用，保持现有信号架构不变。

| 维度 | 评估 |
|------|------|
| **场景变更量** | 小 — 仅添加 4 个节点（WorldEnvironment + 2×ScoreZone + ScoreFlash），修改 ext_resource 引用 |
| **代码变更量** | 中 — 创建 constants.gd（~60 行），修改 4 个脚本移除重复常量并引用 GameConstants，更新 2–3 个测试文件中的路径 |
| **风险** | 低 — 所有现有测试和信号连接保持不变 |
| **测试影响** | 小 — 边界从 `_process` 硬编码改为 Area2D zone 后，测试需适配新得分触发方式 |
| **工程量** | 3–5 小时 |

**具体步骤：**

1. 复制 `game.tscn` → `Main.tscn`，添加：
   - `WorldEnvironment` (instance of `world_environment.tscn`)
   - `ScoreZoneLeft` (Area2D, CollisionShape2D 20×720, pos x=0, y=360)
   - `ScoreZoneRight` (Area2D, CollisionShape2D 20×720, pos x=1280, y=360)
   - `ScoreFlash` (Node, `score_flash.gd`, child ColorRect 1280×720)
2. 创建 `gdscripts/constants.gd`（`class_name GameConstants`），提取所有常量
3. 修改 `ball.gd`、`paddle.gd`、`scoring_manager.gd`、`game_manager.gd` 引用 `GameConstants`
4. 更新 `project.godot` 的 `run/main_scene`
5. 更新测试文件中的硬编码路径
6. 删除 `game.tscn`

**优点：**
- 最小变更面 — 不重写任何现有逻辑
- 保留所有已验证的信号连接
- 测试基础设施受影响最小

**缺点：**
- ScoreZones 需要在 ball.gd 中添加 Area2D 碰撞检测逻辑作为备选（或替代 `_process` X 检测）
- 常量迁移需要触碰多个文件

### 方案 B：从零重建 Main.tscn

**描述：** 全新创建 `Main.tscn`，用干净的 ext_resource 引用重新实例化所有组件，删除 `game.tscn`。

| 维度 | 评估 |
|------|------|
| **场景变更量** | 大 — 全新 TSCN 文件，所有 NodePath 重新配置 |
| **风险** | 中高 — GameStateMachine 的 7 个 NodePath exports 需精确复制，任一错误导致 FSM 静默失败 |
| **工程量** | 6–8 小时 |

**优点：**
- 干净的节点树 — 无历史遗留的 ext_resource ID 映射问题
- 强制审查每个 NodePath 和信号连接

**缺点：**
- 重新创建所有 UI 节点树（StartMenu/CenterContainer/VBoxContainer/TitleLabel/PromptLabel 等 ~30 行手动结构 + GameHUD/MarginContainer/HBoxContainer ~30 行 + GameOverScreen ~25 行）容易出错
- GameStateMachine NodePath 需要逐一手动配置
- 回归风险高 — 可能遗漏隐式依赖（如 ball.gd 通过 parent.has_node("Ball") 找球）

### 方案 C：保持 game.tscn，仅打补丁

**描述：** 不重命名，保持 `game.tscn` 文件名，仅添加缺失节点和 constants.gd。

| 维度 | 评估 |
|------|------|
| **风险** | 最低 — 零重命名风险 |
| **工程量** | 2–3 小时 |

**优点：**
- 零路径更新 — project.godot、测试、DESIGN 文档全部无需修改
- 最快交付

**缺点：**
- 不满足 Issue 要求 `Main.tscn`
- 与项目命名惯例不一致

### 推荐：方案 A

**理由：**

1. **最小风险，最大覆盖：** 方案 A 在现有已验证的 scene tree 上增量添加，GameStateMachine 的 NodePath exports 保持不变，信号连接不受影响。
2. **ScoreZones 迁移策略（渐进式）：** 为避免破坏 ball.gd 的现有测试，先在 `_process` 中保留 X 边界检测作为 fallback，同步添加 ScoreZone Area2D 碰撞检测。如果 ScoreZone 的 `body_entered` 触发 → emit score signal；否则 `_process` X 检测兜底。这允许测试逐步迁移而不会回归。
3. **常量迁移策略（非破坏性）：** `constants.gd` 使用 `class_name GameConstants`，初始阶段在 ball.gd/paddle.gd 中保留本地 `const` 并赋值为 `GameConstants.BALL_INITIAL_SPEED`。后续 PR 可以完全移除本地定义。
4. **方案 B 过度：** 从零重建使 GameStateMachine 的 7 个 `@onready var` NodePath 全部面临错误风险，而当前这些已在 CI 中通过测试验证。没有必要为了"干净"而重新创建已验证的节点树。
5. **方案 C 不符合要求：** Issue 明确要求 `Main.tscn`。

---

## 5. 边界条件与验收标准

### 正常路径

- [ ] **AC1: Main.tscn 场景树正确**
  - WorldEnvironment 节点存在且引用 `world_environment.tscn`
  - ScoreZoneLeft 节点存在（Area2D, 位置 x=0, 尺寸 20×720）
  - ScoreZoneRight 节点存在（Area2D, 位置 x=1280, 尺寸 20×720）
  - ScoreFlash 节点存在（Node + ColorRect 子节点）
  - 其余 9 类节点与当前 game.tscn 一致
  - `project.godot` 中 `run/main_scene="res://scenes/Main.tscn"`

- [ ] **AC2: 所有信号连接完整**
  - Ball.score → ScoringManager（保持不变）
  - ScoringManager.scored → GameStateMachine._on_scored（保持不变）
  - ScoringManager.scored → ScoreFlash._on_score_changed（节点存在后实际生效）
  - GameManager.score_changed → GameHUD._on_score_changed（保持不变）
  - GameManager.match_over → GameStateMachine._on_match_over（保持不变）
  - GameManager.match_over → GameOverScreen._on_match_over（保持不变）
  - 审核 GameManager.game_won — 无消费者是预期行为

- [ ] **AC3: 全局常量统一配置**
  - `gdscripts/constants.gd` 文件存在，使用 `class_name GameConstants`
  - 至少包含以下常量组：
    - 屏幕尺寸：`SCREEN_WIDTH=1280`, `SCREEN_HEIGHT=720`
    - 球物理：`BALL_INITIAL_SPEED=300`, `BALL_MAX_SPEED_MULTIPLIER=2.0`, `BALL_SPEED_INCREMENT=1.05`, `BALL_MAX_BOUNCE_ANGLE=60`, `BALL_SERVE_ANGLE_RANGE=45`, `BALL_RADIUS=10`
    - 挡板：`PADDLE_SPEED=400`, `PADDLE_WIDTH=20`, `PADDLE_HEIGHT=120`
    - AI：`AI_REACTION_DELAY_MIN=0.1`, `AI_REACTION_DELAY_MAX=0.3`, `AI_POSITION_ERROR=20`, `AI_SPEED_BOOST=1.2`, `AI_SPEED_SLOW=0.8`
    - 计分：`POINTS_TO_WIN_GAME=5`, `GAMES_TO_WIN_MATCH=2`
    - 颜色：`PLAYER_NEON_BLUE`, `AI_NEON_RED`, `BG_COLOR` 等
  - `scoring_manager.gd` 和 `game_manager.gd` 中的 `POINTS_TO_WIN_GAME`/`GAMES_TO_WIN_MATCH` 引用 `GameConstants`（消除重复）

- [ ] **AC4: 菜单→对打→得分→局胜→结束→重开链路正常**
  - 启动 → Main.tscn 加载 → WorldEnvironment background 可见 → StartMenu 显示
  - SPACE → SERVING → 1s → ball.serve() → PLAYING → paddles 可移动
  - 球出界 → ScoreFlash 闪烁 → HUD 分数更新 → 1s → serve → PLAYING
  - 5 分 → game_won → 分数归零 → 继续下一局
  - 2 局 → match_over → GameOverScreen 显示胜者
  - SPACE → MENU → 分数重置

- [ ] **AC5: 编译验证无错误**
  - `godot --path mini-pong/ --headless --quit` 退出码 0
  - `godot --path mini-pong/ --headless --script tests/check_compile.gd` 所有脚本通过
  - `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全部测试通过（或适配后通过）

### 边界情况

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | Main.tscn 加载时 WorldEnvironment 引用文件丢失 | Godot 打印 `Missing resource: res://scenes/world_environment.tscn` 警告，场景仍加载，无 crash |
| 2 | ScoreFlash ColorRect 节点缺失 | scoring_manager.gd:46 `score_flash.has_method("_on_score_changed")` → false → 跳过，得分仍正常工作 |
| 3 | ScoreZone body_entered 和 ball._process X 检测同时触发 | ball.gd 使用 `_scored_this_frame` 标志防止同一帧重复 emit score signal |
| 4 | GameConstants 尚未被所有脚本引用（渐进迁移） | 各脚本保留本地 const fallback。旧的 `const POINTS_TO_WIN_GAME = 5` 仍有效 |
| 5 | Main.tscn 在被其他 .tscn 引用前删除 game.tscn | `git mv` 方式重命名，或先创建 Main.tscn 再删除 game.tscn（两阶段提交） |
| 6 | 测试文件在常量迁移后检测到值变化 | 所有常量值不变 — 只移动定义位置。测试结果应完全一致 |
| 7 | 两个 paddle 使用同一 `player_paddle.tscn`，AIPaddle 的 mode=1 不被 SceneTree 识别 | paddle.gd `_ready()` 读取 `mode` 枚举 — AI paddle 的 `mode = Mode.AI = 1` 在 TSCN 中通过 `mode = 1` 设置，已验证可正常工作 |
| 8 | CanvasLayer 节点内联在 Main.tscn 中（非 ext_resource 实例） | 与 #292 设计一致 — DESIGN doc 指定内联节点树。不需要改为 ext_resource 引用 |

### 失败路径

| # | 场景 | 处理 |
|---|------|------|
| 1 | `project.godot` 中 `run/main_scene` 指向不存在的 `Main.tscn` | 编译验证会捕获 — `--headless --quit` 报错 `Can't run project: No main scene defined` |
| 2 | GameStateMachine NodePath exports 在重命名后指向空节点 | `_validate_references()` 在 `_ready()` 中检查并 `push_warning` — FSM 不 crash |
| 3 | 测试引用 `game.tscn` 但文件已删除 | 测试运行阶段在 CI 中捕获 — 测试会 FAIL 并打印路径错误 |

---

## 6. 依赖与阻塞项

### 依赖关系

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #287 Ball Physics | ✅ CLOSED | 低 | ball.gd 和 ball.tscn 已完成，SceneTree 中有节点实例 |
| #288 Player Paddle | ✅ CLOSED | 低 | player_paddle.tscn 已完成，AIPaddle 复用同一场景 |
| #290 AI Opponent | ✅ CLOSED | 低 | paddle.gd 的 AI mode (Mode.AI=1) 已完成 |
| #291 Scoring System | ✅ CLOSED | 低 | scoring_manager.gd 已完成，信号已连接 |
| #289 Neon Visual | ✅ CLOSED | 低 | world_environment.tscn、score_flash.gd、neon_glow.gdshader、ball_trail.gd 已创建 |
| #292 UI System | ✅ CLOSED | 低 | CanvasLayer 节点树已内联在 game.tscn 中 |
| #294 Game State Machine | ✅ CLOSED | 低 | game_state_machine.gd 已完成，NodePath exports 已配置 |
| #293 GameManager | ✅ CLOSED | 低 | autoload 已注册，64 行 game_manager.gd |

**依赖链（全部已满足）：**

```
#287 ──→ #291 (Scoring) ──→ #293 (GameManager)
  │                            │
  ├──→ #290 (AI)              ├──→ #292 (UI)
  │                            │     │
  └──→ #288 (Player)          │     └──→ #294 (FSM) ──→ #295 (Assembly)
       │                      │
       └──→ #289 (Visual) ────┘
```

### 阻塞项

| 未来工作 | 优先级 | 说明 |
|---------|:------:|------|
| #296+ (后续 features) | P2 | 本 Issue 是 MVP 最后一个 Integration Issue — 完成后游戏可运行 |
| 球拍颜色改为霓虹 ShaderMaterial | P2 | #289 的 ShaderMaterial 在 component 级别应用 — 不阻塞主场景组装 |
| game_won 信号的 UI 消费者（局间公告） | P3 | game_won 信号目前无人监听 — 可接受的 MVP 行为 |
| 音频系统 | P4 | 超出 MVP 范围 |

### 准备工作

- [x] 审计 game.tscn 当前节点树 — 完成（§1 Current State 表）
- [x] 审计所有信号连接状态 — 完成（§3 信号流图）
- [x] 确认所有依赖已 CLOSED — 完成（§6 依赖表全部 CLOSED）
- [ ] 创建 `docs/PRD/` 目录 — n/a（已存在）

---

## 7. Spike / 实验

**Skipped per depth/standard label.** 本 Issue 为纯组装任务，所有组件已在 #287–#294 的实现和测试中独立验证。无需额外 spike 实验。

---

## 8. 延续上下文

### 系统状态

本 PRD 完成时，Mini Pong MVP 的所有 9 个 Issue（#287–#295）全部交付。Main.tscn 是将所有组件组装为可运行游戏的最后一步。

### 关键文件清单（实施 agent 需要操作的文件）

| 优先级 | 文件 | 操作 |
|:------:|------|------|
| P0 | `mini-pong/scenes/game.tscn` → `Main.tscn` | **RENAME + MODIFY** — 添加 WorldEnvironment、ScoreZones×2、ScoreFlash 节点 |
| P0 | `mini-pong/gdscripts/constants.gd` | **CREATE** — 集中定义全局常量 |
| P0 | `mini-pong/project.godot` | **MODIFY** — `run/main_scene` 更新 |
| P1 | `mini-pong/gdscripts/scoring_manager.gd` | **MODIFY** — `POINTS_TO_WIN_GAME`/`GAMES_TO_WIN_MATCH` → `GameConstants.*` |
| P1 | `mini-pong/gdscripts/game_manager.gd` | **MODIFY** — 同上 |
| P1 | `mini-pong/gdscripts/ball.gd` | **MODIFY** — 球物理常量 → `GameConstants.*`；可选：添加 ScoreZone 碰撞检测 |
| P1 | `mini-pong/gdscripts/paddle.gd` | **MODIFY** — 挡板/AI 常量 → `GameConstants.*` |
| P2 | `mini-pong/tests/test_ball.gd` | **MODIFY** — `game.tscn` → `Main.tscn` |
| P2 | `mini-pong/tests/test_ui_system.gd` | **MODIFY** — `game.tscn` → `Main.tscn` |
| P3 | `mini-pong/gdscripts/game_state_machine.gd` | **MODIFY** — 注释中 `game.tscn` → `Main.tscn` |
| P3 | `mini-pong/scenes/game.tscn` | **DELETE** — 被 Main.tscn 取代 |

### 实施顺序（推荐）

```
Phase 1: 常量提取（纯增量，零破坏性）
  1. CREATE constants.gd (class_name GameConstants)
  2. MODIFY ball.gd → 本地 const 引用 GameConstants.*
  3. MODIFY paddle.gd → 本地 const 引用 GameConstants.*
  4. MODIFY scoring_manager.gd → POINTS_TO_WIN_GAME = GameConstants.*
  5. MODIFY game_manager.gd → 同上
  6. 运行测试验证 — 所有值不变，测试应全通过

Phase 2: 场景组装（增量添加节点）
  1. COPY game.tscn → Main.tscn
  2. ADD WorldEnvironment instance (ext_resource world_environment.tscn)
  3. ADD ScoreZoneLeft (Area2D + CollisionShape2D, pos 0,360)
  4. ADD ScoreZoneRight (Area2D + CollisionShape2D, pos 1280,360)
  5. ADD ScoreFlash (Node + ColorRect, score_flash.gd)
  6. 在 Godot Editor 中验证场景树无警告

Phase 3: 路径更新（全局替换）
  1. MODIFY project.godot → run/main_scene="res://scenes/Main.tscn"
  2. MODIFY tests/test_ball.gd → "game.tscn" → "Main.tscn"
  3. MODIFY tests/test_ui_system.gd → "game.tscn" → "Main.tscn"
  4. MODIFY game_state_machine.gd → 注释更新
  5. DELETE scenes/game.tscn

Phase 4: 编译 & 测试验证
  1. godot --path mini-pong/ --headless --quit           → exit 0
  2. godot --path mini-pong/ --headless --script tests/check_compile.gd → exit 0
  3. godot --path mini-pong/ --headless --script tests/run_tests.gd    → exit 0
```

### 主要风险

1. **ScoreZone 回归风险：** ball.gd 的 `_process` X 边界检测是得分的主要路径。添加 ScoreZone 可能导致同一帧双触发。缓解：在 ball.gd 中添加 `_scored_this_frame` 单次触发保护。
2. **测试路径更新遗漏：** 至少 2 个测试文件硬编码了 `game.tscn` 路径。缓解：批量 grep `game.tscn` 在 mini-pong/ 目录下，确保无遗漏。
3. **常量迁移后测试失败：** 如果 `GameConstants` 引用在 headless 模式下不可用（class_name 需要脚本加载顺序）。缓解：Phase 1 完成后立即运行测试，如果 class_name 不可用在 headless 模式，改为 `const` 脚本（非 class_name）+ `preload()` 加载。

### 后续 Issue（MVP 后）

本 Issue 是 MVP 的最后一个。完成后 Mini Pong 应为一个功能完整的可玩游戏。可能的后续增强（非 MVP 范围）：
- 球拍 ShaderMaterial 霓虹发光效果
- 音效系统
- 难度选择（调 AI 参数）
- 双人对战模式

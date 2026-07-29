# PRD: [Feature] 游戏状态管理 — Game State Machine

> **Issue:** #294
> **标签:** enhancement, workflow/research, depth/standard, priority/high, version/mvp, estimate/small
> **Agent:** game-research-agent
> **日期:** 2026-07-30
> **前置依赖:** #301 (Scaffold — CLOSED ✅), #287 (Ball Physics — CLOSED ✅), #292 (UI System — CLOSED ✅)

---

## 1. 问题定义

### 当前状态

Mini Pong 的游戏逻辑模块已全部完成（球物理 #287、玩家/AI 球拍 #288/#290、计分 #291、GameManager 全局状态 #293、UI 系统 #292），但**缺乏一个中心化的状态机来编排运行时流程**。当前系统通过各脚本内部的 ad-hoc 逻辑协作运行，存在以下问题：

| 组件 | 文件 | 当前行为 | 问题 |
|------|------|---------|------|
| 开始→游戏 | `start_menu.gd:87` | `_on_start_pressed()` 直接 `visible=false` → 显示 HUD → `GameManager.reset_match()` | 无 `serving` 阶段——跳过 1 秒发球延迟，直接进入 gameplay |
| 得分→发球 | `scoring_manager.gd:107-113` | `_pause_and_serve()` 内联 1 秒 `await` → `ball.serve()` | 此逻辑嵌在 scoring manager 中——无法从状态机层面控制或替换 |
| 比赛结束→菜单 | `game_over_screen.gd:96-107` | `_on_restart_pressed()` 直接 `visible=false` → `menu.show_menu()` → `GameManager.reset_match()` | 直接从 game_over 回 menu——无 `scored` 状态隔离 |
| 球冻结 | 无 | 无 | 球在得分后通过 `_is_serving` 标志冻结——但 paddle 仍可移动，游戏无整体"冻结"概念 |
| 输入控制 | 分散 | Paddle 在 `_process` 中读取输入；StartMenu/GameOverScreen 在 `_input` 中处理 SPACE | 无统一的输入门控——菜单阶段 paddle 理论上也可移动 |
| 状态转换 | 分散在 3 个脚本 | 每个脚本独立管理自己的 `visible` 和 `_transitioning` 标志 | 状态不一致风险——菜单认为自己已隐藏但 HUD 未显示 |

**当前 ad-hoc 状态流（无中心编排）：**

```
menu                  playing/scored           game_over
  │                       │                       │
  │ start_menu.gd        │ scoring_manager.gd    │ game_over_screen.gd
  │ _on_start_pressed()  │ _pause_and_serve()    │ _on_restart_pressed()
  │ → hide self          │ → await 1.0s          │ → hide self
  │ → show HUD           │ → ball.serve()        │ → menu.show_menu()
  │ → reset_match()      │                       │ → reset_match()
  └───────────────────────┴───────────────────────┘
        各自独立，无共享状态机概念
```

**现有代码提供了构建所需的一切基础组件，但缺少协调层：**

- ✅ `GameManager` autoload — 全局分数状态、`reset_match()`、`get_winner()` API、`score_changed`/`game_won`/`match_over` 信号
- ✅ `ScoringManager` — `scored(winner)` 每分、`game_won(winner)` 每局、`match_over(winner)` 每场信号
- ✅ `Ball.serve()` — 发球方法
- ✅ `StartMenu` / `GameHUD` / `GameOverScreen` — 三层 CanvasLayer UI，各有 `visible` 属性和动画方法
- ✅ `Paddle._process()` — 玩家/AI 移动逻辑
- ❌ **缺少：** 中心状态机来编排菜单→发球→比赛→得分→结束的状态迁移、输入门控、物体冻结

### 预期行为

实现中心化的游戏状态机，将分散的 ad-hoc 状态逻辑整合为清晰的有限状态机（FSM）：

1. **5 状态枚举：** `menu` → `serving` → `playing` → `scored` → `game_over` → 循环回 `menu`
2. **每个状态控制以下子系统：**
   - **UI 可见性：** 哪个 CanvasLayer 可见（menu → StartMenu，playing/scored/serving → GameHUD，game_over → GameOverScreen）
   - **输入开关：** 哪些按键生效（menu/game_over → 仅 SPACE；playing → WASD/方向键；serving/scored → 无输入）
   - **物体冻结：** 球/paddle 的位置更新是否运行（playing → 全部运行；其他状态 → 球/paddle 冻结）
3. **状态迁移触发条件：**
   - `menu → serving`：SPACE 按下（从 StartMenu）
   - `serving → playing`：1 秒延迟后自动（`await` timer）
   - `playing → scored`：`ScoringManager.scored(winner)` 信号
   - `scored → serving`：1 秒冻结后自动（若比赛未结束）
   - `scored → game_over`：`ScoringManager.match_over(winner)` 信号
   - `game_over → menu`：SPACE 按下（从 GameOverScreen）
4. **编译验证：** `godot --path mini-pong/ --headless --quit` 无脚本错误

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | **启动 → 开始游戏：** 启动后停在菜单。按 SPACE → 进入 1 秒发球倒计时 → 球自动发出 | 每次启动 |
| B | **得分 → 下一回合：** 球出界 → 游戏冻结 1 秒（HUD 分数更新、flash 闪烁）→ 自动发球进入下一回合 | 每回合结束 |
| C | **比赛结束：** 一方赢 2 局 → scored 状态检测到 match_over → 进入 game_over 屏幕 | 每场比赛 1 次 |
| D | **重新开始：** game_over 画面按 SPACE → 回到 menu → 再按 SPACE 开始新比赛 | 每次重新开始 |
| E | **快速 SPACE 连按：** 菜单或结束画面连按 SPACE 不会触发重复状态迁移——仅第一次有效 | 罕见 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 状态枚举和状态迁移逻辑（`game_state_machine.gd`） | 计分逻辑修改（#291 已完成） |
| 根据状态控制 UI 可见性（StartMenu/GameHUD/GameOverScreen.visible） | 新的 UI 元素或动画（#292 已完成） |
| 根据状态控制输入（冻结 paddle 移动） | 输入映射修改（#288 已完成） |
| 根据状态控制球物理（冻结 ball._process） | 球物理修改（#287 已完成） |
| served→playing / scored→serving 的 1 秒计时器 | 复杂的计时器系统 |
| `--headless --quit` 编译验证 | 完整的测试套件 |

---

## 2. 设计意图

### 为什么是现在

Mini Pong 已拥有所有功能模块（球物理、球拍、计分、UI），但缺少一个"大脑"来编排这些模块的运行时行为。当前 ad-hoc 状态管理存在以下具体问题：

1. **`serving` 状态缺失：** `start_menu.gd` 的 `_on_start_pressed()` 跳过了发球的 1 秒预备阶段。用户体验是：按 SPACE → 球立即开始移动，无任何准备时间——不符合经典 Pong 的"预备发球"节奏。

2. **`scored` 冻结缺失：** 得分后球通过 `_is_serving` 标志停在中心，但以下行为不受控制：
   - Paddle 仍在 `_process` 中移动（player/AI）
   - HUD 分数更新在 scored 信号后立即发生——无"冻结→更新→再发球"的节奏
   - `scoring_manager.gd` 的 `_pause_and_serve()` 混合了计分逻辑与状态控制

3. **状态分散在 3 个脚本中：**
   - `start_menu.gd` 管理 menu→game 转换
   - `scoring_manager.gd` 管理 scored→serve 转换
   - `game_over_screen.gd` 管理 game_over→menu 转换
   
   任何状态的修改需要改动多个文件，容易出现一致性问题。

4. **依赖链就绪：** #292（UI 系统）提供了三层 CanvasLayer 的 `visible` 属性——状态机只需读写这些属性即可控制 UI。#291（计分）的信号链（`scored` → `game_won` → `match_over`）提供了状态迁移的触发条件。#293（GameManager）提供了全局分数状态。

5. **状态机必须在主场景组装（#295）之前完成：** #295 需要知道各节点在什么状态下可见/可交互。

### 为什么选择此方案

选择**场景级 FSM（Node 脚本）**而非 autoload 或内联逻辑：

| 理由 | 说明 |
|------|------|
| **与现有模块自然集成** | FSM 是 `game.tscn` 中的一个 Node，通过信号和节点引用连接 Ball、Paddle、UI 层、ScoringManager |
| **状态迁移显式化** | 当前 ad-hoc 转换隐藏在各自脚本的 `_on_*_pressed()` 和 `_pause_and_serve()` 中。FSM 将其提升为显式的 `transition_to(STATE_X)` 调用 |
| **输入/物理冻结统一** | `_process` 中检查当前状态决定是否处理移动——一处修改，全局生效 |
| **可测试性** | FSM 是独立脚本，可 headless 测试状态迁移、计时器、信号响应——不需要完整 game.tscn 场景 |

### 设计原则

1. **信号驱动状态迁移：** FSM 监听 `ScoringManager.scored` / `match_over` 信号触发状态变化，不轮询、不依赖 `_process`
2. **状态枚举 + Transition 表：** 每个状态有明确的 `enter()` / `exit()` / `process()` 行为，状态迁移通过 `transition_to(state)` 统一入口
3. **节点引用而非树遍历：** FSM 通过 `@onready var` 持有 Ball、Paddle、UI 层的引用——在 `game.tscn` 中设置为节点的 `node_path`，不依赖运行时 `get_node("../Foo")`
4. **UI 层由 FSM 控制而非自控：** StartMenu 和 GameOverScreen 的 SPACE 处理逻辑从各脚本中移除，由 FSM 统一在 `_input` 中根据状态处理
5. **1 秒计时使用 `await` + `SceneTreeTimer`：** 与 `scoring_manager.gd` 的 `_pause_and_serve()` 相同模式——已验证可靠

### 先前约束

| 约束 | 来源 | 细节 |
|------|------|------|
| StartMenu.visible 控制菜单显示 | #292 PRD §1 | 状态机读写 `start_menu.visible` |
| GameHUD.visible 控制 HUD 显示 | #292 PRD §1 | 状态机读写 `game_hud.visible` |
| GameOverScreen.visible 控制结束显示 | #292 PRD §1 | 状态机读写 `game_over_screen.visible` |
| ScoringManager.scored(winner) 信号 | #291 PRD §3 | 状态机监听此信号触发 playing→scored |
| ScoringManager.match_over(winner) 信号 | #291 PRD §3 | 状态机监听此信号触发 scored→game_over |
| Ball.serve() 方法 | #287 PRD §4 | 状态机在 serving→playing 时调用 |
| Ball._is_serving 状态 | #287 实现 | 状态机读取以判断 ball 是否就绪 |
| Paddle._process(delta) 移动 | #288 实现 | 状态机通过 bool flag 控制是否执行移动 |
| GameManager.reset_match() | #293 PRD §2 | 状态机在 menu→serving 时调用 |

---

## 3. 影响分析

### 直接影响 — 新增文件

| 文件 | 类型 | 用途 |
|------|------|------|
| `mini-pong/gdscripts/game_state_machine.gd` | GDScript | 中心 FSM：5 状态枚举、transition_to()、_input 处理、UI/物理冻结控制、计时器管理 |

### 直接影响 — 修改文件

| 文件 | 修改性质 | 变更内容 |
|------|---------|---------|
| `mini-pong/scenes/game.tscn` | 修改 | 添加 `GameStateMachine` Node，设置 node refs（ball/paddles/ui layers/scoring manager）；可能需要移除 StartMenu/GameOverScreen 内联的 SPACE 处理逻辑（或保留为兜底） |
| `mini-pong/gdscripts/start_menu.gd` | 轻微修改 | 可选：移除 `_input` 中的 SPACE 处理（如状态机接管）；保留 `show_menu()`/`hide_menu()` 公共 API；保留动画方法 |
| `mini-pong/gdscripts/game_over_screen.gd` | 轻微修改 | 可选：移除 `_input` 中的 SPACE 处理；保留 `_on_match_over()` 信号连接（用于设置文字/颜色）；保留动画方法 |
| `mini-pong/gdscripts/paddle.gd` | 轻微修改 | 添加 `frozen` bool（默认为 false）——`_process` 开头检查：若 `frozen`，`return`。由状态机通过节点引用设置 |
| `mini-pong/gdscripts/scoring_manager.gd` | 修改 | 移除 `_pause_and_serve()` 中的 1 秒 await + `ball.serve()`——改为仅发射信号，由状态机处理延迟和发球。保留分数递增和 `_win_game()` 逻辑 |

### 间接影响

| 文件 | 影响性质 |
|------|---------|
| `mini-pong/gdscripts/ball.gd` | **无修改** — `serve()` 和 `_is_serving` 作为 API 由状态机调用/读取。不需要新增 frozen flag（球已有 `_is_serving`） |
| `mini-pong/gdscripts/game_hud.gd` | **无修改** — 仅通过 visible 由状态机控制；信号连接保持不变 |
| `mini-pong/gdscripts/ball_trail.gd` | **间接** — 球冻结时拖尾自然停止（GPUParticles2D 依赖球位置） |
| `mini-pong/project.godot` | **可能需要** — 若 `input_map` 中缺少 `ui_accept` 绑定，状态机需要在 `_ready` 中注册（SPACE 键） |

### 数据流影响

```
         SPACE 按键
             │
             ▼
    ┌──────────────────────────────────┐
    │     GameStateMachine (Node)      │
    │                                  │
    │  current_state: State enum       │
    │  transition_to(next: State)      │
    │  _input(event) → state 路由      │
    └────┬──────┬──────┬──────┬────────┘
         │      │      │      │
    ┌────▼─┐ ┌─▼──┐ ┌─▼──┐ ┌▼──────┐
    │ UI   │ │Ball│ │Pdl │ │Scoring│
    │Layers│ │    │ │    │ │Manager│
    └──────┘ └────┘ └────┘ └──┬────┘
                              │
                    scored(winner) ──► playing → scored
                    match_over(winner) ──► scored → game_over

状态迁移流程：

menu ──[SPACE]──► serving ──[1s]──► playing ──[scored signal]──► scored
  ▲                                                               │
  │                                          ┌──[1s]──► serving ─┘
  │                                          │
  │                              [match_over signal]
  │                                          │
  └──────────[SPACE]──────── game_over ◄─────┘
```

### 需更新的文档

- [ ] `docs/DESIGN/294-game-state-machine.md` — 待 plan 阶段产出
- [ ] `docs/GAME_DESIGN/INDEX.md` — 如存在，补充状态机章节

---

## 4. 方案对比

### 方案 A：场景级 FSM Node + enum 状态枚举（推荐）

**描述：** 在 `game.tscn` 中添加一个 `GameStateMachine`（`extends Node`）节点。定义 `enum State { MENU, SERVING, PLAYING, SCORED, GAME_OVER }`，通过 `transition_to(state)` 统一入口管理状态迁移。在 `enter_state(s)` / `exit_state(s)` 中控制 UI 可见性、输入和物理冻结。使用 `@onready var` 持有 ball/paddles/ui/scoring_manager 引用。

**核心代码模式：**

```gdscript
enum State { MENU, SERVING, PLAYING, SCORED, GAME_OVER }
var current_state: State = State.MENU

func transition_to(next: State) -> void:
    exit_state(current_state)
    current_state = next
    enter_state(next)

func enter_state(state: State) -> void:
    match state:
        State.MENU:
            show_ui_layer("start_menu")
            freeze_all(true, false)  # freeze ball + paddles, allow SPACE
        State.SERVING:
            show_ui_layer("hud")
            freeze_all(true, false)  # freeze everything during countdown
            await serve_timer(1.0)
            ball.serve()
            transition_to(State.PLAYING)
        State.PLAYING:
            show_ui_layer("hud")
            freeze_all(false, true)  # unfreeze ball + paddles, full input
        State.SCORED:
            freeze_all(true, false)  # freeze during score display
            # Wait for signals to decide next state
        State.GAME_OVER:
            show_ui_layer("game_over")
            freeze_all(true, true)  # freeze ball/paddles, allow SPACE only
```

**Pros:**
- 状态迁移集中化——所有转换路径在一处可见，调试时只需看一个文件
- 与 Godot 4.x 的节点场景模式一致——无需 autoload 或全局注册
- 可复用现有节点引用——通过 `@onready var` 获取 ball/paddles/ui，无需修改这些脚本的结构
- 接口最小化——paddle 只需新增一个 `frozen` bool 属性；ball 无需改动（已有 `_is_serving`）
- 1 秒计时使用 `await`，与现有 `scoring_manager.gd` 模式一致——已验证可行
- 可独立 headless 测试

**Cons:**
- 需要修改 `scoring_manager.gd` 移除 `_pause_and_serve()` 中的 serve 调用——可能引入回归
- `start_menu.gd` 和 `game_over_screen.gd` 的 `_input` 处理需要移除或降级（可能与 FSM 的 `_input` 冲突）
- FSM 需要与 game.tscn 场景结构紧耦合（通过 node_path 引用特定节点）

**Risk:** Low — FSM 模式在游戏开发中成熟可靠。主要风险在 `scoring_manager.gd` 的改动中引入回归。

**Effort:** 3-4 小时 — 核心 FSM 脚本 ~150 行，paddle 修改 2 行，scoring_manager 修改 ~10 行，game.tscn 添加节点。

---

### 方案 B：Autoload StateMachine + Signal 驱动

**描述：** 将状态机注册为 autoload 单例（`StateMachine`），通过信号与各场景组件通信。各组件在 `_ready()` 中连接状态机的 `state_changed` 信号并自行处理 UI/冻结逻辑。

**Pros:**
- 全局可访问——任何脚本可读取 `StateMachine.current_state`
- 解耦——各组件自行决定如何响应状态变化，FSM 不持有节点引用
- 易于扩展——新组件只需连接 `state_changed` 信号

**Cons:**
- **过度设计：** Pong 只有一个主场景（`game.tscn`）——不需要全局状态机。`scene_change` 概念不适用
- **Signal 级联风险：** 状态变化 → 触发 `state_changed` 信号 → 多个组件同时响应——可能出现时序问题（如 UI 在 ball freeze 之前切换）
- **调试困难：** 状态迁移分散在多个文件中——追踪"为什么 playing→scored 时 UI 没切换"需要检查 3-4 个连接点
- **不符合蓝图：** `project.godot` 中每多一个 autoload 增加全局命名空间污染

**Risk:** Low-Med — 可工作但增加不必要的复杂度。

**Effort:** 3-4 小时 — 代码量相当但调试成本更高。

---

### 方案 C：内联状态逻辑到 GameManager

**描述：** 不在新增文件，而是扩展现有 `game_manager.gd` autoload，添加状态枚举和转换方法。`GameManager` 既是数据holder又是状态机。

**Pros:**
- 零新增文件——所有逻辑在 `game_manager.gd` 中
- `GameManager` 已全局可访问——方便各组件读取状态

**Cons:**
- **违反 GameManager 的设计意图：** #293 PRD 明确定义 GameManager 为 "pure-data holder"——添加状态机逻辑破坏此分离
- **GameManager 需要节点引用：** 要控制 UI/Ball/Paddle 的可见性和冻结状态，必须通过 `get_node()` 获取场景节点——但 autoload 不应依赖场景树
- **Headless 兼容性破坏：** GameManager 的测试通过直接实例化脚本运行（`Node.new().set_script(...)`）——添加节点引用后此模式失效
- **职责混合：** 数据 + 编排 + UI 控制 → 维护困难

**Risk:** Medium — 架构退化，破坏已有测试。

**Effort:** 2-3 小时 — 但会引入技术债务。

---

### 推荐：方案 A

| 理由 | 说明 |
|------|------|
| **职责分离** | FSM 专注编排——不持有分数数据（GameManager 负责），不处理碰撞（Ball 负责），不渲染 UI（CanvasLayer 负责） |
| **最小侵入** | 仅修改 paddle（+2 行 frozen flag）和 scoring_manager（-10 行移除 serve 调用）。Ball、GameHUD、BallTrail 完全不变 |
| **符合现有架构** | 项目已采用场景级 Node 模式（ScoringManager、ScoreFlash 均为 game.tscn 中的 Node 节点）——FSM 延续此模式 |
| **可测试性** | FSM 脚本可通过 `Node.new().set_script()` 独立实例化，mock 节点引用后测试状态迁移逻辑 |
| **与 #295 兼容** | #295 主场景组装只需确保 FSM 节点在 game.tscn 中正确配置 node_path——与现有 ScoringManager 的配置方式相同 |

---

## 5. 边界条件与验收标准

### 验收清单

- [ ] **AC1: 4 状态枚举存在且正确** — `menu`, `serving`, `playing`, `scored`, `game_over` 五个状态在 `game_state_machine.gd` 中定义为 `enum State`

- [ ] **AC2: menu 只响应 SPACE** — 
  - menu 状态下所有输入除 SPACE 外被忽略
  - Paddle 不响应 WASD/方向键（`frozen = true`）
  - Ball 不运动（已有 `_is_serving = true`）
  - 按 SPACE → 迁移到 serving 状态
  - UI：StartMenu.visible = true，GameHUD.visible = false，GameOverScreen.visible = false

- [ ] **AC3: serving 1s 后发球** —
  - 进入 serving → 调用 `GameManager.reset_match()` 重置全局分数
  - 1 秒 `await` timer 后调用 `ball.serve()`
  - 自动迁移到 playing 状态
  - serving 期间 paddle 冻结（`frozen = true`）
  - UI：StartMenu.visible = false，GameHUD.visible = true

- [ ] **AC4: playing 允许碰撞和移动** —
  - Ball 的 `_process` 正常运行（`_is_serving = false`，ball 在 `serve()` 后被 FSM 设置）
  - Paddle 的 `_process` 正常运行（`frozen = false`）
  - WASD/方向键控制玩家 paddle，AI paddle 跟踪 ball 位置
  - 碰撞检测正常——paddle→ball 反弹、wall→ball 反弹
  - UI：GameHUD.visible = true，StartMenu.visible = false，GameOverScreen.visible = false

- [ ] **AC5: scored 冻结 1s** —
  - 收到 `ScoringManager.scored(winner)` 信号 → 迁移到 scored
  - Paddle 冻结（`frozen = true`），Ball 不运动（已在 `serve()` 后 `_is_serving = true`）
  - 1 秒冻结后：
    - 若比赛未结束（`GameManager.get_winner() == ""`）→ 迁移到 serving
    - 若比赛结束（`match_over` 已发射或 `get_winner() != ""`）→ 迁移到 game_over
  - UI：GameHUD.visible = true（分数在此状态更新），ScoreFlash 闪烁正常

- [ ] **AC6: game_over 只响应 SPACE 回 menu** —
  - 进入 game_over → paddle 冻结、ball 冻结
  - 按 SPACE → 迁移到 menu 状态
  - UI：GameOverScreen.visible = true，GameHUD.visible = false，StartMenu.visible = false
  - game_over 画面胜者文字和动画正常（由 `game_over_screen.gd` 的 `_on_match_over` 处理）

- [ ] **AC7: --headless --quit 无脚本错误** —
  - `godot --path mini-pong/ --headless --quit` 退出码为 0
  - FSM 脚本编译通过
  - 状态迁移逻辑在 headless 模式下不崩溃（`get_tree()` 守卫）

### 边界条件

1. **快速状态迁移：** 在 scored 的 1 秒冻结期间，若 `match_over` 信号到达——应立即进入 game_over 而非等待 1 秒结束（需取消 scored timer）
2. **重复 SPACE：** menu 或 game_over 状态下快速连按 SPACE——FSM 应在首次 SPACE 后设置 `_transition_lock`，防止重复迁移
3. **信号在错误状态到达：** 若 `scored` 信号在 menu 或 game_over 状态到达（极不可能但防御性编程）——忽略，记录 warning
4. **Ball.serve() 未完成：** serving→playing 的 timer 到期后调用 `ball.serve()` 是异步的（0.5s serve delay）——FSM 应在 `ball.serve()` 完成后等待 0.5s 再真正迁移到 playing。或：FSM 不等待 serve delay 完成——直接设 playing 状态，ball 自行管理 serve 动画
5. **Paddle frozen 重置：** 从 game_over → menu 时需确保 paddle frozen 重置为 true（menu 状态下也应冻结）
6. **ScoringManager 已被修改：** `_pause_and_serve()` 移除后，scoring_manager 的 `_on_ball_score` 在调用链中不再有 serve——需确认 scored 后 ball 不自动重置位置（ball 自己通过 `_process` 的边界检测会触发 `serve()` 在 `scored` 信号之后——这是竞争条件，需要 FSM 在 scored 状态下阻止 ball 移动再调用 serve）
7. **headless 模式下 timer 失败：** `get_tree()` 可能为 null——在 `await` 前检查 `get_tree()` 非 null；headless 下跳过 timer 等待直接迁移

### 失败路径

1. **FSM 节点引用为空：** `game.tscn` 中未正确设置 node_path → `@onready var` 为 null → `enter_state()` 中 guard 检查后静默降级（打印 warning，不 crash）
2. **ScoreManager.scored 信号在 match_over 之后发射：** 此顺序不可能（`_is_match_over` guard 阻止），但若发生——FSM 在 game_over 状态下收到 scored 信号应忽略
3. **SPACE 键未绑定：** 若 `ui_accept` action 不在 input_map 中——FSM 在 `_ready()` 中注册（`InputMap.add_action("ui_accept")` + 绑定 KEY_SPACE）

---

## 6. 依赖与阻塞项

### 依赖项

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|------|------|
| #301 项目骨架 | ✅ CLOSED | None | `mini-pong/` 目录结构、project.godot 已就绪 |
| #287 球物理与碰撞 | ✅ CLOSED | None | `ball.gd` 的 `serve()` 方法和 `_is_serving` 状态可用 |
| #288 玩家球拍控制 | ✅ CLOSED | None | `paddle.gd` 的 `_process` 移动逻辑——需添加 `frozen` flag |
| #290 AI 对手 | ✅ CLOSED | None | AI paddle 共用 `paddle.gd`——frozen flag 同时控制 |
| #291 计分系统 | ✅ CLOSED | None | `ScoringManager` 的 `scored`/`match_over` 信号提供状态迁移触发源 |
| #292 UI 系统 | ✅ CLOSED | None | StartMenu/GameHUD/GameOverScreen 的 `visible` 属性提供状态机控制接口 |
| #293 GameManager 全局状态 | ✅ CLOSED | None | `reset_match()` 和 `get_winner()` API

### 被依赖项（此 PRD 阻塞）

| 未来工作 | 优先级 | 阻塞点 |
|----------|--------|--------|
| #295 主场景组装 | High | 组装脚本需要知道状态机的节点结构以正确配置 node_path |
| #296 音效系统 | Low | 不直接阻塞——音效可独立开发，但需要知道状态迁移事件以触发音效 |

### 依赖链

```
#301 Scaffold ✅
    │
    ├──► #287 球物理 ✅
    │       └──► #291 计分系统 ✅ → #293 GameManager ✅
    │
    ├──► #288 玩家球拍 ✅
    │       └──► #290 AI 对手 ✅
    │
    ├──► #292 UI 系统 ✅
    │       │
    │       ├─── StartMenu, GameHUD, GameOverScreen ✅
    │       │
    └───────┴──► #294 状态机 ◄── 本 Issue
                     │
                     └──► #295 主场景组装
```

### 准备清单

- [x] #301 Scaffold 完成
- [x] #287 Ball 完成（serve() + _is_serving）
- [x] #288 Paddle 完成（_process 移动）
- [x] #290 AI 完成（共用 paddle.gd）
- [x] #291 ScoringManager 完成（scored/match_over 信号）
- [x] #292 UI 完成（visible 控制）
- [x] #293 GameManager 完成（reset_match/get_winner）

---

## 7. Spike / 实验

**Skipped per depth/standard label.** （Section 7 仅在 depth/deep 时为必需。FSM 的 5 状态枚举 + await timer + signal-driven transition 模式在 Godot 4.x 中成熟稳定。所有涉及的技术点（enum matching、await、SceneTreeTimer、信号连接）已在现有代码中有先行验证——`scoring_manager.gd` 的 `_pause_and_serve()` 验证了 await timer 模式，`game_over_screen.gd` 验证了 signal-driven 状态切换。）

---

## 8. 续接上下文

### 系统状态

本 PRD 完成时，Mini Pong 将拥有完整的运行时编排层：

- `game_state_machine.gd`：5 状态 FSM，状态迁移表，输入门控，物理冻结控制
- `paddle.gd`：新增 `frozen` bool 属性——`_process` 入口检查
- `scoring_manager.gd`：移除 `_pause_and_serve()` 中的 serve 逻辑——仅保留计分
- `start_menu.gd` / `game_over_screen.gd`：SPACE 处理可选移除或降级（FSM 接管）
- `game.tscn`：新增 `GameStateMachine` Node，node_path 指向 ball/paddles/ui/scoring_manager

### 当前 ad-hoc 状态 → FSM 迁移映射

| 当前位置 | 当前行为 | FSM 接管后 |
|---------|---------|-----------|
| `start_menu.gd:87` `_on_start_pressed()` | hide menu → show HUD → reset_match | FSM 监听 SPACE → `transition_to(SERVING)` → 1s timer → `transition_to(PLAYING)` |
| `scoring_manager.gd:107` `_pause_and_serve()` | await 1s → ball.serve() | FSM 在进入 SCORED 时设置 1s timer → 然后 `transition_to(SERVING)` |
| `game_over_screen.gd:96` `_on_restart_pressed()` | hide game_over → menu.show_menu() → reset_match | FSM 监听 SPACE → `transition_to(MENU)` |

### 主要风险

| 风险 | 缓解措施 |
|------|---------|
| ScoringManager 修改后 scored 信号 + serve() 竞态 | FSM 在 SCORED 状态下忽略 scored 信号——仅接受 match_over 或 timer 到期 |
| StartMenu/GameOverScreen 的 `_input` 与 FSM 的 `_input` 同时响应 SPACE | 实现方式 A：FSM 在 Node 层级上优先调用 `set_process_input(false)` 禁用 UI 层的 `_input`。方式 B：状态机持有 input 优先级——各脚本检查 `if state_machine.current_state == MENU: return` |
| Ball.serve() 的 0.5s delay 与 FSM 的 1s timer 叠加 | FSM 在 SERVING 状态 wait 1s 后调用 `ball.serve()`，但 ball 内部有 0.5s serve delay——总计 1.5s。可接受（比当前无 delay 好）或调整 FSM timer 为 0.5s + ball 的 0.5s = 1s 总计 |

### 下一步（Plan Agent 续接）

1. **产出 DESIGN doc：** `docs/DESIGN/294-game-state-machine.md`，包含：
   - 完整状态迁移表（5×5 矩阵）
   - `enter_state()` / `exit_state()` 行为规格
   - `@onready var` 引用配置
   - `_input()` 路由逻辑
   - Paddle `frozen` flag 的修改规格
   - ScoringManager `_pause_and_serve()` 重构规格
2. **定义与 #295 的接口：** 状态机节点的 node_path 配置——#295 组装场景时需设置 ball、paddles、ui_layers、scoring_manager 的路径
3. **文件清单（Plan Agent 将编译）：**
   - `mini-pong/gdscripts/game_state_machine.gd`（新增，~150 行）
   - `mini-pong/gdscripts/paddle.gd`（修改，+2 行 frozen flag）
   - `mini-pong/gdscripts/scoring_manager.gd`（修改，-10 行 serve 逻辑）
   - `mini-pong/gdscripts/start_menu.gd`（可选修改，移除 SPACE 处理）
   - `mini-pong/gdscripts/game_over_screen.gd`（可选修改，移除 SPACE 处理）
   - `mini-pong/scenes/game.tscn`（修改，添加 GameStateMachine Node）
   - `mini-pong/tests/test_state_machine.gd`（新增，headless 状态迁移测试）

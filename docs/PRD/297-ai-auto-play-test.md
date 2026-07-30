# PRD: [Test] 100 回合自动对打 — AI Auto-Play Test

> **Issue:** #297
> **标签:** enhancement, workflow/research, depth/standard, priority/high, version/mvp, estimate/medium
> **Agent:** game-research-agent
> **日期:** 2026-07-30
> **前置依赖:** #295 (Main Scene Assembly — CLOSED, implement PR #339 merged)

---

## 1. 问题定义

### 当前状态

Mini Pong 的单元测试覆盖了各个独立组件（ball、paddle、scoring、FSM、UI），但缺少**端到端集成压力测试**。100 局 AI-vs-AI 自动对打是验证系统稳定性的最后防线，可暴露：

| 测试对象 | 当前覆盖 | 缺失 |
|----------|:------:|------|
| Ball 物理 | ✅ test_ball.gd（单元） | 长时间运行下的速度漂移 / NaN |
| AI Paddle | ✅ test_ai_paddle.gd（单元） | 100 局持续运行下的状态累积错误 |
| ScoringManager | ✅ test_scoring_manager.gd（单元） | 200+ 次得分信号后的内存/计数准确性 |
| GameStateMachine | ✅ test_game_state_machine.gd（单元） | MENU→GAME_OVER→MENU 循环 100 次的转换正确性 |
| GameManager (autoload) | ✅ test_game_manager.gd（单元） | 100 次 reset_match() 后的残留状态 |
| **完整对战流程** | ❌ 无 | 长时间运行是否卡死、崩溃、计分溢出 |

### 代码库现状

**Main.tscn 节点结构（#295 组装后）：**

```
Game (Node2D)
├── WorldEnvironment          ← #289 neon glow
├── TopWall / BottomWall      ← StaticBody2D, "walls" group
├── Ball                      ← Area2D, ball.gd
├── PlayerPaddle (mode=0)     ← Area2D, paddle.gd (PLAYER mode)
├── AIPaddle (mode=1)         ← Area2D, paddle.gd (AI mode)
├── ScoringManager            ← Node, scores signals→FSM
├── GameStateMachine          ← Node, 6-state FSM
├── ScoreZoneLeft / Right     ← Area2D body_entered scoring
├── ScoreFlash                ← Node, neon flash effect
├── StartMenu / GameHUD       ← CanvasLayer UI
├── GameOverScreen            ← CanvasLayer winner announcement
└── PauseOverlay              ← CanvasLayer (#296)
```

**关键代码路径：**

- **AI 逻辑** (`paddle.gd` L85–139): `_ai_process()` 使用反应延迟（0.1–0.3s）、位置误差（±20px）、距离调速（1.2x/0.8x）
- **FSM 流程** (`game_state_machine.gd`): MENU →(SPACE)→ SERVING →(await 1s)→ PLAYING ⇌ PAUSED → SCORED →(await 1s)→ SERVING/GAME_OVER →(SPACE)→ MENU
- **计分** (`scoring_manager.gd`): 5 分赢一局，2 局赢一场（三局两胜）
- **Ball serve** (`ball.gd` L75–101): headless 模式下跳过 await 直接设置 velocity
- **Autoload**: `GameManager`（全局状态 + 信号），`AudioEngine`

### Headless 模式特殊性

| 特性 | Editor/运行时 | Headless (`--headless`) |
|------|:----------:|:----------------------:|
| `get_tree()` | 返回 SceneTree | SceneTree 存在（`extends SceneTree`），可创建 timer |
| `create_timer(N)` | 实时等待 N 秒 | **同样实时等待 N 秒** — 这是自动测试的最大障碍 |
| `Input.is_action_pressed()` | 读取键盘 | 无键盘，返回 false |
| `Input.parse_input_event()` | 可用 | 可用 — 可用于模拟按键 |
| `Engine.time_scale` | 1.0 | 可设为高值加速 timer |
| 渲染 | 正常 | 跳过，`_process` 仍以固定 delta 调用 |

**核心挑战：FSM 的 `_timer_1s()` 在 headless SceneTree 中会真实等待 1 秒。按每局约 10 次发球计算，100 局需要 100 × 10 × 1s = 1000s ≈ 16 分钟。**

### 预期行为

1. `godot --path mini-pong/ --headless --script tests/auto_play_test.gd` 正常运行
2. 100 局模拟不崩溃 — 任何 SCRIPT ERROR 视为失败
3. 每局计分到 5（或双方差值 ≥ 1 且一方到 5）
4. 三局两胜逻辑正确 — 先赢 2 局者获胜
5. 比赛有明确胜者 — `GameManager.match_over` 信号携带 "player" 或 "ai"
6. 结束后可重开 — 每局结束后 FSM 回到 MENU，下一局从 MENU 正常启动
7. 任何 SCRIPT ERROR → exit code != 0

### 用户场景

| 场景 | 描述 | 频率 |
|------|------|:----:|
| **A: CI 回归检测** | 每次 git push 运行自动对打，防止重构引入崩溃 | 每次 push |
| **B: 开发迭代验证** | 修改 paddle/ball/FSM 后本地快速验证 100 局稳定性 | 开发中 |
| **C: 计分系统压力测试** | 验证连续 200+ 次得分不出现计分溢出或信号丢失 | 发布前 |

---

## 2. 设计意图

### 为什么当前没有此测试

| 原因 | 详情 |
|------|------|
| 组件优先开发 | #287–#296 每个 issue 独立实现一个子系统，测试也是单元级别 |
| 主场景刚组装完成 | #295 于 2026-07-30 合并 — 在此之前没有可实例化的完整场景 |
| Headless 异步复杂性 | AI 自动对打涉及 timer await、信号链、帧推进，非平凡 |
| CI 管道未建立 | 完整的 CI 测试流水线正在逐步构建 |

### 为什么现在

1. #295 已合并 — 所有组件就位，主场景可实例化
2. AI 对手逻辑已稳定 — `paddle.gd` 的 AI 模式在 #290 中实现并通过单元测试
3. 状态机已验证 — #294 的 FSM 6 状态逻辑通过 16 个测试用例覆盖
4. 需要在正式版发布前建立端到端稳定性基线

### 前置约束

| 约束 | 详情 |
|------|------|
| 测试入口 | `godot --path mini-pong/ --headless --script tests/auto_play_test.gd` |
| 测试框架模式 | 与现有 `run_tests.gd` 一致：`extends SceneTree`，`call_deferred("_run")`，`quit(exit_code)` |
| 玩家挡板 | Main.tscn 中 PlayerPaddle mode=PLAYER — 自动测试需切换为 **mode=AI** |
| FSM 输入 | SPACE 按键驱动 MENU→SERVING / GAME_OVER→MENU 转换 — headless 需模拟 |
| Timer 加速 | `Engine.time_scale` 可加速，但可能影响物理精度；直接跳过 timer 更可控 |
| 计分常数 | POINTS_TO_WIN_GAME=5, GAMES_TO_WIN_MATCH=2（来自 constants.gd） |

---

## 3. 影响分析

### 直接涉及的文件

| 文件 | 模块 | 变更性质 |
|------|------|----------|
| `tests/auto_play_test.gd` | **新文件** | 主测试脚本，100 局循环 + 验证逻辑 |
| (无其他修改) | — | auto_play_test.gd 是纯消费者，读取现有代码，**不修改任何现有文件** |

### 新文件

| 文件 | 用途 |
|------|------|
| `mini-pong/tests/auto_play_test.gd` | 100 回合 AI-vs-AI 自动测试脚本 |

### 间接依赖（读取但不可修改）

| 文件 | 依赖原因 |
|------|----------|
| `gdscripts/paddle.gd` | AI 模式 `_ai_process()`，`Mode.AI` 枚举 |
| `gdscripts/ball.gd` | `serve()` 方法，`score` 信号 |
| `gdscripts/scoring_manager.gd` | `scored`、`game_won`、`match_over` 信号 |
| `gdscripts/game_state_machine.gd` | `transition_to()`、`current_state`、State 枚举 |
| `gdscripts/game_manager.gd` | 全局状态 + `match_over` 信号、`reset_match()` |
| `gdscripts/constants.gd` | POINTS_TO_WIN_GAME=5, GAMES_TO_WIN_MATCH=2 |
| `scenes/Main.tscn` | 完整游戏场景 |
| `scenes/ball.tscn` | Ball 的预设场景（被 Main.tscn 引用） |
| `scenes/player_paddle.tscn` | Paddle 预设（PlayerPaddle 和 AIPaddle 共用） |

### 数据流影响

```
auto_play_test.gd (extends SceneTree)
    │
    ├── 实例化 Main.tscn → 挂载到 SceneTree.root
    │
    ├── 切换 PlayerPaddle.mode = Mode.AI (1)
    │
    ├── 循环 100 次:
    │   │
    │   ├── 1. GameManager.reset_match()
    │   │
    │   ├── 2. 发送 SPACE 事件 (Input.parse_input_event)
    │   │       或直接调用 fsm.transition_to(SERVING)
    │   │
    │   ├── 3. 推进帧循环，等待 match_over 信号
    │   │       await 每帧 → Ball._process() → AI._ai_process()
    │   │       → 得分 → ScoringManager → FSM SCORED → SERVING/PLAYING
    │   │       → 循环直到 GameManager.match_over 触发
    │   │
    │   ├── 4. 验证每局结果:
    │   │       - match_over 信号收到
    │   │       - winner ∈ {"player", "ai"}
    │   │       - 最终 score 一方 = 5 或 ≥5
    │   │       - games_won ≥ 2（三局两胜）
    │   │
    │   └── 5. 发送 SPACE → 返回 MENU，准备下一局
    │
    └── 统计: pass/fail/crash，输出报告，quit(exit_code)
```

### 需要更新的文档

- [x] 无需更新 — 新建测试文件，不影响现有文档

---

## 4. 解决方案对比

### Approach A: 完整 Main.tscn + Input 模拟 + time_scale 加速

**描述：** 实例化 Main.tscn，设置 PlayerPaddle mode=AI，使用 `Input.parse_input_event()` 模拟 SPACE 按键，通过 `Engine.time_scale = 100.0` 加速 timer。

```
# 流程
var scene = load("res://scenes/Main.tscn")
var game = scene.instantiate()
root.add_child(game)

# 设置双 AI
game.get_node("PlayerPaddle").mode = 1  # AI
Engine.time_scale = 100.0  # 加速 timer

for i in 100:
    # 模拟 SPACE → MENU→SERVING
    var ev = InputEventAction.new()
    ev.action = "ui_accept"
    ev.pressed = true
    Input.parse_input_event(ev)
    
    # 等待 match_over
    var done = false
    GameManager.match_over.connect(func(w): done = true)
    while not done:
        await get_tree().process_frame
    
    # 验证
    assert(GameManager.get_winner() != "")
    
    # SPACE → GAME_OVER→MENU
    Input.parse_input_event(ev)
```

| 维度 | 评价 |
|------|------|
| **真实度** | 最高 — 完全模拟真实游戏流程，走完整的 FSM 路径 |
| **复杂度** | 中等 — 需要处理 input 时序、信号连接、帧循环 |
| **速度** | 慢 — time_scale=100 时约 10 秒（100×10×0.01s），time_scale 可能影响物理精度 |
| **可维护性** | 好 — 场景代码不变，测试即客户端 |
| **风险** | `Engine.time_scale` 加速 timer 可能使某些 await 竞态失效 |
| **工作量** | 1–2 天 |

**优点：**
- 最接近真实运行环境
- 自动验证 Input→FSM 的完整链路
- 现有代码零修改

**缺点：**
- time_scale 加速不稳定，大值可能导致 Ball 帧跳过
- 需要处理 FSM `_transition_lock` 时序（SPACE 两次间的间隔）
- 100 局仍需 ~10+ 秒（CI 环境下可接受但偏慢）

---

### Approach B: SceneTree + 直接 FSM 控制 + 帧循环

**描述：** 实例化 Main.tscn，但**绕过 FSM 的 `_input()`**，直接调用 `fsm.transition_to()` 控制状态转换。每帧 `await get_tree().process_frame` 推进模拟。不依赖 time_scale。

```
# 流程
var scene = load("res://scenes/Main.tscn")
var game = scene.instantiate()
root.add_child(game)

var fsm = game.get_node("GameStateMachine")
game.get_node("PlayerPaddle").mode = 1  # AI

# 初始化：手动推进到 SERVING（绕过 MENU input）
GameManager.reset_match()
fsm.transition_to(fsm.State.SERVING)
# FSM 的 SERVING enter_state 会 await _timer_1s() — 1 秒等待
# 方案：在进入前预注入，或使用 call_deferred 异步处理

for i in 100:
    var done = false
    var winner = ""
    GameManager.match_over.connect(func(w): winner = w; done = true, CONNECT_ONE_SHOT)
    
    # 推进帧直到 match_over
    for frame in 10000:  # 安全上限
        await get_tree().process_frame
        if done:
            break
    
    assert(winner != "")
    
    # 返回 MENU
    fsm.transition_to(fsm.State.MENU)
    GameManager.reset_match()
    fsm.transition_to(fsm.State.SERVING)
```

| 维度 | 评价 |
|------|------|
| **真实度** | 高 — 使用真实场景和组件，但不测试 input 路径 |
| **复杂度** | 中等 — 需要理解 FSM 内部状态流 |
| **速度** | **慢** — `_timer_1s()` 在 SceneTree 中真实等待 1 秒，100 局 ≈ 1000 秒 |
| **可维护性** | 中 — 如果 FSM 改变 timer 行为，测试需同步 |
| **风险** | 1 秒 timer 是 dealbreaker，需要额外方案消除 |
| **工作量** | 1–2 天 + timer 绕过方案 |

**优点：**
- 不依赖 input 模拟的脆弱性
- 可以精确控制状态转换时机

**缺点：**
- **1 秒 timer 导致测试太慢（16 分钟）** — 必须绕过的硬伤
- FSM `enter_state(SERVING)` 中的 `await _timer_1s()` 在 SceneTree 下真实等待
- 绕过 timer 需要修改 FSM 或创建 mock — 违背"不修改现有代码"原则

---

### Approach C: 最小测试场景 — 无需 FSM/UI，纯组件驱动 ⭐ 推荐

**描述：** 不加载 Main.tscn。创建一个最小化的 Node2D 测试场景，只包含模拟必需的核心组件：Ball + 两个 AI Paddle + Walls + ScoringManager。通过直接实例化组件、手动设置父子关系、连接信号来驱动完整的 AI-vs-AI 对战，**完全绕过 FSM 和 UI**。

```
# 测试专用最小场景
var test_scene = Node2D.new()

# Walls
var top_wall = _make_wall(640, 5)
var bottom_wall = _make_wall(640, 715)

# Ball
var ball = _make_ball(640, 360)

# AI Paddles (both in AI mode)
var paddle_left = _make_ai_paddle(50, 360)   # "player" side
var paddle_right = _make_ai_paddle(1230, 360) # "ai" side

# ScoringManager
var sm = _make_scoring_manager(ball)

# 驱动循环
for match in 100:
    GameManager.reset_match()
    ball.serve()
    
    while not _match_over:
        await get_tree().process_frame
        ball._process(delta)
        paddle_left._ai_process(delta)
        paddle_right._ai_process(delta)
        # ScoringManager._on_ball_score() 由 ball.score 信号触发
    
    # 验证
    assert(winner in ["player", "ai"])
```

| 维度 | 评价 |
|------|------|
| **真实度** | 中 — 核心物理逻辑（ball + paddle + 计分）完全覆盖，但不测试 FSM/UI |
| **复杂度** | 较高 — 需要手动组装测试场景、创建 mock 节点 |
| **速度** | **极快** — 无 timer，100 局 < 5 秒 |
| **可维护性** | 好 — 测试自包含，不依赖 Main.tscn 结构变化 |
| **风险** | 低 — 各组件独立实例化，与现有单元测试模式一致 |
| **工作量** | 2–3 天 |

**优点：**
- **极快执行** — 100 局 < 5 秒，适合 CI
- 无 timer 依赖 — `_process` 帧驱动，delta 由 SceneTree 提供
- 不依赖 FSM/UI 状态 — 纯物理 + 计分
- 可直接控制 delta 模拟极端帧（大 delta 边界测试）
- 与现有测试模式一致（`extends RefCounted` mock 组件）

**缺点：**
- 不测试 FSM 和 UI 层（但这两个已有单元测试）
- 需要手动构建测试场景（约 50–80 行样板代码）
- 不验证 `Input.parse_input_event` → FSM 的完整链路

---

### 附加方案: 混合 Approach（A + C）

在 Approach A（Main.tscn）的基础上，切入 FSM 的 `_timer_1s()` 使其在 headless 下跳过 await。这需要检测一个"快速模式"标志。

```
# 在 game_state_machine.gd 中
func _timer_1s() -> void:
    var tree := get_tree() if is_inside_tree() else null
    if tree and not Engine.has_singleton("__headless_fast__"):
        await tree.create_timer(1.0).timeout
    # 当 __headless_fast__ singleton 存在时，跳过 timer
```

**不推荐** — 违背"零修改现有代码"原则，且为测试引入生产代码分支。

---

### 推荐: Approach C — 最小测试场景

**理由：**

1. **速度是第一优先级** — CI 流水线中的 100 局测试需要在秒级完成，而非分钟级
2. **组件已有充分单元测试** — FSM（16 个测试）、GameManager、UI 都已单独覆盖，auto_play 应聚焦**集成压力测试**
3. **不修改现有代码** — 最小场景方案零侵入，纯消费者模式
4. **与现有测试模式一致** — `test_ball.gd`、`test_scoring_manager.gd` 等都使用 mock 组件 + 直接方法调用
5. **可扩展** — 未来可轻松扩展为 1000 局、含极限 delta、并发检测等变体

**风险缓解：**
- 同时保留一个轻量级的 Approach A 变体（10 局快速冒烟测试）作为 FSM 集成验证的补充
- 在 auto_play_test.gd 中同时实现两种模式，通过常量切换

---

## 5. 边界条件 & 验收标准

### 正常路径 (Acceptance Criteria)

- [x] **AC1: 脚本正常运行** — `godot --path mini-pong/ --headless --script tests/auto_play_test.gd` 成功执行，exit code 0
  - 短模式（10 局）: < 2 秒
  - 全模式（100 局）: < 10 秒
- [x] **AC2: 100 局不崩溃** — 无 SCRIPT ERROR、无 crash、无无限循环
  - 帧循环有安全上限（如 max 10000 帧/局）
  - NaN/Inf 检测在 ball.gd 和 paddle.gd 中已存在
- [x] **AC3: 每局计分到 5** — 每局结束时至少有一方得分 ≥ 5
  - 验证 `ScoringManager.player_score >= 5 or ScoringManager.ai_score >= 5`
- [x] **AC4: 三局两胜逻辑正确** — 每场比赛先赢 2 局者获胜
  - 验证 `GameManager.player_games_won >= 2 or GameManager.ai_games_won >= 2`
  - 验证 `GameManager.match_over` 信号携带正确 winner
- [x] **AC5: 有明确胜者** — `GameManager.get_winner()` 返回 "player" 或 "ai"，非空字符串
  - 每场比赛结束时有且仅有一个胜者
- [x] **AC6: SCRIPT ERROR → exit code != 0** — 任何 push_error / 异常 → `quit(1)`
  - 默认情况下 `push_error` 不改变 exit code，需在测试中 hook `OS.exception` 或使用 try-catch

### 边界情况

1. **GameManager 状态残留**: 每局结束后调用 `reset_match()` 清除全局状态。验证每局开始前 player_score == 0 && ai_score == 0 && player_games_won == 0 && ai_games_won == 0
2. **Ball 速度漂移**: 长时间运行后 `velocity.length()` 是否仍然接近 `speed`？Ball 每帧 re-normalize（`velocity.normalized() * speed`），但 100 局后验证速度
3. **NaN 传播**: Ball 已检测 NaN velocity。验证 100 局中 Ball NaN 检测从未触发（否则测试失败）
4. **AI 反应延迟随机性**: 验证每局的时间分布不同（不是纯确定性模拟）
5. **双方同时得分**: ScoreZone + `_process` X 边界检测有 `_scored_this_frame` 双重触发保护。验证 100 局中无双重得分
6. **Paddle 越界**: AI 目标位置可能超出屏幕 → paddle `_ai_process` 做了 clamp。验证 100 局中 paddle 始终在 [min_y, max_y]
7. **极快/极慢帧**: 手动注入 `delta=0.001` 和 `delta=0.1`（ball 已 guard `delta > 0.1`）

### 失败路径

1. **Ball 无限反弹**（无得分）: 安全上限内（10000 帧）未触发 match_over → 测试超时失败
2. **ScoringManager 重复信号**: `_is_match_over` guard 失效 → 比赛结束后继续得分
3. **GameManager autoload 污染**: 上一局异常退出导致 autoload 状态未清理 → 下一局 score 从非零开始

---

## 6. 依赖 & 阻塞

### 前置依赖

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #295 Main Scene Assembly | ✅ CLOSED (PR #339 merged) | 无 — 所有组件可用 |
| #287 Ball Physics | ✅ CLOSED | 无 — ball.gd 稳定 |
| #288 Player Paddle | ✅ CLOSED | 无 — paddle.gd AI 模式已实现 |
| #290 AI Opponent | ✅ CLOSED | 无 — `_ai_process()` 完成 |
| #291 Scoring System | ✅ CLOSED | 无 — 信号链就绪 |
| #294 Game State Machine | ✅ CLOSED | 无 — FSM 就绪（但不直接使用） |
| #293 GameManager | ✅ CLOSED | 无 — autoload 可用 |
| Godot 4.7 CLI | ✅ 已安装 | 低 — `--headless --script` 已验证 |

### 依赖链

```
#287 Ball  ─┐
#288 Paddle ┤
#290 AI     ┤──→ #295 Main Assembly ──→ #297 Auto-Play Test
#291 Score  ┤
#294 FSM    ┤
#293 GM     ┘
```

### 被阻塞项

| 未来工作 | 优先级 |
|----------|:------:|
| CI 管道中集成 auto_play_test | 高 |
| 性能基准测试（1000 局） | 低 |
| 难度调整验证（修改 AI params 后的回归测试） | 中 |

### 准备工作

- [x] 确认 `godot --headless --script` 在当前环境可用
- [x] 确认 Main.tscn 可被 `load()` + `instantiate()` 在 headless 下成功
- [ ] 准备测试专用的 paddle 工厂函数（创建 AI 模式 paddle）
- [ ] 准备测试专用的 ball 工厂函数（或直接实例化 ball.tscn）

---

## 7. Spike / 实验

> **Skipped per depth/standard label.**  
> Section 7 (Spike/Experiment) 仅在 `depth/deep` PRD 中为必需。对于 `depth/standard`，从已合并的 DESIGN 文档和已通过的单元测试中有足够信心选择 Approach C。若实施中遇到意外，可回退到实验阶段验证替代方案。

---

## 8. 延续上下文 (Continuation Context)

### 给 Plan Agent 的移交要点

**推荐方案：Approach C — 最小测试场景**

核心思路：不加载完整的 Main.tscn（避免 FSM timer 阻塞），而是手动组装一个只包含物理+计分组件的最小场景。

**关键实现要素：**

1. **脚本结构**：`extends SceneTree`，使用 `call_deferred("_run")` 延迟启动（等待 autoload 就绪）
2. **场景组装**：创建 `Node2D`，手动添加 Wall(StaticBody2D) × 2 + Ball(ball.tscn 实例) + AI Paddle × 2 + ScoringManager
3. **双 AI 配置**：两个 paddle 都设 `mode = 1` (Mode.AI)，ball 通过 `_resolve_ball()` 在各自 `_ready()` 或手动设置 `_ball_node` 引用
4. **帧驱动循环**：`while not match_over: await get_tree().process_frame` — Ball._process() 自动运行，paddle._ai_process() 需手动调用或在 `_process` 中触发
5. **信号监听**：连接 `ScoringManager.match_over` 或 `GameManager.match_over` 检测比赛结束
6. **reset 模式**：每局结束后 `GameManager.reset_match()` 重置全局状态，手动重置 scoring_manager 和 paddle 位置
7. **安全上限**：每局最多 `max_frames = 10000` 帧防止无限循环
8. **错误检测**：hook `OS.exception` 或 wrap 关键调用在 try-catch，任何异常 → fail + continue next match

**⚠️ SceneTree 下的 timer 行为需特别留意：** 如果无意中实例化了 FSM 或使用了 `await tree.create_timer(N)`，它会真实等待 N 秒，不是零耗时。**确保不使用任何 timer。所有组件通过 `_process(delta)` 帧驱动。**

**⚠️ GameManager autoload 全局状态：** GameManager 是全局 singleton。每场比赛结束后必须调用 `GameManager.reset_match()` 清除 games_won 和 scores。同时 scoring_manager 的 `_is_match_over` 也需手动重置。

### 测试输出格式

```
=== Auto-Play Test: 100 Matches (AI vs AI) ===

Match 001: AI wins — 2 games to 1 (scores: 5-3, 4-5, 5-2) [342 frames] ✅
Match 002: Player wins — 2 games to 0 (scores: 5-2, 5-1) [287 frames] ✅
...
Match 100: Player wins — 2 games to 1 (scores: 5-4, 3-5, 5-0) [401 frames] ✅

=== Results ===
✅ Passed: 100/100
❌ Failed: 0/100
   Crashes: 0
   Timeouts: 0
   Avg frames/match: 348.5
   Avg time/match (est): 5.8s @60fps

Total time: 4.2s (headless)
Exit code: 0
```

### 关键常量

| 常量 | 值 | 来源 |
|------|-----|------|
| MATCH_COUNT | 100 | 需求 |
| MAX_FRAMES_PER_MATCH | 10000 | 安全上限（~167 秒 @60fps） |
| POINTS_TO_WIN_GAME | 5 | constants.gd |
| GAMES_TO_WIN_MATCH | 2 | constants.gd |
| AI_REACTION_DELAY_MIN/MAX | 0.1 / 0.3 | constants.gd |
| AI_POSITION_ERROR | 20.0 | constants.gd |

### 与现有测试的关系

- `run_tests.gd` — 新增 `_run("res://tests/auto_play_test.gd", "Auto-Play")` 条目
- 或者 auto_play_test.gd 作为独立入口（`--script tests/auto_play_test.gd`），不依赖 run_tests.gd
- **推荐独立入口** — 避免拉长 run_tests.gd 的总耗时（其他测试 < 1s，auto_play ~5s）

### 主要风险

| 风险 | 缓解 |
|------|------|
| Ball 和 paddle 的 `_ready()` 在 headless 无 viewport 时有 fallback 行为差异 | 已在 ball.gd 和 paddle.gd 中有 FALLBACK_SCREEN_* 常量保护 |
| ScoringManager 的 `_ready()` 期望 ball 为 sibling | 确保 ball 和 scoring_manager 在同一父节点下 |
| Paddle `_resolve_ball()` 依赖父节点结构 | 手动设置 `paddle._ball_node = ball` 绕过自动解析 |
| GameManager autoload 在 headless SceneTree 中可用 | 已验证 — autoload 在 `call_deferred` 时就绪 |

# DESIGN: [Test] 端到端可玩验证 (E2E Playability — AI vs AI 全链路自动对打)

> **Parent Issue:** #394
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** B — 新建真实物理 e2e 场景测试（确认 PRD §4.2 推荐；否决 A 手动物理扩展 / C 仅 L2 无断言）
> **Reference PRD:** docs/PRD/394-e2e-playability.md（research PR #445，已合并）
> **所有权:** `content_ownership: mechanical`（纯测试基建；全部断言/场景/注册为机械实现，零游戏代码改动）
> **深度:** depth/standard（Issue 无 depth 标签，按 #372/#393 惯例）—— 产出 DESIGN；**TASKS 跳过**（受影响文件 ≤4、子系统 2、无迁移/替换，未达 skill 阈值：10 文件 / 5 子任务）
> **上游方案:** docs/PLAN-e2e-verification-v2.md（四层验证 L0-L3 + run-e2e-review.sh）、docs/DESIGN/297-ai-auto-play-test.md（auto_play 先例）、docs/DESIGN/393-main-scene-assembly.md（组装集成先例）
> **测试仅描述，不写可运行测试代码**（implement agent 依此新建 `tests/e2e_playthrough.gd` 等）

---

## 1. 概述

Mini Pong（`mini-pong/`，Godot 4.7.1，720×1280 竖屏）自 #393 主场景组装 merge（PR #444）后，**可玩闭环首次真实存在**（Ball + 双挡板 + BreakoutGrid + WaveController + ScoringManager + GameManager/UpgradePool autoload + UpgradePickUI 全部接线），但没有任何测试用**真实引擎物理 + 真实 AI 对打**把一局打完并断言计分/升级：`auto_play_test.gd`（#297/#385，100 局）是手动物理模拟、无砖墙 harness；`test_integration_393.gd`（10 局）手动调用 `brick.destroy()`，不经过真实球物理，且两者均不覆盖拆砖/穿墙计分一致性与升级参数变化。

本设计按 PRD 推荐 Approach B 新建两个交付物：

1. **`mini-pong/tests/e2e_playthrough.gd`（主交付，L1）**：真实组件迷你树（真实 ball.tscn + player_paddle.tscn×2 均 mode=1 + 真实 BreakoutGrid/WaveController/ScoringManager + 真实 UpgradePickUI + GameManager/UpgradePool autoload），真实物理帧驱动一局到 21 分，AC1-AC4 全部脚本化断言；注册进 `run_tests.gd` 纳入 L1
2. **`mini-pong/tests/playthrough_test.tscn` + `playthrough_driver.gd`（L2 激活，推荐）**：薄运行时场景（实例化真实 Main.tscn + autoplay + 输入馈送 + 超时判定），使 run-e2e-review.sh L2 从 unavailable 变为实际执行（PRD §4.4 推荐；缺失时 L2 warn-only 不阻塞 AC5）

### 设计哲学

1. **真实组件 + 真实物理**（Approach B 确认）：验证对象 = 生产游戏本身，不是测试复刻；手动物理（Approach A）无法验证真实引擎的砖墙/穿墙/计分链路，否决
2. **零游戏代码改动红线**：只新增 `tests/` 文件 + `run_tests.gd` 注册行；所有断言基于既有公开 API/信号（PRD §1.4 不改动约束）
3. **与 Main.tscn 同构组装**：测试树镜像 Main.tscn 的节点名与几何（Ball/PlayerPaddle/AIPaddle/LeftWall/RightWall/BreakoutGrid/WaveController/ScoringManager/UpgradePickUI），复用 #393 已实测的组装模式——节点名决定 `last_toucher` 归属与 `../` 相对路径解析
4. **升级 UI 数据流走真实 UI**：AC2「打空后触发升级 UI 数据流」用**真实 UpgradePickUI 实例**（`wave_settled` → `open()` → `get_candidates(3)` → 输入 `ui_accept` → `_confirm` → `apply(id)` → reveal → `close()` → `advance_settlement()`），与生产路径逐字节一致；`_reveal_hold` 注入 0.05s（#388 明示测试可注入）
5. **确定性双保险**：`UpgradePool.rng.seed(20260813)` 固定抽取序列（与 test_upgrade_pick_ui SEED 同值）；帧数上限 + 墙钟超时双闸防死循环；AI 失误参数沿用 e2e_shots 实测可达族（PlayerPaddle 默认 24 / AIPaddle 200）
6. **AC4 弹性覆盖**：局内自然应用的机械完整升级逐一断言参数变化；不足 3 个不同升级时走 PRD §5.3 失败路径 4 的降级路径（局后直接 `UpgradePool.apply` 补足，注释说明），保证 AC4 永不 flaky

### 1.1 关键事实（plan agent 已对照源码核实）

| 事实 | 核实结果 |
|------|---------|
| 既有测试不满足 AC | `auto_play_test.gd`：`_simulate_frame()` 手动调 `_on_body_entered`/`_on_area_entered`，**避开 ball._process**（serve 的 await），文件头自述「无砖墙 harness → 只有出界分」；`test_integration_393.gd`：逐砖手动 `b.destroy()`，不经过球物理——两者均无计分一致性/升级生效断言 |
| 真实物理可行性 | e2e_shots.json autoplay（双挡板 mode=1 + AIPaddle ai_position_error=200）在 #372 修复后 03_gameover 300s 内可达 → 真实物理 21 分可达已实测（PRD §7 spike 2） |
| GameManager API（AC1 关键） | **`get_winner()` 不存在**（#385 移除局/比赛分层时删除）；终局信息在 `match_over(winner: String)` 信号（"player"/"ai"）+ `is_run_over()`。PRD §4.2 断言 `get_winner()` 非空**已过时**——设计改用 match_over 捕获（附录 A） |
| GameManager 计数 API（AC3） | `player_score/ai_score` + `player_brick_count/ai_brick_count/player_pierce_count/ai_pierce_count`；查询 `get_brick_count(side)` / `get_pierce_count(side)`；`add_score(winner, amount, kind)` 统一入口；`_bump_count` 对 "boundary" 不计数（出界分 = 总分余项） |
| 计分类信号（AC3 信号计数） | `brick_scored(side)` / `pierce_scored(side)`（#392 按类信号，boundary 不触发）/ `score_changed(p, a)` |
| ScoringManager 契约 | `_on_ball_score(side)`：`ball._crossed_wall` → `add_score(winner, 3, "pierce")`，否则 `add_score(winner, 1, "boundary")`；`_on_brick_destroyed`：`ball.last_toucher` 非空 → `add_score(toucher, 1, "brick")`；同帧去重帧守卫 `_brick_destroyed_this_frame` |
| ball.gd 关键状态 | `last_toucher`（按挡板节点名 PlayerPaddle/AIPaddle 判定）、`_crossed_wall`（墙带边沿触发，触球/发球复位）、`serve()`（in-tree 有 0.5s 延时）、`speed_scale` + `set_speed_scale_timed`（缓时）、`set_frozen`、`screen_width/height` 可注入（headless 视口为 0，测试须手动设 720×1280，auto_play 同法） |
| paddle.gd | `enum Mode { PLAYER=0, AI=1 }`；`mode`、`ai_position_error`（默认 24）、`paddle_width`（默认 120）+ `base_paddle_width`（_ready 捕获）、`set_paddle_width(w)`、`magnet_enabled`；AI 模式 `_process` 自动追球（in-tree 无需手动驱动，与 auto_play 手动 `_ai_process` 不同——本测试用真实引擎帧） |
| UpgradePool | autoload；`rng.seed()` 可播种（test_upgrade_pool TC-I1 已验）；`get_candidates(3)`（60/30/10 稀有度先掷 + 回退链）；`apply(id)` → bool + `upgrade_applied` 信号 + `stacks`；`stub_activated` 桩标记；目标解析经 groups（balls/paddles/breakout_grids）惰性注入 `ball_ref/paddle_ref/grid_ref` |
| upgrade_defs | 6/9 机械完整（long_arm→`paddle.paddle_width += LONG_ARM_STEP*base`；fireball→`ball.speed ×1.1` + grid blast；battering_ram→grid blast；magnet_core→`paddle.magnet_enabled=true`；slow_time→`ball.set_speed_scale_timed(0.0, 2.0)`；pre_hole→`grid.open_hole(1)` 挂起至下波）；3 桩（twin/stardust/phantom → `mark_stub_effect`） |
| WaveController | `start_first_wave()` 幂等首波入口（#393 B.1）；`wall_cleared` → `settle_wave()` → `wave_settled` →（`settle_hold=false` 延时自动推进 / `true` 等 `advance_settlement()`）；`advance_settlement()` 幂等（非结算期 no-op，run-over 分支 end_wave_cycle）；`settle_delay` 可注入（test_wave_cycle SHORT_SETTLE=0.01 惯例） |
| UpgradePickUI | `_ready` 自动连 `GameManager.wave_settled → open()`；`open()` 幂等 + `get_tree().paused=true` + `_set_settle_hold(true)`（group 寻址 wave_controllers）；`_unhandled_input`（ui_left/ui_right/ui_accept）；`_confirm` → `apply(_focus_index)` → `_start_reveal()`（`_reveal_hold` 可注入缩短）→ `close()` → 恢复 paused + `advance_settlement()`；**Godot 4 `create_timer` 默认 process_always=true → paused 下 reveal 计时照常推进**（test_upgrade_pick_ui D4/E4 已验） |
| Main.tscn 几何（测试树镜像） | LeftWall(5,640) / RightWall(715,640)（StaticBody2D, groups=[walls]）；Ball(360,640)；PlayerPaddle(360,1240)；AIPaddle(360,40, mode=1)；BreakoutGrid position=(0,640)（wall_y 默认 640 → 砖行世界 y=640 垂直居中）；WaveController/ScoringManager 直挂根 |
| brick.tscn | StaticBody2D（collision_layer=2，球 mask=3 覆盖 → body_entered 零配置生效，#393 已验）；`destroy()` + `grid` 回引用；group "bricks" |
| run_tests.gd | `_run_async(path, name)` 模式（await tester.run()）；当前 24 套件（2137 passed / 0 failed，2026-08-13 研究期基线） |
| run-e2e-review.sh L2 | 检查 `$SUBPROJECT/tests/playthrough_test.tscn` 存在 → `godot --path mini-pong/ --headless tests/playthrough_test.tscn`；缺失 → unavailable warn-only（exit 0 不阻塞）；L2 真实失败(1)才红 |

### 1.2 与 PRD 的差异决策（plan 定稿）

| PRD 断言 / 待决项 | 本设计定稿 | 理由 |
|------------------|-----------|------|
| AC1 判定用 `GameManager.get_winner()`（PRD §4.2） | **改用 `match_over(winner)` 信号捕获** + `is_run_over()` | `get_winner()` 已随 #385 删除（源码核实）；match_over 载荷即权威胜者 |
| AC2 升级 UI 数据流（PRD §3.4 数据流图） | **实例化真实 UpgradePickUI**，测试只馈送 `ui_accept` 输入事件 | 与生产路径逐字节一致（open→候选→确认→reveal→close→advance）；`_reveal_hold` 注入 0.05s；test_upgrade_pick_ui 已验证 paused 下 reveal 计时推进 |
| AC4 覆盖策略（PRD §5.2 边界 5 / §5.3 失败路径 4） | 局内自然应用为主 + **降级路径直接 apply 补足**（注释说明） | 保证 ≥3 个不同机械完整升级的参数变化断言永不 flaky；seed 固定使自然路径高度可复现 |
| 帧数上限（PRD §5.2 边界 1 建议 60k） | `MAX_FRAMES=60000` + **墙钟超时 `DEADLINE_MS=300_000`** 双闸 | 帧闸防死循环；墙钟闸对齐 e2e_shots 03_gameover 300s 实测上限（serve 0.5s 延时是真实时间，纯帧闸不可靠） |
| L2 playthrough_test.tscn（PRD §4.4 可选） | **提供**（tscn + driver 双文件） | AC5「全部层通过」更完整；缺失时 warn-only 保底不阻塞 |
| `e2e_shots.json`（PRD §3.1 可能 MODIFY） | **不计划改动** | 新套件不改变 03_gameover 可达性（同参数族）；如 implement 实测暴露帧数问题再单独调整 |
| `docs/GAME_DESIGN/09-TESTING.md`（PRD §3.5 可选） | **实施期同步**（P2，非必须） | 与 #393 先例一致：文档在实现期随测试清单更新 |

---

## 2. 现有组件修改

| 文件 | 改动 | 为什么 |
|------|------|--------|
| `mini-pong/tests/run_tests.gd` | 新增 1 条 `_run_async("res://tests/e2e_playthrough.gd", "E2E Playthrough")`（置于 Assembly Integration 之后、Auto-Play 之前） | 注册新套件进 L1 全量回归（PRD §8 Phase 3） |
| `mini-pong/gdscripts/*` | **零改动** | 纯测试 Issue 红线（PRD §1.4） |
| `mini-pong/scenes/*` / `project.godot` | **零改动** | 同上 |

> **受影响测试文件清单（implement 改造面）：** 仅 `run_tests.gd`（+1 注册行）。既有 24 套件零改动——新套件与 auto_play_test.gd（无墙手动物理基线）互补不互替（PRD §8 风险 3）。

---

## 3. 新建文件（实现期）

### 3.1 `mini-pong/tests/e2e_playthrough.gd`（主交付，L1，~350-450 行）

- **File:** `mini-pong/tests/e2e_playthrough.gd`
- **Type:** 测试脚本（`extends RefCounted` + `run()`，`_run_async` 注册）
- **测试范式:** test_integration_393 的迷你树组装 + auto_play 的帧驱动循环（但用**真实引擎物理帧**）+ test_upgrade_pick_ui 的输入馈送

#### 常量与可注入参数

```gdscript
const CONSTS = preload("res://gdscripts/constants.gd")
const SEED: int = 20260813            # UpgradePool.rng.seed 固定值（与 test_upgrade_pick_ui 同值；AC4 可复现）
const MAX_FRAMES: int = 60000         # 帧数上限（PRD §5.2 边界 1；防死循环）
const DEADLINE_MS: int = 300_000      # 墙钟超时（对齐 e2e_shots 03_gameover 300s 实测上限）
const SHORT_REVEAL: float = 0.05      # UpgradePickUI._reveal_hold 注入（#388 测试可注入；生产 0.8s）
const AI_ERROR_AI: float = 200.0      # AIPaddle ai_position_error（e2e_shots 实测可达族：失误→失分→21 分可达）
# PlayerPaddle 保持默认 ai_position_error=24（瞄准好→清墙/拆砖，e2e_shots 同配置）
const SCREEN_W: float = 720.0         # headless 视口为 0 → 手动注入（auto_play 同法）
const SCREEN_H: float = 1280.0
const PADDLE_Y_TOP: float = 40.0      # AIPaddle（Main.tscn 几何镜像）
const PADDLE_Y_BOT: float = 1240.0    # PlayerPaddle（Main.tscn 几何镜像）
const WALL_X_LEFT: float = 5.0        # LeftWall（Main.tscn 几何镜像）
const WALL_X_RIGHT: float = 715.0     # RightWall
```

#### 场景组装节点树（`_make_fx()`，镜像 Main.tscn 接线）

```
TestHost (Node2D, tree.root 下)
├── LeftWall (StaticBody2D, groups=[walls], pos=(5,640), CollisionShape2D 10×1280)
├── RightWall (StaticBody2D, groups=[walls], pos=(715,640), CollisionShape2D 10×1280)
├── Ball (instance ball.tscn, pos=(360,640); screen_width=720 / screen_height=1280 手动注入)
├── PlayerPaddle (instance player_paddle.tscn, pos=(360,1240), mode=1)   ← 节点名契约（last_toucher）
├── AIPaddle (instance player_paddle.tscn, pos=(360,40), mode=1, ai_position_error=200)
├── BreakoutGrid (instance breakout_grid.tscn 或 Node2D+breakout_grid.gd, pos=(0,640))  ← wall_y 默认 640
├── WaveController (Node + wave_controller.gd; settle_delay=0.01 注入)
├── ScoringManager (Node + scoring_manager.gd)          ← ../Ball ../BreakoutGrid 相对路径解析
└── UpgradePickUI (instance ui_upgrade_pick.tscn; _reveal_hold=0.05 注入)  ← 真实 UI，AC2 数据流
# GameManager / UpgradePool = project.godot autoload（不建节点）
# FSM / ScoreZone / HUD / 转场 / 失败屏：不组装（本套件只验证可玩闭环核心，与 #297 同哲学）
```

组装要点：
- **节点名必须精确**：`Ball` / `PlayerPaddle` / `AIPaddle` / `BreakoutGrid` / `WaveController` / `ScoringManager` —— ball.gd 按名判 `last_toucher`，ScoringManager/WaveController 按 `../` 相对路径解析（#393 已验契约）
- UpgradePickUI `_ready` 自动连 `wave_settled→open`，`open()` 经 group `wave_controllers` 置 `settle_hold=true` → 推进由 UI close 接管（无需手动 settle_hold）
- 测试清理：run 结束 `host.queue_free()` + `GameManager.reset_match()` + `UpgradePool.stacks/stub_activated/_available` 复位（test_upgrade_pick_ui `_reset()` 同法）——防污染后续套件

#### 驱动循环伪代码

```gdscript
func run() -> void:
    print("\n=== E2E Playthrough (#394) ===")
    GameManager.reset_match()
    UpgradePool.rng.seed = SEED
    _connect_signals()                 # wave_started/wave_settled/wall_cleared/wall_generated/
                                       # brick_scored/pierce_scored/score_changed/match_over/upgrade_applied
    var fx := _make_fx()
    var ctrl: Node = fx.controller
    ctrl.start_first_wave()            # 首波（#393 B.1 入口；wave_index 1 + 首墙生成）
    var frame: int = 0
    var start_ms: int = Time.get_ticks_msec()
    while not GameManager.is_run_over() and frame < MAX_FRAMES \
            and Time.get_ticks_msec() - start_ms < DEADLINE_MS:
        if fx.ui.visible:              # 升级窗口打开（真实 UI，paused=true）→ 馈送确认（焦点 0）
            _feed_accept()
        await _tree().process_frame    # 真实引擎帧（ball._process / paddle._process 自动运行）
        frame += 1
    # ── 收尾断言（AC1-AC4）──
    _assert_ac1_match_completed()      # 21 分终局 + 胜者 + 帧/墙钟闸
    _assert_ac2_wave_flow()            # 每波墙生成 + 打空 + 升级 UI 数据流
    _assert_ac3_scoring_consistency()  # 拆砖 +1 / 穿墙 +3 总分 == 计数重构
    _assert_ac4_upgrades_effective()   # ≥3 升级参数变化生效（不足走降级路径）
    await _cleanup(fx)
    print("  E2E Playthrough: %d passed, %d failed" % [passed, failed])
```

要点：
- **不手动调 `_simulate_frame`**——节点 in-tree，引擎逐帧驱动 ball._process / paddle._process（真实物理；与 auto_play 的手动模拟本质区别，PRD §4.2 核心）
- `ball.serve()` 的 0.5s 延时（in-tree 定时器）自然消化在帧循环里；每次出界分 → serve 复位 `last_toucher/_crossed_wall`（#385 契约）
- UI 打开期间树 paused=true：`process_frame` 信号 pause-immune 照常触发（#388 E4 已验）；ball 冻结即「等待选择」的真实游戏语义

### 3.2 `mini-pong/tests/playthrough_test.tscn` + `mini-pong/tests/playthrough_driver.gd`（L2，推荐）

- **File:** `mini-pong/tests/playthrough_test.tscn` + `mini-pong/tests/playthrough_driver.gd`
- **Type:** 运行时场景（run-e2e-review.sh L2：`godot --path mini-pong/ --headless tests/playthrough_test.tscn`）
- **用途:** 激活 L2 层（PRD §4.4）：真实 Main.tscn 全链路（含 FSM/HUD/转场/失败屏）自动打完一局，exit code 反映成败

```
PlaythroughTest (Node, playthrough_driver.gd)
└── Game (instance Main.tscn, 运行时 add_child)
```

驱动逻辑（`_ready` 起）：
1. `GameManager.reset_match()`；`UpgradePool.rng.seed = SEED`
2. autoplay 参数（镜像 e2e_shots.json）：`Game/PlayerPaddle.mode=1`、`Game/AIPaddle.mode=1`、`Game/AIPaddle.ai_position_error=200`
3. 开局：`Input.parse_input_event(InputEventAction("ui_accept"))` → FSM MENU→SERVING→PLAYING（PLAYING 入口触发 `start_first_wave`，#393 B.1）
4. 轮询帧循环（墙钟上限 `DEADLINE_MS=300_000`）：`Game/UpgradePickUI.visible` 时馈送 `ui_accept`（焦点 0，确定性）；`GameManager.is_run_over()` → 退出
5. 断言：`is_run_over()==true` 且捕获的 `match_over` 胜者非空、墙钟未超时 → `get_tree().quit(0)`；否则 `quit(1)`
6. 超时/异常 → 打印当前分数/波次 → `quit(1)`

> 与 L1 的关系：L1 是隔离迷你树（无 FSM/HUD/转场，断言粒度细）；L2 是生产 Main.tscn 全链路冒烟（验证「真实游戏跑完一局不崩」）。两者互补；L2 缺失时 run-e2e-review.sh warn-only 不阻塞 AC5（PRD §6.3）。

---

## 4. 数据流

### Flow 1: 完整一局主路径（AC1/AC3）

```
start_first_wave()
  → begin_wave(1) → wave_started(1) → generate_wave(厚度 1) → wall_generated(n>0)
ball(真实物理) ── 击砖 ──► BreakoutGrid._on_brick_destroyed
  → brick_destroyed(brick,pos) → ScoringManager._on_brick_destroyed
      → last_toucher 非空 → GameManager.add_score(toucher, 1, "brick")   ← 拆砖 +1
球穿越墙带后出界（未被接住）→ ball.score(side)
  → ScoringManager._on_ball_score(crossed=true) → add_score(winner, 3, "pierce")   ← 穿墙 +3
球普通出界 → _on_ball_score(crossed=false) → add_score(winner, 1, "boundary")      ← 兜底 +1
任一方总分 ≥ 21 → _check_run_end → match_over(winner) → is_run_over()=true → 测试收尾断言
```

### Flow 2: 波次结算 → 升级 UI 数据流（AC2）

```
最后一砖击碎 → remaining_bricks==0 → wall_cleared() 恰好一次
  → WaveController._on_wall_cleared → GameManager.settle_wave() → wave_settled(idx)
      → UpgradePickUI.open(idx)（真实 UI 自动响应）
          ├─ get_candidates(3)（UpgradePool，seed 固定序列）→ 断言 3 张（池未耗尽时）
          ├─ 测试馈送 ui_accept → _confirm → UpgradePool.apply(id) → upgrade_applied(id) + stacks+1
          ├─ reveal（_reveal_hold=0.05，paused 下计时推进）→ close()
          │    ├─ paused=false（恢复游戏时间）
          │    └─ advance_settlement() → WaveController._advance_wave()
          │         → begin_wave(idx+1) → wave_started(idx+1) → generate_wave(更厚) → wall_generated
          └─（终局竞态：is_run_over → 跳过 UI，WaveController end_wave_cycle，不生成新墙）
```

### Flow 3: 计分一致性重构（AC3）

```
局末（match_over 后）：
player_score == player_brick_count*1 + player_pierce_count*3 + boundary余项(≥0)
ai_score      == ai_brick_count*1      + ai_pierce_count*3      + boundary余项(≥0)
信号监听计数一致：brick_scored(player) 次数 == GameManager.get_brick_count("player") 等（双侧 4 项）
```

### Flow 4: 失败/降级路径（AC4 补足 / 超时）

```
AC4 自然路径不足 3 个不同机械升级 →
  降级路径（PRD §5.3 失败路径 4，注释说明）：局后直接 UpgradePool.apply(id) 补足
  （long_arm → paddle_width；fireball → ball.speed；pre_hole → grid._pending_holes），
  复用局内同款参数快照断言；若 apply 返回 false（max_stacks 耗尽）→ 该 id 已充分验证，跳过
帧数/墙钟超时 → 打印当前 player/ai 分数 + wave_index + 已应用升级清单 → fail（诊断信息齐全）
```

---

## 5. 边界条件与失败路径

### 边界条件（≥7）

| # | 场景 | 处理 |
|---|------|------|
| 1 | AI 互怼死循环（球永不落） | `MAX_FRAMES=60000` + `DEADLINE_MS=300_000` 双闸；超限 fail + 打印分数/波次/升级清单 |
| 2 | 砖墙打空但无人到 21（波次推进中） | 正常路径：UI 数据流 → 新墙；断言 wave_index 递增 + 新墙砖数 ≥ 旧墙（厚度杠杆 `WAVE_THICKNESS_STEP=1`） |
| 3 | 拆砖与出界同帧 | ScoringManager 帧守卫已实现（#385 AC4）——总分仍 == 计数重构值（AC3 公式覆盖） |
| 4 | 升级候选不足 3 张（池耗尽） | `get_candidates` 回退链已实现（#387）；断言返回非空即可；AC4 只要求 ≥3 个不同升级被应用 |
| 5 | 桩升级（twin/stardust/phantom）被抽中 | 断言 `UpgradePool.stub_activated[id]==true`（桩标记，可断言「被应用」）；参数变化断言只针对 6 个机械完整升级（PRD 边界 5） |
| 6 | 21 分在升级窗口期间达到 | WaveController run-over 分支 `end_wave_cycle`（#388 边界 5）：断言不生成新墙、match_over 触发；测试驱动循环自然退出 |
| 7 | headless 无渲染资源 | 全部断言纯逻辑/信号；UpgradePickUI 为 CanvasLayer 无渲染依赖（test_upgrade_pick_ui 同范式已验）；brick 贴图缺失不影响 StaticBody2D 碰撞 |
| 8 | UI 打开期间 paused 导致测试等待挂起 | 测试等待全部用 `await process_frame`（pause-immune）+ 帧计数，不用 create_timer 依赖（Godot 4 create_timer 默认 process_always=true 亦可，但帧轮询更稳） |

### 失败路径（≥4）

| # | 场景 | 处理 |
|---|------|------|
| 1 | 组件未接线（守卫生效） | 消费方 `get_node_or_null` + `has_signal/has_method` 双守卫（#384/#393 惯例）；组装错误以断言失败暴露而非静默 |
| 2 | 终局后残留事件 | GameManager `_is_run_over` 守卫 return（#385）；驱动循环 match_over 后停止；`_cleanup` 断开信号防跨套件泄漏 |
| 3 | 超时/死循环 | 双闸 fail + 完整诊断打印（分数/波次/升级/帧数） |
| 4 | 一局内升级未达 3 个（随机性） | seed 固定 + ai_position_error=200（实测可达）优先；仍不足 → 降级路径直接 `apply` 补足（PRD §5.3 失败路径 4，注释说明） |
| 5 | 零穿墙分（pierce 未发生） | `ai_position_error=200` 下 AI 漏接 → 穿越墙带后出界概率高；若整局 0 pierce（统计上极罕见），AC3 一致性公式仍成立，另可重跑一局（≤3 次）再断言 pierce ≥ 1 |

---

## 6. 每场景 / 每组件配置

| 组件 | 配置 | 依据 |
|------|------|------|
| Ball | `screen_width=720` / `screen_height=1280` 手动注入；其余默认 | headless 视口 0（auto_play 同法）；竖屏几何 |
| PlayerPaddle | `mode=1`，`ai_position_error` 默认 24 | e2e_shots 同配置：好瞄准 → 清墙/拆砖 |
| AIPaddle | `mode=1`，`ai_position_error=200` | e2e_shots 实测可达族：失误 → 失分 → 21 分可达 |
| BreakoutGrid | `position=(0,640)`，`wall_y` 默认 640 | Main.tscn 几何镜像；砖行世界 y=640 与 ball 墙带判定同源 |
| WaveController | `settle_delay=0.01`（注入短延时；生产 1.0） | test_wave_cycle SHORT_SETTLE 惯例；推进实际由 UI close 接管（settle_hold 由 UI.open 置 true） |
| UpgradePickUI | `_reveal_hold=0.05`（注入；生产 0.8） | #388 明示测试可注入；每波省 0.75s |
| UpgradePool | `rng.seed = 20260813`（run 起始） | 抽取序列确定（AC4 可复现） |
| GameManager | `reset_match()`（run 起始/清理） | 状态归零防跨套件污染 |

---

## 7. 集成点

> **Status 约定:** ⬜ = pending（实现期接线）；✅ = connected（implement agent 验证后更新）。review agent merge 前核实全部 ⬜ 已解决或显式推迟。

| 集成 | 我们的组件 | 目标组件 | 方式 | Status |
|------|:---:|:---:|------|:---:|
| 首波触发 | e2e_playthrough.gd | WaveController.start_first_wave | 直接调用（#393 B.1 入口） | ⬜ pending |
| 拆砖分链路 | BreakoutGrid.brick_destroyed | ScoringManager._on_brick_destroyed → GameManager.add_score(1,"brick") | 信号连接（真实物理击砖触发） | ⬜ pending |
| 穿墙分链路 | Ball.score | ScoringManager._on_ball_score → add_score(3,"pierce") | 信号连接（`_crossed_wall` 判定） | ⬜ pending |
| 升级 UI 数据流 | UpgradePickUI.open | GameManager.wave_settled（_ready 自动连） | 信号（真实 UI） | ⬜ pending |
| 升级应用 | UpgradePickUI._confirm | UpgradePool.apply(id) → upgrade_applied | 输入事件馈送 ui_accept | ⬜ pending |
| 推进接管 | UpgradePickUI.close | WaveController.advance_settlement（group 寻址） | 方法调用（UI 内部） | ⬜ pending |
| 套件注册 | run_tests.gd | e2e_playthrough.gd | `_run_async` 条目 | ⬜ pending |
| L2 激活 | playthrough_test.tscn | run-e2e-review.sh L2 检查点 | 文件存在 → 实际执行 | ⬜ pending |

---

## 8. 实施阶段

| 阶段 | 优先级 | 内容 | 工作量 |
|:----:|:------:|------|:------:|
| Phase 1 | P0 | `e2e_playthrough.gd` 场景组装（迷你树镜像 Main.tscn + seed/帧闸/延时注入）+ 驱动循环 | 0.5 天 |
| Phase 2 | P0 | AC1-AC4 断言实现（§9 Scenario A-D 逐条）+ 降级路径 | 0.5 天 |
| Phase 3 | P0 | `run_tests.gd` 注册 → `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全量回归全绿（基线 2137 + 新套件） | 0.25 天 |
| Phase 4 | P1 | （推荐）`playthrough_test.tscn` + `playthrough_driver.gd` → 本地跑 run-e2e-review.sh 确认 L2 激活且 exit 0 | 0.25 天 |
| Phase 5 | P2 | （可选）`docs/GAME_DESIGN/09-TESTING.md` 测试清单同步 | 0.1 天 |

---

## 9. 测试用例描述

> 仅描述，不写可运行测试代码（implement agent 依此写 `tests/e2e_playthrough.gd` / `playthrough_driver.gd`）。

### Scenario A: AC1 — AI vs AI 自动打完一局到 21 分

- Test 1（终局可达）：真实物理驱动至 `GameManager.is_run_over()==true`；帧数 < `MAX_FRAMES` 且墙钟 < `DEADLINE_MS`（超限 fail 并打印诊断）
- Test 2（胜者存在）：`match_over(winner)` 已捕获且 winner ∈ {"player","ai"}（PRD 的 `get_winner()` 不存在——以信号载荷为权威）
- Test 3（终局一致性）：胜者总分 ≥ `WIN_SCORE`(21)、败者总分 < 21；`reset_match()` 后分数归零
- Test 4（终局守卫）：match_over 后不再有新计分事件（信号监听计数冻结）

### Scenario B: AC2 — 每波生成砖墙 + 打空后升级 UI 数据流

- Test 1（首波生成）：`start_first_wave()` 后 `wave_started(1)` 且 `wall_generated(remaining>0)`；`grid.remaining_bricks == 期望砖数(厚度)`（GAPS 布局：cols=10 − 2 缝列 = 8/行 → 8×厚度；hole 挂起时按净数）
- Test 2（每波更厚）：第 N 波 `grid.rows == WAVE_START_THICKNESS + (N-1)*WAVE_THICKNESS_STEP`；新墙 remaining ≥ 旧墙
- Test 3（打空触发）：每波最后一砖击碎 → `wall_cleared` 恰好一次 → `wave_settled(idx)` → UpgradePickUI `visible==true`（数据流起点）
- Test 4（候选 3 张）：UI 打开时 `get_candidates(3)` 返回 3 张（池未耗尽；耗尽时非空即可）；`_candidates` 已渲染
- Test 5（确认应用）：馈送 `ui_accept` → `UpgradePool.apply(id)` 返回 true → `upgrade_applied(id)` 恰好一次 → UI reveal → `close()` → `paused` 恢复 false
- Test 6（推进下一波）：`close()` → `advance_settlement()` → `wave_started(idx+1)` → 新墙生成（wave_index 严格递增）
- Test 7（终局不推进）：升级窗口期间任一方到 21 → 不生成新墙、`end_wave_cycle` 生效（#388 边界 5 回归）
- Test 8（信号计数）：wave_started 累计次数 == wave_settled 累计次数 + 1（首波无结算）；wall_cleared 累计 == wave_settled 累计

### Scenario C: AC3 — 拆砖 +1 / 穿墙 +3 总分与事件计数一致

- Test 1（player 侧重构）：`player_score == player_brick_count*1 + player_pierce_count*3 + 余项` 且余项 ≥ 0（余项即 boundary 分，`_bump_count` 对 boundary 不计数）
- Test 2（ai 侧重构）：同上对 ai 侧
- Test 3（信号 == 计数）：监听 `brick_scored`/`pierce_scored` 计数 == `GameManager.get_brick_count/get_pierce_count`（双侧 4 项逐一相等）
- Test 4（拆砖归属）：拆砖分计入 `last_toucher` 侧（球最后碰 PlayerPaddle → player_brick_count+1）
- Test 5（穿墙分值）：pierce 事件经 `_crossed_wall` 路径 → 计 3 分（与 `add_score(_,3,"pierce")` 一致）；整局 pierce 总数 ≥ 1（≤3 局重试兜底，见 §5 失败路径 5）
- Test 6（同帧去重回归）：AC3 公式在任意帧组合下成立（#385 帧守卫覆盖）

### Scenario D: AC4 — ≥3 个升级应用后参数变化生效

- Test 1（应用收集）：监听 `upgrade_applied` 收集 id 集合；断言不同机械完整升级 ≥ 3（不足走降级路径补足，见 Test 8）
- Test 2（long_arm）：apply 后 `paddle.paddle_width` 增量为 `LONG_ARM_STEP * base_paddle_width`（快照对比，浮点容差 1e-4）
- Test 3（fireball）：apply 后 `ball.speed` 增加（×1.1 封顶于 `initial_speed*max_speed_multiplier`）；blast 钩子经 §5 失败路径 4 的受控微检查验证（球旁置砖 → 半径内砖被炸碎，`brick_destroyed` 触发）
- Test 4（battering_ram）：受控微检查——墙存在时 apply → `blast_neighbors` 半径内砖销毁（`brick_destroyed` 信号在后续帧触发）；或断言 `grid.apply_upgrade_hook("blast_neighbors",…)` 派发成功（hook 已注册）
- Test 5（magnet_core）：apply 后 `paddle.magnet_enabled == true`（快照前为 false）
- Test 6（slow_time）：apply 后 `ball.speed_scale == 0.0`（SLOW_TIME_SCALE），`SLOW_TIME_DURATION`(2.0s) 后恢复 `1.0`（等待真实时间或帧计数）
- Test 7（pre_hole）：apply 后 `grid._pending_holes` 增长；下一波 `wall_generated(remaining)` < 无洞期望值（洞柱位整列不实例化，#387 下波消费契约）
- Test 8（桩升级）：twin/stardust/phantom 若被抽中应用 → `UpgradePool.stub_activated[id]==true`（桩标记断言；不做参数变化断言）
- Test 9（降级路径）：自然应用 < 3 个不同机械升级时，局后直接 `apply` 补足（long_arm/fireball/pre_hole 优先）并复用快照断言；`apply` 返回 false（耗尽）→ 该 id 已验证，跳过——保证 Test 1 永不 flaky（注释说明）

### Scenario E: AC5 — run-e2e-review.sh 全层通过

- Test 1（L1 注册）：`run_tests.gd` 含 `e2e_playthrough.gd` 条目；`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（基线 2137 + 新套件断言数），exit code 0
- Test 2（L2 激活）：`tests/playthrough_test.tscn` 存在；`godot --path mini-pong/ --headless tests/playthrough_test.tscn` 跑完一局 quit(0)（L2 从 unavailable → 实际执行）
- Test 3（L0/L3 回归）：check_compile.gd 零错误；L3 视觉帧（01_title/02_midgame/03_gameover）不回归（新文件不触碰 game 代码，预期零影响）
- Test 4（总退出码）：`scripts/run-e2e-review.sh`（按 review agent 惯例）OVERALL=0

### Scenario F: 边界与失败路径（PRD §5.2/§5.3 全量映射）

- Test 1（帧闸）：注入超短帧上限（如 60）→ 超限 fail 路径打印诊断（分数/波次/升级清单）且不崩
- Test 2（组件缺失守卫）：临时移除某组件（如 grid）→ 消费方守卫不崩、断言以失败暴露（#384/#393 容错回归）
- Test 3（终局竞态）：升级窗口期间加分到 21（注入 `add_score`）→ 无新墙、match_over、驱动循环退出
- Test 4（重开循环）：run 结束后 `reset_match` + 重建迷你树再跑首波 → 无残留砖节点、无信号泄漏（#393 清理惯例回归）

### Scenario G: L2 运行时场景（playthrough_test.tscn）

- Test 1（真实 Main.tscn）：实例化后 FSM MENU 态；馈送 ui_accept → SERVING → PLAYING 且 `wave_index==1`（首波触发，#393 B.1）
- Test 2（autoplay 参数）：双挡板 mode==1、AIPaddle ai_position_error==200（e2e_shots 镜像）
- Test 3（升级窗口自动推进）：每波 UI 打开 → 馈送 ui_accept → 升级应用 → 下一波（焦点 0 确定性）
- Test 4（完整一局）：300s 墙钟内 `is_run_over()==true` 且 match_over 胜者非空 → quit(0)；超时 → 打印诊断 → quit(1)

---

## 附录 A: 与 PRD 的差异记录（plan agent 源码核实后定稿）

| PRD 断言 | 实际代码（核实） | 设计决议 |
|---------|----------------|---------|
| AC1 判定 `GameManager.get_winner()` 非空（§4.2） | `get_winner()` **不存在**（#385 删除局/比赛分层时移除）；终局信息在 `match_over(winner)` 信号 | 用 match_over 信号载荷 + `is_run_over()` 判定（Scenario A Test 2） |
| AC2 数据流含 UpgradePickUI 打开（§3.4） | UpgradePickUI `_ready` 自动连 wave_settled；open 幂等 + paused + settle_hold 接管 | 实例化**真实 UI**，测试仅馈送输入事件（最忠实复刻生产路径） |
| AC3 断言「信号监听计数 == GameManager 计数 == 总分重构值」（§4.2） | `brick_scored/pierce_scored` 信号存在（#392）；`_bump_count` 对 boundary 不计数 | 全部采纳，余项即 boundary 分（Scenario C Test 1-3） |
| 帧数上限「如 60k 帧」（§5.2 边界 1） | — | 采纳 60000 + 墙钟 300s 双闸（serve 0.5s 为真实时间，纯帧闸不可靠） |
| AC4 多局策略（§8 风险 2） | — | 定稿单局为主 + 降级路径补足（§9 Scenario D Test 9）；比多局更省时且确定性更强 |
| `e2e_shots.json` 可能 MODIFY（§3.1） | 新套件与 e2e_shots 同参数族 | 不计划改动；如实测暴露问题再单独调整 |
| L2 playthrough_test.tscn「可选」（§3.2/§6.3） | run-e2e-review.sh L2 检查文件存在 | **提供**（tscn + driver）；缺失 warn-only 保底 |

## 附录 B: implement agent 写码参考速查

- **信号连接清单**（全部在 `run()` 起始连接、`_cleanup` 断开）：`GameManager.wave_started/wave_settled/brick_scored/pierce_scored/score_changed/match_over`、`UpgradePool.upgrade_applied`、`fx.grid.wall_cleared/wall_generated`
- **升级参数快照点**：`upgrade_applied` 处理器内先记 `before`（paddle_width/ball.speed/magnet_enabled/speed_scale/_pending_holes.size），apply 已完成（信号在 apply 内 emit）→ 快照需在 `apply` 调用**前**由测试侧记录（监听 `wave_settled` 时预录基线，或对 `_confirm` 路径在馈送 ui_accept 前预录）
- **期望砖数**：GAPS 布局 `expected = 8 * thickness`（cols=10−2 缝列）；`_pending_holes` 消费后按洞列净减（pre_hole 断言用）
- **断言计数**：新套件 `passed/failed` 归入 run_tests.gd 聚合（`_run_async` 自动累加）
- **降级路径注释模板**：`# AC4 降级路径（PRD §5.3 失败路径 4）：本局自然应用仅 N 个升级，直接 apply 补足至 ≥3 个不同机械升级`

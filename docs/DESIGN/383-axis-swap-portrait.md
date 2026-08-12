# DESIGN: [Refactor] 轴交换 + 竖屏 (P0 前置)

> **Parent Issue:** #383
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — 坐标轴交换直改（确认 PRD §4 推荐，与 PLAN-rogue-pong §4.1「坐标只改一遍」零偏差；不做旋转技巧 B、不做双模式开关 C）
> **Reference PRD:** docs/PRD/383-axis-swap-portrait.md（research PR #398，已合并）
> **所有权:** `content_ownership: mechanical`（纯机械坐标轴交换 + 画幅竖屏，无 taste 决策；FSM/scoring 信号链零改动）
> **深度:** depth/standard —— 仅产出 DESIGN 文档；不产出 TASKS 文档；测试仅描述不写代码

---

## 1. 概述

Mini Pong 当前为 **1280×720 横屏**（球沿 X 飞行、左右出界得分、paddle 沿 Y 移动、挡板竖置）。本设计把整套坐标系按「竖屏对打」语义一次性翻转：**画幅 720×1280，paddle 上下分列、沿 X 移动，球沿 Y 垂直对打、上下出界得分，左右墙反弹**。这是 Rogue Pong 攻城战肉鸽的 P0 前置（`docs/PLAN-rogue-pong.md` §4.1 用户已拍板）：垂直攻防主运动轴是 Y，竖屏 720×1280 让砖墙横跨 720px、攻防纵深 1280px，后续所有 feature（砖墙/雨幕/HUD 双得分区）直接建立在本竖屏坐标系上，坐标只改一遍。

**Plan 阶段边界**：本阶段只产出本文档，不碰任何 `.gd` / `.tscn` / `.sh` 文件 —— 下列全部内容为 implement agent 的契约。

### 设计哲学

1. **机械映射、语义唯一**：每个轴交换点只有一种正确改法（§3 总表），无 taste 分支；手感数值（#367 定稿的 BALL_INITIAL_SPEED=330 / PADDLE_SPEED=430 / AI 三参数）**不因轴交换改变**，只改方向语义。
2. **信号链与 FSM 不可动**：`ball.score(side)` → `ScoringManager` → `scored/game_won/match_over` 保持原样；`game_state_machine.gd` / `scoring_manager.gd` 零改动（或仅注释）。得分区只换节点位置与 emit 参数接线。
3. **测试即验收**：物理测试按新竖屏语义**重写而非删除**（Issue 验收条件明确要求）；`test_integration_fsm.gd` 无坐标钉，不动。
4. **一次改完**：不引入 `PORTRAIT` 开关、不做根节点旋转；改完即竖屏，横屏能力丢弃（Rogue Pong 方向已确认不再需要）。

---

## 2. 现状核实（plan agent 已对照源码确认）

| 文件 | 现状（已核实行号） |
|------|-------------------|
| `mini-pong/project.godot` | L25-26：`viewport_width=1280, viewport_height=720` |
| `mini-pong/gdscripts/constants.gd` | L15-16：`SCREEN_WIDTH=1280, SCREEN_HEIGHT=720`；L49-50：`PADDLE_WIDTH=20.0, PADDLE_HEIGHT=120.0` |
| `mini-pong/gdscripts/paddle.gd` | `_ready()` 运行时绑定 InputMap：`paddle_up`(W/↑)、`paddle_down`(S/↓)；`min_y/max_y` 夹取；AI 追踪 `ball.global_position.y` |
| `mini-pong/scripts/run-e2e-review.sh` | L216：`--resolution 1280x720` 硬编码 |
| `mini-pong/tests/` | test_constants / test_paddle / test_ai_paddle / test_ball / test_main_scene / auto_play_test 均钉横屏字面量 |

InputMap 动作不在 `project.godot` 中，而是 paddle.gd `_ready()` 运行时注册 —— 旧动作移除 = 删除 paddle.gd 中的注册代码（test_paddle 断言动作不存在）。

---

## 3. 轴交换映射总表（核心契约，implement 逐行对照）

| 语义维度 | 横屏（现状） | 竖屏（目标） |
|---------|-------------|-------------|
| 画幅 | 1280×720 | **720×1280**（resizable=false 不变） |
| 对打方向 | 左右（X 轴） | **上下（Y 轴）** |
| paddle 位置 | 左(50,360) / 右(1230,360) | **玩家底(360,1240) / AI 顶(360,40)** |
| paddle 移动轴 | Y（W/S/↑/↓） | **X（A/D/←/→）** |
| paddle 夹取 | min_y/max_y | **min_x/max_x = 60 / 660**（`PADDLE_WIDTH/2=60`，`720−60=660`） |
| AI 追踪轴 | `ball.global_position.y` | **`ball.global_position.x`**（延迟/误差/速度阈值公式不变） |
| 挡板尺寸语义 | 20 宽 × 120 长（竖置） | **120 长 × 20 厚（横置）**：`PADDLE_WIDTH=120`（横向长度）、`PADDLE_HEIGHT=20`（纵向厚度） |
| 得分边界 | X：`x<-R`→player、`x>W+R`→ai | **Y：`y<-R`→`score.emit(0)`(player 穿 AI 底线)、`y>H+R`→`score.emit(1)`(ai 穿玩家底线)** |
| 墙反弹 | 上下墙反弹 `velocity.y *= -1` | **左右墙反弹 `velocity.x *= -1`** |
| 发球 | 水平 `velocity=(cos θ·dir, sin θ)` | **垂直 `velocity=(sin θ, cos θ·dir)`**，θ ∈ ±30°，direction=±1 随机 |
| paddle 反弹 | offset 沿 Y、长度读 `shape.size.y`、方向 `-sign(velocity.x)` | **offset 沿 X、长度读 `shape.size.x`、方向 `-sign(velocity.y)`** |
| 反卡位 | `position.x += sign(velocity.x)*push_dist` | **`position.y += sign(velocity.y)*push_dist`**（沿主轴推离） |
| 双触发防护 | `_scored_this_frame` 帧级防护 | 保留（上下得分区同帧双触发防护） |
| NaN 防护 | `velocity=Vector2.RIGHT*speed` 重置 | 保留（重置方向改 `Vector2.DOWN*speed` 或保持 RIGHT，测试不依赖） |

---

## 4. 组件修改清单（implement 契约）

### 4.1 `mini-pong/project.godot`
- L25-26：`viewport_width=720, viewport_height=1280`；`resizable=false` 不变。

### 4.2 `mini-pong/gdscripts/constants.gd`
- L15-16：`SCREEN_WIDTH=720, SCREEN_HEIGHT=1280`。
- L49-50：`PADDLE_WIDTH=120.0`（横向长度）、`PADDLE_HEIGHT=20.0`（纵向厚度）。
- 头部注释：横穿时间语境更新为竖屏（如「横穿 720px / 纵穿 1280px」）。

### 4.3 `mini-pong/gdscripts/paddle.gd`
- `_ready()` InputMap：删除 `paddle_up/paddle_down` 注册（W/S/↑/↓ 全部移除）；新增 `paddle_left`（A/←）与 `paddle_right`（D/→）双绑定。
- `min_y/max_y` → `min_x/max_x`；移动 `position.x`；`FALLBACK_VIEWPORT_Y` → X 语义（或等价重命名）。
- AI：`_ai_target_y` → `_ai_target_x = ball.global_position.x + _ai_error_offset`；`dist = |position.x − _ai_target_x|`；延迟/误差/速度阈值逻辑公式不变。

### 4.4 `mini-pong/gdscripts/ball.gd`
- 得分：`y < -R` → `score.emit(0)`（player）；`y > SCREEN_HEIGHT+R` → `score.emit(1)`（ai）。
- 墙反弹：`velocity.x *= -1`（左右墙 group="walls"）。
- 发球：`velocity = Vector2(sin(θ), cos(θ)*dir) * speed`，θ ∈ ±30°，dir=±1。
- paddle 反弹：offset = `(ball.x − paddle.x) / (shape.size.x / 2)`（长度读 X）；direction = `-sign(velocity.y)`；速度递增 SPEED_INCREMENT 与上限不变。
- 反卡位：`position.y += sign(velocity.y) * push_dist`。

### 4.5 `mini-pong/scenes/player_paddle.tscn`
- CollisionShape：`Vector2(120, 20)`；ColorRect offset：±60（X）/ ±10（Y）。

### 4.6 `mini-pong/scenes/Main.tscn`（布局重摆）
| 节点 | 横屏（现状） | 竖屏（目标） |
|------|------------|------------|
| TopWall/BottomWall | 1280×10 横墙 | → **LeftWall(5,640)** shape 10×1280、**RightWall(715,640)** shape 10×1280 |
| ScoreZoneLeft/Right | 左右竖区 (1280,360) 20×720 | → **ScoreZoneTop(360,0)** shape 720×20 → `emit(0)`=player；**ScoreZoneBottom(360,1280)** shape 720×20 → `emit(1)`=ai |
| Ball | (640,360) | **(360,640)** |
| PlayerPaddle | (50,360) | **(360,1240)** |
| AIPaddle | (1230,360) mode=1 | **(360,40)** mode=1 |
| GameHUD MarginContainer | offset_right=1280 | **offset_right=720** |

### 4.7 `scripts/run-e2e-review.sh`
- L216：`--resolution 1280x720` → `--resolution 720x1280`。

### 4.8 不动文件（明确排除）
`game_state_machine.gd`、`scoring_manager.gd`（零改动或仅注释）、`game_hud.gd`、`start_menu.gd`、`game_over_screen.gd`、`pause_overlay.gd`、`ball_trail.gd`、`world_environment.tscn`、`e2e_shots.json`（analyze_bmp 动态读宽高，无需改）。

---

## 5. 测试重写契约（仅描述，不写代码）

> 物理测试按 Issue 要求重写而非删除；全部为描述性规格，implement 依此重写用例。

| 测试文件 | 重写内容 |
|---------|---------|
| `test_constants.gd` | TC6-2/3：`SCREEN_WIDTH==720`、`SCREEN_HEIGHT==1280`；PADDLE 尺寸断言随 4.2 更新 |
| `test_paddle.gd` | TC-A：绑定 A/← → `paddle_left`、D/→ → `paddle_right`；断言 `paddle_up/paddle_down` 动作不存在；TC-B/C：X 轴移动 + 夹取 `min_x=60/max_x=660`（含启动夹取） |
| `test_ai_paddle.gd` | 全部改为 X 追踪断言：目标 = `ball.global_position.x`，误差/延迟/速度阈值公式不变 |
| `test_ball.gd` | TC-B：墙反弹改 X 分量反转；TC-C：得分改 Y 出界（`y<-R`→player、`y>1280+R`→ai）；TC-D：发球垂直（散布 ±30° 沿 X，不钉具体方向）；TC-E：paddle 反弹读 `shape.size.x`、长度 120 时 offset 归一化正确；反卡位沿 Y |
| `test_main_scene.gd` | TC5/TC14：得分区坐标改上下（ScoreZoneTop(360,0)/ScoreZoneBottom(360,1280)）、720 宽；墙/挡板/球坐标按 4.6 |
| `auto_play_test.gd` | `SCREEN_W=720 / SCREEN_H=1280`；A/D 输入语义 |
| `test_integration_fsm.gd` | **不动**（无坐标钉）；同时作为「FSM/scoring 零改动」的回归证据 |

---

## 6. 边界条件与失败路径（implement 必须遵守）

1. **发球方向随机**：direction=±1 沿 Y、30° 散布沿 X —— 测试钉散布范围，不钉具体方向。
2. **挡板反弹读长度**：漏改 `shape.size.y`→`size.x` 时 offset 用 20 而非 120，反弹角度失真 —— 测试钉「长度=120 时 offset 归一化正确」。
3. **双触发防护**：`_scored_this_frame` 帧级防护保留，测试覆盖同帧双区触发。
4. **反卡位方向**：必须沿 Y（`position.y += sign(velocity.y)*push_dist`），防球卡进挡板。
5. **NaN 防护**：竖屏归一化后仍走重置路径，重置方向与测试解耦。
6. **HUD 宽度**：漏改 offset_right=720 会溢出右侧 —— E2E 截图断言覆盖。
7. **旧输入残留**：`paddle_up/paddle_down` 必须从 paddle.gd 删除（不是只加不删）—— 测试断言动作不存在。
8. **得分区接线反**：ScoreZoneTop→emit(0)=player、ScoreZoneBottom→emit(1)=ai 接反则得分方颠倒 —— test_scoring_manager + test_integration_fsm 回归断言「球穿顶=player 得分」。

---

## 7. 验收标准映射（Issue #383 AC）

| AC | 验收标准 | 设计覆盖 |
|----|---------|---------|
| AC1 | 720x1280 竖屏正常运行 | 4.1 project.godot + headless 编译 + E2E 截图 720×1280 断言 |
| AC2 | 玩家 paddle y=1240、AI y=40，x 移动范围 [60,660] | 4.6 坐标 + 4.3 min_x/max_x + test_paddle 夹取 |
| AC3 | A/D 控制、AI 沿 X 追踪、Y 输入无效 | 4.3 输入/AI + test_paddle/test_ai_paddle 动作不存在断言 |
| AC4 | 垂直发球、Y 出界得分、X 反弹 | 4.4 + test_ball 重写 |
| AC5 | run-e2e-review.sh 720x1280 + 物理测试全过、FSM/scoring 不变 | 4.7 + §5 重写 + 零改动清单 |

---

## 8. 验证步骤（implement 执行顺序）

1. `constants.gd`（SCREEN + PADDLE 语义）→ 2. `project.godot`（viewport）→ 3. `paddle.gd`（输入/移动/AI 轴）→ 4. `ball.gd`（得分/反弹/发球）→ 5. `player_paddle.tscn` + `Main.tscn`（布局/得分区/墙/HUD）→ 6. `run-e2e-review.sh` → 7. 测试重写（test_constants → test_paddle → test_ai_paddle → test_ball → test_main_scene → auto_play_test）→ 8. 本地验证：
   - `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿
   - `scripts/run-e2e-review.sh --resolution 720x1280` L0-L3 全过、截图尺寸 720×1280
   - `game_state_machine.gd` / `scoring_manager.gd` git diff 为空（或仅注释）

---

## 9. 不做的事（明确排除）

- ❌ 不做根节点旋转（Approach B）—— 输入/UI/测试全打架，与「坐标只改一遍」冲突
- ❌ 不做 `PORTRAIT` 双模式开关（Approach C）—— 后续所有 feature 双写成本摊销
- ❌ 不改手感数值（#367 定稿 11 参数）与 FSM/scoring 信号链
- ❌ 不引入任何第三方资产（开源优先调研结论：无可复用插件/模板，纯第一方重构）
- ❌ 不写 runnable 测试文件于本 PR（测试重写归 implement PR）

# PRD: [Refactor] 轴交换 + 竖屏 (P0 前置)

> **Issue:** #383
> **标签:** enhancement, gameplay, testing, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 跳过）
> **所有权:** `content_ownership: mechanical`（纯机械改造：坐标轴交换 + 画幅竖屏，无 taste 内容）
> **上游方案:** `docs/PLAN-rogue-pong.md` §4.1（2026-08-13 用户拍板「轴交换 + 竖屏同批做，坐标只改一遍」）— 本 PRD 是该方案 P0 前置 Issue 的研究落地

---

## 1. 问题定义

### 当前状态

Mini Pong 当前是 **1280×720 横屏**：球沿 X 轴横向飞行、左右出界得分；paddle 沿 Y 轴移动（W/S/↑/↓）；AI 追踪球 Y；挡板竖置（20 宽 × 120 高）左右分列；上下墙反弹 X 分量。整个坐标系以「横向对打」为语义中心。

| 文件 | 当前状态（横屏语义） | 与竖屏需求的差距 |
|------|---------------------|----------------|
| `mini-pong/project.godot` | `viewport_width=1280, viewport_height=720` | ❌ 需 720×1280 |
| `mini-pong/gdscripts/constants.gd` | `SCREEN_WIDTH=1280, SCREEN_HEIGHT=720`；`PADDLE_WIDTH=20`（厚度）、`PADDLE_HEIGHT=120`（长度） | ❌ 需 720/1280；挡板尺寸语义需翻转（长度变横向=width） |
| `mini-pong/gdscripts/paddle.gd` | 移动 `position.y`；边界 `min_y/max_y`；输入 `paddle_up/paddle_down`（W/S/↑/↓）；AI 追踪 `ball.global_position.y` | ❌ 全部改 X 轴 |
| `mini-pong/gdscripts/ball.gd` | 得分 X 边界（`position.x < -R` → `score.emit(1)`，`> W+R` → `score.emit(0)`）；墙反弹 Y 分量（`velocity.y *= -1`）；发球水平（`velocity=(cos θ·dir, sin θ)`）；paddle 反弹读 `shape.size.y` 为长度、offset 沿 Y | ❌ 得分改 Y 边界、墙反弹改 X 分量、发球垂直、反弹读 `size.x`、offset 沿 X |
| `mini-pong/scenes/Main.tscn` | TopWall/BottomWall（1280×10 横墙）；ScoreZoneLeft(0,360)/Right(1280,360)（20×720 竖区）；Ball(640,360)；PlayerPaddle(50,360)/AIPaddle(1230,360)；GameHUD MarginContainer `offset_right=1280` | ❌ 墙左右、得分区上下、挡板 y=1240/40、HUD 宽度 |
| `mini-pong/scenes/player_paddle.tscn` | CollisionShape `Vector2(20,120)`，ColorRect offset ±10/±60 | ❌ 需横置 `Vector2(120,20)`，offset ±60/±10 |
| `scripts/run-e2e-review.sh` | L216 `--resolution 1280x720` 硬编码 | ❌ 需 `--resolution 720x1280` |
| `mini-pong/tests/*.gd` | test_constants 钉 1280/720；test_paddle/test_ai_paddle 全 Y 轴；test_ball 得分 X/墙反弹 Y；test_main_scene 钉得分区坐标；auto_play_test.gd 钉 `SCREEN_W=1280/SCREEN_H=720` | ❌ 物理测试大量重写（Issue 验收条件明确要求） |
| `mini-pong/gdscripts/game_state_machine.gd` | 6 态 FSM（MENU/SERVING/PLAYING/PAUSED/SCORED/GAME_OVER） | ✅ 布局无关，几乎不动 |
| `mini-pong/gdscripts/scoring_manager.gd` | `side 0→player / side 1→ai` 信号链 | ✅ 不动（信号链不变，仅得分区接线换位置） |
| `mini-pong/e2e_shots.json` | state_node/autoplay 均引用 `/root/Game/...` 节点路径 | ✅ 无需改（analyze_bmp 动态读宽高） |
| `mini-pong/gdscripts/game_hud.gd` / `start_menu.gd` / `game_over_screen.gd` / `pause_overlay.gd` / `ball_trail.gd` / `world_environment.tscn` | anchor/铺满式布局或自包含 | ✅ 不动（VersionLabel 等 anchor 自适应） |

### 预期行为（验收条件，源自 Issue #383）

1. **项目以 720x1280 竖屏模式正常运行** — `project.godot` viewport 720×1280，`resizable=false` 不变，Godot 4.7.1 headless 测试与真实渲染截图均通过
2. **玩家 paddle 位于 y=1240、AI paddle 位于 y=40，且 x 轴移动范围正确** — x ∈ [60, 660]（`min_x = PADDLE_WIDTH/2 = 60`，`max_x = 720 − 60 = 660`）
3. **A/D 控制玩家 paddle，AI 沿 X 轴追踪球；Y 轴输入不再影响 paddle** — `paddle_left`(A/←) / `paddle_right`(D/→) 替代 `paddle_up/paddle_down`；旧 W/S/↑/↓ 绑定移除
4. **球从底部/顶部垂直发球，Y 方向出界触发得分，X 方向继续反弹** — 发球主轴向 Y（`velocity=(sin θ, cos θ·dir)`）；`y < -R` → 玩家得分（穿过 AI 底线）、`y > 1280+R` → AI 得分（穿过玩家底线）；左右墙反弹 `velocity.x *= -1`
5. **run-e2e-review.sh --resolution 720x1280 与物理测试全部通过，FSM/scoring 行为不变** — 全测试套件绿 + E2E L0-L3 全过；`game_state_machine.gd` / `scoring_manager.gd` 零改动或仅注释

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家开局 | 每次启动 | 竖屏 720×1280，paddle 在底部（玩家）与顶部（AI），球垂直对打，攻防纵深 1280px |
| B | Rogue Pong 后续砖墙/雨幕/HUD | P0 之后每个 feature | 竖屏坐标系作为一切后续系统的地基（砖墙横跨 720px、雨幕垂直下落与攻击同轴） |
| C | 本地 E2E 验证 | 每个实现 PR | `run-e2e-review.sh --resolution 720x1280` 截图/断言在竖屏下成立 |

### 技术约束（继承自 Issue #383 + PLAN-rogue-pong §4.1）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`） |
| 画幅 | 720×1280 竖屏（9:16），`resizable=false` |
| 语义映射 | 得分轴 X→Y（左右出界→上下出界）；发球水平→垂直；paddle 移动轴 Y→X；AI 追踪 Y→X；挡板尺寸语义 PADDLE_HEIGHT→PADDLE_WIDTH（120 长变横向） |
| 输入 | A/D（+ ←/→ 双绑定，与现有 W/S 双绑定惯例一致） |
| 不变项 | FSM 与 scoring 流程保持不变；`content_ownership: mechanical`（无 taste 决策） |
| 一次改完 | PLAN-rogue-pong §4.1 已确认「坐标只改一遍」— 不引入双模式开关 |
| 开源优先 | 调研结果见下（§1.4） |

### 1.4 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索）：

- **Godot Asset Library**（assetlibrary.godotengine.org, godot 4.x 排序）：无「竖屏 Pong / 垂直 Breakout」可复用模板；最新返回均为无关工具/绘图类资产
- **GitHub 搜索**（GDScript 语言过滤，按 star 排序）：`godot pong` 1037 仓库（最高 Calinou/escape-space 46⭐，俯视混 Pong/Breakout/pinball）；`godot breakout` 235 仓库（didier-v/breakable 64⭐）；`godot portrait 2d` 仅 1 个 0⭐ demo（futbolrush）
- **结论**：全部是独立完整游戏/克隆，**没有「横屏→竖屏轴交换」的可插拔插件/模板**；本改造是纯第一方代码重构，Godot 4.7 内置能力（`project.godot` viewport 尺寸、InputMap 动作、Area2D 物理）完全覆盖，**不引入任何第三方资产**。后续砖墙/雨幕等涉及资产的 Issue 按各自 body 的开源优先要求另行调研。

---

## 2. 设计意图

### 为什么当前状态存在

横屏 1280×720 是 Mini Pong 从 #287（球物理）、#288（玩家挡板）、#290（AI 对手）、#295（Main.tscn 组装）一路继承的初始布局：经典 Pong 语义 = 左右对打，挡板竖置。`constants.gd` 的 SCREEN 常量被 ball/paddle/scoring/game_manager 引用（#295 非破坏性迁移后单一事实源）；测试套件（#287/#288/#290/#295 产出）围绕横屏语义钉了大量字面量。

| 现状来源 | Issue | 贡献 |
|---------|-------|------|
| 球物理（X 得分/Y 墙反弹/水平发球） | #287 | `ball.gd` 当前实现 |
| 玩家挡板（Y 移动/W·S/↑·↓） | #288 | `paddle.gd` Mode.PLAYER 分支 |
| AI 对手（Y 追踪/反应延迟/误差） | #290 | `paddle.gd` Mode.AI 分支 + test_ai_paddle |
| Main.tscn 组装（横墙/左右得分区/挡板坐标） | #295 | 场景布局 |
| 手感定稿（11 参数：速度/反弹角/AI 强度） | #367 | 数值层（**轴交换不改变数值**，只改方向语义） |
| 版本号/标题画面 | #358 | 布局 anchor 自适应，不受影响 |

### 为什么现在改

1. **P0 前置已拍板**：Rogue Pong 攻城战肉鸽方案（`docs/PLAN-rogue-pong.md`，2026-08-13 用户确认）把「轴交换 + 竖屏」列为 **P0 独立先行**——垂直攻防主运动轴是 Y，横屏只给 720px 纵深；竖屏 720×1280 让砖墙横跨 720px、攻防纵深 1280px，「打上去翻过墙」的物理叙事才成立；雨幕垂直下落与攻击方向同轴。
2. **坐标只改一遍**：砖墙、雨幕、HUD 双得分区等后续系统全部依赖竖屏坐标；先改坐标轴，后续 feature 直接建立在竖屏上，避免横屏→竖屏二次迁移。
3. **成本窗口**：当前功能面收敛（无砖墙/雨幕/升级），改动面 = 坐标系 + 测试，FSM/scoring 信号链不动，是迁移成本最低的时刻。

### 先前约束

| 约束 | 细节 |
|------|------|
| 手感数值（#367 定稿） | BALL_INITIAL_SPEED=330、PADDLE_SPEED=430、AI 三参数等 **不因轴交换改变**；球速注释中「横穿时间 1280px」等文案需同步为竖屏语境 |
| 信号链（#295/#291） | `ball.score(side)` → `ScoringManager._on_ball_score` → `scored/game_won/match_over` 保持不变；`side 0=player / 1=ai` 语义保留 |
| FSM（#294/#296） | 6 态机布局无关，`game_state_machine.gd` 不改 |
| 测试即验收 | 物理测试按 Issue 要求「重写」而非删除；`test_integration_fsm.gd` 无坐标钉可不动 |

---

## 3. 影响分析

### 直接改动文件

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/project.godot` | 画幅 | `viewport_width=720, viewport_height=1280`（resizable=false 不变） |
| `mini-pong/gdscripts/constants.gd` | 常量 | `SCREEN_WIDTH=720, SCREEN_HEIGHT=1280`；`PADDLE_WIDTH=120`（横向长度）、`PADDLE_HEIGHT=20`（纵向厚度）；球速注释横穿语境更新 |
| `mini-pong/gdscripts/paddle.gd` | 输入/移动/AI | InputMap：`paddle_up/paddle_down` → `paddle_left/paddle_right`（A/←、D/→）；`min_y/max_y` → `min_x/max_x`；移动 `position.x`；AI `_ai_target_x = ball.global_position.x + error`，`dist = |position.x − _ai_target_x|` |
| `mini-pong/gdscripts/ball.gd` | 物理/得分/发球 | 得分 Y 边界（`y < -R` → `score.emit(0)` 玩家得分；`y > H+R` → `score.emit(1)` AI 得分）；墙反弹 X 分量（`velocity.x *= -1`）；发球垂直（`velocity = (sin θ, cos θ·dir) * speed`）；paddle 反弹 offset 沿 X、长度读 `shape.size.x`、方向翻转 `-sign(velocity.y)`；反卡位 `position.y += sign(velocity.y) * push_dist` |
| `mini-pong/scenes/Main.tscn` | 场景布局 | 墙：TopWall→LeftWall(5,640)/shape 10×1280、BottomWall→RightWall(715,640)；得分区：ScoreZoneLeft→ScoreZoneTop(360,0)/shape 720×20→emit(0)、ScoreZoneRight→ScoreZoneBottom(360,1280)/shape 720×20→emit(1)；Ball(360,640)；PlayerPaddle(360,1240)；AIPaddle(360,40) mode=1；GameHUD MarginContainer `offset_right=1280→720` |
| `mini-pong/scenes/player_paddle.tscn` | 挡板视觉/碰撞 | CollisionShape `Vector2(120,20)`；ColorRect offset ±60/±10 |
| `scripts/run-e2e-review.sh` | E2E | L216 `--resolution 1280x720` → `--resolution 720x1280` |

### 新文件

无新增运行时文件。测试按需重写现有用例（见下）。

### 间接影响（需回归验证）

| 文件 | 影响 | 处理 |
|------|------|------|
| `mini-pong/tests/test_paddle.gd` | TC-A（绑定 W/S/↑/↓）、TC-B/C（Y 移动/夹取）全失效 | 重写为 A/D + X 轴语义 |
| `mini-pong/tests/test_ai_paddle.gd` | 全部 Y 追踪断言失效 | 重写为 X 追踪（公式不变：误差/延迟/速度阈值逻辑保留） |
| `mini-pong/tests/test_ball.gd` | TC-B 墙反弹（Y 反转）、TC-C 得分（X 出界）、TC-D 发球（水平）、TC-E paddle 反弹（读 size.y）失效 | 重写为 X 墙反弹 / Y 得分 / 垂直发球 / 读 size.x |
| `mini-pong/tests/test_constants.gd` | TC6-2/3 钉 `SCREEN_WIDTH==1280 / SCREEN_HEIGHT==720` | 更新为 720/1280 |
| `mini-pong/tests/test_main_scene.gd` | TC5/TC14 钉得分区 (1280,360)/720 高 | 更新为上下得分区坐标/720 宽 |
| `mini-pong/tests/auto_play_test.gd` | `SCREEN_W=1280/SCREEN_H=720` | 更新为 720/1280 |
| `mini-pong/tests/test_integration_fsm.gd` | 无坐标钉（已验证） | 不动 |
| `mini-pong/e2e_shots.json` | 节点路径引用，无分辨率钉 | 不动（analyze_bmp 动态读宽高） |

### 数据流影响

```
球飞行（竖屏）:
    position += velocity * delta
        │
        ├── 左右墙（LeftWall/RightWall, groups=["walls"]）→ velocity.x *= -1   ← 反弹
        ├── 上下得分区（ScoreZoneTop/Bottom, Area2D）:
        │       y < 0        → score.emit(0) → ScoringManager → winner="player"  ← 穿过 AI 底线
        │       y > 1280+R   → score.emit(1) → ScoringManager → winner="ai"      ← 穿过玩家底线
        │                        └─ scored(winner) → GameHUD / ScoreFlash（信号链不变 ✅）
        └── paddle 反弹（player 底 y=1240 / AI 顶 y=40）:
                offset = (ball.x − paddle.x) / (shape.size.x / 2)   ← 长度改读 X
                direction = −sign(velocity.y)                       ← 翻转主轴
                velocity = (sin θ, cos θ·dir) * speed               ← 垂直反弹
                speed *= SPEED_INCREMENT（上限不变，手感数值不变）

FSM / Scoring 流程: 零改动（仅得分区节点换位与 emit 参数接线）
```

### 文档更新

- [ ] `docs/PLAN-rogue-pong.md` — 已含 §4.1 前置改造表（实现后无需改）
- [ ] `docs/GAME_DESIGN/` — 无 1280×720 硬编码（已 grep 验证）；实现 PR merge 后由 review agent 按 GDD 维护规则增量更新
- [ ] `mini-pong/gdscripts/constants.gd` 头部注释 — 横穿时间语境（1280px→720px/1280px）随实现更新
- [ ] 本 PRD merge 后自动推进 Issue #383 → `workflow/plan`（workflow-chain）

---

## 4. 方案对比

### Approach A：坐标轴交换直改（PLAN-rogue-pong §4.1 已确认）

按 §3 表格逐文件交换轴语义：viewport/常量翻转为竖屏，paddle/ball 逻辑轴对调，场景重摆，测试按新语义重写。

- **Pros**：一次性到位，「坐标只改一遍」；无运行时开销；语义最干净——后续砖墙/雨幕直接建在竖屏坐标系上；与已确认方案零偏差
- **Cons**：物理测试重写工作量集中在本 Issue；改完即不可逆（横屏能力丢弃，但 Rogue Pong 方向已确认不再需要）
- **Risk**：Low — 纯机械映射，风险集中在测试重写遗漏；信号链/数值层不动
- **Effort**：0.5–1 周

### Approach B：根节点旋转（CanvasItem transform 90°）

保持代码横屏逻辑，把整个场景节点旋转 90°、视口强制 720×1280。

- **Pros**：代码改动最小（场景根节点 transform）
- **Cons**：输入轴需二次映射（W/S 视觉上仍是 Y）；文字/UI 全部横躺（标题、HUD、暂停/结束屏）；得分/反弹逻辑仍按横屏坐标，球"出界"判断与视觉不符；E2E 截图断言坐标混乱；后续砖墙逻辑在旋转坐标系上实现 = 灾难。**与「坐标只改一遍」决策直接冲突**
- **Risk**：High（视觉/输入/测试全面打架）
- **Effort**：看似小，实际反复修补无底洞

### Approach C：双模式参数化（`PORTRAIT: bool` 开关）

constants 加 `IS_PORTRAIT`，运行时按开关分支。

- **Pros**：横竖屏可切换，回退容易
- **Cons**：每处坐标逻辑 ×2 代码路径与 ×2 测试矩阵；后续砖墙/雨幕/升级全部要双写；已确认方案明确「不引入双模式」；维护成本长期累积
- **Risk**：Med（死代码 + 测试膨胀）
- **Effort**：1–1.5 周（双倍）

### 推荐

**Approach A**。理由：(1) 方案已由用户拍板（PLAN-rogue-pong §4.1「坐标只改一遍」，独立 PR、测试全绿）；(2) 竖屏是 Rogue Pong 一切后续系统的地基，不存在回退需求；(3) B 的旋转技巧与竖屏语义（攻防纵深、雨幕同轴）相悖，C 的双写成本由后续所有 Issue 摊销，均不可取。本 PRD §3/§5/§8 的映射表即 Approach A 的落地方案。

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body）

- [x] **AC1: 项目以 720x1280 竖屏模式正常运行** — `project.godot` viewport 720×1280；`godot --headless` 编译通过；真实渲染截图尺寸为 720×1280（analyze_bmp 断言）
- [x] **AC2: 玩家 paddle 位于 y=1240、AI paddle 位于 y=40，x 轴移动范围正确** — Main.tscn 坐标 + `min_x=60/max_x=660`（720−60）；夹取测试覆盖两端与启动夹取
- [x] **AC3: A/D 控制玩家 paddle，AI 沿 X 轴追踪球；Y 轴输入不再影响 paddle** — `paddle_left`(A/←)/`paddle_right`(D/→) 绑定断言；`paddle_up/down` 动作不存在；AI 追踪 `ball.global_position.x`
- [x] **AC4: 球从底部/顶部垂直发球，Y 方向出界触发得分，X 方向继续反弹** — 发球 `velocity=(sin θ, cos θ·dir)`；`y<0`→player 得分、`y>1280+R`→AI 得分；左右墙反弹 `velocity.x *= -1`
- [x] **AC5: run-e2e-review.sh --resolution 720x1280 与物理测试全部通过，FSM/scoring 行为不变** — 全套 `run_tests.gd` 绿；E2E L0–L3 过；`game_state_machine.gd`/`scoring_manager.gd` 零改动

### 边界情况（Edge Cases）

1. **发球方向随机**：竖屏下 `direction = ±1` 沿 Y，`SERVE_ANGLE_RANGE=30°` 散布沿 X——头球模式与测试需在竖屏坐标系断言（不钉具体方向，钉散布范围）
2. **挡板反弹读长度**：`ball.gd` 从 `shape.size.x` 读长度（原 `size.y`）；若实现时漏改，offset 将用 20 而非 120，反弹角度失真——测试钉「长度=120 时 offset 归一化正确」
3. **双触发防护**：竖屏得分区上下重叠检测（`_scored_this_frame` 帧级防护）保留；测试覆盖同帧双区触发
4. **反卡位方向**：paddle 反弹后 `position.y += sign(velocity.y) * push_dist`（原 X）——竖屏下必须沿 Y 推离，防球卡进挡板
5. **NaN 防护**：竖屏下 `velocity=(sin θ, cos θ·dir)` 归一化后仍走 NaN 重置路径（`velocity=Vector2.RIGHT*speed` 需改为竖屏默认方向 `Vector2.DOWN*speed` 或保持 RIGHT 均可，测试不依赖）
6. **HUD 宽度**：GameHUD MarginContainer `offset_right=1280→720`，漏改会导致 HUD 溢出右侧——E2E 截图断言覆盖
7. **旧输入残留**：`InputMap` 运行期绑定若只加不删，W/S/↑/↓ 仍在——必须移除 `paddle_up/paddle_down` 动作（测试断言动作不存在）

### 失败路径（Failure Paths）

1. **测试重写遗漏**：某测试仍按横屏语义钉坐标 → `run_tests.gd` 红 → 实现 PR 被 CI 拦截；兜底：本 PRD §3 间接影响表逐文件核对
2. **E2E 分辨率参数漏改**：`run-e2e-review.sh` L216 仍传 1280x720 → 截图 1280×720 与项目实际 720×1280 不符 → P5 断言失败；兜底：实现 PR 必须跑 `--resolution 720x1280` 并核对截图尺寸
3. **信号链接线错位**：ScoreZoneTop/Bottom emit 参数与 scoring_manager side 语义（0=player/1=ai）接反 → 得分方颠倒；兜底：test_scoring_manager + test_integration_fsm 回归断言「球穿顶=player 得分」

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| `docs/PLAN-rogue-pong.md` §4.1（轴交换+竖屏方案） | ✅ 已确认（2026-08-13 用户拍板） | Low |
| 现有横屏代码基线（#287/#288/#290/#295/#367 产物） | ✅ main 上完整可用 | Low |
| #367 手感数值定稿 | ✅ 已定稿（TASTE.md v1） | Low — 轴交换不改数值 |

> 本 Issue **无 Depends On 阻塞**（独立先行，不依赖砖墙/雨幕/升级池）。

### 阻塞（Blocks）

| 后续工作 | 优先级 | 说明 |
|---------|:---:|------|
| Rogue Pong MVP：砖墙系统 + 双得分制 + 波次循环 + 3选1 UI + 动态雨幕 | P0 | 全部建立在竖屏坐标系上（砖墙横跨 720px、雨幕垂直下落同轴） |
| 后续所有竖屏 feature（HUD 双得分区、波次转场、失败屏） | P0/P1 | 依赖 #383 的竖屏布局 |

### 依赖链

```
PLAN-rogue-pong.md (2026-08-13 拍板)
        │
        ▼
Issue #383 轴交换+竖屏 (P0 前置) ← 本 PRD
        │
        ├──► MVP 砖墙/双得分/波次/升级/雨幕
        └──► v1/v2 (分裂球/城市天际线/meta)
```

---

## 7. Spike / 实验

**Skipped per depth/standard label**（Issue 无 `depth/deep` 标签；#358/#378 惯例按 standard 处理，Section 7 非必填）。

轴交换为确定性机械映射（§3/§5 已给出逐文件改动与断言），无技术不确定点需要 spike；最大风险（测试重写遗漏）已通过 §3 间接影响表 + §5 失败路径兜底覆盖。

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #383 当前 `workflow/research`，本 PRD merge 后 workflow-chain 自动推进 → `workflow/plan`
- 基线：`main` HEAD = `895691b`（plan: 14 issues 全部注入开源优先调研说明）；横屏代码完整可跑（headless 测试绿）
- 上游方案已确认：`docs/PLAN-rogue-pong.md` §4.1（文件级改动表，本 PRD 已细化为行级映射）

### 关键决策（plan agent 必须继承）

1. **Approach A 坐标轴交换直改**，不做旋转技巧、不做双模式开关（§4）
2. **挡板横置 120×20**：`PADDLE_WIDTH=120`（横向长度）、`PADDLE_HEIGHT=20`（纵向厚度）；`player_paddle.tscn` shape `Vector2(120,20)`、ColorRect offset ±60/±10；`ball.gd` 反弹长度读 `shape.size.x`
3. **得分区接线**：ScoreZoneTop(360,0) → `emit(0)`=player 得分；ScoreZoneBottom(360,1280) → `emit(1)`=ai 得分（保持 scoring_manager `side 0=player/1=ai` 不动）
4. **输入**：`paddle_left`(A/←)、`paddle_right`(D/→) 替代 `paddle_up/paddle_down`（W/S/↑/↓ 移除）；AI 追踪 X 轴，公式（延迟/误差/速度阈值）不变
5. **发球垂直**：`velocity=(sin θ, cos θ·dir)*speed`，θ ∈ ±30°；`direction=±1` 随机
6. **FSM/scoring 零改动**；`game_hud.gd`/`start_menu.gd`/`game_over_screen.gd`/`pause_overlay.gd`/`ball_trail.gd`/`world_environment.tscn` 不动；`e2e_shots.json` 不动
7. **e2e 脚本**：`run-e2e-review.sh` L216 `--resolution 720x1280`；实现 PR 必须真实跑 E2E 验证截图尺寸

### 实现顺序建议（plan agent 参考）

1. `constants.gd`（SCREEN + PADDLE 语义）→ 2. `project.godot`（viewport）→ 3. `paddle.gd`（输入/移动/AI 轴）→ 4. `ball.gd`（得分/反弹/发球）→ 5. `player_paddle.tscn` + `Main.tscn`（布局/得分区/墙/HUD）→ 6. `run-e2e-review.sh` → 7. 测试重写（test_constants → test_paddle → test_ai_paddle → test_ball → test_main_scene → auto_play_test）→ 8. 本地 headless 全绿 + E2E 实弹截图

### 主要风险

- 测试重写遗漏（§3 间接影响表逐文件核对）
- 得分区 emit 接反（§5 失败路径 3）
- 旧输入动作残留（§5 边界 7）

### 交接清单

- [ ] 本 PRD 文件 `docs/PRD/383-axis-swap-portrait.md`
- [ ] 上游方案 `docs/PLAN-rogue-pong.md` §4.1
- [ ] 实测基线：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 当前全绿（实现前可复跑对照）

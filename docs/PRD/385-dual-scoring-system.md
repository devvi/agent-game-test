# PRD: [Feature] 双得分制

> **Issue:** #385
> **标签:** enhancement, gameplay, version/mvp, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验补齐）
> **所有权:** `content_ownership: mechanical`（计分状态/规则/信号为纯机械实现；分值 21/3/1 已由 PLAN-rogue-pong 用户拍板，无 taste 决策）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.2 双得分制（已确认）+ §2.4 21 分制胜负判定（已确认，2026-08-13 用户拍板）
> **前置依赖:** #383（轴交换+竖屏，**已关闭**，PR #409 已合并）→ #384（砖墙系统，PRD #411 + DESIGN #414 已合并，**实现未落地**）→ 本 Issue 消费 #384 定义的 `brick_destroyed` 信号契约

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）目前只有**单一得分制**：球从上/下出界（`ball.score(side)`）→ `ScoringManager` +1 分 → 先到 5 分赢一局、先赢 2 局赢比赛（#291/#293/#295 体系）。**不存在**拆砖分、穿墙分、最后触球者概念，也没有 21 分终局判定。Rogue Pong 的双得分制（PLAN-rogue-pong §2.2）完全缺失。

| 文件 | 当前状态 | 与 #385 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/constants.gd` | `POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2`（#295 单一事实源） | ❌ 无双得分常量：`BRICK_SCORE=1`、`PIERCE_SCORE=3`、`WIN_SCORE=21`；5 分/2 局制与 21 分制冲突 |
| `mini-pong/gdscripts/game_manager.gd` | autoload 全局状态：`player_score/ai_score`、`add_score(winner)`（固定 +1）、`score_changed/game_won/match_over` 信号、`get_winner()`（按局数） | ❌ 无拆砖数/穿墙数状态与查询接口（AC5）；终局判定是 5 分制游戏+2 局制比赛，非 21 分终局（AC3）；`add_score` 无分值/类型参数 |
| `mini-pong/gdscripts/scoring_manager.gd` | 场景侧消费 `ball.score(side)`（side 0=player 顶部出界、1=ai 底部出界）→ `scored` 信号 + `GameManager.add_score`；`get_node_or_null` 容错模式（ScoreFlash） | ❌ 未消费 `BreakoutGrid.brick_destroyed`（拆砖分）；出界分固定 1 分，无穿墙 3 分判定 |
| `mini-pong/gdscripts/ball.gd` | `score(side)` 信号 + `_scored_this_frame` 帧守卫（#295）；`_on_body_entered` walls 分支（X 反弹）、`_on_area_entered` paddles 分支（角度反弹） | ❌ 无最后触球者追踪（AC1 归属依据）；无墙带穿越标记（穿墙判定）；#384 将新增 bricks 分支（球碰砖 → 砖碎+反弹），本 Issue 在其上叠加归属/穿越状态 |
| `mini-pong/gdscripts/paddle.gd` | 双挡板均 `add_to_group("paddles")`，**无 player/ai 区分** | ❌ 最后触球者无法从 group 区分，需按节点名或新增 group |
| `mini-pong/gdscripts/game_hud.gd` | 消费 `GameManager.score_changed` → 显示 "Player: X" / "AI: X" | ⚠️ AC1「拆砖后更新 HUD」：总分联动已具备；拆砖/穿墙双区细分 UI 归 #390/#392/#393（本 Issue 只保证信号链覆盖） |
| `mini-pong/gdscripts/game_state_machine.gd` | FSM：MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER；`scored` → SCORED 暂停 1s；`match_over` → GAME_OVER；SCORED 内 `get_winner()` 判局 | ⚠️ 21 分制下「局」概念消亡：SCORED 后的判定逻辑需改为直达 GAME_OVER（AC3） |
| `mini-pong/gdscripts/game_over_screen.gd` | 消费 `GameManager.match_over` → "YOU WIN!/AI WINS!" | ⚠️ 结算数据（拆砖/穿墙数）读取路径待接（AC5；视觉布局归 #391 失败屏） |
| `mini-pong/tests/test_game_manager.gd` | TC6 断言 5 次 `add_score` → 游戏赢 | ❌ 5 分制断言与 21 分制冲突，需同步更新 |
| `mini-pong/tests/test_scoring_manager.gd` | 常量 5/2，TC3/TC4 断言 5 分赢局、2 局赢比赛 | ❌ 同上，需同步更新 |
| `mini-pong/tests/run_tests.gd` | 注册 14 个测试套件 | ❌ 无双得分测试 |

**#384 实现状态事实核查（依赖边界的关键依据）：**

- #384 的 PRD（#411）与 DESIGN（#414）均已合并，**但实现未落地**：`git ls-tree origin/main mini-pong/gdscripts/` 中**不存在** `breakout_grid.gd` / `brick.gd`，`mini-pong/scenes/` 无 `brick.tscn` / `breakout_grid.tscn`；`plan/384-breakout-grid` 分支只有 DESIGN 文档提交。
- #384 DESIGN 定义的信号契约（供本 Issue 消费）：`brick_destroyed(brick: Node2D, pos: Vector2)` —— 每块砖销毁时发一次（拆砖分归属最后触球方）；`wall_cleared()` —— 归 #386 波次重置，本 Issue 不消费。
- **影响**：本 Issue 的拆砖分消费方必须以 `get_node_or_null` 容错引用 BreakoutGrid（同 ScoringManager 对 ScoreFlash 的既有模式），#384 实现落地 + #393 接线后自动生效；在此之前用隔离测试验证拆砖分逻辑（直接实例化 BreakoutGrid 脚本）。

### 预期行为（验收条件，源自 Issue #385）

1. **AC1 — 拆掉一块砖给最后触球方 +1 分，并更新 HUD** — 消费 `brick_destroyed` → 读 `ball.last_toucher` → `GameManager.add_score(toucher, 1, "brick")` → `score_changed` 信号 → HUD 总分联动
2. **AC2 — 球未被接住从上/下出界且穿越砖墙时，给得分方 +3 分** — ball 追踪墙带穿越标记；出界时若已穿越墙带 → 出界分 3（穿墙分），否则 1（普通出界兜底）
3. **AC3 — 任意一方达到 21 分时 GameManager 进入终局状态** — `WIN_SCORE=21` 终局判定 → `match_over` 信号 → FSM GAME_OVER（取代 5 分/2 局制）
4. **AC4 — 同一帧的拆砖/穿墙不会重复计分** — 复用 #295 `_scored_this_frame` 帧守卫模式：同帧砖碎事件与出界事件互斥计分
5. **AC5 — GameManager 可查询每方拆砖数、穿墙数，供结算/失败屏使用** — `get_brick_count(side)` / `get_pierce_count(side)`（或统一 `get_run_stats()`）查询 API

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 拆砖得分 | 每 rally 多次 | 玩家（底）把球打向砖墙，碰砖 → 砖碎 + 反弹 → 最后触球方（玩家）+1 分，HUD 总分更新 |
| B | 穿洞得分 | 每局多次 | 球穿过墙洞（无砖路径）直达 AI 底线未被接住 → 攻击方（玩家）+3 分（PLAN §2.2 穿墙分语义） |
| C | 打穿推进 | 每局多次 | 球先拆数砖（各 +1）后穿越墙带出界（另一帧）→ 拆砖分 + 穿墙分都计入（PLAN §2.4） |
| D | 21 分终局 | 每 run 一次 | 任意一方总分（拆砖+穿墙）先到 21 → GameManager 终局 → FSM GAME_OVER → 结算屏读取拆砖/穿墙统计 |

### 技术约束（继承自 Issue #385 + PLAN-rogue-pong + #384 契约）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，720×1280 竖屏，resizable=false） |
| 信号契约 | 消费 #384 的 `brick_destroyed(brick, pos)`；**不消费** `wall_cleared()`（归 #386） |
| 计分语义 | 拆砖 1 分给最后触球方；穿墙 3 分给攻击方（得分方）；两者都计入 21 分总分（PLAN §2.2/§2.4） |
| 架构不变项 | #287 信号式碰撞、#291 信号链、#293 GameManager 全局状态、#295 常量单一事实源、#294 FSM 状态机均不重构；`ball.gd` 仅新增状态与分支 |
| 所有权 | `content_ownership: mechanical` — 计分规则/状态/信号为机械实现；分值 21/3/1 已定稿非 taste；拆砖/穿墙的视觉反馈（破砖闪光/穿墙脉冲）归 taste-draft/UI Issue |
| 开源优先 | 调研结果见 §7 实验 1 |

### 1.4 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索）：

- **Godot Asset Library**（assetlibrary.godotengine.org，godot_version=4.7）：`scoring` 过滤 **0 结果**（`total_items: 0`）；`score`/`pong` 无计分/对局状态插件
- **GitHub 搜索**（`godot scoring system`、`godot pong score`，GDScript/Godot 4.x 过滤）：无高星可插拔计分/21 分制插件——计分逻辑与游戏规则强耦合，社区同类均为完整游戏克隆（#384 调研已覆盖 breakout 类 0 结果）
- **结论**：**没有可复用的「双得分制/终局判定」插件**；本功能为第一方实现，Godot 4.7 内置能力（信号、autoload、常量）完全覆盖，**不引入任何第三方资产**。与 #384 的调研结论模式一致。

### Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（`OBSIDIAN_VAULT_PATH`），本会话 **Knowledge Ocean 目录可访问**（较 #384 会话的挂载超时已恢复）
- 检索 `双得分/拆砖/21 分/穿墙/pong`：**无直接命中**——命中的笔记均属其他项目（`raw/Bear/`、`raw/Evernote/完美的一天`、`汐创作笔记`），无本游戏计分设计条目
- **兜底**：双得分制设计决策已由 `docs/PLAN-rogue-pong.md` §2.2（拆砖 1 分最后触球方 + 穿墙 3 分攻击方）与 §2.4（21 分制，先到者赢，砖墙打空=升级+新墙比赛继续）**固化并用户拍板**；其理论依据来自 Obsidian《体验引擎》情感模型（§2.5 引用）。GDD `docs/GAME_DESIGN/14-SCORING-SYSTEM.md`、`15-GAME-MANAGER.md` 提供既有计分架构约定。

### 1.5 范围边界（与相邻 PRD 解冲突）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #291 计分系统 | 边界出界信号链（ball.score → ScoringManager → 5 分/2 局） | ❌ 不重构既有信号链；21 分制在其上叠加/替换终局判定 |
| #293 GameManager 全局状态 | autoload 状态持有 + `add_score` + 查询 API 模式 | ✅ 本 Issue 扩展其状态与 API（AC3/AC5 明确指向 GameManager） |
| #384 砖墙系统 | 砖墙生成/碰撞/`brick_destroyed` 契约 | ❌ 只消费 `brick_destroyed`；不碰生成算法与反弹规则 |
| #386 波次循环 | 波次递增/墙更厚/AI 增强/`wall_cleared` | ❌ 不消费 `wall_cleared`；21 分制下砖墙打空语义归 #386 |
| #390/#391/#392 UI | 波次转场/失败屏/霓虹 UI 升级 | ❌ 拆砖/穿墙**视觉反馈与布局**归 UI Issues；本 Issue 只保证数据与信号链 |
| #393 主场景组装 | BreakoutGrid 接线进 Main.tscn | ❌ Main.tscn 接线归 #393；本 Issue 的消费方用 `get_node_or_null` 容错，接线前可独立测试 |

---

## 2. 设计意图

### 为什么当前状态存在

Mini Pong 从 #287 → #291 → #293 → #295 一路是**经典 Pong 计分**：边界出界 1 分、5 分赢局、2 局赢比赛。双得分制是 Rogue Pong 肉鸽化改造的核心规则（PLAN-rogue-pong §4.2「新: 双得分制」），此前不存在是因为其**载体（砖墙）尚未实现**：拆砖分需要砖可被击碎（#384），穿墙分需要墙有洞（#384 缺口布局）。

| 现状来源 | Issue | 贡献 |
|---------|-------|------|
| 边界出界信号链（side 0/1 + `_scored_this_frame` 帧守卫） | #287/#295 | 穿墙判定可复用的帧级去重模式 |
| 5 分/2 局制计分状态 | #291/#293 | 本 Issue 替换为 21 分终局 |
| `brick_destroyed` 信号契约 | #384 | 拆砖分的输入事件（已定契约，实现未落地） |
| 双得分制/21 分制规则拍板 | PLAN-rogue-pong（用户 2026-08-13） | 分值 1/3/21 定稿，无 taste 空间 |

### 为什么现在改

1. **PLAN-rogue-pong 已拍板**（2026-08-13）：双得分制 + 21 分制是 MVP 核心规则，波次循环（#386）、主场景组装（#393）、失败屏（#391）都依赖本 Issue 的计分 API/信号
2. **契约已就绪**：#384 的 `brick_destroyed` 信号契约已定稿（PRD #411 + DESIGN #414 合并），本 Issue 是消费方——趁实现未落地同步设计，可避免信号签名返工
3. **窗口期**：21 分制替换 5 分/2 局制涉及 FSM/测试联动，越早改，下游 #386/#393 越少返工

### 先前约束

| 约束 | 细节 |
|------|------|
| 信号链（#291/#295） | `ball.score(side)` → ScoringManager → GameManager 链路不动；拆砖/穿墙作为**新事件源**接入同一 GameManager |
| 帧守卫（#295） | `_scored_this_frame` 防同帧双触发模式复用（AC4 同帧去重） |
| GameManager 职责（#293） | 「不重复 ScoringManager 逻辑」——场景侧事件判定（穿墙/拆砖归属）留在场景节点，GameManager 只做状态持有 + 终局判定 + 查询 API |
| 常量单一事实源（#295） | 所有分值/阈值进 `constants.gd`，不散落硬编码 |
| 竖屏坐标（#383） | side 0=player（顶部出界）、side 1=ai（底部出界）；墙带穿越判定基于 `wall_y`（#384 常量 `GRID_WALL_Y=640`） |
| 测试即验收 | 新测试注册进 `run_tests.gd`；`godot --headless --script tests/run_tests.gd` 全绿 |

---

## 3. 影响分析

### 直接受影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/constants.gd` | 计分常量 | **修改**：`POINTS_TO_WIN_GAME` 5→21（或新增 `WIN_SCORE=21` 并弃用前者）；新增 `BRICK_SCORE=1`、`PIERCE_SCORE=3`；`GAMES_TO_WIN_MATCH` 标记弃用（21 分制无局/比赛分层）；新增墙带判定常量（`WALL_BAND_HALF_HEIGHT`，基于 #384 `BRICK_SIZE.y`） |
| `mini-pong/gdscripts/game_manager.gd` | 全局状态 | **修改**：新增 `player_brick_count/player_pierce_count/ai_brick_count/ai_pierce_count`；`add_score(winner, amount, kind)` 扩展（或新增 `add_brick_point/add_pierce_point`）；21 分终局判定 → `match_over`；查询 API `get_brick_count(side)`/`get_pierce_count(side)`（AC5） |
| `mini-pong/gdscripts/scoring_manager.gd` | 场景计分消费 | **修改**：新增 `brick_destroyed` 消费（`get_node_or_null` 容错引用 BreakoutGrid → 读 `ball.last_toucher` → `add_score(toucher, BRICK_SCORE, "brick")`）；出界分判定（穿越墙带 → 3 分，否则 1 分） |
| `mini-pong/gdscripts/ball.gd` | 球状态 | **修改**：新增 `last_toucher: String`（paddles 分支按节点名/新 group 区分 player/ai）；新增墙带穿越标记（Y 跨过 `wall_y ± 带半高` 置位，挡板触球/发球复位）；#384 的 bricks 分支叠加拆砖归属 |
| `mini-pong/gdscripts/paddle.gd` | 挡板分组 | **修改（可选）**：新增 `player_paddle`/`ai_paddle` 组（或依赖节点名 `PlayerPaddle`/`AIPaddle`，见 §5 边界条件） |
| `mini-pong/gdscripts/game_state_machine.gd` | FSM | **修改**：SCORED 状态判定改为「21 分 → GAME_OVER」直达（移除 `get_winner()` 局判定路径） |
| `mini-pong/gdscripts/game_hud.gd` | HUD | **修改（最小）**：总分联动已有（`score_changed`）；如 AC1 要求拆砖分即时可见，可加拆砖/穿墙小计 Label（大改归 #390/#392） |
| `mini-pong/gdscripts/game_over_screen.gd` | 结算屏 | **修改（最小）**：`_on_match_over` 内读 GameManager 查询 API 展示拆砖/穿墙数（布局归 #391） |

### 新建文件

| 文件 | 内容 |
|------|------|
| `mini-pong/tests/test_dual_scoring.gd` | 双得分制测试（拆砖归属/穿墙 3 分/21 分终局/同帧去重/查询 API） |

### 间接受影响模块

| 文件 | 影响 |
|------|------|
| `mini-pong/tests/test_game_manager.gd` | TC6 等 5 分制断言需更新为 21 分制 |
| `mini-pong/tests/test_scoring_manager.gd` | 5 分/2 局断言需更新（穿墙分/拆砖分新用例） |
| `mini-pong/tests/test_ball.gd` | 新增最后触球者/穿越标记用例；既有用例不回归 |
| `mini-pong/tests/test_constants.gd` | 新常量断言 |
| `mini-pong/tests/run_tests.gd` | 注册 `test_dual_scoring.gd` |
| `mini-pong/scenes/Main.tscn` | **不改**（#393 负责接线）；若本 Issue 需临时验证，测试内程序化实例化 |
| `docs/GAME_DESIGN/14-SCORING-SYSTEM.md`、`15-GAME-MANAGER.md` | 21 分制 + 双得分状态更新（review agent merge 后回写惯例） |

### 数据流影响（ASCII）

```
BreakoutGrid.brick_destroyed(brick, pos)   [来自 #384 实现]
    │
    ▼
ScoringManager._on_brick_destroyed(brick, pos)
    ├── 读 Ball.last_toucher ("player"|"ai")
    └── GameManager.add_score(toucher, 1, "brick")
            ├── player_brick_count/ai_brick_count += 1   (AC5 可查询)
            ├── score_changed.emit(p, a) ──► GameHUD 总分更新 (AC1)
            └── _check_run_end(): 任一 ≥ 21 → match_over.emit(winner) (AC3)

Ball 出界 (side)  [既有 score(side) 信号]
    │  (叠加 Ball._crossed_wall 穿越标记)
    ▼
ScoringManager._on_ball_score(side)
    ├── 已穿越墙带 → GameManager.add_score(winner, 3, "pierce")   (AC2)
    │       ├── player_pierce_count/ai_pierce_count += 1
    │       ├── score_changed.emit ──► HUD
    │       └── _check_run_end(): ≥21 → match_over.emit (AC3)
    └── 未穿越墙带（无墙兜底）→ GameManager.add_score(winner, 1, "boundary")

GameManager.match_over(winner)
    ├──► FSM._on_match_over → State.GAME_OVER
    └──► GameOverScreen._on_match_over → 读 get_brick_count/get_pierce_count (AC5)
```

### 需更新的文档

- [x] 本 PRD（#385 研究产出）
- [ ] `docs/GAME_DESIGN/14-SCORING-SYSTEM.md` — 21 分制 + 双得分状态（review 后回写）
- [ ] `docs/GAME_DESIGN/15-GAME-MANAGER.md` — 新状态与查询 API（review 后回写）
- [ ] `docs/PROJECT.md`（如含计分规则段落）

---

## 4. 方案对比

### Approach A：GameManager 扩展为双得分状态持有者 + 场景侧消费节点（推荐）

**描述：** 保持 #293「GameManager 只管全局状态、场景节点管事件判定」的既有分工。场景侧 `ScoringManager`（或新增 `DualScoring` 节点）消费 `brick_destroyed` 与 ball 出界事件，判定归属与穿墙后调用扩展后的 `GameManager.add_score(winner, amount, kind)`；GameManager 持有拆砖/穿墙计数、21 分终局判定与查询 API。`constants.gd` 集中分值（1/3/21）。

**要点：**
- `ball.gd`：`last_toucher`（paddles 分支记录）+ `_crossed_wall` 穿越标记（Y 跨墙带置位，触球/发球复位）
- `scoring_manager.gd`：`get_node_or_null("../BreakoutGrid")` 容错连接 `brick_destroyed`（#393 接线前不崩）
- `constants.gd`：`BRICK_SCORE=1`、`PIERCE_SCORE=3`、`WIN_SCORE=21`；弃用 `GAMES_TO_WIN_MATCH`

**Pros：**
- AC3/AC5 字面指向 GameManager——扩展即满足，无状态镜像/同步问题
- autoload 全局可查：HUD、结算屏、失败屏（#391）、未来波次屏（#386）零接线读取
- 场景侧容错连接：不阻塞 #384 实现落地前的独立测试
- 帧守卫（#295）与 `get_node_or_null`（ScoreFlash）均为既有成熟模式，无新架构

**Cons：**
- GameManager 状态增多（4 个新计数 + 终局判定），但仍是纯数据持有，职责清晰
- 需要同步更新既有 5 分制测试（一次性成本）

**Risk:** Low — 信号链与 FSM 小步修改，#287 测试兜底回归
**Effort:** 0.5–1 周（含测试改造）

### Approach B：独立 DualScoring autoload 单例

**描述：** 新建 `DualScoring` autoload 专门承载双得分状态与终局判定，GameManager 保持原样。

**Pros：** 关注点分离最彻底；不动 GameManager 既有 5 分制逻辑

**Cons：**
- 与 #293 架构决策冲突：GameManager 本是「全局状态单一事实源」，新增第二个计分状态源 → 两处都要维护/查询，AC3「GameManager 进入终局状态」字面不满足
- HUD/结算屏要同时读两个 autoload；`project.godot` autoload 列表 +1
- 21 分制与 5 分制并存造成规则混乱（哪个生效？）

**Risk:** Med — 双状态源漂移；违反既有架构决策
**Effort:** 1–1.5 周

### Approach C：计分逻辑全部内聚到 ball.gd

**描述：** 球自管拆砖/穿墙判定并直接写 GameManager（或自持分数）。

**Pros：** 事件源最近，无需中间节点

**Cons：**
- 破坏 #287「信号式碰撞」与 #291「ScoringManager 权威计分」架构——球同时管物理与计分，职责爆炸
- 与 #384 已否决的「球侧写状态」反模式同构（#384 PRD §4 Approach B 已否决）
- 查询接口/终局判定与 GameManager 割裂，AC5 难满足

**Risk:** High — 架构退化，测试耦合
**Effort:** 0.5 周（短期快但长期债）

### 推荐

**Approach A。** 理由：
1. **AC 对齐**：AC3（GameManager 终局）、AC5（GameManager 查询）字面要求状态进 GameManager，A 是唯一零镜像方案
2. **架构一致**：延续 #293「场景判事件、全局持状态」分工与 #291 信号链，无新 autoload、无规则并存
3. **依赖解耦**：场景侧 `get_node_or_null` 容错使 #385 可与 #384 实现并行落地，不阻塞
4. **最小触碰面**：修改集中在 GameManager 状态区 + ScoringManager 两个 handler + ball 两个状态字段，FSM 仅改 SCORED 判定

---

## 5. 边界条件与验收标准

### 正常路径（AC 清单，源自 Issue #385）

- [x] **AC1: 拆砖分归属最后触球方并更新 HUD** — 玩家触球后球拆 AI 侧砖：`ai_brick_count +1`、`ai_score +1`、`score_changed` 触发、HUD 总分更新
  - 验证：`brick_destroyed` 模拟触发 → GameManager 状态与信号断言；HUD Label 文本断言
- [x] **AC2: 穿墙出界 +3 分** — 球穿越墙带后从顶部出界（未被 AI 接住）：`player_pierce_count +1`、`player_score +3`
  - 验证：ball 穿越标记置位 + 出界 → ScoringManager 走 3 分分支
- [x] **AC3: 21 分终局** — 任一方总分（拆砖+穿墙合计）达 21：GameManager 发 `match_over`，FSM 进 GAME_OVER
  - 验证：20 分时再得 1 分 → `match_over` 恰好一次；分数不再累加
- [x] **AC4: 同帧拆砖/穿墙不重复计分** — 同帧砖碎 + 出界：只计拆砖分（或只计一次，规则见 §5 边界 1）
  - 验证：同帧双事件 → 总分只 +1（拆砖），无 +3
- [x] **AC5: 查询接口** — `GameManager.get_brick_count("player"/"ai")`、`get_pierce_count(side)` 返回正确计数；结算屏可读
  - 验证：结算屏 handler 读查询 API 断言

### 边界条件（编号，≥5）

1. **同帧拆砖+出界（AC4 核心）** — 规则：出界帧内若发生砖碎，只计拆砖分（该帧出界不计穿墙 3 分）；砖碎与出界在不同帧 → 各自计分（打穿推进，PLAN §2.4「都计入」）。复用 `_scored_this_frame` 帧守卫语义，砖碎事件置 `_brick_destroyed_this_frame`，出界判定检查之
2. **最后触球者为空** — 发球后球未触任何挡板直接撞砖（发球方向随机直冲砖墙）：`last_toucher == ""` → 该砖不计拆砖分（防随机发球送分）；砖仍正常碎与反弹（#384 行为不变）
3. **球出界但未穿越墙带（无墙兜底）** — 墙不存在（#384 未接线时期）或墙带判定缺失：出界按普通 1 分（既有行为兜底，游戏不坏）——这是 #385 先于 #393 落地的关键保证
4. **发球/暂停期** — `_is_serving`/PAUSED 时球不动或延迟：无碰撞、无出界、无计分；`last_toucher`/穿越标记复位时机在 `serve()`（发球复位）
5. **双挡板同 group（paddles）** — 最后触球者区分：优先按节点名（`PlayerPaddle`/`AIPaddle`）判定；若实现选择新增 `player_paddle`/`ai_paddle` 组，需在 paddle.gd `_ready()` 加 `add_to_group`（改动最小）
6. **21 分同时达到** — 单次事件只给一方加分，不存在同帧双方到 21；终局判定在每次 `add_score` 后同步执行，先到先赢
7. **墙带判定带宽** — 高速球（627px/s ≈ 10.5px/帧）单帧穿越墙带：判定带取 `wall_y ± (BRICK_SIZE.y/2 + BALL_RADIUS)`（防漏判），常量入 `constants.gd`；方向性（朝对方移动）可选加固
8. **拆砖分与暂停** — 拆砖不触发 FSM SCORED 状态（砖碎+反弹比赛继续）；只有出界（穿墙/普通）才走 SCORED → 重发球流

### 失败路径（≥3）

1. **`brick_destroyed` 消费方引用空节点** — BreakoutGrid 未接线（#393 前）：`get_node_or_null("../BreakoutGrid")` 返回 null → 跳过连接，不报错、不崩（日志警告一次）
2. **终局后事件泄漏** — `match_over` 后球仍在飞/砖仍碎：GameManager `_is_run_over` 守卫（复用 ScoringManager `_is_match_over` 模式），终局后 `add_score` 直接 return
3. **拆砖分重复计入** — 同帧多砖碎：按砖对象身份去重（#384 grid 已去重，消费方再按 `brick` 实例守卫一次，防 #384 实现偏差）
4. **穿越标记残留** — 球触砖反弹回本侧再出界（未穿墙）：标记必须在**挡板触球/发球**时复位，否则误判 3 分——测试覆盖「触砖反弹出界」路径断言 1 分

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #383 轴交换+竖屏（720×1280，side 0/1 语义） | ✅ 已合并（PR #409） | 无 |
| #384 砖墙系统（`brick_destroyed` 契约） | ⚠️ PRD #411 + DESIGN #414 已合并，**实现未落地**（无 breakout_grid.gd） | **中**：拆砖分消费方依赖其实现；本 Issue 用 `get_node_or_null` 容错 + 隔离测试先行，不阻塞 |
| #287 球物理 / #295 帧守卫（`_scored_this_frame`） | ✅ 已存在 | 无（复用模式） |
| #291/#293 信号链与全局状态架构 | ✅ 已存在 | 无（扩展不改架构） |
| 第三方资产 | — | 无（开源优先调研：无可复用方案，§7 实验 1） |

### 阻塞（下游消费者）

| 下游 | 优先级 | 本 Issue 提供的契约 |
|------|--------|-------------------|
| #386 波次循环 | P0 | 21 分制下砖墙打空 ≠ 终局（比赛继续直到 21）的语义确认；`wall_cleared` 不触发终局 |
| #391 失败屏 | P0 | `get_brick_count/get_pierce_count` 查询 API（run 数据） |
| #393 主场景组装 | P0 | BreakoutGrid 接线 → `brick_destroyed` 连到 ScoringManager；墙带常量对齐 |
| #394 端到端可玩验证 | P0 | 双得分 E2E（拆砖 +1、穿洞 +3、21 分终局截图） |

### 依赖链

```
#383 (轴交换+竖屏) ──✅ 已合并──► #384 (砖墙系统) ──⚠️实现未落地──► #385 (本 Issue: 双得分制)
                                                                   │
                #385 契约: brick_destroyed 消费 + add_score(kind) + 21 分终局
                                                                   ▼
                                          #386 (波次循环) ──► #393 (组装) ──► #394 (E2E)
                                          #391 (失败屏读取统计)
```

### 准备清单

- [x] 开源优先调研（Asset Library + GitHub，§7 实验 1）
- [x] 既有信号链核实（ball.score → ScoringManager → GameManager；`_scored_this_frame` 帧守卫可复用）
- [x] #384 实现状态核实（PRD/DESIGN 已合并，代码未落地 → 消费方容错设计）
- [x] Obsidian 知识检索（无直接命中；设计已由 PLAN-rogue-pong §2.2/§2.4 固化）
- [ ] plan agent：确认 `last_toucher` 区分方式（节点名 vs 新 group）与 `POINTS_TO_WIN_GAME` 改名策略（保留名改值 vs 新 `WIN_SCORE`）

---

## 7. Spike / 实验

> 本 Issue 无 `depth/deep` 标签，按 standard 惯例 Section 7 可选；鉴于 Issue body 明确要求「开源优先」调研，以下 3 个实验已在**研究阶段实际执行**并给出结论，供 plan agent 直接引用。

| # | 问题 | 方法 | 结果 | 对方案的影响 |
|---|------|------|------|-------------|
| 1 | 是否存在可复用的双得分/计分插件？ | Godot Asset Library（4.7 过滤 `scoring`/`score`/`pong`）+ GitHub 搜索（`godot scoring system`、`godot pong score`） | Asset Library 0 结果；GitHub 无高星可插拔插件（计分逻辑与游戏规则强耦合） | 确认第一方实现（Approach A），零第三方依赖 |
| 2 | 最后触球者能否从现有代码区分？ | 读 `paddle.gd`（双挡板 `add_to_group("paddles")`）与 `ball.gd` `_on_area_entered` | group 无 player/ai 区分；但场景节点名为 `PlayerPaddle`/`AIPaddle`（Main.tscn），可按 `area.name` 判定 | ball.gd 需加 2 字段（`last_toucher` + 判定），改动 ~10 行 |
| 3 | 同帧去重能否复用既有帧守卫？ | 读 `ball.gd` `_scored_this_frame`（#295 双触发守卫）与 `_on_score_zone`/`_process` 出界路径 | 帧级布尔守卫模式成熟；`serve()` 复位点明确 | AC4 用同模式扩展（`_brick_destroyed_this_frame`），无新机制 |

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- 竖屏 720×1280 已就绪（#383，PR #409）；球 Area2D（layer 3、mask 3），墙/挡板 layer 1，砖 layer 2（#384 契约，球 mask 已覆盖）
- 计分链路：`ball.score(side)`（side 0=player 顶部、1=ai 底部）→ `ScoringManager`（+1、scored 信号）→ `GameManager.add_score`（`score_changed`）→ HUD/FSM
- #384 实现**未落地**（无 breakout_grid.gd/brick.gd）：拆砖分消费方必须 `get_node_or_null` 容错
- 工作区注意：并行 agent 有 #389 雨幕未提交 WIP（`rain_curtain.gd` 等），实现时勿覆盖

### 本 PRD 的核心决策（勿偏离）

1. **Approach A**：场景侧（ScoringManager）判事件（拆砖归属/穿墙判定）→ `GameManager.add_score(winner, amount, kind)`；GameManager 持状态 + 21 分终局 + 查询 API
2. **分值常量**：`BRICK_SCORE=1`、`PIERCE_SCORE=3`、`WIN_SCORE=21`（`constants.gd` 单一事实源）；5 分/2 局制废弃（`POINTS_TO_WIN_GAME` 改 21 或新 `WIN_SCORE`，plan 定）
3. **穿墙判定**：`ball._crossed_wall` 标记（Y 跨 `wall_y ± 带半高` 置位；挡板触球/发球复位）；出界时已穿越 → 3 分，否则 1 分兜底（无墙时期游戏不坏）
4. **最后触球者**：`ball.last_toucher`（paddles 分支按节点名 `PlayerPaddle`/`AIPaddle` 判定）；为空（发球直撞砖）不计拆砖分
5. **AC4 同帧去重**：`_brick_destroyed_this_frame` + 既有 `_scored_this_frame` 帧守卫；同帧砖碎+出界只计拆砖分
6. **终局**：任一方总分 ≥21 → `match_over` 信号（复用既有信号名与 FSM GAME_OVER 路径）；`_is_run_over` 守卫防终局后事件泄漏；砖墙打空不终局（归 #386）
7. **拆砖不暂停**：拆砖不触发 FSM SCORED；只有出界走 SCORED → 重发球

### 新建文件清单

| 文件 | 要点 |
|------|------|
| `mini-pong/tests/test_dual_scoring.gd` | 拆砖归属（含空触球者）、穿墙 3 分、普通出界 1 分兜底、21 分终局恰好一次、同帧去重、查询 API |

### 修改文件清单

| 文件 | 改动 |
|------|------|
| `mini-pong/gdscripts/constants.gd` | 计分常量组（`BRICK_SCORE/PIERCE_SCORE/WIN_SCORE`、墙带判定常量、弃用 `GAMES_TO_WIN_MATCH`） |
| `mini-pong/gdscripts/game_manager.gd` | 4 个计数状态 + `add_score(winner, amount, kind)` + 21 分终局 + `get_brick_count/get_pierce_count` |
| `mini-pong/gdscripts/scoring_manager.gd` | `brick_destroyed` 容错消费 + 出界分 3/1 判定 |
| `mini-pong/gdscripts/ball.gd` | `last_toucher` + `_crossed_wall` 标记（触球/发球复位） |
| `mini-pong/gdscripts/game_state_machine.gd` | SCORED 判定 → 21 分直达 GAME_OVER（移除局判定） |
| `mini-pong/gdscripts/game_hud.gd` | 拆砖/穿墙小计（最小实现，满足 AC1；大 UI 归 #390/#392） |
| `mini-pong/gdscripts/game_over_screen.gd` | 读查询 API 显示拆砖/穿墙数（布局归 #391） |
| `mini-pong/gdscripts/paddle.gd` | （可选）player/ai 区分组 |
| `mini-pong/tests/test_game_manager.gd` / `test_scoring_manager.gd` / `test_ball.gd` / `test_constants.gd` / `run_tests.gd` | 21 分制断言更新 + 新用例注册 |

### 测试要点（test_dual_scoring.gd）

- 拆砖：模拟 `brick_destroyed` 触发 → 最后触球方 +1、计数 +1、`score_changed` 触发；`last_toucher=""` 时不加分
- 穿墙：`_crossed_wall=true` 出界 → +3、`pierce_count +1`；`false` 出界 → +1 兜底
- 终局：累加到 21 → `match_over` 恰好一次、分数冻结；20 分 + 拆砖 1 分 = 21 终局
- 同帧：同帧砖碎+出界 → 只 +1（拆砖），无 +3
- 查询：`get_brick_count/get_pierce_count` 与状态一致

### 主要风险

- `constants.gd` 分值改动影响既有测试（5 分制断言）——必须同步更新，否则 CI 红
- `ball.gd` 触碰核心：`last_toucher`/穿越标记改动须保持 walls/paddles 分支行为不变（#287 测试兜底）
- #384 实现未落地：拆砖分消费方以容错连接 + 隔离测试先行；如 #384 实现先落地，直接接线验证
- 穿墙判定带宽与 `GRID_WALL_Y` 对齐：`#393` 组装时墙 Y 可能调整，常量需单一来源

### 下一步

1. plan agent 依据本 PRD 产出 DESIGN（含测试描述）
2. implement agent 实现（本 Issue 机械所有权，无需人审）
3. #393 组装时接线 `BreakoutGrid.brick_destroyed` → ScoringManager；`wall_cleared` → #386
4. #391 失败屏读取 `get_brick_count/get_pierce_count` 展示 run 数据

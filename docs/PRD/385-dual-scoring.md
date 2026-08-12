# PRD: [Feature] 双得分制 (Dual Scoring System)

> **Issue:** #385
> **标签:** enhancement, gameplay, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验补齐）
> **所有权:** `content_ownership: mechanical`（分值/计数/终局判定为机械规则；HUD 双区视觉与文案归 #392/#393 的 taste 范围）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.2 双得分制（已确认：拆砖 1 分/穿墙 3 分/最后触球方）+ §2.4 21 分制胜负判定（已确认 2026-08-13）
> **前置依赖:** #383（轴交换+竖屏，**已关闭**，PR #409 已合并）→ #384（砖墙系统，**已关闭**，PRD #411 + DESIGN #414 已合并）→ 本 Issue 建立在 720×1280 竖屏 + BreakoutGrid 信号契约之上

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）当前只有**单一得分路径**：球从上/下出界 → `ball.score(side)` → `ScoringManager` → `GameManager.add_score(winner)` 每次 +1 分，先到 5 分赢一局、先赢 2 局赢整场。**不存在拆砖分、穿墙分、最后触球方追踪，也没有 21 分制终局**。

| 文件 | 当前状态 | 与 #385 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/game_manager.gd` | `add_score(winner)` 固定 +1；`POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2`（constants.gd:76-77）；`_check_game_win()` 5 分触发 `game_won`，2 局触发 `match_over` | ❌ 无分值参数（不能 +1 拆砖/+3 穿墙）；❌ 无拆砖/穿墙计数与查询接口（AC5）；❌ 21 分制终局（AC3） |
| `mini-pong/gdscripts/scoring_manager.gd` | 消费 `ball.score(side)` → `scored(winner)` → `GameManager.add_score(winner)`；侧边映射 side=0→player、side=1→ai | ❌ 不消费 `brick_destroyed` 信号（AC1）；❌ 出界得分无 3 分语义（AC2） |
| `mini-pong/gdscripts/ball.gd` | `_on_area_entered` paddles 分支处理挡板反弹；`_process` Y 出界 → `score.emit(side)`；`_scored_this_frame` 防同帧双触发 | ❌ 无 `last_toucher`（最后触球方）追踪（AC1 归属前提） |
| `mini-pong/gdscripts/constants.gd` | `POINTS_TO_WIN_GAME=5`、`GAMES_TO_WIN_MATCH=2`（#295 单一事实源） | ❌ 无 `POINTS_BRICK=1`/`POINTS_WALL_PASS=3`/`POINTS_TO_WIN_GAME=21` 常量 |
| `mini-pong/scenes/Main.tscn` | Ball/双挡板/ScoreZoneTop/Bottom/ScoringManager/FSM/HUD/GameOverScreen；**无 BreakoutGrid 节点** | ❌ 接线归 #393（本 Issue 不改 Main.tscn，与 #384 DESIGN §9 一致） |
| `mini-pong/tests/test_game_manager.gd` | 15 个用例：+1 计分、5 分 game_won、2 局 match_over、reset、get_winner | ❌ 无 21 分制/拆砖/穿墙用例 |
| `mini-pong/tests/test_scoring_manager.gd` | 42 个用例：side→winner 映射、5 分制、post-match guard | ❌ 无 brick_destroyed 消费用例、无 3 分制用例 |

**上游已确认的计分语义（PLAN-rogue-pong §2.2/§2.4，research 无需再议）：**

| 得分 | 分值 | 触发 | 归属 |
|------|:---:|------|------|
| 拆砖分 | 1 | 球击碎砖块（`brick_destroyed` 信号） | **最后触球方**（球最后一次碰到的挡板方） |
| 穿墙分 | 3 | 球未被接住从上/下出界（穿越砖墙到达对方底线） | 攻击方（出界得分方） |
| 胜负 | — | 任意一方先到 **21 分** | 终局（GameManager 进入终局状态） |

**关键事实核查（来自源码，方案 A 可行性的依据）：**

- 竖屏布局中砖墙横跨全屏 720px（#384 DESIGN：`cols = floor(720 / (brick_size.x + gap))` 铺满），左右是墙（X 反弹），球**无法从侧面绕过砖墙** —— 球从一侧到达另一侧底线必然穿过砖墙平面（打碎砖或穿缺口）
- `ball.gd` 出界得分路径已存在且语义对齐：`y < -R → score.emit(0)`（player 得分，球从顶部穿越 AI 侧出界）、`y > H+R → score.emit(1)`（ai 得分）—— **出界 = 穿越砖墙 = 穿墙分 3 分**，可复用现有信号链，无需新增物理检测
- `paddle.gd` 有 `enum Mode { PLAYER=0, AI=1 }` + `@export var mode`；Main.tscn 中 PlayerPaddle mode=0（默认）、AIPaddle mode=1 —— **ball 可借 `area.mode` 判定最后触球方**，零新增配置
- `ScoringManager._ready()` 已有 `get_node_or_null` best-effort 连接模式（ScoreFlash）—— 扩展为连接 `../BreakoutGrid.brick_destroyed` 同构
- #384 DESIGN §3.2 数据流：`BreakoutGrid.brick_destroyed(brick, pos)` 信号 → **#385 拆砖分（最后触球方）** —— 契约已定稿

### 预期行为（验收条件，源自 Issue #385）

1. **AC1 — 拆掉一块砖给最后触球方 +1 分，并更新 HUD** — `brick_destroyed` → 查 `ball.last_toucher` → 该方 `add_points(winner, 1)`；`score_changed` 信号链驱动 HUD 总分更新（HUD 已监听，零改动）
2. **AC2 — 球未被接住从上/下出界且穿越砖墙时，给得分方 +3 分** — 出界得分路径分值 1 → 3（穿墙分）；竖屏下出界必经砖墙（见事实核查），MVP 统一 3 分
3. **AC3 — 任意一方达到 21 分时 GameManager 进入终局状态** — `POINTS_TO_WIN_GAME=21`；21 分触发 `game_won` + `match_over`（终局），FSM GAME_OVER / GameOverScreen 现有链路复用
4. **AC4 — 同一帧的拆砖/穿墙不会重复计分** — 拆砖侧由 BreakoutGrid 按砖身份去重（#384 契约 `_destroyed` 字典）；穿墙侧复用 `_scored_this_frame`；计分入口单一（ScoringManager 集中消费，见 §4 Approach A）
5. **AC5 — GameManager 可查询每方拆砖数、穿墙数，供结算/失败屏使用** — 新增 `player_bricks/ai_bricks/player_wall_passes/ai_wall_passes` 计数 + `get_bricks_destroyed(side)`/`get_wall_passes(side)` 查询接口（#391 失败屏 / #390 波次转场消费）

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 对打拆砖 | 每局每回合 | 玩家把球打向砖墙，碰砖 → 砖碎 +1 分（归最后触球方=玩家）+ 反弹；HUD 总分即时更新 |
| B | 穿墙得分 | 每局多次 | 球穿过砖墙缺口/留缝到达 AI 底线出界 → +3 分（攻击方）；穿墙是稀缺高价值动作（3 分 vs 拆砖 1 分） |
| C | 21 分终局 | 每场一次 | 任意一方累计到 21 分 → `match_over` → FSM GAME_OVER → 失败屏/结算（#391）读取拆砖数/穿墙数展示 run 数据 |

### 技术约束（继承自 Issue #385 + PLAN-rogue-pong + 依赖链）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，720×1280 竖屏，resizable=false） |
| 计分规则 | 拆砖 1 分（最后触球方）、穿墙 3 分（攻击方）、**先到 21 分者赢**（PLAN §2.4，已确认 2026-08-13） |
| 不变项 | FSM（#294）、`ball.score(side)` 信号链（#291/#295）、手感数值（#367）、HUD 总分显示（#292）不变；`scoring_manager.gd` 只扩展不重构 |
| 信号契约 | 消费 `BreakoutGrid.brick_destroyed(brick, pos)`（#384 定义）；**不实现**砖墙/波次逻辑（#384/#386 范围） |
| 接线边界 | Main.tscn 中 BreakoutGrid 节点实例化与正式接线归 **#393**；本 Issue 交付 ScoringManager 消费逻辑（`get_node_or_null` 自动连接 + 隔离测试），与 #384 DESIGN §9 一致 |
| 所有权 | `content_ownership: mechanical` — 分值/计数/终局为机械规则；HUD 拆砖/穿墙双区视觉、结算文案等 taste 内容归 #392/#393 |
| 开源优先 | 调研结果见 §1.4（无可复用第三方计分资产，第一方实现） |

### 1.4 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（与 #384 调研同口径）：

- **Godot Asset Library**（assetlibrary.godotengine.org，godot_version=4.7，sort=updated）：`score`/`scoring`/`breakout` 过滤**无计分插件**——计分是游戏逻辑而非资产；砖块生成/粒子/shader 资产已由 #384 §1.4 调研（结论：无可复用插件）
- **GitHub 搜索**（`godot breakout scoring`）：全部为**独立完整游戏克隆**（<5⭐），无"双得分制计分模块"可插拔组件；计分规则（拆砖 1 分/穿墙 3 分/21 分制）是本项目 PLAN-rogue-pong 专属设计，第三方通用计分库不匹配
- **结论**：**无可复用的「双得分制计分」插件/模板**；本功能为第一方实现，Godot 4.7 内置信号/常量机制完全覆盖，**不引入任何第三方资产**。与 #383/#384 的调研结论模式一致。

### Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（WebDAV，`OBSIDIAN_VAULT_PATH`），`Knowledge Ocean/wiki/体验引擎-patterns.md` 可读
- 检索命中：《体验引擎》模式 **"可预测的奖励变得无聊"**（patterns.md:79-80，"在不可预测的时间间隔传递奖励"）—— 支撑双得分制的分值差异设计：拆砖 1 分（高频可预测）+ 穿墙 3 分（稀缺高价值，穿墙动作本身不可预测）形成奖励节奏差异，与 PLAN §2.2 注释"穿墙是稀缺高价值动作"一致
- 未发现直接描述"双得分制/21 分制"的独立笔记；玩法决策已由 `docs/PLAN-rogue-pong.md` §2.2/§2.4 固化（该文档本身引用 Obsidian 理论），research 以 PLAN 为准

### 1.5 范围边界（与相邻 PRD 解冲突）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #291 计分系统 | 出界得分信号链、5 分一局/2 局一场 | ❌ 不重构信号链；只改分值（1→3 穿墙）与终局阈值（5→21） |
| #293 GameManager | 全局状态单例、score_changed/game_won/match_over | ❌ 不重建 GameManager；扩展 `add_points(winner, pts)` + 计数/查询 API |
| #384 砖墙系统 | BreakoutGrid 生成/碰撞/`brick_destroyed`/`wall_cleared` 信号 | ❌ 只**消费** `brick_destroyed`，不实现砖墙、不生成砖 |
| #386 波次循环 | 波次递增/墙更厚/AI 增强/墙打空重生 | ❌ 不消费 `wall_cleared`（归 #386）；墙打空后的重生不在本 Issue |
| #393 主场景组装 | 把 1-10 组件接入 Main.tscn（含 brick_destroyed 正式接线） | ❌ **不改 Main.tscn**；本 Issue 交付消费逻辑 + 隔离测试，#393 负责场景内接线 |
| #392 霓虹 UI 升级 / #391 失败屏 | HUD 双区视觉、结算展示 | ❌ 只提供查询接口（AC5），UI 呈现归 #392/#391 |

---

## 2. 设计意图

### 为什么当前状态存在

Mini Pong 从 #287（球物理）→ #291（计分）→ #293（GameManager）→ #295（组装）一路是**经典 Pong 单得分制**：出界即 +1，5 分一局、2 局一场。Rogue Pong 的"拆砖/穿墙双得分 + 21 分长局"是肉鸽化改造引入的新规则（PLAN-rogue-pong §2.2/§2.4），此前不存在是因为：砖墙系统（#384）尚未就绪——拆砖分的前提（可破坏砖块）刚由 #384 契约定义；竖屏坐标系（#383）刚落地，穿墙分语义（球穿越砖墙到达对方底线）才有物理载体。

| 现状来源 | Issue | 贡献 |
|---------|-------|------|
| 出界得分信号链（side→winner→add_score） | #291 | `ball.score(side)` 链路现状 |
| GameManager 全局状态（5 分/2 局） | #293 | 需扩展的计分/终局逻辑 |
| 常量单一事实源（POINTS_TO_WIN_GAME=5） | #295 | constants.gd 计分常量组 |
| 竖屏 720×1280（出界=穿墙的物理前提） | #383 | PR #409 已合并 |
| `brick_destroyed` 信号契约 | #384 | PRD #411 + DESIGN #414 已合并（实现落地状态见 §6 风险） |

### 为什么现在改

1. **PLAN-rogue-pong 已拍板**（2026-08-13）：双得分制 + 21 分制是 MVP 核心玩法规则，§2.2/§2.4 明确"已确认"
2. **契约就绪**：#384 的 `brick_destroyed(brick, pos)` 信号契约已定稿，拆砖分有了事件源；竖屏下出界=穿墙的物理事实使穿墙分可零成本复用现有出界得分路径
3. **依赖链窗口**：#383/#384 均已关闭，本 Issue 是 MVP 依赖链上"计分规则"一环；#386（波次循环）、#391（失败屏）、#393（组装）均等待本 Issue 的计数/查询接口

### 先前约束

| 约束 | 细节 |
|------|------|
| 信号链（#291/#295） | `ball.score(side)` → ScoringManager → GameManager 链路**不改**；分值/阈值变化在 ScoringManager/GameManager 内部 |
| 终局链路（#294/#292） | FSM 监听 `match_over` → GAME_OVER；GameOverScreen 监听 `match_over` —— 21 分制复用现有 `match_over` 信号，零 UI 改动 |
| 防重机制（#287/#295） | `_scored_this_frame`（ball 同帧防双触发）复用；拆砖去重由 #384 契约（`_destroyed` 字典按砖身份）保证 |
| 接线边界（#384 DESIGN §9） | Main.tscn 接线归 #393；本 Issue 用 `get_node_or_null` best-effort 连接 + 隔离测试 |
| 测试即验收 | 新用例注册进 `run_tests.gd`；`godot --headless --script tests/run_tests.gd` 全绿 |

---

## 3. 影响分析

### 直接影响的模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/constants.gd` | 常量 | **Modified** — 新增双得分常量组（`POINTS_BRICK=1`、`POINTS_WALL_PASS=3`）；`POINTS_TO_WIN_GAME: 5 → 21`；`GAMES_TO_WIN_MATCH: 2 → 1`（21 分制单局终局，保留 match 概念作终局信号载体） |
| `mini-pong/gdscripts/game_manager.gd` | 全局状态 | **Modified** — `add_score(winner)` → `add_points(winner, points)`（兼容调用）；新增拆砖/穿墙计数（`player_bricks`/`ai_bricks`/`player_wall_passes`/`ai_wall_passes`）+ 查询接口 `get_bricks_destroyed(side)`/`get_wall_passes(side)`；`_check_game_win()` 阈值 5→21；`reset_game()`/`reset_match()` 重置新计数 |
| `mini-pong/gdscripts/scoring_manager.gd` | 计分消费 | **Modified** — `_on_ball_score` 分值 1→3（穿墙分）；新增 `_on_brick_destroyed(brick, pos)`：查 `ball.last_toucher` → `GameManager.add_points(winner, 1)` + 拆砖计数；`_ready()` 用 `get_node_or_null("../BreakoutGrid")` best-effort 连接 `brick_destroyed` |
| `mini-pong/gdscripts/ball.gd` | 球物理 | **Modified** — 新增 `last_toucher: String`（""/"player"/"ai"）；`_on_area_entered` paddles 分支按 `area.mode`（paddle.Mode.PLAYER=0/AI=1）记录；`serve()` 按发球方向初始化（向上→"player"、向下→"ai"） |
| `mini-pong/tests/test_game_manager.gd` | 测试 | **Modified** — 新增 21 分制终局、拆砖/穿墙计数、查询接口用例 |
| `mini-pong/tests/test_scoring_manager.gd` | 测试 | **Modified** — 新增 brick_destroyed 消费、3 分穿墙、同帧防重用例 |
| `mini-pong/tests/run_tests.gd` | 测试入口 | **Modified** — 注册新增测试套件（若新建 `test_dual_scoring.gd`） |

### 新文件

| 文件 | 职责 |
|------|------|
| `mini-pong/tests/test_dual_scoring.gd`（可选，或并入 test_scoring_manager） | 双得分制集成测试：拆砖+1、穿墙+3、21 分终局、同帧防重、查询接口 |

### 间接影响的模块

| 文件 | 影响 | 说明 |
|------|------|------|
| `mini-pong/scenes/Main.tscn` | 本 Issue **不改** | BreakoutGrid 实例化与 brick_destroyed 正式接线归 #393；本 Issue 的 `get_node_or_null` 连接在 #393 落地后自动生效 |
| `mini-pong/gdscripts/game_hud.gd` | 本 Issue **不改** | 已监听 `GameManager.score_changed`，拆砖/穿墙分经该信号自动更新总分（AC1 "更新 HUD" 满足）；双区视觉归 #392 |
| `mini-pong/gdscripts/game_state_machine.gd` / `game_over_screen.gd` | 本 Issue **不改** | `match_over` 现有链路承载 21 分终局（AC3）；查询接口供 #391 后续消费 |
| `mini-pong/tests/test_main_scene.gd` | 兼容性检查 | Main.tscn 无 BreakoutGrid 时 ScoringManager 不崩（`get_node_or_null` 返回 null 静默跳过）——需回归确认 |
| `docs/GAME_DESIGN/14-SCORING-SYSTEM.md` | 文档 | GDD backfill 惯例（#311）：更新 21 分制/双得分说明（可由本 Issue 或 #393 顺带） |

### 数据流影响

```
BreakoutGrid.brick_destroyed(brick, pos)          [#384 契约，Main.tscn 接线归 #393]
    │
    ▼
ScoringManager._on_brick_destroyed(brick, pos)    [get_node_or_null 连接]
    │  winner = ball.last_toucher                 [ball 按 paddle.mode 维护]
    ├── GameManager.add_points(winner, POINTS_BRICK=1)
    │       ├── 拆砖计数: player_bricks/ai_bricks += 1   ──► AC5 查询接口
    │       └── score_changed.emit(p, a) ──► HUD 总分更新  [AC1 ✓]
    │
Ball._process() Y 出界 → score.emit(side)          [现有链路，分值改造]
    │
    ▼
ScoringManager._on_ball_score(side)
    ├── winner = side 映射 (0→player, 1→ai)
    ├── 穿墙计数: player_wall_passes/ai_wall_passes += 1 ──► AC5 查询接口
    ├── GameManager.add_points(winner, POINTS_WALL_PASS=3) [AC2 ✓]
    │       └── score_changed.emit(p, a) ──► HUD
    └── if 达到 21 分:
            game_won.emit(winner) + match_over.emit(winner) [AC3 ✓]
                │
                ▼
            FSM (#294) → GAME_OVER ──► GameOverScreen (#292, 不动)
```

### 同帧防重（AC4）数据流

```
同一帧内：
  拆砖事件 → BreakoutGrid._destroyed 按砖身份去重 → 每砖 brick_destroyed 恰好一次
           → ScoringManager 每砖恰好 add_points(1) 一次        [拆砖不重复]
  出界事件 → ball._scored_this_frame 守卫 → score(side) 恰好一次
           → ScoringManager 恰好 add_points(3) 一次            [穿墙不重复]
  拆砖 + 穿墙同帧（球碎砖后同帧出界）：两笔独立计分，各一次，不互相抑制
```

---

## 4. 方案对比

### Approach A：ScoringManager 集中消费 + GameManager 扩展（推荐）

**描述：** 保持 #291/#293 现有分层——场景内 ScoringManager 是**唯一计分入口**（消费 `ball.score(side)` 出界 + `BreakoutGrid.brick_destroyed` 拆砖），GameManager 只做数据记账（`add_points(winner, pts)` + 计数 + 终局判定）。ball 新增 `last_toucher`（按 `paddle.mode` 记录），供拆砖分归属查询。分值常量集中在 constants.gd。

**Pros：**
- 完全复用现有信号链与分层：`scored`/`game_won`/`match_over` 信号、HUD 监听、FSM 终局链路**零改动**
- 计分入口单一 → AC4 防重天然成立（拆砖去重靠 #384 契约、穿墙去重靠 `_scored_this_frame`，两入口互不干扰）
- 与 #384 DESIGN 数据流完全对齐：`brick_destroyed → #385 拆砖分(最后触球方)` 正是本方案
- 穿墙分复用现有出界路径：竖屏下出界必经砖墙（事实核查），**零新增物理检测**
- `get_node_or_null` best-effort 连接与 ScoreFlash 模式同构，Main.tscn 无 BreakoutGrid 时不崩（#393 落地后自动生效）

**Cons：**
- `scoring_manager.gd` 职责略增（拆砖消费 + 穿墙分值），但仍保持"信号消费→记账"单一职责
- `ball.gd` 需加 `last_toucher`（~5 行），触碰核心文件但不动既有分支逻辑

**Risk：** Low（改动面小、模式与 #291/#384 同构、契约已定稿）　**Effort：** 0.5-1 周

### Approach B：GameManager 直接消费信号（autoload 直连）

**描述：** GameManager（autoload）在 `_ready()` 直接连接 `ball.score` 与 `BreakoutGrid.brick_destroyed`，跳过 ScoringManager。

**Pros：**
- 计分逻辑全部收敛到 GameManager，ScoringManager 零改动

**Cons：**
- **打破 #291/#293 分层**：autoload 直连场景节点（ball/BreakoutGrid）使全局单例依赖具体场景结构，headless 测试需 mock 场景树，耦合度显著上升
- ScoringManager 现有的 side→winner 映射、post-match guard 逻辑重复实现或被迫迁移
- 与 #291 DESIGN"ScoringManager 是场景内计分节点"的既定架构冲突，违背项目最小触碰面惯例

**Risk：** Med　**Effort：** 1-1.5 周

### Approach C：新建 DualScoringManager 独立节点

**描述：** 新增场景节点专职双得分制，ScoringManager 只保留经典出界得分，两套计分并行。

**Pros：**
- 新旧计分完全隔离

**Cons：**
- **两套计分状态漂移风险**：score_changed/终局判定分属两个节点，HUD/FSM 需监听两路信号，复杂度翻倍
- GameManager 仍需统一记账与查询（AC5 要求 GameManager 可查询），新增节点反而引入中间层
- 21 分终局必须跨节点汇总 → 比 Approach A 多一层信号往返

**Risk：** Med-High　**Effort：** 1.5-2 周

### 推荐

**Approach A。** 理由：(1) 与 #291/#293/#384 既有架构同构，消费方在场景内、数据在全局单例，符合项目分层惯例；(2) 穿墙分复用现有出界得分路径（竖屏出界=穿墙的事实），AC2 零新增物理检测；(3) AC4 防重由现有机制自然满足（#384 去重 + `_scored_this_frame`）；(4) AC5 查询接口落在 GameManager（issue 明确要求），与 #293 全局状态定位一致。

**穿墙分实现子决策（AC2）：** MVP 统一"出界 = 穿墙分 3 分"，**不做**"球是否实际穿过砖墙"的逐帧检测。依据：竖屏布局砖墙横跨全屏 720px、左右有墙（X 反弹），球到达对方底线必须穿过砖墙平面（#384 事实核查）；穿墙检测需在 ball 维护"穿越砖墙区域"状态机，复杂度高且与 #384 缺口语义重复，违背最小触碰面。边界：砖墙打空后的重生归 #386（本 Issue 不消费 `wall_cleared`），若未来出现"无墙直飞出界"，分值语义由 #386 波次设计再议。

**终局实现子决策（AC3）：** `POINTS_TO_WIN_GAME: 5 → 21`，`GAMES_TO_WIN_MATCH: 2 → 1`（保留 match_over 作为终局信号载体，FSM/GameOverScreen 现有监听零改动）。不在本 Issue 删除 games 概念——删除涉及 #291 测试 42 例与 FSM 链路重构，收益（少一个计数器）远小于风险；`GAMES_TO_WIN_MATCH=1` 使 `match_over` 在 21 分时立即触发，语义等价"单局终局"。

---

## 5. 边界条件与验收标准

### 验收标准（Issue #385 AC 映射）

- [x] **AC1: 拆掉一块砖给最后触球方 +1 分，并更新 HUD**
  - `brick_destroyed` 到达 ScoringManager → `ball.last_toucher` 非空 → 该方 `add_points(winner, 1)`
  - `score_changed` 发出 → HUD 两个 Label 文本更新（已监听，回归确认）
  - 测试：模拟 `_on_brick_destroyed(brick, pos)`，last_toucher="player" → player_score +1
- [x] **AC2: 球未被接住从上/下出界且穿越砖墙时，给得分方 +3 分**
  - `_on_ball_score(side)` 分值 1 → 3（`POINTS_WALL_PASS`）
  - side=0（顶部出界）→ player +3；side=1（底部出界）→ ai +3
  - 测试：既有出界用例分值断言 1 → 3 更新
- [x] **AC3: 任意一方达到 21 分时 GameManager 进入终局状态**
  - `POINTS_TO_WIN_GAME=21`；`_check_game_win()` 21 分 → `game_won` + `match_over`（`GAMES_TO_WIN_MATCH=1`）
  - 终局后 `_is_match_over`/match guard 生效，后续得分忽略（复用 #291 机制）
  - 测试：20→21 触发 match_over；21 后 add_points 被忽略
- [x] **AC4: 同一帧的拆砖/穿墙不会重复计分**
  - 拆砖：每砖 `brick_destroyed` 恰好一次（#384 去重契约）；测试：同砖 destroy 两次 → 计一次
  - 穿墙：`_scored_this_frame` 守卫；测试：同帧双出界 → 计一次
  - 拆砖+穿墙同帧：两笔各一次；测试：模拟同帧两事件 → +1 与 +3 各一次
- [x] **AC5: GameManager 可查询每方拆砖数、穿墙数，供结算/失败屏使用**
  - `player_bricks`/`ai_bricks`/`player_wall_passes`/`ai_wall_passes` 公开计数
  - `get_bricks_destroyed(side)`/`get_wall_passes(side)` 查询接口
  - `reset_game()`/`reset_match()` 重置全部计数
  - 测试：拆 2 砖 + 1 穿墙 → 计数 2/1；reset 后归零

### 边界条件（Edge Cases，≥5）

1. **发球后未碰挡板先拆砖** — `serve()` 按发球方向初始化 `last_toucher`（向上→"player"、向下→"ai"），拆砖分有归属；若实现遗漏，`last_toucher=""` 时拆砖分归属**攻击方默认值**（向上发球=player），并 push_warning 提示
2. **球碎砖后同帧出界（拆砖+穿墙同帧）** — 两笔独立计分各一次（AC4）；球已出界并 `serve()` 重置，`last_toucher` 按新发球方向重置
3. **同帧双砖同碎** — #384 契约按砖身份去重，`brick_destroyed` 每砖一次 → 拆砖分每砖一次（AC4）
4. **砖墙打空（wall_cleared）** — 本 Issue 不消费 `wall_cleared`（归 #386）；墙空后球直飞出界仍按穿墙 3 分（MVP 语义，重生归 #386）
5. **21 分制下的局/场语义** — `GAMES_TO_WIN_MATCH=1`：21 分即 `match_over`，`player_games_won` 变为 0/1 二元；`get_winner()` 逻辑不变（≥1 局即胜）
6. **Main.tscn 无 BreakoutGrid 节点（#393 未接线时）** — `get_node_or_null("../BreakoutGrid")` 返回 null → 静默跳过拆砖连接，穿墙分/经典计分不受影响（test_main_scene 回归）
7. **HUD 总分与双区** — 本 Issue 保证 `score_changed` 总分含拆砖/穿墙；HUD 拆砖/穿墙双区视觉归 #392，不在此实现
8. **post-match guard** — 21 分终局后 `match_over` 已发，`_is_match_over` 抑制后续 `score`/`brick_destroyed` 计分（复用 #291 机制，brick_destroyed 路径同样检查）

### 失败路径（≥3）

1. **拆砖分归属错误（last_toucher 为空/过期）** — `serve()` 重置 last_toucher 的时序遗漏 → 拆砖分落空。对策：`_on_brick_destroyed` 中 `last_toucher` 为空时按发球方向兜底（见边界 1）+ push_warning；测试覆盖发球直拆砖
2. **计分重复（同砖两次 destroy / 同出界两次 score）** — 依赖 #384 去重与 `_scored_this_frame`；ScoringManager 侧不再加第二道守卫（保持单一来源），测试覆盖
3. **21 分阈值跨帧竞态** — 同帧 player 与 ai 先后 add_points 均达 21？实际不可能（每帧最多一次 score 事件），但 `_check_game_win` 用 `elif` 保证只判一个 winner（现有实现已如此，回归确认）
4. **GAMES_TO_WIN_MATCH=1 后 match 状态残留** — `reset_match()` 必须同时重置新计数（拆砖/穿墙），否则结算/失败屏读到旧 run 数据；测试覆盖 reset 后全部归零

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|:---:|
| #383 轴交换+竖屏（720×1280） | ✅ CLOSED，PR #409 已合并 | Low — 出界=穿墙的物理前提已就绪 |
| #384 砖墙系统（brick_destroyed 契约） | ⚠️ **CLOSED（PRD #411 + DESIGN #414 已合并），但实现代码未出现在 main**（2026-08-13 research 核查：`mini-pong/gdscripts/` 无 `breakout_grid.gd`/`brick.gd`，`run_tests.gd` 无砖墙套件） | **Med-High** — `brick_destroyed` 信号契约以 DESIGN 为准；实现阶段需先确认 #384 落地（或与 #384 实现同步），否则拆砖分无事件源 |
| #393 主场景组装（Main.tscn 接线） | ⏳ workflow/backlog，未开始 | Med — 本 Issue 用 `get_node_or_null` best-effort 连接 + 隔离测试，不阻塞 AC1-AC5 验收；#393 落地后场景内自动生效 |

```
依赖链: #383 (已合并) → #384 (PRD/DESIGN 已合并，实现待确认) → #385 (本 Issue) ──► #386/#391/#393 消费计数与查询接口
```

**⚠️ 实现阶段前置检查（重要）：** implement agent 动手前必须执行 `ls mini-pong/gdscripts/breakout_grid.gd` 确认 #384 实现已落地；若缺失，需先协调 #384 实现合入（或在本 Issue 分支内以隔离测试模拟 brick_destroyed 信号验证计分逻辑，场景内接线仍归 #393）。

**准备清单：**
- [ ] 确认 #384 实现状态（`breakout_grid.gd`/`brick.gd` 是否在 main）
- [ ] 确认 #393 未并行修改 ScoringManager/Main.tscn（避免接线冲突）
- [ ] constants.gd 常量组先行（#295 单一事实源惯例）

---

## 7. Spike / 实验（研究期已执行）

### 实验 1：竖屏出界=穿墙的物理事实验证

- **问题：** AC2 的"穿越砖墙"判定是否可以零检测复用出界得分路径？
- **方法：** 核查 #384 DESIGN 布局算法（砖墙横跨 720px 铺满，`cols = floor(720/(size.x+gap))`）+ Main.tscn 左右墙 StaticBody2D（X 反弹）
- **结果：** ✅ 成立 —— 砖墙 X 方向铺满全屏、左右墙封死 X 轴，球到达对方底线必须穿过砖墙平面（碎砖或穿缺口）；出界即穿墙
- **影响：** Approach A 采用"出界统一 3 分"，不做逐帧穿越检测（节省 ~1 周复杂度）

### 实验 2：paddle.mode 可作最后触球方判定源

- **问题：** ball 如何零配置知道最后碰的挡板是谁？
- **方法：** 读 `paddle.gd`（`enum Mode { PLAYER=0, AI=1 }` + `@export var mode`）与 Main.tscn（PlayerPaddle 默认 mode=0、AIPaddle `mode = 1`）
- **结果：** ✅ 成立 —— `_on_area_entered` 的 paddles 分支中 `area.mode == paddle.Mode.PLAYER` 即可判定，无需新增组/属性
- **影响：** `last_toucher` 实现成本 ~5 行，AC1 归属判定可靠

### 实验 3：GAMES_TO_WIN_MATCH=1 的终局语义等价性

- **问题：** 21 分制下保留 games 概念（=1）与删除 games 概念，对现有链路影响差异？
- **方法：** 读 `game_manager.gd` 终局链（`_check_game_win` → `_win_game` → games++ → `match_over`）与 `test_game_manager.gd` 15 例、`test_scoring_manager.gd` 42 例
- **结果：** ✅ 保留 + 置 1 的改动面最小（2 行常量 + 0 测试重构）；删除 games 需重构 #291 两套测试 57 例 + FSM 监听，收益趋近于零
- **影响：** AC3 采用 `GAMES_TO_WIN_MATCH=1`，`match_over` 承载 21 分终局

---

## 8. 延续上下文（Continuation Context）

### 系统状态（implement agent 接手时）

- 基础：720×1280 竖屏（#383 已合并）、经典计分链路 `ball.score(side)` → ScoringManager → GameManager（5 分/2 局，constants.gd:76-77）
- **#384 实现未在 main**（research 核查）：`breakout_grid.gd`/`brick.gd` 不存在，`brick_destroyed` 信号契约以 `docs/DESIGN/384-breakout-grid-brick-wall.md` §3.4 为准 —— 动手前先确认
- Main.tscn 无 BreakoutGrid 节点：本 Issue 用 `get_node_or_null("../BreakoutGrid")` best-effort 连接，场景内接线归 #393

### 实现顺序（建议）

1. `constants.gd`：`POINTS_BRICK=1`、`POINTS_WALL_PASS=3`、`POINTS_TO_WIN_GAME=21`、`GAMES_TO_WIN_MATCH=1`
2. `ball.gd`：`last_toucher` + paddles 分支记录 + `serve()` 方向初始化（~5 行，不动既有分支）
3. `game_manager.gd`：`add_points(winner, pts)`（`add_score` 改为转发或保留兼容）、拆砖/穿墙计数 + 查询接口、`_check_game_win` 21 分、reset 重置新计数
4. `scoring_manager.gd`：`_on_ball_score` 分值 3、新增 `_on_brick_destroyed`（last_toucher → +1 + 计数）、`_ready()` 连接 brick_destroyed
5. 测试：test_game_manager（21 分/计数/查询）、test_scoring_manager（3 分/拆砖消费/同帧防重）、可选 test_dual_scoring 集成套件；`run_tests.gd` 注册
6. 本地验证：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含既有 14 套件回归）；`godot --path mini-pong/ --headless --quit` 编译通过

### 交接给 plan agent 的关键点

- **分值/阈值**：拆砖 1 分（`POINTS_BRICK`）、穿墙 3 分（`POINTS_WALL_PASS`）、21 分终局（`POINTS_TO_WIN_GAME=21`、`GAMES_TO_WIN_MATCH=1`）
- **归属规则**：拆砖 → `ball.last_toucher`（`paddle.mode` 判定）；穿墙 → 出界得分方（side 映射，现有逻辑）
- **AC4 防重**：拆砖靠 #384 砖身份去重、穿墙靠 `_scored_this_frame`，ScoringManager 为唯一计分入口，**不要**加第二道守卫
- **AC5 接口**：`player_bricks`/`ai_bricks`/`player_wall_passes`/`ai_wall_passes` + `get_bricks_destroyed(side)`/`get_wall_passes(side)`；#391 失败屏/#390 波次转场将消费
- **边界**：不消费 `wall_cleared`（#386）；不改 Main.tscn（#393）；不改 HUD 双区视觉（#392）；`content_ownership: mechanical`
- **风险**：#384 实现落地状态（Med-High）—— plan/implement 阶段第一优先级确认

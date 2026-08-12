# PRD: [Integration] 主场景组装 — Main Scene Assembly (Rogue Pong Wave Edition)

> **Issue:** #393
> **标签:** enhancement, feature, gameplay, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#383/#384/#386/#390/#392 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验/基线证据补齐）
> **所有权:** `content_ownership: mechanical`（场景节点组装/信号接线/常量收敛为纯机械实现；波次数值、文案、配色归 taste-draft Issue）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2/§4.2（砖墙+波次+升级主玩法改造）、§3.3（霓虹 HUD）
> **前置依赖:** #383, #384, #385, #386, #387, #388, #389, #390, #391, #392（全部 CLOSED）
> **参考先例:** `docs/PRD/295-main-scene-assembly.md`（同题「主场景组装」旧版 Pong 先例，524 行，8 段式）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：10 个前置组件中 8 个已实现，但其中 2 个（#384 BreakoutGrid、#390 波次转场）的 issue 虽已关闭，代码从未落地；Main.tscn 已有 8 个组件实例，缺 3 个节点接线（BreakoutGrid / WaveController / 波次转场），且失败屏内联节点落后于 #391 实现。**

#### Phase 1：Main.tscn 节点清单（2026-08-13 源码核查）

当前 `mini-pong/scenes/Main.tscn`（约 200 行）节点树：

```
Game (Node2D)
├── WorldEnvironment (instance of world_environment.tscn)
├── AtmosphereLayer (CanvasLayer, layer=0)
│   └── RainCurtain (instance of rain_curtain.tscn)          ← #389 ✅
├── LeftWall / RightWall (StaticBody2D, groups=[walls])
├── Ball (instance of ball.tscn)                             ← #287 ✅
├── PlayerPaddle (instance of player_paddle.tscn)            ← #288 ✅
├── AIPaddle (instance of player_paddle.tscn, mode=1)        ← #290 ✅
├── ScoringManager (Node, scoring_manager.gd)                ← #385 ✅
├── GameStateMachine (Node, game_state_machine.gd)           ← #294 ✅
│   └── NodePath exports → StartMenu/GameHUD/GameOverScreen/PauseOverlay/Ball/PlayerPaddle/AIPaddle/ScoringManager
├── ScoreZoneTop / ScoreZoneBottom (Area2D, mask=4)          ← #295/#383 ✅
├── ScoreFlash (Node + ScoreFlashRect, score_flash.gd)       ← #289 ✅
├── StartMenu (CanvasLayer, layer=1, 内联节点树, start_menu.gd) ← #292 ⚠️ ui_start_menu.tscn 存在但未用
├── GameHUD (instance of ui_game_hud.tscn)                   ← #392 ✅
├── GameOverScreen (CanvasLayer, layer=1, 内联节点树, game_over_screen.gd) ← #391 ⚠️ 落后实现
├── PauseOverlay (CanvasLayer, layer=10)                     ← #296 ✅
└── UpgradePickUI (instance of ui_upgrade_pick.tscn)         ← #388 ✅ (layer 未设=1，应=2)
```

#### Phase 2：Gap 分析（组件 | Issue | 代码状态 | Main.tscn 状态 | 缺失）

| 组件 | Issue # | 代码状态 | Main.tscn 状态 | 缺失 |
|------|---------|:-------:|:-------------:|------|
| BreakoutGrid 砖墙 | #384 | ❌ **未落地**（issue 已关、无 impl PR；仅 DESIGN `docs/DESIGN/384-breakout-grid-brick-wall.md`） | ❌ 无节点 | `brick.gd`+`brick.tscn`、`breakout_grid.gd`+`breakout_grid.tscn`、`ball.gd` bricks 分支、`constants.gd` BRICK_* 常量组、Main.tscn 节点、`test_breakout_grid.gd` |
| GameManager | #385/#386 | ✅ autoload（`project.godot`） | ✅ 无需节点（autoload） | — |
| UpgradePool | #387 | ✅ autoload | ✅ 无需节点（autoload） | — |
| 3选1升级UI | #388 | ✅ `upgrade_pick_ui.gd` | ✅ 已实例化 | 实例 layer 未设（默认 1，常量 `UPGRADE_UI_LAYER=2`） |
| 雨幕 | #389 | ✅ `rain_curtain.gd`（含 `set_wave_factor`） | ✅ `AtmosphereLayer/RainCurtain` | — |
| 波次循环 WaveController | #386 | ✅ `wave_controller.gd`（组 `wave_controllers`，`get_node_or_null` 容错） | ❌ **无节点** | Main.tscn 添加 WaveController 节点（`../BreakoutGrid`/`../AIPaddle`/`../AtmosphereLayer/RainCurtain` 相对路径即解析） |
| 波次转场 | #390 | ❌ **未落地**（无脚本/无场景/无 DESIGN；仅 PRD `docs/PRD/390-wave-transition.md`） | ❌ 无节点 | `wave_transition_controller.gd`、`wave_transition.tscn`、`WAVE_TRANSITION_*` 常量组、Main.tscn 节点、`test_wave_transition.gd` |
| 失败屏 | #391 | ✅ `game_over_screen.gd`（win/fail 双分支 + run 数据） | ⚠️ 内联 GameOverScreen **缺** `FailurePhraseLabel`/`RunStatsLabel`（`ui_game_over.tscn` 含此二 Label 但未被实例化） | 换用 `ui_game_over.tscn` 实例，或补齐内联 Label |
| 霓虹 HUD | #392 | ✅ `game_hud.gd`（容错消费 grid 3 信号） | ✅ 已实例化 | 剩余砖数/波次显示依赖 #384 落地后才有数据 |
| 轴交换+竖屏 | #383 | ✅ 720×1280 竖屏布局 | ✅ 坐标已对齐（PR #409） | — |
| StartMenu | #292 | ✅ `start_menu.gd` | ✅ 内联可用（`ui_start_menu.tscn` 未用） | 可选：统一为实例化（非必需） |

**证据链（代码未落地确认）：**
- `wave_controller.gd` 头部注释：「#384 实现未落地期」「grid 未接线时波次状态机照常推进…生成环节跳过并 push_warning」
- `brick_upgrade_hooks.gd` 头部注释：「#384 BreakoutGrid 代码未落地 → 契约先行」
- `git log --all` 无任何 brick/breakout 实现提交（仅 PRD #411 / DESIGN #414 文档提交）
- `git ls-tree origin/plan/384-breakout-grid` 仅有 docs，无 gdscripts 代码
- `gdscripts/` 无 `breakout_grid.gd` / `brick.gd` / `wave_transition_controller.gd`

**预接线代码（已就绪、只等节点）**：ScoringManager、WaveController、GameHUD、UpgradePickUI 均以 `get_node_or_null("../BreakoutGrid")` + `has_signal`/`has_method` 双守卫消费 #384 契约——节点一挂即自动接线，零改脚本。

#### Phase 3：信号链审计

```
Ball.score(side) [ball.gd _on_score_zone]
    │
    ▼
ScoringManager._on_ball_score(side)                       ← ✅ _ready 中 ball.score.connect
    ├── GameManager.add_score(winner, amount, kind)       ← ✅ autoload
    │     ├── score_changed(p,a) ──► GameHUD._on_score_changed     ← ✅
    │     ├── brick_scored(side) ──► GameHUD._on_brick_scored      ← ✅ (#392)
    │     ├── pierce_scored(side) ──► GameHUD._on_pierce_scored    ← ✅ (#392)
    │     ├── wave_started(idx) ──► GameHUD._on_wave_started       ← ✅ (#392)
    │     │                    └──► WaveTransition (「第 N 道墙」)    ← ❌ #390 未实现
    │     ├── wave_settled(idx) ──► UpgradePickUI.open              ← ✅ (#388)
    │     └── match_over(winner) ──► GameStateMachine._on_match_over ← ✅
    │                          └──► GameOverScreen._on_match_over   ← ✅ (#391)
    └── scored(winner) ──► GameStateMachine._on_scored   ← ✅
                     └──► ScoreFlash._on_score_changed   ← ✅

BreakoutGrid.brick_destroyed(brick, pos)                  ← ❌ 组件未落地；消费者已就绪
    ├── ScoringManager._on_brick_destroyed → add_score(toucher,1,"brick")  ← ✅ 代码就绪
    └── GameHUD._on_grid_brick_destroyed（剩余砖数）       ← ✅ 代码就绪
BreakoutGrid.wall_cleared()                               ← ❌ 组件未落地；消费者已就绪
    ├── WaveController._on_wall_cleared → settle_wave()   ← ✅ 代码就绪
    └── GameHUD._on_grid_wall_cleared                     ← ✅ 代码就绪
BreakoutGrid.wall_generated(remaining)                    ← ❌ 组件未落地（DESIGN #384 增补契约）；消费者已就绪
    └── GameHUD._on_grid_wall_generated（剩余砖数播种）     ← ✅ 代码就绪

WaveController（脚本就绪 #386，节点未挂载）
    ├── ../BreakoutGrid  → get_node_or_null ⚠️ null 至 #393 接线
    ├── ../AIPaddle      → ✅ 存在
    ├── ../AtmosphereLayer/RainCurtain → ✅ 存在
    ├── GameManager.settle/begin/end_wave + is_run_over  ← ✅ autoload
    ├── rain_curtain.set_wave_factor(idx)                ← ✅ #389 契约
    └── generate_wave(厚度,0,-1)                          ← ❌ 依赖 #384

UpgradePickUI（实例化 ✅）
    ├── GameManager.wave_settled.connect(open)           ← ✅
    ├── UpgradePool.get_candidates(3) / apply(id)        ← ✅ autoload
    └── group("wave_controllers").advance_settlement()   ← ⚠️ 无节点时 no-op；WaveController 挂载后激活

GameOverScreen（#391）
    └── GameManager.match_over → 分档选句 + run 三项（波次/拆砖/穿墙） ← ✅ autoload 查询 API
        ⚠️ 内联节点缺 FailurePhraseLabel/RunStatsLabel → 文本不显示（get_node_or_null 兜底不崩）
```

**Bonus 审计 — 常量重复检测**：`grep -rh '^const [A-Z_]' gdscripts/*.gd` 无重复定义（`WIN_SCORE` 仅 constants.gd 定义 + game_manager.gd 本地别名引用，属既有模式）。**常量缺口**：无 `BRICK_*` 组（#384 DESIGN §4.2：BRICK_SIZE 64×24 / BRICK_GAP 4 / BRICK_MIN_DIM 14）、无 `WAVE_TRANSITION_*` 组（#390 PRD §4：FADE_IN 0.5 / HOLD 1.0 / FADE_OUT 0.5 / 字号 112/40 / 描边 10 / DECISIVE_SCORE 18 / JSON 路径）。

**测试基线（2026-08-13 实跑）**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` → **1781 passed, 0 failed**，含 Auto-Play 100 局（AI vs AI）。全部现有套件在缺 #384/#390 下仍绿——容错守卫设计有效；「10 局无脚本错误」在组装后需重新验证完整波次循环路径。

### 1.2 预期行为（验收条件，源自 Issue #393）

1. **AC1 — Main.tscn 可直接运行完整一局，不需要额外手工连线** — 单场景自足：所有场景侧节点（BreakoutGrid/WaveController/波次转场/HUD/失败屏/升级 UI）挂在 Main.tscn，autoload（GameManager/UpgradePool/AudioEngine）由 project.godot 提供；`run/main_scene` 已指向 Main.tscn
2. **AC2 — 墙清空→波次结算→升级→新墙→AI 增强的循环完整** — `wall_cleared`（#384）→ `settle_wave` → `wave_settled` → 升级 UI（#388）→ `advance_settlement` → `begin_wave`（wave_started → 转场 #390）→ `generate_wave`（更厚）→ AI 收紧（#386）
3. **AC3 — HUD 分数/波次/剩余砖数随信号实时更新** — GameManager 4 信号（score_changed/brick_scored/pierce_scored/wave_started）+ grid 3 信号（brick_destroyed/wall_cleared/wall_generated）全部有消费方
4. **AC4 — 失败屏与获胜状态均可到达，无孤立信号或错误** — match_over 双消费者（FSM→GAME_OVER 态、GameOverScreen→win/fail 双分支）；失败屏 Label 补齐
5. **AC5 — 运行 10 局无脚本错误/空引用，场景树无泄漏** — Auto-Play 100 局基线（现状 0 错误）+ 组装后波次路径验证；`clear_wall()` 快照遍历 + `is_instance_valid` 防 queue_free 泄漏（#384 契约）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 完整一局 | 每局 | 菜单 → SPACE → 发球 → 拆砖（brick_destroyed→+1 分）→ 墙空（wall_cleared）→ 结算 → 3 选 1 升级 → 转场「第 2 道墙」→ 更厚新墙 + AI 更难 → … → 21 分终局 |
| B | 失败/获胜 | 每局末 | 任一方到 21 → match_over → 失败屏（玩家败：分档选句+三项 run 数据 / 玩家胜：获胜文案）→ SPACE 回菜单 |
| C | HUD 实时性 | 全程 | 分数/拆砖/穿墙/波次/剩余砖数随信号即时更新，零轮询（#392 契约） |

### 1.4 技术约束（继承自 Issue #393 + 依赖链）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，`run/main_scene="res://scenes/Main.tscn"`，720×1280 竖屏，resizable=false，gl_compatibility 由根 project.godot 指定） |
| 布局语义 | 砖墙横跨 720px，`wall_y=640`（`GRID_WALL_Y`）；墙带判定 `WALL_BAND_HALF_HEIGHT=22`（#385）；球层 bit 3 / 砖层 bit 2 / 墙拍层 bit 1（#384 核查：球 mask 已含 bit 2，零改动） |
| 信号契约 | 消费方全部以 `get_node_or_null` + `has_signal`/`has_method` 双守卫容错（WaveController/ScoringManager/GameHUD/UpgradePickUI 均如此）——接线是纯增量，无破坏面 |
| FSM 不变项 | 不扩展 FSM（DESIGN #386 决策 1）；转场是呈现层，走信号消费模式（#390 PRD §4.1 Approach A 演员冻结） |
| 内容边界 | 副句文案归 #396（`content/wave_failure_text.json`，机械只读）；升级文案归 #395（`upgrade_pool.json`）；本 Issue 零硬编码文案 |
| autoload | GameManager/UpgradePool/AudioEngine 已在 project.godot 注册——**不创建对应场景节点** |
| 组装边界 | 本 Issue 不改 8 个已落地组件的脚本逻辑（ball.gd bricks 分支除外——它是 #384 契约的组成部分，见 §1.1 缺口） |

### 1.5 开源优先调研结果（Issue body 要求：粒子、shader、UI 主题、砖块生成）

调研时间 2026-08-13，检索范围 Godot Asset Library（godotengine.org/asset-library/api，godot_version=4.7）+ GitHub（带 auth 搜索，按 star 排序）：

- **Godot Asset Library**：`breakout` → **0 结果**；`brick` → 2 条（Logic Bricks 4.2 Tools——LEGO 风格逻辑砖编辑器，非可破坏地形；Scene Manager——无关）；`neon` → 4 条（QTI Neon/NeonSceneRunner/NeonGameModes/NeonPageController，全部为编辑器工具/脚本 demo，非运行时 UI 主题）；`rain` → 36 条均为 3D 地形/SDK 工具类资产，无 2D 雨幕
- **GitHub 搜索**：`godot breakout` → 288 仓库，全部为**完整游戏克隆**（最高 didier-v/breakable 64⭐，完整 Breakout 游戏 demo 而非可插拔砖墙生成模块）；`godot brick breaker` → 59 仓库，同样为完整游戏克隆（最高 claucambra/BrickBuster 10⭐）；`godot neon ui theme` → 1 条（Shilo/NeoCade-Theme **0⭐**，Godot 4.6 街机风格 UI 主题，无成熟度证据）；`godot rain particles 2d` → 0 结果
- **社区/论坛**：Godot 官方论坛与 r/godot 无「可复用砖墙生成/波次转场覆盖层」成熟分发物；Godot 内置 `Tween`/`LabelSettings`（描边）/`GPUParticles2D`/`StaticBody2D` 信号完全覆盖组装所需能力
- **与前置 PRD 结论一致**：#384（砖墙）、#389（雨幕）、#390（转场）、#392（霓虹 HUD）研究阶段分别做过同结论检索——**均无可直接复用的成熟插件/模板，全部第一方实现，零第三方依赖**。唯一有参考价值的候选是 `pirachute/godot-weather-2D`（93⭐，其「运行时改 amount 会重启粒子系统」警告被 #389 采纳为技术证据），与 #389 自研实现不冲突
- **结论**：**无可复用资产**，符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。组装所需全部能力 = Godot 4.7 内置 + 项目既有 8 个第一方组件

### 1.6 Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（`OBSIDIAN_VAULT_PATH`，WebDAV）。本会话根目录可列（`Knowledge Ocean`/`copilot` 等），但 `Knowledge Ocean/wiki/` 子目录读取为空/超时——与 #384/#390 研究会话同症状（挂载层限制），未能直接检索到组装相关笔记
- **兜底（设计文档层）**：组装相关的全部体验语义已由项目文档固化——`docs/PLAN-rogue-pong.md` §2（砖墙/波次/升级主玩法）§3.3（霓虹 HUD）、GDD `docs/GAME_DESIGN/10-SCENE-LAYOUT.md`（场景布局）、`24-WAVE-CYCLE.md`（波次信号契约表）、`23-UPGRADE-POOL.md`、`25-UPGRADE-UI.md`、`22-RAIN-CURTAIN.md`；#392 PRD §1.6 成功检索到的「90 年代地摊文艺」克制反例约束（描边克制/微投影而非重阴影/信息密度低）已内化为 HUD/转场 UI 的既定视觉坐标
- 后续阶段（plan/implement）如需可重试挂载直接检索

### 1.7 范围边界（与相邻 PRD 解冲突）

| PRD/Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #295 主场景组装（旧 Pong） | 旧版 game.tscn→Main.tscn 重命名、ScoreZone、ScoreFlash、常量集中 | ✅ 历史先例；本 PRD 只引用其结构与方法，不重做其已交付内容 |
| #384 砖墙系统 | 砖墙生成算法/碰撞/信号契约（DESIGN 已定稿） | ❌ 不重设计 API——只把 DESIGN 契约**落地为代码**并挂入 Main.tscn（缺口补齐） |
| #385 双得分制 | 计分/终局判定/查询 API | ❌ 不改 game_manager.gd/scoring_manager.gd 逻辑（已 ✅） |
| #386 波次循环 | 波次状态机/难度递增 | ❌ 不改 wave_controller.gd（已 ✅）——只挂节点 |
| #387 升级池架构 | 升级池数据枢纽/9 定义 | ❌ 不改 upgrade_pool.gd（已 ✅ autoload） |
| #388 3选1升级UI | 卡片交互/焦点/reveal | ❌ 不改 upgrade_pick_ui.gd（已 ✅）——只补实例 layer |
| #389 动态雨幕 | 雨幕粒子公式/波次因子 | ❌ 不改 rain_curtain.gd（已 ✅） |
| #390 波次转场 | 转场呈现/暂停/副句读取（PRD 已定稿方案） | ❌ 不重设计——按 PRD §4 推荐（演员冻结+Tween 三段式+分档选句）**落地为代码**并挂入 Main.tscn（缺口补齐） |
| #391 失败屏 | win/fail 双分支/run 数据 | ❌ 不改 game_over_screen.gd（已 ✅）——只修正 Main.tscn 内联节点落后问题 |
| #392 霓虹 HUD | 三区布局/按类信号 | ❌ 不改 game_hud.gd（已 ✅）——grid 信号数据源由 #384 补齐后自动激活 |
| #395/#396 文案 | 升级文案/波次副句内容（taste-draft） | ❌ 只读 JSON，不拥有/不修改文案 |

**本 PRD 的独有范围**：Main.tscn 节点树结构、NodePath 配置、ext_resource 引用、信号接线完整性、两个未落地组件的契约落地（#384/#390）、失败屏内联节点修正、运行验证（10 局/场景树泄漏）。

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 现状 | 成因 | 证据 |
|------|------|------|
| Main.tscn 已有 8 组件但缺 3 节点 | 历次实现按「组件独立交付 + 容错防崩」策略推进，接线被 #393 显式留白 | wave_controller.gd/scoring_manager.gd 注释「接线归 #393」；#384 PRD §1.5「接线归 #393」 |
| #384/#390 代码未落地但 issue 已关 | 实现阶段缺失：`git log` 显示两 issue 仅 research/plan 文档提交；#384 关闭于 2026-08-12（closed_by devvi，无 impl PR） | `git log --all` 无 brick 实现提交；`origin/plan/384-breakout-grid` 仅 docs；#390 无 DESIGN doc |
| 容错守卫普遍存在 | 组件间以 `get_node_or_null`+`has_signal` 解耦，未接线时不崩只 warn | wave_controller.gd「push_warning」、game_hud.gd「_warned 只警告一次」、scoring_manager.gd「容错连接」 |
| 失败屏内联节点落后 | #391 实现（PR #439）交付了 `ui_game_over.tscn`（含 FailurePhraseLabel/RunStatsLabel），但 Main.tscn 仍用 #292 时代的内联节点树 | Main.tscn 内联 GameOverScreen 仅 WinnerLabel/Spacer/RestartPromptLabel |

### 2.2 为什么现在改

1. **MVP 最后一环**：Issue #393 是 rogue-pong 主玩法的收口——10 个组件首次协作的关键节点；AC2 的完整循环（墙清空→结算→升级→新墙→AI 增强）必须依赖 #384 落地
2. **契约已全部定稿**：#384 DESIGN（PR #414）给出 BreakoutGrid 完整 API（generate_wave/clear_wall/brick_destroyed/wall_cleared/wall_generated/@export 参数）；#390 PRD（PR #429）给出转场完整方案（演员冻结/Tween 三段/分档选句）——**本 Issue 是执行层，无设计决策**（Patch 19 参数契约→执行层模式：先例 #217）
3. **消费方全部就绪**：8 个组件的消费者代码已用守卫写好，只差节点存在——接线成本趋近于零，收益是完整可玩循环
4. **测试基线全绿**：1781 用例 0 失败证明既有组件稳定，风险集中在两个缺失组件的契约落地

### 2.3 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 新增 `gdscripts/breakout_grid.gd`+`brick.gd`+`wave_transition_controller.gd`、`scenes/brick.tscn`+`breakout_grid.tscn`+`wave_transition.tscn`；改 `constants.gd`、`ball.gd`（bricks 分支）、`Main.tscn`、`run_tests.gd`；**不碰** FSM、game_manager.gd、scoring_manager.gd、wave_controller.gd、upgrade_pool.gd、game_hud.gd、upgrade_pick_ui.gd、rain_curtain.gd 逻辑 |
| 引擎版本 | Godot 4.7.1；Tween/LabelSettings/GPUParticles2D 原生能力；JSON 用 `FileAccess`+`JSON.parse_string`（#396/#395 先例） |
| UI 语境 | 竖屏 720×1280；HUD 顶部 0–160px 条带 + 底部玩家区；转场文字居中 y≈640 安全区（#390 AC4） |
| 测试基线 | #346 修复后全绿；mock 模式（test_wave_cycle.gd 假 grid/AIPaddle/RainCurtain 契约子集）；headless 可跑 |
| 内容红线 | 副句/升级文案零硬编码（#396/#395 契约）；本 Issue 不评审文案 |

---

## 3. 影响分析

### 3.1 新文件

| 文件 | 用途 |
|------|------|
| `mini-pong/gdscripts/brick.gd` | 单砖（#384 DESIGN §4.1）：`destroy()` 幂等 → 通知 grid → `queue_free()`；`is_in_group("bricks")` |
| `mini-pong/gdscripts/breakout_grid.gd` | 网格管理器（#384 DESIGN §4.1）：`class_name BreakoutGrid`，@export 参数组，`generate_wave(thickness, layout, seed)`/`clear_wall()`/`_on_brick_destroyed`/`register_upgrade_hook`/`open_hole`/`blast_neighbors`（#387 钩子），信号 brick_destroyed/wall_cleared/wall_generated |
| `mini-pong/scenes/brick.tscn` | 单砖场景（StaticBody2D layer 2 + ColorRect + CollisionShape2D，64×24） |
| `mini-pong/scenes/breakout_grid.tscn` | 网格容器场景（Node2D + breakout_grid.gd） |
| `mini-pong/gdscripts/wave_transition_controller.gd` | 转场控制器（#390 PRD §4 推荐组合）：连接 wave_started → 演员冻结 → 读 JSON 选副句 → 2.0s Tween 三段 → 解锁 |
| `mini-pong/scenes/wave_transition.tscn` | 转场覆盖层（CanvasLayer + 全屏 ColorRect dim + 居中大字 Label + 副句 Label，LabelSettings 描边） |
| `mini-pong/tests/test_breakout_grid.gd` | 砖墙测试套件（mock ball + 布局/信号/再生/幂等用例，对照 DESIGN #384 §5） |
| `mini-pong/tests/test_wave_transition.gd` | 转场测试套件（短时长注入 + 选句纯函数断言，对照 PRD #390 §5） |

### 3.2 直接改动文件

| 文件 | 改动 | 性质 |
|------|------|------|
| `mini-pong/gdscripts/constants.gd` | 新增 `BRICK_*` 组（BRICK_SIZE 64×24/BRICK_GAP 4/BRICK_MIN_DIM 14，DESIGN #384 §4.2）+ `WAVE_TRANSITION_*` 组（FADE_IN 0.5/HOLD 1.0/FADE_OUT 0.5/字号 112+40/描边 10/DECISIVE_SCORE 18/JSON 路径，PRD #390 §4） | 增量 |
| `mini-pong/gdscripts/ball.gd` | `_on_body_entered` 新增 `bricks` 分支（~10 行）：dominant-axis 反弹 → `_bounce_cooldown` → `body.destroy()`（DESIGN #384 §4.2） | 增量（#384 契约组成部分） |
| `mini-pong/scenes/Main.tscn` | 添加 BreakoutGrid 实例（y=640）、WaveController 节点、WaveTransition 实例；GameOverScreen 换 `ui_game_over.tscn` 实例（或补齐 2 Label）；UpgradePickUI 实例设 `layer = 2` | 组装 |
| `mini-pong/tests/run_tests.gd` | 注册 `test_breakout_grid.gd` + `test_wave_transition.gd` | 增量 |
| `mini-pong/tests/test_main_scene.gd` | 补充节点断言（BreakoutGrid/WaveController/WaveTransition 存在 + NodePath 正确） | 增量 |

### 3.3 间接影响（需回归验证）

| 系统 | 影响 | 验证 |
|------|------|------|
| HUD 剩余砖数/波次显示 | grid 3 信号激活后从「—」变为真实数据 | test_hud.gd 全量回归 |
| 拆砖分/穿墙分 | brick_destroyed 激活拆砖分路径（此前仅出界分可测） | test_scoring_manager.gd + test_dual_scoring.gd 回归 |
| 波次循环 | wall_cleared → 结算 → 升级 → 新墙全链激活（此前 mock grid） | test_wave_cycle.gd 回归（mock 仍可用）+ 新集成用例 |
| 升级效果 | grid 类效果（open_hole/blast_neighbors）从 no-op 变为真实 | test_upgrade_pool.gd 回归（TC-H1/H2） |
| 雨幕 | set_wave_factor 激活波次因子 | test_rain.gd 回归 |
| 自动对打 | 100 局基线需在波次路径下重跑（验证 AC5） | auto_play_test.gd |

### 3.4 数据流影响

数据流无拓扑变化：GameManager 仍是唯一状态权威（分数/波次/计数），场景侧节点均为信号消费者。变化仅在**信号源补全**——BreakoutGrid 成为 brick_destroyed/wall_cleared/wall_generated 的生产者（#384 契约），WaveTransition 成为 wave_started 的第二消费者（#390）。升级流：wave_settled → UpgradePickUI（暂停）→ apply → 恢复 → advance_settlement → 下一波（#388 已实现，节点接线后激活）。

### 3.5 文档更新

- `docs/GAME_DESIGN/INDEX.md` 无新增章节（#384/#390 章节由各自 issue 维护）；本 Issue 组装说明沉淀于 PRD 本身
- 若 `Main.tscn` 结构变化较大，同步 `docs/GAME_DESIGN/10-SCENE-LAYOUT.md` 场景树示意

---

## 4. 方案对比（组装策略）

### 4.1 Approach A：增量组装 + 缺口补齐（推荐）

在现有 Main.tscn 基础上：① 按 #384 DESIGN 契约落地 BreakoutGrid（brick.gd/tscn + breakout_grid.gd/tscn + ball.gd bricks 分支 + 常量）；② 按 #390 PRD 契约落地 WaveTransition（controller + tscn + 常量）；③ 添加 WaveController 节点；④ 修正失败屏内联节点为 `ui_game_over.tscn` 实例；⑤ UpgradePickUI 补 layer=2；⑥ 注册新测试 + 全量回归 + 100 局验证。

- Pros：改动面最小（8 个已落地组件零逻辑改动）；消费方守卫已就绪，接线零风险；契约（DESIGN #384/PRD #390）已定稿，实现无设计歧义；与 #295 先例同法（增量修复）
- Cons：一个 PR 内含两个「契约落地」实现，体量偏大（可拆为前置实现 PR + 组装 PR，见 §6.2）
- Risk: Low ／ Effort: 2–3 天

### 4.2 Approach B：从零重建 Main.tscn

丢弃现有场景树，按「理想结构」重写全部节点。

- Pros：结构最干净
- Cons：现有 8 组件实例 + NodePath 导出 + 测试断言（test_main_scene.gd 21 个 TC 断言节点坐标/形状）全部重写，回归面爆炸；#295 先例已证明增量路径成功
- Risk: High ／ Effort: 4–5 天
- **否决**

### 4.3 Approach C：仅接线，缺失组件留待后续 Issue

只添加 WaveController/失败屏修正/layer 修正，BreakoutGrid 与波次转场另开 Issue。

- Pros：本 PR 最小
- Cons：AC2（完整循环）/AC3（剩余砖数）/AC5（10 局波次路径）全部无法满足——组装验收失败；#384/#390 issue 已关闭，重开成本高且割裂契约
- Risk: High ／ Effort: 1 天（但验收不通过）
- **否决**

### 4.4 推荐组合汇总

| 决策点 | 推荐 | 依据 |
|--------|------|------|
| 组装策略 | A：增量 + 缺口补齐 | #295 先例成功；守卫就绪零风险 |
| BreakoutGrid 实现 | 按 DESIGN #384 契约逐条落地 | API/信号/参数已定稿（含 #392 增补 wall_generated） |
| 波次转场实现 | 按 PRD #390 推荐组合（演员冻结+Tween 三段+分档选句） | 上游约束（不扩展 FSM/不拥有文案）全守 |
| 失败屏 | Main.tscn 换 `ui_game_over.tscn` 实例 | 消除内联与实现的双份漂移（#391 交付物被闲置） |
| UpgradePickUI | 实例设 `layer=2`（`UPGRADE_UI_LAYER`） | 常量既定分层（HUD 1 之上、Pause 10 之下） |
| 实施粒度 | 单个组装 PR（内含两个契约落地，按 §8 顺序推进） | cron 自主流水线；#384/#390 无独立实现 PR 可依赖 |

---

## 5. 边界条件与验收

### 5.1 正常路径（AC 检查清单，映射 Issue body）

| AC | 检查方式 |
|----|---------|
| AC1 直接运行完整一局 | `godot --path mini-pong/` 启动 Main.tscn（`run/main_scene` 已指向）；`test_main_scene.gd` 断言新增节点存在 |
| AC2 循环完整 | 集成用例：mock 球拆完全墙 → 断言 settle_wave → wave_settled → 升级窗口打开 → 确认 → advance_settlement → begin_wave → 新墙生成 → AI 参数收紧 |
| AC3 HUD 实时更新 | test_hud.gd 回归 + 断言 brick_destroyed/wall_generated 驱动剩余砖数 Label |
| AC4 失败屏/获胜可达 | test_failure_screen.gd 回归 + FSM match_over 双消费者断言；失败屏 Label 文本实际渲染（RunStatsLabel/FailurePhraseLabel 存在性） |
| AC5 10 局无错误 | `auto_play_test.gd`（100 局基线）在组装后重跑 0 失败；`clear_wall()` 场景树泄漏检查（快照遍历 + is_instance_valid） |

### 5.2 边界情况（Edge Cases）

| # | 场景 | 处理 |
|---|------|------|
| 1 | 波次上限（WAVE_MAX_INDEX=99） | WaveController push_warning 停止推进（#386 已实现） |
| 2 | 发球直撞砖（无 last_toucher） | 砖碎反弹但不计分（#385 边界 2 已实现） |
| 3 | 同帧双砖/砖+出界 | 砖对象身份去重 + 帧守卫（#384/#385 契约） |
| 4 | 升级窗口打开期间到 21 分 | run-over 分支 end_wave_cycle，不生成新墙（#388 边界 5） |
| 5 | 决胜波副句 | 任一方 ≥18 → ws4（#390 分档覆盖） |
| 6 | JSON 缺失/解析失败 | 转场只显大字、副句留空；失败屏兜底短句（#396 容错契约） |

### 5.3 失败路径（Failure Paths）

| # | 场景 | 处理 |
|---|------|------|
| 1 | 节点未接线（守卫仍生效） | 全部消费方 get_node_or_null 兜底 + push_warning 一次；测试仍绿（现状即证明） |
| 2 | 终局后残留事件 | GameManager `_is_run_over` 守卫 return（#385 已实现） |
| 3 | queue_free 期间回调 | `is_instance_valid(brick)` 检查（#384 契约） |
| 4 | 转场中玩家按 Escape | 演员冻结惯例（非全局暂停）→ 无输入冲突面（#390 Approach A） |

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 说明 |
|------|:----:|------|
| #383–#392 全部组件 | ✅ CLOSED | 8 个已实现；#384/#390 契约文档已定稿（DESIGN/PRD）但代码未落地——本 PRD 将其列为**缺口补齐**而非重新设计 |
| Godot 4.7.1 | ✅ | 本机 `/usr/local/bin/godot` 实测 |
| 测试基线 | ✅ | 1781 passed / 0 failed（2026-08-13 实跑） |

### 6.2 阻塞（Blocks）

| 阻塞项 | 说明 | 缓解 |
|--------|------|------|
| #384 代码未落地 | 无 brick/breakout_grid 实现，AC2/AC3/AC5 依赖其契约 | 本 PRD §8 Phase 1 按 DESIGN #384 契约落地（API 已定稿，零设计歧义） |
| #390 代码未落地 | 无转场实现，AC2 的「新墙仪式感」缺失 | 本 PRD §8 Phase 2 按 PRD #390 推荐组合落地 |
| 内联失败屏落后 | FailurePhraseLabel/RunStatsLabel 缺失 | §8 Phase 3 换 `ui_game_over.tscn` 实例 |

**实施粒度决策**：`workflow-chain` 对已关闭的 #384/#390 无法再触发 label 流转，故契约落地必须并入 #393 组装 PR（§4.4 依据），而非另开 Issue。

### 6.3 依赖链

```
#383 竖屏 → #384 砖墙 → #385 双得分 → #386 波次循环 → #387 升级池 → #388 升级UI
              └→ #389 雨幕 ──┘                        └→ #390 转场
                                                        └→ #391 失败屏 → #392 霓虹HUD
                                                                         ↓
                                                              #393 主场景组装（本 Issue）
```

---

## 7. Spike / 实验

按 depth/standard 惯例（#295/#390 同例）跳过独立 spike——两个待落地组件的方案均已由前置文档定稿并经其研究阶段验证：

- **#384**：DESIGN #414 已含碰撞层核查（球 mask bit 2 已含砖层）、布局算法（GAPS/OFFSET/HOLES）、信号恰好一次守卫——研究期实验已完成
- **#390**：PRD #429 §7 已含 Tween 三段时长可测性、演员冻结 headless 安全性实验
- **本 PRD 研究期实跑基线**：全量测试 1781 通过 + Auto-Play 100 局（0 脚本错误）——作为 AC5 的组装前对照

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

组装完成时，rogue-pong MVP 的 10 个组件全部接入 Main.tscn，形成完整可玩闭环（墙清空→结算→升级→新墙→AI 增强→21 分终局）。GameManager/UpgradePool/AudioEngine 为 autoload；场景侧 11 个节点全部挂在 Main.tscn 单一场景。

### 关键文件清单（实施 agent 需要操作的文件）

| 优先级 | 文件 | 操作 |
|:------:|------|------|
| P0 | `mini-pong/gdscripts/breakout_grid.gd` | **CREATE** — 按 DESIGN #384 §4.1 契约（@export 参数/信号 3 个/API 6 个） |
| P0 | `mini-pong/gdscripts/brick.gd` | **CREATE** — 单砖 destroy() 幂等 |
| P0 | `mini-pong/scenes/brick.tscn` / `breakout_grid.tscn` | **CREATE** — StaticBody2D layer 2 / Node2D 容器 |
| P0 | `mini-pong/gdscripts/wave_transition_controller.gd` | **CREATE** — 按 PRD #390 §4 推荐组合 |
| P0 | `mini-pong/scenes/wave_transition.tscn` | **CREATE** — CanvasLayer + 大字/副句 Label（LabelSettings 描边） |
| P0 | `mini-pong/gdscripts/constants.gd` | **MODIFY** — 新增 `BRICK_*` + `WAVE_TRANSITION_*` 常量组 |
| P0 | `mini-pong/gdscripts/ball.gd` | **MODIFY** — `_on_body_entered` 新增 bricks 分支（~10 行） |
| P0 | `mini-pong/scenes/Main.tscn` | **MODIFY** — 加 BreakoutGrid/WaveController/WaveTransition 节点；失败屏换 `ui_game_over.tscn` 实例；UpgradePickUI `layer=2` |
| P1 | `mini-pong/tests/test_breakout_grid.gd` / `test_wave_transition.gd` | **CREATE** — 新套件 |
| P1 | `mini-pong/tests/run_tests.gd` | **MODIFY** — 注册 2 个新套件 |
| P1 | `mini-pong/tests/test_main_scene.gd` | **MODIFY** — 补充节点存在性/NodePath 断言 |
| P2 | `docs/GAME_DESIGN/10-SCENE-LAYOUT.md` | **MODIFY** — 场景树示意同步（可选） |

### 实施顺序（推荐）

```
Phase 1: BreakoutGrid 契约落地（#384，纯增量，可独立验证）
  1. constants.gd BRICK_* 组（BRICK_SIZE 64×24 / BRICK_GAP 4 / GRID_WALL_Y 已有 / BRICK_MIN_DIM 14）
  2. brick.gd + brick.tscn（StaticBody2D layer 2, group "bricks", 64×24, destroy() 幂等）
  3. breakout_grid.gd + breakout_grid.tscn（@export 参数 / BrickLayout 枚举 GAPS/OFFSET/HOLES /
     generate_wave(thickness, layout, seed) 先 clear_wall() / brick_destroyed / wall_cleared 恰好一次 /
     wall_generated(remaining) 末尾 emit / register_upgrade_hook + open_hole + blast_neighbors（#387 钩子注册表））
  4. ball.gd bricks 分支（dominant-axis 反弹 → body.destroy()）
  5. test_breakout_grid.gd（对照 DESIGN §5 用例）+ run_tests.gd 注册 → 全量回归

Phase 2: WaveTransition 契约落地（#390，纯增量，可独立验证）
  1. constants.gd WAVE_TRANSITION_* 组（0.5/1.0/0.5 三段 / 112+40 字号 / 10 描边 / DECISIVE_SCORE 18 / JSON 路径）
  2. wave_transition.tscn（CanvasLayer + ColorRect dim + 居中 VBox：TitleLabel + SubtitleLabel，LabelSettings）
  3. wave_transition_controller.gd（wave_started 消费 → 演员冻结（paddle.set_frozen + ball.set_frozen）→
     读 wave_failure_text.json 分档选句 → Tween 三段 2.0s → 解锁兜底；get_node_or_null 容错）
  4. test_wave_transition.gd（短时长注入 + 选句纯函数断言）→ 全量回归

Phase 3: Main.tscn 组装（核心）
  1. 添加 BreakoutGrid 实例（position y=640, 直挂 Game 根）
  2. 添加 WaveController 节点（直挂 Game 根 — ../BreakoutGrid ../AIPaddle ../AtmosphereLayer/RainCurtain 即解析）
  3. 添加 WaveTransition 实例（CanvasLayer, layer 高于 Atmosphere(0) 低于 HUD(1)? 注意：#390 转场层建议 layer=3，
     高于 UpgradePickUI(2)、低于 PauseOverlay(10)——与常量组对齐）
  4. GameOverScreen 内联节点树 → 替换为 ui_game_over.tscn 实例（保留 CanvasLayer layer=1 + visible=false 覆盖）
  5. UpgradePickUI 实例补 layer = 2（UPGRADE_UI_LAYER）
  6. test_main_scene.gd 补断言 → 全量回归

Phase 4: 运行验证（AC 清单）
  1. godot --path mini-pong/ --headless --quit → exit 0
  2. godot --path mini-pong/ --headless --script tests/check_compile.gd → exit 0
  3. godot --path mini-pong/ --headless --script tests/run_tests.gd → 全绿（含新增 2 套件）
  4. auto_play_test.gd（100 局，验证 AC5 波次路径下 0 脚本错误/空引用）
  5. 可选 L3 视觉：run-e2e-review.sh 截图验证转场/升级 UI/失败屏渲染
```

### 主要风险

1. **#384 契约落地偏差**：DESIGN 定的 API 与消费方守卫假设不一致（如 wall_generated 负载类型）。缓解：落地后立即跑 test_hud/test_wave_cycle/test_scoring_manager 回归——守卫代码即契约测试
2. **砖层碰撞回归**：砖放 layer 2 后与球 mask 交互——DESIGN 已核查（球 mask=3 含 bit 2），落地后用 test_ball.gd 回归
3. **失败屏换实例的视觉回归**：`ui_game_over.tscn` 与内联节点样式可能不一致——以 #391/#392 霓虹样式为准（NeonStyle 应用在 game_over_screen.gd 内）
4. **转场层遮挡**：layer 选择错误会盖住升级 UI 或露出 HUD——按常量分层（Atmosphere 0 / HUD 1 / Upgrade 2 / Transition 3 / Pause 10）
5. **单 PR 体量**：含 2 个契约落地 + 组装。缓解：Phase 1/2 各自可独立全量回归，phase 间失败可定位

### 后续 Issue（MVP 后）

- #384/#390 代码落地后，波次数值/配色/副句文案的 taste 调优（归 taste-draft 队列）
- 砖块硬度/特殊砖（#384 DESIGN 预留扩展）
- 场景切换/标题画面分离（当前单场景自足）
```


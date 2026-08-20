# Design: [Integration] 组装 MVP 战斗闭环（可玩版本）

> **Parent Issue:** #585
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4 推荐组合**逐项确认采纳，无分歧** —— 组装策略 A（单一编排脚本 `main_battle.gd` BattleAssembler，Main.tscn 只加 1 脚本节点 + 1 场景实例）/ 失败字幕 A（复用 Main CanvasLayer 程序化 Label 淡入 + 输入冻结 + AI 停止）/ 余韵 5s A（assembler 内轻量状态机 + Timer）/ 低血氛围 A（单点接线 `hud.low_health_changed → atmosphere.set_low_health`）；方案 B/C 显式否决，理由同 PRD §4（全声明式无法满足 bind 契约 / 独立战斗场景对 MVP 过重）
> **Reference PRD:** `docs/PRD/585-mvp-combat-loop-assembly.md`（research PR #664 已合并 2026-08-20）
> **上游方案:** `docs/DESIGN/583-snowy-shandong-village-battle-stage.md`（battle_stage 出生点/StageCamera 消费契约 +「#585 组装时挂入 Main.tscn 且不重复挂 Atmosphere」）；`docs/DESIGN/581-enemy-ai.md`（敌人节点组合 = EnemyAI + CombatEntity(is_player=false) + StickFigureController，AI 零渲染）；`docs/DESIGN/575-combat-entity-state-machine.md`（6 信号契约 + 11 态 + bind_input_controller）；`docs/DESIGN/577-parry-clash-stance-break.md`（bind_entities/bind_input 判定器契约）；`docs/DESIGN/576-hud-stance-bars.md`（bind_player/set_target_enemy + low_health_changed 边沿）；`docs/DESIGN/578-two-life-revive.md`（ReviveOrchestrator bind_player 幂等接线 = 编排器架构先例）；`docs/DESIGN/579-combat-feedback-system.md`（bind_judge/subscribe_entity/camera_path 反馈矩阵）；`docs/DESIGN/580-execution-system.md`（ExecutionOrchestrator 5 项 bind 契约：bind_player/bind_enemy/bind_judge/bind_input/bind_feedback）；`docs/DESIGN/582-snow-night-atmosphere.md`（set_low_health 氛围入口）
> **所有权:** `content_ownership: mechanical`（组装 = 机械工程：场景装配/信号接线/状态编排；失败字幕文案（B5 候选 5 选 1）与教学提示文案（taste-draft 候选清单）随 PR 提交待用户定稿，**实现期禁止把候选清单「顺手定稿」**，定稿归 #584/用户；余韵/字幕时序参数进 constants「组装编排」`# DRAFT` 分区）
> **深度:** standard（PRD 头标注 depth: standard；GitHub 无 depth 标签）—— 5 文件（2 新建脚本 + 1 新建测试 + 2 修改）/ 13 项接线子任务跨 11 子系统（玩家装配/敌人装配/Judge/HUD/反馈/复活/处决/氛围/失败字幕/余韵/教学提示/smoke/E2E）→ **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-585，branch `plan/585-mvp-combat-loop-assembly`）；constants.gd「组装编排」分区追加在**文件尾部**（#584 手感分区已在前部，同文件不同区域，main 侧无代码冲突预期）；Main.tscn 为 #572 标题场景——本次只做追加式修改（+1 场景实例 + 1 脚本节点），不删既有节点；smoke_test.gd / run_tests.gd / e2e_shots.json 均为追加式（AC4 场景 / 新套件挂载 / assembly 组）
> **红线:** 只动 `shandong-wolf/` 下 5 文件（见 §3.1）；**绝不触碰** 全部 17 个既有组件脚本（`combat_entity.gd` / `combat_judge.gd` / `enemy_ai.gd` / `hud.gd` / `reaction_controller.gd` / `revive_orchestrator.gd` / `execution_orchestrator.gd` / `player_controller.gd` / `stick_figure_controller.gd` / `atmosphere_controller.gd` / `input_controller.gd` / `combat_states.gd` / `combat_state_table.gd` / `state_machine.gd` / `stick_figure.gd` / `sword_arc.gd` 等——组装发现缺口 → 回退对应 Issue 修复，禁止绕过）、`project.godot`（main_scene 已是 Main.tscn、autoload 已注册，零改动）、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`tests/check_compile.gd`；零第三方 addon（开源调研结论 PRD §6.2：成熟模板均为独立完整方案，与 17 组件契约冲突，不引入）；**不写可运行测试文件**（只产出 DESIGN/TASKS 文档 + 测试用例描述）；**不定稿任何 `# DRAFT` 值 / taste 文案候选**；PR body 用 `Parent #585`（不带冒号）

---

## 1. 架构总览

**问题本质是「17 个零件全部就位、彼此零接线，游戏不可玩」。** #573–#584 逐个交付了玩家控制器/火柴人/战斗实体/判定器/HUD/反馈/复活/处决/AI/场景/氛围，每个组件都预留了 `bind_*` / `subscribe_*` / `bind_entities` 程序化注入契约——这些契约就是为组装准备的（#573 PRD 红线「Main.tscn 不修改；玩家实体的场景挂接由后续战斗场景 issue 负责」——**#585 就是那个「后续」**）。当前 `godot --path shandong-wolf/` 启动 = #572 的静态标题画面（Main.tscn 77 行 + Atmosphere 实例）。本 issue 交付 = **`main_battle.gd` BattleAssembler 编排脚本（装配 + 接线 + 游戏状态编排）+ Main.tscn 追加挂载 + 失败字幕/余韵/教学提示三个缺失子系统 + test_main_assembly.gd + smoke AC4 场景 + e2e assembly 组**。组装完成即游戏可玩（AC4：5-10 分钟可验证核心玩法）。

**设计哲学：装配程序化，接线集中化，编排状态化，组件零改动。**
1. **装配程序化**——所有实例化/定位/bind 都在 `main_battle.gd` 的 `_ready()` 同步完成，Main.tscn 只加 1 个 `Node2D` + 脚本节点和 1 个 battle_stage 实例（Approach A，PRD §4.1）。组件 bind 契约（player/judge 引用、Camera2D path）无法纯声明注入，程序化是唯一可行路径；
2. **接线集中化**——13 项接线清单（PRD §8）全部收敛到一个可单测脚本，与组件既有测试模式（程序化实例化，test_battle_stage/test_enemy_ai 同构）天然对齐；
3. **编排状态化**——assembler 持轻量游戏状态机 `idle → combat → kill → afterglow → fail`（idle/combat/kill 为被动观察态，afterglow 由 5s Timer 驱动，fail 为终态），失败字幕/余韵时序全部状态机内编排；
4. **组件零改动**——17 个组件全部只消费不修改；发现缺口 → 回退对应 Issue（红线）。接线中发现的最大「缺口」实为**敌人视觉**：敌人同样复用 SW-003 火柴人骨架（#581 DESIGN 明确：EnemyAI + CombatEntity(is_player=false) + StickFigureController，AI 零渲染），非新资产。

```
★ Issue #585 本设计（shandong-wolf MVP 战斗闭环组装 SW-013）
┌────────────────────────────────────────────────────────────────────────────┐
│ 新建（2 文件 + 1 测试，全部 shandong-wolf/ 下）                                │
│  gdscripts/main_battle.gd       BattleAssembler（Node2D，装配+接线+状态编排） │
│    ├─ _ready() 13 步装配（PRD §8 顺序即依赖顺序）                              │
│    ├─ 玩家 = PlayerController(CharacterBody2D, 组 player)                     │
│    │   ├─ StickFigureController（instance player_stick_figure.tscn，视觉）    │
│    │   └─ CombatEntity(is_player=true, life_total=2)                         │
│    ├─ 敌人 = EnemyAI(CharacterBody2D) + StickFigureController + CombatEntity  │
│    │   └─（life_total=1, 放置 EnemySpawnA, EnemySpawnB 备用）                 │
│    ├─ 实例化 Judge/HUD/Reaction/Revive/Execution 并逐一 bind                  │
│    ├─ 游戏状态机 idle→combat→kill→afterglow→fail（轻量枚举 + Timer）           │
│    ├─ 失败字幕（CanvasLayer Label 淡入 + 输入冻结 + AI 停止）                  │
│    └─ 教学提示（开局 3s 浮现，文案 taste 候选）                                │
│  tests/test_main_assembly.gd    六组用例（挂载完整/信号链连通/闭环/失败/余韵）  │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────────────────┐
│ 修改（2 文件，全部追加式）                                                     │
│  scenes/Main.tscn           + instance battle_stage.tscn + Node2D main_battle│
│  tests/smoke_test.gd        追加 AC4 完整闭环场景（Scenario II）              │
│  tests/run_tests.gd         _run_tests() 追加 test_main_assembly             │
│  e2e_shots.json             追加 assembly 组（闭环/处决/失败/余韵截图）        │
│  gdscripts/constants.gd     文件尾部追加「组装编排」# DRAFT 分区               │
└────────────────────────────────────────────────────────────────────────────┘
事件源（只读消费，零修改）: InputController 信号（#573）+ CombatEntity 6 信号（#575）
                        + CombatJudge 5 结果事件（#577）+ Hud.low_health_changed（#576）
消费方（自动接管，零修改）: StickFigureController.consume_state（#574）/ Hud（#576）
                        / ReactionController.trigger_feedback（#579）/ ExecutionOrchestrator（#580）
                        / ReviveOrchestrator（#578）/ EnemyAI（#581）/ Atmosphere.set_low_health（#582）
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件/场景） | Issue | 状态 | 本设计的消费方式 |
|------|:---:|:---:|-----------------|
| `scenes/Main.tscn` | #572 | ✅ 77 行标题场景 + Atmosphere 实例 | **修改**：追加 battle_stage 实例 + `Node2D` + `main_battle.gd`（§3.2）；既有标题/版本标签节点保留 |
| `gdscripts/player_controller.gd` | #573/#611 | ✅ CharacterBody2D 移动实体（组 `player`） | 程序化 `new()` + add_child，定位 PlayerSpawn —— 零改动 |
| `gdscripts/input_controller.gd` | #573/#611 | ✅ InputController autoload | 直接取 autoload 引用（`root.get_node_or_null("InputController")`，headless 兼容），bind 给 entity/judge/execution —— 零改动 |
| `scenes/player_stick_figure.tscn` | #574/#612 | ✅ StickFigureController + StickFigure + AnimationPlayer | instance 作玩家/敌人视觉子节点；`entity.state_changed → stick.consume_state` —— 零改动 |
| `gdscripts/combat_entity.gd` | #575/#618 | ✅ CombatEntity（is_player/life_total/6 信号 + bind_input_controller + execute_kill/set_invincible/recover_from_break） | `new({...})` 变体参数构造玩家/敌人实体 + bind_input_controller —— 零改动 |
| `gdscripts/hud.gd` | #576/#627 | ✅ Hud（bind_player/set_target_enemy/处决+击杀提示/low_health_changed 边沿） | 实例挂 CanvasLayer + bind 双实体 + `low_health_changed → atmosphere.set_low_health` —— 零改动 |
| `gdscripts/combat_judge.gd` | #577/#626 | ✅ CombatJudge（bind_entities/bind_input/register_attack_window/5 结果事件） | `bind_entities(player, enemy)` + `bind_input(ic)`（**必须先于首帧 resolve**，§4 Flow 4）—— 零改动 |
| `gdscripts/revive_orchestrator.gd` | #578 | ✅ 两条命复活编排（bind_player/is_armed） | `bind_player(player)` —— 零改动 |
| `gdscripts/reaction_controller.gd` | #579/#654 | ✅ 反馈矩阵（bind_judge/subscribe_entity/camera_path export/freeze_time_stack） | `bind_judge` + `subscribe_entity` 双实体 + `camera_path = "BattleStage/StageCamera"` —— 零改动 |
| `gdscripts/execution_orchestrator.gd` | #580/#660 | ✅ 处决触发链路（bind_player/bind_enemy/bind_judge/bind_input/bind_feedback 5 项） | 5 项全 bind —— 零改动 |
| `gdscripts/enemy_ai.gd` | #581/#638 | ✅ EnemyAI（waypoints/player/judge export + bind_entity） | `bind_entity(enemy_entity)` + `player`/`judge` 引用注入 + 放置 EnemySpawnA —— 零改动 |
| `scenes/battle_stage.tscn` | #583 | ✅ 2400px 舞台 + PlayerSpawn(640,560)/EnemySpawnA(700,560)/EnemySpawnB(1720,560)/StageCamera | instance 进 Main（**不重复挂 Atmosphere**，#583 DESIGN 约定）—— 零改动 |
| `gdscripts/atmosphere_controller.gd` | #582/#613 | ✅ 氛围层（set_low_health(enabled)/debug 入口） | 经 Main 既有 Atmosphere 实例取引用，接 low_health_changed —— 零改动 |
| `tests/smoke_test.gd` | #573+ | ✅ 输入/移动链路（AC6） | **修改**：追加 AC4 完整闭环场景（§3.5） |
| `tests/run_tests.gd` | #572+ | ✅ 15 套件挂载 | **修改**：追加 `test_main_assembly`（§3.4） |
| `e2e_shots.json` | #574+ | ✅ 6 组 shot（stick_figure/snow_night/hud/feedback/battle_stage/execution） | **修改**：追加 assembly 组（§3.6） |
| `gdscripts/constants.gd` | #572/#584 | ✅ 全 `# DRAFT` 分区 + 定稿值（SWORD_DAMAGE_EXECUTE/EXECUTE_RANGE 等） | **修改**：文件尾部追加「组装编排」`# DRAFT` 分区（§3.3） |

### 1.2 PRD 断言 vs 实际代码（Gap 分析）

| PRD 断言 | 实际代码 | 设计裁决 |
|---------|---------|---------|
| 敌人 = CombatEntity + EnemyAI（§8 步骤 4，未列视觉） | #581 DESIGN 明确敌人节点组合含 StickFigureController（复用 SW-003 骨架，AI 零渲染） | **敌人同样 instance player_stick_figure.tscn 作视觉子节点**（非新资产，红线合规）；`consume_state` 由敌人 entity.state_changed 驱动 |
| 玩家 = PlayerController + CombatEntity + StickFigure | `player_controller.gd` 是 CharacterBody2D（物理体），StickFigureController 是 Node2D（视觉） | 节点树：PlayerController 为根（物理/组 player）→ 子节点 StickFigureController 实例（视觉）+ CombatEntity（数据/状态机）；StickFigureController 位置对齐 PlayerController 原点 |
| `project.godot` 需改 main_scene（#583 备注） | `run/main_scene="res://scenes/Main.tscn"` **已是** Main.tscn | **project.godot 零改动** |
| 失败字幕用 Main 现有 CanvasLayer | Main CanvasLayer 内含 CenterContainer 标题（TitleLabel/SubtitleLabel）+ VersionLabel + PostMergeProbeLabel | assembler 复用该 CanvasLayer 挂字幕 Label；**标题 CenterContainer 在 _ready 隐藏**（MVP 开场直接进入雪夜村口，标题卡不占画面；节点保留不删，#572 语义可回归）；VersionLabel/PostMergeProbeLabel 不动 |
| 敌人数量 | #583 DESIGN 提「EnemySpawnA/B 实例化 2 敌人」；#585 PRD §8 步骤 4 定「放置 EnemySpawnA（EnemySpawnB 备用）」；CombatJudge/ExecutionOrchestrator 均为单敌契约 | **MVP 单敌（EnemySpawnA）**，EnemySpawnB 保留备用（多敌波次超出 MVP 范围，AC 无多敌要求） |
| 组装顺序敏感（PRD §7 实验 1） | 全部 bind 在 `_ready()` 同步完成（首帧前就绪） | bind 顺序即 PRD §8 清单顺序；judge.bind_entities/bind_input 在第 5 步完成，早于首帧 resolve —— 预期 0 顺序敏感点（test 驱动验证） |
| smoke_test.gd 需追加 AC4 场景 | smoke 现有 `_init → call_deferred("_run")` + headless 手动驱动模式 | Scenario II 照同款模式程序化实例化完整闭环（§8 Scenario G） |

## 2. 新组件 — 详细设计

### 2.1 main_battle.gd — BattleAssembler 组装编排脚本（PRD §4.1 方案 A / §4.2 A / §4.3 A）

- **File:** `shandong-wolf/gdscripts/main_battle.gd`
- **extends:** Node2D（挂 Main.tscn 下同名节点）
- **Node structure（运行期构建）:**

```
Main (Node2D, Main.tscn)
├── WorldBackdrop / CanvasLayer(标题/版本/探针) / Atmosphere  ── 既有，零删改
├── BattleStage (instance battle_stage.tscn)                  ── 追加（不重复挂 Atmosphere）
│   ├── PlayerSpawn (Marker2D @ 640,560)
│   ├── EnemySpawnA (Marker2D @ 700,560) / EnemySpawnB (备用)
│   └── StageCamera (Camera2D current)
└── MainBattle (Node2D, script = main_battle.gd)              ── 追加（本设计）
    ├── Player (PlayerController, CharacterBody2D, 组 player) @ PlayerSpawn
    │   ├── PlayerStickFigure (instance player_stick_figure.tscn)
    │   └── PlayerEntity (CombatEntity, is_player=true, life_total=2)
    ├── Enemy (EnemyAI, CharacterBody2D) @ EnemySpawnA
    │   ├── EnemyStickFigure (instance player_stick_figure.tscn)
    │   └── EnemyEntity (CombatEntity, is_player=false, life_total=1)
    ├── Judge (CombatJudge, Node)
    ├── Reaction (ReactionController, Node2D, camera_path=.../StageCamera)
    ├── Execution (ExecutionOrchestrator, Node)
    ├── Revive (ReviveOrchestrator, Node)
    ├── HudLayer (CanvasLayer) ── Hud (Hud)
    └── FailLabel (Label, 挂在 Main/CanvasLayer, 初始隐藏)
```

- **Signals（本组件不发业务信号；对外暴露供测试/E2E 断言）:**
  - `game_state_changed(from: String, to: String)` —— 游戏状态机迁移广播（test/E2E 断言用）
  - `fail_subtitle_shown()` —— 失败字幕显示完成（测试断言恰好一次）
- **State Properties:**
  - `enum GameState { IDLE, COMBAT, KILL, AFTERGLOW, FAIL }`，`var _game_state: int = GameState.IDLE`
  - `var player / enemy / judge / hud / reaction / execution / revive / atmosphere`（引用缓存，测试可读）
  - `var _afterglow_timer: Timer`（击杀后 5s 余韵，`AFTERGLOW_SECONDS` # DRAFT）
  - `var _fail_freeze: bool`（失败终态输入冻结标志）
- **Key Methods:**
  - `_ready()` —— 13 步装配全链路（§4 Flow 4 顺序契约）：① instance BattleStage ② 构建玩家 ③ 定位 ④ 构建敌人 ⑤ Judge bind ⑥ HUD bind ⑦ Reaction bind ⑧ Revive bind ⑨ Execution bind ⑩ 低血氛围接线 ⑪ 失败字幕监听 ⑫ 余韵监听 ⑬ 教学提示；末步隐藏标题 CenterContainer、`_set_game_state(IDLE)`
  - `_build_player() -> Node2D` —— `PlayerController.new()` + add_child + instance stick figure + `CombatEntity.new({is_player=true, life_total=2})` + `bind_input_controller(ic)` + 连线 `entity.state_changed → stick.consume_state`
  - `_build_enemy() -> Node2D` —— `EnemyAI.new()`（waypoints 由 EnemySpawnA/B 坐标派生）+ stick figure + `CombatEntity.new({is_player=false, life_total=1})` + `ai.bind_entity(enemy_entity)` + 注入 `ai.player = player_controller`、`ai.judge = judge`
  - `_wire_fail_path()` —— `player_entity.died.connect(_on_player_final_death)`，`final==true` 才进 fail
  - `_on_player_final_death(entity, final)` —— `final==true` → `_set_game_state(FAIL)` → 输入冻结（InputController 停轮询或 PlayerController 禁用，二选一实现期定，test 断言输入无效果）+ EnemyAI 停止（`enemy.set_physics_process(false)` 或 `_dead` 既有全禁）→ 死亡反馈播完 ≥0.5s（`FAIL_SUBTITLE_DELAY` # DRAFT）→ FailLabel 淡入 1s（`FAIL_SUBTITLE_FADE_SECONDS` # DRAFT，文案候选清单 §2.2）
  - `_on_enemy_final_death(entity, final)` —— `final==true` → `_set_game_state(KILL)`（HUD 击杀提示自动触发，零接线）→ `_set_game_state(AFTERGLOW)` + `_afterglow_timer.start(AFTERGLOW_SECONDS)` → 到期 `_set_game_state(IDLE)`（等待再战；敌人重生不在 MVP 范围，AC3 只要求空闲 ≥5s）
  - `_set_game_state(next)` —— 状态迁移 + `game_state_changed` 广播 + 幂等守卫（FAIL 为终态，不再迁移）
  - `_show_tutorial_hint()` —— 开局 `TUTORIAL_HINT_DELAY`（# DRAFT）后浮现操作提示 Label（移动/攻击/格挡键位，文案 taste 候选 §2.3）
- **Integration notes:** 全部 13 步在 `_ready()` 同步完成（首帧前就绪，PRD §7 实验 1 预期 0 顺序敏感点）；组件引用存成员变量供 test 断言 bind 目标非 null（AC5「无 pending 组件」）。

### 2.2 失败字幕（PRD §4.2 方案 A）

- 复用 Main 既有 CanvasLayer 程序化创建 `Label`（`anchors_preset=15` 居中，初始 `visible=false`、`modulate.a=0`）；不新建场景
- 时序：`player.died(final=true)` → FAIL 态 → 输入冻结 + AI 停止 → 延迟 `FAIL_SUBTITLE_DELAY=0.5`（# DRAFT）→ Tween 淡入 `FAIL_SUBTITLE_FADE_SECONDS=1.0`（# DRAFT）→ 常驻
- 文案：**候选 5 选 1 进 PR 待用户定稿**（B5 失败表达，taste-draft）：『雪落无声。村口只剩你。』『雪还在下。村口没人了。』『灯灭了。雪落无声。』『村口只剩下雪。』『刀还在。你没了。』—— 实现期禁止自行定稿
- 冻结实现：InputController 有 `_process` 轮询——实现期在 `_freeze_input()` 里用 `ic.set_process(false)`（简单直接，test 断言 attack/guard 不再产生意图事件）；EnemyAI 停用 `enemy.set_physics_process(false)`（AI `_physics_process` 消费 move_intent，停用即停走）

### 2.3 教学提示（PRD §8 步骤 13，情绪弧「教学」）

- 开局 `TUTORIAL_HINT_DELAY=3.0`（# DRAFT）后，CanvasLayer 顶部浮现提示 Label（移动 `←→` / 攻击 J 或键位名按 input map `game_light_attack` / 格挡 `game_guard`），数秒后淡出（复用 HUD hint 显隐模式或 assembler 轻量 Tween，实现期定）
- 文案 taste 候选清单进 PR：如『村口有动静。握紧你的刀。』『→← 移动 · J 攻击 · K 格挡』等，用户定稿

## 3. 既有组件修改

### 3.1 文件清单总表

| 性质 | 文件 | 变更 |
|------|------|------|
| 新建 | `shandong-wolf/gdscripts/main_battle.gd` | 组装编排脚本（§2.1） |
| 新建 | `shandong-wolf/tests/test_main_assembly.gd` | 组装测试套件（§8） |
| 修改 | `shandong-wolf/scenes/Main.tscn` | + instance battle_stage.tscn + Node2D main_battle（§3.2） |
| 修改 | `shandong-wolf/gdscripts/constants.gd` | 文件尾部追加「组装编排」`# DRAFT` 分区（§3.3） |
| 修改 | `shandong-wolf/tests/run_tests.gd` | `_run_tests()` 追加 1 行（§3.4） |
| 修改 | `shandong-wolf/tests/smoke_test.gd` | 追加 Scenario II AC4 完整闭环（§3.5） |
| 修改 | `shandong-wolf/e2e_shots.json` | 追加 assembly 组（§3.6） |

### 3.2 Main.tscn — 追加挂载（唯一场景修改）

```tscn
[ext_resource type="PackedScene" path="res://scenes/battle_stage.tscn" id="2_battle_stage"]
[ext_resource type="Script" path="res://gdscripts/main_battle.gd" id="3_main_battle"]

[node name="BattleStage" parent="." instance=ExtResource("2_battle_stage")]

[node name="MainBattle" type="Node2D" parent="."]
script = ExtResource("3_main_battle")
```

- 顺序：BattleStage 在 Atmosphere 之前或之后均可（StageCamera current 接管渲染；Atmosphere 不重复挂——#583 约定）
- **不删除** WorldBackdrop / CanvasLayer 标题 / VersionLabel / PostMergeProbeLabel（标题 CenterContainer 由 assembler `_ready` 隐藏）

### 3.3 constants.gd — 追加「组装编排」分区（文件尾部，格式照 #572 既有分区）

```gdscript
# ── 组装编排（# DRAFT 候补值，定稿归 #584/用户；#585 消费方，禁止实现期定稿）──
# AFTERGLOW_SECONDS
#   AC3: 击杀后场景空闲 ≥5s 情绪余韵，雪花持续（Atmosphere 无暂停路径，天然持续）
#   候选集: [5.0, 6.0, 8.0]（默认 5.0；MVP 收束节奏，最短满足 AC3 字面）
# FAIL_SUBTITLE_DELAY / FAIL_SUBTITLE_FADE_SECONDS
#   AC2: 死亡反馈（白闪/屏震 #579）播完后 ≥0.5s 字幕淡入 1s
#   候选集: delay [0.3, 0.5, 1.0] / fade [0.8, 1.0, 1.5]（默认 0.5 / 1.0）
# TUTORIAL_HINT_DELAY
#   情绪弧「教学」: 开局 3s 内浮现操作提示（移动/攻击/格挡键位）
#   候选集: [2.0, 3.0, 5.0]（默认 3.0）
# FAIL_SUBTITLE_CANDIDATES: Array[String]  # B5 失败表达候选 5 选 1（§2.2），taste-draft 进 PR 待用户定稿
# TUTORIAL_HINT_CANDIDATES: Array[String]  # 教学提示文案候选（§2.3），taste-draft 进 PR 待用户定稿
```

### 3.4 tests/run_tests.gd — 挂载新套件

```gdscript
_run("res://tests/test_main_assembly.gd", "MainAssembly")
```

### 3.5 tests/smoke_test.gd — 追加 AC4 完整闭环场景

- 新增 `Scenario II (AC4)`：程序化 `load("res://scenes/Main.tscn").instantiate()` 挂树 → 手动驱动 120 帧 → 断言 5 阶段可达：`game_state_changed` 观测 IDLE→(COMBAT)→KILL→AFTERGLOW；驱动玩家移动遇敌、注入攻击、敌人 stance_broken、处决键、敌人 died(true)、afterglow 5s 到期回 IDLE——headless 确定性驱动（照既有手动 `_process(0.016)` / `await physics_frame` 模式，规避帧序竞态）
- 失败路径子场景：注入玩家 died(true) ×2 → FailLabel.visible == true 且文案 ∈ 候选清单

### 3.6 e2e_shots.json — 追加 assembly 组

- `main_scene`: 新增 `scenes/e2e_main_assembly_capture.tscn`（CaptureRig + instance Main.tscn，state 轮询契约照 e2e_battle_stage_capture 模式）——**注意**：本 rig 为新建文件，列入 §3.1 新建清单
- shots：`01_spawn_combat`（出生遇敌）/ `02_parry_execute`（弹反崩解处决）/ `03_fail_subtitle`（失败字幕）/ `04_afterglow`（击杀余韵雪幕）——供 review agent 提交用户裁决（taste：失败文案/教学文案/处决构图）

## 4. 数据流

### Flow 1: 完整战斗闭环（正常路径，AC1/AC4 核心）

```
① 玩家出生   _ready() 装配完成 → Player @ PlayerSpawn，IDLE 态
② 遇敌       EnemyAI 感知（can_sense_player 120° 6m）→ chase → entity.request_transition("attack")
             → 敌人 entity state_changed("attack") → 判定器自动登记窗口（#577）
③ 攻击/弹反  玩家 attack_pressed → 玩家 entity attack 态 → CombatJudge.resolve_attack
             → parry_success（弹反）→ ReactionController 火花/hit-stop/屏震/白闪（#579 已接）
             → 敌人 stance_broken → ExecutionOrchestrator armed 窗口（#580 已接）
④ 敌人崩解   stance_broken → 敌人 entity 进 stance_break 态 → stick figure anim_stance_break
⑤ 处决       armed 窗口内 attack_pressed + 距离 ≤ EXECUTE_RANGE → execute 转移 → execute_kill
             → enemy died(final=true) → S 级反馈 + 淡出（#580 全链路已交付，组装只 bind）
⑥ 击杀       enemy died(true) → HUD 击杀提示（#576 自动）→ assembler KILL 态 → AFTERGLOW
⑦ 余韵       afterglow Timer 5s（雪花持续，Atmosphere 天然）→ 到期回 IDLE
```

### Flow 2: 失败路径（AC2）

```
玩家 life_1 耗尽 → died(entity, false) → ReviveOrchestrator 计时 → revive()（#578，半管血）
玩家 life_2 耗尽 → died(entity, true) → assembler FAIL 态（终态，幂等守卫不再迁移）
  → 输入冻结（ic.set_process(false)）+ EnemyAI 停用（set_physics_process(false)）
  → FAIL_SUBTITLE_DELAY(0.5s) → FailLabel Tween 淡入 1s → 常驻（文案 ∈ 候选清单）
```

### Flow 3: 余韵期间交互（AC3 边界）

```
AFTERGLOW 态：玩家移动=只读（InputController 仍轮询，PlayerController 正常物理）
  攻击=自然落空（无目标/敌人已死，判定器无窗口可 resolve，无错误无软锁）
  → 5s 到期 → IDLE（等待再战；敌人重生不在 MVP 范围）
```

### Flow 4: 装配顺序契约（PRD §8 清单即依赖顺序，全部同步 _ready 完成）

```
1  Main.tscn instance BattleStage + MainBattle
2  玩家装配（PlayerController + stick + CombatEntity + bind_input_controller + state_changed→consume_state）
3  玩家定位 PlayerSpawn
4  敌人装配（EnemyAI + stick + CombatEntity + bind_entity + player/judge 注入）定位 EnemySpawnA
5  Judge.bind_entities(player_entity, enemy_entity) + bind_input(ic)   ← 必须先于首帧 resolve
6  Hud 实例挂 CanvasLayer + bind_player + set_target_enemy
7  Reaction.bind_judge + subscribe_entity(player/enemy) + camera_path
8  Revive.bind_player
9  Execution.bind_player/bind_enemy/bind_judge/bind_input/bind_feedback
10 hud.low_health_changed → atmosphere.set_low_health（单点接线）
11 player.died → _on_player_final_death（fail 路径）
12 enemy.died → _on_enemy_final_death（余韵路径）
13 教学提示 Timer（TUTORIAL_HINT_DELAY 后浮现）
```

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| execute 态再按攻击 | #580 armed 已清除 + `request_transition("execute")` 幂等（已实现）；组装 test 验证不重复触发 |
| 复活无敌期受击 | #578 无敌期 take_damage no-op 双保险（已实现）；组装验证接线后仍生效 |
| 处决演出期间玩家受击 | #575 take_damage execute 态 no-op 守卫 + 判定器跳过守卫（已实现） |
| 敌人 final death 后 AI | #581 `_dead` 全禁 + #580 `_on_enemy_died` 自动解绑防 queue_free 后访问（已实现）；组装不重复处理 |
| 低血边沿恰好一次 | #576 边沿触发语义；组装接线后 test 断言恰好一次 true/false（不重入不漏发） |
| 余韵期间无目标攻击 | 自然落空无错误（AC1 延伸；test 注入 attack 断言无异常无状态迁移） |
| 失败字幕出现后再输入 | 输入已冻结（ic.set_process(false)），无状态迁移无软锁（test 断言 FAIL 后无信号事件） |
| 组装顺序依赖 | bind 全在 `_ready()` 同步完成；test 按 Flow 4 顺序驱动 120 帧断言首帧 resolve 正常（PRD §7 实验 1） |
| 标题卡遮挡 | assembler `_ready` 隐藏 CenterContainer（节点保留），MVP 开场直接进入雪夜村口 |
| 教学提示与战斗重叠 | 提示 3s 后淡出；提示期间战斗照常（只读不阻塞）；test 断言提示淡出后无残留节点 |
| 双死竞态（died(true) 与 revive 竞争） | #578 终态 revive() 被拒（已实现）；assembler 只消费 final==true，幂等进 FAIL |
| Atmosphere 缺省（headless 测试无 Main 树） | test 直接程序化装配可空 atmosphere 引用（`get_node_or_null`），低血接线 no-op 不崩溃 |

## 6. 集成点

> **状态约定：** ⬜ = pending（本设计声明，implement agent 接线后改 ✅）。implement agent MUST 更新本表；review agent 验证全 ⬜ 已解决或显式延期才可合并。

| # | 集成 | 我们的组件 | 目标组件 | 方式 | 状态 |
|:-:|------|:---:|:---:|------|:---:|
| 1 | 场景挂载 | Main.tscn | battle_stage.tscn | instance 进 Main（不重复挂 Atmosphere） | ⬜ |
| 2 | 玩家视觉 | CombatEntity.state_changed | StickFigureController.consume_state | 信号直连（#574 契约） | ⬜ |
| 3 | 玩家输入桥 | CombatEntity.bind_input_controller | InputController autoload | 方法注入 | ⬜ |
| 4 | 敌人 AI | EnemyAI.bind_entity + player/judge 注入 | CombatEntity(敌人) + PlayerController + CombatJudge | 方法注入 + export 赋值 | ⬜ |
| 5 | 判定 | CombatJudge.bind_entities(p,e) + bind_input(ic) | 双实体 + InputController | 方法注入（首帧前） | ⬜ |
| 6 | HUD | Hud.bind_player / set_target_enemy | 双实体 | 方法注入 | ⬜ |
| 7 | 反馈 | ReactionController.bind_judge + subscribe_entity ×2 + camera_path | Judge + 双实体 + StageCamera | 方法注入 + export path | ⬜ |
| 8 | 复活 | ReviveOrchestrator.bind_player | 玩家实体 | 方法注入 | ⬜ |
| 9 | 处决 | ExecutionOrchestrator.bind_player/bind_enemy/bind_judge/bind_input/bind_feedback | 双实体 + Judge + IC + Reaction | 5 项方法注入（#580 契约） | ⬜ |
| 10 | 低血氛围 | Hud.low_health_changed | Atmosphere.set_low_health | 单点信号直连 | ⬜ |
| 11 | 失败字幕 | player.died(final=true) | assembler FAIL 状态机 → Label | 信号 → 状态迁移 → UI | ⬜ |
| 12 | 余韵 | enemy.died(final=true) | assembler AFTERGLOW 状态机 + Timer | 信号 → 状态迁移 → 定时 | ⬜ |
| 13 | 教学提示 | 开局 Timer | CanvasLayer Label | 定时浮现（文案 taste 候选） | ⬜ |

## 7. 实现阶段

| Phase | 优先级 | 组件 | 估算 | 依赖 |
|:-----:|:------:|------|:----:|------|
| Phase 0 | P0 | Spike 验证：PRD §7 实验 1（组装顺序时序，headless 120 帧闭环）/ 实验 2（失败字幕时序，E2E fail shot）/ 实验 3（余韵 5s 状态边界） | 0.5d | PRD §7 |
| Phase 1 | P0 | constants.gd「组装编排」# DRAFT 分区（§3.3 逐字落地） | 0.5d | — |
| Phase 2 | P0 | main_battle.gd 装配 + 13 步接线（§2.1 + §4 Flow 4） | 1.5d | Phase 1 |
| Phase 3 | P0 | 失败字幕 + 输入冻结 + 教学提示（§2.2/§2.3） | 0.5d | Phase 2 |
| Phase 4 | P0 | Main.tscn 追加挂载（§3.2） | 0.5d | Phase 2 |
| Phase 5 | P0 | tests/test_main_assembly.gd + run_tests.gd 挂载（§8） | 0.5d | Phase 2-4 |
| Phase 6 | P0 | smoke_test.gd Scenario II（AC4 完整闭环） | 0.5d | Phase 5 |
| Phase 7 | P1 | e2e assembly 组 + rig（§3.6）+ 截图附 PR + 文案候选清单附 PR | 0.5d | Phase 3-4, Spike 2/3 |

## 8. 测试用例描述

> **约定：** 只描述测试场景，不写可运行测试代码（implement agent 交付 `tests/test_main_assembly.gd` 等）。headless 模式：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 与 `tests/smoke_test.gd`。驱动模式照既有：`_process(delta)` 手动推进 + `await physics_frame`（规避帧序竞态）；程序化实例化 Main.tscn（`load().instantiate()`）或直接装配 BattleAssembler 组件（headless 免树）。场景映射 PRD §7 实验 1-3 + issue AC1-AC5。

### Scenario A: 挂载完整性（AC5「无 pending 组件」）
- Test A1（Main 可加载）：`load("res://scenes/Main.tscn")` 非 null；instantiate 后 MainBattle 节点存在且 script == main_battle.gd
- Test A2（bind 目标非 null）：_ready 后 player/enemy/judge/hud/reaction/execution/revive/atmosphere 引用全部非 null（组件级）
- Test A3（BattleStage 挂载）：Main 下 BattleStage 实例存在；PlayerSpawn/EnemySpawnA/StageCamera 路径可达
- Test A4（标题隐藏）：CenterContainer.visible == false（MVP 开场直进战斗）

### Scenario B: 信号链连通（PRD §5.3 失败路径 1）
- Test B1（玩家动画链）：注入 player_entity.state_changed("idle"→"move") → stick.consume_state 被调（mock 或动画状态断言）
- Test B2（判定链）：敌人进 attack 态 → judge 窗口已登记（register_attack_window 计数 ≥1）；玩家 attack → resolve 产出 parry_success/hit_landed 之一
- Test B3（处决链）：敌人 stance_broken → execution.armed；窗口内 attack_pressed + 距离内 → execute 转移 → enemy died(true) 恰好一次
- Test B4（HUD 链）：玩家 hp_changed → hud 血条更新（set_debug_hp 或内部值断言）；敌人 died(true) → 击杀提示可见
- Test B5（反馈链）：judge 事件 → reaction.trigger_feedback 被调（mock 计数）
- Test B6（复活链）：玩家 died(false) → revive 计时 → revived 信号发出（hp 恢复）
- Test B7（氛围链）：hud 低血边沿 → atmosphere.set_low_health(true/false) 恰好各一次（不重入不漏发）

### Scenario C: 完整闭环冒烟（AC1/AC4，PRD §7 实验 1）
- Test C1（闭环可达）：程序化驱动 出生→遇敌→攻击→弹反→崩解→处决→击杀，`game_state_changed` 观测 IDLE→COMBAT→KILL→AFTERGLOW 全可达，无软锁（每阶段输入可恢复）
- Test C2（顺序敏感 0 点）：装配后首帧（_ready 后第一 physics frame）resolve 正常，无「judge 未 bind」警告
- Test C3（120 帧稳定）：闭环推进 120 帧无报错无泄漏（节点数不增长）

### Scenario D: 失败路径（AC2，PRD §7 实验 2）
- Test D1（双死→字幕）：玩家 died(true) → FAIL 态 → FailLabel.visible==true 且文案 ∈ FAIL_SUBTITLE_CANDIDATES
- Test D2（输入冻结）：FAIL 后注入 attack_pressed → 无实体状态迁移（输入无效果）
- Test D3（AI 停止）：FAIL 后敌人 `_physics_process` 停用（move_intent 不再消费）
- Test D4（终态幂等）：二次 died(true) → 无二次字幕、状态不迁移（fail_subtitle_shown 恰好一次）
- Test D5（单死不失败）：died(false) → 非 FAIL 态（复活路径接管）

### Scenario E: 余韵 5s（AC3，PRD §7 实验 3）
- Test E1（时序）：enemy died(true) → AFTERGLOW 态；推进 <5s 状态不变；推进 ≥5s → 回 IDLE（Timer 到期断言）
- Test E2（只读输入）：AFTERGLOW 期间注入移动 → 玩家位移正常（只读不打断）；注入攻击 → 无异常无状态迁移（自然落空）
- Test E3（雪花持续）：AFTERGLOW 期间 Atmosphere 粒子节点存在且 emitting（无暂停路径）

### Scenario F: 失败路径防回归（PRD §5.3）
- Test F1（漏接线）：未 bind_input 的 judge 实例 resolve → 断言红（信号链连通测试即漏接线拦截）
- Test F2（窗口错过）：stance_break 后不处决 → 推进 ≥3s → 敌人 recover_from_break（架势恢复 50%）→ 再战无软锁
- Test F3（Main 资源路径）：Main.tscn ext_resource 路径错误 → 场景加载断言红
- Test F4（E2E 驱动兼容）：assembly 组 shot 可经 e2e rig 稳定产出（非黑屏非全白）

### Scenario G: smoke AC4（tests/smoke_test.gd Scenario II）
- Test G1（闭环 exit 0）：headless `--script tests/smoke_test.gd` 完整闭环驱动 + 失败字幕子场景 → exit 0
- Test G2（时长窗口）：闭环可在 5-10 分钟内手动完成（CI smoke 自动跑通即 AC4 证据）

## 9. 验收条件映射（源自 Issue #585 body）

- [ ] **AC1: 玩家可完整经历 出生→遇敌→弹反→崩解→处决→击杀 闭环且无软锁** —— Scenario C（闭环可达 + 每阶段输入可恢复）+ Flow 1 数据流
- [ ] **AC2: 玩家两条命耗尽后显示失败字幕（文案候选『雪落无声。村口只剩你。』）** —— Scenario D（双死→字幕 + 文案 ∈ 候选清单 + 输入冻结 + AI 停止）
- [ ] **AC3: 击杀敌人后场景内至少空闲 5s（情绪余韵），雪花持续飘落** —— Scenario E（afterglow ≥5s 时序 + 雪花持续）
- [ ] **AC4: 5-10 分钟可完成完整 MVP 流程（smoke test 自动跑通）** —— Scenario G（smoke exit 0 + 闭环驱动）
- [ ] **AC5: 组装完成后 compile/run 测试全绿，无 pending 组件** —— Scenario A（bind 目标非 null）+ 15 套既有套件全绿 + check_compile 退出 0

## 10. 明确不修改（与 PRD §8 红线对齐）

- **不修改** 全部 17 个既有组件脚本（`combat_entity.gd` / `combat_judge.gd` / `enemy_ai.gd` / `hud.gd` / `reaction_controller.gd` / `revive_orchestrator.gd` / `execution_orchestrator.gd` / `player_controller.gd` / `stick_figure_controller.gd` / `atmosphere_controller.gd` / `input_controller.gd` / `combat_states.gd` / `combat_state_table.gd` / `state_machine.gd` / `stick_figure.gd` / `sword_arc.gd` / `time_scale_stack.gd` 等）——组装只 bind 接线；发现缺口 → 回退对应 Issue 修复，禁止绕过
- **不修改** `project.godot`（main_scene 已是 Main.tscn；autoload Game/InputController 已注册）
- **不修改** `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`tests/check_compile.gd`、`scripts/`
- **不删除** Main.tscn 既有节点（WorldBackdrop/CanvasLayer 标题/VersionLabel/PostMergeProbeLabel/Atmosphere）——只隐藏标题 CenterContainer
- **不新增** 视觉/音频资产（全部复用程序化组件；敌人视觉复用 SW-003 火柴人）；不新增第三方 addon（开源调研 PRD §6.2 结论：模板不引入，编排模式作参考——该结论由 implement PR 说明）
- **不定稿任何 `# DRAFT` 值**（余韵/字幕时序/教学提示延时）+ **不裁决 taste 文案**（失败字幕 B5 候选 5 选 1 + 教学提示候选，全部随 PR 附清单待用户定稿）
- **不写可运行测试文件**（本 issue 只产出 DESIGN/TASKS 文档；测试代码归 implement agent）

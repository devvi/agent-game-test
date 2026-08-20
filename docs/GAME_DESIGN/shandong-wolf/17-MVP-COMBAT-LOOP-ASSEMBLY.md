# MVP 战斗闭环组装 — BattleAssembler / 游戏状态机 / 失败字幕 / 击杀余韵 / 教学提示（#585/#666）

> 落盘依据：PR **#666**（feat(585) 组装 MVP 战斗闭环（可玩版本），已 merge 2026-08-20）←
> DESIGN `docs/DESIGN/585-mvp-combat-loop-assembly.md`（plan PR #665 已 merge）+ PRD
> `docs/PRD/585-mvp-combat-loop-assembly.md`（research PR #664 已 merge）。
> 上游：#573 输入/玩家控制器（bind_input_controller 契约）、#574 火柴人动画（consume_state）、
> #575 战斗实体（6 信号 + is_player/life_total 变体参数）、#576 HUD（bind_player/set_target_enemy
> + low_health_changed 边沿）、#577 判定（bind_entities/bind_input + 五结果事件）、#578 复活
> （bind_player 编排器先例）、#579 反馈（bind_judge/subscribe_entity/camera_path）、#580 处决
> （5 项 bind 契约）、#581 敌人 AI（bind_entity + player/judge 注入）、#582 氛围（set_low_health
> 入口）、#583 战斗舞台（battle_stage.tscn 出生点/StageCamera 消费契约）。
> ✅ 代码状态：#666 已合并，`main_battle.gd`（MainBattle BattleAssembler）/
> `test_main_assembly.gd`（24 用例）/ `e2e_main_assembly_capture.tscn` + `.gd` /
> Main.tscn 追加挂载（+BattleStage 实例 + MainBattle 节点）/ constants.gd「组装编排」
> # DRAFT 分区 / run_tests.gd 挂载 / smoke_test.gd Scenario II / e2e_shots.json assembly 组
> 全部落地 **main**（2026-08-20）。**组装完成即游戏可玩**（AC4：5-10 分钟完整 MVP 闭环）。
> 组装编排 4 常量（余韵/字幕时序/教学延时）+ 2 组 taste 文案候选为 `# DRAFT`，定稿归
> #584/用户（E2E assembly 组截图用户裁决），实现期禁止二选一偷定。

## 1. 设计意图

**问题本质是「17 个零件全部就位、彼此零接线，游戏不可玩」。** #573–#584 逐个交付了玩家
控制器/火柴人/战斗实体/判定器/HUD/反馈/复活/处决/AI/场景/氛围，每个组件都预留了 `bind_*` /
`subscribe_*` / `bind_entities` 程序化注入契约——这些契约就是为组装准备的（#573 PRD 红线
「Main.tscn 不修改；玩家实体的场景挂接由后续战斗场景 issue 负责」——**#585 就是那个「后续」**）。
#666 交付 = **`main_battle.gd` BattleAssembler 编排脚本（装配 + 接线 + 游戏状态编排）+ Main.tscn
追加挂载 + 失败字幕 / 余韵 / 教学提示三个缺失子系统 + test_main_assembly.gd 24 用例 + smoke
AC4 场景 + e2e assembly 组**。组装完成即 MVP 可玩版本（AC4：5-10 分钟可验证核心玩法）。

设计哲学四条（与 PRD §4 推荐组合逐项对齐，方案 B/C 显式否决，无分歧）：

1. **装配程序化**——所有实例化/定位/bind 都在 `main_battle.gd` 的 `_ready()` 同步完成，
   Main.tscn 只加 1 个 `Node2D` + 脚本节点和 1 个 battle_stage 实例（Approach A）。组件 bind
   契约（player/judge 引用、Camera2D path）无法纯声明注入，程序化是唯一可行路径；
2. **接线集中化**——13 项接线清单（PRD §8）全部收敛到一个可单测脚本，与组件既有测试模式
   （程序化实例化）天然对齐；
3. **编排状态化**——assembler 持轻量游戏状态机 `IDLE → COMBAT → KILL → AFTERGLOW → FAIL`
   （idle/combat/kill 为被动观察态，afterglow 由 5s Timer 驱动，fail 为终态），失败字幕/余韵
   时序全部状态机内编排；
4. **组件零改动**——17 个组件全部只消费不修改；发现缺口 → 回退对应 Issue 修复（红线）。

## 2. 架构决策

| 决策点 | 采纳方案 | 否决方案 | 否决理由 |
|--------|---------|---------|---------|
| 组装策略 | A：单一编排脚本 `main_battle.gd`（BattleAssembler，Node2D） | B：全声明式 Main.tscn / C：独立战斗场景 + Main 切换 | B 无法满足 bind 契约（player/judge 引用、Camera2D path 纯声明注入不可行）+ 17+ 处信号手写易错；C 对 MVP 单场景过重（无切换需求，标题场景含 Atmosphere 需迁移），且增加软锁面（PRD §4.1） |
| 失败字幕 | A：复用 Main 既有 CanvasLayer 程序化 Label 淡入 + 输入冻结 + AI 停止 | B：独立 game_over.tscn / C：HUD 扩展承担 | B MVP 过重且需场景切换状态机；C 越权（HUD 管战斗条/提示，不管全局失败编排）（PRD §4.2） |
| 击杀余韵 | A：assembler 内轻量状态机 + 5s Timer | B：独立 StageController 节点 / C：裸 Timer 无状态 | B 多一层抽象 MVP 不需要；C 可读性差、难断言（PRD §4.3） |
| 低血氛围 | 单点接线 `hud.low_health_changed → atmosphere.set_low_health` | —（唯一接线路径无竞争） | #576 边沿信号 + #582 入口都已就绪，只差一行 connect（PRD §4.4） |
| 敌人数量 | MVP 单敌（EnemySpawnA），EnemySpawnB 备用 | 双敌（A/B 同时实例化） | CombatJudge/ExecutionOrchestrator 均为单敌契约，多敌波次超出 MVP 范围，AC 无多敌要求 |
| 输入冻结 | `ic.set_process(false)`（InputController 停轮询） | PlayerController 禁用 | 简单直接，test 断言 attack/guard 不再产生意图事件 |
| AI 停止 | `enemy.set_physics_process(false)`（AI `_physics_process` 消费 move_intent） | 改 enemy_ai.gd 加接口 | 零改动红线：既有 `_dead` 全禁与停用二选一，停物理进程最直接 |

## 3. 组件结构

### 3.1 main_battle.gd — MainBattle（BattleAssembler 组装编排脚本）

`MainBattle (extends Node2D, class_name MainBattle)` —— 挂 Main.tscn 下同名节点，`_ready()`
13 步同步装配（全部首帧前就绪，PRD §7 实验 1 预期 0 顺序敏感点）。**Signals（本组件不发业务
信号，对外暴露供测试/E2E 断言）**：

```gdscript
signal game_state_changed(from_state: String, to_state: String)  # 游戏状态机迁移广播（test/E2E 断言）
signal fail_subtitle_shown()                                     # 失败字幕显示完成（断言恰好一次）
```

**State Properties：**

```gdscript
enum GameState { IDLE, COMBAT, KILL, AFTERGLOW, FAIL }
var game_state: int = GameState.IDLE          # public 供测试/E2E 读取
var player / enemy / player_entity / enemy_entity   # 组件引用缓存（test 断言 bind 目标非 null，AC5）
var judge / hud / reaction / execution / revive / atmosphere
var fail_label: Label        # 失败字幕（挂 Main/CanvasLayer，public 供测试断言）
var tutorial_label: Label    # 教学提示（挂 Main/CanvasLayer，public 供测试断言）
var _fail_handled: bool = false       # 失败路径幂等守卫（二次 died(true) 不再重演）
var _afterglow_started: bool = false  # 余韵幂等守卫（二次 died(true) 不重启 Timer）
```

**装配顺序（§4 Flow 4 顺序契约，即依赖顺序）**：

1. 定位既有节点（`../BattleStage` / `../CanvasLayer` / `../Atmosphere` / `/root/InputController`，
   `get_node_or_null` headless 兼容）
2. 玩家装配 `_build_player()`：`PlayerController.new()`（CharacterBody2D，组 `player`）→
   instance `player_stick_figure.tscn` 作视觉子节点 → `CombatEntity.new({is_player=true, life_total=2})`
   → `bind_input_controller(ic)` → `entity.state_changed → stick.consume_state(to)`（lambda 转发第二参）
3. 玩家定位 PlayerSpawn（stage 消费）
4. Judge 节点先建（敌人装配的 judge 引用依赖）
5. 敌人装配 `_build_enemy()`：`EnemyAI.new()`（`player`/`judge` 注入 + waypoints 由
   EnemySpawnA/B 坐标派生）+ stick figure 视觉 + `CombatEntity.new({is_player=false, life_total=1})`
   + `bind_entity(enemy_entity)` + 放置 EnemySpawnA；`state_changed → consume_state(to)` +
   `_on_enemy_entity_state_changed`（敌人首次进 attack 态且 IDLE → COMBAT）
6. Judge bind（**必须先于首帧 resolve**）：`bind_entities(player_entity, enemy_entity)` + `bind_input(ic)`
7. HUD：`HudLayer(CanvasLayer) → Hud` + `bind_player` + `set_target_enemy`
8. Reaction：`camera_path = ^"../BattleStage/StageCamera"` **必须先于 add_child 设置**（其 _ready 读取）
   + `bind_judge` + `subscribe_entity` ×2
9. Revive：`bind_player(player_entity)`
10. Execution 5 项全 bind：`bind_player/bind_enemy/bind_judge/bind_input/bind_feedback`
11. 低血氛围单点接线：`hud.low_health_changed.connect(atmosphere.set_low_health)`
    （headless 免 Main 树时引用 null → no-op 不崩溃）
12. 失败路径：`player_entity.died.connect(_on_player_final_death)`
13. 余韵路径：`enemy_entity.died.connect(_on_enemy_final_death)` + 教学提示 + 隐藏标题卡 + `IDLE`

**状态迁移唯一入口 `_set_game_state(next)`**：同态幂等 + **FAIL 终态守卫**（不再迁移）+
广播 `game_state_changed` 名字符串。

**失败路径 `_on_player_final_death(entity, final)`**：`final==true` → `_fail_handled=true` →
FAIL 态 → 输入冻结 `ic.set_process(false)` + AI 停止 `enemy.set_physics_process(false)` →
`_show_fail_subtitle_delayed()`。

**余韵路径 `_on_enemy_final_death(entity, final)`**：`final==true` → `_afterglow_started=true` →
KILL（HUD 击杀提示自动触发，零接线）→ AFTERGLOW → `AFTERGLOW_SECONDS` Timer 到期回 IDLE
（敌人重生不在 MVP 范围，AC3 只要求空闲 ≥5s）。

**教学提示 `_setup_tutorial_hint()`**：隐藏标题 `CenterContainer`（节点保留，#572 语义可回归）+
CanvasLayer 顶部 Label（`PRESET_CENTER_TOP`，`HUD_MOON_WHITE`，初始隐藏透明）+
`TUTORIAL_HINT_DELAY` Timer 到期 `_show_tutorial_hint()`：淡入 0.5s → 停留 2.5s → 淡出 0.5s → 隐藏。

**节点树（运行期构建）**：

```
Main (Node2D, Main.tscn)
├── WorldBackdrop / CanvasLayer(标题/版本/探针) / Atmosphere  ── 既有，零删改
├── BattleStage (instance battle_stage.tscn)                  ── 追加（不重复挂 Atmosphere，#583 约定）
│   ├── PlayerSpawn (Marker2D @ 640,560) / EnemySpawnA @ 700,560 / EnemySpawnB (备用)
│   └── StageCamera (Camera2D current)
└── MainBattle (Node2D, script = main_battle.gd)              ── 追加（本系统）
    ├── Player (PlayerController, 组 player) @ PlayerSpawn
    │   ├── PlayerStickFigure (instance player_stick_figure.tscn)
    │   └── PlayerEntity (CombatEntity, is_player=true, life_total=2)
    ├── Enemy (EnemyAI) @ EnemySpawnA
    │   ├── EnemyStickFigure (instance player_stick_figure.tscn)
    │   └── EnemyEntity (CombatEntity, is_player=false, life_total=1)
    ├── Judge (CombatJudge) / Reaction (ReactionController, camera_path=StageCamera)
    ├── Execution (ExecutionOrchestrator) / Revive (ReviveOrchestrator)
    └── HudLayer (CanvasLayer) ── Hud
```

### 3.2 失败字幕（缺失子系统 1）

复用 Main 既有 CanvasLayer 程序化创建 `Label`（`PRESET_FULL_RECT` 居中，初始 `visible=false`、
`modulate.a=0`，font_size 36 白色）；不新建场景。时序：`player.died(final=true)` → FAIL 态 →
输入冻结 + AI 停止 → 延迟 `FAIL_SUBTITLE_DELAY` → Tween 淡入 `FAIL_SUBTITLE_FADE_SECONDS` →
常驻 + 广播 `fail_subtitle_shown()`（恰好一次）。文案取候选清单首项（taste-draft 待用户定稿）。

### 3.3 教学提示（缺失子系统 3，开场情绪弧「教学」）

开局 `TUTORIAL_HINT_DELAY` 后顶部浮现操作提示 Label（移动/攻击/格挡键位），淡入 0.5s →
停留 2.5s → 淡出 0.5s → 隐藏。提示期间战斗照常（只读不阻塞）；文案取候选清单首项
（taste-draft 待用户定稿）。

### 3.4 Main.tscn — 追加挂载（唯一场景修改）

```tscn
[ext_resource type="PackedScene" path="res://scenes/battle_stage.tscn" id="2_battle_stage"]
[ext_resource type="Script" path="res://gdscripts/main_battle.gd" id="3_main_battle"]

[node name="BattleStage" parent="." instance=ExtResource("2_battle_stage")]
[node name="MainBattle" type="Node2D" parent="."]
script = ExtResource("3_main_battle")
```

不删除 WorldBackdrop / CanvasLayer 标题 / VersionLabel / PostMergeProbeLabel（标题 CenterContainer
由 assembler `_ready` 隐藏）；`project.godot` 零改动（main_scene 已是 Main.tscn）。

> #675（2026-08-20 merge）：WorldBackdrop 追加 `z_index = -2`（背景垫底，修复 #654/#666 引入的
> 背景盖火花缺陷——层级约定「背景 < 火花 < 角色」详见 15-COMBAT-FEEDBACK-SYSTEM §9；本组装场景
> 间接受益：assembly 组 02_parry_execute 截图恢复火花可见）。

### 3.5 constants.gd — 「组装编排」# DRAFT 分区（文件尾部追加）

| 常量 | 值（# DRAFT） | 语义 | 候选集 |
|------|:---:|------|:---:|
| `AFTERGLOW_SECONDS` | 5.0 | AC3：击杀后场景空闲 ≥5s 情绪余韵，雪花持续（Atmosphere 无暂停路径，天然持续） | [5.0, 6.0, 8.0] |
| `FAIL_SUBTITLE_DELAY` | 0.5 | AC2：死亡反馈（白闪/屏震 #579）播完后 ≥0.5s 字幕开始淡入 | [0.3, 0.5, 1.0] |
| `FAIL_SUBTITLE_FADE_SECONDS` | 1.0 | 字幕淡入时长 | [0.8, 1.0, 1.5] |
| `TUTORIAL_HINT_DELAY` | 3.0 | 情绪弧「教学」：开局 3s 内浮现操作提示 | [2.0, 3.0, 5.0] |
| `FAIL_SUBTITLE_CANDIDATES` | Array[String] ×5 | B5 失败表达候选 5 选 1（taste-draft 待用户定稿） | 『雪落无声。村口只剩你。』『雪还在下。村口没人了。』『灯灭了。雪落无声。』『村口只剩下雪。』『刀还在。你没了。』 |
| `TUTORIAL_HINT_CANDIDATES` | Array[String] ×3 | 教学提示文案候选（taste-draft 待用户定稿） | 『村口有动静。握紧你的刀。』『←→ 移动 · J 攻击 · K 格挡』『雪夜村口，有人来了。』 |

实现期禁止裁决任何候选值/文案（定稿归 #584/用户）。

## 4. 数据流

### Flow 1: 完整战斗闭环（正常路径，AC1/AC4 核心）

```
① 玩家出生   _ready() 装配完成 → Player @ PlayerSpawn，IDLE 态
② 遇敌       EnemyAI 感知（120° 6m）→ chase → 敌人 entity 进 attack 态
             → assembler 首次接战 IDLE→COMBAT；判定器自动登记窗口（#577）
③ 攻击/弹反  玩家 attack_pressed → CombatJudge.resolve_attack → parry_success
             → ReactionController 火花/hit-stop/屏震/白闪（#579 已接）
             → 敌人 stance_broken → ExecutionOrchestrator armed 窗口（#580 已接）
④ 敌人崩解   stance_broken → 敌人 entity 进 stance_break 态 → stick anim_stance_break
⑤ 处决       armed 窗口内 attack_pressed + 距离 ≤ EXECUTE_RANGE → execute 转移
             → execute_kill → enemy died(final=true) → S 级反馈 + 淡出（#580 全链路，组装只 bind）
⑥ 击杀       enemy died(true) → HUD 击杀提示（#576 自动）→ assembler KILL → AFTERGLOW
⑦ 余韵       afterglow Timer 5s（雪花持续，Atmosphere 天然）→ 到期回 IDLE（等待再战）
```

### Flow 2: 失败路径（AC2，终态）

```
玩家 life_1 耗尽 → died(entity, false) → ReviveOrchestrator 计时 → revive()（#578，半管血）
玩家 life_2 耗尽 → died(entity, true) → assembler FAIL 态（终态，幂等守卫不再迁移）
  → 输入冻结（ic.set_process(false)）+ EnemyAI 停用（set_physics_process(false)）
  → FAIL_SUBTITLE_DELAY(0.5s) → FailLabel Tween 淡入 1s → 常驻（文案 ∈ 候选清单，取首项）
```

### Flow 3: 余韵期间交互（AC3 边界）

```
AFTERGLOW 态：玩家移动 = 只读（InputController 仍轮询，PlayerController 正常物理）
  攻击 = 自然落空（无目标/敌人已死，判定器无窗口可 resolve，无错误无软锁）
  → 5s 到期 → IDLE（敌人重生不在 MVP 范围）
```

## 5. 测试与 E2E

### 5.1 test_main_assembly.gd — 组装测试套件（24 用例，run_tests.gd 以 MainAssembly 挂载，末位运行）

| Scenario | 用例 | 覆盖 |
|---------|------|------|
| A 挂载完整性 | A1-A4 | Main 可加载 + MainBattle 节点/script；bind 目标引用全非 null（AC5 无 pending）；BattleStage/出生点/StageCamera 路径可达；标题 CenterContainer 隐藏 |
| B 信号链连通 | B1-B7 | 玩家动画链（state_changed→consume_state）；判定链（窗口登记/resolve 产出）；处决链（stance_broken→armed→execute→died(true) 恰好一次）；HUD 链（hp_changed/击杀提示）；反馈链（trigger_feedback mock）；复活链（died(false)→revive）；氛围链（低血边沿恰好各一次） |
| C 完整闭环 | C1 | 程序化驱动 出生→遇敌→弹反→崩解→处决→击杀，`game_state_changed` 观测 IDLE→COMBAT→KILL→AFTERGLOW 全可达无软锁 |
| D 失败路径 | D1-D5 | 双死→字幕（文案 ∈ 候选清单）；FAIL 后输入无效果；AI 停用；终态幂等（fail_subtitle_shown 恰好一次）；单死不失败（复活路径接管） |
| E 余韵 5s | E1-E3 | 时序（<5s 不变、≥5s 回 IDLE）；只读输入不打断/无目标攻击落空无报错；雪花持续 |
| F 防回归 | F1-F3 | 漏接线断言红；处决窗口错过→recover_from_break 再战；Main.tscn 资源路径错误断言红 |

headless 约束：禁止 `:=` 类型推断（4.7.1 硬错误）；组件脚本一律 `load()` 访问（禁 class_name
标识符引用）；autoload 经 `root.get_node_or_null("InputController")` 运行时获取；组件
_process/timer 全部手动驱动（`tick_frame()`/`timeout.emit()`/tween custom_step 同步推进），
零 await；释放用立即 `free()`（hud._ready 经 group "hud" queue_free 重复实例会污染后续场景）。

### 5.2 smoke_test.gd — Scenario II（AC4 完整闭环）

程序化 `load("res://scenes/Main.tscn").instantiate()` 挂树 → 手动驱动 120 帧 → 断言 5 阶段可达
（IDLE→COMBAT→KILL→AFTERGLOW→回 IDLE）+ 失败字幕子场景（双死 → FailLabel.visible == true 且
文案 ∈ 候选清单）→ exit 0。

### 5.3 e2e assembly 组（e2e_shots.json 追加）

rig：`scenes/e2e_main_assembly_capture.tscn` + `gdscripts/e2e_main_assembly_capture.gd`
（CaptureRig 契约，state 轮询驱动，照 e2e_battle_stage_capture 模式）。

| shot | 场景 | 供用户裁决（taste） |
|------|------|------|
| 01_spawn_combat | 出生遇敌（COMBAT 态） | 开场构图 |
| 02_parry_execute | 弹反崩解处决 | 处决构图 |
| 03_fail_subtitle | 失败字幕 | 失败文案 5 选 1 |
| 04_afterglow | 击杀余韵雪幕 | 余韵节奏 |

## 6. 边界情况

| 边界情况 | 缓解措施 |
|---------|---------|
| execute 态再按攻击 | #580 armed 已清除 + `request_transition("execute")` 幂等；test 验证不重复触发 |
| 复活无敌期受击 | #578 无敌期 take_damage no-op 双保险；组装验证接线后仍生效 |
| 处决演出期间玩家受击 | #575 take_damage execute 态 no-op 守卫 + 判定器跳过守卫（已实现） |
| 敌人 final death 后 AI | #581 `_dead` 全禁 + #580 `_on_enemy_died` 自动解绑防 queue_free 后访问（已实现） |
| 低血边沿恰好一次 | #576 边沿触发语义；test 断言恰好一次 true/false（不重入不漏发） |
| 余韵期间无目标攻击 | 自然落空无错误无状态迁移（test 注入攻击断言） |
| 失败字幕出现后再输入 | 输入已冻结（ic.set_process(false)），无状态迁移无软锁 |
| 组装顺序依赖 | bind 全在 `_ready()` 同步完成；test 按 Flow 4 顺序驱动断言首帧 resolve 正常（PRD §7 实验 1，0 顺序敏感点） |
| 标题卡遮挡 | assembler `_ready` 隐藏 CenterContainer（节点保留），MVP 开场直进雪夜村口 |
| 教学提示与战斗重叠 | 提示 3s 后淡出；提示期间战斗照常（只读不阻塞）；test 断言淡出后无残留节点 |
| 双死竞态（died(true) 与 revive 竞争） | #578 终态 revive() 被拒（已实现）；assembler 只消费 final==true，幂等进 FAIL |
| Atmosphere 缺省（headless 测试无 Main 树） | `get_node_or_null` 可空引用，低血接线 no-op 不崩溃 |

## 7. 明确不修改 / 不定稿

- **零改动** 全部 17 个既有组件脚本（只消费 bind/subscribe 契约）；发现缺口 → 回退对应 Issue 修复
- **零改动** `project.godot`（main_scene 已是 Main.tscn；autoload Game/InputController 已注册）
- **不删除** Main.tscn 既有节点（WorldBackdrop/CanvasLayer 标题/VersionLabel/PostMergeProbeLabel/Atmosphere）——只隐藏标题 CenterContainer
- **不新增** 视觉/音频资产（全部复用程序化组件；敌人视觉复用 SW-003 火柴人骨架）；不引入第三方 addon（开源调研结论：成熟模板均为独立完整方案，与 17 组件契约冲突，编排模式作参考）
- **不定稿任何 `# DRAFT` 值**（余韵/字幕时序/教学延时）+ **不裁决 taste 文案**（失败字幕 B5 候选 5 选 1 + 教学提示候选，随 PR 附清单待用户定稿）
- **敌人重生 / 多敌波次不在 MVP 范围**（EnemySpawnB 保留备用；AC3 只要求击杀后空闲 ≥5s）

# Design: [Feature] 战斗实体基类与状态机（CombatEntity + 11 态战斗状态机）

> **Parent Issue:** #575
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4 五决策点**全部确认采纳方案 A** —— ①状态机架构 = `StateMachineBase` 派生 + 集中转移合法性表（否决 enum+match：与 #572 地基重复造轮子、enum→String 契约双维护易漂移；否决 LimboAI addon：#572 已裁决不引入第三方）；②玩家/敌人变体 = 单类 + `@export` 参数（否决双子类/策略组合：MVP 无多态需求）；③数据所有权 = 实体自持 + constants 初始化 + 信号广播（否决 Game autoload 全局：多敌人实例无法区分）；④输入→状态映射 = 实体内嵌 `_StateInputBridge` 订阅 InputController 信号（否决放 #585 组装层/PlayerController：状态契约权威在本层）；⑤两段血 = `_active_life` 双条独立计数
> **Reference PRD:** `docs/PRD/575-combat-entity-state-machine.md`（research PR #615 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/572-scaffold-main-entry.md`（StateMachineBase 三接口派生 + constants # DRAFT 注释规范「候补值+影响什么+情感断言」+ run_tests.gd `_run()` 挂载模式）；`docs/DESIGN/574-stick-figure-silhouette-animation.md`（状态对象写法范本 `stick_figure_anim_states.gd`：RefCounted 内部类 + 工厂 make_state；DESIGN 文档结构）；`docs/DESIGN/573-input-map-player-controller.md`（InputController 意图信号契约：attack_pressed / heavy_attack_pressed / guard_pressed(timestamp_ms) / guard_held / revive_pressed）
> **所有权:** `content_ownership: mechanical`（数据容器 + 状态转移拓扑 + 信号契约 = 机械工程，无品味裁决空间；手感数值全量 # DRAFT **只读不裁决**，定稿归 #584；本层新增时序常量同样标 # DRAFT 候补值+影响+情感断言，禁止实现期偷定）
> **深度:** deep（PRD 标注 depth: deep；3 新脚本 + 1 新测试文件 + 2 修改文件，跨 4 子系统：数据层/状态对象层/转移表/输入桥，且为 #576/#577/#578/#580/#581/#585 的下游契约源）—— 产出 **DESIGN + TASKS** 文档
> **并行上下文:** worktree 并行 —— constants.gd 为**追加式新增时序常量**（新开「战斗时序」分区，不触碰既有 8 分区常量行，与 #584 调参面板无同区改写冲突）；新文件全部独立命名（`combat_*` / `test_combat_entity.gd`）；唯一共享文件 = `tests/run_tests.gd`（追加一行 `_run()`，当前无并发 impl 在改它；#576/#577/#578/#580/#581 均未开始）

---

## 1. 架构总览

**问题本质是「有地基、无战斗层」。** shandong-wolf 经 #572/#573/#574/#584 已具备全部地基：StateMachineBase（RefCounted 三接口 + 同态守卫 + 防重入锁，注释明言「#575 战斗实体状态机在其上定义具体状态」）、WolfConstants 全量 # DRAFT 数值（两条命/架势/刀伤害/帧节奏）、InputController 意图事件信号、StickFigureController.consume_state 11 态动画契约。但 `gdscripts/` 无任何 hp/stance 数据容器、无 11 个 canonical 战斗状态对象、无转移合法性执行层——**本 issue 交付 = 战斗数据层 + 状态机层，是全部下游战斗系统（#576 HUD / #577 判定 / #578 复活 / #580 处决 / #581 敌AI）的契约源头**。

**设计哲学：数据即状态、状态即契约、转移即查表、变体即参数。**
1. **数据即状态**：CombatEntity 是 hp（两段式）/stance/facing 的唯一数据容器，HUD/判定/动画全部从这里读；两段血 = hp_1/hp_2 两条独立计数，`_active_life` 标记当前受击条。
2. **状态即契约**：11 个 canonical 状态名（idle/move/attack/heavy_attack/guard/parry_success/stagger/stance_break/execute/revive/dead）是本 issue 的**唯一权威来源**，逐字对齐 #574 consume_state 的 ANIM_CLIP_NAMES 键集——禁止自造状态名（parry 单列 / run 代替 move 都是红线）。
3. **转移即查表**：`request_transition(to)` 是唯一转移入口；合法性检查 = 数据驱动转移表（拓扑合法性）+ 守卫函数（条件合法性）两层——杜绝「任何代码直接改状态」的漂移风险（AC2 核心）。
4. **变体即参数**：玩家与敌人共用同一类，差异 = `@export` 参数（is_player / life_total / 血量 / 架势上限），与 issue body「差异通过参数配置」逐字一致。

```
                    ★ Issue #575 本设计（shandong-wolf 战斗数据+状态层）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 新建（4 文件，全部 shandong-wolf/ 下）                                          │
│  gdscripts/combat_entity.gd        CombatEntity（Node2D）—— 数据容器 + 转移入口 │
│                                    + _StateInputBridge 输入桥（is_player 启用） │
│  gdscripts/combat_state_table.gd   11 态转移合法性表（TRANSITIONS + is_legal）  │
│  gdscripts/combat_states.gd        CombatStateBase + 11 状态对象（派生          │
│                                    StateMachineBase，帧/秒常量驱动自动退出）    │
│  tests/test_combat_entity.gd       受击/架势/死亡 3 主路径 + 121 对遍历 + 变体   │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（2 文件）                                                                │
│  gdscripts/constants.gd            追加「战斗时序」# DRAFT 分区 5 常量（§2.1）  │
│  tests/run_tests.gd                追加 _run(test_combat_entity)（smoke 可选） │
├──────────────────────────────────────────────────────────────────────────────┤
│ 消费方（0 改动，后续 issue 挂接）                                               │
│  #574 动画 → consume_state(state_name)；#576 HUD → hp/stance/state 信号         │
│  #577 判定 → take_damage/take_stance_damage；#578 复活 → dead/revive/revive()  │
│  #580 处决 → stance_break→execute 通道；#581 敌AI → enemy 变体参数              │
│  #585 组装 → PlayerController+CombatEntity+StickFigureController 信号桥接      │
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    ▼
      InputController 信号 ──► _StateInputBridge ──► request_transition(to)
        （attack/heavy_attack/guard/revive + move 轴轮询）   │
                                        combat_state_table.is_legal(from,to) ──非法──► reject + push_warning
                                            │ 合法
                                            ▼
                                    fsm.transition_to(state_obj)
                                            │
              state_changed(from,to) ──► #574 consume_state(to) 播动画；#576 HUD 状态提示
                                            ▼
                              CombatState.update(delta)（定时状态帧计数自动退出 → idle）
                                            │
      #577: take_damage ──► hp 扣减 ──hp_1≤0──► die() ──► dead + died(final) 信号
      #577: take_stance_damage ──► stance 扣减 ──≤0──► break_stance() ──► stance_broken 信号 ──► #580
      #578: revive() ──► dead→revive（1s）→idle，hp_2=50 接管，无敌 1s，架势清空
```

**与 PRD 方案裁决的一致性：** PRD §4.1/§4.2/§4.3/§4.4 各推荐方案 A，本设计逐项确认采纳，无分歧。PRD §7 四个 Spike（转移表覆盖性 / 两段血时序 / 架势上限派生 / 变体冒烟）的**预期结论已直接内化为本设计决策**：①转移表 = 拓扑合法性 + 守卫 = 条件合法性的两层设计，attack 中连段走同态重入钩子（见 §2.3/§2.4）；②状态序列 `idle→dead→revive→idle→dead` 精确复现，hp_2 独立计数；③架势上限 MVP 固定 POSTURE_BREAK_THRESHOLD，预留 `_recalc_stance_max()` 钩子；④单类双变体 headless 全流程可测。若 Spike 实测推翻任一内化结论，implement 需在 PR 中说明偏离及理由。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实 origin/main eb00d2d） | 与 #575 的差距 |
|------|--------------------------------------------------|---------------|
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ `StateMachineBase`（RefCounted + class_name）：状态对象 enter/exit/update 三接口 + `transition_to()`（同态守卫 + 防重入锁 + null 安全）；文件头注释明言「派生: #575 战斗实体状态机在其上定义具体状态」 | ✅ 可直接派生 11 个战斗状态对象，零改动 |
| `shandong-wolf/gdscripts/constants.gd` | ✅ `WolfConstants`（RefCounted + class_name），8 个 # DRAFT 分区：弹反窗口/架势回复/两条命/刀伤/帧节奏/刀光/输入/受击敌人处决；已含 LIFE_TOTAL=2、LIFE_1_MAX=100、LIFE_2_ABS=50、POSTURE_BREAK_THRESHOLD=100、POSTURE_RECOVERY_PER_SEC=25、SWORD_DAMAGE_LIGHT=12/HEAVY=30/EXECUTE=999、FRAME_ATTACK_WINDUP=8、FRAME_ATTACK_RECOVERY=14、FRAME_RHYTHM_BASE=60、FRAME_ANIM_EXECUTE_TOTAL=5 | ❌ 无本层时序常量（STAGGER_FRAMES / PARRY_SUCCESS_FRAMES / STANCE_BREAK_RECOVERY_SEC / REVIVE_SECONDS / INVINCIBLE_SECONDS）——追加式新增（§2.1） |
| `shandong-wolf/gdscripts/input_controller.gd` | ✅ `InputController`（autoload，lazy）：9 意图信号（attack_pressed / heavy_attack_pressed / guard_pressed(timestamp_ms) / guard_held / dash_pressed / jump_pressed / interact_pressed / revive_pressed）+ 输入缓冲队列（poll_buffer/peek_buffer/buffer_size）+ get_move_axis() | ✅ 输入桥直接订阅 attack/heavy_attack/guard/revive 信号 + 轮询 get_move_axis()，零改动 |
| `shandong-wolf/gdscripts/player_controller.gd` | ✅ `PlayerController`（CharacterBody2D）：_physics_process 加速度移动，消费 get_move_axis()，组 "player" | 不修改；facing 同步由输入桥轮询轴完成（§2.5） |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | ✅ `consume_state(state)` 唯一动画入口 + `_resolve_canonical(state)` 归一 | 不修改；本层产出与 canonical 集合同名的 state_name，契约对齐（§6） |
| `shandong-wolf/gdscripts/stick_figure_anim_states.gd` | ✅ 11 个动画状态对象（AnimStateIdle..Dead 内部类 + `make_state` 工厂 + ANIM_CLIP_NAMES 键集 = canonical 11 名） | ✅ 状态对象写法范本（§2.3 同构）；implement 后跑其单测验证状态名逐名匹配（§8 场景 F） |
| `shandong-wolf/gdscripts/game.gd` | ✅ `Game` autoload 锚点（preload constants + DebugCanvas） | 无改动 |
| `shandong-wolf/gdscripts/` | ❌ 无任何 combat 脚本 | 本 issue 全部新建（combat_entity / combat_state_table / combat_states） |
| `shandong-wolf/scenes/Main.tscn` | ✅ 纯声明式标题场景 | **不修改**（红线）；实体实例化进场景归 #583/#585 |
| `shandong-wolf/tests/run_tests.gd` | ✅ 已挂 6 套件（StateMachine/Constants/StickFigureAnimation/InputController/PlayerController/DebugCanvas），`_run()` 模式 | ❌ 追加 `_run("res://tests/test_combat_entity.gd", "CombatEntity")` |
| `shandong-wolf/tests/smoke_test.gd` | ✅ 冒烟绿（I1 位移 / I2 边沿信号） | 可选追加实体实例化探针（§3） |
| `shandong-wolf/tests/test_state_machine.gd` | ✅ 状态机单测范本（Mock 内部类 + 调用序断言 + `_assert` 模式） | 测试写法范本（§8） |
| `mini-pong/` | ✅ 视觉体系先例 | 仅作模式参考，**不复制**（跨游戏红线） |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| StateMachineBase 派生点已预留（注释「#575 在其上定义具体状态」） | ✅ 属实（state_machine.gd 头注释 + 三接口 + 同态守卫 + 防重入锁） | combat_states.gd 直接派生；状态对象写法与 stick_figure_anim_states.gd 同构 |
| constants 已含两条命/架势/刀伤害/帧节奏全量 # DRAFT | ✅ 属实（LIFE_TOTAL/LIFE_1_MAX/LIFE_2_ABS、POSTURE_*、SWORD_DAMAGE_*、FRAME_ATTACK_*、FRAME_ANIM_EXECUTE_TOTAL） | 只读消费；本层 5 个时序常量**尚不存在** → 追加式新增（§2.1） |
| InputController 有 attack_pressed/heavy_attack_pressed/guard_pressed(timestamp_ms)/guard_held/revive_pressed | ✅ 属实（9 意图信号齐全，guard_pressed 仅时间戳） | 输入桥订阅这 5 个信号（dash/jump 不映射，垫步/跳留在移动层） |
| #574 consume_state 消费 11 态 canonical 状态名 | ✅ 属实（ANIM_CLIP_NAMES 键集 = idle/move/attack/heavy_attack/guard/parry_success/stagger/stance_break/execute/revive/dead，与 issue body 契约逐字一致） | 本层 state_name 逐名对齐；转移表以该集合为全集 |
| run_tests.gd `_run()` 挂载模式可用 | ✅ 属实（6 套件挂载） | 追加 test_combat_entity 一行 |
| **（PRD 未覆盖的设计点）** move/idle 状态由谁驱动 | PRD §4.4 只定义了 attack/heavy_attack/guard 三个输入映射，**未定义 move 状态驱动方**；PlayerController 是纯移动实体不产状态名 | 设计裁决：输入桥轮询 `get_move_axis()`（axis≠0 → move，=0 → idle，仅当实体处于 idle/move 时生效），同时同步 facing（§2.5）——headless 可 mock（手动设 axis 或直接 request_transition） |
| **（PRD 未覆盖的设计点）** attack 中再按 = 连段链如何实现 | StateMachineBase 同态守卫会静默忽略 attack→attack | 设计裁决：转移表允许 attack→attack（拓扑合法）；`request_transition` 同态重入时调用状态对象可选 `restart()` 钩子（AttackState 实现：仅收招 phase 重置帧计数 = 连段，前摇/暴发期忽略）——两层设计落地（§2.3/§2.4） |

---

## 2. 新组件 — 详细设计

### 2.1 `gdscripts/constants.gd` — 追加「战斗时序」# DRAFT 分区（修改）

追加式新增分区（不触碰既有 8 分区任何一行），5 个时序常量，注释遵循 #572 规范（候补值 + 影响什么 + 情感断言）：

| 常量 | 候补值 | 影响 | 情感断言 | 消费方 |
|------|--------|------|---------|--------|
| `STAGGER_FRAMES` | 12（候选 [8,12,16]） | 受击硬直时长——太短无受击感，太长卡操作 | 硬直是「被打断」的代价，不是「罚站」 | StaggerState（§2.3） |
| `PARRY_SUCCESS_FRAMES` | 10（候选 [8,10,12]） | 弹反成功瞬间帧（硬直窗口，#577 驱动进入） | 弹反成功必须比格挡爽（只狼铁律 1） | ParrySuccessState |
| `STANCE_BREAK_RECOVERY_SEC` | 3.0（#580 同值互引） | 崩解后敌人起身恢复时间 | 崩解 = 可从容处决的窗口（只狼铁律 2） | StanceBreakState |
| `REVIVE_SECONDS` | 1.0（#578 同值互引） | 倒地→复活的演出时长 | 「还没打完这一仗」，不是神迹 | ReviveState |
| `INVINCIBLE_SECONDS` | 1.0（#578 同值互引） | 复活后无敌时长 | 硬汉的第二次机会，不是耍赖 | CombatEntity（无敌期计时） |

> 全部标 `# DRAFT` 只读；定稿归 #584（调参面板）。实现期**禁止**二选一偷定。

### 2.2 `gdscripts/combat_state_table.gd` — 转移合法性表（新增）

- **File:** `shandong-wolf/gdscripts/combat_state_table.gd`
- **class_name:** `CombatStateTable`（extends RefCounted，静态工具）
- **结构：** 数据驱动 Dictionary + 查询 API，无状态无逻辑分支

```gdscript
extends RefCounted
class_name CombatStateTable

## 11 态转移拓扑（canonical 状态名权威集，与 #574 ANIM_CLIP_NAMES 键集逐字对齐）
const CANONICAL_STATES: Array[String] = [
    "idle", "move", "attack", "heavy_attack", "guard", "parry_success",
    "stagger", "stance_break", "execute", "revive", "dead",
]

## from -> [to, ...]；表外转移一律非法
const TRANSITIONS: Dictionary = {
    "idle":          ["move", "attack", "heavy_attack", "guard", "stagger", "stance_break", "parry_success", "dead"],
    "move":          ["idle", "attack", "heavy_attack", "guard", "stagger", "stance_break", "parry_success", "dead"],
    "attack":        ["attack", "idle", "stagger", "stance_break", "dead"],   # attack→attack = 连段（同态重入钩子）
    "heavy_attack":  ["idle", "stagger", "stance_break", "dead"],
    "guard":         ["idle", "attack", "heavy_attack", "stance_break", "dead", "parry_success"],
    "parry_success": ["idle", "attack", "heavy_attack", "move"],
    "stagger":       ["idle", "dead"],
    "stance_break":  ["idle", "execute", "dead"],
    "execute":       ["idle"],
    "revive":        ["idle"],
    "dead":          ["revive"],                                              # 状态机停摆：仅复活可出
}

static func is_legal(from: String, to: String) -> bool:
    var allowed: Array = TRANSITIONS.get(from, [])
    return allowed.has(to)
```

**转移语义要点（红线案例显式列出）：**
- `stance_break → attack/heavy_attack/guard` **表外 = reject**（AC2 红线：崩解失衡不可攻击/格挡）
- `dead → 除 revive 外全部表外 = reject`（状态机停摆，AC4）
- `guard → stance_break` 表内（边界 5：格挡中崩解 = 失衡，优先级高于格挡姿态）
- `guard → parry_success` 表内（#577 弹反成功驱动入口）
- `attack → attack` 表内（连段拓扑合法；条件合法性 = restart 钩子，见 §2.3/§2.4）
- 同态转移（from == to）除 attack 外：表内无自环，但 `request_transition` 层由 StateMachineBase 同态守卫静默忽略（§5 边界 4）

### 2.3 `gdscripts/combat_states.gd` — CombatStateBase + 11 状态对象（新增）

- **File:** `shandong-wolf/gdscripts/combat_states.gd`
- **结构：** 顶层 `CombatStateBase`（RefCounted）+ 11 个内部类（与 stick_figure_anim_states.gd 写法同构）+ `make_state` 工厂

```gdscript
extends RefCounted
## CombatStates — 战斗状态对象集（#575）。
## 基于 StateMachineBase（state_machine.gd）派生：enter/exit/update 三接口。
## 状态名权威集见 combat_state_table.gd CANONICAL_STATES（与 #574 consume_state 逐字对齐）。

const StateMachineBaseScript = preload("res://gdscripts/state_machine.gd")

static func make_state(state_name: String, entity: Object) -> Object:
    match state_name:
        "idle":          return CombatStateIdle.new(entity)
        "move":          return CombatStateMove.new(entity)
        "attack":        return CombatStateAttack.new(entity)
        "heavy_attack":  return CombatStateHeavyAttack.new(entity)
        "guard":         return CombatStateGuard.new(entity)
        "parry_success": return CombatStateParrySuccess.new(entity)
        "stagger":       return CombatStateStagger.new(entity)
        "stance_break":  return CombatStateStanceBreak.new(entity)
        "execute":       return CombatStateExecute.new(entity)
        "revive":        return CombatStateRevive.new(entity)
        "dead":          return CombatStateDead.new(entity)
        _:               return CombatStateIdle.new(entity)

class CombatStateBase:
    extends RefCounted
    var entity: Object = null        # CombatEntity 引用（转移统一走 entity.request_transition）
    var _elapsed: float = 0.0        # 定时状态帧计数累加

    func _init(ent: Object) -> void:
        entity = ent

    func enter() -> void:
        _elapsed = 0.0               # 进入即重置计时（同态重入 restart 也走 enter 重置）

    func exit() -> void:
        pass

    func update(_delta: float) -> void:
        pass

    ## 可选钩子：同态重入时由 entity.request_transition 调用（仅 AttackState 实现）
    func restart() -> void:
        pass
```

**11 个状态对象设计（定时状态 = 帧/秒常量驱动自动退出；退出统一在 `update()` 内调 `entity.request_transition("idle")`，禁止在 `enter()` 内发起转移——防重入红线，§5 失败 2）：**

| 状态对象 | 进入动作 | update 行为 | 自动退出 |
|---------|---------|------------|---------|
| `CombatStateIdle` | 无 | 无（等待外部转移） | 不自动退出 |
| `CombatStateMove` | 无 | 无（移动位移由 PlayerController 负责，本层只占状态名） | 不自动退出（轴归零 → idle 由桥驱动） |
| `CombatStateAttack` | 重置 phase=0（前摇） | 帧计数：`frame = int(_elapsed * FRAME_RHYTHM_BASE)`；phase 0 前摇（<WINDUP 8 帧）/ 1 暴发（WINDUP..WINDUP+4）/ 2 收招（>WINDUP+4）；累计 ≥ WINDUP(8)+RECOVERY(14)=22 帧 → idle | `request_transition("idle")`；`restart()` 实现：**仅 phase==2（收招）时**重置 `_elapsed=0` 回前摇 = 连段成立；phase 0/1 时忽略 |
| `CombatStateHeavyAttack` | 无 | 帧计数累计 ≥ 22 帧（复用 FRAME_ATTACK_WINDUP+RECOVERY，无 heavy 专属常量，# DRAFT 待 #584）→ idle | 同左 |
| `CombatStateGuard` | 无 | 无（持续姿态；架势回复/扣减归 #577 判定层经 take_stance_damage 驱动） | 不自动退出（guard 释放 → idle 由桥驱动） |
| `CombatStateParrySuccess` | 无 | 帧计数累计 ≥ PARRY_SUCCESS_FRAMES(10) → idle | 同左（#577 若需反击窗口延长，调参面板改常量） |
| `CombatStateStagger` | 无 | 帧计数累计 ≥ STAGGER_FRAMES(12) → idle | 同左 |
| `CombatStateStanceBreak` | 无 | 秒累计 ≥ STANCE_BREAK_RECOVERY_SEC(3.0) → idle | 同左（期间 #580 可经 request_transition("execute") 抢先） |
| `CombatStateExecute` | 无 | 帧计数累计 ≥ FRAME_ANIM_EXECUTE_TOTAL(5) → idle | 同左（执行中无敌，§5 边界 6） |
| `CombatStateRevive` | 无 | 秒累计 ≥ REVIVE_SECONDS(1.0) → idle | 同左（hp_2 初始化/无敌开启在 entity.revive() 完成，§2.4） |
| `CombatStateDead` | 无 | 无（状态机停摆） | 不自动退出（仅 revive() 驱动 dead→revive） |

### 2.4 `gdscripts/combat_entity.gd` — CombatEntity 基类（新增）

- **File:** `shandong-wolf/gdscripts/combat_entity.gd`
- **class_name:** `CombatEntity`（extends Node2D）
- **结构：** 数据容器 + FSM 持有 + 唯一转移入口 + 受击/架势/生死接口 + 信号广播 + 输入桥（内嵌方法组）

**属性（@export 变体参数 + 运行期数据）：**

```gdscript
extends Node2D
class_name CombatEntity

## 变体参数（issue body「差异通过参数配置」；玩家=new(is_player=true, life_total=2)；敌人=new(is_player=false, life_total=1)）
@export var is_player: bool = false
@export var life_total: int = 2        # 玩家 2 / 小兵 1
@export var life_1_max: float = 100.0  # 默认 WolfConstants.LIFE_1_MAX
@export var life_2_abs: float = 50.0   # 默认 WolfConstants.LIFE_2_ABS
@export var stance_max: float = 100.0  # 默认 WolfConstants.POSTURE_BREAK_THRESHOLD

## 运行期数据
var hp_1: float
var hp_2: float                        # life_total=1 时不参与
var stance: float
var facing: int = 1                    # 1 右 / -1 左（AC1 可读写）
var is_stance_broken: bool = false
var state_name: String = "idle"        # canonical 状态名（#574 consume_state 消费）
var _active_life: int = 1              # 两段血标记：1 = hp_1 受击条，2 = hp_2 受击条
var _is_final_dead: bool = false       # 终态（final=true 后禁止 revive）
var _invincible_until_sec: float = 0.0 # 复活无敌期截止（Time.get_ticks_msec()/1000.0 比较）
var fsm: Object                        # StateMachineBase 实例

## 信号（#576 HUD / #574 动画 / #577/#578/#580 下游契约）
signal hp_changed(hp_1: float, hp_2: float, active_life: int)
signal stance_changed(stance: float, stance_max: float)
signal stance_broken(entity: CombatEntity)
signal state_changed(from: String, to: String)
signal died(entity: CombatEntity, final: bool)
signal revived(entity: CombatEntity)
```

**接口方法（签名与 PRD §8.3 逐字一致）：**

| 方法 | 逻辑要点 |
|------|---------|
| `_init()` | 从 WolfConstants 初始化 hp_1=life_1_max、hp_2=life_2_abs、stance=stance_max；创建 fsm = StateMachineBaseScript.new()；预建 11 状态对象字典（懒建亦可，推荐 _init 预建 + `_state_objs[名]` 映射） |
| `_ready()` | 若 is_player：尝试 `root.get_node_or_null("InputController")` 自动接桥（失败静默——headless 测试无 autoload 也能跑）；亦可手动 `bind_input_controller(ic)` |
| `_process(delta)` | `fsm.update(delta)` 转发；无敌期到期自动失效（`_invincible_until_sec` 过期置 0）；桥启用时轮询移动轴 + guard 释放检测（§2.5） |
| `request_transition(to: StringName) -> bool` | **唯一转移入口**。守卫序：① `_is_final_dead` → reject + push_warning；② `state_name == "dead" and to != "revive"` → reject + push_warning（停摆）；③ `CombatStateTable.is_legal(state_name, to)` 查表 → 非法 reject + push_warning（状态不漂移）；④ 同态（to == state_name）：调当前状态对象可选 `restart()`（has_method 检查）后返回 true（attack→attack 连段）；⑤ 合法 → `fsm.transition_to(_state_objs[to])` → 更新 state_name → `emit state_changed(from, to)` → true |
| `take_damage(amount: float, source: Object) -> void` | 防御性兜底：dead/revive/execute 状态或无敌期内 → no-op（0 伤害）；amount clamp 到 ≥0（负/NaN/Inf 视为 0 + push_warning）；扣当前受击条 hp → `emit hp_changed`；hp_1≤0（active_life=1）或 hp_2≤0（active_life=2）→ `die()`；**stagger 转移**：仅当状态 ∈ {idle, move, attack, heavy_attack} 时 `request_transition("stagger")`（guard 中受击保持格挡姿态不硬直——#577 判定层将来裁决扣架势；stance_break 失衡中不重复硬直） |
| `take_stance_damage(amount: float) -> void` | 兜底：dead/revive → no-op；clamp ≥0；stance 扣减 → `emit stance_changed`；stance ≤ 0 → `break_stance()` |
| `break_stance() -> void` | 幂等：`is_stance_broken` 已 true → return（不二次广播）；置 is_stance_broken=true、stance=0（clamp）、`emit stance_broken(self)`、`request_transition("stance_break")`（guard→stance_break 表内合法，§5 边界 5） |
| `die() -> void` | `_active_life==1 and life_total==2` → `emit died(self, false)` + `request_transition("dead")`（#578 接管复活）；否则 → `_is_final_dead=true`、`emit died(self, true)` + `request_transition("dead")`（终态；life_total=1 变体打空 hp_1 直接 final=true，§5 边界 10） |
| `revive() -> void` | 终态误复活守卫：`_is_final_dead or life_total < 2` → no-op + push_warning（§5 失败 3）；否则 `_active_life=2`、hp_2=life_2_abs（**独立计数**，不受 hp_1 残值影响）、stance 清空 + is_stance_broken=false、`_invincible_until_sec = now + INVINCIBLE_SECONDS`、`request_transition("revive")`、`emit revived(self)`（#578 自动路径：监听 died(final=false) 起 1s 计时后调 revive()；F 键路径：桥接 revive_pressed → revive()，两路兼容） |
| `_recalc_stance_max() -> float` | 钩子：MVP 返回 `stance_max`（固定值）；未来派生规则（只狼铁律「架势上限=当前 HP 上限」）改内部实现即可，信号契约不动（PRD 实验 3 内化） |
| `bind_input_controller(ic: Node) -> void` | 手动接线（#585 组装或测试）；保存引用 + 订阅信号（§2.5） |

### 2.5 `_StateInputBridge` — 输入→状态映射（CombatEntity 内嵌方法组）

- **归属：** combat_entity.gd 内部（PRD §4.4 方案 A：实体内嵌，状态契约权威在本层）
- **启用条件：** 仅 `is_player == true`（enemy 变体无玩家输入，AI 驱动归 #581）
- **接线方式：** `_ready()` 自动尝试获取 InputController autoload + `bind_input_controller()` 手动兜底；headless 测试可手动 `emit` 信号或直接调 request_transition（桥非必经）

| 输入源 | 映射 | 说明 |
|--------|------|------|
| `attack_pressed` | `request_transition("attack")` | idle/move/guard 可入；attack 中再按 = 连段（restart 钩子） |
| `heavy_attack_pressed` | `request_transition("heavy_attack")` | idle/move/guard 可入 |
| `guard_pressed(timestamp_ms)` | `request_transition("guard")` | 时间戳本层不消费（弹反判定归 #577） |
| `guard_held`（_process 轮询 `Input.is_action_pressed("game_guard")`） | 释放检测：state==guard 且未按住 → `request_transition("idle")` | 按住期间状态机天然保持 guard 姿态 |
| `revive_pressed` | `revive()` | #578 F 键驱动路径（自动路径由 #578 监听 died 计时） |
| `get_move_axis()`（_process 轮询） | axis≠0 且 state ∈ {idle,move} → `request_transition("move")`；axis==0 且 state==move → `request_transition("idle")`；同时 `facing = sign(axis)` | **move/idle 驱动方（PRD §4.4 未定义，本设计补全，§1.2）**；垫步/跳**不映射**（留在移动层，canonical 集无对应状态） |

> 桥的移动轴轮询与 PlayerController 位移读取同一 `get_move_axis()`，二者无写冲突（PlayerController 只动 velocity，桥只动状态名与 facing）。

---

## 3. 既有组件修改

### 3.1 新文件

| 文件 | 内容 | 规模预估 |
|------|------|:-------:|
| `shandong-wolf/gdscripts/combat_entity.gd` | CombatEntity（Node2D）+ 输入桥 + 信号契约 | ~260 行 |
| `shandong-wolf/gdscripts/combat_state_table.gd` | CANONICAL_STATES + TRANSITIONS + is_legal | ~60 行 |
| `shandong-wolf/gdscripts/combat_states.gd` | CombatStateBase + 11 状态对象 + make_state | ~250 行 |
| `shandong-wolf/tests/test_combat_entity.gd` | 三主路径 + 121 对遍历 + 变体 + 边界（§8） | ~450 行 |

### 3.2 修改文件

| 文件 | 变更 | 原因 |
|------|------|------|
| `shandong-wolf/gdscripts/constants.gd` | 追加「战斗时序」# DRAFT 分区 5 常量（§2.1 表） | 定时状态自动退出 + 无敌期需要时序常量；只读，定稿归 #584 |
| `shandong-wolf/tests/run_tests.gd` | `_run_tests()` 内追加一行：`_run("res://tests/test_combat_entity.gd", "CombatEntity")` | 挂载新套件（#572 模式） |
| `shandong-wolf/tests/smoke_test.gd`（**可选**） | 追加实体实例化探针：headless new 玩家/敌人两变体 + 读属性断言 | 冒烟层 AC1 覆盖（不强制；若加，须保持现有 I1/I2 不回归） |

### 3.3 移除/弃用文件

无（零删除）。

### 3.4 受影响的测试文件

| 测试文件 | 变更性质 |
|---------|---------|
| `shandong-wolf/tests/test_combat_entity.gd` | **新增**（§8 全部用例） |
| `shandong-wolf/tests/run_tests.gd` | 追加一行挂载（§3.2） |
| `shandong-wolf/tests/test_stick_figure_animation.gd` | **不改**；implement 后手动跑一遍确认 11 态状态名与 ANIM_CLIP_NAMES 键集逐名匹配（契约对齐验证，§8 场景 F） |
| `shandong-wolf/tests/test_state_machine.gd` / 其余 5 套件 | 不改（防回归跑全量即可） |

---

## 4. 数据流

### Flow 1：输入 → 状态转移（正常路径）

```
InputController.attack_pressed
  → _StateInputBridge → entity.request_transition("attack")
      → 守卫① 非终态 ✓ → 守卫② 非 dead ✓ → CombatStateTable.is_legal("idle","attack") = true ✓
      → fsm.transition_to(CombatStateAttack)  [同态守卫/防重入锁]
      → state_name="attack" → emit state_changed("idle","attack")
          → #574 consume_state("attack") 播 anim_attack
          → AttackState.update(): 帧计数 8(前摇)→4(暴发)→10(收招) → 22 帧后 request_transition("idle")
```

### Flow 2：受击 → stagger（#577 判定层调用）

```
#577: entity.take_damage(12, attacker)
  → 兜底检查（非 dead/revive/execute、非无敌期）✓
  → hp_1 = 100-12 = 88 → emit hp_changed(88, 50, 1) → #576 HUD 血条
  → 状态 ∈ {idle,move,attack,heavy_attack} → request_transition("stagger")（表内合法）
  → StaggerState.update(): 12 帧（STAGGER_FRAMES）后 → request_transition("idle")
```

### Flow 3：架势崩解 → stance_break → 处决通道（AC3 + #580）

```
#577: entity.take_stance_damage(10) × N
  → stance 逐次扣减 → emit stance_changed(stance, stance_max) → #576 HUD 架势条
  → stance ≤ 0 → break_stance()
      → is_stance_broken 幂等检查（单次触发）
      → stance=0（clamp）→ emit stance_broken(self) → #577/#580 消费
      → request_transition("stance_break")（guard 中同样表内合法，边界 5）
  → StanceBreakState 3.0s（STANCE_BREAK_RECOVERY_SEC）恢复
      → #580 处决驱动：request_transition("execute") → ExecuteState 5 帧 → idle
      → 或自然恢复 → idle
```

### Flow 4：两段血死亡 → 复活（AC4 + #578）

```
打空 hp_1（active_life=1, life_total=2）→ die()
  → emit died(self, false) → #578 监听（自动路径：1s 后调 revive()；F 键路径：桥接 revive_pressed）
  → request_transition("dead") → 状态机停摆（除 revive 外全部 reject）
  → #578: entity.revive()
      → 终态守卫 ✓ → _active_life=2, hp_2=50（独立计数）, stance 清空, 无敌 1s
      → request_transition("revive") → emit revived(self)
      → ReviveState 1.0s（REVIVE_SECONDS）→ idle
  → 再打空 hp_2（active_life=2）→ die() → emit died(self, true) + _is_final_dead=true → 终态（SW-015 失败判定）
  → 终态后 revive() → no-op + push_warning（失败路径 3）
```

### Flow 5：非法转移拒绝（AC2 红线）

```
任何调用方：entity.request_transition("attack")（当前 state_name="stance_break"）
  → CombatStateTable.is_legal("stance_break","attack") = false
  → push_warning + 返回 false + 状态不漂移（state_name 仍 "stance_break"）
  → 单测断言：转移被拒 + 状态未变 + warning 触发
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | dead 状态受击 | take_damage/take_stance_damage 在 dead/revive 状态 → no-op（0 伤害不扣血不扣架势；#577 判定层不该调，防御性兜底） |
| 2 | 复活无敌期内受击 | revive() 设 `_invincible_until_sec = now + INVINCIBLE_SECONDS`；期内 take_damage → 0 伤害；`_process` 到期自动失效 |
| 3 | 架势溢出单次触发 | stance=5 时 take_stance_damage(10) → clamp 至 0 + `is_stance_broken` 幂等标志 → 恰好一次 break_stance + 恰好一次 stance_broken（不因溢出二次广播） |
| 4 | 同态转移 | request_transition(当前状态)（非 attack）→ StateMachineBase 同态守卫静默忽略（无回调无警告） |
| 5 | guard 中架势崩解 | guard → stance_break 在 TRANSITIONS 表内显式允许（格挡中崩解 = 失衡，优先级高于格挡姿态） |
| 6 | parry_success/execute 中受击 | parry_success 免伤归 #577 裁决（本层提供状态位）；execute 中 take_damage no-op（转移表禁止 execute 中受击转移）；execute 状态表出边仅 [idle] |
| 7 | facing 翻转 | 桥轮询移动轴时 `facing = sign(axis)`；攻击中翻转由 #574 刀光/挥砍消费时机决定（本层只保证 facing 正确读写，AC1 覆盖） |
| 8 | 两段血边界 | hp_1 归零瞬间连击第二段 → 实体已 dead，take_damage no-op，不重复 die（状态兜底先于扣血） |
| 9 | hp/stance clamp | hp_1/hp_2 ∈ [0, max]、stance ∈ [0, stance_max]；负伤害/NaN/Inf → 视为 0 + push_warning（失败路径 4） |
| 10 | life_total=1 变体 | 敌人无第二条血：hp_1 归零 → die() 直接 died(final=true)（不经可复活 dead；复活语义仅玩家，#578 只挂玩家） |
| 11 | 终态误复活 | `_is_final_dead` 或 life_total<2 时 revive() → no-op + push_warning（#578 驱动方必须只监听 died(final=false)） |
| 12 | 状态机重入 | enter() 内嵌套 request_transition → StateMachineBase 防重入锁拦截；战斗层约定：状态 enter 内**禁止**发起转移，一律延迟到 update（定时状态帧计数自然退出） |
| 13 | 连段条件合法性 | attack 中再按攻击：前摇/暴发 phase（0/1）restart() 忽略（防无脑连打）；收招 phase（2）restart() 重置回前摇 = 连段成立 |
| 14 | 输入桥缺失 | 非玩家变体不接桥（AI 归 #581）；玩家变体 autoload 不可得（headless）→ 静默跳过，测试直接调 request_transition / 手动 emit 信号 |

---

## 6. 集成点

> **状态约定：** ⬜ = 待 implement 接线；✅ = 已连接（implement agent 完成后更新；review agent 验证）。

| 集成 | 本组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 状态名消费 | `CombatEntity.state_name` / `state_changed` | #574 | 组装层（#585）wire `state_changed(from,to) → StickFigureController.consume_state(to)`；本层状态名与 ANIM_CLIP_NAMES 键集逐字对齐（implement 后跑 #574 单测验证） | ⬜ 待 #585 |
| HUD 血条/架势条 | `hp_changed(hp_1,hp_2,active_life)` / `stance_changed(stance,stance_max)` | #576 | 信号订阅 | ⬜ 待 #576 |
| 判定入口 | `take_damage(amount, source)` / `take_stance_damage(amount)` / `stance_broken` / `parry_success` 状态 | #577 | 接口调用 + 信号 | ⬜ 待 #577 |
| 复活驱动 | `died(final=false)` / `revive()` / `revive` 状态 / `revived` | #578 | 接口调用（自动 1s 或 F 键两路兼容） | ⬜ 待 #578 |
| 处决驱动 | `stance_break→execute` 转移通道 / `stance_broken` | #580 | 接口调用（request_transition("execute")） | ⬜ 待 #580 |
| 敌 AI 实体 | enemy 变体参数（life_total=1 等） | #581 | 实例化参数 | ⬜ 待 #581 |
| 场景组装 | `CombatEntity` + `PlayerController` + `StickFigureController` | #585 | 实例化 + 信号桥接（state_changed→consume_state；PlayerController 位移→move 状态可经输入桥轴轮询自动覆盖） | ⬜ 待 #585 |

> 本 issue 交付可独立实例化/单测的类；所有场景内集成由 #583/#585 完成（PRD §1.4 范围边界）。

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 依赖 | 预估 |
|:----:|:------:|------|------|:----:|
| Phase 1 | P0 | constants.gd 追加「战斗时序」5 常量（§2.1） | 无 | 0.5h |
| Phase 2 | P0 | combat_state_table.gd（§2.2） | Phase 1（无硬依赖，常量不参与表） | 1h |
| Phase 3 | P0 | combat_states.gd：CombatStateBase + 11 状态对象 + make_state（§2.3） | Phase 1 | 3h |
| Phase 4 | P0 | combat_entity.gd：数据/信号/request_transition/take_damage/take_stance_damage/break_stance/die/revive（§2.4） | Phase 2 + 3 | 4h |
| Phase 5 | P1 | _StateInputBridge（§2.5） | Phase 4 | 1.5h |
| Phase 6 | P0 | test_combat_entity.gd 全量用例（§8）+ run_tests.gd 挂载 + 全量回归 | Phase 2-5 | 4h |
| Phase 7 | P1 | 契约对齐验证：#574 动画单测/冒烟确认 11 态逐名匹配；#573 输入单测确认桥接无回归 | Phase 6 | 0.5h |

> Phase 2-5 可并行开发（表/状态对象/实体/桥文件独立，接口按 §2 契约互锁）。

---

## 8. 测试用例描述

> **测试文件：** `shandong-wolf/tests/test_combat_entity.gd`（挂载 run_tests.gd；测试写法沿用 test_state_machine.gd 模式：extends Object + passed/failed + `_assert`；Node2D 实体测试 add 到 `root` 以便 _process/_ready 生效，纯数据断言可免树直接 new）。**只写描述，不写可运行测试代码（implement agent 职责）。**

### Scenario A：变体实例化与属性读写（AC1）
- Test 1 玩家变体初始化：`CombatEntity.new()` 设 is_player=true, life_total=2 → 断言 hp_1=100、hp_2=50、stance=100、facing=1、state_name="idle"、is_stance_broken=false
- Test 2 敌人变体初始化：is_player=false, life_total=1, life_1_max=40, stance_max=50 → 断言 hp_1=40、stance=50；hp_2 不参与
- Test 3 属性读写：直接赋值 hp_1/hp_2/stance/facing 后读回一致（AC1「正确读写」）
- Test 4 两变体同代码路径：同一类实例化，参数不同行为不同（死亡语义差异见 Scenario E）

### Scenario B：状态流转合法性（AC2 + PRD 实验 1）
- Test 5 转移表 121 对遍历：11×11 全部 (from,to)，`is_legal()` 结果与 §2.2 TRANSITIONS 期望表 100% 一致（表内全 true、表外全 false）
- Test 6 红线案例：state_name="stance_break" 时 request_transition("attack"/"heavy_attack"/"guard") 全部返回 false + push_warning + 状态不漂移
- Test 7 停摆：state_name="dead" 时除 "revive" 外全部转移 reject
- Test 8 合法转移执行：idle→attack→idle→move 等表内转移实际切换 state_name 且发出 state_changed(from,to)
- Test 9 同态忽略：idle 时 request_transition("idle") → 静默忽略（无 state_changed 无 warning）
- Test 10 连段钩子：attack 收招 phase 时 request_transition("attack") → restart 重置帧计数；前摇 phase 时 → 忽略

### Scenario C：受击主路径（AC5-1）
- Test 11 受击掉血：take_damage(12) → hp_1=88 + hp_changed 信号（参数 88,50,1）+ 进入 stagger
- Test 12 stagger 自动退出：stagger 12 帧（手动推进 fsm.update 或 await process_frame）→ 回 idle
- Test 13 guard 中受击：state=guard 时 take_damage → 扣血但不进入 stagger（保持格挡姿态）
- Test 14 无敌期受击：revive 后 1s 内 take_damage(999) → hp 不变（0 伤害）
- Test 15 负伤害 clamp：take_damage(-5) → 视为 0 + warning，hp 不变

### Scenario D：架势主路径（AC3 + AC5-2）
- Test 16 架势扣减：take_stance_damage(30) × 3 → stance=10 + 3 次 stance_changed
- Test 17 崩解广播：stance=5 时 take_stance_damage(10) → 恰好一次 break_stance + 恰好一次 stance_broken + 进入 stance_break
- Test 18 幂等：崩解后再 take_stance_damage → 不二次广播 stance_broken
- Test 19 guard 中崩解：state=guard 时架势归零 → guard→stance_break 转移成功（边界 5）
- Test 20 崩解恢复：stance_break 3.0s 后自动回 idle（期间 request_transition("execute") 可抢先）

### Scenario E：死亡主路径（AC4 + AC5-3）
- Test 21 第一条命耗尽：take_damage(100) → state=dead + died(final=false) + 状态机停摆
- Test 22 复活流：revive() → state=revive → 1s 后 idle；hp_2=50 独立计数、stance 清空、无敌开启（INVINCIBLE_SECONDS 内 take_damage 无效）
- Test 23 第二条命耗尽：复活后再打空 hp_2 → died(final=true) + _is_final_dead + 终态
- Test 24 life_total=1 终态：敌人打空 hp_1 → 直接 died(final=true)（不经可复活 dead）
- Test 25 终态误复活：final=true 后 revive() → no-op + push_warning
- Test 26 状态序列断言：`idle→dead→revive→idle→dead` 精确复现（PRD 实验 2）

### Scenario F：边界/契约对齐
- Test 27 dead 中受击 no-op：take_damage/take_stance_damage 在 dead → 0 伤害 0 架势
- Test 28 双状态机契约对齐：#574 ANIM_CLIP_NAMES 键集 == combat_state_table CANONICAL_STATES（逐名相等，11/11）——防状态名漂移红线
- Test 29 输入桥 mock：手动 emit InputController 信号（attack_pressed/heavy_attack_pressed/guard_pressed/revive_pressed）→ 对应转移发生；guard 释放（模拟松开）→ 回 idle；轴轮询（模拟 axis≠0/0）→ move/idle + facing 同步
- Test 30 全量回归：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 7 套件全绿（含既有 6 套件防回归）

---

## 9. 验收条件映射（源自 Issue #575 body）

| # | 验收条件 | 本设计保障 | 覆盖用例 |
|---|---------|-----------|:-------:|
| AC1 | CombatEntity 可实例化玩家与敌人两种变体，hp/stance 属性正确读写 | §2.4 单类 + @export 参数（is_player/life_total/life_1_max/life_2_abs/stance_max） | T1-T4 |
| AC2 | 状态机可驱动状态流转，且状态切换必须经合法性检查（如 stance_break 时不可攻击） | §2.2 集中转移表 + §2.4 request_transition 唯一入口（查表 reject + 状态不漂移） | T5-T10 |
| AC3 | take_stance_damage 在 stance≤0 时触发 break_stance() 并广播信号 | §2.4 break_stance 幂等 + stance_broken 信号（单次触发） | T16-T19 |
| AC4 | 两段血：第一条血归零进入 dead 状态（由 SW-007 接管复活），第二条半管血独立计数 | §2.4 _active_life 双条独立计数 + die()/revive() + died(final) 信号 | T21-T26 |
| AC5 | 单元测试覆盖：受击/架势/死亡 3 条主路径 | §8 Scenario C/D/E | T11-T26 |

---

## 10. 明确不修改（与 PRD §8.5 红线对齐）

- ❌ 不造 canonical 集合外的状态名（禁止 parry 单列 / run 代替 move）
- ❌ 不引入第三方 addon（#572 裁决；PRD §6.2 调研结论：无成熟可复用战斗实体模板）
- ❌ 不修改 `mini-pong/` 任何文件（游戏隔离红线）
- ❌ 不修改 `scenes/Main.tscn`（标题场景红线）
- ❌ 不裁决 # DRAFT 数值（只读 constants；新常量也标 # DRAFT）
- ❌ 不做判定/演出逻辑（#577/#578/#580 职责：弹反窗口、复活演出、处决演出）
- ❌ 不写实现代码/测试代码（本 phase 仅 DESIGN + TASKS 文档）
- ❌ 不修改 state_machine.gd / input_controller.gd / stick_figure_*.gd / player_controller.gd（零改动消费）

## 附：开源调研结论（PRD §6.2 已调研，implement PR 须附说明）

PRD §6.2 结论直接引用：FSM 层复用 #572 自研 StateMachineBase（40 行满足，不引入 addon）；战斗实体层 GitHub 检索（mecha-party-fighters/parry-shmup 等 0-2⭐ 个人习作）无 hp+stance+两段命数据模型先例 → **自研 CombatEntity**（issue body 允许「找不到再自行实现」）。implement PR 须引用本调研结论，无需重复调研。

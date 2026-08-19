# Design: [Feature] 基础日本兵 AI（巡逻 / 追击 / 攻击 / 被弹反）

> **Parent Issue:** #581
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4 **方案 A 确认采纳** —— EnemyAI 独立行为状态机（Patrol/Chase/Attack/Retreat，按 combat_states.gd 范式派生）+ 判定层自动窗口复用（仅补 3 处 additive 参数化：AttackWindow.windup_frames / CombatEntity 攻击伤害 @export / CombatJudge 登记取值）；否决方案 B（扩 11 态转移表——违反 #575 状态名权威集红线）与方案 C（Behaviour Tree 开源库——与 issue body「使用通用状态机扩展」冲突 + MVP 过度设计）
> **Reference PRD:** `docs/PRD/581-enemy-ai.md`（research PR #632 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/575-combat-entity-state-machine.md`（CombatEntity 变体参数 + request_transition 唯一转移入口 + 6 信号 + combat_states.gd 状态对象范式）；`docs/DESIGN/577-parry-clash-stance-break.md`（AttackWindow 窗口契约 + CombatJudge 自动登记 + 五结果事件 + 25 用例测试范式）；`docs/DESIGN/584-combat-tuning-draft.md`（WolfConstants # DRAFT 只读 + DebugCanvas 调参面板 + ENEMY_ATTACK_WINDUP 候选 [12,15,18]）；`docs/DESIGN/573-input-map-player-controller.md`（CharacterBody2D 加速度移动模型）
> **所有权:** `content_ownership: mechanical`（AI 行为/感知/决策 = 机械工程：状态流转 + 几何判据 + 概率决策；手感数值全量 # DRAFT **只读不裁决**，新增 AI 分区常量同样标 # DRAFT 候选集，定稿归 #584；ENEMY_ATTACK_WINDUP 15→12 为 PRD §8.4-1 已裁决的 AC 对齐改动，偏差记录交 #584）
> **深度:** standard（GitHub 无 depth 标签；PRD 标注 depth: standard）—— 9 文件 / 4 子系统（常量、判定参数化、AI 行为层、测试）× 6+ 独立子任务 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，参照 #584/#577 先例）
> **并行上下文:** worktree 并行 —— constants.gd 为**追加式新增「AI 分区」常量**（不触碰既有 9 分区任何常量行，与 #584 调参面板无同区改写冲突）；新文件全部独立命名（`enemy_ai.gd` / `enemy_ai_states.gd` / `test_enemy_ai.gd`）；唯一共享文件 = `tests/run_tests.gd`（追加一行 `_run()`；#579/#580/#583/#585 均未开始，无并发改写）

---

## 1. 架构总览

**问题本质是「战斗层原料全部就绪，『谁驱动敌人』零存在」。** shandong-wolf 经 #575/#577/#584 已具备敌人「能被打、能被弹反、能崩解」的**承受面**：CombatEntity 敌人变体（is_player=false / life_total=1，#575 注释明言「敌AI 用 enemy 变体」）、CombatJudge 对任意实体进入 attack/heavy_attack 态**自动登记 AttackWindow**（#577 注释明言「敌人 MVP 由 #581 登记窗口」）、11 态战斗状态机（idle/move → attack/heavy_attack 表内转移合法、parry_success → idle 表内）、WolfConstants 只狼基准常量（PARRY_STANCE_DAMAGE=25 / POSTURE_HIT_COST=35 / ENEMY_ATTACK_WINDUP=15）。但 `gdscripts/` 无任何 AI 层：无行为状态机（巡逻→追击→攻击→回避）、无感知（120° 视线 6m）、无敌人移动实体、无攻击决策。**本 issue 交付 = 敌人行为驱动面，是 #585 组装（战斗闭环）的最后一个行为组件。**

**设计哲学：行为层与战斗层解耦、决策门控 = 硬约束、感知 = 几何判据、判定 = 复用自动窗口、数值 = 全走 constants。**

1. **行为层与战斗层解耦**：EnemyAI 是独立 Node（CharacterBody2D 移动实体），持有**第二个** StateMachineBase 实例（AI 行为状态：patrol/chase/attack/retreat）；战斗状态（11 态）与判定（#577）原样复用。单向依赖：AI 决策 → `entity.request_transition("attack"/"heavy_attack")` + 位移意图；战斗结果 → 经 state_changed / stance_broken / parry_success 信号**反向门控** AI 决策。两层可 headless 单测。
2. **决策门控 = 硬约束**：AI 只在实体处于 `idle`/`move` 态时做决策（战斗动画/硬直期间由 combat FSM 接管，AI 不抢戏）；弹反命中后 AI 进入 `ENEMY_PARRY_STUN_SECONDS`（0.5s）抑制窗——共享 parry_success 态仅 10 帧（≈0.167s），0.5s 硬直由 **AI 层补足**（AC2 的实现位置裁决点，见 §9 风险 2）。杜绝「硬直中敌人还在追击」的穿帮。
3. **感知 = 几何判据，不是物理**：120° 视线锥用 facing 方向点积（半角 60° → cos60°=0.5）+ 水平距离 + 高度容忍判定，无 raycast / 无 Area2D——与 #577「零碰撞体」架构一致（#574 sword_arc 注释「碰撞判定归 #577」）。
4. **判定 = 复用自动窗口**：#577 `_on_entity_state_changed` 已对任意实体进入 attack 态自动登记窗口——AI 无需手动登记，只需 3 处 additive 参数化：AttackWindow.windup_frames（敌人前摇 12 帧）、CombatEntity.attack_hp_damage / attack_stance_damage（敌人伤害）、CombatJudge 登记时读实体参数（≥0 用实体值，否则玩家常量兜底）。
5. **数值 = 全走 constants**：感知范围/角度/速度/冷却/伤害/概率/抑制窗全部新增 AI 分区 # DRAFT 常量，AI 代码零字面量。

```
                    ★ Issue #581 本设计（shandong-wolf 敌人行为层）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 新建（3 文件，全部 shandong-wolf/ 下）                                          │
│  gdscripts/enemy_ai.gd        EnemyAI（CharacterBody2D，class_name）           │
│                               —— 行为 FSM 持有 + 感知 + 决策门控 + 位移          │
│  gdscripts/enemy_ai_states.gd PatrolState/ChaseState/AttackState/RetreatState  │
│                               —— 按 combat_states.gd 范式派生（enter/exit/update）│
│  tests/test_enemy_ai.gd       AC1-AC5 主路径 + 感知边界 + 回避统计 + 回归        │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（4 文件，全部 additive，不动任何既有接口/事件/裁决顺序）                     │
│  gdscripts/constants.gd             追加「AI 分区」# DRAFT 常量（§3.1）          │
│  gdscripts/combat_attack_window.gd  追加 windup_frames: int = -1（-1→回退）     │
│  gdscripts/combat_entity.gd         追加 attack_hp_damage / attack_stance_damage│
│  gdscripts/combat_judge.gd          自动登记改读实体参数 + 敌人 windup           │
│  tests/run_tests.gd                 追加 _run(test_enemy_ai)                   │
│  tests/smoke_test.gd（可选）         AC5 冒烟：玩家站桩 5s 内敌人攻击路径         │
├──────────────────────────────────────────────────────────────────────────────┤
│ 消费方（0 改动，后续 issue 挂接）                                               │
│  #579 反馈 → 订阅 judge 五结果事件（hit_landed/parry_success/clash…）           │
│  #580 处决 → stance_broken 事件 + entity 引用（3s 窗口）                        │
│  #583 场景 → EnemyAI.waypoints @export（出生点 + 巡逻路径坐标）                 │
│  #585 组装 → EnemyAI + CombatEntity(is_player=false) + StickFigureController   │
│  #586 E2E   → e2e_shots.json 剧本（敌人巡逻/攻击截图裁决）                       │
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    ▼
        #573 PlayerController（移动模型范本，不改）
        #575 CombatEntity  ──► request_transition / take_stance_damage / 6 信号
        #577 CombatJudge   ──► 自动登记窗口 / 弹反→拼刀→格挡→受击 / 五结果事件
                                    │
                                    ▼
                        EnemyAI（行为 FSM）
                         ├─ PatrolState: waypoint ping-pong（到达停顿）
                         ├─ ChaseState: 转向（facing）+ 逼近 + 停距 + 丢失回巡逻
                         ├─ AttackState: 三连砍（attack 连段 restart）或突刺（heavy_attack）+ 冷却
                         ├─ RetreatState: 5% 后退回避（玩家攻击前摇触发，seed 可注入）
                         └─ 决策门控: 实体非 idle/move 不决策 + 弹反抑制窗 0.5s
                                    │
                                    ▼
                    entity.request_transition("attack") ──► CombatJudge 自动登记
                    （windup=ENEMY_ATTACK_WINDUP、伤害=实体参数）──► #579/#580
```

**与 PRD 方案裁决的一致性：** PRD §4.1 推荐方案 A（EnemyAI 独立行为状态机 + 判定层自动窗口复用），本设计逐项确认采纳，无分歧。PRD §7 三个 Spike（感知几何精度 / 5% 回避可测性 / windup 参数化弹反时序）的**预期结论已直接内化为本设计决策**：①感知闭区间含端点 + 「> 阈值则 false」单向容差；②RNG seed 注入 + 逐事件独立采样；③windup_frames -1 回退兼容既有玩家窗口。若 Spike 实测推翻任一内化结论，implement 需在 PR 中说明偏离及理由。

### 1.1 既有实现状态（Prior Implementation Status，plan agent 已逐条核实 origin/main ff61192）

| 文件 | 当前状态（2026-08-20 侦查） | 与 #581 的差距 |
|------|---------------------------|---------------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ `CombatEntity`（#575/#618 交付）：is_player/life_total/life_1_max/life_2_abs/stance_max @export 变体参数 + request_transition 唯一转移入口 + take_damage/take_stance_damage/break_stance/die/revive + 6 信号（hp_changed/stance_changed/stance_broken/state_changed/died/revived） | **两处 additive**：敌人攻击伤害 @export（§3.1）——PRD 断言「敌人变体携带自身攻击伤害」当前不存在 |
| `shandong-wolf/gdscripts/combat_state_table.gd` | ✅ 11 态 CANONICAL_STATES 权威集；idle/move → attack/heavy_attack 表内；attack → attack 连段表内；parry_success → idle 表内 | 零改动消费：AI 只调 request_transition，不新增状态名 |
| `shandong-wolf/gdscripts/combat_states.gd` | ✅ 状态对象范式（StateMachineBase 三接口 + restart 连段钩子）；CombatStateAttack 三段 phase + WINDUP+RECOVERY 帧自动退 idle；parry_success 10 帧自动退 idle | 零改动：敌人复用同一套战斗状态，AI 不复制状态逻辑（敌人 attack 态时长沿用玩家 WINDUP+RECOVERY=22 帧，命中窗 12+4 帧在态内闭合，不冲突） |
| `shandong-wolf/gdscripts/combat_judge.gd` | ✅ `CombatJudge`（#577/#626 交付）：`_on_entity_state_changed` 对**任意实体** attack/heavy_attack 自动登记 AttackWindow（hp_damage=SWORD_DAMAGE_LIGHT/HEAVY、stance_damage=POSTURE_HIT_COST、direction=entity.facing）+ 弹反→拼刀→格挡→受击裁决 + 五结果事件 + 幂等防重入 | **一处 additive**：登记时 hp_damage/stance_damage 改读实体参数（§3.1）——PRD 断言「敌人伤害可配置」当前登记值写死玩家常量 |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | ✅ `AttackWindow`（RefCounted，#577/#626 交付）：`hit_frame() = start_frame + int(C.FRAME_ATTACK_WINDUP)`（**硬编码玩家 8 帧前摇**）；is_active/is_expired 闭区间 | **一处 additive**：追加 `windup_frames: int = -1`（-1 → 回退 FRAME_ATTACK_WINDUP；敌人窗口 = ENEMY_ATTACK_WINDUP）——PRD 断言「敌人前摇 12/15 帧时命中帧会错位」属实 |
| `shandong-wolf/gdscripts/constants.gd` | ✅ `WolfConstants` 全量 # DRAFT：ENEMY_ATTACK_WINDUP=15（候选 [12,15,18]，DebugCanvas 同步登记）/ PARRY_STANCE_DAMAGE=25 / POSTURE_HIT_COST=35 / HITBOX_RANGE=80 / HITBOX_ACTIVE_FRAMES=4 / MOVE_MAX_SPEED=300 / MOVE_ACCELERATION=1200 / STAGGER_FRAMES=12 / PARRY_SUCCESS_FRAMES=10 / STANCE_BREAK_RECOVERY_SEC=3.0 | **❌ 缺 AI 分区常量**（感知范围/角度/速度/冷却/伤害/概率/抑制窗）——追加式新增（§3.1） |
| `shandong-wolf/gdscripts/player_controller.gd` | ✅ CharacterBody2D 加速度移动模型（velocity.x = move_toward(...) + move_and_slide，velocity.y=0） | 零改动：EnemyAI 位移仿此模型（§2.1） |
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ `StateMachineBase`（#572）：三接口 enter/exit/update + transition_to（同态守卫 + 防重入锁） | 零改动：EnemyAI 内部持有第二个 StateMachineBase 实例 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | ✅ consume_state 消费 11 态（#574） | 零改动：AI 零渲染，patrol/chase 走 move/idle 动画，攻击/硬直由战斗态驱动 |
| `shandong-wolf/tests/run_tests.gd` | ✅ 9 套件注册（含 CombatJudge 25 用例） | 追加一行 `_run("res://tests/test_enemy_ai.gd", "EnemyAI")` |
| `shandong-wolf/tests/test_combat_judge.gd` | ✅ 25 用例（弹反/拼刀/格挡/受击/崩解/防重入全绿基线） | 零改动（additive 补丁必须保其全绿） |
| `shandong-wolf/gdscripts/` | ❌ 无 AI 层 | 本 issue 全部新建 |

**核心缺口确认（PRD 断言 vs 实际代码库交叉核对）：** 三处 PRD 断言与现状的差距全部核实属实——①CombatEntity 无 `attack_hp_damage/attack_stance_damage`；②AttackWindow.hit_frame() 硬编码玩家 FRAME_ATTACK_WINDUP；③CombatJudge 自动登记 hp_damage 写死玩家刀伤害常量。均以 additive 参数化解决（§3.1），不修改任何既有接口签名/事件名/裁决顺序。


---

## 2. 新组件详细设计

### 2.1 EnemyAI（`shandong-wolf/gdscripts/enemy_ai.gd`，新增）

- **文件:** `shandong-wolf/gdscripts/enemy_ai.gd`
- **类:** `class_name EnemyAI`，`extends CharacterBody2D`（移动实体，仿 #573 PlayerController 移动模型）
- **职责:** 行为 FSM 持有 + 感知（120° 视线 6m）+ 决策门控 + 位移执行。**`decide(delta)` 纯决策方法（无物理依赖，headless 测试手动驱动）与 `_physics_process`（move_and_slide）分离**——这是可测性核心。
- **Node 结构（#585 组装时，本 issue 不组装场景）:**
  ```
  EnemyAI (CharacterBody2D)          ← 本类
  ├── CombatEntity (is_player=false, life_total=1, life_1_max=ENEMY_HP_MAX,
  │                 stance_max=POSTURE_BREAK_THRESHOLD, 本地坐标 (0,0))
  └── StickFigureController          ← 复用 SW-003 骨架（consume_state 驱动，零新渲染）
  ```
- **@export 参数:**
  ```gdscript
  @export var waypoints: Array[Vector2] = []   # 巡逻路径（#583 场景配置；空数组=原地等待，不报错）
  @export var player: Node2D                   # 玩家移动实体引用（感知/追击目标）
  @export var judge: Object                    # CombatJudge 引用（null = 不登记窗口，仅行为路径可测）
  @export var rng_seed: int = -1               # -1 = 全局 RNG；≥0 = 确定性（测试注入，CI 稳定）
  ```
- **运行期属性:**
  ```gdscript
  var entity: CombatEntity = null              # bind_entity() 注入（#585 组装调用）
  var _ai_fsm: Object                          # 第二个 StateMachineBase 实例（行为 FSM）
  var _move_intent: Vector2 = Vector2.ZERO     # decide() 写、_physics_process 读
  var _parry_stun_until_sec: float = 0.0       # 弹反抑制窗截止（AC2 硬直补足）
  var _attack_cooldown_until_sec: float = 0.0  # 攻击冷却（ENEMY_ATTACK_COOLDOWN_SEC）
  var _rng: RandomNumberGenerator              # seed 注入的确定性 RNG
  var _dead: bool = false                      # 实体终态后 AI 完全禁用
  ```
- **信号:** 无新增信号（AI 是纯消费者；结果事件全部走 #577 判定器，避免信号面膨胀）
- **关键方法（pseudocode）:**
  ```gdscript
  func bind_entity(e: CombatEntity) -> void:
      ## #585 组装时调用；绑定后注入敌人攻击伤害参数（judge 登记读取）+ 订阅信号
      entity = e
      if e != null:
          e.attack_hp_damage = C.ENEMY_HP_DAMAGE        # 实体参数注入（§3.1）
          e.attack_stance_damage = C.POSTURE_HIT_COST
          e.state_changed.connect(_on_entity_state_changed)   # 硬直/崩解/死亡门控
          e.died.connect(_on_entity_died)

  func _ready() -> void:
      ## 行为 FSM 初始化（PatrolState 起步）+ RNG seed 注入（rng_seed >= 0 时）
      _ai_fsm = StateMachineBaseScript.new()
      _ai_fsm.transition_to(EnemyAIStatesScript.make_state("patrol", self))
      _rng = RandomNumberGenerator.new()
      if rng_seed >= 0: _rng.seed = rng_seed
      if player != null:
          player.state_changed.connect(_on_player_state_changed)  # 5% 回避触发源（AC3）

  func can_sense_player() -> bool:
      ## 120° 视线 6m 几何判据（无 raycast / 无 Area2D）：
      ##   ① 高度容忍: absf(player.y - position.y) > ENEMY_SENSE_HEIGHT_TOLERANCE → false
      ##   ② 水平距离: dx = player.x - position.x；absf(dx) > ENEMY_SENSE_RANGE_PX → false
      ##   ③ 视线锥:   facing 方向点积 —— to_player.x * facing < cos(60°) * |dx| → false
      ##               （半角 60° → cos60° = 0.5；单向容差「> 阈值则 false」防浮点抖动）
      ##   ④ 边界语义: 闭区间含端点（距离恰 = RANGE、夹角恰 = 60° 均判定为可见）
      ##   ⑤ 玩家死亡/终态 → false（不追击尸体）

  func decide(delta: float) -> void:
      ## 纯决策入口（headless 测试手动调用；_physics_process 不直接调决策逻辑）：
      ##   ① 决策门控: entity 为 null / _dead / 实体非 idle/move 态 → 只清 move_intent 返回
      ##   ② 弹反抑制窗: Time 未到 _parry_stun_until_sec → 不决策（AC2 硬直 0.5s）
      ##   ③ 推进行为 FSM: _ai_fsm.update(delta) → 状态对象写 _move_intent /
      ##      entity.request_transition("attack"/"heavy_attack") / facing 更新

  func move_intent() -> Vector2:
      return _move_intent

  func _physics_process(delta: float) -> void:
      ## 位移执行（仿 #573 加速度模型，冷冽干脆）：
      velocity.x = move_toward(velocity.x, _move_intent.x, C.MOVE_ACCELERATION * delta)
      velocity.y = 0.0
      move_and_slide()

  func _on_player_state_changed(_from: String, to: String) -> void:
      ## AC3 触发源: 玩家进入 attack/heavy_attack（前摇开始）且玩家在
      ##   ENEMY_RETREAT_TRIGGER_RANGE 内 → 掷骰 5%（_rng.randf() < ENEMY_RETREAT_CHANCE）
      ##   → 行为 FSM 转移 RetreatState（95% 不打断当前行为）

  func _on_entity_state_changed(_from: String, to: String) -> void:
      ## 决策门控补充: 实体进入 stagger/stance_break/dead → 记录（decide 内自然被门控）；
      ## 弹反硬直检测: judge 绑定且收到 parry_success(defender=player, attacker=entity)
      ##   → _parry_stun_until_sec = now + ENEMY_PARRY_STUN_SECONDS（AC2 0.5s 补足层）

  func _on_entity_died(_entity, _final: bool) -> void:
      _dead = true
      _move_intent = Vector2.ZERO               # 死亡终态: 不再感知/移动/决策（§5 边界 6）

  func set_rng_seed(seed: int) -> void:
      rng_seed = seed
      _rng.seed = seed                          # 测试注入（实验 2：确定性回避统计）
  ```
- **集成说明:** 感知/决策/移动三块全部与场景树解耦（`decide` 手动驱动 + `_physics_process` 仅消费 move_intent）；攻击窗口**不手动登记**——实体进入 attack 态后 #577 自动登记（§3.1 参数化保证 windup=12、伤害=实体参数）；动画零介入——stick_figure 由战斗态 state_changed 驱动。

### 2.2 行为状态对象（`shandong-wolf/gdscripts/enemy_ai_states.gd`，新增）

- **文件:** `shandong-wolf/gdscripts/enemy_ai_states.gd`
- **范式:** 与 combat_states.gd 完全同构——`make_state(name, ai)` 工厂 + CombatStateBase 三接口（enter/exit/update）+ restart 钩子；基于 StateMachineBase（#572）派生，**不引入新状态机框架**（issue body「使用通用状态机扩展」字面对齐）。
- **AI 行为状态集（4 态，全部映射到既有战斗态动画，不进 11 态 CANONICAL_STATES）:**

```gdscript
const C = preload("res://gdscripts/constants.gd")

## 工厂: AI 行为态名 → 状态对象（未知 → PatrolState 兜底）
static func make_state(state_name: String, ai: Object) -> Object:
    match state_name:
        "patrol":   return PatrolState.new(ai)
        "chase":    return ChaseState.new(ai)
        "attack":   return AttackState.new(ai)
        "retreat":  return RetreatState.new(ai)
        _:          return PatrolState.new(ai)

class PatrolState:
    extends RefCounted
    ## 巡逻: waypoint ping-pong + 到达停顿 ENEMY_PATROL_PAUSE_SEC
    ##   - waypoints 空数组 → 原地 idle 等待（不报错，失败路径 2）
    ##   - 单 waypoint → ping-pong 降级原地等待（不报错，边界 8）
    ##   - 移动速度 ENEMY_PATROL_SPEED；到达 |dx| < 4px → 停 ENEMY_PATROL_PAUSE_SEC
    ##   - 感知触发（ai.can_sense_player()）→ ai._ai_fsm.transition_to(make_state("chase", ai))
    func enter(): _elapsed = 0.0; _dir = 1
    func update(delta): 推进 waypoint；写 ai._move_intent = Vector2(_dir * ENEMY_PATROL_SPEED, 0)

class ChaseState:
    extends RefCounted
    ## 追击: 转向 + 逼近 + 停距
    ##   - 转向: facing 更新为 sign(dx)，但受 ENEMY_TURN_DELAY_SEC 转向延迟约束
    ##            （防瞬移转身穿帮，边界 1；延迟计时在 update 内累积）
    ##   - 逼近: |dx| > ENEMY_ATTACK_RANGE → _move_intent.x = sign(dx) * ENEMY_CHASE_SPEED
    ##   - 停距: |dx| <= ENEMY_ATTACK_RANGE → _move_intent.x = 0
    ##   - 丢失: 距离 > ENEMY_LOSE_SIGHT_RANGE（= SENSE_RANGE × 1.5 派生）→ 回 Patrol
    ##            （从最近 waypoint 继续，不瞬移，边界 2）
    ##   - 攻击条件: 停距 + 冷却就绪（now >= ai._attack_cooldown_until_sec）
    ##            → transition_to(make_state("attack", ai))

class AttackState:
    extends RefCounted
    ## 攻击: 三连砍或突刺二选一 + 冷却
    ##   - 决策: _rng.randf() < ENEMY_THRUST_CHANCE → 突刺 heavy_attack；否则三连砍 attack
    ##   - 三连砍: entity.request_transition("attack") 进入战斗态；连段 = 收招 phase
    ##             再次 request_transition("attack")（同态 restart 钩子，#575 已支持）
    ##             连段次数 = 3（第 1 刀由本态发起，第 2/3 刀在 update 内按帧间隔补发）
    ##   - 突刺:   entity.request_transition("heavy_attack")（单发）
    ##   - 冷却:   攻击发起后 ai._attack_cooldown_until_sec = now + ENEMY_ATTACK_COOLDOWN_SEC
    ##   - 退出:   连段完成或实体离开 idle/move 门控（被弹反/受击/崩解 → 决策门控接管，
    ##              连段计划作废，边界 7）→ 回 Chase

class RetreatState:
    extends RefCounted
    ## 回避: 5% 后退一步再扑（反页游木桩，AC3）
    ##   - 进入: ai._on_player_state_changed 掷骰命中（玩家 attack 前摇开始 + 距离触发）
    ##   - 行为: 向远离玩家方向移动 ENEMY_RETREAT_SECONDS（速度 = ENEMY_CHASE_SPEED）
    ##   - 退出: 时长满 → 若 |dx| <= ENEMY_ATTACK_RANGE → Attack；否则 → Chase（边界 10）
```

- **集成说明:** 状态对象只写 `ai._move_intent` 与调 `ai.entity.request_transition()`，**绝不直接改 entity.state_name**（#575 request_transition 唯一转移入口红线）；AI 行为态名（patrol/chase/retreat）与战斗态名（11 态）是两个命名空间，动画映射由战斗态驱动（AI 零渲染）。


---

## 3. 既有组件修改

### 3.1 文件清单

**新文件（3）**

| 文件 | 内容 |
|------|------|
| `shandong-wolf/gdscripts/enemy_ai.gd` | EnemyAI（§2.1） |
| `shandong-wolf/gdscripts/enemy_ai_states.gd` | 4 行为状态对象（§2.2） |
| `shandong-wolf/tests/test_enemy_ai.gd` | §8 测试用例落地（implement agent 编写） |

**修改文件（6，全部 additive）**

| 文件 | 变更 | 动机 |
|------|------|------|
| `shandong-wolf/gdscripts/constants.gd` | 追加「AI 分区」# DRAFT 常量（§3.2） | AC4：AI 参数全部从 constants.gd 读取 |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | 追加 `var windup_frames: int = -1`；`hit_frame()` 优先用 windup_frames（≥0），-1 回退 FRAME_ATTACK_WINDUP | 敌人前摇 12 帧时命中帧正确（PRD §8.2-2） |
| `shandong-wolf/gdscripts/combat_entity.gd` | 追加 `@export var attack_hp_damage: float = -1.0` / `@export var attack_stance_damage: float = -1.0`（-1 = 玩家常量兜底） | 敌人变体携带自身攻击伤害，供判定层读取（PRD §8.2-3） |
| `shandong-wolf/gdscripts/combat_judge.gd` | `_on_entity_state_changed` 登记时：hp_damage 读 `entity.attack_hp_damage`（≥0 用实体值，否则 SWORD_DAMAGE_LIGHT/HEAVY 兜底）、stance_damage 读 `entity.attack_stance_damage`（≥0 用实体值，否则 POSTURE_HIT_COST 兜底）；windup 读 `ENEMY_ATTACK_WINDUP`（敌人）/ 默认玩家前摇 | 敌人伤害/前摇接入自动窗口（PRD §8.2-4） |
| `shandong-wolf/tests/run_tests.gd` | 追加 `_run("res://tests/test_enemy_ai.gd", "EnemyAI")` | 注册新套件 |
| `shandong-wolf/tests/smoke_test.gd` | （可选）AC5 冒烟场景：玩家站桩 + 敌人 5s 内完成巡逻→发现→接近→攻击路径 | AC5 |

**受影响的测试文件**

| 文件 | 变更性质 |
|------|---------|
| `shandong-wolf/tests/test_combat_judge.gd` | 零改动（additive 补丁回归基线，25 用例必须全绿） |
| `shandong-wolf/tests/run_tests.gd` | +1 行注册 |
| `shandong-wolf/tests/smoke_test.gd` | 可选追加 AC5 场景 |

**不修改（红线）:** `combat_state_table.gd` / `combat_states.gd` / `state_machine.gd` / `player_controller.gd` / `stick_figure_controller.gd` / `debug_canvas.gd` / `project.godot` / `scenes/Main.tscn` / `mini-pong/*`

### 3.2 constants.gd AI 分区（# DRAFT，全部「只狼基准/issue body → 候选 + 影响 + 情感断言」注释，定稿归 #584）

```gdscript
# ── AI 分区（# DRAFT 候补值，待 #584 定稿；#581 消费方，禁止实现期定稿）──
const ENEMY_SENSE_RANGE_PX: float = 600.0       # 候选 [400,500,600]；issue 指定 6m@100px/m；感知水平距离上限
const ENEMY_SENSE_ANGLE_DEG: float = 120.0      # issue 指定；半角 60° → cos60°=0.5 点积阈值（派生，不重复定义）
const ENEMY_SENSE_HEIGHT_TOLERANCE: float = 150.0  # 候选 [100,150,200]；平台制高度容忍（MVP 无 raycast）
const ENEMY_PATROL_SPEED: float = 80.0          # 候选 [60,80,100]；巡逻步态（火柴人 move 动画节奏）
const ENEMY_CHASE_SPEED: float = 180.0          # 候选 [150,180,220]；追击压迫感（低于玩家 300 但足够逼近）
const ENEMY_TURN_DELAY_SEC: float = 0.2         # 候选 [0.1,0.2,0.3]；转向延迟防瞬移转身穿帮
const ENEMY_ATTACK_RANGE: float = 80.0          # 候选 [70,80,100]；默认 80 = HITBOX_RANGE 对齐（停距=可命中）
const ENEMY_ATTACK_COOLDOWN_SEC: float = 1.5    # 候选 [1.2,1.5,2.0]；攻击节奏阀（压迫但不无脑）
const ENEMY_HP_DAMAGE: float = 15.0             # 候选 [10,15,20]；sekiro 敌小兵对玩家伤害基准（100/15≈7 刀击杀）
const ENEMY_HP_MAX: float = 40.0                # 候选 [30,40,50]；sekiro 敌小兵 HP 30-50（life_1_max 注入）
const ENEMY_THRUST_CHANCE: float = 0.3          # 候选 [0.2,0.3,0.5]；突刺 vs 三连砍 决策概率
const ENEMY_RETREAT_CHANCE: float = 0.05        # issue 指定（AC3）；5% 后退回避
const ENEMY_RETREAT_SECONDS: float = 0.5        # 候选 [0.3,0.5,0.8]；回避位移时长
const ENEMY_RETREAT_TRIGGER_RANGE: float = 200.0  # 候选 [150,200,250]；玩家攻击前摇触发回避的距离
const ENEMY_PARRY_STUN_SECONDS: float = 0.5     # 候选 [0.4,0.5,0.6]；默认 0.5 = AC2 硬直（AI 层补足）
const ENEMY_LOSE_SIGHT_RANGE: float = 900.0     # 派生 = ENEMY_SENSE_RANGE_PX × 1.5（候选倍数 [1.3,1.5,2.0]）
const ENEMY_PATROL_PAUSE_SEC: float = 1.0       # 候选 [0.5,1.0,1.5]；waypoint 到达停顿
```

**裁决点（PRD §8.4-1，本设计采纳）:** `ENEMY_ATTACK_WINDUP` 现有值 15（候选 [12,15,18]，#584 已 merge）——issue AC1 硬约束「攻击前摇 12 帧」→ **实现期改值为 12 并保留候选注释**（偏差记录交 #584 定稿；DebugCanvas 面板 `default: 15` 不改——面板仅展示候选，运行值读 constants）。本层只保证「读常量不硬编码」。

### 3.3 additive 补丁细节（implement 照此编写，现有 25 判定用例必须全绿）

```gdscript
## combat_attack_window.gd（追加字段 + 修改 hit_frame）
var windup_frames: int = -1     # -1 → 回退 FRAME_ATTACK_WINDUP（玩家窗口零变化）；敌人 = ENEMY_ATTACK_WINDUP
func hit_frame() -> int:
    var w: int = windup_frames if windup_frames >= 0 else int(C.FRAME_ATTACK_WINDUP)
    return start_frame + w

## combat_entity.gd（追加 @export，玩家行为零变化）
@export var attack_hp_damage: float = -1.0      # 敌人命中 HP 伤害（EnemyAI._ready 注入 ENEMY_HP_DAMAGE；-1=玩家常量兜底）
@export var attack_stance_damage: float = -1.0  # 敌人命中架势伤害（EnemyAI._ready 注入 POSTURE_HIT_COST；-1=玩家常量兜底）

## combat_judge.gd（_on_entity_state_changed 登记取值，不改任何接口/事件/裁决顺序）
var is_enemy: bool = entity != null and entity.has_method("is_player") and not entity.is_player
w.hp_damage = float(entity.attack_hp_damage) if (entity != null and entity.attack_hp_damage >= 0.0) \
    else float(C.SWORD_DAMAGE_HEAVY if to == "heavy_attack" else C.SWORD_DAMAGE_LIGHT)
w.stance_damage = float(entity.attack_stance_damage) if (entity != null and entity.attack_stance_damage >= 0.0) \
    else float(C.POSTURE_HIT_COST)
if is_enemy:
    w.windup_frames = int(C.ENEMY_ATTACK_WINDUP)   # 敌人前摇 12 帧（AC1）
# 玩家路径：windup_frames 保持 -1 → hit_frame 回退 FRAME_ATTACK_WINDUP=8，行为与现状逐字节一致
```

---

## 4. 数据流

### Flow 1：正常路径——巡逻 → 发现 → 追击 → 攻击（AC1/AC5）

```
1. EnemyAI 初始 PatrolState：沿 waypoints ping-pong（ENEMY_PATROL_SPEED，到达停顿 1.0s）
2. 玩家进入感知（|dx| <= 600px 且 视线夹角 <= 60° 且 高度差 <= 150px）→ can_sense_player() = true
3. → ChaseState：facing 转向 sign(dx)（受 0.2s 转向延迟）→ 以 ENEMY_CHASE_SPEED 逼近
4. |dx| <= ENEMY_ATTACK_RANGE(80) 且冷却就绪 → AttackState
5. AttackState 决策：randf() < 0.3 → 突刺 heavy_attack；否则三连砍 attack（收招 phase restart 连段 ×3）
6. entity.request_transition("attack") → 11 态战斗 FSM 进入 attack（前摇 12 帧 = ENEMY_ATTACK_WINDUP）
7. CombatJudge._on_entity_state_changed 自动登记 AttackWindow（windup=12、hp_damage=15、stance_damage=35、direction=facing）
8. 命中帧 start+12 → resolve_attack：玩家无 guard_pressed → 受击（take_damage(15) + take_stance_damage(35) + hit_landed 事件 → #579）
9. 冷却 1.5s → 重复 4-8（压迫感循环）
```

### Flow 2：弹反路径——前摇可弹反 → 硬直 → 架势 → 崩解（AC2）

```
1. 敌人 AttackState 进入 attack（前摇 12 帧窗口 active）
2. 玩家 guard_pressed 时间戳 ∈ [hit_ms - 200ms, hit_ms] 且 facing 正确 → parry_ok（#577 既有逻辑，零改动）
3. CombatJudge._resolve_parry：敌人 take_stance_damage(25)（PARRY_STANCE_DAMAGE 只读消费）
   + 玩家 request_transition("parry_success") + emit parry_success → #579
4. EnemyAI 收到 parry_success（judge 绑定）→ _parry_stun_until_sec = now + 0.5s（ENEMY_PARRY_STUN_SECONDS）
   ——共享 parry_success 态仅 10 帧 ≈0.167s，AI 抑制窗补足至 AC2 的 0.5s 硬直（期间不追击不攻击）
5. 第 4 次弹反：4 × 25 = 100 = POSTURE_BREAK_THRESHOLD → stance <= 0 → break_stance()
   → stance_break 态 3.0s（#575 战斗状态机自然驱动，AI 决策门控全程不抢戏）→ #580 处决接管
6. stance_break 恢复 idle → AI 决策门控解锁 → 回 ChaseState 继续
```

### Flow 3：5% 回避路径（AC3）

```
1. 玩家 request_transition("attack") → player.state_changed → "attack"（前摇开始）
2. EnemyAI._on_player_state_changed：|dx| <= ENEMY_RETREAT_TRIGGER_RANGE(200) → 掷骰
3. _rng.randf() < 0.05（seed 可注入）→ RetreatState：向远离玩家移动 0.5s（ENEMY_RETREAT_SECONDS）
4. 时长满 → |dx| <= 80 → AttackState（回扑）；否则 ChaseState（玩家后撤了，边界 10）
5. 95% 未命中 → 不打断当前行为（继续巡逻/追击/攻击决策）
```

### Flow 4：失败/边界路径

```
a. waypoints 未配置（空数组）→ PatrolState 原地等待（push_warning 一次），感知触发仍可 Chase
b. judge 未绑定（null）→ EnemyAI 正常移动/感知/转移，攻击窗口不登记（push_warning 一次）——
   headless 行为路径测试无需 judge；窗口断言单独在绑定 judge 的用例中验证
c. 实体死亡（life_total=1 → die() → dead 终态）→ _on_entity_died → _dead=true → AI 完全禁用
d. 实体受击/崩解中（stagger/stance_break/attack 等非 idle/move 态）→ decide() 门控直接返回，
   战斗 FSM 接管动画，AI 不抢戏
```


---

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| 1. 玩家在敌人身后（facing 反向） | 视线锥外不发现；Chase 中玩家绕后 → 敌人转向（ENEMY_TURN_DELAY_SEC=0.2s 延迟，防瞬移转身穿帮）后重新判定 |
| 2. 玩家超出追击范围 | Chase 中丢失（距离 > ENEMY_LOSE_SIGHT_RANGE=900）→ 回 Patrol（从最近 waypoint 继续，不瞬移） |
| 3. 玩家处于不可命中态（dead/revive/execute/无敌期） | judge 守卫已 no-op（#577）；AI 感知对死亡玩家返回 false（不追击尸体） |
| 4. 敌人被连续弹反至 stance_break | stance_break 态 3.0s 内 AI 不决策（战斗 FSM 接管失衡动画）；恢复 idle 后回 Chase；期间 #580 处决接管则 AI 禁用 |
| 5. 敌人受击 stagger（玩家刀命中） | stagger 态 12 帧 AI 不决策；恢复后继续（受击双重惩罚 hp+stance 由 #577 施加） |
| 6. 敌人死亡 | life_total=1 → die() → dead 终态（_is_final_dead）→ _dead=true → AI 完全禁用（不再感知/移动/决策） |
| 7. 三连砍连段中断 | 连段第 2/3 刀前玩家弹反/敌人受击 → parry_success/stagger → 决策门控接管，连段计划作废（AI 抑制窗/硬直优先） |
| 8. 巡逻路径只有一个 waypoint | ping-pong 降级为原地等待（不报错）；空数组同样降级（失败路径 2） |
| 9. 敌人与玩家高度差超容忍 | 高度差 > ENEMY_SENSE_HEIGHT_TOLERANCE → 不发现/不追击（MVP 平台制简化，无 raycast） |
| 10. 5% 回避期间玩家后撤 | Retreat 期满后目标距离 > ENEMY_ATTACK_RANGE → 回 Chase 而非 Attack（不空挥） |
| 11. 感知数值非法（范围 ≤0 / 角度 >180） | push_warning + 回退默认值（不崩溃，仿 StickFigure 参数校验范式） |
| 12. 弹反硬直期间玩家再次出刀 | 抑制窗未结束 → AI 不决策（不会「硬直中反击」穿帮）；抑制窗结束 → 正常决策 |
| 13. 同帧多次玩家攻击事件 | 回避掷骰逐事件独立采样（无状态），重复触发无累积效应（实验 2 内化） |
| 14. 敌人攻击态内玩家先命中（敌人 attack 中受击） | 战斗态由 #575 接管（attack → stagger 表内转移合法），AI 决策门控等待恢复；无双重攻击 |

**失败路径**

| 失败场景 | 处理 |
|---------|------|
| waypoints 未配置（@export 空数组） | Patrol 降级原地等待（push_warning 一次，不崩溃）；Chase 仍可被感知触发 |
| judge 未绑定（null） | EnemyAI 正常移动/感知/转移，攻击窗口不登记（push_warning 一次）——headless 行为路径测试无需 judge |
| entity 未绑定（null） | decide() 门控直接返回（不 NPE）；_physics_process 仍可移动（测试可先验移动模型） |

---

## 6. 每场景/每组件配置

| 配置项 | 值 | 提供方 | 说明 |
|--------|:---:|--------|------|
| `EnemyAI.waypoints` | 巡逻路径坐标数组 | #583（场景 issue，未开始） | 雪夜村口固定路径；本 issue 测试用临时坐标 |
| `EnemyAI.player` | 玩家节点引用 | #585（组装 issue，未开始） | 本 issue 测试直接注入 |
| `EnemyAI.judge` | CombatJudge 引用 | #585 | null 时行为路径可测 |
| `CombatEntity(is_player=false)` 变体 | life_total=1 / life_1_max=ENEMY_HP_MAX(40) / stance_max=POSTURE_BREAK_THRESHOLD(100) | #585 组合约定（PRD §8.3） | 攻击伤害参数由 EnemyAI._ready 注入 |
| `ENEMY_ATTACK_WINDUP` | 12（AC1 对齐，原 15） | #584 定稿域 | 实现期改值 + 保留候选注释 |

---

## 7. 集成点

> **Status 约定：** ⬜ = pending（资源已设计，未连接）；✅ = connected（implement agent 验证）。implement 必须在接线时更新本表；review agent 验证全部 ⬜ 已解决或显式推迟。

| 集成 | 本组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| 敌人攻击窗口登记 | EnemyAI → CombatEntity(attack 态) → CombatJudge 自动登记 | #577 | state_changed 信号（#577 既有，additive 参数化后敌人窗口生效） | ✅（#581 impl 接线：judge 登记读实体参数 + windup=12） |
| 弹反硬直抑制窗 | EnemyAI 订阅 judge.parry_success / player.state_changed→parry_success | #577/#581 | 信号订阅 → _parry_stun_until_sec | ✅（#581 impl 接线：judge.parry_success → 0.5s 抑制窗） |
| 5% 回避触发 | EnemyAI 订阅 player.state_changed → attack/heavy_attack | #573/#581 | 信号订阅 + RNG 掷骰 | ✅（#581 impl 接线：player.state_changed → RNG seed 注入掷骰） |
| 打击反馈消费 | judge.hit_landed/parry_success/clash/block_held/stance_broken | #579 | 事件订阅（#577 已发射，本 issue 不实现） | ⬜（下游） |
| 处决接管 | entity.stance_broken + stance_break 态 3s 窗口 | #580 | stance_broken 信号（#575 已发射） | ⬜（下游） |
| 场景出生点/巡逻路径 | EnemyAI.waypoints @export | #583 | 场景配置数据 | ⬜（下游） |
| 场景组装 | EnemyAI + CombatEntity + StickFigureController | #585 | 节点组合（PRD §8.3 组合约定） | ⬜（下游） |
| GDD 落盘 | docs/GAME_DESIGN/shandong-wolf/12-ENEMY-AI.md（新章节） | post-merge | post-merge agent | ⬜ |

---

## 8. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | constants.gd AI 分区常量（§3.2）+ ENEMY_ATTACK_WINDUP 15→12 | 0.5 天 |
| Phase 2 | P0 | 3 处 additive 补丁：combat_attack_window.gd / combat_entity.gd / combat_judge.gd（§3.3）→ 跑既有 test_combat_judge.gd 25 用例全绿（回归基线） | 0.5 天 |
| Phase 3 | P0 | enemy_ai.gd（§2.1）：FSM 持有 + can_sense_player + decide 门控 + 位移 | 1 天 |
| Phase 4 | P0 | enemy_ai_states.gd（§2.2）：Patrol/Chase/Attack/Retreat | 0.5 天 |
| Phase 5 | P1 | test_enemy_ai.gd（§8 测试用例）+ run_tests.gd 注册 + smoke_test.gd AC5（可选） | 0.5-1 天 |
| Phase 6 | P1 | 全量回归：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 10 套件全绿 + smoke | 0.25 天 |


---

## 9. 测试用例描述

> **测试纪律（对齐 test_combat_judge.gd 范本）：** headless 免树——EnemyAI/CombatEntity 直接 `new()` + 手动调 `decide(delta)`/`request_transition()`/`tick_frame()`，不依赖真实帧/物理/Input；RNG 一律 `set_rng_seed()` 注入确定性；禁止 `:=` 类型推断（Godot 4.7.1 视推断警告为硬错误）；class_name 一律经 `load()` 访问。**本阶段只写描述，可运行测试代码由 implement agent 编写。**

### Scenario A：主路径——巡逻 → 发现 → 追击 → 攻击（AC1 + AC5）

- Test 1 巡逻起步：EnemyAI + entity 绑定，waypoints=[(-300,0),(300,0)]，玩家远置（1000px 外）→ 手动推进 decide()，断言 entity.state_name 保持 idle/move、敌人 x 坐标在 waypoints 间往返（ping-pong），到达停顿 ≥ ENEMY_PATROL_PAUSE_SEC
- Test 2 感知发现：玩家置于 (400, 0)（|dx|=400 ≤ 600 且视线内）→ 断言 can_sense_player() == true；行为 FSM 转移 ChaseState（facing 转向 sign(dx)）
- Test 3 追击逼近：Chase 中玩家保持静止 → 敌人 x 以 ENEMY_CHASE_SPEED 逼近；|dx| 收敛至 ≤ ENEMY_ATTACK_RANGE 后停距（move_intent.x == 0）
- Test 4 攻击发起（AC1）：停距 + 冷却就绪 → 断言 entity.request_transition("attack") 生效（entity.state_name == "attack"）且敌人 attack_hp_damage == ENEMY_HP_DAMAGE
- Test 5 攻击窗口 windup（AC1）：绑定 judge + tick_frame 推进 → 断言自动登记的 AttackWindow.windup_frames == ENEMY_ATTACK_WINDUP（12）且 hit_frame() == start + 12（窗口命中帧正确）
- Test 6 三连砍 vs 突刺决策：seed 注入固定 → 多次攻击决策断言攻击态为 attack（连段）或 heavy_attack（突刺），两者均发生（ENEMY_THRUST_CHANCE=0.3 统计面）
- Test 7 攻击冷却：攻击后立即再决策 → 冷却未到不发起（_attack_cooldown_until_sec 门控）；冷却过后可再次发起
- Test 8 AC5 smoke：玩家站桩于感知范围内（400px）→ 模拟推进 5s（decide(1/60) × 300 帧）→ 断言 5s 内 entity.state_name 到达 "attack"（完成巡逻→发现→接近→攻击全路径）
- Test 9 攻击态内可被弹反（AC1 后半）：敌人 attack 窗口 active 时玩家 guard_pressed 在弹反闭区间 → parry_success 事件（复用 #577 既有逻辑断言，敌人窗口 windup=12 下 hit_ms 正确）

### Scenario B：感知边界（PRD 实验 1 内化）

- Test 10 角度边界：玩家与 facing 夹角恰 60°（半角边界）→ can_sense_player() == true（闭区间含端点）；夹角 61° → false
- Test 11 距离边界：|dx| 恰 600（= ENEMY_SENSE_RANGE_PX）→ true；601 → false（「> 阈值则 false」单向容差）
- Test 12 高度容忍：|dy| 恰 150 → true；151 → false
- Test 13 身后不发现：玩家在敌人背后（facing 反向，夹角 >90°）→ false（视线锥外）
- Test 14 追击丢失：Chase 中玩家移出 ENEMY_LOSE_SIGHT_RANGE（900px）→ 回 PatrolState（从最近 waypoint 继续，位置不瞬移）
- Test 15 感知可复现性：同相对位置矩阵（8 方位 × 3 距离 × 3 高度差）→ 判定结果仅依赖 facing/距离/高度三输入（无隐藏状态）

### Scenario C：弹反硬直与架势崩解（AC2）

- Test 16 弹反架势扣减：敌人被弹反 → entity.stance 扣 25（PARRY_STANCE_DAMAGE 只读消费）且收到 parry_success 事件
- Test 17 连续 4 次弹反崩解：弹反 ×4 → 4×25=100=POSTURE_BREAK_THRESHOLD → stance ≤ 0 → break_stance() → entity.state_name == "stance_break"（数值自洽断言）
- Test 18 弹反硬直抑制窗：弹反后 enemyAI._parry_stun_until_sec 生效（0.5s = ENEMY_PARRY_STUN_SECONDS）→ 抑制窗内 decide() 不发起追击/攻击（move_intent 归零）；抑制窗过后恢复决策
- Test 19 崩解期间 AI 不决策：stance_break 态（3.0s）内 decide() 门控返回（不移动不攻击）；恢复 idle 后回 ChaseState

### Scenario D：5% 后退回避（AC3 + PRD 实验 2 内化）

- Test 20 回避触发：seed 注入使 randf() < 0.05 → 玩家进入 attack 前摇且 |dx| ≤ ENEMY_RETREAT_TRIGGER_RANGE → RetreatState：敌人向远离玩家方向移动 ENEMY_RETREAT_SECONDS
- Test 21 回避频率统计：固定 seed 模拟 1000 次「玩家 attack 前摇开始」事件 → Retreat 触发次数频率 ∈ [0.03, 0.07]（收敛于 0.05 ± 0.02）
- Test 22 确定性：同一 seed 重跑 → 回避序列逐次一致（CI 稳定）；无 seed（-1）→ 全局 RNG 兜底不崩溃
- Test 23 95% 不回避：seed 注入 randf() ≥ 0.05 → 当前行为不被打断（Chase 继续逼近 / 攻击决策照常）
- Test 24 回避后回扑：Retreat 期满且 |dx| ≤ ENEMY_ATTACK_RANGE → AttackState；玩家后撤（|dx| > 80）→ ChaseState（边界 10）

### Scenario E：常量驱动（AC4）

- Test 25 全参数读常量：断言 AI 代码路径零字面量（code review 项）——改 ENEMY_SENSE_RANGE_PX（600→400）→ can_sense_player 距离边界随动；改 ENEMY_RETREAT_CHANCE（0.05→0.1）→ 回避频率随动；改 ENEMY_PARRY_STUN_SECONDS → 抑制窗时长随动
- Test 26 感知数值非法兜底：ENEMY_SENSE_RANGE_PX ≤ 0 / 角度 > 180 → push_warning + 回退默认值（不崩溃）

### Scenario F：边界与失败路径（§5）

- Test 27 waypoints 空数组：Patrol 原地等待（push_warning 一次，不报错）；玩家进入感知 → 仍可 Chase
- Test 28 单 waypoint：ping-pong 降级原地等待（不报错）
- Test 29 judge 未绑定：decide 正常推进行为路径（攻击不登记窗口，push_warning 一次）；不 NPE
- Test 30 entity 未绑定：decide 门控返回；_physics_process 移动模型可独立验证（move_intent 消费）
- Test 31 敌人死亡：entity.die()（life_total=1 → final dead）→ _dead=true → 后续 decide() 完全禁用（move_intent 归零、不再感知）
- Test 32 敌人受击 stagger：敌人 attack 中玩家命中 → stagger 态 12 帧内 decide 门控返回；恢复后继续
- Test 33 连段中断：三连砍第 2 刀前玩家弹反 → parry_success → 连段计划作废（抑制窗接管，不继续第 3 刀）
- Test 34 回避期间玩家后撤：Retreat 期满 |dx| > 80 → ChaseState（不空挥攻击）

### Scenario G：回归基线

- Test 35 additive 无回归：既有 test_combat_judge.gd 25 用例全绿（windup_frames -1 回退路径下玩家窗口行为与现状逐字节一致；judge 登记玩家伤害走常量兜底路径）
- Test 36 全量回归：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 10 套件全绿（含既有 9 套件防回归）；`smoke_test.gd` 通过


---

## 10. 验收条件映射（源自 Issue #581 body）

| # | 验收条件 | 本设计保障 | 覆盖用例 |
|---|---------|-----------|:-------:|
| AC1 | 日本兵具备 巡逻→追击→攻击 状态流转，攻击前摇 12 帧且前摇期间可被弹反 | §2.1/§2.2 AI 行为 FSM 三态流转；§3.2 ENEMY_ATTACK_WINDUP 15→12（AC 对齐，保留候选注释）；§3.3 AttackWindow.windup_frames + judge 自动登记 → 前摇帧 = 12 且窗口内弹反走 #577 既有闭区间逻辑 | T1-T9 |
| AC2 | 被弹反后硬直 0.5s 并增加 25 架势值，连续 4 次弹反可崩解（数值来自 constants.gd） | PARRY_STANCE_DAMAGE=25 只读消费（4×25=100=POSTURE_BREAK_THRESHOLD 自洽）；0.5s 硬直 = AI 层 ENEMY_PARRY_STUN_SECONDS 抑制窗补足（共享 parry_success 态仅 0.167s） | T16-T19 |
| AC3 | AI 有 5% 概率在玩家攻击前摇时后退闪避 | ENEMY_RETREAT_CHANCE=0.05 读 constants；player.state_changed→attack 触发；RNG seed 可注入（确定性单测） | T20-T24 |
| AC4 | AI 参数全部从 constants.gd 读取 | §3.2 AI 分区 17 常量全 # DRAFT；§2 代码零字面量；测试改常量值断言行为随动 | T25-T26 |
| AC5 | smoke test：玩家站桩时敌人 5s 内完成巡逻→发现→接近→攻击的路径 | headless 模拟 5s（decide(1/60)×300 帧）断言 entity.state_name == "attack"；smoke_test.gd 可选落地 | T8 |

## 11. 明确不修改（与 PRD §8.5 红线对齐）

- ❌ 不改 11 态 `CANONICAL_STATES` / `consume_state` 契约（#575 状态名权威集；patrol/chase/retreat 是 **AI 行为态**，不进战斗状态表）
- ❌ 不引入 Area2D/CollisionShape2D 物理碰撞（#577 逻辑帧窗口架构；攻击命中复用 judge 自动登记）
- ❌ 不裁决 # DRAFT 数值（只读 constants；AI 新常量也标 # DRAFT 候选集，定稿归 #584；ENEMY_ATTACK_WINDUP 15→12 为 PRD §8.4-1 已裁决例外，偏差记录交 #584）
- ❌ 不改 #577 五结果事件名与裁决顺序（parry_success/block_held/hit_landed/clash/stance_broken 契约）
- ❌ 不修改既有接口签名（judge/entity/AttackWindow 全部 additive 扩展，现有 test_combat_judge.gd 25 用例必须全绿）
- ❌ 不写死 AI 数值字面量（感知/速度/冷却/伤害/概率/抑制窗全走 constants）
- ❌ 不改 debug_canvas.gd（#584 调参面板域；AI 新常量如需面板登记由 #584 追加，本 issue 只保证 constants 只读消费）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不修改 scenes/Main.tscn（标题场景红线）
- ❌ 不做场景组装与渲染（#583/#585 职责）；敌人视觉复用 SW-003，AI 层零渲染代码
- ❌ 不写可运行实现/测试代码（本 phase 仅 DESIGN + TASKS 文档；测试代码归 implement agent）

## 附：风险裁决点采纳（PRD §8.4）

| # | 裁决点 | 本设计采纳 |
|---|--------|-----------|
| 1 | ENEMY_ATTACK_WINDUP 12 vs 15（AC1 vs constants 默认） | 实现期取 12 对齐 AC（改常量值 + 保留候选注释），偏差记录给 #584 定稿——本层只保证「读常量不硬编码」 |
| 2 | 0.5s 弹反硬直的实现位置 | AI 层抑制窗 ENEMY_PARRY_STUN_SECONDS 补足（不改共享 parry_success 态，避免影响玩家弹反手感）；若用户裁决改战斗态，属 #584 域 |
| 3 | 三连砍连段窗口覆盖 | judge 同 attacker 旧窗口覆盖（连段语义已支持）；连段间隔/冷却调参归 #584 |
| 4 | 敌人攻击伤害默认值 | ENEMY_HP_DAMAGE=15（候选 [10,15,20]），100/15≈7 刀击杀与「压迫感但可失误」MVP 一致 |
| 5 | #585 组装前可用性 | headless 单测 + smoke 全免场景树（decide 手动驱动）；场景化组装依赖 #583/#585，不阻塞 |
| 6 | GDD 落盘 | post-merge agent 新增 `docs/GAME_DESIGN/shandong-wolf/12-ENEMY-AI.md` |

## 附：开源调研结论（PRD §6.2 已调研，implement PR 须附说明）

PRD §6.2 结论直接引用：Godot enemy AI 生态（Snaiel/Godot4ThirdPersonCombatPrototype 234⭐ 3D 战斗原型、metanoia83/XdrenalYT 3D 教学 demo、Cod-e-Codes/SarutobiSasuke8 2D 完整游戏原型）——要么 3D 视角与横板 2D + 逻辑帧判定架构不符、要么教学 demo 非可复用库；Behaviour Tree 库（andrew-wilkes/godot-behaviour-tree 53⭐ 最高、JassJam 11⭐、ratkingsminion 5⭐）非 Godot 4.7 官方生态且与 issue body「使用通用状态机扩展」方向冲突。**无成熟可复用的「Godot 2D 横板类只狼敌人 AI」开源库 → 自研 EnemyAI 行为状态机（方案 A，issue body 允许「找不到再自行实现」）。** implement PR 须引用本调研结论，无需重复调研。

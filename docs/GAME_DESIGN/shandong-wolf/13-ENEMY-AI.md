# 基础日本兵 AI — EnemyAI 行为状态机 + 判定层 additive 参数化（#581/#638）

> 落盘依据：PR #638（implement，squash-merge 2026-08-20, commit 75b0b34）← DESIGN `docs/DESIGN/581-enemy-ai.md`（plan #633 已 merge）← PRD `docs/PRD/581-enemy-ai.md`（research #632 已 merge）。
> 上游：#575 CombatEntity 敌人变体与 11 态状态机（08/09 章）、#577 CombatJudge 自动登记窗口与五结果事件（11 章）、#573 PlayerController 加速度移动模型（06 章）、#584 数值 DRAFT 纪律与 DebugCanvas（02/05 章）。
> 本层是 #585 战斗闭环组装的**最后一个行为组件**：敌人「能被打/能弹反/能崩解」的承受面已就绪（#575/#577），本层交付「谁驱动敌人」。下游 #579 反馈 / #580 处决 / #583 场景 / #585 组装 / #586 E2E 全部挂接本层接口。

## 1. 设计意图

**问题本质是「战斗层原料全部就绪，『谁驱动敌人』零存在」。** #575/#577/#584 已让敌人具备承受面（is_player=false 变体、自动登记 AttackWindow、11 态战斗状态机、只狼基准常量），但 `gdscripts/` 无任何 AI 层：无行为状态机、无感知、无敌人移动实体、无攻击决策。本 issue 交付 = 敌人行为驱动面。

设计哲学五条（PRD §4.1 方案 A 确认采纳，DESIGN 定稿，implement 逐字落实）：

1. **行为层与战斗层解耦**：EnemyAI 是独立 Node（CharacterBody2D 移动实体），持有**第二个** StateMachineBase 实例（AI 行为态 patrol/chase/attack/retreat）；战斗 11 态与 #577 判定原样复用。单向依赖：AI 决策 → `entity.request_transition("attack"/"heavy_attack")` + 位移意图；战斗结果 → 经 state_changed / stance_broken / parry_success 信号反向门控 AI 决策。两层可 headless 单测。
2. **决策门控 = 硬约束**：AI 只在实体处于 `idle`/`move` 态时做决策（战斗动画/硬直期间由 combat FSM 接管，AI 不抢戏）；弹反命中后 AI 进入 `ENEMY_PARRY_STUN_SECONDS`（0.5s）抑制窗——共享 parry_success 态仅 10 帧（≈0.167s），0.5s 硬直由 **AI 层补足**（不改共享战斗态，避免影响玩家弹反手感）。
3. **感知 = 几何判据，不是物理**：120° 视线锥用 facing 方向点积（半角 60° → cos60°=0.5）+ 水平距离 + 高度容忍判定，无 raycast / 无 Area2D——与 #577「零碰撞体」架构一致。
4. **判定 = 复用自动窗口**：#577 `_on_entity_state_changed` 已对任意实体进入 attack 态自动登记窗口——AI 无需手动登记，只需 3 处 additive 参数化（§4），玩家路径行为与现状逐字节一致。
5. **数值 = 全走 constants**：感知范围/角度/速度/冷却/伤害/概率/抑制窗全部新增 AI 分区 # DRAFT 常量（17 个 + ENEMY_ATTACK_WINDUP 改值），AI 代码零字面量。

**方案裁决**：方案 A（EnemyAI 独立行为状态机 + 判定层自动窗口复用）采纳；否决方案 B（扩 11 态转移表——违反 #575 状态名权威集红线）与方案 C（Behaviour Tree 开源库——与 issue body「使用通用状态机扩展」冲突 + MVP 过度设计）。

## 2. 架构决策

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|---------------|---------|---------|
| AI 架构 | EnemyAI 独立行为状态机（第二个 StateMachineBase，4 行为态） | 扩 11 态转移表 / Behaviour Tree 库 | #575 状态名权威集红线；issue body「通用状态机扩展」；开源库非 Godot 4.7 官方生态且无 2D 横板类只狼先例 |
| 感知 | 几何判据（点积视线锥 + 距离 + 高度容忍） | raycast / Area2D | #577 零碰撞体架构一致；弹反是时间窗，物理碰撞无法表达 |
| 弹反硬直 0.5s | AI 层抑制窗 ENEMY_PARRY_STUN_SECONDS 补足 | 改共享 parry_success 战斗态 | 共享态仅 10 帧，改战斗态影响玩家弹反手感（#584 域） |
| 攻击前摇 | ENEMY_ATTACK_WINDUP 15→12（AC1 对齐） | 保持 15 | issue AC1 硬约束「攻击前摇 12 帧」；偏离记录交 #584 定稿 |
| 判定参数化 | 3 处 additive（windup_frames / 伤害 @export / judge 读实体参数） | 敌人专用判定分支 | 玩家路径零变化，既有 25 判定用例必须全绿 |

## 3. EnemyAI 组件

文件：`shandong-wolf/gdscripts/enemy_ai.gd`（class_name `EnemyAI` extends CharacterBody2D，非 autoload——#585 组装时实例化进场景）。

**职责：** 行为 FSM 持有 + 感知（120° 视线 6m）+ 决策门控 + 位移执行。**`decide(delta)` 纯决策方法（无物理依赖，headless 测试手动驱动）与 `_physics_process`（只消费 `_move_intent`，仿 #573 加速度模型）分离**——这是可测性核心。

**Node 结构（#585 组装约定，本 issue 不组装场景）：**

```
EnemyAI (CharacterBody2D)          ← 本类
├── CombatEntity (is_player=false, life_total=1, life_1_max=ENEMY_HP_MAX=40,
│                 stance_max=POSTURE_BREAK_THRESHOLD=100, 本地坐标 (0,0))
└── StickFigureController          ← 复用 SW-003 骨架（consume_state 驱动，AI 零渲染）
```

**@export 参数（#583 场景配置；测试直接注入）：**

```gdscript
@export var waypoints: Array = []    # 巡逻路径（空数组=原地等待，不报错）
@export var player: Node2D           # 玩家实体引用（感知/追击目标）
@export var judge: Node = null       # CombatJudge 引用（null = 不登记窗口，仅行为路径可测）
@export var rng_seed: int = -1       # -1 = 全局 RNG；≥0 = 确定性（测试注入，CI 稳定）
```

**关键接口（定义）：**

```gdscript
func bind_entity(e) -> void          # #585 组装调用：注入 attack_hp_damage/attack_stance_damage + 订阅 state_changed/died
func can_sense_player() -> bool      # 纯函数几何判据（无物理）
func decide(delta: float) -> void    # 纯决策入口：门控 → 推进行为 FSM（headless 手动调用）
func move_intent() -> Vector2        # decide 写、_physics_process 读
func set_rng_seed(seed: int) -> void # 测试注入（确定性回避统计）
```

**决策门控（decide 内硬约束，顺序执行）：**

```
① entity 为 null / _dead → 清 move_intent 返回（终态完全禁用）
② 实体非 idle/move 态（stagger/stance_break/attack 等）→ 清 move_intent 返回（战斗 FSM 接管）
③ Time 未到 _parry_stun_until_sec（弹反抑制窗）→ 清 move_intent 返回（硬直 0.5s 不追击不攻击）
④ 推进行为 FSM → 状态对象写 _move_intent / 调 entity.request_transition
```

**can_sense_player() 几何判据（闭区间含端点，「> 阈值则 false」单向容差防浮点抖动）：**

```
① 玩家死亡终态（_is_final_dead）→ false（不追击尸体）
② 水平距离 |dx| > ENEMY_SENSE_RANGE_PX(600) → false
③ 视线锥: to_player.x * facing < cos(60°) * |to_player| → false（半角 60° → cos60°=0.5，阈值由
   cos(deg_to_rad(ENEMY_SENSE_ANGLE_DEG / 2.0)) 计算，角度恰 = 半角判定可见）
④ 高度容忍 |dy| > ENEMY_SENSE_HEIGHT_TOLERANCE(150) → false
```

## 4. 判定层 additive 参数化（3 处，玩家路径零变化）

#577 已对任意实体进入 attack 态自动登记 AttackWindow——敌人窗口生效只需参数化，不改任何接口签名/事件名/裁决顺序：

```gdscript
## combat_attack_window.gd
var windup_frames: int = -1     # -1 → 回退 FRAME_ATTACK_WINDUP（玩家窗口零变化）；敌人 = ENEMY_ATTACK_WINDUP(12)
func hit_frame() -> int:        # 优先 windup_frames（≥0），否则 int(C.FRAME_ATTACK_WINDUP)

## combat_entity.gd（追加 @export，玩家行为零变化）
@export var attack_hp_damage: float = -1.0      # 敌人命中 HP 伤害（bind_entity 注入 ENEMY_HP_DAMAGE；-1=玩家常量兜底）
@export var attack_stance_damage: float = -1.0  # 敌人命中架势伤害（bind_entity 注入 POSTURE_HIT_COST；-1=玩家常量兜底）

## combat_judge.gd（_on_entity_state_changed 登记取值，不改接口/事件/裁决顺序）
# hp_damage/stance_damage: 实体参数 ≥0 用实体值，否则玩家常量（SWORD_DAMAGE_LIGHT/HEAVY、POSTURE_HIT_COST）兜底
# 敌人（is_player=false）额外: w.windup_frames = int(C.ENEMY_ATTACK_WINDUP)  # 前摇 12 帧（AC1）
# 玩家路径: windup_frames 保持 -1 → hit_frame 回退 FRAME_ATTACK_WINDUP=8，行为与现状逐字节一致
```

## 5. 行为状态对象（enemy_ai_states.gd，4 态）

文件：`shandong-wolf/gdscripts/enemy_ai_states.gd`。范式与 combat_states.gd 完全同构——`make_state(name, ai)` 工厂 + enter/exit/update 三接口；基于 StateMachineBase（#572）派生，**不引入新状态机框架**。AI 行为态名（patrol/chase/retreat）与战斗 11 态是两个命名空间，**绝不直接改 entity.state_name**（#575 request_transition 唯一转移入口红线）。

| 行为态 | 职责 | 关键参数 |
|--------|------|---------|
| PatrolState | waypoint ping-pong 巡逻 + 到达停顿；空数组/单点降级原地等待（不报错）；感知触发 → Chase | ENEMY_PATROL_SPEED=80 / ENEMY_PATROL_PAUSE_SEC=1.0 |
| ChaseState | 转向（sign(dx)，ENEMY_TURN_DELAY_SEC=0.2s 延迟防瞬移转身）+ 逼近 + 停距；丢失（>ENEMY_LOSE_SIGHT_RANGE=900，= SENSE_RANGE×1.5 派生）回 Patrol（从最近 waypoint 继续不瞬移）；停距+冷却就绪 → Attack | ENEMY_CHASE_SPEED=180 / ENEMY_ATTACK_RANGE=80 / ENEMY_TURN_DELAY_SEC=0.2 |
| AttackState | 三连砍（attack 连段 restart 钩子 ×3）或突刺（heavy_attack）二选一 + 冷却；被弹反/受击 → 决策门控接管，连段计划作废 | ENEMY_THRUST_CHANCE=0.3 / ENEMY_ATTACK_COOLDOWN_SEC=1.5 |
| RetreatState | 5% 后退回避（玩家 attack 前摇触发，逐事件独立采样无累积）；期满按距离回 Attack 或 Chase | ENEMY_RETREAT_CHANCE=0.05 / ENEMY_RETREAT_SECONDS=0.5 / ENEMY_RETREAT_TRIGGER_RANGE=200 |

## 6. AI 分区常量（constants.gd，# DRAFT 只读不裁决，定稿归 #584）

全部 # DRAFT 候补值（三行注释：候选集/影响/情感断言），实现期禁止定稿。ENEMY_ATTACK_WINDUP 15→12 为 PRD §8.4-1 已裁决的 AC 对齐例外，偏离记录交 #584。

| 常量 | 值 | 候选集 | 含义 |
|------|:---:|--------|------|
| ENEMY_ATTACK_WINDUP | 12 | [12,15,18] | 敌人攻击前摇帧（AC1 对齐，原 15；DebugCanvas 面板 default 15 不改，运行值读 constants） |
| ENEMY_SENSE_RANGE_PX | 600.0 | [400,500,600] | 感知水平距离上限（6m@100px/m，issue 指定） |
| ENEMY_SENSE_ANGLE_DEG | 120.0 | [90,120,180] | 视线张角（半角 60° → cos60°=0.5 点积阈值派生） |
| ENEMY_SENSE_HEIGHT_TOLERANCE | 150.0 | [100,150,200] | 平台制高度容忍（MVP 无 raycast） |
| ENEMY_PATROL_SPEED | 80.0 | [60,80,100] | 巡逻步态速度 |
| ENEMY_CHASE_SPEED | 180.0 | [150,180,220] | 追击速度（低于玩家 300 但足够逼近） |
| ENEMY_TURN_DELAY_SEC | 0.2 | [0.1,0.2,0.3] | 转向延迟（防瞬移转身穿帮） |
| ENEMY_ATTACK_RANGE | 80.0 | [70,80,100] | 攻击停距（= HITBOX_RANGE 对齐，停距=可命中） |
| ENEMY_ATTACK_COOLDOWN_SEC | 1.5 | [1.2,1.5,2.0] | 攻击节奏阀 |
| ENEMY_HP_DAMAGE | 15.0 | [10,15,20] | 敌人对玩家 HP 伤害（100/15≈7 刀击杀） |
| ENEMY_HP_MAX | 40.0 | [30,40,50] | 敌人生命（life_1_max 注入，sekiro 敌小兵 30-50） |
| ENEMY_THRUST_CHANCE | 0.3 | [0.2,0.3,0.5] | 突刺 vs 三连砍概率 |
| ENEMY_RETREAT_CHANCE | 0.05 | issue 指定 | 5% 后退回避（AC3） |
| ENEMY_RETREAT_SECONDS | 0.5 | [0.3,0.5,0.8] | 回避位移时长 |
| ENEMY_RETREAT_TRIGGER_RANGE | 200.0 | [150,200,250] | 玩家攻击前摇触发回避的距离 |
| ENEMY_PARRY_STUN_SECONDS | 0.5 | [0.4,0.5,0.6] | 弹反硬直抑制窗（AI 层补足 AC2） |
| ENEMY_LOSE_SIGHT_RANGE | 900.0 | 倍数 [1.3,1.5,2.0] | 追击丢失距离（= SENSE_RANGE × 1.5 派生） |
| ENEMY_PATROL_PAUSE_SEC | 1.0 | [0.5,1.0,1.5] | waypoint 到达停顿 |

## 7. 数据流

**Flow 1 正常路径（巡逻→发现→追击→攻击，AC1/AC5）：** Patrol 沿 waypoints ping-pong → 玩家进入感知（|dx|≤600 且夹角≤60° 且 |dy|≤150）→ Chase（facing 转向 + 逼近）→ |dx|≤80 且冷却就绪 → Attack 决策（randf()<0.3 突刺 heavy_attack，否则三连砍 attack）→ `entity.request_transition("attack")` → #577 自动登记 AttackWindow（windup=12、hp_damage=15、stance_damage=35）→ 命中帧 start+12 裁决受击 → 冷却 1.5s 循环。

**Flow 2 弹反路径（AC2）：** 敌人 attack 前摇 12 帧窗口 active → 玩家 guard_pressed 时间戳 ∈ [hit_ms-200ms, hit_ms] 且 facing 正确 → parry_ok（#577 既有逻辑零改动）→ 敌人 take_stance_damage(25) + EnemyAI 收到 parry_success → 抑制窗 0.5s（共享态 10 帧 + AI 补足）→ 第 4 次弹反 4×25=100=POSTURE_BREAK_THRESHOLD → stance_break 态 3.0s（#575 自然驱动，AI 决策门控不抢戏）→ #580 处决接管。

**Flow 3 5% 回避（AC3）：** 玩家 `request_transition("attack")` → player.state_changed → EnemyAI 掷骰（|dx|≤200 且 randf()<0.05）→ RetreatState 远离移动 0.5s → 期满按距离回 Attack（≤80）或 Chase；95% 未命中不打断当前行为。

**Flow 4 失败/边界：** waypoints 空数组 → Patrol 原地等待（push_warning 一次）；judge 未绑定 → 行为路径可测，攻击窗口不登记（push_warning 一次）；实体死亡 → _dead=true → AI 完全禁用（不再感知/移动/决策）；实体非 idle/move 态 → decide 门控直接返回。

## 8. 集成点（下游挂接约定）

| 集成 | 本组件 → 目标 | 方式 | Status |
|------|:---:|------|:---:|
| 敌人攻击窗口登记 | EnemyAI → CombatEntity(attack 态) → CombatJudge | state_changed 信号 + additive 参数化 | ✅ 已连接（#638） |
| 弹反硬直抑制窗 | EnemyAI 订阅 judge.parry_success | 信号订阅 → _parry_stun_until_sec | ✅ 已连接（#638） |
| 5% 回避触发 | EnemyAI 订阅 player.state_changed → attack/heavy_attack | 信号订阅 + RNG 掷骰 | ✅ 已连接（#638） |
| 打击反馈消费 | judge.hit_landed/parry_success/clash/block_held/stance_broken | 事件订阅（#577 已发射） | ⬜ 下游 #579 |
| 处决接管 | entity.stance_broken + stance_break 态 3s 窗口 | stance_broken 信号 | ⬜ 下游 #580 |
| 场景出生点/巡逻路径 | EnemyAI.waypoints @export | 场景配置数据 | ⬜ 下游 #583 |
| 场景组装 | EnemyAI + CombatEntity + StickFigureController | 节点组合（PRD §8.3） | ⬜ 下游 #585 |
| E2E 剧本 | e2e_shots.json 敌人巡逻/攻击截图 | 截图裁决 | ⬜ 下游 #586 |

## 9. 测试

文件：`shandong-wolf/tests/test_enemy_ai.gd`（36 用例，DESIGN §9 Scenario A-G 落地，run_tests.gd 注册第 10 套件）。纪律对齐 test_combat_judge.gd：headless 免树（直接 new + 手动 decide/tick，不依赖真实帧/物理/Input）、RNG 一律 set_rng_seed() 注入确定性、禁止 `:=` 类型推断（Godot 4.7.1 视推断警告为硬错误）、class_name 一律经 load() 访问、Time 系门控用成员赋值推进（不依赖真实时钟）。

| 场景 | 用例 | 覆盖 |
|------|:---:|------|
| A 主路径 | T1-T9 | 巡逻 ping-pong / 感知发现 / 追击停距 / 攻击发起 / 窗口 windup=12 / 三连砍 vs 突刺 / 冷却 / 5s 全路径 smoke / 前摇可弹反 |
| B 感知边界 | T10-T15 | 角度恰 60° 闭区间 / 距离恰 600 / 高度恰 150 / 身后不发现 / 丢失回巡逻 / 8 方位×3 距离×3 高度可复现性 |
| C 弹反硬直与崩解 | T16-T19 | 弹反扣 25 / 4 次弹反崩解（4×25=100 自洽）/ 抑制窗 0.5s / 崩解期不决策 |
| D 5% 回避 | T20-T24 | 触发 / 1000 次频率 ∈[0.03,0.07] / seed 确定性 / 95% 不打断 / 回扑分流 |
| E 常量驱动 | T25-T26 | 改常量值行为随动（零字面量）/ 非法值兜底 |
| F 边界失败路径 | T27-T34 | 空 waypoints / 单 waypoint / judge 未绑定 / entity 未绑定 / 死亡禁用 / stagger 门控 / 连段中断 / 回避后撤 |
| G 回归基线 | T35-T36 | additive 无回归（既有 25 判定用例全绿）/ 全量 10 套件 |

## 10. 验收条件映射（issue #581 body）

| AC | 保障 | 覆盖用例 |
|----|------|:-------:|
| AC1 巡逻→追击→攻击流转 + 前摇 12 帧可弹反 | AI 行为 FSM 三态 + ENEMY_ATTACK_WINDUP=12 + judge 自动登记（windup=12 窗口内弹反走 #577 闭区间） | T1-T9 |
| AC2 弹反硬直 0.5s + 25 架势 + 4 次崩解 | PARRY_STANCE_DAMAGE=25 只读消费 + AI 抑制窗补足 0.5s（共享态仅 0.167s） | T16-T19 |
| AC3 5% 概率后退闪避 | ENEMY_RETREAT_CHANCE=0.05 读 constants + seed 注入确定性 | T20-T24 |
| AC4 参数全从 constants.gd 读取 | AI 分区 18 常量全 # DRAFT，代码零字面量 | T25-T26 |
| AC5 smoke 5s 内完成全路径 | headless 模拟 300 帧断言 state_name == "attack" | T8 |

## 11. 明确不修改（与 PRD §8.5 红线对齐）

- ❌ 不改 11 态 CANONICAL_STATES / consume_state 契约（patrol/chase/retreat 是 AI 行为态，不进战斗状态表）
- ❌ 不引入 Area2D/CollisionShape2D 物理碰撞（#577 逻辑帧窗口架构）
- ❌ 不裁决 # DRAFT 数值（ENEMY_ATTACK_WINDUP 15→12 为已裁决例外，偏差记录交 #584）
- ❌ 不改 #577 五结果事件名与裁决顺序（additive 补丁必须保既有 25 判定用例全绿）
- ❌ 不改 debug_canvas.gd（#584 调参面板域）、scenes/Main.tscn（标题场景红线）、mini-pong/ 任何文件
- ❌ 不做场景组装与渲染（#583/#585 职责）；敌人视觉复用 SW-003，AI 层零渲染代码

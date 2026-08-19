# 拼刀 / 弹反 / 架势崩解判定系统 — CombatJudge + AttackWindow 判定层（#577/#626）

> 落盘依据：PR #626（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/577-parry-clash-stance-break.md`。
> 上游：#575 CombatEntity 接口与 11 态状态机（08/09 章）、#573 guard_pressed 输入时间戳契约（06 章）、#574 零碰撞体架构裁决（07 章）、#584 数值 DRAFT 纪律（02 章）。
> 本层是 #579 反馈 / #580 处决 / #581 敌AI / #593 音效的**唯一事件输入面**——五结果事件契约在此定型，后续 issue 只许订阅不许改名。

## 1. 设计意图

**问题本质是「判定原料全部就绪，裁决者零存在」。** 经 #573/#574/#575/#584，判定所需的一切都已就位：
InputController.guard_pressed(timestamp_ms) 输入时间戳契约、CombatEntity 的 take_damage/take_stance_damage/
break_stance 接口与 6 信号、combat_state_table guard→parry_success 转移入口、WolfConstants 只狼基准常量、
StickFigureController.consume_state parry_success 动画消费位、sword_arc 注释明言「零碰撞体、判定归 #577」。
但 gdscripts/ 无任何攻击帧窗口描述器、无命中裁决执行者、无五结果事件发射器——**本层交付 = 判定层**。

设计哲学四条（DESIGN 定稿，implement 逐字落实）：
1. **判定器 = 事件协调器（不是实体）**：CombatJudge 是独立 Node（非 CombatEntity 子类），订阅双方实体
   state_changed + 输入 guard_pressed/guard_held → 按优先级裁决 → 调用实体接口 → 发射结果事件。实体层（#575）
   与判定层解耦，判定规则可 headless 免树直接单测。
2. **窗口 = 帧区间（不是空间体）**：攻击命中窗口 = `[FRAME_ATTACK_WINDUP, FRAME_ATTACK_WINDUP + HITBOX_ACTIVE_FRAMES]`
   （逻辑帧计数 @60fps）；弹反窗口 = guard_pressed 时间戳 ∈ `[敌人 hit 帧 - PARRY_WINDOW_SECONDS, 敌人 hit 帧]`
   （闭区间，只狼基准）。空间真实性 = 命中瞬间距离 + facing 校验（横板一维）——**不引入任何 Area2D/CollisionShape2D**
   （#574 零碰撞体红线；弹反是时间窗，物理碰撞无法表达）。
3. **优先级 = 显式常量（不是代码顺序）**：`CLASH_PRIORITY`（0=弹反优先，默认）——裁决顺序 弹反 > 拼刀 > 格挡 > 受击，
   全部走常量可调，实现期禁止写死。
4. **事件 = 契约（不是内部细节）**：五个结果事件是 #579/#574/#593/#580 的唯一输入面，事件名与 issue body
   逐字对齐，禁止改名；stance_broken 由 #575 发射 → 本层幂等转发（统一「判定结果从判定器出」）。

## 2. 架构决策

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|---------------|---------|---------|
| 判定架构 | 独立 CombatJudge 判定器（Node，非实体） | 内嵌 CombatEntity / 信号链分散 | #575 既定分层「实体不做判定」逐字一致；优先级裁决需全局视图 |
| Hitbox/Parry-box 表示 | 逻辑帧窗口 + 距离/facing 校验 | Area2D 物理碰撞 | #574 sword_arc「零碰撞体、判定归 #577」裁决；弹反时间窗无法用物理表达 |
| 弹反窗口检测 | guard_pressed 时间戳对齐 | 状态位轮询 | 无法区分按下时机与持续按住 |
| 拼刀优先级 | CLASH_PRIORITY 显式常量（弹反>拼刀>格挡>受击） | 代码顺序隐式 | 用户可裁决，改常量+冲突矩阵断言翻转 |
| 事件契约 | 判定器统一发射五事件（parry_success/block_held/hit_landed/clash/stance_broken） | 各层自发事件 | 统一事件出口，下游单点订阅 |
| stance_break 消费 | 转发 #575 信号（幂等） | 判定器重发 | 统一事件出口 + 防双发 |

## 3. 判定器职责边界（CombatJudge）

文件：`shandong-wolf/gdscripts/combat_judge.gd`（class_name `CombatJudge` extends Node，**非 autoload**——
#585 组装时实例化进场景；测试直接 new + 手动 tick_frame）。

**单一职责：** 攻击窗口登记 → 命中裁决（弹反→拼刀→格挡→受击）→ 调用实体接口 → 发射五结果事件。
不做渲染/演出/音效（#579/#593）、不做状态机/数据存储（#575）、不做输入采集（#573）。

**事件契约（信号，与 issue body 逐字对齐，禁止改名）：**

```gdscript
signal parry_success(defender: CombatEntity, attacker: CombatEntity, stance_damage: float)
signal block_held(defender: CombatEntity, attacker: CombatEntity, stance_cost: float)
signal hit_landed(defender: CombatEntity, attacker: CombatEntity, hp_damage: float, stance_damage: float)
signal clash(entity_a: CombatEntity, entity_b: CombatEntity, stance_cost: float)
signal stance_broken(entity: CombatEntity)   # 转发 #575 信号（统一事件出口）
```

**关键接口：**

```gdscript
func bind_entities(p: CombatEntity, e: CombatEntity) -> void   # 订阅双方 state_changed / stance_broken
func bind_input(ic: Object) -> void                             # 订阅 guard_pressed(ts) / guard_held
func register_attack_window(w: AttackWindow) -> void            # 登记窗口；同 attacker 旧窗口作废（连段覆盖语义）
func resolve_attack(attacker: CombatEntity, defender: CombatEntity) -> void  # 幂等裁决入口
func tick_frame() -> void                                       # headless 测试手动推进（免 SceneTree 帧循环）
```

**实现偏离说明（#626 实测记录，语义等价）：** Godot 4.7.1 信号 `.bind` 参数追加到信号参数之后——
`_on_entity_state_changed` 实际签名 `(_from, to, entity)`；`_on_stance_broken` 连接不带 `.bind(entity)`
（1 参 handler + bind 会报 "Method expected 1 argument(s)" 且永不执行）。后续 issue 订阅本层信号时按上述
**五事件签名**接线，勿照抄 handler 连接细节。

## 4. AttackWindow 描述器

文件：`shandong-wolf/gdscripts/combat_attack_window.gd`（class_name `AttackWindow` extends RefCounted——
纯数据描述器，无节点、无逻辑分支，headless 免树 new）。#581 敌AI 与玩家攻击共用的窗口契约。

```gdscript
class_name AttackWindow
extends RefCounted

var attacker: CombatEntity   # 攻击者引用（判定器据此路由 take_damage/take_stance_damage）
var start_frame: int         # 攻击开始帧（进入 attack/heavy_attack 状态帧）
var active_frames: int       # 判定有效帧数（HITBOX_ACTIVE_FRAMES # DRAFT）
var hp_damage: float         # 命中 HP 伤害（玩家 SWORD_DAMAGE_LIGHT/HEAVY；敌人 #581 配置）
var stance_damage: float     # 命中架势伤害（POSTURE_HIT_COST # DRAFT）
var direction: int           # 攻击方向（-1/1 = 攻击者 facing 快照）

func hit_frame() -> int            # = start_frame + FRAME_ATTACK_WINDUP
func is_active(frame: int) -> bool  # frame ∈ [hit_frame, hit_frame + active_frames]（闭区间含端点）
func is_expired(frame: int) -> bool # frame > hit_frame + active_frames（判定器据此清理）
```

玩家攻击窗口由 CombatJudge 在 `state_changed → attack/heavy_attack` 时**自动构造**（hp_damage 取
SWORD_DAMAGE_LIGHT/HEAVY，direction 取 entity.facing 快照）；敌人窗口 MVP 由测试构造驱动（#581 实现后
在攻击前摇期间构造登记）。

## 5. 裁决顺序与防重入

`resolve_attack` 按 **CLASH_PRIORITY 常量**驱动的固定顺序裁决（零字面量红线，改常量冲突矩阵断言翻转）：

| 顺序 | 路径 | 触发条件 | 执行 | 事件 |
|:---:|------|---------|------|------|
| 1 | 弹反 | guard_pressed ts ∈ 弹反窗（闭区间）+ facing 校验通过 | 玩家 0 伤害 + enemy.take_stance_damage(PARRY_STANCE_DAMAGE) + player.request_transition("parry_success") | `parry_success` |
| 2 | 拼刀 | 弹反短路后，双方窗口同帧 active（重叠） | 双方 take_stance_damage(CLASH_STANCE_COST) | `clash` |
| 3 | 格挡 | defender.state_name == "guard"（含弹反失败后的持续格挡） | take_stance_damage(POSTURE_BLOCK_COST) 不扣血 | `block_held` |
| 4 | 受击 | 兜底 | take_damage(hp) + take_stance_damage(stance) | `hit_landed` |

**防重入/防双罚：** `_resolved` 字典键 `"attacker:defender:frame"`——同一命中恰好裁决一次；stance_broken
转发用 `_forwarded_stance_break` 幂等标记（#575 侧 break_stance 本身幂等 + 本层转发幂等 = 双保险）。
弹反路径 PARRY_COST（弹反扣自身架势）MVP **不施加**（# DRAFT 候补，施加时机归 #584 定稿后 #585 组装裁决）。

## 6. 判定分区常量（#577/#626 追加）

追加式新增「判定」分区（置「受击/敌人/处决」分区之后），全部 `# DRAFT` 只读，定稿归 #584；消费方：
combat_judge.gd / combat_attack_window.gd。注释含只狼基准 + 候选集 + 影响 + 情感断言（#572 规范）。

| 常量 | 候补值 | 候选集 | 说明 | 消费方 |
|------|--------|--------|------|--------|
| `PARRY_STANCE_DAMAGE` | `25.0` | [20, 25, 30] | 弹反成功大幅涨敌架势（AC1 硬约束 ≥20；默认 25 = 区间中位） | CombatJudge 弹反路径 |
| `CLASH_STANCE_COST` | `10.0` | [8, 10, 12] | 拼刀双方各扣小架势（互格=节奏博弈，代价低于受击） | CombatJudge 拼刀路径 |
| `CLASH_PRIORITY` | `0` | [0=弹反优先, 1=拼刀优先] | 同帧三重叠裁决结果开关——手感基调决定性常量 | resolve_attack 顺序 |
| `HITBOX_ACTIVE_FRAMES` | `4` | [4, 6, 8] | 攻击暴发判定持续帧（与 #574 挥刀暴发帧对齐）；越长命中越宽容、弹反/拼刀窗口随之变宽 | AttackWindow.is_active |
| `HITBOX_RANGE` | `80.0` | [60, 80, 100] | 横板一维命中距离阈值 px（SWORD_LENGTH=88 派生近似）；距离外挥空=不发射事件 | resolve_attack 距离校验 |
| `PARRY_DIRECTION_TOLERANCE` | `1` | [1=仅同侧, 2=宽容] | 弹反必须面向攻击（背对挨打=受击） | resolve_attack facing 校验 |

## 7. 数据流（六条 Flow 一览）

1. **弹反成功**：敌人 attack → 自动登记窗口 → 玩家 guard_pressed(ts) 记录 → hit 帧到达 → ts ∈ 弹反窗 →
   0 伤害 + 敌架势大涨 + request_transition("parry_success") → emit parry_success（→ #579 四要素 / #593 ding）。
2. **拼刀**：双方窗口同帧 active → 弹反短路后查重叠 → 双方扣 CLASH_STANCE_COST → emit clash。
3. **格挡**：guard_pressed 超窗 / 长按 → defender.state_name=="guard" → 扣 POSTURE_BLOCK_COST 不扣血 → emit block_held。
4. **受击**：兜底 → take_damage + take_stance_damage（→ 硬直/死亡/崩解均由 #575 处理）→ emit hit_landed。
5. **架势崩解转发**：任意实体 stance ≤ 0 → #575 break_stance（幂等）→ stance_broken → 本层幂等转发 → emit
   stance_broken（→ #580 处决通道 / #579 全屏闪）。
6. **防重入**：同帧二次 resolve → `_resolved` 键已存在 → no-op；窗口 is_expired → 清理移除。

## 8. 边界与错误处理（关键项）

| 边界情况 | 缓解措施 |
|---------|---------|
| 弹反窗口闭区间 | ts 恰在 hit_ms 或 hit_ms - PARRY_WINDOW_SECONDS*1000 → 窗口内；窗口外 1ms → 不弹反 |
| 弹反失败后持续格挡 | guard 态仍成立 → 走 block_held 不重复受击（_resolved 防双罚，恰好一次事件） |
| 无敌期/死亡/复活/处决态受击 | 判定器跳过该实体（#575 侧 no-op 兜底 + 判定器守卫双保险） |
| 距离挥空 / facing 相反 | abs(x 差) > HITBOX_RANGE 或 facing 相反 → 不命中（窗口正常过期） |
| 同 attacker 双窗口（连段） | register_attack_window 覆盖语义：新窗口作废旧窗口；MVP 单段由 hit 帧一次性裁决 |
| 未注册窗口收到命中 / 未 bind 实体 | no-op + push_warning（不凭空判定，防 NPE） |
| 同帧多次 guard_pressed | 帧级去抖：取最后一次按下时间戳 |
| 事件重复发射 | _resolved 防重入键 + stance_broken 转发幂等——每次命中恰好一次事件 |

## 9. 集成点（下游挂接）

| 集成 | 本层组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| 判定输入 | _on_guard_pressed/_on_guard_held | #573 InputController（已合并） | bind_input 订阅 guard_pressed(ts)/guard_held | ⬜ 待接线（#585 组装） |
| 实体数据 | CombatJudge → CombatEntity 接口 | #575（已合并） | bind_entities + take_damage/take_stance_damage/request_transition + state_changed/stance_broken 订阅 | ✅ 本层实现内完成 |
| 弹反动画 | request_transition("parry_success") → consume_state | #574（已合并） | 经 #575 状态转移间接消费（anim_parry_success） | ✅ 契约对齐 |
| 反馈消费 | 五结果事件 | #579 反馈（未开始） | 订阅五事件 → 反馈矩阵（火花/hit-stop/屏震） | ⬜ 事件契约已定，订阅待 #579 |
| 音效消费 | parry_success ding / clash 金属声 | #593 音效（未开始） | 经 #579 反馈事件联动 | ⬜ 待 #593 |
| 处决通道 | stance_broken 转发事件 | #580 处决（未开始） | 订阅 stance_broken → 处决驱动 | ⬜ 待 #580 |
| 敌AI 窗口 | register_attack_window(AttackWindow) | #581 敌AI（未开始） | #581 攻击前摇期间构造窗口登记；MVP 测试构造驱动 | ⬜ 契约已定，实现待 #581 |
| 组装 | CombatJudge 实例化 + bind_entities ×2 + bind_input | #585 组装（未开始） | 场景实例化 + 信号桥接 | ⬜ 待 #585 |

## 10. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #577 | 拼刀/弹反/架势崩解判定系统（本文件所属；判定层 = 五结果事件唯一发射方） | 已合并（#626） |
| #575 | 战斗实体基类与状态机（判定器消费接口与信号的上游） | 已合并（#618） |
| #573 | 输入映射与玩家控制器（guard_pressed 时间戳契约） | 已合并（#611） |
| #574 | 火柴人动画（零碰撞体裁决 + parry_success 动画消费位） | 已合并（#612） |
| #584 | 数值 DRAFT 集中表（判定 6 常量定稿唯一通道，调参面板） | 草稿已合并（#609），待用户定稿 |
| #579/#580/#581/#585 | 反馈/处决/敌AI/组装（本层下游消费方） | 待实现 |

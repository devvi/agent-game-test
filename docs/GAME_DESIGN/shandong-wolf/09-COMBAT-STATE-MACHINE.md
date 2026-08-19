# 11 态战斗状态机 — 转移合法性表 + 状态对象 + 时序常量（#575/#618）

> 落盘依据：PR #618（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/575-combat-entity-state-machine.md` §2.1-§2.3。
> 上游：#572 StateMachineBase（03-STATE-MACHINE.md）三接口派生；#574 ANIM_CLIP_NAMES 键集（状态名契约对齐）。
> 本层与 08-COMBAT-ENTITY.md 同属 #575：实体层持有 FSM 与数据，本层提供转移拓扑与状态行为。

## 1. 设计意图

战斗状态流转是拼刀循环（受击硬直 / 格挡 / 架势崩解 / 复活）的地基。状态机必须回答两个问题：
**「什么转移合法」（拓扑合法性）与「什么条件下合法」（条件合法性）**。若放任各处直接改状态，
状态名与转移规则将随实现漂移——#574 动画契约、#577 判定、#580 处决全部依赖稳定的 canonical 状态集。

本层三组件各司其职：
1. **combat_state_table.gd**（CombatStateTable）——11 态转移拓扑表 + `is_legal(from, to)` 静态查询，纯数据无逻辑；
2. **combat_states.gd**（CombatStateBase + 11 状态对象 + make_state 工厂）——派生 StateMachineBase，帧/秒常量驱动自动退出；
3. **constants.gd「战斗时序」分区**——5 个时序常量（# DRAFT 候补值，定稿归 #584），定时状态自动退出的唯一时间源。

## 2. 架构决策

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|---------------|---------|---------|
| 状态机基类 | 派生 StateMachineBase（state_machine.gd，三接口 + 同态/防重入守卫） | LimboAI addon / enum+match | #572 已裁决：40 行自研满足，不引第三方 |
| 转移合法性 | 数据驱动转移表（拓扑）+ request_transition 守卫（条件）两层 | 各处散落 if 判断 | 状态不漂移（AC2 核心）；查表可单测遍历 121 对 |
| 状态对象写法 | RefCounted 内部类 + make_state 工厂（与 stick_figure_anim_states.gd 同构） | 单文件 match 大函数 | 每态独立 enter/exit/update，可测可扩展 |
| 自动退出 | 定时状态在 update() 内帧/秒计数 → request_transition("idle") | enter() 内发起转移 | 防重入红线（StateMachineBase 锁拦截） |

## 3. 转移合法性表（combat_state_table.gd）

文件：`shandong-wolf/gdscripts/combat_state_table.gd`（class_name `CombatStateTable`，extends RefCounted，静态工具）。

```gdscript
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
- `dead → 除 revive 外全部表外 = reject`（状态机停摆）
- `guard → stance_break` 表内（格挡中崩解 = 失衡，优先级高于格挡姿态）
- `guard → parry_success` 表内（#577 弹反成功驱动入口）
- `attack → attack` 表内（连段拓扑合法；条件合法性 = AttackState.restart 钩子，仅收招 phase 重置帧计数）
- 同态转移（from == to）除 attack 外：表内无自环，request_transition 层由 StateMachineBase 同态守卫静默忽略

## 4. 状态对象设计（combat_states.gd）

文件：`shandong-wolf/gdscripts/combat_states.gd`——顶层 `CombatStateBase`（extends RefCounted，持有 entity 引用 +
`_elapsed` 计时 + enter/exit/update 三接口 + 可选 `restart()` 钩子）+ 11 个内部类 + `make_state(state_name, entity)` 工厂
（未知状态名回落 idle）。**退出统一在 update() 内调 `entity.request_transition("idle")`，禁止在 enter() 内发起转移**（防重入红线）。

| 状态对象 | 进入动作 | update 行为 | 自动退出 |
|---------|---------|------------|---------|
| `CombatStateIdle` | 无 | 无（等待外部转移） | 不自动退出 |
| `CombatStateMove` | 无 | 无（位移由 PlayerController 负责，本层只占状态名） | 不自动退出（轴归零 → idle 由输入桥驱动） |
| `CombatStateAttack` | 重置 phase=0（前摇） | 帧计数：`frame = int(_elapsed * FRAME_RHYTHM_BASE)`；phase 0 前摇（<8 帧）/ 1 暴发（8..12）/ 2 收招（>12）；累计 ≥ WINDUP(8)+RECOVERY(14)=22 帧 → idle | `request_transition("idle")`；`restart()`：**仅 phase==2 时**重置 `_elapsed=0` 回前摇 = 连段成立，phase 0/1 忽略 |
| `CombatStateHeavyAttack` | 无 | 帧计数累计 ≥ 22 帧（复用 FRAME_ATTACK_WINDUP+RECOVERY，无 heavy 专属常量）→ idle | 同左 |
| `CombatStateGuard` | 无 | 无（持续姿态；架势回复/扣减归 #577 经 take_stance_damage 驱动） | 不自动退出（guard 释放 → idle 由桥驱动） |
| `CombatStateParrySuccess` | 无 | 帧计数累计 ≥ PARRY_SUCCESS_FRAMES(10) → idle | 同左（#577 若需延长反击窗口，调参面板改常量） |
| `CombatStateStagger` | 无 | 帧计数累计 ≥ STAGGER_FRAMES(12) → idle | 同左 |
| `CombatStateStanceBreak` | 无 | 秒累计 ≥ STANCE_BREAK_RECOVERY_SEC(3.0) → idle | 同左（期间 #580 可经 request_transition("execute") 抢先） |
| `CombatStateExecute` | 无 | 帧计数累计 ≥ FRAME_ANIM_EXECUTE_TOTAL(5) → idle | 同左（执行中无敌） |
| `CombatStateRevive` | 无 | 秒累计 ≥ REVIVE_SECONDS(1.0) → idle | 同左（hp_2 初始化/无敌开启在 entity.revive() 完成） |
| `CombatStateDead` | 无 | 无（状态机停摆） | 不自动退出（仅 revive() 驱动 dead→revive） |

## 5. 战斗时序常量（constants.gd 追加「战斗时序」# DRAFT 分区）

> 追加式新增分区（#618），不触碰既有 8 分区；全部 `# DRAFT` 只读，定稿归 #584（调参面板）。
> 注释遵循 #572 规范：候补值 + 影响什么 + 情感断言。

| 常量 | 候补值 | 影响 | 情感断言 | 消费方 |
|------|--------|------|---------|--------|
| `STAGGER_FRAMES` | 12（候选 [8,12,16]） | 受击硬直时长——太短无受击感，太长卡操作 | 硬直是「被打断」的代价，不是「罚站」 | StaggerState |
| `PARRY_SUCCESS_FRAMES` | 10（候选 [8,10,12]） | 弹反成功瞬间帧（硬直窗口，#577 驱动进入） | 弹反成功必须比格挡爽（只狼铁律 1） | ParrySuccessState |
| `STANCE_BREAK_RECOVERY_SEC` | 3.0（#580 同值互引） | 崩解后敌人起身恢复时间 | 崩解 = 可从容处决的窗口（只狼铁律 2） | StanceBreakState |
| `REVIVE_SECONDS` | 1.0（#578 同值互引） | 倒地→复活的演出时长 | 「还没打完这一仗」，不是神迹 | ReviveState |
| `INVINCIBLE_SECONDS` | 1.0（#578 同值互引） | 复活后无敌时长 | 硬汉的第二次机会，不是耍赖 | CombatEntity（无敌期计时） |

## 6. 数据流（核心路径）

**Flow 1 输入 → 状态转移：** `InputController.attack_pressed → 输入桥 → request_transition("attack")`
→ 守卫① 非终态 → 守卫② 非 dead → is_legal("idle","attack")=true → `fsm.transition_to(CombatStateAttack)`
→ state_name="attack" + emit state_changed → #574 consume_state("attack") 播 anim_attack
→ AttackState 帧计数 8(前摇)+4(暴发)+10(收招) = 22 帧后回 idle。

**Flow 2 受击 → stagger：** `take_damage(12, attacker)` → 兜底检查 ✓ → hp_1 扣减 + emit hp_changed
→ 状态 ∈ {idle,move,attack,heavy_attack} → 进 stagger → 12 帧后回 idle（guard 中受击不硬直，保持格挡姿态）。

**Flow 3 架势崩解 → 处决通道：** `take_stance_damage × N` → stance ≤ 0 → `break_stance()`（幂等）
→ emit stance_broken → 进 stance_break（3.0s）→ #580 可 request_transition("execute")（5 帧）抢先，或自然回 idle。

**Flow 4 非法转移拒绝：** stance_break 中 request_transition("attack") → is_legal=false → push_warning + 返回 false + 状态不漂移。

## 7. 测试覆盖（test_combat_entity.gd，30 用例）

- **Scenario B（转移合法性）**：121 对 (from,to) 遍历断言 is_legal 与表 100% 一致；红线案例（stance_break 禁攻/格挡、dead 停摆）；同态静默忽略；attack 连段 restart 钩子（收招 phase 重置、前摇 phase 忽略）
- **Scenario C/D/E（三主路径）**：受击掉血 + stagger 自动退出 + guard 不硬直 + 无敌期 0 伤害 + clamp；架势扣减/崩解幂等/guard 中崩解/stance_break 恢复；两段血死亡→复活→终态序列 `idle→dead→revive→idle→dead` + life_total=1 直接终态 + 终态误复活守卫
- **Scenario F（契约对齐）**：#574 ANIM_CLIP_NAMES 键集 == CANONICAL_STATES 逐名相等（11/11，防状态名漂移红线）；输入桥 mock（5 信号 + guard 释放 + 轴轮询 facing 同步）；全量回归 7 套件全绿

## 8. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #572 | StateMachineBase（本层派生基类） | 已合并（#599） |
| #575 | 战斗实体基类与状态机（本文件所属） | 已合并（#618） |
| #574 | 动画消费契约（ANIM_CLIP_NAMES 键集对齐） | 已合并（#612） |
| #577/#578/#580 | 判定/复活/处决（本层状态驱动方） | 待实现 |
| #584 | 时序常量定稿（调参面板） | 草稿已合并（#609），待用户定稿 |


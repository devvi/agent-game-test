# Boss级 AI 战斗交互升级 — 霸体 + 自动面向 + 停距/击退 + 防御行为 + 差异化前摇/弹反（#720/#730）

> 落盘依据：PR #730（implement，squash-merge 2026-08-21, commit af72d3b）← DESIGN `docs/DESIGN/720-combat-interaction-interrupt-hit.md`（plan #726 已 merge）← PRD `docs/PRD/720-combat-interaction-interrupt-hit.md`（research #722 已 merge）。
> 增量：把敌人从「能被普攻无限打断的弱 AI」升级为「只狼 Boss 级」——**霸体让蓄力期不可被普攻打断、自动面向消除站桩挥空、停距/击退缩短让连段可续、防御行为（格挡）让玩家需要破防策略、差异化前摇/弹反窗口/弹反回报奖励「读招」**。数值全部 # DRAFT + 候选集归 #584 用户裁决。
> 上游：#575/#618 CombatEntity 数据模型与 11 态战斗状态机（08/09 章）、#577/#626 CombatJudge 判定层五事件 + AttackWindow 窗口契约（11 章）、#581/#638/#703 EnemyAI 四态行为 FSM + 运行时驱动链（13 章）、#682/#695 精英 Boss AI 参数档位 + 蓄力重斩 + 击退 + 架势恢复（19 章）、#718/#727 stagger→stance_break 崩解拓扑补齐（09 章，本设计零改转移表）。
> 所有权：`content_ownership: mechanical` —— 霸体/自动面向/停距/击退/弹反窗口/弹反回报 = 机械判定与数值工程，headless 可自动验证；**差异化前摇的视觉信号（举刀姿态/刀光节奏）含 taste 成分**，骨架由本设计定、表现细节归 implement 视觉层 + #584 用户裁决。

## 1. 设计意图

**问题本质是「敌人无法构成有效博弈对手」——AI 太弱智 + 玩家攻击太强两个方向同时失衡，导致弹反/格挡/架势/处决全系统没有值得测的对手。** 用户 2026-08-21 实机反馈：敌人蓄力被玩家每击打断 → 永远出不了招（无霸体）；击退后追不回来（无压迫）；玩家架势伤害 35×3=105>100 → 3 击崩解秒杀（无双轨博弈）。用户拍板：**大幅增强敌人 AI 至只狼 Boss 级——这是 MVP 可测性的前提**。

**设计哲学：一切增量走「数据驱动 + 既有路径复用」，判定层逻辑零分支爆炸，不碰 #718 拓扑红线。** 霸体在实体层（take_damage）拦截 stagger 打断、弹反路径天然绕过；弹反差异化挂在 AttackWindow（数据字段）而非 judge 分支；防御行为复用 11 态 guard 态（零新增战斗状态名）；自动面向在攻击入口一次性修正（不追踪）。

1. **霸体（抗打断）——蓄力期不可被普攻打断**：敌人处于 attack/heavy_attack 且仍在 windup 期时，`take_damage` 扣血/扣架势但**不转 stagger、不打断动作**；windup 结束（暴发/收招期）恢复可打断。弹反路径（`_resolve_parry` → `request_transition("parry_success")`）不经过 take_damage → **弹反照常打断霸体**（PRD §5.2-1 硬边界）。
2. **自动面向——消除站桩挥空**：玩家 `_on_bridge_attack_pressed`/`_on_bridge_heavy_attack_pressed` 时若有 `_auto_face_target` 且 `|dx| > 0` → 一次翻转 `facing = sign(dx)`，再发起攻击。攻击全程 facing 锁定（窗口 direction 快照语义不变，#577）。
3. **停距/击退/架势数值平衡——连段可续 + 只狼双轨节奏**：`ENEMY_ATTACK_RANGE` 80→65（停距 < HITBOX_RANGE=80 → 10-20px 缓冲）、`ENEMY_KNOCKBACK_PX` 40→22（单次击退后 |dx|≈87 略出范围、玩家前移 10-20px 续连段、Chase 无冷却回扑兜底）、`POSTURE_HIT_COST` 35→18（5.6 击 → 6 击崩解，5-7 击区间）。
4. **防御行为（格挡）——新增 GuardState，复用 guard 态**：玩家进入 attack/heavy_attack 前摇 → 敌人 idle/move 且 `|dx| ≤ HITBOX_RANGE` → 掷骰 `randf() < ENEMY_BLOCK_CHANCE(0.4)` → 行为 FSM 转移 GuardState → `entity.request_transition("guard")` → 玩家命中走 judge 既有 `defender.state_name == "guard"` → `block_held`（扣 POSTURE_BLOCK_COST=10）。连续攻击被格挡 → 敌人架势持续扣减 → 破防策略成立（换弹反/蓄力重击/持续压制）。
5. **差异化前摇 + 视觉信号——三级可读梯度（读招回报）**：combo 短前摇（fallback 12 帧，需预判/反应弹反）、thrust 中前摇（`ENEMY_THRUST_WINDUP=16` 新增，身体前倾/刀尖朝向信号）、charge 长前摇（`ENEMY_CHARGE_WINDUP` 20→24，举刀蓄力姿态信号）。具体姿态数值归 implement 视觉层 + #584，本设计只定「三级前摇必须三级可读信号」的约束。
6. **弹反窗口/回报差异化——奖励读招**：普攻标准窗口 0.2s/回报 35、突刺中窗 0.25s/回报 45、蓄力宽窗 0.3s/回报 55——长前摇 + 宽判定 + 高回报 = 读招回报。
7. **血线阶段（P2 可选）**：`ENEMY_ENRAGE_HP_RATIO=0.5`，HP ≤ 50% 触发强化（冷却 ×0.6 + charge 概率 ×1.5 候选）——本期不阻塞 MVP。

**方案裁决**：PRD §4 **方案 A × 4 全部确认采纳**（霸体=蓄力期霸体 / 自动面向=攻击瞬间转向 / 停距=60-70px / 击退=20-25px）；issue body 2026-08-21 用户追加要素（防御行为、差异化前摇+视觉信号、弹反窗口差异化、弹反回报差异化、数值平衡 35→15-20、血线阶段=可选 P2）全部纳入。

## 2. 架构决策

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|--------------|---------|---------|
| 霸体落点 | `combat_entity.take_damage` windup 分支（`_is_armored()` 拦截 stagger） | 改 judge 打断裁决 | 弹反路径天然绕过 take_damage → 蓄力期弹反 100% 保留（PRD §5.2-1 硬边界） |
| 自动面向 | 攻击入口一次性修正 facing（`_face_nearest_target()`） | 全程追踪朝向（方案 B） | 破坏 direction 快照 + 视觉违和（PRD §4.2 否决理由采纳） |
| 弹反差异化载体 | `AttackWindow` 新增 2 字段（数据驱动，judge 读字段 fallback） | judge 按招式分支 | 逻辑零分支爆炸；字段 -1 → 回退既有常量 → 既有测试零破坏 |
| 防御行为 | 复用 11 态 guard 态 + 行为 FSM 新增 GuardState | 新增战斗状态名 | 零触碰 combat_state_table.gd 拓扑红线（#718 边界）；guard 进出转移表已完备 |
| 数值平衡 | 用户拍板值 + 候选集（默认取区间中位）标 # DRAFT | 偷定单一值 | 定稿归 #584（status/human-review 并行）；候选集登记供调参面板 |
| 击退缩短 | 位移层击退 40→22 + 停距 65 | 改判定范围 | 单次击退后仍 ≤ 判定边界，连段可续 |

## 3. 霸体（抗打断）—— `combat_entity.gd`

- **文件:** `shandong-wolf/gdscripts/combat_entity.gd`
- **机制:** 敌人处于 attack/heavy_attack 且**仍在 windup 期**时，`take_damage` 扣血/扣架势但**不转 stagger、不打断动作**；windup 结束（暴发/收招期）恢复可打断。
- **windup 期判定:** 进入 attack/heavy_attack 态时记录 `_windup_frames`（读自身 override `current_windup_frames`，fallback 读 `C.ENEMY_ATTACK_WINDUP`；heavy_attack 且无 override = thrust，读 `C.ENEMY_THRUST_WINDUP`）；用 `_state_elapsed_frames`（新增，_process 按 FRAME_RHYTHM_BASE 累计）与 windup_frames 比较。
- **状态属性:**
  - `var _state_elapsed_frames: int = 0`（进入任意态重置；_process 每帧 +1——仅敌人变体需要精确计时）
  - `var _windup_frames: int = 0`（进入 attack/heavy_attack 时按招式设置）

```gdscript
func _is_armored() -> bool:
    ## 霸体条件: 敌人 + attack/heavy_attack 态 + 仍在 windup 期内
    if is_player: return false
    if state_name != "attack" and state_name != "heavy_attack": return false
    return _state_elapsed_frames < _windup_frames

func take_damage(amount, source = null) -> void:
    # ...（既有 dead/revive/execute + 无敌 + 非法值守卫原样保留）...
    emit_signal("hp_changed", ...)
    if (_active_life == 1 and hp_1 <= 0.0) or (_active_life == 2 and hp_2 <= 0.0):
        die()
        return
    if _is_armored():
        return   # ★ 霸体: 扣血已发生（hp_changed 已广播），但不转 stagger、不打断蓄力
    if state_name in ["idle", "move", "attack", "heavy_attack"]:
        request_transition("stagger")
```

- **state_changed 挂钩:** `_on_state_entered`（request_transition 成功后）重置 `_state_elapsed_frames = 0`；attack/heavy_attack 时设置 `_windup_frames`。
- **弹反路径不受影响:** judge `_resolve_parry` → `request_transition("parry_success")` 不经过 take_damage → 蓄力期弹反照常打断（PRD §5.2-1 边界 1）。
- **边界:** 蓄力期被崩解（stance 归零）→ `break_stance()` 也不经 take_damage → 崩解天然打断霸体（#718 修复前有 warning，known limitation）。

## 4. 玩家攻击自动面向 — `combat_entity.gd`

- **文件:** `shandong-wolf/gdscripts/combat_entity.gd`
- **机制:** 玩家 `_on_bridge_attack_pressed` / `_on_bridge_heavy_attack_pressed` 时，若存在 `_auto_face_target`（敌人引用，main_battle 注入）且 `|dx| > 0` → 一次翻转 `facing = sign(dx)`，再 `request_transition("attack"/"heavy_attack")`。攻击全程 facing 锁定（窗口 direction 快照语义不变）。
- **状态属性:** `var _auto_face_target: Node2D = null`（main_battle 装配注入 player_entity._auto_face_target = enemy_entity；headless 测试手动设）

```gdscript
func _face_nearest_target() -> void:
    if _auto_face_target == null: return
    var dx: float = _auto_face_target.position.x - position.x
    if dx == 0.0: return
    facing = 1 if dx > 0.0 else -1

func _on_bridge_attack_pressed() -> void:
    _face_nearest_target()          # ★ 攻击瞬间自动转向
    request_transition("attack")
```

- **优先级语义（PRD §5.2-2）:** 攻击转向优先于移动 facing；攻击结束后 facing 保持攻击方向——`_bridge_poll` 在非 idle/move 态不更新 facing（既有行为已满足）。
- **边界:** 场上无敌人（target null / 敌人死亡）→ no-op 保持原 facing（PRD §5.2-3）；玩家 heavy_attack 同规则。
- **Integration:** `main_battle.gd` 装配处新增一行注入（§7）。

## 5. 停距/击退/架势数值 + 新常量 — `constants.gd`

- **文件:** `shandong-wolf/gdscripts/constants.gd`
- **变更（全部标 # DRAFT + 候选集，用户拍板值 = 默认）:**

| 常量 | 现值 | 新默认 | 候选集 | 依据 |
|------|:---:|:---:|------|------|
| `ENEMY_ATTACK_RANGE` | 80.0 | **65.0** | [60, 65, 70] | PRD §4.3 方案 A——停距 < HITBOX_RANGE=80 → 10-20px 缓冲；65 为区间中位 |
| `ENEMY_KNOCKBACK_PX` | 40.0 | **22.0** | [20, 22, 25] | PRD §4.4 方案 A——单次击退后 |dx| ≈ 65+22=87 略出范围，玩家前移 10-20px 即续连段；Chase 无冷却回扑兜底 |
| `POSTURE_HIT_COST` | 35.0 | **18.0** | [15, 18, 20] | issue body 拍板 15-20（5-7 击崩解）——100/18≈5.6 → 6 击崩解 |
| `ENEMY_CHARGE_WINDUP` | 20 | **24** | [20, 24, 28] | issue body 要素 8：蓄力重斩 20+ 帧长前摇（奖励读招） |
| `ENEMY_ATTACK_COOLDOWN_SEC` | 1.5 | **1.2** | [1.2, 1.5, 1.8] | issue body 要素 6：攻击欲望高、压迫感 |
| `PARRY_STANCE_DAMAGE` | 25.0 | **35.0** | [30, 35, 40] | 普通弹反回报（issue body 30-40）——3 次弹反崩解 |

- **新增常量（# DRAFT）:**

| 常量 | 默认 | 候选集 | 用途 |
|------|:---:|------|------|
| `ENEMY_THRUST_WINDUP` | 16 | [14, 16, 18] | 突刺/横扫中前摇（combo 12 短 / thrust 16 中 / charge 24 长——三级可读梯度） |
| `ENEMY_BLOCK_CHANCE` | 0.4 | [0.3, 0.4, 0.5] | 防御触发概率（玩家攻击前摇内敌人掷骰进入 guard） |
| `PARRY_WINDOW_CHARGE_SECONDS` | 0.3 | [0.25, 0.3, 0.35] | 蓄力重斩弹反窗口（加宽——读招回报） |
| `PARRY_WINDOW_THRUST_SECONDS` | 0.25 | [0.2, 0.25, 0.3] | 突刺弹反窗口（中） |
| `PARRY_STANCE_DAMAGE_CHARGE` | 55.0 | [50, 55, 60] | 蓄力重斩弹反回报（弹大招扣更多） |
| `PARRY_STANCE_DAMAGE_THRUST` | 45.0 | [40, 45, 50] | 突刺弹反回报（中） |
| `ENEMY_ENRAGE_HP_RATIO`（P2 可选） | 0.5 | [0.4, 0.5, 0.6] | 血线阶段：HP ≤ 50% 触发强化（冷却缩短 + charge 概率提升） |

- **联动规则:** `PARRY_WINDOW_SECONDS=0.2` 保留为普通连击默认窗口（AttackWindow 字段 fallback）；`PARRY_STANCE_DAMAGE=35` 新默认同时被既有测试 `_test_24`（==25.0 断言）消费 → **该断言需更新**（§10 受影响测试）。

## 6. 敌人防御行为（格挡）—— `enemy_ai.gd` + `enemy_ai_states.gd`

- **文件:** `shandong-wolf/gdscripts/enemy_ai.gd`、`shandong-wolf/gdscripts/enemy_ai_states.gd`
- **机制（Pattern 2 — 行为 FSM 内新增 GuardState，不新增战斗状态名）:**
  1. **触发:** 玩家进入 attack/heavy_attack 前摇（复用 `_on_player_state_changed` 钩子，现 retreat 触发同源）→ 敌人实体处于 idle/move、`|dx| ≤ HITBOX_RANGE`（玩家攻击够得着）→ 掷骰 `_rng.randf() < ENEMY_BLOCK_CHANCE` → 行为 FSM 转移 GuardState。
  2. **执行:** GuardState.enter → `ai.entity.request_transition("guard")`（战斗态进入 guard；AI decide 门控自然冻结位移）。玩家攻击命中 → judge 既有路径 `defender.state_name == "guard"` → `block_held`（敌人扣 POSTURE_BLOCK_COST=10 架势 + 事件广播，#579 反馈/#593 音效自动消费）。
  3. **退出:** 玩家攻击窗口结束（judge 侧无法直接感知 → 用计时）：GuardState 持续 `ENEMY_GUARD_HOLD_SECONDS`（新常量，候选 [0.4, 0.5, 0.6]s，覆盖玩家 windup 8 + burst 4 + recovery 10 ≈ 22 帧 ≈ 0.37s）→ 期满 `request_transition("idle")` + 回 Chase。
  4. **敌人弹反（P2 可选，本期不实现）:** 敌人 guard 起始时刻若恰在玩家攻击命中帧前 PARRY_WINDOW_SECONDS 内 → 玩家被弹反。本期标注 P2 可选，不阻塞 MVP。

```gdscript
class GuardState:
    extends AIStateBase
    func enter() -> void:
        ai._behavior = "guard"
        state_name = "guard"
        _elapsed = 0.0
        if ai.entity != null:
            ai.entity.request_transition("guard")
    func update(delta: float) -> void:
        _elapsed += delta
        if _elapsed >= float(C.ENEMY_GUARD_HOLD_SECONDS):
            if ai.entity != null and ai.entity.state_name == "guard":
                ai.entity.request_transition("idle")
            ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
```

- **防御触发钩子（enemy_ai.gd `_on_player_state_changed` 扩展）:** 敌人 idle/move + `|dx| ≤ HITBOX_RANGE` + 非 retreat/guard 行为 + `_rng.randf() < ENEMY_BLOCK_CHANCE` → `_ai_fsm.transition_to(GuardState)`。
- **边界:** 格挡中玩家弹反？——玩家弹反只对敌人**攻击**有效（defender==player），敌人格挡时玩家攻击走 block_held，无冲突；格挡中敌人架势归零 → `guard → stance_break` 表内合法（#718 无关）；格挡中敌人被玩家绕背 → facing 不变（MVP 一维，无绕背语义）。
- **Integration:** judge 零改动（block 路径既有）；#579 反馈 / #593 音效经 block_held 事件自动消费。

## 7. 差异化前摇 + 弹反窗口/回报差异化 — `enemy_ai_states.gd` + `combat_attack_window.gd` + `combat_judge.gd`

- **差异化前摇（`enemy_ai_states.gd` AttackState.enter 扩展）:** 三选一出招时注入差异化前摇 override——
  - **combo（普通连击）:** `current_windup_frames` 不设 → judge fallback `ENEMY_ATTACK_WINDUP=12`（短前摇，需预判/反应弹反）
  - **thrust（突刺/横扫变体）:** 注入 `current_windup_frames = ENEMY_THRUST_WINDUP`（16，中前摇）
  - **charge（蓄力重斩）:** 已有 override `ENEMY_CHARGE_WINDUP`（20→24，长前摇）
- **视觉信号（taste 骨架，implement 落地）:** 差异化前摇必须搭配差异化视觉——charge 期举刀蓄力姿态、thrust 身体前倾/刀尖朝向、刀光节奏（sword_arc #574 既有）。具体姿态数值归 implement 视觉层 + #584 用户裁决，本设计只定「三级前摇必须三级可读信号」的约束。
- **AttackWindow 新增字段（`combat_attack_window.gd`）:**

```gdscript
var parry_window_seconds: float = -1.0    # -1 → 回退 C.PARRY_WINDOW_SECONDS（普通连击 0.2）
var parry_stance_damage: float = -1.0     # -1 → 回退 C.PARRY_STANCE_DAMAGE（普通弹反 35）
```

- **judge 登记窗口时按招式注入（`_on_entity_state_changed` 敌人分支）:** 按 windup 阈值链（charge 24 先判、thrust 16 次判、其余 fallback）注入 `parry_window_seconds`/`parry_stance_damage`——charge→0.3s/55、thrust→0.25s/45、combo→字段保持 -1 fallback（0.2s/35）。
- **judge `_resolve_parry` 改读窗口字段（fallback 保既有语义）:** `parry_window_seconds >= 0.0` 则用窗口字段、否则回退 `C.PARRY_WINDOW_SECONDS`；`parry_stance_damage >= 0.0` 则用窗口字段、否则回退 `C.PARRY_STANCE_DAMAGE`。
- **边界:** 玩家攻击敌人时 defender=enemy、`parry_ok` 判定仅 `defender == player` → 玩家弹反逻辑零变化；窗口差异化只对敌人攻击生效（玩家攻击窗口 parry 字段保持 -1）。

## 8. 数据流

**Flow 1: 玩家进攻（修复后）**
```text
玩家按攻击（attack_pressed）
    ▼
CombatEntity._on_bridge_attack_pressed
    ├── _face_nearest_target() → facing = sign(enemy.x - player.x)   ★ 自动面向
    └── request_transition("attack") → state_changed
    ▼
CombatJudge._on_entity_state_changed → AttackWindow 登记（direction=修正后 facing）
    ▼
命中帧 CombatJudge.resolve_attack
    ├── 距离: |dx| ≤ HITBOX_RANGE=80（停距 65 < 80 → 天然缓冲）
    ├── facing: rel_dir == w.direction（攻击瞬间已转向 → 不再挥空）
    ├── 弹反?（玩家 guard 时机）→ parry_success（combo 0.2s/35；thrust 0.25s/45；charge 0.3s/55）
    ├── clash?（双方窗口同帧）→ 各扣 10（打铁节奏保留）
    └── 受击: enemy.take_damage + take_stance_damage(18) + hit_landed
    ▼
enemy.take_damage
    ├── windup 期 → _is_armored() = true → 扣血不打断（霸体）
    └── 收招期 → stagger（可打断，玩家反击窗口）
    ▼
hit_landed → EnemyAI._on_judge_hit_landed → 击退 22px（衰减 DECAY=3）
    → 敌人被推出 ≤ 87px，Chase 无冷却回扑 → 连段可续
```

**Flow 2: 敌人进攻（Boss 级节奏）**
```text
敌人 Chase 逼近 → 停距 65px
    ▼
AttackState.enter 三选一掷骰
    ├── charge 24%? → 蓄力重斩（windup 24 帧，长前摇 + 举刀信号，弹反窗 0.3s 宽）
    ├── thrust 30%? → 突刺（windup 16 帧，中前摇 + 前倾信号，弹反窗 0.25s）
    └── combo → 三连砍（windup 12 帧，短前摇，弹反窗 0.2s 标准）
    ▼
玩家普攻命中 windup 期 → 霸体（不打断）→ 蓄力照常完成出招   ★ 不再「停止不出招」
玩家弹反 → parry_success 直接打断（路径独立于 take_damage）
```

**Flow 3: 敌人防御（新增）**
```text
玩家进入 attack/heavy_attack 前摇
    ▼
EnemyAI._on_player_state_changed（复用 retreat 触发钩子）
    ├── 敌人 idle/move + |dx| ≤ 80 → 掷骰 40% 进入防御
    └── 行为 FSM → GuardState → entity.request_transition("guard")
    ▼
玩家攻击命中帧 → CombatJudge.resolve_attack
    └── defender.state_name == "guard" → block_held（敌人扣 10 架势 + 事件）
    ▼
GuardState 期满（ENEMY_GUARD_HOLD_SECONDS）→ request_transition("idle") → 回 Chase
    （连续攻击被格挡 → 敌人架势持续扣减 → 破防策略成立：换弹反/蓄力重击/持续压制）
```

## 9. 边界情况与错误处理

| # | 边界情况 | 处理 |
|---|---------|------|
| 1 | 弹反 vs 霸体优先级（蓄力期玩家弹反） | parry_success 路径不经过 take_damage → 天然打断霸体（PRD §5.2-1，必测） |
| 2 | 收招期可打断（霸体误伤反向用例） | `_is_armored()` 严格 windup 期（`_state_elapsed_frames < _windup_frames`）——收招期恢复 stagger（PRD §5.3-1，必测） |
| 3 | 自动面向 vs 移动 facing 冲突 | 攻击转向优先（攻击入口一次性修正）；`_bridge_poll` 非 idle/move 不更新 facing（PRD §5.2-2，必测） |
| 4 | 无敌人时攻击 | `_auto_face_target == null` → no-op（PRD §5.2-3，必测） |
| 5 | 蓄力期被崩解（霸体 + 崩解并存） | break_stance 不经 take_damage → 崩解打断霸体；#718 未修前 warning 属 known limitation（#718 轨道） |
| 6 | 击退后出范围 | 停距 65 + 击退 22 → 单次击退后 87px 略出范围 → 玩家前移 10-20px 续连段 或 敌人 Chase 回扑（PRD §5.2-5，必测） |
| 7 | 防御触发频率过高/过低 | ENEMY_BLOCK_CHANCE=0.4 候选 [0.3, 0.4, 0.5]；防御不打断 retreat 既有路径 |
| 8 | 防御中玩家蓄力重击 | 玩家 heavy_attack 同样触发防御判定 → block_held 扣 10；重击被格挡不破防——鼓励换弹反 |
| 9 | 格挡中架势归零 | `guard → stance_break` 表内合法（#575 拓扑既有）→ 崩解 → 处决窗口（#580 衔接） |
| 10 | 弹反窗口差异化误伤普通连击 | 普通连击窗口字段保持 -1 → fallback PARRY_WINDOW_SECONDS=0.2，既有 `_test_1/_test_2` 边界断言零破坏 |
| 11 | thrust 与 charge 的 windup 阈值混淆 | judge 注入用 `>=` 阈值链（charge 24 先判、thrust 16 次判、其余 fallback）——两常量间距 8 帧，无重叠区间 |
| 12 | 敌人死亡后防御/霸体残留 | `_dead` 标志使 decide 门控短路（既有）；防御触发钩子 `_dead` 守卫已加 |
| 13 | 血线阶段（P2）半血判定 | `hp_1 / life_1_max ≤ 0.5`，敌人 life_total=1 → 无复活干扰；enrage 只调冷却/概率，不新增状态 |
| 14 | headless 可测性 | 霸体（`_state_elapsed_frames` 手动设置）、自动面向（`_auto_face_target` 手动注入）、防御（`_on_player_state_changed` 手动调用 + rng_seed 确定性）、弹反差异化（窗口字段断言）全部无场景树依赖 |

## 10. 受影响测试文件

| 测试文件 | 变更性质 |
|---------|---------|
| `shandong-wolf/tests/test_combat_judge.gd` | `_test_24`（PARRY_STANCE_DAMAGE==25 / POSTURE_HIT_COST==35 常量断言 → 新默认 35/18）；新增弹反窗口/回报差异化用例 |
| `shandong-wolf/tests/test_enemy_ai.gd` | `_test_16/_test_17`（弹反回报 25→35、4 次崩解→3 次）；`_test_33`（combo_interrupt 行为反转：windup 期命中不中断）；`_test_40`（击退 40→22 字面量核对）；新增霸体/防御/停距缓冲用例 |
| `shandong-wolf/tests/test_combat_entity.gd` | 新增霸体（windup 不打断/收招可打断）+ 自动面向用例；`_test_c1` 等既有用例核对（idle 态受击仍 stagger——霸体只拦 windup 期，预计零破坏） |

## 11. 验收条件映射（issue #720 body 6 条 + PRD §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 敌人能稳定出招且威胁感强（普通攻击不无限打断——弹反/闪避才有窗口） | §3 霸体（windup 期不打断）+ §7 三级前摇 | T1-T4（霸体/弹反打断/收招可打断）+ T15（前摇梯度）+ 实机 |
| AC2 | 玩家 5-7 次有效命中才崩解（只狼双轨节奏） | §5 POSTURE_HIT_COST 35→18 | T20（6 击崩解）+ T21（3 次弹反崩解） |
| AC3 | 敌人会追击（脱战会被追上）、会防御（格挡/弹反玩家攻击） | 追击=既有 Chase 无冷却 + 停距 65 增强压迫；防御=§6 GuardState 新增 | T8-T10（停距/击退/回扑）+ T11-T14（防御触发/判定/退出） |
| AC4 | 弹反/格挡/架势崩解/处决全系统有完整可测的博弈循环 | 弹反（差异化窗口/回报 §7）+ 格挡（§6）+ 崩解（#718 并行）+ 处决（#580 既有） | T16-T18（弹反差异化）+ T12（格挡）+ T23（E2E 闭环） |
| AC5 | 战斗有来有回：玩家需要观察出招、选择应对（弹反/闪避/格挡/输出时机） | 三级前摇可读（§7）+ 防御/弹反博弈（§6/§7） | T15-T19 + 实机手测（用户裁决） |
| AC6 | MVP 战斗闭环可测（接战→博弈→崩解/处决或败北） | 全部组件联动 + 霸体保证互攻成立 | T23（E2E playthrough）+ T22（全量单测） |

## 12. 明确不修改（与 PRD §3.3/§6.1/§8 红线对齐）

- ❌ `shandong-wolf/gdscripts/combat_state_table.gd`（11 态转移拓扑**冻结**——stagger→stance_break 归 #718 独立轨道，PRD §6.1）
- ❌ `shandong-wolf/gdscripts/combat_states.gd`（状态对象集零改动——霸体在 take_damage 层，不新增战斗状态名）
- ❌ `shandong-wolf/gdscripts/player_controller.gd` / `stick_figure_controller.gd`（移动层/视觉翻转零改动——自动面向经 CombatEntity facing 写入，#683 facing→scale.x 翻转自动联动）
- ❌ `shandong-wolf/gdscripts/hud.gd` / `reaction_controller.gd` / `execution_orchestrator.gd` / `feedback_spark.gd`（五事件契约不变，消费方零改动）
- ❌ `shandong-wolf/scenes/*`、`shandong-wolf/project.godot`、`game-env/manifest.yaml`、`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`（跨游戏/管线红线）
- ❌ 任何贴图 / Sprite2D / shader 美术资产（零美术资产改动；视觉信号复用既有 stick_figure 动画 + sword_arc）
- ❌ 任何可运行测试文件（本阶段只产出 DESIGN + TASKS 文档 + 测试用例描述；测试代码归 implement agent）
- ✅ `combat_judge.gd` 既有五事件签名 / `_resolve_clash` / block 路径 / 距离判定 / facing 校验**逻辑零改动**（仅弹反裁决改读窗口字段，fallback 保持语义）
- ✅ `enemy_ai.gd` 既有 Chase/Patrol/Retreat/感知逻辑零改动（防御为追加触发分支，retreat 优先守卫）
- ✅ `test_combat_judge.gd` 既有 `_test_1~_test_23` 除 `_test_24` 外零改动（普通攻击弹反走 fallback 常量）

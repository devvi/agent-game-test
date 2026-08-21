# Design: [Boss 级 AI] 战斗交互升级——敌人出招稳定（霸体）+ 玩家命中可靠（自动面向/停距/击退）+ 防御/前摇/弹反博弈深化

> **Parent Issue:** #720（bug / feature / workflow/plan / priority/high / gameplay / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A × 4 全部确认采纳**（霸体=蓄力期霸体 / 自动面向=攻击瞬间转向 / 停距=60-70px / 击退=20-25px）；**issue body 2026-08-21 用户拍板追加要素全部纳入**（防御行为、差异化前摇+视觉信号、弹反窗口差异化、弹反回报差异化、数值平衡 35→15-20、血线阶段=可选 P2）——PRD 完成后用户追加了 Boss 级 AI 需求（见 §1.1 范围对照），本设计是 PRD 4 方向 + 追加要素的合并落地。
> **Reference PRD:** `docs/PRD/720-combat-interaction-interrupt-hit.md`（research PR #722 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/575-combat-entity-state-machine.md`（11 态 FSM + take_damage 契约）；`docs/DESIGN/577-parry-clash-stance-break.md`（判定层五事件 + AttackWindow）；`docs/DESIGN/581-enemy-ai.md`（行为 FSM patrol/chase/attack/retreat）；`docs/DESIGN/682-elite-boss-ai.md`（蓄力重斩 override + 击退 + 架势恢复）；`docs/DESIGN/703-enemy-ai-driver-wiring.md`（#710 已交付——运行时驱动链）
> **所有权:** `content_ownership: mechanical`（霸体/自动面向/停距/击退/弹反窗口/弹反回报=机械判定与数值工程，headless 可自动验证；**前摇差异化视觉信号（举刀姿态/刀光节奏）含 taste 成分**，骨架由本设计定、表现细节归 implement 视觉层 + #584 用户裁决）
> **深度:** standard（issue 无 depth 标签，PRD 头标注 depth: standard）—— 涉及生产文件 **6**（constants / combat_entity / combat_judge / combat_attack_window / enemy_ai / enemy_ai_states）+ 测试文件 **3**（test_combat_judge / test_enemy_ai / test_combat_entity），跨 **5 个子系统**（常量层/实体层/判定层/攻击窗口/AI 行为层）→ **产出 TASKS 文档**（skill standard 阈值：5+ 不同子系统子任务）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-720，branch `plan/720-combat-interaction-interrupt-hit`）；**#718（workflow/plan）并行轨道**——research PR #723 已合并（PRD 已出），plan agent 可能并行产出 #718 plan PR；本设计**不修改 combat_state_table.gd 转移拓扑**（#718 边界，PRD §6.1）；**#584（OPEN, status/human-review）数值定稿队列**——本设计全部数值采用「用户拍板值 + 候选集」标 # DRAFT，定稿归 #584；无其他开放 PR 触碰 shandong-wolf 战斗文件（2026-08-21 核验：零 open PR）
> **红线:** 只动 PRD §3.1 列出的文件 + issue body 追加要素所需文件；**不修改 combat_state_table.gd**（11 态拓扑与 #574 动画逐字对齐，#718 独立轨道）；**不写可运行测试文件**（测试用例描述归本 DESIGN §9，测试代码归 implement agent）；PR body 用 `Parent #720`（不带冒号）

---

## 1. 架构总览

### 1.1 范围对照（PRD 4 方向 vs issue body 用户拍板 Boss 级 AI）

issue body 于 2026-08-21 用户拍板**大幅增强敌人 AI 至只狼 Boss 级**，验收标准 6 条。PRD（#722）覆盖其中 4 个方向，用户追加要素 8-10（前摇可读性/弹反窗口/弹反回报）与 Boss 级核心要素（防御行为、数值平衡、血线阶段可选）**PRD 未覆盖**。本设计合并两者：

| 需求来源 | 要素 | 本设计落点 | 优先级 |
|---------|------|-----------|:---:|
| PRD 方向 1 | 敌人蓄力期霸体（普攻不打断，弹反才打断） | §2.1（combat_entity.take_damage windup 分支） | P0 |
| PRD 方向 2 | 玩家攻击自动面向最近敌人 | §2.2（combat_entity 攻击入口 facing 修正） | P0 |
| PRD 方向 3 | 停距 < 判定范围（80→60-70） | §2.3（constants ENEMY_ATTACK_RANGE） | P0 |
| PRD 方向 4 | 击退缩短 + 回扑（40→20-25） | §2.3（constants ENEMY_KNOCKBACK_PX） | P0 |
| issue body 要素 1 | 攻击多样（连击 2-3 段 + 蓄力重斩 + 突刺/横扫） | 已有三选一（combo×3/thrust/charge）；**横扫 = thrust 视觉变体**（P2 可选） | P1 |
| issue body 要素 2 | 霸体/抗打断 | = PRD 方向 1 | P0 |
| issue body 要素 3 | 追击压迫（脱战被追上） | 已有 Chase 无冷却回扑（#581）；停距改近增强压迫 | P0 |
| issue body 要素 4 | **防御行为（敌人格挡/弹反玩家攻击）** | §2.4（**新增** GuardState + guard 判定路径；敌人弹反 = P2） | P0 |
| issue body 要素 5 | 架势管理（回复/崩解→处决） | 已有（#682 恢复 + #580 衔接）；#718 并行轨道补齐崩解 | P0 |
| issue body 要素 6 | 压迫感（节奏快、前摇清晰） | §2.5（差异化前摇）+ 冷却候选缩短 | P0 |
| issue body 要素 7 | 血线阶段变化（可选） | §2.6（P2 可选 enrage） | P2 |
| issue body 要素 8 | 前摇可读性（差异化前摇 + 视觉信号） | §2.5（ENEMY_THRUST_WINDUP 新增 / CHARGE 20→24 候选） | P0 |
| issue body 要素 9 | 弹反窗口差异化（普攻 0.15-0.2 / 蓄力 0.3） | §2.7（AttackWindow.parry_window_seconds 按招式） | P0 |
| issue body 要素 10 | 弹反回报清晰（普攻 30-40 / 蓄力 50-60） | §2.7（AttackWindow.parry_stance_damage 按招式） | P0 |
| issue body 数值 | 架势伤害 35→15-20（5-7 击崩解） | §2.3（POSTURE_HIT_COST → 18 候选 [15,18,20]） | P0 |

### 1.2 核心架构决策

**决策 1 — 霸体在实体层（take_damage），弹反路径天然保留。** judge 的 `_resolve_parry` 直接 `request_transition("parry_success")`，不经过 `take_damage` → 霸体分支只拦截 stagger 打断路径，弹反打断蓄力 100% 保留（PRD §5.2-1 硬性边界）。

**决策 2 — 弹反差异化挂在 AttackWindow（数据驱动），judge 逻辑零分支爆炸。** 招式类型（combo/thrust/charge）在 `enemy_ai_states.gd` 出招时决定，经 `current_windup_frames` override 链已在 judge 登记时可见；新增 `parry_window_seconds` / `parry_stance_damage` 两个窗口字段，judge 弹反裁决改为读窗口字段（默认回退既有常量 → 既有测试零破坏）。

**决策 3 — 防御行为复用 11 态 guard 态（零新增状态名）。** 敌人格挡 = 实体进入既有 `guard` 态，judge 既有 `defender.state_name == "guard"` → block_held 路径直接生效（扣 POSTURE_BLOCK_COST）。不触碰 combat_state_table.gd 拓扑红线（guard 进出转移表已完备：idle/move→guard 合法、guard→idle/stance_break 合法）。

**决策 4 — 自动面向在攻击入口一次性修正，不追踪。** 保持 #577 窗口 direction 快照语义（登记时 facing），只把「攻击瞬间 facing 错误」这个挥空充分条件消除；不做方案 B 的全程追踪（会破坏 direction 快照 + 视觉违和，PRD §4.2 否决理由采纳）。

**决策 5 — 数值全部「用户拍板值 + 候选集」标 # DRAFT，定稿归 #584。** 用户已拍板方向（35→15-20、弹反 30-40/50-60、窗口 0.15-0.2/0.3），本设计取区间中位为默认实现值，候选集登记，定稿裁决权留 #584（status/human-review 并行中）。

### 1.3 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| 11 态战斗 FSM（`combat_entity.gd` + `combat_state_table.gd`） | #575（#618 merged） | ✅ | **改**（combat_entity：霸体分支 + 自动面向入口）；**零改**（combat_state_table：拓扑冻结，#718 轨道） |
| 判定层五事件（`combat_judge.gd` + `combat_attack_window.gd`） | #577（#626 merged） | ✅ | **改**：弹反裁决读窗口字段（差异化窗口/回报）；AttackWindow 加 2 字段 |
| 敌 AI 行为 FSM（`enemy_ai.gd` + `enemy_ai_states.gd`） | #581（#638 merged）/ #703（#710 merged） | ✅ | **改**：AttackState 前摇注入（thrust 中前摇）；新增防御触发 + GuardState 行为态 |
| 精英化（蓄力重斩/击退/架势恢复） | #682（#695 merged） | ✅ | **改**：constants 数值（停距/击退/架势伤害）；charge 前摇候选 20→24 |
| 运行时驱动链（decide→_physics_process） | #703（#710 merged） | ✅ | **零改**——防御/霸体全部经既有驱动链 |
| 玩家输入桥（`_on_bridge_attack_pressed`） | #573/#585 | ✅ | **改**：攻击入口加自动面向（facing 修正） |
| 弹反窗口/回报常量（PARRY_WINDOW_SECONDS=0.2 / PARRY_STANCE_DAMAGE=25） | #584 DRAFT | ✅ 登记中 | **改**：窗口/回报按招式差异化（新增字段 + 新常量） |
| 受击/架势常量（POSTURE_HIT_COST=35 / ENEMY_ATTACK_RANGE=80 / ENEMY_KNOCKBACK_PX=40） | #584 DRAFT | ✅ 登记中 | **改**：采纳用户拍板值（18 / 65 / 22，候选集登记） |

### 1.4 核心缺口与修复决策（codebase 勘探确认）

| PRD/issue 断言 | 实际代码 | 结论 |
|---------|---------|------|
| 敌人蓄力被普攻打断 → 连段作废回 Chase（打断循环） | `enemy_ai_states.gd` AttackState.update：`st 非 idle/move/attack/heavy_attack → 回 Chase`；`combat_entity.take_damage` 四态可被打断进 stagger ✓ | 属实——霸体落点 = take_damage windup 分支 |
| 玩家站桩攻击 facing 不更新 → 挥空 | `combat_entity._bridge_poll`：facing 仅移动轴更新；`combat_judge.gd` facing 校验 `rel_dir != w.direction → 挥空` ✓ | 属实——自动面向落点 = 攻击入口 |
| 拼刀反复（双方窗口同帧 → clash 各扣 10） | `combat_judge._resolve_clash` ✓ | 保留（打铁节奏是只狼要素）；本设计不取消 clash，靠停距/击退缩短减少「玩家单方面打不到」场景 |
| 击退 40px 把敌人推出 80px 判定范围 | `enemy_ai._on_judge_hit_landed`：`_knockback_vel = ENEMY_KNOCKBACK_PX=40` ✓ | 属实——缩短至 22 + 停距 65 后单次击退仍 ≤ 判定边界 |
| 敌人无防御行为（issue body 要素 4） | `enemy_ai.gd` 仅有 retreat（5% 后退），无 guard/格挡触发 ✓ | **属实——新增防御行为**（§2.4） |
| 弹反窗口固定 0.2s（issue body 要素 9） | `combat_judge._resolve_parry`：`PARRY_WINDOW_SECONDS` 全局常量；AttackWindow 无招式类型字段 ✓ | 属实——窗口差异化挂 AttackWindow |
| 弹反回报固定 25（issue body 要素 10） | `combat_judge._resolve_parry`：`PARRY_STANCE_DAMAGE=25` 固定 ✓ | 属实——回报差异化挂 AttackWindow |
| 玩家 3 击崩解敌人（35×3=105>100）过快（issue body 数值） | `POSTURE_HIT_COST=35`，玩家攻击 stance_damage = POSTURE_HIT_COST ✓ | 属实——15-20 区间取 18（6 击崩解） |
| 蓄力/突刺前摇可读性不足（issue body 要素 8） | `ENEMY_ATTACK_WINDUP=12`（combo）/ `ENEMY_CHARGE_WINDUP=20`（charge）；thrust 复用默认 12 ✓ | 属实——thrust 独立中前摇（新增常量），charge 20→24 候选 |
| #718 stagger→stance_break 非法转移 | `combat_state_table.gd`：`stagger: [idle, dead]` 无 stance_break ✓ | **边界**：不修（#718 独立轨道，PRD §6.1） |

---

## 2. 新组件 — 详细设计

### 2.1 霸体（抗打断）—— `combat_entity.gd` 修改

- **文件:** `shandong-wolf/gdscripts/combat_entity.gd`
- **机制:** 敌人处于 attack/heavy_attack 且**仍在 windup 期**时，`take_damage` 扣血/扣架势但**不转 stagger、不打断动作**；windup 结束后（暴发/收招期）恢复可打断。
- **windup 期判定:** 实体自行计时——进入 attack/heavy_attack 态时记录 `_windup_frames`（读自身 override `current_windup_frames`，fallback 读 `C.ENEMY_ATTACK_WINDUP`；heavy_attack 且无 override = thrust，读 `C.ENEMY_THRUST_WINDUP`）；用 `_state_elapsed_frames`（新增，_process 按 FRAME_RHYTHM_BASE 累计）与 windup_frames 比较。
- **状态属性:**
  - `var _state_elapsed_frames: int = 0`（进入任意态重置；_process 每帧 +1——仅敌人变体需要精确计时，玩家侧开销可忽略）
  - `var _windup_frames: int = 0`（进入 attack/heavy_attack 时按招式设置）
- **关键方法（伪代码）:**
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
- **state_changed 挂钩:** `_on_state_entered`（在 request_transition 成功后）重置 `_state_elapsed_frames = 0`；attack/heavy_attack 时设置 `_windup_frames`。
- **弹反路径不受影响:** judge `_resolve_parry` → `request_transition("parry_success")` 不经过 take_damage → 蓄力期弹反照常打断（PRD §5.2-1 边界 1）。
- **边界:** 蓄力期被崩解（stance 归零）→ `break_stance()` 也不经 take_damage 的 stagger 分支 → 崩解天然打断霸体（PRD §5.2-4；#718 修复前有 warning，known limitation）。
- **Integration:** `_process` 每帧 `_state_elapsed_frames += 1`（仅状态非 idle 时）；headless 测试手动 tick 或直接设 `_state_elapsed_frames`。

### 2.2 玩家攻击自动面向 — `combat_entity.gd` 修改

- **文件:** `shandong-wolf/gdscripts/combat_entity.gd`
- **机制:** 玩家 `_on_bridge_attack_pressed` / `_on_bridge_heavy_attack_pressed` 时，若存在 `_auto_face_target`（敌人引用，main_battle 注入）且 `|dx| > 0` → 一次翻转 `facing = sign(dx)`，再 `request_transition("attack"/"heavy_attack")`。攻击全程 facing 锁定（窗口 direction 快照语义不变）。
- **状态属性:** `var _auto_face_target: Node2D = null`（main_battle 装配注入 player_entity._auto_face_target = enemy_entity；headless 测试手动设）
- **关键方法（伪代码）:**
```gdscript
func _face_nearest_target() -> void:
    if _auto_face_target == null: return
    var dx: float = _auto_face_target.position.x - position.x
    if dx == 0.0: return
    facing = 1 if dx > 0.0 else -1

func _on_bridge_attack_pressed() -> void:
    _face_nearest_target()          # ★ 攻击瞬间自动转向
    request_transition("attack")

func _on_bridge_heavy_attack_pressed() -> void:
    _face_nearest_target()
    request_transition("heavy_attack")
```
- **优先级语义（PRD §5.2-2）:** 攻击转向优先于移动 facing；攻击结束后 facing 保持攻击方向（不跳回移动方向）——`_bridge_poll` 在非 idle/move 态不更新 facing（既有行为已满足）。
- **边界:** 场上无敌人（target null / 敌人死亡）→ no-op 保持原 facing（PRD §5.2-3）；玩家 heavy_attack 同规则（PRD §5.2-6）。
- **Integration:** `main_battle.gd` 装配处新增一行注入（§3.3）。

### 2.3 停距/击退/架势伤害数值 — `constants.gd` 修改

- **文件:** `shandong-wolf/gdscripts/constants.gd`
- **变更（全部标 # DRAFT + 候选集，用户拍板值 = 默认）:**

| 常量 | 现值 | 新默认 | 候选集 | 依据 |
|------|:---:|:---:|------|------|
| `ENEMY_ATTACK_RANGE` | 80.0 | **65.0** | [60, 65, 70] | PRD §4.3 方案 A——停距 < HITBOX_RANGE=80 → 10-20px 缓冲；65 为区间中位 |
| `ENEMY_KNOCKBACK_PX` | 40.0 | **22.0** | [20, 22, 25] | PRD §4.4 方案 A——单次击退后 |dx| ≈ 65+22=87 略出范围，玩家前移 10-20px 即续连段；Chase 无冷却回扑兜底 |
| `POSTURE_HIT_COST` | 35.0 | **18.0** | [15, 18, 20] | issue body 拍板 15-20（5-7 击崩解）——100/18≈5.6 → 6 击崩解 |
| `ENEMY_CHARGE_WINDUP` | 20 | **24** | [20, 24, 28] | issue body 要素 8：蓄力重斩 20+ 帧长前摇（奖励读招） |
| `ENEMY_ATTACK_COOLDOWN_SEC` | 1.5 | **1.2** | [1.2, 1.5, 1.8] | issue body 要素 6：攻击欲望高、压迫感（候选，改不改均不破坏逻辑） |

- **新增常量（# DRAFT）:**

| 常量 | 默认 | 候选集 | 用途 |
|------|:---:|------|------|
| `ENEMY_THRUST_WINDUP` | 16 | [14, 16, 18] | 突刺/横扫中前摇（combo 12 短 / thrust 16 中 / charge 24 长——三级可读梯度） |
| `ENEMY_BLOCK_CHANCE` | 0.4 | [0.3, 0.4, 0.5] | 防御触发概率（玩家攻击前摇内敌人掷骰进入 guard） |
| `PARRY_WINDOW_CHARGE_SECONDS` | 0.3 | [0.25, 0.3, 0.35] | 蓄力重斩弹反窗口（加宽——读招回报） |
| `PARRY_WINDOW_THRUST_SECONDS` | 0.25 | [0.2, 0.25, 0.3] | 突刺弹反窗口（中） |
| `PARRY_STANCE_DAMAGE_CHARGE` | 55.0 | [50, 55, 60] | 蓄力重斩弹反回报（弹大招扣更多） |
| `PARRY_STANCE_DAMAGE_THRUST` | 45.0 | [40, 45, 50] | 突刺弹反回报（中） |
| `PARRY_STANCE_DAMAGE`（改默认） | 25.0 | **35.0** [30, 35, 40] | 普通弹反回报（issue body 30-40） |
| `ENEMY_ENRAGE_HP_RATIO`（P2 可选） | 0.5 | [0.4, 0.5, 0.6] | 血线阶段：HP ≤ 50% 触发强化（冷却缩短 + charge 概率提升） |

- **联动规则:** `PARRY_WINDOW_SECONDS=0.2` 保留为普通连击默认窗口（AttackWindow 字段 fallback）；`PARRY_STANCE_DAMAGE=35` 新默认同时被既有测试 `_test_24`（==25.0 断言）消费 → **该断言需更新**（§9 受影响测试）。

### 2.4 敌人防御行为（格挡）—— `enemy_ai.gd` + `enemy_ai_states.gd` 修改（新增）

- **文件:** `shandong-wolf/gdscripts/enemy_ai.gd`、`shandong-wolf/gdscripts/enemy_ai_states.gd`
- **机制（Pattern 2 — 行为 FSM 内新增 GuardState，不新增战斗状态名）:**
  1. **触发:** 玩家进入 attack/heavy_attack 前摇（复用 `_on_player_state_changed` 钩子，现 retreat 触发同源）→ 敌人实体处于 idle/move、`|dx| ≤ HITBOX_RANGE`（玩家攻击够得着）→ 掷骰 `_rng.randf() < ENEMY_BLOCK_CHANCE` → 行为 FSM 转移 GuardState。
  2. **执行:** GuardState.enter → `ai.entity.request_transition("guard")`（战斗态进入 guard；AI decide 门控自然冻结位移）。玩家攻击命中 → judge 既有路径 `defender.state_name == "guard"` → `block_held`（敌人扣 POSTURE_BLOCK_COST=10 架势 + 事件广播，#579 反馈/#593 音效自动消费）。
  3. **退出:** 玩家攻击窗口结束（judge 侧无法直接感知 → 用计时）：GuardState 持续 `ENEMY_GUARD_HOLD_SECONDS`（新常量，候选 [0.4, 0.5, 0.6]s，覆盖玩家 windup 8 + burst 4 + recovery 10 ≈ 22 帧 ≈ 0.37s）→ 期满 `request_transition("idle")` + 回 Chase。
  4. **敌人弹反（P2 可选，本期不实现）:** 敌人 guard 起始时刻若恰在玩家攻击命中帧前 PARRY_WINDOW_SECONDS 内 → 玩家被弹反（玩家架势扣 + 硬直）。依赖 judge 扩展 `defender == enemy` 的 parry 分支，本期标注 P2 可选，不阻塞 MVP。
- **状态属性（enemy_ai.gd）:** `var _guard_until_sec: float = 0.0`
- **行为态工厂:** `make_state("guard", ai)` → `GuardState.new(ai)`（enemy_ai_states.gd）。
- **GuardState 伪代码:**
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
- **防御触发钩子（enemy_ai.gd `_on_player_state_changed` 扩展）:**
```gdscript
func _on_player_state_changed(_from: String, to: String) -> void:
    # ...既有 retreat 逻辑保留...
    if to != "attack" and to != "heavy_attack": return
    if _ai_fsm == null or entity == null or _dead: return
    if entity.state_name != "idle" and entity.state_name != "move": return
    if _behavior == "retreat" or _behavior == "guard": return
    if player == null: return
    var dx: float = player.position.x - position.x
    if absf(dx) > float(C.HITBOX_RANGE): return     # 玩家攻击够不着 → 不防御
    if _rng.randf() < float(C.ENEMY_BLOCK_CHANCE):
        _ai_fsm.transition_to(SelfScript.make_state("guard", ai))
```
- **边界:** 格挡中玩家弹反？——玩家弹反只对敌人**攻击**有效（defender==player），敌人格挡时玩家攻击走 block_held，无冲突；格挡中敌人架势归零 → `guard → stance_break` 表内合法（#718 无关）；格挡中敌人被玩家绕背 → facing 不变（MVP 一维，无绕背语义）。
- **Integration:** judge 零改动（block 路径既有）；#579 反馈 / #593 音效经 block_held 事件自动消费。

### 2.5 差异化前摇 + 视觉信号 — `enemy_ai_states.gd` + 表现层

- **文件:** `shandong-wolf/gdscripts/enemy_ai_states.gd`（逻辑）；视觉信号消费既有动画/刀光系统（#574/#683/#579，零新组件）
- **机制:** AttackState 三选一出招时注入差异化前摇 override：
  - **combo（普通连击）:** `current_windup_frames` 不设 → judge fallback `ENEMY_ATTACK_WINDUP=12`（短前摇，需预判/反应弹反）
  - **thrust（突刺/横扫变体）:** 注入 `current_windup_frames = ENEMY_THRUST_WINDUP`（16，中前摇）
  - **charge（蓄力重斩）:** 已有 override `ENEMY_CHARGE_WINDUP`（20→24 候选，长前摇）
- **视觉信号（taste 骨架，implement 落地）:** 差异化前摇必须搭配差异化视觉——charge 期举刀蓄力姿态（stick_figure 动画既有 state_changed→动画链路，#574 FRAME_ANIM_ATTACK_WINDUP=8 帧蓄力段）；thrust 身体前倾/刀尖朝向（stick_figure 姿态微调）；刀光节奏（sword_arc #574 既有）。**具体姿态数值归 implement 视觉层 + #584 用户裁决，本设计只定「三级前摇必须三级可读信号」的约束。**
- **伪代码（AttackState.enter 扩展）:**
```gdscript
func enter() -> void:
    # ...既有三选一掷骰...
    if _attack_kind == "thrust":
        ai.entity.current_windup_frames = int(C.ENEMY_THRUST_WINDUP)   # ★ 中前摇注入
    # charge/combo 走既有 override/fallback 链
```
- **Integration:** judge `_on_entity_state_changed` 登记窗口时读 `current_windup_frames` override（既有 fallback 链）→ 窗口 windup 自动差异化；测试 `_test_37_charge_window_contract` 断言 `windup_frames == ENEMY_CHARGE_WINDUP`（读常量自动跟随）。

### 2.6 血线阶段变化（P2 可选）— `enemy_ai.gd`

- **机制（可选，不阻塞 MVP）:** 敌人 HP ≤ `ENEMY_ENRAGE_HP_RATIO`（0.5）→ 强化态：`_attack_cooldown_until_sec` 缩短（冷却 ×0.6 候选）+ charge 概率提升（ENEMY_CHARGE_CHANCE ×1.5 候选）。落点：`decide()` 入口计算 `_enraged` 标志，AttackState 读冷却/概率时按标志调整。
- **边界:** 半血判定用 `entity.hp_1 / entity.life_1_max ≤ ratio`（life_total=1 敌人）；复活（玩家两条命）不影响敌人血线。
- **本期状态:** ⬜ P2 可选——DESIGN 只登记机制与常量，implement agent 可自主决定是否纳入（issue body 明示「可选」）。

### 2.7 弹反窗口/回报差异化 — `combat_attack_window.gd` + `combat_judge.gd` 修改

- **文件:** `shandong-wolf/gdscripts/combat_attack_window.gd`（+2 字段）、`shandong-wolf/gdscripts/combat_judge.gd`（弹反裁决读字段）
- **AttackWindow 新增字段:**
```gdscript
var parry_window_seconds: float = -1.0    # -1 → 回退 C.PARRY_WINDOW_SECONDS（普通连击 0.2）
var parry_stance_damage: float = -1.0     # -1 → 回退 C.PARRY_STANCE_DAMAGE（普通弹反 35）
```
- **judge 登记窗口时按招式注入（`_on_entity_state_changed` 敌人分支）:**
```gdscript
if is_enemy:
    var wu: int = int(entity.current_windup_frames) if (entity.current_windup_frames >= 0) else int(C.ENEMY_ATTACK_WINDUP)
    w.windup_frames = wu
    if wu >= int(C.ENEMY_CHARGE_WINDUP):
        w.parry_window_seconds = float(C.PARRY_WINDOW_CHARGE_SECONDS)      # 0.3 宽窗
        w.parry_stance_damage = float(C.PARRY_STANCE_DAMAGE_CHARGE)        # 55
    elif wu >= int(C.ENEMY_THRUST_WINDUP):
        w.parry_window_seconds = float(C.PARRY_WINDOW_THRUST_SECONDS)      # 0.25 中窗
        w.parry_stance_damage = float(C.PARRY_STANCE_DAMAGE_THRUST)        # 45
    # 否则: 普通连击 → 字段保持 -1 → fallback 常量（0.2 / 35）
```
- **judge `_resolve_parry` 改读窗口字段（fallback 保既有语义）:**
```gdscript
var win: Object = _active_window_for(attacker)
var pws: float = float(win.parry_window_seconds) if (win != null and win.parry_window_seconds >= 0.0) else float(C.PARRY_WINDOW_SECONDS)
var lower_ms: int = hit_ms - int(pws * 1000.0)
# ...
var psd: float = float(win.parry_stance_damage) if (win != null and win.parry_stance_damage >= 0.0) else float(C.PARRY_STANCE_DAMAGE)
enemy.take_stance_damage(psd)
emit_signal("parry_success", player, enemy, psd)
```
- **边界:** 玩家攻击敌人时 defender=enemy、`parry_ok` 判定仅 `defender == player` → 玩家弹反逻辑零变化；敌人弹反玩家（要素 4 P2）本期不实现（judge 扩展留待 P2）；窗口差异化只对敌人攻击生效（玩家攻击窗口 parry 字段保持 -1）。
- **Integration:** `test_combat_judge._test_1/_test_2`（弹反窗口边界）走普通攻击（字段 -1 → fallback 0.2）→ 零破坏；`_test_17_four_parries_break` 依赖 PARRY_STANCE_DAMAGE=25 → 新默认 35 后 3 次弹反崩解 → **断言需更新**（§9）。

---

## 3. 既有组件修改汇总

### 3.1 修改文件

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ① take_damage 加 `_is_armored()` 霸体分支（windup 期不转 stagger）；② 攻击入口 `_face_nearest_target()` 自动面向；③ 新增 `_state_elapsed_frames`/`_windup_frames`/`_auto_face_target` 状态属性；④ request_transition 成功后状态计时重置 | PRD 方向 1+2 落地主体 |
| `shandong-wolf/gdscripts/combat_judge.gd` | `_resolve_parry` 弹反窗口/回报改读 AttackWindow 差异化字段（fallback 既有常量）；`_on_entity_state_changed` 敌人分支按 windup 注入 parry 字段 | issue body 要素 9+10 |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | 新增 `parry_window_seconds` / `parry_stance_damage` 两字段（-1 = fallback） | 弹反差异化数据载体 |
| `shandong-wolf/gdscripts/enemy_ai.gd` | ① `_on_player_state_changed` 扩展防御触发（掷骰 ENEMY_BLOCK_CHANCE → GuardState）；② 新增 `_guard_until_sec`；③（P2）`_enraged` 血线阶段标志 | issue body 要素 4/7 |
| `shandong-wolf/gdscripts/enemy_ai_states.gd` | ① 新增 `GuardState` 行为态 + make_state 注册；② AttackState.enter 注入 thrust 中前摇 override；③ 新增常量 `ENEMY_GUARD_HOLD_SECONDS` 消费 | 防御行为 + 差异化前摇 |
| `shandong-wolf/gdscripts/constants.gd` | §2.3 数值变更 + 新增 8 常量（全部 # DRAFT + 候选集） | 数值平衡 + 新机制参数 |
| `shandong-wolf/gdscripts/main_battle.gd` | 装配处注入 `player_entity._auto_face_target = enemy_entity`（1 行） | 自动面向目标注入 |

### 3.2 新文件

| 文件 | 用途 |
|------|------|
| （无新 .gd/.tscn 文件） | 全部改动在既有文件内增量完成——防御行为复用 guard 态 + 行为 FSM 新态（enemy_ai_states.gd 内），零新组件（与 #703/#713 同策略，控制改动面） |

### 3.3 受影响测试文件（implement agent 需更新/新增——见 §9 完整清单）

| 测试文件 | 变更性质 |
|---------|---------|
| `shandong-wolf/tests/test_combat_judge.gd` | `_test_24`（PARRY_STANCE_DAMAGE==25 / POSTURE_HIT_COST==35 常量断言 → 新默认 35/18）；新增弹反窗口/回报差异化用例 |
| `shandong-wolf/tests/test_enemy_ai.gd` | `_test_16/_test_17`（弹反回报 25→35、4 次崩解→3 次）；`_test_33`（combo_interrupt 行为反转：windup 期命中不中断）；`_test_40`（击退 40→22 字面量核对）；新增霸体/防御/停距缓冲用例 |
| `shandong-wolf/tests/test_combat_entity.gd` | 新增霸体（windup 不打断/收招可打断）+ 自动面向用例；`_test_c1` 等既有用例核对（idle 态受击仍 stagger——霸体只拦 windup 期，预计零破坏） |

---

## 4. 数据流

**Flow 1: 玩家进攻（正常路径 —— 修复后）**
```text
玩家按攻击（attack_pressed）
    ▼
CombatEntity._on_bridge_attack_pressed
    ├── _face_nearest_target() → facing = sign(enemy.x - player.x)   ★ 自动面向（方向 2）
    └── request_transition("attack") → state_changed
    ▼
CombatJudge._on_entity_state_changed → AttackWindow 登记（direction=修正后 facing）
    ▼
命中帧 CombatJudge.resolve_attack
    ├── 距离: |dx| ≤ HITBOX_RANGE=80（停距 65 < 80 → 天然缓冲，方向 3）
    ├── facing: rel_dir == w.direction（攻击瞬间已转向 → 不再挥空）
    ├── 弹反?（玩家按 guard 时机）→ parry_success（普通 0.2s/35；charge 0.3s/55）
    ├── clash?（双方窗口同帧）→ 各扣 10（打铁节奏保留）
    └── 受击: enemy.take_damage + take_stance_damage(18) + hit_landed
    ▼
enemy.take_damage
    ├── windup 期 → _is_armored() = true → 扣血不打断（霸体，方向 1）
    └── 收招期 → stagger（可打断，玩家反击窗口）
    ▼
hit_landed → EnemyAI._on_judge_hit_landed → 击退 22px（方向 4，衰减 DECAY=3）
    → 敌人被推出 ≤ 87px，Chase 无冷却回扑 → 连段可续
```

**Flow 2: 敌人进攻（Boss 级节奏 —— 修复后）**
```text
敌人 Chase 逼近 → 停距 65px（方向 3）
    ▼
AttackState.enter 三选一掷骰
    ├── charge 24%? → 蓄力重斩（windup 24 帧，长前摇 + 举刀视觉信号，弹反窗 0.3s 宽）
    ├── thrust 30%? → 突刺（windup 16 帧，中前摇 + 前倾视觉信号，弹反窗 0.25s）
    └── combo → 三连砍（windup 12 帧，短前摇，弹反窗 0.2s 标准）
    ▼
玩家普攻命中 windup 期 → 霸体（不打断）→ 蓄力照常完成出招   ★ 不再「停止不出招」
玩家弹反 → parry_success 直接打断（路径独立于 take_damage）
    ▼
敌人出招命中 → 玩家受击/格挡/弹反（既有五事件契约）
```

**Flow 3: 敌人防御（新增 —— issue body 要素 4）**
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

**Flow 4: 边缘 —— 无敌人攻击 / 敌人死亡**
```text
玩家攻击时 _auto_face_target == null 或敌人 _is_final_dead
    → _face_nearest_target() no-op（保持原 facing）→ 既有 facing 挥空判定兜底
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 处理 |
|---|---------|------|
| 1 | **弹反 vs 霸体优先级**（蓄力期玩家弹反） | parry_success 路径不经过 take_damage → 天然打断霸体（PRD §5.2-1，必测） |
| 2 | **收招期可打断**（霸体误伤反向用例） | `_is_armored()` 严格 windup 期（`_state_elapsed_frames < _windup_frames`）——收招期恢复 stagger；测试覆盖「收招期命中进 stagger」防 windup 边界错位（PRD §5.3-1） |
| 3 | **自动面向 vs 移动 facing 冲突** | 攻击转向优先（攻击入口一次性修正）；`_bridge_poll` 非 idle/move 不更新 facing → 攻击中/后保持攻击方向（PRD §5.2-2，必测） |
| 4 | **无敌人时攻击** | `_auto_face_target == null` → no-op（PRD §5.2-3，必测） |
| 5 | **蓄力期被崩解**（霸体 + 崩解并存） | break_stance 不经 take_damage → 崩解打断霸体；#718 未修前 `stagger→stance_break` warning 属 known limitation（#718 轨道，PRD §5.3-4） |
| 6 | **击退后出范围** | 停距 65 + 击退 22 → 单次击退后 87px 略出范围 → 玩家前移 10-20px 续连段 或 敌人 Chase 回扑（无冷却）；连续击退被推出 → 回扑再战（PRD §5.2-5，必测） |
| 7 | **防御触发频率过高/过低** | ENEMY_BLOCK_CHANCE=0.4 候选 [0.3, 0.4, 0.5]；防御不打断 retreat 既有路径（`_behavior == "retreat"` 时跳过防御触发） |
| 8 | **防御中玩家蓄力重击** | 玩家 heavy_attack 同样触发防御判定（`to == "heavy_attack"` 分支）→ block_held 扣 10；重击被格挡不破防——鼓励换弹反 |
| 9 | **格挡中架势归零** | `guard → stance_break` 表内合法（#575 拓扑既有）→ 崩解 → 处决窗口（#580 衔接，#718 修复后路径完整） |
| 10 | **弹反窗口差异化误伤普通连击** | 普通连击窗口字段保持 -1 → fallback PARRY_WINDOW_SECONDS=0.2，既有 `_test_1/_test_2` 边界断言零破坏 |
| 11 | **thrust 与 charge 的 windup 阈值混淆** | judge 注入用 `>=` 阈值链（charge 24 先判、thrust 16 次判、其余 fallback）——两常量间距 8 帧，无重叠区间 |
| 12 | **敌人死亡后防御/霸体残留** | `_dead` 标志使 decide 门控短路（既有）；防御触发钩子 `_dead` 守卫已加 |
| 13 | **血线阶段（P2）半血判定** | `hp_1 / life_1_max ≤ 0.5`，敌人 life_total=1 → 无复活干扰；enrage 只调冷却/概率，不新增状态 |
| 14 | **headless 可测性** | 霸体（`_state_elapsed_frames` 手动设置）、自动面向（`_auto_face_target` 手动注入）、防御（`_on_player_state_changed` 手动调用 + rng_seed 确定性）、弹反差异化（窗口字段断言）全部无场景树依赖 |

**失败路径（≥3）:**

| # | 失败场景 | 兜底 |
|---|---------|------|
| 1 | 霸体 windup 边界错位（收招期误判 windup） | §5 边界 2 反向用例（收招期命中 → stagger）CI 兜底 |
| 2 | 自动面向导致 facing 抖动（攻击中移动） | 攻击转向锁（一次性修正）+ `_bridge_poll` 非 idle/move 不更新——测试覆盖攻击中按反方向移动 facing 不变 |
| 3 | 防御掷骰使敌人全程格挡（0.4 概率偏高体验） | ENEMY_BLOCK_CHANCE 候选可调 + 格挡扣架势（10/次）有代价——连续格挡自己先崩解（策略自平衡） |
| 4 | 弹反差异化后蓄力重斩窗口 0.3s 过宽 | 候选 [0.25, 0.3, 0.35] 归 #584 用户裁决；普通攻击仍 0.2s 兜底 |
| 5 | #718 未修前崩解路径 warning | known limitation：本设计不修转移表；崩解测试标注（#718 merge 后自动消除） |

---

## 6. 集成点

> **状态约定:** ⬜ = 待实现（implement agent 接线）；✅ = 已连接（implement agent 验证后更新）。review agent 在 merge 前核对全部 ⬜ 已解决或显式延后。

| 集成 | 我们的组件 | 目标 Issue | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| 霸体（windup 不打断） | `combat_entity.take_damage` + `_is_armored()` | #720 | take_damage stagger 分支前 return；`_state_elapsed_frames` 计时 | ⬜ 待实现 |
| 自动面向 | `combat_entity._on_bridge_attack/heavy_attack_pressed` | #720 | `_face_nearest_target()` 一次翻转 facing；main_battle 注入 target | ⬜ 待实现 |
| 停距/击退/架势数值 | `constants.gd`（ENEMY_ATTACK_RANGE=65 / ENEMY_KNOCKBACK_PX=22 / POSTURE_HIT_COST=18） | #720 | 常量替换 + 候选集注释 | ⬜ 待实现 |
| 防御行为 | `enemy_ai_states.gd` GuardState + `enemy_ai._on_player_state_changed` | #720 | 玩家攻击前摇触发掷骰 → guard 态 → block_held（judge 既有路径） | ⬜ 待实现 |
| 差异化前摇 | `enemy_ai_states.AttackState.enter`（thrust override 16）| #720 | `current_windup_frames` 注入（复用 #682 override 链） | ⬜ 待实现 |
| 弹反窗口/回报差异化 | `combat_attack_window` 2 字段 + `combat_judge._resolve_parry` | #720 | 窗口字段按 windup 注入；judge 读字段 fallback 常量 | ⬜ 待实现 |
| 崩解/处决路径 | `combat_state_table`（stagger→stance_break） | #718（并行） | 本设计不修；#718 merge 后路径完整 | ⬜ 外部依赖 |
| 反馈/音效消费 | `block_held`/`parry_success`/`hit_landed` 事件 | #579/#593 | 事件契约不变，零改动自动消费 | ✅ 既有 |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估计 |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | `constants.gd` 数值（停距 65 / 击退 22 / 架势 18 / charge 24 + 新增 8 常量） | 0.25 天 |
| Phase 2 | P0 | `combat_entity.gd` 霸体（_is_armored + 状态计时）——核心 | 0.5 天 |
| Phase 3 | P0 | `combat_entity.gd` 自动面向 + `main_battle.gd` 注入 | 0.25 天 |
| Phase 4 | P0 | `combat_attack_window.gd` + `combat_judge.gd` 弹反窗口/回报差异化 | 0.5 天 |
| Phase 5 | P0 | `enemy_ai_states.gd` GuardState + `enemy_ai.gd` 防御触发 + thrust 前摇注入 | 0.5 天 |
| Phase 6 | P0 | 受影响测试更新（_test_24/_test_16/_test_17/_test_33/_test_40）+ 新增用例 | 0.5 天 |
| Phase 7 | P1 | headless 全量单测 + E2E 截图验证 + 实机手测 AC1-AC6 | 0.5 天 |
| Phase 8 | P2 | 血线阶段 enrage（可选，implement 自主决定） | 0.25 天 |

> 合计约 3.25 天（PRD 4 方向 ≈2.5 天 + 防御/弹反差异化追加 ≈0.75 天）。依赖链：Phase 1 → 2 → 3/4/5（可并行）→ 6 → 7；Phase 8 独立可选。

---

## 8. 测试用例描述

> 只描述测试场景，不写可运行代码（测试代码归 implement agent）。新增用例全部 headless（test_combat_judge.gd / test_enemy_ai.gd / test_combat_entity.gd），遵循既有 `_test_N_name` 命名 + `_c("CONST")` 常量读取风格。

### Scenario A: 霸体（PRD 实验 1 —— 打断循环根治）

- **T1（windup 期命中不打断）:** 敌人进入 attack 态且 `_state_elapsed_frames < windup` → 模拟玩家命中（take_damage）→ 断言敌人**仍保持 attack/heavy_attack**（不转 stagger）、HP 已扣、hp_changed 已广播。前置：敌人实体 + 手动设 `_state_elapsed_frames`。预期：霸体生效（修复前该用例红——命中即 stagger）。
- **T2（蓄力重斩 windup 期同理）:** charge 出招（windup=24）后 windup 期内命中 → 不打断；推进 `_state_elapsed_frames ≥ 24` 后再命中 → 进 stagger。前置：charge override 注入。预期：windup 期霸体、收招期可打断（PRD §5.3-1 反向用例兜底）。
- **T3（弹反仍打断蓄力）:** 蓄力期玩家弹反（guard 时间戳在窗口内）→ 断言敌人进入 parry_success 路径（弹反打断霸体）。前置：judge 绑定 + 玩家 guard_pressed 注入。预期：弹反 > 霸体（PRD §5.2-1 硬边界）。
- **T4（收招期可打断）:** windup 结束后（暴发/收招）命中 → 断言转 stagger。前置：同 T1。预期：玩家反击窗口保留。

### Scenario B: 自动面向（PRD 实验 2 —— 站桩挥空根治）

- **T5（facing 相反时自动转向命中）:** 玩家 facing=-1、敌人在右侧（dx>0）、注入 `_auto_face_target` → `_on_bridge_attack_pressed()` → 断言 facing 翻转为 +1 → judge 推进到命中帧 → 断言 hit_landed 触发。前置：judge 绑定 + target 注入。预期：命中成立（修复前 facing=-1 挥空）。
- **T6（无敌人 no-op）:** `_auto_face_target = null` → 攻击 → facing 不变。前置：同 T5 无 target。预期：no-op。
- **T7（攻击中移动 facing 不抖动）:** 攻击转向后 `_bridge_poll` 收到反向移动轴 → 断言 facing 保持攻击方向（非 idle/move 不更新）。前置：模拟输入桥。预期：攻击转向锁成立。

### Scenario C: 停距/击退组合（PRD 实验 3 —— 连段可续）

- **T8（停距缓冲）:** 敌人停距 65px（ENEMY_ATTACK_RANGE）→ 玩家攻击 → `|dx|=65 ≤ HITBOX_RANGE=80` → 命中（修复前 80=80 无缓冲）。前置：常量已改。预期：命中成立。
- **T9（击退缩短后连段）:** headless 模拟：敌人 65px 处被命中 1 次（击退 22px）→ 断言命中后 |dx| ≤ 80（或玩家前移 10px 后恢复命中）；3 次连续命中至少 2 次命中。前置：`_on_judge_hit_landed` 触发。预期：单次击退后仍在可续范围（对比现状 40px 击退 3 次全出范围）。
- **T10（回扑无冷却）:** 击退后敌人进入 Chase → 断言无冷却空窗直接逼近（AttackState 冷却只 gate 出招）。前置：行为 FSM。预期：回扑成立。

### Scenario D: 防御行为（issue body 要素 4 —— 新增）

- **T11（格挡触发）:** 敌人 idle/move + |dx| ≤ 80 + rng_seed 固定 → 玩家进入 attack 前摇 → 断言行为 FSM 进入 guard、实体进入 guard 态。前置：`_on_player_state_changed` + 确定性 RNG。预期：掷骰命中（seed 选取使 randf < 0.4）。
- **T12（格挡判定）:** 敌人 guard 态 → 玩家攻击命中帧 → 断言 judge 走 block_held（敌人扣 POSTURE_BLOCK_COST=10、hit_landed 不发射）。前置：judge 绑定。预期：block 路径生效（judge 既有逻辑零改动验证）。
- **T13（防御退出）:** GuardState 期满（ENEMY_GUARD_HOLD_SECONDS）→ 断言回 idle + Chase。前置：行为 FSM tick。预期：防御有界。
- **T14（防御不触发在 retreat 中）:** 敌人 retreat 行为中玩家攻击 → 断言不进入 guard（_behavior 守卫）。前置：同 T11。预期：路径互斥。

### Scenario E: 差异化前摇 + 弹反窗口/回报（issue body 要素 8/9/10 —— 新增）

- **T15（三级前摇窗口）:** 三选一（seed 固定）分别出招 → 断言 judge 登记窗口 windup_frames：combo=12 / thrust=16 / charge=24。前置：AttackState 注入 + judge 绑定。预期：三级梯度成立（ENEMY_ATTACK_WINDUP < ENEMY_THRUST_WINDUP < ENEMY_CHARGE_WINDUP）。
- **T16（蓄力弹反宽窗）:** charge 攻击 → 玩家 guard 时间戳在 `hit_ms - 0.3s` 边界（比普通窗 0.2s 更早）→ 断言 parry_success 仍触发。前置：judge + 时间戳注入。预期：0.3s 宽窗生效（普通窗 0.2s 该时间点必失败——对比断言）。
- **T17（普通连击窗口不变）:** combo 攻击 → 玩家 guard 在 `hit_ms - 0.2s` 边界 → parry_success；`hit_ms - 0.25s` → 失败。前置：同 T16。预期：普通窗 0.2s fallback 零回归（`_test_1/_test_2` 既有断言保护）。
- **T18（弹反回报差异化）:** charge 弹反 → 敌人 stance 扣 55（PARRY_STANCE_DAMAGE_CHARGE）；combo 弹反 → 扣 35（新默认）。前置：judge + parry 触发。预期：回报与招式匹配。
- **T19（视觉信号约束，表现层）:** 实机/E2E 观察：charge 出招有举刀蓄力姿态、thrust 有前倾信号、combo 短促——三级可读（人工裁决，taste 归 #584）。前置：动画链路（#574）正常。预期：信号可读（不阻塞 CI，E2E 截图证据）。

### Scenario F: 数值平衡（issue body —— 5-7 击崩解）

- **T20（6 击崩解）:** 玩家对敌人连续命中（每次 stance_damage=18）→ 断言第 6 击 stance 归零触发 stance_broken（5-7 击区间内）。前置：POSTURE_HIT_COST=18。预期：5.6 击 → 6 击崩解（修复前 3 击秒杀）。
- **T21（3 次弹反崩解）:** 普通弹反（35）3 次 → stance 归零 → stance_broken。前置：PARRY_STANCE_DAMAGE=35。预期：3 击弹反崩解（更新 `_test_17` 4→3 断言）。

### Scenario G: 回归（R）

- **T22（全量单测）:** `godot --headless --path shandong-wolf -s tests/run_tests.gd` 全绿（既有 ~1314 基线 + 新增/更新用例）。前置：全部 Phase 完成。预期：全绿（含 `_test_24/_test_16/_test_17/_test_33/_test_40` 更新后）。
- **T23（E2E 战斗循环）:** L2 运行时 playthrough：接战→互攻（敌人出招不被普攻锁死）→格挡/弹反博弈→崩解/处决或败北闭环可跑。前置：CI 三层门禁（L0 编译/L1 smoke/L2 playthrough）。预期：闭环成立（issue body AC6）。
- **T24（#718 known limitation 标注）:** 崩解相关用例标注「#718 未修前 stagger→stance_break warning 属 known limitation」——#718 merge 后移除标注。前置：#718 状态确认。预期：测试不因 #718 假红。

---

## 9. 验收条件映射（issue body 6 条 + PRD §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 敌人能稳定出招且威胁感强（普通攻击不无限打断——弹反/闪避才有窗口） | §2.1 霸体（windup 期不打断）+ §2.5 三级前摇 | T1-T4（霸体/弹反打断/收招可打断）+ T15（前摇梯度）+ 实机 |
| AC2 | 玩家 5-7 次有效命中才崩解（只狼双轨节奏） | §2.3 POSTURE_HIT_COST 35→18 | T20（6 击崩解）+ T21（3 次弹反崩解） |
| AC3 | 敌人会追击（脱战会被追上）、会防御（格挡/弹反玩家攻击） | 追击=既有 Chase 无冷却（#581/#703）+ 停距 65 增强压迫；防御=§2.4 GuardState 新增 | T8-T10（停距/击退/回扑）+ T11-T14（防御触发/判定/退出） |
| AC4 | 弹反/格挡/架势崩解/处决全系统有完整可测的博弈循环 | 弹反（差异化窗口/回报 §2.7）+ 格挡（§2.4）+ 崩解（#718 并行）+ 处决（#580 既有） | T16-T18（弹反差异化）+ T12（格挡）+ T23（E2E 闭环） |
| AC5 | 战斗有来有回：玩家需要观察出招、选择应对（弹反/闪避/格挡/输出时机） | 三级前摇可读（§2.5）+ 防御/弹反博弈（§2.4/§2.7） | T15-T19 + 实机手测（用户裁决） |
| AC6 | MVP 战斗闭环可测（接战→博弈→崩解/处决或败北） | 全部组件联动 + 霸体保证互攻成立 | T23（E2E playthrough）+ T22（全量单测） |

---

## 10. 明确不修改（与 PRD §3.3/§6.1/§8 红线对齐）

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

# Design: [Feature] 拼刀 / 弹反 / 架势崩解判定系统（CombatJudge + AttackWindow）

> **Parent Issue:** #577
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4 六决策点**全部确认采纳方案 A** —— ①判定架构 = 独立 CombatJudge 判定器（否决内嵌 CombatEntity：与 #575 既定分层「实体不做判定」逐字一致；否决信号链分散：优先级裁决需全局视图）；②Hitbox/Parry-box 表示 = 逻辑帧窗口 + 距离/facing 校验（否决 Area2D 物理碰撞：#574 sword_arc 注释「零碰撞体、判定归 #577」架构裁决 + 弹反是时间窗无法用物理表达）；③弹反窗口检测 = guard_pressed 时间戳对齐（否决状态位轮询：无法区分按下时机与持续按住）；④拼刀优先级 = CLASH_PRIORITY 显式常量（弹反 > 拼刀 > 格挡 > 受击）；⑤事件契约 = 判定器统一发射五事件（parry_success/block_held/hit_landed/clash/stance_broken 转发）；⑥stance_break 消费 = 转发 #575 信号（统一事件出口）
> **Reference PRD:** `docs/PRD/577-parry-clash-stance-break.md`（research PR #621 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/575-combat-entity-state-machine.md`（CombatEntity 数据容器 + 11 态转移表 guard→parry_success 预留入口 + take_damage/take_stance_damage/break_stance 接口与 stance_broken 信号契约 + 测试写法范本 test_combat_entity.gd）；`docs/DESIGN/573-input-map-player-controller.md`（guard_pressed(timestamp_ms)/guard_held 输入契约）；`docs/DESIGN/574-stick-figure-silhouette-animation.md`（consume_state 11 态动画消费位 + sword_arc 零碰撞体裁决）；`docs/DESIGN/584-combat-tuning-draft.md`（WolfConstants # DRAFT 数值只读 + DebugCanvas 调参面板）
> **所有权:** `content_ownership: mechanical`（判定规则 = 机械工程：优先级枚举 + 时间窗比较 + 事件发射；手感数值全量 # DRAFT **只读不裁决**，新增判定常量同样标 # DRAFT 候选集，定稿归 #584）
> **深度:** deep（PRD 标注 depth: deep；2 新脚本 + 1 新测试文件 + 2 修改文件，跨判定层/常量层/测试三层，且为 #579/#580/#581/#585 的下游事件契约源）—— 产出 **DESIGN + TASKS** 文档
> **并行上下文:** worktree 并行 —— constants.gd 为**追加式新增「判定分区」常量**（不触碰既有 9 分区常量行，与 #584 调参面板无同区改写冲突）；新文件全部独立命名（`combat_judge.gd` / `combat_attack_window.gd` / `test_combat_judge.gd`）；唯一共享文件 = `tests/run_tests.gd`（追加一行 `_run()`；#576/#578/#580/#581/#585 均未开始，无并发改写）

---

## 1. 架构总览

**问题本质是「判定原料全部就绪，裁决者零存在」。** shandong-wolf 经 #573/#574/#575/#584 已具备判定所需的一切：InputController.guard_pressed(timestamp_ms)/guard_held（输入时间戳契约，#573 注释明言「弹反判定归 #6」）、CombatEntity 数据接口（take_damage/take_stance_damage/break_stance + 6 信号，take_damage 在 guard 状态不触发 stagger——调用侧裁决位已预留）、CombatStateTable guard→parry_success 转移入口（注释明言「#577 弹反成功驱动入口」）、WolfConstants 只狼基准常量（PARRY_WINDOW_FRAMES=12 候选 [8,10,12,14]）、StickFigureController.consume_state parry_success 动画消费位、SwordArc（注释明言「节点树无 Area2D/CollisionShape2D/任何碰撞类型，碰撞判定归 #577」）。但 `gdscripts/` 无任何攻击帧窗口描述器、无命中裁决执行者、无五结果事件发射器——**本 issue 交付 = 判定层，是 #579 反馈 / #593 音效 / #580 处决 / #581 敌AI 的唯一事件输入面**。

**设计哲学：判定器 = 事件协调器（不是实体）、窗口 = 时间/帧区间（不是空间体）、优先级 = 显式常量（不是代码顺序）、事件 = 契约（不是内部细节）。**

1. **判定器 = 事件协调器**：CombatJudge 是独立 Node（非 CombatEntity 子类），订阅双方实体 state_changed + 输入 guard_pressed/guard_held → 按优先级裁决 → 调用实体接口（take_damage/take_stance_damage/request_transition）→ 发射结果事件。实体层（#575）与判定层解耦，判定规则可 headless 免树直接单测（PRD AC5 三条路径单一入口可断言）。
2. **窗口 = 帧区间**：攻击命中窗口 = `[FRAME_ATTACK_WINDUP, FRAME_ATTACK_WINDUP + HITBOX_ACTIVE_FRAMES]`（逻辑帧计数，@60fps 派生秒）；弹反窗口 = guard_pressed 时间戳 ∈ `[敌人 hit 帧 - PARRY_WINDOW_SECONDS, 敌人 hit 帧]`（闭区间，只狼基准）。空间真实性 = 命中瞬间距离 + facing 校验（横板一维）。
3. **优先级 = 显式常量**：`CLASH_PRIORITY`（0=弹反优先，默认）——裁决顺序 弹反 > 拼刀 > 格挡 > 受击，全部走常量可调，实现期禁止写死（issue body 明示「拼刀优先级等集中 constants.gd # DRAFT，用户裁决」）。
4. **事件 = 契约**：`parry_success` / `block_held` / `hit_landed` / `clash` / `stance_broken` 五个结果事件是 #579/#574/#593/#580 的唯一输入面，事件名与 issue body 逐字对齐，禁止改名；stance_broken 由 #575 发射 → 本层转发（统一「判定结果从判定器出」）。

```
                    ★ Issue #577 本设计（shandong-wolf 判定层）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 新建（3 文件，全部 shandong-wolf/ 下）                                          │
│  gdscripts/combat_attack_window.gd   AttackWindow 描述器（RefCounted）         │
│                                      —— #581 敌AI 与玩家攻击共用的窗口契约      │
│  gdscripts/combat_judge.gd           CombatJudge（Node，class_name）           │
│                                      —— 窗口登记 → 优先级裁决 → 事件发射        │
│  tests/test_combat_judge.gd          弹反/拼刀/受击 3 主路径 + 冲突矩阵 + 边界  │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（2 文件）                                                                │
│  gdscripts/constants.gd             追加「判定」# DRAFT 分区 5 常量（§2.1）     │
│  tests/run_tests.gd                 追加 _run(test_combat_judge)              │
├──────────────────────────────────────────────────────────────────────────────┤
│ 消费方（0 改动，后续 issue 挂接）                                               │
│  #579 反馈 → 订阅 parry_success/clash/hit_landed/block_held/stance_broken      │
│  #574 动画 → state_changed → consume_state("parry_success")（经 #575 间接）    │
│  #580 处决 → stance_broken 转发事件                                            │
│  #581 敌AI → register_attack_window(AttackWindow)（#581 提供攻击窗口）          │
│  #585 组装 → CombatJudge 实例化 + bind_entities ×2 + bind_input               │
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    ▼
      #573 InputController ──► guard_pressed(ts) / guard_held
      #575 CombatEntity  ──► state_changed(from,to) / stance_broken(entity)
                                    │
                                    ▼
                        CombatJudge（判定协调器）
                         ├─ 实体进入 attack/heavy_attack → 自动登记 AttackWindow
                         ├─ 敌人 hit 帧到达 → resolve_attack(attacker, defender)
                         │    ┌─ 弹反: guard_pressed ts ∈ 弹反窗 + facing 正确
                         │    │     玩家 0 伤害 + 敌人 take_stance_damage(≥20)
                         │    │     + 玩家 request_transition("parry_success")
                         │    │     └─► emit parry_success ──► #579/#574/#593
                         │    ├─ 拼刀: 双方窗口重叠 → 双方 take_stance_damage
                         │    │     └─► emit clash ──► #579/#593
                         │    ├─ 格挡: guard 状态 → take_stance_damage(BLOCK_COST)
                         │    │     └─► emit block_held ──► #579
                         │    └─ 受击: 兜底 → take_damage + take_stance_damage
                         │          └─► emit hit_landed ──► #579
                         └─ stance_broken 转发 ──► emit stance_broken ──► #580/#579
```

**与 PRD 方案裁决的一致性：** PRD §4.1–§4.6 六决策点全部推荐方案 A，本设计逐项确认采纳，无分歧。PRD §7 三个 Spike（弹反窗口时间戳精度 / 拼刀 vs 弹反优先级矩阵 / 事件契约与防重入）的**预期结论已直接内化为本设计决策**：①弹反窗口 = 闭区间含端点（§2.3 边界语义）；②CLASH_PRIORITY=0 弹反优先短路，冲突矩阵 4 组合每种恰好一个结果事件；③事件签名固定 + consumed 防重入幂等。若 Spike 实测推翻任一内化结论，implement 需在 PR 中说明偏离及理由。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实 origin/main b477bc2） | 与 #577 的差距 |
|------|--------------------------------------------------|---------------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ `CombatEntity`（#575/#618 交付）：take_damage（guard 状态不触发 stagger——调用侧裁决位预留）/ take_stance_damage（≤0 → break_stance）/ break_stance（幂等）/ die / revive / request_transition 全接口 + 6 信号（hp_changed/stance_changed/stance_broken/state_changed/died/revived） | 零改动消费：判定器只调用其接口 + 订阅 state_changed/stance_broken |
| `shandong-wolf/gdscripts/combat_state_table.gd` | ✅ 11 态转移表：guard → parry_success 表内，注释明言「#577 弹反成功驱动入口」 | 零改动：request_transition("parry_success") 直接可用 |
| `shandong-wolf/gdscripts/combat_states.gd` | ✅ CombatStateAttack 帧计数三段 phase（0 前摇 / 1 暴发 / 2 收招，WINDUP+RECOVERY 22 帧自动退 idle）+ restart 连段钩子；CombatStateParrySuccess PARRY_SUCCESS_FRAMES 后自动退 idle | 零改动：攻击帧窗口由判定器基于 state_changed + FRAME_ATTACK_WINDUP 派生 |
| `shandong-wolf/gdscripts/input_controller.gd` | ✅ `InputController`（autoload）：guard_pressed(timestamp_ms)（仅时间戳，注释「弹反判定归 #6」）+ guard_held（按住期间每帧） | 零改动：判定器 bind_input 订阅这两信号 |
| `shandong-wolf/gdscripts/constants.gd` | ✅ `WolfConstants` 全量 # DRAFT：PARRY_WINDOW_FRAMES=12（候选 [8,10,12,14]）/ PARRY_WINDOW_SECONDS=0.2 / POSTURE_BLOCK_COST=10 / POSTURE_HIT_COST=35 / PARRY_COST=1.0 / FRAME_ATTACK_WINDUP=8 / FRAME_ATTACK_RECOVERY=14 / FRAME_RHYTHM_BASE=60 / PARRY_SUCCESS_FRAMES=10 / SWORD_DAMAGE_LIGHT=12 / SWORD_DAMAGE_HEAVY=30 | ❌ 缺判定专用常量（弹反架势伤害/拼刀架势成本/攻击判定窗口/距离/方向容差）——追加式新增（§2.1） |
| `shandong-wolf/gdscripts/sword_arc.gd` | ✅ 纯视觉层：注释「节点树无 Area2D/CollisionShape2D/任何碰撞类型，碰撞判定归 #577」 | 不修改：判定层=逻辑帧窗口，非物理碰撞 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | ✅ consume_state 消费 11 态；parry_success → anim_parry_success | 不修改：判定结果经 request_transition("parry_success") 后动画自动跟随 |
| `shandong-wolf/gdscripts/` | ❌ 无判定层：无 CombatJudge、无 AttackWindow、无结果事件发射器 | 本 issue 全部新建（combat_judge / combat_attack_window） |
| `shandong-wolf/tests/run_tests.gd` | ✅ 已挂 7 套件（…/CombatEntity），`_run()` 模式 | ❌ 追加 `_run("res://tests/test_combat_judge.gd", "CombatJudge")` |
| `shandong-wolf/tests/test_combat_entity.gd` | ✅ 判定层测试写法范本（免树直接 new + 手动推进 + `_assert` 模式 + 信号日志） | 测试写法范本（§8） |
| `mini-pong/` | ✅ 视觉体系先例 | 仅作模式参考，**不复制**（跨游戏红线） |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| CombatEntity 已交付 take_damage/take_stance_damage/break_stance + stance_broken 信号，guard 受击不 stagger | ✅ 属实（combat_entity.gd 全接口 + 6 信号；take_damage 在 guard/stagger/stance_break/parry_success/revive 状态不进入 stagger） | 判定器只调用接口 + 订阅信号；受击路径 take_damage + take_stance_damage 双重惩罚由判定器驱动 |
| combat_state_table guard → parry_success 表内，弹反入口已预留 | ✅ 属实（TRANSITIONS["guard"] 含 "parry_success"；idle/move 也含 parry_success） | 弹反成功 → request_transition("parry_success") 原样使用 |
| InputController.guard_pressed(timestamp_ms) 仅含时间戳，弹反判定归本 issue | ✅ 属实（input_controller.gd 注释 + 信号签名） | CombatJudge.bind_input 订阅 guard_pressed（记 ts）+ guard_held（格挡态参考） |
| constants 已含 PARRY_WINDOW_FRAMES/POSTURE_BLOCK_COST/POSTURE_HIT_COST/PARRY_COST | ✅ 属实（全部 # DRAFT 只读） | 只读消费；判定专用 5 常量**尚不存在** → 追加式新增（§2.1） |
| sword_arc.gd 零碰撞体，碰撞判定归 #577 | ✅ 属实（头注释明言） | 判定层 = 逻辑帧窗口 + 距离/facing 校验，不引入任何 Area2D/CollisionShape2D |
| 无判定层（无 CombatJudge/AttackWindow/事件发射器） | ✅ 属实（gdscripts/ 17 文件无任何 combat_judge/attack_window） | 本 issue 全部新建（§2.2/§2.3） |

---

## 2. 新组件 — 详细设计

### 2.1 `gdscripts/constants.gd` — 追加「判定」# DRAFT 分区（修改）

**追加式新增**，新开「判定」分区（置于「受击/敌人/处决」分区之后），不触碰既有常量行。全部 # DRAFT 只读，定稿归 #584：

```gdscript
# ── 判定层（# DRAFT 候补值，待 #584 定稿；#577 消费方，禁止实现期定稿）──
# PARRY_STANCE_DAMAGE
#   只狼基准: 弹反成功大幅涨敌架势（精准格挡的奖励——成功 0 伤害+敌架势大涨）
#   候选集: [20, 25, 30]（默认 25 = 区间中位；AC1 硬约束 ≥20）
#   该值影响什么: 弹反的「爽感」——太小=弹反无价值，太大=几下弹反直接崩解
#   情感断言: 弹反成功必须比格挡爽（只狼铁律 1）
const PARRY_STANCE_DAMAGE: float = 25.0      # # DRAFT
# CLASH_STANCE_COST
#   只狼基准: 拼刀（打铁）双方各扣小架势（互格=节奏博弈，代价低于受击）
#   候选集: [8, 10, 12]（默认 10 = 区间中位）
#   该值影响什么: 拼刀频率与架势续航——太小=无限拼刀，太大=拼刀=慢性自杀
#   情感断言: 打铁的代价是「势均力敌」，不是单方面惩罚
const CLASH_STANCE_COST: float = 10.0        # # DRAFT
# CLASH_PRIORITY
#   只狼基准: 弹反优先于拼刀（玩家精准按出弹反窗口却被拼刀顶掉 = 高操作被低操作覆盖）
#   候选集: [0=弹反优先, 1=拼刀优先]（默认 0；用户实机裁决，改此常量+冲突矩阵断言翻转）
#   该值影响什么: 同帧三重叠时的裁决结果——手感基调的决定性开关
const CLASH_PRIORITY: int = 0                # # DRAFT
# HITBOX_ACTIVE_FRAMES
#   只狼基准: 攻击暴发帧数（挥刀命中判定持续帧；#574 FRAME_ANIM_ATTACK_BURST=4 对齐）
#   候选集: [4, 6, 8]（默认 4 = #574 挥刀暴发帧）
#   该值影响什么: 命中宽容度——窗口越长越容易命中，同时拼刀/弹反判定窗口随之变宽
const HITBOX_ACTIVE_FRAMES: int = 4          # # DRAFT
# HITBOX_RANGE
#   只狼基准: 刀长近身判定（横板一维：攻击者 x 与防御者 x 的水平距离阈值，px）
#   候选集: [60, 80, 100]（默认 80 = SWORD_LENGTH=88 派生近似）
#   该值影响什么: 挥空语义——距离外攻击不命中（AC 未覆盖，挥空=不发射事件）
const HITBOX_RANGE: float = 80.0             # # DRAFT
# PARRY_DIRECTION_TOLERANCE
#   只狼基准: 弹反必须面向攻击（背对挨打=受击）
#   候选集: [1=仅同侧（defender 朝向攻击者）, 2=宽容（前后均可）]（默认 1）
#   该值影响什么: 弹反方向判定的严格度——1 防背身无脑弹反
const PARRY_DIRECTION_TOLERANCE: int = 1     # # DRAFT
```

**注释规范**（沿 #584/#575 先例）：每个常量带「只狼基准 → 候选集 + 该值影响什么 + 情感断言」注释，供 #584 调参面板与用户裁决。**本层不得出现任何字面量数值**（AC4 红线）。

### 2.2 `gdscripts/combat_attack_window.gd` — AttackWindow 描述器（新增）

- **File:** `shandong-wolf/gdscripts/combat_attack_window.gd`
- **Type:** `class_name AttackWindow extends RefCounted`（纯数据描述器，无节点、无逻辑分支，headless 免树 new）
- **职责:** 一次攻击的命中判定窗口契约——#581 敌AI 与玩家攻击共用；CombatJudge 消费 `is_active(frame)` 判定命中帧
- **State Properties:**

```gdscript
class_name AttackWindow
extends RefCounted

var attacker: CombatEntity   # 攻击者引用（判定器据此路由 take_damage/take_stance_damage）
var start_frame: int         # 攻击开始帧（进入 attack/heavy_attack 状态帧，判定器逻辑帧计数）
var active_frames: int       # 判定有效帧数（HITBOX_ACTIVE_FRAMES # DRAFT）
var hp_damage: float         # 命中 HP 伤害（玩家用 SWORD_DAMAGE_LIGHT/HEAVY；敌人用 #581 AI 配置）
var stance_damage: float     # 命中架势伤害（POSTURE_HIT_COST # DRAFT）
var direction: int           # 攻击方向（-1/1 = 攻击者 facing 快照；命中瞬间 facing 校验用）

## 命中判定帧区间（闭区间，@60fps 逻辑帧）:
##   hit_frame = start_frame + FRAME_ATTACK_WINDUP
##   有效区间 = [hit_frame, hit_frame + active_frames]
func hit_frame() -> int
func is_active(frame: int) -> bool   # frame ∈ [hit_frame, hit_frame + active_frames]
func is_expired(frame: int) -> bool  # frame > hit_frame + active_frames（判定器据此清理）
```

- **Key Methods:** `hit_frame()`（= start_frame + FRAME_ATTACK_WINDUP，常量驱动）、`is_active(frame)`（闭区间含端点）、`is_expired(frame)`。
- **Integration notes:** 由 CombatJudge `register_attack_window(w)` 登记；#581 敌AI 在攻击前摇期间构造并登记（PRD §8.3 契约）；玩家攻击窗口由 CombatJudge 在 state_changed→attack/heavy_attack 时自动构造（hp_damage 取 SWORD_DAMAGE_LIGHT/HEAVY，direction 取 entity.facing 快照）。

### 2.3 `gdscripts/combat_judge.gd` — CombatJudge 判定协调器（新增）

- **File:** `shandong-wolf/gdscripts/combat_judge.gd`
- **Type:** `class_name CombatJudge extends Node`（非 autoload——#585 组装时实例化进场景，测试直接 new + 手动 tick）
- **职责（单一）:** 攻击窗口登记 → 命中裁决（弹反→拼刀→格挡→受击）→ 调用实体接口 → 发射五结果事件。**不做渲染/演出/音效**（#579/#593），**不做状态机/数据存储**（#575），**不做输入采集**（#573）。
- **Signals（事件契约，与 issue body 逐字对齐，禁止改名）:**

```gdscript
signal parry_success(defender: CombatEntity, attacker: CombatEntity, stance_damage: float)
signal block_held(defender: CombatEntity, attacker: CombatEntity, stance_cost: float)
signal hit_landed(defender: CombatEntity, attacker: CombatEntity, hp_damage: float, stance_damage: float)
signal clash(entity_a: CombatEntity, entity_b: CombatEntity, stance_cost: float)
signal stance_broken(entity: CombatEntity)   # 转发 #575 信号（统一事件出口）
```

- **State Properties:**

```gdscript
var player: CombatEntity          # bind_entities 注入（防御者=玩家，弹反/格挡/受击裁决对象）
var enemy: CombatEntity           # bind_entities 注入（攻击者=敌人，MVP 单敌）
var _ic: Object = null            # InputController 引用（bind_input 注入；headless 可 null）
var _frame: int = 0               # 逻辑帧计数（_process 推进；headless 测试手动 tick_frame()）
var _windows: Array = []          # 活跃 AttackWindow 列表（按 attacker 去重）
var _last_guard_press_ms: int = -1  # 最近 guard_pressed 时间戳（弹反窗口比对）
var _forwarded_stance_break: Dictionary = {}  # 实体 → 已转发标记（stance_broken 幂等转发）
var _resolved: Dictionary = {}    # "attacker:defender:frame" → true（防重入/防双罚）
```

- **Key Methods（签名 + 逻辑要点）:**

```gdscript
func bind_entities(p: CombatEntity, e: CombatEntity) -> void
    ## 保存引用 + 订阅双方 state_changed（登记玩家攻击窗口）/ stance_broken（转发）
func bind_input(ic: Object) -> void
    ## 订阅 guard_pressed(timestamp_ms)（记 _last_guard_press_ms）/ guard_held（格挡参考，MVP 可用 state_name 代替）
func register_attack_window(w: AttackWindow) -> void
    ## 登记窗口：同 attacker 已有窗口 → 旧窗口作废（连段/重攻击覆盖语义）；窗口加入 _windows
func resolve_attack(attacker: CombatEntity, defender: CombatEntity) -> void
    ## 幂等裁决入口（防重入键 "attacker:defender:frame"；已裁决 → no-op）
    ## 裁决顺序（全部走常量，禁止写死）:
    ##   1. 弹反: _last_guard_press_ms ∈ [hit_ms - PARRY_WINDOW_SECONDS*1000, hit_ms]
    ##            且 facing 校验通过（PARRY_DIRECTION_TOLERANCE）
    ##      → 玩家不调 take_damage（0 伤害）；enemy.take_stance_damage(PARRY_STANCE_DAMAGE)
    ##      → player.request_transition("parry_success")（#575 表内合法）
    ##      → emit parry_success(defender, attacker, PARRY_STANCE_DAMAGE)
    ##   2. 拼刀: CLASH_PRIORITY==0 时弹反短路后；双方窗口同帧 active（窗口重叠）
    ##      → 双方 take_stance_damage(CLASH_STANCE_COST)；emit clash(a, b, CLASH_STANCE_COST)
    ##   3. 格挡: defender.state_name == "guard"（guard_held 语义，含弹反失败后的持续格挡）
    ##      → defender.take_stance_damage(POSTURE_BLOCK_COST)（不扣血）；emit block_held
    ##   4. 受击: 兜底
    ##      → defender.take_damage(window.hp_damage) + take_stance_damage(window.stance_damage)
    ##      → emit hit_landed(defender, attacker, hp, stance)
func _process(_delta: float) -> void
    ## _frame += 1；遍历 _windows：命中帧到达（is_active）→ resolve_attack(attacker, defender)；
    ## 过期窗口（is_expired）→ 清理
func tick_frame() -> void
    ## headless 测试手动推进（免 SceneTree 帧循环）
func _on_entity_state_changed(entity: CombatEntity, from: String, to: String) -> void
    ## to ∈ {"attack", "heavy_attack"} → 自动构造 AttackWindow 登记（玩家；敌人 MVP 由 #581/测试登记）
func _on_guard_pressed(timestamp_ms: int) -> void
    ## 记录 _last_guard_press_ms（同帧多次按下取最后一次——帧级去抖）
func _on_guard_held() -> void
    ## MVP 参考信号（格挡态判定可直接读 defender.state_name == "guard"，保留订阅以备 #584 细化）
func _on_stance_broken(entity: CombatEntity) -> void
    ## 幂等转发: _forwarded_stance_break[entity] 已置位 → no-op；否则 emit stance_broken(entity)
```

- **Integration notes:**
  - 弹反成功后 `request_transition("parry_success")`：玩家此刻必在 guard 态（guard_pressed 输入桥已转移），guard→parry_success 表内合法；若 #585 组装时序导致玩家在 idle 态弹反，idle→parry_success 同样表内合法——双保险。
  - 弹反成功玩家**不调 take_damage**（0 伤害语义，AC1）；PARRY_COST（弹反扣自身架势 0-2 候选）MVP 阶段**不施加**（# DRAFT 候补，施加时机归 #584 定稿后 #585 组装裁决）——DESIGN 明确此裁决，避免实现期偷加。
  - 敌人攻击窗口 MVP 由测试构造驱动（#581 未实现）；CombatJudge 对「未登记窗口的命中」no-op + push_warning（PRD 失败路径 1）。
  - 事件无订阅方时安全（Godot 信号无订阅不报错，#579/#593 未实现期间的预期状态）。

---

## 3. 既有组件修改

### 3.1 新文件

| 文件 | 内容 | 依据 |
|------|------|------|
| `shandong-wolf/gdscripts/combat_attack_window.gd` | AttackWindow 描述器（RefCounted）：attacker/start_frame/active_frames/hp_damage/stance_damage/direction + hit_frame()/is_active()/is_expired() | §2.2 |
| `shandong-wolf/gdscripts/combat_judge.gd` | CombatJudge（Node，class_name）：bind_entities/bind_input/register_attack_window/resolve_attack/_process/tick_frame + 5 结果事件信号 + 防重入 | §2.3 |
| `shandong-wolf/tests/test_combat_judge.gd` | 测试套件：弹反/拼刀/受击 3 主路径 + 冲突矩阵 + 窗口边界 + 事件契约/防重入 + 失败路径 | §8 |

### 3.2 修改文件

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `shandong-wolf/gdscripts/constants.gd` | 追加「判定」# DRAFT 分区 5 常量：PARRY_STANCE_DAMAGE=25（候选 [20,25,30]）/ CLASH_STANCE_COST=10（候选 [8,10,12]）/ CLASH_PRIORITY=0（候选 [0,1]）/ HITBOX_ACTIVE_FRAMES=4（候选 [4,6,8]）/ HITBOX_RANGE=80（候选 [60,80,100]）/ PARRY_DIRECTION_TOLERANCE=1（候选 [1,2]），注释含只狼基准+候选集+影响+情感断言 | AC4：判定数值全部 constants 化，禁字面量；#584 调参面板消费 |
| `shandong-wolf/tests/run_tests.gd` | 追加 `_run("res://tests/test_combat_judge.gd", "CombatJudge")`（置于 CombatEntity 之后） | 套件注册（#572 挂载模式） |

### 3.3 移除/弃用文件

无（纯新增 + 追加修改）。

### 3.4 受影响的测试文件

| 文件 | 变更性质 |
|------|---------|
| `shandong-wolf/tests/test_combat_judge.gd` | **新增**（§8 全部用例；测试写法沿用 test_combat_entity.gd：extends Object + passed/failed + `_assert` + 信号日志 + 免树直接 new + 手动 tick_frame 推进，不依赖真实帧/物理） |
| `shandong-wolf/tests/run_tests.gd` | 追加一行 `_run()` 注册（不改动既有 7 行） |
| 既有 7 套件 | **零改动**（防回归：run_tests.gd 全量跑） |

---

## 4. 数据流

### Flow 1：弹反成功（AC1 正常路径）

```
1. 敌人进入 attack 态（#581 或测试）→ CombatJudge._on_entity_state_changed → 登记 AttackWindow(start_frame=F, direction=enemy.facing)
2. 玩家按下格挡 → InputController emit guard_pressed(ts) → CombatJudge._on_guard_pressed 记录 _last_guard_press_ms=ts
   （同时 #575 输入桥 request_transition("guard")，玩家进入 guard 态）
3. CombatJudge._process 帧推进至 hit_frame = F + FRAME_ATTACK_WINDUP → 窗口 is_active → resolve_attack(enemy, player)
4. 裁决: ts ∈ [hit_ms - PARRY_WINDOW_SECONDS*1000, hit_ms]（闭区间）且 facing 校验通过
5. 执行: player 不调 take_damage（0 伤害）; enemy.take_stance_damage(25)
        → enemy stance 扣减 → 若 ≤0 → break_stance → stance_broken 转发（Flow 5）
        player.request_transition("parry_success") → state_changed(idle→parry_success) → #574 consume_state
6. emit parry_success(player, enemy, 25) ──► #579 弹反四要素 / #593 ding
```

### Flow 2：拼刀（AC2 正常路径）

```
1. 双方均进入 attack 态 → 各登记 AttackWindow（start_frame 相同或重叠）
2. 某帧双方窗口同时 is_active → resolve_attack 轮询
3. 裁决: 弹反检查失败（无 guard_pressed 或 ts 在窗口外）→ CLASH_PRIORITY==0 短路后查重叠 → clash
4. 执行: 双方 take_stance_damage(CLASH_STANCE_COST=10)；emit clash(player, enemy, 10)
```

### Flow 3：格挡（guard_held 正常路径）

```
1. 玩家按住格挡（guard_pressed 已过但未弹反成功 / 或长按）→ 玩家 state_name == "guard"
2. 敌人 hit 帧到达 → resolve_attack → 弹反失败（ts 超窗）+ 无 clash（玩家无攻击窗口）
3. 裁决: defender.state_name == "guard" → block_held
4. 执行: player.take_stance_damage(POSTURE_BLOCK_COST=10)（不扣血）；emit block_held(player, enemy, 10)
```

### Flow 4：受击（兜底路径，AC5-3）

```
1. 敌人 hit 帧到达 → resolve_attack → 弹反失败 + 无 clash + 非 guard 态
2. 执行: player.take_damage(window.hp_damage) + take_stance_damage(POSTURE_HIT_COST=35)
        → hp 扣减（≤0 → die → died 信号）；stance 扣减（≤0 → break_stance）
        → #575 take_damage 使 idle/move/attack/heavy_attack 态进入 stagger
3. emit hit_landed(player, enemy, hp_damage, 35) ──► #579 受击反馈
```

### Flow 5：架势崩解转发（AC3）

```
1. 任意实体 stance ≤ 0 → #575 break_stance()（幂等）→ emit stance_broken(entity)（#575 侧）
2. CombatJudge._on_stance_broken(entity) → _forwarded_stance_break 检查（幂等）→ emit stance_broken(entity)
3. ──► #580 处决通道 / #579 全屏淡白闪
```

### Flow 6：防重入（PRD 实验 3）

```
1. resolve_attack(attacker, defender) 被同一帧第二次调用（信号重入/多订阅方）
2. 防重入键 "attacker:defender:_frame" 已存在 → no-op（每次命中恰好一次裁决，防双罚）
3. 窗口过期（is_expired）→ 从 _windows 移除 → 后续帧不再触发
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| 弹反窗口边界（闭区间） | guard_pressed ts 恰在 hit_ms 或 hit_ms - PARRY_WINDOW_SECONDS*1000 → 视为窗口内（闭区间含端点）；窗口外 1ms → 不弹反（PRD 实验 1 四时间点断言） |
| 拼刀 vs 弹反同帧三重叠 | CLASH_PRIORITY==0 → 弹反优先短路（先查弹反再查重叠）；断言结果 parry_success 而非 clash（冲突矩阵 Test） |
| 弹反失败后持续格挡 | guard_pressed 触发弹反判定失败 + guard 态仍成立 → 走格挡裁决（block_held），不重复受击；同一次敌人命中只裁决一次（_resolved 防双罚） |
| 无敌期受击 | player revive 无敌期（INVINCIBLE_SECONDS）内敌人命中 → 判定器 no-op（不发射 hit_landed）；#575 take_damage 本身也 no-op（双保险） |
| dead/revive/execute 态受击 | defender 处于 dead/revive/execute → 判定器跳过该实体（#575 侧 no-op 兜底 + 判定器守卫） |
| stance 溢出单次崩解 | enemy stance=5 时弹反 25 → #575 take_stance_damage clamp + 单次 break_stance + 判定器幂等转发 stance_broken（不双发） |
| 多敌（未来） | 每对 (attacker, defender) 独立裁决，按事件顺序发射；MVP 单敌（_windows 支持多窗口，扩展天然成立） |
| 距离挥空 | 命中瞬间 abs(attacker.x - defender.x) > HITBOX_RANGE 或 facing 相反 → 不命中（hit_landed 不发射；窗口正常过期） |
| facing 翻转 | 窗口登记时 direction 快照；命中瞬间 defender facing 已翻转 → 按命中瞬间 facing 裁决（弹反方向判定用实时 facing） |
| 双攻击窗口（连段） | 同 attacker 新窗口登记 → 旧窗口作废（register_attack_window 覆盖语义）；同态重入（attack→attack）不广播 state_changed（#575 已知限制）→ MVP 单段攻击窗口由 hit 帧一次性裁决，连段二次登记归 #581/#585 组装（DESIGN 明确此限制，implement 不硬解） |
| 未注册窗口收到命中 | resolve_attack 找不到 attacker 的活跃窗口 → no-op + push_warning（不凭空判定） |
| guard_pressed 无敌人攻击 | 玩家按下格挡但无攻击窗口 → 无裁决（guard 态由 #575 输入桥管理，判定器不干预） |
| 判定器未 bind 实体 | bind 前 resolve 调用 → no-op + push_warning（防 NPE） |
| 事件重复发射 | _resolved 防重入键（"attacker:defender:frame"）+ stance_broken 转发幂等标记——每次命中恰好一次事件 |
| 数值异常 | PARRY_WINDOW 为 0/负 → 常量防御（#584 候选集约束 + push_warning） |
| 同帧多次 guard_pressed | 帧级去抖：_last_guard_press_ms 取最后一次按下（PRD 实验 1 结论） |

---

## 6. 集成点

> **Status 约定:** ⬜ = 待接线（资源已创建，未连目标）; ✅ = 已连接（implement agent 核实）。implement 必须更新此表；review agent 合并前验证全部 ⬜ 已解决或显式推迟。

| 集成 | 本层组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| 判定输入 | CombatJudge._on_guard_pressed/_on_guard_held | #573 InputController | bind_input(ic) 订阅 guard_pressed(timestamp_ms)/guard_held | ⬜ 待接线（#585 组装） |
| 实体数据 | CombatJudge → CombatEntity 接口 | #575（已合并） | bind_entities + take_damage/take_stance_damage/request_transition + state_changed/stance_broken 订阅 | ✅ 本层实现内完成 |
| 弹反动画 | request_transition("parry_success") → state_changed → consume_state | #574（已合并） | 经 #575 状态转移间接消费（anim_parry_success） | ✅ 契约对齐（本层只发转移） |
| 反馈消费 | parry_success/clash/hit_landed/block_held/stance_broken 信号 | #579 反馈（未开始） | #579 订阅五事件 → 反馈矩阵（火花/hit-stop/屏震） | ⬜ 事件契约已定，订阅待 #579 |
| 音效消费 | parry_success ding / clash 金属声 | #593 音效（未开始） | 经 #579 反馈事件联动 | ⬜ 待 #593 |
| 处决通道 | stance_broken 转发事件 | #580 处决（未开始） | #580 订阅 stance_broken → 处决驱动 | ⬜ 待 #580 |
| 敌AI 窗口 | register_attack_window(AttackWindow) | #581 敌AI（未开始） | #581 攻击前摇期间构造窗口登记；MVP 测试构造驱动 | ⬜ 契约已定，实现待 #581 |
| 组装 | CombatJudge 实例化 + bind_entities ×2 + bind_input | #585 组装（未开始） | #585 场景实例化 + 信号桥接 | ⬜ 待 #585 |

---

## 7. 实现阶段

| Phase | 优先级 | 组件 | 预估 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | constants.gd 追加「判定」分区 6 常量（§2.1） | 0.5 天 |
| Phase 2 | P0 | combat_attack_window.gd（AttackWindow 描述器） | 0.5 天 |
| Phase 3 | P0 | combat_judge.gd（裁决器核心：bind/register/resolve/五事件/防重入） | 1.5 天 |
| Phase 4 | P0 | test_combat_judge.gd（§8 全部用例）+ run_tests.gd 注册 | 1 天 |
| Phase 5 | P1 | 全量回归（run_tests.gd 8 套件）+ PR 附开源调研结论 | 0.5 天 |

依赖序：P1→P2→P3（judge 依赖 window + constants）；P4 依赖 P2/P3；P5 收尾。测试先行（TDD red）：combat_judge.gd 不存在时 load() 返回 null → 断言失败（red），避免整文件解析错误。

---

## 8. 测试用例描述

> **测试文件：** `shandong-wolf/tests/test_combat_judge.gd`（挂载 run_tests.gd；测试写法沿用 test_combat_entity.gd 模式：extends Object + passed/failed + `_assert` + 信号日志 + 免树直接 new + `tick_frame()` 手动推进，不依赖真实帧/物理）。**只写描述，不写可运行测试代码（implement agent 职责）。**

### Scenario A：弹反成功路径（AC1 + PRD 实验 1）
- Test 1 窗口内弹反：敌人 AttackWindow(hit_frame=T)，玩家 guard_pressed 在 T-0.2s（闭区间下界）→ resolve → 玩家 hp 不变（0 伤害）+ 敌人 stance 扣 PARRY_STANCE_DAMAGE（≥20）+ 玩家 state=parry_success + parry_success 事件恰好一次（参数 defender=player, stance_damage=25）
- Test 2 窗口终点弹反：guard_pressed 恰在 hit_ms（闭区间上界）→ 同上成功
- Test 3 窗口外 1ms 失败：guard_pressed 在 hit_ms+1ms → 不弹反（走后续裁决，见 Scenario C）
- Test 4 窗口外 201ms 失败：guard_pressed 在 hit_ms-201ms → 不弹反
- Test 5 同帧多次按下取最后：同帧两次 guard_pressed，第二次在窗口内 → 弹反成功（帧级去抖）

### Scenario B：拼刀路径（AC2 + PRD 实验 2 冲突矩阵）
- Test 6 双方窗口重叠 → clash：玩家+敌人窗口同帧 active，无 guard_pressed → 双方 stance 各扣 CLASH_STANCE_COST + clash 事件恰好一次
- Test 7 冲突矩阵 4 组合：弹反+拼刀（三重叠）→ parry_success（弹反优先）；拼刀+格挡 → clash；弹反+格挡 → parry_success；三重叠 → parry_success——每种组合恰好一个结果事件（CLASH_PRIORITY==0 断言）
- Test 8 CLASH_PRIORITY=1 翻转：改常量后三重叠 → clash（断言随常量翻转，验证「裁决顺序必须走常量」红线）
- Test 9 窗口不重叠 → 无 clash：玩家窗口已过期时敌人命中 → 不发射 clash

### Scenario C：格挡与受击路径（AC5-3 + 边界）
- Test 10 格挡：guard_pressed 超窗 + 玩家 state=guard → block_held（扣 POSTURE_BLOCK_COST 不扣血）
- Test 11 弹反失败转格挡：guard_pressed 超窗 1ms + 按住（guard 态）→ block_held 而非受击（防双罚：恰好一次事件）
- Test 12 未格挡受击：无 guard → take_damage(hp_damage) + take_stance_damage(POSTURE_HIT_COST) + hit_landed 事件（参数 hp/stance 正确）
- Test 13 距离挥空：abs(attacker.x - defender.x) > HITBOX_RANGE → 不发射 hit_landed（窗口正常过期）
- Test 14 facing 校验：PARRY_DIRECTION_TOLERANCE=1 且 defender 背对攻击 → 弹反失败 → 走受击

### Scenario D：架势崩解与事件契约（AC3 + PRD 实验 3）
- Test 15 崩解转发：敌人 stance=5，弹反 25 → #575 break_stance → 判定器转发 stance_broken 恰好一次（幂等）
- Test 16 转发幂等：同一实体 stance_broken 二次到达 → 不二次转发
- Test 17 事件签名契约：五事件发射参数与 §2.3 契约逐字一致（实体引用/数值类型）
- Test 18 防重入：同一命中 resolve_attack 连调两次 → 第二次 no-op（结果事件恰好一次，防双罚）
- Test 19 未注册窗口命中：resolve_attack 无活跃窗口 → no-op + push_warning

### Scenario E：边界/失败路径（§5 + PRD §5.3）
- Test 20 无敌期命中：player 无敌期（INVINCIBLE_SECONDS 内）→ 判定器 no-op（无 hit_landed）
- Test 21 dead 实体命中：defender 处于 dead → 跳过（无事件）
- Test 22 判定器未 bind：resolve 调用 → no-op + push_warning（防 NPE）
- Test 23 窗口覆盖：同 attacker 二次登记 → 旧窗口作废新窗口生效（连段语义）
- Test 24 数值全部来自 constants：断言判定路径中无字面量（code review 项；改 PARRY_STANCE_DAMAGE 常量 → 判定结果随动）
- Test 25 全量回归：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 8 套件全绿（含既有 7 套件防回归）

---

## 9. 验收条件映射（源自 Issue #577 body）

| # | 验收条件 | 本设计保障 | 覆盖用例 |
|---|---------|-----------|:-------:|
| AC1 | 玩家在弹反窗口内被攻击命中时，受到 0 伤害且对攻击者造成 ≥20 架势伤害（数值来自 constants.gd） | §2.3 弹反路径：不调 take_damage + take_stance_damage(PARRY_STANCE_DAMAGE=25 ≥20) + request_transition("parry_success") | T1-T5 |
| AC2 | 双方攻击判定重叠时触发 clash 拼刀，双方均收到小架势伤害且事件信号发出 | §2.3 拼刀路径：双方 take_stance_damage(CLASH_STANCE_COST) + emit clash | T6-T9 |
| AC3 | 敌人架势值归零时进入 stance_break 状态并广播信号 | §2.3 stance_broken 转发（#575 幂等广播 + 本层统一事件出口） | T15-T16 |
| AC4 | 弹反窗口、架势数值全部从 constants.gd 读取，PR 中说明调参候选 | §2.1 判定分区 6 常量全 # DRAFT 候选集；§2.3 零字面量 | T24 |
| AC5 | 单元测试覆盖：弹反成功/拼刀/未弹反受击 三条判定路径 | §8 Scenario A/B/C | T1-T14 |

---

## 10. 明确不修改（与 PRD §8.5 红线对齐）

- ❌ 不引入 Area2D/CollisionShape2D 物理碰撞（#574 零碰撞体架构裁决；PRD §6.2 调研结论：开源 hitbox 生态全部物理模式，与时间窗语义冲突）
- ❌ 不修改 #575 已合并的 combat_entity.gd / combat_state_table.gd / combat_states.gd 接口（只消费信号与调用接口；guard→parry_success 入口原样使用）
- ❌ 不裁决 # DRAFT 数值（只读 constants；新常量也标 # DRAFT 候选集，定稿归 #584；PARRY_COST 施加时机推迟至 #584 定稿后）
- ❌ 不改结果事件名（parry_success/block_held/hit_landed/stance_broken/clash 与 issue body 逐字对齐）
- ❌ 不写死裁决优先级（必须走 CLASH_PRIORITY 常量）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不修改 scenes/Main.tscn（标题场景红线）
- ❌ 不写实现代码/测试代码（本 phase 仅 DESIGN + TASKS 文档；测试代码归 implement agent）
- ❌ 不做渲染/演出/音效（#579 反馈矩阵 / #593 音效；本层只发射事件）
- ❌ 不消费动画（#574 consume_state 经 #575 state_changed 自动跟随，本层不直接调用）

## 附：开源调研结论（PRD §6.2 已调研，implement PR 须附说明）

PRD §6.2 结论直接引用：Godot hitbox/hurtbox 生态（cluttered-code/godot-health-hitbox-hurtbox 169⭐、GDQuest 教学 demo 等）全部为 **Area2D/Area3D 物理碰撞模式**——与 #574「零碰撞体、判定归 #577」架构裁决冲突，且**无法表达弹反时间窗**（guard_pressed 时间戳 vs 攻击帧对齐）；parry 相关仓库（parry-shmup/parry-pong 等）全部 0-2⭐ 个人习作无复用价值 → **自研 CombatJudge 逻辑帧窗口判定层**（issue body 允许「找不到再自行实现」）。implement PR 须引用本调研结论，无需重复调研。

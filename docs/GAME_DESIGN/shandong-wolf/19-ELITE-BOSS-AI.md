# 精英 Boss AI — 参数档位 + 蓄力重斩 + 受击击退 + 架势脱战恢复 + EnemyHealthBar（#682/#695）

> 落盘依据：PR #695（implement，squash-merge 2026-08-21, commit 608f8e2）← DESIGN `docs/DESIGN/682-elite-boss-ai.md`（plan #690 已 merge）← PRD `docs/PRD/682-elite-boss-ai.md`（research #687 已 merge）。
> 增量：#703/#710（2026-08-21）落地运行时驱动链——`_physics_process` 先 decide 后 `_apply_movement`，击退与决策门控的正交性（§4 第 4 条）由驱动链结构性保证（decide 门控提前 return 不影响 `_apply_movement` 无条件可达），详见 13 章 §13。
> 上游：#581/#638 EnemyAI 四态行为 FSM 与判定层参数化（13 章，精英化基底）、#575/#618 CombatEntity 数据模型与 6 信号（08 章）、#577/#626 CombatJudge 双轨伤害与自动窗口登记（11 章）、#576/#627 HUD 与 _HudBar 自绘条（10 章）、#585/#666 战斗闭环组装（17 章）、#580/#660 处决编排器（16 章，零改动消费）。
> 所有权：`content_ownership: mechanical` —— AI 出招概率 / HP 双轨 / 击退位移 / 架势恢复 = 机械工程；**全部新数值 # DRAFT 只读不裁决**，候选集移交 #584 调参面板定稿；EnemyHealthBar 视觉色相按 #576 既有风格 additive 实现，用户定稿差异走 #576 human-review 通道。

## 1. 设计意图

**问题本质是「战斗数据模型与行为层原料全部就绪，但精英感（血量存在感 + 变招 + 受击反馈 + 节奏阀）五处断点」。** #585 组装后敌人「能动、能打、能被打、能崩解」——但 HP 慢线数据模型（`life_1_max`）存在却从未被装配消费（`ENEMY_HP_MAX=40` 常量定义了没人读，`life_1_max` 走默认 100）、无敌人血条 UI（玩家感知「无血量概念」）、攻击组缺蓄力形态（只有突刺/三连砍）、受击缺击退位移（只有 12 帧硬直）、架势无脱战恢复（不被打就一直满架）。用户 8-21 实机反馈「敌人一击毙命 + 无 AI 无法测试战斗」即源于此。

**设计哲学：精英是小兵 AI 的参数档位，不是新类；双轨击杀 = 只狼铁律（处决是奖励不是补刀）；一切增量走信号/参数，不碰判定与处决层。**

1. **精英 = 参数档位 + 行为增量，绝不重写**（#575「差异通过参数配置」契约字面对齐）：EnemyAI 新增 `@export elite_mode: bool = false`——装配时置 true → AttackState 出招三选一（+蓄力重斩）；HP/架势由装配注入 CombatEntity 参数；击退/恢复为独立 additive 机制。小兵档位（`elite_mode=false`）行为与 #581 逐字节一致，既有 36 条 AI 测试回归全绿。
2. **双轨击杀成立（HP 慢线 / 架势快线）**：慢线 = 装配消费 `ENEMY_HP_MAX`（80）+ EnemyHealthBar 可视化，轻击 12/刀 → 7 刀削死（`die()` 终态）；快线 = 4 次弹反（25×4=100）崩解 → #580 处决窗口 → 处决一击（999）。弹反高手速杀 < 稳健玩家磨刀——只狼式「快线奖励技术」。
3. **蓄力重斩 = 长前摇可弹反重击**：AttackState 掷骰三选一；复用 `AttackWindow.windup_frames` 契约（#581 已交付字段），**但注入点需要新增**——`CombatJudge._on_entity_state_changed` 对敌人硬编码 `windup_frames = ENEMY_ATTACK_WINDUP`、`hp_damage = entity.attack_hp_damage`（单值）。设计裁决：CombatEntity 新增 2 个瞬时 override 字段（默认 -1 兜底 = #581 行为不变），蓄力出招前设置、judge 登记时读取。
4. **受击后退 = 位移层击退**：EnemyAI 订阅 `judge.hit_landed`（defender == 本敌人，与既有 parry_success 订阅同构）→ 沿受击反向设置 `_knockback_vel`，stagger 期间线性衰减位移（`ENEMY_KNOCKBACK_DECAY`），与 12 帧硬直叠加成「僵直+后退」完整反馈；位移执行在 `_apply_movement`（与决策门控正交——硬直中 AI 不决策但击退仍执行；#703/#710 驱动链落地后由 `_physics_process` 先 decide 后 _apply_movement 结构性保证），与 #579 反馈渲染（火花/屏震）分层正交。
5. **架势脱战恢复 = 节奏阀**：CombatEntity `_process` 轮询（仅 `is_player=false` 且未崩解且超延迟窗口）→ 按 `ENEMY_STANCE_RECOVER_PER_SEC` 恢复至 stance_max；`take_stance_damage` 重置延迟计时——只狼铁律 4「回复太快=无脑弹反，太慢=龟缩」，sekiro 基准 1.5s/20-35 per/s 放宽候选。
6. **Boss 条 = EnemyStanceBar 组合扩展**：hud.gd 新增 `EnemyHealthBar`（同锚点顶部中央，240×10 暗红粗条，位于 EnemyStanceBar 上方），复用 `_HudBar` 自绘组件 + 新增 `set_fill_color` additive 覆写（默认行为零变化）；`set_target_enemy` 订阅 `hp_changed`，died 双条联动隐藏。

**方案裁决**：方案 A（精英 = EnemyAI 参数档位 + 行为增量 + 数据/UI additive 补丁，不新建类）采纳；否决方案 B（独立 EliteBossAI 双类并存——违反 #575「差异通过参数配置」契约 + 双份维护）与方案 C（提前实现 #589 军曹内容——issue 边界红线 + 危攻击不可弹反与 issue「可弹反的蓄力攻击」矛盾），理由同 PRD §4.2/§4.3。

## 2. 架构决策

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|--------------|---------|---------|
| 精英架构 | EnemyAI.elite_mode 参数档位 + 装配注入 HP | 独立 EliteBossAI 双类 | #575「差异通过参数配置」契约 + 双份维护 |
| HP 慢线 | 装配消费 ENEMY_HP_MAX（40→80 候选上调） | 保持 40 | AC5「多次攻击才能击杀」；life_1_max 首次被装配消费 |
| 蓄力注入 | CombatEntity 瞬时 override ×2（windup/hp_damage fallback 链） | 改 judge 硬编码分支 | PRD §8.3 假设「entity 携带 windup」在代码库不存在（gap 1/2）；additive 默认 -1 兜底 #581 逐字节一致 |
| 受击击退 | EnemyAI hit_landed 订阅 → 位移层击退（衰减 + clamp） | 改 #579 反馈渲染层 | 位移层与渲染层正交，事件源共用 hit_landed |
| 脱战恢复 | CombatEntity._process 轮询（仅 is_player=false） | 改玩家架势语义 | 玩家实体行为零变化（回归全绿） |
| 敌人血条 | _HudBar 复用 + set_fill_color additive 覆写 | 新自绘类 | #576 同构复用；默认 fill 行为零变化（玩家两条不受影响） |
| 速度/冷却 | MVP 维持 #581 默认（追击 180 px/s、冷却 1.5s） | 新增精英速度/冷却常量 | PRD §8.2 交付物清单无此两项（gap 3 范围收敛）；候选记入 #584 候选池 |

## 3. 精英参数档位（EnemyAI.elite_mode + 精英常量组）

文件：`shandong-wolf/gdscripts/enemy_ai.gd`（修改）+ `constants.gd`（新增「精英 AI」分区）。

```gdscript
# enemy_ai.gd
@export var elite_mode: bool = false   # true → 读精英常量组（蓄力出招启用）；装配注入
```

- **语义**：elite_mode 是**行为档位开关**——只影响 AttackState 出招决策是否含蓄力重斩（§4）；HP/架势数值不读 AI 档位（由装配直接注入 CombatEntity `life_1_max`，§8），避免双通道数值源。
- **缺省回退**：装配未注入 elite_mode → false = #581 小兵行为（二选一出招），不报错——向后兼容 #581 场景与既有测试。

## 4. 蓄力重斩出招（AttackState 三选一 + 瞬时 override 注入）

文件：`enemy_ai_states.gd`（AttackState 修改）+ `combat_entity.gd`（override 字段）+ `combat_judge.gd`（fallback 链）。

**出招决策（elite_mode 门控，概率和 = 1 约束）：**

```gdscript
# AttackState.enter() —— 原二选一改为:
if ai.elite_mode and ai._rng.randf() < float(C.ENEMY_CHARGE_CHANCE):
    _attack_kind = "charge"                      # 蓄力重斩
elif ai._rng.randf() < float(C.ENEMY_THRUST_CHANCE):
    _attack_kind = "thrust"                      # 突刺（#581 既有）
else:
    _attack_kind = "combo"                       # 三连砍（#581 既有）

# update() 蓄力分支（_attack_kind == "charge"）——同一个 heavy_attack 战斗态 + 瞬时 override 注入:
ai.entity.current_windup_frames = int(C.ENEMY_CHARGE_WINDUP)   # 20 帧前摇
ai.entity.current_hp_damage = float(C.ENEMY_CHARGE_HP_DAMAGE) # 25 伤害
ai.entity.request_transition("heavy_attack")                    # 同步触发 judge 登记
ai.entity.current_windup_frames = -1            # 清空（防泄漏到下一击）
ai.entity.current_hp_damage = -1.0
```

**CombatEntity 瞬时 override 字段（additive，默认 -1 = #581 行为不变）：**

```gdscript
var current_windup_frames: int = -1    # 蓄力重斩前摇 override（-1 → judge 用 ENEMY_ATTACK_WINDUP）
var current_hp_damage: float = -1.0    # 蓄力重斩伤害 override（-1 → attack_hp_damage → 玩家常量兜底）
```

**CombatJudge 登记 fallback 链（additive，默认路径与 #581 逐字节一致）：**

```gdscript
# combat_judge.gd:_on_entity_state_changed —— 仅敌人分支:
if is_enemy:
    var wu: int = int(entity.current_windup_frames) if (entity.current_windup_frames >= 0) else int(C.ENEMY_ATTACK_WINDUP)
    w.windup_frames = wu
# hp_damage 取值链（敌我共用）:
w.hp_damage = float(entity.current_hp_damage) if (entity != null and entity.current_hp_damage >= 0.0) \
    else float(entity.attack_hp_damage) if (entity != null and entity.attack_hp_damage >= 0.0) \
    else float(C.SWORD_DAMAGE_HEAVY if to == "heavy_attack" else C.SWORD_DAMAGE_LIGHT)
```

**弹反兼容**：蓄力窗口仍经 `AttackWindow.is_active(frame)` 闭区间（#577 逻辑零改动）——20 帧前摇 → hit_frame = start + 20，弹反闭区间 `[hit_ms - 200ms, hit_ms]` 相对 12 帧突刺更宽松（实验 1 验证，难度平衡裁决归 #584）。**连段中断**：蓄力前摇期间玩家弹反 → parry_success → 抑制窗接管，AttackState 连段计划作废回 Chase（#581 既有边界复用，零新代码）。

## 5. 受击击退（位移层）

文件：`enemy_ai.gd`（修改）。

```gdscript
var _knockback_vel: float = 0.0       # stagger 期间沿受击反向，ENEMY_KNOCKBACK_DECAY 衰减
var _knockback_dir: int = 1           # 受击反向（相对 attacker 位置）

# _ensure_judge_subscription 内追加（与既有 parry_success 订阅同构）:
if judge.has_signal("hit_landed"):
    judge.hit_landed.connect(_on_judge_hit_landed)

func _on_judge_hit_landed(defender, attacker, _hp_damage: float, _stance_damage: float) -> void:
    if _dead or entity == null:
        return
    if defender != entity:             # 只响应「本敌人被击中」
        return
    var dx: float = 0.0
    if attacker != null:
        dx = attacker.position.x - position.x
    _knockback_dir = -1 if dx >= 0.0 else 1    # 远离攻击者
    _knockback_vel = float(C.ENEMY_KNOCKBACK_PX)
```

**位移执行（`_apply_movement` 内，与决策门控正交——硬直中 AI 不决策但击退仍执行）：** 击退分量覆盖 AI 位移意图 → `velocity.x = dir * vel` → 每帧 `vel -= ENEMY_KNOCKBACK_DECAY * delta` → `position.x = clampf(position.x, 0, STAGE_WIDTH_PX=2400)`（#583 舞台宽，纯 clamp 不引入新物理）。守卫：实体离开 stagger 态立即清零 `_knockback_vel` 走正常位移路径——「stagger 结束 → 击退归零 → Chase 恢复」，杜绝击退残留覆盖 Chase 位移（无弹簧抖动，边界 1）。与 #579 反馈渲染正交：击退是位移层（EnemyAI），火花/hit-stop/屏震是渲染层（ReactionController），hit_landed 是两者共同事件源，互不修改。

## 6. 架势脱战恢复（CombatEntity 敌人专用）

文件：`combat_entity.gd`（修改，additive）。

```gdscript
var _stance_recover_delay_until_sec: float = -1.0   # take_stance_damage 重置；-1 = 尚未受击（无恢复窗口）

# _process 内追加（fsm.update 之后，仅敌人变体）:
if not is_player and not is_stance_broken and state_name != "dead" and state_name != "revive":
    var now: float = Time.get_ticks_msec() / 1000.0
    if _stance_recover_delay_until_sec >= 0.0 and now >= _stance_recover_delay_until_sec and stance < stance_max:
        stance = clampf(stance + float(C.ENEMY_STANCE_RECOVER_PER_SEC) * delta, 0.0, stance_max)
        emit_signal("stance_changed", stance, stance_max)

# take_stance_damage 内追加（受击/被弹反即重置——两条路径都走本函数）:
if not is_player:
    _stance_recover_delay_until_sec = Time.get_ticks_msec() / 1000.0 + float(C.ENEMY_STANCE_RECOVER_DELAY_SEC)
```

**恢复语义要点：** 崩解期间（`is_stance_broken=true`）不恢复（快线处决窗口不被恢复打断）；`recover_from_break`（50% + 5s 疲惫）后恢复机制照常；玩家实体（`is_player=true`）不触发——玩家架势语义不变（回归全绿）；恢复中玩家重新攻击 → 延迟重置 → 「恢复-再受伤」节拍正确（不出现边恢复边掉架势的闪烁，边界 4）。

## 7. EnemyHealthBar（Boss 条组合）

文件：`hud.gd`（修改，additive）。

```
Hud (CanvasLayer)
└── EnemyHealthBar (_HudBar)      # 新: 顶部中央暗红粗条 240×10
│   ├─ anchor_left/right = 0.5
│   ├─ offset_left/right = ±HUD_ENEMY_BAR_WIDTH/2
│   ├─ offset_top = HUD_ENEMY_BAR_TOP (=12)              → 12..22
│   └─ offset_bottom = HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT
└── EnemyStanceBar (_HudBar)      # 既有: 下移至血条下方
    ├─ offset_top = HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT + HUD_ENEMY_HP_GAP (=26)
    └─ offset_bottom = ... + HUD_STANCE_HEIGHT            → 26..32
```

- **`_HudBar` additive 扩展（fill 色覆写，默认行为零变化——玩家两条约 `set_segments` 路径不受影响）：**

```gdscript
var _fill_override: Color = Color.TRANSPARENT
var _use_fill_override: bool = false

func set_fill_color(color: Color) -> void:
    _fill_override = color
    _use_fill_override = true
    queue_redraw()
# _draw 内活性段颜色分支:
var fill_color: Color = _fill_override if _use_fill_override \
    else (C.HUD_BLOOD_RED if _low_hp_mode else C.HUD_MOON_WHITE)
```

- **`set_target_enemy` 增订**：`entity.hp_changed.connect(_on_enemy_hp_changed, CONNECT_REFERENCE_COUNTED)` + `EnemyHealthBar.visible = true` + `set_segments([entity.hp_1], [entity.life_1_max], 0)`；null 分支与 `_disconnect_enemy` 同步隐藏/断开。`_on_enemy_hp_changed(hp_1, ...)` → `EnemyHealthBar.set_segments([hp_1], [life_1_max], 0)`。
- **died 联动**：`final=true` → `EnemyHealthBar.visible = false`（与 EnemyStanceBar 同处隐藏）；`final=false`（防御分支）→ `set_segments([0.0], [1.0], 0)`。
- **布局联动**：EnemyHealthBar 占位顶部 12..22，EnemyStanceBar 下移至 26..32（`HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT + HUD_ENEMY_HP_GAP`）；`test_hud.gd` T5 布局断言同步更新（12 → 26）。

## 8. 装配接通（main_battle.gd 一行参数）

文件：`shandong-wolf/gdscripts/main_battle.gd`（`_build_enemy`，唯一触碰点）。

```gdscript
enemy_entity = CombatEntityScript.new({"is_player": false, "life_total": 1,
    "life_1_max": C.ENEMY_HP_MAX})          # ← HP 慢线接通（装配显式消费 ENEMY_HP_MAX=80）
enemy.elite_mode = true                      # ← MVP 单敌人即精英（蓄力出招启用）
```

## 9. 精英 AI 分区常量（constants.gd，# DRAFT 只读不裁决，定稿归 #584）

全部带「sekiro 基准 → 候选集 + 影响 + 情感断言」三行注释（与 AI 分区同纪律）。`ENEMY_HP_MAX` 默认 40→**80** 候选上调、候选集 [30,40,50]→[60,80,100]、情感断言「小兵是消耗品」→「精英是磨刀石：七刀之内是紧张，一刀半血是恐惧」；`test_enemy_ai.gd:136` 动态读常量自动跟随，其余测试 fixture 显式传 `life_1_max=40.0`（局部配置不受影响）。

| 常量 | 值 | 候选集 | 含义 |
|------|:---:|--------|------|
| ENEMY_CHARGE_WINDUP | 20 | [18, 20, 24] 帧 | 蓄力重斩前摇——弹反闭区间绝对窗口时长（实验 1） |
| ENEMY_CHARGE_HP_DAMAGE | 25.0 | [20, 25, 30] | 蓄力命中 HP 伤害——慢线加速器 |
| ENEMY_CHARGE_CHANCE | 0.2 | [0.15, 0.2, 0.25] | 蓄力出招概率（三选一掷骰首层，和 = 1 约束） |
| ENEMY_KNOCKBACK_PX | 40.0 | [30, 40, 60] | 击退初速（px/s 当量，stagger 12 帧内衰减） |
| ENEMY_KNOCKBACK_DECAY | 3.0 | [2, 3, 4] /s | 击退速度线性衰减系数（防弹簧抖动） |
| ENEMY_STANCE_RECOVER_DELAY_SEC | 2.5 | [2.0, 2.5, 3.0] | 受击/弹反后无架势伤害的恢复延迟窗 |
| ENEMY_STANCE_RECOVER_PER_SEC | 20.0 | [15, 20, 25] | 脱战恢复速率（上限 stance_max） |
| ENEMY_HP_MAX（既有，改默认） | 80.0 | [60, 80, 100] | 敌人血条上限（life_1_max 装配注入）——默认 40→80 候选上调 |
| HUD_ENEMY_HP_GAP | 4.0 | [2, 4, 6] | 敌人血条与架势条间距（HUD 分区内） |

## 10. 数据流

### Flow 1: 慢线（削血击杀，AC5 主路径）

```
玩家轻击命中（SWORD_DAMAGE_LIGHT=12）
  → judge.resolve_attack → enemy.take_damage(12)
      → hp_1 -= 12 → hp_changed(68, ...) → HUD EnemyHealthBar 比例更新（新）
      → stagger 12 帧硬直 + EnemyAI 击退位移（新，ENEMY_KNOCKBACK_PX 衰减）
      → take_stance_damage(35) + 脱战恢复延迟重置（新）
  → 7 刀后 hp_1 = 0 → die() final=true → died → HUD 击杀提示（#576 既有）
      + EnemyHealthBar/EnemyStanceBar 双条隐藏（新）→ main_battle KILL → AFTERGLOW
```

### Flow 2: 快线（弹反 → 崩解 → 处决，AC2/AC3/AC7 主路径）

```
敌人蓄力重斩（elite_mode=true，windup=20 帧）
  → judge 登记 AttackWindow（override fallback 链读取，新）→ 弹反闭区间 [hit-200ms, hit]
  → 玩家 guard_pressed 命中 → parry_success → enemy.take_stance_damage(25)
      → 脱战恢复延迟重置（新）+ EnemyAI 抑制窗 0.5s（#581 既有）
  → 4 次弹反 stance=0 → break_stance → stance_broken
      → #580 ExecutionOrchestrator armed 3s 窗口（零改动）
      → attack_pressed + 距离校验 → execute → execute_kill(999) → died(final)
      → HUD 双条隐藏 + 处决/击杀提示（#576 既有）
```

### Flow 3: 蓄力重斩窗口登记（新，gap 1/2 修复路径）

```
AttackState.enter: elite && rng < ENEMY_CHARGE_CHANCE → _attack_kind="charge"
  → update: entity.current_windup_frames=20 / current_hp_damage=25（瞬时设置）
  → entity.request_transition("heavy_attack")
      → state_changed 同步广播 → judge._on_entity_state_changed
          → w.windup_frames = override(20)（fallback 链）
          → w.hp_damage = override(25)（fallback 链）
  → 清空 override（-1/-1.0）→ 下一击回退 #581 默认
  → judge.tick_frame: frame == start+20 → resolve_attack → 命中/弹反/格挡/拼刀四路（#577 零改动）
```

### Flow 4: 架势脱战恢复（新，AC8 主路径）

```
敌人受击/被弹反 → take_stance_damage → _stance_recover_delay_until_sec = now + 2.5s
  → 2.5s 内无新架势伤害 → _process 每帧 stance += 20*delta（上限 100）→ stance_changed → HUD 架势条回升
  → 恢复中玩家再攻击 → take_stance_damage → 延迟重置 → 恢复暂停（边界 4）
  → 崩解（stance=0）→ is_stance_broken=true → 轮询跳过（快线窗口不被恢复打断）
```

### Flow 5: 受击击退（新）

```
judge.resolve_attack 命中 → emit hit_landed(defender=enemy, attacker=player, ...)
  → EnemyAI._on_judge_hit_landed: defender==entity → _knockback_dir = 远离玩家
  → _knockback_vel = 40（ENEMY_KNOCKBACK_PX）
  → _physics_process → _apply_movement: 击退分支覆盖位移意图 → velocity.x = dir*vel
  → 每帧 vel -= 3*delta（ENEMY_KNOCKBACK_DECAY）→ 12 帧 stagger 内衰减归零
  → position.x clamp [0, 2400]（STAGE_WIDTH_PX 兜底）→ 恢复后 Chase 从落点继续（无弹簧抖动）
```

## 11. 测试

文件：`test_enemy_ai.gd`（新增 E 组精英用例：蓄力出招概率/前摇 20/伤害 25、击退位移与衰减、elite=false 回归；既有 36 条用例零改动）+ `test_hud.gd`（EnemyHealthBar 注入可见/hp_changed 驱动比例/died 隐藏 + T5 布局断言 12→26 同步）+ `test_combat_entity.gd`（脱战恢复：延迟窗口内不恢复/超时逐帧恢复至上限/崩解不恢复/玩家不触发/恢复-再受伤重置/双写竞态）+ `test_main_assembly.gd`（可选装配断言：`life_1_max == ENEMY_HP_MAX`、`elite_mode == true`）。

| 场景 | 覆盖 |
|------|------|
| A 精英装配与 HP 慢线（AC5） | 装配消费 ENEMY_HP_MAX（80）/ 7 刀慢线击杀非一击毙命 / hp_changed 信号链 |
| B EnemyHealthBar（AC6） | 注入可见 / 布局（240×10 + offset_top 12，EnemyStanceBar 26）/ 信号驱动比例 / died 隐藏 / 玩家条回归零变化 |
| C 蓄力重斩（AC2 + 实验 1） | elite 门控（false 无 charge）/ 概率分布 ≈0.2 和=1 / 窗口 windup=20 伤害 25 / override 清空无泄漏 / 可弹反闭区间三态 |
| D 受击击退 | 触发与方向 / 位移与衰减 / 衰减归零无弹簧 / 玩家不受击退 / 越界 clamp |
| E 架势脱战恢复（AC8 + 实验 2） | 延迟窗内不恢复 / 超时恢复封顶 / 崩解中不恢复 / 玩家不触发 / 恢复-再受伤重置 / 双写竞态（快线 4 弹反仍可崩解） |
| F 失败路径 | HP 装配漏改 / 蓄力窗口未注入（windup==12 拦截）/ 血条未绑定 |
| G 既有回归 | elite_mode=false 全量 #581 用例 / #577 五结果事件顺序 / #580 处决窗口衔接 / 玩家实体全部用例 |

## 12. 验收条件映射（issue #682 body 5 条 + 补充 4 条 + PRD §5.1）

| AC | 保障 |
|----|------|
| AC1 敌人主动接近并攻击 | ✅ 既有（#581 chase+attack）维持 + elite_mode 档位；追击速度/冷却维持 #581 默认（范围收敛，候选移交 #584） |
| AC2 攻击可弹反 + 弹反后硬直 | 既有回归（#577 闭区间 + #581 抑制窗）+ 新蓄力重斩可弹反（windup 20 帧，窗口更宽松） |
| AC3 架势崩解后可处决 | ✅ 既有（#580 armed 3s 窗口），本 issue 确认衔接零改动 |
| AC4 玩家不操作时敌人持续进攻 | ✅ 既有（#581 冷却 1.5s 循环）维持 |
| AC5 敌人有血条，多次攻击才能击杀 | 装配消费 ENEMY_HP_MAX（80）+ 慢线 7 刀击杀（非一击毙命） |
| AC6 敌人血条/架势条 UI 可见（顶部 Boss 条） | EnemyHealthBar（240×10 暗红）+ EnemyStanceBar 下移组合 |
| AC7 崩解后进入处决窗口（#580 衔接） | ✅ 既有（编排器零改动） |
| AC8 架势脱战恢复（不无限崩解） | 敌人专用恢复（延迟 2.5s + 20/s） |
| 实验 1 蓄力前摇 vs 弹反闭区间 | Scenario C（数据记录交 #584 裁决） |
| 实验 2 脱战恢复节奏 vs 崩解频率 | Scenario E（快线不被恢复打断） |

## 13. 明确不修改（与 PRD §8.5 交接红线对齐）

- ❌ 不改 11 态 `CANONICAL_STATES` / `consume_state` 契约（combat_state_table.gd 零改动；精英行为仍是 AI 行为态）
- ❌ 不改 #577 五结果事件名与裁决顺序（combat_judge.gd 仅 2 处 fallback 链 additive）；不引入 Area2D/CollisionShape2D 物理碰撞
- ❌ 不改 #580 处决编排器（execution_orchestrator.gd 零改动——只消费 stance_broken/armed 窗口衔接）
- ❌ 不改 #589 军曹/#590 汉奸内容（危攻击/霸体/体型/掉落/二阶段/台词/演出——本 issue 只交付通用精英模板）
- ❌ 不改玩家实体行为（脱战恢复仅 is_player=false；玩家 HP/架势/HUD 区块零改动）
- ❌ 不改既有接口签名（entity/judge/AttackWindow 全部 additive）
- ❌ 不裁决 # DRAFT 数值（精英 AI 分区只读 + 候选集移交 #584；EnemyHealthBar 视觉色相差异走 #576 human-review 通道）

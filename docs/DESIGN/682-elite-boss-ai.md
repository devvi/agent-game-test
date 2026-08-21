# Design: [Feature] 敌人 AI：只狼式精英怪 Boss（攻击/弹反/架势交互）

> **Parent Issue:** #682（feature / workflow/plan / priority/high / gameplay / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 确认采纳** —— 精英 = EnemyAI 的参数档位 + 行为增量（蓄力重斩 / 受击击退 / 架势脱战恢复）+ 数据/UI additive 补丁（HP 慢线装配消费 + EnemyHealthBar），**不新建类**。方案 B（独立 EliteBossAI 双类并存——违反 #575「差异通过参数配置」契约 + 双份维护）与方案 C（提前实现 #589 军曹内容——issue 边界红线 + 危攻击不可弹反与 issue「可弹反的蓄力攻击」矛盾）显式否决，理由同 PRD §4.2/§4.3
> **Reference PRD:** `docs/PRD/682-elite-boss-ai.md`（research PR #687 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/581-enemy-ai.md`（EnemyAI 四态行为 FSM + 决策门控 + 弹反抑制窗——本设计的精英基底，全部增量在其上叠加）；`docs/DESIGN/575-combat-entity-state-machine.md`（CombatEntity 变体参数契约 + 6 信号 + request_transition 唯一入口）；`docs/DESIGN/577-parry-clash-stance-break.md`（AttackWindow 窗口契约 + CombatJudge 自动登记 + 五结果事件）；`docs/DESIGN/585-mvp-combat-loop-assembly.md`（main_battle.gd 13 步装配——唯一触碰点 = 敌人装配一行参数）；`docs/DESIGN/576-hud-stance-bars.md`（EnemyStanceBar 顶部中央 + _HudBar 自绘条组件——EnemyHealthBar 同构复用）
> **所有权:** `content_ownership: mechanical`（AI 出招概率/HP 双轨/击退位移/架势恢复 = 机械工程；全部新数值 # DRAFT **只读不裁决**，候选集移交 #584 调参面板定稿；EnemyHealthBar 视觉色相按 #576 既有风格 additive 实现，用户定稿差异走 #576 human-review 通道）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 11 文件（6 gdscripts + 1 可选 + 4 测试）/ 5 子系统（constants、装配、HUD、行为层、实体数据）× 7+ 独立子任务 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：10+ 文件 / 5+ 独立子任务跨多子系统，照 #581/#661 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-682，branch `plan/682-elite-boss-ai`）；constants.gd 为**追加式新增「精英 AI」分区**（不触碰既有 9 分区常量行，唯一例外 = ENEMY_HP_MAX 默认值 40→80 候选上调，与 #584 调参面板无同区改写冲突）；#576/#584 草稿已 merge（human-review 等用户定稿，v4 规则 human Issue 不进依赖链视为已满足）——UI 视觉差异由用户定稿通道收敛，不阻塞本 issue；`mini-pong/` 零影响
> **红线:** 只动 shandong-wolf/ 下 6 gdscripts + 1 可选 + 4 测试文件（§3.1 清单）；**绝不触碰** 11 态 `CANONICAL_STATES` / `consume_state` 契约（精英行为仍是 AI 行为态）、#577 五结果事件名与裁决顺序、#580 处决编排器（execution_orchestrator.gd 零改动）、#589/#590 军曹/Boss 内容（危攻击/霸体/体型/掉落/二阶段/台词/演出）、玩家实体行为（脱战恢复仅 is_player=false）；不引入 Area2D/CollisionShape2D 物理碰撞；不修改既有接口签名（全部 additive）；数值全走 constants # DRAFT，AI 代码零字面量；**不写可运行测试文件**（只产出 DESIGN/TASKS 文档 + 测试用例描述）；PR body 用 `Parent #682`（不带冒号）

---

## 1. 架构总览

**问题本质是「战斗数据模型与行为层原料全部就绪，但精英感（血量存在感 + 变招 + 受击反馈 + 节奏阀）五处断点」。** #585 组装后敌人「能动、能打、能被打、能崩解」——但 HP 慢线数据模型（life_1_max）存在却从未被装配消费（ENEMY_HP_MAX=40 常量定义了没人读，life_1_max 走默认 100）、无敌人血条 UI（玩家感知「无血量概念」）、攻击组缺蓄力形态（只有突刺/三连砍）、受击缺击退位移（只有 12 帧硬直）、架势无脱战恢复（不被打就一直满架，崩解后仅 recover_from_break 一次性 50%）。用户 8-21 实机反馈「敌人一击毙命 + 无 AI 无法测试战斗」即源于此。**本 issue 交付 = 在 #581 EnemyAI 基底上做参数化精英化 + 五处 additive 补丁，不重写任何既有契约。**

**设计哲学：精英是小兵 AI 的参数档位，不是新类；双轨击杀 = 只狼铁律（处决是奖励不是补刀）；一切增量走信号/参数，不碰判定与处决层。**

1. **精英 = 参数档位 + 行为增量，绝不重写**（#575「差异通过参数配置」契约字面对齐）：EnemyAI 新增 `@export elite_mode: bool = false`——装配时置 true → AttackState 出招三选一（+蓄力重斩）；HP/架势由装配注入 CombatEntity 参数；击退/恢复为独立 additive 机制。小兵档位（elite_mode=false）行为与 #581 逐字节一致，既有 36 条 AI 测试回归全绿。
2. **双轨击杀成立（HP 慢线 / 架势快线）**：慢线 = 装配消费 `ENEMY_HP_MAX`（精英候选默认 80）+ EnemyHealthBar 可视化，轻击 12/刀 → 7 刀削死（die() 终态，击杀提示 #576 既有）；快线 = 4 次弹反（25×4=100）崩解 → #580 处决窗口 → 处决一击（999）。弹反高手速杀 < 稳健玩家磨刀——只狼式「快线奖励技术」。
3. **蓄力重斩 = 长前摇可弹反重击**：AttackState 掷骰三选一；复用 `AttackWindow.windup_frames` 契约（#581 已交付字段），**但注入点需要新增**——实测 `CombatJudge._on_entity_state_changed` 对敌人硬编码 `windup_frames = ENEMY_ATTACK_WINDUP`、`hp_damage = entity.attack_hp_damage`（单值），PRD §8.3 假设的「entity 携带 windup → judge 登记」在代码库中**不存在**（gap 1/2，见 §1.2）。设计裁决：CombatEntity 新增 2 个瞬时 override 字段（默认 -1 兜底 = #581 行为不变），蓄力出招前设置、judge 登记时读取。
4. **受击后退 = 位移层击退**：EnemyAI 订阅 `judge.hit_landed`（defender == 本敌人，与既有 parry_success 订阅同构）→ 沿受击反向设置 `_knockback_vel`，stagger 期间线性衰减位移（`ENEMY_KNOCKBACK_DECAY`），与 12 帧硬直叠加成「僵直+后退」完整反馈；位移执行在 `_apply_movement`（与决策门控正交——硬直中 AI 不决策但击退仍执行），与 #579 反馈渲染（火花/屏震）分层正交。
5. **架势脱战恢复 = 节奏阀**：CombatEntity `_process` 轮询（仅 `is_player=false` 且未崩解且超延迟窗口）→ 按 `ENEMY_STANCE_RECOVER_PER_SEC` 恢复至 stance_max；`take_stance_damage` 重置延迟计时——只狼铁律 4「回复太快=无脑弹反，太慢=龟缩」，sekiro 基准 1.5s/20-35 per/s 放宽候选。
6. **Boss 条 = EnemyStanceBar 组合扩展**：hud.gd 新增 `EnemyHealthBar`（同锚点顶部中央，240×10 暗红粗条，位于 EnemyStanceBar 上方），复用 `_HudBar` 自绘组件 + 新增 `set_fill_color` additive 覆写（默认行为零变化）；`set_target_enemy` 订阅 hp_changed，died 双条联动隐藏。

```
★ Issue #682 本设计（shandong-wolf 敌人精英化增量）
┌────────────────────────────────────────────────────────────────────────────┐
│ 修改（6 gdscripts + 1 可选 + 4 测试，全部 shandong-wolf/ 下）                  │
│  ├─ constants.gd       精英 AI 分区 # DRAFT 常量（8 项）+ ENEMY_HP_MAX 上调   │
│  ├─ main_battle.gd     敌人装配一行参数: life_1_max=C.ENEMY_HP_MAX + elite   │
│  │                     _mode=true（HP 慢线接通，唯一触碰点）                    │
│  ├─ enemy_ai_states.gd AttackState 出招三选一（+蓄力重斩，elite_mode 门控）     │
│  ├─ enemy_ai.gd        hit_landed 订阅 → 受击击退位移（stagger 期间衰减）       │
│  ├─ combat_entity.gd   瞬时 override 字段 ×2（windup/hp_damage）+ 敌人架势     │
│  │                     脱战恢复（_process 轮询，仅 is_player=false）           │
│  ├─ combat_judge.gd    窗口登记读 override（fallback 链，additive）            │
│  ├─ hud.gd             EnemyHealthBar（顶部中央暗红条）+ _HudBar.fill_color   │
│  │                     覆写 + set_target_enemy 订阅 hp_changed                │
│  └─ combat_attack_window.gd（可选）: 如需按出招区分再扩展，优先零改动           │
│  └─ tests/ 4 文件       AC5-AC8 用例 + 边界/失败路径 + 实验 1/2 落地           │
└────────────────────────────────────────────────────────────────────────────┘
只读消费（零修改）: CombatJudge 五结果事件 / ExecutionOrchestrator 处决窗口
                  （#580）/ ReactionController 反馈渲染（#579）/ #576 玩家 HUD 区块
事件源（只读）: judge.hit_landed / parry_success（既有信号，新增订阅）
下游消费者（自动接管）: #589 军曹（精英档位 + Boss 条复用）/ #590 汉奸 Boss
                        （双轨击杀 + 双条 UI 复用）/ #584 数值定稿（候选集移交）
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的消费方式 |
|------|:---:|:---:|------|
| EnemyAI 四态行为 FSM（enemy_ai.gd 177 行） | #581/#638 | ✅ 已合并 | 精英化基底：新增 elite_mode 档位 + hit_landed 击退订阅，decide/门控/抑制窗零改动 |
| 行为状态对象集（enemy_ai_states.gd 223 行） | #581/#638 | ✅ 已合并 | AttackState 出招决策二选一 → 三选一（elite_mode 门控）；Chase/Patrol/Retreat 零改动 |
| CombatEntity 数据模型 + 6 信号（combat_entity.gd 252 行） | #575/#618 | ✅ 已合并 | 瞬时 override 字段 ×2（additive）+ 敌人架势脱战恢复（_process 轮询，仅 is_player=false） |
| CombatJudge 双轨伤害 + 自动窗口登记（combat_judge.gd 223 行） | #577/#626 | ✅ 已合并 | 窗口登记读 override（fallback 链——默认路径与 #581 逐字节一致） |
| AttackWindow.windup_frames 字段 | #577/#581 | ✅ 已交付 | 蓄力重斩复用（windup_frames >= 0 分支既有）；注入点新增（见 §1.2 gap 1） |
| 敌人装配（main_battle.gd _build_enemy） | #585/#666 | ✅ 已合并 | 一行参数：`life_1_max: C.ENEMY_HP_MAX` + `enemy.elite_mode = true` |
| HUD EnemyStanceBar + _HudBar 自绘条（hud.gd 410 行） | #576 | ✅ 草稿 merged（human-review） | EnemyHealthBar 同构复用 _HudBar；set_target_enemy 增订 hp_changed |
| 处决编排（execution_orchestrator.gd 186 行） | #580/#660 | ✅ 已合并 | **零改动**——只消费 stance_broken → armed 窗口衔接（AC3/AC7 确认） |
| 常量（constants.gd 641 行） | #584 | ✅ 草稿 merged（human-review） | 新增「精英 AI」分区 # DRAFT 常量；ENEMY_HP_MAX 默认 40→80 候选上调 |
| 测试（test_enemy_ai / test_hud / test_combat_entity / test_main_assembly） | #581/#576/#575/#585 | ✅ 全绿（1314 单测） | 修改：蓄力/击退/恢复/血条用例 + T5 布局断言同步 + 装配断言 |

### 1.2 核心缺口与修复决策（本设计新增 + gap analysis）

| # | 缺口（codebase 勘探发现） | 修复决策 | 归属 |
|---|--------------------------|---------|------|
| 1 | **PRD §8.3 假设「entity 携带 windup → judge 登记」不存在**：实测 `combat_judge.gd:_on_entity_state_changed` 对敌人**硬编码** `w.windup_frames = int(C.ENEMY_ATTACK_WINDUP)`（12 帧），实体无 windup 字段——蓄力重斩 20 帧前摇无处注入 | CombatEntity 新增瞬时字段 `current_windup_frames: int = -1`（默认 -1 兜底 = #581 行为不变）；judge 登记改 fallback 链：`entity.current_windup_frames >= 0 ? override : ENEMY_ATTACK_WINDUP`（仅敌人分支） | 本 issue |
| 2 | **蓄力重斩伤害无处区分**：judge 对敌人 `w.hp_damage = entity.attack_hp_damage`（单值 15）——PRD §8.2 的 `ENEMY_CHARGE_HP_DAMAGE`（25）需要 per-attack 注入 | CombatEntity 新增瞬时字段 `current_hp_damage: float = -1.0`（fallback 链同 gap 1：override → attack_hp_damage → SWORD_DAMAGE_HEAVY/LIGHT）；AI 蓄力出招时设置、`state_changed` 同步登记后清空 | 本 issue |
| 3 | **PRD §5.1 AC1 引用的「追击速度/攻击冷却精英常量（§8.2）」在 §8.2 清单中不存在**——交付物清单只有 7 项新常量 + ENEMY_HP_MAX 上调，无速度/冷却项 | 设计裁决：**MVP 维持 #581 默认**（追击 180 px/s、冷却 1.5s），精英差异聚焦 HP/架势/出招/击退/恢复五处；速度/冷却精英候选记入 #584 候选池移交，不新增常量——避免超出 PRD 交付物清单 | 本 issue（范围收敛） |
| 4 | **EnemyStanceBar 下移会破坏 #576 测试**：`test_hud.gd` T5 断言 `EnemyStanceBar.offset_top == 12.0` | 布局决策：EnemyHealthBar 占位顶部 12..22（宽 240 高 10 暗红），EnemyStanceBar 下移至 26..32（`HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT + HUD_ENEMY_HP_GAP`）；T5 断言同步更新（test_hud.gd 在修改清单内，PRD §5.1 AC6「下移/保持其下」明示） | 本 issue |
| 5 | **蓄力攻击与 #581 出招测试的兼容面**：`test_enemy_ai.gd` 有 36 条用例断言二选一出招（seed-scan 找 attack/heavy_attack） | elite_mode 门控：**默认 false 时行为与 #581 逐字节一致**（二选一），elite 用例显式置 elite_mode=true 后断言三选一——既有用例零改动全绿，新增 E 组精英用例 | 本 issue |
| 6 | **击退位移与场景边界**：#583 舞台宽 `STAGE_WIDTH_PX = 2400`（constants 既有）——击退 40px 无越界风险，但 clamp 兜底防未来候选值放大 | `_apply_movement` 击退分量执行后 `position.x = clampf(position.x, 0, STAGE_WIDTH_PX)`（不引入新物理，纯 clamp） | 本 issue（边界兜底） |

---

## 2. 新组件 — 详细设计

> 本 issue **无新文件**——「新组件」是既有文件内的 5 个新增能力（elite 档位 / 蓄力重斩 / 击退 / 脱战恢复 / EnemyHealthBar），全部 additive。按 PRD §8.3 接口契约逐项展开。

### 2.1 精英参数档位（EnemyAI.elite_mode + 精英常量组）

- **文件:** `shandong-wolf/gdscripts/enemy_ai.gd`（修改）+ `constants.gd`（新增分区）
- **接口契约（PRD §8.3 落地）:**
```gdscript
# enemy_ai.gd
@export var elite_mode: bool = false   # true → 读精英常量组（蓄力出招启用）；装配注入
```
- **语义:** elite_mode 是**行为档位开关**——只影响 AttackState 出招决策是否含蓄力重斩（§2.2）；HP/架势数值不读 AI 档位（由装配直接注入 CombatEntity `life_1_max`，§3.2-2），避免双通道数值源。
- **缺省回退（边界 6）:** 装配未注入 elite_mode → false = #581 小兵行为，不报错（向后兼容 #581 场景）。
- **新常量（constants.gd「精英 AI」分区，全部 # DRAFT 只读 + 候选集 + 情感断言注释，定稿归 #584）:**

| 常量 | 默认 | 候选集 | sekiro 基准 | 影响 |
|------|:---:|:---:|------|------|
| `ENEMY_CHARGE_WINDUP` | 20 | [18, 20, 24] 帧 | 危攻击前摇 14-18 帧（本作保持可弹反，放宽） | 蓄力重斩前摇——弹反闭区间绝对窗口时长（实验 1） |
| `ENEMY_CHARGE_HP_DAMAGE` | 25.0 | [20, 25, 30] | 重击语义（轻击 12/刀 ×2 倍） | 蓄力命中 HP 伤害——慢线加速器 |
| `ENEMY_CHARGE_CHANCE` | 0.2 | [0.15, 0.2, 0.25] | 变招频率克制 | 蓄力出招概率（三选一掷骰，和 = 1 约束） |
| `ENEMY_KNOCKBACK_PX` | 40.0 | [30, 40, 60] | 受击后退位移量 | 击退初速（px/s 当量，stagger 12 帧内衰减） |
| `ENEMY_KNOCKBACK_DECAY` | 3.0 | [2, 3, 4] /s | 防弹簧抖动 | 击退速度线性衰减系数（边界 1） |
| `ENEMY_STANCE_RECOVER_DELAY_SEC` | 2.5 | [2.0, 2.5, 3.0] | 脱战/停防 1.5s（放宽） | 受击/弹反后无架势伤害的恢复延迟窗 |
| `ENEMY_STANCE_RECOVER_PER_SEC` | 20.0 | [15, 20, 25] | 20-35/s 基准 | 脱战恢复速率（上限 stance_max） |
| `ENEMY_HP_MAX`（既有，改默认） | **80.0** | [60, 80, 100] | 精英候选（sekiro 小兵 30-50 上调） | 敌人血条上限（life_1_max 装配注入）——**默认 40→80 候选上调，注释同步更新** |
| `HUD_ENEMY_HP_GAP` | 4.0 | [2, 4, 6] | #576 布局呼吸感 | 敌人血条与架势条间距 |

> ⚠️ **ENEMY_HP_MAX 修改提示:** 既有值为 40（`# 候选集: [30, 40, 50]（默认 40 = sekiro 敌小兵 HP 30-50）`）——本设计将其默认调至 80、候选集更新为 [60, 80, 100]、情感断言改为精英语义；#581 测试 `test_enemy_ai.gd:136` 动态读常量自动跟随，其余测试 fixture 均显式传 `life_1_max=40.0`（局部配置，不受影响）。

### 2.2 蓄力重斩出招（AttackState 三选一 + 瞬时 override 注入）

- **文件:** `enemy_ai_states.gd`（AttackState 修改）+ `combat_entity.gd`（override 字段）+ `combat_judge.gd`（fallback 链）
- **出招决策（elite_mode 门控，概率和 = 1 约束）:**
```gdscript
# AttackState.enter() —— 原二选一改为:
if ai.elite_mode and ai._rng.randf() < float(C.ENEMY_CHARGE_CHANCE):
    _attack_kind = "charge"                      # 蓄力重斩
elif ai._rng.randf() < float(C.ENEMY_THRUST_CHANCE):
    _attack_kind = "thrust"                      # 突刺（#581 既有）
else:
    _attack_kind = "combo"                       # 三连砍（#581 既有）
```
- **蓄力出招执行（update 内，_attack_kind == "charge" 分支）:**
```gdscript
# 蓄力 = 同一个 heavy_attack 战斗态 + 瞬时 override 注入:
ai.entity.current_windup_frames = int(C.ENEMY_CHARGE_WINDUP)   # 20 帧前摇
ai.entity.current_hp_damage = float(C.ENEMY_CHARGE_HP_DAMAGE) # 25 伤害
ai.entity.request_transition("heavy_attack")                    # 同步触发 judge 登记
# request_transition → state_changed 同步广播 → judge._on_entity_state_changed
#   同步读取 override 构造 AttackWindow → 之后 AI 清空 override（防泄漏到下一击）
ai.entity.current_windup_frames = -1
ai.entity.current_hp_damage = -1.0
```
- **CombatEntity 新增瞬时字段（gap 1/2 落地）:**
```gdscript
# combat_entity.gd（additive，默认 -1 = #581 行为不变）
var current_windup_frames: int = -1    # 蓄力重斩前摇 override（-1 → judge 用 ENEMY_ATTACK_WINDUP）
var current_hp_damage: float = -1.0    # 蓄力重斩伤害 override（-1 → attack_hp_damage → 玩家常量兜底）
```
- **CombatJudge 登记 fallback 链（additive，默认路径与 #581 逐字节一致）:**
```gdscript
# combat_judge.gd:_on_entity_state_changed —— 仅敌人分支两行改动:
if is_enemy:
    var wu: int = int(entity.current_windup_frames) if (entity.current_windup_frames >= 0) else int(C.ENEMY_ATTACK_WINDUP)
    w.windup_frames = wu
# hp_damage 取值链（敌我共用）:
w.hp_damage = float(entity.current_hp_damage) if (entity != null and entity.current_hp_damage >= 0.0) \
    else float(entity.attack_hp_damage) if (entity != null and entity.attack_hp_damage >= 0.0) \
    else float(C.SWORD_DAMAGE_HEAVY if to == "heavy_attack" else C.SWORD_DAMAGE_LIGHT)
```
- **弹反兼容:** 蓄力窗口仍经 `AttackWindow.is_active(frame)` 闭区间（#577 逻辑零改动）——20 帧前摇 → hit_frame = start + 20，弹反闭区间 `[hit_ms - 200ms, hit_ms]` 相对 12 帧突刺更宽松（实验 1 验证，难度平衡裁决归 #584）。
- **连段中断（边界 2）:** 蓄力前摇期间玩家弹反 → parry_success → 抑制窗接管，AttackState 连段计划作废回 Chase（#581 既有边界 7 复用，零新代码）。

### 2.3 受击击退（位移层）

- **文件:** `enemy_ai.gd`（修改）
- **接口契约（PRD §8.3 落地）:**
```gdscript
# enemy_ai.gd
var _knockback_vel: float = 0.0       # stagger 期间沿受击反向，ENEMY_KNOCKBACK_DECAY 衰减
var _knockback_dir: int = 1           # 受击反向（相对 attacker 位置）
```
- **触发订阅（与既有 parry_success 订阅同构，惰性接线复用 `_ensure_judge_subscription`）:**
```gdscript
# _ensure_judge_subscription 内追加:
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
- **位移执行（`_apply_movement` 内，与决策门控正交——硬直中 AI 不决策但击退仍执行）:**
```gdscript
# _apply_movement 内追加（在 _move_intent 消费之前/叠加）:
if absf(_knockback_vel) > 0.001:
    var kb: float = float(_knockback_dir) * _knockback_vel
    velocity.x = kb                       # 击退覆盖 AI 位移意图（stagger 期间 _move_intent 本为 0）
    _knockback_vel = maxf(_knockback_vel - float(C.ENEMY_KNOCKBACK_DECAY) * delta, 0.0)
    if is_inside_tree():
        move_and_slide()
    else:
        position += Vector2(kb * delta, 0.0)
    position.x = clampf(position.x, 0.0, float(C.STAGE_WIDTH_PX))   # 边界 8 兜底
    return
# 正常路径: 既有 _move_intent 消费不变
```
- **与 #579 反馈渲染正交:** 击退是位移层（EnemyAI），火花/hit-stop/屏震是渲染层（ReactionController）——hit_landed 是两者共同的事件源，互不修改。
- **防「击退-拉回」弹簧抖动（边界 1）:** stagger 12 帧期间决策门控禁止 Chase 位移（#581 既有），击退速度线性衰减（ENEMY_KNOCKBACK_DECAY=3/s → 40px 初速 12 帧内衰减约 60%），stagger 结束前 `_knockback_vel` 归零，恢复后从击退落点继续 Chase——衰减系数进 constants。

### 2.4 架势脱战恢复（CombatEntity 敌人专用）

- **文件:** `combat_entity.gd`（修改，additive）
- **接口契约（PRD §8.3 落地）:**
```gdscript
# combat_entity.gd
var _stance_recover_delay_until_sec: float = -1.0   # take_stance_damage 重置；-1 = 尚未受击（无恢复窗口）
```
- **恢复轮询（挂进既有 `_process`，仅敌人变体）:**
```gdscript
# _process 内追加（fsm.update 之后）:
if not is_player and not is_stance_broken and state_name != "dead" and state_name != "revive":
    var now: float = Time.get_ticks_msec() / 1000.0
    if _stance_recover_delay_until_sec >= 0.0 and now >= _stance_recover_delay_until_sec and stance < stance_max:
        stance = clampf(stance + float(C.ENEMY_STANCE_RECOVER_PER_SEC) * delta, 0.0, stance_max)
        emit_signal("stance_changed", stance, stance_max)
```
- **延迟重置（`take_stance_damage` 内追加，受击/被弹反即重置——受击即 `take_stance_damage(35)`、弹反即 `take_stance_damage(25)`，两条路径都走本函数）:**
```gdscript
if not is_player:
    _stance_recover_delay_until_sec = Time.get_ticks_msec() / 1000.0 + float(C.ENEMY_STANCE_RECOVER_DELAY_SEC)
```
- **恢复语义要点:**
  - 崩解期间（`is_stance_broken=true`）不恢复（快线处决窗口不被恢复打断）；
  - `recover_from_break`（50% + 5s 疲惫）后 `is_stance_broken=false` → 恢复机制照常（疲惫只降受击架势伤害倍率，不关恢复）；
  - 玩家实体（`is_player=true`）不触发——玩家架势语义不变（回归全绿）；
  - 恢复中玩家重新攻击 → `take_stance_damage` 重置延迟计时 → 「恢复-再受伤」节拍正确（不出现边恢复边掉架势的闪烁，边界 4）。

### 2.5 EnemyHealthBar（Boss 条组合）

- **文件:** `hud.gd`（修改，additive）
- **节点结构（纯代码创建，零 tscn 零贴图，与 #576 同构）:**
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
- **新增公有成员:**
```gdscript
var EnemyHealthBar: _HudBar        # 顶部中央暗红条（血条+架势条组合的上条）
```
- **`_HudBar` additive 扩展（fill 色覆写，默认行为零变化——玩家两条约 `set_segments` 路径不受影响）:**
```gdscript
# hud.gd 内层类 _HudBar:
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
- **`set_target_enemy` 增订（hp_changed 订阅 + 立即初始化 + 显隐联动）:**
```gdscript
# set_target_enemy 内（既有 stance 订阅旁追加）:
entity.hp_changed.connect(_on_enemy_hp_changed, CONNECT_REFERENCE_COUNTED)
EnemyHealthBar.visible = true
EnemyHealthBar.set_segments([entity.hp_1], [entity.life_1_max], 0)
# null 分支与 _disconnect_enemy 同步追加 EnemyHealthBar 隐藏/断开

func _on_enemy_hp_changed(hp_1: float, _hp_2: float, _active_life: int) -> void:
    EnemyHealthBar.set_segments([hp_1], [_target_enemy.life_1_max], 0)
```
- **died 联动（`_on_enemy_died` 内追加）:** `final=true` → `EnemyHealthBar.visible = false`（与 EnemyStanceBar 同处隐藏）；`final=false`（防御分支）→ `set_segments([0.0], [1.0], 0)`。
- **`_create_nodes` 内创建:** `EnemyHealthBar = _HudBar.new()` + 锚点/offsets 设置 + `EnemyHealthBar.set_fill_color(C.HUD_BLOOD_RED)` + `visible = false`。

---

## 3. 既有组件修改

### 3.1 文件清单总表

| 类别 | 文件 | 变更性质 | 内容摘要 |
|------|------|:---:|------|
| 修改 | `shandong-wolf/gdscripts/constants.gd` | 修改（追加分区 + 1 值上调） | 「精英 AI」分区 8 项 # DRAFT 常量（§2.1 表）+ ENEMY_HP_MAX 40→80 候选上调 |
| 修改 | `shandong-wolf/gdscripts/main_battle.gd` | 修改（一行参数） | 敌人装配消费 ENEMY_HP_MAX + elite_mode=true（HP 慢线接通） |
| 修改 | `shandong-wolf/gdscripts/enemy_ai_states.gd` | 修改（additive） | AttackState 出招三选一（elite_mode 门控）+ 蓄力 override 注入 |
| 修改 | `shandong-wolf/gdscripts/enemy_ai.gd` | 修改（additive） | hit_landed 订阅 + 受击击退位移（_apply_movement） |
| 修改 | `shandong-wolf/gdscripts/combat_entity.gd` | 修改（additive） | 瞬时 override 字段 ×2 + 敌人架势脱战恢复 |
| 修改 | `shandong-wolf/gdscripts/combat_judge.gd` | 修改（additive，2 行） | 窗口登记 fallback 链（windup/hp_damage override） |
| 修改（可选） | `shandong-wolf/gdscripts/combat_attack_window.gd` | 零改动优先 | 蓄力窗口复用 windup_frames 字段；如需按出招区分再加 override（实现期裁决） |
| 修改 | `shandong-wolf/gdscripts/hud.gd` | 修改（additive） | EnemyHealthBar + _HudBar.set_fill_color + set_target_enemy 增订 hp_changed |
| 修改 | `shandong-wolf/tests/test_enemy_ai.gd` | 修改 | 蓄力出招（概率/前摇/伤害）/ 击退位移 / elite 门控用例 |
| 修改 | `shandong-wolf/tests/test_hud.gd` | 修改 | EnemyHealthBar 信号驱动断言 + T5 布局断言同步（26） |
| 修改 | `shandong-wolf/tests/test_combat_entity.gd` | 修改 | 脱战恢复用例（延迟/速率/上限/崩解中不恢复/玩家不触发） |
| 修改 | `shandong-wolf/tests/test_main_assembly.gd` | 修改（可选） | 装配断言：敌人 life_1_max == ENEMY_HP_MAX + elite_mode == true |

### 3.2 各文件修改细节（implement agent 据此可写码）

#### 3.2-1 constants.gd

- 新增「精英 AI」分区（放在既有 AI 分区之后），8 项常量全部带「sekiro 基准 → 候选集 + 影响 + 情感断言」注释（§2.1 表）。
- ENEMY_HP_MAX：默认 40 → **80**，候选集 [30, 40, 50] → **[60, 80, 100]**，情感断言「小兵是消耗品」→「精英是磨刀石：七刀之内是紧张，一刀半血是恐惧」。
- 新增 `HUD_ENEMY_HP_GAP: float = 4.0`（# DRAFT，HUD 分区内）。

#### 3.2-2 main_battle.gd（`_build_enemy`）

```gdscript
# 敌人装配 —— 唯一触碰点（PRD §8.2 顺序 2）
enemy_entity = CombatEntityScript.new({"is_player": false, "life_total": 1,
    "life_1_max": C.ENEMY_HP_MAX})          # ← 新增: 装配显式消费 ENEMY_HP_MAX（慢线接通）
enemy.elite_mode = true                      # ← 新增: MVP 单敌人即精英（蓄力出招启用）
```

#### 3.2-3 enemy_ai_states.gd（AttackState）

```gdscript
# enter(): 出招决策二选一 → 三选一（elite_mode 门控，概率和 = 1）
var _attack_kind: String = "combo"           # "charge" / "thrust" / "combo"
func enter() -> void:
    ...
    if ai.elite_mode and ai._rng.randf() < float(C.ENEMY_CHARGE_CHANCE):
        _attack_kind = "charge"
    elif ai._rng.randf() < float(C.ENEMY_THRUST_CHANCE):
        _attack_kind = "thrust"
    else:
        _attack_kind = "combo"

# update(): 三分支
if _attack_kind == "charge":
    if not _issued:
        ai.entity.current_windup_frames = int(C.ENEMY_CHARGE_WINDUP)
        ai.entity.current_hp_damage = float(C.ENEMY_CHARGE_HP_DAMAGE)
        ai.entity.request_transition("heavy_attack")   # 同步触发 judge 登记（读 override）
        ai.entity.current_windup_frames = -1           # 清空（防泄漏到下一击）
        ai.entity.current_hp_damage = -1.0
        ai._attack_cooldown_until_sec = now + float(C.ENEMY_ATTACK_COOLDOWN_SEC)
        _issued = true
    else:
        ai._ai_fsm.transition_to(SelfScript.make_state("chase", ai))
# thrust / combo 分支 = #581 既有代码原样保留
```

#### 3.2-4 enemy_ai.gd

```gdscript
# 新成员:
@export var elite_mode: bool = false
var _knockback_vel: float = 0.0
var _knockback_dir: int = 1

# _ensure_judge_subscription 追加 hit_landed 订阅（与 parry_success 同构）
# _on_judge_hit_landed: defender != entity → 早退；否则设 _knockback_dir/_knockback_vel
# _apply_movement 追加击退分支（§2.3 伪代码）: 击退覆盖位移意图 + 衰减 + STAGE_WIDTH_PX clamp
```

#### 3.2-5 combat_entity.gd

```gdscript
# 新成员（additive）:
var current_windup_frames: int = -1
var current_hp_damage: float = -1.0
var _stance_recover_delay_until_sec: float = -1.0

# _process 追加: 敌人架势脱战恢复轮询（§2.4 伪代码，仅 is_player=false）
# take_stance_damage 追加: 敌人受击/弹反重置恢复延迟计时（§2.4）
```

#### 3.2-6 combat_judge.gd（`_on_entity_state_changed`）

```gdscript
# 敌人分支 windup fallback 链 + hp_damage 取值链（§2.2 伪代码，additive 两处）
```

#### 3.2-7 hud.gd

```gdscript
# _create_nodes: EnemyHealthBar 创建（§2.5 节点结构）+ set_fill_color(C.HUD_BLOOD_RED)
# set_target_enemy: hp_changed 订阅 + 初始化 + visible；null 分支隐藏；_disconnect_enemy 追加
# _on_enemy_hp_changed / _on_enemy_died 联动（§2.5）
# _HudBar: set_fill_color + _draw 分支（§2.5，默认行为零变化）
```

#### 3.2-8 测试文件修改（测试描述见 §8，不写可运行代码）

| 文件 | 变更 |
|------|------|
| `tests/test_enemy_ai.gd` | 新增 E 组精英用例（elite_mode=true）：蓄力出招概率/前摇 20/伤害 25、击退位移与衰减、elite=false 回归；既有 36 条用例零改动 |
| `tests/test_hud.gd` | 新增 EnemyHealthBar 用例（注入可见/hp_changed 驱动比例/died 隐藏）；T5 布局断言 12→26 同步 |
| `tests/test_combat_entity.gd` | 新增脱战恢复用例（延迟窗口内不恢复/超时逐帧恢复至上限/崩解不恢复/玩家不触发/恢复-再受伤重置） |
| `tests/test_main_assembly.gd` | 可选装配断言：enemy_entity.life_1_max == ENEMY_HP_MAX、enemy.elite_mode == true |

---

## 4. 数据流

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

### Flow 5: 受击击退（新，issue「僵直/后退」后半）

```
judge.resolve_attack 命中 → emit hit_landed(defender=enemy, attacker=player, ...)
  → EnemyAI._on_judge_hit_landed: defender==entity → _knockback_dir = 远离玩家
  → _knockback_vel = 40（ENEMY_KNOCKBACK_PX）
  → _physics_process → _apply_movement: 击退分支覆盖位移意图 → velocity.x = dir*vel
  → 每帧 vel -= 3*delta（ENEMY_KNOCKBACK_DECAY）→ 12 帧 stagger 内衰减归零
  → position.x clamp [0, 2400]（STAGE_WIDTH_PX 兜底）→ 恢复后 Chase 从落点继续（无弹簧抖动）
```

---

## 5. 边界条件与错误处理

| 边界用例 | 缓解 |
|---------|------|
| 击退与追击叠加抖动（击退后被拉回） | 击退速度线性衰减（ENEMY_KNOCKBACK_DECAY=3/s，进 constants）；stagger 12 帧期间决策门控禁止 Chase 位移（#581 既有）——衰减先于 stagger 结束归零，恢复后从落点继续 Chase |
| 蓄力攻击在连段中被打断（前摇期间被弹反） | parry_success → 抑制窗接管（#581 边界 7 复用）；蓄力窗口同样被抑制窗覆盖——AI 回 Chase，连段计划作废 |
| 玩家削血击杀与架势崩解同帧竞争 | 既有守卫：take_damage 先判 hp≤0 → die()（终态锁）；break_stance 幂等 + 终态后 AI 禁用（#581 既有）；测试覆盖同帧双归零 |
| 脱战恢复与战斗再触发（恢复-再受伤闪烁） | take_stance_damage 重置延迟计时 → 恢复暂停；「恢复-再受伤」节拍正确（不出现边恢复边掉架势） |
| 敌人血条在处决/死亡后的显隐 | execute_kill → died(final) → 双条隐藏（_on_enemy_died 扩展）；处决演出期间血条保持 0 隐藏（#576 既有路径） |
| 精英参数档位缺省（装配未注入 elite_mode） | elite_mode=false = #581 小兵行为（二选一出招），不报错——向后兼容 #581 场景与既有测试 |
| 蓄力概率与突刺概率互斥（和 = 1 约束） | 三选一掷骰序：charge（ENEMY_CHARGE_CHANCE）→ thrust（ENEMY_THRUST_CHANCE）→ combo（余量）；概率非法（>1）→ push_warning + 回退二选一 |
| 击退目标越界 | position.x clamp [0, STAGE_WIDTH_PX=2400]（#583 舞台尺寸，纯 clamp 不引入新物理） |
| override 字段泄漏到下一击（蓄力后普通攻击带 20 帧前摇） | 出招后同步清空（current_windup_frames=-1 / current_hp_damage=-1.0）；judge 登记 fallback 链默认回退 ENEMY_ATTACK_WINDUP/attack_hp_damage |
| 敌人架势恢复与 #580 恢复双写竞态（脱战恢复 vs recover_from_break 同帧） | 幂等守卫：is_stance_broken 检查（崩解中轮询跳过）+ 恢复仅非崩解态执行；测试注入同帧双触发断言最终值 ∈ [0, stance_max] |
| ENEMY_HP_MAX 上调对既有测试的冲击 | test_enemy_ai.gd:136 动态读常量自动跟随；其余 fixture 显式传 life_1_max=40.0（局部配置不受影响）；test_main_assembly 新增装配断言拦截回退 |
| 蓄力窗口未注入（override 漏设回落 12 帧） | judge 登记时断言：elite 蓄力出招窗口 windup == ENEMY_CHARGE_WINDUP（测试拦截「弹反过于容易」） |

---

## 6. 集成点

> **Status 约定:** ⬜ = pending（资源已创建，尚未连接目标）；✅ = connected（implement agent 验证）。implement agent 必须在接线时更新本表。review agent 在合并前验证所有 ⬜ 已解决或显式延期。

| 集成 | 本组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|-----|:---:|
| HP 慢线装配 → 敌人实体 | main_battle.gd `_build_enemy` | #585 | `life_1_max: C.ENEMY_HP_MAX` + `enemy.elite_mode = true` | ⬜ pending |
| 蓄力出招 → 窗口登记 | enemy_ai_states.gd → combat_entity.gd override → combat_judge.gd | #577/#581 | `request_transition("heavy_attack")` 同步触发登记；fallback 链读取 override | ⬜ pending |
| 受击 → 击退位移 | judge.hit_landed → EnemyAI._on_judge_hit_landed → _apply_movement | #579（事件源复用） | 信号订阅（与 parry_success 同构）；渲染层零改动 | ⬜ pending |
| 敌人受击/弹反 → 脱战恢复 | take_stance_damage → CombatEntity._process | #575 | 延迟重置 + 轮询恢复（仅 is_player=false） | ⬜ pending |
| 敌人 HP → Boss 条 | CombatEntity.hp_changed → Hud.EnemyHealthBar | #576 | set_target_enemy 订阅 + _HudBar.set_fill_color | ⬜ pending |
| 崩解 → 处决窗口 | stance_broken → ExecutionOrchestrator | #580 | 既有衔接确认（零改动，回归全绿） | ✅ 既有 |
| 精英档位 → #589 军曹 | EnemyAI.elite_mode + 常量组 + Boss 条 UI | #589（backlog） | 内容 issue 叠加武器/危攻击/霸体，零重复实现 | ⬜ 移交 |
| 数值候选 → #584 定稿 | constants 精英分区 # DRAFT | #584（human-review） | 候选集 + 情感断言注释移交调参面板 | ⬜ 移交 |

---

## 7. 实现阶段

| Phase | 优先级 | 组件 | 估算 |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | constants.gd 精英分区 8 常量 + ENEMY_HP_MAX 上调 + HUD_ENEMY_HP_GAP | 0.2d |
| Phase 2 | P0 | combat_entity.gd override 字段 ×2 + 敌人脱战恢复（_process + take_stance_damage 重置） | 0.5d |
| Phase 3 | P0 | combat_judge.gd fallback 链（windup/hp_damage 两处） | 0.2d |
| Phase 4 | P0 | enemy_ai_states.gd AttackState 三选一 + 蓄力 override 注入（elite_mode 门控） | 0.5d |
| Phase 5 | P0 | enemy_ai.gd hit_landed 订阅 + 击退位移（_apply_movement + clamp） | 0.5d |
| Phase 6 | P0 | main_battle.gd 装配一行参数（life_1_max + elite_mode） | 0.1d |
| Phase 7 | P0 | hud.gd EnemyHealthBar + set_fill_color + set_target_enemy 增订 + T5 布局同步 | 0.5d |
| Phase 8 | P0 | 测试：test_enemy_ai（E 组）/ test_hud / test_combat_entity / test_main_assembly | 0.5d |
| Phase 9 | P1 | 实验 1 复验（蓄力 windup 20 vs 弹反闭区间） + 实验 2 复验（脱战恢复节奏 vs 崩解频率） | 0.3d |

依赖顺序: Phase 1（常量先锁）→ 2/3（数据层 + 判定层）→ 4/5（行为层）→ 6（装配接通）→ 7（UI）→ 8（测试锁定契约，可与 4-7 并行后置）→ 9（实验复验）。估算合计 ≈ 2.5d（PRD §4.1 Effort 对齐）。

---

## 8. 测试用例描述

> 只描述测试场景，**不写可运行测试代码**（实现归 implement agent）。既有 1314 单测基线全绿不动（elite_mode=false 默认路径回归）。

### Scenario A: 精英装配与 HP 慢线（AC5）
- Test A1（装配消费常量）: `main_battle.gd` 装配后 `enemy_entity.life_1_max == C.ENEMY_HP_MAX`（80）、`hp_1 == 80`、`enemy.elite_mode == true`
- Test A2（多次攻击才击杀）: 轻击 12/刀 ×6 → `hp_1 > 0`（未死）；×7 → `died(final=true)`（慢线 7 刀，非一击毙命）
- Test A3（hp_changed 信号链）: 每次削血 → hp_changed 参数正确（80→68→...）；hp 归零走 die() 终态（非处决演出）

### Scenario B: EnemyHealthBar（AC6）
- Test B1（注入可见）: set_target_enemy 后 `EnemyHealthBar.visible == true`、`EnemyStanceBar.visible == true`；双条同锚点（anchor 0.5）
- Test B2（布局）: EnemyHealthBar size == (240, 10) 且 offset_top == HUD_ENEMY_BAR_TOP（12）；EnemyStanceBar offset_top == 26（HUD_ENEMY_BAR_TOP + HUD_BAR_HEIGHT + HUD_ENEMY_HP_GAP）——T5 断言同步更新
- Test B3（信号驱动比例）: 注入 set_debug 驱动 hp_changed(40, 0, 1) → `get_segment_fractions() == [0.5]`；fill 色为 HUD_BLOOD_RED（set_fill_color 生效）
- Test B4（died 隐藏）: died(final=true) → 双条 `visible == false`；set_target_enemy(null) → 双条隐藏
- Test B5（玩家条回归）: 玩家血条/架势条零变化（fill_override 默认关闭 → 月白活性段）

### Scenario C: 蓄力重斩出招（AC2 扩展 + 实验 1）
- Test C1（elite 门控）: elite_mode=false → 长序列出招不含 charge 形态（突刺/三连砍二选一，回归 #581）；elite_mode=true → 扫描种子存在 charge 形态
- Test C2（概率分布）: elite=true + 固定种子序列 → charge 出招比例 ≈ ENEMY_CHARGE_CHANCE（±0.05 容差）；三形态概率和 = 1
- Test C3（窗口前摇）: 蓄力出招 → judge 登记窗口 `windup_frames == ENEMY_CHARGE_WINDUP`（20）、`hp_damage == ENEMY_CHARGE_HP_DAMAGE`（25）
- Test C4（override 清空）: 蓄力后下一击（突刺/三连）窗口 windup 回落 ENEMY_ATTACK_WINDUP（12）——无泄漏
- Test C5（可弹反，实验 1 落地）: 蓄力窗口闭区间边界三态（lower/hit/超出）弹反判定正确；20 帧前摇下弹反成功（窗口绝对时长 0.33s）——难度数据记录交 #584

### Scenario D: 受击击退（issue「僵直/后退」后半）
- Test D1（触发）: judge 命中敌人 → `_knockback_vel == ENEMY_KNOCKBACK_PX`、方向远离攻击者
- Test D2（位移）: 推进 5 帧 → 敌人 x 位移方向正确、幅度与衰减一致（`vel` 每帧减 ENEMY_KNOCKBACK_DECAY*delta）
- Test D3（衰减归零）: 推进至 stagger 结束 → `_knockback_vel == 0`，恢复后 Chase 位移正常（无弹簧抖动）
- Test D4（玩家不受击退）: 玩家被击中 → 敌人 `_knockback_vel` 不变（defender != entity 早退）
- Test D5（越界兜底）: 敌人贴边（x=0/2400）受击 → position.x clamp 在 [0, 2400]

### Scenario E: 架势脱战恢复（AC8 + 实验 2）
- Test E1（延迟窗口内不恢复）: 注入 take_stance_damage(35) → 2.5s 内推进 → stance 不变
- Test E2（超时恢复）: 延迟窗过后推进 → stance 逐帧 += ENEMY_STANCE_RECOVER_PER_SEC*delta，至 stance_max 封顶
- Test E3（崩解中不恢复）: break_stance 后推进 → stance 保持 0（快线窗口不被恢复打断）
- Test E4（玩家不触发）: is_player=true 实体受击 → 无恢复（玩家架势语义不变）
- Test E5（恢复-再受伤重置）: 恢复 1s 后再注入 stance 伤害 → 延迟计时重置，恢复暂停（无闪烁）
- Test E6（双写竞态，实验 2 落地）: 脱战恢复与 recover_from_break 同帧双触发 → 最终 stance ∈ [0, stance_max]；弹反序列（间隔 1.2s < 延迟 2.5s）下 4 弹反仍可崩解（快线成立）

### Scenario F: 失败路径（PRD §5.3 拦截）
- Test F1（HP 装配漏改）: life_1_max 回落默认 100 → test_main_assembly 装配断言拦截
- Test F2（蓄力窗口未注入）: 蓄力出招窗口 windup == 12（漏设 override）→ C3 断言拦截
- Test F3（血条未绑定）: set_target_enemy 后 hp_changed 不驱动 EnemyHealthBar → B3 断言拦截

### Scenario G: 既有回归（红线验证）
- Test G1: elite_mode=false 全量 #581 用例（36 条）逐条通过（行为逐字节一致）
- Test G2: #577 弹反/拼刀/格挡五结果事件顺序不变（judge fallback 链默认路径）
- Test G3: #580 处决窗口衔接回归（stance_broken → armed → execute，编排器零改动）
- Test G4: 玩家实体全部用例回归（脱战恢复仅 is_player=false）

---

## 9. 验收条件映射（源自 Issue #682 body 5 条 + 补充 4 条 + PRD §5.1）

- [ ] **AC1: 敌人会主动接近并攻击玩家（无需玩家贴脸）** —— ✅ 既有（#581 chase+attack），本 issue 维持 + elite_mode 档位（§2.1）；追击速度/冷却维持 #581 默认（§1.2 gap 3 范围收敛，候选移交 #584）
- [ ] **AC2: 敌人攻击可被弹反，弹反后敌人硬直** —— 既有回归（#577 闭区间 + #581 抑制窗）+ 新蓄力重斩可弹反（§2.2 + Scenario C5）
- [ ] **AC3: 敌人架势条崩解后可处决** —— ✅ 既有（#580 armed 3s 窗口），本 issue 确认衔接（Flow 2 回归）
- [ ] **AC4: 玩家不操作时敌人会持续进攻（可观察 AI 行为）** —— ✅ 既有（#581 冷却 1.5s 循环），维持
- [ ] **AC5: 敌人有血条，普通攻击需多次才能击杀（非一击毙命）** —— §3.2-2 装配消费 ENEMY_HP_MAX（80）+ Scenario A2（7 刀慢线）
- [ ] **AC6: 敌人血条/架势条 UI 可见（顶部 Boss 条）** —— §2.5 EnemyHealthBar（240×10 暗红）+ EnemyStanceBar 下移组合 + Scenario B1-B4
- [ ] **AC7: 架势崩解后进入处决窗口（与 #580 衔接）** —— ✅ 既有（Flow 2 回归，编排器零改动）
- [ ] **AC8: 架势脱战恢复（不无限崩解）** —— §2.4 敌人专用恢复（延迟 2.5s + 20/s）+ Scenario E1-E6
- [ ] **实验 1: 蓄力前摇 vs 弹反闭区间时序** —— Scenario C5（数据记录交 #584 裁决）
- [ ] **实验 2: 脱战恢复节奏 vs 崩解频率** —— Scenario E6（快线不被恢复打断）

## 10. 明确不修改（与 PRD §8.5 交接红线对齐）

- **不修改** 11 态 `CANONICAL_STATES` / `consume_state` 契约（combat_state_table.gd 零改动；精英行为仍是 AI 行为态）
- **不修改** #577 五结果事件名与裁决顺序（combat_judge.gd 仅 2 处 fallback 链 additive）；**不引入 Area2D/CollisionShape2D 物理碰撞**
- **不修改** #580 处决编排器（execution_orchestrator.gd 零改动——只消费 stance_broken/armed 窗口衔接）
- **不修改** #589 军曹/#590 汉奸内容（危攻击/霸体/体型/掉落/二阶段/台词/演出——本 issue 只交付通用精英模板）
- **不修改** 玩家实体行为（脱战恢复仅 is_player=false；玩家 HP/架势/HUD 区块零改动）
- **不修改** 既有接口签名（entity/judge/AttackWindow 全部 additive；既有 19 测试文件默认路径全绿）
- **不修改** `mini-pong/` 任何文件、`scenes/Main.tscn`、`project.godot`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`（post-merge agent 负责）
- **不裁决** # DRAFT 数值（constants 精英分区只读 + 候选集移交 #584；EnemyHealthBar 视觉色相差异走 #576 human-review 通道）
- **不写可运行测试文件**（本 issue 只产出 DESIGN/TASKS 文档 + 测试用例描述；测试代码归 implement agent）
- **不 merge 自己的 PR**（workflow-chain 自动推进；stage-gate.py 校验）

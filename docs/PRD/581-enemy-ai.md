# PRD #581 — [Feature] 基础日本兵 AI（巡逻 / 追击 / 攻击 / 被弹反）

> **Issue:** #581
> **标签:** enhancement, gameplay, content, version/mvp, workflow/research（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=10）
> **深度:** standard（分解 JSON id=10 标注 `depth: standard` → §1–6 + §8 必填；§7 可选，本 PRD 含 3 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-20
> **所有权:** `content_ownership: mechanical`（AI 行为/感知/决策=机械工程；手感数值全部 # DRAFT 只读，定稿归 #584）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Users/devvi/~/Documents/Obsidian Vault/`：wiki grep 只狼/敌人 → `wiki/游戏设计理念.md`（只狼=「机制作为修辞」的灵感来源）、`wiki/JRPG战斗系统演变.md`（敌人 AI 决策范式演变）；raw grep 敌人/AI/状态机 → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（阶段 4 混合探索期「条件→行动」FSM 决策范式、「AI 队友智能行动」、难度自适应）、`raw/Bear/state machine.md`（状态机记录范式））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`：敌人=『压迫感』来源、攻击前摇「舞刀」预备帧、5% 后退回避、反页游木桩）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：敌小兵 1 管架势、危攻击前摇 14-18 帧可识破、敌人 HP 30-50、受击双重惩罚）+ 同链 issues（#575 已 merged / #577 已 merged / #578 复活 / #579 反馈 / #580 处决 / #583 场景 / #584 数值 / #585 组装）+ 开源调研（GitHub API 检索 godot+enemy+ai / godot+behaviour+tree，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=10，estimate 3d，priority high，milestone mvp）
> **前置依赖:** #575（CLOSED，PR #618 merged：CombatEntity + 11 态战斗状态机 + 转移表 + 敌人变体参数）、#577（CLOSED，PR #626 merged：CombatJudge + AttackWindow 判定层 + 攻击窗口自动登记）——全部已满足

---

## 1. 问题定义

### 1.1 现状（2026-08-20 worktree 侦查 @ origin/main f85bbd7）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ 已交付（#575/#618） | `is_player` / `life_total` / `stance_max` @export 变体参数——敌人变体 = `new(is_player=false, life_total=1)` 即得；`request_transition()` 唯一转移入口（查表合法才转移）；`take_damage`/`take_stance_damage`/`break_stance`/`die` + 6 信号——**AI 层在其上叠加，不改接口** |
| `shandong-wolf/gdscripts/combat_state_table.gd` | ✅ 已交付（#575/#618） | 11 态 `CANONICAL_STATES` 权威集（与 #574 consume_state 逐字对齐，**禁止增删状态名**）；`idle/move → attack/heavy_attack` 表内——敌人攻击转移合法；`parry_success → idle` 表内 |
| `shandong-wolf/gdscripts/combat_states.gd` | ✅ 已交付（#575/#618） | 状态对象范本（StateMachineBase 三接口 enter/exit/update + `restart()` 连段钩子）；parry_success 10 帧（PARRY_SUCCESS_FRAMES）自动退出 ≈ 0.167s；stagger 12 帧；stance_break 3.0s——**敌人复用同一套战斗状态，AI 不复制状态逻辑** |
| `shandong-wolf/gdscripts/combat_judge.gd` | ✅ 已交付（#577/#626） | `_on_entity_state_changed`：**任意实体进入 attack/heavy_attack 态自动登记 AttackWindow**（start_frame=judge 帧、active_frames=HITBOX_ACTIVE_FRAMES、hp_damage=玩家刀伤害 SWORD_DAMAGE_LIGHT/HEAVY、stance_damage=POSTURE_HIT_COST、direction=entity.facing）；`resolve_attack` 弹反→拼刀→格挡→受击优先级全走常量；距离/facing 校验用 HITBOX_RANGE=80——**⚠️ 两处待参数化（见下）** |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | ✅ 已交付（#577/#626） | `hit_frame() = start_frame + FRAME_ATTACK_WINDUP`（**硬编码玩家 8 帧前摇**）——**⚠️ 敌人前摇 12/15 帧时命中帧会错位，需加 windup 字段（additive）** |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#584/#609） | `ENEMY_ATTACK_WINDUP=15`（候选 [12,15,18]——**⚠️ issue AC1 要求 12 帧，裁决点见 §8.4-1**）；`PARRY_STANCE_DAMAGE=25`（4×25=100=POSTURE_BREAK_THRESHOLD，**AC2「连续 4 次弹反崩解」数值自洽**）；`POSTURE_HIT_COST=35`；`HITBOX_RANGE=80`；`MOVE_MAX_SPEED=300`/`MOVE_ACCELERATION=1200`（移动模型基准）——**❌ 缺 AI 分区常量**（感知范围/角度、巡逻/追击速度、攻击冷却/伤害、弹反硬直抑制、后退回避概率，见 §8.3） |
| `shandong-wolf/gdscripts/player_controller.gd` | ✅ 已交付（#573/#611） | CharacterBody2D 加速度移动模型（`velocity.x = move_toward(velocity.x, dir*MAX_SPEED, ACCEL*delta)` + move_and_slide）——**敌人移动实体可仿照此模型** |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | ✅ 已交付（#574/#612） | `consume_state(state)` 唯一动画入口（canonical 11 态 + 别名）——**敌人复用 SW-003 火柴人骨架**：patrol/chase 走 move/idle 动画，攻击/硬直由战斗态自动驱动，AI 层零渲染 |
| `shandong-wolf/scenes/player_stick_figure.tscn` | ✅ 组合范本 | StickFigureController 根 + StickFigure 子 + AnimationPlayer——敌人场景组合归 #583/#585，本 issue 不组装 |
| `shandong-wolf/tests/` | ✅ 三入口 + combat 套件 | run_tests.gd 已挂 test_combat_entity/test_combat_judge；本 issue 追加 test_enemy_ai.gd |
| `shandong-wolf/gdscripts/` | ❌ 无 AI 层 | 无 EnemyAI、无行为状态对象、无感知（120° 视线 6m）、无敌人移动实体、无攻击决策——**本 issue 全部新建** |

**核心缺口：** 战斗层原料全部就绪且敌人变体接口全预留（#575 注释明言「敌AI 用 enemy 变体」、#577 注释明言「敌人 MVP 由 #581 登记窗口」、判定层对任意实体自动登记攻击窗口），但**「谁驱动敌人」零存在**——没有行为状态机（巡逻→追击→攻击→回避）、没有感知（120° 视线 6m）、没有移动实体、没有攻击决策。所有「敌人动起来」的行为逻辑都未落地。

### 1.2 验收条件（源自 Issue #581 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | 日本兵具备 巡逻→追击→攻击 状态流转，攻击前摇 12 帧且前摇期间可被弹反 | §4.1 方案 A（EnemyAI 独立行为状态机 + 判定层自动窗口）+ §5.1 AC1：AI 状态机三态流转；攻击窗口 windup 参数化（§8.3）保证前摇帧=ENEMY_ATTACK_WINDUP 且窗口内弹反判定走 #577 既有闭区间逻辑 |
| AC2 | 被弹反后硬直 0.5s 并增加 25 架势值，连续 4 次弹反可崩解（数值来自 constants.gd） | §5.1 AC2：PARRY_STANCE_DAMAGE=25 只读消费（4×25=100=stance_max 崩解，数值自洽）；0.5s 硬直 = AI 层弹反抑制窗 ENEMY_PARRY_STUN_SECONDS（共享 parry_success 态仅 0.167s，硬直时长由 AI 决策门控补足，§4.1-决策门控） |
| AC3 | AI 有 5% 概率在玩家攻击前摇时后退闪避 | §5.1 AC3：ENEMY_RETREAT_CHANCE=0.05（# DRAFT）读 constants；玩家 state_changed→attack/heavy_attack 触发判定（§4.1-RetreatState）；RNG 可注入（seed 可控）便于单测（§7 实验 2） |
| AC4 | AI 参数全部从 constants.gd 读取 | §5.1 AC4 + §8.3：感知/速度/冷却/伤害/概率/抑制窗全走 WolfConstants 新 AI 分区，禁硬编码；新常量标 # DRAFT + 候选集 |
| AC5 | smoke test：玩家站桩时敌人 5s 内完成巡逻→发现→接近→攻击的路径 | §5.1 AC5 + §8：test_enemy_ai.gd 主路径用例——模拟 5s 内敌人从 patrol 到 entity.state_name=="attack"（玩家站桩在感知范围内） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机战斗（MVP 压迫感来源） | 每次游玩 | 雪夜村口：日本兵沿固定路径巡逻（火柴人步态）→ 玩家进入 120° 视线 6m 内 → 转身追击 → 近身三连砍或突刺（前摇「舞刀」预备帧可读）→ 玩家弹反成功 → 敌人 0.5s 硬直 + 架势 +25 → 第 4 次弹反架势崩解（3s 失衡）→ 处决（#580）；偶尔（5%）玩家出刀时敌人后退一步再扑 |
| B | 下游系统消费（#579/#580/#583/#585） | 每次 impl PR | 判定层结果事件（parry_success/hit_landed/clash/stance_broken）驱动 #579 反馈；stance_break → #580 处决；#583 场景放置敌人出生点与巡逻路径；#585 组装 EnemyAI+CombatEntity+StickFigureController 进场景 |
| C | 开发者 headless 验证 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`：构造玩家站桩 + 敌人实体 + EnemyAI，手动 `decide(delta)` 推进，断言 5s 内巡逻→发现→追击→攻击全路径；不依赖场景树与真实输入 |

### 1.4 范围边界（Patch 14 去冲突 + 组装/判定层红线）

| PRD / 分解 id | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #575（实体/状态机，merged） | CombatEntity 数据容器 + 11 态转移 + 敌人变体参数 | ❌ 不重写战斗状态；只**消费** request_transition/take_* 接口与 state_changed/stance_broken 信号；仅做两处 **additive** 参数扩展（攻击伤害 @export，§3.1） |
| #577（判定，merged） | CombatJudge + AttackWindow + 五结果事件 | ❌ 不重写判定逻辑；复用自动窗口登记与弹反/拼刀/格挡/受击裁决；仅做两处 **additive** 参数化（攻击伤害取值 + window windup 字段，§3.1） |
| 分解 id 9 / #580（处决，未开始） | stance_break → 处决演出/敌人淡出 | ❌ 不做处决；本 issue 只保证敌人 stance_break 态由战斗状态机自然驱动（3s 恢复），处决接管归 #580 |
| 分解 id 7 / #578（复活，未开始） | 玩家两条命复活 | ❌ 敌人 life_total=1（die 即终态）；玩家复活流与本 issue 无关 |
| 分解 id 12 / #583（场景，未开始） | 场景平台/敌人出生点/巡逻路径坐标 | ❌ 不做场景；本 issue 交付可 headless 实例化的 EnemyAI 类，出生点/waypoint 坐标是场景配置数据（#583 提供，EnemyAI 以 @export 数组接收） |
| 分解 id 14 / #585（组装，未开始） | 玩家/敌人节点组装进场景 | ❌ 不做场景组装；本 issue 交付 EnemyAI（CharacterBody2D）+ 组合约定（§8.3），组装归 #585 |
| #584（数值 DRAFT，merged + human-review） | 全量 # DRAFT 数值 + 调参面板 | ❌ 不裁决数值；AI 新常量全部标 # DRAFT + 候选集只读引用，定稿归 #584 |
| #586（E2E，未开始） | 端到端截图裁决 | ❌ 不做 E2E；本 issue 交付 smoke test 路径，E2E 剧本归 #586 |

**AI 层红线（issue body + 代码注释三重声明）：**
- AI 状态是**行为层**，不是战斗状态——11 态 `CANONICAL_STATES` / `consume_state` 契约一字不改（#575 状态名权威集红线）；巡逻/追击/回避 = AI 行为状态，动画一律映射到既有 move/idle/attack 等战斗态
- 攻击判定零物理碰撞——复用 #577 逻辑帧窗口（judge 自动登记），不引入 Area2D/CollisionShape2D
- 全部数值走 constants.gd # DRAFT 只读，禁止实现期定稿
- AI 自身不渲染——完全复用 SW-003 火柴人骨架（consume_state 驱动），攻击特效归 SW-008（#579），雾/雪归 SW-011（#582）

---

## 2. 设计意图

### 2.1 为什么现在做

1. **战斗层原料全部就绪（2026-08-20）**：#575 敌人变体接口（is_player=false/life_total=1）与 #577 判定层自动窗口登记均已 merged——敌人「能被打、能被弹反、能崩解」的**承受面**已完整，只差「能动、能打人」的**驱动面**。这是 MVP 战斗闭环（#585 组装）的最后一个行为组件。
2. **只狼/审美坐标对齐（sekiro-tuning-reference + brief）**：敌人不是靶子是『压迫感』来源——「舞刀」预备帧（前摇可读）、5% 后退回避（反页游木桩）、崩解可处决（只狼铁律 2）。感知/攻击/回避三组数值全部可调（# DRAFT），手感基调由本层行为节奏承载。
3. **依赖链已解锁**：issue body 前置依赖 #575、#577 均 CLOSED；#583（场景）与 #585（组装）尚未开始——本层先落地行为类，场景/组装按 §8.3 组合约定接入即可，不阻塞。

### 2.2 为什么是本层（历史成因）

| 约束 | 来源 | 详情 |
|------|------|------|
| 「使用通用状态机扩展」 | issue body 明示 | StateMachineBase（#572）三接口契约 + 状态对象工厂范式（#575 combat_states.gd）——AI 行为状态对象按同一范式派生，不引入新状态机框架 |
| 攻击窗口登记契约 | #577 §8.3 | 「#581 敌AI 与玩家攻击共用 AttackWindow 契约」——本 issue 是契约的消费方/落地方 |
| 敌人变体参数化 | #575 交付契约 | 敌我差异走 @export 参数（life_total=1 / stance_max / 攻击伤害），AI 层不复制数据模型 |
| 判定/演出分层 | issue body + brief | 攻击特效归 SW-008（#579）、环境归 SW-011（#582）、处决归 #580——本层只做**行为决策与移动** |

### 2.3 本层设计意图

- **行为层与战斗层解耦**：EnemyAI 是独立 Node（CharacterBody2D 移动实体），持有自己的 StateMachineBase 实例（AI 行为状态：patrol/chase/attack/retreat）；战斗状态（11 态）与判定（#577）原样复用。AI 决策 → 调用 `entity.request_transition("attack"/"heavy_attack")` + 驱动位移；战斗结果（弹反/受击/崩解）→ 经 state_changed/stance_broken 信号**反向**门控 AI 决策。两层单向依赖，可 headless 单测。
- **决策门控 = 硬约束**：AI 只在实体处于 `idle`/`move` 态时做决策（战斗动画/硬直期间由 combat FSM 接管，AI 不抢戏）；弹反命中后 AI 进入 ENEMY_PARRY_STUN_SECONDS 抑制窗（0.5s 硬直 = AC2 的补足层，共享 parry_success 态仅 0.167s）。杜绝「硬直中敌人还在追击」的穿帮。
- **感知 = 几何判据，不是物理**：120° 视线锥用 facing 方向点积 + 水平距离 + 高度容忍判定（横板一维为主），无 raycast/无 Area2D——与 #577「零碰撞体」架构一致。
- **复用判定层自动窗口**：#577 的 `_on_entity_state_changed` 已对任意实体进入 attack 态自动登记窗口——AI 无需手动登记，只需保证敌人攻击伤害可配置（§3.1 参数化补丁）与窗口前摇帧正确（windup 字段）。
- **数值全走 constants**：感知范围/速度/冷却/伤害/概率/抑制窗全部新增 AI 分区 # DRAFT 常量，AI 代码零字面量。

---

## 3. 影响分析

### 3.1 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/enemy_ai.gd` | **新增** | EnemyAI（`extends CharacterBody2D`）：持有 StateMachineBase（AI 行为 FSM）+ 感知（120° 视线 6m）+ 决策门控 + 位移（加速度模型仿 #573）；`decide(delta)` 纯决策方法（headless 可手动驱动）与 `_physics_process`（move_and_slide）分离；@export：waypoints 巡逻路径 / 玩家引用 / 判定器引用 / RNG seed |
| `shandong-wolf/gdscripts/enemy_ai_states.gd` | **新增** | AI 行为状态对象（基于 StateMachineBase 三接口派生）：PatrolState（waypoint ping-pong）/ ChaseState（逼近+转向+停距）/ AttackState（三连砍/突刺决策 + 冷却）/ RetreatState（5% 回避）——写法范本 = combat_states.gd |
| `shandong-wolf/gdscripts/constants.gd` | 修改 | 追加 AI 分区 # DRAFT 常量（§8.3 清单：感知/速度/冷却/伤害/概率/抑制窗），全部「只狼基准或 issue body → 候选 + 影响 + 情感断言」注释，定稿归 #584 |
| `shandong-wolf/gdscripts/combat_entity.gd` | 修改（additive） | 追加 `@export var attack_hp_damage: float = -1.0` 与 `@export var attack_stance_damage: float = -1.0`（-1 = 兜底玩家刀伤害常量，玩家行为零变化）——敌人变体由此携带自身攻击伤害，供判定层读取 |
| `shandong-wolf/gdscripts/combat_judge.gd` | 修改（additive） | `_on_entity_state_changed` 自动登记窗口时：`hp_damage` 改读 `entity.attack_hp_damage`（≥0 用实体值，否则玩家常量兜底）、`stance_damage` 同理；`windup_frames` 改读 `ENEMY_ATTACK_WINDUP`（敌人）/ 默认玩家前摇——**不改任何现有接口/事件/裁决顺序** |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | 修改（additive） | 追加 `var windup_frames: int = -1`（-1 → 回退 `FRAME_ATTACK_WINDUP`）；`hit_frame()` 用 `windup_frames >= 0 ? windup_frames : FRAME_ATTACK_WINDUP`——兼容现有玩家窗口，敌人窗口前摇帧正确 |
| `shandong-wolf/tests/test_enemy_ai.gd` | **新增** | 主路径（巡逻→发现→追击→攻击 5s）+ 感知边界（角度/距离/高度容忍）+ 5% 回避（seed 注入统计）+ 弹反硬直抑制窗 + 参数常量读取断言（§5/§7 落地） |
| `shandong-wolf/tests/run_tests.gd` | 修改 | 注册 test_enemy_ai.gd |
| `shandong-wolf/tests/smoke_test.gd` | 修改（可选） | AC5 冒烟：玩家站桩 + 敌人 5s 内完成巡逻→发现→接近→攻击路径 |

### 3.2 间接受影响的模块（下游消费者，本次不改）

| 文件/系统 | 影响 | 消费方式 |
|-----------|------|---------|
| #579 打击反馈（未建） | 敌人攻击命中玩家 → hit_landed 事件（已有契约） | 信号订阅（#577 已发射） |
| #580 处决（未建） | 敌人 stance_break → 处决触发（3s 窗口） | stance_broken 信号 + entity 引用 |
| #583 场景（未建） | 敌人出生点 + 巡逻 waypoint 坐标 | EnemyAI.waypoints @export 场景配置 |
| #585 组装（未建） | EnemyAI + CombatEntity(is_player=false) + StickFigureController 组合进场景 | 节点组合（§8.3 组合约定） |
| #586 E2E（未建） | 敌人巡逻/攻击行为截图裁决 | e2e_shots.json 剧本 |

### 3.3 数据流

```
玩家攻击（#573 输入）
    │
    ▼
玩家 CombatEntity.state_changed → "attack" ──► EnemyAI.RetreatState 监听（5% 概率触发）
    │
    ▼
EnemyAI 行为 FSM（patrol/chase/attack/retreat）
    ├── request_transition("attack"/"heavy_attack") ──► 敌人 CombatEntity（11 态战斗 FSM）
    │        └── state_changed ──► CombatJudge._on_entity_state_changed（自动登记 AttackWindow：
    │                                 windup=ENEMY_ATTACK_WINDUP、伤害=实体参数）         ──► #579 反馈
    │        └── tick_frame 命中帧 ──► resolve_attack（弹反→拼刀→格挡→受击，全走常量）
    │                 ├── 弹反成功 ──► 敌人 take_stance_damage(25) + parry_success 事件
    │                 ├── 受击 ──► 玩家 take_damage(ENEMY_HP_DAMAGE) + take_stance_damage(35)
    │                 └── stance ≤ 0 ──► break_stance ──► stance_break 态（3s）──► #580 处决
    ├── 位移意图（move_intent）──► _physics_process ──► move_and_slide（仿 #573 加速度模型）
    └── 决策门控：实体非 idle/move 态 → 不决策；弹反后 ENEMY_PARRY_STUN_SECONDS 抑制
```

### 3.4 需要更新的文档

- [ ] `docs/GAME_DESIGN/shandong-wolf/` — post-merge agent：新增敌人 AI 章节（行为状态机 + 感知参数 + 决策门控）
- [ ] `docs/PROJECT.md` — 若涉及系统清单变更（post-merge agent 处理）

---

## 4. 方案对比

### 4.1 方案 A：EnemyAI 独立行为状态机 + 判定层自动窗口复用（推荐）

**描述：** 新建 `EnemyAI`（CharacterBody2D，仿 #573 PlayerController 移动模型），内部持有第二个 `StateMachineBase` 实例，行为状态对象（Patrol/Chase/Attack/Retreat）按 combat_states.gd 范式派生。AI 决策通过 `entity.request_transition()` 驱动战斗态、通过 `move_intent` 驱动位移；攻击窗口**不手动登记**——复用 #577 自动登记（仅补 windup 字段 + 攻击伤害参数化两处 additive 改动）。感知 = 几何判据（facing 点积 + 距离 + 高度容忍）。

| 维度 | 内容 |
|------|------|
| AI 状态集 | Patrol（waypoint ping-pong + 到达停顿）/ Chase（转向逼近 + 停距）/ Attack（三连砍或突刺 + 冷却）/ Retreat（5% 回避） |
| 与战斗层关系 | 单向依赖：AI → CombatEntity（转移/信号）；战斗结果 → 信号门控 AI（决策门控 + 弹反抑制窗） |
| 攻击接入 | 复用 #577 `_on_entity_state_changed` 自动登记；`AttackWindow.windup_frames` 补敌人前摇；`CombatEntity.attack_hp_damage/attack_stance_damage` 补敌人伤害 |
| 测试性 | `decide(delta)` 纯决策（无物理依赖），headless 手动推进断言；RNG seed 注入 |
| 动画 | 复用 SW-003：move/idle 走既有 clip，攻击/硬直由战斗态驱动，零新动画 |

**Pros：** 与 issue body「使用通用状态机扩展」逐字对齐（StateMachineBase 即通用状态机）；行为层/战斗层职责清晰，判定/动画/反馈全部复用既有契约；headless 可测；数值全走 constants；敌人视觉完全复用 SW-003（零渲染代码）。
**Cons：** 两个 FSM 并存需纪律（AI 不得直接改 entity.state_name，只能 request_transition）；两处 additive 补丁（judge/AttackWindow/CombatEntity）需在实现期保持向后兼容。
**Risk：** Low（补丁均为 additive，现有 25 条判定测试不受影响）。
**Effort：** 2.5-3 天（AI 状态机 1.5 天 + 感知/位移/窗口接入 0.5 天 + 单测 0.5-1 天）。

### 4.2 方案 B：扩展现有 11 态转移表加入 patrol/chase 行为态

**描述：** 在 `CANONICAL_STATES` 增加 patrol/chase 等状态，让战斗状态机直接承载 AI 行为。

**Pros：** 单一状态机，无双 FSM 协调成本。
**Cons：** **违反 #575 状态名权威集红线**——`consume_state`（#574 动画）按 11 态实现，增名即动画失配；AI 行为（waypoint 遍历/感知/冷却）与战斗数据（hp/stance）耦合进同一状态对象，违背「AI 不渲染、复用骨架」的职责分离；所有下游（#576 HUD/#579 反馈）的状态订阅面被污染。
**Risk：** High（架构红线 + 动画契约破坏）。
**Effort：** 1.5 天（看似更省，实则拆弹成本高）。
**结论：** 否——红线否决。

### 4.3 方案 C：引入 Behaviour Tree 开源库

**描述：** 引入 `andrew-wilkes/godot-behaviour-tree`（53⭐，GDScript）等 BT 框架承载敌人决策。

**Pros：** BT 适合复杂决策树/复用节点；社区成熟度（53⭐）尚可。
**Cons：** 开源调研（§6.2）显示无 Godot 4.7 高星 BT 库（次高 11⭐）；BT 与 issue body「使用通用状态机扩展」明示方向冲突；外部依赖引入 + 学习/适配成本；MVP 4 行为态用 BT 属于过度设计（决策树展开后仍等价于 4 态 FSM）。
**Risk：** Medium（依赖维护 + 架构偏离既定 FSM）。
**Effort：** 3-4 天（含库适配与测试基建）。
**结论：** 否——MVP 不需要，且与既定架构/issue body 冲突。

### 4.4 推荐

**方案 A。** 理由：
1. issue body 明示「使用通用状态机扩展，不硬编码逻辑」——StateMachineBase 派生行为状态对象是字面对齐；
2. 两处 additive 补丁（窗口 windup + 攻击伤害参数化）是 #577 契约预留位的自然落地（§8.3「#581 敌AI 与玩家攻击共用」）；
3. 感知/决策/移动三块均可 headless 单测，与项目测试纪律一致；
4. 敌人视觉零成本（复用 SW-003），行为层可独立先行，不阻塞 #583/#585。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（验收清单，映射 issue body）

- [x] **AC1: 巡逻→追击→攻击 状态流转，攻击前摇 12 帧且前摇期间可被弹反**
  - [ ] EnemyAI 初始 Patrol：沿 waypoints ping-pong，到达停顿 ENEMY_PATROL_PAUSE_SEC
  - [ ] 玩家进入感知（范围 ENEMY_SENSE_RANGE_PX + 角度 120° + 高度容忍）→ Chase：转向（entity.facing=sign(dx)）+ 逼近，|dx|≤ENEMY_ATTACK_RANGE 停距
  - [ ] 冷却就绪且停距 → Attack：`request_transition("attack"/"heavy_attack")`；前摇帧 = `ENEMY_ATTACK_WINDUP`（裁决点：AC 要求 12，constants 候选 [12,15,18]，见 §8.4-1）
  - [ ] 前摇期间判定窗口 active → 玩家 guard_pressed 在弹反闭区间内 → parry_success（#577 既有逻辑，零改动）
- [x] **AC2: 被弹反后硬直 0.5s 并增加 25 架势值，连续 4 次弹反可崩解（数值来自 constants.gd）**
  - [ ] 弹反 → `PARRY_STANCE_DAMAGE=25` 经 take_stance_damage 施加（#577 已实现，只读消费）
  - [ ] 4×25=100=POSTURE_BREAK_THRESHOLD → 第 4 次弹反 break_stance → stance_break 态 3.0s（#575 已实现）
  - [ ] 弹反后 AI 决策抑制 `ENEMY_PARRY_STUN_SECONDS=0.5`（AI 层补足 AC 硬直；共享 parry_success 态 0.167s 之上叠加抑制窗，期间不追击不攻击）
- [x] **AC3: AI 有 5% 概率在玩家攻击前摇时后退闪避**
  - [ ] 玩家 state_changed → attack/heavy_attack（前摇开始）且玩家在 ENEMY_RETREAT_TRIGGER_RANGE 内 → 掷骰（seed 可控）5% 进入 Retreat：向远离玩家移动 ENEMY_RETREAT_SECONDS → 回 Chase
  - [ ] 95% 不回避：继续当前行为（不打断攻击决策）
- [x] **AC4: AI 参数全部从 constants.gd 读取**
  - [ ] 感知范围/角度/速度/冷却/伤害/概率/抑制窗全部引用 WolfConstants AI 分区，测试断言「改常量值 → 行为随之变化」
- [x] **AC5: smoke test：玩家站桩时敌人 5s 内完成巡逻→发现→接近→攻击的路径**
  - [ ] headless：玩家站桩于感知范围内（如 400px），敌人 5s 模拟时间内到达 `entity.state_name == "attack"`（或完成一次攻击窗口登记）

### 5.2 边界情况（Edge Cases）

1. **玩家在敌人身后**：facing 反向 → 视线锥外不发现；Chase 中玩家绕后 → 敌人转向后重新判定（转向延迟 ENEMY_TURN_DELAY_SEC 候选 [0.1,0.2,0.3]，防瞬移转身穿帮）
2. **玩家超出追击范围**：Chase 中丢失（距离 > ENEMY_LOSE_SIGHT_RANGE = SENSE_RANGE × 1.5 候选）→ 回 Patrol（从最近 waypoint 继续，不瞬移）
3. **玩家处于不可命中态**：dead/revive/execute/无敌期 → judge 守卫已 no-op（#577）；AI 照常 Chase 但不触发命中
4. **敌人被连续弹反至 stance_break**：stance_break 态 3.0s 内 AI 不决策（战斗 FSM 接管失衡动画）；恢复 idle 后 AI 回 Chase；期间 #580 处决接管则 AI 禁用
5. **敌人受击 stagger（玩家刀命中）**：stagger 态 12 帧 AI 不决策；恢复后继续（受击双重惩罚 = hp+stance 由 #577 施加）
6. **敌人死亡**：life_total=1 → die() → dead 终态（_is_final_dead）→ AI 完全禁用（不再感知/移动/决策）
7. **三连砍连段中断**：连段第 2/3 刀前玩家弹反 → parry_success → 连段计划作废（AI 抑制窗接管）
8. **巡逻路径只有一个 waypoint**：ping-pong 降级为原地等待（不报错）
9. **敌人与玩家同平台判定**：高度差 > 容忍 → 不发现/不追击（MVP 平台制简化，不引入 raycast）
10. **5% 回避期间玩家后撤**：Retreat 期满后目标距离 > 攻击范围 → 回 Chase 而非 Attack

### 5.3 失败路径（Failure Paths）

1. **感知数值非法**（范围 ≤0 / 角度 >180）：push_warning + 回退默认值（不崩溃，仿 StickFigure 参数校验范式）
2. **waypoints 未配置**（@export 空数组）：Patrol 降级为原地 idle 等待（不报错），Chase 仍可被感知触发
3. **判定器未绑定**（judge 引用为 null）：EnemyAI 正常移动/感知/转移，攻击窗口不登记（push_warning 一次）——headless 单测允许无 judge 跑行为路径，窗口断言单独绑定 judge 用例

---

## 6. 依赖与阻塞

### 6.1 依赖关系

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #575 CombatEntity + 11 态状态机（#618 merged） | ✅ | 无 |
| #577 CombatJudge + AttackWindow（#626 merged） | ✅ | 无 |
| #584 数值 DRAFT（#609 merged，human-review 中） | ✅ | 低（AI 新常量 # DRAFT 只读，不与 #584 冲突） |
| #579 打击反馈 | ⛔ 未开始 | 低（消费 hit_landed/parry_success 事件，事件契约已定，不阻塞） |
| #580 处决 | ⛔ 未开始 | 低（消费 stance_broken，本层不依赖其实现） |
| #583 场景 / #585 组装 | ⛔ 未开始 | 中（EnemyAI 场景化组合依赖 #585；本层 headless 独立可测，不阻塞） |

```
#572 ──► #573 ──► #575 ──► #577 ──► #581（本 issue：敌AI）──► #585 组装 ──► #586 E2E
#572 ──► #584 ──┘        │                              ├──► #579 反馈（事件消费）
                         └──► #578 复活 / #580 处决       └──► #583 场景（出生点/路径坐标）
```

### 6.2 开源调研（issue body 要求「开源优先，成熟方案优先复用，找不到再自行实现，并在 PR 中说明调研结果」）

| 类别 | 候选 | 调研结论 |
|------|------|---------|
| Godot enemy AI（GDScript，2026-08-20 GitHub API 检索） | Snaiel/Godot4ThirdPersonCombatPrototype（234⭐） | 3D 第三人称战斗原型（移动/镜头/敌人行为）——3D 视角与横板 2D + 逻辑帧判定架构不符；无 120° 视线/弹反联动语义。**不采用** |
| Godot enemy AI | metanoia83/Godot-4.0-Basic-Character-Controller-and-Enemy-AI（18⭐）/ XdrenalYT/Enemy-AI-Godot-4（4⭐） | 基础状态机敌人（3D 第三人称教学 demo）——思路（行为 FSM）与方案 A 一致，但均为 3D 教学 demo 非可复用库，且不接本项目判定层契约。**思路借鉴，实现自研** |
| Godot 2D enemy AI | Cod-e-Codes/godot-adventure-rpg（7⭐）/ SarutobiSasuke8/BrotatoLike（5⭐） | 2D 项目但为完整游戏原型非 AI 库；BrotatoLike 为俯视角 survivor。**不采用** |
| Behaviour Tree 库 | andrew-wilkes/godot-behaviour-tree（53⭐）/ JassJam/Godot-BehaviourTree（11⭐）/ ratkingsminion/bt.gd（5⭐） | 最高 53⭐ 且非 Godot 4.7 官方生态；BT 与 issue body「使用通用状态机扩展」方向冲突；MVP 4 行为态过度设计（§4.3）。**不采用** |

**结论：** 无成熟可复用的「Godot 2D 横板类只狼敌人 AI」开源库；现有候选要么 3D 视角不符、要么教学 demo 非库、要么 BT 架构冲突。**自研 EnemyAI 行为状态机**（方案 A，issue body 允许「找不到再自行实现」）。implement PR 须引用本调研结论。

### 6.3 前置准备

- [ ] implement 前确认 origin/main 已含 #618（#575 实现）、#626（#577 实现）、#609/#611/#612（侦查基准 f85bbd7 已含）
- [ ] 本 PRD merge 后，plan agent 读 §8 交接上下文即可开工，无需重扫源码

---

## 7. Spike / 实验（depth/standard 可选，本 PRD 含 3 实验提升交接质量）

### 实验 1：120° 视线锥几何判据精度

- **要回答的问题**：facing 点积 + 水平距离 + 高度容忍的组合判据，在边界（恰好 60° 夹角 / 恰好 6m / 高度差恰在容忍值）上是否稳定？玩家在身后（角度 >90°）是否必然不发现？
- **方法**：headless 构造玩家-敌人相对位置矩阵（8 个方位角 × 3 距离 × 3 高度差），断言 `EnemyAI.can_sense_player()` 结果与几何期望一致
- **预期结果**：闭区间边界含端点判定正确；身后/超距/超高差全部 false；判定结果仅依赖 facing/距离/高度三输入（可复现）
- **对方案的影响**：若点积边界有浮点抖动，感知判定统一走「> 阈值则 false」单向容差；若高度容忍语义与 #583 平台制冲突（玩家在另一平台），容忍值降级或改平台 ID 判定

### 实验 2：5% 后退回避的可测性与频率统计

- **要回答的问题**：seed 注入的 RNG 在 1000 次玩家攻击事件模拟中，回避触发频率是否收敛于 0.05 ± 0.02？固定 seed 是否完全可复现（CI 稳定性）？
- **方法**：EnemyAI 暴露 `set_rng_seed(seed)`；模拟 1000 次「玩家 attack 前摇开始」事件，统计 Retreat 触发次数；同一 seed 重跑断言序列一致
- **预期结果**：频率 ∈ [0.03, 0.07]；同 seed 全等；无 seed 时用全局 RandomNumberGenerator 兜底
- **对方案的影响**：若频率统计波动超容忍（RNG 质量问题），改 `randf() < ENEMY_RETREAT_CHANCE` 为逐事件独立采样（无状态）即可；若 CI 需要确定性，测试一律注入 seed

### 实验 3：攻击窗口 windup 参数化后的弹反时序对齐

- **要回答的问题**：敌人前摇 12 帧（AC1）时，judge 自动登记窗口的 `hit_frame = start_frame + 12`、`hit_ms = hit_frame × 1000/60`，玩家 guard_pressed 在 `[hit_ms - 200ms, hit_ms]` 闭区间内弹反成功——与 #577 现有 8 帧玩家窗口的测试夹具是否共存？现有 test_combat_judge.gd 25 用例是否全绿（additive 无回归）？
- **方法**：跑现有 test_combat_judge.gd（回归基线）→ 构造敌人实体（attack_hp_damage=15、windup=12）+ AI 触发 attack → 断言窗口 windup=12、hit 帧正确、弹反闭区间判定成功/失败边界
- **预期结果**：现有 25 用例全绿；敌人窗口 hit 帧 = start+12；弹反闭区间语义与玩家一致（PARRY_WINDOW_SECONDS=0.2）
- **对方案的影响**：若 AttackWindow.windup_frames 默认值处理破坏现有窗口（-1 回退逻辑 bug），恢复默认 8 帧路径并单独修字段初始化；若敌人 12 帧前摇导致弹反「太容易」（窗口绝对时间变长），候选集下调 PARRY_WINDOW_FRAMES 或记录 #584 裁决

---

## 8. 交接上下文（plan agent 交接）

### 8.1 系统现状快照

- origin/main @ f85bbd7（#618/#626/#631 已 merge）：CombatEntity（is_player/life_total/stance_max 变体参数 + request_transition 唯一转移入口 + 6 信号）、CombatStateTable（11 态权威集）、CombatStates（状态对象范式 + restart 连段钩子）、CombatJudge（任意实体 attack 态自动登记窗口 + 弹反→拼刀→格挡→受击裁决 + 五结果事件）、AttackWindow（hit_frame = start + FRAME_ATTACK_WINDUP）、WolfConstants 全量 # DRAFT（含 ENEMY_ATTACK_WINDUP=15 / PARRY_STANCE_DAMAGE=25 / POSTURE_HIT_COST=35 / HITBOX_RANGE=80）、PlayerController（CharacterBody2D 加速度移动）、StickFigureController.consume_state（11 态动画）
- AI 层（本 issue）**零存在**：无 EnemyAI、无行为状态对象、无感知、无敌人移动实体

### 8.2 交付物清单（按实现顺序）

| 顺序 | 文件 | 内容 |
|:----:|------|------|
| 1 | `constants.gd`（修改） | AI 分区 # DRAFT 常量：ENEMY_SENSE_RANGE_PX（候选 [400,500,600]，默认 600=6m@100px/m，issue 指定）/ ENEMY_SENSE_ANGLE_DEG（120，issue 指定）/ ENEMY_SENSE_HEIGHT_TOLERANCE（候选 [100,150,200]）/ ENEMY_PATROL_SPEED（候选 [60,80,100]）/ ENEMY_CHASE_SPEED（候选 [150,180,220]）/ ENEMY_TURN_DELAY_SEC（候选 [0.1,0.2,0.3]）/ ENEMY_ATTACK_RANGE（候选 [70,80,100]，默认 80=HITBOX_RANGE 对齐）/ ENEMY_ATTACK_COOLDOWN_SEC（候选 [1.2,1.5,2.0]）/ ENEMY_HP_DAMAGE（候选 [10,15,20]，默认 15）/ ENEMY_THRUST_CHANCE（候选 [0.2,0.3,0.5]，默认 0.3）/ ENEMY_RETREAT_CHANCE（0.05，issue 指定）/ ENEMY_RETREAT_SECONDS（候选 [0.3,0.5,0.8]）/ ENEMY_RETREAT_TRIGGER_RANGE（候选 [150,200,250]）/ ENEMY_PARRY_STUN_SECONDS（候选 [0.4,0.5,0.6]，默认 0.5=AC2）/ ENEMY_LOSE_SIGHT_RANGE（=SENSE×1.5 派生）/ ENEMY_PATROL_PAUSE_SEC（候选 [0.5,1.0,1.5]）/ ENEMY_HP_MAX（候选 [30,40,50]，默认 40=sekiro 敌小兵 HP 30-50）——全部「基准 → 候选 + 影响 + 情感断言」注释 |
| 2 | `combat_attack_window.gd`（修改，additive） | 追加 `windup_frames: int = -1`（-1 → 回退 FRAME_ATTACK_WINDUP）；hit_frame() 优先用 windup_frames |
| 3 | `combat_entity.gd`（修改，additive） | 追加 `@export var attack_hp_damage: float = -1.0` / `@export var attack_stance_damage: float = -1.0`（-1 = 玩家常量兜底） |
| 4 | `combat_judge.gd`（修改，additive） | `_on_entity_state_changed`：hp_damage/stance_damage 读实体参数（≥0 用实体值，否则玩家常量）；windup_frames 敌人读 ENEMY_ATTACK_WINDUP |
| 5 | `enemy_ai.gd`（新增） | EnemyAI（CharacterBody2D）：AI FSM 持有 + `can_sense_player()` 感知 + `decide(delta)` 纯决策（headless 可驱动）+ `_physics_process` 位移 + @export（waypoints/player/judge/rng_seed）+ 决策门控（实体非 idle/move 不决策、弹反抑制窗） |
| 6 | `enemy_ai_states.gd`（新增） | PatrolState / ChaseState / AttackState（三连砍=attack 连段 restart 钩子、突刺=heavy_attack）/ RetreatState |
| 7 | `test_enemy_ai.gd`（新增） | §5.1 AC1-AC5 用例 + §5.2/§5.3 边界失败路径 + §7 实验 1/2/3 落地 |
| 8 | `run_tests.gd`（修改） | 注册 test_enemy_ai.gd |
| 9 | `smoke_test.gd`（修改，可选） | AC5 冒烟 |

### 8.3 接口契约（下游系统的消费面）

```gdscript
## EnemyAI（class_name，extends CharacterBody2D）——敌人行为层唯一入口
@export var waypoints: Array[Vector2] = []    # 巡逻路径（#583 场景配置；空数组=原地等待）
@export var player: Node2D                    # 玩家移动实体引用（感知/追击目标）
@export var judge: Object                     # CombatJudge 引用（null = 不登记窗口，仅行为路径）
@export var rng_seed: int = -1                # -1 = 全局 RNG；≥0 = 确定性（测试注入）

func bind_entity(entity: CombatEntity) -> void      # 绑定敌人战斗实体（#585 组装时调用）
func can_sense_player() -> bool                     # 120° 视线 6m 几何判据（facing 点积+距离+高度容忍）
func decide(delta: float) -> void                   # 纯决策：推进 AI FSM → 设置 move_intent / request_transition（headless 测试手动调用）
func move_intent() -> Vector2                       # 当前位移意图（_physics_process 消费）

## 敌人攻击伤害（CombatEntity additive 参数，judge 读取）
@export var attack_hp_damage: float = -1.0          # 敌人命中 HP 伤害（EnemyAI._ready 设 ENEMY_HP_DAMAGE；-1=玩家常量兜底）
@export var attack_stance_damage: float = -1.0      # 敌人命中架势伤害（EnemyAI._ready 设 POSTURE_HIT_COST；-1=玩家常量兜底）

## AttackWindow（additive 字段，兼容既有玩家窗口）
var windup_frames: int = -1                          # -1 → 回退 FRAME_ATTACK_WINDUP；敌人 = ENEMY_ATTACK_WINDUP
```

**组合约定（#585 组装时遵循）：** 敌人场景根 = EnemyAI（CharacterBody2D），子节点 = CombatEntity（is_player=false, life_total=1, life_1_max=ENEMY_HP_MAX, stance_max=POSTURE_BREAK_THRESHOLD，本地坐标 (0,0)，攻击伤害参数由 EnemyAI._ready 注入）+ StickFigureController（复用 SW-003 骨架，零新渲染）。

### 8.4 主要风险与裁决点

1. **ENEMY_ATTACK_WINDUP 12 vs 15（AC1 vs constants 默认）**：issue AC1 硬约束「攻击前摇 12 帧」；constants 当前默认 15（候选 [12,15,18]，#584 已 merge）。本 PRD 立场：**实现期取 12 对齐 AC**（读常量 ENEMY_ATTACK_WINDUP，值改 12 并保留候选注释），偏差记录给 #584 定稿——数值归属 #584 裁决，本层只保证「读常量不硬编码」。
2. **0.5s 弹反硬直的实现位置**：共享 parry_success 态仅 0.167s（PARRY_SUCCESS_FRAMES=10），AC2 的 0.5s 由 **AI 层抑制窗**（ENEMY_PARRY_STUN_SECONDS）补足，不修改共享战斗态（避免影响玩家弹反手感）。若用户裁决「0.5s 应体现在战斗态」，改 PARRY_SUCCESS_FRAMES 候选 + 冲突矩阵（#584 域）。
3. **三连砍连段的判定窗口覆盖**：judge 自动登记对同 attacker 旧窗口覆盖（连段语义已支持）；连段第 2/3 刀窗口 start_frame 顺延，弹反窗口随之顺延——若实机感觉连段弹反「过于容易/困难」，调 ENEMY_ATTACK_COOLDOWN_SEC/连段间隔（#584 域）。
4. **敌人攻击伤害默认值**：ENEMY_HP_DAMAGE=15（候选 [10,15,20]）——sekiro 敌小兵对玩家伤害基准，玩家两条命下 15/次 ≈ 7 刀击杀（100/15），与「压迫感但可失误」MVP 目标一致；用户实机裁决归 #584。
5. **#585 组装前 EnemyAI 的可用性**：headless 单测 + smoke 路径全部免场景树（decide 手动驱动）；场景化组装（出生点/waypoint/玩家引用注入）依赖 #583/#585——若 #585 延期，本层交付的类与测试不受影响。
6. **GDD 落盘**：post-merge agent 新增 `docs/GAME_DESIGN/shandong-wolf/08-ENEMY-AI.md`（行为状态机 + 感知参数 + 决策门控 + 组合约定）。

### 8.5 红线（implement agent 禁止）

- ❌ 不改 11 态 `CANONICAL_STATES` / `consume_state` 契约（#575 状态名权威集；patrol/chase 是 AI 行为态，不进战斗状态表）
- ❌ 不引入 Area2D/CollisionShape2D 物理碰撞（#577 逻辑帧窗口架构；攻击命中复用 judge 自动登记）
- ❌ 不裁决 # DRAFT 数值（只读 constants；AI 新常量也标 # DRAFT 候选集）
- ❌ 不改 #577 五结果事件名与裁决顺序（parry_success/block_held/hit_landed/clash/stance_broken 契约）
- ❌ 不修改既有接口签名（judge/entity/AttackWindow 全部 additive 扩展，现有 test_combat_judge.gd 25 用例必须全绿）
- ❌ 不写死 AI 数值字面量（感知/速度/冷却/伤害/概率/抑制窗全走 constants）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不修改 scenes/Main.tscn（标题场景红线）
- ❌ 不做场景组装与渲染（#583/#585 职责）；敌人视觉复用 SW-003，AI 层零渲染代码

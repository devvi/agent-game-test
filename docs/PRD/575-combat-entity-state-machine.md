# PRD #575 — [Feature] 战斗实体基类与状态机（CombatEntity + 11 态战斗状态机）

> **Issue:** #575
> **标签:** enhancement, gameplay, workflow/research, version/mvp（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=4）
> **深度:** deep（分解 JSON id=4 标注 `depth: deep` → §1–8 全必填，§7 含 ≥3 实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: mechanical`（数据/状态容器=机械工程；手感数值定稿归 #584，本 issue 只读 constants # DRAFT 不裁决）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian/Knowledge Ocean/`：wiki grep 只狼 → `wiki/游戏设计理念.md`（只狼为灵感来源）；raw grep 弹反/格挡/架势 → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（「弹反/闪避 = 时机判定」动作进阶层 + 分层设计）、`raw/Bear/state machine.md`（叙事状态机记录范式））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：架势上限=当前 HP 上限铁律、两条命、受击双重惩罚）+ 同链 issues（#573 输入 / #574 动画 / #576 HUD / #577 判定 / #578 复活 / #580 处决 / #581 敌AI）+ 开源调研（GitHub API 检索 FSM/combat/parry/sekiro/respawn，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=4，estimate 3d，priority high）
> **前置依赖:** #572（merged #599：constants.gd + state_machine.gd + Game autoload）、#573（merged #611：InputController 意图事件 + PlayerController）、#574（merged #612：StickFigureController.consume_state 契约）、#584（merged #609：战斗数值 DRAFT 集中表）——全部已满足

---

## 1. 问题定义

### 1.1 现状（2026-08-19 worktree 侦查 @ origin/main e70dcb2）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ 已交付（#572/#599） | `StateMachineBase`（RefCounted）：状态对象 enter/exit/update 三接口 + transition_to()（同态守卫 + 防重入锁）；注释明言「#575 战斗实体状态机在其上定义具体状态」——**派生点已预留** |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#584/#609） | `WolfConstants` 全量 # DRAFT：两条命（LIFE_TOTAL=2 / LIFE_1_MAX=100 / LIFE_2_ABS=50）、架势（POSTURE_BREAK_THRESHOLD=100 / POSTURE_RECOVERY_PER_SEC=25 / POSTURE_RECOVERY_DELAY=1.5 / POSTURE_BLOCK_COST=10）、刀伤害（LIGHT=12 / HEAVY=30 / EXECUTE=999）、帧节奏（FRAME_ATTACK_WINDUP=8 / FRAME_ATTACK_RECOVERY=14 / FRAME_ANIM_EXECUTE_TOTAL=5）——**本层只读消费** |
| `shandong-wolf/gdscripts/game.gd` | ✅ 已交付（#572/#599） | `Game` autoload 锚点，注释明言「后续系统（输入/战斗/音频）挂接于此」——战斗系统挂载点已预留 |
| `shandong-wolf/gdscripts/input_controller.gd` | ✅ 已交付（#573/#611） | 意图事件信号：attack_pressed / heavy_attack_pressed / guard_pressed(timestamp_ms) / guard_held / dash_pressed / jump_pressed / interact_pressed / revive_pressed + 输入缓冲队列（poll_buffer/peek_buffer）——**状态转移的输入源** |
| `shandong-wolf/gdscripts/player_controller.gd` | ✅ 已交付（#573/#611） | 移动实体（_physics_process 加速度移动）——与战斗层的关系见 §1.4 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | ✅ 已交付（#574/#612） | `consume_state(state)` 唯一动画入口（不读 Input、不订阅 #573 信号）；`_resolve_canonical(state)` 状态名归一——**11 态 canonical 名已在本层被消费，本 issue 必须产出同名状态** |
| `shandong-wolf/gdscripts/stick_figure_anim_states.gd` | ✅ 已交付（#574/#612） | 基于 StateMachineBase 派生的动画状态对象（ANIM_CLIP_NAMES 映射）——可作状态对象写法范本 |
| `shandong-wolf/gdscripts/` | ❌ 无战斗层 | 无 hp/stance 数据容器、无战斗状态对象、无转移合法性检查、无玩家/敌人变体配置——**本 issue 全部新建** |
| `shandong-wolf/scenes/Main.tscn` | ✅ 标题场景（#562/#563/#570） | 纯声明式标题；本 issue 不修改它（红线）；战斗实体实例化归 #583/#585 |
| `shandong-wolf/tests/` | ✅ 三入口（#572） | run_tests.gd 已挂 state_machine/constants/debug_canvas 单测；本 issue 追加 test_combat_entity.gd |

**核心缺口：** shandong-wolf 已有地基（StateMachineBase 派生点 + constants 全量 DRAFT 数值 + consume_state 动画契约 + 输入意图事件），但**战斗数据层与状态机层零存在**——没有 hp（两段式）/stance/facing 的数据容器，没有 11 个 canonical 战斗状态对象，没有「状态切换必须经合法性检查」的执行层。所有下游战斗系统（#576 HUD、#577 判定、#578 复活、#580 处决、#581 敌AI）都依赖本层先落地。

### 1.2 验收条件（源自 Issue #575 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | CombatEntity 可实例化玩家与敌人两种变体，hp/stance 属性正确读写 | §4.2 方案 A（单类 + @export 参数配置）+ §5.1 AC1：life_total/hp_1/hp_2/stance/facing 全可读写，两个变体同一类 |
| AC2 | 状态机可驱动状态流转，且状态切换必须经合法性检查（如 stance_break 时不可攻击） | §4.1 方案 A（StateMachineBase 派生 + 集中转移表）+ §5.1 AC2：`request_transition()` 查表，非法转移 reject + warning，状态不漂移 |
| AC3 | take_stance_damage 在 stance≤0 时触发 break_stance() 并广播信号 | §4.3 + §5.1 AC3：stance 归零 → `break_stance()` → `stance_broken` 信号（幂等，单次触发） |
| AC4 | 两段血：第一条血归零进入 dead 状态（由 SW-007 接管复活），第二条半管血独立计数 | §4.3 + §5.1 AC4：hp_1 独立、hp_2 独立计数（LIFE_2_ABS=50）；hp_1≤0 → die() → dead 状态 + died(final=false)；`revive()`（#578 驱动）→ revive→idle，hp_2 接管 |
| AC5 | 单元测试覆盖：受击/架势/死亡 3 条主路径 | §5.1 AC5 + §8：test_combat_entity.gd 三组用例（受击掉血+stagger、架势归零崩解、两段死亡+复活流） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机操作（MVP 战斗闭环前置） | 每次游玩 | 玩家控制火柴人：idle 待机 → move 移动 → attack/heavy_attack 挥砍 → guard 格挡 → 受击 stagger 硬直 → 架势崩解 stance_break 失衡 → 被处决/处决敌人 → 第一条命耗尽倒地（dead）→ 原地复活（revive）再战；全部状态由本层数据与状态机承载 |
| B | 下游战斗系统消费（#576/#577/#578/#580/#581） | 每次 impl PR | HUD 读 hp/stance 信号画两段血条+架势条；判定系统调 take_damage/take_stance_damage 并消费 stance_broken/parry_success；复活系统调 revive()；处决系统驱动 execute；敌AI 用 enemy 变体 |
| C | 开发者 headless 验证 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`：直接 new 两个变体断言数据读写/转移合法性/两段死亡流——不依赖场景树 |

### 1.4 范围边界（Patch 14 去冲突 + 状态契约红线）

| PRD / 分解 id | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #572（scaffold，merged） | StateMachineBase 通用地基 | ❌ 不重写状态机基类；只在其上派生 11 个战斗状态对象 + 转移表 |
| #573（输入，merged） | Input Map + InputController 意图事件 + 输入缓冲 + PlayerController 位移 | ❌ 不重复输入层；只新增「输入信号 → 战斗状态转移」的桥接消费（攻击/格挡进入战斗状态；垫步/跳留在移动层，不进 canonical 状态集） |
| #574（动画，merged） | consume_state(state) 动画消费契约 + 11 态关键帧 | ❌ 不消费动画；本 issue 是**状态名唯一权威来源**——产出与 consume_state 同名 canonical 状态，动画层只读状态名 |
| 分解 id 6 / #577（判定） | 弹反窗口/拼刀/架势伤害判定，消费 guard_pressed 时间戳 | ❌ 不做判定逻辑；本 issue 只提供 take_damage/take_stance_damage 接口与 parry_success/stagger/stance_break 状态，判定归 #577 |
| 分解 id 7 / #578（复活） | 1s 倒地→原地复活→半管第二条血→无敌 1s→架势清空 | ❌ 不做复活动画/时序演出；本 issue 提供 dead 状态 + revive() 接口与 revive 状态，驱动归 #578 |
| 分解 id 9 / #580（处决） | 处决触发/无敌/敌人淡出 | ❌ 不做处决演出；本 issue 提供 stance_break→execute 转移通道，驱动归 #580 |
| 分解 id 5 / #581（敌AI） | 巡逻/追击/攻击 AI 状态（通用状态机扩展） | ❌ 不做 AI；本 issue 提供 enemy 变体 CombatEntity（hp/stance 参数化），AI 状态在 #581 叠加 |
| #584（数值 DRAFT，merged） | 手感数值候补值与调参面板 | ❌ 不裁决数值；constants # DRAFT 只读；本层新增的时序常量（见 §4.3）同样标 # DRAFT 待定稿 |
| #585（组装） | 玩家=PlayerController+CombatEntity+StickFigureController 组装 | ❌ 不做场景组装；本 issue 交付可独立实例化/单测的类，实例化进场景归 #583/#585 |

**状态契约红线（issue body 2026-08-19 三方对齐）：** 状态名固定为 idle/move/attack/heavy_attack/guard/parry_success/stagger/stance_break/execute/revive/dead。禁止自造状态名（如 parry 单列、run 代替 move）。#574 consume_state 已按此集合实现，本层产出必须逐名对齐。

---

## 2. 设计意图

### 2.1 为什么现在做

1. **状态契约已三方对齐（2026-08-19）**：输入层（#573 已 merged）、动画层（#574 已 merged）都已按 11 态 canonical 集合交付，本 issue 是契约的**唯一权威来源**——所有下游（#576/#577/#578/#580/#581）都在等本层定义状态语义。
2. **地基全部就绪**：StateMachineBase（派生点）、constants 全量 DRAFT 数值（两条命/架势/帧节奏）、consume_state 契约——本层是「数据 + 状态」的收口层，无前置阻塞。
3. **只狼机制对齐（sekiro-tuning-reference）**：血条与架势分离是拼刀循环的地基；「架势上限 = 当前 HP 上限」「受击双重惩罚」「两条命」三条铁律决定本层数据模型——hp 与 stance 必须独立但联动。

### 2.2 为什么是本层（历史成因）

| 约束 | 来源 | 详情 |
|------|------|------|
| StateMachineBase 通用化 | #572 PRD 决策 | 地基只提供三接口契约与守卫，**不设计任何具体状态**——具体状态是 #575 的职责 |
| 状态名契约 | #573/#574 交付契约 | 动画层 consume_state 已按 canonical 集合实现，若本层改名/增名 → #574 动画失配 |
| 数值 # DRAFT | #584 交付 | 手感数值全部候补待定稿，本层**只读**，新增时序常量也标 # DRAFT |
| 判定/演出分层 | issue body 明确 | hit-stop 归 SW-008（#579）、判定归 #577、复活演出归 #578、处决演出归 #580——本层只做**状态与数据** |

### 2.3 本层设计意图

- **数据即状态，状态即契约**：CombatEntity 是 hp/stance/facing 的唯一数据容器（HUD/判定/动画都从这里读）；状态机是 canonical 状态名的唯一产出者（动画从这里消费）。
- **合法性检查是硬约束**：转移表集中定义，`request_transition()` 是唯一转移入口——杜绝「任何代码都能直接改状态」的漂移风险（AC2 核心）。
- **变体参数化**：玩家与敌人共用同一类，差异 = @export 参数（life_total、血量、架势上限）——issue body 明示「差异通过参数配置」。
- **两段血 = 两条独立计数**：hp_1（满管 100）与 hp_2（半管 50）独立存储独立扣减；hp_1 归零 → dead（可复活），hp_2 归零 → 终态死亡（失败事件）。
- **只狼铁律落地**：架势上限默认 = POSTURE_BREAK_THRESHOLD（100，# DRAFT）；受击硬直（stagger）、格挡姿态（guard）是状态层提供的**反应位**，具体数值判定归 #577。

---

## 3. 影响分析

### 3.1 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/combat_entity.gd` | **新增** | CombatEntity 基类（Node2D）：hp 两段/stance/facing 数据 + take_damage/take_stance_damage/break_stance/die/revive 接口 + request_transition 转移入口 + 信号广播 |
| `shandong-wolf/gdscripts/combat_state_table.gd` | **新增** | 11 态转移合法性表（数据驱动 Dictionary）+ `is_legal(from, to)` 查询 API |
| `shandong-wolf/gdscripts/combat_states.gd` | **新增** | CombatStateBase + 11 个状态对象（enter/exit/update，时序由 constants 帧常量驱动） |
| `shandong-wolf/gdscripts/constants.gd` | 修改 | 追加本层时序 # DRAFT 常量（STAGGER_FRAMES / PARRY_SUCCESS_FRAMES / STANCE_BREAK_RECOVERY_SEC / REVIVE_SECONDS / INVINCIBLE_SECONDS，候补值+影响+情感断言注释，定稿归 #584） |
| `shandong-wolf/tests/test_combat_entity.gd` | **新增** | 受击/架势/死亡 3 条主路径 + 转移合法性 + 变体参数化单测 |
| `shandong-wolf/tests/run_tests.gd` | 修改 | 注册 test_combat_entity.gd |
| `shandong-wolf/tests/smoke_test.gd` | 修改（可选） | 实体实例化冒烟（headless new 两个变体 + 读属性） |

### 3.2 间接受影响的模块（下游消费者，本次不改）

| 文件/系统 | 影响 | 消费方式 |
|-----------|------|---------|
| #576 HUD（未建） | hp_changed / stance_changed / state_changed 信号 → 两段血条+架势条 | 信号订阅 |
| #577 判定（未建） | take_damage / take_stance_damage 调用方；stance_broken 消费方；parry_success 状态驱动方 | 接口调用 + 信号 |
| #578 复活（未建） | dead 状态 + revive() 驱动方；revive 状态时序 | 接口调用 |
| #580 处决（未建） | stance_break 状态 + execute 转移驱动方 | 接口调用 + 信号 |
| #581 敌AI（未建） | enemy 变体（life_total=1 等参数） | 实例化参数 |
| #574 动画（已建） | consume_state(state) 消费本层 state_name | 状态名只读 |
| #585 组装（未建） | PlayerController + CombatEntity + StickFigureController 组装 | 实例化 + 信号桥接 |

### 3.3 数据流图

```
#573 InputController（意图事件）
    │  attack_pressed / heavy_attack_pressed / guard_pressed / guard_held
    ▼
CombatEntity._StateInputBridge（订阅信号）
    │  request_transition("attack"|"heavy_attack"|"guard")
    ▼
combat_state_table.is_legal(from, to) ──非法──► reject + push_warning（状态不漂移）
    │ 合法
    ▼
StateMachineBase.transition_to(state_obj)（同态守卫 + 防重入锁）
    │
    ├──► state_changed(from, to) ──► #574 consume_state(state) 播动画
    │                              └──► #576 HUD 状态提示（未来）
    ▼
CombatState（11 态对象，帧时序驱动）
    │
#577 判定：take_damage(amount, source) ──► hp 扣减 ──hp_1≤0──► die() ──► dead 状态 + died(final=false)
#577 判定：take_stance_damage(amount) ──► stance 扣减 ──stance≤0──► break_stance() ──► stance_break + stance_broken 信号 ──► #580 处决
#578 复活：revive() ──► dead→revive（1s，无敌）→idle，hp_2=50 接管，架势清空
    │
    └──► hp_changed / stance_changed ──► #576 HUD 血条/架势条
```

### 3.4 需更新的文档

- [ ] `docs/GAME_DESIGN/shandong-wolf/` 新增战斗实体章节（post-merge agent 落盘，编号 06-COMBAT-ENTITY）
- [ ] `docs/GAME_DESIGN/shandong-wolf/03-STATE-MACHINE.md` 集成点表格补 #575 行
- [ ] `docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md` 补充本层新增时序常量（若有）
- [ ] `PROJECT.md` 战斗系统进度更新

---

## 4. 方案对比

### 4.1 状态机架构（核心决策）

**方案 A：StateMachineBase 派生 + 集中转移合法性表（推荐）**

状态对象基于 #572 `StateMachineBase` 派生（11 个 RefCounted 状态对象，enter/exit/update），合法性检查独立为数据驱动转移表 `combat_state_table.gd`，实体只暴露 `request_transition(to)` 唯一入口。

| 维度 | 内容 |
|------|------|
| 状态对象 | `CombatStateBase`（RefCounted，含 name + entity 引用 + enter/exit/update），11 态逐名对齐 canonical 集合 |
| 合法性 | `combat_state_table.gd`：`TRANSITIONS: Dictionary`（from → [to...]）+ `is_legal(from, to)`；表外转移一律 reject |
| 时序 | 定时状态（attack/stagger/parry_success/stance_break/revive/execute）用 constants 帧常量驱动自动退出 |
| 测试 | headless 直接 `CombatEntity.new()` 实例化，不依赖场景树 |

Pros：完全契合 #572 地基（派生点注释明言）；转移表可枚举可单测（AC2 的「合法性检查」可断言）；状态名集中定义杜绝漂移；与 #574 状态对象写法同构（范本现成）。
Cons：11 个状态对象样板代码较多（~250 行）；转移表需人工维护（但有单测兜底）。
Risk：**Low**。Effort：2-3 天。

**方案 B：单文件 enum + match 状态机（mini-pong 模式）**

在 combat_entity.gd 内用 `enum State { IDLE, MOVE, ... }` + `match` 硬编码转移。

Pros：单文件直观、行数少。
Cons：与 #572 通用 StateMachineBase 地基重复造轮子（#572 明确为 #575 派生预留）；enum 名与 canonical 字符串契约需双维护（#574 consume_state 消费的是字符串状态名，enum→String 映射层易漂移）；转移逻辑散落在 match 分支，合法性检查难枚举断言；扩展 enemy AI 状态（#581）需侵入本文件。
Risk：**Med**（状态契约漂移是红线级风险）。Effort：1-2 天。

**方案 C：第三方 FSM addon（LimboAI 等）**

引入 LimboAI（2962⭐）等成熟 FSM 插件承载战斗状态。

Pros：生态成熟、可视化调试。
Cons：已被 #572 PRD 明确否决（「40 行自研满足，不引入第三方 addon」——GDD 03 §2）；addon 状态对象与 canonical 字符串契约对齐成本高；headless 单测引入外部依赖；与 #574 已交付的 StateMachineBase 派生写法不一致。
Risk：**High**（违反 #572 既定架构决策）。Effort：2-4 天（含迁移）。

**推荐：方案 A**。理由：① 地基注释明言派生点，A 是唯一「不重复造轮子」的选项（issue body 开源优先要求下，§6.2 调研证明没有比 StateMachineBase 更优的成熟方案）；② AC2 的合法性检查需要可枚举、可断言的执行层，只有 A 提供；③ 与 #574 动画状态对象写法同构，implement agent 有现成范本。

### 4.2 玩家/敌人变体（issue body 明示「差异通过参数配置」）

| 方案 | 描述 | 裁决 |
|------|------|:----:|
| **A（推荐）** | 单类 `CombatEntity` + `@export` 参数：`is_player`、`life_total`（玩家 2 / 小兵 1）、`life_1_max`、`life_2_abs`、`stance_max`。玩家=new(is_player=true, life_total=2)；敌人=new(is_player=false, life_total=1) | ✅ 与 issue body「差异通过参数配置」逐字一致；AC1「可实例化两种变体」直接可测 |
| B | `PlayerEntity extends CombatEntity` / `EnemyEntity extends CombatEntity` 两个子类 | ❌ 子类只改参数不改行为——过度分层，双份维护；敌人类型多（小兵/军曹/Boss）会继续膨胀子类 |
| C | 基类 + 策略组件组合 | ❌ MVP 无多态需求，组合是 #595 升级成长系统的候选，不是本层职责 |

### 4.3 数据所有权与两段血模型

**方案 A（推荐）：实体自持数据 + constants 初始化 + 信号广播**

hp_1 / hp_2 / stance / facing 为实体实例属性，初始值从 `WolfConstants` 读取（LIFE_1_MAX=100、LIFE_2_ABS=50、POSTURE_BREAK_THRESHOLD=100，# DRAFT 只读）；变更经 hp_changed / stance_changed 信号广播。

两段血语义：`_active_life ∈ {1, 2}` 标记当前受击条。hp_1 归零 → `die()` → dead 状态 + `died(final=false)`（#578 接管复活）；`revive()` → _active_life=2、hp_2=LIFE_2_ABS（50，独立计数）、架势清空、无敌 1s（INVINCIBLE_SECONDS # DRAFT）→ revive→idle；hp_2 归零 → `died(final=true)` 终态（供 SW-015 失败判定）。life_total=1 变体跳过 hp_2 直接终态。

Pros：数据与 DRAFT 表单一事实源一致；多敌人实例各自独立（未来战场多敌人必须）；信号契约直供 HUD（#576）。
Cons：实体需自管恢复/无敌计时（~30 行）。
Risk：**Low**。

**方案 B：数值存 Game autoload 全局**。❌ 多敌人实例无法区分（一个战场上多个日本兵共享血量=灾难）；Game 变成上帝对象。
**方案 C：数值存 constants 静态**。❌ 运行期无法变化（掉血/回血不可能）。

**本层新增时序常量（进 constants.gd # DRAFT 分区，只读，定稿归 #584）：**

| 常量 | 候补值 | 影响 | 情感断言 |
|------|--------|------|---------|
| `STAGGER_FRAMES` | 12（候选 [8,12,16]） | 受击硬直时长——太短无受击感，太长卡操作 | 硬直是「被打断」的代价，不是「罚站」 |
| `PARRY_SUCCESS_FRAMES` | 10（候选 [8,10,12]） | 弹反成功瞬间帧（硬直窗口，#577 驱动进入） | 弹反成功必须比格挡爽（只狼铁律 1） |
| `STANCE_BREAK_RECOVERY_SEC` | 3.0（#580 同值互引） | 崩解后敌人起身恢复时间 | 崩解=可从容处决的窗口（只狼铁律 2） |
| `REVIVE_SECONDS` | 1.0（#578 同值互引） | 倒地→复活的演出时长 | 「还没打完这一仗」，不是神迹 |
| `INVINCIBLE_SECONDS` | 1.0（#578 同值互引） | 复活后无敌时长 | 硬汉的第二次机会，不是耍赖 |

### 4.4 输入 → 状态映射（#2 输入事件映射为状态转移）

**方案 A（推荐）：CombatEntity 内嵌 `_StateInputBridge` 订阅 InputController 信号**

实体持有对 `InputController` 的引用（或由 #585 组装时 wire），订阅：attack_pressed → request_transition("attack")（idle/move/attack/guard 可入，attack 中再按=连段链）；heavy_attack_pressed → "heavy_attack"；guard_pressed → "guard"；guard 释放（无 guard_held）→ 回 idle；**垫步/跳不映射**（留在移动层，canonical 集无对应状态）。

Pros：状态契约权威在本层（issue body 指定「#2 输入事件映射为状态转移」归本契约）；下游 #577 无需关心输入→状态；headless 可 mock 信号单测。
Cons：实体需感知 InputController（解耦靠信号，不靠直接引用——用信号连接，headless 测试可手动 emit）。
Risk：**Low**。

**方案 B：映射放 #585 组装层**。❌ 状态契约权威在 #575，组装层映射会让状态语义悬空；#577/#581 依赖本层时映射还不存在。
**方案 C：PlayerController 内嵌映射**。❌ PlayerController 是移动实体（#573），战斗状态混入移动层违反单一职责；enemy 变体（无玩家输入）无法复用。

### 4.5 推荐汇总

| 决策点 | 推荐 | 核心依据 |
|--------|------|---------|
| 状态机架构 | A：StateMachineBase 派生 + 集中转移表 | #572 派生点预留；AC2 可断言；#574 写法同构 |
| 变体方式 | A：单类 + @export 参数 | issue body 明示；AC1 可测 |
| 数据所有权 | A：实体自持 + constants 初始化 + 信号 | 多敌人必须；HUD 信号契约 |
| 输入映射 | A：实体内 _StateInputBridge 订阅信号 | 状态契约权威在本层；headless 可 mock |
| 两段血 | A：_active_life 双条独立计数 | AC4 逐字满足；#578 驱动点清晰 |

---

## 5. 边界条件与验收

### 5.1 验收清单（源自 issue body 5 条 AC）

- [x] **AC1: 双变体实例化** — `CombatEntity.new()` 设置 is_player/life_total 后：玩家变体 hp_1=100、hp_2=50、stance=100；敌人变体（life_total=1）hp_1 可配（如 40）、hp_2 不参与、stance 可配（如 50）
  - 验证：headless 单测断言属性读写 + 变体差异（§7 实验 4）
- [x] **AC2: 状态流转合法性** — `request_transition()` 走转移表：stance_break 时 attack/heavy_attack/guard 全部 reject（push_warning + 状态不漂移）；表内转移全部通过
  - 验证：test_combat_entity.gd 遍历 11×11 状态对（§7 实验 1）
- [x] **AC3: 架势崩解广播** — `take_stance_damage(10)` 连续调用至 stance≤0 → 恰好一次 `break_stance()` + 恰好一次 `stance_broken` 信号 + 进入 stance_break 状态（幂等：崩解后再调用不二次广播）
  - 验证：信号计数断言（§5.2 边界 3）
- [x] **AC4: 两段血** — 打空 hp_1 → dead 状态 + `died(final=false)` + 状态机停摆（除 revive 外全部转移 reject）；`revive()` → revive 状态（1s）→ idle，hp_2=50 独立计数、stance 清空、无敌 1s 内 take_damage 无效；再打空 hp_2 → `died(final=true)` 终态
  - 验证：状态序列断言 `idle→dead→revive→idle→dead` + 血量断言（§7 实验 2）
- [x] **AC5: 三条主路径单测** — test_combat_entity.gd 覆盖：受击（take_damage → 掉血 + stagger 转移）、架势（take_stance_damage → 崩解 + 信号）、死亡（两段死亡流 + 复活流）
  - 验证：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 全绿

### 5.2 边界条件

1. **dead 状态受击** — take_damage/take_stance_damage 在 dead/revive 状态被调用 → no-op（0 伤害，不扣血不扣架势；判定层不该调，防御性兜底）
2. **复活无敌期内受击** — revive 后 1s（INVINCIBLE_SECONDS）内 take_damage → 0 伤害（#578 契约：不可受击、不可被弹反架势伤害）；无敌期结束自动失效
3. **架势溢出单次触发** — stance=5 时 take_stance_damage(10) → 恰好一次 break_stance（stance clamp 至 0，不因溢出二次广播）
4. **同态转移** — request_transition(当前状态) → StateMachineBase 同态守卫静默忽略（无回调无警告）
5. **guard 中架势崩解** — guard 状态 stance 归零 → 允许 guard→stance_break 转移（格挡中崩解=失衡，优先级高于格挡姿态）
6. **parry_success/execute 中受击** — 判定层窗口期语义：parry_success 免伤归 #577 裁决（本层提供状态位），execute 中无敌归 #580 驱动（本层转移表禁止 execute 中受击转移）
7. **facing 翻转** — 移动反向时 facing 更新；攻击中翻转由 #574 刀光/挥砍方向消费时机决定（本层只保证 facing 正确读写，AC1 覆盖）
8. **两段血边界** — hp_1 归零瞬间的连击第二段 → 实体已 dead，take_damage no-op，不重复 die
9. **hp/stance clamp** — hp_1/hp_2 ∈ [0, max]，stance ∈ [0, stance_max]；负伤害/NaN 防御性 clamp（§5.3 失败 4）
10. **life_total=1 变体** — 敌人无第二条血：hp_1 归零 → die() 直接 `died(final=true)`（不经过可复活 dead；复活语义仅玩家，#578 只挂玩家）

### 5.3 失败路径

1. **非法转移请求** — 任何代码绕过 `request_transition()` 直接调 fsm.transition_to()？→ 本层设计：状态对象 enter 内**只能**经 request_transition 改状态（状态对象持有 entity 引用，转移统一走实体入口）；非法请求 reject + push_warning + 状态不漂移（AC2 单测覆盖）
2. **状态机重入** — enter() 内嵌套 request_transition → StateMachineBase 防重入锁拦截（push_warning + 忽略）；战斗层约定：状态 enter 内**禁止**发起转移，一律延迟到 update（时序状态用帧计数自然退出）
3. **终态误复活** — hp_2 已归零（final=true）或 life_total=1 时调用 revive() → no-op + push_warning（终态不可复活；#578 驱动方必须只监听 died(final=false)）
4. **数值异常** — amount 为负/NaN/Inf → clamp 到 [0, ∞) 防御（hit 类接口对负值视为 0 并 push_warning）

---

## 6. 依赖与阻塞

### 6.1 依赖链

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #572（scaffold） | ✅ merged #599 | 无 | StateMachineBase + Game autoload + constants 骨架 |
| #573（输入） | ✅ merged #611 | 无 | InputController 意图事件（attack_pressed/guard_pressed/guard_held）——输入→状态映射源 |
| #574（动画） | ✅ merged #612 | 无 | consume_state 契约——本层状态名消费方（契约对齐是红线） |
| #584（数值 DRAFT） | ✅ merged #609 | 无 | constants 全量 DRAFT 数值（两条命/架势/刀伤害）——本层只读 |
| #577（判定） | ⛔ 未开始 | 中 | 依赖本层 take_damage/take_stance_damage + stance_broken；本层不阻塞（接口先交付） |
| #578（复活） | ⛔ 未开始 | 中 | 依赖本层 dead/revive 状态与 revive()；驱动时序（自动 vs F 键）由 #578 定，本层两路都支持 |
| #580（处决） | ⛔ 未开始 | 中 | 依赖 stance_break→execute 转移通道 |
| #581（敌AI） | ⛔ 未开始 | 中 | 依赖 enemy 变体实例化 |
| #576（HUD） | ⛔ 未开始 | 低 | 依赖 hp_changed/stance_changed 信号 |

```
#572 ──► #573 ──┐
#572 ──► #574 ──┼──► #575（本 issue）──► #576 HUD
#572 ──► #584 ──┘         │              ├──► #577 判定 ──► #578 复活
                          │              ├──► #580 处决
                          │              └──► #581 敌AI
                          └──► #585 组装 ──► #586 E2E
```

### 6.2 开源调研（issue body 要求「开源优先，成熟方案优先复用，找不到再自行实现，并在 PR 中说明调研结果」）

| 类别 | 候选 | 调研结论 |
|------|------|---------|
| Godot FSM | LimboAI（2962⭐）/ gd-YAFSM（668⭐）/ gdquest-design-patterns（443⭐） | **已在 #572 调研并明确否决**（GDD 03 §2：40 行自研 StateMachineBase 满足，不引入 addon）；本层直接复用 StateMachineBase，不重复调研 |
| Godot FSM（小插件） | kubecz3k/FiniteStateMachine（118⭐）、godot-addons/godot-finite-state-machine（100⭐）、VisualFSM（18⭐）、EasyStateMachine（13⭐）、fsm-godot（12⭐）、OmniStatevFSM（10⭐） | 全部为 Node 型/编辑器可视化插件，面向场景树状态机；本层是 RefCounted 数据+状态容器（headless 可测），插件无增益，且与 #572 已交付派生写法冲突 |
| 战斗实体/架势/弹反 | GitHub 检索 godot+combat / godot+parry / godot+sekiro：mecha-party-fighters（2⭐）、parry-shmup（1⭐）、scout（1⭐）、parry-pong（1⭐）、TurnBase-Parry-and-Dodge（1⭐）、Midlands-Besiege-Saga（0⭐） | 全部为个人习作/课程演示（0-2⭐），无成熟可复用模板，无 hp+stance+两段命数据模型先例 |
| 复活/两条命 | godot+respawn+player 检索 | 仅 0⭐ 演示项目，无成熟方案 |

**结论：** FSM 层复用 #572 自研 StateMachineBase（已有裁决）；战斗实体层无成熟开源可复用 → **自研 CombatEntity**（issue body 允许「找不到再自行实现」）。implement PR 须引用本调研结论。

### 6.3 前置准备

- [ ] implement 前确认 origin/main 已含 #609/#611/#612（本 PRD 侦查基准 e70dcb2 已含）
- [ ] 本 PRD merge 后，plan agent 读 §8 交接上下文即可开工，无需重扫源码

---

## 7. Spike / 实验（depth/deep 必填，≥3 实验）

### 实验 1：集中转移表覆盖性验证

- **要回答的问题**：数据驱动转移表能否覆盖 11 态全部合法转移，且所有非法转移（含红线案例 stance_break→attack）都被拒绝？
- **方法**：headless 单测遍历 11×11=121 个状态对，对每个 (from, to)：`is_legal(from, to)` 结果与人工整理期望表比对；再对合法转移执行 `request_transition` 断言状态实际切换、非法转移断言 reject + 状态不漂移 + push_warning
- **预期结果**：表内/表外判定 100% 一致；AC2 红线案例（stance_break→attack/heavy_attack/guard）全部拒绝
- **对方案的影响**：若表驱动出现遗漏（合法转移被误拒），需补表条目而非改架构；若发现转移表无法表达的守卫（如「attack 中连段需缓冲队列非空」），追加守卫函数进 request_transition（表=拓扑合法性，守卫=条件合法性，两层设计）

### 实验 2：两段血 dead→revive 状态流时序

- **要回答的问题**：hp_1 归零 → dead → revive() → revive → idle → hp_2 独立计数的完整序列，是否与 #578 契约（1s 倒地、半管第二条、无敌 1s、架势清空）逐项一致？
- **方法**：headless 模拟：take_damage(100) 打空 hp_1 → 断言状态=dead + died(final=false) + 其余转移全 reject；调 revive() → 断言 revive 状态 + INVINCIBLE_SECONDS 内 take_damage 无效 + 期满后有效；打空 hp_2 → 断言 died(final=true) + 终态；life_total=1 变体打空 → 直接 final=true（跳过复活）
- **预期结果**：状态序列 `idle→dead→revive→idle→dead` 精确复现；hp_2 独立计数（不受 hp_1 残值影响）
- **对方案的影响**：若 revive() 由 F 键（#573 revive_pressed）驱动而非自动，本层接口不变（谁调 revive() 是 #578 的事）；若「复活后架势清空」语义有分歧（清空 vs 半额），记入 §8 风险清单交 #584/#578 裁决

### 实验 3：架势上限派生规则（只狼铁律：架势上限 = 当前 HP 上限）

- **要回答的问题**：sekiro-tuning-reference 表「架势上限 = 当前 HP 上限，低血时架势上限同比例降」——MVP 采用固定值（POSTURE_BREAK_THRESHOLD=100 # DRAFT）还是跟随当前 HP 派生？
- **方法**：实现两种派生原型：①固定 100（stance_max 常量）；②stance_max = 当前 hp 总量（hp_1+hp_2 活性条），低血时按比例收缩。对比：HUD 展示语义（#576 读 stance_max 画条）、判定消费语义（#577 崩解阈值随血下降）、与 #584 调参面板（POSTURE_BREAK_THRESHOLD 候选 [100,150]）的兼容性
- **预期结果**：MVP 推荐**固定值**（POSTURE_BREAK_THRESHOLD 直接初始化 stance_max）——派生规则是手感层裁决（影响难度曲线），归 #584 候选；本层预留 `_recalc_stance_max()` 钩子（当前返回常量，未来可派生），接口不变
- **对方案的影响**：若用户裁决派生规则，本层只需改 _recalc_stance_max 内部实现 + 单测，信号契约（stance_changed 携带 stance_max）不动

### 实验 4：玩家/敌人变体参数化冒烟

- **要回答的问题**：单类 + @export 参数能否无歧义实例化两种变体，且 headless 全流程可用？
- **方法**：headless smoke：`CombatEntity.new()` 分别配玩家参数（life_total=2, life_1_max=100, life_2_abs=50, stance_max=100）与敌人参数（life_total=1, life_1_max=40, stance_max=50），断言初始属性、take_damage/take_stance_damage 行为差异、died(final) 语义差异
- **预期结果**：两变体同代码路径不同数据，全部断言通过
- **对方案的影响**：若出现敌人特有行为（如 AI 状态叠加）无法参数化表达，标记为 #581 的扩展点（AI 状态在 #581 用同一 StateMachineBase 叠加，不修改本层基类）

---

## 8. 交接上下文（plan agent 交接）

### 8.1 系统现状快照

- origin/main @ e70dcb2（#612 已 merge）：StateMachineBase（RefCounted 三接口 + 转移守卫）、WolfConstants 全量 # DRAFT（两条命/架势/帧节奏/刀伤害）、Game autoload、InputController（9 意图信号 + 缓冲）、PlayerController（移动）、StickFigureController.consume_state（11 态动画契约）、stick_figure_anim_states.gd（状态对象写法范本）、debug_canvas（#584 调参面板）
- 战斗层（本 issue）**零存在**：无 combat 脚本、无测试、无场景实例化（实例化归 #583/#585）

### 8.2 交付物清单（按实现顺序）

| 顺序 | 文件 | 内容 |
|:----:|------|------|
| 1 | `constants.gd`（修改） | 追加 §4.3 五个时序 # DRAFT 常量（STAGGER_FRAMES=12 / PARRY_SUCCESS_FRAMES=10 / STANCE_BREAK_RECOVERY_SEC=3.0 / REVIVE_SECONDS=1.0 / INVINCIBLE_SECONDS=1.0），注释含候补值+影响+情感断言，定稿归 #584 |
| 2 | `combat_state_table.gd`（新增） | `TRANSITIONS: Dictionary`（11 态转移表，见 §4.1 方案 A）+ `is_legal(from, to)`；表内容以 §4.1 转移语义为准（stance_break 禁 attack/heavy_attack/guard 等红线） |
| 3 | `combat_states.gd`（新增） | `CombatStateBase`（RefCounted：name + entity + enter/exit/update）+ 11 个状态对象；定时状态用帧常量计数自动退出；**状态名逐字对齐 canonical 集合**（#574 consume_state 消费同名） |
| 4 | `combat_entity.gd`（新增） | `class_name CombatEntity extends Node2D`：@export 变体参数（is_player/life_total/life_1_max/life_2_abs/stance_max）、hp_1/hp_2/stance/facing/is_stance_broken/_active_life 数据、take_damage/take_stance_damage/break_stance/die/revive 接口、request_transition 唯一转移入口（查表+守卫）、信号（hp_changed/stance_changed/stance_broken/state_changed/died/revived）、_StateInputBridge（订阅 InputController：attack/heavy_attack/guard 三映射，垫步/跳不映射）、_recalc_stance_max 钩子（实验 3） |
| 5 | `test_combat_entity.gd`（新增） | 受击/架势/死亡 3 主路径（AC5）+ 转移表 121 对遍历（实验 1）+ 两段死亡流（实验 2）+ 变体冒烟（实验 4）+ 边界/失败路径用例（§5.2/§5.3） |
| 6 | `run_tests.gd`（修改） | 注册 test_combat_entity.gd；smoke_test.gd 可选加实体实例化探针 |

### 8.3 接口契约（下游系统的消费面）

```gdscript
## CombatEntity（class_name，extends Node2D）
@export var is_player: bool = false
@export var life_total: int = 2        # 玩家 2 / 小兵 1
@export var life_1_max: float = 100.0  # 默认 WolfConstants.LIFE_1_MAX
@export var life_2_abs: float = 50.0   # 默认 WolfConstants.LIFE_2_ABS
@export var stance_max: float = 100.0  # 默认 WolfConstants.POSTURE_BREAK_THRESHOLD
var hp_1: float
var hp_2: float                        # life_total=1 时不参与
var stance: float
var facing: int = 1
var is_stance_broken: bool
var state_name: String                 # canonical 状态名（#574 consume_state 消费）

func take_damage(amount: float, source: Object) -> void    # #577 调用；hp_1≤0 → die()
func take_stance_damage(amount: float) -> void             # #577 调用；stance≤0 → break_stance()
func break_stance() -> void                                # 幂等；广播 stance_broken
func die() -> void                                         # dead 状态 + died(final) 信号
func revive() -> void                                      # #578 调用；dead→revive→idle
func request_transition(to: StringName) -> bool            # 唯一转移入口（查表 + 守卫）

signal hp_changed(hp_1: float, hp_2: float, active_life: int)          # #576 HUD
signal stance_changed(stance: float, stance_max: float)                # #576 HUD
signal stance_broken(entity: CombatEntity)                             # #577/#580
signal state_changed(from: String, to: String)                         # #574/#576
signal died(entity: CombatEntity, final: bool)                         # #578(final=false)/SW-015(final=true)
signal revived(entity: CombatEntity)                                   # #578
```

### 8.4 主要风险与裁决点

1. **#578 复活驱动时序**（自动 1s vs F 键）：本层 dead 状态 + revive() 接口两路兼容；#578 实现时定夺，若自动则监听 died(final=false) 起 1s 计时后调 revive()
2. **受击硬直规则**：take_damage 默认在非 guard/parry_success/execute/revive/dead 状态触发 stagger 转移；#577 判定层若需更细（弹反成功免伤、格挡扣架势不扣血）在调用侧裁决，不修改本层默认
3. **架势上限派生**（实验 3）：MVP 固定 POSTURE_BREAK_THRESHOLD；派生规则候选交 #584 调参面板
4. **#574 状态名对齐**：implement 后必须跑 #574 的 consume_state 侧单测/冒烟验证 11 态逐名匹配（stick_figure_anim_states.gd 的 ANIM_CLIP_NAMES 键集 = 本层状态名集合）
5. **GDD 落盘**：post-merge agent 新增 `docs/GAME_DESIGN/shandong-wolf/06-COMBAT-ENTITY.md`（数据模型 + 转移表 + 信号契约）

### 8.5 红线（implement agent 禁止）

- ❌ 不造 canonical 集合外的状态名（禁止 parry 单列 / run 代替 move）
- ❌ 不引入第三方 addon（#572 裁决；§6.2 调研结论）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不修改 scenes/Main.tscn（标题场景红线）
- ❌ 不裁决 # DRAFT 数值（只读 constants；新常量也标 # DRAFT）
- ❌ 不做判定/演出逻辑（#577/#578/#580 职责）

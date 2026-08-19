# PRD #577 — [Feature] 拼刀 / 弹反 / 架势崩解判定系统

> **Issue:** #577
> **标签:** enhancement, gameplay, content, version/mvp, workflow/research（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=6）
> **深度:** deep（分解 JSON id=6 标注 `depth: deep` → §1–8 全必填，§7 含 ≥3 实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: mechanical`（判定规则=机械工程；手感数值全部 # DRAFT 只读，定稿归 #584）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`：wiki grep 只狼 → `wiki/游戏设计理念.md`（只狼=「机制作为修辞」的灵感来源）；raw grep 弹反/格挡/架势 → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（「弹反/闪避 = 时机判定」动作进阶层 + 分层设计））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：弹反窗口 10-14 帧、弹反扣架势 0-2、受击双重惩罚、架势崩解→可处决）+ 同链 issues（#575 已 merged / #579 反馈 / #574 动画 / #593 音效）+ 开源调研（GitHub API 检索 godot+hitbox / godot+parry / godot+sekiro，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=6，estimate 4d，priority critical）
> **前置依赖:** #575（CLOSED/status/done，PR #618 merged：CombatEntity + 11 态战斗状态机 + guard→parry_success 转移表已预留）——已满足

---

## 1. 问题定义

### 1.1 现状（2026-08-19 worktree 侦查 @ origin/main 1bdb6c7）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ 已交付（#575/#618） | take_damage / take_stance_damage / break_stance / die / revive / request_transition 全接口 + 6 信号（hp_changed/stance_changed/stance_broken/state_changed/died/revived）；take_damage 在 guard 状态不触发 stagger——**判定层调用侧裁决位已预留** |
| `shandong-wolf/gdscripts/combat_state_table.gd` | ✅ 已交付（#575/#618） | 11 态转移表：`guard → parry_success` 表内——注释明言「guard → parry_success 表内（#577 弹反成功驱动入口）」——**弹反状态入口已预留** |
| `shandong-wolf/gdscripts/input_controller.gd` | ✅ 已交付（#573/#611） | guard_pressed(timestamp_ms)（仅时间戳，注释明言「弹反判定归 #6」）+ guard_held（按住期间每帧）——**判定输入源已就位** |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#584/#609） | PARRY_WINDOW_FRAMES=12（候选 [8,10,12,14]）、POSTURE_BLOCK_COST=10、POSTURE_HIT_COST=35、PARRY_COST=1.0、FRAME_ATTACK_WINDUP=8、FRAME_ATTACK_RECOVERY=14、PARRY_SUCCESS_FRAMES=10、STAGGER_FRAMES=12——**但缺判定专用常量**（弹反架势伤害/拼刀架势成本/攻击判定窗口/距离） |
| `shandong-wolf/gdscripts/sword_arc.gd` | ✅ 已交付（#574/#612） | 注释明言「节点树无 Area2D/CollisionShape2D/任何碰撞类型，碰撞判定归 #577」——**判定层=逻辑帧窗口，非物理碰撞**（架构裁决已定） |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | ✅ 已交付（#574/#612） | consume_state 消费 11 态：attack 三段（前摇/暴发/收招）时间边界由 constants 派生；parry_success → anim_parry_success——**判定结果动画位已就位** |
| `shandong-wolf/gdscripts/` | ❌ 无判定层 | 无 CombatJudge、无攻击帧窗口描述器、无 clash 检测、无结果事件发射器——**本 issue 全部新建** |
| `shandong-wolf/tests/` | ✅ 三入口（#572）+ combat 套件（#575） | run_tests.gd 已挂 test_combat_entity.gd；本 issue 追加 test_combat_judge.gd |

**核心缺口：** shandong-wolf 已具备判定所需的一切**原料**（实体数据/状态接口、guard 输入时间戳、弹反状态转移入口、只狼基准常量、动画消费位），但**判定层本身零存在**——没有「敌人攻击命中玩家时按 弹反→拼刀→格挡→受击 优先级裁决」的执行者，没有攻击帧窗口（Hitbox）与弹反帧窗口（Parry-box）的叠加检测，没有 parry_success/block_held/hit_landed/stance_broken/clash 五个结果事件的发射器（#579 反馈 / #574 动画 / #593 音效都在等这些事件）。

### 1.2 验收条件（源自 Issue #577 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | 玩家在弹反窗口内被攻击命中时，受到 0 伤害且对攻击者造成 ≥20 架势伤害（数值来自 constants.gd） | §4.2 方案 A（guard_pressed 时间戳 vs 敌人 hit 帧对齐）+ §5.1 AC1：PARRY_STANCE_DAMAGE≥20（# DRAFT）经 take_stance_damage 施加，不调 take_damage（0 伤害），request_transition("parry_success") |
| AC2 | 双方攻击判定重叠时触发 clash 拼刀，双方均收到小架势伤害且事件信号发出 | §4.4 + §5.1 AC2：攻击帧窗口重叠检测 → 双方 take_stance_damage(CLASH_STANCE_COST) + emit clash |
| AC3 | 敌人架势值归零时进入 stance_break 状态并广播信号 | §4.1 + §5.1 AC3：消费 #575 stance_broken 信号并转发结果事件（#575 已幂等广播；本层统一事件出口） |
| AC4 | 弹反窗口、架势数值全部从 constants.gd 读取，PR 中说明调参候选 | §5.1 AC4：全部判定数值引用 WolfConstants，新常量标 # DRAFT + 候选集，禁硬编码 |
| AC5 | 单元测试覆盖：弹反成功/拼刀/未弹反受击 三条判定路径 | §5.1 AC5 + §8：test_combat_judge.gd 三组用例（§7 实验 1/2 落地） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机战斗（MVP 核心手感） | 每次游玩 | 玩家按 L 格挡：敌人攻击命中瞬间若在弹反窗口内 → parry_success（火花+硬直+敌人架势大涨）；按住 → block_held（扣自身架势不扣血）；双方同时出刀 → clash（金属声+双方小架势伤害）；没挡住 → hit_landed（掉血+扣架势双重惩罚） |
| B | 下游反馈/动画/音效消费（#579/#574/#593） | 每次判定 | 五个结果事件驱动：parry_success → 弹反四要素（火花/hit-stop/屏震/白闪）+ anim_parry_success + 清脆 ding；clash → 拼刀特效；hit_landed → 受击反馈 |
| C | 开发者 headless 验证 | 每次 impl PR | 模拟帧序列：构造玩家/敌人实体 + 攻击窗口 + guard_pressed 时间戳，断言裁决结果与事件发射——不依赖场景树与真实输入 |

### 1.4 范围边界（Patch 14 去冲突 + 判定层红线）

| PRD / 分解 id | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #575（实体/状态机，merged） | 数据容器 + 11 态转移 + take_damage/take_stance_damage/break_stance | ❌ 不修改实体接口与转移表；只消费其信号与调用其接口；guard→parry_success 入口**原样使用** |
| #584（数值 DRAFT，merged） | 全量 # DRAFT 数值 + 调参面板 | ❌ 不裁决数值；全部只读；新增判定常量同样标 # DRAFT 待 #584 定稿 |
| 分解 id 8 / #579（反馈，未开始） | 火花/hit-stop/屏震/慢动作 反馈矩阵，消费判定结果事件 | ❌ 不做渲染/演出；本层只**发射事件**，反馈组合归 #579 |
| 分解 id 3 / #574（动画，merged） | consume_state 11 态动画 + 刀光 | ❌ 不消费动画；本层结果事件触发 request_transition("parry_success") 后动画层自动跟随 |
| 分解 id 22 / #593（音效，未开始） | 程序化音效，消费 #579 反馈事件 | ❌ 不发声；音效归 #593 联动 #579 |
| 分解 id 5 / #581（敌AI，未开始） | 巡逻/追击/攻击 AI 状态 | ❌ 不做 AI；本层只定义 AttackWindow 注册契约（§8.3），AI 攻击窗口由 #581 提供 |
| 分解 id 7 / #578（复活）/ id 9 / #580（处决） | 复活/处决驱动 | ❌ 不做；本层只裁决「命中结果」 |

**判定层红线（issue body + 代码注释三重声明）：**
- 判定是**逻辑帧窗口检测**（时间戳/帧计数对齐），不是 Area2D 物理碰撞——sword_arc.gd 注释明言零碰撞体、判定归 #577（§4.2 方案对比详述）
- 结果事件名固定：`parry_success` / `block_held` / `hit_landed` / `stance_broken` / `clash`——#579/#574/#593 按此订阅，禁止改名
- 全部数值走 constants.gd # DRAFT 只读，禁止实现期定稿

---

## 2. 设计意图

### 2.1 为什么现在做

1. **判定原料全部就绪（2026-08-19）**：输入时间戳（#573）、实体数据接口（#575）、弹反状态入口（#575 转移表 guard→parry_success）、动画消费位（#574）、只狼基准常量（#584）——五层地基齐备，判定层是唯一缺口，也是 MVP 战斗闭环（#585 组装）的最后一个逻辑组件。
2. **只狼机制对齐（sekiro-tuning-reference）**：「弹反成功必须比格挡爽」（成功 0 伤害+敌架势大涨）、「受击双重惩罚」（扣血+扣架势）、「架势崩解→可处决」——三条铁律全部落在本层的裁决优先级与数值流向上。
3. **这是『我赢了一场艰难的仗』的核心手感引擎**（issue body 审美坐标）：弹反「难而公平」的窗口（只狼基准 10-14 帧）、拼刀的双方代价、失败代价明确——判定层的裁决粒度决定手感基调，必须先于 #585 组装落地。

### 2.2 为什么是本层（历史成因）

判定逻辑在本 issue 之前散落为「注释预留」：input_controller 注释「弹反判定归 #6」、sword_arc 注释「碰撞判定归 #577」、combat_state_table 注释「guard → parry_success 表内（#577 弹反成功驱动入口）」、PRD 575 §8.4 风险 2「#577 判定层若需更细（弹反成功免伤、格挡扣架势不扣血）在调用侧裁决」。本 issue 是这些预留位的**唯一收口**。

### 2.3 本层设计意图

- **判定器 = 事件协调器，不是实体**：CombatJudge 是独立 Node（非 CombatEntity 子类），订阅双方实体状态 + guard 输入 → 按优先级裁决 → 调用实体接口 + 发射结果事件。实体层（#575）与判定层解耦，判定规则可 headless 单测。
- **窗口 = 时间/帧区间，不是空间体**：攻击命中窗口 = `[FRAME_ATTACK_WINDUP, FRAME_ATTACK_WINDUP + HITBOX_ACTIVE_FRAMES]`（帧计数，@60fps 派生秒）；弹反窗口 = guard_pressed 时间戳 ∈ `[敌人 hit 帧 - PARRY_WINDOW_SECONDS, 敌人 hit 帧]`（时间戳对齐，只狼基准）。方向判定用实体 facing 对比攻击方向。
- **优先级 = 显式常量**：弹反 > 拼刀 > 格挡 > 受击（issue body 明示「拼刀优先级」进 constants # DRAFT 用户裁决），裁决顺序可调。
- **事件 = 契约**：五个结果事件是 #579/#574/#593 的唯一输入面（§3.3 数据流图），信号签名固定。

---

## 3. 影响分析

### 3.1 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/combat_judge.gd` | **新增** | CombatJudge（Node，class_name）：订阅实体 state_changed + 输入 guard_pressed/guard_held → 攻击帧窗口登记 → 命中裁决（弹反/拼刀/格挡/受击）→ 调用 take_damage/take_stance_damage/request_transition + 发射五个结果事件 |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | **新增** | AttackWindow 描述器（RefCounted）：attacker/start_frame/active_frames/hp_damage/stance_damage/direction——#581 敌AI 与玩家攻击共用的攻击窗口契约（§8.3） |
| `shandong-wolf/gdscripts/constants.gd` | 修改 | 追加判定分区 # DRAFT 常量（PARRY_STANCE_DAMAGE / CLASH_STANCE_COST / CLASH_PRIORITY / HITBOX_ACTIVE_FRAMES / HITBOX_RANGE / PARRY_DIRECTION_TOLERANCE，候选集+只狼出处，定稿归 #584） |
| `shandong-wolf/tests/test_combat_judge.gd` | **新增** | 弹反成功/拼刀/未弹反受击 三条判定路径 + 优先级冲突矩阵 + 事件发射断言 |
| `shandong-wolf/tests/run_tests.gd` | 修改 | 注册 test_combat_judge.gd |

### 3.2 间接受影响的模块（下游消费者，本次不改）

| 文件/系统 | 影响 | 消费方式 |
|-----------|------|---------|
| #579 反馈（未建） | parry_success/clash/hit_landed/stance_broken/block_held → 反馈矩阵 | 订阅 CombatJudge 结果事件 |
| #574 动画（已建） | parry_success → state_changed → consume_state("parry_success") 播硬直帧 | 经 #575 状态转移间接消费 |
| #593 音效（未建） | parry_success ding / clash 金属声 | 经 #579 反馈事件联动 |
| #581 敌AI（未建） | 攻击前摇期间注册 AttackWindow | 调用 CombatJudge.register_attack_window() |
| #585 组装（未建） | CombatJudge 实例化 + wire（实体×2 + InputController） | 实例化 + bind |

### 3.3 数据流图

```
#573 InputController（guard 输入）
    │  guard_pressed(timestamp_ms) / guard_held（每帧）
    ▼
CombatJudge（判定协调器）
    │  订阅 #575 CombatEntity.state_changed(from, to)
    │  攻击窗口登记: 实体进入 attack/heavy_attack → register_attack_window(AttackWindow)
    │  敌人 hit 帧到达 / 双方窗口重叠 / 输入事件到达 → 优先级裁决:
    │
    ├── 弹反: guard_pressed 时间戳 ∈ [敌人hit帧-窗口, 敌人hit帧] + facing 正确
    │      ├── 玩家 0 伤害（不调 take_damage）
    │      ├── 敌人 take_stance_damage(PARRY_STANCE_DAMAGE ≥20)
    │      ├── 玩家 request_transition("parry_success")（#575 转移表已预留）
    │      └── emit parry_success(defender, attacker, damage) ──► #579 弹反四要素 / #574 anim_parry_success
    │
    ├── 拼刀: 玩家攻击窗口 ∩ 敌人攻击窗口 ≠ ∅
    │      ├── 双方 take_stance_damage(CLASH_STANCE_COST)
    │      └── emit clash(entity_a, entity_b, cost) ──► #579 拼刀特效 / #593 金属声
    │
    ├── 格挡: guard_held 且非弹反窗口
    │      ├── 玩家 take_stance_damage(POSTURE_BLOCK_COST)（不扣血）
    │      └── emit block_held(defender, attacker, cost) ──► #579 最小火花
    │
    ├── 受击: 无以上任何条件
    │      ├── 玩家 take_damage(敌hp伤害) + take_stance_damage(POSTURE_HIT_COST)（双重惩罚）
    │      └── emit hit_landed(defender, attacker, hp, stance) ──► #579 受击反馈
    │
    └── 架势崩解: 消费 #575 stance_broken 信号
           └── emit stance_broken(entity) ──► #579 全屏淡白闪 / #580 处决通道
```

### 3.4 需更新的文档

- [ ] `docs/GAME_DESIGN/shandong-wolf/` 新增判定系统章节（post-merge agent 落盘，编号 07-COMBAT-JUDGE）
- [ ] `docs/GAME_DESIGN/shandong-wolf/03-STATE-MACHINE.md` 集成点表格补 #577 行
- [ ] `docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md` 补充判定分区常量
- [ ] `PROJECT.md` 战斗系统进度更新

---

## 4. 方案对比

### 4.1 判定架构（核心决策）

**方案 A：独立 CombatJudge 判定器（推荐）**

独立 Node（class_name CombatJudge），持有双方实体引用 + InputController 引用，订阅信号做裁决。职责单一：窗口登记 → 优先级裁决 → 调用实体接口 → 发射事件。headless 可直接 new + 手动 emit 信号单测。

| 维度 | 内容 |
|------|------|
| 位置 | gdscripts/combat_judge.gd（Node，非 autoload——#585 组装时实例化进场景或测试直接 new） |
| 输入 | 订阅实体 state_changed（登记攻击窗口）+ InputController.guard_pressed/guard_held |
| 裁决 | resolve_attack(attacker, defender) 按优先级 弹反→拼刀→格挡→受击 |
| 输出 | 调用实体接口 + 发射五个结果事件 |

Pros：判定规则集中在单一可测类（AC5 三条路径 headless 直接断言）；不侵入 #575 实体（已合并，改动成本高）；#581 敌AI 只需注册 AttackWindow 即可复用同一裁决器；与 #579 ReactionController 的「统一消费反馈」架构对偶。
Cons：多一个协调器节点（#585 组装需 wire）。
Risk：**Low**。Effort：2-3 天。

**方案 B：判定逻辑内嵌 CombatEntity**

在 #575 已合并的 combat_entity.gd 里加 hit 检测/窗口裁决。

Pros：无新文件。
Cons：#575 已合并并自测，侵入式修改破坏「实体=数据+状态」单一职责（#575 PRD 红线「本层不做判定」）；玩家与敌人判定规则相同但触发源不同（玩家=输入窗口，敌人=AI 窗口），内嵌难以复用；headless 测试需实体带状态机全链。
Risk：**Med**（违反 #575 既定分层 + 已合并代码返工）。Effort：1-2 天。

**方案 C：信号链分散判定（无中心裁决器）**

攻击窗口/弹反窗口各自独立检测，通过信号互相通知。

Pros：无中心类。
Cons：优先级裁决（弹反 vs 拼刀 vs 格挡）需要全局视图——分散后裁决顺序不可枚举、冲突矩阵无法单测（AC5 的「三条判定路径」无单一入口可断言）；事件顺序不确定。
Risk：**High**（裁决顺序不可测 = 手感基调失控）。Effort：2-3 天。

**推荐：方案 A**。理由：① 与 #575 既定分层（实体不做判定）逐字一致；② AC5「三条判定路径」需要单一可测裁决入口，只有 A 提供；③ #581 敌AI / #585 组装的下游契约（AttackWindow 注册）只有 A 能提供统一接口；④ 与 #579 反馈统一消费架构对偶。

### 4.2 Hitbox/Parry-box 表示（帧窗口 vs 物理碰撞）

**方案 A：逻辑帧窗口（时间戳/帧计数对齐，推荐）**

Hitbox = 攻击有效帧区间 `[FRAME_ATTACK_WINDUP, FRAME_ATTACK_WINDUP + HITBOX_ACTIVE_FRAMES]`（帧计数，@60fps 派生秒）；Parry-box = 弹反时间窗 `[敌人 hit 帧 - PARRY_WINDOW_SECONDS, 敌人 hit 帧]`（guard_pressed 时间戳对齐）。

Pros：与 sword_arc.gd 注释「零碰撞体、判定归 #577」架构裁决一致；headless 可精确构造帧序列单测（不依赖物理引擎帧序）；时间戳对齐直接消费 #573 guard_pressed(timestamp_ms) 契约；无 Area2D/CollisionShape2D 节点树开销。
Cons：空间判定（距离/方向）需自行计算（用实体 position + facing，横板一维足够）。
Risk：**Low**。Effort：1 天（相对物理方案）。

**方案 B：Area2D hitbox/hurtbox 物理碰撞（godot-health-hitbox-hurtbox 模式）**

实体挂 Area2D + CollisionShape2D，用 body_entered/area_entered 检测命中。

Pros：Godot 生态成熟模式（169⭐ 组件库核心思路）；距离/方向由物理层天然解决。
Cons：与 sword_arc.gd 明确注释冲突（「节点树无 Area2D/CollisionShape2D/任何碰撞类型」）——#574 视觉层已按零碰撞体交付，引入物理碰撞 = 视觉层返工；火柴人 Line2D 骨架无碰撞形状，需额外造形状节点；**弹反窗口是时间判定不是空间判定**（guard_pressed 时间戳 vs 攻击帧），Area2D 无法表达；headless 单测需要物理场景（SceneTree 物理帧），违背项目「免树直接 new」测试范式。
Risk：**High**（与 #574 架构裁决冲突 + 时间窗无法表达）。Effort：2-3 天。

**方案 C：混合（逻辑窗口 + 距离校验）**

帧窗口判定为主，命中瞬间追加 `abs(attacker.x - defender.x) <= HITBOX_RANGE` 与 facing 方向校验（横板一维）。

Pros：保留逻辑判定的可测性，补充基本空间真实性（距离外挥空不命中）。
Cons：比纯逻辑多一个距离常量（# DRAFT）。
Risk：**Low**。Effort：1 天。

**推荐：方案 A（含距离/facing 校验，即 A∩C）**。理由：① 唯一符合 #574「零碰撞体」既定架构的选项；② 弹反窗口本质是时间窗（只狼基准），物理碰撞无法表达「按下时机 vs 攻击帧」的对齐；③ 项目测试范式是免树直接 new（#575 先例），物理方案破坏该范式。

### 4.3 弹反窗口检测实现

| 方案 | 描述 | 裁决 |
|------|------|:----:|
| **A（推荐）** | guard_pressed(timestamp_ms) 记录最近按下时刻；敌人攻击 hit 帧到达时比较 `press_ms ∈ [hit_ms - PARRY_WINDOW_SECONDS*1000, hit_ms]` → parry 成功；facing 校验：玩家 facing 朝向攻击者 | ✅ 直接消费 #573 时间戳契约；窗口边界精确可单测（§7 实验 1）；只狼基准 10-14 帧 = PARRY_WINDOW_FRAMES 直接换算 |
| B | 实体状态位轮询：每帧检查 defender.state_name == "guard" 且进入 guard 帧数 ≤ PARRY_WINDOW_FRAMES | ❌ 依赖状态机帧计数而非输入时间戳；guard 可能由格挡按住进入（guard_held），无法区分「按下时机」与「持续按住」——弹反只响应 guard_pressed（#573 契约语义） |
| C | 输入缓冲队列消费（InputController.poll_buffer） | ❌ #573 缓冲队列是攻击连招用，guard 是边缘事件（#573 已直接发射 guard_pressed 信号），绕一层缓冲无增益 |

### 4.4 拼刀（clash）优先级

| 方案 | 描述 | 裁决 |
|------|------|:----:|
| **A（推荐）** | 优先级常量 `CLASH_PRIORITY`：弹反 > 拼刀 > 格挡 > 受击。裁决顺序：先查弹反（若满足则 parry_success 短路），再查双方攻击窗口重叠（clash），再查 guard_held（block_held），最后 hit_landed | ✅ issue body 明示「拼刀优先级等集中 constants.gd # DRAFT(候选,用户裁决)」——显式常量可调可单测；弹反优先符合只狼「弹反是最高奖励动作」铁律 |
| B | 时间序先到先得：谁先命中谁赢 | ❌ 同一帧内双方命中先后依赖帧序（物理帧抖动），不可测；「拼刀优先级」无法表达 |
| C | 拼刀优先于弹反 | ❌ 玩家明明精准按出弹反窗口却被拼刀顶掉 = 高操作被低操作覆盖，违背只狼「弹反必须比格挡爽」铁律 1 |

### 4.5 事件契约

| 方案 | 描述 | 裁决 |
|------|------|:----:|
| **A（推荐）** | CombatJudge 统一发射五事件：`parry_success(defender, attacker, stance_damage)` / `block_held(defender, attacker, stance_cost)` / `hit_landed(defender, attacker, hp_damage, stance_damage)` / `clash(a, b, stance_cost)` / `stance_broken(entity)`（转发 #575 信号） | ✅ issue body 指定事件名逐字对齐；单一出口 = #579/#574/#593 订阅面稳定；stance_broken 转发保持「判定结果统一从判定器出」 |
| B | 实体各自发射 | ❌ 事件来源分散，#579 需同时订阅两个实体 + 输入层；stance_broken 已由 #575 发射，再发射=重复 |
| C | 事件名省略参数 | ❌ #579 反馈需要伤害数值（火花规模/屏震幅度按事件奖励分级），无参数事件无法表达反馈强度 |

### 4.6 推荐汇总

| 决策点 | 推荐 | 核心依据 |
|--------|------|---------|
| 判定架构 | A：独立 CombatJudge 判定器 | 与 #575 分层一致；AC5 单一可测入口；#581/#585 统一契约 |
| Hitbox 表示 | A：逻辑帧窗口 + 距离/facing 校验 | #574 零碰撞体架构裁决；弹反=时间窗无法用物理表达 |
| 弹反窗口 | A：guard_pressed 时间戳对齐 | #573 时间戳契约直读；只狼基准直接换算 |
| 拼刀优先级 | A：CLASH_PRIORITY 显式常量（弹反>拼刀>格挡>受击） | issue body 要求常量可调；只狼铁律 |
| 事件契约 | A：判定器统一发射五事件 | issue body 事件名逐字对齐；#579 订阅面稳定 |

---

## 5. 边界条件与验收

### 5.1 验收清单（源自 issue body 5 条 AC）

- [x] **AC1: 弹反成功** — guard_pressed 时间戳落在敌人 hit 帧窗口内 + facing 正确 → 玩家 0 伤害（不调 take_damage）+ 敌人 take_stance_damage(PARRY_STANCE_DAMAGE ≥20) + request_transition("parry_success") + emit parry_success
  - 验证：headless 构造帧序列：敌人 hit 帧 T，guard_pressed 在 [T-window, T] 内 → 断言玩家 hp 不变、敌人 stance 减少 ≥20、玩家状态=parry_success、事件参数正确（§7 实验 1）
- [x] **AC2: 拼刀** — 玩家攻击窗口 ∩ 敌人攻击窗口非空 → 双方 take_stance_damage(CLASH_STANCE_COST) + emit clash
  - 验证：双方 attack 窗口重叠帧内命中 → 断言双方 stance 各扣 CLASH_STANCE_COST、clash 事件恰好一次（§7 实验 2）
- [x] **AC3: 架势崩解** — 敌人 stance ≤ 0 → 消费 #575 stance_broken → 转发 emit stance_broken
  - 验证：敌人 stance 打到 0 → 断言 stance_broken 事件恰好一次（转发幂等，#575 侧已断言）
- [x] **AC4: 数值全部来自 constants.gd** — 判定不出现任何字面量；PARRY_WINDOW/PARRY_STANCE_DAMAGE/CLASH_STANCE_COST/CLASH_PRIORITY 全部引用 WolfConstants
  - 验证：code review + 单测对常量变更敏感（改常量 → 判定结果随动）
- [x] **AC5: 三条判定路径单测** — 弹反成功/拼刀/未弹反受击
  - 验证：test_combat_judge.gd 三组用例（§7 实验 1/2 落地）+ run_tests.gd 全绿

### 5.2 边界条件

1. **弹反窗口边界** — guard_pressed 恰在窗口边界（press_ms == hit_ms 或 == hit_ms - window）→ 视为窗口内（闭区间）；窗口外 1ms → 不弹反（AC1 需边界用例）
2. **拼刀 vs 弹反同帧** — 玩家攻击窗口与敌人攻击窗口重叠，且玩家 guard_pressed 也在弹反窗口 → 弹反优先（CLASH_PRIORITY，§4.4 方案 A）；测试断言 parry_success 而非 clash
3. **弹反与格挡同键** — guard_pressed 触发弹反判定后，若失败且 guard_held 持续 → 转格挡裁决（block_held），不重复受击；同一次敌人命中只裁决一次（防双罚）
4. **无敌期** — 玩家 revive 无敌（INVINCIBLE_SECONDS）内敌人命中 → 判定器 no-op（不发射 hit_landed；#575 take_damage 本身也 no-op，双保险）
5. **dead/execute 受击** — defender 处于 dead/revive/execute → 判定器跳过该实体（#575 侧 no-op 兜底）
6. **stance 溢出单次** — 敌人 stance=5 时弹反 PARRY_STANCE_DAMAGE=25 → #575 take_stance_damage clamp + 单次 break_stance + 单次 stance_broken 转发（不双发）
7. **多敌（未来）** — 多敌人窗口同时命中玩家 → 每对 (attacker, defender) 独立裁决，裁决结果按事件顺序发射（#581 多敌场景预留；MVP 单敌）
8. **距离挥空** — 玩家攻击窗口有效但距离超 HITBOX_RANGE 或 facing 相反 → 不命中（hit_landed 不发射）
9. **facing 翻转** — 攻击窗口登记时攻击方向快照；命中瞬间 defender facing 已翻转 → 按命中瞬间 facing 裁决（弹反方向判定）
10. **双攻击窗口** — 同实体连续攻击（attack→attack 连段）→ 旧窗口作废新窗口生效（#575 restart 钩子语义对齐）

### 5.3 失败路径

1. **未注册攻击窗口收到命中** — 敌人 hit 帧到达但无对应 AttackWindow 登记（#581 未实现时单测驱动）→ 判定器 no-op + push_warning（不凭空判定）
2. **guard_pressed 无敌人攻击** — 玩家按下格挡但无敌人攻击 → 无裁决（guard 状态由 #575 输入桥管理，判定器不干预）
3. **判定器未 bind 实体** — 单测忘 bind → resolve 调用 no-op + push_warning（防 NPE）
4. **事件重复发射** — 同一命中触发两次 resolve → 判定器保证每次命中恰好一次裁决（内部 consumed 标记，§7 实验 3 断言）
5. **数值异常** — PARRY_WINDOW 为 0/负 → 常量防御（#584 面板候选集约束 + push_warning）

---

## 6. 依赖与阻塞

### 6.1 依赖链

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #575（实体/状态机） | ✅ merged #618 | 无 | take_damage/take_stance_damage/stance_broken 信号/guard→parry_success 转移——本层唯一消费面 |
| #573（输入） | ✅ merged #611 | 无 | guard_pressed(timestamp_ms)/guard_held——弹反/格挡判定输入 |
| #584（数值 DRAFT） | ✅ merged #609 | 无 | PARRY_WINDOW_FRAMES/POSTURE_BLOCK_COST/POSTURE_HIT_COST/PARRY_COST 只读；本层新增判定常量标 # DRAFT |
| #574（动画） | ✅ merged #612 | 无 | consume_state 消费 parry_success/stagger 状态（经 #575 state_changed 间接） |
| 分解 id 8 / #579（反馈） | ⛔ 未开始 | 低 | 本层事件契约先行定义（§8.3），#579 实现时订阅即可，不阻塞 |
| 分解 id 5 / #581（敌AI） | ⛔ 未开始 | 中 | 本层定义 AttackWindow 契约（§8.3），#581 实现时注册；MVP 单测用模拟窗口驱动 |
| 分解 id 14 / #585（组装） | ⛔ 未开始 | 低 | CombatJudge 实例化 + wire 归 #585；本层 headless 独立可测 |

```
#572 ──► #573 ──► #575 ──► #577（本 issue：判定）──► #579 反馈
#572 ──► #584 ──┘        │                            ├──► #578 复活
                         └──► #585 组装 ──► #586 E2E   └──► #581 敌AI（AttackWindow 注册）
```

### 6.2 开源调研（issue body 要求「开源优先，成熟方案优先复用，找不到再自行实现，并在 PR 中说明调研结果」）

| 类别 | 候选 | 调研结论 |
|------|------|---------|
| Godot hitbox/hurtbox | cluttered-code/godot-health-hitbox-hurtbox（169⭐，2026-08-17 更新） | Area2D/Area3D 组件管理健康/伤害/治疗——**物理碰撞模式**：与 #574「零碰撞体、判定归 #577」架构裁决冲突；无时间窗（弹反）语义，仅空间命中。**不采用**（架构冲突 + 时间窗无法表达） |
| Godot hitbox 教学 | gdquest-demos/godot-4-hitbox-hurtbox（7⭐）/ godot-4-juicy-attack（7⭐） | GDQuest 官方教学 demo：Area2D hitbox/hurtbox + 打击反馈演示——同物理模式，且为教学演示非库。思路（hitbox/hurtbox 职责分离）可借鉴为「攻击窗口 vs 受击判定」概念，实现仍走逻辑帧窗口 |
| hitbox 编辑器 | coelhucas/hitbox-editor（56⭐） | 编辑器工具（编辑碰撞盒映射）——非运行时判定系统，与逻辑帧窗口无关 |
| Godot parry | parry-shmup（1⭐）/ parry-pong（1⭐）/ TurnBase-Parry-and-Dodge（1⭐）/ mecha-party-fighters（2⭐） | 全部 1-2⭐ 个人习作/课程演示，无成熟可复用弹反判定系统 |
| Godot sekiro 系 | Midlands-Besiege-Saga-Demo（0⭐）等 | 0⭐ 演示项目，无参考价值 |

**结论：** 无成熟可复用的「弹反/拼刀/架势判定」开源系统；hitbox 生态全部为 Area2D 物理模式，与本项目「逻辑帧窗口 + 零碰撞体」的既定架构（#574 注释 + #573 时间戳契约 + 只狼时间窗基准）冲突。**自研 CombatJudge 逻辑判定层**（issue body 允许「找不到再自行实现」）。implement PR 须引用本调研结论。

### 6.3 前置准备

- [ ] implement 前确认 origin/main 已含 #618（#575 实现）与 #609/#611/#612（本 PRD 侦查基准 1bdb6c7 已含）
- [ ] 本 PRD merge 后，plan agent 读 §8 交接上下文即可开工，无需重扫源码

---

## 7. Spike / 实验（depth/deep 必填，≥3 实验）

### 实验 1：弹反窗口时间戳对齐精度

- **要回答的问题**：guard_pressed 时间戳与敌人 hit 帧的时间窗对齐（PARRY_WINDOW_SECONDS=0.2s），闭区间边界（恰在窗口起止点）判定是否正确，1ms 偏差是否稳定？
- **方法**：headless 构造：敌人攻击窗口（hit 帧 T=0.5s）+ 玩家 guard_pressed 在 T-0.2s / T / T+0.001s / T-0.201s 四个时间点 → 断言弹反成功/成功/失败（窗口外）/失败
- **预期结果**：闭区间 [T-window, T] 内全部 parry_success；窗口外 1ms 即失败；事件恰好一次
- **对方案的影响**：若时间戳毫秒精度不够（帧内多次按下），需在 CombatJudge 内做帧级去抖（同帧多按取最后一次）；若边界语义与只狼手感不符（用户裁决），改 PARRY_WINDOW 候选值即可（§4.3 方案 A 数值解耦）

### 实验 2：拼刀 vs 弹反优先级冲突矩阵

- **要回答的问题**：同一帧内「玩家攻击窗口 + 敌人攻击窗口 + 玩家 guard_pressed 在弹反窗口」三者重叠时，裁决结果是否稳定为 parry_success（CLASH_PRIORITY=弹反优先）？双方攻击重叠但无 guard → clash？
- **方法**：枚举 4 种冲突组合（弹反+拼刀 / 拼刀+格挡 / 弹反+格挡 / 三重叠），headless 断言每种组合的裁决结果与事件
- **预期结果**：弹反优先短路；拼刀次之；格挡再次；受击兜底；每种组合恰好一个结果事件
- **对方案的影响**：若用户裁决「拼刀优先」（双刀互格=打铁更爽），仅改 CLASH_PRIORITY 常量 + 本矩阵断言翻转，架构不动（§4.4 方案 A 显式常量设计目的）

### 实验 3：结果事件契约与防重入

- **要回答的问题**：五个结果事件（parry_success/block_held/hit_landed/stance_broken/clash）的信号签名与 §8.3 契约逐字一致；同一命中是否恰好一次事件（防双罚）？
- **方法**：单测断言事件参数（伤害值/实体引用）与 §8.3 契约一致；连续 resolve 两次同一命中 → 第二次 no-op（consumed 标记）
- **预期结果**：事件签名契约稳定；重复 resolve 幂等
- **对方案的影响**：若 #579 需要额外参数（如碰撞点），在 §8.3 契约上追加而非改事件名；防重入失败则改内部 consumed 标记为「按 (attacker, defender, frame) 去重」

---

## 8. 交接上下文（plan agent 交接）

### 8.1 系统现状快照

- origin/main @ 1bdb6c7（#618/#619 已 merge）：CombatEntity（take_damage/take_stance_damage/break_stance/die/revive/request_transition + 6 信号）、CombatStateTable（11 态转移表，guard→parry_success 预留）、InputController（guard_pressed(timestamp_ms)/guard_held）、WolfConstants 全量 # DRAFT、StickFigureController.consume_state（11 态动画）、SwordArc（零碰撞体视觉层）、DebugCanvas（#584 调参面板）
- 判定层（本 issue）**零存在**：无 CombatJudge、无 AttackWindow、无结果事件发射器

### 8.2 交付物清单（按实现顺序）

| 顺序 | 文件 | 内容 |
|:----:|------|------|
| 1 | `constants.gd`（修改） | 追加判定分区 # DRAFT 常量：PARRY_STANCE_DAMAGE（只狼基准弹反大幅涨敌架势 → 候选 [20,25,30]，AC1 ≥20）/ CLASH_STANCE_COST（候选 [8,10,12]）/ CLASH_PRIORITY（0=弹反优先 1=拼刀优先，默认 0）/ HITBOX_ACTIVE_FRAMES（候选 [4,6,8]，默认 4=#574 挥刀暴发帧）/ HITBOX_RANGE（候选 [60,80,100]px）/ PARRY_DIRECTION_TOLERANCE（默认 1=仅同侧）——全部「只狼基准 → 候选 + 影响 + 情感断言」注释，定稿归 #584 |
| 2 | `combat_attack_window.gd`（新增） | AttackWindow 描述器（RefCounted）：attacker / start_frame / active_frames / hp_damage / stance_damage / direction；`is_active(frame)` 查询；#581 敌AI 与玩家攻击共用 |
| 3 | `combat_judge.gd`（新增） | `class_name CombatJudge extends Node`：bind_entities(player, enemy) / bind_input(ic) / register_attack_window(window) / resolve_attack(attacker, defender)（优先级 弹反→拼刀→格挡→受击）/ _on_entity_state_changed / _on_guard_pressed / _on_guard_held / _on_stance_broken 转发；五结果事件信号；consumed 防重入 |
| 4 | `test_combat_judge.gd`（新增） | 三条判定路径（AC5）+ 弹反窗口边界（实验 1）+ 冲突矩阵（实验 2）+ 事件契约/防重入（实验 3）+ 边界/失败路径（§5.2/§5.3） |
| 5 | `run_tests.gd`（修改） | 注册 test_combat_judge.gd |

### 8.3 接口契约（下游系统的消费面）

```gdscript
## CombatJudge（class_name，extends Node）——判定层唯一裁决入口
var player: CombatEntity          # bind_entities 注入
var enemy: CombatEntity           # bind_entities 注入

func bind_entities(p: CombatEntity, e: CombatEntity) -> void
func bind_input(ic: Object) -> void                        # #573 InputController
func register_attack_window(w: AttackWindow) -> void       # #581 敌AI / 玩家攻击登记
func resolve_attack(attacker: CombatEntity, defender: CombatEntity) -> void  # 幂等（防重入）

## 结果事件（#579 反馈 / #574 动画 / #593 音效 统一订阅面；事件名与 issue body 逐字对齐）
signal parry_success(defender: CombatEntity, attacker: CombatEntity, stance_damage: float)
signal block_held(defender: CombatEntity, attacker: CombatEntity, stance_cost: float)
signal hit_landed(defender: CombatEntity, attacker: CombatEntity, hp_damage: float, stance_damage: float)
signal clash(entity_a: CombatEntity, entity_b: CombatEntity, stance_cost: float)
signal stance_broken(entity: CombatEntity)                 # 转发 #575 信号（统一事件出口）

## AttackWindow（RefCounted，#581 敌AI 注册契约）
class AttackWindow:
    var attacker: CombatEntity
    var start_frame: int           # 攻击开始帧（#575 进入 attack 状态帧）
    var active_frames: int         # 判定有效帧数（HITBOX_ACTIVE_FRAMES # DRAFT）
    var hp_damage: float           # 命中 HP 伤害（敌人用 SWORD_DAMAGE_* 或 AI 配置）
    var stance_damage: float       # 命中架势伤害（POSTURE_HIT_COST # DRAFT）
    var direction: int             # 攻击方向（-1/1，命中瞬间 facing 校验用）
    func is_active(frame: int) -> bool
```

### 8.4 主要风险与裁决点

1. **CLASH_PRIORITY 定稿**（弹反优先 vs 拼刀优先）：本 PRD 推荐弹反优先（只狼铁律）；用户可改常量 + 冲突矩阵断言翻转——实现期**不得**写死裁决顺序，必须走 CLASH_PRIORITY 常量（#584 调参面板可调）
2. **#581 敌AI 未实现**：MVP 判定用测试构造的 AttackWindow 驱动；#581 实现时按 §8.3 契约注册即可，CombatJudge 无需改动——敌 AI 攻击前摇（ENEMY_ATTACK_WINDUP=15 帧）期间注册窗口
3. **弹反窗口边界语义**（闭区间含端点）：若用户实机裁决「窗口外 1ms 也应成功」（宽容手感），改 PARRY_WINDOW 候选值（8/14 两极），判定逻辑不动（实验 1 结论）
4. **事件消费方时序**：#579/#593 未实现期间，事件无人订阅是安全的（Godot 信号无订阅不报错）；#585 组装时 wire 全部消费方
5. **GDD 落盘**：post-merge agent 新增 `docs/GAME_DESIGN/shandong-wolf/07-COMBAT-JUDGE.md`（判定优先级 + 事件契约 + AttackWindow）

### 8.5 红线（implement agent 禁止）

- ❌ 不引入 Area2D/CollisionShape2D 物理碰撞（#574 零碰撞体架构裁决；§4.2 调研结论）
- ❌ 不修改 #575 已合并的 combat_entity.gd / combat_state_table.gd 接口（只消费信号与调用接口；guard→parry_success 入口原样使用）
- ❌ 不裁决 # DRAFT 数值（只读 constants；新常量也标 # DRAFT 候选集）
- ❌ 不改结果事件名（parry_success/block_held/hit_landed/stance_broken/clash 与 issue body 逐字对齐）
- ❌ 不写死裁决优先级（必须走 CLASH_PRIORITY 常量）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不修改 scenes/Main.tscn（标题场景红线）

# PRD #682 — [Feature] 敌人 AI：只狼式精英怪 Boss（攻击/弹反/架势交互）

> **Issue:** #682
> **标签:** workflow/research, priority/high, feature, gameplay, version/mvp（issue 无 `depth/*` 标签，参照 #581 先例取 `depth: standard` → §1–6 + §8 必填；§7 可选，本 PRD 含 2 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-21
> **所有权:** `content_ownership: mechanical`（AI 行为/HP 双轨/击退/架势恢复=机械工程；手感数值全部 # DRAFT 只读，定稿归 #584）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + `default_branch: main` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`：wiki grep 只狼/精英/Boss → `wiki/游戏设计理念.md`（只狼=「机制作为修辞」，战斗机制隐喻角色成长）、`wiki/JRPG战斗系统演变.md`（Boss 战戏剧性/难度=机制理解/模块化难度）；raw grep 敌人/AI → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（阶段 4 混合探索期「条件→行动」FSM 决策范式、难度自适应「AI 辅助强←→中←→无」）、`raw/Bear/state machine.md`（状态机记录范式））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`：敌人=『压迫感』来源、MVP 策略「手感验证优先，内容/Boss 后置」、精英=军曹后置 #589）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：敌小兵 HP 30-50/架势 40-60、精英架势 120-160、架势回复=脱战 1.5s 后 20-35/s、处决是奖励不是补刀、受击双重惩罚、危攻击前摇 14-18 帧）+ 同链 PRD/DESIGN（#575/#576/#577/#580/#581/#584/#585 全读）+ origin/main 源码实测（c22025d，17 组件接口逐一核对）
> **来源:** 用户实机试玩反馈（2026-08-21）：敌人一击毙命 + 无 AI 无法测试战斗。非 backlog 分解（`docs/RAW/game-to-issues-shandong-wolf.json` 无此条——#682 是用户直建 issue，位于分解 id 18/#589 军曹、id 19/#590 汉奸 Boss 之前）
> **前置依赖:** #575（CLOSED）、#577（CLOSED）、#580（CLOSED）、#581（CLOSED，PR #638 merged）、#585（CLOSED，PR #666 merged）、#576/#584（草稿已 merge，`status/human-review` 等用户定稿——v4 规则：human Issue 不进依赖链，视为已满足）——全部满足

---

## 1. 问题定义

### 1.1 现状（2026-08-21 worktree 侦查 @ origin/main c22025d）

**一句话现状：** MVP 战斗闭环已可玩（#585/#666），敌人「能动、能打、能被打、能崩解」，但**血量形同虚设（无 UI、装配不消费、被架势快线绕过）、攻击组缺「蓄力攻击」、受击缺「后退」、架势无脱战恢复**——敌人是「会动的小兵靶子」，不是「只狼式精英 Boss」。用户 8-21 实机反馈「敌人一击毙命 + 无 AI 无法测试战斗」即源于此。

| 组件（文件） | Issue | 当前状态 | 与 #682 的差距 |
|------|-------|:-------:|------|
| `gdscripts/enemy_ai.gd`（177 行） | #581/#638 | ✅ 行为 FSM（patrol/chase/attack/retreat）+ 120° 视线 6m 感知 + 弹反抑制窗（0.5s）+ 决策门控 + `decide(delta)` headless 可测 | ⚠️ 精英化需：新出招（蓄力重斩）、受击击退、攻击欲望参数化——行为框架本身**不重写** |
| `gdscripts/enemy_ai_states.gd`（223 行） | #581/#638 | ✅ PatrolState/ChaseState/AttackState/RetreatState；AttackState 出招二选一（突刺 heavy_attack 30% / 三连砍 attack×3）；冷却 1.5s | ⚠️ 出招决策扩为三选一（+蓄力重斩）；Chase/Attack 接击退位移 |
| `gdscripts/combat_entity.gd`（252 行） | #575/#618 | ✅ hp_1/life_1_max（默认 100）/hp_2/stance/stance_max 数据模型 + take_damage/take_stance_damage/break_stance/die + 6 信号 + 敌人变体参数（is_player=false, life_total=1） | ⚠️ **HP 慢线数据模型存在但从未被真正消费**；❌ 无架势脱战恢复（仅 #580 recover_from_break 50%+5s 疲惫） |
| `gdscripts/main_battle.gd`（#585 装配） | #585/#666 | ✅ 敌人装配 `CombatEntityScript.new({"is_player": false, "life_total": 1})` → life_1_max 走默认 100 | ⚠️ **未消费 `ENEMY_HP_MAX=40` 常量**（constants 已定义、装配不读）——HP 慢线断点之一 |
| `gdscripts/combat_judge.gd` | #577/#626 | ✅ 玩家攻击对敌人 hp(12)+架势(35) 双伤害；弹反 25 架势；窗口自动登记 + windup 参数化 | ✅ 无缺口（判定层已是双轨伤害，本 PRD 只读消费） |
| `gdscripts/hud.gd`（410 行） | #576 | ✅ EnemyStanceBar 顶部中央（240×6，set_target_enemy 注入显示）+ 处决/击杀提示 | ❌ **无敌人 HP 条**——「血条不可见」= 用户「无血量概念」感知的直接来源 |
| `gdscripts/execution_orchestrator.gd` | #580/#660 | ✅ stance_broken → armed 3s 窗口 → attack_pressed+距离校验 → execute+execute_kill（999 一击）+ 淡出 | ✅ 无缺口（处决窗口完整，本 PRD 只确认衔接） |
| 攻击组 | #581/#584 | ✅ 三连砍（attack）+ 突刺（heavy_attack，前摇 12 帧=ENEMY_ATTACK_WINDUP，可弹反） | ❌ **「蓄力攻击」专属形态缺失**（长前摇+高伤害+可弹反的重击，issue 明示） |
| 受击反馈 | #575/#579 | ✅ stagger 12 帧硬直 + #579 火花/hit-stop/屏震 | ❌ **受击后退（击退位移）缺失**（issue「僵直/后退」后半） |
| 架势恢复 | — | ❌ 无脱战恢复；崩解后仅 recover_from_break（50% 架势 + 5s 疲惫） | ❌ **「架势脱战恢复（不无限崩解）」缺失**（issue 补充 AC） |
| 主动索敌/持续进攻 | #581 | ✅ chase 逼近 + 停距 + 冷却 1.5s；玩家站桩时敌人持续进攻（issue AC4 已满足） | ✅ 无缺口（维持 + 数值候选） |

**核心缺口（本 PRD 的增量工作，共 5 项）：**
1. **HP 慢线虚设**：数据模型在（life_1_max）、伤害路径在（12/刀）、但装配不消费 ENEMY_HP_MAX、无 HP UI、且实际击杀恒走「3 刀架势崩解（35×3=105>100）→ 处决一击（999）」——HP 100 形同虚设，用户感知「一击毙命/无血量概念」。**双轨击杀（削血慢线 / 架势快线）未成立。**
2. **敌人血条 UI 缺失**：只有 EnemyStanceBar（顶部中央细条），无 HP 条。issue 补充 AC 要求「顶部 Boss 条或扩展 EnemyStanceBar 为血条+架势条组合」。
3. **蓄力攻击缺失**：攻击组只有三连砍+突刺，无「可弹反的蓄力攻击」（长前摇、高伤害、前摇可读）。
4. **受击后退缺失**：受击只有 12 帧硬直，无击退位移。
5. **架势无脱战恢复**：不被打就一直满架（崩解后 50% 恢复但无持续回复），「不无限崩解」的节奏阀缺失。

### 1.2 验收条件（issue body 5 条 + 补充 4 条 → 本 PRD 保障）

| # | 验收条件 | 现状 | 本 PRD 保障 |
|---|---------|:----:|------------|
| AC1 | 敌人会主动接近并攻击玩家（无需玩家贴脸） | ✅ 已满足（#581 chase+attack） | §5.1 AC1：维持 + 精英参数化（追击速度/冷却候选） |
| AC2 | 敌人攻击可被弹反，弹反后敌人硬直 | ✅ 已满足（#577 闭区间 + #581 抑制窗 0.5s） | §5.1 AC2：维持；蓄力攻击同样可弹反（窗口 windup 参数化） |
| AC3 | 敌人架势条崩解后可处决 | ✅ 已满足（#580 处决窗口 3s） | §5.1 AC3：维持 + 确认衔接（不重做） |
| AC4 | 玩家不操作时敌人会持续进攻（可观察 AI 行为） | ✅ 已满足（#581 冷却 1.5s 循环进攻） | §5.1 AC4：维持 |
| AC5（补充） | 敌人有血条，普通攻击需多次才能击杀（非一击毙命） | ❌ 装配不消费 HP 常量 + 架势快线绕过 | §5.1 AC5：装配消费 ENEMY_HP_MAX（精英候选值）+ HP 归零=普通死亡（非处决）——慢线成立 |
| AC6（补充） | 敌人血条/架势条 UI 可见（顶部 Boss 条或现有 HUD 位置扩展） | ❌ 无 HP 条 | §5.1 AC6：EnemyHealthBar（顶部中央，EnemyStanceBar 上方）→ 血条+架势条组合 |
| AC7（补充） | 架势崩解后进入处决窗口（与 #580 衔接） | ✅ 已满足 | §5.1 AC7：维持（stance_broken → armed 窗口） |
| AC8（补充） | 架势脱战恢复（不无限崩解） | ❌ 无 | §5.1 AC8：脱战延迟 + 每秒恢复（sekiro 基准） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 精英遭遇战（MVP 压迫感升级） | 每次游玩 | 雪夜村口：精英敌人巡逻 → 发现玩家 → 追击 → 三连砍/突刺/蓄力重斩（前摇「舞刀」可读）轮换 → 玩家弹反成功 → 敌人硬直 + 架势上涨 → 4 次弹反崩解 → 处决窗口 → 处决一击（快线）；或玩家削血 5-7 刀磨死（慢线）——两条胜利路径并存 |
| B | Boss 条读图（信息层） | 每次游玩 | 顶部中央：敌人血条（暗红粗条）+ 架势条（细条）双条可见；受击/弹反时血条、架势条实时变化；崩解 → 架势条清零 + 「处决」提示 |
| C | 开发者 headless 验证 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`：断言敌人装配 life_1_max=ENEMY_HP_MAX、多次攻击才击杀（非一击）、蓄力攻击窗口前摇更长且可弹反、受击后退位移、脱战架势恢复 |

### 1.4 范围边界（Patch 14 去冲突）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #581 小兵 AI（CLOSED，#638 merged） | 行为 FSM 四态 + 感知 + 弹反抑制窗 | ❌ 不重写行为状态机；只做**精英参数变体 + 出招增量 + 击退接线**（additive） |
| #576 HUD（草稿 merged，human-review） | EnemyStanceBar + 玩家血条 + 提示 | ❌ 不改玩家区块与既有条；只**新增 EnemyHealthBar**（additive，血条+架势条组合） |
| #580 处决（CLOSED，#660 merged） | stance_broken → 处决演出/杀敌/淡出 | ❌ 不动编排器/处决态；只确认「崩解 → 处决窗口」衔接（issue AC7） |
| #584 数值 DRAFT（草稿 merged，human-review） | 全量 # DRAFT 数值 + 调参面板 | ❌ 不裁决数值；精英新常量全部标 # DRAFT + 候选集只读引用 |
| #585 组装（CLOSED，#666 merged） | main_battle.gd 玩家/敌人/判定/HUD/处决装配 | ⚠️ 唯一触碰点：敌人装配显式消费 ENEMY_HP_MAX（一行参数注入），其余装配不动 |
| #589 精英敌人·军曹（backlog OPEN，dept #581/#585） | 具体内容精英：刺刀/危攻击（不可弹反突刺）/横扫/180 架势/霸体/1.3x 体型/掉落 | ❌ 不实现军曹特有内容；#682 交付**通用精英模板**（行为/双轨/UI/恢复），#589 在其上叠加内容 |
| #590 汉奸 Boss（backlog OPEN，dept #580/#585/#589） | 两阶段 Boss 战/台词/最终处决特写 | ❌ 不实现 Boss 战；不触碰二阶段/演出 |
| #579 打击反馈（CLOSED，#654 merged） | 火花/hit-stop/屏震/慢动作/白闪 | ❌ 不改反馈矩阵；受击后退是**位移层**（EnemyAI），与反馈渲染正交 |

**红线（继承 + 新增）：**
- ❌ 不改 11 态 `CANONICAL_STATES` / `consume_state` 契约（#575 状态名权威集；精英行为仍是 AI 行为态，不进战斗状态表）
- ❌ 不改 #577 五结果事件名与裁决顺序；不引入 Area2D/CollisionShape2D 物理碰撞
- ❌ 不裁决 # DRAFT 数值（只读 constants；精英新常量标 # DRAFT + 候选集，定稿归 #584）
- ❌ 不修改既有接口签名（entity/judge/AttackWindow 全部 additive 扩展，现有测试必须全绿）
- ❌ 不做场景组装与渲染（敌人视觉复用 SW-003，AI 层零渲染代码）
- ❌ 不修改 mini-pong/ 任何文件；不修改 scenes/Main.tscn
- ❌ 不提前实现 #589/#590 的军曹/Boss 内容（体型/危攻击/二阶段/掉落/台词/演出）

---

## 2. 设计意图

### 2.1 为什么现在做

1. **用户实机试玩反馈（2026-08-21）直接点名**：「敌人目前一击毙命（无血量概念）+ 无 AI 无法测试战斗」——#585 组装后的 MVP 已可玩，但敌人是「3 刀崩解 → 处决一击」的固定剧本，HP 慢线不存在、精英感不存在。这是 MVP 战斗闭环（手感验证）的**最后一块体验短板**。
2. **依赖链全部解锁**：#575/#577/#580/#581/#585 全 CLOSED，#576/#584 草稿已 merge——行为层、判定层、处决层、装配层原料齐备，本 issue 只做**增量**（HP 装配消费 + UI 扩展 + 出招/击退/恢复），无任何前置阻塞。
3. **为 #589/#590 铺路**：brief 明确「手感验证优先，内容/Boss 后置」。本 issue 交付**通用精英模板**（精英 AI 行为 + HP/架势双轨 + Boss 条 UI + 脱战恢复），#589 军曹/#590 汉奸在其上叠加内容（武器/危攻击/二阶段/演出）即可，避免内容 issue 各自重复实现通用框架。
4. **只狼/审美坐标对齐（sekiro-tuning-reference + brief）**：精英 = 「压迫感来自节奏变化与机制理解，不是加血」；双轨击杀 = 只狼铁律 5「处决是奖励不是补刀」；架势脱战恢复 = 铁律 4「回复太快=无脑弹反，太慢=龟缩」；蓄力攻击前摇可读 = 只狼「危」攻击的可读性哲学（本作保持可弹反，差异记录 #584）。

### 2.2 为什么是本层（历史成因）

| 约束 | 来源 | 详情 |
|------|------|------|
| 敌人差异走参数 | #575 交付契约 | 敌我差异走 @export 参数（is_player/life_total/life_1_max/stance_max）——精英 = 新参数组合（life_1_max=ENEMY_HP_MAX 精英值、stance_max 候选上调），不复制数据模型 |
| 攻击窗口共用契约 | #577 §8.3 + #581 落地 | AttackWindow.windup_frames 已参数化（#581）——蓄力攻击 = 更长 windup 的同一窗口契约，判定零改动 |
| 行为层与战斗层解耦 | #581 DESIGN | EnemyAI 独立行为 FSM + 决策门控——精英出招/击退全在行为层，11 态战斗状态一字不改 |
| 判定/演出分层 | issue body + brief | 受击后退是位移层（EnemyAI._apply_movement），与 #579 反馈渲染（火花/屏震）正交不冲突 |
| HUD 布局先例 | #576 PRD §4.2 | 敌人架势条 = 顶部中央细条（set_target_enemy 注入）——血条 = 同锚点上方粗条，组合成「Boss 条」 |
| 数值归属 | #584 契约 | 全部新数值 # DRAFT 只读 + 候选集，定稿归 #584 调参面板 |

### 2.3 本层设计意图

1. **精英 = 小兵 AI 的参数变体 + 行为增量，绝不重写**：#581 的四态行为 FSM（patrol/chase/attack/retreat）与判定/处决契约是通用基底，精英化只做三处增量——AttackState 出招三选一（+蓄力重斩）、受击击退接线、攻击节奏参数化。**「精英」不是新类，是 EnemyAI 的一个参数档位**（@export elite_mode 或装配时注入精英常量组）。
2. **双轨击杀成立（HP 慢线 / 架势快线）**：慢线 = 削血至 0 → 普通死亡（die() 终态，击杀提示已有 #576）；快线 = 架势崩解 → 处决窗口（#580）→ 处决一击。两条路都能赢，数值上「弹反高手 4 弹反速杀（快线）< 稳健玩家 5-7 刀磨死（慢线）」——只狼式「快线奖励技术」。
3. **Boss 条 = EnemyStanceBar 扩展组合**：顶部中央新增 EnemyHealthBar（暗红粗条，宽同 240px、高 10px 与玩家血条同规格），EnemyStanceBar 下移/保持其下——血条+架势条垂直组合，信息归属清晰（都是「当前敌人」），不遮挡读图（#576 §4.2 布局先例延续）。
4. **蓄力攻击 = 长前摇可弹反重击**：新出招「蓄力重斩」——前摇 ENEMY_CHARGE_WINDUP（候选 [18, 20, 24] 帧，sekiro 危攻击 14-18 帧基准但本作保持可弹反）、伤害 ENEMY_CHARGE_HP_DAMAGE（候选 [20, 25, 30]）、概率 ENEMY_CHARGE_CHANCE（候选 [0.15, 0.2, 0.25]）；窗口经 AttackWindow.windup_frames 注入（#581 既有字段），弹反闭区间判定零改动（#577 逻辑）。
5. **架势脱战恢复 = 节奏阀**：敌人受击/受弹反后 ENEMY_STANCE_RECOVER_DELAY_SEC（候选 [2.0, 2.5, 3.0]s，sekiro 停防 1.5s 基准放宽）内无架势伤害 → 以 ENEMY_STANCE_RECOVER_PER_SEC（候选 [15, 20, 25]/s，sekiro 20-35 基准）恢复至 stance_max。**只对敌人启用**（玩家架势语义另议，不改玩家体验）。
6. **受击后退 = 位移层击退**：敌人受击（hit_landed，defender=敌人）→ EnemyAI 施加 ENEMY_KNOCKBACK_PX（候选 [30, 40, 60]px）沿受击反向线性衰减位移（stagger 态期间执行），与 12 帧硬直叠加成「僵直+后退」完整反馈。

---

## 3. 影响分析

### 3.1 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/main_battle.gd` | 敌人装配（#585） | **修改（一行参数）**：`CombatEntityScript.new({"is_player": false, "life_total": 1, "life_1_max": C.ENEMY_HP_MAX})`——装配显式消费 ENEMY_HP_MAX（当前 40，精英候选上调见 §8.4-1），HP 慢线接通 |
| `shandong-wolf/gdscripts/hud.gd` | HUD（#576） | **修改（additive）**：新增 `EnemyHealthBar`（顶部中央，EnemyStanceBar 上方，宽 240px 高 10px，暗红）；`set_target_enemy` 订阅 hp_changed；显隐与 EnemyStanceBar 联动（died 隐藏）；`_HudBar` 复用（分段条组件） |
| `shandong-wolf/gdscripts/constants.gd` | 数值（#584 契约） | **修改**：精英 AI 分区 # DRAFT 新常量（§8.2 清单：蓄力攻击 windup/伤害/概率、受击击退、架势脱战恢复延迟/速率、精英 HP/架势候选） |
| `shandong-wolf/gdscripts/enemy_ai_states.gd` | 行为状态（#581） | **修改（additive）**：AttackState 出招决策二选一 → 三选一（突刺/三连/蓄力重斩，蓄力 = heavy_attack + windup 注入）；ChaseState/AttackState 不被击退打断（击退期间决策门控自然生效） |
| `shandong-wolf/gdscripts/enemy_ai.gd` | 行为驱动（#581） | **修改（additive）**：受击击退——订阅 entity hit 路径（judge.hit_landed 或 entity 受击信号），stagger 态期间 `_move_intent` 追加击退分量；`_apply_movement` 消费 |
| `shandong-wolf/gdscripts/combat_entity.gd` | 战斗数据（#575） | **修改（additive）**：敌人架势脱战恢复——`_process` 轮询（is_player=false 且未崩解且延迟窗口已过 → stance += PER_SEC*delta，上限 stance_max，发射 stance_changed）；`take_stance_damage` 重置延迟计时 |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | 窗口（#577/#581） | **修改（additive，可选）**：若蓄力重斩需独立于 heavy_attack 的更前摇，windup_frames 已支持（#581 交付）；如需按出招区分，加 `windup_override` 注入点——优先复用现有字段，避免新字段 |
| `shandong-wolf/tests/test_enemy_ai.gd` | 测试 | **修改**：蓄力攻击出招概率/前摇断言、击退位移断言、脱战恢复断言 |
| `shandong-wolf/tests/test_hud.gd` | 测试 | **修改**：敌人血条信号驱动断言（hp_changed → 条比例/显隐） |
| `shandong-wolf/tests/test_combat_entity.gd` | 测试 | **修改**：架势脱战恢复用例（延迟/速率/上限/崩解中不恢复） |
| `shandong-wolf/tests/test_main_assembly.gd` | 测试 | **修改（可选）**：装配断言——敌人 life_1_max == ENEMY_HP_MAX |

### 3.2 间接受影响的模块（下游消费者，本次不改）

| 文件/系统 | 影响 | 消费方式 |
|-----------|------|---------|
| #589 军曹（backlog） | 精英模板基底 | 复用 EnemyAI 精英参数档位 + Boss 条 UI，叠加武器/危攻击/霸体 |
| #590 汉奸 Boss（backlog） | 双轨击杀 + Boss 条 | 复用双轨/UI，叠加二阶段/演出 |
| #584 调参面板（human-review） | 精英新常量入表 | 候选值列表移交 #584 定稿 |
| #579 反馈（CLOSED） | 蓄力攻击命中反馈 | 复用既有 hit_landed/parry_success 事件分级（不需新事件） |

### 3.3 数据流

```
玩家攻击（#573 输入）
    │
    ▼
玩家 CombatEntity.state_changed → "attack" ──► EnemyAI.AttackState 出招三选一（掷骰）
    │                                        ├── 突刺 heavy_attack（30%）
    │                                        ├── 三连砍 attack×3（余下概率内）
    │                                        └── 蓄力重斩 heavy_attack + windup=ENEMY_CHARGE_WINDUP（新）
    ▼
敌人 CombatEntity（11 态战斗 FSM，不改）
    ├── request_transition("attack"/"heavy_attack")
    │        └── state_changed ──► CombatJudge 自动登记 AttackWindow（windup 实体参数）──► 弹反闭区间（#577）
    │                 ├── 弹反成功 ──► 敌人 take_stance_damage(25) + parry_success + 抑制窗 0.5s（#581 既有）
    │                 └── 受击 ──► 敌人 take_damage(12)+take_stance_damage(35) + hit_landed
    │                         ├── take_damage → stagger 12 帧 + EnemyAI 击退位移（新：ENEMY_KNOCKBACK_PX）
    │                         └── stance ≤ 0 → break_stance → stance_break 3s ──► #580 处决窗口（快线）
    └── take_damage 累计 → hp ≤ 0 → die() 普通死亡（慢线，击杀提示 #576 既有）
    └── 脱战恢复（新）：无架势伤害 ≥ ENEMY_STANCE_RECOVER_DELAY_SEC → stance += PER_SEC*delta（上限 stance_max）
HUD（#576 + 新 EnemyHealthBar）
    ├── EnemyStanceBar ← stance_changed（既有）
    └── EnemyHealthBar ← hp_changed（新：顶部中央暗红条 + 架势条组合）
```

### 3.4 需要更新的文档

- [ ] `docs/GAME_DESIGN/shandong-wolf/` — post-merge agent：新增/更新 敌人 AI 章节（精英参数档位 + 蓄力攻击 + 击退 + 脱战恢复）与 HUD 章节（Boss 条组合）
- [ ] `docs/PROJECT.md` — 若涉及系统清单变更（post-merge agent 处理）

---

## 4. 方案对比

### 4.1 方案 A：升级现有 EnemyAI（精英参数变体 + 行为增量 + 数据/UI additive 补丁）（推荐）

**描述：** 不新建类。EnemyAI 增加精英参数档位（@export 或装配注入精英常量组），AttackState 出招扩为三选一（+蓄力重斩），EnemyAI 订阅受击施加击退；main_battle.gd 一行参数消费 ENEMY_HP_MAX；hud.gd 新增 EnemyHealthBar（additive）；CombatEntity 增加敌人架势脱战恢复（additive，仅 is_player=false）。全部改动 additive，现有 19 个测试文件全绿基线不破坏。

| 维度 | 内容 |
|------|------|
| 精英化方式 | 参数档位：装配时注入 elite 常量组（HP/架势/前摇/伤害/概率/冷却），EnemyAI 行为零分支或极少分支 |
| 出招扩展 | AttackState 掷骰三选一；蓄力重斩 = heavy_attack + windup 注入（复用 #581 字段） |
| HP 慢线 | main_battle.gd 消费 ENEMY_HP_MAX + hud EnemyHealthBar；hp 归零 → die() 普通死亡 |
| 击退 | EnemyAI 订阅受击 → _move_intent 击退分量（stagger 期间） |
| 架势恢复 | CombatEntity._process 轮询（敌人专用）+ take_stance_damage 重置延迟 |
| 测试性 | 全部 headless 可测（decide 手动驱动 + 信号断言） |

**Pros：** 与「敌人差异走参数」（#575 契约）逐字对齐；行为/判定/处决/反馈契约零破坏（additive 全绿）；工作量最小（约 2-2.5 天）；#589/#590 直接复用精英档位，无迁移成本；数值全走 constants # DRAFT。
**Cons：** EnemyAI 单类承载小兵+精英两档参数，需纪律维护（参数组集中 constants，防散落）；击退与 Chase 位移叠加需防「击退后被拉回」抖动（衰减处理）。
**Risk：** Low（全部 additive；既有 25 条判定测试 + 19 测试文件回归基线）。
**Effort：** 2-2.5 天（HP 装配+UI 0.5 天 + 蓄力/击退/恢复 1-1.5 天 + 测试 0.5 天）。

### 4.2 方案 B：新建独立 EliteBossAI 类（平行实现，双 AI 并存）

**描述：** 新建 `elite_boss_ai.gd`（extends CharacterBody2D，独立行为 FSM），小兵 EnemyAI 与精英 AI 双类并存，装配按敌人类型实例化。

**Pros：** 小兵/精英代码物理隔离，互不干扰；精英专属行为（未来 #589 霸体/危攻击）有独立生长空间。
**Cons：** 与「敌人差异走参数」（#575 明言）契约冲突——敌人变体参数化是既定架构，双类 = 复制 177+223 行行为框架；感知/决策门控/抑制窗/击退逻辑双份维护；#589/#590 还要再选边（或三份）；MVP 单敌人战场下双类无收益。
**Risk：** Medium（架构偏离 + 双份维护成本 + 测试双份）。
**Effort：** 3.5-4 天（新类 + 双份测试）。
**结论：** 否——违反 #575 参数化契约，MVP 过度设计。

### 4.3 方案 C：提前实现 #589 军曹内容（内容驱动精英化）

**描述：** 跳过通用模板，直接把 #589 军曹（刺刀/危攻击/霸体/180 架势/1.3x 体型/掉落）作为「精英 Boss」实现，一 issue 两吃。

**Pros：** 一步到位交付具体精英内容；用户可立即对战「军曹」。
**Cons：** **严重越权**——#589 是独立 backlog issue（deps #581/#585，label workflow/backlog 未 promote），本 issue 吃掉其内容 = 双 issue 重复/冲突；#682 issue body 未要求军曹内容（只要求「类似只狼精英怪 Boss 的 AI」= 通用行为）；危攻击（不可弹反）与 issue「可弹反的蓄力攻击」直接矛盾；掉落/体型/霸体是 #589 专属范围。
**Risk：** High（issue 边界破坏 + 与 #589 内容重复）。
**Effort：** 4d（军曹全量内容）。
**结论：** 否——issue 边界红线否决；#589 后续在方案 A 的精英档位上叠加内容。

### 4.4 推荐

**方案 A。** 理由：
1. #575「差异通过参数配置」契约字面对齐——精英是小兵 AI 的参数档位，不是新类；
2. issue body 全部验收条件（含补充 4 条）在 additive 增量内闭环，无一需要重写既有契约；
3. 工作量最小且全部 headless 可测，与项目测试纪律一致；
4. 为 #589/#590 提供通用精英基底（Boss 条 UI/双轨击杀/蓄力攻击/击退/恢复），内容 issue 零重复实现；
5. 「蓄力攻击可弹反」与 #589 危攻击（不可弹反）语义天然区分，两个 issue 无数值/机制冲突。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（验收清单，映射 issue body 5 条 + 补充 4 条）

- [x] **AC1: 敌人会主动接近并攻击玩家（无需玩家贴脸）**（既有能力，精英化维持）
  - [ ] 敌人初始 Patrol → 玩家进入 120° 视线 6m → Chase 逼近 → 停距 → 攻击（#581 既有路径回归全绿）
  - [ ] 精英参数档位：追击速度/攻击冷却读精英常量候选（§8.2），不改行为路径
- [x] **AC2: 敌人攻击可被弹反，弹反后敌人硬直**（既有能力，含新蓄力攻击）
  - [ ] 三连砍/突刺/蓄力重斩三种出招全部经 #577 弹反闭区间判定（PARRY_WINDOW_SECONDS=0.2）
  - [ ] 弹反成功 → 敌人 25 架势 + 0.5s 抑制窗硬直（#581 既有，回归）
  - [ ] 蓄力重斩窗口 windup=ENEMY_CHARGE_WINDUP（≥18 帧）时弹反闭区间判定仍正确（实验 1）
- [x] **AC3: 敌人架势条崩解后可处决**（既有能力，确认衔接）
  - [ ] 4 次弹反（25×4=100）或 3 刀受击（35×3=105）→ break_stance → stance_break 3s → #580 armed 窗口 → attack_pressed 处决一击（回归全绿）
- [x] **AC4: 玩家不操作时敌人会持续进攻**（既有能力，维持）
  - [ ] 玩家站桩 → 敌人按冷却循环 攻击→收招→攻击（回归）
- [x] **AC5: 敌人有血条，普通攻击需多次才能击杀（非一击毙命）**（新）
  - [ ] main_battle.gd 敌人装配 life_1_max = ENEMY_HP_MAX（精英候选值，§8.4-1）
  - [ ] 纯削血路径：轻击 12/刀 → ENEMY_HP_MAX(候选 60-80) 需 5-7 刀击杀，`die()` 普通死亡（无处决演出，击杀提示 #576 显示）
  - [ ] 测试断言：敌人 hp 初始 = ENEMY_HP_MAX；N 刀后 hp>0（未死）；N+1 刀后 died(final=true)
- [x] **AC6: 敌人血条/架势条 UI 可见（顶部 Boss 条）**（新）
  - [ ] hud.gd 新增 EnemyHealthBar：顶部中央（同 EnemyStanceBar 锚点），宽 240px 高 10px 暗红条，位于 EnemyStanceBar 上方
  - [ ] `set_target_enemy(entity)` 注入 → 双条同时显示；hp_changed → 血条比例更新；died(final) → 双条隐藏
  - [ ] 测试断言：注入后 EnemyHealthBar.visible=true；set_debug_hp 驱动比例；died 后隐藏
- [x] **AC7: 架势崩解后进入处决窗口（与 #580 衔接）**（既有能力，确认）
  - [ ] stance_broken → ExecutionOrchestrator armed 3s 窗口 → 距离内 attack_pressed → execute（回归全绿）
- [x] **AC8: 架势脱战恢复（不无限崩解）**（新）
  - [ ] 敌人受击/受弹反后 ≥ ENEMY_STANCE_RECOVER_DELAY_SEC 无架势伤害 → stance 以 ENEMY_STANCE_RECOVER_PER_SEC 恢复至 stance_max
  - [ ] 崩解期间（stance_break）不恢复；recover_from_break（50%+5s 疲惫）后恢复机制照常
  - [ ] 仅敌人生效：玩家实体（is_player=true）不触发脱战恢复（玩家架势语义不变，回归全绿）
  - [ ] 测试断言：注入 stance 伤害 → 延迟窗口内不恢复 → 超延迟后逐帧恢复至上限；崩解态不恢复

### 5.2 边界情况（Edge Cases）

1. **击退与追击叠加抖动**：受击击退（stagger 12 帧）期间 AI 决策门控已禁止 Chase 位移（#581 既有）——击退衰减在 stagger 结束前归零，恢复后从击退落点继续 Chase，**禁止「击退-拉回」弹簧抖动**（击退速度线性衰减，衰减系数进 constants）
2. **蓄力攻击在连段中被打断**：蓄力重斩前摇期间玩家弹反 → parry_success → 连段计划作废（AI 抑制窗接管，#581 既有边界 7 复用）——蓄力窗口同样被抑制窗覆盖
3. **玩家削血击杀与架势崩解同帧竞争**：hp 归零与 stance 归零同帧 → die() 与 break_stance 竞态——既有守卫：`take_damage` 先判 hp≤0 → die()（终态锁）；`break_stance` 幂等 + 终态后 AI 禁用（#581 既有），测试覆盖同帧双归零
4. **脱战恢复与战斗再触发**：恢复进行中玩家重新攻击 → take_stance_damage 重置延迟计时，恢复暂停——「恢复-再受伤」节拍正确（不出现边恢复边掉架势的闪烁）
5. **敌人血条在处决/死亡后的显隐**：execute_kill → died(final) → 双条隐藏（#576 既有 _on_enemy_died 路径扩展）；处决演出（execute 态）期间血条保持 0 隐藏
6. **精英参数档位缺省**：装配未注入精英常量组 → 回退小兵参数（ENEMY_HP_MAX 当前值 40 等），不报错（向后兼容 #581 场景）
7. **蓄力攻击概率与突刺概率互斥**：出招三选一掷骰概率和 = 1（ENEMY_CHARGE_CHANCE + ENEMY_THRUST_CHANCE + 三连余量），非法和（>1）→ push_warning + 回退默认
8. **击退目标越界**：击退位移使敌人越过场景边界（2400px 舞台）——clamp 到舞台内（#583 舞台尺寸，不引入新物理）

### 5.3 失败路径（Failure Paths）

1. **HP 装配未消费常量**（main_battle.gd 漏改）：敌人 life_1_max 回落默认 100 → 慢线 9 刀击杀（偏离精英预期）——测试 test_main_assembly 断言 life_1_max == ENEMY_HP_MAX 拦截
2. **架势恢复与 #580 恢复双写竞态**：脱战恢复（_process 轮询）与 recover_from_break（50% 恢复）同帧双写 stance → 幂等守卫（is_stance_broken 检查 + 恢复仅非崩解态执行），测试注入同帧双触发断言最终值 ∈ [0, stance_max]
3. **蓄力攻击窗口未注入**（windup 字段漏设）：蓄力重斩回落普通 heavy_attack 前摇（12 帧）→ 弹反「过于容易」——judge 登记时断言 windup==ENEMY_CHARGE_WINDUP（敌人蓄力出招），测试拦截
4. **hud EnemyHealthBar 未绑定 hp_changed**：血条恒满——set_target_enemy 订阅断言 + set_debug_hp 驱动测试拦截

---

## 6. 依赖与阻塞

### 6.1 依赖关系

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #575 CombatEntity（#618 merged） | ✅ | 无（数据模型既有，只加脱战恢复 additive） |
| #577 CombatJudge + AttackWindow（#626 merged） | ✅ | 无（弹反闭区间零改动；windup 字段 #581 已交付） |
| #580 处决系统（#660 merged） | ✅ | 无（只消费 stance_broken/armed 窗口） |
| #581 敌 AI（#638 merged） | ✅ | 无（行为框架基底） |
| #585 组装（#666 merged） | ✅ | 低（main_battle.gd 一行参数修改，回归全绿） |
| #576 HUD 草稿（human-review） | ✅ | 低（EnemyHealthBar additive；用户定稿仅影响视觉细节不阻塞） |
| #584 数值草稿（human-review） | ✅ | 低（新常量 # DRAFT 只读，定稿归 #584） |
| #589/#590 内容 issue（backlog） | ⛔ 未开始 | 无（本 PRD 交付通用基底，不依赖内容） |

```
#575 ──► #577 ──► #581 ──► #585 ──► #682（本 issue：精英化增量）──► #589 军曹 ──► #590 汉奸 Boss
#580 ──┘                        │         │
#576 ──► HUD 基底 ──────────────┘         └──► #584 数值定稿（精英常量入表）
```

### 6.2 开源调研（issue body 要求「开源优先，成熟方案优先复用，找不到再自行实现，并在 PR 中说明调研结果」）

| 类别 | 候选 | 调研结论 |
|------|------|---------|
| Godot elite/mini-boss AI（GDScript，2026-08-21 GitHub API 检索） | Snaiel/Godot4ThirdPersonCombatPrototype（234⭐） | 3D 第三人称战斗原型——3D 视角与横板 2D + 逻辑帧判定架构不符；无架势/弹反/双轨击杀语义。**不采用**（与 #581 调研结论一致） |
| Godot boss fight / 2-phase boss | 无 Godot 4.7 高星 2D boss 模板（检索 boss fight godot / elite enemy godot，最高 30-50⭐ 教学 demo） | 教学 demo 非可复用库，且不接本项目判定层/处决契约。**不采用** |
| 行为树扩展（精英复杂决策） | andrew-wilkes/godot-behaviour-tree（53⭐，#581 已调研） | #581 已否决（MVP 4 态 FSM 过度设计）；精英三选一出招仍处 FSM 表达力内。**不采用** |

**结论：** 无成熟可复用的「Godot 2D 横板类只狼精英敌人 AI」开源库（#581 调研结论延续，本 issue 增量未超出 FSM 表达力）。**在 #581 自研 EnemyAI 基底上做参数化升级**（方案 A）。implement PR 须引用本调研结论。

### 6.3 前置准备

- [ ] implement 前确认 origin/main 已含 #638（#581 实现）、#660（#580 实现）、#666（#585 实现）、#654（#579 实现）
- [ ] 本 PRD merge 后，plan agent 读 §8 交接上下文即可开工，无需重扫源码

---

## 7. Spike / 实验（depth/standard 可选，本 PRD 含 2 实验提升交接质量）

### 实验 1：蓄力攻击前摇 vs 弹反闭区间时序对齐

- **要回答的问题**：蓄力重斩前摇 18/20/24 帧（ENEMY_CHARGE_WINDUP 候选）时，#577 弹反闭区间 `[hit_ms - 200ms, hit_ms]` 是否仍成立？前摇越长 → 窗口绝对时间越长 → 弹反是否「过于容易」？
- **方法**：构造敌人实体（windup 候选值）+ AttackState 蓄力出招 → judge 登记窗口断言 hit_frame = start + windup → 玩家 guard_pressed 在闭区间边界（lower/hit/超出）三态断言；对比 12 帧突刺基线
- **预期结果**：三候选 windup 下闭区间判定全部正确；弹反难度随前摇线性放宽（24 帧 ≈ 0.4s 窗口，需在「可读」与「不难」间取平衡）→ 记录 #584 裁决
- **对方案的影响**：若 24 帧弹反「过于容易」（无脑弹反），候选集下调或蓄力攻击改为「弹反窗口更紧」（弹反窗收窄系数，新常量）；若 18 帧手感好则定稿候选

### 实验 2：架势脱战恢复节奏（延迟/速率组合 vs 崩解频率）

- **要回答的问题**：脱战延迟 2.0/2.5/3.0s × 恢复速率 15/20/25 per/s 的 9 组合下，「弹反 4 次崩解」的快线是否仍显著快于「削血 5-7 刀」的慢线？恢复是否导致「永远崩不了」（玩家失误一次就白打）？
- **方法**：headless 模拟——固定弹反序列（4 次弹反间隔 1.2s）注入 stance 伤害 + 脱战恢复，断言崩解所需弹反次数随组合变化；统计「崩解前需连续输出秒数」
- **预期结果**：sekiro 基准组合（2.5s/20 per/s）下 4 弹反仍可崩解（弹反间隔 < 延迟窗口）；慢线 5-7 刀不受恢复影响（受击即重置延迟）→ 双轨速度差成立
- **对方案的影响**：若某组合下快线失效（恢复 > 弹反积攒），延迟窗口收窄或速率下调；若慢线被恢复拖长（玩家 2 刀后停手 → 敌人回满），属预期「脱战惩罚」，记录 #584

---

## 8. 交接上下文（plan agent 交接）

### 8.1 系统现状快照

- origin/main @ c22025d：EnemyAI 行为 FSM（patrol/chase/attack/retreat，感知 120°/6m、弹反抑制窗 0.5s、5% 回避）、CombatEntity（hp_1/life_1_max=100/stance_max=100 + 6 信号）、CombatJudge（双轨伤害 12/35、弹反 25、窗口 windup 参数化）、ExecutionOrchestrator（崩解 → armed 3s → 处决一击）、HUD（EnemyStanceBar 顶部中央 + 玩家血条/架势条 + 提示）、main_battle.gd 完整装配（#585）
- 缺口（本 PRD 增量）：HP 慢线装配不消费 ENEMY_HP_MAX、无敌人血条 UI、无蓄力攻击、无受击击退、无架势脱战恢复

### 8.2 交付物清单（按实现顺序）

| 顺序 | 文件 | 内容 |
|:----:|------|------|
| 1 | `constants.gd`（修改） | 精英 AI 分区 # DRAFT 常量：ENEMY_CHARGE_WINDUP（候选 [18,20,24] 帧，默认 20）/ ENEMY_CHARGE_HP_DAMAGE（候选 [20,25,30]，默认 25）/ ENEMY_CHARGE_CHANCE（候选 [0.15,0.2,0.25]，默认 0.2）/ ENEMY_KNOCKBACK_PX（候选 [30,40,60]，默认 40）/ ENEMY_KNOCKBACK_DECAY（候选 [2,3,4]/s）/ ENEMY_STANCE_RECOVER_DELAY_SEC（候选 [2.0,2.5,3.0]，默认 2.5=sekiro 1.5s 放宽）/ ENEMY_STANCE_RECOVER_PER_SEC（候选 [15,20,25]，默认 20=sekiro 基准）/ ENEMY_HP_MAX 候选上调（当前 40=sekiro 小兵 30-50；精英候选 [60,80,100]，默认 80）——全部「sekiro 基准 → 候选 + 影响 + 情感断言」注释，定稿归 #584 |
| 2 | `main_battle.gd`（修改） | 敌人装配 `new({"is_player": false, "life_total": 1, "life_1_max": C.ENEMY_HP_MAX})` |
| 3 | `hud.gd`（修改，additive） | EnemyHealthBar（顶部中央 240×10 暗红，EnemyStanceBar 上方）；set_target_enemy 订阅 hp_changed；died 双条隐藏 |
| 4 | `enemy_ai_states.gd`（修改，additive） | AttackState 出招三选一（蓄力重斩 = request_transition("heavy_attack") + 实体 windup 注入 ENEMY_CHARGE_WINDUP） |
| 5 | `enemy_ai.gd`（修改，additive） | 受击击退：订阅 hit_landed（defender=本敌人）→ _knockback 意图（stagger 期间衰减）；_apply_movement 消费 |
| 6 | `combat_entity.gd`（修改，additive） | 敌人架势脱战恢复：_process 轮询（is_player=false 且非崩解且超延迟 → 恢复至 stance_max，发射 stance_changed）；take_stance_damage 重置延迟计时 |
| 7 | `combat_attack_window.gd`（修改，可选） | 蓄力 windup 注入点（优先复用 windup_frames 字段；如需按出招区分再加 override） |
| 8 | `test_enemy_ai.gd` / `test_hud.gd` / `test_combat_entity.gd` / `test_main_assembly.gd`（修改） | §5.1 AC5-AC8 用例 + §5.2/§5.3 边界失败路径 + §7 实验 1/2 落地 |

### 8.3 接口契约（下游系统的消费面）

```gdscript
## EnemyAI 精英档位（装配注入，向后兼容小兵缺省）
@export var elite_mode: bool = false        # true → 读精英常量组（HP/架势/前摇/伤害/概率/冷却）
## 蓄力重斩（AttackState 出招三选一）
# 出招时: entity.request_transition("heavy_attack")
# 窗口注入: entity 携带 windup（ENEMY_CHARGE_WINDUP）→ judge 登记 AttackWindow.windup_frames（#581 既有字段）
## 受击击退（EnemyAI 内部）
var _knockback_vel: float = 0.0             # stagger 期间沿受击反向，ENEMY_KNOCKBACK_DECAY 衰减
## 架势脱战恢复（CombatEntity，仅 is_player=false）
var _stance_recover_delay_until_sec: float  # take_stance_damage 重置；_process 超时后 PER_SEC 恢复
## HUD Boss 条（hud.gd）
var EnemyHealthBar: _HudBar                 # 顶部中央暗红条；set_target_enemy 绑定 hp_changed
```

**组合约定（#589/#590 后续遵循）：** 精英敌人 = 同一 EnemyAI 节点 + elite_mode=true + 精英常量组；视觉仍复用 SW-003 骨架（#589 的 1.3x 体型/刺刀由内容 issue 叠加）；Boss 条 UI 已就绪，内容 issue 无需重做 HUD。

### 8.4 主要风险与裁决点

1. **ENEMY_HP_MAX 精英值**：当前 40（sekiro 小兵 30-50）。精英候选 [60, 80, 100]——用户「多次攻击才击杀（非一击死）」+ 轻击 12/刀 → 80 ≈ 7 刀，与「慢线稳健、快线技术」双轨成立；若用户实机嫌磨，下调 60 或上调轻击伤害（#584 域）。
2. **蓄力攻击前摇 20 vs 弹反难度**：20 帧 ≈ 0.33s 前摇可读；弹反闭区间 0.2s 相对 12 帧突刺（0.2s 窗口）更宽松——实验 1 验证；若「无脑弹反」，收窄弹反窗或降蓄力频率（#584 域）。
3. **击退与场景边界**：击退 40px 在 2400px 舞台内无越界风险（边界 8 clamp 兜底）；击退衰减系数候选 [2,3,4]/s 防弹簧抖动（实验外验证，进单测）。
4. **脱战恢复对快线的影响**：弹反间隔（AI 冷却 1.5s 内玩家可弹反 4 次）< 延迟窗口 2.5s → 快线不被恢复打断；玩家失误停手 → 敌人回架势 = 只狼式「脱战惩罚」（实验 2 验证）。
5. **#576 human-review 的 UI 定稿**：EnemyHealthBar 视觉（暗红/宽度/高度）先按 #576 既有风格 additive 实现；用户定稿差异由 #576 通道收敛，不阻塞本 issue。
6. **GDD 落盘**：post-merge agent 更新 `docs/GAME_DESIGN/shandong-wolf/13-ENEMY-AI.md`（精英档位/蓄力/击退/恢复）与 `10-HUD-STANCE-BARS.md`（Boss 条组合）。

### 8.5 红线（implement agent 禁止）

- ❌ 不改 11 态 `CANONICAL_STATES` / `consume_state` 契约（精英行为仍是 AI 行为态，不进战斗状态表）
- ❌ 不改 #577 五结果事件名与裁决顺序；不引入 Area2D/CollisionShape2D 物理碰撞
- ❌ 不裁决 # DRAFT 数值（只读 constants；精英新常量标 # DRAFT + 候选集）
- ❌ 不实现 #589 军曹/#590 汉奸内容（危攻击/霸体/体型/掉落/二阶段/台词/演出）
- ❌ 不修改既有接口签名（entity/judge/AttackWindow 全部 additive；现有 19 测试文件必须全绿）
- ❌ 不写死 AI 数值字面量（蓄力/击退/恢复/HP 全走 constants）
- ❌ 不修改 mini-pong/ 任何文件；不修改 scenes/Main.tscn；不改玩家实体行为（脱战恢复仅 is_player=false）

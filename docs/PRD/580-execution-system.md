# PRD #580 — [Feature] 处决系统（架势崩解 → 处决特写）

> **Issue:** #580
> **标签:** enhancement, gameplay, workflow/research, version/mvp（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=9）
> **深度:** deep（分解 JSON id=9 标注 `depth: deep` → §1–8 全必填，§7 含 ≥3 实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-20
> **所有权:** `content_ownership: mechanical`（处决机制实现=机械工程；慢动作时长/淡出节奏/演出强度参数=taste-draft，constants.gd # DRAFT + 候补值 + E2E 截图用户裁决，不在本 issue 定稿）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（OBSIDIAN_VAULT_PATH=/Volumes/Obsidian，本地 `~/Documents/Obsidian Vault/` 同源）：wiki grep 只狼 → `wiki/游戏设计理念.md`（只狼为灵感来源、「游戏机制是超越文本的修辞手段」——处决特写是情绪弧最高点的表达手段，不是装饰）；raw grep 破防/增伤 → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（FF16 **Stagger 系统=破防增伤** ——「崩解后疲惫期更容易被再次崩解」的机制佐证）+ `raw/Bear/feedback.md`（弱相关）；grep 处决/忍杀/介错 → wiki/raw 无直接技术笔记 → 审美权威源 = 设计 brief（`docs/RAW/shandong-wolf-brief.md` §审美坐标/§核心机制#5/§校准偏好 B3「处决特写构图 = 截图证据 + 用户裁决」）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：**忍杀 Deathblow = 架势崩解 → 一击必杀 + 演出；铁律 5「处决是奖励不是补刀」；铁律 2「崩解惩罚必须清晰：失衡硬直 2-3s，玩家可从容处决」**）+ 视觉配方（`agents/skills/game-to-issues/references/visual-implementation-path.md` §5 血色配方「处决瞬间：vignette 血色加深 + 红闪 100-150ms + 雪地血迹低饱和暗红 #5a1010，血色必须克制」+ §6.5 火柴人动作「处决上撩→斩落 5 帧」+ **§7 处决特写配方「hit-stop + 时间缩放 + 镜头顿帧 + 刀光；白刃斩后接雪粒子静止帧」**）+ 同链 issues（#573 输入 / #574 动画 / #575 实体+状态机 / #577 判定 / #578 复活 / #579 反馈 / #581 敌AI / #584 数值 / #585 组装）+ 开源调研（GitHub API 检索 execution/finisher/deathblow，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=9，estimate 3d，priority high）
> **前置依赖:** #577（merged #626：CombatJudge 五结果事件契约，stance_broken 幂等转发）、#579（merged #654：ReactionController S 级 execute 反馈 + TimeScaleStack + 刀光）——全部已满足

---

## 1. 问题定义

### 1.1 现状（2026-08-20 worktree 侦查 @ origin/main e0939e6）

**契约层已 100% 就绪——处决所需的信号、状态、动画、反馈全部由上游 issue 交付，唯一缺失是「编排者」。**

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ 已交付（#575/#618） | CombatEntity（Node2D）：6 信号契约（hp_changed / stance_changed / **stance_broken** / state_changed / died / revived）+ `break_stance()` 幂等（stance=0 + 广播 + 转移 stance_break）+ `request_transition` 唯一入口 + `die()` 两段血（敌人 life_total=1 → final=true）——**⚠️ 红线：`take_damage` 在 `execute` 态 no-op（§5.2-1 执行中无敌）** |
| `shandong-wolf/gdscripts/combat_state_table.gd` | ✅ 已交付（#575/#618） | 11 态 CANONICAL_STATES 权威集 + TRANSITIONS 拓扑表——**`stance_break → execute` 表内（#580 处决入口已拓扑预留）**；`execute → idle` 表内；`stance_break → attack/guard` 表外（崩解失衡禁攻） |
| `shandong-wolf/gdscripts/combat_states.gd` | ✅ 已交付（#575/#618） | CombatStateStanceBreak：`STANCE_BREAK_RECOVERY_SEC(3.0)` 后自动退出 → idle（注释明言「期间 #580 可经 request_transition(\"execute\") 抢先」）；CombatStateExecute：`FRAME_ANIM_EXECUTE_TOTAL(5)` 帧后自动退出 → idle（执行中无敌） |
| `shandong-wolf/gdscripts/combat_judge.gd` | ✅ 已交付（#577/#626） | **stance_broken 幂等转发**（统一事件出口）；判定器对「无敌期/死亡/复活/处决态受击」跳过（§8 边界表）——处决期间目标免疫判定已由判定器+实体双保险 |
| `shandong-wolf/gdscripts/input_controller.gd` | ✅ 已交付（#573/#611） | `attack_pressed` 意图信号（复用 #2 attack 键 = 处决键，issue 触发契约逐字对齐） |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#572/#584/#599/#609） | `SWORD_DAMAGE_EXECUTE=999`（机械语义，骨架期可定稿）、`EXECUTE_RANGE=1.2`、`FRAME_ANIM_EXECUTE_TOTAL=5`、`SLOWMO_COEFF=0.2`、`SLOWMO_HOLD_SECONDS=0.4`、`STANCE_BREAK_RECOVERY_SEC=3.0`；**⚠️ `POSTURE_RECOVERY_PER_SEC/DELAY` 定义但零消费方**（架势自然回复机制尚未落地，见 §1.4 边界） |
| `shandong-wolf/gdscripts/reaction_controller.gd` | ✅ 已交付（#579/#654） | **execute = S 级反馈矩阵**（hit-stop 150ms + 屏震 4px + 慢动作 0.05x 0.5s + 刀光弧线 + 血色粒子）+ `_trigger_execute_arc()`（目标 SwordArc.trigger_burst 只调用不改实现）+ TimeScaleStack 嵌套时间缩放（墙钟兜底）+ screen_shake + flash_effect |
| `shandong-wolf/gdscripts/hud.gd` | ✅ 已交付（#576/#627） | `_on_enemy_stance_broken` → **处决提示自动显示**（EXECUTE_HINTS 5 候选草稿，implement 选 1，候选清单进 PR 待用户定稿）；玩家进 attack/execute 态自动隐藏提示；敌人 `died(final=true)` → 击杀提示 + 架势条隐藏 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | ✅ 已交付（#574/#612） | **anim_execute clip 已构建**（FRAME_ANIM_EXECUTE_TOTAL=5 帧上撩→斩落，_build_execute_spec）+ consume_state 契约把 `execute` 状态映射到 anim_execute |
| `shandong-wolf/gdscripts/enemy_ai.gd` | ✅ 已交付（#581/#638） | 实体进非 idle/move 态清 move_intent（stance_break/execute 自动停走）；`_on_entity_died` → AI 完全禁用（_dead=true） |
| `shandong-wolf/e2e_shots.json` | ✅ 已交付（#574/#579/#582/#583） | feedback 组 **fb_execute shot**（state 3，settle 120）+ stick_figure 组 EXECUTE=9 态；battle_stage 组 3 景（PANORAMA/CLOSEUP/MOON） |
| `shandong-wolf/gdscripts/` | ❌ **无触发编排器** | `request_transition("execute")` 全库零调用（唯一提及是注释）；`SWORD_DAMAGE_EXECUTE` 零消费；无「玩家靠近崩解敌人按攻击自动衔接」的任何判定逻辑 |
| `shandong-wolf/gdscripts/` | ❌ **无杀敌路径** | take_damage 在 execute 态 no-op（无敌红线）→ 处决杀敌必须走**专用接口**（§4.2 核心设计决策） |
| `shandong-wolf/gdscripts/` | ❌ **无玩家无敌接口** | AC2「处决期间玩家与目标均无敌」：目标侧已由 #575/#577 双保险；**玩家侧无公共无敌接口**（`_invincible_until_sec` 私有，仅 revive() 内部使用） |
| `shandong-wolf/gdscripts/` | ❌ **无淡出机制** | 处决结束敌人淡出（modulate alpha 1→0 0.3s）如墨迹消散——revive_fx 有 modulate 闪烁先例可参考，无现成淡出组件 |
| `shandong-wolf/gdscripts/` | ❌ **无疲惫起身** | 「3s 未处决 → 恢复 50% 架势 + 5s 疲惫（受架势伤害 +20%）」零实现；无 exhausted 标志、无增伤乘数消费点 |
| `shandong-wolf/scenes/` | ⏳ #585 组装 OPEN | CombatJudge / ReactionController / 实体 / Camera2D 尚未入战斗场景——**本 issue 编排器必须与场景解耦（bind 模式），零场景依赖**（同 #578 ReviveOrchestrator 先例） |

**核心缺口：** 处决链路的**每一块零件都已存在**——崩解信号（#575/#577）、execute 状态拓扑（#575）、5 帧处决动画（#574）、S 级反馈组合（#579）、HUD 提示（#576）、杀敌常量（#584）——但**没有任何组件把它们串起来**：玩家按攻击键时没人检查「敌人是否崩解 + 是否在距离内」，敌人崩解后没人抢先转移 execute，杀敌没有通道（take_damage 无敌红线），演出结束没有淡出，错过窗口没有疲惫起身。**本 issue 交付 = 处决编排层（ExecutionOrchestrator）+ 2 个最小实体接口扩展（execute_kill / set_invincible / recover_from_break）+ 1 个淡出组件 + constants「处决演出」分区。** 这是 #585 组装「可玩战斗闭环」的最后一个功能件。

### 1.2 验收条件（源自 Issue #580 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | 敌人 stance_break 后 3s 内按 execute 键触发处决动画并杀敌 | §4.1 编排器（armed 窗口 = STANCE_BREAK_RECOVERY_SEC 同源互引）+ §4.2 execute_kill 杀敌通道 + §5.1 AC1 时序断言 |
| AC2 | 处决期间玩家与目标均无敌，处决后目标淡出消失 | §4.3 玩家 set_invincible 公共接口（目标侧 #575 take_damage no-op + #577 判定器守卫双保险）+ §4.2 淡出组件（modulate 1→0 0.3s） |
| AC3 | 崩解后 3s 未执行，敌人起身并恢复 50% 架势，且 5s 内疲惫（受架势伤害 +20%） | §4.4 recover_from_break（50% 恢复 + exhausted 标志 + take_stance_damage 内 ×1.2 乘数，5s 到期幂等恢复） |
| AC4 | 处决触发 SW-008 的强力慢动作与火花，持续时间 0.6s | §4.1 编排器调 trigger_feedback("execute")（S 级矩阵已由 #579 交付）+ §5.1 AC4：慢动作时长候选统一进「处决演出」分区（三处候选冲突见 §1.5，taste 域用户裁决） |
| AC5 | E2E 截图提交用户裁决：处决瞬间构图符合『雪夜+血色+水墨』审美许可（禁止夸张喷血、禁止奥特曼式发光） | §7 实验 3（battle-stage 级处决构图 rig）+ §8 交接：E2E 截图产出路径 + taste-draft 裁决通道（#584 面板 + 用户实机） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机操作（MVP 战斗闭环） | 每次游玩 | 玩家弹反/连击打崩敌人架势 → 敌人失衡白闪 + 处决提示浮现 → 玩家靠近按攻击键 → 短促慢动作 + 刀光 + 血色粒子 + 敌人被斩落淡出如墨迹消散——『赢了一场艰难的仗』的情绪峰值；若玩家犹豫 3s，敌人起身（疲惫喘息，架势只有一半）——玩家可再崩解一次 |
| B | 下游系统消费（#585 组装 / SW-019 扩展） | 每次 impl PR | 组装层把 ExecutionOrchestrator 实例化进战斗场景并 bind 玩家/敌人/判定器/输入；处决演出强度参数从 constants「处决演出」分区读取——Boss/精英（SW-019）只改参数不碰编排逻辑 |
| C | 开发者 headless + E2E 验证 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`：直接 new ExecutionOrchestrator 断言触发时序/无敌窗口/疲惫数值/杀敌通道；E2E rig 注入处决构图截图供用户裁决 |

### 1.4 范围边界（Patch 14 去冲突 + 契约红线）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #575（战斗实体，merged #618） | CombatEntity 数据容器 + 11 态状态机 + 6 信号 + take_damage execute no-op 无敌红线 | ❌ 不重写实体；**只做最小 additive 接口扩展**（execute_kill / set_invincible / recover_from_break，语义与既有机制同构，不改既有路径） |
| #577（判定，merged #626） | 弹反/拼刀/格挡/受击裁决 + 五结果事件（含 stance_broken 幂等转发） | ❌ 不做判定；只消费 stance_broken 事件作为处决窗口开启信号（判定器对处决态实体跳过受击 = 目标无敌来源之一） |
| #579（反馈，merged #654） | 分级反馈矩阵 + S 级 execute 组合（刀光/血色粒子/hit-stop/慢动作/屏震）+ TimeScaleStack | ❌ 不重造反馈；编排器只调 `trigger_feedback("execute")` 一个入口，慢动作时长冲突（§1.5）由本 PRD 归拢进常量分区，**实现归 #579 已有组件** |
| #574（动画，merged #612） | anim_execute clip（5 帧上撩→斩落）+ SwordArc 刀光 | ❌ 不重造动画/刀光；编排器经 request_transition("execute") 间接消费 anim_execute（状态名契约对齐） |
| #578（复活，merged） | 两条命原地复活（ReviveOrchestrator 编排先例） | ❌ 不做复活；**编排器架构直接借鉴 ReviveOrchestrator bind 模式**（订阅信号 + 自管理计时 + headless 确定性 _process 驱动） |
| #581（敌AI，merged #638） | 巡逻/追击/攻击/被弹反 4 行为态 | ❌ 不改 AI；AI 已对 stance_break/execute/dead 态自动停走（_on_entity_state_changed / _on_entity_died），疲惫起身后 AI 自然恢复行动 |
| #584（数值 DRAFT，OPEN） | 手感数值集中表 + DebugCanvas 调参面板 | ❌ 不裁决任何 # DRAFT 数值；新增「处决演出」常量同样标 # DRAFT + 候补值，定稿通道归 #584/用户 |
| #585（组装，OPEN） | 把全部组件实例化进战斗场景 + 信号桥接 | ❌ 不组装场景；编排器 bind 模式与场景解耦，#585 只做实例化 + bind 接线（§8 交接清单） |
| #582（氛围，merged） | 雪幕/月光/水墨晕染/血色 vignette（常驻氛围层） | ❌ 不碰氛围层；处决血色粒子是事件瞬态（S 级局部 burst，#579 已交付），与常驻 vignette 上下分层共存 |

**契约红线（本 PRD 只许订阅不许改名）：** 处决事件名以 #577 五结果事件（stance_broken）+ CombatEntity 信号（state_changed/died）为准；状态名以 CANONICAL_STATES（execute/stance_break）为准；反馈入口以 ReactionController.trigger_feedback("execute") 为准；`take_damage` 在 execute 态 no-op 是 #575 无敌红线——**处决杀敌禁止绕过它去改 take_damage 的无敌逻辑，必须走新增专用接口**（§4.2）。

### 1.5 预期行为（处决时序 + 参数候选）

> 参数全部 # DRAFT（候补值来自 issue body + #579 矩阵 + 只狼基准 + 视觉配方 §7），**数值定稿归用户**（#584 通道 + E2E 截图裁决）。

**触发时序（issue 触发契约 2026-08-19 逐字落实）：**

```
t=0    敌人 stance ≤ 0 → break_stance()（幂等）→ stance_break 态（3.0s 窗口）
       ├── CombatJudge 幂等转发 stance_broken → ReactionController（A- 崩解反馈）+ Hud（处决提示）+ ExecutionOrchestrator（armed=true，窗口计时）
t∈[0,3s]  玩家按 attack（复用 #2 攻击键，靠近自动衔接）
       └── 距离校验 |dx| ≤ EXECUTE_RANGE_PX 且 armed → 处决触发：
           ├── 玩家 set_invincible(EXECUTE_INVINCIBLE_SECONDS)   # AC2 玩家无敌
           ├── 敌人 request_transition("execute")                 # 5 帧处决动画（#574 anim_execute）
           ├── 敌人 execute_kill()                                # AC1 杀敌（绕过 take_damage no-op 红线）
           │     ├── emit died(enemy, true) → Hud 击杀提示 + ReactionController death 反馈 + AI 禁用
           │     └── _is_final_dead = true（状态机停摆守卫，防复活/防二次事件）
           ├── trigger_feedback("execute") → S 级（150ms hit-stop + 慢动作 + 刀光 + 血色粒子 + 屏震）  # AC4
           └── 淡出（modulate alpha 1→0 0.3s，如墨迹消散）→ queue_free  # AC2
t=3s    未处决 → 敌人起身：stance = 50% × stance_max + exhausted=true（5s）  # AC3
       └── exhausted 期间 take_stance_damage × 1.2（疲惫期更容易再次崩解）
```

**慢动作时长三处候选冲突（本 PRD 归拢，不裁决）：**

| 来源 | time_scale | 时长 | 说明 |
|------|:---:|:---:|------|
| Issue #580 body（AC4/功能描述） | `0.1` | `0.6s` | 「短促慢动作（time_scale 0.1 持续 0.6s）」——本 issue 的权威输入 |
| #579 反馈矩阵 S 级（已实现 FEEDBACK_SLOWMO） | `0.05` | `0.5s` | 「0.05x 特写」+ AC4「0.05x 特写结束恢复正常」 |
| constants 现默认（SLOWMO_COEFF / SLOWMO_HOLD_SECONDS） | `0.2` | `0.4s` | #584 候补值（候选集 [0.1, 0.2, 0.3]） |

**冲突处理：** 三处同指「处决演出慢动作」但数值互不相同——实现期禁止二选一偷定。本 PRD 新增「处决演出」常量分区，把三个候选集并列为 `EXECUTE_SLOWMO_SCALE`（候选 [0.05, 0.1, 0.2]）+ `EXECUTE_SLOWMO_MS`（候选 [400, 500, 600]），消费方（编排器 → trigger_feedback）经常量读值，**#584/用户实机裁决**。机制层面：慢动作由 #579 TimeScaleStack 提供（已保证嵌套恢复，AC4 机械成立），本 issue 只传参。

**EXECUTE_RANGE 单位坑（# DRAFT 待裁决）：** `EXECUTE_RANGE=1.2` 语义为「1.2m」（sekiro-reference），但 Godot 2D 场景 1 单位 = 1px——直接按 1.2px 判距离必然永不触发。派生 `EXECUTE_RANGE_PX = EXECUTE_RANGE × 100 = 120px`（与 HITBOX_RANGE=80px 同量级，# DRAFT 候补，比例 100px/m 供用户裁决）。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`/Volumes/Obsidian`（OBSIDIAN_VAULT_PATH）与 `~/Documents/Obsidian Vault/` 同源，wiki + raw 定向 grep：`只狼|忍杀|处决|架势|崩解|破防|终结|介错|墨迹|消散`）。
- **命中笔记：**
  - **《游戏设计理念》（wiki）**：*「游戏机制是超越文本的修辞手段」*、灵感来源含《只狼》→ 佐证处决特写作为「情绪弧最高点」的表达手段地位：处决不是击杀动画，是『赢了一场艰难的仗』那一刻的修辞。
  - **《JRPG 战斗系统研究 - 最终综合报告》（raw/Bear）**：FF16 **Stagger 系统 = 破防增伤**（ARPG 层）→ 直接支撑 AC3「疲惫起身更容易被再次崩解」：破防后的虚弱窗口（增伤乘数）是成熟动作 RPG 的标准奖励结构，与只狼「崩解 → 从容处决」互证。
  - **《feedback.md》（raw/Bear）**：弱相关（叙事视角反馈材料）。
- **Vault 无处决/忍杀技术笔记**（grep 处决/忍杀/介错/墨迹均无命中）→ 技术权威源 = issue body 画面实现路径（刀光 Line2D additive + 淡出 modulate 1→0 0.3s）+ 视觉配方 §7（处决特写：hit-stop + 时间缩放 + 镜头顿帧 + 刀光 + 白刃斩后雪粒子静止帧）+ 只狼调参基准（忍杀语义）。审美反例（介错/武士道美化、夸张喷血、奥特曼发光）来自 brief 反例清单，本 PRD 以 E2E 截图裁决为唯一验收通道。

---

## 2. 设计意图

### 2.1 现状为何存在

| 原因 | 细节 |
|------|------|
| 战斗系统分层推进 | #572 地基 → #573 输入 → #574 动画 → #575 数据/状态机 → #577 判定 → #578 复活 → #579 反馈 → **#580 处决（本层）** → #581 敌AI → #585 组装；处决是「崩解 → 击杀」的收尾演出，依赖判定（#577）、反馈（#579）、动画（#574）全部落地才能编排，故排在它们之后 |
| 处决被拆为独立 issue | 分解 JSON id=9 明确「处决对 Boss/精英的演出强度由 SW-019 扩展，本系统提供通用接口」——机制与演出强度分权，处决层作为机械 issue 提供通用编排接口，Boss 演出扩展后置 |
| 无现成编排先例 | 除 #578 ReviveOrchestrator 外，战斗层全部是「单组件单职责」（判定器/反馈器/状态机各自独立）；跨组件时序编排（信号 → 窗口 → 输入 → 转移 → 杀敌 → 演出 → 淡出）需要第一个「指挥者」组件 |

### 2.2 为何现在

1. **上游契约全部闭合**：#577（#626）已 merged——stance_broken 幂等转发是处决窗口的现成开启信号；#579（#654）已 merged——S 级 execute 反馈组合（刀光/血色粒子/hit-stop/慢动作/屏震）已可被单入口调用；#581（#638）已 merged——敌AI 已对 stance_break/execute/dead 态自动停走。**处决编排所需的输入、状态、动画、反馈、AI 配合全部可用，本 issue 纯编排，无任何底层负担。**
2. **#585 组装在即**：组装「可玩战斗闭环」的验收路径是「出生 → 遇敌 → 弹反 → 崩解 → 处决 → 击杀」——处决是闭环的终点演出，晚落地会阻塞闭环验收（#585 deps 含 id=9）。
3. **用户审美校准点**：brief 完成标准 = 「汉奸 Boss 处决特写出现时（雪夜+血色+水墨构图），我知道这游戏成了」——处决构图是 MVP 阶段唯一需要用户截图裁决的演出级场景（AC5），提前落地让 taste 通道（#584）尽早开始校准。

### 2.3 之前约束（继承 issue + brief + 配方 + 只狼基准，Patch 19）

| 约束 | 详情 | 来源 |
|------|------|------|
| 攻击键 = 处决键 | 靠近崩解敌人按攻击键自动衔接处决，无额外按键（「同键多义」只狼输入哲学） | issue 触发契约 2026-08-19 + #573 分解 JSON id=2 |
| 处决动作 12 帧以内 | 快、准、结局明确；现 anim_execute=5 帧（上撩→斩落）满足 | issue body 审美坐标 + #574 |
| 处决无敌 | 处决期间玩家与目标均无敌；take_damage execute no-op 是既有红线，禁止破坏 | issue AC2 + #575 |
| 崩解窗口 3s | STANCE_BREAK_RECOVERY_SEC=3.0（#618 战斗时序常量，#580 同值互引）；错过 → 起身疲惫 | issue AC1/AC3 + #618 GDD 09 章 |
| 数值集中 | 全部手感参数进 constants.gd # DRAFT，消费方经 DebugCanvas.get_value 读值（热更新优先，release 回落 const） | #584 + 02-CONSTANTS GDD |
| 工程/品味分离 | 机制实现 = mechanical（本 issue）；慢动作时长/淡出节奏/演出强度 = taste-draft（#584/用户裁决） | brief §校准偏好 + #579 先例 |
| 零碰撞体红线 | 距离判定用一维坐标差（横板），不引入 Area2D/CollisionShape2D（与 #574/#577 裁决一致） | #574 裁决 + #577 判定层 |
| 不引第三方 addon | #572 裁决：自研 40 行等价物优先，成熟开源方案先调研后复用 | #572 + 开源优先 brief |

---

## 3. 影响分析

### 3.1 直接影响文件（新增为主，修改为最小 additive）

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/execution_orchestrator.gd` | 处决编排器（**新建**） | Node（非实体、非 autoload，类 ReviveOrchestrator）：订阅 stance_broken + attack_pressed + state_changed + died → armed 窗口计时 → 距离/状态校验 → 处决触发序列（玩家无敌 + 敌人 execute + execute_kill + 反馈 + 淡出） |
| `shandong-wolf/gdscripts/execution_fade.gd` | 敌人淡出组件（**新建**） | Node：modulate alpha 1→0（0.3s # DRAFT）→ queue_free；is_instance_valid 守卫；与时间缩放解耦（墙钟驱动，慢动作期间不卡淡出） |
| `shandong-wolf/gdscripts/combat_entity.gd` | 实体接口扩展（**最小修改**） | 追加 3 个公共方法（additive，不触碰既有路径）：`execute_kill()`（处决杀敌专用通道）、`set_invincible(seconds)`（复用 _invincible_until_sec 机制）、`recover_from_break()`（起身：50% 架势 + exhausted 5s） |
| `shandong-wolf/gdscripts/constants.gd` | 「处决演出」分区（**追加**） | 新增 1 个 # DRAFT 分区：EXECUTE_SLOWMO_SCALE/MS（候选归拢 §1.5）、EXECUTE_INVINCIBLE_SECONDS、EXECUTE_FADE_SECONDS、EXECUTE_RANGE_PX、EXECUTE_EXHAUSTED_SECONDS、EXECUTE_RECOVER_RATIO、EXECUTE_EXHAUST_MULTIPLIER——全部 # DRAFT 只读，定稿归 #584 |
| `shandong-wolf/tests/run_tests.gd` | 测试挂载（**修改**） | 追加 `test_execution_orchestrator.gd` 套件 |
| `shandong-wolf/e2e_shots.json` | E2E 剧本（**追加**） | execution 组（或扩展 feedback 组）：处决构图 shot（§7 实验 3） |

### 3.2 新文件（汇总）

| 文件 | 行数估算 | 职责 |
|------|:---:|------|
| `execution_orchestrator.gd` | ~150 | 处决触发编排（bind 模式 + armed 窗口 + 时序序列 + headless _process 驱动） |
| `execution_fade.gd` | ~50 | 淡出演出（alpha 1→0 → queue_free） |
| `tests/test_execution_orchestrator.gd` | ~200 | 五路径单测（触发成功/错过窗口/距离外/玩家死亡守卫/淡出清理） |

### 3.3 间接影响

| 模块 | 影响 | 说明 |
|------|------|------|
| Hud | 无修改，行为增强 | 处决提示已由 #627 自动显示（_on_enemy_stance_broken）；处决成功 → 敌人 died(true) → 击杀提示自动接管（_on_enemy_died 已实现）；玩家 attack 态自动隐藏提示（_on_player_state_changed 已实现）——**零改动** |
| ReactionController | 无修改，消费增强 | trigger_feedback("execute") 已有 S 级实现 + _trigger_execute_arc 刀光（#654）——编排器接入即用 |
| CombatJudge | 无修改 | 处决期间目标受击跳过已内置（无敌期/死亡/复活/处决态守卫）；execute_kill 后实体 dead → 判定器 no-op |
| EnemyAI | 无修改 | stance_break/execute 态停走 + died 禁用已内置；疲惫起身（idle 态）AI 自然恢复行动 |
| #585 组装 | 接线依赖 | 组装层需实例化 ExecutionOrchestrator + bind_player/bind_enemy/bind_input/bind_judge + bind Camera2D（反馈）——§8 交接清单 |

### 3.4 数据流（处决全链路 ASCII）

```
敌人 stance ≤ 0 → break_stance()（幂等, #575）
    │ emit stance_broken(enemy)
    ▼
CombatJudge._on_stance_broken（幂等转发 #577）
    ├──► ReactionController → A- 崩解反馈（全屏淡白闪 + 0.5x 慢动作 0.3s）        ← #579 已交付
    ├──► Hud._on_enemy_stance_broken → 处决提示（EXECUTE_HINTS）                    ← #627 已交付
    └──► ExecutionOrchestrator._on_stance_broken → armed=true（窗口计时 3.0s）      ← 本 issue 新建
            │
            ▼ 玩家 attack_pressed（#573 输入桥）＋ |dx| ≤ EXECUTE_RANGE_PX ＋ armed
ExecutionOrchestrator._on_attack_pressed
    ├── player.set_invincible(EXECUTE_INVINCIBLE_SECONDS)      # AC2 玩家无敌（新接口）
    ├── enemy.request_transition("execute")                     # 5 帧 anim_execute（#574 消费）
    ├── enemy.execute_kill()                                    # AC1 杀敌（新接口，绕过 take_damage no-op）
    │     ├── emit died(enemy, true) ──► Hud 击杀提示 / ReactionController death / EnemyAI 禁用
    │     └── _is_final_dead = true（停摆守卫）
    ├── trigger_feedback("execute", {target_entity: enemy})     # AC4 S 级（150ms hit-stop + 慢动作 + 刀光 + 血色粒子 + 屏震）
    └── ExecutionFade.bind(enemy) → alpha 1→0 0.3s → queue_free  # AC2 淡出如墨迹消散
            │
            ▼ t=3.0s 窗口耗尽（armed 到期，未处决）
enemy.recover_from_break()                                      # AC3 起身（新接口）
    ├── stance = 0.5 × stance_max（恢复 50%）
    └── exhausted = true（5s）→ take_stance_damage × 1.2（疲惫期更易再崩解）→ 到期幂等恢复 1.0
```

### 3.5 文档更新

- [x] `docs/GAME_DESIGN/shandong-wolf/15-EXECUTION-SYSTEM.md`（post-merge agent 在 implement PR merge 后填充）
- [ ] `docs/GAME_DESIGN/shandong-wolf/INDEX.md`（追加 15 章条目）
- [ ] `docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md`（处决演出分区常量登记）
- [ ] `docs/GAME_DESIGN/shandong-wolf/11-PARRY-CLASH-STANCE-BREAK.md` §9 集成点「处决通道」状态 ⬜ → ✅
- [ ] `shandong-wolf/docs/PROJECT.md`（处决系统条目）

---

## 4. 方案对比（多子系统 PRD：4.1–4.5 各子系统独立对比）

### 4.1 触发编排器架构（核心：谁把零件串起来）

**方案 A：ExecutionOrchestrator（独立 Node，bind 模式，推荐）**
- 描述：类 #578 ReviveOrchestrator 的编排器（Node 非实体）：`bind_player(p)` / `bind_enemy(e)` / `bind_input(ic)` / `bind_judge(j)` 幂等接线；订阅 stance_broken（armed=true + 窗口计时）与 attack_pressed（处决检查）+ 一维距离校验（|dx| ≤ EXECUTE_RANGE_PX）；`_process(delta)` 自管理窗口计时（headless 确定性，测试手动推进）；触发时执行时序序列（§1.5）。
- 优点：与场景解耦（#585 组装只做实例化 + bind）；与 #578 同构（先例可循）；headless 免树直接单测；单一职责（编排，不做判定/反馈/状态）。
- 缺点：新增一个组件（~150 行）。
- 风险：Low。Effort：1-2 天。

**方案 B：CombatJudge 内嵌处决判定**
- 描述：判定器 resolve_attack 里加处决分支。
- 缺点：违反 #577 单一职责红线（「判定器不做渲染/演出/编排」——GDD 11 章明文）；判定器无窗口计时/无敌管理职责，膨胀成上帝组件。
- 风险：Med。Effort：1 天（但架构违规）。

**方案 C：CombatEntity 自驱动（stance_break 态内轮询输入）**
- 描述：StanceBreakState.update() 里轮询输入桥攻击键 + 距离。
- 缺点：实体不感知输入（#575 输入桥只桥接意图到转移）；状态对象直改实体数据违反「状态对象只计时」契约（GDD 09 章）；处决需协调玩家（无敌）与敌人（转移/杀敌）双侧，实体内无对方引用。
- 风险：High（状态机契约破坏）。Effort：2 天。

**推荐 A：** 与 #578 先例同构、职责单一、契约零破坏。

### 4.2 处决杀敌通道（核心决策：take_damage execute no-op 红线）

**方案 A：新增 `execute_kill()` 专用接口（推荐）**
- 描述：CombatEntity 追加公共方法：置 `_is_final_dead = true` + emit `died(self, true)` + 广播 hp_changed（hp 归零）——**不调用 take_damage、不转移 dead 态**（保持 execute 演出态，5 帧动画 + 淡出照常）；状态机停摆守卫（_is_final_dead）保证死后不可 revive/不可二次事件。
- 优点：零触碰 #575 无敌红线（take_damage 的 execute no-op 原样保留）；语义清晰（处决 = 无视架势终结，与 SWORD_DAMAGE_EXECUTE=999 机械语义一致）；died(true) 信号让 HUD/反馈/AI 自动接管（零改动消费）。
- 缺点：实体类新增一个公共方法（additive）。
- 风险：Low。Effort：0.5 天。

**方案 B：修改 take_damage 允许 execute 态被处决伤害击杀**
- 描述：给 take_damage 加 is_execution 参数或特判伤害值 999。
- 缺点：破坏 #575「execute 态 no-op」无敌契约——测试断言（test_combat_entity 30 用例）与 GDD 08 章红线需同步修改；特判魔法值 = 散落硬编码（#584 红线）。
- 风险：High（契约破坏连锁）。Effort：1 天（含契约修订）。

**方案 C：先杀敌（take_damage in stance_break 态）再转移 execute**
- 描述：处决触发时先 take_damage(999)（stance_break 态可扣血）→ die() → 再 request_transition("execute")。
- 缺点：die() 内部转移 dead（状态机停摆）→ `dead → execute` 表外 = reject → **处决动画永远无法播放**（拓扑死路）；两段血玩家侧还会触发复活路径。
- 风险：High（机制不成立）。Effort：—（否决）。

**推荐 A：** 唯一同时满足「杀敌 + 保持 execute 演出 + 契约零破坏」的路径。单测断言：execute_kill 后 state_name 仍为 "execute"、died(final=true) 恰好一次、take_damage 在 execute 态依旧 no-op。

### 4.3 玩家无敌（AC2 玩家侧）

**方案 A：新增 `set_invincible(seconds)` 公共接口（推荐）**
- 描述：CombatEntity 追加公共方法，复用既有 `_invincible_until_sec` 墙钟机制（revive() 同款）：`_invincible_until_sec = now + seconds`；take_damage/take_stance_damage 的无敌期 no-op 守卫（已存在）自动生效。编排器在触发处决瞬间 `player.set_invincible(EXECUTE_INVINCIBLE_SECONDS)`。
- 优点：零新机制（复用既有无敌期）；判定器侧对无敌实体跳过受击（#577 已内置）→ 双保险；headless 可测（Time.get_ticks_msec 注入）。
- 缺点：实体类新增一个公共方法（additive）。
- 风险：Low。Effort：0.5 天。

**方案 B：判定器守卫扩展（处决期间跳过玩家）**
- 描述：CombatJudge 记处决状态，期间不裁决玩家受击。
- 缺点：判定器需感知处决演出时长（跨组件状态耦合）；漏恢复 = 玩家永久无敌 bug。
- 风险：Med-High。Effort：1 天。

**方案 C：玩家进 execute 状态**
- 描述：拓扑表加 idle→execute，玩家转移 execute 态。
- 缺点：改 CANONICAL_STATES 拓扑 + #574 ANIM_CLIP_NAMES 契约（11/11 对齐断言破）+ 玩家 execute 态无动画 clip 定义；处决演出的是敌人（被斩者），玩家保持攻击挥刀即可——状态机迁移过度设计。
- 风险：High（状态名契约连锁）。Effort：2 天。

**推荐 A：** 最小接口 + 既有机制复用，无敌时长作为「处决演出」分区常量（EXECUTE_INVINCIBLE_SECONDS，候选 [1.0, 1.5, 2.0]，覆盖 execute 5 帧 + 淡出 0.3s 有余）。

### 4.4 疲惫起身（AC3：50% 架势恢复 + 5s +20% 受架势伤害）

**方案 A：实体数据层（recover_from_break + take_stance_damage 内乘数，推荐）**
- 描述：CombatEntity 追加：`recover_from_break()`（幂等：stance = 0.5 × stance_max + exhausted=true + emit stance_changed；由编排器 armed 到期调用，或由 CombatStateStanceBreak 退出钩子调用——双保险幂等）+ `exhausted` 数据 + take_stance_damage 内 `if exhausted: amount *= EXECUTE_EXHAUST_MULTIPLIER` + _process 内 exhausted 到期（EXECUTE_EXHAUSTED_SECONDS）幂等清除。
- 优点：增伤乘数在实体内部 = 消费方无关（判定器/测试/未来系统统一受益）；数据与状态机分离（状态对象只计时，恢复语义归实体层——#575 契约一致）；幂等防双写竞态。
- 缺点：实体类新增 1 数据 + 2 方法（additive）。
- 风险：Low。Effort：1 天。

**方案 B：编排器计时回调**
- 描述：Orchestrator 3s 到期直接写 enemy.stance / enemy.exhausted。
- 缺点：实体数据被外部直写（#575「实体层持有数据」契约破坏——reaction_controller 先例已证明「只读信号 + 调用接口」才是本项目红线）；双计时（编排器 3s + 状态机 3s）竞态窗口。
- 风险：Med（契约破坏）。Effort：1 天。

**方案 C：判定器消费疲惫**
- 描述：CombatJudge resolve_attack 里查 exhausted 乘 1.2。
- 缺点：判定器需读实体疲惫状态（跨组件）；只有判定路径受益，未来其他架势伤害源（如直调 take_stance_damage）漏乘。
- 风险：Med。Effort：0.5 天（但覆盖面窄）。

**推荐 A：** 乘数下沉实体层（唯一数据源），与 #577 判定器「调用实体接口」的既有模式一致。⚠️ 注：`POSTURE_RECOVERY_PER_SEC/DELAY`（自然回复）当前零消费方——本 issue 的 recover_from_break 是**固定值恢复（50%），不依赖自然回复机制**；自然回复落地归 #585 组装（或后续 issue），两者互不阻塞。

### 4.5 演出参数化接口（SW-019 Boss/精英扩展预留）

**方案 A：constants「处决演出」分区 + 编排器经 DebugCanvas.get_value 读值（推荐）**
- 描述：新增分区常量（EXECUTE_SLOWMO_SCALE/MS、EXECUTE_INVINCIBLE_SECONDS、EXECUTE_FADE_SECONDS、EXECUTE_RANGE_PX、EXECUTE_EXHAUSTED_SECONDS、EXECUTE_RECOVER_RATIO、EXECUTE_EXHAUST_MULTIPLIER）全部 # DRAFT + 候选集；编排器统一经 `DebugCanvas.get_value("NAME", C.NAME)` 读值（热更新优先，release 回落 const）；Boss/精英（SW-019）扩展 = 改参数或按实体等级读不同值，编排逻辑零改动。
- 优点：数值集中（#584 红线）；SW-019 扩展点显式（「本系统提供通用接口」issue 原话）；调参面板 F1 热更新直接作用于处决演出。
- 缺点：无（参数化成本 ≈ 0）。
- 风险：Low。Effort：0.5 天。

**方案 B：编排器内硬编码**
- 缺点：违反数值集中红线；SW-019 扩展需改代码。
- 风险：Med。Effort：0.5 天（但违规）。

**方案 C：独立 ExecutionDirector（场景级演出导演系统）**
- 描述：场景树级导演节点管理镜头/时间缩放/多阶段演出。
- 缺点：MVP 单敌人单处决，导演系统过度工程（#585 组装后再评估）。
- 风险：Med。Effort：3+ 天。

**推荐 A：** 参数分区 + get_value 读值，SW-019 扩展点以常量表形式固化在 PRD（§8 交接）。

### 4.6 推荐汇总表

| 子系统 | 推荐 | 核心文件 | Effort |
|--------|------|---------|:------:|
| 触发编排器 | A：ExecutionOrchestrator bind 模式 | `execution_orchestrator.gd` | 1-2d |
| 处决杀敌 | A：execute_kill() 专用接口（绕过 take_damage no-op 红线） | `combat_entity.gd`（additive） | 0.5d |
| 玩家无敌 | A：set_invincible(seconds) 复用既有无敌期 | `combat_entity.gd`（additive） | 0.5d |
| 疲惫起身 | A：实体数据层（recover_from_break + 乘数下沉 take_stance_damage） | `combat_entity.gd`（additive） | 1d |
| 淡出演出 | A：独立 ExecutionFade（墙钟驱动，与时间缩放解耦） | `execution_fade.gd` | 0.5d |
| 演出参数化 | A：constants「处决演出」分区 + DebugCanvas.get_value | `constants.gd`（追加） | 0.5d |
| **合计** | | | **3d**（与 estimate 3d 对齐） |

---

## 5. 边界条件与验收标准

### 5.1 验收条件（AC checklist，源自 issue body）

- [ ] **AC1: 敌人 stance_break 后 3s 内按 execute 键触发处决动画并杀敌**
  - 验证：单测断言时序（armed → attack_pressed → enemy 进入 execute 态（state_changed "stance_break"→"execute"）→ execute_kill 发出 died(true) → 全程恰好一次）；距离外按攻击键不触发（正常 attack 流程）；窗口过期（≥3.0s）后按攻击键不触发（走起身路径）
- [ ] **AC2: 处决期间玩家与目标均无敌，处决后目标淡出消失**
  - 验证：触发瞬间玩家 set_invincible 生效（take_damage no-op 断言）；目标 execute 态 take_damage no-op（#575 既有断言保留）；execute_kill 后 ExecutionFade alpha 1→0 0.3s → 节点释放（单测注入 tween 或直接断言 fade 完成回调）；淡出期间玩家无敌窗口未过期
- [ ] **AC3: 崩解后 3s 未执行，敌人起身并恢复 50% 架势，且 5s 内疲惫（受架势伤害+20%）**
  - 验证：armed 到期 → recover_from_break 恰好一次（stance == 0.5 × stance_max，幂等防双写）；exhausted=true 期间 take_stance_damage(10) 实际扣 12（×1.2）；5s 到期后乘数恢复 1.0；起身后 AI 恢复行动（_dead=false、move_intent 可再次置位）
- [ ] **AC4: 处决触发 SW-008 的强力慢动作与火花，持续时间 0.6s**
  - 验证：触发序列调 trigger_feedback("execute") 恰好一次（ReactionController 侧 S 级矩阵 #654 已实现，编排器只传参）；慢动作时长候选 [400, 500, 600]ms 进「处决演出」分区 # DRAFT（不裁决）；TimeScaleStack 嵌套恢复断言（#579 既有 AC4 保留）
- [ ] **AC5: E2E 截图提交用户裁决：处决瞬间构图符合『雪夜+血色+水墨』审美许可**
  - 验证：实验 3 截图产出（处决瞬间：火柴人斩落 + 刀光弧线 + 血色粒子 + 雪幕 + 冷月光背景）；review agent 提交用户裁决；反例断言（无夸张喷血/无奥特曼发光——截图分析 + 人工）

### 5.2 边缘情形（≥5）

1. **处决窗口与状态自动退出同帧竞态**——CombatStateStanceBreak 3.0s 自动退 idle 与编排器 armed 3.0s 到期同源同值（STANCE_BREAK_RECOVERY_SEC 互引）：编排器以 `state_changed` 观察为准（敌人已回 idle → armed 立即失效），恢复路径幂等（recover_from_break 只执行一次，防双写）
2. **玩家 attack 按下瞬间敌人已起身**——armed 过期但 state 仍是 stance_break（同帧边界）：编排器按 armed 为准（攻击不触发处决，走正常 attack 流程，CombatJudge 正常登记窗口）
3. **处决触发瞬间玩家先死**——玩家 died 后 attack_pressed 仍可能到达：编排器守卫 `player.state_name != "dead"`，玩家 dead → 处决不触发（防「尸体处决」演出）
4. **敌人 execute_kill 后淡出期间二次事件**——died(true) 后 _is_final_dead 停摆：编排器 unbind 敌人（防信号泄漏）；淡出期间任何 stance/伤害信号 no-op（实体已停摆）
5. **距离边界**——|dx| 恰等于 EXECUTE_RANGE_PX：闭区间（≤）触发；1px 之外不触发（与 #577 弹反窗口闭区间语义一致）
6. **处决慢动作 0.05x 期间淡出**——ExecutionFade 用墙钟（Time.get_ticks_msec）驱动而非 _process delta（时间缩放不影响墙钟）：慢动作 0.6s 内淡出照常完成，不卡顿（对齐 TimeScaleStack 墙钟兜底哲学）
7. **exhausted 5s 到期与再次崩解重叠**——敌人疲惫期再次被崩解（乘数 1.2 加速）：break_stance 幂等覆盖 exhausted（新一轮崩解 → 处决优先，疲惫标志在 execute_kill/recover 时正确复位）
8. **HUD 提示与处决竞态**——处决提示显示中玩家按攻击：_on_player_state_changed 自动隐藏（#627 已实现）；处决成功 → 击杀提示接管；两者不会同屏残留
9. **单目标绑定**——MVP 单敌人：编排器只 bind 一个敌人；多敌人场景（#585 组装扩展）需按距离最近/锁定目标选择，PRD 预留 bind_enemy 幂等重绑语义
10. **headless 无场景树**——编排器 _process(delta) 手动推进（对齐 ReviveOrchestrator 测试模式），零 SceneTree/autoload 依赖；Time.get_ticks_msec 测试注入可控

### 5.3 失败路径（≥3）

1. **误用 take_damage 处决杀敌 → 静默失败**（execute 态 no-op 红线）：单测防回归——execute 态 take_damage(999) 后 hp 不变、无 died 信号；execute_kill() 后 died(true) 恰好一次 + state 保持 execute
2. **编排器信号泄漏**（敌人 queue_free 后回调访问已释放对象）：bind/unbind 模式（对齐 ReviveOrchestrator.unbind_player 先例）+ is_instance_valid 守卫；敌人 died 时编排器自动 unbind
3. **起身恢复双写竞态**（状态机自动退出 + 编排器到期同时调恢复）：recover_from_break 幂等（exhausted 已置位或 stance 已恢复 → no-op）
4. **慢动作卡死**（0.05x 期间漏恢复）：TimeScaleStack 墙钟兜底（#579 已交付 AC4 机械保证）；编排器不直接写 Engine.time_scale（红线：只经 trigger_feedback → TimeScaleStack）
5. **E2E 截图抓不到处决瞬间**（5 帧动画 + 慢动作窗口 < settle 间隔）：实验 3 rig 用「冻结效果帧」模式（对齐 #579 实验 4 兜底）——把时间栈暂停，让刀光/血色粒子/斩落姿态停留在画面中供截图

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 | 说明 |
|------|------|:----:|------|
| #575（CombatEntity + 11 态状态机） | ✅ merged #618 | 无 | 6 信号契约 + stance_break→execute 拓扑 + take_damage execute no-op 红线（本 issue 接口扩展的基座） |
| #577（判定系统） | ✅ merged #626 | 无 | stance_broken 幂等转发 = 处决窗口开启信号；判定器对处决态实体跳过受击 |
| #579（打击反馈） | ✅ merged #654 | 无 | S 级 execute 反馈（刀光/血色粒子/hit-stop/慢动作/屏震）+ TimeScaleStack；编排器只调 trigger_feedback 一个入口 |
| #574（火柴人动画） | ✅ merged #612 | 无 | anim_execute clip（5 帧上撩→斩落）+ SwordArc 刀光（S 级复用） |
| #578（两条命复活） | ✅ merged | 无 | ReviveOrchestrator bind 模式 = 编排器架构先例；玩家复活路径与处决不冲突（守卫 5.2-3） |
| #581（敌AI） | ✅ merged #638 | 无 | stance_break/execute 停走 + died 禁用已内置；起身后 AI 自然恢复 |
| #584（数值 DRAFT 定稿） | ⏳ OPEN | Low | 处决演出常量同样走 # DRAFT 通道；调参面板 F1 热更新直接作用于处决参数 |
| #585（组装 MVP 闭环） | ⏳ OPEN | Med | 编排器实例化 + bind 接线（§8 清单）；**本 issue 不阻塞——编排器 bind 模式与场景解耦，测试/E2E rig 独立验证** |
| #593（音效系统） | ⏳ backlog | Low | 处决音效 hook 预留（trigger_feedback data 透传），本 issue 不发声 |
| SW-019（Boss/精英处决演出强度） | ⏳ backlog | Low | 消费「处决演出」分区常量，编排逻辑零改动（§4.5 扩展点） |

### 6.2 开源调研结果（issue 🔍 段要求——PR 必须说明）

GitHub API 检索（2026-08-20，`gh api search/repositories`）：

| 检索词 | 结果 | 结论 |
|--------|------|------|
| godot execution combat | 0 个仓库 | 无直接可复用方案 |
| godot finisher move | 0 个仓库 | 无直接可复用方案 |
| godot deathblow | 0 个仓库 | 无直接可复用方案 |
| godot souls-like 2d | `zakkor/dungeon` ⭐8（top-down souls-like）等 6 个 0-8⭐ 个人项目 | 均无成熟的「架势崩解 → 处决」子系统，无 Godot 版忍杀参考实现 |

**结论：** Godot 社区**不存在成熟的开源处决/finish-move 实现**（与 #579 调研结论一致：hit-stop/spark/parry 均无成熟 addon）。**自研 + 机制借鉴**：只狼忍杀语义（sekiro-tuning-reference：崩解 → 一击必杀 + 演出；铁律 5「处决是奖励不是补刀」）+ 视觉配方 §7（hit-stop + 时间缩放 + 刀光 + 白刃斩后雪粒子静止帧），复用项目内已交付的 SwordArc / TimeScaleStack / CombatStateExecute / anim_execute——**零件全是自研，编排也是自研，零第三方依赖**（#572 不引 addon 红线）。

### 6.3 依赖链图

```
#575 实体+11态 ──┐
#577 判定(stance_broken) ──┼──► #580 处决系统（本 issue）──► #585 组装闭环
#579 反馈(S级execute) ──┘        │
#574 动画(anim_execute) ──┐      ├──（数值定稿）── #584
#578 复活(bind先例) ───────┘      ├──（演出强度扩展）── SW-019 Boss/精英
#581 敌AI（停走/禁用配合）──┘      └──（音效 hook）── #593
```

---

## 7. Spike / 实验（deep 必填，≥3 实验）

### 实验 1：处决触发时序 headless 全链路（AC1/AC2 核心验证）

- **要回答的问题：** 编排器能否在 headless 环境（无场景树）下确定性完成「stance_broken → armed → attack_pressed → execute 转移 → execute_kill → died」全链路，且每步恰好一次？
- **方法：** 直接 new ExecutionOrchestrator + 两个 CombatEntity（玩家/敌人，headless 免树）+ 手动 `_process(delta)` 推进（对齐 ReviveOrchestrator/test_combat_entity _advance 模式）；注入 stance_broken → 推进至 3.0s 窗口内 → 注入 attack_pressed（距离内）→ 断言：玩家 set_invincible 生效（take_damage no-op）、敌人 state_changed "stance_break"→"execute"、execute_kill 后 died(true) 恰好一次、state 保持 execute、trigger_feedback("execute") 恰好一次（mock ReactionController）。
- **预期结果：** 全链路断言通过；边界注入（距离外 / 窗口过期 / 玩家 dead）各自走正常路径（attack 流程 / 起身恢复 / 不触发）。
- **对方案的影响：** 验证 4.1 方案 A 编排器 + 4.2 方案 A execute_kill 可行；若失败 → 回退检查请求转移时序（execute_kill 与 request_transition 的顺序）。

### 实验 2：疲惫起身数值闭环（AC3 验证）

- **要回答的问题：** 「3s 起身恢复 50% 架势 + 5s 疲惫 ×1.2 增伤」的数值语义在实体数据层（4.4 方案 A）是否正确且幂等？
- **方法：** 单测：敌人 stance_break → armed 到期 → recover_from_break 恰好一次（stance == 0.5 × stance_max）；exhausted=true 期间 take_stance_damage(10) → stance 实际扣 12（断言 stance_changed 信号值）；推进 5s（EXECUTE_EXHAUSTED_SECONDS）→ 乘数恢复 1.0；双调 recover_from_break → no-op；起身后再次崩解（乘数加速路径）→ 新一轮 break_stance 幂等覆盖。
- **预期结果：** 数值断言全绿；幂等防双写成立；起身后 AI 可恢复行动（move_intent 可置位）。
- **对方案的影响：** 验证 4.4 方案 A（乘数下沉实体层）；若 exhausted 到期与再次崩解竞态失败 → 调整到期清除时机（break_stance 时清 exhausted）。

### 实验 3：处决构图 E2E 截图（AC5 用户裁决素材）

- **要回答的问题：** 能否产出「雪夜 + 血色 + 水墨」处决瞬间的稳定截图供用户裁决？构图是否克制（无夸张喷血/无奥特曼发光）？
- **方法：** 复用/扩展 E2E rig：battle_stage 背景（雪幕 + 冷月光 + 水墨晕染，#582/#583 已交付）+ 玩家/敌人火柴人 + 处决注入（敌人 execute 态 + 刀光弧线 trigger_burst + 血色粒子 burst + 慢动作冻结帧）——新增 e2e_shots.json execution 组（shot：处决斩落瞬间 / 淡出消散瞬间，settle_frames 覆盖演出窗口，「冻结效果帧」模式兜底）；截图走现有 analyze_bmp.py 4 重防伪断言 + 反例断言（血色饱和度上限、无全屏发光）。
- **预期结果：** 两张稳定截图产出；review agent 提交用户裁决（brief B3 通道：处决特写构图 = 截图证据 + 用户裁决）。
- **对方案的影响：** 验证 AC5 验收通道成立；若截图构图不成立（血色过重/构图杂乱）→ 调整血色粒子参数候选（# DRAFT）提交用户，不推翻机制。

### 实验 4：处决期间玩家无敌与判定器交互（AC2 + AC4 组合验证）

- **要回答的问题：** 处决演出期间（慢动作 0.05x-0.1x + 玩家无敌窗口）玩家受击链路是否全部 no-op？时间缩放嵌套是否安全恢复？
- **方法：** 组合测试：触发处决（慢动作 0.1x 0.6s + 玩家 set_invincible）→ 期间注入敌人攻击窗口命中玩家（CombatJudge.resolve_attack）→ 断言玩家 0 伤害、0 架势扣减、无 hit_landed 事件；TimeScaleStack push/pop 序列（0.05 hit-stop → 0.1 慢动作 → 逐层 pop → 终值 1.0，墙钟兜底漏 pop 用例）；淡出墙钟驱动断言（慢动作期间 ExecutionFade 照常推进）。
- **预期结果：** 玩家受击全 no-op（判定器守卫 + 实体无敌双保险）；时间缩放恢复 1.0 无卡死（#579 AC4 既有断言 + 处决参数组合）；淡出不因慢动作卡顿。
- **对方案的影响：** 验证 4.3 方案 A（set_invincible）与淡出墙钟设计；若判定器对无敌玩家仍发事件 → 检查 resolve_attack 守卫顺序（#577 边界表「无敌期受击 → 判定器跳过」）。

---

## 8. 交接上下文（给 plan agent 的手记）

### 系统状态（2026-08-20，origin/main e0939e6）

- **处决链路零件全部就绪**：stance_broken 信号（#575/#577 幂等转发）、execute 状态拓扑（#575，stance_break→execute 表内）、anim_execute 5 帧动画（#574）、S 级 execute 反馈（#579/#654，trigger_feedback 单入口）、HUD 处决提示（#627 自动显隐）、杀敌常量 SWORD_DAMAGE_EXECUTE=999（#584）。
- **本 issue 交付物**：ExecutionOrchestrator（编排器）+ 3 个 CombatEntity additive 接口（execute_kill / set_invincible / recover_from_break）+ ExecutionFade（淡出）+ constants「处决演出」# DRAFT 分区 + test_execution_orchestrator.gd + e2e execution 组 shot。
- **未落地（不在本 issue 范围）**：战斗场景组装（#585 OPEN）、架势自然回复消费（POSTURE_RECOVERY_* 零消费方，归 #585/后续）、Boss/精英演出强度（SW-019）。

### 关键红线（plan agent 必须逐条守住）

1. **take_damage 在 execute 态 no-op 是 #575 无敌红线**——处决杀敌只能走新增 execute_kill()（§4.2 方案 A），禁止改 take_damage、禁止特判魔法值 999。
2. **处决触发契约逐字落实**：stance_broken（#577 事件）+ 玩家 attack_pressed（#573 输入）+ 距离 ≤ EXECUTE_RANGE_PX + armed 窗口（STANCE_BREAK_RECOVERY_SEC 同值互引）——攻击键=处决键，无额外按键。
3. **慢动作时长三处候选冲突（0.1/0.6s vs 0.05/0.5s vs 0.2/0.4s）**——全部并列为 EXECUTE_SLOWMO_SCALE/MS # DRAFT 候补，实现期禁止二选一偷定；机制走 #579 TimeScaleStack（编排器禁止直写 Engine.time_scale）。
4. **EXECUTE_RANGE 单位坑**——1.2 语义为米，Godot 场景 1 单位=1px，派生 EXECUTE_RANGE_PX=120（# DRAFT 候补，比例待用户裁决）。
5. **数值全部 # DRAFT 进「处决演出」分区**，消费方经 DebugCanvas.get_value 读值（热更新优先）；定稿归 #584/用户，本 issue 不裁决。
6. **编排器 bind 模式与场景解耦**（#578 ReviveOrchestrator 先例）——#585 组装只做实例化 + 接线，本 issue 测试/E2E 独立验证。
7. **契约只订阅不改名**：事件名（stance_broken/died）、状态名（execute/stance_break）、反馈入口（trigger_feedback("execute")）以既有实现为准。

### 给 #585 组装的接线清单（处决部分）

- 实例化 ExecutionOrchestrator（Node）+ `bind_player(player_entity)` + `bind_enemy(enemy_entity)` + `bind_input(input_controller)`（attack_pressed 订阅）+ `bind_judge(combat_judge)`（stance_broken 订阅，或直连实体信号——二选一按 #577 统一事件出口原则，优先 bind_judge）
- 实例化 ExecutionFade 并注入敌人（或编排器内部持有）
- 反馈侧：ReactionController.bind_judge（#579 已有）+ Camera2D 注入 screen_shake（#579 已有）——本 issue 的 trigger_feedback("execute") 依赖这些既有接线
- 处决提示/击杀提示：Hud 已自动消费（bind_player/set_target_enemy 已有）——零额外接线

### 下一步与风险

- **下一步**：#585 组装（把编排器 + 判定器 + 反馈 + 实体 + 场景全接起来，闭环验收「出生→遇敌→弹反→崩解→处决→击杀」）；#584 用户裁决处决演出数值；SW-019 Boss/精英演出强度扩展。
- **主要风险**：① execute_kill 与 request_transition("execute") 调用顺序（先转移后杀敌，保持演出态）；② armed 窗口与状态机 3s 同源互引（同帧竞态靠幂等恢复兜底）；③ E2E 处决构图是否通过用户审美裁决（AC5 是 taste 通道，机制先行、参数可调）。
- **测试挂载**：`tests/run_tests.gd` 追加 `_run("res://tests/test_execution_orchestrator.gd", "ExecutionOrchestrator")`；实验 1-4 对应用例分组（触发时序 / 疲惫数值 / 无敌交互 / 淡出清理）。

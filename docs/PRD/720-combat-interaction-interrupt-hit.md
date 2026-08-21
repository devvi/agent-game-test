# PRD #720 — [Bug] 战斗交互：敌人接近后停止不出招（打断循环）+ 玩家攻击难以命中（facing/拼刀/击退）

> **Issue:** #720
> **标签:** bug, workflow/research, priority/high, gameplay, version/mvp（issue 无 `depth/*` 标签，参照 #682/#703/#713 先例取 `depth: standard` → §1–6 + §8 必填；§7 可选，本 PRD 含 3 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-21
> **所有权:** `content_ownership: mechanical`（打断循环/自动面向/范围对称=机械工程；手感数值（击退衰减/停距候选）全部 # DRAFT 只读，定稿归 #584 taste-draft 队列）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + `default_branch: main` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian/Knowledge Ocean/` + `~/Documents/Obsidian Vault/`：wiki grep 只狼/弹反/拼刀 → `wiki/游戏设计理念.md`（只狼=「机制作为修辞」）、`wiki/JRPG战斗系统演变.md`（弹反/闪避=时机判定、难度=机制理解）；raw grep 拼刀/弹反/敌人/AI → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（「弹反/闪避=时机判定」动作进阶层 + 分层设计、AI 辅助强度可调））+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：弹反窗口 10-14 帧、受击双重惩罚、处决是奖励不是补刀、调参优先级）+ 同链 PRD/DESIGN（#577/#581/#584/#585/#682/#703/#713 全读）+ origin/main 源码实测（444e71d，combat_judge.gd / enemy_ai.gd / enemy_ai_states.gd / combat_entity.gd / combat_state_table.gd / constants.gd / player_controller.gd / combat_attack_window.gd 逐行核对）
> **来源:** 用户实机验证反馈（2026-08-21，#703/#704 修复后）：敌人靠近后停止不出招 + 玩家攻击难以命中。#703（PR #710）/#704（PR #709）已 merge 生效，行为驱动链已通，但战斗交互手感仍不可玩。
> **前置依赖:** #703（CLOSED，PR #710 merged：decide 运行时驱动链已生效）、#682（CLOSED，PR #695 merged：击退/蓄力重斩/架势恢复）、#577（CLOSED，PR #626 merged：判定层）、#581（CLOSED，PR #638 merged：敌 AI 行为 FSM）、#585（CLOSED，PR #666 merged：MVP 组装）——全部满足；#718（OPEN，stagger→stance_break 非法转移，独立研究轨道，见 §6.1）

---

## 1. 问题定义

### 1.1 现状（2026-08-21 worktree 侦查 @ origin/main 444e71d）

**一句话现状：** 战斗判定与 AI 驱动链本身全部正常（#703 修复后敌人会索敌、会出招、玩家命中判定逻辑经 headless 验证 hit_landed 正确触发），但**四个交互层缺陷叠加**导致用户实机体验「敌人停止不出招 + 玩家打不到」：

1. **打断循环（敌人不出招的根因）**：敌人 Chase 停距（80px）→ AttackState 蓄力（windup 12/20 帧）→ 玩家在蓄力期命中 → 敌人进入 stagger（0.2s）→ `enemy_ai_states.gd AttackState.update` 检测到实体非 idle/move/attack/heavy_attack → **连段作废回 Chase** → 冷却 1.5s 后再蓄力 → 再被打断。玩家视角：敌人「一直停止不出招」。
2. **facing 挥空（玩家打不到的根因之一）**：`combat_judge.gd` 要求攻击方向 == 敌人相对方向（`rel_dir != w.direction → 挥空`）。玩家**站桩攻击时 facing 不更新**（facing 仅在 `_bridge_poll` 移动轴非零时更新）→ 面向错误必挥空。设计行为（只狼式需转身），但无任何辅助反馈，用户感知为「打不到」。
3. **拼刀（玩家打不到的根因之二）**：双方攻击窗口同帧 active → clash（拼刀）——双方各扣 10 架势不掉血。玩家连续攻击与敌人攻击窗口重叠时反复拼刀，用户感知「打不出伤害」。
4. **击退拉距（玩家打不到的根因之三）**：玩家命中 → 敌人受击击退 40px（#682 ENEMY_KNOCKBACK_PX）→ 连续攻击时敌人被逐步推出 HITBOX_RANGE=80 判定范围 → 后续攻击挥空。

| 组件（文件） | Issue | 当前状态 | 与 #720 的差距 |
|------|-------|:-------:|------|
| `gdscripts/combat_judge.gd`（resolve_attack，第 84-95 行） | #577/#626 | ✅ 命中/弹反/拼刀/格挡/受击五结果裁决 + 距离/facing 双校验逻辑正确（headless 测试验证 hit_landed 正常） | ❌ **无 facing 容差/自动转向机制**——facing 不符直接挥空且零反馈；clash 判定无「玩家优先」设计 |
| `gdscripts/enemy_ai_states.gd`（AttackState.update，第 120-160 行） | #581/#638 | ✅ 三选一出招（蓄力/突刺/三连砍）+ 冷却 1.5s + 连段中断回 Chase | ❌ **无霸体/抗打断**——实体进入 stagger 即连段作废回 Chase → 打断循环（每次蓄力都被玩家普攻打断） |
| `gdscripts/combat_entity.gd`（take_damage，第 132-150 行） | #575/#618 | ✅ 受击进入 stagger（idle/move/attack/heavy_attack 四态可被打断） | ❌ **attack/heavy_attack 蓄力期无抗打断区分**——普攻与弹反同样打断，玩家无脑连打即可锁死敌人 |
| `gdscripts/combat_entity.gd`（_bridge_poll，第 200-210 行） | #575/#618 | ✅ 移动轴更新 facing | ❌ **站桩攻击不更新 facing**——玩家面向敌人攻击时若 facing 相反必挥空 |
| `gdscripts/enemy_ai.gd`（_on_judge_hit_landed + _apply_movement） | #682/#695 | ✅ 受击击退 40px + DECAY 衰减，仅 stagger 期间位移 | ⚠️ 击退把敌人推出攻击范围 → 连续攻击挥空；数值 # DRAFT 候选待 #584 |
| `gdscripts/constants.gd` | #584/#609 | ✅ ENEMY_ATTACK_RANGE=80 = HITBOX_RANGE=80（停距=可命中边界） | ⚠️ 对称但无缓冲——敌人停距恰在玩家判定边界，任意位移（击退/玩家前移）即出范围 |
| `gdscripts/combat_state_table.gd` | #575/#618 | ✅ 11 态转移拓扑 | ❌ **stagger: [idle, dead] 不含 stance_break**——stagger 中架势归零 → 崩解请求被拒 + warning（#718，独立轨道） |

**核心缺口（本 PRD 的增量工作，共 4 个方向，issue body 明示「用户拍板后实施」）：**

1. **AI 出招霸体/抗打断**（方向 1）——普通攻击不打断蓄力，只狼式「弹反才打断」。
2. **玩家攻击自动面向最近敌人**（方向 2）——攻击瞬间自动转向，消除站桩挥空。
3. **停距与判定范围对称性**（方向 3）——ENEMY_ATTACK_RANGE=80 与 HITBOX_RANGE=80 的边界体验。
4. **击退距离/衰减手感**（方向 4）——击退把敌人推出攻击范围的补偿。

### 1.2 预调查表（bug-pre-investigation-workflow §7）

| Issue 声明 | 预调查结果 |
|-----------|-----------|
| 命中逻辑本身正常：headless 模拟玩家攻击（40px、facing 匹配）→ hit_landed 正常触发（hp=12） | ✅ **属实**（combat_judge.gd resolve_attack 全链路正确；test_combat_judge.gd _test_13/_test_14 覆盖距离挥空与 facing 校验） |
| facing 校验：judge 要求攻击方向 == 敌人相对方向——玩家站着不动攻击（facing 未更新）面向错误 → 挥空 | ✅ **属实**（combat_judge.gd:87-93 rel_dir != w.direction → resolved+return 零事件；combat_entity.gd:200-204 facing 仅移动轴更新） |
| 疑似拼刀：玩家/敌人攻击窗口同帧 → clash（拼刀）——双方扣架势不掉血 | ✅ **属实**（combat_judge.gd _resolve_clash：双方窗口同帧 active → 各扣 CLASH_STANCE_COST=10，不调 take_damage；CLASH_PRIORITY=0 → 弹反优先，clash 次之） |
| 疑似打断循环：Chase 停距 80px → AttackState 蓄力 → 被玩家攻击打断（stagger）→ 回 idle → 再蓄力 → 再被打断 | ✅ **属实**（enemy_ai_states.gd AttackState.update 第 120-130 行：st 非 idle/move/attack/heavy_attack → 回 Chase；combat_entity.take_damage 四态可被打断进 stagger） |
| 击退：玩家命中 → 敌人受击击退（#682 knockback）→ 连续攻击时敌人被击退拉开距离 → 后续攻击出范围 | ✅ **属实**（enemy_ai.gd _on_judge_hit_landed 设 _knockback_vel=40；_apply_movement 仅 stagger 期间位移；HITBOX_RANGE=80 无缓冲） |
| #718（stagger 转换 bug）加剧打断循环 | ✅ **属实但独立**（combat_state_table.gd stagger: [idle, dead] 无 stance_break——stagger 中架势归零 → request_transition("stance_break") 被拒 + push_warning + is_stance_broken 置位但状态不转移。**#718 是独立 OPEN issue 且同样 workflow/research 轨道，本 PRD 不重复设计其修复**，见 §6.1 边界） |

**Stale claims：无。** issue body 的四项调查结论全部与当前源码（444e71d）一致。

### 1.3 验收条件（issue body 3 条 → 本 PRD 保障）

| # | 验收条件 | 现状 | 本 PRD 保障 |
|---|---------|:----:|------------|
| AC1 | 战斗交互可玩（敌人有明确的攻击节奏，玩家能稳定命中） | ❌ 打断循环 + 挥空 | §5.1 AC1：霸体（方向 1）+ 自动面向（方向 2）组合 → 敌人出招节奏稳定、玩家命中稳定 |
| AC2 | 无 #718 的 stagger 转换 warning | ❌ stagger 中崩解请求被拒 + warning | §6.1 边界：#718 独立轨道（本 PRD 不重复修复）；本 PRD 的霸体机制减少 stagger 期间被崩解的场景，但不承诺消除 #718 warning（归 #718 验收） |
| AC3 | 实机战斗循环可玩（接战→互攻→崩解/处决或败北） | ❌ 循环断裂 | §5.1 AC3：互攻成立（敌人出招不被普攻锁死）+ 崩解/处决路径可达（#718 修复后） |

> ⚠️ **AC2 边界说明**：issue body 将「无 #718 warning」列入验收，但 #718 的修复（stagger→stance_break 转移表）属于独立 OPEN issue 的研究轨道。本 PRD 在 §6.1 明确：**#720 不修改 combat_state_table.gd 的转移拓扑**；#720 的霸体机制降低打断频率从而降低触发概率，最终消除 warning 归 #718 验收。

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家主动进攻（MVP 核心手感） | 每次游玩 | 玩家接近敌人 → 敌人 Chase 停距 → 出招蓄力（可读前摇）→ 玩家弹反或侧移躲开 → 反击命中（自动面向，稳定命中）→ 连续削架势 → 崩解 → 处决 |
| B | 敌人进攻节奏 | 每次接战 | 敌人蓄力出招**不被玩家普攻无脑打断**（霸体）→ 玩家必须弹反/闪避应对 → 敌人有明确攻击节奏（出招→收招→冷却→再出招），不再是「蓄力即被打断的木桩」 |
| C | 玩家站桩攻击 | 常见误操作 | 玩家面向错误方向攻击 → 攻击瞬间自动转向最近敌人 → 不再「对着空气挥剑」；转向时机与动画同步 |
| D | 连续攻击追击 | 常见 | 玩家连续攻击 → 敌人被击退但**不立即出范围**（停距缓冲或击退衰减补偿）→ 连段可续 |

---

## 2. 设计意图

### 2.1 为什么现状如此

| 现状 | 来源 Issue | 设计意图（当时） | 为何现在失效 |
|------|-----------|-----------------|-------------|
| judge 要求攻击方向==敌人相对方向，否则挥空 | #577 | 只狼式「转身才能攻击」——防背刺/防无脑连打 | 只狼有转身辅助+敌人攻击节奏完整；本项目无任何面向辅助 → 站桩玩家频繁挥空，感知为 bug |
| 敌人蓄力可被普攻打断（进 stagger） | #575/#581 | 受击打断=合理反馈；#682 蓄力重斩靠 windup 帧数制造可弹反窗口 | 敌人出招频率低（冷却 1.5s）+ 蓄力期长（12/20 帧）+ 玩家可无脑连打 → **每次蓄力都被打断**，敌人永远出不了招 |
| 敌人停距 80px = 玩家 HITBOX_RANGE 80px | #584/#581 | 停距=可命中，对称设计 | 无缓冲：击退 40px 即出范围；玩家前移半步也出范围 → 边界体验极差 |
| 击退 40px + 线性衰减 | #682 | 受击后退反馈（僵直+后退） | 连续攻击下敌人被逐步推出范围，连段断裂 |

### 2.2 为什么现在改

1. **MVP 验收门槛**（#585 AC / GDD 完整路径）：战斗交互可玩是 MVP「核心玩法验证」的硬性验收——「接战→互攻→崩解/处决或败北」循环当前断裂（敌人出不了招=无互攻）。
2. **#703/#704 修复后行为驱动链已通**：敌人会动、会出招、会击退——行为层全部就位，剩下的纯粹是交互层调优，改动面可控。
3. **用户实机验证暴露**：2026-08-21 实机反馈直接点名两个现象（敌人停止/打不到），是「手感验证优先」MVP 策略下的最高优先级反馈。

### 2.3 既有约束

| 约束 | 详情 |
|------|------|
| 判定层事件契约不可破坏 | #577 五结果事件（parry_success/block_held/hit_landed/clash/stance_broken）被 #579 反馈/#574 动画/#593 音效消费——本 PRD 只加机制不删事件 |
| 11 态转移拓扑权威集 | combat_state_table.gd CANONICAL_STATES 与 #574 动画消费逐字对齐——**本 PRD 不增删状态名、不改转移拓扑**（#718 例外，独立轨道） |
| 手感数值 # DRAFT 只读 | 停距/击退/霸体窗口等数值全部标 # DRAFT + 候选集，定稿归 #584（taste-draft 人机共做队列） |
| 只狼体系基准 | 用户 2026-08-19 拍板：手感数值直接参考只狼（sekiro-tuning-reference.md），偏离写理由 |
| headless 可测性 | 所有新机制必须保持 judge/entity 的 headless 纯函数入口可测（现有 1314 单测基线不可破坏） |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/combat_judge.gd` | 判定层 | **修改**：facing 校验增加自动转向支持（方向 2：攻击瞬间若 facing 不符 → 自动修正方向或按最近敌人重定向）；clash 判定保持（方向 1 的霸体在实体层，judge 不变或微调） |
| `shandong-wolf/gdscripts/combat_entity.gd` | 实体层 | **修改**：take_damage 增加霸体判断（方向 1：蓄力期普攻不打断/只扣架势不掉血或按方案）；_bridge_poll 增加攻击自动面向（方向 2） |
| `shandong-wolf/gdscripts/enemy_ai_states.gd` | AI 行为层 | **修改**：AttackState 蓄力期（windup 内）免疫 stagger 打断的处理（方向 1 落地主体）；被打断后行为（回 Chase vs 原地再蓄力） |
| `shandong-wolf/gdscripts/enemy_ai.gd` | AI 驱动层 | **修改**（可选）：击退衰减/停距补偿（方向 3/4）——若采用「击退不推出范围」或「击退后 AI 立即回扑」 |
| `shandong-wolf/gdscripts/constants.gd` | 常量层 | **修改**：新增 # DRAFT 常量（霸体帧数/自动转向开关/停距候选/击退候选），标注候选集，定稿归 #584 |
| `shandong-wolf/tests/test_combat_judge.gd` | 测试 | **修改**：新增自动面向/霸体用例 |
| `shandong-wolf/tests/test_enemy_ai.gd` | 测试 | **修改**：新增「蓄力期被打断不取消」用例（打断循环回归测试） |

### 3.2 新文件

| 文件 | 用途 |
|------|------|
| （无新增 .gd 文件） | 四个方向全部在既有文件内增量修改——不新增组件，控制改动面（与 #703 同策略） |

### 3.3 间接影响模块

| 文件 | 影响 |
|------|------|
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | 自动面向 → facing 变化 → 视觉翻转（#683 已接 facing→scale.x 翻转，零改动自动生效） |
| `shandong-wolf/gdscripts/hud.gd` | 无（事件契约不变） |
| `shandong-wolf/gdscripts/reaction_controller.gd` | 无（消费既有五事件，事件仍发射） |
| `shandong-wolf/gdscripts/execution_orchestrator.gd` | 无（崩解路径依赖 #718 修复后可达） |

### 3.4 数据流影响

```
玩家攻击输入（attack_pressed）
    │
    ▼
CombatEntity.request_transition("attack")   ← 方向2: 进入 attack 前自动面向最近敌人（facing 修正）
    │
    ▼
state_changed → CombatJudge._on_entity_state_changed
    │             └─ 登记 AttackWindow（direction = 修正后 facing）
    ▼
CombatJudge.resolve_attack（命中帧）
    ├── 距离校验（|dx| > HITBOX_RANGE → 挥空）      ← 方向3: 停距候选缩小/加缓冲
    ├── facing 校验（rel_dir != w.direction → 挥空）← 方向2: 攻击瞬间已自动转向 → 命中率提升
    ├── 弹反 → 拼刀 → 格挡 → 受击                   ← 方向1: 敌人蓄力期普攻不打断（霸体在实体层）
    │
    ▼
hit_landed → enemy.take_damage
    │             ├── 方向1: 敌人蓄力期 → 霸体（不转 stagger，只扣架势/或按方案）
    │             └── 普通态 → stagger（既有）
    ▼
hit_landed 信号 → EnemyAI._on_judge_hit_landed → 击退 40px   ← 方向4: 衰减/停距补偿
```

### 3.5 需更新的文档

- [x] `docs/PRD/720-combat-interaction-interrupt-hit.md`（本 PRD）
- [ ] `docs/GAME_DESIGN/shandong-wolf/` 战斗章节（post-merge agent 在 #720 merge 后更新）
- [ ] `docs/TASKS/`（plan agent 产出）

---

## 4. 方案对比（4 子系统，issue body 四方向逐一对比）

> 结构遵循 Patch 19 多子系统 PRD 规则：4.1–4.4 各子系统独立 A/B/C 对比，§4.5 推荐组合表。issue body 明示「用户拍板后实施」——本 PRD 给出技术推荐，方向选择权保留给用户（§5.2 决策点）。

### 4.1 方向 1：AI 出招霸体/抗打断（普通攻击不打断蓄力——只狼式：弹反才打断）

**背景：** 打断循环根因——敌人蓄力期（windup 12/20 帧）被玩家普攻打进 stagger → AttackState 连段作废回 Chase。只狼式解法：蓄力攻击有霸体（poise），普通攻击不打断，弹反/架势崩解才打断。

| 方案 | 描述 |
|------|------|
| **A：蓄力期霸体（推荐）** | enemy 进入 attack/heavy_attack 态且处于 windup 期（前 12/20 帧）→ `take_damage` 不转 stagger（只扣 HP/架势，保留受击反馈事件但不打断动作）；windup 结束后（暴发/收招期）恢复可打断。实现：combat_entity 加 `is_windup()` 判断（读 judge 登记的 AttackWindow.windup 或实体自身计时），take_damage 分支 |
| **B：全攻击期霸体** | 整个 attack/heavy_attack 态（含收招）不可被打断，仅弹反/崩解打断。实现最简（状态名判断即可），但收招期不可打断 → 玩家反击窗口变小，连段体验差 |
| **C：仅蓄力重斩霸体** | 只对 elite charge（ENEMY_CHARGE_WINDUP=20）加霸体，普攻三连砍/突刺维持可打断。改动最小，但三连砍（3×8 帧）仍会被无脑连打锁死——打断循环未根治 |

**Pros/Cons：**

| 方案 | Pros | Cons | Risk | Effort |
|------|------|------|------|--------|
| A | 根治打断循环；只狼式「弹反才打断」成立；蓄力可读前摇保留（玩家仍有弹反窗口）；收招期可打断保玩家反击 | 需区分 windup/暴发/收招三阶段（复用 AttackState._phase 逻辑或 judge 窗口）；弹反打断路径需保留（judge._resolve_parry 直接 request_transition("parry_success") 不受 take_damage 影响，天然保留） | Low | 1-2d |
| B | 实现最简 | 收招期不可打断 → 玩家反击窗口缩小；与 #577 弹反「弹反成功=硬直 1.2s 可安全输出」冲突（弹反后敌人仍在收招霸体） | Med | 0.5-1d |
| C | 改动最小 | 三连砍仍被锁死——用户「敌人一直停止不出招」场景（三连砍打断）未根治 | Med | 0.5d |

**推荐：方案 A。** 理由：① 根治打断循环（用户 AC1 核心诉求）；② 只狼基准对齐（「弹反才打断」是只狼蓄力攻击核心体验）；③ windup 期保留弹反判定（judge 弹反路径独立于 take_damage，不受影响）；④ 收招期可打断 → 玩家反击窗口不缩水。

### 4.2 方向 2：玩家攻击自动面向最近敌人（攻击时自动转向）

**背景：** facing 挥空——玩家站桩攻击时 facing 不更新（仅移动轴更新），面向错误必挥空且零反馈。

| 方案 | 描述 |
|------|------|
| **A：攻击瞬间自动转向（推荐）** | `request_transition("attack"/"heavy_attack")` 时（或进入 attack 态瞬间），若场上存在敌人且玩家 facing 与敌人方向不符 → 自动翻转 facing（一次，攻击全程锁定）。实现：combat_entity 攻击入口处读对手位置（judge 已持有 player/enemy 引用，或 main_battle 注入） |
| **B：攻击全程追踪转向** | 攻击前摇期（windup 8 帧）每帧向最近敌人转向。实现复杂（攻击中改 facing 影响窗口 direction 快照），且「挥剑中途转身」视觉违和 |
| **C：facing 容差（放宽判定）** | judge facing 校验从「==」改为「|dx| 容差」或去掉校验。实现最简但破坏 #577 设计语义（背刺防连打失效），且「挥空」从「打不到」变「转身也能打到」——只狼式转身要求被移除 |

**Pros/Cons：**

| 方案 | Pros | Cons | Risk | Effort |
|------|------|------|------|--------|
| A | 根治站桩挥空；一次转向视觉自然（攻击起手转身）；headless 可测（facing 断言）；与 #683 视觉翻转自动联动 | 攻击瞬间转向若与移动方向冲突需定优先级（攻击转向 > 移动 facing） | Low | 0.5-1d |
| B | 攻击中持续对敌 | 窗口 direction 快照语义被破坏（#577 direction 是登记时快照）；视觉违和；测试复杂 | Med-High | 1-2d |
| C | 实现最简 | 破坏 #577 设计语义；「背刺防连打」失效；与只狼基准偏离 | Med | 0.5d |

**推荐：方案 A。** 理由：① 根治用户「打不到」第一大来源；② 只狼基准（只狼攻击有自动转身辅助，玩家不需要手动转身）；③ 与 #683 facing→视觉翻转零成本联动；④ 一次转向不破坏窗口 direction 快照语义。

### 4.3 方向 3：敌人停距（ENEMY_ATTACK_RANGE=80）与玩家 HITBOX_RANGE=80 的对称性

**背景：** 停距=判定边界无缓冲——敌人停恰在 80px，玩家任意位移（前移/击退）即出范围。

| 方案 | 描述 |
|------|------|
| **A：停距 < 判定范围（推荐）** | ENEMY_ATTACK_RANGE 缩至候选下限（如 60-70px），敌人停距更近 → 玩家攻击必然命中（80px 判定覆盖 60px 停距，含 10-20px 缓冲）。同时敌人出招距离更近 = 压迫感更强（符合 brief「敌人=压迫感来源」）。数值 # DRAFT 候选 [60, 70, 80]，定稿归 #584 |
| **B：判定范围扩大** | HITBOX_RANGE 扩至 90-100px。玩家攻击更远 → 命中更容易，但「空气命中」风险回归（#713 教训：60px 出生点 < 80px 判定=出生即被空气命中），且与 SWORD_LENGTH=88 视觉剑长脱节 |
| **C：维持对称 + 加缓冲逻辑** | 保持 80=80，但在击退/位移后检测「敌人是否出范围」→ 自动回位或允许攻击延伸。实现复杂（位移后补偿逻辑侵入移动层） |

**Pros/Cons：**

| 方案 | Pros | Cons | Risk | Effort |
|------|------|------|------|--------|
| A | 一劳永逸消除边界挥空；压迫感增强（brief 对齐）；数值可调（# DRAFT 候选集）；与 #713 修复不冲突（出生点 200px 已外移） | 敌人停距更近 → 玩家反应时间略减（需要弹反窗口微调，弹反窗口 0.2s 不变仍够） | Low | 0.5d（改常量）+ 测试更新 |
| B | 玩家命中更容易 | 空气命中风险（#713 教训）；与视觉剑长脱节；「打不到」问题部分解决但「挥空边界」仍在 | Med | 0.5d |
| C | 不动数值 | 位移补偿逻辑侵入移动层，与 #682 击退/移动模型耦合；复杂度最高 | High | 2-3d |

**推荐：方案 A。** 理由：① 停距 60-70px < 判定 80px → 天然缓冲（10-20px），连续攻击 + 击退 40px 后仍可能出范围但概率大降；② 敌人停距更近 = 更压迫（brief 明示敌人=『压迫感』来源）；③ 数值 # DRAFT 候选归 #584 定稿；④ 避免方案 B 的 #713 空气命中回归风险。

### 4.4 方向 4：击退距离/衰减手感

**背景：** 玩家命中 → 敌人击退 40px（ENEMY_KNOCKBACK_PX=40，DECAY=3.0 线性衰减）→ 连续攻击下敌人逐步推出 80px 判定范围。

| 方案 | 描述 |
|------|------|
| **A：击退缩短 + 敌人回扑（推荐）** | ENEMY_KNOCKBACK_PX 缩至 20-25px（候选 [20, 25, 40]，# DRAFT）+ 击退结束后 AI 立即回扑（AttackState 被打断回 Chase 后无冷却空窗直接再逼近——现冷却 1.5s 是「再出招」冷却，回扑逼近不受限，Chase 本就无冷却，验证确认）。实际只需缩击退距离即可大幅缓解 |
| **B：击退方向衰减（贴墙/限位）** | 击退距离按剩余距离衰减（敌人靠近场景边界时击退减小）。实现复杂（需要场景宽度/障碍查询） |
| **C：移除击退** | 只留 stagger 硬直。实现最简但 #682 受击反馈「僵直+后退」后半缺失，反馈变弱 |

**Pros/Cons：**

| 方案 | Pros | Cons | Risk | Effort |
|------|------|------|------|--------|
| A | 击退 20-25px + 停距 60-70px（4.3 方案 A）→ 连续攻击最多推出 1 次即出范围但很快回扑；手感直接改善；数值 # DRAFT 可调 | 需验证 Chase 回扑无冷却空窗（代码确认：冷却只 gate AttackState 出招，Chase 逼近无冷却） | Low | 0.5d |
| B | 边界手感精细 | 实现复杂；MVP 单场景边界简单，收益低 | Med | 1-2d |
| C | 最简 | 受击反馈减弱（#682 AC「僵直+后退」后半缺失）；用户「打不到」未直接解决（挥空来自 facing/clash 更多） | Low | 0.5d |

**推荐：方案 A（缩击退为主，配合 4.3 方案 A 的停距缓冲）。** 理由：① 击退 40px → 20-25px 后，配合停距 60-70px，连续攻击下敌人仍基本在判定范围内；② 击退手感保留（#682 反馈不丢）；③ 数值 # DRAFT 候选归 #584。

### 4.5 推荐组合表

| 子系统 | 推荐 | 核心落点 |
|--------|------|---------|
| 4.1 敌人霸体/抗打断 | A：蓄力期霸体 | `combat_entity.gd` take_damage + windup 判断 |
| 4.2 玩家自动面向 | A：攻击瞬间自动转向 | `combat_entity.gd` 攻击入口 facing 修正 |
| 4.3 停距对称性 | A：ENEMY_ATTACK_RANGE → 60-70px | `constants.gd`（# DRAFT 候选） |
| 4.4 击退手感 | A：ENEMY_KNOCKBACK_PX → 20-25px | `constants.gd`（# DRAFT 候选） |

> **组合自洽性：** 4.1（敌人能出招）+ 4.2（玩家能命中）+ 4.3/4.4（命中后连段可续）四个方向互补，共同达成 AC1「敌人有明确攻击节奏，玩家能稳定命中」。任一方向单独实施都不完整（如只做霸体：敌人出招了但玩家打不到；只做自动面向：玩家能命中但敌人出不了招）。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1: 战斗交互可玩（敌人有明确的攻击节奏，玩家能稳定命中）**
  - [ ] 敌人蓄力期（windup 内）被玩家普攻命中 → 不转 stagger、不取消攻击（4.1 方案 A）——蓄力照常完成出招
  - [ ] 敌人蓄力期被玩家**弹反** → 照常打断（judge._resolve_parry 路径保留）
  - [ ] 玩家站桩攻击且敌人不在 facing 方向 → 攻击瞬间自动转向敌人 → 命中（4.2 方案 A）
  - [ ] 敌人停距后玩家攻击必然命中（停距 60-70 < 判定 80，4.3 方案 A）
- [x] **AC2: 无 #718 的 stagger 转换 warning** — ⚠️ 边界：#718 独立轨道，本 PRD 不修改转移拓扑；霸体机制降低打断频率从而降低触发概率，最终消除归 #718（见 §6.1）
- [x] **AC3: 实机战斗循环可玩（接战→互攻→崩解/处决或败北）**
  - [ ] 接战：敌人 Chase 逼近停距（4.3 数值）
  - [ ] 互攻：敌人蓄力出招（霸体保护）↔ 玩家弹反/闪避后反击（自动面向命中）
  - [ ] 崩解/处决：#718 修复后，双方架势归零 → stance_break → 处决/败北路径可达

### 5.2 边界情况

1. **弹反 vs 霸体优先级**：敌人蓄力期玩家弹反 → 必须打断（弹反路径独立于 take_damage，天然满足）——测试用例必加。
2. **自动面向 vs 移动 facing 冲突**：玩家移动中按攻击 → 攻击转向优先；攻击结束后 facing 保持攻击方向（不跳回移动方向）——需定语义并测试。
3. **无敌人时攻击**：场上无敌人（或敌人死亡）→ 自动面向 no-op，保持原 facing。
4. **敌人蓄力期被崩解**：蓄力期敌人架势归零（玩家弹反累计或霸体扣架势）→ 崩解打断霸体（stance_break 优先级 > 霸体）——需确认 break_stance 路径（不经过 take_damage 的 stagger 分支，天然可打断）。
5. **击退后出范围**：停距 60-70 + 击退 20-25 → 单次击退后敌人 80-95px，玩家前移 10-20px 即可续连段；连续击退（多次命中）→ 敌人可能被推出范围 → Chase 回扑（无冷却）再战——「追击—回扑」节奏成立。
6. **玩家蓄力重斩（heavy_attack）是否也自动面向**：是——与普攻同规则（只狼重击同样自动转身）。
7. **霸体期受击反馈**：蓄力期被普攻命中（不打断）→ 是否播放受击反馈（火花/屏震）？建议：扣架势+轻反馈（血/架势条变化可见），但不进 stagger 动画（动作不打断）。——待 implement 定细节，数值/表现归 #584。
8. **headless 兼容**：自动面向/霸体判断不依赖场景树（judge/entity 均 headless 可测）——新用例全 headless。

### 5.3 失败路径

1. **霸体判断误伤**：若 windup 判断实现错位（如收招期也算 windup）→ 敌人收招期不可打断 → 玩家反击窗口消失 → 测试必须覆盖「收招期可打断」反向用例。
2. **自动面向导致 facing 抖动**：攻击瞬间转向后若玩家同时按反方向移动 → facing 冲突抖动 → 需定义优先级（攻击转向锁 > 移动轴），测试覆盖。
3. **停距改小后敌人贴脸**：60px 停距下敌人攻击动画与玩家视觉重叠 → 若观感差，回退 70px 候选（# DRAFT 可调，定稿归 #584）。
4. **#718 未修前崩解路径**：敌人蓄力期被崩解（霸体+崩解并存）→ 若 break_stance 与霸体逻辑冲突（崩解请求被 stagger 拒）→ 仍出现 #718 warning —— 归 #718 修复，本 PRD 测试标注「known limitation」。

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #703（decide 运行时驱动链） | ✅ CLOSED（PR #710 merged） | 无——行为驱动已生效，本 PRD 在其上叠加 |
| #682（击退/蓄力重斩/架势恢复） | ✅ CLOSED（PR #695 merged） | 无——击退机制已就位，本 PRD 只调数值 |
| #577（判定层五事件） | ✅ CLOSED（PR #626 merged） | 无——事件契约不破坏 |
| #581（敌 AI 行为 FSM） | ✅ CLOSED（PR #638 merged） | 无——AttackState 是霸体落点 |
| #585（MVP 组装） | ✅ CLOSED（PR #666 merged） | 无 |
| **#718（stagger→stance_break 非法转移）** | ⚠️ **OPEN（workflow/research 独立轨道）** | **边界：本 PRD 不修改 combat_state_table.gd 转移拓扑**。AC2（无 #718 warning）的最终达成依赖 #718 修复 merge。本 PRD 的霸体机制减少打断频率 → 降低触发概率，但不承诺消除。plan agent 需确认 #718 的 research/plan/impl 进度，若 #718 先 merge 则 AC2 可达；若并行则 #720 impl 测试标注 known limitation |

**依赖链：**

```
#577 判定层 ──► #581 敌 AI ──► #682 精英化 ──► #703 驱动链 ──► #720 交互调优（本 PRD）
                                            └─► #718 stagger→stance_break（并行轨道，AC2 依赖）
```

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| #718（stagger→stance_break） | 高 | AC2 最终达成依赖其 merge；本 PRD 不重复设计 |
| #584（战斗数值定稿） | 高 | 本 PRD 全部 # DRAFT 数值（停距/击退/霸体窗口）定稿归 #584 taste-draft 队列 |

### 6.3 准备

- [x] 确认 #718 状态（OPEN，独立轨道）——§6.1 边界已记录
- [x] 确认 #703/#682 已 merge（行为驱动链生效）
- [x] 确认 judge 弹反路径独立于 take_damage（霸体不破坏弹反打断）

---

## 7. Spike / 实验（depth/standard 可选——本 PRD 含 3 实验提升交接质量，参照 #703/#713 先例）

### 实验 1：打断循环 headless 复现 + 霸体修复验证

- **Question：** 当前打断循环（敌人蓄力→玩家普攻→stagger→回 Chase）能否 headless 稳定复现？霸体修复后是否消失？
- **Method：** test_enemy_ai.gd 新增用例：构造敌人进入 attack 态（windup 期）→ 模拟玩家命中（take_damage）→ 断言敌人**仍保持 attack/heavy_attack**（霸体生效）→ 推进 windup 结束 → 再命中 → 断言进入 stagger（收招期可打断）。
- **Expected Result：** 修复前：windup 期命中即 stagger；修复后：windup 期命中保持 attack，收招期命中进 stagger。
- **Impact on Approach：** 验证 4.1 方案 A 的 windup 边界实现正确性。

### 实验 2：自动面向 headless 验证

- **Question：** 攻击瞬间自动转向后，judge 的 facing 校验是否通过、命中是否成立？
- **Method：** test_combat_judge.gd 新增用例：玩家 facing=-1、敌人在玩家右侧（dx>0）→ request_transition("attack") → 断言 facing 翻转为 +1 → judge 推进到命中帧 → 断言 hit_landed 触发。
- **Expected Result：** facing 自动修正 → 命中成立；反向用例（无敌人）→ facing 不变。
- **Impact on Approach：** 验证 4.2 方案 A 的转向时机（攻击入口 vs 命中瞬间）与优先级。

### 实验 3：停距/击退组合边界验证

- **Question：** 停距 60-70 + 击退 20-25 组合下，连续攻击是否稳定在判定范围内？
- **Method：** headless 模拟：敌人停距 65px → 玩家连续命中 3 次（每次击退 22px，衰减）→ 断言每次命中时 |dx| ≤ 80（HITBOX_RANGE）→ 计算第几次命中后出范围 → 验证 Chase 回扑恢复。
- **Expected Result：** 单次击退 22px 后 dx≈87 > 80 出范围 1 次 → 玩家前移或敌人回扑后恢复；3 次命中中至少 2 次命中（对比现状 40px 击退：3 次全出范围）。
- **Impact on Approach：** 验证 4.3+4.4 组合的自洽性，给出 # DRAFT 数值候选依据。

---

## 8. 交接上下文（plan agent 必读）

### 系统状态

- 战斗判定（#577）、敌 AI 行为（#581）、精英化（#682）、运行时驱动链（#703）、出生点外移（#713）全部已 merge 生效。当前 origin/main = 444e71d。
- **四个交互缺陷并存**：敌人蓄力被普攻锁死（打断循环）/ 玩家站桩挥空（facing）/ 拼刀无感（clash 双方扣架势不掉血）/ 击退推出范围。
- **#718 是独立 OPEN issue（同样 workflow/research）**：stagger→stance_break 转移表缺失。**本 PRD 不修改 combat_state_table.gd**——plan agent 请确认 #718 进度，若已 merge 则 AC2 可达；若并行则 #720 impl 的崩解测试标注 known limitation。

### 核心决策点（issue body「用户拍板后实施」）

| 方向 | 本 PRD 推荐 | 用户可选 |
|------|------------|---------|
| 4.1 霸体 | A：蓄力期霸体 | B：全攻击期 / C：仅蓄力重斩 |
| 4.2 自动面向 | A：攻击瞬间自动转向 | B：全程追踪 / C：facing 容差 |
| 4.3 停距 | A：60-70px | B：判定扩大 / C：缓冲逻辑 |
| 4.4 击退 | A：20-25px | B：方向衰减 / C：移除 |

> 若用户/plan 拍板全部采用推荐组合（A×4），实现顺序建议：4.2（自动面向，独立最小）→ 4.1（霸体，核心）→ 4.3+4.4（数值，合并改 constants + 测试）。

### 实施提示

1. **4.1 霸体落点**：`combat_entity.gd take_damage` 分支——判断敌人是否处于 windup（entity 自身计时 `_elapsed * FRAME_RHYTHM_BASE < windup_frames` 或读 judge 窗口）。注意**弹反路径**（judge._resolve_parry → request_transition("parry_success")）不经过 take_damage，霸体不破坏弹反。
2. **4.2 自动面向落点**：`combat_entity.gd` 攻击入口（request_transition("attack"/"heavy_attack") 或 _on_bridge_attack_pressed）——翻转 facing 前需知道敌人位置（judge 已持有 enemy 引用，或经 main_battle 注入）。headless 测试需手动注入敌人位置。
3. **4.3/4.4 数值**：只改 constants.gd 两个 # DRAFT 常量（ENEMY_ATTACK_RANGE 候选 [60,70,80]、ENEMY_KNOCKBACK_PX 候选 [20,25,40]）+ 更新 test_enemy_ai.gd 停距断言（现断言 `<= attack_range + 2.0`，改常量后自动跟随）。
4. **测试基线**：现有 1314 单测（#703 基线）不可破坏；新增用例全部 headless（test_combat_judge.gd / test_enemy_ai.gd）。
5. **CI 三层门禁**：L0 编译（--check-only）/ L1 smoke / L2 运行时 playthrough——改判定/实体后 L1/L2 必跑。

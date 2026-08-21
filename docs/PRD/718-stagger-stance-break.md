# PRD #718 — [Bug] stagger 态下架势崩解丢失：illegal transition stagger -> stance_break（战斗中崩解不触发）

> **Issue:** #718
> **标签:** bug, workflow/research, priority/high, gameplay, version/mvp（issue 无 `depth/*` 标签，参照 #682/#703/#713 先例取 `depth: standard` → §1–6 + §8 必填；§7 可选，本 PRD 含 3 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-21
> **所有权:** `content_ownership: mechanical`（状态转移拓扑/伤害路径=机械工程；崩解演出节奏归 #580 已定稿，本 issue 零 taste 裁决）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + 默认分支 `main` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（rclone `obsidian:"Knowledge Ocean/"`：wiki 74 笔记 + raw/Bear/：wiki grep 只狼 → `wiki/游戏设计理念.md`（只狼=灵感来源、「游戏机制是超越文本的修辞手段」——崩解是双轨战斗的情绪高潮表达，不是装饰）；raw grep 破防/架势/崩解/Stagger → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md:167`（FF16 **Stagger 系统=破防增伤** ——「崩解后疲惫期更容易被再次崩解」的机制佐证）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：**铁律 6「受击惩罚双重（扣血+扣架势）——纯防御会崩架势，逼玩家进攻」** + 铁律 2「崩解惩罚必须清晰：失衡硬直 2-3s，玩家可从容处决」）+ 同链 PRD/DESIGN（#575/#577/#580/#713 全读）+ origin/main 源码实测（444e71d，combat_state_table.gd / combat_entity.gd / combat_judge.gd / combat_states.gd / execution_orchestrator.gd / test_combat_entity.gd / test_combat_judge.gd 逐行核对）
> **来源:** 用户实机战斗验证发现（2026-08-21）；headless 复现（fight_probe：连续受击触发 warning）。issue body 自带根因定位（状态表 `stagger` 行缺 `stance_break`），预调查逐条核实属实。
> **前置依赖:** #575（CLOSED，11 态状态机+转移表）、#577（CLOSED，PR #626 merged，CombatJudge 判定层）、#580（CLOSED，PR #660 merged，处决系统）、#713（CLOSED，PR #716 merged，出生点外移）——全部满足

---

## 1. 问题定义

### 1.1 现状（2026-08-21 worktree 侦查 @ origin/main 444e71d）

**一句话现状：** 实体处于 `stagger`（受击硬直，12 帧）时，判定层同一命中帧先后调用 `take_damage`（扣血）与 `take_stance_damage`（扣架势，`combat_judge.gd:121-122`）；若架势被扣到 0 → `break_stance()` → `request_transition("stance_break")` → **状态表 `stagger: ["idle","dead"]` 表外拒绝** → `push_warning("illegal transition stagger -> stance_break")` + 状态不漂移 → **崩解不触发**（`is_stance_broken=true` 与 `stance_broken` 广播已发生，但 state 卡在 stagger，12 帧后回 idle——崩解展示、处决窗口、处决连招全部丢失）。

| 组件（文件） | Issue | 当前状态 | 与 #718 的关系 |
|------|-------|:-------:|------|
| `gdscripts/combat_state_table.gd`（TRANSITIONS `"stagger": ["idle","dead"]`） | #575/#618 | ✅ 11 态转移拓扑权威集 | ❌ **bug 源**：stagger 态缺 `stance_break` 出口；注释明言「guard → stance_break 表内（格挡中崩解 = 失衡，优先级高于格挡姿态）」——**同样的失衡优先级语义没有给 stagger** |
| `gdscripts/combat_entity.gd` `take_stance_damage()`（L142-160） | #575/#618 | ✅ stance 扣减 → stance≤0 → `break_stance()` | ⚠️ 无状态守卫：dead/revive no-op，但 **stagger 中照常扣架势 → 归零 → 请求被表拒**（问题触发点） |
| `gdscripts/combat_entity.gd` `break_stance()`（L162-170） | #575/#618 | ✅ 幂等（is_stance_broken 防二次广播） | ⚠️ 先置 `is_stance_broken=true` + 广播 `stance_broken` 再请求转移——**转移被拒时标记/广播已发生**（副作用先行） |
| `gdscripts/combat_judge.gd` 受击兜底（L120-122） | #577/#626 | ✅ `take_damage` + `take_stance_damage` 同帧先后调用（血+架势双重惩罚=铁律 6） | ⚠️ **主要触发路径**：stagger 中二次受击 → take_damage 不再进 stagger（正确），但 take_stance_damage 照常扣 → 归零 → 请求被拒 |
| `gdscripts/combat_judge.gd` guard 路径（L116）/ parry 路径（L162）/ clash 路径（L179-180） | #577/#626 | ✅ 其他 take_stance_damage 调用方 | ⚠️ 次触发路径（stagger 中 clash/guard 扣架势归零同理会撞表） |
| `gdscripts/combat_states.gd` `CombatStateStagger` | #575/#618 | ✅ `STAGGER_FRAMES(12)` 后自动退出 → idle | ⚠️ 退出时无 pending 检查（方案 B 的挂载点） |
| `gdscripts/execution_orchestrator.gd`（L6-20 armed 窗口） | #580/#660 | ✅ `stance_broken` → armed → attack_pressed → 处决 | ❌ **受害方**：崩解不触发 → stance_broken 虽广播但实体状态错误 → 处决连招断裂 |
| `gdscripts/stick_figure_controller.gd` `consume_state()` | #574/#612 | ✅ 11 态动画契约（切状态即切 clip） | ⚠️ 方案 A 需确认 stagger→stance_break 切帧无异常（#574 契约内，风险 Low） |
| `tests/test_combat_entity.gd`（C1/C2/C3 + B2） | #575/#618 | ✅ 现有覆盖：damage→stagger / stagger 自动退出 / guard 不硬直 / stance_break 红线 | ❌ **缺「stagger 中崩解」用例**（issue AC3 要求补） |

**核心缺口：** 转移表拓扑与伤害路径的**语义不一致**——铁律 6 要求「受击双重惩罚（扣血+扣架势）」在连续受击下依然成立（stagger 中再受击继续削架势 → 崩解），但转移表把 stagger 视为「完全受控态」（只允许 idle/dead 退出）。`#577` 已为 guard 裁决了「崩解优先级高于格挡姿态」（guard→stance_break 表内），**stagger 缺同样的裁决**——这是 #575 设计时的盲区：stagger 仅 12 帧且当时判定层未落地连击，未预见到「stagger 中二次受击架势归零」场景。

### 1.2 预调查表（bug-pre-investigation-workflow §Patch 10）

| Issue 声明 | 预调查结果 |
|-----------|-----------|
| 运行时警告 `illegal transition stagger -> stance_break`（战斗中实体处于 stagger 时架势扣到 0） | ✅ **属实**（源码核对：状态表 stagger 行缺 stance_break；take_stance_damage→break_stance→request_transition 无状态守卫） |
| `combat_state_table.gd` TRANSITIONS：`stagger: ["idle","dead"]` | ✅ **属实**（L35 `"stagger": ["idle", "dead"]`，与 DESIGN 575 §2.2 权威表逐字一致） |
| 根因 2：`take_stance_damage` 未处理 stagger 态特殊性 | ✅ **属实**（L142-160 无 stagger 分支；仅 dead/revive no-op + 无敌期 no-op） |
| 影响：硬直中崩解→处决连招中断；双轨战斗连续受击断裂 | ✅ **属实**（execution_orchestrator armed 窗口依赖 stance_broken；状态卡 stagger → 处决不可达） |
| 建议 1：状态表补 `stagger → stance_break` | ✅ **采纳**（§4 方案 A 推荐；与 guard→stance_break 同构） |
| 建议 2：伤害路径 pending_break（stagger 中归零 → 记录，结束后转入） | ✅ **备选**（§4 方案 B） |
| 需同步检查 take_stance_damage 调用时序（judge 受击兜底 vs stagger 中二次受击） | ✅ **已核查**：judge 受击兜底 L120-122 同帧双调用为唯一主路径；guard/parry/clash 路径同构；`take_stance_damage` 有 dead/revive 守卫但**无 execute 守卫**（judge 对处决态目标跳过=双保险，防御性缺口见 §5.2 边界 6） |

**无 stale claims**——issue body 的现象、根因、影响、建议全部与当前代码一致（444e71d）。

### 1.3 验收条件（issue body 3 条 → 本 PRD 保障）

| # | 验收条件 | 现状 | 本 PRD 保障 |
|---|---------|:----:|------------|
| AC1 | 战斗中架势扣到 0（无论是否处于 stagger）→ 稳定触发 stance_break（无 warning） | ❌ stagger 中归零 → warning + 崩解丢失 | §5.1 AC1：状态表补 `stagger → stance_break`（方案 A）+ 新增「stagger 中崩解」实体测试断言：无 push_warning + state == stance_break |
| AC2 | 崩解 → 处决连招完整（#580） | ❌ 崩解不触发 → 处决不达 | §5.1 AC2：stance_broken 广播时序不变 → execution_orchestrator armed 窗口照常开启 → 处决回归测试（test_execution_orchestrator）覆盖 |
| AC3 | headless 战斗测试覆盖「stagger 中崩解」场景 | ❌ 现有 C1/C2/C3 无此场景 | §5.1 AC3：test_combat_entity.gd 追加用例（stagger 中 take_stance_damage 归零 → stance_break 无 warning）+ test_combat_judge.gd 追加连续受击用例（同一实体两帧受击，第二帧扣架势归零） |

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 连续受击崩解（核心 bug 场景） | 高频（连击对抗中） | 玩家/敌人被连击：第一击进 stagger（12 帧硬直）→ 第二击同帧扣血+扣架势 → 架势归零 → **应崩解**（失衡硬直 3s，可处决）。现状：warning + 崩解丢失，12 帧后回 idle 继续挨打 |
| B | 弹反/拼刀链中崩解 | 中频 | 弹反成功扣敌 PARRY_STANCE_DAMAGE / 拼刀双方扣 CLASH_STANCE_COST → 架势归零崩解（idle/attack 态路径现状正常；stagger 中发生则同 bug） |
| C | 崩解→处决完整连招（#580 回归） | 每次崩解后 | stance_broken → armed 窗口（3s）→ attack_pressed → 距离校验 → execute 转移 → 处决演出。本修复必须保证该链不回归 |

## 2. 设计意图

### 2.1 现状为何如此（历史成因）

| 成因 | 说明 |
|------|------|
| #575 设计裁决（DESIGN 575 §2.2 转移拓扑） | stagger 定义为「受击硬直，短暂受控」：转移表保守设计 `["idle","dead"]`——硬直期只允许自然恢复或死亡。**盲区**：未预见到「stagger 中二次受击扣架势归零」——当时（2026-08-19）判定层 #577 尚未落地，攻击窗口/连击/架势扣减路径不存在，stagger 只可能由单次受击进入 |
| #577 裁决「guard → stance_break 表内」 | 格挡中崩解=失衡，优先级高于格挡姿态——**崩解优先级高于姿态的先例已立**；但只覆盖 guard，未覆盖 stagger（判定层落地时 focus 在弹反/拼刀，连击削架势场景未做拓扑扩展） |
| 铁律 6 的实现粒度 | 「受击惩罚双重（扣血+扣架势）」只落在函数层（take_damage + take_stance_damage 同帧调用），**未在状态拓扑层贯通**——函数层语义（连续受击继续削架势）与拓扑层语义（stagger 受控不可出）冲突 |

### 2.2 为何现在改

- **#713 之后战斗闭环完整可玩**：出生→接战→崩解→处决全链已通（#713 PR #716 merged 2026-08-21），用户实机验证进入战斗深度体验阶段，连续受击是高频对抗形态——崩解断裂直接破坏双轨战斗核心循环。
- **mvp 收尾期**（version/mvp）：双轨「削血慢线 + 架势崩解快线」是游戏核心机制（GDD/只狼基准），连续受击不断链是 mvp 验收底线。
- 修复面极小（1 行拓扑 + 注释 + 测试），风险低，收益明确。

### 2.3 先前约束（不得破坏）

| 约束 | 详情 |
|------|------|
| 状态名权威集 | 11 态 canonical 名（#575 红线，与 #574 consume_state 对齐）——**不新增状态名** |
| 转移即查表 | `request_transition` 唯一入口 + 数据驱动表 + 守卫两层（#575 AC2）——修复落在表/守卫层，不改入口架构 |
| 崩解优先级高于姿态 | guard→stance_break 先例（#577）；本修复将同语义扩展到 stagger |
| 处决窗口 | STANCE_BREAK_RECOVERY_SEC=3.0（#580 armed 窗口）——不变 |
| 硬直节奏 | STAGGER_FRAMES=12（#584 DRAFT）——方案 A 不改变硬直时长本身（崩解打断硬直是语义升级） |
| 判定层零改动 | combat_judge.gd 调用时序（血+架势同帧）正确，**不修改**——铁律 6 保留 |

## 3. 影响分析

### 3.1 直接影响

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/combat_state_table.gd` | TRANSITIONS `stagger` 行 | **必改**（方案 A）：`["idle","dead"]` → `["idle","dead","stance_break"]` + 注释（stagger 中崩解=失衡，优先级高于硬直，与 guard 同构） |
| `shandong-wolf/tests/test_combat_entity.gd` | 追加用例 | **必改**：`_test_c4_stagger_stance_break()`（stagger 中 take_stance_damage 归零 → stance_break 无 warning）+ 状态表断言表更新（stagger 行） |
| `shandong-wolf/tests/test_combat_judge.gd` | 追加用例 | **必改**：连续受击场景（第一击进 stagger，第二击扣架势归零 → 崩解） |
| `shandong-wolf/gdscripts/combat_entity.gd` | take_stance_damage / break_stance | **可选加固**（§5.2 边界 6）：take_stance_damage 补 `execute` no-op 守卫（防御性，judge 层已双保险）；方案 A 主路径不改 break_stance |

### 3.2 新建文件

| 文件 | 说明 |
|------|------|
| 无新源码文件 | 修复为 1 行拓扑 + 测试追加（最小侵入） |

### 3.3 间接影响

| 文件 | 影响 |
|------|------|
| `shandong-wolf/gdscripts/combat_judge.gd` | 零改动（调用时序正确，铁律 6 保留） |
| `shandong-wolf/gdscripts/combat_states.gd` | 方案 A 零改动（CombatStateStagger 自然退出逻辑不变；崩解打断由 break_stance 转移触发） |
| `shandong-wolf/gdscripts/execution_orchestrator.gd` | 零改动（消费 stance_broken；时序不变则 armed 窗口照常） |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | 零改动（consume_state 按状态切 clip，stagger→stance_break 切帧契约内） |
| `shandong-wolf/gdscripts/constants.gd` | 零改动（无新常量） |
| `shandong-wolf/gdscripts/enemy_ai.gd` / `main_battle.gd` | 零改动（不感知状态转移表） |

### 3.4 数据流影响

```
攻击窗口命中帧（combat_judge resolve_attack）
    │
    ├── take_damage(w.hp_damage)                        ← 扣血
    │       └── 状态 ∈ {idle,move,attack,heavy_attack} → request_transition("stagger")
    │            （stagger 中二次受击：不进 stagger，保持硬直）✅ 现状正确
    │
    └── take_stance_damage(w.stance_damage)             ← 扣架势（铁律 6 双重惩罚）
            └── stance ≤ 0 → break_stance()
                    ├── is_stance_broken = true
                    ├── emit stance_broken(entity) ──► judge 幂等转发 ──► ExecutionOrchestrator armed 窗口（#580）
                    └── request_transition("stance_break")
                            ├── 现状：stagger 态 → 表外拒绝 + push_warning ❌ 崩解丢失
                            └── 修复后：stagger 态 → 表内合法 → state=stance_break ✅
                                    └── state_changed(stagger→stance_break) ──► consume_state 切崩解动画
                                            └── CombatStateStanceBreak（3s）→ #580 attack_pressed → execute
```

### 3.5 文档更新

- [x] `docs/DESIGN/575-combat-entity-state-machine.md` §2.2 转移表（stagger 行 + 语义注释）——post-merge agent 更新
- [x] `docs/GAME_DESIGN/shandong-wolf/`（状态机章节：stagger 可崩解语义）——post-merge agent 更新
- [x] `docs/PROJECT.md`（本修复一行记录）——post-merge agent 更新
- [ ] 本 PRD 为 issue 唯一研究产物（无其他文档）

## 4. 方案比较

### 方案 A：状态表补 `stagger → stance_break`（推荐）

**描述：** TRANSITIONS `"stagger"` 行追加 `"stance_break"` + 语义注释；`break_stance()` 语义不变（架势归零立即崩解，**打断** stagger 硬直进入崩解失衡）——与 #577 guard→stance_break 完全同构（崩解优先级高于姿态/硬直）。判定层、伤害路径、状态对象全部零改动。

| 维度 | 评估 |
|------|------|
| Pros | 最小改动（1 行 + 注释 + 2 测试）；语义与 guard 先例一致（失衡打断一切动作）；无新状态字段/时序复杂度；铁律 6 双轨惩罚完整保留 |
| Cons | stagger 12 帧硬直被立即截断（动画上硬直→失衡直接切帧）——consume_state 按状态切 clip（#574 契约），切帧风险 Low；需回归确认无动画跳变 |
| Risk | **Low**（拓扑加边，表内语义与 guard 先例一致；测试覆盖新路径） |
| Effort | 0.5 天 |

### 方案 B：伤害路径 pending_break（stagger 中归零 → 记录，硬直结束后转入）

**描述：** `break_stance()`（或 take_stance_damage）检测 `state_name == "stagger"` → 不立即转移，置 `pending_break` 标志；`CombatStateStagger.update` 硬直自然退出前检查 pending → `request_transition("stance_break")`；`stance_broken` 广播延迟到实际转移时（保持时序一致）。

| 维度 | 评估 |
|------|------|
| Pros | 保留完整 stagger 硬直动画（演出上「硬直完才失衡」）；转移时机显式可控 |
| Cons | 新增状态字段 + 广播时机/幂等/边界复杂度（stagger 中 hp 归零 die() 与 pending 互斥、pending 期间处决/复活竞态）；stagger 仅 12 帧（0.2s），延迟转移体感差异极小，复杂度不匹配收益 |
| Risk | **Med**（新状态字段引入时序竞态面；#580 armed 窗口与 pending 转移的交互需额外测试） |
| Effort | 1–1.5 天 |

### 方案 C：stagger 中 take_stance_damage no-op（不扣架势）

**描述：** stagger 态受击不扣架势（连击无法在硬直中积累崩解）。

| 维度 | 评估 |
|------|------|
| Pros | 实现最简单（一行守卫）；warning 消失 |
| Cons | **违背铁律 6**（受击双重惩罚是只狼核心哲学：纯防御/挨打会崩架势，逼玩家进攻）；连续受击完全失去崩解积累 → 连击惩罚消失；设计层面不可接受 |
| Risk | **High**（机制违背，非实现风险） |
| Effort | 0.5 天 |

### 推荐

**方案 A**，理由：

1. **语义同构先例**：#577 已裁决「guard → stance_break 表内（格挡中崩解=失衡，优先级高于格挡姿态）」——stagger→stance_break 是同一裁决对硬直态的推广（崩解优先级高于硬直），拓扑层一致性最强。
2. **最小侵入**：1 行拓扑 + 注释 + 2 测试；判定层/伤害路径/状态对象/编排器全部零改动——回归面最小（mvp 收尾期红线）。
3. **铁律 6 完整保留**：连续受击双重惩罚（血+架势）在硬直中继续成立，崩解立即打断硬直——玩家被连击削到崩解→处决的完整循环不被断链（AC1/AC2 直接满足）。
4. **体感正确**：stagger 中架势归零「立即失衡倒地」符合只狼崩解直觉（失衡打断一切动作）；方案 B 的 0.2s 延迟转移体感无差别，却引入 pending 状态复杂度。

方案 B 作为 plan 阶段的备选（若实现时发现动画层 stagger→stance_break 切帧有不可接受的视觉跳变，再降级 B）；方案 C 明确否决（机制违背）。

## 5. 边界条件与验收标准

### 5.1 正常路径（AC checklist）

- [x] **AC1: 任意状态下架势归零 → 稳定触发 stance_break（无 warning）**
  - `request_transition("stance_break")` 在 idle/move/attack/heavy_attack/guard/stagger 态均表内合法
  - test_combat_entity.gd 新增：stagger 中 `take_stance_damage(stance_max)` → state == "stance_break" + `is_stance_broken == true` + 断言无 push_warning
  - 状态表断言表（test_combat_entity.gd L20-27）同步更新 stagger 行
- [x] **AC2: 崩解 → 处决连招完整（#580）**
  - stance_broken 广播时序不变（break_stance 内 emit 先行，转移紧随）→ ExecutionOrchestrator armed 窗口照常
  - test_execution_orchestrator.gd 回归：stance_broken → armed → attack_pressed → execute 转移链不回归
- [x] **AC3: headless 战斗测试覆盖「stagger 中崩解」**
  - test_combat_judge.gd 新增：第一帧受击进 stagger → 第二帧受击扣架势归零 → 实体进入 stance_break（无 warning）+ judge 幂等转发 stance_broken 恰好一次

### 5.2 边界条件

1. **stagger 中 hp 归零（受击致死）**：`take_damage` 先扣血 → hp≤0 → `die()` → `request_transition("dead")`（stagger→dead 表内合法）→ state=dead；随后同帧 `take_stance_damage` 被 dead 守卫 no-op（combat_entity.gd L143）——**无二次 warning，死优先于崩解** ✅ 现状已正确，回归测试覆盖。
2. **stance_break 中再受击（已崩解）**：`break_stance` 幂等（is_stance_broken 已 true → return）——不二次广播/转移 ✅ 现状已正确（B2 红线测试覆盖）。
3. **guard 中崩解（既有路径）**：guard→stance_break 表内（#577）——修复不触碰该行，回归测试覆盖。
4. **parry_success 中扣架势归零（潜在同类缺口）**：`parry_success: ["idle","attack","heavy_attack","move"]` 表外无 stance_break；理论路径=玩家弹反成功 10 帧内与敌人窗口 clash（双方扣 CLASH_STANCE_COST）且玩家架势恰好归零 → 同款 warning。MVP 1v1 下概率极低（parry_success 10 帧 + 架势恰好归零）——**plan 阶段裁决**：方案 A 可顺手补 `parry_success → stance_break`（同语义）或依赖 judge 跳过（clash 双方非处决态，不跳过）——建议补行（1 字符成本，消灭整类缺口）。
5. **execute 中受击**：judge 对处决态目标跳过（#580 §8 边界）+ take_damage execute no-op（L125）✅ 现状已正确；但 `take_stance_damage` **无 execute 守卫**（L143 仅 dead/revive）——防御性建议补 `execute` no-op（与 take_damage 对齐，防未来直连调用）。
6. **revive 中受击**：take_stance_damage revive no-op（L143）✅ 现状已正确。
7. **敌我对称性**：修复对玩家与敌人实体同样生效（同一类/同一表）——玩家被连击崩解、敌人被连击崩解均正常。

### 5.3 失败路径

1. **表外缺口未清（parry_success）**：若 plan 阶段不补 parry_success 行，该路径仍可触发 warning——测试套件枚举全部 11 态 × 受击归零组合，发现即补（§7 实验 2 输出）。
2. **动画切帧异常**：stagger→stance_break 直接切 clip 若有视觉跳变（consume_state 帧边界）——E2E/用户裁决（本 issue 机械层不裁决视觉，交付 plan 时在 Continuation Context 标注）。
3. **CI 回归**：L0 编译（状态表语法）+ L1 逻辑（实体/判定测试）+ L2 运行时（playthrough）三层门禁；任何一层失败 → self-correct 路径。

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|------|
| #575（状态表+实体） | CLOSED | ✅ 修复载体 |
| #577（判定层） | CLOSED | ✅ 调用时序已核查（无需改动） |
| #580（处决系统） | CLOSED | ✅ 消费 stance_broken，时序不变 |
| #574（动画 consume_state） | CLOSED | ✅ 切帧契约内（方案 A 前提） |
| #713（出生点外移） | CLOSED | ✅ 战斗闭环已通，本修复在其上 |

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|:------:|------|
| 无 | — | 本修复不阻塞任何已知 issue |

### 6.3 依赖链

```
#572 骨架 → #573 输入 → #574 动画 → #575 状态机 → #577 判定 → #580 处决
                                            ↓
                                  #713 出生点（已合并）
                                            ↓
                                  ★ #718 本修复（stagger 可崩解）
                                            ↓
                                （plan → implement → CI → review）
```

## 7. 实验 / Spike（standard 可选——本 PRD 含 3 实验提升交接质量）

### 实验 1：状态表补行后复现原场景（headless）

- **问题**：补 `stagger → stance_break` 后，fight_probe 连续受击场景是否完全无 warning + 稳定崩解？
- **方法**：test_combat_entity.gd 新增用例（stagger 中 take_stance_damage 归零）→ `godot --headless --script tests/run_tests.gd` 跑 L1；观察 stderr 无 `illegal transition` push_warning
- **预期结果**：用例绿 + 零 warning；state 序列 idle→stagger→stance_break
- **对方案的影响**：验证方案 A 主路径；失败则转向方案 B

### 实验 2：全路径表外缺口枚举（11 态 × 扣架势归零）

- **问题**：除 stagger 外，还有哪些态在「受击扣架势归零」路径上表外拒绝（同类 bug）？
- **方法**：枚举 11 个 canonical 态，对每个态模拟 take_stance_damage(stance_max)（绕过守卫直调或构造可达场景），断言 request_transition("stance_break") 结果
- **预期结果**：stagger、parry_success 两处表外（其余态要么表内、要么守卫 no-op）——parry_success 缺口确认，plan 阶段补行
- **对方案的影响**：若发现更多缺口 → 方案 A 一次补全（同一语义），消灭整类 warning

### 实验 3：stagger→stance_break 切帧与广播序列

- **问题**：状态转移与 stance_broken 广播的时序对 #580 armed 窗口是否无损？
- **方法**：test_combat_judge.gd 追加连续受击用例（两帧两次 resolve_attack），断言 state_changed 广播序列（idle→stagger→stance_break）与 stance_broken 恰好一次转发
- **预期结果**：广播序列正确；ExecutionOrchestrator armed 窗口开启；execute 可达
- **对方案的影响**：确认 AC2 成立（崩解→处决链完整）

## 8. 交接上下文（Continuation Context）

**系统状态：** shandong-wolf 战斗系统全链已通（#713 后），唯一已知缺陷为 #718 的 stagger 态崩解丢失——1 行拓扑缺口，根因与修复面已完全定位。

**推荐方案（供 plan agent）：** 方案 A——`combat_state_table.gd` TRANSITIONS `"stagger"` 行追加 `"stance_break"`（`["idle","dead","stance_break"]`）+ 注释「stagger 中崩解=失衡，优先级高于硬直，与 guard 同构（#577）」。附带两个防御性加固（plan 裁决）：
1. `parry_success` 行补 `stance_break`（同语义，消灭 §5.2 边界 4 的同类缺口）；
2. `combat_entity.gd` `take_stance_damage` 补 `execute` no-op 守卫（与 take_damage L125 对齐，§5.2 边界 5）。

**必改测试：** test_combat_entity.gd（状态表断言表 stagger 行 + 新增 `_test_c4_stagger_stance_break`）、test_combat_judge.gd（连续受击崩解用例）；回归 test_execution_orchestrator（AC2 处决链）。

**主风险：**
- 动画层 stagger→stance_break 切帧视觉跳变（#574 契约内 Low；E2E/用户裁决兜底）
- parry_success 缺口若不补，同类 warning 偶发（建议一并补行）

**下一步（plan agent）：** DESIGN 文档——转移表 diff（2 行）+ 测试用例规格 + CI 回归清单；实现面 ≤ 0.5 天。post-merge 需更新 DESIGN 575 §2.2 转移表与 GDD 状态机章节（stagger 可崩解语义）。

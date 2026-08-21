# Design: [Bug] stagger 态下架势崩解丢失：illegal transition stagger -> stance_break（战斗中崩解不触发）

> **Parent Issue:** #718（bug / workflow/plan / priority/high / gameplay / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 确认采纳** —— `combat_state_table.gd` TRANSITIONS `"stagger"` 行追加 `"stance_break"`（`["idle","dead","stance_break"]`，崩解打断硬直=失衡，与 guard→stance_break #577 同构），并采纳 PRD §8 建议的 **2 项防御性加固（plan 裁决）**：① `parry_success` 行同语义补 `"stance_break"`（消灭 §5.2 边界 4 同类缺口——PRD §7 实验 2 预期确认该缺口存在）；② `combat_entity.gd` `take_stance_damage` 补 `execute` no-op 守卫（与 `take_damage` L125 对齐，§5.2 边界 5）。方案 B（pending_break 延迟转移）保留为动画切帧异常时的降级备选；方案 C（stagger 中不扣架势）**明确否决**——违背铁律 6「受击惩罚双重（扣血+扣架势），纯防御会崩架势，逼玩家进攻」。
> **Reference PRD:** `docs/PRD/718-stagger-stance-break.md`（research PR #723 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/575-combat-entity-state-machine.md` §2.2（11 态转移拓扑权威集——本文档是该权威集的补丁）；`docs/DESIGN/577-*`（判定层 guard→stance_break 先例：崩解优先级高于姿态）；`docs/DESIGN/580-*`（处决系统 armed 窗口消费 stance_broken）；`docs/DESIGN/713-enemy-spawn-distance-hitbox.md`（2026-08-21 最新 sibling 文档，格式基准）
> **所有权:** `content_ownership: mechanical`（状态转移拓扑/伤害路径守卫 = 纯机械工程，可自动验证；崩解演出节奏归 #580 已定稿，本 issue 零 taste 裁决——stagger→stance_break 切帧视觉观感归 E2E/用户裁决，PRD §5.3 失败路径 2）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard，照 #682/#703/#713 先例）—— 涉及文件 **4**（2 生产 .gd + 2 测试 .gd）+ ≤4 项实现子任务同属战斗状态机单子系统 → **不产出 TASKS 文档**（skill standard 阈值未触发：文件 <10、无迁移、子任务 <5 且不跨子系统，照 #704/#713 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-718，branch `plan/718-stagger-stance-break`）；**无并行冲突面**（2026-08-21 核验：open PR 仅 #724 plan/719-esc-pause-menu，无任何分支触碰 `combat_state_table.gd`/`combat_entity.gd`）；#720 的 research PR #722 已合并（战斗交互：霸体/自动面向/停距/击退）——其实现 PR 未开，属 implement 阶段后续，与本文档零文件重叠；`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`、`game-env/manifest.yaml` 零影响
> **红线:** 只动 PRD §3.1 列出的文件；**生产改动仅 2 文件**（combat_state_table.gd 2 行拓扑 + combat_entity.gd 1 行守卫）；`combat_judge.gd`（调用时序正确，铁律 6 保留）、`combat_states.gd`（CombatStateStagger 零改动）、`execution_orchestrator.gd`、`stick_figure_controller.gd`、`constants.gd`（无新常量）全部零改动；**不写可运行测试文件**（测试用例描述归本 DESIGN §8，测试代码归 implement agent）；**不 merge 任何 PR**（本 phase 只创建 PR）；PR body 用 `Parent #718`（不带冒号）

---

## 1. 架构总览

**问题本质是「状态转移拓扑与伤害路径的语义不一致」：** 铁律 6 要求受击双重惩罚（扣血+扣架势）在连续受击下依然成立——stagger（受击硬直，12 帧）中二次受击照常扣架势 → 架势归零 → `break_stance()` → `request_transition("stance_break")` → **状态表 `"stagger": ["idle","dead"]` 表外拒绝** → `push_warning("illegal transition stagger -> stance_break")` + 状态卡在 stagger（`is_stance_broken=true` 与 `stance_broken` 广播已发生但转移失败）→ **崩解展示、处决窗口、处决连招（#580）全部丢失**。`#577` 已为 guard 裁决「崩解优先级高于格挡姿态」（guard→stance_break 表内），**stagger 缺同样的裁决**——这是 #575 设计时的盲区：stagger 仅 12 帧且当时判定层未落地连击，未预见到「stagger 中二次受击架势归零」场景。

**设计哲学：修拓扑不修调用时序 —— 把「崩解优先级高于姿态」的既有裁决扩展到硬直态。** bug 的充分必要条件是「stagger 态下架势归零 → 转移请求被表拒」；在状态表给 stagger 加 `stance_break` 出口直接消除拒绝，`break_stance()` 语义不变（架势归零立即崩解，**打断** stagger 硬直进入崩解失衡——与 guard 完全同构），判定层、伤害路径、状态对象全部零改动。同时按 PRD §7 实验 2 的枚举思路补 `parry_success` 同类缺口 + `take_stance_damage` 的 `execute` 守卫，**消灭整类「表外拒绝 + warning」缺口**，而非只修单点。

```text
★ Issue #718 本设计（状态表补边 + 2 项防御加固，判定层零改动）
┌──────────────────────────────────────────────────────────────────────┐
│ 修改前（错误）                          修改后（正确）                   │
│   TRANSITIONS["stagger"]               TRANSITIONS["stagger"]         │
│     = ["idle","dead"]                    = ["idle","dead","stance_break"]│
│   stagger 中架势归零 → 表外拒绝           stagger 中架势归零 → 表内合法    │
│   push_warning + 崩解丢失                state=stance_break → 处决可达   │
│   break_stance(): is_stance_broken=true + emit stance_broken 先行       │
│   （副作用先行，转移被拒 → 标记/广播已发生）  （转移成功后语义完整）          │
│   parry_success 行缺 stance_break        parry_success 补 stance_break │
│   take_stance_damage 无 execute 守卫     take_stance_damage 补 execute │
│   combat_judge.gd / combat_states.gd / execution_orchestrator.gd 全部零改动（铁律 6 保留）│
└──────────────────────────────────────────────────────────────────────┘
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| 11 态转移拓扑权威集（`combat_state_table.gd` TRANSITIONS，`"stagger": ["idle","dead"]` L35） | #575/#618 | ✅ | **改**：stagger 行补 `"stance_break"` + parry_success 行补 `"stance_break"`（2 行 + 注释，唯一生产拓扑改动） |
| `take_stance_damage()`（`combat_entity.gd` L142-160，dead/revive no-op 守卫，无 execute 守卫） | #575/#618 | ✅ | **改**：守卫补 `execute` no-op（1 行，与 `take_damage` L125 对齐）——防御性，judge 层已双保险 |
| `break_stance()`（`combat_entity.gd` L162-170，幂等 is_stance_broken） | #575/#618 | ✅ | **零改动**——语义不变（先置标记+广播 stance_broken，再请求转移；表内合法后副作用与状态一致） |
| 受击兜底（`combat_judge.gd` L120-122 `take_damage` + `take_stance_damage` 同帧先后调用） | #577/#626 | ✅ | **零改动**——唯一主触发路径；铁律 6 双重惩罚正确，问题在拓扑不在时序 |
| guard 路径（`combat_judge.gd` `POSTURE_BLOCK_COST`）/ parry 路径（L162 `PARRY_STANCE_DAMAGE`）/ clash 路径（L179-180 `CLASH_STANCE_COST`） | #577/#626 | ✅ | **零改动**——次触发路径（stagger 中 clash/guard 扣架势归零同理会撞表，拓扑修复后全部表内合法） |
| `CombatStateStagger`（`combat_states.gd` L125-131，STAGGER_FRAMES=12 后自动退出 → idle） | #575/#618 | ✅ | **零改动**——方案 A 由 break_stance 转移打断硬直，无需 pending 检查挂载点（方案 B 才需要） |
| `execution_orchestrator.gd` armed 窗口（L6-20，消费 stance_broken） | #580/#660 | ✅ | **零改动**——广播时序不变 → armed 窗口照常 → 处决链回归验证 |
| `stick_figure_controller.gd` `consume_state()`（11 态动画契约） | #574/#612 | ✅ | **零改动**——stagger→stance_break 切帧在契约内（风险 Low，E2E 裁决兜底） |
| `test_combat_entity.gd` EXPECTED_TRANSITIONS（L20-27，121 对遍历比对）+ C1/C2/C3/D1-D5 | #575/#618 | ✅ | **改**：断言表 stagger/parry_success 行同步 + 新增用例（§8 T1/T6/T7） |
| `test_combat_judge.gd`（_test_1~24，含 _test_15_stance_broken_forward 幂等转发） | #577/#626 | ✅ | **改**：新增连续受击用例（§8 T5）；既有 24 用例零改动回归 |
| `test_execution_orchestrator.gd`（_test_a1_full_trigger_chain） | #580/#660 | ✅ | **零改动回归**——AC2 处决链验证 |

### 1.2 核心缺口与修复决策（codebase 勘探确认 + PRD 断言交叉核对）

| PRD 断言 | 实际代码 | 结论 |
|---------|---------|------|
| `combat_state_table.gd` TRANSITIONS：`"stagger": ["idle","dead"]` | `combat_state_table.gd:35` `"stagger": ["idle", "dead"]`，注释明言 guard→stance_break 表内先例 ✓ | 属实——修复本体（方案 A） |
| stagger 中 `take_stance_damage` 照常扣架势 → 归零 → 请求被表拒 | `combat_entity.gd:142-160` 仅 dead/revive no-op + 无敌期 no-op，无 stagger 分支 ✓ | 属实——问题触发点；方案 A 不改该函数（拓扑修复后请求合法） |
| `break_stance()` 先置标记+广播再请求转移（副作用先行） | `combat_entity.gd:162-170` `is_stance_broken=true` → `emit stance_broken` → `request_transition` ✓ | 属实——转移成功后副作用与状态一致；幂等保留 |
| judge 受击兜底同帧双调用（L120-122）为唯一主路径 | `combat_judge.gd:120-122` `defender.take_damage(w.hp_damage); defender.take_stance_damage(w.stance_damage)` ✓ | 属实——主触发路径；判定层零改动 |
| `take_stance_damage` 无 execute 守卫（防御性缺口） | `combat_entity.gd:142-143` 仅 `dead`/`revive` 守卫；`take_damage` L125 有 execute 守卫 ✓ | 属实——防御加固 2（与 take_damage 对齐） |
| PRD 建议新测试名 `_test_c4_stagger_stance_break` | `test_combat_entity.gd` **已有** `_test_c4_invincible_window`（L349）、`_test_c5_negative_clamp`（L362）——C4 编号被占用 | **差异——设计裁决**：新用例命名 `_test_d6_stagger_break_in_stagger`（归入 Scenario D 架势主路径，与 d1-d5 同域），`_test_c4_*` 编号不动（避免改写既有用例） |
| 建议 1：状态表补 `stagger → stance_break` | 语义与 guard→stance_break（#577）同构，拓扑层一致性最强 ✓ | **采纳**（方案 A，PRD §4 推荐） |
| 建议 2：伤害路径 pending_break | 新增状态字段 + 广播/幂等/竞态复杂度，stagger 仅 12 帧（0.2s）延迟体感无差别 | **降级备选**——仅当动画层切帧出现不可接受跳变时启用（PRD §4 方案 B） |
| 建议 3：stagger 中不扣架势 | 违背铁律 6（纯防御/挨打会崩架势是只狼核心哲学），连击惩罚消失 | **否决**（PRD §4 方案 C） |

> **与 PRD 的差异说明（1 处，非方案级）：** ① 新测试命名从 PRD 建议的 `_test_c4_stagger_stance_break` 改为 `_test_d6_stagger_break_in_stagger`（C4 已被 `_test_c4_invincible_window` 占用——PRD 未核对既有测试编号）；② 采纳 PRD §8 两项防御性加固（parry_success 补行 + execute 守卫）为正式设计内容（PRD 标记「plan 裁决」，本设计裁决：采纳——1 字符成本消灭整类缺口）。

---

## 2. 转移表补丁 — 详细设计（唯一生产拓扑改动）

### 2.1 `combat_state_table.gd` 目标 diff

- **归属文件:** `shandong-wolf/gdscripts/combat_state_table.gd`（`:35` `"stagger"` 行 + `:34` `"parry_success"` 行）
- **目标值:**

```gdscript
# 修改前 (L34-35):
	"parry_success": ["idle", "attack", "heavy_attack", "move"],
	"stagger": ["idle", "dead"],
# 修改后:
	"parry_success": ["idle", "attack", "heavy_attack", "move", "stance_break"],
	"stagger": ["idle", "dead", "stance_break"],
```

- **注释同步（文件头语义要点区 + 行内）:** 新增语义要点「stagger → stance_break 表内（硬直中崩解 = 失衡，优先级高于硬直，与 guard 同构 #577）；parry_success → stance_break 表内（弹反窗口内 clash 扣架势归零同样失衡）」——保持「语义要点显式列出红线案例」的文件惯例。

### 2.2 语义论证（stagger 与 guard 同构）

| 维度 | guard → stance_break（#577 先例） | stagger → stance_break（本设计） |
|------|------|------|
| 姿态/状态语义 | 格挡姿态 = 主动防御 | 受击硬直 = 被动受控 |
| 崩解触发 | 格挡中扣架势归零（POSTURE_BLOCK_COST 累积） | 硬直中二次受击扣架势归零（铁律 6 双重惩罚） |
| 崩解优先级 | 失衡打断格挡姿态 | 失衡打断硬直（立即进入崩解失衡展示） |
| 裁决一致性 | 「崩解优先级高于姿态」已立 | 同裁决推广到硬直态——拓扑层一致性 |

> 方案 A 不改变 `STAGGER_FRAMES=12` 本身（硬直时长不变，崩解打断是语义升级而非节奏改动）；`STANCE_BREAK_RECOVERY_SEC=3.0`（#580 armed 窗口）不变。

### 2.3 防御加固 1: `parry_success` 行补 `"stance_break"`（PRD §5.2 边界 4 / §7 实验 2）

- **缺口路径:** 玩家弹反成功 → `parry_success`（`PARRY_SUCCESS_FRAMES=10`，`constants.gd:262`）；窗口内与敌人攻击 clash（双方各扣 `CLASH_STANCE_COST`）→ 玩家架势恰好归零 → `break_stance()` → `request_transition("stance_break")` → **现状表外拒绝 + 同款 warning**。MVP 1v1 概率低但属整类缺口。
- **裁决:** 采纳补行——1 字符成本，与 stagger 同语义（失衡打断一切动作），消灭整类「表外拒绝」warning；PRD §7 实验 2（11 态 × 扣架势归零枚举）预期确认仅 stagger/parry_success 两处缺口，补后清零。

### 2.4 防御加固 2: `combat_entity.gd` `take_stance_damage` 补 `execute` 守卫（PRD §5.2 边界 5）

- **缺口:** `take_stance_damage`（L142-143）仅 `dead`/`revive` no-op 守卫；`take_damage`（L125）已有 `execute` no-op 守卫——两者不对称。现状 judge 对处决态目标跳过（#580 §8 边界）为双保险，但直连调用路径（未来代码/测试）可穿透。
- **目标 diff:**

```gdscript
# 修改前 (combat_entity.gd L142-143):
	if state_name == "dead" or state_name == "revive":
		return
# 修改后:
	if state_name == "dead" or state_name == "revive" or state_name == "execute":
		return
```

- **语义:** 处决演出中架势扣减无意义（处决结束回 idle 前 stance 已由 break_stance 置 0），no-op 与 take_damage 对齐；不影响任何既有路径（judge 本就不对处决态目标调 take_stance_damage）。

---

## 3. 既有组件修改

### 3.1 `shandong-wolf/gdscripts/combat_state_table.gd`（生产改动 1/2）

| 位置 | 变更 | 伪代码 |
|------|------|--------|
| `:35` TRANSITIONS `"stagger"` | `["idle","dead"]` → `["idle","dead","stance_break"]` | 行尾追加 `"stance_break"` + 行内注释「硬直中崩解=失衡，优先级高于硬直，与 guard 同构（#577）」 |
| `:34` TRANSITIONS `"parry_success"` | `["idle","attack","heavy_attack","move"]` → 追加 `"stance_break"` | 行尾追加 `"stance_break"` + 注释「弹反窗口内崩解同语义（#718 防御加固 1）」 |
| 文件头语义要点区 | 追加 2 条红线要点 | 「stagger→stance_break 表内」「parry_success→stance_break 表内」 |

### 3.2 `shandong-wolf/gdscripts/combat_entity.gd`（生产改动 2/2）

| 位置 | 变更 | 伪代码 |
|------|------|--------|
| `take_stance_damage()` L142-143 | no-op 守卫补 `execute` | `if state_name == "dead" or state_name == "revive" or state_name == "execute": return`（与 take_damage L125 对齐） |

### 3.3 `shandong-wolf/tests/test_combat_entity.gd`（测试改动 1/2）

| 位置 | 变更 | 说明 |
|------|------|------|
| EXPECTED_TRANSITIONS（L20-27） | `"stagger"` 行 → `["idle","dead","stance_break"]`；`"parry_success"` 行 → `["idle","attack","heavy_attack","move","stance_break"]` | **必须与实现同 PR 同步**——`_test_b1_transition_table_121` 将 EXPECTED_TRANSITIONS 与 `is_legal` 121 对遍历比对，只改实现不改断言表 → CI 红（失败路径 3） |
| 新增 `_test_d6_stagger_break_in_stagger` | §8 T1 | Scenario D 架势主路径追加（命名避开既有 `_test_c4_invincible_window`，见 §1.2 差异说明） |
| 新增 `_test_d7_parry_success_stance_break` | §8 T6 | 防御加固 1 用例 |
| 新增 `_test_d8_execute_stance_damage_noop` | §8 T7 | 防御加固 2 用例 |

### 3.4 `shandong-wolf/tests/test_combat_judge.gd`（测试改动 2/2）

| 位置 | 变更 | 说明 |
|------|------|------|
| 新增 `_test_25_stagger_consecutive_hit_break` | §8 T5 | 既有编号 _test_1~24 之后追加（AC3 headless 战斗场景） |

### 3.5 文件变更汇总

- **修改文件（4）:** `shandong-wolf/gdscripts/combat_state_table.gd`（2 行拓扑 + 注释）、`shandong-wolf/gdscripts/combat_entity.gd`（1 行守卫）、`shandong-wolf/tests/test_combat_entity.gd`（断言表 2 行 + 3 新用例）、`shandong-wolf/tests/test_combat_judge.gd`（1 新用例）
- **新文件（0）:** 无
- **删除/弃用文件（0）:** 无
- **受影响测试文件（2）:** 上表 2 个；`test_execution_orchestrator.gd` 零改动（回归验证）
- **文档（post-merge agent 更新，不阻塞）:** `docs/DESIGN/575-combat-entity-state-machine.md` §2.2 转移表（stagger/parry_success 行 + 语义注释）、`docs/GAME_DESIGN/shandong-wolf/` 状态机章节（stagger 可崩解语义）、`docs/PROJECT.md`（一行记录）（PRD §3.5）

---

## 4. 数据流

**Flow 1: stagger 中崩解 → 处决全链（修复后 —— 核心路径）**
```text
combat_judge.gd 受击兜底（resolve_attack，L120-122，零改动）
    ├── take_damage(w.hp_damage)              # 第一击: idle→stagger（表内）
    │                                          # 第二击（stagger 中）: 不进 stagger，保持硬直（现状正确）
    └── take_stance_damage(w.stance_damage)    # 铁律 6 双重惩罚：stagger 中照常扣（零改动）
            └── stance ≤ 0 → break_stance()    # combat_entity.gd L162-170（零改动）
                    ├── is_stance_broken = true
                    ├── emit stance_broken(entity) ──► judge 幂等转发 ──► ExecutionOrchestrator armed 窗口（#580）
                    └── request_transition("stance_break")
                            ├── 修复前: stagger 态 → 表外拒绝 + push_warning ❌ 崩解丢失
                            └── 修复后: stagger→stance_break 表内合法 → state=stance_break ✅
                                    └── state_changed(stagger→stance_break) ──► consume_state 切崩解动画（#574 契约）
                                            └── CombatStateStanceBreak（STANCE_BREAK_RECOVERY_SEC=3.0）
                                                    └── #580: attack_pressed → 距离校验 → execute → 处决演出
```

**Flow 2: 修复前 bug 路径（对照）**
```text
stagger 中二次受击 → take_stance_damage → stance 归零 → break_stance()
    → is_stance_broken=true + stance_broken 广播（副作用先行）
    → request_transition("stance_break") → 表外拒绝 + push_warning
    → state 卡 stagger → 12 帧后回 idle → 崩解展示/处决窗口/处决连招全部丢失 ✗
```

**Flow 3: parry_success 中崩解（防御加固 1 路径）**
```text
弹反成功 → request_transition("parry_success")（PARRY_SUCCESS_FRAMES=10）
    → 窗口内 clash（双方各扣 CLASH_STANCE_COST，combat_judge.gd L179-180）
    → 玩家 stance ≤ 0 → break_stance() → request_transition("stance_break")
    → 修复后: 表内合法 → state=stance_break ✅（修复前: 同款 warning ✗）
```

**Flow 4: 死优先于崩解（同帧 hp 归零 —— 现状已正确，回归验证）**
```text
受击兜底同帧: take_damage 先扣血 → hp ≤ 0 → die() → request_transition("dead")
    （stagger→dead 表内合法）→ state=dead
    → 随后 take_stance_damage 被 dead 守卫 no-op（combat_entity.gd L143）→ 无二次 warning ✅
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 处理 |
|---|---------|------|
| 1 | **stagger 中 hp 归零（受击致死）** | take_damage 先扣血 → die() → state=dead；同帧 take_stance_damage 被 dead 守卫 no-op（L143）→ 死优先于崩解，无二次 warning（Flow 4，现状正确） |
| 2 | **stance_break 中再受击（已崩解）** | `break_stance()` 幂等（is_stance_broken=true → return）——不二次广播/转移（既有 B2/D3 测试覆盖） |
| 3 | **guard 中崩解（既有路径）** | guard→stance_break 表内（#577）——本设计不触碰该行，回归测试覆盖 |
| 4 | **parry_success 中扣架势归零（同类缺口）** | 防御加固 1 补行——弹反窗口内 clash 崩解同语义合法（§2.3） |
| 5 | **execute 中受击/直连扣架势** | judge 对处决态目标跳过（#580 §8 边界）+ 防御加固 2（take_stance_damage 补 execute no-op 守卫，与 take_damage 对齐） |
| 6 | **revive 中受击** | take_stance_damage revive no-op（L143）✅ 现状正确 |
| 7 | **敌我对称性** | 同一类/同一表——玩家被连击崩解、敌人被连击崩解均正常（修复对双方同样生效） |
| 8 | **stagger→stance_break 切帧动画** | consume_state 按状态切 clip（#574 契约）；stagger 12 帧硬直被立即截断进崩解失衡——语义正确，视觉观感归 E2E/用户裁决（失败路径 1 兜底） |

**失败路径（≥3）:**

| # | 失败场景 | 兜底 |
|---|---------|------|
| 1 | 动画层 stagger→stance_break 切帧视觉跳变不可接受 | 降级方案 B（pending_break 延迟转移，PRD §4 备选）——保留完整 stagger 硬直动画后转崩解；本设计在 Continuation Context 标注，由 implement/E2E 阶段裁决 |
| 2 | CI 三层门禁失败（L0 编译 / L1 逻辑 / L2 运行时） | self-correct 路径：L0 语法错 → 修表；L1 断言红 → 检查 EXPECTED_TRANSITIONS 与实现同步（失败路径 3 最常见根因）；L2 playthrough → fight_probe 连续受击场景复测 |
| 3 | 实现改了状态表但没同步测试断言表 | `_test_b1_transition_table_121` 121 对遍历比对立即红——测试与实现必须同 PR 同步修改（§3.3 已列为必改） |
| 4 | 修复未生效（战斗实测仍有 warning） | 重跑 headless 单测（新用例 T1/T5/T6 全绿）+ fight_probe 连续受击场景 stderr 零 warning 检查 + 实机手测 AC1-AC3 |

---

## 6. 集成点

> **状态约定:** ⬜ = 待实现（implement agent 接线）；✅ = 已连接（implement agent 验证后更新）。review agent 在 merge 前核对全部 ⬜ 已解决或显式延后。

| 集成 | 我们的组件 | 目标 Issue | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| stagger 行补 stance_break | `combat_state_table.gd` `:35` | #718 | 拓扑加边（1 行 + 注释） | ⬜ 待实现 |
| parry_success 行补 stance_break | `combat_state_table.gd` `:34` | #718 | 拓扑加边（1 行 + 注释，防御加固 1） | ⬜ 待实现 |
| take_stance_damage execute 守卫 | `combat_entity.gd` `:142-143` | #718 | no-op 守卫补 execute（防御加固 2） | ⬜ 待实现 |
| stance_broken → armed 窗口 | `execution_orchestrator.gd`（#580） | #718/#580 | 零改动；回归验证 _test_a1_full_trigger_chain | ⬜ 待验证 |
| 转移表断言镜像 | `test_combat_entity.gd` EXPECTED_TRANSITIONS | #575/#718 | 2 行同步（stagger/parry_success） | ⬜ 待实现 |
| 切帧动画契约 | `stick_figure_controller.gd` consume_state（#574） | #718/#574 | 零改动；E2E/实机验证 stagger→stance_break 切帧 | ⬜ 待验证 |
| 死优先于崩解 | `combat_entity.gd` dead 守卫（L143） | #718 | 零改动；Flow 4 回归验证 | ⬜ 待验证 |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估计 |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | `combat_state_table.gd` 2 行拓扑（stagger + parry_success）+ 文件头语义要点注释 | 0.1 天 |
| Phase 2 | P0 | `combat_entity.gd` take_stance_damage 补 execute 守卫（1 行） | 0.05 天 |
| Phase 3 | P0 | `test_combat_entity.gd`（断言表 2 行 + `_test_d6/_test_d7/_test_d8` 3 新用例）、`test_combat_judge.gd`（`_test_25` 1 新用例） | 0.2 天 |
| Phase 4 | P0 | headless 全量单测 + fight_probe 连续受击零 warning + E2E/实机验证 AC1-AC3 + 处决链回归（#580） | 0.15 天 |

> 合计约 0.5 天（与 PRD §4 方案 A 估计一致）。单依赖链：Phase 1 → Phase 2 → Phase 3 → Phase 4。

---

## 8. 测试用例描述

> 只描述测试场景，不写可运行代码（测试代码归 implement agent）。命名已避开既有用例编号（§1.2 差异说明）。

### Scenario AC1: 任意状态架势归零 → 稳定 stance_break（issue AC1）

- **T1（`_test_d6_stagger_break_in_stagger`，新增）:** 构造实体处于 stagger（`request_transition("stagger")` 或 `take_damage` 进入），随后 `take_stance_damage(stance_max)`（一次扣满）。断言：`state_name == "stance_break"`、`is_stance_broken == true`、`stance_broken` 信号恰好一次、**无 illegal transition push_warning**（状态序列 idle→stagger→stance_break）。修复前该用例红（warning + state 卡 stagger）。
- **T2（`_test_b1_transition_table_121` 更新回归）:** EXPECTED_TRANSITIONS stagger/parry_success 行同步后，121 对遍历比对（is_legal）全绿——状态表断言表与实现逐字镜像（#575 红线）。

### Scenario AC2: 崩解 → 处决连招完整（issue AC2，#580 回归）

- **T3（`test_execution_orchestrator.gd` 回归，零改动）:** 既有 `_test_a1_full_trigger_chain` 全绿——stance_broken → armed 窗口 → attack_pressed → 距离校验 → execute 转移链不回归（广播时序不变是前提，§4 Flow 1）。
- **T4（state_changed 广播序列断言）:** 连续受击场景下断言 `state_changed` 广播序列为 idle→stagger→stance_break（顺序正确，无缺失）；`stance_broken` 先于转移（break_stance 语义不变）。

### Scenario AC3: headless 战斗测试覆盖「stagger 中崩解」（issue AC3）

- **T5（`_test_25_stagger_consecutive_hit_break`，test_combat_judge.gd 新增）:** 两帧连续 `resolve_attack`：帧 1 命中 → 实体进 stagger（take_damage + take_stance_damage，架势未归零）；帧 2 命中 → 扣血 + 扣架势归零 → 断言实体 `state_name == "stance_break"`、无 warning、judge 转发 `stance_broken` **恰好一次**（幂等，参照既有 `_test_15_stance_broken_forward`/`_test_16_stance_broken_forward_idempotent` 断言风格）。

### Scenario P: 同类缺口补全（防御加固 1/2）

- **T6（`_test_d7_parry_success_stance_break`，新增）:** 实体 `request_transition("parry_success")` 后 `take_stance_damage(stance_max)` → 断言 state == "stance_break"、无 warning（修复前表外拒绝红）。
- **T7（`_test_d8_execute_stance_damage_noop`，新增）:** 实体处于 execute → `take_stance_damage(stance_max)` → 断言 stance 不变（>0）、无 break_stance 触发、无 warning（防御加固 2 生效）。
- **T8（全路径枚举断言，可选增强）:** 11 个 canonical 态 × `take_stance_damage(stance_max)` 直调枚举——断言仅 dead/revive/execute no-op，其余态全部可达 stance_break 且零 warning（PRD §7 实验 2 的自动化形态；实现时可并入 D 组循环用例）。

### Scenario R: 回归

- **T9（既有实体用例零改动回归）:** C1（damage→stagger）/ C2（stagger 自动退出）/ C3（guard 不硬直）/ D1-D5（架势主路径：drain/break_broadcast/break_idempotent/guard_break/break_recovery_execute）/ B2（stance_break 红线：不可 attack/guard）/ B3（dead 锁定）全部零改动全绿。
- **T10（既有判定层用例零改动回归）:** `test_combat_judge.gd` 既有 _test_1~24 全绿（含 parry/clash/block/hit_landed/stance_broken_forward 幂等转发）——判定层零改动红线验证。
- **T11（全量单测 + 运行时）:** `godot --headless --path shandong-wolf -s tests/run_tests.gd` 全绿 + fight_probe 连续受击场景 stderr **零 illegal transition warning**（L2 运行时门禁）。

---

## 9. 验收条件映射（issue body + PRD §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 战斗中架势扣到 0（无论是否处于 stagger）→ 稳定触发 stance_break（无 warning） | §2.1（stagger 行补边）+ §3.1 | T1（_test_d6）+ T2（121 对断言表）+ T5（_test_25）+ T11（运行时零 warning） |
| AC2 | 崩解 → 处决连招完整（#580） | §4 Flow 1（广播时序不变）+ 集成点 armed 窗口 | T3（_test_a1_full_trigger_chain 回归）+ T4（广播序列） |
| AC3 | headless 战斗测试覆盖「stagger 中崩解」场景 | §3.4（test_combat_judge 新用例）+ §8 T5 | T5（连续受击用例）+ T11（headless 全量） |

---

## 10. 明确不修改（与 PRD §3.3/§8 红线对齐）

- ❌ `shandong-wolf/gdscripts/combat_judge.gd`（受击兜底 L120-122 调用时序、guard/parry/clash 路径、stance_broken 幂等转发全部零改动——铁律 6 保留）
- ❌ `shandong-wolf/gdscripts/combat_states.gd`（CombatStateStagger 自然退出逻辑、CombatStateStanceBreak 全部零改动——方案 A 由 break_stance 转移打断硬直，无需 pending 挂载点）
- ❌ `shandong-wolf/gdscripts/execution_orchestrator.gd`（armed 窗口消费 stance_broken，零改动——广播时序不变则处决链照常）
- ❌ `shandong-wolf/gdscripts/stick_figure_controller.gd`（consume_state 11 态动画契约零改动——stagger→stance_break 切帧在契约内）
- ❌ `shandong-wolf/gdscripts/constants.gd`（`STAGGER_FRAMES=12`、`STANCE_BREAK_RECOVERY_SEC=3.0`、`PARRY_SUCCESS_FRAMES=10`、`CLASH_STANCE_COST` 等全部零改动——无新常量，零数值裁决）
- ❌ `shandong-wolf/gdscripts/enemy_ai.gd` / `enemy_ai_states.gd` / `main_battle.gd`（不感知状态转移表，零改动）
- ❌ `shandong-wolf/tests/test_execution_orchestrator.gd`（零改动回归验证）
- ❌ `project.godot`、`game-env/manifest.yaml`、`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`（跨游戏/管线红线）
- ❌ 任何贴图 / Sprite2D / shader 美术资产（零美术资产改动）
- ❌ 任何可运行测试文件（本阶段只产出 DESIGN 文档 + 测试用例描述；测试代码归 implement agent）
- ✅ `break_stance()`（combat_entity.gd L162-170）零改动——幂等语义保留；`take_stance_damage` 仅补 1 行 execute 守卫（防御加固 2），其余逻辑零改动
- ✅ 本 phase 不 merge 任何 PR（只创建 `plan/718-stagger-stance-break` PR，body `Parent #718`）

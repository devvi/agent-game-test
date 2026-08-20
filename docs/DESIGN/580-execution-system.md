# Design: [Combat] 处决系统（架势崩解 → 处决特写）

> **Parent Issue:** #580
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4.6 推荐组合**逐项确认采纳，无分歧** —— 触发编排器 A（ExecutionOrchestrator 独立 Node bind 模式，类 #578 ReviveOrchestrator）/ 处决杀敌 A（`execute_kill()` 专用接口，绕过 take_damage execute no-op 红线）/ 玩家无敌 A（`set_invincible(seconds)` 复用既有无敌期）/ 疲惫起身 A（实体数据层 `recover_from_break()` + ×1.2 乘数下沉 take_stance_damage）/ 淡出演出 A（独立 ExecutionFade，墙钟驱动）/ 演出参数化 A（constants「处决演出」# DRAFT 分区）；方案 B/C 显式否决，理由同 PRD §4（职责耦合违规 / 契约破坏连锁 / 拓扑死路）
> **Reference PRD:** `docs/PRD/580-execution-system.md`（research PR #656 已合并 2026-08-20）
> **上游方案:** `docs/DESIGN/578-two-life-revive.md`（ReviveOrchestrator bind/unbind 幂等接线 + headless `_process(delta)` 手动推进 = 编排器架构先例）；`docs/DESIGN/579-combat-feedback-system.md`（S 级 execute 反馈矩阵 + TimeScaleStack 嵌套/墙钟兜底 + `_trigger_execute_arc` 刀光）；`docs/DESIGN/575-combat-entity-state-machine.md`（6 信号契约 + 11 态拓扑 + take_damage execute no-op 红线 + `_invincible_until_sec` 机制）；`docs/DESIGN/577-parry-clash-stance-break.md`（stance_broken 幂等转发统一事件出口 + 判定器「dead/revive/execute 态受击跳过」守卫）
> **所有权:** `content_ownership: mechanical`（处决机制实现=机械工程——编排时序/杀敌通道/无敌窗口/疲惫数值/淡出机制；慢动作时长/淡出节奏/演出强度参数=taste-draft——`# DRAFT` + 候补值 + E2E 截图用户裁决，**实现期禁止把 DRAFT 值「顺手定稿」**，定稿归 #584/用户）
> **深度:** deep（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=9 标注 depth: deep → PRD §1–8 全必填，§7 含 ≥3 实验；GitHub 无 depth 标签）—— 6 文件（2 新建脚本 + 1 新建测试 + 3 修改）/ 6 独立子任务（编排器、淡出组件、实体 3 接口+1 数据、常量分区、测试套件、E2E 截图）→ **产出 DESIGN + TASKS 文档**
> **并行上下文:** worktree 隔离（/tmp/wt-plan-580，branch `plan/580-execution-system`）；constants.gd「处决演出」分区追加在**文件尾部**（#584 手感分区已在前部，同文件不同区域，main 侧无代码冲突预期）；e2e_shots.json 追加 `execution` 组（与 stick_figure/snow_night/hud/feedback/battle_stage 组并存，追加式无并发改写）；`combat_entity.gd` 为多 issue 共享文件——本设计只做**纯 additive 追加**（3 公共方法 + 1 数据 + 1 到期清除分支），不改既有路径一行
> **红线:** 只动 `shandong-wolf/` 下 6 文件（见 §3.1）；**绝不触碰** `combat_states.gd` / `combat_state_table.gd`（#575 拓扑契约）、`combat_judge.gd`（#577 判定契约）、`reaction_controller.gd` / `time_scale_stack.gd` / `sword_arc.gd`（#579 只调不改）、`hud.gd` / `enemy_ai.gd`（#576/#581 零改动消费）、`scenes/`（#585 组装域）、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`tests/check_compile.gd`、`tests/smoke_test.gd`；零第三方 addon；**take_damage execute no-op 是 #575 无敌红线——处决杀敌禁止绕过它去改 take_damage，必须走新增 `execute_kill()`**；禁止直写 `Engine.time_scale`（只经 trigger_feedback → TimeScaleStack）；三处慢动作候选（0.1/0.6s vs 0.05/0.5s vs 0.2/0.4s）必须并列 `# DRAFT` 登记，**实现期禁止二选一偷定**；PR body 用 `Parent #580`（不带冒号）

---

## 1. 架构总览

**问题本质是「处决链路的每一块零件都已存在，唯独没有编排者」。** #575（#618）已交付 CombatEntity 6 信号 + `stance_break → execute` 拓扑 + `take_damage` execute 态 no-op 无敌红线；#577（#626）已交付 stance_broken 幂等转发统一事件出口；#579（#654）已交付 S 级 execute 反馈组合（150ms hit-stop + 0.05x 慢动作 0.5s + 刀光弧线 + 血色粒子 + 屏震）与 TimeScaleStack；#574（#612）已交付 anim_execute 5 帧处决动画；#576（#627）已交付处决提示自动显隐；#584 已定稿杀敌常量 SWORD_DAMAGE_EXECUTE=999。**但全库零处 `request_transition("execute")` 调用、零距离校验、零杀敌通道（take_damage 无敌红线挡住了所有常规伤害路径）、零淡出、零疲惫起身。** 本 issue 交付 = **ExecutionOrchestrator（编排器）+ 3 个 CombatEntity additive 接口（execute_kill / set_invincible / recover_from_break）+ ExecutionFade（淡出）+ constants「处决演出」# DRAFT 分区 + test_execution_orchestrator.gd + e2e execution 组 shot**。这是 #585 组装「可玩战斗闭环」（出生→遇敌→弹反→崩解→处决→击杀）的最后一个功能件。

**设计哲学：编排器编排，实体持数据，反馈只传参。** 三个决策全部锚定 PRD §4 推荐方案：
1. **编排器是唯一「指挥者」**——跨组件时序（信号→窗口→输入→转移→杀敌→演出→淡出）收敛到 ExecutionOrchestrator 一个组件，与场景解耦（bind 模式，同 #578 先例），headless 免树可测（`_process(delta)` 手动推进）；
2. **实体是唯一数据持有者**——杀敌（execute_kill）、无敌（set_invincible）、起身疲惫（recover_from_break + exhausted 乘数）全部下沉 CombatEntity additive 接口，零外部直写实体数据（#575「实体层持有数据」契约）；
3. **反馈零改造**——编排器只调 `trigger_feedback("execute")` 一个入口，S 级矩阵、TimeScaleStack、刀光全部由 #579 既有组件执行（§1.2 Gap 解析：PRD「编排器传参慢动作」在既有 API 下无参可传，参数化通道归 #584 定稿时接入）。

```
★ Issue #580 本设计（shandong-wolf 处决系统 SW-009）
┌────────────────────────────────────────────────────────────────────────────┐
│ 新建（3 文件，全部 shandong-wolf/ 下）                                         │
│  gdscripts/execution_orchestrator.gd   ExecutionOrchestrator（Node，编排器）  │
│    ├─ bind_player / bind_enemy / bind_input / bind_judge（幂等接线，unbind）  │
│    ├─ _on_stance_broken → armed=true + 窗口计时（STANCE_BREAK_RECOVERY_SEC）  │
│    ├─ _on_attack_pressed → 距离/armed/玩家存活校验 → _trigger_execution()    │
│    ├─ _trigger_execution() 时序序列（无敌→转移→杀敌→反馈→淡出）                │
│    └─ _process(delta) 窗口到期 → enemy.recover_from_break()（幂等起身）       │
│  gdscripts/execution_fade.gd           ExecutionFade（Node，淡出演出）         │
│    ├─ bind(entity)：modulate alpha 1→0（墙钟驱动，慢动作不卡淡出）             │
│    └─ fade_completed(entity) → queue_free（is_instance_valid 守卫）          │
│  tests/test_execution_orchestrator.gd  五组用例（触发时序/边界/无敌交互/        │
│                                         疲惫数值/淡出清理 + 失败路径防回归）     │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────────────────┐
│ 修改（3 文件，全部 additive）                                                  │
│  gdscripts/combat_entity.gd   追加 3 公共方法 + exhausted 数据 + 到期清除      │
│  gdscripts/constants.gd       文件尾部追加「处决演出」# DRAFT 分区              │
│  tests/run_tests.gd           _run_tests() 追加 test_execution_orchestrator   │
│  e2e_shots.json               追加 execution 组（斩落/淡出 2 shot）            │
└────────────────────────────────────────────────────────────────────────────┘
事件源（只读消费，零修改）: CombatEntity 信号（#575） + CombatJudge.stance_broken（#577 统一出口）
                        + InputController.attack_pressed（#573 攻击键=处决键）
消费方（自动接管，零修改）: Hud（#627 处决提示/击杀提示）/ ReactionController（#654 S 级反馈）
                        / EnemyAI（#638 停走/禁用）/ CombatJudge（#626 execute 态受击跳过）
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统 | 状态 | 本设计的消费方式 |
|------|:----:|-----------------|
| `combat_entity.gd`（#575/#618） | ✅ 已交付 | 6 信号只读订阅；`request_transition("execute")` 拓扑已预留（stance_break→execute 表内）；追加 3 接口 + exhausted 数据（additive，§3.2） |
| `combat_states.gd`（#575/#618） | ✅ 已交付 | `CombatStateStanceBreak` 3.0s 自动退 idle（期间可被 execute 抢先）；`CombatStateExecute` 5 帧自动退 idle —— **零改动**（§1.2 Gap 2：execute_kill 后守卫拒绝转移的已知噪声） |
| `combat_state_table.gd`（#575/#618） | ✅ 已交付 | `stance_break → execute → idle` 拓扑表内；execute→dead 表外（处决不转移 dead 态的结构性保证）—— **零改动** |
| `combat_judge.gd`（#577/#626） | ✅ 已交付 | stance_broken 幂等转发统一出口；判定器守卫「dead/revive/execute 态受击跳过」= 处决演出期目标无敌的**结构性保证**（§2.1 设计决策 D2）—— **零改动** |
| `reaction_controller.gd`（#579/#654） | ✅ 已交付 | `trigger_feedback("execute")` S 级组合 + `_trigger_execute_arc` 刀光 + TimeScaleStack 墙钟兜底 —— 编排器只调一个入口，**零改动** |
| `input_controller.gd`（#573/#611） | ✅ 已交付 | `attack_pressed` 意图信号（复用 #2 attack 键 = 处决键，issue 触发契约逐字对齐）—— 编排器 bind_input 订阅，**零改动** |
| `hud.gd`（#576/#627） | ✅ 已交付 | `_on_enemy_stance_broken` 自动显示处决提示（EXECUTE_HINTS 5 候选，implement 选 1 进 PR 待用户定稿）；玩家进 attack/execute 态自动隐藏；`died(final=true)` → 击杀提示接管 —— **零改动** |
| `enemy_ai.gd`（#581/#638） | ✅ 已交付 | 实体进 stance_break/execute 态清 move_intent 自动停走；`_on_entity_died` → AI 完全禁用；起身（idle + 50% 架势）后 AI 自然恢复 —— **零改动** |
| `stick_figure_controller.gd`（#574/#612） | ✅ 已交付 | anim_execute clip（5 帧上撩→斩落）+ consume_state 把 execute 映射到 anim_execute —— 经 request_transition("execute") 间接消费，**零改动** |
| `revive_orchestrator.gd`（#578） | ✅ 已交付 | bind/unbind 幂等接线 + `_process(delta)` 自管理计时 + headless 免树 = 本设计编排器的**直接架构模板** |
| `constants.gd`（#572/#584/#599/#609） | ✅ 已交付 | **无「处决演出」分区**；SWORD_DAMAGE_EXECUTE=999 已定稿、EXECUTE_RANGE=1.2（米，单位坑见 §1.2 Gap 1）、FRAME_ANIM_EXECUTE_TOTAL=5、STANCE_BREAK_RECOVERY_SEC=3.0 —— 本 issue 在文件尾部追加分区（§3.3） |
| `tests/run_tests.gd` | ✅ 已交付 | 已挂 14 套件；追加 `test_execution_orchestrator.gd`（§3.4） |
| `e2e_shots.json` | ✅ 已交付 | dict 结构（states/autoplay/groups…）；feedback 组已有 fb_execute shot（S 级反馈截图）；本 issue 追加 execution 组（§3.5） |
| 战斗场景（#583 battle_stage.tscn） | ✅ 已交付 | 处决构图 E2E 背景复用（雪幕+冷月光+水墨，#582/#583）；#585 组装时挂载编排器 —— 本 issue 编排器 bind 模式与场景解耦 |

### 1.2 PRD 断言 vs 实际代码（Gap 分析）

| PRD 断言 | 实际代码 | 设计解析 |
|---------|---------|---------|
| `EXECUTE_RANGE=1.2` 直接用于距离校验 | `EXECUTE_RANGE` 语义为「1.2 米」（sekiro-reference），Godot 2D 场景 1 单位=1px，直接按 1.2px 判距离永不触发 | 派生 `EXECUTE_RANGE_PX = EXECUTE_RANGE × 100 = 120px`（# DRAFT 候补，与 HITBOX_RANGE=80px 同量级；比例 100px/m 待用户裁决），编排器距离校验用 PX 派生值 |
| 「消费方（编排器 → trigger_feedback）经常量读值」传参慢动作（§1.5 三处候选） | `ReactionController.trigger_feedback(event, data)` 的 data 键仅 position/normal/target_entity/attacker_entity/direction/direction_vec/source，**无慢动作覆盖键**；慢动作读 `C.FEEDBACK_SLOWMO[level]`（S 级 = 0.05/500ms 已实现） | **参数化通道在既有 API 下无参可传**：EXECUTE_SLOWMO_SCALE/MS 作为候选登记（constants 文档契约，禁止二选一偷定）；机制消费方仍是 #579 S 级矩阵（AC4 机械保证已成立——TimeScaleStack 嵌套+墙钟兜底与具体数值无关）；用户裁决结果 ≠ S 级现值时，由 #584 改 `FEEDBACK_SLOWMO["S"]`（#579/#584 域），本 issue 零改动 |
| 「不转移 dead 态（保持 execute 演出态，5 帧动画 + 淡出照常）」+「状态机停摆守卫（_is_final_dead）保证死后不可 revive/不可二次事件」 | `CombatStateExecute.update` 5 帧后每帧调用 `entity.request_transition("idle")`；`request_transition` 守卫① `_is_final_dead and to != "dead"` → **拒绝 + push_warning** | **已知噪声（设计接受）**：execute_kill 置位 _is_final_dead 后，execute→idle 请求每帧被拒并告警（淡出 0.3s 窗口内约 13 条）；**行为正确**——状态保持 execute 正是设计目标（判定器守卫对 execute 态持续跳过 = 淡出窗口期目标无敌），且阻止二次 died/复活；**禁止**为消噪改 combat_states.gd / 守卫①（红线）。单测断言与 PRD 一致：state 保持 execute、died(true) 恰好一次 |
| 「恢复路径由编排器 armed 到期调用，或由 CombatStateStanceBreak 退出钩子调用——双保险幂等」 | `CombatStateStanceBreak` 只计时退出（3.0s → request_transition("idle")），**无恢复钩子** | 恢复唯一驱动 = **编排器 armed 到期调 `recover_from_break()`**（幂等：is_stance_broken 已清 → no-op）；state_changed 观察（stance_break→idle）仅作 armed 失效信号 + 立即触发恢复（双保险仍成立，幂等防双写） |
| `stance_broken` 订阅「优先 bind_judge（统一事件出口）」 | CombatJudge.stance_broken 为幂等转发（`_forwarded_stance_break` 防重）；CombatEntity.stance_broken 为原始单发 | **双源等价**（同一 break_stance 派生，均幂等单发）：bind_judge 优先（#585 组装路径），bind_enemy 直连实体信号为降级（headless 测试免判定器）；两源互斥切换，禁止同帧双订阅（防 armed 计时重置竞态，§2.1 设计决策 D3） |
| 其余断言（6 信号契约 / stance_break→execute 拓扑 / trigger_feedback("execute") S 级 / attack_pressed 攻击键 / HUD 提示自动显隐 / AI 停走+禁用） | 与 PRD 逐字一致（已核实源码） | ✅ 全部成立，零修改消费 |

---

## 2. 新组件 — 详细设计

### 2.1 execution_orchestrator.gd — 处决触发编排器（PRD §4.1 方案 A）

- **File:** `shandong-wolf/gdscripts/execution_orchestrator.gd`
- **Class:** `extends Node`，`class_name ExecutionOrchestrator`（非实体、非 autoload，类 #578 ReviveOrchestrator）
- **Node structure:** 无场景树依赖；由 #585 组装实例化并 add_child（或测试直接 new + 手动 `_process`）

**Signals:** 无（编排器只消费信号、调用接口、创建淡出组件，不对外发事件）

**State Properties:**
```gdscript
var _player: Object = null          # bind_player 注入（处决无敌目标）
var _enemy: Object = null           # bind_enemy 注入（崩解/处决/起身目标）
var _judge: Object = null           # bind_judge 注入（stance_broken 统一出口，可选）
var _input: Object = null           # bind_input 注入（attack_pressed 处决键）
var _armed: bool = false            # 处决窗口开启（stance_broken 置位，触发/起身/解绑清除）
var _arm_elapsed: float = 0.0       # 窗口计时（_process(delta) 累加，headless 手动推进）
var _stance_source: Object = null   # stance_broken 当前信号源（judge 优先 / enemy 降级，互斥切换）
var fade: Object = null             # ExecutionFade 实例（_init 创建，测试可注入/断言）
```

**Key Methods:**
```gdscript
func bind_player(p) -> void:
    # 幂等接线（先断开旧实体信号，对齐 ReviveOrchestrator.bind_player 先例）
    # 订阅 p.state_changed（玩家 dead 守卫用，或触发时实时查 state_name —— 取实时查，免订阅）
    _player = p

func bind_enemy(e) -> void:
    # 幂等接线：断开旧 enemy 全部订阅（防信号泄漏，PRD §5.3-2）
    # 订阅 e.state_changed（armed 失效观察） + e.died（unbind 清理）
    # 若 _judge == null → 订阅 e.stance_broken（降级直连，headless 测试路径）
    # 若已有 judge → 切换信号源（D3）

func bind_judge(j) -> void:
    # 统一事件出口优先（#585 组装路径）：断开 enemy 直连 → 改连 j.stance_broken
    # has_signal 防护 + 同实体幂等（防重绑）

func bind_input(ic) -> void:
    # 订阅 ic.attack_pressed（攻击键 = 处决键，issue 触发契约逐字落实）

func unbind_enemy() -> void:
    # 场景切换/实体销毁前调用：断开全部订阅 + _enemy = null + _armed = false

func _on_stance_broken(entity) -> void:
    if entity != _enemy: return
    _armed = true                    # 窗口开启（幂等：重复事件仅重置计时，事件本身单发）
    _arm_elapsed = 0.0

func _on_enemy_state_changed(from: String, to: String) -> void:
    if from == "stance_break" and to == "idle":
        # 状态机 3.0s 自动退出（同源常量）→ armed 失效 + 立即恢复（幂等，PRD §5.2-1 双保险）
        if _armed:
            _armed = false
            if is_instance_valid(_enemy):
                _enemy.recover_from_break()
    elif to == "execute":
        _armed = false               # 处决已触发（本路径由 _trigger_execution 已清，防御性双清）

func _on_enemy_died(_ent, _final) -> void:
    unbind_enemy()                   # 防信号泄漏（queue_free 后回调访问已释放对象）

func _on_attack_pressed() -> void:
    # 处决检查：armed ∧ 玩家存活 ∧ 距离内（闭区间 ≤）→ 触发；否则正常 attack 流程继续
    if not _armed: return
    if _player == null or not is_instance_valid(_player): return
    if _player.state_name == "dead": return        # 防「尸体处决」演出（PRD §5.2-3）
    if _enemy == null or not is_instance_valid(_enemy): return
    if absf(_player.position.x - _enemy.position.x) > _range_px(): return   # 距离外 → 正常 attack
    _trigger_execution()

func _trigger_execution() -> void:
    # 时序序列（PRD §1.5 逐字落实，顺序关键：先转移后杀敌，PRD §8 风险①）
    _armed = false
    _player.set_invincible(_read("EXECUTE_INVINCIBLE_SECONDS", C.EXECUTE_INVINCIBLE_SECONDS))
    if _enemy.state_name != "execute":
        _enemy.request_transition("execute")        # 5 帧 anim_execute（#574 消费；幂等：已 execute 则跳过）
    _enemy.execute_kill()                            # AC1 杀敌（绕过 take_damage no-op 红线，§3.2.1）
    if _judge_bound_feedback():                      # ReactionController 注入（bind_feedback 或经 data 传递）
        _feedback.trigger_feedback("execute", {"target_entity": _enemy})   # AC4 S 级（#654）
    fade.bind(_enemy)                                # AC2 淡出（modulate 1→0 0.3s → queue_free）

func _process(delta: float) -> void:
    if not _armed: return
    _arm_elapsed += delta
    if _arm_elapsed >= float(C.STANCE_BREAK_RECOVERY_SEC):   # 同源互引（#618 时序常量）
        _armed = false
        _arm_elapsed = 0.0
        if is_instance_valid(_enemy):
            _enemy.recover_from_break()              # AC3 起身（幂等，§3.2.3）
```

**设计决策（D 系列，实现 agent 必须遵守）：**
- **D1（距离校验）:** 一维坐标差 `|dx| ≤ EXECUTE_RANGE_PX` 闭区间（与 #577 弹反窗口闭区间语义一致），零碰撞体（#574/#577 零碰撞体红线）；`_range_px()` 经 `DebugCanvas.get_value("EXECUTE_RANGE_PX", C.EXECUTE_RANGE_PX)` 读值（热更新优先，release 回落 const，#584 约定）
- **D2（目标无敌结构保证）:** 处决演出期目标无敌**不靠编排器**——判定器守卫「execute 态受击跳过」（#626 已内置）+ `execute_kill` 保持 execute 态 = 双保险；编排器零额外守卫
- **D3（stance_broken 单源）:** bind_judge 与 bind_enemy 直连**互斥切换**（judge 绑定 → 断开实体直连），禁止同帧双订阅——否则同一 break_stance 双触发会重置 armed 计时（窗口被拉长 3s 的竞态）
- **D4（同键多义不拦截玩家 attack）:** 玩家按攻击键 → 实体输入桥 `request_transition("attack")` 与编排器处决检查**并行**（两路都订阅 attack_pressed）；处决触发时玩家 attack 转移照常（挥刀演出与处决演出同帧并行）；判定器对 execute 态目标跳过 = 玩家攻击窗口解析时无二次伤害/无二次事件
- **D5（慢动作零直写）:** 编排器不读 EXECUTE_SLOWMO_* 应用（无参可传，§1.2 Gap 2），不直写 `Engine.time_scale`（红线）；慢动作由 trigger_feedback("execute") → TimeScaleStack 提供（#654 已保证嵌套恢复 + 墙钟兜底）
- **D6（反馈注入双通道）:** 编排器暴露 `bind_feedback(rc)`（#585 组装接线）；headless 测试注入 mock ReactionController 断言 `trigger_feedback("execute")` 恰好一次；未绑定 → 静默跳过（编排器不持有反馈逻辑，只发命令）

### 2.2 execution_fade.gd — 敌人淡出组件（PRD §4.2 淡出演出 / §4.6 方案 A）

- **File:** `shandong-wolf/gdscripts/execution_fade.gd`
- **Class:** `extends Node`，`class_name ExecutionFade`
- **Node structure:** 由编排器 _init 创建并 add_child（或测试直接 new）；可挂任意 CanvasItem 目标

**Signals:**
```gdscript
signal fade_completed(entity: Node)   # 淡出完成（queue_free 前发出，测试断言点）
```

**State Properties:**
```gdscript
var _target: Node = null          # 淡出目标（CanvasItem，modulate 可写）
var _start_ms: int = -1           # 起始墙钟（Time.get_ticks_msec()，首次 _tick 惰性记录）
var _bound: bool = false
```

**Key Methods:**
```gdscript
func bind(entity) -> void:
    # 幂等重绑：新目标重置计时；_start_ms = -1（下一 _tick 惰性记录）
    # 目标必须可写 modulate（Node2D/Control），否则 push_warning + 不绑定

func _process(_delta: float) -> void:
    _tick(Time.get_ticks_msec())          # 墙钟驱动（PRD §5.2-6：时间缩放不影响墙钟，慢动作不卡淡出）

func _tick(now_ms: int) -> void:
    # 核心推进（测试直接注入 now_ms，headless 确定性 —— 对齐 TimeScaleStack.tick 模式）
    if not _bound: return
    if not is_instance_valid(_target):     # 目标已释放（竞态）→ 解绑静默退出
        _bound = false
        return
    if _start_ms < 0:
        _start_ms = now_ms
        _target.modulate.a = 1.0
    var elapsed: float = float(now_ms - _start_ms) / 1000.0
    var ratio: float = elapsed / _read("EXECUTE_FADE_SECONDS", C.EXECUTE_FADE_SECONDS)
    if ratio >= 1.0:
        _target.modulate.a = 0.0
        var done: Object = _target
        _bound = false
        emit_signal("fade_completed", done)
        done.queue_free()                  # 如墨迹消散（issue body 画面路径）
        return
    _target.modulate.a = clampf(1.0 - ratio, 0.0, 1.0)
```

**设计要点：**
- **墙钟而非 delta 累加**：`_process(delta)` 只做转发，进度全部由 `Time.get_ticks_msec()` 差值计算——处决慢动作 0.05x-0.1x 期间（0.5-0.6s）淡出 0.3s 照常完成，不卡顿（PRD §5.2-6，对齐 TimeScaleStack 墙钟兜底哲学）
- **is_instance_valid 守卫**：目标被外部释放（二次事件/场景切换）→ 静默解绑，不访问已释放对象（PRD §5.3-2）
- **fade_completed 信号**：headless 测试断言点（绑定后 `_tick(start+150)` 断言 alpha≈0.5 → `_tick(start+300)` 断言信号发出 + 目标 freed）
- **参数化**：`EXECUTE_FADE_SECONDS`（0.3s # DRAFT，issue body 字面值）经 `_read()` 包装（DebugCanvas.get_value 优先）

---

## 3. 既有组件修改

### 3.1 文件清单总表

| 类型 | 文件 | 变更 |
|:---:|------|------|
| 新建 | `shandong-wolf/gdscripts/execution_orchestrator.gd` | 编排器（~150 行，§2.1） |
| 新建 | `shandong-wolf/gdscripts/execution_fade.gd` | 淡出组件（~50 行，§2.2） |
| 新建 | `shandong-wolf/tests/test_execution_orchestrator.gd` | 测试套件（~200 行，§8） |
| 修改 | `shandong-wolf/gdscripts/combat_entity.gd` | 追加 3 公共方法 + exhausted 数据 + 到期清除（§3.2，**纯 additive**） |
| 修改 | `shandong-wolf/gdscripts/constants.gd` | 文件尾部追加「处决演出」# DRAFT 分区（§3.3） |
| 修改 | `shandong-wolf/tests/run_tests.gd` | 挂载新套件（§3.4） |
| 修改 | `shandong-wolf/e2e_shots.json` | 追加 execution 组（§3.5） |

### 3.2 combat_entity.gd — 3 公共方法 + 1 数据（PRD §4.2/§4.3/§4.4 方案 A，全部 additive）

> **红线声明：** 以下全部为**新增代码**，不改 `take_damage` / `take_stance_damage` 既有守卫一行（仅 take_stance_damage 内**追加**乘数分支）；`break_stance()` 内**追加**一行 exhausted 复位。既有测试（test_combat_entity 30 用例）零改动零破坏。

#### 3.2.1 `execute_kill()` — 处决杀敌专用通道（PRD §4.2 方案 A）

```gdscript
func execute_kill() -> void:
    ## 处决杀敌专用接口（#580）：绕过 take_damage 的 execute no-op 无敌红线（§5.2-1）。
    ## 语义: 无视架势终结（SWORD_DAMAGE_EXECUTE=999 机械语义）；不调用 take_damage、
    ##   不转移 dead 态——保持 execute 演出态（5 帧动画 + 淡出照常，判定器守卫持续跳过）。
    ## 停摆守卫: _is_final_dead 置位 → 不可 revive / 不可二次 died / 转移请求被守卫①拒绝
    if _is_final_dead:
        return
    _is_final_dead = true
    exhausted = false
    hp_1 = 0.0
    emit_signal("hp_changed", hp_1, hp_2, _active_life)
    emit_signal("died", self, true)     # HUD 击杀提示 / ReactionController death / EnemyAI 禁用自动接管
```

#### 3.2.2 `set_invincible(seconds)` — 玩家无敌公共接口（PRD §4.3 方案 A）

```gdscript
func set_invincible(seconds: float) -> void:
    ## 处决/演出期无敌（#580）：复用既有无敌期机制（revive() 同款墙钟比较）。
    ## take_damage / take_stance_damage 的无敌期 no-op 守卫已存在，自动生效（双保险 + 判定器守卫）。
    _invincible_until_sec = Time.get_ticks_msec() / 1000.0 + maxf(seconds, 0.0)
```

#### 3.2.3 `recover_from_break()` — 起身疲惫（PRD §4.4 方案 A）

```gdscript
var exhausted: bool = false                    # 新增数据（疲惫标志，AC3）
var _exhausted_until_sec: float = 0.0          # 疲惫到期墙钟

func recover_from_break() -> void:
    ## 崩解起身（#580，幂等）：50% 架势恢复 + 5s 疲惫（受架势伤害 ×1.2）。
    ## 幂等: is_stance_broken 已清 → no-op（防状态机退出与编排器到期双写竞态，PRD §5.3-3）
    if not is_stance_broken:
        return
    is_stance_broken = false
    stance = clampf(stance_max * _read("EXECUTE_RECOVER_RATIO", C.EXECUTE_RECOVER_RATIO), 0.0, stance_max)
    exhausted = true
    _exhausted_until_sec = Time.get_ticks_msec() / 1000.0 + _read("EXECUTE_EXHAUSTED_SECONDS", C.EXECUTE_EXHAUSTED_SECONDS)
    emit_signal("stance_changed", stance, stance_max)
```

**take_stance_damage 追加分支**（仅追加，不改既有守卫）:
```gdscript
    # 在既有「无敌期 no-op」守卫之后、扣减之前追加:
    if exhausted:
        amount = amount * _read("EXECUTE_EXHAUST_MULTIPLIER", C.EXECUTE_EXHAUST_MULTIPLIER)   # ×1.2 疲惫增伤
```

**break_stance() 追加一行**（疲惫期再次崩解 → 新轮次优先，PRD §5.2-7）:
```gdscript
    exhausted = false
```

**_process 追加到期清除**（疲惫 5s 到期幂等恢复 1.0）:
```gdscript
    if exhausted and Time.get_ticks_msec() / 1000.0 >= _exhausted_until_sec:
        exhausted = false
```

### 3.3 constants.gd — 追加「处决演出」分区（文件尾部，格式照 #572 既有分区）

> 全部 `# DRAFT` 候补值，**禁止实现期定稿**；候选集来自 issue body + #579 矩阵 + 只狼基准 + 视觉配方 §7。

```gdscript
# ── 处决演出（# DRAFT 候补值，定稿归 #584/用户；#580 消费方，禁止实现期定稿）──
# EXECUTE_SLOWMO_SCALE / EXECUTE_SLOWMO_MS
#   三处候选归拢（PRD §1.5，禁止二选一偷定）: issue body 0.1/0.6s vs #579 S 级 0.05/0.5s vs constants 默认 0.2/0.4s
#   机制消费方 = #579 S 级矩阵（FEEDBACK_SLOWMO["S"]）；本分区为候选登记，定稿时由 #584 改 FEEDBACK_SLOWMO
const EXECUTE_SLOWMO_SCALE: Array = [0.05, 0.1, 0.2]      # # DRAFT（候选集）
const EXECUTE_SLOWMO_MS: Array = [400, 500, 600]          # # DRAFT（候选集）
# EXECUTE_INVINCIBLE_SECONDS
#   候选集: [1.0, 1.5, 2.0]（默认 1.5；覆盖 execute 5 帧 + 淡出 0.3s 有余）
#   情感断言: 处决是「赢了一场艰难的仗」的奖励时刻——无敌窗口给足演出呼吸，不耍赖
const EXECUTE_INVINCIBLE_SECONDS: float = 1.5             # # DRAFT
# EXECUTE_FADE_SECONDS
#   issue body: modulate alpha 1→0 0.3s 如墨迹消散
const EXECUTE_FADE_SECONDS: float = 0.3                   # # DRAFT
# EXECUTE_RANGE_PX
#   派生: = EXECUTE_RANGE(1.2m) × 100px/m（# DRAFT 比例，与 HITBOX_RANGE=80px 同量级）
#   候选集: [100, 120, 150]（默认 120）
const EXECUTE_RANGE_PX: float = 120.0                     # # DRAFT
# EXECUTE_EXHAUSTED_SECONDS / EXECUTE_RECOVER_RATIO / EXECUTE_EXHAUST_MULTIPLIER
#   AC3: 崩解后 3s 未处决 → 起身恢复 50% 架势 + 5s 疲惫（受架势伤害 +20%）
const EXECUTE_EXHAUSTED_SECONDS: float = 5.0              # # DRAFT
const EXECUTE_RECOVER_RATIO: float = 0.5                  # # DRAFT
const EXECUTE_EXHAUST_MULTIPLIER: float = 1.2             # # DRAFT
```

### 3.4 tests/run_tests.gd — 挂载新套件

```gdscript
_run("res://tests/test_execution_orchestrator.gd", "ExecutionOrchestrator")   # 追加（#580）
```

### 3.5 e2e_shots.json — 追加 execution 组（PRD §7 实验 3）

- 新增 `execution` group（match: `gdscripts/execution_*.gd` 等），2 shot：
  - `01_execute_strike`（处决斩落瞬间：敌人 execute 态 + 刀光弧线 + 血色粒子 + 慢动作冻结帧，settle_frames 覆盖演出窗口）
  - `02_execute_fade`（淡出消散瞬间：alpha 中段，墨迹消散构图）
- rig 路径候选（Spike 裁决，§7 Phase 0）：①扩展 `e2e_battle_stage_capture` rig 注入处决序列（battle_stage 背景 + 双火柴人）；②新建 `e2e_execution_capture` rig（instance battle_stage + 注入）；兜底「冻结效果帧」模式（对齐 #579 实验 4：freeze_time_stack=true 让刀光/血色/斩落姿态停留画面）
- 产出截图走现有 analyze_bmp.py 4 重防伪断言 + 反例断言（血色饱和度上限、无全屏发光——AC5「禁止夸张喷血、禁止奥特曼式发光」）

---

## 4. 数据流

### Flow 1: 处决触发全链路（正常路径，AC1/AC2/AC4 核心）

```
敌人 stance ≤ 0 → break_stance()（幂等，#575）
    ├── emit stance_broken(enemy) ──► CombatJudge._on_stance_broken（幂等转发 #626）
    │     ├──► ReactionController → A- 崩解反馈（全屏淡白闪 + 0.5x 慢动作 0.3s）      ← #579 已交付
    │     ├──► Hud._on_enemy_stance_broken → 处决提示（EXECUTE_HINTS，#627）          ← 零改动
    │     └──► ExecutionOrchestrator._on_stance_broken → armed=true，窗口计时 3.0s    ← 本 issue
    ▼ 玩家 attack_pressed（#573）＋ |dx| ≤ EXECUTE_RANGE_PX（闭区间）＋ armed ＋ 玩家存活
ExecutionOrchestrator._trigger_execution()
    ① player.set_invincible(EXECUTE_INVINCIBLE_SECONDS)      # AC2 玩家无敌（新接口）
    ② enemy.request_transition("execute")                     # 5 帧 anim_execute（#574 消费，先转移后杀敌）
    ③ enemy.execute_kill()                                    # AC1 杀敌（新接口，绕过 take_damage no-op）
       ├── _is_final_dead = true（停摆守卫）+ exhausted 复位 + hp 归零广播
       └── emit died(enemy, true) ──► Hud 击杀提示 / ReactionController death / EnemyAI 禁用
    ④ trigger_feedback("execute", {target_entity: enemy})    # AC4 S 级（150ms hit-stop + 0.05x 慢动作 + 刀光 + 血色粒子 + 屏震，#654）
    ⑤ fade.bind(enemy) → modulate alpha 1→0（0.3s 墙钟）→ fade_completed → queue_free   # AC2 如墨迹消散
```

### Flow 2: 错过处决窗口 → 起身疲惫（回退路径，AC3）

```
t=3.0s 窗口耗尽（编排器 _arm_elapsed ≥ STANCE_BREAK_RECOVERY_SEC，与状态机 3.0s 同源互引）
    ├── 编排器: _armed=false → enemy.recover_from_break()（幂等）
    │     ├── stance = 0.5 × stance_max（恢复 50%，AC3）
    │     └── exhausted = true（5s，EXECUTE_EXHAUSTED_SECONDS）
    └── 状态机: CombatStateStanceBreak 自动退 idle（同帧，顺序无关——幂等防双写）
    ▼ exhausted 期间
take_stance_damage(10) → 实际扣 12（×1.2 疲惫增伤，实体层乘数下沉，全消费方统一受益）
    ▼ 5s 到期
_process 清除 exhausted（乘数恢复 1.0，幂等）
    ▼ AI 侧（零改动）
idle 态 → EnemyAI 自然恢复行动（move_intent 可再次置位，_dead=false）
```

### Flow 3: 处决期间玩家受击（无敌交互，AC2 + AC4 组合）

```
处决触发瞬间 → 玩家 set_invincible(1.5s)（实体无敌期 + 判定器守卫双保险）
    ▼ 处决演出期间（慢动作 0.05x-0.1x 0.5-0.6s + 玩家无敌窗口）敌人攻击命中玩家
CombatJudge.resolve_attack
    ├── 守卫①: 玩家 state_name ∈ {dead, revive, execute}？否（玩家在 attack 态）
    ├── 守卫②: 玩家 _invincible_until_sec > now？是 → 跳过（0 伤害 0 架势 0 事件）     ← #626 已内置
    └── 目标侧: 敌人处于 execute 态（execute_kill 后保持）→ 判定器跳过受击               ← D2 结构保证
TimeScaleStack 嵌套（hit-stop 150ms → 慢动作 500ms → 逐层 pop → 终值 1.0，墙钟兜底）    ← #654 已交付
ExecutionFade 墙钟驱动 → 慢动作期间淡出照常完成（不卡顿）
```

### Flow 4: E2E 处决构图截图（AC5 用户裁决路径）

```
E2E rig 注入（Spike 裁决路径）:
    敌人 execute 态 + SwordArc.trigger_burst（刀光）+ 血色粒子 burst + freeze_time_stack=true（冻结效果帧）
    → e2e_shots.json execution 组 shot（01 斩落 / 02 淡出）→ analyze_bmp.py 4 重防伪断言
    → review agent 提交用户裁决（brief B3 通道）: 『雪夜+血色+水墨』审美许可
    → 反例断言: 无夸张喷血（血色饱和度上限）/ 无奥特曼式发光（无全屏高亮）
```

---

## 5. 边界情况与错误处理

| 边界情形 | 缓解措施 |
|---------|---------|
| 1. 处决窗口与状态机自动退出同帧竞态（3.0s 双计时） | 编排器 armed 到期与 state_changed(stance_break→idle) 双驱动恢复，`recover_from_break()` 幂等（is_stance_broken 已清 → no-op）防双写；armed 标志防重复触发 |
| 2. 玩家 attack 按下瞬间敌人已起身（同帧边界） | 编排器按 armed 为准：armed 已清 → 不触发处决，走正常 attack 流程（CombatJudge 正常登记窗口）；起身后 AI 恢复行动，无幽灵处决 |
| 3. 处决触发瞬间玩家先死（died 后 attack_pressed 仍可能到达） | `_on_attack_pressed` 守卫 `player.state_name == "dead"` → 处决不触发，防「尸体处决」演出 |
| 4. 敌人 execute_kill 后淡出期间二次事件（二次 stance_broken/受击） | `_is_final_dead` 停摆（revive 拒绝 + 转移守卫①拒绝 + 二次 died no-op）；编排器 `_on_enemy_died` → unbind_enemy 防信号泄漏；判定器 execute 态跳过 = 无受击事件 |
| 5. 距离边界恰等 EXECUTE_RANGE_PX | 闭区间（≤）触发；1px 之外不触发（与 #577 弹反窗口闭区间语义一致）；单测断言 120px 触发 / 120.1px 不触发 |
| 6. 处决慢动作 0.05x 期间淡出 | ExecutionFade 用墙钟（Time.get_ticks_msec）计算进度而非 _process delta——时间缩放不影响墙钟，0.3s 淡出照常完成（对齐 TimeScaleStack 墙钟兜底哲学） |
| 7. exhausted 5s 到期与再次崩解重叠（疲惫期 ×1.2 加速再崩解） | `break_stance()` 追加 exhausted 复位（新轮次崩解 → 处决优先）；`execute_kill()` 同样复位；到期清除幂等 |
| 8. HUD 提示与处决竞态（提示显示中按攻击） | #627 已实现：玩家进 attack/execute 态自动隐藏提示；处决成功 → died(true) 击杀提示接管；两路不会同屏残留——零改动 |
| 9. 单目标绑定（MVP 单敌人） | 编排器只 bind 一个敌人；bind_enemy 幂等重绑语义（新绑断开旧绑，防泄漏）；多敌人（#585 扩展）需按距离最近/锁定目标选择，PRD 预留 |
| 10. headless 无场景树 | 编排器/淡出 `_process(delta)` 手动推进（对齐 ReviveOrchestrator 测试模式）；淡出 `_tick(now_ms)` 测试注入墙钟，零 SceneTree/autoload 依赖 |
| 11. 玩家 attack 转移被拒（stagger/guard 态按攻击） | 处决检查不依赖玩家战斗态（仅 dead 守卫）；玩家 attack 转移被状态机拒不影响处决触发（issue 契约「靠近按攻击键自动衔接」） |
| 12. execute_kill 后状态机每帧请求 execute→idle 被拒 | 已知噪声（§1.2 Gap 2）：守卫①拒绝 + push_warning，淡出 0.3s 窗口内约 13 条；行为正确（保持 execute = 判定器守卫持续跳过），**禁止**为消噪改红线文件 |

**失败路径（PRD §5.3 防回归断言）：**
1. **误用 take_damage 处决杀敌 → 静默失败**：execute 态 `take_damage(999)` 后 hp 不变、无 died 信号（#575 既有断言保留）；`execute_kill()` 后 died(true) 恰好一次 + state 保持 execute
2. **编排器信号泄漏**（敌人 queue_free 后回调访问已释放对象）：bind/unbind 模式（对齐 ReviveOrchestrator）+ `is_instance_valid` 守卫（编排器 _process / 淡出 _tick 双处）；敌人 died 时自动 unbind
3. **起身恢复双写竞态**：`recover_from_break()` 幂等（is_stance_broken 已清 → no-op）
4. **慢动作卡死**（漏恢复）：TimeScaleStack 墙钟兜底（#654 已交付）；编排器不直写 `Engine.time_scale`（红线）
5. **E2E 截图抓不到处决瞬间**（5 帧动画 + 慢动作窗口 < settle 间隔）：冻结效果帧模式兜底（对齐 #579 实验 4）——时间栈暂停，刀光/血色粒子/斩落姿态停留画面供截图

---

## 6. 集成点

> **状态约定：** ⬜ = pending（资源已建，未接入目标）；✅ = connected（implement agent 验证）。implement agent 必须更新本表；review agent 验证所有 ⬜ 已解决或显式延期后才可 merge。

| 集成 | 本组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 处决窗口开启 | ExecutionOrchestrator | #577 | `bind_judge(combat_judge)` 订阅 stance_broken（统一出口优先）；headless 降级 `bind_enemy` 直连实体信号 | ⬜ |
| 处决键 | ExecutionOrchestrator | #573 | `bind_input(input_controller)` 订阅 attack_pressed（攻击键=处决键） | ⬜ |
| 玩家无敌 | CombatEntity.set_invincible | #575/#580 | 编排器触发时调用；take_damage/take_stance_damage 既有无敌期 no-op 自动生效 | ⬜ |
| 处决动画 | CombatEntity.request_transition("execute") | #574 | 状态名契约对齐 → consume_state → anim_execute（5 帧上撩→斩落） | ⬜ |
| 处决杀敌 | CombatEntity.execute_kill | #580/#576/#579/#581 | emit died(true) → Hud 击杀提示 / ReactionController death / EnemyAI 禁用（零改动消费） | ⬜ |
| S 级反馈 | ExecutionOrchestrator → ReactionController | #579 | `trigger_feedback("execute", {target_entity: enemy})`（#654 S 级矩阵 + TimeScaleStack + 刀光） | ⬜ |
| 淡出演出 | ExecutionFade | #580 | fade.bind(enemy) → modulate alpha 1→0 0.3s → queue_free | ⬜ |
| 起身疲惫 | CombatEntity.recover_from_break | #580/#581 | 编排器 armed 到期调用；idle 态 AI 自然恢复行动 | ⬜ |
| 处决提示/击杀提示 | Hud | #576 | 零接线（#627 已自动消费 stance_broken/died/attack 态） | ✅（既有） |
| 组装接线 | ExecutionOrchestrator 实例化 + bind | #585 | 组装层实例化并 bind_player/bind_enemy/bind_input/bind_judge/bind_feedback + 挂树 | ⬜（下游） |
| Boss/精英演出强度 | constants「处决演出」分区 | SW-019 | 消费分区常量（按实体等级读不同值），编排逻辑零改动 | ⬜（backlog） |

---

## 7. 实现阶段

| Phase | 优先级 | 组件 | 估算 | 依赖 |
|:-----:|:------:|------|:----:|------|
| Phase 0 | P0 | Spike 验证：实验 1（触发时序 headless 全链路）/ 实验 2（疲惫数值闭环）/ 实验 3（E2E rig 路径选择——扩展 battle_stage rig vs 新建 execution rig） | 0.5d | PRD §7 |
| Phase 1 | P0 | constants.gd「处决演出」# DRAFT 分区（§3.3 逐字落地） | 0.5d | — |
| Phase 2 | P0 | combat_entity.gd additive：execute_kill / set_invincible / recover_from_break + exhausted 数据 + take_stance_damage 乘数分支 + break_stance 复位 + _process 到期清除（§3.2） | 1d | Phase 1 |
| Phase 3 | P0 | execution_orchestrator.gd（§2.1 D1-D6 逐条落地） | 1d | Phase 2 |
| Phase 4 | P0 | execution_fade.gd（§2.2 墙钟驱动 + fade_completed） | 0.5d | — |
| Phase 5 | P0 | tests/test_execution_orchestrator.gd + run_tests.gd 挂载（§8 场景 A-G） | 0.5d | Phase 2-4 |
| Phase 6 | P1 | e2e_shots.json execution 组 + rig 落地（Spike 3 裁决路径） | 0.5d | Phase 3-4, Spike 3 |

---

## 8. 测试用例描述

> **约定：** 只描述测试场景，不写可运行测试代码（implement agent 交付 `tests/test_execution_orchestrator.gd`）。headless 模式：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd`。编排器/淡出 `_process(delta)` / `_tick(now_ms)` 手动推进（对齐 test_revive_orchestrator _advance 模式）；mock ReactionController 断言 trigger_feedback 调用。场景映射 PRD §7 实验 1-4。

### Scenario A: 处决触发全链路（PRD 实验 1 / AC1/AC2/AC4 核心）
- Test A1（触发成功）：new ExecutionOrchestrator + 玩家/敌人 CombatEntity（headless 免树）+ mock ReactionController；注入 stance_broken(enemy) → `_process` 推进窗口内 → 注入 attack_pressed（|dx|=100 ≤ 120）→ 断言：玩家 `_invincible_until_sec` 已置位（take_damage no-op）、敌人 state_changed "stance_break"→"execute"、execute_kill 后 died(true) 恰好一次、state 保持 "execute"、mock `trigger_feedback("execute")` 恰好一次、fade.bind 已调用
- Test A2（全程恰好一次）：全链路信号计数断言（died / trigger_feedback / fade_completed 各 1）
- Test A3（处决期间玩家无敌生效）：触发后玩家 `take_damage(15)` → hp 不变（无敌期 no-op）

### Scenario B: 触发边界（不触发处决的各路径）
- Test B1（距离外）：|dx|=121 > 120 → 不触发；玩家正常进入 attack 态（同键多义 D4）
- Test B2（窗口过期）：推进 ≥3.0s → attack_pressed → 不触发；敌人已走 recover_from_break 路径
- Test B3（玩家已死）：玩家 state=dead → attack_pressed → 不触发（防「尸体处决」）
- Test B4（未 armed）：无 stance_broken 直接 attack_pressed → 不触发（正常 attack）
- Test B5（同帧起身竞态）：state_changed(stance_break→idle) 与 armed 到期同帧 → recover_from_break 恰好一次（幂等防双写）

### Scenario C: 玩家无敌与判定器交互（PRD 实验 4 / AC2+AC4 组合）
- Test C1（受击全 no-op）：处决演出期间（玩家无敌窗口）注入 CombatJudge.resolve_attack 命中玩家 → 0 伤害 / 0 架势扣减 / 无 hit_landed 事件（判定器守卫 + 实体无敌双保险）
- Test C2（目标侧免疫）：处决期间敌人被攻击窗口命中 → 判定器跳过（execute 态守卫）
- Test C3（时间栈嵌套恢复）：hit-stop(0.05,150) → 慢动作(0.05,500) 嵌套 push → 逐层 pop → 终值 1.0；漏 pop 模拟 → tick() 墙钟强制恢复（#579 既有 AC4 保留 + 处决参数组合）

### Scenario D: 疲惫起身数值闭环（PRD 实验 2 / AC3）
- Test D1（起身恢复）：armed 到期 → recover_from_break 恰好一次；stance == 0.5 × stance_max（stance_changed 信号值断言）
- Test D2（疲惫增伤）：exhausted=true 期间 take_stance_damage(10) → stance 实际扣 12（×1.2）
- Test D3（到期恢复）：推进 5s（EXECUTE_EXHAUSTED_SECONDS）→ exhausted=false → take_stance_damage(10) 扣 10（乘数恢复 1.0）
- Test D4（幂等）：双调 recover_from_break → 第二次 no-op（无 stance 二次恢复）
- Test D5（再次崩解覆盖）：疲惫期 break_stance → exhausted 复位 + 新一轮 stance_broken 事件
- Test D6（AI 恢复）：起身后敌人 move_intent 可再次置位（AI 零改动配合验证）

### Scenario E: 淡出清理（AC2）
- Test E1（淡出推进）：bind 敌人 → `_tick(start+150)` → modulate.a ≈ 0.5 → `_tick(start+300)` → fade_completed 发出 + 目标 freed
- Test E2（墙钟不卡）：`_tick` 注入大间隔（模拟慢动作 0.05x 期间墙钟照走）→ 淡出按时完成（不依赖 delta）
- Test E3（目标释放守卫）：淡出中途目标被外部 queue_free → `_tick` 静默解绑（无访问已释放对象报错）
- Test E4（重绑）：bind 新目标 → 计时重置（alpha 从 1.0 重新开始）

### Scenario F: 失败路径防回归（PRD §5.3）
- Test F1（take_damage 红线）：execute 态 take_damage(999) → hp 不变、无 died 信号（#575 既有断言保留）
- Test F2（execute_kill 停摆）：execute_kill 后 revive() 被拒（no-op + push_warning）；二次 execute_kill no-op；died(true) 不重复
- Test F3（信号泄漏）：敌人 died → 编排器自动 unbind → 敌人 queue_free 后 `_process` 推进无报错
- Test F4（无反馈绑定）：未 bind_feedback 时触发处决 → 静默跳过（不崩溃）

### Scenario G: E2E 处决构图截图（PRD 实验 3 / AC5）
- Test G1（shot 产出）：execution 组 2 shot（01 斩落 / 02 淡出）稳定截图产出，通过 analyze_bmp.py 4 重防伪断言
- Test G2（反例断言）：截图血色饱和度 ≤ 上限（无夸张喷血）、无全屏高亮（无奥特曼发光）——供 review agent 提交用户裁决

---

## 9. 验收条件映射（源自 Issue #580 body）

- [ ] **AC1: 敌人 stance_break 后 3s 内按 execute 键触发处决动画并杀敌** —— Scenario A（armed → attack_pressed 距离内 → execute 转移 → execute_kill died(true) 恰好一次）+ Scenario B（距离外/过期/玩家死不触发）
- [ ] **AC2: 处决期间玩家与目标均无敌，处决后目标淡出消失** —— 目标侧：判定器 execute 态跳过守卫（D2）+ execute_kill 保持 execute 态；玩家侧：set_invincible + 判定器无敌期跳过（Test A3/C1）；淡出：Scenario E（alpha 1→0 0.3s → queue_free）
- [ ] **AC3: 崩解后 3s 未执行，敌人起身并恢复 50% 架势，且 5s 内疲惫（受架势伤害+20%）** —— Scenario D（recover 50% / ×1.2 / 5s 到期恢复 / 幂等 / AI 恢复）
- [ ] **AC4: 处决触发 SW-008 的强力慢动作与火花，持续时间 0.6s** —— trigger_feedback("execute") 恰好一次（S 级矩阵 #654 已实现）；慢动作时长候选 [400,500,600]ms 进「处决演出」分区 # DRAFT 登记（不裁决）；TimeScaleStack 嵌套恢复断言（Test C3）
- [ ] **AC5: E2E 截图提交用户裁决：处决瞬间构图符合『雪夜+血色+水墨』审美许可（禁止夸张喷血、禁止奥特曼式发光）** —— Scenario G（2 shot 产出 + 反例断言）→ review agent 提交用户裁决（taste 通道，#584 面板 + 用户实机）

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- **不修改** `combat_states.gd` / `combat_state_table.gd`（#575 拓扑契约；execute 态 5 帧自动退出 + stance_break 3.0s 自动退出原样保留）
- **不修改** `combat_judge.gd`（#577 判定契约；stance_broken 幂等转发 / execute 态跳过守卫原样消费）
- **不修改** `reaction_controller.gd` / `time_scale_stack.gd` / `sword_arc.gd` / `feedback_spark.gd` / `screen_shake.gd` / `flash_effect.gd`（#579 只调 `trigger_feedback("execute")` 一个入口）
- **不修改** `hud.gd` / `enemy_ai.gd` / `stick_figure_controller.gd` / `input_controller.gd` / `player_controller.gd`（零改动消费方）
- **不修改** `combat_entity.gd` 的 `take_damage` execute no-op 守卫（#575 无敌红线）；`request_transition` 守卫①不因消噪而改
- **不修改** 任何 `scenes/`（#585 组装域；编排器 bind 模式与场景解耦）、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`shandong-wolf/tests/check_compile.gd`、`shandong-wolf/tests/smoke_test.gd`
- **不新增** 第三方 addon（开源调研 PRD §6.2 结论：Godot 社区无成熟处决/finisher 实现 → 自研 + 复用项目内 SwordArc/TimeScaleStack/CombatStateExecute/anim_execute，零第三方依赖）
- **不定稿任何 `# DRAFT` 值**（慢动作三候选 / 无敌时长 / 淡出节奏 / 范围 / 疲惫数值全部留待 #584/用户裁决）
- **不写可运行测试文件**（本 issue 只产出 DESIGN/TASKS 文档；测试代码归 implement agent）

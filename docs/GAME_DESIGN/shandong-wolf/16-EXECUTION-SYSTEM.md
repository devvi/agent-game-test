# 处决系统 — 编排器 / 杀敌通道 / 无敌窗口 / 疲惫起身 / 淡出（#580/#660）

> 落盘依据：PR **#660**（feat(580) 处决系统（架势崩解 → 处决特写），已 merge 2026-08-20）←
> DESIGN `docs/DESIGN/580-execution-system.md`。
> 上游：#575 战斗实体（6 信号 + stance_break→execute 拓扑 + take_damage execute no-op 无敌红线）、
> #577 判定层（stance_broken 幂等转发统一事件出口）、#579 打击反馈（S 级 execute 矩阵 +
> TimeScaleStack 墙钟兜底 + 刀光）、#574 火柴人动画（anim_execute 5 帧上撩→斩落）、
> #576 HUD（处决提示/击杀提示自动显隐）、#578 ReviveOrchestrator（bind/unbind 幂等接线 +
> headless `_process(delta)` 手动推进 = 编排器架构模板）、#581 EnemyAI（停走/禁用零改动消费）。
> ✅ 代码状态：#660 已合并，`execution_orchestrator.gd` / `execution_fade.gd` /
> `test_execution_orchestrator.gd` 与 combat_entity.gd 3 个 additive 接口 + exhausted 数据、
> constants.gd「处决演出」# DRAFT 分区、run_tests.gd 注册、e2e_shots.json execution 组
> 全部落地 **main**（2026-08-20）。
> 全部演出参数为 `# DRAFT` 候补值（慢动作三候选 / 无敌时长 / 淡出节奏 / 范围 / 疲惫数值），
> 定稿归 #584/用户（taste 域，E2E AC5 截图用户裁决），实现期禁止二选一偷定。

## 1. 设计意图

**问题本质是「处决链路的每一块零件都已存在，唯独没有编排者」。** #575（#618）已交付
CombatEntity 6 信号 + `stance_break → execute` 拓扑 + `take_damage` execute 态 no-op 无敌红线；
#577（#626）已交付 stance_broken 幂等转发统一事件出口；#579（#654）已交付 S 级 execute 反馈组合
与 TimeScaleStack；#574（#612）已交付 anim_execute 5 帧处决动画；#576（#627）已交付处决提示自动
显隐——但全库零处 `request_transition("execute")` 调用、零距离校验、零杀敌通道（take_damage 无敌
红线挡住了所有常规伤害路径）、零淡出、零疲惫起身。本系统交付 = **ExecutionOrchestrator（编排器）
+ CombatEntity 3 个 additive 接口（execute_kill / set_invincible / recover_from_break）+
ExecutionFade（淡出）+ constants「处决演出」# DRAFT 分区 + test_execution_orchestrator.gd +
e2e execution 组 shot**。

设计哲学三条（与 PRD §4 推荐方案逐项对齐，无分歧）：

1. **编排器是唯一「指挥者」**——跨组件时序（信号→窗口→输入→转移→杀敌→演出→淡出）收敛到
   ExecutionOrchestrator 一个组件，与场景解耦（bind 模式，同 #578 先例），headless 免树可测
   （`_process(delta)` 手动推进）；
2. **实体是唯一数据持有者**——杀敌（execute_kill）、无敌（set_invincible）、起身疲惫
   （recover_from_break + exhausted 乘数）全部下沉 CombatEntity additive 接口，零外部直写实体数据
   （#575「实体层持有数据」契约）；
3. **反馈零改造**——编排器只调 `trigger_feedback("execute")` 一个入口，S 级矩阵、TimeScaleStack、
   刀光全部由 #579 既有组件执行（参数化通道在既有 API 下无参可传，候选值登记 constants 分区，
   定稿时由 #584 改 `FEEDBACK_SLOWMO["S"]`）。

## 2. 架构决策

| 决策点 | 采纳方案 | 否决方案 | 否决理由 |
|--------|---------|---------|---------|
| 编排器形态 | A：ExecutionOrchestrator（Node，bind 模式，类 #578 ReviveOrchestrator） | B：场景直连/autoload 单例 | 与场景解耦（#585 组装时实例化）+ headless 免树可测；autoload 违反「实体持数据」职责边界（PRD §4） |
| 杀敌通道 | A：`execute_kill()` 专用接口（绕过 take_damage no-op，不转移 dead 态） | 改 take_damage / 常规伤害路径 | take_damage execute no-op 是 #575 无敌红线——处决杀敌禁止绕过它去改 take_damage（PRD §8 风险） |
| 玩家无敌 | A：`set_invincible(seconds)` 复用既有无敌期机制（revive() 同款墙钟比较） | 新独立无敌机制 | 重复造轮子；既有 take_damage/take_stance_damage 无敌期 no-op 守卫自动生效（双保险） |
| 疲惫起身 | A：实体数据层 `recover_from_break()` + ×1.2 乘数下沉 take_stance_damage | 消费方各自乘 | 全消费方统一受益；零外部直写实体数据契约 |
| 淡出演出 | A：ExecutionFade 独立 Node，墙钟驱动 modulate alpha 1→0 | Tween/动画驱动 | 处决慢动作 0.05x 期间 Tween 被 time_scale 缩放卡住；墙钟（Time.get_ticks_msec）不受时间缩放影响（对齐 TimeScaleStack 兜底哲学） |
| stance_broken 信号源 | A：bind_judge 统一出口优先 / bind_enemy 直连降级，互斥切换（D3） | 同帧双订阅 | 同一 break_stance 双触发会重置 armed 计时（窗口被拉长 3s 的竞态） |
| 慢动作参数化 | A：三处候选并列登记 constants「处决演出」分区（`# DRAFT`） | 实现期二选一偷定 | 慢动作时长/淡出节奏/演出强度 = taste 域，定稿归 #584/用户（E2E AC5 截图裁决） |

## 3. 组件结构

### 3.1 execution_orchestrator.gd — 处决触发编排器

`ExecutionOrchestrator (extends Node, class_name ExecutionOrchestrator)` —— 非实体、非 autoload，
类 #578 ReviveOrchestrator：无场景树依赖，由 #585 组装实例化并 add_child（或测试直接 new +
手动 `_process`）。**Signals: 无**（编排器只消费信号、调用接口、创建淡出组件，不对外发事件）。

```gdscript
var _player: Object = null          # bind_player 注入（处决无敌目标）
var _enemy: Object = null           # bind_enemy 注入（崩解/处决/起身目标）
var _judge: Object = null           # bind_judge 注入（stance_broken 统一出口，可选）
var _input: Object = null           # bind_input 注入（attack_pressed 处决键）
var _armed: bool = false            # 处决窗口开启（stance_broken 置位，触发/起身/解绑清除）
var _arm_elapsed: float = 0.0       # 窗口计时（_process(delta) 累加，headless 手动推进）
var _stance_source: Object = null   # stance_broken 当前信号源（judge 优先 / enemy 降级，互斥切换）
var fade: Object = null             # ExecutionFade 实例（_init 创建，测试可注入/断言）

func bind_player(p) / bind_enemy(e) / bind_judge(j) / bind_input(ic) / bind_feedback(rc) -> void
#   幂等接线（先断开旧实体信号，对齐 ReviveOrchestrator 先例）；bind_enemy 订阅
#   e.state_changed（armed 失效观察）+ e.died（unbind 清理）；bind_judge 绑定 → 断开实体直连（D3）

func _on_stance_broken(entity) -> void
#   entity != _enemy → return；_armed = true + _arm_elapsed = 0（窗口开启，事件本身单发）

func _on_attack_pressed() -> void
#   处决检查: armed ∧ 玩家存活（state_name != "dead"，防尸体处决）∧ |dx| ≤ EXECUTE_RANGE_PX
#   （闭区间）→ _trigger_execution()；否则正常 attack 流程继续（同键多义 D4，两路并行）

func _trigger_execution() -> void
#   时序序列（顺序关键: 先转移后杀敌，PRD §8 风险①）:
#   ① player.set_invincible(EXECUTE_INVINCIBLE_SECONDS)   玩家无敌（AC2）
#   ② enemy.request_transition("execute")                 5 帧 anim_execute（#574 消费，幂等）
#   ③ enemy.execute_kill()                                AC1 杀敌（绕过 take_damage no-op）
#   ④ _feedback.trigger_feedback("execute", {"target_entity": _enemy})   AC4 S 级（#654）
#   ⑤ fade.bind(_enemy)                                   AC2 淡出（modulate 1→0 0.3s）

func _process(delta: float) -> void
#   armed 期间累加；_arm_elapsed ≥ STANCE_BREAK_RECOVERY_SEC（3.0s，与状态机同源互引）
#   → _armed=false + enemy.recover_from_break()（AC3 起身，幂等）
```

**设计决策（D 系列）：**
- **D1（距离校验）:** 一维坐标差 `|dx| ≤ EXECUTE_RANGE_PX` 闭区间（与 #577 弹反窗口闭区间语义一致），
  零碰撞体；`_range_px()` 经 DebugCanvas.get_value 热更新读值（release 回落 const，#584 约定）
- **D2（目标无敌结构保证）:** 处决演出期目标无敌不靠编排器——判定器守卫「execute 态受击跳过」
  （#626 内置）+ execute_kill 保持 execute 态 = 双保险
- **D3（stance_broken 单源）:** bind_judge 与 bind_enemy 直连互斥切换，禁止同帧双订阅（防 armed 计时重置竞态）
- **D4（同键多义不拦截 attack）:** 玩家攻击键 → 实体输入桥与编排器处决检查并行；处决触发时玩家
  attack 转移照常（挥刀与处决演出同帧并行），判定器对 execute 态目标跳过 = 无二次伤害/事件
- **D5（慢动作零直写）:** 编排器不直写 `Engine.time_scale`（红线）；慢动作由 trigger_feedback →
  TimeScaleStack 提供（嵌套恢复 + 墙钟兜底，#654 已保证）
- **D6（反馈注入双通道）:** 编排器暴露 `bind_feedback(rc)`（#585 组装接线）；headless 测试注入
  mock 断言 `trigger_feedback("execute")` 恰好一次；未绑定 → 静默跳过

### 3.2 execution_fade.gd — 敌人淡出组件

`ExecutionFade (extends Node, class_name ExecutionFade)` —— 由编排器 _init 创建并 add_child
（或测试直接 new）；可挂任意 CanvasItem 目标。**墙钟驱动而非 delta 累加**：`_process(delta)` 只做
转发，进度全部由 `Time.get_ticks_msec()` 差值计算——处决慢动作 0.05x-0.1x 期间（0.5-0.6s）淡出
0.3s 照常完成，不卡顿（对齐 TimeScaleStack 墙钟兜底哲学）。

```gdscript
signal fade_completed(entity: Node)   # 淡出完成（queue_free 前发出，测试断言点）

func bind(entity) -> void
#   幂等重绑：新目标重置计时（_start_ms = -1 下一 _tick 惰性记录）；目标必须可写 modulate
#   （Node2D/Control），否则 push_warning + 不绑定

func _tick(now_ms: int) -> void
#   核心推进（测试直接注入 now_ms，headless 确定性——对齐 TimeScaleStack.tick 模式）:
#   is_instance_valid 守卫（目标被外部释放 → 静默解绑，防访问已释放对象）
#   ratio = elapsed / EXECUTE_FADE_SECONDS；ratio ≥ 1 → alpha=0 + emit fade_completed + queue_free
#   否则 alpha = clampf(1 - ratio, 0, 1)（如墨迹消散，issue body 画面路径）
```

### 3.3 combat_entity.gd — 3 个 additive 接口 + 1 数据（纯追加，不改既有守卫一行）

```gdscript
func execute_kill() -> void
#   处决杀敌专用接口（#580）: 绕过 take_damage 的 execute no-op 无敌红线。
#   语义: 无视架势终结（SWORD_DAMAGE_EXECUTE=999 机械语义）；不调用 take_damage、不转移 dead 态
#   ——保持 execute 演出态（5 帧动画 + 淡出照常，判定器守卫持续跳过）。
#   停摆守卫: _is_final_dead 置位 → 不可 revive / 不可二次 died / 转移请求被守卫①拒绝
#   流程: _is_final_dead=true + exhausted 复位 + hp_1=0 + emit hp_changed + emit died(self, true)
#     （HUD 击杀提示 / ReactionController death / EnemyAI 禁用自动接管）

func set_invincible(seconds: float) -> void
#   处决/演出期无敌（#580）: 复用既有无敌期机制（revive() 同款墙钟比较）
#   _invincible_until_sec = 墙钟 + maxf(seconds, 0)；take_damage/take_stance_damage 既有
#   无敌期 no-op 守卫自动生效（双保险 + 判定器守卫）

var exhausted: bool = false                    # 新增数据（疲惫标志，AC3）
var _exhausted_until_sec: float = 0.0

func recover_from_break() -> void
#   崩解起身（#580，幂等）: is_stance_broken 已清 → no-op（防状态机退出与编排器到期双写竞态）
#   stance = stance_max × EXECUTE_RECOVER_RATIO（恢复 50%，AC3）+ exhausted=true 5s
#   + emit stance_changed
```

**take_stance_damage 追加分支**（仅追加，不改既有守卫）：`if exhausted: amount *= EXECUTE_EXHAUST_MULTIPLIER`
（×1.2 疲惫增伤，实体层乘数下沉，全消费方统一受益）。**break_stance() 追加一行** `exhausted = false`
（疲惫期再次崩解 → 新轮次优先）。**_process 追加到期清除**（5s 到期幂等恢复乘数 1.0）。

### 3.4 constants.gd — 「处决演出」# DRAFT 分区（文件尾部追加，格式照 #572 既有分区）

| 常量 | 值 | 说明 |
|------|:--:|------|
| `EXECUTE_SLOWMO_SCALE` / `EXECUTE_SLOWMO_MS` | `[0.05,0.1,0.2]` / `[400,500,600]` | 三处候选归拢（issue body 0.1/0.6s vs #579 S 级 0.05/0.5s vs constants 默认 0.2/0.4s），机制消费方 = #579 S 级矩阵，定稿时 #584 改 FEEDBACK_SLOWMO |
| `EXECUTE_INVINCIBLE_SECONDS` | `1.5` | 玩家无敌窗口（候选 [1.0,1.5,2.0]，覆盖 execute 5 帧 + 淡出 0.3s 有余；情感断言: 给足演出呼吸，不耍赖） |
| `EXECUTE_FADE_SECONDS` | `0.3` | 淡出时长（issue body 字面值: alpha 1→0 如墨迹消散） |
| `EXECUTE_RANGE_PX` | `120.0` | 距离校验（派生: EXECUTE_RANGE 1.2m × 100px/m，# DRAFT 比例，候选 [100,120,150]，与 HITBOX_RANGE=80px 同量级） |
| `EXECUTE_EXHAUSTED_SECONDS` | `5.0` | 疲惫时长（AC3） |
| `EXECUTE_RECOVER_RATIO` | `0.5` | 起身架势恢复比例（AC3: 恢复 50%） |
| `EXECUTE_EXHAUST_MULTIPLIER` | `1.2` | 疲惫期受架势伤害乘数（AC3: +20%） |

## 4. 数据流

### Flow 1: 处决触发全链路（AC1/AC2/AC4 核心）

```
敌人 stance ≤ 0 → break_stance()（幂等，#575）
    ├── emit stance_broken ──► CombatJudge（幂等转发 #626）
    │     ├──► ReactionController → A- 崩解反馈（全屏淡白闪 + 0.5x 慢动作 0.3s）   ← #579 已交付
    │     ├──► Hud → 处决提示（EXECUTE_HINTS，#627）                               ← 零改动
    │     └──► ExecutionOrchestrator._on_stance_broken → armed=true，窗口计时 3.0s  ← 本系统
    ▼ 玩家 attack_pressed（#573）＋ |dx| ≤ EXECUTE_RANGE_PX ＋ armed ＋ 玩家存活
ExecutionOrchestrator._trigger_execution()
    ① player.set_invincible(1.5s)        # AC2 玩家无敌（新接口）
    ② enemy.request_transition("execute") # 5 帧 anim_execute（#574 消费，先转移后杀敌）
    ③ enemy.execute_kill()                # AC1 杀敌（新接口，绕过 take_damage no-op）
       ├── _is_final_dead = true（停摆守卫）+ exhausted 复位 + hp 归零广播
       └── emit died(enemy, true) ──► Hud 击杀提示 / ReactionController death / EnemyAI 禁用
    ④ trigger_feedback("execute")         # AC4 S 级（hit-stop + 慢动作 + 刀光 + 血色粒子 + 屏震，#654）
    ⑤ fade.bind(enemy) → alpha 1→0（0.3s 墙钟）→ fade_completed → queue_free   # AC2 如墨迹消散
```

### Flow 2: 错过处决窗口 → 起身疲惫（回退路径，AC3）

```
t=3.0s 窗口耗尽（编排器 _arm_elapsed ≥ STANCE_BREAK_RECOVERY_SEC，与状态机 3.0s 同源互引）
    ├── 编排器: _armed=false → enemy.recover_from_break()（幂等）
    │     ├── stance = 0.5 × stance_max（恢复 50%）
    │     └── exhausted = true（5s，EXECUTE_EXHAUSTED_SECONDS）
    └── 状态机: CombatStateStanceBreak 自动退 idle（同帧，顺序无关——幂等防双写）
    ▼ exhausted 期间: take_stance_damage(10) → 实际扣 12（×1.2 疲惫增伤）
    ▼ 5s 到期: _process 清除 exhausted（乘数恢复 1.0）→ EnemyAI idle 态自然恢复行动（零改动）
```

### Flow 3: 处决期间无敌交互（AC2 + AC4 组合）

```
处决触发瞬间 → 玩家 set_invincible(1.5s)（实体无敌期 + 判定器守卫双保险）
    ▼ 处决演出期间敌人攻击命中玩家: CombatJudge.resolve_attack
    守卫①: 玩家 state_name ∈ {dead, revive, execute}？否（玩家在 attack 态）
    守卫②: 玩家 _invincible_until_sec > now？是 → 跳过（0 伤害 0 架势 0 事件）   ← #626 已内置
    目标侧: 敌人 execute 态（execute_kill 后保持）→ 判定器跳过受击              ← D2 结构保证
TimeScaleStack 嵌套（hit-stop 150ms → 慢动作 500ms → 逐层 pop → 终值 1.0，墙钟兜底）  ← #654
ExecutionFade 墙钟驱动 → 慢动作期间淡出照常完成（不卡顿）
```

## 5. 边界情况与错误处理

| 边界情形 | 缓解措施 |
|---------|---------|
| 窗口与状态机自动退出同帧竞态（3.0s 双计时） | armed 到期与 state_changed(stance_break→idle) 双驱动恢复，`recover_from_break()` 幂等防双写；armed 标志防重复触发 |
| 玩家 attack 按下瞬间敌人已起身（同帧边界） | 按 armed 为准：已清 → 不触发处决，走正常 attack 流程，无幽灵处决 |
| 处决触发瞬间玩家先死 | `_on_attack_pressed` 守卫 `player.state_name == "dead"` → 不触发，防「尸体处决」演出 |
| 敌人 execute_kill 后淡出期间二次事件（二次 stance_broken/受击） | `_is_final_dead` 停摆（revive 拒绝 + 转移守卫①拒绝 + 二次 died no-op）；编排器 `_on_enemy_died` → unbind_enemy 防信号泄漏；判定器 execute 态跳过 |
| 距离边界恰等 EXECUTE_RANGE_PX | 闭区间（≤）触发；1px 之外不触发（与 #577 弹反窗口闭区间语义一致） |
| 处决慢动作 0.05x 期间淡出 | ExecutionFade 用墙钟计算进度而非 delta——时间缩放不影响墙钟，0.3s 淡出照常完成 |
| exhausted 5s 到期与再次崩解重叠 | `break_stance()` 追加 exhausted 复位（新轮次崩解 → 处决优先）；`execute_kill()` 同样复位；到期清除幂等 |
| execute_kill 后状态机每帧请求 execute→idle 被拒 | 已知噪声（守卫①拒绝 + push_warning，淡出 0.3s 内约 13 条）；行为正确——保持 execute = 判定器守卫持续跳过，**禁止**为消噪改红线文件 |
| headless 无场景树 | 编排器/淡出 `_process(delta)` / `_tick(now_ms)` 手动推进（对齐 ReviveOrchestrator / TimeScaleStack 测试模式），零 SceneTree/autoload 依赖 |

**失败路径防回归（PRD §5.3）：**
1. **误用 take_damage 处决杀敌 → 静默失败**：execute 态 `take_damage(999)` 后 hp 不变、无 died 信号（#575 既有断言保留）；`execute_kill()` 后 died(true) 恰好一次 + state 保持 execute
2. **编排器信号泄漏**（敌人 queue_free 后回调访问已释放对象）：bind/unbind 模式 + `is_instance_valid` 守卫（编排器 _process / 淡出 _tick 双处）；敌人 died 时自动 unbind
3. **起身恢复双写竞态**：`recover_from_break()` 幂等（is_stance_broken 已清 → no-op）
4. **慢动作卡死**（漏恢复）：TimeScaleStack 墙钟兜底（#654 已交付）；编排器不直写 `Engine.time_scale`（红线）
5. **E2E 截图抓不到处决瞬间**（5 帧动画 + 慢动作窗口 < settle 间隔）：冻结效果帧模式兜底（对齐 #579 实验 4）——时间栈暂停，刀光/血色粒子/斩落姿态停留画面供截图

## 6. 测试套件

`tests/test_execution_orchestrator.gd`（run_tests.gd 挂载，headless：`godot --path shandong-wolf/
--headless --script tests/run_tests.gd`；编排器/淡出手动推进，mock ReactionController 断言
trigger_feedback 调用）：

| 场景 | 覆盖 | 关键断言 |
|------|------|---------|
| A 触发全链路 | 正常路径 + 全程恰好一次 + 玩家无敌生效 | died / trigger_feedback / fade_completed 各 1；玩家 take_damage(15) hp 不变；state 保持 execute |
| B 触发边界 | 距离外 / 窗口过期 / 玩家已死 / 未 armed / 同帧起身竞态 | 均不触发处决；recover_from_break 恰好一次（幂等防双写） |
| C 无敌交互 | 受击全 no-op / 目标侧免疫 / 时间栈嵌套恢复 | 0 伤害 0 架势 0 事件；hit-stop→慢动作嵌套逐层 pop 终值 1.0 |
| D 疲惫数值闭环 | 起身恢复 50% / ×1.2 增伤 / 5s 到期恢复 / 幂等 / 再次崩解覆盖 / AI 恢复 | stance == 0.5×max；扣 12（输入 10）；到期后扣 10 |
| E 淡出清理 | 淡出推进 / 墙钟不卡 / 目标释放守卫 / 重绑 | `_tick(+150)` alpha≈0.5 → `_tick(+300)` 信号发出 + 目标 freed |
| F 失败路径防回归 | take_damage 红线 / execute_kill 停摆 / 信号泄漏 / 无反馈绑定 | 二次 execute_kill no-op；died(true) 不重复；未 bind_feedback 静默跳过 |

## 7. E2E 截图（AC5 用户裁决证据）

`e2e_shots.json` 新增 `execution` 组（match: `gdscripts/execution_*.gd` 等），2 shot：
- `01_execute_strike`（处决斩落瞬间：敌人 execute 态 + 刀光弧线 + 血色粒子 + 慢动作冻结帧）
- `02_execute_fade`（淡出消散瞬间：alpha 中段，墨迹消散构图）

rig 路径：扩展 battle_stage rig 注入处决序列 / 新建 execution rig（Spike 裁决），兜底「冻结效果帧」
模式（对齐 #579 实验 4）。截图走 analyze_bmp.py 4 重防伪断言 + 反例断言（血色饱和度上限、无全屏
发光——AC5「禁止夸张喷血、禁止奥特曼式发光」），供 review agent 提交用户裁决。

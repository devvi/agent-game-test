# CombatEntity — 战斗实体基类：数据容器 + 唯一转移入口 + 信号契约 + 输入桥（#575/#618）

> 落盘依据：PR #618（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/575-combat-entity-state-machine.md` §2.4-§2.5。
> 上游：#572 逻辑地基（StateMachineBase + WolfConstants）、#573 输入层（InputController 意图信号）、#574 动画（consume_state 11 态契约）。
> 下游契约源：#576 HUD / #577 判定 / #578 复活 / #580 处决 / #581 敌AI / #585 组装——全部消费本层接口，本层不做判定/演出。

## 1. 设计意图

shandong-wolf 经 #572/#573/#574/#584 已有全部地基（状态机基类、数值集中地、输入意图层、动画消费契约），
但 `gdscripts/` 没有任何 hp/stance 数据容器、没有战斗状态对象、没有转移合法性执行层——**本层是全部下游
战斗系统（HUD/判定/复活/处决/敌AI）的契约源头**。

**四条设计哲学：**
1. **数据即状态**：CombatEntity 是 hp（两段式）/stance/facing 的唯一数据容器，HUD/判定/动画全部从这里读；两段血 = hp_1/hp_2 两条独立计数，`_active_life` 标记当前受击条。
2. **状态即契约**：11 个 canonical 状态名（idle/move/attack/heavy_attack/guard/parry_success/stagger/stance_break/execute/revive/dead）是本层唯一权威来源，与 #574 ANIM_CLIP_NAMES 键集逐字对齐——禁止自造状态名（parry 单列 / run 代替 move 都是红线）。
3. **转移即查表**：`request_transition(to)` 是唯一转移入口；合法性 = 数据驱动转移表（拓扑合法性）+ 守卫函数（条件合法性）两层——杜绝「任何代码直接改状态」的漂移风险。
4. **变体即参数**：玩家与敌人共用同一类，差异 = @export 参数（is_player / life_total / 血量 / 架势上限），无多态需求不造双子类。

## 2. 架构决策（PRD §4 五决策点，全部方案 A）

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|---------------|---------|---------|
| 状态机架构 | 派生 StateMachineBase + 集中转移合法性表（combat_state_table.gd） | B：enum+match 单文件；C：LimboAI addon | enum→String 契约双维护易漂移；#572 已裁决不引入第三方 |
| 玩家/敌人变体 | 单类 + @export 参数（new(is_player=true, life_total=2)） | 双子类 / 策略组合 | MVP 无多态需求，参数配置即满足 |
| 数据所有权 | 实体自持 + WolfConstants 初始化 + 信号广播 | Game autoload 全局 | 多敌人实例无法区分 |
| 输入→状态映射 | 实体内嵌 `_StateInputBridge` 订阅 InputController 信号 | 放 #585 组装层/PlayerController | 状态契约权威在本层 |
| 两段血 | `_active_life` 双条独立计数（hp_1 满条 + hp_2 半管） | 单条血 + 复活重置 | 只狼式回生机制（brief 核心机制 #4） |

> **开源调研（PRD §6.2）：** FSM 层复用 #572 自研 StateMachineBase（40 行满足三接口 + 守卫，不引入 addon）；
> 战斗实体层 GitHub 检索（mecha-party-fighters/parry-shmup/scout 等 0-2⭐ 个人习作）无 hp+stance+两段命
> 数据模型成熟先例 → 自研 CombatEntity。

## 3. 类定义

文件：`shandong-wolf/gdscripts/combat_entity.gd`（class_name `CombatEntity`，extends Node2D）。
变体参数 + 运行期数据 + 信号契约（与 #574/#576/#577/#578/#580 下游逐字对齐）：

```gdscript
extends Node2D
class_name CombatEntity

## 变体参数（issue body「差异通过参数配置」）
@export var is_player: bool = false
@export var life_total: int = 2        # 玩家 2 / 小兵 1
@export var life_1_max: float = 100.0  # 默认 WolfConstants.LIFE_1_MAX
@export var life_2_abs: float = 50.0   # 默认 WolfConstants.LIFE_2_ABS
@export var stance_max: float = 100.0  # 默认 WolfConstants.POSTURE_BREAK_THRESHOLD

## 运行期数据
var hp_1: float
var hp_2: float                        # life_total=1 时不参与
var stance: float
var facing: int = 1                    # 1 右 / -1 左
var is_stance_broken: bool = false
var state_name: String = "idle"        # canonical 状态名（#574 consume_state 消费）
var _active_life: int = 1              # 两段血标记: 1 = hp_1 受击条，2 = hp_2 受击条
var _is_final_dead: bool = false       # 终态（final=true 后禁止 revive）
var fsm: Object                        # StateMachineBase 实例
var _state_objs: Dictionary = {}       # canonical 状态名 → 状态对象（_init 预建）

## 信号（#576 HUD / #574 动画 / #577/#578/#580 下游契约）
signal hp_changed(hp_1: float, hp_2: float, active_life: int)
signal stance_changed(stance: float, stance_max: float)
signal stance_broken(entity: CombatEntity)
signal state_changed(from: String, to: String)
signal died(entity: CombatEntity, final: bool)
signal revived(entity: CombatEntity)
```

构造约定：`_init(config: Dictionary = {})` 先应用变体参数（测试经 `new({is_player=true, life_total=2})`
传入），再从 WolfConstants 初始化 hp_1=life_1_max / hp_2=life_2_abs / stance=stance_max，预建 11 状态对象
字典；`_process(delta)` 转发 fsm.update + 无敌期到期自动失效 + 输入桥轮询（is_player 启用时）。

## 4. 接口方法（签名与 PRD §8.3 逐字一致）

| 方法 | 逻辑要点 |
|------|---------|
| `request_transition(to: String) -> bool` | **唯一转移入口**。守卫序：① `_is_final_dead` 且 to≠dead → reject + push_warning；② dead 停摆（仅 revive 可出）→ reject；③ 查表 `CombatStateTable.is_legal(from, to)` 非法 → reject + 状态不漂移；④ 同态（to == state_name）→ 调当前状态对象可选 `restart()` 钩子后返回 true（attack→attack 连段）；⑤ 合法 → `fsm.transition_to` + 更新 state_name + emit state_changed(from, to) |
| `take_damage(amount: float, source: Object) -> void` | 兜底：dead/revive/execute 状态或无敌期内 → no-op（0 伤害）；amount clamp ≥0（负/NaN/Inf 视为 0 + warning）；扣当前受击条 hp → emit hp_changed；条归零 → die()；**stagger 转移**：仅状态 ∈ {idle, move, attack, heavy_attack} 时进 stagger（guard 中受击保持格挡姿态不硬直） |
| `take_stance_damage(amount: float) -> void` | 兜底：dead/revive → no-op；clamp ≥0；stance 扣减 → emit stance_changed；stance ≤ 0 → break_stance() |
| `break_stance() -> void` | 幂等：`is_stance_broken` 已 true → return（不二次广播）；置 true + stance=0 + emit stance_broken(self) + request_transition("stance_break")（guard→stance_break 表内合法） |
| `die() -> void` | `_active_life==1 and life_total==2` → emit died(self, false) + 进 dead（#578 接管复活）；否则 `_is_final_dead=true` + emit died(self, true) + 进 dead（终态；life_total=1 变体打空 hp_1 直接 final=true） |
| `revive() -> void` | 终态守卫：`_is_final_dead or life_total < 2` → no-op + warning；否则 `_active_life=2`、hp_2=life_2_abs（独立计数）、stance 清空 + is_stance_broken=false、`_invincible_until_sec = now + INVINCIBLE_SECONDS`、进 revive 态、emit revived(self) |
| `_recalc_stance_max() -> float` | 派生钩子：MVP 返回 stance_max 固定值；未来「架势上限 = 当前 HP 上限」（只狼铁律）改内部实现即可，信号契约不动 |
| `bind_input_controller(ic: Node) -> void` | 手动接线（#585 组装或测试）；保存引用 + 订阅攻击/重击/格挡/复活信号 |

## 5. 两段血与死亡复活流（AC4 + #578 契约）

```
打空 hp_1（active_life=1, life_total=2）→ die()
  → emit died(self, false) → #578 监听（自动 1s 后调 revive()；F 键路径：桥接 revive_pressed）
  → request_transition("dead") → 状态机停摆（除 revive 外全部 reject）
  → #578: entity.revive()
      → 终态守卫 ✓ → _active_life=2, hp_2=50（独立计数，不受 hp_1 残值影响）, stance 清空, 无敌 1s
      → request_transition("revive") → emit revived(self)
      → ReviveState 1.0s（REVIVE_SECONDS）→ idle
  → 再打空 hp_2（active_life=2）→ die() → emit died(self, true) + _is_final_dead=true → 终态
  → 终态后 revive() → no-op + push_warning（终态误复活守卫）
```

关键边界：dead/revive 中受击 no-op；复活无敌期（INVINCIBLE_SECONDS）内 take_damage 0 伤害、`_process`
到期自动失效；break_stance 幂等（恰好一次 stance_broken 广播，防溢出二次触发）；life_total=1 敌人无
可复活 dead（打空即 final=true，#578 只挂玩家）。

## 6. 输入桥 `_StateInputBridge`（输入→状态映射，仅 is_player）

- 启用条件：仅 `is_player == true`（enemy 变体无玩家输入，AI 驱动归 #581）
- 接线：`_ready()` 自动获取 `/root/InputController` autoload（headless 无 autoload 静默跳过）+ `bind_input_controller()` 手动兜底；测试可手动 emit 信号或直接调 request_transition（桥非必经）

| 输入源 | 映射 | 说明 |
|--------|------|------|
| `attack_pressed` | `request_transition("attack")` | idle/move/guard 可入；attack 中再按 = 连段（restart 钩子，仅收招 phase 成立） |
| `heavy_attack_pressed` | `request_transition("heavy_attack")` | idle/move/guard 可入 |
| `guard_pressed(timestamp_ms)` | `request_transition("guard")` | 时间戳本层不消费（弹反判定归 #577） |
| `guard_held`（_process 轮询） | 释放检测：state==guard 且未按住 → `request_transition("idle")` | 按住期间状态机天然保持 guard 姿态 |
| `revive_pressed` | `revive()` | #578 F 键驱动路径（自动路径由 #578 监听 died 计时） |
| `get_move_axis()`（_process 轮询） | axis≠0 且 state ∈ {idle,move} → move；axis==0 且 state==move → idle；同时 `facing = sign(axis)` | **move/idle 驱动方**（PRD §4.4 未定义，本设计补全）；垫步/跳不映射（留在移动层） |

> 桥的移动轴轮询与 PlayerController 位移读取同一 `get_move_axis()`，二者无写冲突（PlayerController 只动 velocity，桥只动状态名与 facing）。

## 7. 下游契约（集成点）

| 集成 | 本层接口 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 状态名消费 | `state_name` / `state_changed` | #574 | #585 组装层 wire `state_changed → consume_state(to)`；状态名与 ANIM_CLIP_NAMES 逐字对齐（单测断言 11/11） | ⬜ 待 #585 |
| HUD 血条/架势条 | `hp_changed(hp_1,hp_2,active_life)` / `stance_changed(stance,stance_max)` | #576 | 信号订阅 | ⬜ 待 #576 |
| 判定入口 | `take_damage(amount,source)` / `take_stance_damage(amount)` / `stance_broken` / parry_success 状态 | #577 | 接口调用 + 信号 | ⬜ 待 #577 |
| 复活驱动 | `died(final=false)` / `revive()` / `revived` | #578 | 接口调用（自动 1s 或 F 键两路兼容） | ⬜ 待 #578 |
| 处决驱动 | stance_break→execute 转移通道 / `stance_broken` | #580 | 接口调用（request_transition("execute")） | ⬜ 待 #580 |
| 敌 AI 实体 | enemy 变体参数（life_total=1 等） | #581 | 实例化参数 | ⬜ 待 #581 |
| 场景组装 | CombatEntity + PlayerController + StickFigureController | #585 | 实例化 + 信号桥接 | ⬜ 待 #585 |

## 8. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #575 | 战斗实体基类与状态机（本文件所属） | 已合并（#618） |
| #576/#577/#578/#580/#581/#585 | 下游消费方 | 待实现 |


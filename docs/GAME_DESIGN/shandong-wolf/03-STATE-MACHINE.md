# StateMachineBase — 通用状态机基类（#572）

> 落盘依据：PR #599（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/572-scaffold-main-entry.md` §2.2。
> 通用地基：不设计任何具体状态（#575 战斗状态机职责），只提供三接口契约与转移守卫。

## 1. 设计意图

#575 战斗状态机、#577 拼刀判定都需要状态机，若无基类将各自从零造轮子。本基类取「最小必要结构」：状态对象模式（gdquest 最小 FSM 惯用模式，零依赖参考），约 40 行自研即满足，**不引入第三方 addon**（PRD §6.2 调研：LimboAI 2962⭐ / gd-YAFSM 668⭐ / gdquest-design-patterns 443⭐ 均否决）。

## 2. 架构决策

| 方案 | 内容 | 裁决 |
|------|------|:----:|
| A（采纳） | 自研通用 RefCounted 基类，状态对象 enter/exit/update 三接口 | ✅ 通用、无依赖、headless 可直接实例化单测 |
| B（否决） | 第三方 addon（LimboAI 等） | ❌ 过度设计，40 行自研满足 |
| C（否决） | enum+match 单文件 FSM（mini-pong 模式） | ❌ 场景级非通用，绑定具体状态枚举 |

与 mini-pong `game_state_machine.gd` 的关键差异：mini-pong 是 enum+match 的场景级 Node FSM（`_transition_lock` 防重入）；本基类是**通用** RefCounted（不绑定场景、不绑定状态枚举），`has_method` 鸭子类型守卫替代类型约束（Godot 无接口），**不复制 mini-pong 代码**（PRD §1.4 范围边界）。

## 3. 类定义

文件：`shandong-wolf/gdscripts/state_machine.gd`（类名 `StateMachineBase`，extends RefCounted）。

```gdscript
var current_state: Object = null      # 当前状态对象（可为 null = 空状态）
var _transition_locked: bool = false  # 防重入锁（transition 进行中禁止再 transition）

# 三接口契约（状态对象实现，本基类不实现具体逻辑）:
#   func enter() -> void          # 进入状态：初始化
#   func exit() -> void           # 退出状态：清理
#   func update(delta: float) -> void  # 每帧逻辑（由基类 update() 转发）

func transition_to(new_state: Object) -> void   # 同态守卫 + 防重入守卫
func update(delta: float) -> void               # 转发给 current_state.update(delta)
```

## 4. 转移语义与守卫

| 场景 | 行为 |
|------|------|
| 正常转移 | `A.exit()` 先于 `B.enter()`（调用序契约） |
| 同态转移（目标 == 当前） | 静默忽略，无任何回调 |
| 重入转移（enter() 内嵌套） | `_transition_locked` 锁：push_warning + 忽略 |
| 空状态（current_state == null） | update()/transition_to() 均 no-op 安全 |
| 目标为 null | 仅 exit 当前状态，不 enter |

`STATE_MACHINE_MAX_TRANSITIONS` 常量预留给后续若需「单帧单转移」硬限制（本期仅防重入锁，不额外实现计数）。

## 5. 测试（test_state_machine.gd）

两个 mock 状态对象（记录 enter/exit/update 调用日志），直接 `StateMachineBase.new()` 实例化断言：

- **A 调用序**：正常转移日志序 == `[A.exit(), B.enter()]`；null → A 仅 `A.enter()`；update 转发 delta 原值
- **B 同态守卫**：同对象二次转移无回调；守卫不破坏后续 update 转发
- **C 防重入**：enter() 内嵌套转移被拦截（B.enter 未调用 + push_warning）；转移完成后锁释放，可再次转移
- **D 空状态**：null 时 update no-op；transition_to(null) 仅 exit 不 enter

## 6. 集成点

| Integration | Target Issue | How | Status |
|-------------|:---:|-----|:---:|
| 战斗状态机派生 | #575 | `combat_states.gd` 11 个战斗状态对象派生本基类（CombatStateBase + make_state 工厂，转移表见 09 章） | ✅ 已合并（#618） |

## 7. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #572 | 逻辑地基（本文件所属） | 已合并（#599） |
| #575 | 战斗实体状态机（派生本基类） | 已合并（#618） |

# 输入层 — Input Map + InputController 意图事件/缓冲 + PlayerController（#573/#611）

> 落盘依据：PR #611（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/573-input-map-player-controller.md`；
> PRD `docs/PRD/573-input-map-player-controller.md`（research PR #602，已 merge）。
> 上游地基：#572（Game autoload 锚点 + constants.gd + StateMachineBase），本层通过 `[autoload]` 追加挂接，**不改动 game.gd**。

## 1. 设计意图

shandong-wolf 经 #572 已有逻辑地基（constants/state_machine/Game autoload）但**输入层零存在**：
`project.godot` 无 `[input]` 段（`Input.is_action_pressed("game_*")` 直接报错）、无玩家实体、无输入缓冲、
无意图事件契约。本层交付 = **Input Map 9 动作 + InputController（意图事件发射 + 时间戳缓冲队列）+
PlayerController（CharacterBody2D 加速度模型）+ 输入层常量分区**，是后续 #3（动画）、#6（拼刀/弹反/架势）、
#575（战斗状态机）的输入前置。

**只狼输入哲学（2026-08-19 用户拍板）为强制约束：**
①同键多义——`game_guard` 一键双义（按住=格挡姿态 / 按下时机=弹反输入，语义分离为 `guard_pressed` 边沿事件
与 `guard_held` 持续事件）；攻击键=处决键（**不新增 `game_execute` 映射**，处决上下文判定闭环归 #6）；
`game_dash` 轻按/按住双义（< 200ms=垫步事件 / ≥ 200ms=冲刺态）。
②输入缓冲——收招前 100-200ms 窗口内输入自动衔接（时间戳 FIFO 队列，消费方 poll）。
③无输入吞噬——队列无覆盖语义，300ms 3 连击全保留，上限 8 条「拒新不丢旧」。
④前摇可取消——本层保证缓冲不丢输入、事件不被场景状态吞；取消语义由消费方（#575/#6）实现。

**组件隔离（红线）：** InputController 是纯机械输入层，不接触战斗逻辑/动画/场景状态——只做
读 Input Map → 边沿检测 → 发信号；维护缓冲队列；提供移动轴查询。`guard_pressed` 仅含时间戳（原始按下事件），
弹反窗口值（`PARRY_WINDOW_FRAMES`）只读传递不判定，判定归 #6。PlayerController 只消费移动轴（连续轴，不进缓冲），
攻击/格挡/垫步等边沿事件由消费方直接监听 InputController 信号，本类不转发（单一职责）。

## 2. Input Map（project.godot `[input]` 段，9 动作）

统一 `game_` 前缀；移动为连续轴（`Input.get_axis`，不进缓冲），其余 7 个为边沿事件（进缓冲 + 发信号）。

| 动作 | 语义 | 主键 | 候选键 | 备注 |
|------|------|------|--------|------|
| `game_move_left` | 横板左移（轴） | A | ← | 连续轴，不进缓冲 |
| `game_move_right` | 横板右移（轴） | D | → | 连续轴，不进缓冲 |
| `game_light_attack` | 轻击 | J | 鼠标左键 | 边沿事件；处决复用此键（无独立 execute 键，AC3） |
| `game_heavy_attack` | 重砍（蓄力预留） | K | 鼠标右键 | 边沿事件 |
| `game_guard` | 格挡/弹反同键 | **L** | — | 双义：按住=格挡姿态 / 按下时机=弹反输入 |
| `game_dash` | 垫步/冲刺 | **Shift** | — | 轻按(<200ms)=垫步 / 按住(≥200ms)=冲刺 |
| `game_jump` | 跳跃 | Space | — | 边沿事件 |
| `game_interact` | 交互/捡刀 | E | — | 边沿事件 |
| `game_revive` | 两条命倒地复活 | F | — | 边沿事件；无提示时照发（消费方裁决） |

> **键位裁决（GDD 补记）：** issue 映射表 guard 与 dash 曾同写「Shift」，若共用同键则同帧「按住」语义冲突
> （按住=格挡 vs 按住=冲刺无法共存）。以 AC1/DESIGN §2.1 裁决为准：`game_guard`=L 独键，`game_dash`=Shift。
> 物理键值：A/D=65/68、J=74、K=75、L=76、Shift=4194325、Space=32、E=69、F=70、←/→=4194319/4194321。

`[autoload]` 段在 `Game` 之后追加 `InputController="*res://gdscripts/input_controller.gd"`（声明顺序保证
初始化顺序，InputController 只用 preload constants，无运行时依赖 Game）。

## 3. InputController（autoload 单例，意图事件层）

**注册：** `project.godot [autoload]`，全局名 `/root/InputController`（消费方 #3/#6/#575 直接
`InputController.<signal>.connect(...)`）。`class_name InputController`，`extends Node`。

**8 个意图事件信号：**

```gdscript
signal attack_pressed                          # 轻击（处决复用此键，上下文判定归 #6）
signal heavy_attack_pressed                    # 重砍
signal guard_pressed(timestamp_ms: int)        # 格挡键按下时机（原始事件，仅时间戳）
signal guard_held                              # 格挡键按住持续（每帧）
signal dash_pressed                            # 垫步（轻按，< DASH_HOLD_THRESHOLD_MS）
signal jump_pressed
signal interact_pressed
signal revive_pressed
```

**缓冲 API（消费方 #6/#575 调用）：**

```gdscript
func poll_buffer() -> Dictionary              # FIFO 出队（跳过超窗条目），无则返回 {}
func peek_buffer() -> Dictionary              # 只读队首，不出队
func buffer_size() -> int                     # 当前队列长度
func is_sprinting() -> bool                   # dash 按住 ≥ DASH_HOLD_THRESHOLD_MS
```

**核心机制：**
- **边沿检测**：`_was_pressed` 状态表（action → bool）做按下边沿检测，`EDGE_ACTIONS` 表内 7 动作逐帧扫描；
  按下边沿 → `_push_buffer`（时间戳 FIFO）+ 对应信号恰 1 次；`guard_held` 按住期间每帧发射（与
  `guard_pressed` 语义独立，互不覆盖）。
- **缓冲无吞噬**：`_buffer: Array[Dictionary]`，条目 `{action, timestamp_ms}`；上限 `INPUT_BUFFER_MAX=8`
  满时拒新不丢旧；`_clear_expired` 每帧过滤超窗（> `INPUT_BUFFER_WINDOW_MS`=150ms）条目——超窗清理不算吞噬。
- **dash 双义**：按下记 `_dash_press_time_ms`；释放时 `held_ms < DASH_HOLD_THRESHOLD_MS(200)` → emit
  `dash_pressed`（垫步）；按住 ≥ 阈值 → `_sprinting=true`（`is_sprinting()` 查询，释放复位）。
- **Input Map 校验**：`_ready()` 用 `ALL_ACTIONS`（9 动作全清单）逐个 `InputMap.has_action`，缺失 →
  `push_error` 列出并降级运行不 crash（PRD §5.3-1）。
- **参数容错**：`_safe_window_ms()` 将窗口 clamp 到 ≥1ms，非法值（0/负/NaN）不崩。

## 4. PlayerController（玩家移动实体）

**注册：** `class_name PlayerController`，`extends CharacterBody2D`；`_ready()` 时 `add_to_group("player")`
（#6 近距探测/处决判定基础设施）。玩家实体场景挂接由后续战斗场景 issue 负责（Main.tscn 红线不改），
smoke/单测程序化实例化。

**移动模型（加速度，冷冽干脆）：**

```gdscript
func _physics_process(delta: float) -> void:
    var dir: float = InputController.get_move_axis()
    velocity.x = move_toward(velocity.x, dir * C.MOVE_MAX_SPEED, C.MOVE_ACCELERATION * delta)
    velocity.y = 0.0        # 无重力（横板战斗判定面）
    move_and_slide()
```

**手感参数（# DRAFT，定稿归 #584）：** `MOVE_ACCELERATION=1200.0`（px/s²，起步 2 帧达标）、
`MOVE_MAX_SPEED=300.0`（px/s）——2s@60fps 位移 ≥100px（AC6 达标基础）。

**红线：** 不消费边沿事件（事件由 #3/#6/#575 直接监听 InputController，本类不转发，保持单一职责）。

## 5. 输入层常量（constants.gd 追加分区，全部 # DRAFT）

`# ── 输入层（# DRAFT 候补值，待 #584 定稿）──` 分区，追加于帧节奏分区之后：

| 常量 | DRAFT 值 | 说明 |
|------|:---:|------|
| `INPUT_BUFFER_WINDOW_MS` | `150` | 输入缓冲窗口（AC4 ∈ [100,200]，越大越宽容） |
| `INPUT_BUFFER_MAX` | `8` | 缓冲队列上限（拒新不丢旧，AC5 边界） |
| `DASH_HOLD_THRESHOLD_MS` | `200` | 垫步/冲刺双义分界（轻按=垫步 / 按住≥此值=冲刺） |
| `MOVE_ACCELERATION` | `1200.0` | 移动加速度 px/s²（起步 2 帧达标） |
| `MOVE_MAX_SPEED` | `300.0` | 移动最高速度 px/s |

`PARRY_WINDOW_FRAMES=12`（# DRAFT）保持只读不改：InputController 仅将 `guard_pressed` 时间戳 + 窗口值暴露给 #6，
本层不读窗口做判定（窗口值异常 ≤0 也不影响输入层发射）。

## 6. 数据流

**意图事件链（边沿）：** 物理按键 → Input Map（`game_*`）→ InputController `_process` → 边沿检测
（`_was_pressed` false→true）→ `push_buffer({action, timestamp_ms})` + emit 信号 → 消费方
（#4/#575 攻击态、#6 弹反/格挡判定、#3 动画关键帧）。

**移动链：** 按住 D → `get_axis("game_move_left","game_move_right")=+1.0` → PlayerController
`move_toward(velocity.x, 1.0*300, 1200*delta)` → `move_and_slide()` → position.x 递增（2s ≈ 300px 达最高速）。

**垫步/冲刺时间分叉：** 按下 Shift → 记 `_dash_press_time_ms`；释放 <200ms → emit `dash_pressed`（垫步）；
按住 ≥200ms → `is_sprinting()=true`（冲刺态，消费方驱动）。

**缓冲消费：** 收招前窗口内输入入队 → 消费方在收招结束帧 `poll_buffer()` FIFO 出队衔接下一击；
300ms 3 连击全入队无覆盖（AC5）；超窗条目每帧清理（不算吞噬）。

## 7. 集成点（本层契约，消费方待接）

| 集成 | 本层提供 | 目标 issue | 方式 |
|------|---------|:---:|------|
| 弹反判定 | `guard_pressed(timestamp_ms)` + 只读 `PARRY_WINDOW_FRAMES` | #6 | 时间戳对齐攻击帧做窗口判定（本层不判定） |
| 格挡判定 | `guard_held`（每帧持续） | #6 / #4 | 按住持续事件 → 格挡姿态 |
| 处决闭环（AC3） | `attack_pressed`（复用攻击键，无独立 execute 键） | #6 | 上下文判定归 #6；本层保证事件可达 |
| 战斗状态机驱动 | `poll_buffer()` + 全部意图事件 | #575 | 消费事件/缓冲驱动状态迁移 |
| 玩家近距探测 | `add_to_group("player")` | #6 | body_entered/body_exited 近距探测依赖 |
| 数值定稿 | 输入层 # DRAFT 分区 + `PARRY_WINDOW_FRAMES` | #584 | 候补值 → 用户定稿（替换值 + 去 DRAFT 标记） |

## 8. 测试与验证（#611 已交付）

- `tests/test_input_controller.gd`：缓冲无吞噬（3 连击全保留/超窗清理/上限拒新不丢旧）、同键双义
  （guard 按下恰 1 次 + 按住持续、dash 轻按垫步/长按冲刺）、时间戳语义、Input Map 缺失校验、参数 clamp。
- `tests/test_player_controller.gd`：2s 位移 ≥100px、加速度收敛于 MOVE_MAX_SPEED、左右同按抵消、
  无输入静止、group "player" 归属。
- `tests/smoke_test.gd` 扩展（AC6 载体）：程序化实例化 PlayerController → `Input.action_press("game_move_right")`
  120 帧 → 断言 `position.x ≥ 100`；connect attack/guard/dash 信号 → 手动 `_process(0.016)` 驱动断言均被捕获。
  ⚠️ 实测教训：InputController 是 lazy autoload，`--script` 主脚本编译早于 autoload 注册，
  **标识符 `InputController` 不可解析** → 必须 `root.get_node_or_null("InputController")` 运行时获取、
  `load()` 而非 `preload()`（CI smoke 失败根因，已修复）。
- `tests/run_tests.gd`：挂载 4 套件（StateMachine / Constants / InputController / PlayerController +
  DebugCanvas），`pass==0 → 退出非 0`（防挂载遗漏静默绿）。

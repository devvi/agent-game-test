# Design: [Feature] 输入映射与玩家控制器 — Input Map + InputController 意图事件 + 输入缓冲 + PlayerController

> **Parent Issue:** #573
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4.4 推荐组合 —— 四个子系统**全部确认采纳方案 A**（输入层=独立 InputController + 信号意图事件；输入缓冲=时间戳 FIFO 队列（窗口/上限 constants.gd 参数化）；玩家移动=CharacterBody2D + 加速度模型；Input Map=9 个 `game_` 前缀动作入 project.godot `[input]` 段）；方案 B（PlayerController 内直接轮询）/ C（第三方输入插件 drkitt/godot-input-buffer 等）显式否决，理由同 PRD §4 与 §6.2 开源调研结论
> **Reference PRD:** `docs/PRD/573-input-map-player-controller.md`（research PR #602 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/572-scaffold-main-entry.md`（Game autoload 锚点 + constants `# DRAFT` 分区 + StateMachineBase 基座，本设计在其上挂输入层）；其 §6 集成点已预留「autoload 段 Game 之后追加」挂接方式
> **所有权:** `content_ownership: mechanical`（输入层 = 机械工程，零品味裁决空间；弹反窗口/加速度/缓冲窗口等手感数值全部保持 `# DRAFT` 候补值，定稿归 #584 / 分解 id 13，本设计只读 `PARRY_WINDOW_FRAMES` 不裁决）
> **深度:** standard（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=2 标注 depth: standard；GitHub 无 depth 标签）—— 8 文件 / 3 新组件 + 2 修改 + 3 测试入口 / 6+ 独立子任务跨 4 子系统 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，同 #572 先例）
> **红线:** 只动 `shandong-wolf/` 下 8 文件（4 新建 + 4 修改，见 §3）；**绝不触碰** `mini-pong/`、`shandong-wolf/scenes/Main.tscn`（含 PostMergeProbeLabel）、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`（GDD 是 post-merge agent 职责）；零美术资产/零插件 addon/零像素帧；不写任何可运行测试文件（仅 §8 测试用例描述）

---

## 1. 架构总览

**问题本质是「有地基、无输入层」。** shandong-wolf 经 #572 已具备逻辑地基（`constants.gd` WolfConstants 数值集中地 + `state_machine.gd` StateMachineBase + `game.gd` Game autoload 锚点），但 `project.godot` **零 Input Map 定义**（`Input.is_action_pressed("game_*")` 会直接报错）、`gdscripts/` 无玩家实体、无输入缓冲、无意图事件契约。后续 #3（火柴人动画）、#6（拼刀/弹反/架势判定）、#575（战斗状态机）全部依赖输入事件作为前置——本 issue 交付 = **Input Map 9 动作 + InputController（意图事件发射 + 时间戳缓冲队列）+ PlayerController（CharacterBody2D 加速度模型）+ 输入层常量分区 + 测试用例描述**。

**设计哲学：只狼输入哲学（2026-08-19 用户拍板）为强制约束。** ①同键多义——`game_guard` 一键双义（按住=格挡姿态 / 按下时机=弹反输入，语义分离为 `guard_pressed`（边沿，仅时间戳）与 `guard_held`（持续），判定归 #6 消费，本层不做判定）；攻击键=处决键（**不新增 `game_execute` 映射**，处决上下文判定闭环归 #6）；`game_dash` 轻按/按住双义（< 阈值=垫步事件 / ≥ 阈值=冲刺态）。②输入缓冲——收招前 100-200ms 窗口内输入自动衔接（时间戳 FIFO 队列，消费方 poll）。③无输入吞噬——队列无覆盖语义，300ms 3 连击全保留。④前摇可取消——攻击前摇可取消为垫步：InputController 保证缓冲不丢输入、事件不被场景状态吞掉，取消语义由消费方（#575/#6）基于缓冲与事件实现。

**组件隔离：InputController 是纯输入层（机械），不接触任何战斗逻辑。** 它只做三件事：读 Input Map → 边沿检测 → 发信号；维护缓冲队列；提供移动轴查询。`guard_pressed` 仅含时间戳（原始按下事件），弹反窗口值只从 `constants.gd` 只读传递（本层不判定）。PlayerController 只消费移动轴（连续轴，不进缓冲队列），攻击/格挡/垫步等事件信号由消费方（#3/#6/#575）独立监听。

```
                 ★ Issue #573 本设计（shandong-wolf 输入层）
┌────────────────────────────────────────────────────────────────────────────┐
│ 新建（4 文件，全部 shandong-wolf/ 下）                                        │
│  gdscripts/input_controller.gd   InputController（Node，autoload 单例）      │
│    └─ 8 意图事件信号 + 时间戳缓冲队列 + 边沿检测 + guard/dash 双义            │
│  gdscripts/player_controller.gd  PlayerController（CharacterBody2D）        │
│    └─ 加速度模型位移 + group "player"（#6 近距探测依赖）                      │
│  tests/test_input_controller.gd  单测: 缓冲无吞噬/同键双义/时间戳语义          │
│  tests/test_player_controller.gd 单测: 位移断言/加速度/事件捕获               │
├────────────────────────────────────────────────────────────────────────────┤
│ 修改（4 文件）                                                               │
│  project.godot              [input] 段 9 个 game_* 动作 + [autoload] 追加    │
│                             InputController（Game 之后，顺序保证）           │
│  gdscripts/constants.gd     追加输入层 # DRAFT 分区（缓冲窗口/上限/垫步阈值/   │
│                             移动加速度/最高速度）                             │
│  tests/run_tests.gd         挂载 test_input_controller + test_player_controller │
│  tests/smoke_test.gd        扩展 AC6 断言（模拟按键驱动位移 ≥100px + 信号捕获）│
├────────────────────────────────────────────────────────────────────────────┤
│ 验证（0 改动）: scenes/Main.tscn 保持纯声明式；game.gd 不修改                  │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    ▼
              物理按键 (A/D/J/K/L/Shift/Space/E/F)
                    │  Input Map (game_*) — project.godot [input]
                    ▼
              InputController (autoload，Game 之后初始化)
                    ├── 连续轴: get_move_axis() ◄── PlayerController 每帧查询
                    ├── 边沿事件: 缓冲队列（时间戳, INPUT_BUFFER_WINDOW_MS）→ poll
                    ├── guard_pressed(timestamp_ms) ──► #6 弹反判定（本层不判定）
                    ├── guard_held(每帧) ──────────────► #6 格挡 / #4 格挡姿态
                    ├── attack_pressed ────────────────► #4/#575 攻击态（处决复用此键）
                    └── 全部意图事件 ──────────────────► #3 火柴人动画
```

**与 PRD 方案裁决的一致性：** PRD §4.1/§4.2/§4.3 各推荐方案 A，§4.4 汇总推荐组合；本设计逐项确认采纳，无分歧。PRD §7 三个 Spike（E1 缓冲无吞噬 / E2 同键双义语义分离 / E3 移动手感标定）为 implement Phase 0 执行项，其结果对本设计无结构性影响（仅验证契约与参数初值，失败路径 PRD §5.3 已给回退）。

### 1.1 既有实现状态（Prior Implementation Status，plan agent 逐条核实）

| 文件 | 当前状态（2026-08-19 侦查） | 与 #573 的差距 |
|------|----------------------------|---------------|
| `shandong-wolf/project.godot` | ✅ name=山东抗日之狼、`[application]`/`[display]`/`[autoload]`（Game 已注册）；**无 `[input]` 段** | ❌ 新增 `[input]` 段（9 动作）+ `[autoload]` 追加 InputController |
| `shandong-wolf/gdscripts/constants.gd` | ✅ WolfConstants（#599 交付）：`PARRY_WINDOW_FRAMES=12`（# DRAFT）等 5 分区 + 机械常量；**无输入层分区** | ❌ 追加输入层 `# DRAFT` 分区（§2.4） |
| `shandong-wolf/gdscripts/game.gd` | ✅ Game autoload 锚点，头注释明言「后续系统（输入/战斗/音频）挂接于此」 | 无改动（挂接通过 `[autoload]` 追加实现，不动 #572 交付文件） |
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ StateMachineBase（#599 交付） | 无改动（#575 消费本层事件） |
| `shandong-wolf/gdscripts/` 玩家实体 | ❌ 不存在（无 player 脚本、无 `is_in_group("player")`） | ❌ 新建 player_controller.gd |
| `shandong-wolf/scenes/Main.tscn` | ✅ 纯声明式标题场景（#562/#563/#570） | 无改动（红线；玩家实体由 smoke 程序化实例化） |
| `shandong-wolf/tests/run_tests.gd` | ⚠️ 挂载 2 套件（test_state_machine + test_constants） | ❌ 追加 2 套件挂载 |
| `shandong-wolf/tests/smoke_test.gd` | ⚠️ 骨架探针（仅「SMOKE OK」） | ❌ 扩展 AC6 断言（位移 + 信号捕获） |
| `shandong-wolf/tests/check_compile.gd` | ✅ 遍历 gdscripts/+tests/ 自动纳入新脚本 | 无改动 |
| mini-pong 先例（paddle.gd 轮询） | ✅ 即时键盘轮询模式 | **反例**——不采用（无缓冲无事件，违反只狼输入哲学，PRD §1.4） |

### 1.2 PRD 断言 vs 实际代码交叉对照（含设计裁决）

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| project.godot 无 `[input]` 段 | ✅ 属实（全文仅 application/display/autoload） | 新增 `[input]` 段，不动现有段 |
| `game_` 前缀动作全部缺失 | ✅ 属实（Input Map 零动作） | 9 动作全清单（§2.1） |
| `PARRY_WINDOW_FRAMES=12` 存在于 constants.gd | ✅ 属实（# DRAFT，候补 [8,10,12,14]） | 只读不修改（§2.4 注释引用） |
| Game autoload 注释预留输入挂接点 | ✅ 属实（「后续系统（输入/战斗/音频）挂接于此」） | 通过 `[autoload]` 追加 InputController 实现（Game 之后，初始化顺序保证） |
| InputController 挂 Game autoload 下（PRD §3.1 表述） | — | **裁决：** 采用 #572 DESIGN §6 预留的「autoload 段 Game 之后追加」方式（`/root/InputController` 单例），**不修改 game.gd**（保持 #572 交付文件零改动）；PRD 表述「挂 Game 下」理解为逻辑归属而非 add_child 实现 |
| PRD §3.1 称「8 个 game_ 动作」但 §3.1.1 表格列 9 行（move_left/move_right 拆两轴） | — | **裁决：** 按表格 9 个动作落地（8 个逻辑操作拆成 9 个 Input Map 动作），AC1 验证按 9 动作断言 |
| PRD §3.1 直接影响表未列 smoke_test.gd，但 AC6 验证方式 = smoke 命令断言位移+信号 | — | **裁决：** smoke_test.gd 必须扩展（AC6 唯一验证载体），纳入修改清单 → 总文件数 8（§3） |
| 无 addons 目录，Space 键无插件冲突 | ✅ 属实 | 零插件红线保持（§6.2 调研结论） |
| `Input.action_press` 可驱动 headless 输入（AC6） | ✅ mini-pong smoke 先例（`Input.action_press` 在 --script 模式可用） | smoke 采用 action_press 驱动 + 定步长帧推进（§8 Scenario I） |

---

## 2. 新组件 — 详细设计

### 2.1 `shandong-wolf/project.godot` `[input]` 段（修改，AC1 交付物）

- **位置:** `shandong-wolf/project.godot` 追加 `[input]` 段（文件末尾，`[autoload]` 段之后追加 InputController 行）
- **9 个动作全清单**（统一 `game_` 前缀；Godot 4.7 `physical_keycode` 值供 implement 构造 `[input]` 段）：

| 动作名 | 语义 | 主键 | physical_keycode | 候选键 | 备注 |
|--------|------|------|------------------|--------|------|
| `game_move_left` | 横板左移（轴） | A | 65 | ←（4194319） | `Input.get_axis` 连续轴，不进缓冲 |
| `game_move_right` | 横板右移（轴） | D | 68 | →（4194321） | 同上 |
| `game_light_attack` | 轻击 | J | 74 | 鼠标左键（button_index=1） | 边沿事件 → 缓冲 |
| `game_heavy_attack` | 重砍（蓄力预留） | K | 75 | 鼠标右键（button_index=2） | 边沿事件 → 缓冲 |
| `game_guard` | 格挡/弹反同键 | **L** | 76 | — | 双义：按住=格挡姿态 / 按下时机=弹反输入 |
| `game_dash` | 垫步/冲刺 | **Shift** | 4194325 | — | 轻按(<阈值)=垫步 / 按住(≥阈值)=冲刺 |
| `game_jump` | 跳跃 | Space | 32 | — | 边沿事件 |
| `game_interact` | 交互/捡刀 | E | 69 | — | 边沿事件 |
| `game_revive` | 两条命倒地复活 | F | 70 | — | 边沿事件；无提示时照发（消费方裁决） |

> **键位裁决（表格歧义澄清，写入 PR 说明 + GDD 补记）：** issue 映射表格挡/弹反写「L/Shift」而垫步/冲刺也是 Shift——若 guard 与 dash 共用 Shift，同帧「按住」语义冲突（按住=格挡姿态 vs 按住=冲刺无法共存）。**以 AC1 为准：`game_guard`=L 独键，`game_dash`=Shift**（PRD §3.1.1 裁决一致）。
>
> **无 `game_execute`（处决）映射**（AC3）：处决复用 `game_light_attack`（attack_pressed），「靠近架势崩解敌人 → 自动处决」的上下文判定闭环归 #6；本层只保证 attack 事件不被场景状态吞掉。

- **`[autoload]` 段追加**（顺序保证初始化）：`[autoload]` 段在 `Game="*res://gdscripts/game.gd"` 之后追加一行 `InputController="*res://gdscripts/input_controller.gd"`。autoload 按声明顺序初始化 → InputController 初始化时 Game 已就绪（若实现中需访问 Game 常量，顺序无问题；实际 InputController 只用 preload constants，无运行时依赖）。

### 2.2 `shandong-wolf/gdscripts/input_controller.gd`（新建，意图事件层）

- **文件:** `shandong-wolf/gdscripts/input_controller.gd`
- **类:** `class_name InputController`，`extends Node`（autoload 单例，`/root/InputController` 全局可访问）
- **职责（严格机械层，零战斗逻辑）：** 读 Input Map → 边沿检测 → 发射 8 个意图事件信号；维护时间戳缓冲队列（FIFO 无吞噬）；提供移动轴查询；`guard_pressed` 只含时间戳（判定归 #6）；`PARRY_WINDOW_FRAMES` 只读传递不判定。

```gdscript
extends Node
## InputController — shandong-wolf 输入意图层（#573）。
## 注册: project.godot [autoload] InputController="*res://gdscripts/input_controller.gd"（Game 之后）
## 职责: 读 Input Map（game_*）→ 边沿检测 → 意图事件信号；时间戳缓冲队列（无吞噬）；
##       guard_pressed 仅含时间戳（弹反判定归 #6）；PARRY_WINDOW_FRAMES 只读不判定。
## 红线: 不接触战斗逻辑/动画/场景状态；消费方 #3/#6/#575/#4 独立监听。

signal attack_pressed                          # 轻击（处决复用此键，上下文判定归 #6）
signal heavy_attack_pressed                    # 重砍
signal guard_pressed(timestamp_ms: int)        # 格挡键按下时机（原始事件，仅时间戳）
signal guard_held                              # 格挡键按住持续（每帧）
signal dash_pressed                            # 垫步（轻按，< DASH_HOLD_THRESHOLD_MS）
signal jump_pressed
signal interact_pressed
signal revive_pressed

const C = preload("res://gdscripts/constants.gd")

# 边沿检测动作表（按下边沿 → 缓冲 + 信号；移动轴不在此列）
const EDGE_ACTIONS: Array[StringName] = [
    &"game_light_attack", &"game_heavy_attack", &"game_guard",
    &"game_dash", &"game_jump", &"game_interact", &"game_revive",
]

var _was_pressed: Dictionary = {}              # action:StringName → bool（边沿状态表）
var _buffer: Array[Dictionary] = []            # [{action: StringName, timestamp_ms: int}] FIFO
var _dash_press_time_ms: int = -1              # dash 按下时刻（Time.get_ticks_msec）
var _sprinting: bool = false                   # dash 按住 ≥ 阈值 → 冲刺态

func _ready() -> void:
    _validate_input_map()                      # 缺失动作 push_error 列出，降级运行不 crash

func _process(_delta: float) -> void:
    _clear_expired()                           # 超窗条目每帧清理
    _poll_edges()                              # 边沿检测 → push 缓冲 + emit 信号
    _update_dash_hold()                        # dash 按住时长 → 冲刺态判定

## ── 连续轴查询（PlayerController 消费，不进缓冲）──
func get_move_axis() -> float:
    return Input.get_axis("game_move_left", "game_move_right")

## ── 缓冲 API（消费方 #6/#575 调用）──
func poll_buffer() -> Dictionary:              # FIFO 出队（跳过超窗条目），无则返回 {}
func peek_buffer() -> Dictionary:              # 只读队首，不出队
func buffer_size() -> int:                     # 当前队列长度（AC5 断言用）

## ── 冲刺态查询（消费方/动画）──
func is_sprinting() -> bool:                   # dash 按住 ≥ DASH_HOLD_THRESHOLD_MS
```

**关键逻辑伪代码（implement 据此实现）：**

```
_poll_edges():
    for action in EDGE_ACTIONS:
        now = Input.is_action_pressed(action)
        was = _was_pressed.get(action, false)
        if now and not was:                          # 按下边沿
            _push_buffer(action)                     # 入缓冲（上限拒绝超额新条目，不丢已有）
            match action:
                "game_guard":  emit guard_pressed(Time.get_ticks_msec())   # 恰 1 次
                "game_dash":   _dash_press_time_ms = now_ms                # 计时起点
                "game_light_attack": emit attack_pressed; ...              # 各边沿事件
        if now and action == "game_guard":
            emit guard_held                          # 按住持续，每帧
        if not now and was and action == "game_dash":
            held_ms = now_ms - _dash_press_time_ms
            if held_ms < C.DASH_HOLD_THRESHOLD_MS:   # 轻按 → 垫步
                emit dash_pressed
            _sprinting = false
        _was_pressed[action] = now

_update_dash_hold():
    if _was_pressed.get("game_dash", false):
        _sprinting = Input.is_action_pressed("game_dash") and \
            (Time.get_ticks_msec() - _dash_press_time_ms) >= C.DASH_HOLD_THRESHOLD_MS

_push_buffer(action):
    now = Time.get_ticks_msec()
    if _buffer.size() >= C.INPUT_BUFFER_MAX:         # 上限：拒新不丢旧（AC5 边界）
        return
    _buffer.append({"action": action, "timestamp_ms": now})

_clear_expired():
    now = Time.get_ticks_msec()
    _buffer = _buffer.filter(func(e): return now - e.timestamp_ms <= C.INPUT_BUFFER_WINDOW_MS)

poll_buffer():
    _clear_expired()
    if _buffer.is_empty(): return {}
    return _buffer.pop_front()                       # FIFO

_validate_input_map():
    missing = [a for a in ALL_ACTIONS if not InputMap.has_action(a)]
    if missing: push_error("InputController: missing Input Map actions: %s" % missing)
    # 降级运行：缺失动作不 crash，仅报错（PRD §5.3-1）
```

- **同键双义语义分离（AC2 核心）：** `guard_pressed` = 按下边沿恰 1 次（携带 `timestamp_ms`），`guard_held` = 按住期间每帧持续——两事件独立计数互不覆盖（PRD §5.2-3）。`guard_pressed` 不携带任何判定结果（本层不判定弹反），#6 用时间戳对齐攻击帧做窗口判定（窗口值只读 `C.PARRY_WINDOW_FRAMES`）。
- **集成说明:** autoload 全局名 `InputController` 可直接引用（消费方 #3/#6/#575 用 `InputController.attack_pressed.connect(...)`）；check_compile 自动纳入（gdscripts/ 扫描）。

### 2.3 `shandong-wolf/gdscripts/player_controller.gd`（新建，移动实体）

- **文件:** `shandong-wolf/gdscripts/player_controller.gd`
- **类:** `class_name PlayerController`，`extends CharacterBody2D`
- **职责:** 消费 InputController 移动轴 → 加速度模型位移；`add_to_group("player")`（#6 近距探测基础设施）；不消费边沿事件（事件由 #3/#6/#575 监听，本类不转发——保持单一职责）。
- **无重力**（横板侧视战斗判定面，PRD §4.3 方案 A）；`velocity.y` 保持 0；`move_and_slide` 预留后续碰撞/地面。

```gdscript
extends CharacterBody2D
## PlayerController — shandong-wolf 玩家移动实体（#573）。
## 组: "player"（#6 近距探测/处决判定依赖）
## 移动: 加速度模型（冷冽干脆）——velocity.x = move_toward(velocity.x, dir*MAX_SPEED, ACCEL*delta)
## 消费: InputController.get_move_axis()（连续轴）；不消费边沿事件（消费方直接监听 InputController 信号）

const C = preload("res://gdscripts/constants.gd")

func _ready() -> void:
    add_to_group("player")

func _physics_process(delta: float) -> void:
    var dir: float = InputController.get_move_axis()   # autoload 全局名直接访问
    velocity.x = move_toward(velocity.x, dir * C.MOVE_MAX_SPEED, C.MOVE_ACCELERATION * delta)
    velocity.y = 0.0                                    # 无重力（横板战斗判定面）
    move_and_slide()
```

- **手感参数（# DRAFT，定稿归 #584）：** `MOVE_ACCELERATION=1200.0`（px/s²）、`MOVE_MAX_SPEED=300.0`（px/s）——起步 2 帧达标、加速度大（「冷冽干脆」，PRD §2.3/§7 E3 标定）。
- **集成说明:** 玩家实体场景挂接由后续战斗场景 issue 负责（Main.tscn 红线不改）；smoke/单测**程序化实例化**（`PlayerController.new()` + `add_child` + 手工 `_physics_process` 步进或入树跑帧）。

### 2.4 `shandong-wolf/gdscripts/constants.gd` 输入层分区（修改，追加 # DRAFT）

在 `FRAME_RHYTHM_BASE` 之后追加「输入层」分区，全部 `# DRAFT` 候补值（`# DRAFT` 标记是 test_input_controller.gd 断言对象，**实现期删除标记/改值定稿 = 测试 FAIL**）：

```gdscript
# ── 输入层（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 缓冲窗口 150ms ∈ [100,200]（AC4）；队列上限 8；垫步长按阈值 200ms；
#   移动加速度 1200 px/s² / 最高速度 300 px/s（起步 2 帧达标，冷冽干脆）
#   该值影响什么: 输入缓冲窗口=连招衔接手感（越大越宽容）；垫步阈值=轻按/按住双义分界；
#   移动参数=横板位移手感（AC6 位移 ≥100px 的达标基础）
#   情感断言: 输入零吞噬的"指哪打哪"——快速连按全生效，操作意图不丢失
const INPUT_BUFFER_WINDOW_MS: int = 150       # # DRAFT（AC4：∈ [100,200]）
const INPUT_BUFFER_MAX: int = 8               # # DRAFT（队列上限，拒新不丢旧）
const DASH_HOLD_THRESHOLD_MS: int = 200       # # DRAFT（轻按=垫步 / 按住≥此值=冲刺）
const MOVE_ACCELERATION: float = 1200.0       # # DRAFT（px/s²，起步 2 帧达标）
const MOVE_MAX_SPEED: float = 300.0           # # DRAFT（px/s）
```

- **弹反窗口只读不改：** `PARRY_WINDOW_FRAMES=12`（# DRAFT）保持原样；InputController 仅将 `guard_pressed` 时间戳 + 窗口值暴露给 #6（本层不读窗口做判定，故窗口值异常（≤0）也不影响输入层发射——PRD §5.2-10）。

### 2.5 测试文件（新建，仅测试用例描述——plan 阶段不写可运行测试代码）

- **`shandong-wolf/tests/test_input_controller.gd`**: extends Object，`run()` 入口 + `_assert` 计数模式（同 test_state_machine.gd 结构）；实例化 InputController（`InputController.new()`，不入树也能 `_process` 手工驱动，或入树跑帧）断言缓冲无吞噬/同键双义/时间戳语义/边沿单次/垫步阈值/Input Map 校验。用例见 §8 Scenario A-E。
- **`shandong-wolf/tests/test_player_controller.gd`**: extends Object，程序化实例化 PlayerController（+ 必需入树节点/InputController autoload 已由引擎加载）断言位移/加速度/同帧左右抵消/无输入静止。用例见 §8 Scenario F-H。

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 性质 | 伪代码/说明 |
|------|------|------|------------|
| `shandong-wolf/project.godot` | 新增 `[input]` 段（9 动作，§2.1）+ `[autoload]` 段追加 `InputController="*res://gdscripts/input_controller.gd"`（Game 之后） | 新增段（不动现有配置） | `[input]` 段含 9 个 `game_*` 动作的 InputEventKey/InputEventMouseButton 事件数组（physical_keycode 见 §2.1 表） |
| `shandong-wolf/gdscripts/constants.gd` | 追加输入层 `# DRAFT` 分区（5 常量，§2.4） | 追加分区（不改既有 5 分区与机械常量） | 文件末尾 `FRAME_RHYTHM_BASE` 之后追加；`# DRAFT` 标记保留 |
| `shandong-wolf/tests/run_tests.gd` | `_run_tests()` 追加 2 个套件挂载 | 行为变更（2 → 4 套件） | `_run("res://tests/test_input_controller.gd", "InputController")` + `_run("res://tests/test_player_controller.gd", "PlayerController")`；`_pass/_fail` 汇总逻辑保留 |
| `shandong-wolf/tests/smoke_test.gd` | 扩展 AC6 断言（原「SMOKE OK」探针 → 输入层冒烟） | 行为变更（探针 → 真实断言） | 程序化实例化 PlayerController 入树 → `Input.action_press("game_move_right")` 定步长推进 ~120 帧（2s@60fps）→ 断言 `position.x ≥ 100`；connect InputController 的 attack_pressed/guard_pressed/dash_pressed 断言均被捕获 → 退出码 0 |

### 3.2 新文件清单

| 文件 | 说明 |
|------|------|
| `shandong-wolf/gdscripts/input_controller.gd` | InputController 意图事件层（§2.2） |
| `shandong-wolf/gdscripts/player_controller.gd` | PlayerController 移动实体（§2.3） |
| `shandong-wolf/tests/test_input_controller.gd` | 输入控制器单测（§2.5） |
| `shandong-wolf/tests/test_player_controller.gd` | 玩家控制器单测（§2.5） |

### 3.3 不修改（显式声明，防越界）

| 文件 | 原因 |
|------|------|
| `shandong-wolf/scenes/Main.tscn` | 红线（PRD §8）；玩家实体由 smoke/后续战斗场景程序化实例化 |
| `shandong-wolf/gdscripts/game.gd` | #572 交付文件零改动；挂接通过 `[autoload]` 追加实现（§1.2 裁决） |
| `shandong-wolf/gdscripts/state_machine.gd` | 不修改；#575 在其上消费本层事件 |
| `shandong-wolf/tests/check_compile.gd` | 自动覆盖新脚本，无改动需求 |
| `shandong-wolf/tests/test_state_machine.gd` / `test_constants.gd` | #572 已交付，不触碰 |
| `shandong-wolf/e2e_shots.json` | PRD 未要求 |
| `mini-pong/` 全部 | 跨游戏红线（PRD §8） |
| `game-env/manifest.yaml` / `.github/workflows/` | 管线配置非本 issue 职责 |
| `docs/GAME_DESIGN/` | GDD 补记是 post-merge agent 职责 |
| 任何美术资产 / 插件 addon / 像素帧 | PRD §6.2 调研结论：零插件（§6 集成点说明） |

---

## 4. 数据流

### Flow 1: 意图事件链（正常路径 — 轻击/格挡/垫步等边沿事件）
```
物理按键 J ──► Input Map (game_light_attack) ──► InputController._process
    ├─ 边沿检测（_was_pressed false→true）
    ├─ push_buffer({action, timestamp_ms})          # 入缓冲（窗口 150ms，上限 8）
    └─ emit attack_pressed ──► 消费方（#4/#575 攻击态；处决上下文归 #6）
物理按键 L 按下 ──► emit guard_pressed(timestamp_ms) 恰 1 次 ──► #6 弹反判定（对齐攻击帧）
物理按键 L 按住 ──► emit guard_held 每帧 ──► #6 格挡 / #4 格挡姿态
消费方（#6/#575）: InputController.poll_buffer() → FIFO 出队 → 衔接下一动作（AC4 缓冲衔接）
```

### Flow 2: 移动链（正常路径 — AC6 位移）
```
按住 D ──► Input.get_axis("game_move_left","game_move_right") = +1.0
    ──► PlayerController._physics_process: velocity.x = move_toward(0, 1.0*300, 1200*delta)
    ──► move_and_slide() ──► position.x 递增
    ──► 2s@60fps 位移 ≈ 300px 达最高速后线性累积 ≥ 100px（AC6 达标）
```

### Flow 3: 垫步/冲刺双义（时间分叉路径）
```
按下 Shift ──► _dash_press_time_ms = now（计时起点）
    ├─ 释放 < 200ms（DASH_HOLD_THRESHOLD_MS）──► emit dash_pressed（垫步）＋ _sprinting=false
    └─ 按住 ≥ 200ms ──► _sprinting=true（is_sprinting() 查询）──► 持续冲刺位移（消费方驱动）
```

### Flow 4: 缓冲消费（边沿路径 — AC4/AC5）
```
收招前窗口内输入（如攻击后摇 14 帧内按下轻击）:
    attack_pressed 入队 ──► 消费方在收招结束帧 poll_buffer() ──► 取到 {action: attack, ts} ──► 衔接下一击
300ms 内 3 连击（间隔 100ms）:
    push×3 ──► 队列 [a1, a2, a3]（无覆盖）──► poll×3 全成功（AC5）
超窗条目（>150ms 未消费）:
    _clear_expired 每帧过滤 ──► 清理不算吞噬（已过窗口的输入本就不该衔接）
```

---

## 5. 边界情况与错误处理

| Edge Case | Mitigation |
|-----------|------------|
| 1. 左右同帧同按 | `Input.get_axis` 返回 0 → velocity.x 归零（横板惯例），不 panic（PRD §5.2-1，§8 Scenario G） |
| 2. Shift 轻按 vs 长按双义 | 按下计时 / 释放 < `DASH_HOLD_THRESHOLD_MS`(200) → `dash_pressed`；按住 ≥ 阈值 → 冲刺态（`is_sprinting()`）；阈值参数落 constants.gd # DRAFT（PRD §5.2-2，§8 Scenario D） |
| 3. guard 键同帧多事件 | 边沿检测防重复：按住 L 时 `guard_pressed` 恰 1 次，`guard_held` 每帧持续——两语义独立计数互不覆盖（PRD §5.2-3，§8 Scenario B） |
| 4. 缓冲窗口内多个输入 | FIFO 按入队顺序保留（attack+guard 连按 → 消费顺序 = 入队顺序）（PRD §5.2-4，§8 Scenario C） |
| 5. 300ms 3 连击 | 3 条全入队无吞噬；第 4 击超出 `INPUT_BUFFER_MAX`(8) 拒新条目不丢已有（PRD §5.2-5，§8 Scenario A） |
| 6. 缓冲条目过期 | 超窗（>150ms）每帧清理；清理不算吞噬（PRD §5.2-6，§8 Scenario A） |
| 7. 移动与事件同帧 | 移动是连续轴（不进缓冲队列），`get_axis` 与边沿事件互不干扰（PRD §5.2-7） |
| 8. 无输入静止 | velocity 按加速度模型 `move_toward` 归零，不漂移（PRD §5.2-8，§8 Scenario H） |
| 9. 复活 F 无提示时 | InputController 无状态判定（机械层），`revive_pressed` 照发；「提示出现时有效」由消费方（两条命系统）裁决，本层不吞事件（PRD §5.2-9） |
| 10. 弹反窗口值异常（≤0） | 输入层不依赖窗口值做判定（读取仅传递），`guard_pressed` 仍照发（PRD §5.2-10） |
| 11. 前摇可取消（只狼哲学④） | 攻击前摇窗口内 dash：缓冲队列保证 dash 输入不丢 + 事件不被场景状态吞；「前摇取消」的具体状态迁移语义由 #575/#6 消费缓冲实现——本层契约保障（输入可达性），§8 Scenario E |
| 12. 快速连按期间消费方忙碌 | 缓冲队列 + 上限 8 保证至少 8 个输入不丢；消费方 poll 频率不足时超窗清理（有界内存，无无限增长） |

### 失败路径（PRD §5.3 全采纳）

| 失败场景 | 处理 |
|---------|------|
| 1. Input Map 缺失 `game_*` 动作 | InputController `_ready()` 校验 `InputMap.has_action` 全清单，缺失 → `push_error` 列出 + 降级运行不 crash；单测断言校验函数对缺失动作报错（§8 Scenario E） |
| 2. Game/InputController autoload 未注册或顺序破坏 | 启动即失败 → check_compile 编译期暴露；`[autoload]` 顺序 Game 先于 InputController（§2.1） |
| 3. 意图事件无消费方（#3/#6 未实现） | Godot 信号无监听者安全 no-op；smoke 用显式 `connect` 捕获验证发射（发射与消费解耦，下游未接不 crash） |
| 4. 缓冲窗口/阈值参数非法（0/负/NaN） | implement 在读取处 `clampf` 到合法范围（≥1ms），参数异常不崩；# DRAFT 值域由 test_input_controller 断言（§8 Scenario E） |
| 5. 多 agent 并发生成冲突 | worktree 隔离 + 白名单提交（worktree-commit.sh 强制）；本 PR 文件清单（§3）互不重叠 |

---

## 6. 集成点

> **Status 约定:** ⬜ = 待 implement 接线；✅ = implement 已连接。implement agent 必须更新本表。review agent 验证所有 ⬜ 已解决或显式延期后合并。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 意图事件消费（动画） | InputController 8 信号 | #3（火柴人动画） | `InputController.attack_pressed.connect(...)` 等 | ⬜ pending |
| 弹反判定 | `guard_pressed(timestamp_ms)` + 只读 `PARRY_WINDOW_FRAMES` | #6（拼刀/弹反/架势判定） | #6 用时间戳对齐攻击帧做窗口判定；本层不判定 | ⬜ pending |
| 格挡判定 | `guard_held`（每帧持续） | #6 / #4 | 按住持续事件 → 格挡姿态 | ⬜ pending |
| 处决闭环（AC3） | `attack_pressed`（复用攻击键，无独立 execute 键） | #6 | 「靠近架势崩解敌人 → 自动处决」上下文判定归 #6；本层保证事件可达 | ⬜ pending |
| 战斗状态机驱动 | 缓冲队列 `poll_buffer()` + 全部意图事件 | #575 | `class BattleStateMachine extends StateMachineBase` 消费事件/缓冲驱动迁移 | ⬜ pending |
| 玩家近距探测 | `add_to_group("player")` | #6 | `body_entered/body_exited` 近距探测依赖 | ⬜ pending |
| 数值定稿 | 输入层 `# DRAFT` 分区 + `PARRY_WINDOW_FRAMES` | #584 / 分解 id 13 | 候补值 → 用户定稿（替换值 + 去 # DRAFT 标记，走 #584 PR） | ⬜ pending |
| 单测挂载 | run_tests.gd | 本 issue | `_run("res://tests/test_input_controller.gd", ...)` + test_player_controller | ✅ done |
| smoke 断言 | smoke_test.gd | 本 issue | AC6：action_press 驱动位移 ≥100px + 信号捕获 | ✅ done |
| 零插件决策 | 自研 ~50 行缓冲（时间戳+窗口+FIFO，dragonforge 模式参考） | 本 issue | PRD §6.2 调研 6 候选均不引入；复用设计模式不引 addon（#572 红线） | ✅ done |

---

## 7. 实现阶段

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | `project.godot` `[input]` 段 9 动作 + `[autoload]` 追加 InputController | 0.5d |
| Phase 2 | P0 | `constants.gd` 输入层 `# DRAFT` 分区（5 常量） | 0.25d |
| Phase 3 | P0 | `input_controller.gd`（信号 + 缓冲 + 边沿 + 双义 + 校验） | 1d |
| Phase 4 | P0 | `player_controller.gd`（CharacterBody2D 加速度模型 + group） | 0.5d |
| Phase 5 | P0 | `test_input_controller.gd` + `test_player_controller.gd` + `run_tests.gd` 挂载 | 0.75d |
| Phase 6 | P0 | `smoke_test.gd` 扩展（AC6）+ 三入口全绿实测 + Spike E1-E3 验证（PRD §7） | 0.5d |

> 依赖序：Phase 1→2 无依赖可并行（Input Map 先行可手测）；Phase 3 依赖 2（缓冲窗口/阈值常量）；Phase 4 依赖 1（动作存在）与 3（get_move_axis）；Phase 5 依赖 3/4；Phase 6 收尾。总估 3.5d（PRD estimate 2d 偏乐观，含 Spike 与 headless 输入时序排障；输入层时序（action_press 与 _process 帧序）是主要风险点）。

---

## 8. 测试用例描述

> 仅描述测试场景，不写可运行测试代码（plan 阶段红线；实现由 implement agent 完成）。测试框架沿用 mini-pong/#572 模式：`extends Object` + `run()` 入口 + `_assert` 计数。

### Scenario A: 输入缓冲无吞噬（test_input_controller.gd，AC4/AC5 核心）
- **A1（300ms 3 连击全保留）**: `Input.action_press(game_light_attack)` 间隔 100ms 共 3 次（每次 press 后 release 再按），每帧驱动 `_process` → 断言 `buffer_size()==3`，`poll_buffer()` 连续 3 次全成功且 action 均为 game_light_attack（FIFO 顺序 = 入队顺序）。
- **A2（窗口内可取）**: press 后 100ms 内（< 150ms 窗口）`poll_buffer()` 仍可取到（收招前衔接基础）。
- **A3（超窗清理）**: press 后推进 > 150ms（如 200ms）再 poll → 返回空；`buffer_size()==0`；清理不算吞噬。
- **A4（上限拒新不丢旧）**: 连按 9 次（> `INPUT_BUFFER_MAX`=8）→ 队列保留 8 条，第 9 次被拒；poll 8 次全成功。
- **A5（FIFO 多动作混合）**: 150ms 内 attack → guard 连按 → poll 顺序 == [attack, guard]（PRD §5.2-4）。

### Scenario B: 格挡=弹反同键双义（test_input_controller.gd，AC2）
- **B1（按下恰 1 次 + 按住持续）**: `Input.action_press(game_guard)` 保持 1 秒不 release → 断言 `guard_pressed` 信号恰捕获 1 次（带 timestamp_ms > 0）；`guard_held` 每帧持续（≥2 帧）。
- **B2（释放后再按重新触发）**: release 后再次 press → `guard_pressed` 再次发射（边沿状态表复位）。
- **B3（时间戳语义）**: 捕获的 `guard_pressed` 参数为 int 毫秒时间戳，且两次按下时间戳单调递增；信号不带判定结果（仅时间戳）。
- **B4（窗口值只读）**: 断言 `WolfConstants.PARRY_WINDOW_FRAMES == 12` 且输入层未修改该值（读不写）。

### Scenario C: 缓冲消费与衔接（test_input_controller.gd，AC4 语义）
- **C1（poll 出队即消费）**: 入队 2 条 → poll 1 次 → `buffer_size()==1`，队首为第 1 条。
- **C2（peek 只读）**: peek 后 `buffer_size()` 不变；peek 值 == 下一次 poll 值。
- **C3（空队列安全）**: 无输入时 poll/peek 均返回空且不崩溃。

### Scenario D: 垫步/冲刺双义（test_input_controller.gd）
- **D1（轻按垫步）**: press(game_dash) 后 100ms（< 200ms 阈值）release → `dash_pressed` 恰 1 次；`is_sprinting()==false`。
- **D2（长按冲刺）**: press 后按住 ≥ 250ms → `is_sprinting()==true`；期间不发射 `dash_pressed`（冲刺不是垫步）；release 后 `is_sprinting()==false`。
- **D3（阈值边界）**: 按住恰好 200ms release → 按 D1 语义（≥ 阈值 = 冲刺态，不发射 dash_pressed）。

### Scenario E: 校验与非法值（test_input_controller.gd，PRD §5.3）
- **E1（缺失动作校验）**: 临时移除某动作（如 `InputMap.erase_action("game_jump")`）后调 `_validate_input_map()` → `push_error` 输出含缺失动作名；移除动作恢复后无报错。
- **E2（参数 clamp）**: `INPUT_BUFFER_WINDOW_MS` 被误设 0/负值 → 读取处 clamp 到 ≥1ms，缓冲不崩（输入层容错）。
- **E3（消费方未接不 crash）**: 无任何信号连接时连续驱动 `_process` 多帧 → 无报错（信号 no-op 安全）。

### Scenario F: 移动位移（test_player_controller.gd，AC6 基础）
- **F1（2s 位移 ≥100px）**: 程序化实例化 PlayerController 入树（或手工步进 `_physics_process` 120 次 × delta=1/60），`Input.action_press(game_move_right)` 全程按住 → 断言 `position.x ≥ 100`。
- **F2（加速度模型）**: 单帧位移增量随帧数递增（先加速后匀速），velocity 收敛于 `MOVE_MAX_SPEED`（move_toward 语义）；起步 2 帧内 velocity > 0。
- **F3（速度上限）**: 持续按住 2s 后 `velocity.x <= MOVE_MAX_SPEED`（不超速）。

### Scenario G: 移动边界（test_player_controller.gd）
- **G1（左右同按抵消）**: `action_press(game_move_left)` + `action_press(game_move_right)` 同帧 → `get_move_axis()==0` → velocity.x 归零（不 panic）。
- **G2（无输入静止）**: 无按键推进多帧 → velocity.x 衰减到 0，position 不漂移。
- **G3（group 归属）**: `is_in_group("player")==true`（#6 近距探测前置）。

### Scenario H: 玩家-输入集成（test_player_controller.gd）
- **H1（轴查询走 InputController）**: PlayerController 位移由 `InputController.get_move_axis()` 驱动（非直接轮询 Input）——断言通过 autoload 全局名可访问（编译期即验证）。
- **H2（边沿事件不吞）**: 移动期间按攻击 → `attack_pressed` 仍被 InputController 发射（PlayerController 不拦截/不转发，消费方直连 InputController）。

### Scenario I: smoke test（smoke_test.gd，AC6 验收载体）
- **I1（位移断言）**: `Input.action_press("game_move_right")` 定步长推进 ~120 帧（2s@60fps）→ `position.x ≥ 100px` → 退出码 0。
- **I2（信号捕获）**: 显式 connect InputController 的 `attack_pressed`/`guard_pressed`/`dash_pressed` → `action_press` 对应键 → 3 个信号均被捕获（发射与消费解耦验证）。
- **I3（回归防退化）**: 原「SMOKE OK」探针保留（工程可加载），新增断言失败 → 退出码非 0。

### Scenario J: 三入口回归（CI / 本地）
- **J1（check_compile）**: `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0，count 覆盖新增 2 gdscripts（input_controller/player_controller）+ 2 tests 脚本。
- **J2（run_tests）**: `... --script tests/run_tests.gd` 退出 0，输出「TESTS: N passed, 0 failed」且 N ≥ 4 套件用例总数；pass==0 → 退出非 0（防挂载遗漏静默绿）。
- **J3（smoke）**: `... --script tests/smoke_test.gd` 退出 0（I1/I2 全过）。
- **J4（主场景冒烟）**: `godot --path shandong-wolf/ --headless --quit` 退出 0（autoload 追加 InputController 后启动链兼容）。

---

## 9. 验收条件映射（源自 Issue #573 body）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | Input Map 完整：移动 A/D、轻击 J、重砍 K、格挡/弹反 L（同键）、垫步 Shift、跳 Space、交互 E、复活 F——project.godot 可查见 | §2.1 `[input]` 段 9 个 `game_*` 动作（A/D/←/→/J/左键/K/右键/L/Shift/Space/E/F） | `grep -A2 '^game_' shandong-wolf/project.godot` 全清单 + J1 check_compile |
| AC2 | 格挡=弹反同键验证：按住=格挡姿态（持续有效），弹反窗口内按下=弹反（窗口从 constants.gd 读取，只狼基准 10-14 帧） | §2.2 `guard_pressed`（按下时机+时间戳）/`guard_held`（按住持续）语义分离；窗口只读 `PARRY_WINDOW_FRAMES=12`（# DRAFT），判定归 #6 | B1/B2/B3/B4 单测断言 |
| AC3 | 处决自动衔接：靠近架势崩解敌人按攻击自动进入处决（不额外按键） | §2.1 无 `game_execute` 映射；`attack_pressed` 复用攻击键任意时刻可达 | smoke I2（attack_pressed 可捕获）+ PR 说明标注跨系统 AC 依赖 #6（闭环归 #6） |
| AC4 | 输入缓冲：收招前 100-200ms 内输入自动衔接下一动作（smoke test 可断言） | §2.2 时间戳缓冲队列，窗口 `INPUT_BUFFER_WINDOW_MS=150`（# DRAFT ∈ [100,200]） | A2（窗口内可取）+ A3（超窗清理） |
| AC5 | 快速连按不丢输入：300ms 内 3 连击全部生效（缓冲队列 ≥1，无吞噬） | §2.2 FIFO 队列无覆盖语义 + `INPUT_BUFFER_MAX=8`（拒新不丢旧） | A1（3 连击全保留）+ A4（上限边界） |
| AC6 | smoke test：模拟按键可驱动玩家 2 秒内位移 ≥100px，攻击/格挡/垫步事件信号均可被捕获 | §2.3 加速度模型（`MOVE_ACCELERATION=1200` / `MOVE_MAX_SPEED=300` # DRAFT）+ §3.1 smoke 扩展 | I1（位移 ≥100px）+ I2（attack/guard/dash 信号捕获）+ J3 退出码 0 |

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `mini-pong/` 任何文件（跨游戏红线）
- ❌ `shandong-wolf/scenes/Main.tscn`（含 PostMergeProbeLabel、标题/副标题/版本标签）
- ❌ `shandong-wolf/gdscripts/game.gd`（#572 交付文件零改动；挂接走 `[autoload]` 追加）
- ❌ `shandong-wolf/gdscripts/state_machine.gd`、`tests/test_state_machine.gd`、`tests/test_constants.gd`（#572 交付，不触碰）
- ❌ `game-env/manifest.yaml`、`.github/workflows/`、`scripts/`（管线参数化已自动跟随）
- ❌ `docs/GAME_DESIGN/`（post-merge agent 职责）
- ❌ `shandong-wolf/e2e_shots.json`（PRD 未要求）
- ❌ 任何美术资产 / 插件 addon / 像素帧（PRD §6.2 调研结论：零插件，复用设计模式）
- ❌ 不写任何可运行测试文件（本 DESIGN §8 仅为测试用例描述，测试代码归 implement agent）
- ✅ constants.gd 所有手感值保持 `# DRAFT` + 候补值，定稿归 #584；`PARRY_WINDOW_FRAMES` 只读不改
- ✅ 输入映射名统一 `game_` 前缀；`game_guard`=L 独键、`game_dash`=Shift（键位裁决 §2.1）

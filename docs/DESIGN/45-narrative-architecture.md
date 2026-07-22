# Design: #45 — Narrative Architecture（叙事架构设计）

> Parent Issue: #45
> Agent: plan-agent
> Date: 2026-07-22

---

## 1. Architecture Overview

### Core Idea

采用**线性场景图 + 状态感知分支**模式（PRD #45 Approach A）。物理路径固定为 6 场景线性序列——办公室 → 大厅 → 便利店 → 天桥 → 地下通道 → 地铁站——但叙事体验通过三轴状态值（hope/conviction/will）动态变化。玩家在同一个场景中看到的文本、听到的对话、感受到的氛围各不相同，取决于其内心状态。

**核心原则（「体验引擎」世界叙事模式）：**
1. **系统即叙事** — 环境变化不由脚本驱动，而由玩家状态驱动（状态 → 世界滤镜 → 新文本）
2. **决策产生系统，不产生剧情** — 玩家的选择改变「世界如何被感知」，而非「接下来发生什么」
3. **叙事密度靠环境细节，不靠对白量** — 雨量、灯光颜色、NPC 站位、影子长度均为叙事工具

### Data Flow

```
玩家在每个场景中的选择
    │
    ├──► 影响状态滑条（三轴: hope / conviction / will）
    │       │
    │       ▼ StateSystem.state_changed 信号
    │       │
    │       ├──► NarrativeManager — 场景文本变体选择
    │       ├──► DialogueEngine — NPC 对话分支筛选
    │       ├──► WorldviewController — 环境描述模板切换
    │       ├──► RainController — 雨量变化
    │       └──► ClockManager — 游戏天数消耗
    │
    ├──► 累加叙事 flag / 回声标记
    │       │
    │       ▼ EchoSystem
    │       到达重现场景时检测回声ID
    │       → 触发叙事回声（台词重复 / 意象重现）
    │
    └──► 推进 3 个月时钟
            │
            ▼
        地铁站终局: 根据状态值判定结局
         ├──► Keep Walking（hope≥6, will≥5）
         ├──► Turn Back（conviction≤3）
         └──► Stay（hope≤4, conviction≤4, will≤4）
```

### Key Architectural Decisions

| 决策 | 选择 | 理由 |
|------|------|------|
| 场景拓扑 | 线性序列（6场景固定路径） | 降低实现复杂度；强化「你在赶路」的紧迫感；回声系统在固定路径上更可靠 |
| 叙事分支方式 | 状态阈值 + 文本变体 | 无需庞大分支树；同一场景在不同状态下自动产生分支感 |
| 结局判定时机 | 地铁站终局，三轴状态综合判定 | 玩家整条路径的所有选择都影响结局，而非仅最后一个选择 |
| 回声触发策略 | 累加 flag + 场景检测 | 固定路径保证回声时机可控（便利店→地下通道必定经过） |
| Stranger NPC | 内在投射模式（状态感知 + 自动变体） | 同一NPC在不同状态下展现不同外貌/语气/对话 |
| 状态轴名称 | hope / conviction / will | 与现有 `state_system.gd` 和 `constants.gd` 保持一致 |

---

## 2. Scene Node Tree Layer（场景节点树结构）

### 场景关系总图

```
办公室 (office.tscn)
  │ 交互: 电脑(看邮件/deadline)、窗(看雨)、手机(确认时间)
  │ 出口: 对话触发场景切换 → lobby.tscn
  ▼
大厅 (lobby.tscn)
  │ 交互: 保安(闲聊)、Stranger(第一次对话)、出口
  │ Choice: 回应 Stranger / 无视 → 影响 hope ±0.5, conviction ±0.5
  ▼
便利店 (convenience_store.tscn)
  │ 交互: 店员(能量补给)、货架(探索)、窗外(看雨)
  │ Choice: 买咖啡/不买 → 影响 will ±1; 跟店员聊天/沉默 → 影响 hope ±0.5
  ▼
天桥 (bridge.tscn)
  │ 交互: 栏杆(俯瞰车流)、流浪汉(镜像对话)、雨(压力增强)
  │ Choice: 停留/快步走过/给零钱 → 影响 conviction ±1
  ▼
地下通道 (underpass.tscn)
  │ 交互: Stranger(深度对话)、涂鸦墙(回忆闪回)、出口
  │ Echo ID: "rain_echo", "screensaver_echo" 在此触发
  │ Choice: 关键回声对话 → 三轴各 ±1
  ▼
地铁站 (subway_station.tscn) ═══ 终局
  │ 交互: 检票口、时钟、Stranger(最后告别)
  │ 结局判定: 三轴状态值
  ├──► Keep Walking
  ├──► Turn Back
  └──► Stay
```

### 2.1 Office (scenes/office/office.tscn)

**结构：**
```
office.tscn
 ├── Node3D (root)
 │    ├── Node3D "Environments"
 │    │    ├── Node3D "WindowText" (LoFiText3D) — 窗外风景描述
 │    │    ├── Node3D "ScreensaverText" (LoFiText3D) — 屏保文字「你做游戏有什么用？」
 │    │    └── Node3D "DesktopText" (LoFiText3D) — 电脑桌面，显示 deadline
 │    ├── Area3D "InteractionZones"
 │    │    ├── Area3D "OfficeDoorTrigger" — 出口触发区
 │    │    └── Area3D "WindowTrigger" — 窗边交互触发区
 │    ├── SceneManager (node from scene_manager.tscn) — 场景过渡管理器
 │    └── CanvasLayer
 │         └── DialoguePanel — 对话面板
 ├── autoload: GameManager, StateSystem, ClockManager
 └── script: gdscripts/office.gd
```

**交互点：**

| 对象 | 交互类型 | 触发方式 | 效果 |
|------|---------|---------|------|
| 电脑 | 环境阅读 | Area3D + InputEvent | 显示 deadline 文本，消耗 0 天 |
| 窗 | 环境阅读 + 状态感知 | Area3D + InputEvent | 文本变体取决于 hope 值 |
| 手机 | 环境阅读 | Area3D + InputEvent | 显示当前时间，确认「第 X 天」 |
| 门 | 场景出口 | Area3D + 点击 | 触发 door_dialogue，选择离开 → 切换到 lobby.tscn |

### 2.2 Lobby (scenes/lobby/lobby.tscn)

**结构：**
```
lobby.tscn
 ├── Node3D (root)
 │    ├── Node3D "Environments"
 │    │    ├── Node3D "EntranceText" (LoFiText3D) — 大厅环境描述
 │    │    └── Node3D "StrangerSpotlight" — Stranger 站位区域
 │    ├── Area3D "InteractionZones"
 │    │    ├── Area3D "SecurityGuardTrigger" — 保安对话
 │    │    ├── Area3D "StrangerTrigger" — Stranger 第一次相遇
 │    │    └── Area3D "ExitTrigger" — 出口到便利店
 │    ├── SceneManager
 │    └── CanvasLayer/DialoguePanel
 └── script: gdscripts/lobby.gd
```

**交互点：**

| 对象 | 交互类型 | 触发方式 | 效果 |
|------|---------|---------|------|
| 保安 | 对话 | Area3D + 点击 | 闲聊，影响 hope ±0.5 |
| Stranger | 对话（第一次） | Area3D + 点击 | **关键选择**：回应/无视 → hope ±0.5, conviction ±0.5 |
| 出口 | 场景切换 | Area3D + 点击 | 切换到 convenience_store.tscn |

### 2.3 Convenience Store (scenes/store/convenience_store.tscn)

**结构（部分已存在）：**
```
convenience_store.tscn
 ├── Node3D (root)
 │    ├── Node3D "Environments"
 │    │    ├── Node3D "CounterText" (LoFiText3D) — 柜台描述
 │    │    ├── Node3D "ShelvesText" (LoFiText3D) — 货架描述
 │    │    └── Node3D "WindowStoreText" (LoFiText3D) — 窗外雨景
 │    ├── Area3D "InteractionZones"
 │    │    ├── Area3D "ClerkTrigger" — 店员对话
 │    │    ├── Area3D "CoffeeChoice" — 买咖啡/不买
 │    │    └── Area3D "StoreExitTrigger" — 出口到天桥
 │    ├── SceneManager
 │    └── CanvasLayer/DialoguePanel
 └── script: gdscripts/store.gd
```

### 2.4 Bridge (scenes/bridge/bridge.tscn) — 新建

```
bridge.tscn
 ├── Node3D (root)
 │    ├── Node3D "Environments"
 │    │    ├── Node3D "TrafficText" (LoFiText3D) — 车流描述
 │    │    ├── Node3D "HomelessText" (LoFiText3D) — 流浪汉文本
 │    │    └── Node3D "RainBridgeText" (LoFiText3D) — 雨夜天桥描述
 │    ├── Area3D "InteractionZones"
 │    │    ├── Area3D "RailingTrigger" — 栏杆俯瞰
 │    │    ├── Area3D "HomelessTrigger" — 流浪汉对话
 │    │    └── Area3D "BridgeExitTrigger" — 出口到地下通道
 │    ├── SceneManager
 │    └── CanvasLayer/DialoguePanel
 └── script: gdscripts/bridge.gd
```

**特殊机制 — 极低信念触发：**
当 conviction ≤ 2 时，内心独白出现「从这里跳下去就解脱了」的隐性选项。这不是一个可点击的选择——它是自动触发的文本闪烁，然后被拉回现实。

**回声 2 触发点：** 流浪汉说出屏保上的文字「你做游戏有什么用？」。

### 2.5 Underpass (scenes/underpass/underpass.tscn) — 新建

```
underpass.tscn
 ├── Node3D (root)
 │    ├── Node3D "Environments"
 │    │    ├── Node3D "GraffitiText" (LoFiText3D) — 涂鸦墙描述
 │    │    ├── Node3D "EchoText" (LoFiText3D) — 回声触发时的文字闪现
 │    │    └── Node3D "UnderpassLight" — 灯光效果（状态感知）
 │    ├── Area3D "InteractionZones"
 │    │    ├── Area3D "GraffitiTrigger" — 涂鸦互动（回忆闪回）
 │    │    ├── Area3D "StrangerEchoTrigger" — Stranger 回声对话
 │    │    └── Area3D "UnderpassExitTrigger" — 出口到地铁站
 │    ├── SceneManager
 │    └── CanvasLayer/DialoguePanel
 └── script: gdscripts/underpass.gd
```

**回声核心触发点：** 此处 Stranger 再次出现，重复便利店门口的台词「雨这么大，你不会想走太远的」，但语气根据玩家中间的选择而变化（从关切到讽刺/失望）。

### 2.6 Subway Station (scenes/subway_station/subway_station.tscn) — 新建

```
subway_station.tscn
 ├── Node3D (root)
 │    ├── Node3D "Environments"
 │    │    ├── Node3D "TicketGateText" (LoFiText3D) — 检票口
 │    │    ├── Node3D "ClockText" (LoFiText3D) — 时钟（末班车时间）
 │    │    ├── Node3D "BroadcastText" (LoFiText3D) — 广播回声
 │    │    └── Node3D "StrangerFinalText" (LoFiText3D) — Stranger 最后告别
 │    ├── Area3D "InteractionZones"
 │    │    ├── Area3D "TicketGateTrigger" — 进站（Keep Walking 路径）
 │    │    ├── Area3D "TurnBackTrigger" — 转身离开（Turn Back 路径）
 │    │    └── Area3D "BenchTrigger" — 坐下等待（Stay 路径）
 │    ├── SceneManager
 │    └── CanvasLayer/DialoguePanel
 └── script: gdscripts/subway_station.gd
```

**结局触发逻辑：**
进入地铁站后，自动根据三轴状态值显示不同的交互选项：
- hope ≥ 6 且 will ≥ 5 → 检票口高亮「进站」，Stranger 微笑告别
- conviction ≤ 3 → 出口方向出现「转身回去」选项
- 其他情况 → 三条路径均可见，玩家可自行选择
- 全部趋中（4-6 范围）→ 默认触发 Stay 结局

---

## 3. GDScript / Logic Layer

### 3.1 New Script: `gdscripts/narrative_manager.gd`

**Extends:** `Node`（建议作为 Autoload 或在 GameManager 中引用）

**Purpose:** 叙事架构的核心控制器。管理场景序列、结局判定、回声系统触发。监听 StateSystem.state_changed 信号，根据状态选择场景文本变体和叙事事件。

```gdscript
extends Node

# --- Signals ---
signal scene_text_changed(scene_id: String, tone: String)  # 场景文本变体切换
signal echo_triggered(echo_id: String, variant: int)        # 回声触发
signal ending_determined(ending: String)                    # 结局判定

# --- Scene Sequence ---
const SCENE_ORDER: Array[String] = [
    "office", "lobby", "convenience_store",
    "bridge", "underpass", "subway_station"
]

const SCENE_PATHS: Dictionary = {
    "office": "res://scenes/office/office.tscn",
    "lobby": "res://scenes/lobby/lobby.tscn",
    "convenience_store": "res://scenes/store/convenience_store.tscn",
    "bridge": "res://scenes/bridge/bridge.tscn",
    "underpass": "res://scenes/underpass/underpass.tscn",
    "subway_station": "res://scenes/subway_station/subway_station.tscn"
}

# --- Ending Thresholds ---
const ENDING_KEEP_WALKING_HOPE: float = 6.0
const ENDING_KEEP_WALKING_WILL: float = 5.0
const ENDING_TURN_BACK_CONVICTION: float = 3.0
const ENDING_STAY_HOPE: float = 4.0
const ENDING_STAY_CONVICTION: float = 4.0
const ENDING_STAY_WILL: float = 4.0

# --- State ---
var current_scene_index: int = 0
var echo_flags: Dictionary = {}       # {echo_id: bool} — 是否已触发
var echo_variants: Dictionary = {}    # {echo_id: int} — 变体索引

# --- Echo System References ---
@onready var _state_system: Node = get_node_or_null("/root/StateSystem")
@onready var _dialogue_engine: Node = get_node_or_null("/root/GameManager")


func _ready() -> void:
    if _state_system and _state_system.has_signal("state_changed"):
        _state_system.state_changed.connect(_on_state_changed)


func _on_state_changed(state: Dictionary) -> void:
    # 根据当前场景 ID 和状态，计算文本基调并广播
    var tone := _calculate_tone_for_scene(current_scene_index, state)
    scene_text_changed.emit(SCENE_ORDER[current_scene_index], tone)


## 计算场景文本基调。不同场景对同一状态的响应不同。
func _calculate_tone_for_scene(scene_idx: int, state: Dictionary) -> String:
    var hope: float = state.get("hope", 5.0)
    var conviction: float = state.get("conviction", 5.0)
    var will: float = state.get("will", 5.0)

    match scene_idx:
        0:  # Office — 起点，对 hope 敏感
            if hope <= 3.0: return "despair"
            elif hope >= 7.0: return "hope"
            else: return "neutral"
        1:  # Lobby — 第一次遇到 Stranger，受 conviction 影响
            if conviction <= 3.0: return "fear"
            elif conviction >= 7.0: return "defiant"
            else: return "neutral"
        2:  # Convenience Store — 温暖/冷漠取决于 hope
            if hope <= 3.0: return "cold"
            elif hope >= 7.0: return "warm"
            else: return "neutral"
        3:  # Bridge — 阈限空间，受 will 影响
            if will <= 3.0: return "tired"
            elif will >= 7.0: return "determined"
            else: return "neutral"
        4:  # Underpass — 回声核心，综合状态
            return _calculate_underpass_tone(state)
        5:  # Subway Station — 结局
            return _calculate_station_tone(state)
        _:
            return "neutral"


func _calculate_underpass_tone(state: Dictionary) -> String:
    var hope: float = state.get("hope", 5.0)
    var conviction: float = state.get("conviction", 5.0)
    if hope <= 4.0 and conviction <= 4.0:
        return "despair"
    elif hope >= 6.0 and conviction >= 6.0:
        return "resolute"
    else:
        return "neutral"


func _calculate_station_tone(state: Dictionary) -> String:
    var hope: float = state.get("hope", 5.0)
    var conviction: float = state.get("conviction", 5.0)
    if hope >= ENDING_KEEP_WALKING_HOPE:
        return "forward"
    elif conviction <= ENDING_TURN_BACK_CONVICTION:
        return "backward"
    else:
        return "waiting"


## 触发叙事回声。由场景脚本在适当时机调用。
func trigger_echo(echo_id: String) -> void:
    if echo_flags.get(echo_id, false):
        return  # 已触发过，不再重复
    echo_flags[echo_id] = true
    echo_variants[echo_id] = _calculate_echo_variant(echo_id)
    echo_triggered.emit(echo_id, echo_variants[echo_id])


## 计算回声变体索引。基于当前状态决定 Stranger 第二次出现时的语气。
func _calculate_echo_variant(echo_id: String) -> int:
    match echo_id:
        "rain_echo":
            # 回声1变体: 取决于玩家在便利店到地下通道之间的选择
            # 0=关切(希望高), 1=中性, 2=讽刺/失望(希望低)
            var hope: float = _state_system.hope if _state_system else 5.0
            if hope >= 7.0: return 0
            elif hope <= 3.0: return 2
            else: return 1
        "screensaver_echo":
            # 回声2变体: 取决于 conviction
            var conviction: float = _state_system.conviction if _state_system else 5.0
            if conviction >= 7.0: return 0  # 挑衅语气:「你做……」
            else: return 1  # 自嘲语气:「你做……」
        _:
            return 0


## 地铁站终局判定。返回 ending ID 字符串。
func determine_ending(state: Dictionary) -> String:
    var hope: float = state.get("hope", 5.0)
    var conviction: float = state.get("conviction", 5.0)
    var will: float = state.get("will", 5.0)

    # 优先级 1: Turn Back (信念极低)
    if conviction <= ENDING_TURN_BACK_CONVICTION:
        return "turn_back"

    # 优先级 2: Keep Walking (希望高 + 意志强)
    if hope >= ENDING_KEEP_WALKING_HOPE and will >= ENDING_KEEP_WALKING_WILL:
        return "keep_walking"

    # 优先级 3: Stay (默认/全部趋中)
    if hope <= ENDING_STAY_HOPE and conviction <= ENDING_STAY_CONVICTION and will <= ENDING_STAY_WILL:
        return "stay"

    # 模糊状态 → 默认 Stay
    return "stay"


## 获取下一个场景的场景 ID。可用于场景过渡逻辑。
func get_next_scene(current_scene: String) -> String:
    var idx: int = SCENE_ORDER.find(current_scene)
    if idx == -1 or idx >= SCENE_ORDER.size() - 1:
        return ""
    return SCENE_ORDER[idx + 1]
```

### 3.2 New Script: `gdscripts/scene_base.gd`

**Extends:** `Node`（基类，所有场景脚本继承自此）

**Purpose:** 提供场景脚本的公共行为：状态感知文本配置、对话复原、回声触发接口。

```gdscript
extends Node

# SceneBase — 所有场景脚本的基类
# 提供公共行为: fade-in、状态感知文本配置、对话复原

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel

var scene_id: String = ""  # 子类重写


func _ready() -> void:
    if scene_manager:
        scene_manager.fade_in()
    _configure_environmental_text()
    _restore_dialogue_state()


## 子类重写: 配置该场景的所有环境文本（状态感知）
func _configure_environmental_text() -> void:
    pass


## 从 GameManager 恢复对话状态
func _restore_dialogue_state() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm and dialogue_runner and dialogue_runner.choices_made.is_empty():
        if gm.has("choices_history") and not gm.choices_history.is_empty():
            dialogue_runner.choices_made = gm.choices_history.duplicate()
```

### 3.3 New Script: `gdscripts/office.gd`（扩展现有）

```gdscript
extends Node  # scene_base 模式

@onready var scene_manager: Node = $SceneManager
@onready var dialogue_runner: Node = $CanvasLayer/DialoguePanel
@onready var window_text: Node3D = $Environments/WindowText
@onready var screensaver_text: Node3D = $Environments/ScreensaverText
@onready var desktop_text: Node3D = $Environments/DesktopText
@onready var door_trigger: Area3D = $InteractionZones/OfficeDoorTrigger

var scene_id: String = "office"


func _ready() -> void:
    scene_manager.fade_in()
    var gm: Node = get_node_or_null("/root/GameManager")
    var tone := _get_tone(gm)
    _set_environment_text(tone, gm)
    door_trigger.input_event.connect(_on_door_trigger_input)
    _restore_dialogue_state()


func _get_tone(gm: Node) -> String:
    if not gm:
        return "neutral"
    var hope: float = gm.get_slider("hope")
    if hope <= 3.0: return "despair"
    elif hope >= 7.0: return "hope"
    else: return "neutral"


func _set_environment_text(tone: String, gm: Node) -> void:
    match tone:
        "hope":
            window_text.text = "The city glitters through the rain.\nTonight could be different."
        "neutral":
            window_text.text = "Rain on the glass.\nAnother night at the office."
        "despair":
            window_text.text = "The streetlights blur.\nOne more night. One more."

    # 屏保文字始终固定 — 它是回声2的源点
    screensaver_text.text = "你做游戏有什么用？"
    desktop_text.text = "Deadline: Day %d / 90" % (gm.get_slider("day") if gm else 0)


func _on_door_trigger_input(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _start_door_dialogue()


func _start_door_dialogue() -> void:
    dialogue_runner.start("res://dialogues/office_door.json", "office_door")


func _restore_dialogue_state() -> void:
    var gm: Node = get_node_or_null("/root/GameManager")
    if gm and dialogue_runner and dialogue_runner.choices_made.is_empty():
        if gm.has("choices_history") and not gm.choices_history.is_empty():
            dialogue_runner.choices_made = gm.choices_history.duplicate()
```

### 3.4 Scene Scripts Pattern（所有场景脚本模式）

每个场景脚本继承 `scene_base.gd` 的公共行为，重写 `_configure_environmental_text()`：

| 场景 | 脚本 | 环境文本配置 | 特殊交互 |
|------|------|-------------|---------|
| Office | `office.gd` | 窗景文字（hope 驱动）、屏保文字、deadline | 门触发对话→场景切换 |
| Lobby | `lobby.gd` | 大厅描述（conviction 驱动）、保安态度 | Stranger 第一次对话（关键选择） |
| Convenience Store | `store.gd` | 灯光描述（hope 驱动）、货架文字 | 咖啡购买（will 影响） |
| Bridge | `bridge.gd` | 车流文字（will 驱动）、流浪汉文字 | 流浪汉镜像对话、回声2触发 |
| Underpass | `underpass.gd` | 涂鸦文字、灯光效果（综合状态） | Stranger 回声对话、回声1触发 |
| Subway Station | `subway_station.gd` | 时钟文字、广播文字 | 终局结局判定、Stranger 告别 |

### 3.5 Existing Script Modifications

#### `gdscripts/state_system.gd` — 需扩展

当前 `state_system.gd` 已经包含三轴管理器。叙事架构需要在其基础上扩展：

```gdscript
## 新增: 获取状态区间标签（用于回声变体计算）
func get_state_tier(axis: String) -> String:
    var value: float = get(axis, 5.0)
    if value <= 3.0: return "low"
    elif value >= 7.0: return "high"
    else: return "mid"
```

#### `gdscripts/game_manager.gd` — 需扩展

当前 GameManager 已有对话 API 骨架。需添加：

```gdscript
# --- 叙事系统 API ---

## 获取当前场景 ID
var current_scene_id: String = "office"

## 获取下一场景 ID
func get_next_scene_id() -> String:
    # 委托给 NarrativeManager
    var nm: Node = get_node_or_null("/root/GameManager/NarrativeManager")
    if nm and nm.has_method("get_next_scene"):
        return nm.get_next_scene(current_scene_id)
    return ""
```

#### `gdscripts/dialogue_engine.gd` / `gdscripts/dialogue_runner.gd` — 无需修改

现有的对话引擎（#46）对话条件评估和效果应用接口已经完整。叙事架构仅需通过 JSON 对话文件定义新对话树即可集成。

---

## 4. State System API Interface Definition（状态系统接口定义）

### 4.1 公开 API

`StateSystem`（位于 `/root/StateSystem` 的 Autoload）对外暴露以下接口：

| 方法/信号 | 类型 | 签名 | 说明 |
|-----------|------|------|------|
| `apply_choice()` | 方法 | `apply_choice(effect: Dictionary) -> void` | 应用选择效果，effect = {hope: float, conviction: float, will: float} |
| `get_state()` | 方法 | `get_state() -> Dictionary` | 返回 {hope: float, conviction: float, will: float} |
| `get_state_tier()` | 方法 | `get_state_tier(axis: String) -> String` | 返回 "low"/"mid"/"high"（阈值 3.0 / 7.0） |
| `reset()` | 方法 | `reset() -> void` | 重置为默认值 5.0 |
| `state_changed` | 信号 | `signal state_changed(state: Dictionary)` | 状态变化时广播 |

### 4.2 状态-结局映射矩阵

| 结局 | hope | conviction | will | 叙事含义 |
|------|------|-----------|------|---------|
| Keep Walking | ≥ 6 | — | ≥ 5 | 接受现状但选择继续前进。不是胜利，是坚持 |
| Turn Back | — | ≤ 3 | — | 否认现实，想要重新开始——回到办公室意味着再来一次 |
| Stay | ≤ 4 | ≤ 4 | ≤ 4 | 既不走也不回——在站台上无尽等待。完全否认 |

### 4.3 选择点状态影响对照

| 场景 | 选择点 | hope 影响 | conviction 影响 | will 影响 | 天数消耗 |
|------|--------|-----------|----------------|-----------|---------|
| 办公室 | 离开（无选择） | 0 | 0 | 0 | 0 |
| 大厅 | 回应 Stranger | +0.5 | +0.5 | 0 | 1 |
| 大厅 | 无视 Stranger | -0.5 | -0.5 | 0 | 1 |
| 大厅 | 跟保安闲聊 | +0.5 | 0 | -0.5 | 1 |
| 便利店 | 买咖啡 | +0.5 | 0 | +1.0 | 1 |
| 便利店 | 不买 | -0.5 | 0 | -0.5 | 1 |
| 便利店 | 跟店员聊天 | +0.5 | +0.5 | 0 | 2 |
| 便利店 | 沉默 | 0 | -0.5 | 0 | 1 |
| 天桥 | 停留看风景 | +0.5 | +0.5 | -0.5 | 1 |
| 天桥 | 快步走过 | 0 | 0 | +0.5 | 1 |
| 天桥 | 给流浪汉零钱 | +1.0 | +1.0 | 0 | 1 |
| 天桥 | 忽视流浪汉 | -0.5 | -0.5 | 0 | 1 |
| 地下通道 | 对 Stranger 承认 | +1.0 | +1.0 | +1.0 | 2 |
| 地下通道 | 对 Stranger 否认 | -1.0 | -1.0 | -1.0 | 2 |
| 地下通道 | 沉默离开 | 0 | 0 | 0 | 1 |

---

## 5. Echo System Data Model（回声系统数据模型）

### 5.1 回声定义

```gdscript
# 回声数据模型 — 每个回声条目定义
# EchoEntry = {
#     id: String,           # 唯一标识
#     trigger_scene: String, # 源点场景（回声台词首次出现的场景）
#     echo_scene: String,    # 重现场景（回声重现的场景）
#     echo_variants: Array,  # 文本变体数组 [文本0, 文本1, 文本2]
#     condition: Dictionary  # 可选 — 触发条件
# }
```

### 5.2 定义的三条回声

| ID | 源点场景 | 文本 | 重现场景 | 变体 | 触发条件 |
|----|---------|------|---------|------|---------|
| `rain_echo` | 便利店 | Stranger 说「雨这么大，你不会想走太远的」 | 地下通道 | 3 种（关切/中性/讽刺） | 必触发（固定路径） |
| `screensaver_echo` | 办公室 | 屏保文字「你做游戏有什么用？」 | 天桥 | 2 种（挑衅/自嘲） | 必触发（流浪汉对话中重现） |
| `lobby_broadcast_echo` | 大厅 | 保安说「又是一个加班到这个点的」 | 地铁站 | 1 种（广播变体重现「末班车即将发车」） | 需保安对话过一次 |

### 5.3 回声 1 变体对照（rain_echo）

| 变体索引 | 玩家状态条件 | Stranger 语气 | 文本 |
|---------|-------------|--------------|------|
| 0 | hope ≥ 7 | 关切、平静 | 「雨这么大，你不会想走太远的……但如果你一定要走，我理解。」 |
| 1 | 3 < hope < 7 | 中性、客观 | 「雨这么大，你不会想走太远的。」 |
| 2 | hope ≤ 3 | 讽刺、失望 | 「雨这么大，你不会想走太远的。……我早说过了。」 |

### 5.4 回声触发流程

```
玩家经过便利店外 → Stranger 说出"雨这么大"
    → EchoSystem 记录 echo_flags["rain_echo"] = false（未触发）
    → continue...
    →
玩家到达地下通道 → 遇到 Stranger
    → EchoSystem 检测 echo_flags["rain_echo"] == false
    → NarrativeManager.trigger_echo("rain_echo")
    → 计算变体索引（基于当前 hope 值）
    → echo_triggered.emit("rain_echo", variant_index)
    → DialogueEngine 加载对应变体的对话树
```

---

## 6. Stranger NPC Character Design Document（角色设计文档）

### 6.1 角色隐喻

Stranger 不是「神秘路人」——它是玩家内心状态的物理投射。每次出现时，Stranger 的外表、语气、对话内容都在反映玩家当前的三轴状态。

**核心设计原则：** Stranger 没有固定的「身份」。它的存在意义是「作为一面镜子」——玩家看 Stranger 时，看到的是自己的状态。

### 6.2 状态-外观映射

| 状态区间 | 外观 | 语气 | 站位 | 对话倾向 |
|---------|------|------|------|---------|
| hope ≥ 7, conviction ≥ 7 | 轮廓清晰，穿棕色风衣 | 平静、温暖 | 正面面对玩家 | 「你看起来不错」「这条路我走过很多次」 |
| hope ≥ 7, conviction < 5 | 轮廓清晰，但姿势拘谨 | 关切但犹豫 | 侧身站立 | 「你确定是这条路吗？」「好像要下雨了」 |
| 3 < hope < 7, 3 < conviction < 7 | 半清晰，浅色外套 | 中性、模糊 | 站在光线交界处 | 简短、开放性问题 |
| hope ≤ 3 | 面部被阴影覆盖 | 空洞、遥远 | 背光站立 | 「雨太大了。或者……是你眼睛有问题？」 |
| conviction ≤ 3 | 身影模糊，几乎看不清 | 讽刺、疲倦 | 蹲/坐在地上 | 「又来一次？」「你还没走完？」 |
| will ≤ 3 | 垂头、姿势无力 | 细声、断续 | 靠着墙 | 句子不完整，常常欲言又止 |

### 6.3 出场时机

| 出现地点 | 叙事功能 | 对话内容概要 |
|---------|---------|-------------|
| 大厅（第一次） | 引入 NPC，建立「这个人在观察我」的初始感知 | 「又一个加班的。」选择：回应/无视 |
| 地下通道（回声） | 核心回声音韵 — 重复/变形之前的话 | 回声变体对话（见 5.3） |
| 地铁站（终局） | 三个结局各有不同的告别方式 | 见下文表 |

### 6.4 结局中的 Stranger

| 结局 | Stranger 行为 | 后给玩家留下的印象 |
|------|--------------|------------------|
| Keep Walking | 在闸机口微笑，模糊地说「下次再见」→ 消失在人群中 | 一个终于放心的人 |
| Turn Back | 在天桥另一头出现，姿势和你出发时一模一样——好像在等你回来 | 一个从未离开过的人 |
| Stay | 坐在你旁边，但不再说话。最后站起来走进维修通道，留下你一个人 | 一个已经放弃了你的人 |

### 6.5 状态-对话文本模板

Stranger 的对话使用模板插值而非全手写。以下是一个模板示例：

```
模板 1（大厅，初次见面）:
  「{greeting}。{observation}」
    - greeting: "又一个加班的" (hope≥5) / "又一个" (hope<5)
    - observation: "看来你今天状态不错" (conviction≥6) / "你看上去不太好" (conviction<4) / "今天也很晚" (其他)

模板 2（地下通道，回声）:
  「{rain_echo_variant}」
    - 见 5.3 回声变体表

模板 3（地铁站，告别）:
  「{farewell}」
    - Keep Walking: "下次再见" — 微笑，转身消失
    - Turn Back: "你确定？" — 侧头，不变的姿势
    - Stay: "……" — 沉默，最终离开
```

---

## 7. Scene-State Mapping Matrix（场景-状态映射矩阵）

### 7.1 场景 × 状态区间 → 文本基调

| 场景 | hope≤3 (低) | hope 4-6 (中) | hope≥7 (高) | conviction≤3 (低) | conviction 4-6 (中) | conviction≥7 (高) |
|------|-------------|--------------|-------------|-------------------|--------------------|--------------------|
| 办公室 | 绝望（「灰色的雨」） | 中性（「又是办公室」） | 希望（「今晚不同」） | 焦虑（屏保闪烁） | 中性 | 坚定（「还有时间」） |
| 大厅 | 冷色调灯光 | 中性灯光 | 暖色调灯光 | 保安语气生硬 | 保安正常 | 保安点头示意 |
| 便利店 | 灯光刺眼/苍白 | 正常便利店灯光 | 温暖灯光 | 店员冷淡 | 店员正常 | 店员微笑 |
| 天桥 | 车流声刺耳 | 中性描述 | "城市在发光" | 恐高感加重 | 中性 | 眺望远方 |
| 地下通道 | 涂鸦阴暗/压抑 | 普通涂鸦 | 涂鸦略带色彩 | Stranger 带讽刺 | Stranger 中性 | Stranger 肯定 |
| 地铁站 | 末班车已走 | 时钟在走 | 进站（Keep Walking） | 检票口关闭 | 中性 | 站台明亮 |

### 7.2 场景 × will 的影响

will 主要影响场景中的「行动力」描述：

| will≤3 (低) | will 4-6 (中) | will≥7 (高) |
|-------------|--------------|-------------|
| 动作描述：缓慢、沉重 | 动作描述：正常 | 动作描述：轻盈、快速 |
| 对话选项出现「算了」「下次再说」 | 正常选项 | 对话选项出现「走吧」「继续」 |
| NPC 反应：「你看起来很累」 | 正常 | NPC 反应：「你精力不错」 |

### 7.3 文本变体策略

不采用全量手写（6 场景 × 3 轴 × 3 区间 = 54 套文本）。而是使用**分层模板插值**：

1. **场景核心文本**（每场景 1 套，含插值槽位）
2. **状态前缀词**（hope/conviction/will 各 3 档，共 9 个前缀）
3. **NPC 语气修饰**（3 档，基于 conviction）
4. **环境细节补丁**（2-3 个独立变量：雨量、灯光、背景音）

**组合方式：**
```
场景文本 = 核心文本.replace("{hope_prefix}", hope_prefix)
                    .replace("{conviction_prefix}", conviction_prefix)
                    .replace("{will_modifier}", will_modifier)
```

示例（便利店核心文本）：
```
「便利店的灯{light_tone}。{shelf_description}
{clerk_interaction}」
- light_tone: "刺眼又苍白" / "正常亮着" / "发出温暖的光"
- shelf_description: "货架上的东西看起来都一样" / "货架整齐" / "货架上的零食让人安心"
- clerk_interaction: "店员低头玩手机" / "店员朝你点点头" / "店员微笑着说'晚上好'"
```

---

## 8. Choice Point Specification（选择点规格说明）

### 8.1 选择点类型

参照 PRD #45 5.2 节：

| 类型 | 数量 | 特点 | 实现方式 |
|------|------|------|---------|
| 普通选择 | 6-8 | 衡量当前状态，影响小范围状态值（±0.5） | 对话 JSON 中的 choice 节点 |
| 条件选择 | 3-4 | 需要特定状态值才出现（如 conviction≥6 才出现的选项） | dialogue_condition_evaluator.gd 条件评估 |
| 终局选择 | 1-2 | 地铁站的最终判定——影响进入哪个结局 | narrative_manager.gd 的 ending 判定 |

### 8.2 完整选择点清单

| ID | 场景 | 类型 | 条件 | 选项 | 效果 | 文本模板 |
|----|------|------|------|------|------|---------|
| C01 | 大厅 | 普通 | — | 「你也是？」/ 沉默离开 | hope±0.5, conviction±0.5 | 「{greeting}」 |
| C02 | 大厅 | 条件 | conviction≥6 | 「我认识你吗？」 | hope+0.5, conviction+1.0 | 「也许你见过我」—— Stranger 说 |
| C03 | 大厅 | 普通 | — | 跟保安聊天 / 直接走出 | hope+0.5 或 0 | 「今天又加班？」/ 沉默 |
| C04 | 便利店 | 普通 | — | 买咖啡 / 不买 | will±1.0 | 「要一杯热的，谢谢」/ 「不用了」 |
| C05 | 便利店 | 条件 | hope≥6 | 跟店员说「今天过得不好」 | hope+1.0, will+0.5 | 「有时候一杯咖啡就够了」 |
| C06 | 便利店 | 普通 | — | 跟店员聊天 / 沉默 | hope±0.5, conviction±0.5 | 「这雨什么时候停？」/ 沉默 |
| C07 | 天桥 | 普通 | — | 停留看风景 / 快步走过 / 给零钱 | 多轴影响 | 文本随选择变化 |
| C08 | 天桥 | 条件 | conviction≤3 | 「这里跳下去会怎样？」（隐性触发） | 无选择——内心独白 | 「从这里跳下去就解脱了」——但你没有 |
| C09 | 天桥 | 条件 | will≥6 | 在雨中快步跑过天桥 | will+0.5, hope+0.5 | 「跑起来，雨打在脸上」 |
| C10 | 地下通道 | 普通 | — | 回应 Stranger / 沉默 | 三轴各±1，回声触发 | 见 5.3 |
| C11 | 地下通道 | 条件 | hope≥5 and will≥5 | 承认「我没事」 | 三轴各+0.5 | 「我没事。……大概是。」 |
| C12 | 地铁站 | 终局 | hope≥6, will≥5 | 进站（Keep Walking） | 结局 A | 「滴——检票通过」 |
| C13 | 地铁站 | 终局 | conviction≤3 | 转身（Turn Back） | 结局 B | 「你转身。雨还在下。」 |
| C14 | 地铁站 | 终局 | 默认 | 坐下等待（Stay） | 结局 C | 「末班车的灯光消失在隧道深处」 |

### 8.3 条件选择条件详情

| 条件选择 | 条件类型 | 条件逻辑 |
|---------|---------|---------|
| C02 — 「我认识你吗？」 | slider | conviction ≥ 6 |
| C05 — 「今天过得不好」 | slider | hope ≥ 6 |
| C08 — 内心独白「跳下去」 | slider | conviction ≤ 3（自动触发，非可选项） |
| C09 — 跑过天桥 | slider | will ≥ 6 |
| C11 — 「我没事」 | and slider | hope ≥ 5 AND will ≥ 5 |

---

## 9. Test Layer

### 9.1 测试结构

新建测试文件：`tests/test_narrative_architecture.gd` — 验证叙事架构逻辑。

### 9.2 覆盖要求

| 测试范围 | 正常路径 | 边界情况 | 失败路径 |
|---------|---------|---------|---------|
| NarrativeManager 场景序列 | ✅ | — | ✅ |
| NarrativeManager ending 判定 | ✅ (3种) | 边界值 | ✅ 默认 Stay |
| Echo 触发和变体计算 | ✅ (3条回声，含变体) | ✅ | ✅ |
| SceneBase fade-in + 状态文本 | ✅ | — | — |
| StateSystem get_state_tier | ✅ | 边界值 3.0/7.0 | — |

### 9.3 测试用例示例

**TC-N1: 正常结局路径（状态足够→Keep Walking）**

| # | 场景 | 输入/设置 | 预期行为 | 验证方法 |
|---|------|----------|---------|---------|
| TC-N1-1 | hope=7.0, will=6.0 | `NarrativeManager.determine_ending()` | 返回 "keep_walking" | `_assert(ending == "keep_walking")` |

**TC-N2: 边界结局路径（conviction≤3→Turn Back）**

| # | 场景 | 输入/设置 | 预期行为 | 验证方法 |
|---|------|----------|---------|---------|
| TC-N2-1 | conviction=2.0 | `NarrativeManager.determine_ending()` | 返回 "turn_back" | `_assert(ending == "turn_back")` |

**TC-N3: 默认结局（全部趋中→Stay）**

| # | 场景 | 输入/设置 | 预期行为 | 验证方法 |
|---|------|----------|---------|---------|
| TC-N3-1 | hope=5.0, conviction=5.0, will=5.0 | `determine_ending()` | 返回 "stay" | `_assert(ending == "stay")` |

**TC-N4: Echo 触发**

| # | 场景 | 输入/设置 | 预期行为 | 验证方法 |
|---|------|----------|---------|---------|
| TC-N4-1 | hope=7.0, trigger_echo("rain_echo") | variant=0，echo_flags["rain_echo"]=true | `_assert(variant == 0)` |
| TC-N4-2 | hope=2.0, trigger_echo("rain_echo") | variant=2，echo_flags["rain_echo"]=true | `_assert(variant == 2)` |
| TC-N4-3 | 重复触发同一回声 | echo_flags["rain_echo"] 已为 true | 第二次调用无效果 | `_assert(signal_count == 1)` |

**TC-N5: 状态轴 tier 计算**

| # | 场景 | 输入/设置 | 预期行为 | 验证方法 |
|---|------|----------|---------|---------|
| TC-N5-1 | hope=2.0 | `get_state_tier("hope")` | "low" | `_assert(tier == "low")` |
| TC-N5-2 | hope=5.0 | `get_state_tier("hope")` | "mid" | `_assert(tier == "mid")` |
| TC-N5-3 | hope=8.0 | `get_state_tier("hope")` | "high" | `_assert(tier == "high")` |
| TC-N5-4 | hope=3.0 (边界) | `get_state_tier("hope")` | "low" | `_assert(tier == "low")` |
| TC-N5-5 | expectation=7.0 (边界) | `get_state_tier("conviction")` | "high" | `_assert(tier == "high")` |

---

## 10. Files Changed（按层汇总）

### 新建文件

| 文件 | 说明 | 预估行数 |
|------|------|---------|
| `gdscripts/narrative_manager.gd` | 叙事架构核心控制器 | +200 |
| `gdscripts/scene_base.gd` | 场景脚本基类 | +60 |
| `gdscripts/lobby.gd` | 大厅场景脚本 | +80 |
| `gdscripts/bridge.gd` | 天桥场景脚本 | +80 |
| `gdscripts/underpass.gd` | 地下通道场景脚本 | +90 |
| `gdscripts/subway_station.gd` | 地铁站场景脚本 | +100 |
| `scenes/lobby/lobby.tscn` | 大厅场景 | +50 |
| `scenes/bridge/bridge.tscn` | 天桥场景 | +50 |
| `scenes/underpass/underpass.tscn` | 地下通道场景 | +50 |
| `scenes/subway_station/subway_station.tscn` | 地铁站场景 | +60 |
| `dialogues/office_door.json` | 办公室出口对话 | +30 |
| `dialogues/lobby_stranger.json` | 大厅 Stranger 初次对话 | +50 |
| `dialogues/lobby_guard.json` | 大厅保安对话 | +30 |
| `dialogues/store_clerk.json` | 便利店店员对话 | +40 |
| `dialogues/bridge_homeless.json` | 天桥流浪汉对话 | +30 |
| `dialogues/underpass_stranger_echo.json` | 地下通道回声对话 | +40 |
| `dialogues/subway_ending.json` | 地铁站终局对话 | +50 |
| `tests/test_narrative_architecture.gd` | 叙事架构测试 | +60 |

### 修改文件

| 文件 | 变更 | 预估行数 |
|------|------|---------|
| `gdscripts/state_system.gd` | 添加 get_state_tier() 方法 | +10 |
| `gdscripts/game_manager.gd` | 添加 current_scene_id, get_next_scene_id() | +15 |
| `gdscripts/scene_manager.gd` | 确保支持新的场景路径 | +5 |
| `gdscripts/constants.gd` | 添加叙事架构常量 | +15 |
| `scenes/main.tscn` | 确保 NarrativeManager 在场景树中 | +5 |

### 总计：约 +1,200 行（新代码 ~1,150 + 修改 ~50）

---

## 11. Acceptance Criteria 对照

### AC1（Shallow）— 完整时间线图

- [x] 第 2 节：6 个场景的线性路径图 + 节点树结构
- [x] 第 8 节：完整选择点清单（14 个选择点，含 3-4 个条件选择 + 1-2 个终局选择）
- [x] 第 4.2 节：3 个结局的状态条件映射表
- [x] 物理路径 + 状态分支共同构成完整「场景叙事图」

### AC2（Middle）— 叙事回声

- [x] 第 5.2 节：回声 1（rain_echo）— 便利店→地下通道，含 3 种变体
- [x] 第 5.2 节：回声 2（screensaver_echo）— 办公室→天桥，含 2 种变体
- [x] 第 5.2 节：回声 3（lobby_broadcast_echo）— 大厅保安→地铁站广播（后备）

### AC3（Deep）— 内在投射

- [x] 第 6 节：Stranger NPC 完整角色设计（状态-外观映射、出场时机、结局差异）
- [x] 第 4.2 节：三个结局的心理学映射（Keep Walking=接受，Turn Back=否认，Stay=停滞）
- [x] 第 6.4 节：Stranger 在不同结局中的角色行为差异

---

## 12. Dependencies & Next Steps

### Depends On

| 依赖 | 状态 | 风险 |
|------|------|------|
| Issue #42 主题-机制映射 | ✅ 已关闭 | Low — 映射链已定稿 |
| Issue #46 对话引擎数据模型 | ✅ 已关闭 | Low — 对话引擎运行时已设计，叙事架构直接使用 |
| Issue #5 CRPG 核心机制 | Research 完成 | Medium — 状态系统（state_system.gd）已实现基础版本 |
| 三轴状态系统实现 | ✅ 部分完成 | Low — state_system.gd 已实现 hope/conviction/will 三轴，需扩展 get_state_tier() |

### Next Steps（Implement 阶段）

1. 实现 `narrative_manager.gd` — 场景序列、结局判定、回声系统
2. 实现 `scene_base.gd` — 场景脚本基类
3. 创建 6 个场景的 `.tscn` 文件（office 已存在，需扩展；其余 5 个新建）
4. 创建场景脚本（office.gd 已存在，扩展；其余新建）
5. 创建对话 JSON 文件（7 个 NPC 对话树）
6. 扩展 `state_system.gd`（get_state_tier）
7. 扩展 `game_manager.gd`（scene tracking API）
8. 编写对话 JSON 文本内容（状态感知变体）
9. 编写测试 `tests/test_narrative_architecture.gd`

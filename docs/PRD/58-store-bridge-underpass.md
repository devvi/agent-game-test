# Research: [Scene] 便利店 → 天桥 → 地下通道

> Parent Issue: #58
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. 问题定义

### 当前行为

游戏目前包含前三个场景（办公室→大厅→便利店）的基础实现，天桥和地下通道场景已创建骨架文件和场景结构，但尚未完成有效内容。

**现有基础设施：**

- **`scenes/bridge/bridge.tscn`** — 场景骨架（Node3D 根节点 + Environments 子节点含 TrafficText/HomelessText/RainBridgeText + InteractionZones 含 RailingTrigger/HomelessTrigger/BridgeExitTrigger），**缺失** SceneManager.gd 脚本、DialoguePanel 实例、FadeCurtain、WorldEnvironment、Camera3D、光照
- **`scenes/underpass/underpass.tscn`** — 场景骨架（Node3D 根节点含 GraffitiText/EchoText/UnderpassLight + Interactions 含 GraffitiTrigger/StrangerEchoTrigger/UnderpassExitTrigger），同样**缺失**完整场景设施
- **`gdscripts/bridge.gd`** — 87 行，实现完整：`_get_tone()` 基于 will 值返回 tired/determined/neutral，`_set_environment_text()` 三组状态文本，`_check_intrusive_thought()` 低信念内心独白（conviction ≤ 2），栏杆/流浪汉/出口触发逻辑
- **`gdscripts/underpass.gd`** — 105 行，实现完整：`_get_tone()` 基于 hope+conviction 复合状态返回 despair/resolute/neutral，`_check_echoes()` 集成 screensaver_echo 和 rain_echo 回声系统，涂鸦/Stranger回声/出口触发逻辑
- **`dialogues/bridge_homeless.json`** — 流浪汉对话已实现（3 选项：给零钱/停下倾听/快步走过），设置 `screensaver_echo_heard` flag
- **`dialogues/underpass_stranger_echo.json`** — Stranger 回声对话已实现（3 分支：承认/否认/沉默），含 slider_delta 效果
- **`gdscripts/narrative_manager.gd`** — 场景序列已包含 bridge (index 3) 和 underpass (index 4)，回声系统定义了 `rain_echo` 和 `screensaver_echo`

**关键问题：**
- 天桥和地下通道场景**缺少完整的 3D 环境**（无几何体、无相机、无光照、无 WorldEnvironment）
- 场景间过渡机制已实现（`scene_manager.gd` 的 `advance_scene()`），但便利店 → 天桥 → 地下通道 → 地铁站的**对话/触发连接尚未建立**
- 天桥的**回声系统集成**（办公室屏保 echo 在低 conviction 时触发）已编码但需要在场景中验证
- AC3 要求的**隐藏文本**（despair < -5 时揭示 Stranger 为投影）与现有状态系统存在概念差异：`state_system.gd` 使用 hope/conviction/will (0–10)，`game_state.gd` 使用 hope/despair (0–100)，而 Issue 描述使用「despair < -5」

### 预期行为

玩家可以：

1. **从便利店通过出口触发过渡到天桥** — 完成便利店交互后，出口触发 → 场景切换至天桥
2. **在天桥探索三个交互点** — 栏杆（俯瞰车流，状态感知）、流浪汉（回声对话，触发 screensaver_echo）、出口（继续前行到地下通道）
3. **天桥环境文本响应玩家状态** — will 值决定 tired/determined/neutral 三套文本；低 conviction 触发内心独白
4. **通过天桥出口过渡到地下通道** — 出口触发 → 场景切换至地下通道
5. **在地下通道触发 Stranger 回声对话** — 三分支选择导向三种结局走向
6. **地下通道环境文本响应复合状态** — hope+conviction 决定 despair/resolute/neutral 基调
7. **深层路径（despair 极高时）揭示隐藏文本** — Stranger 被揭示为投影，改变叙事理解

### 用户场景

- **场景 A（首次游玩）：** 玩家完成便利店对话后，点击出口 → 淡出 → 天桥加载。看到"Traffic flows below the bridge…"等中性文本。点击栏杆看到描述文字。与流浪汉互动触发回声对话（"你做游戏有什么用？"），选择给零钱 → 信念+1。走到出口 → 淡出 → 地下通道加载。触发 Stranger 回声对话（"雨这么大，你不会想走太远的。"），选择承认 → 抵达地铁站。
- **场景 B（低信念/低希望重玩）：** 玩家 conviction ≤ 2 时进入天桥 → 内心独白触发（"从这里跳下去就解脱了"）。栏杆触发痛苦文本。地下通道 despair 基调下涂鸦文字消失，EchoText 揭示 Stranger 真相。
- **场景 C（高希望/高信念重玩）：** 玩家看到栏杆的积极文本（"The city lights stretch…"）。流浪汉选择偏积极。地下通道 resolute 基调下涂鸦文字包含鼓励信息。Stranger 对话选择承认获得全属性 +1。
- **频率：** 每轮游戏必经路径。这是从便利店到终局（地铁站）的中间段落，叙事密度最高。

---

## 2. 设计意图（功能）

### 为什么当前行为存在？

项目按分层 Issue 构建：
1. **Issues #15, #43, #45** — 项目脚手架：叙事架构、场景管理器、场景基类
2. **Issue #55** — 前三个场景集成（办公室→大厅→便利店），已合并
3. **Issue #58（此 Issue）** — 中间两个场景（天桥→地下通道），作为 #55 的直接后缀

天桥和地下通道的骨架（脚本、TSCN 结构、对话 JSON）已在 #45 叙事架构和 #55 场景序列中预先搭建，但几何体、光照、完整场景设施（Camera3D、WorldEnvironment、FadeCurtain）以及到便利店/地铁站的连接尚未实现。

### 为什么现在改变？

- Issue #55（办公室→街道→便利店）已合并，场景过渡机制已验证
- 天桥和地下通道的 GDScript 和对话 JSON 已就绪，只需场景环境搭建和连接
- 这是通往终局（地铁站，#59 或后续 Issue）的唯一路径，必须优先完成
- 回声系统（screensaver_echo 从办公室 → 天桥，rain_echo 从便利店 → 地下通道）的集成验证必须在此 Issue 中完成

### 先前约束

| 约束 | 详情 |
|------|------|
| 引擎 | Godot 4.7.1 / GDScript 2.0（静态类型） |
| 场景格式 | TSCN（Godot 文本场景格式） |
| 状态系统 | 三轴：hope, conviction, will (0–10, 5=中性) via `state_system.gd` |
| 游戏状态 | `game_state.gd`：hope (0–100), despair (0–100) — 与 state_system.gd 共存 |
| 对话格式 | JSON 格式，DialogueParser 加载 |
| 视觉风格 | Edward Hopper 城市夜景 — 深色 (#1a1a2e 天空)、暖琥珀光、lo-fi 像素文本 |
| 写作风格 | Hemingway — 短句、冰山理论、每行 ≤25 字 |
| LoFi 文本 | Label3D + 自定义着色器（像素化、色彩深度、扫描线、自发光辉光） |
| 场景过渡 | `SceneManager.gd` — fade_to_black (0.5s) → change_scene_to_file → fade_in (0.5s) |
| Autoloads | GameManager, GameState（但 state_system.gd 是手动实例化） |
| 对话引擎 | 信号驱动：`dialogue_started`, `dialogue_ended`, `node_changed`, `choices_available`, `choice_made` |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scenes/bridge/bridge.tscn` | 天桥场景 | **修改** — 添加 SceneManager.gd 脚本、DialoguePanel 实例、FadeCurtain、Camera3D、WorldEnvironment、光照、3D 几何体 |
| `scenes/underpass/underpass.tscn` | 地下通道场景 | **修改** — 与天桥相同：添加完整场景基础设施 |
| `dialogues/bridge_homeless.json` | 流浪汉对话 | **可能修改** — 选项可能需连接到场景过渡或新对话节点 |
| `dialogues/underpass_stranger_echo.json` | Stranger 回声对话 | **可能修改** — 终局连接：每个分支应导向地铁站或三结局之一 |
| `gdscripts/game_state.gd` | 游戏状态 | **可能修改** — 添加 despair 访问方法或映射到 state_system |
| `scenes/store/convenience_store.tscn` | 便利店场景 | **修改** — 添加 store → bridge 出口触发 |

### 间接影响模块

| 文件 | 模块 | 原因 |
|------|------|------|
| `gdscripts/narrative_manager.gd` | 叙事管理器 | 确保 bridge (index 3) 和 underpass (index 4) 正确工作；echo 集成验证 |
| `gdscripts/store.gd` | 便利店脚本 | 出口触发可能需连接桥的入口（目前已通过 `advance_scene()` 处理） |
| `gdscripts/subway_station.gd` | 地铁站脚本 | 地下通道出口需正确连接到地铁站 |
| `tests/` | 测试套件 | 场景过渡测试、回声系统测试 |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | GDD | 更新场景序列细节和回声集成 |

### 数据流影响

```
便利店 (Convenience Store)
  │ 玩家完成对话 → 点击出口触发
  │ advance_scene() → NarrativeManager.current_scene_index: 2→3
  │ change_scene_to_file("bridge.tscn")
  ▼
天桥 (Bridge)
  │ _ready() → fade_in → _configure_environmental_text() (基于 will)
  │ 交互: 栏杆(俯瞰) → 状态感知文本
  │ 交互: 流浪汉 → bridge_homeless.json → screensaver_echo 设置
  │ 低 conviction: 内心独白(侵入性想法)
  │ 出口 → advance_scene() → index: 3→4
  │ change_scene_to_file("underpass.tscn")
  ▼
地下通道 (Underpass)
  │ _ready() → fade_in → _configure_environmental_text() (基于 hope+conviction)
  │ _check_echoes() → 检查之前触发的 echo
  │ 交互: 涂鸦墙 → 回忆闪回(基于 hope)
  │ 交互: Stranger → underpass_stranger_echo.json
  │    ├── "我知道…" → hope+1, conviction+1, will+1
  │    ├── "不关你的事" → hope-1, conviction-1, will-1
  │    └── 沉默走过 → 无变化
  │ 高 despair: 隐藏文本揭示 Stranger 为投影
  │ 出口 → advance_scene() → index: 4→5
  │ change_scene_to_file("subway_station.tscn")
  ▼
地铁站 (Subway Station) ═══ 终局
```

### 需更新的文档

- [x] **此输出：** `docs/PRD/58-store-bridge-underpass.md`
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` — 更新天桥和地下通道场景的详细实现
- [ ] `docs/GAME_DESIGN/INDEX.md` — 更新索引

---

## 4. 方案比较

> depth/deep 标签：至少 2 种方案。

### 方案 A：完整场景构建（继承 Issue #55 模式）

**描述：**

遵循 #55 建立的场景模式：每个场景是独立 `.tscn`，包含：
- 根 Node3D + 场景脚本
- Camera3D + WorldEnvironment + 光照
- Environments（环境文本 Label3D 节点）
- InteractionZones（Area3D 触发器）
- SceneManager（fade 过渡）
- CanvasLayer → DialoguePanel（对话 UI）
- CanvasLayer → FadeCurtain（淡入淡出）

以 `convenience_store.tscn` 为参考模板，为 `bridge.tscn` 和 `underpass.tscn` 添加缺失的节点。使用 CSG 几何体（长方体）构建基础环境。

**优点：**
- 与 #55 完全一致的架构 — 无需学习新模式
- 每个场景可独立在 Godot 编辑器中打开和测试
- 场景过渡机制已验证（SceneManager, advance_scene）
- 对话 JSON 已存在，只需验证集成
- CSG 几何体快速搭建，无需外部 3D 模型

**缺点：**
- 天桥和地下通道需要 3D 环境设计（河/运河、栏杆、隧道墙壁）
- 几何体需要与叙事氛围匹配（黑暗运河、破损涂鸦墙、闪烁灯光）
- 需要额外设计「隐藏文本」的视觉呈现方式

**风险：** 低 — 与 #55 完全相同的模式。唯一风险是 AC3 的「despair < -5」条件与现有 state_system 的映射关系不确定。

**工作量：** 2–3 周（2 个场景 × 场景搭建 + 环境文本验证 + 回声集成 + 隐藏文本 + 测试）

---

### 方案 B：天桥 → 地下通道作为单一组合场景

**描述：**

将天桥和地下通道组合为一个 `bridge_underpass.tscn` 场景。玩家从桥的一端进入，走过整座桥，通过楼梯/坡道进入地下通道。整个序列在一个场景内完成，使用可见性切换而非场景过渡。

- 一个大的 Node3D 根包含桥的上层和地下通道下层
- 玩家从桥入口出发，走到桥另一端，沿坡道下行到地下通道
- 两个区域各有独立的 Camera3D 位置
- 地下通道内的 Stranger 对话在同一个场景中触发
- 「隐藏文本」在场景最后位置（靠近出口）根据状态显示

**优点：**
- 减少一次场景过渡（便利店 → 天桥 → 地下通道 变为 便利店 → 复合场景）
- 视觉上更连贯 — 玩家看到从天桥到地下通道的连续下坡
- NarrativeManager 只需从 bridge_index 跳转到 subway_index

**缺点：**
- 与既定场景模式不同（每个场景独立 .tscn）
- 场景文件更大，编辑器加载更慢
- Camera3D 需要在同场景内切换位置
- 需要在同一个场景树中管理两个环境的 WorldEnvironment 和光照
- 如果几何体复杂，难以在编辑器中导航

**风险：** 中 — 打破了每个场景独立 .tscn 的模式。WorldEnvironment 冲突（同场景只能有一个生效）需要额外处理。

**工作量：** 3–4 周（复合场景设计 + 两组环境 + 相机切换 + 光照管理 + 测试）

---

### 推荐

**→ 方案 A**，因为：
1. 与 #55 完全一致的架构 — 后续场景（地铁站）可直接沿用
2. 天桥和地下通道的 GDScript 已按独立场景编写（各自继承 SceneBase，各自有 `_ready()` 和交互触发逻辑）
3. NarrativeManager.SCENE_ORDER 已预设 bridge 和 underpass 为独立条目
4. 场景过渡本身是叙事工具 — 淡入淡出强化夜间行走的节奏感
5. 方案 B 的组合场景需要在同场景内处理两次 `_configure_environmental_text()` 调用（桥区域 → 地下通道区域），增加不必要的复杂度

---

## 5. 边界条件与验收条件

### 正常路径

1. **AC1（Shallow）：玩家完成 3 次场景过渡（便利店→天桥→地下通道且不崩溃）**
   - 便利店场景 → 点击出口 → 淡出 → 天桥场景加载 → 淡入
   - 天桥环境文本显示基于 will 值的正确变体
   - 天桥 → 点击出口 → 淡出 → 地下通道加载 → 淡入
   - 地下通道环境文本显示基于 hope+conviction 的变体
   - 完整流程无崩溃或错误

2. **AC2（Middle）：天桥文本基于便利店选择变化；Stranger 对话两层可见**
   - 如果玩家在便利店选择了高 conviction 路径 → 天桥 homeless 对话选项相应变化
   - bridge_homeless.json 已包含 3 选项（给零钱/倾听/走过），选项效果影响状态
   - underpass_stranger_echo.json 已有 3 分支（承认/否认/沉默），构成第一个可见层
   - **第二层：** 当玩家状态满足特定条件（如 screensaver_echo 已触发且 conviction < 4），Stranger 对话文本出现变体——更尖锐或更悲伤的台词版本

3. **AC3（Deep）：地下通道隐藏文本（despair 高时揭示 Stranger 为投影）**
   - 当 despair 达到阈值时（映射到 state_system：hope ≤ 2 且 conviction ≤ 2），地下通道的 EchoText 或特定环境文本显示：
   - 内容：揭示 Stranger 实际上是玩家内心的投射（"⌈你看到的不是别人——是你的影子⌋"）
   - 该文本在正常状态不可见（EchoText 默认 visible = false）
   - 当 despair 条件满足时，文本变为可见且内容改变

### 边界情况

1. **状态值在阈值边界：** `will = 3.0` 精确返回 tired 变体（使用 `<= 3.0` 和 `>= 7.0`，已验证）。`hope = 4.0` 且 `conviction = 4.0` 返回 despair 基调（使用 `<= 4.0`）。

2. **conviction 极低触发内心独白：** `conviction <= 2.0` 触发侵入性想法文本（"从这里跳下去就解脱了"）。已实现在 `bridge.gd._check_intrusive_thought()`。

3. **Echo 重复触发：** `NarrativeManager.trigger_echo()` 有 `echo_flags` 保护，防止 echo 重复触发。每个回声在整个游戏中只触发一次。

4. **对话文件缺失：** 如果 `bridge_homeless.json` 或 `underpass_stranger_echo.json` 缺失，`DialogueRunner.start()` 返回 false。流浪汉交互显示后备文本："The homeless person doesn't respond."；Stranger 交互显示："The tunnel is empty."

5. **场景加载失败：** `change_scene_to_file()` 返回错误时，SceneManager 记录错误。便利店场景保持当前状态。

6. **快速场景切换：** SceneManager 的 `transition_in_progress` 防止快速双击导致的多次场景切换。

### 失败路径

1. **对话文件损坏或格式错误：** Parser 在 load_dialogue() 时返回错误。Runner 记录错误。交互点保持可点击但显示后备文本。

2. **StateSystem 不可用：** 如果 `/root/StateSystem` 不存在，场景文本默认使用 neutral/5 变体。对话条件使用默认值评估。

3. **despair 映射找不到：** 如果 `game_state.gd` 的 despair 值与 `state_system.gd` 的值不一致，隐藏文本条件可能错误触发或不触发。**缓解：** 统一两个状态系统，或在 `game_state.gd` 中添加从 state_system 到 despair 的映射方法。

> 这些直接成为 Plan 阶段的测试用例骨架。

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| Issue #55 — 便利店场景（办公室→街道→便利店） | ✅ 已合并 | **低** — 天桥从便利店出口进入 |
| Issue #54 — 叙事架构（场景序列、回声系统） | ✅ 已合并 | **低** — SCENE_ORDER 已包含 bridge/underpass |
| Issue #15 — 项目脚手架 | ✅ 已合并 | **低** — 基础场景结构 |
| Issue #46 — 对话引擎 | ✅ 已合并 | **低** — 对话 JSON 已存在且格式已验证 |
| StateSystem 三轴状态 | ✅ 已实现 | **低** — bridge.gd 和 underpass.gd 都已使用 |
| DialogueRunner 信号 | ✅ 已实现 | **低** — choice_made → scene 连接已验证 |

### 依赖链

```
#55 Office → Street → Convenience Store
  │
  └── #58 (此 Issue) Store → Bridge → Underpass
        │
        └── #XXXX Subway Station（地铁站终局）
```

### 阻塞

| 未来工作 | 优先级 |
|---------|--------|
| 地铁站终局场景 | **Critical** — 地下通道出口直接导向地铁站 |
| 地铁站三结局实现 | **High** — 需要地下通道 Stranger 对话的选择作为输入 |
| 游戏主菜单/标题画面 | Medium |

### 准备工作

- [ ] **场景模板化：** 以 `convenience_store.tscn` 为模板为 bridge.tscn 和 underpass.tscn 添加完整场景基础设施（Camera3D、WorldEnvironment、光照、SceneManager、FadeCurtain、DialoguePanel 实例）
- [ ] **Exit 触发连接：** 确保便利店出口 → 天桥入口 → 地下通道入口 → 地铁站入口的 `advance_scene()` 调用链正确
- [ ] **despair 映射：** 确定 AC3「despair < -5」如何映射到现有 state_system（hope/conviction/will）或 game_state（hope/despair）
- [ ] **隐藏文本视觉：** 设计隐藏文本的呈现方式（EchoText 变为可见 + 内容变化？特殊 Label3D 仅在高 despair 时出现？）
- [ ] **三结局对话连接：** underpass_stranger_echo.json 的 3 个终局分支需要连接到地铁站的 3 个结局（Keep Walking / Turn Back / Stay）

---

## 7. Spike / 实验（depth/deep 强制 — 至少 3 个实验）

### 实验 A: despair 阈值映射 — 确定 AC3 条件

**待解答问题：**

Issue #58 的 AC3 要求「despair < -5」触发隐藏文本，但现有项目中有两个状态系统：
- `state_system.gd`：hope/conviction/will 在 0–10 范围，无 despair 概念
- `game_state.gd`：hope/despair 在 0–100 范围

如何将「despair < -5」（负值？）映射到可用状态？

**方法：**

1. 检查 `game_state.gd` 的当前实现（已读取：hope=100, despair=0, clamped 0–100）
2. 实验三种映射：
   - (a) 将「despair < -5」解读为「hope ≤ 2 且 conviction ≤ 2」（state_system 等效）
   - (b) 修改 `game_state.gd` 使 despair 范围包含负值，或在 `underpass.gd` 中添加基于 `(-hope/conviction 组合)` 的计算
   - (c) 在 `underpass.gd._check_echoes()` 中添加新的 echo 类型，由 `NarrativeManager.echo_flags` 和状态组合触发
3. Godot headless 验证：加载游戏状态并检查阈值触发

**预期结果：**

方案 (b) 最合理：AC3 的「despair < -5」可解读为 state_system 中 `hope ≤ 2.0` 且 `conviction ≤ 2.0` 的复合条件，或在 underpass.gd 中使用 GameState 的 despair 值（需修改范围支持负值）。

**对方案的影响：**

如果 (b) 成立，只需在 `underpass.gd._check_echoes()` 中或 `_configure_environmental_text()` 中添加条件分支。如果不成立，需要重新定义触发条件或修改状态系统。

---

### 实验 B: Echo 链集成验证 — 办公室屏保 → 天桥 → 地下通道

**待解答问题：**

回声系统定义了两个回声链：
1. **rain_echo：** 便利店 Stranger「雨这么大…」→ 地下通道重演（3 变体）
2. **screensaver_echo：** 办公室屏保「你做游戏有什么用？」→ 天桥流浪汉触发

当前代码中：
- `bridge.gd` 的 `_check_intrusive_thought()` 检查 `conviction ≤ 2.0` 触发内心独白
- 地下通道的 `_check_echoes()` 检查 `nm.echo_flags` 并设置 EchoText
- 天桥流浪汉对话 `bridge_homeless.json` 设置 `screensaver_echo_heard` flag

但 echo flags 和非 echo 文本（内心独白）是**两个独立系统**。实际 spelunking 时需要验证：
1. 玩家完成办公室场景 → 看到屏保 → 触发 screensaver_echo
2. 玩家到达天桥 → 如果 conviction ≤ 2 → 内心独白 + screensaver_echo 的状态检查
3. 玩家到达地下通道 → EchoText 显示 screensaver_echo 回响

**方法：**

1. 在测试中模拟路径：设置游戏状态（conviction=2.0），触发 screensaver_echo
2. 依次加载 bridge 和 underpass 场景
3. 检查 bridge 的 `_check_intrusive_thought()` 是否触发
4. 检查 underpass 的 `_check_echoes()` 是否读取到 echo_flags
5. 验证 EchoText 的 visible 和 text 是否正确

**预期结果：**

回声链应该可以工作（代码逻辑正确），但存在一个 gap：桥的侵入性想法和流浪汉对话的 screensaver_echo 是两条独立路径。需要确认玩家走两条路径时场景表现一致。

**对方案的影响：**

如果回声链有 gap，需要在桥的侵入性想法触发时同时调用 `nm.trigger_echo("screensaver_echo")`，使两条路径汇入同一个回声系统。

---

### 实验 C: Stranger 对话两层可见性 — 条件分支密度估算

**待解答问题：**

AC2 要求「Stranger's dialogue has two visible layers」。当前 `underpass_stranger_echo.json` 只有一层（3 分支：承认/否认/沉默）。如何添加第二层并确保玩家自然发现？

**方法：**

1. 分析现有条件系统（`dialogue_condition_evaluator.gd` 支持 slider/flag/choice_made/and/or/not）
2. 设计第二层文本的触发条件：
   - 第二层在每个分支的基础上根据 `conviction` 或 `screensaver_echo_heard` flag 变化
   - 例如：承认分支中，如果 `screensaver_echo_heard == true`，Stranger 说：「……你听到了，是吧。那条声音。」vs 默认「……好。那就走吧。」
3. 估算每个节点的分支文本变体数量
4. 检查 JSON 文件大小是否超过合理范围
5. 考虑使用 DialogueRunner 的 `choice_made` 历史引用之前的节点选择

**预期结果：**

- 每个分支约 2 个变体（带 echo flag 和不带），共约 6 个额外节点
- JSON 文件从当前 ~73 行扩展到约 150 行
- 条件使用 `flag` 类型（`screensaver_echo_heard`）和 `slider` 类型（`conviction`）

**对方案的影响：**

如果是可行的，直接在 `underpass_stranger_echo.json` 中添加条件节点。如果分支密度超过预期（每个分支 3+ 变体），考虑将对话拆分为多个 JSON 文件或使用中间层状态聚合条件。

---

## 8. 延续上下文

> *此部分是 activeForm 到下一个 agent（plan → implement）的交接内容。*

目前天桥和地下通道的**脚本层完全就绪**（bridge.gd: 87 行, underpass.gd: 105 行），对话 JSON 已存在（bridge_homeless.json: 35 行, underpass_stranger_echo.json: 73 行），但**场景环境层缺失**：
- 两个场景的 `.tscn` 都缺少 Camera3D、WorldEnvironment、光照、完整 SceneManager、DialoguePanel 实例、FadeCurtain
- 天桥需要 3D 几何体（桥面、栏杆、运河/公路下方）以匹配黑暗城市夜景氛围
- 地下通道需要 3D 几何体（隧道墙壁、涂鸦纹理、闪烁灯光）以匹配 liminal space 设计
- 便利店出口需要连接到天桥入口

**主要风险：**
1. **despair 映射不确定性（实验 A）：** AC3 的「despair < -5」与现有 state_system 的映射关系尚未定案，这是唯一可能改变架构的决策点
2. **Echo 集成验证（实验 B）：** 回声链在逻辑上正确，但需要实际场景加载测试确认侵入性想法和 screensaver_echo 两条路径的一致性
3. **Stranger 对话两层设计（实验 C）：** 条件分支扩展量适中，但需要写作者为第二层提供高质量的变体台词

**推荐实施顺序：**
1. Spike：despair 阈值映射决定 → 确定 AC3 触发条件 (实验 A)
2. 场景模板化：以 `convenience_store.tscn` 为模板，为 bridge.tscn 和 underpass.tscn 添加完整场景基础设施
3. 天桥 3D 几何体搭建（CSG 长方体桥面 + 栏杆 + 运河环境）
4. 地下通道 3D 几何体搭建（CSG 隧道 + 涂鸦平面 + 灯光柱）
5. 便利店出口 → 天桥连接
6. 天桥 → 地下通道连接
7. Stranger 对话二层变体添加（实验 C 输出）
8. AC3 隐藏文本实现（实验 A 输出）
9. 回声链集成验证（实验 B 输出）
10. 端到端测试

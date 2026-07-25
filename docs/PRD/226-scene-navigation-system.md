# Research: 场景间导航系统实现 (Scene Navigation System Implementation)

> Parent Issue: #226
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

《雨夜普罗摩茨》项目的场景间导航系统已**部分实现**，但核心运行组件仍有缺口。

**已实现的组件**（来自 #156, #221 合并）：

| 组件 | 文件 | 状态 | 行数 |
|------|------|:----:|:----:|
| ExitZone | `gdscripts/exit_zone.gd` | ✅ BUILD | 146 |
| SceneTitleOverlay | `gdscripts/scene_title_overlay.gd` | ✅ BUILD | 156 |
| SceneManager.trigger_zone_transition | `gdscripts/scene_manager.gd` | ✅ BUILD | 227 |
| SceneManager._show_title_overlay | `gdscripts/scene_manager.gd` | ✅ BUILD | inline |
| GameManager.navigation_context | `gdscripts/game_manager.gd` | ✅ BUILD | property (line 35) |
| GameManager.fallback_count | `gdscripts/game_manager.gd` | ✅ BUILD | property (line 37) |
| GameManager.target_spawn_point | `gdscripts/game_manager.gd` | ✅ BUILD | property (line 32) |
| Constants (NAV_\*) | `gdscripts/constants.gd` | ✅ BUILD | Lines 202-218, 10 constants |
| Input action "navigate_hint" | `project.godot` | ✅ BUILD | InputMap |
| FadeCurtain pipeline | `gdscripts/scene_manager.gd` | ✅ BUILD | Lines 26-76 |

**但以下核心运行组件尚未实现：**

| 缺失项 | 说明 | 影响 | 对应 AC |
|--------|------|------|---------|
| **NavigationController** | 每个场景的导航编排器——管理状态计时器、卡住检测、H键提示路由 | 场景中没有运行时导航逻辑 | AC1 |
| **NavFallback** | 卡住/掉落检测与回退传送逻辑 | 玩家掉出地图或卡在几何体时无法自动恢复 | AC1, AC5 |
| **H键提示系统** | 玩家按 H 键时显示场景方向提示文本 | 玩家无法按需获取导航辅助 | AC3 |
| **条件触发文本** | 停留>60s / 错误方向>30s 时触发环境文本更新 | 迷路玩家得不到渐进式辅助 | AC1 |
| **路线进度显示** | UI 显示当前场景名 + 路线进度 | 玩家不知"走了多远了" | AC3 |
| **场景可视引导配置** | 各场景的光源/NPC姿态/环境文本方向指引 | 场景中没有具体的出口引导元素 | AC1 |
| **导航时幻觉等级更新** | 进入新场景时同步更新距离-幻觉等级 | 幻觉等级不随场景变化 | AC5 |
| **对话状态保持** | 导航过渡中对话状态不丢失的验证 | 导航可能打断活跃对话 | AC4 |

### 详细缺口分析：已实现 vs 待实现

| 功能区域 | #221 PRD 设计 | DESIGN #221 详细设计 | 实际代码 | 差距 |
|----------|:-----------:|:------------------:|:-------:|:----:|
| SceneTitleOverlay | ✅ | ✅ | ✅ | 已实现 |
| ExitZone + navigation_context | ✅ | ✅ | ✅ | 已实现 |
| SceneManager.trigger_zone_transition | ✅ | ✅ | ✅ | 已实现 |
| NavigationController | ✅ | ✅ | ❌ | 需要新建 (约200行) |
| NavFallback (独立节点) | ✅ | ✅ | ❌ | 需要新建 (约80行) |
| fallback 检测 (高度/速度) | ✅ | 设计在 NavFallback | ❌ | 需要实现 |
| 条件触发 (Stay>60s/WrongDir>30s) | ✅ | 设计在 NavigationController | ❌ | 需要实现 |
| H键提示文本 | ✅ | ✅ | ❌ | 需要实现 |
| 路线进度 UI | ❌ 仅场景标题卡 | ❌ | ❌ | 需要设计+实现 |
| 幻觉等级更新 | ❌ | ❌ | ❌ | 需要实现 |
| 对话状态保持验证 | ❌ | ❌ | ❌ | 需要验证+修复 |
| 场景引导配置 (光/文本) | ✅ | ✅ | ❌ | 每个场景需要实现 |

### Expected Behavior

根据 Issue #226 验收条件：

1. **AC1:** 按 #11/#221 的设计实现导航系统——玩家通过点击/选择推进场景，或通过 ExitZone 行走过渡。导航系统完整运作（NavigationController + NavFallback + 条件触发 + H键提示）。
2. **AC2:** 导航时有场景过渡动画（淡入淡出或滑动）—— SceneTitleOverlay 在过渡期间显示，淡出 0.5s + 显示 3.0s + 淡入 0.5s。
3. **AC3:** 当前场景名称 + 路线进度显示在 UI 上——场景标题卡显示名称，进度条或文本指示显示路线进度。
4. **AC4:** 导航不打断对话状态——对话中的场景过渡正确处理，choices_made/state 不丢失。
5. **AC5:** 导航至新场景时更新距离-幻觉等级——进入新场景时调用 `NarrativeManager.get_hallucination_level()` 并应用到视觉参数。

### User Scenarios

- **Scenario A（首次游玩）：** 玩家从办公室开始，走进 ExitZone → 场景过渡淡出 → SceneTitleOverlay 显示"办公室 / The door waits." → 淡入 → 玩家出现在大厅。SceneTitleOverlay 显示名称和进度信息。
- **Scenario B（迷路玩家）：** 玩家在新场景中茫然停留 >60s → 环境文本自动更新为更明确的提示（"门在你身后的方向"）。或按 H 键获得提示。
- **Scenario C（卡住/掉落）：** 玩家掉出场景边界 → NavFallback 检测高度 < -10 → 快速淡出（0.3s）→ 重定位到 SpawnPoint → 淡入 → 显示回退文本。
- **Scenario D（对话中过渡）：** 玩家在对话中选择携带 scene 元数据的选项 → 对话状态保存到 GameManager → 场景过渡 → 新场景恢复对话状态 → 玩家继续对话。
- **Frequency:** 每次场景切换触发导航系统。每条游玩流程约 6+ 次场景切换。卡住/掉落低频但关键。

---

## 2. Design Intent

### Why Does Current Behavior Exist?

导航系统部分实现的现状源于迭代式开发的历史：

| 原因 | 说明 | 相关 Issue |
|------|------|-----------|
| ExitZone 优先于 NavigationController | #156 专注于"怎么切换场景"（ExitZone 机械层），导航逻辑（停留检测、H键、fallback）是后续范围 | #156 |
| SceneTitleOverlay 作为独立组件交付 | #221 的设计文档包括 SceneTitleOverlay，实施阶段作为独立 PR 合并；但导航编排器因 scope 拆分留到后续 | #221 |
| 路线进度 UI 未纳入导航设计 | #221 的设计聚焦于"引导玩家到出口"，未包含"路线进度"这个上层感知需求 | #221 |
| 幻觉引擎独立于导航 | #214 设计了距离→幻觉映射表，但"导航时触发幻觉更新"是实施细节，未在设计层面连接 | #214 |
| 场景引导配置未统一 | 每个场景的环境引导（光、文本、NPC姿态）需要逐个场景实现，无法一次性完成 | — |

### Why Change Now?

1. **基础设施已就绪** — ExitZone、SceneTitleOverlay、SceneManager 扩展、GameManager 属性、Constants——所有依赖已合并。仅 NavigationController + NavFallback + 配置工作待完成。

2. **MVP 路径需要完整的导航体验** — 没有 NavigationController 意味着：
   - 玩家迷路没有任何渐进辅助（停留检测、方向纠正提示都不存在）
   - 玩家卡住必须重启游戏（无 fallback）
   - 玩家无法按 H 获取提示
   - 幻觉等级在不同场景中不更新

3. **路线进度是核心 MVP 功能** — 玩家需要感知"旅程"的进程。三条路线的叙事弧线（#214）已经设计完成，路线进度显示让玩家知道在路线上的位置。

4. **对话状态保持需要验证** — #156 的 SceneManager 已有 `_persist_dialogue_state()`，但在 ExitZone 过渡路径中未充分验证，可能导致对话中的过渡丢失状态。

5. **幻觉等级更新是导航的核心反馈** — 距离→幻觉映射（#214）是雨夜普罗摩茨的核心机制之一。导航至新场景而不更新幻觉等级意味着幻觉机制不随游戏进程演进。

### Previous Constraints

| 约束 | 说明 | 来源 |
|------|------|------|
| 博尔赫斯风格约束 | 导航引导不能破坏「不可靠叙述」——不能有明确的「→ 出口」箭头或元游戏提示 | #214 (B1-B6) |
| Hemingway 约束 | 任何导航文本必须遵循 25 字符/句、3 句/节点限制 | #51 |
| 三层表达 | 导航设计必须支持 L1（字面出口指示）、L2（暗示性导引）、L3（象征性路径）三层 | #214 |
| 现有过渡通道 | 必须使用现有 SceneManager fade-out/fade-in 管道 | #156 |
| ExitZone 接口 | NavigationController 需兼容现有 ExitZone 的 `exit_label`/`route_hint` 接口 | #156 |
| 场景序列 | 场景顺序由 `NarrativeManager.SCENE_ORDER` 定义，不可修改 | #45/#214 |
| 幻觉映射 | 幻觉等级由 `NarrativeManager.get_hallucination_level()` 计算，不可在 NavigationController 中重写 | #214 |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/navigation_controller.gd` | NavigationController | **新建** — 每个场景的导航编排器 |
| `gdscripts/nav_fallback.gd` | NavFallback | **新建** — 卡住/掉落检测与回退 |
| `gdscripts/scene_base.gd` | SceneBase | **修改** — 添加 `_setup_navigation()` 和导航信号连接 |
| `gdscripts/scene_manager.gd` | SceneManager | **修改** — 添加过渡时间轴中的幻觉更新钩子 |
| `gdscripts/player_controller.gd` | PlayerController | **修改** — 添加 H键输入绑定和 `navigation_hint_requested` 信号 |
| `gdscripts/narrative_manager.gd` | NarrativeManager | **修改** — 添加场景导航时更新幻觉等级的公共方法 |
| `gdscripts/game_manager.gd` | GameManager | **修改** — 添加 `route_progress` 和 `last_scene_id` 属性 |
| `scenes/office/office.gd` | 办公室场景 | **修改** — 出口环境引导（光源、文本） |
| `scenes/lobby/lobby.gd` | 大厅场景 | **修改** — Stranger 姿态、出口引导 |
| `scenes/store/convenience_store.gd` | 便利店场景 | **修改** — 后门引导、环境文本 |
| `scenes/street/street.gd` | 街道场景 | **修改** — 方向引导、光源方向 |
| `scenes/bridge/bridge.gd` | 天桥场景 | **修改** — 方向性引导、光源指引 |
| `scenes/underpass/underpass.gd` | 地下通道场景 | **修改** — 出口光引导 |
| `scenes/subway_station/subway_station.gd` | 地铁站场景 | **修改** — 路线分歧引导 |
| `scenes/*.tscn` (8 场景) | 场景文件 | **修改** — ExitZone 放置和光照调整 |

### New Files Needed

| File | Purpose |
|------|---------|
| `gdscripts/navigation_controller.gd` | 每个场景的导航编排器，管理条件计时器、H键路由、卡住检测 |
| `gdscripts/nav_fallback.gd` | 独立 fallback 组件，检测玩家掉落/卡住并执行重定位 |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/state_system.gd` | StateSystem | 可能需要提供 `is_in_dialogue` 状态供 NavigationController 检查 |
| `gdscripts/worldview_controller.gd` | WorldviewController | 路线进度可能影响视觉反馈参数 |
| `dialogues/*.dialogue` .js| 对话文件 | NPC 对话可能加入方向性提示（间接导航） |
| `gdscripts/hallucination_shader.gd` | 幻觉着色器 | 幻觉等级更新后需要同步视觉参数 |

### Data Flow Impact

**当前场景过渡流程（已实现）：**

```
玩家走入 ExitZone
  → ExitZone._on_body_entered()
    → 设置 GameManager:
      ├── target_spawn_point = spawn_point
      └── navigation_context = {exit_label, route_hint, next_scene_id}
    → SceneManager.trigger_zone_transition(target_scene)
      → SceneManager._show_title_overlay(target_scene)
        → SceneTitleOverlay (scene_name + route_hint)
      → fade_out (0.5s) → change_scene_to_file → fade_in (0.5s)
      → SceneBase._ready() → _instantiate_player() at spawn_point
```

**添加 NavigationController + 幻觉更新后的完整流程：**

```
玩家走入 ExitZone
  → ExitZone._on_body_entered()
    → 设置 GameManager.navigation_context
    → SceneManager.trigger_zone_transition(target_scene)
      → SceneManager._show_title_overlay(target_scene)
      → 对话状态持久化 (已实现)
      → fade_out (0.5s) → change_scene_to_file

--- 新场景加载 ---

  → SceneBase._ready()
    → SceneManager.fade_in()
    → _instantiate_player() at spawn_point
    → _setup_navigation()            ← 新增
      → NavigationController 创建/连接
        ├── 连接 fallback_triggered → SceneBase._on_player_fell()
        ├── 连接 navigation_hint_requested → SceneBase._show_navigation_hint()
        └── 连接 condition_text_updated → SceneBase._on_condition_text_updated()
    → 更新幻觉等级                    ← 新增
      → NarrativeManager.get_hallucination_level(scene_id, state)
      → 发出 hallucination_level_changed 信号
    → 更新路线进度                    ← 新增
      → 计算 current_scene_index / SCENE_ORDER.size()
      → 存入 GameManager.route_progress
    → _restore_dialogue_state()       ← 验证：对话状态保持
    → fade_in() 完成
      → SceneTitleOverlay 显示 3.0s 后自动消失
```

**Fallback 流程：**

```
NavigationController._physics_process():
  ├── 如果 player.global_position.y < -10.0 → 触发 fallback("fell")
  └── 或 velocity.length() < 0.01 持续 3s (非对话中) → 触发 fallback("stuck")

NavFallback._trigger_fallback(reason):
  ├── 增加 GameManager.fallback_count
  ├── 如果 fallback_count >= 3 → 强制跳转到 title_screen.tscn
  ├── fade_out (0.3s)
  ├── 传送玩家到 SpawnPoint
  ├── 重置玩家 velocity
  ├── fade_in (0.3s)
  └── NavigationController 重置所有计时器
```

### Documents to Update

- [x] **本文档:** `docs/PRD/226-scene-navigation-system.md`
- [ ] `docs/DESIGN/226-scene-navigation-system.md` — Plan 阶段实施设计文档
- [ ] `docs/TASKS/226-scene-navigation-system.md` — 实施任务分解
- [ ] `docs/GAME_DESIGN/` — 添加导航系统说明

---

## 4. Solution Comparison

### Approach A: 独立 NavigationController 节点 + SceneBase 集成

**描述：**

每个场景创建一个独立的 `NavigationController` 节点（`extends Node`）作为 SceneBase 的子节点，负责该场景的所有导航运行时逻辑。NavFallback 作为 NavigationController 的子组件或同级节点。SceneBase 在 `_ready()` 中调用 `_setup_navigation()` 创建/连接 NavigationController。

**NavigationController 职责：**
- 管理条件计时器（stay >60s, wrong direction >30s, stuck >3s）
- 路由 H 键提示（连接 PlayerController.navigation_hint_requested）
- 检测玩家掉落（y < -10）和卡住（velocity < 0.01 for 3s）
- 触发 fallback 信号
- 提供 `get_exit_hint_text()` / `get_stay_warning_text()` / `get_wrong_dir_text()`

**NavFallback 职责：**
- 监听 fallback_triggered 信号
- 执行淡出→重定位→淡入序列
- 管理 fallback 计数器（防止无限循环）
- 3 次 fallback 后跳转到 title screen

**SceneBase 新增方法：**
```gdscript
func _setup_navigation() -> void:
    if not enable_navigation: return
    var nav = get_node_or_null("NavigationController")
    if not nav:
        nav = load("res://gdscripts/navigation_controller.gd").new()
        nav.name = "NavigationController"
        add_child(nav)
    nav.set("scene_id", scene_id)
    nav.set("spawn_point", _get_player_spawn_position())
    nav.fallback_triggered.connect(_on_player_fell)
    nav.navigation_hint_requested.connect(_show_navigation_hint)
    nav.condition_text_updated.connect(_on_condition_text_updated)

func _show_navigation_hint(text: String) -> void: pass  # override
func _on_condition_text_updated(hint: String) -> void: pass  # override
```

**幻觉等级更新：**
在 `SceneBase._ready()` 中增加：
```gdscript
func _update_hallucination_on_scene_entry() -> void:
    var nm := get_node_or_null("/root/NarrativeManager")
    var ss := get_node_or_null("/root/StateSystem")
    if nm and ss and ss.has_method("get_state"):
        var state := ss.get_state()
        var level = nm.get_hallucination_level(scene_id, state)
        nm.set("_hallucination_level", level)
        nm.hallucination_level_changed.emit(level)
```

**路线进度显示：**
```gdscript
func _update_route_progress() -> void:
    var nm := get_node_or_null("/root/NarrativeManager")
    if not nm:
        return
    var idx = nm.SCENE_ORDER.find(scene_id)
    var total = nm.SCENE_ORDER.size()
    var progress = float(idx + 1) / float(total)  # 0.0 ~ 1.0
    var gm := get_node_or_null("/root/GameManager")
    if gm:
        gm.set("route_progress", progress)
        gm.set("route_progress_text", "%d/%d" % [idx + 1, total])
    # 路由名称：从 NarrativeManager 获取
    var route = _get_current_route_name()
    _update_progress_ui(route, progress)
```

**Pros:**
- 独立组件，职责清晰（导航逻辑不侵入 SceneBase）
- 每个场景可独立启用/禁用导航（`enable_navigation` export 属性）
- NavFallback 分离管理，回退逻辑不耦合计时器
- 条件计时器在 physics_process 中运行，不受 _process 帧率影响
- 幻觉等级更新和路线进度更新集中在一处（SceneBase._ready()），易于审计
- SceneBase 的修改最小化（~15 行新增 + 2 个 virtual 方法）
- 与现有 ExitZone / SceneManager / SceneTitleOverlay 完全兼容

**Cons:**
- 每个场景多一个节点实例（NavigationController + NavFallback），8 个场景 = 16 个节点
- 条件计时器需要每帧检查 physics_process → 极低 CPU 开销（每个场景一次位置/方向检查）
- NavigationController 需要引用 PlayerController（通过 parent 访问或信号）
- NavFallback 的回退序列需要与 SceneManager 协作（fade_out/fade_in 调用）

**Risk:** 🟢 Low — 每个子组件都是标准 Godot 模式（Node._physics_process, Area3D.body_entered, Timer, signal connection）。不存在引擎级不确定性。

**Effort:** Medium（3-5 天 — NavigationController + NavFallback 约 1.5 天, SceneBase 集成约 0.5 天, 幻觉/路线进度更新约 0.5 天, 场景引导配置约 1-2 天, 测试约 0.5 天）

---

### Approach B: SceneBase 直接集成导航逻辑（无独立 NavigationController）

**描述：**

不在独立节点中管理导航逻辑，而是将 NavigationController 的所有功能直接集成到 SceneBase 中。SceneBase 在 `_ready()` 中初始化计时器变量，在 `_physics_process()` 中检查条件，在 `_input()` 中处理 H 键。NavFallback 的逻辑也直接集成。

```gdscript
# SceneBase.gd (修改后)
var _stay_timer: float = 0.0
var _wrong_dir_timer: float = 0.0
var _stuck_timer: float = 0.0
var _hint_cooldown: float = 0.0
var _last_player_pos: Vector3
var _fallback_count: int = 0

func _ready() -> void:
    # ... 现有逻辑 ...
    if enable_navigation:
        _init_navigation_timers()

func _physics_process(delta: float) -> void:
    if not enable_navigation:
        return
    _update_navigation_timers(delta)

func _input(event: InputEvent) -> void:
    if not enable_navigation:
        return
    if event.is_action_pressed("navigate_hint"):
        _show_hint_text()

func _show_hint_text() -> void: pass
func _on_condition_text_updated(hint: String) -> void: pass
```

**Pros:**
- 无需新建节点，SceneBase 内聚所有导航逻辑
- 每个场景自动继承导航行为（无需在场景中手动添加 NavigationController 节点）
- 单文件管理，易于 debug（所有导航代码在 SceneBase 中）
- 没有节点间的信号连接延迟

**Cons:**
- SceneBase 职责爆炸——从 243 行增长到约 400+ 行
- SceneBase 混合了场景生命周期、玩家生成、环境文本、幻觉更新、导航逻辑——违反单一职责
- 子类无法独立定制导航行为（SceneBase 的导航逻辑对所有场景相同）
- 添加/移除导航功能需要修改 SceneBase（影响所有场景），不是组件化的开关
- 未来的导航增强（如多出口优先级、地图导航）将进一步膨胀 SceneBase
- 与现有 SceneBase 的信号连接（`scene_text_changed`, `interaction_requested`）交织，增加耦合风险

**Risk:** 🟡 Medium — 代码组织问题（职责爆炸）虽不直接影响运行时正确性，但显著增加维护成本和未来的修改风险。

**Effort:** Short-term Low / Long-term Medium（~2-3 天实现，但后续每次导航功能修改都需要修改 SceneBase）

---

### Approach C: 利用 autoload 管理全局导航状态 + 信号驱动的组件

**描述：**

创建一个 `NavigationRouter` autoload 管理全局导航状态（场景序列、路线进度、fallback 计数器），每个场景通过信号和 autoload 方法请求导航操作。NavigationController 作为简易节点（仅管理本地计时器），NavFallback 逻辑放在 autoload 中。

```gdscript
# NavigationRouter.gd (autoload)
extends Node

var scene_sequence: Array[String] = []
var current_route: String = ""
var route_progress: float = 0.0
var fallback_count: int = 0
var hallucination_level: int = 0

func register_scene_navigation(scene_id: String) -> void:
    var idx = scene_sequence.find(scene_id)
    route_progress = float(idx + 1) / float(scene_sequence.size())

func trigger_fallback(player: Node, spawn_point: Vector3) -> void:
    fallback_count += 1
    if fallback_count >= 3:
        get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
        return
    # 执行淡出→重定位→淡入
```

**Pros:**
- 全局导航状态集中管理（route_progress, hallucination_level, fallback_count 不依赖 GameManager）
- 所有场景共享导航状态，无需通过 GameManager 传播
- 跨场景的 fallback 计数真正全局（不仅仅是当前场景）
- autoload 在场景加载时不会重置（GameManager 的属性可能被重置）

**Cons:**
- **新的 autoload 增加耦合** — 所有场景都要依赖 NavigationRouter，增加了加载时的依赖链长度
- GameManager 已经承担全局状态管理角色——新增 NavigationRouter 与现有 `navigation_context` 属性重复
- 全局 fallback 计数 vs 单场景 fallback 计数：3 次连续 fallback 触发 title screen 应该是单次场景访问的限制，不是全局
- 每个场景的 NavigationController 仍然存在——autoload 不消除本地节点，只是转移全局状态
- 与现有 SceneManager 的 fade 管道协作需要额外磨合（SceneManager 不是 autoload）

**Risk:** 🟡 Medium — 新增 autoload 打破现有架构模式（7 个现有的 autoload 已充分），引入不必要的全局耦合。

**Effort:** Medium（3-5 天 — autoload + 现有组件适配）

---

### 推荐方案

→ **Approach A（独立 NavigationController 节点 + SceneBase 集成）** 因为：

1. **职责分离** — NavigationController 承担导航编排，SceneBase 承担场景生命周期。未来任何导航功能修改不影响 SceneBase 的核心职责（玩家生成、状态连接、环境文本）。

2. **组件化** — 每个场景通过 `enable_navigation` 开关控制导航。可以在 `_setup_navigation()` 中延迟或条件化创建（例如：教程场景不需要导航）。

3. **与现有架构一致** — ExitZone 也是独立 Area3D 节点，SceneTitleOverlay 是独立 CanvasLayer——NavigationController 遵循相同的组件化模式。

4. **幻觉/路线进度更新在 SceneBase 中** — 虽然 NavigationController 是独立节点，幻觉等级更新和路线进度显示属于"场景进入时的一次性操作"，放在 SceneBase._ready() 中更自然（不需要 NavigationController 的每帧逻辑）。

5. **最小化 SceneBase 修改** — \<15 行新增代码 + 2 个 virtual 方法。SceneBase 保持不变的核心架构。

6. **NavFallback 作为独立组件** — 回退逻辑（fade_out/teleport/fade_in 序列）是 SceneManager 的扩展操作，NavFallback 作为一个独立的 Node 与 SceneManager 协作，不耦合 NavigationController 的计时器。

**关键设计决策：**

| 决策 | 选择 | 理由 |
|:----:|:----:|:----:|
| NavigationController vs 直接集成 | 独立 Node | 职责分离（ScenarioBase 不做导航编排） |
| NavFallback vs NavigationController 内置 | 独立 Node | 回退逻辑不耦合计时器，便于独立测试 |
| 幻觉等级更新位置 | SceneBase._ready() | 场景进入时一次性操作，不在 NavigationController 中 |
| 路线进度存储 | GameManager | 复用现有状态管理，不支持新建 autoload |
| H键输入检测 | PlayerController → NavigationController | 现有信号连接模式（与 EKeyTrigger 一致） |
| 条件触发文本持久化 | 临时覆盖 5s 后恢复 | 不改变场景的 tone 文本，仅临时提示 |
| 对话状态保持 | 现有 SceneManager._persist_dialogue_state() | 已实现，只需验证 ExitZone 路径的正常工作 |

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

- [x] **AC1: 导航系统实现** — NavigationController + NavFallback 实现，SceneBase 集成，8 场景引导配置
- [x] **AC2: 过渡动画** — SceneTitleOverlay 在过渡期间显示，淡出 0.5s + 显示 3.0s + 淡入 0.5s。不可跳过。
- [x] **AC3: 场景名 + 路线进度** — SceneTitleOverlay 显示场景中文名（SceneBase.scene_title_chinese, 见 DESIGN #221 §2.2），路线进度以 "2/6" 文本显示在标题卡副标题中
- [x] **AC4: 对话不打断** — `SceneManager._persist_dialogue_state()` 在 ExitZone 路径中正确保存 `choices_history`，新场景 `_restore_dialogue_state()` 正确恢复
- [x] **AC5: 幻觉等级更新** — `_update_hallucination_on_scene_entry()` 在 `SceneBase._ready()` 中调用，更新 `NarrativeManager._hallucination_level` 并发出 `hallucination_level_changed` 信号

### Acceptance Criteria Detail

| AC# | 描述 | 验证方法 |
|:---:|------|---------|
| AC1 | NavigationController 在每个场景启动时创建，_physics_process 管理条件计时器 | 单元测试：断言计时器随 delta 递增；集成测试：断言 fallback 触发 |
| AC1 | NavFallback 在玩家 y < -10 或速度 < 0.01 持续 3s 时触发 | 单元测试：mock PlayerController 位置/速度 → 断言 fallback 信号发射 |
| AC1 | Fallback 传送玩家到 SpawnPoint，重置速度，显示回退文本 | 集成测试：模拟位置异常 → 断言 fade_out → spawn_point teleport → fade_in |
| AC1 | 连续 3 次 fallback 跳转到 title_screen.tscn | 单元测试：mock fallback_count=3 → 断言 change_scene_to_file("title_screen") 调用 |
| AC2 | SceneTitleOverlay 在 trigger_zone_transition 中创建 | 集成测试：模拟场景过渡 → 断言 SceneTitleOverlay 节点存在 |
| AC2 | SceneTitleOverlay 显示场景中文名 + 路线提示 + 路线进度 | 视觉测试：标题卡文本包含 scene title + route_hint + "2/6" |
| AC3 | 路线进度在 GameManager.route_progress 中更新 | 单元测试：进入 scene 3/6 → 断言 progress = 3.0/6.0 ≈ 0.5 |
| AC4 | Dialogue state 在 ExitZone 过渡后正确恢复 | 集成测试：对话中 ExitZone 过渡 → 断言 choices_made/state 在目标场景中一致 |
| AC5 | 进入新场景时 hallucination_level 正确更新 | 单元测试：mock NarrativeManager → 断言 get_hallucination_level 被调用 |
| AC5 | hallucination_level_changed 信号被发射 | 单元测试：连接信号 → 断言信号在场景加载时发射 |

### Edge Cases

1. **对话中触发 ExitZone 过渡（AUTO 模式）：** 玩家在对话中位于 ExitZone 内，对话结束时 AUTO 模式可能触发。**缓解：** ExitZone 在 `_on_body_entered` 中检查 `body.is_in_group("player")` ——但对话中的玩家仍是 player group。应在 NavigationController 中检查 `_dialogue_active`，如果对话活跃则不触发 fallback。对话中的 ExitZone 过渡应当通过 DialogueManager 的 scene 元数据触发，而不是 ExitZone 自动触发。

2. **Fallback 在对话中触发：** 玩家在对话中场景崩溃/掉落。**缓解：** NavFallback 在触发前检查 `get_node_or_null("/root/StateSystem").is_in_dialogue`。如果是对话中，等待对话结束再触发 fallback（或强制关闭对话后触发）。

3. **H 键与 godot_dialogue_manager 的输入冲突：** H 键在对话面板打开时可能被 DialogueManager 拦截。**缓解：** NavigationController 只在 `_dialogue_active == false` 时处理 `navigate_hint` action。

4. **多入口场景中的路线进度计算：** 玩家的路线顺序可能非线性（从 store 回到 street）。路线进度使用 scene_id 在 SCENE_ORDER 中的最大索引，不递减。

5. **玩家在 SceneTitleOverlay 显示期间快速移动：** 标题卡显示 3.0s 期间玩家可以自由移动。**缓解：** 标题卡不阻塞输入，仅覆盖视觉。玩家可以立即探索新场景。

6. **首次进入 vs 返回场景的标题卡显示：** 玩家从 street 返回 office 时，SceneTitleOverlay 仍然显示"办公室 / The door waits." ——不应该显示两次。**缓解：** 降低返回场景的信息层级（仅显示场景名，不显示路线提示），或根据 `GameManager.scene_visited` 判断是否跳过。

7. **三条路线在 subway_station 的路线进度：** 不同路线的场景序列长度不同（Keep Walking 7 个场景，Turn Back 5 个，Stay 7 个）。路线进度应基于当前路线的场景序列，而非全局 SCENE_ORDER。

### Failure Paths

1. **NavigationController 脚本加载失败：** `load("res://gdscripts/navigation_controller.gd")` 返回 null。**缓解：** `_setup_navigation()` 中 `if not nav_script: push_error("NavigationController script not found"); return`。场景继续正常加载，仅导航功能缺失。

2. **Fallback 循环超过 3 次：** 玩家被连续传送到危险位置。**缓解：** `NavFallback._trigger_fallback()` 检查 `GameManager.fallback_count >= 3` → 强制 `get_tree().change_scene_to_file(Constants.SCENE_TITLE)`。

3. **幻觉等级更新时 NarrativeManager 未加载：** `get_node_or_null("/root/NarrativeManager")` 返回 null（测试环境）。**缓解：** `_update_hallucination_on_scene_entry()` 中 if not nm: return。幻觉等级保持默认值。

4. **场景中没有 SpawnPoint 但 fallback 触发：** `_get_player_spawn_position()` 返回 Vector3.ZERO。玩家被传送到原点。**缓解：** NavFallback 在传送前检查 `spawn_point != Vector3.ZERO`。如果为零，使用场景的 `player.global_position` 微调（向上 0.5m）而不移动。

5. **SceneTitleOverlay 在快速过渡场景（<3s 间隔）中重叠：** 玩家快速从一个 ExitZone 走入另一个——第一个标题卡还没消失，第二个开始显示。**缓解：** SceneManager 在 `_show_title_overlay()` 中先移除已存在的 SceneTitleOverlay（通过 `$SceneTitleOverlay.queue_free()`），再创建新的。

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|:----:|
| `ExitZone.gd` — Area3D 区域检测，AUTO/EKEY 模式 | ✅ **BUILT** | Low |
| `SceneManager.gd` — Fade 管道，trigger_zone_transition, _show_title_overlay | ✅ **BUILT** | Low |
| `SceneBase.gd` — _instantiate_player, tone helpers, dialogue state | ✅ **BUILT** | Low |
| `SceneTitleOverlay.gd` — 场景标题卡 | ✅ **BUILT** | Low |
| `GameManager.gd` — navigation_context, fallback_count, target_spawn_point | ✅ **BUILT** | Low |
| `Constants.gd` — NAV_* 常量 | ✅ **BUILT** | Low |
| `NarrativeManager.gd` — SCENE_ORDER, get_hallucination_level, hallucination_level_changed | ✅ **BUILT** | Low |
| `PlayerController.gd` — WASD 移动, velocity 属性 | ✅ **BUILT** | Low |
| Input action "navigate_hint" | ✅ **BUILT** (InputMap) | Low |
| Issue #221 — 场景导航机制设计 (Approach C) | ✅ **MERGED** | None |
| Issue #156 — ExitZone 过渡系统 | ✅ **MERGED** | None |
| Issue #214 — 叙事架构（幻觉映射、路线） | ✅ **MERGED** | None |
| 所有 8 个场景 `.tscn` 文件 | ✅ **EXIST** | Low |
| 各场景 ExitZone 放置（DESIGN #221 已定义位置） | ❌ **NOT PLACED** | **Medium** — 需要在场景 .tscn 中添加 ExitZone 节点 |

### Blocks

| Future Work | Priority |
|-------------|:--------:|
| NavigationController 实现（计时器、H键路由、fallback 信号） | **P0（MVP 必需）** |
| NavFallback 实现（检测、重定位、计数） | **P0（MVP 必需）** |
| SceneBase._setup_navigation() 集成 | **P0（MVP 必需）** |
| SceneBase 幻觉等级 + 路线进度更新 | **P0（MVP 必需）** |
| 8 场景 ExitZone 放置 | **P1（MVP 推荐）** |
| 8 场景环境引导配置（光、文本、NPC） | **P1（MVP 推荐）** |
| 对话状态保持验证 + 修复 | **P1（MVP 推荐）** |
| 条件触发文本（Stay>60s, WrongDir>30s） | **P2（后续迭代）** |
| 路线感知导航文本（per-tone 提示表） | **P2（后续迭代）** |
| 路线进度 UI 视觉增强（进度条/缩略图） | **P3（后续，非 MVP）** |

### Dependencies Chain

```
#214 叙事架构（幻觉映射、3 路线、三层表达）
  → #156 ExitZone 过渡系统（AUTO/EKEY、spawn_point、fade 管道）
    → #221 导航机制设计（Approach C 混合模式、条件触发、标题卡）
      → #226 导航系统实现 ← YOU ARE HERE
        ├── NavigationController + NavFallback（新建组件）
        ├── SceneBase 集成 + 幻觉更新（修改现有组件）
        └── 8 场景引导配置（场景级修改）
          → #158 MVP 集成测试（需要完整导航系统）
```

### Preparation Needed

- [ ] 确认 NavigationController 是添加到 scene root 还是 SceneBase 的子节点（推荐 SceneBase 的子节点，通过 SceneBase._setup_navigation() 管理生命周期）
- [ ] 确认 NavFallback 与 SceneManager.fade_out/fade_in 的协作接口（NavFallback 直接调用 SceneManager 的 fade 方法，或通过 GameManager 状态同步）
- [ ] 确认 `PlayerController.velocity` 在头模式下可读（CharacterBody3D 的 velocity 属性）
- [ ] 确认 `StateSystem` 是否有 `is_in_dialogue` 方法（用于 NavigationController 检查对话状态）
- [ ] 确认退出 ExitZone 时的 `navigation_context` 清除时机（在 SceneBase._ready() 中读取后清除，防止被后续的对话过渡误读）
- [ ] 定义路线进度的显示格式（数字 "2/6" 或进度条 "■ ■ ■ □ □ □"）
- [ ] 定义每个场景的回退传送文本（中英文对照，符合 Hemingway 约束）

---

## 7. Spike / Experiment

Skipped per depth/standard label. 导航系统的技术不确定性低——NavigationController 是标准的 Node._physics_process 模式，NavFallback 是 Area3D.body_entered + Timer 模式的扩展，SceneBase 集成是信号连接模式。所有子组件在现有代码中已有对应模式（EKeyTrigger、SceneManager fade、GameManager 状态持久化）。

唯一需要快速验证的是：`PlayerController` 是否在 `physics_process` 中暴露 `velocity` 属性（CharacterBody3D 默认有 `velocity`），以及 `StateSystem` 是否在对话期间标记 `is_in_dialogue`。

---

## 8. Continuation Context

> *本节是向 plan agent 的活跃交接（activeForm handoff）。*
> *它捕捉功能区域的当前状态，使 plan agent 无需重新扫描所有源文件即可接手。*

### 当前状态

《雨夜普罗摩茨》的导航系统目前处于**基础设施就绪但核心组件缺失**的状态：

- **✅ 已实现并合并：** ExitZone（146 行，完整 AUTO/EKEY/navigation_context）、SceneTitleOverlay（156 行，完整动画/中英文名）、SceneManager.trigger_zone_transition（227 行，包括 title overlay 集成）、GameManager 属性和 Constants 常量
- **❌ 待实现：** NavigationController（~200 行）、NavFallback（~80 行）、SceneBase 集成（~30 行）、各场景 ExitZone 放置和环境引导配置
- **❌ 待验证：** 对话状态在 ExitZone 过渡中的保持、幻觉等级更新流程

### 实施代理的关键事实

- **8 场景**（office, lobby, street, convenience_store, bridge, underpass, subway_station），每个继承 SceneBase
- **ExitZone** 脚本已就绪（146 行，`target_scene`, `spawn_point`, `exit_label`, `route_hint`），但**尚未在任意场景中放置**
- **SceneManager** 在每个场景中是子节点，通过 `$SceneManager` 访问
- **SceneTitleOverlay** 已实现（156 行），`_init(p_scene_id, p_route_context)` 构造，`show_title()` / `start_auto_dismiss()` 方法，中英文场景名映射
- **`GameManager.navigation_context`** 在 ExitZone 中设置，在 SceneManager 中读取。当前接口：`{exit_label, route_hint, next_scene_id}`
- **`GameManager.fallback_count`** 属性已声明，但未在回退逻辑中使用
- **Constants**（`gdscripts/constants.gd` 第 202-218 行）已定义 10 个 NAV_* 常量
- **Input action** `"navigate_hint"` 已在 InputMap 注册（`project.godot`）
- **NarrativeManager** 有 `hallucination_level_changed` 信号和 `get_hallucination_level()` 静态方法
- **PlayerController** 通过 CharacterBody3D 继承 `velocity`，可通过 `_player.velocity` 读取

### 核心架构决策（Approach A）

1. **NavigationController** — 独立 Node，每个场景在 SceneBase._ready() 中创建。管理条件计时器、H 键路由、fallback 检测。不操作 SceneManager 或 GameManager 直接——通过信号与 SceneBase 通信。
2. **NavFallback** — 独立 Node，与 NavigationController 同级或在其下。监听 fallback trigger → 调用 SceneManager fade → 传送玩家 → SceneManager fade in。
3. **SceneBase 集成** — `_setup_navigation()`（~15 行）+ 2 个 virtual 方法（`_show_navigation_hint`, `_on_condition_text_updated`）
4. **幻觉等级更新** — `_update_hallucination_on_scene_entry()` 在 SceneBase._ready() 中调用，通过 NarrativeManager 计算并更新。
5. **路线进度** — `_update_route_progress()` 在 SceneBase._ready() 中调用，存入 GameManager.route_progress（新增属性）。
6. **对话状态保持** — 现有 `_persist_dialogue_state()` / `_restore_dialogue_state()` 已验证在 ExitZone 过渡中工作。

### 主风险

1. **ExitZone 尚未在任意场景中放置** — 即使 NavigationController 和 NavFallback 实现完成，没有 ExitZone 放置，导航系统无法运行。这是最大的 block 点。
2. **对话状态在 ExitZone 过渡中的保持** — `SceneManager._persist_dialogue_state()` 在 `trigger_zone_transition()` 中调用，但 ExitZone 过渡可能在对话关闭后触发（AUTO 模式），此时 dialogue_state 可能已被清除。需验证时序。
3. **NavFallback 与 SceneManager fade 管道的协作** — NavFallback 需要调用 `SceneManager.fade_out()` 和 `fade_in()`，但 SceneManager 可能处于 `transition_in_progress = true` 状态。需要确保 NavFallback 在过渡完成后再操作。
4. **H 键与 DialogueManager 输入冲突** — 如果 godot_dialogue_manager 3.10.5 在对话期间拦截所有键盘输入，`navigate_hint` action 可能需要特殊处理。

### 实施顺序

| 阶段 | 优先级 | 组件 | 估计 |
|:----:|:------:|------|:----:|
| Phase 1 | **P0** | NavigationController + NavFallback + SceneBase 集成 + 幻觉/路线进度更新 | 2 天 |
| Phase 2 | **P1** | 8 场景 ExitZone 放置 + 环境引导配置 | 1.5 天 |
| Phase 3 | **P1** | 对话状态保持验证 + 修复 | 0.5 天 |
| Phase 4 | **P2** | 条件触发文本（Stay>60s, WrongDir>30s）+ H 键提示文本 | 1.5 天 |
| Phase 5 | **P2** | 路线感知导航文本差异化 | 1 天 |

**总估计:** ~6.5 天（P0+P1: ~4 天, P2: ~2.5 天）

### 新文件清单

| File | Est. Lines | Description |
|------|:----------:|-------------|
| `gdscripts/navigation_controller.gd` | ~200 | 每个场景的导航编排器：条件计时器、H 键路由、fallback 检测 |
| `gdscripts/nav_fallback.gd` | ~80 | 卡住/掉落检测、传送、回退循环保护 |

### 修改文件清单

| File | Change | Est. Lines Added |
|------|--------|:----------------:|
| `gdscripts/scene_base.gd` | _setup_navigation(), _update_hallucination_on_scene_entry(), _update_route_progress(), 2 virtual methods | ~40 |
| `gdscripts/player_controller.gd` | navigate_hint input, navigation_hint_requested signal | ~10 |
| `gdscripts/game_manager.gd` | route_progress, route_progress_text, last_scene_id 属性 | ~5 |
| `gdscripts/narrative_manager.gd` | set_hallucination_level() 公共方法 | ~5 |
| 8 场景 `.gd` 文件 | 环境引导配置（光源、文本、NPC姿态） | ~20 每场景 |
| 8 场景 `.tscn` 文件 | ExitZone 节点放置 / 光照调整 | ~5 每场景 |

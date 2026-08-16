# DESIGN: [Bug] title 界面错误混杂了正式游戏画面

> **Parent Issue:** #508
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** A — FSM 状态驱动 + `game_world` group 组寻址（确认 PRD §4 推荐方案；light 修复，无方案分歧）
> **Reference PRD:** docs/PRD/508-title-screen-world-bleed.md（research PR #509，已合并）
> **所有权:** `content_ownership: mechanical`（MENU 状态隐藏游戏世界 = 确定性可见性状态修复，无品味决策）
> **深度:** light（Issue body「工作深度: light（简单修复，快速完成）」）—— 文件域 2（Main.tscn / game_state_machine.gd）+ 1 测试文件描述，无新文件、无迁移、无弃用 → **不产 TASKS 文档**（低于阈值）

---

## 1. 架构概述

### 1.1 设计核心

**FSM 新增 `_set_world_visible(visible: bool)`，经 `get_tree().call_group("game_world", "set", "visible", visible)` 切换游戏世界可见性；Main.tscn 给 5 个世界节点/层打 `groups=["game_world"]`。MENU 进入即隐藏世界，离开 MENU 恢复可见；PAUSED / GAME_OVER 保持可见（与 PRD §4 范围红线严格对齐：仅 title 屏隐藏）。**

```
Main.tscn (单场景常驻, #393 组装)
├── AtmosphereLayer  (CanvasLayer, layer=0)  ── groups=["game_world"]  ← 整层隐藏覆盖 BgPulse + RainCurtain
│   ├── BgPulse      (ColorRect, #449 呼吸层)
│   └── RainCurtain  (CanvasLayer 实例, 雨幕)
├── Ball             (Area2D 实例)            ── groups=["game_world"]
├── PlayerPaddle     (Area2D 实例)            ── groups=["game_world"]
├── AIPaddle         (Area2D 实例)            ── groups=["game_world"]
├── BreakoutGrid     (Node2D 实例)            ── groups=["game_world"]
├── WaveController   (group "wave_controllers" 先例, #388/#393)   ← 不入组（无视觉渲染）
├── GameStateMachine ── 新增 _set_world_visible(); MENU 分支隐藏 / exit_state(MENU) 恢复
└── StartMenu / GameHUD / GameOverScreen / PauseOverlay  (CanvasLayer, FSM._set_ui 既有控制)

FSM.enter_state(MENU)   → _set_world_visible(false)  → 世界隐藏, 仅 StartMenu + 干净背景
FSM.exit_state(MENU)    → _set_world_visible(true)   → 世界恢复 (MENU→SERVING 过渡)
```

设计哲学：
1. **职责归 FSM（#294）** — FSM 已是全部运行时状态/UI 可见性的唯一编排者；游戏世界可见性是缺失的状态维度，补在 FSM 最内聚，不新增独立管理器
2. **组寻址免维护** — `call_group` 替代 @onready 引用列表（方案 C 的漏节点复发形态）；与 `_start_first_wave()`（wave_controllers）及 wave_controller.gd:28 `add_to_group` 先例一致；新增世界节点入组即自动纳入
3. **CanvasLayer 整层隐藏语义干净** — AtmosphereLayer 是 CanvasLayer（layer=0），子节点 BgPulse + RainCurtain 随层整体隐藏，避免逐个 ColorRect 处理
4. **headless 安全（AC4）** — mini-tree 测试无 "game_world" 组 → `call_group` no-op 不崩溃；`get_tree()` 空指针守卫同 `_start_first_wave` 模式
5. **最小变更（light）** — 仅 Main.tscn 加 5 处 `groups` 属性 + FSM 一个方法两处调用，0.5 天工作量，无场景重排（方案 B 的回归面风险不引入）

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main @ 29bf689） | 设计裁决 |
|---------|--------------------------|---------|
| FSM `_set_ui()` 只切 4 个 UI CanvasLayer.visible，从未隐藏游戏世界 | ✅ game_state_machine.gd:186-192 `_set_ui(layer)` 仅操作 start_menu/game_hud/game_over_screen/pause_overlay | 新增独立 `_set_world_visible()`，与 `_set_ui()` 并列，不改动既有 UI 切换 |
| Main.tscn Ball/Paddle/BreakoutGrid/AtmosphereLayer 无 visible=false | ✅ Main.tscn:33/57/60/63/67 各节点行无 visible 属性；无 group 属性 | 节点行追加 `groups=["game_world"]`（tscn 组语法先例：LeftWall/RightWall `groups=["walls"]` Main.tscn:45/51） |
| AtmosphereLayer 为 CanvasLayer（layer=0），子节点 BgPulse/RainCurtain 可随层整体隐藏 | ✅ Main.tscn:33 `[node name="AtmosphereLayer" type="CanvasLayer" parent="."]` layer=0，BgPulse(ColorRect)+RainCurtain 为其子节点 | CanvasLayer.visible=false 隐藏整层，单点覆盖两个视觉元素 |
| wave_controller.gd 有 group 寻址先例 | ✅ wave_controller.gd:28 `add_to_group("wave_controllers")`；FSM `_start_first_wave()` 用 `get_first_node_in_group` | 同一模式：`call_group("game_world", "set", "visible", v)` |
| headless 测试大量使用 mini-tree（无 Main.tscn 全树） | ✅ test_integration_fsm.gd 为 RefCounted 脚本直接驱动，无 Main.tscn 节点 | `call_group` 对不存在的组 no-op；`get_tree()` null 守卫 → 零影响 |
| FSM `_ready()` 已有 `_validate_references()` 校验 @onready | ✅ game_state_machine.gd:244 `_validate_references()` push_warning 不崩溃 | 组非空校验沿用同一「警告不崩溃」风格（§5.3-1 失败路径缓解） |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立裁决）

**裁决 1（恢复可见性时机）：隐藏放 `enter_state(MENU)`，恢复放 `exit_state(MENU)`。** PRD §8 给出两个可选实现（MENU 分支隐藏 + exit_state(MENU) 恢复，或各分支显式调用）。定案：`enter_state(MENU)` 隐藏 + `exit_state(MENU)` 恢复 —— 恰好 2 处调用点覆盖全部 4 条路径（启动进入 MENU、GAME_OVER→MENU、MENU→SERVING、任意状态回 MENU），且 MENU 是唯一隐藏状态，恢复语义天然收敛。SERVING 分支不显式调用（避免与 exit_state 重复；exit_state 同步执行于 transition_to 内，早于 SERVING 的 1s 发球计时，无黑屏窗口）。

**裁决 2（组非空校验位置）：`_ready()` 内新增校验，空组 push_warning。** PRD §5.3-1：group 名拼写错误 → call_group 静默 no-op → 世界不隐藏（回归原 bug）。校验放 `_ready()` 末尾（`_validate_references()` 之后），`get_tree().get_nodes_in_group("game_world").is_empty()` 时 `push_warning("FSM: group 'game_world' is empty — title screen world hiding disabled")`。headless mini-tree 上下文必然空组 → 必然 warning，但按既有约定 warning 不崩溃、不影响测试结果（test_integration_fsm.gd 等 RefCounted 脚本无 FSM 实例，实际不触发）。

**裁决 3（PAUSED / GAME_OVER 保持可见）：不隐藏。** PRD §4 范围红线：仅 MENU 隐藏；GAME_OVER 保留残局展示（#391 已冻结球）、PAUSED 保留世界供半透明遮罩叠层。实现上天然成立 —— 本设计只在 MENU enter/exit 调用 `_set_world_visible`，其余状态不动。

**裁决 4（ScoreZone/LeftWall/RightWall/WaveController 不入组）：** 纯物理/碰撞节点无视觉渲染（PRD §1.1 表格已确认），入组徒增噪音；组契约只需覆盖「有视觉的世界元素」。

---

## 2. 新组件

无新文件。可见性状态机全部内聚于既有 `game_state_machine.gd`；不新建脚本/场景/常量文件/资源。

| 文件 | 说明 |
|------|------|
| （无） | light 修复，PRD §3.2 确认无新文件 |

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 理由 |
|------|------|------|
| `mini-pong/scenes/Main.tscn` | 5 处节点行追加 `groups=["game_world"]` | 组寻址目标注册（AtmosphereLayer 整层隐藏覆盖 BgPulse+RainCurtain） |
| `mini-pong/gdscripts/game_state_machine.gd` | 新增 `_set_world_visible(visible: bool)`；`enter_state(MENU)` 调用 false；`exit_state` 新增 MENU 分支调用 true；`_ready()` 组非空校验 | FSM 补全世界可见性状态维度（#294 职责） |

**Main.tscn 精确 diff（按行）：**

```
33: [node name="AtmosphereLayer" type="CanvasLayer" parent="." groups=["game_world"]]
57: [node name="Ball" parent="." instance=ExtResource("1_ball") groups=["game_world"]]
60: [node name="PlayerPaddle" parent="." instance=ExtResource("2_player_paddle") groups=["game_world"]]
63: [node name="AIPaddle" parent="." instance=ExtResource("2_player_paddle") groups=["game_world"]]
67: [node name="BreakoutGrid" parent="." instance=ExtResource("13_breakout_grid") groups=["game_world"]]
```

（组属性语法先例：`[node name="LeftWall" type="StaticBody2D" parent="." groups=["walls"]]` Main.tscn:45）

**game_state_machine.gd 新增/修改方法（伪代码）：**

```gdscript
# ── 新增 Helper（置于 _set_ui 之后）──
## #508: MENU 状态隐藏游戏世界（game_world 组）。call_group 对缺失组 no-op，
## mini-tree/headless 测试安全（与 _start_first_wave 的 group 寻址模式一致）。
func _set_world_visible(visible: bool) -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree == null:
		return
	tree.call_group("game_world", "set", "visible", visible)

# ── _ready() 末尾新增校验（_validate_references() 之后）──
	# #508 失败路径缓解（PRD §5.3-1）: 组空 → push_warning, 不崩溃
	var tree := get_tree() if is_inside_tree() else null
	if tree != null and tree.get_nodes_in_group("game_world").is_empty():
		push_warning("FSM: group 'game_world' is empty — title world hiding disabled (#508)")

# ── enter_state(State.MENU) 分支追加 ──
		State.MENU:
			_set_ui("start_menu")
			_freeze_paddles(true)
			_transition_lock = false
			_set_world_visible(false)          # #508: MENU 隐藏游戏世界

# ── exit_state() 新增 MENU 分支 ──
func exit_state(state: State) -> void:
	match state:
		State.SCORED:
			_scored_timer_active = false
		State.GAME_OVER:                # #391 AC4
			_freeze_ball(false)
		State.MENU:                     # #508: 离开 MENU 恢复世界可见（MENU→SERVING）
			_set_world_visible(true)
		_:
			pass
```

### 3.2 受影响测试文件（只列描述，不写代码）

| 测试文件 | 变更性质 |
|---------|---------|
| `mini-pong/tests/test_integration_fsm.gd` | 新增/追加 game_world 可见性断言（§9 Scenario A-C；mini-tree 注入带 group 的 mock 节点）—— 实现阶段由 implement agent 写入 |
| 其余 `tests/*.gd` | 零改动 —— headless mini-tree 不加载 Main.tscn 全树，`call_group` no-op（AC4） |

### 3.3 移除/弃用文件

无。

---

## 4. 数据流

### Flow 1: 正常路径 — 启动进入 title（AC1）
```
Main.tscn 实例化 → FSM._ready()
  → _validate_references() 校验通过
  → enter_state(State.MENU)
      ├── _set_ui("start_menu")          → StartMenu 可见
      └── _set_world_visible(false)      → game_world 组: Ball/Paddle×2/BreakoutGrid/AtmosphereLayer visible=false
                                          → BgPulse + RainCurtain 随 AtmosphereLayer 整层隐藏
结果: 仅 PONG://21 标题层 + 干净背景
```

### Flow 2: 正常路径 — SPACE 开始（AC2）
```
_input(ui_accept) → MENU 分支 (无 _transition_lock)
  → _transition_lock = true
  → transition_to(State.SERVING)
      ├── exit_state(MENU) → _set_world_visible(true)   ← 同步恢复, 早于 1s 发球计时
      ├── enter_state(SERVING): _set_ui("hud"), _freeze_paddles(true)
      │     └── GameManager.reset_match()（仅 previous==MENU）
      └── await _timer_1s() → ball.serve() → PLAYING
结果: 球/球拍/雨幕/背景脉冲可见, 对局正常
```

### Flow 3: 对局结束返回 title（AC3）
```
ScoringManager.scored → 21 分 → is_run_over → transition_to(GAME_OVER)
  ├── exit_state(SCORED): _scored_timer_active=false
  ├── enter_state(GAME_OVER): _set_ui("game_over"), _freeze_ball(true)   ← 世界保持可见（残局展示）
  └── SPACE 按任意键 → GAME_OVER 分支 → transition_to(MENU)
      ├── exit_state(GAME_OVER): _freeze_ball(false)
      └── enter_state(MENU): _set_world_visible(false)   ← 世界再次隐藏（同步, 无中间帧闪烁）
```

### Flow 4: 暂停（边界 — 世界保持可见）
```
PLAYING → Escape → transition_to(PAUSED)
  ├── _set_ui("pause"), pause_overlay.show_overlay()     ← 半透明遮罩叠于世界之上
  └── _set_world_visible 不调用 → 世界可见 ✅（PRD §5.2-1）
```

### Flow 5: headless / mini-tree（AC4）
```
test_integration_fsm.gd (RefCounted, 无 Main.tscn)
  → FSM 不实例化 / 或 mini-tree 无 game_world 组
  → call_group("game_world", ...) → no-op（Godot 组寻址语义）
  → 不崩溃, 测试照常
```

---

## 5. 边界情况与错误处理

| Edge Case | 缓解 |
|-----------|------|
| PAUSED（Escape） | 世界保持可见——暂停遮罩半透明叠于世界之上（PRD §5.2-1；设计仅 MENU 调用隐藏，天然满足） |
| GAME_OVER | 世界保持可见——终局画面含残局状态（#391 已冻结球）（PRD §5.2-2） |
| MENU → SERVING 过渡 | `exit_state(MENU)` 同步恢复可见，早于 1s 发球计时，无黑屏窗口（PRD §5.2-3） |
| headless / mini-tree 无 game_world 组 | `call_group` no-op 不崩溃；`get_tree()` null 守卫（PRD §5.2-4，裁决 2） |
| group 名拼写错误 → 静默 no-op 回归原 bug | `_ready()` 组非空校验 + push_warning（PRD §5.3-1，裁决 2） |
| 未来新增世界节点忘加 group → title 屏再次泄漏 | 组契约写入 GDD（review agent 在 implement merge 后更新 docs/GAME_DESIGN/）+ 组装类 PRD 模板（PRD §5.2-6 / §8 风险） |
| GAME_OVER → MENU 过渡（_transition_lock 已释放） | `enter_state(MENU)` 同步隐藏，无中间帧闪烁（PRD §5.2-7） |
| 启动即 MENU（_ready → enter_state(MENU)） | 首帧世界即隐藏，无「先显示后隐藏」闪烁 |
| FSM 未挂载（mini-tree 场景） | `_set_world_visible` 仅存在于 FSM 内部，无外部调用者；不存在悬空引用 |

---

## 6. 按场景/组件配置

| 场景 | 节点 | 入组 | 隐藏效果 |
|:-----:|------|:---:|---------|
| Main.tscn | AtmosphereLayer (CanvasLayer, layer=0) | `game_world` | 整层隐藏 → BgPulse + RainCurtain 一并不可见 |
| Main.tscn | Ball | `game_world` | 不可见 |
| Main.tscn | PlayerPaddle | `game_world` | 不可见 |
| Main.tscn | AIPaddle | `game_world` | 不可见 |
| Main.tscn | BreakoutGrid | `game_world` | 不可见（MENU 下本就无砖，防未来首波泄漏） |
| Main.tscn | LeftWall/RightWall/ScoreZone/ScoreFlash/WaveController | 不入组 | 纯物理/自隐藏节点，无视觉泄漏 |

---

## 7. 集成点

| Integration | 我们的组件 | 目标 | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| FSM ↔ 游戏世界 | `_set_world_visible()` | #508 | `call_group("game_world", "set", "visible", v)` | ⬜ pending（implement 接线） |
| Main.tscn ↔ game_world 组 | 5 节点 `groups` 属性 | #508 | tscn 组属性注册 | ⬜ pending |
| GDD 约定 | 「MENU 状态隐藏 game_world 组」 | docs/GAME_DESIGN/ | review agent 在 implement merge 后更新（本 plan 阶段不写 GDD） | ⬜ deferred |

> 状态约定：⬜ = pending（implement agent 接线并更新）；deferred = 明确延后到 implement merge 后由 review agent 执行。

---

## 8. 实现阶段

light 修复，单阶段即可，无需分阶段交付：

| Phase | 内容 | 依赖 |
|:-----:|------|------|
| Phase 1（P0） | Main.tscn 5 处 `groups=["game_world"]` + FSM `_set_world_visible()`/enter/exit/校验 | 无（FSM #294 与组装 #393 均已合入 main） |

---

## 9. 测试用例描述（实现阶段据此编写，不在此写可运行测试）

> 约定：测试驱动采用 mini-tree 注入 mock 节点（带 `groups=["game_world"]`）到 `test_integration_fsm.gd` 或新建 `test_world_visibility.gd`（由 implement agent 定）；断言点全部走 `Node.visible` 属性。Group 缺失上下文下 `call_group` no-op 为既有语义，测试天然覆盖。

### Scenario A: MENU 状态世界隐藏（AC1）
- **Test A1（启动隐藏）**：构造 FSM mini-tree（含带 `game_world` 组的 mock 节点 ball/paddle/atmosphere），调用 `_ready()` 进入 MENU。预期：全部 mock 节点 `visible == false`。
- **Test A2（GAME_OVER → MENU 再隐藏，AC3）**：FSM 置 GAME_OVER → 触发 `transition_to(MENU)`。预期：mock 节点 `visible == false`；且无中间帧闪烁（同步调用，可用 process_frame 单帧断言）。
- **Test A3（组缺失不崩溃）**：FSM mini-tree 不含任何 `game_world` 节点，进入 MENU。预期：无异常抛出，`_ready()` 正常完成（可断言无 push_error；push_warning 允许）。

### Scenario B: 离开 MENU 世界恢复（AC2）
- **Test B1（MENU → SERVING）**：FSM 在 MENU，注入 `ui_accept` 事件。预期：`exit_state(MENU)` 同步将 mock 节点 `visible` 置回 true（在 SERVING 1s 计时前断言）。
- **Test B2（PLAYING 保持可见）**：FSM 到 PLAYING。预期：mock 节点 `visible == true`，且对局逻辑不受影响。

### Scenario C: PAUSED / GAME_OVER 保持可见（PRD §5.2-1/2 边界）
- **Test C1（PAUSED）**：PLAYING → Escape → PAUSED。预期：mock 节点 `visible == true`（暂停遮罩叠于世界之上）。
- **Test C2（GAME_OVER）**：触发 21 分终局 → GAME_OVER。预期：mock 节点 `visible == true`（残局展示，#391 冻结球）。

### Scenario D: `_set_world_visible` 幂等与守卫
- **Test D1（重复调用）**：连续两次 `_set_world_visible(false)`。预期：无异常，节点保持隐藏（call_group 幂等）。
- **Test D2（组空校验警告）**：FSM `_ready()` 于无组上下文。预期：产生 push_warning（可用 `push_warning` 捕获或日志断言），不崩溃。

### Scenario E: 既有测试不回归（AC4）
- **Test E1**：完整 headless 测试套件（`godot --headless` + run_tests.gd）全绿 —— FSM 集成测试（test_integration_fsm.gd）、paddle/scoring/wave/upgrade 等全部既有测试零失败。
- **Test E2**：`--check-only` 编译通过（L0 gate），Main.tscn 场景可正常加载（tscn 组属性语法合法）。

---

## 10. 延续上下文（implement agent 交接）

**系统状态**：main @ 29bf689（PRD #508 已合入）。Main.tscn 单场景常驻；FSM #294 已接管 UI 层可见性；`game_world` 组尚不存在（全部世界节点无组）。

**实现要点**：
1. `Main.tscn` 5 处节点行加 `groups=["game_world"]`（精确行号见 §3.1；AtmosphereLayer 必须入组——整层隐藏是覆盖 BgPulse+RainCurtain 的唯一单点手段）
2. `game_state_machine.gd`：`_set_world_visible(visible)`（`get_tree()` null 守卫 + `call_group`）；`enter_state(MENU)` 调 false；`exit_state` 新增 `State.MENU` 分支调 true；`_ready()` 组非空校验 push_warning
3. 测试：§9 Scenario A-E 用例描述落地到 FSM 集成测试（mini-tree 注入 group mock 节点）；既有测试保持全绿
4. 不做：PAUSED/GAME_OVER 不隐藏世界；不新建场景/脚本；不改其他状态分支

**风险**：新增世界节点忘加 group → title 屏再次泄漏。对策：GDD 组契约由 review agent 在 implement merge 后写入 docs/GAME_DESIGN/；组装类 PRD 模板已列（PRD §8）。

**参考文件**：`mini-pong/scenes/Main.tscn`（节点行 33/57/60/63/67；groups 语法先例 45/51）、`mini-pong/gdscripts/game_state_machine.gd`（enter_state:44-157 / exit_state:159-171 / _set_ui:186-192 / _start_first_wave:227-238 / _ready:24-44）、`mini-pong/gdscripts/wave_controller.gd:28`（group 先例）、`docs/DESIGN/294-game-state-machine.md`、`docs/DESIGN/292-ui-system.md`

# Design: ESC 暂停菜单 + 游戏操作手册（移动/攻击/格挡/闪避/处决说明）

> **Parent Issue:** #719（feature / workflow/plan / priority/high / ui / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A2 确认采纳** —— `get_tree().paused = true` 树暂停全局冻结 + 新建 `pause_menu.gd`（CanvasLayer layer=2，`process_mode = PROCESS_MODE_ALWAYS`）自检 ESC（A2，InputController 保持 INHERIT 零改动）。方案 A1（InputController 加 `pause_pressed` 信号 + 自身 ALWAYS）否决理由同 PRD §4（暂停中仍轮询边沿 → 战斗信号泄漏，需暂停抑制开关）；方案 B（局部冻结）否决理由同 PRD §4（冻结面人肉枚举，AC4 全覆盖难证明）；方案 C（`Engine.time_scale=0`）否决理由同 PRD §4（与 #579 TimeScaleStack 互踩，`_process` 仍每帧调用）。
> **Reference PRD:** `docs/PRD/719-esc-pause-menu.md`（research PR #721 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/576-hud-stance-bars.md`（HUD CanvasLayer 纯代码体系 + `HUD_*` 色板 + 零贴图零 tscn 惯例）；`docs/DESIGN/585-mvp-combat-loop-assembly.md` §2.1（main_battle.gd 13 步同步装配，`_build_hud()` 同构先例）；`docs/DESIGN/684-boss-hp-bar-ui.md`（HUD 增量程序化 UI 模式）；`docs/DESIGN/573-input-map-player-controller.md`（InputController 输入意图层 + 输入缓冲语义）；`docs/DESIGN/580-execution-system.md`（手册「处决」条目文案来源）
> **所有权:** `content_ownership: mechanical`（暂停 toggle 状态机 / ESC 边沿检测 / 菜单节点结构与按钮接线 / 手册文本 InputMap 自动生成 = 机械工程，可自动验证；菜单标题文案、手册措辞、遮罩色值与透明度候选 = taste 通道，全部标 `# DRAFT` 只读，定稿归 human-review 通道——实现期禁止裁决）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 **5**（2 修改：`project.godot` + `constants.gd`；1 修改：`main_battle.gd`；2 新建：`pause_menu.gd` + `test_pause_menu.gd`）+ E2E 2 文件（`e2e_pause_capture.gd` + `e2e_shots.json` 追加）→ **不产出 TASKS 文档**（skill standard 阈值未触发：文件 <10、无迁移、子任务 <5 且不跨子系统，照 #704/#713 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-719，branch `plan/719-esc-pause-menu`）；**并行 issue 冲突面**（2026-08-21 核验）：#718（stagger→stance_break，workflow/plan）、#720（战斗交互霸体/击退，workflow/plan）与 #719 并行推进——#718/#720 同触 `combat_judge.gd`/`combat_state_table.gd`（本设计零触碰）、#720 或触 `main_battle.gd`（本设计第 ⑮ 步新增装配为 additive 追加，冲突面小；提交前 worktree-commit.sh 自动 merge main + 冲突分级）；`constants.gd` 分区新增 `PAUSE_*` 块（独立命名空间，无既有常量冲突）；`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`、`game-env/manifest.yaml` 零影响
> **红线:** 只动 PRD §3.1/§3.2 列出的文件；**InputController 零改动**（A2 红线：不新增信号、不改 process_mode、不新增方法——缓冲清理走既有公共 API `poll_buffer()`/`buffer_size()` 循环，见 §3.4）；`constants.gd` 新增 `PAUSE_*` 全标 `# DRAFT` 只读；恢复路径唯一入口 `toggle_pause(false)`（禁止散点 `paused=false` 直写）；**不写可运行测试文件**（测试用例描述归本 DESIGN §8，测试代码归 implement agent）；PR body 用 `Parent #719`（不带冒号）

---

## 1. 架构总览

**一句话设计：ESC 是系统级输入，暂停是树级状态——新增一个常驻的 `PauseMenu`（CanvasLayer, ALWAYS）作为唯一暂停持有者，自检 ESC 边沿，翻转 `get_tree().paused`，并承载菜单 UI + 运行时从 InputMap 生成的操作手册。** 战斗侧（InputController / CombatEntity / EnemyAI / Atmosphere / HUD）全部保持 INHERIT 默认——`paused=true` 一帧冻结全部，零组件改动，天然满足 AC4。

```text
物理 ESC 键（4194305，新增 game_pause 动作）
    │  Input.is_action_just_pressed("game_pause")   ← PauseMenu._process（ALWAYS 常驻，战斗冻结时仍响应）
    ▼
PauseMenu.toggle_pause()  ── 唯一暂停/恢复入口（幂等，FAIL 守卫在内）
    ├── 暂停分支: get_tree().paused = true
    │     ├── 全部 INHERIT 节点冻结: 战斗 _process/_physics_process、Tween/Timer、
    │     │   GPUParticles3D 雪幕、InputController 边沿轮询、HUD 信号链 —— AC4「全部冻结」✓
    │     └── 菜单层（ALWAYS）弹出: 遮罩 ColorRect + 标题 + 「继续」「操作手册」Button
    ├── 恢复分支: get_tree().paused = false + 菜单隐藏 + 缓冲清理（§3.4）
    └── FAIL 守卫: bind_game_state 注入的 game_state == FAIL → 忽略 ESC（幂等，不弹菜单）
                    （双保险: main_battle FAIL 路径已 set_process(false) 冻结 InputController）
操作手册（「操作手册」按钮 → 面板 visible 翻转）
    ├── 动态条目: 遍历 InputMap 全部 game_* 动作 → action_get_events() → 键名（AC3 机器保证）
    └── 静态条目: 处决说明（#580 语义文案，非 InputMap 动作，# DRAFT 措辞）
```

**设计哲学（对齐 PRD §4 三处关键决策）：**
1. **暂停 = 树状态而非组件状态** —— Godot 标准语义，冻结面一次覆盖物理/动画/Tween/Timer/粒子，AC4 无需人肉枚举；代价是「任何 ALWAYS 节点会漏冻结」——2026-08-21 全仓库 grep 核验：**当前源码无任何显式 `process_mode` 设置**（全部 INHERIT 默认），风险面为零（PRD §7 实验 2 预期结论）。
2. **ESC 检测归 PauseMenu 而非 InputController（A2）** —— InputController 是战斗意图层（#573 红线），加 ESC 会引入「暂停中仍发战斗信号」的泄漏路径（A1 缺陷）；PauseMenu 自检则 InputController 保持 INHERIT，暂停即自然停发，零泄漏、零改动。
3. **手册文本运行时从 InputMap 生成** —— AC3 从「人工核对」升级为「机器保证」，并天然规避既有 `TUTORIAL_HINT_CANDIDATES[1]`（"K 格挡"）与 InputMap（K=重攻击、L=格挡）的矛盾（PRD §1.1 侦查发现）；该教学提示文案修正属 taste 通道，本设计仅 flag 不处理。

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| 输入意图层（`input_controller.gd`，autoload，`_process` 边沿轮询 + 150ms 缓冲） | #573 | ✅ | **零改动**——A2 语义下暂停即自然冻结；缓冲清理走既有公共 API（§3.4） |
| HUD 体系（`hud.gd`，CanvasLayer layer=1，`_HudBar` 自绘，`HUD_*` 色板） | #576/#684 | ✅ | **零改动**——暂停时 INHERIT 冻结信号链，恢复后自动续画；菜单沿用同构模式（色板复用，不新增色相） |
| 装配层（`main_battle.gd` 13 步同步装配 + `_build_hud()` 先例 + `GameState` 枚举 + `_set_game_state` FAIL 终态守卫） | #585 | ✅ | **改**：第 ⑮ 步新增 `_build_pause_menu()`（`_build_hud()` 同构）→ `PauseLayer`(CanvasLayer layer=2, ALWAYS) → PauseMenu + `bind_game_state` |
| 全局常量（`constants.gd`，`HUD_*` 色板 + `FAIL_SUBTITLE_*`/`TUTORIAL_HINT_*` 文案候选先例） | #584/#585 | ✅ | **改**：新增 `PAUSE_*` 分区（标题/遮罩色值/透明度/字体尺寸/手册措辞候选，全 `# DRAFT`） |
| InputMap（`project.godot [input]`，`game_*` 9 动作，无 ESC） | #573 | ✅ | **改**：新增 `game_pause` = ESC（物理键 4194305）；既有 `game_*` 全不动 |
| 场景（`Main.tscn` CanvasLayer/CenterContainer 标题卡 + `battle_stage.tscn`） | #585/#583 | ✅ | **零改动**——菜单独立新 CanvasLayer，不与标题卡复用 |
| 处决系统（`execution_orchestrator.gd`，崩解后可处决） | #580 | ✅ | **零改动**——手册「处决」条目仅静态文案引用（「崩解后按攻击键」） |
| 时间缩放（#579 TimeScaleStack / Reaction 慢动作，`Engine.time_scale` 持有者） | #579 | ✅ | **零改动**——暂停只动 `get_tree().paused`，不触碰 `time_scale`；恢复后慢动作续跑（§5 边界 5） |
| 既有测试（`tests/test_input_controller.gd` 缓冲语义 / `test_main_assembly.gd` 装配断言 / `test_hud.gd` 静态契约） | #573/#585/#576 | ✅ | **回归验证**——暂停默认 off，零行为变化，全绿预期 |
| E2E shot plan（`e2e_shots.json` + `e2e_hud_capture.gd` 三态模式先例） | #586/#661/#662 | ✅ | **改**：新增 `e2e_pause_capture.gd`（PAUSE_OPEN/MANUAL_OPEN/PAUSE_RESUME 三态）+ `e2e_shots.json` 追加 pause group |

### 1.2 核心缺口与设计决策（codebase 勘探确认）

| PRD 断言 | 实际代码 | 设计决策 |
|---------|---------|------|
| InputMap 绑定：A/D←/→、J/左键、K/右键、L、Shift、空格、E、F | `project.godot [input]` 逐条核验 ✓（game_move_left=65+4194319、game_light_attack=74+鼠标左键 button_index=1、game_heavy_attack=75+右键=2、game_guard=76、game_dash=4194325、game_jump=32、game_interact=69、game_revive=70） | 手册键名以 `InputMap.action_get_events()` 运行时读取为准；键名映射表见 §2.4 |
| `game_pause` 动作不存在 | `project.godot [input]` 无 pause 动作 ✓；`input_controller.gd` `ALL_ACTIONS`/`EDGE_ACTIONS` 不含 ESC ✓ | 新增 `game_pause`=ESC(4194305)（唯一新增动作）；**不加入** InputController 的 `ALL_ACTIONS`（A2 红线：InputController 不认识该动作） |
| 「暂停瞬间 InputController 清空缓冲队列」 | `input_controller.gd` **无清空方法**——仅有 `poll_buffer()`（pop_front）/`peek_buffer()`/`buffer_size()`（均含 `_clear_expired()` 副作用），`_buffer` 私有 | **不新增 `clear_buffer()` 方法**（守 A2「InputController 零改动」红线字面）；恢复路径由 PauseMenu 循环 `while ic.buffer_size() > 0: ic.poll_buffer()` 清空（§3.4 伪代码）——零改动 + 语义等价 |
| `bind_game_state(getter)` 注入 game_state 只读接口 | `main_battle.gd` `game_state: int` 为公共变量（`GameState` 枚举，FAIL=4）；无独立 getter 方法 | `main_battle.gd` 第 ⑮ 步传 Callable：`pause_menu.bind_game_state(func() -> int: return game_state)`——只读闭包注入，不暴露写接口 |
| FAIL 终态按 ESC 不弹菜单（PRD §5.2 边界 2） | `_set_game_state` FAIL 终态守卫存在（不再迁移）；`_on_player_final_death` 已 `InputController.set_process(false)`（输入冻结） | PauseMenu 守卫 `_get_game_state() == FAIL → return`（幂等忽略）；InputController 冻结为双保险 |
| 恢复后输入缓冲不爆键（PRD §5.3 边界 3） | 缓冲窗口 `INPUT_BUFFER_WINDOW_MS=150`，暂停期间 InputController 冻结不清理，物理时间流逝 | 恢复路径统一清空（§3.4）；清空后战斗意图零残留（测试 T9 断言） |
| 手册条目「处决：崩解后触发——#580」 | `execution_orchestrator.gd` 处决触发 = 架势崩解后攻击键（无独立 InputMap 动作） | 手册 = 动态 InputMap 条目 + **静态补充行**（处决说明，文案 `# DRAFT` 候选）；结构测试断言动态部分与 InputMap 一致（静态行不参与一致性断言） |

> **与 PRD 的差异说明（1 处落地选择）：** PRD §5.3 失败路径 3 要求「恢复路径唯一入口 `toggle_pause(false)`」——本设计进一步将该入口收敛为**静态单例语义**：`toggle_pause()` 无参翻转（内部按当前 `_paused` 分支），「继续」按钮与再次 ESC 走同一函数同一分支，杜绝两处恢复代码漂移（§2.3）。PRD 其余方案全项采纳。

---

## 2. 新组件 — PauseMenu 详细设计

### 2.1 `gdscripts/pause_menu.gd`（新）

- **文件:** `shandong-wolf/gdscripts/pause_menu.gd`
- **基类:** `CanvasLayer`（`class_name PauseMenu`）——与 Hud 同构（Hud extends CanvasLayer），layer=2（HUD layer=1 之上），`process_mode = PROCESS_MODE_ALWAYS`
- **节点结构（_ready 代码创建，零 tscn 零贴图，Hud 同构）:**

```text
PauseMenu (CanvasLayer, layer=2, process_mode=ALWAYS)      ← 本脚本
├── DimOverlay (ColorRect, 全屏 1280×720, color=C.PAUSE_DIM_COLOR, 初始 visible=false)
├── MenuRoot (VBoxContainer, 居中 anchors, 初始 visible=false)
│   ├── TitleLabel (Label, text=C.PAUSE_TITLE_CANDIDATES[0], 字号 C.PAUSE_TITLE_FONT_SIZE)
│   ├── ResumeButton (Button, text=C.PAUSE_BTN_RESUME_TEXT)
│   ├── ManualButton (Button, text=C.PAUSE_BTN_MANUAL_TEXT)
│   └── HintLabel (Label, text=C.PAUSE_HINT_TEXT)          # 「ESC 恢复」提示，小字号
└── ManualPanel (VBoxContainer + ScrollContainer, 初始 visible=false)   # 操作手册面板
    ├── ManualTitle (Label, text=C.PAUSE_MANUAL_TITLE_TEXT)
    └── ManualLines (VBoxContainer)   # 行 = Label × N，运行时由 manual_text() 填充
```

- **Signals:** 无对外信号（暂停是树级状态，无消费者需要订阅；`game_state_changed` 由 main_battle 广播，PauseMenu 只读不转发）
- **State Properties:**

| 变量 | 类型 | 初始值 | 语义 |
|------|------|--------|------|
| `_paused` | bool | `false` | 当前暂停态（toggle 幂等基准） |
| `_manual_visible` | bool | `false` | 手册面板可见态（ESC 恢复优先关闭） |
| `_game_state_getter` | Callable | `Callable()` | 注入的 game_state 只读闭包（FAIL 守卫） |
| `_input_controller` | Node | null | `/root/InputController` 引用（恢复时清缓冲） |
| `DimOverlay` / `MenuRoot` / `ManualPanel` | Control | null | 公有节点成员（_ready 创建，tests 直接访问，Hud 同构） |
| `ManualLines` | VBoxContainer | null | 手册行容器（tests 遍历断言） |

- **Key Methods:**

```gdscript
func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS      # 战斗冻结时菜单仍响应（AC4）
	if not InputMap.has_action("game_pause"):
		push_error("PauseMenu: missing Input Map action 'game_pause'")   # fail-safe: 禁用菜单不崩溃
		set_process(false)
		return
	_create_nodes()                               # 零 tscn 代码建树（Hud 同构）
	add_to_group("pause_menu")                    # 装配重入幂等守卫（首实例保留）
	_input_controller = get_node_or_null("/root/InputController")

func _process(_delta: float) -> void:
	## A2: PauseMenu 自检 ESC 边沿（ALWAYS 常驻，暂停中仍响应）
	if Input.is_action_just_pressed("game_pause"):
		toggle_pause()

func toggle_pause() -> void:
	## 唯一暂停/恢复入口（幂等 + FAIL 守卫）
	if _game_state_getter.is_valid() and _game_state_getter.call() == GameState.FAIL:
		return                                    # FAIL 终态: 不弹菜单（幂等）
	if _paused:
		_resume()
	else:
		_pause()

func _pause() -> void:
	_paused = true
	get_tree().paused = true                      # 全局冻结（INHERIT 全覆盖）
	DimOverlay.visible = true
	MenuRoot.visible = true

func _resume() -> void:
	_paused = false
	ManualPanel.visible = false                   # 手册随恢复关闭（ESC=恢复优先）
	_manual_visible = false
	DimOverlay.visible = false
	MenuRoot.visible = false
	_clear_input_buffer()                         # 防恢复瞬间「隔空出刀」（§3.4）
	get_tree().paused = false                     # 唯一恢复路径（禁止散点直写）

func _clear_input_buffer() -> void:
	## InputController 零改动方案: 走既有公共 API 循环清空（poll_buffer 内含 _clear_expired）
	if _input_controller == null:
		return
	while _input_controller.buffer_size() > 0:
		_input_controller.poll_buffer()

func manual_text() -> Array:
	## 运行时从 InputMap 生成 [动作, 键名列表] 行（AC3 机器保证）
	## 动态: game_* 动作遍历 action_get_events() → keycode 映射（§2.4 表）
	## 静态: 追加处决说明行（# DRAFT 文案候选, 不参与一致性断言）
	return [...]
```

### 2.2 按钮接线（_create_nodes 内）

```gdscript
ResumeButton.pressed.connect(func() -> void: toggle_pause())      # 「继续」= 同一 toggle 入口
ManualButton.pressed.connect(func() -> void: _toggle_manual())    # 手册面板 visible 翻转
```

- `_toggle_manual()`: `_manual_visible = not _manual_visible; ManualPanel.visible = _manual_visible`——首开时填充 `manual_text()` 行（懒生成，避免每帧重建）
- 手册打开时再按 ESC → 直接恢复并关手册（PRD §5.2 边界 8 取「ESC=恢复优先」语义）

### 2.3 状态机（暂停生命周期）

```text
        ┌────────────────────────────────────────────────┐
        │  ESC(edge) / ResumeButton                        │
        ▼                                                  │
  ┌──────────┐   _pause()   ┌──────────────────────┐   _resume()   ┌──────────┐
  │ RUNNING  │ ───────────► │ PAUSED（战斗全冻结） │ ────────────► │ RUNNING  │
  │ paused=F │              │ 菜单 ALWAYS 响应      │               │ paused=F │
  └──────────┘              └──────────────────────┘               └──────────┘
        ▲                        │  ManualButton                       ▲
        │                        ▼                                     │
        │              ┌──────────────────────┐                        │
        │              │ PAUSED+MANUAL（手册开）│── ESC/继续 ──────────────┘
        │              │ ESC=恢复优先，关面板    │
        │              └──────────────────────┘
        └──── ESC 在 FAIL 态被守卫拦截（幂等忽略，不进入任何分支）────┘
```

**幂等性:** 连按 ESC 交替触发（toggle）；恢复后 1 帧内再按 = 再暂停（正常 toggle，无抖动）；按住 ESC 不重复触发（`is_action_just_pressed` 边沿语义）。

### 2.4 键名映射表（manual_text 内部，`# DRAFT` 展示名候选）

| physical_keycode | 展示名（`# DRAFT`） | 说明 |
|:---:|:---:|------|
| 65 / 68 | A / D | 移动左右 |
| 4194319 / 4194321 | ← / → | 方向键备选 |
| 74 + 鼠标左键 | J / 鼠标左键 | 轻攻击（InputEventMouseButton button_index=1） |
| 75 + 鼠标右键 | K / 鼠标右键 | 重攻击（button_index=2） |
| 76 | L | 格挡/弹反（按住=格挡，时机=弹反） |
| 4194325 | Shift | 闪避（轻按=垫步，按住=冲刺） |
| 32 | 空格 | 跳跃 |
| 69 | E | 互动 |
| 70 | F | 复活（#578 二命） |

> 映射实现建议：`OS.get_keycode_string(keycode)` 为兜底，上表为展示名覆盖（←/→/Shift/空格 等美观名）。结构测试只断言「每条 InputMap 事件都能映射出非空键名」（防映射表漏项），不断言具体展示字符串（taste 域）。

---

## 3. 既有组件修改

### 3.1 `shandong-wolf/project.godot`（InputMap 新增 1 动作）

| 位置 | 变更 | 说明 |
|------|------|------|
| `[input]` 段尾 | 新增 `game_pause={ "deadzone": 0.5, "events": [Object(InputEventKey, ... "physical_keycode":4194305 ...)] }` | ESC 物理键（KEY_ESCAPE=4194305）；既有 9 个 `game_*` 动作零改动 |

> 与 `input_controller.gd` 的 `ALL_ACTIONS` 保持**不联动**（InputController 不认 `game_pause`——A2 红线，避免其边沿轮询暂停动作）。

### 3.2 `shandong-wolf/gdscripts/main_battle.gd`（第 ⑮ 步装配）

| 位置 | 变更 | 伪代码 |
|------|------|--------|
| `_ready()` 末尾（`_sync_visual_facing()` 后） | 新增 `_build_pause_menu()` 调用 | `_build_pause_menu()`（`_build_hud()` 同构） |
| 新方法 `_build_pause_menu()` | 装配 + FAIL 守卫注入 | 见下 |

```gdscript
func _build_pause_menu() -> void:
	## ⑮ 暂停菜单: PauseLayer(CanvasLayer, layer=2, ALWAYS) → PauseMenu + FAIL 守卫注入
	var pause_layer: CanvasLayer = CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	add_child(pause_layer)
	pause_menu = PauseMenuScript.new()
	pause_layer.add_child(pause_menu)
	pause_menu.bind_game_state(func() -> int: return game_state)   # 只读闭包注入（FAIL 守卫）
```

- 新增成员 `var pause_menu = null`（装配产物引用，测试断言用）
- **零组件改动**：不触碰既有 13 步、不注入 InputController、不改 `_set_game_state`

### 3.3 `shandong-wolf/gdscripts/constants.gd`（新增 `PAUSE_*` 分区，全 `# DRAFT`）

| 常量 | 候选值 | 语义 |
|------|--------|------|
| `PAUSE_TITLE_CANDIDATES` | `["暂停", "雪夜村口 · 暂歇", "歇一歇"]`（`# DRAFT`） | 菜单标题（taste 候选，implement 选 1 进 PR） |
| `PAUSE_BTN_RESUME_TEXT` | `"继续"`（`# DRAFT`） | 「继续」按钮文案 |
| `PAUSE_BTN_MANUAL_TEXT` | `"操作手册"`（`# DRAFT`） | 手册按钮文案 |
| `PAUSE_MANUAL_TITLE_TEXT` | `"操作手册"`（`# DRAFT`） | 手册面板标题 |
| `PAUSE_HINT_TEXT` | `"按 ESC 或「继续」恢复"`（`# DRAFT`） | 底部提示 |
| `PAUSE_DIM_COLOR` | `Color(0.08, 0.08, 0.10, 0.6)`（`# DRAFT`） | 遮罩色值+透明度（HUD_INK_BLACK #141414 派生，taste 候选） |
| `PAUSE_TITLE_FONT_SIZE` | `32`（`# DRAFT`） | 标题字号 |
| `PAUSE_BTN_FONT_SIZE` | `22`（`# DRAFT`） | 按钮字号 |
| `PAUSE_MANUAL_FONT_SIZE` | `20`（`# DRAFT`） | 手册行字号 |
| `PAUSE_EXECUTE_LINE_CANDIDATES` | `["处决：架势崩解后按攻击键（J）", "处决：崩解后近身按攻击键"]`（`# DRAFT`） | 静态处决说明行（taste 候选，implement 选 1） |

> 色板收敛：仅从既有 `HUD_MOON_WHITE`/`HUD_INK_BLACK`/`HUD_BLOOD_RED` 派生，不新增色相（#576 色板收敛红线）。

### 3.4 InputController — 零改动（缓冲清理方案）

**红线：`input_controller.gd` 零改动**（PRD §8.2 A2 红线字面：不新增信号、不改 process_mode、不加方法）。缓冲清理由 PauseMenu 消费既有公共 API：

```gdscript
# PauseMenu._resume() 内（§2.1 已列）
while _input_controller.buffer_size() > 0:
	_input_controller.poll_buffer()
```

- `buffer_size()` 与 `poll_buffer()` 均内含 `_clear_expired()`（物理时间窗过滤）——暂停期间滞留的过期条目先被过滤，剩余活条目被 pop 丢弃
- 语义等价于「清空缓冲」，且 InputController 文件零 diff（`git diff` 可证）

### 3.5 文件变更汇总

- **修改文件（3）:** `shandong-wolf/project.godot`（InputMap +1 动作）、`shandong-wolf/gdscripts/main_battle.gd`（第 ⑮ 步 + `_build_pause_menu()`）、`shandong-wolf/gdscripts/constants.gd`（`PAUSE_*` 分区）
- **新文件（2）:** `shandong-wolf/gdscripts/pause_menu.gd`、`shandong-wolf/tests/test_pause_menu.gd`（implement 期产出，本 DESIGN 仅 §8 用例描述）
- **E2E（implement 期）:** `shandong-wolf/gdscripts/e2e_pause_capture.gd`（新）+ `shandong-wolf/e2e_shots.json`（追加 pause group）
- **删除/弃用文件（0）:** 无

---

## 4. 数据流

### Flow 1: 暂停（正常路径）

```text
1. 战斗进行中（RUNNING），玩家按 ESC
2. PauseMenu._process（ALWAYS）: Input.is_action_just_pressed("game_pause") == true
3. toggle_pause() → 守卫检查: game_state != FAIL → 通过
4. _pause(): _paused=true; get_tree().paused=true
5. 冻结面（AC4）: InputController 停轮询（INHERIT）、PlayerController/EnemyAI 停 _process、
   CombatEntity 停 _physics_process、HUD Tween/Timer 停、Atmosphere GPUParticles3D 停发
6. 菜单层（ALWAYS 不受影响）: DimOverlay + MenuRoot visible=true，按钮可点
```

### Flow 2: 恢复（正常路径）

```text
1. PAUSED 中，玩家点「继续」或再按 ESC
2. ResumeButton.pressed → toggle_pause()（同一入口）或 _process ESC 边沿 → toggle_pause()
3. _resume(): _paused=false; ManualPanel.visible=false; DimOverlay/MenuRoot hidden
4. _clear_input_buffer(): 循环 buffer_size()/poll_buffer() 清空滞留战斗意图
5. get_tree().paused=false → 全树恢复 _process/_physics_process
6. 战斗无缝续跑（输入无残留、慢动作 time_scale 未动、Tween 从暂停点续跑）
```

### Flow 3: 操作手册查看

```text
1. PAUSED 中，点「操作手册」→ _toggle_manual() → ManualPanel.visible=true
2. 首开懒生成: manual_text() 遍历 InputMap game_* 动作 → [动作, 键名] 行 + 静态处决行
3. 再点「操作手册」→ 面板关闭（仍在 PAUSED）
4. 手册开着时按 ESC → _resume() 直接恢复并关面板（ESC=恢复优先，PRD §5.2 边界 8）
```

### Flow 4: FAIL 终态拦截（失败路径）

```text
1. 玩家死亡 final=true → main_battle._on_player_final_death → _set_game_state(FAIL)
   + InputController.set_process(false)（输入冻结）+ 失败字幕淡入
2. 玩家按 ESC → PauseMenu._process 边沿命中 → toggle_pause()
3. 守卫: _game_state_getter.call() == FAIL → return（幂等，不弹菜单、不动 paused）
4. 失败演出不被中断（AC 边界 2 ✓）
```

---

## 5. 边界情况与错误处理

| # | 边界场景 | 缓解措施 |
|---|---------|---------|
| 1 | 暂停中连按 ESC（toggle 抖动） | `is_action_just_pressed` 边沿语义 + `_paused` 状态幂等——已暂停再按=恢复，恢复后 1 帧内再按=再暂停（正常交替） |
| 2 | FAIL 终态按 ESC | `bind_game_state` 守卫拦截（`game_state==FAIL → return`）；main_battle FAIL 路径已 `set_process(false)` 冻结 InputController（双保险）；失败字幕演出零中断 |
| 3 | 暂停前输入缓冲残留 → 恢复瞬间「隔空出刀」 | `_resume()` 统一 `_clear_input_buffer()`（`buffer_size()`/`poll_buffer()` 循环，InputController 零改动）；测试 T9 断言恢复后 `buffer_size()==0` |
| 4 | 冲刺按住中暂停 | `_sprinting` 状态随 INHERIT 冻结；恢复后若 Shift 已松开，`_was_pressed[game_dash]` 下一帧 `_update_dash_hold()` 自愈（无粘滞冲刺） |
| 5 | 慢动作（#579 `Engine.time_scale≠1`）中暂停 | 暂停只动 `get_tree().paused`，不触碰 `Engine.time_scale`（TimeScaleStack 独立持有者）；恢复后慢动作无缝续跑——§7 实验 1 佐证 |
| 6 | 处决特写（#580）中暂停 | 处决演出为 Tween/Timer 驱动 → 树暂停即冻结；恢复后续跑；暂停中 CombatJudge 信号链零输入无新判定（可接受，不特判） |
| 7 | 手册面板开着时再按 ESC | ESC=恢复优先：`_resume()` 强制关面板再恢复（PRD §5.2 边界 8 取后者语义） |
| 8 | `game_pause` 动作缺失（InputMap 未注册） | `_ready` 校验 `InputMap.has_action("game_pause")`，缺失 → `push_error` + `set_process(false)` 禁用菜单（fail-safe：游戏照常运行不崩溃）；测试 T10 断言 |
| 9 | 装配重入/重复实例 | `add_to_group("pause_menu")` + 首实例保留守卫（Hud 同款模式）；重复装配幂等 |
| 10 | 菜单节点创建失败（极端） | `_create_nodes` 包 try 语义（Godot 无 try，用 `is_instance_valid` 逐节点守卫），任一步失败 → `push_error` + 菜单禁用，游戏不崩溃 |
| 11 | 窗口失焦自动暂停 | **超出范围**（deferred，非 issue 验收项，PRD §5.2 边界 7），仅记录不实现 |
| 12 | 暂停中 HUD 信号迟到（恢复瞬间重画） | 信号源（CombatEntity）暂停时冻结不发；恢复后 HUD 按既有信号续画，无队列堆积（信号非缓冲式） |

---

## 6. 集成点

> **Status 约定：** ⬜ = pending（实现 agent 接线后更新为 ✅）；review agent 验证全部 ⬜ 解决或显式 defer 后合并。

| 集成 | 我们的组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|-----|:---:|
| InputMap 动作 | `game_pause`（ESC 4194305） | #719 | `project.godot [input]` 新增 | ⬜ pending |
| 暂停状态机 | PauseMenu ↔ `get_tree().paused` | #719 | 树级暂停（唯一持有者） | ⬜ pending |
| FAIL 守卫 | PauseMenu ↔ main_battle `game_state` | #585 | `bind_game_state(Callable)` 只读闭包注入 | ⬜ pending |
| 缓冲清理 | PauseMenu ↔ InputController 公共 API | #573 | `buffer_size()`/`poll_buffer()` 循环（零改动） | ⬜ pending |
| 装配 | main_battle `_build_pause_menu()`（第 ⑮ 步） | #585 | `PauseLayer`(CanvasLayer) → PauseMenu | ⬜ pending |
| 色板/常量 | PauseMenu ↔ `constants.gd` `PAUSE_*` | #576/#584 | `const C = preload(...)` 复用 | ⬜ pending |
| 手册键名 | manual_text ↔ InputMap `action_get_events()` | #573 | 运行时读取（AC3 机器保证） | ⬜ pending |
| 手册处决文案 | 静态行 ↔ #580 语义 | #580 | `PAUSE_EXECUTE_LINE_CANDIDATES`（`# DRAFT`） | ⬜ pending |
| E2E 截图 | e2e_pause_capture ↔ e2e_shots.json pause group | #586 | CaptureRig 兼容三态驱动 | ⬜ pending |

---

## 7. 实施阶段

| Phase | 优先级 | 组件 | 说明 |
|:-----:|:--------:|-----------|------|
| Phase 1 | P0 | `project.godot` + `pause_menu.gd` 骨架 + `constants.gd` `PAUSE_*` | InputMap 动作、菜单节点树（遮罩/标题/按钮/手册面板）、toggle 状态机、FAIL 守卫、缓冲清理——核心可玩闭环 |
| Phase 2 | P0 | `main_battle.gd` 第 ⑮ 步 + `test_pause_menu.gd` + E2E | 装配接线、§8 用例落地、`e2e_pause_capture.gd` 三态 + shot plan |

> 无跨阶段阻塞依赖：Phase 1 完成即手动可玩（临时挂接验证），Phase 2 完成验收闭环。

---

## 8. 测试用例描述（implement agent 落地于 `tests/test_pause_menu.gd`）

> **不写可运行测试文件**——以下为场景化用例描述，测试代码由 implement agent 编写。参考既有测试风格：`tests/test_hud.gd`（静态契约断言）、`tests/test_input_controller.gd`（缓冲语义断言）、`tests/test_main_assembly.gd`（装配产物断言）。

### Scenario A: 暂停/恢复 toggle（AC1/AC2）

- **T1 暂停进入**：装配 MainBattle（含 PauseMenu）→ 模拟 ESC 边沿（`Input.action_press("game_pause")` + 一帧 `_process`）→ 断言 `get_tree().paused == true`、`DimOverlay.visible`、`MenuRoot.visible`
- **T2 恢复（「继续」按钮）**：PAUSED 中点 ResumeButton → 断言 `paused == false`、菜单隐藏、战斗节点 `is_processing()` 为真
- **T3 恢复（再次 ESC）**：PAUSED 中模拟 ESC 边沿 → 断言 `paused == false`（与 T2 同一入口语义）
- **T4 toggle 幂等**：连按 ESC 三次 → 状态序列 pause→resume→pause，最终 `paused == true`；单帧内重复边沿不重复触发（边沿语义）
- **T5 菜单可交互（AC4）**：PAUSED 中 ManualButton 可点击（`process_mode` 断言：PauseMenu `PROCESS_MODE_ALWAYS`）；战斗节点（PlayerController/EnemyAI/Hud）`process_mode` 保持 INHERIT 默认

### Scenario B: 手册一致性（AC3）

- **T6 手册条目 vs InputMap 逐行一致**：`manual_text()` 动态部分遍历 → 对每条 `game_*` 动作，断言手册行存在且键名与 `InputMap.action_get_events()` 映射一致（覆盖移动/轻攻/重攻/格挡/闪避/跳跃/互动/复活全 9 动作）
- **T7 键名映射完整性**：每个 InputMap 事件都能映射出非空键名（防映射表漏项；不断言具体展示字符串——taste 域）
- **T8 手册静态处决行**：手册含处决说明行（文案取 `PAUSE_EXECUTE_LINE_CANDIDATES` 首项），该行不参与 T6 一致性断言
- **T8b 手册懒生成**：首次开手册前 `ManualLines` 子节点为空，开启后填充 N 行；再次开关不重复追加（幂等）

### Scenario C: 冻结语义（AC4）

- **T9 暂停中战斗信号零发射**：PAUSED 下模拟攻击键按下 → 断言 InputController **无** `attack_pressed` 等信号发出（A2 语义：INHERIT 冻结）；恢复后首帧断言 `buffer_size() == 0`（缓冲已清，边界 3）
- **T9b 粒子/Tween 冻结**（PRD §7 实验 2）：headless 场景置 `paused=true` → 断言 Atmosphere 粒子 `emitting` 停、HUD Tween `is_running() == false`；恢复后续跑

### Scenario D: FAIL 守卫（边界 2）

- **T10 FAIL 终态不弹菜单**：注入 game_state=FAIL 的闭包 → 模拟 ESC → 断言 `paused` 保持 false、菜单不可见（幂等忽略）；同时断言 `game_pause` 缺失时 `_ready` push_error 且菜单禁用（fail-safe，边界 8）

### Scenario E: 装配与回归

- **T11 装配产物**：MainBattle `_ready` 后 `pause_menu` 非空、`PauseLayer` 为 CanvasLayer layer=2、PauseMenu `process_mode == ALWAYS`、`bind_game_state` 后 FAIL 守卫生效（T10 复用）
- **T12 既有回归**：`tests/run_tests.gd` 全绿（暂停默认 off，`test_input_controller.gd` 缓冲用例不受影响——PauseMenu 未装配时 `_input_controller` 为 null 时 `_clear_input_buffer` no-op）

### E2E 计划（implement 期，`e2e_pause_capture.gd` 同构 `e2e_hud_capture.gd`）

| shot | 状态 | 断言/截图内容 |
|------|:---:|------|
| PAUSE_OPEN | 0 | 暂停菜单弹出：遮罩 + 标题 + 「继续」「操作手册」按钮 |
| MANUAL_OPEN | 1 | 操作手册面板：动态键位行（移动/攻击/格挡/闪避/跳跃/互动/复活/处决）+ 静态处决说明 |
| PAUSE_RESUME | 2 | 恢复后战斗画面（冻结面解除，战斗场景截图） |

- `e2e_shots.json` 追加 `pause` group（match `gdscripts/pause_menu.gd`、`gdscripts/e2e_pause_capture.*`），`main_scene` 指向 `e2e_pause_capture.tscn`
- 驱动契约与 CaptureRig 兼容：`current_state` 轮询 + `auto_cycle` 兜底（press 仅支持 enter/space/esc/方向键——ESC 注入天然可用，与 `e2e_hud_capture.gd` digit 键方案不同，pause 三态全走 ESC/按钮注入）

---

## 9. 验收条件映射与明确不修改

### 9.1 AC 映射（issue body 4 条）

| AC | 保障位置 | 验证 |
|----|---------|------|
| AC1 游戏进行中 ESC → 暂停 + 菜单弹出（画面冻结） | §2.1 `_process` 自检 + `_pause()`（`get_tree().paused=true`） | T1 + E2E PAUSE_OPEN |
| AC2 选「继续」或再按 ESC → 恢复 | §2.1 `toggle_pause()` 双路径（按钮 + ESC 同一入口） | T2/T3 + E2E PAUSE_RESUME |
| AC3 操作手册显示正确按键（与 InputMap 一致） | §2.4 `manual_text()` 运行时生成 | T6/T7/T8 |
| AC4 暂停期间敌人/粒子/动画全部冻结，菜单可交互 | §2.1 ALWAYS + 全树 INHERIT（grep 核验零显式 process_mode） | T5/T9/T9b |

### 9.2 明确不修改（红线清单）

| 文件/系统 | 原因 |
|-----------|------|
| `gdscripts/input_controller.gd` | A2 红线：零改动（不新增信号/方法、不改 process_mode）——缓冲清理走既有公共 API |
| `gdscripts/hud.gd` / `combat_entity.gd` / `combat_judge.gd` / `enemy_ai*.gd` / `execution_orchestrator.gd` / `reaction_controller.gd` / `revive_orchestrator.gd` | 战斗/表现侧零触碰——暂停是树级状态，非组件改动 |
| `scenes/*.tscn`（Main/battle_stage/e2e_*） | 菜单纯代码创建（零 tscn 惯例）；E2E capture 场景归 implement 期新建 |
| `e2e_shots.json` 既有 group | 仅追加 pause group，不改既有 shot |
| `TUTORIAL_HINT_CANDIDATES[1]`（K/L 矛盾） | taste 通道 flag，本 issue 不修（PRD §1.1 明确范围外） |
| `mini-pong/`、`.github/`、`scripts/`、`framework/`、`game-env/manifest.yaml` | 游戏外零影响 |

> **实现红线复述（implement agent 必读）：** 恢复路径唯一入口 `toggle_pause()`；`# DRAFT` 常量实现期禁止裁决（候选进 PR 待用户定稿）；InputController 零 diff；不写 `paused=false` 散点直写；测试断言与 §8 用例一一对应。

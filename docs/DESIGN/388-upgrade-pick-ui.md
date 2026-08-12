# DESIGN: [Feature] 3选1升级UI (Upgrade Pick UI)

> **Parent Issue:** #388
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A×4 — ① 确认后 reveal 稀有度 ② `get_tree().paused` + UI `PROCESS_MODE_ALWAYS` ③ WaveController `settle_hold`/`advance_settlement()` 推进接管 ④ `focus_index` + `_unhandled_input` 焦点状态机（**全部确认 PRD §4 推荐，无分歧**）
> **Reference PRD:** docs/PRD/388-upgrade-pick-ui.md（research PR #434，已合并 2026-08-12）
> **上游方案:** docs/PLAN-rogue-pong.md §2.5（3 选 1 + 稀有度后置 reveal 情绪机制）+ §3.3（3 张霓虹卡片、glow 边框、hover 微亮、数值大字、Tween 150–300ms）
> **所有权:** `content_ownership: mechanical`（交互机械层；稀有度**色值**与卡片**文案**归 taste 域 #395，本设计以 taste 占位常量给出、映射键机械定稿——沿 #387 先例）
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386/#387 惯例处理）—— 产出 DESIGN + TASKS；**测试仅描述，不写可运行测试代码**
> **Plan 阶段边界:** 本阶段只产出本文档与 `docs/TASKS/388-upgrade-pick-ui.md`，不碰任何 `.gd` / `.tscn` / `.json` / `project.godot` 文件 —— 下列全部内容为 implement agent 的契约。

---

## 1. 架构概述

Mini Pong（`mini-pong/`，Godot 4.7.1，720×1280 竖屏，#383 已合并）的升级数据链路已闭环（#386 挂点 → #387 数据 → #395 文案），**唯独缺少玩家可见的 3 选 1 升级交互层**（GDD 23 标注 "3-choice UI (#388, not yet wired)"）。本设计新增一个 CanvasLayer 场景 `UpgradePickUI`：监听 `GameManager.wave_settled`（#386 挂点）→ 调 `UpgradePool.get_candidates(3)`（#387，唯一候选来源）→ 焦点环选择 → `apply(id)` → reveal 稀有度 → 关闭并恢复游戏时间 → 显式通知 WaveController 推进下一波。

```
  BreakoutGrid.wall_cleared（#384 契约；#393 组装前不激活）
        │
        ▼
  WaveController._on_wall_cleared() ──► GameManager.settle_wave()
                                            │ wave_state = SETTLED
                                            ▼  （同步 emit）
                              GameManager.wave_settled(wave_index)
                                            │
                                            ▼
  ┌──────────────────────── UpgradePickUI（CanvasLayer layer 2，新） ────────────────────────┐
  │  open(wave_index): UpgradePool.get_candidates(3) → 渲染 3 卡（不足则按实渲染）            │
  │                    → get_tree().paused = true（AC4 游戏时间暂停）                          │
  │                    → WaveController.settle_hold = true（推进接管）                        │
  │  _unhandled_input: ui_left/ui_right 循环切换 focus_index；ui_accept → 确认                 │
  │  _confirm(): UpgradePool.apply(id)                                                        │
  │       ├─ true  → REVEALING：边框切稀有度色 + 稀有度名称 + 短句（AC3）→ 短暂展示 → close()  │
  │       └─ false → 保持打开 + push_warning（边界 2）                                        │
  │  close(): visible=false → get_tree().paused = false（AC4 恢复）                            │
  │           → WaveController.advance_settlement() → _advance_wave() → 下一波                │
  └───────────────────────────────────────────────────────────────────────────────────────────┘
```

### 设计哲学

1. **最小侵入**（PRD §2 前置约束）：`UpgradePool` / `GameManager` / FSM **零改动**——UI 只消费既有信号与 API；`WaveController` 只加一个默认关闭的 hold/advance 机制（默认 `false` 保持 #386 行为，既有 wave 测试零破坏）。
2. **显式接管，不靠暂停隐式解决**：`SceneTreeTimer` 默认 `process_always=true`，`get_tree().paused` **无法**阻止 WaveController 的自动推进计时——推进时机接管必须是 `settle_hold` 显式机制（PRD §4.3-A，spike 实验 3 已验证）。
3. **树级暂停是标准答案**：`get_tree().paused = true` 天然冻结 ball/paddle/FSM/雨幕等全部 PAUSABLE 逻辑；Godot 4 的 `process_mode` 同时门控 `_input`/`_unhandled_input` 回调——UI 根节点 `PROCESS_MODE_ALWAYS` 保证暂停下仍收输入，FSM 的 `_input` 被抑制（Escape 不误触，边界 4 天然满足）。
4. **机械占位**：稀有度色值标注 taste 占位（`UPGRADE_RARITY_COLORS`），映射关系（COMMON/RARE/LEGENDARY → 色键）机械定稿可测，具体色值归 taste 域（沿 #387「机械占位数值」先例）。
5. **容错消费**（沿 #386 先例）：WaveController 通过 group `wave_controllers` + `has_method` 守卫访问——#393 组装前 Main.tscn 无 WaveController 节点时 UI 照常工作（open/close 的接管调用 no-op 不崩）。

### 关键事实（plan agent 已对照源码核实）

| 事实 | 源码依据 |
|------|---------|
| `GameManager.wave_settled(wave_index)` 存在且 `settle_wave()` **同步 emit**（→ UI.open() 在 `_on_wall_cleared` 恢复执行前完成，settle_hold 无竞态） | `game_manager.gd` §Wave Cycle + `wave_controller.gd` `_on_wall_cleared` |
| `UpgradePool.get_candidates(3)` 候选结构 `{id, name, rarity(int), max_stacks, effect_desc, display}`；`rng` 可 `seed()`（测试确定性）；`apply(id)->bool`；`upgrade_applied(id)` 信号 | `upgrade_pool.gd` |
| `WaveController` 现状：`_on_wall_cleared()` → `settle_wave()` → `await create_timer(settle_delay)` → `_advance_wave()`；`settle_delay` 已是可注入实例变量；`_settling` 守卫防重复 | `wave_controller.gd`（86 行） |
| **Main.tscn 现无 WaveController/BreakoutGrid 节点**（运行时波次链路未激活，#393 组装）；CanvasLayer 层序：Atmosphere(0) / StartMenu(1) / GameHUD(1) / GameOverScreen(1) / PauseOverlay(10) | `scenes/Main.tscn` |
| `project.godot` 无自定义 `[input]` 段——使用 Godot 内置 `ui_left`/`ui_right`/`ui_accept`/`ui_cancel`；FSM `_input` 消费 `ui_accept`/`ui_cancel` | `project.godot` + `game_state_machine.gd` |
| PauseOverlay（layer **10**）无 `process_mode=ALWAYS`——其由 FSM 驱动、不在树级暂停下工作；升级 UI 必须**显式** `PROCESS_MODE_ALWAYS` | `scenes/Main.tscn` + `pause_overlay.gd` |
| 测试基座：`run_tests.gd` 注册 18 套件，`_run_async` 用于含 `await` 的套件（`test_wave_cycle.gd` 先例）；测试文件 `extends RefCounted` + `run()` | `tests/run_tests.gd` |

### Prior Implementation Status（相关 Issue 既有工作）

- **#386（波次循环，PR #428 已合并）**：`wave_settled` 挂点 + `WaveController` 已落地；`WAVE_SETTLE_DELAY=1.0s` 自动推进，注释明确「#388 接线后由其接管推进时机」。本设计在其上加 hold/advance。
- **#387（升级池，PR #423 已合并）**：`UpgradePool` autoload + `upgrade_defs.gd` 9 定义 + `get_candidates(3)`/`apply(id)`/`upgrade_applied` 全部就绪；`tests/test_upgrade_pool.gd`（29 条）已存在。
- **#395（升级池文案）**：`mini-pong/assets/content/upgrade_pool.json` 已落地（schema `upgrade-pool-content/v1`），UI 只读消费 `display`（缺失兜底工作名）。
- **#388 无既有实现**：无 `upgrade_pick_ui.gd` / `ui_upgrade_pick.tscn` / `test_upgrade_pick_ui.gd`。注意：research 分支 `research/#388-upgrade-pick-ui`（PR #430）为**过期重复分支**（仍 OPEN，与已合并的 PR #434 同名异分支），非部分实现，忽略即可。
- **#384（砖墙）**：PRD #411 + DESIGN #414 已合并但**实现未落地**——本设计全部测试与实现不依赖其运行时存在（headless 直测 UI 层 + mock 契约）。

### 与 PRD 的差异决策（plan 定稿）

| # | PRD 表述 | 源码事实 | 设计定稿 |
|---|---------|---------|---------|
| 1 | §6「升级 UI 置于 GameHUD 之上、**与 PauseOverlay 同级（layer 2）**」 | PauseOverlay 实际是 layer **10**（非 2） | 取 PRD §3 的 **layer 2** 定稿：GameHUD(1) 之上、PauseOverlay(10) 之下；PauseOverlay 与升级 UI 互斥显示（FSM 在树级暂停下不响应 Escape，二者不会同时出现） |
| 2 | §8 数据流「confirm → apply → reveal → close」 | 若 close 与 reveal 同帧，玩家**看不到**稀有度——违背 PLAN §2.5 惊喜时刻 | 确认后进入 `REVEALING` 态，reveal 动效后**短暂展示**（`UPGRADE_UI_REVEAL_HOLD=0.8s`，taste 占位、测试可注入缩短），期间输入锁定，然后 close（§3.1） |
| 3 | §8「close: ... → WaveController.advance_settlement()」 | WaveController 非 autoload，Main.tscn 现无该节点 | UI 经 group `wave_controllers` + `has_method` 守卫调用（沿 #386 `get_node_or_null` 容错先例）；未挂载时 no-op 不崩（§3.1 `_advance_settlement`） |
| 4 | §4.3-A「UI 打开时置 hold」 | `settle_wave()` 同步 emit → UI.open() 在 `_on_wall_cleared` 的 hold 检查**之前**执行 | hold 判定放在 `settle_wave()` 返回之后、`create_timer` 之前；依赖同步信号序，无竞态（§4.1 伪代码） |

---

## 2. 现状核实与差距发现（plan agent 已对照源码）

### Gap Discovery（PRD 断言 vs 实际代码）

| PRD 断言 | 实际代码 | 设计决议 |
|---------|---------|---------|
| §3「ui_upgrade_pick 与 PauseOverlay 同模式」 | PauseOverlay 无 `process_mode=ALWAYS`（FSM 驱动型，非树级暂停场景） | 升级 UI 根节点**必须** `process_mode = Node.PROCESS_MODE_ALWAYS`（§3.2）——这是 AC4 暂停下仍可交互的前提 |
| §8「close 调 WaveController.advance_settlement()」 | `wave_controller.gd` 无 `settle_hold`/`advance_settlement`；Main.tscn 无 WaveController 节点 | 新增两个成员（默认行为不变）+ group 寻址 + `has_method` 守卫（§4.1） |
| §5 边界 4「树级暂停屏蔽 FSM `_input`」 | FSM 用 `_input` 消费 `ui_accept`/`ui_cancel`，未设 process_mode（默认 PAUSABLE） | 成立：Godot 4 `process_mode` 门控输入回调；实现期以回归测试锁定（§9 TC-E3） |
| §5 AC3「稀有度以颜色/边框显现」 | `constants.gd` 仅有 `PLAYER_NEON_BLUE`/`AI_NEON_RED`/`BG_COLOR`，无稀有度色 | 新增 `UPGRADE_RARITY_COLORS`/`UPGRADE_RARITY_NAMES` 映射（§4.2） |
| PRD §3 表格「run_tests.gd 注册 18 个套件」 | 实际 18 行注册（含 `_run_async` 的 wave 套件） | 新增套件用 `_run_async` 注册（含 `await` 延时）（§4.4） |

### 集成模式选择

本 UI 是**全新独立 CanvasLayer 场景**，不替换、不包装任何既有 Area3D/触发节点——按 SKILL「Pattern 1 — Sibling（additive）」思路，以兄弟节点挂载于 Main.tscn（与 StartMenu/GameHUD/GameOverScreen 同层结构），零侵入既有信号接线。不采用 Pattern 2/3（无既有组件可替换/继承）。

---
---

## 3. 新组件 — 详细设计

### 3.1 `mini-pong/gdscripts/upgrade_pick_ui.gd`（新建 — 升级选择层脚本）

**Node 角色**：挂载于 `ui_upgrade_pick.tscn` 根（CanvasLayer）。三态状态机 `CLOSED → SELECTING → REVEALING → CLOSED`。

**信号**

| 信号 | 参数 | 说明 |
|------|------|------|
| `upgrade_chosen(upgrade_id: String)` | 选中的升级 id | 可选扩展锚点（供 #393 E2E 断言/未来 HUD 消费；`upgrade_applied` 已存在故非必需，实现期可不接） |

**状态属性**

```gdscript
enum UIState { CLOSED, SELECTING, REVEALING }
var _state: int = UIState.CLOSED      # 状态机；仅 SELECTING 响应输入
var _focus_index: int = 0             # 焦点卡下标（循环切换）
var _candidates: Array = []           # open() 时 get_candidates(3) 的结果缓存
var _wave_index: int = 0              # 本次升级窗口的波次号（wave_settled 载荷）
var _reveal_hold: float = CONSTS.UPGRADE_UI_REVEAL_HOLD   # reveal 展示时长（测试可注入缩短）
```

**关键方法（implement 契约）**

```gdscript
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # AC4 前提：树级暂停下仍处理输入
	visible = false
	GameManager.wave_settled.connect(open)    # #386 挂点（autoload 信号，任意场景/headless 可用）

## AC1/AC5：打开升级窗口。幂等：已打开/REVEALING 中再收到 wave_settled → no-op。
func open(wave_index: int) -> void:
	if visible or _state != UIState.CLOSED:
		return                                # 边界 3：wave_settled 连发幂等
	if GameManager.is_run_over():
		return                                # 边界 5：终局竞态跳过升级窗口
	_candidates = UpgradePool.get_candidates(CONSTS.UPGRADE_CANDIDATE_COUNT)   # AC5 唯一来源
	if _candidates.is_empty():
		return                                # 失败路径 1：无候选 → 静默跳过，不暂停
	_wave_index = wave_index
	_focus_index = 0
	_render_candidates()                      # 按实际张数渲染（<3 时隐藏多余卡）
	visible = true
	_state = UIState.SELECTING
	get_tree().paused = true                  # AC4：游戏时间暂停
	_set_settle_hold(true)                    # 推进接管：WaveController 停止自动推进

## AC2：焦点环 + 确认。仅 SELECTING 态响应。
func _unhandled_input(event: InputEvent) -> void:
	if _state != UIState.SELECTING or not visible:
		return
	if event.is_action_pressed("ui_left"):
		_move_focus(-1)
	elif event.is_action_pressed("ui_right"):
		_move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		_confirm()
	# ui_cancel 不消费（边界 4：保持打开；FSM 在暂停下收不到，天然不切 PAUSED）

func _move_focus(delta: int) -> void:
	var n: int = _candidates.size()
	_focus_index = posmod(_focus_index + delta, n)   # 循环 0→1→2→0（AC2）
	_apply_focus_visual()                             # 高亮切换（modulate/边框，Tween 150ms）

func _confirm() -> void:
	var id: String = _candidates[_focus_index].id
	if UpgradePool.apply(id):                         # AC2：应用选中升级（恰好一次）
		upgrade_chosen.emit(id)
		_start_reveal()
	# apply 返回 false（未知 id / 已达 max_stacks 竞态）→ 保持打开 + push_warning（边界 2）

## AC3：确认后 reveal。REVEALING 态锁定输入；短暂展示后关闭。
func _start_reveal() -> void:
	_state = UIState.REVEALING
	var chosen: Dictionary = _candidates[_focus_index]
	_reveal_card(_focus_index, chosen)                # 边框切稀有度色 + RarityLabel 显示名称 + 短句
	await get_tree().create_timer(_reveal_hold).timeout  # paused 下 process_always 仍计时（§6）
	if not is_inside_tree():
		return
	close()

## AC2/AC4：关闭并恢复。幂等。
func close() -> void:
	if _state == UIState.CLOSED:
		return
	_state = UIState.CLOSED
	visible = false
	get_tree().paused = false                         # AC4：恢复游戏时间
	_advance_settlement()

## 推进接管（差异决策 3）：经 group 寻址 WaveController，未挂载时 no-op。
func _advance_settlement() -> void:
	var wc = get_tree().get_first_node_in_group("wave_controllers")
	if wc != null and wc.has_method("advance_settlement"):
		wc.advance_settlement()                       # → _advance_wave() → 下一波

func _set_settle_hold(hold: bool) -> void:
	var wc = get_tree().get_first_node_in_group("wave_controllers")
	if wc != null and "settle_hold" in wc:
		wc.settle_hold = hold
```

**渲染辅助（implement 契约要点）**

- `_render_candidates()`：遍历 `_candidates`，第 i 卡写 `NameLabel.text`（`display.name_working` 非空优先，否则 `name` 兜底）、`ShortPhraseLabel.text`（`display.short_phrase` 非空优先，否则留空）、`EffectDescLabel.text`（`effect_desc`）；候选 <3 时隐藏多余卡；全部卡**中性霓虹样式**（无稀有度线索）。
- `_apply_focus_visual()`：焦点卡高亮（边框亮度/色调提升 + 轻微放大），非焦点卡恢复；Tween 时长 `UPGRADE_UI_FOCUS_TWEEN`。
- `_reveal_card(i, chosen)`：第 i 卡 `StyleBoxFlat.border_color = UPGRADE_RARITY_COLORS[chosen.rarity]` + `RarityLabel.text = UPGRADE_RARITY_NAMES[chosen.rarity]`（Tween 时长 `UPGRADE_UI_REVEAL_TWEEN`）；其余卡保持中性。

**集成说明**：不修改 UpgradePool/GameManager/FSM 任何契约；不新增 FSM 状态；不依赖 Control focus 系统（手动焦点状态机，headless 可直测）。

### 3.2 `mini-pong/scenes/ui_upgrade_pick.tscn`（新建 — 三卡霓虹选择层）

**Node 结构**

```
UpgradePickUI (CanvasLayer, layer=2, process_mode=3(ALWAYS), visible=false, script=upgrade_pick_ui.gd)
└── CenterContainer (全屏锚点 15)
    └── HBoxContainer (separation=UPGRADE_UI_CARD_SEPARATION, alignment=center)
        ├── Card0 (PanelContainer, custom_minimum_size=UPGRADE_UI_CARD_WIDTH×HEIGHT, StyleBoxFlat 霓虹边框)
        │   └── VBoxContainer
        │       ├── NameLabel (font_size≈32, 数值大字 — PLAN §3.3)
        │       ├── ShortPhraseLabel (font_size≈18, modulate 半透明 — #395 short_phrase)
        │       ├── EffectDescLabel (font_size≈16, autowrap)
        │       └── RarityLabel (font_size≈20, 初始 text="" 且隐藏 — AC3 确认前无稀有度线索)
        ├── Card1 (同 Card0)
        └── Card2 (同 Card0)
```

**要点**

- CanvasLayer `layer = 2`（差异决策 1）；`process_mode = 3`（ALWAYS，AC4 前提）；初始 `visible = false`（与 PauseOverlay 同模式挂载，由脚本控制显隐）。
- 三卡**预创建**（`@onready` 引用数组 `_cards = [$CenterContainer/HBoxContainer/Card0, ...]`），不足 3 候选时隐藏多余卡——避免运行时动态建卡（headless 稳定、场景可预览）。
- StyleBoxFlat 主题：深色底（`BG_COLOR` 系）+ 霓虹边框（`PLAYER_NEON_BLUE` 系中性色，确认前**不**携带稀有度色）；焦点/选中态由脚本改 border_color/modulate（不依赖 Theme 资源文件，全内联 StyleBoxFlat——沿 #292 先例）。
- 短句/文案数据源：#395 JSON 经 `UpgradePool` 注入的 `display` 字段（只读）；缺失走兜底链（§3.1）。

### 3.3 `mini-pong/tests/test_upgrade_pick_ui.gd`（新建 — 实现期测试套件）

**文件由 implement agent 依 §9 编写**（本阶段不产出 runnable 文件）。规格要点：

- 基座沿 `test_wave_cycle.gd` 先例：`extends RefCounted` + `run()`（`await` 化，经 `_run_async` 注册）；真实 autoload（GameManager/UpgradePool）+ mini tree（根 Node 下挂 UpgradePickUI 实例 + 可选 WaveController/mock）。
- 确定性：`UpgradePool.rng.seed(固定值)` 固定候选序列；`_reveal_hold` 注入短时长（如 0.01s）避免长等待。
- 输入 feed：`Input.parse_input_event()` 构造 `ui_left`/`ui_right`/`ui_accept`/`ui_cancel` 动作事件（4.4-A 手动状态机，headless 无 Control focus 依赖）。
- 推进接管断言：mini tree 内挂真实 WaveController + mock BreakoutGrid（#414 契约子集：`wall_cleared` 信号 + `generate_wave` + 调用记录，复用 `test_wave_cycle.gd` 既有夹具模式）或注入带 `advance_settlement` 的假节点于 group `wave_controllers`。
- 暂停断言：`get_tree().paused` 直读；FSM Escape 屏蔽用 `test_pause.gd` 同款 FSM mock 或集成断言（`test_integration_fsm.gd` 先例）。

---
---

## 4. 现有组件修改

### 4.1 修改文件清单

| 文件 | 改动 | 为什么 |
|------|------|--------|
| `mini-pong/gdscripts/wave_controller.gd` | 新增 `settle_hold: bool = false` + `advance_settlement()`；`_ready` 加 group `wave_controllers`；`_on_wall_cleared` 结算后 hold 检查 | PRD §4.3-A 推进接管：默认 false 保持 #386 行为，既有 wave 测试零破坏 |
| `mini-pong/gdscripts/constants.gd` | 新增 `UPGRADE_RARITY_COLORS`/`UPGRADE_RARITY_NAMES` + `UPGRADE_UI_*` 常量组 | AC3 稀有度映射（taste 占位）+ PLAN §3.3 视觉参数单一事实源 |
| `mini-pong/scenes/Main.tscn` | 挂载 `ui_upgrade_pick`（ext_resource + node，初始 `visible=false`） | AC1 波间弹窗的宿主挂载（#393 组装时与 WaveController 一并激活） |
| `mini-pong/tests/run_tests.gd` | 注册 `test_upgrade_pick_ui.gd`（`_run_async`，命名 "Upgrade Pick UI"） | 套件纳入 headless 回归 |
| `docs/GAME_DESIGN/25-UPGRADE-UI.md` + `docs/PROJECT.md` | 新章/清单更新（实现 PR 同步，管线惯例） | 文档闭环 |

### 4.2 `wave_controller.gd` 伪代码（implement 契约）

```gdscript
# ── 新增成员（#388 推进接管；默认 false = 原 #386 自动推进行为）──
var settle_hold: bool = false   # true = 结算后暂停自动推进，等待 UpgradePickUI 调 advance_settlement()

func _ready() -> void:
	add_to_group("wave_controllers")            # #388：UI 经 group 寻址（差异决策 3）
	if breakout_grid != null and breakout_grid.has_signal("wall_cleared"):
		breakout_grid.wall_cleared.connect(_on_wall_cleared)
	else:
		push_warning("WaveController: BreakoutGrid 未接线 (#384/#393)，波次循环暂不激活")

func _on_wall_cleared() -> void:
	if _settling or GameManager.is_run_over():
		return
	_settling = true
	GameManager.settle_wave()                 # 同步 emit wave_settled → UI.open() 会置 settle_hold=true
	if GameManager.is_run_over():
		GameManager.end_wave_cycle()
		_settling = false
		return
	if settle_hold:
		return                                # #388：推进时机由 UI 接管（_settling 保持 true 等待 advance）
	await get_tree().create_timer(settle_delay).timeout   # 原自动推进路径（#386 行为不变）
	if not is_inside_tree():
		return
	_advance_wave()
	_settling = false

## #388：UI 关闭后显式推进（等价原延时后的动作 + _settling 复位）。幂等：非结算期 no-op。
func advance_settlement() -> void:
	if not _settling:
		return
	if GameManager.is_run_over():
		GameManager.end_wave_cycle()
		_settling = false
		return
	_advance_wave()
	_settling = false
```

> **时序保证（无竞态）**：`settle_wave()` 同步 emit → UI `open()`（含 `settle_hold = true`）在 `_on_wall_cleared` 恢复执行**之前**完成 → hold 检查必然命中。UI 未接线时 `settle_hold` 恒 false → 原自动推进路径，回归零破坏。

### 4.3 `constants.gd` 伪代码（implement 契约）

```gdscript
# ── Upgrade Pick UI (#388) ──
# 3 选 1 升级选择层（PLAN-rogue-pong §3.3：3 张霓虹卡片、glow 边框、数值大字、
# 动效 Tween 150–300ms）。色值为 taste 占位（沿 #387 机械占位先例），映射键机械定稿。
const UPGRADE_UI_LAYER: int = 2                     # GameHUD(1) 之上、PauseOverlay(10) 之下（差异决策 1）
const UPGRADE_UI_CARD_WIDTH: float = 180.0          # 卡片尺寸（taste 占位）
const UPGRADE_UI_CARD_HEIGHT: float = 260.0
const UPGRADE_UI_CARD_SEPARATION: float = 16.0
const UPGRADE_UI_FOCUS_TWEEN: float = 0.15          # 焦点切换动效 150ms（PLAN §3.3 区间内）
const UPGRADE_UI_REVEAL_TWEEN: float = 0.25         # reveal 动效 250ms
const UPGRADE_UI_REVEAL_HOLD: float = 0.8           # reveal 展示时长（差异决策 2；taste 占位，测试可注入缩短）
const UPGRADE_RARITY_COLORS: Dictionary = {         # AC3：稀有度 → 边框/光晕色（taste 占位色值）
	0: Color(0.29, 0.56, 0.85, 1.0),   # COMMON    → 霓虹蓝系（PLAYER_NEON_BLUE 同系）
	1: Color(0.62, 0.32, 0.95, 1.0),   # RARE      → 霓虹紫系
	2: Color(1.0, 0.78, 0.2, 1.0),     # LEGENDARY → 金系
}
const UPGRADE_RARITY_NAMES: Dictionary = {0: "普通", 1: "稀有", 2: "传说"}   # AC3 稀有度名称
```

### 4.4 `Main.tscn` 伪代码（implement 契约）

```
[ext_resource type="PackedScene" path="res://scenes/ui_upgrade_pick.tscn" id="12_upgrade_pick"]

[node name="UpgradePickUI" parent="." instance=ExtResource("12_upgrade_pick")]
# 场景文件内已含: layer=2 / process_mode=3 / visible=false（3.2 契约；Main.tscn 无需重复覆写）
```

> 挂载点与 GameHUD/GameOverScreen 平级（CanvasLayer 兄弟节点，沿 #292 模式）。**不**在 Main.tscn 加 WaveController/BreakoutGrid（属 #393 组装范围）。

### 4.5 `run_tests.gd` 伪代码（implement 契约）

```gdscript
await _run_async("res://tests/test_upgrade_pick_ui.gd", "Upgrade Pick UI")   # 含 await（reveal/settle 延时）
```

### 受影响测试文件

| 文件 | 改动性质 |
|------|---------|
| `mini-pong/tests/test_upgrade_pick_ui.gd` | **新建**（§9 场景 A–H 规格，implement 依此编写） |
| `mini-pong/tests/run_tests.gd` | 注册新套件（4.5） |
| `mini-pong/tests/test_wave_cycle.gd` | **不改**（默认 `settle_hold=false` 兼容；实现期回归确认全绿） |
| `mini-pong/tests/test_pause.gd` / `test_integration_fsm.gd` | **不改**（回归锁定 Escape 屏蔽/FSM 零改动） |

---

## 5. 数据流

### Flow 1: 波间升级窗口（正常路径，AC1–AC5 全链路）

```
BreakoutGrid.wall_cleared（#384 契约）
  → WaveController._on_wall_cleared()
  → GameManager.settle_wave()          [wave_state = SETTLED]
  → wave_settled(wave_index) 同步 emit
  → UpgradePickUI.open(wave_index)
      1. is_run_over()? → 跳过（边界 5）
      2. UpgradePool.get_candidates(3) → 3 候选（AC5 唯一来源）
      3. 渲染 3 卡（display 兜底链）→ visible = true，focus_index = 0（AC1）
      4. get_tree().paused = true（AC4）
      5. WaveController.settle_hold = true（推进接管）
  → _on_wall_cleared 恢复：settle_hold == true → 跳过自动延时（_settling 保持 true）
  → 玩家 ui_right/ui_left 循环切换 focus_index（AC2）
  → ui_accept → UpgradePool.apply(id)
      → true：upgrade_chosen.emit → REVEALING（输入锁定）→ 边框稀有度色 + 名称 + 短句（AC3）
              → await REVEAL_HOLD → close()
      → false：保持打开 + push_warning（边界 2）
  → close(): visible=false → get_tree().paused = false（AC4）→ WaveController.advance_settlement()
  → advance_settlement(): _settling==true → _advance_wave() → begin_wave()/难度递增/生成新墙 → 下一波
```

### Flow 2: apply 失败路径（边界 2）

```
ui_accept → apply(id) == false（未知 id / 已达 max_stacks 竞态）
  → 不 reveal、不关闭、不恢复暂停、不推进
  → push_warning("UpgradePool: ... 无法应用")，UI 保持 SELECTING 可继续选择
```

### Flow 3: 候选不足/为空（边界 1 + 失败路径 1）

```
get_candidates(3) 返回 2 张（池耗尽）
  → 渲染 2 卡（第 3 卡隐藏），focus_index clamp 到 size-1，左右切换 0→1→0
get_candidates(3) 返回 0 张（全部耗尽）
  → 不弹 UI、不暂停（静默跳过本波升级窗口，波次照常由 WaveController 自动推进）
```

### Flow 4: 终局竞态（边界 5 + 失败路径 2）

```
wave_settled 后任一方到 21 分（is_run_over() == true）
  → WaveController._on_wall_cleared 的 run-over 分支直接 end_wave_cycle（不等待、不推进）
  → UI.open() 的 is_run_over() 前置检查 → 不弹 UI
  → 若 reveal 期间 match_over：close() → advance_settlement() 的 run-over 分支 → end_wave_cycle，不生成新墙
```

### Flow 5: #384/#393 未组装容错（现状 Main.tscn）

```
Main.tscn 无 WaveController/BreakoutGrid 节点
  → wave_settled 无场景侧触发源 → UI 不弹（信号无消费者语义，#386 已按此设计）
  → 即便 UI 被手动触发：_set_settle_hold / _advance_settlement 经 group 寻址失败 → no-op 不崩
  → headless 测试在 mini tree 内自组 WaveController/mock，与场景组装解耦
```

---
---

## 6. 边界条件与错误处理

| # | 边界场景 | 缓解措施 |
|---|---------|---------|
| 1 | **候选不足 3 张**（池耗尽/回退链全空） | 按实际张数渲染，`focus_index` 经 `posmod` 天然 clamp 到 `size`；空数组直接不弹 UI 不暂停（Flow 3） |
| 2 | **`apply` 返回 false**（未知 id / 已达 max_stacks 竞态） | 保持 UI 打开 + `push_warning`；不 reveal、不关闭、不恢复暂停、不推进（Flow 2） |
| 3 | **`wave_settled` 连发** | 双侧守卫：WaveController `_settling` 忽略重复 `wall_cleared`；UI `open()` 对 `visible/state != CLOSED` no-op（幂等） |
| 4 | **UI 打开时按 Escape** | 树级暂停下 FSM `_input`（PAUSABLE）被 process_mode 门控抑制 → 天然不切 PAUSED；UI 自身不消费 `ui_cancel`（保持打开） |
| 5 | **终局竞态**（`wave_settled` 后 `is_run_over()`） | WaveController run-over 分支直接 `end_wave_cycle` 不推进；UI `open()` 前置检查跳过升级窗口；reveal 期间终局 → `advance_settlement()` run-over 分支（Flow 4） |
| 6 | **display 文案缺失/损坏**（#395 JSON） | `UpgradePool` 已兜底工作名；UI 只读消费候选的 `name`/`effect_desc`（`display.name_working`/`short_phrase` 空则回退），不依赖 display 非空 |
| 7 | **paused 下计时语义** | `create_timer` 默认 `process_always=true` → REVEALING 的展示计时在暂停下照常推进（设计依赖此语义，与 WaveController 自动推进同一机制——但自动推进已被 settle_hold 显式接管，不冲突） |
| 8 | **`advance_settlement()` 误调**（非结算期/未 hold） | `_settling == false` 时直接 no-op（幂等防御）；UI 只在 close() 时调用一次 |
| 9 | **headless/无真实窗口** | 4.4-A 手动焦点状态机（无 Control focus 依赖），`Input.parse_input_event()` 直测；`_reveal_hold` 可注入短时长 |
| 10 | **close() 重复调用** | `_state == CLOSED` 直接 return（幂等）；REVEALING 中场景卸载 → `is_inside_tree()` 检查防悬挂协程泄漏（沿 #386 先例） |

**失败路径（≥3）**

| # | 失败场景 | 处理 |
|---|---------|------|
| 1 | `get_candidates` 返回空数组 | 不弹 UI、不暂停，静默跳过本波升级窗口（波次由 WaveController 自动推进） |
| 2 | `apply` 失败 | 见边界 2（保持打开 + 警告，可重选） |
| 3 | Main.tscn 未挂载 UI 节点 / WaveController 未挂载 | `wave_settled` 无监听者即 no-op 不崩（#386 信号无消费者语义）；UI 的 group 寻址失败 no-op 不崩 |

---

## 7. 集成点

> **Status 约定：** ⬜ = 待接线（资源已建、未连接目标）；✅ = 已连接（implement agent 验证后更新）。review agent 合并前核查全部 ⬜ 已解决或显式延期。

| 集成 | 我方组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| `GameManager.wave_settled(wave_index)` → `UpgradePickUI.open()` | upgrade_pick_ui.gd | #386 | `_ready()` 信号 connect（autoload 信号） | ✅ 已接线（impl PR） |
| `UpgradePool.get_candidates(3)` → 卡片渲染 | upgrade_pick_ui.gd | #387 | `open()` 内只读调用（AC5 唯一来源） | ✅ 已接线（impl PR） |
| `UpgradePool.apply(id)` + `upgrade_applied` → reveal 锚点 | upgrade_pick_ui.gd | #387 | `_confirm()` 调用 + 信号消费（reveal 时序锚点，可选） | ✅ 已接线（impl PR） |
| UI `open()` → `WaveController.settle_hold = true` | wave_controller.gd | #388/#386 | group `wave_controllers` + `"settle_hold" in wc` 守卫 | ✅ 已接线（impl PR） |
| UI `close()` → `WaveController.advance_settlement()` | wave_controller.gd | #388/#386 | group + `has_method` 守卫（未挂载 no-op） | ✅ 已接线（impl PR） |
| `ui_upgrade_pick` 挂载 Main.tscn（layer 2, ALWAYS, 初始隐藏） | Main.tscn | #393 | ext_resource + CanvasLayer 兄弟节点 | ✅ 已接线（impl PR） |
| #390 波次转场共享 `wave_settled` 挂点 | — | #390 | 各自独立信号处理；升级 UI 打开期间转场让位（UI 打开=游戏时间暂停，转场动画若为 PAUSABLE 自然冻结） | ⬜ deferred |
| #384 砖墙运行时链路（墙 → 波次 → 升级 E2E） | — | #384/#393 | 实现不依赖；落地后手动/E2E 验证（§11 步骤 4） | ⬜ deferred |

---

## 8. 实施阶段

| Phase | 优先级 | 内容 | 依赖 |
|:-----:|:------:|------|------|
| Phase 1 | P0 | `constants.gd` 常量组 + `wave_controller.gd` hold/advance（无 UI 依赖，可先行独立验证回归） | 无 |
| Phase 2 | P0 | `upgrade_pick_ui.gd` + `ui_upgrade_pick.tscn` | Phase 1 常量 |
| Phase 3 | P0 | Main.tscn 挂载 + `test_upgrade_pick_ui.gd` + run_tests.gd 注册 | Phase 1+2 |
| Phase 4 | P1 | `docs/GAME_DESIGN/25-UPGRADE-UI.md` + `docs/PROJECT.md` 更新 | Phase 3 |

---
---

## 9. 测试用例描述（仅描述，implement 依此写代码）

> 本 PR 不写 runnable 测试文件。以下为 `mini-pong/tests/test_upgrade_pick_ui.gd`（新套件，场景 A–H）+ `test_wave_cycle.gd` 回归的规格。共 **28 条**。确定性前提：`UpgradePool.rng.seed(固定值)`；`_reveal_hold` 注入短时长（如 0.01s）；输入经 `Input.parse_input_event()` feed 动作事件。

### Scenario A: 打开与候选渲染（AC1/AC5）— 5 条
- **TC-A1**（PRD T-1）：seed rng 后 emit `wave_settled(1)` → UI `visible == true`、3 张卡、`focus_index == 0`、卡 0 处于聚焦高亮
- **TC-A2**（PRD T-5）：`open()` 期间 `get_candidates` **恰好被调一次**；卡片内容与候选一致（id/name/effect_desc）
- **TC-A3**：display 兜底链——候选 `display.name_working`/`short_phrase` 为空时卡片回退 `name`/留空短句（不依赖 display 非空）
- **TC-A4**：`open(wave_index)` 的波次号被正确持有（供升级窗口上下文使用，如未来 HUD 显示「第 N 波升级」）
- **TC-A5**：幂等——UI 已打开时再次 emit `wave_settled` → no-op（`get_candidates` 不重复调用、状态不变）

### Scenario B: 焦点切换（AC2）— 4 条
- **TC-B1**（PRD T-2 前半）：feed `ui_right`×3 → 焦点 0→1→2→0 环绕；每次聚焦高亮跟随
- **TC-B2**：feed `ui_left` → 焦点 0→2（反向环绕）
- **TC-B3**：CLOSED 态 feed 方向/确认键 → 无任何状态变化（输入门控）
- **TC-B4**：REVEALING 态 feed 方向/确认键 → 无状态变化（确认后输入锁定）

### Scenario C: 确认与 apply（AC2）— 5 条
- **TC-C1**（PRD T-2 后半）：选中卡后 feed `ui_accept` → `apply(选中 id)` 恰好一次 → UI 隐藏
- **TC-C2**：先 `ui_right` 再 `ui_accept` → `apply` 的参数为移动后的焦点卡 id
- **TC-C3**：`apply` 返回 false（注入未知 id/耗尽场景）→ UI 保持打开、`paused` 保持 true、无推进调用、`push_warning` 出现
- **TC-C4**：成功 apply 时 `upgrade_applied(id)` 恰好 emit 一次（reveal 锚点信号）
- **TC-C5**：`close()` 重复调用幂等（第二次直接 return）

### Scenario D: 稀有度 reveal（AC3）— 4 条
- **TC-D1**（PRD T-3 前半）：确认前选中卡**无**稀有度名称文本（RarityLabel 空/隐藏）、边框为中性霓虹色（无稀有度色）
- **TC-D2**（PRD T-3 后半）：确认后选中卡边框切 `UPGRADE_RARITY_COLORS[rarity]` + RarityLabel 显示「普通/稀有/传说」
- **TC-D3**：确认后**未被选**的卡保持中性样式（仅所选卡 reveal）
- **TC-D4**：REVEALING 展示时长按 `_reveal_hold`（短注入）→ 超时后自动 close（paused 下计时仍推进，见 §6 边界 7）

### Scenario E: 暂停与恢复（AC4）— 4 条
- **TC-E1**（PRD T-4 前半）：`open()` 后 `get_tree().paused == true`
- **TC-E2**（PRD T-4 后半）：`close()` 后 `get_tree().paused == false`
- **TC-E3**：UI 打开（paused=true）时 feed `ui_cancel` → FSM 状态不变（不切 PAUSED）、UI 保持打开（Escape 屏蔽，回归 `test_pause.gd` 语义）
- **TC-E4**：paused=true 下 REVEALING 计时照常推进（短 hold 注入，close 在 paused 态发生且恢复 paused=false）

### Scenario F: 推进接管（WaveController hold/advance）— 5 条
- **TC-F1**：默认 `settle_hold == false` → 未接线 UI 时 `wall_cleared` 后仍走自动延时推进（回归 `test_wave_cycle.gd` 场景 A 零破坏）
- **TC-F2**：UI `open()` 后 `wave_controller.settle_hold == true`；`wall_cleared` → `settle_wave()` 后**不**自动推进（无 `_advance_wave` 调用、无新 `wave_started`）
- **TC-F3**：UI `close()` → `advance_settlement()` 被调 → `_advance_wave()` 发生（`wave_index +1`、`wave_started` emit）
- **TC-F4**：非结算期调 `advance_settlement()` → no-op（不推进、不崩）
- **TC-F5**：group `wave_controllers` 无成员（WaveController 未挂载）→ UI open/close 不崩；close 不推进（容错 no-op，Flow 5）

### Scenario G: 边界与失败路径 — 5 条
- **TC-G1**：候选 2 张 → 渲染 2 卡（第 3 卡隐藏）、`ui_right` 切换 0→1→0 环绕
- **TC-G2**：候选 0 张 → 不弹 UI、`paused` 保持 false（静默跳过）
- **TC-G3**：终局竞态——`is_run_over() == true` 时 emit `wave_settled` → 不弹 UI、不暂停
- **TC-G4**：reveal 期间终局（apply 使分数到 21）→ close 后 `advance_settlement()` 走 run-over 分支（`end_wave_cycle`，不生成新墙）
- **TC-G5**：`display` 字段全缺失 → 卡片用工作名/effect_desc 兜底渲染（与 TC-A3 互补的极端情形）

### Scenario H: 注册与回归 — 3 条
- **TC-H1**：`run_tests.gd` 注册 "Upgrade Pick UI" 套件（`_run_async`）；`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿
- **TC-H2**：回归 `test_pause.gd` / `test_wave_cycle.gd` / `test_upgrade_pool.gd` / `test_integration_fsm.gd` 全绿（默认 `settle_hold=false` 零破坏）
- **TC-H3**：headless 全流程 smoke——seed → open → 切换 → 确认 → reveal → close 无异常退出（无 Control focus 依赖）

---

## 10. 验收标准映射（Issue #388 五条 AC）

| AC | 验收标准 | 测试锚点 |
|----|---------|---------|
| AC1 | 波间自动弹出三张卡片，焦点默认在第一张 | TC-A1（+ TC-G1 不足 3 张的实渲染） |
| AC2 | 左右方向键切换焦点，确认键应用选中升级并关闭 UI | TC-B1/B2、TC-C1/C2 |
| AC3 | 稀有度以颜色/边框显现，确认后才展示完整稀有度 | TC-D1/D2/D3 |
| AC4 | UI 打开时游戏时间暂停，关闭后恢复 | TC-E1/E2 |
| AC5 | 候选升级来自 `UpgradePool.get_candidates(3)` | TC-A2 |

---

## 11. 验证步骤（implement 执行顺序）

1. **基线**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` —— 既有 18 套件全绿（含 test_upgrade_pool/test_wave_cycle）
2. **Phase 1 后**：重跑 wave 套件 + 全部回归，确认 `settle_hold` 默认 false 零破坏
3. **Phase 2+3 后**：全量 headless（含新 "Upgrade Pick UI" 套件 28 条）+ `check_compile.gd`
4. **手动场景调试兜底**（#384 未落地期间）：临时场景挂 WaveController + mock BreakoutGrid（#414 契约）触发 `wall_cleared` → 目视升级窗口焦点/暂停/reveal/推进（或 mini tree 内手动 `wave_settled.emit`）
5. **PR 说明**：#384 砖墙实现未落地 → 运行时整链路（墙→波次→升级）不可 E2E，本 PR 以 headless 单测 + 手动场景调试覆盖，如实说明
6. #384/#393 组装后：E2E 验证「墙清空 → 升级窗口 → 下一波」全链路；#390 接线时协调共享 `wave_settled` 挂点

---

## 12. 不做的事（范围边界，明确排除）

- **不写/不改任何 runnable 测试文件**（`test_upgrade_pick_ui.gd` 由 implement agent 依 §9 编写；本阶段零测试代码产出）
- **不改** `UpgradePool` / `upgrade_defs.gd` / `GameManager` / `game_state_machine.gd` / `ball.gd` / `paddle.gd` / `BreakoutGrid` 契约
- **不写/改** #395 `upgrade_pool.json`（只读消费 `display`）
- **不扩展 FSM**（#386 决策 1：不新增 UPGRADE 状态）
- **不依赖 Control focus 系统**（`grab_focus`/`focus_neighbor`）——headless 脆弱
- **不实现** #384 砖墙 / #393 场景组装 / #390 波次转场（各自 Issue 范围）
- **不改** PauseOverlay/StartMenu/GameOverScreen 行为（层序共存，互不干扰）

---

*Plan 产出：本文档 + `docs/TASKS/388-upgrade-pick-ui.md`（Phase 1–4 任务清单）。验收以 §10 映射为准。*

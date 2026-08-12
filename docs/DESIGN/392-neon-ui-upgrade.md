# DESIGN: [Feature] 霓虹UI升级 (Neon HUD Upgrade)

> **Parent Issue:** #392
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A + A — GameManager 按类信号（`brick_scored` / `pierce_scored`）+ 三区分区布局 + `ui_neon_style.gd` 共享样式工具（确认 PRD §4 双轴推荐，无偏离）
> **Reference PRD:** docs/PRD/392-neon-ui-upgrade.md（research PR #433，已合并）
> **所有权:** `content_ownership: mechanical`（分区布局/信号接线/样式机制为机械可测；描边粗细、投影偏移、信息条配色、底部单行 vs 左右下角 = taste-draft，交 human-review 定稿）
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386/#389 惯例按 standard 处理）—— 产出 DESIGN + TASKS；**测试仅描述，不写可运行测试代码**
> **Plan 阶段边界:** 本阶段只产出本文档、`docs/TASKS/392-neon-ui-upgrade.md` 与 DESIGN #414 的契约附注，不碰任何 `.gd` / `.tscn` / `project.godot` 文件 —— 下列全部内容为 implement agent 的契约。

---

## 1. 概述

Mini Pong（720×1280 竖屏，Godot 4.7.1）的 HUD 停留在 #292 时代：顶部居中一行两个总分 Label，无霓虹描边、无投影、无拆砖/穿墙分区、无波次号、无剩余砖数。在双得分制（#385）、波次循环（#386）、动态雨幕（#389）全部落地后，本 Issue 按 PLAN-rogue-pong §3.3 已拍板的 UI 规格升级 HUD：

- **霓虹描边 + 微投影**：全部数字 Label 经共享样式工具设置 `font_outline_color/outline_size` + `font_shadow_color/shadow_offset_x/y`（默认字体 + 主题覆盖，headless 安全、零 license 成本）（AC1）
- **三区分区**：顶部 AI 红色区（y∈[12,84]：AI 总分 + 拆/穿双子区 + 中立信息条第二行）、底部玩家蓝色区（y∈[1252,1280]，玩家挡板下方单行：玩家总分 + 拆/穿双子区）（AC2/AC4）
- **波次号 + 剩余砖数**：波次号消费 `GameManager.wave_started` + 初始 `wave_index`；剩余砖数容错消费 BreakoutGrid 契约（#384，`brick_destroyed` / `wall_cleared` / 契约增补 `wall_generated`），#384 实现未落地时显示占位符且不报错（AC3）
- **信号驱动零轮询**：总分/拆砖/穿墙/波次/剩余砖数全部由信号触发更新；`game_hud.gd` 无 `_process`（AC5）

### 设计哲学

1. **Approach A 确认（数据轴）**：GameManager 新增 `brick_scored(side)` / `pierce_scored(side)` 两个按类信号，`add_score()` 内按 kind emit —— 唯一满足 AC5 字面语义（「所有更新走信号」）的方案；信号级可测；纯增量（既有 `score_changed` / `wave_started` 零改动，延续 #386 向 GameManager 增加信号先例）。否决 Approach B（隐式依赖「先计数后 emit」顺序，无显式信号可断言）与 Approach C（轮询，直接违反 AC5）。
2. **Approach A 确认（布局轴）**：三区分区 + `ui_neon_style.gd` 静态样式工具 —— 唯一同时满足 AC2（顶红底蓝、拆穿双区）与 AC3 的结构方案；样式工具为单一事实源，#388/#390/#391 直接复用保证全 UI 视觉一致。否决 Approach B（顶部单行堆叠，违反 AC2 且信息密度过高）与 Approach C（第三方字体/shader，违背 PLAN §3.3 已拍板路线）。
3. **容错消费 #384**：`get_node_or_null("../BreakoutGrid")` + `has_signal/has_method` 双守卫（同 ScoringManager/WaveController 既有模式）——#384 实现未落地、#393 未接线时游戏不崩，剩余砖数显示「—」占位并 `push_warning` 一次；#393 接线后自动生效。
4. **契约增补 `wall_generated`**：向 #384 DESIGN 附注增补 `wall_generated(remaining: int)` 信号（#384 实现未落地，增补零成本），作为剩余砖数新墙刷新主路径；未采纳则回退 `wave_started` handler 内 `call_deferred` 读 `remaining_bricks`（功能等价，双路径都实现、都测试）。
5. **单份 HUD 定义**：Main.tscn 改为实例化 `ui_game_hud.tscn`（节点名保持 `GameHUD`，layer 统一为 1），消除 #292 遗留的「独立场景 layer=0 vs 内联副本 layer=1」双份维护；FSM/StartMenu/test_main_scene 的 `GameHUD` 引用全部不变。
6. **测试即验收**：测试用例描述见 §9；implement agent 写 `test_hud.gd` 并注册进 `run_tests.gd`；theme override 断言一律用 `label.get("theme_override_...")`（GDD16 已知 headless 下 `get_theme_font_size` 返回 0 的坑）；`godot --headless --script tests/run_tests.gd` 全绿（基线 1487 用例零回归）。

### 1.1 关键事实（plan agent 已对照源码核实）

| 事实 | 核实结果 |
|------|---------|
| `game_hud.gd` 现状 | 34 行：`@onready` 两个 Label（`$MarginContainer/HBoxContainer/PlayerScoreLabel` / `AIScoreLabel`）；`_ready` 连接 `score_changed` → `_on_score_changed` 只更新两行文本；`visible=false`；**无任何 outline/shadow 主题覆盖、无分区、无波次/剩余砖数、无 `_process`** |
| `ui_game_hud.tscn` 现状 | 独立场景：CanvasLayer **layer=0**、`visible=false`；MarginContainer(anchors_preset=2, margin_top=20/left=40/right=-40) > HBoxContainer(alignment=1, separation=60) > 两个 Label（font_size=28，modulate 蓝/红） |
| `Main.tscn` 内联副本 | GameHUD 节点内联（非实例化）：CanvasLayer **layer=1**、`visible=false`，子树与 ui_game_hud.tscn 同构（MarginContainer offset 全 0 + offset_right=720）——**layer 不一致（0 vs 1）且双份定义** |
| `game_manager.gd` 信号现状 | 只有 `score_changed(player_score, ai_score)` / `match_over(winner)` / `wave_started(wave_index)` / `wave_settled(wave_index)` —— **无 `brick_scored` / `pierce_scored`**（纯新增） |
| `add_score` 内部顺序 | `_bump_count()`（更新拆砖/穿墙计数）→ `score_changed.emit()` → `_check_run_end()`；`_is_run_over` / `amount<=0` / 非法 winner 早退（无信号泄漏）—— 按类信号插在 `_bump_count` 之后、`score_changed.emit` 之前，HUD 在 handler 内读 `get_brick_count()/get_pierce_count()` 必然拿到最新值（PRD §4.1 Approach A 可行性依据） |
| 查询 API（#385） | `get_brick_count(side)` / `get_pierce_count(side)` 已存在（AC5） |
| `wave_started` 时序（#386） | `begin_wave()` 内 emit `wave_started`，**先于** WaveController `_advance_wave()` 的 `generate_wave()`（同帧）—— HUD 不能在 `wave_started` handler 同步读新墙剩余数（契约缺口，§4 Flow 2） |
| BreakoutGrid（#384） | **实现未落地**：`mini-pong/gdscripts/` 无 `breakout_grid.gd` / `brick.gd` → 只能 `get_node_or_null` 容错，不能 `preload`；契约（DESIGN #414）：`remaining_bricks`（只读 var）、`brick_destroyed(brick, pos)`、`wall_cleared()`（每墙一次守卫）、`generate_wave(thickness, layout, seed)` —— **无 `wall_generated` 信号**（附注增补，§3.3） |
| `constants.gd` 现状 | 有 `PLAYER_NEON_BLUE`(#4a90d9) / `AI_NEON_RED`(#ff3355)（#289）、`BRICK_SCORE=1`/`PIERCE_SCORE=3`/`WIN_SCORE=21`（#385）、`WAVE_*` 组（#386）、`RAIN_*` 组（#389）—— **无 `HUD_*` 组** |
| 节点名契约 | `game_state_machine.gd` L28 `@onready var game_hud: CanvasLayer = $"../GameHUD"`；`start_menu.gd` L86 `_get_sibling("GameHUD")` —— **节点名必须保持 `GameHUD`** |
| 既有测试锚点 | `test_main_scene.gd` TC1-11（`has_node("GameHUD")` 存在）、TC20-11（`GameHUD/MarginContainer.offset_right == 720`）；`test_ui_system.gd` TC6（实例化 ui_game_hud.tscn：visible=false / PlayerScoreLabel / AIScoreLabel 路径与初值）、TC9（脚本级实例化 + `_on_score_changed` 文本）、TC15-6/7/8/9（Main.tscn GameHUD 为 CanvasLayer、visible=false、layer=1）—— 布局改造后 TC6/TC9/TC15 按新路径同步，TC1-11/TC20-11 语义保留 |
| 测试注册 | `run_tests.gd` 模式：`_run("res://tests/test_X.gd", "Name")`（已注册 16+ 套件，含 test_dual_scoring.gd / test_wave_cycle.gd / test_rain.gd） |
| E2E | `mini-pong/e2e_shots.json` loop 原型 3 shots；`match: ["gdscripts/.*\.gd", ...]` → game_hud.gd 改动必命中；`02_midgame`（PLAYING 态，require player_score>=1）截图将包含新 HUD；4 重断言（非黑/色数/主题色 4a90d9/帧间差异）需实测（Spike 1） |
| 引擎 | Godot 4.7.1（game-env/manifest.yaml）；默认分支 `main` |

### 1.2 与 PRD 的差异决策（plan 定稿，PRD §8 交接点待决项）

| PRD 待决项 | 本设计定稿 | 理由 |
|-----------|-----------|------|
| 按类信号 emit 顺序（PRD §3.2「之前或之后均可」） | **`_bump_count` 之后、`score_changed.emit` 之前** | 确定性顺序便于测试断言（子区先于总分更新，渲染无耦合）；不依赖「先计数后 emit」之外的新隐式契约 |
| 信息条位置（PRD §4.2「挂顶部区下方或并入顶部区第二行」） | **并入顶部区第二行**（与 AI 拆/穿子区同行，HUD_INFO_COLOR 中立色） | 保持单一顶部安全区锚点（y∈[12,84]），避免第三锚点引入新的遮挡面；信息密度符合「90 年代地摊文艺」克制约束 |
| `wall_generated` 契约增补（PRD §8 决策 3） | **采纳为主路径 + call_deferred 回退双实现** | 有 `wall_generated` 用信号（首选）；无则 `wave_started` handler 内 `call_deferred` 读 `remaining_bricks`（帧末 generate_wave 已执行）——两条路径都实现、都测试（PRD §5 边界 2「测试钉两种路径」） |
| 底部区布局（PRD §4.2「单行 vs 左右下角双子区」） | **单行「总分 + 拆 x · 穿 y」**（font ~20px）；左右下角双子区（x<290 / x>430）为 taste 备选 | 28px 高度单行在默认字体下行高可容纳；Spike 2 截图实测兜底，容不下再切备选（结构不变，仅锚点/字号 taste 微调） |
| `ui_game_hud.tscn` layer（PRD §1 双份定义 layer 不一致） | **统一 layer=1**（与 Main.tscn 内联副本一致，TC15-9 语义保留） | 消除双份不一致；HUD 在 L3（layer=1）位于雨幕 L0 之上（结构性可读，AC1） |
| Main.tscn 改造方式（PRD §8 决策 5） | **实例化 `ui_game_hud.tscn`**（节点名 `GameHUD` 不变）；若与 #393 组装冲突则保持内联但两处子树一致 | 消除双份维护（PRD §5 失败路径 3）；实例化后 Main.tscn 只留一行 instance + 覆盖 layer=1 |
| 样式常量数值 | `HUD_OUTLINE_SIZE=6`、`HUD_SHADOW_OFFSET=(2,2)`、`HUD_SHADOW_COLOR=半透明黑`、`HUD_INFO_COLOR=中性` 进 constants.gd，**机械占位** | 描边粗细/投影偏移/信息条配色为 taste-draft（human-review 定稿），常量单一事实源便于后调（PRD §8 决策 6） |

---

## 2. 现有组件修改 — 详细设计

### 2.1 `mini-pong/gdscripts/constants.gd`（修改 — HUD 常量组）

新增「── Neon HUD (#392) ──」常量组（置于 Colors 组之后）：

```gdscript
# ── Neon HUD (#392) ──
# 霓虹 HUD 样式/布局常量 (PLAN-rogue-pong §3.3; mechanical; 描边粗细/投影偏移/信息条配色 = taste-draft 可调)
const HUD_OUTLINE_SIZE: int = 6                    # 霓虹描边粗细 (px) — taste-draft 占位
const HUD_SHADOW_OFFSET: Vector2 = Vector2(2, 2)   # 微投影偏移 (px) — taste-draft 占位（微投影非重阴影）
const HUD_SHADOW_COLOR: Color = Color(0, 0, 0, 0.6)  # 投影色：半透明黑（克制）
const HUD_INFO_COLOR: Color = Color(0.82, 0.82, 0.88, 1.0)  # 中立信息条（波次/剩余砖）—— taste-draft 可调
const HUD_FONT_SIZE_MAIN: int = 28                # 总分大字
const HUD_FONT_SIZE_SUB: int = 20                 # 子区/信息条小字
const HUD_TOP_BAND_TOP: float = 12.0              # 顶部区上缘（安全区，AC4）
const HUD_TOP_BAND_BOTTOM: float = 84.0           # 顶部区下缘
const HUD_BOTTOM_BAND_TOP: float = 1252.0         # 底部区上缘（玩家挡板 1230–1250 下方）
const HUD_BOTTOM_BAND_BOTTOM: float = 1280.0      # 底部区下缘（屏幕底）
const HUD_PLACEHOLDER: String = "—"               # #384 未接线时剩余砖数占位符
```

### 2.2 `mini-pong/gdscripts/game_manager.gd`（修改 — 按类信号，纯增量）

**职责**：`add_score()` 内按 kind 发出按类信号，供 HUD 双区（拆砖/穿墙）独立订阅（AC5）。既有信号/API 零改动。追加：

```gdscript
# ── Neon HUD (#392) ──
signal brick_scored(side: String)    # 拆砖得分（#385 kind="brick"）→ HUD 拆砖子区（AC5）
signal pierce_scored(side: String)   # 穿墙得分（#385 kind="pierce"）→ HUD 穿墙子区（AC5）
```

`add_score()` 内、`_bump_count()` 之后、`score_changed.emit()` 之前插入（顺序确定性，§1.2）：

```gdscript
	# ── Neon HUD (#392)：按类信号（_bump_count 之后、score_changed 之前；boundary 不触发）──
	match kind:
		"brick":
			brick_scored.emit(winner)
		"pierce":
			pierce_scored.emit(winner)
		_:
			pass
```

不改动：`score_changed` / `match_over` / `wave_started` / `wave_settled`、`reset_match()`、`_check_run_end()`、查询 API。`reset_match()` 无需新增重置（按类信号无状态，计数重置已由 `_bump_count` 对应字段覆盖）。

### 2.3 `mini-pong/gdscripts/game_hud.gd`（重构 — 三区 + 信号接线 + 容错）

**职责**：三区 Label 引用 + 霓虹样式 + 信号驱动更新（零轮询）+ #384 容错消费。保留 #292 的 `visible=false`（FSM `_set_ui("hud")` / StartMenu 控制显隐）与「节点缺失则跳过」守卫（test_ui_system TC9 脚本级实例化依赖）。

```gdscript
extends CanvasLayer
## GameHUD — 三区霓虹 HUD（#392）：顶部 AI 红区 / 底部玩家蓝区 / 中立信息条。
## 全部更新走信号（AC5）；BreakoutGrid 容错消费（#384 契约，#393 接线后自动生效）。
## Parent Issue: #292, #392

const CONSTS = preload("res://gdscripts/constants.gd")
const UiNeonStyle = preload("res://gdscripts/ui_neon_style.gd")

# ── Node References（三区，§2.4 场景结构）──
@onready var ai_total_label: Label = $MarginContainer/TopBand/AITotalLabel
@onready var ai_brick_label: Label = $MarginContainer/TopBand/SubRow/AIBrickLabel
@onready var ai_pierce_label: Label = $MarginContainer/TopBand/SubRow/AIPierceLabel
@onready var wave_label: Label = $MarginContainer/TopBand/SubRow/WaveLabel
@onready var bricks_label: Label = $MarginContainer/TopBand/SubRow/BricksLabel
@onready var player_total_label: Label = $MarginContainer/BottomBand/PlayerTotalLabel
@onready var player_brick_label: Label = $MarginContainer/BottomBand/PlayerBrickLabel
@onready var player_pierce_label: Label = $MarginContainer/BottomBand/PlayerPierceLabel
@onready var breakout_grid: Node = get_node_or_null("../BreakoutGrid")   # #384 容错：#393 接线前为 null

var _grid_connected: bool = false   # 剩余砖数数据源是否可用（push_warning 一次守卫）

func _ready() -> void:
	if not ai_total_label or not player_total_label:
		return                       # Guard：脚本单独实例化（测试）时跳过（#292 惯例）
	_apply_neon()
	_connect_signals()
	_seed_initial()
	visible = false                  # Hidden until StartMenu triggers show

func _apply_neon() -> void:
	# AC1：所有数字 Label 霓虹描边 + 微投影（样式单一事实源，§3.1）
	UiNeonStyle.apply(ai_total_label, CONSTS.AI_NEON_RED)
	UiNeonStyle.apply(ai_brick_label, CONSTS.AI_NEON_RED, {"outline_size": 4})
	UiNeonStyle.apply(ai_pierce_label, CONSTS.AI_NEON_RED, {"outline_size": 4})
	UiNeonStyle.apply(player_total_label, CONSTS.PLAYER_NEON_BLUE)
	UiNeonStyle.apply(player_brick_label, CONSTS.PLAYER_NEON_BLUE, {"outline_size": 4})
	UiNeonStyle.apply(player_pierce_label, CONSTS.PLAYER_NEON_BLUE, {"outline_size": 4})
	UiNeonStyle.apply(wave_label, CONSTS.HUD_INFO_COLOR, {"outline_size": 4})
	UiNeonStyle.apply(bricks_label, CONSTS.HUD_INFO_COLOR, {"outline_size": 4})

func _connect_signals() -> void:
	if is_instance_valid(GameManager):
		if GameManager.has_signal("score_changed"):
			GameManager.score_changed.connect(_on_score_changed)
		if GameManager.has_signal("brick_scored"):
			GameManager.brick_scored.connect(_on_brick_scored)
		if GameManager.has_signal("pierce_scored"):
			GameManager.pierce_scored.connect(_on_pierce_scored)
		if GameManager.has_signal("wave_started"):
			GameManager.wave_started.connect(_on_wave_started)
	# BreakoutGrid 容错消费（#384 契约）
	if breakout_grid != null:
		if breakout_grid.has_signal("brick_destroyed"):
			breakout_grid.brick_destroyed.connect(_on_brick_destroyed)
			_grid_connected = true
		if breakout_grid.has_signal("wall_cleared"):
			breakout_grid.wall_cleared.connect(_on_wall_cleared)
		if breakout_grid.has_signal("wall_generated"):
			breakout_grid.wall_generated.connect(_on_wall_generated)   # 契约增补主路径
	if not _grid_connected:
		push_warning("GameHUD: BreakoutGrid 未接线（#384/#393），剩余砖数显示占位符")
		bricks_label.text = "剩余 " + CONSTS.HUD_PLACEHOLDER

func _seed_initial() -> void:
	# 无信号时从 GameManager 状态播种（#292 惯例；AC3 初始波次号）
	_on_score_changed(GameManager.player_score, GameManager.ai_score)
	_on_brick_scored("player")
	_on_brick_scored("ai")
	_on_pierce_scored("player")
	_on_pierce_scored("ai")
	wave_label.text = "第 %d 波" % GameManager.wave_index
	if _grid_connected:
		call_deferred("_refresh_bricks")

# ── Signal Handlers（全部信号驱动，无 _process 轮询）──
func _on_score_changed(player_score: int, ai_score: int) -> void:
	player_total_label.text = "玩家 %d" % player_score
	ai_total_label.text = "AI %d" % ai_score

func _on_brick_scored(side: String) -> void:
	# 即时单读查询 API（add_score 先计数后 emit，读必最新；非轮询）
	if side == "player":
		player_brick_label.text = "拆 %d" % GameManager.get_brick_count("player")
	else:
		ai_brick_label.text = "拆 %d" % GameManager.get_brick_count("ai")

func _on_pierce_scored(side: String) -> void:
	if side == "player":
		player_pierce_label.text = "穿 %d" % GameManager.get_pierce_count("player")
	else:
		ai_pierce_label.text = "穿 %d" % GameManager.get_pierce_count("ai")

func _on_wave_started(index: int) -> void:
	wave_label.text = "第 %d 波" % index
	if _grid_connected and not breakout_grid.has_signal("wall_generated"):
		call_deferred("_refresh_bricks")   # 回退路径：帧末（generate_wave 已执行）读新墙剩余数

func _on_brick_destroyed(_brick: Node2D, _pos: Vector2) -> void:
	_refresh_bricks()                      # 即时单读 grid.remaining_bricks（AC3）

func _on_wall_cleared() -> void:
	bricks_label.text = "剩余 0"            # 整墙打空 → 归零

func _on_wall_generated(remaining: int) -> void:
	bricks_label.text = "剩余 %d" % remaining   # 新墙总数（契约增补主路径）

func _refresh_bricks() -> void:
	if breakout_grid == null:
		return
	var remaining = breakout_grid.get("remaining_bricks")
	bricks_label.text = "剩余 %d" % (int(remaining) if remaining != null else 0)
```

**说明**：`get("remaining_bricks")` 走 #384 只读 var 契约（`get()` 容错，属性缺失返回 null → 显示 0 不崩）。

### 2.4 `mini-pong/scenes/ui_game_hud.tscn`（重排 — 三区分区）

**节点结构**（实现期落地；`layer` 统一为 1，消除双份 layer 不一致）：

```
GameHUD (CanvasLayer, layer=1, visible=false, script=game_hud.gd)
└── MarginContainer (anchors_preset=15 全宽, offset_right=720 —— 保留 TC20-11 语义)
    ├── TopBand (VBoxContainer, anchors 顶部: offset_top=12, offset_bottom=84 → y∈[12,84])
    │   ├── AITotalLabel (Label, "AI 0", 居中, font HUD_FONT_SIZE_MAIN)
    │   └── SubRow (HBoxContainer, alignment=1 居中, separation=24)
    │       ├── AIBrickLabel (Label, "拆 0", font HUD_FONT_SIZE_SUB)
    │       ├── AIPierceLabel (Label, "穿 0", font HUD_FONT_SIZE_SUB)
    │       ├── WaveLabel (Label, "第 0 波", font HUD_FONT_SIZE_SUB)
    │       └── BricksLabel (Label, "剩余 —", font HUD_FONT_SIZE_SUB)
    └── BottomBand (HBoxContainer, anchors 底部: offset_top=-28, offset_bottom=0 → y∈[1252,1280])
        ├── PlayerTotalLabel (Label, "玩家 0", font HUD_FONT_SIZE_SUB)
        ├── PlayerBrickLabel (Label, "拆 0", font HUD_FONT_SIZE_SUB)
        └── PlayerPierceLabel (Label, "穿 0", font HUD_FONT_SIZE_SUB)
```

- 配色由 `game_hud.gd._apply_neon()` 统一设置（AiNeon 红 / 玩家蓝 / 信息条中立），tscn 内不散落 modulate（消除 #289 时代「tscn 配色 + 脚本配色」双源）
- `autowrap` 关闭 + `clip_text` 关闭（底部 28px 单行，font 20 默认行高可容纳；Spike 2 实测兜底）

### 2.5 `mini-pong/scenes/Main.tscn`（修改 — 实例化 ui_game_hud.tscn）

- 删除内联 GameHUD 子树（MarginContainer/HBoxContainer/两个 Label），替换为：

```
[node name="GameHUD" parent="." instance=ExtResource("<ui_game_hud>")]
layer = 1
```

- 新增 `[ext_resource type="PackedScene" path="res://scenes/ui_game_hud.tscn" id="<id>"]`
- 节点名 `GameHUD` 不变（FSM `$"../GameHUD"` / StartMenu `_get_sibling("GameHUD")` / test_main_scene TC1-11 零改动）
- `layer = 1` 显式覆盖（与 ui_game_hud.tscn 默认一致，双保险）；`visible=false` 由 tscn 自带
- TC20-11 语义保留：MarginContainer 全宽（offset_right=720）不变，断言无需改

### 2.6 受影响测试文件（implement agent 改造清单）

| 文件 | 改动 |
|------|------|
| `mini-pong/tests/test_hud.gd` | **新建** —— §9 场景 A–F 的可运行实现 |
| `mini-pong/tests/test_game_manager.gd` | **扩展** —— `brick_scored` / `pierce_scored` 信号用例（kind 触发、boundary 不触发、非法 winner 不触发，§9 Scenario E-5/G-3） |
| `mini-pong/tests/test_ui_system.gd` | **同步** —— TC6（Label 路径改三区新路径 + 拆/穿/波次/剩余 Label 存在性）、TC9（`_on_score_changed` 文本断言改新文本格式）、TC15（layer=1 断言不变） |
| `mini-pong/tests/test_main_scene.gd` | **同步** —— TC1-11（GameHUD 存在）不变；TC20-11（offset_right==720）语义保留（MarginContainer 全宽） |
| `mini-pong/tests/run_tests.gd` | **修改** —— 注册 `test_hud.gd` |
| `docs/DESIGN/384-breakout-grid-brick-wall.md` | **附注** —— `wall_generated` 契约增补（§3.3） |

---

## 3. 新建文件（实现期）

### 3.1 `mini-pong/gdscripts/ui_neon_style.gd`（新建 — 霓虹样式单一事实源）

```gdscript
extends RefCounted
## 霓虹 Label 样式单一事实源（#392）。
## PLAN-rogue-pong §3.3：默认字体 + 主题覆盖描边 + 微投影（headless 安全、零 license）。
## 本 Issue HUD 使用；#388/#390/#391 复用（全 UI 视觉一致性）。
class_name UiNeonStyle

const CONSTS = preload("res://gdscripts/constants.gd")

static func apply(label: Label, color: Color, opts := {}) -> void:
	# 主色（霓虹源色）
	label.add_theme_color_override("font_color", color)
	# 霓虹描边
	label.add_theme_color_override("font_outline_color", opts.get("outline_color", color))
	label.add_theme_constant_override("outline_size", opts.get("outline_size", CONSTS.HUD_OUTLINE_SIZE))
	# 微投影（克制：小偏移 + 半透明黑，非重阴影）
	label.add_theme_color_override("font_shadow_color", opts.get("shadow_color", CONSTS.HUD_SHADOW_COLOR))
	var off: Vector2 = opts.get("shadow_offset", CONSTS.HUD_SHADOW_OFFSET)
	label.add_theme_constant_override("shadow_offset_x", int(off.x))
	label.add_theme_constant_override("shadow_offset_y", int(off.y))
```

- 纯静态函数、无状态；`outline_size` 小字号（20px）可用 `opts` 覆盖为 4（Spike 1 实测糊字则下调，taste 参数）
- headless 安全：走标准 `theme_override_*` 属性，测试用 `get()` 读取（GDD16）

### 3.2 `mini-pong/tests/test_hud.gd`（新建 — 实现期）

隔离测试，**不依赖 #384 落地**：mock BreakoutGrid（普通 Node 挂 mock 脚本：实现 `brick_destroyed` / `wall_cleared` / `wall_generated` 信号 + `remaining_bricks` 属性 + 调用记录，模拟 #414 契约）；场景侧实例化 `ui_game_hud.tscn` 断言布局/样式/接线。测试描述见 §9。

### 3.3 `docs/DESIGN/384-breakout-grid-brick-wall.md`（附注 — `wall_generated` 契约增补）

在文件末尾追加附录（**仅文档，不改 #384 既有契约内容**）：

```markdown
## 附录 A: #392 契约增补（2026-08-13, plan agent）

**新增信号 `wall_generated(remaining: int)`**（#392 霓虹 HUD 需求，PRD #392 §4.3 推荐；#384 实现未落地，增补零成本）：

| 信号 | 参数 | 消费方 | 语义 |
|------|------|--------|------|
| `wall_generated` | `(remaining: int)` | #392 HUD 剩余砖数 | `generate_wave()` 完成新墙生成后发出，负载 = 新墙砖总数 |

- 触发点：`generate_wave()` 末尾（清空旧墙 → 生成新砖 → 重置计数/守卫 → `remaining_bricks = rows * cols` → emit）
- 语义：解决 §4.1 契约缺口 —— `wave_started`（#386）先于 `generate_wave()`，HUD 无法在波次开始时同步感知新墙剩余数；本信号让新墙总数在生成瞬间即可由信号消费（AC3）
- 守卫：与 `wall_cleared` 同规则（每墙一次，`generate_wave()` 重置）
- 兼容：纯新增信号，不影响 `brick_destroyed` / `wall_cleared` / `remaining_bricks` / `generate_wave` 既有契约
- 回退：若实现方不采纳，HUD 侧 `wave_started` handler 内 `call_deferred` 读 `remaining_bricks`（功能等价，DESIGN #392 §5 失败路径 4）
```

---

## 4. 数据流

### Flow 1: 拆砖 / 穿墙得分更新（AC2/AC5）

```
ScoringManager（#385 既有）判定得分归属
    ▼
GameManager.add_score(winner, amount, kind)
    ├─ guard: _is_run_over / amount<=0 / 非法 winner → return（无信号泄漏）
    ├─ player_score/ai_score += amount
    ├─ _bump_count(winner, kind)                    # 先计数（读必最新的依据）
    ├─ [新增] brick_scored.emit(winner)   ──► HUD _on_brick_scored(side)  ──► 「拆 x」子区（对应方，即时单读 get_brick_count）
    ├─ [新增] pierce_scored.emit(winner)  ──► HUD _on_pierce_scored(side) ──► 「穿 x」子区（对应方，即时单读 get_pierce_count）
    ├─ score_changed.emit(p, a)          ──► HUD _on_score_changed ──► 总分 Label ×2
    └─ _check_run_end() → match_over（#385 既有，终局路径不变）
boundary 兜底分：只走 score_changed（总分更新），不触发按类信号（双区不动）
```

### Flow 2: 波次号 + 剩余砖数更新（AC3）

```
GameManager.begin_wave()（#386）──► wave_started.emit(wave_index) ──► HUD _on_wave_started
    ├─ wave_label.text = "第 N 波"
    └─ 剩余砖数刷新（两条路径，§1.2）:
        ├─ 主路径: BreakoutGrid.generate_wave() 末尾 emit wall_generated(remaining)
        │            ──► HUD _on_wall_generated → bricks_label = "剩余 remaining"
        └─ 回退路径（无 wall_generated 信号）: HUD call_deferred("_refresh_bricks")
                    帧末（generate_wave 已执行）读 grid.remaining_bricks → bricks_label
游戏进行中:
    brick_destroyed(brick, pos) ──► HUD _on_brick_destroyed → _refresh_bricks()（即时单读 remaining_bricks）
    wall_cleared()               ──► HUD _on_wall_cleared → bricks_label = "剩余 0"
```

### Flow 3: 初始播种（无信号期，#292 惯例）

```
_ready():
    _apply_neon()   # 8 个数字 Label 全部套霓虹样式（AC1）
    _connect_signals()
    _seed_initial():
        _on_score_changed(GameManager.player_score, GameManager.ai_score)   # 总分
        _on_brick_scored("player"/"ai") + _on_pierce_scored("player"/"ai")  # 双区计数
        wave_label.text = "第 %d 波" % GameManager.wave_index                # 波次号
        grid 已连接 → call_deferred(_refresh_bricks) / 未连接 → "剩余 —"
    visible = false   # FSM/StartMenu 控制显隐（#292 惯例不变）
```

### Flow 4: #384 未接线容错（#393 接线前）

```
_ready(): breakout_grid == null（或无 brick_destroyed 信号）→ push_warning 一次，bricks_label="剩余 —"
       其余区（总分/拆/穿/波次）全部正常更新（数据源为 GameManager，#385/#386 已落地）
#393 接线后：get_node_or_null("../BreakoutGrid") 命中 → 信号连接 → 剩余砖数自动生效（零改动）
```

---

## 5. 边界条件与失败路径

### 边界条件（≥5）

1. **#384 未接线期（当前 main 状态）** — `get_node_or_null("../BreakoutGrid") == null` → 剩余砖数显示「—」+ `push_warning` 一次（`_grid_connected` 守卫防重复 warning）；其他区正常（PRD §5 边界 1）
2. **`wave_started` 先于 `generate_wave` 发出** — `wave_started` handler 内同步读 `remaining_bricks` 是旧值 → 主路径等 `wall_generated`（新墙总数）；回退路径 `call_deferred` 帧末读（PRD §5 边界 2，双路径都测试）
3. **雨幕可读性** — HUD 在 L3（layer=1）位于 L0 雨幕（layer=0）之上，雨滴永远绘制在 HUD 之下；描边+投影提供对亮球/bloom 的对比度；Spike 1 用 02_midgame 截图实测（AC1）
4. **boundary 兜底分**（无墙期普通出界 1 分）— 触发 `score_changed` 但不触发按类信号；总分更新、双区不动（PRD §5 边界 4）
5. **终局后信号** — `add_score` 在 `_is_run_over` 时直接 return（#385 守卫）→ 无信号泄漏；HUD 保持终局分数，GAME_OVER 屏接管（PRD §5 边界 5）
6. **初始播种** — `_ready` 时无信号：从 `GameManager.player_score/ai_score/wave_index` + 查询 API 播种（#292 惯例）；grid 未接线时剩余砖数播种为「—」（PRD §5 边界 6）
7. **同帧拆砖 + 穿墙** — ScoringManager 帧守卫（#385 AC4）保证同帧只计一种；HUD 按收到的信号顺序更新即可，无冲突（PRD §5 边界 7）
8. **字号/行高** — 底部区 28px 高单行（font 20px）；若默认字体行高超界：Label 关闭 `autowrap` + 保持单行，或切左右下角双子区布局（x<290 / x>430 避开挡板）—— taste 决策，Spike 2 截图确认（PRD §5 边界 8）

### 失败路径（≥3）

1. **E2E 断言因新 HUD 变红**（02_midgame 新增红区/信息条影响色数/帧间差异断言）→ 先调 shot 参数（settle_frames/断言阈值），不删 HUD 内容；若主题色断言（4a90d9）被 AI 红区（ff3355）干扰，检查断言实现是否允许多主题色（PRD §5 失败路径 1）
2. **headless 下 theme override 不可读**（GDD16 已知坑：`get_theme_font_size` 返回 0）→ 测试一律用 `label.get("theme_override_...")` 断言（既有约定）；`ui_neon_style.apply` 走标准主题覆盖，headless 安全（PRD §5 失败路径 2）
3. **Main.tscn 内联 HUD 与 ui_game_hud.tscn 不同步**（双份维护风险）→ 本 Issue 改为 Main.tscn 实例化（节点名 GameHUD 不变）；若实例化遇阻（#393 组装范围冲突），至少保证两处子树一致 + test_main_scene TC20-11 兜底（PRD §5 失败路径 3）
4. **`wall_generated` 契约增补未被 #384 实现采纳** → 回退路径：HUD 在 `wave_started` handler 内 `call_deferred` 读 `grid.remaining_bricks`（边界 2），功能等价，不阻塞（PRD §5 失败路径 4）
5. **底部区与玩家挡板视觉重叠**（安全区计算误差）→ Spike 2 截图实测 + 安全区断言兜底；taste 阶段允许微调底部区锚点（±4px）（PRD §5 失败路径 5）

---

## 6. 每场景配置（安全区，AC4）

| 区域 | 锚点/偏移 | y 范围 | 与主体关系 | 归属 |
|------|-----------|--------|-----------|------|
| 顶部 AI 区（TopBand） | anchor_top=0, offset_top=12, offset_bottom=84 | y∈[12,84] | 与 AI 挡板（y∈[30,50]）仅上缘轻微交叠或完全避开（与现状 HUD 一致，可接受）；远离砖墙 y=640 | `ui_game_hud.tscn` |
| 底部玩家区（BottomBand） | anchor_bottom=1, offset_top=-28, offset_bottom=0 | y∈[1252,1280] | 整体在玩家挡板（y∈[1230,1250]）**下方**，零交集 | `ui_game_hud.tscn` |
| 中立信息条（波次/剩余） | 并入 TopBand 第二行（SubRow） | y∈[12,84] | 与 AI 区同带，不新增锚点 | `ui_game_hud.tscn` |

- 两区均全宽（x∈[0,720]），不遮挡球道（球道 x∈[10,710] 无 HUD 元素伸入）
- 砖墙主体 y=640 与两区均无交集（720px 高差）

---

## 7. 集成点

> 状态约定：⬜ = pending（实现 agent 接线后更新）；✅ = 已存在/已连接。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| `GameManager.score_changed(p,a)` → 总分 Label ×2 | game_hud._on_score_changed | #292 既有 → 本 Issue 保留 | signal connect（`has_signal` 守卫） | ✅ 已存在（保留） |
| `GameManager.brick_scored(side)` → 拆砖子区 | game_hud._on_brick_scored | 本 Issue 新增（#385 kind 源） | signal connect（GameManager 侧 emit） | ⬜ pending |
| `GameManager.pierce_scored(side)` → 穿墙子区 | game_hud._on_pierce_scored | 本 Issue 新增（#385 kind 源） | signal connect（GameManager 侧 emit） | ⬜ pending |
| `GameManager.wave_started(index)` → 波次号 | game_hud._on_wave_started | #386 既有信号，本 Issue 消费 | signal connect（`has_signal` 守卫） | ✅ 已发出（消费本 Issue） |
| `BreakoutGrid.brick_destroyed(brick,pos)` → 剩余砖数 | game_hud._on_brick_destroyed | #384 契约（实现未落地） | signal connect（`get_node_or_null("../BreakoutGrid")` + `has_signal` 守卫） | ⬜ pending（#393 接线后生效） |
| `BreakoutGrid.wall_cleared()` → 剩余砖数归零 | game_hud._on_wall_cleared | #384 契约 | signal connect（同上容错） | ⬜ pending |
| `BreakoutGrid.wall_generated(remaining)` → 新墙剩余数 | game_hud._on_wall_generated | #384 契约增补（§3.3） | signal connect（`has_signal` 守卫；无则 call_deferred 回退） | ⬜ pending |
| `ui_neon_style.gd` → #388/#390/#391 视觉复用 | UiNeonStyle.apply | #388 升级卡 / #390 转场 / #391 失败屏 | 静态工具复用（视觉一致性） | ✅ 已就绪（消费归下游） |
| Main.tscn GameHUD 实例化 | ui_game_hud.tscn | 本 Issue 内部（消除双份定义） | PackedScene instance（节点名 GameHUD 不变） | ⬜ pending |

---

## 8. 实施阶段

| Phase | 优先级 | 组件 | 估算 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | `constants.gd` HUD_* 常量组 + `ui_neon_style.gd` 新建（样式工具） | 0.5 天 |
| Phase 2 | P0 | `game_manager.gd` 新增 `brick_scored`/`pierce_scored` 信号 + `test_game_manager.gd` 信号用例 | 0.5 天 |
| Phase 3 | P0 | `ui_game_hud.tscn` 三区重排 + `game_hud.gd` 重构（样式/接线/容错/播种） | 1 天 |
| Phase 4 | P0 | `Main.tscn` 实例化改造（消除双份定义，节点名 GameHUD 不变） | 0.5 天 |
| Phase 5 | P0 | `test_hud.gd` 新建 + `run_tests.gd` 注册 + `test_ui_system.gd` / `test_main_scene.gd` 同步，`godot --headless` 全绿（含既有 16+ 套件零回归） | 1 天 |
| Phase 6 | P1 | Spike 1（E2E 02_midgame 4 重断言实测）+ Spike 2（720×1280 布局遮挡截图）+ 实弹截图 | 0.5–1 天 |

依赖顺序：Phase 1 → 2 → 3 → 4 → 5；Phase 6 可与 5 并行（截图兜底）。taste 参数（描边粗细/投影偏移/信息条配色/底部单行 vs 左右下角）在 Phase 6 实测后由 human-review 定稿。

---

## 9. 测试用例描述

> 仅描述场景与断言，不写可运行代码。implement agent 按此实现 `test_hud.gd` 并扩展既有套件（§2.6）。mock BreakoutGrid 模拟 #414 契约（`brick_destroyed` / `wall_cleared` / `wall_generated` 信号 + `remaining_bricks` 属性 + 调用记录）。theme override 断言一律用 `label.get("theme_override_...")`（GDD16：headless 下 `get_theme_font_size` 返回 0）。所有测试在 `godot --headless --script tests/run_tests.gd` 下运行。

### Scenario A: 霓虹样式（AC1）

- **Test A-1 描边已设置**：实例化 `ui_game_hud.tscn`，遍历 8 个数字 Label（AI 总分/拆/穿、玩家总分/拆/穿、波次、剩余）→ 每个 `label.get("theme_override_colors/font_outline_color")` 非空且 `label.get("theme_override_constants/outline_size")` > 0。
- **Test A-2 微投影已设置**：每个数字 Label 的 `theme_override_constants/shadow_offset_x` / `shadow_offset_y` > 0，且 `theme_override_colors/font_shadow_color` 的 alpha > 0。
- **Test A-3 样式单一事实源**：`UiNeonStyle.apply(label, color)` 后断言 4 项 override（font_color/outline/shadow_color/shadow_offset）与常量组一致；直接调用工具断言（不依赖场景）。
- **Test A-4 headless 安全**：在 headless 下完成 A-1/A-2 全部 `get()` 读取非零（GDD16 坑规避：不使用 `get_theme_font_size`）。

### Scenario B: 分区布局与配色（AC2）

- **Test B-1 顶红底蓝**：AI 区 Label（AITotalLabel）在顶部（TopBand 的 anchor_top == 0），玩家区 Label（PlayerTotalLabel）在底部（BottomBand 的 anchor_bottom == 1）。
- **Test B-2 配色正确**：AI 区 Label 的 `theme_override_colors/font_color` == `AI_NEON_RED`(#ff3355)；玩家区 == `PLAYER_NEON_BLUE`(#4a90d9)；信息条（WaveLabel/BricksLabel）== `HUD_INFO_COLOR`（非红非蓝，中立）。
- **Test B-3 拆/穿独立 Label**：AIBrickLabel 与 AIPierceLabel（及玩家侧）为独立节点、文本可独立更新（先拆后穿 → 两文本互不覆盖）。
- **Test B-4 信号隔离**：发 `brick_scored("player")` → 仅玩家拆砖子区文本变化，穿墙子区与 AI 区不变；发 `pierce_scored("ai")` → 仅 AI 穿墙子区变化。

### Scenario C: 波次与剩余砖数（AC3）

- **Test C-1 波次号信号更新**：发 `wave_started(3)` → WaveLabel 文本含「3」。
- **Test C-2 初始播种**：`_ready` 无信号时 WaveLabel == GameManager.wave_index（`reset_match()` 后为「第 0 波」；`begin_wave()` 后实例化为「第 1 波」）。
- **Test C-3 brick_destroyed 即时单读**：mock grid 发 `brick_destroyed` → BricksLabel == mock 的 `remaining_bricks` 当前值（mock 先减计数再发信号）。
- **Test C-4 wall_cleared 归零**：发 `wall_cleared()` → BricksLabel 含「0」。
- **Test C-5 wall_generated 主路径**：发 `wall_generated(24)` → BricksLabel 含「24」（新墙总数）。
- **Test C-6 回退路径**：mock grid **无** `wall_generated` 信号 → 发 `wave_started` 后（等一帧）BricksLabel 读到 mock 的 `remaining_bricks`（call_deferred 生效）。

### Scenario D: 安全区（AC4）

- **Test D-1 顶部区范围**：TopBand 的 rect y 范围 ⊆ [HUD_TOP_BAND_TOP, HUD_TOP_BAND_BOTTOM]（[12, 84]）。
- **Test D-2 底部区范围**：BottomBand 的 rect y 范围 ⊆ [HUD_BOTTOM_BAND_TOP, HUD_BOTTOM_BAND_BOTTOM]（[1252, 1280]），且与玩家挡板矩形（y∈[1230,1250]）零交集。
- **Test D-3 全宽**：MarginContainer `offset_right == 720`（TC20-11 语义保留）、offset_left == 0；两区均不伸入球道（x∈[10,710] 无 HUD 元素）。
- **Test D-4 与砖墙无交集**：两区 rect 与砖墙 y=640 无交集（安全区断言，Spike 2 截图实测补充）。

### Scenario E: 信号驱动零轮询（AC5）

- **Test E-1 无 _process**：`game_hud.gd` 脚本不定义 `_process`（`script.get_script_method_list()` 无 `_process`；或代码审查）。
- **Test E-2 score_changed 更新总分**：发 `score_changed(5, 3)` → 玩家总分 Label 含「5」、AI 总分含「3」（文本格式按 §2.3）。
- **Test E-3 brick_scored 路由**：`brick_scored("player")` → 玩家拆砖子区文本 == `get_brick_count("player")`；`brick_scored("ai")` → AI 侧。
- **Test E-4 pierce_scored 路由**：`pierce_scored("player")` → 玩家穿墙子区文本 == `get_pierce_count("player")`。
- **Test E-5 boundary 不触发按类信号**（test_game_manager.gd 扩展）：`add_score("player", 1, "boundary")` → `brick_scored` / `pierce_scored` 均未发出（`score_changed` 正常发出）。

### Scenario F: 容错与守卫

- **Test F-1 无 grid 不崩**：无 BreakoutGrid 节点 → `_ready` 不崩、`push_warning` 恰好一次、BricksLabel ==「剩余 —」、其余区正常。
- **Test F-2 部分信号缺失**：mock grid 有 `brick_destroyed` 但无 `wall_cleared` / `wall_generated` → `has_signal` 守卫跳过缺失项，剩余砖数走 brick_destroyed 路径（不崩、无错误）。
- **Test F-3 终局后无泄漏**：`GameManager.is_run_over() == true` 后 `add_score` 直接 return → HUD 不收到任何信号，保持终局分数（#385 守卫验证）。
- **Test F-4 同帧拆砖 + 穿墙**：同帧先后发 `brick_scored` 与 `pierce_scored` → 两子区各自更新为最新计数，无覆盖/无报错。
- **Test F-5 脚本级实例化安全**（test_ui_system TC9 同步）：裸 CanvasLayer + game_hud.gd（无场景子树）→ `_ready` 守卫 return，不崩。

### Scenario G: 既有套件集成与回归

- **Test G-1 test_ui_system.gd 同步**：TC6（三区新 Label 路径 + 8 个 Label 存在性 + 初值文本）、TC9（`_on_score_changed` 新文本格式）、TC15（Main.tscn GameHUD layer==1、visible==false 不变）全部通过。
- **Test G-2 test_main_scene.gd 同步**：TC1-11（GameHUD 存在）不变通过；TC20-11（MarginContainer offset_right==720）保留通过。
- **Test G-3 test_game_manager.gd 扩展**：`brick_scored` / `pierce_scored` 信号断言（kind 触发、boundary 不触发、非法 winner 不触发、终局后不触发）。
- **Test G-4 run_tests.gd 全绿**：注册 `test_hud.gd` 后 `godot --headless --script tests/run_tests.gd` 全绿（基线 1487 用例 + 新用例，既有 16+ 套件零回归）。
- **Test G-5 E2E 02_midgame 截图**（Spike 1，实机非 headless）：4 重断言（非黑/色数/主题色 4a90d9/帧间差异）通过；若变红先调 shot 参数（settle_frames/阈值），不删 HUD 内容；新增红色（ff3355）在色数断言内正常。

---

## 附录 A: 与 PRD 的差异记录

| PRD 表述 | 本设计 | 原因 |
|---------|--------|------|
| 按类信号 emit 顺序「之前或之后均可」（PRD §3.2） | `_bump_count` 之后、`score_changed.emit` 之前 | 确定性顺序便于测试断言（§1.2） |
| 信息条「挂顶部区下方或并入顶部区第二行」（PRD §4.2） | 并入顶部区第二行（SubRow） | 单一安全区锚点、克制信息密度（§1.2） |
| `wall_generated` 未采纳则回退 call_deferred（PRD §8 决策 3） | 双路径都实现：`wall_generated` 主路径 + call_deferred 回退 | PRD §5 边界 2「测试钉两种路径」（§1.2/§4 Flow 2） |
| 底部区布局待 Spike 2 决定（PRD §4.2） | 默认单行「总分+拆/穿」；左右下角双子区为 taste 备选 | 28px 单行默认行高可容纳，Spike 2 实测兜底（§1.2） |
| ui_game_hud.tscn layer=0（现状） | 统一 layer=1 | 消除双份不一致，HUD 在雨幕之上（AC1/TC15-9）（§1.2） |
| Main.tscn 改造「实例化或保持内联」（PRD §8 决策 5） | 实例化 ui_game_hud.tscn（节点名 GameHUD 不变） | 消除双份维护（§2.5） |
| 样式常量（PRD §8 决策 6） | `HUD_OUTLINE_SIZE=6` / `HUD_SHADOW_OFFSET=(2,2)` / `HUD_INFO_COLOR` 机械占位进 constants.gd | taste-draft 后调，单一事实源（§2.1） |

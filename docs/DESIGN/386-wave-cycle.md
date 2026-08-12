# DESIGN: [Feature] 波次循环 (Wave Cycle)

> **Parent Issue:** #386
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — GameManager 持有波次状态机 + 场景侧 WaveController 消费 `wall_cleared`（确认 PRD §4 推荐，无偏离）
> **Reference PRD:** docs/PRD/386-wave-cycle.md（research PR #425，已合并）
> **所有权:** `content_ownership: mechanical`（波次状态机/递增/清理/终局停止为纯机械实现；波次难度**数值曲线**归 taste-draft Issue）
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385 惯例按 standard 处理）—— 产出 DESIGN + TASKS；**测试仅描述，不写可运行测试代码**
> **Plan 阶段边界:** 本阶段只产出本文档与 `docs/TASKS/386-wave-cycle.md`，不碰任何 `.gd` / `.tscn` / `project.godot` 文件 —— 下列全部内容为 implement agent 的契约。

---

## 1. 概述

Mini Pong（720×1280 竖屏，PR #409 后）目前是单局 21 分制对打（#385 已落地）：从 MENU 发球对打直到任意一方先到 21 分，**不存在波次概念**。本设计引入 **波次循环**（PLAN-rogue-pong §2.1 核心循环）：

- **波次推进**：砖墙打空（#384 契约 `wall_cleared`）＝ 一局结束 → 波次结算（短暂状态，为 #388 升级 UI / #390 转场提供挂点）→ 自动生成更厚新墙 → 下一波（AC1）
- **难度爬升**：每波墙厚 `+WAVE_THICKNESS_STEP` **且** AI 反应延迟/位置误差按 `AI_DIFFICULTY_FACTOR` 收紧（clamp 下限）——双杠杆保证「至少一项严格递增」（AC2）
- **wave_index 可读**：`GameManager.wave_index` 从 1 起递增，`wave_started(wave_index)` 信号供 #390 转场（「第 N 道墙」）/ #393 HUD（AC3）
- **清理语义**：只调 `generate_wave()`（内部先 `clear_wall()` 快照清空全部旧砖 + 重置守卫），**绝不 `new` 第二个网格**（AC4）
- **终局停止**：结算时检查 `is_run_over()`（#385 已落地 21 分终局）→ 停止生成新墙，FSM 走既有 `match_over → GAME_OVER` 路径（AC5）

### 设计哲学

1. **Approach A 确认**：延续 #385「autoload 持状态 + 信号，场景节点消费编排」分工 —— GameManager 只做波次**状态持有**（wave_index / wave_state / 信号 / 查询 API），场景侧新建 `WaveController` 消费 `wall_cleared` 并驱动状态机、算难度、调 `generate_wave`。不扩展 FSM（否决 Approach C，状态归属错误会波及 #388/#390/#391 全部下游），不把场景引用塞进 autoload（否决 Approach B，破坏 #385 建立的纯状态测试模式）。
2. **容错消费 #384**：`get_node_or_null("../BreakoutGrid")` + `has_signal("wall_cleared")` / `has_method("generate_wave")` 双守卫（同 ScoringManager 对 brick_destroyed 的既有模式）——#384 实现未落地、#393 未接线时游戏不崩、波次状态机照常推进（wave_index 递增可测），生成环节跳过并 `push_warning`。
3. **常量单一事实源**：全部 `WAVE_*` / `AI_DIFFICULTY_*` 常量进 `constants.gd`（#295 约束），默认值为**机械占位**（taste-draft 后调），不散落硬编码。
4. **结算不依赖 #388**：`wave_settled` 发出后按 `WAVE_SETTLE_DELAY`（默认 1.0s）延时自动进下一波；#388 升级 UI 接线后由其接管推进时机（其 AC 独立，本 Issue 只保证挂点）。
5. **测试即验收**：测试用例描述见 §9；implement agent 写 `test_wave_cycle.gd` 并注册进 `run_tests.gd`；mock BreakoutGrid 模拟 #384 契约（同 test_dual_scoring 的 mock 模式）；`godot --headless --script tests/run_tests.gd` 全绿。

### 1.1 关键事实（plan agent 已对照源码核实）

| 事实 | 核实结果 |
|------|---------|
| GameManager 现状 | `mini-pong/gdscripts/game_manager.gd` 有 `score_changed` / `match_over` 信号、`player_score/ai_score`、拆砖/穿墙计数、`add_score(winner, amount, kind)`、`is_run_over()`、`reset_match()`、`_check_run_end()` —— **无任何 wave 字段/信号/枚举**（波次状态机为纯新增） |
| FSM 终局入口 | `game_state_machine.gd` 已直连 `GameManager.match_over`（`_on_match_over` → GAME_OVER，#385 AC3）→ AC5 复用既有路径，**FSM 零改动** |
| #384 信号契约 | `wall_cleared()`（整墙打空**只发一次**，`_wall_cleared_emitted` 守卫，`generate_wave()` 重置）；`generate_wave(thickness: int, layout: BrickLayout, seed: int)` 先 `clear_wall()`（快照 `queue_free` 全部旧砖 + 重置计数/守卫/集合），`rows == thickness`；`enum BrickLayout { GAPS, OFFSET, HOLES, MIXED }`（DESIGN #414 §3.4/§4.1） |
| #384 实现状态 | **未落地**：`git ls-tree origin/main mini-pong/gdscripts/` 无 `breakout_grid.gd` / `brick.gd` → WaveController 必须 `get_node_or_null` 容错 + 隔离测试先行；**不能 `preload` breakout_grid.gd**（解析失败）→ layout 用字面量对齐契约（见 §3.1） |
| AI 参数可缩放 | `paddle.gd` L16-31（#387 落地后）`ai_reaction_delay_min/max`、`ai_position_error`、`ai_speed_boost/slow` 均为**实例级 `@export`**，`_ai_process`（L122-140）每帧读取 → **运行时改实例属性即生效**（PRD §7 实验 2 确认） |
| 节点名 | `AIPaddle`（paddle.tscn 实例，Main.tscn 既有）→ WaveController 用 `get_node_or_null("../AIPaddle")` 缩放 |
| 常量现状 | `constants.gd` 有 Dual Scoring 组（L82-86）但**无 `WAVE_*` 组**；AI 手感常量（`AI_REACTION_DELAY_MIN=0.15` / `MAX=0.4` / `AI_POSITION_ERROR=24.0`，#367 定稿值）在 L57-73 |
| 测试注册 | `run_tests.gd` 模式：`_run("res://tests/test_X.gd", "Name")`（已注册 14+ 套件，含 test_dual_scoring.gd） |

### 1.2 与 PRD 的差异决策（plan 定稿，PRD §8 交接点 2 待决项）

| PRD 待决项 | 本设计定稿 | 理由 |
|-----------|-----------|------|
| `wave_index` 语义（PRD 表述「初始 1」） | **IDLE 期 0，首次 `begin_wave()` 后为 1**；`reset_match()` 归零 | 重置语义干净（reset 后回 0 而非 1，避免「未开局就 wave_index==1」）；对外可读值首波仍为 1，AC3 断言不变 |
| 停止 API（PRD 只列 begin/settle/is_wave_cycle_active） | **追加 `end_wave_cycle()`**（wave_state → IDLE，wave_index 保留供 run 统计） | PRD §5 AC5 要求「wave_state=IDLE」；且用户场景 C 要求 run 数据含波次数 → wave_index 不能随停止归零 |
| `generate_wave` 的 layout 参数 | **字面量 `0`（= BrickLayout.GAPS）+ 注释对齐 #414 契约**；每波 seed 传 `-1`（随机） | #384 脚本未落地，`preload` 其枚举会解析失败（同 #385 自带 `GRID_WALL_Y` 常量策略）；布局轮换属 taste 内容，MVP 全波 GAPS |
| AI 缩放下限 | **追加 FLOOR 常量组**（`AI_REACTION_DELAY_MIN_FLOOR=0.05` / `MAX_FLOOR=0.12` / `AI_POSITION_ERROR_FLOOR=8.0`） | 多波后参数不越界（机械可测）；PRD 只要求「因子占位」，clamp 下限是保证 AC2 语义完整的最小补充 |
| 结算推进时机 | **`WAVE_SETTLE_DELAY=1.0s` 常量**，`await create_timer` 自动进下一波 | PRD §5 失败路径 2 已要求「延时自动推进」，定稿为常量便于测试与 #388 接管 |

---

## 2. 现有组件修改 — 详细设计

### 2.1 `mini-pong/gdscripts/constants.gd`（修改）

新增「── Wave Cycle (#386) ──」常量组（置于 Dual Scoring 组之后）：

```gdscript
# ── Wave Cycle (#386) ──
# 波次循环 (PLAN-rogue-pong §2.1; mechanical; 数值曲线占位归 taste-draft)
const WAVE_START_THICKNESS: int = 1        # 首波厚度（行数）——机械占位，taste-draft 可调
const WAVE_THICKNESS_STEP: int = 1         # 每波厚度增量（AC2 厚度杠杆）
const WAVE_MAX_INDEX: int = 99             # 波次上限防御（21 分制下实际远早触发 AC5）
const WAVE_SETTLE_DELAY: float = 1.0       # 结算 → 下一波自动延时（#388 接线后由其接管推进时机）
const AI_DIFFICULTY_FACTOR: float = 0.9    # 每波 AI 参数收紧系数（<1 = 更难；taste-draft 占位）
const AI_REACTION_DELAY_MIN_FLOOR: float = 0.05  # 收紧下限（clamp，防过度）
const AI_REACTION_DELAY_MAX_FLOOR: float = 0.12
const AI_POSITION_ERROR_FLOOR: float = 8.0
```

### 2.2 `mini-pong/gdscripts/game_manager.gd`（修改 — 波次状态机宿主）

**职责**：纯状态持有 + 信号 + 查询 API，**零场景引用**（延续 #385 的 autoload 纯状态模式）。追加：

```gdscript
# ── Wave Cycle (#386) ──
enum WaveState { IDLE, RUNNING, SETTLED }

signal wave_started(wave_index: int)   # 新一波开始（#390 转场「第 N 道墙」/ #393 HUD，AC3）
signal wave_settled(wave_index: int)   # 墙清空结算挂点（#388 升级 UI 触发时机）

var wave_index: int = 0                # 当前波次号：IDLE 期 0，首次 begin_wave() 后从 1 递增（AC3）
var wave_state: WaveState = WaveState.IDLE

func begin_wave() -> void:
	wave_index += 1
	wave_state = WaveState.RUNNING
	wave_started.emit(wave_index)

func settle_wave() -> void:
	if wave_state == WaveState.IDLE:
		return
	wave_state = WaveState.SETTLED
	wave_settled.emit(wave_index)

func end_wave_cycle() -> void:
	wave_state = WaveState.IDLE   # AC5 停止；wave_index 保留供 run 统计（GAME_OVER 屏「波次数」归 #391）

func is_wave_cycle_active() -> bool:
	return wave_state != WaveState.IDLE
```

`reset_match()`（#385 既有）**追加两行**：`wave_index = 0`、`wave_state = WaveState.IDLE`（边界 1：首波从 1 起）。

### 2.3 `mini-pong/gdscripts/game_state_machine.gd`（不改 — 明确排除）

AC5 的 GAME_OVER 到达由既有 `match_over → _on_match_over → GAME_OVER` 覆盖（#385 AC3，已验证）。波次状态在 GameManager（Issue 原文），FSM 不新增 WAVE/SETTLEMENT 状态（Approach C 否决理由，PRD §4.1）。

### 2.4 `mini-pong/gdscripts/game_hud.gd` / `game_over_screen.gd`（不改）

- `game_hud.gd`：波次号 UI（「第 N 道墙」）归 #390/#393；本 Issue 只保证 `wave_index` 可读 + `wave_started` 信号
- `game_over_screen.gd`：run 统计含波次数归 #391（读取 `GameManager.wave_index` 即可，本 Issue 保证数据路径）

### 2.5 受影响测试文件（implement agent 改造清单）

| 文件 | 改动 |
|------|------|
| `mini-pong/tests/test_wave_cycle.gd` | **新建** —— §9 场景 A–G 的可运行实现 |
| `mini-pong/tests/test_game_manager.gd` | **扩展** —— wave API 单元断言（begin/settle/end/is_wave_cycle_active + reset_match 重置，§9 Scenario G-2） |
| `mini-pong/tests/test_constants.gd` | **扩展** —— `WAVE_*` / `AI_DIFFICULTY_*` 常量断言（§9 Scenario G-3） |
| `mini-pong/tests/run_tests.gd` | **修改** —— 注册 `test_wave_cycle.gd` |

---

## 3. 新建文件（实现期）

### 3.1 `mini-pong/gdscripts/wave_controller.gd`（新建 — 场景侧波次编排）

与 ScoringManager 同构（#385）：`@onready` + `get_node_or_null` 容错引用，`_ready()` 里按 `has_signal` 条件连接。

```gdscript
extends Node
## 波次编排（#386）：消费 BreakoutGrid.wall_cleared（#384 契约，容错）→ 驱动 GameManager 波次状态机
## → 难度递增 → generate_wave(更厚) → is_run_over() 停止。与 ScoringManager 同构（#385）。

const CONSTS = preload("res://gdscripts/constants.gd")

@onready var breakout_grid: Node = get_node_or_null("../BreakoutGrid")  # #384 容错：#393 接线前为 null
@onready var ai_paddle: Node = get_node_or_null("../AIPaddle")

var _settling: bool = false   # 结算中守卫：忽略重复 wall_cleared / 并发信号（边界 4）

func _ready() -> void:
	if breakout_grid != null and breakout_grid.has_signal("wall_cleared"):
		breakout_grid.wall_cleared.connect(_on_wall_cleared)
	else:
		push_warning("WaveController: BreakoutGrid 未接线 (#384/#393)，波次循环暂不激活")

func _on_wall_cleared() -> void:
	if _settling or GameManager.is_run_over():
		return
	_settling = true
	GameManager.settle_wave()                 # SETTLED + wave_settled（#388/#390 挂点）
	if GameManager.is_run_over():
		GameManager.end_wave_cycle()          # AC5：21 分后停止，不生成新墙
		_settling = false
		return
	await get_tree().create_timer(CONSTS.WAVE_SETTLE_DELAY).timeout  # 结算延时（#388 接线后由其接管）
	_advance_wave()
	_settling = false

func _advance_wave() -> void:
	GameManager.begin_wave()                  # wave_index +1 → RUNNING → wave_started（AC3）
	_apply_difficulty(GameManager.wave_index)
	if breakout_grid != null and breakout_grid.has_method("generate_wave"):
		breakout_grid.generate_wave(_wave_thickness(GameManager.wave_index), 0, -1)
		# layout=0 = BrickLayout.GAPS（#414 契约；不 preload 未落地脚本，字面量 + 注释对齐）
		# seed=-1 = 随机；generate_wave 内部先 clear_wall() → AC4
	else:
		push_warning("WaveController: generate_wave 不可用（#384 未落地），跳过墙生成")

func _wave_thickness(index: int) -> int:
	return CONSTS.WAVE_START_THICKNESS + (index - 1) * CONSTS.WAVE_THICKNESS_STEP

func _apply_difficulty(index: int) -> void:
	# AC2：AI 反应延迟/位置误差每波收紧（clamp 下限）；厚度杠杆由 _wave_thickness 保证
	if ai_paddle == null:
		push_warning("WaveController: AIPaddle 未接线，跳过 AI 缩放（厚度杠杆仍满足 AC2）")
		return
	ai_paddle.ai_reaction_delay_min = maxf(CONSTS.AI_REACTION_DELAY_MIN_FLOOR,
		float(ai_paddle.ai_reaction_delay_min) * CONSTS.AI_DIFFICULTY_FACTOR)
	ai_paddle.ai_reaction_delay_max = maxf(CONSTS.AI_REACTION_DELAY_MAX_FLOOR,
		float(ai_paddle.ai_reaction_delay_max) * CONSTS.AI_DIFFICULTY_FACTOR)
	ai_paddle.ai_position_error = maxf(CONSTS.AI_POSITION_ERROR_FLOOR,
		float(ai_paddle.ai_position_error) * CONSTS.AI_DIFFICULTY_FACTOR)
```

**挂载方式**（#393 组装时）：`Main.tscn` 新增 WaveController 节点（与 ScoringManager 同级，`../BreakoutGrid` / `../AIPaddle` 相对路径成立）。本 Issue 不接线（§6），脚本可独立实例化供隔离测试。

### 3.2 `mini-pong/tests/test_wave_cycle.gd`（新建）

隔离测试，**不依赖 #384 落地**：mock BreakoutGrid（脚本内 `class_name` 或普通 Node 挂 mock 脚本，实现 `wall_cleared` 信号 + `generate_wave`/`clear_wall` 记录方法，模拟 #414 契约：generate_wave 先清空再按 thickness 生成，brick 计数可查）。测试描述见 §9。

---

## 4. 数据流

### Flow 1: 墙清空 → 结算 → 下一波（AC1）

```
BreakoutGrid 最后一砖销毁 ── remaining_bricks == 0 ──► wall_cleared()          [#384 契约]
    │  （未接线时：无消费方连接，信号无人接收 → 无效果，游戏照常）
    ▼
WaveController._on_wall_cleared()   [get_node_or_null("../BreakoutGrid") 容错连接]
    ├─ guard: _settling / GameManager.is_run_over() → return
    ▼
GameManager.settle_wave() ──► wave_state = SETTLED ──► wave_settled.emit(wave_index)
    │                                                      └─► #388 升级 UI / #390 转场挂点
    ▼  （WAVE_SETTLE_DELAY 延时后，_settling 全程 true 防重入）
GameManager.begin_wave() ──► wave_index += 1 ──► wave_state = RUNNING ──► wave_started.emit(wave_index)
    │                                                              └─► #390「第 N 道墙」/ #393 HUD（AC3）
    ▼
WaveController._apply_difficulty(wave_index)   [AI 反应延迟/位置误差收紧，clamp 下限]
    ▼
breakout_grid.generate_wave(thickness, GAPS, -1)   [内部先 clear_wall() → AC4；单实例，绝无第二个网格]
```

### Flow 2: 难度递增（AC2）

```
thickness = WAVE_START_THICKNESS + (wave_index - 1) * WAVE_THICKNESS_STEP      # 每波 +1（厚度杠杆）
ai_reaction_delay_min/max = max(FLOOR, 现值 * AI_DIFFICULTY_FACTOR)            # 每波 ×0.9（AI 杠杆）
ai_position_error        = max(FLOOR, 现值 * AI_DIFFICULTY_FACTOR)
```
双杠杆均严格单调（厚度线性增；AI 参数单调收紧到 FLOOR 后持平）→ AC2「至少一项严格递增」确定性满足。FLOOR 触底后厚度仍递增，永不失效。

### Flow 3: 21 分停止（AC5）

```
最后一砖使一方到 21 分：brick_destroyed → add_score → _check_run_end → match_over（先发，#385 既有）
    → FSM _on_match_over → GAME_OVER（幂等守卫，#385 已验证）
同帧/相邻帧 wall_cleared 后到 → WaveController._on_wall_cleared 入口 is_run_over() 守卫 → return
    （不 settle、不生成；若已 settle 则 end_wave_cycle() → wave_state = IDLE）
```

### Flow 4: #384 未接线容错（#393 接线前）

```
_ready(): breakout_grid == null（或无 wall_cleared 信号）→ push_warning，不连接
_on_wall_cleared 永远不会被触发 → 波次状态机保持 IDLE（wave_index == 0）
_advance_wave（仅测试直调时）：grid 无 generate_wave → push_warning，wave_index 仍 +1（状态机不卡死）
```

---

## 5. 边界条件与失败路径

### 边界条件（≥5）

1. **首波起始** — MENU → 第一局：`reset_match()` 重置 `wave_index=0` / `wave_state=IDLE`；首次 `begin_wave()` → `wave_index=1`，首波厚度 = `WAVE_START_THICKNESS`（边界 1，PRD §5）
2. **wall_cleared 与 match_over 同帧/相邻** — 最后一砖使一方到 21：`match_over` 先发（brick_destroyed → add_score → `_check_run_end`），`wall_cleared` 后到 → `_on_wall_cleared` 入口 `is_run_over()` 守卫 return → 不结算不生成；FSM `_on_match_over` 幂等（GAME_OVER 守卫，#385 已验证）
3. **#384 未接线（实现未落地期）** — `get_node_or_null("../BreakoutGrid")` 为 null → `push_warning` + 跳过连接（ScoringManager 同款）；隔离测试直接实例化脚本验证逻辑
4. **wall_cleared 重复发出/并发** — #384 的 `_wall_cleared_emitted` 守卫保证每墙一次；WaveController 侧再加 `_settling` 布尔守卫（结算延时期间忽略任何重复信号）
5. **wave_index 上限防御** — 达到 `WAVE_MAX_INDEX`（99）后停止递增与生成（防御；21 分制下 AC5 实际远早触发）
6. **发球/暂停态** — 球静止或 PAUSED 时无砖接触，`wall_cleared` 不可能触发（#384 边界 6 已覆盖），波次状态机无需处理
7. **结算阶段再得分** — SETTLED 期间球已停（FSM 冻结挡板），无新得分路径；`scored` 信号被 FSM 状态守卫忽略（#385 既有）

### 失败路径（≥3）

1. **generate_wave 抛错/网格为空** — 生成后校验 mock/真实 grid 的 `remaining_bricks > 0`（`get("remaining_bricks")` 容错读），为 0 则回退重试一次（seed 变化）；仍失败 → `push_warning` + 波次暂停（不崩溃）
2. **升级 UI（#388）未接线时结算挂起** — 结算**不依赖** #388：`wave_settled` 发出后按 `WAVE_SETTLE_DELAY` 自动进下一波；#388 接线后由其决定推进时机（其 AC 独立）
3. **wave_index 溢出** — 达到 `WAVE_MAX_INDEX` 后停止递增并停止生成（防御；AC5 先触发则走 AC5 路径）
4. **ai_paddle 未接线** — `get_node_or_null("../AIPaddle")` 为 null → 跳过 AI 缩放 + `push_warning`；厚度杠杆仍保证 AC2（至少一项严格递增不失效）

---

## 6. 每场景配置

本 Issue **不修改任何 `.tscn`**。未来 #393 组装时的配置清单（供参考，非本 Issue 交付）：

| 场景 | 配置 | 归属 |
|------|------|------|
| `mini-pong/scenes/Main.tscn` | 实例化 `breakout_grid.tscn`（节点名 `BreakoutGrid`，WaveController 的 `get_node_or_null("../BreakoutGrid")` 依赖此名）；新增 WaveController 节点（与 ScoringManager 同级，依赖 `../AIPaddle` 节点名） | #393（连同 #384 的 BreakoutGrid 一并接入） |

---

## 7. 集成点

> 状态约定：⬜ = pending（实现 agent 接线后更新）；✅ = 已存在/已连接。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| `BreakoutGrid.wall_cleared()` → 波次推进 | WaveController._on_wall_cleared | #384 → 本 Issue 消费 | signal connect（`get_node_or_null` 容错，节点名 `../BreakoutGrid`） | ⬜ pending |
| `GameManager.wave_started(wave_index)` → 波次转场/HUD | —（本 Issue 只保证发出与负载） | #390 / #393 | 信号消费（「第 N 道墙」文案/布局归下游） | ⬜ pending |
| `GameManager.wave_settled(wave_index)` → 升级抽取 | —（本 Issue 只发挂点） | #388 | 信号消费（升级 UI 归 #388，其触发时机=本挂点） | ⬜ pending |
| `GameManager.match_over` → FSM GAME_OVER | GameStateMachine._on_match_over | 本 Issue 内部 | 既有连接（AC5 复用，零改动） | ✅ 已存在 |
| paddle.gd AI 实例参数 → 每波缩放 | WaveController._apply_difficulty | 本 Issue 内部 | 运行时改实例属性（#387 已实例级 @export，PRD §7 实验 2 确认） | ✅ 已就绪 |
| `GameManager.reset_match()` → 波次重置 | 本 Issue 内部 | reset_match() 追加 `wave_index=0` / `wave_state=IDLE` | ⬜ 新增 |

---

## 8. 实施阶段

| Phase | 优先级 | 组件 | 估算 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | `constants.gd` WAVE_* 常量组 + `game_manager.gd` 波次状态机（enum/信号/begin/settle/end/is_wave_cycle_active + reset_match 扩展） | 0.5 天 |
| Phase 2 | P0 | `wave_controller.gd` 新建（容错消费 + 结算延时 + 难度递增 + 生成编排） | 0.5 天 |
| Phase 3 | P0 | `test_wave_cycle.gd` 新建 + `test_game_manager.gd` / `test_constants.gd` 扩展 + `run_tests.gd` 注册，`godot --headless` 全绿（含既有套件零回归） | 1 天 |

依赖顺序：Phase 1 → 2 → 3。Phase 2 可与 Phase 1 并行（WaveController 引用 GameManager API，先定签名即可）。

---

## 9. 测试用例描述

> 仅描述场景与断言，不写可运行代码。implement agent 按此实现 `test_wave_cycle.gd` 并扩展既有套件（§2.5）。mock BreakoutGrid 模拟 #414 契约（`wall_cleared` 信号 + `generate_wave` 先清空再生成 + `remaining_bricks` 可查 + 调用记录）。所有测试在 `godot --headless --script tests/run_tests.gd` 下运行。

### Scenario A: 波次推进（AC1）

- **Test A-1 墙清空进入结算**：mock grid 发 `wall_cleared` → 断言 `GameManager.wave_state == SETTLED`、`wave_settled` 恰好一次且负载 == 当前 wave_index。
- **Test A-2 结算后自动下一波**：延时（测试用短延时或直调 `_advance_wave()`）后 → `wave_index +1`、`wave_state == RUNNING`、`wave_started` 恰好一次、mock `generate_wave` 被调用。
- **Test A-3 生成参数递增**：波 N 与波 N+1 的 `generate_wave` 首参（thickness）差 == `WAVE_THICKNESS_STEP`。
- **Test A-4 连续多波**：连续 3 次 `wall_cleared` → `wave_index == 3`、`generate_wave` 恰好 3 次（无跳过/无重复）。

### Scenario B: 难度递增（AC2）

- **Test B-1 厚度严格递增**：`_wave_thickness(2) > _wave_thickness(1)`，且 == `WAVE_START_THICKNESS + WAVE_THICKNESS_STEP`。
- **Test B-2 AI 参数收紧**：两波后 mock paddle 的 `ai_reaction_delay_min/max`、`ai_position_error` 均 ≤ 波 1 值（收紧方向），且 ≥ 对应 FLOOR（clamp 不越界）。
- **Test B-3 至少一项严格递增**：对任意相邻波断言「thickness 更大 或 AI 参数任一更紧」恒真（双杠杆都实现，实际两者同时成立）。
- **Test B-4 下限 clamp**：循环多波后参数不低于 FLOOR 常量（不趋零/不 NaN）。

### Scenario C: wave_index 生命周期（AC3）

- **Test C-1 首波为 1**：`reset_match()` 后首次 `begin_wave()` → `wave_index == 1`。
- **Test C-2 递增**：连续两波后 `wave_index == 2`。
- **Test C-3 信号负载**：`wave_started` / `wave_settled` 参数与 `GameManager.wave_index` 一致（可读性契约，#390/#393 依赖）。
- **Test C-4 reset 重置**：`reset_match()` 后 `wave_index == 0`、`wave_state == IDLE`、`is_wave_cycle_active() == false`。

### Scenario D: 旧墙不叠加（AC4）

- **Test D-1 单实例**：整轮测试中 mock grid 实例化次数 == 1（WaveController 绝不 `new` 网格）。
- **Test D-2 只调 generate_wave**：每波只调 `generate_wave`（mock 调用序列中无对 `clear_wall` 的直接调用——清理由 `generate_wave` 内部保证，#414 契约）。
- **Test D-3 砖数无残留**：mock 模拟 #414 清理语义（generate_wave 先清空再按 thickness 生成）→ 连续 3 波后 mock 的砖计数 == 第 3 波应生成数（0 残留）。
- **Test D-4 重复信号不叠加**：同一墙连发两次 `wall_cleared` → 只推进一波（`_settling` 守卫，边界 4）。

### Scenario E: 21 分停止（AC5）

- **Test E-1 终局后不结算不生成**：预置 `GameManager.is_run_over() == true` → mock 发 `wall_cleared` → 断言无 `wave_settled`/`wave_started`、`generate_wave` 未被调、wave 状态不变。
- **Test E-2 终局当波停止**：模拟最后一砖到 21 分（settle 后 `is_run_over()` 为 true）→ `end_wave_cycle()` → `wave_state == IDLE`、`generate_wave` 未被调、`wave_index` 保留（run 统计可读）。
- **Test E-3 FSM 既有路径**：`match_over` 已发 → FSM `_on_match_over` → GAME_OVER（复用 #385 既有 test_integration_fsm 断言，本 Issue 零新增接线）。

### Scenario F: 容错与守卫

- **Test F-1 无 grid 不崩**：无 BreakoutGrid 节点 → `WaveController._ready()` 不崩、`push_warning` 一次、波次状态机保持 IDLE。
- **Test F-2 无 ai_paddle**：AI 缩放跳过 + `push_warning`；厚度杠杆仍生效（AC2 满足，失败路径 4）。
- **Test F-3 结算中忽略重复**：`_settling == true` 期间再发 `wall_cleared` → 忽略（边界 4）。
- **Test F-4 generate_wave 不可用**：grid 有 `wall_cleared` 信号但无 `generate_wave` 方法 → `push_warning`，但 `wave_index` 仍 +1（状态机不卡死，Flow 4）。

### Scenario G: 重置与防御 + 既有套件集成

- **Test G-1 WAVE_MAX_INDEX 防御**：循环推进到 `WAVE_MAX_INDEX` → 停止递增与生成（防御路径；21 分制下正常流程不会到达）。
- **Test G-2 test_game_manager.gd 扩展**：wave API 单元断言（begin/settle/end/is_wave_cycle_active 状态转移 + `reset_match` 重置，§2.2）。
- **Test G-3 test_constants.gd 扩展**：`WAVE_*` / `AI_DIFFICULTY_*` 常量值/类型断言（§2.1）。
- **Test G-4 run_tests.gd 全绿**：注册 `test_wave_cycle.gd` 后 `godot --headless --script tests/run_tests.gd` 全绿，既有 14+ 套件零回归。

---

## 附录 A: 与 PRD 的差异记录

| PRD 表述 | 本设计 | 原因 |
|---------|--------|------|
| `wave_index` 初始 1（PRD §3/§8） | IDLE 期 0，首次 `begin_wave()` 后 1 | 重置语义干净；对外首波仍为 1，AC3 断言不变（§1.2） |
| GameManager API：begin/settle/is_wave_cycle_active（PRD §3） | 追加 `end_wave_cycle()` | PRD §5 AC5 要求停止后 `wave_state=IDLE`，且 wave_index 需保留供 run 统计（用户场景 C） |
| `generate_wave(thickness, layout, seed)` layout 参数（PRD §1 契约核查） | 字面量 0（GAPS）+ 注释对齐 #414 | #384 脚本未落地，preload 枚举会解析失败（同 #385 自带常量策略，§1.2） |
| AI 缩放因子占位（PRD §4.2/§8） | 因子 + FLOOR clamp 常量组 | 保证多波后参数不越界、机械可测（§1.2） |
| 结算推进（PRD §5 失败路径 2） | `WAVE_SETTLE_DELAY=1.0s` 常量 + `await create_timer` | 定稿为常量便于测试与 #388 接管（§1.2） |
| 难度曲线数值（PRD §1 技术约束） | 全部常量机械占位（`WAVE_START_THICKNESS=1` / `STEP=1` / `FACTOR=0.9`） | 曲线归 taste-draft；本 Issue 只保证机械机制与 AC2 确定性（PRD §4.2 Approach A） |

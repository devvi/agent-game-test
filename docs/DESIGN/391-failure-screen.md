# DESIGN: [Feature] 失败屏 (Failure Screen)

> **Parent Issue:** #391
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A — 扩展既有 GameOverScreen 为 win/fail 双分支（确认 PRD §4 维度一方案 A）+ 维度二方案 B — 软冻结扩展实现 AC4 暂停（确认，无偏离）
> **Reference PRD:** docs/PRD/391-failure-screen.md（research PR #431，已合并）
> **所有权:** `content_ownership: mechanical`（失败分支渲染/分档选句/三项 run 数据/终局冻结/重开为纯机械实现；失败短句**文案值**归 #396 taste-draft，本设计只做机械消费，不在代码硬编码新文案）
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386 惯例按 standard 处理）—— 产出 DESIGN；**测试仅描述，不写可运行测试代码**
> **Plan 阶段边界:** 本阶段只产出本文档，不碰任何 `.gd` / `.tscn` / `.json` / `project.godot` 文件 —— 下列全部内容为 implement agent 的契约。

---

## 1. 概述

Mini Pong（720×1280 竖屏，Godot 4.7.1，`mini-pong/`）当前**没有失败屏**：21 分终局（#385）后进入的是 #292 时代的胜者宣告屏（GameOverScreen），AI 获胜时显示红色 "AI WINS!" 大字 + 闪烁 "按 SPACE 重新开始"。玩家失败时无失败短句、无 run 数据（波次/拆砖/穿墙）展示，且 GAME_OVER 期间球仍运动（AC4「失败屏出现时游戏暂停」未满足）。

本设计把 GameOverScreen 从「胜者宣告屏」扩展为「终局屏」（win/fail 双分支，PRD 方案 A）：

- **失败分支（winner == "ai"）**：隐藏 WinnerLabel，头条换成失败短句（从 `wave_failure_text.json` 按 run 数据 severity 分档机械选句），下方展示 3 项 run 数据（波次 / 拆砖 / 穿墙，玩家单侧，全部来自 GameManager 查询 API）；克制呈现 —— 不启动 #292 脉冲动画，保留重启提示闪烁。
- **胜利分支（winner == "player"）**：既有 "YOU WIN!" 分支、脉冲动画、文案原样保留（回归红线）。
- **AC4 暂停**：GAME_OVER enter 时在既有 `_freeze_paddles(true)` 之外**冻结球**（ball 新增 `frozen` 标志 + `set_frozen()`，`_process` 早退），exit 时解冻 —— 对齐 #296 软冻结约定，不用 `get_tree().paused`。
- **AC5 重开**：SPACE → FSM `GAME_OVER → MENU` → `GameManager.reset_match()`（wave_index 归零、四计数归零、`_is_run_over=false`），新 run 从波 1 开始。

### 设计哲学

1. **Approach A 确认（激活既有插槽，不新建系统）**：#385 已在 `game_over_screen.gd` 埋入数据读取路径（P/A 双区格式，`RunStatsLabel` 不存在时静默跳过，注释明确「布局归 #391」）；本设计是「激活插槽 + 补失败分支」，零新场景、零新 CanvasLayer、零 Main.tscn 改动（Main.tscn 接线归 #393 的边界不冲突）。独立 FailureScreen 场景（PRD 方案 B）被否决：重复代码 + 违反 #393 边界 + MVP 过度设计。
2. **数据单一来源 = GameManager**：波次读 `get_wave_index()`（新增 getter，与 `get_brick_count/get_pierce_count` 查询 API 风格一致），拆砖/穿墙读既有查询 API；不做本地缓存（issue 原文）。
3. **文案机械消费、内容红线归配置**：选句逻辑只按 `wave_index` 分档（`<=2→fp1；<=5→fp2；>=6→fp3；else→fp4 兜底`，PRD §8 契约）；运行时**不做** emoji/感叹号文本校验（GDD 21 契约 —— 红线由 #396 配置内容保证）；`draft: true` 不阻塞机械插槽。
4. **软冻结扩展（AC4）**：对齐 #296「FSM 冻结 + 不碰 SceneTree pause」的既有约定；ball 新增独立 `frozen` 标志（与 paddle `set_frozen` 对称），**否决**复用 `speed_scale=0`（#387 缓时带 `_slow_time_remaining` 定时恢复语义，会与冻结互扰）、**否决** `get_tree().paused`（牵连 autoload process_mode，终局态不需要可恢复暂停）。
5. **JSON 消费沿用 #395 先例**：`FileAccess.get_file_as_string` + `JSON.parse_string` + schema 检查 + warn-once + 逐级兜底（upgrade_pool.gd `_load_display_names` 模式）；路径常量进 `constants.gd`（#295 单一事实源）。
6. **测试即验收**：测试用例描述见 §9；implement agent 写 `test_failure_screen.gd` 并注册进 `run_tests.gd`；headless 可测（复用 test_pause TC5 的 ball 位置断言模式）；`godot --headless --script tests/run_tests.gd` 全绿。

### 1.1 关键事实（plan agent 已对照源码核实）

| 事实 | 核实结果 |
|------|---------|
| `game_over_screen.gd` #385 埋入的数据路径 | ✅ `_on_match_over()` 内 `get_node_or_null("CenterContainer/VBoxContainer/RunStatsLabel")`，格式「拆砖 P:%d/A:%d 穿墙 P:%d/A:%d」；节点缺失静默跳过；`_ready` 用 `$CenterContainer/VBoxContainer/WinnerLabel` + RestartPromptLabel 且 null 守卫 |
| `ui_game_over.tscn` 节点 | ✅ 仅 WinnerLabel(72px) + Spacer + RestartPromptLabel(28px)；无 FailurePhraseLabel / RunStatsLabel |
| `game_manager.gd` 数据源 | ✅ `wave_index` public var（#386，终局后保留）、`get_brick_count(side)` / `get_pierce_count(side)`（#385 AC5）、`match_over(winner)` 信号、`reset_match()` 全量归零（含 wave_index=0）；**无 `get_wave_index()` getter** |
| FSM GAME_OVER | ✅ `enter_state(GAME_OVER)`：`_set_ui("game_over")` + `_freeze_paddles(true)` + `_transition_lock=false`；`exit_state` 无 GAME_OVER 分支；SPACE 在 GAME_OVER → MENU（`_transition_lock` 防重入）；`_on_match_over` 有 `current_state==GAME_OVER` 早退守卫；**球无冻结** |
| ball.gd 冻结能力 | ⚠️ 无 `frozen` 标志；`speed_scale`（#387 缓时）置 0 可停位移但带 `_slow_time_remaining` 定时恢复；`_process` 有 `_is_serving` 早退与 delta 守卫 |
| `wave_failure_text.json` | ✅ `mini-pong/content/wave_failure_text.json`（res:// 下为 `res://content/...`，**注意**与 upgrade JSON 的 `res://assets/content/` 不同目录）；schema `wave-failure-text/v1`，`draft: true`，`failure_phrases[]` 4 条（fp1-fp4，均带 id/text/context/emotion/recommended，fp1 recommended:true） |
| JSON 消费先例 | ✅ `upgrade_pool.gd` #395 `_load_display_names`：FileAccess + JSON.parse_string + schema 校验 + warn-once + 逐级兜底；`constants.gd` 持路径常量（`UPGRADE_JSON_PATH`） |
| `get_tree().paused` | ✅ 全库零使用（#296 软冻结约定） |
| Main.tscn GameOverScreen | ✅ 已实例化（node name GameOverScreen，layer=1，visible=false）；子节点仅 WinnerLabel/Spacer/RestartPromptLabel，无冲突 |

### 1.2 PRD 断言 vs 实际代码（缺口分析）

| PRD 断言 | 实际代码 | 设计决议 |
|---------|---------|---------|
| `game_over_screen.gd` 数据路径已埋 | ✅ 属实（P/A 双区格式，RunStatsLabel 缺失静默跳过） | 改为玩家单侧三项（§2.3），保留 get_node_or_null 容错 |
| FSM GAME_OVER 球不冻结（AC4 缺口） | ✅ 属实 | ball 加 `frozen`/`set_frozen` + FSM enter/exit 接线（§2.5/§2.6） |
| `wave_index` 可直接读、建议补 getter | ✅ 属实（public var，无 getter） | 补 `get_wave_index()`（§2.2），不改状态/计数逻辑 |
| JSON 在 `mini-pong/content/` | ✅ 属实 | 新增 `FAILURE_TEXT_PATH` 常量指向 `res://content/wave_failure_text.json`（§2.1） |
| 球冻结可复用 `speed_scale` | ⚠️ 部分可行但有 #387 定时恢复互扰 | 否决复用；新增独立 `frozen` 标志（§2.6） |

### 1.3 与 PRD 的差异决策（plan 定稿）

| PRD 待决项 | 本设计定稿 | 理由 |
|-----------|-----------|------|
| RunStatsLabel 呈现（PRD 留「单 Label 多行或三行 Label」） | **单 Label 单行**：`波次 %d · 拆砖 %d · 穿墙 %d`（font 28px，居中） | 三项均为 ≤2 位数字，28px 单行在 720 宽内不截断；单节点断言简单（AC2 验证「含三值」即可） |
| 失败分支 WinnerLabel 处理 | **fail 分支隐藏 WinnerLabel**（短语即头条）；win 分支隐藏 FailurePhraseLabel/RunStatsLabel | 终局屏双视觉模式语义干净；两 Label 在场景中常驻（TC7 节点存在性断言兼容，见 §9） |
| 脉冲动画（PRD 留「保留或降级」） | fail 分支**不启动** `_start_winner_pulse()`（克制），保留 `_start_prompt_blink()`；win 分支原样 | Issue 原文「克制、不堆特效」；#292 脉冲是 win 分支既有行为 |
| fp3 的「或接近 21」条件 | 机械分档**只用 wave_index**（≥6 → fp3）；比分接近度属 taste 非机械语义 | PRD §8 契约原文 `<=2→档1；<=5→档2；>=6→档3；else→兜底`，机械可测 |
| 球冻结机制 | ball.gd 新增 `frozen: bool` + `set_frozen(value)`；`_process` 冻结时早退；`serve()` 防御性复位 `frozen=false` | 与 paddle `set_frozen` 对称、headless 可测；`speed_scale=0` 与 #387 定时恢复互扰；SceneTree pause 牵连 autoload（均否决） |
| 兜底默认句 | `constants.gd` 新增 `FAILURE_TEXT_DEFAULT_PHRASE = "墙还在，雨未停"`（= fp4 兜底文案，红线合规） | PRD §5 边界 2：JSON 缺失/损坏时默认句 + push_warning；AC3 允许「兜底默认句除外」硬编码 |
| TASKS doc | **不产出**（depth/standard；本 Issue 为既有文件修改，无新运行时组件，实施顺序见 §8） | 386 的 TASKS 服务于新组件 WaveController；本 Issue 修改面集中，DESIGN 即契约 |

---

## 2. 现有组件修改 — 详细设计

### 2.1 `mini-pong/gdscripts/constants.gd`（修改 — 常量单一事实源）

在「── Upgrade Pool (#387) ──」组之后新增：

```gdscript
# ── Failure Screen (#391) ──
# 失败屏 (PLAN-rogue-pong §2.4; mechanical; 文案值归 #396 taste-draft)
const FAILURE_TEXT_PATH: String = "res://content/wave_failure_text.json"  # #396 schema wave-failure-text/v1
const FAILURE_TEXT_DEFAULT_PHRASE: String = "墙还在，雨未停"               # JSON 缺失/损坏兜底（≤10字、无感叹号/emoji，红线合规）
const FAILURE_WAVE_TIER1_MAX: int = 2    # fp1 早败（波 1-2）
const FAILURE_WAVE_TIER2_MAX: int = 5    # fp2 中败（波 3-5）
const FAILURE_WAVE_TIER3_MIN: int = 6    # fp3 晚败（波 6+）
```

> 分档函数：`wave_index <= TIER1_MAX → 档1；<= TIER2_MAX → 档2；>= TIER3_MIN → 档3；else（含 0/异常）→ 兜底档`。

### 2.2 `mini-pong/gdscripts/game_manager.gd`（修改 — 补查询 getter，不动状态/计数）

在 `get_pierce_count()` 之后追加（与 `get_brick_count/get_pierce_count` API 风格一致）：

```gdscript
func get_wave_index() -> int:    # #391 AC2：失败屏波次数查询（wave_index 终局后保留供 run 统计）
	return wave_index
```

> 不改任何状态/计数/信号逻辑；`wave_index` public var 保留（既有消费方 #390/#393 不受影响）。此改动为机械微改，若实现侧希望缩 scope 可跳过（失败屏直接读 `GameManager.wave_index`），但**推荐实施**以统一查询 API 风格。

### 2.3 `mini-pong/gdscripts/game_over_screen.gd`（修改 — 核心：win/fail 双分支）

**职责**：从「胜者宣告屏」扩展为「终局屏」。win 分支原样；fail 分支 = 隐藏 WinnerLabel + 分档选短句 + 玩家单侧三项数据 + 克制动画。

**新增常量与节点引用：**

```gdscript
const CONSTS = preload("res://gdscripts/constants.gd")
const RUN_STATS_FORMAT: String = "波次 %d · 拆砖 %d · 穿墙 %d"

@onready var failure_phrase_label: Label = get_node_or_null("CenterContainer/VBoxContainer/FailurePhraseLabel") as Label
@onready var run_stats_label: Label = get_node_or_null("CenterContainer/VBoxContainer/RunStatsLabel") as Label
```

> 新引用用 `get_node_or_null`（#385 RunStatsLabel 容错模式延续，bare 脚本/节点缺失不崩溃）；既有 `winner_label`/`restart_label` 保持 `$` 路径 + null 守卫不动。

**`_on_match_over(winner)` 重构（伪代码契约）：**

```gdscript
func _on_match_over(winner: String) -> void:
	if not winner_label or not restart_label:
		return
	var is_fail := winner == "ai"
	winner_label.visible = not is_fail                          # fail 分支隐藏胜者宣告
	if failure_phrase_label:
		failure_phrase_label.visible = is_fail
	if run_stats_label:
		run_stats_label.visible = is_fail
	match winner:
		"player":
			winner_label.text = TEXT_PLAYER_WIN
			winner_label.modulate = COLOR_PLAYER
			_start_winner_pulse()                               # win 分支保留 #292 脉冲
		"ai":
			if failure_phrase_label:
				failure_phrase_label.text = _select_failure_phrase(GameManager.get_wave_index())
			_render_run_stats()                                 # 玩家单侧三项（替换 #385 P/A 双区）
			# 克制：不启动脉冲（Issue 原文）
		_:
			return
	_start_prompt_blink()                                       # 两个分支都保留重启提示闪烁
	# —— 以下为既有逻辑，保持不变 ——
	# 隐藏 HUD（_get_sibling("GameHUD")）、visible = true、_transitioning = false
```

**新增方法（契约）：**

```gdscript
## 玩家单侧三项 run 数据：波次 / 拆砖 / 穿墙（AC2，全部来自 GameManager 查询 API）
func _render_run_stats() -> void:
	if not is_instance_valid(GameManager):
		return
	var stats := RUN_STATS_FORMAT % [
		GameManager.get_wave_index(),
		GameManager.get_brick_count("player"),
		GameManager.get_pierce_count("player"),
	]
	if run_stats_label:
		run_stats_label.text = stats

## 分档选句（AC3）：wave_index <=2→fp1；<=5→fp2；>=6→fp3；else→fp4 兜底（PRD §8 契约）
## 返回 String，永不返回空串；JSON 全链路失败 → FAILURE_TEXT_DEFAULT_PHRASE
func _select_failure_phrase(wave_index: int) -> String:
	var phrases := _load_failure_phrases()
	if phrases.is_empty():
		return CONSTS.FAILURE_TEXT_DEFAULT_PHRASE
	var tier := _pick_tier(wave_index)          # 0/1/2/3（3=兜底档）
	# 档内优先 recommended；按 id 后缀约定匹配（fp1/fp2/fp3=档1/2/3，fp4=兜底档，schema 契约）
	var candidates: Array = phrases.filter(func(p): return _phrase_tier(p) == tier)
	for p in candidates:
		if p.get("recommended", false):
			return String(p.get("text", CONSTS.FAILURE_TEXT_DEFAULT_PHRASE))
	if not candidates.is_empty():
		return String(candidates[0].get("text", CONSTS.FAILURE_TEXT_DEFAULT_PHRASE))
	return CONSTS.FAILURE_TEXT_DEFAULT_PHRASE

## JSON 只读消费（#395 先例）：FileAccess + JSON.parse_string + schema 检查 + warn-once
## 可选 path 参数便于测试注入缺失/损坏文件（默认 CONSTS.FAILURE_TEXT_PATH）
func _load_failure_phrases(path: String = CONSTS.FAILURE_TEXT_PATH) -> Array:
	# 空文件 / 解析失败 / schema != "wave-failure-text/v1" / failure_phrases 非数组
	# → warn-once push_warning + 返回 []（调用方走默认句兜底）

## 档位判定：返回 0/1/2/3；异常（0、负数、非 int）→ 3 兜底
func _pick_tier(wave_index: int) -> int:
	if wave_index <= CONSTS.FAILURE_WAVE_TIER1_MAX: return 0
	if wave_index <= CONSTS.FAILURE_WAVE_TIER2_MAX: return 1
	if wave_index >= CONSTS.FAILURE_WAVE_TIER3_MIN: return 2
	return 3

## id → 档位（schema 契约：fp1/fp2/fp3 → 0/1/2；fp4 或未知 → 3）
func _phrase_tier(phrase: Dictionary) -> int:
	var pid := String(phrase.get("id", ""))
	match pid:
		"fp1": return 0
		"fp2": return 1
		"fp3": return 2
		_:     return 3
```

> **文案红线**：本脚本除 `FAILURE_TEXT_DEFAULT_PHRASE`（AC3 明示例外）外**不得出现**任何文案字面量；不硬编码 fp1-fp4 文本。`draft: true` 仅标记文案值未定稿，机械选句逻辑先行（GDD 21 契约）。

### 2.4 `mini-pong/scenes/ui_game_over.tscn`（修改 — 新增两 Label）

VBoxContainer 内、WinnerLabel 之后插入两个节点（顺序：WinnerLabel → FailurePhraseLabel → RunStatsLabel → Spacer → RestartPromptLabel）：

```
[node name="FailurePhraseLabel" type="Label" parent="CenterContainer/VBoxContainer"]
text = ""
horizontal_alignment = 1
theme_override_font_sizes/font_size = 36        # 头条级但弱于 WinnerLabel(72)
modulate = Color(1.0, 1.0, 1.0, 1.0)

[node name="RunStatsLabel" type="Label" parent="CenterContainer/VBoxContainer"]
text = ""
horizontal_alignment = 1
theme_override_font_sizes/font_size = 28        # 与 RestartPromptLabel 同级
modulate = Color(1.0, 1.0, 1.0, 1.0)
```

> 节点路径与 #385 已埋代码的 `get_node_or_null("CenterContainer/VBoxContainer/RunStatsLabel")` 一致（零改脚本路径）；两 Label 默认 `visible` 继承父（场景实例化时屏幕整体隐藏，`_on_match_over` 按分支控制可见性）。竖屏 720×1280 校验：短语 ≤10 字 @36px 单行约 360px、三项数据 @28px 约 400px，均远小于 720 宽，无截断风险。

### 2.5 `mini-pong/gdscripts/ball.gd`（修改 — 最小冻结支持）

新增冻结标志（与 paddle `set_frozen` 对称）：

```gdscript
# ── State ──
var frozen: bool = false        # #391 AC4：GAME_OVER 终局冻结（软冻结约定，不用 SceneTree pause）

## 终局冻结/解冻（FSM GAME_OVER enter/exit 调用；headless 可测）
func set_frozen(value: bool) -> void:
	frozen = value

func _process(delta: float) -> void:
	if _is_serving:
		return
	if frozen:                  # #391 AC4：冻结期间不做任何位移/计分/墙带判定
		return
	# ... 既有逻辑不变 ...

func serve() -> void:
	# ... 既有复位逻辑 ...
	frozen = false              # 防御性复位：新发球/新 run 永不携带陈旧冻结（与 _is_serving 复位同位置）
```

> 冻结早退置于 `_is_serving` 之后、位移/计分/墙带判定之前 —— 冻结期间球位置不变、不产生 scored、不更新穿墙标记。不触碰 `speed_scale`/`_slow_time_remaining`（#387 缓时语义隔离）。

### 2.6 `mini-pong/gdscripts/game_state_machine.gd`（修改 — GAME_OVER 球冻结接线）

```gdscript
func enter_state(state: State) -> void:
	match state:
		# ... 既有分支不变 ...
		State.GAME_OVER:
			_set_ui("game_over")
			_freeze_paddles(true)
			_freeze_ball(true)          # #391 AC4：新增 —— 球停止运动
			_transition_lock = false

func exit_state(state: State) -> void:
	match state:
		State.SCORED:
			_scored_timer_active = false
		State.GAME_OVER:                # #391 AC4：新增 —— 离开终局屏解冻（SPACE → MENU 后新 run 球可动）
			_freeze_ball(false)
		_:
			pass

## 软冻结扩展（#296 约定）：has_method 守卫 —— 既有测试的 ball mock（无 set_frozen）不崩溃
func _freeze_ball(freeze: bool) -> void:
	if ball and ball.has_method("set_frozen"):
		ball.set_frozen(freeze)
```

> **兼容性**：`test_game_state_machine.gd` / `test_pause.gd` 的 ball mock 为裸 `Area2D.new()`（无 `set_frozen`）→ `has_method` 守卫跳过，既有 18+7 用例零改动通过。计分不可发生已由既有语义保证（FSM 非 PLAYING 时 `_on_scored` 忽略，`_on_match_over` 有 GAME_OVER 早退守卫）。

### 2.7 文件变更清单

**修改文件（6）**

| 文件 | 变更 | 动机 |
|------|------|------|
| `mini-pong/gdscripts/constants.gd` | 新增 Failure Screen 常量组（§2.1） | #295 常量单一事实源；路径/分档边界/默认句 |
| `mini-pong/gdscripts/game_manager.gd` | 新增 `get_wave_index()`（§2.2） | AC2 查询 API 风格一致 |
| `mini-pong/gdscripts/game_over_screen.gd` | win/fail 双分支 + 分档选句 + 三项数据 + 克制动画（§2.3） | AC1/AC2/AC3 核心 |
| `mini-pong/scenes/ui_game_over.tscn` | 新增 FailurePhraseLabel + RunStatsLabel（§2.4） | AC1/AC2 布局 |
| `mini-pong/gdscripts/ball.gd` | 新增 `frozen`/`set_frozen` + `_process` 早退 + `serve()` 复位（§2.5） | AC4 最小冻结支持 |
| `mini-pong/gdscripts/game_state_machine.gd` | GAME_OVER enter 冻结球 / exit 解冻 + `_freeze_ball` 助手（§2.6） | AC4 接线 |

**新增文件（2，测试为 implement agent 职责）**

| 文件 | 用途 |
|------|------|
| `mini-pong/tests/test_failure_screen.gd` | 失败屏用例（§9 描述，implement 阶段编写并注册进 `run_tests.gd`） |
| `mini-pong/tests/run_tests.gd`（修改注册行） | 追加 `_run("res://tests/test_failure_screen.gd", "Failure Screen")`（若用例含 await 用 `_run_async`，对齐 test_wave_cycle 先例） |

**移除/弃用文件：无。** **不触碰：** `Main.tscn`（#393 边界）、`wave_failure_text.json`（#396 只读消费）、`test_pause.gd`（PAUSED 语义不变）。

**受影响测试文件（兼容性）**

| 测试文件 | 影响 | 动作 |
|---------|------|------|
| `tests/test_ui_system.gd` | TC7 只断言 WinnerLabel/RestartPromptLabel 存在（两新 Label 不影响）；TC10 只调用不崩溃；TC11 常量不变 | 兼容不改；可选补两新 Label 存在性断言 |
| `tests/test_game_state_machine.gd` | ball mock 无 `set_frozen` → `has_method` 守卫跳过 | 兼容不改；新增冻结断言需在 mock 上加 `set_frozen` |
| `tests/test_pause.gd` | PAUSED 语义不变，`_freeze_ball` 只作用于 GAME_OVER | 不动 |
| `tests/test_dual_scoring.gd` | `get_wave_index()` 为纯新增 getter | 可选加 1-2 条断言（非必须） |

---

## 3. 数据流

### Flow 1：正常失败路径（AC1/AC2/AC3/AC4）

```
ScoringManager.scored → FSM._on_scored（PLAYING 消费）→ SCORED（挡板冻结，1s）
    └─ GameManager.is_run_over() == true（AI 先到 21，#385 单一权威）
        └─ transition_to(GAME_OVER)
            ├─ _set_ui("game_over")        → GameOverScreen.visible = true（三层切换 #292）
            ├─ _freeze_paddles(true)       → 既有
            └─ _freeze_ball(true)          → ball.set_frozen(true)（AC4，新增）
                    │
                    ▼
GameManager.match_over("ai") ──(既有信号连接)──► GameOverScreen._on_match_over("ai")
    ├─ winner_label.visible = false（fail 分支隐藏胜者宣告）
    ├─ FailurePhraseLabel.visible = true
    │    └─ text = _select_failure_phrase(GameManager.get_wave_index())
    │         ├─ _load_failure_phrases() → res://content/wave_failure_text.json（#396）
    │         └─ 分档: wave_index<=2→fp1 / <=5→fp2 / >=6→fp3 / else→fp4（recommended 优先）
    ├─ RunStatsLabel.visible = true
    │    └─ text = "波次 %d · 拆砖 %d · 穿墙 %d" % [get_wave_index(), get_brick_count("player"), get_pierce_count("player")]
    └─ _start_prompt_blink()（克制：无脉冲）
```

### Flow 2：配置缺失/损坏回退路径

```
_select_failure_phrase(wave_index)
    ├─ FileAccess.get_file_as_string(FAILURE_TEXT_PATH) 为空 → warn-once + []
    ├─ JSON.parse_string 返回 null / 非 Dictionary → warn-once + []
    ├─ schema != "wave-failure-text/v1" → warn-once + []
    ├─ failure_phrases 非数组 / 空数组 → []
    └─ [] → 返回 CONSTS.FAILURE_TEXT_DEFAULT_PHRASE（"墙还在，雨未停"，红线合规）
        → 失败屏仍可用：短句兜底 + 三项数据照常显示（PRD §5 失败路径 1）
```

### Flow 3：重开路径（AC5）

```
SPACE（FSM._input，GAME_OVER 状态，_transition_lock 防重入）
    └─ transition_to(MENU)
        ├─ exit_state(GAME_OVER) → _freeze_ball(false)（球解冻，新 run 可动）
        ├─ _set_ui("start_menu") → GameOverScreen.visible = false（失败屏隐藏）
        └─ MENU 后 SPACE → SERVING：
            ├─ GameManager.reset_match() → wave_index=0、四计数归零、_is_run_over=false、wave_state=IDLE
            └─ 首波 begin_wave() → wave_index=1 → 新 run 从波 1 开始
```

---

## 4. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | **首波未开始即败（wave_index == 0）** | 分档无 0 档 → `_pick_tier(0)` 落入兜底档（fp4 / recommended / 默认句），不崩溃（PRD §5 边界 1） |
| 2 | **JSON 缺失 / 解析失败 / schema 不符 / 空数组** | 逐级兜底 → `FAILURE_TEXT_DEFAULT_PHRASE`（≤10 字、无 emoji/感叹号，红线合规）+ warn-once `push_warning`；失败屏仍可用（Flow 2） |
| 3 | **`draft: true` 未定稿** | 机械插槽不依赖定稿文案值：档内 recommended 优先，任选一条即可；定稿后仅改 JSON，代码零改动（GDD 21 契约） |
| 4 | **玩家获胜（winner == "player"）** | 走既有 "YOU WIN!" 分支：WinnerLabel 显示 + 脉冲；FailurePhraseLabel/RunStatsLabel 隐藏；不改 win 分支文案（回归红线） |
| 5 | **失败屏显示期间按 ESC** | FSM `_input` 中 `ui_cancel` 只匹配 PLAYING/PAUSED，GAME_OVER 无响应（既有行为，回归确认） |
| 6 | **SPACE 连按 / 重入** | `_transition_lock` 防重入（#294 既有）；`_on_match_over` 的 `current_state==GAME_OVER` 早退守卫防重复渲染 |
| 7 | **21 分同帧双事件** | #385 既有 `elif` 单 winner 语义，失败屏只消费单次 `match_over`（回归确认） |
| 8 | **Headless 无树 / bare 脚本** | `get_tree()` null 守卫（#292 既有早退模式）；新引用全部 `get_node_or_null`；动画调用 `is_inside_tree()` 守卫 |
| 9 | **RunStatsLabel / FailurePhraseLabel 节点缺失** | `get_node_or_null` 容错静默跳过（#385 容错模式延续），不崩溃 |
| 10 | **球冻结回归（GAME_OVER 后球仍移动）** | `test_failure_screen.gd` ball 位置断言拦截；`serve()` 防御性 `frozen=false` 防陈旧冻结泄漏到新 run |
| 11 | **既有测试 mock 无 `set_frozen`** | `_freeze_ball` 用 `has_method("set_frozen")` 守卫 → test_game_state_machine / test_pause 既有 mock 零改动通过 |
| 12 | **竖屏 720×1280 布局** | 短语 ≤10 字 @36px、三项数据 @28px 单行均远小于 720 宽，不截断不溢出（沿 #292 分辨率校验约定） |
| 13 | **win 分支脉冲动画与隐藏 Label 的 tween 冲突** | `_start_winner_pulse` 只对 WinnerLabel（win 分支显示时）；fail 分支不启动，无隐藏节点动画泄漏 |

---

## 5. 每场景 / 每组件配置

### 5.1 `ui_game_over.tscn` 布局（720×1280 竖屏）

| 节点（CenterContainer/VBoxContainer 下） | 字号 | 显示条件 | 说明 |
|:---|:---:|:---|:---|
| WinnerLabel | 72 | win 分支（visible=true）| 既有；"YOU WIN!" + 玩家蓝 + 脉冲 |
| FailurePhraseLabel | 36 | fail 分支 | 新增；失败短句头条（克制：无脉冲） |
| RunStatsLabel | 28 | fail 分支 | 新增；`波次 %d · 拆砖 %d · 穿墙 %d` |
| Spacer | — | 常驻 | 既有 |
| RestartPromptLabel | 28 | 常驻 | 既有；「按 SPACE 重新开始」+ 闪烁（两分支均保留） |

### 5.2 常量配置（constants.gd）

| 常量 | 值 | 说明 |
|------|-----|------|
| `FAILURE_TEXT_PATH` | `res://content/wave_failure_text.json` | #396 文案文件（只读消费） |
| `FAILURE_TEXT_DEFAULT_PHRASE` | `墙还在，雨未停` | 兜底默认句（红线合规，AC3 明示例外） |
| `FAILURE_WAVE_TIER1_MAX` | `2` | fp1 早败（波 1-2） |
| `FAILURE_WAVE_TIER2_MAX` | `5` | fp2 中败（波 3-5） |
| `FAILURE_WAVE_TIER3_MIN` | `6` | fp3 晚败（波 6+） |

---

## 6. 集成点

> **Status 约定：** ⬜ = pending（资源已建，未接线）；✅ = connected（implement agent 验证）。implement agent 必须在接线时更新本表；review agent 在 merge 前核对 ⬜ 全部解决或显式延期。

| 集成 | 我方组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| `GameManager.match_over` → `GameOverScreen._on_match_over` | game_over_screen.gd | #385/#292 | 既有信号连接（`_ready` 内 `has_signal` 守卫） | ✅ 既有 |
| `GameManager.match_over` → `FSM._on_match_over` → GAME_OVER | game_state_machine.gd | #294/#385 | 既有信号连接 + GAME_OVER 早退守卫 | ✅ 既有 |
| `GameManager.get_wave_index()/get_brick_count/get_pierce_count` → RunStatsLabel | game_over_screen.gd | #385/#386 | 查询 API 只读（AC2，数据单一来源） | ✅ #391 已接线 |
| `res://content/wave_failure_text.json` → 分档选句 | game_over_screen.gd `_load_failure_phrases` | #396 | FileAccess 只读 + schema 检查 + 逐级兜底（#395 先例） | ✅ #391 已接线 |
| FSM GAME_OVER enter/exit → `ball.set_frozen` | game_state_machine.gd + ball.gd | #391 | `_freeze_ball` 助手（has_method 守卫） | ✅ #391 已接线 |
| #393 组装/HUD | Main.tscn 既有 GameOverScreen 实例 | #393 | 本 Issue 只改 GameOverScreen 内部；#393 接线时**勿覆盖** FailurePhraseLabel/RunStatsLabel 节点 | ⬜ 待 #393 遵守 |
| `run_tests.gd` → test_failure_screen.gd | tests/ | #391 | 注册新套件（§9） | ✅ #391 已接线 |

---

## 7. 实施阶段

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | `constants.gd`（FAILURE_* 常量组）+ `game_manager.gd`（`get_wave_index()`） | 0.5 天 |
| Phase 2 | P0 | `game_over_screen.gd`：fail 分支 + 分档选句 + 三项数据；win 分支兼容（#385 P/A 双区代码替换） | 1.5 天 |
| Phase 3 | P0 | `ui_game_over.tscn`：FailurePhraseLabel + RunStatsLabel 布局（720×1280 校验） | 0.5 天 |
| Phase 4 | P0 | `ball.gd`（frozen/set_frozen/`_process` 早退/`serve()` 复位）+ `game_state_machine.gd`（GAME_OVER 冻结/解冻） | 0.5 天 |
| Phase 5 | P1 | `tests/test_failure_screen.gd` + `run_tests.gd` 注册；既有套件回归（test_ui_system/test_game_state_machine/test_pause） | 1 天 |

> 依赖顺序：Phase 1 先于 2（常量/查询 API 是渲染前置）；Phase 4 独立可并行；Phase 5 依赖 2-4 全部落地。总估算 0.5–1 周（对齐 PRD §4 方案 A effort）。

---

## 8. 测试用例描述

> **只描述，不写可运行测试代码**（implement agent 编写 `mini-pong/tests/test_failure_screen.gd` 并注册进 `run_tests.gd`）。断言风格沿用既有套件：`_assert(condition, name)` 计数 passed/failed；mock 模式参照 test_pause TC5（ball 位置断言）与 test_game_state_machine（FSM + mock 节点装配）。

### Scenario A：失败分支渲染（AC1/AC2）

- **A-1 失败切换**：预置 FSM 于 PLAYING、GameManager 21 分终局（`match_over("ai")`）→ 断言 FSM `current_state == GAME_OVER`、GameOverScreen.visible == true、WinnerLabel.visible == false、FailurePhraseLabel.visible == true、RunStatsLabel.visible == true。
- **A-2 三项 run 数据**：预置 `wave_index=3`、`player_brick_count=7`、`player_pierce_count=2` 后触发 `_on_match_over("ai")` → 断言 RunStatsLabel.text 同时含「波次 3」「拆砖 7」「穿墙 2」三个片段（含分隔符格式串断言可读 `RUN_STATS_FORMAT`）。
- **A-3 数据来自 GameManager**：断言渲染路径调用 `get_wave_index()`/`get_brick_count("player")`/`get_pierce_count("player")`（mock 计数或读值断言），无本地缓存变量。

### Scenario B：短句分档选句（AC3）

- **B-1 档 1（早败）**：`wave_index` 分别取 0/1/2 → `_select_failure_phrase` 返回 fp1 档文本（`"雨还在下"`；0 落入兜底档则返回 fp4/默认句 —— 按 §1.3 定稿：`wave_index==0` 走兜底档，1/2 走 fp1）。
- **B-2 档 2（中败）**：`wave_index` 取 3/5 → fp2 档文本（`"雨记住了这一局"`）。
- **B-3 档 3（晚败）**：`wave_index` 取 6/99 → fp3 档文本（`"就差一道墙"`）。
- **B-4 兜底档**：`wave_index` 取 0 或异常值 → fp4 档（`"墙还在，雨未停"`）；`recommended` 优先逻辑：构造同档多条短语时优先 `recommended: true`。
- **B-5 配置驱动**：临时改 JSON 某档位 `text`（或注入 mock 文件）→ 屏幕短句随之变化（证明文案来自配置而非硬编码）；代码 grep 无 emoji/感叹号文案字面量（默认句除外）。

### Scenario C：配置容错（Flow 2）

- **C-1 文件缺失**：注入不存在的 path → 返回 `FAILURE_TEXT_DEFAULT_PHRASE`，`push_warning` 仅一次（warn-once）。
- **C-2 解析失败**：注入非法 JSON 文本 → 同上兜底，不崩溃。
- **C-3 schema 不符 / 空数组**：注入 schema 错误或 `failure_phrases: []` → 同上兜底。

### Scenario D：终局暂停（AC4）

- **D-1 冻结调用**：GAME_OVER enter 后断言 ball mock 的 `frozen == true`（mock 记录 `set_frozen` 调用）。
- **D-2 位置不变**：进入 GAME_OVER 后推进多帧 → 断言 ball.position 不变（复用 test_pause TC5 模式；ball mock 带 `_process` 位移 + `frozen` 早退）。
- **D-3 计分不可发生**：GAME_OVER 期间触发 `scored` 信号 → FSM 忽略（`current_state` 仍为 GAME_OVER）。
- **D-4 解冻**：SPACE → MENU（GAME_OVER exit）→ 断言 `set_frozen(false)` 被调用；新 run 球可动。
- **D-5 mock 兼容**：既有 test_game_state_machine / test_pause 全套件在 ball mock 无 `set_frozen` 时仍通过（`has_method` 守卫）。

### Scenario E：重开（AC5）

- **E-1 全量归零**：GAME_OVER 中 SPACE → 断言 `GameManager.reset_match()` 被调用且 `wave_index == 0`、四计数归零、`_is_run_over == false`。
- **E-2 新 run 从波 1**：重开后首波 `begin_wave()` → `wave_index == 1`。
- **E-3 屏幕复位**：重开后 GameOverScreen.visible == false（三层切换回归）；下次 `match_over` 时新数据覆盖旧文本。

### Scenario F：win 分支回归

- **F-1 YOU WIN! 保留**：`match_over("player")` → WinnerLabel.text == "YOU WIN!"、modulate 为玩家蓝、脉冲启动；FailurePhraseLabel/RunStatsLabel 隐藏。
- **F-2 既有套件兼容**：test_ui_system TC7（Label 存在性）/ TC10（调用不崩溃）/ TC11（常量）/ TC12（invalid winner 早退）全绿。

### Scenario G：headless 安全

- **G-1 bare 脚本**：无树实例 `_on_match_over("ai")` / `_on_match_over("player")` 不崩溃（新引用 get_node_or_null 守卫）。
- **G-2 节点缺失**：场景缺 FailurePhraseLabel/RunStatsLabel 时 fail 分支静默跳过、不崩溃（#385 容错延续）。
- **G-3 全量回归**：`godot --headless --script tests/run_tests.gd` 全部既有套件 + 新套件全绿。

---

## 9. 交接说明（implement agent）

1. **实施顺序**：Phase 1 → 2 → 3 → 4 → 5（§7）。
2. **分档函数契约**：`wave_index <= 2 → 档1(fp1)；<= 5 → 档2(fp2)；>= 6 → 档3(fp3)；else → 兜底档(fp4)`；档内 recommended 优先。
3. **失败短句文案值归 #396 定稿流程**：实施阶段**不要**在代码里硬编码 fp1-fp4 新文案（仅 `FAILURE_TEXT_DEFAULT_PHRASE` 例外）；`draft: true` 不阻塞。
4. **开源调研结论复述**：PRD §4 调研为 0 结果（Godot Asset Library 无失败屏组件），Godot 内建 CanvasLayer/Label 自实现 —— 实施 PR 需复述此结论以满足 issue「开源优先」验收。
5. **勿触碰**：`Main.tscn`（#393 边界）、`wave_failure_text.json` 内容（只读消费）、PAUSED 语义（#296）。
6. **回归重点**：win 分支（F-1/F-2）、既有 FSM 测试 mock 兼容（D-5）、headless 全绿（G-3）。

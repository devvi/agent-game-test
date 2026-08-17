# DESIGN: [Feature] 游戏波数触发迭代 — 特殊砖触发升级（Special-Brick Wave Trigger）

> **Parent Issue:** #529
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** A + 1（PRD §4.3 推荐组合逐项确认采纳）——触发归属 = 方案 A（对称触发，升级窗口归玩家，`last_toucher` 仅记录）；特殊砖生成 = 方案 1（替换式 + 厚度≥3 条件生成，薄墙回退 `wall_cleared`）；视觉 = brick.tscn 内运行时覆写（零新场景、零 tscn 改动）
> **Reference PRD:** docs/PRD/529-wave-trigger-special-brick.md（research PR #533 已合并；#534 为重复 research PR，内容已随 #533 移除）
> **上游方案:** docs/PLAN-rogue-pong.md §2.1 核心循环（波次开始 → 砖墙 → 对打 → 结算 → 3选1升级 → 下一波）+ §v1「特殊砖视觉 (铁砖/奖励砖)」（本 Issue 是特殊砖家族第一块：**触发机制**，非视觉扩展）；PRD #384 §4.3「砖侧可扩展性强（后续 v1 特殊砖/奖励砖的入场钩子）」预留落地
> **所有权:** `content_ownership: mechanical`——触发语义/内部位生成/信号链路/常量结构 = mechanical（可测）；`SPECIAL_BRICK_COLOR`/`SPECIAL_BRICK_GLOW_COLOR` 色值 = taste-draft 占位（本 DESIGN 给占位值，human-review 定稿，调参零代码改动）
> **深度:** depth/standard —— 产出 DESIGN + TASKS 两份文档（6 个独立实现子任务跨 4 个子系统 + 3 个测试文件，达 skill standard TASKS 阈值：5+ distinct subtasks）；测试仅描述不写代码
> **并行上下文:** #527（visual-enrichment）plan 已合（DESIGN 已入 main）但其实现未开始——#527 的 `BRICK_VARIANT_*`/`brick_variant`/`_spawn_brick(variant)` 与 #529 的 `SPECIAL_BRICK_*`/`is_special`/`_spawn_special_brick()` 同域（constants.gd / brick.gd / breakout_grid.gd），但**语义正交**（#527=视觉变体，#529=触发机制）。双方均按「constants.gd 只追加新区、既有区逐字节不动；brick.gd 只加字段与方法」先例（#448/#449/#450/#464）实现，冲突面仅限新增区，implement 阶段按合入顺序处理即可

---

## 1. 架构总览

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）的波次循环与升级链路已全部落地（#384→#385→#386→#387→#388→#390 全合并），但**升级/波数轮换的唯一触发条件是「整墙砖块打空」（`BreakoutGrid.wall_cleared`）**。波次越厚，尾部剩余砖越稀疏，玩家与 AI 越难命中 → 节奏拖沓（Issue 动机「游戏节奏越来越慢」）。

本设计按 PRD 推荐组合，把触发源从「整墙打空」迭代为「**砖堆内部（被包围）的特殊砖被击碎即触发**」——特殊砖仍是普通砖（占计数、参与 `wall_cleared`、拆砖分不变），只是多了 `is_special` 标记与一条新信号：

```
                        ★ Issue #529 波数触发迭代（本 DESIGN）
        ┌──────────────────────────────┴──────────────────────────────┐
        │ 触发侧（新增触发源，复用既有结算链路）      │ 生成侧（替换式，零契约破坏）     │
        ▼                                                ▼
  ball.gd（改 1 行）                               breakout_grid.gd（核心修改）
  body.destroy(last_toucher) ──→ brick.destroy(source)  generate_wave 末尾
        │                              │ breaker = source    ├─ _spawn_special_brick()
        ▼                              ▼                     │    （内部位判定 + 替换标记）
  brick.gd（改）                    grid._on_brick_destroyed  │         │
  is_special / breaker               ├─ 去重/计数/拆砖分不变    │         ▼
  apply_special_visual()             └─ is_special && breaker != ""  砖 is_special=true
                                          → special_brick_destroyed.emit(breaker)  视觉覆写
                                                    │
                                                    ▼
  wave_controller.gd（改）       _on_special_brick_destroyed(breaker)
                                    ├─ 守卫: _settling / is_run_over（既有复用）
                                    ▼
                              _begin_settlement()  ← _on_wall_cleared 主体抽取（双触发源共享）
                                    ├─ settle_wave() → wave_settled → UpgradePickUI 三选一（零改动）
                                    └─ advance_settlement() → _advance_wave() → 下一波（含新特殊砖）

  回退路径（厚度<3 / 无内部位）: wall_cleared → _on_wall_cleared → _begin_settlement() 【现状不变】
```

### 设计哲学

1. **契约不动，只加触发源**：#384 四方法契约（`generate_wave`/`clear_wall`/`brick_destroyed`/`wall_cleared`）、#386 结算链路（`_settling` 守卫/`settle_hold`/`advance_settlement`）、#385 归属机制（`last_toucher`）全部原样复用；特殊砖 = 普通砖 + 标记，不新增砖类型、不新增场景。
2. **替换式生成（方案 1）**：在已放置的普通砖中选 1 颗标记为特殊砖——计数/销毁/信号天然走既有单一递减入口，`remaining_bricks` 无漂移；「被包围」语义由实际砖位 4 邻域判定保证；洞/缝列天然不产生候选。
3. **同帧竞态去重继承**：特殊砖 = 最后一块砖时 `special_brick_destroyed` 与 `wall_cleared` 同帧先后 emit → WaveController `_settling` 守卫保证结算恰好一次（PRD 边界 1）。
4. **归属语义 = 方案 A（对称触发，窗口归玩家）**：任何一方击碎特殊砖（`last_toucher ∈ {player, ai}`）→ 窗口照常弹出供玩家三选一；归属仅用于拆砖分（既有机制）与记录。**发球直撞（`last_toucher == ""`）不触发**（防发球瞬间误触发，沿用 #385 边界 2 先例）。
5. **视觉零 tscn 改动**：`test_visual_contrast` E2-2 文本断言锁定 brick.tscn 的 color 字面 → 特殊砖视觉全部**运行时覆写**（ColorRect.color + 材质 `duplicate()` 后改 `glow_color`，#464 教训：共享 `neon_glow_material.tres` 的 `glow_color.a=1.0` → 不独立材质则边缘被完全覆盖/污染共享资源）。
6. **headless / 无 autoload 容错**：信号接线沿用 `has_signal`/`has_method` 双守卫；`ball` 引用 `get_node_or_null` 容错；生成失败（无候选）静默跳过 + 回退，不 `push_error`（#384 未接线期容错先例）。

### PRD 方案确认

| 决策点 | PRD 推荐 | 本设计 | 说明 |
|--------|---------|--------|------|
| 触发归属 | §4.1 方案 A（对称触发，窗口归玩家） | ✅ 采纳 | 升级=玩家侧语义（GDD 23）+ 实现最小；AI 击碎 = 玩家白得一次窗口（正反馈） |
| 特殊砖生成 | §4.2 方案 1（替换式 + 厚度≥3 条件） | ✅ 采纳 | 计数/销毁/信号契约不变；薄墙自动回退（AC4） |
| 信号设计 | `special_brick_destroyed(breaker)` 新信号 | ✅ 采纳 | 与 `brick_destroyed` 正交，WaveController 单点消费 |
| 结算复用 | `_on_wall_cleared` 主体抽 `_begin_settlement()` | ✅ 采纳 | 双触发源共享守卫/接管，零重复 |
| 视觉 | `is_special` 时覆写颜色/光晕 | ✅ 采纳，定稿为**同场景运行时覆写** | 零新场景、零 tscn 改动（E2-2 文本断言保护）；材质 duplicate + glow_color（#464 教训） |
| breaker 注入 | 「球触球方快照注入」 | ✅ 定稿为 **`brick.destroy(source)` 传参** | 见 §2 gap 核查（ball.gd 补 1 行传参，PRD 影响表未列，属必要澄清） |

---

## 2. 现状核实（plan agent 已对照源码确认，2026-08-17）

| 文件 | 现状 | 对本设计的影响 |
|------|------|---------------|
| `mini-pong/gdscripts/breakout_grid.gd` | 237 行；`generate_wave(thickness, layout, seed)`：`clear_wall()` → 行/列双循环放置（GAPS 每 5 列 1 缝跳过；OFFSET/MIXED 奇数行 `odd_offset=(w+g)*0.5`；越界跳过）→ `remaining_bricks = placed` → `_consume_pending_holes()`（#387 挂起洞消费）→ `wall_generated.emit`；`_on_brick_destroyed` 单一递减入口（`_destroyed` 按对象去重）→ `remaining<=0` 时 `wall_cleared`（`_wall_cleared_emitted` 守卫每墙一次）；信号 `brick_destroyed(brick,pos)`/`wall_cleared()`/`wall_generated(remaining)` | `_spawn_special_brick()` 插在 `_consume_pending_holes()` **之后**、`wall_generated.emit` **之前**（防特殊砖被挂起洞清掉）；`_on_brick_destroyed` 加 emit 分支；`blast_neighbors`/`_remove_column` 的 `b.destroy()` 改传 `"upgrade"` |
| `mini-pong/gdscripts/brick.gd` | 30 行；无 CONSTS preload；`var grid`/`_destroyed`；`_ready` 入组 `bricks`；`destroy()` 幂等 → `grid._on_brick_destroyed(self)` + `AudioEngine.play_brick_break()` + `queue_free()` | 增 `is_special`/`breaker` 字段 + `destroy(source := "")` 签名 + `apply_special_visual()`；需加 `const CONSTS = preload(...)` |
| `mini-pong/gdscripts/wave_controller.gd` | 112 行；`_on_wall_cleared`（守卫 `_settling`/`is_run_over` → `settle_wave` → run-over 分支 → `settle_hold` 接管/延时自动推进 → `_advance_wave` → `_settling=false`）；`advance_settlement()`（#388 UI 推进，幂等）；`_advance_wave` 调 `generate_wave(thickness, 0, -1)`（layout=0=GAPS）；`_ready` 已有 `wall_cleared` has_signal 双守卫接线 | 主体抽 `_begin_settlement()`；新增 `_on_special_brick_destroyed(breaker)`；`_ready` 加 `special_brick_destroyed` 接线（双守卫）；`ball` onready（get_node_or_null，仅记录） |
| `mini-pong/gdscripts/ball.gd` | 43 行 `var last_toucher: String = ""`；202-209 行 `_on_body_entered`：`body.is_in_group("bricks")` → `body.destroy()`（**未传参**） | **改 1 行**：`body.destroy(last_toucher)`（PRD 影响表未列 ball.gd，属必要澄清，见 gap 核查） |
| `mini-pong/gdscripts/constants.gd` | 231 行，`class_name GameConstants`；分区至 `# ── Combo Speed Feedback (#504)`；**无 SPECIAL_BRICK 区** | 追加 `SPECIAL_BRICK_*` 区（既有区逐字节不动） |
| `mini-pong/scenes/brick.tscn` | ColorRect `color = Color(1, 0.616, 0.271, 1)` + 共享 `neon_glow_material.tres`；**test_visual_contrast E2-2 文本断言锁定 color 字面** | **不改 tscn**；特殊砖视觉运行时覆写 |
| `mini-pong/assets/neon_glow_material.tres` | `glow_color = Color(0.29,0.56,0.85,1.0)`、`glow_width=0.25`、`glow_intensity=1.0`；E3-2 文本断言锁定 | **不改 .tres**；特殊砖材质运行时 `duplicate()` |
| `mini-pong/gdscripts/game_manager.gd` | autoload；`wave_started(i)`/`wave_settled(i)`；`begin_wave`/`settle_wave`/`is_run_over`/`end_wave_cycle` | **零改动**（settle 流/终局守卫复用） |
| `mini-pong/gdscripts/upgrade_pick_ui.gd` / `upgrade_pool.gd` / `scoring_manager.gd` / `wave_transition_controller.gd` | 消费 `wave_settled`/`brick_destroyed`/`wave_started` | **零改动**（触发源变化对下游无感知） |
| `mini-pong/tests/test_breakout_grid.gd`（375 行）/ `test_wave_cycle.gd`（556 行）/ `test_dual_scoring.gd`（528 行） | 已有墙生成/信号/波次推进/拆砖分用例（`_test_a1_wall_cleared_settles`、`_test_a1_player_brick` 等） | 扩展新用例（§8 Scenario B/C/D），`run_tests.gd` **无需新增套件** |

### PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计处置 |
|---------|-----------|---------|
| 「breaker 销毁时由球触球方快照注入」（§3 brick.gd） | `ball.gd` 208-209 行 `body.destroy()` **无参调用**；球是唯一知道 `last_toucher` 的组件；PRD §3 影响表**未列 ball.gd** | 定稿：`brick.destroy(source := "")` 传参注入；`ball.gd` 改 1 行传 `last_toucher`（默认参使既有调用零破坏）。PRD 影响表补 ball.gd（机械 1 行，非范围扩大） |
| 「边界 2：发球直撞（`last_toucher==""`）不触发」 vs 「边界 4：blast_neighbors/open_hole 波及特殊砖 → 视为击碎触发」 | 两边界均无触球方（发球直撞与升级效果都不经过 paddle 碰撞），仅凭 `last_toucher` 无法区分 | 定稿触发规则：**`special_brick_destroyed` 仅在 `breaker != ""` 时 emit**；`ball.gd` 传 `last_toucher`（发球直撞 = `""` → 不触发，边界 2 ✓）；grid 内部销毁路径（`blast_neighbors`/`_remove_column`/`_open_hole_now`）改传 `"upgrade"`（≠ `""` → 触发，边界 4 ✓，且与「升级连锁触发轮换属预期」一致）。`breaker` 取值域 = `""`/`"player"`/`"ai"`/`"upgrade"`，WaveController 只记录不区分（方案 A） |
| 「`_spawn_special_brick()` 在 generate_wave 末尾追加」 | `generate_wave` 末尾是 `_consume_pending_holes()`（会 `_remove_column` 销毁砖）→ `wall_generated.emit` | **插入点必须在 `_consume_pending_holes()` 之后**：若在之前标记，挂起洞可能把特殊砖所在列清掉（同帧 destroy → 波初即触发轮换，竞态）。定稿插入点 = `_consume_pending_holes()` 之后、`wall_generated.emit` 之前（见 §3.3） |
| 「内部位 = 4 正交邻域均有砖，避开洞/缝列」 | 生成循环是行/列双循环（GAPS 缝列 `c%5==4` 跳过；HOLES 整列跳过；OFFSET 奇数行偏移 `(w+g)*0.5`） | 定稿：**基于实际砖位判定**（生成后遍历 children），邻域 = 距离判定（`dx==±(w+g) ∧ dy==0` 或 `dx==0 ∧ dy==±(h+g)`）——布局无关（OFFSET 错位行自然无同列邻砖 → 不产生候选），洞/缝列天然无砖 → 无冲突；位置量化 0.5 网格作字典键（O(n) 邻域查询） |
| 「`@onready var ball = get_node_or_null("../Ball")`（容错，读 last_toucher 归属）」 | WaveController 与 Ball 同级（Main 根下），路径成立 | 采纳：`ball` 引用仅作**归属诊断记录**（方案 A 下窗口不区分归属方）；信号负载 `breaker` 已是主数据源，ball 引用为可选日志用途，null 时跳过不阻塞 |
| 「每波恰好 1 颗」 | 特殊砖替换式标记，`SPECIAL_BRICK_PER_WAVE=1` | 每波 `generate_wave` 恰好执行 1 次 `_spawn_special_brick()`（替换 1 颗）；同 seed 布局确定 → 特殊砖位置可复现（测试契约，同 #384 seed 先例） |

---

## 3. 既有组件修改（本设计无新文件）

> 全部为**修改既有文件**，无新增 .gd/.tscn/.tres。实现 PR 文件白名单见 §7。

### 3.1 `mini-pong/gdscripts/constants.gd` — 追加 SPECIAL_BRICK_* 区

文件末尾追加（既有区逐字节不动，沿用 #448/#449/#450/#464 分区先例）：

```gdscript
# ── Special Brick Wave Trigger (#529) ──
# 波数触发迭代 (PRD #529 方案1; 机制/常量 = mechanical, 色值 = taste-draft 占位,
# human-review 定稿, 调参零代码改动)。特殊砖 = 普通砖 + is_special 标记,
# 击碎即触发波次结算 (替代整墙打空), 拆砖分/计数/终局规则不变 (AC5)。
const SPECIAL_BRICK_PER_WAVE: int = 1        # 每波恰好 1 颗 (替换式, 不新增砖)
const SPECIAL_BRICK_MIN_THICKNESS: int = 3   # 厚度 < 3 无内部位 → 回退 wall_cleared (AC4)
const SPECIAL_BRICK_COLOR: Color = Color(0.45, 1.0, 0.75, 1.0)       # taste 占位: 亮薄荷绿 #73ffbf
const SPECIAL_BRICK_GLOW_COLOR: Color = Color(0.45, 1.0, 0.75, 1.0)  # taste 占位: 同色光晕
```

机械约束（测试断言，§8 A 组）：`SPECIAL_BRICK_COLOR` 与 `PLAYER_NEON_BLUE`（#4a90d9）RGB 距离 ×255 ≥ 32（E2E theme 保护，tol 32 先例 #527）；与 `BRICK_NEON`（#ff9d45，hue 28.4°）可区分（hue 环形距离 ≥ 60° 或 RGB 距离 ×255 ≥ 60）。占位值 #73ffbf 验证：vs #4a90d9 RGB 距离 ≈122 ✓；vs #ff9d45 ≈210 ✓；hue ≈152.7° vs 28.4° = 124° ✓。

### 3.2 `mini-pong/gdscripts/brick.gd` — 字段 + destroy 签名 + 视觉覆写

```gdscript
extends StaticBody2D
## ...既有注释保留...

const CONSTS = preload("res://gdscripts/constants.gd")   # #529 新增

var grid: Node
var _destroyed: bool = false
var is_special: bool = false      # #529: grid 生成时标记 (替换式, 每波 ≤1)
var breaker: String = ""          # #529: 销毁来源快照 ("player"/"ai"/"upgrade"/"")


func destroy(source: String = "") -> void:    # #529: 签名加默认参 (既有调用零破坏)
	if _destroyed:
		return
	_destroyed = true
	breaker = source                          # #529: 来源快照 (ball 传 last_toucher; grid 内部销毁传 "upgrade")
	if grid != null and is_instance_valid(grid) and grid.has_method("_on_brick_destroyed"):
		grid._on_brick_destroyed(self)
	if is_instance_valid(AudioEngine):        # #450 null-safe
		AudioEngine.play_brick_break()
	queue_free()


## #529: 特殊砖视觉覆写 (brick.tscn 内运行时改色, 零 tscn 改动 — E2-2 文本断言保护)
## 由 grid._spawn_special_brick() 在 is_special=true 后调用; 无 ColorRect → no-op (容错先例 #526)。
func apply_special_visual() -> void:
	var rect := find_child("ColorRect", false, false) as ColorRect
	if rect == null:
		return
	rect.color = CONSTS.SPECIAL_BRICK_COLOR
	if rect.material != null:
		var mat: ShaderMaterial = rect.material.duplicate()
		mat.set_shader_parameter("glow_color", CONSTS.SPECIAL_BRICK_GLOW_COLOR)
		rect.material = mat       # #464 教训: 共享 .tres glow_color.a=1.0 → 必须独立材质实例
```

要点：
- `destroy()` 逻辑零变化，仅新增 `breaker` 快照与默认参（既有测试/调用方零回归）。
- `apply_special_visual()` 只改**本实例**的 ColorRect 与材质，共享 `.tres` 与 brick.tscn 逐字节不变（E2-2/E3-2 文本断言恒成立）。

### 3.3 `mini-pong/gdscripts/breakout_grid.gd` — 信号 + 生成 + emit 分支

**新信号**（声明于既有三信号旁）：

```gdscript
signal special_brick_destroyed(breaker: String)   # #529: 特殊砖被击碎 (breaker 非空才发)
```

**`generate_wave` 末尾插入**（`_consume_pending_holes()` 之后、`wall_generated.emit` 之前）：

```gdscript
	_consume_pending_holes()               # 既有: 消费上波挂起 open_hole 请求
	_spawn_special_brick()                 # #529 新增: 内部位特殊砖 (见下)
	wall_generated.emit(remaining_bricks)  # 既有 #392: 每墙一次
```

**新方法**（布局无关的内部位判定，基于实际砖位）：

```gdscript
## #529: 替换式特殊砖生成 (PRD 方案1)。仅厚度 ≥ SPECIAL_BRICK_MIN_THICKNESS 且存在
## 4 正交邻域齐全的砖位时, 标记恰好 1 颗。无候选 → 静默跳过 + 回退 wall_cleared (容错先例)。
func _spawn_special_brick() -> void:
	if rows < CONSTS.SPECIAL_BRICK_MIN_THICKNESS:
		return                              # AC4: 薄墙回退 (行为与现状一致)
	var target = _pick_internal_brick()
	if target == null:
		return                              # 无内部位 → 本波回退, 不 push_error (边界 8)
	target.is_special = true
	target.breaker = ""
	if target.has_method("apply_special_visual"):
		target.apply_special_visual()


## 内部位候选: 4 正交邻域 (上/下/左/右) 均为存在砖。邻域判定 = 距离判定
## (dx==±(w+g) ∧ dy==0 或 dx==0 ∧ dy==±(h+g)), 布局无关 (洞/缝列无砖 → 天然不产生候选)。
## 候选选择: 距墙几何中心最近 (欧氏距离平方), 平局取行主序首个 — 确定性, 同 seed 可复现。
func _pick_internal_brick() -> Node2D:
	var step_x: float = _brick_w() + brick_gap
	var step_y: float = _brick_h() + brick_gap
	var by_pos: Dictionary = {}             # 位置量化 0.5 网格 → 砖 (浮点容差)
	for child in get_children():
		if child.is_in_group("bricks"):
			by_pos[_key(child.position)] = child
	if by_pos.size() < 5:
		return null                          # 少于 5 砖不可能有完整 4 邻域
	var center: Vector2 = _wall_center_local()
	var best: Node2D = null
	var best_d: float = INF
	for b in by_pos.values():
		var p: Vector2 = b.position
		if not (by_pos.has(_key(p + Vector2(-step_x, 0))) and by_pos.has(_key(p + Vector2(step_x, 0)))
			and by_pos.has(_key(p + Vector2(0, -step_y))) and by_pos.has(_key(p + Vector2(0, step_y)))):
			continue
		var d: float = b.position.distance_squared_to(center)
		if d < best_d:
			best_d = d
			best = b
	return best


func _key(v: Vector2) -> Vector2:
	return (v * 2.0).round() / 2.0          # 量化到 0.5 网格 (步长 68/28 整数, 位置精度 ≤0.5)


func _wall_center_local() -> Vector2:
	var cols: int = _compute_cols()
	var step_x: float = _brick_w() + brick_gap
	return Vector2(_compute_start_x(cols) + (cols - 1) * step_x * 0.5,
		wall_y - position.y)                # local_wall_y 同 generate_wave 推导
```

**`_on_brick_destroyed` 加 emit 分支**（在 `brick_destroyed.emit` 之后、`wall_cleared` 判定之前）：

```gdscript
func _on_brick_destroyed(brick: Node2D) -> void:
	if _destroyed.has(brick):
		return
	_destroyed[brick] = true
	remaining_bricks -= 1
	brick_destroyed.emit(brick, brick.global_position)
	if brick.is_special and brick.breaker != "":     # #529 新增: 触发规则见 §2 gap 核查
		special_brick_destroyed.emit(brick.breaker)
	if remaining_bricks <= 0 and not _wall_cleared_emitted:
		_wall_cleared_emitted = true
		wall_cleared.emit()                          # 同帧双发由 WaveController._settling 去重 (边界 1)
```

**内部销毁路径传来源标记**（升级连锁触发，边界 4）：

```gdscript
	# blast_neighbors() 与 _remove_column() 内: b.destroy() → b.destroy("upgrade")
```

### 3.4 `mini-pong/gdscripts/ball.gd` — 传触球方快照（改 1 行）

```gdscript
	# 208-209 行 (既有 bricks 分支内):
	if body.has_method("destroy"):
		body.destroy(last_toucher)      # #529: 注入触球方快照 (发球直撞 = "" → 不触发)
```

### 3.5 `mini-pong/gdscripts/wave_controller.gd` — 共享结算 + 新触发入口

```gdscript
@onready var ball = get_node_or_null("../Ball")   # #529: 归属诊断 (方案 A 仅记录, null 跳过)


func _ready() -> void:
	add_to_group("wave_controllers")
	if breakout_grid != null and breakout_grid.has_signal("wall_cleared"):
		breakout_grid.wall_cleared.connect(_on_wall_cleared)
	else:
		push_warning("WaveController: BreakoutGrid 未接线 (#384/#393)，波次循环暂不激活")
	# #529 新增: 特殊砖触发源 (双触发源之一, 同样双守卫容错)
	if breakout_grid != null and breakout_grid.has_signal("special_brick_destroyed"):
		breakout_grid.special_brick_destroyed.connect(_on_special_brick_destroyed)


## #529: 触发入口 1 — 整墙打空 (现状路径, 主体已抽至 _begin_settlement)
func _on_wall_cleared() -> void:
	if _settling or GameManager.is_run_over():
		return
	_begin_settlement()


## #529: 触发入口 2 — 特殊砖击碎 (方案 A: 对称触发, 窗口归玩家, breaker 仅记录)
func _on_special_brick_destroyed(breaker: String) -> void:
	if _settling or GameManager.is_run_over():
		return
	if breaker != "" and ball != null:
		pass    # 归属记录占位 (诊断/未来统计用; 本 Issue 不落地消费方)
	_begin_settlement()


## #529: 共享结算主体 (原 _on_wall_cleared 主体抽取; 双触发源复用, 守卫/接管零重复)
func _begin_settlement() -> void:
	_settling = true
	GameManager.settle_wave()                 # SETTLED + wave_settled (#388/#390 挂点)
	if GameManager.is_run_over():
		GameManager.end_wave_cycle()          # AC5: 21 分后停止, 不生成新墙
		_settling = false
		return
	if settle_hold:
		return                                # #388: 推进时机由 UI 接管 (_settling 保持 true)
	await get_tree().create_timer(settle_delay).timeout
	if not is_inside_tree():
		return
	_advance_wave()
	_settling = false
```

要点：
- `advance_settlement()`（#388 UI 推进）零改动——只依赖 `_settling`/`_advance_wave`，与触发源无关。
- `_on_wall_cleared` 行为与现状逐位一致（守卫在入口，`_begin_settlement` 与原主体同序）。

---

## 4. 数据流

### Flow 1 — 正常路径：球击碎特殊砖 → 三选一 → 下一波（AC2/AC3）

```
ball._on_body_entered: body.is_in_group("bricks")
  └─ body.destroy(ball.last_toucher)                    # ball.gd 改 1 行 (last_toucher ∈ {player, ai})
brick.destroy(source): breaker = source; _destroyed = true
  └─ grid._on_brick_destroyed(self)
grid._on_brick_destroyed: 去重 → remaining-1 → brick_destroyed.emit
  └─ is_special && breaker != "" → special_brick_destroyed.emit(breaker)     # 新增
WaveController._on_special_brick_destroyed(breaker)
  └─ 守卫: _settling / is_run_over → return
  └─ _begin_settlement()
     ├─ _settling = true
     ├─ GameManager.settle_wave() → wave_settled.emit(wave_index)
     │    └─► UpgradePickUI.open() → 三选一 (get_candidates(3)) → close() → advance_settlement()   # 零改动
     ├─ advance_settlement(): is_run_over? → end_wave_cycle : _advance_wave()
     │    ├─ begin_wave() → wave_started.emit → 转场/雨幕/HUD 照常 (#390/#389/#392)
     │    └─ generate_wave(更厚) [内部 clear_wall → 剩余旧砖清除] → _spawn_special_brick() → 新特殊砖
     └─ _settling = false
```

### Flow 2 — 回退路径：薄墙/无内部位 → 整墙打空照旧（AC4）

```
厚度 1-2 或无 4 邻域候选 → _spawn_special_brick() 直接 return
  → 无特殊砖 → 行为与现状完全一致:
     wall_cleared → _on_wall_cleared → 守卫 → _begin_settlement() → ... (同 Flow 1 后半)
```

### Flow 3 — 同帧竞态：特殊砖 = 最后一块砖（边界 1）

```
_on_brick_destroyed 单帧内: special_brick_destroyed.emit → wall_cleared.emit (先后)
  → WaveController 先收 special: _settling = true → _begin_settlement
  → 后收 wall_cleared: 守卫 _settling == true → return
  → 结算恰好一次 (wave_settled 计数 == 1, 测试 C5 断言)
```

### Flow 4 — 升级连锁：blast_neighbors / open_hole 波及特殊砖（边界 4）

```
upgrade_hook 触发: blast_neighbors(pos, radius) → b.destroy("upgrade")     # 来源标记
  → grid._on_brick_destroyed: is_special && breaker=="upgrade" != "" → emit("upgrade")
  → _begin_settlement() → 轮换 (属预期: fireball/破城锤 击碎特殊砖同样轮换)
```

### Flow 5 — 发球直撞特殊砖：不触发（边界 2）

```
发球后未触任何挡板: ball.last_toucher == "" → destroy("") → breaker == ""
  → grid: is_special 但 breaker == "" → 不 emit → 砖碎 + 计墙 (remaining-1), 不轮换
  → 若为最后一块 → wall_cleared 照常触发 (现状语义)
```

### Flow 6 — 终局竞态：击碎特殊砖使一方到 21 分（边界 6）

```
settle_wave() 后 GameManager.is_run_over() == true
  → _begin_settlement run-over 分支: end_wave_cycle() + _settling=false → return
  → 不生成新墙, wave_index 冻结 (与 #386 边界 5 一致)
```

---

## 5. 边界情况与错误处理

| # | 边界/失败场景 | 处置 | 对应 |
|---|--------------|------|------|
| 1 | 特殊砖 = 最后一块砖（同帧 `wall_cleared`） | 同帧双 emit → WaveController `_settling` 守卫去重，结算恰好一次 | PRD 边界 1 / AC2 |
| 2 | 发球直撞特殊砖（`last_toucher == ""`） | `breaker == ""` → 不 emit → 砖碎、计墙、不轮换（防发球瞬间误触发） | PRD 边界 2 |
| 3 | 厚度 < 3 / 无内部位 | `_spawn_special_brick` 早退/无候选 → 本波无特殊砖，`wall_cleared` 回退（AC4，**设计决策非缺陷**） | PRD 边界 3 / AC4 |
| 4 | blast_neighbors / open_hole 波及特殊砖 | grid 内部销毁路径传 `"upgrade"` → emit → 触发轮换（升级连锁属预期） | PRD 边界 4 |
| 5 | 结算窗口打开期间（paused）残余信号 | `_settling` 保持 true 直到 `advance_settlement` 复位；重复 `special_brick_destroyed`/`wall_cleared` 被忽略（既有机制） | PRD 边界 5 |
| 6 | 21 分竞态 | `settle_wave` 后 `is_run_over` → `end_wave_cycle`，不生成新墙（两触发入口同守卫） | PRD 边界 6 / AC5 |
| 7 | 洞/缝冲突 | 内部位判定基于**实际存在的砖**（生成后遍历）→ 洞/缝列天然无候选 | PRD 边界 7 |
| 8 | 生成失败（候选为空） | 静默跳过 + 本波回退 `wall_cleared`，不 `push_error`（容错先例 #384 未接线期） | PRD 失败路径 3 |
| 9 | 挂起洞（open_hole pending）与特殊砖同波 | `_spawn_special_brick` 在 `_consume_pending_holes()` **之后**执行 → 特殊砖不可能落在被挂起洞清掉的列（§2 gap 核查） | 本 DESIGN 新增 |
| 10 | 特殊砖被 blast 同帧多砖销毁 | `destroy()` 幂等 + `_destroyed` 对象去重 → emit 恰好一次 | 本 DESIGN 新增 |
| 11 | 替换式计数无漂移 | 特殊砖不新增砖、不改变 `remaining_bricks`；`wall_generated` 计数与 HUD 语义不变 | AC3/AC5 |
| 12 | `ball` 节点缺失 | WaveController `get_node_or_null("../Ball")` 为 null → 归属记录跳过，窗口仍触发（方案 A 下归属仅记录） | PRD 失败路径 2 |
| 13 | 既有调用方零回归 | `destroy(source := "")` 默认参：测试/既有路径直接 `destroy()` 不受影响（非特殊砖不 emit） | AC5 |
| 14 | grid 未接线 / 信号无消费者 | `special_brick_destroyed` 无监听 → no-op；`_ready` has_signal 双守卫（与 #384 未接线期同容错） | PRD 失败路径 1 |

---

## 6. 集成点

> **状态约定：** ⬜ = pending（资源已设计，未接线）；✅ = connected（implement agent 接线后更新）。implement agent 必须在本表勾选，review agent 合入前核查 ⬜ 全部解决或显式延后。

| 集成 | 我方组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 特殊砖触发信号 | `BreakoutGrid.special_brick_destroyed(breaker)` | #529 | WaveController `_ready` `has_signal` 双守卫 connect → `_on_special_brick_destroyed` | ✅ |
| 触球方快照注入 | `ball.gd` `body.destroy(last_toucher)` | #385/#529 | ball.gd 208-209 行 bricks 分支改传参（1 行） | ✅ |
| 升级连锁来源标记 | `blast_neighbors`/`_remove_column` → `b.destroy("upgrade")` | #387/#529 | grid 内部销毁路径传来源标记（边界 4） | ✅ |
| 特殊砖视觉 | `brick.apply_special_visual()` | #529 | `_spawn_special_brick` 标记后调用；ColorRect 改色 + 材质 duplicate + glow_color | ✅ |
| 结算复用 | `_begin_settlement()` | #386/#529 | `_on_wall_cleared` 主体抽取；双触发入口共享守卫/接管 | ✅ |
| 既有结算挂点 | `GameManager.wave_settled` | #388 | UpgradePickUI 既有消费，零改动（✅ 既有，不需 implement 动作） | ✅ |
| 新墙转场 | `GameManager.wave_started` | #390/#389 | `_advance_wave` 既有调用，零改动 | ✅ |

---

## 7. 实现阶段

> 单实现 PR（机制 + 测试同批）。Phase 1 依赖 0 外部；Phase 2 依赖 Phase 1 完成。

| Phase | 优先级 | 组件 | 内容 |
|:-----:|:------:|------|------|
| 1 | P0 | constants.gd / brick.gd / breakout_grid.gd / wave_controller.gd / ball.gd | §3 全部机械改动（常量区 → 字段/签名 → 生成+信号 → 结算抽取 → 1 行传参） |
| 2 | P0 | test_breakout_grid.gd / test_wave_cycle.gd / test_dual_scoring.gd | §8 Scenario B/C/D 用例（只写测试代码，不新增套件） |
| 3 | P1 | 验证 | 全量套件全绿 + `godot --path mini-pong --headless --quit` 无脚本错误 + E2E 视觉回归（§8 E 组） |
| 4 | P2 | taste 定稿 | `SPECIAL_BRICK_COLOR`/`SPECIAL_BRICK_GLOW_COLOR` human-review 定稿（调参零代码改动） |

### PR 文件白名单（8 文件，worktree-commit.sh 白名单 add）

- `mini-pong/gdscripts/constants.gd`（仅追加 SPECIAL_BRICK_* 区）
- `mini-pong/gdscripts/brick.gd`（字段 + destroy 签名 + apply_special_visual + CONSTS preload）
- `mini-pong/gdscripts/breakout_grid.gd`（信号 + _spawn_special_brick 族 + emit 分支 + 来源标记）
- `mini-pong/gdscripts/wave_controller.gd`（_begin_settlement 抽取 + _on_special_brick_destroyed + 接线 + ball onready）
- `mini-pong/gdscripts/ball.gd`（1 行传参）
- `mini-pong/tests/test_breakout_grid.gd` / `test_wave_cycle.gd` / `test_dual_scoring.gd`（扩展）

### 明确不修改（红线）

`upgrade_pick_ui.gd`、`upgrade_pool.gd`、`scoring_manager.gd`、`game_manager.gd`、`wave_transition_controller.gd`、FSM、`brick.tscn`、`neon_glow_material.tres`、`neon_glow.gdshader`、`Main.tscn`、`run_tests.gd`（无需新增套件）—— 全部沿用现状（PRD §8 零改动红线）。

---

## 8. 测试用例描述

> 按 skill 协议：**只描述场景与断言，不写可运行测试代码**。实际测试代码由 implement agent 编写并落入 §7 白名单三个测试文件（`run_tests.gd` 不新增套件）。基线：现有 24 套件全绿（AC5 零回归红线）。
> 验收映射：AC1–AC5（PRD §5.1）逐条对应；PRD §5 边界 1–8 与失败路径覆盖；编号沿用各文件既有前缀（test_wave_cycle 的 `_test_*` 场景字母已用至 G → 新用例从 H 组起；test_breakout_grid 用既有 `_test_*` 命名空间追加；test_dual_scoring 新用例从 J 组起，避开既有 A–H）。

### Scenario A — 常量与机械约束（test_breakout_grid.gd `_test_constants` 扩展）

- **A1（机械键）**：`SPECIAL_BRICK_PER_WAVE == 1`、`SPECIAL_BRICK_MIN_THICKNESS == 3`（运行时断言）。
- **A2（E2E theme 保护）**：`SPECIAL_BRICK_COLOR` 与 `PLAYER_NEON_BLUE`（#4a90d9）RGB 距离 ×255 ≥ 32；与 `BRICK_NEON` RGB 距离 ×255 ≥ 60（可辨识）。
- **A3（默认砖零回归）**：`is_special == false` 砖 `ColorRect.color` == 场景字面 `Color(1, 0.616, 0.271, 1)` 且材质 `is_same()` 共享 .tres（文本断言 brick.tscn 未被修改，同 test_visual_contrast E2-2 模式）。

### Scenario B — 内部位生成（test_breakout_grid.gd）

- **B1（AC1 内部位）**：`generate_wave(3, GAPS, seed)` → 恰好 1 颗 `is_special` 砖；其 4 正交邻域（上/下/左/右）均为存在砖；不在 gap 列（`c%5==4` 无砖列）。
- **B2（AC4 薄墙回退）**：`generate_wave(1..2, GAPS, seed)` → 0 颗 `is_special`（**不得断言薄墙出特殊砖**——设计决策非缺陷）。
- **B3（可复现）**：同 seed 两次 `generate_wave(4, GAPS, seed)` → 布局一致且特殊砖位置一致（替换选择确定性，沿用 #384 seed 契约）。
- **B4（每波恰好 1 颗）**：`generate_wave(4/5, GAPS, seed)` → `is_special` 计数 == 1（PER_WAVE 约束；厚度变化不增加颗数）。
- **B5（挂起洞后存活）**：`open_hole(1)` → `generate_wave(3, GAPS, seed)` → 特殊砖存在且**不在被洞清除的列**（`_spawn_special_brick` 在 `_consume_pending_holes` 之后执行，边界 9）；`remaining_bricks` == 生成净数。
- **B6（无候选容错）**：极端 seed 或无内部位布局 → 0 颗 + 不 `push_error`（边界 8）；`wall_generated` 照常 emit。
- **B7（计数参与）**：特殊砖计入 `remaining_bricks`；击碎后计数递减（替换式无漂移，AC5）。

### Scenario C — 触发链路（test_wave_cycle.gd，新 H 组）

- **C1（AC2 全链路）**：mini-tree：`generate_wave(3, GAPS, seed)` → 取 `is_special` 砖 → `destroy("player")` → `wave_settled` 发出（升级窗口挂点）→ `advance_settlement()` → `wave_index +1` → 新墙含新特殊砖（复用 d2 无残留断言模式）。
- **C2（AC3 不等墙空）**：击碎特殊砖时剩余旧砖 > 0 → 轮换仍发生；`clear_wall` 清掉剩余旧砖（新墙生成后旧砖 `is_instance_valid == false`）。
- **C3（方案 A 对称触发）**：`destroy("ai")` → 同样 `wave_settled`（窗口归玩家；不断言 AI 侧分支）。
- **C4（边界 2 发球直撞）**：`destroy("")` → 不 `wave_settled`、不轮换；砖碎 + 计数减（拆砖分走既有路径）。
- **C5（边界 1 同帧去重）**：特殊砖 = 最后一块（`destroy("player")` 使 remaining 归 0）→ `special_brick_destroyed` 与 `wall_cleared` 同帧 → `wave_settled` 计数 == 1（恰好一次）。
- **C6（边界 5 结算期忽略）**：`_settling == true` 期间再 `destroy` 特殊砖/`wall_cleared` → 无二次结算。
- **C7（边界 6 终局竞态）**：击碎特殊砖使一方到 21 分 → `end_wave_cycle`、不生成新墙、`wave_index` 冻结（复用 e1/e2 断言模式）。
- **C8（边界 4 升级连锁）**：`blast_neighbors(pos, radius)` 波及特殊砖（`destroy("upgrade")`）→ `wave_settled` 触发。
- **C9（AC4 回退回归）**：厚度 1-2 波 → 无特殊砖 → `wall_cleared` 路径照旧（既有 a1/a2 用例回归）。
- **C10（WAVE_MAX_INDEX 防御）**：达上限 → `_advance_wave` 不推进（g1 回归；特殊砖路径同样受 `_advance_wave` 防御）。

### Scenario D — 拆砖分不变式（test_dual_scoring.gd，新 J 组）

- **D1（AC5 拆砖分）**：特殊砖被 player 击碎 → player +1；被 ai 击碎 → ai +1（`brick_destroyed` 既有路径，特殊砖无特殊计分）。
- **D2（发球直撞零分）**：`destroy("")` 击碎特殊砖 → 0 分（a3 边界回归）；21 分终局判定不受触发源影响。

### Scenario E — 回归与 E2E（AC5/红线）

- **E1（零回归）**：run_tests.gd 全量套件全绿（含 test_wave_cycle/test_breakout_grid/test_dual_scoring 既有用例）。
- **E2（headless）**：`godot --path mini-pong --headless --quit` 无脚本错误（AC5）。
- **E3（E2E 视觉）**：`run-e2e-review.sh --with-visual` → 01_title theme_absent 保持、02_midgame 非黑/theme 4 重断言通过（特殊砖色避开 #4a90d9 → theme 断言安全；需图形环境，软性依赖同 #466 惯例）。
- **E4（文件域）**：实现 PR files 列表 ⊆ §7 白名单 8 文件，不混入其他 issue 文件（AC8/红线）。

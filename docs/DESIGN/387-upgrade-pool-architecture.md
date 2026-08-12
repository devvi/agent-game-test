# DESIGN: [Feature] 升级池架构 (UpgradePool)

> **Parent Issue:** #387
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A×5 — ① autoload 单例载体 ② Callable 效果回调定义 ③ 稀有度先掷 60/30/10 抽取 ④ @export 实例属性 + setter（下一帧生效） ⑤ BreakoutGrid upgrade_hooks 注册表（**全部确认 PRD §4 推荐，无分歧**）
> **Reference PRD:** docs/PRD/387-upgrade-pool-architecture.md（research PR #415，已合并）
> **上游方案:** docs/PLAN-rogue-pong.md §2.5（9 升级清单 + 稀有度 60/30/10 + 每波 3 选 1 + 稀有度后置 reveal，已确认 2026-08-13）
> **所有权:** `content_ownership: mechanical`（池结构/抽取算法/参数实例化/钩子契约 = 机械实现；升级数值与文案归 taste 域，#395 已排队 human-review）
> **深度:** depth/standard —— 仅产出 DESIGN 文档；不产出 TASKS 文档；测试仅描述不写代码

---

## 1. 架构概述

Mini Pong（`mini-pong/`，Godot 4.7.1，720×1280 竖屏）目前**不存在任何升级/波次系统**。本设计将 Rogue Pong 的成长核心——数据驱动升级池——落地为第三个 autoload 单例 `UpgradePool`，作为 #386 波次循环与 #388 3 选 1 UI 的**数据枢纽**（Issue 上下文明示：升级是每波成长的核心，3 选 1 UI 的数据来源）。

```
                    ┌────────────────────────── 消费方（本 Issue 不接线） ──────────────────────────┐
                    │  #386 波次循环（清墙结算）──► UpgradePool.get_candidates(3)                     │
                    │  #388 3 选 1 UI ──────────► UpgradePool.get_candidates(3) / apply(id)        │
                    └──────────────────────────────────┬───────────────────────────────────────────┘
                                                       │
    ┌────────────────────────────── UpgradePool（autoload 单例，新） ──────────────────────────────┐
    │  upgrade_defs.gd（9 定义单一事实源：id/name/rarity/max_stacks/effect:Callable）                │
    │  get_candidates(n) ：稀有度先掷 60/30/10 → 稀有度内均匀选 → 候选去重 → 回退链                    │
    │  apply(id)        ：计数 → effect.call(ctx) → max_stacks=1 移出池 → upgrade_applied.emit      │
    │  rng（可 seed()）；显示字段只读消费 #395 upgrade_pool.json（缺失/解析失败 → 工作名兜底）        │
    └──────────────────────────────────┬──────────────────────────────────────────────────────────┘
                                       │ effect ctx = {ball, paddle, grid, params}
              ┌────────────────────────┼───────────────────────────────┐
              ▼                        ▼                               ▼
    ball.gd（改小）            paddle.gd（改中）              BreakoutGrid（#384 未落地 → 契约先行）
    speed_scale / 定时恢复     const→@export 实例属性         upgrade_hooks 注册表 + open_hole /
    add_to_group("balls")     set_paddle_width(w) 同步 shape  blast_neighbors(pos,radius)
                              magnet 磁力标志               brick_upgrade_hooks.gd 注册实现
```

### 设计哲学

1. **数据驱动（AC1 字面）**：9 个升级 = 9 条定义（含 `effect: Callable`），`apply()` 统一走一个调用点；新增升级 = 加一条定义，零分支修改
2. **稀有度先掷（AC2 精确 60/30/10）**：每张卡独立掷稀有度，稀有度内均匀选升级——研究期 spike（PRD §7 S3，20000 次模拟）已证伪"升级粒度加权无放回"（边际分布漂移到 55.7/37.8/6.5）
3. **下一帧生效零机制（AC3）**：参数全部实例化后 `_process` 每帧读取实例属性 → 效果回调只写属性即天然下一帧生效，无需事件/信号机制（球读 `CollisionShape2D.shape.size.x` 已实例化，长臂即时感知）
4. **概念分层**：GameManager（#293）= 分数/局/场次（每分每秒）；UpgradePool = 每波成长决策（每波一次）——≥3 维度不同 → 独立 autoload，不并入 GameManager
5. **契约先行（AC4）**：#384 代码未落地 → upgrade_hooks 作为**增量契约**设计（不改变 #384 DESIGN 已合并的 `generate_wave/clear_wall/brick_destroyed/wall_cleared` API），假 grid 桩测试先行

### Prior Implementation Status（相关 Issue 的既有工作）

| 相关项 | 状态 | 本设计如何衔接 |
|--------|------|---------------|
| #383 轴交换+竖屏 | ✅ 已关闭（PR #409） | 720×1280 坐标系是挡板宽度/砖墙钩子的前提，无需改动 |
| #384 BreakoutGrid | ⚠️ DESIGN 已合并（PR #414），**代码未落地**（无 impl 分支、gdscripts 无 breakout 文件） | upgrade_hooks 契约 + 桩先行；`brick_upgrade_hooks.gd` 可对假 grid 测试；#384 落地后补集成测试 |
| #395 升级池文案 | 🔄 status/human-review（draft 已 merge） | 本 Issue **只读消费** JSON 显示字段，缺失回退工作名，不写文案 |
| #295 ball 参数实例化 | ✅ 已落地 | AC3 ball 侧已达标，仅补 `speed_scale` + `balls` 组 |
| #288 paddle const 参数 | ✅ 已落地（const 形式） | AC3 paddle 侧缺口，本设计改造 |

---

## 2. 现状核实与差距发现（plan agent 已对照源码）

| 文件 | 现状（已核实） | 与 #387 的差距 |
|------|---------------|---------------|
| `mini-pong/gdscripts/paddle.gd` | `const SPEED/PADDLE_WIDTH/PADDLE_HEIGHT`（来自 CONSTS）；`_process` 玩家/AI 两处读 `SPEED`（L104/L140）；`_ready` L71 用 `PADDLE_WIDTH` 算边界；`PADDLE_HEIGHT` **声明但零使用** | ❌ const → 实例属性；缺 `set_paddle_width()`；缺磁心升级所需 magnet 标志 |
| `mini-pong/gdscripts/ball.gd` | 5 个手感参数全部 `@export` + 实例读取（#295）；`_process` 位移 `position += velocity * delta`；未加入任何 group | ✅ AC3 ball 侧已达标；❌ 缺 `speed_scale`（缓时用）；缺可被池解析的稳定引用 |
| `mini-pong/gdscripts/constants.gd` | GameConstants 单一事实源（#295）；手感常量带 #367 定稿注释 | ❌ 无 UPGRADE_* 常量组 |
| `mini-pong/project.godot` | autoload：GameManager、AudioEngine | ❌ 未注册 UpgradePool |
| `mini-pong/tests/run_tests.gd` | 注册 14 个测试套件（`_run(path, name)` 模式） | ❌ 未注册升级池测试 |
| `mini-pong/tests/test_paddle.gd` | 12 自动 + 1 结构 + 1 CI 用例；`_make_paddle()` 用 `Area2D.new() + set_script` 模式 | ❌ 无实例属性/setter 用例 |
| `mini-pong/gdscripts/breakout_grid.gd` | **不存在**（#384 未落地） | ❌ upgrade_hooks 挂载点待增量契约 |
| `mini-pong/assets/content/upgrade_pool.json` | **不存在**（#395 implement 落地） | ❌ 本 Issue 只读消费，缺失必须兜底 |

### Gap Discovery（PRD 断言 vs 实际代码）

| PRD 断言 | 实际代码 | 设计决议 |
|----------|---------|---------|
| paddle `PADDLE_HEIGHT` 1 处直接引用 | **0 处**（仅 L10 声明） | 仍按 PRD 转为 `@export paddle_height`（AC3 完整性 + 未来用），无行为变化 |
| ball 修改仅 `speed_scale` | 池的 ctx 解析需要稳定球引用 | 额外 1 行：ball `_ready()` 加 `add_to_group("balls")`（池经 group 解析目标，headless 测试可注入覆盖） |
| 磁心升级 = 挡板磁力吸球 | paddle 无磁力概念 | paddle 新增 `magnet_enabled`/`magnet_pull_radius`/`magnet_pull_strength` 三个 `@export`（默认关，机械占位，数值归 taste） |
| upgrade_hooks 挂在 BreakoutGrid | breakout_grid.gd 不存在 | 契约先行：注册表 + 分发 API 定义于本设计 §3.3/§4；`brick_upgrade_hooks.gd` 提供实现，假 grid 桩可测 |
| #395 JSON 含 `rarity` 字符串（common/rare/legendary） | upgrade_pool.json 不存在 | 只读解析 + 逐字段兜底；机械稀有度以 `upgrade_defs.gd` enum 为准 |

---

## 3. 新组件 — 详细设计

### 3.1 `mini-pong/gdscripts/upgrade_defs.gd` — 9 升级定义单一事实源

- **File:** `mini-pong/gdscripts/upgrade_defs.gd`；`extends RefCounted`，`class_name UpgradeDefs`
- **职责:** 机械层 9 条升级定义的唯一来源。id 与 #395 JSON 对齐、跨文档不漂移；显示名运行时由 `UpgradePool` 从 JSON 覆盖，此处为**工作名兜底**
- **枚举:** `enum Rarity { COMMON = 0, RARE = 1, LEGENDARY = 2 }`（与 `UPGRADE_RARITY_WEIGHTS` 数组下标一一对应）
- **定义结构（每条 Dictionary）:**
  ```
  {
    "id": String,          # long_arm / fireball / battering_ram / magnet_core / twin / slow_time / pre_hole / stardust / phantom
    "name": String,        # 工作名（中文，兜底显示）
    "rarity": Rarity,      # COMMON / RARE / LEGENDARY
    "max_stacks": int,     # 1 = 整局至多一次；>1 = 可堆叠至 N
    "effect_desc": String, # 机械效果一句话（taste 文案以 JSON 为准）
    "effect": Callable     # 静态方法引用，签名 func(ctx: Dictionary) -> void
  }
  ```
- **API:** `static func definitions() -> Array[Dictionary]`（返回 9 条）；`static func by_id(id: String) -> Dictionary`（找不到返回 `{}`）
- **9 条定义（稀有度/效果来自 PLAN-rogue-pong §2.5；max_stacks 为机械占位，数值归 taste 域）:**

| id | 工作名 | 稀有度 | max_stacks | 效果签名（ctx 见 §3.2） | 实现级别 |
|----|--------|:------:|:----------:|------------------------|:--------:|
| `long_arm` | 长臂 | COMMON | 3 | `paddle.set_paddle_width(paddle.paddle_width + 0.3 * paddle.base_paddle_width)`（对基数加算，两次 → +60%） | ✅ 完整 |
| `fireball` | 燃烧弹 | COMMON | 3 | `ball.speed = min(ball.speed * 1.1, ball.initial_speed * ball.max_speed_multiplier)` + `grid.apply_upgrade_hook("blast_neighbors", {pos: ball.global_position, radius: R})` | ✅ 完整（grid 可空） |
| `battering_ram` | 破城锤 | COMMON | 3 | `grid.apply_upgrade_hook("blast_neighbors", {pos: ball.global_position, radius: R2})` | ✅ 完整（grid 可空） |
| `magnet_core` | 磁心 | RARE | 2 | `paddle.magnet_enabled = true`（`_process` 内磁力拉球，见 §4 paddle 修改） | ✅ 完整 |
| `twin` | 双生 | RARE | 1 | **回调桩**：`UpgradePool.mark_stub_effect("twin")`（分裂球需实例化场景 + Main.tscn 生命周期接线，超出本 Issue 机械范围） | 🟡 桩 + 说明 |
| `slow_time` | 缓时 | RARE | 2 | `ball.set_speed_scale_timed(0.0, 2.0)`（球速冻结 2s，_process 倒计时恢复） | ✅ 完整 |
| `pre_hole` | 预开洞 | RARE | 1 | `grid.apply_upgrade_hook("open_hole", {count: 1})`（下波 generate_wave 时生效） | ✅ 完整（grid 可空） |
| `stardust` | 星尘 | LEGENDARY | 1 | **回调桩**：`mark_stub_effect("stardust")`（穿墙轨迹伤害需场景实例化，独立小 PR 深化） | 🟡 桩 + 说明 |
| `phantom` | 幻影 | LEGENDARY | 1 | **回调桩**：`mark_stub_effect("phantom")`（挡板残影多段判定需视觉 + 碰撞规则变化，独立小 PR 深化） | 🟡 桩 + 说明 |

> **桩决策（PRD §5 边界 8 授权 plan agent 定夺）:** twin/stardust/phantom 的效果回调本期以**可调用、可断言、不崩溃**的桩落地（写 `UpgradePool.stub_activated[id] = true` 状态 + `push_warning` 说明），完整实现随 #384 落地后以独立小 PR 深化；桩使 `apply()` 链路与抽取/计数/不可重复语义全量可测。6/9 效果（long_arm/fireball/battering_ram/magnet_core/slow_time/pre_hole）机械完整实现。

- **效果实现位置:** 静态方法集中于 `UpgradeDefs`（如 `static func _effect_long_arm(ctx: Dictionary) -> void`），定义表用 `Callable(UpgradeDefs, "_effect_long_arm")` 引用——单测可直接 `def.effect.call(test_ctx)` 独立验证

### 3.2 `mini-pong/gdscripts/upgrade_pool.gd` — autoload 单例

- **File:** `mini-pong/gdscripts/upgrade_pool.gd`；`extends Node`；`project.godot` 注册 `UpgradePool="*res://gdscripts/upgrade_pool.gd"`
- **Node structure:** 无场景依赖，纯逻辑单例（autoload 节点）
- **Signals:** `signal upgrade_applied(upgrade_id: String)`（供 #388 UI 与 #386 波次后续消费；本 Issue 不接线）
- **State Properties:**
  ```
  var rng: RandomNumberGenerator = RandomNumberGenerator.new()   # 可 seed()，测试/自动对打确定性
  var stacks: Dictionary = {}          # id → 已拿次数
  var stub_activated: Dictionary = {}  # id → true（桩效果标记，可断言）
  var _available: Array[Dictionary] = []   # 未耗尽定义池（max_stacks 未达上限）
  var _display: Dictionary = {}        # id → {name_working, short_phrase, naming_candidates}（来自 #395 JSON）
  var ball_ref: Node2D = null          # 目标解析缓存；测试可直接注入覆盖
  var paddle_ref: Node2D = null
  var grid_ref: Node = null
  ```
- **Key Methods:**
  ```
  func _ready() -> void:
      _available = UpgradeDefs.definitions().duplicate()
      _load_display_names()            # 只读消费 #395 JSON，失败静默兜底

  func get_candidates(n: int = CONSTS.UPGRADE_CANDIDATE_COUNT) -> Array[Dictionary]:
      # 每张卡独立走一次稀有度先掷（AC2 精确 60/30/10）
      # 1. rarity = _roll_rarity()  （rng.randi_range(1,100) 映射 60/30/10）
      # 2. eligible = [d for d in _available if d.rarity == rarity and d.id not in picked_ids]
      # 3. eligible 空 → 回退链: 按 [COMMON, RARE, LEGENDARY] 找第一个非空稀有度
      #    再空（全局耗尽）→ 返回已收集（可能 < n）
      # 4. 均匀随机选一个 → 附加 display 元数据 → 加入候选
      # 返回 Array[Dictionary]: 每项 {id, name, rarity, max_stacks, effect_desc, display}
      # 候选内 id 互异（去重保证）

  func apply(upgrade_id: String) -> bool:
      # def = UpgradeDefs.by_id(upgrade_id); def 空 或 不在 _available → return false
      # ctx = _build_ctx()  → {ball, paddle, grid, params}
      # def.effect.call(ctx)           （桩效果 → mark_stub_effect）
      # stacks[id] += 1
      # if stacks[id] >= def.max_stacks: _available.erase(def)   （整局不可重复语义）
      # upgrade_applied.emit(upgrade_id)
      # return true

  func get_definitions() -> Array[Dictionary]: return UpgradeDefs.definitions()
  func get_stacks(id: String) -> int: return stacks.get(id, 0)
  func _roll_rarity() -> Rarity: ...      # 60/30/10 权重映射
  func _build_ctx() -> Dictionary: ...    # 惰性解析 ball/paddle/grid（见下）
  func _load_display_names() -> void: ... # FileAccess + JSON.parse_string，见 §4 JSON 契约
  func reload_display_names() -> void: ...# 可选：运行时重载
  ```
- **目标解析（`_build_ctx`）:** 惰性 + 可注入——
  ```
  ball_ref   = ball_ref   or get_tree().get_first_node_in_group("balls")     # ball.gd _ready 加组
  paddle_ref = paddle_ref or get_tree().get_first_node_in_group("paddles")   # paddle.gd 已有该组
  grid_ref   = grid_ref   or get_tree().get_first_node_in_group("breakout_grids")  # #384 落地时加组（契约）
  ```
  任一为 null 时效果回调自行判空（grid 类效果 no-op + 不崩）；headless 测试直接注入 `ball_ref/paddle_ref/grid_ref`（含假 grid），无需场景树
- **Integration notes:** 池**不主动触发任何流程**——`get_candidates` 由 #386 清墙结算调用、`apply` 由 #388 UI 调用；本 Issue 不接线，避免与并行 PR 冲突

### 3.3 `mini-pong/gdscripts/brick_upgrade_hooks.gd` — 砖类升级效果实现

- **File:** `mini-pong/gdscripts/brick_upgrade_hooks.gd`；`extends RefCounted`，`class_name BrickUpgradeHooks`
- **职责（PRD §4.5-A 字面）:** 向 BreakoutGrid 的 `upgrade_hooks` 注册表注册砖类效果实现；`BreakoutGrid._ready()` 调用 `BrickUpgradeHooks.register_all(self)` 完成接线（**grid 侧拥有注册时机**，避免钩子文件自行找节点）
- **API:**
  ```
  static func register_all(grid: Node) -> void:
      grid.register_upgrade_hook("open_hole", Callable(BrickUpgradeHooks, "_open_hole"))
      grid.register_upgrade_hook("blast_neighbors", Callable(BrickUpgradeHooks, "_blast_neighbors"))

  static func _open_hole(ctx: Dictionary) -> void:
      grid.open_hole(ctx.get("count", 1))          # generate_wave 后补开洞（复用 #384 hole 布局逻辑）

  static func _blast_neighbors(ctx: Dictionary) -> void:
      grid.blast_neighbors(ctx.get("pos", Vector2.ZERO), ctx.get("radius", 0.0))
  ```
- **测试友好:** `register_all(fake_grid)` 对**假 grid**（普通对象 + 三个方法）即可断言注册与分发链路，不依赖 #384 落地
- **不变量:** 不修改 #384 DESIGN 已合并的 API（`generate_wave(thickness, layout, seed)`/`clear_wall`/`brick_destroyed`/`wall_cleared`）

---

## 4. 现有组件修改

### 4.1 修改文件清单

| 文件 | 改动 | 为什么 |
|------|------|--------|
| `mini-pong/gdscripts/paddle.gd` | `const SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` → `@export var paddle_speed/paddle_width/paddle_height`（默认值仍 = CONSTS）；新增 `base_paddle_width`、`set_paddle_width(w)`、磁心三 export；两处 `SPEED` 引用改 `paddle_speed`、`_ready` 边界用 `paddle_width` | AC3 字面：参数实例级；长臂/幻影升级入口；磁心效果承载 |
| `mini-pong/gdscripts/ball.gd` | 新增 `@export var speed_scale: float = 1.0` + `_process` 位移乘 `speed_scale`；新增 `set_speed_scale_timed(scale, duration)`（`_slow_time_remaining` 倒计时恢复）；`_ready` 加 `add_to_group("balls")` | 缓时冻结 2s；池 ctx 解析稳定引用（gap 决议） |
| `mini-pong/gdscripts/constants.gd` | 新增「── Upgrade Pool (#387) ──」组：`UPGRADE_RARITY_WEIGHTS=[60,30,10]`、`UPGRADE_CANDIDATE_COUNT=3`、`UPGRADE_POOL_SIZE=9`、`UPGRADE_JSON_PATH="res://assets/content/upgrade_pool.json"` | 遵循 #295 单一事实源惯例 |
| `mini-pong/project.godot` | `[autoload]` 追加 `UpgradePool="*res://gdscripts/upgrade_pool.gd"` | autoload 单例注册（2 → 3 个） |
| `mini-pong/tests/run_tests.gd` | `_run("res://tests/test_upgrade_pool.gd", "Upgrade Pool")`（置于 test_constants 之后） | 测试即验收 |
| `mini-pong/tests/test_paddle.gd` | 新增实例属性用例（§9 Scenario F） | AC3 回归覆盖 |
| `mini-pong/gdscripts/breakout_grid.gd` | **增量契约（随 #384 落地）**：`var upgrade_hooks: Dictionary = {}`、`register_upgrade_hook(id, cb)`、`apply_upgrade_hook(id, ctx) -> bool`、`open_hole(count)`、`blast_neighbors(pos, radius)`；`_ready` 加 `add_to_group("breakout_grids")` + 调 `BrickUpgradeHooks.register_all(self)` | AC4 字面满足；不改 #384 既有 API |

### 4.2 paddle.gd 伪代码（implement 契约）

```gdscript
# ── const 移除，改为实例属性（默认值仍来自 CONSTS，#367 定稿值不变）──
@export var paddle_speed: float = CONSTS.PADDLE_SPEED
@export var paddle_width: float = CONSTS.PADDLE_WIDTH
@export var paddle_height: float = CONSTS.PADDLE_HEIGHT
var base_paddle_width: float = CONSTS.PADDLE_WIDTH   # _ready 时捕获（长臂加算基准）

# ── 磁心（#387 新增，默认关；数值占位归 taste 域）──
@export var magnet_enabled: bool = false
@export var magnet_pull_radius: float = 180.0
@export var magnet_pull_strength: float = 600.0

func set_paddle_width(w: float) -> void:
    paddle_width = w
    var cs := $CollisionShape2D as CollisionShape2D   # 同步碰撞体（球读 shape.size.x → 即时感知）
    if cs != null and cs.shape is RectangleShape2D:
        cs.shape.size.x = w
    _recalc_bounds()                                   # min_x/max_x 重算 + position.x clamp

func _recalc_bounds() -> void:
    var half_width := paddle_width / 2.0
    min_x = half_width
    max_x = (viewport_w 或 FALLBACK) - half_width
    position.x = clamp(position.x, min_x, max_x)

# _process 改动点：
#   玩家分支: position.x += move * paddle_speed * delta
#   AI 分支:  position.x += move * paddle_speed * factor * delta
#   新增磁力段: if magnet_enabled and _ball_node != null:
#       if abs(_ball_node.global_position.x - position.x) <= magnet_pull_radius:
#           position.x = move_toward(position.x, _ball_node.global_position.x, magnet_pull_strength * delta)
#       position.x = clamp(position.x, min_x, max_x)
```

### 4.3 ball.gd 伪代码（implement 契约）

```gdscript
# 新增（其余 5 参数已实例级，仅验证）
@export var speed_scale: float = 1.0
var _slow_time_remaining: float = 0.0

func _ready() -> void:
    add_to_group("balls")            # 池 ctx 解析（gap 决议）
    # ... 既有逻辑不变 ...

func _process(delta: float) -> void:
    # ... 既有守卫不变 ...
    if _slow_time_remaining > 0.0:               # 定时恢复（不依赖 SceneTreeTimer，headless 可测）
        _slow_time_remaining -= delta
        if _slow_time_remaining <= 0.0:
            speed_scale = 1.0
    position += velocity * delta * speed_scale   # 缓时冻结：speed_scale=0 → 位移 0
    # ... 其余逻辑不变 ...

func set_speed_scale_timed(scale: float, duration: float) -> void:
    speed_scale = scale
    _slow_time_remaining = duration              # 重复施放 = 重置倒计时（可堆叠语义）
```

### 4.4 #395 JSON 只读消费契约（upgrade_pool.gd 内部）

```
路径:   res://assets/content/upgrade_pool.json（#395 implement 落地；本 Issue 不写）
加载:   FileAccess.get_file_as_string + JSON.parse_string（零第三方依赖，headless/CI 安全）
校验:   dict["schema"] == "upgrade-pool-content/v1"；dict["upgrades"] 为 Array
映射:   id → {name_working, short_phrase, naming_candidates}
兜底:   文件缺失 / 解析失败 / schema 不符 / 单条缺 id → 该项回退 upgrade_defs.gd 工作名，
        push_warning 一次（不 spam），游戏继续 —— #395 定稿前容错
```

### 4.5 文件分类汇总

- **New files:** `upgrade_defs.gd`、`upgrade_pool.gd`、`brick_upgrade_hooks.gd`（实现阶段新增 `tests/test_upgrade_pool.gd`）
- **Modified:** `paddle.gd`、`ball.gd`、`constants.gd`、`project.godot`、`tests/run_tests.gd`、`tests/test_paddle.gd`、`breakout_grid.gd`（增量，随 #384）
- **Removed/Deprecated:** 无
- **Affected test files:** `tests/test_upgrade_pool.gd`（新套件）、`tests/test_paddle.gd`（增实例属性用例）、`tests/run_tests.gd`（注册）；`test_ball.gd` 可选补 speed_scale 用例（非阻塞）

---

## 5. 数据流

### Flow 1: 每波 3 选 1（正常路径，跨 Issue 协作）

```
#386 清墙 → wall_cleared → 波次结算
  └─► UpgradePool.get_candidates(3)                    [本 Issue 交付]
        ├─ 掷稀有度(60/30/10) ×3 → 稀有度内均匀选 → 候选去重
        └─ 返回 [{id,name,rarity,max_stacks,effect_desc,display}] ×3
  └─► #388 UI 渲染三卡（稀有度后置 reveal，UI 决策）    [本 Issue 不接线]
  └─► 玩家确认 → #388 调 UpgradePool.apply(id)         [本 Issue 交付]
        ├─ stacks[id] += 1
        ├─ def.effect.call({ball,paddle,grid,params})
        ├─ max_stacks 达上限 → 移出 _available（整局不可重复）
        └─ upgrade_applied.emit(id)
  └─► 效果只写实例属性 → 下一帧 _process 读取 → 下一帧生效（AC3）
```

### Flow 2: apply 失败路径

```
apply(id):
  id 不在定义表      → return false（调用方 #388 忽略，无副作用）
  id 已耗尽(移出池)  → return false（UI 不应再展示该卡；防御性返回）
  effect 内部目标缺失 → 各效果判空（grid 类 no-op + push_warning；ball/paddle 类若 null 则记录并跳过）
```

### Flow 3: 抽取回退（边界）

```
get_candidates(3) 第 i 张卡：
  掷出 LEGENDARY，但 2 个传说都在候选/已耗尽 → eligible 空
  → 回退链 [COMMON, RARE, LEGENDARY] 取第一个非空稀有度
  → 全局 _available 空 → 返回已收集候选（<3，UI 按实际数量渲染）
```

### Flow 4: JSON 显示名兜底

```
_ready → _load_display_names()
  FileAccess 打开失败 → 全部回退工作名，push_warning ×1
  JSON 解析失败/schema 不符 → 同上
  单条 id 缺失 → 该项回退工作名
  成功 → get_candidates 每项 display 字段带 JSON 值（UI reveal 用）
```

---

## 6. 边界条件与错误处理

| # | 边界场景 | 缓解 |
|---|---------|------|
| 1 | 某稀有度抽空（如传说仅 2 个且已全部在候选/耗尽） | 回退链 [COMMON→RARE→LEGENDARY] 取首个非空；仍空则返回少于 n 的候选（§5 Flow 3）；测试钉死回退顺序 |
| 2 | 候选内重复 | 每张卡选后 `picked_ids` 去重；同稀有度可多张（如 3 张全普通），但升级 id 互异 |
| 3 | 不可重复语义（`max_stacks=1`） | `apply()` 达上限即从 `_available` 移除 = **整局**至多一次（区别于"一次候选内不重复"）；移除后 `get_candidates` 不再出现 |
| 4 | 堆叠语义（`max_stacks>1`） | `stacks[id]` 计数；长臂对**基数**加算（两次 → +60%，PRD 场景 C 字面）；缓时重复施放重置倒计时 |
| 5 | rng 可复现性 | `UpgradePool.rng.seed()` 注入；统计测试固定种子 + 大样本；生产默认随机 |
| 6 | #395 JSON 缺失/解析失败/缺字段 | §4.4 逐级兜底回退工作名，`push_warning` 一次，游戏不崩 |
| 7 | #384 未落地（grid 为 null） | fireball/battering_ram/pre_hole 效果判空 no-op；`register_all` 对假 grid 可测；集成测试随 #384 补齐 |
| 8 | 手感常量默认值（#367 定稿） | **只允许运行时实例级修改**；constants.gd 只新增 UPGRADE_* 组，BALL_*/PADDLE_*/AI_* 默认值零改动 |
| 9 | 双生/星尘/幻影需场景实例化 | 回调桩（`stub_activated` 标记 + warning），apply 链路全量可测；完整实现独立小 PR 深化（§3.1 桩决策） |
| 10 | 缓时冻结期间球速变化 | `speed_scale` 只乘位移，velocity/speed 不变；恢复 1.0 后速度衔接无跳变 |
| 11 | 发球/暂停态 | `_is_serving` 期间 `_process` 早退、`frozen` 挡板不动 → 升级效果写属性无冲突；`speed_scale` 在恢复帧重新生效 |
| 12 | 同帧多升级（理论不可能，防御） | `apply` 串行调用，每调用独立 `_available` 快照；`upgrade_applied` 逐次 emit |

**失败路径（≥4）:**
1. **apply 未知/已耗尽 id** — 查表失败返回 `false`，不计数、不 emit、不崩
2. **ctx 目标为 null 时效果执行** — 各效果回调显式判空（grid 类 no-op；ball/paddle 类跳过并 `push_warning`），桩效果只写标记
3. **JSON 加载半损坏** — 解析成功但单条缺字段 → 该项回退工作名，其余项正常（不整体回退）
4. **`_available` 耗尽后仍被调用** — `get_candidates` 返回空/短数组而非报错；`apply` 返回 false

---

## 7. 集成点

> **状态约定:** ⬜ = pending（资源已设计/创建，尚未接线）；✅ = connected（implement agent 验证）。implement 完成后必须更新本表；review agent 在合并前核对全部 ⬜ 已解决或显式延期。

| 集成 | 我方组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 波次结算取卡 | `UpgradePool.get_candidates(3)` | #386 | 清墙 → 调接口 | ⬜ pending |
| 三卡数据 + 确认应用 | `get_candidates` / `apply(id)` | #388 | UI 数据入口（`upgrade_applied` 信号可监听） | ⬜ pending |
| 效果目标（球） | `ball.gd` `balls` 组 + `speed_scale`/`set_speed_scale_timed` | #387 | ctx 惰性解析 + 实例属性写入 | ⬜ pending |
| 效果目标（挡板） | `paddle.gd` `paddles` 组 + `set_paddle_width`/`magnet_*` | #387 | ctx 惰性解析 + 实例属性写入 | ⬜ pending |
| 砖墙钩子注册/分发 | `brick_upgrade_hooks.gd` + `BreakoutGrid.upgrade_hooks` | #384（未落地） | `register_all(grid)`；效果经 `apply_upgrade_hook(id, ctx)` | ⬜ pending（契约先行） |
| 显示字段只读 | `upgrade_pool.gd._load_display_names()` | #395 | `FileAccess` + `JSON.parse_string` + 逐级兜底 | ⬜ pending |

---

## 8. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | `constants.gd` UPGRADE 组 → `upgrade_defs.gd`（9 定义 + 6 完整效果 + 3 桩） | 1 天 |
| Phase 2 | P0 | `upgrade_pool.gd`（autoload：抽取/apply/rng/JSON 兜底/ctx 解析） | 1 天 |
| Phase 3 | P0 | `paddle.gd` 实例化 + `set_paddle_width` + magnet；`ball.gd` speed_scale + `balls` 组 | 0.5 天 |
| Phase 4 | P0 | `project.godot` 注册 + `run_tests.gd` 注册 + `test_upgrade_pool.gd` + `test_paddle.gd` 用例 | 1 天 |
| Phase 5 | P1 | `brick_upgrade_hooks.gd` + `breakout_grid.gd` 增量契约（随 #384 落地；假 grid 桩先行） | 0.5 天（契约）+ 随 #384 |

依赖顺序：1→2→3→4 严格串行；Phase 5 与 #384 实现耦合，可并行推进契约与桩测试。

---

## 9. 测试用例描述（仅描述，implement 依此写代码）

> 本 PR 不写 runnable 测试文件。以下为 `tests/test_upgrade_pool.gd`（新套件，场景 A–I）与 `tests/test_paddle.gd`（场景 F 增量）的规格。共 **27 条**。

### Scenario A: 9 定义完整性（AC1）— 4 条
- **TC-A1** 定义齐全：`UpgradePool.get_definitions().size() == 9`；9 个 id 恰为 long_arm/fireball/battering_ram/magnet_core/twin/slow_time/pre_hole/stardust/phantom
- **TC-A2** 每条定义含 id/name/rarity/max_stacks/effect_desc 且 `effect is Callable`（AC1 字面）
- **TC-A3** 稀有度分布：COMMON=3（长臂/燃烧弹/破城锤）、RARE=4（磁心/双生/缓时/预开洞）、LEGENDARY=2（星尘/幻影）
- **TC-A4** `by_id("long_arm")` 命中；`by_id("unknown")` 返回空 Dictionary（不崩）

### Scenario B: 稀有度先掷 60/30/10（AC2）— 4 条
- **TC-B1** 单卡权重映射：固定种子下 `_roll_rarity()` 落在 1–60→COMMON、61–90→RARE、91–100→LEGENDARY
- **TC-B2** 统计断言：固定种子 + 20000 次 `get_candidates(3)` 采样，全部 60000 张卡稀有度频率落在 60±5% / 30±5% / 10±5%
- **TC-B3** 候选每项携带 `rarity` 元数据（UI 后置 reveal 的数据前提）
- **TC-B4** 每张卡独立掷稀有度：候选可含 2–3 张同稀有度（如全普通），不强制均匀

### Scenario C: 候选内去重 — 2 条
- **TC-C1** `get_candidates(3)` 返回 3 个**互异** id（同一稀有度可多张，但升级不重复）
- **TC-C2** 池内只剩 2 个未耗尽升级时返回 2 个（不报错、不补重复）

### Scenario D: 不可重复 / 堆叠（AC2）— 5 条
- **TC-D1** `max_stacks=1`（星尘）：`apply("stardust")` 成功且 `get_stacks==1`；再 `apply` 返回 false；后续 `get_candidates` 不再出现 stardust（整局语义）
- **TC-D2** `max_stacks>1`（长臂）：连续 apply 两次均成功，`get_stacks("long_arm")==2`
- **TC-D3** 堆叠到上限后：第 4 次 `apply("long_arm")`（max_stacks=3）返回 false 且不再入候选
- **TC-D4** 候选去重与整局不可重复正交：stardust 未拿时可在候选出现一次；拿过后全局消失
- **TC-D5** `get_stacks` 对未拿升级返回 0

### Scenario E: apply 链路与效果回调（AC5）— 5 条
- **TC-E1** `apply("long_arm")`：注入假 paddle，断言 `set_paddle_width` 被调用且新宽度 = 基数 ×1.3（两次后 ×1.6，加算语义）
- **TC-E2** `apply("slow_time")`：注入假 ball，断言 `set_speed_scale_timed(0.0, 2.0)` 被调用（参数精确）
- **TC-E3** `apply("magnet_core")`：注入假 paddle，断言 `magnet_enabled == true`
- **TC-E4** 桩效果（twin/stardust/phantom）：`apply` 返回 true、`stub_activated[id] == true`、无异常抛出
- **TC-E5** `upgrade_applied` 信号在成功 apply 时恰好 emit 一次（id 参数正确）；失败 apply 不 emit

### Scenario F: 实例参数下一帧生效（AC3）— 5 条（`test_paddle.gd` 增量 + ball 可选）
- **TC-F1** `set_paddle_width(156)` 后 `paddle_width == 156` 且 `CollisionShape2D.shape.size.x == 156`（同步）
- **TC-F2** setter 后 `min_x/max_x` 按新宽度重算，`position.x` 被 clamp 回合法区间
- **TC-F3** 玩家分支 `_process` 使用 `paddle_speed` 实例值：改实例属性后模拟一帧，位移 = `move * paddle_speed * delta`（新值生效 = 下一帧生效）
- **TC-F4** AI 分支同样读 `paddle_speed`（改值后 AI 帧位移变化）
- **TC-F5** ball `speed_scale`：设 0.0 后 `_process` 位移为 0；`set_speed_scale_timed(0.0, 2.0)` 后经 2s（模拟帧）恢复 1.0（`test_ball.gd` 可选）

### Scenario G: JSON 显示名兜底（#395 只读消费）— 3 条
- **TC-G1** 文件存在且 schema 正确：`get_candidates` 的 `display` 字段取 JSON 值（name_working/short_phrase/naming_candidates）
- **TC-G2** 文件缺失/解析失败：全部回退工作名，游戏不崩，`push_warning` 至多一次
- **TC-G3** 单条缺字段：该项回退工作名，其余项正常取 JSON 值

### Scenario H: upgrade_hooks 注册表（AC4，契约先行）— 3 条
- **TC-H1** `BrickUpgradeHooks.register_all(fake_grid)` 后 `fake_grid.upgrade_hooks` 含 open_hole/blast_neighbors 两个 Callable
- **TC-H2** `fake_grid.apply_upgrade_hook("blast_neighbors", {pos, radius})` 分发到注册实现；未注册 id 返回 false
- **TC-H3** 效果在 grid 为 null 时：`apply("pre_hole")` 返回 true 且不崩（no-op 路径）

### Scenario I: rng 可播种确定性 — 1 条
- **TC-I1** 同一种子两次完整 `get_candidates(3)` 序列完全一致；不同种子序列不同

### Scenario J: 注册与回归 — 1 条
- **TC-J1** `run_tests.gd` 注册 "Upgrade Pool" 套件；`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含既有 14 套件回归）

---

## 10. 验收标准映射（Issue #387 五条 AC）

| AC | 验收标准 | 设计覆盖 |
|----|---------|---------|
| AC1 | 9 个独立升级定义（id/名称/稀有度/效果回调） | §3.1 定义表 + `effect: Callable`；TC-A1/A2 |
| AC2 | 60/30/10 权重抽取 + 不可重复/堆叠配置 | §3.2 稀有度先掷 + `max_stacks`；TC-B2 统计 / TC-D1–D3 |
| AC3 | 参数实例级 + 下一帧生效 | §4.2/§4.3 const→@export + 每帧读取；TC-F1–F5 |
| AC4 | 预开洞等砖墙升级走 BreakoutGrid upgrade_hooks | §3.3 + §4.1 增量契约；TC-H1–H3（桩先行） |
| AC5 | `get_candidates(3)` 与 `apply(upgrade_id)` 接口 | §3.2 公共 API；TC-B/C/E 全链路 |

---

## 11. 验证步骤（implement 执行顺序）

1. `constants.gd` UPGRADE 组 → 2. `upgrade_defs.gd` → 3. `upgrade_pool.gd` → 4. `paddle.gd`/`ball.gd` 实例化 → 5. `project.godot` 注册 → 6. `run_tests.gd` 注册 + `test_upgrade_pool.gd` + `test_paddle.gd` 用例 → 7. `brick_upgrade_hooks.gd`（桩/随 #384）
8. 本地验证：
   - `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含既有回归）
   - `godot --path mini-pong/ --headless --quit` 编译通过（autoload 注册无解析错误）
   - `project.godot` git diff 仅含新增 autoload 行；constants 手感默认值（#367）diff 为空
9. E2E：`e2e_shots.json` 现有 shot 不涉及升级卡（#388 落地前无 UI）——本 Issue 无 E2E 影响

---

## 12. 不做的事（范围边界，明确排除）

- ❌ **3 选 1 UI**（#388）：三卡渲染/焦点/reveal/暂停全部归 #388；本 Issue 只交数据接口
- ❌ **波次循环**（#386）：清墙→结算→新墙归 #386；池不主动触发任何流程
- ❌ **双得分制**（#385）：拆砖/穿墙分不碰
- ❌ **升级文案**（#395）：upgrade_pool.json 由 #395 implement 落地；#387 只读消费，缺失兜底
- ❌ **Main.tscn 接线**：池/球/挡板/砖墙接线归 #386/#388/#393，本 Issue 不改场景
- ❌ **手感常量默认值**（#367 定稿）：只允许运行时实例级修改，constants 只新增 UPGRADE_* 组
- ❌ **双生/星尘/幻影完整实现**：回调桩 + 说明，独立小 PR 深化（§3.1 桩决策）
- ❌ **音效** `play_upgrade_pick`（可选 Stretch，归音频域）
- ❌ **第三方资产**：开源优先调研（PRD §1.4）结论 = 无可复用升级池系统，第一方实现、零依赖
- ❌ **写 runnable 测试文件于本 PR**：测试归 implement PR（本 PR 仅 DESIGN 文档）

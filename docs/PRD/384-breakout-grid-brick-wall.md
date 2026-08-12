# PRD: [Feature] 砖墙系统 (BreakoutGrid)

> **Issue:** #384
> **标签:** enhancement, gameplay, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验补齐）
> **所有权:** `content_ownership: mechanical`（程序化生成 + 碰撞 + 信号，无 taste 决策；波次数值/配色归 taste-draft Issue）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.3 砖墙语义（已确认）+ §4.2 主玩法改造（"新: 砖墙系统 (BreakoutGrid + 碰撞 + 程序生成)"）
> **前置依赖:** #383（轴交换+竖屏，**已关闭**，PR #409 已合并）→ 本 Issue 建立于 720×1280 竖屏坐标系

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280，PR #409 后）**不存在任何可破坏地形**：球只与左右墙（StaticBody2D，X 分量反弹）和上下挡板（Area2D，角度反弹）交互；场景中没有砖墙节点、没有波次/墙体概念、没有拆砖事件。Rogue Pong 的核心对象（中立砖墙）完全缺失。

| 文件 | 当前状态 | 与 #384 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/ball.gd` | `_on_body_entered` 只处理 `walls` 组（X 反弹）；`_on_area_entered` 只处理 `paddles` 组（角度反弹） | ❌ 无 `bricks` 分支：球碰砖 → 砖碎 + 反弹（AC2）不存在 |
| `mini-pong/scenes/Main.tscn` | LeftWall/RightWall（竖屏 10×1280）、ScoreZoneTop/Bottom、Ball、双挡板、FSM/ScoringManager | ❌ 无 BreakoutGrid 节点（接线归 #393，见 §1.5 范围边界） |
| `mini-pong/scenes/ball.tscn` | `collision_layer=4`（第 3 层）、`collision_mask=3`（第 1+2 层） | ✅ **第 2 层空闲**：砖放第 2 层即被球检测到，**零 mask 配置改动** |
| `mini-pong/scenes/player_paddle.tscn` / 左右墙 | 挡板 Area2D 第 1 层、墙 StaticBody2D 第 1 层 | ✅ 层分配互不冲突（第 1 层=墙/挡板，第 2 层=砖，第 3 层=球） |
| `mini-pong/gdscripts/constants.gd` | SCREEN 720/1280、球/挡板/手感常量（#295 单一事实源） | ❌ 无砖墙常量（BRICK_SIZE/GAP/WALL_Y） |
| `mini-pong/tests/run_tests.gd` | 注册 14 个测试套件 | ❌ 无砖墙测试 |
| `mini-pong/tests/test_ball.gd` | 墙反弹/挡板反弹/得分/发球用例 | ❌ 无砖块反弹用例 |

**碰撞层/掩码事实核查（来自源码，方案 A 可行性的关键依据）：**

- 球 `ball.tscn`：`collision_layer = 4`（bit 3），`collision_mask = 3`（bit 1 + bit 2）
- 墙 `Main.tscn` LeftWall/RightWall：StaticBody2D，默认 layer 1 → 球 `body_entered` 触发
- 挡板 `player_paddle.tscn`：Area2D，默认 layer 1 → 球 `area_entered` 触发
- 得分区：Area2D `collision_mask = 4`（只监听球的 layer 3）
- **结论**：砖放 **layer 2**（bit 2），球现有 mask 已含 bit 2 → Area2D(球) 对 StaticBody2D(砖) 的 `body_entered` 立即生效，`ball.tscn`/`project.godot` **无需任何改动**。

### 预期行为（验收条件，源自 Issue #384）

1. **AC1 — 每波可生成至少 1 面横跨屏幕的砖墙，砖块布局包含留缝、错位和缺口** — BreakoutGrid 程序化生成横跨 720px 的砖墙；布局枚举含 `GAPS`（留缝）、`OFFSET`（错位）、`HOLES`（缺口）三种模式（可加 `MIXED` 组合模式贴合 PLAN §2.3 的 ASCII 示意图）
2. **AC2 — 球与砖块碰撞后砖块移除并反弹，反弹方向符合物理规则** — Breakout 式 dominant-axis 反弹（`|vx| ≥ |vy|` 翻 X，否则翻 Y）；砖块同一处理内原子销毁（碎）+ 反弹，无幽灵反弹
3. **AC3 — 洞口/缺口区域无碰撞体，球可自由穿过** — 缺口 = 该位置不实例化砖节点（无 StaticBody2D），穿洞即穿墙得分路径（#385 消费）
4. **AC4 — 砖墙打空后只发出一次 wall_cleared 信号** — BreakoutGrid 维护 `remaining_bricks` 计数 + `_wall_cleared_emitted` 守卫；`generate_wave()` 时重置
5. **AC5 — 生成参数集中在 BreakoutGrid 配置中，可驱动波次厚度/形状** — `@export` 参数（砖尺寸/留缝/布局/行数/洞数/种子/墙 Y）+ `generate_wave(thickness, layout, seed)` API，供 #386 波次循环驱动

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 对打拆砖 | 每局每回合 | 玩家（底部）把球打向中间砖墙，碰砖 → 砖碎 + 反弹；拆砖分归属最后触球方（#385），剩余砖数上 HUD（#393） |
| B | 穿洞得分 | 每局多次 | 球穿过缺口/留缝到达 AI 底线 → 穿墙分 3 分（#385）；洞口无碰撞体保证直飞路径 |
| C | 波次重置 | 每波结束 | 整墙打空 → `wall_cleared` 一次 → #386 波次循环结算/升级 → 以更厚/新形状参数调 `generate_wave()` 生成新墙 |

### 技术约束（继承自 Issue #384 + PLAN-rogue-pong）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，720×1280 竖屏，resizable=false） |
| 布局语义 | 砖墙横跨 720px（X 方向铺满），位于 AI 挡板（y=40）与玩家挡板（y=1240）之间，默认 `wall_y=640`（球发球位） |
| 不变项 | FSM（#294）、scoring 信号链（#291/#295）、手感数值（#367）不变；`ball.gd` 仅新增 bricks 分支，不重构既有碰撞逻辑 |
| 信号契约 | 本 Issue 定义 `brick_destroyed`（供 #385 拆砖分）与 `wall_cleared`（供 #386 波次重置）两个信号，**不实现计分/波次逻辑** |
| 所有权 | `content_ownership: mechanical` — 生成算法/碰撞/信号为机械实现；波次厚度数值、配色、砖硬度等 taste 内容不在本 Issue |
| 开源优先 | 调研结果见 §1.4 |

### 1.4 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索，GDScript/Godot 4.x 过滤）：

- **Godot Asset Library**（assetlibrary.godotengine.org，godot_version=4.7，sort=updated）：`breakout` 过滤 **0 结果**（`total_items: 0`）；`brick`/`brick breaker` 无程序化砖墙生成插件（仅零星工具/绘图资产）
- **GitHub 搜索**（`godot breakout` 235 仓库，按 star 排序）：全部为 **独立完整游戏克隆**（<5⭐，如 seoLegna/08-Breakout 1⭐、YeOldeDM/godot-breakout-example 3⭐）；最高分 didier-v/breakable（64⭐）是完整 Breakout 游戏 demo 而非可插拔砖墙生成模块
- **GitHub 搜索**（`godot brick breaker`）：同样为完整游戏克隆（Soulzerz/godot_brick_breaker 4⭐ 等），无网格生成/可破坏地形插件
- **结论**：**没有可复用的「程序化砖墙生成 + 可破坏地形」插件/模板**；本功能为第一方实现，Godot 4.7 内置能力（StaticBody2D/Area2D 信号、场景实例化、`queue_free`）完全覆盖，**不引入任何第三方资产**。与 #383 的调研结论模式一致。

### Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（WebDAV，`OBSIDIAN_VAULT_PATH`），本会话 `Knowledge Ocean` 目录读取超时（挂载延迟），未能直接检索到砖墙相关笔记
- **兜底**：砖墙设计决策已由 `docs/PLAN-rogue-pong.md` §2.3 固化并引用 Obsidian《体验引擎》理论 —— 中立墙语义（砖=可破坏反弹地形、洞口=无碰撞通道、墙空=一局结束）、拆砖分归属最后触球方（§2.2）；GDD `docs/GAME_DESIGN/13-BALL-PHYSICS.md`、`10-SCENE-LAYOUT.md` 提供物理/场景约定
- 后续阶段（plan/implement）如需，可重试挂载直接检索

### 1.5 范围边界（与相邻 PRD 解冲突）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #287 球物理 | 球运动/墙与挡板反弹/得分/发球 | ❌ 不重构球运动；只加 bricks 分支（~10 行） |
| #383 轴交换+竖屏 | 720×1280 坐标系、A/D 输入、得分轴 Y | ❌ 坐标已定，直接使用 |
| #385 双得分制 | 拆砖 1 分（最后触球方）/穿墙 3 分/21 分制 | ❌ 只定义 `brick_destroyed` 契约，不计分 |
| #386 波次循环 | 波次递增/墙更厚/AI 增强 | ❌ 只提供 `generate_wave()` + `wall_cleared`，不实现波次 |
| #393 主场景组装 | 把 1-10 组件接入 Main.tscn | ❌ **Main.tscn 接线推迟到 #393**；本 PRD 交付独立 `breakout_grid.tscn` + 隔离测试 |

---

## 2. 设计意图

### 为什么当前状态存在

Mini Pong 从 #287（球物理）→ #288（挡板）→ #290（AI）→ #295（Main.tscn 组装）一路是**经典 Pong 语义**：无地形、无波次、无拆砖。砖墙是 Rogue Pong 攻城战肉鸽引入的全新系统（PLAN-rogue-pong §4.2「新: 砖墙系统」），此前不存在是因为 P0 前置（竖屏坐标系）尚未落地。

| 现状来源 | Issue | 贡献 |
|---------|-------|------|
| 球碰撞处理（walls/paddles 两分支） | #287 | `ball.gd` 现有分支结构 |
| Main.tscn 场景组装（无砖墙节点） | #295 | 场景接线现状 |
| 竖屏 720×1280（砖墙横跨 720px 的前提） | #383 | 坐标系地基（PR #409 已合并） |
| 手感数值（球速上限 330×1.9≈627px/s） | #367 | 决定砖块最小尺寸防穿透约束 |

### 为什么现在改

1. **PLAN-rogue-pong 已拍板**（2026-08-13）：砖墙是 MVP 核心对象，双得分制（#385）、波次循环（#386）、主场景组装（#393）全部依赖本 Issue 的信号/API 契约 —— 本 Issue 是 MVP 依赖链的**契约源头**
2. **地基已就绪**：#383 竖屏已合并，砖墙横跨 720px、攻防纵深 1280px 的坐标系可用；球 mask 已天然覆盖 layer 2，接入成本最低
3. **窗口期**：功能面尚未收敛到组装（#393），单独交付 BreakoutGrid 节点 + 隔离测试不会与并行 UI Issue（#390/#391/#392）冲突

### 先前约束

| 约束 | 细节 |
|------|------|
| 球速上限（#367 定稿） | `initial_speed 330 × max_multiplier 1.9 ≈ 627 px/s` → 60fps 下单帧位移 ≈ 10.5px → **砖块最小边长 ≥ 14px** 防隧穿 |
| 反弹节奏（#287） | `_bounce_cooldown = 2` 帧防连触机制复用（砖角双砖同时接触的序列化） |
| 信号链（#291/#295） | `score(side)` → ScoringManager 链路不动；砖墙信号是**新旁路**（拆砖/穿墙分），不影响既有对打得分 |
| 层/掩码 | 砖 = layer 2（bit 2），球 mask=3 已含；**不改** ball.tscn/project.godot |
| 测试即验收 | 新测试注册进 `run_tests.gd`；`godot --headless --script tests/run_tests.gd` 全绿 |

---

## 3. 影响分析

### 直接影响的模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/ball.gd` | 球碰撞 | **Modified** — `_on_body_entered` 新增 `bricks` 组分支：dominant-axis 反弹 + 通知砖销毁（约 10 行）；复用 `_bounce_cooldown` |
| `mini-pong/gdscripts/constants.gd` | 常量 | **Modified** — 新增砖墙常量组（`BRICK_SIZE`、`BRICK_GAP`、`GRID_WALL_Y`、`BRICK_MIN_DIM` 等，遵循 #295 单一事实源惯例） |
| `mini-pong/tests/run_tests.gd` | 测试入口 | **Modified** — 注册 `test_breakout_grid.gd` |
| `mini-pong/tests/test_ball.gd` | 球物理测试 | **Modified** — 新增砖块反弹用例（侧击翻 X / 顶击翻 Y / 砖被移除） |

### 新文件

| 文件 | 职责 |
|------|------|
| `mini-pong/gdscripts/breakout_grid.gd` | 网格管理器：`generate_wave()` 程序化生成、砖计数、`brick_destroyed`/`wall_cleared` 信号、`remaining_bricks` 只读 |
| `mini-pong/gdscripts/brick.gd` | 单砖：`add_to_group("bricks")`、`collision_layer=2`、`destroy()`（通知 grid + `queue_free`） |
| `mini-pong/scenes/brick.tscn` | 砖场景：StaticBody2D + ColorRect（复用 `assets/neon_glow_material.tres` 霓虹材质）+ CollisionShape2D（RectangleShape2D） |
| `mini-pong/scenes/breakout_grid.tscn` | 网格场景：根 Node2D + `breakout_grid.gd`（独立可实例化，供测试与 #393 接线） |
| `mini-pong/tests/test_breakout_grid.gd` | 砖墙测试套件（布局/信号/缺口无碰撞/只发一次） |

### 间接影响的模块

| 文件 | 影响 | 说明 |
|------|------|------|
| `mini-pong/scenes/Main.tscn` | 本 Issue **不改** | 接线归 #393；本 PRD 只在 Continuation Context 给出接线清单 |
| `mini-pong/gdscripts/audio_engine.gd` | 可选（Stretch） | 新增 `play_brick_break()` 合成音效；非 AC 阻塞项，plan agent 可决定随 #384 或并入 #392 |
| `docs/GAME_DESIGN/` | 文档 | 建议新增砖墙章节（GDD backfill 惯例 #311），由本 Issue 或 #393 顺带更新 |
| `mini-pong/e2e_shots.json` | 后续 | 砖墙 E2E 截图归 #394 |

### 数据流影响

```
Ball._on_body_entered(brick: StaticBody2D)   [球 mask=3 ∩ 砖 layer=2 → 触发]
    │  brick.is_in_group("bricks")
    ├── 反弹: dominant-axis flip (|vx|≥|vy| → vx=-vx; 否则 vy=-vy)
    │         + _bounce_cooldown = 2 帧 + AudioEngine 提示音(可选)
    ├── brick.destroy()
    │       └──► BreakoutGrid._on_brick_destroyed(brick)
    │               ├── remaining_bricks -= 1
    │               ├── brick_destroyed.emit(brick, brick.global_position) ──► #385 拆砖分(最后触球方)
    │               └── if remaining_bricks == 0 and not _wall_cleared_emitted:
    │                       _wall_cleared_emitted = true
    │                       wall_cleared.emit() ──► #386 波次重置 → generate_wave(更厚参数)
    └── 缺口/留缝位置: 无砖实例 → 无碰撞 → 球直飞 ──► #385 穿墙分(3分)路径
```

---

## 4. 方案对比

### Approach A：每砖 = StaticBody2D（group `bricks`，layer 2）+ `ball.gd` 加 bricks 分支

**描述：** 每个砖块实例化为独立 StaticBody2D（复用现有墙的模式），`collision_layer=2`、`collision_mask=0`（砖不需要探测任何东西，只被球探测）；`brick.gd` 负责 `destroy()`；球侧在 `_on_body_entered` 增加 `bricks` 分支，用 Breakout 标准 dominant-axis 规则反弹并通知砖销毁；BreakoutGrid 聚合计数与信号。缺口 = 不实例化该位置砖（天然无碰撞体）。

**Pros：**
- 完全复用现有 `walls` 管线：球 `body_entered` 已接通，**零层/掩码配置**（layer 2 已在球 mask 内，已核实）
- 与 #287 墙反弹实现同构，代码风格一致；`_bounce_cooldown` 直接复用
- 缺口无碰撞体 = 无节点，AC3 从生成算法直接满足，无额外逻辑
- 性能：~100 砖 × StaticBody2D 在 2D 场景开销可忽略（Godot 4.7 静态体合并）

**Cons：**
- 触碰 `ball.gd`（核心文件），需保证不破坏既有 walls/paddles 分支
- 每砖一个节点，场景树节点数增加（可接受）

**Risk：** Low（改动面小、模式成熟、层已预分配）　**Effort：** 0.5-1 周

### Approach B：每砖 = Area2D，砖自检测球（`area_entered`），`ball.gd` 零改动

**描述：** 砖为 Area2D（layer 2、mask=4 监听球 layer 3），每砖自己 `area_entered` 检测球 → 从砖侧写 `ball.velocity`（dominant-axis 翻转）+ 自毁；BreakoutGrid 只做计数与信号。

**Pros：**
- `ball.gd` 完全不改（隔离性最强，符合「新增节点」字面诉求）
- 砖侧可扩展性强（后续 v1 特殊砖/奖励砖的入场钩子）

**Cons：**
- 砖侧直接写 `ball.velocity`（公开 var），破坏球自管理速度的状态封装（`speed` 归一化逻辑在 `_process` 里每帧重算，外部写 velocity 会被覆盖/冲突）
- Area2D-Area2D 需要双向 mask 配置（砖 mask=4），且球 `area_entered` 分支只认 `paddles` 组 —— 球侧不加分支则砖必须自己处理，**反模式**：碰撞响应分散到 ~100 个砖对象
- 砖自毁时 `queue_free` 与球帧序竞态更难控制（球下一帧可能再触发已删砖）

**Risk：** Med（状态封装冲突 + 响应分散）　**Effort：** 0.5-1 周

### Approach C：单 StaticBody2D + 多 CollisionShape2D 子节点，grid `_process` 手动检测

**描述：** 整墙一个 StaticBody2D，每砖一个 CollisionShape2D 子节点（或 RectangleShape2D 数组）；BreakoutGrid 每帧用球位置做重叠查询/射线，命中 → 移除对应 shape + 反弹。

**Pros：**
- 物理节点数最少（1 个 body）
- 形状即数据，缺口 = 不生成 shape，语义直观

**Cons：**
- 需要每帧手动 overlap 查询（`_process` 轮询，与 #295 信号驱动风格相悖）
- StaticBody2D 动态增删 shape 在 Godot 4 中 clunky（需重建 shape owner），易出空引用
- 反弹法线需自行计算，脱离物理引擎信号模型；测试难度高
- 与球现有 `body_entered` 管线完全脱节，撞墙/撞砖逻辑双轨

**Risk：** High（轮询 + 动态 shape 管理，非惯用模式）　**Effort：** 1-2 周

### 推荐：Approach A

1. **零配置接入**：球 mask=3 已含 layer 2（源码核实），`ball.tscn`/`project.godot` 不动；`body_entered` 管线现成
2. **最小触碰面**：`ball.gd` 仅新增一个 `bricks` 分支（~10 行），walls/paddles 分支与 FSM/ScoringManager 零改动 —— 符合 #287 既有架构（信号驱动 + 组判定）
3. **AC 直接满足**：缺口=无节点（AC3）、原子销毁+反弹（AC2）、计数守卫（AC4）、@export+API（AC5）全部在网格管理器单点实现
4. **下游契约清晰**：`brick_destroyed`/`wall_cleared` 由 grid 聚合发出，与 #385/#386 解耦
5. Approach B 的 velocity 写冲突与 C 的轮询反模式均不符合本项目「信号驱动、球自管运动」的既定架构（#287/#295）

---

## 5. 边界条件与验收标准

### 正常路径（AC 映射）

- [x] **AC1: 每波生成横跨屏幕砖墙，布局含留缝/错位/缺口**
  - `generate_wave(thickness, layout, seed)` 后砖墙 X 方向铺满 720px（首砖 x ≥ 砖宽/2，末砖 x ≤ 720 − 砖宽/2）
  - 布局枚举 `GAPS/OFFSET/HOLES/MIXED` 各自生成预期砖数（测试断言）
- [x] **AC2: 球碰砖 → 砖移除并反弹，方向符合物理规则**
  - 侧击（|vx| ≥ |vy|）→ `vx` 翻转；顶/底击（|vy| > |vx|）→ `vy` 翻转（dominant-axis，Breakout 标准）
  - 同一帧内砖 `queue_free`（原子销毁），无幽灵反弹
- [x] **AC3: 洞口/缺口无碰撞体，球自由穿过**
  - `HOLES` 布局的洞位不实例化砖节点；测试断言洞位无 StaticBody2D、球沿洞轴心穿过不反弹
- [x] **AC4: 整墙打空只发一次 wall_cleared**
  - `remaining_bricks == 0` 且 `_wall_cleared_emitted == false` 时发出；`generate_wave()` 重置守卫
- [x] **AC5: 生成参数集中在 BreakoutGrid 配置，可驱动波次厚度/形状**
  - `@export`：`brick_size`、`brick_gap`、`layout`、`rows`、`hole_count`、`hole_seed`、`wall_y`、`brick_material`
  - `generate_wave(thickness, layout, seed)` API：`rows = thickness`（#386 递增驱动）、`seed < 0` 随机

### 边界情况（≥5）

1. **砖角双砖同时接触** — 球对角砸在两砖接缝：`_bounce_cooldown=2` 帧序列化，只反弹一次；每砖 `destroy()` 幂等（已销毁砖不再重复计数）
2. **最后一砖打空（含同帧双砖）** — 同帧两砖同时碎：计数按砖对象去重（`destroyed_bricks` 集合），`remaining_bricks` 精确归零，`wall_cleared` 只发一次
3. **高速隧穿（球速上限 627px/s ≈ 10.5px/帧）** — 砖块最小边长 ≥ 14px（`BRICK_MIN_DIM` 常量 + 生成时 clamp），单帧位移 < 砖最小边长 → 不隧穿；`brick_size` 导出参数也强制 ≥ 14px
4. **错位行侧边命中** — `OFFSET` 布局下球可擦到上一行砖的侧棱：dominant-axis 规则自动翻 X（侧击），行为符合 Breakout 直觉
5. **缺口穿行** — 球沿洞轴心穿过：洞位无碰撞体，无反弹、无砖碎，直飞对方底线（#385 穿墙分路径）
6. **发球/暂停态** — `_is_serving` 时球静止/不发球（#294 FSM 冻结挡板），无接触可能；`PAUSED` 态 `_process` 停更，砖无反应
7. **波次再生（#386 调用）** — `generate_wave()` 先 `clear_wall()`（`queue_free` 全部旧砖 + 重置计数/守卫/集合），再生成新墙；旧信号不泄漏到新墙
8. **球撞墙同帧撞砖** — cooldown 串行化：先到者先处理，`_bounce_cooldown` 期间的第二次接触被忽略（复用 #287 机制）

### 失败路径（≥3）

1. **wall_cleared 重复发出** — 守卫 `_wall_cleared_emitted` 置位后不再发；`generate_wave()` 必须重置该守卫（测试覆盖：打空→重生成→再打空，恰好两次）
2. **幽灵反弹（砖未碎但球反弹）** — 反弹与 `destroy()` 在同一 handler 原子执行：先标记砖已销毁（集合去重）再改球速度；任何异常路径（`is_instance_valid` 检查失败）不执行反弹
3. **网格销毁期空引用** — 砖 `destroy()` 用 `queue_free`（延迟帧释放），grid 回调内先 `is_instance_valid(brick)` 再操作；`clear_wall()` 遍历前快照列表
4. **计数漂移** — `remaining_bricks` 只由 `_on_brick_destroyed` 单一入口递减（不从场景树扫描推导），防止重复/漏减

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #383 轴交换+竖屏（720×1280） | ✅ 已合并（PR #409） | 无 |
| #287 球物理（collision handler 结构） | ✅ 已存在 | 无（只加分支） |
| #295 Main.tscn 组装（节点/组/层惯例） | ✅ 已存在 | 无 |
| 第三方资产 | — | 无（开源优先调研：无可复用方案，§1.4） |

### 阻塞（下游消费者）

| 下游 | 优先级 | 本 Issue 提供的契约 |
|------|--------|-------------------|
| #385 双得分制 | P0（依赖 #383+#384） | `brick_destroyed(brick, pos)` 事件（拆砖分归属最后触球方） |
| #386 波次循环 | P0 | `wall_cleared` 信号 + `generate_wave(thickness, layout, seed)` API |
| #393 主场景组装 | P0 | `breakout_grid.tscn` 场景 + 接线清单 |
| #394 端到端可玩验证 | P0 | 砖墙 E2E 截图（发光+破洞） |

### 依赖链

```
#383 (轴交换+竖屏) ──✅已合并──► #384 (本 Issue: BreakoutGrid) ──► #385 (双得分制)
                                        │                        └──► #386 (波次循环)
                                        └──► #393 (主场景组装) ──► #394 (E2E)
```

### 准备清单

- [x] 开源优先调研（Asset Library + GitHub，§1.4）
- [x] 碰撞层/掩码核实（layer 2 空闲，球 mask=3 已覆盖）
- [x] 竖屏坐标核实（720×1280，墙 Y 默认 640）
- [ ] plan agent：确认砖块视觉（复用 neon 材质）与可选音效（`play_brick_break`）取舍

---

## 7. Spike / 实验

> 本 Issue 无 `depth/deep` 标签，按 standard 惯例 Section 7 可选；鉴于 Issue body 明确要求「开源优先」调研，以下 3 个实验已在**研究阶段实际执行**并给出结论，供 plan agent 直接引用。

| # | 问题 | 方法 | 结果 | 对方案的影响 |
|---|------|------|------|-------------|
| 1 | 是否存在可复用的程序化砖墙插件/资产？ | Godot Asset Library（4.7 过滤 `breakout`/`brick`）+ GitHub 搜索（`godot breakout` 235 仓库、`godot brick breaker`） | Asset Library 0 结果；GitHub 全部为 <5⭐ 完整游戏克隆，无可插拔网格生成模块 | 确认第一方实现（Approach A），零第三方依赖 |
| 2 | 球能否零配置检测砖？ | 读 `ball.tscn`（mask=3=bit1+2）与 `Main.tscn`/`player_paddle.tscn` 层分配 | 球 mask 已含 layer 2；第 2 层空闲；砖 StaticBody2D → `body_entered` 直接触发 | Approach A 可行，无需改层/掩码配置 |
| 3 | 反弹规则哪个满足「符合物理规则」？ | 对比 dominant-axis flip 与碰撞法线反射（结合 #287 信号式碰撞无法线的事实） | dominant-axis（|vx|≥|vy| 翻 X）为 Breakout 标准且与现有信号模型兼容；法线反射需 move_and_collide 重构，代价高 | 采用 dominant-axis flip + cooldown 复用 |

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- 竖屏 720×1280 已就绪（#383，PR #409）；球为 Area2D（layer 3、mask 3），墙/挡板在 layer 1；**layer 2 空闲且已在球 mask 内**
- `ball.gd` 碰撞处理为组判定分支结构（walls → X 翻；paddles → 角度反弹 + cooldown），新增 bricks 分支与之同构
- 无任何砖墙相关代码/资源存在（已核实 `mini-pong/` 全目录）

### 本 PRD 的核心决策（勿偏离）

1. **Approach A**：每砖 StaticBody2D（group `bricks`、layer 2、mask 0）+ `ball.gd` 加 bricks 分支（dominant-axis 反弹 + 通知销毁）
2. **缺口 = 无节点**：`HOLES` 布局洞位不实例化砖，AC3 天然满足
3. **信号契约**：`brick_destroyed(brick, pos)`（#385 拆砖分）+ `wall_cleared()`（#386 波次重置，守卫只发一次）
4. **生成 API**：`generate_wave(thickness, layout, seed)`；`rows = thickness`；`@export` 参数集中（AC5）
5. **防隧穿**：砖最小边长 ≥ 14px（球速上限 627px/s ≈ 10.5px/帧）
6. **Main.tscn 不改**：接线归 #393；本 Issue 交付 `breakout_grid.tscn` + 隔离测试

### 新建文件清单

| 文件 | 要点 |
|------|------|
| `mini-pong/gdscripts/breakout_grid.gd` | `@export` 参数、`generate_wave/clear_wall`、计数 + 守卫、两信号、`remaining_bricks` 只读 |
| `mini-pong/gdscripts/brick.gd` | group `bricks`、layer 2、`destroy()` 幂等（集合去重） |
| `mini-pong/scenes/brick.tscn` | StaticBody2D + ColorRect（`assets/neon_glow_material.tres`）+ CollisionShape2D |
| `mini-pong/scenes/breakout_grid.tscn` | 根 Node2D + script |
| `mini-pong/tests/test_breakout_grid.gd` | 见下「测试要点」 |

### 修改文件清单

| 文件 | 改动 |
|------|------|
| `mini-pong/gdscripts/ball.gd` | `_on_body_entered` 加 `bricks` 分支（~10 行）：dominant-axis 反弹 + cooldown + `brick.destroy()` |
| `mini-pong/gdscripts/constants.gd` | 砖墙常量组（`BRICK_SIZE`、`BRICK_GAP`、`GRID_WALL_Y=640`、`BRICK_MIN_DIM=14`） |
| `mini-pong/tests/run_tests.gd` | 注册 `test_breakout_grid.gd` |
| `mini-pong/tests/test_ball.gd` | 砖块反弹用例（侧击翻 X、顶击翻 Y、砖移除） |

### 测试要点（test_breakout_grid.gd）

- 布局：GAPS/OFFSET/HOLES/MIXED 各自砖数与铺满 720px 断言；OFFSET 行偏移 = (砖宽+缝)/2；HOLES 洞位无砖
- 信号：逐砖碎发 `brick_destroyed`；全部打空 `wall_cleared` 恰好一次；再生后重打空再恰好一次
- 缺口：洞轴心直穿无反弹
- 再生：`generate_wave()` 后旧砖清空、计数/守卫重置

### 主要风险

- `ball.gd` 触碰核心：改动必须保持 walls/paddles 分支行为不变（#287 测试兜底）
- 同帧多砖销毁：计数去重必须按砖对象身份，勿用位置/索引
- 音效/视觉为可选 Stretch：不阻塞 AC；如做，复用 AudioEngine 合成模式与 neon 材质

### 下一步

1. plan agent 依据本 PRD 产出 DESIGN（含测试描述）
2. implement agent 实现（本 Issue 机械所有权，无需人审）
3. #393 组装时把 `breakout_grid.tscn` 实例化进 Main.tscn（墙 Y 默认 640），接线 `brick_destroyed`→#385、`wall_cleared`→#386

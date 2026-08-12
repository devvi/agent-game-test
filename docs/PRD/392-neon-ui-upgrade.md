# PRD: [Feature] 霓虹UI升级 — Neon HUD Upgrade

> **Issue:** #392
> **标签:** enhancement, workflow/available, graphics, ui, version/mvp
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386/#389 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（headless 下 outline/shadow 渲染、E2E 断言影响、720×1280 布局遮挡）而包含 2 个轻量实验）
> **所有权:** `content_ownership: mechanical`（分区布局/信号接线/样式参数 = 机械可测；描边粗细、投影偏移、信息条配色等视觉细节 = taste-draft，走 human-review 定稿）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3.3 UI（已确认：「默认字体 + 霓虹描边 + 微投影，headless 安全、零 license 成本；HUD 顶部中央 拆砖分/穿墙分 双区 + 波次号 + 剩余砖数；玩家蓝/AI 红」）+ §3.1 分层（L0 氛围 / L1 世界 / L2 反馈 / **L3 UI**）
> **前置依赖:** #383（✅ CLOSED — 轴交换+竖屏 720×1280）、#384（✅ CLOSED — 砖墙系统 PRD #411 + DESIGN #414 合并，**实现未落地**）、#385（✅ CLOSED — 双得分制，已实现）、#386（✅ CLOSED — 波次循环，已实现 PR #428）

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）的 HUD 停留在 #292 时代：**顶部居中一行两个总分 Label，无霓虹描边、无投影、无拆砖/穿墙分区、无波次号、无剩余砖数**。双得分制（#385）、波次循环（#386）、雨幕（#389）全部落地后，HUD 仍是「Player: n / AI: n」的朴素文本，与 PLAN §3.3 已确认的 UI 规格（霓虹描边 + 微投影 + 双区 + 波次号 + 剩余砖数）存在系统性差距。

| 文件 | 当前状态 | 与 #392 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/game_hud.gd` | 34 行：`_ready` 连接 `GameManager.score_changed` → 只更新 `PlayerScoreLabel`/`AIScoreLabel` 两个 Label；`visible=false` 由 FSM/StartMenu 控制 | ❌ 无霓虹描边/微投影（仅 modulate 颜色）；❌ 无拆砖/穿墙双区；❌ 无波次号/剩余砖数；❌ 无样式复用工具 |
| `mini-pong/scenes/ui_game_hud.tscn`（独立场景） | CanvasLayer layer=0，MarginContainer(顶部 margin 20, 左右 40) > HBoxContainer(居中, separation 60) > 两 Label（font_size 28，modulate 蓝 `PLAYER_NEON_BLUE` / 红 `AI_NEON_RED`） | ❌ 无 outline/shadow 主题覆盖；❌ 布局只有顶部一行；❌ 与 Main.tscn 内联副本**重复定义且 layer 不一致**（ui_game_hud.tscn layer=0 vs Main.tscn 内联 GameHUD layer=1） |
| `mini-pong/scenes/Main.tscn` | `GameHUD` 节点内联（非实例化 ui_game_hud.tscn）：CanvasLayer layer=1，子树与 ui_game_hud.tscn 同构 | ❌ 需同步改造（或改为实例化，消除双份维护） |
| `mini-pong/gdscripts/game_manager.gd` | `score_changed(p, a)` 每次 `add_score()` 后触发（总分）；`wave_started(wave_index)` / `wave_settled`（#386）已有；`get_brick_count(side)` / `get_pierce_count(side)` 查询 API 已有（#385 AC5） | ⚠️ **无按类信号**（拆砖/穿墙各自触发），HUD 双区更新要么新增 `brick_scored`/`pierce_scored` 信号，要么在 `score_changed` 里读查询 API（§4.1 对比） |
| `mini-pong/gdscripts/breakout_grid.gd` | **❌ 不存在**（#384 实现未落地：`git ls-tree origin/main mini-pong/gdscripts/` 无 breakout_grid.gd / brick.gd） | ⚠️ 剩余砖数数据源缺失 → HUD 必须按 #384 契约（`remaining_bricks` / `brick_destroyed` / `wall_cleared`）容错消费（`get_node_or_null` 模式，同 scoring_manager/wave_controller），#393 接线后自动生效 |
| `mini-pong/gdscripts/constants.gd` | `PLAYER_NEON_BLUE`(#4a90d9) / `AI_NEON_RED`(#ff3355)（#289）、`BRICK_SCORE`/`PIERCE_SCORE`/`WIN_SCORE`（#385）、`WAVE_*`（#386） | ❌ 无 `HUD_*` 样式/布局常量（描边尺寸/投影偏移/安全区） |
| 分层（PLAN §3.1） | L0 `AtmosphereLayer`(layer=0, 雨幕) / L1 世界 / L2 反馈(ScoreFlash) / L3 UI（GameHUD layer=1、StartMenu layer=1、PauseOverlay layer=10） | ✅ 分层已就位：HUD 在雨幕之上绘制，可读性有结构性保证（§5 边界 3） |
| 场景几何 | AI 挡板中心 (360,40) 高 20 → y∈[30,50]；玩家挡板中心 (360,1240) → y∈[1230,1250]；砖墙默认 `wall_y=640`；ScoreZone 无可见渲染 | 布局约束源：顶部/底部安全区须避开挡板与砖墙（§4.2） |
| `mini-pong/e2e_shots.json` | loop 原型 3 shots（01_title/02_midgame/03_gameover），match `gdscripts/.*\\.gd` 命中即跑 → game_hud.gd 改动必命中；02_midgame（PLAYING 态）截图将包含新 HUD | ⚠️ 4 重断言（非黑/色数/主题色 4a90d9/帧间差异）需实测通过（Spike 1） |

**关键事实核查（来自源码）：**

- `game_manager.gd:add_score(winner, amount, kind)` 内 `_bump_count()` **先**更新拆砖/穿墙计数、**后** emit `score_changed` —— 因此 HUD 在 `score_changed` 处理器内读 `get_brick_count()/get_pierce_count()` 必然拿到最新值（§4.1 Approach B 可行性的依据）
- `GameManager.wave_started(wave_index)` 在 `WaveController._advance_wave()` 中 **先于** `generate_wave()` 发出（begin_wave → 难度 → 雨幕 → generate_wave 同帧顺序）—— HUD 不能在同一 handler 同步读新墙剩余数（§4.1 契约缺口）
- **#384 DESIGN §4.1 契约缺口**：BreakoutGrid 只有 `brick_destroyed` / `wall_cleared` 两个信号，`generate_wave()` **不发出「新墙已生成」信号** → 剩余砖数在新墙生成瞬间无法由信号感知（首次拆砖前会显示旧值/0）。由于 #384 实现未落地，**现在补一个 `wall_generated(remaining: int)` 信号到契约零成本**（无既有代码要改）
- `test_main_scene.gd` TC1-11 断言 `GameHUD` 节点存在、TC20-11 断言 `GameHUD/MarginContainer.offset_right == 720` —— 布局改造需保持这两条断言语义或同步更新测试
- `test_ui_system.gd` TC6（Labels 存在/visible=false）、TC9（score_changed 更新文本）、TC15-7/8/9（CanvasLayer、visible=false、layer=1，针对 Main.tscn 内联节点）—— 改造后需同步

### 1.2 预期行为（验收条件，源自 Issue #392）

1. **AC1 — HUD 所有数字使用霓虹描边+微投影样式，在雨幕动效下可读** — 所有数字 Label 设置 `theme_override_colors/font_outline_color` + `theme_override_constants/outline_size`（描边）+ `theme_override_colors/font_shadow_color` + `theme_override_constants/shadow_offset_x/y`（微投影）；HUD 位于 L3（layer=1）在 L0 雨幕之上，配合描边/投影对比度保证可读
2. **AC2 — 玩家为蓝色，AI 为红色，拆砖和穿墙分数在两个独立区域** — 顶部 AI 红色区（AI 总分 + AI 拆砖/穿墙双子区）、底部玩家蓝色区（玩家总分 + 玩家拆砖/穿墙双子区）；拆砖与穿墙为两个独立 Label 子区（视觉分离，可独立断言）
3. **AC3 — HUD 显示当前波次和剩余砖数（由 BreakoutGrid 提供）** — 波次号消费 `GameManager.wave_started` + 初始 `wave_index`；剩余砖数消费 BreakoutGrid `brick_destroyed`（读 `remaining_bricks`）/ `wall_cleared`（归零）/ `wall_generated`（契约补充，新墙总数）；#384 未落地时显示占位符且不报错
4. **AC4 — 720x1280 下 HUD 不遮挡球道与砖墙主体** — 顶部区 y∈[12,84]、底部区 y∈[1252,1280]（玩家挡板下方），均远离砖墙（y=640）与挡板主体；Spike 2 截图实测
5. **AC5 — 分数更新来自 GameManager 信号，不使用轮询** — 总分/拆砖/穿墙/波次/剩余砖数全部由信号触发更新（`score_changed` + 新增按类信号 + `wave_started` + grid 信号）；无 `_process` 轮询

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 对打进行中 | 持续 | 顶部红区 AI 总分/拆砖/穿墙、底部蓝区玩家总分/拆砖/穿墙实时更新；霓虹描边数字在雨幕与 bloom 中清晰可读 |
| B | 波次推进 | 每波一次 | 顶部信息条「第 N 波 · 剩余 x」随 `wave_started` 更新波次号、随新墙生成刷新剩余砖数 |
| C | 拆砖/穿墙得分 | 每局多次 | 拆砖 +1（最后触球方）→ 对应方拆砖子区 +1；穿墙 +3 → 穿墙子区 +3；两区独立跳动更新，无轮询 |

### 1.4 技术约束（继承自 Issue #392 + PLAN-rogue-pong + 依赖链）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，720×1280 竖屏，resizable=false，Forward+） |
| 字体 | **默认字体**（PLAN §3.3 已确认）：Label 主题覆盖实现描边+微投影，**不引入第三方字体**（headless 安全、零 license 成本） |
| 分层 | HUD = L3 UI 层（CanvasLayer layer=1），在 L0 雨幕（layer=0）之上；不得改 AtmosphereLayer/世界层 |
| 配色 | 玩家蓝 `PLAYER_NEON_BLUE`(#4a90d9)、AI 红 `AI_NEON_RED`(#ff3355)（constants.gd #289 单一事实源）；信息条（波次/剩余）中立色 |
| 不变项 | FSM（#294）、scoring 信号链（#291/#295/#385）、波次状态机（#386）、雨幕（#389）、手感数值（#367）不变；`game_manager.gd` 只**新增**信号不删改既有信号 |
| 接线边界 | BreakoutGrid 实例化与正式接线归 **#393**；本 Issue 交付容错消费（`get_node_or_null` + `has_signal/has_method` 双守卫，同 scoring_manager/wave_controller 模式） |
| 信号纪律 | 所有更新走信号（AC5）；剩余砖数读取 = 信号处理器内的**即时单读**（非周期轮询） |
| 所有权 | `content_ownership: mechanical`（布局/信号/样式机制）；描边粗细、投影偏移、信息条配色 = taste-draft |
| 开源优先 | 调研结果见 §1.5 — 结论：不引入第三方资产，第一方实现并说明理由 |

### 1.5 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索范围 Godot Asset Library + GitHub（带 auth 搜索，按 star 排序）：

- **Godot Asset Library**（assetlibrary.godotengine.org，godot_version=4.7）：`neon` → 4 条（QTI Neon 4.2 / NeonSceneRunner 4.4 / NeonGameModes 4.4 / NeonPageController 4.4，均为**编辑器工具/脚本 demo**，非运行时 UI 主题）；`hud` → 1 条（Metal HUD gd，Tools 类）；`ui theme` → 1 条（Windows 95 UI Theme — 复古主题，与霓虹赛博风格相反）；`cyberpunk` → 0 条；`retro` → 2 条（无关工具/着色器合集）——**无霓虹 HUD/UI 主题资产**
- **GitHub 搜索**（`godot neon ui` / `godot cyberpunk ui` / `godot hud theme godot4`）：最高分 `metapika/neon-page-controller` 仅 **4⭐**（页面切换控制器，非 HUD 视觉）；`Shilo/NeoCade-Theme`（Godot 4.6 UI Theme addon，arcade 风格，**0⭐**、2026-05 最后更新、无成熟度证据）——**无成熟可复用方案**
- **社区/论坛**：Godot 官方论坛与 Reddit r/godot 无「霓虹 HUD 主题」成熟分发物；Godot 内置 Label `font_outline_color/outline_size/font_shadow_color/shadow_offset` 主题覆盖即官方支持的描边+投影机制（文档齐全、headless 安全）
- **结论**：**无可直接复用的成熟霓虹 HUD 方案**。PLAN §3.3 已确认「默认字体 + 霓虹描边 + 微投影」路线，Godot 内置 Label 主题覆盖完全覆盖需求，第一方实现（共享样式工具 + 分区布局）成本可控，不引入第三方依赖，符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（本会话挂载于 `~/Documents/Obsidian Vault/`，含 `raw/` 58 篇 + `wiki/` 笔记）：检索关键词「HUD / UI / 可读性 / 字体 / 描边 / 霓虹 / 雨 / 氛围」命中以下笔记——
- `wiki/体验引擎-patterns.md`：§14「可预测的奖励变得无聊」（:79-80，#385 已引用）支撑拆砖 1 分/穿墙 3 分的节奏差异；UI 沉浸感条目「UI 元素打破沉浸感……最小化 HUD」（:14-15）与「沉浸感被 UI 破坏 → 隐形界面」（:112）支撑本 Issue 信息密度克制（只放必要的 5 组数字，不堆装饰）
- `wiki/90年代地摊文艺.md`：反例约束（克制、不堆砌特效）——描边克制、微投影而非重阴影、信息条中性色
- `wiki/原始材料-开发笔记.md`：雨相关笔记链接（`[[看雨]]`/`[[雨和馄饨]]`）——雨幕 × 霓虹的「雨夜竞技场」观感上下文
- **上游确认**：UI 规格已由 `docs/PLAN-rogue-pong.md` §3.3 **用户拍板**（默认字体+霓虹描边+微投影、双区、玩家蓝/AI 红、克制优先）；本 Issue 的 HUD 视觉约束（描边克制、微投影而非重阴影、信息密度低）继承「90 年代地摊文艺」反例约束

### 1.7 范围边界（与相邻 PRD 解冲突）

| PRD/Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #292 UI 系统 | 基础 HUD（顶部居中总分）、信号链（score_changed）、可见性控制（FSM/StartMenu） | ❌ 不重建信号链与可见性控制；保留 score_changed 消费，重构视觉与结构 |
| #384 砖墙系统 | BreakoutGrid 生成/碰撞/`brick_destroyed`/`wall_cleared`/`remaining_bricks` | ❌ 只**消费**剩余砖数契约（含建议新增 `wall_generated` 信号）；不实现砖墙 |
| #385 双得分制 | 计分/计数 API（`add_score` kind、`get_brick_count`/`get_pierce_count`） | ❌ 只**展示**计数；不改计分规则 |
| #386 波次循环 | wave_index/波次状态机/`wave_started`/难度递增 | ❌ 只**消费** `wave_started` 显示波次号；不推进波次 |
| #389 动态雨幕 | L0 氛围层（雨幕粒子/公式） | ❌ 不改雨幕；HUD 在 L3 之上保证可读 |
| #388 3选1升级UI | 波间三张霓虹卡片（OPEN，backlog） | ❌ 不做升级卡；但共享霓虹样式工具（§3.1 `ui_neon_style.gd`）供其复用 |
| #390 波次转场 | 全屏「第 N 道墙」大字转场（OPEN，backlog） | ❌ 不做转场屏；HUD 的波次号为**常驻小字**，与转场大字互补不重复 |
| #391 失败屏 | 失败屏 run 数据（OPEN，backlog） | ❌ 不做结算屏；HUD 不展示 run 汇总 |
| #393 主场景组装 | BreakoutGrid 接线/组件组装（workflow/backlog） | ❌ 不接线网格；HUD 容错消费，#393 完成后自动生效 |

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 现状 | 成因 | 证据 |
|------|------|------|
| HUD 只有顶部两行总分 | #292 时代只有单得分制（出界 +1），HUD 只需总分 | `game_hud.gd` 34 行、无其他 Label |
| 无霓虹描边/投影 | #289 霓虹视觉只覆盖世界层（glow/bloom/球拖尾/shader），UI 未纳入 | `ui_game_hud.tscn` 仅 modulate 颜色 |
| 无拆砖/穿墙/波次/剩余砖数 | 双得分（#385）、波次（#386）、砖墙（#384 实现未落地）在 HUD 设计之后才出现 | GameManager 只有 score_changed；grid 文件不存在 |
| 双份 HUD 定义 | #292 交付独立 ui_game_hud.tscn，Main.tscn 组装时内联复刻（#295）未实例化 | ui_game_hud.tscn layer=0 vs Main.tscn 内联 layer=1 |
| 剩余砖数无信号感知 | #384 DESIGN §4.1 只定义 brick_destroyed/wall_cleared，`generate_wave()` 无「新墙生成」信号 | DESIGN #414 信号清单 |

### 2.2 为什么现在改

1. **上游已拍板**：PLAN-rogue-pong §3.3 UI 规格（2026-08-13 确认）——霓虹描边+微投影、双区、波次号、剩余砖数、玩家蓝/AI 红；本 Issue 是 §3.3 的执行层
2. **数据源全部就绪**：#385 提供拆砖/穿墙计数与查询 API、#386 提供 wave_index/`wave_started`、#384 契约提供 `remaining_bricks`（实现未落地但契约已合并，容错消费即可）；HUD 是这些契约的**第一个 UI 消费者**
3. **雨幕已落地（#389）**：L0 雨幕 + L3 HUD 的分层结构已在 Main.tscn 存在，HUD 升级是「雨夜霓虹竞技场」观感的最后一块拼图（Issue body 上下文：「雨幕与霓虹 UI 共同构成竖屏赛博体育场观感」）
4. **成本窗口**：#384 实现未落地 → 现在补 `wall_generated` 信号进契约零成本；#393 组装在 backlog → 本 Issue 先行交付 HUD 容错消费，组装时自动生效；与 #388/#390/#391（均 OPEN/backlog）错开，且共享样式工具先落地可供其复用

### 2.3 先前约束

| 约束 | 细节 |
|------|------|
| #289 视觉基调 | 深底 #0a0a12、glow_intensity 0.6、bloom 0.8；霓虹配色 PLAYER_NEON_BLUE/AI_NEON_RED 为唯一玩家/AI 色源 |
| PLAN §3.3 UI | 默认字体 + 霓虹描边 + 微投影（headless 安全、零 license）；动效统一 Tween 150-300ms 淡入/滑入，不弹跳不花哨 |
| #292 HUD 惯例 | 顶部 margin 20、左右 padding 40、HBox 居中 separation 60；`visible=false` 初始，FSM `_set_ui("hud")` / StartMenu 控制显隐 |
| #385/#386 信号 | `score_changed` / `wave_started` 为既有契约，只扩展不删改 |
| #384 契约（DESIGN #414） | `remaining_bricks`（只读）、`brick_destroyed(brick, pos)`、`wall_cleared()`、`generate_wave()` 内 `clear_wall()`；本 PRD 建议增补 `wall_generated(remaining)` |
| 场景几何 | AI 挡板 y∈[30,50]、玩家挡板 y∈[1230,1250]（120 宽居中）、砖墙 y=640；ScoreZone 无可见渲染 |
| 测试即验收 | 新测试注册进 `run_tests.gd`；theme override 断言用 `label.get("theme_override_...")`（GDD16 已记录 headless 下 `get_theme_font_size` 返回 0 的坑） |
| E2E | e2e_shots.json loop 命中 `gdscripts/.*\\.gd` → 02_midgame 截图含新 HUD；4 重断言需实测通过 |

---

## 3. 影响分析

### 3.1 新文件

| 文件 | 类型 | 职责 |
|------|------|------|
| `mini-pong/gdscripts/ui_neon_style.gd` | 脚本（工具类） | 霓虹 Label 样式的**单一事实源**：`static func apply(label: Label, color: Color, opts := {})` 设置 outline_size/outline_color/shadow_offset/shadow_color 等主题覆盖；本 Issue 的 HUD 使用，#388/#390/#391 后续复用（视觉一致性） |
| `mini-pong/tests/test_hud.gd` | 测试 | 霓虹样式断言（outline>0/投影偏移>0）、信号接线（score_changed/brick_scored/pierce_scored/wave_started）、剩余砖数（mock grid 信号）、容错（无 grid 不崩）、布局安全区断言、headless 安全 |

### 3.2 直接改动文件

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/game_manager.gd` | 状态 | **新增** `signal brick_scored(side: String)` / `signal pierce_scored(side: String)`；`add_score()` 内按 kind emit（`_bump_count` 之后、`score_changed` 之前或之后均可，顺序无耦合）。不改既有信号/API |
| `mini-pong/gdscripts/game_hud.gd` | HUD | 重构：四区 Label 引用（AI 总分/玩家总分/拆砖×2/穿墙×2/波次/剩余砖数）；`_apply_neon()` 经 ui_neon_style 套样式；连接 score_changed + brick_scored + pierce_scored + wave_started + grid 信号（容错）；`_ready` 初值播种（同 #292 惯例） |
| `mini-pong/scenes/ui_game_hud.tscn` | 场景 | 重排为分区布局（顶部 AI 区 / 底部玩家区 / 中立信息条）；Label 主题覆盖（或由脚本统一设置） |
| `mini-pong/scenes/Main.tscn` | 场景 | GameHUD 子树同步改造；**建议改为实例化 `ui_game_hud.tscn`**（消除双份维护、统一 layer=1）；节点名保持 `GameHUD` 使 FSM/StartMenu/test_main_scene 引用不变 |
| `mini-pong/gdscripts/constants.gd` | 常量 | 新增 `HUD_*` 组：`HUD_OUTLINE_SIZE=6`、`HUD_SHADOW_OFFSET=2`、`HUD_SHADOW_COLOR`、`HUD_INFO_COLOR`（中立信息条色）、安全区 `HUD_TOP_BAND_Y/HUD_BOTTOM_BAND_Y` 等（机械可测；具体数值 taste-draft 可调） |
| `mini-pong/tests/run_tests.gd` | 测试 | 注册 `test_hud.gd` |
| `mini-pong/tests/test_game_manager.gd` | 测试 | 新增 brick_scored/pierce_scored 信号用例（kind 触发、boundary 不触发） |
| `mini-pong/tests/test_ui_system.gd` | 测试 | TC6/TC9/TC15 按新结构同步（Label 路径/文本/断言） |
| `mini-pong/tests/test_main_scene.gd` | 测试 | TC1-11（GameHUD 存在）不变；TC20-11（offset_right==720）按新布局同步 |

### 3.3 间接影响（需回归验证）

| 文件 | 影响 | 处理 |
|------|------|------|
| `mini-pong/gdscripts/score_flash.gd` | 不受影响（L2 反馈层独立） | 零改动；L2 反馈（得分闪光）与 L3 HUD 分区视觉叠加需截图确认不违和（Spike 1） |
| `mini-pong/gdscripts/game_state_machine.gd` / `start_menu.gd` | 引用 `../GameHUD` / sibling `GameHUD` | 零改动（节点名与类型 CanvasLayer 不变） |
| `mini-pong/e2e_shots.json` | 02_midgame 截图将包含新 HUD（红区/蓝区/信息条） | 断言需实测：新增红色（ff3355）在色数断言内正常；主题色 4a90d9 保持；若帧间差异/色数断言受影响，调整 shot 参数而非回退 HUD（Spike 1） |
| `docs/GAME_DESIGN/16-UI-SYSTEM.md` | GameHUD 章节描述过时 | 实现 PR merge 后由 review agent 增量更新 |
| `docs/DESIGN/384-breakout-grid-brick-wall.md` | 若采纳 `wall_generated` 契约增补 | 附注更新（DESIGN #414 增补一行信号清单） |

### 3.4 数据流影响

```
更新源（全部信号，零轮询）:
    GameManager.add_score(winner, amount, kind)      # #385 既有
        ├── brick   → brick_scored(side)  [新增]  ──► HUD 拆砖子区（对应方）
        ├── pierce  → pierce_scored(side) [新增]  ──► HUD 穿墙子区（对应方）
        └── 全部    → score_changed(p,a)  [既有]  ──► HUD 总分 Label ×2
    GameManager.begin_wave()                          # #386 既有
        └── wave_started(wave_index)            ──► HUD 波次号 + call_deferred 读新墙剩余数
    BreakoutGrid（#384 契约，容错）:
        ├── brick_destroyed(brick, pos)         ──► HUD 剩余砖数 = grid.remaining_bricks（即时单读）
        ├── wall_cleared()                      ──► HUD 剩余砖数 = 0
        └── wall_generated(remaining) [契约增补]──► HUD 剩余砖数 = remaining（新墙总数）
    容错: get_node_or_null("../BreakoutGrid") == null → 剩余砖数显示 "—" 占位，push_warning 一次
                               ▼
    HUD 渲染（L3 CanvasLayer layer=1，雨幕 L0 之上）:
        ui_neon_style.apply(label, PLAYER_NEON_BLUE / AI_NEON_RED / HUD_INFO_COLOR)
        ├── font_outline_color + outline_size(6)   ← 霓虹描边
        └── font_shadow_color + shadow_offset(2,2) ← 微投影
```

### 3.5 文档更新

- [ ] `docs/PRD/392-neon-ui-upgrade.md`（本文件）
- [ ] `docs/DESIGN/384-breakout-grid-brick-wall.md` — 若采纳 `wall_generated` 信号增补（附注）
- [ ] `docs/GAME_DESIGN/16-UI-SYSTEM.md` — 实现 PR merge 后由 review agent 增量更新（GameHUD 章节）
- [ ] 本 PRD merge 后自动推进 Issue #392 → `workflow/plan`（workflow-chain）

---

## 4. 方案对比

本 Issue 含两个设计轴：**数据更新机制**（4.1）与**布局/视觉结构**（4.2），按项目多子系统 PRD 惯例（#217/#389 先例）分节对比，末尾汇总推荐组合。

### 4.1 数据更新机制 —— 拆砖/穿墙双区如何更新

#### Approach A：扩展 GameManager 按类信号（推荐）

`game_manager.gd` 新增 `brick_scored(side)` / `pierce_scored(side)` 两个信号，`add_score()` 内按 kind emit；HUD 各子区各连其信号。

- **Pros**：语义一一对应（拆砖区只听 brick_scored），符合 AC5「所有更新走信号」字面要求；信号级可测（test_game_manager 直接断言触发）；#391 失败屏如需按类监听可复用；GameManager 只**新增**不删改，无回归面
- **Cons**：GameManager 多 2 个信号（约 4 行 + 测试）
- **Risk**：Low — 纯增量；`score_changed`/`wave_started` 等既有信号不动
- **Effort**：0.5 天

#### Approach B：复用 score_changed + 查询 API（零 GameManager 改动）

HUD 在 `_on_score_changed()` 内调用 `GameManager.get_brick_count(side)` / `get_pierce_count(side)` 刷新双区（`add_score` 先计数后 emit 的顺序保证读到最新值）。

- **Pros**：GameManager 零改动；同样信号驱动（非轮询）
- **Cons**：HUD 每次 score_changed（含 boundary 兜底分）都要重读 4 个计数；「拆砖/穿墙各走各的信号」语义弱化；对 add_score 内部「先计数后 emit」顺序产生隐式依赖（未来重构易破坏）
- **Risk**：Med — 隐式顺序契约，无显式信号可断言
- **Effort**：0.5 天

#### Approach C：_process 轮询（排除）

HUD 每帧读 GameManager 计数与 grid.remaining_bricks。

- **Pros**：无
- **Cons**：**直接违反 AC5**（「分数更新来自 GameManager 信号，不使用轮询」）
- **Risk**：High（AC 不合规）
- **Effort**：0.5 天

**推荐：Approach A。** 理由：(1) 唯一满足 AC5 字面语义的方案；(2) 信号级可测、无双区更新歧义；(3) 纯增量改动（既有信号零改动）；(4) 与 #386 向 GameManager 增加 wave 信号的先例一致。

### 4.2 布局与视觉结构 —— 分区 + 霓虹样式如何落地

#### Approach A：分区布局 + 共享霓虹样式工具（推荐）

HUD 重构为三区：**顶部 AI 红色区**（y∈[12,84]：AI 总分大字 + 「拆 x · 穿 y」双子区）、**底部玩家蓝色区**（y∈[1252,1280]，玩家挡板下方：玩家总分 + 「拆 x · 穿 y」双子区）、**中立信息条**（「第 N 波 · 剩余 x」，挂顶部区下方或并入顶部区第二行）；霓虹样式收敛到 `ui_neon_style.gd` 静态工具（默认字体 + 主题覆盖，PLAN §3.3）。

- **Pros**：完全满足 AC2（顶红底蓝、拆穿双区）与 AC3（波次/剩余砖数）；AC4 由安全区计算保证（顶部区避开 AI 挡板 y∈[30,50] 的上缘重叠、底部区整体在玩家挡板下方）；样式工具单一事实源，#388/#390/#391 直接复用保证全 UI 视觉一致；默认字体 headless 安全
- **Cons**：底部区可用高度仅 ~28px（1252–1280），单行紧凑（总分+拆/穿一行排布，字号 ~20px）——若 human-review 嫌小，可改为左右下角双子区（x<290 / x>430）避开挡板，属 taste 微调
- **Risk**：Low — 布局可测（安全区断言）+ Spike 2 截图兜底；样式工具为纯静态函数无状态
- **Effort**：0.5–1 周

#### Approach B：在现有顶部单行基础上堆叠扩展

保持顶部 HBox，加更多 Label（总分、拆、穿、波次、剩余）挤在一行。

- **Pros**：改动最小
- **Cons**：**违反 AC2 布局要求**（「顶部 AI 红色区、底部玩家蓝色区」——玩家区必须在底部）；720px 宽一行塞 5+ 组数字信息密度过高、雨幕下可读性差；无玩家/AI 空间分区语义
- **Risk**：High（AC 不合规）
- **Effort**：0.5 天（但返工）

#### Approach C：自定义霓虹字体 + shader 描边

引入第三方字体（如 Orbitron/霓虹风）或 canvas shader 做描边发光。

- **Pros**：视觉更「霓虹」
- **Cons**：**违背 PLAN §3.3 已确认路线**（默认字体，headless 安全、零 license 成本）；第三方字体有 license/导入/headless 渲染风险（#216 addon 分类调研先例：视觉资产常是 editor-only 或运行时坑）；shader 描边在 Label 上需额外 Control 层，复杂度与测试面大增
- **Risk**：Med-High（上游路线冲突 + 资产风险）
- **Effort**：1–2 周

**推荐：Approach A。** 理由：(1) 唯一同时满足 AC2/AC3/AC4 的结构方案；(2) PLAN §3.3 路线（默认字体 + 主题覆盖描边/投影）已用户拍板，A 是它的直接执行；(3) 共享样式工具为 #388/#390/#391 提供视觉一致性基础；(4) 调研证据（§1.5）证明无成熟第三方方案可复用。

### 4.3 推荐组合汇总

| 设计轴 | 推荐 | 核心文件 |
|--------|------|---------|
| 数据更新机制 | A：GameManager 新增 brick_scored/pierce_scored 信号 | `game_manager.gd` |
| 布局与视觉 | A：三区分区 + ui_neon_style 共享工具 | `game_hud.gd` / `ui_game_hud.tscn` / `ui_neon_style.gd` |
| 剩余砖数契约 | 增补 `wall_generated(remaining)` 到 BreakoutGrid 契约（#384 实现前零成本） | DESIGN #414 附注 + HUD 容错消费 |

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body）

- [x] **AC1: HUD 所有数字使用霓虹描边+微投影样式，在雨幕动效下可读** — 所有数字 Label 经 `ui_neon_style.apply()` 设置 `font_outline_color`+`outline_size>0`+`font_shadow_color`+`shadow_offset`；HUD layer=1 在雨幕 layer=0 之上（结构性可读）+ 描边/投影对比度；test_hud.gd 断言每个数字 Label 的 theme override 非零
- [x] **AC2: 玩家为蓝色，AI 为红色，拆砖和穿墙分数在两个独立区域** — 顶部 AI 区（PLAYER_NEON_BLUE 用于玩家/AI_NEON_RED 用于 AI）；每区拆砖/穿墙为两个独立 Label；test_hud.gd 断言分区锚点（AI 区 anchor_top=0、玩家区 anchor_bottom=1）与配色
- [x] **AC3: HUD 显示当前波次和剩余砖数（由 BreakoutGrid 提供）** — 波次号 = `GameManager.wave_started` + 初始 `wave_index`；剩余砖数 = `brick_destroyed`（读 grid.remaining_bricks）/ `wall_cleared`（0）/ `wall_generated`（新墙总数，契约增补）；grid 未接线 → 显示「—」占位 + push_warning 一次，不报错
- [x] **AC4: 720x1280 下 HUD 不遮挡球道与砖墙主体** — 顶部区 y∈[12,84]、底部区 y∈[1252,1280]（玩家挡板 1230–1250 下方）；与砖墙 y=640 无交集；test_hud.gd 安全区断言 + Spike 2 截图实测
- [x] **AC5: 分数更新来自 GameManager 信号，不使用轮询** — score_changed（总分）/ brick_scored（拆砖）/ pierce_scored（穿墙）/ wave_started（波次）/ grid 信号（剩余砖数）；`game_hud.gd` 无 `_process` 轮询（代码审查 + 测试断言无 _process）

### 边界情况（Edge Cases）

1. **#384 未接线期（当前 main 状态）** — `get_node_or_null("../BreakoutGrid") == null` → 剩余砖数显示「—」，其他区正常；#393 接线后自动生效（容错模式已由 scoring_manager/wave_controller 验证）
2. **`wave_started` 先于 `generate_wave` 发出** — 新墙剩余数在 `wave_started` handler 里**同步读**是旧值；用 `call_deferred`（帧末，generate_wave 已执行）读 `grid.remaining_bricks`，或等 `wall_generated` 信号（契约增补后首选）——测试钉两种路径
3. **雨幕可读性** — HUD 在 L3（layer=1）位于 L0 雨幕之上，雨滴永远绘制在 HUD 之下；描边+投影提供对亮球/bloom 的对比度；Spike 1 用 02_midgame 截图实测
4. **boundary 兜底分**（无墙期普通出界 1 分）— 触发 score_changed 但不触发 brick_scored/pierce_scored；总分更新、双区不动——测试钉「boundary 不触发按类信号」
5. **终局后信号** — `add_score` 在 `is_run_over()` 时直接 return（#385 守卫）→ 无信号泄漏；HUD 保持终局分数，GAME_OVER 屏接管
6. **初始播种** — `_ready` 时无信号：从 `GameManager.player_score/ai_score/wave_index` + 查询 API 播种（#292 惯例）；grid 未接线时剩余砖数播种为「—」
7. **同帧拆砖+穿墙** — ScoringManager 帧守卫（#385 AC4）保证同帧只计一种；HUD 按收到的信号更新即可，无冲突
8. **字号/行高** — 底部区 28px 高单行（font ~20px）；若默认字体行高超界，Label 设 `autowrap` 关闭 + `clip_text` 或用左右下角双子区布局（taste 决策，Spike 2 截图确认）

### 失败路径（Failure Paths）

1. **E2E 断言因新 HUD 变红**（02_midgame 新增红区/信息条影响色数/帧间差异断言）→ 先调 shot 参数（settle_frames/断言阈值），不删 HUD 内容；若主题色断言（4a90d9）被 AI 红区干扰，检查断言实现是否允许多主题色
2. **headless 下 theme override 不可读**（GDD16 已知坑：`get_theme_font_size` 返回 0）→ 测试一律用 `label.get("theme_override_...")` 断言（既有约定）；ui_neon_style.apply 走标准主题覆盖，headless 安全
3. **Main.tscn 内联 HUD 与 ui_game_hud.tscn 不同步**（双份维护风险）→ 本 Issue 改为 Main.tscn 实例化 ui_game_hud.tscn（节点名 GameHUD 不变）；若实例化遇阻（#393 组装范围冲突），至少保证两处子树一致 + test_main_scene TC20-11 同步
4. **grid 契约增补（wall_generated）未被 #384 实现采纳** → 回退路径：HUD 在 `wave_started` handler 内 `call_deferred` 读 `grid.remaining_bricks`（边界 2 路径），功能等价，不阻塞
5. **底部区与玩家挡板视觉重叠**（安全区计算误差）→ Spike 2 截图实测 + 安全区断言兜底；taste 阶段允许微调底部区锚点（±4px）

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #383 轴交换+竖屏 720×1280 | ✅ CLOSED | Low — 布局坐标系已定 |
| #385 双得分制（计数 + score_changed + 查询 API） | ✅ CLOSED（PR #424） | Low — 双区数据源 |
| #386 波次循环（wave_index + wave_started） | ✅ CLOSED（PR #428） | Low — 波次号数据源 |
| #384 砖墙系统（remaining_bricks 契约） | ✅ CLOSED（PRD #411 + DESIGN #414 合并；**实现未落地**） | **Med** — 剩余砖数源缺失 → 容错消费 + 契约增补 `wall_generated`（§4.3） |
| #389 动态雨幕（L0 分层） | ✅ CLOSED（PR #416） | Low — 可读性上下文 |
| #292 UI 系统（HUD 基线） | ✅ 已落地 | Low — 保留信号链/可见性控制 |

### 阻塞（Blocks）

| 后续工作 | 优先级 | 说明 |
|---------|:---:|------|
| #393 主场景组装 | P0 | BreakoutGrid 接线后 HUD 剩余砖数自动生效（本 Issue 已容错）；组装时核对 GameHUD 实例化方式 |
| #388/#390/#391 UI 系列 | P1 | 复用 `ui_neon_style.gd` 保证全 UI 霓虹视觉一致（本 Issue 先行落地样式工具） |

### 依赖链

```
#383 竖屏（✅） → #384 砖墙契约（✅ PRD/DESIGN，实现未落地） → #385 双得分（✅）
                → #386 波次（✅）→ #389 雨幕（✅）
                                        │
                                        ▼
                              Issue #392 霓虹UI升级（本 PRD — L3 HUD 执行层）
                                        │
        ├──► 消费: GameManager 信号（#385/#386）+ BreakoutGrid 契约（#384，容错）
        ├──► 被组装: #393 主场景组装（接线后剩余砖数生效）
        └──► 被复用: #388/#390/#391（ui_neon_style.gd）
```

---

## 7. Spike / 实验

depth/standard 下 Section 7 非必填，但存在两项真实技术不确定性（headless 下 outline/shadow 渲染与 E2E 断言影响、720×1280 布局遮挡），故包含 2 个轻量实验，成本各 ≤0.5 天：

### 实验 1：霓虹描边+微投影 headless 安全性与 E2E 断言影响

- **问题**：AC1 要求描边+投影在雨幕下可读；GDD16 记录 headless 下 theme override 读取有坑（get_theme_font_size 返回 0）；E2E 02_midgame 截图将包含新 HUD，4 重断言（非黑/色数/主题色/帧间差异）是否仍过未知
- **方法**：实现最小原型（ui_neon_style.apply + 三区 Label）后：headless 跑 run_tests.gd（断言 outline_size>0/shadow_offset 非零可读）；实机跑 e2e loop 截图，对比改造前后 02_midgame 的 analyze_bmp 断言输出
- **预期结果**：headless 下 theme override 经 `get()` 可读（既有约定）；E2E 断言全过或仅需微调 shot 参数（settle_frames）——不得删除 HUD 内容
- **对方案影响**：若 E2E 色数断言对新增红色（ff3355）过敏，调整断言阈值而非回退分区布局；若 outline_size=6 在 20px 小字号下糊字，下调至 4（taste 参数，constants 可调）

### 实验 2：720×1280 布局遮挡实测

- **问题**：AC4 要求 HUD 不遮挡球道与砖墙主体；底部区仅 28px 高（1252–1280），单行「总分+拆/穿」在默认字体下是否容纳、是否与玩家挡板（y≤1250）重叠未知
- **方法**：临时场景按 4.2 Approach A 布局实例化三区，实机截图（720×1280）叠加球道中线与砖墙 y=640 参考线，逐区测量 Label rect 与挡板/砖墙矩形交集
- **预期结果**：顶部区 y∈[12,84] 与 AI 挡板（30–50）仅上缘 6px 内轻微交叠或完全避开（可接受，与现状 HUD 一致）；底部区与玩家挡板零交集；信息条不覆盖砖墙
- **对方案影响**：若底部单行容纳不下，切换左右下角双子区布局（x<290 / x>430）——布局参数进 constants.gd `HUD_*`，方案 A 结构不变

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #392 当前 `workflow/available`，本 PRD merge 后 workflow-chain 自动推进 → `workflow/plan`
- 基线：`main` HEAD = `a096a94`（#428 波次循环已 merge，其后仅 docs 提交）；`godot --path mini-pong/ --headless --script tests/run_tests.gd` 当前**全绿**（基线实测，含 Wave Cycle/FSM Integration 套件，1487 用例，2026-08-13 复跑确认：1487 passed / 0 failed）
- 上游方案已确认：`docs/PLAN-rogue-pong.md` §3.3（UI 规格权威源）+ §3.1（L3 分层）
- Obsidian 知识检索：本会话 Vault 挂载超时（`Too many open files`，与 #384/#386 同症状，重试 36 次失败）；理论兜底 = PLAN §3.3 + #385/#389 已注入的《体验引擎》引用与「90 年代地摊文艺」反例约束（克制优先）——已体现在 §4.2/§5 的设计语言

### 关键决策（plan agent 必须继承）

1. **Approach A（4.1）**：GameManager 新增 `brick_scored(side)` / `pierce_scored(side)` 信号（add_score 内按 kind emit，纯增量，不改既有信号）；HUD 双区各连其信号 —— AC5「所有更新走信号」字面满足
2. **Approach A（4.2）**：三区分区布局——顶部 AI 红区（y∈[12,84]：总分 + 拆/穿双子区）、底部玩家蓝区（y∈[1252,1280]，挡板下方单行）、中立信息条（「第 N 波 · 剩余 x」）；霓虹样式收敛 `ui_neon_style.gd` 静态工具（默认字体 + 主题覆盖，PLAN §3.3）
3. **契约增补**：建议向 #384 DESIGN 增补 `wall_generated(remaining)` 信号（#384 实现未落地，零成本）；未采纳则回退 `wave_started` handler 内 `call_deferred` 读 `grid.remaining_bricks`（§5 失败路径 4）
4. **容错消费**：`get_node_or_null("../BreakoutGrid")` + `has_signal/has_method` 双守卫（scoring_manager/wave_controller 同构）；未接线时剩余砖数显示「—」，不报错
5. **Main.tscn**：GameHUD 改为实例化 `ui_game_hud.tscn`（消除双份定义、统一 layer=1）；节点名保持 `GameHUD`（FSM/StartMenu/test_main_scene 引用不变）；若与 #393 组装冲突则保持内联但两处同步
6. **样式参数**：`constants.gd` 新增 `HUD_*` 组（outline_size/shadow_offset/安全区/信息色）；描边粗细、投影偏移、底部布局（单行 vs 左右下角）为 taste-draft，交 human-review 定稿
7. **测试**：`test_hud.gd`（样式/信号/剩余砖数/容错/安全区/headless）+ `test_game_manager.gd` 信号用例 + run_tests.gd 注册；theme override 断言用 `get()`（GDD16 坑）；test_ui_system/test_main_scene 同步
8. **E2E**：02_midgame 截图含新 HUD，4 重断言实测通过（必要时调 shot 参数，不删 HUD）

### 实现顺序建议（plan agent 参考）

1. `constants.gd`（HUD_* 常量）→ 2. `ui_neon_style.gd`（静态样式工具）→ 3. `game_manager.gd`（2 信号 + test_game_manager 用例）→ 4. `ui_game_hud.tscn` 重排分区 → 5. `game_hud.gd` 重构（信号接线 + 样式 + 容错）→ 6. `Main.tscn` 实例化改造（或同步内联）→ 7. `test_hud.gd` + run_tests.gd 注册 + test_ui_system/test_main_scene 同步 → 8. Spike 1（E2E 断言实测）→ 9. Spike 2（布局遮挡截图实测）→ 10. 本地 headless 全绿 + E2E 实弹截图

### 主要风险

- E2E 断言受新 HUD 影响变红（Spike 1 前置实测兜底）
- 底部区 28px 容纳问题（Spike 2 实测 + 左右下角双子区备选）
- `wall_generated` 契约增补不被采纳（call_deferred 回退路径等价）
- 双份 HUD 定义不同步（实例化改造消除，test_main_scene TC20-11 兜底）

### 交接清单

- [ ] 本 PRD 文件 `docs/PRD/392-neon-ui-upgrade.md`
- [ ] 上游方案 `docs/PLAN-rogue-pong.md` §3.3 + §3.1（UI 规格/分层权威源）
- [ ] 契约源 `docs/DESIGN/384-breakout-grid-brick-wall.md`（remaining_bricks/brick_destroyed/wall_cleared + 建议增补 wall_generated）
- [ ] 数据源 `game_manager.gd`（score_changed/wave_started/get_brick_count/get_pierce_count 现状）
- [ ] 实测基线：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 当前全绿（实现前可复跑对照）

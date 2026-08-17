# PRD: [Feature] title 支持游戏模式选择，支持本地双人对战

> **Issue:** #543
> **标签:** enhancement, workflow/available → workflow/research（research 阶段处理）
> **Agent:** game-research-agent
> **日期:** 2026-08-18
> **深度:** depth/standard（Issue body「工作深度: auto」且无 depth/ 标签，按 #392/#449/#464/#476/#527 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（InputMap 运行时重建的 headless 安全性、双焦点环同屏交互、title 新增 UI 对 E2E theme_absent 断言的影响）而包含 3 个轻量实验，沿 #527 先例）
> **所有权:** `content_ownership: mixed`（模式状态机/输入拆分/debuff 机制/目标解析契约 = mechanical 可测；debuff 卡名/短句/数值 = taste-draft，走 #395 域 human-review 定稿，零代码改动可调）
> **上游方案:** PLAN-rogue-pong §1 三条设计主线（Pong×Breakout 对打、肉鸽 3 选 1 升级、雨夜氛围）——本 Issue 在其「对打」主线上扩展**本地双人对战**形态，不改变波次/升级/得分机制本身
> **并行上下文:** 无并行 research（#543 无其他 open PR/branch）；不触碰波次触发（#529）、画面丰富化（#527）、暂停/标题世界隐藏（#508/#513）的既有实现

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280，Forward+）目前**只有单人模式**：玩家（底部挡板，A/D + ←/→ 控制）对战 AI（顶部挡板，球追踪），title 屏只有「按 SPACE 开始」单一入口（#292/#508），游戏模式不可选。升级系统（#387/#388）9 个定义中 6 个可选升级**全部是自身增益**（buff），无任何针对对手的减益（debuff）——单人模式下合理，但双人模式下「三选一」只有自利卡，缺少马里奥赛车式「害对手」的策略博弈。输入层面 `paddle_left/paddle_right` 把 A/D 与 ←/→ **绑在同一 action**（#383 竖屏定稿），双人分键前必须先拆分。

| 系统 | 文件 | 当前状态 | 与 #543 的差距 |
|------|------|---------|---------------|
| Title 屏 | `scenes/ui_start_menu.tscn` + `gdscripts/start_menu.gd` | 单 PromptLabel「按 SPACE 开始」，无模式选项；`show_menu()/hide_menu()` 由 FSM 控制 | ❌ 无游戏模式选择入口；标题即「单人 AI 对战」硬编码 |
| 开始流 | `gdscripts/game_state_machine.gd` `_input()` | MENU 态 `ui_accept`(SPACE/Enter) 直接 `transition_to(SERVING)`；`enter_state(SERVING)` 里 `reset_match()` | ❌ 无模式读取/透传；2P 模式需在开始前决定并配置双挡板 |
| 挡板输入 | `gdscripts/paddle.gd` `_ready()` + `_process()` | `Mode.PLAYER` 运行时把 A/D+←/→ 绑进 `paddle_left/paddle_right`（`if not InputMap.has_action` 守卫）；AI 模式追踪球 | ❌ 双人分键需要独立 action（P2 = ←/→）；当前 ←/→ 与 A/D 同 action，2P 下会双板同动 |
| 升级池 | `gdscripts/upgrade_defs.gd` + `upgrade_pool.gd` | 9 定义（6 可选 + 3 桩过滤）；`_build_ctx()` 经 `paddles` 组取**第一个**挡板为 `paddle` 目标 | ❌ 无「谁在升级/对手是谁」语义；无 opponent 目标解析；无 debuff 定义 |
| 升级 UI | `gdscripts/upgrade_pick_ui.gd` + `ui_upgrade_pick.tscn` | 单焦点环：`ui_left/ui_right` 循环移动、`ui_accept` 确认 → `UpgradePool.apply(id)`；树级暂停下 `PROCESS_MODE_ALWAYS` | ❌ 无双人确认路径（P1=E / P2=右Shift）；单焦点环无法表达双游标 |
| 得分/胜负 | `gdscripts/game_manager.gd` + `scoring_manager.gd` + `ball.gd` | 双得分制：winner 语义 `"player"`（底侧）/ `"ai"`（顶侧），先到 21 分 `match_over` | ✅ 机制可复用：2P 下 P2 映射到 `"ai"` 侧即可，零改动 |
| HUD/结算 | `game_hud.gd` / `game_over_screen.gd` | 顶区显示「AI 红区」、结算屏 `is_fail = winner=="ai"` → 「YOU WIN!」/失败文案 | ⚠️ 2P 模式需把显示名从「AI」翻译为「P2」，结算屏显示 P1/P2 胜者 |
| E2E | `e2e_shots.json` | `autoplay.mode=ai` 把双板 mode 覆盖为 1（AI 对打）；`01_title` 断言 MENU 态 + `theme_absent: 4a90d9`；`02_midgame` 按 `enter` 开始 | ⚠️ title 新增模式选择 UI 不得破坏 theme_absent；默认单人 + SPACE 直开需保持 autoplay 兼容 |

**关键事实核查（来自源码 + 既有 PRD）：**

- **`paddle.gd` 已有 Mode 枚举与完整 PLAYER/AI 双路径**（#290/#383）：`enum Mode { PLAYER=0, AI=1 }`、`@export var mode`、AI 参数 `@export` 可调、`paddles` 组注册。2P 模式 = 双板均 `mode=PLAYER` + 新增 `player_index` 区分输入/连击/升级归属，AI 路径原样保留给单人模式。
- **输入绑定是运行时的**：`paddle.gd:_ready()` 对 PLAYER 模式动态 `InputMap.add_action`（A/← → paddle_left，D/→ → paddle_right），`project.godot` **没有** `[input]` 段。→ 双人分键既可以在运行时按模式重建绑定，也可以在 `project.godot` 静态定义后运行时只做模式化增删（Spike 1 验证 headless 安全性）。
- **升级目标解析只认第一个挡板**：`upgrade_pool.gd:_build_ctx()` → `get_first_node_in_group("paddles")`。现有 6 个自利效果（long_arm/fireball/battering_ram/magnet_core/slow_time/pre_hole）全部读 `ctx["paddle"]`。2P 需要 `self_paddle`/`opponent_paddle` 双目标，且**既有效果必须回退兼容**（`ctx["paddle"]` 兜底，测试 mock 零回归）。
- **连击加速（#504）只认 PLAYER 模式 + player_score**：`paddle.gd:_on_score_changed` 用 `_last_player_score` 跟踪 player 侧分数。2P 下 P2 挡板（PLAYER 模式）也会收到 `score_changed`——**P2 应跟踪 ai_score**，否则 P2 连击逻辑错乱（实现细节：按 `player_index` 选分数通道）。
- **`ui_accept` 是 SPACE/Enter**（Godot 内建 action，FSM/升级 UI 共用）；E 与右 Shift 当前**未被任何 action 占用**（grep 无绑定），可安全用作 `p1_confirm`/`p2_confirm`。
- **#508 世界隐藏纪律**：MENU 态 `_set_world_visible(false)` 隐藏 `game_world` 组。模式选择 UI 挂在 `StartMenu`（CanvasLayer layer=1）内即天然在 MENU 可见、开局后随 StartMenu 隐藏——结构性兼容，无需新机制。
- **`game_over_screen.gd` 文案**：`is_fail := winner == "ai"`（#391 双分支）。2P 下 `"ai"` 语义 = P2：显示层把 P2 胜利从「失败文案」分支切到「胜者宣告」分支（P2 WIN!），内部 winner 字符串不动。

### 1.2 Obsidian 知识库搜索结果（issue 未勾选「搜索 Obsidian」；深度 auto → standard 惯例自动搜索）

| 检索范围 | 命中文档 | 结论 |
|---------|---------|------|
| `/Volumes/Obsidian/Knowledge Ocean/wiki/`（WebDAV 挂载）grep `双人\|本地对战\|对战\|P2\|两个玩家` | `CUSGA 2026 游戏评选笔记.md`（「高达对战」游戏名）、`This War of Mine`（机制即叙事） | 无本项目双人/对战模式设计笔记；均为泛义命中 |
| 同上 grep `升级\|肉鸽\|马里奥赛车\|害对手\|debuff` | `中国科幻80年代低谷.md`、`极乐迪斯科`（概率机制） | 无升级博弈/害对手设计笔记 |
| 同上 grep `PONG://\|mini-pong\|标题\|title\|游戏模式` | 无命中 | 无本项目 title 屏/模式选择设计笔记 |

**结论：Obsidian 知识库无本项目双人模式/模式选择设计笔记，知识搜索无新增约束。** 设计意图以仓库内既有 PRD/DESIGN（#292 title、#290 AI 对手、#383 竖屏输入、#387/#388 升级、#385 双得分、#294 FSM）与 PLAN-rogue-pong 为准（#508 同款降级路径）。

### 1.3 预期行为（验收条件，源自 Issue #543）

1. [ ] **AC1 — title 支持游戏模式选择，默认单人（AI 对战）** — 标题屏新增模式选项（「单人模式（AI 对战）」/「本地双人对战」），默认选中单人；SPACE/Enter 以当前选择开始；单人路径与现状零行为差异（#508 世界隐藏、FSM 开始流不变）
2. [ ] **AC2 — 本地双人模式：P1 底侧 A/D 移动 + E 确认升级** — P1 挡板（底）用 A/D 控制方向；升级选择用 A/D 移动游标、**E 确认**；E 不与其他 action 冲突
3. [ ] **AC3 — 本地双人模式：P2 顶侧 ←/→ 移动 + 右 Shift 确认升级** — P2 挡板（顶）用 ←/→ 控制方向；升级选择用 ←/→ 移动游标、**右 Shift 确认**；与 P1 输入互不干扰（分键后 A/D 不再触发 P2、←/→ 不再触发 P1）
4. [ ] **AC4 — 双人「三选一」升级含害对手（debuff）升级** — 2P 模式候选池 = 现有自利卡 + ≥3 种害对手卡（缩板/冻结/减速/方向紊乱等，数值 taste 占位）；单人模式候选池行为不回归（debuff 卡不进单人池）
5. [ ] **AC5 — 双人模式得分/胜负/HUD/结算语义正确** — 内部 winner 复用 `"player"/"ai"`；HUD 顶区显示 P2（替代「AI」）；结算屏 P1/P2 胜者宣告正确（P2 胜利不再走失败文案分支）
6. [ ] **AC6 — headless 无脚本错误 + run_tests.gd 全绿** — `--headless --quit` 无错误；既有测试（FSM/挡板/升级池/升级 UI/双得分等）零回归；新增纯逻辑可单测（InputMap 重建、2P 目标解析、debuff 回调、模式状态机）
7. [ ] **AC7 — E2E L0–L2 全绿** — `run-e2e-review.sh --skip-visual`：01_title MENU 态 + theme_absent 保持（新增 UI 色避开 #4a90d9 容差 32）、02_midgame/03_gameover autoplay（双 AI 对打）兼容模式选择默认值
8. [ ] **AC8 — PR files 仅含本 Issue 文件域** — 白名单 = §4.5 推荐表所列文件；不混入波次/画面/暂停等其他 issue 文件

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 单人开玩（默认） | 常态 | 开机 → title 默认选中「单人模式（AI 对战）」→ SPACE 直开，与现状完全一致；雨夜竞技场 + AI 对手 |
| B | 本地双人对战 | 每局 | title 切到「本地双人对战」→ SPACE 开始 → P1 底侧 A/D、P2 顶侧 ←/→ 同屏对打；砖墙/波次/得分与单人一致 |
| C | 双人波间升级 | 每波 | 波清结算 → 三选一升级：P1 用 A/D+E、P2 用 ←/→+右Shift 各自选择；候选卡里出现「缩小对手挡板」「冻结对手」等害对手卡——先确认者锁定，后确认者从剩余卡选，同屏博弈 |
| D | 双人终局 | 每局末 | 先到 21 分者胜：HUD 顶区显示 P2 分数（红区语义保留）、结算屏宣告 P1/P2 胜者；SPACE 回 title 可换模式重开 |

### 1.5 技术约束（继承 Issue #543 + 既有架构）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 project.godot，720×1280 竖屏，Forward+） |
| 输入拆分 | `paddle_left/paddle_right`（A/D+←/→ 同 action，#383）必须按模式拆分：单人保持现状；双人 A/D 仅 P1、←/→ 仅 P2；新增 `p1_confirm`(E)/`p2_confirm`(右Shift)——E/右Shift 当前无占用（已验证） |
| 模式状态 | 新增模式状态（GameManager 或 FSM 持有）：`SINGLE`（默认）/`LOCAL_2P`；title 选择 → 开始流读取 → 双挡板配置（2P 下 AIPaddle 节点 `mode=PLAYER, player_index=1`） |
| 升级目标契约 | `UpgradePool` ctx 扩展 `self_paddle`/`opponent_paddle`；既有 `paddle` 键回退兼容；`apply(id, player_index)` 签名向后兼容（默认 0） |
| 单人池隔离 | debuff 卡不进单人候选池（`get_candidates(n, allow_opponent)` 过滤或按模式过滤）；单人模式 6 卡池 + 3 桩过滤行为逐字节不变（#526 纪律） |
| #508 世界隐藏 | 模式选择 UI 挂 `StartMenu` CanvasLayer（layer=1），MENU 可见、开局随 StartMenu 隐藏；不新增 game_world 节点 |
| E2E 断言 | `theme_color 4a90d9` 全局 + `01_title theme_absent`；新增 UI 元素色避开 #4a90d9（tol 32）；`autoplay.mode=ai` 双板覆盖为 AI——与模式选择默认值解耦（默认单人即可兼容） |
| 动效纪律 | PLAN §3.3：模式选项高亮切换 Tween 150–300ms，不弹跳不花哨 |
| 克制纪律 | Obsidian「抽象留白」+ CUSGA「堆砌反例」：双人 = 最小机制增量（模式选择 + 分键 + debuff 池 + 双游标），不新造玩法系统；debuff 数值/文案走 taste 域 #395 定稿 |
| 开源优先 | 不引入第三方资产；引擎内建（InputMap/VBoxContainer/Label/ColorRect）实现（§1.6） |

### 1.6 开源优先调研结果

调研时间 2026-08-18，检索 Godot Asset Library（godot_version=4.7）+ 社区：

- **本地双人同屏输入**：Godot 标准做法 = InputMap 多 action + 按 player 索引读（`Input.get_axis("p1_left","p1_right")` 模式）；社区无「Pong 双人模式」addon，引擎内建能力完整覆盖
- **双游标升级 UI**：无现成 addon；Control 节点 + 双 focus 索引渲染为第一方标准做法（#388 单游标已有同构先例）
- **害对手（debuff）升级**：无「Pong debuff」addon；`upgrade_defs.gd` 定义扩展（target 字段 + opponent 回调）为第一方标准做法
- **结论**：**无可直接复用的成熟方案**，第一方实现零依赖、headless 可测，符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。

---

## 2. 设计意图

### 2.1 现状成因

| 现状 | 成因 Issue | 说明 |
|------|-----------|------|
| 只有单人模式，title 无模式选择 | #292（title 屏）/#294（FSM）/#290（AI 对手） | MVP 路径：先做「玩家 vs AI」闭环（#290 是早期 feature），title 单入口「按 SPACE 开始」满足 MVP；模式选择从未被需求化 |
| A/D 与 ←/→ 绑同一 action | #383（竖屏布局） | 竖屏化时「底侧挡板」单手可达性设计：A/D 为主、←/→ 为辅（同一挡板双键位），单人场景下无冲突；双人分键需求首次出现 |
| 升级池全为自利 buff | #387（升级池架构） | 单人 vs AI 语境下「升级 = 强化自己」；对 AI 的 debuff 语义弱（AI 数值由难度系数驱动，#290/#386），无人提议害 AI 卡 |
| 升级 UI 单焦点环 | #388（3 选 1 UI） | 单人确认链 `ui_left/ui_right/ui_accept` 单一输入源；双人双确认需求首次出现 |

### 2.2 为何现在做

1. **玩法闭环已齐，双人是自然的横向扩展**：波次/砖墙/双得分/升级/结算全部机制就绪（#384–#393），加双人 = 在既有对打主线上把「对手」从 AI 换成真人，机制增量小、收益大（issue 原话「双人游戏更有趣」）。
2. **title 是唯一入口，模式选择必须在此落地**：单场景常驻架构（#295/#393）下 title 屏是每局必经节点，模式选择 UI 挂 StartMenu 结构性最简（#508 纪律已保证 MENU 世界隐藏）。
3. **输入分键时机成熟**：`paddle.gd` 已有 Mode 枚举与 PLAYER 双路径，加 `player_index` 是增量扩展；E/右Shift 无占用，分键零冲突。
4. **debuff 卡是双人博弈的调味剂**：马里奥赛车式「害对手」让三选一从「纯自利数值」变成「攻防选择」，双人策略深度显著提升；单人池隔离保证零回归。

### 2.3 既有约束（必须继承）

| 约束 | 详情 | 出处 |
|------|------|------|
| winner 语义 `"player"/"ai"` | 双得分制（#385）与 FSM/结算/HUD 全链路消费；2P 下 P2 映射 `"ai"` 侧，**不改内部字符串** | #385 DESIGN §2.2 |
| `paddles` 组 + `_build_ctx` 惰性解析 | UpgradePool 目标解析先例；扩展不破坏既有测试 mock（ball_ref/paddle_ref 可注入） | #387 DESIGN §3.2 |
| 桩过滤纪律 | 玩家可选的升级必须全部有可见反馈（#526）；新增 debuff 卡不得是桩 | #526 PRD §2.2 |
| #508 世界隐藏 | MENU 隐藏 `game_world`；模式 UI 挂 StartMenu 层 | #508 修复 |
| 连击（#504）PLAYER-only | 2P 下双板均 PLAYER → 连击对双方启用，各自按 player_index 跟踪分数通道 | #504 PRD |
| 树级暂停下 PROCESS_MODE_ALWAYS | 升级 UI 在 `get_tree().paused` 下仍响应输入（#388 AC4）；2P 双游标沿用 | #388 DESIGN |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `scenes/ui_start_menu.tscn` | Title 屏 | 新增模式选择区（ModeSelect VBox：两个选项 Label/按钮 + 高亮指示） |
| `gdscripts/start_menu.gd` | Title 屏逻辑 | 模式选项状态 + ↑/↓（或 W/S）切换 + 选中模式透传给 GameManager/FSM；`_on_start_pressed()` 前设置模式 |
| `gdscripts/game_state_machine.gd` | FSM | MENU→SERVING 前读取 GameManager.game_mode；2P 模式无 FSM 改动（双板冻结逻辑已通用），仅确认模式已配置 |
| `gdscripts/game_manager.gd` | 全局状态 | 新增 `enum GameMode { SINGLE=0, LOCAL_2P=1 }` + `game_mode` 变量 + `set_game_mode()/get_game_mode()`；`reset_match()` 不动 |
| `gdscripts/paddle.gd` | 挡板 | 新增 `@export player_index: int = 0`；`_ready()` 按 `player_index` 绑定输入（0 → paddle_left/paddle_right，单人模式追加 ←/→；1 → p2_left/p2_right）；`_process()` 按索引读 action；连击按索引跟踪分数（P2 看 ai_score） |
| `gdscripts/upgrade_defs.gd` | 升级定义 | 新增 ≥3 个 debuff 定义（`target: "opponent"` 字段 + `_effect_*` 回调，读 `ctx["opponent_paddle"]`）；既有 6 卡加 `target: "self"`（默认） |
| `gdscripts/upgrade_pool.gd` | 升级池 | `_build_ctx()` 扩展 `self_paddle`/`opponent_paddle`（按 player_index 从 paddles 组解析，`paddle` 键回退）；`apply(id, player_index=0)`；`get_candidates(n, allow_opponent)` 模式过滤 |
| `gdscripts/upgrade_pick_ui.gd` | 升级 UI | 2P 模式双游标：P1 用 A/D+E、P2 用 ←/→+右Shift；先确认者锁定卡片，后确认者从剩余卡选；reveal 双方完成后统一关闭 |
| `gdscripts/game_hud.gd` | HUD | 2P 模式顶区显示名「AI」→「P2」（红区颜色语义保留，P2 仍是红区） |
| `gdscripts/game_over_screen.gd` | 结算屏 | 2P 模式胜者宣告：`winner=="player"` → 「P1 WIN!」、`winner=="ai"` → 「P2 WIN!」（不再走失败文案分支）；败者侧可显示统计 |
| `gdscripts/constants.gd` | 常量 | 新增 `GAME_MODE_*`/`P2_*` 输入 action 名、`DEBUFF_*` 数值占位（taste 域）、`DEBUFF` target 常量；既有常量逐字节不动（#448/#449/#450 并行先例） |
| `mini-pong/project.godot` | 输入定义 | 可选：静态定义 `p1_confirm`(E)/`p2_confirm`(右Shift)/`p2_left`/`p2_right`（或全部运行时绑定，Spike 1 定稿） |
| `mini-pong/e2e_shots.json` | E2E | 可选：01_title 增加模式选择 UI 存在性断言（默认单人态）；autoplay 兼容性验证 |

### 3.2 新文件

| 文件 | 用途 |
|------|------|
| `mini-pong/tests/test_local_2p.gd` | 新增测试套件：模式状态机、InputMap 拆分、2P 目标解析、debuff 回调、双游标确认流（注册进 `tests/run_tests.gd`） |
| （可选）`mini-pong/gdscripts/game_mode.gd` | 若模式状态逻辑超出 GameManager 职责（不推荐，GameManager 已可承载） |

### 3.3 间接影响

| 模块 | 影响 | 说明 |
|------|------|------|
| `ball.gd` | 无改动 | `last_toucher`/`score(side)` 语义不变；2P 下 P2 触球 = `"ai"` toucher，天然正确 |
| `scoring_manager.gd` | 无改动 | side 0/1 → player/ai 映射不变；拆砖归属按 last_toucher 不变 |
| `wave_controller.gd` | 无改动 | 波次/升级挂点与玩家数量无关 |
| `brick_upgrade_hooks.gd` / `breakout_grid.gd` | 无改动 | pre_hole/fireball 等 grid 类效果与对手无关 |
| `audio_engine.gd` | 无改动 | 音效与模式无关 |
| 既有测试 | 兼容 | paddle mock 无 `player_index`（默认 0）→ 行为不变；`_build_ctx` 保留 `paddle` 键 → UpgradePool 测试零回归 |

### 3.4 数据流影响

**模式选择流（title → 开局）：**

```
StartMenu（title）
  ├── 默认 SINGLE；↑/↓ 切换选项 → 高亮 Tween（150–300ms）
  ├── SPACE/Enter（ui_accept）→ FSM._input() MENU 分支
  │     └── GameManager.set_game_mode(selected)
  │           └── transition_to(SERVING)
  │                 ├── SINGLE: AIPaddle.mode=AI（现状，不变）
  │                 └── LOCAL_2P: AIPaddle.mode=PLAYER, player_index=1
  │                              PlayerPaddle.mode=PLAYER, player_index=0
  │                              InputMap 按模式重建（Spike 1 定稿）
  └── GameManager.reset_match()（SERVING 既有路径）
```

**2P 升级流（wave_settled → 双确认 → 应用）：**

```
GameManager.wave_settled(wave_index)
    │
    ▼
UpgradePickUI.open(wave_index)          ← 2P 模式
    ├── UpgradePool.get_candidates(3, allow_opponent=true)
    │     ├── 自利卡（target=self，6 种）
    │     └── 害对手卡（target=opponent，≥3 种，稀有度权重混合）
    ├── 双游标渲染（Card0/1/2 各带 P1/P2 焦点指示）
    │     ├── P1: p1_left/p1_right（A/D）+ p1_confirm（E）
    │     └── P2: p2_left/p2_right（←/→）+ p2_confirm（右Shift）
    ├── 先确认者: UpgradePool.apply(id, player_index) → 卡片锁定 + reveal
    └── 后确认者: 从剩余卡选 → apply → reveal → 双方完成 → close()
          └── _advance_settlement() → WaveController 下一波（#388 接管不变）
```

**升级目标解析（2P）：**

```
UpgradePool._build_ctx(player_index)
    ├── self_paddle     = paddles 组内 player_index 匹配的挡板
    ├── opponent_paddle = paddles 组内另一挡板
    ├── paddle          = self_paddle（回退键，既有效果/测试零改动）
    ├── ball / grid     = 既有惰性解析（balls / breakout_grids 组）
    └── params          = {player_index, target}
          ├── target="self"     效果读 self_paddle（long_arm/magnet_core/...）
          └── target="opponent" 效果读 opponent_paddle（shrink/freeze/slow/reverse）
```

### 3.5 文档更新清单

- [ ] `docs/DESIGN/543-mode-select-local-2p.md`（plan agent 产出，本 PRD 为输入）
- [ ] `mini-pong/tests/run_tests.gd`（注册 test_local_2p）
- [ ] `mini-pong/assets/content/upgrade_pool.json`（新增 debuff 卡显示名/短句，taste-draft 域 #395，draft 标记）
- [ ] `mini-pong/e2e_shots.json`（如 Spike 3 结论需要）
- [ ] `docs/TASTE.md`（若 debuff 命名定稿走 human-review 队列）

---

## 4. 方案对比

### 4.1 游戏模式选择 UI

**方案 A：StartMenu 内嵌模式选择区（推荐）**

在 `ui_start_menu.tscn` 的 VBoxContainer（TitleLabel/PromptLabel 之间）插入 ModeSelect 区：两个选项行「单人模式（AI 对战）」「本地双人对战」，当前选项高亮（霓虹边框/颜色，复用 #388 焦点视觉）；↑/↓（或 W/S）循环切换，SPACE 直接以当前选项开始；默认 SINGLE。

- Pros：单场景零新增 CanvasLayer；#508 纪律天然兼容（MENU 可见、开局随 StartMenu 隐藏）；默认单人 + SPACE 直开 → E2E autoplay/既有测试零改动；改动面最小（1 个 tscn + start_menu.gd）
- Cons：选项行占用 title 视觉空间（竖屏 720 宽足够，克制排版可解）；↑/↓ 在 MENU 态无既有占用（paddle frozen），无冲突
- Risk：Low；Effort：0.5–1 天

**方案 B：独立模式选择场景（新 scene + 场景切换）**

新增 ModeSelect.tscn，title → 模式选择 → 游戏三段式。

- Pros：UI 解耦清晰，未来加模式（如在线）可扩展
- Cons：与单场景常驻架构（#295/#393）冲突——需改 FSM 场景切换流、#508 世界隐藏、E2E 01_title 断言；为 2 个模式引入场景切换是过度设计
- Risk：Med；Effort：2–3 天

**方案 C：PromptLabel 改造为选项行**

把「按 SPACE 开始」直接变成两行可切换选项。

- Pros：零新增节点
- Cons：提示语与选项语义混杂（开始提示消失）；视觉挤压；可读性差
- Risk：Med；Effort：0.5 天

**推荐：A**。理由：(1) 最小机制增量符合克制纪律；(2) 单场景常驻架构下无场景切换成本；(3) 默认单人保持 E2E/既有行为零回归；(4) 未来扩展模式只需在 ModeSelect 区加行。

### 4.2 双人输入拆分

**方案 A：运行时按模式重建 InputMap（推荐）**

`paddle.gd:_ready()` 改为按 `player_index` 绑定，并在模式切换时由 GameManager/FSM 统一重建：

| 模式 | paddle_left | paddle_right | p2_left | p2_right | p1_confirm | p2_confirm |
|------|------------|-------------|---------|----------|-----------|-----------|
| SINGLE | A + ← | D + → | — | — | — | — |
| LOCAL_2P | A | D | ← | → | E | 右Shift |

实现：SINGLE 绑定保持现状（`if not InputMap.has_action` 守卫不变）；LOCAL_2P 启动时从 `paddle_left/paddle_right` 移除 ←/→ 事件（`action_erase_event`），并确保 `p2_left/p2_right/p1_confirm/p2_confirm` 存在（静态定义于 project.godot 或运行时 add，Spike 1 定稿）；重复进入 MENU 幂等（先清后建）。

- Pros：单 action 语义清晰；单人路径逐字节不变；P1/P2 键位完全隔离（A/D 不触发 P2、←/→ 不触发 P1）；E/右Shift 零冲突
- Cons：InputMap 运行时增删需要幂等设计（重复开局不残留）；headless 安全性需 Spike 1 验证
- Risk：Low；Effort：1–1.5 天

**方案 B：节点内硬编码 keycode 判断**

`_process()` 里直接 `Input.is_key_pressed(KEY_A)` 等，不走 InputMap。

- Pros：改动局部化，无 InputMap 生命周期问题
- Cons：破坏既有 action 架构（#383 输入即 action）；不可重映射；与升级 UI 的 action 判断不一致；测试 mock 输入注入困难
- Risk：Med；Effort：1 天

**方案 C：P2 复用 ui_left/ui_right**

P2 挡板读 `ui_left/ui_right`（内建 action）。

- Pros：零新增 action
- Cons：`ui_left/ui_right` 被升级 UI 焦点环消费（#388）——树级暂停下挡板虽不动，但 PLAYING 态升级窗口外无冲突不代表语义干净；且 ←/→ 与 paddle_left/paddle_right 的 A/D 合并绑定仍在，P1/P2 键位不隔离（P1 按 ← 也会动 P2）
- Risk：High（键位冲突核心问题未解决）；Effort：0.5 天

**推荐：A**。理由：(1) 唯一真正隔离 P1/P2 键位的方案（AC3 硬性要求）；(2) 单人路径零回归；(3) action 语义与既有架构一致，升级 UI 复用同一套 action 体系。

### 4.3 双人升级交互

**方案 A：同屏共享 3 卡 + 双游标（推荐）**

3 张卡不变，每张卡上渲染 P1/P2 两个焦点指示（如卡左下/右下角标）；P1 用 A/D+E、P2 用 ←/→+右Shift 独立移动游标；**先确认者锁定所选卡（该卡对另一人置灰不可选），后确认者从剩余卡选**；双方确认后统一 reveal（稀有度展示）→ 关闭恢复游戏时间。

- Pros：同屏博弈感最强（马里奥赛车式「抢卡」张力）；单次暂停窗口完成双方升级（节奏快）；WaveController 挂点零改动（仍是 1 次 wave_settled → 1 次 close）
- Cons：双游标渲染 + 锁定状态机复杂度中等（SELECTING 态拆 P1/P2 两个 focus_index + locked 卡集合）；一方确认后另一方的可选项收窄需 UI 明示
- Risk：Med；Effort：2 天

**方案 B：顺序选择（P1 先选 → reveal → P2 再选）**

同一窗口内两次选择阶段：P1 阶段（E 确认）→ reveal → P2 阶段（右Shift 确认）→ reveal → 关闭。

- Pros：实现最简单（复用单游标逻辑跑两遍）；无锁定竞态
- Cons：节奏拖沓（两段 reveal）；先选者有信息优势（看到 P1 选择后可针对性选害 P1 的卡——策略上反而有趣，但对称性差）；「同时抢」的社交张力消失
- Risk：Low；Effort：1 天

**方案 C：各自独立弹出（两次 wave_settled）**

2P 模式 wave_settled 触发两次升级窗口（P1 一次、P2 一次）。

- Pros：UI 完全复用单游标
- Cons：需改 WaveController 挂点/推进接管（#388 契约破坏）；两次暂停窗口节奏割裂；升级与波次推进耦合复杂化
- Risk：High（挂点契约改动波及 #386/#388 测试）；Effort：2.5 天

**推荐：A**。理由：(1) 最贴 issue「双人确认」语义（P1/P2 各自的键位都明确给出，暗示同屏同时操作）；(2) 单窗口单挂点，波次契约零改动；(3) 抢卡博弈强化「害对手」设计意图。

### 4.4 害对手（debuff）升级设计

**目标模型**：`upgrade_defs.gd` 定义新增 `target` 字段（`"self"` 默认 / `"opponent"`）；效果回调经 `ctx["opponent_paddle"]` 施加影响。**单人模式** `get_candidates()` 过滤 `target=="opponent"` 卡（池行为与 #526 完全一致）；**2P 模式** 自利 + 害对手按稀有度权重混合出 3 卡。数值全部 taste 占位（#395 域），机械结构与回调本 Issue 定稿。

**候选 debuff 卡（≥3 种，满足 AC4；数值为占位，命名走 #395）**：

| id | 工作名 | 稀有度 | 效果（占位数值） | 目标机制 |
|----|-------|--------|-----------------|---------|
| `shrink_opponent` | 压缩 | COMMON | 对手挡板宽度 -30%（对基数减算，max_stacks 2） | `opponent_paddle.set_paddle_width(w * 0.7)`（复用 #387 入口，反向） |
| `freeze_opponent` | 冻结 | RARE | 对手挡板冻结 1.5s | 独立于 FSM 的临时冻结：`opponent_paddle.set_frozen_timed(1.5)`（新增方法；与 FSM 全局冻结互斥计数——Spike 2 验证） |
| `slow_opponent` | 迟缓 | RARE | 对手挡板速度 -25% 持续 8s | `opponent_paddle.set_speed_scale_timed(0.75, 8.0)`（复用 #387 缓时同构：乘性 scale + 定时恢复） |
| `reverse_opponent` | 紊乱 | RARE | 对手左右方向反转 3s | `opponent_paddle.set_input_invert_timed(3.0)`（输入取反；仅对 PLAYER 模式有意义——2P 专用，单人池天然隔离） |

**实现要点**：
- `paddle.gd` 新增 `_timed_freeze`/`_speed_scale`/`_input_invert` 三套定时状态（与 #387 slow_time 的 ball 端 `set_speed_scale_timed` 同构），全部 `@export` 数值 + CONSTS 占位；
- **FSM 冻结互斥**：`set_frozen(true)`（FSM 全局）与 `freeze_opponent`（临时）需计数/优先级约定——FSM 冻结优先，临时冻结计时在 FSM 解冻后继续走完（Spike 2 实验定稿）；
- debuff 卡同样遵守 #526「可选升级必须可见反馈」：应用时在对手挡板侧触发可见效果（颜色闪变/图标），taste 域定稿；
- `upgrade_pool.json` 新增 debuff 卡条目（`draft: true`，走 #395 human-review）。

**推荐**：上述 4 卡作为 v1 集合（3 COMMON/RARE + 1 RARE）。理由：(1) 与既有 6 卡机制同构（宽度/速度/冻结/方向都是挡板已有属性），实现风险低；(2) 稀有度分布与现有 60/30/10 权重兼容；(3) 覆盖「攻防」两个维度（缩板/冻板 = 防守压制，减速/紊乱 = 进攻干扰）。

### 4.5 推荐汇总

| 子系统 | 推荐 | 核心文件 |
|--------|------|---------|
| 模式选择 UI | A：StartMenu 内嵌选项区（默认单人） | `ui_start_menu.tscn` / `start_menu.gd` |
| 双人输入拆分 | A：运行时按模式重建 InputMap | `paddle.gd` / `project.godot`（可选） |
| 双人升级交互 | A：同屏 3 卡 + 双游标 + 先锁后选 | `upgrade_pick_ui.gd` / `ui_upgrade_pick.tscn` |
| 害对手升级 | 4 卡 debuff（压缩/冻结/迟缓/紊乱） | `upgrade_defs.gd` / `upgrade_pool.gd` / `paddle.gd` |
| 模式状态 | GameManager 承载 `game_mode` | `game_manager.gd` |
| 显示层 | HUD「P2」/结算 P1·P2 胜者宣告 | `game_hud.gd` / `game_over_screen.gd` |

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单，映射 Issue #543 body）

- [x] **AC1: title 支持游戏模式选择，默认单人（AI 对战）** — 选项区默认高亮「单人模式（AI 对战）」；SPACE/Enter 以当前选择开始
  - [x] 单人路径：`GameManager.game_mode == SINGLE` → 双挡板配置与现状逐字节一致（PlayerPaddle PLAYER/0、AIPaddle AI）
  - [x] 模式切换：↑/↓（或 W/S）循环切换，高亮 Tween 150–300ms（PLAN §3.3）
  - [x] 重开路径：GAME_OVER → SPACE → MENU 回 title 时选项保留上次选择（或复位默认——二选一，plan agent 定稿，推荐保留）
- [x] **AC2: P1 底侧 A/D 移动 + E 确认升级** — P1 挡板 `_process` 读 `paddle_left/paddle_right`（A/D）；升级窗口 P1 游标 A/D 移动、E 确认
  - [x] E 键仅升级窗口 SELECTING 态消费（PLAYING 态按 E 无动作，防误触）
  - [x] E/右Shift 与 ui_accept/ui_cancel 无冲突（事件消费顺序：升级 UI `_unhandled_input` 在树级暂停下独占）
- [x] **AC3: P2 顶侧 ←/→ 移动 + 右 Shift 确认升级** — P2 挡板读 `p2_left/p2_right`；升级窗口 P2 游标 ←/→ 移动、右Shift 确认
  - [x] 分键隔离：2P 下 A/D 只动 P1、←/→ 只动 P2（Spike 1 验证 InputMap 重建后无残留绑定）
  - [x] 单人模式 ←/→ 仍控制挡板（兼容现状，#383 双键位不回归）
- [x] **AC4: 双人「三选一」含害对手升级（≥3 种）** — 2P 候选池含 `shrink_opponent`/`freeze_opponent`/`slow_opponent`/`reverse_opponent` 中 ≥3 种；单人池 0 种（过滤）
  - [x] debuff 效果对 `opponent_paddle` 生效且可见（#526 可见反馈纪律）
  - [x] 稀有度权重混合：出卡分布符合 60/30/10（池扩展不破坏 `rarity_from_roll` 纯函数）
- [x] **AC5: 双人得分/胜负/HUD/结算正确** — winner 内部 `"player"/"ai"` 不变；2P HUD 顶区「P2」；结算 P1/P2 胜者宣告
  - [x] P2 胜利走胜者宣告分支（不复用失败文案分支）
  - [x] 连击（#504）双方各自计（P1 看 player_score、P2 看 ai_score），互不污染
- [x] **AC6: headless 无脚本错误 + run_tests.gd 全绿** — `--headless --quit` 零错误；既有套件零回归；新增 test_local_2p 覆盖：模式状态机/InputMap 拆分/debuff 回调/双游标确认
- [x] **AC7: E2E L0–L2 全绿** — `run-e2e-review.sh --skip-visual`：01_title theme_absent 保持（模式 UI 色避 #4a90d9 tol 32）；02_midgame/03_gameover autoplay 兼容（默认 SINGLE + SPACE 直开）
- [x] **AC8: PR files 仅含本 Issue 文件域** — 白名单 = §4.5 表 + 测试/常量/JSON；不混入波次/画面/暂停文件

### 5.2 边界情况

1. **2P 升级一方先确认**：先确认者卡片锁定 + 置灰（另一人不可选）；被锁卡不得被后确认者 apply（`apply` 前校验 locked 集合）
2. **双方同帧确认同一卡**：帧内先后序裁决——先处理者锁定成功，后处理者收到「已锁」提示并重选（不崩溃、不双扣）
3. **单人模式误按 E/右Shift**：无绑定 action → 无动作（InputMap 无 p1_confirm/p2_confirm 时 `is_action_pressed` 返回 false，需守卫 `InputMap.has_action`）
4. **2P 模式升级窗口暂停期间 P1/P2 挡板输入**：树级暂停（#388 AC4）下挡板 `_process` 不跑，双游标输入经 `PROCESS_MODE_ALWAYS` 独占——天然无冲突
5. **FSM 冻结 vs 临时冻结互斥**：`freeze_opponent` 生效中发生 SCORED/GAME_OVER（FSM 全局冻结）→ FSM 冻结优先；恢复 PLAYING 后临时冻结剩余时长继续走完（Spike 2 定稿计数语义）
6. **2P 模式 SPACE 直开（未切换选项）**：默认 SINGLE 直接开局，与现状一致（E2E autoplay 依赖此路径）
7. **debuff 卡对 AI 挡板**：单人池过滤后不可见；2P 下 opponent 恒为 PLAYER 模式挡板（reverse 类效果对 AI 无意义，天然隔离）
8. **2P 模式重开（GAME_OVER → MENU → SPACE）**：模式状态复位或保留（推荐保留）；InputMap 重建幂等（重复开局不残留 ←/→ 于 paddle_left）
9. **升级池耗尽**：2P 下自利卡耗尽但 debuff 卡仍可出（`_available` 池按模式过滤后独立）；双方耗尽 → 既有空候选静默跳过路径（#388 失败路径 1）不变
10. **连击窗口跨模式**：模式切换发生在 MENU（得分清零时机），`_last_player_score` 基准随 `reset_match()` 复位（#504 边界 6 既有语义）——2P 下 P2 通道同样适用

### 5.3 失败路径

1. **InputMap 重建失败/残留**：`action_erase_event` 幂等失败 → 双板同动（AC3 破坏）。防护：重建前置 `InputMap.has_action` + 事件级比对；test_local_2p 断言「2P 下 A 不触发 p2_left 绑定、← 不在 paddle_left 事件集」
2. **`opponent_paddle` 解析失败（组内单板/测试 mock）**：`_build_ctx` 判空 → debuff 效果 push_warning + no-op（与 #387 既有判空风格一致），不崩溃；单人模式 `get_candidates` 过滤后 debuff 卡根本不进池，无此路径
3. **2P 升级一方确认后另一方不确认（挂起）**：升级窗口无限等待。防护：锁定后设置等待超时（如 10s，CONSTS 占位）→ 超时自动以剩余卡随机代选或视为放弃（plan agent 定稿其一，推荐超时代选保持节奏）
4. **E2E 01_title 断言回归**：模式 UI 引入 #4a90d9 系色 → theme_absent 失败。防护：模式高亮色用 PADDLE_NEON（#00e5ff）或 BRICK_NEON（#ff9d45）系（均距 #4a90d9 容差外），Spike 3 实测
5. **既有测试回归（paddle mock 无 player_index）**：`player_index` 默认 0 + `paddle` ctx 回退键 → 全部既有测试路径不变；CI L0–L2 兜底

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|------|
| #292 title 屏 + #508 世界隐藏 | ✅ 已合入 | 无（模式 UI 挂 StartMenu，纪律已固化） |
| #294 FSM（MENU→SERVING 流） | ✅ 已合入 | 无（模式读取为增量） |
| #290 AI 对手 + #383 竖屏输入 | ✅ 已合入 | 无（Mode 枚举复用；分键为本 Issue 职责） |
| #385 双得分制（winner player/ai） | ✅ 已合入 | 无（2P 映射复用，零改动） |
| #387 升级池 + #388 升级 UI | ✅ 已合入 | 无（ctx 扩展 + 双游标为增量；#526 桩过滤纪律继承） |
| #504 连击 | ✅ 已合入 | Med（2P 需按 player_index 分流分数通道） |
| #527 画面丰富化 / #529 波次触发 | ✅ 已合入 | 无（文件域无交集，AC8 白名单隔离） |
| Issue 声明依赖 | — | Issue body「Depends on: #」为空 → 无外部依赖 |

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|:------:|------|
| debuff 卡命名/数值定稿（#395 taste 域） | P1 | 本 PRD 只定机械结构与占位值；显示文案走 human-review 队列 |
| 双人模式升级池平衡性调优 | P2 | 首版后按实玩反馈调数值（taste 域） |
| （可选）害对手卡扩展（如偷球/减速球） | P3 | v1 后按需扩池 |

### 6.3 准备清单

- [ ] `constants.gd` 新增区：`GAME_MODE_*`、`P2_*` action 名、`DEBUFF_*` 占位（既有常量逐字节不动）
- [ ] `paddle.gd` 新增 `player_index` + 定时状态方法（`set_frozen_timed`/`set_speed_scale_timed`/`set_input_invert_timed`）
- [ ] `upgrade_defs.gd` 新增 `target` 字段 + 4 debuff 定义
- [ ] `upgrade_pool.gd` ctx 双目标 + `apply(id, player_index)` + `get_candidates(n, allow_opponent)`
- [ ] `upgrade_pick_ui.gd` 双游标状态机（P1/P2 focus_index + locked 集合 + 等待超时）
- [ ] `game_manager.gd` `game_mode` 状态 + setter/getter
- [ ] `start_menu.gd` 模式选项状态 + 切换 + 透传
- [ ] `game_hud.gd` / `game_over_screen.gd` P1/P2 显示分支
- [ ] `tests/test_local_2p.gd` + `run_tests.gd` 注册
- [ ] `upgrade_pool.json` debuff 条目（draft: true）
- [ ] E2E：`run-e2e-review.sh --skip-visual` 全绿验证

### 6.4 依赖链

```
#292 title ──► #508 世界隐藏 ──┐
#294 FSM ──────────────────────┼──► 本 Issue #543（模式选择 + 本地双人）
#290 AI + #383 竖屏输入 ───────┤        │
#385 双得分 ───────────────────┤        ├──► #395 taste（debuff 文案/数值定稿）
#387/#388 升级 ────────────────┘        └──► plan #543 → implement #543
```

---

## 7. Spike / 实验

> 深度 depth/standard 下 Section 7 可选；因存在 3 个真实技术不确定性，沿 #527 先例包含 3 个轻量实验。

### 实验 1：InputMap 运行时重建的 headless 安全性

- **问题**：`action_erase_event` / `action_add_event` 在 `--headless` 下是否安全？重复开局（多次 MENU→开局）是否残留绑定导致双板同动？
- **方法**：最小 GDScript（`--headless --script`）：add paddle_left(A/←) → erase ← → 断言事件集；重复 3 轮；再验证 `is_action_pressed` 对未绑定 key 返回 false
- **预期结果**：API 安全、幂等；若 `action_erase_event` 有已知竞态 → 回退方案：SINGLE/LOCAL_2P 各自完整重建（先 remove_action 再 add）
- **影响**：决定 §4.2 方案 A 的实现细节（增量 erase vs 全量重建），影响 paddle.gd/project.godot 改动面

### 实验 2：临时冻结与 FSM 全局冻结互斥语义

- **问题**：`freeze_opponent` 生效中 FSM 切 SCORED/GAME_OVER（`set_frozen(true)`），恢复后临时冻结剩余时长如何续走？双冻结计数如何不互相覆盖？
- **方法**：原型 paddle.gd 双状态（`_fsm_frozen: bool` + `_timed_freeze_remaining: float`），`_process` 冻结判定 = `_fsm_frozen or _timed_freeze_remaining > 0`；脚本模拟 SCORED→PLAYING 时序断言剩余时长续走
- **预期结果**：判定式（或关系）+ 独立计时器可正确表达；FSM 解冻后剩余时长走完
- **影响**：决定 `set_frozen_timed` 实现与 §5.2-5 边界语义；影响 paddle.gd 冻结路径改动

### 实验 3：01_title 模式选择 UI 对 E2E theme_absent 断言的影响

- **问题**：模式选项高亮色若误用 #4a90d9 系 → `theme_absent: 4a90d9` 失败（#517 纪律）
- **方法**：按推荐色（PADDLE_NEON #00e5ff / BRICK_NEON #ff9d45）实现选项高亮 → 跑 `run-e2e-review.sh --skip-visual` L0–L2 + 截图人工核对 01_title
- **预期结果**：theme_absent 通过；若色数断言波动 → 高亮改 modulate 透明度而非新增色相（零新增色）
- **影响**：决定模式 UI 视觉实现（色值/透明度），影响 ui_start_menu.tscn 与 e2e_shots.json（如需）

---

## 8. 延续上下文

### 8.1 系统现状（plan agent 无需重扫的关键事实）

- **title/FSM**：`ui_start_menu.tscn`（CanvasLayer layer=1，CenterContainer/VBoxContainer 三段：TitleLabel/PromptLabel/VersionLabel）；`start_menu.gd` 无输入处理（FSM `_input()` 收 ui_accept，#294）；FSM `enter_state(SERVING)` 调 `GameManager.reset_match()` 后 1s 发球
- **挡板**：`paddle.gd` 267 行；`enum Mode { PLAYER, AI }`；`_ready()` PLAYER 分支动态绑 A/D+←/→（`if not InputMap.has_action` 守卫）；连击 #504 读 `score_changed(player_score, ai_score)` 只跟踪 player 侧；`set_paddle_width`/`magnet_enabled`/`set_frozen` 为升级/FSM 入口
- **升级**：`upgrade_defs.gd` 9 定义（6 可选 + 3 桩，`is_stub` 过滤 #526）；`upgrade_pool.gd` `get_candidates(3)` 60/30/10 先掷 + `_build_ctx` 经 `paddles` 组取首板；`upgrade_pick_ui.gd` 单游标 `ui_left/ui_right/ui_accept`，`wave_settled` 挂点 + `advance_settlement` 推进接管
- **得分**：`game_manager.gd` `add_score(winner, amount, kind)`，WIN_SCORE=21，`match_over(winner)`；`scoring_manager.gd` side 0→player/1→ai；`ball.gd` `last_toucher` "player"/"ai"
- **HUD/结算**：`game_hud.gd` 顶区 AIScoreLabel 红区（#392）；`game_over_screen.gd` `is_fail := winner=="ai"` 双分支（#391）
- **E2E**：`e2e_shots.json` `autoplay.mode=ai` 双板覆盖 AI + `01_title` theme_absent 4a90d9 + `02_midgame` press enter；`run-e2e-review.sh --skip-visual`（L3 已砍，2026-08-15）

### 8.2 移交 plan agent 的关键决策点

1. **推荐方案**（§4.5）：A/A/A + 4 debuff 卡；如 Spike 1/2/3 有意外结论，按实验影响列回退
2. **InputMap 实现**：Spike 1 定稿「增量 erase」vs「全量重建」；`p1_confirm`/`p2_confirm`/`p2_left`/`p2_right` 静态定义于 project.godot 或运行时（推荐静态定义 + 运行时按模式增删 ←/→）
3. **模式状态复位语义**：重开保留 vs 复位默认（推荐保留，§5.2-8）
4. **升级窗口等待超时**：10s 超时代选 vs 放弃（推荐超时代选，§5.3-3）
5. **显示层**：HUD 顶区「P2」文本与红区颜色保留；结算 P1/P2 胜者宣告文案（taste 域可调，机械分支本 Issue 定）
6. **测试清单**：test_local_2p 必须覆盖 §5.2 边界 1/2/3/5/8 与 §5.3-1/2（InputMap 断言、同帧锁卡、冻结互斥、幂等重建）
7. **文件域白名单**（AC8）：`ui_start_menu.tscn`、`start_menu.gd`、`game_state_machine.gd`、`game_manager.gd`、`paddle.gd`、`upgrade_defs.gd`、`upgrade_pool.gd`、`upgrade_pick_ui.gd`、`ui_upgrade_pick.tscn`、`game_hud.gd`、`game_over_screen.gd`、`constants.gd`、`project.godot`（可选）、`e2e_shots.json`（可选）、`tests/test_local_2p.gd`、`tests/run_tests.gd`、`assets/content/upgrade_pool.json`

### 8.3 主要风险

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| InputMap 运行时重建残留 → 双板同动 | Med | Spike 1 + test_local_2p 事件集断言 |
| 双游标锁定状态机复杂度（同帧/先锁） | Med | §5.2-1/2 明确裁决序；UI 置灰反馈 |
| FSM 冻结 vs 临时冻结互斥 | Med | Spike 2 + 判定式冻结（或关系） |
| E2E 01_title 断言回归 | Low | Spike 3 + 推荐色规避 #4a90d9 |
| 连击双通道污染 | Low | player_index 分流 + 既有 #504 测试扩展 |
| debuff 数值/文案品味未定稿 | Low | taste 域 #395 human-review，机械结构先行 |

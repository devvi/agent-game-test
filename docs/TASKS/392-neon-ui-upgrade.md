# Tasks: [Feature] 霓虹UI升级 (Neon HUD Upgrade)

> **Parent Issue:** #392
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Design:** docs/DESIGN/392-neon-ui-upgrade.md
> **深度:** depth/standard（涉及 9 个代码/测试文件 + 2 文档，按 #385/#386 惯例产出 TASKS 供 implement 使用）
> **所有权:** `content_ownership: mechanical` — 布局/信号/样式机制机械实现；描边粗细、投影偏移、信息条配色、底部单行 vs 左右下角 = taste-draft（human-review 定稿）

---

## Phase 1: 常量与样式工具（P0，地基）
- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): 新增 Neon HUD 常量组 —— `HUD_OUTLINE_SIZE=6`、`HUD_SHADOW_OFFSET=Vector2(2,2)`、`HUD_SHADOW_COLOR=半透明黑`、`HUD_INFO_COLOR=中性色`、`HUD_FONT_SIZE_MAIN=28`、`HUD_FONT_SIZE_SUB=20`、`HUD_TOP_BAND_TOP=12`、`HUD_TOP_BAND_BOTTOM=84`、`HUD_BOTTOM_BAND_TOP=1252`、`HUD_BOTTOM_BAND_BOTTOM=1280`、`HUD_PLACEHOLDER="—"`（DESIGN §2.1）
- [ ] Task 2 (`mini-pong/gdscripts/ui_neon_style.gd`): **新建** —— `class_name UiNeonStyle`，`static func apply(label, color, opts := {})`：font_color / font_outline_color + outline_size / font_shadow_color + shadow_offset_x/y 主题覆盖（默认取 HUD_* 常量，opts 可覆盖 outline_size）（DESIGN §3.1）

## Phase 2: GameManager 按类信号（P0）
- [ ] Task 3 (`mini-pong/gdscripts/game_manager.gd`): 新增 `signal brick_scored(side: String)` / `signal pierce_scored(side: String)`；`add_score()` 内 `_bump_count` 之后、`score_changed.emit` 之前按 kind emit（boundary 不触发）；既有信号/API 零改动（DESIGN §2.2）
- [ ] Task 4 (`mini-pong/tests/test_game_manager.gd`): 扩展 —— `brick_scored`/`pierce_scored` 信号用例（kind 触发、boundary 不触发、非法 winner 不触发、终局后不触发）（DESIGN §9 Scenario E-5/G-3）

## Phase 3: HUD 场景与脚本（P0，核心）
- [ ] Task 5 (`mini-pong/scenes/ui_game_hud.tscn`): 重排三区 —— GameHUD(CanvasLayer layer=1, visible=false) > MarginContainer(全宽 offset_right=720) > TopBand(y∈[12,84]: AITotalLabel + SubRow[AIBrickLabel/AIPierceLabel/WaveLabel/BricksLabel]) + BottomBand(y∈[1252,1280]: PlayerTotalLabel/PlayerBrickLabel/PlayerPierceLabel)；配色不散落 modulate（由脚本统一）（DESIGN §2.4）
- [ ] Task 6 (`mini-pong/gdscripts/game_hud.gd`): 重构 —— 8 个 Label 引用 + `_apply_neon()`（UiNeonStyle 套样式）+ `_connect_signals()`（GameManager 4 信号 + grid 3 信号容错 `has_signal` 守卫 + `push_warning` 一次）+ `_seed_initial()`（播种）；handlers：score_changed/brick_scored/pierce_scored/wave_started（call_deferred 回退）/brick_destroyed（即时单读 remaining_bricks）/wall_cleared（归零）/wall_generated；无 `_process`；保留节点缺失守卫与 `visible=false`（DESIGN §2.3）

## Phase 4: 主场景组装（P0）
- [ ] Task 7 (`mini-pong/scenes/Main.tscn`): 删除内联 GameHUD 子树，改为实例化 `ui_game_hud.tscn`（新增 ext_resource），节点名 `GameHUD` 不变 + `layer=1` 显式覆盖（DESIGN §2.5）

## Phase 5: 测试改造与验收（P0）
- [ ] Task 8 (`mini-pong/tests/test_hud.gd`): **新建** —— mock BreakoutGrid（#414 契约：brick_destroyed/wall_cleared/wall_generated 信号 + remaining_bricks 属性 + 调用记录）；§9 场景 A–F 可运行实现（霓虹样式/分区配色/波次与剩余砖数/安全区/信号驱动/容错守卫）
- [ ] Task 9 (`mini-pong/tests/run_tests.gd`): 注册 `test_hud.gd`
- [ ] Task 10 (`mini-pong/tests/test_ui_system.gd`): 同步 TC6（三区 Label 路径 + 8 Label 存在 + 初值文本）、TC9（`_on_score_changed` 新文本格式）、TC15（layer==1 不变）
- [ ] Task 11 (`mini-pong/tests/test_main_scene.gd`): TC1-11（GameHUD 存在）不变；TC20-11（MarginContainer offset_right==720）语义保留
- [ ] Task 12 (验收): `godot --headless --script tests/run_tests.gd` 全绿（基线 1487 用例 + 新用例，既有 16+ 套件零回归）

## Phase 6: Spike 实测（P1，视觉兜底）
- [ ] Task 13 (Spike 1): E2E `02_midgame` 截图 4 重断言（非黑/色数/主题色 4a90d9/帧间差异）实测通过；必要时调 shot 参数（settle_frames/阈值），**不删 HUD 内容**
- [ ] Task 14 (Spike 2): 720×1280 实机截图叠加球道/砖墙参考线，逐区测量与挡板/砖墙交集；底部单行容纳不下则切左右下角双子区布局（taste 决策，锚点/字号微调）
- [ ] Task 15 (文档): `docs/DESIGN/384-breakout-grid-brick-wall.md` 附注 `wall_generated` 契约增补（DESIGN #392 §3.3）—— 本 Task 随实现 PR 一并合入（或实现前先合入均可）

## 明确不做（范围边界）
- ❌ `mini-pong/gdscripts/game_state_machine.gd` / `start_menu.gd`（GameHUD 节点名不变，零改动）
- ❌ `mini-pong/gdscripts/score_flash.gd`（L2 反馈层独立，零改动；视觉叠加由 Spike 1 截图确认）
- ❌ BreakoutGrid 实现与接线（#384/#393；本 Issue 只容错消费）
- ❌ 计分规则/波次状态机（#385/#386 既有，只消费）
- ❌ `docs/GAME_DESIGN/16-UI-SYSTEM.md`（实现 PR merge 后由 review agent 增量更新）
- ❌ 任何第三方字体/资产（开源优先调研结论：无可复用方案，PRD §1.5）
- ❌ 写 runnable 测试文件于本 PR（测试归 implement PR）

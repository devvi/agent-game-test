# DESIGN: [Feature] title 支持游戏模式选择，支持本地双人对战

> **Parent Issue:** #543
> **Agent:** game-plan-agent
> **Date:** 2026-08-18
> **Approach:** A + A + A + 4 debuff 卡（PRD §4 推荐组合逐项确认采纳）——模式选择 UI = §4.1 方案 A（StartMenu 内嵌选项区，默认单人）；双人输入拆分 = §4.2 方案 A（运行时按模式重建 InputMap，增量 erase）；双人升级交互 = §4.3 方案 A（同屏 3 卡 + 双游标 + 先锁后选）；害对手升级 = §4.4 4 卡 debuff v1（压缩/冻结/迟缓/紊乱）
> **Reference PRD:** docs/PRD/543-mode-select-local-2p.md（research PR #545 已合并 2026-08-17）
> **上游方案:** docs/PLAN-rogue-pong.md §1「对打」主线——本 Issue 在既有 Pong×Breakout 对打 + 肉鸽三选一升级之上扩展**本地双人对战**形态，不改变波次/升级/得分机制本身
> **所有权:** `content_ownership: mixed`——模式状态机/输入拆分/debuff 机械结构/目标解析契约/双游标裁决序 = mechanical（可测）；debuff 卡名/短句/数值（shrink/freeze/slow/reverse 的幅度与时长）= taste-draft 占位（本 DESIGN 给占位值，走 #395 域 human-review 定稿，调参零代码改动）
> **深度:** depth/standard（Issue 无 depth/ 标签，PRD 按 #392/#449/#464/#476/#527 惯例判 standard）——**产出 DESIGN + TASKS 两份文档**（文件域白名单 17 文件 ≥10 阈值，达 skill standard TASKS 要求）；测试仅描述不写代码（plan 阶段红线）
> **并行上下文:** #527（visual-enrichment）已合入但实现未开始；#529（波次触发）DESIGN 已合入。本 Issue 文件域（§7 白名单）与二者无交集（constants.gd 只追加新区、既有区逐字节不动——#448/#449/#450/#464 先例）；`BrickVariant`/`SPECIAL_BRICK_*` 与本 Issue `GAME_MODE_*`/`P2_*`/`DEBUFF_*` 均落在 constants.gd 不同新区，implement 阶段按合入顺序追加即可

---

## 1. 架构总览

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280，Forward+）目前只有单人模式：title 单入口「按 SPACE 开始」（#292/#508）、玩家挡板 A/D+←/→ 对战 AI（#290/#383）、升级池 6 卡全为自利 buff（#387/#388）。本设计按 PRD 推荐，把「AI 对手」抽象为「P2 玩家」：title 增加模式选择（默认单人），双人模式双板均 PLAYER 模式并分键，升级三选一增加害对手 debuff 卡与双游标同屏博弈：

```
                              ★ Issue #543 本地双人对战（本 DESIGN）
        ┌───────────────────────────────┴───────────────────────────────┐
        │ Title 侧（模式选择，StartMenu 内嵌）         │ 开局侧（模式落盘，FSM/GameManager）        │
        ▼                                          ▼
  ui_start_menu.tscn（改）                     game_state_machine.gd（改）
  VBoxContainer 插入 ModeSelect 区               MENU 态 ui_accept → SERVING 前
  （单人模式(AI 对战)/本地双人对战 两行）            GameManager.set_game_mode(StartMenu.selected)
        │  ↑/↓ 切换 + 高亮 Tween（150–300ms）        │
        ▼                                          ▼
  start_menu.gd（改）                           enter_state(SERVING)（改）
  _mode_index + 高亮 + 写入 GameManager            reset_match() 后按 game_mode 配置双板：
        │                                          ├─ SINGLE: AIPaddle.mode=AI（现状逐字节不变）
        └──────────► GameManager.game_mode ────────┤─ LOCAL_2P: AIPaddle.mode=PLAYER, player_index=1
                                                    │            PlayerPaddle.player_index=0
                                                    └─ InputMap 按模式重建（增量 erase ←/→，Spike 1 定稿）

  2P 升级流（wave_settled → 双确认 → 应用）：
  wave_controller._begin_settlement() → GameManager.settle_wave() → wave_settled
        │
        ▼
  UpgradePickUI.open(wave_index)（改）
    ├─ UpgradePool.get_candidates(3, allow_opponent=true)   ← 2P 才含 debuff
    │     ├─ 自利卡 6 种（target=self，稀有度权重 60/30/10 不变）
    │     └─ debuff 卡 ≥3 种（target=opponent：shrink/freeze/slow/reverse）
    ├─ 双游标（P1: A/D+E；P2: ←/→+右Shift，PROCESS_MODE_ALWAYS 下树级暂停仍响应）
    │     ├─ 先确认者锁定卡片（对方置灰）
    │     └─ 后确认者从剩余卡选 → 双方 reveal 完成 → close()
    └─ _advance_settlement() → wave_controller.advance_settlement() → 下一波（#388 接管不变）

  升级目标解析（2P）：
  UpgradePool._build_ctx(player_index)
    ├─ self_paddle     = paddles 组内 player_index 匹配的挡板
    ├─ opponent_paddle = paddles 组内另一挡板（2P 下恒为 PLAYER 模式挡板）
    ├─ paddle          = self_paddle（回退键——既有效果/测试零改动）
    └─ ball / grid     = 既有惰性解析（balls / breakout_grids 组）
```

### 设计哲学

1. **对手语义复用，机制零重构**：#385 双得分制 winner `"player"/"ai"` 字符串**内部不动**——2P 下 P2 直接映射 `"ai"` 侧（HUD/结算/连击/拆砖分全链路自动正确）；`ball.last_toucher`、`scoring_manager`、`wave_controller` 零改动（PRD §3.3 核查结论，本设计复核一致）。
2. **默认单人 = 逐字节不回归**：`game_mode` 默认 `SINGLE`；title 默认选中单人；SPACE 直开路径与现状一致（E2E autoplay 兼容）；`paddle.gd` 既有 `if not InputMap.has_action` 守卫保留，单人路径绑定集合不变。
3. **分键 = 增量 erase，不重造输入系统**：`paddle_left/paddle_right` 的 A/D 事件保留，2P 下仅 erase ←/→ 事件到 `p2_left/p2_right`（增量式，Spike 1 定稿；失败回退全量重建）。E/右Shift 当前零占用（源码 grep 验证），新增 action 无冲突。
4. **双游标 = 单窗口单挂点**：#388 的 wave_settled 挂点与 `advance_settlement` 推进接管**不改**——双方在同一个暂停窗口内完成选择，波次契约零破坏。
5. **debuff = 挡板属性同构**：缩板/冻结/减速/方向反转全部落在 `paddle.gd` 已有属性面（宽度/速度/冻结/输入轴），与 #387 slow_time 的 `set_speed_scale_timed` 同构；单人池经 `target` 过滤天然隔离（#526 桩过滤纪律）。
6. **视觉纪律**：模式高亮/双游标指示色用 `PADDLE_NEON #00e5ff`/`BRICK_NEON #ff9d45` 系，全部避开 `#4a90d9`（tol 32，E2E 01_title theme_absent 保护，#517 纪律）；动效 Tween 150–300ms（PLAN §3.3），不弹跳不花哨。
7. **headless / 无 autoload 容错**：InputMap 操作前 `has_action` 守卫；`GameManager`/`StartMenu` 引用 `get_node_or_null`/组寻址容错；debuff 目标判空 push_warning + no-op（#387 既有风格）。

### PRD 方案确认

| 决策点 | PRD 推荐 | 本设计 | 说明 |
|--------|---------|--------|------|
| 模式选择 UI | §4.1 方案 A（StartMenu 内嵌，默认单人） | ✅ 采纳 | 单场景常驻架构零场景切换；#508 世界隐藏结构性兼容；E2E autoplay 零改动 |
| 输入拆分 | §4.2 方案 A（运行时重建 InputMap，增量 erase） | ✅ 采纳 | 唯一真正隔离 P1/P2 键位（AC3）；单人路径零回归 |
| 双人升级交互 | §4.3 方案 A（同屏 3 卡 + 双游标 + 先锁后选） | ✅ 采纳 | 单窗口单挂点，波次契约零破坏；「抢卡」博弈贴合害对手设计意图 |
| 害对手升级 | §4.4 4 卡 debuff v1 | ✅ 采纳 | 与既有挡板属性同构，实现风险低；数值 taste 占位 #395 定稿 |
| 模式状态 | GameManager 承载 `game_mode` | ✅ 采纳 | GameManager 已是全局状态持有者（得分/波次/终局），职责匹配 |
| 显示层 | HUD「P2」/结算 P1·P2 胜者宣告 | ✅ 采纳 | 内部 winner 字符串不动，仅显示层分支 |

---

## 2. 现状核实（plan agent 已对照源码确认，2026-08-18）

PRD §8.1 已给出「无需重扫」事实清单；本设计对**关键断言逐条对照源码复核**，发现 1 处 PRD 未覆盖的架构事实（FSM 已持有双板 NodePath），并确认全部其余断言成立：

| PRD 断言 | 实际代码（对照结果） | 设计裁决 |
|---------|--------------------|---------|
| `paddle.gd` 有 `enum Mode { PLAYER=0, AI=1 }` 与完整 PLAYER/AI 双路径 | ✅ 成立（paddle.gd:11；`_ready()` PLAYER 分支动态绑 A/←→paddle_left、D/→→paddle_right，`if not InputMap.has_action` 守卫；`_process` 读 `Input.is_action_pressed`） | 新增 `player_index` 为增量；PLAYER 绑定逻辑按索引分流 |
| 输入绑定是运行时的，`project.godot` 无 `[input]` 段 | ✅ 成立（project.godot grep 无 `[input]`/paddle action） | `p1_confirm`/`p2_confirm`/`p2_left`/`p2_right` 静态定义于 project.godot + 运行时增删 ←/→（Spike 1 定稿） |
| 升级目标解析只认第一个挡板（`get_first_node_in_group("paddles")`） | ✅ 成立（upgrade_pool.gd:160 `paddle_ref`；ctx 另有 ball_ref/grid_ref） | `_build_ctx(player_index)` 扩展 `self_paddle`/`opponent_paddle`；`paddle` 键 = self_paddle 回退 |
| 升级定义 9 个（6 可选 + 3 桩过滤）无 target 字段 | ✅ 成立（upgrade_defs.gd:9 定义；`is_stub` 过滤；effect 为 Callable） | 既有 6 卡加 `target:"self"`（默认）；新增 4 debuff 卡 `target:"opponent"` |
| 升级 UI 单焦点环 `ui_left/ui_right/ui_accept`、`PROCESS_MODE_ALWAYS` | ✅ 成立（upgrade_pick_ui.gd:24 `_focus_index`、:36 `process_mode = PROCESS_MODE_ALWAYS`、:65 `_unhandled_input`） | 2P 分支新增 P1/P2 双 focus + locked 集合；SINGLE 分支代码路径不动 |
| `ui_accept` 是 SPACE/Enter；E/右Shift 未被占用 | ✅ 成立（FSM `_input` 消费 ui_accept；grep 无 E/右Shift 绑定） | 新增 `p1_confirm`(E)/`p2_confirm`(Shift) 零冲突 |
| title 屏 `ui_start_menu.tscn` 为 CanvasLayer layer=1，VBox 三段（Title/Prompt/Version） | ✅ 成立（scenes/ui_start_menu.tscn：CanvasLayer layer=1 → CenterContainer → VBoxContainer → TitleLabel「PONG://21」/PromptLabel「按 SPACE 开始」/VersionLabel） | ModeSelect 区插入 TitleLabel 与 PromptLabel 之间 |
| FSM MENU 态 ui_accept 直接 `transition_to(SERVING)`，SERVING 入口 `reset_match()` | ✅ 成立（game_state_machine.gd:71-79 MENU 分支 + `_transition_lock`；:111-117 SERVING 入口 reset_match） | MENU→SERVING 前写 game_mode（StartMenu 已随切换写入，FSM 仅读取确认） |
| 连击（#504）只认 PLAYER 模式 + player_score | ✅ 成立（paddle.gd:63 `_last_player_score`、:122 `_on_score_changed(player_score, _ai_score)`） | 按 `player_index` 选分数通道：P2 看 ai_score |
| HUD 顶区「AI 红区」/结算 `is_fail := winner=="ai"` | ✅ 成立（game_hud.gd:124 `"AI: "`；game_over_screen.gd:58 `is_fail := winner == "ai"`、TEXT_PLAYER_WIN/TEXT_AI_WIN） | 2P 显示层分支：HUD「P2: 」、结算 P1/P2 WIN（胜者分支） |
| E2E `autoplay.mode=ai` 双板覆盖 mode=1；01_title `theme_absent: 4a90d9` | ✅ 成立（e2e_shots.json autoplay.tweaks 覆盖 PlayerPaddle/AIPaddle mode=1；01_title state=MENU + theme_absent） | 默认 SINGLE + SPACE 直开 → autoplay 兼容；模式 UI 色避 #4a90d9 |
| **（PRD 未提及）FSM 已持有双板 NodePath** | ✅ 新发现（game_state_machine.gd:104-110 `start_menu`/`player_paddle`/`ai_paddle` NodePath export） | FSM 是 2P 挡板配置的天然落点：`enter_state(SERVING)` 按 game_mode 调 `GameManager.apply_mode_to_paddles()` 或直接配置双板 |

**结论**：PRD 全部关键断言成立，无需要推翻的设计假设；唯一新增架构事实（FSM 持双板 NodePath）使模式落盘路径更短——无需新场景/新节点。

---

## 3. 新组件 — 详细设计

本设计无新 .tscn 场景、无新 .gd 文件（`test_local_2p.gd` 测试套件除外，属 implement 阶段）。所有新增能力以**字段/方法/状态机**形式落在既有组件内。

### 3.1 ModeSelect 模式选择区（ui_start_menu.tscn + start_menu.gd 内新增）

- **位置**：`scenes/ui_start_menu.tscn` 的 `CenterContainer/VBoxContainer` 中，TitleLabel 与 PromptLabel 之间插入 ModeSelect 区（VBoxContainer 子节点，含两行 Label + 高亮指示）。
- **节点结构**：

```
StartMenu (CanvasLayer, layer=1)
└── CenterContainer
    └── VBoxContainer
        ├── TitleLabel            （现状不动）
        ├── ModeSelectVBox        （新增，间距 8，字号 22）
        │   ├── ModeOption1       Label「单人模式（AI 对战）」
        │   └── ModeOption2       Label「本地双人对战」
        ├── PromptLabel           「按 SPACE 开始」（现状不动）
        └── VersionLabel          （现状不动）
```

- **状态属性**（start_menu.gd）：
  - `var _mode_index: int = 0`（0 = SINGLE，默认；1 = LOCAL_2P）
  - `var _mode_labels: Array[Label] = []`（`@onready` 收集 ModeOption1/2）
  - `var _mode_tween: Tween = null`（高亮切换动画句柄，复用 `_kill_tween`）
- **关键方法**：
  - `func get_selected_mode() -> int`：返回 `_mode_index`（FSM/GameManager 读取入口）
  - `func _unhandled_input(event) -> void`：仅当 `visible`（MENU 态）且 GameManager 可用时，消费 `ui_up`/`ui_down`（↑/↓，W/S 由 Godot 内建 ui_up/ui_down 默认映射覆盖）→ `_mode_index = posmod(_mode_index ± 1, 2)` → `_apply_mode_highlight()` → `GameManager.set_game_mode(_mode_index)`；**不消费 ui_accept**（FSM 既有 MENU 分支继续处理）
  - `func _apply_mode_highlight() -> void`：选中行 `modulate = PADDLE_NEON`（#00e5ff）+ 字号 24；未选中行 `modulate = 0.4 透明度` + 字号 20；切换 Tween 150–300ms（不弹跳）
  - `func _ready()` 扩展：收集 `_mode_labels`、`_apply_mode_highlight()` 初始化（默认选中单人）
  - `func show_menu()/hide_menu()` 扩展：show 时重绘高亮（保留上次选择，§6-8 决策）；hide 时 `_kill_tween`
- **集成**：GameManager 写入（见 §3.2）；FSM 无需感知选项 UI——mode 已在切换时落盘，SPACE 直开即用当前值（PRD §5.2-6 默认单人路径）。

### 3.2 GameMode 模式状态（game_manager.gd 内新增）

- **文件**：`gdscripts/game_manager.gd`
- **状态属性**：
  - `enum GameMode { SINGLE = 0, LOCAL_2P = 1 }`（与 StartMenu `_mode_index` 同值对齐）
  - `var game_mode: GameMode = GameMode.SINGLE`（默认单人；`reset_match()` 不触碰——重开保留选择，§6-8）
  - `const MODE_P2_TOP_INDEX: int = 1`（顶侧挡板 player_index）
- **关键方法**：
  - `func set_game_mode(mode: int) -> void`：`game_mode = mode as GameMode`（越界值 clamp 到 SINGLE，防御性）
  - `func get_game_mode() -> int`：返回 `game_mode`
  - `func apply_mode_to_paddles() -> void`：按 `game_mode` 配置 paddles 组（**FSM enter_state(SERVING) 调用**）：
    - SINGLE：`AIPaddle.mode = Mode.AI`（回写场景默认值 1，幂等）；`PlayerPaddle.mode = Mode.PLAYER, player_index = 0`（默认值，幂等）；InputMap 恢复单人绑定（§3.3）
    - LOCAL_2P：`AIPaddle.mode = Mode.PLAYER, player_index = MODE_P2_TOP_INDEX`；`PlayerPaddle.mode = Mode.PLAYER, player_index = 0`；InputMap 切换 2P 绑定（§3.3）
    - 实现注记：paddles 组内按 `player_index` 匹配；组空/节点失效 → push_warning + 跳过（headless 容错先例）。FSM 持双板 NodePath（§2 新发现），`apply_mode_to_paddles` 也可由 FSM 直接传双板引用，implement 二选一（推荐 GameManager 内组寻址，单点职责）

### 3.3 InputMap 分键重建器（paddle.gd + project.godot）

- **静态 action 定义**（`mini-pong/project.godot` 新增 `[input]` 段，仅新增 4 个 action，不动任何既有项）：
  - `p1_confirm`：Key E
  - `p2_confirm`：Key Shift（Godot Key 枚举无独立 RSHIFT keycode，左右 Shift 同为 KEY_SHIFT；物理右 Shift 键触发——设计采用 KEY_SHIFT 绑定，文档注明，严格左右区分留作未来增强）
  - `p2_left`：Key ←
  - `p2_right`：Key →
- **运行时绑定策略**（paddle.gd `_ready()` + GameManager 模式切换钩子）：

| 模式 | paddle_left | paddle_right | p2_left | p2_right | p1_confirm | p2_confirm |
|------|------------|-------------|---------|----------|-----------|-----------|
| SINGLE | A + ← | D + → | — | — | — | — |
| LOCAL_2P | A | D | ← | → | E | 右Shift |

- **关键方法**（paddle.gd 新增静态工具）：
  - `static func rebind_for_mode(mode: int) -> void`：幂等重建——
    - 前置：确保 `p2_left/p2_right/p1_confirm/p2_confirm` 存在（静态定义后恒存在；`has_action` 守卫 + `action_add_event` 兜底）
    - SINGLE：确保 `paddle_left` 含 A+←、`paddle_right` 含 D+→（现状守卫路径，`if not InputMap.has_action` 保留）；从 `p2_left/p2_right` 移除 ←/→（若存在，事件级比对后 erase，幂等）
    - LOCAL_2P：从 `paddle_left` erase ←、`paddle_right` erase →（事件级比对，不存在则 no-op）；确保 `p2_left` 含 ←、`p2_right` 含 →
    - 重复开局幂等：每次 MENU→SERVING 前调用（SINGLE 先清后建语义），erase 全部为「比对存在才 erase」
  - `paddle.gd _ready()` PLAYER 分支：`player_index == 0` → 读 `paddle_left/paddle_right`（现状）；`player_index == 1` → 读 `p2_left/p2_right`（新增分支）；AI 分支不变
  - `_process()` 输入读取：按 `player_index` 选 action 对（`_input_axis()` 辅助方法，读 `Input.get_axis(left_action, right_action)`），`_input_invert_remaining > 0` 时取反
- **Spike 1 交接**：增量 erase 的 headless 安全性由 implement Phase 0 验证（§10）；若 `action_erase_event` 有竞态 → 回退全量重建（先 `remove_action` 再 `add_action`），改动面仅限 `rebind_for_mode` 内部。

### 3.4 挡板定时状态（paddle.gd 内新增）

与 #387 slow_time 的 `set_speed_scale_timed` 同构的三套定时状态 + 一个即时状态：

- **状态属性**（paddle.gd 新增）：
  - `var _timed_freeze_remaining: float = 0.0`（freeze_opponent 临时冻结）
  - `var _speed_scale: float = 1.0`、`var _speed_scale_remaining: float = 0.0`（slow_opponent 减速）
  - `var _input_invert_remaining: float = 0.0`（reverse_opponent 方向反转）
- **关键方法**：
  - `func set_frozen_timed(duration: float) -> void`：`_timed_freeze_remaining = duration`（重复施加取 max，防覆盖）
  - `func set_speed_scale_timed(scale: float, duration: float) -> void`：`_speed_scale = scale`、`_speed_scale_remaining = duration`
  - `func set_input_invert_timed(duration: float) -> void`：`_input_invert_remaining = duration`
  - `func is_effectively_frozen() -> bool`：`return _fsm_frozen or _timed_freeze_remaining > 0.0`（**判定式或关系**，Spike 2 定稿：FSM 全局冻结优先，临时冻结计时独立走完，二者互不覆盖）
  - `_process(delta)` 扩展：
    - 冻结判定改用 `is_effectively_frozen()`（`_fsm_frozen` 由既有 `set_frozen` 维护，逻辑不动）
    - 三个定时器递减：`_timed_freeze_remaining = max(0, _timed_freeze_remaining - delta)` 等
    - 移动速度乘以 `_speed_scale`（`PADDLE_SPEED * _speed_scale`，AI 模式不适用——2P 下 opponent 恒为 PLAYER，天然隔离）
    - 输入轴读取后按 `_input_invert_remaining > 0` 取反
- **可见反馈**（#526 纪律）：debuff 生效期间对手挡板侧触发可见效果（颜色闪变/边框图标），色值避开 #4a90d9，taste 域 #395 定稿（机械钩子本 Issue 定：`_on_debuff_applied` 信号或 modulate 切换，implement 选其一）。

### 3.5 双游标升级状态机（upgrade_pick_ui.gd 内新增 2P 分支）

- **状态属性**（新增）：
  - `var _p1_focus_index: int = 0`、`var _p2_focus_index: int = 0`（双游标焦点）
  - `var _locked_cards: Array[int] = []`（已确认锁定的卡下标；对方不可选）
  - `var _p1_confirmed: bool = false`、`var _p2_confirmed: bool = false`
  - `var _confirm_timeout: float = 0.0`（10s 等待超时，CONSTS 占位 `UPGRADE_2P_CONFIRM_TIMEOUT: float = 10.0`）
  - `var _is_2p: bool = false`（open 时按 `GameManager.get_game_mode() == LOCAL_2P` 判定）
- **关键方法**：
  - `open(wave_index)` 扩展：`_is_2p` 判定；2P 下 `_p1_focus_index = _p2_focus_index = 0`、locked/confirmed 清空、`_confirm_timeout = CONSTS.UPGRADE_2P_CONFIRM_TIMEOUT`；候选池 = `UpgradePool.get_candidates(3, allow_opponent=_is_2p)`；单游标路径（`_focus_index` + ui_left/ui_right/ui_accept）在 `_is_2p == false` 时原样保留
  - `_unhandled_input(event)` 扩展：`_is_2p` 分支——
    - P1：`p1_left/p1_right`（A/D）移动 `_p1_focus_index`（posmod 循环）；`p1_confirm`（E）→ `_confirm_2p(0)`
    - P2：`p2_left/p2_right`（←/→）移动 `_p2_focus_index`；`p2_confirm`（Shift）→ `_confirm_2p(1)`
    - **同帧裁决序**：P1 先处理、P2 后处理（player_index 顺序，确定性；§6-2）
  - `func _confirm_2p(player_index: int) -> void`：
    - 目标卡 = 对应焦点；若卡在 `_locked_cards` → 该玩家收到「已锁」提示（卡片置灰闪动），不锁定不 apply
    - 否则：`UpgradePool.apply(id, player_index)` → 卡加入 `_locked_cards` + 对另一玩家置灰 + 该玩家侧 reveal
    - 双方确认完成 → `_finish_2p()`；单方完成 → 等另一方 + 超时计时
  - `func _process(delta)` 扩展：`_is_2p` 且单方确认后 `_confirm_timeout -= delta`；归零 → 未确认方自动以剩余卡中随机一张代选（`UpgradePool.apply(remaining_id, player_index)`，§6-3 决策：超时代选保持节奏）→ `_finish_2p()`
  - `func _finish_2p() -> void`：双方 reveal 完成后统一 `close()` → `_advance_settlement()`（#388 接管路径不变）
  - `_render_candidates()`/`_apply_focus_visual()` 扩展：2P 下每卡渲染 P1/P2 双焦点指示（卡左下/右下角标，PADDLE_NEON/BRICK_NEON 色）；locked 卡对未确认方显示置灰
- **挂起保护**：单方确认后窗口仍在 `PROCESS_MODE_ALWAYS` 下运行，超时代选保证窗口必然关闭（§6-3）。

### 3.6 debuff 升级定义（upgrade_defs.gd + upgrade_pool.gd）

- **target 字段**：`definitions()` 每个定义新增 `"target": "self"`（既有 6 卡显式标注，默认值兜底）；4 张 debuff 卡 `"target": "opponent"`。
- **新增 4 卡**（数值 taste 占位，命名 #395 定稿）：

| id | 工作名 | 稀有度 | max_stacks | 效果（占位数值） | 回调 |
|----|-------|--------|-----------|-----------------|------|
| `shrink_opponent` | 压缩 | COMMON | 2 | 对手挡板宽度 -30%（对基数减算） | `opponent_paddle.set_paddle_width(w * 0.7)`（复用 #387 入口反向） |
| `freeze_opponent` | 冻结 | RARE | 1 | 对手挡板冻结 1.5s | `opponent_paddle.set_frozen_timed(1.5)`（§3.4，与 FSM 冻结判定式互斥） |
| `slow_opponent` | 迟缓 | RARE | 1 | 对手挡板速度 -25% 持续 8s | `opponent_paddle.set_speed_scale_timed(0.75, 8.0)`（#387 同构） |
| `reverse_opponent` | 紊乱 | RARE | 1 | 对手左右方向反转 3s | `opponent_paddle.set_input_invert_timed(3.0)`（仅 PLAYER 模式有意义，2P 专用） |

- **回调签名**：`_effect_shrink_opponent(ctx: Dictionary) -> void` 等；效果入口先判空 `ctx.get("opponent_paddle")` → 无则 `push_warning + return`（#387 判空风格）；单人不进池故无 AI 目标路径。
- **upgrade_pool.gd 扩展**：
  - `func get_candidates(n: int = CONSTS.UPGRADE_CANDIDATE_COUNT, allow_opponent: bool = false) -> Array`：候选过滤追加 `if not allow_opponent and d.get("target", "self") == "opponent": continue`；单人调用点（`get_candidates(3)`）默认值 false → 单人池行为逐字节不变（#526 纪律）
  - `func apply(upgrade_id: String, player_index: int = 0) -> bool`：签名向后兼容（默认 0）；`_build_ctx(player_index)` 传入
  - `func _build_ctx(player_index: int = 0) -> Dictionary`：paddles 组内按 `player_index` 解析 `self_paddle`（无匹配/单板 → 取第一个，回退现状）；`opponent_paddle` = 组内另一挡板（无 → null）；`paddle` 键 = `self_paddle`（既有效果/测试零回归）
  - `rarity_from_roll` 纯函数不动（60/30/10 权重天然覆盖新增卡）
- **upgrade_pool.json**：新增 4 条 debuff 卡条目（`draft: true`，走 #395 human-review 定稿显示文案）。

---

## 4. 既有组件修改

### 4.1 文件清单

| 文件 | 改动 | 动机 |
|------|------|------|
| `scenes/ui_start_menu.tscn` | TitleLabel/PromptLabel 间插入 ModeSelectVBox（2 行选项 Label） | AC1 模式选择入口 |
| `gdscripts/start_menu.gd` | `_mode_index` + `_unhandled_input`(ui_up/ui_down) + 高亮 + `get_selected_mode()` + GameManager 写入 | AC1 模式切换与透传 |
| `gdscripts/game_state_machine.gd` | MENU→SERVING 确认 game_mode 已配置；`enter_state(SERVING)` 调 `GameManager.apply_mode_to_paddles()` | AC1/AC3 模式落盘与双板配置 |
| `gdscripts/game_manager.gd` | `enum GameMode` + `game_mode` + `set/get_game_mode` + `apply_mode_to_paddles()` | 模式全局状态 |
| `gdscripts/paddle.gd` | `@export player_index` + 按索引绑定/读取输入 + 三套定时状态 + `rebind_for_mode` 静态工具 + 连击按索引分流 | AC2/AC3/AC4 分键与 debuff 载体 |
| `gdscripts/upgrade_defs.gd` | 既有 6 卡 `target:"self"` + 4 debuff 定义（target:"opponent"） | AC4 害对手升级 |
| `gdscripts/upgrade_pool.gd` | `get_candidates(n, allow_opponent)` + `apply(id, player_index)` + `_build_ctx(player_index)` 双目标 | AC4 目标解析契约 |
| `gdscripts/upgrade_pick_ui.gd` | 2P 双游标状态机 + 锁定 + 超时代选 | AC2/AC3 双人确认 |
| `scenes/ui_upgrade_pick.tscn` | 卡左下/右下角标节点（可选：P1/P2 焦点指示 Label ×2） | 双游标可见性 |
| `gdscripts/game_hud.gd` | 2P 下顶区 `"AI: "` → `"P2: "`（红区颜色保留） | AC5 显示语义 |
| `gdscripts/game_over_screen.gd` | 2P 下 winner 分支：`"player"`→「P1 WIN!」、`"ai"`→「P2 WIN!」（不走失败分支） | AC5 结算语义 |
| `gdscripts/constants.gd` | 追加新区：`GAME_MODE_*`、`P2_*` action 名、`DEBUFF_*` 占位、`UPGRADE_2P_CONFIRM_TIMEOUT`；既有区逐字节不动 | 常量单一来源 |
| `mini-pong/project.godot` | 新增 `[input]` 段：`p1_confirm`(E)/`p2_confirm`(Shift)/`p2_left`(←)/`p2_right`(→) | 静态 action 定义 |
| `mini-pong/e2e_shots.json` | 可选：01_title 增补模式选择 UI 存在性断言（默认单人态，theme_absent 保持） | AC7 验证 |
| `mini-pong/assets/content/upgrade_pool.json` | 新增 4 debuff 条目（`draft: true`） | AC4 显示文案（taste 域） |
| `mini-pong/tests/test_local_2p.gd` | **新增**测试套件（§9 场景 A–I） | AC6 测试 |
| `mini-pong/tests/run_tests.gd` | 注册 test_local_2p | AC6 套件接入 |

### 4.2 关键改动伪代码

**game_state_machine.gd**（MENU→SERVING + 双板配置）：

```gdscript
# _input() MENU 分支（现状）之后追加（改动最小化）：
#   State.MENU: transition_to(State.SERVING) 前无需额外代码——
#   StartMenu 切换时已写 GameManager.game_mode（§3.1）；此处仅防御性确认：
if current_state == State.MENU and GameManager != null and GameManager.has_method("get_game_mode"):
    pass  # 模式已落盘；SPACE 直开即用当前值

# enter_state(SERVING) 内 reset_match() 之后追加：
if GameManager != null and GameManager.has_method("apply_mode_to_paddles"):
    GameManager.apply_mode_to_paddles()   # 按 game_mode 配置双板 + InputMap 重建（§3.2/§3.3）
```

**paddle.gd**（player_index 分流 + 定时状态核心）：

```gdscript
@export var player_index: int = 0   # 0 = P1（底侧，默认，兼容既有场景/测试）

# _ready() PLAYER 分支改：按索引选 action 对
var left_action := "paddle_left" if player_index == 0 else "p2_left"
var right_action := "paddle_right" if player_index == 0 else "p2_right"
# 绑定逻辑保留现状守卫（if not InputMap.has_action）；action 名按索引切换

# _process() 输入读取改：
var axis := Input.get_axis(left_action, right_action)
if _input_invert_remaining > 0.0:
    axis = -axis
velocity.x = axis * CONSTS.PADDLE_SPEED * _speed_scale   # _speed_scale 默认 1.0

# 连击分流（#504 扩展）：
func _on_score_changed(player_score: int, ai_score: int) -> void:
    var my_score := player_score if player_index == 0 else ai_score
    # 既有 _last_player_score 逻辑对 my_score 执行（P2 不再错读 player 通道）

# 冻结判定改：
func is_effectively_frozen() -> bool:
    return _fsm_frozen or _timed_freeze_remaining > 0.0
```

**upgrade_pool.gd**（双目标 ctx）：

```gdscript
func _build_ctx(player_index: int = 0) -> Dictionary:
    var ctx := {}
    var paddles := get_tree().get_nodes_in_group("paddles")
    var self_paddle = null
    var opponent_paddle = null
    for p in paddles:
        if int(p.get("player_index", 0)) == player_index:
            self_paddle = p
        else:
            opponent_paddle = p   # 组内另一挡板（单板时保持 null）
    if self_paddle == null and not paddles.is_empty():
        self_paddle = paddles[0]  # 回退：无 player_index 匹配（既有测试 mock/单人）
    ctx["paddle"] = self_paddle          # 回退键（既有效果零改动）
    ctx["self_paddle"] = self_paddle
    ctx["opponent_paddle"] = opponent_paddle
    ctx["ball_ref"] = get_tree().get_first_node_in_group("balls")
    ctx["grid_ref"] = get_tree().get_first_node_in_group("breakout_grids")
    ctx["player_index"] = player_index
    return ctx
```

**upgrade_pick_ui.gd**（2P 确认裁决）：

```gdscript
func _confirm_2p(player_index: int) -> void:
    var focus := _p1_focus_index if player_index == 0 else _p2_focus_index
    if focus in _locked_cards:
        _flash_locked(focus, player_index)   # 置灰闪动提示，不 apply
        return
    var id: String = _candidates[focus].id
    UpgradePool.apply(id, player_index)      # apply(id, player_index) 新签名
    _locked_cards.append(focus)
    _set_card_locked_for_other(focus, player_index)
    _reveal_card(focus, _candidates[focus])  # 该玩家侧 reveal
    if player_index == 0: _p1_confirmed = true else: _p2_confirmed = true
    if _p1_confirmed and _p2_confirmed:
        _finish_2p()
```

**game_over_screen.gd**（2P 胜者宣告分支）：

```gdscript
func _on_match_over(winner: String) -> void:
    var is_2p := GameManager != null and GameManager.has_method("get_game_mode") \
                 and GameManager.get_game_mode() == GameManager.GameMode.LOCAL_2P
    if is_2p:
        # 双人：两侧都走「胜者宣告」分支（不复用失败文案分支）
        winner_label.visible = true
        failure_phrase_label.visible = false
        run_stats_label.visible = false
        winner_label.text = "P1 WIN!" if winner == "player" else "P2 WIN!"
        winner_label.modulate = COLOR_PLAYER if winner == "player" else CONSTS.AI_NEON_RED
        _start_winner_pulse()
        return
    # 单人路径 = 现状（is_fail := winner == "ai" 双分支，逐字节不动）
```

---

## 5. 数据流

### Flow 1：模式选择 → 开局（正常路径）

```
StartMenu._ready()
  └─ _mode_index = 0（默认 SINGLE）→ _apply_mode_highlight()（单人高亮）
玩家按 ↑/↓（ui_up/ui_down）
  └─ start_menu._unhandled_input → _mode_index = 1 → 高亮 Tween 150–300ms
       └─ GameManager.set_game_mode(1)          # 立即落盘
玩家按 SPACE（ui_accept）
  └─ FSM._input MENU 分支（_transition_lock 守卫）→ transition_to(SERVING)
       └─ enter_state(SERVING)：GameManager.reset_match()
            └─ GameManager.apply_mode_to_paddles()
                 ├─ LOCAL_2P: AIPaddle.mode=PLAYER, player_index=1
                 │            PlayerPaddle.mode=PLAYER, player_index=0
                 └─ InputMap.rebind_for_mode(LOCAL_2P)   # paddle_left 只留 A、← 移入 p2_left
1s 后 serve → PLAYING：P1 按 A/D 动底板、P2 按 ←/→ 动顶板（互不干扰）
```

### Flow 2：2P 波间升级（双确认 → 应用）

```
wave_controller._begin_settlement()（墙清空/特殊砖触发，#529 路径共用）
  └─ GameManager.settle_wave() → wave_settled.emit(wave_index)
       └─ UpgradePickUI.open(wave_index)   # _is_2p = true
            ├─ UpgradePool.get_candidates(3, allow_opponent=true)
            │     ├─ 自利卡（target=self，6 种）
            │     └─ debuff 卡（target=opponent，4 种按稀有度权重混合）
            ├─ 双游标渲染（P1 青 / P2 橙 焦点角标）
            ├─ P1: A/D 移游标 + E 确认 → _confirm_2p(0) → 锁卡 + P1 reveal
            ├─ P2: ←/→ 移游标 + Shift 确认 → _confirm_2p(1) → 锁卡 + P2 reveal
            └─ 双方完成 → _finish_2p() → close() → _advance_settlement()
                 └─ wave_controller.advance_settlement() → 下一波（#388 接管不变）
```

### Flow 3：升级目标解析（2P）

```
UpgradePool._build_ctx(player_index=1)    # P2 确认了一张 debuff
  ├─ paddles 组 = [PlayerPaddle(idx 0), AIPaddle(idx 1)]
  ├─ self_paddle     = AIPaddle（player_index 1 匹配）
  ├─ opponent_paddle = PlayerPaddle
  ├─ paddle          = AIPaddle（回退键）
  └─ 效果回调 _effect_freeze_opponent(ctx)
       └─ ctx["opponent_paddle"].set_frozen_timed(1.5)
            └─ PlayerPaddle 冻结 1.5s（is_effectively_frozen = true，FSM 解冻不影响剩余计时）
```

### Flow 4：fallback / 超时路径

```
2P 升级窗口：P1 已确认，P2 长时间未操作
  └─ _process：_confirm_timeout 10s → 0
       └─ 未确认方以剩余卡随机代选（UpgradePool.apply(remaining_id, player_index)）
            └─ _finish_2p() → 窗口关闭，节奏不挂起（§6-3）
单人误按 E/Shift：InputMap 无 p1_confirm/p2_confirm 绑定（SINGLE 下未重建）
  └─ is_action_pressed 返回 false → 无动作（has_action 守卫）
```

---

## 6. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | 2P 升级一方先确认 | 卡加入 `_locked_cards` + 对另一玩家置灰；`_confirm_2p` 前置校验 locked → 提示不 apply（PRD §5.2-1） |
| 2 | 双方同帧确认同一卡 | 帧内裁决序 = player_index 顺序（P1 先 P2 后，确定性）；后处理者收到「已锁」提示并重选（不崩溃、不双扣）（PRD §5.2-2） |
| 3 | 一方确认后另一方不确认（挂起） | 10s 超时（`UPGRADE_2P_CONFIRM_TIMEOUT` 占位）→ 未确认方剩余卡随机代选 → 窗口必然关闭（PRD §5.3-3；决策：超时代选） |
| 4 | 单人模式误按 E/右Shift | SINGLE 下 `p1_confirm/p2_confirm` 无绑定（未重建）→ `is_action_pressed` false；`has_action` 守卫兜底（PRD §5.2-3） |
| 5 | FSM 全局冻结 vs 临时冻结互斥 | `is_effectively_frozen = _fsm_frozen or _timed_freeze_remaining > 0`（或关系）；FSM 解冻后剩余时长继续走完（PRD §5.2-5，Spike 2 定稿） |
| 6 | 2P 模式 SPACE 直开（未切换选项） | 默认 `SINGLE` 直接开局，与现状一致（E2E autoplay 依赖此路径）（PRD §5.2-6） |
| 7 | debuff 卡对 AI 挡板 | 单人池 `get_candidates` 默认过滤 `target=="opponent"` → 不可见；2P 下 opponent 恒为 PLAYER 模式挡板（reverse 类对 AI 无意义，天然隔离）（PRD §5.2-7） |
| 8 | 2P 重开（GAME_OVER → MENU → SPACE） | `game_mode` 保留上次选择（推荐决策，PRD §8.2-3）；InputMap 重建幂等（事件级比对 erase，重复开局不残留） |
| 9 | 升级池耗尽 | 2P 下自利卡耗尽但 debuff 仍可出（`_available` 按 target 独立过滤）；双方耗尽 → 既有空候选静默跳过路径（#388 失败路径 1）不变（PRD §5.2-9） |
| 10 | 连击窗口跨模式 | 模式切换发生在 MENU（得分清零时机），`_last_player_score` 基准随 `reset_match()` 复位；P2 通道同语义（PRD §5.2-10） |
| 11 | InputMap 重建失败/残留 | 重建前置 `has_action` + 事件级比对；test_local_2p 断言「2P 下 A 不触发 p2 绑定、← 不在 paddle_left 事件集」（PRD §5.3-1） |
| 12 | `opponent_paddle` 解析失败（单板/测试 mock） | `_build_ctx` 判空 → debuff 效果 push_warning + no-op（#387 既有风格），不崩溃（PRD §5.3-2） |
| 13 | E2E 01_title theme_absent 回归 | 模式高亮/游标色用 PADDLE_NEON #00e5ff / BRICK_NEON #ff9d45 系（距 #4a90d9 tol 32 外）；Spike 3 实测（PRD §5.3-4） |
| 14 | 既有测试回归（paddle mock 无 player_index） | `player_index` 默认 0 + `paddle` ctx 回退键 → 既有路径不变；CI L0–L2 兜底（PRD §5.3-5） |
| 15 | 树级暂停期间挡板输入 | 升级窗口 `PROCESS_MODE_ALWAYS` 独占双游标输入；挡板 `_process` 暂停不跑——天然无冲突（PRD §5.2-4） |

---

## 7. 集成点

> **状态约定：** ⬜ = pending（资源已设计，待 implement 接线）；✅ = connected（implement agent 验证）。implement agent 必须更新本表；review agent 合并前核对全部 ⬜ 已解决或显式延后。

| 集成 | 我方组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| ModeSelect 高亮/切换 | start_menu.gd `_mode_index` | #543 | `_unhandled_input` ui_up/ui_down + Tween 高亮 | ✅ connected |
| 模式写入 | start_menu.gd → GameManager | #543 | `GameManager.set_game_mode(_mode_index)` | ✅ connected |
| 模式落盘/双板配置 | GameManager `apply_mode_to_paddles()` | #543 | FSM `enter_state(SERVING)` 调用 | ✅ connected |
| InputMap 分键 | paddle.gd `rebind_for_mode()` | #543 | `apply_mode_to_paddles` 内调用；paddle `_ready` 按索引绑定 | ✅ connected |
| 双游标输入 | upgrade_pick_ui.gd `_unhandled_input` | #543 | `p1_left/p1_right/p1_confirm`（P1）、`p2_left/p2_right/p2_confirm`（P2） | ✅ connected |
| 升级目标解析 | upgrade_pool.gd `_build_ctx(player_index)` | #543 | `self_paddle`/`opponent_paddle`/`paddle` 回退键 | ✅ connected |
| debuff 回调 | upgrade_defs.gd `_effect_*` | #543 | `ctx["opponent_paddle"].set_*_timed(...)` | ✅ connected |
| 连击分流 | paddle.gd `_on_score_changed` | #504 | 按 `player_index` 选分数通道（P2 看 ai_score） | ✅ connected |
| 结算语义 | game_over_screen.gd `_on_match_over` | #391 | 2P 分支胜者宣告（P1/P2 WIN!） | ✅ connected |
| HUD 显示 | game_hud.gd `_on_score_changed` | #392 | 2P 下 `"AI: "` → `"P2: "`（红区保留） | ✅ connected |
| 波次推进 | UpgradePickUI `_advance_settlement` → WaveController | #388 | 既有 group 寻址接管，零改动（回归验证） | ✅ connected |
| debuff 文案 | upgrade_pool.json（draft: true） | #395 | human-review 定稿显示名/短句 | ⬜ deferred |
| E2E 断言 | e2e_shots.json 01_title | #517 | 未改文件（可选）；默认单人 + SPACE 直开兼容 autoplay；模式高亮色避 #4a90d9（A2 测试固化） | ✅ connected |

---

## 8. 实现阶段

| 阶段 | 优先级 | 组件 | 估计 |
|:-----:|:------:|------|:----:|
| Phase 0 | P0 | Spike 1/2/3（§10）：InputMap 增量 erase headless 安全性、冻结互斥判定式、01_title 色断言 | 0.5 天 |
| Phase 1 | P0 | 常量区 + project.godot 静态 action（`GAME_MODE_*`/`P2_*`/`DEBUFF_*`/`UPGRADE_2P_CONFIRM_TIMEOUT`） | 0.5 天 |
| Phase 2 | P0 | GameManager 模式状态 + `apply_mode_to_paddles()`；FSM SERVING 接线 | 0.5 天 |
| Phase 3 | P0 | paddle.gd：`player_index` 分流 + `rebind_for_mode` + 三套定时状态 + 连击分流 | 1 天 |
| Phase 4 | P0 | upgrade_defs.gd target 字段 + 4 debuff 卡；upgrade_pool.gd ctx/apply/get_candidates 扩展 | 1 天 |
| Phase 5 | P0 | upgrade_pick_ui.gd 双游标状态机（锁定/同帧裁决/超时） | 1 天 |
| Phase 6 | P1 | StartMenu 模式选择 UI + HUD/结算显示分支 + upgrade_pool.json draft 条目 | 1 天 |
| Phase 7 | P0 | test_local_2p.gd（§9 场景 A–I）+ run_tests.gd 注册 + headless/回归/E2E 验证 | 1 天 |

依赖序：Phase 1 → 2 → 3/4（可并行）→ 5 → 6 → 7。总估 6–6.5 天（含 0.5 天 Spike）。

---

## 9. 测试用例描述

> 测试仅描述，不写可运行代码（plan 阶段红线）。新增套件 `mini-pong/tests/test_local_2p.gd`，注册进 `tests/run_tests.gd`。覆盖 PRD §5.2 边界 1/2/3/5/8 与 §5.3 失败路径 1/2（PRD §8.2-6 清单）+ 既有套件零回归。

### Scenario A — 模式状态机与常量（test_local_2p.gd `_test_constants` 扩展）

- **A1（机械键）**：`GameMode.SINGLE == 0`、`LOCAL_2P == 1`；`UPGRADE_2P_CONFIRM_TIMEOUT == 10.0`；`P2_*`/`p1_confirm` action 名常量存在。
- **A2（E2E theme 保护）**：模式高亮色（PADDLE_NEON #00e5ff / BRICK_NEON #ff9d45）与 PLAYER_NEON_BLUE（#4a90d9）RGB 距离 ×255 ≥ 32（同 #529 A2 模式）。
- **A3（默认单人）**：`GameManager.game_mode` 初始 == SINGLE；`StartMenu.get_selected_mode()` 初始 == 0。
- **A4（越界 clamp）**：`set_game_mode(99)` → 落回 SINGLE（防御性）。

### Scenario B — InputMap 拆分与幂等（test_local_2p.gd）

- **B1（AC3 分键隔离）**：`rebind_for_mode(LOCAL_2P)` 后断言 `paddle_left` 事件集 == {A}（不含 ←）、`paddle_right` == {D}（不含 →）、`p2_left` 含 ←、`p2_right` 含 →、`p1_confirm` 含 E、`p2_confirm` 含 Shift（PRD §5.3-1 事件级断言）。
- **B2（AC2 单人零回归）**：`rebind_for_mode(SINGLE)` 后 `paddle_left` 事件集 == {A, ←}、`paddle_right` == {D, →}（与现状绑定集合逐元素一致）。
- **B3（幂等重建）**：连续 3 轮 `SINGLE→LOCAL_2P→SINGLE` 循环后事件集无残留、无重复（重复开局不双板同动，PRD §5.2-8）。
- **B4（headless 安全）**：`--headless` 下执行上述重建无脚本错误（Spike 1 结论固化）。
- **B5（未绑定 key 读 false）**：SINGLE 下 `Input.is_action_pressed("p2_left")` == false（has_action 守卫兜底，PRD §5.2-3）。

### Scenario C — 2P 挡板配置与连击通道（test_local_2p.gd）

- **C1（AC3 双板配置）**：`apply_mode_to_paddles()` 后 AIPaddle.mode == PLAYER、player_index == 1；PlayerPaddle.mode == PLAYER、player_index == 0；SINGLE 下 AIPaddle.mode 回写 AI（场景默认值）。
- **C2（#504 连击分流）**：P2 挡板（player_index=1）收到 `score_changed(player_score+1, ai_score 不变)` → 不触发 P2 连击；`ai_score+1` → 触发（P2 看 ai_score 通道，互不污染）。
- **C3（组空容错）**：paddles 组空时 `apply_mode_to_paddles()` push_warning + 不崩溃（headless 容错）。

### Scenario D — 2P 目标解析（test_local_2p.gd，mock paddles 组）

- **D1（AC4 self/opponent）**：双板 mock（player_index 0/1）下 `_build_ctx(1)` → `self_paddle == AIPaddle`、`opponent_paddle == PlayerPaddle`、`paddle == self_paddle`（回退键）。
- **D2（回退兼容）**：无 player_index 的 mock（既有测试风格）→ `self_paddle == 组内第一个`、`opponent_paddle == null`；`paddle` 键行为与旧 `paddle_ref` 一致（既有 UpgradePool 测试零回归，PRD §5.3-2）。
- **D3（单板判空）**：单板组 → `opponent_paddle == null`；debuff 效果调用 → push_warning + no-op，不崩溃。

### Scenario E — debuff 回调与定时状态（test_local_2p.gd）

- **E1（shrink 压缩）**：`set_paddle_width(w*0.7)` 在 opponent_paddle 生效；max_stacks=2 时第三次不可选（`_is_available` 排除）。
- **E2（freeze 冻结互斥）**：`set_frozen_timed(1.5)` 后 `is_effectively_frozen() == true`；期间 `set_frozen(true)`（FSM）→ 解冻后剩余时长继续走完（或关系判定，PRD §5.2-5）。
- **E3（slow 减速）**：`set_speed_scale_timed(0.75, 8.0)` 后 `_process` 速度 ×0.75；8s 后恢复 1.0。
- **E4（reverse 反转）**：`set_input_invert_timed(3.0)` 期间按右 → 挡板左移（轴取反）；3s 后恢复正常。
- **E5（单人池隔离）**：`get_candidates(3)`（allow_opponent=false）不含任何 `target=="opponent"` 卡；`get_candidates(3, true)` 可含（#526 纪律：debuff 卡非桩、可见反馈钩子存在）。

### Scenario F — 双游标升级交互（test_local_2p.gd，模拟输入注入）

- **F1（AC2/AC3 独立游标）**：2P 窗口下 P1 按 A/D 只动 `_p1_focus_index`、P2 按 ←/→ 只动 `_p2_focus_index`（互不干扰）。
- **F2（先锁后选）**：P1 确认卡 0 → 卡 0 入 locked、对 P2 置灰；P2 确认卡 0 → 「已锁」提示 + 不 apply；P2 确认卡 1 → 成功（PRD §5.2-1）。
- **F3（同帧同卡裁决）**：同帧 P1/P2 都确认卡 1 → P1 锁定成功、P2 收到已锁（player_index 顺序裁决，PRD §5.2-2；不双扣——apply 计数 == 1）。
- **F4（超时代选）**：P1 确认后模拟 10s 无 P2 操作 → P2 自动以剩余卡随机代选 → 窗口关闭、`advance_settlement` 恰好一次（PRD §5.3-3）。
- **F5（SINGLE 回归）**：单人窗口 `ui_left/ui_right/ui_accept` 路径行为与现状一致（既有 upgrade_pick_ui 测试零回归）。

### Scenario G — HUD/结算显示（test_local_2p.gd / 文本断言）

- **G1（AC5 HUD）**：2P 下 `_on_score_changed` 后顶区标签文本 == 「P2: N」（红区颜色语义保留）；SINGLE 下 == 「AI: N」（现状）。
- **G2（AC5 结算）**：2P 下 `_on_match_over("ai")` → 「P2 WIN!」且走胜者宣告分支（failure_phrase/run_stats 隐藏）；`_on_match_over("player")` → 「P1 WIN!」。
- **G3（SINGLE 结算回归）**：SINGLE 下 `_on_match_over("ai")` → 失败文案分支（现状逐字节不变）。

### Scenario H — 回归与 E2E（AC6/AC7/AC8）

- **H1（零回归）**：run_tests.gd 全量套件全绿（FSM/挡板/升级池/升级 UI/双得分/连击等既有用例）。
- **H2（headless）**：`godot --path mini-pong --headless --quit` 无脚本错误（AC6）。
- **H3（E2E L0–L2）**：`run-e2e-review.sh --skip-visual` → 01_title MENU 态 + theme_absent 4a90d9 保持（模式 UI 色避让）、02_midgame/03_gameover autoplay 兼容（默认 SINGLE + SPACE 直开）（AC7）。
- **H4（文件域）**：实现 PR files 列表 ⊆ §4.1 白名单 17 文件，不混入波次/画面/暂停等其他 issue 文件（AC8/红线）。

### Scenario I — 手动验收（非自动化，implement 后人工过）

- **I1（AC1 手感）**：title 上 ↑/↓ 切换模式高亮 Tween 150–300ms 顺滑；SPACE 直开单人（默认）与现状一致。
- **I2（AC2/AC3 实机双人）**：双人实机：P1 A/D 只动底板、P2 ←/→ 只动顶板；升级窗口 E 与右Shift 各自确认、同屏抢卡博弈成立。
- **I3（AC4 博弈趣味）**：双人一局内 debuff 卡（缩板/冻结/减速/紊乱）可见生效且反馈清晰（#526 纪律）；数值合理性留 #395 taste 域调参。

---

## 10. Spike 交接（implement Phase 0 执行，plan 阶段不跑实验）

沿 #527 先例：PRD §7 三个轻量实验由 implement Phase 0 执行，结论影响本设计如下：

| Spike | 验证问题 | 设计影响 |
|-------|---------|---------|
| 1 | `action_erase_event` headless 安全性 + 重复开局幂等 | §3.3 增量 erase 方案；若竞态 → 回退全量重建（仅改 `rebind_for_mode` 内部） |
| 2 | 临时冻结 vs FSM 冻结互斥（或关系判定 + 剩余时长续走） | §3.4 `is_effectively_frozen` 判定式；若计数语义复杂化 → 独立 `_fsm_frozen` 与 `_timed_freeze_remaining` 双状态不变，仅调整判定优先级 |
| 3 | 01_title 模式 UI 色对 theme_absent 断言影响 | §3.1 高亮色 PADDLE_NEON/BRICK_NEON；若色数波动 → 高亮改 modulate 透明度（零新增色相） |

**决策点定稿（PRD §8.2 移交清单，本设计已裁决）：**
1. InputMap：静态定义 4 action 于 project.godot + 运行时增量 erase ←/→（Spike 1 验证；失败回退全量重建）
2. 模式状态复位：重开保留上次选择（§6-8）
3. 升级窗口等待：10s 超时代选（§6-3）
4. 显示层：HUD「P2: N」红区保留；结算 P1/P2 WIN 走胜者宣告分支（§4.2）
5. 右 Shift：绑定 KEY_SHIFT（Godot 无独立 RSHIFT keycode，左右 Shift 同键；物理右 Shift 触发）

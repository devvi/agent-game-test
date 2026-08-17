# PRD: [Feature] 暂停菜单显示当前比分与波次

> **Issue:** #513
> **标签:** enhancement, feature, depth/light, priority/medium, version/mvp
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** light（depth/light 标签 → Section 1–5 + 8 必填；6/7 跳过并注明）
> **所有权:** `content_ownership: mechanical`（确定性数据展示：暂停时读 GameManager 状态写入 Label，无品味决策）
> **来源:** cron research 派发（workflow/available → workflow/research）
> **前置依赖:** 无（依赖既有设施均已合入 main：#296 暂停、#385/#386 GameManager 状态、#392 霓虹 HUD/NeonStyle、#393 单场景组装）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：暂停时（FSM PAUSED 状态）GameHUD 被隐藏（`_set_ui("pause")` → `game_hud.visible=false`），PauseOverlay 仅显示半透明遮罩 + 居中「暂停」文字（#296 最小实现），玩家暂停时无法确认当前比分与波次。GameManager（autoload）的 `player_score / ai_score / wave_index` 状态与 `score_changed / wave_started` 信号均已就绪（#385/#386），只缺一个消费方。**

| 系统 | 当前状态 | 证据 |
|------|---------|------|
| PauseOverlay（pause_overlay.gd） | 仅 `show_overlay()/hide_overlay()` 切 visible；节点为 ColorRect 遮罩 + 单 Label「暂停」 | `mini-pong/gdscripts/pause_overlay.gd`（22 行）；Main.tscn `[node name="PauseOverlay" type="CanvasLayer"]` layer=10 + ColorRect(0,0,0,0.6) + Label(font_size 48, 居中) |
| FSM PAUSED（#296） | `_set_ui("pause")` 隐藏 StartMenu/GameHUD/GameOverScreen，仅 PauseOverlay 可见 | `game_state_machine.gd:enter_state(State.PAUSED)` → `_set_ui("pause")` + `show_overlay()` |
| 比分/波次数据 | GameManager `player_score: int` / `ai_score: int` / `wave_index: int` + `score_changed(p,a)` / `wave_started(index)` 信号 | `game_manager.gd` state 区与信号区；game_hud.gd 已消费（`_on_score_changed` / `_on_wave_started`） |
| 暂停冻结语义 | 暂停期间球 `delta<=0` 守卫、paddle `set_frozen(true)`、`_on_scored` 非 PLAYING 拒绝 → 比分/波次必然冻结 | `game_state_machine.gd` PAUSED 分支；GAME_DESIGN/18-PAUSE-SYSTEM.md |
| HUD 格式先例 | 比分 `"Player: %d"` / `"AI: %d"`；信息条 `"第 %d 波 · 剩余 %d"` | `game_hud.gd:_on_score_changed` / `_on_grid_wall_generated` |

**预调查结论（Patch 10 对照）：** issue 为 available-rescan 新分配，`git log --all` 无 #513 相关提交；`grep -rn "show_overlay" gdscripts/` 仅 FSM 一处调用。无 stale claims，全部声明确认成立。

### 1.2 Obsidian 知识库搜索结果（issue 要求知识搜索）

| 检索范围 | 命中文档 | 结论 |
|---------|---------|------|
| `/Volumes/Obsidian/Knowledge Ocean/wiki/`（WebDAV 已挂载）grep「暂停/pause」 | 「CUSGA 2026 游戏评选笔记.md」 | 「梦系穿梭」游戏的「暂停测评」条目，非本项目暂停菜单设计 |
| 同上 | 「人工智能递归自我改进.md」 | 「单方面暂停」为宏观发展策略讨论，与游戏 UI 无关 |
| 同上 grep「mini-pong / PONG / 比分 / 波次 / score / wave」 | 无命中 | 知识库无本项目暂停/比分/波次设计笔记 |

**结论：Obsidian 知识库无本项目暂停菜单设计笔记，知识搜索无新增约束。** 设计意图以仓库内 DESIGN #296（暂停）、DESIGN #385/#386（双得分/波次）、DESIGN #392（霓虹 HUD）为准，见第 2 节。

### 1.3 预期行为（验收条件，源自 Issue #513）

1. [ ] **AC1** 暂停时 overlay 显示玩家与 AI 的当前比分（格式参考 HUD 信息栏）
2. [ ] **AC2** 暂停时 overlay 显示当前波次
3. [ ] **AC3** 比分/波次在暂停瞬间正确反映游戏状态（暂停后不再更新）
4. [ ] **AC4** `--headless --quit` 无脚本错误
5. [ ] **AC5** 恢复游戏后 overlay 隐藏，无残留文本

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| 1 | 对局中按 Escape 暂停 | 每局 1–3 次 | 暂停时想确认当前局面（比分差距、打到第几波）再决定是否继续 |
| 2 | 暂停后查看状态 | 每局暂停时 | 遮罩之下只有「暂停」二字，玩家被迫恢复游戏才能看 HUD → 信息断层 |
| 3 | 快速暂停/恢复 | 偶尔 | 连按 Escape，比分/波次应保持暂停瞬间的值，无闪烁/无残留 |

## 2. 设计意图

### 2.1 为什么当前状态存在

| 贡献者 | 决策 | 后果 |
|--------|------|------|
| DESIGN #296（暂停系统） | PauseOverlay 最小实现：遮罩 +「暂停」Label | 覆盖层只有文字，无任何游戏状态信息 |
| DESIGN #292 / FSM #294 | `_set_ui()` 每次只显示一个 UI 层；PAUSED 只显示 PauseOverlay | 暂停时 HUD（layer 1）被隐藏，比分/波次随 HUD 消失 |
| DESIGN #385/#386（GameManager） | 双得分 + 波次状态与信号先于 UI 需求就绪 | 数据设施完备，缺 overlay 消费方（game_hud.gd 是唯一消费方） |

### 2.2 为什么现在改

- Issue #513 明确要求（version/mvp 打磨项）：暂停是玩家高频触点（每局 1–3 次），「暂停 → 看不到局面 → 必须恢复才能看」破坏信息连续性
- 数据（GameManager 状态）、样式（NeonStyle）、格式先例（HUD 文案）全部就绪，属于纯增量 UI 展示，无架构风险
- 暂停冻结语义使「读一次即正确」成为天然实现：无需订阅信号、无需轮询（AC3 自动满足）

### 2.3 先前约束

| 约束 | 详情 |
|------|------|
| 引擎/目录 | Godot 4.7.1，mini-pong/ |
| 暂停冻结语义 | 暂停期间状态冻结（球/板/得分全部停摆），issue 明示「比分/波次取暂停前一帧的值即可」→ 进入 PAUSED 时读值一次即正确 |
| 视觉 | 沿用 ui_neon_style（霓虹冷色），不引入新主题（issue 明示） |
| 层序 | PauseOverlay layer=10（constants.gd WAVE_TRANSITION_LAYER 注释：Atmosphere 0 < HUD 1 < Upgrade 2 < WaveTransition 3 < Pause 10） |
| HUD 格式先例 | `"Player: %d"` / `"AI: %d"`（game_hud.gd）；信息条 `"第 %d 波"` 前缀（`_refresh_info_bar`） |
| 测试契约 | mini-tree 测试无 GameManager autoload 全树 → 读值必须 null 守卫（game_hud.gd `_wave_index()` 的 `gm.get()` + null 检查模式） |
| 容错消费惯例 | #392 契约：未接线显示占位符「—」，不崩溃 |

## 3. 影响分析

### 3.1 直接影响

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| mini-pong/gdscripts/pause_overlay.gd | 暂停覆盖层（#296） | 新增比分/波次 Label 引用与 GameManager 读值；`show_overlay()` 内填充文本 |
| mini-pong/scenes/Main.tscn | 单场景组装（#393） | PauseOverlay 节点下新增 2 个 Label（比分行 + 波次行），NeonStyle 样式在代码侧应用（对齐 #392 单一事实源） |

### 3.2 新文件

无（light 深度：Label 进既有 Main.tscn 节点树，不新建场景/脚本）

### 3.3 间接影响

| 文件 | 影响 |
|------|------|
| mini-pong/tests/test_pause.gd | FSM 测试的 pause_overlay 是 mock CanvasLayer（`_make_mock_pause_overlay` 仅 show/hide），不受新方法影响 → 零回归；可选新增 overlay 内容断言 |
| mini-pong/tests/test_hud.gd | 不加载 Main.tscn 全树，无影响 |
| mini-pong/tests/e2e_playthrough.gd | 暂停相关仅升级 UI 的 `tree.paused` 断言，与 PauseOverlay 内容无关，无影响 |
| docs/GDD.md / docs/PROJECT.md | 可选补一行「暂停菜单显示比分/波次」约定（非强制） |

### 3.4 数据流

```
FSM.enter_state(PAUSED)  (Escape in PLAYING)
        │
        ▼
_set_ui("pause") ──► GameHUD.visible=false；PauseOverlay.visible=true
        │
        ▼
pause_overlay.show_overlay()
        │
        ├──► _resolve_game_manager()  (autoload GameManager；测试可注入)
        │
        ▼
读 GameManager: player_score / ai_score / wave_index（get() + null 守卫）
        │
        ▼
ScoreLabel.text = "Player: %d   AI: %d"（或双色两段）
WaveLabel.text  = "第 %d 波"
        │
        ▼
FSM.enter_state(PLAYING) (Escape again) ──► hide_overlay() → 整层隐藏（无残留）
```

### 3.5 文档更新

- [ ] docs/GDD.md —（可选）暂停菜单信息展示约定
- [x] 本 PRD 为研究阶段唯一必需产物

## 4. 方案比较

### 方案 A：场景静态 Label + show_overlay() 读值（推荐）

Main.tscn 的 PauseOverlay 下新增 ScoreLabel / WaveLabel（锚点居中，位于「暂停」文字下方）；pause_overlay.gd 在 `show_overlay()` 时经 `get("player_score") / get("ai_score") / get("wave_index")` 读 GameManager 并写入文本；NeonStyle.apply 套样式。

| 维度 | 评估 |
|------|------|
| Pros | 最小变更面（1 脚本 + 1 场景文件）；读一次即正确（暂停冻结语义，AC3 天然满足）；样式走 NeonStyle 单一事实源；复用 game_hud.gd `_wave_index()` 的 get()+null 守卫模式，headless 安全 |
| Cons | 场景文件 +2 节点、脚本 +~20 行；文本格式需与 HUD 约定保持一致（双处维护） |
| Risk | Low（GameManager 缺失 → 占位符「—」，不崩溃） |
| Effort | 0.5 天 |

### 方案 B：信号驱动（connect score_changed / wave_started）

暂停时连接 GameManager 信号、恢复时断开；或常驻连接但仅在 overlay visible 时更新文本。

| 维度 | 评估 |
|------|------|
| Pros | 与 #392「更新全部由信号驱动，零轮询」惯例字面一致 |
| Cons | 暂停期间状态不可能变化（冻结语义）→ 信号连接是纯冗余；需管理连接/断开生命周期（恢复时忘记断开 = 信号泄漏）；测试需 mock 信号发射，复杂度上升 |
| Risk | Med（连接生命周期管理 + 与冻结语义矛盾的过度设计） |
| Effort | 1 天 |

### 方案 C：暂停时保持 HUD 可见（复用 HUD，overlay 不加信息）

FSM `_set_ui("pause")` 时同时保持 `game_hud.visible = true`，让玩家透过遮罩看 HUD。

| 维度 | 评估 |
|------|------|
| Pros | 零新 UI 节点，复用既有 HUD 布局 |
| Cons | HUD layer=1 在遮罩 layer=10 之下 → 比分被 0.6 alpha 黑幕压暗，可读性差；信息分散顶部红区/底部蓝区/信息条三处，与 issue「overlay 添加两行信息」诉求不符；改 FSM 可见性契约，影响面大于方案 A |
| Risk | Med（可读性 + FSM 契约变更 + 与 issue 描述背离） |
| Effort | 0.5 天 |

### 推荐

**方案 A**。理由：(1) issue 明示「添加两行信息」到 pause_overlay，方案 C 偏离诉求；(2) 暂停冻结语义下读一次即正确，方案 B 的信号机制是冗余复杂度；(3) 变更面最小（1 脚本 + 1 场景），符合 depth/light；(4) 与既有模式完全对齐——game_hud.gd 的 `_resolve_game_manager()` / `_wave_index()` 就是同款读值写法，NeonStyle.apply 就是同款样式入口。

## 5. 边界条件与验收标准

### 5.1 正常路径 AC（映射 Issue #513）

- [x] **AC1: 暂停显示比分** — PLAYING 按 Escape → overlay 显示 `Player: X  AI: Y`（X/Y 与 GameManager 当前值一致；格式参考 HUD）
  - 验证：暂停后比对 GameManager.player_score / ai_score 与 Label 文本
- [x] **AC2: 暂停显示波次** — overlay 显示 `第 N 波`（N = GameManager.wave_index）
  - 验证：暂停后比对 GameManager.wave_index 与 Label 文本
- [x] **AC3: 暂停瞬间定格** — 暂停期间比分/波次不再变化（即使恢复后发生得分/换波，暂停期间文本恒定）
  - 验证：暂停中等待数帧，Label 文本不变；恢复后再次暂停，文本更新为新值
- [x] **AC4: headless 无脚本错误** — `godot --headless --quit` 与全量测试套件无报错
  - 验证：CI / 本地 `./scripts/run-tests.sh` 全绿
- [x] **AC5: 恢复后无残留** — 恢复 PLAYING 后 overlay 整层隐藏，无残留文本
  - 验证：hide_overlay() 后 visible=false；再次暂停文本重新填充

### 5.2 边界情况

1. **首波前暂停（wave_index == 0）**：PLAYING 进入即触发首波（#393 `_start_first_wave`），正常不可达；防御性显示「第 0 波」而非占位符（数值诚实），不崩溃
2. **GameManager 缺失（mini-tree 测试）**：`_resolve_game_manager()` 返回 null → Label 写占位符「—」+ 单次 push_warning，不崩溃（对齐 game_hud.gd 容错惯例）
3. **快速暂停/恢复连按**：每次 show_overlay() 重新读值；hide 时整层隐藏 → 无中间帧残留
4. **比分位数增长（0 → 21）**：Label 靠左/居中自适应宽度，21 分制下最多 2 位数字，无溢出风险
5. **21 分终局（GAME_OVER）后 Escape**：FSM `_input` 仅 PLAYING/PAUSED 响应 ui_cancel → 终局无法暂停，无需处理
6. **Label 与「暂停」文字重叠**：新 Label 锚点下移（offset_top 正值），垂直三行排布，不与 font_size 48 的「暂停」重叠
7. **中文渲染**：默认字体渲染中文已有先例（「暂停」Label），无新增字体依赖
8. **headless 样式安全**：NeonStyle.apply 为纯主题覆盖（ui_neon_style.gd 注释「headless 安全」），无渲染依赖

### 5.3 失败路径

1. **GameManager 解析失败**（autoload 未注册的异常环境）→ 占位符「—」，单次 push_warning，不崩溃（恢复路径：环境修正后重试）
2. **Label 节点缺失**（旧场景缓存 / 手工删节点）→ `get_node_or_null()` 守卫，跳过填充，不崩溃（FSM `_validate_references` 同款风格）
3. **文本格式与 HUD 漂移**（如 HUD 改文案而 overlay 未同步）→ 缓解：PRD 明确格式字符串常量建议放 constants.gd（`HUD_SCORE_PREFIX` 等），plan 阶段落实

## 6. 依赖与阻塞

**Skipped per depth/light** — 无前置依赖；依赖设施（#296 暂停 FSM、#385/#386 GameManager 状态与信号、#392 NeonStyle 与 HUD 格式、#393 Main.tscn 组装）均已合入 main。

## 7. Spike / 实验

**Skipped per depth/light** — 无技术不确定性：`get()` 读值 + null 守卫 + NeonStyle.apply 组合已在 game_hud.gd（#392/#448）实战验证；CanvasLayer 下 Label 布局为 Godot 4.7 标准语义。

## 8. 延续上下文（plan agent 交接）

**系统状态**：PauseOverlay（layer=10）含 ColorRect 遮罩 + 居中「暂停」Label，由 FSM PAUSED 状态经 `show_overlay()/hide_overlay()` 控制（#296）；GameManager autoload 持有 `player_score / ai_score / wave_index` 与 `score_changed / wave_started` 信号（#385/#386）；NeonStyle 为 Label 样式单一事实源（#392）。Obsidian 无相关设计笔记，设计意图以 DESIGN #296/#385/#386/#392 为准。

**核心结论**：采用方案 A——Main.tscn PauseOverlay 下新增 2 个 Label（比分行/波次行），pause_overlay.gd 在 `show_overlay()` 时从 GameManager 读值填充。深度 light，变更面 1 脚本 + 1 场景文件。

**实现要点（plan agent）**：
1. `mini-pong/scenes/Main.tscn`：PauseOverlay 节点（`[node name="PauseOverlay"]`，行 156 起）下新增 ScoreLabel 与 WaveLabel——锚点居中、位于「暂停」Label 下方（offset_top 递增，避免重叠）；文本初始为「—」占位；脚本引用不变
2. `mini-pong/gdscripts/pause_overlay.gd`：新增 `@onready var score_label: Label = $ScoreLabel` / `wave_label: Label = $WaveLabel`；新增 `_resolve_game_manager()`（game_hud.gd 模式：可注入 `var game_manager` + `is_instance_valid(GameManager)` 回退）与 `_read_state()`；`show_overlay()` 内调用 `_read_state()` 填充文本（格式：`"Player: %d   AI: %d"` 与 `"第 %d 波"`）；NeonStyle.apply 套色（比分行可 PLAYER_NEON_BLUE / AI_NEON_RED 双色或 HUD_INFO_COLOR 单色，波次行 HUD_INFO_COLOR）；全部经 `get_node_or_null` / null 守卫，缺失写「—」
3. 常量：格式前缀（`"Player: "` / `"AI: "` / `"第 "` / `" 波"`）建议抽入 constants.gd 与 HUD 共享，避免双处漂移（§5.3-3）
4. 测试：扩展 `mini-pong/tests/test_pause.gd` 或新增 overlay 测试——实例化 pause_overlay.gd + mock GameManager（`Engine.register_singleton` 先例见 test_pause.gd `_setup_gm_mock`），断言 show_overlay() 后 Label 文本 = mock 值；GameManager 缺失时显示「—」不崩溃；`--headless` 全量套件回归
5. 文档：GDD 补「暂停菜单显示比分/波次」一行（可选）

**风险**：无实质风险（Low）。文本格式与 HUD 双处维护是唯一长期注意点 → 常量共享缓解。

**参考文件**：`mini-pong/gdscripts/pause_overlay.gd`、`mini-pong/scenes/Main.tscn`（PauseOverlay 段）、`mini-pong/gdscripts/game_hud.gd`（`_resolve_game_manager` / `_wave_index` / 文案先例）、`mini-pong/gdscripts/game_manager.gd`（状态与信号）、`mini-pong/gdscripts/ui_neon_style.gd`、`docs/DESIGN/296-pause-and-sound.md`、`docs/GAME_DESIGN/18-PAUSE-SYSTEM.md`、`docs/PRD/296-pause-and-sound.md`

# PRD: [Feature] 3选1升级UI (Upgrade Pick UI)

> **Issue:** #388
> **标签:** enhancement, ui, version/mvp, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384 惯例处理：Section 1–6 + 8 必填，Section 7 以研究期已执行实验补齐）
> **所有权:** `content_ownership: mechanical`（纯机械交互层：候选展示/焦点切换/确认/reveal/暂停/推进接管；稀有度色值取值与卡片文案归 taste 域 #395 与 PLAN-rogue-pong §2.5）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.5（3 选 1 + 稀有度选择后 reveal 的情绪机制）+ §3.3（升级卡：3 张霓虹卡片，glow 边框 + hover 微亮，数值大字；动效统一 Tween 150–300ms）
> **前置依赖:** #386（波次循环，PR #428 已合并：`GameManager.wave_settled(wave_index)` 挂点 + `WaveController` 场景侧自动推进 `WAVE_SETTLE_DELAY=1.0s` 待 #388 接管）→ #387（升级池，PR #423 已合并：`UpgradePool.get_candidates(3)` / `apply(id)` / `upgrade_applied` 信号）→ #395（升级池文案 JSON 已落地 `mini-pong/assets/content/upgrade_pool.json`，schema `upgrade-pool-content/v1`）→ 本 Issue

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280，#383 已合并）的升级数据链路已全部就绪，**唯独缺少玩家可见的 3 选 1 升级交互层**：GDD 23 明确标注 `3-choice UI (#388, not yet wired)`。波次循环（#386）与升级池（#387）的代码均已落地（PR #428 / #423），`wave_settled` 信号就是为本 UI 预留的触发挂点。

| 系统 | 当前状态 | 与 #388 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/upgrade_pool.gd`（#387 PR #423） | ✅ `get_candidates(3)` 返回 `{id, name, rarity, max_stacks, effect_desc, display}`；`apply(id)->bool`；`upgrade_applied(id)` 信号；rng 可 seed（测试确定性） | ❌ 无 UI 消费方——`get_candidates` 从未被调用 |
| `mini-pong/gdscripts/upgrade_defs.gd` | ✅ `Rarity {COMMON=0, RARE=1, LEGENDARY=2}` + 9 定义 | — 只读消费 |
| `mini-pong/assets/content/upgrade_pool.json`（#395 已落地） | ✅ schema `upgrade-pool-content/v1`，每升级含 `name_working`/`short_phrase`/`naming_candidates`（如 长臂「够得着了」、燃烧弹「火过留洞」），经 `UpgradePool._load_display_names` 兜底注入候选 `display` 字段 | — 只读消费；UI 卡片短句数据源 |
| `mini-pong/gdscripts/game_manager.gd`（#386 PR #428） | ✅ `wave_settled(wave_index)` 信号（SETTLED 状态发出）+ `wave_state` 枚举 | — 触发挂点已就绪，无监听者 |
| `mini-pong/gdscripts/wave_controller.gd`（#386） | ✅ `wall_cleared` → `settle_wave()` → `await create_timer(WAVE_SETTLE_DELAY=1.0s)` → `_advance_wave()`；注释明确「#388 接线后由其接管推进时机」（DESIGN #386 边界 2） | ⚠️ 需要 hold/advance 接管机制，否则 UI 打开期间自动推进仍会触发 |
| `mini-pong/gdscripts/constants.gd` | ✅ `PLAYER_NEON_BLUE #4a90d9` / `AI_NEON_RED #ff3355` / `BG_COLOR #0a0a12`（#289 调色板） | ❌ 无稀有度颜色映射（AC3 需要颜色/边框区分） |
| 暂停机制（#296） | ⚠️ FSM `PAUSED` 状态仅冻结 paddle + ball delta guard，**未使用** `get_tree().paused` | AC4「UI 打开时游戏时间暂停」需设计（见 §4.2） |
| `mini-pong/scenes/Main.tscn` | ✅ 已含 4 个 CanvasLayer UI 层（StartMenu/GameHUD/GameOverScreen/PauseOverlay）+ ScoreFlash；**无** WaveController/BreakoutGrid 节点 | 升级 UI 层需挂载；运行时波次链路未激活（#384 砖墙未实现） |
| 输入映射 | `project.godot` 无自定义 `[input]` 段 | 使用 Godot 内置 `ui_left`/`ui_right`/`ui_accept`/`ui_cancel` |
| `mini-pong/tests/run_tests.gd` | ✅ 注册 17 个套件（含 test_upgrade_pool / test_wave_cycle） | ❌ 无升级 UI 测试 |

### 预期行为（验收条件，源自 Issue #388）

1. **AC1 — 波间自动弹出三张卡片，焦点默认在第一张** — 监听 `GameManager.wave_settled`，打开 UI 并渲染 `get_candidates(3)` 结果，`focus_index = 0`
2. **AC2 — 左右方向键切换焦点，确认键应用选中升级并关闭 UI** — `ui_left`/`ui_right` 循环切换；`ui_accept` → `UpgradePool.apply(id)` → reveal → 关闭
3. **AC3 — 稀有度以颜色/边框显现，确认后才展示完整稀有度** — 确认前卡片为中性霓虹样式（无稀有度线索）；确认后边框/光晕切换为稀有度颜色并显示稀有度名称（普通/稀有/传说）
4. **AC4 — UI 打开时游戏时间暂停，关闭后恢复** — `get_tree().paused = true`（UI 层 `process_mode = ALWAYS`），关闭后恢复
5. **AC5 — 候选升级来自 `UpgradePool.get_candidates(3)`** — 唯一候选来源，UI 不自行生成

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 波间升级（玩家） | 每波一次 | 砖墙打空 → `wave_settled` → UI 弹出（游戏时间暂停）→ 三张霓虹卡 → 左右切换焦点 → 确认 → reveal 稀有度 → `apply(id)` → UI 关闭（恢复）→ 推进下一波 |
| B | 稀有度 reveal（玩家） | 每波一次 | 确认前卡片隐藏稀有度（PLAN §2.5 情绪机制 2「不可预测奖励」）；确认后展示完整稀有度（颜色/边框 + 名称）与短句，制造惊喜时刻 |
| C | 实现期回归 | 每次改动 | headless 注入候选 + feed 输入事件，断言焦点切换/apply 调用/暂停恢复/推进接管（`UpgradePool.rng.seed()` 保证确定性） |

### 技术约束（继承自 Issue #388 与上游）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`；竖屏 720×1280，#383 已合并） |
| 所有权 | mechanical——只做交互机械层；稀有度**色值**与卡片**文案**归 taste（#395 JSON 已含 `short_phrase`；色值在 constants.gd 以 taste 占位常量给出，映射关系机械可测，同 #387 机械占位先例） |
| 消费契约 | 只读消费 `UpgradePool.get_candidates(3)`/`apply(id)`/`upgrade_applied`；只监听 `GameManager.wave_settled(wave_index)`；**不修改** UpgradePool API 与 GameManager 波次状态机语义 |
| 推进接管 | #386 DESIGN 决策 4「结算不依赖 #388」：`wave_settled` 后 `WAVE_SETTLE_DELAY=1.0s` 自动进下一波；#388 接线后由 UI 决定推进时机（其 AC 独立）——本 Issue 需在 WaveController 加 hold/advance 机制（§4.3） |
| FSM 边界 | #386 决策 1 否决扩展 FSM 状态——升级 UI 不得新增 FSM State |
| 开源优先 | Issue 上下文要求先搜 Asset Library/GitHub——调研结论见 §7 实验 1：**无可复用成熟方案，第一方实现** |

### Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（`OBSIDIAN_VAULT_PATH`，WebDAV）。本会话检索 `Knowledge Ocean` 目录：**目录为空**（无升级/UI 相关笔记；#386 会话曾遇读取超时，本次为空目录，均未检索到直接可用的波间升级 UI 笔记）。
- **兜底**：升级 UI 的体验设计已由 `docs/PLAN-rogue-pong.md` §2.5 **固化并用户拍板**（2026-08-13）——其理论依据即来自 Obsidian 知识库（《体验引擎》情感模型：情感误归因 / 不可预测奖励 / 极乐迪斯科带代价的选择），落地为：3 选 1 + 稀有度选择后 reveal + 每卡一行克制短句（#395 JSON 已提供）。§3.3 确认升级卡视觉（3 张霓虹卡片、glow 边框、hover 微亮、数值大字、Tween 150–300ms）。GDD `docs/GAME_DESIGN/16-UI-SYSTEM.md`（CanvasLayer 模式）与 `23-UPGRADE-POOL.md`（3-choice UI not yet wired）为本 PRD 的结构依据。

---

## 2. 设计意图

### 为什么现状如此

- **#387 只交付了数据层**：升级池（autoload）、9 定义、60/30/10 抽取、apply 链路——按设计它是「wave settlement 与 paddle/ball/grid 之间的 data hub」，UI 消费方明确留给 #388（GDD 23），故 `get_candidates` 至今无调用方。
- **#386 刻意让结算不依赖 #388**（DESIGN 决策 4）：`wave_settled` 发出后按 1.0s 延时自动进下一波，保证升级 UI 缺席时波次循环照常运转——因此本 Issue 必须提供**显式的推进时机接管**，而非依赖删除自动推进。
- **现有 UI 全部是「信息展示 + 单键确认」模式**（StartMenu/GameHUD/GameOverScreen 均为 CanvasLayer + Label，#292），没有任何「多选一 + 焦点切换」交互先例——本 UI 是项目第一个键盘导航选择层。

### 为什么现在做

- 依赖已闭环：**#386（挂点）✅ PR #428 → #387（数据）✅ PR #423 → #395（文案）✅ JSON 已落地**。数据链路齐备而玩家看不到升级时刻，肉鸽循环（PLAN §2.1：波次开始 → 对打 → 墙清空 → 结算 → **3选1升级** → 下一波）在 MVP DoD 路径（§6：MENU → 波1 → 3选1 → 波2 → …）上缺最后一环。
- 升级池已就绪但「无人触发」（#386 PRD §1 亦记录此 gap）——本 UI 是触发点。

### 前置约束（继承）

- 不改 UpgradePool API、不改 GameManager 波次状态机、不扩展 FSM（#386 决策 1）。
- 不写 #395 JSON（只读消费 `display`；`name_working`/`short_phrase` 缺失时兜底 `name`/`effect_desc`）。
- 稀有度颜色**映射关系**（COMMON/RARE/LEGENDARY → 色键）为机械可测，具体**色值**标注 taste 占位（沿 #387「机械占位数值」先例）。
- `get_tree().paused` 语义：WaveController 的 `SceneTreeTimer` 默认 `process_always=true`（暂停下仍计时）→ 自动推进的接管必须是显式机制，不能依赖暂停。

---

## 3. 影响分析

### 直接影响模块

| 文件 | 改动 | 说明 |
|------|------|------|
| `mini-pong/gdscripts/upgrade_pick_ui.gd` | **新建** | CanvasLayer 脚本：`open(wave_index)` / 焦点状态机 / reveal / apply / close + 暂停管理 + 推进接管调用 |
| `mini-pong/scenes/ui_upgrade_pick.tscn` | **新建** | 三张霓虹卡片（PanelContainer + StyleBox 边框 + Label），CanvasLayer layer 2，初始 `visible=false` |
| `mini-pong/gdscripts/wave_controller.gd` | 修改 | 新增 `settle_hold: bool`（默认 false）+ `advance_settlement()`（§4.3-A）；默认行为不变，兼容 #386 既有测试 |
| `mini-pong/gdscripts/constants.gd` | 修改 | 新增 `UPGRADE_RARITY_COLORS`（taste 占位色值）+ UI 常量（卡片尺寸/动画时长） |
| `mini-pong/scenes/Main.tscn` | 修改 | 挂载 `ui_upgrade_pick`（与 PauseOverlay 同模式，`visible=false`） |
| `mini-pong/tests/test_upgrade_pick_ui.gd` | **新建** | headless：注入候选 / feed 输入事件 / 断言暂停与推进接管 |
| `mini-pong/tests/run_tests.gd` | 修改 | 注册 `test_upgrade_pick_ui.gd` |

### 间接影响模块

| 模块 | 影响 |
|------|------|
| `game_manager.gd` / `upgrade_pool.gd` | **零改动**——只消费信号与 API（不改契约，最小侵入） |
| `game_state_machine.gd` | **零改动**——树级暂停天然屏蔽其 `_input`（Escape 不会误触）；需在实现期回归 `test_pause.gd` 确认 |
| `docs/GAME_DESIGN/` | 新增 `25-UPGRADE-UI.md` 章（或并入 23）记录 UI 层设计（管线惯例：实现 PR 同步 GDD） |
| #390 波次转场 / #393 HUD / #394 E2E | 同挂 `wave_settled` 的共享挂点——本 UI 打开期间转场应让位（§6 协调点） |

### 数据流图（波间升级窗口）

```
BreakoutGrid.wall_cleared
    │
    ▼
WaveController._on_wall_cleared() ──► GameManager.settle_wave()
                                        │  wave_state = SETTLED
                                        ▼
                              wave_settled(wave_index) ──► UpgradePickUI.open(wave_index)
                                                              ├─ UpgradePool.get_candidates(3) → 3 候选（display 文案 + effect_desc）
                                                              ├─ get_tree().paused = true（游戏时间暂停）
                                                              ├─ ui_left/ui_right 切换 focus_index
                                                              ├─ ui_accept → UpgradePool.apply(id)
                                                              │     ├─ true  → reveal 稀有度 → upgrade_applied → close
                                                              │     └─ false → 保持打开 + push_warning（边界 2）
                                                              └─ close: get_tree().paused = false
                                                                        └─ WaveController.advance_settlement() → _advance_wave() → 下一波
```

### 文档更新清单

- `docs/GAME_DESIGN/25-UPGRADE-UI.md`（新章，或并入 23）
- `docs/PROJECT.md`（模块清单 + 波次循环状态）

---

## 4. 方案对比

### 4.1 稀有度揭示策略（AC3 + PLAN §2.5 情绪机制 2）

| | Approach A：确认后 reveal（推荐） | Approach B：确认前颜色暗示 | Approach C：完全隐藏 |
|---|---|---|---|
| 描述 | 选择前卡片为中性霓虹样式（聚焦高亮）；确认后边框/光晕切换稀有度颜色 + 显示稀有度名称 + 短句 | 选择前边框按稀有度低亮着色（无文字标签），确认后全亮 + 名称 | 确认前无任何稀有度线索，确认后一次性 reveal |
| Pros | 与 PLAN「稀有度不提前显示」字面一致；AC3「颜色/边框显现」在确认后完整满足；实现最简单 | 给玩家渐进线索 | 最保守 |
| Cons | — | 「暗示」语义模糊，玩家可能误读为普通样式差异；削弱惊喜时刻 | 与 AC3「稀有度以颜色/边框显现」字面冲突风险 |
| Risk | 低 | 中（taste 争议） | 中（AC 不满足） |
| Effort | S | M | S |

**推荐 A**：确认后 reveal。AC3 解读为「稀有度通过颜色/边框显现，且完整稀有度在确认后才展示」——与 PLAN §2.5 情绪机制 2（不可预测奖励）完全一致，且为机械层最简实现。

### 4.2 暂停机制（AC4）

| | Approach A：`get_tree().paused` + UI `PROCESS_MODE_ALWAYS`（推荐） | Approach B：FSM 扩展 UPGRADE 状态 | Approach C：节点级冻结扩展 |
|---|---|---|---|
| 描述 | UI 打开时 `get_tree().paused = true`，UI 根节点 `process_mode = PROCESS_MODE_ALWAYS` 继续处理输入；关闭后 `false` | 在 FSM 增加 `UPGRADE` 状态，复用 `_freeze_paddles` 模式 | 沿现有 `_freeze_paddles` + ball delta guard 逐个冻结 |
| Pros | Godot 标准「游戏时间暂停」；天然冻结 ball/paddle/FSM._input/音频之外全部逻辑；headless 可断言 `is_paused()` | 状态显式 | 不动树级暂停 |
| Cons | 需注意 `SceneTreeTimer` 默认 `process_always=true`（计时不停）→ 必须配合 §4.3 接管 | **违反 #386 决策 1**（不扩展 FSM）；FSM 与波次状态机职责重复 | 漏网风险高（ball/paddle/粒子/雨幕…逐节点）；不可枚举 |
| Risk | 低（配合 4.3） | 高（架构违规） | 高（遗漏即穿帮） |
| Effort | S | M | L |

**推荐 A**：`get_tree().paused` 是 AC4 字面「游戏时间暂停」的标准实现。配合 §4.3-A 解决自动推进问题。

### 4.3 波次推进时机接管（#386 DESIGN 边界 2 的落地）

| | Approach A：WaveController hold/advance API（推荐） | Approach B：UI 直接调 `GameManager.begin_wave()` | Approach C：延时依赖 UI 信号 |
|---|---|---|---|
| 描述 | WaveController 新增 `settle_hold: bool`（默认 false）+ `advance_settlement()`；UI 打开时置 hold，确认后调 `advance_settlement()` 走 `_advance_wave()` | UI 关闭后自己 `begin_wave()` | `settle_delay` 改为等待 UI 信号才推进 |
| Pros | 最小侵入、显式、可单测（默认 false 保持 #386 行为，既有测试零破坏）；`_advance_wave`（难度递增/雨幕因子/墙生成）逻辑不重复 | 代码少 | 少改 WaveController |
| Cons | WaveController 增一个 API | **绕过 `_advance_wave`**：难度递增、`set_wave_factor`、`generate_wave(更厚)` 全部丢失或重复实现——职责越界 | 隐式耦合（WaveController 需知道 UI 存在）；难测、难兜底 |
| Risk | 低 | 高（难度曲线断裂） | 中 |
| Effort | S | S | M |

**推荐 A**：`settle_hold`（默认 false）+ `advance_settlement()`。`_on_wall_cleared` 中：`settle_wave()` 后若 `settle_hold` 为 true 则跳过自动延时直接返回（等待 UI 调用）；否则维持现状。UI 关闭时调用 `advance_settlement()` 触发推进。

### 4.4 输入与焦点管理（AC2）

| | Approach A：`_unhandled_input` 焦点状态机（推荐） | Approach B：Control focus 系统 | Approach C：信号总线 |
|---|---|---|---|
| 描述 | UI 内维护 `focus_index: int`，`_unhandled_input` 处理 `ui_left`/`ui_right`（循环切换）/`ui_accept`（确认）；高亮 = 直接改卡片 modulate/边框 | `grab_focus()` + `focus_neighbor`，依赖 Godot 焦点导航 | 输入经总线转发 |
| Pros | 与现有 FSM `_input` 模式同构；headless 可直接 `Input.parse_input_event()` 断言；无场景树焦点依赖 | 少写状态逻辑 | 解耦 |
| Cons | 手动管理焦点环 | headless 测试脆弱（焦点在 paused + 无真实窗口下行为不稳）；卡片容器导航配置繁琐 | 过度设计（单消费者） |
| Risk | 低 | 中 | 低（但无必要） |
| Effort | S | M | M |

**推荐 A**：`focus_index` 整数 + `_unhandled_input`。确认键用 `ui_accept`（内置 SPACE/Enter，与 FSM 一致）。

### 推荐汇总

| 子方案 | 推荐 | 核心落地 |
|--------|------|---------|
| 稀有度揭示 | 4.1-A 确认后 reveal | `upgrade_pick_ui.gd` |
| 暂停机制 | 4.2-A `get_tree().paused` + ALWAYS | `upgrade_pick_ui.gd` + `ui_upgrade_pick.tscn` |
| 推进接管 | 4.3-A WaveController hold/advance | `wave_controller.gd` |
| 输入焦点 | 4.4-A `_unhandled_input` 状态机 | `upgrade_pick_ui.gd` |

---

## 5. 边界条件与验收标准

### 正常路径（AC 清单）

| AC | 验收标准 | 测试锚点 |
|----|---------|---------|
| AC1 | `wave_settled` 发出 → UI `visible=true`、3 张卡片、`focus_index==0`、第一张高亮 | `test_upgrade_pick_ui.gd` T-1 |
| AC2 | `ui_right`/`ui_left` 循环切换焦点（0→1→2→0）；`ui_accept` → `apply(选中 id)` 恰好一次 → `visible=false` | T-2 |
| AC3 | 确认前无稀有度名称/无稀有度色边框；确认后边框切稀有度颜色 + 显示「普通/稀有/传说」 | T-3 |
| AC4 | open 后 `get_tree().paused == true`；close 后 `false` | T-4 |
| AC5 | open 时 `get_candidates(3)` 恰好被调一次，卡片内容 = 返回候选（id/name/short_phrase） | T-5 |

### 边界情况（≥5）

1. **候选不足 3 张**（池耗尽/回退链全空）——按实际张数渲染，`focus_index` clamp 到 `size-1`；空数组直接关闭 UI 不暂停
2. **`apply` 返回 false**（未知 id / 已达 max_stacks 的竞态）——保持 UI 打开 + `push_warning`，不关闭、不恢复、不推进
3. **`wave_settled` 连发**——WaveController `_settling` 守卫已忽略重复 `wall_cleared`；UI 侧 open 时若已 visible 则 no-op（幂等）
4. **UI 打开时按 Escape**——树级暂停屏蔽 FSM `_input`（天然不切 PAUSED）；UI 自身不消费 `ui_cancel`（保持打开）
5. **终局竞态**（`wave_settled` 后 `is_run_over()`）——WaveController 已走 `end_wave_cycle` 不推进；UI open 前检查 `is_run_over()` 则跳过升级窗口
6. **display 文案缺失**（JSON 缺失/损坏）——`UpgradePool` 已兜底工作名，UI 直接消费候选的 `name`/`effect_desc`（不依赖 `display` 非空）
7. **headless/无真实窗口**——不依赖 Control focus 系统（4.4-A），`Input.parse_input_event` 直测

### 失败路径（≥3）

1. `get_candidates` 返回空 → 不弹 UI、不暂停（静默跳过本波升级窗口）
2. `apply` 失败 → 见边界 2
3. Main.tscn 未挂载 UI 节点（现状）→ `wave_settled` 无监听者即 no-op，不崩溃（信号无消费者语义，#386 已按此设计）

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 说明 |
|------|:----:|------|
| #386 波次循环 | ✅ 已合并（PR #428） | `wave_settled` 挂点 + WaveController（本 Issue 在其上加 hold/advance） |
| #387 升级池 | ✅ 已合并（PR #423） | `get_candidates(3)` / `apply(id)` / `upgrade_applied` |
| #395 升级池文案 | ✅ 已落地 | `upgrade_pool.json`（schema `upgrade-pool-content/v1`），只读消费 |
| #384 砖墙系统 | ⚠️ 实现未落地（PRD #411 + DESIGN #414 已合并） | 运行时整链路（墙 → 波次 → 升级）待其落地 + 场景组装；**本 Issue 实现与测试不依赖其运行时存在**（headless 直测 UI 层） |

### 阻塞（下游消费者）

| 消费者 | 依赖内容 | 协调点 |
|--------|---------|--------|
| #390 波次转场（未开工） | 同挂 `wave_settled` | 升级 UI 打开期间转场应让位；两者均监听 `wave_settled`，互不干扰（各自独立信号处理） |
| #393/#394 组装与 E2E | UI 场景挂载 + 全链路 | Main.tscn 挂载后 E2E 截图（升级卡） |

### 依赖链

```
#384 砖墙(未实现) → #386 波次(✅) → #387 升级池(✅) → #395 文案(✅) → #388 升级UI(本 Issue) → #390/#393/#394
```

### 准备清单

- 确认 Main.tscn CanvasLayer 层序：升级 UI 置于 GameHUD 之上、与 PauseOverlay 同级（layer 2）
- constants.gd 新增 `UPGRADE_RARITY_COLORS`（COMMON→霓虹蓝系 / RARE→霓虹紫系 / LEGENDARY→金色系，色值标注 taste 占位，映射关系机械定稿）
- `UpgradePool.rng.seed()` 供测试固定候选序列

---

## 7. Spike / 实验

> 本 Issue 无 `depth/deep` 标签，按 standard 惯例 Section 7 可选；鉴于 Issue body 明确要求「开源优先」调研，以下 3 个实验已在**研究阶段实际执行**并给出结论。

| # | 问题 | 方法 | 结果 | 对方案的影响 |
|---|------|------|------|-------------|
| 1 | 是否存在可复用的 3 选 1 升级选择 UI 插件/模板？ | Godot Asset Library（4.x 过滤 `upgrade`/`choice`/`roguelike`）+ GitHub 搜索（`godot upgrade ui`/`godot card selection`） | Asset Library：`upgrade` 多为编辑器工具或 4.0 时代战斗升级 demo（如 Wyvernshield 战斗升级）、`roguelike` 无可插拔选择 UI；GitHub：学习向 demo（<5⭐），无霓虹 3 选 1 卡片 UI 模块；Godot 内置 `PanelContainer`/`StyleBox`/`Tween` 足以实现 PLAN §3.3 视觉 | **确认第一方实现**（Approach 4.1–4.4），零第三方依赖；沿用 GDD 16 CanvasLayer 模式与 #289 霓虹调色板 |
| 2 | 稀有度颜色映射现状 | grep `constants.gd` + GDD 16/289 调色板 | 仅有 `PLAYER_NEON_BLUE #4a90d9` / `AI_NEON_RED #ff3355` / `BG_COLOR #0a0a12`，**无稀有度色** | 新增 `UPGRADE_RARITY_COLORS` 映射（机械键 + taste 占位色值） |
| 3 | `get_tree().paused` 与自动推进的交互 | 读 `game_state_machine.gd`/`wave_controller.gd` + SceneTreeTimer 语义 | FSM 未用树级暂停；`SceneTreeTimer` 默认 `process_always=true` → **暂停下 WaveController 自动推进仍会计时触发** | §4.3-A（settle_hold/advance_settlement）为**必要机制**，不能靠暂停隐式解决 |

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- 依赖全部就绪：`wave_settled`（#386 PR #428）、`get_candidates(3)`/`apply(id)`/`upgrade_applied`（#387 PR #423）、文案 JSON（#395 已落地 `mini-pong/assets/content/upgrade_pool.json`）
- `get_candidates(3)` 候选结构：`{id, name, rarity(Rarity enum int), max_stacks, effect_desc, display:{name_working, short_phrase, naming_candidates}}`；`display` 缺失时兜底 `name`/`effect_desc`
- **Main.tscn 现无 WaveController/BreakoutGrid**——运行时波次链路未激活（#384 砖墙未实现 + 场景未组装）；升级 UI 监听 `wave_settled` 与全部单测不依赖运行时接线
- WaveController 现状：`_on_wall_cleared()` → `settle_wave()` → `await create_timer(WAVE_SETTLE_DELAY)` → `_advance_wave()`；`settle_delay` 为可注入实例变量

### 本 PRD 的核心决策（勿偏离）

1. **4.1-A**：确认后 reveal 稀有度（边框颜色 + 名称 + 短句）；选择前中性霓虹样式
2. **4.2-A**：`get_tree().paused = true/false` + UI 根 `process_mode = PROCESS_MODE_ALWAYS`
3. **4.3-A**：WaveController 新增 `settle_hold: bool`（默认 false）+ `advance_settlement()`；UI open 置 hold、close 后调 advance——默认 false 保持 #386 行为，既有 wave 测试零破坏
4. **4.4-A**：`focus_index` + `_unhandled_input` 状态机（`ui_left`/`ui_right` 循环切换、`ui_accept` 确认）
5. **边界**：不修改 UpgradePool/GameManager/FSM；不写 #395 JSON；稀有度色值 taste 占位但映射键机械定稿

### 新建文件清单

| 文件 | 要点 |
|------|------|
| `mini-pong/gdscripts/upgrade_pick_ui.gd` | `open(wave_index)`：`get_candidates(3)` → 渲染 → `paused=true` → hold；`_unhandled_input` 焦点环；`ui_accept` → `apply(id)`（false 不关闭）→ reveal → `close()`（`paused=false` + `advance_settlement()`）；`upgrade_applied` 可作 reveal 锚点 |
| `mini-pong/scenes/ui_upgrade_pick.tscn` | CanvasLayer（layer 2，`process_mode=ALWAYS`，初始 `visible=false`）+ HBox 三卡（PanelContainer + StyleBoxLine/霓虹边框 + 名称 Label + 短句 Label + 效果 Label） |
| `mini-pong/tests/test_upgrade_pick_ui.gd` | 见「测试要点」 |

### 修改文件清单

| 文件 | 改动 |
|------|------|
| `mini-pong/gdscripts/wave_controller.gd` | `settle_hold: bool = false`；`_on_wall_cleared` 中 hold 为 true 时跳过自动延时；`advance_settlement()` → `_advance_wave()`（含 `_settling` 复位） |
| `mini-pong/gdscripts/constants.gd` | `UPGRADE_RARITY_COLORS: Dictionary`（COMMON/RARE/LEGENDARY → Color，taste 占位）+ `UPGRADE_UI_*`（卡宽/间距/动画时长 150–300ms） |
| `mini-pong/scenes/Main.tscn` | 挂 `ui_upgrade_pick`（`visible=false`） |
| `mini-pong/tests/run_tests.gd` | 注册 `test_upgrade_pick_ui.gd` |
| `docs/GAME_DESIGN/25-UPGRADE-UI.md` | 新章（实现 PR 同步） |

### 测试要点（test_upgrade_pick_ui.gd）

- T-1 AC1：`UpgradePool.rng.seed()` + emit `wave_settled` → UI visible、3 卡、`focus_index==0`
- T-2 AC2：feed `ui_right`×3 环绕回 0；`ui_accept` → `apply` 恰一次、UI 隐藏、`paused==false`、`advance_settlement` 被调
- T-3 AC3：确认前无稀有度标签/色边框；确认后稀有度名称与颜色呈现
- T-4 AC4：open 后 `get_tree().paused==true`；close 后 `false`
- T-5 AC5：`get_candidates(3)` 恰一次 + 卡片内容与候选一致（id/name/short_phrase 兜底链）
- 边界：候选 2 张/0 张；`apply` false 保持打开；`wave_settled` 幂等；Escape 不误触（回归 `test_pause.gd`/`test_wave_cycle.gd` 全绿）

### 主要风险

- **SceneTreeTimer 在 paused 下仍计时** → 自动推进必须由 4.3-A 显式接管（已定，勿改为依赖暂停）
- **Escape 误触** → 树级暂停屏蔽 FSM `_input`（天然安全）；实现期回归 `test_pause.gd` 确认 FSM 在 `paused=true` 时无输入处理
- **#384 未实现** → E2E 全链路（墙→波次→升级）不可跑；UI 层单测 + 手动场景调试兜底，PR 中如实说明

### 下一步

1. plan agent 依据本 PRD 产出 DESIGN（含 WaveController hold/advance API 细节、卡片场景结构与稀有度色值占位、Main.tscn 接线）
2. implement agent 实现 `upgrade_pick_ui.gd` + `ui_upgrade_pick.tscn` + wave_controller 修改 + 测试（含 run_tests.gd 注册）
3. #384 砖墙落地 + 场景组装后，E2E 验证「墙清空 → 升级窗口 → 下一波」全链路；#390 转场接线时协调 `wave_settled` 共享挂点（UI 打开期间转场让位）

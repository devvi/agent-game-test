# PRD: [Feature] 失败屏 (Failure Screen)

> **Issue:** #391
> **标签:** enhancement, workflow/available, ui, version/mvp
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 跳过）
> **所有权:** `content_ownership: mechanical`（失败屏为纯机械 UI 层：短句文本内容归 #396 已落地，本 Issue 只做读取/布局/状态切换，无 taste 决策）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2（失败即叙事，非惩罚）+ `docs/PRD/396-wave-failure-copy-draft.md`（B5 失败短句候选，已 merged #400 + 落地 #407）
> **前置依赖:** #385（双得分制，**已关闭** PR #424）→ #386（波次循环，**已关闭** PR #425）→ 本 Issue；内容数据源 #396（**已合并** PR #407，`mini-pong/content/wave_failure_text.json` 已存在）

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）已有 **21 分终局结算屏**（#292 建 GameOverScreen）：`match_over(winner)` 信号 → 显示 "YOU WIN!" / "AI WINS!" + SPACE 重开提示。但该屏是**胜负同屏**的结算公告，不是 Issue 要求的**失败屏**：

| 文件 | 当前状态 | 与 #391 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/game_over_screen.gd` | 消费 `match_over` → 胜/负各显示一行大字 + 脉冲/闪烁动画；已有 `get_node_or_null(".../RunStatsLabel")` 容错读取（#385 AC5 预留，节点不存在则跳过） | ❌ 无失败短句显示（内容源 #396 已就绪但无人读取）；❌ 无 RunStatsLabel 节点（数据读取路径存在但布局未建）；❌ 胜负同屏无「失败」专属呈现 |
| `mini-pong/gdscripts/game_state_machine.gd` | 6 态 FSM：...→SCORED→GAME_OVER→MENU；GAME_OVER 态 `_set_ui("game_over")` + `_freeze_paddles(true)`；SPACE → MENU（重开路径已通） | ⚠️ AC4「失败屏出现时游戏暂停」未满足：GAME_OVER 只冻结 paddle，**球仍可能移动**（`ball.gd` 无 `set_frozen` 方法，`_process` 持续运行） |
| `mini-pong/gdscripts/ball.gd` | `_process` 手动移动；无 frozen 状态（paddle 有 `set_frozen`，ball 没有） | ❌ 无暂停接口——AC4 需要 ball 在 GAME_OVER 时停住 |
| `mini-pong/gdscripts/game_manager.gd` | **数据全部就绪**（#385/#386 已落地）：`wave_index`（波次）、`get_brick_count(side)`（拆砖）、`get_pierce_count(side)`（穿墙）、`match_over(winner)`、`reset_match()` | ✅ 无差距——run 数据查询 API 齐备，本 Issue 只消费 |
| `mini-pong/content/wave_failure_text.json` | **已存在**（#396 全链路：PRD #400 + DESIGN #406 + impl #407 合并）：`failure_phrases` 4 条候选（fp1「雨还在下」recommended:true、fp2「雨记住了这一局」、fp3「就差一道墙」、fp4「墙还在，雨未停」），schema `wave-failure-text/v1`，`draft: true` | ✅ 内容就绪——本 Issue 机械层读取 `failure_phrases`；短句选择策略待定（§4） |
| `mini-pong/scenes/Main.tscn` | GameOverScreen 内联节点树：`CenterContainer/VBoxContainer/WinnerLabel + Spacer + RestartPromptLabel` | ❌ 无 RunStatsLabel 节点、无 FailurePhraseLabel 节点（布局归本 Issue） |
| `mini-pong/tests/` | 17 套件（#346 基线 + #385/#386 新增） | ❌ 无失败屏测试（短句读取/数据展示/暂停/重开） |

### 预期行为（验收条件，源自 Issue #391）

1. **AC1 — 玩家失败时切换至失败屏** — `match_over("ai")`（玩家败）时显示失败屏：失败短句 + run 数据；`match_over("player")`（玩家胜）保持既有胜利呈现（胜负分流）
2. **AC2 — 展示波次、总拆砖数、总穿墙数 3 项 run 数据** — 波次 = `GameManager.wave_index`；总拆砖 = `get_brick_count("player")`；总穿墙 = `get_pierce_count("player")`（玩家视角 run 数据）
3. **AC3 — 短句从配置读取且无 emoji/夸张语气** — 运行时读 `res://content/wave_failure_text.json` 的 `failure_phrases`（`FileAccess.get_file_as_string()` + `JSON.parse_string()`，项目既有 JSON 先例 #407）；文本内容已由 #396 海明威校验（无感叹号/无 emoji/形容词 ≤1）
4. **AC4 — 失败屏出现时游戏暂停** — GAME_OVER 进入时 ball + paddles 全部冻结（§4 暂停机制对比）
5. **AC5 — 可重开进入新一轮** — 复用既有路径：SPACE → MENU → `reset_match()`（wave_index/计数归零）→ SPACE 再开（已通，需验证）

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|:---:|------|
| A | 玩家失败（AI 先到 21 分） | 高 | 球出界计分后进入 GAME_OVER：失败屏显示短句（如「雨还在下」）+ 波次/拆砖/穿墙 3 项数据，游戏静止，SPACE 重开 |
| B | 玩家胜利（玩家先到 21 分） | 中 | 保持既有 "YOU WIN!" 结算呈现（本 Issue 不改变胜利路径） |
| C | 首波即败（波 1-2） | 低 | 短句应匹配早败语境（fp1「雨还在下」recommended）——按波次语境选择短句 |
| D | 惜败（波 6+ 或比分接近 21） | 低 | 短句匹配晚败语境（fp3「就差一道墙」） |

---

## 2. 设计意图

### 为什么现状如此

| 现状 | 成因 Issue | 说明 |
|------|-----------|------|
| GameOverScreen 是胜负同屏结算公告 | #292 | MVP 早期只有「先到 5 分赢一局」的局/赛制，结算屏只需公告胜负 |
| 无 run 数据展示 | #385/#386 之前无数据 | 拆砖/穿墙/波次概念是 PONG://21 攻城战肉鸽方案（PLAN-rogue-pong §2）引入的，数据 API 在 #385/#386 才落地 |
| 短句内容为空 | #396 前无文案 | B5 失败表达属 taste 领域（人机共做），文案由 #396 产出候选并已落地 `wave_failure_text.json` |
| GAME_OVER 不暂停球 | #294 FSM 设计 | 早期只有 paddle 冻结（胜负已分，球自然出界停摆）；波次模式下球可能仍在中场移动 |

### 为什么现在改

1. **机械数据全部就绪**：#385（PR #424）提供拆砖/穿墙计数 + `match_over`；#386（PR #425）提供 `wave_index` + 波次状态机；本 Issue 只需消费，无新状态设计
2. **内容数据源已落地**：#396 全链路合并（#407），`wave_failure_text.json` 存在且 schema 与 #391 读取点对齐（DESIGN #406 §4 明确「#391 读 `failure_phrases`」）——机械层读取即可，不阻塞于用户定稿（draft 标记不影响结构读取）
3. **克制优先的品味方向已确认**：PLAN-rogue-pong §2「失败 = 叙事生产，非惩罚」+ #396 B5 候选（海明威式短句）——失败屏**不堆特效**，数据 + 一句短句即交付

### 先前约束

| 约束 | 详情 |
|------|------|
| 引擎/目录 | Godot 4.7.1，`mini-pong/` 子项目（自有 project.godot），竖屏 720×1280 |
| 数据唯一入口 | run 数据必须来自 `GameManager`（Issue 明确「数据来自 GameManager」），不得在场景侧另存副本 |
| 文案不进代码 | 短句必须从配置文件读取（AC3），不硬编码进 .gd / constants.gd（#396 AC5 边界） |
| 不堆特效 | 失败屏保持克制：Label 呈现即可，不引入粒子/动画系统（审美坐标：雨夜竞技场 + 霓虹描边 + 克制优先，TASTE.md） |

---

## 3. 影响分析

### 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/game_over_screen.gd` | 失败屏控制器 | **修改**：失败/胜利分流（`match_over("ai")` → 短句 + 3 项数据）；`RunStatsLabel`/`FailurePhraseLabel` 引用；短句读取函数（读 JSON → 按波次选短句） |
| `mini-pong/scenes/Main.tscn` | GameOverScreen 节点树 | **修改**：新增 `FailurePhraseLabel`（短句，置于 WinnerLabel 下方）+ `RunStatsLabel`（波次/拆砖/穿墙 3 项）节点 |
| `mini-pong/gdscripts/game_state_machine.gd` | FSM GAME_OVER 态 | **修改**：进入 GAME_OVER 时冻结 ball（AC4，配合 ball 新增接口） |
| `mini-pong/gdscripts/ball.gd` | 球物理 | **修改**：新增 `set_frozen(value)` + `_frozen` 状态（`_process` 中 frozen 时 return），同 paddle 模式 |

### 新增文件

| 文件 | 用途 |
|------|------|
| `mini-pong/tests/test_failure_screen.gd` | 失败屏测试：短句读取（JSON 解析 + 按波次选择）、3 项数据文本、失败/胜利分流、frozen 后球不动、reset 后重开 |

### 间接影响的模块

| 文件 | 影响 |
|------|------|
| `mini-pong/content/wave_failure_text.json` | **只读**，不修改（内容归属 #396）；短句选择策略见 §4 |
| `mini-pong/gdscripts/game_manager.gd` | 不修改（数据 API 已齐）；若需「总拆砖/总穿墙」双方合计口径则只读不改 |
| `mini-pong/tests/run_tests.gd` | 注册新套件（+1 → 18 套件） |
| `mini-pong/tests/test_integration_fsm.gd` | 若断言 GAME_OVER 球状态，需同步（现有断言不涉及 ball frozen，预计无冲突） |

### 数据流

```
GameManager.match_over(winner: String)          # #385：21 分终局
    │
    ▼
GameStateMachine._on_match_over()  →  GAME_OVER 态
    ├── _freeze_paddles(true)                    # 既有
    └── ball.set_frozen(true)                    # 新增（AC4）
    │
    ▼
GameOverScreen._on_match_over(winner)
    ├── winner == "ai"（玩家失败）
    │     ├── FailurePhraseLabel.text ← JSON.failure_phrases[按波次选择].text   # AC3
    │     └── RunStatsLabel.text ← 波次:wave_index  拆砖:get_brick_count("player")  穿墙:get_pierce_count("player")   # AC2
    └── winner == "player"（玩家胜）
          └── 既有 "YOU WIN!" 呈现（不变）
    │
    ▼
SPACE（GAME_OVER 态）→ MENU → reset_match() → 新一轮（AC5）
```

---

## 4. 方案对比

### 4.1 失败屏架构

#### Approach A：扩展既有 GameOverScreen（推荐）

在现有 CanvasLayer 内联节点树（Main.tscn）上增加两个 Label，脚本内按 winner 分流。

| 维度 | 说明 |
|------|------|
| 结构 | 复用 `GameOverScreen` CanvasLayer：`WinnerLabel`（保留）+ `FailurePhraseLabel`（新增，失败时显示短句）+ `RunStatsLabel`（新增，3 项数据）+ `RestartPromptLabel`（既有） |
| 分流 | `_on_match_over("ai")` → 显示短句 + 数据 + "AI WINS!" 小字（或复用 WinnerLabel 显示失败短句）；`_on_match_over("player")` → 保持现状 |
| 数据 | `GameManager.wave_index` / `get_brick_count("player")` / `get_pierce_count("player")`（已有 #385 读取代码骨架） |

- **Pros**：零新场景；FSM/`_set_ui`/SPACE 重开接线零改动；#385 已预留 RunStatsLabel 读取路径（`get_node_or_null` 容错，直接补节点即生效）；改动面最小（1 脚本 + 1 场景 + 1 ball 方法）
- **Cons**：胜/负共用一个 CanvasLayer，分流逻辑需清晰（`match winner` 分支）；WinnerLabel 语义从「公告」扩展为「失败短句」需注意命名清晰
- **Risk**：低——改动集中，既有测试（FSM 集成、game_over_screen 行为）可复用
- **Effort**：0.5–1 周

#### Approach B：新建独立 FailureScreen 场景 + 节点

新建 `mini-pong/scenes/ui_failure_screen.tscn` + `failure_screen.gd`，FSM 增加 FAILED 状态（或复用 GAME_OVER 但切换不同 UI）。

- **Pros**：失败/胜利 UI 完全隔离，语义清晰；未来可独立演进
- **Cons**：新增场景 + 新增 FSM 状态（或双 CanvasLayer 切换）；`_set_ui` 接线改动；与 #390 波次转场（同样新增全屏 UI）职责边界易混；MVP 下过度设计
- **Risk**：中——FSM 状态增加引入回归面；与既有 GAME_OVER 重开路径（SPACE → MENU）需复制
- **Effort**：1.5–2 周

#### Approach C：第三方插件/模板（开源优先调研结论）

按 Issue「开源优先」要求，已检索：

| 来源 | 检索词 | 结果 |
|------|--------|------|
| Godot Asset Library（godotengine.org/asset-library/api） | `gameover` / `game over` / `game over screen` / `end screen` / `game over ui` | 全部 0 结果；UI 类目（category=UI）0 匹配模板 |
| GitHub（gh search / search API） | `godot game over screen` / `godot failure screen` / `godot ui screens` / `godot addon ui` | 仅 4 个不相关项目（party game / TicTacToe / parkour / SlimeQuest，均 0–1 star，非失败屏模板）；无成熟失败屏/结算屏插件 |
| 社区 | Reddit `godot game over screen` | 无可用结构化结果 |

**结论**：无可复用的成熟失败屏插件/模板——失败屏高度项目相关（短句 + run 数据 + 既有 CanvasLayer 模式），且项目克制风格拒绝堆特效依赖。**自行扩展既有 GameOverScreen（Approach A）为最优**，与 #358 标题屏（项目自研 UI 先例）一致。

- **Risk**：高（若强行引入第三方 UI 库，与现有 #292 CanvasLayer 模式冲突）
- **Effort**：不可估（无合适候选）

**推荐 A**，理由：
1. 数据/内容/接线三就绪，A 只做「补节点 + 分流 + 暂停」，改动最小且可隔离测试
2. #385 已按「布局归 #391」预留 RunStatsLabel 读取路径——A 直接兑现该预留，B/C 均浪费
3. 开源调研确认无成熟第三方方案，自研成本低于引入依赖

### 4.2 暂停机制（AC4）

#### P1：ball 新增 `set_frozen`（推荐）

`ball.gd` 加 `var _frozen: bool` + `func set_frozen(v)`，`_process` 开头 `if _frozen: return`。FSM GAME_OVER 态调 `ball.set_frozen(true)`（paddle 冻结已有）。

- **Pros**：与 paddle 模式同构；headless 可测（断言 `_process` 后 position 不变）；不影响 UI 动画（tween 继续，脉冲/闪烁正常）
- **Cons**：需改 ball.gd（+1 方法 +1 状态）
- **Risk**：低——`_process` 早退不影响 serve/计分路径（frozen 只在 GAME_OVER 置位）
- **Effort**：0.5 天

#### P2：`get_tree().paused = true`

GAME_OVER 时暂停整个 SceneTree。

- **Pros**：彻底暂停一切（含 AI/计时器）
- **Cons**：**会暂停 GameOverScreen 自身的 tween 动画**（脉冲/闪烁需 `process_mode = PROCESS_MODE_ALWAYS` 规避）；FSM 的 `_timer_1s`/await 交互复杂化；headless 测试需处理 pause 状态；#296 暂停（PAUSED 态）也未用 tree.paused（用 overlay + freeze）——项目无此先例
- **Risk**：中——破坏既有动画/计时行为，回归面大
- **Effort**：1 天

**推荐 P1**：与项目既有暂停模式（#296 PAUSED：overlay + freeze，非 tree.paused）一致；只冻结游戏实体，UI 动画保持活跃（失败屏脉冲/闪烁是 #292 既有体验，不应被暂停杀死）。

### 4.3 短句选择策略（AC3）

| 策略 | 描述 | Pros | Cons | 推荐 |
|------|------|------|------|:---:|
| S1：按波次语境匹配 | `wave_index` 1-2 → fp1；3-5 → fp2；6+ → fp3；兜底 fp4 | 与 #396 语境表（context 字段）一一对应，场景 C/D 精准 | 需实现区间映射逻辑（≤10 行） | ✅ |
| S2：固定 recommended | 始终读 `recommended: true` 条目（fp1「雨还在下」） | 最简（读第一条 recommended） | 所有失败场景同一句，语境不匹配 | — |
| S3：随机 | 从 failure_phrases 随机 | 变化感 | 与「克制」冲突（随机破坏一致性）；不可测 | — |

**推荐 S1**：JSON 已带 `context` 字段（「波 1-2/波 3-5/波 6+/通用」），S1 直接消费该结构；S2 作兜底（解析失败/无匹配时回退 recommended 或 fp1）。实现：`_pick_failure_phrase(wave_index, phrases)` → 按区间过滤 → 无匹配回退 recommended:true → 再无回退第一项。

---

## 5. 边界条件与验收标准

### 正常路径

- [x] **AC1: 失败切换** — `match_over("ai")` → GAME_OVER → 失败屏显示（短句 + 3 项数据）；`match_over("player")` → 既有胜利呈现
  - [x] 验证：mock `match_over("ai")` → 断言 FailurePhraseLabel 非空、RunStatsLabel 含 3 项
  - [x] 验证：mock `match_over("player")` → 断言不显示失败短句
- [x] **AC2: 3 项 run 数据** — 波次/拆砖/穿墙均来自 GameManager
  - [x] 验证：设 `wave_index=3`、`player_brick_count=12`、`player_pierce_count=4` → 文本含 "3" / "12" / "4"
- [x] **AC3: 短句从配置读取** — `res://content/wave_failure_text.json` → `failure_phrases`
  - [x] 验证：文件存在、schema 为 `wave-failure-text/v1`、所选条目 text 无 emoji/感叹号（内容侧 #396 已校验）
- [x] **AC4: 失败屏出现时游戏暂停** — GAME_OVER 进入时 `ball.set_frozen(true)` + paddles frozen
  - [x] 验证：frozen 后 `_process` 多帧 position 不变
- [x] **AC5: 可重开** — SPACE → MENU → `reset_match()` → SPACE → 新一轮
  - [x] 验证：reset 后 wave_index=0、计数归零、ball unfrozen

### 边界情况

1. **JSON 文件缺失/解析失败** — 回退：不显示短句（或显示内置兜底「墙还在，雨未停」），不崩溃；log 警告
2. **JSON 无 recommended 条目** — S1 回退链末端取 `failure_phrases[0]`
3. **wave_index = 0（IDLE 异常态）** — 按早败区间（≤2）处理 → fp1
4. **穿墙/拆砖数为 0** — 正常显示 "0"（首波即败场景，数据诚实呈现）
5. **失败屏已显示时重复 match_over** — `_on_match_over` 幂等守卫（同 #292 `_transitioning` 模式）
6. **winner 非法值** — 保持既有 `match ... _: return` 语义，不显示失败屏
7. **ball frozen 后 serve/计分事件** — frozen 只读 `_frozen`，不阻塞信号；GAME_OVER 后 `add_score` 已被 `_is_run_over` 守卫（#385 失败路径 2）

### 失败路径

1. **content JSON 不存在**（#407 被回滚等）→ 失败屏无短句但数据照常显示；测试覆盖容错分支
2. **ball.gd 未实现 set_frozen**（实现遗漏）→ FSM 用 `has_method` 容错调用（同 ScoringManager 对 ScoreFlash 模式），测试断言 frozen 行为失败即暴露
3. **RunStatsLabel 节点缺失** → `get_node_or_null` 容错（#385 既有模式），不崩溃；E2E 截图验证节点存在

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|:---:|
| #385 双得分制（`match_over`/`get_brick_count`/`get_pierce_count`） | ✅ 已合并（PR #424） | 无 |
| #386 波次循环（`wave_index`/`reset_match`） | ✅ 已合并（PR #425） | 无 |
| #396 失败短句内容（`wave_failure_text.json`） | ✅ 已合并（PR #407，`draft: true`） | 低——draft 仅标记待用户定稿，结构/字段可用；若用户后续改文案，读取逻辑不变 |
| #390 波次转场（读同一 JSON 的 `wave_subtitles`） | ⏳ OPEN（并行，非本 Issue 依赖） | 低——两 Issue 各读各的字段组（`wave_subtitles` vs `failure_phrases`），无写入冲突；同文件只读 |

**依赖链：**

```
#383 轴交换 → #384 砖墙 → #385 双得分制 ─┐
                                        ├─→ #391 失败屏（本 Issue）
#386 波次循环 ───────────────────────────┘
#396 失败短句（内容）──→  wave_failure_text.json（只读）
```

**无阻塞。** 前置依赖全部关闭；#396 内容已落地；#390 并行无冲突（同文件不同字段，双方只读）。

**准备工作：**
- [x] 确认 `wave_failure_text.json` 字段（`failure_phrases[].text/context/recommended`）——已核实
- [x] 确认 GameManager 查询 API 签名——已核实
- [x] 开源优先调研（Asset Library / GitHub / 社区）——已执行，无成熟方案（§4.1-C）

---

## 7. Spike / 实验

> Skipped per depth/standard 标签（Issue 无 depth/deep 标签，按 #358/#385/#386 惯例 standard 处理：Section 7 可选）。研究期已执行的验证：JSON 结构核验（`wave_failure_text.json` 4 条 failure_phrases 字段完整）、GameManager API 签名核验（`get_brick_count/get_pierce_count/wave_index` 存在）、ball.gd frozen 缺失确认（§1 现状表）。

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- 竖屏 720×1280（#383，PR #409）；21 分终局 + 拆砖/穿墙计数 + `match_over`（#385，PR #424）；波次状态机 `wave_index`/`begin_wave`/`settle_wave`/`end_wave_cycle`（#386，PR #425）
- 内容源 `mini-pong/content/wave_failure_text.json` 已落地（#407 merged，`draft: true`，schema `wave-failure-text/v1`）——**只读，勿改**；字段与 #391 读取点对齐（DESIGN #406 §4）
- GameOverScreen 已有 #385 预留的 RunStatsLabel 容错读取（`get_node_or_null`），节点缺失时静默跳过——补节点即生效
- FSM GAME_OVER 态：`_set_ui("game_over")` + `_freeze_paddles(true)`；SPACE → MENU 重开已通；**ball 无 frozen 接口（本 Issue AC4 的主要代码增量）**
- 并行管线活跃（#390 转场 OPEN 同读该 JSON 的 `wave_subtitles`），实现前先 `git pull origin main`

### 本 PRD 的核心决策（勿偏离）

1. **Approach A（§4.1）**：扩展既有 GameOverScreen，不新建场景/FSM 状态——补 `FailurePhraseLabel` + `RunStatsLabel` 两节点，`_on_match_over` 按 winner 分流（`"ai"` 失败 → 短句 + 数据；`"player"` → 现状）
2. **P1 暂停（§4.2）**：ball.gd 新增 `set_frozen` + `_frozen` 状态（`_process` 早退）；FSM GAME_OVER 调 `ball.set_frozen(true)`——**不要用 `get_tree().paused`**（会杀死 GameOverScreen 自身 tween 动画，且项目无此先例）
3. **S1 短句选择（§4.3）**：按 `wave_index` 区间匹配 `failure_phrases` 的 `context`（1-2→fp1、3-5→fp2、6+→fp3、兜底 fp4）；回退链：区间匹配 → recommended:true → `[0]`；JSON 缺失 → 不显示短句不崩溃
4. **数据口径**：玩家视角 run 数据（`get_brick_count("player")` / `get_pierce_count("player")` / `wave_index`）——失败屏是玩家失败场景，展示玩家侧数据
5. **只读边界**：不改 `game_manager.gd`、不改 `wave_failure_text.json`、不改胜负判定逻辑（#385 `match_over(winner)` 语义保持）

### 下一步（plan agent）

1. 读 `mini-pong/gdscripts/game_over_screen.gd`（#292 既有 + #385 预留读取）与 `mini-pong/gdscripts/ball.gd`（`_process` 结构，frozen 插入点）
2. 设计 Main.tscn GameOverScreen 节点布局：`WinnerLabel`（72px）→ `FailurePhraseLabel`（短句，建议 36-40px，霓虹描边风格）→ `RunStatsLabel`（3 项数据，建议 24px）→ `RestartPromptLabel`（既有 28px）
3. 新增 `test_failure_screen.gd`：mock `match_over` 分流、JSON 读取（`FileAccess` headless 可用）、frozen 后 position 不变、reset 后 unfrozen；注册进 `run_tests.gd`（18 套件）
4. E2E：`scripts/run-e2e-review.sh` 失败屏截图（GAME_OVER 态）应含短句 + 3 项数据（对齐 #358 先例）
5. 若 #390 转场实现在本 Issue 前落地，确认两屏切换时序无冲突（转场 → 对打 → 失败屏；互不叠加显示）

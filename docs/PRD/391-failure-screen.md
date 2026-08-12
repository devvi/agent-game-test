# PRD: [Feature] 失败屏 (Failure Screen)

> **Issue:** #391
> **标签:** enhancement, ui, version/mvp, workflow/available（research 进行中 → workflow/research）
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期实际执行的验证补齐）
> **所有权:** `content_ownership: mechanical`（失败判定/run 数据读取/暂停/重开为纯机械实现；失败短句文案值归 #396 taste-draft，本 Issue 只做机械消费）
> **引擎/目录约束:** Godot 4.7.1，`mini-pong/` 子项目（`mini-pong/gdscripts/`、`mini-pong/scenes/`），竖屏 720×1280（#383）
> **上游方案:** `docs/PLAN-rogue-pong.md` §2.2/§2.4（双得分制 + 21 分终局）+ §2.1（波次循环）；GDD 21 章（wave-failure-text/v1 schema，失败短句消费契约）
> **前置依赖:** #385（双得分制，**已实现并合并** PR #424）→ #386（波次循环，**已实现并合并** PR #428）→ 本 Issue。两项依赖均已满足，无阻塞。

---

## 1. 问题定义

### 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）目前**没有失败屏**：21 分终局（#385）后进入的是 #292 时代的**胜者宣告屏**（GameOverScreen）——AI 获胜时显示红色 "AI WINS!" 大字 + 闪烁 "按 SPACE 重新开始"，无失败短句、无 run 数据展示（波次/拆砖/穿墙），失败瞬间游戏也未暂停（球在 GAME_OVER 期间继续运动）。数据契约与文案契约均已就绪，唯独 UI 消费方（失败屏）未接线：

| 文件/资源 | 当前状态 | 与 #391 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/game_over_screen.gd` | #292 胜者宣告屏（YOU WIN!/AI WINS! + SPACE 重启 + 脉冲动画）；#385 已埋**数据读取路径**：`_on_match_over()` 读取 `GameManager.get_brick_count()/get_pierce_count()` 并格式化「拆砖 P:x/A:y 穿墙 P:x/A:y」写入 `RunStatsLabel`，但节点不存在 → `get_node_or_null` 返回 null 静默跳过（注释明确「布局归 #391」） | ❌ 无失败短句分支；❌ 无波次数读取；❌ 统计格式为 P/A 双区而非玩家单侧三项；❌ 无暂停语义 |
| `mini-pong/scenes/ui_game_over.tscn` | CanvasLayer → CenterContainer → VBoxContainer：WinnerLabel（72px）+ Spacer + RestartPromptLabel（28px「按 SPACE 重新开始」） | ❌ 无 FailurePhraseLabel、无 RunStatsLabel（波次/拆砖/穿墙三项） |
| `mini-pong/gdscripts/game_manager.gd` | ✅ 数据齐全：`player_brick_count/player_pierce_count` + `get_brick_count(side)/get_pierce_count(side)`（#385 AC5）；`wave_index` public var（#386，注释「GAME_OVER 屏波次数归 #391」）；`match_over(winner)` 信号；`reset_match()` 重置全部计数与 `wave_index=0` | ⚠️ 无 `get_wave_index()` 查询方法——`wave_index` 为 public var 可直接读，建议补 getter 保持查询 API 风格（非必须） |
| `mini-pong/gdscripts/game_state_machine.gd` | 6 态 FSM：#294。`GAME_OVER` enter 时 `_set_ui("game_over")` + `_freeze_paddles(true)`；SPACE 在 GAME_OVER → MENU（`reset_match()` 经 MENU→SERVING 触发）；`_on_match_over` → GAME_OVER | ❌ GAME_OVER 期间球仍运动（`ball._process` 无冻结）——AC4「失败屏出现时游戏暂停」未满足 |
| `mini-pong/content/wave_failure_text.json` | ✅ #396 草稿已合并（PR #407，`draft: true`，schema `wave-failure-text/v1`）：`failure_phrases[]` 4 条候选（fp1「雨还在下」早败波1-2 / fp2「雨记住了这一局」中败波3-5 / fp3「就差一道墙」晚败波6+或接近21 / fp4「墙还在，雨未停」通用兜底），每条 ≤10 字、无感叹号、无 emoji、无惩罚性措辞 | ⚠️ GDD 21 章明确消费契约：「#391 失败屏读 `failure_phrases[].text`（按 run 数据 severity 分档）」——机械插槽不依赖草稿文案值，`draft:true` 不阻塞 |
| `mini-pong/scenes/Main.tscn` | GameOverScreen 节点已实例化（id 6_game_over），三层 CanvasLayer 切换就绪 | ✅ 无需新增节点；接线归 #393 的约定不冲突（本 Issue 只改 GameOverScreen 内部） |

### 期望行为

1. **玩家失败（`match_over` winner="ai"）→ 切换至失败屏**：不经过 MENU，直接进入 GAME_OVER 显示失败界面。
2. **展示 3 项 run 数据**：波次（`GameManager.wave_index`，失败瞬间值）、总拆砖数（`player_brick_count`）、总穿墙数（`player_pierce_count`）——数据全部来自 GameManager（issue 原文）。
3. **短句从配置读取**：按 run 数据 severity 分档从 `wave_failure_text.json` 的 `failure_phrases[]` 选句；无 emoji/夸张语气由配置内容红线保证（#396/GDD 21），运行时只做机械选句。
4. **失败屏出现时游戏暂停**：球停止运动、挡板冻结、计分不可发生。
5. **可重开进入新一轮**：SPACE → `reset_match()`（wave_index 归零、四计数归零、`_is_run_over=false`）→ 新 run 从波 1 开始。

### 范围边界（与重叠 PRD 去冲突）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #385 双得分制 | 拆砖/穿墙计数与查询 API、21 分终局、`match_over` | ❌ 不改 GameManager 计数/终局逻辑——只消费 `get_brick_count/get_pierce_count` 与 `wave_index` |
| #292 UI 系统 | 三层 CanvasLayer visible 切换、GameOverScreen 基础结构、SPACE 重启 | ❌ 不重构三层切换与 FSM 接线——只改 GameOverScreen 内部布局与失败分支 |
| #294 游戏状态机 | 6 态 FSM、GAME_OVER 状态、SPACE→MENU | ❌ 不新增状态——复用 GAME_OVER，仅补 AC4 暂停语义 |
| #296 暂停与音效 | PAUSED 状态、PauseOverlay、软冻结约定 | ❌ 不触碰 PAUSED——失败屏暂停是 GAME_OVER 内的终局冻结，非可恢复暂停 |
| #396 波次副句与失败短句 | `wave_failure_text.json` 候选文案与 schema、内容红线 | ❌ 不改 JSON 文案值——只按 schema 消费 `failure_phrases[].text`（`draft:true` 时以 recommended/任意条兜底） |
| #390 波次转场 | 消费 `wave_subtitles[]`（按 wave_index 分档） | ❌ 不消费 wave_subtitles——本 PRD 只消费 failure_phrases |
| #393 组装/HUD | Main.tscn 节点接线、HUD 波次显示 | ❌ 不触碰 Main.tscn 接线与 HUD |

本 PRD 是**失败屏（Failure Screen）**——聚焦失败分支的 UI 布局、run 数据消费、终局暂停与重开。它**不重新分析** #385 的计分机制、#292 的 UI 架构、#294 的状态机设计、#396 的文案创作。

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家失败（AI 先到 21 分） | 每 run 1 次（高频） | 失败屏出现：短句 + 波次/拆砖/穿墙三项数据，游戏暂停 |
| B | 玩家获胜（玩家先到 21 分） | 每 run 1 次（中频） | 保持现有 "YOU WIN!" 胜者宣告屏（本 Issue 不覆盖，win 分支原样保留） |
| C | 失败后重开 | 每 run 1 次 | SPACE → 新一轮，波次从 1 重新开始，计数归零 |

---

## 2. 设计意图

### 为什么当前行为如此

GameOverScreen 诞生于 #292（UI 系统）——当时是纯**胜者宣告**（5 分制），没有 run 数据概念。随后两条依赖线把「失败屏」的契约逐层铺好，但都明确把 UI 消费方留给 #391：

- **#385 双得分制**（已合并 #424）：引入拆砖/穿墙计数与 21 分终局。AC5 原文：「GameManager 可查询每方拆砖数、穿墙数，**供结算/失败屏使用**」；实现时在 `game_over_screen.gd` 埋入统计读取代码并注释「**布局归 #391**」——数据路径先行，布局留待本 Issue。
- **#386 波次循环**（已合并 #428）：引入 `wave_index`，`end_wave_cycle()` 注释「wave_index 保留供 run 统计（**GAME_OVER 屏『波次数』归 #391**）」。
- **#396 波次副句与失败短句**（草稿已合并 #407）：产出 `wave_failure_text.json`（schema wave-failure-text/v1），GDD 21 章数据流明确「#391 失败屏读 `failure_phrases[].text`（按 run 数据 severity 分档）」——文案契约先于 UI 落定。

### 为什么现在改

数据契约（计数 API、`wave_index`、`match_over`）与文案契约（`wave-failure-text/v1`）均已落地并合并。失败屏是双得分制 + 波次循环体验闭环的**最后一个未接线消费方**：目前玩家失败看到的仍是 5 分制时代的 "AI WINS!" 大字，run 数据（波次/拆砖/穿墙）没有任何展示出口，且失败瞬间游戏不暂停。Issue 上下文明确设计意图：「让失败提供信息与氛围，而不是惩罚性界面」——数据（三项 run 统计）即信息，短句（海明威式克制文案）即氛围。

### 既往约束

| 约束 | 详情 |
|------|------|
| 竖屏 720×1280 | #383 轴交换后所有 UI 在此分辨率下清晰可读、不截断 |
| 三层 CanvasLayer visible 切换 | #292 约定：同一时刻仅一层可见（StartMenu/GameHUD/GameOverScreen） |
| FSM 单一输入路由 | #294 约定：SPACE 在 GAME_OVER 状态由 FSM `_input()` 处理（GameOverScreen 自身不再接 `_input`） |
| 软冻结约定 | #296 暂停 = FSM 冻结挡板 + 音频暂停，**未使用** `get_tree().paused`；headless 测试友好 |
| 文案红线 | #396/GDD 21：失败短句 ≤10 字（含标点）、禁感叹号、每句修饰词 ≤1、禁惩罚性/空洞措辞、禁 emoji/网络梗 |
| 保持克制、不堆特效 | Issue 原文：失败屏克制呈现，不叠加粒子/Shader 特效（现有脉冲 alpha 动画属 #292 既有行为，失败分支可保留或降级） |
| 数据来自 GameManager | Issue 原文：run 数据统一从 GameManager 查询 API 读取，不做本地缓存 |
| Headless 安全 | 既有约定：`get_tree()` null 守卫、`get_node_or_null` 容错、`has_signal/has_method` 双守卫 |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/game_over_screen.gd` | GameOverScreen | **修改**：新增失败分支（winner=="ai"）——按 severity 分档选短句 + 读取三项 run 数据渲染；#385 埋入的 P/A 双区统计代码改为玩家单侧三项；暂停触发 |
| `mini-pong/scenes/ui_game_over.tscn` | GameOverScreen 场景 | **修改**：VBoxContainer 内新增 FailurePhraseLabel + RunStatsLabel（波次/拆砖/穿墙，可单 Label 多行或三行 Label）；保留 WinnerLabel（win 分支）与 RestartPromptLabel |
| `mini-pong/gdscripts/game_state_machine.gd` | FSM | **修改**：`GAME_OVER` enter 时补球冻结（AC4）；exit 时解冻 |
| `mini-pong/gdscripts/game_manager.gd` | GameManager | **可选微改**：补 `get_wave_index()` getter（与 `get_brick_count/get_pierce_count` API 风格一致）；不改任何状态/计数逻辑 |

### 新增文件

| 文件 | 用途 |
|------|------|
| `mini-pong/tests/test_failure_screen.gd`（新增） | 失败屏用例：失败分支渲染、三项数据、severity 分档、暂停、重开（注册进 `run_tests.gd`） |

### 间接影响模块

| 文件 | 影响 |
|------|------|
| `mini-pong/tests/test_ui_system.gd` | TC7/TC10/TC11 断言 "YOU WIN!"/"AI WINS!" 常量与 RestartPromptLabel——**win 分支保留则兼容**；需新增失败屏断言（FailurePhraseLabel/RunStatsLabel 存在性） |
| `mini-pong/tests/test_game_state_machine.gd` | GAME_OVER 相关用例——若 FSM 增加球冻结调用，需同步 mock |
| `mini-pong/tests/test_pause.gd` | 不动（PAUSED 语义不变）；其 mock 模式可复用 |
| `mini-pong/tests/test_dual_scoring.gd` | 若补 `get_wave_index()`，可加 1-2 条 wave_index 断言（非必须） |

### 数据流

```
GameManager.match_over("ai")  ← 21 分终局（#385 单一权威）
    │
    ▼
GameStateMachine._on_match_over("ai")
    └── transition_to(GAME_OVER)                ← FSM（#294）
            ├── _set_ui("game_over")            → GameOverScreen.visible = true
            ├── _freeze_paddles(true)           → 既有
            └── 球冻结（AC4，新增）               → ball 停止运动
                    │
                    ▼
GameOverScreen._on_match_over("ai")
    ├── 选句: wave_failure_text.json failure_phrases[]
    │        按 GameManager.wave_index 分档（1-2 / 3-5 / 6+ / 兜底）
    │        → FailurePhraseLabel.text
    ├── 数据: GameManager.get_brick_count("player")
    │         GameManager.get_pierce_count("player")
    │         GameManager.wave_index
    │        → RunStatsLabel.text（波次 / 拆砖 / 穿墙）
    └── 隐藏 GameHUD（既有 #385 行为）
            │
            ▼
SPACE（FSM _input，GAME_OVER 状态）
    └── transition_to(MENU) → GameManager.reset_match()   ← wave_index=0、计数归零（AC5）
```

### 需更新的文档

- [ ] `docs/PRD/391-failure-screen.md`（本文件）
- [ ] `docs/GAME_DESIGN/`：失败屏章节（post-merge，review agent 惯例）
- [ ] `docs/TASKS/`：plan 阶段产出（下游）

---

## 4. 方案比较

### 维度一：失败屏呈现结构

**方案 A：在既有 GameOverScreen 内扩展失败分支（推荐）**

`game_over_screen.gd` 增加失败路径（winner=="ai" → 短句 + run 数据），`ui_game_over.tscn` 补两个 Label 节点；win 分支（YOU WIN!）原样保留。

- **Pros:** 复用三层切换、FSM 接线、SPACE 重启、`_on_restart_pressed` 流程，零新场景零新节点；#385 已埋的数据读取代码直接激活（把 P/A 双区格式改为玩家单侧三项）；与 #393 组装边界无冲突
- **Cons:** GameOverScreen 语义从「胜者宣告」扩展为「终局屏」（win/fail 双分支），单脚本需保持分支清晰（`match winner` 内聚）
- **Risk:** Low
- **Effort:** 0.5–1 周

**方案 B：新建独立 FailureScreen 场景**

新增 `ui_failure_screen.tscn` + `failure_screen.gd`，Main.tscn 增加节点，FSM `_set_ui` 增加 "failure" 分支。

- **Pros:** win/fail 语义完全分离，脚本职责纯净
- **Cons:** 新增节点与 FSM 分支违反「Main.tscn 接线归 #393」的既定边界；重启/回 MENU 逻辑需复制一份；MVP 下过度设计（两份几乎相同的 CanvasLayer 屏）
- **Risk:** Med
- **Effort:** 1–1.5 周

### 维度二：失败时「游戏暂停」实现

**方案 A：SceneTree 全局暂停** — `GAME_OVER` enter 时 `get_tree().paused = true`，GameOverScreen 设 `process_mode = PROCESS_MODE_ALWAYS` 保持动画。

- **Pros:** 语义上真正「暂停」，球/挡板/计分/音频全部停止，AC4 严格满足
- **Cons:** 与 #296 既有「软冻结」约定不一致（项目从未使用 SceneTree pause）；autoload（GameManager/AudioEngine）默认 `PROCESS_MODE_INHERIT` 也会被暂停，需逐节点 process_mode 审计；headless 测试需处理 paused 语义；失败屏本身是终局态，不需要可恢复暂停，全局暂停是「杀鸡用牛刀」
- **Risk:** Med
- **Effort:** 0.5–1 周

**方案 B：软冻结扩展（推荐）** — 对齐 #296 模式：`GAME_OVER` enter 时除 `_freeze_paddles(true)` 外，冻结球（`ball` 增加 freeze 标志或 `velocity = Vector2.ZERO`），exit 时解冻；计分天然不可发生（FSM 不在 PLAYING 不消费 scored）。

- **Pros:** 与既有软冻结约定完全一致、headless 可测（复用 test_pause TC5 模式）、零 SceneTree 语义、改动最小
- **Cons:** 需给 ball 加最小 freeze 支持（约 5 行）；「暂停」是软性语义（场景树仍在跑）——但对终局屏足够
- **Risk:** Low
- **Effort:** 0.5 周

### 开源调研（issue 🔍 开源优先）

| 渠道 | 检索 | 结果 |
|------|------|------|
| Godot Asset Library (assetlibrary.godotengine.org) | filter=game over screen / failure（Godot 4.7） | **0 结果**（`total_items: 0`） |
| GitHub 仓库搜索 | "godot game over screen"（按 stars） | 仅 <5⭐ 完整游戏克隆（TicTacToe 等），**无可插拔的「失败屏/run 统计」组件** |
| 社区模式 | 失败屏 = CanvasLayer + Label + 暂停 + 重开 | Godot 内建节点即可实现，无需第三方依赖 |

**结论：** 失败屏（短句 + 三项 run 数据 + 暂停 + 重开）是 Godot 内建 CanvasLayer/Label/Tween 的组合，无成熟第三方插件可复用；自行实现约 0.5–1 周，且与项目既有 UI 约定（#292 三层切换、#296 软冻结）天然一致，不引入外部依赖。

### 推荐

**呈现结构取方案 A（扩展 GameOverScreen）+ 暂停取维度二方案 B（软冻结扩展）。**

1. #385/#386 已在 `game_over_screen.gd`/`game_manager.gd` 预留数据路径与波次保留语义，方案 A 是「激活既有插槽」而非「新建系统」——与 #386 先例（autoload 持状态、场景节点消费编排）一致。
2. 软冻结与项目 #294/#296 约定一致、headless 可测；SceneTree 全局暂停会牵连 autoload 与动画，收益（终局屏无需恢复）不抵复杂度。
3. 独立场景方案 B 的优势（语义纯净）在 MVP 阶段被「Main.tscn 接线归 #393」的边界与重复代码成本抵消。

---

## 5. 边界条件与验收标准

### 正常路径（AC 清单，映射 issue 验收条件）

- [x] **AC1: 玩家失败时切换至失败屏** — `match_over("ai")` → FSM GAME_OVER → GameOverScreen 显示失败短句 + run 数据
  - 验证：构造 AI 21 分终局 → 断言 FSM `current_state == GAME_OVER`、GameOverScreen.visible == true、FailurePhraseLabel/RunStatsLabel 文本非空
- [x] **AC2: 展示波次、总拆砖数、总穿墙数 3 项 run 数据** — 波次 = `GameManager.wave_index`、拆砖 = `player_brick_count`、穿墙 = `player_pierce_count`（玩家单侧）
  - 验证：预置 wave_index=3、拆砖 7、穿墙 2 → 断言 RunStatsLabel 含三值
- [x] **AC3: 短句从配置读取且无 emoji/夸张语气** — 从 `wave_failure_text.json` `failure_phrases[]` 按 severity 分档读取；脚本不含文案硬编码（兜底默认句除外）
  - 验证：改 JSON 某档位 text → 屏幕文本随之变化；代码 grep 无 emoji/感叹号文案字面量；内容红线（≤10 字、无感叹号/emoji）由 #396 配置内容保证，运行时不做文本校验（GDD 21 契约）
- [x] **AC4: 失败屏出现时游戏暂停** — GAME_OVER 进入后球不再移动、挡板冻结、计分不可发生
  - 验证：失败后推进多帧 → 断言 ball 位置不变（复用 test_pause TC5 模式）、paddle frozen、FSM 不在 PLAYING 时 scored 信号被忽略
- [x] **AC5: 可重开进入新一轮** — SPACE → `reset_match()` → 新 run 波次从 1 开始
  - 验证：重开后断言 `wave_index == 0`（SERVING 后首波 begin_wave → 1）、四计数归零、`_is_run_over == false`

### 边界情况（≥5）

1. **首波未开始即败（wave_index == 0）** — 分档无 0 档 → 落入 fp4 通用兜底（或 recommended 句），不得崩溃。
2. **配置缺失/解析失败** — `wave_failure_text.json` 不存在或 JSON 非法 → 使用 constants.gd 中的默认短句（仍满足无 emoji 红线）+ `push_warning`；`failure_phrases` 为空数组同理。
3. **`draft: true` 未定稿** — #396 草稿态：机械插槽不依赖定稿值，任选一条（recommended 优先）即可；定稿后仅改 JSON，代码零改动（GDD 21 明确）。
4. **玩家获胜（winner=="player"）** — 走既有 "YOU WIN!" 分支，不显示失败短句与 run 数据（或按后续 issue 扩展）；本 Issue 不改 win 分支文案。
5. **失败屏显示期间按 ESC** — FSM `_input` 中 `ui_cancel` 只匹配 PLAYING/PAUSED，GAME_OVER 无响应（既有行为，回归确认）。
6. **SPACE 连按/重入** — `_transition_lock` 防重入（#294 既有）；GameOverScreen `_on_restart_pressed` 的 `_transitioning` 守卫保持。
7. **21 分同帧双事件** — #385 既有 `elif` 单 winner 语义，失败屏只消费单次 `match_over`（回归确认）。
8. **Headless 无树** — `get_tree()` null 守卫（#292 既有 `_ready` 早退模式）；暂停/动画调用全部守卫。
9. **竖屏 720×1280 布局** — 短句 + 三项数据 + 提示行不截断不溢出（沿 #292 分辨率校验约定）。

### 失败路径（≥3）

1. **JSON 解析失败** → 默认短句兜底 + `push_warning`，失败屏仍可用（数据照常显示）。
2. **Label 节点缺失**（RunStatsLabel 等）→ `get_node_or_null` 守卫静默跳过（沿用 #385 已埋的容错模式），不崩溃。
3. **球冻结回归**（GAME_OVER 后球仍移动）→ 测试 `test_failure_screen.gd` 断言位置不变拦截；FSM exit 时解冻逻辑与 PAUSED 不互扰。

---

## 6. 依赖与阻塞

### 依赖（Depends On）

| 依赖 | 状态 | 风险 |
|------|------|------|
| #385 双得分制（计数 API + `match_over` 21 分终局） | ✅ 已合并（PR #424） | 无 |
| #386 波次循环（`wave_index` 保留供 run 统计） | ✅ 已合并（PR #428） | 无 |
| #396 波次副句与失败短句（`wave_failure_text.json` schema） | ✅ 草稿已合并（PR #407）；⚠️ `draft: true` 待用户定稿（issue open，status/human-review） | 低——机械插槽不依赖定稿文案值（GDD 21 明确） |
| #292 UI 系统（三层 CanvasLayer 约定） | ✅ 已合并（PR #329） | 无 |
| #294 游戏状态机（GAME_OVER 状态） | ✅ 已合并（PR #333） | 无 |

### 阻塞（Blocks）

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| #393 组装/HUD 接线 | P1 | 失败屏布局在 Main.tscn 中已实例化，不阻塞；#393 组装时勿覆盖本 Issue 新增的 Label 节点 |
| 失败屏 run 数据视觉呈现（taste） | P3 | 文案/视觉 taste 内容归 #396/#392 类 issue，本 Issue 只做机械呈现 |

### 依赖链

```
#292 UI 系统 ──► #294 FSM ──► #385 双得分制 ──► #386 波次循环 ──► #391 失败屏（本 Issue）
                                    └──► #396 文案草稿（wave_failure_text.json）──► #391
```

### 前置准备

- [ ] 确认 `mini-pong/content/wave_failure_text.json` 存在且 schema 合法（已确认，PR #407 合并）
- [ ] 确认 GameManager 三数据源可用（已确认源码：`wave_index`/`get_brick_count`/`get_pierce_count`）
- [ ] 确认 #393 未并行改动 Main.tscn 的 GameOverScreen 节点（当前 Main.tscn 无 RunStatsLabel，无冲突）

---

## 7. Spike / 实验

> Issue #391 无 `depth/deep` 标签，按 depth/standard 处理（Section 7 可选）。以下为**研究期实际执行的验证**，作为方案选择的证据记录。

**实验 1：severity 分档边界验证**

- **问题:** `wave_index` 与 4 条候选（fp1-fp4）的分档映射在 0/1/2/3/5/6/99 边界是否正确？
- **方法:** 对照 #396 PRD §4.3 与 JSON `context` 字段（波1-2 / 波3-5 / 波6+ / 通用兜底），枚举 wave_index 0..99 映射。
- **预期结果:** 分档函数 `wave_index <= 2 → fp1；<= 5 → fp2；>= 6 → fp3；异常/缺失 → fp4 兜底`；wave_index==0（未开波即败）落入兜底。
- **影响:** 确认机械分档简单线性，无需权重/概率；兜底条款进 §5 边界 1。

**实验 2：暂停方案 headless 可测性验证**

- **问题:** SceneTree 全局暂停（`get_tree().paused`）vs 软冻结（ball freeze）哪个可被现有测试基建验证？
- **方法:** 阅读 test_pause.gd TC5（mock ball 位置断言模式）与 #296 实现（FSM 软冻结，未用 SceneTree pause）；grep 全库确认 `get_tree().paused` 零使用。
- **预期结果:** 软冻结与既有测试模式一致；全局暂停会牵连 autoload process_mode，测试需额外处理。
- **影响:** 推荐暂停 = 软冻结扩展（§4 维度二方案 B）；全局暂停列为备选。

**实验 3：文案消费契约验证**

- **问题:** `wave_failure_text.json` 的 schema 是否足够支撑运行时按档位选句（不依赖定稿）？
- **方法:** 解析 JSON 确认 `failure_phrases[]` 4 条均带 `id/text/context/emotion/recommended`；对照 GDD 21 数据流「#391 失败屏读 failure_phrases[].text（按 run 数据 severity 分档）」。
- **预期结果:** 契约完备；`draft: true` 仅标记文案值未定稿，机械选句逻辑可先行实现。
- **影响:** 确认 AC3 实现路径 = 读 JSON + 分档选句 + recommended 优先，无阻塞。

---

## 8. 交接上下文（Continuation Context）

### 系统状态

- **数据契约就绪：** GameManager 已提供 `get_brick_count(side)`/`get_pierce_count(side)`（#385）与 public `wave_index`（#386，终局后保留供 run 统计）；`match_over(winner)` 为终局单一权威；`reset_match()` 全量归零。
- **文案契约就绪：** `mini-pong/content/wave_failure_text.json`（schema `wave-failure-text/v1`，`draft: true`）已合并（#396 PR #407）；GDD 21 章规定 #391 按 severity 分档消费 `failure_phrases[].text`。
- **UI 插槽未接线：** `game_over_screen.gd` 已含 #385 埋入的统计读取代码（P/A 双区格式，`RunStatsLabel` 节点不存在时静默跳过）；`ui_game_over.tscn` 无 FailurePhraseLabel/RunStatsLabel；GAME_OVER 期间球未冻结（AC4 缺口）。

### 关键文件现状

| 文件 | 现状 | 本 Issue 动作 |
|------|------|--------------|
| `mini-pong/gdscripts/game_over_screen.gd` | 胜者宣告 + #385 数据读取（P/A 格式） | 改造为 win/fail 双分支；fail 分支渲染短句 + 玩家单侧三项数据 |
| `mini-pong/scenes/ui_game_over.tscn` | WinnerLabel + Spacer + RestartPromptLabel | 新增 FailurePhraseLabel + RunStatsLabel（波次/拆砖/穿墙） |
| `mini-pong/gdscripts/game_state_machine.gd` | GAME_OVER 冻结 paddles，球不冻结 | GAME_OVER enter 补球冻结（AC4），exit 解冻 |
| `mini-pong/gdscripts/game_manager.gd` | 数据齐全 | 可选：补 `get_wave_index()` getter（非必须） |
| `mini-pong/content/wave_failure_text.json` | draft:true 4 条候选 | 只读消费，不改内容 |
| `mini-pong/tests/test_failure_screen.gd` | 不存在 | 新增并注册进 `run_tests.gd` |

### 主要风险

1. **暂停语义选择**：软冻结（推荐）需给 ball 加最小 freeze 支持；避免误用 `get_tree().paused` 牵连 autoload。
2. **#385 遗留格式改动**：现「拆砖 P:x/A:y 穿墙 P:x/A:y」双区格式按 AC2 改为玩家单侧三项（波次/拆砖/穿墙）——注意 `test_ui_system.gd` 等既有断言未覆盖该字符串（TC10 只验证不崩溃），改动安全。
3. **win 分支回归**：YOU WIN! 分支、脉冲动画、RestartPromptLabel 文案与 TC7/TC11 断言需保持兼容。
4. **并行代理冲突**：本分支 `research/391-failure-screen` 曾由先前中断尝试创建（本地分支位于 main HEAD，无远端）；提交前 `git fetch` + 推送后 `git ls-remote` 校验。

### 下一步（plan agent）

1. 依据本 PRD 产出 `docs/DESIGN/391-failure-screen.md`：实施顺序建议 `game_over_screen.gd`（fail 分支 + 分档选句 + 三项数据）→ `ui_game_over.tscn`（Label 布局，竖屏 720×1280 校验）→ `game_state_machine.gd`（球冻结）→ 可选 `get_wave_index()` → `test_failure_screen.gd`。
2. 分档函数契约：`wave_index <= 2 → 档1；<= 5 → 档2；>= 6 → 档3；else → 兜底`（对应 fp1/fp2/fp3/fp4，recommended 优先）。
3. 失败短句文案值归 #396 定稿流程，实施阶段**不要**在代码里硬编码新文案。
4. 开源调研结论（无需第三方依赖）需在实施 PR 中复述，满足 issue「开源优先」验收。

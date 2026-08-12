# PRD: [Feature] 波次转场 (Wave Transition)

> **Issue:** #390
> **标签:** enhancement, ui, version/mvp, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#386/#396 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 跳过）
> **所有权:** `content_ownership: mechanical`（转场 UI/时序/暂停/配置读取为纯机械实现；副句**文案内容**归 #396 taste-draft，本 Issue 只读不拥有）
> **上游方案:** `docs/PLAN-rogue-pong.md` §L3/L137：`波次转场: 大字「第三道墙」+ 海明威式副句, 2s`；MVP 清单含「波次转场」
> **前置依赖:** #386（波次循环，**已合并** PR #428）→ `GameManager.wave_started(wave_index)` 信号契约（DESIGN #386 AC3 明确预留 #390 为「第 N 道墙」消费方）
> **内容契约:** #396（**已合并** PR #407）→ `mini-pong/content/wave_failure_text.json`（schema `wave-failure-text/v1`，`wave_subtitles` 段 4 条副句按波次分档）

---

## 1. 问题定义

### 当前状态

PONG://21 攻城战肉鸽（`mini-pong/`，Godot 4.7.1，竖屏 720×1280）的波次循环（#386）已落地，
**`wave_started(wave_index)` 信号契约就绪但零消费者**——新波开始时玩家看不到任何视觉反馈，
没有「第 N 道墙」大字、没有副句、没有呼吸点。副句内容资源（#396）已就绪但同样无人读取。

| 系统 | Issue | 当前状态 | 与 #390 的差距 |
|------|-------|---------|----------------|
| `mini-pong/gdscripts/game_manager.gd` | #386（✅ merged #428） | autoload 持波次状态：`wave_index`（0→1 起递增）、`WaveState`（IDLE/RUNNING/SETTLED）、`begin_wave()` 内 `wave_started.emit(wave_index)`（line 76）、`wave_settled` | ✅ **触发契约就绪**——`wave_started` 无任何消费者，转场即该信号的第一个消费方（DESIGN #386 §3.1/AC3 预留） |
| `mini-pong/gdscripts/wave_controller.gd` | #386（✅ merged #428） | 场景侧编排：`wall_cleared` → `settle_wave()` → `WAVE_SETTLE_DELAY`(1.0s) → `_advance_wave()`：`begin_wave()`（发信号）→ `generate_wave(更厚)` 同步执行 | ⚠️ **时序事实**：`wave_started` 与 `generate_wave` 同帧发生——转场播放时新墙已在覆盖层背后生成（可接受，见 §4.4）；**不改 WaveController** |
| `mini-pong/scenes/Main.tscn` | #393（⏳ backlog） | 无 `BreakoutGrid` / `WaveController` / 转场节点——#384 实现与 #393 组装均未落地 | ⚠️ 运行期端到端波次不可玩；转场控制器须沿用 `get_node_or_null` 容错 + 隔离测试模式（同 `test_wave_cycle.gd` mock 法） |
| `mini-pong/gdscripts/game_state_machine.gd` | #294/#296（✅） | 6 态 FSM（MENU→SERVING→PLAYING⇌PAUSED→SCORED→GAME_OVER）；PAUSED = **演员冻结惯例**（`_freeze_paddles(true)` + 覆盖层 + 音频暂停，**不设** `get_tree().paused`） | ⚠️ 无转场态；#386 DESIGN 明确「不扩展 FSM」——转场不得新增 FSM 状态（Approach C 否决理由波及全部下游） |
| 覆盖层 UI 先例 | #292/#296（✅） | `StartMenu` / `GameOverScreen` / `PauseOverlay` = CanvasLayer + ColorRect + Label；`ScoreFlash` = Tween 透明度淡出（0.2s） | ✅ 模式可直接复用；转场 = 覆盖层 + 双向 Tween |
| `mini-pong/gdscripts/ball.gd` | #287（✅） | `_process` 手动移动（line 120）；**无 frozen/暂停标志**；仅 `_is_serving` 守卫 | ⚠️ 转场「暂停游戏」需冻结球——要么给 ball 加 frozen 标志（Approach A），要么全局暂停（Approach B） |
| `mini-pong/content/wave_failure_text.json` | #396（✅ merged #407） | schema `wave-failure-text/v1`，`wave_subtitles` 4 条：ws1 雨声盖过心跳（波 1-2）/ ws2 每一道墙都更厚（波 3-5）/ ws3 雨越下越大（波 6+）/ ws4 拆到墙倒为止（决胜波）；`draft: true` | ✅ **副句内容就绪**——#390 按波次分档读取即可，不拥有文案 |
| `mini-pong/gdscripts/constants.gd` | #367/#386（✅） | `WAVE_*` 常量组（厚度/延时/AI 收紧）；`SCREEN_WIDTH=720` / `SCREEN_HEIGHT=1280` | ❌ 无 `WAVE_TRANSITION_*` 常量组（时长分段/字号/描边/JSON 路径/决胜波阈值） |
| `mini-pong/gdscripts/game_hud.gd` | #292（✅） | 顶部 `MarginContainer/HBoxContainer` 双得分 Label（核心区域 = 屏幕顶部约 0–160px 条带） | ⚠️ AC4「不遮挡 HUD 核心区域」——转场文字必须居中于中部安全区，避开顶部条带 |

### 预期行为（验收条件，源自 Issue #390）

1. **AC1 — 每次新波开始播放「第 N 道墙」+ 副句** — 消费 `GameManager.wave_started(wave_index)`：大字「第 {N} 道墙」+ 从 `wave_failure_text.json` 按波次分档选出的副句
2. **AC2 — 转场总时长 2.0 秒（淡入-停留-淡出）** — Tween 三段合计恰为 2.0s（分段常量可配，和恒等于 2.0；测试断言）
3. **AC3 — 转场期间游戏暂停，完成后解锁** — 转场全程冻结球与双拍（或全局暂停，见 §4.1），结束后恢复；解锁有兜底（防卡死）
4. **AC4 — 字号/描边适配 720x1280，不遮挡 HUD 核心区域** — 主字约 112px + 副句约 40px + LabelSettings 描边（outline）；文字居中屏幕中部（y≈640），HUD 顶部条带零遮挡
5. **AC5 — 副句内容从统一文本配置读取** — 唯一内容源 = `res://content/wave_failure_text.json` 的 `wave_subtitles` 段；代码内零硬编码文案

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 波次呼吸点 | 每波一次 | 墙打空 → 结算延时（1.0s）→ 新波 `wave_started` → 覆盖层淡入「第 N 道墙」+ 副句（雨声盖过心跳…）→ 停留 → 淡出 → 游戏解锁，玩家看到更厚的新墙 |
| B | 决胜波仪式 | 决胜波一次 | 比分接近 21（任一方 ≥18）→ 副句切「拆到墙倒为止」（ws4 覆盖波次分档）——终局前的仪式感 |
| C | 内容缺失容错 | 异常路径 | JSON 缺失/解析失败 → 仍显示「第 N 道墙」大字，副句留空，不 crash、不阻塞波次推进 |

### 技术约束（继承自 Issue #390 + 上游）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 `project.godot`，`config/features=PackedStringArray("4.7")`，720×1280 竖屏，resizable=false） |
| 触发契约 | 唯一触发源 = `GameManager.wave_started(wave_index)`（#386 AC3）；`wave_index` 从 1 起 |
| FSM 不变项 | **不扩展 FSM**（DESIGN #386 决策 1：「否决 Approach C，状态归属错误会波及 #388/#390/#391 全部下游」）；转场是呈现层，走场景节点消费信号模式（与 WaveController/ScoringManager 同构） |
| 内容边界 | 副句文案归 #396（taste-draft，`draft: true`，用户定稿后文本可变化）；#390 只实现「按波次分档读取」的机械选择规则，schema 以 #396 为准 |
| 暂停语义 | 沿用 #296 演员冻结惯例（不设 `get_tree().paused`）为基准方案（§4.1 Approach A），全局暂停为备选（Approach B） |
| 时序事实 | `wave_started` 与 `generate_wave` 同帧（WaveController 同步调用）——新墙在覆盖层背后已生成，属预期（§4.4） |
| 测试基线 | #346 修复后全绿；`test_wave_cycle.gd` 已确立 mock 模式（mock BreakoutGrid/AIPaddle/RainCurtain 契约子集） |

### 开源优先调研说明（Issue body 要求）

Godot Asset Library（godotengine.org/asset-library，godot_version=4）检索 `transition` / `overlay`：
EasyTransition、Extendable Scene Transitions、BTransition、Fade Transition、Monitor overlay——**全部为场景切换（scene-to-scene）淡入淡出或工具类**，无一提供「波次横幅大字 + 副句 + 定时暂停」的游戏内回合覆盖层；GitHub 检索 `godot wave transition` 无相关成熟项目。
**结论：无可用插件可复用，自行实现零成本**——项目已有 CanvasLayer+ColorRect+Label 覆盖层模式（#292/#296）与内置 `Tween`/`LabelSettings`（描边），Godot 4.7 原生能力全覆盖，不引入第三方依赖。

### Obsidian 知识检索

- Vault 挂载于 `/Volumes/Obsidian`（WebDAV），本轮尝试检索 `Knowledge Ocean/wiki/` 失败——挂载层报 `Too many open files in system`（与 #386 研究会话同症状；`/Volumes/Obsidian` 根目录可列，子目录不可读）
- **兜底（设计文档层）**：转场语义已由 `docs/PLAN-rogue-pong.md` §L3（「大字+海明威式副句, 2s」）固化；副句美学证据由 **#396 PRD**（其研究阶段成功检索 vault）注入：空洞骑士「沉默作为叙事策略」（克制/负空间）、看火人「极简叙事的精度」（物象服务叙事）、体验引擎 §6 标签化（副句按波次分档 = 情感标签曲线）——#390 的机械职责是让这些副句在正确的波次以正确的时序出现

---

## 2. 设计意图

### 为什么现在做

波次转场的**触发契约与内容源均已就绪，只差呈现层机械实现**：

1. **契约就绪**：#386（merged #428）交付 `wave_started(wave_index)`，DESIGN #386 §3.1/AC3 白纸黑字预留「#390 转场（『第 N 道墙』）」为消费方；GDD 24-WAVE-CYCLE 信号契约表同列。**#390 是契约的第一个消费者**，不做任何上游改动。
2. **内容就绪**：#396（merged #407）交付 `wave_failure_text.json`，副句按波次分档（1-2/3-5/6+/决胜波）——正是「副句从统一文本配置读取」（AC5）的契约。
3. **体验缺口**：当前新波开始零视觉反馈，波次循环缺「呼吸点与仪式感」（Issue 上下文）——转场是波次循环 MVP（PLAN §MVP 清单含「波次转场」）的最后一块拼图之一。

### 为什么现状如此（成因）

| 现状 | 成因 | 证据 |
|------|------|------|
| wave_started 零消费者 | #386 只保证「发出 + 负载」，「消费归 #390/#393」（DESIGN #386 §9 信号表） | game_manager.gd 无转场相关引用；Main.tscn 无转场节点 |
| 副句资源无人读取 | #396 交付内容资源时 #390 尚未实现，读取路径无消费方 | `grep -rn "wave_failure_text" mini-pong/gdscripts/` 为空 |
| 无转场 FSM 态 | #386 DESIGN 决策 1 明确「不扩展 FSM」 | 6 态枚举无 WAVE/TRANSITION |
| 覆盖层先例齐全 | #292 UI 系统 + #296 PauseOverlay + ScoreFlash Tween | PauseOverlay（CanvasLayer+ColorRect+Label）、score_flash.gd（Tween fade） |

### 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 新增 `gdscripts/wave_transition_controller.gd`（或 + 独立 .tscn）；改 `constants.gd`（常量组）与 `Main.tscn`（挂节点）；**不碰** FSM、WaveController、GameManager、ball 物理、HUD 布局 |
| 引擎版本 | Godot 4.7.1；JSON 用 `FileAccess` + `JSON.parse_string`（#396 契约指定读取路径，项目有 `e2e_shots.json`/`upgrade_pool.json` 先例） |
| UI 语境 | 竖屏 720×1280 街机屏显；主字约 112px、副句约 40px、描边 outline 8–12px；文字居中安全区（y≈640 ± 200），顶部 0–160px HUD 条带零遮挡 |
| 内容红线 | 副句文本零硬编码（AC5）；转场 UI 只显示，不评审/不修改文案 |
| 测试基线 | 沿用 mock 模式（参照 test_wave_cycle.gd）；headless 可跑；tween 时长测试注入短值 |

---

## 3. 影响分析

### 新增文件

| 文件 | 用途 |
|------|------|
| `mini-pong/gdscripts/wave_transition_controller.gd` | 转场控制器（CanvasLayer 或挂 CanvasLayer 的 Node）：连接 `GameManager.wave_started` → 冻结/暂停 → 读 JSON 选副句 → 2.0s Tween（淡入-停留-淡出）→ 解锁；`get_node_or_null` 容错 + `has_signal` 守卫（与 WaveController 同构） |
| `mini-pong/scenes/wave_transition.tscn`（推荐） | CanvasLayer + 全屏半透明 ColorRect（dim）+ 居中 VBoxContainer：大字 Label（「第 N 道墙」）+ 副句 Label + LabelSettings（字号/描边）；或由控制器纯代码构建（二选一，见 §4.2） |
| `mini-pong/tests/test_wave_transition.gd` | 转场测试套件（mock 契约 + 短时长注入），注册进 `run_tests.gd` |

### 修改文件

| 文件 | 改动 | 性质 |
|------|------|------|
| `mini-pong/gdscripts/constants.gd` | 新增 `WAVE_TRANSITION_*` 常量组（见 §4 推荐表） | 纯常量追加 |
| `mini-pong/scenes/Main.tscn` | 挂载 `WaveTransition` 节点（CanvasLayer 层序置于 HUD 之上、PauseOverlay 之下或同级） | 节点实例化 |
| `mini-pong/gdscripts/ball.gd` | **仅当采用 §4.1 Approach A**：新增 `frozen` 标志（`_process` 开头守卫，仿 `_is_serving`） | 条件性改动（Approach B 则零改动） |
| `mini-pong/tests/run_tests.gd` | 注册 `test_wave_transition` 套件 | 一行注册 |

### 间接影响

| 模块 | 影响 |
|------|------|
| FSM / WaveController / GameManager | **零改动**——转场只消费 `wave_started` 信号，不触碰状态机与波次推进 |
| #393 主场景组装 | 转场节点由本 Issue 自带实例化（自包含）；#393 组装时无需为转场另做接线（与 BreakoutGrid/WaveController 接线互不依赖） |
| #396 内容资源 | 只读；用户定稿改文案不影响读取路径与分档规则（schema 不变） |
| #388 升级 UI | 挂 `wave_settled`（settle 窗口），转场挂 `wave_started`（下一波）——时序相邻不重叠，互不干扰 |
| #391 失败屏 | 无关（GAME_OVER 路径）；转场不进入终局流程 |

### 数据流

```
GameManager.begin_wave() ──► wave_index += 1 ──► wave_state = RUNNING ──► wave_started.emit(wave_index)
    │                                                                          │
    │（WaveController 同步 continue：generate_wave(更厚) 已在覆盖层背后生成新墙）     ▼
    │                                                          WaveTransitionController._on_wave_started(n)
    │                                                              │  冻结球+双拍（Approach A）或 get_tree().paused（B）
    │                                                              ▼
    │                                              FileAccess 读 res://content/wave_failure_text.json
    │                                                              │  wave_subtitles 按波次分档选句（决胜波 ws4 覆盖）
    │                                                              ▼
    │                                              覆盖层淡入（0.5s）→ 停留（1.0s）→ 淡出（0.5s）= 2.0s
    │                                                              │
    │                                                              ▼
    │                                              解锁（球+双拍恢复 / 恢复 paused=false）—— 兜底保证必达
    ▼
游戏继续（玩家看到更厚的新墙，进入下一波对打）
```

### 文档更新

- [ ] `docs/GAME_DESIGN/25-WAVE-TRANSITION.md`（新章节，参照 24-WAVE-CYCLE 格式；GDD INDEX.md 登记）
- [ ] `docs/PRD/390-wave-transition.md`（本文件）
- [ ] `docs/PLAN-rogue-pong.md`（无需改——§L3 语义已含）

---

## 4. 方案对比

### 4.1 暂停机制（AC3）

**Approach A：演员冻结（推荐）**

转场全程 `_freeze_paddles(true)`（既有 API）+ `ball.set_frozen(true)`（ball.gd 新增 frozen 标志，仿 `_is_serving` 守卫 `_process`）；结束后恢复。沿用 #296 已确立的暂停惯例（FSM PAUSED 即演员冻结，不设 `get_tree().paused`）。

- Pros：与项目暂停惯例一致；无全局状态，headless 测试零风险（tween/计时器不受影响）；雨幕/音频继续（「雨还在下」氛围，#396 taste 方向）；改动面小（ball.gd +1 标志）
- Cons：需改 ball.gd（新增 frozen 标志）；「暂停」是演员级而非全局级（雨幕/音频继续——对本场景反而是优点）
- Risk: Low ／ Effort: 1 天

**Approach B：全局暂停（`get_tree().paused`）**

转场期间 `get_tree().paused = true`，控制器节点 `process_mode = PROCESS_MODE_ALWAYS`，Tween 设 `TWEEN_PAUSE_PROCESS` 继续播放；结束恢复。

- Pros：一行实现「全部暂停」，AC3 字面最干净；ball.gd 零改动
- Cons：**与项目惯例相悖**（#296 刻意不用全局暂停）；雨幕/音频/全部计时器同停（氛围冻结）；headless 测试需小心（测试内计时器会被暂停拖住）；Escape 暂停键在转场期需额外守卫；引入新的全局状态面
- Risk: Med ／ Effort: 1 天

**Approach C：FSM 新增 WAVE_TRANSITION 状态**

- Pros：与既有状态机集成最彻底
- Cons：**直接违反 DESIGN #386 决策 1**（「不扩展 FSM……波及 #388/#390/#391 全部下游」）；扩大 test_integration_fsm 测试面；呈现层问题用状态机解决属过度工程
- Risk: High ／ Effort: 2 天

### 4.2 转场呈现（AC2/AC4）

**Approach A：Tween 透明度三段式（推荐）**

控制器持 ColorRect/Labels，`create_tween()` 依次：`modulate:a` 0→1（FADE_IN）→ 停留（HOLD，可用 `tween_interval`）→ 1→0（FADE_OUT），总时长 = 三段和 = 2.0s；隐藏后回调解锁。文字节点直接建在 .tscn（`wave_transition.tscn`），LabelSettings 定字号/描边。

- Pros：项目已有 Tween 先例（ScoreFlash 0.2s fade）；时长精确可测（`tween.get_total_time()` 或分段常量断言）；LabelSettings 原生描边（AC4）；场景文件可调布局，便于「不遮挡 HUD」视觉校验
- Cons：无（成熟模式）
- Risk: Low ／ Effort: 0.5 天

**Approach B：AnimationPlayer + 动画资源**

- Pros：动画可视化编辑
- Cons：为 3 段透明度动画引入 AnimationPlayer 资源管线，重；测试需驱动 AnimationPlayer 而非直接断言时长
- Risk: Med ／ Effort: 1 天

**Approach C：纯代码 `_process` 计时**

- Pros：零场景文件
- Cons：手动计时易漂移；布局/描边全在代码，AC4 视觉校验困难；弃用引擎 Tween 优势
- Risk: Med ／ Effort: 1 天

### 4.3 副句选择（AC5）

**Approach A：波次分档 + 决胜波覆盖（推荐）**

读 `wave_subtitles` 数组（顺序即档位），按规则选句：任一方比分 ≥ `WAVE_TRANSITION_DECISIVE_SCORE`（常量，默认 18）→ ws4（决胜波）；否则按 `wave_index` 分档 1-2 → ws1 / 3-5 → ws2 / 6+ → ws3；无匹配或 JSON 缺失 → 副句留空（只显示大字）。档位边界为机械常量（内容侧 context 字符串仅供人工阅读，不解析）。

- Pros：确定性、可测（断言各波次/比分选句）；与 #396 context 分档一一对应；内容缺失优雅降级（AC 全保）
- Cons：档位边界硬编码于机械侧——#396 若改 schema 需同步（契约已在 §6/§8 标注风险与缓解）
- Risk: Low ／ Effort: 0.5 天

**Approach B：随机选句**

- Pros：重复波次有变化
- Cons：破坏「波次推进 → 张力递增」的标签化曲线（体验引擎 §6：副句是情感标签，应确定对应波次）；测试不可断言
- Risk: Med ／ Effort: 0.5 天

**Approach C：全部副句轮播/堆叠显示**

- Pros：无
- Cons：与「克制、少即是多」（#396 美学）直接冲突；遮挡 HUD 风险（AC4）
- Risk: High ／ Effort: 0.5 天

### 4.4 与 WaveController 的时序（设计确认）

`wave_started` 与 `generate_wave` 同帧发生（WaveController._advance_wave 同步调用）。转场淡入时新墙已在覆盖层背后生成——**属预期**：淡出后玩家立即看到更厚的新墙（「呼吸点后直面升级后的墙」仪式感成立）。**不修改 WaveController 的调用顺序**（延迟 generate_wave 会耦合两系统并破坏 #386 测试契约）；若未来要「墙随淡出浮现」，留给 DESIGN 作为可选项，不写入本 PRD 验收。

### 推荐与理由

**4.1 选 A（演员冻结）+ 4.2 选 A（Tween 三段式）+ 4.3 选 A（分档+决胜波覆盖）**：

1. **AC 全命中**：AC1（wave_started 消费 + 大字+副句）/ AC2（三段和 = 2.0s 常量可测）/ AC3（演员冻结 + 兜底解锁）/ AC4（LabelSettings 字号描边 + 中部安全区布局）/ AC5（JSON 唯一内容源，零硬编码）；
2. **上游约束全守**：不扩展 FSM（DESIGN #386 决策 1）、不拥有文案（#396 契约）、不改 WaveController/GameManager；
3. **项目惯例一致**：演员冻结（#296）、覆盖层模式（#292）、Tween 先例（ScoreFlash）、信号消费容错模式（WaveController/ScoringManager）——五个既有模式零新范式；
4. **测试友好**：无全局暂停状态，headless 下 tween 时长可注入短值，选句规则纯函数可断言。

**推荐常量组（constants.gd `WAVE_TRANSITION_*`）**：

| 常量 | 默认值 | 意图 |
|------|:------:|------|
| `WAVE_TRANSITION_FADE_IN` | 0.5 | 淡入时长（s） |
| `WAVE_TRANSITION_HOLD` | 1.0 | 停留时长（s） |
| `WAVE_TRANSITION_FADE_OUT` | 0.5 | 淡出时长（s）——三段和恒 = 2.0（AC2） |
| `WAVE_TRANSITION_TITLE_FONT_SIZE` | 112 | 大字「第 N 道墙」字号（720×1280） |
| `WAVE_TRANSITION_SUBTITLE_FONT_SIZE` | 40 | 副句字号 |
| `WAVE_TRANSITION_OUTLINE_SIZE` | 10 | 描边宽度（AC4） |
| `WAVE_TRANSITION_JSON_PATH` | `res://content/wave_failure_text.json` | 统一文本配置路径（#396 契约） |
| `WAVE_TRANSITION_DECISIVE_SCORE` | 18 | 决胜波阈值（任一方 ≥ 此值 → ws4；taste-draft 可调） |
| `WAVE_TRANSITION_BAND_*` | 1-2 / 3-5 / 6+ | 波次分档边界（机械占位，对应 ws1/ws2/ws3） |

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue 5 条 AC）

- [x] **AC1: 每次新波开始播放「第 N 道墙」+副句**
  - 验证：连接 `wave_started` → 控制器显示大字文本 == `"第 %d 道墙" % wave_index`；副句 == 分档规则选句（mock 各波次断言）
- [x] **AC2: 转场总时长 2.0 秒（淡入-停留-淡出）**
  - 验证：断言 `FADE_IN + HOLD + FADE_OUT == 2.0`；tween 结束后覆盖层隐藏（短时长注入测试）
- [x] **AC3: 转场期间游戏暂停，完成后解锁**
  - 验证：转场起 `ball.frozen == true` 且双拍 frozen；结束回调后恢复 false；解锁兜底（结束回调必达，异常路径 §5 失败路径 2）
- [x] **AC4: 字号/描边适配 720x1280，不遮挡 HUD 核心区域**
  - 验证：LabelSettings 字号/描边按常量；文字容器 rect 中心 y ≈ 640 且与顶部 HUD 条带（0–160px）无交集；截图人工校验
- [x] **AC5: 副句内容从统一文本配置读取**
  - 验证：`grep -rn "雨声盖过心跳\|每一道墙都更厚" mini-pong/gdscripts/` 为空；选句逻辑读 `WAVE_TRANSITION_JSON_PATH`

### 边界条件（Edge Cases）

1. **首波（wave 1）**：当前运行期（#393 未接线）无初始 `begin_wave()` 调用——转场仅响应 `wave_started`，不自行启动波次；首波触发路径归 #393 组装，测试直调 `begin_wave()` 模拟（同 test_wave_cycle C-1）
2. **决胜波覆盖优先级**：比分 ≥18 与波次分档冲突时 ws4 优先（波次分档为兜底）
3. **JSON 缺失/解析失败/schema 字段缺失**：副句留空，仅显示大字，`push_warning`，不 crash、不阻塞波次推进
4. **转场期间 Escape 暂停键**：控制器持转场锁，忽略 `ui_cancel` 期间的状态切换（或 FSM 本就只响应 PLAYING/PAUSED——转场期 FSM 仍在 PLAYING，需守卫避免进入 PAUSED 打断转场）
5. **转场期间得分/清墙信号**（理论上不可能——球已冻结）：`wave_started` 重入守卫（`_transitioning` 标志），重复信号忽略
6. **2.0s 精确性**：分段常量可调但和必须 == 2.0（常量注释 + 测试断言双保险）
7. **波次推进中多次转场**：每波一次，`_transitioning` 结束后才允许下一次（防连发）
8. **终局（21 分）后**：`wave_started` 不再发出（#386 AC5 已保证），转场自然不触发；决胜波副句（ws4）只在波次推进时出现，不进 GAME_OVER 屏

### 失败路径

1. **实现把副句硬编码进 .gd** → 违反 AC5。缓解：review 用 AC5 的 grep 卡口（同 #396 §5 模式）
2. **解锁兜底缺失导致游戏卡死**（转场中异常/节点被移出场景）→ 结束回调 + `is_inside_tree()` 守卫 + 转场锁 finally 语义恢复冻结状态；测试断言异常路径必解锁
3. **布局遮挡 HUD**（文字 rect 侵入顶部条带）→ AC4 截图校验卡口；容器约束在安全区
4. **#396 定稿改 schema/分档** → 读取路径与分档规则以 schema 为准；改 schema 需同步 #390 常量（§8 风险 3 缓解：DESIGN 引用同一 schema）

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| #386 波次循环（`wave_started` 契约） | ✅ merged #428 | 无——契约已测试（test_wave_cycle C-3 信号负载） |
| #396 副句内容资源（统一文本配置） | ✅ merged #407 | 低——`draft: true`，用户定稿仅改文本不改 schema/路径 |
| #393 主场景组装（BreakoutGrid/WaveController 入 Main.tscn） | ⏳ backlog | 中——端到端可玩验证依赖；**信号契约与隔离测试不依赖**（转场容错 + mock 测试） |
| #384 砖墙实现 | ⏳ 实现未落地 | 中——同上，运行期无 BreakoutGrid 时转场照常（wave_started 仍可发出） |
| #388 升级 UI（`wave_settled` 挂点） | ⏳ backlog | 无——settle 窗口与转场（wave_started）时序相邻不重叠 |
| #292/#296 覆盖层/Tween 先例 | ✅ 项目内 | 无——模式直接复用 |

```
#384（砖墙，实现未落地）──► #393（主场景组装，⏳）──► 端到端可玩验证
                                                          │
#386（波次循环，✅ #428）──► wave_started 契约 ──► 本 Issue #390（波次转场）──► #388（升级 UI，⏳）
                                                          │
#396（副句内容，✅ #407）──► wave_failure_text.json（唯一内容源）───────────────┘
```

**无阻塞（信号契约与内容源均已满足）。** 运行期端到端依赖 #393/#384，但 #390 的契约、内容、测试三要素齐备，可按容错模式独立交付（同 #386 前置期交付先例）。

---

## 7. Spike / 实验

Skipped per `depth/standard`（Issue 无 depth 标签，按 #358/#378/#386/#396 惯例按 standard 处理；Section 7 仅 `depth/deep` 必填）。
理由：Tween 三段式与 CanvasLayer 覆盖层均为项目内已验证模式（ScoreFlash/PauseOverlay 先例），无未验证的机械行为；副句内容/分档的 taste 决策已由 #396 PRD 完成。

---

## 8. 延续上下文（Continuation Context）

**给 plan agent 的手递**（plan agent 产出 DESIGN 时直接采用，无需重扫源码）：

**系统状态**：PONG://21 批次中 #386（波次循环）与 #396（副句内容）已合并；`GameManager.wave_started(wave_index)` 信号就绪且零消费者；`mini-pong/content/wave_failure_text.json`（schema `wave-failure-text/v1`，`wave_subtitles` ws1-ws4 按波次分档）就绪；`Main.tscn` 无 BreakoutGrid/WaveController/转场节点（#393 backlog、#384 实现未落地）；FSM 6 态不可扩展（DESIGN #386 决策 1）；覆盖层先例 = StartMenu/GameOverScreen/PauseOverlay（CanvasLayer+ColorRect+Label）+ ScoreFlash（Tween）；暂停惯例 = 演员冻结（#296，不设 `get_tree().paused`）；HUD 核心区域 = 顶部 0–160px 得分条带。

**主风险**：
1. 副句硬编码进 .gd → 违反 AC5（§5 失败路径 1）
2. 解锁兜底缺失 → 转场卡死（§5 失败路径 2）
3. #396 定稿改 schema/分档 → 读取规则漂移（§5 失败路径 4；DESIGN 必须引用同一 schema）
4. 全局暂停（Approach B）被误选 → 与项目惯例相悖 + 测试拖慢（§4.1 已否决，DESIGN 应坚持 A）
5. 转场节点与 #393 组装冲突 → 本 Issue 自带实例化、自包含，组装时零额外接线

**下一步（plan → implement）**：
1. DESIGN 引用本 PRD §4 推荐组合（演员冻结 + Tween 三段式 + 分档选句）+ §4 常量组（`WAVE_TRANSITION_*`，三段和 == 2.0）+ 读取路径 `res://content/wave_failure_text.json`（#396 schema 为契约）
2. implement 新建 `gdscripts/wave_transition_controller.gd`（+ `scenes/wave_transition.tscn`）：连接 `GameManager.wave_started`（`has_signal` 守卫，容错同 WaveController）→ 冻结球+双拍 → 读 JSON 分档选句（决胜波 ws4 覆盖，比分 ≥18 常量）→ 2.0s Tween → 兜底解锁；ball.gd 加 `frozen` 标志（`_process` 首行守卫）；constants.gd 加常量组；Main.tscn 挂节点；**不碰** FSM/WaveController/GameManager/文案
3. implement 新建 `tests/test_wave_transition.gd` 并注册 `run_tests.gd`：mock 契约（直调 `begin_wave()` 触发，短时长注入），断言 AC1（大字文本/选句）、AC2（三段和 2.0）、AC3（冻结/解锁）、AC5（零硬编码 grep）；AC4 截图人工校验
4. review：AC5 grep 卡口 + 时长断言 + 兜底解锁 + 截图（720×1280 无 HUD 遮挡）→ merge（PR 用 `parent #390`）
5. 端到端验证待 #393 组装合并后补跑（转场 + 真 BreakoutGrid 全链路）；GDD 新章节 `25-WAVE-TRANSITION.md` 随实现 PR 落地

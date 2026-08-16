# PRD: [Bug] title界面错误混杂了正式游戏画面

> **Issue:** #508
> **标签:** bug, workflow/available → workflow/research（available-rescan 分配）
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** light（Issue body「工作深度: light（简单修复，快速完成）」；无 depth/ 标签，按 body 声明 light：Section 1–5 + 8 必填；6/7 跳过并注明）
> **所有权:** `content_ownership: mechanical`（确定性可见性状态修复：MENU 状态隐藏游戏世界 = 机械可测，无品味决策）
> **来源:** available-rescan（workflow/available → workflow/research）
> **前置依赖:** 无（独立 bug；依赖既有 FSM #294 与 Main 单场景组装 #393）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：Main.tscn 为单场景常驻架构（#295/#393 组装），游戏世界节点（Ball、PlayerPaddle、AIPaddle、RainCurtain、BgPulse、BreakoutGrid、墙壁、得分区）从启动起就存在于场景树并持续渲染；FSM（#294）`_set_ui()` 只切换 4 个 UI 层（StartMenu/GameHUD/GameOverScreen/PauseOverlay）的 `CanvasLayer.visible`，从未隐藏游戏世界 → MENU 状态下「PONG://21」标题与半透明提示之下，球、双球拍、雨幕、呼吸背景脉冲全部可见，「部分正式游戏画面」混杂在 title 界面。**

| 节点 | 类型 | MENU 状态可见性 | 证据 |
|------|------|:---:|------|
| Ball | Area2D（ball.tscn） | ✅ 可见 | Main.tscn `[node name="Ball" parent="."]` 无 visible=false；FSM 仅软冻结（#296），不隐藏 |
| PlayerPaddle / AIPaddle | Area2D（player_paddle.tscn） | ✅ 可见 | Main.tscn 实例化无 visible=false；MENU 仅 `set_frozen(true)` |
| RainCurtain | CanvasLayer 实例（rain_curtain.tscn） | ✅ 可见 | AtmosphereLayer 下常驻；全仓库 grep 无对其 visible 的控制 |
| BgPulse | ColorRect（#449 呼吸层） | ✅ 可见 | AtmosphereLayer 下常驻全屏脉冲；无隐藏逻辑 |
| BreakoutGrid | Node2D | ⚠️ 节点在、无渲染 | 砖墙由 `generate_wave()` 惰性生成（首波 #393 进入 PLAYING 才触发），MENU 下无砖 |
| LeftWall/RightWall/ScoreZone | StaticBody2D/Area2D | 不可见 | 纯物理/碰撞节点，无视觉 |
| ScoreFlashRect | ColorRect（全屏白） | ✅ 自隐藏 | score_flash.gd `_ready()` → `modulate.a=0; hide()` |
| UpgradePickUI | CanvasLayer 实例 | ✅ 自隐藏 | upgrade_pick_ui.gd `_ready()` → `visible=false` |
| GameOverScreen / PauseOverlay / WaveTransition | CanvasLayer | ✅ 不可见 | Main.tscn visible=false / FSM 控制 |

#### 预调查结果（bug pre-investigation，Patch 10）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | title 界面可看到部分正式游戏画面 | ✅ **确认（未修复）** | `game_state_machine.gd:_set_ui()` 只写 4 个 UI CanvasLayer.visible；`grep -rn "call_group\|game_world\|world_visible\|set_visible" gdscripts/` 无任何对 Ball/Paddle/AtmosphereLayer 的可见性控制 |
| 2 | 怀疑场景管理有问题（issue 推测） | ⚠️ **部分成立** | 非场景切换 bug，而是单场景常驻架构下「MENU 状态隐藏游戏世界」的 FSM 职责缺失（DESIGN #294 设计缺口） |
| 3 | 是否已有修复 | ❌ 无 | `git log --all` 无 #508 相关提交；最近 title 相关提交 242adc9（#378 命名同步）、2c95f2d（#358 版本号）均不涉及可见性 |

**无 stale claims** — issue 为 available-rescan 新分配，描述与当前代码一致，全部声明确认成立。

### 1.2 Obsidian 知识库搜索结果（issue 已勾选「搜索 Obsidian 知识库」）

| 检索范围 | 命中文档 | 结论 |
|---------|---------|------|
| `/Volumes/Obsidian/Knowledge Ocean/wiki/`（WebDAV 已挂载） | 「赛博增殖：网球与绒毛.md」 | 记录 2026-06 AI 自主开发网球游戏事件（工作流教训），无 title 屏设计约束 |
| 同上 | 「2026-06-18 独立游戏开发与设计思路讨论.md」「独立游戏开发讨论.md」 | 泛义「网球」隐喻讨论，非本项目 UI 设计 |
| 同上（grep PONG:// / mini-pong / 标题 / title） | 其余 wiki 无命中 | 无本项目 title 屏/场景管理设计笔记 |

**结论：Obsidian 知识库无本项目 title 屏设计笔记，知识搜索无新增约束。** 降级说明（skill 降级路径）：设计意图以仓库内 DESIGN #292（UI 系统）、DESIGN #294（FSM）、PRD #295/#393（单场景组装）为准，见第 2 节。

### 1.3 预期行为（验收条件，源自 Issue #508）

1. [ ] **AC1** 进入游戏后 title 界面只显示标题层（PONG://21、按 SPACE 开始、版本号）与干净背景氛围，不混杂球/球拍/雨幕等正式游戏元素
2. [ ] **AC2** 按 SPACE 开始后游戏元素正常显示，对局不受影响
3. [ ] **AC3** 对局结束返回 title（GAME_OVER → MENU）时游戏元素再次隐藏
4. [ ] **AC4** 既有自动化测试（FSM/集成/headless）不回归

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| 1 | 首次启动进入 title | 每次启动 | 玩家停留数秒，看到球/球拍/雨幕穿透半透明标题层 → 观感混乱，误以为游戏已开始 |
| 2 | 对局结束返回 title | 每局结束 | GAME_OVER 按 SPACE 回 MENU，游戏世界瞬时重现 |
| 3 | 长时间停留 title | 偶尔 | 雨幕粒子持续飘落 + 背景脉冲呼吸（标题 alpha 0.6–1.0 半透明），干扰标题可读性 |

## 2. 设计意图

### 2.1 为什么当前状态存在

| 贡献者 | 决策 | 后果 |
|--------|------|------|
| DESIGN #292（UI 系统） | StartMenu「layer 1 (topmost — blocks interaction with game)」 | 只阻断交互，无视觉隔离；设计未要求隐藏游戏世界 |
| DESIGN #294（FSM） | 状态表只定义「UI Visible / Input Active / Ball Moving / Paddle Moving」 | 可见性维度只覆盖 UI 层；游戏世界可见性不在状态契约内 |
| PRD #295 / #393（Main Scene Assembly） | 全部组件单场景常驻，靠 CanvasLayer.visible 切换 UI | 游戏世界节点常驻场景树 → 天然「穿透」UI 层可见 |

### 2.2 为什么现在改

- Issue #508 明确报告（light 深度，简单修复）；问题自 #295 组装起即存在，此前无 title 屏视觉审查
- title 屏是玩家第一印象入口，混杂正式游戏画面破坏 #289/#392 投入的 neon 氛围呈现，也误导玩家操作

### 2.3 先前约束

| 约束 | 详情 |
|------|------|
| 引擎/目录 | Godot 4.7.1，mini-pong/ |
| 场景架构 | 单场景 Main.tscn 常驻（#295/#393），不做运行时场景切换 |
| FSM 单一职责 | 状态机已是运行时编排唯一入口（#294），可见性职责归 FSM |
| 测试契约 | headless 测试大量使用 mini-tree（无 Main.tscn 全树），隐藏逻辑必须对缺失组 no-op 安全 |
| CanvasLayer 语义 | AtmosphereLayer 是 CanvasLayer（layer=0），子节点 BgPulse/RainCurtain 可随层整体隐藏 |
| 组寻址先例 | wave_controller.gd:27 已用 group "wave_controllers" 寻址（#388/#393 模式） |

## 3. 影响分析

### 3.1 直接影响

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| mini-pong/scenes/Main.tscn | 场景组装（#393） | Ball / PlayerPaddle / AIPaddle / BreakoutGrid / AtmosphereLayer 各加 `groups=["game_world"]` |
| mini-pong/gdscripts/game_state_machine.gd | FSM（#294） | 新增 `_set_world_visible()`；enter_state MENU 分支隐藏世界，其余状态恢复 |

### 3.2 新文件

无（light 修复，不新增场景/脚本）

### 3.3 间接影响

| 文件 | 影响 |
|------|------|
| mini-pong/tests/test_integration_fsm.gd | 若断言节点 visible 需同步；call_group 对 mini-tree（无 game_world 组）no-op → 大概率零影响 |
| mini-pong/tests/*.gd | headless 测试不加载 Main.tscn 全树 → 无影响 |
| docs/GDD.md / docs/PROJECT.md | 建议补一行「MENU 状态隐藏 game_world 组」约定（非强制） |

### 3.4 数据流

```
FSM.enter_state(MENU)            FSM.enter_state(SERVING/PLAYING/SCORED/PAUSED/GAME_OVER)
        │                                   │
        ▼                                   ▼
_set_world_visible(false)         _set_world_visible(true)
        │                                   │
        ▼                                   ▼
get_tree().call_group("game_world", "set", "visible", false)
        ├── Ball / PlayerPaddle / AIPaddle / BreakoutGrid   (Node2D.visible=false)
        └── AtmosphereLayer                                  (CanvasLayer.visible=false → 整层隐藏 BgPulse + RainCurtain)
```

### 3.5 文档更新

- [ ] docs/GDD.md —（可选）title 屏世界隐藏约定
- [x] 本 PRD 为研究阶段唯一必需产物

## 4. 方案比较

### 方案 A：FSM 状态驱动 + group 组寻址（推荐）

FSM 增加 `_set_world_visible(visible: bool)`，经 `get_tree().call_group("game_world", "set", "visible", v)` 切换；Main.tscn 给 5 个世界节点/层打 `groups=["game_world"]`。

| 维度 | 评估 |
|------|------|
| Pros | 职责归 FSM（#294 编排中心）；组寻址免维护 @onready 引用列表；新增世界节点入组即自动纳入；CanvasLayer 整层隐藏语义干净；与 #393 既有 group 寻址模式（wave_controllers）一致 |
| Cons | call_group 为运行时字符串寻址（无编译期检查）；需约定「世界节点必须入组」 |
| Risk | Low（组不存在时 call_group no-op，headless mini-tree 安全） |
| Effort | 0.5 天（Main.tscn 5 处 group + FSM ~15 行） |

### 方案 B：世界节点包进独立 CanvasLayer

Main.tscn 将 Ball/Paddles/BreakoutGrid 等世界节点移入新 CanvasLayer（layer=0，与 AtmosphereLayer 同级），FSM 切换该层 visible。

| 维度 | 评估 |
|------|------|
| Pros | 单点切换；绘制顺序显式；与 UI 层结构对称 |
| Cons | Main.tscn 结构性大改（节点重排，diff 大、评审成本高）；可能引入 draw order/坐标回归；与「light 快速完成」目标冲突 |
| Risk | Med（场景重组回归面大） |
| Effort | 1 天 |

### 方案 C：FSM @onready 逐个隐藏（硬编码引用）

FSM 增加 Ball/Paddle/AtmosphereLayer 等 @onready 引用并逐个置 visible。

| 维度 | 评估 |
|------|------|
| Pros | 最直接，无场景文件改动 |
| Cons | FSM 引用列表膨胀；新增世界节点易漏 → 半隐藏（本 bug 的复发形态）；与 #393 组装式场景风格相悖 |
| Risk | Med（漏节点 = 复发） |
| Effort | 0.5 天 |

### 推荐

**方案 A**。理由：(1) FSM 已是全部运行时状态/可见性的唯一编排者（#294），世界可见性是缺失的状态维度，补在 FSM 最内聚；(2) 组寻址与 #393 组装式场景既有模式（wave_controller.gd group 寻址）一致；(3) Risk 最低且 headless 安全；(4) 变更面最小（Main.tscn 加 5 处 group 属性 + FSM 一个方法），符合 light 深度。**范围：仅 MENU 状态隐藏世界；GAME_OVER 保留世界可见（终局画面展示残局状态，#391 已冻结球），PAUSED 保留可见（暂停遮罩需叠在世界之上）**——与 issue 描述（title 屏）严格对齐，最小变更。

## 5. 边界条件与验收标准

### 5.1 正常路径 AC

- [ ] **AC1: MENU 状态世界隐藏** — 启动后 Ball/Paddle/雨幕/背景脉冲不可见，仅 StartMenu 标题层与干净背景
- [ ] **AC2: SPACE 开始后世界恢复** — SERVING/PLAYING 状态 Ball/Paddle/雨幕/背景脉冲可见
- [ ] **AC3: 返回 title 再次隐藏** — GAME_OVER → MENU 后世界再次不可见
- [ ] **AC4: 既有测试不回归** — `godot --headless` 测试套件全过

### 5.2 边界情况

1. PAUSED（Escape）：世界必须保持可见——暂停遮罩半透明叠于世界之上，隐藏世界破坏暂停观感（FSM 仅 MENU 隐藏）
2. GAME_OVER：保持可见——终局画面含残局状态（#391 已冻结球）
3. MENU → SERVING 过渡：SERVING enter 即恢复可见，避免 1s 发球计时期间黑屏
4. headless / mini-tree 测试：无 "game_world" 组 → call_group no-op，不崩溃
5. AtmosphereLayer 整体入组：CanvasLayer.visible=false 隐藏整层（BgPulse + RainCurtain），避免逐个 ColorRect 隐藏
6. 未来新增世界节点：必须加 `groups=["game_world"]`，否则 title 屏再次泄漏（写进 Continuation Context 交接）
7. GAME_OVER → MENU 过渡中（_transition_lock）：MENU enter 同步隐藏，无中间帧闪烁

### 5.3 失败路径

1. group 名拼写错误 → call_group 静默 no-op → 世界不隐藏（回归原 bug）。缓解：FSM `_ready()` 校验 `get_tree().get_nodes_in_group("game_world")` 非空，空则 push_warning
2. FSM @onready 引用 null（mini-tree 测试）→ 既有 `_validate_references()` push_warning 不崩溃；新逻辑同样以 has_method / 组寻址守卫
3. 若误用方案 B 造成 draw order 回归 → 视觉回归 E2E（#466/#476 L3）应捕获；回退方案 A 即可

## 6. 依赖与阻塞

**Skipped per depth/light**（Issue body「工作深度: light」；本 bug 无前置依赖，独立可修；依赖的既有设施 FSM #294 / 组装 #393 均已合入 main）

## 7. Spike / 实验

**Skipped per depth/light** — 无技术不确定性：方案 A 的 call_group 组寻址模式已在 wave_controller.gd（group "wave_controllers"）实战验证；CanvasLayer.visible 隐藏整层为 Godot 4.7 标准语义

## 8. 延续上下文（plan agent 交接）

**系统状态**：Main.tscn 单场景常驻（#393 组装完成）；FSM #294 已接管全部 UI 层可见性；游戏世界可见性维度缺失 = #508 根因。Obsidian 无相关设计笔记，设计意图以 DESIGN #292/#294 为准。

**核心结论**：MENU 状态隐藏 `game_world` 组（Ball / PlayerPaddle / AIPaddle / BreakoutGrid / AtmosphereLayer），其余状态恢复可见。推荐方案 A（FSM + group 组寻址），light 深度。

**实现要点（plan agent）**：
1. `Main.tscn`：Ball、PlayerPaddle、AIPaddle、BreakoutGrid、AtmosphereLayer 各加 `groups=["game_world"]`（AtmosphereLayer 为 CanvasLayer，整层隐藏覆盖 BgPulse + RainCurtain）
2. `game_state_machine.gd`：新增 `_set_world_visible(visible: bool)` → `get_tree().call_group("game_world", "set", "visible", visible)`；`enter_state(State.MENU)` 调用 false；SERVING/PLAYING/SCORED/PAUSED/GAME_OVER 分支调用 true（最小变更：可在 MENU 分支隐藏、exit_state(MENU) 恢复，或各分支显式调用）；`_ready()` 校验组非空并 push_warning
3. 测试：FSM 集成测试新增断言——MENU 下 game_world 组节点 visible=false、SERVING 后 visible=true（mini-tree 注入带 group 的 mock 节点验证）；既有测试保持全绿
4. 文档：GDD 补「MENU 状态隐藏 game_world 组」约定；后续组装类 issue 的 DESIGN 把 group 契约写入节点清单

**风险**：新增世界节点忘记加 group → title 屏再次泄漏。对策：group 契约写入 GDD + 组装类 PRD 模板（本 PRD §5.2-6 已列）。

**参考文件**：`mini-pong/scenes/Main.tscn`、`mini-pong/gdscripts/game_state_machine.gd`、`mini-pong/gdscripts/wave_controller.gd`（group 寻址先例）、`docs/DESIGN/292-ui-system.md`、`docs/DESIGN/294-game-state-machine.md`、`docs/PRD/295-main-scene-assembly.md`

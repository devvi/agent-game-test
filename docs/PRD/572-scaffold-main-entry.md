# PRD #572 — [Scaffold] 项目骨架与正式场景入口（constants.gd + state_machine.gd + autoload 注册）

> **Issue:** #572
> **标签:** enhancement, infrastructure, version/mvp, workflow/available（research 阶段认领；stage-gate 对 research 接受 workflow/research 或 workflow/available）
> **深度:** standard（GitHub 无 depth label；分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=1 标注 `depth: standard` → §1–6 + §8 必填，§7 含实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: mechanical`（工程骨架，无品味裁决空间；DRAFT 数值的品味定稿归 #584）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`，wiki+raw grep 弹反/架势/格挡/状态机）+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`）+ GDD 分目录（`docs/GAME_DESIGN/shandong-wolf/01-OVERVIEW.md`）+ 开源插件调研（GitHub API 检索 6 个 Godot 状态机插件，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json`，estimate 1d，priority critical）
> **前置依赖:** #75a057a（P3 参数化收尾，merged）— manifest game.active 全链路参数化；#559/#562/#563/#567（shandong-wolf 骨架链路：Main.tscn 标题场景 + probe label + CI/E2E 打通，全部 merged）；mini-pong 先例（constants.gd / game_state_machine.gd / run_tests.gd 挂载模式，仅作模式参考）

---

## 1. 问题定义

### 1.1 现状（shandong-wolf/ 骨架状态，2026-08-19 侦查）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/project.godot` | ✅ 基本就绪 | `config/name="山东抗日之狼"`；`run/main_scene="res://scenes/Main.tscn"`；`window/size/viewport_width=1280`、`height=720`、`resizable=false`、stretch `canvas_items`（AC1 的窗口约束已满足）；**`[autoload]` 段缺失** |
| `shandong-wolf/scenes/Main.tscn` | ✅ 存在 | 纯声明式标题场景（#562/#563/#570）：Main(Node2D) → CanvasLayer → CenterContainer/VBox → TitleLabel「山东抗日之狼」+ SubtitleLabel「雪夜 · 大刀 · 山东村」+ VersionLabel「v0.1.0」+ PostMergeProbeLabel（管线探针，勿动）；零脚本零资源 |
| `shandong-wolf/gdscripts/` | ❌ 空 | 仅 `.gitkeep`；无 constants.gd、无 state_machine.gd、无任何 autoload 脚本 |
| `shandong-wolf/tests/check_compile.gd` | ✅ 可用 | 遍历 gdscripts/ + tests/ 逐个 load 校验（call_deferred 等 autoload 初始化后执行），新脚本自动纳入 |
| `shandong-wolf/tests/smoke_test.gd` | ✅ 可用 | 「SMOKE OK: shandong-wolf skeleton loads」，退出码 0 |
| `shandong-wolf/tests/run_tests.gd` | ⚠️ 占位 | 「skeleton — no tests yet」，退出码 0；未挂载任何测试套件 |

**核心缺口：** shandong-wolf 有可运行的主场景，但**无任何游戏逻辑脚本地基**——数值无集中地（后续 #573-578 的手感参数将散落硬编码，违反 brief「所有视觉与手感参数必须集中 constants.gd，禁止散落硬编码」红线）、无通用状态机基类（后续 #575 战斗实体状态机、#577 拼刀判定都将从零造轮子）、无 autoload 注册约定（后续控制器/管理器单例无统一挂载点）。本 issue 交付 = 三个地基文件 + autoload 注册 + 三入口测试全绿。

### 1.2 验收条件（源自 Issue #572 body，映射到各阶段 agent）

| # | 验收条件 | 负责阶段 | 本 PRD 的保障措施 |
|---|---------|---------|------------------|
| AC1 | scenes/Main.tscn 存在并可运行，窗口 1280x720 不可缩放 | implement（验证为主） | ✅ 已满足（#562）；implement 仅**验证**不重建：`godot --path shandong-wolf/` 首帧渲染标题 + project.godot 窗口配置断言 |
| AC2 | gdscripts/constants.gd 已创建，内含 # DRAFT 分区（弹反窗口/架势回复/两条命数值/刀伤害/帧节奏候补值） | implement | §4.1 方案 A + §5.1 AC2：RefCounted + class_name + const，5 个 # DRAFT 分区齐全，候补值显式标注「待 #584 定稿」，禁止实现期"顺手定稿" |
| AC3 | gdscripts/state_machine.gd 已创建，提供 enter/exit/update 三接口并含单元测试 | implement | §4.2 方案 A：通用基类（状态对象 enter/exit/update + transition_to + 防重入守卫）；tests/test_state_machine.gd 单测覆盖调用序/同态守卫/空状态 |
| AC4 | tests 三入口（compile/smoke/run）全绿 | implement/CI | §5.1 AC4：check_compile 自动扫描新脚本；smoke 保持绿；run_tests.gd 从占位升级为挂载 test_state_machine.gd（+ 可选 test_constants.gd），失败退出码非 0 |
| AC5 | 不得引入任何外部美术资产或 AI 生成像素动画帧 | implement | §8 红线：本 issue 零资源文件（仅 .gd/.tscn/project.godot），后续视觉一律程序化生成 |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 后续 feature issue 实现（#573-#578） | 每次 impl PR | 每个实现 agent 需要 constants.gd 集中读取手感参数、需要 state_machine.gd 做战斗/实体状态编排——地基缺失则各自散落硬编码 |
| B | CI 三入口（compile/smoke/run） | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/{check_compile,smoke_test,run_tests}.gd` 必须全绿；新增脚本不得破坏编译 |
| C | 玩家/开发者首启 | 手动 | `godot --path shandong-wolf/` 启动即见标题场景（1280x720 固定窗口），骨架成立 |

### 1.4 范围边界（与既有 PRD/后续 issue 去冲突，Patch 14）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #559（管线冒烟，merged） | Main.tscn 标题场景 + run/main_scene 指向 | ❌ 不重建/不修改 Main.tscn（含 PostMergeProbeLabel）；仅验证其为唯一入口 |
| #294（mini-pong GameStateMachine PRD） | mini-pong 场景级 FSM（enum + match，6 态编排） | ❌ 不复刻 mini-pong 的具体状态编排；只借鉴其「enter_state/transition 防重入」模式，抽象为通用基类 |
| #575（战斗实体基类与状态机，backlog） | 战斗实体的**具体**状态机（待机/移动/攻击/受击…） | ❌ 不设计任何战斗状态；#572 只交付**通用** enter/exit/update 基类，#575 在其上派生具体状态 |
| #584（战斗数值 DRAFT 集中表，backlog） | 手感数值**候选清单 + 调参面板 + 用户定稿** | ❌ 不产出完整候选数值表、不建调参面板；#572 只建 constants.gd 的 # DRAFT **分区骨架 + 结构**，候补值占位由 #584 接管定稿 |
| mini-pong 全部 | mini-pong 游戏逻辑（constants/FSM/测试先例） | ❌ 不复制 mini-pong 代码；其 constants.gd / test 挂载仅作模式参考（§8 注明可读文件） |

### 1.5 预期行为（最小骨架语义）

1. `shandong-wolf/gdscripts/constants.gd`：`class_name` + 常量分区（弹反窗口/架势回复/两条命数值/刀伤害/帧节奏），每分区 `# DRAFT` 标注 + 候补值 + 「该值影响什么/情感断言」注释（mini-pong 先例风格），**全部值标记待定稿**。
2. `shandong-wolf/gdscripts/state_machine.gd`：通用状态机基类，状态对象实现 `enter()/exit()/update(delta)` 三接口，基类提供 `transition_to()`（同态守卫 + 防重入）与 `update()` 转发。
3. `shandong-wolf/project.godot`：`[autoload]` 段建立统一注册点（推荐注册最小 `Game` 单例，见 §4.3）。
4. `shandong-wolf/tests/run_tests.gd`：从占位升级为真实挂载，跑通 state_machine 单测并输出 pass/fail 计数。
5. 三入口命令全绿，零美术资产。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，wiki + raw 全量 grep：`弹反|架势|格挡|状态机`）。
- **命中笔记：**
  - **《技术笔记》§动画系统**：*「Mecanim 动画系统：状态机设计、大型动画列表播放优化」*（Unity 语境）→ 佐证状态机基类应把**状态生命周期（enter/exit/update）与状态数据解耦**，动画/输入等系统可独立挂接——支撑 state_machine.gd 用「状态对象」而非「enum+match」的通用化设计（§4.2 方案 A）。
  - **《JRPG 战斗系统研究 - 最终综合报告》**（raw/Bear/）：*「弹反/闪避 = 时机判定（动作游戏）」*；FF16 **Stagger 系统 = 破防增伤**（ARPG 案例）；难度分层模型 *「基础：简单动作系统 → 进阶：连招/弹反/闪避 → 策略：属性/状态」* → 直接支撑 brief 的「弹反窗口 = 时机判定」「架势崩解 → 处决」循环（#577 判定系统语义），并佐证 **DRAFT 候补值应围绕"时机窗口/回复节奏/资源数量"三轴**组织（§4.1 分区设计依据）。
  - **《CUSGA 2026 游戏评选笔记》**：独立游戏「设计简洁有新意」评价语境（#559 已引）→ 骨架期克制原则：constants.gd/state_machine.gd 只做最小必要结构，不提前堆功能。
- **Vault 无 shandong-wolf 专属状态机/数值设计笔记**（命中均为通用原则）→ 结构权威源 = brief（`docs/RAW/shandong-wolf-brief.md` §数值：两条命=第 1 条归零→原地复活→第 2 条半管血；架势=格挡/弹反消耗、崩解→处决；草稿规范=constants.gd + # DRAFT + 候补值）+ GDD 01-OVERVIEW（场景现状）。

---

## 2. 设计意图

### 2.1 现状为何存在

| 原因 | 说明 |
|------|------|
| 管线冒烟优先 | #559-#570 阶段目标是打通 research→plan→implement→CI→E2E→merge→post-merge 全链路，骨架只承载标题场景 + probe label（GDD 01-OVERVIEW §1），游戏逻辑刻意留白 |
| 脚手架脚本产物 | `47f0a2b`（P3 参数化收尾）用 new-game-scaffold.sh 生成 shandong-wolf/ 空骨架：project.godot / Main.tscn / tests 三入口 / e2e_shots.json，gdscripts 与 assets 仅 .gitkeep |
| 数值定稿流程未启动 | brief 规定 A1 数值手感（弹反窗口/架势回复/两条命数值/刀伤害）走「# DRAFT + 候补值 → 用户定稿」（#584），骨架期不产出正式数值 |

### 2.2 为什么现在改

- #572 是分解清单（game-to-issues-shandong-wolf.json）中 **id=1 的第一个 issue**（critical / 1d），后续 #573 输入映射、#575 战斗状态机、#577 拼刀判定、#578 两条命全部以 constants.gd / state_machine.gd / autoload 为地基——**地基不立，后续每个实现 agent 都会各自造轮子或散落硬编码**，违背 brief 红线。
- 骨架链路（#559-#570）已验证管线可用，时机成熟：本 issue 是「管线空转」到「真实游戏开发」的转换点。

### 2.3 先前约束（继承自 issue body，Patch 19）

| 约束 | 值 | 来源 |
|------|-----|------|
| 引擎 | Godot 4.7.1 | manifest engine.version |
| 目录 | `shandong-wolf/`（manifest game.active 单一事实源） | manifest game.subprojects |
| 窗口 | 1280x720，resizable=false，stretch canvas_items | shandong-wolf/project.godot（AC1） |
| 参数集中 | 所有视觉与手感参数必须集中 constants.gd，禁止散落硬编码 | issue 上下文 / brief |
| 数值草稿规范 | constants.gd + `# DRAFT` + 候补值（不提前定稿） | brief §草稿规范 |
| 美术 | 零外部资产 / 零 AI 生成像素帧；视觉一律程序化（Line2D/Polygon2D + AnimationPlayer） | issue 上下文（AC5） |
| 开源优先 | 实现前先调研 Godot Asset Library/GitHub/社区，成熟方案优先，调研结果写入 PR | issue 上下文（§6.2 已执行） |
| 文字质感 | 短句克制（标题/探针文案已定，勿改） | issue 上下文 / GDD 01-OVERVIEW |

---

## 3. 影响分析

### 3.1 新文件（全部在 shandong-wolf/ 下）

| 文件 | 模块 | 说明 |
|------|------|------|
| `shandong-wolf/gdscripts/constants.gd` | 数值集中地 | `class_name WolfConstants`，extends RefCounted，5 个 # DRAFT 分区（弹反窗口/架势回复/两条命/刀伤害/帧节奏）+ 版本/窗口机械常量 |
| `shandong-wolf/gdscripts/state_machine.gd` | 通用状态机基类 | `class_name StateMachineBase`，extends RefCounted；状态对象 enter/exit/update 三接口 + transition_to 防重入守卫 + update 转发 |
| `shandong-wolf/gdscripts/game.gd` | autoload 锚点（方案 A，见 §4.3） | `class_name Game`，extends Node，最小单例：持有版本号 + 预加载 constants，供后续系统挂接 |
| `shandong-wolf/tests/test_state_machine.gd` | 单测（AC3 必需） | extends Object，run() + _assert 模式（mini-pong 先例），覆盖 enter/exit/update 调用序、同态 transition 守卫、空状态安全、防重入 |
| `shandong-wolf/tests/test_constants.gd` | 单测（推荐，非必需） | 断言 5 个 # DRAFT 分区常量存在且为候补值（防实现期误定稿） |

### 3.2 修改文件

| 文件 | 变更 | 性质 |
|------|------|------|
| `shandong-wolf/project.godot` | 新增 `[autoload]` 段：`Game="*res://gdscripts/game.gd"` | 新增段，不动现有 display/application 配置 |
| `shandong-wolf/tests/run_tests.gd` | 占位升级：`_run("res://tests/test_state_machine.gd", ...)`（+ test_constants.gd） | 行为变更（占位 → 真实测试） |

### 3.3 间接影响

- `check_compile.gd`：自动扫描 gdscripts/ + tests/ 新脚本，无需改动（autoload 引用经 call_deferred 解析）。
- CI（pipeline-tests.yml / opencode-review.yml）：随 manifest 参数化已自动跟随 game.active，**零改动**；impl PR 合入后 CI 自动跑 shandong-wolf 三入口。
- GDD `docs/GAME_DESIGN/shandong-wolf/`：post-merge agent 按约定补记（constants 分区 / autoload 注册），本 PRD 不写 GDD。
- 后续 issue：#573 输入控制器挂到 Game autoload；#575 从 StateMachineBase 派生；#584 接管 # DRAFT 值定稿。

### 3.4 数据流影响（启动链，骨架期）

```
project.godot run/main_scene
    │
    ▼
scenes/Main.tscn（纯声明式标题 UI，零脚本）── 首帧渲染「山东抗日之狼」+ v0.1.0
    │
[autoload] Game（gdscripts/game.gd）── 引擎启动即初始化（早于主场景 _ready）
    │      └── preload constants.gd（WolfConstants 静态常量表）
    ▼
tests（headless）
    ├── check_compile.gd ──► load gdscripts/*.gd + tests/*.gd（含新增 3 脚本）
    ├── smoke_test.gd ────► 工程加载 + autoload 初始化成功即退出 0
    └── run_tests.gd ─────► _run(test_state_machine.gd) ──► enter/exit/update 断言
```

### 3.5 需更新的文档

- [ ] `docs/PRD/572-scaffold-main-entry.md`（本文件）
- [ ] `docs/GAME_DESIGN/shandong-wolf/`（post-merge agent 补记：constants 分区表 + autoload 注册约定 + state_machine 基类接口）
- [ ] `docs/RAW/game-to-issues-shandong-wolf.json`（github_number 关联，脚本层处理）
- [ ] （不更新）docs/NAMING.md — mini-pong 专属，不涉及

---

## 4. 方案对比

### 4.1 constants.gd 组织形态

| 维度 | 方案 A：RefCounted + class_name + preload | 方案 B：autoload 单例 | 方案 C：无 class 纯 const 文件 |
|------|------------------------------------------|----------------------|------------------------------|
| 描述 | `class_name WolfConstants` extends RefCounted；消费方 `const C = preload("res://gdscripts/constants.gd")` | 注册为 autoload 全局单例，直接 `WolfConstants.XXX` 访问 | 裸 const 文件，`preload(...)` 后点成员访问 |
| 先例 | ✅ mini-pong constants.gd 完全一致（11 个手感参数定稿，验证成熟） | ❌ mini-pong 未采用（constants 不是 Node，无需挂场景树） | ❌ 无先例 |
| 优点 | 类型提示全、零运行时开销、import 即常量折叠；# DRAFT 注释可内联 | 全局直接访问免 preload | 最简单 |
| 缺点 | 消费方需 preload 一行 | 违背项目先例；constants 无状态，挂单例浪费 | 无类型提示；无 class_name 无法被工具链识别 |
| 风险 | Low | Med（架构不一致） | Med |
| 努力 | 0.5d | 0.5d | 0.25d |

**推荐：方案 A。** 与 mini-pong 先例完全对齐，check_compile 自动覆盖，`# DRAFT` 分区 + 情感断言注释可内联到每个 const（brief 草稿规范字面要求「constants.gd + # DRAFT + 候补值」）。

### 4.2 state_machine.gd 形态（含开源调研结论）

| 维度 | 方案 A：自研通用基类（状态对象） | 方案 B：引入第三方 addon | 方案 C：mini-pong 式 enum+match 单文件 FSM |
|------|-------------------------------|--------------------------|------------------------------------------|
| 描述 | `StateMachineBase`（RefCounted）：状态对象实现 enter/exit/update，基类管理 transition_to（同态守卫 + 防重入）+ update 转发，~40 行 | 引入 LimboAI（2962⭐）等插件 | enum State + match dispatch 单脚本 |
| 优点 | 精确满足「enter/exit/update 三接口 + 单元测试」验收；零依赖零插件导入；单测可直接实例化 | 功能全（BT+FSM、可视化） | mini-pong 已验证 |
| 缺点 | 无可视化（骨架期不需要） | 插件导入链 + .godot 缓存污染；2962⭐ 的 LimboAI 为 BT+FSM 重型框架，对「三接口基类」是过度工程；破坏「工程骨架最小化」 | **不通用**——具体状态写死在脚本里，违背 issue「通用状态机基类」字面要求；后续 #575 无法复用 |
| 风险 | Low | Med-High（插件与 Godot 4.7.1 兼容性、骨架期复杂度） | Med（不满足验收） |
| 努力 | 0.5-1d | 1-2d（含集成调试） | 0.5d |

**开源调研结论（issue「开源优先」要求，2026-08-19 GitHub API 实测）：** 检索 6 个候选——`limbonaut/limboai`（2962⭐，BT+FSM 重型框架）、`imjp94/gd-YAFSM`（668⭐，Yet Another FSM）、`gdquest-demos/godot-design-patterns`（443⭐，含最小 FSM 设计模式教学）、`Jeh3no/Godot-Advanced-State-Machine-First-Person-Controller`（232⭐，FPS 专用）、`kubecz3k/FiniteStateMachine`（118⭐）、`Daylily-Zeleen/HierarchicalFiniteStateMachine`（56⭐，可视化层级 FSM）。**结论：均不采纳。** 理由：① issue 验收的是「enter/exit/update 三接口 + 单元测试」的最小通用基类，约 40 行 GDScript 即满足，「轮子」本身过小，引入插件反而引入 .godot 插件导入链与版本兼容风险；② 最小 FSM 的惯用模式由 gdquest 设计模式库公开文档化，**以该模式为参考实现（零依赖）**，即「复用成熟方案的设计模式，而非引入其插件」；③ Godot 4.7 无内置 FSM，自研基类与引擎版本解耦。后续若需要 BT/层级 FSM（暂无需求），再评估 LimboAI。

**推荐：方案 A。** 状态对象模式与 Obsidian《技术笔记》「状态机设计」解耦原则一致；单测直接 `StateMachineBase.new()` + 两个 mock 状态断言调用序，headless 可跑（AC3）。

### 4.3 autoload 注册策略（「gdscripts/ 统一 autoload 注册」落点）

| 维度 | 方案 A：注册最小 Game 单例 | 方案 B：暂不注册，仅留约定 | 方案 C：注册 constants/state_machine 为 autoload |
|------|---------------------------|---------------------------|-------------------------------------------------|
| 描述 | `gdscripts/game.gd`（class_name Game, extends Node, ~15 行）注册为 `Game` autoload：持有版本号 + 预加载 constants，作为统一注册锚点 | project.godot 不加 [autoload] 段，只在 PRD/文档声明约定 | 把 constants.gd / state_machine.gd 挂为全局单例 |
| 优点 | 满足 issue 字面要求「gdscripts/ 统一 autoload 注册」；为 #573 输入控制器等提供挂接点；compile/smoke/run 三入口自动实测 autoload 机制 | 最保守，零新增文件 | 直接可用 |
| 缺点 | 新增一个"空"单例（骨架期无实际职责） | issue 功能描述明确列出 autoload 注册为交付物，留白会被 plan/implement 视为未完成；无实测验证 autoload 机制 | **架构错误**：constants 是静态常量表（非 Node），state_machine 是基类（非单例），挂 autoload 违背 mini-pong 先例且语义混乱 |
| 风险 | Low | Med（验收歧义） | High（语义错误） |
| 努力 | 0.25d | 0 | 0.25d |

**推荐：方案 A。** Game 单例是「统一注册」的物理落点：未来所有全局管理器（输入、战斗、音频）挂在 [autoload] 段 Game 之后，形成可预期的注册表；run_tests 的 call_deferred 机制已验证 autoload 兼容性（mini-pong 先例）。

### 4.4 推荐组合

| 子系统 | 推荐 | 核心文件 |
|--------|------|---------|
| 数值集中地 | A：RefCounted + class_name + preload | `shandong-wolf/gdscripts/constants.gd` |
| 状态机基类 | A：自研通用基类（状态对象三接口） | `shandong-wolf/gdscripts/state_machine.gd` |
| autoload 注册 | A：最小 Game 单例锚点 | `shandong-wolf/gdscripts/game.gd` |
| 单测挂载 | mini-pong 先例 `_run()` 模式 | `shandong-wolf/tests/test_state_machine.gd` |

推荐理由：① 三个方案 A 全部有项目内先例或公开成熟模式背书，零插件依赖，符合骨架期最小化；② 验收条件逐条可测（三入口命令 + 单测断言）；③ 为 #573-#584 建立无歧义的地基接口（class_name + # DRAFT 分区 + autoload 锚点），后续 issue 的 Plan 无需重新侦查。

---

## 5. 边界条件与验收

### 5.1 正常路径（AC 检查清单，映射 Issue body）

- [x] **AC1: scenes/Main.tscn 存在并可运行，窗口 1280x720 不可缩放**
  - 验证：`godot --path shandong-wolf/ --headless --quit` 退出码 0；`grep -E 'viewport_width|viewport_height|resizable' shandong-wolf/project.godot` 命中 1280/720/false；Main.tscn 保持零脚本（不因本 issue 改动）
- [x] **AC2: gdscripts/constants.gd 已创建，内含 # DRAFT 分区**
  - 验证：`grep -c '# DRAFT' shandong-wolf/gdscripts/constants.gd` ≥ 5；5 个分区名（弹反窗口/架势回复/两条命数值/刀伤害/帧节奏）齐全；每个 const 带候补值 + 注释，无定稿标记（`# 定稿` 字样出现即 FAIL）
- [x] **AC3: gdscripts/state_machine.gd 提供 enter/exit/update 三接口并含单元测试**
  - 验证：`grep -nE 'func (enter|exit|update)'` 在状态对象接口文档/基类中出现三接口；`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 输出包含 state machine 测试 pass 计数且退出码 0
- [x] **AC4: tests 三入口全绿**
  - 验证：三条命令逐一执行退出码均为 0——
    `godot --path shandong-wolf/ --headless --script tests/check_compile.gd`
    `godot --path shandong-wolf/ --headless --script tests/smoke_test.gd`
    `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`
- [x] **AC5: 不得引入外部美术资产或 AI 生成像素帧**
  - 验证：impl PR diff 仅含 .gd / .tscn / project.godot；`find shandong-wolf/ -newer ... -name '*.png' -o -name '*.jpg'` 无新增

### 5.2 边界情况

1. **多游戏共存下的 class_name 冲突**：shandong-wolf 与 mini-pong 是独立 Godot 工程（各自 project.godot/.godot 缓存），class_name 作用域隔离；仍建议 shandong-wolf 用 `WolfConstants`/`StateMachineBase` 前缀命名，避免未来工具链（如 check_compile 跨目录扫描）歧义。
2. **# DRAFT 候补值被实现期"顺手定稿"**：红线——constants.gd 所有手感值必须保留 `# DRAFT` 标记与候补值注释；定稿流程专属 #584。test_constants.gd 可断言 `# DRAFT` 存在性防回归。
3. **autoload 初始化顺序**：Game autoload 的 `_ready` 早于主场景；若 Game 引用 constants 用 preload（编译期静态），无初始化顺序问题；禁止在 Game 中依赖其他未注册单例。
4. **check_compile 对 autoload 引用的解析**：run_tests/check_compile 已用 call_deferred 等待 autoload 就绪（mini-pong 同款），新 autoload 注册后编译检查仍应通过；若失败，先查 project.godot [autoload] 路径是否 `*res://` 前缀。
5. **run_tests.gd 挂载空测试**：若 test_state_machine.gd 存在但 run() 未执行（挂载遗漏），run_tests 必须 FAIL（pass=0 且无输出 → 退出码非 0），禁止静默绿。
6. **Main.tscn 探针 label 回归**：PostMergeProbeLabel 是管线冒烟物（#570），本 issue 不得增删改 Main.tscn 任何节点。

### 5.3 失败路径

1. **run_tests.gd 挂载后出现编译错误**（state_machine.gd 或 test 文件语法/类型错误）→ check_compile 与 run_tests 双双 FAIL；处理：在 worktree 内修正脚本直至三入口全绿，禁止跳过测试直接提交。
2. **autoload 注册导致 smoke 失败**（project.godot [autoload] 路径错误或脚本 _ready 崩溃）→ smoke_test 退出非 0；处理：检查路径 `*res://gdscripts/game.gd` 与脚本 extends Node，回退方案 B（暂不注册）并在 PR 说明。
3. **# DRAFT 分区缺失**（实现遗漏某分区）→ AC2 grep 计数不足；处理：按 §1.2 表逐分区补齐，宁可候补值粗糙不可缺分区（结构 > 数值，数值归 #584）。
4. **worktree 冲突**（worktree-commit.sh merge origin/main 冲突）→ 按脚本冲突分级处理；无法自动解决则 abort 并报告，不硬解。

---

## 6. 依赖与阻塞

### 6.1 依赖表

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #75a057a（P3 参数化：manifest game.active 全链路） | ✅ merged | Low |
| #559/#562/#563/#567（shandong-wolf 骨架链路 + probe label） | ✅ merged | Low |
| mini-pong 先例（constants.gd / game_state_machine.gd / run_tests.gd 挂载模式） | ✅ 可读参考 | Low |
| Godot 4.7.1 运行时（三入口命令） | ✅ 环境就绪 | Low |
| 第三方 addon | ❌ 不引入（§4.2 调研结论） | — |

### 6.2 开源调研记录（issue「开源优先」要求，写入 PR 的调研结果）

| 候选 | Stars | 评估 | 结论 |
|------|-------|------|------|
| limbonaut/limboai | 2962 | BT+FSM 重型框架，插件导入链复杂 | ❌ 过度工程 |
| imjp94/gd-YAFSM | 668 | 通用 FSM，但为完整插件 | ❌ 三接口基类自研更轻 |
| gdquest-demos/godot-design-patterns | 443 | 最小 FSM 惯用模式公开文档 | ✅ 作为设计模式参考（零依赖） |
| Jeh3no/Godot-Advanced-State-Machine-First-Person-Controller | 232 | FPS 专用控制器 | ❌ 领域不匹配 |
| kubecz3k/FiniteStateMachine | 118 | 轻量 FSM 插件 | ❌ 自研 ~40 行等价 |
| Daylily-Zeleen/HierarchicalFiniteStateMachine | 56 | 层级 FSM 可视化 | ❌ 骨架期不需要 |

### 6.3 依赖链

```
#75a057a（P3 参数化）→ #559/#562/#563/#567（骨架链路）→ ★ #572（本 issue：地基）
    ├──→ #573 输入映射与玩家控制器（挂 Game autoload）
    ├──→ #575 战斗实体基类与状态机（派生 StateMachineBase）
    ├──→ #577 拼刀/弹反/架势崩解判定（消费 constants DRAFT 分区）
    └──→ #584 战斗数值 DRAFT 集中表（接管 constants 定稿）
```

### 6.4 准备清单

- [ ] implement agent 先读本 PRD §3.1/§3.2 文件清单 + §5.3 失败路径
- [ ] implement agent 读 mini-pong 先例：`mini-pong/gdscripts/constants.gd`（注释风格）、`mini-pong/gdscripts/game_state_machine.gd`（transition 防重入）、`mini-pong/tests/run_tests.gd`（_run 挂载）
- [ ] 无阻塞项

---

## 7. Spike / 实验（standard 深度，含 3 个轻量实验）

### 实验 1：单测先行驱动 state_machine.gd 接口

- **问题**：enter/exit/update 三接口的调用语义（进入时 exit 先于 enter？同态 transition 是否吞掉？）如何被机器验证。
- **方法**：在写 state_machine.gd 之前先写 test_state_machine.gd（两个 mock 状态记录调用日志），再实现基类使测试通过。
- **预期结果**：断言顺序 exit(old) → enter(new)；同态 transition 不触发任何回调；update(delta) 转发给当前状态；空状态（无 current_state）下 update/transition 不崩溃。
- **对方案的影响**：验证 §4.2 方案 A 的接口契约，失败则回调设计（如改为基类持有 enter/exit/update 方法本身而非状态对象）需调整。

### 实验 2：三入口全绿实测（headless）

- **问题**：新增 3 个脚本 + autoload 后，compile/smoke/run 是否仍全绿。
- **方法**：在 worktree 内依次执行三条命令（§5.1 AC4），记录退出码。
- **预期结果**：三条均退出 0；check_compile 输出新增脚本 count 增加；run_tests 输出「TESTS: N passed, 0 failed」且 N ≥ 状态机用例数。
- **对方案的影响**：任何一条非绿 → 按 §5.3 失败路径处理，不提交。

### 实验 3：Game autoload + Main.tscn 启动链冒烟

- **问题**：注册 Game 单例后，主场景启动链是否被破坏（autoload 与零脚本 Main.tscn 的兼容性）。
- **方法**：`godot --path shandong-wolf/ --headless --quit`（加载主场景）+ smoke_test。
- **预期结果**：退出码 0，无 autoload 相关报错；probe label 场景仍可实例化（E2E 截图不受影响）。
- **对方案的影响**：失败则回退 §4.3 方案 B（暂不注册 autoload），并在 PR 中说明原因。

---

## 8. 交接上下文（Continuation Context）

**系统状态（plan agent 接手时）：** shandong-wolf/ 骨架链路全绿（#559-#570），Main.tscn 为纯声明式标题场景，gdscripts/ 与 assets/ 空，[autoload] 段不存在，run_tests.gd 为占位。本 PRD 已定：3 个新文件 + 2 个修改文件（§3.1/§3.2）+ 三入口全绿验收。

**plan agent 下一步：**
1. 读本 PRD §4 推荐组合（4.4 表）——直接按推荐方案出 DESIGN，无需重新对比方案。
2. 文件落点（白名单）：`shandong-wolf/gdscripts/constants.gd`、`shandong-wolf/gdscripts/state_machine.gd`、`shandong-wolf/gdscripts/game.gd`、`shandong-wolf/tests/test_state_machine.gd`、`shandong-wolf/tests/test_constants.gd`（推荐）、修改 `shandong-wolf/project.godot`（[autoload] 段）、`shandong-wolf/tests/run_tests.gd`（挂载）。
3. 红线（implement 必须遵守）：
   - ❌ 绝不触碰 `mini-pong/` 任何文件；❌ 绝不 `git add .`（白名单提交）
   - ❌ 不修改 `shandong-wolf/scenes/Main.tscn`（含 PostMergeProbeLabel）
   - ❌ 不引入任何美术资产 / 插件 addon / 像素帧
   - ✅ constants.gd 所有手感值保持 `# DRAFT` + 候补值，定稿归 #584
   - ✅ 三入口命令本地实测全绿后才提交
4. 参考文件（只读）：`mini-pong/gdscripts/constants.gd`（注释风格）、`mini-pong/gdscripts/game_state_machine.gd`（transition 防重入模式）、`mini-pong/tests/run_tests.gd`（_run 挂载）、`mini-pong/tests/test_game_state_machine.gd`（单测模式）、`docs/RAW/shandong-wolf-brief.md`（数值语义）。
5. 后续 issue 衔接：#573 输入控制器挂 Game autoload；#575 从 StateMachineBase 派生战斗状态机；#577 消费 constants 的弹反/架势分区；#584 接管 # DRAFT 定稿并建调参面板。
6. 合并后：post-merge agent 补记 GDD（constants 分区表 + autoload 注册 + 基类接口）；workflow-chain.yml 自动推进 label（research → plan）；本 PR 由脚本层合并，research agent 不自行 merge。

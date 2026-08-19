# Design: [Scaffold] 项目骨架与正式场景入口 — constants.gd + state_machine.gd + autoload 注册

> **Parent Issue:** #572
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4.4 推荐组合 —— 三个子系统**全部确认采纳方案 A**（constants.gd=RefCounted+class_name+preload；state_machine.gd=自研通用基类，状态对象 enter/exit/update；autoload=最小 Game 单例锚点）；方案 B/C（第三方 addon、enum+match 单文件、autoload 挂 constants）显式否决，理由同 PRD §4
> **Reference PRD:** `docs/PRD/572-scaffold-main-entry.md`（research PR #597 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/559-shandong-wolf-pipeline-smoke.md`（Main.tscn 场景结构）、`docs/DESIGN/567-post-merge-probe.md`（骨架期最小 diff 纪律）；mini-pong 先例 `constants.gd`（注释风格）/`game_state_machine.gd`（transition 防重入）/`run_tests.gd`（_run 挂载）/`test_game_state_machine.gd`（单测模式），仅作模式参考不复制代码
> **所有权:** `content_ownership: mechanical`（工程骨架 = 纯机械地基，无品味裁决空间；# DRAFT 数值的品味定稿归 #584，本设计明确不碰数值定稿）
> **深度:** standard（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=1 标注 depth: standard；GitHub 无 depth 标签）—— 7 文件 / 4 子系统 6+ 独立子任务 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统）
> **红线:** 只动 `shandong-wolf/` 下 7 文件（5 新建 + 2 修改，见 §3）；**绝不触碰** `mini-pong/`、`shandong-wolf/scenes/Main.tscn`（含 PostMergeProbeLabel）、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`（GDD 是 post-merge agent 职责）；零美术资产/零插件/零像素帧

---

## 1. 架构总览

**问题本质是「有场景、无逻辑地基」而非功能缺陷。** shandong-wolf 经 #559-#570 骨架链路已具备可运行主场景（`scenes/Main.tscn` 纯声明式标题场景，1280x720 不可缩放），但 `gdscripts/` 为空：数值无集中地（后续 #573-#578 的手感参数将散落硬编码，违反 brief「所有视觉与手感参数必须集中 constants.gd，禁止散落硬编码」红线）、无通用状态机基类（#575 战斗状态机、#577 拼刀判定将各自从零造轮子）、无 autoload 注册约定（后续控制器/管理器单例无统一挂载点）。本 issue 交付 = **三个地基文件 + autoload 注册 + 三入口测试全绿**。

**设计哲学：最小地基 + 零依赖 + 结构先行。** 三个组件全部取「骨架期最小必要结构」：constants.gd 只建 `# DRAFT` 分区骨架与候补值注释（数值定稿归 #584，禁止实现期顺手定稿）；state_machine.gd 只实现通用三接口基类（不设计任何战斗状态，具体状态是 #575 的事）；Game autoload 只做最小锚点（不堆职责）。开源调研（PRD §6.2，6 个 FSM 插件：LimboAI 2962⭐ / gd-YAFSM 668⭐ / gdquest-design-patterns 443⭐ 等）结论：**三接口基类约 40 行自研即满足，不引入第三方 addon**，gdquest 最小 FSM 设计模式为零依赖参考——本设计确认采纳。

```
                 ★ Issue #572 本设计（shandong-wolf 逻辑地基）
┌────────────────────────────────────────────────────────────────────────────┐
│ 新建（5 文件，全部 shandong-wolf/ 下）                                        │
│  gdscripts/constants.gd      WolfConstants（RefCounted）                     │
│    └─ 5 个 # DRAFT 分区: 弹反窗口/架势回复/两条命数值/刀伤害/帧节奏 + 机械常量   │
│  gdscripts/state_machine.gd  StateMachineBase（RefCounted）                  │
│    └─ 状态对象 enter/exit/update 三接口 + transition_to（同态守卫+防重入）      │
│  gdscripts/game.gd           Game（Node，autoload 锚点）                     │
│    └─ 版本号 + preload constants（供 #573 等后续系统挂接）                     │
│  tests/test_state_machine.gd 单测: 调用序/同态守卫/防重入/空状态               │
│  tests/test_constants.gd     单测: 5 分区存在性 + 无定稿标记（防误定稿回归）     │
├────────────────────────────────────────────────────────────────────────────┤
│ 修改（2 文件）                                                               │
│  project.godot              [autoload] Game="*res://gdscripts/game.gd"       │
│  tests/run_tests.gd         占位 → _run(test_state_machine) + _run(test_constants) │
├────────────────────────────────────────────────────────────────────────────┤
│ 验证（0 改动）: scenes/Main.tscn 保持纯声明式（AC1 窗口约束 #562 已满足）        │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    ▼
              godot --path shandong-wolf/（启动链）
                ├─ [autoload] Game 初始化（早于主场景 _ready）
                ├─ Main.tscn 首帧渲染标题（1280x720 固定窗口）
                └─ headless 三入口: check_compile / smoke_test / run_tests 全绿
```

**与 PRD 方案裁决的一致性：** PRD §4.1/§4.2/§4.3 各推荐方案 A，§4.4 汇总推荐组合。本设计逐项确认采纳，无分歧；PRD §7 三个 Spike（单测先行驱动接口 / 三入口全绿实测 / autoload 启动链冒烟）为 implement Phase 0 执行项，其结论对本设计无结构性影响（仅验证接口契约与启动链，失败路径 PRD §5.3 已给回退：autoload 失败 → 方案 B 暂不注册）。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实） | 与 #572 的差距 |
|------|--------------------------------------------------|---------------|
| `shandong-wolf/project.godot` | ✅ name=山东抗日之狼、`run/main_scene="res://scenes/Main.tscn"`、1280x720 resizable=false、stretch canvas_items 全设；**`[autoload]` 段缺失** | ❌ 新增 `[autoload]` 段（Game） |
| `shandong-wolf/scenes/Main.tscn` | ✅ 纯声明式标题场景（#562/#563/#570）：Main→CanvasLayer→CenterContainer/VBox→TitleLabel+SubtitleLabel；VersionLabel 左下；PostMergeProbeLabel 右下探针 | 无（AC1 验证为主，**不改**） |
| `shandong-wolf/gdscripts/` | ❌ 空（仅 .gitkeep） | ❌ 新建 constants.gd / state_machine.gd / game.gd |
| `shandong-wolf/tests/check_compile.gd` | ✅ 遍历 gdscripts/+tests/ 逐个 load（call_deferred 等 autoload 就绪），新脚本自动纳入 | 无改动 |
| `shandong-wolf/tests/smoke_test.gd` | ✅ 「SMOKE OK」，退出码 0 | 无改动 |
| `shandong-wolf/tests/run_tests.gd` | ⚠️ 占位「skeleton — no tests yet」，无套件挂载 | ❌ 升级为挂载 test_state_machine.gd + test_constants.gd |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位（states 空） | 无（PRD 未要求，不动） |
| `mini-pong/`（先例） | ✅ constants.gd / game_state_machine.gd / run_tests.gd / test_* 全套 | 仅作模式参考，**不复制** |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| project.godot 窗口约束已满足（1280x720 / resizable=false） | ✅ 属实（`[display]` 段） | 零改动，AC1 仅验证 |
| project.godot 无 `[autoload]` 段 | ✅ 属实（全文无 autoload 段） | 新增 `[autoload]` 段，不动现有段 |
| Main.tscn 零脚本纯声明式 | ✅ 属实（tscn 无 ext_resource、无 script） | 保持，**不修改**（含探针 label） |
| gdscripts/ 空 | ✅ 属实（仅 .gitkeep） | 新建 3 脚本 |
| run_tests.gd 为占位 | ✅ 属实（「skeleton — no tests yet」，_pass/_fail 计数框架已有） | 在 `_run_tests()` 内追加 `_run(...)` 挂载行 |
| check_compile 自动覆盖新脚本 | ✅ 属实（DirAccess 遍历 gdscripts/+tests/） | 零改动 |
| mini-pong `game_state_machine.gd` 的 transition 防重入模式可借鉴 | ✅ 属实（`_transition_lock` + `enter_state` 防重入） | 抽象为通用基类的同态守卫 + 防重入（§2.2） |
| mini-pong `constants.gd` 注释风格（该值影响什么/情感断言）可借鉴 | ✅ 属实（每个定稿 const 带双注释） | 移植为「候补值 + 影响 + 情感断言」三行注释（§2.1） |
| Godot 4.7 默认字体含 CJK | ✅ 属实（Main.tscn 中文 Label 正常） | constants.gd 注释可用中文 |

---

## 2. 新组件 — 详细设计

### 2.1 `shandong-wolf/gdscripts/constants.gd`（新建，数值集中地）

- **文件:** `shandong-wolf/gdscripts/constants.gd`
- **类:** `class_name WolfConstants`，`extends RefCounted`（方案 A：非 Node，不挂场景树，preload 静态访问）
- **消费方模式:** `const C = preload("res://gdscripts/constants.gd")` → `C.PARRY_WINDOW_FRAMES`
- **结构:** 机械常量区（非 taste 参数，可定稿）+ 5 个 `# DRAFT` 手感分区（全部候补值，**禁止定稿**）

```gdscript
extends RefCounted
## WolfConstants — shandong-wolf 全局常量单一事实源。
## 消费方: const C = preload("res://gdscripts/constants.gd")
## 手感分区全部 # DRAFT 候补值，定稿归 #584（taste 域，本文件禁止"顺手定稿"）。

class_name WolfConstants

# ── 机械常量（非 taste 参数，骨架期定稿）──
const GAME_VERSION: String = "v0.1.0"        # 与 Main.tscn VersionLabel 一致（#562）
const SCREEN_WIDTH: int = 1280               # project.godot viewport_width（AC1）
const SCREEN_HEIGHT: int = 720               # project.godot viewport_height（AC1）
const STATE_MACHINE_MAX_TRANSITIONS: int = 1 # 状态机单次 update 允许的最大 transition 数（防重入，§2.2）

# ── 弹反窗口（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 12 帧 @60fps = 0.2s（只狼系参考: 弹反判定极短，成功即架势重创）
#   该值影响什么: 弹反判定时间窗——越短越硬核，越长越宽容；帧节奏候补值联动（§帧节奏）
#   情感断言: 生死一瞬的"叮"——成功弹反是最高潮时刻，窗口必须短到值得炫耀
const PARRY_WINDOW_FRAMES: int = 12          # # DRAFT
const PARRY_WINDOW_SECONDS: float = 0.2      # # DRAFT（= FRAME_RHYTHM 的派生展示，不重复定义来源）

# ── 架势回复（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 0.8 架势/秒 自然回复；格挡消耗 10；弹反成功不消耗反而崩解敌方
#   该值影响什么: 架势（士气）条 = 格挡/弹反资源；崩解 → 处决（brief 核心机制 #5）
#   情感断言: 攻防节奏的呼吸感——防守方靠回复喘息，进攻方靠持续压制崩解
const POSTURE_RECOVERY_PER_SEC: float = 0.8  # # DRAFT
const POSTURE_BLOCK_COST: float = 10.0       # # DRAFT
const POSTURE_BREAK_THRESHOLD: float = 100.0 # # DRAFT（满则崩解）

# ── 两条命数值（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 第 1 条满血 100；归零 → 原地复活（第 2 条半管血 50）
#   该值影响什么: 只狼式两条命（brief 核心机制 #4）——第 1 条是容错，第 2 条是决心
#   情感断言: 复活仪式感 + 半管血的紧迫——第二次倒下就是真的输了
const LIFE_TOTAL: int = 2                    # # DRAFT（两条命，机械语义可定稿）
const LIFE_1_MAX: float = 100.0              # # DRAFT
const LIFE_2_MAX_RATIO: float = 0.5          # # DRAFT（第 2 条 = 半管血）

# ── 刀伤害（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 轻击 10 / 重击 25；处决 999（无视架势直接击杀）
#   该值影响什么: 击杀节奏（普通兵 3-4 刀 vs 精英 8-10 刀）；刀来自尸体（brief 剧情起点）
#   情感断言: 刀刀见血不拖沓——每刀都有明确的"砍中了"反馈
const SWORD_DAMAGE_LIGHT: float = 10.0       # # DRAFT
const SWORD_DAMAGE_HEAVY: float = 25.0       # # DRAFT
const SWORD_DAMAGE_EXECUTE: float = 999.0    # # DRAFT（处决 = 架势崩解后终结）

# ── 帧节奏（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 攻击前摇 8 帧 / 攻击后摇 14 帧 / 弹反窗口 12 帧（与 PARRY_WINDOW 联动）
#   该值影响什么: 攻防节奏的"帧感"（只狼系动作游戏的核心手感）；所有动画关键帧规划基准
#   情感断言: 干脆利落——前摇可读、后摇可惩罚，拼刀节奏像呼吸
const FRAME_ATTACK_WINDUP: int = 8           # # DRAFT
const FRAME_ATTACK_RECOVERY: int = 14        # # DRAFT
const FRAME_RHYTHM_BASE: int = 60            # # DRAFT（基准帧率参考）
```

- **集成说明:** check_compile 自动纳入（gdscripts/ 扫描）；消费方 #573-#578 通过 preload 读取；`# DRAFT` 标记是 test_constants.gd 的断言对象（§8 Scenario E），**实现期删除 # DRAFT 或改值定稿 = 测试 FAIL**。

### 2.2 `shandong-wolf/gdscripts/state_machine.gd`（新建，通用状态机基类）

- **文件:** `shandong-wolf/gdscripts/state_machine.gd`
- **类:** `class_name StateMachineBase`，`extends RefCounted`（非 Node：不依赖场景树，headless 单测可直接实例化）
- **设计:** 状态对象模式（gdquest 最小 FSM 惯用模式，零依赖参考）——具体状态是普通 Object/RefCounted，实现三接口；基类只管转移与转发。**不设计任何具体状态**（#575 职责）。

```gdscript
extends RefCounted
## StateMachineBase — 通用状态机基类（#572）。
## 状态对象（任意 Object）实现 enter()/exit()/update(delta) 三接口；
## 基类提供 transition_to()（同态守卫 + 防重入）与 update() 转发。
## 派生: #575 战斗实体状态机在其上定义具体状态。

class_name StateMachineBase

var current_state: Object = null      # 当前状态对象（可为 null = 空状态）
var _transition_locked: bool = false  # 防重入锁（transition 进行中禁止再 transition）

## 三接口契约（状态对象实现，本基类不实现具体逻辑）:
##   func enter() -> void          # 进入状态：初始化
##   func exit() -> void           # 退出状态：清理
##   func update(delta: float) -> void  # 每帧逻辑（由基类 update() 转发）

func transition_to(new_state: Object) -> void:
    ## 转移: 同态守卫（同对象不重复触发）+ 防重入守卫（转移中禁止嵌套转移）
    if _transition_locked:
        push_warning("StateMachineBase: transition blocked — re-entrant call")
        return
    if new_state == current_state:
        return  # 同态守卫: 目标 == 当前，静默忽略（无回调）
    _transition_locked = true
    if current_state != null and current_state.has_method("exit"):
        current_state.exit()
    current_state = new_state
    if current_state != null and current_state.has_method("enter"):
        current_state.enter()
    _transition_locked = false

func update(delta: float) -> void:
    ## 转发: 空状态安全（current_state == null 时 no-op）
    if current_state != null and current_state.has_method("update"):
        current_state.update(delta)
```

- **关键决策（与 mini-pong 差异点，需 implement 注意）:** mini-pong `game_state_machine.gd` 是 enum+match 的场景级 FSM（Node 挂场景树，`_transition_lock` 防重入）；本基类是**通用** RefCounted 基类（不绑定场景、不绑定具体状态枚举），`has_method` 守卫替代类型约束（Godot 无接口，鸭子类型），**不复制 mini-pong 代码**（PRD §1.4 范围边界）。
- **集成说明:** #575 在其上派生：`class BattleStateMachine extends StateMachineBase` + 具体状态对象实现三接口；`STATE_MACHINE_MAX_TRANSITIONS` 常量预留给后续若需"单帧单转移"硬限制（本期仅防重入锁，不额外实现计数）。

### 2.3 `shandong-wolf/gdscripts/game.gd`（新建，autoload 锚点）

- **文件:** `shandong-wolf/gdscripts/game.gd`
- **类:** `class_name Game`，`extends Node`（autoload 必须 Node）
- **职责（最小锚点，不堆职责）:** 持有版本号 + 预加载 constants，作为统一注册锚点（#573 输入控制器等后续系统挂接处）。

```gdscript
extends Node
## Game — shandong-wolf 全局 autoload 锚点（#572）。
## 注册: project.godot [autoload] Game="*res://gdscripts/game.gd"
## 职责: 最小单例——版本号 + constants 预加载；后续系统（输入/战斗/音频）挂接于此。

const WolfConstants = preload("res://gdscripts/constants.gd")

var game_version: String = WolfConstants.GAME_VERSION
```

- **注册:** `shandong-wolf/project.godot` 新增段（不动 `[application]`/`[display]`）：
  ```ini
  [autoload]
  Game="*res://gdscripts/game.gd"
  ```
- **集成说明:** autoload 初始化早于主场景 `_ready`（引擎启动即加载）；constants 用 **preload 编译期静态引用**，无初始化顺序问题（PRD §5.2-3）；`*res://` 前缀是 autoload 必需格式（PRD §5.2-4，漏前缀会导致编译检查失败）。

### 2.4 测试文件（新建，仅测试用例描述——plan 阶段不写可运行测试代码）

- **`shandong-wolf/tests/test_state_machine.gd`**（AC3 必需）: extends Object，`run()` 入口 + `_assert` 计数模式（mini-pong test_game_state_machine.gd 同款结构，不复制其用例）。两个 mock 状态对象（`_MockStateA`/`_MockStateB`，记录 enter/exit/update 调用日志），直接 `StateMachineBase.new()` 实例化断言。用例见 §8 Scenario A-D。
- **`shandong-wolf/tests/test_constants.gd`**（推荐，PRD §3.1）：extends Object，断言 5 个 `# DRAFT` 分区常量存在、值为候补值、文件无定稿标记。用例见 §8 Scenario E。

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 性质 | 伪代码 |
|------|------|------|--------|
| `shandong-wolf/project.godot` | 新增 `[autoload]` 段：`Game="*res://gdscripts/game.gd"` | 新增段（不动现有配置） | `[autoload]` 段追加在文件末尾或 `[application]` 之后 |
| `shandong-wolf/tests/run_tests.gd` | `_run_tests()` 从占位升级：挂载 2 个套件 + 汇总计数 | 行为变更（占位 → 真实测试） | `_run("res://tests/test_state_machine.gd", "State Machine")` + `_run("res://tests/test_constants.gd", "Constants")`；`_pass/_fail` 汇总逻辑保留 |

### 3.2 新文件清单

| 文件 | 说明 |
|------|------|
| `shandong-wolf/gdscripts/constants.gd` | WolfConstants（§2.1） |
| `shandong-wolf/gdscripts/state_machine.gd` | StateMachineBase（§2.2） |
| `shandong-wolf/gdscripts/game.gd` | Game autoload（§2.3） |
| `shandong-wolf/tests/test_state_machine.gd` | 状态机单测（§2.4） |
| `shandong-wolf/tests/test_constants.gd` | 常量分区断言（§2.4） |

### 3.3 不修改（显式声明，防越界）

| 文件 | 原因 |
|------|------|
| `shandong-wolf/scenes/Main.tscn` | AC1 验证为主；探针 label（#570）与标题结构零改动（PRD §5.2-6 / §8 红线） |
| `shandong-wolf/tests/check_compile.gd` / `smoke_test.gd` | 自动覆盖/保持绿，无改动需求 |
| `shandong-wolf/e2e_shots.json` | PRD 未要求 |
| `mini-pong/` 全部 | 跨游戏红线（PRD §8） |
| `game-env/manifest.yaml` / `.github/workflows/` | 管线配置非本 issue 职责（已参数化自动跟随） |
| `docs/GAME_DESIGN/` | GDD 补记是 post-merge agent 职责 |

---

## 4. 数据流

### Flow 1: 启动链（正常路径）
```
godot --path shandong-wolf/
  ├─ 引擎启动 → project.godot [autoload] 段 → Game 单例初始化（preload constants → game_version=v0.1.0）
  ├─ run/main_scene="res://scenes/Main.tscn" → 实例化（纯声明式 UI，零脚本）
  │    └─ 首帧渲染: TitleLabel「山东抗日之狼」+ SubtitleLabel + VersionLabel v0.1.0 + PostMergeProbeLabel
  └─ 窗口: 1280x720, resizable=false（AC1）→ 首帧可见即成立
```

### Flow 2: 状态机转移（正常/异常路径）
```
正常:  State A (enter) ──transition_to(B)──► B.enter()；A.exit() 先于 B.enter()（调用序契约）
       update(delta) 每帧转发给 current_state.update(delta)
异常1: transition_to(A) 当 current_state==A → 同态守卫: 静默忽略，无任何回调
异常2: A.enter() 内嵌套 transition_to(C) → 防重入锁: push_warning + 忽略（_transition_locked 期间）
异常3: current_state == null 时 update()/transition_to() → 空状态安全: no-op 不崩溃
```

### Flow 3: 三入口测试流（CI/本地）
```
godot --path shandong-wolf/ --headless --script tests/check_compile.gd  → load gdscripts/ 3 脚本 + tests/ 5 脚本，退出 0
godot --path shandong-wolf/ --headless --script tests/smoke_test.gd    → 工程加载 + autoload 初始化成功，退出 0
godot --path shandong-wolf/ --headless --script tests/run_tests.gd     → _run(test_state_machine) + _run(test_constants) → TESTS: N passed, 0 failed，退出 0
```

---

## 5. 边界情况与错误处理

| Edge Case | Mitigation |
|-----------|------------|
| 1. 同态 transition（目标 == 当前状态） | 同态守卫：直接 return，不触发 exit/enter（§2.2，测试 Scenario B） |
| 2. 重入 transition（enter() 内嵌套转移） | `_transition_locked` 防重入锁：push_warning + 忽略（§2.2，测试 Scenario C） |
| 3. 空状态（current_state == null） | update()/transition_to() 均 no-op 安全；转移目标为 null 时仅 exit 不 enter（§2.2，测试 Scenario D） |
| 4. # DRAFT 候补值被实现期"顺手定稿" | 红线 + test_constants.gd 断言：5 分区常量存在 + 文件含 `# DRAFT` 标记 + 无定稿字样（§8 Scenario E，PRD §5.2-2） |
| 5. autoload 初始化顺序 | Game 内 constants 用 preload（编译期静态），无运行时顺序依赖；Game 不引用其他未注册单例（PRD §5.2-3） |
| 6. check_compile 对 autoload 引用解析失败 | run_tests/check_compile 已用 call_deferred 等 autoload 就绪；若失败先查 project.godot `[autoload]` 路径是否 `*res://` 前缀（PRD §5.2-4） |
| 7. run_tests 挂载空测试（挂载遗漏静默绿） | run_tests 必须 FAIL：pass==0 且无输出 → 退出码非 0，禁止静默绿（PRD §5.2-5，§8 Scenario F） |
| 8. Main.tscn 探针 label 回归 | 本 issue 零改动 Main.tscn；implement 若误改 → review 阶段 diff 核查（PRD §5.2-6） |
| 9. class_name 跨游戏冲突 | shandong-wolf 与 mini-pong 独立 Godot 工程（独立 .godot 缓存）作用域隔离；仍用 `WolfConstants`/`StateMachineBase` 前缀防未来工具链歧义（PRD §5.2-1） |
| 10. 三入口任一失败 | 按 PRD §5.3 失败路径：run_tests 编译错误 → 修正脚本至全绿再提交；autoload 导致 smoke 失败 → 检查路径/extends Node，回退方案 B（暂不注册）并在 PR 说明 |

---

## 6. 集成点

> **Status 约定:** ⬜ = 待 implement 接线；✅ = implement 已连接。implement agent 必须更新本表。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| constants 消费 | WolfConstants | #573/#575/#577/#578 | `const C = preload("res://gdscripts/constants.gd")` | ⬜ pending |
| 状态机派生 | StateMachineBase | #575 | `class BattleStateMachine extends StateMachineBase` + 状态对象三接口 | ⬜ pending |
| autoload 挂接 | Game | #573 | 输入控制器注册到 Game（autoload 段 Game 之后追加） | ✅ done（#573 impl 已接线: [autoload] 追加 InputController） |
| 数值定稿 | WolfConstants # DRAFT 分区 | #584 | 候补值 → 用户定稿（替换值 + 去 # DRAFT 标记，走 #584 PR） | ⬜ pending |
| 单测挂载 | run_tests.gd | 本 issue | `_run("res://tests/test_state_machine.gd", ...)` + test_constants | ✅ done |

---

## 7. 实现阶段

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | `gdscripts/constants.gd`（5 分区 + 机械常量） | 0.5d |
| Phase 2 | P0 | `gdscripts/state_machine.gd`（基类三接口 + 守卫） | 0.5d |
| Phase 3 | P0 | `gdscripts/game.gd` + `project.godot` [autoload] 段 | 0.25d |
| Phase 4 | P0 | `tests/test_state_machine.gd` + `tests/test_constants.gd` + `run_tests.gd` 挂载 | 0.5d |
| Phase 5 | P0 | 三入口全绿实测（compile/smoke/run）+ Spike 1-3 验证（PRD §7） | 0.25d |

> 依赖序：Phase 1→2 无依赖可并行；Phase 3 依赖 1（Game preload constants）；Phase 4 依赖 2（单测实例化基类）；Phase 5 收尾。总估 2d（PRD estimate 1d 偏乐观，含 Spike 与三入口排障）。

---

## 8. 测试用例描述

> 仅描述测试场景，不写可运行测试代码（plan 阶段红线；实现由 implement agent 完成）。

### Scenario A: 状态机三接口调用序（test_state_machine.gd）
- **A1（正常转移序）**: 两个 mock 状态（记录调用日志）`transition_to(B)` → 断言日志序 == `[A.exit(), B.enter()]`（exit 先于 enter，PRD §7 实验 1 契约）。
- **A2（初始转移）**: 从 null 直接 `transition_to(A)` → 仅 `A.enter()`，无 exit 调用。
- **A3（update 转发）**: 设 current=A 后 `update(0.016)` → 断言 `A.update` 收到 delta=0.016。

### Scenario B: 同态守卫（test_state_machine.gd）
- **B1（同对象忽略）**: `transition_to(A)` 两次 → 第二次无任何回调（exit/enter 计数不变）。
- **B2（同态后 update 正常）**: 同态忽略后 `update(delta)` 仍转发给当前状态（守卫不破坏正常转发）。

### Scenario C: 防重入（test_state_machine.gd）
- **C1（嵌套转移拦截）**: mock A 的 `enter()` 内调用 `transition_to(B)` → 断言 B.enter 未被调用 + push_warning 已发（`_transition_locked` 生效）。
- **C2（锁释放）**: 转移完成后再次 `transition_to(B)` 正常执行（锁在转移末尾释放，非永久锁死）。

### Scenario D: 空状态安全（test_state_machine.gd）
- **D1（null update）**: 无 current_state 时 `update(0.016)` → no-op 不崩溃。
- **D2（null 目标）**: `transition_to(null)` → 仅 exit 当前状态，不进入新状态（无 enter 调用）。

### Scenario E: constants 分区存在性（test_constants.gd）
- **E1（5 分区齐全）**: `WolfConstants` 存在 `PARRY_WINDOW_*` / `POSTURE_*` / `LIFE_*` / `SWORD_*` / `FRAME_*` 常量（按 §2.1 命名断言），任一缺失 FAIL。
- **E2（候补值未定稿）**: 文件源码含 ≥5 处 `# DRAFT` 标记；不含「# 定稿」字样（防实现期顺手定稿，PRD §5.2-2）。
- **E3（机械常量）**: `GAME_VERSION == "v0.1.0"`、`SCREEN_WIDTH==1280`、`SCREEN_HEIGHT==720`（与 project.godot/Main.tscn 一致，AC1 联动）。

### Scenario F: 三入口回归（CI / 本地）
- **F1（check_compile）**: `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0，输出 count 覆盖新增 3 gdscripts + 2 tests 脚本。
- **F2（smoke）**: `... --script tests/smoke_test.gd` 退出 0，无 autoload 报错（Game 初始化成功，Spike 3）。
- **F3（run_tests）**: `... --script tests/run_tests.gd` 退出 0，输出「TESTS: N passed, 0 failed」且 N ≥ 状态机用例数（A-D 场景全过）；pass==0 → 退出非 0（防挂载遗漏静默绿）。
- **F4（主场景冒烟）**: `godot --path shandong-wolf/ --headless --quit` 退出 0（autoload + Main.tscn 启动链兼容，AC1/Spike 3）。

---

## 9. 验收条件映射（源自 Issue #572 body）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | scenes/Main.tscn 存在并可运行，窗口 1280x720 不可缩放 | 零改动（#562 已满足） | F4 + project.godot `[display]` 断言（1280/720/resizable=false） |
| AC2 | gdscripts/constants.gd 已创建，内含 # DRAFT 分区（弹反窗口/架势回复/两条命数值/刀伤害/帧节奏候补值） | §2.1 五个分区 + 候补值注释 | E1/E2（分区存在 + # DRAFT 标记） |
| AC3 | gdscripts/state_machine.gd 已创建，提供 enter/exit/update 三接口并含单元测试 | §2.2 基类 + 状态对象契约；§2.4 单测 | A-D 场景 + F3（run_tests 输出 pass 计数） |
| AC4 | tests 三入口（compile/smoke/run）全绿 | §3.1 run_tests 挂载 + 自动覆盖 | F1/F2/F3 三命令退出码全 0 |
| AC5 | 不得引入任何外部美术资产或 AI 生成像素动画帧 | §3.3 零资源文件（仅 .gd/.tscn/project.godot） | implement PR diff 核查：无 .png/.jpg 等新增 |

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `mini-pong/` 任何文件（跨游戏红线）
- ❌ `shandong-wolf/scenes/Main.tscn`（含 PostMergeProbeLabel、标题/副标题/版本标签）
- ❌ `game-env/manifest.yaml`、`.github/workflows/`、`scripts/`（管线参数化已自动跟随）
- ❌ `docs/GAME_DESIGN/`（post-merge agent 职责）
- ❌ `shandong-wolf/e2e_shots.json`（PRD 未要求）
- ❌ 任何美术资产 / 插件 addon / 像素帧（AC5）
- ✅ constants.gd 所有手感值保持 `# DRAFT` + 候补值，定稿归 #584

# PRD: [Canary] Mini Pong 标题画面显示版本号 v1.0.0

> **Issue:** #358
> **标签:** workflow/available, canary
> **Agent:** game-research-agent
> **日期:** 2026-08-10
> **深度:** depth/standard（Issue 无 depth 标签，按 standard 处理：Section 1–6 + 8）
> **金丝雀目的:** 验证 workflow 全链路（research → plan → implement → CI → review → merge）+ 新的本地 E2E 视觉验证（`scripts/run-e2e-review.sh`，commit `864d2df` / PR #357 引入）

---

## 1. 问题定义

### 当前状态

Mini Pong 的标题画面（StartMenu）已由 #292 建成：三层 CanvasLayer UI 架构，标题画面只有居中的 **TitleLabel**（"Mini Pong"，64px）和 **PromptLabel**（"按 SPACE 开始"，28px），**没有任何版本号显示**。仓库中也不存在任何版本号定义（`grep` 全仓无 `1.0.0`/`VERSION` 常量，`mini-pong/project.godot` 无 `config/version`）。

| 组件 | 状态 | 细节 |
|------|:----:|------|
| `mini-pong/gdscripts/start_menu.gd` | ✅ | 107 行 CanvasLayer 控制器；`@onready` 引用 `TitleLabel`/`PromptLabel`；脉冲/闪烁动画；headless 安全守卫 |
| `mini-pong/scenes/ui_start_menu.tscn` | ✅ | 独立场景：`CenterContainer/VBoxContainer/TitleLabel + PromptLabel` |
| `mini-pong/scenes/Main.tscn` | ✅ | **内联** StartMenu 节点树（`layer=1, visible=true`），**不实例化** `ui_start_menu.tscn` —— 两处节点树重复 |
| `mini-pong/gdscripts/constants.gd` | ✅ | `GameConstants`（class_name）—— 项目"单一事实来源"常量文件，无版本常量 |
| `mini-pong/project.godot` | ✅ | `config/name="Mini Pong"`，`config/features=PackedStringArray("4.7")`，**无 version 字段** |
| 版本号显示 | ❌ | 不存在 —— 本 Issue 的交付物 |
| `mini-pong/e2e_shots.json` | ❌ | 不存在 —— run-e2e-review.sh 会回退到 `framework/templates/e2e_shots.json`（见风险 R1） |

### 预期行为

1. **标题画面左下角渲染 `v1.0.0` 文本** —— StartMenu 可见时（MENU 状态）在屏幕左下角显示版本号
2. **不影响现有游戏循环** —— 对打 / 计分 / 暂停逻辑零改动
3. **现有测试全部通过，新增/更新测试覆盖版本号文本存在** —— 测试基线为 #346 修复后的全绿套件（run_tests.gd 聚合 14 个套件）
4. **E2E 视觉验证通过** —— review agent 用 `scripts/run-e2e-review.sh` 跑本地 E2E，标题画面截图（`01_title`，MENU 状态）应包含版本号

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家启动游戏 | 每次启动 | 标题画面左下角可见 `v1.0.0`，不遮挡中央标题/提示 |
| B | 开发者跑测试 | 每次提交/PR | `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿，新增版本号测试通过 |
| C | review agent 视觉验证 | 每次实现 PR | `run-e2e-review.sh <PR> --subproject mini-pong` 的 `01_title` 截图包含版本号像素 |

### 技术约束（继承自 Issue #358）

- **Godot 4.7.1**，目录 `mini-pong/`（有自己的 `project.godot`）
- **只改 `mini-pong/` 下的文件**，不碰根目录/其他子项目
- `start_menu.gd` 是标题画面脚本
- 视觉验证：review agent 会用 `run-e2e-review.sh` 跑本地 E2E，标题画面截图应包含版本号

---

## 2. 设计意图

### 为什么现在做

这是 **canary（金丝雀）Issue**：功能本身极小（一个版本号文本），真正的目的是**端到端验证 workflow 全链路**与**新的本地 E2E 视觉验证管线**（#357 于 `864d2df` 合入 `run-e2e-review.sh` + archetype shot plan）。因此 PRD 必须同时保证：(a) 功能正确实现；(b) 现有测试不回归；(c) 新 E2E 视觉层（L3）能在本 Issue 上真正跑通——这也是全链路第一次用上视觉验证。

### 为什么当前 UI 层长这样

#292 建立了三层 CanvasLayer 架构（StartMenu / GameHUD / GameOverScreen），`start_menu.gd` 通过 `@onready` 引用场景内节点、用 tween 做动画，并在 headless 下用 `is_inside_tree() and get_tree()` 守卫（#296 补的 Pause 层同理）。版本号显示应**沿用这套既有模式**，不引入新架构。

### 先前约束

| 约束 | 细节 |
|------|------|
| 目录边界 | 只改 `mini-pong/`（Issue 明示 + 项目 manifest 子项目结构） |
| 引擎版本 | Godot 4.7.1，`config/features=PackedStringArray("4.7")` |
| 测试基线 | #346 修复后全绿（此前 895 passed / 7 failed → 已修复，见 PR #353/#355/#356） |
| 视觉验证 | `run-e2e-review.sh`（#357）L0-L3 四层，截图必须非伪造（4 重 anti-fake 断言） |
| 渲染环境 | 1280×720 固定窗口，霓虹配色（玩家蓝 #4a90d9 / AI 红 #ff3355，见 #289） |

### 研究关键发现（Research Findings）

1. **双场景同步问题（最重要）**：`Main.tscn` **内联**了 StartMenu 节点树而非实例化 `ui_start_menu.tscn`。运行时实际显示的是 `Main.tscn` 的树（`run/main_scene="res://scenes/Main.tscn"`），而 `test_ui_system.gd` TC5 加载的是 `ui_start_menu.tscn`。**若只改其中一个场景，会出现"测试通过但实际画面/截图没有版本号"**。两处都必须有版本节点，或由 `start_menu.gd` 程序化创建（一处代码两处生效）。
2. **版本号来源缺失**：仓库无任何版本常量。需要引入 `v1.0.0` 的定义点（推荐 `GameConstants`，见方案对比）。
3. **E2E shot plan 路径不匹配（风险 R1）**：`mini-pong/` 没有自己的 `e2e_shots.json`，`run-e2e-review.sh` 回退到 `framework/templates/e2e_shots.json`；该模板 `state_node: "/root/Main/GameStateMachine"`，而 `Main.tscn` 根节点名为 **`Game`**（`[node name="Game" type="Node2D"]`），实际路径应为 `/root/Game/GameStateMachine`。模板路径解析会失败/拿不到状态。**需要新增 `mini-pong/e2e_shots.json`（在 mini-pong/ 内，不违反约束），state_node 指向 `/root/Game/GameStateMachine`，shot `01_title`（MENU 状态）必须捕获左下角版本号**。shot plan 的 `loop` group 匹配 `gdscripts/.*\.gd` 与 `scenes/.*\.tscn`，本 PR 改动必然命中，视觉层会被执行。
4. **FSM 状态确认**：`game_state_machine.gd` 为 6 状态机（MENU → SERVING → PLAYING ⇌ PAUSED → SCORED → GAME_OVER → MENU），`current_state` 属性存在，`State.MENU` 是初始状态 —— 与 shot plan 的 states 映射（`"MENU": 0`）一致。
5. **Obsidian 知识库不可用**：`OBSIDIAN_VAULT_PATH=/Volumes/Obsidian`（挂载根，vault 在 `Knowledge Ocean/` 下），本次执行时**未挂载**（`Operation canceled`）。知识库检索降级为仓库内 `docs/`（GAME_DESIGN / DESIGN / PRD），以上发现均来自仓库文档与源码实证。

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/start_menu.gd` | StartMenu 控制器 | 修改：新增版本号节点引用（`get_node_or_null` 兜底）或程序化创建；`_ready()` 设置版本文本（headless 安全） |
| `mini-pong/scenes/ui_start_menu.tscn` | StartMenu 场景 | 修改：新增 `VersionLabel` 节点（左下角锚定） |
| `mini-pong/scenes/Main.tscn` | 主场景 | 修改：StartMenu 内联树中新增同名 `VersionLabel` 节点（与 ui_start_menu.tscn 保持同步） |
| `mini-pong/gdscripts/constants.gd` | 全局常量 | 修改：新增 `GAME_VERSION: String = "v1.0.0"`（推荐方案） |
| `mini-pong/tests/test_ui_system.gd` | UI 测试 | 修改：新增 TC（版本号节点存在 + 文本正确） |
| `mini-pong/tests/test_main_scene.gd` | 主场景测试 | 修改（可选）：断言 Main.tscn 的 StartMenu 下也有版本节点 |
| `mini-pong/e2e_shots.json` | E2E shot plan | **新增**：mini-pong 专属 shot plan（修正 state_node 路径 + 01_title 捕获） |

### 新增文件

| 文件 | 用途 |
|------|------|
| `mini-pong/e2e_shots.json` | 本地 E2E 视觉验证的 shot plan（修正 `/root/Game/GameStateMachine`，`01_title` MENU 状态） |

### 间接影响

| 模块 | 影响 |
|------|------|
| `test_constants.gd` | 若在 `GameConstants` 加常量，需确认无"常量全集"断言被破坏（追加式修改，预期无影响） |
| FSM / Pause / 计分 | **零影响** —— 版本号是纯展示层，不接任何信号，不参与输入路由（AC2 的保障手段） |

### 数据流

```
GameConstants.GAME_VERSION ("v1.0.0")
    │  (start_menu.gd _ready())
    ▼
StartMenu/VersionLabel.text
    │
    ├──► 渲染到 1280×720 左下角（MENU 状态可见）
    └──► e2e_capture.gd 截图 01_title ──► analyze_bmp.py 断言（像素/主题色）
```

### 文档更新清单

- [x] 本 PRD（`docs/PRD/358-title-screen-version.md`）
- [ ] `docs/GAME_DESIGN/16-UI-SYSTEM.md` —— 实现合并后补充 VersionLabel 到 StartMenu 小节（由 plan/implement 阶段处理，本阶段不改）

---

## 4. 方案对比

### 方案 A：场景声明式节点 + GameConstants 常量（推荐）

在两个场景的 StartMenu 树中各加一个 `VersionLabel`（`Label`，左下角锚定，字号 16–20，霓虹蓝低透明度），`start_menu.gd` 用 `@onready var version_label: Label = get_node_or_null("...")` 引用并在 `_ready()` 中 `version_label.text = GameConstants.GAME_VERSION`；`constants.gd` 新增 `const GAME_VERSION: String = "v1.0.0"`。

- **Pros**：与 #292 既有声明式场景风格完全一致；测试可直接加载场景断言节点与文本；版本号单一事实来源（常量）；E2E 截图确定性最高
- **Cons**：两处场景需同步维护（Main.tscn 内联树 + ui_start_menu.tscn）；`get_node_or_null` 需兜底
- **Risk**：Low（纯追加节点，无逻辑改动）
- **Effort**：0.5–1 天

### 方案 B：start_menu.gd 程序化创建

`_ready()` 中 `add_child()` 动态创建左下角 Label 并设置文本，不改任何 .tscn。

- **Pros**：单点改动，两处场景同时生效；无需同步 .tscn
- **Cons**：与项目声明式风格相悖；布局参数埋在代码里；headless 下需额外守卫；测试需先触发 `_ready()` 再查动态节点，断言更绕
- **Risk**：Med（风格不一致，测试脆弱）
- **Effort**：0.5–1 天

### 方案 C：project.godot `config/version` + ProjectSettings

在 `mini-pong/project.godot` 加 `config/version="1.0.0"`，`start_menu.gd` 用 `ProjectSettings.get_setting("application/config/version")` 读取。

- **Pros**：版本号与导出配置同源；语义"官方"
- **Cons**：key 不存在时 `get_setting` 会报错需先注册；仍需要一个 Label 节点承载展示；对 canary 属过度设计；测试需 mock ProjectSettings
- **Risk**：Med（配置读取 + 测试复杂性）
- **Effort**：1 天

### 推荐

**方案 A**。理由：
1. 与 #292 UI 架构和现有测试模式（TC5 加载场景断言节点）完全对齐，测试覆盖最直接
2. `GameConstants` 本就是项目"单一事实来源"（constants.gd 头注释），版本号放这里符合既有约定
3. 对 E2E 视觉层最友好：场景静态节点在 MENU 状态必然渲染，`01_title` 截图稳定包含版本号
4. 双场景同步是唯一额外成本，但通过测试（TC5 + test_main_scene）可强制两者一致，正好覆盖 AC3

---

## 5. 边界条件与验收标准

### 正常路径（AC 清单）

- [x] **AC1：标题画面左下角渲染 `v1.0.0` 文本**
  - `ui_start_menu.tscn` 与 `Main.tscn` 的 StartMenu 树中均存在 `VersionLabel` 节点
  - 节点锚定左下角（anchors_preset 左下），文本为 `v1.0.0`（或 `GameConstants.GAME_VERSION`）
  - StartMenu `visible=true` 时（MENU 状态）可见，不遮挡 TitleLabel/PromptLabel
- [x] **AC2：不影响现有游戏循环（对打/计分/暂停）**
  - 不修改 `ball.gd` / `paddle.gd` / `scoring_manager.gd` / `game_state_machine.gd` / `game_manager.gd` / `audio_engine.gd` 等游戏逻辑
  - 版本节点不连接任何信号、不响应输入
- [x] **AC3：现有测试全部通过，新增/更新测试覆盖版本号文本存在**
  - `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（14 套件）
  - `test_ui_system.gd` 新增 TC：加载 `ui_start_menu.tscn`，断言 `VersionLabel` 存在且 `text == "v1.0.0"`
  - `test_main_scene.gd` 新增/更新断言：Main.tscn 的 StartMenu 下 `VersionLabel` 存在
- [x] **AC4：E2E 视觉验证——标题画面截图应包含版本号**
  - `scripts/run-e2e-review.sh <PR> --subproject mini-pong` 的 L3 视觉层通过
  - `01_title`（MENU 状态）截图包含版本号像素（左下角区域非背景色）

### 边界情况

1. **Headless 环境**：`_ready()` 中设置版本文本需沿用 `is_inside_tree() and get_tree()` 守卫，`get_node_or_null` 为 null 时静默跳过（不崩溃）
2. **两场景不同步**：只改 `ui_start_menu.tscn` 漏改 `Main.tscn` → 实际运行画面无版本号。由测试（TC5 + test_main_scene）双保险拦截
3. **左下角与 PromptLabel 视觉冲突**：PromptLabel 居中（VBoxContainer），VersionLabel 左下角（独立锚定），无重叠；字号 ≤20 时不影响
4. **版本号来源变更**：`GameConstants.GAME_VERSION` 是唯一修改点；场景文本由 `_ready()` 覆盖，避免 .tscn 硬编码与常量漂移
5. **字体缺失**：Godot 回退 system_font，版本号仍可渲染（#292 已有约定）
6. **E2E 截图时机**：`01_title` settle_frames=10，StartMenu 初始 `visible=true`，MENU 状态截图稳定包含版本号
7. **窗口分辨率**：1280×720 固定（`resizable=false`），左下角锚定在任意该分辨率下位置确定

### 失败路径

1. **E2E state_node 解析失败（R1）**：若实现 PR 不带 `mini-pong/e2e_shots.json`，回退模板的 `/root/Main/GameStateMachine` 路径在 mini-pong 中不存在 → L3 视觉层无法按状态截图。**缓解：实现 PR 必须新增 `mini-pong/e2e_shots.json`**（state_node=`/root/Game/GameStateMachine`）
2. **测试通过但画面无版本号**：仅改了 `ui_start_menu.tscn`（TC5 通过），Main.tscn 内联树未同步 → 实际游戏/截图无版本号。**缓解：test_main_scene 断言 + L3 截图双重验证**
3. **`_ready()` 崩溃风险**：若用非兜底 `@onready` 且某场景缺节点，headless 下 `_ready()` 抛错。**缓解：`get_node_or_null` + 守卫**

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #292 UI 系统（StartMenu 三层架构） | CLOSED ✅ | — |
| #295 主场景组装（Main.tscn 内联 StartMenu） | CLOSED ✅ | 双场景同步是核心风险点 |
| #346 测试修复（全绿基线） | CLOSED ✅（PR #353/#355/#356） | — |
| #357 E2E runner（`run-e2e-review.sh`） | MERGED ✅（`864d2df`） | 模板 state_node 路径与 mini-pong 不匹配（R1） |
| Godot 4.7.1 二进制 | 环境提供 | `RUNNER_GODOT` 可覆盖 |
| `mini-pong/e2e_shots.json` | ❌ 待创建 | 本 Issue 实现阶段新增（在 mini-pong/ 内，不违反约束） |

### 阻塞

无阻塞。本 Issue 不依赖其他开放 Issue。

### 依赖链

```
#292 UI ──► #295 组装 ──► #346 测试修复 ──► #357 E2E runner ──► 本 Issue (#358 canary 全链路验证)
```

### 准备清单

- [ ] 确认 `godot` 4.7.1 可用（`run-e2e-review.sh` P0 检查）
- [ ] 实现阶段先建 `mini-pong/e2e_shots.json`（修正 state_node）再跑 L3
- [ ] 基线记录：实现前 `run_tests.gd` 全绿计数（供回归对比）

---

## 7. Spike / 实验

**Skipped per depth/standard label**（Issue #358 无 `depth/deep` 标签）。说明：本 Issue 为 canary 验证，功能面积极小（追加一个静态 Label），无未验证的技术风险点需要 spike；唯一环境性风险（E2E state_node 路径）已在 §2/§5 以确定性方式给出修复路径（新增 `mini-pong/e2e_shots.json`），不需要实验验证。

---

## 8. 延续上下文

### 系统状态

- 三层 CanvasLayer UI（#292）就绪；StartMenu 在 `Main.tscn` **内联** + `ui_start_menu.tscn` 独立场景 **两处存在**，`start_menu.gd` 共用
- `GameConstants`（constants.gd）为常量单一事实来源；尚无版本常量
- 测试套件 14 个套件全绿（#346 修复后）；E2E runner（#357）已可用但 mini-pong 无专属 shot plan
- FSM：6 状态机，初始 MENU，`current_state` 属性存在，状态枚举值与模板 shot plan 映射一致

### 主要风险（plan agent 必须继承）

| # | 风险 | 缓解 |
|---|------|------|
| R1 | E2E 回退模板 `state_node="/root/Main/GameStateMachine"` 与实际场景根 `Game` 不匹配 | 实现 PR 新增 `mini-pong/e2e_shots.json`（state_node=`/root/Game/GameStateMachine`） |
| R2 | Main.tscn 内联树与 ui_start_menu.tscn 双场景不同步 | 两处都加 `VersionLabel`；测试双保险（TC5 + test_main_scene） |
| R3 | 版本号来源漂移 | `GameConstants.GAME_VERSION` 唯一来源，`_ready()` 统一赋值 |

### 下一步（plan agent 交接）

1. 依据本 PRD §4 方案 A 产出 `docs/DESIGN/358-*.md`：VersionLabel 节点规格（左下锚定、字号、颜色）、`GameConstants.GAME_VERSION`、两场景同步要求、`mini-pong/e2e_shots.json` 内容
2. 测试规格：`test_ui_system.gd` 新增 TC（场景加载 → VersionLabel 存在 → text=="v1.0.0"）；`test_main_scene.gd` 断言 Main.tscn 内联树节点
3. 约束重申：**Godot 4.7.1，只改 `mini-pong/` 下文件**；不改游戏逻辑（AC2）
4. 实现后由 review agent 跑 `scripts/run-e2e-review.sh <PR> --subproject mini-pong`，确认 L0–L3 全过、`01_title` 截图含版本号
5. 合并后需验证 workflow-chain 自动推进 issue 标签（research → plan），canary 全链路闭环

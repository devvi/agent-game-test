# PRD: [Bug] title 没有显示双人模式入口

> Issue: #551（label: `bug` + `workflow/available`，工作深度 **light**，优先级 medium）
> 引擎: Godot 4.7.1（`mini-pong/` 子项目，`run/main_scene = res://scenes/Main.tscn`，竖屏 720×1280）
> 关联: 依赖 #543（本地双人对战，PR #549 已于 2026-08-17 合并）

## 1. 问题定义

### 1.1 当前状态

打开游戏（主场景 `Main.tscn`）后，title 界面只显示标题「PONG://21」与「按 SPACE 开始」，**看不到「本地双人对战」入口**。Issue #543 要求 title 支持游戏模式选择（#543 PRD AC1），PR #549 已实现完整双人玩法机制，但**入口 UI 没有出现在运行时主场景中**。

**Bug 前置侦查（Patch 10 流程）——已修复 / 仍损坏 / 过时声明：**

| 项目 | 结论 | 证据 |
|------|------|------|
| 双人玩法机制（GameManager.GameMode、双板配置、分键、双计分通道、双人升级） | ✅ **Already fixed**（#549 已实现） | `game_manager.gd:21` `enum GameMode { SINGLE=0, LOCAL_2P=1 }`；`apply_mode_to_paddles()`（FSM SERVING 入口调用，`game_state_machine.gd:119`）；`paddle.gd:68` `rebind_for_mode()`；`paddle.gd:161` P2 改绑 `p2_left/p2_right` |
| 模式选择 UI 逻辑（↑/↓ 切换、高亮、透传 GameManager） | ✅ **Already fixed**（#549 已实现） | `start_menu.gd:25-27` `_mode_index`/`_mode_labels`；`_unhandled_input()` ↑/↓ → `GameManager.set_game_mode()`；`_apply_mode_highlight()` |
| **title 界面双人模式入口（可见性）** | ❌ **Still broken（本 Bug）** | 运行时主场景 `Main.tscn` 的 `StartMenu` 内联子树**缺少** `ModeSelectVBox`/`ModeOption1`/`ModeOption2` 三个节点（`grep ModeSelect Main.tscn` 无命中） |
| Issue 声称的「title 未显示双人模式入口」 | ✅ **与现状一致（非过时声明）** | 与源码核查结果吻合，缺陷真实存在 |

**根因分析（场景双份漂移）：**

- `project.godot:15` 的 `run/main_scene = res://scenes/Main.tscn` — **运行时 title 屏是 Main.tscn 内联的 StartMenu 子树**（`Main.tscn:148`，CanvasLayer + script），不是独立的 `ui_start_menu.tscn`。
- PR #549 按 DESIGN #543 §3.1 只把 `ModeSelectVBox`（含 ModeOption1/2）插进了 **`ui_start_menu.tscn`**（独立基准场景，非运行时场景），**Main.tscn 的内联 StartMenu 子树未同步**。
- `start_menu.gd:_ready()` 用 `get_node_or_null()` 收集模式选项（`start_menu.gd:47-52`），**节点缺失时静默跳过**（headless 容错设计）→ `_mode_labels` 恒为空 → 高亮无对象、title 屏不显示任何模式选项，游戏照常运行不报错。
- 由于「静默降级」，玩家实际上**可以盲按 ↑/↓ + SPACE 进入双人模式**（`_unhandled_input` 不依赖节点存在），但界面零提示 — 与 Issue 描述的「找不到双人模式入口」完全一致。

**测试缺口（为何 CI 全绿放行）：**

| 测试 | 断言内容 | 缺口 |
|------|---------|------|
| `tests/test_main_scene.gd` TC19 | 仅同步校验 `StartMenu/VersionLabel`（font_size/modulate/anchors 对齐 `ui_start_menu.tscn`） | ❌ 未断言 `ModeSelectVBox`/`ModeOption1/2` 存在性 |
| `tests/test_local_2p.gd` A3/H1 | `get_selected_mode()` 初始值 == 0；脚本/场景可加载 | ❌ 在 mini-tree 上测，未实例化真实 `Main.tscn` 校验模式区 |
| `mini-pong/e2e_shots.json` `01_title` | 仅断言 `StartMenu/VersionLabel` 文本 `v1.0.0` + `theme_absent: 4a90d9` | ❌ 未断言模式选项文本 |

**受影响系统表：**

| 系统 | 文件 | 当前状态 | 与 #551 的差距 |
|------|------|---------|---------------|
| 运行时 Title 屏 | `scenes/Main.tscn`（StartMenu 内联子树） | 仅 TitleLabel/PromptLabel/VersionLabel，无模式区 | ❌ 缺 `ModeSelectVBox` + 2 个 ModeOption Label |
| 基准 Title 场景 | `scenes/ui_start_menu.tscn` | ✅ 含完整 ModeSelectVBox（#549 已加） | —（同步基准，保持不动） |
| Title 屏逻辑 | `gdscripts/start_menu.gd` | 模式切换/高亮/透传逻辑完整，`get_node_or_null` 静默容错 | ⚠️ 节点补齐后自动生效，**零改动** |
| 2P 玩法机制 | `game_manager.gd` / `paddle.gd` / FSM | ✅ 完整（#549） | — |

### 1.2 Obsidian 知识库搜索结果（issue 未勾选「搜索 Obsidian」；按项目惯例自动搜索）

| 检索范围 | 命中文档 | 结论 |
|---------|---------|------|
| `/Volumes/Obsidian/Knowledge Ocean/wiki/` 文件名 grep `双人\|多人\|对战\|模式\|菜单\|title\|标题\|pong\|PvP\|联机` | 无命中 | wiki 无本项目模式选择/标题屏设计笔记 |
| 同上 wiki/ 内容 grep `双人` | 无命中 | 同上 |
| `/Volumes/Obsidian/Knowledge Ocean/outputs/` + `raw/`（Bear/Feishu/Clippings）内容检索 | ⚠️ **未完成** — 检索过程中 WebDAV 挂载中断（NAS `guaguastation.mycloudnas.com:1995` 不可达：curl PROPFIND HTTP 000，重挂载报 -5014） | 无法检索；与 #543 的 Obsidian 结论（无本项目双人/模式选择笔记）方向一致 |

**结论：** Obsidian wiki 无本项目双人模式/标题屏设计笔记，知识搜索无新增约束。mini-pong 的设计知识以仓库内 PRD/DESIGN/GDD 为准（#292 title、#294 FSM、#543/#549 双人模式、#295/#393 单场景常驻架构、#508 MENU 世界隐藏）。若 NAS 恢复，可补跑 outputs/raw 检索确认（不影响本 PRD 结论 — 缺陷为纯场景同步问题，与设计笔记无关）。

### 1.3 预期行为（验收条件，源自 Issue #551）

1. [ ] **AC1 — title 界面显示双人模式入口** — 打开游戏（`Main.tscn` 运行时场景），title 界面可见「单人模式（AI 对战）」与「本地双人对战」两个模式选项（与 `ui_start_menu.tscn` 一致）。
2. [ ] **AC2 — 默认单人 + SPACE 直开，单人路径零行为差异** — 默认选中「单人模式（AI 对战）」；SPACE 以当前选择开始；单人模式与现状逐字节一致（#508 世界隐藏、FSM 开始流不变）。
3. [ ] **AC3 — ↑/↓ 切换 + 高亮反馈** — ↑/↓ 在两个模式间循环切换，选中行 `PADDLE_NEON` 高亮 + 字号 24，未选中 0.4 透明度 + 字号 20（`start_menu.gd:_apply_mode_highlight()` 既有实现）。
4. [ ] **AC4 — 选择双人后开局为双人** — 选中「本地双人对战」→ SPACE → `GameManager.game_mode == LOCAL_2P` → 双板 + P2 分键生效（`apply_mode_to_paddles()`）。
5. [ ] **AC5 — 场景同步有测试锁定** — 新增/扩展测试断言 `Main.tscn` 的 ModeSelect 区与 `ui_start_menu.tscn` 一致，防止再次漂移。

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 单人玩家快速开局 | 高频 | 打开游戏 → 默认单人高亮 → SPACE 直接开始（与现状零差异） |
| B | 双人玩家选择本地对战 | 中频 | 打开游戏 → title 看到「本地双人对战」→ ↓ 切换 → SPACE 开始双人 |
| C | 对局结束重开 | 中频 | GAME_OVER → SPACE → MENU，保留上次选择（`show_menu()` 重绘高亮，`reset_match()` 不触碰 `game_mode`） |

### 1.5 技术约束（继承 Issue #551 + 既有架构）

| 约束 | 详情 |
|------|------|
| 引擎/目录 | Godot 4.7.1，`mini-pong/` 子项目；`project.godot` `run/main_scene = res://scenes/Main.tscn` |
| 单场景常驻架构 | #295/#393：所有 UI 挂在 Main.tscn 一个场景内，无场景切换 |
| 模式选择入口位置 | DESIGN #543 §3.1：`CenterContainer/VBoxContainer` 中 TitleLabel 与 PromptLabel 之间 |
| headless 容错 | `start_menu.gd` 全部节点引用走 `get_node_or_null`，缺失不得崩溃（测试/CI headless） |
| 主题色纪律 | 高亮色 `PADDLE_NEON`（#4a90d9）— E2E `01_title` `theme_absent: 4a90d9` 保护 |
| #508 纪律 | MENU 态隐藏 `game_world`；模式区挂在 StartMenu（layer=1）内，开局随 StartMenu 隐藏，无需新机制 |

## 2. 设计意图

### 2.1 现状成因

- DESIGN #543 的文件清单只写了 `ui_start_menu.tscn`（§3.1、文件表第 246 行），未提及 `Main.tscn` 内联 StartMenu 子树 — 因为 #543 立项时以「Title 屏 = ui_start_menu.tscn」为心智模型（#543 PRD 1.1 现状表）。
- 但运行时实际渲染的是 **Main.tscn 内联副本**（#295 单场景常驻架构的产物），两个场景的 StartMenu 互为「双份」。
- R2 同步纪律只以 TC19 锁了 `VersionLabel` 一个节点（#358 的版本号同步），未覆盖整个子树 → #549 加了 ModeSelect 区后，Main.tscn 漂移未被任何测试捕获。
- `get_node_or_null()` 的静默降级是刻意的 headless 容错，副作用是**吞掉了节点缺失错误**，让漂移在运行时无感、无日志。

### 2.2 为何现在做

- #549 已交付**完整且正确**的双人玩法机制（GameMode/双板/分键/双计分/双人升级），唯一缺口是入口可见性 — 玩家无法从 UI 上发现并选择双人模式，功能形同虚设。
- Issue #551 明确要求 title 显示双人模式入口；工作深度 light（简单修复，快速完成）。
- 修复面 = Bug 面：纯场景节点补齐 + 测试锁定，不触碰任何玩法逻辑（机制层零改动）。

### 2.3 既有约束（必须继承）

| 约束 | 详情 | 来源 |
|------|------|------|
| 模式枚举对齐 | `_mode_index` 0=SINGLE / 1=LOCAL_2P 与 `GameManager.GameMode` 同值 | #543 |
| 高亮样式 | 选中 `PADDLE_NEON` + 字号 24；未选中 alpha 0.4 + 字号 20 | #543（start_menu.gd 既有） |
| 布局 | 模式区位于 TitleLabel 与 PromptLabel 之间，VBox separation=8，选项字号 22，水平居中 | #543 DESIGN §3.1 |
| 默认值 | `_mode_index` 初始 0（SINGLE），`GameManager.game_mode` 初始 SINGLE，`reset_match()` 不重置 | #543 / #549 |

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/scenes/Main.tscn` | StartMenu/CenterContainer/VBoxContainer | 插入 `ModeSelectVBox`（VBoxContainer, separation=8）+ `ModeOption1`（「单人模式（AI 对战）」）+ `ModeOption2`（「本地双人对战」）三个节点，逐字段对齐 `ui_start_menu.tscn`（font_size 22、horizontal_alignment 1） |
| `mini-pong/tests/test_main_scene.gd` | TC19（或新增 TC） | 扩展断言：`StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption1|2` 存在于 Main.tscn，文本与 `ui_start_menu.tscn` 一致 |
| `mini-pong/e2e_shots.json` | `01_title` shot | （可选，推荐）`assert_text` 增加 `StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption2` 文本含「本地双人对战」 |

### 3.2 新文件

无（纯场景节点补齐 + 既有测试文件扩展）。

### 3.3 间接影响

| 文件 | 影响 |
|------|------|
| `gdscripts/start_menu.gd` | **零改动** — 节点补齐后 `_mode_labels` 自动非空，高亮/切换/透传立即生效 |
| `scenes/ui_start_menu.tscn` | 保持为同步基准（不动） |
| E2E `01_title` 截图 | 截图画面将首次出现模式选项文本 — 视觉断言需同步（见 3.1） |

### 3.4 数据流影响

```
Main.tscn StartMenu 子树（节点补齐后）
    │  get_node_or_null(".../ModeSelectVBox/ModeOption1|2")
    ▼
start_menu.gd _mode_labels[2]
    │  _unhandled_input (↑/↓, MENU 态 visible)
    ├──► _mode_index = posmod(_mode_index ± 1, 2)
    │       └──► GameManager.set_game_mode(_mode_index)      ← 既有链路，不变
    └──► _apply_mode_highlight()（选中行 PADDLE_NEON+24 / 未选中 alpha0.4+20）
    │
    ▼
FSM MENU ui_accept → SERVING
    └──► GameManager.reset_match() → apply_mode_to_paddles()  ← 既有链路，不变
            └──► paddle mode/player_index/InputMap 重建（LOCAL_2P 双板分键）
```

**要点：** 本修复只补「节点存在性」这一环（图中第一行），其下游全部是 #549 已验证的既有链路。

### 3.5 文档更新清单

- [x] 本 PRD（`docs/PRD/551-title-local-2p-entry.md`）
- [ ] `docs/GAME_DESIGN/` — 模式选择已在 #543 沉淀，本 Bug 不引入新设计概念，无需追加（plan agent 复核）
- [ ] `docs/DESIGN/551-*.md` — 由 plan agent 基于本 PRD 产出

## 4. 方案对比

### 4.1 方案 A：Main.tscn 镜像 ModeSelectVBox 子树（推荐）

从 `ui_start_menu.tscn` 逐字段复制 ModeSelectVBox/ModeOption1/ModeOption2 三个节点到 Main.tscn 的 `StartMenu/CenterContainer/VBoxContainer`（TitleLabel 与 PromptLabel 之间），并新增测试断言两者一致。

- Pros：改动面最小（1 个 tscn + 1 个测试文件扩展）；与 #543 方案 A（StartMenu 内嵌选项区）完全一致；`start_menu.gd` 零改动，headless 容错天然兼容；修复面 = Bug 面。
- Cons：Main.tscn 与 ui_start_menu.tscn 仍是「双份」，未来还有漂移可能 — 由扩展后的 TC19 全节点断言锁定。
- Risk：**Low** — 纯声明式节点添加，无逻辑变更；测试锁定防回归。
- Effort：**<0.5 人日**

### 4.2 方案 B：Main.tscn 的 StartMenu 改为实例化 ui_start_menu.tscn

删除 Main.tscn 内联 StartMenu 子树，改为 `[node name="StartMenu" parent="." instance=ExtResource(...)]` 指向 `ui_start_menu.tscn`。

- Pros：根治双份漂移（单一事实源）；未来 UI 改动只需改一处。
- Cons：改动面超出 Bug 面 — 需验证 FSM `../StartMenu` NodePath（实例化后节点名仍为 StartMenu，可行但需实测）；`playthrough_driver.gd`/`e2e_playthrough.gd` 的 Main.tscn 几何镜像、TC19 断言路径、`ui_start_menu.tscn` 的 layer/visible 属性覆盖均需逐一核对；违反「light 简单修复」深度定位。
- Risk：**Med** — 结构重构类改动，需回归整条 E2E 链路。
- Effort：**1–2 人日**

### 4.3 方案 C：start_menu.gd 程序化创建模式选项

`_ready()` 中检测 ModeSelectVBox 缺失时用代码创建 ModeOption Label。

- Pros：不依赖场景文件，任何场景形态下都能显示。
- Cons：与 DESIGN #543 §3.1「场景内声明」的设计决策背道而驰；样式/布局逻辑从 tscn 分散进代码；测试断言困难（需等 _ready 后查动态节点）；掩盖了「场景未同步」这一真实问题。
- Risk：**Med** — 引入与架构相悖的双轨做法。
- Effort：**1 人日**

### 4.4 推荐

**方案 A。** 理由：(1) 缺陷本质是「运行时场景缺节点」，方案 A 直接补节点，修复面与 Bug 面重合；(2) #543 的既有实现（start_menu.gd 逻辑 + ui_start_menu.tscn 基准）零改动、零回归风险；(3) 测试锁定（TC19 扩展 + E2E assert_text 可选）防止漂移复发；(4) 符合 light 深度定位。方案 B 是结构性改进，可另立 Issue 跟进（根治双份场景），不作为本 Bug 的修复手段。

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1: title 显示双人模式入口**
  - `Main.tscn` 实例化后 `StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption2` 存在且文本为「本地双人对战」
  - `ModeOption1` 文本为「单人模式（AI 对战）」；两选项位于 TitleLabel 与 PromptLabel 之间
- [x] **AC2: 默认单人 + 单人零回归**
  - 初始 `_mode_index == 0`、`GameManager.game_mode == SINGLE`
  - SPACE 直开 → SERVING → `reset_match()` + `apply_mode_to_paddles()`（SINGLE 路径逐字节回归）
  - MENU 态世界隐藏（#508）不变
- [x] **AC3: ↑/↓ 切换 + 高亮**
  - ↓ 一次 → `_mode_index == 1` → ModeOption2 高亮（PADDLE_NEON + 字号 24）、ModeOption1 置灰（alpha 0.4 + 字号 20）；↑ 反向；循环切换（posmod）
- [x] **AC4: 双人开局生效**
  - 选中 LOCAL_2P → SPACE → `GameManager.game_mode == LOCAL_2P` → 双板 PLAYER 模式、P2 绑 `p2_left/p2_right`、P2 计分通道为 ai_score（`paddle.gd:229`）
- [x] **AC5: 场景同步测试锁定**
  - 测试断言 Main.tscn 模式区三节点存在且文本/字号与 `ui_start_menu.tscn` 一致

### 5.2 边界情况

1. **headless / mini-tree 测试**：`start_menu.gd` 在无 StartMenu 子树的测试环境中 `get_node_or_null` 返回 null → 静默跳过，不得崩溃（既有容错，回归验证）。
2. **ui_start_menu.tscn 未加载/不存在**：TC19 的基准比对分支已有 `if packed:` 守卫，缺失时跳过比对不失败。
3. **GameManager 未就绪**：`is_instance_valid(GameManager) and has_method("set_game_mode")` 守卫（start_menu.gd:91）— 切换时安全。
4. **部分节点缺失（如 opt1 有 opt2 无）**：`_mode_labels` append-only 非 null 收集（start_menu.gd:50-52）→ 高亮只作用于存在的行；正常路径下三节点必须齐全（测试保证）。
5. **竖屏布局**：模式区在 VBox 中 Title/Prompt 之间，两行 Label 字号 22 不溢出 720×1280（与 ui_start_menu.tscn 同布局，基准已成立）。
6. **重开保留上次选择**：GAME_OVER → MENU → SPACE 后 `game_mode` 不被 `reset_match()` 重置（game_manager.gd:26 注释）→ 上次双人选择保留（#543 设计意图）。
7. **E2E theme_absent 保护**：高亮色 PADDLE_NEON = #4a90d9 与 `01_title` 的 `theme_absent: 4a90d9` 同色 — 模式区出现后 title 截图不得新增主题色（保持单色系，无冲突）。

### 5.3 失败路径

1. **节点路径拼写错误 → 静默降级**：`get_node_or_null` 不报错，缺陷复现且无日志。对策：AC5 测试必须显式断言三节点存在（fail-fast），不能依赖运行时。
2. **双份场景再次漂移**：未来 #543 之后的新 UI 改动只改 ui_start_menu.tscn 而漏 Main.tscn。对策：TC19 扩展为「全子树同步断言」（至少覆盖 ModeSelect 区 + VersionLabel），E2E 01_title assert_text 兜底。
3. **E2E 断言过严导致误报**：若 `01_title` 增加文本断言后截图时机（settle_frames=10）内模式区未渲染完成 → 断言失败。对策：保持 `settle_frames` 或断言节点属性而非像素文本（与现有 VersionLabel 断言同模式）。

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|------|------|
| #543（本地双人对战） | ✅ 已实现（PR #549 merged 2026-08-17） | 无 — 本 PRD 只补入口可见性，机制层零改动 |
| DESIGN #543（ModeSelect 区设计） | ✅ 已存在 | 无 — 节点字段按 §3.1 逐字段复制 |

```
#543 (feature) → PR #549 (impl, merged) → #551 (本 Bug: 入口可见性) → plan → implement
```

阻塞：无。被阻塞：无。

## 7. Spike / 实验

Skipped per `depth/light`（Issue #551 工作深度: light，简单修复，无需实验验证方案可行性 — 方案 A 为纯声明式节点添加，无未知技术风险）。

## 8. 延续上下文（plan agent 交接）

**系统状态：** origin/main 头 = `24fce34`（feat(544) #550）。双人模式机制完整（#549），唯一缺口是 Main.tscn 内联 StartMenu 子树的 ModeSelect 区节点。

**本 PRD 的落地范围（plan agent 应产出 DESIGN 覆盖）：**

1. `mini-pong/scenes/Main.tscn` — 在 `StartMenu/CenterContainer/VBoxContainer` 的 TitleLabel（`PONG://21`）与 PromptLabel（`按 SPACE 开始`）之间插入：
   - `ModeSelectVBox`（VBoxContainer，`theme_override_constants/separation = 8`）
   - `ModeOption1`（Label，text「单人模式（AI 对战）」，`horizontal_alignment = 1`，`theme_override_font_sizes/font_size = 22`）
   - `ModeOption2`（Label，text「本地双人对战」，同属性）
   - **逐字段基准：`scenes/ui_start_menu.tscn:26-38`**（唯一事实源）
2. `mini-pong/tests/test_main_scene.gd` — 扩展 TC19 或新增 TC：断言 Main.tscn 三节点存在、文本一致、位置在 Title/Prompt 之间；比对 `ui_start_menu.tscn` 对应节点属性（字号/对齐）。
3. `mini-pong/e2e_shots.json` — `01_title` 的 `assert_text` 增加 `ModeOption2` 文本「本地双人对战」断言（可选但推荐，防回归）。
4. **不要动** `start_menu.gd`、`game_state_machine.gd`、`game_manager.gd`、`paddle.gd`、`ui_start_menu.tscn` — 机制层全部就绪。

**主要风险：** 双份场景漂移（TC19 全节点断言锁定）；`get_node_or_null` 静默容错掩盖缺失（测试 fail-fast 对抗）；E2E 截图时机（保持现有 settle_frames 模式）。

**验收锚点（implement 后验证）：** `tests/run_tests.gd` 全绿（含扩展 TC19 + test_local_2p 既有 A3/H1）；headless 启动 `Main.tscn` 无错误输出；E2E `01_title` 截图可见「本地双人对战」文本。

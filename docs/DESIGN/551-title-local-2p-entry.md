# Design: [Bug] title 界面显示双人模式入口（Main.tscn 模式区节点补齐）

> **Parent Issue:** #551
> **Agent:** game-plan-agent
> **Date:** 2026-08-18
> **Approach:** 方案 A（PRD §4.1 推荐方案——Main.tscn 镜像 ModeSelectVBox 子树），确认采纳；方案 B（实例化 ui_start_menu.tscn 根治双份）显式延后，另立 Issue 跟进
> **Reference PRD:** docs/PRD/551-title-local-2p-entry.md（research PR #552 已合并 2026-08-18）
> **深度:** light（Issue body「工作深度: light（简单修复，快速完成）」）——只产出 DESIGN 文档，不产出 TASKS 文档；测试仅描述不写代码（plan 阶段红线）
> **依赖:** #543（本地双人对战，PR #549 已合并 2026-08-17）——机制层全部就绪，本设计只补入口可见性

---

## 1. 架构总览

**问题本质是「运行时场景缺节点」而非逻辑缺陷。** #543/#549 已交付完整且正确的双人玩法机制（GameMode 枚举、双板配置、P2 分键、双计分、双人升级）与模式选择 UI 逻辑（`start_menu.gd` 的 ↑/↓ 切换/高亮/透传），唯一缺口是**运行时主场景 `Main.tscn` 内联 StartMenu 子树缺少 ModeSelectVBox/ModeOption1/ModeOption2 三个节点**：

- `project.godot:15` 的 `run/main_scene = res://scenes/Main.tscn` —— 运行时 title 屏是 **Main.tscn 内联的 StartMenu 子树**（`Main.tscn:148`，CanvasLayer + script），不是独立的 `ui_start_menu.tscn`。
- PR #549 只把模式区节点插进了 **`ui_start_menu.tscn`**（独立基准场景，非运行时场景），Main.tscn 的内联子树未同步 → 两个场景的 StartMenu 互为「双份」且已漂移。
- `start_menu.gd:_ready()` 用 `get_node_or_null()` 收集模式选项（headless 容错设计），节点缺失时**静默跳过** → `_mode_labels` 恒为空 → title 屏不显示任何模式选项，且游戏照常运行不报错（玩家可盲按 ↑/↓ + SPACE 进入双人，但界面零提示）。

**设计哲学：修复面 = Bug 面。** 本设计只补「节点存在性」这一环（`Main.tscn` 声明式节点插入 + 测试锁定），其下游全部是 #549 已验证的既有链路（`_mode_labels` 收集 → ↑/↓ 切换 → `GameManager.set_game_mode()` → FSM MENU→SERVING → `apply_mode_to_paddles()`），机制层与 `start_menu.gd` **零改动**。同步纪律以「扩展 TC19 为全子树断言 + E2E assert_text 兜底」锁定，防止双份场景再次漂移。

```
                    ★ Issue #551 本设计（只补第一行）
        ┌────────────────────────────────────────────────────────────────┐
        │ Main.tscn StartMenu 内联子树（修改，插入 3 节点）                 │
        │   CenterContainer/VBoxContainer                                │
        │     ├── TitleLabel        （既有，不动）                          │
        │     ├── ModeSelectVBox    （新增，separation=8）                 │
        │     │     ├── ModeOption1  「单人模式（AI 对战）」                 │
        │     │     └── ModeOption2  「本地双人对战」                       │
        │     └── PromptLabel       （既有，不动）                          │
        └───────────────────────────┬────────────────────────────────────┘
                                    │ get_node_or_null 收集（既有，start_menu.gd 零改动）
                                    ▼
                          start_menu.gd _mode_labels[2]
                                    │ _unhandled_input ↑/↓（MENU 态）
                                    ▼
                        GameManager.set_game_mode(_mode_index)   ← 既有链路
                                    │ FSM MENU ui_accept → SERVING
                                    ▼
                reset_match() → apply_mode_to_paddles()（LOCAL_2P 双板分键） ← 既有链路
```

## 2. 既有实现状态（Prior Implementation Status）

| 系统 | 文件 | 当前状态（#549 合并后） | 与 #551 的差距 |
|------|------|----------------------|---------------|
| 双人玩法机制 | `game_manager.gd` / `paddle.gd` / `game_state_machine.gd` | ✅ 完整：`enum GameMode { SINGLE=0, LOCAL_2P=1 }`（game_manager.gd:21）、`apply_mode_to_paddles()`（FSM SERVING 入口调用）、`rebind_for_mode()`（paddle.gd:68，P2 绑 `p2_left/p2_right`） | 无 |
| 模式选择 UI 逻辑 | `gdscripts/start_menu.gd` | ✅ 完整：`_mode_index`/`_mode_labels`（25-27）、`_unhandled_input()` ↑/↓ → `GameManager.set_game_mode()`、`_apply_mode_highlight()`（选中 PADDLE_NEON+24 / 未选中 alpha 0.4+20）；节点引用全部 `get_node_or_null`（47-52），缺失静默跳过 | 节点补齐后自动生效，**零改动** |
| 基准 Title 场景 | `scenes/ui_start_menu.tscn` | ✅ 含完整 ModeSelectVBox（26-38 行，#549 已加） | 保持为同步基准（不动） |
| **运行时 Title 屏** | **`scenes/Main.tscn`（StartMenu 内联子树）** | ⚠️ 仅 TitleLabel/PromptLabel/VersionLabel，**缺模式区三节点** | ❌ **本 Bug 修复面** |
| 同步测试 | `tests/test_main_scene.gd` TC19 | ✅ 仅同步校验 `StartMenu/VersionLabel`（font_size/modulate/anchors 对齐 `ui_start_menu.tscn`） | ❌ 未断言 ModeSelect 区存在性/一致性 |
| E2E 截图 | `mini-pong/e2e_shots.json` `01_title` | ✅ 仅断言 `StartMenu/VersionLabel` 文本 `v1.0.0` + `theme_absent: 4a90d9` | ❌ 未断言模式选项文本 |

**已确认的设计缺口（PRD 断言 vs 实际代码）：**

| PRD 断言 | 实际代码 | 设计裁决 |
|---------|---------|---------|
| `start_menu.gd` 会收集模式选项并高亮 | ✅ 存在（`_ready()` 47-52 + `_apply_mode_highlight()`） | 零改动，节点补齐即生效 |
| `ui_start_menu.tscn` 模式区字段可作逐字段基准 | ✅ 存在（26-38 行） | 作为唯一事实源逐字段复制 |
| `Main.tscn` 缺节点时无报错 | ✅ `get_node_or_null` 静默降级 | 测试必须 fail-fast 显式断言，不能依赖运行时 |

## 3. 变更设计

### 3.1 `mini-pong/scenes/Main.tscn`（修改 — 插入模式区三节点）

**插入位置：** `StartMenu/CenterContainer/VBoxContainer` 内，`TitleLabel` 节点（当前 163-167 行）之后、`PromptLabel` 节点（当前 169 行）之前。

**新增节点（逐字段基准 = `scenes/ui_start_menu.tscn:26-38`，唯一事实源）：**

```
[node name="ModeSelectVBox" type="VBoxContainer" parent="StartMenu/CenterContainer/VBoxContainer"]
theme_override_constants/separation = 8

[node name="ModeOption1" type="Label" parent="StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox"]
text = "单人模式（AI 对战）"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 22

[node name="ModeOption2" type="Label" parent="StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox"]
text = "本地双人对战"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 22
```

**逐字段规格表（implement 时必须与基准逐字段一致）：**

| 字段 | ModeSelectVBox | ModeOption1 | ModeOption2 | 基准（ui_start_menu.tscn） |
|------|:---:|:---:|:---:|------|
| type | VBoxContainer | Label | Label | 同左 |
| `theme_override_constants/separation` | `8` | — | — | 26 行 |
| `text` | — | `单人模式（AI 对战）` | `本地双人对战` | 29/33 行 |
| `horizontal_alignment` | — | `1` | `1` | 30/34 行 |
| `theme_override_font_sizes/font_size` | — | `22` | `22` | 31/35 行 |

**注意事项：**
- 高亮样式（选中 +24 / 未选中 0.4 alpha +20）由 `_apply_mode_highlight()` 运行时注入，**不写入 tscn**（与 ui_start_menu.tscn 一致——基准 tscn 同样只声明 font_size 22，高亮是运行时的）。
- 无 `modulate` 声明（与基准一致）；高亮色 PADDLE_NEON #4a90d9 与 `01_title` 的 `theme_absent: 4a90d9` 同色，截图不得新增主题色。
- 竖屏 720×1280 布局：模式区在 VBox 中 Title/Prompt 之间，两行 Label 字号 22 不溢出（基准已成立）。

### 3.2 `mini-pong/tests/test_main_scene.gd`（修改 — 扩展 TC19）

**TC19（R2 同步测试）扩展断言**，沿用既有 `get_node_or_null` + `if packed:` 守卫模式（ui_start_menu.tscn 缺失时跳过比对不失败）：

| 断言 | 内容 | 失败含义 |
|------|------|---------|
| TC19-7 | `StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox` 存在 | Main.tscn 缺模式容器 |
| TC19-8 | `ModeOption1` 存在、是 Label、`text == "单人模式（AI 对战）"` | 缺/错选项 1 |
| TC19-9 | `ModeOption2` 存在、是 Label、`text == "本地双人对战"` | 缺/错选项 2 |
| TC19-10 | VBox 子节点顺序：TitleLabel < ModeSelectVBox < PromptLabel | 插入位置错误 |
| TC19-11 | `ModeOption1|2` 的 `theme_override_font_sizes/font_size == 22` 且与 `ui_start_menu.tscn` 对应节点一致 | 与基准漂移 |
| TC19-12 | `ModeSelectVBox` 的 `theme_override_constants/separation == 8` 且与基准一致 | 与基准漂移 |
| TC19-13 | `ModeOption1|2` 的 `horizontal_alignment == 1` 且与基准一致 | 与基准漂移 |

> 实现方式建议：在 `_test_tc19_version_label_in_start_menu()` 内追加（保持 R2 同步断言集中一处），或新增 `_test_tc23_mode_select_region_sync()` 并在 `run()` 注册——二选一，由 implement agent 按文件结构整洁度决定；本 DESIGN 推荐**追加到 TC19**（语义一致：都是「Main.tscn 内联 StartMenu 与 ui_start_menu.tscn 的 R2 同步」）。

### 3.3 `mini-pong/e2e_shots.json`（修改 — 可选，推荐）

`01_title` shot 的 `assert_text` 数组追加一项（防回归兜底）：

```json
{
  "node": "/root/Game/StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption2",
  "prop": "text",
  "contains": "本地双人对战"
}
```

**保持** `settle_frames: 10` 与 `theme_absent: 4a90d9` 不变（PRD §5.3 失败路径 3：截图时机内模式区需渲染完成——沿用现有 VersionLabel 断言模式，断言节点属性而非像素文本）。

### 3.4 明确不动清单（红线）

| 文件 | 理由 |
|------|------|
| `gdscripts/start_menu.gd` | 逻辑完整，节点补齐后自动生效 |
| `game_state_machine.gd` / `game_manager.gd` / `paddle.gd` | 机制层全部就绪（#549） |
| `scenes/ui_start_menu.tscn` | 保持为同步基准（唯一事实源） |
| `tests/test_local_2p.gd` 等其它测试 | 既有 A3/H1 用例继续有效，不触碰 |

### 3.5 文件变更清单

- **新文件：** 无
- **修改文件：** `mini-pong/scenes/Main.tscn`（插入 3 节点）、`mini-pong/tests/test_main_scene.gd`（扩展 TC19）、`mini-pong/e2e_shots.json`（01_title assert_text 追加 1 项，可选）
- **删除/弃用文件：** 无
- **受影响测试文件：** `tests/test_main_scene.gd`（TC19 扩展，见 §3.2）；`tests/test_local_2p.gd` 无需改动（回归验证即可）

## 4. 数据流

**Flow 1 — 正常路径（title 显示模式入口 → 双人开局）：**

```
Main.tscn 实例化
  → start_menu.gd _ready()
  → get_node_or_null("CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption1|2")  ← 本设计补齐后非 null
  → _mode_labels = [ModeOption1, ModeOption2]
  → _apply_mode_highlight() → ModeOption1 高亮（PADDLE_NEON + 24）、ModeOption2 置灰（alpha 0.4 + 20）
玩家按 ↓ → _unhandled_input → _mode_index = posmod(0+1, 2) = 1
  → _apply_mode_highlight() → ModeOption2 高亮
  → GameManager.set_game_mode(1)  →  game_mode = LOCAL_2P
玩家按 SPACE → FSM MENU ui_accept → SERVING
  → GameManager.reset_match() → apply_mode_to_paddles()
  → 双板 PLAYER 模式、P2 绑 p2_left/p2_right、P2 计分通道 ai_score
```

**Flow 2 — 回退路径（headless / mini-tree 测试环境，节点缺失）：**

```
start_menu.gd _ready() → get_node_or_null 返回 null → _mode_labels 为空
  → _apply_mode_highlight() 循环 0 次，不崩溃
  → 游戏照常运行（title 不显示模式区）
  → 既有容错，回归验证：TC 环境无 StartMenu 子树时不得报错
```

**Flow 3 — 边界路径（对局结束重开，保留上次选择）：**

```
GAME_OVER → SPACE → FSM 回 MENU → start_menu.gd show_menu()
  → visible = true → _apply_mode_highlight()（重绘，保留 _mode_index 上次值）
  → reset_match() 不触碰 game_mode（game_manager.gd:26 注释，#543 设计意图）
  → 上次双人选择保留
```

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| 节点路径拼写错误 → `get_node_or_null` 静默降级，缺陷无感复发 | TC19-7/8/9 显式断言三节点存在（fail-fast），不依赖运行时行为 |
| headless / mini-tree 测试环境无 StartMenu 子树 | 既有 `get_node_or_null` 容错，`_apply_mode_highlight()` 空循环不崩溃；TC19 的 `if packed:` 守卫在 ui_start_menu.tscn 缺失时跳过比对不失败 |
| 双份场景再次漂移（未来只改 ui_start_menu.tscn 漏 Main.tscn） | TC19 扩展为模式区全字段同步断言 + E2E 01_title assert_text 兜底（§3.2/3.3） |
| `GameManager` 未就绪（切换时单例无效） | `start_menu.gd:91` 既有守卫 `is_instance_valid(GameManager) and has_method("set_game_mode")`，切换安全 |
| 部分节点缺失（opt1 有 opt2 无） | `_mode_labels` append-only 非 null 收集 → 高亮只作用于存在的行；正常路径由测试保证三节点齐全 |
| 竖屏布局溢出（720×1280） | 模式区与 ui_start_menu.tscn 同布局，基准已成立（两行字号 22 不溢出） |
| E2E 截图时机内模式区未渲染完成 → 断言误报 | 保持 `settle_frames: 10`，断言节点属性（text contains）而非像素文本，与现有 VersionLabel 断言同模式 |
| `theme_absent` 保护冲突 | 高亮色 PADDLE_NEON #4a90d9 与 `01_title` `theme_absent: 4a90d9` 同色——模式区出现后 title 截图不得新增主题色（模式区仅文本，无彩色元素） |
| 重开保留上次选择 | `reset_match()` 不重置 `game_mode`（#543 设计意图），`show_menu()` 重绘高亮保留 `_mode_index` |

## 6. 集成点

> **状态约定：** ⬜ = 待 implement agent 接线并验证；✅ = implement agent 完成后更新。review agent 合并前核验所有 ⬜ 已解决或显式延后。

| 集成 | 我方组件 | 目标组件 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 节点 → 逻辑 | `Main.tscn` ModeSelectVBox/ModeOption1\|2 | `start_menu.gd` `_mode_labels` | `get_node_or_null` 收集（既有代码，无需改；节点补齐即接线） | ⬜ 待 implement 验证 |
| 切换 → 透传 | `start_menu.gd` `_unhandled_input` ↑/↓ | `GameManager.set_game_mode()` | 既有链路（start_menu.gd:88/95） | ⬜ 待 implement 验证 |
| 模式 → 开局 | `GameManager.game_mode` | FSM SERVING → `apply_mode_to_paddles()` | 既有链路（game_state_machine.gd:119） | ⬜ 待 implement 验证 |
| 同步 → 测试 | TC19 扩展断言 | `Main.tscn` 模式区 vs `ui_start_menu.tscn` | `get_node_or_null` + 字段比对（§3.2） | ⬜ 待 implement 实现 |
| 截图 → E2E | `01_title` assert_text 追加 | `Main.tscn` ModeOption2 文本 | e2e_shots.json（§3.3，可选） | ⬜ 待 implement 实现 |

## 7. 测试用例描述

> 以下为**测试场景描述**（plan 阶段不写可运行测试代码，implement agent 据此编写/扩展 `tests/` 下用例）。

### 场景 A：Main.tscn 模式区节点完整性（AC1，对应 TC19-7/8/9）
- **Test A-1（三节点存在性）：** 加载并实例化 `Main.tscn`；断言 `StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox`、`.../ModeOption1`、`.../ModeOption2` 均存在且 ModeOption 为 Label 类型。
- **Test A-2（文本正确）：** 断言 ModeOption1.text == `单人模式（AI 对战）`、ModeOption2.text == `本地双人对战`。
- **Test A-3（插入位置）：** 断言 VBoxContainer 的 `get_children()` 顺序为 [TitleLabel, ModeSelectVBox, PromptLabel, ...]（模式区位于 Title 与 Prompt 之间）。

### 场景 B：与基准场景 ui_start_menu.tscn 的 R2 同步（AC5，对应 TC19-11/12/13）
- **Test B-1（字段一致性）：** 分别实例化 `Main.tscn` 与 `ui_start_menu.tscn`；断言 ModeOption1/2 的 `theme_override_font_sizes/font_size == 22`、`horizontal_alignment == 1`、ModeSelectVBox 的 `theme_override_constants/separation == 8`，且 Main.tscn 各字段值与 ui_start_menu.tscn 对应节点**逐字段相等**。
- **Test B-2（基准缺失容错）：** 若 `ui_start_menu.tscn` 无法加载（`if packed:` 分支），跳过比对断言不失败（沿用 TC19-4 既有守卫模式）。

### 场景 C：默认单人 + 高亮状态（AC2/AC3）
- **Test C-1（默认值）：** 实例化 Main.tscn 后 `start_menu.get_selected_mode() == 0`，`GameManager.game_mode == SINGLE`（既有 test_local_2p A3 回归）。
- **Test C-2（初始高亮）：** `_ready()` 后 ModeOption1 高亮（modulate == PADDLE_NEON、font_size 24），ModeOption2 置灰（alpha 0.4、font_size 20）。
- **Test C-3（↓ 切换）：** 模拟 ui_down → `_mode_index == 1` → ModeOption2 高亮、ModeOption1 置灰；`GameManager.game_mode == LOCAL_2P`（`set_game_mode` 被调用）。
- **Test C-4（↑ 反向 + 循环）：** 模拟 ui_up 从 0 → `posmod(-1, 2) == 1`（循环到末尾）；再 ui_up → 0；ui_down 从 1 → 0（循环到开头）。
- **Test C-5（不可见不响应）：** `hide_menu()`（非 MENU 态）后模拟 ↑/↓，`_mode_index` 不变（`if not visible: return` 守卫）。

### 场景 D：双人开局生效（AC4）
- **Test D-1（LOCAL_2P 开局）：** 选择模式 1 后模拟 SPACE（FSM MENU→SERVING）；断言 `GameManager.game_mode == LOCAL_2P`、双板 mode == PLAYER、P2 输入映射为 `p2_left/p2_right`、P2 计分通道 ai_score（回归 test_local_2p 既有 H 组用例）。
- **Test D-2（单人零回归）：** 默认模式 SPACE 直开；断言与 #508/#549 前单人路径逐字节一致（世界隐藏、FSM 开始流不变）——回归既有 test_local_2p A3/H1。

### 场景 E：headless / mini-tree 容错（边界）
- **Test E-1（无子树不崩溃）：** 在无 StartMenu 子树的测试环境（mini-tree）加载 `start_menu.gd`，`_ready()` 不报错、`_mode_labels` 为空、无异常输出（既有容错回归）。

### 场景 F：E2E 01_title 截图（AC1 视觉层，可选）
- **Test F-1（模式选项可见）：** 按 e2e_shots.json 跑 `01_title` shot；断言 `/root/Game/StartMenu/CenterContainer/VBoxContainer/ModeSelectVBox/ModeOption2` 的 text 包含「本地双人对战」；`theme_absent: 4a90d9` 不新增主题色；settle_frames 内渲染完成无误报。

### 场景 G：重开保留上次选择（边界）
- **Test G-1（GAME_OVER → MENU 保留）：** 双人对局结束后回 MENU；断言 `GameManager.game_mode` 仍为 LOCAL_2P、`_mode_index` 保留 1、`show_menu()` 重绘高亮仍指向 ModeOption2（回归既有流程）。

## 8. 实施阶段

> light 深度：单阶段交付，无多阶段依赖。

| 阶段 | 内容 | 依赖 | 预估 |
|:---:|------|------|:---:|
| Phase 1 | ① Main.tscn 插入模式区三节点（§3.1）→ ② 扩展 TC19（§3.2）→ ③ e2e_shots.json 追加断言（§3.3，可选）→ ④ 跑 `tests/run_tests.gd` 全绿 + headless 启动 Main.tscn 无错误 + E2E 01_title 截图验证 | 无 | <0.5 人日 |

**验收锚点（implement 后验证）：** `tests/run_tests.gd` 全绿（含扩展 TC19 + test_local_2p 既有 A3/H1）；headless 启动 `Main.tscn` 无错误输出；E2E `01_title` 截图可见「本地双人对战」文本；`start_menu.gd`/`game_state_machine.gd`/`game_manager.gd`/`paddle.gd`/`ui_start_menu.tscn` 零改动（git diff 验证）。

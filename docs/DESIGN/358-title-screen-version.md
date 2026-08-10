# Design: Mini Pong 标题画面显示版本号 v1.0.0

> **Parent Issue:** #358
> **Agent:** game-plan-agent
> **Date:** 2026-08-10
> **Approach:** A — 场景声明式节点 + GameConstants 常量（采纳 PRD §4 推荐方案，无偏离）
> **深度:** depth/standard（Issue 无 depth 标签）—— 仅产出 DESIGN 文档；不产出 TASKS 文档（改动 7 个文件、纯追加式、单一子系统，不满足 TASKS 阈值）
> **PRD:** docs/PRD/358-title-screen-version.md（research PR #359，已合并）

---

## 1. 架构总览

```
┌────────────────────────── 1280×720 视口（resizable=false）──────────────────────────┐
│                                                                                       │
│                        Mini Pong        ← TitleLabel（64px，居中）                     │
│                        按 SPACE 开始     ← PromptLabel（28px，居中）                   │
│                                                                                       │
│  v1.0.0                 ← VersionLabel（16px，左下角锚定，本 Issue 新增）              │
└───────────────────────────────────────────────────────────────────────────────────────┘
                             ▲
                             │ text 赋值（start_menu.gd _ready()）
             ┌───────────────┴───────────────┐
             │ GameConstants.GAME_VERSION     │ ← constants.gd 新增常量（版本号单一事实来源）
             └───────────────────────────────┘

E2E 视觉验证链（#357 引入，L3 层）：
  mini-pong/e2e_shots.json ──► run-e2e-review.sh ──► e2e_capture.gd 截图 01_title（MENU 状态）
        ──► analyze_bmp.py 4 重 anti-fake 断言（非黑 / ≥3 色 / 含主题色 4a90d9 / 帧差 ≥5.0）
```

**设计哲学：**

1. **纯展示层、零逻辑耦合**（AC2）：VersionLabel 不连接任何信号、不响应输入、不参与 FSM/计分/暂停逻辑——AC2 的结构性保障。
2. **版本号单一事实来源**（PRD R3）：`GameConstants.GAME_VERSION` 是唯一定义点；场景静态文本仅作兜底，`_ready()` 统一用常量覆盖，杜绝 .tscn 硬编码与常量漂移。
3. **双场景同步由测试双保险**（PRD R2）：`Main.tscn` 内联树与 `ui_start_menu.tscn` 独立场景必须同时新增 VersionLabel，由 `test_ui_system.gd` + `test_main_scene.gd` 双侧断言拦截"测试通过但实际画面无版本号"。
4. **E2E 路径修正**（PRD R1）：新增 `mini-pong/e2e_shots.json`（在 mini-pong/ 内，不违反目录约束），把 `state_node` 修正为 `/root/Game/GameStateMachine`（Main.tscn 根节点名为 `Game`），并修正 autoplay/require 的节点路径。

**方案确认：** PRD §4 推荐方案 A（场景声明式节点 + GameConstants 常量）。本设计完全采纳：与 #292 既有声明式场景风格一致，测试可直接加载场景断言节点与文本（对齐现有 TC5 模式），对 E2E 视觉层最友好（静态节点在 MENU 状态必然渲染）。方案 B（程序化创建）与项目声明式风格相悖、headless 下需额外守卫；方案 C（ProjectSettings config/version）key 需注册、测试需 mock，对 canary 属过度设计。

---

## 2. 新组件 — 详细设计

### 2.1 VersionLabel（Label 节点，两处场景各一）

- **文件：** `mini-pong/scenes/ui_start_menu.tscn`（独立场景，StartMenu 根下）+ `mini-pong/scenes/Main.tscn`（内联树，parent=`StartMenu`）
- **节点结构：** StartMenu（CanvasLayer）的**直接子节点**，与 `CenterContainer` 平级：

```
StartMenu (CanvasLayer, layer=1, visible=true)
├── CenterContainer / VBoxContainer / TitleLabel + PromptLabel   （既有，不动）
└── VersionLabel (Label)                                          （新增，左下角锚定）
```

- **属性规格（两处完全一致）：**

| 属性 | 值 | 说明 |
|------|-----|------|
| type | `Label` | — |
| `anchors_preset` | `2`（左下角） | anchor_left/right = 0.0，anchor_top/bottom = 1.0 |
| `offset_left` | `16.0` | 距左 16px |
| `offset_top` | `-36.0` | 标签顶部距底 36px |
| `offset_right` | `400.0` | 宽度上限 384px（文本实际 ~60px，左对齐） |
| `offset_bottom` | `-12.0` | 距底 12px |
| `text` | `"v1.0.0"` | 静态兜底值；`_ready()` 会用 `GameConstants.GAME_VERSION` 覆盖 |
| `theme_override_font_sizes/font_size` | `16` | 可读且不抢视觉焦点（≤20 不冲突，PRD 边界 3） |
| `modulate` | `Color(0.29, 0.56, 0.85, 0.6)` | 霓虹蓝 #4a90d9 @ 60% 透明度（#289 主题色） |

- **信号：** 无。
- **布局依据：** 1280×720 固定窗口；VersionLabel 位于左下角（屏幕坐标 y ∈ [684, 708]），与居中的 VBoxContainer（TitleLabel/PromptLabel）无任何重叠区域；`resizable=false` 保证任意时刻位置确定。

### 2.2 mini-pong/e2e_shots.json（新配置文件）

**实现阶段照此内容创建**（本阶段只给规格，不落文件）：

```json
{
  "_comment": "mini-pong 专属 E2E shot plan（#358）。修正模板 state_node 为 /root/Game/...（Main.tscn 根节点名为 Game）。",
  "game": "mini-pong",
  "default_archetype": "loop",
  "max_wall_seconds": 120,
  "state_node": "/root/Game/GameStateMachine",
  "state_property": "current_state",
  "states": { "MENU": 0, "SERVING": 1, "PLAYING": 2, "PAUSED": 3, "SCORED": 4, "GAME_OVER": 5 },
  "theme_color": "4a90d9",
  "autoplay": {
    "mode": "ai",
    "tweaks": [
      { "node": "/root/Game/PlayerPaddle", "prop": "mode", "value": 1 },
      { "node": "/root/Game/AIPaddle", "prop": "mode", "value": 1 },
      { "node": "/root/Game/AIPaddle", "prop": "ai_position_error", "value": 60 }
    ]
  },
  "groups": {
    "loop": {
      "_comment": "match 覆盖 gdscripts/.*\.gd、scenes/.*\.tscn、project\.godot —— 本 PR 改动必然命中，L3 视觉层会被执行",
      "match": ["gdscripts/.*\.gd", "scenes/.*\.tscn", "project\.godot"],
      "shots": [
        { "name": "01_title", "state": "MENU", "settle_frames": 10 },
        { "name": "02_midgame", "state": "PLAYING", "require": { "node": "/root/GameManager", "prop": "player_score", "min": 1 }, "settle_frames": 5 },
        { "name": "03_gameover", "state": "GAME_OVER", "settle_frames": 10 }
      ]
    }
  }
}
```

**关键修正点（相对 framework/templates/e2e_shots.json）：**

| 项 | 模板值（错误） | 本设计值（正确） | 原因 |
|----|--------------|----------------|------|
| `state_node` | `/root/Main/GameStateMachine` | `/root/Game/GameStateMachine` | Main.tscn 根节点名为 `Game`（PRD R1） |
| `require.node` | `/root/Main/GameManager` | `/root/GameManager` | GameManager 是 autoload（project.godot `[autoload]`），实际位于 `/root/` 下，Main.tscn 中无此节点 |
| autoplay tweaks | `/root/Main/PlayerPaddle` 等 | `/root/Game/PlayerPaddle`、`/root/Game/AIPaddle` | 同上，节点在 `Game` 根下 |

`01_title`（MENU 状态，settle_frames=10）：StartMenu 初始 `visible=true`、FSM 初始 `State.MENU`（`current_state` 属性已确认存在，枚举值 0 与 states 映射一致）——截图稳定包含左下角版本号。`theme_color=4a90d9` 驱动 analyze_bmp.py 第三重 anti-fake 断言。

---

## 3. 现有组件修改

### 3.1 PRD 断言 vs 代码库现状（gap 分析）

| PRD 断言 | 实际代码库 | 设计裁决 |
|----------|-----------|---------|
| `start_menu.gd` 107 行 CanvasLayer 控制器 | ✅ 一致（@onready 引用 TitleLabel/PromptLabel，headless 守卫存在） | 按 PRD 追加 version_label 引用 |
| Main.tscn 根节点名为 `Game` | ✅ `[node name="Game" type="Node2D"]` | e2e_shots.json 全部路径用 `/root/Game/...` |
| 模板 shot plan 可用 | ⚠️ 模板 `state_node=/root/Main/...` 在 mini-pong 解析失败；`require` 引用 `/root/Main/GameManager` 也不存在（autoload 在 `/root/GameManager`） | 新增 `mini-pong/e2e_shots.json` 修正全部路径（§2.2） |
| 测试 TC5 加载场景断言节点 | ⚠️ 现有 TC5 用 `packed.instantiate()` 裸实例化，**不 add_child，`_ready()` 不执行** | .tscn 静态 `text="v1.0.0"` 兜底 + 测试双路径断言（静态值 & `_ready()` 后常量值，见 §9 Scenario B） |
| constants.gd 无版本常量 | ✅ 确认（仅 Screen/Ball/Paddle/AI/Scoring/Colors 分区） | 追加 `GAME_VERSION` 到新 "Version" 分区 |
| test_constants.gd 有"常量全集"断言 | ✅ 无全集断言，仅逐项断言具体值 | 追加常量安全；可选追加 GAME_VERSION 断言 |
| FSM 6 状态、`current_state`、MENU 初始 | ✅ 全部确认 | e2e states 映射沿用 |

### 3.2 修改清单

| 文件 | 变更 | 原因 |
|------|------|------|
| `mini-pong/gdscripts/constants.gd` | 新增 `const GAME_VERSION: String = "v1.0.0"`（新 `# ── Version ──` 分区，置于 Screen 分区之后） | 版本号单一事实来源（R3）；class_name GameConstants 全局可用，start_menu.gd 直接引用 |
| `mini-pong/gdscripts/start_menu.gd` | 新增 `@onready var version_label: Label = get_node_or_null("VersionLabel")`；`_ready()` 内（既有空守卫之后）加 `if version_label: version_label.text = GameConstants.GAME_VERSION` | 运行时统一赋值防漂移；`get_node_or_null` 兜底保证 headless/缺节点不崩溃（PRD 边界 1） |
| `mini-pong/scenes/ui_start_menu.tscn` | StartMenu 根下新增 VersionLabel（§2.1 规格） | AC1 独立场景侧 |
| `mini-pong/scenes/Main.tscn` | StartMenu 内联树新增同名 VersionLabel（`parent="StartMenu"`，属性与上完全一致） | AC1 实际运行侧（R2 双场景同步） |
| `mini-pong/tests/test_ui_system.gd` | 扩展 TC5 或新增 TC16（§9 Scenario B） | AC3 |
| `mini-pong/tests/test_main_scene.gd` | 新增 TC（§9 Scenario C） | AC3 + R2 双保险 |
| `mini-pong/tests/test_constants.gd` | 可选新增 GAME_VERSION 断言（§9 Scenario A） | 常量回归 |

**新文件：** `mini-pong/e2e_shots.json`
**删除/弃用文件：** 无
**受影响测试文件：** `test_ui_system.gd`（追加式）、`test_main_scene.gd`（追加式）、`test_constants.gd`（可选追加式）——均为纯追加，不改动任何既有断言。

**start_menu.gd 变更伪代码：**

```gdscript
# ── Node References ──
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel      # 既有
@onready var prompt_label: Label = $CenterContainer/VBoxContainer/PromptLabel    # 既有
@onready var version_label: Label = get_node_or_null("VersionLabel")             # 新增（兜底引用）

func _ready() -> void:
	# Guard: run only if nodes exist（既有）
	if not title_label or not prompt_label:
		return

	# 新增：版本号统一由常量赋值（headless 安全，纯属性写入）
	if version_label:
		version_label.text = GameConstants.GAME_VERSION

	# 既有动画逻辑不变（is_inside_tree() and get_tree() 守卫）
	if is_inside_tree() and get_tree():
		_start_title_pulse()
		_start_prompt_blink()

	visible = true
```

---

## 4. 数据流

**Flow 1 — 正常路径（启动 → 渲染）：**
```
main 启动 → Main.tscn 实例化（run/main_scene）
  → StartMenu 节点树就绪（含 VersionLabel，静态 text="v1.0.0"）
  → StartMenu._ready() 执行 → version_label.text = GameConstants.GAME_VERSION（"v1.0.0"）
  → FSM 初始 MENU 状态，StartMenu visible=true
  → 左下角 (16, 684)–(400, 708) 渲染 v1.0.0（霓虹蓝 60% 透明）
```

**Flow 2 — 兜底路径（节点缺失）：**
```
某场景缺 VersionLabel（如测试裸建 start_menu.gd，或未来场景重构漏加）
  → get_node_or_null("VersionLabel") 返回 null
  → if version_label: 守卫跳过 → 不崩溃、不报错
  → 其余 UI（标题/提示/动画）行为完全不受影响
```

**Flow 3 — E2E 视觉验证路径（review agent 执行）：**
```
run-e2e-review.sh <PR> --subproject mini-pong
  → 读取 mini-pong/e2e_shots.json（存在，不再回退模板）
  → resolve_plan.py：PR diff 命中 loop 组（gdscripts/.*\.gd / scenes/.*\.tscn）
  → e2e_capture.gd：驱动 FSM 至 MENU → settle 10 帧 → 截图 01_title.png
  → analyze_bmp.py 4 重断言：非黑（黑像素占比 ≤0.5）、颜色数 ≥3、含主题色 4a90d9（容差 32）、
    与 02_midgame 帧差 ≥5.0
  → 通过 → L3 视觉层 PASS，截图上传 PR 评论
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | headless 下 `_ready()` 执行 | 沿用既有 `is_inside_tree() and get_tree()` 守卫；text 赋值是纯属性写入，无渲染依赖（PRD 边界 1） |
| 2 | 场景缺 VersionLabel（测试裸建/未来重构） | `get_node_or_null` + `if version_label:` 守卫；且既有 title/prompt 空守卫先行 return（PRD 失败路径 3） |
| 3 | 双场景不同步：只改 ui_start_menu.tscn 漏改 Main.tscn（R2） | 两处都加节点；TC5/TC16（独立场景）+ test_main_scene 新 TC（内联树）双保险（PRD 失败路径 2） |
| 4 | .tscn 静态文本与常量漂移（R3） | `_ready()` 用 `GameConstants.GAME_VERSION` 覆盖；测试断言静态值 == 常量值 |
| 5 | E2E state_node 解析失败（R1） | 实现 PR 必须新增 `mini-pong/e2e_shots.json`（state_node=`/root/Game/GameStateMachine`）；不新增则回退模板路径必然失败（PRD 失败路径 1） |
| 6 | 左下角与 PromptLabel 视觉冲突 | VersionLabel 独立锚定左下角，CenterContainer 居中，无重叠；字号 16 ≤ 20（PRD 边界 3） |
| 7 | 截图时机不稳定 | `01_title` settle_frames=10；StartMenu 初始 visible=true、FSM 初始 MENU（PRD 边界 6） |
| 8 | 字体缺失 | Godot 回退 system_font，版本号仍可渲染（#292 既有约定，PRD 边界 5） |
| 9 | 分辨率变化 | 1280×720 固定（resizable=false），左下角锚定位置确定（PRD 边界 7） |

---

## 6. 每场景 / 每组件配置

| 场景 | 节点路径 | 配置要点 |
|:----:|---------|---------|
| `ui_start_menu.tscn` | `StartMenu/VersionLabel` | §2.1 规格：anchors_preset=2，offset(16, -36, 400, -12)，font_size=16，modulate 蓝 60%，text="v1.0.0" |
| `Main.tscn` | `StartMenu/VersionLabel`（parent=`StartMenu`） | 与上**逐属性一致**（R2 同步要求）；运行时由同一 `start_menu.gd` 驱动 |

---

## 7. 集成点

> 状态约定：⬜ = 待实现 agent 接线；✅ = 已连接（实现 agent 完成后更新）。

| 集成 | 我方组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 版本号常量 → 展示 | `VersionLabel.text` | `GameConstants.GAME_VERSION` | start_menu.gd `_ready()` 赋值（class_name 直接引用） | ⬜ |
| E2E shot plan → runner | `mini-pong/e2e_shots.json` | `run-e2e-review.sh` L3 | 文件位于 `<subproject>/e2e_shots.json`，runner 自动发现（不再回退模板） | ⬜ |
| 状态驱动截图 | `e2e_capture.gd` | `GameStateMachine.current_state` | `state_node=/root/Game/GameStateMachine`，states 映射 MENU=0 | ⬜ |
| 截图 → 视觉断言 | `01_title.png` | `analyze_bmp.py` | `--theme 4a90d9` / `--min-colors 3` / `--diff-with 02_midgame --min-delta 5.0` | ⬜ |
| 双场景一致性 | 两处 `VersionLabel` | 测试双保险 | `test_ui_system.gd` TC5/TC16 + `test_main_scene.gd` 新 TC | ⬜ |

---

## 8. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | constants.gd（GAME_VERSION）+ start_menu.gd（引用与赋值）+ 两场景 VersionLabel 节点 | 0.5 天 |
| Phase 2 | P0 | `mini-pong/e2e_shots.json` + 测试更新（test_ui_system / test_main_scene / 可选 test_constants） | 0.5 天 |

依赖顺序：Phase 1 先行（测试与 E2E 依赖节点存在）；Phase 2 的 E2E 验证依赖 `run-e2e-review.sh` 可用（#357 已合入，`864d2df`）。

---

## 9. 测试用例描述

> 仅测试描述，不写可运行测试代码（实现 agent 负责落盘）。断言读取 font_size 时遵循 #346 教训：用 `label.get("theme_override_font_sizes/font_size")`，不要用 `get_theme_font_size()`（headless 返回 0）。

### Scenario A: GameConstants.GAME_VERSION（test_constants.gd，可选追加）
- Test A-1：`load("res://gdscripts/constants.gd")` 后 `CONSTS.GAME_VERSION` 存在且 `== "v1.0.0"`。
- Test A-2：既有 TC6/TC7/TC8 断言全部保持通过（追加式修改不破坏任何既有断言）。

### Scenario B: ui_start_menu.tscn 的 VersionLabel（test_ui_system.gd — 扩展 TC5 或新增 TC16）
前置：`load("res://scenes/ui_start_menu.tscn")` 并 `instantiate()`。
- Test B-1：`get_node_or_null("VersionLabel")` 非空。
- Test B-2：节点是 `Label` 类型。
- Test B-3：静态 `text == "v1.0.0"`（裸 instantiate 不触发 `_ready()`，验证 .tscn 兜底值——对应 gap 分析中的测试模式差异）。
- Test B-4：`get("theme_override_font_sizes/font_size") >= 12`（字号规格 16）。
- Test B-5：锚定左下角（`anchor_top == 1.0` 且 `anchor_left == 0.0`）。
- Test B-6：`add_child` 入树触发 `_ready()` 后 `text == GameConstants.GAME_VERSION`（验证常量覆盖，防漂移）。
- Test B-7：`modulate` 为霓虹蓝系（R/G/B 分别与 0.29/0.56/0.85 容差 0.01，参照 TC11 颜色断言模式）。

### Scenario C: Main.tscn 内联树的 VersionLabel（test_main_scene.gd，新增）
前置：`load("res://scenes/Main.tscn")` 并 `instantiate()`。
- Test C-1：`StartMenu/VersionLabel` 节点存在。
- Test C-2：静态 `text == "v1.0.0"`。
- Test C-3：与 ui_start_menu.tscn 的 VersionLabel 配置一致（font_size / modulate / 锚定逐项对比，防 R2 双场景漂移——PRD 失败路径 2 的结构性拦截）。

### Scenario D: start_menu.gd 运行时行为
- Test D-1：裸建 start_menu.gd（无子节点）调用 `_ready()` 不崩溃（headless 安全，参照 TC3 模式）。
- Test D-2：挂载含 VersionLabel 的节点树并 `_ready()` 后，`text == GameConstants.GAME_VERSION`。
- Test D-3：`show_menu()` / `hide_menu()` 往返后版本号随 StartMenu 显隐联动、无报错（验证零副作用）。

### Scenario E: E2E 视觉验证（`scripts/run-e2e-review.sh <PR> --subproject mini-pong`）
- Test E-1（L0）：mini-pong 子项目 Godot 编译通过（含新增节点/常量）。
- Test E-2（L1）：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿。
- Test E-3（L2）：运行时截图 `01_title.png` 成功产出（MENU 状态，settle_frames=10）。
- Test E-4（L3）：analyze_bmp.py 4 重 anti-fake 断言通过——非黑（黑像素占比 ≤ 0.50）、颜色数 ≥ 3、含主题色 `4a90d9`（RGB 容差 32）、与 `02_midgame` 帧差 ≥ 5.0。
- Test E-5：人工/脚本复核 `01_title.png` 左下角区域（屏幕 y ∈ [680, 715]）存在非背景色像素（版本号可见，AC4）。

### Scenario F: 回归
- Test F-1：14 个测试套件全绿（#346 修复后基线，`run_tests.gd` 聚合）。
- Test F-2：diff 确认不触碰 `ball.gd` / `paddle.gd` / `scoring_manager.gd` / `game_state_machine.gd` / `game_manager.gd` / `audio_engine.gd` 等游戏逻辑（AC2 保障手段）。
- Test F-3：`mini-pong/` 目录边界——diff 无任何 `mini-pong/` 之外的文件（技术约束）。

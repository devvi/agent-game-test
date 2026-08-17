# DESIGN: [Feature] 暂停菜单显示当前比分与波次

> **Parent Issue:** #513
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** A — 场景静态 Label + show_overlay() 读值（确认 PRD §4 推荐方案；light 特性，无方案分歧）
> **Reference PRD:** docs/PRD/513-pause-score-wave.md（research PR #514，已合并）
> **所有权:** `content_ownership: mechanical`（暂停时读 GameManager 状态写入 Label = 确定性数据展示，无品味决策）
> **深度:** light（depth/light 标签）—— 文件域 2（pause_overlay.gd / Main.tscn）+ constants.gd 常量 + 1 测试文件描述，无新文件、无迁移、无弃用 → **不产 TASKS 文档**（低于阈值）

---

## 1. 架构概述

### 1.1 设计核心

**PauseOverlay（CanvasLayer layer=10）下新增 ScoreLabel / WaveLabel 两个 Label 节点；pause_overlay.gd 新增 `_resolve_game_manager()` 与 `_read_state()`，在 `show_overlay()` 时从 GameManager（autoload）读 `player_score / ai_score / wave_index` 写入文本并套 NeonStyle。暂停冻结语义保证「读一次即正确」，无需信号订阅（AC3 天然满足）。**

```
Main.tscn PauseOverlay 节点树（改造后）
PauseOverlay (CanvasLayer, layer=10, visible=false, script=pause_overlay.gd)
├── ColorRect                  (遮罩 0,0,0,0.6, 全屏, 既有 #296)
├── Label                      (「暂停」, font_size 48, 居中, 既有 #296)
├── ScoreLabel  (新增)         (font_size 32, 居中, 暂停文字下方, 文本初始「—」)
└── WaveLabel   (新增)         (font_size 32, 居中, ScoreLabel 下方, 文本初始「—」)

FSM.enter_state(PAUSED) ──► _set_ui("pause") ──► pause_overlay.show_overlay()
        │                                             │
        └── GameHUD.visible=false                     ▼
                                             _read_state():
                                               gm = _resolve_game_manager()
                                               gm == null → 两 Label 写「—」+ push_warning(1次)
                                               否则 → ScoreLabel = "Player: X   AI: Y"
                                                      WaveLabel  = "第 N 波"
                                                      NeonStyle.apply 两 Label (HUD_INFO_COLOR)
```

设计哲学：
1. **读一次即正确（冻结语义）** — 暂停期间球/板/得分全部停摆（#296 + GAME_DESIGN/18-PAUSE-SYSTEM.md），进入 PAUSED 时读值一次即定格；不订阅 `score_changed/wave_started`（方案 B 否决：与冻结语义矛盾 + 连接生命周期管理纯冗余，PRD §4）
2. **消费方复用既有数据设施** — GameManager 状态（#385/#386）就绪只缺消费方；game_hud.gd 的 `_resolve_game_manager()`（可注入 var + `is_instance_valid(GameManager)` 回退）与 `_wave_index()`（`get()` + null 守卫）是同款读写模式，直接对齐
3. **样式单一事实源** — NeonStyle.apply（#392）+ constants.gd 颜色常量；不引入新主题（issue 明示）
4. **容错消费惯例** — 未接线（GameManager 缺失 / Label 缺失）显示占位符「—」，不崩溃（#392 契约 + game_hud.gd `_warned` 单次警告模式）
5. **最小变更（light）** — 1 脚本 + 1 场景 + 4 常量，0.5 天工作量；不动 FSM `_set_ui` 契约、不动 HUD

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main @ 92bfb1c） | 设计裁决 |
|---------|--------------------------|---------|
| pause_overlay.gd 仅 show_overlay()/hide_overlay() 切 visible，22 行 | ✅ pause_overlay.gd 全文件 22 行：extends CanvasLayer + @onready color_rect/label + _ready hide + show/hide | 保持 show/hide 契约不变，仅 show_overlay() 内追加 _read_state() |
| PauseOverlay 为 CanvasLayer layer=10，ColorRect 遮罩 + 单 Label「暂停」(font_size 48) | ✅ Main.tscn:156-158 CanvasLayer layer=10 visible=false；167 ColorRect 全屏 0.6 alpha；173 Label anchors_preset=8 居中 offset_top=-24 font_size=48（186 行） | 新 Label 锚点居中、offset_top 下移避开「暂停」文字（垂直三行排布） |
| GameManager 有 player_score/ai_score/wave_index + score_changed/wave_started 信号 | ✅ game_manager.gd:16/22 信号；29/30/37 状态变量；wave_index 注释「IDLE 期 0，begin_wave 后从 1 递增」 | 读值走 `gm.get("...")` + null 守卫（同 game_hud.gd `_wave_index()`），不依赖信号 |
| game_hud.gd 有 `_resolve_game_manager()` 注入/回退模式与 `_wave_index()` | ✅ game_hud.gd:62-70 `_resolve_game_manager()`（var 可注入 + is_instance_valid 回退）；72-78 `_wave_index()` get()+null 守卫 | pause_overlay.gd 同款实现（可注入 `var game_manager`，测试 mock 便利） |
| HUD 文案先例 "Player: %d" / "AI: %d"；信息条「第 %d 波」 | ✅ game_hud.gd:124/126 `"AI: " + str(ai)` / `"Player: " + str(p)`；168/173 `"第 %d 波 · 剩余 %d"` | 比分行 `"Player: %d   AI: %d"`（同一行双前缀）；波次行 `"第 %d 波"`；格式前缀入 constants.gd（裁决 2） |
| NeonStyle.apply(label, color) 静态方法 | ✅ ui_neon_style.gd:9 class_name NeonStyle；:15 static func apply(label, color, opts={}) | 直接调用；颜色常量 constants.gd（HUD_INFO_COLOR 等，§3） |
| test_pause.gd 有 Engine.register_singleton mock GameManager 先例 | ✅ test_pause.gd:126-170 `_setup_gm_mock()`（GDScript 源码注入 + register_singleton） | §9 测试描述复用该模式（mock 注入 game_manager var 或注册单例） |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立裁决）

**裁决 1（比分行单色单 Label）：** PRD §8 允许双色（PLAYER_NEON_BLUE/AI_NEON_RED）或单色（HUD_INFO_COLOR）。定案：**单 Label + 单色 HUD_INFO_COLOR**。理由：双色需拆两个 Label 或 RichTextLabel（light 深度范围膨胀）；HUD 双色来自「顶部红区/底部蓝区」布局，暂停行无分区诉求；mechanical 所有权下信息清晰 > 装饰。若未来 taste 调整要双色，拆两个 Label 成本低，本 plan 不预埋。

**裁决 2（格式常量入 constants.gd，HUD 暂不迁移）：** PRD §5.3-3/§8-3 要求格式前缀进 constants.gd 防双处漂移。定案：**新增 4 常量**（HUD_SCORE_PREFIX_PLAYER="Player: "、HUD_SCORE_PREFIX_AI="AI: "、HUD_WAVE_PREFIX="第 "、HUD_WAVE_SUFFIX=" 波"），pause_overlay.gd 消费；**game_hud.gd 既有内联字符串不迁移**（light 边界，改动 HUD 引入回归风险，收益低于成本）。漂移风险记为已知债务，由 review agent 在 implement merge 后写入 GDD（§7 deferred）。

**裁决 3（读值时机 = show_overlay() 内每次调用）：** 每次 `show_overlay()` 都重新 `_read_state()`。理由：快速暂停/恢复连按（PRD §1.4 场景 3）要求再暂停时文本刷新为新值；冻结语义下每次读值成本为零（无 I/O），幂等。**不订阅信号**（方案 B 否决，PRD §4 已论证冗余）。

**裁决 4（GameManager 缺失 → 占位符「—」+ 单次 push_warning）：** 对齐 game_hud.gd `_warned` 单次警告模式（新 `_warned_gm: bool`），防 mini-tree/headless 刷屏；缺失时两 Label 写「—」，不崩溃（PRD §5.2-2 / §5.3-1）。

---

## 2. 新组件

无新脚本/场景/资源文件（light 深度，Label 进既有 Main.tscn 节点树）。「新增」仅指 Main.tscn PauseOverlay 下两个场景内节点，详见 §3.1 与 §6。

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `mini-pong/gdscripts/pause_overlay.gd` | 新增 `@onready var score_label: Label = $ScoreLabel` / `wave_label: Label = $WaveLabel`；新增 `var game_manager`（可注入）+ `_warned_gm: bool`；新增 `_resolve_game_manager()` / `_read_state()` / `_set_texts()`；`show_overlay()` 末尾调用 `_read_state()` | 消费 GameManager 状态；注入点对齐 game_hud.gd；读值填充文本 |
| `mini-pong/scenes/Main.tscn` | PauseOverlay 下新增 ScoreLabel / WaveLabel 节点（§6 配置表） | 两行信息载体（issue AC1/AC2） |
| `mini-pong/gdscripts/constants.gd` | Neon HUD 区（#392）新增 4 个格式常量（裁决 2） | 防双处文案漂移（PRD §5.3-3） |

**pause_overlay.gd 变更后形态（伪代码，implement agent 据此落地）：**

```gdscript
extends CanvasLayer
## ...(既有头注释保留)...
const CONSTS = preload("res://gdscripts/constants.gd")
const NeonStyle = preload("res://gdscripts/ui_neon_style.gd")

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var score_label: Label = $ScoreLabel        # 新增
@onready var wave_label: Label = $WaveLabel          # 新增

var game_manager                                   # 可注入（测试 mock，对齐 game_hud.gd）
var _warned_gm: bool = false                       # GameManager 缺失只警告一次

func _ready() -> void:
    hide()

func show_overlay() -> void:
    visible = true
    _read_state()                                   # 新增：读一次即正确（冻结语义）

func hide_overlay() -> void:
    visible = false

# ── 新增内部方法 ──
func _resolve_game_manager():
    if game_manager != null:
        return game_manager
    if is_instance_valid(GameManager):              # autoload 回退
        game_manager = GameManager
    return game_manager

func _read_state() -> void:
    var gm = _resolve_game_manager()
    if gm == null:
        if not _warned_gm:
            push_warning("PauseOverlay: GameManager 未找到，显示占位符")
            _warned_gm = true
        _set_texts("—", "—")
        return
    var p = gm.get("player_score")
    var a = gm.get("ai_score")
    var w = gm.get("wave_index")
    _set_texts(
        CONSTS.HUD_SCORE_PREFIX_PLAYER + str(int(p) if p != null else 0) + "   " +
        CONSTS.HUD_SCORE_PREFIX_AI + str(int(a) if a != null else 0),
        CONSTS.HUD_WAVE_PREFIX + str(int(w) if w != null else 0) + CONSTS.HUD_WAVE_SUFFIX)

func _set_texts(score_text: String, wave_text: String) -> void:
    if score_label:
        score_label.text = score_text
        NeonStyle.apply(score_label, CONSTS.HUD_INFO_COLOR)
    if wave_label:
        wave_label.text = wave_text
        NeonStyle.apply(wave_label, CONSTS.HUD_INFO_COLOR)
```

> 注：`@onready` 在 Label 缺失时会报错（Godot 4 对缺失节点抛错）——设计上要求 Main.tscn 同步新增节点（同一 PR 内落地）；若实现期担心旧场景缓存，可退化为 `get_node_or_null("ScoreLabel")` 手动解析（PRD §5.3-2 已给守卫思路，实现 agent 自行权衡，二选一即可，本设计推荐 @onready + 场景同步变更）。

### 3.2 受影响测试文件（只列描述，不写代码）

| 测试文件 | 影响 | 处理 |
|---------|------|------|
| `mini-pong/tests/test_pause.gd` | FSM 测试的 `_make_mock_pause_overlay`（test_pause.gd:71）是注入源码的 mock CanvasLayer（仅 show/hide），**不受** pause_overlay.gd 新方法影响 → 零回归 | 不修改；overlay 内容测试建议新建文件（§9） |
| `mini-pong/tests/test_hud.gd` | 不加载 Main.tscn 全树，无影响 | 无 |
| `mini-pong/tests/e2e_playthrough.gd` | 暂停相关仅 `tree.paused` 断言，与 overlay 内容无关 | 无 |

### 3.3 移除/弃用文件

无。

---

## 4. 数据流

### Flow 1: 正常路径 — PLAYING 按 Escape 暂停（AC1/AC2/AC3）

```
PLAYING 中按 Escape
  → FSM._input ui_cancel → transition_to(State.PAUSED)        (game_state_machine.gd:66)
  → enter_state(PAUSED): _set_ui("pause")                     (:137-141)
      → GameHUD.visible = false（比分/波次随 HUD 隐藏）
      → PauseOverlay.visible = true
      → pause_overlay.show_overlay()
          → _read_state()
              → _resolve_game_manager() → GameManager (autoload)
              → gm.get("player_score") / gm.get("ai_score") / gm.get("wave_index")
              → ScoreLabel.text = "Player: X   AI: Y"   (NeonStyle HUD_INFO_COLOR)
              → WaveLabel.text  = "第 N 波"             (NeonStyle HUD_INFO_COLOR)
```

### Flow 2: 回退路径 — GameManager 缺失（mini-tree / headless 异常环境，AC4）

```
show_overlay() → _read_state() → _resolve_game_manager() == null
  → 单次 push_warning（_warned_gm 防刷屏）
  → ScoreLabel.text = "—" / WaveLabel.text = "—"
  → 不崩溃；后续环境修正后再次 show_overlay() 自动恢复
```

### Flow 3: 恢复与再暂停（AC5 + 快速连按）

```
PAUSED 中按 Escape → enter_state(PLAYING): hide_overlay() → PauseOverlay.visible = false（整层隐藏，无残留文本）
再暂停 → show_overlay() → _read_state() 重新读当前值 → 文本刷新为新值（无中间帧残留）
```

---

## 5. 边界情况与错误处理

| Edge Case | 缓解 |
|-----------|------|
| 首波前暂停（wave_index == 0） | 正常不可达（#393 `_start_first_wave` 进入 PLAYING 即触发首波）；防御性显示「第 0 波」（数值诚实），不崩溃（PRD §5.2-1） |
| GameManager 缺失（mini-tree 测试 / autoload 未注册） | `_resolve_game_manager()` null → 占位符「—」+ 单次 push_warning（裁决 4；对齐 game_hud.gd 容错惯例，PRD §5.2-2） |
| 快速暂停/恢复连按 | 每次 show_overlay() 重新读值（裁决 3）；hide 整层隐藏 → 无中间帧残留（PRD §5.2-3） |
| 比分位数增长（0 → 21） | Label 水平居中、offset_left/right ±220 自适应宽度；21 分制最多 2 位数字，无溢出（PRD §5.2-4） |
| 21 分终局（GAME_OVER）后 Escape | FSM `_input` 仅 PLAYING/PAUSED 响应 ui_cancel → 终局无法暂停，无需处理（PRD §5.2-5） |
| Label 与「暂停」文字重叠 | 新 Label 锚点居中 + offset_top 下移（ScoreLabel +80 / WaveLabel +132），垂直三行排布，不与 font_size 48 文字重叠（PRD §5.2-6） |
| 中文渲染 | 默认字体渲染中文已有先例（「暂停」Label），无新增字体依赖（PRD §5.2-7） |
| headless 样式安全 | NeonStyle.apply 为纯主题覆盖（注释「headless 安全」），无渲染依赖（PRD §5.2-8） |
| Label 节点缺失（旧场景缓存/手工删节点） | @onready 依赖场景同步变更（同一 PR）；若采用 get_node_or_null 变体则跳过填充不崩溃（PRD §5.3-2） |
| 文本格式与 HUD 漂移 | 格式前缀入 constants.gd 共享（裁决 2）；HUD 内联字符串迁移记为债务，GDD 记录（§7 deferred） |

---

## 6. 按场景/组件配置

| 场景 | 节点 | 配置 | 说明 |
|:-----:|------|------|------|
| Main.tscn | `PauseOverlay/ScoreLabel`（新增） | `anchors_preset=8`（居中），`offset_left=-220 / offset_top=80 / offset_right=220 / offset_bottom=120`，`text="—"`，`horizontal_alignment=1`，`vertical_alignment=1`，theme_override font_size=32 | 比分行：`"Player: X   AI: Y"`；位于「暂停」文字（center±24）下方 |
| Main.tscn | `PauseOverlay/WaveLabel`（新增） | 同上，`offset_top=132 / offset_bottom=172` | 波次行：`"第 N 波"`；位于 ScoreLabel 下方 |
| Main.tscn | `PauseOverlay`（既有） | 不改（layer=10 / visible=false / script 引用） | 新 Label 自动随整层显示/隐藏（AC5 天然满足） |

> 样式（颜色/描边）由代码侧 `NeonStyle.apply` 套用（对齐 #392「样式单一事实源在代码」）；场景文件只负责布局与初始占位文本。

---

## 7. 集成点

| Integration | 我们的组件 | 目标 | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| FSM ↔ PauseOverlay | `show_overlay()/hide_overlay()` | #296 | 既有调用点不变（game_state_machine.gd:126/140），show_overlay 内部追加读值 | ✅ 既有（无需新接线） |
| PauseOverlay ↔ GameManager | `_resolve_game_manager()` + `_read_state()` | #385/#386 | autoload 读值（get() + null 守卫），不连信号 | ⬜ pending（implement 接线） |
| PauseOverlay ↔ NeonStyle | `NeonStyle.apply` | #392 | 代码侧套样式（HUD_INFO_COLOR） | ⬜ pending |
| constants.gd ↔ PauseOverlay | 4 个格式常量 | #513 | preload CONSTS 消费 | ⬜ pending |
| GDD 约定 | 「暂停菜单显示比分/波次」+ 格式常量债务 | docs/GAME_DESIGN/ | review agent 在 implement merge 后更新（本 plan 阶段不写 GDD） | ⬜ deferred |

> 状态约定：⬜ = pending（implement agent 接线并更新）；deferred = 明确延后到 implement merge 后由 review agent 执行。

---

## 8. 实现阶段

light 特性，单阶段交付：

| Phase | 内容 | 依赖 |
|:-----:|------|------|
| Phase 1（P0） | constants.gd 4 常量 → Main.tscn 2 Label → pause_overlay.gd 读值填充 → 测试描述落地 | 无（#296/#385/#386/#392/#393 均已合入 main） |

---

## 9. 测试用例描述（实现阶段据此编写，不在此写可运行测试）

> 约定：测试驱动复用 test_pause.gd 的 mock 模式——`Engine.register_singleton("GameManager", mock)`（test_pause.gd:157 先例）或直接注入 `overlay.game_manager = mock`（裁决 4 注入点）；实例化真实 `pause_overlay.gd`（非 mock CanvasLayer）挂到测试树，手动调用 `show_overlay()`/`hide_overlay()` 断言 Label 文本。建议落点：新建 `mini-pong/tests/test_pause_overlay.gd`（由 implement agent 定，与 test_pause.gd 并列）。

### Scenario A: show_overlay 填充比分与波次（AC1/AC2）
- **Test A1（比分填充）**：mock GameManager `player_score=7 / ai_score=3`，实例化 pause_overlay.gd（含 ScoreLabel/WaveLabel 节点），调用 `show_overlay()`。预期：`score_label.text == "Player: 7   AI: 3"`。
- **Test A2（波次填充）**：mock `wave_index=4`，`show_overlay()`。预期：`wave_label.text == "第 4 波"`。
- **Test A3（样式已套）**：A1 之后断言 `score_label` 存在主题覆盖（font_color 非默认或 outline 已设——以 NeonStyle.apply 生效为准）。

### Scenario B: 暂停瞬间定格（AC3）
- **Test B1（暂停中不变）**：`show_overlay()` 后修改 mock 的 `player_score`（模拟不可能发生的暂停中得分），等待数帧。预期：`score_label.text` 不变（无信号订阅，读值仅在 show 时发生）。
- **Test B2（再暂停刷新）**：mock 置新值后再次 `show_overlay()`。预期：文本刷新为新值。

### Scenario C: GameManager 缺失 → 占位符（AC4 容错）
- **Test C1（缺失不崩溃）**：不注册 GameManager、不注入，直接 `show_overlay()`。预期：`score_label.text == "—"` 且 `wave_label.text == "—"`，无异常抛出。
- **Test C2（单次警告）**：连续两次 `show_overlay()`。预期：push_warning 仅一次（`_warned_gm` 生效；可用捕获或计数断言）。

### Scenario D: Label 缺失守卫
- **Test D1（节点缺失）**：仅挂 ScoreLabel（无 WaveLabel）实例化。预期：无崩溃，ScoreLabel 正常填充，wave 分支跳过（若采用 get_node_or_null 变体；@onready 方案下此场景由场景文件保证不出现）。

### Scenario E: 恢复后无残留（AC5）
- **Test E1（隐藏整层）**：`show_overlay()` 后 `hide_overlay()`。预期：`visible == false`，无残留文本（整层隐藏语义）。
- **Test E2（再显示重新填充）**：hide 后修改 mock 值再 show。预期：文本为新值，无上次残留。

### Scenario F: 既有测试不回归（AC4）
- **Test F1**：完整 headless 测试套件（`godot --headless` + run_tests.gd）全绿 —— test_pause.gd（FSM 暂停流程 + mock overlay 不受影响）、test_hud.gd 等零失败。
- **Test F2**：`--headless --quit` 无脚本错误；Main.tscn 场景可正常加载（新增 Label 节点语法合法）。

---

## 10. 延续上下文（implement agent 交接）

**系统状态**：main @ 92bfb1c（PRD #513 已合入）。PauseOverlay（layer=10）含 ColorRect 遮罩 + 居中「暂停」Label（#296），FSM PAUSED 经 `show_overlay()/hide_overlay()` 控制（game_state_machine.gd:126/140）；GameManager autoload 持有 `player_score/ai_score/wave_index` 与 `score_changed/wave_started` 信号（#385/#386）；NeonStyle.apply 为样式入口（#392）；test_pause.gd `_setup_gm_mock` 为单例 mock 先例。

**实现要点**：
1. `mini-pong/gdscripts/constants.gd`：Neon HUD 区（#392 注释行附近）新增 `HUD_SCORE_PREFIX_PLAYER = "Player: "`、`HUD_SCORE_PREFIX_AI = "AI: "`、`HUD_WAVE_PREFIX = "第 "`、`HUD_WAVE_SUFFIX = " 波"`（裁决 2）
2. `mini-pong/scenes/Main.tscn`：PauseOverlay 节点（Main.tscn:156 起）下新增 ScoreLabel / WaveLabel（§6 配置；初始 `text="—"`；与「暂停」Label 垂直三行不重叠）
3. `mini-pong/gdscripts/pause_overlay.gd`：§3.1 伪代码落地——@onready 两 Label + `var game_manager` 注入点 + `_warned_gm` + `_resolve_game_manager()`/`_read_state()`/`_set_texts()`；`show_overlay()` 调 `_read_state()`；**保持 show/hide 对外契约不变**（FSM 调用点零改动）
4. 测试：§9 Scenario A–F 落地（建议新文件 `test_pause_overlay.gd`）；既有测试保持全绿
5. 不做：不连信号（方案 B 否决）；不改 FSM `_set_ui` 契约；不改 game_hud.gd 内联文案；不新建场景/脚本/资源；不写 GDD（review agent 负责）

**风险**：无实质风险（Low）。唯一长期注意点 = 文案双处维护 → constants.gd 常量共享 + GDD 债务记录缓解（§5/§7）。

**参考文件**：`mini-pong/gdscripts/pause_overlay.gd`（22 行现状）、`mini-pong/scenes/Main.tscn`（PauseOverlay 段 156-186）、`mini-pong/gdscripts/game_hud.gd`（_resolve_game_manager:62-70 / _wave_index:72-78 / 文案先例:124-126,168-191）、`mini-pong/gdscripts/game_manager.gd`（信号 16/22、状态 29/30/37）、`mini-pong/gdscripts/constants.gd`（#392 区 149-159）、`mini-pong/gdscripts/ui_neon_style.gd`（apply:15）、`mini-pong/tests/test_pause.gd`（mock 先例 71/126-170）、`docs/DESIGN/296-pause-and-sound.md`、`docs/GAME_DESIGN/18-PAUSE-SYSTEM.md`

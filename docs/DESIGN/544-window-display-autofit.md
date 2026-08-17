# DESIGN: [Feature] 游戏窗口大小根据显示设备初始化时自动调整

> **Parent Issue:** #544
> **Agent:** game-plan-agent
> **Date:** 2026-08-18
> **Approach:** B（PRD §4 推荐——运行时 autoload 自适应 + stretch canvas_items，逐项确认采纳；PRD 内部两处矛盾见 §2 gap 表）
> **Reference PRD:** docs/PRD/544-window-display-autofit.md（research PR #547 已合并 2026-08-18）
> **深度:** light（Issue body「工作深度: light（简单改动，快速完成）」；无 depth/ 标签，按 body 声明 light）——**单 DESIGN 文档，不产 TASKS**（skill: depth/light SKIP）
> **所有权:** `content_ownership: mechanical` —— 窗口尺寸计算/居中/回退全部为确定性几何与平台 API 机械逻辑，无 taste 决策

---

## 1. 架构总览

现状：`mini-pong/project.godot` 固定窗口 720×1280（竖屏，`resizable=false`），窗口物理尺寸 = viewport 逻辑尺寸，
`[display]` 无任何 stretch 配置。在高度 < 1280px 的显示器（如主流 1920×1080）上，窗口底部被屏幕裁掉——
玩家挡板（`Main.tscn` PlayerPaddle position (360,1240)，底缘 1250）与底部 HUD 完全不可见 → 无法操作挡板 = 无法游玩。
全仓 grep `DisplayServer` 零命中，窗口从未被代码管理过。

本设计按 PRD Approach B：新增 `WindowAutofit` autoload，启动时读取主屏**可用区域**（排除菜单栏/Dock/任务栏），
以可用高度为基准、严格保持 720:1280 等比计算窗口物理尺寸并居中；`project.godot` 开启 `stretch/mode=canvas_items`
+ `aspect=keep`，保证内容随窗口等比缩放。**逻辑分辨率 720×1280 零改动**（constants.gd + 全部测试 + E2E 基线钉死，#383 地基）：

```
                     ★ Issue #544 窗口显示适配层（纯显示层，零逻辑接触）
        ┌──────────────────────────────────────┴──────────────────────────────────────┐
        │ project.godot [display]（改）                       │ WindowAutofit autoload（新增）          │
        ▼                                                    ▼
  window/size/viewport 720×1280（不变）                _ready()（先于 Main.tscn，首帧前就位）
  window/size/resizable=false（不变）                     ├─ headless guard：DisplayServer.get_name()=="headless" → 跳过
  window/stretch/mode="canvas_items"（🆕）               ├─ DisplayServer.screen_get_usable_rect(0)   ← 主屏可用区域（含系统 UI 扣除）
  window/stretch/aspect="keep"（🆕）                     │     └─ 无效矩形 (0,0,0,0) → push_warning + 回退默认 720×1280
                                                         ├─ compute_window_size(rect)（纯函数，可单测）
                                                         │     └─ 目标高 = min(可用高, 1280)；目标宽 = floori(高×720/1280)
                                                         ├─ DisplayServer.window_set_size(Vector2i(w,h))
                                                         └─ DisplayServer.window_set_position(compute_centered_position(...))

  渲染管线：逻辑 720×1280 画布 ── canvas_items + keep ──► 等比缩放到窗口物理尺寸（≤1px 取整差由 aspect=keep 吸收）
```

### 设计哲学

1. **纯显示层，逻辑零接触**：只动 `[display]` 窗口配置 + 新增 autoload；`constants.gd`、全部坐标/碰撞/FSM/计分、8+ 个钉 1280 的测试文件逐字节不动（PRD §3.3 核查结论，本设计复核一致）。
2. **等比 = 严格 9:16**：以显示器可用**高度**为基准（AC1 的裁切根因是高度），宽度由 720:1280 推得，AC2 取整误差 ≤1px，由 `aspect=keep` 吸收（亚像素级黑边，不可见）。
3. **headless 双保险跳过**：CI/E2E（`--headless`、`--resolution 720x1280`）下 autoload 必须零副作用——`DisplayServer.get_name()=="headless"` 显式 early return + 无效矩形回退兜底，流水线零回归（PRD §8 风险 2）。
4. **纯函数可单测**：`compute_window_size()` / `compute_centered_position()` 抽出为 static 纯函数，headless 下静态调用即可断言（符合项目「机械逻辑必须可测」惯例，PRD §3.1）。
5. **v1 不做放大与多屏**：窗口上限 720×1280（min 语义，PRD §3.4/§8 核心公式）；多屏固定主屏 screen 0——两者均为 light 深度显式非目标（§2 gap 1、§5 边界 4）。

### PRD 方案确认

| 决策点 | PRD 推荐 | 本设计 | 说明 |
|--------|---------|--------|------|
| 窗口适配方案 | §4 Approach B（autoload 自适应 + stretch） | ✅ 采纳 | 唯一满足 AC1/AC2 的方案；A/C 均无法让 1280 高窗口适配 1080 显示器 |
| 核心 API 链 | §8 `screen_get_usable_rect(0)` → `compute_window_size()` → `window_set_size` + `window_set_position` 居中 | ✅ 采纳 | 跨平台统一 DisplayServer API（Godot 4.0+ 稳定） |
| 高度策略 | §3.4/§8「目标高 = min(rect.h, 1280)」 | ✅ 采纳 | min 语义 = 窗口上限 720×1280；§5.2 边界 2 的「放大」例子与本公式矛盾，见 §2 gap 1 |
| stretch 配置 | §3.1 `canvas_items` + `keep` | ✅ 采纳 | 窗口缩小/放大时内容等比缩放而非裁切/变形 |
| headless 回退 | §8「无有效屏幕静默回退 720×1280」 | ✅ 采纳（增强） | 显式 headless 名检查 + 无效矩形回退双保险 |
| 测试 | §3.2 纯函数单测（headless 可跑） | ✅ 采纳 | 新增 `test_window_autofit.gd`，TC-W 编号（避开既有 TC 前缀冲突） |

---

## 2. 现状核实（plan agent 已对照源码确认，2026-08-18）

| 文件 | 现状 | 对本设计的影响 |
|------|------|---------------|
| `mini-pong/project.godot` | `[display]` L26–28：`window/size/viewport_width=720`、`viewport_height=1280`、`resizable=false`；**无任何 `window/stretch/*` 键**；`[autoload]` 为 GameManager/AudioEngine/UpgradePool（无 WindowAutofit） | 修改点：`[display]` 增 2 键 + `[autoload]` 增 1 行 |
| `mini-pong/gdscripts/constants.gd` | L15–16：`SCREEN_WIDTH=720` / `SCREEN_HEIGHT=1280` | **不改**；本组件以 `preload` 只读引用作单一事实源 |
| `mini-pong/scenes/Main.tscn` | PlayerPaddle position (360,1240)、ScoreZoneBottom (360,1280)——正是被 1080p 显示器裁掉的部分 | **不改**；stretch 缩放后完整可见 |
| 全仓 `gdscripts/` / `scenes/` | `grep DisplayServer/window_set_size/screen_get` → 仅 `city_glow.gd` 的 `TextureRect.STRETCH_SCALE` 一处，无任何窗口管理代码 | 无现存窗口逻辑冲突，新 autoload 无既有接线要兼容 |
| `mini-pong/gdscripts/ball.gd` L52 / `paddle.gd` L249 | `get_viewport()` 读 viewport 边界 | **零回归**：stretch `canvas_items` 下 `get_viewport().size` 仍返回逻辑 720×1280（Godot 4 语义），球/挡板边界计算不受物理窗口尺寸影响 |
| `mini-pong/tests/run_tests.gd` | `_run("res://tests/xxx.gd", ...)` 注册制；无 test_window_autofit | 需新增一行注册（implement 任务） |
| `scripts/run-e2e-review.sh` L243 | `--resolution 720x1280` 显式覆盖渲染尺寸 | **零回归**：headless 下 autofit 跳过，显式 resolution 仍生效 |

### PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计处置 |
|---------|-----------|---------|
| §5.2 边界 2「可用高 > 1280 → 等比放大窗口（如 810×1440 / 1440×2560）」 | **与 PRD 自身矛盾**：§3.4 数据流与 §8 交接上下文核心公式均为「目标高 = min(rect.h, 1280）」，且 §5.1 验收锚点 `1080 → (607,1080)` 只覆盖 ≤1280 场景 | **v1 采用 min 语义**（窗口上限 720×1280）：1440p/4K 下窗口 720×1280 仍满足 AC1（高 ≤ 可用高）与 AC2（9:16 严格）；1:1 渲染最清晰。「放大窗口」= light 深度显式非目标，如需另提 issue（§8 已注明） |
| §5.3 失败路径「DisplayServer 调用抛异常 → try/catch 回退」 | GDScript 4 **无 try/catch**；DisplayServer 原生调用不抛异常，失败以返回值/无操作呈现 | 前置校验 + `push_warning` 实现同等回退语义（§3.1 `_ready` guard 设计） |
| §3.1「WindowAutofit 置于 GameManager 之前，启动即适配」 | `[autoload]` 现顺序 GameManager → AudioEngine → UpgradePool；GameManager `_ready` 不读窗口/视口尺寸（源码核实） | 新增行置于 GameManager **之前**（PRD 指定）；顺序安全 |
| §1.1「测试套件 8 文件钉死 720×1280」 | `run_tests.gd` 实际注册 ~30 个测试文件，均断言逻辑常量/逻辑行为；无任何测试断言窗口物理尺寸 | 逻辑分辨率不动 → 全部既有测试零改动（§8.2 回归清单） |
| §3.1「抽出纯函数 compute_window_size(screen_rect) -> Vector2i」 | 无现存窗口代码 | 采纳；**追加** `compute_centered_position()` 纯函数使「居中」也可 headless 单测（§3.1、TC-W7） |

---

## 3. 新组件与既有组件修改

### 3.1 新文件 `mini-pong/gdscripts/window_autofit.gd` — WindowAutofit autoload（~50 行）

```gdscript
extends Node
## WindowAutofit — #544: 启动时按主屏可用区域等比缩放窗口并居中。
## 纯显示层：不改逻辑分辨率 720×1280（constants.gd + 全部测试钉死，#383 地基）。
## 设计: docs/DESIGN/544-window-display-autofit.md

const CONSTS = preload("res://gdscripts/constants.gd")
const LOGICAL_SIZE: Vector2i = Vector2i(CONSTS.SCREEN_WIDTH, CONSTS.SCREEN_HEIGHT)  # 720×1280

## headless/CI 守卫：无真实显示服务时静默跳过（E2E --resolution 720x1280 不受影响）。
## 双保险 1 — 显式 headless 名检查（PRD §8 风险 2 + §5.2 边界 5）。
static func _should_skip() -> bool:
	return DisplayServer.get_name() == "headless"

## 纯函数（可单测）：以可用高度为基准、保持 720:1280 等比计算窗口物理尺寸。
## 目标高 = min(可用高, 1280)（v1 上限，见 §2 gap 1）；目标宽 = floori(高 × 720/1280)。
## 1080p → (607,1080)；768 → (432,768)；1440 → (810,1440)；2160 → (1215,2160)。
## 双保险 2 — 无效矩形 (≤0) 回退默认 720×1280（PRD §5.3 失败路径 2）。
static func compute_window_size(screen_rect: Rect2i) -> Vector2i:
	if screen_rect.size.x <= 0 or screen_rect.size.y <= 0:
		return LOGICAL_SIZE
	var target_h: int = mini(screen_rect.size.y, CONSTS.SCREEN_HEIGHT)
	var target_w: int = floori(target_h * CONSTS.SCREEN_WIDTH / float(CONSTS.SCREEN_HEIGHT))
	return Vector2i(target_w, target_h)

## 纯函数（可单测）：窗口几何中心对齐可用区域中心（整除向下取整，亚像素误差不可见）。
static func compute_centered_position(usable: Rect2i, win: Vector2i) -> Vector2i:
	var x := usable.position.x + floori((usable.size.x - win.x) / 2.0)
	var y := usable.position.y + floori((usable.size.y - win.y) / 2.0)
	return Vector2i(x, y)

func _ready() -> void:
	if _should_skip():
		return
	var usable := DisplayServer.screen_get_usable_rect(0)   # 主屏（screen 0）可用区域，排除菜单栏/Dock/任务栏
	if usable.size.x <= 0 or usable.size.y <= 0:
		push_warning("WindowAutofit: 无有效屏幕可用区域 (%s)，回退默认窗口 720×1280" % usable)
		return
	var win := compute_window_size(usable)
	DisplayServer.window_set_size(win)
	DisplayServer.window_set_position(compute_centered_position(usable, win))
```

- **节点类型:** `Node`（autoload 单例，无场景文件，纯脚本注册）
- **信号:** 无（一次性启动适配，无需对外通信）
- **状态属性:** 无实例状态（全部逻辑在 static 纯函数 + `_ready` 一次性流程内）
- **关键方法:** `_should_skip()` / `compute_window_size()` / `compute_centered_position()` / `_ready()`（如上）
- **集成要点:** autoload `_ready` 先于 `Main.tscn` 加载 → 窗口尺寸在首帧渲染前就位，无「先 720×1280 再跳变」闪烁

> **为什么 static + CONSTS 引用可行：** GDScript 4 static 函数可访问类常量；`CONSTS.SCREEN_WIDTH/HEIGHT` 只读引用 constants.gd，
> 单一事实源（未来 #383 若改逻辑分辨率，本组件自动跟随，但 AC4 明确不变）。

### 3.2 `mini-pong/project.godot` — 修改（2 处）

**`[autoload]`（增 1 行，置于 GameManager 之前——PRD §6 准备清单 1）：**

```ini
[autoload]

WindowAutofit="*res://gdscripts/window_autofit.gd"   ; 🆕 #544 启动即适配窗口（置于 GameManager 之前）
GameManager="*res://gdscripts/game_manager.gd"
AudioEngine="*res://gdscripts/audio_engine.gd"
UpgradePool="*res://gdscripts/upgrade_pool.gd"
```

**`[display]`（增 2 键，viewport/resizable 逐字节不动——PRD §6 准备清单 2）：**

```ini
[display]

window/size/viewport_width=720
window/size/viewport_height=1280
window/size/resizable=false
window/stretch/mode="canvas_items"   ; 🆕 #544 内容按窗口等比缩放（而非裁切）
window/stretch/aspect="keep"         ; 🆕 #544 保持 9:16（≤1px 取整差由此吸收）
```

> 键名与 Godot 4.7 写法一致（`canvas_items` / `keep`）；implement 阶段以 `godot --path mini-pong/ --headless --quit` 实际校验（PRD §8 风险 2 兜底）。

### 3.3 新文件 `mini-pong/tests/test_window_autofit.gd` — 纯函数单测

- 结构沿用既有测试惯例：`extends RefCounted`、`run()` 入口、`_assert(cond, name)` 计数、TC 编号命名。
- 全部用例**静态调用** `load("res://gdscripts/window_autofit.gd")` 上的纯函数（不依赖 autoload 名称解析，headless 可跑）。
- 编号 **TC-W1 起**（避开既有 `test_*` 的 TC-A/B/C/D/E/F/H 前缀，526 先例）。
- 注册：`run_tests.gd` 增一行 `_run("res://tests/test_window_autofit.gd", "Window Autofit")`（implement 任务）。
- 具体用例描述见 §8.1；**不写可运行测试代码**（plan 阶段红线）。

### 3.4 文件变更总表

| 类别 | 文件 | 变更性质 | 内容 |
|------|------|:---:|------|
| 新文件 | `mini-pong/gdscripts/window_autofit.gd` | 新增 | autoload：`_should_skip` / `compute_window_size` / `compute_centered_position` / `_ready`（§3.1） |
| 新文件 | `mini-pong/tests/test_window_autofit.gd` | 新增 | 纯函数单测 TC-W1–W9（§8.1） |
| 修改 | `mini-pong/project.godot` | 修改 | `[autoload]` +1 行（WindowAutofit 置顶）；`[display]` +2 键（stretch canvas_items/keep） |
| 修改 | `mini-pong/tests/run_tests.gd` | 修改 | +1 行注册 `test_window_autofit.gd` |
| 删除/废弃 | 无 | — | — |
| 受影响既有测试 | 无（全量零改动） | — | AC4 回归 = headless 套件全绿（§8.2） |

---

## 4. 数据流

### Flow 1 — 正常路径：1080p 显示器启动（issue 主场景）
```
Godot 启动 → autoload 初始化（WindowAutofit 第一）
  → _ready()
      ├─ _should_skip() → false（非 headless）
      ├─ DisplayServer.screen_get_usable_rect(0) → Rect2i(0,0,1920,1080)   ← 排除 macOS 菜单栏/Dock
      ├─ compute_window_size(Rect2i(0,0,1920,1080))
      │     ├─ target_h = min(1080, 1280) = 1080
      │     └─ target_w = floori(1080 × 720/1280) = floori(607.5) = 607
      │     └─► Vector2i(607, 1080)
      ├─ DisplayServer.window_set_size(Vector2i(607,1080))      → 窗口物理尺寸适配显示器
      └─ DisplayServer.window_set_position(Vector2i(656, 0))    → 居中（(1920-607)/2=656）
  → Main.tscn 加载，渲染管线：逻辑 720×1280 → canvas_items+keep → 607×1080 物理窗口
  → 玩家挡板（逻辑 y 1250 → 物理 1054 < 1080）与底部 HUD 完整可见 ✓ AC1/AC2/AC3
```

### Flow 2 — headless / CI（E2E、`--headless --quit` 校验）
```
_ready() → _should_skip() → DisplayServer.get_name()=="headless" → true → return（零副作用）
  → 窗口保持 project.godot 默认 720×1280；run-e2e-review.sh 的 --resolution 720x1280 显式覆盖继续生效
  → headless 全量测试 / E2E L0–L3 与改动前逐字节一致 ✓ AC4
```

### Flow 3 — 无有效屏幕（异常/受限环境）
```
_ready() → _should_skip() → false
  → screen_get_usable_rect(0) → Rect2i(0,0,0,0)（或负尺寸）
  → 前置校验命中 → push_warning("WindowAutofit: 无有效屏幕可用区域…") + return
  → 窗口保持默认 720×1280，游戏照常运行（功能降级而非崩溃）✓ PRD §5.3 失败路径 2
```

---

## 5. 边界情况与错误处理

| # | 边界/错误场景 | 缓解 |
|---|--------------|------|
| 1 | **可用高 < 1280**（1080p / 768p 笔记本）→ 等比缩小窗口（607×1080 / 432×768），底部内容完整可见 | `compute_window_size` min + floori 等比（issue 主场景，TC-W1/W2/W6） |
| 2 | **可用高 > 1280**（1440p / 4K）→ **v1 不放大**：min 语义窗口 720×1280，1:1 渲染最清晰 | §2 gap 1 决策；AC1/AC2 仍满足（TC-W3/W4 锁定契约） |
| 3 | **系统 UI 遮挡**（macOS 菜单栏/Dock、Windows 任务栏）| 用 `screen_get_usable_rect()` 而非 `screen_get_size()`（PRD §5.2 边界 3） |
| 4 | **多显示器** | 固定主屏 `screen 0`（窗口初始所在屏）；light 不引入屏选择 UI/跟随鼠标屏（PRD §8 非目标） |
| 5 | **headless / CI**（无真实显示服务）| 双保险：`_should_skip()` 显式 headless 名检查 + 无效矩形回退（PRD §5.2 边界 5，TC-W8） |
| 6 | **极小屏 800×600** | 等比缩至 337×600，内容仍完整；light 不设最小尺寸下限（PRD §5.2 边界 6，TC-W6） |
| 7 | **`screen_get_usable_rect` 返回 (0,0,0,0) / 负尺寸** | 前置校验 → push_warning + 回退默认 720×1280，不阻塞启动（PRD §5.3 失败路径 2，TC-W5） |
| 8 | **WM 拒绝 set_size/set_position**（个别平台/窗口管理器）| Godot 保持默认窗口，游戏照常运行（功能降级而非崩溃；GDScript 4 无异常抛出，无需 try/catch——§2 gap 2） |
| 9 | **Retina / 高分屏（macOS 缩放）** | DisplayServer 平台抽象按逻辑点/物理像素自动处理，零额外代码 |
| 10 | **首帧闪烁**（先显示 720×1280 再跳变）| autoload `_ready` 先于 Main.tscn → 窗口尺寸在首帧渲染前就位，无可见跳变 |
| 11 | **逻辑分辨率回归** | constants.gd / 全部坐标 / 测试零改动；`get_viewport().size` 在 canvas_items 下仍返回 720×1280（ball/paddle 边界零回归） |
| 12 | **autoload 顺序依赖** | WindowAutofit 置 GameManager 前（PRD 指定）；GameManager `_ready` 不读窗口尺寸（源码核实），顺序安全 |

---

## 6. 集成点

> **状态约定：** ⬜ = 待 implement 接线；✅ = 已存在。implement agent 完成接线后更新本表。

| 集成 | 本组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| autoload 注册 | `window_autofit.gd` | `project.godot [autoload]` | 新增行置于 GameManager 之前 | ⬜ pending |
| stretch 渲染 | `project.godot [display]` | 渲染管线 | `window/stretch/mode="canvas_items"` + `aspect="keep"` | ⬜ pending |
| 屏幕查询 | `window_autofit.gd` | `DisplayServer.screen_get_usable_rect(0)` | Godot 4.7 平台 API（主屏可用区域） | ⬜ pending |
| 窗口尺寸/位置 | `window_autofit.gd` | `DisplayServer.window_set_size` / `window_set_position` | Godot 4.7 平台 API | ⬜ pending |
| 逻辑分辨率 | `window_autofit.gd` | `constants.gd` SCREEN_WIDTH/HEIGHT | `preload` 只读引用（单一事实源） | ✅ 既有 |
| 测试注册 | `tests/test_window_autofit.gd` | `tests/run_tests.gd` | 追加 `_run("res://tests/test_window_autofit.gd", "Window Autofit")` | ⬜ pending |

---

## 7. 实现阶段

| Phase | 优先级 | 内容 | 涉及文件 | 估计 |
|:-----:|:---:|------|---------|:---:|
| Phase 1 | P0 | `window_autofit.gd`：autoload + 双纯函数 + 双保险 guard | `gdscripts/window_autofit.gd` | 0.25 天 |
| Phase 2 | P0 | `project.godot`：`[autoload]` +1 行、`[display]` +2 键 | `project.godot` | 0.1 天 |
| Phase 3 | P0 | 测试：`test_window_autofit.gd`（TC-W1–W9）+ `run_tests.gd` 注册 | `tests/` 2 文件 | 0.25 天 |
| Phase 4 | P0 | 回归：headless 全量套件绿 + `run-e2e-review.sh` L0–L3 + 真机人工验证居中/可见 | — | 0.25 天 |

Phase 1/2/3 相互独立可并行；Phase 4 依赖前三者。合入红线：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿 + E2E L0–L3 通过。

---

## 8. 测试用例描述（仅描述，不写可运行测试代码）

> 验收映射：AC1–AC4（PRD §5.1）逐条对应；边界 1–12（§5）与失败路径（PRD §5.3）覆盖。
> 测试文件：`mini-pong/tests/test_window_autofit.gd`（extends RefCounted，`run()` 入口，静态调用纯函数，编号 TC-W 起）。
> 注意：`run_tests.gd` 需新增注册行，否则新测试不会被加载（implement 任务，遗漏会静默少测）。

### 8.1 `test_window_autofit.gd` — 纯函数单测（headless 可跑）

- **TC-W1（AC1 1080p 适配锚点）**：`compute_window_size(Rect2i(0,0,1920,1080)) == Vector2i(607,1080)`（PRD §5.1 锚点，floori 取整）。
- **TC-W2（AC2 等比全高度遍历）**：对可用高 768/900/1080/1440/2160 分别调用（矩形 `Rect2i(0,0,1920,h)`），断言：
  ① `result.y == h`（≤1280 时窗口高 = 可用高）；② `result.x == floori(h * 720 / 1280.0)`；
  ③ 宽高比误差 `abs(result.x / result.y - 720.0 / 1280.0) ≤ 1px`（具体锚点：768→432、900→506、1080→607、1440→810、2160→1215）。
- **TC-W3（v1 cap 语义——§2 gap 1 锁定）**：`compute_window_size(Rect2i(0,0,3840,2160)) == Vector2i(720,1280)`（4K 不放大）。
- **TC-W4（1440p cap）**：`compute_window_size(Rect2i(0,0,2560,1440)) == Vector2i(720,1280)`。
- **TC-W5（边界 7 / PRD §5.3 失败路径 2——无效矩形回退）**：`compute_window_size(Rect2i(0,0,0,0)) == Vector2i(720,1280)`；负尺寸 `Rect2i(0,0,-1,-1)` 同样回退；`Rect2i(100,50,0,800)`（宽 0）回退。
- **TC-W6（边界 6——极小屏）**：`compute_window_size(Rect2i(0,0,800,600)) == Vector2i(337,600)`（floori(337.5)）。
- **TC-W7（AC3 居中纯函数）**：`compute_centered_position(Rect2i(0,0,1920,1080), Vector2i(607,1080)) == Vector2i(656,0)`；非零原点 `Rect2i(100,50,1920,1080)` → `Vector2i(756,50)`；窗口等于可用区（720×1280 于 720×1280）→ `(0,0)`。
- **TC-W8（边界 5——headless 守卫）**：`_should_skip()` 在当前进程（headless 测试环境）返回 true；实例化 `load(...).new()` 并 `_ready()` → 不崩溃、无窗口副作用（headless 下任何 `window_set_*` 都不该发生——以 `_should_skip` 短路保证，测试断言跳过路径返回值即可）。
- **TC-W9（constants 引用完整性）**：`load("res://gdscripts/window_autofit.gd").LOGICAL_SIZE == Vector2i(720,1280)`（防未来 constants.gd 改动静默改变窗口契约；与 `test_constants.gd` TC6-2/3 呼应）。

### 8.2 回归确认（AC4 — 既有测试零改动）

- **headless 全量套件**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿——`ball.gd`/`paddle.gd` 的 `get_viewport().size` 在 stretch canvas_items 下仍为 720×1280（Godot 4 语义），既有 ~30 个测试文件逐字节零改动。
- **E2E**：`scripts/run-e2e-review.sh` L0–L3 通过——headless 下 autofit 跳过，`--resolution 720x1280` 显式覆盖继续生效，截图基线零漂移。
- **`project.godot` 合法性**：`godot --path mini-pong/ --headless --quit` 无解析错误（stretch 键名与 autoload 注册校验，PRD §6 准备清单 2）。

### 8.3 手动/视觉验证（非自动化，真机执行）

- 1080p 横屏显示器启动 → 窗口 607×1080 居中 → 玩家挡板（y≈1240）与底部 HUD 完整可见 → 可正常游玩（PRD §8 验收锚点）。
- 768p 笔记本 → 窗口 ~432×768 居中，内容完整。
- 1440p/4K → 窗口保持 720×1280（不放大，v1 契约）。
- macOS 上窗口不覆盖菜单栏/Dock（usable_rect 生效）；多显示器时窗口位于主屏居中。
- 游戏内操作回归抽查：发球/挡板移动/计分/波次升级均正常（显示层改动零逻辑接触）。

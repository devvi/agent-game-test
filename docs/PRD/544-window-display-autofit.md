# PRD #544 — [Feature] 游戏窗口大小根据显示设备初始化时自动调整

> **Issue:** #544
> **标签:** enhancement, workflow/available → workflow/research（2026-08-18 认领）
> **Agent:** game-research-agent
> **日期:** 2026-08-18
> **深度:** light（Issue body「工作深度: light（简单改动，快速完成）」；无 depth/ 标签，按 body 声明 light：Section 1–5 + 8 必填，Section 6 简述、Section 7 跳过并注明）
> **所有权:** `content_ownership: mechanical`（确定性窗口尺寸计算 = 纯几何/API 机械逻辑，无品味决策）
> **引擎/目录约束:** Godot 4.7.1 / `mini-pong/`（继承自 Issue body 与项目现状，Patch 19）
> **研究选项:** Obsidian 知识库未勾选（issue body 复选框为 `- [ ]`），且深度为 light → 不强制搜索设计笔记，按标准代码探查完成
> **来源:** 任务指派（game-research-agent）
> **前置依赖:** 无（`Depends on: #` 为空）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：`mini-pong/project.godot` 固定窗口尺寸 720×1280（竖屏，`resizable=false`），窗口物理尺寸 = viewport 逻辑尺寸。在高度 < 1280px 的显示器（如主流 1920×1080 横屏，可用高 1080）上，窗口底部被屏幕裁掉——玩家挡板位于 `y=1240`（`Main.tscn` PlayerPaddle position (360,1240)，挡板半高 10 → 底缘 1250）及底部 HUD 完全不可见。玩家无法操作挡板 = 无法游玩。**

| 文件 | 当前状态 | 与需求的差距 |
|------|---------|-------------|
| `mini-pong/project.godot` | `window/size/viewport_width=720`、`viewport_height=1280`、`resizable=false`（L26–28） | ❌ 窗口固定 720×1280，不随显示设备高度缩放；`[display]` 无 stretch 配置（默认不缩放内容） |
| `mini-pong/gdscripts/constants.gd` | `SCREEN_WIDTH=720 / SCREEN_HEIGHT=1280`（L15–16） | ✅ 逻辑分辨率常量，**不改**（#383 竖屏地基） |
| `mini-pong/scenes/Main.tscn` | PlayerPaddle position (360,1240)；ScoreZoneBottom 在底部 | ❌ 玩家挡板/底部得分区位于 1280 底部区域，屏幕裁切后不可见 |
| 全仓 `gdscripts/` | `grep DisplayServer/window_set_size/screen_get` → 仅 `city_glow.gd` 的 `stretch_mode` 一处，无任何窗口自适应代码 | ❌ 无现成窗口管理逻辑，需新建 |

**代码佐证（2026-08-18 实测扫描）：**
- `grep -rn "DisplayServer\|window_set_size\|screen_get" mini-pong/gdscripts/ mini-pong/scenes/` → 无命中（窗口从未被代码管理过）
- 测试套件（`test_constants.gd`、`test_main_scene.gd`、`test_ball.gd`、`auto_play_test.gd` 等 8 文件）全部钉死逻辑 720×1280 → **逻辑分辨率不可动**，方案只能在「窗口物理尺寸」层做文章

### 1.2 预期行为（验收条件，源自 Issue #544）

1. [ ] **AC1** 游戏启动时窗口高度 ≤ 显示器可用高度（等比缩放），玩家挡板（y≈1240）与底部 HUD 完整可见
2. [ ] **AC2** 窗口宽高比严格保持 720:1280 = 9:16（等比缩放，无拉伸变形）
3. [ ] **AC3** 窗口在显示器上居中显示
4. [ ] **AC4** 逻辑分辨率/游戏坐标系不变（仍 720×1280），`resizable=false` 不变；headless 测试与 E2E（`run-e2e-review.sh --resolution 720x1280`）全部通过

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 1080p 横屏显示器（1920×1080，最常见） | 每次启动 | 当前窗口高 1280 > 可用 1080，底部挡板被裁 → 完全无法游玩（issue 报告场景） |
| B | 高分辨率显示器（1440p / 4K） | 每次启动 | 窗口可等比放大，画面更清晰，无黑边 |
| C | 笔记本小屏（1366×768 等） | 每次启动 | 窗口缩到 ~432×768，内容完整可见 |
| D | 多显示器/主屏判定 | 每次启动 | 窗口应基于主屏（初始所在屏）可用区域缩放，避免落在副屏外 |

### 1.4 范围边界（与 #383 去冲突，Patch 14）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #383（轴交换 + 竖屏） | 坐标系改造、逻辑分辨率定为 720×1280、挡板/得分区重排 | ❌ 不改 `constants.gd` 逻辑分辨率、不改任何坐标/碰撞/测试 |
| #544（本 PRD） | 显示适配层：窗口物理尺寸随显示器可用高度等比缩放 + 居中 | — 只动 `[display]` 窗口配置 + 新增 autoload |

---

## 2. 设计意图

### 2.1 现状为何存在

| 约束 | 来源 | 说明 |
|------|------|------|
| 720×1280 固定竖屏 | #383（2026-08-13 轴交换+竖屏） | 竖屏改造时只定了逻辑分辨率，未考虑运行时显示设备差异；Godot 默认窗口尺寸 = viewport 尺寸 |
| `resizable=false` | #383 继承（早期横屏遗留） | 玩家无法手动拖拽缩放窗口，裁切问题无手动出路 |
| 无 stretch 配置 | 项目初始配置 | `[display]` 无 `window/stretch/mode`，窗口缩小会直接裁切内容而非缩放 |

### 2.2 为什么现在改

#544 报告玩家在 1080p 显示器上看不到玩家挡板——这不是体验瑕疵而是**核心可玩性阻断**（无法操作挡板 = 无法游玩）。修复是纯显示层机械改动，不动游戏逻辑，风险低、收益高，符合「light（简单改动，快速完成）」定位。

### 2.3 先前约束（继承）

| 约束 | 详情 |
|------|------|
| 逻辑分辨率 720×1280 不可变 | `constants.gd` + 8 个测试文件 + E2E 截图基线全部钉死 |
| `resizable=false` 保持 | 只做启动时自动适配，不做运行期手动缩放 |
| 引擎 API 面 | Godot 4.7.1 `DisplayServer`（4.0+ 稳定 API：`screen_get_usable_rect()` / `window_set_size()` / `window_set_position()`） |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/window_autofit.gd` | 新增 autoload | **新增**：`_ready()` 中读取可用屏幕区域 → 计算 9:16 窗口尺寸 → `window_set_size` + 居中；抽出纯函数 `compute_window_size(screen_rect: Rect2i) -> Vector2i` 供 headless 单测 |
| `mini-pong/project.godot` | `[autoload]` | **修改**：注册 `WindowAutofit="*res://gdscripts/window_autofit.gd"`（置于 GameManager 之前，启动即适配） |
| `mini-pong/project.godot` | `[display]` | **修改**：`window/stretch/mode="canvas_items"` + `window/stretch/aspect="keep"` — 保证窗口缩小/放大时内容按逻辑 720×1280 等比缩放而非裁切/变形 |
| `mini-pong/tests/test_window_autofit.gd` | 新增单测 | **新增**：纯函数测试（高度适配、9:16 宽高比保持、头less 回退） |

### 3.2 新文件

| 文件 | 用途 |
|------|------|
| `mini-pong/gdscripts/window_autofit.gd` | 窗口自适应 autoload（~60 行） |
| `mini-pong/tests/test_window_autofit.gd` | 纯数学单测（headless 可跑） |

### 3.3 间接影响

| 模块 | 影响 | 理由 |
|------|------|------|
| `constants.gd` / 全部坐标逻辑 / 8 个钉 1280 的测试 | ✅ 无影响 | 逻辑分辨率不变，stretch 层负责渲染缩放 |
| `scripts/run-e2e-review.sh`（L243 `--resolution 720x1280`） | ✅ 无影响 | headless 下 autofit 自动跳过（无真实屏幕），显式 `--resolution` 仍生效 |
| `Main.tscn` / `GameManager` / FSM / 计分 | ✅ 无影响 | 显示层改动，零逻辑接触 |

### 3.4 数据流

```
Godot 启动
    │
    ▼
WindowAutofit._ready()  (autoload，先于 Main.tscn)
    │
    ├── DisplayServer.screen_get_usable_rect(screen=0)   ← 排除 macOS 菜单栏/Dock、Windows 任务栏
    │       └──► 可用 Rect2i (x, y, w, h)
    │
    ├── compute_window_size(rect)  (纯函数，可单测)
    │       └──► 目标高 = min(rect.h, 1280)；目标宽 = round(目标高 × 9/16)（保持 720:1280）
    │
    ├── DisplayServer.window_set_size(Vector2i(w, h))
    │       └──► 窗口物理尺寸适配显示设备
    │
    └── DisplayServer.window_set_position(居中坐标)
            └──► 窗口居中于主屏

渲染管线: stretch/mode=canvas_items + aspect=keep
    逻辑 720×1280 画布 ──► 等比缩放到窗口物理尺寸 ──► 无裁切、无变形、无黑边
```

### 3.5 需更新的文档

- [ ] `docs/PRD/544-window-display-autofit.md`（本 PRD）
- [ ] （可选）`docs/` 设计笔记中窗口配置说明——plan/implement 阶段按实际落地补充

---

## 4. 方案对比

### Approach A: project.godot 静态窗口覆盖（`window/size/window_width_override` + `height_override`）

- **描述:** 在 `project.godot` 写死一个固定的窗口物理尺寸覆盖值（如 607×1080），完全不用代码。
- **Pros:** 零代码、零风险、无需测试
- **Cons:** 只适配单一显示器尺寸；换设备/换分辨率即失效；本质是把「适配」变成「另一个硬编码」
- **Risk:** 中（不满足「根据玩家显示器设备」的核心诉求，治标不治本）
- **Effort:** 极低（<0.1 人日）

### Approach B: 运行时 autoload 自适应 + stretch canvas_items（推荐）

- **描述:** 新增 `window_autofit.gd` autoload，启动时读取 `DisplayServer.screen_get_usable_rect()`（主屏可用区域，排除菜单栏/Dock/任务栏），以**显示器可用高度**为基准、保持 9:16 宽高比计算窗口尺寸，`window_set_size` + `window_set_position` 居中；同时 `project.godot` 开启 `stretch/mode=canvas_items` + `aspect=keep` 保证内容随窗口等比缩放。
- **Pros:** 真正「根据玩家显示器设备等比缩放」；跨平台统一 API；逻辑分辨率零改动（测试/E2E 全绿）；headless/CI 下自动跳过不破坏现有流水线
- **Cons:** 需 ~60 行新代码 + 单测；多屏场景需明确主屏策略（取 screen 0 即可，light 不引入屏选择 UI）
- **Risk:** 低（纯显示层机械逻辑；唯一风险点是 headless guard，已在方案内覆盖）
- **Effort:** 低（0.2–0.5 人日）

### Approach C: 仅开 stretch 模式、不改窗口尺寸

- **描述:** 只加 `stretch/mode=canvas_items` + `aspect=keep`，窗口仍 720×1280。
- **Pros:** 改动最小
- **Cons:** 窗口物理高度仍 1280 > 1080，屏幕裁切问题**原样存在**（stretch 只缩放内容到窗口，不缩放窗口本身）；aspect=keep 反而可能引入黑边
- **Risk:** 高（不解决 issue 报告的根因）
- **Effort:** 极低

### 推荐：Approach B

1. 唯一满足 AC1（窗口高度 ≤ 显示器可用高度）与 AC2（9:16 等比）的方案——A/C 均无法让 1280 高的窗口适配 1080 显示器
2. 逻辑分辨率零改动 → 8 个钉 1280 的测试、E2E 截图基线、`run-e2e-review.sh` 全部不受影响，回归面最小
3. 纯函数 `compute_window_size()` 可 headless 单测 → 符合项目「机械逻辑必须可测」惯例
4. 与 #383 边界清晰：本方案只动显示层（窗口 + stretch），不碰 #383 的任何坐标/逻辑

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1 窗口适配显示器可用高度** — 1080p 显示器启动：窗口高 = 1080（≤ 可用高），玩家挡板 y≈1240 完整可见
  - 验证：`compute_window_size(Rect2i(0,0,1920,1080)) == Vector2i(607,1080)`（9:16 取整）
- [x] **AC2 宽高比 9:16 严格保持** — 任意屏幕尺寸下 `w/h == 720/1280`（取整误差 ≤1px）
  - 验证：单测遍历 768/900/1080/1440/2160 高度，断言宽高比
- [x] **AC3 窗口居中** — `window_set_position` 使窗口几何中心对齐主屏可用区域中心
  - 验证：代码审查 + 真实渲染截图（非 headless）人工确认
- [x] **AC4 游戏逻辑零回归** — `constants.gd` 720×1280 不变；`resizable=false` 不变；headless 测试全绿；`run-e2e-review.sh` L0–L3 通过

### 5.2 边界情况

1. 屏幕可用高 < 1280（1080p / 768p 笔记本）→ 等比缩小窗口，底部内容完整可见（issue 主场景）
2. 屏幕可用高 > 1280（1440p / 4K）→ 等比放大窗口（如 810×1440 / 1440×2560），canvas_items 按窗口像素渲染，放大不糊
3. 主屏可用区域含菜单栏/Dock/任务栏（macOS/Windows）→ 用 `screen_get_usable_rect()` 而非 `screen_get_size()`，避免窗口仍被系统 UI 遮挡
4. 多显示器 → 启动窗口位于主屏（screen 0），以主屏可用区域为准；light 深度不引入屏选择逻辑
5. headless / CI（无真实显示服务）→ `screen_get_usable_rect()` 返回默认或异常，guard 后跳过缩放，保持 720×1280，流水线不受影响
6. 极小屏幕（如 800×600）→ 窗口缩至 ~337×600，仍完整可见；light 深度不设最小尺寸下限

### 5.3 失败路径

1. `DisplayServer` 调用抛异常（无显示服务/权限）→ try/catch 回退默认 720×1280 + `push_warning`，不阻塞启动
2. `screen_get_usable_rect()` 返回 `Rect2i(0,0,0,0)` → 视为无有效屏幕，回退默认尺寸
3. `window_set_size` 被窗口管理器拒绝（个别平台/WM）→ 保持 Godot 默认窗口，游戏照常运行（功能降级而非崩溃）

---

## 6. 依赖与阻塞（light 深度简述）

| 依赖 | 状态 | 风险 |
|------|------|------|
| Godot 4.7.1 `DisplayServer` API（4.0+ 稳定） | ✅ 可用 | 低 |
| #383 竖屏 720×1280 地基 | ✅ 已落地（2026-08-13） | 低——本 PRD 只在其上加显示适配层 |
| 外部三方库 / 插件 | ✅ 无 | — |

**依赖链：** `#383（竖屏逻辑分辨率地基）→ #544（窗口显示适配层）`——本 PRD 不改地基，只加「窗户」。

**准备清单：**
- [ ] 确认 `project.godot` `[autoload]` 注册顺序（WindowAutofit 置于 GameManager 之前）
- [ ] 确认 `window/stretch` 键名与 Godot 4.7 兼容写法（`canvas_items` / `keep`）

---

## 7. Spike / 实验

Skipped per 工作深度 light（Issue body 明确「简单改动，快速完成」；方案 B 为确定性机械逻辑，无不确定性需实验验证）。

---

## 8. 交接上下文（给 plan agent）

**系统状态：**
- 窗口从未被代码管理：`grep DisplayServer` 全仓无命中；窗口尺寸 = project.godot 硬编码 720×1280，`resizable=false`
- 逻辑分辨率 720×1280 是 #383 起的全项目地基（constants.gd + 8 个测试文件 + E2E 基线），**不可动**
- 玩家挡板位于 y=1240（Main.tscn PlayerPaddle (360,1240)），正是被 1080p 显示器裁掉的部分

**关键决策（本 PRD 已定，plan 直接执行）：**
- 方案：Approach B —— 新增 `window_autofit.gd` autoload + `project.godot` 开 stretch（`canvas_items` + `keep`）
- 核心 API：`DisplayServer.screen_get_usable_rect(0)` → `compute_window_size()` 纯函数 → `DisplayServer.window_set_size()` + `window_set_position()` 居中
- 头less guard：无有效屏幕时静默回退 720×1280（CI/E2E 必须保持全绿）

**plan 阶段任务（按序）：**
1. 新建 `mini-pong/gdscripts/window_autofit.gd`（autoload，含 `compute_window_size()` 纯函数）
2. 修改 `mini-pong/project.godot`：`[autoload]` 注册 + `[display]` stretch 两键
3. 新建 `mini-pong/tests/test_window_autofit.gd`（纯函数单测：1080p→(607,1080)、768/1440/2160 等比断言、异常回退）
4. 回归：headless 全测试 + `run-e2e-review.sh` L0–L3

**主要风险：**
- 多屏策略仅取主屏（screen 0）——如后续要「窗口跟随鼠标所在屏」属新需求，另行提 issue
- stretch 键名若与 Godot 4.7 写法有出入，以实际引擎校验为准（implement 阶段 `--headless --quit` 验证）

**验收锚点：** 1080p 显示器启动游戏 → 窗口 607×1080 居中 → 玩家挡板与底部 HUD 完整可见 → 游戏可正常游玩。

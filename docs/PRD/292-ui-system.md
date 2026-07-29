# PRD: [Feature] UI 系统 — 菜单/计分/结束

> **Issue:** #292
> **标签:** enhancement, workflow/research, depth/standard, priority/high, version/mvp, estimate/medium
> **Agent:** game-research-agent
> **日期:** 2026-07-30
> **前置依赖:** #301 (Scaffold — CLOSED ✅), #291 (Scoring — CLOSED ✅), #289 (Neon Visual — CLOSED ✅)

---

## 1. 问题定义

### 当前状态

Mini Pong 的游戏逻辑基础设施已完成（球物理 #287、计分 #291、GameManager autoload #293、霓虹视觉 #289），但**所有用户可感知的 UI 层完全缺失**。游戏启动后直接进入 gameplay，无开始画面、无分数显示、无结束画面——玩家不知道得分和胜负状态。

| 组件 | 状态 | 细节 |
|------|:----:|------|
| `scoring_manager.gd` | ✅ | 112 行：`scored`/`game_won`/`match_over` 信号已发射，**无消费者显示分数** |
| `game_manager.gd` | ✅ | 77 行 autoload：`score_changed`/`game_won`/`match_over` 信号，全局可访问分数 |
| `score_flash.gd` | ✅ | 48 行：`flash(color)` 方法存在，`_on_score_changed` 回调已定义（未连接），**仅做全屏闪烁** |
| `game.tscn` | ✅ | 含 Ball、PlayerPaddle、AIPaddle、ScoringManager，**无 CanvasLayer/UI 节点** |
| `ball_trail.gd` | ✅ | GPUParticles2D 拖尾，纯视觉效果 |
| 霓虹颜色约定 | ✅ | PRD #289：玩家蓝 #4a90d9、AI 红 #ff3355、背景 #0a0a12 |
| 开始画面 | ❌ | 不存在—游戏启动后立即进入 gameplay |
| HUD 分数显示 | ❌ | 不存在—得分后无可见反馈（仅 score_flash 全屏闪烁） |
| 结束画面 | ❌ | 不存在—比赛结束后游戏无任何 UI 变化 |
| CanvasLayer 结构 | ❌ | 不存在—无三层 UI 架构 |

**当前信号流（UI 完全未连接）：**

```
GameManager (autoload)
  ├── signal score_changed(player_score, ai_score) → 无人监听
  ├── signal game_won(winner)                      → 无人监听
  └── signal match_over(winner)                     → 无人监听

ScoringManager (game.tscn Node)
  ├── signal scored(winner)    → score_flash._on_score_changed（已注释连接代码）
  ├── signal game_won(winner)  → 无人监听
  └── signal match_over(winner) → 无人监听
```

### 预期行为

构建三层 CanvasLayer UI 系统，通过 `visible` 属性切换状态，连接游戏信号驱动 UI 更新：

1. **开始画面（StartMenu）：** 霓虹蓝 (#4a90d9) 发光标题 "Mini Pong"，下方闪烁提示 "按 SPACE 开始"，按 SPACE 后隐藏本层、显示 HUD 层、开始游戏
2. **游戏中 HUD（GameHUD）：** 顶部居中显示比分，格式 "`Player: {n}`" （蓝色 #4a90d9） + "`AI: {n}`" （红色 #ff3355），通过 `GameManager.score_changed` 信号驱动更新
3. **结束画面（GameOverScreen）：** 胜者大字（蓝色 "YOU WIN!" / 红色 "AI WINS!"），下方闪烁提示 "按 SPACE 重新开始"，按 SPACE 后调用 `GameManager.reset_match()` 回到开始画面
4. **三层切换：** 仅通过 `CanvasLayer.visible` 控制——同一时刻仅一层可见
5. **发光效果：** 标题和胜者文字通过 modulate alpha 动画（Tween `tween_property`）模拟霓虹发光脉冲——不做实际 ShaderMaterial
6. **编译验证：** `godot --path mini-pong/ --headless --quit` 无脚本错误
7. **1280×720 分辨率：** 所有 UI 元素在此分辨率下清晰可读、不截断、不溢出

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | **游戏启动：** 打开游戏 → 看到霓虹蓝发光标题 "Mini Pong" + 闪烁 "按 SPACE 开始" | 每次启动 1 次 |
| B | **全程查看分数：** 游戏中顶部持续显示当前比分，得分时分数立即更新（如 2→3） | 每一帧 |
| C | **得分确认：** 球出界后 → HUD 分数递增 + score_flash 全屏闪烁 → 1 秒后重新发球 | 每回合结束 |
| D | **比赛结束：** 一方先赢 2 局 → 看到巨大的 "YOU WIN!" 或 "AI WINS!" + "按 SPACE 重新开始" | 每场比赛 1 次 |
| E | **重新开始：** 结束画面按 SPACE → 回到开始画面 → 再按 SPACE 开始新比赛 | 每次重新开始 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 三个 CanvasLayer 场景（StartMenu, GameHUD, GameOverScreen） | 游戏状态机编排（#294） |
| `start_menu.gd` — 开始画面控制脚本 | 音效系统（#296） |
| `game_hud.gd` — HUD 分数显示脚本 | 玩家名称输入或配置 UI |
| `game_over_screen.gd` — 结束画面控制脚本 | 暂停菜单或设置菜单 |
| modulate alpha 动画模拟发光效果 | ShaderMaterial 发光（已在 #289 中处理球/球拍） |
| `GameManager.score_changed` 信号连接 | 计分逻辑修改（#291 已完成） |
| `GameManager.match_over` 信号连接 | GameManager 扩展（#293 已完成） |
| `--headless --quit` 编译验证 | 性能基准测试 |

### 范围边界 vs 重叠 PRD

| PRD | Covers | NOT covered（留给本 PRD） |
|-----|--------|--------------------------|
| #289 霓虹视觉 | 视觉效果：glow、粒子、颜色约定 | ❌ UI/HUD 文字显示 — #289 明确标注 "不包括 UI/HUD" |
| #291 计分系统 | 信号发射：`scored`/`game_won`/`match_over` | ❌ 信号的 UI 消费 — #291 明确标注 "不包括 UI 渲染（HUD 文字、结束画面 — #292）" |
| #293 GameManager | 全局状态：`score_changed` 信号、`reset_match()` API | ❌ UI 渲染 — #293 明确标注 "不包括 UI 渲染（#292）" |
| #301 项目骨架 | 目录结构、project.godot 配置 | ❌ 任何游戏逻辑或 UI |

**本 PRD 是 UI 系统的展示层**——它消费 #291/#293 的信号，使用 #289 约定的霓虹颜色，通过 CanvasLayer + modulate 动画完整的视觉呈现。

---

## 2. 设计意图

### 为什么是现在

Mini Pong 的游戏逻辑基础设施已就绪：#287（球物理）、#288（玩家球拍）、#290（AI 对手）、#291（计分）、#293（GameManager）、#289（霓虹视觉）。球员可以移动球拍、球可以碰撞反弹、计分信号正在发射——但玩家完全看不到任何 UI 反馈。UI 是玩家与游戏之间的唯一桥梁。没有 UI，游戏"看不见"——MVP 不可玩。

#292 是所有依赖信号（#291/#293）的 UI 消费层，必须排在计分和 GameManager 之后，但排在状态机（#294）和主场景组装（#295）之前——状态机需要 UI 层的 visible 状态来编排状态迁移，主场景需要 UI 层的 CanvasLayer 节点来组装 game.tscn。

### 为什么选择此方案

三层 CanvasLayer 是 Godot 4.x 的标准 UI 架构模式：每层独立渲染栈，互不干扰，通过 `visible` 一键切换。与单层动态 Add/Remove 子节点相比，CanvasLayer.visible 切换更快、更可预测、更容易与状态机集成。

霓虹发光效果用 modulate alpha 动画模拟而非 ShaderMaterial——原因：(1) 本 PRD 专注 UI 文字效果，#289 已用 ShaderMaterial 处理球/球拍的几何发光；(2) modulate 动画对 Label 节点更自然——Tween `.tween_property(label, "modulate:a", ...)` 让文字闪动/呼吸，代码量极少；(3) 避免了 CanvasLayer 内 Label 的 ShaderMaterial 与 2D UI 渲染器的兼容性问题。

### 设计原则

1. **信号驱动，零轮询：** HUD 不在 `_process()` 中轮询 `GameManager.player_score`——通过 `GameManager.score_changed.connect(hud._on_score_changed)` 信号驱动。结束画面通过 `GameManager.match_over.connect(game_over._on_match_over)` 触发。只有闪烁动画需要 `_process()` 控制帧级不透明度。
2. **三层互斥可见性：** 任何时刻只有一个 CanvasLayer.visible==true。切换逻辑由外部状态机（#294）或内联在开始/结束画面的 SPACE 按键处理中完成。
3. **复用 #289 霓虹颜色约定：** 玩家蓝 #4a90d9、AI 红 #ff3355——所有 UI 文字使用同一调色板，保持视觉一致性。
4. **1280×720 锚定：** 所有 Label 使用 anchor 定位（顶部居中、中央居中），不依赖绝对像素位置——确保分辨率变化时 UI 不偏移。
5. **headless-safe：** 所有脚本使用 `get_tree()` 守卫——headless 模式下 `get_tree()` 返回 null——await 和 Tween 创建前检查。

### 先前约束

| 约束 | 来源 | 细节 |
|------|------|------|
| 霓虹蓝/红颜色 | #289 PRD | 玩家 #4a90d9，AI #ff3355 — 严格遵循 |
| GameManager autoload | #293 PRD | `score_changed`/`game_won`/`match_over` 信号已定义，可全局访问 |
| scoring_manager 信号 | #291 PRD | `scored`/`game_won`/`match_over` — 场景级信号，与 GameManager 有重叠 |
| 2D Forward+ 渲染器 | #301 PRD | `mini-pong/project.godot` 已配置 |
| 1280×720 分辨率 | 用户指定 | 所有 UI 元素须在此分辨率下清晰可读 |
| CanvasLayer.visible 切换 | 用户指定 | 三层 UI 通过 visible 而非 add_child/remove_child 切换 |

---

## 3. 影响分析

### 直接影响的文件

| 文件 | 影响性质 |
|------|---------|
| `mini-pong/gdscripts/game_hud.gd` | **新建** — HUD 分数显示脚本 |
| `mini-pong/gdscripts/start_menu.gd` | **新建** — 开始画面控制脚本 |
| `mini-pong/gdscripts/game_over_screen.gd` | **新建** — 结束画面控制脚本 |
| `mini-pong/scenes/ui_start_menu.tscn` | **新建** — 开始画面场景（CanvasLayer + Label） |
| `mini-pong/scenes/ui_game_hud.tscn` | **新建** — HUD 场景（CanvasLayer + Label） |
| `mini-pong/scenes/ui_game_over.tscn` | **新建** — 结束画面场景（CanvasLayer + Label） |
| `mini-pong/scenes/game.tscn` | **修改** — 添加三个 CanvasLayer 子节点实例化 |
| `mini-pong/tests/test_ui_system.gd` | **新建** — UI 系统的 headless 编译测试 |

### 间接影响的文件

| 文件 | 影响性质 |
|------|---------|
| `mini-pong/gdscripts/score_flash.gd` | **轻微修改** — 注释掉 `_on_score_changed` 中的旧连接注释（#291 已标注 "to be wired by future scoring system issue"），改为实际连接到 GameManager 或保留给 #295 主场景组装 |
| `mini-pong/gdscripts/scoring_manager.gd` | **无修改** — 信号发射逻辑不变 |

### 数据流影响

```
GameManager.score_changed(player_score, ai_score)
    │
    ├──► game_hud.gd::_on_score_changed(ps, as)
    │       └──► Label.text = "Player: " + str(ps)         (蓝色 #4a90d9)
    │       └──► Label.text = "AI: " + str(as)             (红色 #ff3355)
    │
    └──► score_flash.gd::_on_score_changed(winner)         (已存在)
            └──► flash(blue|red) → ColorRect 0.2s 淡出

GameManager.match_over(winner)
    │
    ├──► game_over_screen.gd::_on_match_over(winner)
            └──► visible = true
            └──► Label.text = "YOU WIN!" | "AI WINS!"
            └──► start flashing "按 SPACE 重新开始"

StartMenu (SPACE press)
    │
    └──► start_menu.visible = false
         game_hud.visible = true
         触发 GameManager.reset_match() 或状态机开始游戏

GameOverScreen (SPACE press)
    │
    └──► game_over.visible = false
         start_menu.visible = true
         GameManager.reset_match()
```

### 需更新的文档

- [ ] `docs/DESIGN/292-ui-system.md` — 待 plan 阶段产出
- [ ] `GDD.md` — 如存在，补充 UI 系统章节

---

## 4. 方案比较

### 方案 A：三层 CanvasLayer + modulate 动画（推荐）

**描述：** 三个独立 CanvasLayer 子场景，每个含 Label 节点。发光效果通过 Tween 控制 Label.modulate.a 动画实现脉冲/闪烁。信号驱动：HUD 监听 `GameManager.score_changed`，结束画面监听 `GameManager.match_over`。

**Pros:**
- 符合用户明确指定的 "三层 UI 通过 CanvasLayer.visible 切换"
- CanvasLayer 独立渲染栈，无 Z-order 冲突
- modulate alpha 动画代码量极少（每个动画 5-10 行 Tween）
- 与 Godot 4.x UI 最佳实践一致
- 状态机集成简单——只需读写 3 个 CanvasLayer.visible
- 每层场景独立 `.tscn` 文件——可并行开发、独立测试

**Cons:**
- modulate 动画不如 ShaderMaterial 发光真实（但用户接受 "通过 modulate 透明度动画模拟"）
- 三个独立场景增加了文件数量（但组织清晰）
- 需要在 `game.tscn` 中手动添加三个实例化节点（或通过 #295 组装）

**Risk:** Low — CanvasLayer 是 Godot 核心类，稳定可靠。modulate 动画无性能风险（3 个 Label 节点，总 draw calls < 10）。

**Effort:** 2-3 小时 — 三个脚本各 30-50 行，三个场景模板级简单，信号连接 3 行。

---

### 方案 B：单一 CanvasLayer + Control 容器切换

**描述：** 一个 CanvasLayer 包含三个 Control 容器（StartMenu/GameHUD/GameOverScreen），通过切换容器的 visibility 而非 CanvasLayer.visible 来控制。

**Pros:**
- 单一 `.tscn` 文件，减少场景数量
- 所有 UI 在一个渲染栈上，切换可靠性最高
- 不需要跨场景信号连接

**Cons:**
- 不符合用户明确指定的 "三层 UI 通过 CanvasLayer.visible 切换"——本方案通过 Control.visible 切换
- 单一场景臃肿——三个 UI 层挤在一个 .tscn 中，合并冲突风险增加
- 状态机需要知道 Control 节点路径而非 CanvasLayer 节点路径——与未来 #294 的约定不一致
- Z-order 管理需手动维护——若添加更多 UI 层（如暂停菜单），排序易出错

**Risk:** Low — 技术可行，但与规格不符。

**Effort:** 2 小时 — 可借助单一场景模板。

---

### 方案 C：Theme 驱动 + 九宫格 UI 系统

**描述：** 定义 Godot Theme 资源——统一字体、颜色、样式。创建 `ui_system.gd` autoload 管理 UI 生命周期、动画、按键处理。开始/结束画面通过 Theme 资源动态生成 Label，而非静态场景。

**Pros:**
- Theme 驱动——修改视觉风格只需改一个 Theme 资源
- 可扩展——添加新 UI 元素（暂停菜单、设置面板）无需新增场景

**Cons:**
- **过度工程** — Mini Pong 仅有 3 个静态 UI 层，Theme 资源的创建和维护成本远超收益
- 需要额外的 autoload（`ui_system.gd`）——增加 project.godot 的 autoload 列表
- 与 Godot 4.x 的 Theme 系统存在兼容性陷阱——CanvasLayer 内 Theme 继承链不直观
- 动态生成 UI vs. 静态场景——调试 UI 布局更困难（无编辑器预览）
- 不符合用户简洁的 "三层 CanvasLayer" 指定

**Risk:** Medium — Godot Theme 系统复杂，CanvasLayer + Theme 组合在 4.x 中存在已知边缘情况。

**Effort:** 5-6 小时 — Theme 资源设计、autoload 脚本、动态生成逻辑。

---

### 推荐：方案 A

| 理由 | 说明 |
|------|------|
| **与规格完全一致** | 用户明确指定 "三层 CanvasLayer.visible 切换"，方案 A 精确匹配 |
| **与现有架构一致** | 各 PRD（#291/#293/#289）均采用独立场景文件组织——方案 A 延续此模式 |
| **状态机兼容** | #294 状态机仅需读写 3 个 CanvasLayer 节点的 visible 属性 |
| **代码量最小** | 3 个脚本合计 ~120 行，无基础设施层 |
| **可验证性最高** | 每层可独立 headless 编译测试 |

---

## 5. 边界条件与验收标准

### 验收清单

- [ ] **AC1：开始画面有霓虹蓝发光标题和闪烁提示**
  - "Mini Pong" 标题 Label 颜色为 #4a90d9
  - 标题有 modulate.a 脉冲动画（如 0.6 ↔ 1.0，周期 1.5s）
  - "按 SPACE 开始" 提示闪烁（如 modulate.a 0.0 ↔ 1.0，周期 0.8s）
  - 按 SPACE 后开始画面消失

- [ ] **AC2：HUD 顶部分数用对应霓虹色**
  - 分数在 1280×720 画面上方显示（如 anchor top, y offset 20px）
  - 玩家分数用蓝色 #4a90d9，AI 分数用红色 #ff3355
  - 通过 `GameManager.score_changed` 信号更新（非 `_process` 轮询）
  - 初始显示 "Player: 0 AI: 0"

- [ ] **AC3：结束画面有胜者大字**
  - 胜者显示为 "YOU WIN!"（玩家胜，蓝色 #4a90d9）或 "AI WINS!"（AI 胜，红色 #ff3355）
  - 胜者文字有 pulse 动画
  - "按 SPACE 重新开始" 闪烁提示可见
  - 按 SPACE 后调用 `GameManager.reset_match()` 并回到开始画面

- [ ] **AC4：三层 UI 通过 CanvasLayer.visible 切换**
  - 初始状态：StartMenu.visible=true, GameHUD.visible=false, GameOverScreen.visible=false
  - SPACE 开始：StartMenu.visible=false, GameHUD.visible=true
  - 比赛结束：GameHUD.visible=false, GameOverScreen.visible=true
  - SPACE 重新开始：GameOverScreen.visible=false, StartMenu.visible=true

- [ ] **AC5：1280×720 分辨率可读**
  - 所有 Label 使用 anchor 定位，字体大小 ≥ 24px
  - 无元素截断或溢出画布
  - 不同分辨率（如 1920×1080）缩放后仍可读

- [ ] **AC6：--headless --quit 无脚本错误**
  - `godot --path mini-pong/ --headless --quit` 退出码为 0
  - 所有脚本编译通过
  - `get_tree()` 守卫避免 headless 空指针

### 边界条件

1. **headless 模式：** `get_tree()` 返回 null 时，所有 `await`、`create_tween()` 调用被跳过——脚本静默降级，不 crash
2. **GameManager 未注册：** 若 autoload 注册失败（#293 回退），`_ready()` 中 `is_instance_valid(GameManager)` 检查为空时——Label 显示初始分数 "0"，不 crash
3. **初始状态：** 首次加载时 score 信号尚未发射——HUD 的 Label 直接读取 `GameManager.player_score`/`ai_score`，初始均为 0
4. **快速 SPACE 连按：** 开始/结束画面须防抖动——`_on_space_pressed` 入口处检查 `_transitioning` bool，防止连续触发切换
5. **信号在 visible=false 时发射：** HUD 在 invisible 状态下收到 `score_changed`——仍更新内部 Label.text，但不可见（无副作用，切换回来时显示正确分数）
6. **字体缺失回退：** 若指定字体不可用——Godot 自动回退到系统默认字体（`system_font`），UI 仍可显示（美观度下降但功能不损）
7. **CanvasLayer 层级：** 三层 CanvasLayer 的顺序在 `game.tscn` 中固定——不依赖动态 Z-index

### 失败路径

1. **信号连接失败：** `GameManager.score_changed.connect()` 在 GameManager 未就绪时抛出错误 → `_ready()` 中用 `is_instance_valid()` + try/catch 守卫
2. **CanvasLayer 未实例化：** `game.tscn` 中缺少 UI 子场景 → Label 引用为 null → `_ready()` 中检查后静默退出
3. **Tween 冲突：** 同一 Label 已有运行时 Tween → 新 Tween 调用 `tween.kill()` 再创建——防止复数动画叠加

---

## 6. 依赖与阻塞项

### 依赖项

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|------|------|
| #301 项目骨架 | ✅ CLOSED | None | `mini-pong/project.godot`、Forward+ 渲染器、目录结构已就绪 |
| #291 计分系统 | ✅ CLOSED | None | `ScoringManager` 的 `scored`/`game_won`/`match_over` 信号已发射 |
| #293 GameManager | ✅ CLOSED | None | autoload 已注册，`score_changed`/`match_over` 信号、`reset_match()` API 可用 |
| #289 霓虹视觉 | ✅ CLOSED | None | 颜色约定 #4a90d9/#ff3355 已确立，可直接引用 |

### 被依赖项（此 PRD 阻塞）

| 未来工作 | 优先级 | 阻塞点 |
|----------|--------|--------|
| #294 状态机 | High | 状态机需要 UI 层的 CanvasLayer.visible 属性来定义状态迁移（menu→playing→game_over） |
| #295 主场景组装 | High | 组装脚本需要实例化 UI 层的三个 CanvasLayer 子场景 |
| #296 音效系统 | Low | 不直接阻塞——音效可独立开发 |

### 依赖链

```
#301 Scaffold ✅
    │
    ├──► #287 球物理 ✅
    │       └──► #291 计分系统 ✅ → #293 GameManager ✅
    │                                       │
    ├──► #289 霓虹视觉 ✅                  │
    │       │                               │
    │       └───────────────────────────────┤
    │                                       │
    └──► #292 UI 系统 ◄─────────────────────┘  ← 本 Issue
              │
              ├──► #294 状态机
              ├──► #295 主场景组装
              └──► #296 音效
```

### 准备清单

- [x] #301 Scaffold 完成——目录结构存在
- [x] #291 ScoringManager 完成——信号发射正常
- [x] #293 GameManager autoload 完成——全局状态可访问
- [x] #289 霓虹视觉完成——颜色约定已确立
- [ ] 字体选择（可选）— 若不指定，Godot 使用系统默认字体

---

## 7. Spike / 实验

**Skipped per depth/standard label.** (Section 7 仅在 depth/deep 时为必需。Mini Pong UI 系统使用 Godot 核心 CanvasLayer + Label 组件，无技术不确定性。modulate 动画和信号连接均为 Godot 基础功能，无需 Spike 验证。)

---

## 8. 续接上下文

### 系统状态

本 PRD 完成时，Mini Pong 将首次拥有完整可感知的 UI 层：
- 三个 CanvasLayer 场景（StartMenu、GameHUD、GameOverScreen）及其 GDScript 控制器
- HUD 连接 `GameManager.score_changed` 信号以显示实时分数
- 开始/结束画面处理 SPACE 按键进行状态切换
- `game.tscn` 已添加三个 CanvasLayer 实例化节点

### 主要风险

| 风险 | 缓解措施 |
|------|---------|
| #294 状态机实现 #292 后改变了 UI 切换逻辑 | #292 脚本中设计 `transition_to(layer_name)` 方法，使 #294 可以覆写切换逻辑而无需修改 UI 场景结构 |
| GameManager 信号在 UI ready 之前发射 | HUD 在 `_ready()` 中主动读取 `GameManager.player_score`/`ai_score` 作为初始值 |
| headless 模式 Tween 创建失败 | 所有 `create_tween()` 调用前检查 `get_tree()` 非 null |

### 下一步（Plan Agent 续接）

1. **产出 DESIGN doc：** `docs/DESIGN/292-ui-system.md`，包含三个脚本的完整 API 规格（信号处理器签名、导出变量、Tween 动画参数）
2. **定义字体与字号：** 设计文档中确定字体（默认或自定义）、标题字号、HUD 字号、提示文字号——确保 AC5（1280×720 可读）
3. **协调与 #294 的互操作：** 设计文档中定义 UI 层与状态机的接口——UI 提供 `set_layer_visible(layer_name, bool)` API 供状态机调用
4. **协调与 #295 的组装：** 设计文档中注明 CanvasLayer 子场景需在 `game.tscn` 中按顺序实例化
5. **文件清单（Plan Agent 将编译）：**
   - `mini-pong/scenes/ui_start_menu.tscn` + `mini-pong/gdscripts/start_menu.gd`
   - `mini-pong/scenes/ui_game_hud.tscn` + `mini-pong/gdscripts/game_hud.gd`
   - `mini-pong/scenes/ui_game_over.tscn` + `mini-pong/gdscripts/game_over_screen.gd`
   - `mini-pong/scenes/game.tscn`（修改：添加三个 CanvasLayer 实例）
   - `mini-pong/tests/test_ui_system.gd`（headless 编译验证）

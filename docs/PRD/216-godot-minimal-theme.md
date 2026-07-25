# Research: 集成 godot-minimal-theme UI 主题

> Parent Issue: #216
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

项目目前**没有统一的中枢 UI 主题系统**。所有 UI 元素的样式以零散的 `theme_override_*` 形式定义在各个场景文件中：

| 场景文件 | 当前样式方式 | 当前颜色 |
|---------|-------------|---------|
| `scenes/title_screen.tscn` | 空 Theme 子资源 + 逐节点 theme_override | 浅蓝色文字 (#cccfff 系列) 在深色背景 (#0d0d14) 上 |
| `scenes/dialogue/dialogue_panel.tscn` | StyleBoxFlat 子资源 + theme_override | 半透明黑底 (#000 0.6α) + 白色文字 |
| `scenes/dialogue/dialogue_balloon.tscn` | StyleBoxFlat 子资源 + theme_override | 深灰底 (#1a1a1a 0.9α) + 暖棕文字 (#947038/#d4a66b) |
| `scenes/ui/status_bar.tscn` | ColorRect + theme_override | 琥珀 (#FFB000) + 暗蓝 (#2A2A4A) |
| `scenes/dialogue/response_panel.tscn` | 无主题覆盖 | 默认 Control 样式 |

**核心问题：**

1. **无复用性** — 每个场景独立定义 StyleBoxFlat、颜色、字体等，修改一套颜色方案需要手动改动 5+ 个文件
2. **风格不一致** — 标题屏用浅蓝冷色系、对话用暖棕、状态栏用琥珀/暗蓝——三个子系统使用完全不同的色板
3. **无主题资源** — 没有 `.tres` Theme 文件或 `Theme` 类型资源的集中定义。`title_screen.tscn` 虽有一个空 Theme 子资源（`Theme_4a6q1`），但其内部无任何颜色/样式定义
4. **难以维护** — 新增 UI 组件时，开发者必须手动复制现有颜色值而非引用主题变量；未来调整色板需要 grep 搜索所有 `.tscn` 文件

### Expected Behavior

集成 `godot-minimal-theme` (passivestar/godot-minimal-theme, 3781⭐) 的设计理念，但注意：

> **⚠️ 重要发现：** `godot-minimal-theme` 的 `minimal_theme.tres` 是 **Godot 编辑器主题**，使用 `EditorSettings` / `EditorInterface` API。它无法直接用于游戏运行时 UI。自 Godot 4.6 起该主题已作为默认编辑器主题原生集成，因此**项目的编辑器端不需要额外安装**。

本项目需要的是**运行时自定义 Theme 资源**，借鉴 `godot-minimal-theme` 的设计语言（扁平、极简、低对比度边框、圆角控制），并应用项目自定义的霓虹配色方案：

1. 集中式 `Theme` 资源文件（`.tres`），统一管理所有 UI 组件的颜色、StyleBox、字体
2. 配色方案：暗色底 (#0a0a12) + 霓虹蓝 (#4a90d9) + 霓虹红 (#ff3355)
3. 所有内置 UI 组件（Panel、Button、Label、RichTextLabel、ScrollBar 等）使用主题颜色
4. 自定义 UI 组件（对话气泡、状态栏）通过主题常量引用颜色
5. Godot 4.7.1 `--headless --quit` 无加载错误

### User Scenarios

- **Scenario A（开发-新增界面）：** 开发者新建一个 OptionButton 控件，不需要手动设置颜色——Theme 资源自动提供一致的 StyleBox、字体颜色和悬停/按下状态样式。频率：每次 UI 开发。
- **Scenario B（设计-调整色板）：** 产品决定将霓虹蓝从 #4a90d9 调整为 #3a80c9——只需要修改 Theme 资源中的一个颜色常量，所有引用该颜色的 UI 组件自动更新。频率：设计迭代期间多次。
- **Scenario C（验证-样式一致性）：** QA 遍历所有 UI 场景，确认 Button、Panel、Label 等控件在标题屏、对话面板、状态栏中使用一致的视觉风格。频率：集成测试阶段。

---

## 2. Design Intent

### 为什么当前没有统一主题？

项目按功能子系统逐 Issue 开发（#42 对话引擎 → #44 Lo-Fi 3D 文字 → #45 叙事架构 → #47 GameState → #52 对话运行时 → #53 UI 系统 → #142 玩家控制器），每个子系统独立实现其 UI 样式：

1. **标题屏（Issue #147）** — 最早实现的 UI 场景，使用了最简单的 theme_override 方式
2. **对话气泡（Issues #46/#52）** — 使用 `dialogue_manager` 插件的示例气泡风格（暖棕色调），后续自定义了颜色但未抽象为主题
3. **状态栏（Issue #53）** — 设计了独特的 Hopper 风格琥珀/暗蓝配色，与对话面板不共享色板
4. **对话面板（Issue #52）** — 使用最简单的半透明黑底 + 白字，与对话气泡风格不统一

### 为什么现在改？

1. **项目接近 MVP 集成阶段** — 已有 22+ 场景文件和 50+ GDScript 文件，UI 组件数量增长后统一风格的成本越来越高
2. **版本/mvp 验收要求** — AC 明确要求"所有内置 UI 组件正常显示"和"自定义 UI 使用主题颜色"
3. **配色方案已确定** — Issue #216 明确指定了暗色底 + 霓虹蓝 + 霓虹红的色彩体系
4. **后续开发依赖** — 玩家控制器 #142、NPC 交互 #152、场景过渡 #156 等都会引入新的 UI 组件，统一主题可减少每个新组件的样式开发工作
5. **Godot 4.7.1 主题系统成熟** — 从 Godot 4.6 起 `godot-minimal-theme` 的设计语言已原生集成，Theme 资源的性能开销为零（编译期预加载）

### Previous Constraints

| 约束 | 内容 |
|------|------|
| 引擎 | Godot 4.7.1 / GDScript 2.0 |
| 渲染器 | `forward_plus`，已启用 Glow（后处理辉光） |
| UI 系统 | 已存在的 StatusBar、DialoguePanel、DialogueBalloon、TitleScreen、ResponsePanel |
| 字体资源 | 位图字体 `assets/fonts/pixel_font.tres` (.fnt + .png) |
| 已有 addon | `addons/dialogue_manager/`（对话管理器插件，版本 v3.10.x） |
| 已有配色 | Hopper 风格：暖琥珀 (#FFB000) / 暗蓝 (#2A2A4A) / 深色半透明背景 |
| 平台 | macOS / Linux |
| 子项目 | `rainy-night-prometheus/` — 与主项目使用相同的 symlink 脚本（#213 已完成） |
| 目标版本 | MVP — 不追求高视觉保真度，但需风格一致 |

---

## 3. Impact Analysis

### Directly Affected Modules

| 文件 | 模块 | 变更性质 |
|------|------|----------|
| `assets/themes/neon_theme.tres`（新建） | 主 Theme 资源 | **新建** — 集中定义的 Theme 文件，包含 Panel/Label/Button/RichTextLabel 等控件的颜色、StyleBox、字体设置 |
| `scenes/title_screen.tscn` | 标题屏 | **修改** — 移除空 Theme 子资源和逐节点 theme_override，改为引用全局 Theme |
| `scenes/dialogue/dialogue_panel.tscn` | 对话面板 | **修改** — 将 theme_override 改为通过主题常量引用 |
| `scenes/dialogue/dialogue_balloon.tscn` | 对话气泡 | **修改** — 将暖棕色调覆盖为霓虹主题色，子资源 StyleBox 调整颜色 |
| `scenes/dialogue/response_panel.tscn` | 响应面板 | **修改** — 添加主题样式引用 |
| `scenes/ui/status_bar.tscn` | 状态栏 | **参考** — 状态栏保持独立配色（Hopper 风格），不做重大改动，但确保不冲突 |
| `addons/dialogue_manager/` | 对话管理器插件 | **参考** — 检查插件内置 theme_override，必要时覆盖 |

### New Files Needed

| 文件 | 用途 |
|------|------|
| `assets/themes/neon_theme.tres` | 运行时自定义 Theme 资源，包含完整的颜色/StyleBox/字体定义 |
| `docs/PRD/216-godot-minimal-theme.md` | **本次产出——本文档** |

### Indirectly Affected Modules

| 文件 | 模块 | 关联原因 |
|------|------|----------|
| `gdscripts/dialogue_balloon.gd` | 对话气泡脚本 | 可能需要在 `_ready()` 中处理 Theme 加载后的颜色同步 |
| `gdscripts/dialogue_runner.gd` | 对话运行时 | 可能涉及 Dynamic 颜色切换（如根据状态改变字体颜色） |
| `gdscripts/response_button.gd` | 响应按钮脚本 | 按钮的离散/悬停/按下状态已通过 theme_override 控制，Theme 统一后需确认代码逻辑兼容 |
| `rainy-night-prometheus/scenes/` | 子项目场景 | 如果子项目有独立 UI 场景，需同步添加 Theme 引用 |
| `docs/GAME_DESIGN/03-GODOT-SETUP.md` | GDD | 应补充 Theme 系统的架构说明和引用路径 |

### Data Flow Impact

```
project.godot (Theme 预加载)
    │
    ├─── assets/themes/neon_theme.tres
    │        │
    │        ├─── Font colors → Label, RichTextLabel, Button, LinkButton
    │        ├─── StyleBoxes → Panel, Button, LineEdit, ScrollBar, CheckBox
    │        ├─── Constants   → custom colors via theme.get_color("neon_blue", "Custom")
    │        └─── Fonts       → pixel_font.tres 作为默认字体
    │
    ├─── scenes/title_screen.tscn
    │        └─── VBoxContainer.theme = preload("res://assets/themes/neon_theme.tres")
    │
    ├─── scenes/dialogue/dialogue_panel.tscn
    │        └─── Panel (自动继承根 Theme 或显式设置)
    │
    ├─── scenes/dialogue/dialogue_balloon.tscn
    │        └─── CanvasLayer.Balloon (自动继承)
    │
    └─── scenes/ui/status_bar.tscn
             └─── CanvasLayer (保持独立，但 Label 字体使用主题字体)
```

> Theme 资源在 Godot 中通过 **引用链** 传递：子节点默认继承父节点的 Theme。只需要设置根场景（title_screen.tscn 的根 VBoxContainer、main.tscn 的 CanvasLayer）的 theme 属性，所有后代 Control 节点自动继承。

### Documents to Update

- [x] **本次产出:** `docs/PRD/216-godot-minimal-theme.md`
- [ ] `docs/DESIGN/216-godot-minimal-theme.md` — Plan 阶段输出
- [ ] `docs/GAME_DESIGN/03-GODOT-SETUP.md` — 补充 Theme 系统说明

---

## 4. Solution Comparison

### Approach A: 单一集中式 Theme .tres 资源 + 逐场景显式引用

**Description:**

创建一个独立的 `assets/themes/neon_theme.tres` 文件，使用 Godot 的 Theme 资源系统完整定义：
- 所有 Control 类型节点的颜色（`font_color`、`font_color_hover`、`font_color_pressed`、`font_color_disabled`）
- StyleBox 样式（`panel`、`normal`、`hover`、`pressed`、`disabled`、`focus`）
- 字体大小和字体资源引用
- 间距常量（`separation`、`margin_*`）

然后在每个需要主题的 UI 场景的根节点上显式设置 `theme = preload(...)`。

**Theme 颜色配置：**

```gdscript
# assets/themes/neon_theme.tres — 颜色常量设计
# 暗色底: #0a0a12
# 霓虹蓝: #4a90d9
# 霓虹红: #ff3355
# 辅助色系:
#   — 深灰面: #1a1a2e (面板背景)
#   — 浅灰面: #2a2a3e (按钮/输入框背景)
#   — 白色文字: #d0d0e0 (主文字)
#   — 灰色文字: #808098 (次要/禁用文字)
```

**Pros:**
- **Godot 标准做法** — Theme 资源是 Godot 的原生 UI 主题系统，性能零开销（编译时加载为二进制）
- **单点维护** — 修改一个 `.tres` 文件的颜色值即可更新全局 UI
- **类型安全** — 通过 `theme.get_color("neon_blue", "Custom")` 可在 GDScript 中访问主题常量
- **渐进式迁移** — 可以逐个场景迁移，不需要一次性改动所有场景
- **完全控制** — 不依赖任何外部 addon，项目独立
- **子项目兼容** — `rainy-night-prometheus/` 可以通过 symlink 直接引用同路径 Theme 资源

**Cons:**
- **初始配置量大** — Theme 资源需要为所有使用的控件类型配置颜色/StyleBox（15-20 个配置项）
- **手动引用** — 每个场景需要显式设置 theme 引用，新场景容易遗漏
- **已存在的 theme_override 冲突** — 现有 `theme_override_*` 优先级高于 Theme 资源，需要逐个清理

**Risk:** Low — 标准的 Godot 主题工作流，已在无数项目中使用
**Effort:** 1 个 Theme .tres 文件（~100 行） + 5 个场景修改

---

### Approach B: 使用 Theme 预加载（project.godot）+ 全局默认主题

**Description:**

在 `project.godot` 的 `[gui]` 部分设置 `theme = res://assets/themes/neon_theme.tres`，使该主题成为全局默认主题。所有未显式设置 theme 的 Control 节点自动使用该主题。

**Pros:**
- **零引用工作** — 不需要在每个场景手动设置 `theme` 属性
- **一致性保障** — 新增任何 UI 场景自动获得正确样式
- **覆盖方便** — 需要不同风格的场景可以通过局部 theme_override 覆盖

**Cons:**
- **全局覆盖可能产生意外** — 如果 `addons/dialogue_manager/` 内部的 UI 组件被意外应用游戏主题，可能导致视觉异常
- **`project.godot` 的 `[gui]` 主题配置在 Godot 4.x 中不如 Theme 资源成熟** — 需要验证在 Godot 4.7.1 中该配置方式是否可用
- **`theme_override_*` 优先—** 现有场景中的 theme_override 不受影响，但新场景如果不正确使用 tema，可能出现颜色缺失
- **回滚/切换困难** — 全局默认主题需要修改 project.godot 才能切换

**Risk:** Medium — 全局主题可能影响 addon UI，需谨慎测试
**Effort:** 1 个 Theme .tres + `project.godot` 单行配置

---

### Approach C: GDScript 驱动的 ThemeBuilder 系统（运行时生成 Theme）

**Description:**

创建一个 `gdscripts/theme_builder.gd` 自动加载脚本，在 `_ready()` 中通过代码创建 `Theme` 对象，动态设置各控件的颜色和 StyleBox。不依赖静态 `.tres` 文件。

```gdscript
# theme_builder.gd — 运行时主题构建器
func _ready() -> void:
    var theme = Theme.new()
    theme.set_color("font_color", "Label", Color("#d0d0e0"))
    theme.set_color("font_color", "Button", Color("#4a90d9"))
    theme.set_stylebox("normal", "Button", _create_neon_stylebox())
    get_tree().root.add_theme_override(theme)
```

**Pros:**
- **最大灵活性** — 颜色可以在代码中计算（如支持运行时色温调整、暗色模式切换）
- **无需 .tres 文件** — Theme 完全由代码生成，适合运行时可定制的场景
- **避免 .tres 导入问题** — 不依赖 Godot 的资源导入流程

**Cons:**
- **失去编辑器可视化反馈** — 颜色值和样式在编辑器中不可见，必须运行游戏才能看到效果
- **代码维护成本高** — 创建 StyleBox、设置各控件类型的 30+ 个属性使代码变长
- **非标准做法** — 背离 Godot 推荐的 Theme 资源工作流，增加团队认知负担
- **编译时优化缺失** — 代码生成的 Theme 不能在编译时优化为二进制格式

**Risk:** Medium-High — 丧失可视化开发效率和编译器优化
**Effort:** 1 个 autoload 脚本（~150 行）+ 需覆盖 ThemeBuilder 的所有场景测试

---

### Comparison Summary

| 维度 | A: 集中式 .tres 资源 | B: 全局默认 Theme | C: 代码生成 Theme |
|------|:---:|:---:|:---:|
| 维护简便性 | ★★★★★ | ★★★★★ | ★★★☆☆ |
| 编辑器可视化 | ★★★★★ | ★★★★★ | ★☆☆☆☆ |
| 渐进式迁移 | ★★★★★ | ★★★★★ | ★★★☆☆ |
| addon 兼容性 | ★★★★★ | ★★★☆☆ | ★★★★☆ |
| 运行时灵活性 | ★★★☆☆ | ★★★☆☆ | ★★★★★ |
| Godot 4.7 标准性 | ★★★★★ | ★★★★☆ | ★★☆☆☆ |
| 新增场景一致性 | ★★★★☆ | ★★★★★ | ★★★★★ |
| 实施风险 | Low | Medium | Medium-High |

### Recommendation

→ **Approach A（单一集中式 Theme .tres + 逐场景显式引用）** 因为：

1. **Godot 标准做法** — Theme 资源是 Godot 的原生 UI 主题系统，成熟、稳定、零运行时开销
2. **渐进迁移** — 可以逐个场景迁移，不影响现有功能，做到一半也能正常运行
3. **编辑器可视化** — 颜色和样式在设计时即可看到效果，无需运行游戏
4. **addon 安全** — `dialogue_manager` 插件的内部 UI 不受影响（仅显式引用的场景应用主题）
5. **子项目兼容** — `rainy-night-prometheus/` 使用 symlink 共享路径结构，可直接引用同一 Theme 资源

**颜色方案草案：**

| Token | 颜色 | 用途 |
|-------|------|------|
| `bg_dark` | `#0a0a12` | 全局背景色（标题屏、面板背景） |
| `bg_panel` | `#141420` | 面板/气泡背景色 |
| `bg_surface` | `#1c1c2e` | 按钮/输入框/下拉框背景 |
| `bg_hover` | `#24243b` | 按钮悬停/输入框聚焦背景 |
| `neon_blue` | `#4a90d9` | 主强调色（选中态、链接、边框高亮） |
| `neon_red` | `#ff3355` | 警告/强调色（未选中态特殊标记） |
| `text_primary` | `#d0d0e0` | 主文字（Label、Button 文字） |
| `text_secondary` | `#808098` | 次要/禁用文字 |
| `text_link` | `#4a90d9` | 链接/交互文字 |
| `border_default` | `#2a2a3e` | 默认边框 |
| `border_focus` | `#4a90d9` | 聚焦状态边框 |
| `font_size_body` | `16` | 正文字号 |
| `font_size_small` | `12` | 辅助文字字号 |
| `font_size_title` | `48` | 标题字号 |
| `corner_radius` | `8` | 圆角半径（StyleBoxFlat） |

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

- [x] **AC1: Theme 资源存在并可加载** — `assets/themes/neon_theme.tres` 文件存在，`--headless --quit` 无资源加载错误
- [ ] **AC2: 颜色方案符合规范** — 暗色底 #0a0a12 在 Panel/背景区域生效，霓虹蓝 #4a90d9 在按钮/强调区域生效，霓虹红 #ff3355 在警告/特殊标记生效
- [ ] **AC3: 内置 UI 组件正常显示** — 标题屏的 Label、Button（如启动提示文字）、对话面板的 Panel/Label/RichTextLabel 均显示正确的主题颜色
- [ ] **AC4: 自定义 UI 使用主题颜色** — `dialogue_balloon.tscn` 中的 Panel、CharacterLabel、DialogueLabel、ResponseButton 使用主题颜色（从目前的暖棕过渡到 neon 色系）
- [ ] **AC5: 无引擎错误或崩溃** — 在 `godot --headless --quit` 和 `godot --path rainy-night-prometheus/ --headless --quit` 下无报错

### Edge Cases

1. **RPG-样式风格不一致导致感官冲突：** 状态栏（琥珀/暗蓝 Hopper 风格）与全局霓虹主题不协调。解决方案：状态栏保持独立配色，但其 Label 字体使用主题资源中的像素字体，确保最少程度的一致性。
2. **theme_override 优先级冲突：** 现有 scene 中使用 `theme_override_styles/panel = SubResource(...)` 的优先级高于 Theme 资源。迁移时需要逐个移除 `theme_override_*` 并让节点继承 Theme 的 StyleBox。
3. **对话管理器 addon 内部 UI：** `addons/dialogue_manager/` 的插件面板（如 error_panel、title_list）使用编辑器主题，不应被游戏主题影响。Approach A 的逐场景引用不会影响它们。
4. **sub_resource 与外部 Theme 同时存在的情况：** 一个节点同时有 `theme = SubResource(...)` 和 `theme_override_*`，且父节点有全局 Theme。Godot 的优先级顺序是：自身 theme_override > 自身 theme > 父节点 theme。迁移时需要删除 SubResource 引用。
5. **子项目 Theme 路径不同：** `rainy-night-prometheus/` 运行时工作目录不同，`res://assets/themes/neon_theme.tres` 路径在两个项目中是否一致需要验证。如果子项目的 assets 目录结构同步（通过 symlink），路径保持一致；否则需要在子项目中创建独立的 symlink。

### Failure Paths

1. **Theme 资源文件未被 Git 跟踪：** 新建的 `.tres` 文件未被添加到 `git add`，其他开发者 checkout 后找不到文件。应在创建后立即 `git add` 并 commit。
2. **主题颜色与 3D 世界环境不协调：** 霓虹色在带有 WorldEnvironment Glow 后处理的 3D 视口中可能显得过于明亮。需要在运行时确认 Glow 强度不影响 UI 的可见度——CanvasLayer 默认不受 Glow 影响。
3. **迁移过程中部分场景遗漏：** 如果只迁移了 title_screen.tscn 和 dialogue_panel.tscn 但遗漏了 dialogue_balloon.tscn，会导致对话系统的面板颜色与其他 UI 不一致。迁移应逐场景完成，每个场景迁移后验证。
4. **`theme.get_color()` 在运行时找不到常量崩溃：** 如果 GDScript 试图通过 `theme.get_color("custom_color", "Custom")` 获取未定义的常量，Godot 会返回默认 Color(0,0,0,1) 而不是崩溃。但最佳实践是在 Theme 资源中预定义所有需要访问的常量。

> 以上 AC、Edge Cases 和 Failure Paths 将直接成为 Plan 阶段的测试用例骨架。

---

## 6. Dependencies & Blockers

### Depends On

| 依赖 | 状态 | 风险 |
|------|------|------|
| Issue #213 — 创建雨夜普罗摩茨项目骨架 | **已完成 (CLOSED)** | Low — symlink 路径已就绪 |
| Godot 4.7.1 Theme 系统 | Stable | Low — 成熟 API |
| `assets/fonts/pixel_font.tres` | 已存在 | Low — Theme 可直接引用 |
| 现有 UI 场景（title_screen, dialogue_panel, dialogue_balloon 等） | 已存在 | Low — 需逐个迁移 |

### Blocks

| 后续工作 | 优先级 |
|---------|--------|
| Issue #142 — 玩家控制器（UI、交互提示需要主题） | Medium |
| Issue #152 — NPC 触发对话（交互提示 UI 需要主题） | Medium |
| Issue #156 — 场景过渡系统（过渡 UI 需要主题） | Low |
| 其他 MVP UI 优化 | Low |

### Dependencies Chain

```
#213 (项目骨架) ─── 已完成
     │
     ▼
#216 (UI 主题) ──── 本文档
     │
     ├──► #142 (玩家控制器 UI)
     ├──► #152 (NPC 交互 UI)
     └──► #156 (场景过渡 UI)
```

### Preparation Needed

- [ ] 创建 `assets/themes/` 目录
- [ ] 设计 Theme 资源的颜色常量完整列表（包含所有使用的 Control 类型）
- [ ] 列出所有需要移除 `theme_override_*` 的 scene 文件
- [ ] 检查 `dialogue_manager` addon 是否有 Hardcoded 主题颜色（如 `dialogue_balloon.tscn` 中的暖棕 `#0.58, 0.44, 0.22`）需要覆盖

---

## 7. Spike / Experiment

> Skipped per `depth/light` label. Sections 1–5 + 8 suffice for this research depth.

---

## 8. Continuation Context

> *本节将当前研究状态传递给下一阶段（Plan → Implement）。*

### 当前状态

项目运行在 Godot 4.7.1，已有 22+ 场景文件和 50+ GDScript 文件。目前**没有统一的 UI 主题系统**——所有样式以零散的 `theme_override_*` 定义在场景文件中。五个主要 UI 场景（title_screen, dialogue_panel, dialogue_balloon, response_panel, status_bar）使用不同的色板。

### 核心发现

1. **godot-minimal-theme 是编辑器主题** — 其 `minimal_theme.tres` 使用 `EditorSettings`/`EditorInterface` API，且自 Godot 4.6 起已作为默认编辑器主题原生集成。项目**不需要额外安装**该 addon。
2. **需要的是一份运行时 Theme 资源** — 推荐创建 `assets/themes/neon_theme.tres`，使用 Godot 原生 Theme 资源系统定义全局 UI 颜色/StyleBox/字体。
3. **推荐方案：单一集中式 .tres + 逐场景引用** — 平衡了维护性、编辑器可视化、addon 兼容性和渐进迁移能力。

### 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 主题方式 | 集中式 Theme .tres (Approach A) | 标准、低风险、渐进迁移 |
| 配色方案 | #0a0a12 / #4a90d9 / #ff3355 | Issue #216 AC 明确指定 |
| 应用方式 | 逐场景根节点显式引用 | 避免影响 dialogue_manager addon |
| 状态栏颜色 | 保持独立（琥珀/暗蓝 Hopper） | 状态栏是 HUD 元素，可保留独特风格 |
| 字体资源 | 引用现有 pixel_font.tres | 复用已导入的位图字体 |
| 迁移策略 | 逐个场景去除 theme_override，改为 Theme 继承 | 每个场景迁移后验证 |

### 后续步骤（Plan 阶段）

1. **创建 Theme 资源** — 设计完整的 color/stylebox/font/constant 集合，写为 `assets/themes/neon_theme.tres`
2. **迁移 title_screen.tscn** — 首个试点场景：删除空 SubResource Theme + 所有 theme_override_*，改为节点 theme 引用
3. **迁移 dialogue_panel.tscn** — 删除 StyleBoxFlat + theme_override
4. **迁移 dialogue_balloon.tscn** — 将暖棕配色改为 neon 色系（保留原有 StyleBox 结构但改颜色）
5. **迁移 response_panel.tscn** — 添加主题继承
6. **验证 status_bar.tscn** — 确认不冲突（保持独立配色）
7. **跑 `--headless --quit` 编译测试** — 确保无资源加载错误
8. **同步子项目** — 确认 `rainy-night-prometheus/` 可正常加载同一 Theme 资源

### 主要风险

1. **theme_override 优先级高于 Theme** — 现有 `theme_override_*` 不会自动被 Theme 覆盖，必须手动删除。Plan 阶段需要建立完整的迁移清单。
2. **对话管理器插件颜色硬编码** — `dialogue_balloon.tscn` 和 `response_button.gd` 中有硬编码的暖棕颜色（`Color(0.58, 0.44, 0.22)`）。覆盖这些颜色需要通过代码或场景修改。
3. **子项目路径验证** — 需要确认 `res://assets/themes/neon_theme.tres` 在 `rainy-night-prometheus/` 和主项目中均可正确解析。

### 传递到 Plan 阶段的关键文件列表

**修改清单：**
- `assets/themes/neon_theme.tres` — **新建**（主 Theme 资源）
- `scenes/title_screen.tscn` — 修改：删除 SubResource Theme + 所有 theme_override_*，添加 theme 引用
- `scenes/dialogue/dialogue_panel.tscn` — 修改：删除 StyleBoxFlat + color/font overrides
- `scenes/dialogue/dialogue_balloon.tscn` — 修改：暖棕→neon 色系切换（Panel StyleBox + CharacterLabel/DialogueLabel/ResponseButton 颜色）
- `scenes/dialogue/response_panel.tscn` — 修改：添加 theme 引用或保持现状

**引用文件（作为颜色/样式参考）：**
- `scenes/title_screen.tscn` — 当前颜色方案可参考但不作为源
- `scenes/ui/status_bar.tscn` — 独立配色（参考，不修改风格）

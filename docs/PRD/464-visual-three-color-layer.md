# PRD: [Feature] 视觉三色分层 — 可控物/目标物/环境颜色分离 (对比度修复)

> **Issue:** #464
> **标签:** enhancement, workflow/research, graphics, version/v1
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386/#389/#392/#449/#450 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（neon glow shader 的 glow_width 混合覆盖基底色、E2E 主题色断言影响、tscn 文本断言可行性）而包含 3 个轻量实验）
> **所有权:** `content_ownership: mechanical`（三色常量定义/场景 color 引用/对比度断言 = 机械可测；色值在 Issue 机械定稿的参考区间内微调 = taste-draft，调参零代码改动）
> **上游方案:** Issue #464 body 设计规范（**机械定稿，非品味博弈**）：可控物（玩家板/AI板）= 高亮冷色（青白/电光青 #00e5ff/#7fdfff，与背景对比度 ≥4:1）；目标物（砖块）= 暖色（橙/琥珀 #ff9d45，与可控物色相分离 ≥60°）；环境（背景 BgPulse/雨）= 低饱和中性冷暗，亮度低于所有游戏元素；球保留高亮白/青
> **并行上下文:** 视觉缺陷修复第一批（2026-08-13，worktree 并行测试后续）— 姊妹 Issue **#465**（雨幕粒子修复：漏水点 → 雨）同为 graphics 视觉修复；本 Issue 只做三色分层，**不碰雨幕粒子**（#465 文件域 = rain 相关，无重叠）；两者均 OPEN

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280，Forward+）存在系统性视觉缺陷：**所有游戏元素共用 #4a90d9 霓虹蓝**，导致玩家板不可见、砖块与对手无法区分。用户实测：`"看不到 player 板, 只能看到对手和砖块"`、`"砖块颜色和对手颜色一致"`。

| 文件 | 当前状态 | 与 #464 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/constants.gd` | Colors 区：`PLAYER_NEON_BLUE = Color(0.29, 0.56, 0.85, 1.0)`（#4a90d9）、`AI_NEON_RED = Color(1.0, 0.2, 0.33, 1.0)`（#ff3355）；Rain 区：`BG_COLOR = #0a0a12`；BG 区：`BG_PULSE_TINT = #4a90d9`（#449） | ❌ 无 PADDLE_NEON / BRICK_NEON 分层常量；玩家板与背景同色系 |
| `mini-pong/scenes/player_paddle.tscn` | ColorRect `color = Color(0.29, 0.56, 0.85, 1)`（#4a90d9 硬编码）+ neon_glow_material | ❌ 玩家板 = 背景同色系（#4a90d9）→ 低感知对比（名义 5.9:1 但同色相 + bloom 冲刷） |
| `mini-pong/scenes/brick.tscn` | ColorRect **无显式 color**（继承默认白 Color(1,1,1,1)）+ neon_glow_material | ❌ 白底 + 93% glow 混合（见 1.1.1）→ 渲染为 #4a90d9 蓝 = 与对手板同色（用户实证） |
| `mini-pong/scenes/Main.tscn` | `BgPulse`（AtmosphereLayer 首子，bg_pulse.gd #449）：`color = Color(0.29, 0.56, 0.85, 1)`，alpha ∈ [0.01, 0.15] 正弦呼吸；`AIPaddle` = `player_paddle.tscn` 实例（mode=1） | ⚠️ BgPulse 亮度已低于所有游戏元素（§1.1.2 验算）→ **无需调整（保留 BG）**；AIPaddle 共享玩家板场景 → 改场景色即双板同色（§2.1） |
| `mini-pong/assets/neon_glow_material.tres` | `glow_color = #4a90d9`；`glow_width = 3.0`（shader hint_range 0–0.5，默认 0.25） | ❌ **根因之一**：glow_width=3.0 → 全矩形 glow ≈ 0.93 → 所有挂该材质的对象（板/砖/球）渲染为 ~93% #4a90d9，基底色被覆盖（§1.1.1） |
| `mini-pong/tests/test_visual_contrast.gd` | **❌ 不存在** | 需新建（Issue 文件域明确要求：三色分离断言） |
| `mini-pong/tests/run_tests.gd` | 注册 25+ 套件（基线 2214 passed / 0 failed，2026-08-13） | ⚠️ 需注册新套件（支持性改动，显式列入文件域） |

#### 1.1.1 根因分析（静态证据，来自源码 + shader 数学）

1. **同色相基底**：玩家板基底色 #4a90d9 与背景（BgPulse 色调 #4a90d9 + 底色 #0a0a12）同属蓝紫色相；名义 WCAG 对比 5.9:1 达标，但**同色相 + glow bloom 冲刷**使玩家板在视觉上「融入」背景（用户实证：看不到玩家板）。
2. **glow 材质强制同色（深层根因）**：`neon_glow.gdshader` 的 `glow = 1.0 - smoothstep(0.0, glow_width, edge_dist)`，`edge_dist ∈ [0, 0.5]`（UV 半宽）。`neon_glow_material.tres` 的 `glow_width = 3.0` **超出 shader hint_range(0, 0.5) 一个数量级** → 中心处 `glow ≈ 0.926`，边缘 = 1.0 → `COLOR.rgb = mix(src_color, #4a90d9, glow·a)` 使**所有挂该材质的对象约 93% 呈现 #4a90d9**，与基底色无关：
   - 白砖（基底白）→ 渲染 ≈ mix(白, #4a90d9, 0.93) = **#4a90d9 蓝 = 与对手板（同样被强制为 #4a90d9）同色** → 用户「砖块颜色和对手颜色一致」的直接原因
   - 球（白/青）同样被染蓝 → 违反「球保留高亮白/青」
3. **结论**：仅改场景 color（Issue 文件域字面范围）**无法让修复在渲染层生效**——测试断言常量可通过，但渲染仍被 glow 材质拉回 #4a90d9（验算：cyan #00e5ff 经 0.926 混合 → (69,150,220) ≈ #4696dc，仍近 #4a90d9）。**必须同时修正 glow 材质参数**（§4.2 方案对比），这是本 PRD 对 Issue 文件域的唯一扩展建议。

#### 1.1.2 BgPulse「保留」验算

BgPulse 渲染色 = mix(#0a0a12, #4a90d9, alpha ∈ [0.01, 0.15]) → 最亮帧 ≈ (0.039+0.29·0.15, 0.039+0.56·0.15, 0.071+0.85·0.15) ≈ (20, 40, 65) 量级暗蓝；亮度远低于 PADDLE_NEON（#00e5ff，lum 0.63）、BRICK_NEON（#ff9d45，lum 0.46）→ **满足「环境亮度低于所有游戏元素」**，Main.tscn 零改动（符合 Issue「BgPulse color 若需调整」的条件性表述：不需要调整）。

### 1.2 预期行为（验收条件，源自 Issue #464）

1. **AC1 — 三色互异：玩家板 ≠ 砖块 ≠ 背景（RGB 距离 ≥ 60）** — `PADDLE_NEON` / `BRICK_NEON` / `BG_COLOR` 两两 RGB 欧氏距离 ≥ 60（验算：324 / 323 / 290，余量 4–5 倍）
2. **AC2 — 玩家板与背景对比度 ≥ 4:1（WCAG 相对亮度）** — PADDLE_NEON vs BG_COLOR：`(L1+0.05)/(L2+0.05) ≥ 4`（验算 #00e5ff = **12.8:1**；#7fdfff = 13.1:1）
3. **AC3 — 砖块与玩家板色相分离 ≥ 60°（HSV 色相）** — |hue(BRICK_NEON) − hue(PADDLE_NEON)| ≥ 60（验算 #ff9d45(28.4°) vs #00e5ff(186.1°) = **157.7°**）
4. **AC4 — brick.tscn ColorRect 显式设置 color（不再继承默认）** — brick.tscn ColorRect 增加 `color = Color(1.0, 0.616, 0.271, 1)`（BRICK_NEON）
5. **AC5 — 常量可配置，不改动既有逻辑** — 只**新增** PADDLE_NEON / BRICK_NEON 常量；`PLAYER_NEON_BLUE` / `AI_NEON_RED` / `BG_COLOR` / `BG_PULSE_TINT` **值不变**（HUD/GameOver/ScoreFlash/升级 UI 语义色源保持，test_constants TC6/TC8 断言不破）
6. **AC6 — run_tests.gd 全绿** — 基线 2214 passed / 0 failed 不回退；新套件 test_visual_contrast 注册后全绿
7. **AC7 — PR files 仅含文件域，不混入其他 issue** — 白名单 = constants.gd / player_paddle.tscn / brick.tscn / test_visual_contrast.gd（新）/ run_tests.gd（注册行）+ **§4.2 推荐的材质扩展 1 文件**（显式申报）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 对打进行中（PLAYING） | 持续 | 玩家板 = 电光青 #00e5ff（12.8:1 高对比），砖墙 = 琥珀橙 #ff9d45，背景 = 暗蓝灰 — 一眼分辨「我的板 / 目标砖 / 环境」 |
| B | 开局发球（SERVING） | 每分 | 球保留白/青高亮，与砖（橙）、板（青）均可区分，发球轨迹清晰 |
| C | 终局（GAME OVER） | 每局 | 失败屏 HUD 蓝/红语义不变（PLAYER_NEON_BLUE/AI_NEON_RED 未动），三色分层只作用于游戏世界元素 |
| D | 暂停/菜单 | 每局多次 | BgPulse 呼吸不受影响（环境层零改动），菜单文字可读性不变 |

### 1.4 技术约束（继承 Issue #464 + 既有架构）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 project.godot，720×1280 竖屏，Forward+） |
| 文件域（AC7 红线） | `constants.gd`（新增 Colors 分层区）/ `player_paddle.tscn` / `brick.tscn` / `tests/test_visual_contrast.gd`（新）/ `tests/run_tests.gd`（仅注册行）；**建议扩展**：`assets/neon_glow_material.tres`（§4.2 推荐 B，需在实现 PR 说明） |
| constants.gd 分区纪律 | 只**新增** `PADDLE_NEON` / `BRICK_NEON`（Colors 区旁）；既有常量逐字节不动（#448/#449/#450 并行先例：各改各的区） |
| 不变项 | `PLAYER_NEON_BLUE`(#4a90d9) / `AI_NEON_RED`(#ff3355) / `BG_COLOR`(#0a0a12) / `BG_PULSE_TINT` 值不变；`world_environment.tscn` 零改动（test_neon TC2/TC3 文本断言）；paddle.gd / brick.gd / breakout_grid.gd / bg_pulse.gd 零改动；Main.tscn 零改动（BgPulse 已合规） |
| 双板同场景 | `AIPaddle` = `player_paddle.tscn` 实例（mode=1）→ player_paddle.tscn 改色后**双板同色** = Issue 机械定稿「可控物(玩家板/AI板)=冷色」的字面语义；玩家/AI 区分靠**位置**（经典 Pong 惯例）+ HUD 蓝/红语义标签（不变） |
| headless | `--headless --quit` 无脚本错误；run_tests.gd 全绿（AC6） |
| 克制原则 | 只做三色分层，不新增特效/不引入新材质实例；颜色 = 常量级可配（taste 微调零代码改动）；Obsidian「90 年代地摊文艺」反例约束（不堆砌） |
| 所有权 | `content_ownership: mechanical`（常量/引用/断言）；色值在 Issue 参考区间内微调 = taste-draft（human-review 定稿） |
| 开源优先 | 调研结果见 §1.5 — 结论：不引入第三方资产，第一方实现（引擎内建 Color/ColorRect）并说明理由 |

### 1.5 开源优先调研结果（Issue body 要求）

调研时间 2026-08-13，检索 Godot Asset Library 官方 API（godot_version=4.7）+ 社区：

- **Godot Asset Library**：`theme color` → **0 条**；`palette` → 16 条，其中 Scene Paletter / Lospec Palette Importer / Cosineful Palettes [C#] / Palettizer shader 均为**编辑期调色工具或后处理滤镜**，非「可控物/目标物/环境语义三色分层」的运行时方案
- **GitHub/社区**：无「游戏元素语义三色分层（冷色可控物/暖色目标物/中性环境 + WCAG 对比度断言）」成熟 addon；对比度计算与 HSV 色相分离是引擎内建 `Color` 的数学能力（`get_luminance()` / `h()`），无需依赖
- **结论**：**无可直接复用的成熟方案**。第一方实现（constants.gd 三色常量 + tscn ColorRect 引用 + 纯函数对比度断言测试）零依赖、headless 可测、符合「找不到合适方案再自行实现，并在 PR 中说明调研结果」。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，含 `raw/` + `wiki/`）：检索关键词「颜色 / 色彩 / 对比度 / 霓虹 / 辨识 / 配色 / 色相」命中以下笔记——
- `wiki/体验引擎-patterns.md`「模式适用速查」：「沉浸感被 UI 破坏 → 1. 隐形界面」——**可读性是沉浸感前提**；本 Issue 修复的正是「玩家板不可见」这一可读性缺陷（三色分层 = 隐形界面模式的补全：玩家不需要找自己的板，一眼可见）
- `raw/Clippings/文字记录-CUSGA游戏评选作品评估-2026年7月3日.md`（:31）：评审对美术「做了很多很多东西…很满」的评价 → **克制反例**：本次修复只动颜色不动特效，不做加法
- `wiki/游戏设计理念.md`（:176）：「感性色彩」列为游戏设计维度之一——**色彩是语义/情感编码载体**；本 Issue 的三色语义（冷=可控、暖=目标、暗=环境）即色彩编码的机械落地
- **Vault 缺口记录**：vault 内无「WCAG 对比度 / HSV 色相分离」等可量化色彩工程笔记 → 本次断言体系（AC1–AC3）为项目内首创，已在本 PRD §1.2 给出可复算验算值

### 1.7 范围边界（与相邻 PRD/Issue 解冲突）

| PRD/Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #289 霓虹视觉基调 | 深底 #0a0a12、glow/bloom、PLAYER_NEON_BLUE/AI_NEON_RED 定义、neon glow shader | ❌ 不改 PLAYER_NEON_BLUE/AI_NEON_RED 值（HUD/GameOver/ScoreFlash 语义色源）；不重写 shader（只调材质参数，§4.2） |
| #392 霓虹 HUD | HUD 描边/投影/分区、升级卡稀有度色 | ❌ 不碰 HUD/UI 层；升级稀有度色映射（含 #4a90d9 common）不变 |
| #449 背景霓虹呼吸 | BgPulse 节点、BG_PULSE_* 常量、L0 背景呼吸 | ❌ 不碰 bg_pulse.gd / BG_PULSE_* 常量 / Main.tscn；「保留 BG」= 环境层零改动（§1.1.2 验算合规） |
| #384 砖墙系统 | brick.gd / breakout_grid.gd 行为、砖尺寸/布局 | ❌ 不碰砖行为与网格逻辑；只给 brick.tscn ColorRect 加显式 color（AC4） |
| #465 雨幕粒子修复（并行） | 雨滴分布（漏水点→雨） | ❌ 不碰 rain_curtain.gd / 雨公式 / RAIN_* 常量；雨属环境类但颜色已合规（冷暗），本 Issue 不涉雨 |
| #385/#386/#387/#388/#448/#450 | 得分/波次/升级/球速 HUD/音效 | ❌ 无交集 |

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 现状 | 成因 | 证据 |
|------|------|------|
| 所有元素共用 #4a90d9 | #289 以单一霓虹蓝建立视觉基调（深底 + 蓝 glow），当时无砖墙（#384 后才有目标物），「玩家板 vs 砖块 vs 背景」的三方对比需求不存在 | constants.gd Colors 区仅 PLAYER_NEON_BLUE/AI_NEON_RED 两色；brick.tscn ColorRect 无 color |
| glow 材质覆盖基底色（glow_width=3.0） | 材质创建时（2cb4111）glow_width 取 3.0，超出 shader hint_range(0,0.5) 一个数量级——疑似把「像素宽度」直觉直接写入 UV 单位 | neon_glow_material.tres `glow_width = 3.0` vs shader `hint_range(0.0, 0.5)` 默认 0.25 |
| 砖块「继承默认色」 | #384 砖墙实现时只挂材质、未设 color（当时视觉基调即「全蓝」，无分层需求） | brick.tscn ColorRect 无 color 属性 |

### 2.2 为什么现在改

1. **用户实证缺陷**：`"看不到 player 板"`、`"砖块颜色和对手颜色一致"` — 这是可玩性/可读性缺陷，不是品味问题；Issue 已机械定稿（非品味博弈），验收可量化（RGB 距离/对比度/色相分离）
2. **砖墙成为目标物后，语义分层是刚需**：#384 砖墙落地后，场上同时存在「可控物（板）/ 目标物（砖）/ 环境（背景）」，三者必须可一眼区分——标准游戏视觉设计：可控=高对比冷色、目标=暖色、环境=低饱和中性
3. **低成本窗口**：全部改动收敛在常量 + 场景 color 引用 + 1 个材质参数，零新脚本/零新节点/零依赖；断言走纯函数（Color 数学），headless 可测
4. **并行验收载体**：与 #465 同属「视觉缺陷修复第一批」，验证 worktree 并行隔离下的文件域纪律（AC7）

### 2.3 先前约束

| 约束 | 细节 |
|------|------|
| #289 视觉基调 | 深底 #0a0a12、glow 0.6/bloom 0.8；霓虹色源 = PLAYER_NEON_BLUE(#4a90d9)/AI_NEON_RED(#ff3355)——**值不可变**（多处消费） |
| #449 背景呼吸 | BgPulse 色调 #4a90d9、alpha ≤15%——环境层「保留」 |
| Issue #464 机械定稿 | 可控=高亮冷色（对比度 ≥4:1）；目标=暖色（色相分离 ≥60°）；环境=低饱和中性冷暗；球保留白/青 |
| Obsidian 克制原则 | 不堆砌特效（CUSGA 评审「很满」反例）；三色分层 = 纯语义编码，无新增视觉元素 |
| 双板同场景 | AIPaddle 复用 player_paddle.tscn → 双板同色是结构事实，按定稿接受（位置区分），HUD 蓝/红语义保留 |

---

## 3. 影响分析

### 3.1 新文件

| 文件 | 类型 | 职责 |
|------|------|------|
| `mini-pong/tests/test_visual_contrast.gd` | 测试（extends RefCounted，run_tests.gd 注册） | 三色分离断言：① 常量存在与值（PADDLE_NEON / BRICK_NEON）；② 两两 RGB 距离 ≥60；③ WCAG 对比度 PADDLE_NEON vs BG_COLOR ≥4:1（用 `Color.get_luminance()`）；④ HSV 色相分离 BRICK_NEON vs PADDLE_NEON ≥60°（`Color.h()`）；⑤ tscn 文本断言：brick.tscn ColorRect 含显式 `color = Color(1.0, 0.616, 0.271, 1)`、player_paddle.tscn ColorRect color = PADDLE_NEON 值（沿用 test_neon TC2/TC3 文本断言模式） |

### 3.2 直接改动文件

| 文件 | 改动性质 |
|------|---------|
| `mini-pong/gdscripts/constants.gd` | **新增** `# ── Visual Three-Color Layer (#464) ──` 区（Colors 区旁）：`PADDLE_NEON: Color = Color(0, 0.898, 1.0, 1.0)`（#00e5ff，推荐，对比度 12.8:1；备选 #7fdfff 13.1:1）、`BRICK_NEON: Color = Color(1.0, 0.616, 0.271, 1.0)`（#ff9d45，Issue 参考值）。`PLAYER_NEON_BLUE` / `AI_NEON_RED` / `BG_COLOR` / `BG_PULSE_TINT` **逐字节不动**（AC5） |
| `mini-pong/scenes/player_paddle.tscn` | ColorRect `color = Color(0, 0.898, 1.0, 1)`（PADDLE_NEON，替换硬编码 #4a90d9）→ 玩家板 + AI 板（共享场景）均变电光青 |
| `mini-pong/scenes/brick.tscn` | ColorRect **新增** `color = Color(1.0, 0.616, 0.271, 1)`（BRICK_NEON 显式设置，AC4） |
| `mini-pong/tests/run_tests.gd` | **新增注册行**：`_run("res://tests/test_visual_contrast.gd", "Visual Contrast")`（支持性改动，显式列入文件域） |
| `mini-pong/assets/neon_glow_material.tres`（**建议扩展，§4.2 推荐 B**） | `glow_width = 3.0 → 0.25`（回落到 shader hint 区间 = 边缘描边语义）→ 基底色透出，三色分层在渲染层生效；glow_color #4a90d9 保留（描边仍霓虹蓝，克制的品牌色） |

### 3.3 间接影响（需回归验证）

| 文件 | 影响 | 处理 |
|------|------|------|
| `mini-pong/scenes/Main.tscn` | 零改动（BgPulse 已合规 §1.1.2；AIPaddle 共享场景自动变色） | ✅ 不碰（Issue「若需调整」= 不需要） |
| `mini-pong/scenes/ball.tscn` | 球挂 neon_glow_material → glow_width 修正后**球还原为基底白/青**（符合「球保留高亮白/青」） | ✅ 受益；无改动 |
| `mini-pong/gdscripts/neon_glow.gdshader` | 零改动（材质参数回落即达 hint 语义） | ✅ 不碰 |
| `mini-pong/tests/test_constants.gd` | TC6/TC8 只断言 PLAYER_NEON_BLUE/AI_NEON_RED/BG_COLOR 值 | ✅ 零改动；新增常量不触及 |
| `mini-pong/tests/test_neon.gd` | TC2/TC3 文本断言 world_environment.tscn（零改动）| ✅ 不碰 |
| `mini-pong/tests/test_ui_system.gd` / `game_hud.gd` / `game_over_screen.gd` / `score_flash.gd` | 各自本地硬编码 #4a90d9/#ff3355（HUD 语义色） | ✅ 值未变，不受影响 |
| `mini-pong/e2e_shots.json` | `theme_color = "4a90d9"`：HUD/开始菜单/升级 UI 仍含 #4a90d9 → 存在性断言大概率仍过；但**主色分布改变**（板变青、砖变橙） | ⚠️ 需实测（Spike 2）；若主题色断言失败 → 更新 e2e_shots.json（超文件域，需在实现 PR 说明） |
| `docs/GAME_DESIGN/11-PLAYER-PADDLE.md` / `12-NEON-VISUAL.md` | 颜色描述将过时（#4a90d9 → 三色分层） | 实现 PR merge 后由 review agent 增量更新（GDD 惯例） |

### 3.4 运行流

```
constants.gd: PADDLE_NEON(#00e5ff) / BRICK_NEON(#ff9d45) / BG_COLOR(#0a0a12, 不变)
        │
        ▼
player_paddle.tscn ColorRect.color = PADDLE_NEON ──► 玩家板 + AI 板（共享场景）渲染电光青
brick.tscn ColorRect.color = BRICK_NEON      ──► 砖墙渲染琥珀橙
BgPulse (Main.tscn)                          ──► 暗蓝呼吸环境（不变）
        │
        ▼
neon_glow_material.glow_width 3.0 → 0.25    ──► 边缘描边（霓虹蓝 #4a90d9），基底色透出
        │
        ▼
test_visual_contrast.gd: RGB 距离 ≥60 / WCAG ≥4:1 / HSV 色相 ≥60°（纯函数断言）
```

- 三色分层为**静态语义编码**：无运行时状态、无信号、无 FSM 交互（比 #449 呼吸更简单——纯常量 + 场景引用）
- 断言全部走 `Color` 数学（`get_luminance()` / `h()` / 欧氏距离），headless 下可测

### 3.5 文档更新

- [ ] `docs/PRD/464-visual-three-color-layer.md`（本文件）
- [ ] `docs/GAME_DESIGN/11-PLAYER-PADDLE.md` / `12-NEON-VISUAL.md` — 实现 PR merge 后由 review agent 增量更新（三色分层）
- [ ] 本 PRD merge 后自动推进 Issue #464 → `workflow/plan`（workflow-chain.yml；squash-merge 若不触发则 REST API 手动推进）

---

## 4. 方案对比

本 Issue 含两个设计轴：**颜色常量与场景引用**（4.1）与 **glow 材质处理**（4.2，本 PRD 的关键研究增量），末尾汇总推荐组合。

### 4.1 颜色常量与场景引用

#### Approach A：新增 PADDLE_NEON / BRICK_NEON 常量 + 场景显式引用（推荐）

constants.gd 新增两常量（#00e5ff / #ff9d45），player_paddle.tscn / brick.tscn 的 ColorRect color 显式引用；PLAYER_NEON_BLUE / AI_NEON_RED / BG_COLOR 值不动。

- **Pros**：AC1–AC5 全命中（验算余量大：324/12.8:1/157.7°）；单一事实源（常量）；既有断言（test_constants TC6/TC8）零风险；HUD/GameOver/ScoreFlash 语义色不变；双板共享场景自动同色 = 定稿语义
- **Cons**：双板同色（玩家/AI 靠位置区分）——与「玩家蓝/AI 红」旧直觉不同，但 Issue 机械定稿明确「可控物(玩家板/AI板)=冷色」，且 HUD 蓝/红标签保留语义锚点
- **Risk**：Low — 纯常量 + 场景引用 + 文本断言，无逻辑改动
- **Effort**：0.5 天

#### Approach B：直接修改 PLAYER_NEON_BLUE 值

把 PLAYER_NEON_BLUE 改成 #00e5ff，玩家板沿用该常量。

- **Pros**：不新增常量
- **Cons**：**破坏既有语义**：PLAYER_NEON_BLUE 是 HUD/GameOver/ScoreFlash/升级 UI 的语义色源（test_ui_system / game_hud / game_over_screen / score_flash 均硬编码或引用）；改值 = 全局变青，超出 Issue 文件域且违反 AC5「不改动既有逻辑」；test_constants TC8-2 断言其值 → 必破
- **Risk**：High（全局语义污染 + 测试必破）
- **Effort**：0.2 天（但不可接受）

#### Approach C：不新增常量，tscn 内联硬编码新色

场景内直接写 Color(0, 0.898, 1.0, 1) 等。

- **Pros**：零常量区改动
- **Cons**：颜色散落多文件、无单一事实源（与项目「constants.gd 单一事实源」纪律冲突）；测试断言需硬编码两处值；taste 微调要改多个文件
- **Risk**：Med（维护性 + 与 #367 手感定稿「常量收敛」先例相悖）
- **Effort**：0.3 天

**推荐：Approach A。** 理由：(1) 唯一满足 AC1–AC5 全部验收且余量最大的方案；(2) 单一事实源纪律；(3) 零回归面；(4) 色值收敛在常量 → taste 微调零代码改动（human-review 定稿）。

### 4.2 glow 材质处理（关键研究增量）

> **研究发现**：`neon_glow_material.tres` 的 `glow_width = 3.0`（shader hint_range 0–0.5）使所有挂载对象渲染为 ~93% #4a90d9。**仅改场景 color 时，AC 测试全过但渲染仍全蓝**（验算：cyan 混合后 ≈ #4696dc）——视觉缺陷不会被真正修复。本轴决定是否扩展文件域。

#### Approach A：严格 Issue 文件域，只改场景色

不碰材质；只改 constants.gd / player_paddle.tscn / brick.tscn。

- **Pros**：文件域 100% 符合 Issue 字面
- **Cons**：**修复在渲染层失效**：glow 0.926 混合把青/橙拉回 #4a90d9 系（#4696dc / #5791ce）→ 用户可见缺陷依旧；测试成为「假证据」（常量断言过、画面没变）；AC7 满足但 AC1–AC3 的**意图**未达成
- **Risk**：High（缺陷未修复 = 交付失败）
- **Effort**：0.3 天（但无效）

#### Approach B：场景色 + 材质 glow_width 回落 0.25（推荐，扩展 1 文件）

`neon_glow_material.tres`：`glow_width = 3.0 → 0.25`（shader 默认语义 = 边缘描边）；glow_color #4a90d9 保留。

- **Pros**：基底色透出 → 三色分层在渲染层**真实生效**（球还原白/青、砖显橙、板显青）；1 行参数改动、零逻辑；glow 从「全矩形染色」回落为「边缘霓虹描边」，视觉反而更精致（克制原则）；不影响 ball.tscn / brick.tscn 共享材质的使用
- **Cons**：文件域 +1 文件（超出 Issue 字面「仅含」）——需在实现 PR 显式说明根因（shader 数学证据）；glow 描边变细（原 3.0 的「全染」视觉消失）——但那是缺陷不是特性
- **Risk**：Med-Low — 共享材质影响面 = 3 场景（player_paddle/brick/ball），均为正向；需 Spike 1 渲染验证 + Spike 2 E2E 回归
- **Effort**：0.1 天（追加）

#### Approach C：每对象独立材质（per-instance glow_color）

为板/砖各建 unique 材质（板 = 青 glow、砖 = 橙 glow）。

- **Pros**：glow 与基底色同相，视觉最完整
- **Cons**：新增 2+ 材质资源文件（文件域 +3）；违背克制原则（不堆砌）；对 AC1–AC3（断言常量）无增益；实现/维护成本最高
- **Risk**：Med（资源面扩大 + 测试文本断言需覆盖新文件）
- **Effort**：0.5–1 天

**推荐：Approach B。** 理由：(1) 唯一让 AC1–AC3 的**渲染意图**成立的方案（A 是假修复、C 是过度设计）；(2) 1 行参数改动，回落到 shader 自己声明的 hint 区间，属「修 bug 不是加功能」；(3) 共享材质影响面全部正向（板/砖/球同时受益）；(4) 文件域扩展 1 文件且根因可量化（shader 数学），符合 Issue「在 PR 中说明调研结果」的精神。

### 4.3 推荐组合汇总

| 设计轴 | 推荐 | 核心文件 |
|--------|------|---------|
| 颜色常量 | A：新增 PADDLE_NEON(#00e5ff) / BRICK_NEON(#ff9d45)，既有色值不动 | `gdscripts/constants.gd`（仅新增区） |
| 场景引用 | A：player_paddle.tscn color → PADDLE_NEON；brick.tscn 显式 color → BRICK_NEON | `scenes/player_paddle.tscn`、`scenes/brick.tscn` |
| glow 材质 | B：glow_width 3.0 → 0.25（边缘描边语义，基底色透出） | `assets/neon_glow_material.tres`（文件域扩展，PR 说明） |
| 断言 | 新套件 test_visual_contrast.gd（RGB ≥60 / WCAG ≥4:1 / HSV ≥60° / tscn 文本） | `tests/test_visual_contrast.gd`（新）+ `tests/run_tests.gd`（注册行） |
| 环境 | 保留：Main.tscn / bg_pulse.gd / BG_COLOR / BG_PULSE_TINT 零改动（§1.1.2 验算合规） | — |

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body）

- [x] **AC1: 玩家板 ≠ 砖块 ≠ 背景（RGB 距离 ≥ 60）** — PADDLE_NEON(#00e5ff) vs BRICK_NEON(#ff9d45) = 324；vs BG_COLOR(#0a0a12) = 323；BRICK vs BG = 290（断言阈值 60，余量 4–5 倍）
- [x] **AC2: 玩家板 vs 背景对比度 ≥ 4:1（WCAG 相对亮度）** — #00e5ff = 12.8:1（#7fdfff 备选 = 13.1:1）；断言用 `Color.get_luminance()` 纯函数
- [x] **AC3: 砖块 vs 玩家板色相分离 ≥ 60°（HSV）** — 28.4° vs 186.1° = 157.7°
- [x] **AC4: brick.tscn ColorRect 显式设置 color** — `color = Color(1.0, 0.616, 0.271, 1)`（文本断言）
- [x] **AC5: 常量可配置，不改动既有逻辑** — 只新增两常量；PLAYER_NEON_BLUE/AI_NEON_RED/BG_COLOR/BG_PULSE_TINT 值不变；test_constants TC6/TC8 零风险
- [x] **AC6: run_tests.gd 全绿** — 基线 2214 passed / 0 failed 不回退；新套件注册后全绿（Spike 1 验证）
- [x] **AC7: PR files 仅含文件域** — 白名单 = constants.gd / player_paddle.tscn / brick.tscn / test_visual_contrast.gd / run_tests.gd + `assets/neon_glow_material.tres`（§4.2 推荐 B 的显式申报扩展）

### 边界情况（Edge Cases）

1. **双板同色辨识** — AIPaddle 共享 player_paddle.tscn → 双板同为电光青：位置区分（顶/底，经典 Pong 惯例）+ HUD 蓝/红语义标签保留；若 human-review 认为需 AI 异色，属 taste-draft 后续（需 paddle.gd 或独立场景，超本 Issue 文件域）
2. **glow 材质共享面** — neon_glow_material 被 player_paddle/brick/ball 三场景共享：glow_width 回落对三者均正向（基底色透出）；ball 从「被染蓝」还原为白/青（符合定稿）；无反向影响
3. **headless 断言** — 断言走 `Color` 数学 + tscn 文本读取（FileAccess），不依赖渲染 → headless 完全可测（同 test_neon 先例）
4. **E2E 主题色断言** — e2e_shots.json `theme_color=4a90d9`：HUD/开始菜单/升级 UI 仍含 #4a90d9 → 存在性断言大概率仍过；若色数/主题色断言因主色分布改变而失败 → 更新 e2e_shots.json（超文件域，实现 PR 说明），不删断言内容（Spike 2）
5. **并行 #465** — 雨幕修复只涉 rain 文件域，与三色分层零重叠；提交前 merge main 自动合并（worktree 并行纪律）
6. **球速 HUD/音效并行常量** — #448（HUD 区）/ #450（AUDIO 区）已落地或并行：本 Issue 只新增 Colors 区常量，分区互不重叠

### 失败路径（Failure Paths）

1. **E2E 断言变红**（主题色/色数）→ 先验证 4a90d9 是否仍存在于画面（HUD 标签），若确实消失 → 更新 e2e_shots.json theme_color 为三色分层代表色（如 #00e5ff），在实现 PR 说明
2. **glow_width 回落导致描边过弱**（视觉损失）→ 微调 glow_intensity（1.0 → 1.2）或 glow_width（0.25 → 0.3），材质参数级修正（Spike 2 视觉确认）
3. **常量合并冲突无法自动解决** → worktree-commit.sh abort + 报告人工处理（并行测试预案）
4. **色值不被认可**（taste）→ human-review 定稿：PADDLE_NEON 在 #00e5ff/#7fdfff 区间、BRICK_NEON 在琥珀区间微调，常量级零代码改动

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #289 霓虹视觉基调（底色/glow/霓虹色源） | ✅ CLOSED | Low — 被保留的语义色与材质 |
| #384 砖墙系统（brick.tscn / breakout_grid） | ✅ CLOSED（随 #393 组装落地） | Low — 砖 ColorRect 引用目标 |
| #393 主场景组装（Main.tscn 分层/双板实例） | ✅ CLOSED | Low — 双板共享场景的结构事实 |
| #449 背景呼吸（BgPulse / BG_PULSE_TINT） | ✅ CLOSED | Low — 环境层保留对象 |

### 并行 Peer（非依赖）

| Peer | 状态 | 共享面 |
|------|------|--------|
| #465 雨幕粒子修复（视觉第一批） | OPEN（graphics） | 无（rain 文件域 vs 本 Issue 颜色文件域） |

### 依赖链

```
#289 霓虹基调（✅）→ #384 砖墙（✅，#393 组装）→ Issue #464 视觉三色分层（本 PRD）
                                                      │
        ├──► 并行: #465（雨幕粒子，零文件域重叠）
        ├──► 被保留: PLAYER_NEON_BLUE/AI_NEON_RED/BG_COLOR/BG_PULSE_TINT（值不变）
        └──► 被验证: workflow-chain → workflow/plan（下一阶段 plan agent）
```

---

## 7. Spike / 实验

depth/standard 下 Section 7 非必填，但存在三项真实技术不确定性（glow 材质混合的渲染实测、E2E 主题色断言影响、tscn 文本断言对浮点 Color 序列化的匹配），故包含 3 个轻量实验，成本各 ≤0.5 天：

### 实验 1：glow_width 回落后渲染层三色分离实测

- **问题**：shader 数学推得 glow_width=3.0 → 0.926 混合覆盖基底色（§1.1.1）；回落 0.25 后基底色是否真实透出、砖是否显橙/板是否显青，未实机验证
- **方法**：临时分支改 glow_width=0.25 + 场景色后，headless 跑 `godot --path mini-pong/ --headless --quit` 确认无错误；实机（或 e2e 截图）对比改造前后 02_midgame 截图的像素采样：砖区域应出现橙系、板区域应出现青系、背景保持暗蓝
- **预期结果**：渲染层三色分离成立；若残留蓝染 → 需进一步降低 glow 混合强度（glow_intensity 或 glow_width 0.2）
- **对方案影响**：验证推荐 B；若实测渲染仍被覆盖 → 升级为 Approach C（per-instance 材质）并在 PRD 增补

### 实验 2：E2E 4 重断言（主题色/色数）回归

- **问题**：主色分布改变（板青/砖橙）是否触发 e2e_shots.json 的 `theme_color=4a90d9` 存在性断言失败；色数断言对新增两色是否过敏
- **方法**：改造后跑 e2e loop 截图 + `analyze_bmp.py --theme 4a90d9`，检查断言输出；若失败，检查画面中 #4a90d9 来源（HUD 标签/开始菜单/升级 UI 边框）
- **预期结果**：断言全过（#4a90d9 仍存在于 HUD/菜单语义元素）；若失败 → 更新 theme_color（超文件域，PR 说明）
- **对方案影响**：确认是否需要 e2e_shots.json 更新；不删除断言内容

### 实验 3：tscn 文本断言可行性（浮点 Color 序列化）

- **问题**：test_visual_contrast 计划用 FileAccess 文本断言 brick.tscn 的 `color = Color(1.0, 0.616, 0.271, 1)`；Godot tscn 浮点序列化格式（3 位小数、尾随 1）是否与断言字面稳定匹配（同 test_neon TC2/TC3 先例：`Color(0.039, 0.039, 0.071, 1)` 已稳定）
- **方法**：用 Godot 实测写入 `Color(1.0, 0.616, 0.271, 1)` 到 tscn 的序列化输出；或直接在实现 PR 中按断言字面写入场景（test_neon 先例证明可行）
- **预期结果**：序列化格式与断言字面一致；若不一致（如 0.616 → 0.615999 舍入），断言改用「读取 tscn 后解析 Color」或放宽容差
- **对方案影响**：决定断言写法（文本字面 vs 解析比较），避免实现阶段返工

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #464 当前 `workflow/research`（本 PRD 撰写时已由 workflow/available 推进），本 PRD merge 后 workflow-chain.yml 自动推进 → `workflow/plan`（squash-merge 已知 gap：若未自动推进，用 REST API 手动推进 `echo '{"labels":["workflow/plan"]}' | gh api repos/devvi/agent-game-test/issues/464/labels -X POST --input -`）
- 基线：`godot --path mini-pong/ --headless --quit` ✅ 无脚本错误；`run_tests.gd` 基线 **2214 passed / 0 failed**（2026-08-13）
- 上游定稿：Issue #464 body 设计规范（机械定稿）；PLAN-rogue-pong §3.1 分层语义（L1 世界元素三色编码）；GDD 12-NEON-VISUAL / 11-PLAYER-PADDLE 待增量更新

### 给 plan agent 的关键交接

1. **文件域白名单（AC7）**：`gdscripts/constants.gd`（仅新增 Colors 分层区）+ `scenes/player_paddle.tscn` + `scenes/brick.tscn` + `tests/test_visual_contrast.gd`（新）+ `tests/run_tests.gd`（仅注册行）+ **`assets/neon_glow_material.tres`（§4.2 推荐 B 的扩展申报，PR 中必须说明根因：glow_width=3.0 超出 shader hint 0–0.5，0.926 混合覆盖基底色，shader 数学证据见 §1.1.1）**
2. **推荐色值**：`PADDLE_NEON = Color(0, 0.898, 1.0, 1.0)`（#00e5ff，12.8:1；备选 #7fdfff 13.1:1）、`BRICK_NEON = Color(1.0, 0.616, 0.271, 1.0)`（#ff9d45）——AC 验算值（RGB 324 / 12.8:1 / 157.7°）必须在新测试中复现
3. **不变项清单**：PLAYER_NEON_BLUE / AI_NEON_RED / BG_COLOR / BG_PULSE_TINT 值不变；Main.tscn / world_environment.tscn / paddle.gd / brick.gd / breakout_grid.gd / bg_pulse.gd 零改动；双板同色（位置区分，HUD 蓝/红语义保留）
4. **测试注册**：run_tests.gd 新增 `_run("res://tests/test_visual_contrast.gd", "Visual Contrast")`；断言走 `Color.get_luminance()` / `Color.h()` / 欧氏距离纯函数 + tscn 文本断言（Spike 3 确认浮点序列化格式）
5. **E2E 关注**：改造后 e2e loop 必须重跑；若 theme_color 断言失败 → 更新 `mini-pong/e2e_shots.json`（超文件域，PR 说明）；Spike 1/2 的实测结论需在 DESIGN 中引用
6. **并行纪律**：#465（雨幕）并行中，commit 前 merge main（worktree-commit.sh 自动），constants.gd 只改新增区

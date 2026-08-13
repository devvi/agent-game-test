# DESIGN: [Feature] 视觉三色分层 — 可控物/目标物/环境颜色分离 (对比度修复)

> **Parent Issue:** #464
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A（颜色常量 + 场景显式引用）+ B（glow 材质 `glow_width` 回落 0.25）—— 确认 PRD §4.1/§4.2 推荐组合：新增 `PADDLE_NEON` / `BRICK_NEON` 常量 + 场景 ColorRect 显式引用 + `neon_glow_material.tres` 参数修正（文件域扩展 1 文件，实现 PR 必须说明根因）
> **Reference PRD:** docs/PRD/464-visual-three-color-layer.md（research PR #467，已合并）
> **上游方案:** Issue #464 body 设计规范（**机械定稿，非品味博弈**）：可控物（玩家板/AI板）= 高亮冷色（电光青 #00e5ff，对比度 ≥4:1）；目标物（砖块）= 暖色（琥珀橙 #ff9d45，色相分离 ≥60°）；环境（背景 BgPulse/雨）= 低饱和中性冷暗，亮度低于所有游戏元素；球保留高亮白/青
> **所有权:** `content_ownership: mechanical`（三色常量定义/场景 color 引用/对比度断言 = 机械可测；色值在 Issue 参考区间内微调 = taste-draft，调参零代码改动）
> **深度:** depth/standard —— 产出 DESIGN + 精简 TASKS 文档（文件域 6 个、跨 constants/场景/材质/测试 4 子系统，按 #450 并行先例产出 TASKS 明确边界）；测试仅描述不写代码
> **并行上下文:** 视觉缺陷修复第一批（2026-08-13，worktree 并行）—— 姊妹 Issue **#465**（雨幕粒子修复）并行中，文件域零重叠（rain vs 颜色）；同改 `constants.gd` 的 #448（HUD 区）/ #450（AUDIO 区）已落地 —— 本 Issue 只新增 Colors 区旁新区，提交前 merge main 自动合并

---

## 1. 概述

Mini Pong 存在系统性视觉缺陷：玩家板 / 砖块 / 背景共用 #4a90d9 霓虹蓝，玩家板不可见、砖块与对手板无法区分（用户实证：「看不到 player 板」「砖块颜色和对手颜色一致」）。根因有二：(1) 玩家板基底色 #4a90d9 与背景 BgPulse 同色相（名义对比 5.9:1 但同色相 + bloom 冲刷 → 视觉融入背景）；(2) **深层根因**：`neon_glow_material.tres` 的 `glow_width = 3.0` 超出 shader `hint_range(0.0, 0.5)` 一个数量级 → 中心处 `glow ≈ 0.926`，所有挂该材质的对象约 93% 被渲染为 #4a90d9，**基底色被覆盖**（白砖被染蓝 = 用户实证的直接原因）。

本设计按 Issue 机械定稿做**静态语义三色编码**：可控物（玩家板/AI板）= 电光青（#00e5ff）、目标物（砖墙）= 琥珀橙（#ff9d45）、环境（背景）= 暗蓝灰（#0a0a12 不变）。零新节点、零新脚本、零新依赖。

**Plan 阶段边界**：本阶段只产出本文档 + TASKS，不碰任何 `.gd` / `.tscn` / `.tres` / `.json` 文件 —— 下列全部内容为 implement agent 的契约。

### 设计哲学

1. **三色语义即契约**：冷色 = 可控物（对比度 ≥4:1）、暖色 = 目标物（色相分离 ≥60°）、暗中性 = 环境（亮度最低）—— 全部量化断言（RGB 欧氏距离 / WCAG 相对亮度 / HSV 色相），`Color` 数学纯函数 headless 可测。
2. **渲染层有效性优先**：仅改场景 color 是「假修复」—— glow 0.926 混合仍会把青/橙拉回 #4a90d9 系（验算：cyan 经 0.926 混合 ≈ #4696dc）。**必须同时把 `glow_width` 回落 0.25**（shader 自己声明的 hint 区间 = 边缘描边语义），基底色才在渲染层透出。这是对 Issue 文件域的唯一扩展（+1 文件，实现 PR 说明根因）。
3. **单一事实源 + 克制**：颜色收敛于 `constants.gd` 新增区（taste 微调零代码改动）；不新增特效/材质实例/第三方资产（PRD §1.5 调研：Asset Library 无成熟方案，第一方实现）。
4. **零侵入既有语义**：`PLAYER_NEON_BLUE` / `AI_NEON_RED` / `BG_COLOR` / `BG_PULSE_TINT` **值逐字节不动**（HUD/GameOver/ScoreFlash/升级 UI 语义色源）；`paddle.gd` / `brick.gd` / `breakout_grid.gd` / `bg_pulse.gd` / `Main.tscn` / `world_environment.tscn` 零改动。
5. **文件域红线（AC7）**：实现 PR 白名单 = `gdscripts/constants.gd`（仅新增区）+ `scenes/player_paddle.tscn` + `scenes/brick.tscn` + `assets/neon_glow_material.tres`（扩展申报）+ `tests/test_visual_contrast.gd`（新）+ `tests/run_tests.gd`（仅注册行）；用 `worktree-commit.sh` 白名单 add，绝不 `git add .`。

---

## 2. 现状核实（plan agent 已对照 origin/main 源码确认，2026-08-13）

| 文件 | 现状（已核实） | 与 #464 需求的差距 |
|------|--------------|------------------|
| `mini-pong/gdscripts/constants.gd` | `# ── Colors ──` 区仅 `PLAYER_NEON_BLUE = Color(0.29, 0.56, 0.85, 1.0)`（#4a90d9）、`AI_NEON_RED = Color(1.0, 0.2, 0.33, 1.0)`（#ff3355）；Rain 区 `BG_COLOR = Color(0.039, 0.039, 0.071, 1.0)`（#0a0a12）；#449 区 `BG_PULSE_TINT = Color(0.29, 0.56, 0.85, 1.0)` | ❌ 无 PADDLE_NEON / BRICK_NEON 分层常量 |
| `mini-pong/scenes/player_paddle.tscn` | ColorRect（Area2D 直接子节点）`color = Color(0.29, 0.56, 0.85, 1)` 硬编码 + `material = neon_glow_material.tres` | ❌ 玩家板 = 背景同色相 → 低感知对比 |
| `mini-pong/scenes/brick.tscn` | ColorRect **无 `color` 属性**（继承默认白）+ `material = neon_glow_material.tres` | ❌ 白底 + 93% glow 混合 → 渲染为 #4a90d9 = 与对手板同色（用户实证） |
| `mini-pong/assets/neon_glow_material.tres` | `glow_color = Color(0.29, 0.56, 0.85, 1)`（#4a90d9）；`glow_width = 3.0`；`glow_intensity = 1.0` | ❌ **根因**：glow_width=3.0 超出 shader hint_range(0,0.5) → 全矩形 ≈0.926 混合，基底色被覆盖（§1.1.1 shader 数学已复核，见下方验算） |
| `mini-pong/gdscripts/neon_glow.gdshader` | `uniform float glow_width : hint_range(0.0, 0.5) = 0.25`；`glow = 1.0 - smoothstep(0.0, glow_width, edge_dist)`；`COLOR.rgb = mix(src_color.rgb, glow_color.rgb, glow * glow_color.a)` | ⚠️ 材质参数回落即达 hint 语义，shader 本身零改动 |
| `mini-pong/scenes/Main.tscn` | `AtmosphereLayer`（layer=0）下 `BgPulse`（#449，alpha ∈ [0.01,0.15] 呼吸）+ `RainCurtain`；`AIPaddle` = `player_paddle.tscn` 实例（mode=1） | ⚠️ BgPulse 亮度已低于所有游戏元素（PRD §1.1.2 验算）→ **零改动**；AIPaddle 共享玩家板场景 → 改场景色即双板同色（结构事实，按定稿接受） |
| `mini-pong/tests/run_tests.gd` | 注册 25+ 套件（`_run` 同步 + `_run_async` 异步两类）；基线 2214 passed / 0 failed（PRD §8 记录） | ⚠️ 需新增 1 行注册（同步 `_run` 类，与 test_neon 同型） |
| `mini-pong/tests/test_neon.gd` | TC2/TC3 用 `FileAccess.get_file_as_string` + `content.contains(...)` 做 tscn 文本断言（先例：`Color(0.039, 0.039, 0.071, 1)` 字面匹配 world_environment.tscn） | ✅ 新套件沿用此模式 |
| `mini-pong/tests/test_constants.gd` | TC6/TC8 断言 PLAYER_NEON_BLUE / AI_NEON_RED / BG_COLOR 的逐分量值 | ✅ 只新增常量不触及 → 零改动 |
| `mini-pong/e2e_shots.json` | `02_midgame` 组 `theme_color = "4a90d9"`（存在性断言） | ⚠️ 主色分布改变（板青/砖橙）；#4a90d9 仍存在于 HUD/菜单语义元素 → 大概率仍过，需实测（§5.4） |

### shader 数学复核（PRD §1.1.1 结论独立验证）

- `edge_dist ∈ [0, 0.5]`（UV 半宽）。`glow_width = 3.0` 时，中心处 `smoothstep(0, 3.0, 0.5)`：t = 0.5/3 = 0.1667 → `3t² − 2t³ = 0.074` → `glow = 1 − 0.074 = 0.926`；边缘处 glow = 1.0 → **全矩形 ≈ 0.93 混合 #4a90d9** ✅ 复核成立
- `glow_width = 0.25` 时：中心处 `smoothstep(0, 0.25, 0.5) = 1.0` → glow = 0（基底色全透出）；边缘渐变为 1.0 → **边缘描边语义** ✅
- 结论：材质参数回落 0.25 后三色分层在渲染层真实生效；`glow_color #4a90d9` 保留为边缘描边色（克制的品牌色）

### PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计处置 |
|---------|-----------|---------|
| 断言字面 `color = Color(1.0, 0.616, 0.271, 1)` | Godot tscn 浮点序列化为**去尾零最小形式**（证据：既有 `Color(0.29, 0.56, 0.85, 1)`、world_environment `Color(0.039, 0.039, 0.071, 1)` 均为 `1` 而非 `1.0`） | **Spike 3 确定性解决**：场景与断言统一使用规范序列化字面 `Color(0, 0.898, 1, 1)` / `Color(1, 0.616, 0.271, 1)`（§3.2/§3.3）；若编辑器重写为 `0.0`/`1.0` 形式，implement 须以实际写入字面同步断言（容忍记录见 §5.6） |
| 「新增区在 Colors 区旁」 | Colors 区位于文件中部（Brick Wall #384 区之前）；#448 HUD 区 / #450 AUDIO 区在文件末尾追加 | 新区**紧跟 Colors 区之后**（AI_NEON_RED 行后、Brick Wall 区前），与已落地并行区零重叠；提交前 merge main 自动合并 |
| 「新套件注册」 | run_tests.gd 同时有 `_run`（同步）与 `_run_async` | test_visual_contrast 为同步套件（extends RefCounted + `run()`，与 test_neon/test_constants 同型）→ 用 `_run(...)` 注册 |
| 「test_constants TC6/TC8 零风险」 | TC6 逐分量断言 0.29/0.56/0.85、1.0/0.2/0.33；TC8 断言 alpha/BG_COLOR | ✅ 成立——只新增常量不修改既有值 |
| 「Main.tscn 零改动」 | AIPaddle = player_paddle.tscn 实例（共享场景） | ✅ 成立——双板同色为结构事实（§5.1） |

---

## 3. 核心设计（implement 契约）

### 3.1 `constants.gd` — 新增 `Visual Three-Color Layer` 区

- **位置:** 紧跟既有 `# ── Colors ──` 区之后（`AI_NEON_RED` 行后、`# ── Brick Wall (#384) ──` 区前）；既有区**逐字节不动**（AC5；并行 #448/#450 区已在 main，提交前 merge main 自动合并）
- **追加内容（精确文本，含前导空行）:**

```gdscript

# ── Visual Three-Color Layer (#464) ──
# 视觉三色分层 (Issue #464 机械定稿; mechanical): 可控物=高亮冷色(电光青, WCAG 对比度≥4:1),
# 目标物=暖色(琥珀橙, 与可控物 HSV 色相分离≥60°), 环境=低饱和中性冷暗(亮度最低)。
# 双板共享 player_paddle.tscn → 玩家板/AI板同色, 位置区分 (经典 Pong 惯例)。
# 值可配: taste 微调在 Issue 参考区间内改此两常量, 零代码改动。
const PADDLE_NEON: Color = Color(0.0, 0.898, 1.0, 1.0)   # #00e5ff 电光青 (WCAG 12.8:1 vs BG_COLOR; 备选 #7fdfff 13.1:1)
const BRICK_NEON: Color = Color(1.0, 0.616, 0.271, 1.0)  # #ff9d45 琥珀橙 (HSV hue 28.4° vs PADDLE 186.1° = 157.7° ≥ 60°)
```

- **验算（AC1–AC3，须在新测试中复现）:** RGB 欧氏距离 PADDLE↔BRICK = 324、PADDLE↔BG = 323、BRICK↔BG = 290（阈值 60，余量 4–5 倍）；WCAG 对比度 #00e5ff vs #0a0a12 = **12.8:1**（阈值 4:1）；HSV 色相分离 = **157.7°**（阈值 60°）

### 3.2 `player_paddle.tscn` — ColorRect 改色

- **改动:** `color = Color(0.29, 0.56, 0.85, 1)` → `color = Color(0, 0.898, 1, 1)`（PADDLE_NEON 的**规范序列化字面**，与 §7 测试断言逐字节一致；`material` 引用不动）
- **影响:** 玩家板 + AI 板（AIPaddle 共享本场景）均变电光青 —— 定稿语义「可控物=冷色」

### 3.3 `brick.tscn` — ColorRect 显式加色（AC4）

- **改动:** ColorRect 节点在 `material = ExtResource("2_neon_mat")` 行后**新增** `color = Color(1, 0.616, 0.271, 1)`（BRICK_NEON 规范序列化字面）；其余零改动
- **意义:** 不再继承默认白；配合 glow_width 回落，砖墙渲染为琥珀橙

### 3.4 `neon_glow_material.tres` — glow_width 回落（文件域扩展，PR 必须说明）

- **改动:** `shader_parameter/glow_width = 3.0` → `shader_parameter/glow_width = 0.25`；`glow_color`（#4a90d9）与 `glow_intensity`（1.0）**保留**
- **根因说明（写进实现 PR）:** glow_width=3.0 超出 `neon_glow.gdshader` 的 `hint_range(0.0, 0.5)` 一个数量级 → 中心 glow ≈ 0.926 → 所有挂载对象（板/砖/球）约 93% 渲染为 #4a90d9，基底色被覆盖 —— 仅改场景 color 无法让修复在渲染层生效（PRD §1.1.1 shader 数学）
- **共享面影响（全正向）:** player_paddle / brick / ball 三场景共享本材质 —— 板显青、砖显橙、球还原为基底白/青（定稿「球保留高亮白/青」）

### 3.5 `tests/run_tests.gd` — 注册行（支持性改动）

- **改动:** 在 `_run("res://tests/test_constants.gd", "Constants")` 之后新增一行：`_run("res://tests/test_visual_contrast.gd", "Visual Contrast")`（同步套件，与 test_neon 同型）；其余零改动
- **注意:** 新增注册行会改变 run_tests.gd —— 属文件域内显式申报项（AC7）

### 3.6 `tests/test_visual_contrast.gd`（新文件，implement 阶段创建）

- **文件:** `mini-pong/tests/test_visual_contrast.gd`（extends RefCounted，同步 `run()`，`passed`/`failed` 计数，`_assert` 助手 —— 沿用 test_neon 模板）
- **本阶段只描述用例（§7），不写代码。** `.uid` 由 Godot 首次导入自动生成，不入 PR 白名单

---

## 4. 数据流

```
constants.gd (新增区):  PADDLE_NEON #00e5ff / BRICK_NEON #ff9d45 / BG_COLOR #0a0a12 (不变)
        │
        ├──► player_paddle.tscn  ColorRect.color = Color(0, 0.898, 1, 1)   ──► 玩家板 + AI板（共享场景）渲染电光青
        ├──► brick.tscn           ColorRect.color = Color(1, 0.616, 0.271, 1) ──► 砖墙渲染琥珀橙
        ├──► Main.tscn BgPulse    暗蓝呼吸环境（零改动，亮度最低 ✅）
        │
        ▼
neon_glow_material.tres:  glow_width 3.0 → 0.25 ──► 边缘霓虹描边 (#4a90d9)，基底色透出
        │
        ▼
渲染层:  可控物=青 / 目标物=橙 / 环境=暗蓝 / 球=白青 —— 一眼分辨（AC1–AC3 意图达成）
        │
        ▼
test_visual_contrast.gd:  RGB 距离 ≥60 / WCAG ≥4:1 / HSV 色相 ≥60° / tscn 文本断言（纯函数，headless 可测）
```

- 三色分层为**静态语义编码**：无运行时状态、无信号、无 FSM 交互 —— 数据流单向（常量 → 场景引用 → 渲染），比 #449 呼吸更简单
- 断言全部走 `Color` 数学（`get_luminance()` / `h()` / 欧氏距离）+ `FileAccess` tscn 文本读取，headless 下完全可测

---

## 5. 边界情况与错误处理

| # | Edge Case | Mitigation |
|---|-----------|-----------|
| 5.1 | **双板同色辨识** — AIPaddle 共享 player_paddle.tscn → 双板同为电光青 | 按定稿接受：位置区分（顶/底，经典 Pong 惯例）+ HUD 蓝/红语义标签保留（PLAYER_NEON_BLUE/AI_NEON_RED 未动）。若 human-review 要求 AI 异色 → 属 taste-draft 后续（需 paddle.gd 或独立场景，超本 Issue 文件域） |
| 5.2 | **glow 材质共享面** — neon_glow_material 被板/砖/球三场景共享 | glow_width 回落对三者均正向（基底色透出）；球从「被染蓝」还原白/青（符合定稿）；无反向影响。实现后 `godot --path mini-pong/ --headless --quit` 编译验证 |
| 5.3 | **headless 断言可行性** | 断言走 `Color` 数学 + tscn 文本读取（FileAccess），不依赖渲染 → headless 完全可测（test_neon 先例） |
| 5.4 | **E2E 主题色断言** — e2e_shots.json `theme_color=4a90d9` 存在性断言 | 主色分布改变（板青/砖橙）但 HUD/开始菜单/升级 UI 仍含 #4a90d9 → 大概率仍过；若失败 → 更新 `e2e_shots.json`（超文件域，实现 PR 说明），不删断言内容 |
| 5.5 | **并行 #465** — 雨幕修复同批并行 | 只涉 rain 文件域，与三色分层零重叠；提交前 merge main 自动合并（worktree 并行纪律）；constants.gd 只改新增区 |
| 5.6 | **浮点序列化漂移** — Godot 编辑器可能重写 tscn 浮点形式 | 场景与断言统一用规范最小序列化字面；若重写为 `0.0`/`1.0` 形式 → implement 以实际写入字面同步断言（放宽容差或改字面）；禁止在断言中硬编码 PRD 原稿的 `Color(1.0, ...)` 形式（与 Godot 实际序列化不符） |
| 5.7 | **glow 描边过弱**（回落 0.25 后视觉损失） | 微调 `glow_intensity`（1.0 → 1.2）或 `glow_width`（0.25 → 0.3），材质参数级修正（不超文件域）；默认不调 |
| 5.8 | **常量合并冲突**（与并行 PR 同区） | worktree-commit.sh 自动 merge；真冲突 ≤2 文件自动尝试解决，否则 abort + 报告人工处理（不硬解） |

---

## 6. 集成点

> **状态约定:** ⬜ = 待 implement 接线；✅ = implement 已接线验证。implement agent 完成接线后必须更新本表。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 常量 → 场景 | `constants.gd` PADDLE_NEON | #464 | player_paddle.tscn ColorRect `color` 引用（字面写入规范序列化） | ⬜ pending |
| 常量 → 场景 | `constants.gd` BRICK_NEON | #464 | brick.tscn ColorRect 显式 `color`（AC4） | ⬜ pending |
| 材质 → 渲染 | `neon_glow_material.tres` glow_width=0.25 | #464 | 板/砖/球三场景共享材质，基底色透出 | ⬜ pending |
| 测试 → 运行器 | `test_visual_contrast.gd` | #464 | run_tests.gd 新增 `_run(..., "Visual Contrast")` 注册行 | ⬜ pending |
| 游戏 → E2E | 主色分布改变 | #464 | e2e_shots.json theme_color 断言监控（失败才更新，超文件域需 PR 说明） | ⬜ monitoring |
| 常量 → 既有断言 | 新增常量 | #464 | test_constants TC6/TC8 零改动（只断言既有值） | ✅ 已核实安全 |

---

## 7. 测试策略与用例描述

新套件 `tests/test_visual_contrast.gd`（extends RefCounted，同步 `run()`；`passed`/`failed` 计数 + `_assert(cond, name)` 助手，沿用 test_neon 模板）。**以下为用例描述，非可运行代码。**

### Scenario A: 常量存在与值（P0）
- **Test A1:** `load("res://gdscripts/constants.gd")` 成功，`PADDLE_NEON` / `BRICK_NEON` 存在
- **Test A2:** `PADDLE_NEON == Color(0, 0.898, 1.0, 1.0)`（#00e5ff；分量容差 ±0.01，沿 test_constants TC6 模式）
- **Test A3:** `BRICK_NEON == Color(1.0, 0.616, 0.271, 1.0)`（#ff9d45；分量容差 ±0.01）

### Scenario B: 三色互异 —— RGB 欧氏距离 ≥ 60（AC1）
- **Test B1:** `PADDLE_NEON` vs `BRICK_NEON` 欧氏距离 ≥ 60（期望 ≈324）
- **Test B2:** `PADDLE_NEON` vs `BG_COLOR` 欧氏距离 ≥ 60（期望 ≈323）
- **Test B3:** `BRICK_NEON` vs `BG_COLOR` 欧氏距离 ≥ 60（期望 ≈290）
- *实现提示:* 欧氏距离 = `sqrt((r1-r2)^2 + (g1-g2)^2 + (b1-b2)^2)`（Color 无内建距离函数）

### Scenario C: WCAG 对比度 ≥ 4:1（AC2）
- **Test C1:** `PADDLE_NEON.get_luminance()` vs `BG_COLOR.get_luminance()` 相对亮度比 ≥ 4（期望 12.8:1）
- *实现提示:* 对比度 = `(L1 + 0.05) / (L2 + 0.05)`，`L = Color.get_luminance()`（内建，PRD §1.5 确认无依赖）

### Scenario D: HSV 色相分离 ≥ 60°（AC3）
- **Test D1:** `abs(BRICK_NEON.h() - PADDLE_NEON.h())`（或环形差）≥ 60°（期望 157.7°）
- *实现提示:* `Color.h()` 返回 0–1 弧度制（0–360° 映射）；注意环形色相差（|h1−h2| 与 360−|h1−h2| 取小）

### Scenario E: tscn / tres 文本断言（AC4 + 渲染层有效性）
- **Test E1:** `player_paddle.tscn` 可读（FileAccess），`content.contains("color = Color(0, 0.898, 1, 1)")`（PADDLE_NEON 规范序列化字面）
- **Test E2:** `brick.tscn` 可读，`content.contains("color = Color(1, 0.616, 0.271, 1)")`（显式 color，AC4）
- **Test E3:** `neon_glow_material.tres` 可读，`content.contains("shader_parameter/glow_width = 0.25")`（渲染层修复成立的静态证据；沿用 test_neon TC7 文件完整性模式）
- *注意:* 断言字面必须与 §3.2/§3.3 写入场景的字面**逐字节一致**（§5.6）

### Scenario F: 回归 —— 既有语义色不变（AC5）
- **Test F1（非本套件，引用既有）:** `test_constants.gd` TC6/TC8 对 PLAYER_NEON_BLUE / AI_NEON_RED / BG_COLOR 的断言零改动继续通过（本套件**不重复断言**这些值，避免双源）
- **Test F2（套件级）:** run_tests.gd 全量跑通，基线 2214 passed / 0 failed 不回退，新增 TC 后全绿（AC6）

---

## 8. 实现阶段

| Phase | Priority | Components | 说明 |
|:-----:|:--------:|-----------|------|
| Phase 1 | P0 | constants.gd（新增区）、player_paddle.tscn、brick.tscn、neon_glow_material.tres | 视觉配置核心：常量 + 场景引用 + 材质参数（§3.1–3.4）；全部机械改动，无逻辑 |
| Phase 2 | P0 | test_visual_contrast.gd（新）、run_tests.gd（注册行） | 断言套件（§7）+ 注册（§3.5） |
| Phase 3 | P0 | 验证 + 提交 | `godot --path mini-pong/ --headless --quit` 无脚本错误；run_tests.gd 全绿；E2E loop 重跑（§5.4）；`worktree-commit.sh 464 "<msg>" <6 个白名单文件>` → PR（body `Parent #464`）→ CI → review → merge |

---

## 9. 验收条件映射（AC checklist，源自 Issue #464 body）

- [x] **AC1: 玩家板 ≠ 砖块 ≠ 背景（RGB 距离 ≥ 60）** — 验算 324 / 323 / 290（§3.1；Test B1–B3）
- [x] **AC2: 玩家板 vs 背景对比度 ≥ 4:1（WCAG）** — 12.8:1（§3.1；Test C1，`Color.get_luminance()`）
- [x] **AC3: 砖块 vs 玩家板色相分离 ≥ 60°（HSV）** — 157.7°（§3.1；Test D1，`Color.h()`）
- [x] **AC4: brick.tscn ColorRect 显式设置 color** — `color = Color(1, 0.616, 0.271, 1)`（§3.3；Test E2）
- [x] **AC5: 常量可配置，不改动既有逻辑** — 只新增两常量；PLAYER_NEON_BLUE / AI_NEON_RED / BG_COLOR / BG_PULSE_TINT 值不变（§3.1；Test F1）
- [x] **AC6: run_tests.gd 全绿** — 基线 2214 passed / 0 failed 不回退；新套件注册后全绿（Phase 3；Test F2）
- [x] **AC7: PR files 仅含文件域** — 白名单 = constants.gd / player_paddle.tscn / brick.tscn / test_visual_contrast.gd（新）/ run_tests.gd（注册行）+ **assets/neon_glow_material.tres（§3.4 扩展申报，PR 说明根因）**；worktree-commit.sh 白名单 add，绝不 `git add .`

---

## 附: 明确不做（范围边界）

- ❌ `mini-pong/scenes/Main.tscn` / `world_environment.tscn`（BgPulse 已合规，零改动）
- ❌ `paddle.gd` / `brick.gd` / `breakout_grid.gd` / `bg_pulse.gd` / `neon_glow.gdshader`（零改动）
- ❌ `PLAYER_NEON_BLUE` / `AI_NEON_RED` / `BG_COLOR` / `BG_PULSE_TINT` 值（逐字节不动）
- ❌ rain 文件域（#465 并行，零重叠）；❌ HUD/升级 UI 语义色（#392 域）
- ❌ 新增材质实例 / 特效 / 第三方资产（PRD §1.5 调研：第一方实现，零依赖）
- ❌ 本 PR 写 runnable 测试文件（测试代码归 implement PR；本 PR 只含 DESIGN/TASKS 文档）

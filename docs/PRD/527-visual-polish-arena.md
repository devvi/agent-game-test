# PRD: [Feature] 游戏画面迭代 — 雨夜竞技场视觉层补全（城市光晕 / 暗角 / L2 反馈 / 波次色变）

> **Issue:** #527
> **标签:** enhancement, workflow/research, graphics
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** depth/standard（Issue 无 depth 标签，按 #464/#491/#513 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（暗角实现的可测性、色相缓移与 #464 三色分离约束的共存、连续破砖时 tween 叠加表现）而包含 4 个轻量实验，每个子系统一个）
> **所有权:** `content_ownership: taste-draft`（Issue 无机械规格，「更丰富更酷炫」本质是视觉品味议题；基础设施（节点/信号/常量）机械可测，全部取值（光晕颜色/alpha、暗角强度、squash 幅度、色相步长/色序）为 taste-draft，实现合并后进入 status/human-review 由用户定稿）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3 画面方案「雨夜竞技场」（已确认）— L0 氛围层（雨幕粒子 ✅ + 底部城市光晕 ❌ + 暗角 ❌）、L1 世界层（✅）、L2 反馈层（破砖闪光 ❌ / 穿墙脉冲 ❌ / 得分弹出 ❌ / 挡板 squash ❌）、L3 UI 层（✅）；v1 路线图「波次色变」❌
> **并行上下文/范围去冲突:** 视觉类既有 PRD 均已合入且域不同 — #464（静态三色分离）、#465（雨幕修复）、#485（BgPulse 呼吸）、#491（雨量按分数分档）、#504（连击板速机制，非视觉）、#513（暂停 HUD 信息）、#517（e2e 标题主题色断言，测试设施）。本 Issue **不重复**上述任何域：不碰雨幕粒子参数、不碰板/砖静态色值、不碰 HUD 信息布局；只补全主计划中未落地的视觉层。

---

## 1. 问题定义

### 1.1 当前状态

用户诉求：「画面整体再丰富、酷炫一些，现在太简洁了」（Issue #527 body）。主计划 `docs/PLAN-rogue-pong.md` §3 已确认的「雨夜竞技场」四层画面架构，落地情况如下：

| 层 | PLAN §3 规划 | 当前实现 | 状态 |
|----|------------|---------|:---:|
| L0 氛围层 | 雨幕粒子 | `rain_curtain.gd`（#389/#465/#491，动态雨量公式） | ✅ |
| L0 氛围层 | 背景呼吸光 | `bg_pulse.gd`（#449，alpha ∈ [0.01,0.15] 正弦呼吸） | ✅ |
| L0 氛围层 | **底部城市光晕** | **不存在**（grep city/光晕 无结果） | ❌ |
| L0 氛围层 | **暗角（≤10%）** | **不存在**（仅 constants.gd:207 注释提及同量级克制） | ❌ |
| L1 世界层 | 砖墙发光+破洞 | `breakout_grid.gd` + `neon_glow_material.tres` | ✅ |
| L1 世界层 | 球/挡板/拖尾 | `ball_trail.gd`（GPUParticles2D，随速发射） | ✅ |
| L2 反馈层 | **破砖闪光** | **不存在**（brick_destroyed 信号已 emit，无视觉消费方） | ❌ |
| L2 反馈层 | **穿墙脉冲** | **不存在**（RAIN_PULSE_PIERCE=0.4 只作用于雨量，无画面脉冲） | ❌ |
| L2 反馈层 | **得分弹出** | **不存在**（score_changed 只更新 HUD 数字） | ❌ |
| L2 反馈层 | **挡板 squash** | **不存在**（球板碰撞无缩放反馈） | ❌ |
| L3 UI 层 | 霓虹描边/升级卡/波次转场/失败屏 | `ui_neon_style.gd` / `upgrade_pick_ui` / `wave_transition` / `game_over_screen` | ✅ |
| v1 路线图 | **波次色变** | **不存在**（波次切换无色调变化） | ❌ |

**根因（静态证据）**：主计划 §3 的画面架构在 MVP 切片（PLAN §5）只优先实现了「功能必需」子层（雨幕/砖墙/UI）；氛围增强子层（城市光晕/暗角）与反馈子层（破砖闪光/挡板 squash 等）因不阻塞玩法被排后，至今未立项落地。已落地的视觉件全部是「功能件」（雨幕=情绪仪表盘、BgPulse=环境呼吸、三色分离=对比度修复、霓虹描边=UI 可读性），没有一件纯装饰性氛围件 — 这正是「画面太简洁」的直接原因：画面只有功能件，缺少氛围件与反馈件。

### 1.2 预期行为（验收条件，源自 Issue #527 + PLAN §3）

1. **AC1 — 底部城市光晕** — Main.tscn L0 氛围层新增城市光晕节点：屏幕底部霓虹渐变光带（复用 `assets/gradient_neon.tres` 或新建渐变），渲染于世界层与 UI 层之下；静态或 ≤4s 周期微呼吸（与 BgPulse #449 同量级克制）
2. **AC2 — 暗角 ≤10%** — 屏幕四边亮度衰减 ≤10%（PLAN 红线），中心区域零衰减；暂停/菜单状态同样生效（FSM-independent，同 BgPulse #449 惯例）
3. **AC3 — L2 反馈层** — 破砖时砖位闪光（150–300ms Tween，PLAN 动效规范）；挡板击球时 squash（横向拉伸→回弹，≤250ms）；穿墙得分时全屏微脉冲（复用 ScoreFlash 通道，克制）
4. **AC4 — 波次色变** — 每波次切换时氛围层（BgPulse 色调 + 城市光晕色调 + 雨幕 tint）色相缓移（每波 15–30°，taste-draft 色序）；**玩家板/AI 板颜色不变**（#464 三色分离语义不破）
5. **AC5 — 测试全绿** — 新增 `tests/test_visual_polish.gd` 并注册进 run_tests.gd；既有 25+ 套件基线不回退
6. **AC6 — E2E 截图覆盖** — e2e_shots.json 新增/更新视觉 shot（城市光晕/暗角在截图中可见），analyze_bmp.py 断言通过（真实渲染捕获：`--display-driver macos --rendering-driver opengl3`，run-e2e-review.sh:242）
7. **AC7 — 文件域白名单** — PR 仅含本 PRD 文件域文件，不混入其他 issue

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 对打进行中（PLAYING） | 持续 | 底部城市光晕 + 暗角让画面有「雨夜竞技场」纵深感；破砖闪光/挡板 squash 让每一次碰撞有手感 |
| B | 波次切换 | 每波 | 氛围色相缓移 + 波次转场大字，节奏变化「看得见」 |
| C | 穿墙得分 | 每分 | 全屏微脉冲 + 雨量脉冲（既有），得分时刻情绪爆发 |
| D | 暂停/菜单 | 每局多次 | 光晕/暗角持续，画面整体感不被打断；HUD 可读性不受影响 |

### 1.4 技术约束（继承 Issue + 既有架构）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，`mini-pong/`（自有 project.godot，720×1280 竖屏，Forward+，WorldEnvironment glow 0.6 / bloom 0.8） |
| 克制红线 | PLAN §3「克制优先」：暗角 ≤10%；动效统一 Tween 150–300ms，不弹跳不花哨 |
| 颜色红线 | #464 三色分离（PADDLE_NEON 青 / BRICK_NEON 橙 / BG 暗蓝灰，两两 RGB 距离 ≥60）**不破**：波次色变只作用于氛围层色调，板/球静态色不动 |
| 文件域红线 | 不碰 `rain_curtain.gd` 雨量公式（#465/#491 域）、不碰 `player_paddle.tscn`/`brick.tscn` 色值（#464 域）、不碰 `paddle.gd` 速度/连击（#504 域）、不碰 HUD 信息布局（#513 域） |
| constants.gd 纪律 | 只**新增** Visual 新区（CITY_GLOW_* / VIGNETTE_* / FEEDBACK_* / WAVE_HUE_*），既有常量逐字节不动（#448/#449/#450 并行先例） |
| headless | `--headless --quit` 无脚本错误；像素级视觉断言走真实渲染 E2E 捕获（macos + opengl3） |

## 2. 设计意图

### 2.1 为什么当前画面「简洁」

1. **排期决策**：主计划 §3 的画面架构在 MVP 切片里只承诺了「动态雨幕 + 波次转场 + 失败屏」，氛围/反馈增强子层归入 MVP 边界之外的隐性范围 — 功能先行。
2. **已落地件全是功能件**：雨幕（情绪仪表盘 #389）、BgPulse（环境呼吸 #449）、三色分离（对比度修复 #464）、霓虹描边（UI 可读性）— 没有纯装饰性氛围件。
3. **落差即缺口**：用户实测「太简洁了」（#527）与 PLAN §3 架构承诺之间的落差 = 未落地的 L0 增强项（城市光晕/暗角）+ L2 反馈项 + v1 波次色变。

### 2.2 为什么现在做

- 玩法层（砖墙/双得分/波次/升级）已合入 main，视觉功能件已稳定 — 在稳定地基上加氛围件，符合「体验引擎-依赖栈分析」模式（先验证机制再制作表现，Obsidian 知识库 `wiki/体验引擎-patterns.md` 模式 8）。
- E2E 真实渲染捕获设施已可用（run-e2e-review.sh:242），新增视觉层可被截图断言覆盖，无「无法验证」的技术阻塞。
- Obsidian 知识库佐证（`wiki/CUSGA 2026 游戏评选笔记.md`）：画面完整度/视觉反馈是独立游戏评价的核心维度（「画面风格完整」「视觉反馈好」），与本 Issue 诉求一致；同时 `体验引擎-patterns.md` 模式 7「抽象留白」提示克制优先 — 视觉丰富不等于堆料，PLAN 的克制红线（暗角 ≤10%、150–300ms 动效）是正确边界。

### 2.3 既有约束（PLAN §3 已确认，继承）

| 约束 | 详情 |
|------|------|
| 分层架构 | L0 氛围 < L1 世界 < L2 反馈 < L3 UI（CanvasLayer 顺序） |
| 克制优先 | 暗角 ≤10%；动效 150–300ms；不弹跳不花哨 |
| 配色 | 雨夜霓虹赛博基因（PONG://NEON），三色分离 #464 已定稿 |
| 视觉断言 | L3 走 analyze_bmp.py（真实渲染截图，主题色/帧间差异断言） |

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/scenes/Main.tscn` | 场景组装 | 修改：AtmosphereLayer（L0）下新增 CityGlow/Vignette 节点；L2 反馈控制器挂载 |
| `mini-pong/gdscripts/constants.gd` | 全局常量 | 修改：**新增** Visual 区（只增不改） |
| `mini-pong/gdscripts/city_glow.gd` | 氛围层 | **新建**：底部光晕控制器（渐变 + 微呼吸） |
| `mini-pong/gdscripts/vignette.gd` | 氛围层 | **新建**：暗角控制器（四边渐变遮罩） |
| `mini-pong/gdscripts/feedback_effects.gd` | 反馈层 | **新建**：破砖闪光 + 挡板 squash + 穿墙脉冲（Tween 驱动） |
| `mini-pong/gdscripts/wave_controller.gd` | 波次循环 | 修改：波次切换时驱动氛围色调相缓移（或由 breakout_grid.wall_generated 触发） |
| `mini-pong/gdscripts/bg_pulse.gd` | 氛围层 | 修改：暴露 tint 读写接口（波次色变消费；不改呼吸逻辑） |
| `mini-pong/tests/test_visual_polish.gd` | 测试 | **新建**：AC1–AC4 断言 |
| `mini-pong/tests/run_tests.gd` | 测试 | 修改：注册新套件（仅注册行） |
| `mini-pong/e2e_shots.json` | E2E | 修改：新增/更新视觉 shot |

### 3.2 新建文件

| 文件 | 用途 |
|------|------|
| `mini-pong/gdscripts/city_glow.gd` | 城市光晕控制器 |
| `mini-pong/gdscripts/vignette.gd` | 暗角控制器 |
| `mini-pong/gdscripts/feedback_effects.gd` | L2 反馈效果控制器 |
| `mini-pong/tests/test_visual_polish.gd` | 视觉补全测试套件 |

### 3.3 间接影响

| 模块 | 影响 |
|------|------|
| `bg_pulse.gd` | 波次色变驱动 BgPulse 色调 → 暴露 tint 读写接口（小改，不改呼吸逻辑/常量） |
| `breakout_grid.gd` | 已 emit `brick_destroyed`/`wall_cleared`/`wall_generated` — 反馈层与色变只消费信号，**不改 grid** |
| `ball.gd` / `paddle.gd` | 挡板 squash 触发点：球-板碰撞事件（消费侧新增发射，不改物理逻辑） |
| `rain_curtain.gd` | 波次色变若涉及雨幕 tint → 需暴露 tint 接口；**红线：不改雨量公式**（#465/#491 域） |
| `assets/gradient_neon.tres` | 复用（蓝→橙渐变已存在）；如需底部专用渐变则新建，不改原资产 |

### 3.4 数据流（信号链）

```
breakout_grid.brick_destroyed(brick, pos)
    │
    ├──► feedback_effects._on_brick_destroyed()  → 砖位闪光 Tween (150-300ms)   ← 新增
    │
breakout_grid.wall_cleared()
    ├──► feedback_effects._on_wall_cleared()     → 全屏微脉冲 (复用 ScoreFlash) ← 新增
    │
球-板碰撞 (ball.gd / paddle.gd 消费侧)
    ├──► feedback_effects._on_paddle_hit()       → 挡板 squash Tween (≤250ms)   ← 新增
    │
wave_controller / wall_generated(remaining)
    ├──► 氛围 tint 色相缓移 (1-2s Tween: BgPulse/光晕/雨幕)                     ← 新增
```

### 3.5 需更新的文档

- [x] `docs/PRD/527-visual-polish-arena.md`（本文件）
- [ ] `docs/TASTE.md` — taste-draft 取值定稿记录（实现后）
- [ ] PLAN-rogue-pong §3 落地状态勾选（可选）

## 4. 方案对比

> Issue #527 覆盖多个独立视觉子系统，按多子系统 PRD 规则（Patch 19）将 Section 4 细分为 4.1–4.4，各自独立方案对比。

### 4.1 子系统 1：底部城市光晕（L0）

**方案 A：CanvasLayer 渐变 ColorRect（推荐）**
- 描述：AtmosphereLayer（L0）内新增 TextureRect/ColorRect + `gradient_neon.tres`（蓝→橙渐变已存在）或新建 GradientTexture2D；贴底对齐，高度 ≈ 屏高 25%；alpha 基线 0.2 + 4s 周期微呼吸（复用 BgPulse 呼吸模式）
- Pros：零 shader 编译风险（headless 安全）；复用现有资产；节点属性可直接被 L2 测试断言；与 BgPulse 同实现范式（ColorRect + alpha 驱动）
- Cons：静态渐变不如 shader 灵动；无法做流动/透视细节
- Risk：Low ｜ Effort：0.5–1 天

**方案 B：全屏 CanvasItem shader 按 UV.y 渐变**
- Pros：可做流动/闪烁细节，观感上限高
- Cons：新增 shader 编译面；headless 编译错误需额外防护；像素级断言弱（无法直接断言 shader 输出）
- Risk：Med ｜ Effort：1–2 天

**方案 C：GPUParticles2D 城市灯光点阵**
- Pros：灯光闪烁动态感强
- Cons：粒子 amount/性能开销；与「克制优先」相悖风险；断言困难
- Risk：Med ｜ Effort：1–2 天

**推荐 A**：理由 — (1) 克制红线下静态渐变 + 微呼吸已足够「丰富」；(2) 与既有 BgPulse 实现范式一致，plan/implement 阶段风险最低；(3) 节点属性可测（AC1 可直接断言）。

### 4.2 子系统 2：暗角 Vignette（L0）

**方案 A：四边 ColorRect 渐变叠加（推荐）**
- 描述：上/下/左/右四条渐变遮罩（边缘 alpha 0.08–0.10，向内衰减到 0），中心区域无覆盖；静态无动画
- Pros：无 shader；alpha 值即断言对象；与 PLAN「暗角 ≤10%」字面对应
- Cons：4 个节点略啰嗦；渐变分辨率受 ColorRect 尺寸限制（竖屏 720×1280 下足够）
- Risk：Low ｜ Effort：0.5 天

**方案 B：全屏暗角 shader**
- Pros：单节点、连续过渡更自然
- Cons：shader 编译面 + 像素断言弱（analyze_bmp 无区域亮度断言能力）
- Risk：Med ｜ Effort：1 天

**方案 C：WorldEnvironment 参数模拟（不做暗角）**
- 描述：仅靠既有 glow/bloom 营造暗角错觉
- Pros：零实现成本
- Cons：不满足 Issue 诉求（画面丰富度无实质提升）
- Risk：Low（但不达标）｜ Effort：0

**推荐 A**：理由 — 暗角强度是克制红线（≤10%），四边渐变完全够用且每一边可独立断言；无 shader 风险。

### 4.3 子系统 3：L2 反馈层（破砖闪光 / 挡板 squash / 穿墙脉冲）

**方案 A：纯 Tween 控制器（推荐）**
- 描述：`feedback_effects.gd` 消费既有信号（brick_destroyed / wall_cleared / 球板碰撞）：破砖 → 砖位 modulate 白闪 150–300ms 回落；击板 → paddle scale.x 1.15 → 1.0（200ms，ease_out）；穿墙 → 复用 ScoreFlash 通道全屏微脉冲。全部 Tween，无 shader
- Pros：与 PLAN「统一 Tween 淡入/滑入 150–300ms」规范完全一致；连续事件 kill/restart 幂等；节点属性可测
- Cons：表现上限低于粒子/shader
- Risk：Low ｜ Effort：1–2 天

**方案 B：破砖碎片 GPUParticles2D**
- Pros：破砖时刻「碎裂感」更强
- Cons：粒子性能 + 断言难；「克制优先」风险；与升级选择等场景叠加时可能视觉过载
- Risk：Med ｜ Effort：2 天

**方案 C：shader 闪光（brick 增加 flash uniform）**
- Pros：闪光质感细腻
- Cons：需改 brick 材质链（触碰 #464 材质域风险）；shader 编译面
- Risk：Med ｜ Effort：2 天

**推荐 A**：理由 — 反馈层核心是「及时、克制、可测」，Tween 方案三者全占；方案 B 记录为 v1.1 可选增强（§6.2），不进本 Issue 文件域。

### 4.4 子系统 4：波次色变（v1 路线图）

**方案 A：氛围层色相缓移（推荐）**
- 描述：每波 `wall_generated` 时，对 BgPulse 色调 / 城市光晕色调 / 雨幕 tint（若暴露接口）做 hue 缓移 15–30°（1–2s Tween）；**玩家板/AI 板/球色不动**（#464 语义色保持）
- Pros：视觉变化显著但克制；不触碰 #464 三色分离断言（板/球色不变）；taste-draft 色序可后期调
- Cons：需要 BgPulse/雨幕暴露 tint 读写接口（小改）
- Risk：Low–Med（接口改动面）｜ Effort：1–2 天

**方案 B：每波静态切换主题色**
- Pros：实现最简单
- Cons：无过渡动画，切换突兀；观感「换皮」而非「渐变」
- Risk：Low ｜ Effort：0.5 天

**方案 C：不纳入本 Issue（defer v1.1）**
- Pros：本 Issue 范围最小
- Cons：波次色变是「酷炫」诉求的高性价比来源，推迟则 Issue 完成度打折
- Risk：Low ｜ Effort：0

**推荐 A**：理由 — 波次色变直接回应「酷炫」诉求，与波次转场（大字+副句）形成节奏递进；只动氛围层保住了 #464 红线。

### 4.5 推荐汇总

| 子系统 | 推荐方案 | 核心文件 | 风险 | 努力 |
|--------|---------|---------|:---:|:---:|
| 城市光晕 | A: CanvasLayer 渐变 ColorRect | `city_glow.gd`（新）+ Main.tscn | Low | 0.5–1 天 |
| 暗角 | A: 四边渐变遮罩 | `vignette.gd`（新）+ Main.tscn | Low | 0.5 天 |
| L2 反馈 | A: Tween 控制器 | `feedback_effects.gd`（新）+ Main.tscn | Low | 1–2 天 |
| 波次色变 | A: 氛围层色相缓移 | `wave_controller.gd`（改）+ `bg_pulse.gd`（tint 接口） | Low–Med | 1–2 天 |

## 5. 边界条件与验收标准

### 5.1 验收条件（映射 Issue #527）

- [x] **AC1: 城市光晕可见** — Main.tscn 含 CityGlow 节点（L0 层，位于世界/UI 之下）；截图 shot 中底部存在霓虹渐变带；节点属性（基线 alpha、周期）与 constants 一致
  - 验证：test_visual_polish.gd 节点存在 + 属性断言；E2E 截图帧间差异含底部区域变化
- [x] **AC2: 暗角 ≤10%** — 四边遮罩边缘 alpha ∈ [0.05, 0.10]；中心区域无遮罩
  - 验证：constants 断言 + 节点 alpha 断言（±0.005 容差）
- [x] **AC3: L2 反馈** — 破砖触发砖位闪光（150–300ms Tween）；球板碰撞触发 paddle squash（≤250ms）；穿墙触发全屏微脉冲
  - 验证：mock 事件 → 断言 Tween 目标值/时长（信号发射测试）
- [x] **AC4: 波次色变** — 每波切换氛围层 hue 偏移 15–30°；玩家板/AI 板颜色不变
  - 验证：波次切换后 BgPulse tint hue 断言；player_paddle.tscn color 断言不变（#464 回归）
- [x] **AC5: 测试全绿** — run_tests.gd 注册 test_visual_polish 后全绿；既有基线不回退
- [x] **AC6: E2E 覆盖** — e2e_shots.json 新增视觉 shot；analyze_bmp.py 断言通过
- [x] **AC7: 文件域白名单** — PR 仅含 §3.1/§3.2 文件域文件

### 5.2 边界情况（≥5）

1. **headless 编译**：新脚本在 `--headless --quit` 下无错误；本 PRD 已规避 shader 方案（全部 ColorRect/Tween）
2. **竖屏布局**：光晕贴底（y 对齐 1280 底部），暗角四边适配 720×1280；HUD 位于底部 → 光晕必须在 HUD（L3）之下
3. **连续破砖**：多砖同帧破碎（清墙瞬间）→ Tween 必须 kill/restart 幂等，不叠加错乱
4. **暂停/菜单状态**：光晕/暗角 FSM-independent（同 BgPulse #449 惯例），暂停时静帧不闪动
5. **波次色变 × #464**：氛围层 hue 偏移不得改变板/球静态色；若砖色参与偏移，需保持与板色 RGB 距离 ≥60（或砖色不动，仅氛围层动）
6. **E2E 帧间差异基线**：暗角/光晕是静态层，帧间差异只来自动态元素 → 既有断言阈值不受影响，但新 shot 需重新校准基线
7. **低端设备**：无粒子增强（方案 C 已排除），ColorRect/Tween 开销可忽略

### 5.3 失败路径（≥3）

1. **渐变资产加载失败** → onready null 检查 + push_warning 降级（同 ball_trail.gd 模式）
2. **Tween 被高频事件打断** → 统一 `_tween.kill()` 后重建，幂等
3. **E2E 截图断言超时** → shot 门控（节点存在 + 属性值条件，同 #491 current_rain 门控模式）
4. **色相缓移越界** → hue 偏移 clamp [0, 360)，且每波累计偏移设上限（防多波后色相漂移失控）

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|:---:|
| #464 三色分层（颜色语义基座） | ✅ CLOSED（main） | Low |
| #449 BgPulse（呼吸范式 + tint 接口改造点） | ✅ CLOSED（main） | Low |
| #389/#465/#491 雨幕系统（波次色变 tint 接口改造点） | ✅ CLOSED（main） | Low–Med（只加 tint 接口，不改雨量公式） |
| E2E 真实渲染捕获（run-e2e-review.sh:242） | ✅ main 可用 | Low |

### 6.2 阻塞（未来工作）

| 未来工作 | 优先级 | 说明 |
|---------|:---:|------|
| v2 城市天际线剪影（PLAN §5） | 中 | 本 Issue 的城市光晕是其地基（光带 → 剪影） |
| v1.1 破砖碎片粒子增强 | 低 | §4.3 方案 B 记录在案，不进本 Issue 文件域 |

### 6.3 依赖链

```
#464 三色分离 ──► #449 BgPulse ──► 本 Issue #527（视觉层补全）
        └──► #389/#465/#491 雨幕 ──┘          └──► v2 天际线（未来）
```

### 6.4 准备事项

- [x] 确认 E2E 捕获命令（`--display-driver macos --rendering-driver opengl3`）
- [x] 确认既有信号钩子（brick_destroyed / wall_cleared / wall_generated）
- [ ] taste-draft 取值清单待用户定稿（§8.4）

## 7. Spike / 实验

> 按多子系统规则（Patch 19）：每个子系统一个实验 + 集成验证。

**E1 — 城市光晕取值与克制平衡**
- 问题：渐变基线 alpha 与呼吸周期取何值，在 E2E 截图中「可见」又不越克制红线？
- 方法：实现方案 A 原型，取 alpha ∈ {0.15, 0.2, 0.25} × 周期 ∈ {3s, 4s, 6s}，各跑一帧真实渲染截图对比
- 预期结果：alpha 0.2 / 周期 4s（与 BgPulse 同周期）为推荐档；截图底部可见渐变带
- 影响：定稿 constants 取值，写入 §8.4 供用户确认

**E2 — 暗角实现的可测性验证**
- 问题：四边 ColorRect（方案 A）在真实渲染截图中的边缘变暗能否被 analyze_bmp 断言？（现有断言只有主题色/帧间差异/色数）
- 方法：实现后截图，比较边缘行 vs 中心行亮度；验证像素级断言可行性；若不可行，降级为节点属性断言
- 预期结果：边缘亮度衰减可测（或明确不可测 → 用节点 alpha 断言兜底）
- 影响：决定 AC2 的验证方式与 e2e 断言写法

**E3 — 连续破砖时 Tween 叠加表现**
- 问题：同帧多砖破碎（清墙瞬间）时，kill/restart 策略是否产生闪烁或漏闪？
- 方法：构造 10 砖同帧销毁测试，观察闪光一致性
- 预期结果：统一 kill + 单控制器串行队列可稳定表现
- 影响：定稿 feedback_effects 的 Tween 管理结构

**E4 — 波次色相缓移与 #464 共存验证**
- 问题：氛围层 hue 偏移 15–30° 后，砖/板/背景的 RGB 距离是否仍满足 #464 ≥60 约束？
- 方法：对 PADDLE_NEON/BRICK_NEON/BG_COLOR 施加 hue 偏移并计算两两 RGB 距离（脚本验算，同 #464 §1.2 方法）
- 预期结果：板色不动、砖色同步偏移时距离保持 ≥60（验算确认或调整偏移上限）
- 影响：定稿波次色变的作用域（只动氛围 vs 动砖色）

## 8. 延续上下文

### 8.1 系统状态

- 主分支 main：雨夜竞技场 MVP 已合入（砖墙/双得分/波次/升级/动态雨幕/霓虹 UI），E2E 真实渲染捕获可用
- 本 PRD 不引入新依赖、不改玩法逻辑；全部改动在视觉层（L0 氛围 + L2 反馈 + v1 波次色变）

### 8.2 给 plan agent 的文件级交接

| 文件 | 动作 | 要点 |
|------|------|------|
| `constants.gd` | 改（只增） | 新增 Visual 区：CITY_GLOW_BASE_ALPHA / CITY_GLOW_PERIOD / VIGNETTE_EDGE_ALPHA / FEEDBACK_FLASH_MS / FEEDBACK_SQUASH_SCALE / WAVE_HUE_STEP_DEG 等；既有常量不动 |
| `city_glow.gd` + Main.tscn | 新建 | L0 底部渐变 + 微呼吸（复用 gradient_neon.tres 或新渐变），挂 AtmosphereLayer，HUD 之下 |
| `vignette.gd` + Main.tscn | 新建 | 四边渐变遮罩，alpha ≤0.10，静态 |
| `feedback_effects.gd` + Main.tscn | 新建 | 消费 brick_destroyed / wall_cleared / 球板碰撞 → Tween 闪光/squash/脉冲；kill/restart 幂等 |
| `wave_controller.gd` / `bg_pulse.gd` | 改 | 波次切换 → 氛围 tint hue 缓移 15–30°（1–2s）；bg_pulse 暴露 tint 读写；**不碰雨量公式** |
| `test_visual_polish.gd` + run_tests.gd | 新建/改 | AC1–AC4 断言 + 注册行 |
| `e2e_shots.json` | 改 | 新增视觉 shot（光晕/暗角可见帧） |

### 8.3 红线清单（implement 必须遵守）

- ❌ 不改 `rain_curtain.gd` 雨量公式（#465/#491 域）
- ❌ 不改 `player_paddle.tscn` / `brick.tscn` 静态色值（#464 域）
- ❌ 不改 `paddle.gd` 速度/连击逻辑（#504 域）
- ❌ 不改 HUD 信息布局（#513 域）
- ✅ 动效一律 Tween 150–300ms；暗角 ≤10%

### 8.4 taste-draft 取值清单（实现后交用户定稿）

| 参数 | 建议值 | 可调范围 |
|------|--------|---------|
| 城市光晕基线 alpha | 0.2 | 0.15–0.25 |
| 城市光晕呼吸周期 | 4s | 3–6s |
| 暗角边缘 alpha | 0.08 | 0.05–0.10 |
| 破砖闪光时长 | 180ms | 150–300ms |
| 挡板 squash 幅度 | 1.15 | 1.10–1.20 |
| 波次 hue 步长 | 20°/波 | 15–30°/波 |

> 交接说明：plan agent 无需重新扫描源码 — 所有钩子（信号/节点/资产）与红线已在本 PRD 列全；taste-draft 取值实现时用建议值，合并后按 content_ownership: taste-draft 流程进入 status/human-review 由用户定稿。

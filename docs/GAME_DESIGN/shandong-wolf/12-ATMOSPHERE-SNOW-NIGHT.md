# 雪夜氛围层 — 单 CanvasModulate 冷月光契约（#582/#624）

> 落盘依据：PR #629（fix，已 merge 2026-08-19）← DESIGN `docs/DESIGN/624-snow-night-atmosphere-regression.md`；
> 上游：#582 雪夜氛围（PRD/DESIGN，taste-draft 待用户定稿）。
> ⚠️ 载体说明：氛围代码落地于 **impl/582-snow-night-atmosphere 分支**（main 上无氛围代码；
> 修复后 #613 重新 review + #582 taste-draft 裁决后随 582 上 main）。本章记录的是**设计契约**
> ——机械部分（moon 数量/层归属/守卫）已由 #629 定稿；常量色值仍属 taste 域（`# DRAFT`，归 #582 用户裁决）。

## 1. 设计意图

**问题本质是「一个被误判的缺陷引发了一次错误的修复」。** #582 原设计只有 1 个 Moonlight 挂
Atmosphere 根（layer 0），但当时可见内容全在 layer 1-10、layer 0 无物可染 → round 1 review
误判「冷月光无效果」为缺陷 → #613 self-correct R1 为满足 AC2 给每个可见 CanvasLayer 各挂一个
moon（atmosphere 内 6 个 + Main.tscn UI 层 1 个 = 7 个）。PRD #624 实测确认 **CanvasModulate
只调制其所在 CanvasLayer 的内容，多个 moon 逐层累积相乘**——7 个 moon 把雪幕白粒子压到 120
（近黑背景上不可见）、血色 α 压到 0.165、layer 0 Backdrop luma 36→17（近黑）。#624 修复 =
回退 + 契约化，**不是重构**。

设计哲学四条（#624 DESIGN 定稿）：
1. **月光 = 世界光**：冷月光只染「大地」（layer 0 世界层，AC2）；雪幕（必须白）、水墨（自带暗角）、
   血色（唯一高饱和例外）、UI（可读性）全部**不放 moon**——保持原始亮度与饱和度。
2. **单一事实源**：1 个 moon（`MOONLIGHT_COLOR_APPLIED`）+ 1 个背景色常量（`NIGHT_BG_COLOR`）；
   `_apply_moonlight()` 从 `find_children` 遍历回退为单节点直接赋值——删掉「每层设色」这个错误的控制面。
3. **结构守卫防再犯**：test_atmosphere C3 语义 180° 反转——「全组件仅 1 个 moon 且位于 layer 0」，
   任何 future agent 给雪幕/血色/UI 层加 moon 都会被测试拦截。
4. **渲染断言分级**：机械断言（moon A/B 亮度比 ≈ 0.471、雪白像素存在、血 A/B diff、UI 白字亮度）
   不依赖 taste 值；taste 依赖断言（`--theme 6e7684` 命中与否）随 `NIGHT_BG_COLOR` 定稿——
   两级口径写入 e2e_shots.json 注释，避免断言随品味值漂移。

## 2. 架构决策

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|--------------|---------|---------|
| moon 数量 | 全场景**唯一 1 个**（挂 Atmosphere 根，layer 0 世界层） | B: 白 moon 占位结构欺骗 / C: screen texture 全屏 shader | 7 moon 逐层相乘压暗雪幕/血色（PRD §1.3 实测）；B 是架构债；C 在 Compatibility 渲染器三重不确定 |
| 层归属 | 雪幕(3-5)/水墨(2)/血色(10)/UI(1) 禁放 moon | 每可见层一 moon（#613 语义） | CanvasModulate 只染自身层，多层相乘破坏原亮度 |
| 夜色背景 | WorldBackdrop（layer 0 ColorRect，`NIGHT_BG_COLOR` 单一事实源） | 无背景（round 1 状态） | layer 0 无物可染 → AC2 不成立（「冷月光无效果」误判根源） |
| 守卫 | C3 语义反转：`find_children("CanvasModulate")` 总数 == 1 + 层归属/颜色/Main.tscn 文本守卫 | 每可见层必须有 moon（#613 语义） | 防再犯：任何给氛围/UI 层加 moon 的改动被 CI 拦截 |
| 色值 | `NIGHT_BG_COLOR` # DRAFT 候选集（首选 #d8dce4） | 单方面定稿 | taste 域归 #582 用户裁决；本设计只定约束（染后 luma ≥ 30）不定值 |

## 3. 层契约与节点树

### 3.1 CanvasLayer 层级约定（#582 定稿，atmosphere_controller.gd 头部注释）

| layer | 内容 | 允许 Moonlight | 理由 |
|:---:|------|:---:|------|
| 0 | 世界层（WorldBackdrop / 未来 #583 战斗场景几何） | ✅ 唯一 moon 在此 | 月光只染世界（AC2） |
| 1 | UI（标题/字幕/版本/探针） | ❌ 禁染 | 白字对比度（F4） |
| 2 | 水墨晕染 | ❌ 禁染 | 自带暗角 |
| 3-5 | 雪幕（远/中/近） | ❌ 禁染 | 必须纯白（F1） |
| 10 | 血色 vignette | ❌ 禁染 | 唯一高饱和例外（F2） |

### 3.2 节点树（atmosphere_layer.tscn，修复后）

```text
Atmosphere (Node2D, atmosphere_controller.gd)
├── Moonlight (CanvasModulate, color=MOONLIGHT_COLOR_APPLIED)   ← 唯一 moon，layer 0
├── SnowCurtain (Node2D, snow_curtain.gd)
│   ├── LayerFar  (CanvasLayer, layer=3) ── Parallax ── Particles   [moon 已删]
│   ├── LayerMid  (CanvasLayer, layer=4) ── Parallax ── Particles   [moon 已删]
│   └── LayerNear (CanvasLayer, layer=5) ── Parallax ── Particles   [moon 已删]
├── InkWashLayer (CanvasLayer, layer=2) ── InkWash (ColorRect)      [moon 已删]
└── BloodVignette (CanvasLayer, layer=10, blood_vignette.gd)
    └── BloodRect (ColorRect)                                       [moon 已删]
```

**红线遵守：** 粒子 `amount`（60/60/80）、Parallax2D `scroll_scale`、粒子材质、水墨/血色 shader
与 α 上限**全部零改动**（PRD §8 红线）；Main.tscn 现有 UI 节点零改动（仅删其下 moon）。

### 3.3 运行时控制面（atmosphere_controller.gd）

```gdscript
## 冷月光契约（#624 修复）: CanvasModulate 只调制其所在 CanvasLayer 的内容，
## 多 moon 逐层相乘会把雪幕/血色压没（PRD #624 §1.3 实测根因）。
## 本组件**唯一** Moonlight 挂在 Atmosphere 根（layer 0 世界层），只染世界内容；
## 雪幕(3-5)/水墨(2)/血色(10) 层禁放 moon —— test_atmosphere C3 守卫 == 1 拦截复犯。
func _apply_moonlight() -> void:
    _moonlight.color = moonlight_color
```

其余接口（`set_low_health` / `debug_trigger_low_health` / `debug_clear_low_health` /
`get_visual_alpha()`）契约面保持——与 #576 HUD 的 low_health 链路（10-HUD-STANCE-BARS.md）零改动对接。

## 4. 氛围常量（#582/#624，载体 impl/582 分支）

> 分区位于 constants.gd「冷月光 / 夜色世界背景 / 水墨晕染 / 血色 vignette」段，全部 `# DRAFT`
> 候补值，定稿归 #582 用户裁决；`BLOOD_VIGNETTE_LAYER` 为机械常量（层级约定，定稿）。

| 常量 | 候补值 | 语义 |
|------|--------|------|
| `MOONLIGHT_COLOR_TARGET` | `#b8c4d9` | AC2 目标色温（只狼苇名城雪夜） |
| `MOONLIGHT_COLOR_APPLIED` | `#6e7684` | = TARGET × 0.6 换算（CanvasModulate 无独立 brightness） |
| `MOONLIGHT_BRIGHTNESS` | `0.6` | 色值换算系数（A/B 亮度比 ≈ 0.471 断言依据） |
| `NIGHT_BG_COLOR` | `#d8dce4`（候选集 #d8dce4 / #4e5464 / #0d1520否决） | layer 0 夜色垫底；染后 ≈ #66686b 命中 theme 断言；约束染后 luma ≥ 30 |
| `INK_EDGE_ALPHA_MAX` | `0.3` | 水墨暗角硬上限 |
| `INK_COLOR` / `INK_INNER_RADIUS` / `INK_SOFTNESS` / `INK_NOISE_AMOUNT` | `#1a1f26` / `0.62` / `0.35` / `0.06` | 水墨质感参数 |
| `BLOOD_VIGNETTE_ALPHA_MAX` | `0.35` | 低血触发 α 硬上限 |
| `BLOOD_VIGNETTE_FADE_SECONDS` | `0.5` | Tween 时长 |
| `BLOOD_VIGNETTE_LAYER` | `10` | 机械常量（层级约定，定稿） |

## 5. 数据流

### Flow 1: 正常路径 — 修复后单 moon 渲染（Main.tscn 首启）

```text
Main 首帧
  ├─ WorldBackdrop(layer0, NIGHT_BG_COLOR #d8dce4) ──× 唯一 Moonlight(#6e7684) ──► ≈ #66686b 冷蓝灰夜色（AC2）
  ├─ 雪幕 Particles(layer3-5, 白 α0.7-0.9) ──无 moon──► 纯白粒子在夜色上可见（F1 修复）
  ├─ 水墨 InkWash(layer2) ──无 moon──► 暗角原样（edge_alpha ≤ 0.3）
  ├─ 血色 BloodVignette(layer10) ──无 moon──► low_health 触发时饱和红 α≤0.35 可见（F2 修复）
  └─ UI(layer1, 白字 255) ──无 moon──► 对比度恢复（F4 修复）
```

### Flow 2: 验证路径 — 月光 A/B 亮度比（机械断言，不依赖 taste 值）

关 moon（color 改白）→ 截 A 图采样背景区 luma_a；开 moon（#6e7684）→ 截 B 图采样 luma_b；
断言 `luma_b / luma_a ≈ 0.471 ± 10%`（MOONLIGHT_BRIGHTNESS）——证明唯一 moon 确实在
layer 0 且只染世界层，与背景色取值无关。

### Flow 3: 边界路径 — 雪幕层被误加 moon（防再犯）

future agent 给 LayerNear 加 CanvasModulate → C3-1 总数守卫 `find_children` 总数 2 ≠ 1 →
FAIL → CI 拦截；C3-2 层归属 / C3-3 颜色 / C3-4 Main.tscn 文本守卫兜底。

## 6. 渲染断言分级（e2e_shots.json 口径）

| 断言 | 级别 | 内容 |
|------|:---:|------|
| moon A/B 亮度比 ≈ 0.471 | 机械 | 不依赖 taste 值，机制验证（Flow 2） |
| 雪白像素存在（≥200 lum） | 机械 | snow_night 截图计数 > 0（AC1） |
| 血触发红像素 A/B diff | 机械 | debug_trigger_low_health 前后截图 diff（AC3） |
| UI 白字 ≥ 200 lum | 机械 | F4 验证（AC5） |
| `--theme 6e7684` 命中 | taste 依赖 | 随 NIGHT_BG_COLOR 定稿；深色候选则改 shot 级 `null` + A/B 亮度比断言（AC2） |

## 7. 边界情况

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | layer 0 无内容（#583 战斗场景落地前） | WorldBackdrop / capture Backdrop 垫底保证 AC2 有物可染 |
| 2 | 背景色候选过暗（#0d1520）复现近黑（F3） | 机械约束染后 luma ≥ 30 + S3 实测拦截；候选集已标注否决候选 |
| 3 | 雪幕层被误加 moon（调参误触） | C3-1 总数守卫（==1）+ C3-4 Main.tscn 文本守卫 |
| 4 | 删 moon 时误删唯一根 moon | C3-1 ==1 拦截（0 ≠ 1）+ C1 用例（根 moon 存在） |
| 5 | Compatibility vs Forward+ 渲染器层作用域语义差异 | 项目 CI/E2E 固定 Compatibility；差异需开新 issue 验证，不静默假设 |
| 6 | E2E 分辨率漂移导致像素断言失效 | 断言口径按实际分辨率适配；snow_night 官方截图需重出（旧图 luma 15.6 作废） |
| 7 | stick_figure 组 theme 断言被染坏 | per-shot `theme_color: null` 跳过 theme，帧间 --diff-with 断言保留验证力 |

## 8. 集成点

| 集成 | 本组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| 单 moon 守卫 | test_atmosphere C3（C3-1~C3-5） | #624 | 结构断言拦截复犯（==1） | ✅ #629 已落地 |
| 层契约注释 | atmosphere_controller.gd 头部 | #583 | #583 复用 .tscn 时照契约放世界几何 | ⬜ 文档层 |
| WorldBackdrop / Backdrop | Main.tscn + capture.tscn | #582 AC2 | layer 0 垫底供月光染色 | ⬜ 待 #613 re-review + 定稿后随 582 上 main |
| snow_night 像素断言 | e2e_shots.json | #586 | 完整剧本纳入月/雪/血像素断言 | ⬜ 注释先行 |
| 修复载体 | impl/582-snow-night-atmosphere 分支 | #613（PR） | 修复落分支 → 重新 review + taste-draft | ⬜ 待裁决 |

## 9. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #624 | 雪夜氛围回归修复（本文件所属；单 CanvasModulate 层契约） | 已合并（#629，落 impl/582 分支） |
| #582 | 雪夜氛围（上游设计；NIGHT_BG_COLOR 等 taste 值定稿归此） | 草稿已合并，待用户定稿 |
| #613 | 雪夜氛围 implement PR（被 #624 阻塞，修复后重新 review） | 阻塞中（修复已并入其载体分支） |
| #576 | HUD（low_health 信号源 → 血色 vignette 消费链路，10 章） | 已合并（#627） |

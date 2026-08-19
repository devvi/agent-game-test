# Design: [Rendering] 修复 #613 雪夜氛围回归 — 单 CanvasModulate 层契约（雪幕/血色/冷月光像素级还原）

> **Parent Issue:** #624（bug / priority/high）
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4 **方案 A 确认采纳** —— 回退 #613 self-correct R1 的「每可见层一 moon」结构（7 个 CanvasModulate）→ **唯一 Moonlight 挂 Atmosphere 根（layer 0 默认画布）** + Main.tscn 补 layer 0 夜色世界背景（NIGHT_BG_COLOR，# DRAFT 候选集）；否决方案 B（白 moon 占位结构欺骗，架构债）与方案 C（screen texture 全屏 shader，Compatibility 渲染器三重不确定）
> **Reference PRD:** `docs/PRD/624-snow-night-atmosphere-regression.md`（research PR #625 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/582-snow-night-atmosphere.md`（CanvasModulate **单节点** #6e7684 原设计 + 层契约 1=UI / 2=水墨 / 3-5=雪幕 / 10=血色——#613 的「每层一 moon」是背离而非演进）
> **修复目标载体:** `impl/582-snow-night-atmosphere` 分支（PR #613，head `51d3083`）—— **main 上无任何氛围代码**，本设计描述的是该分支上文件的修复契约；修复落地后 #613 重新 review + taste-draft 裁决（#582 AC5）
> **所有权:** `content_ownership: mechanical`（结构修复 = 机械工程：moon 数量收敛 7→1、层归属、`CanvasModulate==1` 守卫、A/B 亮度比断言——机械定稿；`NIGHT_BG_COLOR` 色值为 **# DRAFT 候选集**，taste 域归 #582 用户裁决，本设计只定约束不定值）
> **深度:** standard（无 depth label；7 文件变更 < 10 → **仅产出 DESIGN**，不产 TASKS）
> **并行上下文:** 修复文件全部位于 impl/582 分支（main 无氛围代码），与 main 上并行 issue（#575/#576/#577）零交集；constants.gd 为**追加式新增** `NIGHT_BG_COLOR`（不触碰既有氛围分区任何常量行）

---

## 1. 架构总览

**问题本质是「一个被误判的缺陷引发了一次错误的修复」。** #582 原设计（`9a87815`）只有 1 个 Moonlight 挂 Atmosphere 根（layer 0），但当时可见内容全在 layer 1-10，layer 0 无物可染 → round 1 review 误判「冷月光无效果」为缺陷；#613 self-correct R1（`7e88741`）为满足 AC2 在每个可见 CanvasLayer 各挂一个 moon（atmosphere 内 6 个 + Main.tscn UI 层 1 个 = 7 个）。PRD 实测确认 **CanvasModulate 只调制其所在 CanvasLayer 的内容，且多个 CanvasModulate 逐层累积相乘**——7 个 moon 把雪幕白色粒子压到 120（近黑背景上不可见）、血色 α 压到 0.165（不可见）、layer 0 Backdrop luma 36→17（近黑）。**修复 = 回退 + 契约化，不是重构。**

**设计哲学：月光只染世界层；雪/墨/血/UI 保持原亮度；一切可守卫、可断言、可复现。**

1. **月光 = 世界光**：冷月光本质是照亮「大地」的色调（只狼苇名城雪夜），世界内容（layer 0）被染成冷蓝灰（AC2）；雪幕（必须白）、水墨（自带暗角）、血色（唯一高饱和例外）、UI（可读性）**全部不放 moon**——保持原始亮度与饱和度。
2. **单一事实源**：1 个 moon（颜色 = `MOONLIGHT_COLOR_APPLIED`）+ 1 个背景色常量（`NIGHT_BG_COLOR`）；`_apply_moonlight()` 从 `find_children` 遍历回退为单节点直接赋值——删掉「每层设色」这个错误的控制面。
3. **结构守卫防再犯**：test_atmosphere 的 C3 从「每可见层都有 moon」**语义反转**为「全组件仅 1 个 moon 且位于 layer 0」——任何 future agent 给雪幕/血色/UI 层加 moon 都会被测试拦截。
4. **渲染断言分级**：机械断言（不依赖 taste 值）= moon A/B 亮度比 ≈ 0.471、雪白像素存在、血 A/B diff、UI 白字亮度；taste 依赖断言（随 `NIGHT_BG_COLOR` 定稿）= `--theme 6e7684` 命中与否——两级口径写入 e2e_shots.json 注释，避免断言随品味值漂移。

```
                    ★ Issue #624 本设计（修复 #613，契约落在 impl/582 分支）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 修复前（7 个 moon，逐层相乘压暗）                                               │
│   Backdrop(layer0) ×#6e7684 → luma 36→17 近黑（F3）                           │
│   雪幕粒子(layer3-5) ×#6e7684 → 255→120 不可见（F1）                           │
│   血色(layer10)     ×#6e7684 → α0.35→0.165 不可见（F2）                        │
│   UI 文字(layer1)   ×#6e7684 → 255→120 对比度减半（F4）                        │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修复后（1 个 moon 挂 layer 0 世界层，方案 A）                                   │
│   WorldBackdrop(layer0) ×#6e7684 → 冷蓝灰夜色（AC2，亮度约束见 §2.4）           │
│   雪幕粒子(layer3-5)    无 moon  → 纯白 α0.7-0.9（F1 修复）                    │
│   血色(layer10)         无 moon  → 饱和红 α≤0.35（F2 修复）                    │
│   UI(layer1)/水墨(layer2) 无 moon → 原样（F4 修复）                             │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（7 文件，全部在 impl/582 分支上；main 上这些文件尚不存在）                  │
│  scenes/atmosphere/atmosphere_layer.tscn      删 5 个 Moonlight，留根 1 个     │
│  scenes/Main.tscn                             删 UI moon + 新增 WorldBackdrop   │
│  scenes/e2e_stick_figure_capture.tscn         Backdrop 色 → NIGHT_BG_COLOR    │
│  gdscripts/atmosphere_controller.gd           _apply_moonlight() 回退直接赋值  │
│  gdscripts/constants.gd                       追加 NIGHT_BG_COLOR（# DRAFT）   │
│  tests/test_atmosphere.gd                     C3 语义反转（==1 守卫）          │
│  e2e_shots.json                               snow_night 像素断言口径          │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 2. 修复设计 — 详细设计

### 2.1 `scenes/atmosphere/atmosphere_layer.tscn` — moon 收敛 6→1

**文件:** `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn`（impl/582 分支）

**删除 5 个 Moonlight 节点**（均 `CanvasModulate`，颜色 `Color(0.431, 0.463, 0.518, 1)`）：

| 删除节点路径 | 所在层 | 删除原因 |
|-------------|:---:|---------|
| `SnowCurtain/LayerFar/Moonlight` | 3 | 雪幕必须纯白（F1），禁染 |
| `SnowCurtain/LayerMid/Moonlight` | 4 | 同上 |
| `SnowCurtain/LayerNear/Moonlight` | 5 | 同上 |
| `InkWashLayer/Moonlight` | 2 | 水墨自带暗角，禁染 |
| `BloodVignette/Moonlight` | 10 | 血色是唯一高饱和例外（F2），禁染 |

**保留 1 个:** `Atmosphere/Moonlight`（parent = Atmosphere 根，无 CanvasLayer 祖先 → layer 0 默认画布）。这正是 PRD/DESIGN #582 原设计的单节点位置。

**修复后节点树（变更部分）:**

```
Atmosphere (Node2D, atmosphere_controller.gd)
├── Moonlight (CanvasModulate, color=MOONLIGHT_COLOR_APPLIED)   ← 唯一 moon，layer 0
├── SnowCurtain (Node2D, snow_curtain.gd)
│   ├── LayerFar (CanvasLayer, layer=3) ── Parallax ── Particles   [Moonlight 已删]
│   ├── LayerMid (CanvasLayer, layer=4) ── Parallax ── Particles   [Moonlight 已删]
│   └── LayerNear (CanvasLayer, layer=5) ── Parallax ── Particles   [Moonlight 已删]
├── InkWashLayer (CanvasLayer, layer=2) ── InkWash (ColorRect)      [Moonlight 已删]
└── BloodVignette (CanvasLayer, layer=10, blood_vignette.gd)
    └── BloodRect (ColorRect)                                       [Moonlight 已删]
```

**红线遵守:** 粒子 `amount`（60/60/80）、Parallax2D `scroll_scale`、粒子材质、水墨/血色 shader 与 α 上限**全部零改动**（PRD §8 红线）。

### 2.2 `scenes/Main.tscn` — 删 UI moon + layer 0 夜色世界背景

**文件:** `shandong-wolf/scenes/Main.tscn`（impl/582 分支）

1. **删除** `CanvasLayer(layer=1)/Moonlight`（第 7 个 moon，UI 文字从此恢复纯白 255，F4 修复）。
2. **新增** layer 0 夜色世界背景节点（标题场景「第一印象」的 AC2 载体，解决 round 1「无物可染」的根源）：

```
Main (Node2D)
├── WorldBackdrop (ColorRect, layer 0)   ← 新增，全屏夜色垫底
│     color = NIGHT_BG_COLOR（constants 单一事实源）
│     anchors_preset = 15（全屏）· mouse_filter = 2（IGNORE）· grow_h/2 = 2
├── CanvasLayer (layer=1)                ← 现有 UI 零改动（moon 已删）
│     └── CenterContainer/VBox → TitleLabel/SubtitleLabel/VersionLabel/PostMergeProbeLabel
└── Atmosphere (atmosphere_layer.tscn 实例)
```

实现细节：`WorldBackdrop` 直接挂在 Main 根（非 CanvasLayer 内）即 layer 0；ColorRect 默认锚点为左上角，须设 `anchors_preset = 15` + `anchor_right/bottom = 1.0` + `mouse_filter = 2`（照抄 InkWash/BloodRect 的全屏写法）。色值**不写死**在 tscn，从 `NIGHT_BG_COLOR` 常量带出（若 tscn 需要字面量，则 tscn 值 = 常量当前候选值并在注释标注「值随 constants.gd 候选定稿」）。

### 2.3 `gdscripts/atmosphere_controller.gd` — `_apply_moonlight()` 回退直接赋值

**文件:** `shandong-wolf/gdscripts/atmosphere_controller.gd`（impl/582 分支）

- **删除** `find_children("Moonlight", "CanvasModulate", true, false)` 遍历设色循环（这是「每层一 moon」错误的运行时控制面，留着等于给复犯留门）。
- **回退为**：`_moonlight.color = moonlight_color`（`@onready var _moonlight: CanvasModulate = $Moonlight` 路径不变，根 moon 仍在原位）。
- **头部注释补层契约**（防再犯的文档层）：写明「CanvasModulate 只影响自身 CanvasLayer；本组件唯一 Moonlight 挂 layer 0 世界层；雪/墨/血/UI 层禁放 moon，原因 = PRD #624 §1.3 乘法链根因」。

```gdscript
## 层级约定: CanvasLayer layer 1=UI（不动）/ 2=水墨 / 3-5=雪幕（远/中/近）/
## 10=血色 vignette（#583 复用同一 .tscn 照此约定）。
## 冷月光契约（#624 修复）: CanvasModulate 只调制其所在 CanvasLayer 的内容，
## 多 moon 逐层相乘会把雪幕/血色压没（PRD #624 §1.3 实测根因）。
## 本组件**唯一** Moonlight 挂在 Atmosphere 根（layer 0 世界层），只染世界内容；
## 雪幕(3-5)/水墨(2)/血色(10) 层禁放 moon —— test_atmosphere C3 守卫 == 1 拦截复犯。
func _apply_moonlight() -> void:
	_moonlight.color = moonlight_color
```

其余（`set_low_health` / `debug_trigger_low_health` / `debug_clear_low_health` / `_ready` 水墨参数设置）**零改动**——契约面保持，`get_visual_alpha()` 不变（AC3）。

### 2.4 `gdscripts/constants.gd` — 追加 `NIGHT_BG_COLOR`（# DRAFT 候选集）

**文件:** `shandong-wolf/gdscripts/constants.gd`（impl/582 分支），氛围参数分区（`# ── 冷月光` 段之后追加）：

```
# ── 夜色世界背景（# DRAFT 候补值，待 #582 用户裁决；#624 新增）──
#   作用: layer 0 世界垫底，供唯一 Moonlight（#6e7684）染色成冷蓝灰夜色（AC2 载体）
#   约束: 染后（× MOONLIGHT_COLOR_APPLIED）背景 luma ≥ 30 —— 不得回到 #613 近黑态（F3）
#   候选集: #d8dce4（浅月光灰，染后 ≈ #66686b 接近 AC2 目标 #6e7684，theme 断言可命中）——
#           #4e5464（中蓝灰，染后 ≈ #222734，luma ~39，需 A/B 亮度比断言）——
#           #0d1520（PRD §8 建议的深夜色，染后 ≈ #060a0f luma ~10，近黑，**否决候选**）
#   情感断言: 苍白、清冷——月光下的雪夜大地是亮冷灰蓝，不是无月黑夜
const NIGHT_BG_COLOR: Color = Color("#d8dce4")   # # DRAFT（首选候选；染后 ≈ #66686b）
```

**PRD 内部张力裁决（本设计的机械约束，taste 值仍归用户）：** PRD §8 建议 `#0d1520`，但 PRD §3.3/§7 S3 的预期（capture 背景 luma 36、染后 ≈ #2f333c）反推底色应为中-浅蓝灰——`#0d1520` 染后 luma ~10，与当前失败态（luma 15.6-17 近黑）几乎无差别，会**复现 F3**。故首选候选取浅月光灰 `#d8dce4` 系：①染后 ≈ `#66686b`，与 AC2 目标 `#6e7684` 距离 < 32（theme 断言可命中）；②与 `BODY_COLOR #2b2b2b` 墨色剪影对比度 ~60（官方截图「剪影 + 雪夜」构图成立）；③「苍白清冷」情感断言（月光雪地亮、边缘水墨暗角）逐字成立。**implement 期用 S3 脚本实测后提交用户裁决，禁止单方面定稿。**

### 2.5 `scenes/e2e_stick_figure_capture.tscn` — Backdrop 同步 `NIGHT_BG_COLOR`

**文件:** `shandong-wolf/scenes/e2e_stick_figure_capture.tscn`（impl/582 分支）

现有 `Backdrop`（ColorRect，色 `Color(0.1, 0.14, 0.18)`，layer 0）修复后会被唯一 moon 染成 luma ~16——官方 snow_night 截图（用此场景）将仍是近黑背景，F3 在官方截图上**复现**。处置：`Backdrop.color` 改为 `NIGHT_BG_COLOR` 当前候选值（`Color("#d8dce4")`，注释标注随常量候选定稿）。这是官方截图输入物，必须与 Main.tscn 的 WorldBackdrop 同源同色。

### 2.6 `e2e_shots.json` — snow_night 像素断言口径

**文件:** `shandong-wolf/e2e_shots.json`（impl/582 分支）

runner（run-e2e-review.sh）支持 **per-shot `theme_color` 覆盖**（shot 级声明优先于全局 `theme_color`；显式 `null` 跳过 theme 断言）。变更：

| 组 | 处置 | 理由 |
|----|------|------|
| `snow_night.01_snow_night_atmosphere` | shot 级 `"theme_color": "6e7684"`（或 `null` + 注释，见下） | AC2 月光色调断言：染后背景 ≈ #66686b，距 #6e7684 < 32 命中；若用户裁决深色候选则改 `null` 并以 A/B 亮度比断言（§9 R2） |
| `stick_figure.*`（12 shots） | 逐 shot `"theme_color": null` 或保持全局值并在 implement 期实测 | 染后背景/剪影颜色变化（#2b2b2b × 0.471），`c0c8d0` 断言大概率不再命中；**处置规则：implement 期跑一次 P5，theme 断言失败即改 per-shot null（帧间 `--diff-with` 断言仍验证动画状态变化，不丢验证力）** |
| 全局 `theme_color: c0c8d0` | 保持 | 兜底默认值；已被 per-shot 覆盖逻辑取代 |

`snow_night` shot 的 `_comment` 追加像素断言口径说明：theme `6e7684`（月光色）/ 雪白 ≥200 lum 像素存在性（review 侧自定义计数）/ 血触发红像素 A/B（review 手动 `debug_trigger_low_health` 前后截图 diff）。

## 3. 既有组件修改

### 3.1 文件清单总表

| 文件 | 变更性质 | 变更内容 |
|------|:---:|---------|
| `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn` | 改 | 删 5 个 Moonlight（§2.1），保留根 1 个 |
| `shandong-wolf/scenes/Main.tscn` | 改 | 删 UI 层 Moonlight；新增 WorldBackdrop（layer 0，§2.2） |
| `shandong-wolf/scenes/e2e_stick_figure_capture.tscn` | 改 | Backdrop.color → NIGHT_BG_COLOR 候选值（§2.5） |
| `shandong-wolf/gdscripts/atmosphere_controller.gd` | 改 | `_apply_moonlight()` 回退直接赋值 + 层契约注释（§2.3） |
| `shandong-wolf/gdscripts/constants.gd` | 改 | 追加 `NIGHT_BG_COLOR` # DRAFT 候选（§2.4） |
| `shandong-wolf/tests/test_atmosphere.gd` | 改 | C3 语义反转（§3.2） |
| `shandong-wolf/e2e_shots.json` | 改 | snow_night 断言口径 + stick_figure theme 处置（§2.6） |

**新文件:** 无（WorldBackdrop 内联进 Main.tscn，不新建 .tscn——组件太小不值得独立场景）。
**删除文件:** 无（删除的是 tscn 内节点，非文件）。
**受影响测试文件:** `test_atmosphere.gd`（C3 反转 + 新增 Main.tscn 文本守卫，§3.2）。

### 3.2 `tests/test_atmosphere.gd` — C3 语义反转（机械守卫）

`_test_c3_moonlight_covers_visible_layers`（现断言「layer 2/3/4/5/10 每层都有 Moonlight」）**整体重写**为单 moon 守卫，语义 180° 反转：

| 现 C3 断言（#613 语义，删除） | 新 C3 断言（#624 语义） |
|---|---|
| 每个可见 CanvasLayer 必须有 Moonlight 子节点且颜色 == APPLIED | 实例内 `find_children("*", "CanvasModulate")` 总数 **== 1** |
| — | 唯一 moon **无任何 CanvasLayer 祖先**（= 位于 layer 0 世界层） |
| — | 唯一 moon 颜色 == `MOONLIGHT_COLOR_APPLIED` |
| — | 任一 CanvasLayer（2/3/4/5/10）下**不得**存在 Moonlight 子节点 |

测试描述（§9 展开）：C3-1 总数守卫 / C3-2 层归属守卫 / C3-3 颜色守卫 / C3-4 Main.tscn 文本无 `CanvasModulate`（FileAccess 模式，同 B3/D1 先例，防 UI 层 moon 复生）。`_test_c1_moonlight`（根 moon 存在 + 颜色）**保持通过**——根 moon 未删；`_test_c2_moonlight_convert_comment`（换算注释）不变；B1-B4 / D1-D2 / E1-E4 **全部不受影响**。

## 4. 数据流

### Flow 1: 正常路径 — 修复后单 moon 渲染（Main.tscn 首启）

```
Main 首帧
  ├─ WorldBackdrop(layer0, NIGHT_BG_COLOR #d8dce4) ──×唯一 Moonlight(#6e7684)──► ≈#66686b 冷蓝灰夜色（AC2）
  ├─ 雪幕 Particles(layer3-5, 白 α0.7-0.9) ──无 moon──► 纯白粒子在夜色上可见（F1 修复，AC1）
  ├─ 水墨 InkWash(layer2) ──无 moon──► 暗角原样（edge_alpha ≤ 0.3，AC3/AC5）
  ├─ 血色 BloodVignette(layer10) ──无 moon──► low_health 触发时饱和红 α≤0.35 可见（F2 修复，AC3）
  └─ UI(layer1, 白字 255) ──无 moon──► 对比度恢复（F4 修复，AC5）
```

### Flow 2: 验证路径 — 月光 A/B 亮度比（机械断言，不依赖 taste 值）

```
S3 脚本（moon_spike.gd 改 3 行）:
  1. 关 moon（color 改白 #ffffff）→ 截 A 图 → 采样背景区 luma_a
  2. 开 moon（#6e7684）→ 截 B 图 → 采样背景区 luma_b
  3. 断言 luma_b / luma_a ≈ 0.471（MOONLIGHT_BRIGHTNESS）± 10%
     —— 通过 = 唯一 moon 确实在 layer 0 且只染世界层（机制验证，与背景色取值无关）
```

### Flow 3: 边界路径 — 雪幕层被误加 moon（防再犯）

```
future agent 给 LayerNear 加 CanvasModulate(#6e7684)
  → test_atmosphere C3-1 守卫: find_children 总数 2 ≠ 1 → FAIL
  → CI 拦截，diff 审查发现 → 回退
  （同类拦截: C3-4 Main.tscn 文本守卫 / C3-2 层归属守卫 / C3-3 颜色守卫）
```

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | **layer 0 无内容**（#583 战斗场景落地前）：月光无可染对象，AC2 不成立 | WorldBackdrop / capture Backdrop 垫底保证 AC2 有物可染；#583 落地后世界几何放 layer 0 自动被染（层契约注释 + 文档） |
| 2 | **背景色候选过暗**（如 PRD §8 建议的 #0d1520）：染后 luma ~10，F3 复现 | 机械约束「染后 luma ≥ 30」+ S3 实测 + C 组无单测（taste 域），implement 期以像素断言拦截；候选集已标注否决候选 |
| 3 | **雪幕层被误加 moon**（未来调参）：白雪变灰 | C3-1 总数守卫（==1）自动拦截；C3-4 文本守卫兜底 Main.tscn |
| 4 | **血色触发时机/幂等**：重复 `set_low_health(true)` 叠加 | blood_vignette.gd 零改动（tween kill 已有，E3 用例已覆盖）；moon 删除后血色恢复可见，`get_visual_alpha()` 契约不变 |
| 5 | **Compatibility vs Forward+ 渲染器**：层作用域语义在 Forward+ 下需重验 | 项目 CI/E2E 固定 Compatibility（OpenGL/Metal）；S3 验证顺带记录两驱动差异，若 Forward+ 语义不同需开新 issue，不静默假设 |
| 6 | **E2E 分辨率异常**（曾以 720x405 截图）：像素断言按分辨率漂移 | 断言口径按实际分辨率适配（review 协议已有）；snow_night 官方截图需重新产出（旧图 luma 15.6 作废，PRD §8） |
| 7 | **stick_figure 组 theme 断言被染坏**：染后无 c0c8d0 像素 → P5 FAIL | per-shot `theme_color: null` 跳过 theme（帧间 --diff-with 断言保留验证力）；处置规则见 §2.6 |
| 8 | **删 moon 时把唯一根 moon 也删了**（执行偏差）：月光完全消失 | C3-1 ==1 守卫拦截（0 ≠ 1）+ C1 用例（根 moon 存在）拦截 |
| 9 | **水墨暗角叠加背景变深**影响读图 | `INK_EDGE_ALPHA_MAX ≤ 0.3` 硬上限不动 + `INK_INNER_RADIUS 0.62` 中央通透区不动（taste 域，用户裁决） |

## 6. 每场景配置

| 场景 | 唯一 Moonlight | layer 0 内容 | 染后效果 | 备注 |
|:-----|:---:|-------------|----------|------|
| `Main.tscn`（标题） | Atmosphere 根 1 个 | WorldBackdrop（NIGHT_BG_COLOR） | 冷蓝灰夜色 + 纯白雪幕 + 白字 UI | 首启「第一印象」场景（用户场景 A） |
| `e2e_stick_figure_capture.tscn`（E2E） | Atmosphere 根 1 个（实例自带） | Backdrop（NIGHT_BG_COLOR）+ Player（#2b2b2b 剪影） | 夜色背景 + 墨色剪影（对比度 ~60）+ 雪 | 官方截图输入物（用户场景 B） |
| `atmosphere_layer.tscn`（组件，#583 复用） | Atmosphere 根 1 个 | （由宿主场景提供） | 世界内容被染 | 层契约注释 + C3 守卫只对组件内有效，跨场景靠文档（PRD §5.2-2） |

## 7. 集成点

> **Status 约定:** ⬜ = 待 implement agent 接线；✅ = implement 完成并验证。

| 集成 | 本设计组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| 单 moon 守卫 | test_atmosphere C3 | #624 | 结构断言拦截复犯（==1） | ⬜ 待接线 |
| 层契约注释 | atmosphere_controller.gd 头部 | #583 | #583 复用 .tscn 时照契约放世界几何 | ⬜ 文档层 |
| WorldBackdrop / Backdrop | Main.tscn + capture.tscn | #582 AC2 | layer 0 垫底供月光染色 | ⬜ 待接线 |
| snow_night 像素断言 | e2e_shots.json | #586 | 完整剧本纳入月/雪/血像素断言 | ⬜ 注释先行 |
| 修复载体 | impl/582 分支 | #613（PR） | 修复落分支 → 重新 review + taste-draft | ⬜ 待裁决 |

## 8. 实现阶段

| 阶段 | 优先级 | 内容 | 依赖 |
|:---:|:---:|------|------|
| Phase 1 | P0 | 场景结构：atmosphere_layer.tscn 删 5 moon；Main.tscn 删 UI moon + 加 WorldBackdrop；capture.tscn Backdrop 改色 | — |
| Phase 2 | P0 | 逻辑与常量：atmosphere_controller.gd `_apply_moonlight()` 回退 + 注释；constants.gd 追加 NIGHT_BG_COLOR | Phase 1（tscn 引常量） |
| Phase 3 | P0 | 守卫与断言：test_atmosphere.gd C3 反转 + C3-4 文本守卫；e2e_shots.json 断言口径 | Phase 2（结构定稿后可写守卫） |
| Phase 4 | P0 | 验证与裁决：L0 编译 + L1 测试 + S3 渲染验证（A/B 亮度比 + 雪白 + 血 A/B + 官方截图重出）→ 提交 #613 re-review + #582 用户 taste-draft | Phase 1-3 |

估计：0.5–1 天（PRD §4 方案 A Effort 一致）。

## 9. 测试用例描述

> **说明:** 本阶段只写测试**描述**，不写可运行测试文件（plan 阶段红线）。用例编号沿用 test_atmosphere.gd 既有 A-E 场景命名。

### Scenario C3: 单 moon 守卫（语义反转，#624 核心新增）

- **C3-1 总数守卫**: 实例化 `atmosphere_layer.tscn` → `find_children("*", "CanvasModulate", true, false)` 数量 **== 1**。前置：场景已按 §2.1 修复。预期：通过；若 future agent 给任何层加 moon，数量变 2 → FAIL 拦截。
- **C3-2 层归属守卫**: 唯一 moon 的祖先链中**不得存在 CanvasLayer**（即位于 layer 0 默认画布）。预期：moon.parent == Atmosphere 根（或其祖先无 CanvasLayer）。
- **C3-3 颜色守卫**: 唯一 moon 的 `color` RGB == `MOONLIGHT_COLOR_APPLIED`（#6e7684）。预期：相等（保持 C1 语义）。
- **C3-4 Main.tscn 文本守卫**: 用 FileAccess 读取 `Main.tscn` 全文，断言**不含** `"CanvasModulate"` 字样（同 B3/D1 的文本断言模式）。预期：通过；UI 层 moon 复生即 FAIL。
- **C3-5 层内无 moon 守卫**: 遍历实例内全部 CanvasLayer（layer 2/3/4/5/10），断言其子节点中无 CanvasModulate。预期：通过（5 个已删节点不复活）。

### Scenario C（保留用例回归）

- **C1 保持**: 根 moon 存在且颜色 == APPLIED——修复后仍通过（根 moon 未删）。
- **C2 保持**: `MOONLIGHT_COLOR_APPLIED` 行含 `× 0.6` 换算注释——不变。

### Scenario R: 渲染级验证（implement 期真实渲染，非单测）

- **R1 雪幕可见（AC1）**: 官方 snow_night 截图（S3 重出）雪幕区域存在 **≥200 lum 白色像素**（自定义计数 > 0；PRD §5.1 AC1：bright samples ≥ 无 moon 基线 50%）。
- **R2 月光机制（AC2 机械版）**: A/B 亮度比——关 moon（白）vs 开 moon（#6e7684），背景采样区 `luma_b / luma_a ≈ 0.471 ± 10%`（Flow 2）。预期：通过，证明唯一 moon 在 layer 0 生效。
- **R3 月光色调（AC2 taste 版）**: `analyze_bmp --theme 6e7684`（容差 32）对 snow_night 截图。预期：NIGHT_BG_COLOR 首选候选 #d8dce4 染后 ≈ #66686b 命中；若用户裁决深色候选则此断言改 `null` 并以 R2 为准（口径记录在 e2e_shots.json 注释）。
- **R4 血色可见（AC3）**: `debug_trigger_low_health()` 后 0.5s 截图 vs 触发前——`analyze_bmp --diff-with --min-delta 5.0` 有像素差异，且边缘存在 `r>g 且 r-b ≥ 0.15` 红像素（PRD §5.1 AC3）；`get_visual_alpha()` 契约不变（E2 用例覆盖）。
- **R5 UI 亮度恢复（AC5）**: Main.tscn 截图标题白字区域 ≥ 200 lum（F4 修复验证）。

### Scenario 回归（原失败实验全绿，AC6）

- **R6 官方截图断言**: 重出的 `01_snow_night_atmosphere.png` 通过 `--theme 6e7684`（或注释口径）+ 非近黑（`--max-black-ratio`）断言——旧图（luma 15.6，0 白像素）作废。
- **R7 全量单测**: `godot --headless --script tests/run_tests.gd` 退出 0，含反转后 C3 全套 + 既有 A/B/D/E 用例（pass 数 ≥ 原数）。
- **R8 冒烟**: `godot --path shandong-wolf/ --headless --quit` 退出 0（Main.tscn 首启链兼容 WorldBackdrop 新增节点）。

### 既有用例影响清单

| 用例 | 影响 | 处置 |
|------|------|------|
| A1/A2/A3（常量） | 无 | 保持（NIGHT_BG_COLOR 追加不破坏；A2 的 # DRAFT 计数自动 +1） |
| B1-B4（雪幕结构） | 无 | 保持（amount/scale/emitting 零改动） |
| C1/C2（moon 存在/注释） | 无 | 保持（根 moon 未删） |
| C3（每层有 moon） | **反转** | 重写为 C3-1~C3-5（§9） |
| D1/D2（水墨） | 无 | 保持 |
| E1-E4（血色） | 无 | 保持（tween/α 契约未动） |

## 10. 验收条件映射（源自 PRD #624 §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 雪幕粒子可见（≥200 lum 白像素；bright samples ≥ 基线 50%） | §2.1 删雪幕层 moon（粒子零改动） | R1 + B 组用例回归 |
| AC2 | 冷月光色调成立（单 moon 挂 layer 0；背景染成 #6e7684 系；截图存在邻近色像素） | §2.1 单 moon + §2.2/§2.5 背景垫底 + §2.4 NIGHT_BG_COLOR | R2（A/B 亮度比，机械）+ R3（theme 6e7684，taste 依赖） |
| AC3 | 血色 vignette 可见（0.5s 后红像素；get_visual_alpha 契约不变） | §2.1 删血色层 moon（blood_vignette.gd 零改动） | R4 + E 组用例回归 |
| AC4 | CanvasModulate 数量守卫（== 1，防再犯） | §3.2 C3 语义反转 | C3-1~C3-5 |
| AC5 | 非氛围层不受影响（UI 白字 ≥200 lum；水墨 edge_alpha ≤0.3；amount 60/60/80 未改） | §2.2 删 UI moon + §2.3 回退 + 红线 | R5 + A3/B3/D1 回归 |
| AC6 | 回归验证（官方截图 theme 通过；血 before/after 有差异；blame2 bright samples 恢复） | §2.6 断言口径 | R6/R7/R8 |

## 11. 明确不修改（与 PRD §8 红线对齐）

- ❌ `shandong-wolf/gdscripts/snow_curtain.gd`（粒子无缺陷，只受层 moon 影响；amount 运行时禁改红线）
- ❌ `shandong-wolf/gdscripts/blood_vignette.gd` / `blood_vignette.gdshader`（tween/α 上限正常，只受层 moon 影响）
- ❌ `shandong-wolf/gdscripts/ink_wash.gdshader`（edge_alpha ≤ 0.3 硬上限不动）
- ❌ constants.gd 既有氛围常量行（MOONLIGHT_*/SNOW_*/INK_*/BLOOD_* 全部保留，仅追加 NIGHT_BG_COLOR；taste 域归 #582 用户裁决）
- ❌ `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`framework/`（跨游戏/管线红线）
- ❌ 任何外部美术资产 / 贴图 / 插件（AC5 红线）
- ❌ #583 战斗场景场景几何、#575 玩家实体、#576 HUD、#584 手感定稿、#586 完整 E2E 剧本（范围边界）
- ❌ 本 plan 阶段不写任何可运行测试文件 / 实现文件（仅本文档 + 测试描述）
- ✅ Main.tscn 现有 UI 节点（TitleLabel/SubtitleLabel/VersionLabel/PostMergeProbeLabel + CanvasLayer layer=1）零改动（仅删其下 Moonlight）
- ✅ atmosphere_layer.tscn 的粒子节点 / 材质 / Parallax / InkWash / BloodRect 全部零改动（仅删 5 个 Moonlight）

# 雪夜氛围层 — 单 CanvasModulate 冷月光契约 + 四层系统实现（#582/#624/#613）

> 落盘依据：PR **#613**（feat(582) 雪夜氛围四层系统，已 merge 2026-08-20）← DESIGN
> `docs/DESIGN/582-snow-night-atmosphere.md`；单 moon 契约部分由 PR #629（fix，已 merge
> 2026-08-19）← DESIGN `docs/DESIGN/624-snow-night-atmosphere-regression.md` 定稿。
> 上游：#582 雪夜氛围（PRD/DESIGN，taste-draft 待用户 E2E 截图 ≥70% 定稿）。
> ✅ 代码状态：#613 已合并，氛围代码（atmosphere_controller / snow_curtain / ink_wash /
> blood_vignette / atmosphere_layer.tscn / test_atmosphere）全部落地 **main**（2026-08-20）。
> 机械部分（moon 数量/层归属/守卫）已定稿；常量色值仍属 taste 域（`# DRAFT`，归 #582 用户裁决）。

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
| 氛围实现 | 全程序化：GPUParticles2D + canvas_item shader，零贴图/零外部资产 | 贴图/插件/像素帧 | PRD 硬约束⑤⑥ + issue 🔍 调研结论（无成熟开源方案可复用） |

## 3. 层契约与节点树

### 3.1 CanvasLayer 层级约定（#582 定稿，atmosphere_controller.gd 头部注释）

| layer | 内容 | 允许 Moonlight | 理由 |
|:---:|------|:---:|------|
| 0 | 世界层（WorldBackdrop / 未来 #583 战斗场景几何） | ✅ 唯一 moon 在此 | 月光只染世界（AC2） |
| 1 | UI（标题/字幕/版本/探针） | ❌ 禁染 | 白字对比度（F4） |
| 2 | 水墨晕染 | ❌ 禁染 | 自带暗角 |
| 3-5 | 雪幕（远/中/近） | ❌ 禁染 | 必须纯白（F1） |
| 10 | 血色 vignette | ❌ 禁染 | 唯一高饱和例外（F2） |

### 3.2 节点树（atmosphere_layer.tscn，main 上 #613 实测）

```text
Atmosphere (Node2D, atmosphere_controller.gd)
├── Moonlight (CanvasModulate, color=MOONLIGHT_COLOR_APPLIED)   ← 唯一 moon，layer 0
├── SnowCurtain (Node2D, snow_curtain.gd)
│   ├── LayerFar  (CanvasLayer, layer=3) ── Parallax(scroll_scale 0.2) ── Particles(amount 60)
│   ├── LayerMid  (CanvasLayer, layer=4) ── Parallax(scroll_scale 0.5) ── Particles(amount 60)
│   └── LayerNear (CanvasLayer, layer=5) ── Parallax(scroll_scale 1.0) ── Particles(amount 80)
├── InkWashLayer (CanvasLayer, layer=2) ── InkWash (ColorRect full-rect, ink_wash.gdshader)
└── BloodVignette (CanvasLayer, layer=10, blood_vignette.gd)
    └── BloodRect (ColorRect full-rect, blood_vignette.gdshader)
```

**红线遵守（#613 实测）：** 粒子 `amount`（60/60/80）仅 .tscn 静态声明，运行时禁改
（rain_curtain 教训：Godot 改 amount 重启粒子系统 → 可见跳变）；Parallax2D `scroll_scale`
在 .tscn 声明（0.2/0.5/1.0）；水墨/血色 shader 与 α 上限全部零字面量（读 constants 分区）；
Main.tscn 现有 UI 节点零改动（仅追加 Atmosphere 实例子节点）。

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

## 4. 氛围常量（#582/#624/#613，全部落地 main）

> 分区位于 constants.gd「冷月光 / 夜色世界背景 / 水墨晕染 / 血色 vignette」段，SNOW_*/MOONLIGHT_*/
> INK_*/BLOOD_* 4 组 24 项全部 `# DRAFT` 候补值，定稿归 #582 用户裁决；`BLOOD_VIGNETTE_LAYER`
> 为机械常量（层级约定，定稿）。

| 常量 | 候补值 | 语义 |
|------|--------|------|
| `SNOW_PARTICLES_FAR/MID/NEAR` | `60 / 60 / 80` | 三层粒子数（合计 200，AC1 ±10%）；amount 仅 .tscn 静态声明 |
| `SNOW_PARALLAX_FAR/MID/NEAR` | `0.2 / 0.5 / 1.0` | 三层视差系数（Parallax2D scroll_scale） |
| `SNOW_SCALE_FAR` / `SNOW_SCALE_NEAR` | `0.5` / `1.5` | 远景雪小 / 近景雪大（AC1 近景 1.5x 远景 0.5x） |
| `SNOW_VELOCITY_MIN/MAX` | `20.0 / 40.0` | 飘落速度 px/s（AC1 20-40px/s） |
| `SNOW_ALPHA_MIN/MAX` | `0.7 / 0.9` | 雪幕 α 区间（远 0.7 / 中 0.8 / 近 0.9） |
| `SNOW_WIND_DEFAULT` | `0.0` | 风向漂移（Boss 战可加大；`set_wind()` 运行时调） |
| `MOONLIGHT_COLOR_TARGET` | `#b8c4d9` | AC2 目标色温（只狼苇名城雪夜） |
| `MOONLIGHT_COLOR_APPLIED` | `#6e7684` | = TARGET × 0.6 换算（CanvasModulate 无独立 brightness） |
| `MOONLIGHT_BRIGHTNESS` | `0.6` | 色值换算系数（A/B 亮度比 ≈ 0.471 断言依据） |
| `NIGHT_BG_COLOR` | `#d8dce4`（候选集 #d8dce4 / #4e5464 / #0d1520否决） | layer 0 夜色垫底；染后 ≈ #66686b 命中 theme 断言；约束染后 luma ≥ 30 |
| `INK_EDGE_ALPHA_MAX` | `0.3` | 水墨暗角硬上限（AC3 不遮挡战斗读图） |
| `INK_COLOR` / `INK_INNER_RADIUS` / `INK_SOFTNESS` / `INK_NOISE_AMOUNT` | `#1a1f26` / `0.62` / `0.35` / `0.06` | 水墨质感参数 |
| `BLOOD_VIGNETTE_ALPHA_MAX` | `0.35` | 低血触发 α 硬上限（AC4） |
| `BLOOD_VIGNETTE_FADE_SECONDS` | `0.5` | Tween 时长（AC4 平滑 0.5s 渐变） |
| `BLOOD_VIGNETTE_LAYER` | `10` | 机械常量（层级约定，定稿） |

## 5. 数据流

### Flow 1: 正常路径 — 单 moon 渲染（Main.tscn 首启）

```text
Main 首帧
  ├─ WorldBackdrop(layer0, NIGHT_BG_COLOR #d8dce4) ──× 唯一 Moonlight(#6e7684) ──► ≈ #66686b 冷蓝灰夜色（AC2）
  ├─ 雪幕 Particles(layer3-5, 白 α0.7-0.9) ──无 moon──► 纯白粒子在夜色上可见（F1）
  ├─ 水墨 InkWash(layer2) ──无 moon──► 暗角原样（edge_alpha ≤ 0.3）
  ├─ 血色 BloodVignette(layer10) ──无 moon──► low_health 触发时饱和红 α≤0.35 可见（F2）
  └─ UI(layer1, 白字 255) ──无 moon──► 对比度恢复（F4）
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
| 血触发红像素 A/B diff | 机械 | debug_trigger_low_health 前后截图 diff（AC4） |
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
| 8 | 雪幕粒子不可见（#613 self-correct D 类缺陷） | 粒子补 texture：GradientTexture2D 程序化软白点（#613 已修复，033171e） |

## 8. 集成点

| 集成 | 本组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| 单 moon 守卫 | test_atmosphere C3（C3-1~C3-5） | #624 | 结构断言拦截复犯（==1） | ✅ #629 已落地 |
| 层契约注释 | atmosphere_controller.gd 头部 | #583 | #583 复用 .tscn 时照契约放世界几何 | ⬜ 文档层 |
| WorldBackdrop / Backdrop | Main.tscn + capture.tscn | #582 AC2 | layer 0 垫底供月光染色 | ✅ #613 已落地 main |
| snow_night 像素断言 | e2e_shots.json | #586 | 完整剧本纳入月/雪/血像素断言 | ⬜ 注释先行（snow_night 单帧组已在 main） |
| 氛围实现载体 | impl/582-snow-night-atmosphere 分支 | #613（PR） | 四层系统 + 单 moon 契约随 #613 上 main | ✅ 2026-08-20 已合并 |
| 低血发射端 | HUD low_health_changed 边沿信号 | #576/#575 | `set_low_health()` 契约对接（#575 实体实现后接线） | ⬜ 消费端已建 |

## 9. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #624 | 雪夜氛围回归修复（单 CanvasModulate 层契约） | 已合并（#629，2026-08-19） |
| #613 | 雪夜氛围 implement PR（四层系统 + self-correct 补粒子 texture） | ✅ 已合并（2026-08-20，代码上 main） |
| #582 | 雪夜氛围（上游设计；NIGHT_BG_COLOR 等 taste 值定稿归此） | 草稿已合并，待用户 E2E 截图 ≥70% 定稿 |
| #576 | HUD（low_health 信号源 → 血色 vignette 消费链路，10 章） | 已合并（#627） |
| #586 | 雪夜氛围完整 E2E 剧本 | 待建（snow_night 单帧组已先行） |

## 10. 实现落地（#613，已 merge 2026-08-20）

> 本节记录 #613 实际实现细节（main 实测），与 DESIGN §2/§3 的对应关系。全部文件在
> `shandong-wolf/` 下，零贴图/零外部资产（开源调研结论：GitHub 8 结果均 ≤2★ 无维护、
> Asset Library 无收录 → 自行实现）。

### 10.1 四层系统实现

1. **雪幕** — `snow_curtain.gd`（Node2D 控制器）+ 3×CanvasLayer(3/4/5) + Parallax2D
   （scroll_scale 0.2/0.5/1.0）+ GPUParticles2D（amount 60/60/80 静态声明）。`apply_tunables()`
   把常量下发到三层：far（scale 0.5，α 0.7）/ mid（scale 1.0，α 0.8）/ near（scale 1.5，α 0.9）；
   速度 20-40px/s（initial_velocity_min/max），风向 `set_wind(intensity)` 运行时调
   （direction = (drift_x, 1, 0).normalized()，drift_x = wind × parallax.scroll_scale.x）。
   self-correct 033171e 补粒子 texture（GradientTexture2D 程序化软白点）修复粒子不可见。
2. **冷月光** — CanvasModulate 单节点 `#6e7684`（= `#b8c4d9` × 0.6），挂 Atmosphere 根 layer 0，
   `_apply_moonlight()` 唯一赋值点（C3 守卫 == 1）。
3. **水墨晕染** — `ink_wash.gdshader`（全屏 canvas_item shader，约 17 行）：径向暗角
   （edge_alpha ≤ 0.3 硬上限）+ 噪声渗化（INK_NOISE_AMOUNT 0.06），墨色 `#1a1f26`。
4. **血色 vignette** — `blood_vignette.gd/.gdshader`：CanvasLayer(10) + 径向血色 shader +
   Tween 0.5s（alpha 0→0.35）。契约 `set_low_health(enabled)` + `debug_trigger_low_health()`/
   `debug_clear_low_health()` 兜底（#575 发射端未建期驱动同一契约路径，不绕过 tween）。

### 10.2 挂载与测试

- **场景挂载**：`scenes/atmosphere/atmosphere_layer.tscn`（137 行，Atmosphere 根 + 唯一
  Moonlight + 四层）实例化进 `scenes/Main.tscn`（Atmosphere 子节点）；`e2e_stick_figure_capture.tscn`
  同样 instance Atmosphere 供 snow_night 截图（#613 conflict resolution 合并）。
- **E2E**：`e2e_shots.json` 追加 snow_night 单帧组（完整剧本归 #586）；shot 用 at_frame
  （state={} 在统一 states 映射下永不 ready 的已知 gap，_comment 注明）。
- **测试**：`tests/test_atmosphere.gd`（462 行）覆盖 DESIGN §8 A-E 场景 + C3-1~C3-5 单 moon
  守卫；`run_tests.gd` 第 3 套件挂载（`_run("res://tests/test_atmosphere.gd", "Atmosphere")`）。
- **taste 裁决路径**：E2E 截图附 PR → 用户 ≥70% 裁决定稿；<70% 走 # DRAFT 参数迭代
  （改 constants 候补值，不重写架构）。

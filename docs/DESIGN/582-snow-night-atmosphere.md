# Design: [Rendering] 雪夜氛围（雪幕 / 冷月光 / 水墨晕染 / 血色 vignette）

> **Parent Issue:** #582
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4.6 推荐组合**逐项确认采纳，无分歧** —— 雪幕 A（3×GPUParticles2D + Parallax2D，视差 0.2/0.5/1.0）/ 冷月光 B（单节点 `#6e7684` ≈ `#b8c4d9`×0.6 色值换算，候选 A 备用）/ 水墨 A（全屏 ColorRect + canvas_item shader）/ 血色 A（CanvasLayer layer=10 + shader + Tween 0.5s）/ 挂载 A（`atmosphere_layer.tscn` 场景组件实例化进 Main.tscn）
> **Reference PRD:** `docs/PRD/582-snow-night-atmosphere.md`（research PR #604 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/572-scaffold-main-entry.md`（constants.gd `# DRAFT` 分区格式、run_tests 挂载模式、DESIGN 文档结构约定）；mini-pong 先例 `rain_curtain.gd`（**禁改 amount** 教训）/`vignette.gdshader`（径向暗角 shader 模式）/`test_visual_contrast.gd`（shader uniform 断言模式），仅作模式参考不复制代码
> **所有权:** `content_ownership: taste-draft`（taste-ownership-domains B3 视觉/艺术方向——配色、光效强度、粒子密度；agent 草稿 = 符合审美坐标的实现，用户经 E2E 截图裁决 ≥70% 定稿；PR 用 `Parent #582` 不写 Closes，assign 用户定稿）
> **深度:** standard（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=11 标注 depth: standard；GitHub 无 depth 标签）—— 11 文件（7 新建 + 4 修改）/ 4 氛围子系统 + 挂载集成 = 6+ 独立子任务 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：10+ 文件、5+ 独立子任务跨多子系统）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-582，branch `plan/582-snow-night-atmosphere`）；constants.gd 氛围分区追加在**文件尾部**（#584 手感分区已在前部，同文件不同区域，main 侧无代码冲突预期）；Main.tscn 追加 Atmosphere 实例子节点（#583 战斗场景复用同一 .tscn，不触碰 #583 专属的月亮节点）
> **红线:** 只动 `shandong-wolf/` 下 11 文件（见 §3.1/§3.2）；**绝不触碰** `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`docs/GAME_DESIGN/`、`shandong-wolf/tests/check_compile.gd`、`shandong-wolf/tests/smoke_test.gd`（#572 机制自动纳入新脚本）；零外部美术资产/零贴图/零插件/零像素帧（PRD 硬约束⑤⑥ + issue 🔍 调研结论）

---

## 1. 架构总览

**问题本质是「场景可运行但零氛围」而非功能缺陷。** #572 已交付逻辑地基（constants.gd / state_machine.gd / Game autoload / 测试三入口），Main.tscn 是纯声明式标题场景（CanvasLayer layer=1 UI，8 节点），全屏渲染层缺失：无 CanvasModulate、无全屏 shader 覆盖、无 CanvasLayer 分层约定。而雪夜是本游戏『第一印象』（brief §审美坐标：苍白、清冷、大地如墨；禁止五彩缤纷/阳光明媚/星光点缀）——首启画面即标题场景，氛围层必须随 Main.tscn 首帧成立。本设计交付 = **四层氛围组件（雪幕/冷月光/水墨/血色）+ 参数集中（constants.gd 氛围分区 # DRAFT）+ 场景无关挂载约定（atmosphere_layer.tscn）+ E2E 单帧截图裁决机制**。

**设计哲学：场景无关 + 参数单一事实源 + 程序化零贴图。** 四个子系统全部取「最小可裁决结构」：氛围组件打包为 `atmosphere_layer.tscn` 场景组件（PRD §4.5 方案 A），#583 战斗场景直接复用同一 .tscn，场景几何/月亮节点归 #583 不在此设计；所有视觉参数进 constants.gd 新增「氛围参数」分区（`# DRAFT` 候补值 + 情感断言，格式照 #572），控制器以 `@export` 调参默认取常量；渲染全部 GPUParticles2D + shader 程序化生成，零外部美术资产（开源调研 PRD §6.2 结论：无成熟方案可复用 → 自行实现，项目内 mini-pong 同构先例可对照）。

**层级约定（PRD §8，全场景统一）：** CanvasLayer layer 1 = UI（现有，不动）/ 2 = 水墨 / 3-5 = 雪幕（远/中/近）/ 10 = 血色 vignette。渲染顺序：UI 之下是水墨暗角（中央透明不影响读图），雪幕粒子飘过 UI 之上（雪落标题的『第一印象』），血色最上（低血压迫感，中央透明）。

```
                 ★ Issue #582 本设计（shandong-wolf 氛围四层）
┌──────────────────────────────────────────────────────────────────────────┐
│ 新建（7 文件，全部 shandong-wolf/ 下）                                      │
│  gdscripts/constants.gd 追加分区（改）── 氛围参数 4 组: SNOW_*/MOONLIGHT_*/INK_*/BLOOD_* │
│  gdscripts/atmosphere_controller.gd  编排入口: set_low_health() 契约 + debug 兜底 │
│  gdscripts/snow_curtain.gd           3×CanvasLayer(3-5)+Parallax2D(0.2/0.5/1.0)+GPUParticles2D │
│  gdscripts/ink_wash.gdshader         全屏水墨: 径向暗角(≤0.3) + 噪声渗化        │
│  gdscripts/blood_vignette.gd/.gdshader  CanvasLayer(10)+径向血色 shader+Tween 0.5s │
│  scenes/atmosphere/atmosphere_layer.tscn  场景组件（Main.tscn 与 #583 共用）    │
│  tests/test_atmosphere.gd            参数存在性/三层结构/alpha 上限/tween/契约  │
├──────────────────────────────────────────────────────────────────────────┤
│ 修改（4 文件）                                                             │
│  gdscripts/constants.gd   尾部追加「氛围参数」# DRAFT 分区（4 组 + 情感断言）   │
│  scenes/Main.tscn         根节点下实例化 atmosphere_layer.tscn（Atmosphere）   │
│  tests/run_tests.gd       _run_tests() 追加 _run(test_atmosphere.gd)        │
│  e2e_shots.json           追加「雪夜氛围」单帧 shot（供用户裁决，完整剧本归 #586）│
├──────────────────────────────────────────────────────────────────────────┤
│ 验证（0 改动）: check_compile / smoke_test 由 #572 机制自动纳入新增 .gd/.gdshader │
└───────────────────────────────────┬──────────────────────────────────────┘
                                    ▼
              godot --path shandong-wolf/（启动链）
                ├─ [autoload] Game 初始化（早于主场景 _ready）
                ├─ Main.tscn 首帧: Atmosphere 实例 _ready
                │    ├─ 雪幕 3 层发射（60/60/80 粒子，视差 0.2/0.5/1.0）
                │    ├─ CanvasModulate 冷月 #6e7684（= #b8c4d9 × 0.6）
                │    ├─ 水墨暗角 ColorRect（edge_alpha ≤ 0.3）
                │    └─ 血色 vignette 待命（alpha 0，低血才触发）
                └─ headless 三入口 + 单帧截图: 全绿 → 截图附 PR → 用户 ≥70% 裁决
```

**与 PRD 方案裁决的一致性：** PRD §4.1–§4.5 各子系统推荐方案 A/B/A/A/A，§4.6 汇总。本设计逐项确认采纳，无分歧；PRD §7 三个 Spike（全屏覆盖层方案验证 / 三层雪幕观感 / 冷月光亮度 0.6 语义对比）为 implement Phase 0 执行项，其中 Spike 3 的结论直接影响 MOONLIGHT_COLOR_APPLIED 取值（候选 B `#6e7684` 为主，若截图对比候选 A 更佳则改 `#b8c4d9`+modulate 组合，属于常量候补值调整，不改架构）。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实 origin/main） | 与 #582 的差距 |
|------|--------------------------------------------------------------|---------------|
| `shandong-wolf/gdscripts/constants.gd` | ✅ `WolfConstants`（RefCounted + class_name），5 个手感 `# DRAFT` 分区（弹反窗口/架势回复/两条命/刀伤害/帧节奏）+ 机械常量；**无氛围参数分区** | ❌ 尾部追加「氛围参数」分区（4 组常量 + 情感断言） |
| `shandong-wolf/scenes/Main.tscn` | ✅ 纯声明式标题场景（#562/#563/#570）：Main(Node2D)→CanvasLayer(layer=1)→CenterContainer/VBox→TitleLabel/SubtitleLabel + VersionLabel/PostMergeProbeLabel；无任何渲染层 | ❌ 根节点下实例化 Atmosphere 子节点（不触碰现有 UI 节点） |
| `shandong-wolf/gdscripts/` | ✅ constants.gd / state_machine.gd / game.gd（#572） | ❌ 新建 atmosphere_controller.gd / snow_curtain.gd / ink_wash.gdshader / blood_vignette.gd / blood_vignette.gdshader |
| `shandong-wolf/scenes/` | ✅ 仅 Main.tscn | ❌ 新建 `scenes/atmosphere/atmosphere_layer.tscn` |
| `shandong-wolf/tests/run_tests.gd` | ✅ 挂载 test_state_machine.gd + test_constants.gd（`_run_tests()` 内两行 `_run()`） | ❌ 追加 `_run("res://tests/test_atmosphere.gd", "Atmosphere")` |
| `shandong-wolf/tests/test_constants.gd` | ✅ 5 分区存在性 + `# DRAFT` 标记断言 | 无改动（#582 氛围分区由 test_atmosphere.gd 断言，避免跨套件耦合） |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位（states/groups 空，`_comment` 注明骨架期无玩法） | ❌ 追加「雪夜氛围」单帧 shot（§3.4，供用户裁决；完整剧本归 #586） |
| `shandong-wolf/tests/check_compile.gd` | ✅ 遍历 gdscripts/+tests/ 逐个 load，新脚本自动纳入 | 无改动 |
| `shandong-wolf/tests/smoke_test.gd` | ✅ 「SMOKE OK」退出码 0 | 无改动 |
| `mini-pong/gdscripts/rain_curtain.gd` | ✅ 雨幕先例：**禁改 amount**（改 amount 重启粒子系统 → 可见跳变）头注释 + 公式驱动 | 仅模式参考，**不复制**（雪幕无公式，静态密度） |
| `mini-pong/gdscripts/vignette.gdshader` | ✅ 径向暗角先例（#527，headless 编译安全已验证） | 仅模式参考：血色/水墨版在其上改色 + 噪声，不复制 |
| `#575 玩家实体（low_health 信号源）` | ⏳ OPEN backlog，未实现 | 本设计只建**消费端契约** `set_low_health(enabled)` + `debug_trigger_low_health()` 兜底 |

---

## 2. 新组件 — 详细设计

### 2.1 atmosphere_controller.gd — 氛围编排统一入口

- **File:** `shandong-wolf/gdscripts/atmosphere_controller.gd`
- **Node structure（= atmosphere_layer.tscn 根脚本）：**

```
Atmosphere (Node2D, atmosphere_controller.gd)
├── SnowCurtain (Node2D, snow_curtain.gd)           # 雪幕三层的统一管理
├── Moonlight (CanvasModulate)                       # 冷月色调
├── InkWashLayer (CanvasLayer layer=2)               # 水墨晕染
│   └── InkWash (ColorRect full-rect, ink_wash.gdshader)
└── BloodVignette (CanvasLayer layer=10, blood_vignette.gd)
    └── BloodRect (ColorRect full-rect, blood_vignette.gdshader)
```

- **职责：** 唯一编排入口——`_ready()` 时把 constants 氛围常量下发到四个子系统（月光色 → CanvasModulate.color；水墨 uniform → shader；雪幕调参 → snow_curtain；血色初始 alpha 0），并提供 `set_low_health()` 契约 API。
- **State Properties：** `@export var moonlight_color: Color = C.MOONLIGHT_COLOR_APPLIED`（Spike 3 候选 A/B 切换点）、`@export var ink_edge_alpha: float = C.INK_EDGE_ALPHA_MAX`、`@export var ink_color: Color = C.INK_COLOR`、`@export var blood_alpha_max: float = C.BLOOD_VIGNETTE_ALPHA_MAX`、`@export var blood_fade_seconds: float = C.BLOOD_VIGNETTE_FADE_SECONDS`；`@onready` 引用 `_moonlight: CanvasModulate` / `_ink_rect: ColorRect` / `_blood: blood_vignette` / `_snow: snow_curtain`。
- **Key Methods：**

```gdscript
## 契约 API（#575 未来发射端唯一写入口）——low_health 信号 → 血色 vignette
func set_low_health(enabled: bool) -> void:
    _blood.set_enabled(enabled)          # 内部 0.5s Tween（alpha 0 ↔ 0.35）

## 测试/E2E 兜底（#575 未建期）：驱动同一契约路径，不绕过 tween
func debug_trigger_low_health() -> void:
    set_low_health(true)

func debug_clear_low_health() -> void:
    set_low_health(false)

func _ready() -> void:
    _moonlight.color = moonlight_color
    _apply_ink_uniforms()                # ink_edge_alpha / ink_color → shader material
    _snow.apply_tunables()               # 速度/scale/alpha/wind 下发
```

- **Integration notes：** 不发射信号（纯消费端）；#575 实现时在玩家实体 `low_health` 信号处 `connect(controller.set_low_health)`，发射端归 #575，本 issue 只建消费端。**层级约定注释写在文件头**（layer 1=UI 不动 / 2=水墨 / 3-5=雪幕 / 10=血色），#583 复用同一 .tscn 时照此约定。

### 2.2 snow_curtain.gd — 三层雪幕控制器

- **File:** `shandong-wolf/gdscripts/snow_curtain.gd`
- **Node structure：**

```
SnowCurtain (Node2D, snow_curtain.gd)
├── LayerFar (CanvasLayer layer=3)
│   └── Parallax (Parallax2D scroll_scale=0.2)
│       └── Particles (GPUParticles2D, amount=60, process_material)
├── LayerMid (CanvasLayer layer=4)
│   └── Parallax (Parallax2D scroll_scale=0.5)
│       └── Particles (GPUParticles2D, amount=60, process_material)
└── LayerNear (CanvasLayer layer=5)
    └── Parallax (Parallax2D scroll_scale=1.0)
        └── Particles (GPUParticles2D, amount=80, process_material)
```

- **职责：** 三层雪幕的发射/调参管理。**硬约束（rain_curtain 教训，PRD §4.1）：`amount` 只在 .tscn 静态声明一次（60/60/80 = 200，AC1 中心值），运行时一律禁改**——密度/速度/大小经 initial_velocity / scale / color alpha 表达；`snow_wind` 调参走同一路径（改 initial_velocity 的 x 分量与 rotation，不改 amount）。
- **State Properties：** `@export var velocity_min: float = C.SNOW_VELOCITY_MIN`、`@export var velocity_max: float = C.SNOW_VELOCITY_MAX`、`@export var scale_far: float = C.SNOW_SCALE_FAR`（0.5x）、`@export var scale_near: float = C.SNOW_SCALE_NEAR`（1.5x）、`@export var alpha_min/max: float = C.SNOW_ALPHA_MIN/MAX`、`@export var wind: float = C.SNOW_WIND_DEFAULT`；`@onready` 三层引用（Parallax + Particles + process_material）。
- **Key Methods：**

```gdscript
func apply_tunables() -> void:
    # 每层: velocity → process_material.initial_velocity_min/max（20-40px/s 向下）
    #       scale → particles.scale_amount（远 0.5 / 中 1.0 / 近 1.5，AC1）
    #       alpha → particles.modulate.a（70-90%）
    #       wind  → initial_velocity x 分量 + 粒子 rotation（默认 0，Boss 战可加大）

func set_wind(intensity: float) -> void:
    wind = intensity
    apply_tunables()          # #583 复用点：Boss 战雪势加大（配方 §1 snow_wind）
```

- **发射配置（.tscn 静态）：** `emitting=true`、`one_shot=false`、`explosiveness=0`；发射区域 rect 覆盖视口 + margin（1280x720 + 256px margin，配方 §1 惯例，防三层视差屏幕边缘穿帮，PRD §5.2-2）；粒子用 `ParticleProcessMaterial`：`gravity = Vector2(0, 60)`（轻重力向下）、`initial_velocity_min/max`、`lifetime` 由层高/速度推算（约 8-15s 保证飘满全程）。
- **Integration notes：** 由 atmosphere_controller 在 `_ready()` 调 `apply_tunables()`；Parallax2D 是 Godot 4.7 原生视差节点，#583 相机移动时自动生效（视差 0.2/0.5/1.0 随相机滚动，无需额外代码）。

### 2.3 ink_wash.gdshader — 全屏水墨晕染

- **File:** `shandong-wolf/gdscripts/ink_wash.gdshader`
- **shader_type：** `canvas_item`（headless 编译安全，mini-pong `vignette.gdshader` 同构已验证；零后处理管线，PRD §4.3 方案 A）
- **完整源码（约 20 行 GLSL，实现可直接采用）：**

```glsl
// ink_wash.gdshader — 全屏水墨晕染（#582, PRD §4.3 方案 A；AC3 硬约束: edge_alpha ≤ 0.3）
shader_type canvas_item;
uniform float edge_alpha : hint_range(0.0, 0.3) = 0.3;   // AC3 硬上限（hint_range 上界=0.3，不遮挡战斗读图）
uniform float inner_radius : hint_range(0.0, 1.0) = 0.62; // 中央读图区不变暗半径（归一化，taste-draft）
uniform float softness : hint_range(0.0, 1.0) = 0.35;     // 边缘过渡柔和度（taste-draft）
uniform float noise_amount : hint_range(0.0, 0.2) = 0.06; // 墨色渗化抖动强度（taste-draft）
uniform vec3 ink_color : source_color = vec3(0.102, 0.122, 0.149); // 墨色 #1a1f26（配方 §3，taste-draft）

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    float edge = smoothstep(inner_radius, inner_radius + softness, dist);
    float noise = (hash(floor(UV * 80.0)) - 0.5) * noise_amount;  // 墨色渗化抖动（静态单 pass）
    float ink = clamp(edge + noise, 0.0, 1.0);
    COLOR.rgb = mix(COLOR.rgb, ink_color, ink * edge_alpha);
    COLOR.a = max(COLOR.a, ink * edge_alpha);                     // 暗带自身 alpha（盖住下层，同 vignette 模式）
}
```

- **Integration notes：** 挂全屏 ColorRect（`atmosphere_layer.tscn` 内 InkWashLayer/InkWash，anchors full-rect，`mouse_filter=IGNORE` 不挡输入）；uniform 由 atmosphere_controller `_ready()` 下发（默认即常量值，@export 可调）；`hint_range` 上界 0.3 = AC3 硬约束的声明式表达，test 断言 uniform 值 ≤ 0.3。

### 2.4 blood_vignette.gd + blood_vignette.gdshader — 血色低血 vignette

- **File:** `shandong-wolf/gdscripts/blood_vignette.gd` + `shandong-wolf/gdscripts/blood_vignette.gdshader`
- **Node structure：**

```
BloodVignette (CanvasLayer layer=10, blood_vignette.gd)   # 层级常量 BLOOD_VIGNETTE_LAYER=10
└── BloodRect (ColorRect full-rect, blood_vignette.gdshader, mouse_filter=IGNORE)
```

- **职责：** 玩家低血时的生死压迫感——**红色是唯一允许打破冷色调的高饱和元素**（配方 §0 环境低饱和/关键物高对比）；alpha 0→0.35（AC4 硬上限）0.5s 平滑渐变（Tween，ease 可 taste）。默认 alpha 0（待命，不干扰常态画面）。
- **State Properties：** `@export var alpha_max: float = C.BLOOD_VIGNETTE_ALPHA_MAX`（0.35）、`@export var fade_seconds: float = C.BLOOD_VIGNETTE_FADE_SECONDS`（0.5）；`var _enabled: bool = false`；`var _tween: Tween`（create_tween 单例，重复触发先 kill 再建，防叠加）。
- **Key Methods：**

```gdscript
func set_enabled(enabled: bool) -> void:
    if enabled == _enabled: return              # 幂等守卫（信号重复触发不重启 tween）
    _enabled = enabled
    if _tween and _tween.is_valid(): _tween.kill()
    _tween = create_tween()
    _tween.tween_property($BloodRect, "modulate:a", 1.0 if enabled else 0.0, fade_seconds)
    # 视觉 alpha = modulate.a × alpha_max（0→1 × 0.35 = 0→0.35，AC4）
    # ease 默认 LINEAR；taste 候补: TRANS_SINE（0.5s 平滑，用户裁决项）

func get_visual_alpha() -> float:
    return $BloodRect.modulate.a * alpha_max    # test 采样点（tween 终点断言 0.35）
```

- **blood_vignette.gdshader（径向血色版，模式参考 mini-pong vignette.gdshader）：**

```glsl
// blood_vignette.gdshader — 血色低血 vignette（#582, PRD §4.4 方案 A；AC4: 视觉 alpha 0→0.35）
shader_type canvas_item;
uniform float strength : hint_range(0.0, 0.35) = 0.35;   // 峰值强度上限 0.35（AC4，hint_range 上界声明）
uniform float inner_radius : hint_range(0.0, 1.0) = 0.55; // 中央读图区不变暗半径（taste-draft）
uniform float softness : hint_range(0.0, 1.0) = 0.4;      // 边缘过渡柔和度（taste-draft）
uniform vec3 blood_color : source_color = vec3(0.55, 0.05, 0.05); // 血色（taste-draft，暗红不发亮）

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    float edge = smoothstep(inner_radius, inner_radius + softness, dist);
    COLOR.rgb = mix(COLOR.rgb, blood_color, edge * strength);
    COLOR.a = max(COLOR.a, edge * strength);
}
```

- **Integration notes：** 由 atmosphere_controller 转发 `set_low_health(enabled)`；#575 玩家实体未来 emit `low_health` → controller 连接；当前 `debug_trigger_low_health()` / `debug_clear_low_health()` 供测试/E2E 驱动（参数契约→执行层模式，PRD §8）。**契约文档化进文件头注释**（#575 实现时按契约接入，发射端归 #575）。

### 2.5 atmosphere_layer.tscn — 场景无关氛围层组件

- **File:** `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn`
- **Node structure（= §2.1 全树，根脚本 atmosphere_controller.gd）：** `Atmosphere (Node2D)` → SnowCurtain（含 3×CanvasLayer+Parallax2D+GPUParticles2D）/ Moonlight（CanvasModulate）/ InkWashLayer（CanvasLayer 2 + ColorRect + ink_wash.gdshader）/ BloodVignette（CanvasLayer 10 + ColorRect + blood_vignette.gdshader）。
- **关键静态配置（.tscn 内声明，运行时不改）：** GPUParticles2D `amount` = 60/60/80；Parallax2D `scroll_scale` = 0.2/0.5/1.0；CanvasModulate `color` = `Color(0.431, 0.463, 0.518, 1)`（= #6e7684）；ColorRect `anchors_preset=15`（full-rect）+ `mouse_filter=2`（IGNORE）；两个 shader material 引用 .gdshader。
- **Integration notes：** Main.tscn 根节点下实例化（§3.3）；#583 战斗场景复用同一 .tscn 实例化进战斗场景根（月亮视觉节点归 #583，作为战斗场景自身节点挂载，与氛围层无冲突）；复用约定写入文件头注释（层级 2/3-5/10 照抄）。

---

## 3. 既有组件修改

### 3.1 文件清单总表

| 类别 | 文件 | 变更性质 |
|------|------|---------|
| 新建 | `shandong-wolf/gdscripts/atmosphere_controller.gd` | 编排入口 + 契约 API |
| 新建 | `shandong-wolf/gdscripts/snow_curtain.gd` | 三层雪幕控制器 |
| 新建 | `shandong-wolf/gdscripts/ink_wash.gdshader` | 水墨 shader |
| 新建 | `shandong-wolf/gdscripts/blood_vignette.gd` + `.gdshader` | 血色 vignette |
| 新建 | `shandong-wolf/scenes/atmosphere/atmosphere_layer.tscn` | 场景组件 |
| 新建 | `shandong-wolf/tests/test_atmosphere.gd` | 测试套件（§8 用例描述） |
| 修改 | `shandong-wolf/gdscripts/constants.gd` | 尾部追加「氛围参数」# DRAFT 分区 |
| 修改 | `shandong-wolf/scenes/Main.tscn` | 根节点下实例化 Atmosphere |
| 修改 | `shandong-wolf/tests/run_tests.gd` | 挂载 test_atmosphere.gd |
| 修改 | `shandong-wolf/e2e_shots.json` | 追加雪夜氛围单帧 |
| 移除/弃用 | 无 | — |
| 受影响测试 | `shandong-wolf/tests/test_constants.gd` | 不改（氛围分区断言归 test_atmosphere.gd，防跨套件耦合）；新增 test_atmosphere.gd 挂载进 run_tests.gd |

### 3.2 constants.gd — 追加「氛围参数」分区（文件尾部，格式照 #572 既有分区）

```gdscript
# ── 氛围参数（# DRAFT 候补值，定稿 = #582 E2E 用户裁决）──
#   四组: 雪幕 SNOW_* / 冷月光 MOONLIGHT_* / 水墨 INK_* / 血色 BLOOD_*
#   定稿机制: implement PR 附截图 → 用户 ≥70% 裁决 → 定稿（taste-draft；与 #584 手感定稿互不干扰）

# ── 雪幕（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 远 60 / 中 60 / 近 80 = 200 粒子（AC1 中心值）；视差 0.2x/0.5x/1.0x；scale 近 1.5x 远 0.5x；飘落 20-40px/s；白色 α70-90%
#   该值影响什么: 雪夜纵深与密度——三层视差营造空间，粒子密度决定氛围浓度；amount 只在 .tscn 静态声明，运行时禁改（rain_curtain 教训）
#   情感断言: 苍白、清冷——雪是安静的背景呼吸，不是注意力主角（体验引擎 Atmosphere: 氛围是被感知的背景层）
const SNOW_PARTICLES_FAR: int = 60              # # DRAFT
const SNOW_PARTICLES_MID: int = 60              # # DRAFT
const SNOW_PARTICLES_NEAR: int = 80             # # DRAFT（合计 200）
const SNOW_PARALLAX_FAR: float = 0.2            # # DRAFT（Parallax2D scroll_scale）
const SNOW_PARALLAX_MID: float = 0.5            # # DRAFT
const SNOW_PARALLAX_NEAR: float = 1.0           # # DRAFT
const SNOW_SCALE_FAR: float = 0.5               # # DRAFT（AC1: 远景 0.5x）
const SNOW_SCALE_NEAR: float = 1.5              # # DRAFT（AC1: 近景 1.5x）
const SNOW_VELOCITY_MIN: float = 20.0           # # DRAFT（px/s 飘落速度下界）
const SNOW_VELOCITY_MAX: float = 40.0           # # DRAFT（px/s 上界）
const SNOW_ALPHA_MIN: float = 0.7               # # DRAFT（白色 α70-90%）
const SNOW_ALPHA_MAX: float = 0.9               # # DRAFT
const SNOW_WIND_DEFAULT: float = 0.0            # # DRAFT（风向，Boss 战可加大，配方 §1）

# ── 冷月光（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 目标色温 #b8c4d9（issue AC2 字面值）；CanvasModulate 无独立 brightness，「亮度 0.6」经色值换算 ≈ #6e7684（PRD §4.2 方案 B，单节点单一事实源）
#   该值影响什么: 全场景色温基调——冷月色调先于任何玩法传达『雪夜大刀』
#   情感断言: 苍白、清冷——只狼苇名城雪夜 + 抗战黑白电影月光；禁止阳光明媚/星光点缀；#2a3a4a（配方暗基底）记入候补对照
const MOONLIGHT_COLOR_TARGET: Color = Color("#b8c4d9")   # # DRAFT（AC2 字面色值）
const MOONLIGHT_COLOR_APPLIED: Color = Color("#6e7684")  # # DRAFT（= TARGET × 0.6 换算，Spike 3 截图对比候选 A）
const MOONLIGHT_BRIGHTNESS: float = 0.6                  # # DRAFT（语义 = 色值换算系数）

# ── 水墨晕染（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 边缘暗角 alpha ≤ 0.3（AC3 硬约束，不遮挡战斗读图）；墨色 #1a1f26；径向暗角 + 噪声渗化
#   该值影响什么: 全屏水墨质感——『黑白电影/水墨画』审美的核心载体
#   情感断言: 大地如墨——暗角是氛围不是遮挡，中央读图区必须保持通透
const INK_EDGE_ALPHA_MAX: float = 0.3            # # DRAFT（硬上限，shader hint_range 上界同值）
const INK_COLOR: Color = Color("#1a1f26")        # # DRAFT（墨色参考，配方 §3）
const INK_INNER_RADIUS: float = 0.62             # # DRAFT（归一化中央不变暗半径）
const INK_SOFTNESS: float = 0.35                 # # DRAFT（边缘过渡柔和度）
const INK_NOISE_AMOUNT: float = 0.06             # # DRAFT（噪声渗化抖动强度）

# ── 血色 vignette（# DRAFT 候补值，待 #582 用户裁决）──
#   候补值: 低血触发 alpha 0→0.35（AC4 硬上限），0.5s 平滑渐变；CanvasLayer layer=10
#   该值影响什么: 玩家低血时的生死压迫感——红色只在危险时出现（环境低饱和/关键物高对比，配方 §0）
#   情感断言: 刀刀见血不拖沓——血色是唯一允许打破冷色调的高饱和元素
const BLOOD_VIGNETTE_ALPHA_MAX: float = 0.35     # # DRAFT（硬上限）
const BLOOD_VIGNETTE_FADE_SECONDS: float = 0.5   # # DRAFT（Tween 时长，AC4）
const BLOOD_VIGNETTE_LAYER: int = 10             # 机械常量（CanvasLayer 层级约定，定稿）
```

### 3.3 scenes/Main.tscn — 实例化氛围层

| 变更 | 内容 | 为什么 |
|------|------|--------|
| 根节点 `Main`（Node2D）下追加子节点 | `[node name="Atmosphere" parent="." instance=ExtResource("...atmosphere_layer.tscn")]` + `[ext_resource type="PackedScene" path="res://scenes/atmosphere/atmosphere_layer.tscn" id="..."]` | 氛围层随标题场景首帧成立（场景 A『第一印象』）；渲染层在自身 CanvasLayer 层级（2/3-5/10），与现有 UI layer=1 并存不冲突 |

```gdscript
# 变更后 Main.tscn 结构（氛围层插入，UI 节点零改动）:
# Main (Node2D)
# ├── Atmosphere (atmosphere_layer.tscn 实例)   ← 新增（内部 CanvasLayer 2/3-5/10）
# └── CanvasLayer (layer=1)                     ← 现有 UI 不动
#     └── CenterContainer/VBox → TitleLabel/SubtitleLabel/VersionLabel/PostMergeProbeLabel
```

### 3.4 tests/run_tests.gd + e2e_shots.json — 测试挂载与单帧截图

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `tests/run_tests.gd` | `_run_tests()` 追加一行 `_run("res://tests/test_atmosphere.gd", "Atmosphere")` | 新套件纳入三入口（#572 模式） |
| `e2e_shots.json` | `states` 保持空；`groups` 追加 `snow_night` 组（match `gdscripts/.*\.gd` + `scenes/.*\.tscn`），内含单帧 shot `01_snow_night_atmosphere`（state 空、settle_frames 30、`_comment` 注明「#582 单帧氛围截图供用户 ≥70% 裁决，完整剧本归 #586」） | PRD §3.1 要求追加单帧；v2 schema（`groups[].shots[]`）与 mini-pong 先例兼容；#586 接入完整 harness 时此组自动生效 |

> ⚠️ **实现期说明：** shandong-wolf 的 e2e harness 由 #586 完整接入（当前 JSON 为占位）。若 #586 未落地，实现 PR 用 `godot --path shandong-wolf/ --headless` 启动 + 截图脚本（框架 `e2e_capture.gd` 单帧模式或 `scripts/run-e2e-review.sh` 路径）产出单帧 PNG 附 PR——**PR 必须附截图**（AC5，用户裁决输入物）。

---

## 4. 数据流

### Flow 1: 首帧氛围成立（正常路径）

```
Main.tscn 加载
  → Atmosphere 实例 _ready()
  → atmosphere_controller._ready():
      Moonlight.color = MOONLIGHT_COLOR_APPLIED (#6e7684)      # 冷月色调即刻生效
      ink uniforms 下发（edge_alpha ≤ 0.3 / ink_color #1a1f26） # 水墨暗角即刻生效
      snow_curtain.apply_tunables()                              # 三层粒子参数下发
      blood_vignette alpha = 0                                   # 血色待命
  → 首帧渲染: 雪幕 3 层（60/60/80 粒子, 视差 0.2/0.5/1.0, 近大远小）
      + 冷月底色 + 水墨暗角 → 『雪夜第一印象』成立
  → E2E 截图（headless）→ PNG 附实现 PR → 用户 ≥70% 裁决 → 参数定稿
```

### Flow 2: 低血触发血色 vignette（事件路径）

```
#575 玩家实体（未来）: 生命 ≤ 阈值 → emit low_health
    │（本 issue 期: 测试/E2E 用 debug_trigger_low_health() 驱动同一路径）
    ▼
AtmosphereController.set_low_health(true)
    ▼
blood_vignette.set_enabled(true)   # 幂等守卫（重复触发不重启）
    ▼
Tween 0.5s: BloodRect.modulate.a 0 → 1（视觉 alpha 0 → 0.35）
    ▼
玩家恢复 → set_low_health(false) → Tween 0.5s 回落 alpha 0（#575 恢复信号；测试用 debug_clear_low_health()）
```

### Flow 3: 调参 / 定稿（taste-draft 路径）

```
用户裁决 < 70% 或观感偏差
  → 改 constants.gd 候补值（SNOW_ALPHA / INK_SOFTNESS / BLOOD_* 等）——只改常量，不动结构
  → 或调 atmosphere_layer.tscn 内 @export（编辑器直调，运行时热更）
  → 重跑 E2E 截图 → 再裁决（# DRAFT 机制吸收迭代，PRD §5.3-3）
```

### Flow 4: 失败路径（shader 编译失败 / 截图黑屏）

```
ink_wash.gdshader 语法错误
  → check_compile.gd 遍历 load 失败 → CI 红
  → 本地 godot --path shandong-wolf/ --headless 复现（mini-pong vignette.gdshader 可对照）
  → 修复 shader → 重跑三入口 → 截图复核（PRD §5.3-1/2）
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| 运行时 amount 被误改/漂移（rain_curtain 教训） | `amount` 仅在 .tscn 静态声明（60/60/80），`snow_curtain.gd` 文件头注释禁改红线；test 断言 amount 合计 180–220（AC1 区间），越界 CI 红 |
| 三层视差屏幕边缘穿帮（1280x720 下近景层覆盖不足） | 发射区域 rect = 视口 + margin（配方 §1 惯例）；test/截图复核边缘无黑缝 |
| headless CI 编译 shader | `check_compile.gd` 自动纳入新 .gd/.gdshader（#572 机制），语法错误即红，零额外配置 |
| CanvasModulate 提亮后标题文字对比度下降 | AC2 实现期 E2E 截图含标题场景验证文字可读；必要时 INK_COLOR 加深补偿（PRD §5.2-4，用户裁决项） |
| `low_health` 信号源缺失（#575 未实现） | `debug_trigger_low_health()` / `debug_clear_low_health()` 兜底走同一契约路径；契约文档化进文件头，#575 实现时按契约接入 |
| 血色 Tween 重复触发（信号抖动） | `set_enabled` 幂等守卫（同值直接 return）+ tween 先 kill 再建，防叠加/防重启跳变 |
| 水墨暗角叠加雪幕近景导致叠加 alpha 超标 | 径向设计保证中央读图区不受影响（inner_radius 0.62）；边缘叠加 alpha 上限验证（test 采样四角 + 中央） |
| #583 复用时的层级冲突（月亮节点/雪幕先后、相机视差联动） | 层级约定写入 atmosphere_layer.tscn 文件头（2=水墨/3-5=雪幕/10=血色/UI=1 不动）；月亮节点归 #583 自身挂载，与氛围层无冲突 |
| 性能预算 | 200 粒子 GPU 开销可忽略；全屏 shader 单 pass；1280x720 目标 ≥55fps（帧耗时断言可选，PRD §5.2-8） |
| E2E 截图黑屏/全白（CanvasLayer 层级/覆盖错误） | 层级断言（test 检查各 CanvasLayer.layer 值）+ 人工截图复核（PRD §5.3-2） |
| 用户裁决 < 70% | 参数迭代（改 constants 候补值 → 重跑 E2E → 再裁决），不重写架构（taste-draft 队列模式，PRD §5.3-3） |

---

## 6. 集成点

> **Status convention：** ⬜ = pending（资源已创建，尚未连接到目标）。✅ = connected（implement agent 验证）。implement agent 必须在此表更新接线状态；review agent merge 前验证所有 ⬜ 已解决或显式延期。

| 集成 | 本组件 | 目标 | 如何连接 | 状态 |
|------|:---:|:---:|---------|:---:|
| 场景挂载 | `atmosphere_layer.tscn` 实例 | Main.tscn 根节点（#582 本体） | 实例化子节点 Atmosphere（§3.3） | ✅ connected（implement #582 验证） |
| 参数下发 | `atmosphere_controller.gd` | constants.gd 氛围分区 | preload `C` + `_ready()` 读取常量（§2.1） | ✅ connected（implement #582 验证） |
| 雪幕调参 | `snow_curtain.apply_tunables()` | 3×Parallax2D + 3×GPUParticles2D | @onready 引用 + process_material 属性写入（§2.2） | ✅ connected（implement #582 验证） |
| 水墨 uniform | `atmosphere_controller._ready()` | ink_wash.gdshader material | shader material 的 `set_shader_parameter()`（§2.3） | ✅ connected（implement #582 验证） |
| 血色契约 | `set_low_health(enabled)` | blood_vignette.set_enabled() | controller 转发 + Tween（§2.4） | ✅ connected（implement #582 验证） |
| 低血信号源 | `debug_trigger_low_health()`（本 issue） | #575 玩家实体 `low_health` 信号（未来） | #575 实现时 `connect(controller.set_low_health)`；发射端归 #575，本 issue 只建消费端 | ⬜ pending（显式延期至 #575） |
| E2E 单帧 | e2e_shots.json `snow_night` 组 | #586 E2E 完整剧本 harness | #586 接入 harness 时自动生效；本 issue 实现 PR 用 headless 截图附 PR（AC5） | ⬜ pending（显式延期至 #586） |
| 战斗场景复用 | `atmosphere_layer.tscn` 实例 | #583 战斗场景 | #583 实现时实例化同一 .tscn（月亮节点归 #583） | ⬜ pending（显式延期至 #583） |
| 测试挂载 | `tests/test_atmosphere.gd` | run_tests.gd | `_run_tests()` 追加 `_run(...)` 一行（§3.4） | ✅ connected（implement #582 验证） |

---

## 7. 实现阶段

| Phase | 优先级 | 组件 | 内容 | 估计 |
|:-----:|:------:|------|------|:----:|
| Phase 0 | P0 | Spike 验证（PRD §7 三实验） | ① 全屏 ColorRect+shader headless 编译 + 截图；② 三层雪幕观感基线截图；③ 冷月光亮度 0.6 语义候选 A/B 对比截图 | 0.5d |
| Phase 1 | P0 | constants.gd 氛围分区 | 尾部追加四组 `# DRAFT` 常量（§3.2 源码可直接采用） | 0.5d |
| Phase 2 | P0 | 四个氛围组件 | atmosphere_controller.gd / snow_curtain.gd / ink_wash.gdshader / blood_vignette.gd+.gdshader（§2.1–2.4） | 1d |
| Phase 3 | P0 | 场景组件 + 挂载 | atmosphere_layer.tscn 组装 + Main.tscn 实例化 + run_tests.gd 挂载（§2.5/§3.3/§3.4） | 0.5d |
| Phase 4 | P0 | 测试套件 | test_atmosphere.gd（§8 用例描述） | 0.5d |
| Phase 5 | P0 | E2E 截图 + 用户裁决 | headless 单帧截图附 PR + issue 评论 + assign 用户（AC5；taste-draft 定稿接口） | 0.5d |

---

## 8. 测试用例描述

> 仅描述测试场景，不写可运行测试代码（plan 阶段红线；实现由 implement agent 完成，落 `shandong-wolf/tests/test_atmosphere.gd`，套件模式照 test_constants.gd：`passed/failed` 计数 + `run()`）。

### Scenario A: 参数集中与分区存在性（test_atmosphere.gd）
- **A1（四组氛围常量齐全）**: `WolfConstants` 存在 `SNOW_*`（≥10 项：PARTICLES_FAR/MID/NEAR、PARALLAX_*、SCALE_FAR/NEAR、VELOCITY_MIN/MAX、ALPHA_MIN/MAX、WIND_DEFAULT）/ `MOONLIGHT_*`（COLOR_TARGET/COLOR_APPLIED/BRIGHTNESS）/ `INK_*`（EDGE_ALPHA_MAX/COLOR/INNER_RADIUS/SOFTNESS/NOISE_AMOUNT）/ `BLOOD_*`（ALPHA_MAX/FADE_SECONDS/LAYER），任一缺失 FAIL。
- **A2（候补值未定稿）**: constants.gd 源码氛围分区含 ≥20 处 `# DRAFT` 标记；分区注释含「待 #582 用户裁决」语义（防与 #584 手感定稿混淆）；不含「# 定稿」字样。
- **A3（硬约束常量）**: `INK_EDGE_ALPHA_MAX ≤ 0.3`、`BLOOD_VIGNETTE_ALPHA_MAX == 0.35`、`BLOOD_VIGNETTE_FADE_SECONDS == 0.5`、`SNOW_PARTICLES_FAR+MID+NEAR == 200`（AC1 中心值）。

### Scenario B: 雪幕三层结构断言（test_atmosphere.gd）
- **B1（三层 + 视差 + 粒子数）**: 加载 atmosphere_layer.tscn 实例 → 断言 GPUParticles2D 节点数 == 3；`amount` 合计 180–220（AC1 ±10% 区间）且分布 == [60, 60, 80]；Parallax2D `scroll_scale` == [0.2, 0.5, 1.0]。
- **B2（近大远小 scale）**: 断言近景层 `scale_amount` ≈ 1.5x、远景层 ≈ 0.5x（AC1）；中景 ≈ 1.0x。
- **B3（禁改 amount 红线）**: snow_curtain.gd 源码 grep 无 `amount =` 赋值语句（仅 .tscn 静态声明；防 rain_curtain 教训回归）。
- **B4（发射配置）**: 三层 `emitting == true`、`one_shot == false`；发射区域 rect 覆盖 ≥ 1280x720 + margin（边缘无黑缝）。

### Scenario C: 冷月光（test_atmosphere.gd）
- **C1（节点 + 色值）**: 实例中存在 CanvasModulate 节点；`color` 与 constants 关联（`MOONLIGHT_COLOR_APPLIED` 默认 #6e7684，若 Spike 3 改候选 A 则为 #b8c4d9——断言与 controller 的 @export 默认值一致即可，不硬编码）。
- **C2（换算注释）**: constants.gd 中 `MOONLIGHT_COLOR_APPLIED` 行含换算注释（`× 0.6` 语义），防未来调参丢失亮度语义。

### Scenario D: 水墨 shader（test_atmosphere.gd）
- **D1（uniform 硬上限）**: ink_wash.gdshader 源码断言 `edge_alpha` 的 hint_range 上界 ≤ 0.3 且默认值 ≤ 0.3（AC3 硬约束的声明式检查）。
- **D2（全屏覆盖 + 不挡输入）**: InkWash ColorRect `anchors_preset == 15`（full-rect）+ `mouse_filter == IGNORE`（不挡后续战斗输入）。
- **D3（shader 编译）**: check_compile 覆盖 ink_wash.gdshader / blood_vignette.gdshader（F1 回归项，语法错误即红）。

### Scenario E: 血色 vignette（test_atmosphere.gd）
- **E1（层级 + 初始待命）**: BloodVignette CanvasLayer `layer == 10`；实例初始 `get_visual_alpha() == 0.0`（待命不干扰常态画面）。
- **E2（0.5s 平滑渐变到 0.35）**: `debug_trigger_low_health()` → 立即采样 alpha 接近 0 → 0.5s 后（或 tween 完成后）`get_visual_alpha() ≈ 0.35`（AC4）；断言 tween 时长 == `BLOOD_VIGNETTE_FADE_SECONDS`。
- **E3（回落 + 幂等）**: `debug_clear_low_health()` → 0.5s 后 alpha 回 0；连续两次 `set_low_health(true)` 不重启 tween（幂等守卫，无跳变）。
- **E4（契约直达）**: `set_low_health(true)` 与 `debug_trigger_low_health()` 走同一路径（debug 不绕过 tween——断言 debug 触发后 alpha 也是渐进非瞬跳）。

### Scenario F: 三入口回归（CI / 本地）
- **F1（check_compile）**: `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0，count 覆盖新增 5 gdscripts + 2 gdshader + 1 tests 脚本（#572 自动纳入机制）。
- **F2（run_tests）**: `... --script tests/run_tests.gd` 退出 0，输出「TESTS: N passed, 0 failed」且 N ≥ 原 StateMachine/Constants 用例数 + 本套件 A-E 场景用例数；pass==0 → 退出非 0（防挂载遗漏静默绿）。
- **F3（主场景冒烟）**: `godot --path shandong-wolf/ --headless --quit` 退出 0（autoload + Main.tscn + Atmosphere 实例启动链兼容）。
- **F4（E2E 单帧截图）**: headless 启动 Main.tscn 截图（settle 30 帧）→ PNG 非黑屏非全白、文件非空（AC5 输入物；人工复核观感）。

---

## 9. 验收条件映射（源自 Issue #582 body）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 雪幕粒子数 200±10%，三层视差（0.2x/0.5x/1.0x）且近景雪更大（scale 1.5x 远景 0.5x） | §2.2 三层结构 + §3.2 SNOW_* 常量 | B1/B2（节点数/amount 合计/scroll_scale/scale）+ A3 |
| AC2 | CanvasModulate 色温 #b8c4d9，场景整体呈冷月色调 | §2.1 Moonlight 节点 + §3.2 MOONLIGHT_*（方案 B #6e7684 换算，Spike 3 裁决） | C1/C2（节点 + 色值 + 换算注释）；观感由 F4 截图用户裁决 |
| AC3 | 水墨 shader 全屏生效，边缘暗角 alpha ≤0.3（不遮挡战斗读图） | §2.3 ink_wash.gdshader（hint_range 上界 0.3） | D1/D2（uniform 上限 + 全屏覆盖）+ F4 截图复核 |
| AC4 | 玩家 low_health 信号触发血色 vignette 平滑 0.5s 渐变（0→0.35） | §2.4 契约 API + Tween + §3.2 BLOOD_* 常量 | E1/E2/E3/E4（层级/渐变时长/终点 alpha/幂等）+ A3 |
| AC5 | E2E 截图提交用户裁决：雪夜氛围 ≥70%『黑白电影/水墨画』质感且不干扰战斗可读性 | §7 Phase 5 截图附 PR + issue 评论 + assign 用户（taste-draft 定稿接口） | F4 截图 + 用户主观评分（≥70% 定稿，<70% 走 Flow 3 参数迭代） |
| 附加红线 | 参数全部集中 constants.gd 氛围分区 # DRAFT + 情感断言；零外部美术资产；禁 amount 直改 | §3.2 四组常量 + 文件头红线注释 | A1/A2/B3（分区存在 + # DRAFT + 无 amount 赋值）+ implement PR diff 核查无 .png/.jpg 新增 |

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `mini-pong/` 任何文件（跨游戏红线；rain_curtain/vignette 仅模式参考）
- ❌ `shandong-wolf/tests/check_compile.gd`、`shandong-wolf/tests/smoke_test.gd`（#572 机制自动纳入新脚本，零改动）
- ❌ `shandong-wolf/gdscripts/state_machine.gd`、`shandong-wolf/gdscripts/game.gd`（本 issue 不涉及；Game autoload 的 Atmosphere 访问点为可选增强，PRD §3.3 标注非必须，**不做**）
- ❌ `game-env/manifest.yaml`、`.github/workflows/`、`scripts/`（管线参数化已自动跟随）
- ❌ `docs/GAME_DESIGN/`（场景结构表更新是 post-merge agent 职责）
- ❌ #583 月亮视觉节点 / 场景几何 / #575 玩家实体 / #576 HUD / #584 手感数值定稿 / #586 完整 E2E 剧本（范围边界见 PRD §1.4）
- ❌ 任何外部美术资产 / 插件 addon / 像素帧 / 贴图（AC5 红线 + PRD 硬约束⑥）
- ✅ constants.gd 既有 5 个手感分区保持原样（只在文件尾部追加氛围分区）
- ✅ Main.tscn 现有 UI 节点（TitleLabel/SubtitleLabel/VersionLabel/PostMergeProbeLabel + CanvasLayer layer=1）零改动

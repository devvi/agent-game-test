# DESIGN: [Feature] 游戏画面迭代 — 雨夜竞技场画面丰富化执行层（城市光晕/暗角/L2 反馈/波次色变/特殊砖视觉）

> **Parent Issue:** #527
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** A + A + A（PRD §4.6 推荐组合逐项确认）——L0 光晕 = 渐变 ColorRect + 呼吸（4.1-A）；L0 暗角 = CanvasItem shader 主案 + 径向渐变 fallback（4.2-A，fallback 升级为 B'）；L2 反馈 = 统一 FeedbackFX 控制器 + 首期 2 项（4.3-A+C）；v1 波次色变 = 暖色系 palette 表（4.4-A）；v1 特殊砖 = variant 枚举 + 显式色映射（4.5-A）
> **Reference PRD:** docs/PRD/527-visual-enrichment.md（research PR #530 已合并；#532 为重复 research PR 已关闭）
> **上游方案:** docs/PLAN-rogue-pong.md §3.1（L0 氛围层 = 雨幕粒子 + 底部城市光晕 + 暗角 ≤10%；L2 反馈层 = 破砖闪光/穿墙脉冲/得分弹出/挡板 squash）+ §5 v1 切片（波次色变 + 特殊砖视觉）+ §3.3 动效纪律（Tween 150–300ms，不弹跳）
> **所有权:** `content_ownership: mixed`——机制/常量结构/信号接线 = mechanical（可测）；光晕色调、暗角强度、色变 palette 色值、铁砖配色 = taste-draft（本 DESIGN 给占位值，human-review 定稿，调参零代码改动）
> **深度:** depth/standard——产出 DESIGN + TASKS 两份文档（5 个子系统 = 5 个不同子系统的独立实现子任务，达 skill standard TASKS 阈值：5+ distinct subtasks）；测试仅描述不写代码
> **并行上下文:** 无（#527 无其他 plan/impl 分支在途；#526 research 已独立完成，文件域无交集）

---

## 1. 架构总览

Mini Pong（`mini-pong/`，Godot 4.7.1，竖屏 720×1280，Forward+）MVP 功能全落地，但 PLAN-rogue-pong 已确认的画面规格仍有 5 个子系统未执行（PRD §1.1 差距表）：L0 底部城市光晕、L0 暗角（≤10%）、L2 反馈层（破砖闪光/穿墙脉冲）、v1 波次色变（暖色系）、v1 特殊砖视觉（铁砖）。本设计把这 5 项规格**一次规划、分批实现**：

```
                         ★ Issue #527 画面丰富化执行层（本 DESIGN）
        ┌──────────────────────┬───────────────────────┬───────────────────────┐
        │ PR-A（L0 批，低风险先合）      │ PR-B（v1 批）                 │ 不触碰（红线）            │
        ▼                          ▼                       ▼                       ▼
  city_glow.gd（新）         feedback_fx.gd（新）      brick.tscn（color 字面被     world_environment.tscn
  vignette.gd（新）          breakout_grid.gd          test_visual_contrast       （test_neon 文本断言）
  vignette.gdshader（新）     brick.gd                  E2-2 锁定 → 运行时设色）     score_flash.gd（#289）
  Main.tscn（挂载）           constants.gd              e2e_shots.json /           雨幕/升级/暂停/标题文件
  constants.gd               （WAVE_COLOR_*/           analyze_bmp.py（不修改）
  （CITY_GLOW_*/VIGNETTE_*）   BRICK_VARIANT_* 区）
```

### 设计哲学（每一条都对应 PRD/上游已确认纪律）

1. **执行已确认规格，不发明**：5 子系统全部来自 PLAN §3.1/§5 已确认项，本设计只做「落地路径」，不新增特效、不扩大范围（克制纪律，Obsidian「抽象留白」+ CUSGA「堆砌反例」）。
2. **零侵入事件消费**：L2 反馈全部消费**既有信号**（`BreakoutGrid.brick_destroyed`、`GameManager.pierce_scored`），不修改 brick/scoring/ball 的既有逻辑与文件；`constants.gd` 只**追加** 4 个新区，既有区逐字节不动（#448/#449/#450/#464 并行先例）。
3. **glow 同色规避（#464 教训）**：`neon_glow.gdshader` 的 fragment 是 `mix(src_color, glow_color, glow * glow_color.a)`，且共享材质 `neon_glow_material.tres` 的 `glow_color.a = 1.0` → 边缘区域颜色被 glow_color 完全覆盖。**变体砖必须 `material.duplicate()` + 运行时 `set_shader_parameter("glow_color", ...)`**，绝不改共享 .tres（`test_visual_contrast` E3-2 文本断言锁定其内容）。
4. **结构性 E2E 保护**：新 L0 元素挂 `AtmosphereLayer`（已在 `game_world` 组，#508）→ MENU 态整组隐藏，`01_title` theme_absent 结构性安全；新增色一律避开 `#4a90d9`（tol 32，AC1/AC7）；暗角峰值暗度 ≤ 0.10 保证非黑断言安全。
5. **分层纪律（GDD22 + PLAN §3.1）**：L0 元素挂 AtmosphereLayer（layer=0）；L2 反馈用普通节点 + 树序靠后（默认 layer 0，绘制于世界之上、HUD layer=1 之下），不新建高 layer CanvasLayer，不高于 layer 2。
6. **动效纪律（PLAN §3.3）**：反馈 Tween 一律 150–300ms、不弹跳、不花哨；数值收敛于常量，human-review 可调。
7. **headless 安全**：暗角 shader 由 Spike 1 前置验证（Godot headless 编译 shader 不渲染，预期安全）；任一 shader 路径失败即走零 shader fallback（径向 GradientTexture2D），设计不塌方。
8. **文件域红线（AC8）**：实现 PR 文件白名单 = PR-A 6 文件 / PR-B 7 文件（§9 表格），绝不混入其他 issue 文件；`worktree-commit.sh` 白名单 add。

### PRD 方案确认

| 子系统 | PRD 推荐 | 本设计 | 说明 |
|--------|---------|--------|------|
| L0 城市光晕 | 4.1-A 渐变 ColorRect + 呼吸 | ✅ 采纳 | 程序化 GradientTexture2D（引擎内建，零 .tres 资产） |
| L0 暗角 | 4.2-A shader（fallback B 四角 ColorRect） | ✅ 采纳，fallback 升级 | fallback 用**径向 GradientTexture2D 单节点**（B'，优于四角 ColorRect：无衔接瑕疵、零 shader） |
| L2 反馈 | 4.3-A 控制器 + C 范围（破砖闪光+穿墙脉冲） | ✅ 采纳 | 得分弹出/挡板 squash 留接口，Spike 4 后追加 |
| v1 波次色变 | 4.4-A 暖色 palette 表 | ✅ 采纳 | hue ∈ [20°,60°]，palette[0]=BRICK_NEON 恒为波 1 |
| v1 特殊砖 | 4.5-A variant 枚举 + 显式色映射 | ✅ 采纳 | 首期铁砖（1），variant=2 奖励砖接口预留 |

---

## 2. 现状核实（plan agent 已对照源码确认，2026-08-17）

| 文件 | 现状 | 对本设计的影响 |
|------|------|---------------|
| `mini-pong/gdscripts/constants.gd` | 231 行，`class_name GameConstants`；分区至 `# ── Combo Speed Feedback (#504)`；**无 CITY_GLOW/VIGNETTE/WAVE_COLOR/BRICK_VARIANT 区**；`BRICK_NEON=#ff9d45`（hue 28.4°）、`PADDLE_NEON=#00e5ff`（hue 186.1°）、`BG_COLOR=#0a0a12`、`BG_PULSE_*` 区（4s/0.08/0.07） | 追加 4 个新区；palette 断言以 BRICK/PADDLE hue 为基准 |
| `mini-pong/scenes/Main.tscn` | 217 行；`AtmosphereLayer`（CanvasLayer, `layer=0`, **groups=["game_world"]**）子节点 = `BgPulse`（ColorRect 全屏）+ `RainCurtain`；ext_resource id 最高 `17_bg_pulse`；`ScoreFlash`(Node)+`ScoreFlashRect`（全屏 ColorRect）声明于 StartMenu 之前（默认 layer 0，树序靠后 → 世界之上）；分层：StartMenu/GameHUD/GameOverScreen layer=1、UpgradePickUI layer=2、WaveTransition layer=3、PauseOverlay layer=10 | 新增节点 additive-safe（见下）；L0 挂载点与 L2 挂载点已定位 |
| `mini-pong/gdscripts/breakout_grid.gd` | 237 行；`generate_wave(thickness, layout, seed)` → `_spawn_brick(pos)`（**无 variant 参数**，229 行）；信号 `brick_destroyed(brick,pos)`/`wall_cleared()`/`wall_generated(remaining)`；`_ready` 已 `seed(rng_seed)` 全局播种 | `_spawn_brick` 增 `variant` 参数 + palette 应用点；注入用同种子随机（可复现） |
| `mini-pong/gdscripts/brick.gd` | 30 行；无 @export variant；`destroy()` 幂等；无视觉 API | 增 `@export brick_variant: int = 0` + `apply_variant()` |
| `mini-pong/scenes/brick.tscn` | ColorRect `color = Color(1, 0.616, 0.271, 1)` + 共享 `neon_glow_material.tres`；**test_visual_contrast E2-2 文本断言锁定 color 字面** | **不改 tscn**；色变/变体全部运行时设置 |
| `mini-pong/assets/neon_glow_material.tres` | `glow_color = Color(0.29,0.56,0.85,1.0)`、`glow_width=0.25`、`glow_intensity=1.0`；E3-2 文本断言锁定 `glow_width = 0.25` | **不改 .tres**；变体材质运行时 duplicate |
| `mini-pong/gdscripts/neon_glow.gdshader` | fragment：`COLOR.rgb = mix(src_color.rgb, glow_color.rgb, glow * glow_color.a)`；`glow_color.a=1.0` → 边缘 ≈ 100% glow_color 覆盖 | 变体砖必须独立材质实例（duplicate + set_shader_parameter） |
| `mini-pong/gdscripts/wave_controller.gd` | `_advance_wave()`：`GameManager.begin_wave()`（wave_started emit）→ `generate_wave(_wave_thickness(index), 0, -1)`（layout=0=GAPS）；`start_first_wave()` 首波触发 | generate_wave 执行时 `GameManager.wave_index` 已是当前波号 → palette index 直接可读 |
| `mini-pong/gdscripts/game_manager.gd` | autoload；信号 `score_changed(p,a)`、`wave_started(i)`、`wave_settled(i)`、`brick_scored(side)`、`pierce_scored(side)`、`match_over(winner)`；`add_score(winner, amount, kind)` kind ∈ {boundary,brick,pierce} | **穿墙脉冲事件源 = `GameManager.pierce_scored`**（比 PRD §3.4 所述 scoring_manager 更靠下游、更干净，零改 scoring_manager） |
| `mini-pong/gdscripts/scoring_manager.gd` | `scored(winner)` 仅出界分触发 → `score_flash._on_score_changed`；拆砖分走 `add_score(toucher, 1, "brick")` 不 emit scored | 不修改；FeedbackFX 不依赖本文件 |
| `mini-pong/scenes/world_environment.tscn` | `glow_enabled=true`、`glow_intensity=0.6`、`glow_bloom=0.8`（test_neon TC2/TC3 文本断言） | **不修改**；glow/bloom 免费提供「光晕/脉冲放大」语义 |
| `mini-pong/tests/test_main_scene.gd` | TC21：`has_node("AtmosphereLayer")` + is CanvasLayer + layer==0 + `has_node("AtmosphereLayer/RainCurtain")`（存在性断言，无子节点数量断言） | 新增 CityGlow/Vignette/FeedbackFX additive-safe，零改动 |
| `mini-pong/tests/test_world_visibility.gd` | E1：Main.tscn 中 AtmosphereLayer/Ball/PlayerPaddle/AIPaddle/BreakoutGrid 在 game_world 组；LeftWall/WaveController 不在 | 新 L0 节点挂 AtmosphereLayer 下自动继承 MENU 隐藏；**若 FeedbackFX 挂 CanvasLayer 则需组决策（本设计用普通节点，无需入组，见 §3.3）** |
| `mini-pong/tests/test_visual_contrast.gd` | A–E 五场景：三色常量值/距离/WCAG/hue 分离/tscn-tres 文本断言（`glow_width = 0.25`、brick.tscn color 字面） | 默认砖 variant=0 渲染逐字节不变 → 零回归；变体砖不在三色断言域 |
| `mini-pong/tests/run_tests.gd` | 注册 24 套件（test_paddle → auto_play_test） | 新测试文件（可选 test_visual_enrichment.gd）由 implement agent 注册（plan 阶段不写测试代码） |
| `mini-pong/e2e_shots.json` | `02_midgame`：state PLAYING、press enter、require `player_score ≥ 1`、settle_frames=5、theme_color `4a90d9`；`01_title` theme_absent（#517） | 不修改文件；截帧内容变化由 Spike 2/4 前置验证（AC7） |

### PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计处置 |
|---------|-----------|---------|
| 「glow_width=3.0 → 渲染 ≈93% glow 色」（§4.5-C 证伪依据） | `glow_width` **已回落 0.25**（#464 落地）；但 `glow_color.a=1.0` 使边缘仍 ≈100% 被 glow_color 覆盖（mix 权重 = glow×1.0） | 证伪逻辑仍成立（modulate 被覆盖），变体仍需独立材质；强度略降（glow 区域收窄到 0.25 内） |
| 「穿墙得分在 scoring_manager.gd」 | 事件出口实际在 `GameManager.pierce_scored(side)`（add_score kind=="pierce" 时 emit） | FeedbackFX 消费 `GameManager.pierce_scored`（autoload，容错 is_instance_valid） |
| 「brick.gd 仅 26 行、无 variant」 | 30 行，确认无 variant 概念 | 增 @export + apply_variant（默认 0 兼容） |
| 「`_spawn_brick(pos)` 无 variant 参数」 | 确认（229 行 `_spawn_brick(pos: Vector2)`） | 增 `variant := 0` 默认参（既有调用零改动） |
| 「AtmosphereLayer 仅 BgPulse + RainCurtain」 | 确认（且 AtmosphereLayer **已在 game_world 组**） | CityGlow/Vignette 挂其下自动 MENU 隐藏 |
| 「波次色变消费 wave_started 或 generate_wave 读 wave index」 | `begin_wave()`（wave_started emit）先于 `generate_wave()` 执行 | 选 **generate_wave 内读 `GameManager.wave_index`**（单一读点，无信号时序耦合） |
| 「test_visual_contrast 对默认砖断言不回归」 | E2-2 锁定 brick.tscn color 字面（不改 tscn → 恒成立）；E3-2 锁定 .tres（不改 → 恒成立） | ✅ 结构性成立 |

---

---

## 3. 新组件 — 详细设计

### 3.1 `city_glow.gd`（新文件）— L0 底部城市光晕

- **文件:** `mini-pong/gdscripts/city_glow.gd`（PR-A）
- **基类:** `ColorRect`（引擎内建，headless 安全，#449 同构先例）
- **节点结构（挂载后整体）:**

```
Game (Node2D)
└── AtmosphereLayer (CanvasLayer, layer=0, groups=["game_world"])   # 既有
    ├── BgPulse      (ColorRect, bg_pulse.gd)      # 既有 — 全屏呼吸基底（最底）
    ├── CityGlow     (ColorRect, city_glow.gd)     # 新增 — 底部城市灯火光带
    ├── RainCurtain  (instance: rain_curtain.tscn) # 既有 — 雨幕在光晕之上
    └── Vignette     (ColorRect, vignette.gd)      # 新增 — 暗角（L0 最上，见 3.2）
```

- **纹理:** `_ready()` 程序化创建 `GradientTexture2D`（引擎内建类，零 .tres 资产、零 shader）：
  - `fill_from = Vector2(0, 1)`、`fill_to = Vector2(0, 0)` → 垂直渐变（底部 = 光晕色，向上渐隐为透明）
  - `gradient`：offset 0.0 → `CITY_GLOW_TINT`（alpha 1.0，由呼吸 alpha 统一调制）；offset 1.0 → 同色 alpha 0.0
  - `height = 256`（纹理分辨率，覆盖 720×256 光带区域）
- **锚定:** 底部全宽光带：`anchors_preset = 12`（bottom wide）+ `offset_top = -CITY_GLOW_HEIGHT`（默认 -256.0）→ 覆盖屏幕底部 256px，不遮挡中央战场
- **Signals:** 无（氛围层 FSM-independent，同 BgPulse/RainCurtain 纪律）
- **State Properties:**
  - `var _t: float = 0.0` — 呼吸相位累积（独立于 BgPulse 相位，避免同步闪烁）
- **Key Methods:**

```gdscript
extends ColorRect
## L0 底部城市光晕 — 雨夜竞技场「城市灯火」意象 (#527)。
## 垂直渐变光带 + 正弦呼吸（复用 bg_pulse.gd::compute_alpha 纯函数，DRY）；
## WorldEnvironment glow(0.6)/bloom(0.8) 将光带放大为「光晕」。氛围层 FSM-independent，
## 随 AtmosphereLayer(game_world 组) 在 MENU 态结构性隐藏 (#508)。
## Design: docs/DESIGN/527-visual-enrichment.md §3.1

const CONSTS = preload("res://gdscripts/constants.gd")
const BgPulse = preload("res://gdscripts/bg_pulse.gd")

var _t: float = 0.0

func _ready() -> void:
	# 程序化垂直渐变（底部光晕色 → 顶部透明）；引擎内建，无外部资产
	var grad := Gradient.new()
	grad.set_color(0, CONSTS.CITY_GLOW_TINT)                 # 底部：光晕色（alpha 由呼吸统一调制）
	grad.set_color(1, Color(CONSTS.CITY_GLOW_TINT.r, CONSTS.CITY_GLOW_TINT.g, CONSTS.CITY_GLOW_TINT.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 1)                            # 垂直：下→上
	tex.fill_to = Vector2(0, 0)
	tex.height = int(CONSTS.CITY_GLOW_HEIGHT)
	texture = tex

func _process(delta: float) -> void:
	_t += delta
	color.a = BgPulse.compute_alpha(_t, CONSTS.CITY_GLOW_PERIOD,
		CONSTS.CITY_GLOW_BASE_ALPHA, CONSTS.CITY_GLOW_AMPLITUDE)
```

- **Integration notes:**
  - 呼吸公式复用 `bg_pulse.gd::compute_alpha`（static 纯函数，headless 可求值；period ≤ 0 防除零 NaN 先例沿用）——单一公式两处消费，测试同断言
  - `CITY_GLOW_TINT` 默认占位 **暖琥珀暗调** `Color(1.0, 0.5, 0.2, 1.0)`（城市灯火暖意象，与砖暖色同系但环境亮度更低；与 `#4a90d9` RGB 距离 ≈ 137 ≥ 32 ✓）——taste-draft，human-review 定稿，调参零代码改动
  - 亮度纪律：呼吸 alpha 峰值 ≤ 0.15（与 BG_PULSE 同量级），且光带位于底部 256px 带内、颜色为暗调 → 环境层亮度低于游戏元素（#464）

### 3.2 `vignette.gd` + `vignette.gdshader`（新文件）— L0 暗角（≤10%）

- **文件:** `mini-pong/gdscripts/vignette.gd` + `mini-pong/gdscripts/vignette.gdshader`（PR-A；shader 方案经 Spike 1 验证，失败走 fallback B'）
- **基类:** `ColorRect`（全屏，anchors_preset = 15）
- **主方案 A — CanvasItem shader（PRD 4.2-A）：**

```gdscript
// vignette.gdshader — 全屏径向暗角（PRD 4.2-A；headless 编译安全由 Spike 1 前置验证）
shader_type canvas_item;
uniform float strength : hint_range(0.0, 0.10) = 0.08;   // 峰值暗度上限 0.10（AC2，mechanical）
uniform float inner_radius : hint_range(0.0, 1.0) = 0.62; // 中心不变暗半径（归一化，taste-draft）
uniform float softness : hint_range(0.0, 1.0) = 0.35;     // 边缘过渡柔和度（taste-draft）

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float edge = smoothstep(inner_radius, inner_radius + softness, dist);
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), edge * strength);  // 边缘向黑暗化 ≤10%
	COLOR.a = max(COLOR.a, edge * strength);                  // 暗带自身 alpha（盖住下层 L0）
}
```

- **fallback B' — 径向 GradientTexture2D（零 shader，Spike 1 失败时启用）:**
  - 同 CityGlow 程序化纹理模式：`fill_from = Vector2(0.5, 0.5)`、`fill_to = Vector2(0.5, 0.0)`（radial）、gradient 中心透明 → 边缘 `VIGNETTE_TINT`（alpha = `VIGNETTE_MAX_STRENGTH`）
  - 优于 PRD fallback B（四角 4 ColorRect）：单节点、无角落衔接瑕疵、径向精确「中心不变暗」
- **节点结构:** `AtmosphereLayer/Vignette`（AtmosphereLayer 最后子节点 = L0 最上层，暗角盖住雨幕/光晕；仍低于世界 L1 与 UI L3）
- **Signals:** 无
- **State Properties:** 无（全参数 uniform/常量驱动；shader 参数在 tscn 或 `_ready` 由常量注入）
- **Key Methods:** 无（纯静态表现；`_ready` 可选：`material.set_shader_parameter("strength", CONSTS.VIGNETTE_MAX_STRENGTH)`——常量单一事实源）
- **Integration notes:**
  - 暗度上限 `VIGNETTE_MAX_STRENGTH = 0.10`（mechanical，AC2 硬约束）：非黑断言安全——基底 `#0a0a12`（10,10,18）透出 90% ≈ (10,10,18) 不变（PRD §5.2-5 验算）
  - `inner_radius`/`softness`/`VIGNETTE_TINT` = taste-draft（占位 0.62 / 0.35 / 黑）
  - 暗角在 MENU 随 AtmosphereLayer 隐藏 → `01_title` 截帧无暗化，theme_absent 结构性安全

### 3.3 `feedback_fx.gd`（新文件）— L2 反馈统一控制器（破砖闪光 + 穿墙脉冲）

- **文件:** `mini-pong/gdscripts/feedback_fx.gd`（PR-B）
- **基类:** `Node`（普通节点，非 CanvasLayer——树序靠后 → 默认 layer 0 绘制于世界之上、HUD（layer=1）之下；**不入 game_world 组**：MENU 态无事件源自然不触发，且避免 test_world_visibility E1 的组断言面扩张）
- **节点结构（Main.tscn 内）:**

```
Game (Node2D)
├── ...既有节点...
├── ScoreFlash (Node)                    # 既有（#289）
├── FeedbackFX (Node, feedback_fx.gd)    # 新增 — 声明于 ScoreFlash 之后（树序靠后）
│   ├── PiercePulseRect (ColorRect 全屏)  # 穿墙脉冲：全屏色带，初始 modulate.a=0 + hide()
│   └── BrickFlashPool (Node2D)          # 破砖闪光实例池容器（3 个 FlashRect 循环复用）
└── StartMenu (CanvasLayer, layer=1)     # 既有 — HUD/UI 在反馈之上
```

- **Signals:** 无（纯消费方）
- **事件接线（`_ready`，全部容错 has_signal/has_method/is_instance_valid，仿 scoring_manager #384 容错先例）:**

| 事件 | 信号源 | 处理 | 动效 |
|------|--------|------|------|
| 破砖 | `BreakoutGrid.brick_destroyed(brick, pos)`（group `breakout_grids` 寻址） | 砖位闪光：池中取 FlashRect → 置于 `pos`（尺寸 ≈ BRICK_SIZE → 1.3x 扩散）→ Tween alpha 1→0 | 200ms，不弹跳 |
| 穿墙 | `GameManager.pierce_scored(side)`（autoload） | 全屏脉冲：PiercePulseRect 色带 alpha 0.15→0 | 250ms，不弹跳 |
| 得分弹出（预留） | `GameManager.score_changed(p, a)`（**首期不接**，Spike 4 验证后追加） | `_on_score_changed` stub 留接口 | — |

- **State Properties:**
  - `var _flash_pool: Array = []`、`var _flash_cursor: int = 0` — 3 实例循环池（超出复用最旧；避免高频 instantiate/free）
  - `var _pierce_this_frame: bool = false` — 同帧仲裁帧守卫（仿 scoring_manager `_brick_destroyed_this_frame` 模式）：`_process` 帧首复位，`_on_pierce` 置位，`_on_brick_destroyed` 检查——同帧穿墙 + 破砖 → 脉冲优先（PRD §5.2-8）
- **Key Methods:**

```gdscript
extends Node
## L2 反馈统一控制器 (#527, PRD 4.3-A+C) — 消费既有信号，统一 Tween 动效（150–300ms）。
## 首期：破砖闪光 + 穿墙脉冲；得分弹出/挡板 squash 留接口（Spike 4 后追加）。
## 颜色纪律：全部避开 #4a90d9（tol 32，E2E theme 保护）；MENU 态无事件源自然静默。
## Design: docs/DESIGN/527-visual-enrichment.md §3.3

const CONSTS = preload("res://gdscripts/constants.gd")

@onready var pierce_rect: ColorRect = $PiercePulseRect
@onready var flash_pool: Node2D = $BrickFlashPool

var _flash_cursor: int = 0
var _pierce_this_frame: bool = false

func _ready() -> void:
	_build_flash_pool()
	var tree := get_tree() if is_inside_tree() else null
	if tree == null:
		return
	# 事件源 1：破砖（grid 组寻址，未挂载 no-op —— 容错先例同 #384/#388）
	var grid = tree.get_first_node_in_group("breakout_grids")
	if grid != null and grid.has_signal("brick_destroyed"):
		grid.brick_destroyed.connect(_on_brick_destroyed)
	# 事件源 2：穿墙（autoload，无 autoload 环境静默跳过 —— 同 #450 null-safe 先例）
	if is_instance_valid(GameManager) and GameManager.has_signal("pierce_scored"):
		GameManager.pierce_scored.connect(_on_pierce)

func _process(_delta: float) -> void:
	_pierce_this_frame = false        # 帧守卫复位（同 scoring_manager AC4 模式）

func _on_brick_destroyed(brick: Node2D, pos: Vector2) -> void:
	if _pierce_this_frame:
		return                       # 同帧仲裁：脉冲优先（PRD §5.2-8）
	if is_instance_valid(GameManager) and GameManager.is_run_over():
		return                       # 终局守卫（同 scoring_manager 失败路径 2）
	var rect = _flash_pool[_flash_cursor]
	_flash_cursor = (_flash_cursor + 1) % _flash_pool.size()
	rect.global_position = pos
	rect.scale = Vector2(1.3, 1.3)
	rect.modulate.a = 1.0
	rect.show()
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, CONSTS.FX_BRICK_FLASH_DURATION)
	tw.tween_callback(func(): rect.hide())

func _on_pierce(side: String) -> void:
	_pierce_this_frame = true
	if is_instance_valid(GameManager) and GameManager.is_run_over():
		return
	pierce_rect.color = CONSTS.FX_PIERCE_COLOR        # 暖橙系，非 4a90d9
	pierce_rect.modulate.a = CONSTS.FX_PIERCE_PEAK_ALPHA
	pierce_rect.show()
	var tw := create_tween()
	tw.tween_property(pierce_rect, "modulate:a", 0.0, CONSTS.FX_PIERCE_DURATION)
	tw.tween_callback(func(): pierce_rect.hide())

# —— 预留接口（首期不接线；Spike 4 验证后追加）——
func _on_score_changed(_player: int, _ai: int) -> void:
	pass
```

- **Integration notes:**
  - **破砖闪光 vs ScoreFlash（#289）区分**：ScoreFlash = 全屏色罩 0.2s（出界分，`scored` 信号）；破砖闪光 = **砖位局部光斑**（拆砖分，`brick_destroyed` 信号）——事件源、空间范围、颜色均不同，无视觉混淆
  - **穿墙脉冲 vs ScoreFlash 区分**：脉冲 = 全屏**暖橙色带** alpha 0.15 扫过 250ms；闪烁 = 全屏**蓝/红色罩** 0.2s——颜色不同（脉冲暖色系避开 4a90d9/ff3355 语义）+ 时长不同 + 仲裁（同帧脉冲优先）
  - 颜色常量（taste-draft 占位）：`FX_BRICK_FLASH_COLOR = BRICK_NEON`（破砖同色闪光）、`FX_PIERCE_COLOR = Color(1.0, 0.7, 0.3, 1.0)`（暖橙，非 4a90d9）、`FX_PIERCE_PEAK_ALPHA = 0.15`（克制，非黑断言安全）、`FX_BRICK_FLASH_DURATION = 0.2`、`FX_PIERCE_DURATION = 0.25`（均 ∈ [150,300]ms）
  - 池尺寸 `FX_FLASH_POOL_SIZE = 3`（同帧多砖破碎时复用最旧；超出上限的视觉让位于新事件，克制纪律）

---

---

## 4. 既有组件修改

### 4.1 文件修改总表

**新文件：**

| 文件 | 归属 | 用途 |
|------|:---:|------|
| `mini-pong/gdscripts/city_glow.gd` | PR-A | L0 城市光晕控制器（§3.1） |
| `mini-pong/gdscripts/vignette.gd` | PR-A | L0 暗角控制器（§3.2） |
| `mini-pong/gdscripts/vignette.gdshader` | PR-A | 暗角 shader（主方案 A；fallback B' 时删除本文件） |
| `mini-pong/gdscripts/feedback_fx.gd` | PR-B | L2 反馈控制器（§3.3） |
| `mini-pong/tests/test_visual_enrichment.gd`（可选） | 两者 | 纯函数断言套件（palette hue 域/暗度上限/变体映射/反馈接线），由 implement agent 创建并注册进 run_tests.gd |

**修改文件：**

| 文件 | 变更 | 动机 |
|------|------|------|
| `mini-pong/gdscripts/constants.gd` | 追加 4 个新区（§4.2）；既有区逐字节不动 | 单一事实源（AC8 白名单核心） |
| `mini-pong/scenes/Main.tscn` | AtmosphereLayer 增 CityGlow + Vignette；ScoreFlash 后增 FeedbackFX（§4.4） | L0/L2 挂载 |
| `mini-pong/gdscripts/breakout_grid.gd` | `_spawn_brick(pos, variant := 0)` + palette 应用（§4.3） | 波次色变 + 变体注入 |
| `mini-pong/gdscripts/brick.gd` | `@export brick_variant: int = 0` + `apply_variant()`（§4.3） | 变体视觉载体 |

**不修改（红线）：** `brick.tscn`（E2-2 文本断言锁定 color 字面）、`neon_glow_material.tres`（E3-2 锁定 glow_width）、`world_environment.tscn`（test_neon TC2/TC3）、`score_flash.gd`（test_neon TC9）、`scoring_manager.gd`/`wave_controller.gd`/`game_manager.gd`/`game_state_machine.gd`（事件源已足够，零侵入）、`e2e_shots.json`/`analyze_bmp.py`（断言体系不动）。

### 4.2 `constants.gd` 新增区（机械常量 + taste-draft 占位）

```gdscript
# ── City Glow (#527) ──
# L0 底部城市光晕 (PLAN §3.1「底部城市光晕」执行层; 机制/结构 = mechanical,
# 色调/周期 = taste-draft, human-review 定稿, 调参零代码改动)
const CITY_GLOW_HEIGHT: float = 256.0        # 光带高度（底部 256px，不遮中央战场）
const CITY_GLOW_PERIOD: float = 6.0          # 呼吸周期 6s（慢于 BgPulse 4s，避免同步闪烁）
const CITY_GLOW_BASE_ALPHA: float = 0.05     # 基线 alpha（克制，环境层亮度最低）
const CITY_GLOW_AMPLITUDE: float = 0.05      # 振幅 → alpha ∈ [0.0, 0.10]（峰值 ≤10%，同暗角量级）
const CITY_GLOW_TINT: Color = Color(1.0, 0.5, 0.2, 1.0)  # 暖琥珀灯火（taste-draft 占位；与 4a90d9 距离 ≈137 ≥ 32）

# ── Vignette (#527) ──
# L0 暗角 (PLAN §3.1「暗角(≤10%)」执行层; 峰值暗度上限 = mechanical 硬约束,
# 内半径/柔和度 = taste-draft, human-review 定稿)
const VIGNETTE_MAX_STRENGTH: float = 0.10    # 峰值暗度上限（AC2 硬约束；非黑断言安全）
const VIGNETTE_INNER_RADIUS: float = 0.62    # 中心不变暗半径（归一化，taste-draft 占位）
const VIGNETTE_SOFTNESS: float = 0.35        # 边缘过渡柔和度（taste-draft 占位）

# ── Wave Color (#527) ──
# v1 波次色变 (PLAN §5 v1「波次色变」执行层; 色值 = taste-draft 占位, human-review 定稿;
# hue 域 [20°,60°] 为 #464 语义硬约束——palette 断言拦截)
const WAVE_COLOR_PALETTE: Array[Color] = [
	Color(1.0, 0.616, 0.271, 1.0),  # 波 1: BRICK_NEON #ff9d45 (hue 28.4°) 教学色恒稳
	Color(1.0, 0.718, 0.302, 1.0),  # 波 2: 橙黄 #ffb74d (hue 35.8°)
	Color(1.0, 0.757, 0.027, 1.0),  # 波 3: 金黄 #ffc107 (hue 45.0°)
	Color(1.0, 0.561, 0.235, 1.0),  # 波 4: 深橙 #ff8f3c (hue 25.6°)
]                                    # 全部 hue ∈ [20°,60°]，与 PADDLE_NEON(186°) 距离 ≥126°

# ── Brick Variant (#527) ──
# v1 特殊砖视觉 (PLAN §5 v1「特殊砖视觉(铁砖/奖励砖)」执行层; 色值 = taste-draft 占位;
# 仅视觉载体，玩法语义（铁砖不可破坏等）留给未来玩法 issue)
const BRICK_VARIANT_COLORS: Dictionary = {
	0: Color(1.0, 0.616, 0.271, 1.0),  # 0=普通 → BRICK_NEON（默认渲染逐字节不变）
	1: Color(0.541, 0.608, 0.710, 1.0),# 1=铁砖 → 灰蓝 #8a9bb5（低饱和冷调，非 PADDLE 青）
	2: Color(0.6, 0.8, 0.3, 1.0),      # 2=奖励砖 → 金绿（接口预留，首期不实现）
}
const IRON_BRICK_COUNT_PER_WAVE: int = 2  # 每波铁砖数（波 2 起；taste-draft 可调）

# ── Feedback FX (#527) ──
# L2 反馈动效 (PLAN §3.3 动效纪律: Tween 150–300ms, 不弹跳; 颜色避开 4a90d9 tol 32)
const FX_BRICK_FLASH_DURATION: float = 0.2   # 破砖闪光 200ms
const FX_PIERCE_DURATION: float = 0.25       # 穿墙脉冲 250ms
const FX_PIERCE_PEAK_ALPHA: float = 0.15     # 脉冲峰值 alpha（克制，非黑断言安全）
const FX_PIERCE_COLOR: Color = Color(1.0, 0.7, 0.3, 1.0)   # 暖橙脉冲带（非 4a90d9/ff3355 语义）
const FX_FLASH_POOL_SIZE: int = 3            # 破砖闪光实例池
```

> **taste-draft 定稿流程**（PRD §8）：上表标注「taste-draft 占位」的色值/数值由 implement 阶段生成 taste-draft 常量 → human-review 定稿 → 定稿后追加 `docs/TASTE.md` 条目（§4.5 文档清单）。定稿只改常量值，零代码改动。

### 4.3 `breakout_grid.gd` + `brick.gd` — 波次色变与变体注入

**`breakout_grid.gd` 变更（两处）：**

```gdscript
# 1) generate_wave() 内，进入行循环前（布局/孔洞逻辑零改动）：
var wave_idx: int = 0
if is_instance_valid(GameManager) and GameManager.has_method("get_wave_index"):
	wave_idx = GameManager.get_wave_index()          # begin_wave 已 +1 → 当前波号
var palette_idx: int = maxi(wave_idx - 1, 0) % CONSTS.WAVE_COLOR_PALETTE.size()
var wave_color: Color = CONSTS.WAVE_COLOR_PALETTE[palette_idx]   # 波 1 → idx 0 = BRICK_NEON

# 2) _spawn_brick 签名 + 变体注入（铁砖，波 2 起）：
func _spawn_brick(pos: Vector2, variant: int = 0, base_color: Color = Color(1, 1, 1, 1)) -> void:
	# ...既有实例化逻辑不变...
	brick.apply_variant(variant, base_color)          # brick.gd 新方法（variant=0 时渲染不变）
	add_child(brick)
```

**铁砖注入策略（Spike 3 定稿，默认值）：** `generate_wave()` 内、`_spawn_brick` 调用点按行循环注入：`var variant := 0; if wave_idx >= 2 and randi_range(0, 99) < CONSTS.IRON_BRICK_COUNT_PER_WAVE * 10: variant = 1`（概率 ≈ 每波 2/20 列 ≈ 10%；复用 generate_wave 已 seed 的全局 RNG → 同 seed 布局 + 注入可复现，测试契约）。**首波（wave_idx==1）不注入**（教学墙稳定，PRD §5.2-7 同款纪律）。

**`brick.gd` 变更：**

```gdscript
extends StaticBody2D
## ...既有注释保留...
## #527 增补: brick_variant 视觉变体（0=普通/1=铁砖/2=奖励砖接口）。
## 仅视觉（颜色/glow），不改变可破坏性/分数/碰撞 —— 玩法语义留给未来玩法 issue。
## Design: docs/DESIGN/527-visual-enrichment.md §4.3

const CONSTS = preload("res://gdscripts/constants.gd")

@export var brick_variant: int = 0        # 默认 0 → 既有渲染逐字节不变（AC5）
var grid: Node
var _destroyed: bool = false

func _ready() -> void:
	add_to_group("bricks")
	collision_layer = 2
	collision_mask = 0

## #527: 设置变体视觉。variant=0 → 颜色=base_color（默认 BRICK_NEON），材质不动（共享 .tres，
## 逐字节不变）；variant>=1 → ColorRect 显式设色 + 材质 duplicate 后改 glow_color
## （#464 教训: mix 权重 = glow*glow_color.a=1.0 → 边缘被 glow_color 完全覆盖）。
func apply_variant(variant: int, base_color: Color) -> void:
	brick_variant = variant
	var rect: ColorRect = $ColorRect
	if variant == 0:
		rect.color = base_color
		return
	var vcolor: Color = CONSTS.BRICK_VARIANT_COLORS.get(variant, base_color)
	rect.color = vcolor
	rect.material = rect.material.duplicate()                    # 独立材质实例（不污染共享 .tres）
	rect.material.set_shader_parameter("glow_color", vcolor)     # glow 同色（视觉一致）
```

> **为什么不改 brick.tscn：** `test_visual_contrast` E2-2 断言 tscn 文本 `color = Color(1, 0.616, 0.271, 1)`；运行时设色不影响文本断言 → variant=0 + base_color=BRICK_NEON 时渲染与场景默认逐像素一致（AC5「默认 variant=0 时既有渲染逐字节不变」结构性成立）。

### 4.4 `Main.tscn` 挂载变更

```text
[node name="CityGlow" type="ColorRect" parent="AtmosphereLayer"]
offset_top = -256.0            # CITY_GLOW_HEIGHT（或锚定底部 wide 写法）
anchors_preset = 12            # bottom wide
script = ExtResource("18_city_glow")       # 新 ext_resource id（既有最高 17_bg_pulse）

[node name="Vignette" type="ColorRect" parent="AtmosphereLayer"]
anchors_preset = 15            # 全屏
material = SubResource("vignette_mat")     # 或 _ready 注入参数（常量单一事实源）
script = ExtResource("19_vignette")

[node name="FeedbackFX" type="Node" parent="."]   # 声明于 ScoreFlash 之后（树序靠后 → 世界之上）
script = ExtResource("20_feedback_fx")
[node name="PiercePulseRect" type="ColorRect" parent="FeedbackFX"]  # 全屏, 初始 hide()
[node name="BrickFlashPool" type="Node2D" parent="FeedbackFX"]
```

### 4.5 文档更新清单

- [ ] `docs/DESIGN/527-visual-enrichment.md`（本文档）
- [ ] `docs/TASKS/527-visual-enrichment.md`（本 plan 批）
- [ ] `docs/TASTE.md`：taste-draft 常量（光晕色调/暗角强度/palette/铁砖配色）human-review 定稿后追加条目（implement 阶段）
- [ ] `docs/PLAN-rogue-pong.md`：§3.1 L0/L2、§5 v1 对应项落地打勾（implement 阶段）

---

## 5. 数据流

### Flow 1 — 波次色变 + 铁砖注入（每波）

```
WaveController._advance_wave()（wave_index=N）
  ├─► GameManager.begin_wave() → wave_index=N, wave_started(N) emit
  └─► BreakoutGrid.generate_wave(thickness, layout=GAPS, seed)
        ├─ 读 GameManager.get_wave_index() = N → palette_idx = (N-1) % 4
        ├─ wave_color = WAVE_COLOR_PALETTE[palette_idx]（N=1 → BRICK_NEON）
        ├─ 行循环: _spawn_brick(pos, variant, wave_color)
        │     ├─ variant: N>=2 且 rng<阈值 → 1（铁砖）；否则 0
        │     └─ brick.apply_variant(variant, wave_color)
        │           ├─ variant=0: $ColorRect.color = wave_color（渲染=既有 BRICK_NEON 语义）
        │           └─ variant=1: color=灰蓝 + 材质 duplicate + glow_color=灰蓝
        └─ wall_generated(remaining) emit（HUD 不变）
```

### Flow 2 — 破砖闪光（L2）

```
ball 碰砖 → brick.destroy() → grid._on_brick_destroyed(brick)
  ├─► brick_destroyed(brick, pos) emit
  │     ├─► ScoringManager._on_brick_destroyed → add_score(toucher, 1, "brick")（既有，零改动）
  │     └─► FeedbackFX._on_brick_destroyed(brick, pos)      [新]
  │             ├─ 同帧仲裁: _pierce_this_frame? → 丢弃（脉冲优先）
  │             ├─ 终局守卫: GameManager.is_run_over()? → 丢弃
  │             └─ 池取 FlashRect → pos 定位 → Tween alpha 1→0 (200ms) → hide
  └─► wall_cleared()（清墙时）→ WaveController（既有，零改动）
```

### Flow 3 — 穿墙脉冲（L2）

```
ball 穿越墙带出界 → ScoringManager._on_ball_score → crossed=true
  └─► GameManager.add_score(winner, 3, "pierce")
        ├─► pierce_scored(side) emit ──► FeedbackFX._on_pierce(side)   [新]
        │        ├─ _pierce_this_frame = true（同帧仲裁置位）
        │        ├─ 终局守卫
        │        └─ PiercePulseRect: color=暖橙, alpha=0.15 → Tween 250ms → hide
        └─► score_changed(p, a) emit → HUD（既有）/ ScoreFlash.scored 不触发（拆砖/穿墙不走 scored）
```

### Flow 4 — MENU 隐藏（结构性，零代码）

```
FSM.enter_state(MENU) → _set_world_visible(false) → call_group("game_world", "set", "visible", false)
  └─► AtmosphereLayer.visible = false → CityGlow/Vignette 随父隐藏（#508 既有机制，零新代码）
        └─► 01_title 截帧: 无光晕/无暗角/无 4a90d9 新色 → theme_absent 结构性安全
FeedbackFX 非 game_world 组：MENU 无 brick_destroyed/pierce_scored 事件源 → 自然静默
```

### Flow 5 — fallback 路径（暗角 shader 失败）

```
Spike 1（implement Phase 0）: vignette.gdshader headless 编译失败
  └─► 删除 vignette.gdshader → vignette.gd 改用径向 GradientTexture2D（B'）
        └─► 单节点、零 shader、headless 绝对安全；AC2（≤10%）由 VIGNETTE_MAX_STRENGTH 常量保证不变
```

---

---

## 6. 边界情况与错误处理

| # | 边界场景 | 处理方式 |
|---|---------|---------|
| 1 | **MENU 态**：新 L0 元素（光晕/暗角） | 随 AtmosphereLayer（game_world 组）结构性隐藏（#508）；`01_title` theme_absent 不受影响（非依赖断言的结构性保证） |
| 2 | **PAUSED 态**：光晕/暗角/反馈与暂停层叠 | PauseOverlay（layer=10）在一切之上（GDD22）；L0/L2 均为静态/低频表现，不影响暂停文字可读性；FSM 冻结球后无新事件 → 反馈自然停止 |
| 3 | **波次色变 × #464 语义** | palette hue 域 [20°,60°]（断言拦截），与 PADDLE_NEON hue 186° 距离 ≥126° → 「暖=目标物」语义保持 |
| 4 | **特殊砖 × test_visual_contrast** | 默认砖（variant=0）颜色 = BRICK_NEON、材质不 duplicate → 三色断言零回归；铁砖色（灰蓝）不在三色断言域 |
| 5 | **暗角 × E2E 非黑断言** | `VIGNETTE_MAX_STRENGTH ≤ 0.10`：基底 (10,10,18) 透出 90% ≈ 不变 → 非黑断言安全（Spike 1 验算） |
| 6 | **HOLES/MIXED 布局** | 洞/缝列不实例化砖 → variant 注入只作用于实际 spawn 的砖（`_spawn_brick` 调用点注入）；布局逻辑零改动 |
| 7 | **波 1 教学墙** | palette_idx = (wave_index-1) % n → 波 1 恒 = BRICK_NEON（教学色稳定）；铁砖注入条件 wave_index >= 2 → 首波无变体 |
| 8 | **穿墙脉冲 × ScoreFlash 同帧** | 事件源不同（pierce_scored vs scored）；同帧仲裁 `_pierce_this_frame` 帧守卫 → 脉冲优先（PRD §5.2-8） |
| 9 | **终局后残留事件** | FeedbackFX 两 handler 均检查 `GameManager.is_run_over()` → 丢弃（同 scoring_manager 失败路径 2 先例） |
| 10 | **无 autoload / 无 grid 环境（mini-tree 测试）** | 全部接线容错：`is_instance_valid(GameManager)` + `has_signal` + group 寻址 get_first_node_in_group → no-op + 不崩（#384/#388/#450 先例） |
| 11 | **generate_wave 无 GameManager（单测）** | `wave_idx` 默认 0 → palette_idx 0 = BRICK_NEON（容错默认安全） |
| 12 | **铁砖材质 duplicate 泄漏** | 每砖仅 duplicate 一次（apply_variant 幂等：重复调用先判断 variant 已设则跳过）；砖销毁 queue_free → 材质随节点释放，无泄漏 |
| 13 | **同帧多砖破碎（blast_neighbors）** | 闪光池 3 实例循环复用 → 超出上限视觉让位于新事件（克制纪律，无 instantiate 风暴） |
| 14 | **暗角 shader headless 编译失败** | Spike 1 前置验证；失败 → fallback B'（径向 GradientTexture2D，零 shader）——设计不塌方 |
| 15 | **02_midgame 色数断言增量** | palette 仅 4 色（含 BRICK_NEON 基底）+ 铁砖 1 色 + 脉冲暖橙 → 新增色 ≤ 4；Spike 2 实测确认阈值内；若超阈值 → palette 收敛（4 色内）/色变仅作用于 glow 色调（PRD §5.3-2 失败路径预案） |
| 16 | **PAUSED 进入瞬间的 tween** | Tween 由 SceneTree 驱动，FSM 冻结球不影响 tween 播放；200–250ms 内自然结束，无残留 |

---

## 7. 集成点

> **状态约定：** ⬜ = 待 implement agent 接线；✅ = implement agent 验证后更新。review agent 合并前核对全部 ⬜ 已解决或显式延后。

| 集成 | 我方组件 | 目标 Issue/系统 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 波次色变 | BreakoutGrid.generate_wave | GameManager.wave_index（#386） | 读 `get_wave_index()`（begin_wave 已 +1） | ⬜ |
| 铁砖注入 | BreakoutGrid._spawn_brick | brick.gd apply_variant（新） | `brick.apply_variant(variant, wave_color)` | ⬜ |
| 破砖闪光 | FeedbackFX | BreakoutGrid.brick_destroyed（#384） | group `breakout_grids` 寻址 + connect | ⬜ |
| 穿墙脉冲 | FeedbackFX | GameManager.pierce_scored（#385） | autoload + connect | ⬜ |
| 得分弹出（预留） | FeedbackFX._on_score_changed | GameManager.score_changed（#385） | 首期不接线；Spike 4 后追加 | ⬜ 延后 |
| L0 MENU 隐藏 | CityGlow/Vignette | game_world 组（#508） | 挂 AtmosphereLayer 下继承（零代码） | ⬜ |
| 呼吸公式 | city_glow.gd | bg_pulse.gd::compute_alpha（#449） | preload + static 调用（DRY） | ⬜ |
| 变体材质 | brick.gd apply_variant | neon_glow_material.tres（#289/#464） | material.duplicate() + set_shader_parameter（不改共享资源） | ⬜ |
| E2E 断言 | 全部新视觉 | e2e_shots.json / analyze_bmp.py（#358/#517） | 不修改文件；Spike 2/4 前置验证截帧兼容 | ⬜ |
| taste-draft 定稿 | 全部 taste 常量 | docs/TASTE.md / human-review（B5） | implement 生成草稿 → 定稿后追加条目 | ⬜ 延后 |

---

## 8. 实现阶段（两个实现 PR + Phase 0 Spike）

> PRD §8 建议「拆 2 个实现 PR」：PR-A（L0：光晕 + 暗角，低风险先合）、PR-B（v1：色变 + 铁砖 + L2 反馈，依赖 Spike 2/3/4 结果）。Spike 1–4 由 implement agent 在各自 PR 的 Phase 0 于 worktree 内执行（plan 阶段只产出文档，不跑实验；DESIGN 已覆盖主/备两条路径，Spike 结果只影响参数与路径选择，不改变架构）。

| Phase | PR | 优先级 | 组件 | 依赖 | 估计 |
|:-----:|:---:|:------:|------|------|:----:|
| 0a | A | P0 | Spike 1：vignette.gdshader headless 编译 + 非黑验算 | 无 | 0.5d |
| 1 | A | P0 | constants.gd CITY_GLOW_*/VIGNETTE_* 区 + city_glow.gd + vignette.gd(.gdshader) + Main.tscn 挂载 | 0a | 1d |
| 2 | A | P0 | test_visual_enrichment.gd（L0 纯函数断言）+ run_tests.gd 注册 | 1 | 0.5d |
| 3 | A | P0 | E2E 复跑（--with-visual）+ TASTE.md taste-draft → human-review 定稿 | 2 | 0.5d |
| 0b | B | P0 | Spike 2（palette 色数实测）/ Spike 3（铁砖材质方案）/ Spike 4（反馈接线 + 帧差） | 无（可与 A 并行） | 1d |
| 4 | B | P0 | constants.gd WAVE_COLOR_*/BRICK_VARIANT_*/FX_* 区 + brick.gd apply_variant + breakout_grid.gd（palette + 注入） | 0b | 1d |
| 5 | B | P0 | feedback_fx.gd + Main.tscn FeedbackFX 挂载 | 0b | 1d |
| 6 | B | P0 | test_visual_enrichment.gd（v1 断言扩展）+ run_tests.gd 注册 | 4,5 | 0.5d |
| 7 | B | P1 | E2E 复跑 + TASTE.md 追加 + PLAN-rogue-pong.md 打勾 | 6 | 0.5d |

**PR 文件白名单（AC8）：**
- PR-A（6 文件）：`city_glow.gd`（新）、`vignette.gd`（新）、`vignette.gdshader`（新，fallback B' 时删）、`Main.tscn`、`constants.gd`（仅 CITY_GLOW_*/VIGNETTE_* 区）、`tests/test_visual_enrichment.gd`（新，可选）
- PR-B（7 文件）：`feedback_fx.gd`（新）、`brick.gd`、`breakout_grid.gd`、`constants.gd`（仅 WAVE_COLOR_*/BRICK_VARIANT_*/FX_* 区）、`Main.tscn`、`tests/test_visual_enrichment.gd`（扩展）、`tests/run_tests.gd`（注册）
- 红线：不混入升级池/暂停/雨幕/标题/score_flash/world_environment 等文件

---

## 9. 测试用例描述

> 按 skill 协议：**只描述场景与断言，不写可运行测试代码**。实际测试文件（`tests/test_visual_enrichment.gd` 等）由 implement agent 创建并注册进 `run_tests.gd`。基线：现有 24 套件全绿（AC6，零回归）。

### Scenario A — constants 新区与 palette 域（机械断言）
- **A1** palette 存在且规模 4–6 色：`WAVE_COLOR_PALETTE.size() in [4, 6]`，`palette[0] == BRICK_NEON`（波 1 教学色恒稳）
- **A2** palette hue 域：每色 `hue * 360 ∈ [20, 60]`（#464 暖色域硬约束）；与 `PADDLE_NEON.hue * 360` 环形距离 ≥ 126°
- **A3** 暗角上限：`VIGNETTE_MAX_STRENGTH <= 0.10`（AC2 硬约束，机械）
- **A4** 光晕色避开 theme：`CITY_GLOW_TINT` 与 `PLAYER_NEON_BLUE`（#4a90d9）RGB 距离 ×255 ≥ 32（AC1/AC7）
- **A5** 变体映射：`BRICK_VARIANT_COLORS` 含键 0/1/2；`[0] == BRICK_NEON`；铁砖色与 `PADDLE_NEON` 不混淆（RGB 距离 ≥ 60 或低饱和判定）
- **A6** 动效时长：`FX_BRICK_FLASH_DURATION`、`FX_PIERCE_DURATION ∈ [0.15, 0.30]`（PLAN §3.3 纪律）

### Scenario B — 波次色变与铁砖注入（grid 级）
- **B1** 波 1 全普通砖：`generate_wave(1, GAPS, seed)` 后所有砖 `brick_variant == 0` 且 `ColorRect.color == BRICK_NEON`
- **B2** 波 N 色变：模拟 `wave_index = 3`（GameManager mock 或注入）→ `generate_wave` → 普通砖色 == `palette[2]`；波 2 → `palette[1]`
- **B3** 铁砖注入：波 2+ 生成墙中铁砖数 ∈ [0, IRON_BRICK_COUNT_PER_WAVE×2]（概率注入上限）；铁砖 `ColorRect.color == BRICK_VARIANT_COLORS[1]`
- **B4** 铁砖材质隔离：variant=1 砖的 `ColorRect.material != neon_glow_material.tres`（已 duplicate）且 `glow_color` 参数 == 铁砖色；variant=0 砖材质仍是共享资源（`is_same()` 判定）
- **B5** 同 seed 可复现：同 seed 两次 `generate_wave` → 砖布局 + 铁砖位置一致（注入复用全局 seed）
- **B6** 无 GameManager 容错：mini-tree 无 autoload → `generate_wave` 不崩，砖色 = palette[0]

### Scenario C — L0 光晕与暗角（表现层）
- **C1** CityGlow 纯函数：复用 `BgPulse.compute_alpha` 断言（周期 6s 内 alpha ∈ [0, 0.10] 峰值；period ≤ 0 → base）
- **C2** CityGlow 纹理：`_ready` 后 `texture is GradientTexture2D`、fill_from=(0,1)/fill_to=(0,0)、gradient 端点色 == CITY_GLOW_TINT（底部）/透明（顶部）
- **C3** Vignette 参数化：shader uniform `strength` 上限 0.10（文本断言 .gdshader，同 test_visual_contrast E3 模式）；fallback B' 时断言 radial GradientTexture2D 端点 alpha ≤ 0.10
- **C4** Main.tscn 挂载：`has_node("AtmosphereLayer/CityGlow")`、`has_node("AtmosphereLayer/Vignette")`（additive，test_main_scene TC21 模式）；AtmosphereLayer 仍在 game_world 组
- **C5** MENU 结构性隐藏：mini-tree（test_world_visibility 模式）→ FSM MENU → AtmosphereLayer 隐藏 → CityGlow/Vignette 不可见；PLAYING → 可见

### Scenario D — L2 反馈（信号接线 + 动效）
- **D1** 破砖闪光：mock grid emit `brick_destroyed(brick, pos)` → FlashRect 显示于 pos、Tween 启动、200ms 后 hide；池循环复用（连续 5 次事件 → 3 实例轮转）
- **D2** 穿墙脉冲：mock emit `pierce_scored("player")` → PiercePulseRect 显示、color == FX_PIERCE_COLOR、250ms 后 hide
- **D3** 同帧仲裁：同帧先 pierce 后 brick_destroyed → 砖位闪光被丢弃（脉冲优先）；反序 → 两通道各自播放（帧守卫仅同帧互斥）
- **D4** 终局守卫：`GameManager.is_run_over() == true` → 两 handler 均 no-op
- **D5** 未接线容错：mini-tree 无 grid/无 GameManager → `_ready` 不崩、无连接
- **D6** MENU/PAUSED 静默：无事件源 → 反馈节点保持隐藏（01_title/暂停截帧无反馈残留）

### Scenario E — 回归与 E2E（AC6/AC7）
- **E1** 既有套件零回归：run_tests.gd 全绿（test_neon/test_visual_contrast/test_main_scene/test_constants/test_world_visibility 等 24 套件）
- **E2** headless：`godot --path mini-pong --headless --quit` 无脚本错误（AC6）
- **E3** E2E L1–L3：`run-e2e-review.sh --with-visual` → 01_title theme_absent 保持（MENU 结构性隐藏）、02_midgame 非黑/色数/theme/帧差 4 重断言通过、03_gameover 同（AC7；需图形环境，headless 不可跑截图——软性依赖，同 #466 惯例）
- **E4** 文件域（AC8）：实现 PR files 列表 ⊆ 白名单（§8），不混入其他 issue 文件

---

## 10. Spike 交接（implement Phase 0 执行，plan 阶段不跑实验）

| Spike | 验证问题 | 结果如何影响实现 | DESIGN 覆盖 |
|:-----:|---------|----------------|------------|
| 1（PR-A） | vignette.gdshader headless 编译安全？alpha 0.10 对 (10,10,18) 非黑断言影响？ | 主案 shader / fallback B' 径向渐变 | §3.2 / §5 Flow 5 |
| 2（PR-B） | 4 色 palette 对 02_midgame 色数/theme 断言影响？ | palette 规模定稿（4 色）；超阈值 → 收敛预案 | §4.2 / §6-15 |
| 3（PR-B） | 铁砖 material.duplicate + glow_color 方案生效？默认砖逐字节不变？ | 变体材质路径定稿（duplicate vs 换 .tres） | §4.3 |
| 4（PR-B） | 破砖/穿墙信号链完整？脉冲帧对帧差断言影响？ | 首期 2 项反馈定稿 + 得分弹出是否追加 | §3.3 / §7 |

**Plan 阶段边界声明**：PRD §8 建议 plan agent 先跑 Spike——按 skill 协议（Patch 55，plan 阶段 documentation only），Spike 交由 implement agent 在实现 PR 的 Phase 0 执行（worktree 内，`--headless` 可跑部分；`--with-visual` 需图形环境）。本 DESIGN 对每条 Spike 的两条结果路径均已给出完整设计，实现不阻塞。

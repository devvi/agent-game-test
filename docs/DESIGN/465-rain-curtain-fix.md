# DESIGN: [Feature] 雨幕粒子修复 — 全屏均匀雨滴分布 (漏水点 → 雨)

> **Parent Issue:** #465
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A（修正 GPUParticles2D 场景配置 + 基值对齐）—— 确认 PRD §4 推荐方案：根因 D1（默认 `visibility_rect` 剔除）+ D2（emission rect 半宽语义错配）均有实测证据，配置修正即对症；**不切 CPUParticles2D / 不写 shader**（Spike 3 证实 D3 才启用 Approach B 兜底）
> **Reference PRD:** docs/PRD/465-rain-curtain-fix.md（research PR #470，已合并）
> **所有权:** `content_ownership: mechanical`（发射配置/覆盖率/分布 = 机械可测；雨滴视觉浓度 = taste-draft，走 human-review 定稿）
> **深度:** depth/standard（Issue 无 depth 标签，按 PRD 惯例处理）—— 文件域仅 3 个（tscn/gd/test），未达 TASKS 阈值（<10 文件、<5 子系统、非替代性改造）→ **不产 TASKS 文档**，本文档即 implement 契约
> **并行上下文:** 视觉缺陷修复第一批（2026-08-13，worktree 并行）—— 姊妹 Issue **#464**（视觉三色分层）并行中，文件域零重叠（rain vs 颜色）；本 Issue 文件域与 #464 的 `constants.gd` 改动互不触及（本 Issue 对 `constants.gd` RAIN_* 组**零改动**）

---

## 1. 架构概述

### 1.1 现状与根因（plan agent 已对照 origin/main 源码核实，2026-08-13）

| 文件 | 现状（已核实） | 与需求的差距 |
|------|--------------|-------------|
| `mini-pong/scenes/rain_curtain.tscn`（28 行） | GPUParticles2D `Particles` 节点 `position=Vector2(360,-20)`；ParticleProcessMaterial：`emission_shape=1`(RECTANGLE)、`emission_rect_extents=Vector2(360,8)`、`direction=Vector3(0,1,0)`、`spread=6.0`、`initial_velocity_min/max=700/900`、`scale_min/max=0.7/1.3`、`color=Color(0.72,0.84,1,0.45)`；`amount=400`、`lifetime=1.8`、`preprocess=2.0`；**无 `visibility_rect` 属性** | ❌ ①发射区仅 16px 高的顶部窄带（y∈[-28,-12]）；②`visibility_rect` 缺省 → Godot 默认 `Rect2(-100,-100,200,200)`（**局部坐标**）→ 节点 (360,-20) 下可视窗口仅 x∈[260,460]、y∈[-120,80]，发射区边缘粒子全被剔除 → 只剩"中间偏右上角零星粒子"（PRD §1.2 D1 实测） |
| `mini-pong/gdscripts/rain_curtain.gd`（137 行） | `BASE_VELOCITY_MIN/MAX=700/900`、`BASE_SCALE_MIN/MAX=0.7/1.3`、`RAIN_TINT=Color(0.72,0.84,1,1)`；`_apply_to_particles()`：`vel_mult=0.6+0.8r`、`scale_mult=0.5+0.7r`、`tint.a=0.25+0.55*r`；**从不写 `amount`**（#389 契约红线） | ⚠️ 基值低于 Issue 规范（速度 800–1200、scale 0.5–1.2、alpha 0.2–0.4）；默认雨 (0.3) 下 alpha≈0.415 超标 |
| `mini-pong/tests/test_rain.gd`（265 行） | 公式/clamp/平滑/契约/资源完整性 TC-res-1~20（run_tests.gd 第 34 行已注册） | ❌ 无发射配置断言（position/emission rect/visibility_rect/amount/spread），无分布断言 |
| `mini-pong/assets/rain_drop.png` | 3×14 半透明白竖条（#389 产物，import 正常） | ✅ 符合规范，**保留不动** |
| `mini-pong/scenes/Main.tscn` | `AtmosphereLayer` → `RainCurtain` 实例（无 transform 覆盖） | ✅ 零改动 |

### 1.2 设计哲学

1. **命中实测根因，最小改动面**：D1（visibility_rect 剔除）有 ClassDB 实测证据（`Rect2(-100,-100,200,200)`），D2（半宽语义）为配置事实——修复 = 1 个 tscn 的静态配置修正 + gd 3 组基值对齐 + 测试扩展。**零新节点、零新脚本、零新依赖、零第三方资产**（PRD §1.5 开源调研已沿用 #389 结论：无可复用 2D 雨资产）。
2. **#389 调制契约不可侵犯**：`rain_curtain.gd` 禁写 `amount`（粒子系统重启 → 跳动红线）；运行时调制集 = initial_velocity / scale / color alpha + emitting；公式引擎/平滑/契约 API（`set_wave_factor`/`trigger_event_pulse`/`set_breathing`/`set_intensity`）**零改动**；`constants.gd` RAIN_* 组**零改动**（被 TC-res-8~16 钉死）。
3. **静态配置即断言源**：headless 不渲染粒子 → 分布正确性无法在单测中直接断言渲染输出；设计采用「tscn/gd **静态配置断言**（机械可测）+ E2E 截图分析（运行时覆盖/分布/方向）」双层验证。
4. **可视化窗口与发射区绑定**：`visibility_rect` 是节点**局部坐标**——节点居中后必须显式设全屏 rect，且两者在 tscn 中用注释绑定（防未来位置改动导致重新出现剔除盲区）。

### 1.3 系统关系图

```
（静态配置 — 本次核心修复，一次性修正）
rain_curtain.tscn
  RainCurtain (Node2D, script=rain_curtain.gd)
  └─ Particles (GPUParticles2D)
       position = (360, 640) ──────────────► 发射区 = 世界 (0..720, 0..1280) 全屏
       emission_rect_extents = (360, 640) ──┘ （半宽语义 → 全屏矩形）
       visibility_rect = (-360,-640,720,1280) ► 可视窗口 = 全屏（不再剔除）
       amount = 600 · spread = 8.0 · lifetime=1.8 · preprocess=2.0
       process_material = ParticleProcessMaterial
         initial_velocity_min/max = 800/1200（基值）
         scale_min/max = 0.5/1.2（基值）
         color = (0.72,0.84,1, 0.225)（基值 alpha，运行时被公式覆盖）
（运行时 — #389 契约不变）
rain_curtain.gd 公式引擎（0.1..1.0）
  └─ _apply_to_particles() 每帧调制（禁写 amount）：
       initial_velocity = 800×k .. 1200×k   (k = 0.6+0.8r)   ← 默认雨≈672–1008 px/s
       scale = 0.5×m .. 1.2×m               (m = 0.5+0.7r)
       color.a = 0.15 + 0.25×r              ← 0.225(细雨)..0.40(风暴) ∈ [0.2,0.4] ✓
       emitting = r > 0.05
  └─► GPUParticles2D 渲染：全屏均匀细雨丝斜落（spread 8°，方向一致）
```

---

## 2. 新组件

**无。** 本 Issue 为既有第一方实现的**缺陷修复**（发射配置 + 基值对齐），不引入任何新节点/新脚本/新资源。PRD §4 的 Approach B（CPUParticles2D）与 Approach C（canvas shader）均为文档化兜底，**不提前实施**；仅当 Spike 3 证实 D3（macOS Metal 后端设备级 bug）成立时，implement 才按 PRD §8 决策 1 切换到 B 并回报。

---

## 3. 既有组件修改

### 3.1 `mini-pong/scenes/rain_curtain.tscn` — 核心修复（发射几何 + 可视窗口 + 基值）

**改动点（精确字面，tscn 序列化为 Godot 4.7.1 最小浮点形式）：**

| 属性 | 现值 | 目标值 | 依据 |
|------|------|--------|------|
| `Particles.position` | `Vector2(360, -20)` | `Vector2(360, 640)` | 节点居中 → 发射区/可视窗口与屏幕对齐（#383 竖屏 720×1280） |
| `emission_rect_extents` | `Vector2(360, 8)` | `Vector2(360, 640)` | 半宽语义 → 全屏矩形（Issue 规范：覆盖整个 720×1280，非单点） |
| `visibility_rect`（**新增属性**） | （缺省 → 默认 `Rect2(-100,-100,200,200)` 局部窗口） | `Rect2(-360, -640, 720, 1280)` | 局部坐标 → 世界 (0,0,720,1280) 全屏可视，关闭剔除盲区（D1 主因修复） |
| `amount` | 400 | `600` | 400–800 区间中值（Issue 规范）；静态值，gd **禁写** |
| `spread` | 6.0 | `8.0` | Issue 规范 6–10° 微斜，取中值；方向 `(0,1,0)` 不变 |
| `initial_velocity_min/max` | 700.0/900.0 | `800.0`/`1200.0` | Issue 规范 800–1200 px/s（基值带） |
| `scale_min/max` | 0.7/1.3 | `0.5`/`1.2` | Issue 规范 0.5–1.2 |
| `color` | `Color(0.72, 0.84, 1, 0.45)` | `Color(0.72, 0.84, 1, 0.225)` | alpha 基值取新公式在默认雨 (0.3) 下的值 `0.15+0.25×0.3=0.225`（∈[0.2,0.4]；首帧前静态值与稳态一致，之后被 gd 逐帧覆盖） |
| `lifetime` / `preprocess` | 1.8 / 2.0 | **保留** | 2.0 预热 → 进场景即满屏雨，无 pop-in（PRD §5 边界 7） |
| `emitting` | true | **保留** | 场景级常开，由 gd 的 `emitting = r > 0.05` 逐帧控制 |

**实现注意（注释绑定，写进 tscn）：** `visibility_rect` 与 `position` 必须同步——注释标注"节点居中 + 全屏可视窗口，两者绑定修改"。新增的 `visibility_rect` 属性位于 `[node name="Particles"]` 节（GPUParticles2D 节点属性，非 material 属性）。

### 3.2 `mini-pong/gdscripts/rain_curtain.gd` — 基值对齐（调制契约/公式/平滑零改动）

| 常量/公式 | 现值 | 目标值 | 依据 |
|-----------|------|--------|------|
| `BASE_VELOCITY_MIN/MAX` | 700.0/900.0 | `800.0`/`1200.0` | Issue 规范 800–1200 基值带 |
| `BASE_SCALE_MIN/MAX` | 0.7/1.3 | `0.5`/`1.2` | Issue 规范 0.5–1.2 |
| `_apply_to_particles()` alpha 公式 | `tint.a = 0.25 + 0.55 * r` | `tint.a = 0.15 + 0.25 * r` | 默认雨 0.3→0.225、最大雨 1.0→0.40，全带 ∈ [0.2,0.4] ✓ |

**红线（继承 #389，implement 不得越界）：** `amount` 零写入；`constants.gd` RAIN_* 零改动；`vel_mult=0.6+0.8r` / `scale_mult=0.5+0.7r` 公式**保留**（PRD §3.4 数据流验算：默认雨 ≈672–1008 px/s 落入"风暴上探 1680"的强度语义）；`RAIN_TINT` 色值保留（蓝白 #b8d6ff，符合"白/浅灰蓝"规范）。

### 3.3 `mini-pong/tests/test_rain.gd` — 扩展（**不新建重复套件**）

> **文件名 gap 处理（PRD §3.1/§8 决策 4 继承）：** Issue 文件域写 `test_rain_curtain.gd`（新增/更新），实际既有测试文件为 `test_rain.gd`（265 行，run_tests.gd 第 34 行已注册，TC-res-1~20）。**设计处置：更新既有 `test_rain.gd`**（追加新测试组，避免双套件）；若 review 门禁要求字面文件名，再行改名并同步 run_tests.gd 注册行。

新增测试组（详细用例见 §9）：
- **发射配置断言组**：tscn 文本含 `position = Vector2(360, 640)`、`emission_rect_extents = Vector2(360, 640)`、`visibility_rect = Rect2(-360, -640, 720, 1280)`、`amount = 600`、`spread = 8.0`、`initial_velocity_min = 800.0` / `initial_velocity_max = 1200.0`、`scale_min = 0.5` / `scale_max = 1.2`、color alpha ∈ [0.2,0.4]（沿用 test_neon.gd 的 `FileAccess.get_file_as_string` + `content.contains` 文本断言先例，见 #464 DESIGN §2）
- **基值断言组**：加载 `rain_curtain.gd` 脚本读常量（`BASE_VELOCITY_MIN==800.0` 等，与 test_rain.gd 既有 `_make_curtain()` 模式同型）+ gd 源码文本含 `0.15 + 0.25 * r`
- **回归组**：既有 TC-res-1~20 保持全绿（tscn 结构断言不受配置值影响）

### 3.4 修改清单汇总

**Modified files：**

| 文件 | 改动 | 动机 |
|------|------|------|
| `mini-pong/scenes/rain_curtain.tscn` | position/emission_rect_extents/visibility_rect(新增)/amount/spread/基值/color alpha（§3.1） | D1+D2 根因修复 |
| `mini-pong/gdscripts/rain_curtain.gd` | 3 组基值 + alpha 公式（§3.2） | Issue 规范对齐 |
| `mini-pong/tests/test_rain.gd` | 新增发射配置断言 + 基值断言（§3.3/§9） | 测试即验收（headless 可测部分） |

**New files：** 无（`test_rain_curtain.gd` 按 §3.3 gap 处置不新建）
**Removed/Deprecated：** 无
**Affected test files：** `test_rain.gd`（扩展）；`run_tests.gd` **零改动**（注册行已存在）；`test_visual_contrast.gd`（#464 并行新增）零改动
**Not modified（验证保留）：** `rain_drop.png`、`constants.gd`、`Main.tscn`、`e2e_shots.json`

### 3.5 PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计处置 |
|---------|-----------|---------|
| 文件域写 `test_rain_curtain.gd`（新增/更新） | 既有测试文件实为 `test_rain.gd`（265 行，run_tests.gd 第 34 行已注册） | 更新既有 `test_rain.gd` 避免双套件（§3.3） |
| 修复前 tscn 无 visibility_rect → 默认剔除窗口 | ✅ 核实：tscn 28 行无 `visibility_rect` 属性 | 设计显式新增全屏 `visibility_rect`（§3.1） |
| gd 基值 700/900、0.7/1.3、alpha `0.25+0.55r` | ✅ 核实：与 PRD §1.1 一致 | 按 §3.2 对齐新值 |
| tscn color alpha 基值 0.2–0.4 | 现值 0.45 超标 | 取 0.225（= 新公式默认雨值，§3.1） |
| `#389 契约禁止写 amount` | ✅ 核实：gd 全文无 `amount` 写入 | 红线继承，测试回归守住 |

---

## 4. 数据流

### Flow 1 — 正常路径：全屏均匀雨幕（修复后）

```
1. Main.tscn 实例化 RainCurtain（AtmosphereLayer 下，零改动）
2. Particles 节点静态配置加载：
   position(360,640) + emission_rect_extents(360,640) → 出生点均匀铺满 (0..720, 0..1280)
   visibility_rect(-360,-640,720,1280) → 可视窗口 = 全屏（无剔除）
   preprocess=2.0 → 进场景即有满屏雨（预热）
3. 每帧 _process(delta)：
   a. _update_inputs：球速/比分只读采样 + 事件脉冲指数衰减
   b. _compute_target → compute_target_rain 公式（clamp 0.1..1.0）
   c. smooth_step（τ=0.15s 指数平滑）
   d. _apply_to_particles：velocity/scale/alpha 按 §1.3 公式调制 + emitting 开关（不写 amount）
4. 渲染：全屏均匀细雨丝以 spread 8° 斜落，方向一致
```

### Flow 2 — 剔除兜底（防回归）

```
若 visibility_rect 缺失或小于全屏（如未来位置改动未同步）：
  → 超出局部 rect 的粒子被剔除 → 局部"漏水点"回归
  → 防线：① tscn 注释绑定 position↔visibility_rect（§3.1）
           ② TC-A 组配置断言钉死 rect 值（§9 场景 A）
           ③ E2E 02_midgame 截图覆盖 ≥60% 断言（§9 场景 D）
```

### Flow 3 — 边缘路径：性能降载（fps < 55）

```
全屏雨幕 fps < 55（低端 Mac）→ 降载阶梯（taste-draft 调参，不降 AC1/AC2 阈值）：
  amount 600 → 400（tscn 静态，改一次；gd 不写）→ lifetime 1.8 → 1.5
  仍不达标 → 记录性能数据，评估 Approach C（PRD §5 失败路径 2）
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | **emission_rect_extents 半宽语义**：`(360,640)` 是半宽 → 全屏须 `Vector2(360,640)` + 节点居中 `(360,640)`，任何一项错位都会产生边缘盲区（现配置 `(360,8)`+节点 `(360,-20)` 即 16px 顶部窄带） | TC-A 断言同时钉死 position 与 extents；E2E 截图覆盖 ≥60% 兜底 |
| 2 | **visibility_rect 局部坐标系**：属性为节点局部坐标 → 居中后须 `Rect2(-360,-640,720,1280)`（世界 (0,0,720,1280)） | tscn 注释绑定两者；TC-A 断言 rect 字面；若节点位置再变 rect 必须同步 |
| 3 | **基值×调制公式相互作用**：改 800/1200 后默认雨 (0.3) 实际 ≈672–1008 px/s、风暴 ≈1120–1680——"800–1200"是**基值带**（规范语义），风暴提速是 #389 强度语义（taste-draft 可调 `k` 公式下限，零代码结构改动） | DESIGN §3.2 明确基值/公式职责分离；TC-B 只钉基值常量与 alpha 带 |
| 4 | **headless 不渲染粒子**：单测不得依赖渲染输出 | 分布断言 = 静态配置断言（headless 可跑）+ E2E 截图分析（运行时）双层 |
| 5 | **E2E 断言漂移**：02_midgame 从"零星粒子"变"全屏雨幕" → 色数/帧间差异断言可能变化 | 实测后调 settle_frames/阈值，**不删雨幕**（#389 PRD §3.3 先例） |
| 6 | **amount 静态性**：amount=600 仅为 tscn 静态值；#389 契约禁止运行时写 amount（粒子重启跳动红线） | TC-B 回归守住"gd 无 amount 写入"；实现不得为调密度在 gd 写 amount |
| 7 | **preprocess 预热**：preprocess=2.0 保留 → 进场景即满屏雨，无"先空后满" pop-in | tscn 保留该属性；TC-res 回归 |
| 8 | **D3（macOS Metal 后端设备级 bug）**：配置修正后仍单粒子 | 执行 Spike 3（Compatibility 渲染器对照 / CPUParticles2D 原型）；成立则切 Approach B（PRD §8 已备参数映射表，1–1.5 周） |
| 9 | **tscn 序列化形式漂移**：Godot 编辑器可能将浮点重写（如 `0.5`↔`0.5`、`0.225` 精度变化） | TC-A 断言与实现字面统一（#464 先例：场景与断言使用规范序列化字面；若编辑器重写则以实际写入字面同步断言，容忍记录） |

---

## 6. 逐组件配置（implement 契约速查）

| 组件 | 配置项 | 目标值 | 备注 |
|------|--------|--------|------|
| `rain_curtain.tscn` Particles | `position` | `Vector2(360, 640)` | 屏幕中心 |
| | `amount` | `600` | 静态；gd 禁写 |
| | `lifetime` / `preprocess` / `emitting` | `1.8` / `2.0` / `true` | 保留 |
| | `visibility_rect` | `Rect2(-360, -640, 720, 1280)` | **新增属性**，与 position 注释绑定 |
| `rain_curtain.tscn` ParticleProcessMaterial | `emission_shape` / `emission_rect_extents` | `1` / `Vector2(360, 640)` | 全屏矩形 |
| | `direction` / `spread` | `Vector3(0, 1, 0)` / `8.0` | 斜落方向一致 |
| | `initial_velocity_min/max` | `800.0` / `1200.0` | 基值 |
| | `scale_min/max` | `0.5` / `1.2` | 基值 |
| | `color` | `Color(0.72, 0.84, 1, 0.225)` | 基值 alpha ∈ [0.2,0.4] |
| | `gravity` | `Vector3(0, 350, 0)` | 保留（既有手感） |
| `rain_curtain.gd` | `BASE_VELOCITY_MIN/MAX` | `800.0`/`1200.0` | 常量 |
| | `BASE_SCALE_MIN/MAX` | `0.5`/`1.2` | 常量 |
| | alpha 公式 | `0.15 + 0.25 * r` | 全带 ∈ [0.2,0.4] |

---

## 7. 集成点

> **状态约定：** ⬜ = 待 implement 接线/验证；✅ = implement 完成后回填。review agent merge 前核对无遗留 ⬜ 或显式 defer。

| 集成 | 本组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| #389 调制契约 | `rain_curtain.gd` ↔ `rain_curtain.tscn` | #389 | `_apply_to_particles()` 每帧写 material 属性（velocity/scale/alpha/emitting）；禁写 amount；契约 API 签名不变 | ⬜ |
| 场景挂载 | `RainCurtain` 实例 ↔ `Main.tscn` AtmosphereLayer | #383/#389 | 零改动（继承场景内节点配置） | ⬜ 仅回归 |
| 测试注册 | `test_rain.gd` ↔ `run_tests.gd` 第 34 行 | #389 | 既有注册行保留，扩展文件内容 | ⬜ 仅回归 |
| E2E 视觉 | 02_midgame 截图 ↔ `e2e_shots.json`（gdscripts/.*\.gd 命中 rain_curtain.gd） | #358 | 全屏雨幕截图 + 4 重断言 + 3 区密度偏差 <30% | ⬜ |
| 并行隔离 | 本 PR 文件域 vs #464（颜色） | #464 | 文件域零重叠；提交前 merge main 由 worktree-commit.sh 自动处理 | ✅ 结构保证 |

---

## 8. 实施阶段

| 阶段 | 优先级 | 内容 | 依赖 |
|:----:|:------:|------|------|
| Phase 1 | P0 | `rain_curtain.tscn` 配置修正（§3.1 全表，含 visibility_rect + 注释绑定） | 无 |
| Phase 2 | P0 | `rain_curtain.gd` 基值 + alpha 公式（§3.2） | Phase 1（同帧生效） |
| Phase 3 | P0 | `test_rain.gd` 新增断言组（§9 场景 A/B）+ 回归（场景 C） | Phase 1+2 |
| Phase 4 | P1 | 本地 headless 全绿（`godot --path mini-pong/ --headless --script tests/run_tests.gd`） | Phase 3 |
| Phase 5 | P1 | 真机截图对照（Spike 1/2/3）：修复前"漏水点" vs 修复后全屏 | Phase 1–4 |
| Phase 6 | P1 | E2E 实弹：02_midgame 全屏雨幕、3 区偏差 <30%、fps ≥55（低端 Mac）；必要时调 settle_frames/降载（§4 Flow 3） | Phase 5 |

**PR files 白名单（AC6 红线）：** `scenes/rain_curtain.tscn` + `gdscripts/rain_curtain.gd` + `tests/test_rain.gd`（+本 DESIGN）。`rain_drop.png` 未改动不进 PR；用 `worktree-commit.sh` 白名单 add，绝不 `git add .`。

---

## 9. 测试用例描述

> **Plan 阶段边界：** 以下仅为**用例描述**（场景/前置/预期），**不写可运行测试代码**——run 函数实现与断言代码由 implement agent 在 Phase 3 编写，沿用 `test_rain.gd` 既有 `_make_curtain()` / `_assert()` / 文本断言（`FileAccess.get_file_as_string` + `contains`，test_neon.gd 先例）模式。

### 场景 A：发射配置断言（tscn 静态文本，headless 可跑）

- **Test A1（节点居中）**：前置 = rain_curtain.tscn 文本可读；预期 = 含 `position = Vector2(360, 640)`。
- **Test A2（全屏发射区）**：前置 = 同上；预期 = 含 `emission_rect_extents = Vector2(360, 640)`（半宽语义 → 720×1280 全屏）。
- **Test A3（全屏可视窗口，D1 修复核心）**：前置 = 同上；预期 = 含 `visibility_rect = Rect2(-360, -640, 720, 1280)`（缺失或小于全屏即 FAIL）。
- **Test A4（粒子数量）**：前置 = 同上；预期 = 含 `amount = 600`（≥400 规范带中值）。
- **Test A5（斜落方向一致）**：前置 = 同上；预期 = `direction = Vector3(0, 1, 0)` 且 `spread = 8.0`（∈[6,10]）。
- **Test A6（速度/尺寸基值）**：前置 = 同上；预期 = `initial_velocity_min = 800.0`、`initial_velocity_max = 1200.0`、`scale_min = 0.5`、`scale_max = 1.2`。
- **Test A7（颜色 alpha 带）**：前置 = 同上；预期 = material `color` 的 alpha ∈ [0.2, 0.4]（解析文本或字面匹配 `Color(0.72, 0.84, 1, 0.225)`）。

### 场景 B：gd 基值与 alpha 公式断言（headless 可跑）

- **Test B1（速度基值常量）**：前置 = `load("res://gdscripts/rain_curtain.gd")` 成功；预期 = `BASE_VELOCITY_MIN == 800.0` 且 `BASE_VELOCITY_MAX == 1200.0`。
- **Test B2（尺寸基值常量）**：前置 = 同上；预期 = `BASE_SCALE_MIN == 0.5` 且 `BASE_SCALE_MAX == 1.2`。
- **Test B3（alpha 公式带）**：前置 = 加载脚本并模拟公式（或断言 gd 源码文本含 `0.15 + 0.25 * r`）；预期 = 默认雨 r=0.3 → alpha=0.225 ∈ [0.2,0.4]；最大雨 r=1.0 → alpha=0.40 ≤ 0.4（全带合规）。
- **Test B4（amount 红线回归）**：前置 = gd 源码全文；预期 = 不含任何 `amount =` / `amount=` 写入（#389 契约，防跳动回归）。

### 场景 C：既有回归（#389 套件不动）

- **Test C1–C20**：前置 = 既有 TC-clamp-1~5 / TC-formula / TC-tension / TC-smoothing / TC-pulse / TC-contract / TC-nan / TC-res-1~20 全部保留；预期 = 全绿（基值/alpha 修改不影响公式/clamp/平滑/契约——`compute_target_rain`/`smooth_step`/契约 API 零改动）。

### 场景 D：E2E 视觉验证（运行时，implement Phase 5–6 实测，非单测）

- **Test D1（全屏覆盖 AC1）**：前置 = 02_midgame 截图（修复后配置）；预期 = 雨像素分布覆盖 ≥ 60% 屏幕区域（网格采样量化；对照修复前"漏水点"截图）。
- **Test D2（三区均匀 AC2）**：前置 = 同上；预期 = 上/中/下三等分雨像素密度偏差 `|max−min|/avg < 30%`。
- **Test D3（方向一致 AC3）**：前置 = 同上；预期 = 雨丝倾斜方向一致（spread 8° 微斜，无乱向）。
- **Test D4（性能 AC5）**：前置 = 低端 Mac 全屏雨幕；预期 = fps ≥ 55；不达标按 §4 Flow 3 降载阶梯（amount→400 / lifetime→1.5）后复测，不降 AC1/AC2 阈值。

### 验收条件映射（Issue #465 body）

| AC | 验证方式 | 对应用例 |
|----|---------|---------|
| 全屏有雨（覆盖 ≥60%） | E2E 截图分析 | D1 |
| 粒子 ≥400 且均匀（三区偏差 <30%） | tscn 断言 + E2E | A4 + D2 |
| 斜落方向一致 | tscn 断言 + E2E | A5 + D3 |
| 视觉参数合规（scale/速度/颜色 alpha） | tscn + gd 断言 | A6/A7 + B1/B2/B3 |
| 性能 fps ≥55 | 实测 | D4 |
| run_tests.gd 全绿 + PR files 仅含文件域 | headless + 白名单 | C1–C20 + §8 白名单 |

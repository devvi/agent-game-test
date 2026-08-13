# PRD: [Feature] 雨幕粒子修复 — 全屏均匀雨滴分布 (漏水点 → 雨)

> **Issue:** #465
> **标签:** enhancement, graphics, priority/high, version/v1, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #389/#464 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（"单粒子"根因、macOS 兼容性）而包含 3 个轻量实验）
> **所有权:** `content_ownership: mechanical`（发射配置/覆盖率为机械可测；雨滴视觉浓度 = taste-draft，走 human-review 定稿）
> **前置依赖:** 无（#465 无依赖，独立推进；底层依赖 #389/#383 均已 CLOSED）

---

## 1. 问题定义

### 1.1 当前状态

Mini Pong 的 L0 氛围层雨幕（#389 落地，commit `5774417`）存在**发射覆盖异常**：用户实测"雨粒子只有一个悬在屏幕中间偏右上角, 不像是雨, 更像漏水点"。粒子没有全屏铺开。

| 系统 | 当前状态 | 与需求的差距 |
|------|---------|------------|
| `mini-pong/scenes/rain_curtain.tscn` | GPUParticles2D 节点 `position=(360,-20)`；`ParticleProcessMaterial`: `emission_shape=1`(RECTANGLE)、`emission_rect_extents=Vector2(360,8)`、`spread=6.0`、`initial_velocity 700–900`、`scale 0.7–1.3`、`color=(0.72,0.84,1,0.45)`；`amount=400`、`lifetime=1.8`、`preprocess=2.0` | ❌ 只生成一条 16px 高的顶部窄带发射区（y∈[-28,-12]），且大量粒子被剔除（见 1.2 诊断 D1）→ 屏幕只见零星粒子 |
| `mini-pong/gdscripts/rain_curtain.gd` | #389 公式引擎：`BASE_VELOCITY_MIN/MAX=700/900`、`BASE_SCALE_MIN/MAX=0.7/1.3`、`RAIN_TINT=(0.72,0.84,1)`、运行时 alpha = `0.25+0.55×rain`；**从不写 `amount`**（粒子重启跳动红线） | ⚠️ 基值低于 Issue 规范（速度 800–1200、scale 0.5–1.2、alpha 0.2–0.4）；默认雨量(0.3)下实际 alpha≈0.415 超标 |
| `mini-pong/tests/test_rain.gd` | 覆盖公式/clamp/平滑/契约/资源完整性（TC-res-1~20） | ❌ 无发射配置断言（emission rect / amount / visibility_rect），无分布断言 |
| `mini-pong/assets/rain_drop.png` | 3×14 半透明白竖条（#389 产物，import 正常） | ✅ 符合 Issue 规范（保留或微调） |
| `mini-pong/scenes/Main.tscn` | `AtmosphereLayer` → `RainCurtain` 实例（无 transform 覆盖，继承场景内 position） | — 无需改动 |

### 1.2 "单粒子"根因诊断（本次研究核心产出）

研究在 **Godot 4.7.1 实测环境**下用 `ClassDB` 验证了两个关键事实（脚本 `/tmp/check_*`，headless 运行）：

| # | 候选根因 | 证据 | 判定 |
|---|---------|------|------|
| **D1** | **GPUParticles2D 默认 `visibility_rect` 剔除** — 实测默认值 `Rect2(-100,-100,200,200)`（节点局部坐标）。节点在 `(360,-20)` → 可视窗口为世界坐标 x∈[260,460]、y∈[-120,80]（约 200px 宽的中心窄柱）。发射区横跨 x∈[0,720]，**落在可视窗口外的粒子全部被剔除** | 实测 `ClassDB.class_get_property_default_value("GPUParticles2D","visibility_rect") = [P:(-100,-100),S:(200,200)]`（2026-08-13 headless 验证）；tscn 中未设置该属性 | ✅ **最可能主因**：恰好解释了"只有屏幕中偏右上方零星粒子"（节点 x=360 居中，spread 6°+重力使幸存粒子右偏下坠） |
| **D2** | 发射区过窄 + 半宽语义混淆 — `emission_rect_extents` 是**半宽**（Godot 语义），`(360,8)` = 720×16px 顶部窄带而非 720×1280 全屏；Issue 规范要求"emission_rect_extents 覆盖整个 720x1280, 非单点" | tscn 实际值；Issue body 明示规范 | ✅ 配置不符规范（即使无剔除也非"全屏均匀"），需改为全屏矩形 |
| **D3** | macOS Metal 后端 GPUParticles2D 已知兼容性问题（部分设备/驱动下粒子数量异常或仅渲染少量粒子） | Issue body 怀疑方向；社区已知报告（Godot 4.x macOS 粒子渲染问题） | ⚠️ 需实验排除（§7 Spike 3）：修复 D1/D2 后若仍异常再验证 |

**结论：修复策略 = 先按 D1+D2 修正配置（低成本、确定性高），D3 作为兜底验证项。** 诊断实验见 §7。

### 1.3 预期行为（验收条件，源自 Issue #465）

1. **全屏均匀雨幕** — 修复后全屏有雨（截图分析：雨像素分布覆盖 ≥ 60% 屏幕区域）
2. **粒子数量与分布** — 粒子数量 ≥ 400，均匀分布（上中下三区域粒子密度偏差 < 30%）
3. **方向一致** — 雨滴斜落方向一致（velocity 方向一致，spread 6–10° 微斜）
4. **视觉参数** — 细长雨滴（rain_drop.png 3×14 保留）、scale 0.5–1.2、下落速度 800–1200 px/s、颜色白/浅灰蓝 alpha 0.2–0.4
5. **性能** — 全屏雨幕时 fps ≥ 55（低端 Mac）
6. **回归** — `run_tests.gd` 全绿；PR files 仅含文件域（雨幕子系统：tscn/gd/png/雨测试）

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 游戏启动/波次开始 | 每次启动 | 竖屏雨夜竞技场开场即有**全屏细雨**（非单点漏水），霓虹 glow 之上雨丝斜落 |
| B | Rally 进行中 | 持续 | #389 公式驱动雨量 0.3→1.0，粒子速度/尺寸/透明度随强度平滑变化，覆盖保持全屏均匀 |
| C | 验收截图 | 一次性 | 02_midgame 截图可见全屏雨幕，三区域密度偏差 < 30% |

### 1.5 技术约束（继承自 Issue #465 + 既有系统）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1（实测 `4.7.1.stable.official.a13da4feb`），本项目 = `mini-pong/`（自有 project.godot，Forward+ 渲染） |
| 画幅 | 720×1280 竖屏（#383 已落地）；发射区/可视区须覆盖全屏 |
| 发射规范 | `emission_rect_extents` 覆盖整个 720×1280（**半宽语义**：`Vector2(360,640)`，节点居中 `(360,640)`） |
| #389 调制契约 | `rain_curtain.gd` **禁止写 `amount`**（Godot 重启粒子系统 → 跳动，AC 红线，§1.5 of PRD #389）；运行时只调制 initial_velocity / scale / color alpha + emitting |
| 不变项 | 公式引擎/clamp/平滑/契约 API（`set_wave_factor`/`trigger_event_pulse`/`set_breathing`/`set_intensity`）零改动；`constants.gd` RAIN_* 组零改动；ball/scoring 信号链零改动 |
| 开源优先 | #389 PRD §1.5 已调研 Godot Asset Library + GitHub（godot-weather-2D 93⭐ 等），结论：无可复用 2D 雨资产，第一方实现（本 Issue 是**既有第一方实现的缺陷修复**，不引入第三方，直接沿用该结论） |
| 所有权 | mechanical（覆盖/分布/方向）；浓度曲线/雨滴视觉 = taste-draft 候补 |

### 1.6 范围去冲突（vs PRD #389）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #389 动态雨幕（CLOSED） | 雨量公式引擎 + 参数调制契约 + 平滑 + Main.tscn 挂载（**逻辑层**：雨量如何算、如何调） | ❌ 不改公式/契约/平滑；本 PRD 只修**发射配置与分布**（渲染层：粒子从哪发射、是否被剔除、覆盖多少屏幕） |

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 现状来源 | Issue/提交 | 贡献 |
|---------|-----------|------|
| 雨幕 L0 执行层落地 | #389（commit `5774417`，2026-08-13） | 公式驱动调制 + GPUParticles2D 场景；**发射配置（position/extents/visibility_rect）从未在真机验证** —— 代码评审与 headless 测试只验证了"节点存在/公式正确"，不验证"粒子实际渲染覆盖"（headless 不渲染粒子） |
| 竖屏坐标系 | #383（CLOSED） | 720×1280 垂直攻防；雨幕发射区按 720 宽设计但高度仅 16px 窄带 |
| 视觉基调 | #289 | 深底 + 霓虹；雨滴蓝白半透明、克制优先 |

**根因一句话**：`rain_curtain.tscn` 的发射几何（位置/半宽/可视剔除窗口）是"纸面正确"（宽度覆盖 720），但 GPUParticles2D 默认 `visibility_rect`（200×200 局部窗口）把发射区边缘的粒子全部剔除，加上发射区仅 16px 高，幸存粒子集中在节点附近的窄柱内 → "单个漏水点"。

### 2.2 为什么现在改

1. **用户可见的核心氛围缺陷**：雨幕是 L0 氛围层的门面（#389 设计意图），"漏水点"直接破坏雨夜竞技场的视觉可信度，priority/high。
2. **修复面收敛、确定性高**：根因 D1 有实测证据（默认 visibility_rect 值），修复 = 场景配置修正 + 参数基值对齐 Issue 规范，不动公式/契约/信号链 → mechanical 低风险。
3. **workflow/available 阶段**：无依赖、无阻塞，可独立推进到 plan/implement。

### 2.3 先前约束

| 约束 | 细节 |
|------|------|
| #389 调制契约 | 禁止写 `amount`；运行时调制集 = initial_velocity_min/max + scale_min/max + color alpha；emitting 开关 |
| #389 平滑 | τ=0.15s 指数平滑，0.5s 达 95%+；测试钉死无跳变 |
| #383 竖屏 | 720×1280；发射区宽 720 与屏幕对齐 |
| #289 视觉基调 | 深底 #0a0a12、霓虹 glow；雨滴蓝白半透明、不抢戏（alpha ≤ 0.4） |
| 测试即验收 | 沿用 test_rain.gd 资源完整性断言风格 + run_tests.gd 注册；headless 不渲染粒子 → 分布断言走配置断言 + E2E 截图 |
| E2E | e2e_shots.json 命中 `gdscripts/.*\.gd`（rain_curtain.gd 必命中）→ 02_midgame 截图含全屏雨幕，4 重断言需实测通过 |

---

## 3. 影响分析

### 3.1 直接改动文件

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/scenes/rain_curtain.tscn` | 场景 | **核心修复**：节点 `position=(360,640)`（屏幕中心）；`emission_rect_extents=Vector2(360,640)`（全屏矩形）；`visibility_rect=Rect2(-360,-640,720,1280)`（关闭剔除盲区，覆盖全屏）；`amount=600`（400–800 区间中值）；`spread=8.0`（6–10° 微斜）；`initial_velocity 800–1200`、`scale 0.5–1.2`、`color` alpha 基值 0.2–0.4（与 gd 调制公式联动）；`lifetime/preprocess` 保留（1.8/2.0 预热防 pop-in） |
| `mini-pong/gdscripts/rain_curtain.gd` | 脚本 | 基值对齐 Issue 规范（**调制契约不变**）：`BASE_VELOCITY_MIN/MAX` 700/900 → 800/1200；`BASE_SCALE_MIN/MAX` 0.7/1.3 → 0.5/1.2；alpha 公式 `0.25+0.55r` → `0.15+0.25r`（默认雨 0.3 → 0.225，最大雨 1.0 → 0.40，落入 0.2–0.4 规范带） |
| `mini-pong/tests/test_rain.gd` | 测试 | **扩展**（不新建重复套件；Issue 文件域写 `test_rain_curtain.gd`（新增/更新），实际既有测试文件为 `test_rain.gd` 且已在 run_tests.gd 注册 —— 建议更新既有文件，避免双套件；如 review 门禁要求字面文件名再改名）：新增发射配置断言（tscn 文本含 `emission_rect_extents = Vector2(360, 640)`、`visibility_rect` 全屏、`amount = 600`、spread ∈ [6,10]）+ 基值断言（BASE_VELOCITY/SCALE 新值、alpha 公式 0.2–0.4 带） |

### 3.2 不改动文件（验证保留）

| 文件 | 说明 |
|------|------|
| `mini-pong/assets/rain_drop.png` | 3×14 符合规范，保留；仅复验 .import 正常 |
| `mini-pong/gdscripts/constants.gd` | RAIN_* 组零改动（RAIN_BASE=0.3 等已被 test_rain.gd TC-res-8~16 钉死） |
| `mini-pong/scenes/Main.tscn` | AtmosphereLayer 实例无需改动（继承场景内节点配置） |
| `mini-pong/tests/run_tests.gd` | 既有 test_rain.gd 注册保持（若新建 test_rain_curtain.gd 才需加一行） |

### 3.3 间接影响（需回归验证）

| 文件 | 影响 | 处理 |
|------|------|------|
| `mini-pong/e2e_shots.json` | 02_midgame 截图从"零星粒子"变为"全屏雨幕" → 非黑/色数/帧间差异断言可能受影响 | 实测；必要时调 settle_frames，不删雨幕（#389 PRD §3.3 先例） |
| `mini-pong/tests/test_rain.gd` 既有用例 | TC-res-2~4 断言 tscn 含 GPUParticles2D/ParticleProcessMaterial/脚本 —— 不受配置修改影响 | 回归全绿即可 |
| #389 调制契约消费方（#384/#385/#386/#388 契约 API） | 契约 API 签名不变，基值变化只影响雨量→参数的映射幅度 | 零改动 |

### 3.4 数据流影响

```
（静态配置，tscn 一次性修正）
    RainCurtain node position = (360, 640) ──► 发射区 = (0..720, 0..1280) 全屏
    emission_rect_extents = (360, 640)      ├──► 粒子出生点均匀铺满全屏
    visibility_rect = (-360,-640,720,1280)  └──► 可视窗口 = 全屏（不再剔除边缘粒子）
            │
（运行时，#389 契约不变）
    rain_curtain.gd 公式引擎（0.3→1.0）
            │
            ▼
    initial_velocity 800×k .. 1200×k (k=0.6+0.8r)   ← 默认雨≈672–1008 px/s，风暴≈1120–1680
    scale 0.5×m .. 1.2×m (m=0.5+0.7r)
    color alpha = 0.15 + 0.25×r                     ← 0.225(细雨) .. 0.40(风暴) ∈ [0.2,0.4] ✓
    emitting = r > 0.05
            │
            ▼
    GPUParticles2D 渲染：全屏均匀雨丝斜落（spread 8° 方向一致）
```

### 3.5 文档更新

- [ ] `docs/PRD/465-rain-curtain-fix.md`（本文件）
- [ ] `docs/DESIGN/389-dynamic-rain-curtain.md` — 实现 PR merge 后由 review agent 增量标注发射配置修订（不重写）

---

## 4. 方案对比

### Approach A：修正 GPUParticles2D 场景配置 + 基值对齐（推荐）

保留 GPUParticles2D + #389 调制契约，按 §1.2 诊断修正 `rain_curtain.tscn`（节点居中、全屏 emission rect、全屏 visibility_rect、amount 600、spread 8°）并对齐 `rain_curtain.gd` 基值（velocity 800/1200、scale 0.5/1.2、alpha 公式 0.15+0.25r）。

- **Pros**：直接命中实测根因 D1/D2；改动面最小（1 tscn + 3 组常量 + 测试扩展）；#389 契约/公式/信号链零改动 → mechanical 风险最低；与 Issue 规范逐条对应（全屏矩形、amount 400–800、速度/尺寸/颜色/方向）
- **Cons**：若 macOS Metal 后端存在 D3 类设备级 bug，配置修正后仍可能异常（需 §7 Spike 3 验证兜底）
- **Risk**：Low–Med（D3 未排除）
- **Effort**：0.5–1 周

### Approach B：切换 CPUParticles2D 兜底

若 Spike 3 证实 macOS Metal 后端 GPU 粒子渲染异常（D3 成立），将雨幕改为 CPUParticles2D（CPU 计算，渲染后端无关）。

- **Pros**：规避 GPU 粒子在 macOS 的全部已知问题；400–600 粒子 CPU 开销可接受（2D 场景）
- **Cons**：**CPUParticles2D 无 `process_material`（ParticleProcessMaterial 仅 GPU 粒子）** → rain_curtain.gd 的 `_material.initial_velocity_min` 等全部调制代码需改写为 CPU 参数（`initial_velocity_min/max` 等直接属性）；测试的 tscn 断言（ParticleProcessMaterial 存在）需改；#389 契约 API 外层不变但实现层重写 → 回归面大
- **Risk**：Med–High（契约实现重写 + 测试改动）
- **Effort**：1–1.5 周

### Approach C：纯 canvas shader 程序化雨丝

`rain_curtain.gdshader` 在 L0 层噪声/正弦画雨丝，uniform 驱动密度/速度。

- **Pros**：无粒子剔除问题；性能最优
- **Cons**：**违反 Issue 明示规范**（"GPUParticles2D emission: 全屏矩形"）；与 #389 参数调制契约（ParticleProcessMaterial 属性）不兼容 → 公式引擎白写；headless shader 编译报错面大、分布断言不可行
- **Risk**：High（AC 不合规）
- **Effort**：1 周

### 推荐

**Approach A**。理由：(1) 根因 D1 有实测证据（默认 `visibility_rect=Rect2(-100,-100,200,200)`，2026-08-13 headless 验证），配置修正即对症；(2) 唯一同时满足全部 AC 且零契约破坏的方案；(3) B 作为 **Spike 3 证实 D3 后**的文档化兜底（不提前实施）；(4) C 违反 Issue 字面规范，排除。

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body）

- [x] **AC1: 全屏有雨（覆盖 ≥ 60% 屏幕）** — 修复后 E2E 截图分析：雨像素分布覆盖 ≥ 60% 屏幕区域（复用 e2e analyze_bmp 或等效脚本，网格采样）；验收基准 = 修复前截图（"漏水点"）对照
- [x] **AC2: 粒子 ≥ 400 且均匀（三区域密度偏差 < 30%）** — `amount=600`（tscn 断言 ≥ 400）；E2E 截图按上/中/下三等分统计雨像素密度，|max−min|/avg < 30%；单测断言 tscn amount 值
- [x] **AC3: 斜落方向一致** — `direction=(0,1,0)` + `spread=8.0`（tscn 断言 ∈ [6,10]）；E2E 截图上雨丝角度一致（无乱向）
- [x] **AC4: 视觉参数符合规范** — scale 0.5–1.2、速度 800–1200 px/s（默认雨带 ≈672–1008，风暴上探 1680 属 #389 强度语义）、颜色 (0.72,0.84,1) alpha 0.2–0.4（默认 0.225 / 风暴 0.40）；单测断言 gd 基值 + alpha 公式带
- [x] **AC5: 性能 fps ≥ 55（低端 Mac）** — 全屏雨幕实测帧率；不达标则 amount 回落 400 / lifetime 缩短（taste-draft 调参，不降 AC1/AC2 阈值）
- [x] **AC6: run_tests.gd 全绿 + PR files 仅含文件域** — headless `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；PR 改动仅限 `rain_curtain.tscn` / `rain_curtain.gd` / `test_rain.gd`（+本 PRD）；rain_drop.png 若未改动则不进 PR

### 边界情况（Edge Cases）

1. **半宽语义**：`emission_rect_extents` 为半宽 → 全屏须 `Vector2(360,640)` + 节点居中 `(360,640)`，任何一项错位都会产生边缘盲区（如原配置 `(360,8)` + 节点 `(360,-20)` = 顶部 16px 窄带）
2. **visibility_rect 坐标系**：属性为**节点局部坐标** → 节点居中后须设 `Rect2(-360,-640,720,1280)`（世界 (0,0,720,1280)）；若节点位置再变，rect 必须同步（实现时用注释绑定两者）
3. **#389 运行时调制与基值的相互作用**：基值改 800/1200 后，调制公式 `k=0.6+0.8r` 使默认雨 ≈672–1008、风暴 ≈1120–1680 —— "800–1200"是基值带（规范语义），风暴提速是强度语义（taste-draft 可调 k 公式下限）
4. **headless 不渲染粒子**：单测不得依赖渲染输出；分布断言 = tscn 配置断言（静态）+ E2E 截图分析（运行时）
5. **E2E 断言漂移**：02_midgame 从零星粒子变全屏雨幕 → 色数/帧间差异断言可能变化；处理 = 调 settle_frames/阈值，不删雨幕
6. **amount 静态性**：amount=600 仅为 tscn 静态值；#389 契约禁止运行时写 amount（跳动红线）——实现不得为"调密度"在 gd 中写 amount
7. **preprocess 预热**：preprocess=2.0 保留 → 进场景即满屏雨，无"先空后满" pop-in

### 失败路径（Failure Paths）

1. **配置修正后仍单粒子（D3 成立，macOS Metal 设备级 bug）** → 执行 §7 Spike 3 验证（Compatibility 渲染器对照 / CPUParticles2D 原型）；成立则切 Approach B（文档化兜底，1–1.5 周）
2. **全屏雨幕导致 fps < 55（低端 Mac）** → amount 600→400、lifetime 1.8→1.5 降载；仍不达标则 Approach C 评估（记录性能数据再决策）
3. **E2E 4 重断言失败（雨幕过密）** → 调 alpha 公式下界（0.15→0.10）与 settle_frames，保留覆盖 ≥60% 主 AC
4. **visibility_rect 属性在目标版本缺失/改名** → 实测环境为 Godot 4.7.1，`ClassDB` 已确认属性存在（type 7=Rect2）；实现前用 §7 Spike 2 复验即可排除

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #465 自身 | 无 Depends On（Issue 无依赖字段） | — |
| #389 动态雨幕（L0 执行层） | ✅ CLOSED（commit `5774417`） | Low — 本 Issue 修复其发射配置，调制契约必须继承 |
| #383 轴交换 + 竖屏 720×1280 | ✅ CLOSED | Low — 全屏发射区坐标基准 |
| #289 霓虹视觉基调 | ✅ 已落地 | Low — 雨滴蓝白半透明叠加既有视觉 |

### 阻塞（Blocks）

| 后续工作 | 优先级 | 说明 |
|---------|:---:|------|
| 无 | — | mechanical 独立 Issue，不阻塞任何在途工作 |

### 依赖链

```
Issue #383 轴交换+竖屏（✅ CLOSED）
        │
        ▼
Issue #389 动态雨幕 L0（✅ CLOSED, commit 5774417）
        │  （调制契约继承：禁写 amount、调制集、平滑）
        ▼
Issue #465 雨幕粒子修复（本 PRD — 发射配置/分布修复，无其他依赖）
```

---

## 7. Spike / 实验

depth/standard 下 Section 7 非必填，但"单粒子"根因存在真实技术不确定性（配置 vs 平台兼容），故含 3 个轻量实验，成本各 ≤0.5 天：

### 实验 1：复现"单粒子"现象并对照修复前后截图

- **问题**：当前 tscn 在真机（macOS）上是否稳定复现"只有零星粒子"？修复后的配置是否全屏有雨？
- **方法**：`godot --path mini-pong/` 跑 Main.tscn（或独立 rain 场景），`--write-movie` 或截图脚本采集 02_midgame 画面；分别用 ①当前配置 ②仅设全屏 visibility_rect ③全屏 rect + 居中节点 采集三张对照图
- **预期结果**：②出现"横跨全宽的雨带"（证明 D1 剔除是主因）；③全屏均匀（证明 D2 修正）
- **对方案影响**：确认 Approach A 的配置集；若 ③ 仍异常 → 触发 Spike 3

### 实验 2：visibility_rect 属性行为验证

- **问题**：Godot 4.7.1 中 GPUParticles2D `visibility_rect` 的剔除语义是否如文档所述（粒子超出局部 rect 即被剔除）？
- **方法**：`ClassDB` 已确认属性存在（type 7）；构造最小场景：节点 (0,0)、emission rect 全屏、visibility_rect 分别设默认 / 全屏，headless + 真机截图对比
- **预期结果**：默认 rect 下边缘粒子不可见；全屏 rect 下可见 → D1 实锤
- **对方案影响**：定稿 tscn 中 visibility_rect 的值与注释绑定说明

### 实验 3：macOS Metal 兼容性排除（D3）

- **问题**：配置全部修正后，macOS 设备上是否仍存在 GPU 粒子渲染异常（后端级 bug）？
- **方法**：修正配置实机验证；若异常，切 Compatibility 渲染器对照；再异常则建 CPUParticles2D 最小原型对比渲染结果与 fps
- **预期结果**：配置修正后正常 → D3 排除；异常 → D3 成立，Approach B 兜底
- **对方案影响**：决定是否启用 Approach B（提前准备好 CPUParticles2D 参数映射表，避免实施期返工）

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #465 当前 `workflow/available`；本 PRD（research PR）merge 后 workflow-chain 推进 → `workflow/plan`
- 基线：`main` HEAD = `532724a`（docs(plan) #464）；Godot 4.7.1 实测可用（`godot --path mini-pong/ --headless` 全绿）
- 实测证据（本 PRD 独有，plan/implement 必须继承）：`GPUParticles2D.visibility_rect` 默认 `Rect2(-100,-100,200,200)`（2026-08-13 `ClassDB` 验证）——"单粒子"主因
- 既有测试：`test_rain.gd`（265 行，TC-res-1~20 资源完整性）注册于 run_tests.gd 第 34 行

### 关键决策（plan agent 必须继承）

1. **Approach A**：修正 `rain_curtain.tscn`（节点 `(360,640)` + `emission_rect_extents=(360,640)` + `visibility_rect=(-360,-640,720,1280)` + `amount=600` + `spread=8.0`）；**不切 CPUParticles2D / shader**（Spike 3 证实 D3 才启用 B）
2. **基值对齐**（rain_curtain.gd，调制契约/公式/平滑零改动）：`BASE_VELOCITY_MIN/MAX` → 800/1200；`BASE_SCALE_MIN/MAX` → 0.5/1.2；alpha 公式 → `0.15 + 0.25×rain`（∈[0.2,0.4]）
3. **红线继承**：#389 契约禁止运行时写 `amount`；`constants.gd` RAIN_* 零改动；ball/scoring 信号链零改动
4. **测试策略**：更新既有 `test_rain.gd`（Issue 文件域写 test_rain_curtain.gd，实际既有文件为 test_rain.gd —— 更新既有避免双套件；若 review 门禁要字面文件名再改名）；新增 tscn 发射配置断言 + 基值/alpha 带断言；分布验证走 E2E 截图分析（headless 不渲染粒子）
5. **E2E**：02_midgame 截图将变为全屏雨幕；4 重断言实测，必要时调 settle_frames，不删雨幕
6. **验收基准**：修复前截图（漏水点）保留为对照；AC1 覆盖 ≥60%、AC2 三区偏差 <30% 用网格采样脚本量化

### 实现顺序建议（plan agent 参考）

1. `rain_curtain.tscn` 配置修正（含 visibility_rect + 注释绑定）→ 2. `rain_curtain.gd` 基值/alpha 公式 → 3. `test_rain.gd` 新增配置断言 → 4. 本地 headless 全绿 → 5. 真机截图验证（Spike 1/2/3 对照）→ 6. E2E 实弹（02_midgame 全屏雨 + fps ≥55）

### 主要风险

- D3（macOS Metal 设备级 bug）在配置修正后仍存在 → Approach B 兜底（Spike 3 前置验证）
- 全屏雨幕 fps 不达标 → amount/lifetime 降载（taste-draft）
- E2E 断言漂移 → settle_frames 调整（#389 PRD §3.3 先例）

### 交接清单

- [ ] 本 PRD 文件 `docs/PRD/465-rain-curtain-fix.md`
- [ ] 实测证据：`visibility_rect` 默认值 `Rect2(-100,-100,200,200)`（§1.2/§8）
- [ ] 既有代码基线：`rain_curtain.tscn`（28 行）、`rain_curtain.gd`（137 行）、`test_rain.gd`（265 行）—— 均在 main HEAD `532724a` 上
- [ ] 对照基准：修复前"漏水点"截图（E2E 或真机采集）

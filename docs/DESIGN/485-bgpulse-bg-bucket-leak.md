# DESIGN: [Bug] 修复 L3 视觉 E2E — BgPulse 相位使背景桶泄漏进 region dominant → pair dist 0.0 + rain 假阳性

> **Parent Issue:** #485
> **Agent:** game-plan-agent
> **Date:** 2026-08-14
> **Approach:** B（断言侧动态 bg 采样：`check_visual` 从帧内角落区实测背景色作为 bg_ref，替代静态 bg_color，参与全部 bg-relative 计算）+ C 的 paddle 阈值校准为辅 —— 确认 PRD §4.4 推荐组合；否决 A（capture 侧固定 alpha：测试帧 ≠ 真实帧 + 模板改动面大 + 不防未来背景动画）
> **Reference PRD:** docs/PRD/485-bgpulse-bg-bucket-leak.md（research PR #487，已合并）
> **上游方案:** docs/DESIGN/466-visual-regression-e2e.md（L3 区域断言，PR #475 未合并）、docs/DESIGN/476-l3-visual-regression-fix.md（bg-relative 语义）、docs/PRD/480-e2e-runner-fix.md（AC4 引用）
> **所有权:** `content_ownership: mechanical`（动态背景采样 + 阈值校准 = 机械可测；雨幕/背景视觉值已由 #464/#465 定稿，无品味决策）
> **深度:** depth/standard（Issue 无 depth 标签，按 #466/#480 惯例）—— 文件域 4 个（analyze_bmp.py / e2e_shots.json / test_e2e_analyze.py / DESIGN 466 文档行），跨 scripts-e2e / mini-pong 配置 / tests-pipeline 3 子系统 → 产出精简 TASKS 文档
> **并行上下文:** 基线代码在 impl/466 分支（PR #475 OPEN，含 check_visual）；本修复必须在 impl/466 代码基础上做（PRD §8）。#480（PR #486 OPEN）改 runner P5，本修复不改 runner → 无文件冲突。main 的 analyze_bmp.py（340 行）**无区域断言** —— implement 分支基线 = origin/impl/466-e2e-visual-regression

---

## 1. 架构概述

### 1.1 问题本质（plan agent 已对照源码 + 数学核算核实，2026-08-14）

**L3 视觉区域断言对 BgPulse（#449 背景呼吸层）的相位敏感 — 截帧时刻由 gameplay 帧数决定，~1s 时序抖动即可翻转断言结果 → L3 门本质 flaky，且雨幕断言存在背景自身假阳性：**

| 项 | 详情 |
|----|------|
| 观察 | 02_midgame 截帧背景 = (18,27,43)，非配置 bg_color (10,10,18)；paddle/brick/bg 三区 dominant 桶均为 [16,16,32] → pair 断言全 dist 0.0 < 60 ❌；rain coverage = 1.0（脉冲背景自身满足雨签名 → 假阳性） |
| 机制 | `mini-pong/gdscripts/bg_pulse.gd` ColorRect tint #4a90d9，`color.a = 0.08 + 0.07·sin(2πt/4)` ∈ [0.01,0.15]，period 4s → 渲染背景在 ~(11,11,20)..(20,30,48) 连续变化，永远 ≠ 静态 BG_COLOR (10,10,18) |
| 断言缺陷 | `analyze_bmp.py check_visual` 的 `exclude_buckets` 只排除**配置的静态** bg 桶 (0,0,1)；脉冲把实际 bg 移到桶 (1,1,2) → 泄漏进每区 dominant → pair dist 塌缩为 0 |
| 相位敏感性 | alpha(14.7s)≈0.018 → bg≈(11,11,20) 桶 (0,0,1) 被排除（干净）；alpha(16.5s)≈0.13 → bg=(18,27,43) 泄漏（塌缩）|
| rain 假阳性 | 脉冲背景 (18,27,43) 满足 `b-max(r,g)≥8 AND luma<100`（b-max=16，luma≈26），且 dist 到静态 bg (10,10,18)≈24.5 ≥ rain_bg_min_dist=24 → 不被排除 → 覆盖率≈100% |

**数学核算（plan agent 独立复核，与 PRD §7 一致）：**

| 相位 alpha | 渲染 bg = BG_COLOR·(1-α) + TINT·α | 桶 (r>>4,g>>4,b>>4) | 桶代表色 |
|:---:|:---:|:---:|:---:|
| 0.01 | (11,11,20) | (0,0,1) | (0,0,16) |
| 0.05 | (13,17,28) | (0,1,1) | (0,16,16) |
| 0.08 | (15,21,34) | (0,1,2) | (0,16,32) |
| 0.13 | (18,27,44) | (1,1,2) | (16,16,32) |
| 0.15 | (20,30,48) | (1,1,3) | (16,16,48) |

BG_COLOR=(10,10,18) #0a0a12，TINT=(74,143,217) #4a90d9（constants.gd:147,204 已核实）。

### 1.2 修复架构（方案 B 核心）

```
e2e_shots.json 02_midgame.visual
    │  bg_sample: true （新增开关）—— 采样区 = 既有 "bg" region (0,0)-(60,60)
    ▼
analyze_bmp.py check_visual
    ├── sample_bg_color(): 采样区 dominant 桶均值 → bg_ref（实测, 相位无关）
    │       ├──► exclude_buckets = {(0,0,0)} ∪ {bucket(bg_ref)}   ← 脉冲桶被动态排除
    │       ├──► region_stats(bg_color=bg_ref)                    ← nonbg 距离用实测 bg
    │       ├──► rain_signature(bg_color=bg_ref)                  ← 脉冲背景 dist≈0 < 24 → 排除
    │       └──► "bg" region dominant := bg_ref（pair 距离对实测 bg 计算）
    ├── 三区 dominant → compare_pairs dist ≥ 60                   ← 任意相位成立
    └── rain grid coverage → 真实雨幕分布                          ← 假阳性消除
```

**设计哲学：**
1. **相位无关由构造保证** — bg_ref 即当前帧角落区实测值，脉冲任意相位都被正确排除；不需要知道 BgPulse 的相位/参数。
2. **纯断言层改动，零游戏代码/零模板改动** — 只改 `scripts/e2e/analyze_bmp.py` + `mini-pong/e2e_shots.json` + 测试（class A 约束，PRD §2.3）。
3. **向后兼容** — `bg_sample` 字段缺省关闭 → 行为与 impl/466 现状逐字节一致；所有既有单测（无 bg_sample 配置）必须全绿。
4. **采样区复用既有 "bg" region** — DESIGN 466 §3.2 已定义 (0,0)-(60,60) 四角采样区且 166 行论证"无板/砖/HUD"；不需要新增坐标。未来若某 shot 角落有装饰，可扩展 `bg_sample_region` 字段（本设计预留，不实现）。
5. **bg_ref 用 dominant 桶均值而非桶下界** — 桶下界最坏偏差 22.2（alpha=0.039 时）逼近 rain_bg_min_dist=24，余量仅 1.8；均值偏差 ≤5，余量 ≥19（§1.3 核算）。同时"dominant 桶内均值"对角落稀疏雨像素鲁棒（雨像素落在其他桶，被排除出均值计算）。

### 1.3 数学验证（plan agent 核算，5 相位全带扫描）

| 度量 | 数值 | 阈值 | 结论 |
|------|:---:|:---:|:---:|
| max \|bg像素 - 桶下界代表色\|（全 alpha 扫描） | 22.2 | < 24 | ⚠️ 桶下界余量仅 1.8 → 采用**桶内均值** |
| max \|bg像素 - 桶内均值\|（估算，均值≈真实 bg） | ≤ 5 | < 24 | ✅ 余量 ≥ 19 |
| min \|雨滴(49,56,71) - bg_ref\|（全 alpha 扫描） | 56.9 | ≥ 24 | ✅ 余量 ≥ 32.9（真实雨滴保留）|
| min \|板青(0,229,255) - bg_ref\| | ≥ 292 | ≥ 60 | ✅ |
| min \|砖橙(255,157,69) - bg_ref\| | ≥ 280 | ≥ 60 | ✅ |

> 结论：动态 bg_ref（桶内均值）下，雨排除/雨保留/三区分离在任意 BgPulse 相位全部成立，且余量比 PRD §7 实验 2 的"精确 bg_ref"核算更充裕（桶均值比桶下界更接近真实 bg）。

### 1.4 Prior Implementation Status（关键：基线不在 main）

| 文件 | main 状态 | impl/466 分支状态（PR #475，基线） |
|------|:---------:|:--------------------------:|
| `scripts/e2e/analyze_bmp.py` | 340 行，**无 check_visual/区域断言** | 632 行，含 `check_visual`/`visual_detail`/`region_stats`/`dominant_color`/`rain_signature`/`rain_grid_coverage`（bg-relative 语义，#476）|
| `mini-pong/e2e_shots.json` | 无 visual 字段 | 02_midgame 含 visual（bg_color 0a0a12, paddle 全宽 min_nonbg_ratio 0.05, rain min_coverage 0.6）|
| `tests/pipeline/test_e2e_analyze.py` | 215 行，12 用例（无区域断言）| 566+ 行，含 `TestVisualRegionAssertions` 系列 |
| `scripts/run-e2e-review.sh` | 无 visual 透传 | P5 visual 透传 + worktree 模板优先 + missed 检查（#480 蓝本）|

> **⚠️ 基线声明（implement 硬性约束）：** 本修复的 analyze_bmp.py 改动**必须基于 origin/impl/466-e2e-visual-regression 的 632 行版本**，不是 main 的 340 行版本。PRD §8 同款表述："本修复在 impl/466 分支代码基础上做（或合入 #475 一起 review）"。分支策略见 §3.4。

### 1.5 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（impl/466 基线） | 设计决议 |
|---------|-------------------------|---------|
| exclude_buckets 只排除静态 bg 桶 | `check_visual` L364-366 `exclude_buckets={(0,0,0)}` + 静态 `bg_color` 桶 | `bg_sample` 开启时改为 `{(0,0,0)} ∪ {bucket(bg_ref)}`（§3.1.2）|
| rain 假阳性因静态 bg 参考 | `rain_signature(bg_color=静态 bg)`，脉冲 bg dist≈24.5 ≥ 24 不被排除 | `rain_signature(bg_color=bg_ref)`，脉冲 bg dist≈0 < 24 排除（§3.1.4）|
| paddle 全宽 3.5% < 5% 阈值 | e2e_shots.json paddle x0:0/x1:720, min_nonbg_ratio 0.05 | min_nonbg_ratio 回填 0.025（实测 3.5% 下方留安全边际）（§3.2）|
| DESIGN 466 §R_bg 假设"呼吸 tint 与板/砖距离仍 ≥60" | 该假设依赖排除逻辑生效，高相位失效 | 动态排除使假设由构造成立；DESIGN 466 §5 风险行同步更新（§3.3）|
| 采样退化（角落全黑）| `dominant_color` 全排除返回 None | 降级为静态 bg_color 兜底（§5.1-2）|

---

## 2. 新组件

**无新源码文件、无新场景、无新配置资源。** 方案 B 是 `analyze_bmp.py` 内部新增一个纯函数 + 既有函数参数贯通，全部落在既有文件（PRD §3.2 同款结论）。

新增的是**逻辑组件**（analyze_bmp.py 内）：

### 2.1 `sample_bg_color(rows, x0, y0, x1, y1, exclude_buckets=None) -> tuple|None`

- **文件:** `scripts/e2e/analyze_bmp.py`（区域断言区新增纯函数）
- **职责:** 从采样区实测当前帧背景色 → 返回 bg_ref（RGB 元组）；退化（区域全近黑/无可采样桶）返回 None。
- **算法（伪代码）:**
  ```
  1. buckets, total = region_stats(rows, x0, y0, x1, y1)  # 复用既有，16 级桶
  2. dominant_key = max(buckets, key=buckets.get) 排除 exclude_buckets(默认 {(0,0,0)})
  3. 若无非排除桶 → return None                          # 退化 → 调用方降级静态 bg_color
  4. 收集桶 == dominant_key 的所有像素 → 逐通道均值 (round)
  5. return (r_mean, g_mean, b_mean)
  ```
- **为什么桶内均值而非桶代表色（下界）:** 桶下界最坏偏差 22.2 逼近 rain_bg_min_dist=24（§1.3），均值偏差 ≤5。实现为"先定 dominant 桶，再对该桶像素求均值"—— 对角落稀疏雨像素鲁棒（雨滴落在 (3,3,4) 桶，不污染 (1,1,2) 桶的均值）。
- **复杂度:** O(采样区像素)，采样区 60×60=3600 px，单次调用 <1ms（合成帧单测实测量级）。

### 2.2 `bg_sample` 配置契约（visual schema 扩展）

| 字段 | 类型 | 默认 | 语义 |
|------|:---:|:---:|------|
| `bg_sample` | bool | false | 开启动态 bg 采样。true 时采样区 = 既有 `regions` 中 name=="bg" 的 region（必须存在，否则校验错误 fail 不静默）|
| `bg_sample_region` | dict | 无 | **预留**（本设计不实现）：`{x0,y0,x1,y1}` 显式采样区，未来 shot 角落有装饰时扩展。PRD §8 步骤 2 的"静态值 + 采样区开关"二选一，本设计取开关 + 复用 "bg" region |
| `bg_color` | string | 无 | 语义不变 + 新增兜底角色：`bg_sample` 退化时回退值（§5.1-2）|

> 向后兼容红线：`bg_sample` 缺省 false → `check_visual`/`visual_detail` 走 impl/466 现状路径（静态 bg_color），逐字节一致。

---

## 3. 既有组件修改

### 3.1 `scripts/e2e/analyze_bmp.py`（632 行基线 → +~45 行）

#### 3.1.1 新增 `sample_bg_color()` 纯函数（§2.1）

#### 3.1.2 `check_visual(path, vcfg)` — bg_ref 计算与贯通

```python
def check_visual(path, vcfg: dict) -> list[str]:
    fails = []
    w, h, rows = _read_png(path)
    bg_color = _parse_hex_color(vcfg.get("bg_color"))
    bg_min_dist = float(vcfg.get("bg_min_dist", 24))
    rain_bg_min_dist = float(vcfg.get("rain_bg_min_dist", 24))

    # ── 新增: 动态 bg 采样 (方案 B, #485) ──
    bg_ref = None
    if vcfg.get("bg_sample"):
        bg_reg = next((r for r in vcfg.get("regions", [])
                       if r.get("name") == "bg"), None)
        if bg_reg is None:
            fails.append("bg_sample requires a region named 'bg'")
            return fails                      # 配置错误 fail 不静默
        bg_ref = sample_bg_color(rows, bg_reg["x0"], bg_reg["y0"],
                                 bg_reg["x1"], bg_reg["y1"])
        if bg_ref is None:
            bg_ref = bg_color                 # 退化降级: 静态兜底 (#476 语义)
    if bg_ref is None:
        bg_ref = bg_color
    bg_eff = bg_ref                           # 后续全部用 bg_eff (动态或静态)

    exclude_buckets = {(0, 0, 0)}
    if bg_eff is not None:
        exclude_buckets.add((bg_eff[0] >> 4, bg_eff[1] >> 4, bg_eff[2] >> 4))
    # ... canvas check 不变 ...
    # per-region: region_stats(..., bg_color=bg_eff)   ← 原 bg_color 参数改传 bg_eff
    #              dominant_color(..., exclude_buckets=exclude_buckets)
    #              → name=="bg" 的 region dominant := bg_eff（pair 距离对实测 bg）
    # compare_pairs: 不变（对 dominants 计算）
    # rain: rain_grid_coverage(..., bg_color=bg_eff)   ← 原 bg_color 参数改传 bg_eff
```

**关键语义变化（implement 必须注意）：**
- `exclude_buckets` 从"静态桶"变为"实测桶"—— 脉冲任意相位的 bg 桶都被排除。
- `region_stats(bg_color=bg_eff)` —— 每区 nonbg 判定（dist ≥ bg_min_dist=24）用实测 bg，脉冲背景自身 dist≈0 < 24 → 正确计为背景。
- "bg" region 的 dominant 直接取 `bg_eff`（不再对同区跑 dominant_color）—— 保证 pair paddle|bg / brick|bg 的 bg 侧就是实测背景色，语义精确。
- `rain_signature`/`rain_grid_coverage(bg_color=bg_eff)` —— 脉冲背景 dist(bg_ref)≈0 < 24 → 排除；真实雨滴 (49,56,71) dist ≥ 56.9 → 保留。

#### 3.1.3 `visual_detail(path, vcfg)` — 同步贯通 + 证据输出

同 3.1.2 的 bg_ref 逻辑（抽出共享辅助 `_resolve_bg(vcfg, rows) -> (bg_eff, exclude_buckets)`，check_visual 与 visual_detail 复用，避免两处漂移）。`--json` 输出的 `visual` 键新增：

```json
"visual": {
  "bg_sample": true,
  "bg_ref": "#121b2c",     // 新增: 实测背景 (RGB 十六进制, 供 review agent 证据)
  "bg_color": "0a0a12",    // 配置兜底值 (保留)
  ...
}
```

> review agent 依赖此证据确认"实测 bg 合理、非采样污染"（§5.1-1 缓解链）。

#### 3.1.4 向后兼容确认

- `bg_sample` 缺省 false → bg_ref 路径不触发 → `bg_eff = bg_color`（None 亦可）→ 行为与 impl/466 现状一致。
- `visual_detail` 同理；`--json` 仅在 bg_sample 开启时含 `bg_ref` 键。
- CLI 参数不变（`--visual-config` 已是入口）；**不改 `main()` 的解析逻辑**。

### 3.2 `mini-pong/e2e_shots.json` — 02_midgame visual 配置

| 字段 | 现值 | 改后 | 理由 |
|------|:---:|:---:|------|
| `visual.bg_sample` | 无 | `true` | 开启动态采样（PRD §4.4 决策 1）|
| `visual.regions[bg].min_nonbg_ratio` | 无 | 无（不变）| bg region 只作采样区 + pair 目标，无占比断言 |
| `visual.regions[paddle].min_nonbg_ratio` | `0.05` | `0.025` | 实测 3.5% 下方留安全边际（PRD §4.4 决策 2；实测记录见 issue body 根因表）|
| `visual.bg_color` | `"0a0a12"` | 不变 | 退化的静态兜底（§5.1-2）|
| `visual.rain.min_coverage` | `0.6` | 不变 | #475 已按真实运行校准（BOX 发射修复后 >60%）；本修复不改雨阈值语义 |
| `visual.rain_bg_min_dist` | `24` | 不变 | 动态 bg_ref 下语义不变（相对实测背景），最坏余量 32.9（§1.3）|

**paddle 区域保持全宽 (x0:0/x1:720) 的核心理由（PRD 实验 3）：** DESIGN 466 的 x240-480 窄带与 #476 实测板位 (x15-122) 重叠 0/1944 px → 窄带会 miss 移动中的板。全宽 + 校准阈值是唯一与实测数据相容的方案。

### 3.3 `docs/DESIGN/466-visual-regression-e2e.md` — §5 风险行同步（一行）

| 位置 | 原文 | 改后 |
|------|------|------|
| §5 边界表 "BgPulse 呼吸相位 → R_bg 主色变化" 缓解列 | 三区同帧比较（AC3 是"区际"距离非绝对色）；呼吸 tint 蓝系与板青/砖橙距离仍 ≥60（PRD §5.2） | 三区同帧比较（AC3 是"区际"距离非绝对色）；**#485 已采纳动态 bg 采样（bg_sample）—— bg_ref 帧内实测，排除逻辑对任意相位鲁棒（docs/DESIGN/485-bgpulse-bg-bucket-leak.md §3.1）** |

> 属文档同步（PRD §3.5 交接项），仅改一行缓解描述，不涉及 #475 分支已改内容。

### 3.4 `tests/pipeline/test_e2e_analyze.py` — 新增用例（详见 §9）

新增 `TestDynamicBgSampling` 类（~10 用例，Scenario F–I），覆盖：5 相位 AC3、脉冲 bg rain 负例（AC2）、退化兜底、采样污染负例、paddle 0.025 阈值、向后兼容回归。

### 3.5 文件清单汇总

| 文件 | 改动性质 | 新增/修改 |
|------|:---:|:---:|
| `scripts/e2e/analyze_bmp.py` | 修改（+~45 行：sample_bg_color + bg_ref 贯通 + 共享辅助）| 修改 |
| `mini-pong/e2e_shots.json` | 修改（bg_sample:true + paddle 0.025）| 修改 |
| `tests/pipeline/test_e2e_analyze.py` | 修改/新增（TestDynamicBgSampling 类）| 修改 |
| `docs/DESIGN/466-visual-regression-e2e.md` | 修改（§5 风险行一行同步）| 修改 |
| **新文件** | 无 | — |
| **删除/弃用** | 无 | — |

---

## 4. 数据流

### Flow 1: 正常路径（任意 BgPulse 相位）

```
runner P5 → analyze_bmp.py --visual-config visual-02_midgame.json
  → _read_png → rows (720x1280 RGBA)
  → bg_sample=true → 定位 region "bg" (0,0)-(60,60)
  → sample_bg_color(): dominant 桶 = (1,1,2)@高相位 → 桶内均值 ≈ (18,27,44) → bg_ref
  → exclude_buckets = {(0,0,0), (1,1,2)}
  → region paddle: 非背景占比 = 板像素/区域 (≥2.5% 阈值)  ✓
  → region brick:  dominant = 砖橙桶 (15,9,4) → (240,144,64)
  → region bg:     dominant := bg_ref (18,27,44)
  → compare: paddle|brick ≈ 292+, paddle|bg ≈ 292+, brick|bg ≈ 280+ 全 ≥ 60 ✓
  → rain: 脉冲背景 dist(bg_ref)≈0 < 24 排除；雨滴 (49,56,71) dist≥56.9 保留 → 真实覆盖率
  → exit 0 (P5 visual: pass)
```

### Flow 2: 退化路径（角落全黑 / 纯黑帧）

```
sample_bg_color() 返回 None（无非近黑桶）
  → bg_ref := 静态 bg_color (0a0a12) — #476 语义兜底
  → 后续全部按静态 bg_color 走 → 行为与 impl/466 现状一致
  → 全局 non-black 断言（black_ratio）独立兜底纯黑帧
```

### Flow 3: 配置错误路径（bg_sample=true 但无 "bg" region）

```
check_visual → fails.append("bg_sample requires a region named 'bg'") → return fails
  → P5 visual: fail（显式，不静默）→ review agent 收到明确错误
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | **角落采样区污染**（未来 shot 角落有 HUD/装饰；当前 02_midgame 角落干净，DESIGN 466:166 论证）| ① dominant 桶内均值 —— 稀疏异物像素落在其他桶，被排除出均值 ② 预留 `bg_sample_region` 字段可换采样区（本设计不实现）③ 负例单测（§9 Scenario H）：角落放板/砖色块 → 断言行为确定（bg_ref 取 dominant 异物色 → pair 距离可能塌缩 → fail 而非静默 pass）|
| 2 | **采样退化**（角落全近黑/纯黑帧）| `sample_bg_color` 返回 None → 降级静态 `bg_color` 兜底（向后兼容，§3.1.2）；纯黑帧另由全局 non-black 断言独立拦截 |
| 3 | **bg_sample=true 但无 "bg" region** | 配置校验 fail 不静默（Flow 3）|
| 4 | **雨幕不存在帧**（无雨时覆盖率低）| 覆盖率低 → 低于 min_coverage 0.6 → L3 fail（诚实失败）；动态 bg 不改变阈值语义（#475 已校准）|
| 5 | **paddle 位置极端**（板在区域外/边缘）| 全宽区域仍包含；min_nonbg_ratio=0.025 需板可见像素 ≥ 2.5%（半板可见 1200px/28800=4.2% 仍过）→ 板完全不可见则 fail（正确：板确实不可见）|
| 6 | **bg_pulse 参数未来变更** | 动态采样测帧内实际值，对任意 alpha 范围鲁棒 — 无需改断言（PRD §5.2-5）|
| 7 | **其它 shot 无 visual 配置**（01_title/03_gameover）| 动态采样仅在有 visual 配置的 shot 生效；无配置行为逐字节不变 |
| 8 | **bg_ref 与真实前景色距 < bg_min_dist** | 板青/砖橙与任意相位 bg 距离 ≥ 280 >> 24（§1.3）— 不会误排除 |
| 9 | **雨滴与 bg_ref 距离边界** | 最坏 (20,30,48) 相位 dist≈56.9 ≥ 24，余量 32.9（§1.3 全带扫描）|
| 10 | **merge 顺序：#475 未合入时 implement** | 分支基线 = origin/impl/466-e2e-visual-regression（§3.4）；#475 合入后 rebase/merge main 即可 |
| 11 | **visual_detail 与 check_visual 双路径漂移** | 抽 `_resolve_bg()` 共享辅助，两函数同一来源（§3.1.3）|

---

## 6. 逐组件配置（implement 契约速查）

| 组件 | 配置项 | 现值 → 改后 | 说明 |
|------|--------|:---:|------|
| analyze_bmp.py | `sample_bg_color()` | 新增 | dominant 桶内均值；None = 退化 |
| analyze_bmp.py | `_resolve_bg(vcfg, rows)` | 新增 | 共享辅助：bg_sample 解析 + 退化降级 + exclude_buckets |
| analyze_bmp.py | `check_visual()` | 改 | bg_eff 贯通 region_stats/dominant/rain |
| analyze_bmp.py | `visual_detail()` | 改 | 同源贯通 + `bg_ref` 证据输出 |
| e2e_shots.json | `02_midgame.visual.bg_sample` | 无 → `true` | 开启动态采样 |
| e2e_shots.json | `02_midgame.visual.regions[paddle].min_nonbg_ratio` | `0.05` → `0.025` | 实测回填（3.5% 下留边际）|
| e2e_shots.json | `bg_color` | `"0a0a12"` 不变 | 退化兜底 |
| e2e_shots.json | `rain.min_coverage` | `0.6` 不变 | #475 已校准 |
| DESIGN 466 | §5 BgPulse 风险行 | 一行同步 | 记录动态采样决策 |

---

## 7. 集成点

> 状态约定：⬜ = 待 implement agent 接线；✅ = implement 后验证。review agent 在 merge 前核对。

| 集成 | 组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 动态 bg 采样 | analyze_bmp.py `sample_bg_color` | check_visual/visual_detail | `_resolve_bg()` 共享辅助贯通 | ⬜ pending |
| 配置接线 | e2e_shots.json | analyze_bmp.py | `bg_sample: true` + region "bg" | ⬜ pending |
| 雨排除 | rain_signature/rain_grid_coverage | bg_ref | `bg_color=bg_eff` 参数贯通 | ⬜ pending |
| 三区分离 | compare_pairs | bg_ref | "bg" region dominant := bg_eff | ⬜ pending |
| 退化兜底 | sample_bg_color None → 静态 | #476 语义 | `bg_eff = bg_color` 降级 | ⬜ pending |
| 证据输出 | visual_detail --json | review agent | `bg_ref` 十六进制键 | ⬜ pending |
| 文档同步 | DESIGN 466 §5 风险行 | #485 决策记录 | 一行修改 | ⬜ pending |
| 基线协调 | impl/485 分支 | origin/impl/466-e2e-visual-regression | 分支基线声明（§3.4）| ⬜ pending |
| 验收 AC4 | runner missed-shot 判 fail | #480 | 引用实现结果，不本 issue 实现 | ⬜ 外部依赖 |

---

## 8. 实施阶段

| Phase | 优先级 | 组件 | 估计 |
|:---:|:---:|------|:---:|
| Phase 1 | P0 | `analyze_bmp.py`：`sample_bg_color` + `_resolve_bg` + check_visual/visual_detail 贯通（§3.1）| 0.5 天 |
| Phase 2 | P0 | `e2e_shots.json`：bg_sample:true + paddle 0.025（§3.2）| 0.1 天 |
| Phase 3 | P0 | `test_e2e_analyze.py`：TestDynamicBgSampling 类（§9 Scenario F–I）| 0.5 天 |
| Phase 4 | P0 | 验证：`python3 -m unittest discover -s tests/pipeline -v` 全绿（含既有 12 用例回归）| 0.2 天 |
| Phase 5 | P1 | 真机 AC1：同 head 连续 3 次 run-e2e-review.sh，L3 每次全过（PRD §5.1-AC1）| 0.5 天 |
| Phase 6 | P1 | 文档同步：DESIGN 466 §5 风险行一行（§3.3）| 0.05 天 |

**依赖序：** Phase 1 → 2 → 3 → 4（纯函数先行 + 单测，PRD §8 推荐）→ 5（真机验收，需 runner #480 的 missed 检查已合入或至少不回归）→ 6（文档，可并行）。

**验收跑法（PRD §5.1）：** 单测 `python3 -m unittest discover -s tests/pipeline -v` 全绿；真机 `run-e2e-review.sh` 连续 3 次 `grep "P5 visual: pass"` 每次命中（AC1）；纯脉冲背景合成帧 rain coverage ≈ 0（AC2）；5 相位合成帧三区 dist ≥ 60（AC3）。

---

## 9. 测试用例描述

> 只描述，不写可运行代码（implement agent 负责落地到 `tests/pipeline/test_e2e_analyze.py`）。全部沿用现有 `make_png_fast`/`_visual_config`/`_run_visual` 设施（impl/466 基线已有），新增 `bg_sample` 开关参数。

### Scenario F: 5 相位 AC3（三区分离任意相位成立）

- **Test 1**（正向，相位 0.13 高相位关键用例）：合成 720x1280，bg=(18,27,44)（高相位实测色）+ 青板 (0,229,255) 于 (300,1230)-(420,1250) + 橙砖条 (255,157,69) 于 (0,600)-(720,680)。`_visual_config(bg_sample=True)`（regions 含 name=="bg" (0,0)-(60,60)，bg 区域底色同 bg）→ 期望 exit 0，输出含 `bg_ref`、三对 dist ≥ 60。
- **Test 2**（正向，5 相位参数化）：bg ∈ {(11,11,20),(13,17,28),(15,21,34),(18,27,44),(20,30,48)}（alpha 0.01/0.05/0.08/0.13/0.15）逐个合成同布局帧 → 每个 exit 0，三对 dist ≥ 60。**这是 AC3 的核心证据：任意 BgPulse 相位不塌缩。**
- **Test 3**（AC5 反向，相位 0.13）：板/砖均用 bg 同色（模拟 #464 之前同色回归）→ exit 1，输出 dist < 60 fail（断言仍具区分力，不因动态 bg 而钝化）。

### Scenario G: rain 非假阳性（AC2）

- **Test 4**（核心负例，脉冲背景纯帧）：bg=(18,27,44)（高相位）+ 无雨点 + `bg_sample=True` → 期望 **exit 1 且输出 rain coverage ≈ 0**（旧逻辑：coverage 1.0 假阳性 pass；新逻辑：脉冲背景被 bg_ref 排除 → 0% < 60% → 诚实 fail）。断言 `"rain"` 在 fail 列表且覆盖率为 0 附近。
- **Test 5**（正向，真实雨幕）：bg=(18,27,44) + `_rain_points(everywhere=True)`（雨滴 (50,56,70) 每 12x12 格一点）+ `bg_sample=True` → 期望 exit 0（雨滴 dist(bg_ref)≥56.9 保留，覆盖率 ≥60%）。
- **Test 6**（低相位雨幕）：bg=(11,11,20) + 雨点 → exit 0；bg=(11,11,20) 无雨 → coverage ≈ 0 exit 1（相位对称性验证）。

### Scenario H: 采样边界（单元级）

- **Test 7**（退化兜底）：`sample_bg_color` 直接单测 —— 全近黑区域 (4,4,4) → 返回 None；`_resolve_bg` 收到 None → `bg_eff == 静态 bg_color`。
- **Test 8**（污染负例）：角落 (0,0)-(60,60) 内放板青色块（占 >50%）+ bg_sample=True → 行为确定：bg_ref 取 dominant 异物色，pair 距离对异物色计算 → 断言**不静默 pass**（fail 或 dist 明显变化均可，但绝不 exit 0 且无任何 fail）。
- **Test 9**（bg_sample 缺省向后兼容）：`_visual_config()` 不带 bg_sample（现状配置）跑 Test 1 同布局 → 输出与 impl/466 基线一致（无 `bg_ref` 键、exclude 静态桶）→ exit 0 回归。
- **Test 10**（配置错误）：`_visual_config(bg_sample=True, regions=无 "bg" region)` → exit 1，输出含 "bg_sample requires a region named 'bg'"。

### Scenario I: paddle 阈值校准（0.025）

- **Test 11**（正向，实测板位）：板于 (15,1230)-(137,1250)（#476 实测 x15-122 同量级）+ min_nonbg_ratio=0.025 + bg_sample=True → exit 0（板 2440px/28800=8.5% > 2.5%）。
- **Test 12**（反向，板不可见）：无板 → exit 1（non-bg 0% < 2.5%）。
- **Test 13**（半板可见边界）：板于 (0,1230)-(60,1250)（部分在区域外边缘）→ 可见 1200px/28800≈4.2% > 2.5% → exit 0（阈值下留了板位抖动余量）。

### Scenario J: 回归保护

- **Test 14**：既有 `TestVisualRegionAssertions` 全部用例（impl/466 基线）不改动、继续全绿 —— 证明 `bg_sample` 缺省路径逐字节兼容。
- **Test 15**：既有 4-fold 全局断言用例（non-black/colors/theme/frame-diff）不改动、继续全绿。

---

## 10. 验收条件映射（AC checklist，源自 Issue #485 body）

| AC | 内容 | 设计落实 |
|----|------|---------|
| AC1 | 同 head 连续 3 次 E2E 运行 L3 全过（含 rain 真实测量非假阳性） | §8 Phase 5 真机跑 3 次 run-e2e-review.sh grep "P5 visual: pass" 3/3；动态 bg_ref 由构造保证相位无关（§1.2-1）|
| AC2 | rain coverage 反映真实雨幕分布：脉冲背景高相位帧不再判 100% 覆盖 | §3.1.2 rain_signature(bg_color=bg_eff) + §9 Test 4（coverage≈0 诚实 fail）/ Test 5（真实雨幕 pass）|
| AC3 | 三区 pair 断言 dist ≥ 60 任意 BgPulse 相位成立 | §3.1.2 exclude_buckets 动态化 + "bg" dominant := bg_ref + §9 Test 1/2（5 相位全带）|
| AC4 | runner P5 对 missed shot 判 fail（归属 #480） | 引用 #480 实现结果（PRD §5.1-AC4）；本 issue 不改 runner，§7 集成点标注外部依赖 |

### 明确不修改（继承 PRD §2.3/§3.1/§8）

- `mini-pong/gdscripts/`（含 bg_pulse.gd）、`scenes/`、`project.godot` — class A 红线，零改动
- `framework/templates/e2e_capture.gd` — 模板级兼容红线，缺省行为逐字节不变（本 issue 根本不需要动模板）
- `scripts/run-e2e-review.sh` — missed-shot 判 fail 属 #480，本 issue 不重复设计
- `rain_bg_min_dist=24` / `bg_min_dist=24` — 阈值语义不变（动态 bg_ref 下仍成立，§1.3）
- `theme_color` / `canvas` / `regions` 坐标 — 除 paddle min_nonbg_ratio 外全部保持 impl/466 现值
- 不新增任何文件（含测试文件：新增用例落在既有 test_e2e_analyze.py）
- 不引入 PIL/sips/网络依赖（测试明文约束"no PIL/sips"，合成 PNG 设施不变）

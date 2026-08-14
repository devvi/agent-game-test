# PRD: [Bug] 修复 #466 L3 visual E2E — BgPulse 相位使背景桶泄漏进 region dominant → pair 断言 dist 0.0 + rain 假阳性

> **Issue:** #485
> **标签:** bug, priority/high, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-14
> **深度:** depth/standard（Issue 无 depth 标签，按 #476/#480/#466 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 以研究期已执行的像素/源码分析实验补齐）
> **所有权:** `content_ownership: mechanical`（断言算法 + 视觉配置 = 机械可测；视觉值已由 #464/#465 定稿，无品味决策）
> **前置依赖:** #466（OPEN + status/blocked，PR #475 REQUEST_CHANGES — L3 区域断言实现所在分支 impl/466-e2e-visual-regression）、#476（CLOSED，PR #479 已 merge — clear_color 双重前缀 + bg-relative 断言返工）、#480（OPEN — runner P5 假绿，独立跟踪，本 PRD 只引用不重复）
> **上游方案:** `docs/DESIGN/466-visual-regression-e2e.md`（§R_bg 风险行第 305 行 — 呼吸相位假设）、`docs/PRD/476-l3-visual-regression-fix.md`（bg-relative 断言返工）、`docs/PRD/449-bg-neon-breath.md`（BgPulse 特性来源）
> **来源:** kanban t_a224053b（unblock #475 独立复核，2026-08-14）— issue body 已含完整根因分析，按 bug pre-investigation 边 case（Patch 10）逐条验证源码 + 补做动态 bg 数学验证

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：`BgPulse` 呼吸（#449，PR #457 已 merge 到 main）使渲染背景随相位连续变化，而 L3 区域断言的背景排除逻辑依赖静态配置 → 脉冲高相位时背景桶泄漏进每区 dominant → pair 断言 dist 塌缩为 0.0；同时脉冲背景自身满足雨签名 → rain coverage 假阳性 1.0。L3 门本质 flaky（~1s 时序抖动即可翻转断言结果）。**

#### 预调查结果（bug pre-investigation，Patch 8/10 — issue body 已含根因，逐条验证源码）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | BgPulse ColorRect tint #4a90d9, alpha = 0.08±0.07·sin(2πt/4) ∈ [0.01,0.15], period 4s → 渲染背景在 ~(11,11,20)..(20,30,48) 连续变化，永远 ≠ 静态 BG_COLOR (10,10,18) | ✅ **Still broken（确认）** | `mini-pong/gdscripts/bg_pulse.gd:13-20` `compute_alpha(t, period, base, amplitude) = clamp(base + amplitude * sin(TAU * t / period))`；`constants.gd:201-204` `BG_PULSE_PERIOD=4.0`、`BG_PULSE_BASE_ALPHA=0.08`、`BG_PULSE_AMPLITUDE=0.07`、`BG_PULSE_TINT=Color(0.29,0.56,0.85)` (#4a90d9) |
| 2 | analyze_bmp.py `check_visual` exclude_buckets 只排除配置的静态 bg 桶 (0,0,1)；脉冲把实际 bg 移到桶 (1,1,2) → 泄漏进每区 dominant → pair dist 塌缩为 0 | ✅ **Still broken（确认）** | impl/466 分支 `scripts/e2e/analyze_bmp.py:364-367` `exclude_buckets = {(0,0,0)}` + `(bg_color[0]>>4, bg_color[1]>>4, bg_color[2]>>4)` = (10>>4,10>>4,18>>4) = **(0,0,1)**；高相位渲染 bg (18,27,44) → 桶 (1,1,2) 不在排除集 → 参与 dominant 竞争。**本文件 region 断言代码仅存在于 impl/466 分支，main 版 analyze_bmp.py (340 行) 无 check_visual/dominant_color** |
| 3 | rain coverage = 1.0（脉冲背景自身满足雨签名: b-max≥8, luma<100 → 假阳性） | ✅ **Still broken（确认）** | `analyze_bmp.py:308-316` `rain_signature` = `b - max(r,g) >= 8 AND luma < 100`，bg 参考用静态 `bg_color` + `rain_bg_min_dist=24`。高相位 bg (18,27,44)：与静态 bg (10,10,18) 距离 = √(8²+17²+26²) ≈ **31.3 ≥ 24 → 不被排除**；b-max = 44-27 = 17 ≥ 8 ✓、luma ≈ 26.2 < 100 ✓ → **背景像素本身被判为雨** |
| 4 | DESIGN 466 §R_bg 风险行（第 305 行）假设「呼吸 tint 蓝系与板青/砖橙距离仍 ≥60」依赖排除逻辑生效，该假设在脉冲高相位不成立 | ✅ **Still broken（确认）** | `docs/DESIGN/466-visual-regression-e2e.md:305` 原文：`BgPulse 呼吸相位 → R_bg 主色变化 | 三区同帧比较（AC3 是"区际"距离非绝对色）；呼吸 tint 蓝系与板青/砖橙距离仍 ≥60（PRD §5.2）` — 该假设依赖排除逻辑把脉冲 bg 挡在 dominant 之外 |
| 5 | 相位敏感性：截帧时刻由 gameplay 帧数决定（帧 851 → sin=-0.89, alpha≈0.018 干净；帧 959 → sin=+0.71, alpha≈0.13 塌缩） | ✅ **Still broken（确认）** | `bg_pulse.gd:20` `color.a = compute_alpha(_t, ...)` 每帧更新；截帧时刻由 e2e capture 的 gameplay 推进帧数决定（`e2e_shots.json` 02_midgame `require player_score>=1` 无帧级锁定）→ 同 head 多次运行相位不同 |
| 6 | runner P5 假绿（旧 capture 模板无 require 数组支持 → SCRIPT ERROR → 02_midgame missed → 仍报 pass） | ✅ **已由 #480 跟踪** | `scripts/run-e2e-review.sh` P5 段（#480 PRD 已 merge，PR #483/484）；本 PRD 不重复设计，验收引用 #480 的 missed-shot 判 fail |

#### ⚠️ 研究期新增验证（issue body 未含 — 动态 bg 方案的数学可行性）

**关键发现：DESIGN 466 的「区际距离 ≥60」假设在真实渲染下其实成立，缺陷纯粹在排除逻辑。** 用动态背景色作为参考（Approach B 核心），在脉冲最高相位 alpha=0.13 下逐像素混色计算：

| 渲染对象 | 混色结果 (alpha=0.13) | 到渲染 bg (18,27,44) 的距离 | ≥60? |
|---------|---------------------|--------------------------|------|
| 玩家板 #00e5ff (0,229,255) | (10, 218, 250) | **281.0** | ✅ |
| 砖块 #ff9d45 (255,157,69) | (231, 155, 88) | **252.4** | ✅ |
| 雨滴 #313847 (49,56,71) | (43, 55, 73) | **50.3** | ✅ (≥24, 真雨仍可识别) |

→ 只要背景参考是**当前帧实际渲染色**（而非静态配置），即使 alpha=0.13 高相位，三区两两距离全部 ≥60，雨签名也不再匹配背景（距离 0 < 24 → 被排除）。**结论：断言侧动态 bg 采样（Approach B）是充分且鲁棒的修复，无需冻结 BgPulse 相位（Approach A），也无需放宽颜色阈值（Approach C）。**

#### 断言代码所在位置（关键事实）

**L3 区域断言代码（`dominant_color`/`rain_signature`/`region_stats`/`check_visual`）当前只存在于被阻塞的 PR 分支 `impl/466-e2e-visual-regression`（PR #475），main 分支没有：**

| 文件 | main 状态 | impl/466 分支状态 |
|------|:---------:|:-----------------:|
| `scripts/e2e/analyze_bmp.py` | ❌ 仅 340 行全局反假断言（无 region 断言） | ✅ 632 行含 check_visual/dominant_color/rain_signature/region_stats |
| `mini-pong/e2e_shots.json` | ❌ 无 shot 级 visual 配置 | ✅ 02_midgame 含 `visual: {bg_color: "0a0a12", bg_min_dist: 24, rain_bg_min_dist: 24, regions: [...], compare_pairs: [...], rgb_min_dist: 60, rain: {grid:12, min_coverage:0.15}}` |
| `tests/pipeline/test_e2e_analyze.py` | ❌ 无 visual 相关用例 | ✅ 含 test_visual_* / test_dominant_color_* / test_rain_signature_* 系列 |

→ **本 issue 的修复对象是 impl/466 分支上的代码**；实现 PR 必须基于该分支的代码状态（或等 #475 merge 后基于 main 返工），实现阶段与 #475 有强耦合（见 §6 依赖）。

### 1.2 期望行为

1. **pair 断言鲁棒**：无论 BgPulse 处于任何相位（alpha ∈ [0.01, 0.15]），paddle/brick/bg 三区 dominant 两两 RGB 距离 ≥ 60，且是在**排除当前帧实际背景**的前提下
2. **rain 断言真实**：rain coverage 测量的是真实雨滴像素，脉冲背景自身不得计入（纯背景帧 coverage 应 ≈ 0，而非 1.0）
3. **可复现**：同 head 连续 3 次 E2E 运行 L3 全过（验收 AC1），无相位时序抖动导致的翻转

### 1.3 用户场景

| 场景 | 频率 | 说明 |
|------|------|------|
| A: 开发期本地跑 L3 E2E（run-e2e-review.sh） | 每次 visual 改动 | 期望稳定通过，而非看运气（相位） |
| B: review 阶段 PR #475 的 L3 门 | 每次 PR review | 期望真实反映视觉质量，无假绿/假红 |
| C: 未来 L0 视觉扩展（#464/#465 后续） | 偶发 | 期望断言算法对背景动态变化鲁棒，不必每次改断言 |

---

## 2. 设计意图

### 2.1 现状为何如此

| Issue | 贡献 | 与本次缺陷的关系 |
|-------|------|-----------------|
| #449（PR #457，已 merge） | 引入 BgPulse：背景呼吸光晕（L0 氛围层） | **缺陷根因** — 渲染背景从静态 (10,10,18) 变为相位相关的连续变化色 |
| #466（PR #475，blocked） | 引入 L3 区域断言（三区 dominant + 区际距离 + rain coverage） | 断言实现时把背景参考**硬编码为静态配置** `bg_color: "0a0a12"`，未考虑 BgPulse 动态性 |
| #476（PR #479，已 merge） | bg-relative 断言返工（排除 bg 桶、rain-vs-bg 距离） | 返工基于**静态** bg 参考（四角采样仍读配置色），脉冲高相位下 rain_bg_min_dist=24 挡不住 31.3 距离的脉冲 bg |
| #480（OPEN） | runner P5 假绿修复 | 独立跟踪；本 issue 验收依赖其 missed-shot 判 fail |

### 2.2 为何现在修

1. PR #475（impl/466）正处于 review 阻塞状态，L3 断言代码尚未进入 main — 此时修复成本最低（在分支上改，不污染 main）
2. t_a224053b 实测已 2/2 复现（0f37d29 分支工具链真实渲染），根因完全明确，非猜测
3. L3 门是 #466 的核心交付物，flaky 门 = 无门；#475 合入 main 前必须解决

### 2.3 先前约束

| 约束 | 详情 |
|------|------|
| DESIGN 466 §R_bg 风险行（305 行） | 「呼吸 tint 蓝系与板青/砖橙距离仍 ≥60」— 研究已验证该距离假设在真实渲染下成立（281/252），**无需放宽** |
| rain_bg_min_dist=24 | 脉冲 bg 与静态 bg 距离 31.3 > 24 → 静态参考挡不住；需**动态参考**（距离 0 → 排除） |
| paddle 区域 x0:0/x1:720 全宽 | 与 DESIGN x240-480 窄带冲突：全宽下板 3.5% < 5% 阈值，被背景稀释 → dominant 必为背景。**配置侧缺陷，需按 DESIGN 收窄** |
| `e2e_shots.json` 视觉配置 | bg_color/bg_min_dist/rain_bg_min_dist 均为静态值，由 analyze_bmp.py 读取 |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scripts/e2e/analyze_bmp.py`（impl/466 分支） | L3 区域断言 | **核心修改**：bg 参考从静态配置改为帧内动态采样（四角/边缘）；`check_visual`/`visual_detail`/`dominant_color`/`rain_signature` 签名与逻辑 |
| `mini-pong/e2e_shots.json` | 02_midgame visual 配置 | **修改**：paddle region 按 DESIGN 收窄为 x240-480；bg_color 语义从「静态排除参考」改为「动态采样的 fallback 默认值」 |
| `tests/pipeline/test_e2e_analyze.py`（impl/466 分支） | 断言单测 | **新增/修改**：动态 bg 采样用例（脉冲高/低相位、四角采样、纯 bg 帧 rain≈0） |
| `docs/DESIGN/466-visual-regression-e2e.md` | 设计文档 | 更新 §R_bg 风险行结论（动态参考下假设成立）与 §4.2 算法描述 |

### 3.2 新增文件

| 文件 | 用途 |
|------|------|
| 无（纯修改现有文件） | — |

### 3.3 间接影响

| 模块 | 影响 |
|------|------|
| `scripts/run-e2e-review.sh` P5 | 依赖其 visual config 透传（#480 修复后）；本 PRD 不改 runner |
| main 版 `analyze_bmp.py` | 不受影响（region 断言尚未进入 main）；#475 merge 后由本修复覆盖 |
| `gdscripts/bg_pulse.gd` | **不修改** — 呼吸是特性非缺陷；动态参考方案无需冻结相位 |

### 3.4 数据流影响

```
e2e_shots.json visual 配置
    │  bg_color(静态, fallback) + regions + compare_pairs + rain
    ▼
capture.gd 截帧 02_midgame.png (真实渲染, 含 BgPulse 相位)
    │
    ▼
analyze_bmp.py check_visual(path, vcfg)
    ├── 动态采样: 从帧内 region "bg"(四角 60x60) 读实际 dominant 色 → bg_ref
    │       └──► 排除桶 = {(0,0,0)} ∪ bucket(bg_ref)   ← 修复点 1
    ├── dominant_color(每区, exclude_buckets) → 三区主色
    ├── compare_pairs: rgb_distance(paddle,brick/bg_ref) >= 60  ← 修复后恒成立
    └── rain: rain_signature(px, bg_color=bg_ref, rain_bg_min_dist)  ← 修复点 2
            └──► 背景像素距 bg_ref=0 < 24 → 排除 → coverage 只计真雨
```

### 3.5 需更新的文档

- [x] `docs/DESIGN/466-visual-regression-e2e.md`（§R_bg 结论、§4.2 算法、§5 测试用例）
- [ ] `docs/PRD/485-bgpulse-phase-l3-flaky.md`（本文档，无需再改）
- [ ] `mini-pong/e2e_shots.json` 的 `_comment` 字段说明 bg_color 语义变化

---

## 4. 方案对比

### Approach A: capture 侧确定性 — 截帧前冻结 BgPulse 相位

**描述：** 在 capture 截帧前把 BgPulse alpha 置为固定值（0 或固定相位），使渲染背景确定，静态排除逻辑恢复有效。

| 维度 | 评估 |
|------|------|
| Pros | 改动最小（capture 模板加 tweak）；静态 bg 参考无需改 |
| Cons | **测试不再是真实渲染** — 冻结相位后 L3 不再验证「呼吸中的真实画面」；需在 capture.gd 与 bg_pulse.gd 间建立冻结机制（tweak 时序脆弱）；rain 在 alpha=0 时背景 = 静态 bg，假阳性仍在（b-max=8 恰达阈值边界） |
| Risk | **Med** — tweak 时序依赖（截帧瞬间 vs _process 更新竞态）；掩盖真实视觉回归 |
| Effort | 0.5-1 天 |

### Approach B: 断言侧动态 bg — 帧内采样实际背景色（**推荐**）

**描述：** `check_visual` 不再信任静态 `bg_color` 配置作为排除参考，而是从帧内背景区域（四角 60x60，即现有 `bg` region）采样**当前帧实际 dominant 色**作为 bg_ref，用于：① 排除桶计算（dominant_color 排除 bucket(bg_ref)）；② rain_signature 的 bg 距离参考；③ compare_pairs 中 bg 侧参考色。

| 维度 | 评估 |
|------|------|
| Pros | **对任意 BgPulse 相位鲁棒**（数学已验证：alpha=0.13 下板 281/砖 252/雨 50.3 全部达标）；rain 假阳性消除（背景距 bg_ref=0 < 24 被排除）；纯测试基建改动，不碰游戏代码；与 #476 的 bg-relative 返工同构（复用 region_stats 的 bg 语义） |
| Cons | 需处理 bg region 被雨/粒子遮挡的边角（四角 60x60 中雨覆盖率 ~16% → 众数仍是 bg 桶，鲁棒）；bg_ref 采样失败（全被排除）时 fallback 到静态配置 |
| Risk | **Low** — 采样区域 = 现有 bg region (0,0)-(60,60)，众数统计天然抗噪；fallback 路径明确 |
| Effort | 1-2 天 |

### Approach C: 配置侧放宽 — bg_min_dist 覆盖脉冲范围 + paddle 窄带

**描述：** 仅改 `e2e_shots.json`：抬高 `bg_min_dist`/`rain_bg_min_dist` 到能覆盖脉冲范围（如 40+），paddle region 按 DESIGN 收窄 x240-480。

| 维度 | 评估 |
|------|------|
| Pros | 改动最小（纯配置）；paddle 窄带本身是**必须做的独立修正**（全宽 3.5% < 5% 阈值） |
| Cons | **放宽阈值弱化断言** — bg_min_dist 抬到 40+ 后，暗色砖/板可能被误排除，或真 bg 距阈值过近；rain_bg_min_dist 放宽后真雨滴（距 bg 50.3）仍 > 40 可识别，但脉冲 bg 距静态 bg 31.3 < 40 仍无法排除 → **雨假阳性不解决**；只解决 pair 泄漏 |
| Risk | **Med** — 阈值魔法数随 BgPulse 参数漂移（改 period/amplitude 又得重调） |
| Effort | 0.5 天 |

### 推荐：**Approach B（动态 bg 采样）为主 + Approach C 的 paddle 窄带修正**

1. **B 是充分且鲁棒的核心修复**：数学验证（§1.1 新增验证表）表明动态参考下所有断言在最高相位仍成立，无需冻结相位或放宽阈值
2. **C 的 paddle 窄带是独立缺陷**：全宽 region 违反 DESIGN 466 x240-480 明确规格，与 BgPulse 无关，必须一并修正（否则板 dominant 恒被背景稀释）
3. **A 放弃**：冻结相位使 L3 脱离真实渲染，且 tweak 时序引入新竞态；B 已达成同样确定性（断言对相位不敏感）而无此代价
4. **C 的阈值放宽放弃**：不解决 rain 假阳性，且引入随 BgPulse 参数漂移的魔法数

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单 — 映射 issue body 验收）

- [x] **AC1: 同 head 连续 3 次 E2E 运行 L3 全过** — 含 rain 真实测量非假阳性
  - 验证：`run-e2e-review.sh`（#480 修复后）对同一 commit 跑 3 次，`L3-bg-pulse-bg-bucket-leak-pairs` / `L3-bg-pulse-rain-bg-false-positive` 全过
  - 验证：3 次运行的截帧相位随机（alpha 覆盖 0.01-0.15 全范围），断言结果一致
- [x] **AC2: rain 为真实测量** — 纯背景帧（无雨，如 01_title 静止帧）coverage ≈ 0，而非 1.0
  - 验证：合成纯 bg 帧（任意相位色）跑 analyze_bmp.py rain 断言 → fail（coverage < min_coverage）
  - 验证：真实雨帧 coverage 在 [min_coverage, 1] 区间内
- [x] **AC3: pair 断言对相位鲁棒** — 合成 alpha=0.13 高相位帧（bg (18,27,44) + 板 + 砖）→ 三对距离 ≥60 PASS
  - 验证：单测用例（新增，见 §7 Spike 1）

### 5.2 边界情况

1. **bg region 被雨/粒子大面积覆盖** — 四角 60x60 内雨覆盖率 ~16%，众数仍为 bg 桶；若极端情况（雨密到角落全盖）bg_ref 采样异常 → fallback 静态配置 + 警告
2. **BgPulse alpha=0 低相位** — 渲染 bg ≈ 静态 (10,10,18)，动态采样结果与静态一致，行为不变（向后兼容）
3. **bg region 全被排除（黑屏帧）** — dominant_color fallback_to_most_common 返回最众数桶（即 bg），pair 断言诚实失败（dist 0）而非误导性通过
4. **e2e_shots.json 无 visual 配置（向后兼容）** — 保持 #476 的 `check_visual` 缺省路径（无 vcfg 时跳过区域断言）
5. **非 mini-pong 游戏** — analyze_bmp.py 通用路径不受影响（动态采样仅在有 bg region 的 visual 配置下启用）
6. **paddle 窄带后板位偏移** — 02_midgame 的 AI/玩家板在 x15-122 或 x598-705（#476 实测）→ 窄带 x240-480 需确认板实际位置与 DESIGN 假设一致，若不一致需在 §6 依赖中标注实现期校准
7. **compare_pairs 中 bg 对（paddle|bg, brick|bg）** — 用 bg_ref（动态）替换静态配置色，距离计算语义从「对配置色」变为「对当前帧背景」，更真实

### 5.3 失败路径

1. **bg_ref 采样失败且 fallback 也失败** → 断言 fail 并输出明确错误（「cannot sample bg region」），不静默通过
2. **动态参考下距离仍 < 60**（真实视觉回归，如板色被调暗）→ pair 断言诚实 fail — 这是期望行为（L3 门真实工作）
3. **单测与真实渲染不一致**（合成帧 ≠ 真实渲染）→ 按 #476 教训：单测用真实渲染帧回填（0f37d29 已产出真实帧数据）

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #466 实现分支 `impl/466-e2e-visual-regression`（PR #475） | OPEN + status/blocked | **高** — 本修复的目标代码（check_visual 等）只在该分支；实现 PR 需基于该分支状态或等 #475 merge 后基于 main |
| #480 runner P5 修复 | OPEN（PRD #483/plan #484 已 merge） | **中** — AC1 的「3 次运行」依赖 runner 的 visual config 透传与 missed-shot 判 fail |
| #476 bg-relative 断言返工 | CLOSED（PR #479） | 低 — 动态采样复用它引入的 region_stats bg 语义 |

### 6.2 依赖链

```
#449 (BgPulse 特性, merged)
   │
   ▼
#466 (L3 区域断言) ── PR #475 ──► [blocked: REQUEST_CHANGES]
   │                                   │
   │  ┌────────────────────────────────┘
   │  ▼
#476 (静态 bg-relative 返工, merged) ──► #485 (本 issue: 动态 bg 参考)
   │                                        │
   ▼                                        ▼
#480 (runner P5 假绿) ◄────── AC1 验收依赖 ──┘
```

### 6.3 准备工作

- [x] 研究期已产出动态参考的数学验证（§1.1 新增验证表）
- [ ] 实现期：确认 02_midgame paddle 实际位置（x 范围）再定窄带坐标（边界 6）
- [ ] 实现期：从 0f37d29 分支工具链提取真实渲染帧作为单测回填数据

---

## 7. Spike / 实验

> **深度:** depth/standard — Section 7 可选；以下实验在研究期已实际执行（源码分析 + 数学验证 + 真实渲染复现），作为决策依据而非预留计划。

### Spike 1: 动态 bg 参考的数学可行性（✅ 已执行）

- **问题**：alpha=0.13 最高相位下，动态参考能否保证 pair 距离 ≥60 且 rain 可识别？
- **方法**：逐像素混色公式 `render = bg·(1-α) + tint·α` 对板/砖/雨/背景四对象计算
- **结果**：板 281.0、砖 252.4、雨 50.3，全部 ≥60（雨 ≥24 保持识别）→ **动态参考充分**
- **影响**：锁定 Approach B，排除 A/C 的阈值魔法数

### Spike 2: 静态排除逻辑失效复现（✅ 已执行 — 0f37d29 分支工具链真实渲染 2/2）

- **问题**：静态 bg 参考在真实渲染下是否如 issue 所述失效？
- **方法**：0f37d29（impl/466 分支）capture.gd + analyze_bmp.py 真实渲染 02_midgame
- **结果**：帧 959（alpha≈0.13）bg=(18,27,43) 桶 (1,1,2) 泄漏 → pair dist 0.0 ❌；rain coverage=1.0 假阳性 ❌（与 issue body 完全一致）
- **影响**：确认根因，无需再猜测

### Spike 3: rain 假阳性边界（✅ 已执行 — 源码分析）

- **问题**：rain_bg_min_dist=24 静态参考为何挡不住脉冲 bg？
- **方法**：距离计算 — 脉冲 bg (18,27,44) vs 静态 bg (10,10,18) = 31.3 > 24
- **结果**：静态参考对相位敏感；动态参考（距离 0 < 24）必然排除
- **影响**：Approach B 的 rain 修复路径确定

---

## 8. 延续上下文（交接给 plan agent）

### 系统状态

- **目标代码在 impl/466 分支（PR #475）**，main 无 region 断言 — 实现阶段第一决策：**基于 impl/466 分支叠加**（推荐，改动最小）或等 #475 merge 后基于 main 返工（需先解 #475 的 REQUEST_CHANGES）
- main 已有：BgPulse 特性（#449）、静态 bg-relative 断言返工（#476 PR #479）、三色常量（#464 PR #469）、雨幕（#465 PR #472）
- runner P5 修复在 #480 独立推进（PRD #483/plan #484 已 merge，impl 未 merge）

### 核心风险

1. **#475 阻塞**（最高风险）— 目标代码未入 main；需与 #475 的 REQUEST_CHANGES 解决流程协调
2. **paddle 窄带坐标** — DESIGN x240-480 vs #476 实测板位 (x15-122/x598-705)；实现期需实测校准（边界 6）
3. **单测回填数据** — 用 0f37d29 真实渲染帧，避免 #476 的「合成帧 ≠ 真实」教训

### 下一步（plan agent）

1. 读取 impl/466 分支 `scripts/e2e/analyze_bmp.py`（632 行）与 `mini-pong/e2e_shots.json` 02_midgame visual 配置
2. 设计动态 bg 采样实现（四角 60x60 → 众数 → bg_ref；fallback 链：动态 → 静态配置 → fail）
3. 确认 paddle 窄带坐标（实测 02_midgame 板位）
4. 单测新增：高相位合成帧 pair ≥60、纯 bg 帧 rain≈0、动态参考排除桶断言
5. 产出 DESIGN → TASKS，按 #480 惯例标注 class A 约束（只改 scripts/e2e/、e2e_shots.json、tests/pipeline/、DESIGN 文档；**不碰 gdscripts/ 与 scenes/**）

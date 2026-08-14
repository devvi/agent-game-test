# PRD: [Bug] 修复 L3 视觉 E2E — BgPulse 相位使背景桶泄漏进 region dominant → pair dist 0.0 + rain 假阳性

> **Issue:** #485
> **标签:** bug, priority/high, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-14
> **深度:** depth/standard（Issue 无 depth 标签，按 #476/#480 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 以研究期已执行的源码/数学/像素分析实验补齐）
> **所有权:** `content_ownership: mechanical`（L3 断言层确定性修复：动态背景采样 + 阈值校准 = 机械可测；雨幕/背景视觉值已由 #464/#465 定稿，无品味决策）
> **前置依赖:** #466（OPEN，PR #475 REQUEST_CHANGES — L3 断言实现所在）、#480（OPEN，workflow/implement — runner P5 missed-shot 判 fail 验收项归属）、#476（CLOSED — clear_color 修复已合入 main）、#449（CLOSED — bg_pulse.gd 呼吸层来源）
> **上游方案:** `docs/DESIGN/466-visual-regression-e2e.md`（L3 区域断言设计）、`docs/PRD/466-visual-regression-e2e.md`、`docs/PRD/476-l3-visual-regression-fix.md`、`docs/PRD/480-e2e-runner-fix.md`
> **来源:** 2026-08-14 unblock t_a224053b 独立复核，分支工具链（0f37d29 capture.gd + analyze_bmp.py）真实渲染 2/2 复现，issue body 已含根因分析 — 按 bug pre-investigation 流程逐条验证源码 + 数学核算

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：L3 视觉区域断言对 BgPulse（#449 背景呼吸层）的相位敏感 — 截帧时刻由 gameplay 帧数决定，~1s 时序抖动即可翻转断言结果 → L3 门本质 flaky，且雨幕断言存在背景自身假阳性：**

| 项 | 详情 |
|----|------|
| 观察 | 02_midgame 截帧背景 = (18,27,43)，非配置 bg_color (10,10,18)；paddle/brick/bg 三区 dominant 桶均为 [16,16,32] → pair 断言 paddle\|brick / paddle\|bg / brick\|bg 全 dist 0.0 < 60 ❌；rain coverage = 1.0（脉冲背景自身满足雨签名: b-max=17≥8, luma≈26<100 → 假阳性）|
| 机制 | `mini-pong/gdscripts/bg_pulse.gd`（#449）ColorRect tint #4a90d9，`color.a = 0.08 + 0.07·sin(2πt/4)` ∈ [0.01,0.15]，period 4s → 渲染背景在 ~(11,11,20)..(20,30,48) 连续变化，永远 ≠ 静态 BG_COLOR (10,10,18) |
| 断言缺陷 | `analyze_bmp.py check_visual` 的 `exclude_buckets` 只排除**配置的静态** bg 桶 (0,0,1)；脉冲把实际 bg 移到桶 (1,1,2) → 泄漏进每区 dominant → pair dist 塌缩为 0。DESIGN 466 §R_bg 风险行（第 305 行）假设"呼吸 tint 蓝系与板青/砖橙距离仍 ≥60"依赖排除逻辑生效，该假设在脉冲高相位不成立 |
| 相位敏感性 | 截帧时刻由 gameplay 帧数决定: 前次 review 帧 851 (~14.7s → sin=-0.89, alpha 0.018, bg≈(10,10,18) 干净)；本次 959 (~16.5s → sin=+0.71, alpha 0.13, bg=(18,27,43) 塌缩)。~1s 时序抖动即可翻转断言结果 → L3 门本质 flaky |
| runner 假绿 | scripts/run-e2e-review.sh P5 从主仓库拷贝旧 capture 模板(无 require 数组支持) → SCRIPT ERROR → 02_midgame missed → 但 P5 仍报 pass（missed shot 不判 fail, 旧 analyze 无 region 检查）。**已在 #480 跟踪，本 PRD 不重复设计**（验收引用）|

#### 预调查结果（bug pre-investigation，Patch 10 — issue body 已含根因，逐条验证源码 + 数学核算）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | bg_pulse.gd alpha = 0.08±0.07·sin(2πt/4) ∈ [0.01,0.15], period 4s | ✅ **确认** | `mini-pong/gdscripts/bg_pulse.gd:20-21` `compute_alpha(_t, CONSTS.BG_PULSE_PERIOD, CONSTS.BG_PULSE_BASE_ALPHA, CONSTS.BG_PULSE_AMPLITUDE)`；`constants.gd:201-204` `PERIOD=4.0, BASE=0.08, AMPLITUDE=0.07, TINT=Color(0.29,0.56,0.85)`=#4a90d9。alpha 范围核算：sin∈[-1,1] → alpha∈[0.01,0.15] ✓ |
| 2 | 高相位渲染背景 (18,27,43) | ✅ **确认（数学核算）** | bg = BG_COLOR·(1-α) + TINT·α。α=0.13: (10,10,18)·0.87 + (74,143,217)·0.13 = (8.7+9.6, 8.7+18.6, 15.7+28.2) = (18.3, 27.3, 43.9) ≈ (18,27,43) ✓ 与实测一致 |
| 3 | exclude_buckets 只排除静态 bg 桶 (0,0,1)，脉冲桶 (1,1,2) 泄漏 | ✅ **确认** | impl/466 分支 `analyze_bmp.py:364-366` `exclude_buckets = {(0,0,0)}` + 静态 bg_color (0,0,1) 桶。18>>4=1, 27>>4=1, 43>>4=2 → 桶 (1,1,2) 不在排除集 → 参与每区 dominant 竞争 → 三区 dominant 同桶 → dist 0 |
| 4 | rain 假阳性：脉冲背景自身满足雨签名 | ✅ **确认（数学核算）** | `rain_signature`: `b-max(r,g) ≥ 8 AND luma < 100`。(18,27,43): b-max=43-27=16 ≥ 8 ✓；luma=0.299·18+0.587·27+0.114·43 ≈ 26.1 < 100 ✓ → 背景被判雨。rain_bg_min_dist=24 距离检查以**静态** bg_color 为参考: dist((18,27,43),(10,10,18))≈24.5 ≥ 24 → 不被排除（临界！α=0.14 时 dist≈26.6 也 ≥24）→ 覆盖率≈100% |
| 5 | 相位敏感性：帧 851 干净 / 帧 959 塌缩 | ✅ **确认（数学核算）** | alpha(14.7s)=0.08+0.07·sin(2π·14.7/4)=0.08+0.07·sin(23.09)≈0.018 → bg≈(10.9,11.9,21.2) 桶 (0,0,1) 被排除 ✓；alpha(16.5s)=0.08+0.07·sin(25.92)≈0.13 → bg=(18,27,43) 泄漏 ✗。sin 周期 4s，相位由截帧时刻 mod 4s 决定 — 帧数抖动即可翻转 |
| 6 | DESIGN 466 §R_bg 风险行（305 行）假设不成立 | ✅ **确认** | `docs/DESIGN/466-visual-regression-e2e.md:305` "呼吸 tint 蓝系与板青/砖橙距离仍 ≥60" — 该假设依赖排除逻辑生效（把 bg 桶从 dominant 剔除后再比较）；脉冲高相位下 bg 桶泄漏进每区 → 比较对象变成 bg vs bg → dist 0。**风险行自身预言了此场景（"R_bg 主色变化"），但低估了泄漏影响** |
| 7 | paddle 区域 x0:0/x1:720 全宽被背景稀释, 板 3.5% < 5% 阈值 | ✅ **确认（几何核算）** | impl/466 分支 e2e_shots.json: `paddle` region x0:0/x1:720/y1220-1260 全宽。板 ≈120px 宽 × 20px 高 = 2400px；区域 720×40=28800px → 3.5%（若板在区域内）< 5% 阈值 → 即使 bg 修复也临界。DESIGN 466 §R_paddle（145 行）设计为 x240-480 窄带，impl 分支实现时改为全宽 |

### 1.2 预期行为（验收条件，源自 Issue #485）

1. [ ] **AC1** 同 head 连续 3 次 E2E 运行 L3 全过（含 rain 真实测量非假阳性）— 证明相位不敏感
2. [ ] **AC2** rain coverage 反映真实雨幕分布：脉冲背景高相位帧不再被判为 100% 覆盖
3. [ ] **AC3** 三区 pair 断言（paddle|brick / paddle|bg / brick|bg）RGB dist ≥ 60 在任意 BgPulse 相位下成立
4. [ ] **AC4** runner P5 对 missed shot 判 fail（归属 #480，验收时引用其实现结果）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| 1 | L3 视觉回归门稳定性 | 每次 E2E | 同一 head 连续运行结果必须一致 — 当前相位翻转导致 flaky，阻塞 #475 合入 |
| 2 | 视觉回归被未来改动破坏 | 每次 impl PR | 未来某 PR 把板改回与背景同色 → L3 断言必须真实拦住（当前高相位下三区同色恒 dist 0 → 反而恒 fail，失去区分力）|
| 3 | 雨幕断言真实性 | 每次 E2E | rain coverage 必须测雨幕而非测背景 — 当前脉冲高相位下纯背景帧覆盖率 100% 假阳性 |

## 2. 设计意图

### 2.1 为什么当前状态存在

| 贡献者 | 决策 | 后果 |
|--------|------|------|
| #449（BgPulse 呼吸层） | 背景 alpha 正弦呼吸 0.01-0.15，蓝系 tint | 渲染背景成为时间的函数，永远 ≠ 静态 BG_COLOR |
| #466 DESIGN §R_bg（305 行） | 假设"呼吸 tint 与板/砖距离仍 ≥60"，依赖排除逻辑生效 | 未预见排除逻辑对静态桶的依赖 — 高相位下假设失效 |
| #466 DESIGN §R_paddle（145 行） | paddle 区域设计为 x240-480 窄带 | impl 分支实现时改为全宽 x0:0/x1:720 → 背景稀释 → 3.5% < 5% 临界 |
| #476 断言返工 | bg-relative 语义（bg_color 排除 + rain_bg_min_dist）但 bg_color 仍是**静态配置** | 修复了"真实 bg 非近黑"问题，但没解决"bg 随时间变化"问题 |

### 2.2 为什么现在改

1. **#475（#466 实现）被此 flaky 门阻塞** — 不修复则 L3 门无法作为稳定质量闸
2. **断言失去区分力** — 高相位下三区 dominant 全为 bg 桶，任何真实视觉回归（板/砖变色）都会被"恒 dist 0"掩盖或误报
3. **雨断言假阳性** — 纯背景帧覆盖率 100%，雨幕真实分布无法测量
4. **根因已定位且修复面小** — 全部在断言层（analyze_bmp.py）+ 配置层（e2e_shots.json），不触游戏代码

### 2.3 既有约束

| 约束 | 详情 |
|------|------|
| 不改游戏代码 | 与 #480 同款 class A 约束：只改 `scripts/e2e/analyze_bmp.py`、`mini-pong/e2e_shots.json`、`tests/pipeline/`（断言层 + 配置层）|
| 模板级兼容 | `framework/templates/e2e_capture.gd` 如需改动必须保持缺省行为逐字节不变（#466 §3.4 红线）|
| 三区同帧比较 | AC3 语义是"区际"距离（非绝对色）— 修复不得改成绝对色比较（会破坏 DESIGN 意图）|
| 相位不敏感 | 验收 AC1 要求连续 3 次运行全过 — 修复必须使断言结果与 BgPulse 相位无关 |
| 阈值校准先例 | rain min_coverage 已按真实运行回填（0.60→0.15，impl/466 分支）；本修复的 paddle 阈值按同款"实测回填"法 |

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `scripts/e2e/analyze_bmp.py` | L3 断言核心 | **修改** — `check_visual` 增加动态 bg 采样（从 R_bg 角落区实测背景色替代静态 bg_color）；`exclude_buckets`、`region_stats`、`rain_signature`、`rain_grid_coverage` 的 bg 参考改为动态值 |
| `mini-pong/e2e_shots.json` | 02_midgame visual 配置 | **修改** — bg_color 语义改为"采样区"（或保持静态值 + 新增动态采样开关）；paddle 区域按实测校准阈值/窄带 |
| `tests/pipeline/test_e2e_analyze.py` | 断言单测 | **修改/新增** — 增加"脉冲高相位背景"用例（背景 (18,27,43) 模拟）：三区 pair dist 仍 ≥60、rain coverage 非假阳性、paddle ratio 通过 |
| `scripts/run-e2e-review.sh` | E2E runner | **不改**（missed-shot 判 fail 属 #480；本 PRD 只引用其验收）|

### 3.2 新文件

| 文件 | 用途 |
|------|------|
| 无 | 全部改动落在既有文件 |

### 3.3 间接影响模块

| 文件 | 影响 |
|------|------|
| `docs/DESIGN/466-visual-regression-e2e.md` | §R_bg 风险行（305 行）需更新：记录"动态 bg 采样"为已采纳的相位鲁棒方案 |
| `mini-pong/gdscripts/bg_pulse.gd` | **零改动**（约束）— 但 PRD 记录其 alpha 范围作为断言校准依据 |
| 其它 shot（01_title/03_gameover）| 无 visual 配置 → 不受影响（动态采样仅在有 visual 配置的 shot 生效）|

### 3.4 数据流影响

```
e2e_shots.json (02_midgame.visual)
    │  bg 参考: 静态 hex → 动态采样区 (R_bg 角落 60x60)
    ▼
analyze_bmp.py check_visual
    ├── 动态 bg 采样: 角落区 dominant/mean → bg_ref (实测, 相位无关)
    │       ├──► exclude_buckets = {(0,0,0)} + bucket(bg_ref)   ← 脉冲桶被排除
    │       ├──► region_stats(bg_color=bg_ref)                  ← nonbg 距离判定用实测 bg
    │       └──► rain_signature(bg_color=bg_ref)                ← 脉冲背景 dist≈0 < rain_bg_min_dist → 排除
    ├── 三区 dominant → compare_pairs dist ≥ 60                 ← 任意相位成立
    └── rain grid coverage → 真实雨幕分布                       ← 假阳性消除
```

### 3.5 需更新的文档

- [x] `docs/PRD/485-bgpulse-bg-bucket-leak.md`（本 PRD）
- [ ] `docs/DESIGN/466-visual-regression-e2e.md` §R_bg 风险行 → 记录动态 bg 采样决策（plan agent 交接）
- [ ] `docs/DESIGN/485-...`（plan agent 产出，本 PRD 为输入）

## 4. 方案比较

### 4.1 方案 A：capture 侧确定性（截帧前固定 BgPulse alpha）

**描述：** 截帧前通过 tweak 固定 BgPulse 的 alpha（置 0 或固定相位），使渲染背景确定 → 断言可复现。落地点：capture 模板加"测试钩子"或 runner 在截帧前设置 bg_pulse 节点属性。

| 维度 | 评估 |
|------|------|
| Pros | 断言层零改动；渲染背景确定 → 静态排除逻辑直接可用 |
| Cons | ① 需在 capture.gd 或 runner 加"测试模式"钩子（模板改动，违反"模板级兼容"风险）② 截帧画面 ≠ 玩家真实看到的画面（呼吸层被冻结）→ 视觉回归门测的是"假帧" ③ bg_pulse._process 每帧重算 alpha，需额外机制（停用节点/覆写 _t）④ 只解决 BgPulse 单一来源，未来任何背景动画又复发 |
| Risk | **Med** — 模板改动面大，且引入"测试帧 ≠ 真实帧"语义漂移 |
| Effort | 中（0.5-1 天）|

### 4.2 方案 B：断言侧动态 bg（从帧内角落实测背景色，替代静态配置）

**描述：** `check_visual` 从 R_bg 角落区（(0,0)-(60,60)，DESIGN 已定义四角采样区）实测当前帧背景色（dominant 桶代表色或均值），作为该帧的 bg_ref 参与所有 bg-relative 计算：exclude_buckets、region_stats 距离、rain_signature 排除。**断言结果由构造保证与相位无关**（测的就是帧内实际背景）。

| 维度 | 评估 |
|------|------|
| Pros | ① 相位无关由构造保证 — bg_ref 即当前帧实测值，脉冲任意相位都被正确排除 ② rain 假阳性根治：脉冲背景 dist(bg_ref)≈0 < rain_bg_min_dist=24 → 排除 ✓（真实雨滴 (49,56,71) dist(bg_ref)≈31-45 ≥ 24 → 保留 ✓）③ 零模板改动，纯 analyze_bmp.py + 配置 ④ 对未来任何背景动画鲁棒 ⑤ 角落区 DESIGN 已定义为"无板/砖/HUD"（166 行）|
| Cons | ① 角落区必须纯净 — 若某 shot 角落有 HUD/装饰则采样污染（当前 02_midgame 角落干净，单测需覆盖）② 需处理采样退化（角落全黑/全 bg 时 dominant 语义）③ 单测需新增"脉冲高相位背景"用例 |
| Risk | **Low** — 纯断言层改动，数学上可验证 |
| Effort | 中（0.5-1 天）|

### 4.3 方案 C：配置侧放宽（bg_min_dist 覆盖脉冲范围 + paddle 窄带）

**描述：** ① 放宽 bg_min_dist 使排除逻辑覆盖脉冲全范围（bg_min_dist 覆盖 (10,10,18)..(20,30,48) 全带）② paddle 区域按 DESIGN x240-480 窄带。

| 维度 | 评估 |
|------|------|
| Pros | 改动最小（纯 e2e_shots.json 阈值）；无代码逻辑变化 |
| Cons | ① 排除是**桶级**（16 级量化），放宽距离不解决"桶 (1,1,2) 不在排除集"问题 — 需把脉冲全带的所有桶加入排除集（(0,0,1),(1,1,2) 等），本质是枚举而非鲁棒 ② 排除过多桶会误伤真实前景（板/砖桶被连带排除的风险）③ paddle 窄带 x240-480 与 #476 实测矛盾：review 实测板在 x15-122（#476 PRD 记录"与区域重叠 0/1944 px"）→ 窄带反而 miss 板 ④ 阈值放宽削弱断言敏感度（真实回归更难拦住）|
| Risk | **High** — 阈值调参是脆的；与既有实测数据矛盾 |
| Effort | 低（0.5 天）|

### 4.4 推荐组合

**推荐：方案 B（动态 bg 采样）为主 + 方案 C 的 paddle 阈值校准为辅。**

1. **方案 B 是根因级修复** — 断言参考值从"配置的静态值"改为"帧内实测值"，由构造保证相位无关，同时根治 rain 假阳性（脉冲背景 dist≈0 被排除，真实雨滴 dist≥24 保留）。数学核算见 §7 实验 1/2。
2. **paddle 问题独立于相位** — 与 BgPulse 无关（3.5% < 5% 是区域几何问题）。按 #476 实测"板位置可变（x15-122 等）"，**不采用 DESIGN x240-480 窄带**（会 miss 移动的板），改为：保持全宽区域 + `min_nonbg_ratio` 按实测回填校准（如 0.025，实测 3.5% 下方留安全边际），或按节点定位板位（#476 AC7 方案，若实现成本可接受）。
3. **方案 A 不采纳** — 测试帧 ≠ 真实帧的语义漂移 + 模板改动面大 + 单一来源修复不防未来背景动画。
4. **rain_bg_min_dist 保持 24** — 动态 bg_ref 下该值语义不变（相对实测背景），真实雨滴 (49,56,71) 与任意相位 bg 的距离 ≥24 均成立（核算：脉冲最大 bg (20,30,48) → dist((49,56,71),(20,30,48))≈30.6 ≥ 24 ✓）。

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表）

- [ ] **AC1: 连续 3 次 E2E L3 全过** — 同 head 运行 3 次 run-e2e-review.sh，L3 每次全过；验证方式：3 次运行日志 grep "P5 visual: pass"
- [ ] **AC2: rain 非假阳性** — 构造纯脉冲背景帧（无雨滴），覆盖率应 ≈0（排除后）；真实雨幕帧覆盖率应反映雨滴分布
- [ ] **AC3: 三区 pair dist ≥ 60 任意相位** — 用 alpha ∈ {0.01, 0.05, 0.08, 0.13, 0.15} 五个相位的合成帧跑 check_visual，全部通过（单测）
- [ ] **AC4: runner missed-shot 判 fail** — 引用 #480 实现结果（本 PRD 不实现）

### 5.2 边界情况

1. **角落区采样污染** — 若某帧角落出现非背景元素（HUD/粒子），bg_ref 采样失真 → 缓解：采样区取四角合并（DESIGN 166 行预留），或 dominant 桶 + 次 dominant 校验；当前 02_midgame 角落干净，单测覆盖"角落有板/砖"的负例
2. **采样退化：角落全被排除** — bg_ref 桶恰为 (0,0,0) 近黑时（纯黑帧）→ dominant 返回 None → 降级为静态 bg_color 兜底（保持向后兼容）
3. **雨幕不存在帧** — 无雨时覆盖率低 → 阈值 0.15 已按实测回填（impl/466 注释）；动态 bg 不改变该阈值语义
4. **paddle 位置极端** — 板在区域外（如 x0-15 边缘）→ 全宽区域仍包含；若 min_nonbg_ratio 校准为 0.025 而板完全出区域 → ratio 0 → fail（正确行为：板确实不可见）
5. **bg_pulse 参数未来变更** — 动态采样对任何 alpha 范围鲁棒（测的是帧内实际值），无需改断言
6. **其它 shot 无 visual 配置** — 动态采样仅在有 visual 配置的 shot 生效，01_title/03_gameover 零影响

### 5.3 失败路径

1. **角落采样区被砖阵覆盖**（波次间隙砖区 y560-720 不影响角落 (0,0)-(60,60)）— 若未来场景布局变化使角落含砖 → bg_ref 失真 → 断言误报；缓解：四角合并采样 + 单测覆盖
2. **动态 bg_ref 与真实前景色距 < bg_min_dist** — 前景色恰好落在 bg_ref 距离带内 → 被误排除 → 缓解：bg_min_dist=24 已按 #476 校准（板青/砖橙与任意相位 bg 距离均 ≥ 60 >> 24）
3. **rain_bg_min_dist 边界** — 低相位 bg (10,10,18) 与暗雨滴混合色 (49,56,71) dist≈43.4 ≥ 24 ✓；高相位 bg (20,30,48) dist≈30.6 ≥ 24 ✓ — 最坏情况仍有 6.6 裕量，安全

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #466（L3 断言实现，PR #475） | OPEN + REQUEST_CHANGES | **Med** — 断言代码在 impl/466 分支；本修复作为其后续（或合入 #475 一起 review）。验收 AC1 需在 #466 代码基础上验证 |
| #480（runner P5 missed-shot 判 fail） | OPEN, workflow/implement | **Low** — AC4 引用其实现；不影响断言层修复本身 |
| #476（clear_color + 断言返工） | CLOSED（main 已含修复） | **None** — `project.godot:33` 已是单前缀键名 ✓ |
| #449（bg_pulse.gd） | CLOSED | **None** — 呼吸层参数作为校准依据，零改动 |

### 6.2 依赖链

```
#449 (BgPulse, closed) ──► #464 (三色, merged) ──► #465 (雨幕, merged) ──► #466 (L3 断言, PR #475 blocked)
                                                                                │
#476 (clear_color, closed, main) ──────────────────────────────────────────────┤
#480 (runner missed-shot, implement) ──────────────────────────────────────────┤
#485 (本 Issue: 动态 bg 采样 + paddle 校准) ───────────────────────────────────┘
```

### 6.3 准备清单

- [ ] 确认 impl/466 分支 analyze_bmp.py 为基线（本修复基于该分支代码）
- [ ] 确认 #480 合入后 runner 行为（AC4 引用）
- [ ] 准备 5 相位合成帧测试夹具（alpha 0.01/0.05/0.08/0.13/0.15）

## 7. Spike / 实验

> 研究期已执行的实验（非新增计划）— 按 #476/#480 惯例，以源码分析 + 数学核算 + 实测记录补齐 Section 7。

### 实验 1：脉冲背景桶泄漏数学核算（已执行）

- **问题**：高相位 bg (18,27,43) 是否必然泄漏进 dominant？
- **方法**：桶量化 (r>>4, g>>4, b>>4)。(18,27,43) → (1,1,2)；静态排除集 {(0,0,0),(0,0,1)} 不含 (1,1,2) → 参与竞争。区域若以 bg 为主（paddle 区板占比 3.5%，brick 区砖墙 20-40%，bg 区 100%）→ paddle/brick 区 dominant 仍可能被 bg 桶拿下（板窄、砖稀疏时）→ dist 塌缩。
- **结果**：确认泄漏机制；结论 — 修复必须动态化排除集
- **影响**：方案 B 的 exclude_buckets 动态化

### 实验 2：rain 假阳性边界核算（已执行）

- **问题**：rain_bg_min_dist=24 在动态 bg 下是否仍有效？
- **方法**：核算各相位 bg_ref 与真实雨滴混合色 (49,56,71) 的欧氏距离。
- **结果**：低相位 (10,10,18)→dist≈43.4；中相位 (15,20,31)→dist≈35.9；高相位 (20,30,48)→dist≈30.6 — 全部 ≥24，裕量最小 6.6。脉冲背景自身 dist(bg_ref)≈0 < 24 → 排除 ✓
- **影响**：rain_bg_min_dist=24 保持；假阳性根治

### 实验 3：paddle 区域几何核算（已执行）

- **问题**：全宽区域 vs DESIGN 窄带 vs 实测板位。
- **方法**：区域几何核算 + #476 实测记录（板在 x15-122）。
- **结果**：全宽 720×40 下板 2400px/28800px=3.5% < 5% 阈值临界；DESIGN x240-480 窄带与实测板位 (x15-122) 重叠为 0 → 窄带方案不可行；结论 — 阈值回填校准或节点定位
- **影响**：方案 C 的 paddle 部分修正为"阈值校准"

## 8. 延续上下文（plan agent 交接）

**系统状态：** L3 断言代码仅存在于 impl/466 分支（PR #475），main 无区域断言。本修复在 impl/466 分支代码基础上做（或合入 #475 一并 review）。main 的 `project.godot` 已含 #476 clear_color 修复。runner missed-shot 判 fail 由 #480 实现（workflow/implement）。

**核心决策（本 PRD 已裁决）：**
1. **方案 B：断言侧动态 bg 采样** — `check_visual` 从 R_bg 角落区实测背景色作为 bg_ref，替换静态 bg_color，参与 exclude_buckets / region_stats / rain_signature 全部 bg-relative 计算。相位无关由构造保证。
2. **paddle：不采用 DESIGN x240-480 窄带**（与 #476 实测板位矛盾）— 保持全宽 + min_nonbg_ratio 按实测回填（~0.025，留安全边际），或节点定位板位（#476 AC7 若成本可接受）。
3. **方案 A（capture 侧固定 alpha）不采纳** — 测试帧 ≠ 真实帧 + 模板改动面大 + 不防未来背景动画。

**主要风险：**
- 角落区采样污染（缓解：四角合并 + 负例单测）
- 采样退化（缓解：降级静态兜底）
- #475 合入顺序（本修复依赖 impl/466 基线，需与 #466 review 协调）

**下一步（plan agent）：**
1. 在 impl/466 分支 analyze_bmp.py 设计 `bg_sample_region`（复用 R_bg 角落区）与 `bg_ref` 计算函数（dominant 桶代表色，退化降级静态值）
2. e2e_shots.json 02_midgame：bg_color 字段语义扩展（静态值 + 采样区开关）或新增 `bg_sample: true`
3. tests/pipeline/test_e2e_analyze.py 新增：5 相位合成帧 AC3 用例、脉冲背景 rain 负例（AC2）、角落污染负例（5.2-1）、退化兜底用例（5.2-2）
4. 与 #480 合入顺序协调：AC4 引用其 missed-shot 实现
5. 产出 DESIGN 485 时更新 DESIGN 466 §R_bg 风险行（305 行）为已采纳方案

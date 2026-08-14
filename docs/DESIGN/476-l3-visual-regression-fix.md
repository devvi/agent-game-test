# DESIGN: [Bug] 修复 main 上既有 L3 视觉回归 — clear_color 双重前缀 + bg-bucket 断言返工

> Parent Issue: #476
> Agent: game-plan-agent
> Date: 2026-08-14
> Approach: PRD §4 推荐组合 — 子系统1 **Approach A**（去双重前缀 + TC4 同步）；子系统2 **Approach A**（bg 相对化断言 + 全宽板扫描）
> 深度: depth/standard（Issue 无 depth 标签，按 #464/#465/#466 惯例）
> 上游: `docs/PRD/476-l3-visual-regression-fix.md`（research PR #477 MERGED）

---

## 1. 架构概述

**问题本质是两个叠加的回归：**
1. **真实视觉回归（main 上既有）**：`mini-pong/project.godot:33` 在 `[rendering]` 段内写了带 `rendering/` 前缀的键名 → 全路径 `rendering/rendering/...` → Godot 静默忽略 → 引擎默认灰 (76,76,76) 取代设计值 (10,10,18)。
2. **断言实现缺陷（#466 的 PR #475 内）**：L3 区域断言 4 处缺陷在真实背景 (10,10,18) 下假失败/假绿。

**修复分为两个工作流落点（PRD §8 交接）：**

```
子系统1: main 修复（本 issue 独立落点，可独立 PR）
  mini-pong/project.godot      :33  去双重前缀（1 行）
  mini-pong/tests/test_neon.gd :47  TC4 断言键名同步（隐藏依赖，防 L1 回归）

子系统2: 断言返工（必须落在 impl/466-e2e-visual-regression 分支，PR #475 内）
  scripts/e2e/analyze_bmp.py            bg 相对化（排除 bg 桶 / nonbg 距离 / 雨签名区分 / 板追踪）
  mini-pong/e2e_shots.json              visual 配置增加 bg 参数 + 板区域改全宽
  tests/pipeline/test_e2e_analyze.py    单测改用真实 bg (10,10,18) + 新增反例
```

**设计哲学：** 断言从"绝对近黑"假设改为"相对背景"——游戏专属参数（bg 色、排除桶、距离阈值）全部由 `e2e_shots.json` 的 visual 配置驱动，`analyze_bmp.py` 保持纯 stdlib 无游戏耦合。阈值一律按真实渲染截图回填，不提交理论值（DESIGN 466 §8 校准要求，review 根因 3）。

### 1.1 Prior Implementation Status（#466 部分实现已存在）

| 文件 | main 状态 | impl/466 分支状态（PR #475） |
|------|:---------:|:----------------------------:|
| `scripts/e2e/analyze_bmp.py` | 仅 4 项全局反假断言 | ✅ 含区域断言 `check_visual`/`visual_detail`（4 缺陷） |
| `mini-pong/e2e_shots.json` | 无 `visual` 字段 | ✅ 含 shot 级 visual 配置（三区 + compare_pairs + rain grid 12/min 60%） |
| `tests/pipeline/test_e2e_analyze.py` | 无区域断言测试 | ✅ 含区域断言测试（正向用例用近黑 bg → 假绿） |

**结论：** 本 DESIGN 不新建组件，全部是返工。main 分支无任何 L3 区域断言代码，子系统 2 的返工必须在 impl/466 分支进行。

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（impl/466 分支） | 设计决议 |
|---------|--------------------------|---------|
| `dominant_color()` 排除 bg 桶 | 仅排除近黑桶 `(0,0,0)`；bg (10,10,18) → 桶 `(0,0,1)` 参与竞争 → 三区主色全 bg → dist 0 | 增加 `exclude_buckets` 参数，bg 桶由 visual 配置注入（§3.3.1） |
| `min_nonbg_ratio` 对真实 bg 恒 100% | `region_stats()` nonblack = `not (r<8 and g<8 and b<8)`；bg (10,10,18) r=10≥8 → 全前景 | nonbg 改为"与 bg 色 RGB 距离 ≥ 阈值"（§3.3.2） |
| `rain_signature` 匹配背景本身 | `b - max(r,g) >= 8 AND luma < 100`；bg (10,10,18)：18-10=8 ✓、luma≈12.7 ✓ → 背景被判为雨 | 增加与 bg 的距离条件（§3.3.3） |
| 板区域追踪真实板位 | 固定区域 x240-480/y1220-1260；review 实测板在 x15-122 → 重叠 0/1944 px | 板区域改全宽底部条带（§3.3.4） |
| 单测用真实背景校准 | `test_e2e_analyze.py:226` `BG_DARK=(4,4,4)` 用于全部正向用例 → 假绿 | 正向用例统一 `BG_REAL=(10,10,18)`（§3.5） |

---

## 2. 新组件

**无新文件**（PRD §3.2）。仅 `e2e_shots.json` 的 visual 配置**新增字段**（非新文件）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `bg_color` | string `"RRGGBB"` | 真实背景色（#464 定稿 `0a0a12`），驱动桶排除与距离判定 |
| `bg_min_dist` | number（默认 24） | nonbg 判定阈值：与 bg 的 RGB 距离 ≥ 此值计为前景 |
| `rain_bg_min_dist` | number（默认 24） | 雨签名与 bg 的最小距离（雨滴混合色 (49,56,71) vs bg (10,10,18) ≈ 63，安全） |
| `paddle_node` | string（可选，默认不启用） | 板节点路径（Approach B 升级项，仅当全宽扫描误报时启用） |

---

## 3. 既有组件修改

### 3.1 `mini-pong/project.godot`（main，子系统 1）— 1 行

`[rendering]` 段（line 33）内键名去双重前缀（段头即前缀，同段 line 32 `environment/glow_enabled=true` 为正确格式）：

```diff
 [rendering]
 
 environment/glow_enabled=true
-rendering/environment/defaults/default_clear_color=Color(0.039, 0.039, 0.071, 1)
+environment/defaults/default_clear_color=Color(0.039, 0.039, 0.071, 1)
```

**验证：** `grep -c "rendering/environment/defaults" mini-pong/project.godot` = 0；`grep -n "default_clear_color" mini-pong/project.godot` 仅命中无前缀行。

### 3.2 `mini-pong/tests/test_neon.gd`（main，子系统 1）— 1 行（隐藏依赖，AC3）

`test_neon.gd:47` TC4 断言的是**旧错误键名**——修复 project.godot 后 TC4 必 FAIL（L1 逻辑层回归，run_tests.gd:19 含 test_neon）。必须同 PR 同步：

```diff
-	_assert(content.contains("rendering/environment/defaults/default_clear_color"), "TC4: default_clear_color in project.godot")
+	_assert(content.contains("environment/defaults/default_clear_color"), "TC4: default_clear_color in project.godot")
```

**红线：** 子系统 1 的 project.godot 修改与 TC4 修改必须同 PR 提交，不可拆分（PRD §5.3 失败路径 1）。

### 3.3 `scripts/e2e/analyze_bmp.py`（impl/466 分支，子系统 2）— 4 处返工

#### 3.3.1 `dominant_color()` — bg 桶排除

```python
def dominant_color(rows, x0, y0, x1, y1, exclude_buckets=None):
    """exclude_buckets: 需排除的颜色桶集合（16 级粒度）。
    默认 {(0,0,0)}（近黑桶）保持向后兼容；bg 色 (10,10,18) → 桶 (0,0,1)
    由 visual 配置注入。"""
    exclude_buckets = exclude_buckets or {(0, 0, 0)}
    _n, _nn, buckets = region_stats(rows, x0, y0, x1, y1)
    best_key, best_count = None, 0
    for key, count in buckets.items():
        if key in exclude_buckets:
            continue
        if count > best_count:
            best_count, best_key = count, key
    return (best_key[0] << 4, best_key[1] << 4, best_key[2] << 4) if best_key else None
```

桶计算：`bg_color` 十六进制 → `(r>>4, g>>4, b>>4)`。`(10,10,18)` → `(0,0,1)`，与近黑桶 `(0,0,0)` 不同，**必须显式加入排除集**。

#### 3.3.2 `region_stats()` — nonbg 相对 bg 判定

```python
def region_stats(rows, x0, y0, x1, y1, step=1, bg_color=None, bg_min_dist=24):
    """nonbg 判定：bg_color 为 None 时保持近黑规则（r<8 and g<8 and b<8，
    向后兼容）；配置 bg_color 时改为 rgb_distance((r,g,b), bg) >= bg_min_dist。"""
    ...
    if bg_color is None:
        n_nonblack += 0 if (r < 8 and g < 8 and b < 8) else 1
    else:
        n_nonblack += 1 if rgb_distance((r, g, b), bg_color) >= bg_min_dist else 0
```

`check_visual()` 内 ratio 计算不变（`nn / n`），但语义从"非黑占比"变为"非背景占比"——真实 bg 下板隐藏 → ratio 掉到阈值以下 → 断言失败（AC7 恢复真实拦截能力）。

#### 3.3.3 `rain_signature()` — 与 bg 区分

```python
def rain_signature(r, g, b, bg_color=None, rain_bg_min_dist=24):
    """雨滴签名：蓝色主导 AND 暗 AND 与背景可区分。
    原有 b - max(r,g) >= 8 AND luma < 100 保留；bg_color 配置时
    增加 rgb_distance((r,g,b), bg) >= rain_bg_min_dist —— 背景 (10,10,18)
    与 bg 距离 0 → 不再被判为雨。"""
    if bg_color is not None and rgb_distance((r, g, b), bg_color) < rain_bg_min_dist:
        return False
    return (b - max(r, g)) >= 8 and _luma(r, g, b) < 100
```

`rain_grid_coverage()` 透传 bg 参数。纯背景画面 → coverage 0（PRD §5.2.2：雨滴混合色 (49,56,71) vs bg 距离 ≈63 > 24，安全余量充足）。

#### 3.3.4 板区域 — 全宽底部条带（优先）/ 节点定位（升级项）

**默认方案：全宽扫描。** 板必在底部 y1220-1260 条带（720x1280 布局），区域由固定 x240-480 改为**全宽 x0-720**。零 capture 改动，砖块行 y560-720 与底部条带无重叠（PRD §5.2.3，需真实截图复核）。

**升级项（Approach B）：** 若全宽条带与砖块/其他元素误报，`e2e_shots.json` 增加 `paddle_node` 节点路径，capture 侧（`framework/templates/e2e_capture.gd`）注入板实际包围盒到 shot 记录 → `check_visual()` 用动态区域。**本 DESIGN 默认不启用**，作为实现期 fallback（PRD §4.2 A 第 4 点）。

#### 3.3.5 `check_visual()` / `visual_detail()` — 配置透传

- 从 vcfg 读取 `bg_color` → 计算 `exclude_buckets`（含近黑桶 + bg 桶）
- `region_stats` / `dominant_color` / `rain_signature` / `rain_grid_coverage` 透传 bg 参数
- `visual_detail()` 证据输出增加 `bg_color`、排除桶、各区域 nonbg 距离口径标注（review 证据可审计）

### 3.4 `mini-pong/e2e_shots.json`（impl/466 分支，子系统 2）— visual 配置返工

`02_midgame` shot 的 visual 配置改动：

| 字段 | 现值（impl/466） | 目标值 | 理由 |
|------|-----------------|--------|------|
| `bg_color` | （无） | `"0a0a12"` | 驱动桶排除 + 距离判定 |
| `bg_min_dist` | （无） | `24` | nonbg 距离阈值（真实截图校准后回填） |
| `rain_bg_min_dist` | （无） | `24` | 雨签名与 bg 区分（雨滴混合色距离 ≈63，安全） |
| `regions.paddle` | `x0:240, x1:480` | `x0:0, x1:720`（全宽） | 追踪任意 x 板位（review 实测 x15-122） |
| `regions.paddle.min_nonbg_ratio` | `0.05` | `0.05`（保留） | 语义变为"非背景占比"，板隐藏 → <5% → fail |
| `regions.bg` | `x0:0,y0:0,x1:60,y1:60` | 不变 | 背景参考区（桶排除后主色 = 背景桶本身） |
| `compare_pairs` / `rgb_min_dist` | paddle-brick / paddle-bg / brick-bg，dist 60 | 不变 | AC4 三色分离 ≥ 60 保留 |
| `rain.grid` / `rain.min_coverage` | 12 / 0.6 | 不变 | AC5 雨幕覆盖率 |

### 3.5 `tests/pipeline/test_e2e_analyze.py`（impl/466 分支，子系统 2）— 真实背景校准

- `BG_DARK=(4,4,4)` → 正向用例统一改用 `BG_REAL=(10,10,18)`（`make_png_fast` 默认 bg 参数改真实背景）
- 保留 1-2 个近黑兼容用例（验证 `bg_color=None` 时向后兼容路径）
- 新增反例：bg 桶参与竞争 → dominant 非 bg 桶；纯 bg 画面 → rain coverage 0；板隐藏 → min_nonbg_ratio fail

### 3.6 修改清单汇总

**New files:** 无
**Modified files:**

| 文件 | 落点 | 变更 |
|------|------|------|
| `mini-pong/project.godot` | main（子系统 1） | 1 行键名去前缀 |
| `mini-pong/tests/test_neon.gd` | main（子系统 1） | 1 行 TC4 键名同步 |
| `scripts/e2e/analyze_bmp.py` | impl/466（子系统 2） | dominant_color/region_stats/rain_signature/check_visual/visual_detail 5 函数返工 |
| `mini-pong/e2e_shots.json` | impl/466（子系统 2） | visual 配置 +bg 参数、板区域全宽 |
| `tests/pipeline/test_e2e_analyze.py` | impl/466（子系统 2） | BG_REAL 校准 + 新增反例 |

**Affected test files:** `tests/pipeline/test_e2e_analyze.py`（返工）、`mini-pong/tests/test_neon.gd`（TC4 同步）。`scripts/run-e2e-review.sh` 接口不变（--visual-config 已透传），无改动。

---

## 4. 数据流

### Flow 1: 正常路径（修复后 L3 全过）

```
project.godot 键名修复 → Godot 渲染清屏 = (10,10,18)
  → e2e_capture.gd 截帧（02_midgame）→ shots/*.png
  → analyze_bmp.py --visual-config（bg_color=0a0a12, 板全宽条带）
      ├─ region_stats（nonbg=与 bg 距离≥24）→ 板/砖/背景主色（bg 桶排除）
      ├─ compare_pairs → 三区两两 RGB dist ≥ 60 ✓
      ├─ rain_grid_coverage（雨签名 vs bg 区分）→ ≥ 60% ✓
      └─ 板全宽条带 nonbg_ratio ≥ 5% ✓
  → summary.json L3_visual = pass → PR 证据 comment
```

### Flow 2: 失败路径（clear_color 未修复）

```
project.godot 仍带双前缀 → 渲染灰底 (76,76,76)
  → bg 参考区 avg ≈ (76,76,76) ≠ (10,10,18) → AC2 失败
  → 桶排除按 bg_color 配置执行 → 灰底桶 (4,4,4) 与排除桶 (0,0,1) 不符
     → 三区主色可能仍为灰 → dist < 60 → L3 fail（真实拦截，非假绿）
```

### Flow 3: 边界路径（AI 板随机位置）

```
autoplay ai_position_error=200 → 板 x ∈ [15, 122]（review 实测）或任意位置
  → 全宽底部条带 x0-720 覆盖所有可能板位 → 板始终被捕获
  → 板隐藏（反向用例/回归）→ 条带内无青色像素 → nonbg_ratio < 5% → fail
```

---

## 5. 边界情况与错误处理

| Edge Case | Mitigation |
|-----------|------------|
| BgPulse 呼吸相位使 bg 主色轻微偏移（tint 蓝系） | 桶粒度 16 级天然覆盖小幅偏移；若超出桶范围 → 按 bg 色距离排除而非固定桶（PRD §5.2.1） |
| 雨滴与 bg 混合中间色 (49,56,71) | 与 bg (10,10,18) 距离 ≈63 ≥ rain_bg_min_dist 24 → 仍判为雨；阈值按真实截图回填 |
| 砖块行 y560-720 与底部板条带 y1220-1260 重叠 | 布局无重叠（720x1280）；实现期必须真实截图复核，若误报 → 升级 paddle_node 方案 |
| glow bloom 提亮/偏移板青色 | 主色比较用桶众数不受影响；若 Approach A 不稳 → 回退 PRD §4.2 Approach C 元素色辅助 |
| TC4 隐藏依赖（改 project.godot 忘改 test_neon.gd:47） | 子系统 1 两文件必须同 PR 提交；CI L1 层（run_tests.gd:19 test_neon）兜底拦截 |
| AI 板 autoplay 位置随机（ai_position_error=200） | 板区域全宽扫描，固定区域必然漏检（review 实测重叠 0/1944 px） |
| 无 visual 配置的旧 shot（向后兼容） | `bg_color` 缺失时 `bg_color=None` → 保持近黑行为，不破坏既有 4 项反假断言 |
| 深色模式下 capture 色彩空间差异 | 截图 sRGB 一致 → 距离阈值稳定（PRD §5.2.5） |

---

## 6. 每场景/组件配置

子系统 2 的配置集中在 `e2e_shots.json` `02_midgame.visual`（§3.4 表格为新旧对照）。子系统 1 无场景配置（project.godot 全局渲染键）。

---

## 7. 集成点

> Status 约定：⬜ = pending；✅ = connected（implement agent 接线后更新；review agent 复核）

| Integration | Our Component | Target | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 渲染清屏色 | project.godot `environment/defaults/default_clear_color` | 全部场景 | Godot 全局渲染键（修复后生效） | ⬜ pending |
| L1 逻辑层 | test_neon.gd TC4 键名断言 | project.godot | `content.contains("environment/defaults/default_clear_color")` | ⬜ pending |
| 区域断言 | analyze_bmp.py `check_visual()` | e2e_shots.json visual 配置 | `--visual-config` 透传 bg_color/exclude_buckets/全宽板区域 | ⬜ pending |
| E2E 接线 | run-e2e-review.sh P5 | analyze_bmp.py | 接口不变（--visual-config 已透传），仅行为改善 | ✅ 不变 |
| 断言返工落点 | 子系统 2 三文件 | #466 PR #475（impl/466 分支） | 在 impl/466-e2e-visual-regression 分支上返工，随 #475 重跑 E2E | ⬜ pending |
| 板追踪升级项 | paddle_node 字段 | framework/templates/e2e_capture.gd | 仅当全宽扫描误报时启用（默认不启用） | ⬜ deferred |

---

## 8. 实施阶段

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | 子系统 1：project.godot 键名修复 + test_neon.gd TC4 同步（同一 PR） | 0.5 天 |
| Phase 2 | P0 | 子系统 2：analyze_bmp.py 5 函数返工（bg 相对化） | 1 天 |
| Phase 3 | P0 | 子系统 2：e2e_shots.json visual 配置 + test_e2e_analyze.py 真实背景校准 | 0.5 天 |
| Phase 4 | P0 | 真实截图校准：重跑 run-e2e-review.sh，回填 bg_min_dist/rain_bg_min_dist/板条带 y 范围，验证 L3 pass | 0.5 天 |

依赖顺序：Phase 1 可独立先行（解锁 main 灰底回归）；Phase 2-4 在 #466 PR 内串行。

---

## 9. 测试用例描述

> 仅描述，不写可运行测试代码（implement agent 落点标注）。标 ★ 为新增用例。

### Scenario A: L1 逻辑层 — project.godot 键名（AC1/AC3）
- **Test 1（改，test_neon.gd TC4）**：`_test_project_clear_color()` 断言 `project.godot` 内容包含 `environment/defaults/default_clear_color`（无 `rendering/` 前缀）。前置：project.godot 已修复。预期：`tests/run_tests.gd` L1 全过（含 test_neon），不回归。
- **Test 2（反向）**：若 project.godot 恢复双前缀键名 → TC4 断言失败（拦截回归）。前置：无。预期：L1 fail。

### Scenario B: 单测 — bg 桶排除（AC4 单元层）★
- **Test 3**：合成 PNG 720x1280，bg=BG_REAL(10,10,18)，三区分别填 PADDLE_NEON/BRICK_NEON/bg 色；visual 配置 bg_color=0a0a12。预期：paddle 区 dominant=青色桶、brick 区=橙色桶、bg 区=背景桶；compare_pairs 两两 dist ≥ 60。
- **Test 4（反向）**：三区全填 bg 色 → dominant 均为背景桶 → dist 0 < 60 → fail（bg 桶被排除后无元素色可竞争，正确拦截）。

### Scenario C: 单测 — min_nonbg_ratio 相对 bg（AC7 单元层）★
- **Test 5**：bg=BG_REAL，paddle 区填青色 rect，min_nonbg_ratio=0.05 → nonbg（距 bg ≥ 24）占比 ≥ 5% → pass。
- **Test 6（反向）**：paddle 区全为 bg 色（板隐藏）→ nonbg 占比 ≈ 0 < 5% → fail。前置：BG_REAL 背景。预期：断言失败（修复前恒 100% 假绿）。

### Scenario D: 单测 — 雨签名与 bg 区分（AC5 单元层）★
- **Test 7**：纯 bg=BG_REAL 画面，无雨滴 → rain_grid_coverage = 0（修复前恒 ≈100% 假阳性）。前置：rain_bg_min_dist=24。预期：coverage 0 < 0.6 → fail（无雨时不通过，语义正确）。
- **Test 8**：bg=BG_REAL + 雨滴混合色 (49,56,71) 散布 → coverage ≥ 0.6 → pass。预期：雨签名命中真实雨滴、排除背景。

### Scenario E: 单测 — 板全宽追踪（AC7 单元层）★
- **Test 9**：板 rect 位于 x15-122（review 实测位置，旧区域 x240-480 外）→ 全宽条带捕获 → dominant=青色 → pass。
- **Test 10（反向）**：底部条带无板 → nonbg_ratio < 5% → fail。

### Scenario F: E2E 真实画面（AC2/AC4/AC5/AC7，implement agent 用 run-e2e-review.sh 验证）
- **Test 11（AC2）**：重跑 E2E，bg 参考区 avg ≈ (10,10,18)（非 (76,76,76)）。前置：Phase 1 已 merge。预期：像素分析 bg avg ≈ (10,10,18)。
- **Test 12（AC4）**：真实截图上三区主色两两 RGB dist ≥ 60，且 dominants 非 bg 桶。
- **Test 13（AC5）**：真实雨幕帧 rain coverage ≥ 60%，bg 参考区无雨签名像素。
- **Test 14（AC7）**：真实截图中板在任意 x 位置均被全宽条带捕获（review 实测 x15-122 场景重放）。

### Scenario G: 兼容性（向后兼容）
- **Test 15**：无 visual 配置的 shot → `check_visual` 返回 []（不改变既有 4 项反假断言行为）。前置：bg_color 缺省。预期：旧行为不变。

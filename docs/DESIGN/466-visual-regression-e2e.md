# DESIGN: [Test] 视觉回归 E2E — 玩家板可见 + 颜色区分 + 雨幕分布断言

> **Parent Issue:** #466
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** A（扩展 analyze_bmp.py 区域断言 + e2e_shots.json shot 级 `visual` 配置驱动 + run-e2e-review.sh P5 接线）—— 确认 PRD §4.1 推荐方案；否决 B（独立 visual_assert.py，重复解码逻辑）与 C（capture.gd 内像素断言，违反职责边界 + headless 视口为 0）
> **Reference PRD:** docs/PRD/466-visual-regression-e2e.md（research PR #473，已合并）
> **上游方案:** docs/PLAN-e2e-verification-v2.md（L0-L3 四层模型）、docs/DESIGN/394-e2e-playability.md、docs/DESIGN/464-visual-three-color-layer.md、docs/DESIGN/465-rain-curtain-fix.md
> **所有权:** `content_ownership: mechanical`（区域/阈值/分布断言 = 机械实现，无品味决策；阈值首次真实运行校准后回填）
> **深度:** depth/standard（Issue 无 depth 标签，按 PRD 惯例处理）—— 文件域 5 个（analyze_bmp.py / e2e_shots.json / test_e2e_analyze.py / run-e2e-review.sh / e2e_capture.gd），跨 scripts-e2e / mini-pong 配置 / tests-pipeline / scripts-runner / framework-template 5 子系统，达 TASKS 阈值 → 产出精简 TASKS 文档
> **并行上下文:** 前置 #464（PR #469）、#465（PR #472）已 merged，颜色/分布基线已落地；本 Issue 只改测试基建，**零游戏代码改动**（class A 红线）

---

## 1. 架构概述

### 1.1 现状与差距（plan agent 已对照 origin/main 源码核实，2026-08-13）

| 文件 | 现状（已核实） | 与需求的差距 |
|------|--------------|-------------|
| `scripts/e2e/analyze_bmp.py`（340 行） | 纯 stdlib PNG 解码 + 4 项全局断言（non-black / color count / theme / frame diff，均为 flag-gated CLI 参数） | ❌ **无任何区域/元素断言** —— 全局统计量无法证明"玩家板/砖块/雨幕真的渲染了"（PRD §1.1 实测：板区 y1220-1260 92% 近黑背景色，主题色断言在板不可见时仍通过） |
| `mini-pong/e2e_shots.json` | 3 shots（01_title/02_midgame/03_gameover）；02_midgame 已带 `press: enter` + `require: player_score >= 1`；`theme_color: "4a90d9"`（stale） | ❌ 无 shot 级视觉断言配置；`theme_color` 在 post-#464 画面中无"元素存在"语义（4a90d9 仅存于 BgPulse tint 与升级 UI 边框） |
| `framework/templates/e2e_capture.gd`（387 行） | `_require_ok()` 仅支持 `{node, prop, min}` 数值比较；press 注入/assert_text/settle/per-shot deadline 全可用 | ⚠️ 无 `children_in_group` 计数 require —— 无法表达"砖块存在"门（PRD §5.2 边界 1 方案 a） |
| `scripts/run-e2e-review.sh`（354 行） | P5 循环对每张 png 调 analyze_bmp.py，透传 `--min-colors/--theme/--diff-with` 等全局参数 | ❌ 不透传 shot 级 visual 配置 |
| `tests/pipeline/test_e2e_analyze.py`（215 行） | `make_png()` 合成 PNG + `run_cli()` 设施完备，覆盖 4 断言 | ❌ 无区域断言单测（AC5 反向测试未覆盖） |
| `mini-pong/gdscripts/brick.gd` | `_ready()` 中 `add_to_group("bricks")`（第 17 行，已核实） | ✅ 砖块已入组 —— `children_in_group` require 可直接用 `get_nodes_in_group("bricks")` |

### 1.2 设计哲学

1. **叠加而非替代**：4-fold anti-fake 全局断言保留（防黑帧/冻结帧），新增区域断言是**叠加层**，只对带 `visual` 配置的 shot 生效；无配置时行为逐字节不变（向后兼容红线，`test_e2e_analyze.py` 既有用例必须全绿）。
2. **配置驱动、游戏专属坐标**：区域坐标/阈值/雨网格全部放在 `mini-pong/e2e_shots.json` 的 shot 级 `visual` 字段（游戏专属配置），框架逻辑（analyze_bmp.py）与游戏内容解耦 —— 其他游戏传自己的区域即可复用。`resolve_plan.py` 的 shot 对象已原样透传到 plan.json，P5 可直接读取。
3. **纯 stdlib + CI 可跑**：所有新断言基于现有 `_read_png()` 的 RGBA rows，无 PIL/sips（`test_e2e_analyze.py` 明文约束"no PIL/sips"）。
4. **确定性优先**：砖区波次间隙空窗（PRD §5.2 边界 1）选方案 a —— capture 模板 `_require_ok()` 增加 `children_in_group` 计数（模板级兼容：缺省无此字段时行为不变），截帧前强制"砖块存在"，杜绝 AC3 砖主色退化为背景色的误报。
5. **反向测试进单测**：AC5（改回同色 → 断言失败）以合成 PNG 在 `test_e2e_analyze.py` 实现，无需真机改色（PRD §4.4 决策表）。

### 1.3 系统关系图

```
run-e2e-review.sh P5
  ├─ resolve_plan.py e2e_shots.json diff.txt → plan.json（shot 对象原样透传，含新增 visual 字段）
  ├─ godot --script capture.gd → shots/01_title.png 02_midgame.png 03_gameover.png
  │     └─ e2e_capture.gd _require_ok(): 02_midgame 新增 children_in_group("bricks", min=4) 门
  ├─ 既有 4-fold anti-fake（每张图）: non-black / colors / theme / frame-diff
  └─ 新增区域断言（仅 02_midgame，读 plan.json 中该 shot 的 visual 配置）:
        ├─ R_paddle (x240-480, y1220-1260): 非背景像素占比 ≥ 5%            → AC2
        ├─ 三区主色: R_paddle vs R_brick (y560-720) vs R_bg (四角 60x60)
        │     └─ 两两 RGB 欧氏距离 ≥ 60                                     → AC3
        └─ 全屏雨像素: 蓝主导 + 低亮度 签名, 12x12 网格覆盖 ≥ 60%            → AC4
        └─ canvas 尺寸校验: 截图必须 720x1280（visual.canvas 声明）→ 防区域错位
```

---

## 2. 新组件

**无新脚本文件。** 区域断言并入 `analyze_bmp.py`（Approach A），不新建 `visual_assert.py`（Approach B 否决：重复 PNG 解码逻辑 + P6 输出合并复杂 + 与 test 设施重复）。

新增的是**数据契约**（shot 级 `visual` 配置 schema，见 §3.2），不是代码组件。

---

## 3. 既有组件修改

### 3.1 `scripts/e2e/analyze_bmp.py` — 区域断言核心（Approach A）

新增纯函数（均可独立单测，全部基于 `_read_png()` 返回的 RGBA rows）：

```python
# ── Region assertions (visual regression, #466) ──────────────────────────

def region_stats(rows, x0, y0, x1, y1, step=1):
    """采样区域内像素: 返回 (n_total, n_nonblack, color_bucket_counter)。
    颜色桶与全局 analyze() 同粒度 (16 级: r>>4, g>>4, b>>4)。
    近黑定义与全局一致: r<8 and g<8 and b<8。"""

def dominant_color(rows, x0, y0, x1, y1):
    """区域主色 = 颜色桶众数 (排除近黑桶)。返回 (r, g, b) 或 None (区域全近黑)。"""

def rgb_distance(c1, c2) -> float:
    """欧氏距离: sqrt((r1-r2)^2 + (g1-g2)^2 + (b1-b2)^2)。"""

def rain_signature(r, g, b) -> bool:
    """雨滴签名: b - max(r,g) >= 8 且 luma < 100 (PRD §4.4)。
    雨滴混合色 ≈ (49,56,71) luma≈56 ✓；BgPulse 亮相 luma≈149 ✗；暗底 r≈g≈b 非蓝主导 ✗。"""

def rain_grid_coverage(rows, w, h, grid=12, step=2) -> float:
    """全屏 (w,h) 划分 grid×grid 网格, 每格含 ≥1 雨签名像素 → 覆盖格。
    返回 覆盖格数 / 总格数。"""

def check_visual(path, vcfg: dict) -> list[str]:
    """执行全部区域断言, 返回失败消息列表 (空 = 全过)。
    vcfg schema 见 §3.2。步骤:
      1. canvas 校验: 截图尺寸必须 == vcfg["canvas"] (如 "720x1280") → 不匹配立即 fail
      2. 对 vcfg["regions"] 中每个 region: 提取主色 + 非背景占比,
         min_nonbg_ratio 存在且不满足 → fail
      3. 对 vcfg["compare_pairs"] 中每对 region: 主色 RGB 距离 < rgb_min_dist → fail
      4. rain 配置存在 → 雨网格覆盖率 < rain.min_coverage → fail"""
```

**CLI 扩展**（缺省关闭，向后兼容）：

```
python3 scripts/e2e/analyze_bmp.py shot.png [既有参数...] \
    [--visual-config <path.json>]   # 新增: 区域断言配置 (shot 级 visual 字段的 JSON 文件)
```

- `--visual-config` 缺省 = None → 区域断言整体跳过，行为与现状逐字节一致
- 传入后：先跑既有 4 断言（保留），再跑 `check_visual()`；任一 fail → exit 1
- `--json` 输出扩展：`visual` 键含各 region 的主色/占比/距离/覆盖明细（review agent 证据用）

**纯函数 + CLI 分离**：`check_visual()` 纯函数返回结构化结果（region 主色、距离、覆盖率、fail 列表），`main()` 负责格式化 ✅/❌ 行。`test_e2e_analyze.py` 直接 import `check_visual` 测纯函数，`run_cli` 测 exit code。

### 3.2 `mini-pong/e2e_shots.json` — shot 级 visual 配置 + theme_color 更新

**02_midgame shot 新增 `visual` 字段**（区域坐标依据 PRD §4.4 决策表 + §1.1 源码核实基线）：

```json
{
  "name": "02_midgame",
  "state": "PLAYING",
  "press": { "key": "enter" },
  "require": [
    { "node": "/root/GameManager", "prop": "player_score", "min": 1 },
    { "children_in_group": { "group": "bricks", "min": 4 } }
  ],
  "settle_frames": 5,
  "visual": {
    "canvas": "720x1280",
    "regions": [
      { "name": "paddle", "x0": 240, "y0": 1220, "x1": 480, "y1": 1260, "min_nonbg_ratio": 0.05 },
      { "name": "brick",  "x0": 0,   "y0": 560,  "x1": 720, "y1": 720 },
      { "name": "bg",     "x0": 0,   "y0": 0,    "x1": 60,  "y1": 60 }
    ],
    "compare_pairs": [ ["paddle", "brick"], ["paddle", "bg"], ["brick", "bg"] ],
    "rgb_min_dist": 60,
    "rain": { "grid": 12, "min_coverage": 0.60 }
  }
}
```

**设计决策说明（对照 PRD §4.4 决策表）：**

| 决策点 | PRD 建议 | 本设计定稿 | 理由 |
|--------|---------|-----------|------|
| R_paddle | y1220-1260，x240-480 | **采纳** x240-480/y1220-1260 | 板 span y1230-1250 + 余量；x 窄带提高信噪比（板 120px 宽 vs 全宽 720px 会被背景稀释） |
| R_brick | y560-720 全宽 | **采纳** 全宽 y560-720 | 墙带 wall_y=640 ± 砖阵半高；含拆砖中/波次间隙两种状态（children_in_group 门保证 ≥4 块存在） |
| R_bg | 四角 60x60 | **简化为一角** (0,0)-(60,60) | 三区同帧比较，"区际"距离非绝对色；BgPulse 呼吸为全局 tint，一角即代表（PRD §5.2 边界 2 同款论证）。四角合并留作实现期若一角误报再扩展 |
| 主色提取 | 颜色桶众数，排除近黑 | **采纳**（16 级桶，与全局同粒度） | `dominant_color()` 排除近黑桶 → 区域全近黑返回 None → 该区域断言 fail |
| 雨签名 | `b-max(r,g)≥8 且 luma<100` | **采纳** | PRD §4.4 双条件，暗底/亮相均被排除 |
| 覆盖率网格 | 12x12，≥60% 格含雨像素 | **采纳** grid=12, min_coverage=0.60 | 镜像 #465 AC1；网格化抗"单点密集"假阳性 |
| theme_color | 改 00e5ff 或移除 | **改为 `"00e5ff"`**（玩家板电光青） | 4a90d9 已无元素语义；00e5ff 是 post-#464 玩家板色，theme 断言成为"板色存在"廉价兜底（与 AC2 区域断言叠加） |

**require 数组化**：现有 `_require_ok()` 接受单 dict `{node, prop, min}`。本设计将 02_midgame 的 require 改为**数组**（多条件 AND），capture 模板需支持数组形式（见 §3.4）—— 这是 PRD §5.2 方案 a 的落地点。

### 3.3 `scripts/run-e2e-review.sh` — P5 接线

P5 循环中，对每张 png：

```bash
for png in "$OUT/shots/"*.png; do
  args=(--min-colors 3 --name "$(basename "$png")")
  [ -n "$THEME" ] && args+=(--theme "$THEME")
  if [ -n "$prev" ]; then args+=(--diff-with "$prev" --min-delta 5.0 --diff-ratio 0.005); fi
  # 新增: shot 级 visual 配置透传
  shot_name="$(basename "$png" .png)"
  python3 - "$OUT/plan.json" "$shot_name" "$OUT/visual-$shot_name.json" <<'PY' >/dev/null 2>&1 && args+=(--visual-config "$OUT/visual-$shot_name.json")
import json, sys
plan = json.load(open(sys.argv[1]))
for s in plan.get("shots", []):
    if s.get("name") == sys.argv[2] and "visual" in s:
        json.dump(s["visual"], open(sys.argv[3], "w"), indent=2)
        sys.exit(0)
sys.exit(1)
PY
  # ... 既有 analyze_bmp.py 调用不变
done
```

- visual 配置提取失败（该 shot 无 visual 字段）→ 不传 `--visual-config`，行为与现状一致
- **尺寸校验位置**：`check_visual()` 内部做 canvas 校验（截图 ≠ 720x1280 → fail），不依赖 run-e2e-review.sh

### 3.4 `framework/templates/e2e_capture.gd` — `_require_ok()` 扩展（方案 a，模板级兼容）

```gdscript
func _require_ok(d: Dictionary) -> bool:
	if not d.has("require"):
		return true
	var req = d["require"]
	# 数组形式: 多条件 AND (#466 — require 数组化)
	if req is Array:
		for cond in req:
			if not _require_one(cond):
				return false
		return true
	return _require_one(req)

func _require_one(req: Dictionary) -> bool:
	if req.has("children_in_group"):
		# 新增: 组内节点计数门 (#466 方案 a — 砖块存在性)
		var group: String = str(req["children_in_group"].get("group", ""))
		var min_count: int = int(req["children_in_group"].get("min", 1))
		return root.get_tree().get_nodes_in_group(group).size() >= min_count
	var node = root.get_node_or_null(str(req.get("node", "")))
	if node == null:
		return false
	var v = node.get(str(req.get("prop", "")))
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v) >= float(req.get("min", 1))
	return true
```

- **模板级兼容红线**：`require` 为单 dict 时走原逻辑（`_require_one` 行为与现状逐字节一致）；`children_in_group` 字段缺省时不影响任何既有 shot plan。`01_title`/`03_gameover` 无 require 或单 dict → 零影响
- 这是 PRD 文件域"e2e_capture.gd（仅若需）"的**唯一改动点**：`_require_ok` 一个函数重构 + 新增 `_require_one`，**不碰** press 注入 / 状态推进 / settle / deadline 任何逻辑（PRD §1.1 表 #1 预调查结论：capture 状态推进已可用，AC1 无需新增机制）

### 3.5 `tests/pipeline/test_e2e_analyze.py` — 区域断言单测（含 AC5 反向）

新增测试类（沿用 `make_png`/`run_cli`/`write_png` 设施）：

| 测试 | 合成 PNG | visual 配置 | 期望 |
|------|---------|------------|------|
| `test_visual_paddle_present` | 暗底 (10,10,18) + 板色块 (0,229,255) 在 (300,1230)-(420,1250) | paddle min_nonbg_ratio=0.05 | rc=0 |
| `test_visual_paddle_missing_fails`（**AC5 反向**） | 纯暗底（无板） | paddle min_nonbg_ratio=0.05 | rc=1，输出含 "paddle" fail |
| `test_visual_three_color_separation` | 暗底 + 青板 + 橙砖 (255,157,69) 在 (0,600)-(720,680) | compare_pairs 三对，rgb_min_dist=60 | rc=0 |
| `test_visual_same_color_fails`（**AC5 反向**） | 板/砖全用暗底色（同色回归） | compare_pairs | rc=1 |
| `test_visual_rain_coverage_pass` | 全屏均匀撒蓝主导低亮像素 (50,56,70) | rain grid=12 min=0.60 | rc=0 |
| `test_visual_rain_coverage_fail` | 只在一个角撒雨像素 | rain grid=12 min=0.60 | rc=1 |
| `test_visual_canvas_mismatch` | 64x64 PNG | canvas="720x1280" | rc=1，输出含尺寸错误 |
| `test_visual_config_absent_backward_compat` | 渐变 PNG | 不传 --visual-config | rc=0（与现状一致） |
| `test_rain_signature_excludes_bright` | 亮蓝 (0,150,255)（luma>100）铺满 | rain | rc=1（签名排除） |
| `test_rain_signature_excludes_gray` | 中性灰 (70,70,70)（非蓝主导）铺满 | rain | rc=1 |

> 单测只测 analyze_bmp.py（Python 层）。capture 模板 `_require_ok` 的 `children_in_group`/数组逻辑由 implement agent 在 `mini-pong/tests/` 层验证（Godot 侧，遵循既有 test 结构）—— 具体用例描述见 §9 Scenario D。

### 3.6 修改清单汇总

**New files：** 无
**Modified files：**

| 文件 | 改动 | 动机 |
|------|------|------|
| `scripts/e2e/analyze_bmp.py` | region 纯函数 + `check_visual()` + `--visual-config` CLI + `--json` 扩展（§3.1） | 区域断言核心（Approach A） |
| `mini-pong/e2e_shots.json` | 02_midgame 增 `visual` 配置 + require 数组化 + `theme_color` → `00e5ff`（§3.2） | 配置驱动 |
| `scripts/run-e2e-review.sh` | P5 循环 shot 级 visual 提取透传（§3.3） | 管线接线 |
| `framework/templates/e2e_capture.gd` | `_require_ok` 数组化 + `children_in_group`（§3.4） | 砖块存在门（方案 a） |
| `tests/pipeline/test_e2e_analyze.py` | 区域断言单测类（§3.5） | CI 可测 + AC5 反向 |
| `docs/DESIGN/394-e2e-playability.md` | L3 章节补一句"区域断言（#466）" | 文档同步（非代码） |

**Removed/Deprecated：** 无
**Affected test files：** `tests/pipeline/test_e2e_analyze.py`（扩展）；`mini-pong/tests/` 侧新增/扩展 `_require_ok` 相关用例（implement agent 决定落点，见 §9）
**Not modified（红线）：** `mini-pong/gdscripts/`、`mini-pong/scenes/`、`mini-pong/project.godot`、`resolve_plan.py`（shot 对象已原样透传，零改动）、`e2e_capture.gd` 的 press/状态推进逻辑

---

## 4. 数据流

### Flow 1: 正常路径（midgame 视觉断言全过）

```
run-e2e-review.sh P5
  ├─ resolve_plan.py mini-pong/e2e_shots.json diff.txt → plan.json
  │     （resolve_plan.py _PASSTHROUGH 不含 shots 级过滤 — shot 对象含 visual 字段原样透传 ✓）
  ├─ godot --script capture.gd -- plan.json
  │     └─ 02_midgame: press enter → PLAYING → _require_ok([
  │           player_score>=1 ✓ AND get_nodes_in_group("bricks").size()>=4 ✓ ])
  │        → settle 5 帧 → 截图 shots/02_midgame.png (720x1280)
  ├─ 4-fold anti-fake: non-black ✓ colors ✓ theme #00e5ff ✓ diff ✓
  └─ 区域断言 (--visual-config visual-02_midgame.json):
        ├─ canvas 校验: 720x1280 == 720x1280 ✓
        ├─ R_paddle 非背景占比 25% >= 5% ✓ → AC2
        ├─ 主色: paddle(0,229,255) vs brick(255,157,69) 距离≈347 ✓
        │        paddle vs bg(10,10,18) ≈300 ✓  brick vs bg ≈278 ✓ → AC3
        └─ 雨网格覆盖 85% >= 60% ✓ → AC4
  → 全部 ✅ → P5=pass → P6 证据评论含 02_midgame.png + 断言明细
```

### Flow 2: 失败路径（视觉回归被破坏）

```
未来某 PR 把玩家板改回背景色 (10,10,18):
  ├─ capture 正常 (板仍渲染, 只是同色)
  ├─ 4-fold anti-fake: 仍全过 (非黑/色数/theme 00e5ff 仍存在于别处/帧 diff ✓)
  └─ 区域断言: R_paddle 主色 (10,10,18) == bg 主色 → 距离 0 < 60 ❌
        + R_paddle 非背景占比 0% < 5% ❌
  → analyze_bmp.py exit 1 → P5=fail → run-e2e-review.sh exit 1
  → PR 评论呈现 ❌ 明细 (既有机制) → 拦截合并 (与 #464 之前"静默通过"形成对照)
```

### Flow 3: 边界路径（波次间隙砖块清空）

```
02_midgame 截帧瞬间恰逢波次间隙 (砖阵被清空, 下一波未生成):
  ├─ _require_ok([... children_in_group("bricks", min=4)]) → bricks 数 < 4 → 条件不满足
  ├─ capture 循环继续轮询 (既有 pending 机制, per-shot deadline 内)
  ├─ 下一波砖生成 → get_nodes_in_group("bricks").size() >= 4 → 截帧
  └─ 若 deadline (120s) 内始终无砖 → shot 标记 missed (既有机制) → 区域断言跳过并标注"未执行"
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解 |
|---------|------|
| 波次间隙砖块清空 → AC3 砖主色退化 | **方案 a**：`children_in_group("bricks", min=4)` 门强制砖存在才截帧（§3.4）；deadline 内无砖 → missed 显式标注，不静默通过 |
| BgPulse 呼吸相位 → R_bg 主色变化 | 三区同帧比较（AC3 是"区际"距离非绝对色）；呼吸 tint 蓝系与板青/砖橙距离仍 ≥60（PRD §5.2） |
| 雨幕 alpha 低 (0.225) → 雨像素接近暗底 | 签名双条件"蓝主导 + 低亮度"（§3.1 `rain_signature`）；暗底 r≈g≈b 不满足蓝主导 |
| 粒子瞬时分布不均 → 单帧覆盖 <60% | 12x12 网格统计 + 60% 阈值与 #465 AC1 对齐；阈值可首次真实运行后按实测回填（PRD §8） |
| HUD/计分文本干扰区域 | 区域坐标避开 HUD（R_brick y560-720 与 HUD 不重叠；R_paddle x 窄带 240-480 避开计分文本） |
| 分辨率变化 → 区域错位 | `visual.canvas: "720x1280"` 声明 + `check_visual()` 尺寸校验，不匹配立即 fail（非错位静默） |
| 截图失败/缺 midgame | 既有 missed 机制报错；区域断言跳过并显式标注"未执行"（run-e2e-review.sh 循环天然处理） |
| 旧调用（无 visual 配置的 PR diff） | `--visual-config` 缺省关闭 → 行为与现状逐字节一致；模板 require 单 dict 路径不变 |
| analyze_bmp.py 解析新参数失败 | 新 CLI 参数缺省即关闭；解析失败走既有 unknown arg 分支 exit 2，不影响旧调用 |
| 玩家板/AI 板双板 | autoplay 设 PlayerPaddle mode=1 (AI)，AI 模式下板仍渲染 → 视觉断言不受影响（PRD §1.1 表 #2） |

---

## 6. 每场景配置

| Scene / Shot | 区域断言 | 配置要点 |
|:---:|:---:|------|
| 01_title (MENU) | ❌ 无 visual 配置 | 保持现状（菜单非三色基线场景） |
| **02_midgame (PLAYING)** | ✅ paddle/brick/bg 三区 + 雨网格 | §3.2 完整配置；require 数组化 + children_in_group |
| 03_gameover (GAME_OVER) | ❌ 无 visual 配置 | 保持现状（GameOver 画面非三色基线场景） |

---

## 7. 集成点

> **Status 约定：** ⬜ = pending（资源已创建，尚未接线）；✅ = connected（implement agent 验证）。

| 集成 | 我们的组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|------|:---:|
| analyze_bmp.py `check_visual()` | region 纯函数 | #466 | `--visual-config` CLI 参数由 run-e2e-review.sh P5 透传 | ⬜ |
| e2e_shots.json `visual` 字段 | shot 配置 | #466 | resolve_plan.py 原样透传 → P5 提取为 JSON 文件 | ⬜ |
| e2e_capture.gd `_require_ok` 数组化 | 模板 require | #466 | 02_midgame require 数组 + children_in_group("bricks") | ⬜ |
| test_e2e_analyze.py 单测类 | 合成 PNG 设施 | #466 | 直接 import check_visual / run_cli | ⬜ |
| docs/DESIGN/394 L3 一行 | 文档 | #466 | 描述区域断言叠加层 | ⬜ |

---

## 8. 实施阶段

| Phase | 优先级 | 组件 | 估计 |
|:---:|:---:|------|:---:|
| Phase 1 | P0 | `analyze_bmp.py` region 纯函数 + `check_visual()` + CLI（§3.1） | 0.5 天 |
| Phase 2 | P0 | `test_e2e_analyze.py` 单测类（§3.5，含 AC5 反向） | 0.5 天 |
| Phase 3 | P0 | `e2e_shots.json` visual 配置 + theme_color（§3.2） | 0.5 天 |
| Phase 4 | P0 | `run-e2e-review.sh` P5 透传（§3.3） | 0.5 天 |
| Phase 5 | P1 | `e2e_capture.gd` `_require_ok` 数组化 + children_in_group + mini-pong 侧验证（§3.4/§9-D） | 0.5 天 |
| Phase 6 | P1 | 真机跑 `run-e2e-review.sh`（--baseline 或含视觉改动 PR），记录实测像素值回填阈值（PRD §8 决策 5） | 0.5 天 |
| Phase 7 | P2 | docs/DESIGN/394 L3 一行同步（§3.6） | 0.1 天 |

依赖序：Phase 1 → 2（纯函数先行 + 单测，PRD §8 推荐）→ 3/4（配置 + 接线）→ 5（capture 门）→ 6（校准）→ 7（文档）。

---

## 9. 测试用例描述

> 只描述，不写可运行代码（implement agent 负责落地）。

### Scenario A: 玩家板可见性（AC2）
- **Test 1**（正向）：合成 720x1280 PNG，暗底 (10,10,18) + 板色块 (0,229,255) 于 (300,1230)-(420,1250)。visual 配置 paddle x240-480/y1220-1260 min_nonbg_ratio=0.05 → 期望 exit 0，输出含 "paddle" ✅ 与非背景占比 ≥5%。
- **Test 2**（AC5 反向）：纯暗底无板。同一配置 → 期望 exit 1，输出含 paddle fail（非背景占比 <5%）。**这是"板不可见"回归的拦截证据**。

### Scenario B: 三色分离（AC3）
- **Test 3**（正向）：暗底 + 青板 (0,229,255) + 橙砖条 (255,157,69) 于 (0,600)-(720,680) + 角落暗底 → compare_pairs 三对 rgb_min_dist=60 → 期望 exit 0，输出三对距离明细（≈347/300/278）。
- **Test 4**（AC5 反向）：板/砖均用暗底色（模拟 #464 之前同色回归）→ 期望 exit 1，输出 RGB 距离 <60 fail。

### Scenario C: 雨幕分布（AC4）
- **Test 5**（正向）：全屏均匀撒蓝主导低亮像素 (50,56,70)（≈雨滴混合色）→ grid=12 min_coverage=0.60 → 期望 exit 0。
- **Test 6**（反向）：仅左上角 1/16 区域撒雨像素 → 期望 exit 1（覆盖率 <60%）。
- **Test 7**（签名排除）：亮蓝 (0,150,255)（luma>100）铺满 → 期望 exit 1（签名不认亮蓝）；中性灰 (70,70,70) 铺满 → exit 1（非蓝主导）。

### Scenario D: capture 模板 require（Godot 侧，implement agent 落点）
- **Test 8**：构造含 `children_in_group: {group:"bricks", min:4}` 的 require 数组，场景中 bricks 组 0 节点 → `_require_ok` 返回 false；加入 4 个砖节点 → true。
- **Test 9**：单 dict require（旧格式，如 01_title 无 require / 其他游戏模板）→ 行为与改动前一致（回归）。
- **Test 10**：require 数组多条件（player_score>=1 AND bricks>=4）同时满足才 true，任一不满足 false。

### Scenario E: 向后兼容与尺寸
- **Test 11**：渐变 PNG 不传 `--visual-config` → exit 0，输出与改动前逐字节一致（回归）。
- **Test 12**：64x64 PNG + canvas="720x1280" → exit 1，输出含尺寸不匹配错误（防区域错位）。
- **Test 13**：`--json` 输出含 `visual` 键（region 主色/占比/距离/覆盖明细）→ review agent 证据可解析。

### Scenario F: 真机校准（Phase 6，非单测）
- **Test 14**：对 post-#464 midgame 真实截图跑 `--visual-config`，记录实际 非背景占比 / 三对距离 / 雨覆盖率，与理论值（25% / 347-300-278 / ≥60%）比对，偏差 >20% 则回填阈值并注释（PRD §8 决策 5）。

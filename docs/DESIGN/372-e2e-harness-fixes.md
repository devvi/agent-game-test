# DESIGN: [Infra] 修复 run-e2e-review.sh P6 上传函数顺序 + frozen 阈值过严 (class A)

> **Parent Issue:** #372
> **Agent:** game-plan-agent
> **Date:** 2026-08-11
> **Approach:** 全部沿用 PRD §4 推荐方案 A —— P6 helper 上移 + gist 通道修正 + frozen 占比指标 + per-shot deadline（§4.1-A / §4.2-A / §4.3-A(占比, 兼容 OR) / §4.4-A）；`resolve_plan.py` 与 `test_e2e_runner.py` 经核实**无需改动**（见 §4/§6）
> **Reference PRD:** docs/PRD/372-e2e-harness-fixes.md
> **所有权:** class A 基建（workflow/plan）—— 只改测试基建文件，**不改游戏代码**（`mini-pong/gdscripts/`、`scenes/`、`project.godot`）；PR body 用 `Parent #372`（不写 Closes）；merge 后由 implement 阶段推进
> **深度:** depth/standard — 仅 DESIGN doc，无 TASKS doc

---

## 1. 概述

本 Issue 修复 #371 review 暴露的 4 个 class A E2E 基建缺陷（全部位于 harness 本身，非游戏缺陷），使 E2E 证据链真正闭环：

1. **P6 上传函数定义在调用点之后**（`upload_via_github`/`upload_via_gist` 定义于 344/360 行，`exit "$OVERALL"` 于 339 行之后）→ bash `command not found`；且第 283 行 `$name_` 是未绑定变量（应为 `$name`），`set -u` 下 P6 直接崩溃，`gh pr comment` 永不执行。
2. **截图无法嵌入 PR comment**：`upload_via_github` 用字面量 `Authorization: Bearer ***` + 浏览器拖拽上传端点（非 REST comment-attachment API，脚本注释自述 2026-07-31 验证无此 API）→ 认证必失败；gist fallback URL `https://gist.githubusercontent.com/raw/$id/$fname` 缺 username 段 → 404。
3. **frozen 启发式误报**：`analyze_bmp.py` 的 frame-diff 用**全帧平均** luma 差；霓虹暗底（大面积 `#0a0a12` 近黑）使均值几乎不变（#371 实测 Δluma=0.5 < 5.0），但逐像素 9301px（1.009%）显著变化 → L3 误报 fail。
4. **03_gameover 超时**：`mini-pong/e2e_shots.json` 全局 `max_wall_seconds: 120`，5 分制双 AI 对打（`ai_position_error=200`）120s 内打不完 → shot 永不 ready → capture exit 1。

**Plan 阶段边界**：本阶段只产出本文档，不写任何可运行代码 —— 下列修改清单是给 implement agent 的契约。所有设计已对照源码逐行核实（行号见 §2 证据）。

---

## 2. 现状核实（plan agent 已对照源码确认）

| # | PRD 声明 | 源码证据（已核实） |
|---|---------|------------------|
| 1 | P6 helper 在调用点之后 | `run-e2e-review.sh`：P6 EVIDENCE 块 251 行起，`upload_via_github` 调用在 273 行、`upload_via_gist` 在 276 行；函数定义在 344/360 行（`exit "$OVERALL"` 339 行之后）|
| 1b | `$name_` 未绑定 | 283 行 `echo "_upload failed — see /tmp/e2e-$PR_NUM/shots/$name_"` —— `$name_` 无定义，`set -u` 下崩溃 |
| 2 | `Bearer ***` + 错误端点 | 349 行 `curl -s -H "Authorization: Bearer ***" https://github.com/upload/policies/assets ...` |
| 2b | gist URL 缺 user 段 | 365 行 `echo "https://gist.githubusercontent.com/raw/$id/$fname"`（真实格式 `<user>/<gist_id>/raw/<file>`）|
| 3 | frozen 用全帧平均 luma | `analyze_bmp.py` `_luma_delta()` 返回 `total / n`（全采样点平均 \|Δluma\|）；CLI `--min-delta` 默认 5.0；runner 273-276 行区域传 `--min-delta 5.0` |
| 4 | 全局 120s deadline | `mini-pong/e2e_shots.json` `max_wall_seconds: 120`；`e2e_capture.gd` `_deadline_ms` 单一全局（`_started_ms + int(_plan.get("max_wall_seconds", 120)) * 1000`），shot 无独立 deadline |
| 5 | 透传链 | `resolve_plan.py` shot dict **原样 append**（`shots.append(s)`）→ `deadline_s` 字段自动透传，**无需改 resolve_plan.py** |
| 6 | runner 测试 | `test_e2e_runner.py` 全部用例走 `--no-comment`/`--dry-run`，不触碰 P6 上传分支 → **无需改 test_e2e_runner.py**（PRD 原标"可能"，核实为不需要）|

---

## 3. 组件修改清单（implement 契约）

| 文件 | 改动性质 | 内容 |
|------|---------|------|
| `scripts/run-e2e-review.sh` | **修改** | §4.1：两个 upload helper 定义移到 P6 EVIDENCE 块之前；`$name_`→`$name`；§4.2：删除 `upload_via_github`（浏览器端点 + `Bearer ***` 永远不可用），gist 为唯一通道并修正 URL；§4.3：P5 断言传 `--diff-ratio 0.005`；头部注释更新 P6 通道说明 |
| `scripts/e2e/analyze_bmp.py` | **修改** | §4.3：新增 `--diff-ratio`（变化像素占比阈值）与 `--pixel-delta`（单像素 Δluma 阈值，默认 20）选项；frame-diff 断言改为"均值 OR 占比"双通道 |
| `mini-pong/e2e_shots.json` | **修改** | §4.4：03_gameover shot 增加 `"deadline_s": 300`；`_comment` 说明 deadline 策略 |
| `framework/templates/e2e_capture.gd` | **修改** | §4.4：per-shot deadline 支持（`_shot_deadline_ms()` + 主循环/settle 按 shot 判定）；头部 schema 注释同步 |
| `framework/ARCHITECTURE.md` | **修改** | 组件表 `analyze_bmp.py` 行（帧间差异指标）与 `e2e_capture.gd` 行（per-shot deadline）描述同步 |
| `framework/templates/e2e_shots.json` | **修改** | 模板 shot 注释补充 `deadline_s` 可选字段说明（向后兼容：缺省用全局 `max_wall_seconds`）|
| `tests/pipeline/test_e2e_analyze.py` | **修改** | §4.3 新增：霓虹暗底变化帧回归用例（#371 场景）、`--diff-ratio` 下 identical→frozen、全黑→全白→pass、缺省行为向后兼容 |
| `scripts/e2e/resolve_plan.py` | **不改** | shot dict 原样透传（已核实），`deadline_s` 无需特殊处理 |
| `tests/pipeline/test_e2e_runner.py` | **不改** | P6 分支未被现有用例触碰（已核实）|
| 游戏代码（`mini-pong/gdscripts/`、`scenes/`、`project.godot`） | **不改** | class A 红线 |

---

## 4. 修改细节（implement 精确规格）

### 4.1 `scripts/run-e2e-review.sh` — P6 函数顺序 + `$name_` 修正

**现状**：`upload_via_github`（344 行）/`upload_via_gist`（360 行）定义在 `exit "$OVERALL"`（339 行）之后；P6 调用点 273/276 行。

**改法（PRD §4.1-A）**：

1. 把两个 upload helper 的**整个定义块**移动到 `# ═══ P6 EVIDENCE ═══` 区块（251 行）之前、P5 VISUAL 区块之后（约 249 行处），保持 `set -u` 全局语义不变。
2. 283 行 fallback 文案 `$name_` → `$name`：
   ```bash
   echo "_upload failed — see /tmp/e2e-$PR_NUM/shots/$name"
   ```
3. 验收自查：`grep -n "upload_via" scripts/run-e2e-review.sh` 定义行号 < 调用行号；`grep -n 'name_' scripts/run-e2e-review.sh` 无 `"$name_"` 模式残留。

### 4.2 `scripts/run-e2e-review.sh` — 上传通道收敛为 gist（PRD §4.2-A）

**删除** `upload_via_github` 整个函数（含 `Bearer ***` 字面量与浏览器端点），在原位置留 3 行注释说明删除原因（防止后续维护者误以为该通道可用）：

```bash
# ⚠ upload_via_github 已删除（2026-08-11, #372）：
#   https://github.com/upload/policies/assets 是浏览器拖拽上传端点，
#   非 REST comment-attachment API（2026-07-31 已验证不存在），
#   字面量 Bearer *** 占位符永远无法认证 → 该通道不可修复，弃用。
```

P6 comment 构建循环（原 273-276 行）改为**只走 gist 通道**：

```bash
for png in "$OUT/shots/"*.png; do
  [ -f "$png" ] || continue
  name="$(basename "$png")"
  url="$(upload_via_gist "$png")"
  ...
done
```

**`upload_via_gist` 修正**（原 360-365 行）：

1. `gh gist create --public` 输出解析：不假设 `tail -1` 就是 URL —— 用 grep 提取 URL 行：
   ```bash
   gist_url="$(gh gist create --public "$png" 2>/dev/null | grep -Eo 'https://gist\.github\.com/[^ ]+' | head -1)"
   ```
2. 从 URL 解析 `<user>` 与 `<gist_id>` 两个段（URL 形如 `https://gist.github.com/<user>/<gist_id>`）：
   ```bash
   user="$(printf '%s' "$gist_url" | sed -E 's#https://gist\.github\.com/([^/]+)/.*#\1#')"
   id="$(printf '%s' "$gist_url" | sed -E 's#.*/([^/]+)$#\1#')"
   [ -n "$user" ] && [ -n "$id" ] || return 1
   ```
3. raw URL 修正为带 user 段：
   ```bash
   echo "https://gist.githubusercontent.com/$user/$id/raw/$fname"
   ```
4. 失败路径：任何一步解析失败 → `return 1` → P6 循环落到 `_upload failed — see /tmp/...` 本地路径文案，**不崩溃**（所有变量先绑定，`set -u` 安全）。

### 4.3 `scripts/e2e/analyze_bmp.py` — frozen 指标改为"变化像素占比"（PRD §4.3-A，兼容 OR）

**新增指标**：逐像素 |Δluma| > 单像素阈值（`--pixel-delta`，默认 20）的像素占比 ≥ `--diff-ratio`（如 0.005）→ 判定"画面变化"。对霓虹暗底鲁棒（#371 实测 1.009% 显著变化像素，占比指标必过），同时保留均值通道兼容亮色游戏与旧测试。

**实现规格**：

1. 新增函数（复用 `_luma_delta` 的采样遍历结构，step=3 保持一致）：
   ```python
   def _changed_ratio(path_a: str, path_b: str, pixel_delta: float = 20.0) -> float:
       # 尺寸不同 → return 1.0（必变化，与 _luma_delta 返回 inf 语义一致）
       # 逐采样点 |Δluma| > pixel_delta 计数 / 总采样数
   ```
2. CLI 新增选项：`--diff-ratio R`（float，默认 None = 不启用占比通道）、`--pixel-delta D`（float，默认 20.0）。
3. frame-diff 断言（assertion 4）逻辑改为**双通道 OR**：
   ```python
   diff_with = _s("--diff-with")
   if diff_with:
       min_delta = _f("--min-delta", 5.0)
       delta = _luma_delta(path, diff_with)
       diff_ratio_arg = _f("--diff-ratio", None)   # None → 不启用
       ratio_ok = False
       ratio = 0.0
       if diff_ratio_arg is not None:
           ratio = _changed_ratio(path, diff_with, _f("--pixel-delta", 20.0))
           ratio_ok = ratio >= diff_ratio_arg
       if delta >= min_delta or ratio_ok:
           passes.append(f"diff vs {Path(diff_with).name}: Δluma={delta:.1f} >= {min_delta}"
                         + (f" 或 变化像素占比 {ratio*100:.3f}% >= {diff_ratio_arg*100:.3f}%" if diff_ratio_arg is not None else ""))
       else:
           fails.append(f"diff vs {Path(diff_with).name}: Δluma={delta:.1f} < {min_delta}"
                        + (f" 且 变化像素占比 {ratio*100:.3f}% < {diff_ratio_arg*100:.3f}%" if diff_ratio_arg is not None else "") + " — frozen?")
   ```
4. 不传 `--diff-ratio` 时行为与现状完全一致（纯均值）→ 旧调用方/旧测试零破坏。
5. `_f()` 需支持 `None` 默认值语义（现实现 `str(v) if ...` 会把 None 当 falsy → 返回 default；注意 `--diff-ratio` 传参后值必须是可 float() 的字符串，天然满足）。

### 4.4 runner 传参（`run-e2e-review.sh` P5 断言循环）

原 `args+=(--diff-with "$prev" --min-delta 5.0)` 改为：

```bash
args+=(--diff-with "$prev" --min-delta 5.0 --diff-ratio 0.005)
```

（`--pixel-delta` 用默认 20，不显式传。阈值依据：#371 实测 1.009% 变化像素、单像素 Δluma 变化远超 20；0.5% 阈值留 2 倍裕量。若 implement 阶段用 #371 真实两帧验证不通过，可在 0.002–0.01 区间微调并在 PR 里说明。）

### 4.5 `mini-pong/e2e_shots.json` — 03_gameover per-shot deadline（PRD §4.4-A）

03_gameover shot 增加 `deadline_s` 字段：

```json
{ "name": "03_gameover", "state": "GAME_OVER", "settle_frames": 10, "deadline_s": 300 }
```

`_comment` 更新：说明 03_gameover 因 5 分制双 AI 对打耗时不可控，单独延长至 300s（120s 全局 + 180s 裕量），其它 shot 沿用全局 120s。**不改** `ai_position_error=200`（保持对打节奏证据质量，PRD §4.4-C 已否）。

### 4.6 `framework/templates/e2e_capture.gd` — per-shot deadline 支持

1. 新增 helper：
   ```gdscript
   func _shot_deadline_ms(d: Dictionary) -> int:
       var per := int(d.get("deadline_s", 0))
       if per > 0:
           return _started_ms + per * 1000
       return _deadline_ms
   ```
2. 主循环：`for shot in pending:` 内先做 per-shot 过期检查（`now >= _shot_deadline_ms(d)` → 直接记 missed，不进 still_pending）；`_settle` 调用改为传入该 shot 的 deadline：`await _settle(int(d.get("settle_frames", 5)), _shot_deadline_ms(d))`。
3. `_settle(frames: int, deadline_ms: int)` 签名变更：内部 `Time.get_ticks_msec() >= deadline_ms` 判定（原用全局 `_deadline_ms`）。
4. 全局 `_deadline_ms` 保留（`max_wall_seconds` 仍是总上限，防死锁卡死 CI）；per-shot deadline 只可能比全局更早到期。
5. 头部 schema 注释补充 `deadline_s` 字段说明。

### 4.7 `tests/pipeline/test_e2e_analyze.py` — 新增用例（只写测试描述与断言要点，不写实现）

| 用例 | 输入 | 期望 |
|------|------|------|
| `test_frame_diff_identical_fails_diff_ratio` | 两张 identical 帧，`--diff-ratio 0.005` | rc=1，输出含 "frozen" |
| `test_frame_diff_full_change_passes_diff_ratio` | 全黑→全白，`--diff-ratio 0.005 --min-colors 1` | rc=0（占比 100% ≥ 0.5%）|
| `test_frame_diff_dark_neon_change_passes`（**#371 回归**）| 64×64 暗底 `#0a0a12`，第二帧约 1% 像素（如 8×5 矩形）改为亮色（如 `#4a90d9`），`--diff-ratio 0.005 --min-delta 5.0 --min-colors 1` | rc=0 —— 均值 Δluma 远 < 5.0 但占比 ≥ 0.5% → 占比通道救回（镜像 #371：Δluma=0.5 但 1.009% 像素变化）|
| `test_frame_diff_ratio_default_off` | 不传 `--diff-ratio`，identical 帧 | rc=1（旧均值行为，向后兼容）|
| 既有 2 个 diff 用例 | 不传 `--diff-ratio` | 保持绿（纯均值路径未动）|

**测试基线**：改完必须 `python3 -m pytest tests/pipeline/`（104 用例基线全绿，ARCHITECTURE.md D3）。

### 4.8 `framework/ARCHITECTURE.md` — 组件表同步

| 行 | 现值 | 改为 |
|----|------|------|
| `e2e/analyze_bmp.py` | `PNG 原生 4 重防伪断言（非黑/色数/主题色/帧间差异, 纯 stdlib）` | `PNG 原生 4 重防伪断言（非黑/色数/主题色/帧间差异——全帧平均Δluma 或 变化像素占比, 纯 stdlib）` |
| `e2e_capture.gd` | `截图驱动 SceneTree 脚本（状态机轮询 + press 注入 + assert_text, 进程内截图）` | `截图驱动 SceneTree 脚本（状态机轮询 + press 注入 + assert_text + per-shot deadline, 进程内截图）` |

### 4.9 `framework/templates/e2e_shots.json` — 模板注释

`max_wall_seconds` 字段旁注释补充：`shot 可设 deadline_s 覆盖全局（缺省沿用 max_wall_seconds）`；03_gameover 示例不动（模板保持最小）。

---

## 5. 验收标准映射（Issue #372 AC）

| AC | 验证方式 | 对应修改 |
|----|---------|---------|
| AC1: P6 函数定义在调用点前 + `$name_` 修正 | `grep -n "upload_via" run-e2e-review.sh` 定义行号 < 调用行号；无 `"$name_"` 残留；`bash -n` 通过 | §4.1 |
| AC2: 截图可嵌入 PR comment（gist raw 链接） | 实测 `run-e2e-review.sh <PR>` 后 comment 含 `![name](https://gist.githubusercontent.com/<user>/<id>/raw/<file>)`；`curl -I` 返回 200 | §4.2 |
| AC3: frozen 阈值对霓虹暗底不误报 | #371 真实两帧（01_title vs 02_midgame）跑 `analyze_bmp.py --diff-ratio 0.005` 断言 pass；`test_e2e_analyze.py` 新增暗底用例绿 | §4.3/§4.7 |
| AC4: 03_gameover deadline 内可捕获 | 实测 E2E 跑通，results.json 03_gameover saved=true | §4.5/§4.6 |
| AC5: `--headless --quit` 无脚本错误 | `godot --path mini-pong/ --headless --quit` exit 0 无 stderr | 无改动（验收确认项）|

## 6. 边界与失败路径（implement 必须遵守）

1. `gh gist create` 输出解析：输出可能多行（进度/URL），必须 grep URL 行，不能 `tail -1`；URL 缺 user 段 → `return 1` 回退本地路径，不崩溃。
2. gist 创建失败（网络/auth 缺 gist scope）→ 回退本地路径文案（不崩溃），comment 仍发布（含本地路径提示）。
3. `set -u` 全局生效：所有新增变量先绑定再使用（`user`/`id`/`ratio` 等），杜绝第二个 `$name_`。
4. `--no-comment`/`--dry-run` 模式 P6 跳过，helper 位置移动不影响。
5. 多张截图循环：单张上传失败 `|| return 1` 隔离，不中断后续。
6. `analyze_bmp.py`：纯黑→纯黑 占比 0% → frozen（正确）；纯黑→全白 占比 100% → 变化（正确）；`--diff-ratio` 缺省 → 旧均值行为。
7. per-shot deadline 缺省兼容：旧 shot plan 无 `deadline_s` → 全局 `max_wall_seconds`。
8. `deadline_s` 解析失败（非 int）→ GDScript `int()` 转 0 → 走全局 deadline，不 crash。
9. 全局 120s 仍是总上限 —— per-shot 300s 只放宽 03_gameover 自身的等待，不无限（防 CI 卡死）。

## 7. 验证步骤（implement 阶段执行顺序）

1. `python3 -m pytest tests/pipeline/` —— 基线 104 用例全绿（改前）。
2. 改 `analyze_bmp.py` → 跑 `test_e2e_analyze.py` 新用例。
3. 改 `run-e2e-review.sh` → `bash -n scripts/run-e2e-review.sh` + 跑 `test_e2e_runner.py`。
4. 改 `e2e_capture.gd` / `e2e_shots.json` → `godot --path mini-pong/ --headless --quit`（AC5）。
5. 全量 `python3 -m pytest tests/pipeline/` 回归。
6. 有环境条件时：用 #371 真实两帧（`docs/e2e-evidence/358/` 的 01_title/02_midgame.png，同款霓虹暗底）验证 AC3；`--dry-run` 验证 P6 comment 构建；真实 run 验证上传（AC2/AC4）。

## 8. 不做的事（明确排除）

- 不改 `mini-pong/gdscripts/`、`scenes/`、`project.godot`（class A 红线，PRD 约束）。
- 不新建 upload 独立脚本（PRD §4.1-B 否：单文件改动足够）。
- 不全局延长 `max_wall_seconds`（PRD §4.4-B 否：拖慢所有 shot）。
- 不改 `ai_position_error`（PRD §4.4-C 否：改变对打节奏与证据质量）。
- 不降 `--min-delta`（PRD §4.3-B 否：均值仍被暗底稀释，且可能引入假变化误判）。
- 不删 4 重反假断言中的任何一道（PRD 沿用约束）。

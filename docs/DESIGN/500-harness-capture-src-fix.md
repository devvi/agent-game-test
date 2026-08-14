# DESIGN: [Fix] run-e2e-review.sh — CAPTURE_SRC worktree 优先 + L3 missed 门控

> **Parent Issue:** #500
> **Agent:** game-plan-agent
> **Date:** 2026-08-15
> **Approach:** A + A + A — CAPTURE_SRC worktree 优先（PRD §4.1-A）+ results.json missed 门控（§4.2-A，附 capture exit code 兜底）+ ANALYZE_SRC 一致性扩展（§4.3-A）—— 确认 PRD 推荐组合；否决 §4.1-B（只修 miss 不修模板盲区，AC1 无法满足）与 §4.2-B 单独使用（无 shot 级诊断，且崩溃时无 results.json 兜底更弱）
> **Reference PRD:** docs/PRD/500-harness-capture-src-fix.md（research PR #501，已合并）
> **上游方案:** docs/DESIGN/480-e2e-runner-fix.md §3.1.3（CAPTURE_SRC/ANALYZE_SRC 双 worktree 优先，已 MERGED 的设计资产）、`origin/impl/480-e2e-runner-fix` f6c379c（全量实现蓝本，PR #486 CLOSED 未 merge）、`origin/impl/491-rain-score-levels` 103a37c（missed-check 参考实现，PR #494 OPEN）
> **所有权:** `content_ownership: mechanical`（runner 基建修复，纯机械逻辑：模板来源解析 + results.json 消费，无任何品味决策）
> **深度:** depth/standard（Issue 无 depth 标签，按 #480/#476/#466 惯例）—— 文件域 4 个（run-e2e-review.sh / test_e2e_runner.py / docs/PLAN-e2e-verification-v2.md / framework/ARCHITECTURE.md），其中实现修改仅 2 个文件，未达 TASKS 阈值（10+ 文件 / 5+ 子系统迁移）→ **不产出 TASKS 文档**
> **并行上下文:** ① PR #494（impl/491）OPEN 未 merge —— 其 103a37c 已含 missed-check 最小块，main 尚无此逻辑 → 本 issue 必须实现该块且**与 103a37c 逐字一致**（两种 merge 顺序均安全，见 §1.3-2）；② PR #498（impl/495）OPEN 未 merge —— AC4 回归验证对象（模板 confirm_upgrade 改动）；③ #499 为重复 Issue（早 12 分钟创建，同根因）→ 本 PR 描述中引用，实现后 close

---

## 1. 架构概述

### 1.1 设计核心

**问题本质是两个叠加的 class A 基建缺陷（harness 层，非游戏代码缺陷），使模板修改型 PR 的 L3 验证静默失真：**

1. **CAPTURE_SRC 固定指向 main 克隆（`$REPO_ROOT`）而非 PR worktree（`$WT`）** — `run-e2e-review.sh:57`。任何修改 `framework/templates/e2e_capture.gd` 的 PR（如 #498 的 confirm_upgrade 自动确认），其 L3 capture 实际跑的是 **main 版旧模板** → PR 的模板改动被静默跳过。
2. **L3 门控 false-pass** — P5 断言区（L220-248）只检查 PNG 存在性 + analyze_bmp 断言，**不读 capture driver 已写好的 `results.json` 的 `missed` 列表**；`local_capture=$?`（L217）捕获后仅 log 不参与门控 → 部分 shot 漏截时 summary.json 仍写 `L3_visual: pass`。

**修复架构（全部落在 runner 单文件 + 其 pipeline 测试 + 2 个文档，零新文件）：**

```
scripts/run-e2e-review.sh (354 行, 唯一实现修改文件)
  ├── P5 块内（worktree 创建后、cp 前）新增 CAPTURE_SRC 重解析:
  │     $WT/framework/templates/e2e_capture.gd 存在 → 用 PR 版; 否则回退 $REPO_ROOT
  ├── P5 块内新增 ANALYZE_SRC 重解析（一致性扩展, PRD §4.3-A）:
  │     $WT/scripts/e2e/analyze_bmp.py 存在 → 用 PR 版; 否则回退 $SCRIPT_DIR
  ├── P5 VISUAL_FAIL=0 初始化后新增 results.json missed 门控:
  │     results.json 存在且 missed 非空 → VISUAL_FAIL=1（与 impl/491 103a37c 逐字一致）
  │     results.json 缺失且 capture exit≠0 → VISUAL_FAIL=1（exit code 兜底, PRD §4.2 A+B 组合）
  └── 新增 log "  capture source: $CAPTURE_SRC"（可观测性 + pipeline 测试断言点, 对齐 "plan source" 既有日志模式 L190）
```

设计哲学：

1. **"用 PR 版本跑 PR" 原则完整落地** — PLAN_SRC（L188-189）已 worktree 优先，本 issue 把同一模式补齐到 CAPTURE_SRC 与 ANALYZE_SRC；常规 PR（worktree 无模板差异）回退 REPO_ROOT，行为与现状逐位一致（零回归红线）。
2. **capture driver 是权威输出源，runner 只消费不重复实现** — `e2e_capture.gd` 已写 `results.json`（含 `missed` 数组，L374-378）并在 any missed 时 exit 1（L43 文档契约）→ runner 读取 `missed` 数组即可，driver 零改动。
3. **双保险门控** — results.json（A）提供 shot 级诊断（missed 带 shot 名）；capture exit code（B）兜底 results.json 缺失场景（capture 崩溃未写完）。A 优先，B 仅在 A 不适用时生效（PRD §5.2-8）。
4. **机械可测** — 模板来源 = 文件存在性判定（纯 shell）；missed 门控 = JSON 数组长度判定（纯 python3 stdlib）→ fake-godot 注入可端到端断言，无需真实渲染。

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main @ 304dee2） | 设计裁决 |
|---------|--------------------------|---------|
| CAPTURE_SRC 固定 REPO_ROOT（L57） | ✅ `run-e2e-review.sh:57` `CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"`；唯一消费点在 L213 `cp "$CAPTURE_SRC" "$OUT/capture.gd"` | ⚠️ **关键裁决**：worktree-first 重解析**不能放 L57** —— L57 在 P1 worktree add（L183 附近）之前执行，此时 `$WT` 尚不存在，`[ -f "$WT/..." ]` 恒假 → 恒回退 REPO_ROOT → **照 PRD §4.1-A 字面"L57 2 行"实现 = 无效修复**。正确位置：P5 块内（worktree 创建后）重解析（§3.1.1，与 f6c379c 同款） |
| PLAN_SRC 已有 worktree 优先模式（L188-189） | ✅ `PLAN_SRC="${E2E_PLAN_PATH:-$WT/$SUBPROJECT/e2e_shots.json}"` + `[ -f ] ||` 回退 | CAPTURE_SRC/ANALYZE_SRC 采用同一 `[ -f ] ||` 回退惯用法 |
| results.json 位于 `$OUT/shots/results.json` | ✅ capture 的 `out_dir` 注入 = `$OUT/shots`（L204-210 注入 plan.json）；`e2e_capture.gd` `_write_results()` 写 `_out_dir/results.json`（L374-378） | 门控读取路径 = `"$OUT/shots/results.json"`，与 impl/491 读取位置一致 |
| exit 1 = any missed | ✅ `e2e_capture.gd` L42-43 文档契约（`Exit 0 = all shots captured, 1 = any missed`） | exit code 作为 results.json 缺失时的兜底信号 |
| L3 门控不读 missed → false-pass | ✅ L220-248 无 results.json 读取；L217-218 `local_capture=$?` 仅 log；L222 `ls` 非空即过 | VISUAL_FAIL=0 后插入 missed 门控（§3.1.2） |
| analyze_bmp.py 来自 SCRIPT_DIR（REPO_ROOT） | ✅ L234 `python3 "$SCRIPT_DIR/e2e/analyze_bmp.py"`；⚠️ 测试 fixture（test_e2e_runner.py setUp）**不创建** `scripts/e2e/analyze_bmp.py`，其 SCRIPT_DIR 经 BASH_SOURCE 解析 = 真实仓库 scripts/ → 回退路径天然成立 | ANALYZE_SRC worktree 优先 + 回退 `$SCRIPT_DIR`（§3.1.1） |
| PR #494 未 merge → missed 块需本 issue 实现 | ✅ `gh pr view 494` → state=OPEN, mergedAt=null（2026-08-15 03:0x 复核） | 实现块与 impl/491 `103a37c` 逐字一致（merge 顺序安全，§1.3-2） |
| fake godot 不写 results.json | ✅ `FAKE_GODOT_SRC`（test_e2e_runner.py L52-67）`--display-driver` 分支只写 PNG 不写 results.json | 扩展 FAKE_GODOT_SRC：`cfg["results_json"]` 键存在时写 results.json（默认不写 → 现有 12+ 用例零影响）（§3.2） |
| `--skip-visual` / dry-run 语义不变 | ✅ P5 整块被 `if [ "$SKIP_VISUAL" = "1" ]` / `[ "$DRY_RUN" = "0" ]` 守卫 | 新逻辑全部在 P5 块内 → 两语义天然不变（§5-4/5） |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立发现）

**裁决 1（关键）：CAPTURE_SRC/ANALYZE_SRC 的 worktree-first 解析必须发生在 P5 块内，而非脚本顶部 L57。** PRD §4.1-A 展示的"L57 2 行"写法若照字面落地是**无效修复**（L57 执行时 `$WT` 尚不存在 → 恒回退）。正确实现 = L57 保持 REPO_ROOT 默认值声明不变，P5 块内（P1 worktree add 成功、cp 之前）重新解析 worktree-first + 回退（与 `f6c379c` 在 P5 块内重解析的写法一致，该实现已被 #480 的 167 测试验证过）。同时新增 `log "  capture source: $CAPTURE_SRC"` —— 这是 pipeline 测试断言"选了哪个模板"的观测点（对齐 L190 的 `plan source` 日志模式）。

**裁决 2：missed 门控 = results.json 权威（A）+ capture exit 兜底（B），且 A 块与 impl/491 `103a37c` 逐字一致。** 理由：① impl/491 分支（PR #494）已实现并 review APPROVED，逐字一致保证两种 merge 顺序均无冲突 —— #494 先 merge 则 main 已有 A 块、本 issue 只需补 B 兜底（elif 追加，非冲突修改）；本 issue 先 merge 则 #494 merge 时 A 块 diff 为空（已存在）。② B 兜底只在 `results.json` **缺失**时生效（`elif`），避免与 A 的权威语义打架（PRD §5.2-8：A 优先）。

**裁决 3：ANALYZE_SRC 一并 worktree 优先（采纳 PRD §4.3-A）。** 理由：① 与 CAPTURE_SRC 同一模式，实现成本 ~3 行；② #480 设计资产（DESIGN §3.1.4a 偏差记录）已含且验证过；③ 消除下一轮同类 review 发现（analyze 修改型 PR 的断言盲区）；④ 超出 issue body 字面范围 → **PR 描述中注明"含 ANALYZE_SRC 一致性扩展"**。

**裁决 4：测试注入扩展 FAKE_GODOT_SRC 而非预写 results.json。** 新增用例需要"capture 后存在 results.json"这一状态 —— 预写方案不可行（runner 启动时 `mkdir -p "$OUT/shots"`，且 subprocess 一次性运行无法中途注入）。扩展方案：FAKE_GODOT_SRC 的 `--display-driver` 分支在写 PNG 后检查 `cfg["results_json"]`（dict），存在则写入 `out_dir/results.json`；**默认无该键 → 不写 → 现有 12+ 用例行为零变化**（PRD §5.3-3 兼容红线）。

---

## 2. 新组件

**无新文件**（与 #485/#491 同款 class：修复全落既有文件）。新增逻辑 = 3 个 shell 代码块 + 1 个测试注入扩展，全部内嵌于既有文件，无新类/新节点/新脚本：

| 逻辑块 | 宿主 | 性质 |
|--------|------|------|
| CAPTURE_SRC / ANALYZE_SRC worktree-first 重解析 | `run-e2e-review.sh` P5 块内 | 文件存在性选择（纯 shell） |
| results.json missed 门控（A + B 兜底） | `run-e2e-review.sh` P5 块内 | JSON 数组消费（python3 stdlib） |
| FAKE_GODOT_SRC `results_json` 注入 | `test_e2e_runner.py` 模块常量 | 测试夹具扩展 |

---

## 3. 既有组件修改

### 3.1 `scripts/run-e2e-review.sh`（修改 — 唯一实现修改文件，354 行）

#### 3.1.1 P5 块内 CAPTURE_SRC / ANALYZE_SRC worktree-first 重解析

**位置：** P5 块 `if [ "$VISUAL" != "fail" ] && [ "$DRY_RUN" = "0" ]` 内、`maybe cp "$CAPTURE_SRC" "$OUT/capture.gd"`（L213）**之前**插入（L57 保持默认声明不动）：

```bash
    # #500: 用 PR worktree 的 capture 模板 + analyze 脚本（"用 PR 版本跑 PR"）。
    # worktree 内缺失（常规 PR 未改基建文件）→ 回退 REPO_ROOT，行为与现状一致。
    CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"
    [ -f "$CAPTURE_SRC" ] || CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"
    ANALYZE_SRC="$WT/scripts/e2e/analyze_bmp.py"
    [ -f "$ANALYZE_SRC" ] || ANALYZE_SRC="$SCRIPT_DIR/e2e/analyze_bmp.py"
    log "  capture source: $CAPTURE_SRC"
    log "  analyze source: $ANALYZE_SRC"
```

**配套修改：** L234 `python3 "$SCRIPT_DIR/e2e/analyze_bmp.py" "$png" "${args[@]}"` → `python3 "$ANALYZE_SRC" "$png" "${args[@]}"`。

> 参考实现对齐：与 `origin/impl/480-e2e-runner-fix` f6c379c 的 P5 重解析块（`CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"; [ -f "$CAPTURE_SRC" ] || CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"` + ANALYZE_SRC 同款）**逐字一致**，仅新增 2 行 source log。

#### 3.1.2 P5 块内 results.json missed 门控（A 权威 + B 兜底）

**位置：** `VISUAL_FAIL=0`（L221）之后、PNG 存在性检查（L222 `if [ -z "$(ls ...)" ]`）**之前**插入：

```bash
    # ── #500: missed-shot → L3 fail（results.json 权威；capture exit 兜底）──
    if [ -f "$OUT/shots/results.json" ]; then
      MISSED=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("missed",[])))' "$OUT/shots/results.json" 2>/dev/null || echo 1)
      if [ "$MISSED" != "0" ]; then
        log "❌ $MISSED shot(s) missed — VISUAL_FAIL (results.json)"
        VISUAL_FAIL=1
      else
        log "✅ results.json: 0 missed"
      fi
    elif [ "$local_capture" != "0" ]; then
      log "❌ capture exit=$local_capture with no results.json — VISUAL_FAIL (exit fallback)"
      VISUAL_FAIL=1
    fi
```

> 参考实现对齐：A 块与 `origin/impl/491-rain-score-levels` 103a37c **逐字一致**（merge 顺序安全，§1.3-2）；B 兜底为本 issue 按 PRD §4.2"建议 A + B 组合"新增的 elif 分支（仅 3 行）。

#### 3.1.3 修改汇总（行级契约）

| 位置 | 改动 | 性质 |
|------|------|------|
| L57 | 保持 `CAPTURE_SRC="$REPO_ROOT/..."` 默认声明 | **不动**（重解析在 P5，裁决 1） |
| P5 块内（L212-213 之间） | 插入 CAPTURE_SRC/ANALYZE_SRC 重解析 + 2 行 source log | 新增 ~7 行 |
| L234 | `"$SCRIPT_DIR/e2e/analyze_bmp.py"` → `"$ANALYZE_SRC"` | 修改 1 行 |
| L221 后（L222 前） | 插入 results.json missed 门控（A + B） | 新增 ~12 行 |

### 3.2 `tests/pipeline/test_e2e_runner.py`（修改 — FAKE_GODOT_SRC 扩展 + 新增用例）

#### 3.2.1 FAKE_GODOT_SRC 扩展（results.json 注入，默认不写）

`FAKE_GODOT_SRC` 的 `--display-driver` 分支（L52-67）在 PNG 写入循环后追加：

```python
        if "results_json" in cfg:
            with open(os.path.join(out_dir, "results.json"), "w") as f:
                json.dump(cfg["results_json"], f)
```

**兼容红线：** 默认 FAKE_CONFIG 无 `results_json` 键 → 不写 → 现有 12+ 用例（含 `test_all_layers_pass_and_worktree_cleaned` 的 L3=pass 断言）零影响。

#### 3.2.2 新增 5 用例（见 §9 Scenario A，TC1-5）

- TC-1 CAPTURE_SRC worktree 优先（模板修改型 PR）
- TC-2 CAPTURE_SRC 回退（常规 PR）
- TC-3 results.json missed 非空 → L3 fail
- TC-4 results.json 0 missed → L3 pass
- TC-5 ANALYZE_SRC worktree 优先（marker 断言）

> 用例均复用既有 `RunnerTestBase`（fake git repo + fake godot + 环境注入），不破坏现有结构。

### 3.3 `docs/PLAN-e2e-verification-v2.md`（修改 — 文档同步）

P5 L3 视觉描述（L65 附近）补两处说明：

1. **P5 资源来源**：`CAPTURE_SRC`/`ANALYZE_SRC` worktree 优先（PR 版），缺失回退 REPO_ROOT —— "用 PR 版本跑 PR" 原则覆盖 capture 模板与 analyze 断言脚本
2. **L3 门控**：P5 断言后读取 `results.json` 的 `missed` 列表，非空 → L3 fail（含 capture exit 兜底）

### 3.4 `framework/ARCHITECTURE.md`（修改 — 契约补录）

本地验证层 L3 节（L160 附近）的失败协议说明中补一行：

> **L3 门控契约（#500）**：capture 驱动写 `results.json`（含 `missed` 数组，any missed → exit 1）；runner 消费该数组，`missed` 非空 → `L3_visual: fail`（杜绝漏截假绿）。

### 3.5 文件清单汇总

| 类别 | 文件 | 变更 |
|------|------|------|
| **修改** | `scripts/run-e2e-review.sh` | P5 资源 worktree 优先 + missed 门控（§3.1） |
| **修改** | `tests/pipeline/test_e2e_runner.py` | FAKE_GODOT_SRC 注入扩展 + 5 用例（§3.2） |
| **修改** | `docs/PLAN-e2e-verification-v2.md` | P5 资源来源 + missed 门控说明（§3.3） |
| **修改** | `framework/ARCHITECTURE.md` | L3 门控契约补录（§3.4） |
| **新增** | — | 无新文件 |
| **删除/废弃** | — | 无 |
| **受影响测试** | `tests/pipeline/test_e2e_runner.py` | 既有 12+ 用例保持全绿（回归红线） |

---

## 4. 数据流

### Flow 1: 模板修改型 PR 正常路径（修复后 — AC1/AC4 主路径）

```
review 主工作区 runner
  ├── PLAN_SRC   = $WT/mini-pong/e2e_shots.json        ← PR 版 (含 confirm_upgrade) ✅
  ├── CAPTURE_SRC = $WT/framework/templates/e2e_capture.gd ← PR 版 (含 _confirm_upgrade_if_visible) ✅
  ├── ANALYZE_SRC = $WT/scripts/e2e/analyze_bmp.py     ← PR 版 (若 PR 改了) / 回退 SCRIPT_DIR
  │     └── capture 跑 PR 模板 → confirm_upgrade 注入 → 3/3 捕获, exit 0
  ├── results.json 读取: missed == [] → log "✅ results.json: 0 missed"
  └── L3 = pass ✅（且是"PR 代码"的 pass，非 main 模板的假 pass）
```

### Flow 2: 常规 PR 回退路径（修复后行为 == 现状）

```
常规 impl PR（未改 framework/templates/ 与 scripts/e2e/）
  ├── $WT/framework/templates/e2e_capture.gd 不存在 → CAPTURE_SRC 回退 $REPO_ROOT/... ✅
  ├── $WT/scripts/e2e/analyze_bmp.py 不存在 → ANALYZE_SRC 回退 $SCRIPT_DIR/e2e/... ✅
  └── capture 跑 main 模板 + main 断言脚本 → 行为与修复前逐位一致（零回归）
```

### Flow 3: 失败路径 — missed shot 判红（修复后 — AC2 主路径）

```
模板修改型 PR + 部分 shot 漏截（deadline/状态未达）
  ├── capture 写 results.json: missed = ["03_gameover"], exit 1
  ├── [ -f results.json ] 命中 → MISSED=1 → log "❌ 1 shot(s) missed" → VISUAL_FAIL=1
  ├── PNG 检查: 01/02 有 PNG → ls 非空（旧逻辑此处会放行）
  └── VISUAL="fail" → summary.json L3_visual: fail → exit 1 ✅（真红, 不再假绿）
```

### Flow 4: 边界路径 — capture 崩溃（无 results.json）兜底

```
capture 异常崩溃（未写完 results.json, 无 PNG）
  ├── [ -f results.json ] 不命中 → elif [ "$local_capture" != "0" ] 命中 → VISUAL_FAIL=1
  └── 即使崩溃 exit code 恰为 0（罕见）, PNG ls 检查仍判 fail（双保险, PRD §5.2-6）
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | worktree 内模板缺失（常规 PR 未改基建文件） | `[ -f "$CAPTURE_SRC" ] ||` 回退 REPO_ROOT，行为与现状逐位一致（Flow 2） |
| 2 | `results.json` 不存在（capture 崩溃未写完） | `[ -f ]` 不命中 → `elif [ "$local_capture" != "0" ]` 兜底判 fail；exit 0 时 PNG 检查兜底（Flow 4） |
| 3 | `results.json` 存在但 JSON 解析失败 / python 缺失 | `python3 -c ... || echo 1` → MISSED=1 → 保守 fail（PRD §5.3-1） |
| 4 | `--skip-visual` | 整个 P5 块（含新逻辑）被 `if [ "$SKIP_VISUAL" = "1" ]` 守卫 → 语义不变，L3=skip |
| 5 | dry-run | 新逻辑在 `[ "$DRY_RUN" = "0" ]` 分支内 → 不执行选择/读取/门控 |
| 6 | `missed` 为 `[]` 但 PNG 缺失（capture 写入后 PNG 被清） | PNG ls 检查仍判 fail（双保险，不降级） |
| 7 | 模板修改型 PR 但 worktree 与 PR HEAD 延迟同步（fetch 竞态） | P1 worktree add 基于最新 fetch；worktree-commit.sh 提交前 merge main 兜底（PRD §5.2-7） |
| 8 | `local_capture` 非零但 results.json 0 missed（capture 自愈场景） | A 优先：以 results.json 为准，exit code 仅作缺失兜底（`elif` 结构天然保证） |
| 9 | PR #494 先 merge（main 已含 A 块） | A 块 diff 为空，本 issue 仅补 B 兜底 elif + CAPTURE_SRC + 测试 → 非冲突追加 |
| 10 | 本 issue 先 merge，#494 后 merge | A 块逐字一致 → #494 merge 时该块 diff 为空，无冲突（裁决 2） |

---

## 6. 逐组件配置（implement 契约速查）

| 组件 | 关键行（main @ 304dee2） | 契约 |
|------|------------------------|------|
| `run-e2e-review.sh` L57 | `CAPTURE_SRC="$REPO_ROOT/..."` 默认声明 | **不动** |
| `run-e2e-review.sh` L188-189 | PLAN_SRC worktree 优先（既有） | 只读参考，不改 |
| `run-e2e-review.sh` L213 前 | P5 块内重解析插入点 | CAPTURE_SRC/ANALYZE_SRC + 2 log（§3.1.1） |
| `run-e2e-review.sh` L221-222 之间 | missed 门控插入点 | A + B 块（§3.1.2） |
| `run-e2e-review.sh` L234 | analyze_bmp.py 调用 | `"$SCRIPT_DIR/e2e/analyze_bmp.py"` → `"$ANALYZE_SRC"` |
| `e2e_capture.gd` L374-378 / L42-43 | results.json + exit 契约 | **只读参考，零改动** |
| `test_e2e_runner.py` FAKE_GODOT_SRC | `--display-driver` 分支 | 追加 `results_json` 注入（§3.2.1） |
| `test_e2e_runner.py` RunnerTestBase | setUp / _run / _summary / _shots | 复用，不加新基类 |
| 环境注入 | E2E_REPO_ROOT / E2E_WORKTREE_ROOT / E2E_BRANCH / FAKE_CONFIG | 既有 6 变量不变，无新变量 |

---

## 7. 集成点

> **Status 约定：** ⬜ = pending（未接线）；✅ = connected（implement agent 验证）。implement agent 须在合入前更新本表。

| 集成 | 本组件 | 目标 | 如何 | 状态 |
|------|:---:|:---:|------|:---:|
| runner ↔ capture driver | `run-e2e-review.sh` P5 | `e2e_capture.gd` `results.json`（missed 数组） | 读 `$OUT/shots/results.json`，非空 → VISUAL_FAIL（driver 零改动） | ⬜ |
| runner ↔ PR worktree | P5 重解析 | `$WT/framework/templates/e2e_capture.gd` + `$WT/scripts/e2e/analyze_bmp.py` | `[ -f ] ||` 回退 REPO_ROOT/SCRIPT_DIR | ⬜ |
| runner ↔ pipeline 测试 | FAKE_GODOT_SRC | `tests/pipeline/test_e2e_runner.py` | `cfg["results_json"]` 注入 → 门控断言（TC3-4） | ⬜ |
| runner ↔ 模板来源可观测 | `log "  capture source: ..."` | P5 日志 / 测试断言 | 输出 `$OUT/capture.gd` 来源（TC1-2 断言点） | ⬜ |
| 本 issue ↔ PR #494（impl/491） | missed A 块 | main（merge 顺序） | 与 103a37c 逐字一致 → 双向无冲突（§5-9/10） | ⬜ |
| 本 issue ↔ PR #498（impl/495） | 回归验证对象 | AC4 | 修复后跑 `run-e2e-review.sh 498` → 用 PR 模板 3/3 pass（§9 Scenario B） | ⬜ |
| 本 issue ↔ #499（duplicate） | PR 描述 | close #499 | PR 描述引用 #499 为 duplicate，实现合并后 close | ⬜ |
| 文档契约 | ARCHITECTURE.md L3 节 | review agent 工作流 | 补 results.json 门控契约说明 | ⬜ |

---

## 8. 实施阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | run-e2e-review.sh：P5 块内 CAPTURE_SRC/ANALYZE_SRC 重解析 + 2 log + L234 改用 $ANALYZE_SRC | 0.25 天 |
| Phase 2 | P0 | run-e2e-review.sh：results.json missed 门控（A 逐字 103a37c + B 兜底 elif） | 0.25 天 |
| Phase 3 | P0 | test_e2e_runner.py：FAKE_GODOT_SRC 注入扩展 + TC1-5 | 0.5 天 |
| Phase 4 | P1 | 文档：docs/PLAN-e2e-verification-v2.md + framework/ARCHITECTURE.md | 0.25 天 |
| Phase 5 | P0 | 验证：`python3 -m unittest discover -s tests/pipeline -v` 全绿（既有 12+ + 新增 5）+ AC4 真实回归（PR #498 场景） | 0.5 天 |

依赖序：Phase 1 → 2 → 3 → 5（实现先行，测试跟随，文档最后，AC4 回归在 pipeline 全绿后）。Phase 4 可与 3 并行。

---

## 9. 测试用例描述

> 说明：本 issue 为 class A 基建修复，测试主体是 **pipeline 测试**（fake godot 端到端）；无游戏逻辑层（L1/L2）改动 → 无 mini-pong 测试改动。AC4 为真实 runner 回归场景。

### Scenario A: pipeline 测试（test_e2e_runner.py 新增 5 用例 — AC3）

> 夹具：既有 `RunnerTestBase`（temp git repo：main + impl/1-test 同源，主树 checkout main，worktree 由 runner P1 创建）；FAKE_GODOT_SRC 扩展后支持 `cfg["results_json"]` 注入。

- **TC-1（CAPTURE_SRC worktree 优先 — 模板修改型 PR）**：前置 —— 在 fixture 的 `impl/1-test` 分支上修改 `framework/templates/e2e_capture.gd` 内容为带 marker 的 PR 版（如 `# PR capture v2`）并 commit，checkout 回 main；运行 runner；**断言** `$OUT/capture.gd`（`$WORKTREE_ROOT/e2e-1/capture.gd`）内容 == PR 版 marker（而非 main 版 `# fake capture`）—— 证明 L3 用 PR 模板。
- **TC-2（CAPTURE_SRC 回退 — 常规 PR）**：fixture 保持默认（impl 分支未改模板）；运行 runner；**断言** `$OUT/capture.gd` 内容 == main 模板（`# fake capture`）—— 回退语义不变，行为与现状一致。
- **TC-3（results.json missed 非空 → L3 fail）**：`FAKE_CONFIG = {"results_json": {"shots": [], "missed": ["03_gameover"]}}`；运行 runner；**断言** exit code == 1 且 `summary.json` `layers.L3_visual == "fail"`，stdout 含 `shot(s) missed`。
- **TC-4（results.json 0 missed → L3 pass）**：`FAKE_CONFIG = {"results_json": {"shots": [{"name": "01_title"}], "missed": []}}`；运行 runner；**断言** exit code == 0 且 `L3_visual == "pass"`，stdout 含 `0 missed`。
- **TC-5（ANALYZE_SRC worktree 优先）**：前置 —— 在 `impl/1-test` 分支添加 `scripts/e2e/analyze_bmp.py`（打印唯一 marker 行到 stdout 后 exit 0）并 commit；运行 runner；**断言** `$OUT/P5-assert.log` 含 marker —— 证明 analyze 用了 PR 版断言脚本。

### Scenario B: 回归场景（AC4 — 真实 runner，非单测）

> 前置：PR #498（impl/495，含 confirm_upgrade 模板改动）OPEN。成本：每次真实跑 ~90-130s（PRD §8.2-4），可接受。

- **Test 1（修复前假绿复现）**：用 main 版 runner 跑 `scripts/run-e2e-review.sh 498`（模板修改型 PR）→ 预期：`$OUT/capture.gd` 为 main 模板（无 `_confirm_upgrade_if_visible`）→ 03_gameover 300s deadline miss → summary L3 仍 `pass`（false-pass 路径复现）。
- **Test 2（修复后 PR 模板生效）**：用修复版 runner 跑同一命令 → 预期：`$OUT/capture.gd` 来自 worktree（PR 模板）→ 3/3 捕获、0 missed、~90-130s → L3 `pass`（真 pass）。
- **Test 3（旧模板反向验证）**：临时将 P5 重解析指向 REPO_ROOT（模拟旧行为）→ 预期：missed 非空 → L3 `fail`（missed 门控生效，诚实失败）。

### Scenario C: 既有回归（验证网，不改动）

- 既有 `tests/pipeline/test_e2e_runner.py` 12+ 用例（TestRunnerFlow / TestRunnerP6Comment）全部保持全绿 —— 兼容红线：FAKE_GODOT_SRC 默认不写 results.json、回退路径行为不变、`--skip-visual`/dry-run/`--no-comment` 语义不变。
- 全量跑法：`python3 -m unittest discover -s tests/pipeline -v`。

---

## 10. 验收条件映射（AC checklist，源自 Issue #500 完成定义）

| AC | 内容 | 设计落实 |
|----|------|---------|
| AC1 | `CAPTURE_SRC` 优先 `$WT/framework/templates/e2e_capture.gd`（PR 分支），缺失时 fallback `$REPO_ROOT/...` | §3.1.1 P5 块内重解析（裁决 1：必须在 worktree 创建后）+ §9 TC-1/TC-2 |
| AC2 | P5 断言后读取 `results.json`：`missed` 非空 → L3 = fail（不再 false-pass） | §3.1.2 A 块（逐字 103a37c）+ B 兜底 + §9 TC-3/TC-4 |
| AC3 | pipeline 测试覆盖（CAPTURE_SRC 选择逻辑 + results.json missed → L3 fail） | §3.2 注入扩展 + 5 用例（≥3 达标）+ §9 Scenario C 全绿 |
| AC4 | 回归：PR #498 场景重跑 — 用旧模板应 L3 fail，用 PR 模板应 3/3 pass | §9 Scenario B Test 1-3（真实 runner，~90-130s/次） |

**补充落实（PRD §3.5 文档 + §4.3 扩展）：**
- docs/PLAN-e2e-verification-v2.md P5 资源来源 + missed 门控说明（§3.3）
- framework/ARCHITECTURE.md L3 门控契约（§3.4）
- ANALYZE_SRC worktree 优先一致性扩展（§3.1.1 + TC-5），PR 描述注明
- 实现合并后 close #499（duplicate，PR 描述引用）

### 明确不修改（继承 PRD §1.4/§2.3/§3.1）

- `framework/templates/e2e_capture.gd` — **零改动**（results.json/missed/exit-1 契约已具备，runner 只消费）
- 游戏代码（`mini-pong/gdscripts/`、`scenes/`、`project.godot`、`mini-pong/e2e_shots.json`）— class A 基建约束，零改动
- 并发锁 / worktree 归属校验（#480 范围，PR #486 内容）— 本 issue 不纳入（与 PRD §1.4 范围一致，不借修复搭车）
- `--skip-visual` / dry-run / `--no-comment` / `--baseline` 语义 — 全部不变
- L57 默认声明、PLAN_SRC 逻辑（L188-189）— 不动
- 不新增任何文件（含测试文件：新用例落在既有 test_e2e_runner.py）
- 不引入新依赖（bash 既有 + python3 stdlib；无 jq/PIL/网络）

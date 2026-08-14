# PRD: [Fix] run-e2e-review.sh — CAPTURE_SRC 从 PR worktree 取模板 + L3 missed 门控

> **Issue:** #500
> **标签:** bug, workflow/research, priority/medium
> **Agent:** game-research-agent
> **日期:** 2026-08-15
> **深度:** depth/standard（Issue 无 depth 标签，按 #480/#476/#466 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 以研究期已执行的源码分析实验补齐）
> **所有权:** `content_ownership: mechanical`（runner 基建修复，纯机械逻辑，无品味决策）
> **来源:** PR #498 review（game-review-agent, 2026-08-15）——harness 缺陷跟踪，不 block PR #498（该 PR 已用 PR 模板直接复验 3/3 通过）
> **重复 Issue:** **#499（2026-08-14 18:40 创建，早 12 分钟）描述同一根因**（CAPTURE_SRC 从 main 而非 worktree 取模板）。#500 为 superset：除 CAPTURE_SRC 外还包含 L3 false-pass（results.json missed 未接线）+ pipeline 测试覆盖 + 回归场景。#499 仅带 `bug` 标签无 workflow 标签，未进流水线。**建议：#500 为规范修复载体，plan agent 实现后 close #499（或在 #500 PR 中引用 #499 为 duplicate）。**
> **约束:** class A 基建 —— 只改 `scripts/`、`framework/templates/`、`tests/pipeline/`、`mini-pong/e2e_shots.json` 等测试基建文件，**不改游戏代码**（`mini-pong/gdscripts/`、`scenes/`、`project.godot`）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：`scripts/run-e2e-review.sh`（本地 E2E 主 runner，#357 引入）存在 2 个叠加的 class A 基建缺陷，导致模板修改型 PR 的 L3 验证静默失真：**

1. **`CAPTURE_SRC` 固定指向 main 克隆（`$REPO_ROOT`），而非 PR worktree（`$WT`）** — `run-e2e-review.sh:57`：
   ```bash
   CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"
   ```
   任何修改 `framework/templates/e2e_capture.gd` 的 PR（如 #498 的 confirm_upgrade 自动确认），其 L3 capture 实际跑的是 **main 版旧模板** → PR 的模板改动被静默跳过，L3 结果不代表 PR 代码。**本 PR #498 实测：** orchestrator e2e run 的 `plan.json` 含 `confirm_upgrade`（来自 worktree 的 `e2e_shots.json`），但 `/tmp/e2e-498/capture.gd` 与 main 模板 diff 为空 → 旧模板无 `_confirm_upgrade_if_visible` → 升级窗口冻结 → 03_gameover 300s deadline miss。

2. **L3 门控 false-pass — 不读 `results.json` 的 `missed` 列表** — P5 断言循环（L220-248）只检查：① PNG 存在性（`ls "$OUT/shots/"*.png` 非空）；② `analyze_bmp.py` 逐张断言。**捕获驱动 `e2e_capture.gd` 已写入 `results.json`（含 `missed` 数组，L374-378）并在 miss 时 exit 1（L43），但 runner：**
   - `local_capture=$?`（L217）只 log 不使用；
   - 无任何 `results.json` 读取；
   - miss 的 shot 不产生 PNG，但**其他 shot 的 PNG 存在** → `ls` 检查通过 → L3 仍报 pass。**本 PR 实测：** 03_gameover deadline miss（无 PNG），01_title/02_midgame 有 PNG → summary.json 仍写 `L3_visual: pass`。

#### 预调查结果（bug pre-investigation，Patch 8/10 — issue body 已含根因，逐条验证源码）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | `CAPTURE_SRC` 从 main（REPO_ROOT）拷贝模板而非 PR worktree（$WT） | ✅ **Still broken（确认）** | `run-e2e-review.sh:57` `CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"` 固定主工作区；对照 L188-189 `PLAN_SRC` 已有 worktree 优先 + REPO_ROOT 回退模式，同一脚本内可借鉴 |
| 2 | L3 门控只看 PNG 存在性 + analyze_bmp 断言，不读 results.json missed → 假 pass | ✅ **Still broken（确认）** | L220-248 无 results.json 读取；L217 `local_capture=$?` 捕获后仅 log（L218）未用于门控；capture driver（e2e_capture.gd L374-378）确实写 `results.json` 且含 `missed` 数组、exit 1（L43） |
| 3 | PR #498 实测：0× confirm_upgrade → 03_gameover deadline 300001ms miss | ✅ **Confirmed** | `/tmp/e2e-498/capture.gd` == main 模板（diff 空）；`e2e_capture.gd` main 版无 `_confirm_upgrade_if_visible`（该函数只在 impl/495 分支 b09ea64 引入）；plan.json 已含 confirm_upgrade（worktree plan） |
| 4 | 同一 run 仍报 "P5 visual: pass" | ✅ **Confirmed** | 03_gameover miss 无 PNG，但 01/02 有 PNG → L222 `ls` 非空 → VISUAL_FAIL 不置位 → L243-244 `VISUAL="pass"` |
| 5 | 用 PR 模板直接重跑：3/3 捕获，零 missed，88.6s < 300s | ✅ **Confirmed** | PR #498 review 证据（review agent 手动以 PR 模板重跑） |

**无 stale claims。** 但有一条**历史上下文必须记录**：

| 历史事实 | 详情 |
|---------|------|
| **#480（2026-08-14）已设计并实现过本修复，但 PR #486 被 CLOSED 未 merge** | PRD #480 + DESIGN #480 已 MERGED（PR #483/#484，docs-only）；impl PR #486（`f6c379c`：worktree 归属校验 + 并发锁 + worktree-first P5 资源 + missed 检查，167 测试全绿）于 2026-08-14 14:20 **CLOSED 未 merge**，原因注释：*"clean-env 清理(2026-08-14): 重构后重新验证, 此 PR 关闭"* → 修复从未进入 main，缺陷原样保留 |
| **#466 的 9d6847f（capture template from PR worktree + fail L3 on missed）同样未上 main** | 该 commit 在 impl/466 分支，PR #475 亦 CLOSED 未 merge |
| **impl/491 分支（PR #494，OPEN，review APPROVED）已含 missed-check 最小实现** | `103a37c`/`12dcec2` 在 `run-e2e-review.sh` 加了 results.json missed → VISUAL_FAIL 块（读取 `$OUT/shots/results.json` 的 `missed` 数组）——但 PR #494 未 merge，main 上仍无此逻辑 |
| **#499 为 #500 的重复 Issue** | 2026-08-14 18:40 创建（早 12 分钟），同根因（CAPTURE_SRC），但仅 `bug` 标签无 workflow 标签；#500 是 superset（含 L3 false-pass + 测试 + 回归） |

### 1.2 预期行为（验收条件，源自 Issue #500 完成定义）

1. [ ] **AC1: CAPTURE_SRC worktree 优先** — `$WT/framework/templates/e2e_capture.gd` 存在时使用 PR 分支模板；缺失时 fallback `$REPO_ROOT/framework/templates/e2e_capture.gd`
2. [ ] **AC2: L3 missed 门控** — P5 断言后读取 `results.json`：`missed` 非空 → L3 = fail（不再 false-pass）
3. [ ] **AC3: pipeline 测试覆盖** — `tests/pipeline/test_e2e_runner.py` 新增用例覆盖 AC1/AC2（CAPTURE_SRC 选择逻辑 + results.json missed → L3 fail）
4. [ ] **AC4: 回归场景** — PR #498 场景重跑：用旧模板应 L3 fail，用 PR 模板应 3/3 pass

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 模板修改型 PR（改 `framework/templates/e2e_capture.gd`）被 review | 模板相关 PR（#498、#495 类） | runner 必须用 PR worktree 内模板跑 capture，否则 PR 模板改动静默未测 |
| B | capture 有 shot miss（deadline/状态未达） | 长对局/慢机器 | 部分 shot 漏截时 L3 必须 fail，而不是因其他 PNG 存在而假 pass |
| C | 旧 PR 未改模板（worktree 无模板差异） | 常规 impl PR | CAPTURE_SRC 回退 REPO_ROOT，行为与现状一致 |

### 1.4 技术约束（继承自 Issue #500 + #480 惯例）

| 约束 | 细节 |
|------|------|
| 范围 | class A 基建：`scripts/run-e2e-review.sh`、`framework/templates/e2e_capture.gd`（只读参考）、`tests/pipeline/test_e2e_runner.py` |
| 不改动 | 游戏代码（`mini-pong/gdscripts/`、`scenes/`、`project.godot`） |
| 语言 | Bash（macOS 13.4 `/usr/bin/env bash`，`set -u` 生效）+ Python3 stdlib |
| 测试基线 | `tests/pipeline/test_e2e_runner.py`（fake godot 注入）；改 runner 必须过 `tests/pipeline/` 全套（ARCHITECTURE.md D3） |
| 兼容红线 | worktree 模板缺失时回退 REPO_ROOT；dry-run 不执行 capture；`--skip-visual` 语义不变 |

---

## 2. 设计意图

### 2.1 为什么当前状态如此

| # | 现状 | 成因 | 历史 |
|---|------|------|------|
| 1 | CAPTURE_SRC 固定 REPO_ROOT | runner 从主工作区执行，`$REPO_ROOT` 是最容易获得的路径；"用 PR 版本跑 PR"原则只落实到了 PLAN_SRC（L188），CAPTURE_SRC 漏了 | #357 引入（864d2df）；#480 设计修复但 PR #486 被 clean-env 清理关闭；#466 分支 9d6847f 同款修复也未 merge |
| 2 | L3 只断言 PNG 存在性 | 设计假设 capture 驱动自身已保证 shot 完整性（exit 1 = any missed）；runner 层未接线消费该信息 | capture driver 的 missed 机制 #372 引入（93766f8）；runner 的 summary 层一直未读 results.json |
| 3 | #480 修复丢失 | 08-14 clean-env 重构把已实现 PR #486 关闭（"重构后重新验证"），但重新验证从未发生 → main 回归到缺陷态 | kanban 调度层重构（2026-08-14）；#486 关闭注释 |

### 2.2 为什么现在改

1. **模板修改型 PR 已现实化**：PR #498（impl/495）修改 `framework/templates/e2e_capture.gd`（confirm_upgrade 自动确认，34 行），其 L3 实测被旧模板污染（0× confirm_upgrade → 03_gameover miss），靠 review agent 手动以 PR 模板重跑才验证通过 —— 手动补偿不可持续
2. **L3 false-pass 会掩盖真实回归**：missed shot 时 summary 仍写 pass，下游 merge 决策依据失真（review agent 读到 pass 会误判 PR 视觉层通过）
3. **#480 的设计资产完整可用**：PRD #480 §4.2 Approach A（CAPTURE_SRC 双 worktree 优先）+ DESIGN #480 已定义清晰方案，且 impl/491 分支已有 missed-check 参考实现 —— 本 issue 是"重新落地已验证的设计"，非新设计

### 2.3 既有约束

| 约束 | 细节 |
|------|------|
| runner 从主工作区执行 | review agent 约定 `scripts/run-e2e-review.sh <PR_NUM>`；脚本内部创建 worktree |
| worktree 路径约定 | `/tmp/wt-impl-<PR_NUM>`（`E2E_WORKTREE_ROOT` 可覆盖） |
| 退出码约定 | 0=全过 / 1=层失败 / 2=pre-flight 失败 |
| 测试注入 | `RUNNER_GODOT` / `E2E_WORKTREE_ROOT` / `E2E_BRANCH` / `E2E_GH_REPO` / `E2E_DIFF_FILES` / `E2E_PLAN_PATH` |
| results.json 位置 | capture 的 `out_dir` = `$OUT/shots`（L203-210 注入 plan.json）→ `results.json` 位于 `$OUT/shots/results.json`（impl/491 分支读取位置一致） |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scripts/run-e2e-review.sh` | P5 资源来源 + L3 门控 | 修改：L57 CAPTURE_SRC worktree 优先 + fallback；P5 断言区（L220 前）插入 results.json missed 检查；L217-218 可选补 `local_capture` 门控兜底 |
| `tests/pipeline/test_e2e_runner.py` | runner 端到端测试 | 新增：CAPTURE_SRC 选择测试（worktree 优先 / 回退）、results.json missed → L3 fail 测试、results.json 0 missed → pass 测试 |
| `framework/templates/e2e_capture.gd` | capture driver | **只读参考**（不改）：其 results.json/missed 输出已存在（L374-378），runner 只需消费 |

### 3.2 新增文件

无（修复均在现有文件内）。

### 3.3 间接影响

| 模块 | 影响 |
|------|------|
| `scripts/e2e/analyze_bmp.py` | 无改动。⚠️ 同类缺陷注意：L234 的 `analyze_bmp.py` 也来自 `$SCRIPT_DIR`（REPO_ROOT）——分析脚本本身被 PR 修改时同样有"用 main 版跑 PR"盲区。#480 实现（f6c379c）曾加 ANALYZE_SRC worktree 优先，但因 PR #486 未 merge 未生效。本 issue 建议一并处理（见 §4.3 讨论），或至少记录为已知限制 |
| `docs/PLAN-e2e-verification-v2.md` | P5 资源来源描述需补充"worktree 优先 + results.json missed 门控"说明（文档更新） |
| review agent 工作流 | 修复后模板修改型 PR 的 L3 自动用 PR 模板；missed shot 自动判 fail，无需手动重跑补偿 |

### 3.4 数据流影响

```
模板修改型 PR（修复前）:
review 主工作区 runner (main 版)
  ├── PLAN_SRC = $WT/mini-pong/e2e_shots.json      ← PR 版 (含 confirm_upgrade) ✅
  └── CAPTURE_SRC = $REPO_ROOT/framework/templates/e2e_capture.gd  ← main 版 (无 _confirm_upgrade_if_visible) ❌
        └── capture 跑旧模板 → 升级窗口冻结 → 03_gameover deadline miss → 无 PNG
        └── P5 断言: 01/02 有 PNG → ls 非空 → L3 = pass ❌ (假绿)

模板修改型 PR（修复后）:
  ├── PLAN_SRC = $WT/mini-pong/e2e_shots.json      ← PR 版 ✅
  ├── CAPTURE_SRC = $WT/framework/templates/e2e_capture.gd  ← PR 版 ✅ (缺失回退 REPO_ROOT)
  │     └── capture 跑 PR 模板 → confirm_upgrade 注入 → 3/3 捕获
  └── results.json 读取: missed == [] → L3 = pass ✅
      或 missed 非空 → L3 = fail ✅ (真红)
```

### 3.5 需更新文档

- [x] `docs/PLAN-e2e-verification-v2.md`（P5 资源 worktree 优先 + missed 门控说明）
- [ ] `framework/ARCHITECTURE.md`（E2E 验证体系节补 results.json 门控契约）

---

## 4. 方案对比

### 4.1 CAPTURE_SRC 来源选择

#### Approach A: worktree 优先 + REPO_ROOT 回退（推荐）

**描述:** 对齐同文件 L188-189 `PLAN_SRC` 的既有模式：
```bash
CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"
[ -f "$CAPTURE_SRC" ] || CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"
```

| 维度 | 评价 |
|------|------|
| Pros | "用 PR 版本跑 PR"原则完整落地；模板修改型 PR 的 L3 自动用 PR 模板；回退语义与现状一致（旧 PR 未改模板 → 行为不变）；与 PLAN_SRC 模式对称，可读性高；#480 设计（PRD §4.2-A）+ impl/491 参考均已验证此写法 |
| Cons | 若 worktree 内模板存在但内容与 PR 分支不同步（git 状态异常）→ 用错版本；概率极低（worktree 由 P1 全新 checkout） |
| Risk | Low |
| Effort | 0.5 天（含测试） |

#### Approach B: 保持 REPO_ROOT + 校验 capture exit code

**描述:** 不动 CAPTURE_SRC，仅在 L217 后加 `[ "$local_capture" != "0" ] && VISUAL_FAIL=1`。

| 维度 | 评价 |
|------|------|
| Pros | 改动最小（3 行） |
| Cons | 模板盲区仍在：PR 的模板改动照样静默未测（capture 用 main 模板跑 PR plan 可能不 crash 但行为错误，如 #498 confirm_upgrade 缺失）；只解决"miss 判 fail"不解决"用错模板" |
| Risk | High（AC1 无法满足） |
| Effort | 0.25 天 |

**推荐 A**：CAPTURE_SRC worktree 优先是 AC1 唯一满足路径。B 只是 AC2 的兜底，不能替代 A。

### 4.2 L3 missed 门控

#### Approach A: 读 results.json 的 missed 数组（推荐）

**描述:** 在 P5 断言循环前（L220 前）插入：
```bash
if [ -f "$OUT/shots/results.json" ]; then
  MISSED=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("missed",[])))' "$OUT/shots/results.json" 2>/dev/null || echo 1)
  if [ "$MISSED" != "0" ]; then
    log "❌ $MISSED shot(s) missed — VISUAL_FAIL (results.json)"
    VISUAL_FAIL=1
  else
    log "✅ results.json: 0 missed"
  fi
fi
```
（与 impl/491 分支 `103a37c` 已实现的最小块逐字一致，可 cherry-pick。）

| 维度 | 评价 |
|------|------|
| Pros | 直接消费 capture driver 已产出的权威结果（`missed` 数组带 shot 名，可诊断）；与 #372 的 per-shot deadline 机制天然衔接；impl/491 已有参考实现 |
| Cons | 依赖 results.json 存在（capture 正常结束才写）；若 capture 异常崩溃（无 results.json）→ `[ -f ]` 不命中 → 依赖现有 PNG 检查兜底（此时通常也无 PNG → VISUAL_FAIL） |
| Risk | Low |
| Effort | 0.25 天（不含测试） |

#### Approach B: 用 capture exit code（`local_capture`）

**描述:** `[ "$local_capture" != "0" ] && VISUAL_FAIL=1`。

| 维度 | 评价 |
|------|------|
| Pros | 3 行实现；exit 1 覆盖所有 miss 场景 |
| Cons | 无 shot 级诊断信息（log 里只有 exit code）；若 capture 因其他原因非零退出（如 driver 内部 error）也判 fail —— 语义偏宽；且 **capture 崩溃时可能无 PNG 也无 results.json，A 的 [ -f ] 守卫比裸 exit code 更稳** |
| Risk | Med（语义过宽 + 诊断弱） |
| Effort | 0.25 天 |

**推荐 A**：results.json 是 capture driver 的官方契约输出（L42-43 文档明确），消费它比裸 exit code 更精确可诊断。**建议 A + B 组合兜底**：results.json 缺失时回退 exit code 检查（双保险），见 §5 边界。

### 4.3 ANALYZE_SRC（analyze_bmp.py）同类盲区 — 是否纳入

**背景:** L234 `python3 "$SCRIPT_DIR/e2e/analyze_bmp.py"` 来自 REPO_ROOT。若 PR 修改 analyze_bmp.py（如 #466/#476 曾改断言逻辑），同样"用 main 版跑 PR 断言"。#480 实现（f6c379c）曾含 ANALYZE_SRC worktree 优先（DESIGN §3.1.4a 偏差记录），但未 merge。

#### Approach A: 一并 worktree 优先（推荐）

**描述:** 与 CAPTURE_SRC 同模式：
```bash
ANALYZE_SRC="$WT/scripts/e2e/analyze_bmp.py"
[ -f "$ANALYZE_SRC" ] || ANALYZE_SRC="$SCRIPT_DIR/e2e/analyze_bmp.py"
```
L234 改用 `python3 "$ANALYZE_SRC"`。

| 维度 | 评价 |
|------|------|
| Pros | 同一哲学一次落实；消除断言脚本盲区；#480 已验证此偏差正确（"两种 merge 顺序均安全"） |
| Cons | 超出 issue body 字面范围（issue 只点名 CAPTURE_SRC）——需在 PR 描述中说明；改动量 +3 行 |
| Risk | Low（与 CAPTURE_SRC 同模式，回退语义安全） |
| Effort | +0.25 天 |

#### Approach B: 不纳入，记录为已知限制

**描述:** 仅修 issue body 点名的 CAPTURE_SRC + missed 门控，ANALYZE_SRC 留待后续。

| 维度 | 评价 |
|------|------|
| Pros | 严格按 issue 范围；改动最小 |
| Cons | 同类缺陷残留（analyze 脚本被改的 PR 仍有盲区）；#480 已设计过的修复再次搁置 |
| Risk | Med（缺陷残留，但当前无 analyze 修改型 PR 在途——#498 只改 capture 模板） |
| Effort | 0 |

**推荐 A**：理由——① 与 CAPTURE_SRC 同一模式，实现成本可忽略；② #480 设计资产已含，属于"落地已验证设计"而非范围蔓延；③ 消除下一轮同类 review 发现。plan agent 可在 PR 描述中注明"含 ANALYZE_SRC 一致性扩展"。

### 4.4 推荐汇总

| 子项 | 推荐 | 核心改动 |
|------|------|---------|
| CAPTURE_SRC | A: worktree 优先 + 回退 | `run-e2e-review.sh:57` 2 行 |
| L3 missed 门控 | A: results.json missed（+ B 兜底） | P5 区 ~8 行（impl/491 参考） |
| ANALYZE_SRC | A: 一并 worktree 优先 | `run-e2e-review.sh:234` 相关 3 行 |

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表）

- [x] **AC1: CAPTURE_SRC worktree 优先**
  - 验证：worktree 内存在模板（模板修改型 PR）→ P5 日志/产物显示 capture.gd 来自 $WT；`$OUT/capture.gd` 与 `$WT/framework/templates/e2e_capture.gd` 内容一致
  - 验证：worktree 无模板差异（常规 PR）→ 回退 REPO_ROOT，`$OUT/capture.gd` == main 模板
- [x] **AC2: L3 missed 门控**
  - 验证：构造 results.json 含 missed 非空（fake godot 注入）→ exit 1 + summary.json `L3_visual: fail`
  - 验证：results.json missed 为空 → L3 pass 不变
- [x] **AC3: pipeline 测试覆盖**
  - 验证：`tests/pipeline/test_e2e_runner.py` 新增 ≥3 用例（CAPTURE_SRC 优先 / CAPTURE_SRC 回退 / missed→fail / 0 missed→pass），`python3 -m unittest discover -s tests/pipeline` 全绿
- [x] **AC4: 回归场景**
  - 验证：对 PR #498 场景（模板修改型）重跑 runner —— 修复前（旧逻辑）L3 false-pass；修复后（worktree 优先 + missed 门控）用 PR 模板 3/3 pass；若模拟旧模板则 L3 fail

### 5.2 边界情况

1. worktree 内模板缺失（旧 PR 未改模板）→ CAPTURE_SRC 回退 REPO_ROOT，行为与现状一致
2. `results.json` 不存在（capture 异常崩溃，未写完）→ `[ -f ]` 不命中 → 依赖 PNG 检查 + `local_capture` 兜底（若加 B）判 fail
3. `results.json` 存在但 JSON 解析失败 → `python3 -c ... || echo 1` → MISSED=1 → fail（保守方向）
4. `--skip-visual` → 跳过整个 P5（含 CAPTURE_SRC/missed 逻辑），语义不变
5. dry-run → `maybe()` 包裹，不执行任何选择/读取
6. results.json 的 `missed` 数组为 `[]` 但 PNG 缺失（capture 写入后 PNG 被清）→ PNG 检查仍判 fail（双保险）
7. 模板修改型 PR 但 worktree 模板与 PR HEAD 有延迟同步（git fetch 竞态）→ P1 worktree add 基于最新 fetch，概率极低；worktree-commit 前 fetch 兜底
8. `local_capture` 非零但 results.json 0 missed（capture 自愈场景）→ 以 results.json 为准（A 优先），exit code 仅作兜底

### 5.3 失败路径

1. `python3 -c` 读取 results.json 时 python 缺失 → `|| echo 1` → 保守 fail
2. CAPTURE_SRC 两处均不存在（worktree 与 REPO_ROOT 都被删）→ `cp` 失败 → 现状行为（capture 无脚本可跑，PNG 检查 fail）
3. 新增测试与 fake godot 现有注入冲突 → 按 `test_e2e_runner.py` 既有模式扩展 FAKE_GODOT_SRC 或 plan 注入，不破坏现有 12+ 用例

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| PR #494（impl/491，含 missed-check 块） | OPEN（review APPROVED，未 merge） | **merge 顺序关键**：若 #494 先 merge，main 已含 missed-check 块（4.2-A 的代码已在），本 issue 只需 CAPTURE_SRC + 测试 + 验证；若本 issue 先 merge，需保证实现与 #494 分支逐字一致（impl/491 分支 `103a37c` 可 cherry-pick），避免 merge 冲突 |
| PR #498（impl/495，模板 confirm_upgrade） | OPEN（review APPROVED，未 merge） | 本 issue 修复后 #498 的 L3 自动用 PR 模板（回归场景 AC4 的实操对象）；#498 本身不依赖本 issue 才能 merge（已手动复验 3/3） |
| `tests/pipeline/test_e2e_runner.py` | 现有（fake godot 端到端） | 新增用例遵循既有注入模式（FAKE_GODOT_SRC / GAME_PLAN / RunnerTestBase） |

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| #499（重复 Issue） | High | 本 issue 实现后 close #499（duplicate），避免双修复 |
| 未来 analyze_bmp.py 修改型 PR | Low | 若本 issue 采纳 §4.3-A，盲区已消除；否则记录为已知限制 |

### 6.3 依赖链

```
#500 (本 issue: CAPTURE_SRC worktree 优先 + L3 missed 门控)
  │ 参考资产（已存在，非新设计）
  ├── PRD #480 (MERGED) + DESIGN #480 (MERGED) — 方案设计
  ├── impl/491 分支 103a37c (PR #494 OPEN) — missed-check 参考实现
  └── impl/480 分支 f6c379c (PR #486 CLOSED 未 merge) — 全量实现蓝本
  │ merge 顺序关注
  ├── PR #494 (impl/491) — 若先 merge 则 missed 块已在 main
  └── PR #498 (impl/495) — 回归验证对象
```

### 6.4 准备清单

- [ ] 确认 PR #494 是否已 merge（若已 merge，missed-check 块已在 main，实现范围缩小）
- [ ] 从 impl/491 分支 `103a37c` 提取 missed-check 块（若需）
- [ ] 从 impl/480 分支 `f6c379c` 提取 CAPTURE_SRC/ANALYZE_SRC worktree 优先写法（若需）
- [ ] 在 `tests/pipeline/test_e2e_runner.py` 新增用例
- [ ] 跑全量 pipeline 测试套件（`python3 -m unittest discover -s tests/pipeline -v`）

---

## 7. Spike / 实验

> 按 #480/#476/#466 惯例：Issue 无 depth 标签，按 depth/standard 处理，Section 7 以研究期已执行的源码分析实验补齐（非强制，但保留验证记录）。

### 实验 1: CAPTURE_SRC 缺陷路径复现（源码追踪）

- **问题**：main 版 runner 对模板修改型 PR 是否必然用旧模板？
- **方法**：读 `run-e2e-review.sh` L57（CAPTURE_SRC 固定 REPO_ROOT）+ L213（`cp "$CAPTURE_SRC" "$OUT/capture.gd"`）；对比 `git show origin/impl/495-e2e-gameover-deadline:framework/templates/e2e_capture.gd` 与 main 版 diff（34 行 confirm_upgrade）
- **结果**：确认。main 模板无 `_confirm_upgrade_if_visible`（b09ea64 只在 impl/495 分支）；runner L57 硬编码 REPO_ROOT → `cp` 得到 main 版 → capture 无 confirm_upgrade 注入。**缺陷路径成立**
- **影响**：CAPTURE_SRC 必须 worktree 优先（方案 4.1-A）

### 实验 2: L3 false-pass 路径验证（源码追踪）

- **问题**：missed shot 时 L3 是否真的假 pass？
- **方法**：读 `run-e2e-review.sh` L220-248（P5 断言）+ L217-218（`local_capture` 只 log 不用）；读 capture driver `e2e_capture.gd` L149-159（missed 收集）+ L374-378（results.json 写入）+ L43（exit 1 = any missed）
- **结果**：确认。miss 的 shot 无 PNG（L324 仅 saved 才写）；01/02 有 PNG → L222 `ls` 非空 → VISUAL_FAIL=0 → L243-244 `VISUAL="pass"`；`local_capture` 捕获后未参与门控；results.json 写了但无人读。**false-pass 路径成立**
- **影响**：L3 必须消费 results.json missed（方案 4.2-A）

### 实验 3: 参考实现可用性确认

- **问题**：impl/491 分支的 missed-check 块是否可直接复用？
- **方法**：`git show 12dcec2:scripts/run-e2e-review.sh | sed -n '215,260p'`（missed 块完整代码）；`git diff origin/main...origin/impl/491-rain-score-levels -- scripts/run-e2e-review.sh`
- **结果**：确认。`103a37c`/`12dcec2` 已含完整 missed-check 块（`[ -f "$OUT/shots/results.json" ]` + `missed` 数组长度判定 + VISUAL_FAIL 置位），读取路径 `$OUT/shots/results.json` 与 capture 实际写入位置（`out_dir`=`$OUT/shots`）一致。**可 cherry-pick 复用**
- **影响**：plan agent 直接引用 impl/491 分支实现，避免重复设计（注意 merge 顺序）

---

## 8. 延续上下文（交接给 plan agent）

### 8.1 系统状态

- `scripts/run-e2e-review.sh`（354 行）为唯一需要修改的 runner 文件；关键行：**L57（CAPTURE_SRC）**、**L217-218（local_capture 捕获未用）**、**L220-248（P5 断言循环，无 results.json 读取）**、L234（analyze_bmp.py 来自 SCRIPT_DIR）、L188-189（PLAN_SRC 已有 worktree 优先模式可对称借鉴）
- capture driver `framework/templates/e2e_capture.gd` 已具备全部所需输出：`results.json`（含 `missed` 数组，L374-378）、exit 1 = any missed（L43）—— **runner 只需消费，driver 零改动**
- `tests/pipeline/test_e2e_runner.py`：现有 12+ 用例（TestRunnerFlow / TestRunnerP6Comment），fake godot 不写 results.json —— 新增用例需扩展 FAKE_GODOT_SRC（可选写 results.json）或注入已有 results.json
- **#480 实现资产**：`origin/impl/480-e2e-runner-fix` 分支 `f6c379c` 含完整修复（并发锁 + 归属校验 + CAPTURE_SRC/ANALYZE_SRC worktree 优先 + missed 检查，167 测试全绿），但因 PR #486 未 merge 全部未上 main —— **plan agent 可直接参考该分支 diff，比从零设计更快且已被验证**

### 8.2 主要风险

1. **PR #494（impl/491）merge 顺序**：若 #494 先 merge，main 已含 missed-check 块（4.2-A 代码已存在），本 issue 只需 CAPTURE_SRC + 测试 + 回归验证；若本 issue 先 merge，missed 块实现必须与 impl/491 分支 `103a37c` 逐字一致（或直接 cherry-pick），避免 merge 冲突
2. **范围蔓延**：§4.3 ANALYZE_SRC 扩展超出 issue 字面范围 —— 若 plan agent 选择纳入，须在 PR 描述注明"一致性扩展"；若选择不纳入，须在 DESIGN 记录为已知限制
3. **测试注入兼容**：新增 results.json 相关用例必须尊重既有 FAKE_GODOT_SRC 注入模式（不破坏现有 12+ 用例）
4. **回归验证成本**：AC4 要求对 PR #498 场景重跑 —— 真实跑一次 E2E 约 90-130s，可接受；测试层用 fake godot 模拟即可覆盖

### 8.3 下一步（plan agent）

1. 先查 **PR #494 是否已 merge**（`gh pr view 494 --json state`）—— 决定 missed-check 块是"已存在需验证"还是"需实现"
2. 读 `docs/PRD/480-e2e-runner-fix.md` + `docs/DESIGN/480-e2e-runner-fix.md`（方案设计已定）+ `git show origin/impl/480-e2e-runner-fix` 分支 `f6c379c`（实现蓝本，重点 CAPTURE_SRC/ANALYZE_SRC worktree 优先写法）
3. 若需实现 missed 块：`git cherry-pick` 或参考 `origin/impl/491-rain-score-levels` 的 `103a37c` diff（仅 `scripts/run-e2e-review.sh` 部分）
4. DESIGN 输出：CAPTURE_SRC worktree 优先（L57）、results.json missed 门控（P5 区）、ANALYZE_SRC 决策（纳入/记录）、≥3 组新测试用例
5. 实施顺序建议：CAPTURE_SRC → missed 门控 → （可选）ANALYZE_SRC → 测试 → 回归
6. 验收跑法：`python3 -m unittest discover -s tests/pipeline -v` 全绿 + 对模板修改型 PR 跑真实 runner 验证 worktree 模板生效
7. **完成后 close #499**（duplicate）—— 在 PR 描述中引用

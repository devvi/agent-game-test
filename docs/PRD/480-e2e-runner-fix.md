# PRD: [Bug] 修复 e2e runner — worktree 归属校验 + P5 plan source + 并发单例

> **Issue:** #480
> **标签:** bug, priority/high, workflow/available
> **Agent:** game-research-agent
> **日期:** 2026-08-14
> **深度:** depth/standard（Issue 无 depth 标签，按 #476/#466/#372 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 以研究期已执行的源码分析实验补齐）
> **所有权:** `content_ownership: mechanical`（runner 基建修复，纯机械逻辑，无品味决策）
> **来源:** review agent 2026-08-14 13:20（PR #475 review，Class A 基建缺陷，非代码缺陷）
> **阻塞:** PR #475（issue #466）— 本 issue 修复后 #475 才可正常 review
> **约束:** class A 基建 —— 只改 `scripts/`、`framework/templates/`、`mini-pong/e2e_shots.json`、`tests/pipeline/` 等测试基建文件，**不改游戏代码**（`mini-pong/gdscripts/`、`scenes/`、`project.godot`）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：`scripts/run-e2e-review.sh`（本地 E2E 主 runner，#357 引入，commit `864d2df`）存在 2 个 class A 基建缺陷，导致并发 review 互相破坏 + PR 分支的 P5 修改无法生效：**

1. **trap cleanup 无 worktree 归属校验** — 并发实例 P0 die 时 `--force` 误删运行中实例的 worktree → L1 假失败（12 failed）
2. **runner 版本盲区** — review 在主工作区跑 main 版 runner，main 版无 PR 的 P5 修改（visual 透传 / worktree 模板优先 / missed 检查），且 `CAPTURE_SRC` 固定指向主工作区模板 → 用 main 模板跑 PR 的 require 数组（Array 形式）必然崩溃（`var req: Dictionary` ← Array）

#### 预调查结果（bug pre-investigation，Patch 8/10 — issue body 已含根因，逐条验证源码）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | trap cleanup 不校验 worktree 归属；并发实例 P0 die 时 `--force` 误删运行中实例的 worktree → L1 假失败 (12 failed) | ✅ **Still broken（确认）** | `run-e2e-review.sh:77-83` `cleanup()` 无条件执行 `git worktree remove "$WT" --force`（L80），无归属校验；L54 `WT="$WORKTREE_ROOT/wt-impl-$PR_NUM"` 仅按 PR 号键控；L134 并发第二实例 `die "worktree already exists"` → exit 2 → trap cleanup → 删除第一实例正在运行的 worktree |
| 2 | 主工作区 runner (main 版) 无 PR 的 P5 修改（visual 透传 / worktree 模板优先 / missed 检查） | ✅ **Still broken（确认）** | `run-e2e-review.sh:57` `CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"` 固定主工作区模板，无 worktree 优先；PR #475 分支（impl/466）runner diff 已加 `CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"` 优先 + visual config 透传（`--visual-config`）+ missed-shot 检查，但**只存在于 PR 分支，main 版没有** |
| 3 | P5 用 main 模板跑 PR 的 require 数组必然崩溃（`var req: Dictionary` ← Array） | ✅ **Still broken（确认）** | main 版 `framework/templates/e2e_capture.gd:278` `var req: Dictionary = d["require"]` 强类型；PR #475 分支 `mini-pong/e2e_shots.json` 的 `02_midgame.require` 已改为 **Array 形式**（require 数组化，#466）→ main 模板类型错误崩溃 |
| 4 | P5 plan source 回退 REPO_ROOT | ⚠️ **部分已满足** | L188 `PLAN_SRC="${E2E_PLAN_PATH:-$WT/$SUBPROJECT/e2e_shots.json}"` 已优先 worktree（worktree 内存在 PR 版 e2e_shots.json 时命中）；但 L189 fallback 仍到 `$REPO_ROOT/framework/templates/e2e_shots.json`，且 review 时 runner 本体（L57 CAPTURE_SRC + L199 resolve_plan.py + L213 capture 驱动）均来自主工作区 main 版 |

**无 stale claims、无已修复项**：`git log --oneline --all | grep 480` 无结果；`run-e2e-review.sh` 最近修改 `0c45f93`（#409）不含上述修复。

### 1.2 预期行为（验收条件，源自 Issue #480）

1. [ ] **AC1** trap cleanup 增加 worktree 归属校验 —— 只清理自己创建的 worktree
2. [ ] **AC2** P5 plan source 指向 worktree 内 `e2e_shots.json`（PR 分支的 shot plan，而非 main 模板）
3. [ ] **AC3** 并发单例防护（锁文件或 PID 校验）—— 同一 PR 同时只允许一个 runner 实例
4. [ ] **AC4** 并发跑两个 `run-e2e-review.sh` 实例互不干扰（验收场景）
5. [ ] **AC5** PR 分支 runner 用 PR 的 shot plan（验收场景）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | review agent 跑本地 E2E 验证 impl PR | 每次 impl PR | 主工作区 runner 创建 worktree 跑 L0-L3；若同一 PR 被并发触发（webhook 重放 / 多 agent），第二个实例必须优雅退出而非破坏第一个实例 |
| B | review 模板/shot plan 变更型 PR（如 #475） | 模板相关 PR | runner 必须用 PR worktree 内的 e2e_capture.gd + e2e_shots.json（worktree 优先），否则 main 版模板对 PR 的新格式（require 数组化）崩溃 |
| C | 长对局/慢机器上的重复 review | 偶发 | P0 失败（如 godot 缺失、branch fetch 失败）时 cleanup 只清理自己的残留，不波及其他实例 |

### 1.4 技术约束（继承自 Issue #480）

| 约束 | 细节 |
|------|------|
| 范围 | class A 基建：`scripts/run-e2e-review.sh`、`framework/templates/e2e_capture.gd`、`mini-pong/e2e_shots.json`、`tests/pipeline/test_e2e_runner.py` |
| 不改动 | 游戏代码（`mini-pong/gdscripts/`、`scenes/`、`project.godot`） |
| 语言 | Bash（macOS 13.4 `/usr/bin/env bash`，`set -u` 生效）+ Python3 stdlib |
| 测试基线 | `tests/pipeline/test_e2e_runner.py`（fake godot 注入的端到端 runner 测试）；改 runner 必须过 `tests/pipeline/` 全套（ARCHITECTURE.md D3） |

---

## 2. 设计意图

### 2.1 为什么当前状态如此

| # | 现状 | 成因 | 历史 |
|---|------|------|------|
| 1 | cleanup 无归属校验 | 设计假设 runner 单实例运行（P0 检查 `[ -d "$WT" ]` 即 die），从未考虑同 PR 并发 | #357 引入（864d2df）；#372 修复过 P6/阈值（93766f8），未触及并发 |
| 2 | CAPTURE_SRC 固定 REPO_ROOT | worktree 隔离（2026-08-13）只隔离了工作区，runner 脚本本身仍从主工作区执行 | worktree 隔离方案见 `docs/PLAN-worktree-isolation.md`；"用 PR 版本跑 PR"（worktree 优先）是 #466 review 才暴露的需求 |
| 3 | main 模板强类型 require | require 断言最初只有 Dictionary 单条件形式；#466 引入"require 数组化"（多条件 AND），模板改造只存在于 PR 分支 | #466（PR #475 未 merge）|

### 2.2 为什么现在改

1. **PR #475 被阻塞**：#475 的 review 需要 runner 支持 PR 版 shot plan（Array require + visual config），main 版 runner 跑必然崩溃 → #475 无法通过 review → #466 无法落地
2. **并发风险已现实化**：多 agent 并发（workflow `max_concurrent_issues: 4`）+ webhook 重放 → 同 PR 并发 runner 实例概率上升；误删 worktree 的后果是 L1 假失败（12 failed），污染 review 结论
3. **class A 基建纪律**：基建缺陷必须独立修复（`docs/PLAN-e2e-verification-v2.md` §5.4：A 类不计 cycle，生成独立 infra issue 跟踪）——本 issue 即该机制的产物

### 2.3 既有约束

| 约束 | 细节 |
|------|------|
| runner 从主工作区执行 | review agent 约定 `scripts/run-e2e-review.sh <PR_NUM>`；脚本内部创建 worktree |
| worktree 路径约定 | `/tmp/wt-impl-<PR_NUM>`（`E2E_WORKTREE_ROOT` 可覆盖） |
| 退出码约定 | 0=全过 / 1=层失败 / 2=pre-flight 失败 |
| 测试注入 | `RUNNER_GODOT` / `E2E_WORKTREE_ROOT` / `E2E_BRANCH` / `E2E_GH_REPO` / `E2E_DIFF_FILES` / `E2E_PLAN_PATH` |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scripts/run-e2e-review.sh` | P0 pre-flight + cleanup trap + P5 资源来源 | 修改：cleanup 归属校验 + 并发单例锁 + CAPTURE_SRC worktree 优先 + visual 透传 + missed 检查（并入 #475 分支 runner 修改） |
| `framework/templates/e2e_capture.gd` | require 断言 | 视 merge 顺序：若 #475 先 merge 则 main 模板已含 Array 支持，本 issue 无需改；否则本 issue 只修 runner（worktree 优先即可规避崩溃），模板归 #475 |
| `tests/pipeline/test_e2e_runner.py` | runner 端到端测试 | 新增：并发单例测试、归属校验测试、worktree 模板优先测试 |

### 3.2 新增文件

无（修复均在现有文件内）。

### 3.3 间接影响

| 模块 | 影响 |
|------|------|
| `scripts/e2e/resolve_plan.py` | 无改动（plan 解析逻辑已支持 shot 级字段透传） |
| `docs/PLAN-e2e-verification-v2.md` | P8 cleanup 描述需补充归属校验/单例说明（文档更新） |
| review agent 工作流 | 修复后 review #475 可正常跑通 |

### 3.4 数据流影响

```
并发场景（修复前）:
Runner-A (PR #466)                     Runner-B (PR #466, 并发触发)
  │ worktree add wt-impl-466              │ P0: [ -d "$WT" ] → true
  │ L1 运行中                             │ die "worktree already exists" exit 2
  │                                      │ trap cleanup EXIT
  │                                      │   └── worktree remove wt-impl-466 --force  ← 误删 A 的 worktree
  │ L1 假失败 (12 failed) ◄───────────────┘

版本盲区场景（修复前）:
review 主工作区 runner (main 版)
  ├── PLAN_SRC = $WT/mini-pong/e2e_shots.json   ← PR 版 (require: Array) ✅
  └── CAPTURE_SRC = $REPO_ROOT/framework/templates/e2e_capture.gd  ← main 版 (var req: Dictionary) ❌
        └── e2e_capture.gd 读 plan.json → _require_ok() → var req: Dictionary = d["require"] ← Array → 崩溃
```

### 3.5 需更新文档

- [x] `docs/PLAN-e2e-verification-v2.md`（P8 cleanup 归属校验说明）
- [ ] `framework/ARCHITECTURE.md`（若并发单例成为架构决策，补充到 E2E 验证体系节）

---

## 4. 方案对比

### 4.1 并发单例防护

#### Approach A: 锁文件 + PID 校验（推荐）

**描述:** P0 检查 `$WORKTREE_ROOT/.e2e-<PR_NUM>.lock`：存在且 PID 存活 → die "another instance running"（exit 2，**不触发 cleanup 删 WT**）；存在但 PID 死亡 → 回收（删旧锁重建）；不存在 → 创建锁文件写入 `$$`。cleanup 时删除锁。

| 维度 | 评价 |
|------|------|
| Pros | 简单可靠；同 PR 并发直接拒绝；stale 锁自动回收；macOS/Linux 通用 |
| Cons | 需处理原子创建（`mkdir` 原子性 > 文件写入）；锁与 worktree 生命周期需同步 |
| Risk | Low |
| Effort | 0.5–1 天 |

#### Approach B: 仅归属校验（cleanup 只删自己的）

**描述:** cleanup 前检查 worktree 是否由本实例创建（如 worktree 内放 `.e2e-owner` 标记文件含 PID，或记录本实例成功 `worktree add` 后才允许删）。

| 维度 | 评价 |
|------|------|
| Pros | 直接消除误删；实现最简 |
| Cons | 不阻止并发（第二个实例仍会 die，只是不再破坏第一个）；无法告知"已有实例在跑" |
| Risk | Med（只解决一半：破坏消除但并发浪费仍在） |
| Effort | 0.5 天 |

#### Approach C: flock(1) 系统锁

**描述:** `flock` 对锁文件加排他锁，第二个实例阻塞等待而非退出。

| 维度 | 评价 |
|------|------|
| Pros | 内核级原子；等待语义清晰 |
| Cons | macOS 自带 flock 行为与 Linux 有差异（BSD flock）；长对局 review 可能让第二实例挂起很久 |
| Risk | Med（平台差异 + 挂起语义） |
| Effort | 0.5 天 |

**推荐 A + B 组合**：锁文件（A）防并发启动 + 归属标记（B）兜底防误删（即使锁逻辑被绕过）。理由：A 提供明确拒绝语义，B 提供纵深防御；两者合计约 1 天，覆盖验收 AC1/AC3/AC4。

### 4.2 P5 资源来源（worktree 优先）

#### Approach A: CAPTURE_SRC + PLAN_SRC 双 worktree 优先（推荐）

**描述:** 同步 #475 分支 runner 的修改：`CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"` 存在则用，否则回退 REPO_ROOT；PLAN_SRC 保持 L188 的 worktree 优先。

| 维度 | 评价 |
|------|------|
| Pros | 与 #475 分支行为一致；"用 PR 版本跑 PR"原则落地；main 模板强类型崩溃路径消除 |
| Cons | 若 worktree 内模板缺失（旧 PR 未改模板）回退 main 版——行为与现在一致，可接受 |
| Risk | Low |
| Effort | 0.5 天 |

#### Approach B: 仅 PLAN_SRC worktree 优先（维持现状）

**描述:** 只保留 L188-189 现状，不动 CAPTURE_SRC。

| 维度 | 评价 |
|------|------|
| Pros | 零改动 |
| Cons | 崩溃路径仍在：PLAN 用 PR 版（Array require），CAPTURE 用 main 版（强类型）→ #475 仍无法 review |
| Risk | High（问题未解决） |
| Effort | 0 |

**推荐 A**：CAPTURE_SRC 必须 worktree 优先，否则验收 AC2/AC5 无法满足。

### 4.3 missed 检查与 visual 透传（#475 分支已有，并入 main runner）

**背景：** #475 分支的 runner diff 已包含 visual config 透传（shot 级 `visual` 字段 → `--visual-config`）和 missed-shot 检查（planned shot 必须有 PNG）。这两个是 #466 的功能依赖，但 **main 版 runner 没有**。

**方案：** 本 issue 将 #475 分支 runner 的这两段修改并入 main 版 runner（与 4.2 的 CAPTURE_SRC worktree 优先一起），使 main 版 runner 具备 review #466 类 PR 的能力。若 #475 先 merge，则 main 已含此修改，本 issue 只需验证。

| 维度 | 评价 |
|------|------|
| 并入方式 | 从 #475 分支 cherry-pick runner diff（仅 `scripts/run-e2e-review.sh` 部分）或按 #475 diff 手工同步 |
| Risk | Low（两段都是纯增量、向后兼容：visual 字段缺失时不加 flag，行为不变） |
| Effort | 0.5 天 |
| 替代方案 | 等 #475 merge 后再做本 issue —— 但 #475 被本 issue 阻塞（鸡生蛋），故必须在本 issue 并入 |

**推荐：** 在本 issue 并入 #475 分支的 runner 修改（worktree 模板优先 + visual 透传 + missed 检查），与并发单例修复同 PR 落地。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表）

- [x] **AC1: trap cleanup 归属校验** — 只清理自己创建的 worktree
  - 验证：手动 kill 运行中实例（P0 后、L1 前）→ 另一实例 worktree 完好
- [x] **AC2: P5 plan source 指向 worktree** — `$WT/$SUBPROJECT/e2e_shots.json` 存在时优先使用
  - 验证：P5 日志输出 plan source 为 worktree 路径
- [x] **AC3: 并发单例防护** — 同一 PR 第二实例启动即拒绝（exit 2，带明确报错）
  - 验证：后台起实例 A，再起实例 B → B 报 "another instance running"
- [x] **AC4: 并发两实例互不干扰** — 不同 PR 的实例并行互不影响（各自 worktree 独立）；同 PR 第二实例不破坏第一实例
  - 验证：PR #X 与 PR #Y 同时跑，均完成且 L1 结果正确
- [x] **AC5: PR 分支 runner 用 PR 的 shot plan** — 对含 e2e_shots.json 修改的 PR，capture 用 worktree 内 plan + 模板
  - 验证：对 #475 跑 runner，P5 日志显示 plan source = worktree 路径，capture 无类型错误

### 5.2 边界情况

1. 锁文件存在但 PID 已死（stale）→ 自动回收，正常启动
2. 锁文件存在且 PID 存活但进程已不是 runner（PID 复用）→ 校验进程命令行或启动时间戳（可选增强）
3. 同 PR 并发第二个实例 → exit 2 且 **不触发 cleanup 删 WT**
4. `--keep` 标志 → cleanup 不删 worktree 但删锁文件（锁是运行期资源）
5. `E2E_WORKTREE_ROOT` 自定义路径 → 锁文件路径跟随 WORKTREE_ROOT
6. worktree 模板不存在（旧 PR 未改模板）→ CAPTURE_SRC 回退 REPO_ROOT，行为与现状一致
7. 失败路径中 cleanup 多次触发（die 后 EXIT trap + 显式调用）→ 幂等（`[ -d "$WT" ]` 守卫已存在）
8. dry-run 模式 → 不创建锁、不删 worktree（`maybe()` 包裹）

### 5.3 失败路径

1. 锁文件创建失败（权限/磁盘）→ 报错 exit 2，不继续（避免无锁并发）
2. cleanup 时 worktree remove 失败 → 保留现状（`2>/dev/null` 静默），锁文件仍删除
3. 归属标记写入失败 → 视为未创建 worktree，cleanup 不删（保守方向）

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #466（视觉回归 E2E 断言） | OPEN（PR #475 被本 issue 阻塞） | 本 issue 修复后 #475 可 review；#475 merge 后 main 模板/plan 支持 Array require + visual config |
| `tests/pipeline/test_e2e_runner.py` | 现有（fake godot 端到端） | 新增用例需遵循现有注入模式 |

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| PR #475（#466 实现） | High | 被本 issue 阻塞；本 issue 并入 runner 修改后可正常 review |
| #476（L3 视觉回归修复） | High | 依赖 #466 的 L3 断言落地 |

### 6.3 依赖链

```
#480 (本 issue: runner 并发 + 版本盲区)
  │ 修复后
  ▼
PR #475 (#466 实现) ──► review 可跑通 ──► merge
  ▼
#476 (L3 断言修复) ──► main L3 全绿
```

### 6.4 准备清单

- [ ] 确认 #475 分支 runner diff 的并入范围（仅 `scripts/run-e2e-review.sh`）
- [ ] 在 `tests/pipeline/test_e2e_runner.py` 新增 3 组用例（并发单例 / 归属校验 / worktree 模板优先）
- [ ] 跑全量 pipeline 测试套件（`tests/pipeline/`）

---

## 7. Spike / 实验

> 按 #476/#466 惯例：Issue 无 depth 标签，按 depth/standard 处理，Section 7 以研究期已执行的源码分析实验补齐（非强制，但保留验证记录）。

### 实验 1: 并发破坏路径复现（源码追踪）

- **问题**：并发实例 P0 die 是否真的会误删运行中实例的 worktree？
- **方法**：读 `run-e2e-review.sh` L77-83（cleanup）+ L134（die 路径），确认 die → exit 2 → `trap cleanup EXIT` 链路
- **结果**：确认。`die "worktree already exists"` 在 L134，exit 2 后 EXIT trap 触发 cleanup，L80 无条件 `worktree remove --force`。**误删路径成立**
- **影响**：必须加归属校验 + 单例锁（方案 4.1 A+B）

### 实验 2: require 类型差异验证（main vs #475 分支）

- **问题**：main 模板对 PR 的 require 数组是否必然崩溃？
- **方法**：`git show origin/impl/466-e2e-visual-regression:mini-pong/e2e_shots.json` 解析 require 类型 vs main 版
- **结果**：main 版 `02_midgame.require` = dict（单条件）；#475 分支 = **list（数组化）**；main 模板 `e2e_capture.gd:278` `var req: Dictionary = d["require"]` 对 list 赋值 → GDScript 类型错误。**崩溃路径成立**
- **影响**：CAPTURE_SRC 必须 worktree 优先（方案 4.2-A）

### 实验 3: #475 分支 runner 修改确认

- **问题**：main 版 runner 是否真的缺 #475 的 P5 修改？
- **方法**：`gh pr diff 475` 提取 runner 段
- **结果**：#475 分支 runner 含 3 段 main 版没有的修改：worktree 模板优先（CAPTURE_SRC）、visual config 透传（`--visual-config`）、missed-shot 检查。**版本盲区成立**
- **影响**：本 issue 并入这三段（§4.3）

---

## 8. 延续上下文（交接给 plan agent）

### 8.1 系统状态

- `scripts/run-e2e-review.sh`（354 行）为唯一需要修改的 runner 文件；关键行：L54（WT 路径）、L57（CAPTURE_SRC）、L77-83（cleanup）、L134（并发 die）、L188-189（PLAN_SRC）
- main 版 `framework/templates/e2e_capture.gd:278` 为强类型 require（本 issue 可不改模板，模板 Array 支持归 #475；但若 #475 未先 merge，runner 的 worktree 优先即可规避崩溃）
- PR #475（impl/466）分支已含 runner 的 P5 修改（worktree 模板优先 + visual 透传 + missed 检查）——**plan agent 应直接参考该分支 diff 而非重新设计**
- 测试基线：`tests/pipeline/test_e2e_runner.py`（fake godot 注入，覆盖 L0-L3 / exit code / baseline / dry-run / P6）；`test_worktree_conflict_exits_2`（L223）已覆盖"worktree 已存在"场景，需更新为"并发锁"语义

### 8.2 主要风险

1. #475 merge 顺序：若 #475 先 merge，main 模板已含 Array require 支持，本 issue 只需并发修复 + 验证；若本 issue 先 merge，需确保 runner worktree 优先逻辑与 #475 分支 diff 一致（避免后续 merge 冲突）
2. 锁文件平台差异：避免依赖 flock（macOS BSD vs Linux 行为差异），用 mkdir/文件 + PID 校验
3. 测试注入兼容：新增锁逻辑必须尊重 `E2E_WORKTREE_ROOT` / dry-run 注入，否则 CI 测试失败

### 8.3 下一步（plan agent）

1. 读 `docs/PRD/466-visual-regression-e2e.md` + `docs/DESIGN/466-visual-regression-e2e.md` 了解 #466 的 require 数组化与 visual config 设计
2. 读 `gh pr diff 475` 提取 runner 三段修改（worktree 模板优先 / visual 透传 / missed 检查），作为本 issue 实现蓝本
3. DESIGN 输出：并发锁（锁文件 + PID 校验 + stale 回收）、cleanup 归属标记（worktree 内 `.e2e-owner` 或本实例创建标志）、CAPTURE_SRC worktree 优先、3 组新增测试用例
4. 实施顺序建议：并发单例 → 归属校验 → P5 worktree 优先 → 测试
5. 验收跑法：`python3 -m unittest discover -s tests/pipeline -v` 全绿 + 手动并发演练（后台两个实例）

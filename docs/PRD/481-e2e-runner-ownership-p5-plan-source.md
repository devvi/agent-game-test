# PRD: [Bug] 修复 e2e runner — worktree 归属守卫 + P5 plan source 版本盲区 (class A 基建)

> **Issue:** #481 — "Fix e2e runner: worktree ownership guard + P5 plan source [fset:runner-a]"
> **标签:** bug, priority/high, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-14
> **深度:** depth/standard（无 depth 标签，按 #372/#476 惯例 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的源码/差异分析实验补齐）
> **所有权:** `content_ownership: mechanical`（纯测试基建修复，无品味决策）
> **来源:** #475 review 结论（2026-08-14，Class A 基建缺陷）。#481 为方案①模拟结论文件自动生成的重复 issue（手动建的 #480 已是 runner fix issue，见 §1.4 去重说明）
> **约束:** class A 基建 —— 只改 `scripts/`、`framework/templates/`、`tests/pipeline/` 等测试基建文件，**不改游戏代码**（`mini-pong/gdscripts/`、`scenes/`）

---

## 1. 问题定义

### 1.1 当前状态（核心发现）

`scripts/run-e2e-review.sh`（#357 引入，#372/#377 修复过 P6 上传与 frozen 阈值）是本地 E2E 主 runner。2026-08-14 review agent 在验证被阻塞的 PR #475 时，发现 3 个 **class A 基建缺陷**（非游戏代码缺陷），全部位于 runner 自身：

1. **runner-worktree-ownership（缺陷 1）**：EXIT trap 的 cleanup 无条件 `git worktree remove "$WT" --force`，不校验"这个 worktree 是不是本进程建的"。并发实例（同一 PR 号重试/重复调度）后到者在 P0 命中 `die "worktree already exists: $WT"` 退出时，其 trap 会把**先到者正在使用的 worktree 强删** → 先到者后续 L0/L1/L2 全部因文件消失而失败（review 实测 12 failed 假失败）。
2. **runner-p5-plan-source（缺陷 2）**：P5 视觉层的全部 harness 工件都从 `REPO_ROOT`（main 工作区版本）执行——`CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"`、`resolve_plan.py`/`analyze_bmp.py` 经 `$SCRIPT_DIR`（= `$REPO_ROOT/scripts`）调用、`PLAN_SRC` 缺失时回退 `$REPO_ROOT/framework/templates/e2e_shots.json`。PR 分支对 harness 的修改（如 #475 的 require 数组化 / shot 级 visual 透传 / missed 检查 / worktree 模板优先）在 main 版 runner 下**永不生效** → main 版 `e2e_capture.gd` 的 typed `var req: Dictionary = d["require"]` 遇 PR 版 plan.json 的 Array require 必然 GDScript 类型崩溃（`Cannot assign Array to Dictionary`）。
3. **runner-concurrency-singleton（缺陷 3）**：无锁文件 / PID 校验。同 PR 号并发唯一的防线就是 P0 的 `[ -d "$WT" ]` die——而这恰是触发缺陷 1 误删路径的入口。

**新增发现（issue body 未提及，预调查中确认）**：`PLAN_SRC` 回退目标 `framework/templates/e2e_shots.json` 的 `state_node` 是过期的 `/root/Main/GameStateMachine`（mini-pong 自 #358 起根节点为 `Game`，游戏自持版本已修正为 `/root/Game/GameStateMachine`）。一旦走回退，capture 会按错误的 state_node 轮询 → 假失败或超时。回退路径是**静默**的（仅 `log "  plan source: $PLAN_SRC"` 一行），无警告。

### 1.2 预调查结果（bug pre-investigation，Patch 8/10）

| # | Issue 声明（review 结论 475.json） | 状态 | 证据（源码/差异核实） |
|---|----------------------------------|:----:|----------------------|
| 1 | runner-worktree-ownership：trap cleanup 不校验 worktree 归属，并发 P0 die 时 `--force` 误删运行中实例的 worktree | ✅ **确认仍坏** | `run-e2e-review.sh` `cleanup()`（trap EXIT）：`[ "$KEEP" != "1" ] && [ -d "$WT" ]` → `git worktree remove "$WT" --force`，无任何"本进程创建"标记；P0 `die "worktree already exists: $WT"` 后 trap 必触发。`tests/pipeline/test_e2e_runner.py:223 test_worktree_conflict_exits_2` 只断言 exit 2，**未断言"不得删除已存在的 worktree"** |
| 2 | runner-p5-plan-source：P5 plan source 回退 REPO_ROOT，用 main 模板跑 PR 的 require 数组必然崩溃 | ✅ **确认仍坏** | `CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"`（main 版，`e2e_capture.gd:278 var req: Dictionary = d["require"]` typed）；`resolve_plan.py`/`analyze_bmp.py` 经 `$SCRIPT_DIR`（main 版）调用；#475 分支的 `mini-pong/e2e_shots.json` 02_midgame `require` 改为 **Array**（`[{node...},{children_in_group...}]`）+ 新增 shot 级 `visual` 配置，`e2e_capture.gd` 改为 `var req` + `_require_one()` 数组分支 —— main 版 runner 跑 #475 分支必然崩溃 |
| 3 | runner-concurrency-singleton：无锁文件/PID 校验 | ✅ **确认仍坏** | `run-e2e-review.sh` 全文无 flock/lock/PID 文件；唯一同 PR 防护是 P0 `[ -d "$WT" ]` die（触发误删的路径本身） |
| 4 | （新增）模板 fallback 的 state_node 过期 | ✅ **确认仍坏** | `framework/templates/e2e_shots.json` `state_node=/root/Main/GameStateMachine`；`mini-pong/e2e_shots.json`（#358 修正）为 `/root/Game/GameStateMachine`；回退路径无警告 |

**已修复项 / stale claims**：无 —— `git log --oneline -- scripts/run-e2e-review.sh` 仅 3 个提交（`864d2df` #357 引入、`93766f8` #372 修复、`0c45f93` #383 竖屏），均不涉及归属/版本/并发。注意 **#475 分支自身已尝试修复缺陷 2 的一部分**（`CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"` 优先 + visual 透传 + missed 检查），但该修复在 PR 分支内，main 版 runner 不会执行它 —— 这正是"版本盲区"的闭环证据。

### 1.3 预期行为（验收条件，源自 Issue #481）

1. [ ] **AC1** 并发跑两个 `run-e2e-review.sh` 实例（同 PR 号）：后到者 P0 失败退出（exit 2），**不得删除先到者正在使用的 worktree**
2. [ ] **AC2** trap cleanup 只清理本实例创建的 worktree（归属标记 / PID 校验），`--keep`/`--dry-run` 语义不变
3. [ ] **AC3** P5 的 4 个 harness 工件（`resolve_plan.py`、`analyze_bmp.py`、`e2e_capture.gd`、`e2e_shots.json`）**优先取 worktree 内版本**（PR 版），worktree 缺失才回退 REPO_ROOT，且回退必须显式 `log` 警告（含来源路径）
4. [ ] **AC4** PR #475 分支跑 runner：L3 不再因 `var req: Dictionary ← Array` 崩溃；require 数组 + shot 级 visual 区域断言 + missed 检查全部生效
5. [ ] **AC5** 单例防护：进程级锁（flock 或 PID 校验），并发第二个实例立即 exit 2 且不产生副作用
6. [ ] **AC6** `tests/pipeline/test_e2e_runner.py` 新增/更新用例覆盖 AC1-AC5，`pipeline-tests` CI 全绿

### 1.4 与 #480 的关系（scope deconfliction）

| Issue | 状态 | 标题/范围 | 本 PRD 处理 |
|-------|:----:|-----------|:-----------:|
| #480 | OPEN | worktree ownership guard + P5 plan source + **concurrency singleton**（手工建） | 本 PRD 覆盖其全部 3 项缺陷（§4.1-4.3） |
| #481（本 issue） | OPEN（本次已 reopen） | worktree ownership guard + P5 plan source（方案①模拟结论自动生成） | 本 PRD 主体 |

两 issue 修复范围一致（#481 body 的 pre-existing failures 同样列出 3 项）。**建议**：保留 #481 走完 research→plan→implement 管线，将 #480 标记为 duplicate/关闭（或反之）；由人工决定去重方向，避免两个 implement agent 修同一段代码。本 PRD 以 #481 为 parent。

### 1.5 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | review agent 并发验证多个 impl PR / 同 PR 重试 | 每次 review 高峰 | 同 PR 重复实例互不干扰；先到者的 worktree 不被后到者误删（12 failed 假失败根因） |
| B | harness 演进 PR（改 runner/模板/断言脚本，如 #466/#475） | 基建演进时 | PR 对 harness 的修改必须被该 PR 自己的 e2e 验证使用，而非 main 版（自举验证） |
| C | 新游戏子项目首个 e2e（worktree 内无 e2e_shots.json） | 罕见 | 回退 main 模板时必须有显式警告，避免静默用过期 state_node 假失败 |

---

## 2. 设计意图

1. **runner 是本地验证的唯一入口**（review agent 工具，ARCHITECTURE.md L3）：误删 worktree 产生假失败 → review 结论被污染（Class B pre-existing 误判）→ 阻塞链错误传播。归属守卫是 runner 可信度的底线。
2. **版本自洽 / 自举（bootstrapping）**："框架管机器，游戏管剧本"（PLAN-e2e-verification 原则 4）隐含前提是 runner 跑的是**被测 PR 的**机器与剧本。harness 演进 PR（如 #475 改 capture 模板/断言脚本/shot plan）必须能被自己的版本验证，否则基建改动永远无法通过自己的 e2e —— 修复方式统一为"worktree 工件优先，REPO_ROOT 兜底"。
3. **并发单例是归属守卫的互补**：归属守卫解决"删错"，单例锁解决"同时跑"；两者共同消灭同 PR 并发竞态。锁为**进程级**（flock），与 ARCHITECTURE.md 2026-07-29 已删除的 label 分布式锁无关，不违反"不得重新引入 label 锁"红线。
4. **与 #476 正交**：#476 修 L3 断言**内容**（bg 桶竞争/雨签名/固定区域）；本 issue 修 runner **基础设施**（归属/版本/并发）。#475 解锁需要两者都落地（#476 修断言内容、本 issue 修 runner 版本盲区）。

---

## 3. 影响分析

| 文件 | 变更 | 风险 |
|------|------|:----:|
| `scripts/run-e2e-review.sh` | ① cleanup 归属守卫（OWNED 标志 + 归属标记文件）② P0 后 flock 单例锁 ③ P5 4 工件 worktree 优先 + 回退警告 | **中** — trap/锁/路径三处改动，必须 `test_e2e_runner.py` 全覆盖 |
| `tests/pipeline/test_e2e_runner.py` | 更新 `test_worktree_conflict_exits_2`（断言不删他人 worktree）；新增 ownership/singleton/plan-source 用例 | 低 |
| `scripts/e2e/resolve_plan.py` | 无改动（仅调用方路径变化） | — |
| `scripts/e2e/analyze_bmp.py` | 无改动（本 issue 不动断言算法） | — |
| `framework/templates/e2e_capture.gd` | 无改动（require 数组化属 #466/#475 分支内容） | — |
| `mini-pong/e2e_shots.json` | 无改动 | — |

不改游戏代码、不改 `.github/workflows/`。runner 修改后需跑 `./scripts/sync-to-hermes.sh`（ARCHITECTURE.md 组件清单约定）。

---

## 4. 方案对比

### 4.1 worktree 归属守卫（缺陷 1）

| 方案 | 做法 | Pros | Cons | 风险/工作量 |
|------|------|------|------|:-----------:|
| **A（推荐）** | bash 标志位 `OWNED=1`（仅 `worktree add` 成功后置位）+ cleanup 仅当 `OWNED=1` 才 remove；纵深防御：add 成功后写 `$WT/.e2e-owner`（PID+时间戳），cleanup 校验标记存在且 PID 匹配（或标记 PID 已死） | 最小改动；本进程未建过 worktree 绝不删；跨进程残留（标记 PID 死亡）可安全回收 | 标志位是进程内状态，跨进程判断需标记文件配合 | 低/中 |
| B | `git worktree list` 解析：cleanup 前校验 $WT 的登记 branch/路径与本次运行一致 | 无额外文件 | worktree 是 git 级对象，无法区分"谁建的"；同 PR 重跑 branch 相同 → 校验恒真，防不了误删 | 中 |
| C | 仅在 P0 conflict die 前先 `git worktree remove` 旧 worktree 再继续 | 让后到者"接管" | **危险** —— 正在运行的实例会被直接打断，比现状更糟 | 高（否决） |

**推荐 A**：OWNED 标志位为主守卫（进程内，零竞态），`.e2e-owner` 标记文件为纵深（清理残留/诊断），B 的 `git worktree list` 输出仅作诊断日志。

### 4.2 P5 plan source / harness 版本（缺陷 2）

| 方案 | 做法 | Pros | Cons | 风险/工作量 |
|------|------|------|------|:-----------:|
| **A（推荐）** | 4 工件统一策略：`worktree 路径优先 → 缺失回退 REPO_ROOT → 回退显式 log 警告`。即 `CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"`（#475 已尝试）、`resolve_plan.py`/`analyze_bmp.py` 先查 `$WT/scripts/e2e/`、`PLAN_SRC` 先查 `$WT/$SUBPROJECT/e2e_shots.json`（已有），回退时 `log "⚠ plan source fallback (worktree missing): $PLAN_SRC"` | 与 #475 分支方向一致；保留 `E2E_PLAN_PATH` 等测试注入通道；回退可见 | 回退仍可能用 main 模板（但显式警告后由人/流程决策） | 低 |
| B | 硬失败：worktree 缺失即 P5 fail，不回退 | 杜绝用错版本 | 破坏 `E2E_PLAN_PATH` 注入与"新游戏无剧本"场景（#358 前无此文件）；过严 | 中（否决） |
| C | 只改 `CAPTURE_SRC`（#475 现状） | 修掉最痛的 typed 崩溃 | 不完整 —— `resolve_plan.py`/`analyze_bmp.py` 仍是 main 版，PR 对断言脚本的修改（#475 的 `--visual-config`/`check_visual`）永不生效，`--visual-config` 传参在 main 版 argparse 下 exit 2 | 中（否决） |

**推荐 A**：统一"worktree 工件优先 + 显式回退警告"，一处策略覆盖全部 4 工件，自举验证闭环。

### 4.3 并发单例（缺陷 3）

| 方案 | 做法 | Pros | Cons | 风险/工作量 |
|------|------|------|------|:-----------:|
| **A（推荐）** | `flock` 锁文件 `$WORKTREE_ROOT/.e2e-runner.lock`（fd 200），获取失败 → die exit 2 | 原子、无 TOCTOU；`flock` 随进程退出自动释放，无残留 | 锁文件位置需与 `E2E_WORKTREE_ROOT` 注入一致（测试隔离） | 低 |
| B | mkdir 锁目录 | 原子 | 进程崩溃残留目录需清理逻辑；竞态处理繁琐 | 中 |
| C | PID 文件 + `kill -0` 校验 | 简单 | TOCTOU 竞态（PID 复用）；崩溃残留 | 中 |

**推荐 A**：进程级 flock 单例，锁失败语义与 P0 一致（exit 2），`--dry-run` 也获取锁（保持行为一致性）。

---

## 5. 边界条件

- **`--keep` / `--dry-run`**：`--keep` 时 cleanup 本就跳过 remove，归属守卫不改变该语义；`--dry-run` 的 `maybe` 包裹 `worktree add`，OWNED 标志位不应在 dry-run 置位（dry-run 不建 worktree，trap 也不删）。
- **测试注入**：`E2E_WORKTREE_ROOT` 可注入（`test_e2e_runner.py` 用临时目录）——单例锁放 `$WORKTREE_ROOT` 下，不同注入根互不干扰；`E2E_PLAN_PATH` 显式指定时跳过 worktree 优先逻辑（注入优先）。
- **回退仅限"worktree 缺失"**：回退是显式 log 警告的兜底，不静默；回退来源含路径，便于诊断（如模板 state_node 过期问题在回退时暴露）。
- **多 PR 并发不受影响**：不同 PR 号 worktree 路径不同（`wt-impl-<N>`），单例锁只防同机同刻两个 runner 实例（含同 PR 重试），不序列化不同 PR 的验证。
- **不引入 label 锁**：ARCHITECTURE.md（2026-07-29）已删除分布式 label 锁，任何代码不得重新引入；本 issue 的 flock 是**进程级**锁，与 label 状态机无关。
- **范围边界**：require 数组化、shot 级 visual 配置、`check_visual` 区域断言是 #466/#475 分支内容，本 issue 只保证 runner 用对版本，**不实现**这些断言语义（#476 修其内容缺陷）。
- **安全**：runner 仍以完整文件系统权限执行 PR 分支 GDScript（既有已知限制，本 issue 不改变）。

---

## 6. 依赖

| 依赖 | 状态 | 关系 |
|------|------|------|
| #466 / PR #475（blocked，impl/466-e2e-visual-regression） | OPEN/blocked | 本 issue 修复后 #475 需 update-branch 重新跑 e2e —— runner 修复是 #475 解锁的前提之一（缺陷 2 直接导致其 L3 崩溃） |
| #476（L3 断言内容修复） | OPEN | 正交无代码依赖；但 #475 重新验证时需 #476 修复已合入 main，否则 L3 断言内容仍失败（非本 issue 范围） |
| `tests/pipeline/`（104 用例，D3 门禁） | main | runner 改动必须过该套件；`pipeline-tests.yml` 在 `scripts/` 变更时强制运行 |
| `framework/templates/e2e_capture.gd`（main 版 typed `var req: Dictionary`） | main | 本 issue 不改 capture 语义；AC4 验证依赖 #475 分支的 capture 版本来证明版本盲区已修复 |

---

## 7. Spike/实验（研究期已执行的验证，standard 深度补齐）

| # | 实验 | 方法 | 结果 |
|---|------|------|------|
| 1 | 并发误删复现（缺陷 1） | 源码路径推演：`die` → `exit 2` → trap EXIT → `cleanup()` 无条件 remove `--force`；`test_e2e_runner.py:223` 只断言 exit 2 | ✅ 复现路径成立：后到者 trap 删除先到者 worktree |
| 2 | 版本盲区复现（缺陷 2） | 对比 main `e2e_capture.gd:278` typed `var req: Dictionary` vs #475 分支 Array require（`mini-pong/e2e_shots.json` 02_midgame）+ `_require_one()` 数组分支 | ✅ 崩溃机理确认：main capture + PR plan = `Cannot assign Array to Dictionary`；且 #475 分支对 `CAPTURE_SRC` 的 worktree 优先修复在 main runner 下不执行 |
| 3 | 模板回退过期（新增） | 对比 `framework/templates/e2e_shots.json`（`/root/Main/...`）vs `mini-pong/e2e_shots.json`（`/root/Game/...`，#358 修正） | ✅ 回退路径用过期 state_node，capture 轮询错节点 → 假失败/超时，且无警告 |

---

## 8. 延续上下文（handoff 给 plan agent）

- **实现入口**：`scripts/run-e2e-review.sh`（cleanup 归属守卫 + flock 单例 + P5 4 工件 worktree 优先 + 回退警告）；`tests/pipeline/test_e2e_runner.py`（更新 `test_worktree_conflict_exits_2` 断言"不删他人 worktree"；新增：`test_owner_marker_only_cleans_own`、`test_singleton_lock_second_exits_2`、`test_plan_source_worktree_priority`、`test_fallback_logs_warning`）。
- **验收路径**：本地跑 `python3 -m unittest discover -s tests/pipeline -v` 全绿；用真实 PR #475 分支跑 `scripts/run-e2e-review.sh 475` 验证 L3 不再崩溃（AC4）；并发双实例验证 AC1/AC5。
- **关键文件现状（实现 agent 勿重复创建）**：`run-e2e-review.sh` 354 行（P0-P7 结构）、`test_e2e_runner.py`（fake godot + 临时 git 仓库注入式测试）、`framework/templates/e2e_shots.json`（回退目标，state_node 过期已知）。
- **去重决策**：本 PRD 覆盖 #480 全部 3 项缺陷；plan 阶段前需人工决定 #480 与 #481 去重方向（建议关闭 #480），避免两个 implement agent 改同一段代码。
- **收尾约定**：runner 修改后跑 `./scripts/sync-to-hermes.sh`；merge 后由 workflow-chain 自动推进 label（`workflow/research` → `workflow/plan`）。

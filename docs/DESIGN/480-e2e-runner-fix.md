# DESIGN: [Bug] 修复 e2e runner — worktree 归属校验 + P5 plan source + 并发单例

> Parent Issue: #480
> Agent: game-plan-agent
> Date: 2026-08-14
> Approach: PRD §4 推荐组合 — **§4.1 Approach A+B**（锁文件 + PID 校验 + 归属标记兜底）；**§4.2 Approach A**（CAPTURE_SRC 双 worktree 优先）；**§4.3** 并入 #475 分支 runner 的三段 P5 修改（visual 透传 / worktree 模板优先 / missed 检查）
> 深度: depth/standard（Issue 无 depth 标签，按 #476/#466/#372 惯例）
> 上游: `docs/PRD/480-e2e-runner-fix.md`（research PR #483 MERGED）

---

## 1. 架构概述

**问题本质是两个叠加的 class A 基建缺陷（非代码缺陷，review deleg_c3630212 于 2026-08-14 发现）：**

1. **并发单例缺陷** — `scripts/run-e2e-review.sh` 的 P0 检查只有 `[ -d "$WT" ]`（按 PR 号键控的固定 worktree 路径），同 PR 并发第二实例 die 后 EXIT trap 触发 `cleanup()`，其中 **无条件** `git worktree remove "$WT" --force` → 误删第一实例正在运行的 worktree → L1 假失败（12 failed）。
2. **runner 版本盲区** — review 在主工作区跑 main 版 runner，main 版无 PR #475 分支的 P5 修改（visual 透传 / worktree 模板优先 / missed 检查），且 `CAPTURE_SRC` 固定指向主工作区模板 → 用 main 模板跑 PR 的 require 数组（Array 形式，#466 引入）必然崩溃（`var req: Dictionary` ← Array）。

**修复架构（全部落在 runner 单文件 + 其 pipeline 测试，不新建组件）：**

```
scripts/run-e2e-review.sh (354 行, 唯一实现修改文件)
  ├── P0 新增: acquire_lock() / release_lock()
  │     锁文件 $WORKTREE_ROOT/.e2e-<PR_NUM>.lock (mkdir 原子创建 + PID 校验)
  │     → 同 PR 并发第二实例: die "another instance running" (exit 2, 不触发删 WT)
  │     → stale 锁 (PID 已死): 自动回收重建
  ├── cleanup() 新增归属校验: WT_OWNED / LOCK_OWNED 双标志
  │     → 只删本实例创建的 worktree; 锁文件始终由持锁者删除
  ├── P5 CAPTURE_SRC 双 worktree 优先 (并入 #475 修改):
  │     $WT/framework/templates/e2e_capture.gd 存在 → 用 PR 版; 否则回退 REPO_ROOT
  ├── P5 visual config 透传 (并入 #475 修改): shot 级 visual 字段 → --visual-config
  └── P5 missed-shot 检查 (并入 #475 修改): 计划 shot 必须有 PNG, 否则 L3 fail
```

**设计哲学（与 PRD §4 一致）：**
- **纵深防御**：锁文件（Approach A）提供明确拒绝语义 + 归属标记（Approach B）兜底防误删 —— 即使锁逻辑被绕过（如锁文件被手工删除），cleanup 仍不会删非本实例创建的 worktree。
- **"用 PR 版本跑 PR"**：P5 的 capture 模板与 shot plan 均以 worktree 内 PR 版优先，main 版仅作回退 —— 消除 main 模板强类型 require 对 Array 格式的崩溃路径。
- **平台中立**：不用 `flock`（macOS BSD vs Linux 行为差异），用 `mkdir` 原子性 + `kill -0` PID 存活校验，macOS/Linux 通用。
- **向后兼容**：visual 字段缺失时不加 `--visual-config` flag、worktree 模板缺失时回退 REPO_ROOT、dry-run 不碰锁 —— 行为与现状一致。

**与 #475 的 merge 顺序关系（PRD §8.2 风险 1）：** 本 PR 先 merge 时，runner 的 worktree 优先逻辑保证 review #475 不崩溃（用 PR 版模板跑 PR 版 plan）；#475 先 merge 时 main 模板已含 Array require 支持，本 PR 逻辑不变仍正确。**两种顺序均安全，runner 修改与 #475 分支 diff 逐字一致，后续无 merge 冲突。**

### 1.1 Prior Implementation Status

| 文件 | main 状态 | #475 分支状态（impl/466） |
|------|:---------:|:--------------------------:|
| `scripts/run-e2e-review.sh` | 无并发锁、无归属校验、CAPTURE_SRC 固定 REPO_ROOT、无 visual 透传、无 missed 检查 | ✅ 已含 CAPTURE_SRC worktree 优先 + visual 透传 + missed 检查（本 issue 蓝本） |
| `framework/templates/e2e_capture.gd` | `var req: Dictionary` 强类型（L278） | ✅ 已支持 Array require（本 issue **不改模板**，模板归 #475） |
| `tests/pipeline/test_e2e_runner.py` | 8 个用例，`test_worktree_conflict_exits_2` 只覆盖"worktree 已存在" | 无并发/归属/模板优先测试（本 issue 新增） |

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main） | 设计决议 |
|---------|-----------------|---------|
| trap cleanup 无条件删 WT | `run-e2e-review.sh:77-83` `cleanup()` L80 `git worktree remove "$WT" --force`，无归属校验 | cleanup 增加 `WT_OWNED` 标志守卫：仅本实例成功 `worktree add` 后才置 1，为 0 时不删（§3.1.2） |
| 并发第二实例误删 WT | L134 `[ -d "$WT" ]` → die exit 2 → EXIT trap → cleanup 删 WT | P0 前置 `acquire_lock()`（锁 + PID 校验），第二实例 die 时 `WT_OWNED=0` → WT 保留（§3.1.1） |
| CAPTURE_SRC 固定 REPO_ROOT | L57 `CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"` | 改为 worktree 优先（§3.1.3，与 #475 diff 一致） |
| P5 plan source 回退 REPO_ROOT | L188-189 `PLAN_SRC="${E2E_PLAN_PATH:-$WT/$SUBPROJECT/e2e_shots.json}"` 已 worktree 优先 | ✅ 已满足，保留现状；L189 fallback 保留（旧 PR 无 plan 时回退模板） |
| main 模板对 Array require 崩溃 | `e2e_capture.gd:278` `var req: Dictionary = d["require"]` | 本 issue 不改模板；CAPTURE_SRC worktree 优先后 review #475 用 PR 版模板，崩溃路径消除 |

---

## 2. 新组件

**无新源码文件**（PRD §3.2）。仅新增两个**运行期资源**（由 runner 创建/销毁，不入库）：

| 资源 | 路径 | 内容 | 生命周期 |
|------|------|------|---------|
| 并发锁目录 | `$WORKTREE_ROOT/.e2e-<PR_NUM>.lock` | 内含 `pid` 文件（持锁实例 PID） | P0 获取 → cleanup 释放（`--keep` 也释放；dry-run 不创建） |
| 归属标记（兜底） | 内存变量 `WT_OWNED`（bash 标志），可选 worktree 内 `.e2e-owner` 文件 | 本实例 PID | `worktree add` 成功后置 1 → cleanup 消费 |

> 锁用 **目录 + mkdir**（原子）而非文件写入，避免"检查-创建"竞态（PRD §4.1 Approach A 的 Cons 处理）。

---

## 3. 既有组件修改

### 3.1 `scripts/run-e2e-review.sh`（354 行，唯一实现修改文件）

#### 3.1.1 P0 并发单例锁（新增函数 `acquire_lock` / `release_lock`）

在 `WORKTREE_ROOT`/`WT` 定义区（L54 附近）新增：

```bash
LOCK="$WORKTREE_ROOT/.e2e-$PR_NUM.lock"     # mkdir 原子创建
LOCK_OWNED=0
WT_OWNED=0

acquire_lock() {                            # P0 调用, dry-run 直接跳过
  [ "$DRY_RUN" = "1" ] && return 0
  if mkdir "$LOCK" 2>/dev/null; then
    echo "$$" > "$LOCK/pid" 2>/dev/null || { rm -rf "$LOCK"; die "lock pid write failed" 2; }
    LOCK_OWNED=1
    log "lock acquired: $LOCK (pid $$)"
    return 0
  fi
  # 锁已存在 → stale 判定: pid 文件缺失或 PID 已死 → 回收
  local old_pid
  old_pid="$(cat "$LOCK/pid" 2>/dev/null || echo "")"
  if [ -z "$old_pid" ] || ! kill -0 "$old_pid" 2>/dev/null; then
    log "stale lock (pid ${old_pid:-unknown} dead) — reclaiming"
    rm -rf "$LOCK"
    if mkdir "$LOCK" 2>/dev/null; then
      echo "$$" > "$LOCK/pid" 2>/dev/null || { rm -rf "$LOCK"; die "lock pid write failed" 2; }
      LOCK_OWNED=1
      return 0
    fi
  fi
  die "another instance running for PR #$PR_NUM (lock: $LOCK, pid $old_pid)" 2
}

release_lock() {
  [ "$LOCK_OWNED" = "1" ] && rm -rf "$LOCK" 2>/dev/null && LOCK_OWNED=0
}
```

P0 顺序调整：`acquire_lock` **先于** 原 `[ -d "$WT" ]` 检查（L134 保留，作为锁被绕过时的第二道防线）。原 `die "worktree already exists"` 语义保留（exit 2），但此时 `WT_OWNED=0` → cleanup 不再删 WT。

#### 3.1.2 cleanup 归属校验（L77-83 改造）

```bash
cleanup() {
  [ -n "$CAFF_PID" ] && kill "$CAFF_PID" 2>/dev/null
  if [ "$KEEP" != "1" ] && [ "$WT_OWNED" = "1" ] && [ -d "$WT" ]; then
    git -C "$REPO_ROOT" worktree remove "$WT" --force 2>/dev/null && log "worktree removed: $WT"
  fi
  release_lock
}
trap cleanup EXIT
```

- `WT_OWNED` 在 P1 `maybe git worktree add "$WT" "$BRANCH"` **成功后** 置 1（紧随其后 `WT_OWNED=1`）。
- `--keep` 保留 worktree 但**仍释放锁**（锁是运行期资源，PRD §5.2-4）。
- 锁文件始终由持锁实例释放；`E2E_WORKTREE_ROOT` 自定义时锁路径自动跟随（PRD §5.2-5）。

#### 3.1.3 P5 CAPTURE_SRC worktree 优先（并入 #475 diff，逐字一致）

L57 定义处保留 REPO_ROOT 回退值；P5 capture 前（#475 分支同位置）改为：

```bash
CAPTURE_SRC="$WT/framework/templates/e2e_capture.gd"
[ -f "$CAPTURE_SRC" ] || CAPTURE_SRC="$REPO_ROOT/framework/templates/e2e_capture.gd"
```

#### 3.1.4 P5 visual config 透传（并入 #475 diff）

analyze_bmp.py 调用循环内，按 shot 从 `$OUT/plan.json` 提取 `visual` 字段，存在则追加 `--visual-config "$OUT/visual-<shot>.json"`（缺失不加 flag，向后兼容）。伪代码与 #475 diff 完全一致：

```bash
shot_name="$(basename "$png" .png)"
if python3 - "$OUT/plan.json" "$shot_name" "$OUT/visual-$shot_name.json" <<'PY' >/dev/null 2>&1
import json, sys
plan = json.load(open(sys.argv[1]))
for s in plan.get("shots", []):
    if s.get("name") == sys.argv[2] and "visual" in s:
        json.dump(s["visual"], open(sys.argv[3], "w"), indent=2)
        sys.exit(0)
sys.exit(1)
PY
then
  args+=(--visual-config "$OUT/visual-$shot_name.json")
fi
```

#### 3.1.5 P5 missed-shot 检查（并入 #475 diff）

对每个已 resolve 的 shot 名检查 `$OUT/shots/<name>.png` 是否存在，缺失 → `VISUAL_FAIL=1` + 日志 `❌ planned shot missing: <name>.png`（#466 DESIGN §1.3：missed 显式标注，不静默通过）。

#### 3.1.6 P6/P7 不变

P6 证据、P7 summary、退出码约定（0/1/2）不动。

### 3.2 `tests/pipeline/test_e2e_runner.py`（305 行，新增 3 组用例 + 改造 1 个既有用例）

| 变更 | 说明 |
|------|------|
| `test_worktree_conflict_exits_2`（L223） | 语义更新：预建 `wt-impl-1` 目录 → 期望 exit 2 **且 worktree 保留**（原断言只查 exit 2 + 无 godot 调用，需补 `self.assertTrue(self._wt_exists())`） |
| 新增 `TestRunnerConcurrency` | TC1 存活锁拒绝 / TC2 stale 锁回收 / TC3 锁创建失败 exit 2 |
| 新增 `TestRunnerOwnership` | TC4 非本实例 worktree 不被删 / TC5 本实例失败清理自己的 / TC6 `--keep` 保留 WT 但释放锁 |
| 新增 `TestRunnerP5WorktreeFirst` | TC7 capture 模板来自 WT / TC8 模板缺失回退 REPO_ROOT / TC9 PLAN_SRC worktree 优先 / TC10 visual 透传 flag / TC11 missed-shot L3 fail |

测试注入保持现有模式（`RUNNER_GODOT` / `E2E_WORKTREE_ROOT` / `E2E_BRANCH` / `E2E_DIFF_FILES` / `E2E_PLAN_PATH`），fake godot 不变。

### 3.3 文档更新（随本 PR，低优先级）

| 文件 | 变更 |
|------|------|
| `docs/PLAN-e2e-verification-v2.md` | P8 cleanup 描述补充归属校验 + 并发锁说明（PRD §3.5） |
| `framework/ARCHITECTURE.md` | E2E 验证体系节补充并发单例决策（PRD §3.5 可选，若篇幅允许） |

### 3.4 明确不改

- `framework/templates/e2e_capture.gd` — Array require 支持归 #475；本 issue 靠 CAPTURE_SRC worktree 优先规避崩溃
- `mini-pong/e2e_shots.json`、`scripts/e2e/resolve_plan.py`、`scripts/e2e/analyze_bmp.py` — 无改动
- 游戏代码（`mini-pong/gdscripts/`、`scenes/`、`project.godot`）— class A 约束，绝不触碰

---

## 4. 数据流

### Flow 1: 并发场景（修复后）

```
Runner-A (PR #466)                          Runner-B (PR #466, 并发触发)
  │ P0: acquire_lock → mkdir 成功, 持锁       │ P0: acquire_lock → mkdir 失败
  │ P1: worktree add → WT_OWNED=1            │     kill -0 A 的 PID → 存活
  │ L1 运行中                                │     die "another instance running" exit 2
  │ ...                                      │     trap cleanup: WT_OWNED=0 → WT 保留 ✓
  │ L1 完成 → cleanup: 删自己的 WT + 释放锁    │     release_lock: LOCK_OWNED=0 → 不动 A 的锁 ✓
  └─ 结果正确, 无假失败                        └─ exit 2 (pre-flight 语义, 与既有约定一致)
```

### Flow 2: 版本盲区场景（修复后, review #475）

```
主工作区 runner (main 版, 含本 issue 修改)
  ├── PLAN_SRC   = $WT/mini-pong/e2e_shots.json        ← PR 版 (require: Array) ✅
  ├── CAPTURE_SRC = $WT/framework/templates/e2e_capture.gd ← PR 版 (Array 支持) ✅
  │     └── 缺失时回退 $REPO_ROOT/framework/templates/e2e_capture.gd
  ├── visual 透传: 02_midgame.visual → --visual-config  ✅
  └── missed 检查: 3 计划 shot 必须有 3 个 PNG          ✅
        └── e2e_capture.gd 读 plan.json → _require_ok() 接受 Array → 无崩溃
```

### Flow 3: stale 锁回收

```
P0: mkdir $LOCK 失败 → cat $LOCK/pid → PID 已死 (kill -0 失败)
  → rm -rf $LOCK → mkdir 重建 → 写入 $$ → LOCK_OWNED=1 → 正常继续
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | 锁存在且 PID 存活（同 PR 并发） | die exit 2 "another instance running"，不删 WT、不动锁（§3.1.1） |
| 2 | 锁存在但 PID 已死（stale） | 自动回收重建，正常启动（Flow 3） |
| 3 | PID 复用（旧 PID 被新进程占用） | `kill -0` 误判存活 → 第二实例退出；影响仅"本次 review 被拒"，无破坏。可选增强：校验进程命令行含 run-e2e-review.sh（PRD §5.2-2，默认不做） |
| 4 | 锁被绕过（如手工删除）后同 PR 并发 | 第二道防线：L134 `[ -d "$WT" ]` 仍 die exit 2；`WT_OWNED=0` 保证不删第一实例 WT |
| 5 | `--keep` | worktree 保留，锁仍释放（锁是运行期资源） |
| 6 | `E2E_WORKTREE_ROOT` 自定义 | 锁路径/WT 路径均跟随 WORKTREE_ROOT，测试注入兼容 |
| 7 | worktree 内模板缺失（旧 PR 未改模板） | CAPTURE_SRC 回退 REPO_ROOT，行为与现状一致 |
| 8 | shot 无 visual 字段 | 不加 `--visual-config` flag，向后兼容 |
| 9 | cleanup 多次触发（die 后 EXIT trap + 显式调用） | `WT_OWNED`/`LOCK_OWNED` 幂等消费，`[ -d "$WT" ]` 守卫已存在 |
| 10 | dry-run | 不创建锁、不删 worktree（`acquire_lock` 首行 return 0；cleanup 各守卫天然跳过） |
| 11 | 锁文件创建失败（权限/磁盘） | die exit 2，不继续（避免无锁并发） |
| 12 | 锁 pid 写入失败 | 回滚锁目录 + die exit 2（保守方向） |
| 13 | cleanup 时 worktree remove 失败 | `2>/dev/null` 静默（现状保留），锁仍释放 |
| 14 | 归属标记写入失败 | 保守方向：视为未创建 worktree，cleanup 不删（PRD §5.3-3） |

---

## 6. 逐组件配置（implement 契约速查）

| 组件 | 配置项 | 默认 | 说明 |
|------|--------|------|------|
| runner P0 | `E2E_WORKTREE_ROOT` | `/tmp` | 锁文件与 WT 根目录 |
| runner P0 | `DRY_RUN`（`--dry-run`） | off | 跳过锁创建/删除 |
| runner P0 | `--keep` | off | 保留 WT、释放锁 |
| runner P5 | `E2E_PLAN_PATH` | `$WT/$SUBPROJECT/e2e_shots.json` | plan source 覆盖（测试注入） |
| runner P5 | `E2E_DIFF_FILES` | `gh pr diff --name-only` | diff 驱动 archetype 选择 |
| 锁文件 | `$WORKTREE_ROOT/.e2e-<PR_NUM>.lock/pid` | — | 持锁实例 PID，`kill -0` 存活判定 |

---

## 7. 集成点

> 状态约定：⬜ = 待 implement agent 接线；✅ = implement 后验证。review agent 在 merge 前核对。

| 集成 | 组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 并发单例 | runner P0 | 同 PR 并发实例 | 锁文件 + PID 校验，exit 2 拒绝 | ✅ implemented |
| 归属校验 | runner cleanup | 本实例 worktree | `WT_OWNED` 标志守卫 `worktree remove` | ✅ implemented |
| 模板来源 | runner P5 | worktree 内 e2e_capture.gd | CAPTURE_SRC worktree 优先 + REPO_ROOT 回退 | ✅ implemented |
| 分析器来源 | runner P5 → analyze_bmp.py | worktree 内 analyze_bmp.py | ANALYZE_SRC worktree 优先 + SCRIPT_DIR 回退（**本 PR 扩展**，见 §3.1.4a） | ✅ implemented |
| visual 透传 | runner P5 → analyze_bmp.py | shot visual 配置 | `--visual-config <json>` flag | ✅ implemented |
| missed 检查 | runner P5 | 计划 shot 完整性 | `$OUT/shots/<name>.png` 存在性断言 | ✅ implemented |
| pipeline 测试 | test_e2e_runner.py | runner 全部行为 | fake godot 注入 + 3 组新用例 | ✅ implemented |
| 文档 | PLAN-e2e-verification-v2.md | P8 cleanup 描述 | 补充归属校验/锁说明 | ✅ implemented |

### 3.1.4a 实现偏差记录（implement agent 2026-08-14，数据驱动）

**偏差：** 在 §3.1.3 的 CAPTURE_SRC worktree 优先之外，**额外**将 `ANALYZE_SRC` 也改为 worktree 优先：

```bash
ANALYZE_SRC="$WT/scripts/e2e/analyze_bmp.py"
[ -f "$ANALYZE_SRC" ] || ANALYZE_SRC="$SCRIPT_DIR/e2e/analyze_bmp.py"
```

**根因（实测证据）：** DESIGN §1.2 断言"两种顺序均安全"，但只验证了 CAPTURE 模板（Array require）的崩溃路径，**未覆盖 analyze 步骤**：

1. #475 分支的 `mini-pong/e2e_shots.json` 中 `02_midgame` 带 `visual` 字段（已核实）
2. 本 PR 按 §3.1.4 并入 visual 透传后，runner 会对带 visual 的 shot 追加 `--visual-config` flag
3. **main 版 `scripts/e2e/analyze_bmp.py` 不认识 `--visual-config`**（实测：`python3 scripts/e2e/analyze_bmp.py x.png --visual-config v.json` → `unknown arg: --visual-config`，exit 2）
4. runner 的 analyze 调用固定 `"$SCRIPT_DIR/e2e/analyze_bmp.py"`（= 主工作区 main 版）→ 若本 PR 先 merge，review #475 时 L3 必假失败 → **与 §1.2"本 PR 先 merge 时 review #475 不崩溃"承诺矛盾**

**修复：** 与 CAPTURE_SRC 同一哲学（"用 PR 版本跑 PR"），analyze 脚本也 worktree 优先——review #475 时用 #475 分支自带的 analyze_bmp.py（含 `--visual-config` 支持），main 版仅作回退。对未改 analyze_bmp.py 的普通 PR 行为不变（worktree 版本 == main 版本）。

**merge 顺序影响：** #475 merge 后 main 的 analyze_bmp.py 获得 `--visual-config` 支持，此偏差自动退化为无操作（worktree 版仍优先但内容与 main 一致）。与 #475 的 runner diff 无重叠行冲突（#475 不修改 analyze 调用行）。

---

## 8. 实施阶段

| 阶段 | 优先级 | 任务 | 预估 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | 并发单例锁（acquire/release_lock + P0 接线）+ cleanup 归属校验（WT_OWNED/LOCK_OWNED） | 0.5 天 |
| Phase 2 | P0 | P5 worktree 优先三段并入（CAPTURE_SRC / visual 透传 / missed 检查，与 #475 diff 逐字一致） | 0.5 天 |
| Phase 3 | P0 | 测试：更新 `test_worktree_conflict_exits_2` + 新增 3 组用例；跑 `python3 -m unittest discover -s tests/pipeline -v` 全绿 | 0.5 天 |
| Phase 4 | P1 | 文档更新（PLAN-e2e-verification-v2.md P8；ARCHITECTURE.md 可选）；真实并发演练（两个后台实例） | 0.5 天 |

**验收跑法（PRD §8.3）：** `python3 -m unittest discover -s tests/pipeline -v` 全绿 + 手动并发演练（后台起实例 A，再起实例 B → B exit 2 且 A 的 WT 完好）。

---

## 9. 测试用例描述

> 只描述场景，不写可运行代码（implement agent 负责落地到 `tests/pipeline/test_e2e_runner.py`）。全部沿用现有 fake godot / 临时 git 仓库注入模式。

### Scenario A: 并发单例锁（TestRunnerConcurrency）

- **TC1 存活锁拒绝**：测试预建 `$E2E_WORKTREE_ROOT/.e2e-1.lock/pid` 写入**测试进程自身 PID**（存活），并预建 `wt-impl-1` 目录 → runner exit 2，stdout 含 "another instance running"，**worktree 目录保留**，无 godot 调用。
- **TC2 stale 锁回收**：锁 pid 写入不存在的 PID（如 `999999999`）→ runner 正常跑完（exit 0），锁目录被清理，worktree 正常创建后清理。
- **TC3 锁创建失败**：`E2E_WORKTREE_ROOT` 指向只读目录（`os.chmod` 去掉写权限）→ runner exit 2，报锁创建失败，无 godot 调用。

### Scenario B: worktree 归属校验（TestRunnerOwnership）

- **TC4 非本实例 worktree 不被删**（改造既有 `test_worktree_conflict_exits_2`）：预建 `wt-impl-1`（模拟另一实例创建）→ exit 2，且 `self._wt_exists()` 为 **True**（关键新断言：原实现会误删）。
- **TC5 本实例失败清理自己的**：L1 逻辑层配置失败（`exit_by_substring`）→ exit 1，worktree 被清理（既有 `test_logic_failure_exits_1` 继续通过，回归保护）。
- **TC6 `--keep` 保留 WT 释放锁**：预置锁由 runner 自己获取（正常跑）→ `--keep` 后 worktree 存在、锁目录不存在。

### Scenario C: P5 worktree 优先（TestRunnerP5WorktreeFirst）

- **TC7 capture 模板来自 WT**：在 `impl/1-test` 分支的 `framework/templates/e2e_capture.gd` 写入分支标记内容（如 `# branch-marker`）→ runner 跑完后 `$OUT/capture.gd` 内容含分支标记（证明用了 worktree 版而非 REPO_ROOT 版）。
- **TC8 模板缺失回退 REPO_ROOT**：分支上删除模板文件 → capture.gd 内容等于 REPO_ROOT 版（`# fake capture`），runner 不崩溃。
- **TC9 PLAN_SRC worktree 优先**：不设 `E2E_PLAN_PATH`，分支 `mini-pong/e2e_shots.json` 含 `"marker": true` → P5 日志 plan source 为 `$WT/mini-pong/e2e_shots.json` 路径，resolve 出的 plan 含 marker。
- **TC10 visual 透传**：分支 plan 的 `02_midgame` shot 增加 `visual` 字段 → fake godot 日志/`P5-assert.log` 显示 analyze_bmp.py 收到 `--visual-config` 参数；无 visual 字段的 shot 不加 flag。
- **TC11 missed-shot L3 fail**：fake godot 配置 `no_pngs` 之外的"只产 2 个 PNG"模式（扩展 fake godot 或预置 shots 目录缺 1 个）→ L3 为 fail，stdout 含 "planned shot missing"。

### Scenario D: 回归保护

- **TC12 dry-run 不碰锁**：`--dry-run` 下不创建锁目录、不删任何 worktree（既有 `test_dry_run_executes_nothing` 扩展断言锁目录不存在）。
- **TC13 全层通过 + 清理**：既有 `test_all_layers_pass_and_worktree_cleaned` 继续通过（锁获取→释放、WT 创建→清理全链路回归）。
- **TC14 P6 评论不受影响**：既有 `test_p6_comment_embeds_gist_urls_no_unbound` 继续通过（并发锁不改变 P6 行为）。

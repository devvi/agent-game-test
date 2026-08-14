# Tasks: [Bug] 修复 e2e runner — worktree 归属校验 + P5 plan source + 并发单例

> Parent Issue: #480
> 深度: depth/standard（5+ 跨子系统实现子任务 → TASKS 必需，同 #476 惯例）
> 依据: `docs/DESIGN/480-e2e-runner-fix.md`

## Phase 1: 并发单例锁 + cleanup 归属校验（runner P0）
- [ ] Task 1 (`scripts/run-e2e-review.sh`): 新增 `LOCK="$WORKTREE_ROOT/.e2e-$PR_NUM.lock"`（mkdir 原子创建）+ `LOCK_OWNED`/`WT_OWNED=0` 变量（§3.1.1 位置：L54 附近）
- [ ] Task 2 (`scripts/run-e2e-review.sh`): 新增 `acquire_lock()`（mkdir 成功→写 `$$` 到 `pid`；失败→`kill -0` stale 判定→回收重建；均失败→die "another instance running" exit 2）；`release_lock()`（`LOCK_OWNED=1` 时 `rm -rf`）；dry-run 首行 return 0
- [ ] Task 3 (`scripts/run-e2e-review.sh`): P0 接线 —— `acquire_lock` 先于既有 `[ -d "$WT" ]` 检查（L134 保留为第二道防线）；`worktree add` 成功后 `WT_OWNED=1`
- [ ] Task 4 (`scripts/run-e2e-review.sh`): `cleanup()`（L77-83）增加 `[ "$WT_OWNED" = "1" ]` 守卫 + 末尾 `release_lock`；`--keep` 保留 WT 但仍释放锁（§3.1.2）

## Phase 2: P5 worktree 优先 + visual 透传 + missed 检查（并入 #475 diff）
- [ ] Task 5 (`scripts/run-e2e-review.sh`): CAPTURE_SRC 双 worktree 优先 —— `"$WT/framework/templates/e2e_capture.gd"` 存在则用，否则回退 `$REPO_ROOT/...`（与 #475 diff 逐字一致）
- [ ] Task 6 (`scripts/run-e2e-review.sh`): visual config 透传 —— shot 级 `visual` 字段 → `--visual-config "$OUT/visual-<shot>.json"`，缺失不加 flag（§3.1.4）
- [ ] Task 7 (`scripts/run-e2e-review.sh`): missed-shot 检查 —— 每个 resolve 出的 shot 必须有 `$OUT/shots/<name>.png`，缺失 → `VISUAL_FAIL=1` + 日志（§3.1.5）

## Phase 3: pipeline 测试
- [ ] Task 8 (`tests/pipeline/test_e2e_runner.py`): 改造 `test_worktree_conflict_exits_2` —— 预建 `wt-impl-1` → exit 2 **且 `self._wt_exists()` 为 True**（原实现会误删）
- [ ] Task 9 (`tests/pipeline/test_e2e_runner.py`): 新增 `TestRunnerConcurrency`（TC1 存活锁拒绝 / TC2 stale 锁回收 / TC3 锁创建失败，DESIGN §9 Scenario A）
- [ ] Task 10 (`tests/pipeline/test_e2e_runner.py`): 新增 `TestRunnerOwnership`（TC4 非本实例 WT 保留 / TC5 本实例失败清理 / TC6 `--keep` 保留 WT 释放锁，Scenario B）
- [ ] Task 11 (`tests/pipeline/test_e2e_runner.py`): 新增 `TestRunnerP5WorktreeFirst`（TC7 模板来自 WT / TC8 缺失回退 / TC9 PLAN_SRC 优先 / TC10 visual 透传 flag / TC11 missed-shot L3 fail，Scenario C）
- [ ] Task 12 (验证): `python3 -m unittest discover -s tests/pipeline -v` 全绿（含既有 8+2 用例回归）

## Phase 4: 文档 + 真实并发演练
- [ ] Task 13 (`docs/PLAN-e2e-verification-v2.md`): P8 cleanup 描述补充归属校验 + 并发锁说明
- [ ] Task 14 (`framework/ARCHITECTURE.md`): E2E 验证体系节补充并发单例决策（可选，若篇幅允许）
- [ ] Task 15 (E2E 演练): 后台起 `scripts/run-e2e-review.sh <PR> --no-comment` 实例 A，再起实例 B → B exit 2 "another instance running" 且 A 的 worktree 完好；对含 e2e_shots.json/模板修改的 PR（如 #475）跑 runner，P5 日志 plan source = worktree 路径、capture 无类型错误（AC4/AC5 验收）

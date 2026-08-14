# Tasks: [Bug] 修复 L3 视觉 E2E — BgPulse 相位使背景桶泄漏进 region dominant → pair dist 0.0 + rain 假阳性

> Parent Issue: #485
> 深度: depth/standard（3 子系统 / 4 文件 / ~8 实现子任务；L3 断言族惯例 #466/#476/#480 均产 TASKS → 精简版）
> 依据: `docs/DESIGN/485-bgpulse-bg-bucket-leak.md`

> **⚠️ 基线硬性约束（implement 第一件事）:** analyze_bmp.py 的区域断言代码**只在 origin/impl/466-e2e-visual-regression 分支**（PR #475），main 的 analyze_bmp.py（340 行）无 check_visual。**分支必须基于 `origin/impl/466-e2e-visual-regression`**（`git fetch origin && git checkout -b impl/485-bgpulse-bg-bucket-leak origin/impl/466-e2e-visual-regression`），完成后再 merge origin/main（#475 若已合入则基线自动含入；若未合入，rebase 到 main 后 PR 目标仍为 main，review agent 协调顺序）。白名单提交用 `./scripts/worktree-commit.sh 485 "<msg>" <files...>`。

## Phase 1: analyze_bmp.py 动态 bg 采样核心（P0）
- [ ] Task 1 (`scripts/e2e/analyze_bmp.py`): 新增 `sample_bg_color(rows, x0, y0, x1, y1, exclude_buckets=None) -> tuple|None` —— region_stats 取 16 级桶 → dominant 桶（排除近黑 (0,0,0)）→ 该桶像素逐通道均值；无非排除桶 → None（DESIGN §2.1/§3.1.1）
- [ ] Task 2 (`scripts/e2e/analyze_bmp.py`): 新增共享辅助 `_resolve_bg(vcfg, rows) -> (bg_eff, exclude_buckets)` —— bg_sample 解析（定位 name=="bg" region，缺失 → 校验错误返回）、sample_bg_color → None 时降级静态 bg_color、exclude_buckets = {(0,0,0)} ∪ {bucket(bg_eff)}（DESIGN §3.1.3）
- [ ] Task 3 (`scripts/e2e/analyze_bmp.py`): `check_visual()` 贯通 —— region_stats(bg_color=bg_eff)、dominant_color(exclude_buckets)、name=="bg" 的 region dominant := bg_eff、rain_grid_coverage(bg_color=bg_eff)（DESIGN §3.1.2）
- [ ] Task 4 (`scripts/e2e/analyze_bmp.py`): `visual_detail()` 同源贯通 + `--json` 输出新增 `bg_ref`（十六进制）与 `bg_sample` 键（DESIGN §3.1.3）
- [ ] Task 5 (回归): `bg_sample` 缺省路径行为与 impl/466 基线逐字节一致（DESIGN §3.1.4）

## Phase 2: e2e_shots.json 配置（P0）
- [ ] Task 6 (`mini-pong/e2e_shots.json`): 02_midgame.visual 新增 `"bg_sample": true`；paddle region `min_nonbg_ratio` 0.05 → 0.025；其余字段（bg_color/rain/regions 坐标）不动（DESIGN §3.2）

## Phase 3: pipeline 单测（P0）
- [ ] Task 7 (`tests/pipeline/test_e2e_analyze.py`): 新增 `TestDynamicBgSampling` 类 —— Scenario F（5 相位 AC3：Test 1-3）、G（rain 非假阳性：Test 4-6）、H（采样边界：Test 7-10）、I（paddle 0.025：Test 11-13）（DESIGN §9）
- [ ] Task 8 (验证): `python3 -m unittest discover -s tests/pipeline -v` 全绿 —— 新增 ~13 用例 + 既有 12 用例（main 基线）+ impl/466 基线 visual 用例全部通过（DESIGN §9 Scenario J）

## Phase 4: 真机验收 + 文档同步（P1）
- [ ] Task 9 (AC1 真机): 同 head 连续 3 次 `scripts/run-e2e-review.sh`（对含 e2e_shots.json 改动的分支/PR），每次 `grep "P5 visual: pass"` 命中；记录 rain coverage 实测值（应 >60% 且非假阳性 100%）（DESIGN §8 Phase 5）
- [ ] Task 10 (`docs/DESIGN/466-visual-regression-e2e.md`): §5 边界表 "BgPulse 呼吸相位 → R_bg 主色变化" 缓解列一行同步为动态 bg 采样决策（DESIGN §3.3）
- [ ] Task 11 (AC4 引用): 确认 #480（runner missed-shot 判 fail）实现状态，在 PR body/评论注明引用关系（本 issue 不实现）

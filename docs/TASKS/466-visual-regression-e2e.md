# Tasks: [Test] 视觉回归 E2E — 玩家板可见 + 颜色区分 + 雨幕分布断言

> **Parent Issue:** #466
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Design:** docs/DESIGN/466-visual-regression-e2e.md
> **深度:** depth/standard（文件域 5 个、跨 scripts-e2e / mini-pong 配置 / tests-pipeline / scripts-runner / framework-template 5 子系统，达 TASKS 阈值 → 产出精简 TASKS 明确边界）
> **所有权:** `content_ownership: mechanical` — 区域/阈值/分布断言机械实现，无品味决策

---

## Phase 1: analyze_bmp.py 区域断言核心（P0）
- [ ] Task 1 (`scripts/e2e/analyze_bmp.py`): 新增纯函数 `region_stats()` / `dominant_color()` / `rgb_distance()` / `rain_signature()` / `rain_grid_coverage()` / `check_visual()`（DESIGN §3.1 签名与伪代码）—— 全部基于既有 `_read_png()` RGBA rows，纯 stdlib，近黑定义 r<8/g<8/b<8 与全局一致
- [ ] Task 2 (`scripts/e2e/analyze_bmp.py`): CLI 新增 `--visual-config <path.json>`（缺省 None → 行为逐字节不变）；`--json` 输出扩展 `visual` 键（region 主色/占比/距离/覆盖明细）

## Phase 2: 单测（P0，先行）
- [ ] Task 3 (`tests/pipeline/test_e2e_analyze.py`): 新增区域断言测试类（DESIGN §9 Scenario A/B/C/E 共 13 用例）—— 含 AC5 反向用例（Test 2/4）与向后兼容回归（Test 11）；沿用 `make_png`/`run_cli`/`write_png` 设施；`python3 -m unittest discover -s tests/pipeline -v` 全绿

## Phase 3: shot 配置 + 管线接线（P0）
- [ ] Task 4 (`mini-pong/e2e_shots.json`): 02_midgame 增 `visual` 配置（canvas/regions/compare_pairs/rgb_min_dist/rain，DESIGN §3.2 精确 JSON）+ require 数组化（player_score>=1 AND children_in_group bricks>=4）+ `theme_color` → `00e5ff`
- [ ] Task 5 (`scripts/run-e2e-review.sh`): P5 循环对每张 png 提取 plan.json 中 shot 级 `visual` 字段写入 `$OUT/visual-<shot>.json` 并透传 `--visual-config`（DESIGN §3.3 内联 python 片段；无 visual 字段的 shot 不传参，行为不变）

## Phase 4: capture 模板 require 扩展（P1）
- [ ] Task 6 (`framework/templates/e2e_capture.gd`): `_require_ok()` 重构为数组/单 dict 双路径 + 新增 `_require_one()` 支持 `children_in_group` 计数（DESIGN §3.4 精确 GDScript）—— **模板级兼容**：单 dict 旧格式行为逐字节不变；不碰 press/状态推进/settle/deadline
- [ ] Task 7 (mini-pong 侧验证): Godot 侧验证 `_require_ok` 数组 + children_in_group（DESIGN §9 Scenario D Test 8-10）—— implement agent 决定落点（新增或扩展既有 test 文件），遵循既有 test 结构

## Phase 5: 验证与提交（P0）
- [ ] Task 8 (验证): `python3 -m unittest discover -s tests/pipeline -v` 全绿（既有用例 + 新增）；`godot --path mini-pong/ --headless --quit` 无脚本错误（若触及 .gd）；`python3 scripts/e2e/analyze_bmp.py --help` 输出含 --visual-config
- [ ] Task 9 (提交): worktree 内 `./scripts/worktree-commit.sh 466 "docs(implement): ..." <白名单文件>`（绝不 git add .）→ PR（body `Parent #466`）→ CI → review agent 跑 run-e2e-review.sh 出具 midgame 区域断言证据（AC6）
- [ ] Task 10 (校准): 首次真机运行记录实测 非背景占比/三对距离/雨覆盖率，偏差 >20% 回填阈值（DESIGN §9 Test 14；PRD §8 决策 5）

## 明确不做（范围边界）
- ❌ `mini-pong/gdscripts/`、`scenes/`、`project.godot` 任何游戏代码（class A 红线，PRD §8 硬性要求 1）
- ❌ `resolve_plan.py`（shot 对象已原样透传，零改动）
- ❌ `e2e_capture.gd` 的 press 注入 / 状态推进 / settle / deadline 逻辑（预调查结论：状态推进已可用，AC1 零改动）
- ❌ 新建独立 `visual_assert.py`（Approach B 否决）
- ❌ 新建 runnable 测试文件于 plan 阶段（测试代码归 implement PR；本 PR 只含 DESIGN/TASKS 文档）
- ❌ `git add .` / `git stash`（worktree 红线）；不改 01_title/03_gameover 的 shot 配置

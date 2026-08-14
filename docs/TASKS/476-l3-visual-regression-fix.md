# Tasks: [Bug] 修复 main 上既有 L3 视觉回归 — clear_color 双重前缀 + bg-bucket 断言返工

> Parent Issue: #476
> 深度: depth/standard（5+ 跨子系统实现子任务 → TASKS 必需）
> 依据: `docs/DESIGN/476-l3-visual-regression-fix.md`

## Phase 1: main 修复（子系统 1 — 独立 PR，可先行 merge）
- [ ] Task 1 (`mini-pong/project.godot`): `[rendering]` 段键名 `rendering/environment/defaults/default_clear_color` → `environment/defaults/default_clear_color`（去双重前缀，值不变 `Color(0.039, 0.039, 0.071, 1)`）。验证：`grep -c "rendering/environment/defaults" mini-pong/project.godot` = 0
- [ ] Task 2 (`mini-pong/tests/test_neon.gd`): TC4（line 47）断言键名同步为 `environment/defaults/default_clear_color`（**必须与 Task 1 同 PR**，否则 L1 逻辑层回归 run_tests.gd:19）。验证：`tests/run_tests.gd` L1 全过

## Phase 2: 断言返工 — analyze_bmp.py（子系统 2，在 impl/466-e2e-visual-regression 分支，PR #475 内）
- [ ] Task 3 (`scripts/e2e/analyze_bmp.py`): `dominant_color()` 增加 `exclude_buckets` 参数（默认 `{(0,0,0)}` 向后兼容），bg 桶 `(0,0,1)` 由 visual 配置注入
- [ ] Task 4 (`scripts/e2e/analyze_bmp.py`): `region_stats()` 增加 `bg_color`/`bg_min_dist` 参数，nonbg 判定改为与 bg RGB 距离 ≥ 阈值（默认 None → 保持近黑规则）
- [ ] Task 5 (`scripts/e2e/analyze_bmp.py`): `rain_signature()` 增加 `bg_color`/`rain_bg_min_dist` 参数（与 bg 距离 < 阈值 → 非雨）；`rain_grid_coverage()` 透传
- [ ] Task 6 (`scripts/e2e/analyze_bmp.py`): `check_visual()`/`visual_detail()` 从 vcfg 读取 `bg_color` → 计算排除桶 + 透传 bg 参数；证据输出标注 bg 口径

## Phase 3: 配置 + 单测（子系统 2）
- [ ] Task 7 (`mini-pong/e2e_shots.json`): `02_midgame.visual` 增加 `bg_color:"0a0a12"`、`bg_min_dist:24`、`rain_bg_min_dist:24`；paddle 区域改全宽 `x0:0,x1:720`（保留 `min_nonbg_ratio:0.05`）
- [ ] Task 8 (`tests/pipeline/test_e2e_analyze.py`): 正向用例合成 PNG 背景 `BG_DARK=(4,4,4)` → `BG_REAL=(10,10,18)`；保留 1-2 个近黑兼容用例
- [ ] Task 9 (`tests/pipeline/test_e2e_analyze.py`): 新增反例 — bg 桶参与竞争、纯 bg 雨 coverage 0、板隐藏 nonbg fail、板在 x15-122 全宽捕获（DESIGN §9 Scenario B-E）

## Phase 4: 真实截图校准 + E2E 重跑（子系统 2）
- [ ] Task 10 (E2E): 重跑 `scripts/run-e2e-review.sh`（PR #475 或新 PR），真实截图验证 bg avg ≈ (10,10,18)、三色 dist ≥ 60、雨 coverage ≥ 60%、板任意 x 捕获
- [ ] Task 11 (回填): 按真实截图回填 `bg_min_dist`/`rain_bg_min_dist`/板条带 y 范围（DESIGN 466 §8 校准要求，不提交理论值）
- [ ] Task 12 (fallback 评估): 若全宽板条带与砖块误报 → 评估 `paddle_node` 节点路径方案（默认不启用）

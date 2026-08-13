# Tasks: [Feature] 视觉三色分层 — 可控物/目标物/环境颜色分离 (对比度修复)

> **Parent Issue:** #464
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Design:** docs/DESIGN/464-visual-three-color-layer.md
> **深度:** depth/standard（文件域 6 个、跨 constants/场景/材质/测试 4 子系统，按 #450 并行先例产出精简 TASKS —— worktree 并行需明确文件域边界）
> **所有权:** `content_ownership: mechanical` — 三色常量/场景引用/对比度断言机械实现；色值微调 = taste-draft（human-review 定稿，调参零代码改动）

---

## Phase 1: 常量 + 场景 + 材质（P0，视觉配置核心）
- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): 紧跟 `# ── Colors ──` 区之后（`AI_NEON_RED` 行后、`# ── Brick Wall (#384) ──` 区前）**新增** `# ── Visual Three-Color Layer (#464) ──` 区：`PADDLE_NEON: Color = Color(0.0, 0.898, 1.0, 1.0)`（#00e5ff）、`BRICK_NEON: Color = Color(1.0, 0.616, 0.271, 1.0)`（#ff9d45）（DESIGN §3.1 精确文本）
  - **并行红线**：只新增本区，既有 16+ 分区逐字节不动（#448 HUD 区 / #450 AUDIO 区已在 main，提交前 merge main 自动合并）
- [ ] Task 2 (`mini-pong/scenes/player_paddle.tscn`): ColorRect `color = Color(0.29, 0.56, 0.85, 1)` → `color = Color(0, 0.898, 1, 1)`（PADDLE_NEON **规范序列化字面**，与测试断言逐字节一致；material 引用不动）（DESIGN §3.2）
- [ ] Task 3 (`mini-pong/scenes/brick.tscn`): ColorRect 在 `material = ExtResource("2_neon_mat")` 行后**新增** `color = Color(1, 0.616, 0.271, 1)`（BRICK_NEON 规范序列化字面，AC4）（DESIGN §3.3）
- [ ] Task 4 (`mini-pong/assets/neon_glow_material.tres`): `shader_parameter/glow_width = 3.0` → `0.25`（glow_color #4a90d9 / glow_intensity 1.0 保留）—— **文件域扩展申报**：实现 PR 必须说明根因（glow_width=3.0 超出 shader hint 0–0.5 一个数量级 → 0.926 混合覆盖基底色，shader 数学见 PRD §1.1.1 / DESIGN §2）（DESIGN §3.4）

## Phase 2: 断言套件（P0）
- [ ] Task 5 (`mini-pong/tests/test_visual_contrast.gd`, 新文件): extends RefCounted + 同步 `run()` + `passed`/`failed`/`_assert`（沿用 test_neon 模板），实现 DESIGN §7 用例：
  - A: 常量存在与值（PADDLE_NEON / BRICK_NEON，容差 ±0.01）
  - B: 两两 RGB 欧氏距离 ≥ 60（期望 324/323/290）
  - C: WCAG 对比度 ≥ 4:1（`Color.get_luminance()`，期望 12.8:1）
  - D: HSV 色相分离 ≥ 60°（`Color.h()` 环形差，期望 157.7°）
  - E: tscn/tres 文本断言（`FileAccess.get_file_as_string` + `contains`）：player_paddle.tscn 含 `color = Color(0, 0.898, 1, 1)`、brick.tscn 含 `color = Color(1, 0.616, 0.271, 1)`、neon_glow_material.tres 含 `shader_parameter/glow_width = 0.25`
  - **注意**：断言字面与场景写入字面逐字节一致；**不得**用 PRD 原稿 `Color(1.0, ...)` 形式（§5.6）
- [ ] Task 6 (`mini-pong/tests/run_tests.gd`): 在 `_run("res://tests/test_constants.gd", "Constants")` 之后新增注册行 `_run("res://tests/test_visual_contrast.gd", "Visual Contrast")`（同步套件，与 test_neon 同型）（DESIGN §3.5）

## Phase 3: 验证与提交（P0）
- [ ] Task 7 (验证): `godot --path mini-pong/ --headless --quit` 无脚本错误；`godot --headless --script res://tests/run_tests.gd` 全绿（基线 2214 passed / 0 failed 不回退，新增 TC 后 ≥ 2214+N）；E2E loop 重跑（e2e_shots.json `theme_color=4a90d9` 存在性断言——若失败更新 e2e_shots.json，超文件域须 PR 说明，DESIGN §5.4）
- [ ] Task 8 (提交): 在 worktree 内 `./scripts/worktree-commit.sh 464 "docs(plan): ..." <6 个白名单文件>`（提交前自动 merge origin/main → 并行区自动合并；冲突按脚本分级处理，不硬解）→ PR（body `Parent #464`）→ CI → review → merge

## 明确不做（范围边界）
- ❌ `mini-pong/scenes/Main.tscn` / `world_environment.tscn`（BgPulse 已合规，零改动）
- ❌ `paddle.gd` / `brick.gd` / `breakout_grid.gd` / `bg_pulse.gd` / `neon_glow.gdshader`（零改动）
- ❌ `PLAYER_NEON_BLUE` / `AI_NEON_RED` / `BG_COLOR` / `BG_PULSE_TINT` 值（逐字节不动）
- ❌ rain 文件域（#465 并行，零重叠）；❌ HUD/升级 UI 语义色（#392 域）
- ❌ 新增材质实例 / 特效 / 第三方资产；❌ `git add .` / `git stash`（worktree 红线）
- ❌ 本 PR 写 runnable 测试文件（测试代码归 implement PR；本 PR 只含 DESIGN/TASKS 文档）

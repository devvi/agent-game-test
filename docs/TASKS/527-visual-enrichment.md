# Tasks: [Feature] 游戏画面迭代 — 雨夜竞技场画面丰富化执行层

> **Parent Issue:** #527
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Reference:** docs/DESIGN/527-visual-enrichment.md（本批唯一事实源，细节以 DESIGN 为准）
> **深度:** depth/standard —— 5 个子系统 = 5 个不同子系统的独立实现子任务（达 TASKS 阈值）
> **实现拆分:** 2 个实现 PR（PR-A = L0 光晕+暗角，低风险先合；PR-B = v1 色变+铁砖+L2 反馈）

---

## Phase 0 — Spike 前置验证（implement worktree 内，结果只影响参数/路径，不改变架构）

- [ ] Spike 1（PR-A）：`vignette.gdshader` headless 编译验证 + 暗角 alpha 0.10 对非黑断言验算（DESIGN §10）
- [ ] Spike 2（PR-B）：4 色 palette 对 02_midgame 色数/theme 断言影响实测
- [ ] Spike 3（PR-B）：铁砖 `material.duplicate()` + `set_shader_parameter("glow_color")` 渲染验证 + 默认砖逐字节不变确认
- [ ] Spike 4（PR-B）：破砖/穿墙信号链接线 + 脉冲帧对帧差断言影响实测

## Phase 1 — PR-A（L0 批，branch `impl/527-visual-enrichment` 或按实现惯例拆 A/B 分支）

- [ ] T1（constants.gd）：追加 `CITY_GLOW_*` + `VIGNETTE_*` 新区（DESIGN §4.2）；既有区逐字节不动
- [ ] T2（city_glow.gd，新）：程序化 GradientTexture2D 垂直渐变 + 复用 `BgPulse.compute_alpha` 呼吸（DESIGN §3.1）
- [ ] T3（vignette.gd + vignette.gdshader，新）：暗角 shader（Spike 1 失败 → fallback B' 径向 GradientTexture2D，删 .gdshader）（DESIGN §3.2）
- [ ] T4（Main.tscn）：AtmosphereLayer 挂 CityGlow（BgPulse 后）+ Vignette（RainCurtain 后，L0 最上）；新 ext_resource id（DESIGN §4.4）
- [ ] T5（test_visual_enrichment.gd，新，L0 部分）：Scenario A/C 断言（palette 域/A4 光晕避 theme/A3 暗角上限/C1-C5）；注册进 run_tests.gd
- [ ] T6：`godot --path mini-pong --headless --quit` 无错误 + run_tests.gd 全绿（AC6 零回归）
- [ ] T7：E2E `--with-visual` L1–L3（AC7）+ taste-draft 常量（光晕色调/暗角强度）→ human-review 定稿 → docs/TASTE.md 追加

## Phase 2 — PR-B（v1 批）

- [ ] T8（constants.gd）：追加 `WAVE_COLOR_*` + `BRICK_VARIANT_*` + `FX_*` 新区（DESIGN §4.2）
- [ ] T9（brick.gd）：`@export brick_variant: int = 0` + `apply_variant(variant, base_color)`（variant=0 不碰材质；variant≥1 显式色 + 材质 duplicate + glow_color）（DESIGN §4.3）
- [ ] T10（breakout_grid.gd）：`generate_wave` 读 `GameManager.get_wave_index()` 计算 palette 色；`_spawn_brick(pos, variant, base_color)` + 铁砖概率注入（波 2 起，复用全局 seed 可复现）（DESIGN §4.3）
- [ ] T11（feedback_fx.gd，新）：破砖闪光（3 实例池）+ 穿墙脉冲（全屏色带）+ 同帧仲裁帧守卫 + 终局守卫 + 容错接线（DESIGN §3.3）
- [ ] T12（Main.tscn）：ScoreFlash 后挂 FeedbackFX（PiercePulseRect + BrickFlashPool）（DESIGN §4.4）
- [ ] T13（test_visual_enrichment.gd，v1 扩展）：Scenario B/D 断言（B1-B6/D1-D6）；run_tests.gd 注册
- [ ] T14：headless 无错误 + run_tests.gd 全绿（AC6）
- [ ] T15：E2E `--with-visual` L1–L3（AC7）+ palette/铁砖配色 taste-draft → human-review 定稿 → docs/TASTE.md 追加 + docs/PLAN-rogue-pong.md §3.1/§5 落地打勾

## 全局红线（每 PR 提交前自查）

- [ ] PR files 白名单（AC8）：PR-A ⊆ 6 文件 / PR-B ⊆ 7 文件（DESIGN §8）；不混入升级池/暂停/雨幕/标题/score_flash/world_environment 等文件
- [ ] 不修改：brick.tscn color 字面（test_visual_contrast E2-2）、neon_glow_material.tres（E3-2）、world_environment.tscn（test_neon TC2/TC3）、e2e_shots.json / analyze_bmp.py
- [ ] 新增色避开 #4a90d9（tol 32）；暗角峰值 ≤ 0.10；动效 Tween ∈ [150,300]ms 不弹跳
- [ ] `worktree-commit.sh` 白名单 add，绝不 `git add .`
- [ ] PR body 格式 `Parent #527`（无冒号）供 workflow-chain label 推进

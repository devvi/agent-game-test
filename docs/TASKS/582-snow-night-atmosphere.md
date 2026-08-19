# Tasks: [Rendering] 雪夜氛围（雪幕 / 冷月光 / 水墨晕染 / 血色 vignette）

> **Parent Issue:** #582
> **深度:** standard —— 11 文件（7 新建 + 4 修改）/ 4 氛围子系统 + 挂载集成 = 6+ 独立子任务（触发 TASKS 阈值：10+ 文件、5+ 独立子任务跨多子系统）
> **依据:** `docs/DESIGN/582-snow-night-atmosphere.md`（plan PR 已合并后本清单即 implement 的合同）

## Phase 0: Spike 验证（PRD §7 三实验，先于编码）
- [ ] Spike 1 (`gdscripts/ink_wash.gdshader`): 最小全屏 ColorRect + canvas_item shader 在 `godot --path shandong-wolf/ --headless --quit` 编译通过 + 截图有径向暗角（排除 CI 风险）
- [ ] Spike 2 (`scenes/atmosphere/`): 三层雪幕基线截图——`snow_wind=0` 下近景大而快 / 远景小而慢，纵深肉眼成立
- [ ] Spike 3 (`gdscripts/atmosphere_controller.gd`): 冷月光候选 B（`#6e7684` 单节点）vs 候选 A（`#b8c4d9` + modulate）同帧截图对比，锁定 AC2 实现语义（倾向 B，候选 A 备用）

## Phase 1: constants.gd 氛围分区（P0）
- [ ] Task 1 (`gdscripts/constants.gd`): 文件尾部追加「氛围参数」# DRAFT 分区——SNOW_*（12 项）/ MOONLIGHT_*（3 项）/ INK_*（5 项）/ BLOOD_*（3 项），含候补值注释 + 该值影响什么 + 情感断言（源码见 DESIGN §3.2，可直接采用）

## Phase 2: 四个氛围组件（P0）
- [ ] Task 2 (`gdscripts/snow_curtain.gd`): 三层雪幕控制器——`apply_tunables()`（velocity/scale/alpha/wind 下发）+ `set_wind()`；文件头禁改 amount 红线注释；@export 默认取常量
- [ ] Task 3 (`gdscripts/ink_wash.gdshader`): 水墨 shader（~20 行 GLSL，源码见 DESIGN §2.3）——径向暗角 edge_alpha ≤0.3 + hash 噪声渗化
- [ ] Task 4 (`gdscripts/blood_vignette.gd` + `blood_vignette.gdshader`): 血色 vignette——CanvasLayer layer=10 + ColorRect + 径向 shader + `set_enabled()` 幂等 + Tween 0.5s（alpha 0↔0.35）+ `get_visual_alpha()` 采样口
- [ ] Task 5 (`gdscripts/atmosphere_controller.gd`): 编排入口——`_ready()` 下发月光色/水墨 uniform/雪幕调参；契约 API `set_low_health(enabled)` + `debug_trigger_low_health()` / `debug_clear_low_health()`（#575 未建期兜底）；文件头层级约定注释（2/3-5/10）

## Phase 3: 场景组件 + 挂载（P0）
- [ ] Task 6 (`scenes/atmosphere/atmosphere_layer.tscn`): 组装氛围层场景组件——根 Atmosphere(Node2D, controller) + SnowCurtain（3×CanvasLayer 3/4/5 > Parallax2D 0.2/0.5/1.0 > GPUParticles2D amount 60/60/80，发射区域 = 视口 + margin）+ Moonlight(CanvasModulate #6e7684) + InkWashLayer(CanvasLayer 2 + ColorRect full-rect + shader) + BloodVignette(CanvasLayer 10)；ColorRect mouse_filter=IGNORE
- [ ] Task 7 (`scenes/Main.tscn`): 根节点下实例化 atmosphere_layer.tscn（Atmosphere 子节点）；现有 UI 节点零改动
- [ ] Task 8 (`tests/run_tests.gd`): `_run_tests()` 追加 `_run("res://tests/test_atmosphere.gd", "Atmosphere")`

## Phase 4: 测试套件（P0）
- [ ] Task 9 (`tests/test_atmosphere.gd`): 按 DESIGN §8 用例描述实现——A（参数分区/硬约束）、B（三层结构/amount 180-220/scroll_scale/scale/禁 amount 源码 grep）、C（月光节点色值）、D（水墨 uniform 上限/全屏/不挡输入）、E（血色层级/0.5s 渐变到 0.35/回落/幂等/契约直达）；套件模式照 test_constants.gd（passed/failed + run()）

## Phase 5: E2E 截图 + 用户裁决（P0）
- [ ] Task 10 (`e2e_shots.json`): 追加 `snow_night` 组单帧 shot（match gdscripts/scenes，settle_frames 30，注释「#582 单帧氛围截图供用户 ≥70% 裁决，完整剧本归 #586」）；若 #586 harness 未接入，用 headless 截图脚本产出单帧 PNG
- [ ] Task 11 (PR 附属): 实现 PR 附截图（非黑屏/全白，标题文字可读）+ issue 评论 + assign 用户裁决（taste-draft：≥70% 定稿，<70% 改 constants 候补值重跑）

## 验证清单（收尾）
- [ ] `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0（覆盖新增 5 gdscripts + 2 gdshader + 1 tests）
- [ ] `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 退出 0（含 Atmosphere 套件 A-E 全过）
- [ ] `godot --path shandong-wolf/ --headless --quit` 退出 0（Main.tscn + Atmosphere 实例启动链）
- [ ] PR diff 核查：无 mini-pong/、无 .png/.jpg 等外部资产、constants.gd 仅尾部追加

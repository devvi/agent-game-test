# Tasks: [Scene] 雪夜山东村战斗场景（单场景 MVP 舞台）

> **Parent Issue:** #583
> **深度:** standard（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=12 标注 depth: standard；GitHub 无 depth 标签）—— 7 文件（4 新建 + 3 修改）/ 7 独立子任务跨多子系统（平台几何、剪影物件、月亮、出生点+相机、常量分区、E2E 截图、测试套件）→ **产出 TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统）
> **依据:** `docs/DESIGN/583-snowy-shandong-village-battle-stage.md`（plan PR 已合并后本清单即 implement 的合同）

## Phase 0: Spike 验证（PRD §7 三实验，先于编码）
- [ ] Spike 1 (`scenes/battle_stage.tscn` + `gdscripts/moon_glow.gdshader`): 月亮光晕 3 变体截图对比——shader 同心衰减 / 双层半透明圆 / 单圆无光晕，锁定 §2.1.5 主路径与回退路径（预期 shader 最优，双层圆为回退）
- [ ] Spike 2 (`tests/test_battle_stage.gd`): 全宽走查——CharacterBody2D 从 x=0 匀速移至 x=2400（velocity.y=0），断言帧位移连续零阻塞（确认 §2.1.1 方案 A；预期不失败）
- [ ] Spike 3 (Mac): battle_stage + Atmosphere 同屏 60s 帧时间均值/1% low，确认 ≥60fps（AC4；若不足降物件复杂度 ≤5 内，不降粒子预算）

## Phase 1: constants.gd 场景分区（P0）
- [ ] Task 1 (`gdscripts/constants.gd`): 文件尾部追加「场景参数」# DRAFT 分区——STAGE_*（2）/ PLATFORM_*（5）/ 色板 *COLOR（4）/ MOON_*（4）/ 物件机械常量（2），含候补值注释 + 该值影响什么 + 情感断言（源码见 DESIGN §3.2，可直接采用）；**不动既有任何分区一行**

## Phase 2: battle_stage.tscn 本体（P0）
- [ ] Task 2 (`scenes/battle_stage.tscn`): 平台——Ground StaticBody2D + CollisionShape2D（RectangleShape2D 2400×24，顶面 y=PLATFORM_Y_BASE=560，单一连续碰撞面）+ 视觉分层（SnowDriftFront 雪堆 Polygon2D 3 段白色 α0.6 低 60-100px / PlatformSilhouetteMid/Back 墨色剪影 2 层）；全部坐标/尺寸声明在 .tscn
- [ ] Task 3 (`scenes/battle_stage.tscn`): 剪影物件——草屋 ×2（Hut Polygon2D 墨色 + RoofSnowLine Line2D 白色屋顶压雪线，屋脊 ≤120px，x≈300/1900）+ 枯树 ×2（Line2D 骨架，x≈900/1500）+ 山峦（Line2D 多层远景，不计数）；物件计数 = 4 ≤ 5
- [ ] Task 4 (`scenes/battle_stage.tscn`): 月亮——Moon Mesh2D 径向渐变圆（MOON_COLOR #b8c4d9 同源，半径 42px，y≈140 苍月悬顶）+ MoonGlow（moon_glow.gdshader 光晕或双层半透明圆回退，Spike 1 裁决）；**非 CanvasModulate**（C3 守卫）
- [ ] Task 5 (`scenes/battle_stage.tscn`): 出生点 + 相机——Marker2D ×3（PlayerSpawn/EnemySpawnA/EnemySpawnB，坐标 .tscn 声明，与物件包围盒无交集）+ StageCamera（Camera2D current=true、position_smoothing=false、limits 0-2400 含 margin）；出生点坐标即 #581 EnemyAI.waypoints 数据来源（#585 配置）

## Phase 3: E2E 组件 + 挂载（P0）
- [ ] Task 6 (`scenes/e2e_battle_stage_capture.tscn`): 截图像具场景——CaptureRig 根 + instance battle_stage + instance atmosphere_layer.tscn（复用 #582 氛围，唯一 moon 归 Atmosphere）+ 驱动桩（current_state 轮询契约）
- [ ] Task 7 (`e2e_shots.json`): 追加 `battle_stage` 组——main_scene = e2e_battle_stage_capture.tscn，3 shot（01_stage_panorama 全景 settle 30 / 02_platform_closeup 平台近景 settle 15 / 03_moon_composition 月亮构图 settle 15），_comment 注明「#583 供用户 AC5 裁决地域感（无日本/西化元素）」；既有三组零改动
- [ ] Task 8 (`tests/run_tests.gd`): `_run_tests()` 追加 `_run("res://tests/test_battle_stage.gd", "BattleStage")`

## Phase 4: 测试套件（P0）
- [ ] Task 9 (`tests/test_battle_stage.gd`): 按 DESIGN §8 用例描述实现——A（可加载/宽度 2400/平台 3 段+单一碰撞面/物件 ≤5/零贴图+无 CanvasModulate）、B（碰撞阻挡 y 差 <1px/全宽走查/出生点布局）、C（色板 ±10%/月亮构图/luma ≥30/C4 计数 ==1）、D（相机 current+limits/贴边不露白）；套件模式照 test_atmosphere.gd（passed/failed + run()）

## Phase 5: E2E 截图 + 用户裁决（P0）
- [ ] Task 10 (PR 附属): headless 产出 battle_stage 组 3 shot PNG（全景/平台近景/月亮构图），非黑屏非全白；实现 PR 附截图 + issue 评论 + assign 用户裁决（AC5 taste-draft：认可定稿，不认可改 constants 候补值重跑——DESIGN Flow 3）

## 验证清单（收尾）
- [ ] `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0（覆盖新增 .gd/.gdshader，check_compile 自动纳入）
- [ ] `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 退出 0（含 BattleStage 套件 A-D 全过）
- [ ] `godot --path shandong-wolf/ --headless --quit` 退出 0（autoload + Main.tscn 启动链兼容，battle_stage 未挂载期不回归）
- [ ] PR diff 核查：无 mini-pong/、无 .png/.jpg 等外部资产、无 CanvasModulate 新增、constants.gd 仅尾部追加、Main.tscn 零改动
- [ ] AC5 截图 3 张附 PR + issue 评论 + assign 用户（用户裁决是定稿入口，PR 不写 Closes）

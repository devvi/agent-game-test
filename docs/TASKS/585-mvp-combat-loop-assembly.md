# Tasks: [Integration] 组装 MVP 战斗闭环（可玩版本）

> **Parent Issue:** #585
> **深度:** standard（PRD 头标注 depth: standard；GitHub 无 depth 标签）—— 7 文件（2 新建脚本 + 1 新建测试 + 1 新建 E2E rig + 3 修改）/ 13 项接线子任务跨 11 子系统 → **产出 TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统）
> **依据:** `docs/DESIGN/585-mvp-combat-loop-assembly.md`（plan PR 已合并后本清单即 implement 的合同）

## Phase 0: Spike 验证（PRD §7 三实验，先于编码）
- [ ] Spike 1 (`tests/test_main_assembly.gd`): 组装顺序时序——_ready 内 13 步 bind 全同步完成后首帧 resolve 正常（预期 0 顺序敏感点，DESIGN §4 Flow 4 顺序契约）
- [ ] Spike 2 (E2E): 失败字幕时序——death 反馈后 ≥0.5s 字幕淡入 1s，截图可辨（DESIGN §2.2 时序参数）
- [ ] Spike 3 (`tests/test_main_assembly.gd`): 余韵 5s 状态边界——afterglow 期间注入 move/attack，只读不打断、无目标攻击落空无报错

## Phase 1: constants.gd 组装分区（P0）
- [ ] Task 1 (`gdscripts/constants.gd`): 文件尾部追加「组装编排」# DRAFT 分区——AFTERGLOW_SECONDS / FAIL_SUBTITLE_DELAY / FAIL_SUBTITLE_FADE_SECONDS / TUTORIAL_HINT_DELAY + FAIL_SUBTITLE_CANDIDATES（B5 候选 5 选 1）/ TUTORIAL_HINT_CANDIDATES（taste 候选），含候补值注释（源码见 DESIGN §3.3）；**不动既有任何分区一行；实现期禁止二选一偷定**

## Phase 2: main_battle.gd 装配 + 接线（P0）
- [ ] Task 2 (`gdscripts/main_battle.gd`): 装配骨架——Node2D + GameState 枚举（IDLE/COMBAT/KILL/AFTERGLOW/FAIL）+ game_state_changed/fail_subtitle_shown 信号 + _set_game_state 幂等迁移（FAIL 终态）
- [ ] Task 3 (`gdscripts/main_battle.gd`): 玩家装配——PlayerController.new()（组 player）@ PlayerSpawn + instance player_stick_figure.tscn 子节点 + CombatEntity.new({is_player=true, life_total=2}) + bind_input_controller(InputController) + entity.state_changed → stick.consume_state 连线
- [ ] Task 4 (`gdscripts/main_battle.gd`): 敌人装配——EnemyAI.new() @ EnemySpawnA（waypoints 从出生点坐标派生）+ instance player_stick_figure.tscn 子节点 + CombatEntity.new({is_player=false, life_total=1}) + ai.bind_entity + ai.player/ai.judge 注入；EnemySpawnB 备用
- [ ] Task 5 (`gdscripts/main_battle.gd`): Judge/HUD/Reaction/Revive/Execution 实例化 + 13 步 bind（DESIGN §6 集成点 5-9）——judge.bind_entities+bind_input / hud.bind_player+set_target_enemy / reaction.bind_judge+subscribe_entity×2+camera_path=StageCamera / revive.bind_player / execution 5 项 bind
- [ ] Task 6 (`gdscripts/main_battle.gd`): 低血氛围单点接线 hud.low_health_changed → atmosphere.set_low_health（DESIGN §6 #10）

## Phase 3: 失败字幕 + 余韵 + 教学提示（P0）
- [ ] Task 7 (`gdscripts/main_battle.gd`): 失败路径——player.died(final=true) → FAIL 态 → 输入冻结（ic.set_process(false)）+ AI 停用 + FailLabel 延迟淡入（文案 ∈ FAIL_SUBTITLE_CANDIDATES，禁自行定稿）
- [ ] Task 8 (`gdscripts/main_battle.gd`): 余韵编排——enemy.died(final=true) → KILL → AFTERGLOW + Timer(AFTERGLOW_SECONDS) → 到期回 IDLE
- [ ] Task 9 (`gdscripts/main_battle.gd`): 教学提示——TUTORIAL_HINT_DELAY 后浮现提示 Label（文案 ∈ TUTORIAL_HINT_CANDIDATES）→ 数秒淡出；_ready 末步隐藏标题 CenterContainer

## Phase 4: Main.tscn 挂载（P0）
- [ ] Task 10 (`scenes/Main.tscn`): + ext_resource battle_stage.tscn + main_battle.gd → + BattleStage instance + MainBattle Node2D（DESIGN §3.2 逐字）；**不删既有节点、不重复挂 Atmosphere**

## Phase 5: 测试套件 + smoke（P0）
- [ ] Task 11 (`tests/test_main_assembly.gd`): 按 DESIGN §8 场景 A-F 实现（挂载完整/bind 非 null/信号链连通/闭环冒烟/失败路径/余韵时序）；套件模式照 test_battle_stage.gd（passed/failed + run()）
- [ ] Task 12 (`tests/run_tests.gd`): `_run_tests()` 追加 `_run("res://tests/test_main_assembly.gd", "MainAssembly")`
- [ ] Task 13 (`tests/smoke_test.gd`): 追加 Scenario II（AC4 完整闭环驱动 + 失败字幕子场景，headless exit 0）

## Phase 6: E2E 截图 + 用户裁决（P1）
- [ ] Task 14 (`scenes/e2e_main_assembly_capture.tscn` + `e2e_shots.json`): 新建 rig（CaptureRig + instance Main.tscn，照 e2e_battle_stage_capture 模式）+ 追加 assembly 组 4 shot（01_spawn_combat / 02_parry_execute / 03_fail_subtitle / 04_afterglow），_comment 注明供用户 AC 裁决（失败文案/教学文案/处决构图）
- [ ] Task 15 (PR 附属): headless 产出 assembly 组截图附 PR + 文案候选清单（失败字幕 B5 5 选 1 + 教学提示）附 PR + issue 评论 + assign 用户裁决；PR 说明开源调研结论（PRD §6.2：模板不引入，编排模式作参考）

## 验证清单（收尾）
- [ ] `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0（覆盖 main_battle.gd，check_compile 自动纳入）
- [ ] `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 退出 0（15 套既有 + MainAssembly 全过）
- [ ] `godot --path shandong-wolf/ --headless --script tests/smoke_test.gd` 退出 0（AC4 闭环自动跑通）
- [ ] `godot --path shandong-wolf/ --headless --quit` 退出 0（Main.tscn 装配后启动链兼容）
- [ ] PR diff 核查：无 mini-pong/、无 .png/.jpg 等外部资产、无第三方 addon、constants.gd 仅尾部追加、Main.tscn 仅追加 2 节点、17 组件脚本零改动、无 DRAFT 值定稿、无 taste 文案裁决
- [ ] E2E assembly 组 4 shot 稳定产出（非黑屏非全白）+ 文案候选清单随 PR + 用户裁决（taste 定稿入口）

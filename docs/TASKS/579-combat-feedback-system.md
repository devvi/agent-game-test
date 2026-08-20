# Tasks: [Rendering] 打击反馈系统（火花 / hit-stop / 屏震 / 慢动作 / 白闪）

> **Parent Issue:** #579
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **深度:** deep（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=8 标注 depth: deep；GitHub 无 depth 标签）—— 11 文件（8 新建 + 3 修改）/ 5 反馈子系统 + E2E rig = 8+ 独立子任务 → **TASKS doc 必需**
> **参考:** `docs/DESIGN/579-combat-feedback-system.md`（§2 新组件 / §3 既有修改 / §8 测试场景为唯一契约）+ `docs/PRD/579-combat-feedback-system.md`（§8.3 接口契约 / §7 实验）
> **红线:** 只动 shandong-wolf/ 下 11 文件；绝不触碰 combat_entity.gd / combat_states.gd / combat_state_table.gd / sword_arc.gd / Main.tscn / mini-pong/ / manifest / CI / GDD；零第三方 addon；**禁止把任何 # DRAFT 值「顺手定稿」**（taste-draft，定稿归 #584/用户）；`Engine.time_scale` 只经 TimeScaleStack 写入；全屏闪白仅限 A- 级 100ms 低 alpha；**PR body 用 `Parent #579` 不写 Closes/Fixes/Resolves**（issue 当前 CLOSED 是 research PR #641 误写 Closes 所致，R5 已知问题，本阶段禁止再触发自动关闭）

## Phase 0: Spike 验证（PRD §7 实验，0.5 天，先于 Phase 1-6）

- [ ] Spike 1（时间栈嵌套恢复，PRD 实验 1 / DESIGN D1）：最小脚本验证 push(0.05,150)→push(0.3,200)→中间值 0.05（min 语义）→逐层 pop→1.0；漏 pop 模拟推进墙钟断言 tick() 强制恢复（DESIGN §2.3/§8 Scenario B）
- [ ] Spike 2（GPUParticles2D one_shot 时序，PRD 实验 3）：最小粒子场景验证 restart()+emitting=true 注入帧内可靠爆发、位置==注入世界坐标、z_index 生效（DESIGN §2.2；若 one_shot 时序不稳 → 回退 CPUParticles2D 方案 B）
- [ ] Spike 3（屏震衰减曲线，PRD 实验 2）：trauma² 指数 vs 线性在 3px/4px 幅值对比 3 帧截图，确认指数衰减 + C 级 2px 沿攻击方向可感知（DESIGN §2.4）
- [ ] Spike 4（实体白闪可行性）：modulate 冲 Color(5,5,5) 保持 100ms 渐回 WHITE 对深色火柴人（#2b2b2b）是否冲白；被钳制 → 改用临时自发光覆盖（taste 域 # DRAFT，DESIGN §2.5）

## Phase 1: constants.gd 反馈分区（P0，0.5 天）

- [ ] 1.1 (`shandong-wolf/gdscripts/constants.gd`)：文件尾部追加「反馈分区」——FEEDBACK_SPARK_COUNT {S:14,A:18,B:6,C:8} / FEEDBACK_SPARK_COLOR Color("#ffd9a0") / FEEDBACK_HITSTOP_MS {S:150,A:90,A_:100,B:30,C:50,PH:60} / FEEDBACK_SHAKE_PX {S:4,A:3,A_:3,B:1,C:2,PH:4} / FEEDBACK_SLOWMO {S:{0.05,500},A:{0.3,200},A_:{0.5,300}} / FEEDBACK_FLASH {A:{0.35,120},A_:{0.25,100}} / FEEDBACK_TIME_MAX_STACK 3 / FEEDBACK_SPARK_Z_INDEX -1（DESIGN §3.2 逐字落地）
- [ ] 1.2 (同上)：追加 # DRAFT 候补值——FEEDBACK_SPARK_VELOCITY / LIFETIME（按等级）/ FEEDBACK_SHAKE_DECAY / FEEDBACK_ENTITY_FLASH_FACTOR，各带候补值 + 影响 + 情感断言注释（格式照 #572 分区）
- [ ] 1.3 (同上)：**禁止**去 `# DRAFT` 标记、禁止改正式值、禁止散落硬编码（Scenario A Test 4 grep 断言会查）

## Phase 2: time_scale_stack.gd（P0，0.5 天）

- [ ] 2.1 (`shandong-wolf/gdscripts/time_scale_stack.gd`)：class_name TimeScaleStack extends RefCounted；`push(scale, duration_ms)`（MAX_STACK_DEPTH 超限丢弃 + 记录墙钟 deadline）/ `pop()` / `tick(now_ms)` 到期强制移除 / `_apply()` 取栈内最小 scale（D1 min 语义，DESIGN §2.3）
- [ ] 2.2 (同上)：hit-stop 用 0.05 而非 0（0 冻结引擎处理兜底失效）；Engine.time_scale 写入口唯一（后续组件禁止直接赋值）

## Phase 3: feedback_spark.gd（P0，0.5 天）

- [ ] 3.1 (`shandong-wolf/gdscripts/feedback_spark.gd`)：class_name FeedbackSpark extends GPUParticles2D；one_shot=true、材质代码创建（零 .tres）、color_ramp #ffd9a0、z_index 读 C.FEEDBACK_SPARK_Z_INDEX（< 角色层）
- [ ] 3.2 (同上)：`burst_at(world_pos, normal, level)`——global_position=world_pos、direction=normal、amount 按等级、restart()+emitting=true 标准序列（DESIGN §2.2）

## Phase 4: screen_shake.gd（P0，0.5 天）

- [ ] 4.1 (`shandong-wolf/gdscripts/screen_shake.gd`)：class_name ScreenShake extends Node；`@export camera_path`（null/失效 no-op + push_warning）；`shake(max_offset_px, direction)` trauma 取 max 不叠加（DESIGN §2.4）
- [ ] 4.2 (同上)：`_process`——offset = 噪声 × trauma² × max_offset、trauma 指数衰减单调回归 0、终值回零

## Phase 5: flash_effect.gd（P0，0.5 天）

- [ ] 5.1 (`shandong-wolf/gdscripts/flash_effect.gd`)：class_name FlashEffect extends Node；`flash_entity(entity, alpha, ms)`——is_instance_valid 防护 + modulate Tween 冲高渐回（Spike 4 结论落地）；`flash_screen(alpha, ms)`——CanvasLayer layer=0 + ColorRect 全屏淡闪（仅 A- 调用点）
- [ ] 5.2 (同上)：全屏淡闪参数读 C.FEEDBACK_FLASH["A_"]（0.25/100ms）；层序低于 UI/氛围层

## Phase 6: reaction_controller.gd（P0，1 天）

- [ ] 6.1 (`shandong-wolf/gdscripts/reaction_controller.gd`)：class_name ReactionController extends Node2D；FEEDBACK_MATRIX（9 事件 × 等级 × 参数包，DESIGN §2.1 矩阵表逐字落地）；`trigger_feedback(event, data)` 公开 API（未知事件 push_warning + no-op）
- [ ] 6.2 (同上)：`bind_judge(judge)` 五结果事件直连（has_signal 防护，handler → trigger_feedback source:"judgment"）；`subscribe_entity(entity)` 信号订阅（state_changed 闭包捕获实体 D2/D4 + _entities 查重）
- [ ] 6.3 (同上)：`_derive_impact_point(attacker, defender, direction)`——SwordPivot 中点 + 法线推导 + 无 pivot 回退 push_warning（D3）；S 级处决复用 SwordArc.trigger_burst()
- [ ] 6.4 (同上)：`_process` 驱动 time_stack.tick()（墙钟兜底轮询）；`signal feedback_played(event, level, data)`（#593 hook，只发信号不发声）；组合触发单帧完成（AC2）

## Phase 7: 测试（P0，0.75 天）

- [ ] 7.1 (`shandong-wolf/tests/test_reaction_controller.gd`)：extends Object + run()/_assert 模式（照 #584 先例）；Scenario A 矩阵完备/单调/慢动作限级/反页游/未知事件（AC1/AC5）
- [ ] 7.2 (同上)：Scenario B 时间栈三路径 + 栈深上限 + 非零断言（AC4）；Scenario C 火花位置/方向/粒子数/层级/颜色（AC3）
- [ ] 7.3 (同上)：Scenario D 屏震衰减/方向/no-op/取 max；Scenario E 白闪双通道/失效防护/仅 A- 调用点/层序
- [ ] 7.4 (同上)：Scenario F 四要素同帧（AC2 决定性）+ feedback_played；Scenario G 碰撞点推导/回退/身份映射（D4）
- [ ] 7.5 (`shandong-wolf/tests/run_tests.gd`)：`_run("res://tests/test_reaction_controller.gd", "ReactionController")` 注册

## Phase 8: E2E 截图 rig（P1，0.75 天）

- [ ] 8.1 (`shandong-wolf/gdscripts/e2e_feedback_capture.gd` + `scenes/e2e_feedback_capture.tscn`)：CaptureRig 变体——Camera2D + ReactionController + 双火柴人（复用 player_stick_figure.tscn）+ `inject_feedback(event)` + digit 键映射（4→parry_success/6→stance_broken/7→execute/2→hit_landed）+ `current_state` 轮询兼容（DESIGN §2.6）
- [ ] 8.2 (同上)：**冻结效果帧模式**——`freeze_effects` 开启后时间栈墙钟不推进，火花/白闪停留画面供截图（AC2 兜底）
- [ ] 8.3 (`shandong-wolf/e2e_shots.json`)：追加 fb_parry_success / fb_stance_break / fb_execute 三档 shot（settle_frames 覆盖效果窗口，格式照 #574 既有条目，DESIGN §3.4）
- [ ] 8.4 验证：headless 跑 `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 全绿；E2E 三档截图产出，PR 附截图路径供 review agent 提交用户裁决（AC6）

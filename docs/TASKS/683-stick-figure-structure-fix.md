# Tasks: 角色绘制修正：火柴人结构完整化（缺头 / 走路动画异常 / 骨架一致性）

> **Parent Issue:** #683
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **依据:** `docs/DESIGN/683-stick-figure-structure-fix.md`（方案 A 全项采纳；深度 standard → 6 项子任务跨 4 子系统，产出 TASKS）
> **红线:** 只动 DESIGN §10 允许的文件；不写可运行测试文件（测试代码归 implement agent，但**测试文件本身的增改**在 Phase 5）；全部新值 # DRAFT 协议，定稿归 #584

## Phase 1: constants.gd # DRAFT 新值/修订（P0）
- [ ] Task 1 (`shandong-wolf/gdscripts/constants.gd`): 新增 `BODY_NECK_LENGTH`（候选 8–12，默认 10）、`BODY_LEG_UPPER_LENGTH`/`BODY_LEG_LOWER_LENGTH`（候选 18–22，默认 20）、`HEAD_OUTLINE_ENABLED`(false)/`HEAD_OUTLINE_WIDTH`(2.0)/`HEAD_OUTLINE_COLOR`(SWORD_COLOR 系)、`FRAME_ANIM_MOVE_CYCLE`(24)、`MOVE_SWING_LEG_DEG`(25)/`MOVE_SWING_ARM_DEG`(25)/`MOVE_KNEE_BEND_DEG`(40)、`KNEE_BEND_MAX_DEG`(90)、`POSE_DELTA_MAX_DEG`(15)、`MOVE_PLAYBACK_SPEED_MIN`(0.3)/`MOVE_PLAYBACK_SPEED_MAX`(1.2)、hold 型 clip 归位段 `FRAME_ANIM_*_EXIT`(2–4)——全部带「候补值+影响什么+情感断言」三要素 # DRAFT 注释（DESIGN §3.1 表）
- [ ] Task 2 (`shandong-wolf/gdscripts/constants.gd`): 修订 `BODY_HEAD_RADIUS` 16.0 → 9.5（候选 9–10，注释说明 GDD 比例依据）；`FRAME_ANIM_MOVE_STEP` 语义修订（值 4 保留 = 关键姿态数，注释更新，三要素保持——E3 断言依赖，禁止删除常量）
- [ ] Task 3: 实现前确认 #584 定稿状态，对齐帧数值标注协议

## Phase 2: stick_figure.gd 骨架结构（P0）
- [ ] Task 4 (`shandong-wolf/gdscripts/stick_figure.gd`): `_build_skeleton()` 头部改造——TorsoPivot 下新增 NeckPivot + 颈 Line2D（BODY_NECK_LENGTH），HeadPivot 改挂 NeckPivot 下（DESIGN §2.1 节点树）；`@export` 增 body_neck_length；`_validate_geometry()` defaults 同步
- [ ] Task 5 (`shandong-wolf/gdscripts/stick_figure.gd`): 腿两段化——LegLPivot/LegRPivot 保持为髋 pivot，新增子膝 LegKPivot + 小腿 Line2D（BODY_LEG_UPPER/LOWER_LENGTH，DESIGN §2.2）；`get_pivot()` 增 "neck"/"leg_k_l"/"leg_k_r" 键
- [ ] Task 6 (`shandong-wolf/gdscripts/stick_figure.gd`): 头轮廓（可选）——HEAD_OUTLINE_ENABLED 时 HeadPivot 下追加圆环 Polygon2D（外圆 head_r+outline_w，holes 内圆 head_r，颜色 HEAD_OUTLINE_COLOR，DESIGN §2.1 可选项）；SwordArc/sprite_slot/set_sprite_slot 零改动

## Phase 3: stick_figure_controller.gd 摆姿与节奏（P0，最大工作量）
- [ ] Task 7 (`shandong-wolf/gdscripts/stick_figure_controller.gd`): `_build_move_spec()` 重写——frames = FRAME_ANIM_MOVE_CYCLE(24)，contact(0)/pass(6)/contact(12)/pass(18) 关键姿态（髋摆 ±MOVE_SWING_LEG_DEG、摆动腿屈膝 MOVE_KNEE_BEND_DEG、摆臂反向同频 ±MOVE_SWING_ARM_DEG、躯干起伏沿用 -4），新增 2 条膝 rotation track（DESIGN §2.5）
- [ ] Task 8 (`shandong-wolf/gdscripts/stick_figure_controller.gd`): 11 clip 按 REST_POSE 衔接规约重摆——REST_POSE 常量表（DESIGN §2.3）；动作型 clip（idle/move/attack/heavy_attack/execute/revive）首/尾帧 = REST_POSE（≤5°）；hold 型 clip（guard/parry_success/stagger/stance_break/dead）首帧 = REST_POSE + 尾部归位段（FRAME_ANIM_*_EXIT 帧）收敛
- [ ] Task 9 (`shandong-wolf/gdscripts/stick_figure_controller.gd`): 全部 clip 的 HeadPivot track 路径同步为 `TorsoPivot/NeckPivot/HeadPivot`（结构变化）；新增公开方法 `set_move_speed(v)`（仅 anim_move 生效，speed_scale = clamp(|v|/300, 0.3, 1.2)，DESIGN §2.4）；play_clip/consume_state/同态重入机制零改动

## Phase 4: main_battle.gd 装配接线（P0）
- [ ] Task 10 (`shandong-wolf/gdscripts/main_battle.gd`): `_build_player()`/`_build_enemy()` 保存 stick 引用为成员；新增 `_sync_visual_facing()`（_process 轮询，缓存比对，facing 变化时设 `StickFigure.scale.x = float(facing)`；玩家读 player_entity.facing、敌人读 enemy_entity.facing；装配完成即设一次初始翻转——DESIGN §3.4）
- [ ] Task 11 (`shandong-wolf/gdscripts/main_battle.gd`): 新增 `_sync_move_speed()`——玩家/敌人 move 状态时调 `set_move_speed(velocity.x)`；**红线：翻转目标必须为 StickFigure 子节点，绝不 scale 物理根/controller 根**

## Phase 5: 单测增改（P0）
- [ ] Task 12 (`shandong-wolf/tests/test_stick_figure_animation.gd`): F1/F2 适配——PIVOT_PARTS 增 neck/leg_k_l/leg_k_r；腿长断言改 BODY_LEG_UPPER_LENGTH + 小腿 BODY_LEG_LOWER_LENGTH；新增颈长/膝节点断言（DESIGN §8 R1/R2）
- [ ] Task 13 (`shandong-wolf/tests/test_stick_figure_animation.gd`): 新增 AC1 用例（T1 颈节点存在/T2 头身重叠 ≤4px/T3 头径比例 GDD ±10%/T4 轮廓开关）；AC2 用例（T1 步态周期 ∈[24,32] 帧/T2 膝 track 存在/T3 contact/pass 姿态断言/T4 速度同步档位/T5 摆臂反向）；AC3 用例（T1 枚举 combat_state_table TRANSITIONS 合法对断言姿态差 ≤15°/T3 膝上限 90°/T5 关键链专项）——DESIGN §8 全部描述
- [ ] Task 14 (`shandong-wolf/tests/test_main_assembly.gd`): 新增 MA 系列 facing 翻转断言——设 entity.facing → 驱动 _process → 断言 StickFigure.scale.x == facing，且 PlayerController 根 scale 不变（物理层零影响红线，DESIGN §8 AC2-T6/T7）
- [ ] Task 15: 全量回归——`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 全绿（19 套件 + 新增用例，E1/C1/C2/G1 等既有断言保持）

## Phase 6: E2E shot plan + 裁决 + GDD 文档（P1）
- [ ] Task 16 (`shandong-wolf/e2e_shots.json`): stick_figure 组 02_move 拆为 02a_move_contact / 02b_move_pass（at_frame 定格 contact/pass 帧）；新增 03_head_readability（idle 定格，白底对比可选）；其余 shot 不变（DESIGN §3.5）
- [ ] Task 17: 运行 E2E stick_figure 组（--with-visual），产出步态/头部截图，提交用户裁决（实验 1 头轮廓去留 / 实验 2 帧数 24/28/32 / 实验 3 速度同步策略）
- [ ] Task 18 (`docs/GAME_DESIGN/shandong-wolf/07-STICK-FIGURE-ANIMATION.md`): 更新骨架节点树（颈/膝）、move 步态摆姿描述、facing 章节
- [ ] Task 19 (`docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md`): 新增 # DRAFT 常量行（DESIGN §3.1 表）

## 依赖顺序
Phase 1 → Phase 2 → Phase 3（骨架结构是摆姿前提）→ Phase 4 → Phase 5 → Phase 6；Phase 3 与 Phase 2 工作量合并计算（膝结构 + clip 重摆叠加）。

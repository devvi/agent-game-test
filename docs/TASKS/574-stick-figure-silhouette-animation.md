# Tasks: [Feature] 火柴人剪影骨架与关键帧动画

> **Parent Issue:** #574
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **来源:** `docs/DESIGN/574-stick-figure-silhouette-animation.md` §7（实现阶段拆分）
> **深度:** deep（分解 JSON id=3）—— 10 文件 / 5 子系统 + E2E 用户裁决，TASKS 必填
> **红线:** 只动 `shandong-wolf/`；零美术资产/零 .tres 动画资源；不修改 Main.tscn；帧节奏不硬编码（全部 constants FRAME_ANIM_* 派生）；冲突值 10vs14 双存不偷定

## Phase 0: Spike 验证（PRD §7 三个实验，预期结论已内化于 DESIGN §1）
- [ ] 实验 1（`gdscripts/stick_figure.gd` 原型）: Line2D 摆姿关键帧可控性 + 动态生成 Animation 资源可行性（时间戳从 constants 派生；零 .tres 优先，失败回退「预置 clip + 时间戳校验断言」并在 PR 说明）
- [ ] 实验 2（`gdscripts/sword_arc.gd` 原型）: 刀光 120° 张角 + 4 帧衰减参数化绘制，验证 additive 在深色底上醒目不刺眼
- [ ] 实验 3（过渡策略）: 直接 play + 首帧姿态约定能否满足 ≤2 帧；跳变大的转移（stagger→idle）是否需要 2 帧插值兜底

## Phase 1: constants FRAME_ANIM_* 分区（DESIGN §2.1）
- [ ] 1.1（`gdscripts/constants.gd`）: 文件末尾追加「动画帧节奏与骨骼几何」# DRAFT 分区（FRAME_ANIM_ATTACK_WINDUP=8 / BURST=4 / RECOVERY=10 / TRANSITION_MAX=2 / MOVE_STEP=4 / EXECUTE_TOTAL=5 / SWORD_ARC_FADE=4），每常量三行注释（候补值/影响/情感断言）
- [ ] 1.2（同上）: 追加骨骼几何与配色常量（BODY_COLOR #2b2b2b / SWORD_COLOR #c0c8d0 / HEAD_RADIUS / TORSO/ARM/LEG_LENGTH / LIMB_WIDTH / SWORD_LENGTH/WIDTH）
- [ ] 1.3（同上）: 追加刀光参数常量（SWORD_ARC_SWEEP_DEG=120 / RADIUS=70 / RINGS=4 / ALPHA_START=0.6）
- [ ] 1.4: 验证 FRAME_ANIM_ATTACK_RECOVERY=10 与既有 FRAME_ATTACK_RECOVERY=14 双存互引注释（禁止二选一）

## Phase 2: 程序化骨架（DESIGN §2.2）
- [ ] 2.1（`gdscripts/stick_figure.gd`）: `_build_skeleton()` 构建 7 pivot（torso/head/arm_l/arm_r/sword/leg_l/leg_r）+ Line2D 肢体 + Polygon2D 头圆 + 刀 Line2D
- [ ] 2.2（同上）: `_validate_geometry()` 参数校验（非法 → push_warning + 默认值兜底）；`get_pivot(part)` 寻址接口；`set_sprite_slot()` 原画接入点预留

## Phase 3: 动画资源动态生成 + 动画状态对象（DESIGN §2.3/§2.4）
- [ ] 3.1（`gdscripts/stick_figure_controller.gd`）: `_build_clip()` 运行时构建 Animation（时间戳 = FRAME_ANIM_* 帧数/60，track = pivot NodePath），11 个 `anim_*` clip 注册进 AnimationPlayer 默认库
- [ ] 3.2（`gdscripts/stick_figure_anim_states.gd`）: 11 个动画状态对象（派生 StateMachineBase，enter 播 clip / update 推进 phase；Attack 态推进 windup→burst→recovery 阶段标记）
- [ ] 3.3: attack clip 三段关键帧摆姿（前摇 8 蓄力下沉 / 暴发 4 挥砍 / 收招 10 滞刀回位，帧间距不对称）；其余 10 clip 摆姿（idle 呼吸 / move 4 帧步态 / guard 横刀 / stagger 后仰 / stance_break 失衡 / execute 上撩斩落 5 帧 / revive 起身 / dead 倒地 / heavy_attack / parry_success 硬直）
- [ ] 3.4: clip 首帧姿态 = 上一状态尾帧姿态的设计约定落实（过渡 ≤2 帧主策略的前提）

## Phase 4: consume_state 契约与调度（DESIGN §2.3）
- [ ] 4.1（`gdscripts/stick_figure_controller.gd`）: `consume_state(state)` 契约——映射表（canonical 11 态 + run→move / parry→guard 别名）+ 未知降级 idle + 同态重入重置前摇首帧 + play 前 stop 旧 clip
- [ ] 4.2（同上）: 过渡策略——直接 play + 首帧姿态约定为主；跳变大的转移 2 帧插值兜底（时长 FRAME_ANIM_TRANSITION_MAX/60）

## Phase 5: 刀光弧线（DESIGN §2.5）
- [ ] 5.1（`gdscripts/sword_arc.gd`）: `_build_polygon()` 扇形弧 + 4 环透明度衰减（vertex_colors）；CanvasItemMaterial BLEND_MODE_ADD；挂 SwordPivot 下随刀旋转
- [ ] 5.2（同上）: `trigger_burst()`（暴发段首帧触发）+ `_process` 4 帧淡出隐藏；节点树无任何碰撞类型

## Phase 6: 场景装配 + 单测（DESIGN §2.6/§2.8/§3.1）
- [ ] 6.1（`scenes/player_stick_figure.tscn`）: 根 Node2D + stick_figure_controller.gd 脚本 + StickFigure + AnimationPlayer（骨架代码构建，tscn 最小化）
- [ ] 6.2（`tests/test_stick_figure_animation.gd`）: 按 DESIGN §8 Scenario A–L 实现用例（映射/别名/11 态完整性/过渡 ≤2 帧/刀光无碰撞/constants 派生/骨架构建/同态重入/未知降级/动态生成/非法参数兜底）
- [ ] 6.3（`tests/run_tests.gd`）: 追加 `_run("res://tests/test_stick_figure_animation.gd", "StickFigureAnimation")`
- [ ] 6.4: 三入口全绿（check_compile / smoke_test / run_tests）+ 主场景冒烟（Main.tscn 零改动回归）

## Phase 7: E2E 截图与用户裁决（DESIGN §2.7/§3.1）
- [ ] 7.1（`scenes/e2e_stick_figure_capture.tscn` + `gdscripts/e2e_stick_figure_capture.gd`）: CaptureRig（深冷底色 ColorRect + Player 实例 + `current_state` 属性 + digit 键 → consume_state 映射）
- [ ] 7.2（`e2e_shots.json`）: 顶层 `main_scene` 指向 capture 场景 + `state_node/state_property/states` 枚举 + `stick_figure` shot group（11 态 shot，attack 3 段独立 shot，settle_frames 覆盖各动画时长）
- [ ] 7.3: `run-e2e-review.sh --with-visual` 跑通，11 态截图落盘 `docs/e2e-evidence/574-*`
- [ ] 7.4: 截图提交用户裁决（AC4）——「小小系列干净力量感 + 雪夜水墨和谐」；不通过 → 调摆姿/帧节奏候补值重提交（taste-draft 领域，机械接口不受影响）
- [ ] 7.5: implement PR 附开源调研说明（引用 PRD §6.2，不重复调研）

## 收尾
- [ ] PR diff 核查: 无 .png/.jpg/.tres/.res 新增（AC5）；无 mini-pong/、Main.tscn、project.godot 改动；constants.gd 无「# 定稿」字样（防偷定）
- [ ] 更新 DESIGN §6 集成点状态表（⬜ → ✅）

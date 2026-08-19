# Tasks: [Feature] 拼刀 / 弹反 / 架势崩解判定系统

> **Parent Issue:** #577
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **来源:** `docs/DESIGN/577-parry-clash-stance-break.md`（§7 实现阶段展开）
> **深度:** deep —— 2 新脚本 + 1 新测试 + 2 修改文件，跨判定层/常量层/测试三层，且为 #579/#580/#581/#585 下游事件契约源 → TASKS 必填

## Phase 1: 常量与窗口描述器（地基）
- [ ] T1 (`shandong-wolf/gdscripts/constants.gd`): 追加「判定」# DRAFT 分区 6 常量 —— PARRY_STANCE_DAMAGE=25（候选 [20,25,30]，AC1 ≥20）/ CLASH_STANCE_COST=10（候选 [8,10,12]）/ CLASH_PRIORITY=0（候选 [0,1]，弹反优先）/ HITBOX_ACTIVE_FRAMES=4（候选 [4,6,8]，与 #574 FRAME_ANIM_ATTACK_BURST 对齐）/ HITBOX_RANGE=80（候选 [60,80,100]）/ PARRY_DIRECTION_TOLERANCE=1（候选 [1,2]），注释含只狼基准+候选集+影响+情感断言（DESIGN §2.1），定稿归 #584
- [ ] T2 (`shandong-wolf/gdscripts/combat_attack_window.gd`): 新建 class_name AttackWindow extends RefCounted —— attacker/start_frame/active_frames/hp_damage/stance_damage/direction + `hit_frame()`（= start_frame + FRAME_ATTACK_WINDUP）/ `is_active(frame)`（闭区间 [hit_frame, hit_frame+active_frames]）/ `is_expired(frame)`（DESIGN §2.2，#581 敌AI 与玩家攻击共用的窗口契约）

## Phase 2: CombatJudge 核心（依赖 T1+T2）
- [ ] T3 (`shandong-wolf/gdscripts/combat_judge.gd`): 新建 class_name CombatJudge extends Node —— 五结果事件信号（parry_success/block_held/hit_landed/clash/stance_broken，与 issue body 逐字对齐）+ 状态（player/enemy/_ic/_frame/_windows/_last_guard_press_ms/_forwarded_stance_break/_resolved）+ bind_entities/bind_input/register_attack_window（同 attacker 覆盖旧窗口）
- [ ] T4 (`shandong-wolf/gdscripts/combat_judge.gd`): resolve_attack(attacker, defender) 幂等裁决（防重入键 "attacker:defender:frame"）——裁决顺序全走常量：①弹反（guard_pressed ts ∈ [hit_ms-PARRY_WINDOW_SECONDS*1000, hit_ms] 闭区间 + facing 校验 → 0 伤害 + enemy.take_stance_damage(PARRY_STANCE_DAMAGE) + player.request_transition("parry_success") + emit parry_success）②拼刀（双方窗口同帧 active → 双方 take_stance_damage(CLASH_STANCE_COST) + emit clash）③格挡（defender.state_name=="guard" → take_stance_damage(POSTURE_BLOCK_COST) + emit block_held）④受击（take_damage + take_stance_damage(POSTURE_HIT_COST) + emit hit_landed）
- [ ] T5 (`shandong-wolf/gdscripts/combat_judge.gd`): _process 帧推进（_frame += 1 + 窗口命中触发 resolve + 过期清理）+ `tick_frame()` headless 手动推进 + _on_entity_state_changed（attack/heavy_attack → 自动登记玩家窗口）/ _on_guard_pressed（记 ts，同帧取最后）/ _on_stance_broken（幂等转发）

## Phase 3: 测试与挂载（依赖 T2-T5）
- [ ] T6 (`shandong-wolf/tests/test_combat_judge.gd`): 新建测试套件 —— DESIGN §8 全部 25 用例（Scenario A 弹反窗口边界 5 例 / B 拼刀+冲突矩阵 4 例 / C 格挡+受击 5 例 / D 崩解+事件契约 5 例 / E 边界失败路径 6 例），写法沿用 test_combat_entity.gd（免树直接 new + tick_frame 手动推进 + 信号日志 + _assert）
- [ ] T7 (`shandong-wolf/tests/run_tests.gd`): 追加 `_run("res://tests/test_combat_judge.gd", "CombatJudge")` 挂载（置于 CombatEntity 之后）
- [ ] T8 (验证): `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 8 套件全绿；确认零字面量判定数值（AC4 code review 项）

## PR 要求
- [ ] T9: PR 附开源调研结论（PRD §6.2：hitbox 生态全物理模式与时间窗冲突 → 自研逻辑帧窗口判定层）；红线自检（不引 Area2D 碰撞/不改 #575 接口/不裁决 # DRAFT 数值/不改结果事件名/不写死裁决优先级/不碰 mini-pong/不碰 Main.tscn/不做渲染演出音效）

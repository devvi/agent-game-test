# Tasks: [Feature] 战斗实体基类与状态机（CombatEntity + 11 态战斗状态机）

> **Parent Issue:** #575
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **来源:** `docs/DESIGN/575-combat-entity-state-machine.md`（§7 实现阶段展开）
> **深度:** deep —— 3 新脚本 + 1 新测试 + 2 修改文件，跨 4 子系统 → TASKS 必填

## Phase 1: 常量与转移表（地基）
- [ ] T1 (`shandong-wolf/gdscripts/constants.gd`): 追加「战斗时序」# DRAFT 分区 5 常量 —— STAGGER_FRAMES=12 / PARRY_SUCCESS_FRAMES=10 / STANCE_BREAK_RECOVERY_SEC=3.0 / REVIVE_SECONDS=1.0 / INVINCIBLE_SECONDS=1.0，注释含候补值+影响+情感断言（DESIGN §2.1），定稿归 #584
- [ ] T2 (`shandong-wolf/gdscripts/combat_state_table.gd`): 新建 class_name CombatStateTable —— CANONICAL_STATES 11 名 + TRANSITIONS 转移表 + `static is_legal(from, to)`（DESIGN §2.2，红线：stance_break 禁 attack/heavy_attack/guard；dead 仅 revive）

## Phase 2: 状态对象（依赖 T1）
- [ ] T3 (`shandong-wolf/gdscripts/combat_states.gd`): 新建 CombatStateBase（RefCounted：name/entity/_elapsed + enter/exit/update/restart）+ `make_state` 工厂（写法同构 stick_figure_anim_states.gd）
- [ ] T4 (`shandong-wolf/gdscripts/combat_states.gd`): 11 个状态对象 —— 定时状态帧/秒常量自动退出（Attack 22 帧含 phase 0/1/2 + restart 连段钩子；HeavyAttack 22 帧；Stagger 12 帧；ParrySuccess 10 帧；StanceBreak 3.0s；Execute 5 帧；Revive 1.0s）；退出统一在 update() 内 request_transition("idle")，enter() 内禁止转移（防重入）

## Phase 3: CombatEntity 核心（依赖 T2+T3）
- [ ] T5 (`shandong-wolf/gdscripts/combat_entity.gd`): 新建 class_name CombatEntity extends Node2D —— @export 变体参数（is_player/life_total/life_1_max/life_2_abs/stance_max）+ 数据（hp_1/hp_2/stance/facing/is_stance_broken/state_name/_active_life/_is_final_dead/_invincible_until_sec）+ constants 初始化 + 6 信号（hp_changed/stance_changed/stance_broken/state_changed/died/revived）
- [ ] T6 (`shandong-wolf/gdscripts/combat_entity.gd`): request_transition(to) 唯一转移入口 —— 守卫序（终态/停摆/查表/同态 restart）+ fsm.transition_to + state_name 更新 + state_changed 广播（DESIGN §2.4 表）
- [ ] T7 (`shandong-wolf/gdscripts/combat_entity.gd`): 接口方法 —— take_damage（兜底/无敌期/clamp/stagger 转移触发规则）、take_stance_damage（clamp/归零→break_stance）、break_stance（幂等+stance_broken）、die（两段血 final 语义）、revive（终态守卫/hp_2 接管/无敌开启/revived）、_recalc_stance_max 钩子（MVP 固定值）
- [ ] T8 (`shandong-wolf/gdscripts/combat_entity.gd`): _process —— fsm.update(delta) 转发 + 无敌期到期失效

## Phase 4: 输入桥（依赖 T5-T7）
- [ ] T9 (`shandong-wolf/gdscripts/combat_entity.gd`): _StateInputBridge —— is_player 时订阅 InputController（attack_pressed→attack / heavy_attack_pressed→heavy_attack / guard_pressed→guard / revive_pressed→revive()）；guard 释放检测（按住轮询松开→idle）；移动轴轮询（axis≠0→move，=0→idle，facing 同步）；bind_input_controller(ic) 手动接线 + autoload 自动获取失败静默

## Phase 5: 测试与挂载（依赖 T2-T9）
- [ ] T10 (`shandong-wolf/tests/test_combat_entity.gd`): 新建测试套件 —— DESIGN §8 全部 30 用例（Scenario A 变体 / B 转移合法性含 121 对遍历 / C 受击 / D 架势 / E 死亡复活 / F 边界+契约对齐）
- [ ] T11 (`shandong-wolf/tests/run_tests.gd`): 追加 `_run("res://tests/test_combat_entity.gd", "CombatEntity")` 挂载
- [ ] T12 (可选 `shandong-wolf/tests/smoke_test.gd`): 追加实体实例化探针（玩家/敌人两变体 new + 属性断言，不回归 I1/I2）
- [ ] T13 (验证): `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 7 套件全绿；跑 #574 test_stick_figure_animation 确认 11 态状态名与 ANIM_CLIP_NAMES 键集逐名匹配（契约对齐红线）

## PR 要求
- [ ] T14: PR 引用本调研结论（FSM 复用 #572 StateMachineBase；战斗实体无成熟开源 → 自研，PRD §6.2）；红线自检（不造状态名/不引 addon/不碰 mini-pong/不碰 Main.tscn/不裁决 # DRAFT 数值/不做判定演出逻辑）

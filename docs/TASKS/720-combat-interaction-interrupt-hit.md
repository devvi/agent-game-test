# Tasks: [Boss 级 AI] 战斗交互升级——霸体/自动面向/停距击退/防御/前摇弹反博弈

> **Parent Issue:** #720
> **深度:** standard（5+ 子系统子任务 → 产出 TASKS，参照 DESIGN §1.1 判定）
> **设计文档:** `docs/DESIGN/720-combat-interaction-interrupt-hit.md`
> **实现顺序:** Phase 1（常量）→ Phase 2（霸体）→ Phase 3（自动面向）→ Phase 4（弹反差异化）→ Phase 5（防御行为）→ Phase 6（测试更新）→ Phase 7（验证）；Phase 8 血线阶段可选

## Phase 1: 常量层（P0）
- [ ] Task 1 (`shandong-wolf/gdscripts/constants.gd`): 修改 `ENEMY_ATTACK_RANGE` 80→65、`ENEMY_KNOCKBACK_PX` 40→22、`POSTURE_HIT_COST` 35→18、`ENEMY_CHARGE_WINDUP` 20→24、`ENEMY_ATTACK_COOLDOWN_SEC` 1.5→1.2（全部保留 # DRAFT + 候选集注释，见 DESIGN §2.3）
- [ ] Task 2 (`shandong-wolf/gdscripts/constants.gd`): 新增常量 `ENEMY_THRUST_WINDUP=16`、`ENEMY_BLOCK_CHANCE=0.4`、`ENEMY_GUARD_HOLD_SECONDS=0.5`、`PARRY_WINDOW_CHARGE_SECONDS=0.3`、`PARRY_WINDOW_THRUST_SECONDS=0.25`、`PARRY_STANCE_DAMAGE_CHARGE=55`、`PARRY_STANCE_DAMAGE_THRUST=45`、`ENEMY_ENRAGE_HP_RATIO=0.5`（P2 可选）
- [ ] Task 3 (`shandong-wolf/gdscripts/constants.gd`): `PARRY_STANCE_DAMAGE` 25→35（普通弹反回报，候选 [30,35,40]）

## Phase 2: 实体层霸体（P0，核心）
- [ ] Task 4 (`shandong-wolf/gdscripts/combat_entity.gd`): 新增 `_state_elapsed_frames` / `_windup_frames` 状态属性；request_transition 成功后重置计时、attack/heavy_attack 时按招式设置 windup（override 链：current_windup_frames → ENEMY_CHARGE_WINDUP/ENEMY_THRUST_WINDUP → ENEMY_ATTACK_WINDUP）
- [ ] Task 5 (`shandong-wolf/gdscripts/combat_entity.gd`): `_process` 非 idle 态每帧 `_state_elapsed_frames += 1`（仅敌人变体需要精确，玩家侧开销可忽略）
- [ ] Task 6 (`shandong-wolf/gdscripts/combat_entity.gd`): 新增 `_is_armored()`；`take_damage` 扣血广播后、stagger 分支前插入霸体 return（windup 期不转 stagger）；确认弹反路径（judge parry_success）不受影响

## Phase 3: 玩家自动面向（P0）
- [ ] Task 7 (`shandong-wolf/gdscripts/combat_entity.gd`): 新增 `_auto_face_target` 属性 + `_face_nearest_target()`（target 非 null 且 |dx|>0 → facing=sign(dx)）；`_on_bridge_attack_pressed`/`_on_bridge_heavy_attack_pressed` 入口调用
- [ ] Task 8 (`shandong-wolf/gdscripts/main_battle.gd`): 装配处注入 `player_entity._auto_face_target = enemy_entity`（1 行）

## Phase 4: 弹反窗口/回报差异化（P0）
- [ ] Task 9 (`shandong-wolf/gdscripts/combat_attack_window.gd`): 新增 `parry_window_seconds` / `parry_stance_damage` 字段（默认 -1 = fallback 常量）
- [ ] Task 10 (`shandong-wolf/gdscripts/combat_judge.gd`): `_on_entity_state_changed` 敌人分支按 windup 阈值链注入 parry 字段（charge≥24 → 0.3s/55；thrust≥16 → 0.25s/45；其余 fallback）
- [ ] Task 11 (`shandong-wolf/gdscripts/combat_judge.gd`): `_resolve_parry` 弹反窗口与回报改读窗口字段（fallback 既有常量）；确认 `_test_1/_test_2` 普通窗零破坏

## Phase 5: 敌人防御行为 + 差异化前摇（P0）
- [ ] Task 12 (`shandong-wolf/gdscripts/enemy_ai_states.gd`): 新增 `GuardState` 行为态（enter→request_transition("guard")；update→期满回 idle + Chase）；`make_state` 注册 "guard"
- [ ] Task 13 (`shandong-wolf/gdscripts/enemy_ai.gd`): `_on_player_state_changed` 扩展防御触发（玩家 attack/heavy_attack + 敌人 idle/move + |dx|≤HITBOX_RANGE + 非 retreat/guard → 掷骰 ENEMY_BLOCK_CHANCE → GuardState）；`_dead` 守卫
- [ ] Task 14 (`shandong-wolf/gdscripts/enemy_ai_states.gd`): `AttackState.enter` thrust 分支注入 `current_windup_frames = ENEMY_THRUST_WINDUP`（中前摇，复用 #682 override 链）
- [ ] Task 15（视觉信号，taste 骨架）: 确认三级前摇的视觉可读（charge 举刀蓄力 / thrust 前倾 / combo 短促）——复用既有 stick_figure 动画 + sword_arc（#574/#683/#579），零新组件；具体姿态数值归 #584 用户裁决

## Phase 6: 测试更新 + 新增（P0）
- [ ] Task 16 (`shandong-wolf/tests/test_combat_judge.gd`): 更新 `_test_24` 常量断言（PARRY_STANCE_DAMAGE 25→35、POSTURE_HIT_COST 35→18）；新增弹反差异化用例（T16-T18）
- [ ] Task 17 (`shandong-wolf/tests/test_enemy_ai.gd`): 更新 `_test_16/_test_17`（弹反回报 35、4 次崩解→3 次）、`_test_33`（combo_interrupt 反转：windup 期命中不中断）、`_test_40`（击退 22 核对）；新增防御用例（T11-T14）+ 三级前摇用例（T15）
- [ ] Task 18 (`shandong-wolf/tests/test_combat_entity.gd`): 新增霸体用例（T1-T4：windup 不打断/收招可打断/弹反打断）+ 自动面向用例（T5-T7）；核对 `_test_c1` 等既有用例（idle 态受击仍 stagger）

## Phase 7: 验证（P1）
- [ ] Task 19: headless 全量单测 `godot --headless --path shandong-wolf -s tests/run_tests.gd` 全绿（~1314 基线 + 新增）
- [ ] Task 20: CI 三层门禁（L0 编译 --check-only / L1 smoke / L2 playthrough）通过
- [ ] Task 21: 实机手测 AC1-AC6（敌人稳定出招 / 5-7 击崩解 / 追击防御 / 博弈循环 / 有来有回 / 闭环可测）+ E2E 截图证据（三级前摇视觉信号，交用户 taste 裁决）

## Phase 8: 血线阶段（P2 可选，implement 自主决定）
- [ ] Task 22 (`shandong-wolf/gdscripts/enemy_ai.gd`): `_enraged` 标志（hp_1/life_1_max ≤ ENEMY_ENRAGE_HP_RATIO）→ 冷却 ×0.6 + charge 概率 ×1.5；`AttackState` 读标志调整

# Tasks: [Feature] 基础日本兵 AI（巡逻 / 追击 / 攻击 / 被弹反）

> **Parent Issue:** #581
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **深度:** standard（无 depth label；PRD 标注 depth: standard）—— 9 文件 / 4 子系统 × 6+ 独立子任务 → 产出 TASKS（触发 skill standard 阈值，参照 #584/#577 先例）
> **依据:** `docs/DESIGN/581-enemy-ai.md`（本 TASKS 的每项任务都有对应设计章节；先读 DESIGN 再动手）
> **红线速查:** 全部 additive，不碰 11 态状态名/五结果事件/既有接口签名；数值只读 constants # DRAFT；不碰 mini-pong/、Main.tscn、debug_canvas.gd；不写死字面量

## Phase 1: 常量层（P0）

- [ ] Task 1 (`shandong-wolf/gdscripts/constants.gd`): 追加「AI 分区」17 个 # DRAFT 常量（ENEMY_SENSE_RANGE_PX / ENEMY_SENSE_ANGLE_DEG / ENEMY_SENSE_HEIGHT_TOLERANCE / ENEMY_PATROL_SPEED / ENEMY_CHASE_SPEED / ENEMY_TURN_DELAY_SEC / ENEMY_ATTACK_RANGE / ENEMY_ATTACK_COOLDOWN_SEC / ENEMY_HP_DAMAGE / ENEMY_HP_MAX / ENEMY_THRUST_CHANCE / ENEMY_RETREAT_CHANCE / ENEMY_RETREAT_SECONDS / ENEMY_RETREAT_TRIGGER_RANGE / ENEMY_PARRY_STUN_SECONDS / ENEMY_LOSE_SIGHT_RANGE / ENEMY_PATROL_PAUSE_SEC），全部带「只狼基准/issue body → 候选 + 影响 + 情感断言」注释（DESIGN §3.2）
- [ ] Task 2 (`shandong-wolf/gdscripts/constants.gd`): ENEMY_ATTACK_WINDUP 15→12（AC1 对齐，保留候选注释 [12,15,18]；偏差记录交 #584；DebugCanvas 面板 default 不改）

## Phase 2: 判定层 additive 补丁（P0，回归基线）

- [ ] Task 3 (`shandong-wolf/gdscripts/combat_attack_window.gd`): 追加 `windup_frames: int = -1`；hit_frame() 优先用 windup_frames（≥0），-1 回退 FRAME_ATTACK_WINDUP（DESIGN §3.3）
- [ ] Task 4 (`shandong-wolf/gdscripts/combat_entity.gd`): 追加 `@export attack_hp_damage: float = -1.0` / `@export attack_stance_damage: float = -1.0`（-1 = 玩家常量兜底）（DESIGN §3.3）
- [ ] Task 5 (`shandong-wolf/gdscripts/combat_judge.gd`): `_on_entity_state_changed` 登记时 hp_damage/stance_damage 读实体参数（≥0 用实体值，否则玩家常量兜底）；敌人窗口 windup_frames = ENEMY_ATTACK_WINDUP（DESIGN §3.3）
- [ ] Task 6 回归验证: `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` → 既有 test_combat_judge.gd 25 用例全绿（additive 无回归基线）

## Phase 3: AI 行为层（P0）

- [ ] Task 7 (`shandong-wolf/gdscripts/enemy_ai.gd`, 新增): EnemyAI（CharacterBody2D）——@export（waypoints/player/judge/rng_seed）+ bind_entity()（注入攻击伤害参数 + 订阅信号）+ can_sense_player()（120° 视线 6m 几何判据）+ decide(delta) 纯决策（决策门控：entity null/_dead/非 idle-move 态/弹反抑制窗）+ move_intent() + _physics_process（仿 #573 加速度模型）+ set_rng_seed()（DESIGN §2.1）
- [ ] Task 8 (`shandong-wolf/gdscripts/enemy_ai_states.gd`, 新增): make_state 工厂 + PatrolState（waypoint ping-pong + 到达停顿 + 空/单 waypoint 降级）+ ChaseState（转向延迟 + 逼近停距 + 丢失回巡逻）+ AttackState（三连砍 restart 连段 / 突刺 heavy_attack + 冷却）+ RetreatState（5% 回避 + 回扑/回追击）（DESIGN §2.2）
- [ ] Task 9 弹反抑制窗接线: EnemyAI 订阅 judge.parry_success（judge 绑定）或 player.state_changed → parry_success → _parry_stun_until_sec = now + ENEMY_PARRY_STUN_SECONDS（AC2 0.5s 硬直补足）

## Phase 4: 测试层（P1）

- [ ] Task 10 (`shandong-wolf/tests/test_enemy_ai.gd`, 新增): DESIGN §9 Scenario A-G 共 36 用例描述落地——headless 免树（new + 手动 decide/tick）、RNG seed 注入、禁 :=、class_name 经 load()（对齐 test_combat_judge.gd 范本）
- [ ] Task 11 (`shandong-wolf/tests/run_tests.gd`): 追加 `_run("res://tests/test_enemy_ai.gd", "EnemyAI")`
- [ ] Task 12 (`shandong-wolf/tests/smoke_test.gd`, 可选): AC5 冒烟——玩家站桩 + 敌人 5s 内完成巡逻→发现→接近→攻击路径（DESIGN §9 T8）
- [ ] Task 13 全量回归: run_tests.gd 10 套件全绿 + smoke_test.gd 通过；PR 附开源调研结论引用（DESIGN 附录）

## 验收（对应 Issue #581 body）

- [ ] AC1: 巡逻→追击→攻击 流转，前摇 12 帧可弹反（T1-T9）
- [ ] AC2: 弹反硬直 0.5s + 25 架势，4 次崩解（T16-T19）
- [ ] AC3: 5% 后退回避（T20-T24）
- [ ] AC4: 参数全走 constants.gd（T25-T26）
- [ ] AC5: smoke 5s 全路径（T8）

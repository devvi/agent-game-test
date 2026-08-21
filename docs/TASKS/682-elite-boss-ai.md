# Tasks: [Feature] 敌人 AI：只狼式精英怪 Boss（攻击/弹反/架势交互）

> **Parent Issue:** #682
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Design:** `docs/DESIGN/682-elite-boss-ai.md`（方案 A：精英 = EnemyAI 参数档位 + additive 增量，11 文件）
> **深度:** standard —— 触发 TASKS 阈值（11 文件 / 5 子系统 × 7+ 独立子任务）

## Phase 1: 常量（先锁契约）
- [ ] Task 1 (`shandong-wolf/gdscripts/constants.gd`): 新增「精英 AI」分区 8 项 # DRAFT 常量（ENEMY_CHARGE_WINDUP=20 / ENEMY_CHARGE_HP_DAMAGE=25 / ENEMY_CHARGE_CHANCE=0.2 / ENEMY_KNOCKBACK_PX=40 / ENEMY_KNOCKBACK_DECAY=3 / ENEMY_STANCE_RECOVER_DELAY_SEC=2.5 / ENEMY_STANCE_RECOVER_PER_SEC=20，全部带候选集 + 情感断言注释）；ENEMY_HP_MAX 默认 40→80（候选 [60,80,100]）；HUD 分区新增 HUD_ENEMY_HP_GAP=4

## Phase 2: 数据层 + 判定层（DESIGN §2.2/§2.4/§3.2-5/§3.2-6）
- [ ] Task 2 (`shandong-wolf/gdscripts/combat_entity.gd`): 新增瞬时 override 字段 `current_windup_frames: int = -1` / `current_hp_damage: float = -1.0`
- [ ] Task 3 (`shandong-wolf/gdscripts/combat_entity.gd`): 敌人架势脱战恢复——`_process` 轮询（仅 is_player=false 且未崩解且超延迟 → stance += PER_SEC*delta 至上限 + stance_changed）；`take_stance_damage` 追加延迟重置（`_stance_recover_delay_until_sec`）
- [ ] Task 4 (`shandong-wolf/gdscripts/combat_judge.gd`): 窗口登记 fallback 链——敌人 windup 读 `current_windup_frames` override（≥0 用 override，否则 ENEMY_ATTACK_WINDUP）；hp_damage 取值链追加 `current_hp_damage` override（override → attack_hp_damage → 玩家常量兜底）

## Phase 3: 行为层（DESIGN §2.1/§2.2/§2.3/§3.2-3/§3.2-4）
- [ ] Task 5 (`shandong-wolf/gdscripts/enemy_ai.gd`): 新增 `@export elite_mode: bool = false`
- [ ] Task 6 (`shandong-wolf/gdscripts/enemy_ai_states.gd`): AttackState 出招二选一 → 三选一（elite_mode 门控：charge → thrust → combo）；charge 分支：设置 override → request_transition("heavy_attack") → 清空 override + 冷却
- [ ] Task 7 (`shandong-wolf/gdscripts/enemy_ai.gd`): 受击击退——`_ensure_judge_subscription` 追加 hit_landed 订阅；`_on_judge_hit_landed`（defender==entity → _knockback_dir/_knockback_vel）；`_apply_movement` 击退分支（衰减 + STAGE_WIDTH_PX clamp）

## Phase 4: 装配 + UI（DESIGN §3.2-2/§3.2-7）
- [ ] Task 8 (`shandong-wolf/gdscripts/main_battle.gd`): `_build_enemy` 装配注入 `life_1_max: C.ENEMY_HP_MAX` + `enemy.elite_mode = true`（HP 慢线接通）
- [ ] Task 9 (`shandong-wolf/gdscripts/hud.gd`): `_create_nodes` 新增 EnemyHealthBar（顶部中央 240×10 暗红，offset_top=12）；EnemyStanceBar 下移（offset_top=26）
- [ ] Task 10 (`shandong-wolf/gdscripts/hud.gd`): `_HudBar` 新增 `set_fill_color`（默认行为零变化）；`set_target_enemy` 增订 hp_changed 订阅 + 初始化 + null/died 显隐联动；`_disconnect_enemy` 追加

## Phase 5: 测试（DESIGN §8 测试用例描述）
- [ ] Task 11 (`shandong-wolf/tests/test_enemy_ai.gd`): 新增 E 组精英用例（elite 门控 / 蓄力概率分布 / 窗口前摇 20 伤害 25 / override 清空 / 弹反闭区间三态 / 击退触发与衰减 / 越界 clamp）
- [ ] Task 12 (`shandong-wolf/tests/test_combat_entity.gd`): 新增脱战恢复用例（延迟内不恢复 / 超时恢复至上限 / 崩解不恢复 / 玩家不触发 / 恢复-再受伤重置 / 双写竞态）
- [ ] Task 13 (`shandong-wolf/tests/test_hud.gd`): 新增 EnemyHealthBar 用例（注入可见 / 布局断言 T5 同步 12→26 / hp_changed 驱动比例 / died 隐藏 / 玩家条回归）
- [ ] Task 14 (`shandong-wolf/tests/test_main_assembly.gd`): 可选装配断言（enemy_entity.life_1_max == ENEMY_HP_MAX、enemy.elite_mode == true）

## Phase 6: 实验复验（DESIGN §7 Phase 9）
- [ ] Task 15: 实验 1——蓄力 windup 20 vs 弹反闭区间时序（弹反难度数据记录交 #584）
- [ ] Task 16: 实验 2——脱战恢复节奏 vs 崩解频率（弹反间隔 1.2s < 延迟 2.5s 快线成立；数据记录交 #584）

## 红线提醒（implement agent 禁止）
- ❌ 不改 11 态 CANONICAL_STATES / consume_state 契约（combat_state_table.gd 零改动）
- ❌ 不改 #577 五结果事件名与裁决顺序（judge 仅 2 处 fallback 链）；不引入 Area2D/CollisionShape2D 物理碰撞
- ❌ 不裁决 # DRAFT 数值（constants 只读 + 候选集移交 #584）
- ❌ 不实现 #589 军曹/#590 汉奸内容（危攻击/霸体/体型/掉落/二阶段/台词/演出）
- ❌ 不修改既有接口签名（全部 additive；既有 19 测试文件默认路径全绿）
- ❌ 不写死 AI 数值字面量（蓄力/击退/恢复/HP 全走 constants）
- ❌ 不修改 mini-pong/ 任何文件、scenes/Main.tscn、玩家实体行为（脱战恢复仅 is_player=false）
- ❌ 不写除 DESIGN/TASKS 外的文档（GDD 更新归 post-merge agent）

# Tasks: [Combat] 处决系统（架势崩解 → 处决特写）

> **Parent Issue:** #580
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **深度:** deep（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=9 标注 depth: deep；GitHub 无 depth 标签）—— 7 文件（3 新建 + 4 修改）/ 6 独立子任务跨多子系统（编排器、淡出、实体接口×3、常量分区、测试套件、E2E 截图）→ **TASKS doc 必需**
> **参考:** `docs/DESIGN/580-execution-system.md`（§2 新组件 / §3 既有修改 / §8 测试场景为唯一契约）+ `docs/PRD/580-execution-system.md`（§7 实验 / §8 交接清单）
> **红线:** 只动 shandong-wolf/ 下 7 文件；绝不触碰 combat_states.gd / combat_state_table.gd / combat_judge.gd / reaction_controller.gd / time_scale_stack.gd / sword_arc.gd / hud.gd / enemy_ai.gd / input_controller.gd / scenes/ / mini-pong/ / manifest / CI / GDD；**take_damage execute no-op 是 #575 无敌红线——处决杀敌只走 execute_kill()**；禁止直写 Engine.time_scale；三处慢动作候选必须并列 # DRAFT 登记，禁止二选一偷定；禁止把任何 # DRAFT 值「顺手定稿」（taste-draft，定稿归 #584/用户）；PR body 用 `Parent #580` 不带冒号；不写可运行测试文件之外的任何实现文件以外的文件（测试代码归本 implement）

## Phase 0: Spike 验证（PRD §7 三实验，0.5 天，先于 Phase 1-6）

- [ ] Spike 1（处决触发时序 headless 全链路，PRD 实验 1 / DESIGN §8 Scenario A）：最小脚本 new ExecutionOrchestrator + 玩家/敌人 CombatEntity + mock ReactionController，注入 stance_broken → 推进窗口内 → 注入 attack_pressed → 断言全链路每步恰好一次（玩家无敌生效 / execute 转移 / died(true) 一次 / state 保持 execute / trigger_feedback 一次）；若失败 → 检查 execute_kill 与 request_transition 调用顺序（DESIGN §2.1 时序 ②③）
- [ ] Spike 2（疲惫起身数值闭环，PRD 实验 2 / DESIGN §8 Scenario D）：recover_from_break 50% 恢复 + exhausted ×1.2 增伤 + 5s 到期恢复 + 幂等防双写；若 exhausted 到期与再次崩解竞态失败 → 调整 break_stance 时 exhausted 复位时机（DESIGN §3.2.3）
- [ ] Spike 3（E2E rig 路径选择，PRD 实验 3 / DESIGN §3.5）：裁决扩展 e2e_battle_stage_capture rig 注入处决序列 vs 新建 e2e_execution_capture rig（instance battle_stage）；验证冻结效果帧模式（freeze_time_stack）能让刀光/血色/斩落姿态停留画面；产出 2 张截图雏形供 Phase 6 落地

## Phase 1: constants.gd「处决演出」分区（P0，0.5 天）

- [ ] Task 1 (`shandong-wolf/gdscripts/constants.gd`)：文件尾部追加「处决演出」# DRAFT 分区——EXECUTE_SLOWMO_SCALE [0.05,0.1,0.2] / EXECUTE_SLOWMO_MS [400,500,600]（三处候选归拢，**并列登记禁止二选一**）/ EXECUTE_INVINCIBLE_SECONDS 1.5（候选 [1.0,1.5,2.0]）/ EXECUTE_FADE_SECONDS 0.3 / EXECUTE_RANGE_PX 120（= EXECUTE_RANGE×100 派生，候选 [100,120,150]）/ EXECUTE_EXHAUSTED_SECONDS 5.0 / EXECUTE_RECOVER_RATIO 0.5 / EXECUTE_EXHAUST_MULTIPLIER 1.2（源码见 DESIGN §3.3，可直接采用）；**不动既有任何分区一行**
- [ ] Task 2 (同上)：消费方读值 `DebugCanvas.get_value("NAME", C.NAME)` 包装（热更新优先，release 回落 const）；**禁止**去 `# DRAFT` 标记、禁止散落硬编码（Scenario D/E 断言会查）

## Phase 2: combat_entity.gd additive 接口（P0，1 天）

- [ ] Task 3 (`shandong-wolf/gdscripts/combat_entity.gd`)：追加 `execute_kill()`——置 `_is_final_dead = true` + exhausted 复位 + hp_1 归零广播 hp_changed + `emit died(self, true)`；**不调用 take_damage、不转移 dead 态**（DESIGN §3.2.1；源码可直接采用）
- [ ] Task 4 (同上)：追加 `set_invincible(seconds)`——复用 `_invincible_until_sec` 墙钟机制（DESIGN §3.2.2）
- [ ] Task 5 (同上)：追加 `exhausted` 数据 + `recover_from_break()`（幂等：is_stance_broken 已清 → no-op；stance = stance_max × EXECUTE_RECOVER_RATIO + exhausted 置位 + 到期墙钟 + stance_changed 广播）+ `take_stance_damage` 内追加乘数分支（exhausted → ×EXECUTE_EXHAUST_MULTIPLIER）+ `break_stance()` 追加 exhausted 复位一行 + `_process` 追加疲惫到期清除（DESIGN §3.2.3）
- [ ] Task 6 (同上)：**红线自查**——不改 take_damage execute no-op 守卫一行、不改 request_transition 守卫①、不改既有任何路径（test_combat_entity 30 用例必须零改动全绿）

## Phase 3: execution_orchestrator.gd（P0，1 天）

- [ ] Task 7 (`shandong-wolf/gdscripts/execution_orchestrator.gd`)：`extends Node` class_name ExecutionOrchestrator；bind_player / bind_enemy / bind_judge / bind_input / unbind_enemy 幂等接线（DESIGN §2.1，D3 单源互斥：judge 绑定 → 断开实体直连）；stance_broken → armed 窗口计时（STANCE_BREAK_RECOVERY_SEC 同源互引）；attack_pressed → 处决检查（armed ∧ 玩家存活 ∧ |dx| ≤ EXECUTE_RANGE_PX 闭区间）→ _trigger_execution()
- [ ] Task 8 (同上)：`_trigger_execution()` 时序序列——① player.set_invincible ② enemy.request_transition("execute")（先转移后杀敌）③ enemy.execute_kill() ④ bind_feedback 已绑 → trigger_feedback("execute", {target_entity: enemy}) ⑤ fade.bind(enemy)（DESIGN §2.1 D4-D6）
- [ ] Task 9 (同上)：`_process(delta)` 窗口到期 → enemy.recover_from_break()；state_changed 观察（stance_break→idle 立即恢复 + armed 失效；→execute 防御性双清）；enemy died → unbind_enemy 防泄漏（DESIGN §2.1 + §5 边界 1/3/4）

## Phase 4: execution_fade.gd（P0，0.5 天）

- [ ] Task 10 (`shandong-wolf/gdscripts/execution_fade.gd`)：`extends Node` class_name ExecutionFade；bind(entity) 幂等重绑 + `_tick(now_ms)` 墙钟核心推进（modulate alpha 1→0，EXECUTE_FADE_SECONDS）+ `_process(_delta)` 转发 Time.get_ticks_msec() + is_instance_valid 守卫 + `fade_completed(entity)` 信号 → queue_free（DESIGN §2.2；源码可直接采用）

## Phase 5: 测试套件（P0，0.5 天）

- [ ] Task 11 (`shandong-wolf/tests/test_execution_orchestrator.gd`)：新建套件覆盖 DESIGN §8 Scenario A-G——A 触发全链路（含恰好一次）/ B 触发边界（距离外/过期/玩家死/未 armed/同帧竞态）/ C 无敌交互（判定器 + 时间栈嵌套恢复）/ D 疲惫数值闭环 / E 淡出清理（墙钟/守卫/重绑）/ F 失败路径防回归（take_damage 红线/停摆/泄漏/无反馈）/ G 由 E2E 截图覆盖；headless 手动 `_process(delta)` / `_tick(now_ms)` 推进（对齐 test_revive_orchestrator 模式）；mock ReactionController
- [ ] Task 12 (`shandong-wolf/tests/run_tests.gd`)：`_run_tests()` 追加 `_run("res://tests/test_execution_orchestrator.gd", "ExecutionOrchestrator")`（DESIGN §3.4）

## Phase 6: E2E 处决构图（P1，0.5 天，依赖 Spike 3 裁决）

- [ ] Task 13 (`shandong-wolf/e2e_shots.json`)：追加 execution 组——01_execute_strike（处决斩落瞬间）/ 02_execute_fade（淡出消散瞬间），settle_frames 覆盖演出窗口，冻结效果帧模式兜底（DESIGN §3.5）
- [ ] Task 14 (rig 文件，按 Spike 3 裁决路径)：扩展 e2e_battle_stage_capture rig 或新建 e2e_execution_capture rig——敌人 execute 态注入 + SwordArc.trigger_burst + 血色粒子 burst + freeze_time_stack；截图走 analyze_bmp.py 4 重防伪断言 + 反例断言（血色饱和度上限 / 无全屏发光）→ 提交 review agent 走用户裁决（AC5 taste 通道）

## 验收自查（全部通过才可 PR）

- [ ] `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 全绿（含既有 14 套件 + 新套件）
- [ ] AC1-AC4 单测断言全覆盖（DESIGN §9 映射表逐条勾选）
- [ ] 红线自查：git diff 只含 7 文件；combat_states/combat_state_table/combat_judge/reaction_controller/hud/enemy_ai 零 diff
- [ ] `# DRAFT` 零定稿：diff 中无去 DRAFT 标记、无慢动作二选一
- [ ] E2E execution 组 2 shot 截图产出（供 review agent 用户裁决）

# Tasks: [Feature] 两条命原地复活系统

> **Parent Issue:** #578
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **深度:** deep（无 depth label；PRD 标注 depth: deep）—— 2 新组件 / 1 常量分区 / 1 测试套件 / E2E 接线 → **产出 TASKS（deep 必写）**
> **依据:** `docs/DESIGN/578-two-life-revive.md`（本 TASKS 的每项任务都有对应设计章节；先读 DESIGN 再动手）
> **红线速查:** 零修改 combat_entity.gd / combat_state_table.gd / combat_states.gd（#575 契约只读）；不重写 hp/架势/无敌逻辑；数值只读 constants # DRAFT（新 FX 分区同样标 # DRAFT）；不碰 mini-pong/、Main.tscn；不写死字面量；不写失败场景（SW-015 职责）

## Phase 1: 常量层（P0）

- [ ] Task 1 (`shandong-wolf/gdscripts/constants.gd`): 追加「复活 FX 分区」10 个 # DRAFT 常量（INK_BURST_COUNT=40 / INK_BURST_SPEED=180 / INK_BURST_LIFETIME=0.4 / INK_COLOR=#141414 / INK_BURST_SPREAD_DEG=180 / FLASH_WHITE=#e8e6e3 / FLASH_BLOOD=#5a1e1e / FLASH_SECONDS=0.2 / FLASH_HOLD_SECONDS=0.2 / SLOWMO_HOLD_SECONDS=0.4 / INVINCIBLE_FLICKER_HZ=8 / INVINCIBLE_FLICKER_ALPHA_MIN=0.3），全部带「issue body/只狼基准 → 候选 + 影响 + 情感断言」注释（DESIGN §3.2；INK_COLOR 与 HUD_INK_BLACK、FLASH_WHITE 与 HUD_MOON_WHITE 同值互引注释）

## Phase 2: 复活编排器（P0，机械层）

- [ ] Task 2 (`shandong-wolf/gdscripts/revive_orchestrator.gd`, 新增): ReviveOrchestrator（Node）——bind_player(entity)（幂等：先解绑旧实体再订阅，仅接受 is_player==true）、_on_entity_died(final=false 才计时，_armed 防重入)、_on_entity_revived（取消 pending，双路径幂等）、_process(delta) 自管理计时（到期 is_instance_valid 守卫后调 entity.revive()）、unbind_player()（DESIGN §2.1）

## Phase 3: 复活演出层（P0，演出层）

- [ ] Task 3 (`shandong-wolf/gdscripts/revive_fx.gd`, 新增): ReviveFX（Node2D）——_ready 代码构建 InkBurst（GPUParticles2D one_shot + 程序化 8x8 圆点 texture，失败降级 null）+ FlashLayer（CanvasModulate 瞬态 Tween：白→血→停留→复原）；bind_player（订阅 revived）+ bind_player_visual（无敌闪烁 modulate 目标）；trigger() 四件套（墨点 burst / 闪屏 Tween / Engine.time_scale 短促降速 _slowmo_set 防嵌套 / _process 相位闪烁 modulate.a 循环）；全参数读 constants 零字面量（DESIGN §2.2）

## Phase 4: 测试 + E2E（P1）

- [ ] Task 4 (`shandong-wolf/tests/test_revive_orchestrator.gd`, 新增): DESIGN §9 Scenario A-G 共 24 用例描述落地——headless 免树（new + 手动 _process 推进）、信号日志成员变量、禁 :=、class_name 经 load()（对齐 test_combat_entity.gd 范本）
- [ ] Task 5 (`shandong-wolf/tests/run_tests.gd`): 追加 `_run("res://tests/test_revive_orchestrator.gd", "ReviveOrchestrator")`
- [ ] Task 6 (`shandong-wolf/scenes/e2e_stick_figure_capture.tscn` + `gdscripts/e2e_stick_figure_capture.gd`): 挂 ReviveFX 节点 + REVIVE 态进入时 fx.trigger() + bind_player_visual（additive 钩子，不动 auto_cycle 既有逻辑；AC5 截图证据路径，DESIGN §3.3）
- [ ] Task 7 全量回归: `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` → 10 套件全绿（含既有 test_combat_entity.gd e1-e6 实体语义零改动基线）+ smoke_test.gd 通过；PR 附开源调研结论引用（DESIGN 附录，PRD §6.2 已调研无需重复）

## 验收（对应 Issue #578 body）

- [ ] AC1: 第一条血归零 → revive 状态 → 1s 后原地复活切半管第二条血（T1-T3）
- [ ] AC2: 复活后 1s 无敌（不可受击/不可被弹反架势伤害）+ 架势条清空（T5-T7）
- [ ] AC3: 第二条血归零才触发玩家死亡事件（died(final=true) 恰一次，供 SW-015 消费）（T8-T9）
- [ ] AC4: 复活动画触发 GPUParticles2D 墨点 burst + CanvasModulate 闪屏（T10-T14）
- [ ] AC5: E2E 截图提交用户裁决（capture rig REVIVE shot + FX 入镜；裁决结果进 docs/TASTE.md）（T24 + E2E）

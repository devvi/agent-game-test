# Tasks: [Feature] 3选1升级UI (Upgrade Pick UI)

> **Parent Issue:** #388
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **设计契约:** docs/DESIGN/388-upgrade-pick-ui.md（§4 伪代码为 implement 契约；§9 测试规格）
> **深度:** depth/standard（6 个实现子任务、跨 4 个子系统，达 SKILL 阈值 → 产出 TASKS，沿 #386 先例）

---

## Phase 1: 常量与推进接管（无 UI 依赖，先行）

- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): 新增 `UPGRADE_UI_LAYER/CARD_WIDTH/CARD_HEIGHT/CARD_SEPARATION/FOCUS_TWEEN/REVEAL_TWEEN/REVEAL_HOLD` 常量组 + `UPGRADE_RARITY_COLORS`/`UPGRADE_RARITY_NAMES` 映射（DESIGN §4.3 伪代码；色值 taste 占位）
- [ ] Task 2 (`mini-pong/gdscripts/wave_controller.gd`): 新增 `settle_hold: bool = false` + `advance_settlement()`（幂等：非结算期 no-op）；`_on_wall_cleared` 结算后 hold 检查跳过自动延时；`_ready` 加 group `wave_controllers`（DESIGN §4.2 伪代码；默认 false 保持 #386 行为）
- [ ] Task 3 (回归): 重跑 `test_wave_cycle.gd` + 全量 headless 确认零破坏（DESIGN §11 步骤 2）

## Phase 2: 升级选择 UI（核心）

- [ ] Task 4 (`mini-pong/gdscripts/upgrade_pick_ui.gd` 新建): 三态状态机（CLOSED/SELECTING/REVEALING）+ `open(wave_index)`（get_candidates(3) 恰好一次、is_run_over 前置检查、paused=true、settle_hold=true、幂等）+ `_unhandled_input` 焦点环（ui_left/right 循环、ui_accept 确认、ui_cancel 不消费）+ `_start_reveal`（稀有度 reveal + REVEAL_HOLD 展示 + 输入锁定）+ `close()`（paused=false、advance_settlement、幂等）+ group 寻址容错（DESIGN §3.1 伪代码）
- [ ] Task 5 (`mini-pong/scenes/ui_upgrade_pick.tscn` 新建): CanvasLayer（layer=2、process_mode=3、visible=false）+ CenterContainer/HBoxContainer + 预创建 3 卡（PanelContainer + StyleBoxFlat 霓虹边框 + Name/ShortPhrase/EffectDesc/RarityLabel，RarityLabel 初始隐藏）（DESIGN §3.2 结构）

## Phase 3: 挂载与测试

- [ ] Task 6 (`mini-pong/scenes/Main.tscn`): 挂载 `ui_upgrade_pick`（ext_resource + CanvasLayer 兄弟节点，初始隐藏；不重复覆写 layer/process_mode）（DESIGN §4.4）
- [ ] Task 7 (`mini-pong/tests/test_upgrade_pick_ui.gd` 新建): 依 DESIGN §9 场景 A–H 编写 28 条测试（seed rng + 短 reveal hold 注入 + `Input.parse_input_event` + mini tree 内 WaveController/mock；TC-E3 Escape 屏蔽回归）
- [ ] Task 8 (`mini-pong/tests/run_tests.gd`): `await _run_async("res://tests/test_upgrade_pick_ui.gd", "Upgrade Pick UI")` 注册；全量 headless 全绿（DESIGN §11 步骤 3）

## Phase 4: 文档闭环（P1）

- [ ] Task 9 (`docs/GAME_DESIGN/25-UPGRADE-UI.md` 新建 + `docs/PROJECT.md`): 记录升级 UI 层设计（CanvasLayer layer 2 / 三态状态机 / 稀有度 reveal 机制），更新模块清单与波次循环状态

---

*完成后 PR 说明：#384 砖墙实现未落地 → 运行时整链路 E2E 不可跑，以 headless 单测 + 手动场景调试兜底（DESIGN §11 步骤 4–6）。*

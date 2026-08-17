# Tasks: title 支持游戏模式选择，支持本地双人对战

> **Parent Issue:** #543
> **Agent:** game-plan-agent
> **Date:** 2026-08-18
> **深度:** depth/standard（文件域白名单 17 文件 ≥10 阈值 + 5+ 独立子系统子任务 → TASKS doc 必需）
> **参考:** docs/DESIGN/543-mode-select-local-2p.md（§3 新组件 / §4 既有组件修改 / §9 测试场景为唯一契约）

## Phase 0: Spike 验证（0.5 天，先于 Phase 1）

- [ ] Spike 1（InputMap 增量 erase headless 安全性）：最小 GDScript `--headless --script` 验证 `action_erase_event` 幂等 + 重复 3 轮无残留；失败 → 回退方案全量重建（DESIGN §10）
- [ ] Spike 2（冻结互斥）：原型 paddle 双状态（`_fsm_frozen` + `_timed_freeze_remaining`）判定式或关系 + 剩余时长续走断言
- [ ] Spike 3（01_title 色断言）：PADDLE_NEON/BRICK_NEON 高亮实测 `run-e2e-review.sh --skip-visual` L0–L2 theme_absent 保持；失败 → modulate 透明度方案

## Phase 1: 常量与静态 action（0.5 天）

- [ ] `gdscripts/constants.gd`：追加新区 `GAME_MODE_*`（SINGLE=0/LOCAL_2P=1）、`P2_*` action 名、`DEBUFF_*` 占位数值（shrink 0.7/freeze 1.5/slow 0.75×8s/reverse 3s）、`UPGRADE_2P_CONFIRM_TIMEOUT=10.0`；既有区逐字节不动（#448/#449/#450/#464 先例）
- [ ] `mini-pong/project.godot`：新增 `[input]` 段 `p1_confirm`(E)/`p2_confirm`(Shift)/`p2_left`(←)/`p2_right`(→)；不触碰任何既有配置

## Phase 2: 模式状态与落盘（0.5 天）

- [ ] `gdscripts/game_manager.gd`：`enum GameMode` + `var game_mode`（默认 SINGLE）+ `set_game_mode`（越界 clamp）/`get_game_mode` + `apply_mode_to_paddles()`（SINGLE 回写 AIPaddle.mode=AI；LOCAL_2P 双板 PLAYER + player_index 0/1；组空 push_warning 容错）（DESIGN §3.2）
- [ ] `gdscripts/game_state_machine.gd`：`enter_state(SERVING)` 中 `reset_match()` 后调 `GameManager.apply_mode_to_paddles()`（has_method 守卫）（DESIGN §4.2）

## Phase 3: 挡板分键与定时状态（1 天）

- [ ] `gdscripts/paddle.gd`：`@export player_index: int = 0`；`_ready()` PLAYER 分支按索引选 action 对（0→paddle_left/right、1→p2_left/right）；`_process()` 读 `Input.get_axis` + invert 取反 + `_speed_scale` 乘数（DESIGN §3.3/§3.4）
- [ ] `gdscripts/paddle.gd`：静态 `rebind_for_mode(mode)`（增量 erase ←/→，事件级比对幂等；Spike 1 结论定稿）
- [ ] `gdscripts/paddle.gd`：三套定时状态 `set_frozen_timed`/`set_speed_scale_timed`/`set_input_invert_timed` + `is_effectively_frozen()`（或关系判定）+ `_process` 定时递减（DESIGN §3.4）
- [ ] `gdscripts/paddle.gd`：连击分流——`_on_score_changed` 按 `player_index` 选分数通道（P2 看 ai_score）（#504 扩展）

## Phase 4: 升级池 debuff（1 天）

- [ ] `gdscripts/upgrade_defs.gd`：既有 6 卡加 `"target": "self"`；新增 4 debuff 定义（shrink_opponent/freeze_opponent/slow_opponent/reverse_opponent，COMMON/RARE/RARE/RARE，`target:"opponent"`，effect 回调读 `ctx["opponent_paddle"]`，判空 no-op）（DESIGN §3.6）
- [ ] `gdscripts/upgrade_pool.gd`：`_build_ctx(player_index=0)` 双目标（self/opponent + `paddle` 回退键）；`apply(id, player_index=0)`；`get_candidates(n, allow_opponent=false)` target 过滤（DESIGN §3.6/§4.2）
- [ ] `mini-pong/assets/content/upgrade_pool.json`：4 条 debuff 条目（`draft: true`，走 #395 human-review）

## Phase 5: 双游标升级 UI（1 天）

- [ ] `gdscripts/upgrade_pick_ui.gd`：2P 分支（`_is_2p` 按 game_mode 判定）——P1/P2 双 focus_index + `_locked_cards` + 确认裁决序（P1 先 P2 后）+ 置灰提示 + 超时代选 10s（DESIGN §3.5）
- [ ] `gdscripts/upgrade_pick_ui.gd`：`open()` 2P 下 `get_candidates(3, allow_opponent=true)`；`_finish_2p()` → close → `_advance_settlement()`（#388 接管不变）；SINGLE 路径不动
- [ ] `scenes/ui_upgrade_pick.tscn`：卡左下/右下角标节点（P1/P2 焦点指示，色避 #4a90d9）

## Phase 6: Title 模式选择与显示层（1 天）

- [ ] `scenes/ui_start_menu.tscn`：TitleLabel/PromptLabel 间插入 ModeSelectVBox（两行选项 Label）（DESIGN §3.1）
- [ ] `gdscripts/start_menu.gd`：`_mode_index`（默认 0）+ `_unhandled_input`（ui_up/ui_down 切换）+ 高亮 Tween 150–300ms + `get_selected_mode()` + `GameManager.set_game_mode()` 即时写入（DESIGN §3.1）
- [ ] `gdscripts/game_hud.gd`：2P 下顶区「AI: N」→「P2: N」（红区颜色保留）
- [ ] `gdscripts/game_over_screen.gd`：2P 分支胜者宣告「P1 WIN!」/「P2 WIN!」（不走失败文案分支）；SINGLE 路径逐字节不动（DESIGN §4.2）
- [ ] `mini-pong/e2e_shots.json`：可选——01_title 增补模式选择 UI 存在性断言（默认单人态，theme_absent 4a90d9 保持）

## Phase 7: 测试与验证（1 天）

- [ ] `mini-pong/tests/test_local_2p.gd`（新增）：场景 A–H（DESIGN §9）——模式状态机/InputMap 拆分幂等/双板配置/连击分流/目标解析/debuff 回调/双游标确认（含同帧裁决与超时）/显示分支/回归
- [ ] `mini-pong/tests/run_tests.gd`：注册 test_local_2p
- [ ] 验证链：`godot --path mini-pong --headless --quit` 零错误（AC6）→ run_tests.gd 全绿（零回归）→ `run-e2e-review.sh --skip-visual` L0–L2 全绿（AC7）→ 实机双人手动过 I1–I3
- [ ] 文件域核对：实现 PR files ⊆ DESIGN §4.1 白名单 17 文件（AC8）

## 交接注记

- debuff 显示文案/数值 = taste-draft 占位（#395 域），实现阶段不得擅自定稿文案
- 单人模式任何路径（输入绑定/升级池/结算/HUD）行为必须与现状逐字节一致（#526/#508 纪律）
- 不写可运行测试文件以外的代码注释风格：新代码遵循既有 `## 注释先例` 风格（含 `Design: docs/DESIGN/543-*.md §X` 引用）

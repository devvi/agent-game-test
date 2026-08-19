# Tasks: [Scaffold] 项目骨架与正式场景入口 — constants.gd + state_machine.gd + autoload 注册

> **Parent Issue:** #572
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **深度:** standard（7 文件 / 4 子系统 6+ 独立子任务 → TASKS doc 必需）
> **参考:** `docs/DESIGN/572-scaffold-main-entry.md`（§2 新组件 / §3 既有修改 / §8 测试场景为唯一契约）
> **红线:** 只动 shandong-wolf/ 下 7 文件；绝不触碰 mini-pong/、Main.tscn、manifest、CI、GDD、美术资产

## Phase 0: Spike 验证（PRD §7，0.25 天，先于 Phase 1-4）

- [ ] Spike 1（单测先行驱动接口）：先写 test_state_machine.gd 两个 mock 状态断言调用序（exit 先于 enter / 同态无回调 / 空状态安全），再实现 state_machine.gd 使测试通过（DESIGN §8 Scenario A-D）
- [ ] Spike 2（三入口全绿实测）：worktree 内依次执行 check_compile / smoke_test / run_tests 三条 headless 命令，记录退出码（DESIGN §8 Scenario F）
- [ ] Spike 3（autoload 启动链冒烟）：注册 Game autoload 后 `godot --path shandong-wolf/ --headless --quit` 退出 0，无 autoload 报错；失败 → 回退方案 B（暂不注册）并在 PR 说明（PRD §5.3-2）

## Phase 1: constants.gd 数值集中地（P0，0.5 天）

- [ ] 1.1 (`shandong-wolf/gdscripts/constants.gd`)：`class_name WolfConstants` extends RefCounted；机械常量区（GAME_VERSION=v0.1.0 / SCREEN_WIDTH=1280 / SCREEN_HEIGHT=720 / STATE_MACHINE_MAX_TRANSITIONS=1）（DESIGN §2.1）
- [ ] 1.2 (同上)：5 个 `# DRAFT` 分区——弹反窗口（PARRY_WINDOW_FRAMES/SECONDS）/ 架势回复（POSTURE_RECOVERY_PER_SEC/BLOCK_COST/BREAK_THRESHOLD）/ 两条命（LIFE_TOTAL/LIFE_1_MAX/LIFE_2_MAX_RATIO）/ 刀伤害（SWORD_DAMAGE_LIGHT/HEAVY/EXECUTE）/ 帧节奏（FRAME_ATTACK_WINDUP/RECOVERY/FRAME_RHYTHM_BASE）；每个 const 带「候补值 + 该值影响什么 + 情感断言」三行注释 + `# DRAFT` 标记，**禁止定稿**（DESIGN §2.1 / §5-4）

## Phase 2: state_machine.gd 通用基类（P0，0.5 天）

- [ ] 2.1 (`shandong-wolf/gdscripts/state_machine.gd`)：`class_name StateMachineBase` extends RefCounted；`current_state` + `_transition_locked` 状态；`transition_to(new_state)`（同态守卫 + 防重入锁 + exit 先于 enter 调用序 + has_method 鸭子类型守卫）；`update(delta)` 转发（空状态 no-op）（DESIGN §2.2）
- [ ] 2.2 (同上)：不设计任何具体状态（#575 职责）；头注释写明三接口契约与派生方式

## Phase 3: Game autoload 锚点（P0，0.25 天）

- [ ] 3.1 (`shandong-wolf/gdscripts/game.gd`)：`class_name Game` extends Node；`const WolfConstants = preload(...)`；`var game_version`（DESIGN §2.3）
- [ ] 3.2 (`shandong-wolf/project.godot`)：新增 `[autoload]` 段 `Game="*res://gdscripts/game.gd"`；不动 `[application]`/`[display]` 任何既有配置（DESIGN §3.1）

## Phase 4: 单测与挂载（P0，0.5 天）

- [ ] 4.1 (`shandong-wolf/tests/test_state_machine.gd`)：extends Object + run()/ _assert 模式；两个 mock 状态对象；覆盖 Scenario A-D（调用序 / 同态守卫 / 防重入 / 空状态）（DESIGN §8）
- [ ] 4.2 (`shandong-wolf/tests/test_constants.gd`)：extends Object；Scenario E——5 分区常量存在 / ≥5 处 `# DRAFT` 且无「# 定稿」字样 / 机械常量值断言（DESIGN §8）
- [ ] 4.3 (`shandong-wolf/tests/run_tests.gd`)：`_run_tests()` 内挂载 `_run("res://tests/test_state_machine.gd", "State Machine")` + `_run("res://tests/test_constants.gd", "Constants")`；_pass/_fail 汇总退出码逻辑保留；**挂载遗漏静默绿必须 FAIL**（DESIGN §5-7）

## Phase 5: 验证收尾（P0，0.25 天）

- [ ] 5.1 三入口全绿：check_compile / smoke_test / run_tests 三条命令退出码均 0（DESIGN §8 Scenario F1-F3）
- [ ] 5.2 主场景冒烟：`godot --path shandong-wolf/ --headless --quit` 退出 0（F4 / AC1）
- [ ] 5.3 文件域核查：PR files ⊆ 白名单 7 文件（3 gdscripts + 2 tests + project.godot + run_tests.gd）；无 .png/.jpg 新增（AC5）；Main.tscn 零 diff
- [ ] 5.4 集成点表回填：DESIGN §6 各 ⬜ → ✅（implement agent 完成接线后）

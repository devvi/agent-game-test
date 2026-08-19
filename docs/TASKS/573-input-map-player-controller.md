# Tasks: [Feature] 输入映射与玩家控制器 — Input Map + InputController + PlayerController

> **Parent Issue:** #573
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **深度:** standard（8 文件 / 3 新组件 + 2 修改 + 3 测试入口 / 6+ 独立子任务跨 4 子系统 → TASKS doc 必需，同 #572 先例）
> **参考:** `docs/DESIGN/573-input-map-player-controller.md`（§2 新组件 / §3 既有修改 / §8 测试场景为唯一契约）
> **红线:** 只动 shandong-wolf/ 下 8 文件（4 新建 + 4 修改）；绝不触碰 mini-pong/、Main.tscn、game.gd、state_machine.gd、manifest、CI、GDD、美术资产；不写可运行测试文件之外的任何非契约代码

## Phase 0: Spike 验证（PRD §7，先于 Phase 1-6）

- [ ] Spike E1（缓冲无吞噬验证）：先写 test_input_controller.gd 的 3 连击断言（DESIGN §8 Scenario A1/A4），再实现缓冲队列使测试通过——队列方案失败 → 退化为单槽（违反 AC5）或插件（违反红线），E1 是方案 A 守门实验
- [ ] Spike E2（同键双义语义分离）：action_press(game_guard) 保持 1 秒不 release，断言 guard_pressed 恰 1 次 + guard_held 每帧持续（DESIGN §8 Scenario B）——决定 `_was_pressed` 边沿状态表必要性
- [ ] Spike E3（移动手感标定）：action_press(game_move_right) 驱动 2 秒测位移；以 MOVE_ACCELERATION=1200 / MOVE_MAX_SPEED=300（# DRAFT）起步 2 帧达标为准，超界调整候选值（DESIGN §8 Scenario F1）

## Phase 1: project.godot Input Map + autoload（P0，0.5 天）

- [ ] 1.1 (`shandong-wolf/project.godot`)：新增 `[input]` 段，9 个 `game_*` 动作（DESIGN §2.1 表）：game_move_left(A+←)/game_move_right(D+→)/game_light_attack(J+左键)/game_heavy_attack(K+右键)/game_guard(L 独键)/game_dash(Shift)/game_jump(Space)/game_interact(E)/game_revive(F)；physical_keycode 按表填（A=65/D=68/J=74/K=75/L=76/Shift=4194325/Space=32/E=69/F=70/←=4194319/→=4194321；鼠标 button_index 1/2）
- [ ] 1.2 (同上)：`[autoload]` 段在 `Game="*res://gdscripts/game.gd"` 之后追加 `InputController="*res://gdscripts/input_controller.gd"`（顺序保证初始化）；不动 `[application]`/`[display]` 任何既有配置
- [ ] 1.3 (验证)：`grep -A2 '^game_' shandong-wolf/project.godot` 全清单可查见（AC1）

## Phase 2: constants.gd 输入层分区（P0，0.25 天）

- [ ] 2.1 (`shandong-wolf/gdscripts/constants.gd`)：文件末尾 `FRAME_RHYTHM_BASE` 之后追加输入层 `# DRAFT` 分区 5 常量（DESIGN §2.4）：INPUT_BUFFER_WINDOW_MS=150（∈[100,200]，AC4）/ INPUT_BUFFER_MAX=8 / DASH_HOLD_THRESHOLD_MS=200 / MOVE_ACCELERATION=1200.0 / MOVE_MAX_SPEED=300.0；每个 const 带「候补值 + 该值影响什么 + 情感断言」注释 + `# DRAFT` 标记，**禁止定稿**；`PARRY_WINDOW_FRAMES` 只读不改

## Phase 3: input_controller.gd 意图事件层（P0，1 天）

- [ ] 3.1 (`shandong-wolf/gdscripts/input_controller.gd`)：`class_name InputController` extends Node；8 信号声明（attack_pressed / heavy_attack_pressed / guard_pressed(timestamp_ms:int) / guard_held / dash_pressed / jump_pressed / interact_pressed / revive_pressed）（DESIGN §2.2）
- [ ] 3.2 (同上)：`EDGE_ACTIONS` 表 + `_was_pressed` 边沿状态表 + `_process` 轮询（`_clear_expired` + `_poll_edges` + `_update_dash_hold`）
- [ ] 3.3 (同上)：时间戳缓冲队列——`_push_buffer`（上限 `INPUT_BUFFER_MAX` 拒新不丢旧）/ `_clear_expired`（超窗过滤）/ `poll_buffer`（FIFO 出队）/ `peek_buffer` / `buffer_size`
- [ ] 3.4 (同上)：guard 双义——按下边沿 emit `guard_pressed(Time.get_ticks_msec())` 恰 1 次，按住期间每帧 emit `guard_held`；dash 双义——按下计时，释放 < `DASH_HOLD_THRESHOLD_MS` emit `dash_pressed`，按住 ≥ 阈值 `is_sprinting()==true`
- [ ] 3.5 (同上)：`_validate_input_map()`——`InputMap.has_action` 全清单校验，缺失 push_error 列出 + 降级运行不 crash；参数读取处 clampf 防非法值（0/负/NaN）
- [ ] 3.6 (同上)：`get_move_axis()` = `Input.get_axis("game_move_left","game_move_right")`（连续轴，不进缓冲）

## Phase 4: player_controller.gd 移动实体（P0，0.5 天）

- [ ] 4.1 (`shandong-wolf/gdscripts/player_controller.gd`)：`class_name PlayerController` extends CharacterBody2D；`_ready` 里 `add_to_group("player")`（#6 近距探测前置）（DESIGN §2.3）
- [ ] 4.2 (同上)：`_physics_process` 加速度模型——`velocity.x = move_toward(velocity.x, dir*C.MOVE_MAX_SPEED, C.MOVE_ACCELERATION*delta)`；`velocity.y = 0`（无重力）；`move_and_slide()`；dir 来自 `InputController.get_move_axis()`
- [ ] 4.3 (同上)：不消费边沿事件（消费方直连 InputController 信号，本类不转发/不拦截）

## Phase 5: 测试套件（P0，0.75 天）

- [ ] 5.1 (`shandong-wolf/tests/test_input_controller.gd`)：extends Object + `run()` + `_assert` 计数模式；用例 = DESIGN §8 Scenario A-E（缓冲无吞噬/双义/时间戳/垫步阈值/校验）
- [ ] 5.2 (`shandong-wolf/tests/test_player_controller.gd`)：extends Object；用例 = DESIGN §8 Scenario F-H（位移 ≥100px/加速度/左右抵消/静止/group）
- [ ] 5.3 (`shandong-wolf/tests/run_tests.gd`)：`_run_tests()` 追加 `_run("res://tests/test_input_controller.gd", "InputController")` + `_run("res://tests/test_player_controller.gd", "PlayerController")`（现 2 套件 → 4 套件）
- [ ] 5.4 (`shandong-wolf/tests/smoke_test.gd`)：扩展 AC6 断言——程序化实例化 PlayerController 入树 → action_press(game_move_right) 定步长推进 ~120 帧 → `position.x ≥ 100`；connect attack_pressed/guard_pressed/dash_pressed 断言均被捕获；原「SMOKE OK」探针保留（DESIGN §8 Scenario I）

## Phase 6: 三入口全绿 + PR 说明（P0，0.5 天）

- [ ] 6.1 (验证)：`godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0（覆盖新增 4 脚本）
- [ ] 6.2 (验证)：`... --script tests/run_tests.gd` 退出 0，「TESTS: N passed, 0 failed」且 N ≥ 4 套件用例总数；pass==0 → 非 0（防静默绿）
- [ ] 6.3 (验证)：`... --script tests/smoke_test.gd` 退出 0（AC6 位移 + 信号捕获断言全过）
- [ ] 6.4 (验证)：`godot --path shandong-wolf/ --headless --quit` 退出 0（autoload 追加后启动链兼容）
- [ ] 6.5 (PR 说明)：写明开源调研结论（PRD §6.2：6 候选插件均不引入，复用 dragonforge 缓冲模式）+ guard/dash 键位裁决（L 独键 vs Shift）+ PRD 两处歧义裁决（8 vs 9 动作；smoke_test.gd 纳入修改）+ AC3 跨系统依赖 #6 标注

## 交付后（非本 PR 范围）

- [ ] post-merge agent：GDD 补记（输入映射表 + 意图事件契约 + InputController 接口 + guard/dash 键位裁决）
- [ ] 分解 id 3（动画消费意图事件）与 id 6（弹反判定消费 guard_pressed/guard_held）在 #573 merged 后创建 GitHub issue

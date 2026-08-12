# Tasks: 升级池架构 (UpgradePool)

> **Parent Issue:** #387
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Depth:** depth/standard —— 满足 TASKS 阈值（10+ 文件受影响、5+ 不同子系统子任务）
> **Reference:** docs/DESIGN/387-upgrade-pool-architecture.md（设计契约，本文档为任务清单）

---

## Phase 1: 常量与定义层（P0）

- [ ] T1 (`mini-pong/gdscripts/constants.gd`): 新增「── Upgrade Pool (#387) ──」组 —— `UPGRADE_RARITY_WEIGHTS`(common 0.6/rare 0.3/legendary 0.1)、`UPGRADE_CANDIDATE_COUNT=3`、`UPGRADE_POOL_SIZE=9`、`PADDLE_WIDTH_MIN=60`、`PADDLE_WIDTH_MAX=660`（默认手感常量 #367 不动）
- [ ] T2 (`mini-pong/gdscripts/upgrade_defs.gd`, 新建): `class_name UpgradeDefs`，`build_defs()` 返回 9 条定义（id/name/rarity/max_stacks/effect_desc/effect: Callable），9 个静态效果回调按 DESIGN §2.1 分级实现（4 完整参数型 + 3 钩子型 + 3 桩）

## Phase 2: UpgradePool autoload（P0）

- [ ] T3 (`mini-pong/gdscripts/upgrade_pool.gd`, 新建): `extends Node` + `class_name UpgradePool`；`rng`(可播种)、`_stacks`、`_defs`、`_display`、`_rarity_pool` 状态；`_ready()` 构建 defs + `_load_display()` + `BrickUpgradeHooks.register_all(grid)`
- [ ] T4 (同上): `get_candidates(n=3)` —— 每卡稀有度先掷 + 候选内去重 + 稀有度池空回退（DESIGN §4 Flow 1 / §5 边界 1-2）；`apply(id)` —— 校验/计数/effect.call(ctx)/max_stacks=1 移出池；`get_definitions()`/`get_stack_count()`/`set_seed()`/`reset()`
- [ ] T5 (`mini-pong/gdscripts/brick_upgrade_hooks.gd`, 新建): `class_name BrickUpgradeHooks`，`register_all(grid)` 注册 pre_hole/fireball_blast/battering_ram 三个回调（DESIGN §2.3）
- [ ] T6 (`mini-pong/project.godot`): `[autoload]` 注册 `UpgradePool="*res://gdscripts/upgrade_pool.gd"`

## Phase 3: 参数实例化（AC3，P0）

- [ ] T7 (`mini-pong/gdscripts/paddle.gd`): `SPEED/PADDLE_WIDTH/PADDLE_HEIGHT` const → `@export var paddle_speed/paddle_width/paddle_height`（默认值 = CONSTS）；`_process` 2 处 SPEED 引用 → paddle_speed；`_ready` 边界计算提取 `_recalc_bounds()` 并改用 paddle_width
- [ ] T8 (同上): 新增 `set_paddle_width(w)` —— clamp + CollisionShape2D.shape.size.x 同步 + `_recalc_bounds()`；新增 `magnet_enabled`/`magnet_strength` + `_process` 磁心吸引逻辑（frozen 守卫之后）
- [ ] T9 (`mini-pong/gdscripts/ball.gd`): 新增 `@export var speed_scale: float = 1.0`，`_process` 位移乘 speed_scale（默认 1.0 行为不变）

## Phase 4: 测试（P0）

- [ ] T10 (`mini-pong/tests/test_upgrade_pool.gd`, 新建): 按 DESIGN §9 Scenario A–D/G/H 编写 —— 9 定义/id 对齐/max_stacks、稀有度分布（播种 + 大样本统计）、候选去重、不可重复/堆叠、apply 参数型效果、桩效果安全、钩子假 grid 桩、JSON 回退
- [ ] T11 (`mini-pong/tests/test_paddle.gd`): 新增 Scenario E 用例 —— 实例属性默认值、set_paddle_width 同步/下一帧生效/边界 clamp、既有回归全绿
- [ ] T12 (`mini-pong/tests/run_tests.gd`): 注册 `_run("res://tests/test_upgrade_pool.gd", "Upgrade Pool")`
- [ ] T13 验证: `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；`godot --path mini-pong/ --headless --quit` 编译通过

## Phase 5: 砖墙钩子集成（AC4，P1 —— 随 #384 落地）

- [ ] T14 (`mini-pong/gdscripts/breakout_grid.gd`, #384 implement 时增量): `upgrade_hooks` 注册表 + `register_upgrade_hook`/`apply_upgrade_hook`/`open_hole(count)`/`blast_neighbors(pos, radius)`（DESIGN §2.4；不改变 #384 既有 API）
- [ ] T15 集成验证: #384 落地后，T-G2 换真实 grid 断言 open_hole/blast_neighbors 生效；砖类升级（pre_hole/fireball/battering_ram）端到端验证

---

## 验收映射

| AC | 任务 |
|----|------|
| AC1 9 定义 + 效果回调 | T2 + T-A1/T-A2 |
| AC2 60/30/10 + 不可重复/堆叠 | T1/T4 + T-B1/T-C1~C3 |
| AC3 实例参数下一帧生效 | T7/T8/T9 + T-E1~E5/T-F1~F2 |
| AC4 砖墙 upgrade_hooks | T5/T14 + T-G1~G3 |
| AC5 get_candidates/apply | T3/T4 + T-B2~B4/T-D1~D4 |

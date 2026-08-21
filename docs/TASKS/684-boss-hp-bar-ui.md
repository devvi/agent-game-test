# Tasks: [UI] 敌人 Boss 血条 UI（只狼式顶部血条 + 架势条组合）

> **Parent Issue:** #684
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **依据:** `docs/DESIGN/684-boss-hp-bar-ui.md`（§7 实现阶段）—— 6 项子任务跨 5 子系统（常量 / 名字 Label / 闪白状态机 / 分档 API / 装配接线 / 测试与 E2E），触发 skill standard 阈值产出 TASKS（照 #683/#661 先例）
> **红线提醒:** 零签名破坏（`set_target_enemy` 等既有 API 不动）；零 `_process` 轮询；零贴图/tscn；`# DRAFT` 数值只读不裁决；不写测试文件以外任何多余代码

## Phase 1: 常量（constants.gd）

- [ ] Task 1 (`shandong-wolf/gdscripts/constants.gd`): 在 HUD 分区之后追加「Boss 血条 UI」分区，5 项 `# DRAFT` 常量（默认 + 候选集 + 情感断言注释）：
  - `HUD_ENEMY_NAME_WIDTH = 240.0`（候选 [200, 240, 280]）
  - `HUD_ENEMY_NAME_FONT_SIZE = 16`（候选 [14, 16, 18]）
  - `HUD_ENEMY_NAME_TOP = 2.0`（候选 [0.0, 2.0, 4.0]）
  - `HUD_STANCE_BREAK_FLASH_SECONDS = 0.18`（候选 [0.12, 0.18, 0.25]）
  - `HUD_STANCE_BREAK_FLASH_COLOR = HUD_MOON_WHITE`（候选 [HUD_MOON_WHITE, HUD_BLOOD_RED.lightened(0.5)]）

## Phase 2: 敌人名字 Label（hud.gd）

- [ ] Task 2 (`shandong-wolf/gdscripts/hud.gd`): `_create_nodes()` 中 `EnemyHealthBar` 创建后追加 `EnemyNameLabel`（`_make_enemy_name_label()` 新私有方法，`_make_hint_label` 同构但**无底框**）；锚点 0.5、宽 `HUD_ENEMY_NAME_WIDTH`、top `HUD_ENEMY_NAME_TOP`、font_size `HUD_ENEMY_NAME_FONT_SIZE`、`OVERRUN_TRIM_ELLIPSIS`
- [ ] Task 3 (`shandong-wolf/gdscripts/hud.gd`): 新增公有 API `set_enemy_display_name(name: String)`（设置 text + `_enemy_display_name` 状态 + `_apply_enemy_visibility()`）；`var EnemyNameLabel: Label` 公有成员

## Phase 3: 崩解闪白状态机（hud.gd）

- [ ] Task 4 (`shandong-wolf/gdscripts/hud.gd`): `_HudBar` 内层类新增 `_break_flash: bool` / `_break_flash_alpha: float` / `_flash_tween: Tween` 状态 + `set_break_flash()`（Tween 淡出 `HUD_STANCE_BREAK_FLASH_SECONDS`，finished 复位）/ `clear_break_flash()` / `is_break_flashing()`；`_draw` 描边与活性段填充分支各加 flash 覆盖（`HUD_STANCE_BREAK_FLASH_COLOR.lerp(原色, _break_flash_alpha)`）
- [ ] Task 5 (`shandong-wolf/gdscripts/hud.gd`): `_on_enemy_stance_broken` 增订 `EnemyStanceBar.set_break_flash()`（保留 `_show_execute_hint()`）；新增 debug API `set_debug_stance_break()`（E2E 驱动，直接置 flash 态）

## Phase 4: Boss/杂兵分档 API（hud.gd）

- [ ] Task 6 (`shandong-wolf/gdscripts/hud.gd`): 新增 `_boss_mode: bool = false` 状态 + 公有 API `set_boss_mode(enabled: bool)`（幂等同值早退）+ 内部 `_apply_enemy_visibility()` 三态显隐唯一收敛点
- [ ] Task 7 (`shandong-wolf/gdscripts/hud.gd`): `set_target_enemy` 增订——有效/null 分支显隐行替换为 `_apply_enemy_visibility()`（分段 `set_segments` 初始化保留、先数据后显隐）；`_on_enemy_died` 增订——final 隐藏名字、非 final 清名字 + `EnemyStanceBar.clear_break_flash()`

## Phase 5: 装配接线（main_battle.gd）

- [ ] Task 8 (`shandong-wolf/gdscripts/main_battle.gd`): `_build_hud` 末尾追加 2 行——`hud.set_boss_mode(true)` + `hud.set_enemy_display_name("…")`（taste 文案 `# DRAFT` 占位，候选进 PR）
- [ ] Task 9 (可选, `shandong-wolf/tests/test_main_assembly.gd`): 装配断言 `_boss_mode == true` + EnemyHealthBar/EnemyNameLabel 可见

## Phase 6: 测试与 E2E

- [ ] Task 10 (`shandong-wolf/tests/test_hud.gd`): 新增场景 A（名字 Label 布局/显隐 A1-A6）、场景 B（闪白状态机 B1-B6）、场景 C（分档三态 C1-C5）、场景 D 回归扩展（died 分支名字断言）；既有 T1-T28/B1-B5 零改动
- [ ] Task 11 (`shandong-wolf/gdscripts/e2e_hud_capture.gd`): enum 扩展 `BOSS_BAR=4 / STANCE_BREAK_FLASH=5 / MINION_MODE=6` + digit 键 4-6 + `CYCLE_SEQUENCE` 7 态 + `_drive_state` 3 新分支
- [ ] Task 12 (`shandong-wolf/e2e_shots.json`): hud group 追加 3 shots（05_hud_boss_bar / 06_hud_stance_break_flash / 07_hud_minion_mode）

## 收尾

- [ ] Task 13: 全量验证——`godot --path shandong-wolf/ --headless --quit` 编译通过；`tests/run_tests.gd` 全绿（含既有用例）；E2E hud group 3 新帧截图产出；候选集（名字文案/闪白时长颜色/百分比文本去留）随 PR 提交供 taste 裁决

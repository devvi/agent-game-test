# Tasks: [Taste] 战斗数值 DRAFT 集中表（手感候补值 + 一次性调参面板）

> **Parent Issue:** #584
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **深度:** standard（6 文件 / 3 子系统 8+ 独立子任务 → TASKS doc 必需，参照 #572 先例）
> **参考:** `docs/DESIGN/584-combat-tuning-draft.md`（§2 新组件 / §3 既有修改 / §8 测试场景为唯一契约）
> **红线:** 只动 shandong-wolf/ 下 6 文件（3 新建 + 3 修改）；绝不触碰 mini-pong/、Main.tscn、project.godot、e2e_shots.json、manifest、CI、GDD、美术资产/插件/UI 图片；**禁止把任何 # DRAFT 值「顺手定稿」**（taste-draft v4，test_constants A4 断言强制）；PR body 用 `Parent #584` 不写 Closes

## Phase 0: Spike 验证（PRD §7，0.5 天，先于 Phase 1-4）

- [ ] Spike 1（F1 物理键 + debug 判定实测）：最小脚本打印 `OS.is_debug_build()` + F1 keycode；headless 跑一次 + GUI 跑一次；导出 release 模板验证判定为 false（DESIGN §7 Phase 1 / PRD §7 实验 1）；F1 捕获不可靠 → 改 InputMap 动作 `toggle_debug_canvas`（集中改名点，PRD §5.2-1 回退路径）
- [ ] Spike 2（纯 Control 布局 1280x720 可行性）：程序化构建 VBoxContainer + ScrollContainer 原型，截图验证 14 行 × 28px 可读、CJK 正常、StyleBoxFlat 半透明白底无图片资产（PRD §7 实验 2）
- [ ] Spike 3（override 热更新链路端到端）：构造假消费方每帧读取 `PARRY_WINDOW_FRAMES`，面板改值后断言下一帧读值变化；模拟 release 走回落分支断言返回 const；读值函数禁止缓存（PRD §7 实验 3）

## Phase 1: constants.gd 全量 DRAFT 值表（P0，1 天）

- [ ] 1.1 (`shandong-wolf/gdscripts/constants.gd`)：5 个既有分区全量改造为「只狼基准 / 候选集 / 偏离理由」三行注释 + `# DRAFT` 标记（DESIGN §2.3 分区一~五：PARRY_WINDOW_FRAMES=12、POSTURE_RECOVERY_PER_SEC=25（旧占位 0.8 必须消失）、POSTURE_BLOCK_COST=10、POSTURE_BREAK_THRESHOLD=100、LIFE_1_MAX=100、LIFE_2_ABS=50、SWORD_DAMAGE_LIGHT=12、SWORD_DAMAGE_HEAVY=30、SWORD_DAMAGE_EXECUTE=999、FRAME_* 延续）
- [ ] 1.2 (同上)：新增「受击/敌人/处决」分区 7 常量——POSTURE_HIT_COST=35（30-40）/ PARRY_COST=1（0-2，偏离理由注明只狼为 0）/ POSTURE_RECOVERY_DELAY=1.5 / ENEMY_ATTACK_WINDUP=15（12-18）/ EXECUTE_RANGE=1.2 / SLOWMO_COEFF=0.2（clamp 下限 0.1）/ LIFE_2_ABS=50（40-60），各带三行注释（DESIGN §2.3 分区六）
- [ ] 1.3 (同上)：`LIFE_2_MAX_RATIO` 保留 const（=0.5，#572 兼容），注释标注「派生展示 = LIFE_2_ABS / LIFE_1_MAX，消费方经 get_value 读派生值」（DESIGN §2.2 派生规则表）
- [ ] 1.4 (同上)：**禁止**改 `GAME_VERSION`/`SCREEN_*`/`STATE_MACHINE_MAX_TRANSITIONS` 机械常量；**禁止**任何参数去 `# DRAFT` 标记或改正式值

## Phase 2: debug_canvas.gd 调参面板（P0，1.5 天）

- [ ] 2.1 (`shandong-wolf/gdscripts/debug_canvas.gd`)：`class_name DebugCanvas` extends CanvasLayer；`const PARAMS: Array[Dictionary]` 14 行参数表（name/label/min/max/step/candidates/default，DESIGN §2.1 表逐字落地）；`_build_ui()` 程序化构建 PanelContainer（StyleBoxFlat 白底 80% 透明）→ ScrollContainer(440×400) → 14 行 HSlider/SpinBox → 工具行（导出 JSON/重置默认/隐藏）；零 tscn 零图片
- [ ] 2.2 (同上)：静态 `_overrides: Dictionary` + `get_value(param_name, default)`（首行 `OS.is_debug_build()` 回落）+ `_resolve_value` 纯函数 + `is_available()`（DESIGN §2.1 静态成员逐字落地）
- [ ] 2.3 (同上)：`_unhandled_input` F1 toggle（`key.pressed and not key.echo and key.keycode == KEY_F1`，仅 debug build）；`_ready()` 内 `OS.is_debug_build()` 双保险 queue_free
- [ ] 2.4 (同上)：`_on_param_changed` range 硬校验（越界拒绝）+ `_apply_derived_rules` 联动（LIFE_1_MAX ↔ POSTURE_BREAK_THRESHOLD 双向，含 `_sync_row` 面板行同步）
- [ ] 2.5 (同上)：`_export_dump()` → `user://tuning_dump_<ts>.json`（meta: game_version/ts/group + params 14 键）；「重置默认」清空 `_overrides`；dump 不自动加载（MVP 无持久化）
- [ ] 2.6 (同上)：SLOWMO_COEFF 写入 clamp 下限 0.1；处决演出期间改值只写 override 不立即改 `Engine.time_scale`（DESIGN §5 边界 3）

## Phase 3: Game autoload 条件实例化（P0，0.5 天）

- [ ] 3.1 (`shandong-wolf/gdscripts/game.gd`)：`const DebugCanvasScript = preload("res://gdscripts/debug_canvas.gd")` + `func _ready() -> void: if DebugCanvasScript.is_available(): add_child(DebugCanvasScript.new())`（+4 行；**唯一 PRD 清单扩展项**，PR 中说明理由：Main.tscn/project.godot 双红线下唯一挂接点，DESIGN §1.2/§3.1）
- [ ] 3.2 (`shandong-wolf/project.godot`)：**零改动**（F1 走 `_unhandled_input` 不占 InputMap）——diff 核查确认

## Phase 4: 测试（P0，0.75 天）

- [ ] 4.1 (`shandong-wolf/tests/test_constants.gd`)：扩展 Scenario A——A1 14 参数存在性（get_script_constant_map）/ A2 三行注释格式（「只狼基准:」+「候选集:」或「偏离理由:」文本扫描）/ A3 候选集 ≥2（豁免名单 LIFE_TOTAL、SWORD_DAMAGE_EXECUTE）/ A4 `# DRAFT` ≥14 且无「# 定稿」/ A5 新增分区 7 常量 / A6 默认值抽查（DESIGN §8）；既有 E1-E3 断言保留
- [ ] 4.2 (`shandong-wolf/tests/test_debug_canvas.gd`)：extends Object + run()/_assert 模式；Scenario B（B1 override 命中 / B2 回落 / B3 未知名静默回落 / B4 is_available + 源码含 OS.is_debug_build 判定 / B5 派生参数裁决）；Scenario C（C1 PARAMS↔constants 双向集合一致 / C2 range 覆盖默认 / C3 candidates ⊆ range）；Scenario D（D1 F1 toggle / D2 越界拒绝 / D3 SLOWMO clamp / D4 联动写入 / D5 dump JSON 可解析含 14 键 / D6 重置默认）（DESIGN §8）
- [ ] 4.3 (`shandong-wolf/tests/run_tests.gd`)：`_run_tests()` 追加 `_run("res://tests/test_debug_canvas.gd", "DebugCanvas")` 第 3 套件；_pass/_fail 汇总保留；套件数 = 3

## Phase 5: 验证收尾（P0，0.5 天）

- [ ] 5.1 三入口全绿：check_compile / smoke_test / run_tests 三条 headless 命令退出码均 0（DESIGN §8 Scenario E1-E3）；debug 下 smoke 实际创建面板节点无报错（E2）
- [ ] 5.2 主场景冒烟：`godot --path shandong-wolf/ --headless --quit` 退出 0（E4）
- [ ] 5.3 AC4 证据材料：3 组候选对比（基准组全默认 / 宽容组 弹反14+回复35+受击30 / 严苛组 弹反8+回复20+受击40）各导出 `user://tuning_dump_<ts>.json` + 面板截图 + 手感描述（弹反容错/架势节奏/紧张感），附 PR；战斗内效果截图顺延 #575/#577，**不搭战斗 demo**（PRD §8 风险红线）
- [ ] 5.4 (`docs/TASTE.md`)：shandong-wolf 建档占位——候补值表（14 参数 × 只狼基准/候选/草稿值，链接 constants.gd）+ 试玩剧本（3 组对比操作步骤）+ 定稿差异记录（留空待用户裁决回填）（DESIGN §3.2）
- [ ] 5.5 文件域核查：PR files ⊆ 白名单 6 文件（constants.gd / debug_canvas.gd / game.gd / test_constants.gd / test_debug_canvas.gd / run_tests.gd）+ docs/TASTE.md；Main.tscn / project.godot / e2e_shots.json 零 diff；无 .png/.jpg 新增
- [ ] 5.6 集成点表回填：DESIGN §6 各 ⬜ → ✅（implement agent 完成接线后）；PR body 含开源调研表结论（PRD §4.2：4 组关键词无成熟方案 → 自研）
- [ ] 5.7 红线自查：无任何 DRAFT 值被定稿（去 # DRAFT / 改正式值 = test_constants A4 FAIL）；PR body 为 `Parent #584`（无冒号、不写 Closes）

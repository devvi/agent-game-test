# Tasks: [Test] 端到端验证（E2E 剧本 + 用户裁决）

> **Parent Issue:** #586
> **深度:** standard（PRD 头标注 depth: standard；GitHub 无 depth 标签）—— 9 文件（2 新建 + 7 修改，全 E2E 侧）/ 7 项实现子任务跨 4 子系统（rig / shot plan / 驱动与管线 / 报告与裁决）+ 3 个 Spike 实验 → **产出 TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，照 #585 先例）
> **依据:** `docs/DESIGN/586-e2e-script-adjudication.md`（plan PR 已合并后本清单即 implement 的合同）

## Phase 0: Spike 实验（PRD §7 三实验，先于编码）
- [ ] Spike E1 (clash 帧确定性): 双实体同帧 `request_transition("attack")` 推进 N 帧监听 judge.clash（rig 连接信号）→ 成功率 ≥90% 则主路径保留，否则 fallback `trigger_feedback("clash")`（构图一致）；results.json 标注 `clash_source`（DESIGN §2.2 `_drive_clash_via_judge`）
- [ ] Spike E2 (MOVE 稳定性): rig 内部按住 `game_move_right` 170 帧 → `move_displacement_px` ≥100px（smoke I1 口径）；若 <100px 检查 InputController bind 路径（DESIGN §2.2 `_start_move_drive`）
- [ ] Spike E3 (Movie Maker 保真): 同场景 rig 截图 vs `--write-movie` 输出逐像素对比；一致则 Tier 3 写入管线文档（DESIGN §3.4）

## Phase 1: resolve_plan.py 组级键提升（P0，缺口 1）
- [ ] Task 1 (`scripts/e2e/resolve_plan.py`): `_GROUP_PROMOTED` 追加 `main_scene`/`state_node`/`state_property`/`states`（first activated group wins，与既有语义一致；DESIGN §3.2）
- [ ] Task 2 (`tests/pipeline/test_e2e_resolve.py`): + 2 用例——组级 main_scene 提升 / 组级 states 提升（未声明组不引入键）；既有 TestDeadlinePassthrough 保持绿

## Phase 2: e2e_capture.gd 驱动修复（P0，缺口 2/5）
- [ ] Task 3 (`framework/templates/e2e_capture.gd`): `_shot_ready` 数字/浮点 state 直接 `int()` 数值比较（字符串 state 走原 states 映射；DESIGN §3.2 伪代码逐字）
- [ ] Task 4 (`framework/templates/e2e_capture.gd`): results.json 捕获条目透传 `scene_description`/`trigger`/`composition`（白名单，缺省跳过；DESIGN §3.2）

## Phase 3: 管线分辨率 + 尺寸断言 + headless 语义（P0，缺口 3/6）
- [ ] Task 5 (`scripts/run-e2e-review.sh`): P5 从 `$WT/$SUBPROJECT/project.godot` 读取 `window/size/viewport_width/height` 生成 `--resolution WxH`（替换硬编码 720x1280，DESIGN §3.2 inline python 同款）；头注释补 headless 三档语义（Tier 1 本地 display driver / Tier 2 CI xvfb / Tier 3 Movie Maker）
- [ ] Task 6 (`scripts/e2e/analyze_bmp.py`): 可选 `--size WxH` 参数——解码后 `(width,height) != (W,H)` 即断言失败；不传则跳过（向后兼容）；P5 L3 每帧注入 `--size "$VIEWPORT"`

## Phase 4: rig 4→7 态扩展（P0，DESIGN §2.2 逐字）
- [ ] Task 7 (`shandong-wolf/gdscripts/e2e_main_assembly_capture.gd`): 枚举扩为 `SPAWN_COMBAT=0 / PARRY=1 / FAIL_SUBTITLE=2 / AFTERGLOW=3 / MOVE=4 / CLASH=5 / EXECUTE=6`（0-3 编号保留）+ `CYCLE_SEQUENCE` 7 态 + `CYCLE_DWELL_FRAMES` 表（SPAWN 40 / MOVE 170 / PARRY 40 / CLASH 40 / EXECUTE 90 / FAIL 40 / AFTERGLOW 40）
- [ ] Task 8 (`shandong-wolf/gdscripts/e2e_main_assembly_capture.gd`): `_drive_state` 重构——每态 `_dwell_frames_left = CYCLE_DWELL_FRAMES[state]` + 进入先 `_release_move_drive()`/`_unfreeze_effects()`；MOVE 态 `_start_move_drive`（内部按住 game_move_right + `move_displacement_px` 每帧更新）/ `_release_move_drive`；PARRY/CLASH/EXECUTE 态设 `reaction.freeze_time_stack=true`
- [ ] Task 9 (`shandong-wolf/gdscripts/e2e_main_assembly_capture.gd`): `_drive_first_parry`（注入 parry_success + `_impact_pos` + 特写构图）/ `_drive_clash`（E1 主路径 + fallback + `clash_source` 标注）/ `_drive_execute_closeup`（承接原 `_drive_parry_execute`：崩解→处决姿态→S 级反馈，不调 execute_kill）；SPAWN/FAIL/AFTERGLOW 驱动逻辑原样保留
- [ ] Task 10 (`shandong-wolf/gdscripts/e2e_main_assembly_capture.gd`): digit 键 1-4 → 1-7（5→MOVE / 6→CLASH / 7→EXECUTE，人工调试用）；特写态 StageCamera zoom 推近（无 zoom 先例则退化为 position 构图）

## Phase 5: e2e_shots.json 剧本组（P0，DESIGN §2.1 逐字）
- [ ] Task 11 (`shandong-wolf/e2e_shots.json`): 新增 `e2e_script` 组——main_scene/state_node/state_property + match 3 条 + 6 shots（01_village_open state 0 / 02_player_move state 4 + require 位移 ≥100 / 03_first_parry state 1 / 04_clash state 5 / 05_execute_closeup state 6 / 06_fail_subtitle state 2），每帧含 scene_description/trigger/composition 文字契约 + settle_frames/theme_color 6e7684
- [ ] Task 12 (`shandong-wolf/e2e_shots.json`): assembly 组 match 收窄为 `["scenes/Main\\.tscn", "scenes/battle_stage\\.tscn"]`（与 e2e_script 互斥）+ `02_parry_execute` state 1→6 + `_comment` 更新

## Phase 6: 报告模板 + 全量验证（P1）
- [ ] Task 13 (`docs/TEST/586-e2e-script-adjudication.md`): 按 DESIGN §2.3 模板落地（单测/smoke/E2E 三栏 + 6 帧 PNG + 元数据 + 裁决表 + 打回目标映射）
- [ ] Task 14 (验证): `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` exit 0 + `tests/smoke_test.gd` exit 0（AC3）+ `python3 -m unittest discover -s tests/pipeline -v`（resolve_plan 回归）+ `scripts/run-e2e-review.sh <PR> --subproject shandong-wolf --with-visual` 产出 6 帧 1280x720 PNG + results.json 元数据齐全（AC2）

## Phase 7: 用户裁决（P1，用户环节）
- [ ] Task 15 (PR 附属): 6 帧 PNG + 报告提交用户裁决（1-5 星/帧，平均 ≥4 通过 / <4 打回）+ 实机手感侧证（5-10 分钟试玩对照）；PR 说明开源调研结论（PRD §4.4：headless 无渲染实证 / GUT/gdUnit4 不引入 / Movie Maker Tier 3）
- [ ] Task 16 (回填): 裁决意见回填对应 Issue acceptance（`gh issue edit` 追加：①→#582 / ②→#574 / ③④→#579 / ⑤→#580 / ⑥→#585+#584）；打回则附差异帧对比（下轮重跑）；**agent 不评星**

## 验证清单（收尾）
- [ ] `python3 -m unittest discover -s tests/pipeline -v` 全绿（resolve_plan 组级键提升 + deadline 透传锁定）
- [ ] `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` exit 0（覆盖 e2e_main_assembly_capture.gd）
- [ ] `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` exit 0（AC3 单测全绿基线不变）
- [ ] `godot --path shandong-wolf/ --headless --script tests/smoke_test.gd` exit 0（AC3 smoke 含 AC4 闭环）
- [ ] E2E 6 帧 PNG 全 1280x720（--size 断言）+ results.json 每帧 state 与 shot 期望一致 + clash_source 已标注
- [ ] docs/TEST/586 报告含三栏 + 裁决表；裁决意见已回填对应 issue acceptance（AC5）

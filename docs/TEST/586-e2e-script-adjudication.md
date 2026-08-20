# E2E 剧本执行报告 — #586（端到端验证）

> 运行日期：_YYYY-MM-DD_
> 引擎版本：godot 4.7.1
> 分支 commit：_<branch>@<commit>_
> 运行人：_<name>_

> **模板说明：** 本模板由 implement #586 产出（`docs/TEST/586-e2e-script-adjudication.md`），运行后填充。裁决意见按 §3 打回目标回填对应 Issue acceptance（AC5）；**agent 不评星、不裁决文案、不替用户定稿**（issue 红线）——§3 用户裁决是唯一 taste 环节。

## 1. 自动化测试（AC3）

| 套件 | 结果 | 计数 |
|------|:---:|------|
| L0 compile（check_compile.gd） | ✅ exit 0 | _55/55_ |
| L1 单测（run_tests.gd，18 套件） | ✅ exit 0 | _N/N passed_ |
| smoke（smoke_test.gd，含 AC4 闭环） | ✅ exit 0 | _—_ |

## 2. E2E 剧本帧（AC1/AC2）

| 帧 | PNG | 尺寸 | 元数据（trigger/composition） | theme 断言 |
|----|-----|:---:|------|:---:|
| 01_village_open | [链接](_docs/e2e-evidence/586/01_village_open.png_) | 1280x720 | _rig 驱动 BattleAssembler 出生态…_ | ✅ 6e7684 |
| 02_player_move | [链接](_docs/e2e-evidence/586/02_player_move.png_) | 1280x720 | _move_displacement_px ≥100…_ | ✅ 6e7684 |
| 03_first_parry | [链接](_docs/e2e-evidence/586/03_first_parry.png_) | 1280x720 | _parry_success 注入 + freeze…_ | ✅ 6e7684 |
| 04_clash | [链接](_docs/e2e-evidence/586/04_clash.png_) | 1280x720 | _judge.clash / rig_fallback（clash_source 标注）_ | ✅ 6e7684 |
| 05_execute_closeup | [链接](_docs/e2e-evidence/586/05_execute_closeup.png_) | 1280x720 | _崩解 + execute + S 级反馈…_ | ✅ 6e7684 |
| 06_fail_subtitle | [链接](_docs/e2e-evidence/586/06_fail_subtitle.png_) | 1280x720 | _玩家双死 → FAIL 态字幕淡入…_ | ✅ 6e7684 |

## 3. 用户裁决（AC4，唯一 taste 环节——agent 不评星）

| 帧 | ★(1-5) | 意见 | 打回目标（若 <4） |
|----|:---:|------|------|
| 01_village_open | | | #582（雪夜） |
| 02_player_move | | | #574（移动） |
| 03_first_parry | | | #579（反馈） |
| 04_clash | | | #579（反馈） |
| 05_execute_closeup | | | #580（处决） |
| 06_fail_subtitle | | | #585（字幕文案）+ #584（数值） |
| **平均** | **_N.N_** | | **≥4 通过 / <4 打回** |

## 4. 结论与回填（AC5）

- 平均分：_N.N_
- 通过与否：_通过 / 打回_
- 打回清单：_（如有 <4 帧，列帧名 + 目标 Issue）_

裁决意见回填命令（追加 acceptance 结论，逐条执行）：

```bash
# ① 雪夜（#582）
gh issue edit 582 --body-file _<回填文件1>_
# ② 移动（#574）
gh issue edit 574 --body-file _<回填文件2>_
# ③④ 反馈（#579）
gh issue edit 579 --body-file _<回填文件3>_
# ⑤ 处决（#580）
gh issue edit 580 --body-file _<回填文件4>_
# ⑥ 字幕文案 + 数值（#585 + #584）
gh issue edit 585 --body-file _<回填文件5>_
gh issue edit 584 --body-file _<回填文件6>_
```

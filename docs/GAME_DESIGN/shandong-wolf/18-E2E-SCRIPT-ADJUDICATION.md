# E2E 剧本验收 — e2e_script 6 帧情感弧剧本组 / rig 4→7 态 / 管线四修复（#586/#673）

> 落盘依据：PR **#673**（feat(586) E2E 剧本验收 — e2e_script 6 帧剧本组 + 管线修复 + rig 7 态
> + 报告模板，已 merge 2026-08-20）← DESIGN `docs/DESIGN/586-e2e-script-adjudication.md`
> （plan PR #670 已 merge）+ PRD `docs/PRD/586-e2e-script-adjudication.md`（research PR #669
> 已 merge）。
> 上游：#585 组装（assembly 组 4 态 rig = 本 issue 地基：BattleAssembler 公有成员驱动契约）、
> #579 反馈（freeze_time_stack 冻结效果帧先例）、#577/#580（judge.clash 信号 / 处决构图先例）、
> #582（theme_color 6e7684 断言口径）、#555（E2E 确定性纪律）。
> ✅ 代码状态：#673 已合并，`e2e_shots.json` e2e_script 组（6 帧文字契约）+ assembly 组
> match 收窄 / `e2e_main_assembly_capture.gd` 4→7 态 rig（CYCLE_SEQUENCE +
> CYCLE_DWELL_FRAMES + move_displacement_px + digit 1-7）/ `resolve_plan.py` 组级键提升 /
> `e2e_capture.gd` 数字 state 直比 + results.json 元数据透传 / `run-e2e-review.sh` 分辨率
> 从 project.godot 读取 / `analyze_bmp.py` --size 断言 / `docs/TEST/586-e2e-script-adjudication.md`
> 报告模板 全部落地 **main**（2026-08-20）。
> **taste 边界：6 帧 1-5 星裁决归用户（AC4），agent 不评星、不裁决失败文案**——E2E 是
> taste-draft 的裁决通道，机械化到截图为止（issue 红线「禁止自动化通过替代用户裁决」）。

## 1. 设计意图

**问题本质是「组件级 AC 截图素材已就位，但没有情感弧验收剧本」。** #574–#585 逐个交付了
7 组 29 帧组件级 rig 截图（stick_figure 12 态 / snow_night 1 帧 / hud 4 态 / battle_stage 3 构图
/ feedback 3 档 / execution 2 镜 / assembly 4 态），每帧都是「这个组件长这样，你裁决」的
组件证据，互不构成叙事。issue #586 要求把散落的证据**编排成 6 帧情感弧验收剧本**
（①雪夜村口冷静开场 → ②玩家移动 → ③首次弹反火花张力 → ④拼刀 → ⑤崩解+处决特写高潮 →
⑥失败字幕余韵），并补上三个验收机制：6 帧文字契约（AC1）、可 headless 运行的 1280x720
截图管线 + JSON 元数据（AC2）、用户 1-5 星裁决闭环 + 测试报告回填（AC3/AC4/AC5）。

设计哲学四条（与 PRD §4 推荐组合逐项对齐，方案 C 显式降级、无分歧）：

1. **确定性压倒一切**——E2E 是验收通道，flaky 管线会瘫痪裁决队列（#555 直接教训）。剧本帧
   全部经 rig 注入驱动（零 AI 随机），每个 shot 由 rig 的 per-state dwell 定长停留 + driver
   轮询捕获，杜绝「settle 中途切态」假帧；
2. **编排构图 ≠ 假帧**——帧是引擎真实渲染（如实提交，无人为后处理，issue 红线），构图是
   rig 编排的（PRD §4.1 Cons 的正面回应：E2 实验证据 + 报告说明）；
3. **机械与 taste 严格分离**——rig/JSON/管线/报告全部 mechanical；唯一 taste 环节（6 帧
   评星 + 失败文案定稿）留给用户；
4. **修复 E2E 管线潜在缺陷是本 issue 的隐含前置**——codebase 勘探发现 driver/resolve_plan
   有 3 个从未暴露的潜在缺陷（组级场景键不提升 / 数字 state 永不 ready / P5 分辨率参数与
   游戏 viewport 冲突），不修则 AC2「6 帧管线可跑」无法成立。

## 2. 架构决策

| 决策点 | 采纳方案 | 否决方案 | 否决理由 |
|--------|---------|---------|---------|
| 剧本载体 | 扩展 assembly rig 4→6 态直接对应 6 帧（方案 A，rig 实际扩为 7 态） | 方案 C（Movie Maker `--write-movie`） | Movie Maker 人工选帧与 AC1「自动剧本契约」冲突，降级为 headless 三档 Tier 3 实验对象，不进主路径 |
| 移动驱动 | rig 内部 `_move_drive`（吸收方案 B 的 press 注入能力） | 方案 B 零 driver 多 shot press 冲突 | 剧本组零 press 字段，规避 `_inject_press` 多 press 重复注入限制（设计 §3.3 已知限制） |
| 停留时序 | rig 内 per-state dwell（CYCLE_DWELL_FRAMES 定长） | 原 auto_cycle_frames 全局值 | 缺口 4：settle 中途切态假帧（02_parry_execute settle 60 > auto_cycle_frames 30 实测） |
| clash 帧 | E1 主路径：双实体同帧 attack → judge.clash 信号 | 直接注入 trigger_feedback | judge 真实链路构图更可信；失败 fallback 注入（构图一致，results.json 标注 clash_source） |
| 分辨率 | P5 从 project.godot 读取 viewport 生成 --resolution | 硬编码 720x1280（#383 mini-pong 竖屏遗留） | shandong-wolf viewport=1280x720，硬编码会竖窗渲染 → AC2「1280x720 PNG」失败 |

## 3. 核心定义

**rig 7 态（`e2e_main_assembly_capture.gd`；0-3 编号保留，向后兼容 assembly 组既有 shot）：**

```gdscript
enum { SPAWN_COMBAT = 0, PARRY = 1, FAIL_SUBTITLE = 2, AFTERGLOW = 3, MOVE = 4, CLASH = 5, EXECUTE = 6 }

## 剧本弧自动循环（对应 e2e_script 组 6 帧 + assembly 组余韵帧）
const CYCLE_SEQUENCE: Array = [SPAWN_COMBAT, MOVE, PARRY, CLASH, EXECUTE, FAIL_SUBTITLE, AFTERGLOW]

## 每态定长停留（帧）——settle 不跨态的关键（#586 缺口 4 修复）：dwell > 对应 shot settle_frames + 10 帧裕量
const CYCLE_DWELL_FRAMES: Dictionary = {
    SPAWN_COMBAT: 40, MOVE: 170, PARRY: 40, CLASH: 40, EXECUTE: 90,
    FAIL_SUBTITLE: 40, AFTERGLOW: 40,
}

var move_displacement_px: float = 0.0  # MOVE 态内每帧更新 = 玩家 global_position.x 相对进入态起点之差（AC2 位移证据）
var _move_drive: bool = false          # MOVE 态移动驱动开关（内部按住 game_move_right，smoke I1 同路径）
var _clash_source: String = ""         # results.json 标注 clash 驱动来源：judge / rig_fallback
```

**管线修复（缺口 1/2/3 是「修了才能跑」的前置，AC2 成立条件）：**

```python
# resolve_plan.py — 组级场景键提升（缺口 1：首个激活组胜出，与既有语义一致）
_GROUP_PROMOTED = ("mode", "path", "transcript", "state_trajectory", "fidelity",
                   "main_scene", "state_node", "state_property", "states")
```

```gdscript
# e2e_capture.gd _shot_ready — 数字 state 直比（缺口 2：既有 4 组数字态 shot 永不 ready）
if typeof(sv) == TYPE_INT or typeof(sv) == TYPE_FLOAT:
    return _current_state() == int(sv) and _require_ok(d) and _assert_text_ok(d)
# 字符串 state 仍走顶层 states 映射（12 态 stick 向后兼容）
```

**e2e_script 剧本组（`e2e_shots.json`，AC1 载体）：** 组级 `main_scene:
res://scenes/e2e_main_assembly_capture.tscn` + `state_node: /root/CaptureRig` +
`state_property: current_state`；match `[e2e_main_assembly_capture\.gd, main_battle\.gd,
e2e_main_assembly_capture\.tscn]`，与 assembly 组（match 收窄为 `[Main\.tscn,
battle_stage\.tscn]`）**互斥**——单次 diff 不会同时命中。每条 shot 含
`scene_description`/`trigger`/`composition` 三字段文字契约（新字段仅本组使用，schema 向后
兼容），resolve_plan.py 原样透传 shot 字典、driver 白名单透传到 results.json（缺口 5）。

## 4. 6 帧剧本契约（AC1）

| shot | state | settle | 场景描述（节选） | 触发 | 构图 |
|------|:---:|:---:|------|------|------|
| 01_village_open | 0 SPAWN_COMBAT | 30 | 雪夜村口开场：玩家与敌人出生对峙，三层雪幕飘落，冷月光染雪地（冷静开场） | rig 驱动 BattleAssembler 出生态（SPAWN_COMBAT），settle 对齐雪花飘落节奏 | 中景对称：玩家（左）与敌人（右）隔平台对峙，雪幕三层可见，无 UI 干扰 |
| 02_player_move | 4 MOVE | 120 | 玩家移动：火柴人 move 动画侧移，雪地位移（动作张力预备） | rig 进入 MOVE 态后内部按住 game_move_right ≥120 帧；require `move_displacement_px ≥ 100` 通过才可截图 | 侧移姿态，运动方向留白（玩家前方空间），雪幕为背景层次 |
| 03_first_parry | 1 PARRY | 20 | 首次弹反火花：苍白金火花爆于刀剑交点，顿帧+慢动作（动作张力） | rig 注入 parry_success 反馈（level A 火花 18 粒 + 90ms 顿帧 + 慢动作），freeze_time_stack 冻结效果帧 | 特写：火花在刀剑交点（_impact_pos），双刀交叉剪影，StageCamera 推近 |
| 04_clash | 5 CLASH | 20 | 拼刀：双刀相格，火花四溅，双方架势僵持（高潮前奏） | 双实体同帧 request_transition("attack") → judge.clash → reaction clash 反馈（B 级 6 粒 + 30ms 顿帧）；E1 失败则 fallback trigger_feedback（results.json 标注驱动来源） | 中近景：双刀相格于画面中心，火花对称溅射，双方身体前倾僵持 |
| 05_execute_closeup | 6 EXECUTE | 60 | 敌人崩解+处决特写：架势崩解剪影 + 处决斩落 + S 级处决反馈（高潮） | rig 崩解（take_stance_damage 999）→ request_transition("execute") → trigger_feedback("execute")（S 级 14 粒 + 150ms 顿帧 + 慢动作），freeze_time_stack 冻结效果帧；不调 execute_kill（防 AFTERGLOW 干扰） | 特写：处决斩落瞬间，敌人崩解剪影 + 苍白金火花 + 刀光，雪幕环绕（照 execution 组构图先例） |
| 06_fail_subtitle | 2 FAIL_SUBTITLE | 30 | 失败字幕：玩家双死，输入冻结，字幕淡入完成（余韵） | rig 驱动玩家双死 → BattleAssembler FAIL 态 → 字幕 Timer 到期 → 淡入 Tween 完成（照 #585 _drive_fail_subtitle，custom_step 同步推进） | 中景：雪夜村口 + 居中失败字幕（文案 ∈ FAIL_SUBTITLE_CANDIDATES，本 issue 不定稿），雪花持续 |

全部 6 帧 theme_color `6e7684`（Moonlight 染后 WorldBackdrop 像素断言，照 #582/#585 口径）。
**assembly 组同步修改：** match 收窄（与 e2e_script 互斥）；`02_parry_execute` state 1→6
（rig 语义拆分后 PARRY=1 只含弹反火花，「崩解+处决」语义由 EXECUTE=6 承接）；顶层 states
（12 态 stick 映射）不动。

## 5. 数据流（确定性核心）

```
e2e_shots.json（e2e_script 组 6 帧） → run-e2e-review.sh P5（gh pr diff --name-only → diff.txt）
  → resolve_plan.py（组激活：match 命中 rig/汇编脚本；组级键提升 + shot 字典原样透传）→ plan.json
  → godot --path shandong-wolf/ --display-driver <os> --rendering-driver opengl3
       --resolution 1280x720（从 project.godot 读取）--script capture.gd -- plan.json
  → e2e_capture.gd（15 帧 settle → autoplay tweaks(auto_cycle=true) → 轮询 CaptureRig.current_state；
     每 shot：_shot_ready 数字直比 + require 位移断言 → settle（dwell 裕量内）→ capture
     → results.json 元数据透传 + clash_source）
  → analyze_bmp.py L3（--min-colors 3 + --theme 6e7684 + --diff-with + --size 1280x720）
  → docs/TEST/586 报告（单测/smoke/E2E 三栏 + 6 帧 + 裁决表）→ 用户 6 帧 1-5 星裁决（AC4）
  → 意见回填对应 Issue acceptance（AC5）
rig 内部时序：SPAWN_COMBAT(40) → MOVE(170, _move_drive 位移证据) → PARRY(40, freeze)
  → CLASH(40, judge 主路径或 fallback) → EXECUTE(90, freeze) → FAIL_SUBTITLE(40)
  → AFTERGLOW(40) → 循环；进入任何态先 _release_move_drive() + _unfreeze_effects()
  （防串态 / 防冻结泄漏到后续 shot）
```

**headless 三档语义（AC2 落地形态）：** Tier 1 本地无人值守（display driver + opengl3 +
`--resolution`，现状）；Tier 2 CI 无窗口等价物（Linux `xvfb-run godot` / macOS display
driver）；Tier 3 Movie Maker 补充证据（`--write-movie out.png`，E3 实验验证后作「录制实机
证据」备选，不进主路径）。调研结论：Godot 4.x `--headless` = dummy DisplayServer **无渲染**
（截图黑图）；GUT/gdUnit4 不引入（自研 runner 已是成熟方案，迁移成本 > 收益）——结论已随
#673 说明（issue「开源优先」显式要求）。

## 6. 边界与错误处理（要点）

| # | 边界/错误场景 | 缓解 |
|---|------|------|
| 1 | clash 双窗口同帧注入失败（窗口错帧 → 无 clash 信号） | E1 主路径超时（60 帧）→ fallback trigger_feedback("clash")（构图一致），results.json 标注 clash_source（预期 judge ≥90%） |
| 2 | MOVE 位移不足（<100px，如输入未 bind） | require 不满足 → shot 永不 ready → deadline 失败 exit 1，**不产出假帧**（照 PRD §5.2 边界 2） |
| 3 | settle 跨态假帧（dwell < settle） | CYCLE_DWELL_FRAMES 每态 dwell = shot settle + ≥10 帧裕量；results.json 每帧 state 与 shot 期望一致 |
| 4 | 冻结泄漏（freeze_time_stack 遗留） | _drive_state 进入任何态先 _unfreeze_effects()；仅 PARRY/CLASH/EXECUTE 设 true |
| 5 | 失败字幕淡入时序（截到半透明字幕） | _drive_fail_subtitle 已 custom_step(2.0) 同步推进 Tween（#585 既有）；settle 30 ≥ 淡入时长 |
| 6 | 雪夜黑帧（渲染失败 = 全黑） | theme_color 6e7684 断言 + --min-colors 3 + --diff-with 防重复帧（既有 4 重防假帧） |
| 7 | PNG 尺寸非 1280x720（分辨率参数回归） | L3 --size 硬校验（缺口 3 修复），失败帧判 invalid 不进入裁决队列 |
| 8 | 剧本组与 assembly 组共存 | match 互斥；双命中极限场景 resolve_plan 按 shot name 去重 + implement 人工确认 |

## 7. 集成点与红线

- **只读消费，零修改**：17 个既有组件脚本 + `shandong-wolf/tests/` 18 套件 + smoke +
  check_compile 全部零改动（AC3 只跑通 + 报告）——rig 只经 BattleAssembler 公有成员
  （player/enemy_entity/judge/reaction/fail_label/_fail_subtitle_timer）与 `judge.clash` 信号 /
  `reaction.trigger_feedback` 事件驱动，发现缺口 → 回退对应 Issue 修复。
- **taste 边界**：6 帧 1-5 星裁决归用户；<4 星打回对应视觉 issue（①→#582 雪夜 / ②→#574
  移动 / ③④→#579 反馈 / ⑤→#580 处决 / ⑥→#585 字幕 + #584 数值）；失败文案定稿归 #584/用户。
- **报告回填**：裁决意见经 `gh issue edit` 追加对应 Issue acceptance（AC5，用户环节）。

## 8. 测试覆盖

- `tests/pipeline/test_e2e_resolve.py`：+2 用例锁定组级 main_scene/states 提升（缺口 1 回归，
  既有 TestDeadlinePassthrough 保持绿）。
- `tests/pipeline/test_e2e_runner.py`：管线 runner 回归（#673 随附）。
- 既有 18 套件 + smoke + check_compile 全绿基线零改动（AC3）。
- 设计场景（implement 交付）：A 组级键提升回归 / B 数字 state 与元数据 / C rig 7 态确定性
  （6 帧全产出 + MOVE 位移断言 + clash 驱动来源 + 冻结防泄漏 + dwell 定长）/ D 分辨率读取与
  --size 断言 / E 用户裁决闭环（流程验证，非自动化评星）。

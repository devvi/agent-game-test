# Design: [Test] 端到端验证（E2E 剧本 + 用户裁决）

> **Parent Issue:** #586
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4 推荐**逐项确认采纳，无分歧** —— 方案 A（扩展 assembly rig 4→6 态直接对应 6 剧本帧）为主；吸收方案 B 的 press 注入能力（MOVE 态移动驱动收敛为 rig 内部 `_move_drive`，零 driver 多 shot press 冲突）；方案 C（Movie Maker `--write-movie`）降级为 §E3 实验对象，不进主路径（理由同 PRD §4.3：人工选帧与 AC1 自动剧本契约冲突）
> **Reference PRD:** `docs/PRD/586-e2e-script-adjudication.md`（research PR #669 已合并 2026-08-20，commit 37153b9）
> **上游方案:** `docs/DESIGN/585-mvp-combat-loop-assembly.md`（assembly 组 4 态 rig = 本 issue 地基：BattleAssembler 公有成员驱动契约 + e2e_main_assembly_capture.gd 结构）；`docs/DESIGN/580-execution-system.md`（处决构图先例）；`docs/DESIGN/579-combat-feedback-system.md`（feedback rig 冻结效果帧模式 `freeze_time_stack` + 火花/顿帧矩阵）；`docs/DESIGN/577-parry-clash-stance-break.md`（judge.clash 信号 → reaction 链路）；`docs/DESIGN/582-snow-night-atmosphere.md`（theme_color 6e7684 像素断言口径）；`docs/DESIGN/555-e2e-pierce-flaky-seed.md`（E2E 确定性纪律）
> **所有权:** `content_ownership: mechanical`（E2E 剧本/管线/元数据/报告 = 机械工程；**用户对 6 帧的 1-5 星裁决是唯一 taste 环节，agent 禁止评星、禁止替用户裁决**——issue 明文「禁止自动化通过替代用户裁决」；失败文案定稿归 #584/用户）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 9（2 修改核心 + 3 管线/驱动 + 1 测试 + 1 模板 + 2 新建报告/JSON 组）+ 7 项实现子任务跨 4 子系统（rig / shot plan / 驱动与管线 / 报告与裁决）+ 3 个 Spike 实验 → **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，照 #585 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-586，branch `plan/586-e2e-script-adjudication`）；改动全部落在 E2E 侧（e2e_shots.json / e2e rig / framework/templates/e2e_capture.gd / scripts/e2e/resolve_plan.py / scripts/run-e2e-review.sh / scripts/e2e/analyze_bmp.py / tests/pipeline/test_e2e_resolve.py / docs/TEST/），与并行 implement 的 17 个战斗组件脚本零交集；constants.gd 零改动（本 issue 无新常量）
> **红线:** 只动 E2E 侧 9 文件（见 §3.1）；**绝不触碰** 17 个既有组件脚本（`combat_entity.gd` / `combat_judge.gd` / `enemy_ai.gd` / `hud.gd` / `reaction_controller.gd` / `revive_orchestrator.gd` / `execution_orchestrator.gd` / `player_controller.gd` / `stick_figure_controller.gd` / `atmosphere_controller.gd` / `input_controller.gd` / `combat_states.gd` / `combat_state_table.gd` / `state_machine.gd` / `stick_figure.gd` / `sword_arc.gd` / `main_battle.gd`）——rig 只经公有成员驱动；`project.godot`、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`shandong-wolf/tests/`（run_tests.gd / smoke_test.gd / check_compile.gd 及 18 套件）**不改**（AC3 只需「跑通 + 报告」，测试套件已是全绿基线）；**不写可运行测试文件**（只产出 DESIGN/TASKS 文档 + 测试用例描述）；**不评星、不裁决文案**；PR body 用 `Parent #586`（不带冒号）

---

## 1. 架构总览

**问题本质是「组件级 AC 截图素材已就位，但没有情感弧验收剧本」。** #574–#585 逐个交付了 7 组 29 帧组件级 rig 截图（stick_figure 12 态 / snow_night 1 帧 / hud 4 态 / battle_stage 3 构图 / feedback 3 档 / execution 2 镜 / assembly 4 态），每帧都是「这个组件长这样，你裁决」的组件证据，互不构成叙事。issue #586 要求把散落的证据**编排成 6 帧情感弧验收剧本**（①雪夜村口冷静开场 → ②玩家移动 → ③首次弹反火花张力 → ④拼刀 → ⑤崩解+处决特写高潮 → ⑥失败字幕余韵），并补上三个验收机制：6 帧文字契约（AC1）、可 headless 运行的 1280x720 截图管线 + JSON 元数据（AC2）、用户 1-5 星裁决闭环 + 测试报告回填（AC3/AC4/AC5）。

**设计哲学：确定性压倒一切；剧本帧 = 编排构图 + 真实渲染；裁决权只归用户。**

1. **确定性压倒一切**——E2E 是验收通道，flaky 管线会瘫痪裁决队列（#555 直接教训）。剧本帧全部经 rig 注入驱动（零 AI 随机），每个 shot 由 rig 的 per-state dwell 定长停留 + driver 轮询捕获，杜绝「settle 中途切态」假帧（现状 02_parry_execute settle 60 vs auto_cycle_frames 30 存在同款隐患，见 §1.2 缺口 4）；
2. **编排构图 ≠ 假帧**——帧是引擎真实渲染（如实提交，无人为后处理，issue 红线），构图是 rig 编排的（PRD §4.1 Cons 的正面回应：E2 实验证据 + 报告说明）；
3. **机械与 taste 严格分离**——rig/JSON/管线/报告全部 mechanical；唯一 taste 环节（6 帧评星 + 失败文案定稿）留给用户（issue 红线「禁止自动化通过替代用户裁决」）；
4. **修复 E2E 管线潜在缺陷是本 issue 的隐含前置**——codebase 勘探发现 driver/resolve_plan 有 3 个从未暴露的潜在缺陷（组级场景键不提升 / 数字 state 永不 ready / P5 分辨率参数与游戏 viewport 冲突），不修则 AC2「6 帧管线可跑」无法成立（详见 §1.2 缺口 1-3）。

```
★ Issue #586 本设计（shandong-wolf E2E 剧本验收 SW-014）
┌──────────────────────────────────────────────────────────────────────────┐
│ e2e_shots.json（修改）                                                      │
│  ├─ 新增 e2e_script 组（6 帧 × scene_description/trigger/composition 文字契约）│
│  ├─ assembly 组 match 收窄（与 e2e_script 互斥）+ 02_parry_execute→EXECUTE │
│  └─ 顶层 states 不动（12 态 stick 映射保留，向后兼容）                        │
│  resolve_plan.py（修改）: _GROUP_PROMOTED += main_scene/state_node/         │
│     state_property/states —— 组级场景覆盖真正生效（缺口 1 修复）              │
│  framework/templates/e2e_capture.gd（修改）: 数字 state 支持（缺口 2 修复）  │
│     + results.json 元数据透传（scene_description/trigger/composition）       │
│  scripts/run-e2e-review.sh（修改）: P5 分辨率从 project.godot 读取           │
│     （缺口 3 修复）+ headless 三档语义文档化                                  │
│  scripts/e2e/analyze_bmp.py（修改）: 可选 --size WxH 尺寸断言（AC2 1280x720）│
│  gdscripts/e2e_main_assembly_capture.gd（修改）: 4 态 → 7 态 rig            │
│     （+MOVE/+CLASH，PARRY/EXECUTE 拆分）+ per-state dwell + freeze 模式      │
│     + move_displacement_px 位移断言属性                                       │
│  docs/TEST/586-e2e-script-adjudication.md（新建）: 测试报告模板               │
│     （单测/smoke/E2E 三栏 + 6 帧 + 裁决表）                                   │
└──────────────────────────────────────────────────────────────────────────┘
事件源（只读消费，零修改）: BattleAssembler 公有成员（main_battle.gd:37-47 player/
  enemy/player_entity/enemy_entity/judge/hud/reaction/execution/revive/
  atmosphere/fail_label/_fail_subtitle_timer）+ judge.clash 信号（#577）
                        + reaction.trigger_feedback 事件（#579）
消费方（自动接管，零修改）: StickFigureController.consume_state（#574）/
  ReactionController 火花顿帧（#579）/ ExecutionOrchestrator 处决演出（#580）/
  Atmosphere 雪幕（#582）/ BattleAssembler FAIL 字幕（#585）
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的消费方式 |
|------|:---:|:---:|------|
| assembly 组 4 态 rig（`e2e_main_assembly_capture.gd`，196 行） | #585 | ✅ merged | 地基：扩展为 7 态；SPAWN_COMBAT/FAIL_SUBTITLE/AFTERGLOW 驱动逻辑原样保留 |
| BattleAssembler（`main_battle.gd`，342 行） | #585 | ✅ merged | 只读公有成员驱动（含 `judge` 公有引用，main_battle.gd:41） |
| 截图驱动（`framework/templates/e2e_capture.gd`，387 行） | #372/#480/#500 | ✅ merged | 修改：数字 state + 元数据透传（缺口 2/5 修复） |
| 剧本解析（`scripts/e2e/resolve_plan.py`） | #372 | ✅ merged | 修改：组级场景键提升（缺口 1 修复） |
| E2E 管线（`scripts/run-e2e-review.sh`，421 行） | #372 | ✅ merged | 修改：分辨率读取 + headless 语义（缺口 3/6 修复） |
| 反馈三档 rig（`e2e_feedback_capture.gd`） | #579 | ✅ merged | 冻结效果帧模式（`freeze_time_stack`）技术先例 |
| clash 反馈链路（judge.clash → reaction） | #577/#579 | ✅ merged | ④ 拼刀帧主驱动路径（E1 实验） |
| 处决演出（`execution_orchestrator.gd`） | #580 | ✅ merged | ⑤ 处决特写构图先例（execution 组 2 镜） |
| 测试套件 18 文件 + smoke + check_compile | #573-#585 | ✅ 全绿基线 | **不改**，AC3 只跑通 + 报告 |

### 1.2 核心缺口与修复决策（codebase 勘探发现，plan 新增）

| # | 缺口 | 证据（实测） | 影响 | 修复决策 |
|---|------|------|------|------|
| 1 | **resolve_plan.py 组级场景键不提升** | `_GROUP_PROMOTED = ("mode","path","transcript","state_trajectory","fidelity")`——hud/battle_stage/feedback/assembly 组的组级 `main_scene`/`state_node`/`state_property` 全部被静默忽略，resolved plan 恒用顶层 `e2e_stick_figure_capture.tscn` | e2e_script 组若照 assembly 组写法声明组级 main_scene，**6 帧将对着错误的 rig 截图** → AC2 直接失败 | `_GROUP_PROMOTED` 追加 `main_scene`/`state_node`/`state_property`/`states`（首个激活组胜出，与既有语义一致）；`tests/pipeline/test_e2e_resolve.py` 补 2 个用例锁定 |
| 2 | **数字 state 的 shot 永不 ready** | `e2e_capture.gd._shot_ready()` 先查 `states.has(d["state"])`；顶层 states 是字符串键（"IDLE".."DEAD"），GDScript 实测 `{"IDLE":0}.has(0) == false`（godot 4.7.1 实证） | assembly/battle_stage/feedback/hud 组全部数字态 shot 永远 pending → deadline 失败（因 L3 visual 默认跳过从未暴露） | `_shot_ready` 对数字/浮点 state 直接 `int()` 数值比较（字符串 state 走原 states 映射，12 态向后兼容）；顺带修复既有 4 组 |
| 3 | **P5 分辨率参数与游戏 viewport 冲突** | `run-e2e-review.sh` P5 硬编码 `--resolution 720x1280`（#383 mini-pong 竖屏遗留）；shandong-wolf `project.godot` viewport = **1280x720**（mini-pong = 720x1280） | shandong-wolf 截图会以竖窗渲染 → AC2「1280x720 PNG」不满足 | P5 从 `$WT/$SUBPROJECT/project.godot` 读取 `window/size/viewport_width/height` 生成 `--resolution WxH`（python inline，照 `default_subproject()` 同款）；`analyze_bmp.py` 加 `--size WxH` 断言，L3 每帧校验 PNG 尺寸 |
| 4 | **auto_cycle 与 settle 时长冲突（settle 中途切态假帧）** | rig `_cycle_frames_left` 每帧递减；02_parry_execute settle 60 > auto_cycle_frames 30 → settle 中途 rig 已切下一态，捕获帧可能是错误状态 | 剧本帧错位 → 裁决素材失真 | e2e_script 组改为 **rig 内 per-state dwell**（CYCLE_DWELL_FRAMES，每态定长停留 > settle_frames + 裕量），auto_cycle 照旧推进但每态停留可配置；settle 永不跨态 |
| 5 | **results.json 元数据不完整** | `_results.append({name,saved,frame,state})`——无 trigger/composition | AC2「JSON 元数据」缺口 | driver 捕获时透传 shot 的 `scene_description`/`trigger`/`composition` 字段（白名单，缺省跳过，与 #372 deadline_s 透传同构）；resolve_plan.py 已原样透传 shot 字典（test 锁定），零改动 |
| 6 | **headless 语义未定义** | `--headless` = dummy DisplayServer 无渲染（截图黑图）；e2e_capture.gd 头注释已实证须 display driver | AC2「可 headless 运行」表述悬空 | 三档语义文档化（§3.4）：Tier 1 本地无人值守 display driver / Tier 2 CI xvfb / Tier 3 Movie Maker 补充证据；调研结论（PRD §4.4）随 implement PR 说明 |
| 7 | **MOVE 位移断言无载体** | driver `require` 只支持数值属性（`float(v) >= min`），玩家位置是 Vector2 | ② 玩家移动帧无法断言真实位移 | rig 暴露数值属性 `move_displacement_px`（MOVE 态内每帧更新），shot 用 `require {node:/root/CaptureRig, prop:move_displacement_px, min:100}`（照 smoke I1 口径） |

> **设计决策依据**：缺口 1/2/3 是「修了才能跑」的前置（AC2 成立条件），缺口 4/5 是 AC1/AC2 的直接要求，缺口 6/7 是 AC2 的落地形态。全部为机械修复，不引入任何新机制。

## 2. 新组件 — 详细设计

### 2.1 e2e_script 剧本组（`shandong-wolf/e2e_shots.json` 新增组，AC1 载体）

**文件:** `shandong-wolf/e2e_shots.json`（修改，追加 `e2e_script` 组 + 收窄 `assembly` 组 match）

```jsonc
"e2e_script": {
  "_comment": "#586 端到端验证剧本组：6 帧情感弧（雪夜村口→移动→弹反火花→拼刀→处决特写→失败字幕），
                每条含 scene_description/trigger/composition 文字契约（AC1）；rig 驱动 BattleAssembler
                真实闭环（e2e_main_assembly_capture.tscn）；theme_color 6e7684 = Moonlight 染后
                WorldBackdrop 断言（照 #582/#585 口径）；dwell 由 rig CYCLE_DWELL_FRAMES 保证 settle 不跨态",
  "main_scene": "res://scenes/e2e_main_assembly_capture.tscn",
  "state_node": "/root/CaptureRig",
  "state_property": "current_state",
  "match": [
    "gdscripts/e2e_main_assembly_capture\\.gd",
    "gdscripts/main_battle\\.gd",
    "scenes/e2e_main_assembly_capture\\.tscn"
  ],
  "shots": [
    { "name": "01_village_open",  "state": 0, "settle_frames": 30, "theme_color": "6e7684",
      "scene_description": "雪夜村口开场：玩家与敌人出生对峙，三层雪幕飘落，冷月光染雪地（冷静开场）",
      "trigger": "rig 驱动 BattleAssembler 出生态（SPAWN_COMBAT），settle 对齐雪花飘落节奏",
      "composition": "中景对称构图：玩家（左）与敌人（右）隔平台对峙，雪幕三层可见，无 UI 干扰" },
    { "name": "02_player_move",   "state": 4, "settle_frames": 120, "theme_color": "6e7684",
      "require": { "node": "/root/CaptureRig", "prop": "move_displacement_px", "min": 100 },
      "scene_description": "玩家移动：火柴人 move 动画侧移，雪地位移（动作张力预备）",
      "trigger": "rig 进入 MOVE 态后内部按住 game_move_right ≥120 帧（smoke I1 口径），位移 ≥100px 断言通过才可截图",
      "composition": "侧移姿态，运动方向留白（玩家前方空间），雪幕为背景层次" },
    { "name": "03_first_parry",   "state": 1, "settle_frames": 20, "theme_color": "6e7684",
      "scene_description": "首次弹反火花：苍白金火花爆于刀剑交点，顿帧+慢动作（动作张力）",
      "trigger": "rig 注入 parry_success 反馈（level A 火花 18 粒 + 90ms 顿帧 + 慢动作），freeze_time_stack 冻结效果帧",
      "composition": "特写：火花在刀剑交点（_impact_pos），双刀交叉剪影，StageCamera 推近" },
    { "name": "04_clash",         "state": 5, "settle_frames": 20, "theme_color": "6e7684",
      "scene_description": "拼刀：双刀相格，火花四溅，双方架势僵持（高潮前奏）",
      "trigger": "rig 双实体同帧 request_transition(\"attack\") → judge.clash 信号 → reaction clash 反馈（B 级火花 6 粒 + 30ms 顿帧）；E1 失败则 fallback trigger_feedback(\"clash\")（results.json 标注驱动来源）",
      "composition": "中近景：双刀相格于画面中心，火花对称溅射，双方身体前倾僵持" },
    { "name": "05_execute_closeup", "state": 6, "settle_frames": 60, "theme_color": "6e7684",
      "scene_description": "敌人崩解+处决特写：架势崩解剪影 + 处决斩落 + S 级处决反馈（高潮）",
      "trigger": "rig 崩解（take_stance_damage → stance_break）→ 处决姿态（request_transition(\"execute\")）→ trigger_feedback(\"execute\")（S 级火花 14 粒 + 150ms 顿帧 + 慢动作），freeze_time_stack 冻结效果帧",
      "composition": "特写：处决斩落瞬间，敌人崩解剪影 + 苍白金火花 + 刀光，雪幕环绕（照 execution 组构图先例）" },
    { "name": "06_fail_subtitle", "state": 2, "settle_frames": 30, "theme_color": "6e7684",
      "scene_description": "失败字幕：玩家双死，输入冻结，字幕淡入完成（余韵）",
      "trigger": "rig 驱动玩家双死 → BattleAssembler FAIL 态 → 字幕 Timer 到期 → 淡入 Tween 完成（照 #585 _drive_fail_subtitle）",
      "composition": "中景：雪夜村口 + 居中失败字幕（文案 ∈ FAIL_SUBTITLE_CANDIDATES，本 issue 不定稿），雪花持续" }
  ]
}
```

**组级 schema 说明（向后兼容，AC1 验收口径）:**
- 新字段 `scene_description` / `trigger` / `composition` 仅 e2e_script 组使用；resolve_plan.py 原样透传 shot 字典（test_e2e_resolve.py 已锁定未知字段透传），driver 白名单透传到 results.json——既有 7 组零字段变化，**schema 向后兼容**；
- `states` 键：e2e_script 组不声明（依赖顶层 12 态 stick 映射 + 缺口 2 修复后的数字 state 直比）；
- **与 assembly 组互斥**（PRD §5.2 边界 6）：e2e_script match 含 rig/汇编脚本；assembly 组 match 收窄为 `["scenes/Main\\.tscn", "scenes/battle_stage\\.tscn"]`——两组 pattern 不相交，单次 diff 不会同时命中（resolve_plan.py 按 shot name 去重，双命中极限场景由 implement PR 人工确认）。

**assembly 组修改（同一文件）:**
- match 收窄（见上）；`02_parry_execute` 的 `state: 1` → `state: 6`（EXECUTE——rig 语义拆分后 PARRY=1 只含弹反火花，原「崩解+处决」语义由 EXECUTE=6 承接）；01/03/04 不变；`_comment` 更新注明「组件级证据，剧本验收见 e2e_script 组」。

### 2.2 E2E rig 7 态扩展（`shandong-wolf/gdscripts/e2e_main_assembly_capture.gd`）

**文件:** `shandong-wolf/gdscripts/e2e_main_assembly_capture.gd`（修改，4 态 → 7 态）

**Node structure:** 不变（CaptureRig 根 + instance Main.tscn），只改脚本内部状态机。

**状态枚举（0-3 编号保留，向后兼容 assembly 组既有 shot）：**

```gdscript
enum { SPAWN_COMBAT = 0, PARRY = 1, FAIL_SUBTITLE = 2, AFTERGLOW = 3, MOVE = 4, CLASH = 5, EXECUTE = 6 }

## 剧本弧自动循环（对应 e2e_script 组 6 帧 + assembly 组余韵帧）
const CYCLE_SEQUENCE: Array = [SPAWN_COMBAT, MOVE, PARRY, CLASH, EXECUTE, FAIL_SUBTITLE, AFTERGLOW]

## 每态定长停留（帧）——settle 不跨态的关键（缺口 4 修复）：
##   dwell > 对应 shot settle_frames + 10 帧裕量
const CYCLE_DWELL_FRAMES: Dictionary = {
    SPAWN_COMBAT: 40, MOVE: 170, PARRY: 40, CLASH: 40, EXECUTE: 90,
    FAIL_SUBTITLE: 40, AFTERGLOW: 40,
}
```

**新增状态属性:**
- `move_displacement_px: float = 0.0`（公有，MOVE 态内每帧更新 = 玩家 `global_position.x` 相对进入 MOVE 态时起点之差；供 shot `require` 断言，AC2 位移证据）
- `_move_drive: bool = false`（内部，MOVE 态移动驱动开关）
- `_move_start_x: float = 0.0`
- `_dwell_frames_left: int = 0`（替代原 `_cycle_frames_left` 的定长逻辑）

**Key Methods:**

```gdscript
func _drive_state(state: int) -> void:
    current_state = state
    _dwell_frames_left = int(CYCLE_DWELL_FRAMES.get(state, 40))
    if _assembler == null:
        return
    _release_move_drive()              # 离开 MOVE 态必释放（防串态）
    _unfreeze_effects()                # 离开演出态必恢复时间栈
    match state:
        SPAWN_COMBAT:
            _framing(Vector2(670.0, 480.0))
        MOVE:
            _framing(Vector2(670.0, 480.0))
            _start_move_drive()        # 内部按住 game_move_right + 记录起点
        PARRY:
            _framing(Vector2(670.0, 480.0))   # 推近构图（特写）见 §2.2 注
            _drive_first_parry()
        CLASH:
            _framing(Vector2(670.0, 480.0))
            _drive_clash()
        EXECUTE:
            _framing(Vector2(670.0, 480.0))   # 特写推近
            _drive_execute_closeup()
        FAIL_SUBTITLE:
            _framing(Vector2(670.0, 480.0))
            _drive_fail_subtitle()     # 原实现原样保留
        AFTERGLOW:
            _framing(Vector2(1000.0, 360.0))
            _drive_afterglow()         # 原实现原样保留

func _process(_delta: float) -> void:
    if auto_cycle:
        _dwell_frames_left -= 1
        if _dwell_frames_left <= 0:
            _advance_cycle()
    if _move_drive and current_state == MOVE:
        # 位移证据更新（require 轮询目标）
        move_displacement_px = _player_x() - _move_start_x
```

**新态驱动逻辑（全部经公有成员，零组件改动）:**

```gdscript
func _start_move_drive() -> void:
    ## ② 玩家移动：内部按住 game_move_right（smoke I1 同路径，InputController 已 bind）
    var p = _assembler.player
    if p == null: return
    _move_start_x = p.global_position.x
    move_displacement_px = 0.0
    _move_drive = true
    Input.action_press("game_move_right")

func _release_move_drive() -> void:
    if _move_drive:
        Input.action_release("game_move_right")
        _move_drive = false

func _drive_first_parry() -> void:
    ## ③ 首次弹反火花：注入 parry_success 反馈（level A 火花/顿帧/慢动作），
    ##    冻结时间栈锁定效果帧（feedback rig 同款技术，reaction_controller.freeze_time_stack）
    var a = _assembler
    if a.reaction == null: return
    if a.reaction.get("freeze_time_stack") != true:
        a.reaction.set("freeze_time_stack", true)   # 冻结 hit-stop/火花供截图
    a.reaction.trigger_feedback("parry_success", {
        "position": _impact_pos(), "normal": Vector2(0.0, -1.0),
        "target_entity": a.enemy_entity, "attacker_entity": a.player_entity,
        "source": "rig",
    })

func _drive_clash() -> void:
    ## ④ 拼刀：主路径 = 双实体同帧进 attack → judge 窗口登记 → clash 信号 →
    ##    reaction clash 反馈（E1 实验对象）；fallback = 直接注入（构图一致）
    var a = _assembler
    if a.reaction == null: return
    if a.reaction.get("freeze_time_stack") != true:
        a.reaction.set("freeze_time_stack", true)
    if _drive_clash_via_judge():          # E1 主路径（judge.clash 信号驱动）
        _clash_source = "judge"           # results.json 驱动来源标注
    else:
        a.reaction.trigger_feedback("clash", {   # fallback：构图一致，来源不同
            "position": _impact_pos(), "normal": Vector2(0.0, -1.0),
            "target_entity": a.enemy_entity, "attacker_entity": a.player_entity,
            "source": "rig_fallback",
        })
        _clash_source = "rig_fallback"

func _drive_clash_via_judge() -> bool:
    ## E1 实验主路径：双实体同帧 request_transition("attack")，推进 N 帧监听 judge.clash。
    ## 信号监听用 rig 连接（judge.clash.connect）或轮询 reaction 状态，实现细节由
    ## implement 依 E1 结果定；预期成功率 ≥90%，失败走 fallback（帧内容一致）。
    var a = _assembler
    if a.judge == null or a.player_entity == null or a.enemy_entity == null:
        return false
    if not a.judge.has_signal("clash"):
        return false
    a.player_entity.request_transition("attack")
    a.enemy_entity.request_transition("attack")
    # …推进帧循环，clash 信号到达即返回 true；超时（如 60 帧）返回 false…

func _drive_execute_closeup() -> void:
    ## ⑤ 崩解 + 处决特写：承接原 _drive_parry_execute 逻辑（崩解 → 处决姿态 →
    ##    S 级处决反馈），StageCamera 推近特写构图；不调 execute_kill（防 died(true)
    ##    触发 assembler AFTERGLOW 干扰本态，原稳定性裁决保留）
    var a = _assembler
    var enemy_entity = a.enemy_entity
    if enemy_entity == null: return
    enemy_entity.facing = -1
    enemy_entity.take_stance_damage(999.0)
    if enemy_entity.state_name != "execute":
        enemy_entity.request_transition("execute")
    if a.reaction != null:
        if a.reaction.get("freeze_time_stack") != true:
            a.reaction.set("freeze_time_stack", true)
        a.reaction.trigger_feedback("execute", {
            "position": _impact_pos(), "normal": Vector2(0.0, -1.0),
            "target_entity": enemy_entity, "attacker_entity": a.player_entity,
            "source": "rig",
        })

func _unfreeze_effects() -> void:
    ## 离开演出态恢复时间栈（freeze_time_stack = false），防冻结泄漏到后续 shot
    var a = _assembler
    if a != null and a.reaction != null and a.reaction.get("freeze_time_stack") == true:
        a.reaction.set("freeze_time_stack", false)
```

**构图（特写推近）:** StageCamera 为 Camera2D——特写态（PARRY/EXECUTE）在 `_framing` 基础上设 `_camera.zoom = Vector2(1.5, 1.5)` 并 `position` 拉近刀剑交点（`_impact_pos()`），离开特写态恢复 `zoom = Vector2.ONE`；若 StageCamera 无 zoom 先例（implement 确认），退化为仅 position 构图（构图文字契约不变，见 §2.1）。

**digit 键扩展（人工/脚本注入备选，沿用 #574/#579 模式）:** `_unhandled_input` 从 KEY_1-4 扩到 KEY_1-7（1→SPAWN_COMBAT / 2→PARRY / 3→FAIL_SUBTITLE / 4→AFTERGLOW / 5→MOVE / 6→CLASH / 7→EXECUTE）。剧本组 shot **不依赖** digit 键（auto_cycle + dwell 驱动），键位仅供人工调试。

**auto_cycle 语义变更（缺口 4 修复）:** `auto_cycle_frames` 仍为导出变量但**仅作兜底初值**；实际停留由 `CYCLE_DWELL_FRAMES[current_state]` 决定（进入态时 `_dwell_frames_left = CYCLE_DWELL_FRAMES[state]`）。e2e_script 组 autoplay.tweaks 照旧开启 `auto_cycle=true`（无需 auto_cycle_frames 对齐——dwell 表已含裕量）。

### 2.3 测试报告模板（`docs/TEST/586-e2e-script-adjudication.md`，implement 产出）

**文件:** `docs/TEST/586-e2e-script-adjudication.md`（新建目录 + 模板，AC3/AC5 载体）

模板四栏：

```markdown
# E2E 剧本执行报告 — #586（端到端验证）

> 运行日期 / 引擎版本（godot 4.7.1）/ 分支 commit / 运行人

## 1. 自动化测试（AC3）
| 套件 | 结果 | 计数 |
|------|:---:|------|
| L0 compile（check_compile.gd） | ✅ exit 0 | 55/55 |
| L1 单测（run_tests.gd，18 套件） | ✅ exit 0 | N/N passed |
| smoke（smoke_test.gd，含 AC4 闭环） | ✅ exit 0 | — |

## 2. E2E 剧本帧（AC1/AC2）
| 帧 | PNG | 尺寸 | 元数据（trigger/composition） | theme 断言 |
|----|-----|:---:|------|:---:|
| 01_village_open | [链接](...) | 1280x720 | … | ✅ 6e7684 |
| …（6 帧全列） | | | | |

## 3. 用户裁决（AC4，唯一 taste 环节——agent 不评星）
| 帧 | ★(1-5) | 意见 | 打回目标（若 <4） |
|----|:---:|------|------|
| 01_village_open | | | #582（雪夜） |
| … | | | |
| **平均** | **≥4 通过 / <4 打回** | | |

## 4. 结论与回填（AC5）
- 平均分 / 通过与否 / 打回清单
- 裁决意见回填：`gh issue edit <对应Issue> --body-file ...`（追加 acceptance 结论）
```

**裁决工作流（AC4/AC5，用户环节，agent 只准备素材与报告）:**
1. 6 帧 PNG（1280x720，真实渲染帧）+ 报告提交用户；
2. 用户每帧 1-5 星 + 意见；平均 ≥4 → 通过；<4 → 打回对应视觉 issue（帧→issue 映射：① #582 雪夜 / ② #574 移动 / ③④ #579 反馈 / ⑤ #580 处决 / ⑥ #585 字幕文案 + #584 数值）；
3. 裁决意见回填对应 Issue acceptance（`gh issue edit` 追加），打回则附差异帧对比（下轮重跑时）；
4. agent 全程不评星、不裁决文案、不替用户定稿（issue 红线）。

## 3. 既有组件修改

### 3.1 修改文件清单

| 文件 | 变更性质 | 内容 | 目的 |
|------|:---:|------|------|
| `shandong-wolf/e2e_shots.json` | 修改 | + e2e_script 组（6 帧文字契约）；assembly 组 match 收窄 + 02_parry_execute→state 6；顶层 states 不动 | AC1 剧本契约 + 组互斥（§2.1） |
| `shandong-wolf/gdscripts/e2e_main_assembly_capture.gd` | 修改 | 4 态 → 7 态 + dwell 表 + freeze 模式 + move_displacement_px + digit 1-7 | 6 帧确定性驱动（§2.2） |
| `scripts/e2e/resolve_plan.py` | 修改 | `_GROUP_PROMOTED` += `main_scene`/`state_node`/`state_property`/`states` | 缺口 1 修复（组级场景生效） |
| `tests/pipeline/test_e2e_resolve.py` | 修改 | + 2 用例：组级 main_scene 提升 / 组级 states 提升 | 锁定缺口 1 修复 |
| `framework/templates/e2e_capture.gd` | 修改 | `_shot_ready` 数字 state 直比 + results.json 元数据透传 | 缺口 2/5 修复（AC2） |
| `scripts/run-e2e-review.sh` | 修改 | P5 分辨率从 project.godot 读取 + headless 三档语义注释 + PNG 尺寸断言调用 | 缺口 3/6 修复（AC2） |
| `scripts/e2e/analyze_bmp.py` | 修改 | 可选 `--size WxH` 参数断言 PNG 尺寸 | AC2 1280x720 校验 |
| `docs/TEST/586-e2e-script-adjudication.md` | 新建 | 测试报告模板（§2.3） | AC3/AC5 载体 |
| `framework/templates/e2e_shots.json` | 修改（可选） | 模板 shot 示例补 scene_description/trigger/composition 注释字段 | 未来游戏复用（PRD §3.4） |

### 3.2 关键修改伪代码

**resolve_plan.py（缺口 1 修复）：**

```python
# 组级键提升集合：first activated group wins（与既有语义一致）
_GROUP_PROMOTED = (
    "mode", "path", "transcript", "state_trajectory", "fidelity",
    "main_scene", "state_node", "state_property", "states",   # ← 新增
)
```

**e2e_capture.gd `_shot_ready`（缺口 2 修复）：**

```gdscript
func _shot_ready(d: Dictionary) -> bool:
    if d.has("state"):
        var sv = d["state"]
        # 数字 state 直比（修复 #586 缺口 2：既有 4 组数字态 shot 永不 ready）
        if typeof(sv) == TYPE_INT or typeof(sv) == TYPE_FLOAT:
            return _current_state() == int(sv) and _require_ok(d) and _assert_text_ok(d)
        # 字符串 state 走 states 映射（12 态 stick 向后兼容）
        var states: Dictionary = _plan.get("states", {})
        if not states.has(sv):
            return false
        var want: int = int(states[sv])
        if _current_state() == want and _require_ok(d) and _assert_text_ok(d):
            return true
        return false
    if d.has("at_frame"):
        return _frame >= int(d.get("at_frame", 0))
    return false
```

**e2e_capture.gd results.json 元数据透传（缺口 5 修复）：**

```gdscript
# 捕获成功后：
var entry: Dictionary = {"name": shot_name, "saved": saved, "frame": _frame,
                         "state": _current_state_name()}
for k in ["scene_description", "trigger", "composition"]:
    if d.has(k):
        entry[k] = d[k]          # AC2 元数据透传（resolve_plan.py 已原样透传 shot 字典）
_results.append(entry)
```

**run-e2e-review.sh P5 分辨率（缺口 3 修复，照 `default_subproject()` 同款 inline python）：**

```bash
# 从项目 project.godot 读取 viewport（shandong-wolf=1280x720 / mini-pong=720x1280）
VIEWPORT="$(python3 - "$WT/$SUBPROJECT/project.godot" <<'PY' || echo 1280x720
import re, sys
txt = open(sys.argv[1], encoding="utf-8").read()
w = re.search(r"window/size/viewport_width=(\d+)", txt)
h = re.search(r"window/size/viewport_height=(\d+)", txt)
print(f"{w.group(1)}x{h.group(1)}" if w and h else "1280x720")
PY
)"
# 替换原硬编码 --resolution 720x1280
... "$GODOT" --path "$SUBPROJECT/" --display-driver macos --rendering-driver opengl3 \
    --resolution "$VIEWPORT" --script "$OUT/capture.gd" -- "$OUT/plan.json" ...
# L3 每帧尺寸断言（照 theme 断言同款注入）
args+=(--size "$VIEWPORT")
```

**analyze_bmp.py `--size WxH`：**

```python
# argparse 加 --size（可选，格式 "WxH"）：
#   解码后 if (width, height) != (W, H): 断言失败（AC2 1280x720 硬校验）
# 不传则跳过（向后兼容既有调用）
```

### 3.3 影响分析

- **直接受影响**：见 §3.1 九文件；其中 `resolve_plan.py`/`e2e_capture.gd`/`run-e2e-review.sh`/`analyze_bmp.py` 是 framework 层共享组件——修改对 mini-pong 的既有组**向后兼容**（数字 state 直比使 mini-pong 字符串态不受影响；分辨率读取使 mini-pong 恢复 720x1280 正确竖屏；组级键提升仅当组声明这些键时才生效）。
- **间接影响**：`shandong-wolf/tests/` 18 套件 + smoke + check_compile **零改动**（AC3 只跑通 + 报告）；`main_battle.gd` / `reaction_controller.gd` / `combat_judge.gd` 等 17 组件 **零改动**（rig 只读消费）。
- **已知限制（既有，不在本 issue 范围）**：`e2e_capture.gd` 的 `_inject_press` 对**多 shot 同时带 press 字段**会在每帧重复注入全部 press（driver 设计假定单 press-shot，mini-pong 先例 01_title 唯一）。本设计规避：剧本组**零 press 字段**（移动由 rig 内部 `_move_drive` 驱动），不触发该限制。未来如需真机 press 剧本，另行 issue。

### 3.4 headless 三档语义（AC2 落地形态，缺口 6）

| Tier | 形态 | 命令/环境 | 适用 |
|:---:|------|------|------|
| 1 | 本地无人值守 | `godot --display-driver <os> --rendering-driver opengl3 --resolution <WxH> --script capture.gd`（现状 + 分辨率修复） | 开发者本地、验收截图 |
| 2 | CI 无窗口等价物 | Linux `xvfb-run godot ...` / macOS display driver（CI 若有窗口环境） | pipeline-tests.yml 可选挂载 |
| 3 | Movie Maker 补充证据 | `--write-movie out.png`（Godot 原生 PNG 序列） | E3 实验验证后作「录制实机证据」备选，不进主路径 |

> 调研结论（PRD §4.4 实证）：Godot 4.x `--headless` = dummy DisplayServer **无渲染**（截图黑图）；GUT/gdUnit4 不引入（自研 runner 已是成熟方案，迁移成本 > 收益）；Movie Maker 作为补充录制路径。**该结论随 implement PR 说明（issue「开源优先」显式要求）。**

## 4. 数据流

### Flow 1: 剧本帧 → 用户裁决（正常路径）

```
e2e_shots.json（e2e_script 组 6 帧，含文字契约）
    │  run-e2e-review.sh P5: gh pr diff --name-only → diff.txt
    ▼
resolve_plan.py（组激活: e2e_script match 命中 rig/汇编脚本 diff；组级
  main_scene/state_node/state_property 提升 + shot 字典原样透传）
    ▼  plan.json（6 shots，数字 state + require + 文字契约字段）
run-e2e-review.sh: godot --path shandong-wolf/ --display-driver macos \
    --rendering-driver opengl3 --resolution 1280x720 --script capture.gd -- plan.json
    ▼
e2e_capture.gd（15 帧 settle → autoplay tweaks(auto_cycle=true) →
  轮询 CaptureRig.current_state；每 shot: ready(数字 state 直比 + require 位移断言)
  → settle(dwell 裕量内) → capture → 元数据透传）
    ├── shots/01_village_open.png … 06_fail_subtitle.png（1280x720 如实帧）
    └── results.json（name/saved/frame/state + trigger/composition + clash 驱动来源）
    ▼
L3 断言（analyze_bmp.py: --min-colors 3 + --theme 6e7684 + --diff-with + --size 1280x720）
    ▼
测试报告 docs/TEST/586-*.md（单测/smoke/E2E 三栏 + 6 帧 + 裁决表）
    ▼
用户裁决（6 帧 1-5 星 + 实机手感侧证）→ 平均 ≥4 通过 / <4 打回 → 意见回填（AC5）
```

### Flow 2: 剧本帧捕获的 rig 内部时序（确定性核心）

```
auto_cycle=true: rig 依 CYCLE_SEQUENCE 推进，每态停留 CYCLE_DWELL_FRAMES[state] 帧
  SPAWN_COMBAT(dwell 40) → MOVE(dwell 170, 内部按住 game_move_right,
      move_displacement_px 每帧更新) → PARRY(dwell 40, 注入 parry_success + 冻结)
  → CLASH(dwell 40, judge 双窗口或注入 + 冻结) → EXECUTE(dwell 90, 崩解+处决+冻结)
  → FAIL_SUBTITLE(dwell 40, 双死字幕) → AFTERGLOW(dwell 40) → 循环
driver 每 shot:  state 匹配（数字直比）→ require（位移 ≥100px）→ settle(≤ dwell-10)
  → capture → 下一 shot 等待 rig 进入下一态
```

### Flow 3: clash 失败路径（E1 fallback）

```
_drive_clash_via_judge() 超时（双窗口同帧注入未触发 judge.clash，如窗口错帧）
    → trigger_feedback("clash", {source: "rig_fallback"})   # 构图一致，来源不同
    → results.json 该帧标注 clash_source: rig_fallback（E1 报告记录成功率）
    → 帧内容与 judge 路径相同（同一 FEEDBACK_MATRIX["clash"] 参数包）
```

## 5. 边界条件与错误处理

| # | 边界/错误场景 | 缓解（mitigation） |
|---|------|------|
| 1 | **clash 双窗口同帧注入失败**（窗口错帧 → 无 clash 信号） | E1 主路径超时（60 帧）→ fallback `trigger_feedback("clash")`（构图一致），results.json 标注 `clash_source`；E1 报告成功率（预期 ≥90%，fallback 100%） |
| 2 | **MOVE 位移不足**（<100px，如输入未 bind） | `require move_displacement_px ≥100` 不满足 → shot 永不 ready → deadline 失败（exit 1），**不产出假帧**（照 PRD §5.2 边界 2）；报告标注该帧失败，不进入裁决队列 |
| 3 | **settle 跨态假帧**（dwell < settle） | CYCLE_DWELL_FRAMES 每态 dwell = shot settle + ≥10 帧裕量（§2.2 表）；实现后跑全组验证：results.json 每帧 state 与 shot 期望一致 |
| 4 | **冻结泄漏**（freeze_time_stack 遗留到后续 shot） | `_drive_state` 进入任何态先 `_unfreeze_effects()`；仅 PARRY/CLASH/EXECUTE 设 true |
| 5 | **失败字幕淡入时序**（截到半透明字幕） | `_drive_fail_subtitle` 已 `custom_step(2.0)` 同步推进 Tween（#585 既有）；settle 30 ≥ 淡入时长 |
| 6 | **雪夜黑帧**（渲染失败 = 全黑） | theme_color 6e7684 断言（照 #582/#585 口径）+ `--min-colors 3` + `--diff-with` 防重复帧（既有 4 重防假帧） |
| 7 | **headless 误用**（`--headless` 直截 = 空渲染） | 管线显式选 display driver，不静默 fallback（Tier 表 §3.4）；文档写入 run-e2e-review.sh 头注释 |
| 8 | **剧本组与 assembly 组共存** | match 互斥（§2.1）；双命中极限场景 resolve_plan 按 shot name 去重 + implement PR 人工确认 |
| 9 | **PNG 尺寸非 1280x720**（分辨率参数回归） | L3 `--size` 断言硬校验（缺口 3 修复），失败帧判 invalid 不进入裁决队列 |
| 10 | **管线超时/死锁** | `max_wall_seconds` 全局兜底 + shot 级 `deadline_s`（既有）；任一帧 deadline 失败 → exit 1 + 报告标注原因（照 #555 flaky 排查先例） |

## 6. 集成点

> **Status 约定:** ⬜ = pending（implement 接线后更新）; ✅ = 已连接（implement agent 验证）。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| rig 驱动 BattleAssembler | e2e_main_assembly_capture.gd | #585 | 公有成员读（player/enemy_entity/judge/reaction/fail_label/_fail_subtitle_timer），零修改 | ⬜ pending |
| clash 信号链 | rig → judge.clash → reaction | #577/#579 | `_drive_clash_via_judge()` 连接 judge.clash（E1 主路径） | ⬜ pending |
| 反馈注入 | rig → reaction.trigger_feedback | #579 | parry_success / clash / execute + freeze_time_stack 冻结 | ⬜ pending |
| 移动驱动 | rig → Input.action_press("game_move_right") | #573 | `_move_drive`（smoke I1 同路径，InputController 已 bind） | ⬜ pending |
| 剧本解析 | resolve_plan.py 组级键提升 | #372 | `_GROUP_PROMOTED` 扩展 + test_e2e_resolve 锁定 | ⬜ pending |
| 截图驱动 | e2e_capture.gd 数字 state + 元数据 | #372/#500 | `_shot_ready` 直比 + results.json 透传 | ⬜ pending |
| 视觉断言 | analyze_bmp.py --size | #466/#517 | L3 尺寸硬校验（AC2） | ⬜ pending |
| 报告回填 | docs/TEST/586 → issue acceptance | #582/#579/#580/#584… | 裁决后 `gh issue edit` 追加 acceptance（AC5） | ⬜ pending（用户环节后） |

## 7. 实现阶段

| Phase | 优先级 | 组件 | 估算 | 依赖 |
|:-----:|:------:|------|:----:|------|
| Phase 0 | P0 | Spike 实验（PRD §7）：E1 clash 帧确定性（双窗口同帧 vs fallback 成功率）/ E2 MOVE press 稳定性（rig 内按住位移 ≥100px）/ E3 Movie Maker 保真对比 | 0.5d | — |
| Phase 1 | P0 | resolve_plan.py 组级键提升 + test_e2e_resolve.py 2 用例（缺口 1） | 0.25d | — |
| Phase 2 | P0 | e2e_capture.gd 数字 state 直比 + 元数据透传（缺口 2/5） | 0.25d | — |
| Phase 3 | P0 | run-e2e-review.sh 分辨率读取 + analyze_bmp.py --size + headless 三档注释（缺口 3/6） | 0.5d | — |
| Phase 4 | P0 | rig 4→7 态 + dwell 表 + freeze 模式 + move_displacement_px + digit 1-7（§2.2） | 1d | Phase 0 E1/E2 |
| Phase 5 | P0 | e2e_shots.json e2e_script 组 6 帧文字契约 + assembly 组收窄/态更新（§2.1） | 0.5d | Phase 4 |
| Phase 6 | P1 | docs/TEST/586 报告模板 + 全量验证（单测/smoke/E2E 6 帧）+ 截图附 PR | 0.5d | Phase 4-5 |
| Phase 7 | P1 | 用户裁决提交 + 意见回填（AC4/AC5，用户环节） | 0.5d | Phase 6 |

## 8. 测试用例描述

> **约定：** 只描述测试场景，不写可运行测试代码（implement agent 交付）。headless 模式：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 与 `tests/smoke_test.gd`（AC3 两项 exit 0）；E2E 截图：`scripts/run-e2e-review.sh <PR> --subproject shandong-wolf --with-visual`（L3 视觉层）。场景映射 PRD §7 实验 E1-E3 + issue AC1-AC5。

### Scenario A: resolve_plan.py 组级场景键提升（缺口 1 回归）
- Test A1（组级 main_scene 提升）：含 `main_scene` 的组激活后，resolved plan 的 `main_scene` == 组值（first activated group wins）
- Test A2（组级 states 提升）：组声明 `states` 字典 → resolved plan 携带组 states；未声明组不引入该键（向后兼容）
- Test A3（既有行为不变）：shot 字典原样透传（deadline_s/scene_description/trigger/composition 不丢失）——既有 TestDeadlinePassthrough 保持绿

### Scenario B: e2e_capture.gd 数字 state 与元数据（缺口 2/5 回归）
- Test B1（数字 state ready）：plan states 为字符串键 + shot state 为数字 → shot 可 ready（数值直比）
- Test B2（字符串 state 兼容）：12 态 stick shot（state "MOVE" 等字符串）仍走 states 映射 ready
- Test B3（require 数值断言）：`move_displacement_px ≥ 100` 未达标不 ready、达标即 ready
- Test B4（元数据透传）：捕获成功的 shot 在 results.json 含 scene_description/trigger/composition；未声明字段的 shot 不新增键
- Test B5（at_frame 兼容）：snow_night at_frame:30 shot 行为不变

### Scenario C: rig 7 态确定性（AC1/AC2 核心，PRD §7 E1/E2）
- Test C1（6 帧全产出）：e2e_script 组跑通产出 6 张 PNG，均 1280x720（--size 断言），results.json 每帧 state 与 shot 期望一致（无 settle 跨态）
- Test C2（MOVE 位移）：02_player_move 的 results.json require 通过（move_displacement_px ≥100）；该帧非黑非全白（theme 6e7684 命中）
- Test C3（clash 驱动来源）：04_clash 的 results.json `clash_source` 标注 judge 或 rig_fallback；E1 报告记录成功率（预期 judge ≥90%）
- Test C4（冻结泄漏防护）：PARRY/CLASH/EXECUTE 截图后下一 shot 时间栈已恢复（freeze_time_stack == false）
- Test C5（auto_cycle dwell）：任一态停留帧数 == CYCLE_DWELL_FRAMES[state]（settle 不跨态的结构保证）

### Scenario D: 管线 headless 语义与断言（AC2，PRD §7 E3）
- Test D1（分辨率读取）：project.godot viewport 1280x720 → 传给 godot 的 `--resolution` == 1280x720（shandong-wolf）；mini-pong 720x1280 不回归
- Test D2（尺寸断言）：analyze_bmp.py `--size 1280x720` 对 1280x720 PNG 通过、对非标尺寸失败
- Test D3（Movie Maker 对比，E3）：同场景 rig 截图 vs `--write-movie` 输出逐像素一致（若成立，Tier 3 写入管线文档）

### Scenario E: 用户裁决闭环（AC4/AC5，流程验证，非自动化评星）
- Test E1（报告模板完备）：docs/TEST/586 模板含单测/smoke/E2E 三栏 + 6 帧 + 裁决表（帧 × 星 × 意见 × 打回目标）
- Test E2（回填脚本可执行）：裁决意见经 `gh issue edit` 追加到对应 Issue acceptance（人工执行，报告记录回填 commit/时间）
- Test E3（打回链路）：<4 星帧 → 打回目标 issue 清单正确（①→#582 / ②→#574 / ③④→#579 / ⑤→#580 / ⑥→#585+#584）

## 9. 验收条件映射（源自 Issue #586 body）

- [ ] **AC1: e2e_shots.json 含 6 个剧本帧，每条含场景描述/触发条件/期望构图（文字描述）** —— §2.1 e2e_script 组 6 帧 × scene_description/trigger/composition 三字段；Scenario C1（6 帧全产出）
- [ ] **AC2: 自动截图管线可 headless 运行，输出 1280x720 PNG 与 JSON 元数据** —— §3.4 三档语义 + §3.2 分辨率读取 + results.json 元数据透传（缺口 3/5/6 修复）；Scenario B4/C1/D1/D2
- [ ] **AC3: 全部单元测试（状态机/弹反/两条命/AI）与 smoke 测试通过，产出测试报告** —— 18 套件 + smoke 全绿基线（零改动）+ docs/TEST/586 报告；Scenario E1
- [ ] **AC4: 用户对 6 张截图的裁决结果平均分 ≥4 星** —— §2.3 裁决工作流（用户环节）；Scenario E2/E3
- [ ] **AC5: 测试报告记录裁决意见并回填到对应 Issue acceptance** —— §2.3 回填步骤；Scenario E2

## 10. 明确不修改（与 PRD §8 交接红线对齐）

- **不修改** 17 个既有组件脚本（`combat_entity.gd` / `combat_judge.gd` / `enemy_ai.gd` / `hud.gd` / `reaction_controller.gd` / `revive_orchestrator.gd` / `execution_orchestrator.gd` / `player_controller.gd` / `stick_figure_controller.gd` / `atmosphere_controller.gd` / `input_controller.gd` / `combat_states.gd` / `combat_state_table.gd` / `state_machine.gd` / `stick_figure.gd` / `sword_arc.gd` / `main_battle.gd`）——rig 只经公有成员/信号消费；发现缺口 → 回退对应 Issue 修复，禁止绕过
- **不修改** `shandong-wolf/tests/`（run_tests.gd / smoke_test.gd / check_compile.gd / 18 套件）——AC3 只跑通 + 报告，测试套件已是全绿基线
- **不修改** `project.godot`、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`gdscripts/constants.gd`（本 issue 无新常量）
- **不新增** 视觉/音频资产（全部复用程序化组件）；不新增第三方 addon（开源调研 PRD §4.4 结论：不引入 GUT/gdUnit4，复用现管线——implement PR 附调研说明）
- **不写可运行测试文件**（本 issue 只产出 DESIGN/TASKS 文档；测试代码归 implement agent）
- **不评星、不裁决文案、不替用户定稿**——taste 环节（6 帧 1-5 星 + 失败文案候选定稿）归用户；打回目标 issue：视觉类 #582/#574/#579/#580/#583，数值类 #584

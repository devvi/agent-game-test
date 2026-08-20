# Design: [Bug] 打击反馈 execute 事件缺失（E2E 截图链路修复：组级 main_scene 提升 + 多场景拆分 + fb 冻结帧接线）

> **Parent Issue:** #661（bug / workflow/plan / priority/medium / gameplay / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 推荐**方案 A 确认采纳，但范围收窄** —— 代码层指控（矩阵无 execute 键 / _trigger_execute_arc 死代码）已被 #654 修复（stale，PRD §1.1 实证）；真实根因在 **E2E 截图链路**（resolve_plan.py 丢弃组级 `main_scene` override → fb 组 shots 跑错场景 + state 枚举错位）。方案 A 四项子任务中 **main_scene 提升已由 #586 implement（PR #673，OPEN）partial 实现**（`_GROUP_PROMOTED` 增补 4 键 + e2e_capture.gd 数字 state 直比 + 既有断言），本设计聚焦 #673 **未覆盖**的差异化增量：**scene_groups 多场景拆分（resolve_plan 输出 + run-e2e-review.sh 消费）+ 组级 autoplay 提升（fb freeze tweak 数据通道）+ e2e_shots.json fb 组 freeze/auto_cycle 接线 + 回归断言增补**。方案 B（只补冻结不修场景）/ C（归档关闭）显式否决，理由同 PRD §4。
> **Reference PRD:** `docs/PRD/661-execute-feedback-event.md`（research PR #672 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/586-e2e-script-adjudication.md`（§1.2 缺口 1 修复 = 本 issue 地基：`_GROUP_PROMOTED` 增补 main_scene/state_node/state_property/states，implement PR #673 已落地）；`docs/DESIGN/579-combat-feedback-system.md`（§2.6 fb rig 冻结效果帧契约 + fb 三档 shot）；`docs/DESIGN/585-mvp-combat-loop-assembly.md`（e2e 组多场景先例）；`docs/DESIGN/555-e2e-pierce-flaky-seed.md`（E2E 确定性纪律）
> **所有权:** `content_ownership: mechanical`（E2E 解析/拆分/冻结接线 = 机械工程；**用户对 fb_execute 截图的 S 级特效审美裁决是唯一 taste 环节**，agent 禁止评星、禁止替用户裁决）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 5（2 框架核心 + 1 shot plan + 2 测试）+ 6 项实现子任务跨 3 子系统（解析器 / 管线驱动 / shot plan+测试）→ **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，照 #586 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-661，branch `plan/661-execute-feedback-event`）；**#586 implement（PR #673，OPEN）是 main_scene 提升的先行实现** —— 本设计在其之上增量（scene_groups / autoplay 提升），若 #673 先合并则自动 rebase 无缝；**#662（plan PR #674 已合并，implement 未开始）改 `scenes/e2e_feedback_capture.tscn` Backdrop z_index** —— 本 issue **不改 tscn**（fb freeze 走 shot plan tweak 数据通道，零场景文件冲突面）；`mini-pong/` 零影响（其 plan 无组级 main_scene/autoplay，解析默认路径不变）；战斗代码（`shandong-wolf/gdscripts/` 下 reaction_controller.gd / execution_orchestrator.gd / combat_entity.gd 等）**零改动**（PRD 红线）
> **红线:** 只动 E2E 侧 5 文件（见 §3.1）；**绝不触碰** `shandong-wolf/gdscripts/` 下任何战斗代码（#579/#580/#585 交付物为保护文件）；`scenes/e2e_feedback_capture.tscn` 交给 #662（Backdrop z），本 issue 不碰；`project.godot`、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`shandong-wolf/tests/`（run_tests.gd / smoke_test.gd / check_compile.gd 及 18 套件）**不改**；**不写可运行测试文件**（只产出 DESIGN/TASKS 文档 + 测试用例描述）；PR body 用 `Parent #661`（不带冒号）

---

## 1. 架构总览

**问题本质是「战斗代码正确，但 E2E 截图链路的场景选择契约从未生效」。** #654 交付 fb rig（`e2e_feedback_capture.tscn`，含 ReactionController + Camera2D）与 fb 三档 shot（fb_parry_success / fb_stance_break / fb_execute），并按 DESIGN 579 §2.6 在 `e2e_shots.json` feedback 组声明了组级 `main_scene` override；但 `scripts/e2e/resolve_plan.py` 的 `_GROUP_PROMOTED` 白名单自 mini-pong 时代起就不含 `main_scene` → 组级场景 override 在解析时被静默丢弃，顶层 `main_scene`（`e2e_stick_figure_capture.tscn`，#574 火柴人 rig，12 态枚举）始终透传 → fb 组 shots 实际跑在**无 ReactionController 的火柴人 rig** 上，且 state 枚举错位（fb 组按反馈 rig 枚举写 `EXECUTE=3`，火柴人 rig 上 `3 = ATTACK_BURST`）→ fb_execute 截图必然「普通对峙（无反馈）」。

**设计哲学：确定性截图 = 场景正确 + 状态正确 + 时序正确，三者缺一不可。**

1. **场景正确（resolve 层）**——组级 `main_scene` 提升（#673 已实现，本设计沿用并加回归断言）；进一步：**多组激活且 main_scene 不同时，按场景分组拆分**（snow_night + feedback 同跑时，各自 shots 归属各自场景，不互相覆盖）；
2. **状态正确（capture 层）**——数字 state 直比（#673 已实现，fb 组 `state: 1/2/3` 不再永不 ready）；
3. **时序正确（shot plan 层）**——fb 组补 **freeze_effects=true + auto_cycle_frames 调大**（DESIGN 579 §2.6 契约落地）：冻结效果帧停留画面供截图 + settle 期间 auto_cycle 不跨态推进（消除 PRD §1.2「settle 期间 auto_cycle 持续推进」的时序风险）。

```
★ Issue #661 本设计（shandong-wolf E2E 截图链路修复）
┌──────────────────────────────────────────────────────────────────────────┐
│ resolve_plan.py（修改，在 #673 基础上增量）                                  │
│  ├─ _GROUP_PROMOTED += "autoplay"   （组级 autoplay 覆盖顶层，first-wins）  │
│  ├─ 新增 scene_groups 输出            （{main_scene: [shot...]}，多场景拆分  │
│  │                                    的数据基础；单场景时行为不变）         │
│  └─ 保留 #673 的 main_scene/state_node/state_property/states 提升          │
│  run-e2e-review.sh（修改）                                                 │
│  └─ scene_groups 有多个不同 main_scene → 按场景分组生成 sub-plan，           │
│     逐次运行 capture（每场景一个 godot 进程），产物合并；单场景走原路径        │
│  e2e_shots.json（修改）                                                    │
│  └─ feedback 组声明 autoplay: {tweaks: [freeze_effects=true,               │
│     auto_cycle_frames=200]}（DESIGN 579 §2.6 契约 + 时序确定性）            │
│  tests/pipeline/test_e2e_resolve.py（修改）                                │
│  └─ 增补 3 断言：组级 autoplay 提升 / scene_groups 多场景拆分 /              │
│     单场景无 override 行为不变                                              │
│  shandong-wolf/tests/test_reaction_controller.gd（可选修改）               │
│  └─ 真实 ReactionController + StickFigure + SwordArc 端到端断言             │
└──────────────────────────────────────────────────────────────────────────┘
依赖（先行，OPEN 待合并）: PR #673（#586 implement）—— main_scene 提升 + 数字
  state 直比 + TestGroupKeyPromotion 断言，本设计在其之上增量
事件源（只读消费，零修改）: e2e_shots.json 顶层 main_scene / autoplay / states
                        + fb rig（e2e_feedback_capture.gd 的 freeze_effects /
                          auto_cycle 属性，tweak 目标）
消费方（自动接管，零修改）: CaptureRig（e2e_capture.gd 驱动）/ analyze_bmp.py
                        （4 重防伪断言）/ 用户裁决（AC6）
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的消费方式 |
|------|:---:|:---:|------|
| `_GROUP_PROMOTED` 增补 main_scene/state_node/state_property/states（resolve_plan.py） | #586 | ✅ 已实现（PR #673，OPEN） | 沿用；本设计在其上追加 `autoplay` |
| e2e_capture.gd 数字 state 直比（fb 组 `state:1/2/3` 可 ready） | #586 | ✅ 已实现（PR #673，OPEN） | 沿用，零改动 |
| TestGroupKeyPromotion（main_scene/state_node/states 提升断言） | #586 | ✅ 已实现（PR #673，OPEN） | 沿用；本设计在其上增补 autoplay/scene_groups 断言 |
| run-e2e-review.sh P5 分辨率从 project.godot 读取（1280x720） | #586 | ✅ 已实现（PR #673，OPEN） | 沿用；本设计在其上增补场景拆分循环 |
| fb rig（e2e_feedback_capture.gd/.tscn）：freeze_effects / auto_cycle / inject_feedback | #579 | ✅ 已合并（#654） | 属性已齐，**接线缺失** = 本设计 shot plan tweak 目标 |
| e2e_shots.json feedback 组（fb 三档 shot + 组级 main_scene 声明） | #579 | ✅ 已合并（#654） | 组级 main_scene 声明已在（被丢弃的根因载体）；本设计补组级 autoplay |
| 战斗代码（reaction_controller.gd / execution_orchestrator.gd / main_battle.gd） | #579/#580/#585 | ✅ 全绿（1314 单测） | **零改动**（PRD 红线） |

### 1.2 核心缺口与修复决策（本设计新增）

| # | 缺口（codebase 勘探发现） | 修复决策 | 归属 |
|---|--------------------------|---------|------|
| 1 | resolve_plan 只提升单值键；多组激活且 main_scene 不同（snow_night 顶层 stick rig + feedback 组 rig）时，**plan.json 只有一个 main_scene**，另一组 shots 必然跑错场景 | resolve_plan 新增 `scene_groups` 输出：激活组按各自 main_scene（缺省 = 顶层）归类 shots；run-e2e-review.sh 检测 >1 场景时按组拆分多次 capture | **本 issue（#673 未覆盖）** |
| 2 | 组级 `autoplay` 不在 `_GROUP_PROMOTED` → fb 组无法声明自己的 tweak（freeze_effects 无处安放；顶层 autoplay 放 freeze tweak 会对无此属性的 stick rig 报错） | `_GROUP_PROMOTED += ("autoplay",)`（首激活组 wins，与 #673 机制同构）；fb 组声明自己的 autoplay | **本 issue（#673 未覆盖）** |
| 3 | fb 组 shots settle_frames 90-120 vs 顶层 auto_cycle_frames=30 → settle 期间 auto_cycle 持续推进，截图可能落在非特效帧（PRD §1.2 时序风险） | fb 组 autoplay 内 `auto_cycle_frames=200`（> 最大 settle 120）+ `freeze_effects=true`（效果停留）→ settle 期间状态稳定 + 特效滞留画面 | **本 issue（#673 未覆盖）** |
| 4 | 编排器测试用 mock feedback 对象，未覆盖真实 SwordArc 调用链 | 可选：test_reaction_controller.gd 补真实 ReactionController + StickFigure + SwordArc → `trigger_feedback("execute")` → `arc.trigger_burst()` 断言 | 本 issue（可选，PRD §3.1） |

---

## 2. 新组件 — 详细设计

**无新文件**（全部为既有文件修改，PRD §3.2 确认）。本设计的「新组件」是 resolve_plan 的两个**新输出契约**，对消费方（run-e2e-review.sh / e2e_capture.gd）是新增接口：

### 2.1 resolve_plan.py 新输出：`scene_groups`（多场景拆分数据基础，AC4 载体）

- **文件:** `scripts/e2e/resolve_plan.py`（修改）
- **契约:** `resolve()` 返回的 resolved 字典新增 `scene_groups: {main_scene: [shot_dict, ...]}`：
  - 遍历激活组（`groups_activated` 顺序），每组 shots 按其**组级 `main_scene`（若声明）或顶层 `main_scene`（缺省）** 归类；
  - 保持现有单值 `main_scene`/`shots` 输出不变（first-wins 语义，#673 行为，向后兼容）；
  - 单场景时 `scene_groups` 只有 1 个 key → 消费方走原路径，零行为变化（mini-pong 兼容）。
- **关键方法伪代码:**

```python
def resolve(plan: dict, diff_files: list[str]) -> dict:
    activated = select_groups(plan, diff_files)
    resolved = {k: plan[k] for k in _PASSTHROUGH if k in plan}   # #673 既有
    shots, seen = [], set()
    scene_groups: dict = {}          # 本 issue 新增
    top_scene = plan.get("main_scene")   # 缺省场景
    group_promoted = set()
    for gname in activated:
        g = groups.get(gname, {})
        g_scene = g.get("main_scene", top_scene)   # 组级 override 或顶层
        for s in g.get("shots", []):
            name = s.get("name", "")
            if name and name in seen:
                continue
            if name:
                seen.add(name)
            shots.append(s)
            scene_groups.setdefault(g_scene, []).append(s)   # 本 issue 新增
        for k in _GROUP_PROMOTED:      # #673 既有 + autoplay（本 issue）
            if k in g and k not in group_promoted:
                resolved[k] = g[k]
                group_promoted.add(k)
    resolved["shots"] = shots
    resolved["scene_groups"] = scene_groups   # 本 issue 新增
    resolved["groups_activated"] = activated
    return resolved
```

- **集成说明:** `scene_groups` 是**只读契约**，不改变 e2e_capture.gd 的任何输入（capture 仍读 `main_scene`/`shots`/`autoplay`）；拆分发生在 run-e2e-review.sh 层。

### 2.2 resolve_plan.py 新提升键：`autoplay`（fb freeze tweak 数据通道，AC6 载体）

- **文件:** `scripts/e2e/resolve_plan.py`（修改，一行）
- **契约:** `_GROUP_PROMOTED = ("mode", "path", "transcript", "state_trajectory", "fidelity", "main_scene", "state_node", "state_property", "states", "autoplay")` —— 组级 `autoplay` 声明时覆盖顶层（首激活组 wins，与 #673 机制同构）。
- **为什么必须组级:** e2e_capture.gd `_apply_tweaks()` 对 `tweaks[].node` 缺失或 `prop` 不存在会 `printerr` 并跳过（无崩溃但脏日志）；顶层 autoplay 的 tweaks 对所有场景生效 —— 把 freeze tweak 放顶层会在 stick rig（无 `freeze_effects` 属性）上报错。fb 组声明自己的 autoplay 是唯一干净通道。
- **mini-pong 兼容:** mini-pong plan 的组无 autoplay 声明 → 提升不触发 → 顶层 autoplay 透传，行为不变。

---

## 3. 既有组件修改

### 3.1 文件清单总表

| 类别 | 文件 | 变更 | 归属 |
|------|------|------|:---:|
| 修改 | `scripts/e2e/resolve_plan.py` | `_GROUP_PROMOTED += "autoplay"` + `scene_groups` 输出 | 本 issue |
| 修改 | `scripts/run-e2e-review.sh` | scene_groups 多场景拆分循环（>1 场景时按组多次 capture，产物合并） | 本 issue |
| 修改 | `shandong-wolf/e2e_shots.json` | feedback 组声明 `autoplay`（freeze_effects=true + auto_cycle_frames=200） | 本 issue |
| 修改 | `tests/pipeline/test_e2e_resolve.py` | 增补 3 断言：组级 autoplay 提升 / scene_groups 拆分 / 单场景不变 | 本 issue |
| 修改（可选） | `shandong-wolf/tests/test_reaction_controller.gd` | 真实 SwordArc 端到端断言（execute → trigger_burst） | 本 issue |
| 只读 | `framework/templates/e2e_capture.gd` | 零修改（数字 state 直比 #673 已落地；tweak 机制已支持任意 prop） | — |
| 只读 | `scenes/e2e_feedback_capture.tscn` | **零修改**（Backdrop z 归 #662；freeze 走 shot plan tweak） | #662 |

### 3.2 run-e2e-review.sh — scene_groups 多场景拆分（AC4/AC5 核心，本 issue 最大增量）

**现状:** P5 层 resolve_plan → plan.json → 单次 `godot --script capture.gd -- plan.json` → `$OUT/shots/*.png`。

**修改后（伪代码，嵌入 P5 段 resolve 之后、capture 之前）:**

```bash
# resolve_plan.py 产物 plan.json 含 scene_groups
SCENE_COUNT=$(python3 - "$OUT/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
g = p.get("scene_groups", {})
print(len(g))
PY
)
if [ "$SCENE_COUNT" -le 1 ]; then
  # 原路径：单场景单次 capture（行为不变，mini-pong 兼容）
  run_capture "$OUT/plan.json" "$OUT/shots"
else
  # 多场景：按 main_scene 分组生成 sub-plan，逐次 capture，产物合并
  python3 - "$OUT/plan.json" "$OUT" <<'PY'
import json, sys
plan, out = json.load(open(sys.argv[1])), sys.argv[2]
groups = plan["scene_groups"]
for i, (scene, shots) in enumerate(groups.items()):
    sub = dict(plan)
    sub["main_scene"] = scene
    sub["shots"] = shots
    sub["out_dir"] = f"{out}/shots/{i}"        # 每组独立输出目录
    json.dump(sub, open(f"{out}/sub-plan-{i}.json", "w"), indent=2)
PY
  for sub in "$OUT"/sub-plan-*.json; do
    run_capture "$sub" "${sub%.json}"          # 每场景一个 godot 进程
  done
  # 产物合并到 $OUT/shots/（analyze_bmp 断言对合并集运行）
  mkdir -p "$OUT/shots"
  for d in "$OUT"/sub-plan-*/; do cp "$d"*.png "$OUT/shots/"; done
fi
```

- **超时预算:** 每场景独立 `max_wall_seconds`（沿用 plan.json 顶层值）；多场景总墙钟 = Σ 各场景，P5 层 deadline 检查覆盖（失败路径见 §5.3）。
- **产物合并语义:** 各场景 PNG 以 shot name 命名（fb_parry_success 等），跨场景 shot name 天然去重（组名不同）；analyze_bmp 对 `$OUT/shots/` 合并集做 4 重防伪断言（现有逻辑不改）。

### 3.3 e2e_shots.json — feedback 组 autoplay 声明（DESIGN 579 §2.6 契约落地，AC6）

```json
"feedback": {
  "_comment": "#579 打击反馈三档截图供用户裁决（AC2/AC6）：注入 parry_success/stance_broken/execute，冻结效果帧模式捕获同帧四要素。#661: 补组级 autoplay —— freeze_effects=true（DESIGN 579 §2.6 契约）+ auto_cycle_frames=200（> 最大 settle 120，settle 期间不跨态）。",
  "main_scene": "res://scenes/e2e_feedback_capture.tscn",
  "state_node": "/root/CaptureRig",
  "state_property": "current_state",
  "match": ["gdscripts/reaction_controller\.gd", "gdscripts/feedback_spark\.gd", "gdscripts/time_scale_stack\.gd", "gdscripts/screen_shake\.gd", "gdscripts/flash_effect\.gd", "gdscripts/e2e_feedback_capture\.gd", "scenes/e2e_feedback_capture\.tscn"],
  "autoplay": {
    "mode": "capture",
    "tweaks": [
      { "node": "/root/CaptureRig", "prop": "freeze_effects", "value": true },
      { "node": "/root/CaptureRig", "prop": "auto_cycle_frames", "value": 200 }
    ]
  },
  "shots": [
    { "name": "fb_parry_success", "state": 1, "settle_frames": 90, "theme_color": null },
    { "name": "fb_stance_break", "state": 2, "settle_frames": 100, "theme_color": null },
    { "name": "fb_execute", "state": 3, "settle_frames": 120, "theme_color": null }
  ]
}
```

**机制说明:** e2e_capture.gd `_apply_tweaks()` 在场景加载 + 15 帧 settle 后执行 → `/root/CaptureRig.freeze_effects = true`（rig `inject_feedback` 时设置 `_controller.freeze_time_stack = true`，hit-stop 停留）+ `auto_cycle_frames = 200`（rig `_advance_cycle` 每 200 帧推进一态，远大于 fb shot 最大 settle 120 → settle 期间 current_state 稳定，截图必落在特效帧）。

### 3.4 影响分析

| 维度 | 影响 |
|------|------|
| hud / battle_stage / assembly / execution 组 | 同样受「组级 main_scene 丢弃」影响（各自 rig 场景从未生效）；本设计的 scene_groups 拆分（+ #673 提升）一并恢复，无需额外工作 |
| mini-pong E2E | 零影响（plan 无组级 main_scene/autoplay；scene_groups 单 key；拆分分支不触发） |
| 战斗代码 | 零改动（PRD 红线；单测 1314 全绿基线不动） |
| #662（Backdrop z） | 零冲突（本 issue 不碰 e2e_feedback_capture.tscn；#662 不碰 resolve_plan/run-e2e-review） |
| 解析器向后兼容 | scene_groups 是新增键，旧消费方（test_e2e_runner.py fake godot）忽略之；单场景行为逐字节不变 |

---

## 4. 数据流

### Flow 1: fb 组截图正常路径（修复后目标态）

```
e2e_shots.json (feedback 组: main_scene=e2e_feedback_capture.tscn + autoplay freeze)
    │
    ▼
resolve_plan.py ──main_scene 提升（#673）+ scene_groups 输出──► plan.json
    │  (main_scene=e2e_feedback_capture.tscn, autoplay=fb 组声明,
    │   scene_groups={e2e_feedback_capture.tscn: [fb_parry_success, fb_stance_break, fb_execute]})
    ▼
run-e2e-review.sh 检测 scene_groups == 1 场景 → 原路径单次 capture
    ▼
godot --script capture.gd -- plan.json
    │  _apply_tweaks: /root/CaptureRig.freeze_effects=true, auto_cycle_frames=200
    │  auto_cycle: IDLE→PARRY(注入 parry_success)→STANCE→EXECUTE，每 200 帧
    │  shot ready: current_state==1 → settle 90 帧（状态稳定，特效冻结停留）
    ▼
fb_execute.png（S 级特效帧）→ analyze_bmp.py 4 重防伪断言 → 用户裁决（AC6）
```

### Flow 2: 多组激活 + 多场景拆分（snow_night + feedback 同跑）

```
diff 同时命中 snow_night 与 feedback 组 match
    ▼
resolve_plan.py: scene_groups = {
    "res://scenes/e2e_stick_figure_capture.tscn": [snow_night shots],   # 缺省顶层
    "res://scenes/e2e_feedback_capture.tscn":     [fb_parry_success, fb_stance_break, fb_execute],
  }
    ▼
run-e2e-review.sh: SCENE_COUNT=2 → 生成 sub-plan-0/sub-plan-1
    ├─ godot (stick rig)   → sub-plan-0/*.png   （snow_night 截图，12 态枚举）
    └─ godot (fb rig)      → sub-plan-1/*.png   （fb 三档截图，反馈 rig 枚举）
    ▼
产物合并到 $OUT/shots/ → analyze_bmp 合并断言 → 两组截图均正确
```

### Flow 3: 单场景无 override（stick_figure / snow_night 独跑，回归基线）

```
激活组无组级 main_scene → scene_groups 单 key（顶层场景）→ SCENE_COUNT=1
→ 原路径单次 capture → 行为与现状逐字节一致（pipeline 测试兜底）
```

---

## 5. 边界条件与错误处理

| 边界用例 | 缓解 |
|---------|------|
| 多组激活且 main_scene 冲突（snow_night + feedback） | scene_groups 按组归类，拆分多次 capture（Flow 2）；各组 shots 归属各自场景不互相覆盖 |
| 组无 main_scene override（stick_figure / snow_night） | 归入顶层 main_scene；scene_groups 单 key 走原路径（Flow 3）；回归断言覆盖 |
| 多个激活组声明同一 main_scene | scene_groups 同 key 合并（`setdefault` append）；拆分后该场景一次 capture 含两组 shots（去重逻辑沿用 `seen`） |
| fb 组 settle 期间 auto_cycle 推进（时序风险） | fb autoplay `auto_cycle_frames=200` > 最大 settle 120；freeze_effects 停留特效；实现期实验 3 验证截图帧 |
| freeze_effects 对无此属性 rig 生效（顶层 autoplay 误放） | 组级 autoplay 隔离；顶层不放 freeze tweak；`_apply_tweaks` 对缺失 prop 仅 printerr 不崩溃（兜底） |
| e2e_shots.json 顶层 main_scene 未来变更 | 组级 override 语义独立于顶层；fb/hud/battle_stage/assembly 组声明各自 rig，不受顶层变更影响 |
| mini-pong 兼容 | 其 plan 无组级 main_scene/autoplay；scene_groups 单 key；pipeline 测试全绿 |
| 多场景拆分后某组 shots 超时 | 每 sub-plan 独立 max_wall_seconds；deadline 记录 failed_shots；不允许静默跳过（沿用现有 failed 上报） |
| 截图出图但无特效（复现 #661 症状） | analyze_bmp 防伪断言（火花/刀光像素非空）必须拒绝 ——「成功出图」≠「拍到特效帧」 |

---

## 6. 集成点

> **Status 约定:** ⬜ = pending（资源已创建，尚未连接目标）；✅ = connected（implement agent 验证）。implement agent 必须在接线时更新本表。review agent 在合并前验证所有 ⬜ 已解决或显式延期。

| 集成 | 本组件 | 目标 Issue | 方式 | Status |
|------|:---:|:---:|-----|:---:|
| fb 组 autoplay → fb rig | e2e_shots.json feedback 组 autoplay.tweaks | #579 rig | tweak 设置 `/root/CaptureRig.freeze_effects=true` + `auto_cycle_frames=200` | ⬜ pending |
| resolve_plan → run-e2e-review | scene_groups 输出 | 本 issue | plan.json 新键；run-e2e-review.sh 读取并拆分 capture | ⬜ pending |
| resolve_plan → e2e_capture | 组级 autoplay 提升 | #586 | `_GROUP_PROMOTED` 含 autoplay；capture `_apply_tweaks` 消费（已支持） | ⬜ pending |
| fb_execute 截图 → 用户裁决 | fb rig + freeze 接线 | #580 AC6 | E2E 产物经 analyze_bmp 断言后提交用户 1-5 星裁决（agent 不评星） | ⬜ pending |

---

## 7. 实现阶段

| Phase | 优先级 | 组件 | 估算 |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | resolve_plan.py：`_GROUP_PROMOTED += autoplay` + scene_groups 输出 | 0.5d |
| Phase 2 | P0 | test_e2e_resolve.py 增补 3 断言（autoplay 提升 / scene_groups 拆分 / 单场景不变）—— 先写断言锁定契约再实现（TDD） | 0.5d |
| Phase 3 | P0 | run-e2e-review.sh scene_groups 拆分循环（多场景分支 + 产物合并） | 1d |
| Phase 4 | P0 | e2e_shots.json feedback 组 autoplay 声明（freeze_effects + auto_cycle_frames） | 0.2d |
| Phase 5 | P1 | 实验 3 复验：以 reaction_controller.gd 为 diff 跑 run-e2e-review.sh，fb_execute.png 经防伪断言（AC5） | 1d |
| Phase 6 | P2 | （可选）test_reaction_controller.gd 真实 SwordArc 端到端断言 | 0.5d |

依赖顺序: Phase 1 → 2（契约先锁）→ 3（消费方）→ 4（数据）→ 5（验证）。Phase 6 独立可并行。**前置依赖: PR #673 合并**（main_scene 提升 + 数字 state 直比是本设计地基；若 #673 未合并则实现期需先合入其 resolve_plan/e2e_capture 改动 —— 由 worktree-commit.sh 的 merge main 自动处理）。

---

## 8. 测试用例描述

> 只描述测试场景，**不写可运行测试代码**（实现归 implement agent）。既有 1314 单测基线全绿不动。

### Scenario A: resolve_plan.py 组级 autoplay 提升（AC6 回归）
- Test A1（autoplay 提升）: 激活组声明 `autoplay` → resolved["autoplay"] == 组级值；未声明组不引入该键
- Test A2（first-wins）: 多组声明 autoplay → 首激活组 wins（与 #673 TestGroupKeyPromotion 同构）
- Test A3（顶层透传不变）: 组无 autoplay → 顶层 autoplay 原样透传（mini-pong 兼容）

### Scenario B: resolve_plan.py scene_groups 拆分（AC4 回归）
- Test B1（单场景）: 激活组无组级 main_scene → scene_groups 仅 1 key（顶层场景），shots 全部归入
- Test B2（多场景拆分）: snow_night + feedback 同激活 → scene_groups 2 keys，各自 shots 正确归属（fb 组归 e2e_feedback_capture.tscn，snow_night 归顶层）
- Test B3（同场景合并）: 多组声明同一 main_scene → 同 key 合并，shots 去重（seen 语义）
- Test B4（向后兼容）: resolved["main_scene"]/["shots"] 单值输出与 #673 行为逐字节一致

### Scenario C: run-e2e-review.sh 多场景 capture（AC4/AC5，pipeline 级）
- Test C1（单场景原路径）: scene_groups 1 key → 单次 capture 调用，命令参数与现状一致（test_e2e_runner.py fake godot 断言）
- Test C2（多场景拆分）: scene_groups 2 keys → 两次 capture 调用，各 sub-plan 的 main_scene 正确，产物合并到 $OUT/shots/
- Test C3（超时预算）: 任一 sub-plan deadline 超时 → failed_shots 上报，不静默跳过

### Scenario D: fb 冻结帧接线（AC5/AC6）
- Test D1（tweak 生效）: 以 reaction_controller.gd 为 diff → plan.json autoplay 含 freeze_effects=true + auto_cycle_frames=200
- Test D2（fb_execute 特效帧）: E2E 复验 → fb_execute.png 经 analyze_bmp 防伪断言（火花/刀光像素非空、非纯对峙帧）
- Test D3（settle 不跨态）: fb 组任一 shot 的 results.json state 与 shot 期望一致（auto_cycle_frames=200 保证）

### Scenario E（可选）: 真实 SwordArc 端到端
- Test E1: 真实 ReactionController + StickFigure + SwordArc 实例 → `trigger_feedback("execute", {target_entity})` → `SwordArc.trigger_burst()` 被调用（当前编排器测试用 mock，未覆盖真实调用链）

---

## 9. 验收条件映射（源自 Issue #661 body + PRD §5.1）

- [ ] **AC1: 矩阵含 execute 键（代码层已验证）** —— ✅ 已由 #654 满足（reaction_controller.gd:22-23），单测 A1 断言通过；本 issue 不重复
- [ ] **AC2: _trigger_execute_arc 可达（代码层已验证）** —— ✅ 已由 #654 满足（reaction_controller.gd:126），节点路径匹配；本 issue 不重复
- [ ] **AC3: 处决反馈生产调用链闭环（代码层已验证）** —— ✅ 已由 #660/#666 满足（execution_orchestrator.gd:171 + main_battle.gd:111）；本 issue 不重复
- [ ] **AC4: resolve_plan 提升组级 main_scene + 多场景拆分** —— §2.1 scene_groups 输出 + §3.2 run-e2e-review 拆分 + Scenario B/C；main_scene 提升本体由 #673 提供
- [ ] **AC5: fb_execute 截图拍到 S 级特效帧** —— §3.3 freeze 接线 + Phase 5 实验 3 复验 + Scenario D2（analyze_bmp 防伪断言）
- [ ] **AC6: 冻结模式接线** —— §3.3 feedback 组 autoplay 含 freeze_effects=true tweak + Scenario D1

## 10. 明确不修改（与 PRD §8 交接红线对齐）

- **不修改** `shandong-wolf/gdscripts/` 下任何战斗代码（`reaction_controller.gd` / `execution_orchestrator.gd` / `combat_entity.gd` / `combat_judge.gd` / `main_battle.gd` / `sword_arc.gd` / `feedback_spark.gd` / `time_scale_stack.gd` / `screen_shake.gd` / `flash_effect.gd` 等 #579/#580/#585 交付物）—— 本 issue 是纯框架 + shot-plan 修复
- **不修改** `scenes/e2e_feedback_capture.tscn`（Backdrop z 归 #662，implement 未开始；freeze 走 shot plan tweak 数据通道）
- **不修改** `framework/templates/e2e_capture.gd`（数字 state 直比 #673 已落地；tweak 机制已支持任意 prop）
- **不修改** `project.godot`、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`gdscripts/constants.gd`（本 issue 无新常量）
- **不修改** `shandong-wolf/tests/` 的 run_tests.gd / smoke_test.gd / check_compile.gd（18 套件全绿基线不动；仅可选新增 test_reaction_controller.gd 用例）
- **不写可运行测试文件**（本 issue 只产出 DESIGN/TASKS 文档 + 测试用例描述；测试代码归 implement agent）
- **不评星、不裁决审美**——fb_execute 截图的 S 级特效裁决（AC6）是唯一 taste 环节，归用户；agent 禁止自动化通过替代用户裁决
- **不 merge 自己的 PR**（workflow-chain 自动推进；stage-gate.py 校验）

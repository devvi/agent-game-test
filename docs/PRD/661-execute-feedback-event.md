# PRD #661 — [Bug] 打击反馈 execute 事件缺失（FEEDBACK_MATRIX 无 execute，处决刀光死代码）

> **Parent Issue:** #661（bug / workflow/research / priority/medium / gameplay / version/mvp）
> **Agent:** game-research-agent（bug pre-investigation，Patch 8/10）
> **游戏:** shandong-wolf（manifest `game.active`）｜**引擎:** Godot 4.7.1
> **深度:** 无 depth label → standard（§1–6 + §8 必写；§7 因已执行实证实验而保留）
> **日期:** 2026-08-21
> **结论一句话:** 战斗代码层两条指控（矩阵无 execute 键 / _trigger_execute_arc 死代码）在 current main 上**均已不成立**（#654 合并早于 issue 创建）；用户观测到的「E2E rig 截图普通对峙」**真实存在**，根因在 **E2E 截图链路**（resolve_plan.py 丢弃 group 级 main_scene override → fb 组 shots 跑错场景 + state 枚举错位），战斗代码零改动。

---

## 1. 问题定义

### 1.1 预调查结论（bug pre-investigation，Patch 10 — 逐条核对 issue 声明 vs 当前源码 + 实证）

| # | Issue 声称 | 预调查结果 | 证据 |
|---|-----------|-----------|------|
| 1 | FEEDBACK_MATRIX（reaction_controller.gd:22）无 `execute` 键 → trigger_feedback('execute') 走边界 6 | ❌ **Stale — 已修复** | `execute` 键是矩阵**首项**（reaction_controller.gd:22-23，`{"level":"S","spark":true,...}`）；文件唯一提交 f592c7b（#654）合并于 **2026-08-20 12:05:27Z，早于 issue 创建 13:57:50Z** |
| 2 | `_trigger_execute_arc(data)` 在矩阵查表之后 → 死代码，处决刀光无实现路径 | ❌ **Stale — 已修复** | `trigger_feedback` 内 `if event == "execute": _trigger_execute_arc(data)`（reaction_controller.gd:126）可达；节点路径 `StickFigure/TorsoPivot/SwordPivot/SwordArc` 与 player_stick_figure.tscn（PlayerStickFigure→StickFigure→TorsoPivot→SwordPivot→SwordArc，stick_figure.gd:84/141）**精确匹配** |
| 3 | 影响 #580 处决系统：处决反馈无法触发 | ❌ **Stale — 已修复** | 生产调用链已闭环：`execution_orchestrator.gd:171` `_feedback.trigger_feedback("execute", {"target_entity": _enemy})` + `main_battle.gd:111` `execution.bind_feedback(reaction)`（#660，14:26:32Z 合并）；全量单测 **1314 passed / 0 failed**（A1 矩阵完备性含 execute；编排器断言 `trigger_feedback("execute")` 恰一次） |
| 4 | E2E rig inject_feedback('execute') 截图为普通对峙（无反馈） | ✅ **Still broken — 根因在 E2E 截图链路，非战斗代码** | 见 §1.2（resolve_plan 实证 + state 枚举错位） |

### 1.2 真实根因（E2E 截图链路，已实证）

**shot-plan 解析丢弃 group 级 `main_scene` override：**

- `shandong-wolf/e2e_shots.json` 顶层 `main_scene` = `res://scenes/e2e_stick_figure_capture.tscn`（#574 火柴人 rig，12 态枚举）；feedback 组声明了自己的场景 `main_scene: res://scenes/e2e_feedback_capture.tscn`（#579 反馈 rig，含 ReactionController + Camera2D）。
- `scripts/e2e/resolve_plan.py` 的 `_GROUP_PROMOTED = ("mode","path","transcript","state_trajectory","fidelity")` **不含 `main_scene`** → 组级场景 override 在解析时被静默丢弃，顶层 `main_scene` 始终透传。
- **实证（2026-08-21）**：以 `gdscripts/reaction_controller.gd` 作为 diff 输入运行 `resolve_plan.py` → 激活 `snow_night, feedback` 两组，但产物 `main_scene` 仍为 `e2e_stick_figure_capture.tscn`，`shots` 含 fb_parry_success / fb_stance_break / fb_execute。
- **后果**：fb 组三档 shot 实际跑在**无 ReactionController 的火柴人 rig** 上；且 state 枚举错位 —— fb 组按反馈 rig 枚举写 `EXECUTE=3`，在火柴人 rig 上 `3 = ATTACK_BURST`。截图必然不含任何打击反馈特效 → 用户看到的「普通对峙（无反馈）」。
- **时间线佐证**：顶层 `main_scene` 自 e70dcb2（#574）起即为 `e2e_stick_figure_capture.tscn`，其后 7 个提交（含 #654 加入 feedback 组）均未改变 → **feedback 组的场景 override 从未在流水线中生效过**，fb 三档截图从未产出过正确素材。

**次要缺口（DESIGN 契约未落地）**：`docs/DESIGN/579-combat-feedback-system.md` §2.6 明确要求 fb 三档 shot「shot plan 在效果窗口内开启」冻结效果帧模式（`freeze_effects`，让 hit-stop 0.05x 停留、火花/刀光滞留画面供截图）；但 `e2e_shots.json` fb 组无 freeze tweak、`e2e_feedback_capture.tscn` 未设 `freeze_effects=true`。即使场景修对，settle 期间 auto_cycle 持续推进，截图仍有落在非特效帧的时序风险。

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 处决触发（#580 实际游戏路径） | 每局多次 | 玩家崩解后按攻击键 → 处决 → S 级反馈（火花+150ms hit-stop+0.05x 慢动作+刀光）。**当前战斗代码已正常**（编排器→trigger_feedback 全链路单测绿） |
| B | E2E fb_execute 截图（AC6 用户裁决输入） | 每次 E2E 流水线 | 流水线截图必须拍到 S 级特效帧供用户裁决「雪夜+血色+水墨」审美。**当前必失败**（跑错场景 + 无冻结） |
| C | 回归保护 | 未来每次改动 | 任何反馈/处决改动后，E2E 截图与单测共同防回归。当前 fb 组截图是**误导性素材**（无特效却成功出图） |

---

## 2. 设计意图

### 2.1 现状为何存在

| 原因 | 详情 |
|------|------|
| #654 实现期未验证解析链路 | feedback 组按 DESIGN 579 §2.6 正确声明了自己的 rig 场景与 shot，但未实证 resolve_plan.py 是否提升 group 级 main_scene（该文件 `_GROUP_PROMOTED` 白名单自 mini-pong 时代延续，从未包含 main_scene） |
| #613 self-correct 统一顶层场景 | 顶层 `main_scene` 改为火柴人 rig（12 态枚举）以服务 stick/snow_night 组；改后未同步核查其余各组（hud/battle_stage/feedback/assembly）的组级 override 是否仍生效 |
| 单测全绿掩盖链路错位 | 战斗代码契约（矩阵/编排器/节点路径）由 1314 条单测完全覆盖且全绿 → 「代码正确」与「E2E 截图正确」被误认为同一件事；截图链路是独立缺陷面 |

### 2.2 为何现在改

- #661 已把「截图无反馈」记录为 bug，且根因明确指向流水线解析缺陷 —— 不修则 fb 三档截图持续产出误导素材，AC6 用户裁决（#579/#580 审美验收）无法进行。
- #666（#585 组装）已交付可玩闭环，处决是情绪弧最高点（#580 上下文），其反馈截图是 MVP 验收必经项。
- 前置约束：战斗代码零改动（reaction_controller.gd / execution_orchestrator.gd / sword_arc.gd 等 #579/#580 交付物为保护文件）；E2E 框架属 framework 域，可安全修改。

### 2.3 前置约束

| 约束 | 详情 |
|------|------|
| 战斗代码零改动 | 矩阵/编排器/节点路径均已验证正确；本 issue 只修 E2E 链路 |
| 解析器向后兼容 | resolve_plan.py 是 mini-pong 与 shandong-wolf 共用框架，改动不得破坏既有组（stick_figure/snow_night 无组级 main_scene，行为不变） |
| DESIGN 579 §2.6 契约 | fb 三档 shot 必须开启冻结效果帧模式 |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scripts/e2e/resolve_plan.py` | E2E shot-plan 解析 | **修改**：`_GROUP_PROMOTED` 增补 `main_scene`（首激活组优先，无冲突时提升） |
| `scripts/run-e2e-review.sh` | E2E 流水线驱动 | **修改**：当解析产物出现多个不同 main_scene 时，按场景拆分多次 capture 运行（当前单进程单场景） |
| `shandong-wolf/e2e_shots.json` | fb 组 shot 定义 | **修改**（可选）：fb 组 autoplay tweaks 增补 `freeze_effects=true`（对齐 DESIGN 579 §2.6） |
| `scenes/e2e_feedback_capture.tscn` | fb rig 场景 | **修改**（可选）：`ReactionController.freeze_time_stack` 或 rig `freeze_effects` 默认值 |
| `tests/pipeline/test_e2e_resolve.py` | 解析器单测 | **修改**：新增「组级 main_scene 提升 / 多场景冲突拆分」断言（回归保护） |
| `shandong-wolf/tests/test_reaction_controller.gd` | 反馈单测 | **可选**：补「真实 ReactionController + StickFigure + SwordArc → execute 事件触发 trigger_burst()」端到端断言（当前编排器测试用 mock feedback 对象，未覆盖真实 SwordArc 调用） |

### 3.2 新建文件

无（全部为既有文件修改）。

### 3.3 间接影响

| 模块 | 影响 |
|------|------|
| hud / battle_stage / assembly 组 | 同样受「组级 main_scene 丢弃」影响（各自 rig 场景从未生效），修复后自动恢复正确场景 |
| mini-pong E2E | 无影响（其 shot plan 无组级 main_scene override；解析器默认行为不变） |

### 3.4 数据流（修复后目标态）

```
e2e_shots.json (fb 组: main_scene=e2e_feedback_capture.tscn)
    │
    ▼
resolve_plan.py ──main_scene 提升──► plan.json (main_scene=e2e_feedback_capture.tscn)
    │                                    │
    │                                    ▼
    │                          run-e2e-review.sh 按 main_scene 拆分
    │                                    │
    ▼                                    ▼
CaptureRig(e2e_feedback_capture)  ◄──  godot --script capture.gd -- plan.json
    │  auto_cycle: IDLE→PARRY→STANCE→EXECUTE
    │  inject_feedback("execute") → ReactionController.trigger_feedback("execute")
    │      ├──► FeedbackSpark.burst_at(S 级 14 粒)
    │      ├──► TimeScaleStack.push(0.05, 500ms)  ← freeze_effects=true 停留
    │      └──► _trigger_execute_arc → SwordArc.trigger_burst()
    ▼
fb_execute.png（S 级特效帧）→ analyze_bmp.py 4 重防伪断言 → 用户裁决
```

### 3.5 需更新文档

- [ ] `docs/DESIGN/579-combat-feedback-system.md` — 无需改（§2.6 契约本就是目标态；落地即对齐）
- [ ] `scripts/e2e/resolve_plan.py` 头部 docstring — 注明 main_scene 提升语义
- [ ] `framework/templates/e2e_capture.gd` — 无需改（驱动已支持任意 main_scene）

---

## 4. 方案对比

### 方案 A：修复 E2E shot-plan 解析（推荐）

**描述**：根治解析链路 —— resolve_plan.py 将激活组的 `main_scene` 提升进解析产物（首个声明者优先）；run-e2e-review.sh 检测到产物需多场景时，按 main_scene 分组拆分多次 capture 运行（每场景一个 godot 进程，产物合并）；fb 组补 freeze tweak 对齐 DESIGN 579 §2.6；test_e2e_resolve.py 补回归断言；可选补真实 SwordArc 端到端单测。

| 维度 | 评估 |
|------|------|
| Pros | 根因修复；hud/battle_stage/assembly 组同步恢复；fb 截图确定性捕获特效帧；回归测试防再犯；战斗代码零改动 |
| Cons | 涉及框架两文件 + shot plan + 单测，改动面中等；多场景拆分需处理产物合并与超时预算 |
| Risk | **Low**（解析器行为可由单测完全覆盖；默认路径对无 override 的组零影响） |
| Effort | 0.5–1 周 |

### 方案 B：仅补冻结接线，不修场景错位

**描述**：只给 fb 组补 freeze tweak / tscn 属性，不修 resolve_plan 的 main_scene 提升。

| 维度 | 评估 |
|------|------|
| Pros | 改动极小 |
| Cons | 截图仍跑在错误场景（无 ReactionController），freeze 无对象可冻 —— **治标不治本**，fb 截图依旧无反馈 |
| Risk | **High**（问题原样存在，只是多了一次无效改动） |
| Effort | 0.1 周 |

### 方案 C：归档关闭（战斗代码已修复，不补 E2E）

**描述**：PRD 结论「已修复」，直接关闭 #661，E2E 链路缺口记入 backlog。

| 维度 | 评估 |
|------|------|
| Pros | 零改动；issue 的代码级指控确实不成立 |
| Cons | fb 三档截图持续产出误导素材（成功出图但无特效），AC6 用户裁决无正确输入；hud/battle_stage/assembly 组场景 override 问题同样未修 |
| Risk | **Medium**（功能不受影响，但验收证据链断裂，未来回归难定位） |
| Effort | 0 |

### 推荐

**方案 A**。理由：(1) 根因明确且已实证，修复面集中在框架解析层，战斗代码零改动；(2) 一次修复同时恢复 4 个组的正确场景（fb/hud/battle_stage/assembly），性价比最高；(3) 补 freeze + 回归测试后，fb_execute 截图成为 AC6 的确定性验收素材；(4) C 可作为 A 合并后的收尾动作（issue 关闭由 workflow-chain 自动推进，无需手动）。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1: 矩阵含 execute 键（代码层已验证）** — reaction_controller.gd:22-23 存在 `"execute": {"level":"S",...}`；A1 单测断言通过
- [x] **AC2: _trigger_execute_arc 可达（代码层已验证）** — reaction_controller.gd:126 `if event == "execute"` 分支调用；节点路径与场景匹配
- [x] **AC3: 处决反馈生产调用链闭环（代码层已验证）** — execution_orchestrator.gd:171 + main_battle.gd:111 绑定；编排器单测断言 trigger_feedback("execute") 恰一次
- [ ] **AC4: resolve_plan 提升组级 main_scene** — 以 reaction_controller.gd 为 diff 输入，解析产物 main_scene = e2e_feedback_capture.tscn（回归断言）
- [ ] **AC5: fb_execute 截图拍到 S 级特效帧** — 修复后重跑 E2E，fb_execute.png 经 analyze_bmp.py 防伪断言（火花/刀光非空、非纯对峙帧）并提交用户裁决
- [ ] **AC6: 冻结模式接线** — e2e_shots.json fb 组含 freeze_effects=true tweak（或等价机制），settle 期间特效停留画面

### 5.2 边界用例

1. **多组同时激活且 main_scene 冲突**（如 snow_night + feedback）：按 main_scene 分组拆分运行，各组 shots 归属各自场景，不互相覆盖
2. **组无 main_scene override**（stick_figure / snow_night）：行为与现状完全一致（顶层 main_scene 透传），回归断言覆盖
3. **多个激活组声明同一 main_scene**：去重合并为一次运行
4. **fb shot 在冻结模式下 deadline 预算**：0.05x 停留会拉长墙钟时间，max_wall_seconds 需覆盖（实测估算：达 EXECUTE ~11s + settle 120 帧 ~40s < 120s）
5. **e2e_shots.json 顶层 main_scene 未来变更**：组级 override 语义独立于顶层，任何顶层变更不再影响 fb/hud/battle_stage/assembly 组
6. **mini-pong 兼容**：其 plan 无组级 main_scene，解析产物不变，pipeline 测试全绿

### 5.3 失败路径

1. **resolve_plan 产物仍为错误 main_scene**：AC4 回归断言失败 → 解析器修复未生效，禁止合并
2. **多场景拆分后部分组 shots 超时**：deadline 记录 failed_shots，需调 max_wall_seconds 或 per-shot deadline_s，不允许静默跳过
3. **截图出图但无特效（复现 #661 症状）**：防伪断言（analyze_bmp 像素级）必须拒绝 —— 截图"成功出图"不等于"拍到特效帧"

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #654（#579 反馈系统 + fb rig + shot） | ✅ 已合并 | 无 |
| #660（#580 处决系统 + 编排器调用） | ✅ 已合并 | 无 |
| #666（#585 组装，main_battle 绑定） | ✅ 已合并 | 无 |
| `tests/pipeline/test_e2e_resolve.py`（解析器既有单测） | ✅ 存在 | 无（在其上增补断言） |

```
#654 (fb rig+shot) ──► #660 (处决编排器) ──► #666 (组装绑定)
        │                    │                    │
        └──────────┬─────────┴─────────┬──────────┘
                   ▼                   ▼
          #661 本 PRD（E2E 截图链路修复，战斗代码零改动）
```

### 6.2 阻塞

| 未来工作 | 优先级 |
|---------|--------|
| fb_execute 截图用户裁决（AC6，#579 审美验收） | 高（本修复解锁） |
| hud / battle_stage / assembly 组截图复验 | 中（同根因自动恢复） |
| #584 参数定稿后重拍 S 级截图 | 低 |

### 6.3 准备清单

- [ ] 在 worktree 内先跑 `tests/pipeline/test_e2e_resolve.py` 确认基线绿
- [ ] 修改 resolve_plan.py 后以 fb diff 实证解析产物
- [ ] 本地单场景试跑 capture.gd 验证 fb_execute 出图

---

## 7. Spike / 实验（无 depth label → standard；因已执行实证实验而保留）

### 实验 1：resolve_plan 解析实证（✅ 已执行，2026-08-21）

- **问题**：fb 组 main_scene override 是否进入解析产物？
- **方法**：`echo "gdscripts/reaction_controller.gd" > diff.txt && python3 scripts/e2e/resolve_plan.py shandong-wolf/e2e_shots.json diff.txt plan.json`
- **结果**：激活 `snow_night, feedback` 两组、4 shots（含 fb_execute），但 `main_scene` 仍为 `e2e_stick_figure_capture.tscn` —— **override 被丢弃，根因确认**
- **影响**：方案 A 的必要性成立（方案 B 无效的直接证据）

### 实验 2：全量单测（✅ 已执行，2026-08-21）

- **问题**：战斗代码 execute 反馈链路是否健康？
- **方法**：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd`
- **结果**：**1314 passed / 0 failed**（A1 矩阵完备性含 execute；编排器 trigger_feedback("execute") 断言；F2 execute_kill 停摆）
- **影响**：issue 三条代码级指控全部证伪；修复面收缩到 E2E 链路

### 实验 3：修复后 fb_execute 截图复验（建议 implement 期执行）

- **问题**：方案 A 落地后 fb_execute.png 是否拍到 S 级特效帧？
- **方法**：修复 resolve_plan + freeze 接线 → 以 reaction_controller.gd 为 diff 跑 run-e2e-review.sh（L3 visual 层）→ analyze_bmp.py 防伪断言 + 人工目检
- **预期**：火花/刀光像素非空、屏震 offset 非零、hit-stop 时间标签停留
- **影响**：AC5/AC6 验收；若失败则回查 state 枚举映射与 settle 时序

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- **战斗代码（#579/#580/#585 交付物）：全部正确，零改动**。FEEDBACK_MATRIX 含 execute 键（reaction_controller.gd:22）；_trigger_execute_arc 可达且节点路径匹配（:126）；生产调用链 execution_orchestrator.gd:171 + main_battle.gd:111 绑定；单测 1314/0 全绿。
- **E2E 截图链路：存在确定性缺陷**。`scripts/e2e/resolve_plan.py` 的 `_GROUP_PROMOTED` 不含 `main_scene` → feedback（及 hud/battle_stage/assembly）组的组级场景 override 被丢弃；fb 组 shots 跑在无 ReactionController 的 e2e_stick_figure_capture.tscn 上且 state 枚举错位（fb `EXECUTE=3` vs 火柴人 rig `3=ATTACK_BURST`）→ fb_execute 截图必现「普通对峙」。顶层 main_scene 自 e70dcb2 起未变，该缺陷自 #654 引入 fb 组起**从未生效过**。
- **次要缺口**：DESIGN 579 §2.6 要求的冻结效果帧模式未接线（fb 组无 freeze tweak）。

### 主要风险

1. 多组激活时 main_scene 冲突的拆分逻辑（snow_night 与 feedback 同跑时需两组场景各跑一次）—— 拆分粒度与产物合并是主要实现复杂度
2. 冻结模式下 0.05x 停留拉长墙钟，deadline 预算需实测校准（实验 3）
3. 解析器是双游戏共用框架，改动需保证 mini-pong 默认路径零变化（有 pipeline 单测兜底）

### 下一步（plan agent）

1. DESIGN 范围 = 方案 A：resolve_plan.py 提升 `main_scene`（首激活组优先）+ run-e2e-review.sh 按 main_scene 拆分多次 capture + e2e_shots.json fb 组补 `freeze_effects=true` tweak + test_e2e_resolve.py 增补 3 条断言（提升/冲突拆分/无 override 不变）
2. **红线**：禁止触碰 shandong-wolf/gdscripts/ 下任何战斗代码（reaction_controller.gd / execution_orchestrator.gd / combat_entity.gd 等）；本 issue 是纯框架 + shot-plan 修复
3. 验收以实验 3 的 fb_execute.png 防伪断言为准；AC4 回归断言必须先绿
4. 若 implement 期发现 fb 组仍需单独 rig 调试，可临时以 `--script` 直跑 e2e_feedback_capture.tscn 验证 rig 自身行为（不改变流水线结论）
